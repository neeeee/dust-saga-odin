"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.CombatSystem = void 0;
const EntityManager_1 = require("../EntityManager");
const shared_1 = require("@dust-saga/shared");
const LineOfSight_1 = require("../../world/LineOfSight");
class CombatSystem extends EntityManager_1.System {
    constructor(entityManager) {
        super(entityManager);
        this.damageCallbacks = [];
        this.deathCallbacks = [];
    }
    onDamage(callback) {
        this.damageCallbacks.push(callback);
    }
    onDeath(callback) {
        this.deathCallbacks.push(callback);
    }
    computePhysicalDamage(attackPower, targetDefense, attackerRacialPassive) {
        const isCritical = Math.random() < (0, shared_1.applyRacialCritChance)(attackerRacialPassive, shared_1.COMBAT_CONFIG.CRITICAL_CHANCE);
        let damage = Math.max(shared_1.COMBAT_CONFIG.MIN_DAMAGE, attackPower - targetDefense * shared_1.COMBAT_CONFIG.DAMAGE_REDUCTION_PER_DEFENSE * 10);
        if (isCritical) {
            damage = Math.floor(damage * shared_1.COMBAT_CONFIG.CRITICAL_MULTIPLIER);
        }
        damage = Math.floor(damage * (0.9 + Math.random() * 0.2));
        return { damage, isCritical };
    }
    getTargetResists(isEnemy, enemyRef, playerRef, players) {
        if (isEnemy && enemyRef) {
            const def = (0, shared_1.getEnemyDefinition)(enemyRef.enemyType);
            return {
                fireResist: def?.fireResist,
                iceResist: def?.iceResist,
                lightningResist: def?.lightningResist,
                darkResist: def?.darkResist,
                holyResist: def?.holyResist,
                poisonResist: def?.poisonResist,
            };
        }
        else if (!isEnemy && playerRef) {
            return {
                fireResist: (playerRef.statBreakdown?.gearCombat?.fireResist ?? 0),
                iceResist: (playerRef.statBreakdown?.gearCombat?.iceResist ?? 0),
                lightningResist: (playerRef.statBreakdown?.gearCombat?.lightningResist ?? 0),
                darkResist: (playerRef.statBreakdown?.gearCombat?.darkResist ?? 0),
                holyResist: (playerRef.statBreakdown?.gearCombat?.holyResist ?? 0),
                poisonResist: (playerRef.statBreakdown?.gearCombat?.poisonResist ?? 0),
            };
        }
        return {};
    }
    applyDamageToTarget(targetId, damage, elementalDamage, isEnemy, enemyRef, playerRef, attackerId) {
        if (isEnemy && enemyRef) {
            enemyRef.health = Math.max(0, enemyRef.health - damage);
            for (const el of elementalDamage) {
                enemyRef.health = Math.max(0, enemyRef.health - el.damage);
            }
            if (enemyRef.invulnerable) {
                enemyRef.health = enemyRef.maxHealth;
            }
            else if (enemyRef.health <= 0 && enemyRef.state !== 'dead') {
                enemyRef.state = 'dead';
                enemyRef.deathTime = Date.now();
                this.deathCallbacks.forEach(cb => cb(targetId, attackerId));
            }
        }
        else if (!isEnemy && playerRef) {
            // player damage is handled by NetworkServer via redirect
        }
    }
    isRangedWeapon(attacker) {
        const weapon = attacker.equipment?.weapon;
        if (!weapon)
            return false;
        const def = this.itemSys.getItemDefinition(weapon.itemId);
        if (!def?.weaponType)
            return false;
        return shared_1.RANGED_WEAPON_TYPES.has(def.weaponType);
    }
    // Melee manual attacks sweep a cone; ranged manual attacks fly a thin
    // corridor (an arrow). Shared filter for manual-attack candidate targets.
    isAlongManualAttackLine(isRanged, dx, dz, dist, facingX, facingZ, halfCone, arrowHalfWidthSq) {
        if (isRanged) {
            const projection = dx * facingX + dz * facingZ;
            if (projection <= 0)
                return false;
            const perpX = dx - projection * facingX;
            const perpZ = dz - projection * facingZ;
            return perpX * perpX + perpZ * perpZ <= arrowHalfWidthSq;
        }
        const dot = (dx * facingX + dz * facingZ) / dist;
        return dot >= Math.cos(halfCone);
    }
    hasExtraHit(attacker) {
        return attacker.statusEffects?.some(e => e.buffData?.extraHit) || false;
    }
    processPlayerAttack(attacker, targetId, enemies, players) {
        const now = Date.now();
        const cooldown = shared_1.GAME_CONFIG.ATTACK_COOLDOWN;
        if (now - attacker.lastAttackTime < cooldown)
            return [];
        let targetPosition;
        let targetDefense;
        let isEnemy = false;
        let enemyRef = null;
        let playerRef = null;
        const enemy = enemies.get(targetId);
        if (enemy && enemy.state !== 'dead') {
            const def = (0, shared_1.getEnemyDefinition)(enemy.enemyType);
            targetDefense = def?.defense || 0;
            targetPosition = enemy.position;
            isEnemy = true;
            enemyRef = enemy;
        }
        else {
            const player = players.get(targetId);
            if (player) {
                const playerEffective = player.effectiveStats ?? (0, shared_1.getEffectiveStats)(player.stats, player.statPoints, player.statusEffects || []);
                targetDefense = playerEffective.defense;
                targetPosition = player.position;
                playerRef = player;
            }
            else {
                return [];
            }
        }
        const dx = attacker.position.x - targetPosition.x;
        const dz = attacker.position.z - targetPosition.z;
        const dist = Math.sqrt(dx * dx + dz * dz);
        const isRanged = this.isRangedWeapon(attacker);
        const attackRange = isRanged ? shared_1.COMBAT_CONFIG.RANGED_ATTACK_RANGE : shared_1.COMBAT_CONFIG.ATTACK_RANGE;
        if (dist > attackRange)
            return [];
        const effective = attacker.effectiveStats ?? (0, shared_1.getEffectiveStats)(attacker.stats, attacker.statPoints, attacker.statusEffects || []);
        const attackerBaseStats = attacker.baseStats || { STA: 0, STR: 0, AGI: 0, DEX: 0, SPI: 0, INT: 0 };
        const attackerTotalDex = (attacker.statPoints.DEX || 0) + (attackerBaseStats.DEX || 0);
        const attackerAcc = (0, shared_1.calculateAccuracy)(attacker.stats.level, attackerTotalDex, effective.accuracyBonus);
        let targetDodge = 0;
        if (isEnemy && enemyRef) {
            targetDodge = Math.floor(enemyRef.level * 0.5);
        }
        else if (playerRef) {
            targetDodge = playerRef.statBreakdown?.totalDodge ?? 0;
        }
        const hitChance = Math.min(0.99, Math.max(0.01, (0, shared_1.calculateHitChance)(attackerAcc, targetDodge)));
        const baseStats = attacker.baseStats || { STA: 0, STR: 0, AGI: 0, DEX: 0, SPI: 0, INT: 0 };
        const totalSPI = (attacker.statPoints.SPI || 0) + (baseStats.SPI || 0);
        const totalINT = (attacker.statPoints.INT || 0) + (baseStats.INT || 0);
        const targetResists = this.getTargetResists(isEnemy, enemyRef, playerRef, players);
        const numHits = this.hasExtraHit(attacker) ? 2 : 1;
        const results = [];
        for (let h = 0; h < numHits; h++) {
            if (Math.random() > hitChance) {
                const missInfo = {
                    attackerId: attacker.characterId,
                    targetId,
                    damage: 0,
                    isCritical: false,
                    damageType: 'physical',
                    missed: true,
                    isRanged,
                };
                this.damageCallbacks.forEach(cb => cb(missInfo));
                results.push(missInfo);
                continue;
            }
            const { damage, isCritical } = this.computePhysicalDamage(effective.attack, targetDefense, attacker.racialPassive);
            const attackerWeaponDef = this.itemSys.getItemDefinition(attacker.equipment?.weapon?.itemId);
            const elementalDamage = (0, shared_1.calculateWeaponElementalDamage)(attackerWeaponDef?.stats.weaponElement, attackerWeaponDef?.stats.weaponElementPower, attacker.statusEffects || [], totalSPI, totalINT, attacker.stats.level, targetResists, attacker.equipment?.weapon?.enhancementElement, attacker.equipment?.weapon?.enhancementLevel, effective.auraDamageMultiplier);
            this.applyDamageToTarget(targetId, damage, elementalDamage, isEnemy, enemyRef, playerRef, attacker.characterId);
            const info = {
                attackerId: attacker.characterId,
                targetId,
                damage,
                isCritical,
                damageType: 'physical',
                elementalDamage: elementalDamage.length > 0 ? elementalDamage : undefined,
                isRanged,
            };
            this.damageCallbacks.forEach(cb => cb(info));
            results.push(info);
        }
        return results;
    }
    processManualAttack(attacker, facingAngle, enemies, players, zoneId) {
        const now = Date.now();
        if (now - attacker.lastManualAttackTime < shared_1.GAME_CONFIG.MANUAL_ATTACK_COOLDOWN)
            return [];
        attacker.lastManualAttackTime = now;
        const isRanged = this.isRangedWeapon(attacker);
        const range = isRanged ? shared_1.COMBAT_CONFIG.RANGED_ATTACK_RANGE : shared_1.COMBAT_CONFIG.MANUAL_ATTACK_RANGE;
        const halfCone = shared_1.COMBAT_CONFIG.MANUAL_ATTACK_CONE_ANGLE / 2;
        const facingX = Math.sin(facingAngle);
        const facingZ = Math.cos(facingAngle);
        const arrowHalfWidthSq = shared_1.COMBAT_CONFIG.MANUAL_ATTACK_ARROW_HALF_WIDTH * shared_1.COMBAT_CONFIG.MANUAL_ATTACK_ARROW_HALF_WIDTH;
        const candidates = [];
        for (const [id, enemy] of enemies) {
            if (enemy.state === 'dead')
                continue;
            const dx = enemy.position.x - attacker.position.x;
            const dz = enemy.position.z - attacker.position.z;
            const dist = Math.sqrt(dx * dx + dz * dz);
            if (dist > range)
                continue;
            if (!this.isAlongManualAttackLine(isRanged, dx, dz, dist, facingX, facingZ, halfCone, arrowHalfWidthSq))
                continue;
            const def = (0, shared_1.getEnemyDefinition)(enemy.enemyType);
            candidates.push({ id, position: enemy.position, defense: def?.defense || 0, isEnemy: true, enemyRef: enemy, playerRef: null });
        }
        for (const [id, player] of players) {
            if (id === attacker.characterId || player.isDead)
                continue;
            const dx = player.position.x - attacker.position.x;
            const dz = player.position.z - attacker.position.z;
            const dist = Math.sqrt(dx * dx + dz * dz);
            if (dist > range)
                continue;
            if (!this.isAlongManualAttackLine(isRanged, dx, dz, dist, facingX, facingZ, halfCone, arrowHalfWidthSq))
                continue;
            const pe = player.effectiveStats ?? (0, shared_1.getEffectiveStats)(player.stats, player.statPoints, player.statusEffects || []);
            candidates.push({ id, position: player.position, defense: pe.defense, isEnemy: false, enemyRef: null, playerRef: player });
        }
        // Melee: conal swing — nearest targets first, damage falls off per target.
        // Ranged: a single arrow — it hits the first thing on its line, and is
        // eaten by terrain if an obstacle blocks the path to that target.
        let hitTargets;
        if (isRanged) {
            candidates.sort((a, b) => {
                const pa = (a.position.x - attacker.position.x) * facingX + (a.position.z - attacker.position.z) * facingZ;
                const pb = (b.position.x - attacker.position.x) * facingX + (b.position.z - attacker.position.z) * facingZ;
                return pa - pb;
            });
            hitTargets = [];
            const first = candidates[0];
            if (first && (0, LineOfSight_1.hasLineOfSight)(zoneId, attacker.position, first.position)) {
                hitTargets.push(first);
            }
        }
        else {
            candidates.sort((a, b) => {
                const da = Math.sqrt((a.position.x - attacker.position.x) ** 2 + (a.position.z - attacker.position.z) ** 2);
                const db = Math.sqrt((b.position.x - attacker.position.x) ** 2 + (b.position.z - attacker.position.z) ** 2);
                return da - db;
            });
            hitTargets = candidates.slice(0, shared_1.COMBAT_CONFIG.MANUAL_ATTACK_MAX_TARGETS);
        }
        const effective = attacker.effectiveStats ?? (0, shared_1.getEffectiveStats)(attacker.stats, attacker.statPoints, attacker.statusEffects || []);
        const baseStats = attacker.baseStats || { STA: 0, STR: 0, AGI: 0, DEX: 0, SPI: 0, INT: 0 };
        const totalSPI = (attacker.statPoints.SPI || 0) + (baseStats.SPI || 0);
        const totalINT = (attacker.statPoints.INT || 0) + (baseStats.INT || 0);
        const attackerTotalDex = (attacker.statPoints.DEX || 0) + (baseStats.DEX || 0);
        const attackerAcc = (0, shared_1.calculateAccuracy)(attacker.stats.level, attackerTotalDex, effective.accuracyBonus);
        const results = [];
        const numHits = this.hasExtraHit(attacker) ? 2 : 1;
        for (let i = 0; i < hitTargets.length; i++) {
            const target = hitTargets[i];
            const falloff = Math.pow(shared_1.COMBAT_CONFIG.MANUAL_ATTACK_FALLOFF, i);
            let targetDodge = 0;
            if (target.isEnemy && target.enemyRef) {
                targetDodge = Math.floor(target.enemyRef.level * 0.5);
            }
            else if (target.playerRef) {
                targetDodge = target.playerRef.statBreakdown?.totalDodge ?? 0;
            }
            const hitChance = Math.min(0.99, Math.max(0.01, (0, shared_1.calculateHitChance)(attackerAcc, targetDodge)));
            const targetResists = this.getTargetResists(target.isEnemy, target.enemyRef, target.playerRef, players);
            for (let h = 0; h < numHits; h++) {
                if (Math.random() > hitChance) {
                    const missInfo = {
                        attackerId: attacker.characterId,
                        targetId: target.id,
                        damage: 0,
                        isCritical: false,
                        damageType: 'physical',
                        missed: true,
                        isRanged,
                    };
                    this.damageCallbacks.forEach(cb => cb(missInfo));
                    results.push(missInfo);
                    continue;
                }
                const { damage: baseDamage, isCritical } = this.computePhysicalDamage(effective.attack, target.defense, attacker.racialPassive);
                const damage = Math.max(shared_1.COMBAT_CONFIG.MIN_DAMAGE, Math.floor(baseDamage * falloff));
                const attackerWeaponDef = this.itemSys.getItemDefinition(attacker.equipment?.weapon?.itemId);
                const elementalDamage = (0, shared_1.calculateWeaponElementalDamage)(attackerWeaponDef?.stats.weaponElement, attackerWeaponDef?.stats.weaponElementPower, attacker.statusEffects || [], totalSPI, totalINT, attacker.stats.level, targetResists, attacker.equipment?.weapon?.enhancementElement, attacker.equipment?.weapon?.enhancementLevel, effective.auraDamageMultiplier);
                const scaledElemental = elementalDamage.map(el => ({
                    element: el.element,
                    damage: Math.max(1, Math.floor(el.damage * falloff))
                }));
                this.applyDamageToTarget(target.id, damage, scaledElemental, target.isEnemy, target.enemyRef, target.playerRef, attacker.characterId);
                const info = {
                    attackerId: attacker.characterId,
                    targetId: target.id,
                    damage,
                    isCritical,
                    damageType: 'physical',
                    elementalDamage: scaledElemental.length > 0 ? scaledElemental : undefined,
                    isRanged,
                };
                this.damageCallbacks.forEach(cb => cb(info));
                results.push(info);
            }
        }
        return results;
    }
    processEnemyAttack(enemy, target) {
        const def = (0, shared_1.getEnemyDefinition)(enemy.enemyType);
        const attackRange = def?.attackRange || 2;
        const dist = Math.sqrt((enemy.position.x - target.position.x) ** 2 +
            (enemy.position.z - target.position.z) ** 2);
        if (dist > attackRange)
            return null;
        const targetDodge = target.statBreakdown?.totalDodge ?? 0;
        const enemyAccuracy = enemy.level + 7;
        let hitChance = (0, shared_1.calculateHitChance)(enemyAccuracy, targetDodge);
        const levelDiff = target.stats.level - enemy.level;
        if (levelDiff > 0) {
            hitChance /= 1 + levelDiff * 0.15;
        }
        hitChance = Math.min(0.99, Math.max(0.01, hitChance));
        if (Math.random() > hitChance) {
            return {
                attackerId: enemy.id,
                targetId: target.characterId,
                damage: 0,
                isCritical: false,
                damageType: 'physical',
                missed: true,
            };
        }
        const attackPower = def?.attack || 5;
        const targetEffective = target.effectiveStats ?? (0, shared_1.getEffectiveStats)(target.stats, target.statPoints, target.statusEffects || []);
        const { damage, isCritical } = this.computePhysicalDamage(attackPower, targetEffective.defense, 'monster');
        let finalDamage = damage;
        if (targetEffective.physicalDamageReduction > 0) {
            finalDamage = Math.floor(finalDamage * (1 - Math.min(0.9, targetEffective.physicalDamageReduction)));
        }
        for (const effect of enemy.statusEffects || []) {
            if (effect.type === shared_1.StatusEffectType.DEBUFF_DAMAGE_DOWN) {
                finalDamage = Math.floor(finalDamage * (1 - (effect.potency || 0)));
            }
        }
        const racialResult = (0, shared_1.processRacialOnDamage)(target, finalDamage, 'physical');
        finalDamage = racialResult.finalDamage;
        return {
            attackerId: enemy.id,
            targetId: target.characterId,
            damage: finalDamage,
            isCritical,
            damageType: 'physical'
        };
    }
    update(_deltaTime) {
    }
}
exports.CombatSystem = CombatSystem;
