import { EntityManager } from '../ecs/EntityManager';
import { EntityData, PositionData } from '@dust-saga/shared';
import { Vector3, distanceSquared } from '@dust-saga/shared';

export class Zone {
  public id: string;
  public name: string;
  public entities: Map<string, any> = new Map();
  private entityManager: EntityManager;

  constructor(id: string, name: string, entityManager: EntityManager) {
    this.id = id;
    this.name = name;
    this.entityManager = entityManager;
  }

  addEntity(entityData: EntityData): void {
    this.entities.set(entityData.id, entityData);
  }

  removeEntity(entityId: string): void {
    this.entities.delete(entityId);
  }

  getEntity(entityId: string): EntityData | undefined {
    return this.entities.get(entityId);
  }

  getEntitiesNearby(position: PositionData, radius: number): EntityData[] {
    const nearby: EntityData[] = [];
    const radiusSquared = radius * radius;

    this.entities.forEach(entity => {
      if (distanceSquared(position, entity.position) <= radiusSquared) {
        nearby.push(entity);
      }
    });

    return nearby;
  }

  getAllEntities(): EntityData[] {
    return Array.from(this.entities.values());
  }

  update(deltaTime: number): void {
    // Update zone-specific logic
  }
}

export class WorldManager {
  private zones: Map<string, Zone> = new Map();
  private entityManager: EntityManager;
  private tickRate: number = 30;
  private lastTick: number = 0;
  private isRunning: boolean = false;

  constructor(entityManager: EntityManager) {
    this.entityManager = entityManager;
    this.initializeZones();
  }

  private initializeZones(): void {
    const starterZone = new Zone('starter_zone', 'Starter Zone', this.entityManager);
    this.zones.set('starter_zone', starterZone);

    const forestZone = new Zone('forest_zone', 'Forest Zone', this.entityManager);
    this.zones.set('forest_zone', forestZone);

    const dungeonZone = new Zone('dungeon_zone', 'Dungeon Zone', this.entityManager);
    this.zones.set('dungeon_zone', dungeonZone);
  }

  getZone(zoneId: string): Zone | undefined {
    return this.zones.get(zoneId);
  }

  getAllZones(): Zone[] {
    return Array.from(this.zones.values());
  }

  addEntityToZone(zoneId: string, entityData: EntityData): void {
    const zone = this.zones.get(zoneId);
    if (zone) {
      zone.addEntity(entityData);
    }
  }

  removeEntityFromZone(zoneId: string, entityId: string): void {
    const zone = this.zones.get(zoneId);
    if (zone) {
      zone.removeEntity(entityId);
    }
  }

  start(): void {
    this.isRunning = true;
    this.lastTick = Date.now();
    this.gameLoop();
  }

  stop(): void {
    this.isRunning = false;
  }

  private gameLoop(): void {
    if (!this.isRunning) return;

    const now = Date.now();
    const deltaTime = (now - this.lastTick) / 1000;
    this.lastTick = now;

    this.update(deltaTime);

    setTimeout(() => this.gameLoop(), 1000 / this.tickRate);
  }

  private update(deltaTime: number): void {
    this.zones.forEach(zone => {
      zone.update(deltaTime);
    });
  }
}