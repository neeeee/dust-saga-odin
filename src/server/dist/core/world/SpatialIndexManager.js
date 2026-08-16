"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SpatialIndexManager = void 0;
const shared_1 = require("@dust-saga/shared");
class SpatialIndexManager {
    constructor(deps) {
        this.deps = deps;
        this.playerSpatialHash = new shared_1.SpatialHash(8);
        this.enemySpatialHash = new shared_1.SpatialHash(8);
    }
    updatePlayerSpatialPosition(characterId, position) {
        const session = this.deps.getPlayers().get(characterId);
        if (session) {
            this.playerSpatialHash.move(characterId, position.x, position.z);
        }
    }
    insertPlayerSpatial(characterId) {
        const session = this.deps.getPlayers().get(characterId);
        if (session?.position) {
            this.playerSpatialHash.insert(characterId, session.position.x, session.position.z, session);
        }
    }
    removePlayerSpatial(characterId) {
        this.playerSpatialHash.remove(characterId);
    }
    insertEnemySpatial(enemy) {
        if (enemy.state !== 'dead') {
            this.enemySpatialHash.insert(enemy.id, enemy.position.x, enemy.position.z, enemy);
        }
    }
    removeEnemySpatial(enemyId) {
        this.enemySpatialHash.remove(enemyId);
    }
    queryEnemiesNear(x, z, radius, zoneId) {
        return this.enemySpatialHash.queryRadius(x, z, radius).filter(e => {
            if (e.data.state === 'dead')
                return false;
            const eZone = this.deps.getSpawnManager().findZoneOfEnemy(e.id);
            return eZone === zoneId;
        });
    }
    queryPlayersNear(x, z, radius, zoneId) {
        return this.playerSpatialHash.queryRadius(x, z, radius).filter(e => {
            if (e.data.isDead)
                return false;
            return e.data.zoneId === zoneId;
        });
    }
    /** Re-position every alive enemy in the hash (called once per tick). */
    updateEnemySpatialHash() {
        const spawnMgr = this.deps.getSpawnManager();
        for (const zoneId of spawnMgr.getZoneIds()) {
            const zoneEnemies = spawnMgr.getEnemiesInZone(zoneId);
            if (!zoneEnemies)
                continue;
            for (const [enemyId, enemy] of zoneEnemies) {
                if (enemy.state !== 'dead' && enemy.position) {
                    this.enemySpatialHash.move(enemyId, enemy.position.x, enemy.position.z);
                }
            }
        }
    }
    /** Seed the enemy hash from all spawned enemies (called once at startup). */
    populateEnemySpatialHash() {
        this.deps.getSpawnManager().iterateAllEnemies(enemy => {
            if (enemy.state !== 'dead') {
                this.enemySpatialHash.insert(enemy.id, enemy.position.x, enemy.position.z, enemy);
            }
        });
    }
}
exports.SpatialIndexManager = SpatialIndexManager;
