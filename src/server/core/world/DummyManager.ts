import {
  Packet, PacketType, PlayerSession,
  JOB_DEFINITIONS, createDefaultSkillProficiencies, createDefaultSkillAdeptness,
  getDesignJobId, getBaseClassForJob, normalizeEquipment,
  JobId, BaseClass, MAX_LEVEL, AccountRole,
  PartyVisibility, LootRule,
  ItemDefinition,
} from '@dust-saga/shared';
import { PartySystem } from '../ecs/systems/PartySystem';
import { PlayerSystem } from '../ecs/systems/PlayerSystem';

export interface DummyMeta {
  ownerId: string;
  isPvp: boolean;
  isWalking: boolean;
  walkPoints: Array<{ x: number; y: number; z: number }>;
  walkIndex: number;
  walkDir: number;
  inParty: boolean;
}

export interface DummyManagerDeps {
  getPlayers(): Map<string, PlayerSession>;
  registerPlayerInZone(characterId: string, zoneId: string): void;
  unregisterPlayerFromZone(characterId: string): void;
  clearMovementThrottle(characterId: string): void;
  broadcastInZone(zoneId: string, packet: Packet): void;
  sendToPlayer(characterId: string, packet: Packet): void;
  sendPartyUpdate(partyId: string): void;
  recalcStats(session: PlayerSession): void;
  getPartySys(): PartySystem;
  getPlayerSys(): PlayerSystem;
  getTickRate(): number;
  getItemDef(id: string): ItemDefinition | undefined;
}

export class DummyManager {
  readonly dummyMeta = new Map<string, DummyMeta>();
  private counter = 0;

  constructor(private deps: DummyManagerDeps) {}

  private gm(characterId: string, message: string): void {
    this.deps.sendToPlayer(characterId, {
      type: PacketType.CHAT_MESSAGE,
      timestamp: Date.now(),
      data: { sender: 'GM', message, channel: 'system' }
    });
  }

  private notFound(dummyId: string, session: PlayerSession): boolean {
    const meta = this.dummyMeta.get(dummyId);
    if (!meta || meta.ownerId !== session.characterId) {
      this.gm(session.characterId, `Dummy "${dummyId}" not found.`);
      return true;
    }
    return false;
  }

  spawnDummy(session: PlayerSession): void {
    this.counter++;
    const dummyId = `dummy_${Date.now()}_${this.counter}`;
    const dummyJob: JobId = JobId.WARRIOR;
    const dummyPosition = { x: session.position.x + 3, y: session.position.y, z: session.position.z };

    const dummySession: PlayerSession = {
      playerId: 'gm_dummy',
      socketId: '',
      username: 'gm_dummy',
      characterId: dummyId,
      characterName: `Dummy_${this.counter}`,
      race: 'human',
      jobId: dummyJob,
      baseClass: BaseClass.WARRIOR,
      stats: { health: 100, maxHealth: 100, mana: 50, maxMana: 50, attack: 10, defense: 5, speed: 1, speedMultiplier: 1, magicAttack: 5, critChance: 0.05, castSpeed: 1, level: 1, experience: 0, experienceToNext: 100 },
      statPoints: { STR: 5, AGI: 5, INT: 5, SPI: 5, DEX: 5, STA: 5 },
      baseStats: { STR: 5, AGI: 5, INT: 5, SPI: 5, DEX: 5, STA: 5 },
      unspentStatPoints: 0,
      unspentSkillPoints: 0,
      skillProficiencies: createDefaultSkillProficiencies(),
      skillAdeptness: createDefaultSkillAdeptness(getDesignJobId(dummyJob)),
      position: { ...dummyPosition },
      rotation: { x: 0, y: 0, z: 0, w: 1 },
      zoneId: session.zoneId,
      targetId: null,
      lastAttackTime: 0,
      lastManualAttackTime: 0,
      lastRegenTick: 0,
      invulnerableUntil: Date.now() + 999999999,
      isDead: false,
      isResting: false,
      restStartedAt: 0,
      currentNpcId: null,
      deathTime: 0,
      nation: null,
      lastSafeZoneId: session.zoneId,
      skillCooldowns: [],
      activeCast: null,
      statusEffects: [],
      statBreakdown: null,
      effectiveStats: null,
      inventory: [],
      gold: 0,
      equipment: normalizeEquipment(null),
      quests: [],
      role: AccountRole.PLAYER,
    };

    this.deps.getPlayers().set(dummyId, dummySession);
    this.deps.registerPlayerInZone(dummyId, session.zoneId);
    this.dummyMeta.set(dummyId, {
      ownerId: session.characterId,
      isPvp: false,
      isWalking: false,
      walkPoints: [
        { x: dummyPosition.x - 5, y: dummyPosition.y, z: dummyPosition.z },
        { x: dummyPosition.x + 5, y: dummyPosition.y, z: dummyPosition.z },
      ],
      walkIndex: 0,
      walkDir: 1,
      inParty: false,
    });

    this.deps.broadcastInZone(session.zoneId, {
      type: PacketType.ENTITY_SPAWN,
      timestamp: Date.now(),
      data: {
        id: dummyId,
        type: 'player',
        position: dummyPosition,
        rotation: dummySession.rotation,
        data: {
          name: dummySession.characterName,
          class: dummySession.jobId,
          race: dummySession.race,
          jobId: dummySession.jobId,
          level: dummySession.stats.level,
          health: dummySession.stats.health,
          maxHealth: dummySession.stats.maxHealth,
          modelFile: JOB_DEFINITIONS[dummySession.jobId]?.modelFile || 'Adventurer.glb'
        }
      }
    });

    this.gm(session.characterId, `SPAWNED ${dummyId}`);
  }

  despawnDummy(dummyId: string, session: PlayerSession): void {
    if (this.notFound(dummyId, session)) return;

    const meta = this.dummyMeta.get(dummyId)!;
    if (meta.inParty) {
      this.deps.getPartySys().leaveParty(dummyId);
    }

    this.deps.getPlayers().delete(dummyId);
    this.deps.unregisterPlayerFromZone(dummyId);
    this.dummyMeta.delete(dummyId);
    this.deps.clearMovementThrottle(dummyId);

    this.deps.broadcastInZone(session.zoneId, {
      type: PacketType.ENTITY_DESPAWN,
      timestamp: Date.now(),
      data: { entityId: dummyId }
    });

    this.gm(session.characterId, `DESPAWNED ${dummyId}`);
  }

  setDummyProperty(dummyId: string, prop: string, value: string, session: PlayerSession): void {
    if (this.notFound(dummyId, session)) return;
    const dummy = this.deps.getPlayers().get(dummyId);
    if (!dummy) return;

    const num = parseFloat(value);
    if (isNaN(num)) {
      this.gm(session.characterId, `Invalid value: ${value}`);
      return;
    }

    const propMap: Record<string, (v: number) => void> = {
      str: (v) => { dummy.statPoints.STR = v; dummy.baseStats.STR = v; },
      dex: (v) => { dummy.statPoints.DEX = v; dummy.baseStats.DEX = v; },
      agi: (v) => { dummy.statPoints.AGI = v; dummy.baseStats.AGI = v; },
      int: (v) => { dummy.statPoints.INT = v; dummy.baseStats.INT = v; },
      spi: (v) => { dummy.statPoints.SPI = v; dummy.baseStats.SPI = v; },
      sta: (v) => { dummy.statPoints.STA = v; dummy.baseStats.STA = v; },
      level: (v) => { dummy.stats.level = Math.max(1, Math.min(v, MAX_LEVEL)); },
      hp: (v) => { dummy.stats.health = v; dummy.stats.maxHealth = Math.max(dummy.stats.maxHealth, v); },
      maxhp: (v) => { dummy.stats.maxHealth = v; dummy.stats.health = Math.min(dummy.stats.health, v); },
      mp: (v) => { dummy.stats.mana = v; dummy.stats.maxMana = Math.max(dummy.stats.maxMana, v); },
      maxmp: (v) => { dummy.stats.maxMana = v; dummy.stats.mana = Math.min(dummy.stats.mana, v); },
      attack: (v) => { dummy.stats.attack = v; },
      defense: (v) => { dummy.stats.defense = v; },
      speed: (v) => { dummy.stats.speed = v; },
      crit: (v) => { dummy.stats.critChance = v; },
    };

    const setter = propMap[prop.toLowerCase()];
    if (!setter) {
      this.gm(session.characterId, `Unknown prop "${prop}". Valid: ${Object.keys(propMap).join(', ')}`);
      return;
    }

    setter(num);
    this.deps.recalcStats(dummy);

    this.deps.broadcastInZone(dummy.zoneId, {
      type: PacketType.STATS_UPDATE,
      timestamp: Date.now(),
      data: { entityId: dummyId, health: dummy.stats.health, maxHealth: dummy.stats.maxHealth, level: dummy.stats.level }
    });

    this.gm(session.characterId, `SET ${dummyId} ${prop}=${num}`);
  }

  setDummyClass(dummyId: string, jobIdStr: string, session: PlayerSession): void {
    if (this.notFound(dummyId, session)) return;
    const dummy = this.deps.getPlayers().get(dummyId);
    if (!dummy) return;

    const validJobs = Object.values(JobId) as string[];
    const targetJob = validJobs.find(j => j.toLowerCase() === jobIdStr.toLowerCase());
    if (!targetJob) {
      this.gm(session.characterId, `Invalid job "${jobIdStr}".`);
      return;
    }

    dummy.jobId = targetJob as JobId;
    dummy.baseClass = getBaseClassForJob(targetJob as JobId);
    this.deps.recalcStats(dummy);

    this.deps.broadcastInZone(dummy.zoneId, {
      type: PacketType.ENTITY_DESPAWN,
      timestamp: Date.now(),
      data: { entityId: dummyId }
    });

    this.deps.broadcastInZone(dummy.zoneId, {
      type: PacketType.ENTITY_SPAWN,
      timestamp: Date.now(),
      data: {
        id: dummyId,
        type: 'player',
        position: dummy.position,
        rotation: dummy.rotation,
        data: {
          name: dummy.characterName,
          class: dummy.jobId,
          race: dummy.race,
          jobId: dummy.jobId,
          level: dummy.stats.level,
          health: dummy.stats.health,
          maxHealth: dummy.stats.maxHealth,
          modelFile: JOB_DEFINITIONS[dummy.jobId]?.modelFile || 'Adventurer.glb'
        }
      }
    });

    this.gm(session.characterId, `CLASS ${dummyId} ${targetJob}`);
  }

  setDummyGear(dummyId: string, preset: string, session: PlayerSession): void {
    if (this.notFound(dummyId, session)) return;
    const dummy = this.deps.getPlayers().get(dummyId);
    if (!dummy) return;

    const presets: Record<string, Record<string, string | null>> = {
      naked: { weapon: null, armor: null, helmet: null, boots: null, gloves: null, legs: null, shield: null },
      common: { weapon: 'wooden_sword', armor: 'leather_armor', helmet: 'cloth_helmet', boots: 'leather_boots', gloves: null, legs: null, shield: null },
      rare: { weapon: 'steel_blade', armor: 'plate_armor', helmet: 'iron_helmet', boots: 'swift_boots', gloves: 'chain_gloves', legs: 'chain_leggings', shield: null },
      legendary: { weapon: 'legendary_blade', armor: 'dragon_plate', helmet: 'dragon_helm', boots: 'dragon_greaves', gloves: 'dragon_gauntlets', legs: 'dragon_leggings', shield: 'tower_shield' },
    };

    const gearPreset = presets[preset.toLowerCase()];
    if (!gearPreset) {
      this.gm(session.characterId, `Unknown preset "${preset}". Valid: ${Object.keys(presets).join(', ')}`);
      return;
    }

    for (const [slot, itemId] of Object.entries(gearPreset)) {
      if (itemId && this.deps.getItemDef(itemId)) {
        (dummy.equipment as any)[slot] = { itemId, enhancementLevel: 0, enhancementElement: null, quantity: 1, slot: 0 };
      } else {
        (dummy.equipment as any)[slot] = null;
      }
    }

    this.deps.recalcStats(dummy);

    this.deps.broadcastInZone(dummy.zoneId, {
      type: PacketType.STATS_UPDATE,
      timestamp: Date.now(),
      data: { entityId: dummyId, health: dummy.stats.health, maxHealth: dummy.stats.maxHealth, level: dummy.stats.level }
    });

    this.gm(session.characterId, `GEAR ${dummyId} ${preset}`);
  }

  toggleDummyPvp(dummyId: string, session: PlayerSession): void {
    if (this.notFound(dummyId, session)) return;
    const dummy = this.deps.getPlayers().get(dummyId);
    if (!dummy) return;

    const meta = this.dummyMeta.get(dummyId)!;
    meta.isPvp = !meta.isPvp;
    dummy.invulnerableUntil = meta.isPvp ? 0 : Date.now() + 999999999;
    dummy.stats.health = dummy.stats.maxHealth;
    dummy.isDead = false;

    this.deps.broadcastInZone(dummy.zoneId, {
      type: PacketType.STATS_UPDATE,
      timestamp: Date.now(),
      data: { entityId: dummyId, health: dummy.stats.health, maxHealth: dummy.stats.maxHealth }
    });

    this.gm(session.characterId, `PVP ${dummyId} ${meta.isPvp ? 'on' : 'off'}`);
  }

  toggleDummyWalk(dummyId: string, session: PlayerSession): void {
    if (this.notFound(dummyId, session)) return;
    const dummy = this.deps.getPlayers().get(dummyId);
    if (!dummy) return;

    const meta = this.dummyMeta.get(dummyId)!;
    meta.isWalking = !meta.isWalking;
    if (meta.isWalking) {
      meta.walkPoints = [
        { x: dummy.position.x - 5, y: dummy.position.y, z: dummy.position.z },
        { x: dummy.position.x + 5, y: dummy.position.y, z: dummy.position.z },
      ];
      meta.walkIndex = 0;
      meta.walkDir = 1;
    }

    this.gm(session.characterId, `WALK ${dummyId} ${meta.isWalking ? 'on' : 'off'}`);
  }

  toggleDummyParty(dummyId: string, session: PlayerSession): void {
    if (this.notFound(dummyId, session)) return;
    const dummy = this.deps.getPlayers().get(dummyId);
    if (!dummy) return;

    const partySys = this.deps.getPartySys();
    const meta = this.dummyMeta.get(dummyId)!;

    if (meta.inParty) {
      const result = partySys.leaveParty(dummyId);
      if (result) {
        meta.inParty = false;
        this.deps.sendPartyUpdate(result.party.partyId);
        this.gm(session.characterId, `PARTY ${dummyId} removed`);
      }
    } else {
      let party = partySys.getPartyForMember(session.characterId);
      if (!party) {
        party = partySys.createParty(session.characterId, session, { visibility: PartyVisibility.OPEN, lootRule: LootRule.RANDOM });
        if (!party) {
          this.gm(session.characterId, 'Failed to create party.');
          return;
        }
        this.deps.sendPartyUpdate(party.partyId);
      }

      const joined = partySys.joinParty(party.partyId, dummyId, dummy);
      if (joined) {
        meta.inParty = true;
        this.deps.sendPartyUpdate(party.partyId);
        this.gm(session.characterId, `PARTY ${dummyId} added`);
      } else {
        this.gm(session.characterId, 'Failed to add dummy to party (full or already in one).');
      }
    }
  }

  /** Despawn all dummies owned by a character (used on disconnect). */
  cleanupOwner(ownerId: string, zoneId: string): void {
    for (const [dummyId, meta] of this.dummyMeta) {
      if (meta.ownerId !== ownerId) continue;
      if (meta.inParty) this.deps.getPartySys().leaveParty(dummyId);
      this.deps.getPlayers().delete(dummyId);
      this.deps.unregisterPlayerFromZone(dummyId);
      this.dummyMeta.delete(dummyId);
      this.deps.clearMovementThrottle(dummyId);
      this.deps.broadcastInZone(zoneId, {
        type: PacketType.ENTITY_DESPAWN,
        timestamp: Date.now(),
        data: { entityId: dummyId }
      });
    }
  }

  tick(): void {
    const now = Date.now();
    const tickRate = this.deps.getTickRate();
    for (const [dummyId, meta] of this.dummyMeta) {
      if (!meta.isWalking) continue;
      const dummy = this.deps.getPlayers().get(dummyId);
      if (!dummy || dummy.isDead) continue;

      const target = meta.walkPoints[meta.walkIndex];
      if (!target) continue;

      const dx = target.x - dummy.position.x;
      const dz = target.z - dummy.position.z;
      const dist = Math.sqrt(dx * dx + dz * dz);

      const speed = 3;
      if (dist < 0.5) {
        meta.walkIndex += meta.walkDir;
        if (meta.walkIndex >= meta.walkPoints.length) {
          meta.walkIndex = meta.walkPoints.length - 2;
          meta.walkDir = -1;
        } else if (meta.walkIndex < 0) {
          meta.walkIndex = 1;
          meta.walkDir = 1;
        }
      } else {
        const dirX = dx / dist;
        const dirZ = dz / dist;
        dummy.position.x += dirX * speed * (1 / tickRate);
        dummy.position.z += dirZ * speed * (1 / tickRate);
        dummy.rotation.y = Math.atan2(dirX, dirZ);
      }

      this.deps.broadcastInZone(dummy.zoneId, {
        type: PacketType.PLAYER_POSITION_UPDATE,
        timestamp: now,
        data: {
          characterId: dummyId,
          position: dummy.position,
          rotation: dummy.rotation
        }
      });
    }
  }
}
