import { v4 as uuidv4 } from 'uuid';
import { EnemyInstance, StatusEffect } from '@dust-saga/shared';
import { getEnemyDefinition, getZoneDefinition, ZONE_DATABASE, ZoneType } from '@dust-saga/shared';

export class SpawnManager {
  private spawnedEnemies: Map<string, Map<string, EnemyInstance>> = new Map();
  private enemyZoneIndex: Map<string, string> = new Map();

  initialize(): void {
    Object.keys(ZONE_DATABASE).forEach(zoneId => {
      this.spawnZoneEnemies(zoneId);
    });
  }

  private spawnZoneEnemies(zoneId: string): void {
    const zoneDef = getZoneDefinition(zoneId);
    if (!zoneDef) return;

    if (zoneDef.type === ZoneType.SAFE || zoneDef.type === ZoneType.NATION) {
      this.spawnedEnemies.set(zoneId, new Map());
      return;
    }

    const enemies = new Map<string, EnemyInstance>();
    this.spawnedEnemies.set(zoneId, enemies);

    for (const spawn of zoneDef.spawns) {
      const enemyDef = getEnemyDefinition(spawn.enemyType);
      if (!enemyDef) continue;

      for (let i = 0; i < spawn.count; i++) {
        const angle = Math.random() * Math.PI * 2;
        const radius = Math.random() * spawn.spawnArea.radius;
        const x = spawn.spawnArea.centerX + Math.cos(angle) * radius;
        const z = spawn.spawnArea.centerZ + Math.sin(angle) * radius;

        const halfSize = zoneDef.size / 2;
        const clampedX = Math.max(-halfSize, Math.min(halfSize, x));
        const clampedZ = Math.max(-halfSize, Math.min(halfSize, z));

        const patrolPoints = this.generatePatrolPoints(
          { x: clampedX, y: 0, z: clampedZ },
          5,
          spawn.spawnArea
        );

        const enemy: EnemyInstance = {
          id: `enemy_${zoneId}_${spawn.enemyType}_${i}`,
          enemyType: spawn.enemyType,
          position: { x: clampedX, y: 0, z: clampedZ },
          rotation: Math.random() * Math.PI * 2,
          health: enemyDef.health,
          maxHealth: enemyDef.health,
          level: enemyDef.level,
          state: 'idle',
          targetId: null,
          spawnPosition: { x: clampedX, y: 0, z: clampedZ },
          lastAttackTime: 0,
          deathTime: 0,
          patrolPoints,
          currentPatrolIndex: 0,
          statusEffects: [],
          invulnerable: spawn.enemyType === 'striking_dummy',
        };

        enemies.set(enemy.id, enemy);
        this.enemyZoneIndex.set(enemy.id, zoneId);
      }
    }
  }

  private generatePatrolPoints(
    center: { x: number; y: number; z: number },
    count: number,
    area: { centerX: number; centerZ: number; radius: number }
  ): Array<{ x: number; y: number; z: number }> {
    const points: Array<{ x: number; y: number; z: number }> = [];
    for (let i = 0; i < count; i++) {
      const angle = (Math.PI * 2 * i) / count + Math.random() * 0.5;
      const r = 3 + Math.random() * 5;
      points.push({
        x: center.x + Math.cos(angle) * r,
        y: 0,
        z: center.z + Math.sin(angle) * r
      });
    }
    return points;
  }

  getEnemiesInZone(zoneId: string): Map<string, EnemyInstance> {
    return this.spawnedEnemies.get(zoneId) || new Map();
  }

  getZoneIds(): string[] {
    return [...this.spawnedEnemies.keys()];
  }

  getEnemy(enemyId: string): EnemyInstance | undefined {
    const zoneId = this.enemyZoneIndex.get(enemyId);
    if (!zoneId) return undefined;
    return this.spawnedEnemies.get(zoneId)?.get(enemyId);
  }

  findZoneOfEnemy(enemyId: string): string | undefined {
    return this.enemyZoneIndex.get(enemyId);
  }

  getAllEnemies(): Map<string, EnemyInstance> {
    const all = new Map<string, EnemyInstance>();
    this.spawnedEnemies.forEach(enemies => {
      enemies.forEach((enemy, id) => all.set(id, enemy));
    });
    return all;
  }

  iterateAllEnemies(cb: (enemy: EnemyInstance, enemyId: string) => void): void {
    this.spawnedEnemies.forEach(enemies => {
      enemies.forEach((enemy, id) => cb(enemy, id));
    });
  }

  forEnemiesInZone(zoneId: string, cb: (enemy: EnemyInstance, enemyId: string) => void): void {
    const enemies = this.spawnedEnemies.get(zoneId);
    if (!enemies) return;
    enemies.forEach(cb);
  }
}
