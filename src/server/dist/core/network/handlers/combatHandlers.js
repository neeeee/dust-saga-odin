"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.registerHandlers = registerHandlers;
const shared_1 = require("@dust-saga/shared");
function registerHandlers(registry) {
    registry.set(shared_1.PacketType.ATTACK, handleAttack);
    registry.set(shared_1.PacketType.MANUAL_ATTACK, handleManualAttack);
}
function handleAttack(ctx, socket, data) {
    const characterId = ctx.findCharacterBySocket(socket.id);
    if (!characterId)
        return;
    const session = ctx.state.players.get(characterId);
    if (!session)
        return;
    if (session.currentNpcId)
        return;
    ctx.cancelRest(session);
    if (data.targetId && ctx.state.players.has(data.targetId) && ctx.isPartyMember(characterId, data.targetId))
        return;
    if (data.targetId && data.targetId !== characterId && ctx.state.players.has(data.targetId) && !(0, shared_1.isZonePvpEnabled)(session.zoneId)) {
        return;
    }
    const damageInfos = ctx.combat.processPlayerAttack(session, data.targetId, ctx.spawnMgr.getEnemiesInZone(session.zoneId) || new Map(), ctx.state.players);
    if (damageInfos.length > 0) {
        session.lastAttackTime = Date.now();
    }
    ctx.broadcastInZone(session.zoneId, {
        type: shared_1.PacketType.ENTITY_ANIMATION,
        timestamp: Date.now(),
        data: { entityId: characterId, animation: 'Attack' }
    }, characterId);
    for (const damageInfo of damageInfos) {
        const enemy = ctx.spawnMgr.getEnemy(data.targetId);
        const player = ctx.state.players.get(data.targetId);
        if (player && data.targetId !== characterId) {
            const totalAutoDmg = damageInfo.damage + (damageInfo.elementalDamage?.reduce((s, e) => s + e.damage, 0) || 0);
            const autoDmgResult = ctx.applyPlayerDamage(player, totalAutoDmg, characterId, damageInfo.damageType || 'physical', damageInfo.isCritical || false, session.zoneId, session.position);
            if (!damageInfo.missed && damageInfo.damage > 0) {
                ctx.processGloomRecoil(session);
            }
            ctx.broadcastInZone(session.zoneId, {
                type: shared_1.PacketType.DAMAGE,
                timestamp: Date.now(),
                data: { ...damageInfo, damage: autoDmgResult.redirected ? 0 : autoDmgResult.damageTaken, missed: autoDmgResult.redirected ? true : damageInfo.missed }
            });
            if (!autoDmgResult.redirected) {
                ctx.sendToPlayer(data.targetId, {
                    type: shared_1.PacketType.STATS_UPDATE,
                    timestamp: Date.now(),
                    data: { characterId: data.targetId, stats: player.stats, statBreakdown: player.statBreakdown, skillProficiencies: player.skillProficiencies, skillAdeptness: player.skillAdeptness }
                });
                if (!damageInfo.missed && damageInfo.damage > 0) {
                    ctx.processOnHitProcs(session, data.targetId, damageInfo.damage, (damageInfo.damageType || 'physical') === 'physical');
                }
                if (player.stats.health <= 0) {
                    ctx.handlePlayerDeath(player);
                }
            }
        }
        else {
            if (!damageInfo.missed && damageInfo.damage > 0) {
                ctx.processGloomRecoil(session);
            }
            ctx.broadcastInZone(session.zoneId, {
                type: shared_1.PacketType.DAMAGE,
                timestamp: Date.now(),
                data: { ...damageInfo }
            });
        }
        if (enemy) {
            if (damageInfo.elementalDamage) {
                for (const el of damageInfo.elementalDamage) {
                    ctx.damageEnemy(enemy, el.damage, characterId);
                }
            }
            if (!damageInfo.missed && damageInfo.damage > 0) {
                ctx.enmity.addDamageEnmity(enemy, characterId, damageInfo.damage);
                if (enemy.health > 0) {
                    ctx.processOnHitProcs(session, data.targetId, damageInfo.damage, true);
                }
            }
            else if (damageInfo.missed) {
                ctx.enmity.addEnmity(enemy, characterId, 50, 0);
            }
            ctx.broadcastInZone(session.zoneId, {
                type: shared_1.PacketType.STATS_UPDATE,
                timestamp: Date.now(),
                data: { entityId: data.targetId, health: enemy.health, maxHealth: enemy.maxHealth }
            });
        }
    }
}
function handleManualAttack(ctx, socket, data) {
    const characterId = ctx.findCharacterBySocket(socket.id);
    if (!characterId)
        return;
    const session = ctx.state.players.get(characterId);
    if (!session || session.isDead)
        return;
    if (session.currentNpcId)
        return;
    ctx.cancelRest(session);
    ctx.broadcastInZone(session.zoneId, {
        type: shared_1.PacketType.ENTITY_ANIMATION,
        timestamp: Date.now(),
        data: { entityId: characterId, animation: 'Attack' }
    }, characterId);
    const zoneEnemies = ctx.spawnMgr.getEnemiesInZone(session.zoneId) || new Map();
    const zonePlayerBuf = new Map();
    if ((0, shared_1.isZonePvpEnabled)(session.zoneId)) {
        ctx.forEachPlayerInZone(session.zoneId, (id, p) => zonePlayerBuf.set(id, p));
    }
    const results = ctx.combat.processManualAttack(session, data.facingAngle, zoneEnemies, zonePlayerBuf, session.zoneId).filter((r) => !ctx.state.players.has(r.targetId) || r.targetId === characterId || !ctx.isPartyMember(characterId, r.targetId));
    for (const info of results) {
        const enemy = ctx.spawnMgr.getEnemy(info.targetId);
        const pTarget = ctx.state.players.get(info.targetId);
        if (pTarget && info.targetId !== characterId) {
            const manualTotal = info.damage + (info.elementalDamage?.reduce((s, e) => s + e.damage, 0) || 0);
            const manualDmgResult = ctx.applyPlayerDamage(pTarget, manualTotal, characterId, info.damageType || 'physical', info.isCritical || false, session.zoneId, session.position);
            if (!info.missed && info.damage > 0) {
                ctx.processGloomRecoil(session);
            }
            ctx.broadcastInZone(session.zoneId, {
                type: shared_1.PacketType.DAMAGE,
                timestamp: Date.now(),
                data: { ...info, damage: manualDmgResult.redirected ? 0 : manualDmgResult.damageTaken, missed: manualDmgResult.redirected ? true : info.missed }
            });
            if (!manualDmgResult.redirected) {
                ctx.sendToPlayer(info.targetId, {
                    type: shared_1.PacketType.STATS_UPDATE,
                    timestamp: Date.now(),
                    data: { characterId: info.targetId, stats: pTarget.stats, statBreakdown: pTarget.statBreakdown, skillProficiencies: pTarget.skillProficiencies, skillAdeptness: pTarget.skillAdeptness }
                });
                if (!info.missed && info.damage > 0) {
                    ctx.processOnHitProcs(session, info.targetId, info.damage, (info.damageType || 'physical') === 'physical');
                }
                if (pTarget.stats.health <= 0) {
                    ctx.handlePlayerDeath(pTarget);
                }
            }
        }
        else {
            if (!info.missed && info.damage > 0) {
                ctx.processGloomRecoil(session);
            }
            ctx.broadcastInZone(session.zoneId, {
                type: shared_1.PacketType.DAMAGE,
                timestamp: Date.now(),
                data: { ...info }
            });
        }
        if (enemy) {
            if (!info.missed && info.damage > 0) {
                const manualTotalDmg = info.damage + (info.elementalDamage?.reduce((s, e) => s + e.damage, 0) || 0);
                ctx.enmity.addDamageEnmity(enemy, characterId, manualTotalDmg);
                if (enemy.health > 0) {
                    ctx.processOnHitProcs(session, info.targetId, info.damage, true);
                }
            }
            else if (info.missed) {
                ctx.enmity.addEnmity(enemy, characterId, 50, 0);
            }
            ctx.broadcastInZone(session.zoneId, {
                type: shared_1.PacketType.STATS_UPDATE,
                timestamp: Date.now(),
                data: { entityId: info.targetId, health: enemy.health, maxHealth: enemy.maxHealth }
            });
        }
    }
}
