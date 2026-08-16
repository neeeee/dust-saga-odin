"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SummonManager = void 0;
const uuid_1 = require("uuid");
const shared_1 = require("@dust-saga/shared");
class SummonManager {
    constructor() {
        this.summons = new Map();
        this.ownerIndex = new Map();
        this.zoneIndex = new Map();
    }
    spawnSummon(ownerId, ownerName, zoneId, summonObj, position, rotation, element) {
        const summonType = summonObj.objectType;
        this.enforceLimits(ownerId, summonType);
        const baseStats = shared_1.SUMMON_STATS[summonType];
        const now = Date.now() / 1000;
        const summon = {
            id: (0, uuid_1.v4)(),
            ownerId,
            ownerName,
            summonType,
            position: { ...position },
            spawnPosition: { ...position },
            rotation,
            health: summonObj.hp ?? baseStats.hp,
            maxHealth: summonObj.hp ?? baseStats.hp,
            defense: summonObj.defense ?? baseStats.defense,
            element,
            attackDamage: summonObj.attackDamage ?? summonObj.aoeDamage ?? baseStats.attackDamage,
            attackRange: summonObj.attackRange ?? baseStats.attackRange,
            attackCooldown: summonObj.attackCooldown ?? baseStats.attackCooldown,
            lastAttackTime: 0,
            duration: summonObj.duration,
            spawnedAt: now,
            targetId: null,
            state: summonType === shared_1.SummonType.WALL ? 'idle' : 'follow',
            zoneId,
            wanderTarget: null,
            wanderCooldown: 0,
        };
        this.summons.set(summon.id, summon);
        if (!this.ownerIndex.has(ownerId))
            this.ownerIndex.set(ownerId, []);
        this.ownerIndex.get(ownerId).push(summon.id);
        if (!this.zoneIndex.has(zoneId))
            this.zoneIndex.set(zoneId, new Set());
        this.zoneIndex.get(zoneId).add(summon.id);
        return summon;
    }
    enforceLimits(ownerId, summonType) {
        const owned = this.ownerIndex.get(ownerId) || [];
        if (summonType === shared_1.SummonType.WALL) {
            const existing = owned.find(id => this.summons.get(id)?.summonType === shared_1.SummonType.WALL);
            if (existing)
                this.despawnSummon(existing);
            return;
        }
        if (summonType === shared_1.SummonType.PLANT) {
            const plants = owned.filter(id => this.summons.get(id)?.summonType === shared_1.SummonType.PLANT);
            if (plants.length >= shared_1.MAX_PLANTS) {
                this.despawnSummon(plants[0]);
            }
            return;
        }
        if (summonType === shared_1.SummonType.WYVERN || summonType === shared_1.SummonType.TURTLE) {
            for (const id of [...owned]) {
                const s = this.summons.get(id);
                if (s && shared_1.COMBAT_SUMMON_TYPES.includes(s.summonType)) {
                    this.despawnSummon(id);
                }
            }
        }
    }
    despawnSummon(summonId) {
        const summon = this.summons.get(summonId);
        if (!summon)
            return;
        this.summons.delete(summonId);
        const owned = this.ownerIndex.get(summon.ownerId);
        if (owned) {
            const idx = owned.indexOf(summonId);
            if (idx !== -1)
                owned.splice(idx, 1);
            if (owned.length === 0)
                this.ownerIndex.delete(summon.ownerId);
        }
        const zoneSet = this.zoneIndex.get(summon.zoneId);
        if (zoneSet) {
            zoneSet.delete(summonId);
            if (zoneSet.size === 0)
                this.zoneIndex.delete(summon.zoneId);
        }
    }
    despawnAllForOwner(ownerId) {
        const owned = this.ownerIndex.get(ownerId);
        if (!owned)
            return [];
        const despawned = [...owned];
        for (const id of despawned) {
            this.despawnSummon(id);
        }
        return despawned;
    }
    getSummon(summonId) {
        return this.summons.get(summonId);
    }
    getSummonsInZone(zoneId) {
        const ids = this.zoneIndex.get(zoneId);
        if (!ids)
            return [];
        const result = [];
        for (const id of ids) {
            const s = this.summons.get(id);
            if (s)
                result.push(s);
        }
        return result;
    }
    getSummonsForOwner(ownerId) {
        const owned = this.ownerIndex.get(ownerId);
        if (!owned)
            return [];
        const result = [];
        for (const id of owned) {
            const s = this.summons.get(id);
            if (s)
                result.push(s);
        }
        return result;
    }
    damageSummon(id, damage) {
        const summon = this.summons.get(id);
        if (!summon)
            return false;
        summon.health = Math.max(0, summon.health - damage);
        return summon.health <= 0;
    }
    getSummonsInRadius(zoneId, center, radius) {
        const zoneSummons = this.getSummonsInZone(zoneId);
        const rSq = radius * radius;
        return zoneSummons.filter(s => {
            const dx = s.position.x - center.x;
            const dz = s.position.z - center.z;
            return dx * dx + dz * dz <= rSq;
        });
    }
    tickExpired() {
        const now = Date.now() / 1000;
        const expired = [];
        for (const [id, summon] of this.summons) {
            if (now - summon.spawnedAt >= summon.duration) {
                expired.push({ id, zoneId: summon.zoneId });
            }
        }
        for (const { id } of expired) {
            this.despawnSummon(id);
        }
        return expired;
    }
    tick(now, deps) {
        const expired = this.tickExpired();
        for (const info of expired) {
            deps.broadcastInZone(info.zoneId, {
                type: shared_1.PacketType.ENTITY_DESPAWN,
                timestamp: Date.now(),
                data: { entityId: info.id },
            });
        }
        const nowSec = now / 1000;
        const spawnMgr = deps.getSpawnManager();
        for (const zoneId of spawnMgr.getZoneIds()) {
            const summons = this.getSummonsInZone(zoneId);
            if (summons.length === 0)
                continue;
            const zoneEnemies = spawnMgr.getEnemiesInZone(zoneId);
            for (const summon of summons) {
                if (summon.health <= 0) {
                    this.despawnSummon(summon.id);
                    deps.broadcastInZone(zoneId, {
                        type: shared_1.PacketType.ENTITY_DESPAWN,
                        timestamp: Date.now(),
                        data: { entityId: summon.id },
                    });
                    continue;
                }
                if (summon.summonType === 'plant') {
                    this.tickPlantAttack(summon, zoneEnemies, nowSec, deps);
                }
                else if (summon.summonType === 'wyvern') {
                    this.tickWyvern(summon, zoneEnemies, nowSec, deps);
                }
                else if (summon.summonType === 'turtle') {
                    this.tickTurtleEarthquake(summon, zoneEnemies, nowSec, deps);
                }
            }
        }
    }
    tickPlantAttack(summon, zoneEnemies, nowSec, deps) {
        if (nowSec - summon.lastAttackTime < summon.attackCooldown)
            return;
        let closestId = null;
        let closestDistSq = summon.attackRange * summon.attackRange;
        for (const [enemyId, enemy] of zoneEnemies) {
            if (enemy.state === 'dead')
                continue;
            const dx = enemy.position.x - summon.position.x;
            const dz = enemy.position.z - summon.position.z;
            const distSq = dx * dx + dz * dz;
            if (distSq < closestDistSq) {
                closestDistSq = distSq;
                closestId = enemyId;
            }
        }
        if (!closestId)
            return;
        summon.lastAttackTime = nowSec;
        const enemy = zoneEnemies.get(closestId);
        const enemyDef = deps.getEnemyEffectiveDefense(enemy);
        const damage = Math.max(1, summon.attackDamage - Math.floor(enemyDef * 0.5));
        const { died } = deps.damageEnemy(enemy, damage, summon.ownerId);
        deps.getEnmity().addDamageEnmity(enemy, summon.id, damage);
        deps.broadcastInZone(summon.zoneId, {
            type: shared_1.PacketType.ATTACK,
            timestamp: Date.now(),
            data: {
                attackerId: summon.id,
                targetId: closestId,
                damage,
                isCritical: false,
                damageType: summon.element || 'physical',
            },
        });
        if (died) {
            deps.handleEnemyKill(closestId, summon.ownerId);
        }
    }
    tickWyvern(summon, zoneEnemies, nowSec, deps) {
        const WANDER_RADIUS = 10;
        const dt = 1 / deps.getTickRate();
        const speed = shared_1.SUMMON_STATS[summon.summonType].speed;
        if (summon.wanderTarget) {
            const wdx = summon.wanderTarget.x - summon.position.x;
            const wdz = summon.wanderTarget.z - summon.position.z;
            const wDist = Math.sqrt(wdx * wdx + wdz * wdz);
            if (wDist > 1) {
                summon.position.x += (wdx / wDist) * speed * dt;
                summon.position.z += (wdz / wDist) * speed * dt;
                summon.rotation = Math.atan2(wdx, wdz);
            }
            else {
                summon.wanderTarget = null;
                summon.wanderCooldown = nowSec + 0.5 + Math.random() * 1.5;
            }
        }
        else if (nowSec >= summon.wanderCooldown) {
            const angle = Math.random() * Math.PI * 2;
            const dist = 3 + Math.random() * (WANDER_RADIUS - 3);
            summon.wanderTarget = {
                x: summon.spawnPosition.x + Math.cos(angle) * dist,
                z: summon.spawnPosition.z + Math.sin(angle) * dist,
            };
        }
        if (nowSec - summon.lastAttackTime < summon.attackCooldown)
            return;
        const aoeRange = summon.attackRange;
        const aoeRangeSq = aoeRange * aoeRange;
        const hitEnemies = [];
        for (const [enemyId, enemy] of zoneEnemies) {
            if (enemy.state === 'dead')
                continue;
            const dx = enemy.position.x - summon.position.x;
            const dz = enemy.position.z - summon.position.z;
            const distSq = dx * dx + dz * dz;
            if (distSq <= aoeRangeSq) {
                hitEnemies.push({ id: enemyId, enemy, distSq });
            }
        }
        if (hitEnemies.length === 0)
            return;
        summon.lastAttackTime = nowSec;
        deps.broadcastInZone(summon.zoneId, {
            type: shared_1.PacketType.ATTACK,
            timestamp: Date.now(),
            data: {
                attackerId: summon.id,
                targetId: null,
                damage: summon.attackDamage,
                isCritical: false,
                damageType: 'fire',
                aoeRadius: aoeRange,
            },
        });
        for (const { id, enemy } of hitEnemies) {
            const enemyDef = deps.getEnemyEffectiveDefense(enemy);
            const damage = Math.max(1, summon.attackDamage - Math.floor(enemyDef * 0.5));
            const { died } = deps.damageEnemy(enemy, damage, summon.ownerId);
            deps.getEnmity().addDamageEnmity(enemy, summon.id, damage);
            deps.broadcastInZone(summon.zoneId, {
                type: shared_1.PacketType.DAMAGE,
                timestamp: Date.now(),
                data: {
                    attackerId: summon.id,
                    targetId: id,
                    damage,
                    isCritical: false,
                    damageType: 'fire',
                },
            });
            const burnDuration = 5;
            enemy.statusEffects = enemy.statusEffects.filter(e => e.type !== shared_1.StatusEffectType.BURN);
            enemy.statusEffects.push({
                id: `burn_${id}_${Date.now()}`,
                type: shared_1.StatusEffectType.BURN,
                sourceId: summon.ownerId,
                targetId: id,
                potency: 0,
                appliedAt: Date.now(),
                duration: burnDuration * 1000,
                tickInterval: 1000,
                lastTickAt: Date.now(),
                stacks: 1,
                skillName: 'Wyvern Fire',
            });
            deps.broadcastInZone(summon.zoneId, {
                type: shared_1.PacketType.ENTITY_STATUS_EFFECTS,
                timestamp: Date.now(),
                data: { entityId: id, effects: enemy.statusEffects }
            });
            if (died) {
                deps.handleEnemyKill(id, summon.ownerId);
            }
        }
    }
    tickTurtleEarthquake(summon, zoneEnemies, nowSec, deps) {
        if (nowSec - summon.lastAttackTime < summon.attackCooldown)
            return;
        const aoeRange = summon.attackRange;
        const aoeRangeSq = aoeRange * aoeRange;
        const hitEnemies = [];
        for (const [enemyId, enemy] of zoneEnemies) {
            if (enemy.state === 'dead')
                continue;
            const dx = enemy.position.x - summon.position.x;
            const dz = enemy.position.z - summon.position.z;
            const distSq = dx * dx + dz * dz;
            if (distSq <= aoeRangeSq) {
                hitEnemies.push({ id: enemyId, enemy });
            }
        }
        if (hitEnemies.length === 0)
            return;
        summon.lastAttackTime = nowSec;
        const baseDamage = summon.attackDamage;
        deps.broadcastInZone(summon.zoneId, {
            type: shared_1.PacketType.ATTACK,
            timestamp: Date.now(),
            data: {
                attackerId: summon.id,
                targetId: null,
                damage: baseDamage,
                isCritical: false,
                damageType: 'physical',
                aoeRadius: aoeRange,
            },
        });
        for (const { id, enemy } of hitEnemies) {
            const enemyDef = deps.getEnemyEffectiveDefense(enemy);
            const damage = Math.max(1, baseDamage - Math.floor(enemyDef * 0.5));
            const { died } = deps.damageEnemy(enemy, damage, summon.ownerId);
            deps.getEnmity().addDamageEnmity(enemy, summon.id, damage);
            deps.broadcastInZone(summon.zoneId, {
                type: shared_1.PacketType.DAMAGE,
                timestamp: Date.now(),
                data: {
                    attackerId: summon.id,
                    targetId: id,
                    damage,
                    isCritical: false,
                    damageType: 'physical',
                },
            });
            const stunEffect = {
                id: `stun_${id}_${Date.now()}`,
                type: shared_1.StatusEffectType.STUN,
                sourceId: summon.ownerId,
                targetId: id,
                potency: 0,
                appliedAt: Date.now(),
                duration: 1000,
                tickInterval: 0,
                lastTickAt: Date.now(),
                stacks: 1,
                skillName: 'Turtle Earthquake',
                debuffCategory: 'stun',
            };
            if (deps.shouldApplyDebuff(stunEffect, id, summon.ownerId)) {
                enemy.statusEffects = enemy.statusEffects.filter(e => e.type !== shared_1.StatusEffectType.STUN);
                enemy.statusEffects.push(stunEffect);
                deps.broadcastInZone(summon.zoneId, {
                    type: shared_1.PacketType.ENTITY_STATUS_EFFECTS,
                    timestamp: Date.now(),
                    data: { entityId: id, effects: enemy.statusEffects }
                });
            }
            if (died) {
                deps.handleEnemyKill(id, summon.ownerId);
            }
        }
    }
}
exports.SummonManager = SummonManager;
