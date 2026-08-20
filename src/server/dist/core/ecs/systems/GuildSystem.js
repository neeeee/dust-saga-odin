"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.GuildSystem = void 0;
const shared_1 = require("@dust-saga/shared");
const DatabaseManager_1 = require("../../database/DatabaseManager");
/**
 * Guilds: Postgres-persisted (guilds + guild_members), cached in memory.
 * Ranks are a fixed set (leader/officer/member/recruit) whose permission
 * flags the leader can tune; the bank holds gold + stacked items; kills by
 * members feed guild XP. All mutations broadcast GUILD_UPDATE to online
 * members and keep session.guildTag/guildRank mirrors in sync for spawn
 * packets (nameplate tags).
 */
class GuildSystem {
    constructor(deps) {
        this.deps = deps;
        this.guilds = new Map();
        this.memberGuild = new Map(); // characterId → guildId
        /** Persisted member rows joined with live-session state. */
        this.memberRows = new Map();
        this.db = DatabaseManager_1.DatabaseManager.getInstance();
    }
    // ── lookups ───────────────────────────────────────────────────────────────
    getGuildForMember(characterId) {
        const guildId = this.memberGuild.get(characterId);
        return guildId ? this.guilds.get(guildId) || null : null;
    }
    getMemberRank(characterId) {
        const guild = this.getGuildForMember(characterId);
        if (!guild)
            return null;
        const member = this.membersOf(guild).find(m => m.characterId === characterId);
        return member ? member.rank : null;
    }
    permissionsOf(guild, rank) {
        return { ...shared_1.DEFAULT_GUILD_PERMISSIONS[rank], ...(guild.rankPerms?.[rank] || {}) };
    }
    membersOf(guild) {
        let rows = this.memberRows.get(guild.guildId);
        if (!rows) {
            rows = [];
            this.memberRows.set(guild.guildId, rows);
        }
        return rows;
    }
    // ── load / login ──────────────────────────────────────────────────────────
    /** Load a character's guild (if any) from DB into cache; sync session mirror. */
    async loadForCharacter(session) {
        if (!this.db.postgres)
            return;
        try {
            const res = await this.db.postgres.query(`SELECT g.id, g.name, g.tag, g.leader_id, g.level, g.experience, g.gold,
                g.bank_items, g.rank_perms, g.motd, m.rank
         FROM guild_members m JOIN guilds g ON g.id = m.guild_id
         WHERE m.character_id = $1`, [session.characterId]);
            if (res.rows.length === 0) {
                session.guildId = null;
                session.guildTag = null;
                session.guildRank = null;
                return;
            }
            const row = res.rows[0];
            const guild = await this.loadGuild(row.id);
            if (!guild)
                return;
            this.memberGuild.set(session.characterId, guild.guildId);
            this.upsertMemberRow(guild.guildId, {
                characterId: session.characterId,
                rank: (0, shared_1.isGuildRank)(row.rank) ? row.rank : 'member',
                name: session.characterName,
                level: session.stats.level,
                jobId: session.jobId || '',
            });
            this.syncSession(session, guild, row.rank);
            await this.sendGuildUpdate(guild.guildId, session.characterId);
            if (guild.motd) {
                this.deps.sendToPlayer(session.characterId, {
                    type: shared_1.PacketType.CHAT_MESSAGE,
                    timestamp: Date.now(),
                    data: { sender: 'Guild', message: `MOTD: ${guild.motd}`, channel: 'guild' },
                });
            }
        }
        catch (error) {
            console.error('[GuildSystem] loadForCharacter failed:', error);
        }
    }
    async loadGuild(guildId) {
        const cached = this.guilds.get(guildId);
        if (cached)
            return cached;
        if (!this.db.postgres)
            return null;
        try {
            const res = await this.db.postgres.query('SELECT * FROM guilds WHERE id = $1', [guildId]);
            if (res.rows.length === 0)
                return null;
            const guild = this.rowToGuild(res.rows[0]);
            this.guilds.set(guildId, guild);
            const members = await this.db.postgres.query(`SELECT m.character_id, m.rank, c.name, c.level, c.job_id
         FROM guild_members m JOIN characters c ON c.id = m.character_id
         WHERE m.guild_id = $1`, [guildId]);
            const rows = members.rows.map((r) => ({
                characterId: r.character_id,
                rank: (0, shared_1.isGuildRank)(r.rank) ? r.rank : 'member',
                name: r.name,
                level: r.level,
                jobId: r.job_id || '',
            }));
            this.memberRows.set(guildId, rows);
            return guild;
        }
        catch (error) {
            console.error('[GuildSystem] loadGuild failed:', error);
            return null;
        }
    }
    rowToGuild(row) {
        const bankItems = row.bank_items
            ? (typeof row.bank_items === 'string' ? JSON.parse(row.bank_items) : row.bank_items)
            : [];
        let rankPerms = {};
        if (row.rank_perms) {
            rankPerms = typeof row.rank_perms === 'string' ? JSON.parse(row.rank_perms) : row.rank_perms;
        }
        return {
            guildId: row.id,
            name: row.name,
            tag: row.tag,
            leaderId: row.leader_id,
            level: row.level || 1,
            experience: Number(row.experience) || 0,
            gold: Number(row.gold) || 0,
            bankItems: Array.isArray(bankItems) ? bankItems : [],
            rankPerms,
            motd: row.motd || '',
        };
    }
    syncSession(session, guild, rank) {
        session.guildId = guild.guildId;
        session.guildTag = guild.tag;
        session.guildRank = (0, shared_1.isGuildRank)(rank) ? rank : 'member';
        this.broadcastTag(session);
    }
    /**
     * Push this player's current guild tag to everyone in their zone so
     * nameplates ("Name [TAG]") update in real time. Call after any membership
     * change (join/leave/kick/disband/create); also safe with a null tag, which
     * clears remote nameplates.
     */
    broadcastTag(session) {
        this.deps.broadcastInZone(session.zoneId, {
            type: shared_1.PacketType.ENTITY_GUILD_TAG,
            timestamp: Date.now(),
            data: { entityId: session.characterId, guildTag: session.guildTag || '' },
        });
    }
    upsertMemberRow(guildId, row) {
        const rows = this.memberRows.get(guildId);
        if (!rows) {
            this.memberRows.set(guildId, [row]);
            return;
        }
        const i = rows.findIndex(m => m.characterId === row.characterId);
        if (i >= 0)
            rows[i] = row;
        else
            rows.push(row);
    }
    removeMemberRow(guildId, characterId) {
        const rows = this.memberRows.get(guildId);
        if (!rows)
            return;
        const i = rows.findIndex(m => m.characterId === characterId);
        if (i >= 0)
            rows.splice(i, 1);
    }
    // ── GUILD_UPDATE broadcast ────────────────────────────────────────────────
    buildUpdateFor(guild, forCharacterId) {
        const myRow = this.membersOf(guild).find(m => m.characterId === forCharacterId);
        const myRank = myRow ? myRow.rank : 'recruit';
        const members = this.membersOf(guild).map(m => {
            const session = this.deps.getPlayers().get(m.characterId);
            return {
                characterId: m.characterId,
                name: session ? session.characterName : m.name,
                level: session ? session.stats.level : m.level,
                jobId: session ? (session.jobId || '') : m.jobId,
                rank: m.rank,
                online: !!session,
            };
        });
        const perms = {};
        for (const rank of shared_1.GUILD_RANKS) {
            perms[rank] = this.permissionsOf(guild, rank);
        }
        return {
            guildId: guild.guildId,
            name: guild.name,
            tag: guild.tag,
            leaderId: guild.leaderId,
            level: guild.level,
            experience: guild.experience,
            xpToNext: (0, shared_1.guildXpToNext)(guild.level),
            motd: guild.motd,
            gold: guild.gold,
            bankItems: guild.bankItems.map(b => ({
                itemId: b.itemId,
                itemName: this.deps.getItemName(b.itemId),
                quantity: b.quantity,
            })),
            members,
            myRank,
            rankPerms: perms,
        };
    }
    async sendGuildUpdate(guildId, onlyCharacterId) {
        const guild = this.guilds.get(guildId);
        if (!guild)
            return;
        const targets = onlyCharacterId
            ? [onlyCharacterId]
            : this.membersOf(guild).map(m => m.characterId);
        for (const characterId of targets) {
            if (!this.deps.getPlayers().get(characterId))
                continue;
            this.deps.sendToPlayer(characterId, {
                type: shared_1.PacketType.GUILD_UPDATE,
                timestamp: Date.now(),
                data: this.buildUpdateFor(guild, characterId),
            });
        }
    }
    notify(guildId, message) {
        const guild = this.guilds.get(guildId);
        if (!guild)
            return;
        for (const m of this.membersOf(guild)) {
            if (this.deps.getPlayers().get(m.characterId)) {
                this.deps.sendToPlayer(m.characterId, {
                    type: shared_1.PacketType.CHAT_MESSAGE,
                    timestamp: Date.now(),
                    data: { sender: 'Guild', message, channel: 'guild' },
                });
            }
        }
    }
    // ── mutations ─────────────────────────────────────────────────────────────
    /** Create a guild; the creator becomes leader. DB-down → error message. */
    async createGuild(session, name, tag) {
        const cleanName = (name || '').trim().substring(0, shared_1.GUILD_NAME_MAX);
        const cleanTag = (tag || '').trim().toUpperCase().substring(0, shared_1.GUILD_TAG_MAX);
        if (!this.db.postgres) {
            this.error(session.characterId, 'Guilds require the database.');
            return;
        }
        if (cleanName.length < 3 || cleanTag.length < 2) {
            this.error(session.characterId, 'Guild name needs 3+ chars and tag 2+ chars.');
            return;
        }
        if (this.getGuildForMember(session.characterId)) {
            this.error(session.characterId, 'You are already in a guild.');
            return;
        }
        try {
            const dupe = await this.db.postgres.query('SELECT id FROM guilds WHERE LOWER(name) = LOWER($1) OR UPPER(tag) = $2 LIMIT 1', [cleanName, cleanTag]);
            if (dupe.rows.length > 0) {
                this.error(session.characterId, 'A guild with that name or tag already exists.');
                return;
            }
            const created = await this.db.postgres.query('INSERT INTO guilds (name, tag, leader_id) VALUES ($1, $2, $3) RETURNING id', [cleanName, cleanTag, session.characterId]);
            const guildId = created.rows[0].id;
            await this.db.postgres.query('INSERT INTO guild_members (guild_id, character_id, rank) VALUES ($1, $2, $3)', [guildId, session.characterId, 'leader']);
            const guild = await this.loadGuild(guildId);
            if (!guild)
                return;
            this.memberGuild.set(session.characterId, guildId);
            this.syncSession(session, guild, 'leader');
            this.deps.sendToPlayer(session.characterId, {
                type: shared_1.PacketType.NOTIFICATION,
                timestamp: Date.now(),
                data: { message: `Guild "${cleanName}" [${cleanTag}] created.`, type: 'success' },
            });
            await this.sendGuildUpdate(guildId);
        }
        catch (error) {
            console.error('[GuildSystem] createGuild failed:', error);
            this.error(session.characterId, 'Could not create the guild.');
        }
    }
    /** Disband: leader only, everyone removed. */
    async disbandGuild(session) {
        const guild = this.getGuildForMember(session.characterId);
        if (!guild || guild.leaderId !== session.characterId) {
            this.error(session.characterId, 'Only the guild leader can disband.');
            return;
        }
        if (!this.db.postgres)
            return;
        const guildId = guild.guildId;
        const members = this.membersOf(guild).map(m => m.characterId);
        try {
            await this.db.postgres.query('DELETE FROM guilds WHERE id = $1', [guildId]);
        }
        catch (error) {
            console.error('[GuildSystem] disbandGuild failed:', error);
            return;
        }
        this.guilds.delete(guildId);
        this.memberRows.delete(guildId);
        for (const cid of members) {
            this.memberGuild.delete(cid);
            const s = this.deps.getPlayers().get(cid);
            if (s) {
                s.guildId = null;
                s.guildTag = null;
                s.guildRank = null;
                this.broadcastTag(s);
                this.deps.sendToPlayer(cid, {
                    type: shared_1.PacketType.GUILD_UPDATE,
                    timestamp: Date.now(),
                    data: { guildId: null },
                });
                this.deps.sendToPlayer(cid, {
                    type: shared_1.PacketType.NOTIFICATION,
                    timestamp: Date.now(),
                    data: { message: `Guild "${guild.name}" was disbanded.`, type: 'info' },
                });
            }
        }
    }
    /** Invite: permission-gated; target must be guildless and online. */
    async invite(session, targetId) {
        const guild = this.getGuildForMember(session.characterId);
        if (!guild) {
            this.error(session.characterId, 'You are not in a guild.');
            return;
        }
        const rank = this.getMemberRank(session.characterId);
        if (!rank || !this.permissionsOf(guild, rank).invite) {
            this.error(session.characterId, 'You do not have permission to invite.');
            return;
        }
        const target = this.deps.getPlayers().get(targetId);
        if (!target) {
            this.error(session.characterId, 'Target not found.');
            return;
        }
        if (this.getGuildForMember(targetId)) {
            this.error(session.characterId, `${target.characterName} is already in a guild.`);
            return;
        }
        if (this.membersOf(guild).length >= shared_1.GUILD_MAX_MEMBERS) {
            this.error(session.characterId, 'The guild is full.');
            return;
        }
        this.deps.sendToPlayer(targetId, {
            type: shared_1.PacketType.GUILD_INVITE,
            timestamp: Date.now(),
            data: { guildId: guild.guildId, guildName: guild.name, tag: guild.tag, inviterName: session.characterName },
        });
        this.deps.sendToPlayer(session.characterId, {
            type: shared_1.PacketType.NOTIFICATION,
            timestamp: Date.now(),
            data: { message: `Guild invite sent to ${target.characterName}.`, type: 'success' },
        });
    }
    /** Accept (or decline) a GUILD_INVITE. */
    async joinInvite(session, guildId, accept) {
        if (!accept) {
            this.deps.sendToPlayer(session.characterId, {
                type: shared_1.PacketType.NOTIFICATION,
                timestamp: Date.now(),
                data: { message: 'Guild invitation declined.', type: 'info' },
            });
            return;
        }
        if (this.getGuildForMember(session.characterId)) {
            this.error(session.characterId, 'You are already in a guild.');
            return;
        }
        if (!this.db.postgres)
            return;
        const guild = await this.loadGuild(guildId);
        if (!guild) {
            this.error(session.characterId, 'That guild no longer exists.');
            return;
        }
        try {
            await this.db.postgres.query('INSERT INTO guild_members (guild_id, character_id, rank) VALUES ($1, $2, $3)', [guildId, session.characterId, 'recruit']);
        }
        catch {
            this.error(session.characterId, 'Could not join the guild.');
            return;
        }
        this.memberGuild.set(session.characterId, guildId);
        this.upsertMemberRow(guildId, {
            characterId: session.characterId,
            rank: 'recruit',
            name: session.characterName,
            level: session.stats.level,
            jobId: session.jobId || '',
        });
        this.syncSession(session, guild, 'recruit');
        this.notify(guildId, `${session.characterName} has joined the guild.`);
        await this.sendGuildUpdate(guildId);
    }
    /** Leave (not allowed for the leader — they must disband or hand over). */
    async leave(session) {
        const guild = this.getGuildForMember(session.characterId);
        if (!guild)
            return;
        if (guild.leaderId === session.characterId) {
            this.error(session.characterId, 'Leaders must disband the guild or promote a successor first.');
            return;
        }
        await this.removeMember(session.characterId, guild, `${session.characterName} has left the guild.`);
    }
    /** Kick: permission + rank-order gated (can only kick below your rank). */
    async kick(session, targetId) {
        const guild = this.getGuildForMember(session.characterId);
        if (!guild)
            return;
        const myRank = this.getMemberRank(session.characterId);
        if (!myRank || !this.permissionsOf(guild, myRank).kick) {
            this.error(session.characterId, 'You do not have permission to kick.');
            return;
        }
        const targetRow = this.membersOf(guild).find(m => m.characterId === targetId);
        if (!targetRow) {
            this.error(session.characterId, 'Member not found.');
            return;
        }
        if (shared_1.GUILD_RANK_ORDER[targetRow.rank] <= shared_1.GUILD_RANK_ORDER[myRank]) {
            this.error(session.characterId, 'You can only kick members below your rank.');
            return;
        }
        const name = targetRow.name;
        await this.removeMember(targetId, guild, `${name} was removed from the guild.`);
    }
    async removeMember(characterId, guild, message) {
        if (this.db.postgres) {
            try {
                await this.db.postgres.query('DELETE FROM guild_members WHERE character_id = $1', [characterId]);
            }
            catch (error) {
                console.error('[GuildSystem] removeMember failed:', error);
                return;
            }
        }
        this.memberGuild.delete(characterId);
        this.removeMemberRow(guild.guildId, characterId);
        const session = this.deps.getPlayers().get(characterId);
        if (session) {
            session.guildId = null;
            session.guildTag = null;
            session.guildRank = null;
            this.broadcastTag(session);
            this.deps.sendToPlayer(characterId, {
                type: shared_1.PacketType.GUILD_UPDATE,
                timestamp: Date.now(),
                data: { guildId: null },
            });
        }
        this.notify(guild.guildId, message);
        await this.sendGuildUpdate(guild.guildId);
    }
    /**
     * Set a member's rank: promote/demote one step or direct assign. Leader can
     * hand leadership to an officer (transferring leaderId); nobody may kick or
     * demote the leader via this path.
     */
    async setRank(session, targetId, newRankRaw) {
        const guild = this.getGuildForMember(session.characterId);
        if (!guild)
            return;
        if (!(0, shared_1.isGuildRank)(newRankRaw)) {
            this.error(session.characterId, 'Unknown rank.');
            return;
        }
        const newRank = newRankRaw;
        const myRank = this.getMemberRank(session.characterId);
        const targetRow = this.membersOf(guild).find(m => m.characterId === targetId);
        if (!targetRow) {
            this.error(session.characterId, 'Member not found.');
            return;
        }
        if (guild.leaderId === session.characterId) {
            // Leader: may assign any rank; assigning 'leader' transfers leadership.
        }
        else {
            if (!myRank || !this.permissionsOf(guild, myRank).promote) {
                this.error(session.characterId, 'You do not have permission to change ranks.');
                return;
            }
            if (shared_1.GUILD_RANK_ORDER[targetRow.rank] <= shared_1.GUILD_RANK_ORDER[myRank]) {
                this.error(session.characterId, 'You can only change ranks below your own.');
                return;
            }
            if (newRank === 'leader') {
                this.error(session.characterId, 'Only the leader can transfer leadership.');
                return;
            }
        }
        if (!this.db.postgres)
            return;
        try {
            await this.db.postgres.query('UPDATE guild_members SET rank = $1 WHERE character_id = $2', [newRank, targetId]);
            if (newRank === 'leader') {
                await this.db.postgres.query('UPDATE guilds SET leader_id = $1 WHERE id = $2', [targetId, guild.guildId]);
                guild.leaderId = targetId;
                // Former leader becomes officer.
                await this.db.postgres.query('UPDATE guild_members SET rank = $1 WHERE character_id = $2', ['officer', session.characterId]);
                const former = this.membersOf(guild).find(m => m.characterId === session.characterId);
                if (former)
                    former.rank = 'officer';
                const s = this.deps.getPlayers().get(session.characterId);
                if (s)
                    s.guildRank = 'officer';
            }
        }
        catch (error) {
            console.error('[GuildSystem] setRank failed:', error);
            return;
        }
        targetRow.rank = newRank;
        const target = this.deps.getPlayers().get(targetId);
        if (target)
            target.guildRank = newRank;
        this.notify(guild.guildId, `${targetRow.name} is now ${newRank}.`);
        await this.sendGuildUpdate(guild.guildId);
    }
    /** Leader edits a rank's permission flags. */
    async setRankPerms(session, rank, perms) {
        const guild = this.getGuildForMember(session.characterId);
        if (!guild)
            return;
        if (guild.leaderId !== session.characterId) {
            this.error(session.characterId, 'Only the guild leader can edit rank permissions.');
            return;
        }
        if (!(0, shared_1.isGuildRank)(rank) || rank === 'leader') {
            this.error(session.characterId, 'Cannot edit that rank.');
            return;
        }
        const merged = {
            ...this.permissionsOf(guild, rank),
            ...perms,
        };
        guild.rankPerms = { ...guild.rankPerms, [rank]: merged };
        if (this.db.postgres) {
            try {
                await this.db.postgres.query('UPDATE guilds SET rank_perms = $1 WHERE id = $2', [
                    JSON.stringify(guild.rankPerms),
                    guild.guildId,
                ]);
            }
            catch (error) {
                console.error('[GuildSystem] setRankPerms failed:', error);
            }
        }
        await this.sendGuildUpdate(guild.guildId);
    }
    async setMotd(session, motd) {
        const guild = this.getGuildForMember(session.characterId);
        if (!guild)
            return;
        const rank = this.getMemberRank(session.characterId);
        if (!rank || !this.permissionsOf(guild, rank).setMotd) {
            this.error(session.characterId, 'You do not have permission to set the MOTD.');
            return;
        }
        guild.motd = (motd || '').trim().substring(0, shared_1.GUILD_MOTD_MAX);
        if (this.db.postgres) {
            try {
                await this.db.postgres.query('UPDATE guilds SET motd = $1 WHERE id = $2', [guild.motd, guild.guildId]);
            }
            catch (error) {
                console.error('[GuildSystem] setMotd failed:', error);
            }
        }
        this.notify(guild.guildId, `MOTD set: ${guild.motd || '(cleared)'}`);
        await this.sendGuildUpdate(guild.guildId);
    }
    // ── bank ──────────────────────────────────────────────────────────────────
    /** Deposit (amount > 0) or withdraw (amount < 0) gold; permission-gated. */
    async bankGold(session, amount) {
        const guild = this.getGuildForMember(session.characterId);
        if (!guild)
            return;
        const rank = this.getMemberRank(session.characterId);
        if (!rank)
            return;
        const perms = this.permissionsOf(guild, rank);
        const amt = Math.floor(amount);
        if (amt === 0)
            return;
        if (amt < 0 && !perms.bankWithdraw) {
            this.error(session.characterId, 'You do not have permission to withdraw gold.');
            return;
        }
        if (amt > 0 && !perms.bankDeposit) {
            this.error(session.characterId, 'You do not have permission to deposit gold.');
            return;
        }
        if (amt > 0) {
            if (session.gold < amt) {
                this.error(session.characterId, 'Not enough gold.');
                return;
            }
            session.gold -= amt;
            guild.gold += amt;
        }
        else {
            const take = -amt;
            if (guild.gold < take) {
                this.error(session.characterId, 'The guild bank does not have that much gold.');
                return;
            }
            guild.gold -= take;
            session.gold += take;
        }
        if (this.db.postgres) {
            try {
                await this.db.postgres.query('UPDATE guilds SET gold = $1 WHERE id = $2', [guild.gold, guild.guildId]);
            }
            catch (error) {
                console.error('[GuildSystem] bankGold failed:', error);
            }
        }
        await this.sendGuildUpdate(guild.guildId);
    }
    /** Deposit (qty > 0) / withdraw (qty < 0) one stacked item type. */
    async bankItem(session, itemId, qty, removeItem, addItem) {
        const guild = this.getGuildForMember(session.characterId);
        if (!guild)
            return;
        const rank = this.getMemberRank(session.characterId);
        if (!rank)
            return;
        const perms = this.permissionsOf(guild, rank);
        const n = Math.floor(qty);
        if (!itemId || n === 0)
            return;
        if (n < 0 && !perms.bankWithdraw) {
            this.error(session.characterId, 'You do not have permission to withdraw items.');
            return;
        }
        if (n > 0 && !perms.bankDeposit) {
            this.error(session.characterId, 'You do not have permission to deposit items.');
            return;
        }
        if (n > 0) {
            if (!removeItem(session, itemId, n)) {
                this.error(session.characterId, 'You do not have that many.');
                return;
            }
            const slot = guild.bankItems.find(b => b.itemId === itemId);
            if (slot)
                slot.quantity += n;
            else if (guild.bankItems.length < shared_1.GUILD_BANK_MAX_SLOTS)
                guild.bankItems.push({ itemId, quantity: n });
            else {
                addItem(session, itemId, n); // refund: bank full
                this.error(session.characterId, 'The guild bank is full.');
                return;
            }
        }
        else {
            const take = -n;
            const slot = guild.bankItems.find(b => b.itemId === itemId);
            if (!slot || slot.quantity < take) {
                this.error(session.characterId, 'The bank does not have that many.');
                return;
            }
            slot.quantity -= take;
            if (slot.quantity <= 0) {
                const i = guild.bankItems.indexOf(slot);
                guild.bankItems.splice(i, 1);
            }
            addItem(session, itemId, take);
        }
        if (this.db.postgres) {
            try {
                await this.db.postgres.query('UPDATE guilds SET bank_items = $1 WHERE id = $2', [
                    JSON.stringify(guild.bankItems),
                    guild.guildId,
                ]);
            }
            catch (error) {
                console.error('[GuildSystem] bankItem failed:', error);
            }
        }
        await this.sendGuildUpdate(guild.guildId);
    }
    // ── guild XP ──────────────────────────────────────────────────────────────
    /** Grant guild XP for a kill; levels up (cap GUILD_MAX_LEVEL) and announces. */
    addExperience(characterId, xp) {
        if (xp <= 0)
            return;
        const guild = this.getGuildForMember(characterId);
        if (!guild || guild.level >= shared_1.GUILD_MAX_LEVEL)
            return;
        guild.experience += xp;
        let leveled = false;
        while (guild.level < shared_1.GUILD_MAX_LEVEL && guild.experience >= (0, shared_1.guildXpToNext)(guild.level)) {
            guild.experience -= (0, shared_1.guildXpToNext)(guild.level);
            guild.level += 1;
            leveled = true;
        }
        if (this.db.postgres) {
            this.db.postgres
                .query('UPDATE guilds SET level = $1, experience = $2 WHERE id = $3', [
                guild.level, guild.experience, guild.guildId,
            ])
                .catch(err => console.error('[GuildSystem] addExperience save failed:', err));
        }
        if (leveled) {
            this.notify(guild.guildId, `The guild reached level ${guild.level}!`);
        }
    }
    // ── misc ──────────────────────────────────────────────────────────────────
    /** Refresh online flags in member lists after a login/logout. */
    async refreshForGuildOf(characterId) {
        const guildId = this.memberGuild.get(characterId);
        if (guildId)
            await this.sendGuildUpdate(guildId);
    }
    /** Relay a raw packet (guild chat) to online members. */
    relayPacket(guildId, packet) {
        const guild = this.guilds.get(guildId);
        if (!guild)
            return;
        for (const m of this.membersOf(guild)) {
            if (this.deps.getPlayers().get(m.characterId)) {
                this.deps.sendToPlayer(m.characterId, packet);
            }
        }
    }
    error(characterId, message) {
        this.deps.sendToPlayer(characterId, {
            type: shared_1.PacketType.NOTIFICATION,
            timestamp: Date.now(),
            data: { message, type: 'error' },
        });
    }
}
exports.GuildSystem = GuildSystem;
