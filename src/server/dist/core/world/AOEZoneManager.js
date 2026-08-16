"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.AOEZoneManager = void 0;
const uuid_1 = require("uuid");
const shared_1 = require("@dust-saga/shared");
class AOEZoneManager {
    constructor(deps) {
        this.deps = deps;
        this.activeAOEZones = new Map();
    }
    spawnAOEZone(session, skillName, position, radius) {
        const skill = this.deps.getSkillSystem().findSkillDefinition(skillName);
        const totalPulses = skill?.pulseCount || 1;
        const pulseInterval = skill?.pulseInterval || 1000;
        const now = Date.now();
        let expiresAt;
        if (skill && skill.duration > 0) {
            expiresAt = skill.duration * 1000 + now;
        }
        else {
            expiresAt = now + pulseInterval * (totalPulses - 1) + 1500;
        }
        const id = (0, uuid_1.v4)();
        const zone = {
            id,
            casterId: session.characterId,
            zoneId: session.zoneId,
            skillName,
            position,
            radius,
            pulseInterval,
            remainingPulses: totalPulses,
            lastPulseAt: now,
            expiresAt,
            entitiesInside: new Map(),
        };
        for (const [enemyId, enemy] of this.deps.getSpawnManager().getEnemiesInZone(session.zoneId) ?? []) {
            if (enemy.state === 'dead')
                continue;
            const dx = enemy.position.x - position.x;
            const dz = enemy.position.z - position.z;
            if (Math.sqrt(dx * dx + dz * dz) <= radius) {
                zone.entitiesInside.set(enemyId, now);
            }
        }
        for (const [pid, player] of this.deps.getPlayers()) {
            if (pid === session.characterId)
                continue;
            if (player.zoneId !== session.zoneId)
                continue;
            if (player.stats.health <= 0 || !player.position)
                continue;
            const dx = player.position.x - position.x;
            const dz = player.position.z - position.z;
            if (Math.sqrt(dx * dx + dz * dz) <= radius) {
                zone.entitiesInside.set(pid, now);
            }
        }
        this.activeAOEZones.set(id, zone);
        this.deps.broadcastInZone(session.zoneId, {
            type: shared_1.PacketType.AOE_ENTITY,
            timestamp: Date.now(),
            data: {
                id,
                type: 'aoe',
                position,
                rotation: { x: 0, y: 0, z: 0, w: 1 },
                data: { skillName, radius, expiresAt: zone.expiresAt },
            }
        });
    }
    removeAOEZone(zoneId) {
        const zone = this.activeAOEZones.get(zoneId);
        if (!zone)
            return;
        this.activeAOEZones.delete(zoneId);
        this.deps.broadcastInZone(zone.zoneId, {
            type: shared_1.PacketType.AOE_DESPAWN,
            timestamp: Date.now(),
            data: { entityId: zoneId }
        });
    }
    tickAOEZones(now) {
        const entries = [...this.activeAOEZones.entries()];
        for (const [zoneId, zone] of entries) {
            if (now >= zone.expiresAt || zone.remainingPulses <= 0) {
                this.removeAOEZone(zoneId);
                continue;
            }
            const caster = this.deps.getPlayers().get(zone.casterId);
            if (!caster || caster.isDead) {
                this.removeAOEZone(zoneId);
                continue;
            }
            if (zone.remainingPulses <= 0)
                continue;
            const lastPulse = zone.lastPulseAt || 0;
            if (now - lastPulse < zone.pulseInterval)
                continue;
            this.deps.applyAOEDamageToTargets(caster, zone.skillName, zone.position, zone.radius);
            zone.lastPulseAt = now;
            zone.remainingPulses--;
        }
    }
    /** Despawn all AOE zones cast by a character (used on disconnect). */
    cleanupOwner(casterId) {
        for (const [zoneId, zone] of this.activeAOEZones) {
            if (zone.casterId === casterId) {
                this.removeAOEZone(zoneId);
            }
        }
    }
    checkEntityAOEEntries(entityId, position, entityZoneId) {
        for (const [, zone] of this.activeAOEZones) {
            if (zone.zoneId !== entityZoneId)
                continue;
            const dx = position.x - zone.position.x;
            const dz = position.z - zone.position.z;
            const dist = Math.sqrt(dx * dx + dz * dz);
            const wasInside = zone.entitiesInside.has(entityId);
            const isInside = dist <= zone.radius;
            if (isInside && !wasInside) {
                zone.entitiesInside.set(entityId, Date.now());
                const caster = this.deps.getPlayers().get(zone.casterId);
                if (caster) {
                    this.deps.onEntityEnterAOE(caster, zone.skillName, entityId, zone.position, zone.radius);
                }
            }
            else if (!isInside && wasInside) {
                zone.entitiesInside.delete(entityId);
            }
        }
    }
    /** Per-tick: detect entities that have newly entered any active AOE zone. */
    tickEntityAOEEntries() {
        if (this.activeAOEZones.size === 0)
            return;
        const spawnMgr = this.deps.getSpawnManager();
        for (const zoneId of spawnMgr.getZoneIds()) {
            const zoneEnemies = spawnMgr.getEnemiesInZone(zoneId);
            if (!zoneEnemies)
                continue;
            for (const [enemyId, enemy] of zoneEnemies) {
                if (enemy.state === 'dead')
                    continue;
                this.checkEntityAOEEntries(enemyId, enemy.position, zoneId);
            }
        }
    }
}
exports.AOEZoneManager = AOEZoneManager;
