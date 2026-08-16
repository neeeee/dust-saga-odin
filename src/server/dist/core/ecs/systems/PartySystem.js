"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.PartySystem = void 0;
const crypto_1 = require("crypto");
const shared_1 = require("@dust-saga/shared");
/**
 * Party state with optional Redis write-through cache.
 *
 * Purpose (Phase B4): make party membership/leadership visible across shards
 * without changing any method signature. Every read stays sync (local Map
 * lookup). Every structural mutation fire-and-forgets a Redis HSET + PUBLISH
 * so other shards' local caches converge within milliseconds via the
 * `party:events` pub/sub channel.
 *
 * Loot pools remain per-shard (ephemeral, not persisted) — a known limitation
 * for cross-shard parties that can be addressed in a future phase.
 *
 * When Redis is unavailable the class behaves identically to the pre-sharding
 * implementation (pure in-process Maps).
 */
class PartySystem {
    constructor(opts = {}) {
        this.parties = new Map();
        this.playerParty = new Map();
        this.lootPool = new Map();
        this.syncSub = null;
        this.redis = opts.redis ?? null;
        this.isConnected = opts.isConnected ?? (() => false);
        this.shardId = opts.shardId ?? 'local';
    }
    // ──────────────────────────────────────────────────────────────────────────
    // Lifecycle
    // ──────────────────────────────────────────────────────────────────────────
    /**
     * Subscribe to the cross-shard party sync channel and seed the local cache
     * from Redis. Called once during bootstrap with a dedicated subscribe client
     * (subscribe mode is exclusive in node-redis). No-op when Redis is absent.
     */
    async startSync(subClient) {
        if (!this.canSync() || this.syncSub)
            return;
        this.syncSub = subClient;
        try {
            await this.loadFromRedis();
            await this.syncSub.subscribe('party:events', (raw) => {
                try {
                    const msg = JSON.parse(raw);
                    if (msg.source === this.shardId)
                        return;
                    if (msg.type === 'upsert' && msg.data) {
                        this.applyRemoteUpsert(msg.partyId, msg.data);
                    }
                    else if (msg.type === 'delete') {
                        this.applyRemoteDelete(msg.partyId);
                    }
                }
                catch {
                    // malformed message — drop silently
                }
            });
            console.log(`Party sync active (shard: ${this.shardId})`);
        }
        catch (err) {
            console.warn('[party] failed to start sync:', err);
            this.syncSub = null;
        }
    }
    /** Load all existing parties from Redis into the local cache (on startup). */
    async loadFromRedis() {
        if (!this.canSync())
            return;
        try {
            const all = await this.redis.hGetAll('parties');
            let count = 0;
            for (const [partyId, json] of Object.entries(all)) {
                try {
                    const data = JSON.parse(json);
                    this.parties.set(partyId, data);
                    for (const m of data.members) {
                        this.playerParty.set(m.characterId, partyId);
                    }
                    if (!this.lootPool.has(partyId))
                        this.lootPool.set(partyId, []);
                    count++;
                }
                catch {
                    // skip malformed entry
                }
            }
            if (count > 0)
                console.log(`[party] loaded ${count} parties from Redis`);
        }
        catch (err) {
            console.warn('[party] failed to load from Redis:', err);
        }
    }
    async stopSync() {
        if (this.syncSub) {
            await this.syncSub.quit().catch(() => { });
            this.syncSub = null;
        }
    }
    // ──────────────────────────────────────────────────────────────────────────
    // Mutations (sync return; Redis write is fire-and-forget)
    // ──────────────────────────────────────────────────────────────────────────
    createParty(leaderId, leaderSession, settings) {
        if (this.playerParty.has(leaderId))
            return null;
        const partyId = `party_${(0, crypto_1.randomUUID)()}`;
        const leader = {
            characterId: leaderId,
            characterName: leaderSession.characterName,
            level: leaderSession.stats.level,
            jobId: leaderSession.jobId,
            health: leaderSession.stats.health,
            maxHealth: leaderSession.stats.maxHealth,
            isLeader: true,
            zoneId: leaderSession.zoneId,
        };
        const party = {
            partyId,
            leaderId,
            members: [leader],
            settings,
        };
        this.parties.set(partyId, party);
        this.playerParty.set(leaderId, partyId);
        this.lootPool.set(partyId, []);
        this.syncToRedis(partyId);
        return party;
    }
    joinParty(partyId, characterId, session) {
        const party = this.parties.get(partyId);
        if (!party)
            return null;
        if (this.playerParty.has(characterId))
            return null;
        if (party.members.length >= shared_1.MAX_PARTY_SIZE)
            return null;
        if (party.settings.visibility === shared_1.PartyVisibility.PRIVATE) {
            return null;
        }
        const member = {
            characterId,
            characterName: session.characterName,
            level: session.stats.level,
            jobId: session.jobId,
            health: session.stats.health,
            maxHealth: session.stats.maxHealth,
            isLeader: false,
            zoneId: session.zoneId,
        };
        party.members.push(member);
        this.playerParty.set(characterId, partyId);
        this.syncToRedis(partyId);
        return party;
    }
    joinByInvite(partyId, characterId, session) {
        const party = this.parties.get(partyId);
        if (!party)
            return null;
        if (this.playerParty.has(characterId))
            return null;
        if (party.members.length >= shared_1.MAX_PARTY_SIZE)
            return null;
        const member = {
            characterId,
            characterName: session.characterName,
            level: session.stats.level,
            jobId: session.jobId,
            health: session.stats.health,
            maxHealth: session.stats.maxHealth,
            isLeader: false,
            zoneId: session.zoneId,
        };
        party.members.push(member);
        this.playerParty.set(characterId, partyId);
        this.syncToRedis(partyId);
        return party;
    }
    leaveParty(characterId) {
        const partyId = this.playerParty.get(characterId);
        if (!partyId)
            return null;
        const party = this.parties.get(partyId);
        if (!party)
            return null;
        party.members = party.members.filter(m => m.characterId !== characterId);
        this.playerParty.delete(characterId);
        let newLeader;
        if (party.members.length === 0) {
            this.parties.delete(partyId);
            this.lootPool.delete(partyId);
            this.syncDeleteFromRedis(partyId);
            return { party, removedId: characterId };
        }
        if (party.leaderId === characterId) {
            party.leaderId = party.members[0].characterId;
            party.members[0].isLeader = true;
            newLeader = party.leaderId;
        }
        this.syncToRedis(partyId);
        return { party, removedId: characterId, newLeader };
    }
    kickMember(leaderId, targetId) {
        const partyId = this.playerParty.get(leaderId);
        if (!partyId)
            return null;
        const party = this.parties.get(partyId);
        if (!party || party.leaderId !== leaderId)
            return null;
        if (leaderId === targetId)
            return null;
        const isMember = party.members.some(m => m.characterId === targetId);
        if (!isMember)
            return null;
        party.members = party.members.filter(m => m.characterId !== targetId);
        this.playerParty.delete(targetId);
        this.syncToRedis(partyId);
        return { party, removedId: targetId };
    }
    promoteLeader(leaderId, targetId) {
        const partyId = this.playerParty.get(leaderId);
        if (!partyId)
            return null;
        const party = this.parties.get(partyId);
        if (!party || party.leaderId !== leaderId)
            return null;
        const target = party.members.find(m => m.characterId === targetId);
        if (!target)
            return null;
        const oldLeader = party.members.find(m => m.characterId === leaderId);
        if (oldLeader)
            oldLeader.isLeader = false;
        target.isLeader = true;
        party.leaderId = targetId;
        this.syncToRedis(partyId);
        return party;
    }
    updateMemberStats(characterId, session) {
        const partyId = this.playerParty.get(characterId);
        if (!partyId)
            return;
        const party = this.parties.get(partyId);
        if (!party)
            return;
        const member = party.members.find(m => m.characterId === characterId);
        if (!member)
            return;
        member.level = session.stats.level;
        member.health = session.stats.health;
        member.maxHealth = session.stats.maxHealth;
        member.jobId = session.jobId;
        member.zoneId = session.zoneId;
        this.syncToRedis(partyId);
    }
    removeParty(partyId) {
        const party = this.parties.get(partyId);
        if (!party)
            return;
        for (const m of party.members) {
            this.playerParty.delete(m.characterId);
        }
        this.parties.delete(partyId);
        this.lootPool.delete(partyId);
        this.syncDeleteFromRedis(partyId);
    }
    handleDisconnect(characterId) {
        return this.leaveParty(characterId);
    }
    // ──────────────────────────────────────────────────────────────────────────
    // Reads (always sync — local cache)
    // ──────────────────────────────────────────────────────────────────────────
    getPartyForMember(characterId) {
        const partyId = this.playerParty.get(characterId);
        if (!partyId)
            return null;
        return this.parties.get(partyId) || null;
    }
    getPartyForMemberOf(targetCharacterId) {
        const partyId = this.playerParty.get(targetCharacterId);
        if (!partyId)
            return null;
        return this.parties.get(partyId) || null;
    }
    getPartyData(partyId) {
        return this.parties.get(partyId) || null;
    }
    isPartyLeader(characterId) {
        const party = this.getPartyForMember(characterId);
        return party?.leaderId === characterId;
    }
    getPartyMembers(characterId) {
        const party = this.getPartyForMember(characterId);
        if (!party)
            return [];
        return party.members.map(m => m.characterId);
    }
    getMaxPartySize() {
        return shared_1.MAX_PARTY_SIZE;
    }
    // ──────────────────────────────────────────────────────────────────────────
    // Loot pool management moved to LootSystem (partyPools map).
    // PartySystem no longer owns loot state — it just broadcasts updates.
    // ──────────────────────────────────────────────────────────────────────────
    /** Clear party-owned loot state when the party disbands. */
    clearLootState(partyId) {
        // delegate handled by LootSystem.clearParty via NetworkServer
    }
    // ──────────────────────────────────────────────────────────────────────────
    // Redis sync (fire-and-forget)
    // ──────────────────────────────────────────────────────────────────────────
    syncToRedis(partyId) {
        if (!this.canSync())
            return;
        const party = this.parties.get(partyId);
        if (!party)
            return;
        void (async () => {
            try {
                const msg = { type: 'upsert', partyId, data: party, source: this.shardId };
                await this.redis.hSet('parties', partyId, JSON.stringify(party));
                await this.redis.publish('party:events', JSON.stringify(msg));
            }
            catch (err) {
                console.warn(`[party] sync failed for ${partyId}:`, err);
            }
        })();
    }
    syncDeleteFromRedis(partyId) {
        if (!this.canSync())
            return;
        void (async () => {
            try {
                const msg = { type: 'delete', partyId, source: this.shardId };
                await this.redis.hDel('parties', partyId);
                await this.redis.publish('party:events', JSON.stringify(msg));
            }
            catch (err) {
                console.warn(`[party] delete-sync failed for ${partyId}:`, err);
            }
        })();
    }
    /** Apply a party upsert received from another shard. */
    applyRemoteUpsert(partyId, data) {
        const old = this.parties.get(partyId);
        const oldIds = old ? new Set(old.members.map(m => m.characterId)) : new Set();
        this.parties.set(partyId, data);
        for (const m of data.members) {
            this.playerParty.set(m.characterId, partyId);
            oldIds.delete(m.characterId);
        }
        for (const leftId of oldIds) {
            this.playerParty.delete(leftId);
        }
        if (!this.lootPool.has(partyId))
            this.lootPool.set(partyId, []);
    }
    /** Apply a party delete received from another shard. */
    applyRemoteDelete(partyId) {
        const party = this.parties.get(partyId);
        if (party) {
            for (const m of party.members) {
                this.playerParty.delete(m.characterId);
            }
        }
        this.parties.delete(partyId);
        this.lootPool.delete(partyId);
    }
    canSync() {
        return this.redis !== null && this.isConnected();
    }
}
exports.PartySystem = PartySystem;
