import { SpatialHash, SpatialEntry, EnemyInstance, PlayerSession } from '@dust-saga/shared';
import { SpawnManager } from './SpawnManager';

export interface SpatialIndexDeps {
  getPlayers(): Map<string, PlayerSession>;
  getSpawnManager(): SpawnManager;
}

export class SpatialIndexManager {
  private playerSpatialHash = new SpatialHash<PlayerSession>(8);
  private enemySpatialHash = new SpatialHash<EnemyInstance>(8);

  constructor(private deps: SpatialIndexDeps) {}

  updatePlayerSpatialPosition(characterId: string, position: { x: number; z: number }): void {
    const session = this.deps.getPlayers().get(characterId);
    if (session) {
      this.playerSpatialHash.move(characterId, position.x, position.z);
    }
  }

  insertPlayerSpatial(characterId: string): void {
    const session = this.deps.getPlayers().get(characterId);
    if (session?.position) {
      this.playerSpatialHash.insert(characterId, session.position.x, session.position.z, session);
    }
  }

  removePlayerSpatial(characterId: string): void {
    this.playerSpatialHash.remove(characterId);
  }

  insertEnemySpatial(enemy: EnemyInstance): void {
    if (enemy.state !== 'dead') {
      this.enemySpatialHash.insert(enemy.id, enemy.position.x, enemy.position.z, enemy);
    }
  }

  removeEnemySpatial(enemyId: string): void {
    this.enemySpatialHash.remove(enemyId);
  }

  queryEnemiesNear(x: number, z: number, radius: number, zoneId: string): SpatialEntry<EnemyInstance>[] {
    return this.enemySpatialHash.queryRadius(x, z, radius).filter(e => {
      if (e.data.state === 'dead') return false;
      const eZone = this.deps.getSpawnManager().findZoneOfEnemy(e.id);
      return eZone === zoneId;
    });
  }

  queryPlayersNear(x: number, z: number, radius: number, zoneId: string): SpatialEntry<PlayerSession>[] {
    return this.playerSpatialHash.queryRadius(x, z, radius).filter(e => {
      if (e.data.isDead) return false;
      return e.data.zoneId === zoneId;
    });
  }

  /** Re-position every alive enemy in the hash (called once per tick). */
  updateEnemySpatialHash(): void {
    const spawnMgr = this.deps.getSpawnManager();
    for (const zoneId of spawnMgr.getZoneIds()) {
      const zoneEnemies = spawnMgr.getEnemiesInZone(zoneId);
      if (!zoneEnemies) continue;
      for (const [enemyId, enemy] of zoneEnemies) {
        if (enemy.state !== 'dead' && enemy.position) {
          this.enemySpatialHash.move(enemyId, enemy.position.x, enemy.position.z);
        }
      }
    }
  }

  /** Seed the enemy hash from all spawned enemies (called once at startup). */
  populateEnemySpatialHash(): void {
    this.deps.getSpawnManager().iterateAllEnemies(enemy => {
      if (enemy.state !== 'dead') {
        this.enemySpatialHash.insert(enemy.id, enemy.position.x, enemy.position.z, enemy);
      }
    });
  }
}
