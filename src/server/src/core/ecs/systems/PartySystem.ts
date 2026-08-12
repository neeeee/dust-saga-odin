import { randomUUID } from 'crypto';
import type { RedisClientType } from 'redis';
import {
  PartyData, PartyMember, PartySettings, PartyVisibility,
  LootRule, PartyLootItem, MAX_PARTY_SIZE, MAX_LOOT_POOL,
  PlayerSession, JOB_DEFINITIONS
} from '@dust-saga/shared';

/** Pub/sub message for cross-shard party cache sync. */
interface PartySyncMessage {
  type: 'upsert' | 'delete';
  partyId: string;
  data?: PartyData;
  source: string;
}

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
export class PartySystem {
  private parties: Map<string, PartyData> = new Map();
  private playerParty: Map<string, string> = new Map();
  private lootPool: Map<string, PartyLootItem[]> = new Map();

  private readonly redis: RedisClientType | null;
  private readonly isConnected: () => boolean;
  private readonly shardId: string;
  private syncSub: RedisClientType | null = null;

  constructor(opts: { redis?: RedisClientType | null; isConnected?: () => boolean; shardId?: string } = {}) {
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
  async startSync(subClient: RedisClientType): Promise<void> {
    if (!this.canSync() || this.syncSub) return;
    this.syncSub = subClient;
    try {
      await this.loadFromRedis();
      await this.syncSub.subscribe('party:events', (raw: string) => {
        try {
          const msg: PartySyncMessage = JSON.parse(raw);
          if (msg.source === this.shardId) return;
          if (msg.type === 'upsert' && msg.data) {
            this.applyRemoteUpsert(msg.partyId, msg.data);
          } else if (msg.type === 'delete') {
            this.applyRemoteDelete(msg.partyId);
          }
        } catch {
          // malformed message — drop silently
        }
      });
      console.log(`Party sync active (shard: ${this.shardId})`);
    } catch (err) {
      console.warn('[party] failed to start sync:', err);
      this.syncSub = null;
    }
  }

  /** Load all existing parties from Redis into the local cache (on startup). */
  async loadFromRedis(): Promise<void> {
    if (!this.canSync()) return;
    try {
      const all = await this.redis!.hGetAll('parties');
      let count = 0;
      for (const [partyId, json] of Object.entries(all)) {
        try {
          const data: PartyData = JSON.parse(json);
          this.parties.set(partyId, data);
          for (const m of data.members) {
            this.playerParty.set(m.characterId, partyId);
          }
          if (!this.lootPool.has(partyId)) this.lootPool.set(partyId, []);
          count++;
        } catch {
          // skip malformed entry
        }
      }
      if (count > 0) console.log(`[party] loaded ${count} parties from Redis`);
    } catch (err) {
      console.warn('[party] failed to load from Redis:', err);
    }
  }

  async stopSync(): Promise<void> {
    if (this.syncSub) {
      await this.syncSub.quit().catch(() => {});
      this.syncSub = null;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Mutations (sync return; Redis write is fire-and-forget)
  // ──────────────────────────────────────────────────────────────────────────

  createParty(
    leaderId: string,
    leaderSession: PlayerSession,
    settings: PartySettings
  ): PartyData | null {
    if (this.playerParty.has(leaderId)) return null;

    const partyId = `party_${randomUUID()}`;
    const leader: PartyMember = {
      characterId: leaderId,
      characterName: leaderSession.characterName,
      level: leaderSession.stats.level,
      jobId: leaderSession.jobId,
      health: leaderSession.stats.health,
      maxHealth: leaderSession.stats.maxHealth,
      isLeader: true,
      zoneId: leaderSession.zoneId,
    };

    const party: PartyData = {
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

  joinParty(
    partyId: string,
    characterId: string,
    session: PlayerSession
  ): PartyData | null {
    const party = this.parties.get(partyId);
    if (!party) return null;
    if (this.playerParty.has(characterId)) return null;
    if (party.members.length >= MAX_PARTY_SIZE) return null;

    if (party.settings.visibility === PartyVisibility.PRIVATE) {
      return null;
    }

    const member: PartyMember = {
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

  joinByInvite(
    partyId: string,
    characterId: string,
    session: PlayerSession
  ): PartyData | null {
    const party = this.parties.get(partyId);
    if (!party) return null;
    if (this.playerParty.has(characterId)) return null;
    if (party.members.length >= MAX_PARTY_SIZE) return null;

    const member: PartyMember = {
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

  leaveParty(characterId: string): { party: PartyData; removedId: string; newLeader?: string } | null {
    const partyId = this.playerParty.get(characterId);
    if (!partyId) return null;

    const party = this.parties.get(partyId);
    if (!party) return null;

    party.members = party.members.filter(m => m.characterId !== characterId);
    this.playerParty.delete(characterId);

    let newLeader: string | undefined;
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

  kickMember(leaderId: string, targetId: string): { party: PartyData; removedId: string } | null {
    const partyId = this.playerParty.get(leaderId);
    if (!partyId) return null;

    const party = this.parties.get(partyId);
    if (!party || party.leaderId !== leaderId) return null;
    if (leaderId === targetId) return null;

    const isMember = party.members.some(m => m.characterId === targetId);
    if (!isMember) return null;

    party.members = party.members.filter(m => m.characterId !== targetId);
    this.playerParty.delete(targetId);

    this.syncToRedis(partyId);
    return { party, removedId: targetId };
  }

  promoteLeader(leaderId: string, targetId: string): PartyData | null {
    const partyId = this.playerParty.get(leaderId);
    if (!partyId) return null;

    const party = this.parties.get(partyId);
    if (!party || party.leaderId !== leaderId) return null;

    const target = party.members.find(m => m.characterId === targetId);
    if (!target) return null;

    const oldLeader = party.members.find(m => m.characterId === leaderId);
    if (oldLeader) oldLeader.isLeader = false;
    target.isLeader = true;
    party.leaderId = targetId;

    this.syncToRedis(partyId);
    return party;
  }

  updateMemberStats(characterId: string, session: PlayerSession): void {
    const partyId = this.playerParty.get(characterId);
    if (!partyId) return;

    const party = this.parties.get(partyId);
    if (!party) return;

    const member = party.members.find(m => m.characterId === characterId);
    if (!member) return;

    member.level = session.stats.level;
    member.health = session.stats.health;
    member.maxHealth = session.stats.maxHealth;
    member.jobId = session.jobId;
    member.zoneId = session.zoneId;

    this.syncToRedis(partyId);
  }

  removeParty(partyId: string): void {
    const party = this.parties.get(partyId);
    if (!party) return;

    for (const m of party.members) {
      this.playerParty.delete(m.characterId);
    }
    this.parties.delete(partyId);
    this.lootPool.delete(partyId);
    this.syncDeleteFromRedis(partyId);
  }

  handleDisconnect(characterId: string): { party: PartyData; removedId: string; newLeader?: string } | null {
    return this.leaveParty(characterId);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Reads (always sync — local cache)
  // ──────────────────────────────────────────────────────────────────────────

  getPartyForMember(characterId: string): PartyData | null {
    const partyId = this.playerParty.get(characterId);
    if (!partyId) return null;
    return this.parties.get(partyId) || null;
  }

  getPartyForMemberOf(targetCharacterId: string): PartyData | null {
    const partyId = this.playerParty.get(targetCharacterId);
    if (!partyId) return null;
    return this.parties.get(partyId) || null;
  }

  getPartyData(partyId: string): PartyData | null {
    return this.parties.get(partyId) || null;
  }

  isPartyLeader(characterId: string): boolean {
    const party = this.getPartyForMember(characterId);
    return party?.leaderId === characterId;
  }

  getPartyMembers(characterId: string): string[] {
    const party = this.getPartyForMember(characterId);
    if (!party) return [];
    return party.members.map(m => m.characterId);
  }

  getMaxPartySize(): number {
    return MAX_PARTY_SIZE;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Loot pool management moved to LootSystem (partyPools map).
  // PartySystem no longer owns loot state — it just broadcasts updates.
  // ──────────────────────────────────────────────────────────────────────────

  /** Clear party-owned loot state when the party disbands. */
  clearLootState(partyId: string): void {
    // delegate handled by LootSystem.clearParty via NetworkServer
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Redis sync (fire-and-forget)
  // ──────────────────────────────────────────────────────────────────────────

  private syncToRedis(partyId: string): void {
    if (!this.canSync()) return;
    const party = this.parties.get(partyId);
    if (!party) return;
    void (async () => {
      try {
        const msg: PartySyncMessage = { type: 'upsert', partyId, data: party, source: this.shardId };
        await this.redis!.hSet('parties', partyId, JSON.stringify(party));
        await this.redis!.publish('party:events', JSON.stringify(msg));
      } catch (err) {
        console.warn(`[party] sync failed for ${partyId}:`, err);
      }
    })();
  }

  private syncDeleteFromRedis(partyId: string): void {
    if (!this.canSync()) return;
    void (async () => {
      try {
        const msg: PartySyncMessage = { type: 'delete', partyId, source: this.shardId };
        await this.redis!.hDel('parties', partyId);
        await this.redis!.publish('party:events', JSON.stringify(msg));
      } catch (err) {
        console.warn(`[party] delete-sync failed for ${partyId}:`, err);
      }
    })();
  }

  /** Apply a party upsert received from another shard. */
  private applyRemoteUpsert(partyId: string, data: PartyData): void {
    const old = this.parties.get(partyId);
    const oldIds = old ? new Set(old.members.map(m => m.characterId)) : new Set<string>();

    this.parties.set(partyId, data);
    for (const m of data.members) {
      this.playerParty.set(m.characterId, partyId);
      oldIds.delete(m.characterId);
    }
    for (const leftId of oldIds) {
      this.playerParty.delete(leftId);
    }
    if (!this.lootPool.has(partyId)) this.lootPool.set(partyId, []);
  }

  /** Apply a party delete received from another shard. */
  private applyRemoteDelete(partyId: string): void {
    const party = this.parties.get(partyId);
    if (party) {
      for (const m of party.members) {
        this.playerParty.delete(m.characterId);
      }
    }
    this.parties.delete(partyId);
    this.lootPool.delete(partyId);
  }

  private canSync(): boolean {
    return this.redis !== null && this.isConnected();
  }
}
