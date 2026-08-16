"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.KnockbackManager = void 0;
const shared_1 = require("@dust-saga/shared");
/** Per-tick integration of `knockbackVelocity` on enemies and players (pure position update, no packets). */
class KnockbackManager {
    constructor(deps) {
        this.deps = deps;
    }
    integrate(statusEffects, speed, dt, pos) {
        if (!statusEffects)
            return;
        const kb = statusEffects.find(e => e.debuffCategory === 'knockback' && e.knockbackVelocity && e.knockbackVelocity.remaining > 0);
        if (!kb)
            return;
        const v = kb.knockbackVelocity;
        const step = Math.min(v.remaining, speed * dt);
        pos.x += v.dx * step;
        pos.z += v.dz * step;
        v.remaining -= step;
        if (v.remaining <= 0) {
            const idx = statusEffects.indexOf(kb);
            if (idx !== -1)
                statusEffects.splice(idx, 1);
        }
    }
    tick() {
        const speed = 15;
        const dt = 1 / this.deps.getTickRate();
        const spawnMgr = this.deps.getSpawnManager();
        for (const zoneId of spawnMgr.getZoneIds()) {
            const enemies = spawnMgr.getEnemiesInZone(zoneId);
            if (enemies) {
                for (const [, enemy] of enemies) {
                    if (enemy.state === 'dead')
                        continue;
                    const def = (0, shared_1.getEnemyDefinition)(enemy.enemyType);
                    if (def?.knockbackImmune)
                        continue;
                    this.integrate(enemy.statusEffects, speed, dt, enemy.position);
                }
            }
            this.deps.forEachPlayerInZone(zoneId, (_id, player) => {
                if (player.isDead)
                    return;
                this.integrate(player.statusEffects, speed, dt, player.position);
            });
        }
    }
}
exports.KnockbackManager = KnockbackManager;
