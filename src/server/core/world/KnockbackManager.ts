import { getEnemyDefinition, PlayerSession } from '@dust-saga/shared';
import { SpawnManager } from './SpawnManager';

export interface KnockbackManagerDeps {
  getSpawnManager(): SpawnManager;
  forEachPlayerInZone(zoneId: string, cb: (id: string, player: PlayerSession) => void): void;
  getTickRate(): number;
}

/** Per-tick integration of `knockbackVelocity` on enemies and players (pure position update, no packets). */
export class KnockbackManager {
  constructor(private deps: KnockbackManagerDeps) {}

  private integrate(statusEffects: any[] | undefined, speed: number, dt: number, pos: { x: number; z: number }): void {
    if (!statusEffects) return;
    const kb = statusEffects.find(e => e.debuffCategory === 'knockback' && e.knockbackVelocity && e.knockbackVelocity.remaining > 0);
    if (!kb) return;
    const v = kb.knockbackVelocity!;
    const step = Math.min(v.remaining, speed * dt);
    pos.x += v.dx * step;
    pos.z += v.dz * step;
    v.remaining -= step;
    if (v.remaining <= 0) {
      const idx = statusEffects.indexOf(kb);
      if (idx !== -1) statusEffects.splice(idx, 1);
    }
  }

  tick(): void {
    const speed = 15;
    const dt = 1 / this.deps.getTickRate();
    const spawnMgr = this.deps.getSpawnManager();
    for (const zoneId of spawnMgr.getZoneIds()) {
      const enemies = spawnMgr.getEnemiesInZone(zoneId);
      if (enemies) {
        for (const [, enemy] of enemies) {
          if (enemy.state === 'dead') continue;
          const def = getEnemyDefinition(enemy.enemyType);
          if (def?.knockbackImmune) continue;
          this.integrate(enemy.statusEffects, speed, dt, enemy.position);
        }
      }

      this.deps.forEachPlayerInZone(zoneId, (_id, player) => {
        if (player.isDead) return;
        this.integrate(player.statusEffects, speed, dt, player.position);
      });
    }
  }
}
