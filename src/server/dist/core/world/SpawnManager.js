"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SpawnManager = void 0;
const shared_1 = require("@dust-saga/shared");
class SpawnManager {
    constructor() {
        this.spawnedEnemies = new Map();
        this.enemyZoneIndex = new Map();
    }
    initialize() {
        Object.keys(shared_1.ZONE_DATABASE).forEach(zoneId => {
            this.spawnZoneEnemies(zoneId);
        });
    }
    spawnZoneEnemies(zoneId) {
        const zoneDef = (0, shared_1.getZoneDefinition)(zoneId);
        if (!zoneDef)
            return;
        if (zoneDef.type === shared_1.ZoneType.SAFE || zoneDef.type === shared_1.ZoneType.NATION) {
            this.spawnedEnemies.set(zoneId, new Map());
            return;
        }
        const enemies = new Map();
        this.spawnedEnemies.set(zoneId, enemies);
        for (const spawn of zoneDef.spawns) {
            const enemyDef = (0, shared_1.getEnemyDefinition)(spawn.enemyType);
            if (!enemyDef)
                continue;
            for (let i = 0; i < spawn.count; i++) {
                const angle = Math.random() * Math.PI * 2;
                const radius = Math.random() * spawn.spawnArea.radius;
                const x = spawn.spawnArea.centerX + Math.cos(angle) * radius;
                const z = spawn.spawnArea.centerZ + Math.sin(angle) * radius;
                const halfSize = zoneDef.size / 2;
                const clampedX = Math.max(-halfSize, Math.min(halfSize, x));
                const clampedZ = Math.max(-halfSize, Math.min(halfSize, z));
                const patrolPoints = this.generatePatrolPoints({ x: clampedX, y: 0, z: clampedZ }, 5, spawn.spawnArea);
                const enemy = {
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
    generatePatrolPoints(center, count, area) {
        const points = [];
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
    getEnemiesInZone(zoneId) {
        return this.spawnedEnemies.get(zoneId) || new Map();
    }
    getZoneIds() {
        return [...this.spawnedEnemies.keys()];
    }
    getEnemy(enemyId) {
        const zoneId = this.enemyZoneIndex.get(enemyId);
        if (!zoneId)
            return undefined;
        return this.spawnedEnemies.get(zoneId)?.get(enemyId);
    }
    findZoneOfEnemy(enemyId) {
        return this.enemyZoneIndex.get(enemyId);
    }
    getAllEnemies() {
        const all = new Map();
        this.spawnedEnemies.forEach(enemies => {
            enemies.forEach((enemy, id) => all.set(id, enemy));
        });
        return all;
    }
    iterateAllEnemies(cb) {
        this.spawnedEnemies.forEach(enemies => {
            enemies.forEach((enemy, id) => cb(enemy, id));
        });
    }
    forEnemiesInZone(zoneId, cb) {
        const enemies = this.spawnedEnemies.get(zoneId);
        if (!enemies)
            return;
        enemies.forEach(cb);
    }
}
exports.SpawnManager = SpawnManager;
