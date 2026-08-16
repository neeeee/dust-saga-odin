"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.WorldManager = exports.Zone = void 0;
const shared_1 = require("@dust-saga/shared");
class Zone {
    constructor(id, name, entityManager) {
        this.entities = new Map();
        this.id = id;
        this.name = name;
        this.entityManager = entityManager;
    }
    addEntity(entityData) {
        this.entities.set(entityData.id, entityData);
    }
    removeEntity(entityId) {
        this.entities.delete(entityId);
    }
    getEntity(entityId) {
        return this.entities.get(entityId);
    }
    getEntitiesNearby(position, radius) {
        const nearby = [];
        const radiusSquared = radius * radius;
        this.entities.forEach(entity => {
            if ((0, shared_1.distanceSquared)(position, entity.position) <= radiusSquared) {
                nearby.push(entity);
            }
        });
        return nearby;
    }
    getAllEntities() {
        return Array.from(this.entities.values());
    }
    update(deltaTime) {
        // Update zone-specific logic
    }
}
exports.Zone = Zone;
class WorldManager {
    constructor(entityManager) {
        this.zones = new Map();
        this.tickRate = 30;
        this.lastTick = 0;
        this.isRunning = false;
        this.entityManager = entityManager;
        this.initializeZones();
    }
    initializeZones() {
        const starterZone = new Zone('starter_zone', 'Starter Zone', this.entityManager);
        this.zones.set('starter_zone', starterZone);
        const forestZone = new Zone('forest_zone', 'Forest Zone', this.entityManager);
        this.zones.set('forest_zone', forestZone);
        const dungeonZone = new Zone('dungeon_zone', 'Dungeon Zone', this.entityManager);
        this.zones.set('dungeon_zone', dungeonZone);
    }
    getZone(zoneId) {
        return this.zones.get(zoneId);
    }
    getAllZones() {
        return Array.from(this.zones.values());
    }
    addEntityToZone(zoneId, entityData) {
        const zone = this.zones.get(zoneId);
        if (zone) {
            zone.addEntity(entityData);
        }
    }
    removeEntityFromZone(zoneId, entityId) {
        const zone = this.zones.get(zoneId);
        if (zone) {
            zone.removeEntity(entityId);
        }
    }
    start() {
        this.isRunning = true;
        this.lastTick = Date.now();
        this.gameLoop();
    }
    stop() {
        this.isRunning = false;
    }
    gameLoop() {
        if (!this.isRunning)
            return;
        const now = Date.now();
        const deltaTime = (now - this.lastTick) / 1000;
        this.lastTick = now;
        this.update(deltaTime);
        setTimeout(() => this.gameLoop(), 1000 / this.tickRate);
    }
    update(deltaTime) {
        this.zones.forEach(zone => {
            zone.update(deltaTime);
        });
    }
}
exports.WorldManager = WorldManager;
