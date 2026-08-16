import { v4 as uuidv4 } from 'uuid';
import { Packet, PacketType, PlayerSession } from '@dust-saga/shared';
import { SpawnManager } from './SpawnManager';
import { SkillSystem } from '../ecs/systems/SkillSystem';

export interface AOEZone {
  id: string;
  casterId: string;
  zoneId: string;
  skillName: string;
  position: { x: number; y: number; z: number };
  radius: number;
  pulseInterval: number;
  remainingPulses: number;
  lastPulseAt: number;
  expiresAt: number;
  entitiesInside: Map<string, number>;
}

export interface AOEZoneManagerDeps {
  getPlayers(): Map<string, PlayerSession>;
  getSpawnManager(): SpawnManager;
  getSkillSystem(): SkillSystem;
  broadcastInZone(zoneId: string, packet: Packet): void;
  applyAOEDamageToTargets(caster: PlayerSession, skillName: string, position: { x: number; y: number; z: number }, radius: number): void;
  onEntityEnterAOE(caster: PlayerSession, skillName: string, targetId: string, position: { x: number; y: number; z: number }, radius: number): void;
}

export class AOEZoneManager {
  private activeAOEZones = new Map<string, AOEZone>();

  constructor(private deps: AOEZoneManagerDeps) {}

  spawnAOEZone(session: PlayerSession, skillName: string, position: { x: number; y: number; z: number }, radius: number): void {
    const skill = this.deps.getSkillSystem().findSkillDefinition(skillName);
    const totalPulses = skill?.pulseCount || 1;
    const pulseInterval = skill?.pulseInterval || 1000;
    const now = Date.now();

    let expiresAt: number;
    if (skill && skill.duration > 0) {
      expiresAt = skill.duration * 1000 + now;
    } else {
      expiresAt = now + pulseInterval * (totalPulses - 1) + 1500;
    }

    const id = uuidv4();
    const zone: AOEZone = {
      id,
      casterId: session.characterId,
      zoneId: session.zoneId,
      skillName,
      position,
      radius,
      pulseInterval,
      remainingPulses: totalPulses,
      lastPulseAt: now,
      expiresAt,
      entitiesInside: new Map<string, number>(),
    };

    for (const [enemyId, enemy] of this.deps.getSpawnManager().getEnemiesInZone(session.zoneId) ?? []) {
      if (enemy.state === 'dead') continue;
      const dx = enemy.position.x - position.x;
      const dz = enemy.position.z - position.z;
      if (Math.sqrt(dx * dx + dz * dz) <= radius) {
        zone.entitiesInside.set(enemyId, now);
      }
    }
    for (const [pid, player] of this.deps.getPlayers()) {
      if (pid === session.characterId) continue;
      if (player.zoneId !== session.zoneId) continue;
      if (player.stats.health <= 0 || !player.position) continue;
      const dx = player.position.x - position.x;
      const dz = player.position.z - position.z;
      if (Math.sqrt(dx * dx + dz * dz) <= radius) {
        zone.entitiesInside.set(pid, now);
      }
    }
    this.activeAOEZones.set(id, zone);

    this.deps.broadcastInZone(session.zoneId, {
      type: PacketType.AOE_ENTITY,
      timestamp: Date.now(),
      data: {
        id,
        type: 'aoe',
        position,
        rotation: { x: 0, y: 0, z: 0, w: 1 },
        data: { skillName, radius, expiresAt: zone.expiresAt },
      }
    });
  }

  removeAOEZone(zoneId: string): void {
    const zone = this.activeAOEZones.get(zoneId);
    if (!zone) return;
    this.activeAOEZones.delete(zoneId);

    this.deps.broadcastInZone(zone.zoneId, {
      type: PacketType.AOE_DESPAWN,
      timestamp: Date.now(),
      data: { entityId: zoneId }
    });
  }

  tickAOEZones(now: number): void {
    const entries = [...this.activeAOEZones.entries()];
    for (const [zoneId, zone] of entries) {
      if (now >= zone.expiresAt || zone.remainingPulses <= 0) {
        this.removeAOEZone(zoneId);
        continue;
      }

      const caster = this.deps.getPlayers().get(zone.casterId);
      if (!caster || caster.isDead) {
        this.removeAOEZone(zoneId);
        continue;
      }

      if (zone.remainingPulses <= 0) continue;

      const lastPulse = zone.lastPulseAt || 0;
      if (now - lastPulse < zone.pulseInterval) continue;

      this.deps.applyAOEDamageToTargets(caster, zone.skillName, zone.position, zone.radius);
      zone.lastPulseAt = now;
      zone.remainingPulses--;
    }
  }

  /** Despawn all AOE zones cast by a character (used on disconnect). */
  cleanupOwner(casterId: string): void {
    for (const [zoneId, zone] of this.activeAOEZones) {
      if (zone.casterId === casterId) {
        this.removeAOEZone(zoneId);
      }
    }
  }

  private checkEntityAOEEntries(entityId: string, position: { x: number; y: number; z: number }, entityZoneId: string): void {
    for (const [, zone] of this.activeAOEZones) {
      if (zone.zoneId !== entityZoneId) continue;
      const dx = position.x - zone.position.x;
      const dz = position.z - zone.position.z;
      const dist = Math.sqrt(dx * dx + dz * dz);
      const wasInside = zone.entitiesInside.has(entityId);
      const isInside = dist <= zone.radius;

      if (isInside && !wasInside) {
        zone.entitiesInside.set(entityId, Date.now());
        const caster = this.deps.getPlayers().get(zone.casterId);
        if (caster) {
          this.deps.onEntityEnterAOE(caster, zone.skillName, entityId, zone.position, zone.radius);
        }
      } else if (!isInside && wasInside) {
        zone.entitiesInside.delete(entityId);
      }
    }
  }

  /** Per-tick: detect entities that have newly entered any active AOE zone. */
  tickEntityAOEEntries(): void {
    if (this.activeAOEZones.size === 0) return;
    const spawnMgr = this.deps.getSpawnManager();
    for (const zoneId of spawnMgr.getZoneIds()) {
      const zoneEnemies = spawnMgr.getEnemiesInZone(zoneId);
      if (!zoneEnemies) continue;
      for (const [enemyId, enemy] of zoneEnemies) {
        if (enemy.state === 'dead') continue;
        this.checkEntityAOEEntries(enemyId, enemy.position, zoneId);
      }
    }
  }
}
