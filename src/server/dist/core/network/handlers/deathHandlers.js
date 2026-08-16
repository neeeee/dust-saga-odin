"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.registerHandlers = registerHandlers;
const shared_1 = require("@dust-saga/shared");
function registerHandlers(registry) {
    registry.set(shared_1.PacketType.RESPAWN_REQUEST, handleRespawnRequest);
    registry.set(shared_1.PacketType.REVIVE_PLAYER, handleRevivePlayer);
}
function handleRespawnRequest(ctx, socket, _data) {
    const characterId = ctx.findCharacterBySocket(socket.id);
    if (!characterId)
        return;
    const session = ctx.state.players.get(characterId);
    if (!session || !session.isDead)
        return;
    let respawnZoneId;
    let respawnPos;
    if (session.nation && shared_1.NATION_ZONE_MAP[session.nation]) {
        const nationInfo = shared_1.NATION_ZONE_MAP[session.nation];
        respawnZoneId = nationInfo.zoneId;
        const zoneDef = (0, shared_1.getZoneDefinition)(respawnZoneId);
        respawnPos = zoneDef?.playerSpawn || { x: 0, y: 0, z: 0 };
    }
    else {
        respawnZoneId = session.lastSafeZoneId;
        const zoneDef = (0, shared_1.getZoneDefinition)(respawnZoneId);
        respawnPos = zoneDef?.playerSpawn || { x: 0, y: 0, z: 0 };
    }
    const changingZone = session.zoneId !== respawnZoneId;
    if (changingZone) {
        ctx.broadcastInZone(session.zoneId, {
            type: shared_1.PacketType.ENTITY_DESPAWN,
            timestamp: Date.now(),
            data: { entityId: characterId }
        });
    }
    session.isDead = false;
    session.isResting = false;
    session.deathTime = 0;
    session.stats.health = session.stats.maxHealth;
    session.stats.mana = session.stats.maxMana;
    session.position = { ...respawnPos };
    session.invulnerableUntil = Date.now() + 5000;
    session.targetId = null;
    session.currentNpcId = null;
    session.activeCast = null;
    session.statusEffects = [];
    ctx.playerSys.recalcStats(session);
    if (changingZone) {
        session.zoneId = respawnZoneId;
        ctx.movePlayerToZone(characterId, respawnZoneId);
        ctx.broadcastInZone(respawnZoneId, {
            type: shared_1.PacketType.ENTITY_SPAWN,
            timestamp: Date.now(),
            data: {
                id: characterId,
                type: 'player',
                position: session.position,
                rotation: session.rotation,
                data: { name: session.characterName, class: session.jobId, race: session.race, jobId: session.jobId, level: session.stats.level, health: session.stats.health, maxHealth: session.stats.maxHealth, isResting: false }
            }
        });
        ctx.sendZoneState(socket, respawnZoneId, characterId);
    }
    ctx.sendToPlayer(characterId, {
        type: shared_1.PacketType.PLAYER_REVIVED,
        timestamp: Date.now(),
        data: { characterId, zoneId: respawnZoneId, position: respawnPos, health: session.stats.health, maxHealth: session.stats.maxHealth, invulnerable: true }
    });
    ctx.sendToPlayer(characterId, {
        type: shared_1.PacketType.STATS_UPDATE,
        timestamp: Date.now(),
        data: { characterId, stats: session.stats }
    });
    ctx.broadcastInZone(session.zoneId, {
        type: shared_1.PacketType.STATS_UPDATE,
        timestamp: Date.now(),
        data: { entityId: characterId, health: session.stats.health, maxHealth: session.stats.maxHealth }
    }, characterId);
    ctx.refreshPartyForMember(characterId);
}
function handleRevivePlayer(ctx, socket, data) {
    const reviverId = ctx.findCharacterBySocket(socket.id);
    if (!reviverId)
        return;
    const reviver = ctx.state.players.get(reviverId);
    if (!reviver || reviver.isDead)
        return;
    const targetId = data.targetId;
    if (!targetId)
        return;
    const target = ctx.state.players.get(targetId);
    if (!target || !target.isDead)
        return;
    if (target.statusEffects?.some(e => e.preventResurrect || e.type === shared_1.StatusEffectType.PREVENT_RESSURECT)) {
        ctx.sendToPlayer(reviverId, {
            type: shared_1.PacketType.CHAT_MESSAGE,
            timestamp: Date.now(),
            data: { sender: 'System', message: 'Target is cursed and cannot be resurrected.', channel: 'system' }
        });
        return;
    }
    const dx = reviver.position.x - target.position.x;
    const dz = reviver.position.z - target.position.z;
    if (Math.sqrt(dx * dx + dz * dz) > 5) {
        ctx.sendToPlayer(reviverId, {
            type: shared_1.PacketType.CHAT_MESSAGE,
            timestamp: Date.now(),
            data: { sender: 'System', message: 'Too far away to revive.', channel: 'system' }
        });
        return;
    }
    const targetZoneDef = (0, shared_1.getZoneDefinition)(target.zoneId);
    const reviverZoneDef = (0, shared_1.getZoneDefinition)(reviver.zoneId);
    const targetNation = targetZoneDef?.nation;
    const reviverNation = reviverZoneDef?.nation;
    if (targetNation) {
        if (reviverNation !== targetNation) {
            ctx.sendToPlayer(reviverId, {
                type: shared_1.PacketType.CHAT_MESSAGE,
                timestamp: Date.now(),
                data: { sender: 'System', message: 'Cannot revive players from another nation in this zone.', channel: 'system' }
            });
            return;
        }
    }
    ctx.handleRevivePlayerBySession(reviver, targetId);
}
