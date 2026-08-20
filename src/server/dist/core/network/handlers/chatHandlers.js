"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.registerHandlers = registerHandlers;
const shared_1 = require("@dust-saga/shared");
function registerHandlers(registry) {
    registry.set(shared_1.PacketType.CHAT_MESSAGE, handleChatMessage);
}
const COMMAND_MIN_ROLE = {
    '/levelup': shared_1.AccountRole.GM,
    '/setlevel': shared_1.AccountRole.GM,
    '/resetstats': shared_1.AccountRole.GM,
    '/resetskills': shared_1.AccountRole.GM,
    '/advance': shared_1.AccountRole.GM,
    '/giveitem': shared_1.AccountRole.GM,
    '/killallenemies': shared_1.AccountRole.GM,
    '/dummy': shared_1.AccountRole.GM,
    '/spawn_dummy': shared_1.AccountRole.GM,
    '/despawn_dummy': shared_1.AccountRole.GM,
    '/kill_dummy': shared_1.AccountRole.GM,
    '/dummy_set': shared_1.AccountRole.GM,
    '/dummy_class': shared_1.AccountRole.GM,
    '/dummy_gear': shared_1.AccountRole.GM,
    '/dummy_pvp': shared_1.AccountRole.GM,
    '/dummy_walk': shared_1.AccountRole.GM,
    '/dummy_party': shared_1.AccountRole.GM,
    '/dummy_list': shared_1.AccountRole.GM,
};
function chatSenderLabel(session) {
    if (session.role === shared_1.AccountRole.ADMIN)
        return `[ADMIN] ${session.characterName}`;
    if (session.role === shared_1.AccountRole.GM)
        return `[GM] ${session.characterName}`;
    return session.characterName;
}
function handleChatMessage(ctx, socket, data) {
    const characterId = ctx.findCharacterBySocket(socket.id);
    if (!characterId)
        return;
    const session = ctx.state.players.get(characterId);
    if (!session)
        return;
    const message = typeof data.message === 'string' ? data.message.substring(0, 200) : '';
    if (!message.trim())
        return;
    if (message.startsWith('/')) {
        handleChatCommand(ctx, socket, session, message);
        return;
    }
    const channel = data.channel || 'zone';
    const packet = {
        type: shared_1.PacketType.CHAT_MESSAGE,
        timestamp: Date.now(),
        data: {
            sender: chatSenderLabel(session),
            message,
            channel
        }
    };
    // Party chat routes to party members only (any zone, any shard via relay).
    if (channel === 'party') {
        const party = ctx.partySys.getPartyForMember(characterId);
        if (!party) {
            ctx.sendToPlayer(characterId, {
                type: shared_1.PacketType.CHAT_MESSAGE,
                timestamp: Date.now(),
                data: { sender: 'System', message: 'You are not in a party.', channel: 'system' }
            });
            return;
        }
        for (const m of party.members) {
            ctx.sendToPlayer(m.characterId, packet);
        }
        return;
    }
    // Guild chat routes to online guild members.
    if (channel === 'guild') {
        const guild = ctx.guildSys.getGuildForMember(characterId);
        if (!guild) {
            ctx.sendToPlayer(characterId, {
                type: shared_1.PacketType.CHAT_MESSAGE,
                timestamp: Date.now(),
                data: { sender: 'System', message: 'You are not in a guild.', channel: 'system' }
            });
            return;
        }
        ctx.guildSys.relayPacket(guild.guildId, packet);
        return;
    }
    if (channel === 'global') {
        ctx.io.emit('packet', packet);
    }
    else {
        ctx.broadcastInZone(session.zoneId, packet);
    }
}
function handleChatCommand(ctx, socket, session, message) {
    const parts = message.toLowerCase().trim().split(/\s+/);
    const cmd = parts[0];
    const minRole = COMMAND_MIN_ROLE[cmd];
    if (minRole && !(0, shared_1.roleAtLeast)(session.role, minRole)) {
        ctx.sendToPlayer(session.characterId, {
            type: shared_1.PacketType.CHAT_MESSAGE,
            timestamp: Date.now(),
            data: { sender: 'System', message: 'Command requires GM privileges.', channel: 'system' }
        });
        return;
    }
    if (cmd === '/levelup') {
        handleLevelUp(ctx, session);
    }
    else if (cmd === '/setlevel') {
        handleSetLevel(ctx, session, parts);
    }
    else if (cmd === '/resetstats') {
        handleResetStats(ctx, session);
    }
    else if (cmd === '/advance') {
        handleAdvance(ctx, session, parts);
    }
    else if (cmd === '/killallenemies') {
        handleKillAllEnemies(ctx, session);
    }
    else if (cmd === '/dummy') {
        handleDummy(ctx, session, parts);
    }
    else if (cmd === '/resetskills') {
        handleResetSkills(ctx, session);
    }
    else if (cmd === '/giveitem') {
        handleGiveItem(ctx, session, parts);
    }
    else if (cmd === '/spawn_dummy') {
        ctx.spawnDummy(session);
    }
    else if (cmd === '/despawn_dummy' || cmd === '/kill_dummy') {
        const dummyId = parts[1];
        if (!dummyId) {
            ctx.sendToPlayer(session.characterId, { type: shared_1.PacketType.CHAT_MESSAGE, timestamp: Date.now(), data: { sender: 'GM', message: 'Usage: /despawn_dummy <id> or /kill_dummy <id>', channel: 'system' } });
            return;
        }
        ctx.despawnDummy(dummyId, session);
    }
    else if (cmd === '/dummy_set') {
        const dummyId = parts[1];
        const prop = parts[2];
        const value = parts[3];
        if (!dummyId || !prop || value === undefined) {
            ctx.sendToPlayer(session.characterId, { type: shared_1.PacketType.CHAT_MESSAGE, timestamp: Date.now(), data: { sender: 'GM', message: 'Usage: /dummy_set <id> <prop> <value>', channel: 'system' } });
            return;
        }
        ctx.setDummyProperty(dummyId, prop, value, session);
    }
    else if (cmd === '/dummy_class') {
        const dummyId = parts[1];
        const jobId = parts[2];
        if (!dummyId || !jobId) {
            ctx.sendToPlayer(session.characterId, { type: shared_1.PacketType.CHAT_MESSAGE, timestamp: Date.now(), data: { sender: 'GM', message: 'Usage: /dummy_class <id> <jobId>', channel: 'system' } });
            return;
        }
        ctx.setDummyClass(dummyId, jobId, session);
    }
    else if (cmd === '/dummy_gear') {
        const dummyId = parts[1];
        const preset = parts[2];
        if (!dummyId || !preset) {
            ctx.sendToPlayer(session.characterId, { type: shared_1.PacketType.CHAT_MESSAGE, timestamp: Date.now(), data: { sender: 'GM', message: 'Usage: /dummy_gear <id> <naked|common|rare|legendary>', channel: 'system' } });
            return;
        }
        ctx.setDummyGear(dummyId, preset, session);
    }
    else if (cmd === '/dummy_pvp') {
        const dummyId = parts[1];
        if (!dummyId) {
            ctx.sendToPlayer(session.characterId, { type: shared_1.PacketType.CHAT_MESSAGE, timestamp: Date.now(), data: { sender: 'GM', message: 'Usage: /dummy_pvp <id>', channel: 'system' } });
            return;
        }
        ctx.toggleDummyPvp(dummyId, session);
    }
    else if (cmd === '/dummy_walk') {
        const dummyId = parts[1];
        if (!dummyId) {
            ctx.sendToPlayer(session.characterId, { type: shared_1.PacketType.CHAT_MESSAGE, timestamp: Date.now(), data: { sender: 'GM', message: 'Usage: /dummy_walk <id>', channel: 'system' } });
            return;
        }
        ctx.toggleDummyWalk(dummyId, session);
    }
    else if (cmd === '/dummy_party') {
        const dummyId = parts[1];
        if (!dummyId) {
            ctx.sendToPlayer(session.characterId, { type: shared_1.PacketType.CHAT_MESSAGE, timestamp: Date.now(), data: { sender: 'GM', message: 'Usage: /dummy_party <id>', channel: 'system' } });
            return;
        }
        ctx.toggleDummyParty(dummyId, session);
    }
    else if (cmd === '/dummy_list') {
        const dummies = [];
        for (const [id, meta] of ctx.dummyMeta) {
            if (meta.ownerId === session.characterId) {
                const d = ctx.state.players.get(id);
                dummies.push(`${id} Lv${d?.stats.level || 0} ${d?.jobId || '?'} ${meta.isPvp ? 'PvP' : 'Friendly'}${meta.isWalking ? ' Walking' : ''}${meta.inParty ? ' Party' : ''}`);
            }
        }
        ctx.sendToPlayer(session.characterId, { type: shared_1.PacketType.CHAT_MESSAGE, timestamp: Date.now(), data: { sender: 'GM', message: dummies.length > 0 ? dummies.join('\n') : 'No dummies spawned.', channel: 'system' } });
    }
    else if (cmd === '/return') {
        handleReturn(ctx, socket, session);
    }
}
function handleLevelUp(ctx, session) {
    const currentLevel = session.stats.level;
    const xpNeeded = session.stats.experienceToNext - session.stats.experience;
    if (xpNeeded > 0) {
        ctx.playerSys.grantExperience(session, xpNeeded);
    }
    ctx.sendToPlayer(session.characterId, {
        type: shared_1.PacketType.CHAT_MESSAGE,
        timestamp: Date.now(),
        data: { sender: 'System', message: `Leveled up! Now level ${session.stats.level}.`, channel: 'system' }
    });
    ctx.sendToPlayer(session.characterId, {
        type: shared_1.PacketType.STATS_UPDATE,
        timestamp: Date.now(),
        data: { characterId: session.characterId, stats: session.stats, statPoints: session.statPoints, unspentStatPoints: session.unspentStatPoints, unspentSkillPoints: session.unspentSkillPoints, skillProficiencies: session.skillProficiencies,
            skillAdeptness: session.skillAdeptness }
    });
    if (currentLevel < session.stats.level) {
        ctx.sendToPlayer(session.characterId, {
            type: shared_1.PacketType.LEVEL_UP,
            timestamp: Date.now(),
            data: { level: session.stats.level, statPoints: session.statPoints, unspentStatPoints: session.unspentStatPoints, unspentSkillPoints: session.unspentSkillPoints }
        });
    }
}
function handleSetLevel(ctx, session, parts) {
    const targetLevel = parseInt(parts[1], 10);
    if (isNaN(targetLevel) || targetLevel < 1 || targetLevel > shared_1.MAX_LEVEL) {
        ctx.sendToPlayer(session.characterId, {
            type: shared_1.PacketType.CHAT_MESSAGE,
            timestamp: Date.now(),
            data: { sender: 'System', message: `Usage: /setlevel <1-${shared_1.MAX_LEVEL}>`, channel: 'system' }
        });
        return;
    }
    let totalStatPoints = 0;
    let totalSkillPoints = 0;
    for (let lvl = 2; lvl <= targetLevel; lvl++) {
        totalStatPoints += (0, shared_1.getStatPointsGainedAtLevel)(lvl);
        totalSkillPoints += (0, shared_1.getSkillPointsGainedAtLevel)(lvl);
    }
    const spentStatPoints = Object.values(session.statPoints).reduce((sum, v) => sum + v, 0);
    session.unspentStatPoints = totalStatPoints - spentStatPoints;
    const currentSkillSpent = Object.values(session.skillProficiencies).reduce((sum, v) => sum + (typeof v === 'number' ? v : 0), 0);
    session.unspentSkillPoints = totalSkillPoints - currentSkillSpent;
    if (session.unspentStatPoints < 0)
        session.unspentStatPoints = 0;
    if (session.unspentSkillPoints < 0)
        session.unspentSkillPoints = 0;
    session.stats.level = targetLevel;
    session.stats.experience = 0;
    session.stats.experienceToNext = (0, shared_1.getExperienceToNextLevel)(targetLevel);
    ctx.playerSys.recalcStats(session);
    ctx.sendToPlayer(session.characterId, {
        type: shared_1.PacketType.CHAT_MESSAGE,
        timestamp: Date.now(),
        data: { sender: 'System', message: `Level set to ${targetLevel}. Total stat points: ${totalStatPoints}, total skill points: ${totalSkillPoints}.`, channel: 'system' }
    });
    ctx.sendToPlayer(session.characterId, {
        type: shared_1.PacketType.STATS_UPDATE,
        timestamp: Date.now(),
        data: { characterId: session.characterId, stats: session.stats, statPoints: session.statPoints, unspentStatPoints: session.unspentStatPoints, unspentSkillPoints: session.unspentSkillPoints, skillProficiencies: session.skillProficiencies,
            skillAdeptness: session.skillAdeptness }
    });
    ctx.sendToPlayer(session.characterId, {
        type: shared_1.PacketType.LEVEL_UP,
        timestamp: Date.now(),
        data: { level: session.stats.level, statPoints: session.statPoints, unspentStatPoints: session.unspentStatPoints, unspentSkillPoints: session.unspentSkillPoints }
    });
    ctx.refreshPartyForMember(session.characterId);
}
function handleResetStats(ctx, session) {
    const spentStatPoints = Object.values(session.statPoints).reduce((sum, v) => sum + v, 0);
    session.statPoints = (0, shared_1.createDefaultStatPoints)();
    session.unspentStatPoints += spentStatPoints;
    ctx.playerSys.recalcStats(session);
    ctx.sendToPlayer(session.characterId, {
        type: shared_1.PacketType.CHAT_MESSAGE,
        timestamp: Date.now(),
        data: { sender: 'System', message: `Stat points reset. Refunded ${spentStatPoints} points.`, channel: 'system' }
    });
    ctx.sendToPlayer(session.characterId, {
        type: shared_1.PacketType.STATS_UPDATE,
        timestamp: Date.now(),
        data: { characterId: session.characterId, stats: session.stats, statPoints: session.statPoints, unspentStatPoints: session.unspentStatPoints, unspentSkillPoints: session.unspentSkillPoints, skillProficiencies: session.skillProficiencies,
            skillAdeptness: session.skillAdeptness }
    });
    ctx.refreshPartyForMember(session.characterId);
}
function handleAdvance(ctx, session, parts) {
    if (!parts[1]) {
        const options = (0, shared_1.getAdvancementOptions)(session.jobId);
        if (options.length === 0) {
            const job = shared_1.JOB_DEFINITIONS[session.jobId];
            const tier = job?.tier || '?';
            ctx.sendToPlayer(session.characterId, {
                type: shared_1.PacketType.CHAT_MESSAGE,
                timestamp: Date.now(),
                data: { sender: 'System', message: `No advancement options for ${session.jobId} (tier ${tier}). You are at the highest tier or tier ${tier} requires level ${tier === 2 ? 20 : 40} to advance.`, channel: 'system' }
            });
        }
        else {
            const optionNames = options.map(o => shared_1.JOB_DEFINITIONS[o]?.name || o).join(', ');
            ctx.sendToPlayer(session.characterId, {
                type: shared_1.PacketType.CHAT_MESSAGE,
                timestamp: Date.now(),
                data: { sender: 'System', message: `Available advancements from ${session.jobId}: ${optionNames}. Usage: /advance <jobName>`, channel: 'system' }
            });
        }
        return;
    }
    const targetName = parts.slice(1).join(' ').toLowerCase();
    const options = (0, shared_1.getAdvancementOptions)(session.jobId);
    const match = options.find(id => {
        const def = shared_1.JOB_DEFINITIONS[id];
        return id.toLowerCase() === targetName || def?.name.toLowerCase() === targetName;
    });
    if (!match) {
        const optionNames = options.map(o => shared_1.JOB_DEFINITIONS[o]?.name || o).join(', ');
        ctx.sendToPlayer(session.characterId, {
            type: shared_1.PacketType.CHAT_MESSAGE,
            timestamp: Date.now(),
            data: { sender: 'System', message: `Invalid advancement target "${parts.slice(1).join(' ')}". Options: ${optionNames || 'none'}`, channel: 'system' }
        });
        return;
    }
    const targetDef = shared_1.JOB_DEFINITIONS[match];
    const oldName = shared_1.JOB_DEFINITIONS[session.jobId]?.name || session.jobId;
    if (ctx.playerSys.advanceJob(session, match)) {
        ctx.sendToPlayer(session.characterId, {
            type: shared_1.PacketType.CHAT_MESSAGE,
            timestamp: Date.now(),
            data: { sender: 'System', message: `Advanced from ${oldName} to ${targetDef?.name || match}! (tier ${targetDef?.tier})`, channel: 'system' }
        });
        ctx.sendToPlayer(session.characterId, {
            type: shared_1.PacketType.STATS_UPDATE,
            timestamp: Date.now(),
            data: { characterId: session.characterId, stats: session.stats, statPoints: session.statPoints, unspentStatPoints: session.unspentStatPoints, unspentSkillPoints: session.unspentSkillPoints, skillProficiencies: session.skillProficiencies,
                skillAdeptness: session.skillAdeptness, jobId: session.jobId, baseClass: session.baseClass }
        });
        ctx.refreshPartyForMember(session.characterId);
    }
    else {
        const requiredLevel = targetDef?.tier === 2 ? 20 : targetDef?.tier === 3 ? 45 : 1;
        ctx.sendToPlayer(session.characterId, {
            type: shared_1.PacketType.CHAT_MESSAGE,
            timestamp: Date.now(),
            data: { sender: 'System', message: `Cannot advance to ${targetDef?.name || match}. Requires level ${requiredLevel} (you are ${session.stats.level}).`, channel: 'system' }
        });
    }
}
function handleKillAllEnemies(ctx, session) {
    const enemies = ctx.spawnMgr.getEnemiesInZone(session.zoneId);
    let killed = 0;
    enemies.forEach((enemy, enemyId) => {
        if (enemy.state === 'dead')
            return;
        if (enemy.invulnerable)
            return;
        enemy.health = 0;
        enemy.state = 'dead';
        enemy.deathTime = Date.now();
        killed++;
        ctx.broadcastInZone(session.zoneId, {
            type: shared_1.PacketType.DAMAGE,
            timestamp: Date.now(),
            data: { attackerId: session.characterId, targetId: enemyId, damage: enemy.maxHealth, isCritical: false, damageType: 'physical' }
        });
        ctx.broadcastInZone(session.zoneId, {
            type: shared_1.PacketType.DEATH,
            timestamp: Date.now(),
            data: { entityId: enemyId, killerId: session.characterId }
        });
        ctx.broadcastInZone(session.zoneId, {
            type: shared_1.PacketType.ENTITY_DESPAWN,
            timestamp: Date.now(),
            data: { entityId: enemyId }
        });
    });
    ctx.sendToPlayer(session.characterId, {
        type: shared_1.PacketType.CHAT_MESSAGE,
        timestamp: Date.now(),
        data: { sender: 'System', message: `Killed ${killed} enemies in zone.`, channel: 'system' }
    });
}
function handleDummy(ctx, session, parts) {
    const subCmd = parts[1];
    if (subCmd === 'set' && parts[2] && parts[3]) {
        const stat = parts[2];
        const value = parseFloat(parts[3]);
        if (isNaN(value)) {
            ctx.sendToPlayer(session.characterId, { type: shared_1.PacketType.CHAT_MESSAGE, timestamp: Date.now(), data: { sender: 'System', message: 'Invalid value.', channel: 'system' } });
            return;
        }
        const statKey = { defense: 'defense', level: 'level', maxhealth: 'maxHealth', health: 'health', fireresist: 'fireResist', iceresist: 'iceResist', lightningresist: 'lightningResist', darkresist: 'darkResist', holyresist: 'holyResist', poisonresist: 'poisonResist', ailmentresist: 'ailmentResist', disorderresist: 'disorderResist', magicresist: 'magicResist' };
        const resolvedStat = statKey[stat] || null;
        if (!resolvedStat) {
            ctx.sendToPlayer(session.characterId, { type: shared_1.PacketType.CHAT_MESSAGE, timestamp: Date.now(), data: { sender: 'System', message: `Unknown stat "${stat}". Valid: defense, level, maxHealth, health, fireResist, iceResist, lightningResist, darkResist, holyResist, poisonResist`, channel: 'system' } });
            return;
        }
        const enemies = ctx.spawnMgr.getEnemiesInZone(session.zoneId);
        let found = false;
        for (const [enemyId, enemy] of enemies) {
            if (enemy.enemyType !== 'striking_dummy')
                continue;
            found = true;
            const def = (0, shared_1.getEnemyDefinition)(enemy.enemyType);
            if (!def)
                continue;
            switch (resolvedStat) {
                case 'defense':
                    def.defense = value;
                    break;
                case 'level':
                    def.level = value;
                    enemy.level = value;
                    break;
                case 'maxHealth':
                    def.health = value;
                    enemy.health = value;
                    enemy.maxHealth = value;
                    break;
                case 'health':
                    enemy.health = Math.min(value, enemy.maxHealth);
                    break;
                case 'fireResist':
                    def.fireResist = value;
                    break;
                case 'iceResist':
                    def.iceResist = value;
                    break;
                case 'lightningResist':
                    def.lightningResist = value;
                    break;
                case 'darkResist':
                    def.darkResist = value;
                    break;
                case 'holyResist':
                    def.holyResist = value;
                    break;
                case 'poisonResist':
                    def.poisonResist = value;
                    break;
                case 'ailmentResist':
                    enemy.ailmentResist = value;
                    break;
                case 'disorderResist':
                    enemy.disorderResist = value;
                    break;
                case 'magicResist':
                    def.fireResist = value;
                    def.iceResist = value;
                    def.lightningResist = value;
                    def.darkResist = value;
                    def.holyResist = value;
                    def.poisonResist = value;
                    break;
                default:
                    ctx.sendToPlayer(session.characterId, { type: shared_1.PacketType.CHAT_MESSAGE, timestamp: Date.now(), data: { sender: 'System', message: `Unknown stat "${stat}". Valid: defense, level, maxHealth, health, fireResist, iceResist, lightningResist, darkResist, holyResist, poisonResist, ailmentResist, disorderResist, magicResist`, channel: 'system' } });
                    return;
            }
            ctx.broadcastInZone(session.zoneId, { type: shared_1.PacketType.STATS_UPDATE, timestamp: Date.now(), data: { entityId: enemyId, health: enemy.health, maxHealth: enemy.maxHealth } });
        }
        if (found) {
            ctx.sendToPlayer(session.characterId, { type: shared_1.PacketType.CHAT_MESSAGE, timestamp: Date.now(), data: { sender: 'System', message: `Striking dummy: set ${stat} = ${value}`, channel: 'system' } });
        }
        else {
            ctx.sendToPlayer(session.characterId, { type: shared_1.PacketType.CHAT_MESSAGE, timestamp: Date.now(), data: { sender: 'System', message: 'No striking dummy in this zone.', channel: 'system' } });
        }
    }
    else {
        ctx.sendToPlayer(session.characterId, { type: shared_1.PacketType.CHAT_MESSAGE, timestamp: Date.now(), data: { sender: 'System', message: 'Usage: /dummy set <stat> <value>  —  Stats: defense, level, maxHealth, health, fireResist, iceResist, lightningResist, darkResist, holyResist, poisonResist, ailmentResist, disorderResist, magicResist', channel: 'system' } });
    }
}
function handleResetSkills(ctx, session) {
    const categoryKeys = new Set(['melee', 'technique', 'prayer', 'magic', 'special']);
    const spentSkillPoints = Object.entries(session.skillProficiencies)
        .filter(([key]) => !categoryKeys.has(key))
        .reduce((sum, [, v]) => sum + v, 0);
    session.skillProficiencies = (0, shared_1.createDefaultSkillProficiencies)();
    session.unspentSkillPoints += spentSkillPoints;
    ctx.sendToPlayer(session.characterId, {
        type: shared_1.PacketType.CHAT_MESSAGE,
        timestamp: Date.now(),
        data: { sender: 'System', message: `Skill points reset. Refunded ${spentSkillPoints} points.`, channel: 'system' }
    });
    ctx.sendToPlayer(session.characterId, {
        type: shared_1.PacketType.STATS_UPDATE,
        timestamp: Date.now(),
        data: { characterId: session.characterId, stats: session.stats, statPoints: session.statPoints, unspentStatPoints: session.unspentStatPoints, unspentSkillPoints: session.unspentSkillPoints, skillProficiencies: session.skillProficiencies,
            skillAdeptness: session.skillAdeptness }
    });
    ctx.refreshPartyForMember(session.characterId);
}
function handleGiveItem(ctx, session, parts) {
    const itemId = parts[1];
    const quantity = parseInt(parts[2]) || 1;
    if (!itemId || !ctx.itemSys.getItemDefinition(itemId)) {
        const itemNames = ctx.itemSys.getAllItemDefinitions().map(i => i.id).join(', ');
        ctx.sendToPlayer(session.characterId, {
            type: shared_1.PacketType.CHAT_MESSAGE,
            timestamp: Date.now(),
            data: { sender: 'System', message: `Unknown item "${itemId || ''}". Available: ${itemNames}`, channel: 'system' }
        });
        return;
    }
    const added = ctx.playerSys.addItemToInventory(session, itemId, quantity);
    if (added) {
        const itemDef = ctx.itemSys.getItemDefinition(itemId);
        ctx.sendToPlayer(session.characterId, {
            type: shared_1.PacketType.CHAT_MESSAGE,
            timestamp: Date.now(),
            data: { sender: 'System', message: `Received ${itemDef?.name ?? itemId} x${quantity}.`, channel: 'system' }
        });
        ctx.sendToPlayer(session.characterId, {
            type: shared_1.PacketType.INVENTORY_UPDATE,
            timestamp: Date.now(),
            data: { inventory: session.inventory, equipment: session.equipment }
        });
    }
    else {
        ctx.sendToPlayer(session.characterId, {
            type: shared_1.PacketType.CHAT_MESSAGE,
            timestamp: Date.now(),
            data: { sender: 'System', message: 'Inventory full.', channel: 'system' }
        });
    }
}
function handleReturn(ctx, socket, session) {
    let spawnPos;
    let spawnZoneId;
    if (session.nation && shared_1.NATION_ZONE_MAP[session.nation]) {
        const nationInfo = shared_1.NATION_ZONE_MAP[session.nation];
        spawnZoneId = nationInfo.zoneId;
        const zoneDef = (0, shared_1.getZoneDefinition)(spawnZoneId);
        spawnPos = zoneDef?.playerSpawn || { x: 0, y: 0, z: 0 };
    }
    else {
        spawnZoneId = session.lastSafeZoneId;
        const zoneDef = (0, shared_1.getZoneDefinition)(spawnZoneId);
        spawnPos = zoneDef?.playerSpawn || { x: 0, y: 0, z: 0 };
    }
    const changingZone = session.zoneId !== spawnZoneId;
    if (changingZone) {
        ctx.broadcastInZone(session.zoneId, {
            type: shared_1.PacketType.ENTITY_DESPAWN,
            timestamp: Date.now(),
            data: { entityId: session.characterId }
        });
    }
    session.position = { ...spawnPos };
    session.statusEffects = [];
    session.activeCast = null;
    ctx.playerSys.recalcStats(session);
    if (changingZone) {
        session.zoneId = spawnZoneId;
        ctx.movePlayerToZone(session.characterId, spawnZoneId);
        ctx.broadcastInZone(spawnZoneId, {
            type: shared_1.PacketType.ENTITY_SPAWN,
            timestamp: Date.now(),
            data: {
                id: session.characterId,
                type: 'player',
                position: session.position,
                rotation: session.rotation,
                data: { name: session.characterName, class: session.jobId, race: session.race, jobId: session.jobId, level: session.stats.level, health: session.stats.health, maxHealth: session.stats.maxHealth }
            }
        });
        ctx.sendZoneState(socket, spawnZoneId, session.characterId);
    }
    ctx.sendToPlayer(session.characterId, {
        type: shared_1.PacketType.PLAYER_REVIVED,
        timestamp: Date.now(),
        data: { characterId: session.characterId, zoneId: spawnZoneId, position: spawnPos, health: session.stats.health, maxHealth: session.stats.maxHealth }
    });
    ctx.sendToPlayer(session.characterId, {
        type: shared_1.PacketType.STATS_UPDATE,
        timestamp: Date.now(),
        data: { characterId: session.characterId, stats: session.stats, statBreakdown: session.statBreakdown, skillProficiencies: session.skillProficiencies, skillAdeptness: session.skillAdeptness }
    });
    ctx.sendToPlayer(session.characterId, {
        type: shared_1.PacketType.STATUS_EFFECT_UPDATE,
        timestamp: Date.now(),
        data: { effects: session.statusEffects }
    });
    ctx.sendToPlayer(session.characterId, {
        type: shared_1.PacketType.CHAT_MESSAGE,
        timestamp: Date.now(),
        data: { sender: 'System', message: 'Returned to spawn.', channel: 'system' }
    });
}
