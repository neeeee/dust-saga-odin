import { v4 as uuidv4 } from 'uuid';
import {
  SummonInstance, SummonType, SummonObject, COMBAT_SUMMON_TYPES, MAX_PLANTS,
  SUMMON_STATS, BANISH_RADIUS,
  EnemyInstance, StatusEffect, StatusEffectType, Packet, PacketType,
} from '@dust-saga/shared';
import { SpawnManager } from './SpawnManager';
import { EnmitySystem } from '../ecs/systems/EnmitySystem';

export interface SummonCombatDeps {
  getSpawnManager(): SpawnManager;
  getEnmity(): EnmitySystem;
  getTickRate(): number;
  broadcastInZone(zoneId: string, packet: Packet): void;
  damageEnemy(enemy: EnemyInstance, damage: number, attackerId?: string): { died: boolean; actualDamage: number };
  getEnemyEffectiveDefense(enemy: EnemyInstance): number;
  handleEnemyKill(enemyId: string, killerId: string): void;
  shouldApplyDebuff(effect: StatusEffect, targetId: string, casterId?: string): boolean;
}

export class SummonManager {
  private summons: Map<string, SummonInstance> = new Map();
  private ownerIndex: Map<string, string[]> = new Map();
  private zoneIndex: Map<string, Set<string>> = new Map();

  spawnSummon(
    ownerId: string,
    ownerName: string,
    zoneId: string,
    summonObj: SummonObject,
    position: { x: number; y: number; z: number },
    rotation: number,
    element?: string,
  ): SummonInstance | null {
    const summonType = summonObj.objectType as SummonType;
    this.enforceLimits(ownerId, summonType);

    const baseStats = SUMMON_STATS[summonType];
    const now = Date.now() / 1000;
    const summon: SummonInstance = {
      id: uuidv4(),
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
      state: summonType === SummonType.WALL ? 'idle' : 'follow',
      zoneId,
      wanderTarget: null,
      wanderCooldown: 0,
    };

    this.summons.set(summon.id, summon);

    if (!this.ownerIndex.has(ownerId)) this.ownerIndex.set(ownerId, []);
    this.ownerIndex.get(ownerId)!.push(summon.id);

    if (!this.zoneIndex.has(zoneId)) this.zoneIndex.set(zoneId, new Set());
    this.zoneIndex.get(zoneId)!.add(summon.id);

    return summon;
  }

  private enforceLimits(ownerId: string, summonType: SummonType): void {
    const owned = this.ownerIndex.get(ownerId) || [];

    if (summonType === SummonType.WALL) {
      const existing = owned.find(id => this.summons.get(id)?.summonType === SummonType.WALL);
      if (existing) this.despawnSummon(existing);
      return;
    }

    if (summonType === SummonType.PLANT) {
      const plants = owned.filter(id => this.summons.get(id)?.summonType === SummonType.PLANT);
      if (plants.length >= MAX_PLANTS) {
        this.despawnSummon(plants[0]);
      }
      return;
    }

    if (summonType === SummonType.WYVERN || summonType === SummonType.TURTLE) {
      for (const id of [...owned]) {
        const s = this.summons.get(id);
        if (s && COMBAT_SUMMON_TYPES.includes(s.summonType)) {
          this.despawnSummon(id);
        }
      }
    }
  }

  despawnSummon(summonId: string): void {
    const summon = this.summons.get(summonId);
    if (!summon) return;

    this.summons.delete(summonId);

    const owned = this.ownerIndex.get(summon.ownerId);
    if (owned) {
      const idx = owned.indexOf(summonId);
      if (idx !== -1) owned.splice(idx, 1);
      if (owned.length === 0) this.ownerIndex.delete(summon.ownerId);
    }

    const zoneSet = this.zoneIndex.get(summon.zoneId);
    if (zoneSet) {
      zoneSet.delete(summonId);
      if (zoneSet.size === 0) this.zoneIndex.delete(summon.zoneId);
    }
  }

  despawnAllForOwner(ownerId: string): string[] {
    const owned = this.ownerIndex.get(ownerId);
    if (!owned) return [];
    const despawned = [...owned];
    for (const id of despawned) {
      this.despawnSummon(id);
    }
    return despawned;
  }

  getSummon(summonId: string): SummonInstance | undefined {
    return this.summons.get(summonId);
  }

  getSummonsInZone(zoneId: string): SummonInstance[] {
    const ids = this.zoneIndex.get(zoneId);
    if (!ids) return [];
    const result: SummonInstance[] = [];
    for (const id of ids) {
      const s = this.summons.get(id);
      if (s) result.push(s);
    }
    return result;
  }

  getSummonsForOwner(ownerId: string): SummonInstance[] {
    const owned = this.ownerIndex.get(ownerId);
    if (!owned) return [];
    const result: SummonInstance[] = [];
    for (const id of owned) {
      const s = this.summons.get(id);
      if (s) result.push(s);
    }
    return result;
  }

  damageSummon(id: string, damage: number): boolean {
    const summon = this.summons.get(id);
    if (!summon) return false;
    summon.health = Math.max(0, summon.health - damage);
    return summon.health <= 0;
  }

  getSummonsInRadius(zoneId: string, center: { x: number; z: number }, radius: number): SummonInstance[] {
    const zoneSummons = this.getSummonsInZone(zoneId);
    const rSq = radius * radius;
    return zoneSummons.filter(s => {
      const dx = s.position.x - center.x;
      const dz = s.position.z - center.z;
      return dx * dx + dz * dz <= rSq;
    });
  }

  tickExpired(): Array<{ id: string; zoneId: string }> {
    const now = Date.now() / 1000;
    const expired: Array<{ id: string; zoneId: string }> = [];
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

  tick(now: number, deps: SummonCombatDeps): void {
    const expired = this.tickExpired();
    for (const info of expired) {
      deps.broadcastInZone(info.zoneId, {
        type: PacketType.ENTITY_DESPAWN,
        timestamp: Date.now(),
        data: { entityId: info.id },
      });
    }

    const nowSec = now / 1000;
    const spawnMgr = deps.getSpawnManager();
    for (const zoneId of spawnMgr.getZoneIds()) {
      const summons = this.getSummonsInZone(zoneId);
      if (summons.length === 0) continue;

      const zoneEnemies = spawnMgr.getEnemiesInZone(zoneId);

      for (const summon of summons) {
        if (summon.health <= 0) {
          this.despawnSummon(summon.id);
          deps.broadcastInZone(zoneId, {
            type: PacketType.ENTITY_DESPAWN,
            timestamp: Date.now(),
            data: { entityId: summon.id },
          });
          continue;
        }

        if (summon.summonType === 'plant') {
          this.tickPlantAttack(summon, zoneEnemies, nowSec, deps);
        } else if (summon.summonType === 'wyvern') {
          this.tickWyvern(summon, zoneEnemies, nowSec, deps);
        } else if (summon.summonType === 'turtle') {
          this.tickTurtleEarthquake(summon, zoneEnemies, nowSec, deps);
        }
      }
    }
  }

  private tickPlantAttack(summon: SummonInstance, zoneEnemies: Map<string, EnemyInstance>, nowSec: number, deps: SummonCombatDeps): void {
    if (nowSec - summon.lastAttackTime < summon.attackCooldown) return;

    let closestId: string | null = null;
    let closestDistSq = summon.attackRange * summon.attackRange;

    for (const [enemyId, enemy] of zoneEnemies) {
      if (enemy.state === 'dead') continue;
      const dx = enemy.position.x - summon.position.x;
      const dz = enemy.position.z - summon.position.z;
      const distSq = dx * dx + dz * dz;
      if (distSq < closestDistSq) {
        closestDistSq = distSq;
        closestId = enemyId;
      }
    }

    if (!closestId) return;

    summon.lastAttackTime = nowSec;
    const enemy = zoneEnemies.get(closestId)!;
    const enemyDef = deps.getEnemyEffectiveDefense(enemy);
    const damage = Math.max(1, summon.attackDamage - Math.floor(enemyDef * 0.5));

    const { died } = deps.damageEnemy(enemy, damage, summon.ownerId);
    deps.getEnmity().addDamageEnmity(enemy, summon.id, damage);

    deps.broadcastInZone(summon.zoneId, {
      type: PacketType.ATTACK,
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

  private tickWyvern(summon: SummonInstance, zoneEnemies: Map<string, EnemyInstance>, nowSec: number, deps: SummonCombatDeps): void {
    const WANDER_RADIUS = 10;
    const dt = 1 / deps.getTickRate();
    const speed = SUMMON_STATS[summon.summonType as keyof typeof SUMMON_STATS].speed;

    if (summon.wanderTarget) {
      const wdx = summon.wanderTarget.x - summon.position.x;
      const wdz = summon.wanderTarget.z - summon.position.z;
      const wDist = Math.sqrt(wdx * wdx + wdz * wdz);
      if (wDist > 1) {
        summon.position.x += (wdx / wDist) * speed * dt;
        summon.position.z += (wdz / wDist) * speed * dt;
        summon.rotation = Math.atan2(wdx, wdz);
      } else {
        summon.wanderTarget = null;
        summon.wanderCooldown = nowSec + 0.5 + Math.random() * 1.5;
      }
    } else if (nowSec >= summon.wanderCooldown) {
      const angle = Math.random() * Math.PI * 2;
      const dist = 3 + Math.random() * (WANDER_RADIUS - 3);
      summon.wanderTarget = {
        x: summon.spawnPosition.x + Math.cos(angle) * dist,
        z: summon.spawnPosition.z + Math.sin(angle) * dist,
      };
    }

    if (nowSec - summon.lastAttackTime < summon.attackCooldown) return;

    const aoeRange = summon.attackRange;
    const aoeRangeSq = aoeRange * aoeRange;
    const hitEnemies: Array<{ id: string; enemy: EnemyInstance; distSq: number }> = [];

    for (const [enemyId, enemy] of zoneEnemies) {
      if (enemy.state === 'dead') continue;
      const dx = enemy.position.x - summon.position.x;
      const dz = enemy.position.z - summon.position.z;
      const distSq = dx * dx + dz * dz;
      if (distSq <= aoeRangeSq) {
        hitEnemies.push({ id: enemyId, enemy, distSq });
      }
    }

    if (hitEnemies.length === 0) return;

    summon.lastAttackTime = nowSec;

    deps.broadcastInZone(summon.zoneId, {
      type: PacketType.ATTACK,
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
        type: PacketType.DAMAGE,
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
      enemy.statusEffects = enemy.statusEffects.filter(e => e.type !== StatusEffectType.BURN);
      enemy.statusEffects.push({
        id: `burn_${id}_${Date.now()}`,
        type: StatusEffectType.BURN,
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
        type: PacketType.ENTITY_STATUS_EFFECTS,
        timestamp: Date.now(),
        data: { entityId: id, effects: enemy.statusEffects }
      });

      if (died) {
        deps.handleEnemyKill(id, summon.ownerId);
      }
    }
  }

  private tickTurtleEarthquake(summon: SummonInstance, zoneEnemies: Map<string, EnemyInstance>, nowSec: number, deps: SummonCombatDeps): void {
    if (nowSec - summon.lastAttackTime < summon.attackCooldown) return;

    const aoeRange = summon.attackRange;
    const aoeRangeSq = aoeRange * aoeRange;
    const hitEnemies: Array<{ id: string; enemy: EnemyInstance }> = [];

    for (const [enemyId, enemy] of zoneEnemies) {
      if (enemy.state === 'dead') continue;
      const dx = enemy.position.x - summon.position.x;
      const dz = enemy.position.z - summon.position.z;
      const distSq = dx * dx + dz * dz;
      if (distSq <= aoeRangeSq) {
        hitEnemies.push({ id: enemyId, enemy });
      }
    }

    if (hitEnemies.length === 0) return;

    summon.lastAttackTime = nowSec;

    const baseDamage = summon.attackDamage;

    deps.broadcastInZone(summon.zoneId, {
      type: PacketType.ATTACK,
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
        type: PacketType.DAMAGE,
        timestamp: Date.now(),
        data: {
          attackerId: summon.id,
          targetId: id,
          damage,
          isCritical: false,
          damageType: 'physical',
        },
      });

      const stunEffect: StatusEffect = {
        id: `stun_${id}_${Date.now()}`,
        type: StatusEffectType.STUN,
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
        enemy.statusEffects = enemy.statusEffects.filter(e => e.type !== StatusEffectType.STUN);
        enemy.statusEffects.push(stunEffect);
        deps.broadcastInZone(summon.zoneId, {
          type: PacketType.ENTITY_STATUS_EFFECTS,
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
