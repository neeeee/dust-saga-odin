import { getEnemyDefinition, PlayerSession } from '@dust-saga/shared';
import { SpawnManager } from './SpawnManager';
import { clampMovement } from './WallRegistry';

export interface KnockbackManagerDeps {
  getSpawnManager(): SpawnManager;
  forEachPlayerInZone(zoneId: string, cb: (id: string, player: PlayerSession) => void): void;
  getTickRate(): number;
}

/**
 * Per-tick integration of `knockbackVelocity` on enemies and players (pure
 * position update, no packets). Each tick's step is clamped against the
 * zone's movement-blocking walls (WallRegistry — the same segments the
 * client collides with): getting blasted backwards stops at the wall
 * instead of tunneling through it, and the remaining impulse is spent.
 */
export class KnockbackManager {
  constructor(private deps: KnockbackManagerDeps) {}

  private integrate(
    statusEffects: any[] | undefined,
    speed: number,
    dt: number,
    pos: { x: number; y?: number; z: number },
    zoneId: string
  ): void {
    if (!statusEffects) return;
    const kb = statusEffects.find(e => e.debuffCategory === 'knockback' && e.knockbackVelocity && e.knockbackVelocity.remaining > 0);
    if (!kb) return;
    const v = kb.knockbackVelocity!;
    const step = Math.min(v.remaining, speed * dt);
    const next = clampMovement(
      zoneId,
      pos,
      { x: pos.x + v.dx * step, z: pos.z + v.dz * step }
    );
    if (next.blocked) {
      // stop at the wall; the impulse is spent against it
      pos.x = next.x;
      pos.z = next.z;
      const idx = statusEffects.indexOf(kb);
      if (idx !== -1) statusEffects.splice(idx, 1);
      return;
    }
    pos.x = next.x;
    pos.z = next.z;
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
          this.integrate(enemy.statusEffects, speed, dt, enemy.position, zoneId);
        }
      }

      this.deps.forEachPlayerInZone(zoneId, (_id, player) => {
        if (player.isDead) return;
        this.integrate(player.statusEffects, speed, dt, player.position, player.zoneId);
      });
    }
  }
}
