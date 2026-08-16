import { EntityManager, System } from '../EntityManager';
import { GAME_CONFIG, COMBAT_CONFIG, PlayerSession, EnemyInstance, DamageInfo, getEnemyDefinition, applyRacialCritChance, processRacialOnDamage, getEffectiveStats, calculateWeaponElementalDamage, calculateAccuracy, calculateHitChance, StatusEffectType, RANGED_WEAPON_TYPES } from '@dust-saga/shared';
import type { ItemSystem } from '../../../systems/ItemSystem';

interface ConeTarget {
  id: string;
  position: { x: number; y: number; z: number };
  defense: number;
  isEnemy: boolean;
  enemyRef: EnemyInstance | null;
  playerRef: PlayerSession | null;
}

export class CombatSystem extends System {
  itemSys!: ItemSystem;
  private damageCallbacks: Array<(info: DamageInfo) => void> = [];
  private deathCallbacks: Array<(entityId: string, killerId: string) => void> = [];

  constructor(entityManager: EntityManager) {
    super(entityManager);
  }

  onDamage(callback: (info: DamageInfo) => void): void {
    this.damageCallbacks.push(callback);
  }

  onDeath(callback: (entityId: string, killerId: string) => void): void {
    this.deathCallbacks.push(callback);
  }

  private computePhysicalDamage(
    attackPower: number,
    targetDefense: number,
    attackerRacialPassive?: string
  ): { damage: number; isCritical: boolean } {
    const isCritical = Math.random() < applyRacialCritChance(attackerRacialPassive, COMBAT_CONFIG.CRITICAL_CHANCE);
    let damage = Math.max(
      COMBAT_CONFIG.MIN_DAMAGE,
      attackPower - targetDefense * COMBAT_CONFIG.DAMAGE_REDUCTION_PER_DEFENSE * 10
    );
    if (isCritical) {
      damage = Math.floor(damage * COMBAT_CONFIG.CRITICAL_MULTIPLIER);
    }
    damage = Math.floor(damage * (0.9 + Math.random() * 0.2));
    return { damage, isCritical };
  }

  private getTargetResists(
    isEnemy: boolean,
    enemyRef: EnemyInstance | null,
    playerRef: PlayerSession | null,
    players: Map<string, PlayerSession>
  ): Record<string, number | undefined> {
    if (isEnemy && enemyRef) {
      const def = getEnemyDefinition(enemyRef.enemyType);
      return {
        fireResist: def?.fireResist,
        iceResist: def?.iceResist,
        lightningResist: def?.lightningResist,
        darkResist: def?.darkResist,
        holyResist: def?.holyResist,
        poisonResist: def?.poisonResist,
      };
    } else if (!isEnemy && playerRef) {
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

  private applyDamageToTarget(
    targetId: string,
    damage: number,
    elementalDamage: Array<{ element: string; damage: number }>,
    isEnemy: boolean,
    enemyRef: EnemyInstance | null,
    playerRef: PlayerSession | null,
    attackerId: string
  ): void {
    if (isEnemy && enemyRef) {
      enemyRef.health = Math.max(0, enemyRef.health - damage);
      for (const el of elementalDamage) {
        enemyRef.health = Math.max(0, enemyRef.health - el.damage);
      }
      if (enemyRef.invulnerable) {
        enemyRef.health = enemyRef.maxHealth;
      } else if (enemyRef.health <= 0 && enemyRef.state !== 'dead') {
        enemyRef.state = 'dead';
        enemyRef.deathTime = Date.now();
        this.deathCallbacks.forEach(cb => cb(targetId, attackerId));
      }
    } else if (!isEnemy && playerRef) {
      // player damage is handled by NetworkServer via redirect
    }
  }

  private isRangedWeapon(attacker: PlayerSession): boolean {
    const weapon = attacker.equipment?.weapon as any;
    if (!weapon) return false;
    const def = this.itemSys.getItemDefinition(weapon.itemId);
    if (!def?.weaponType) return false;
    return RANGED_WEAPON_TYPES.has(def.weaponType);
  }

  private hasExtraHit(attacker: PlayerSession): boolean {
    return attacker.statusEffects?.some(e => e.buffData?.extraHit) || false;
  }

  processPlayerAttack(
    attacker: PlayerSession,
    targetId: string,
    enemies: Map<string, EnemyInstance>,
    players: Map<string, PlayerSession>
  ): DamageInfo[] {
    const now = Date.now();
    const cooldown = GAME_CONFIG.ATTACK_COOLDOWN;
    if (now - attacker.lastAttackTime < cooldown) return [];

    let targetPosition: { x: number; y: number; z: number };
    let targetDefense: number;
    let isEnemy = false;
    let enemyRef: EnemyInstance | null = null;
    let playerRef: PlayerSession | null = null;

    const enemy = enemies.get(targetId);
    if (enemy && enemy.state !== 'dead') {
      const def = getEnemyDefinition(enemy.enemyType);
      targetDefense = def?.defense || 0;
      targetPosition = enemy.position;
      isEnemy = true;
      enemyRef = enemy;
    } else {
      const player = players.get(targetId);
      if (player) {
        const playerEffective = player.effectiveStats ?? getEffectiveStats(player.stats, player.statPoints, player.statusEffects || []);
        targetDefense = playerEffective.defense;
        targetPosition = player.position;
        playerRef = player;
      } else {
        return [];
      }
    }

    const dx = attacker.position.x - targetPosition.x;
    const dz = attacker.position.z - targetPosition.z;
    const dist = Math.sqrt(dx * dx + dz * dz);
    const isRanged = this.isRangedWeapon(attacker);
    const attackRange = isRanged ? COMBAT_CONFIG.RANGED_ATTACK_RANGE : COMBAT_CONFIG.ATTACK_RANGE;
    if (dist > attackRange) return [];

    const effective = attacker.effectiveStats ?? getEffectiveStats(attacker.stats, attacker.statPoints, attacker.statusEffects || []);

    const attackerBaseStats = attacker.baseStats || { STA: 0, STR: 0, AGI: 0, DEX: 0, SPI: 0, INT: 0 };
    const attackerTotalDex = (attacker.statPoints.DEX || 0) + (attackerBaseStats.DEX || 0);
    const attackerAcc = calculateAccuracy(attacker.stats.level, attackerTotalDex, effective.accuracyBonus);
    let targetDodge = 0;
    if (isEnemy && enemyRef) {
      targetDodge = Math.floor(enemyRef.level * 0.5);
    } else if (playerRef) {
      targetDodge = playerRef.statBreakdown?.totalDodge ?? 0;
    }
    const hitChance = Math.min(0.99, Math.max(0.01, calculateHitChance(attackerAcc, targetDodge)));

    const baseStats = attacker.baseStats || { STA: 0, STR: 0, AGI: 0, DEX: 0, SPI: 0, INT: 0 };
    const totalSPI = (attacker.statPoints.SPI || 0) + (baseStats.SPI || 0);
    const totalINT = (attacker.statPoints.INT || 0) + (baseStats.INT || 0);
    const targetResists = this.getTargetResists(isEnemy, enemyRef, playerRef, players);

    const numHits = this.hasExtraHit(attacker) ? 2 : 1;
    const results: DamageInfo[] = [];

    for (let h = 0; h < numHits; h++) {
      if (Math.random() > hitChance) {
        const missInfo: DamageInfo = {
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
      const elementalDamage = calculateWeaponElementalDamage(
        attackerWeaponDef?.stats.weaponElement, attackerWeaponDef?.stats.weaponElementPower,
        attacker.statusEffects || [],
        totalSPI, totalINT, attacker.stats.level, targetResists,
        (attacker.equipment?.weapon as any)?.enhancementElement,
        (attacker.equipment?.weapon as any)?.enhancementLevel,
        effective.auraDamageMultiplier
      );

      this.applyDamageToTarget(targetId, damage, elementalDamage, isEnemy, enemyRef, playerRef, attacker.characterId);

      const info: DamageInfo = {
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

  processManualAttack(
    attacker: PlayerSession,
    facingAngle: number,
    enemies: Map<string, EnemyInstance>,
    players: Map<string, PlayerSession>
  ): DamageInfo[] {
    const now = Date.now();
    if (now - attacker.lastManualAttackTime < GAME_CONFIG.MANUAL_ATTACK_COOLDOWN) return [];
    attacker.lastManualAttackTime = now;

    const isRanged = this.isRangedWeapon(attacker);
    const range = isRanged ? COMBAT_CONFIG.RANGED_ATTACK_RANGE : COMBAT_CONFIG.MANUAL_ATTACK_RANGE;
    const halfCone = COMBAT_CONFIG.MANUAL_ATTACK_CONE_ANGLE / 2;
    const facingX = Math.sin(facingAngle);
    const facingZ = Math.cos(facingAngle);

    const candidates: ConeTarget[] = [];

    for (const [id, enemy] of enemies) {
      if (enemy.state === 'dead') continue;
      const dx = enemy.position.x - attacker.position.x;
      const dz = enemy.position.z - attacker.position.z;
      const dist = Math.sqrt(dx * dx + dz * dz);
      if (dist > range) continue;
      const dot = (dx * facingX + dz * facingZ) / dist;
      if (dot < Math.cos(halfCone)) continue;
      const def = getEnemyDefinition(enemy.enemyType);
      candidates.push({ id, position: enemy.position, defense: def?.defense || 0, isEnemy: true, enemyRef: enemy, playerRef: null });
    }

    for (const [id, player] of players) {
      if (id === attacker.characterId || player.isDead) continue;
      const dx = player.position.x - attacker.position.x;
      const dz = player.position.z - attacker.position.z;
      const dist = Math.sqrt(dx * dx + dz * dz);
      if (dist > range) continue;
      const dot = (dx * facingX + dz * facingZ) / dist;
      if (dot < Math.cos(halfCone)) continue;
      const pe = player.effectiveStats ?? getEffectiveStats(player.stats, player.statPoints, player.statusEffects || []);
      candidates.push({ id, position: player.position, defense: pe.defense, isEnemy: false, enemyRef: null, playerRef: player });
    }

    candidates.sort((a, b) => {
      const da = Math.sqrt((a.position.x - attacker.position.x) ** 2 + (a.position.z - attacker.position.z) ** 2);
      const db = Math.sqrt((b.position.x - attacker.position.x) ** 2 + (b.position.z - attacker.position.z) ** 2);
      return da - db;
    });

    const hitTargets = candidates.slice(0, COMBAT_CONFIG.MANUAL_ATTACK_MAX_TARGETS);

    const effective = attacker.effectiveStats ?? getEffectiveStats(attacker.stats, attacker.statPoints, attacker.statusEffects || []);
    const baseStats = attacker.baseStats || { STA: 0, STR: 0, AGI: 0, DEX: 0, SPI: 0, INT: 0 };
    const totalSPI = (attacker.statPoints.SPI || 0) + (baseStats.SPI || 0);
    const totalINT = (attacker.statPoints.INT || 0) + (baseStats.INT || 0);
    const attackerTotalDex = (attacker.statPoints.DEX || 0) + (baseStats.DEX || 0);
    const attackerAcc = calculateAccuracy(attacker.stats.level, attackerTotalDex, effective.accuracyBonus);

    const results: DamageInfo[] = [];
    const numHits = this.hasExtraHit(attacker) ? 2 : 1;

    for (let i = 0; i < hitTargets.length; i++) {
      const target = hitTargets[i];
      const falloff = Math.pow(COMBAT_CONFIG.MANUAL_ATTACK_FALLOFF, i);

      let targetDodge = 0;
      if (target.isEnemy && target.enemyRef) {
        targetDodge = Math.floor(target.enemyRef.level * 0.5);
      } else if (target.playerRef) {
        targetDodge = target.playerRef.statBreakdown?.totalDodge ?? 0;
      }
      const hitChance = Math.min(0.99, Math.max(0.01, calculateHitChance(attackerAcc, targetDodge)));
      const targetResists = this.getTargetResists(target.isEnemy, target.enemyRef, target.playerRef, players);

      for (let h = 0; h < numHits; h++) {
        if (Math.random() > hitChance) {
          const missInfo: DamageInfo = {
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
        const damage = Math.max(COMBAT_CONFIG.MIN_DAMAGE, Math.floor(baseDamage * falloff));

        const attackerWeaponDef = this.itemSys.getItemDefinition(attacker.equipment?.weapon?.itemId);
        const elementalDamage = calculateWeaponElementalDamage(
          attackerWeaponDef?.stats.weaponElement, attackerWeaponDef?.stats.weaponElementPower,
          attacker.statusEffects || [],
          totalSPI, totalINT, attacker.stats.level, targetResists,
          (attacker.equipment?.weapon as any)?.enhancementElement,
          (attacker.equipment?.weapon as any)?.enhancementLevel,
          effective.auraDamageMultiplier
        );
        const scaledElemental = elementalDamage.map(el => ({
          element: el.element,
          damage: Math.max(1, Math.floor(el.damage * falloff))
        }));

        this.applyDamageToTarget(target.id, damage, scaledElemental, target.isEnemy, target.enemyRef, target.playerRef, attacker.characterId);

        const info: DamageInfo = {
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

  processEnemyAttack(
    enemy: EnemyInstance,
    target: PlayerSession
  ): DamageInfo | null {
    const def = getEnemyDefinition(enemy.enemyType);
    const attackRange = def?.attackRange || 2;

    const dist = Math.sqrt(
      (enemy.position.x - target.position.x) ** 2 +
      (enemy.position.z - target.position.z) ** 2
    );
    if (dist > attackRange) return null;

    const targetDodge = target.statBreakdown?.totalDodge ?? 0;
    const enemyAccuracy = enemy.level + 7;
    let hitChance = calculateHitChance(enemyAccuracy, targetDodge);
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
    const targetEffective = target.effectiveStats ?? getEffectiveStats(
      target.stats,
      target.statPoints,
      target.statusEffects || []
    );
    const { damage, isCritical } = this.computePhysicalDamage(attackPower, targetEffective.defense, 'monster');

    let finalDamage = damage;

    if (targetEffective.physicalDamageReduction > 0) {
      finalDamage = Math.floor(finalDamage * (1 - Math.min(0.9, targetEffective.physicalDamageReduction)));
    }

    for (const effect of enemy.statusEffects || []) {
      if (effect.type === StatusEffectType.DEBUFF_DAMAGE_DOWN) {
        finalDamage = Math.floor(finalDamage * (1 - (effect.potency || 0)));
      }
    }

    const racialResult = processRacialOnDamage(target, finalDamage, 'physical');
    finalDamage = racialResult.finalDamage;

    return {
      attackerId: enemy.id,
      targetId: target.characterId,
      damage: finalDamage,
      isCritical,
      damageType: 'physical'
    };
  }

  update(_deltaTime: number): void {
  }
}
