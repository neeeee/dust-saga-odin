"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.AISystem = void 0;
const EntityManager_1 = require("../EntityManager");
const shared_1 = require("@dust-saga/shared");
const shared_2 = require("@dust-saga/shared");
class AISystem extends EntityManager_1.System {
    constructor(entityManager) {
        super(entityManager);
        this.attackCallbacks = [];
        this.attackSummonCallbacks = [];
        this.respawnCallbacks = [];
        this.aggroCallbacks = [];
        this.enmitySys = null;
    }
    static hashId(id) {
        let hash = 0;
        for (let i = 0; i < id.length; i++) {
            hash = ((hash << 5) - hash + id.charCodeAt(i)) | 0;
        }
        return Math.abs(hash);
    }
    onEnemyAttack(callback) {
        this.attackCallbacks.push(callback);
    }
    onEnemyAttackSummon(callback) {
        this.attackSummonCallbacks.push(callback);
    }
    onEnemyRespawn(callback) {
        this.respawnCallbacks.push(callback);
    }
    onEnemyAggro(callback) {
        this.aggroCallbacks.push(callback);
    }
    getSpeedMultiplier(enemy) {
        let multiplier = 1;
        const now = Date.now();
        for (const effect of enemy.statusEffects || []) {
            if (effect.appliedAt + effect.duration < now)
                continue;
            if (effect.type === shared_1.StatusEffectType.DEBUFF_SPEED_DOWN) {
                multiplier *= (1 - (effect.potency || 0.15));
            }
            else if (effect.type === shared_1.StatusEffectType.SLOW) {
                multiplier *= (1 - (effect.potency || 0.3));
            }
            else if (effect.type === shared_1.StatusEffectType.ROOT || effect.type === shared_1.StatusEffectType.FREEZE || effect.type === shared_1.StatusEffectType.STUN) {
                return 0;
            }
        }
        return Math.max(0, multiplier);
    }
    moveEntity(enemy, target, speed) {
        const dx = target.x - enemy.position.x;
        const dz = target.z - enemy.position.z;
        const dist = Math.sqrt(dx * dx + dz * dz);
        if (dist > 0.01) {
            enemy.position.x += (dx / dist) * speed;
            enemy.position.z += (dz / dist) * speed;
            enemy.rotation = Math.atan2(dx, dz);
        }
    }
    pickAggroTarget(enemy, players, summons, aggroRange, strategy) {
        const candidates = [];
        for (const [, player] of players) {
            const dist = (0, shared_1.distance2D)(enemy.position, player.position);
            if (dist < aggroRange) {
                candidates.push({ characterId: player.characterId, position: player.position, dist });
            }
        }
        for (const [, summon] of summons) {
            const dist = (0, shared_1.distance2D)(enemy.position, summon.position);
            if (dist < aggroRange) {
                candidates.push({ characterId: summon.summonId, position: summon.position, dist, isSummon: true });
            }
        }
        if (candidates.length === 0)
            return null;
        switch (strategy) {
            case 'closest':
                candidates.sort((a, b) => a.dist - b.dist);
                return candidates[0];
            case 'lowestHp':
                const playerMap = this['entityManager'];
                candidates.sort((a, b) => {
                    const pA = playerMap?.players?.get?.(a.characterId);
                    const pB = playerMap?.players?.get?.(b.characterId);
                    return (pA?.stats?.health ?? 999999) - (pB?.stats?.health ?? 999999);
                });
                return candidates[0];
            case 'first':
            default:
                return candidates[0];
        }
    }
    pickPatrolIndex(enemy, strategy) {
        if (strategy === 'sequential') {
            return (enemy.currentPatrolIndex + 1) % enemy.patrolPoints.length;
        }
        return Math.floor(Math.random() * enemy.patrolPoints.length);
    }
    findPlayerTarget(players, targetId) {
        return players.get(targetId)?.position || null;
    }
    findSummonTarget(summons, targetId) {
        return summons.get(targetId)?.position || null;
    }
    resolveTargetPosition(targetId, players, summons) {
        return this.findPlayerTarget(players, targetId) || this.findSummonTarget(summons, targetId);
    }
    /**
     * Decision pass: state transitions, aggro detection, enmity decay, target
     * selection. Staggered (1/N enemies per tick) for CPU savings — this is the
     * expensive part (scanning players, linked aggro, etc.).
     */
    updateDecisions(enemies, players, summons, deltaTime, staggerBucket, staggerMod) {
        const hasStagger = staggerBucket !== undefined && staggerMod !== undefined && staggerMod > 0;
        enemies.forEach((enemy, id) => {
            if (hasStagger && AISystem.hashId(id) % staggerMod !== staggerBucket)
                return;
            if (enemy.state === 'dead') {
                this.checkRespawn(enemy);
                return;
            }
            const def = (0, shared_2.getEnemyDefinition)(enemy.enemyType);
            if (!def)
                return;
            switch (enemy.state) {
                case 'idle':
                    this.decideIdle(enemy, enemies, players, summons, def);
                    break;
                case 'patrol':
                    this.decidePatrol(enemy, enemies, players, summons, def);
                    break;
                case 'chase':
                    this.decideChase(enemy, players, summons, def, deltaTime);
                    break;
                case 'attack':
                    this.decideAttack(enemy, players, summons, def, deltaTime);
                    break;
                case 'return':
                    this.decideReturn(enemy, enemies, players, summons, def, deltaTime);
                    break;
            }
        });
    }
    /**
     * Movement pass: move entities toward their targets based on current state.
     * Runs every tick for ALL enemies — cheap (just math), ensures smooth
     * movement instead of step-wise jumps from the staggered decision pass.
     */
    updateMovement(enemies, players, summons, deltaTime) {
        enemies.forEach((enemy) => {
            if (enemy.state === 'dead')
                return;
            const def = (0, shared_2.getEnemyDefinition)(enemy.enemyType);
            if (!def)
                return;
            switch (enemy.state) {
                case 'patrol':
                    this.movePatrol(enemy, def, deltaTime);
                    break;
                case 'chase':
                    this.moveChase(enemy, players, summons, def, deltaTime);
                    break;
                case 'attack':
                    this.performAttack(enemy, players, summons, def);
                    break;
                case 'return':
                    this.moveReturn(enemy, def, deltaTime);
                    break;
            }
        });
    }
    transitionTo(enemy, state) {
        if (state === 'dead' || state === enemy.state)
            return;
        enemy.state = state;
        if (state === 'idle') {
            enemy.targetId = null;
        }
    }
    checkLinkedAggro(enemy, enemies, players, summons, linkRange) {
        for (const [, other] of enemies) {
            if (other.id === enemy.id)
                continue;
            if (other.enemyType !== enemy.enemyType)
                continue;
            if (other.state !== 'chase' && other.state !== 'attack')
                continue;
            if (!other.targetId)
                continue;
            const dist = (0, shared_1.distance2D)(enemy.position, other.position);
            if (dist > linkRange)
                continue;
            const targetPos = this.resolveTargetPosition(other.targetId, players, summons);
            if (!targetPos)
                continue;
            enemy.state = 'chase';
            enemy.targetId = other.targetId;
            if (this.enmitySys) {
                this.enmitySys.addEnmity(enemy, other.targetId, 1, 0);
            }
            return true;
        }
        return false;
    }
    tryEngageFromEnmity(enemy, players, summons) {
        if (!this.enmitySys || !enemy.enmityTable || Object.keys(enemy.enmityTable).length === 0)
            return false;
        const topTarget = this.enmitySys.getTopTarget(enemy);
        if (!topTarget)
            return false;
        const targetPos = this.resolveTargetPosition(topTarget.characterId, players, summons);
        if (!targetPos)
            return false;
        enemy.state = 'chase';
        enemy.targetId = topTarget.characterId;
        return true;
    }
    // ── Decision handlers (staggered) ─────────────────────────────────────────
    decideIdle(enemy, enemies, players, summons, def) {
        if (!def)
            return;
        if (def.aggroRange > 0 && this.tryEngageFromEnmity(enemy, players, summons))
            return;
        if (def.aggroRange > 0 && this.checkLinkedAggro(enemy, enemies, players, summons, def.aggroRange))
            return;
        const target = this.pickAggroTarget(enemy, players, summons, def.aggroRange, def.aggroStrategy || 'first');
        if (target) {
            enemy.state = 'chase';
            enemy.targetId = target.characterId;
            this.aggroCallbacks.forEach(cb => cb(enemy.id, enemy.enemyType, target.characterId, { ...enemy.position }, { ...enemy.spawnPosition }));
            return;
        }
        if (Math.random() < 0.01 && enemy.patrolPoints.length > 0) {
            this.transitionTo(enemy, 'patrol');
            enemy.currentPatrolIndex = this.pickPatrolIndex(enemy, def.patrolStrategy || 'random');
        }
    }
    decidePatrol(enemy, enemies, players, summons, def) {
        if (!def || enemy.patrolPoints.length === 0) {
            this.transitionTo(enemy, 'idle');
            return;
        }
        if (def.aggroRange > 0 && this.tryEngageFromEnmity(enemy, players, summons))
            return;
        if (def.aggroRange > 0 && this.checkLinkedAggro(enemy, enemies, players, summons, def.aggroRange))
            return;
        const target = enemy.patrolPoints[enemy.currentPatrolIndex];
        const dist = (0, shared_1.distance2D)(enemy.position, target);
        if (dist < 1) {
            enemy.currentPatrolIndex = this.pickPatrolIndex(enemy, def.patrolStrategy || 'random');
            this.transitionTo(enemy, 'idle');
        }
    }
    decideChase(enemy, players, summons, def, deltaTime) {
        if (!def || !enemy.targetId) {
            this.transitionTo(enemy, 'return');
            return;
        }
        if (def.leashRange > 0 && (0, shared_1.distance2D)(enemy.position, enemy.spawnPosition) > def.leashRange) {
            if (this.enmitySys)
                this.enmitySys.clearEnmity(enemy);
            enemy.targetId = null;
            this.transitionTo(enemy, 'return');
            return;
        }
        if (this.enmitySys) {
            this.enmitySys.decay(enemy, deltaTime, true);
            const topTarget = this.enmitySys.getTopTarget(enemy);
            if (topTarget && topTarget.characterId !== enemy.targetId) {
                const newTarget = this.resolveTargetPosition(topTarget.characterId, players, summons);
                if (newTarget) {
                    enemy.targetId = topTarget.characterId;
                }
            }
        }
        const targetPos = this.resolveTargetPosition(enemy.targetId, players, summons);
        if (!targetPos) {
            this.transitionTo(enemy, 'return');
            return;
        }
        const dist = (0, shared_1.distance2D)(enemy.position, targetPos);
        if (dist <= def.attackRange) {
            this.transitionTo(enemy, 'attack');
        }
    }
    decideAttack(enemy, players, summons, def, deltaTime) {
        if (!def || !enemy.targetId) {
            this.transitionTo(enemy, 'return');
            return;
        }
        if (def.leashRange > 0 && (0, shared_1.distance2D)(enemy.position, enemy.spawnPosition) > def.leashRange) {
            if (this.enmitySys)
                this.enmitySys.clearEnmity(enemy);
            enemy.targetId = null;
            this.transitionTo(enemy, 'return');
            return;
        }
        if (this.enmitySys) {
            this.enmitySys.decay(enemy, deltaTime, true);
            const topTarget = this.enmitySys.getTopTarget(enemy);
            if (topTarget && topTarget.characterId !== enemy.targetId) {
                const newTarget = this.resolveTargetPosition(topTarget.characterId, players, summons);
                if (newTarget) {
                    enemy.targetId = topTarget.characterId;
                }
            }
        }
        const targetPos = this.resolveTargetPosition(enemy.targetId, players, summons);
        if (!targetPos) {
            this.transitionTo(enemy, 'return');
            return;
        }
        const dist = (0, shared_1.distance2D)(enemy.position, targetPos);
        if (dist > def.attackRange * 1.5) {
            this.transitionTo(enemy, 'chase');
        }
    }
    decideReturn(enemy, enemies, players, summons, def, deltaTime) {
        if (!def)
            return;
        if (def.aggroRange > 0 && this.tryEngageFromEnmity(enemy, players, summons))
            return;
        if (def.aggroRange > 0 && this.checkLinkedAggro(enemy, enemies, players, summons, def.aggroRange))
            return;
        if (this.enmitySys) {
            this.enmitySys.decay(enemy, deltaTime, false);
        }
        const dist = (0, shared_1.distance2D)(enemy.position, enemy.spawnPosition);
        if (dist < 1) {
            if (this.enmitySys) {
                this.enmitySys.clearEnmity(enemy);
            }
            this.transitionTo(enemy, 'idle');
            const def2 = (0, shared_2.getEnemyDefinition)(enemy.enemyType);
            if (def2) {
                enemy.health = def2.health;
                enemy.statusEffects = [];
            }
        }
    }
    // ── Movement handlers (every tick) ─────────────────────────────────────────
    movePatrol(enemy, def, deltaTime) {
        if (!def || enemy.patrolPoints.length === 0)
            return;
        const target = enemy.patrolPoints[enemy.currentPatrolIndex];
        const speed = (def.patrolSpeed || 1) * deltaTime * this.getSpeedMultiplier(enemy);
        this.moveEntity(enemy, target, speed);
    }
    moveChase(enemy, players, summons, def, deltaTime) {
        if (!def || !enemy.targetId)
            return;
        const targetPos = this.resolveTargetPosition(enemy.targetId, players, summons);
        if (!targetPos)
            return;
        const dist = (0, shared_1.distance2D)(enemy.position, targetPos);
        if (dist <= def.attackRange)
            return;
        const speed = def.speed * deltaTime * this.getSpeedMultiplier(enemy);
        this.moveEntity(enemy, targetPos, speed);
    }
    performAttack(enemy, players, summons, def) {
        if (!def || !enemy.targetId)
            return;
        const targetPos = this.resolveTargetPosition(enemy.targetId, players, summons);
        if (!targetPos)
            return;
        const dist = (0, shared_1.distance2D)(enemy.position, targetPos);
        if (dist > def.attackRange * 1.5)
            return;
        enemy.rotation = Math.atan2(targetPos.x - enemy.position.x, targetPos.z - enemy.position.z);
        const now = Date.now();
        const cooldown = def.attackCooldown || 1000;
        if (now - enemy.lastAttackTime >= cooldown) {
            enemy.lastAttackTime = now;
            const isSummon = summons.has(enemy.targetId);
            if (isSummon) {
                this.attackSummonCallbacks.forEach(cb => cb(enemy.id, enemy.targetId, def.attack));
            }
            else {
                this.attackCallbacks.forEach(cb => cb(enemy.id, enemy.targetId, def.attack));
            }
        }
    }
    moveReturn(enemy, def, deltaTime) {
        if (!def)
            return;
        const speed = def.speed * 1.5 * deltaTime;
        this.moveEntity(enemy, enemy.spawnPosition, speed);
    }
    checkRespawn(enemy) {
        const def = (0, shared_2.getEnemyDefinition)(enemy.enemyType);
        if (!def)
            return;
        if (Date.now() - enemy.deathTime >= def.respawnTime) {
            enemy.health = def.health;
            enemy.state = 'idle';
            enemy.targetId = null;
            enemy.position = { ...enemy.spawnPosition };
            enemy.currentPatrolIndex = 0;
            enemy.statusEffects = [];
            if (this.enmitySys) {
                this.enmitySys.clearEnmity(enemy);
            }
            this.respawnCallbacks.forEach(cb => cb(enemy.id));
        }
    }
    update(_deltaTime) {
    }
}
exports.AISystem = AISystem;
