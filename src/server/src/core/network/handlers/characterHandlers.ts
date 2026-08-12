import { Socket } from 'socket.io';
import {
  Packet, PacketType, PlayerSession, Validator,
  JOB_DEFINITIONS, RACE_DATA, createDefaultStatPoints, createDefaultSkillProficiencies, createDefaultSkillAdeptness,
  getDesignJobId, JobId, Race, StatusEffectType, AccountRole,
  getZoneDefinition, normalizeEquipment,
} from '@dust-saga/shared';
import { NetworkContext, PacketHandler } from '../NetworkContext';

export function registerHandlers(registry: Map<PacketType, PacketHandler>): void {
  registry.set(PacketType.CHARACTER_LIST, handleCharacterList);
  registry.set(PacketType.CHARACTER_CREATE, handleCharacterCreate);
  registry.set(PacketType.CHARACTER_SELECT, handleCharacterSelect);
  registry.set(PacketType.CHARACTER_DELETE, handleCharacterDelete);
  registry.set(PacketType.RETURN_TO_CHARACTER_SELECT, handleReturnToCharacterSelect);
  registry.set(PacketType.LOGOUT, handleLogout);
}

async function handleCharacterList(ctx: NetworkContext, socket: Socket, _data: any): Promise<void> {
  const playerId = ctx.state.socketToPlayer.get(socket.id);
  if (!playerId) return;

  const characters = await ctx.auth.getCharacters(playerId);

  const characterInfos = characters.map(c => {
    const jobDef = JOB_DEFINITIONS[(c.job_id || c.class) as JobId];
    const raceData = RACE_DATA[(c.race || 'human') as Race];
    return {
      id: c.id,
      name: c.name,
      class: c.class || c.job_id,
      race: c.race || 'human',
      jobId: c.job_id || c.class,
      level: c.level,
      zoneId: c.zone_id || 'starter_zone',
      modelFile: jobDef?.modelFile || 'Adventurer.glb'
    };
  });

  ctx.sendToSocket(socket.id, {
    type: PacketType.CHARACTER_LIST,
    timestamp: Date.now(),
    data: { characters: characterInfos }
  });
}

async function handleCharacterCreate(ctx: NetworkContext, socket: Socket, data: any): Promise<void> {
  const playerId = ctx.state.socketToPlayer.get(socket.id);
  if (!playerId) return;

  if (!Validator.validatePlayerName(data.name)) {
    ctx.sendToSocket(socket.id, {
      type: PacketType.ERROR,
      timestamp: Date.now(),
      data: { message: 'Invalid character name. Use 3-20 alphanumeric characters.' }
    });
    return;
  }

  const result = await ctx.auth.createCharacter(playerId, data.name, data.race || 'human', data.characterClass, data.racialPassive);

  if (result.success) {
    const jobDef = JOB_DEFINITIONS[data.characterClass as JobId];
    ctx.sendToSocket(socket.id, {
      type: PacketType.CHARACTER_CREATE,
      timestamp: Date.now(),
      data: {
        character: {
          id: result.characterId,
          name: data.name,
          class: data.characterClass,
          race: data.race || 'human',
          jobId: data.characterClass,
          level: 1,
          zoneId: 'starter_zone',
          modelFile: jobDef?.modelFile || 'Adventurer.glb'
        }
      }
    });
  } else {
    ctx.sendToSocket(socket.id, {
      type: PacketType.ERROR,
      timestamp: Date.now(),
      data: { message: result.error }
    });
  }
}

async function handleLogout(ctx: NetworkContext, socket: Socket, _data: any): Promise<void> {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (characterId) {
    const session = ctx.state.players.get(characterId);
    if (session) {
      await ctx.auth.saveCharacter(characterId, {
        level: session.stats.level,
        experience: session.stats.experience,
        position: session.position,
        zoneId: session.zoneId,
        statPoints: session.statPoints,
        unspentStatPoints: session.unspentStatPoints,
        unspentSkillPoints: session.unspentSkillPoints,
        skillProficiencies: session.skillProficiencies,
        skillAdeptness: session.skillAdeptness,
        jobId: session.jobId,
        nation: session.nation,
        lastSafeZoneId: session.lastSafeZoneId,
        inventory: session.inventory,
        equipment: session.equipment,
        gold: session.gold,
      quests: session.quests,
      recipes: session.learnedRecipes,
      unlockedZones: session.unlockedZones,
    }).catch(err => console.error('Failed to save character on logout:', err));

      ctx.cleanupPlayerZoneResources(session);

      ctx.broadcastInZone(session.zoneId, {
        type: PacketType.ENTITY_DESPAWN,
        timestamp: Date.now(),
        data: { entityId: characterId }
      });

      const partyResult = ctx.partySys.handleDisconnect(characterId);
      if (partyResult && partyResult.party.members.length > 0) {
        ctx.sendPartyUpdate(partyResult.party.partyId);
      }

      ctx.tradeSys.handleDisconnect(characterId);

      ctx.state.players.delete(characterId);
      ctx.state.playerToSocket.delete(characterId);
      ctx.unregisterPlayerFromZone(characterId);
      ctx.clearMovementThrottle(characterId);
      void ctx.presence.markOffline(characterId);
    }
  }

  ctx.state.socketToPlayer.delete(socket.id);
}

async function handleCharacterSelect(ctx: NetworkContext, socket: Socket, data: any): Promise<void> {
  const playerId = ctx.state.socketToPlayer.get(socket.id);
  if (!playerId) return;

  let session: PlayerSession;

  // ── Cross-shard handoff resolution ───────────────────────────────────────
  // If the player was handed off from another shard, use the live session
  // from Redis (preserves buffs, cooldowns, recent inventory changes). Falls
  // back to normal DB-based creation if no handoff is pending.
  const handoffSession = await ctx.resolveZoneHandoff(data.characterId);
  if (handoffSession) {
    session = handoffSession;
    session.socketId = socket.id;
    session.playerId = playerId;
    ctx.playerSys.recalcStats(session);
  } else {
    const characters = await ctx.auth.getCharacters(playerId);
    const char = characters.find(c => c.id === data.characterId);
    if (!char) {
      ctx.sendToSocket(socket.id, {
        type: PacketType.ERROR,
        timestamp: Date.now(),
        data: { message: 'Character not found' }
      });
      return;
    }

    session = ctx.playerSys.createSession(
      playerId,
      socket.id,
      playerId,
      char.id,
      char.name,
      char.race || 'human',
      (char.job_id || char.class) as any,
      char.level,
      char.stat_points ? (typeof char.stat_points === 'string' ? JSON.parse(char.stat_points) : char.stat_points) : createDefaultStatPoints(),
      char.unspent_stat_points || 0,
      char.unspent_skill_points || 0,
      char.skill_proficiencies ? (typeof char.skill_proficiencies === 'string' ? JSON.parse(char.skill_proficiencies) : char.skill_proficiencies) : createDefaultSkillProficiencies(),
      char.skill_adeptness ? (typeof char.skill_adeptness === 'string' ? JSON.parse(char.skill_adeptness) : char.skill_adeptness) : createDefaultSkillAdeptness(getDesignJobId(char.job_id || char.class)),
      char.experience || 0
    );

    session.zoneId = char.zone_id || 'starter_zone';
    session.nation = (char.nation as 'varik' | 'pfelstein' | 'latugan' | null) || null;
    session.lastSafeZoneId = char.last_safe_zone_id || session.zoneId;
    session.gold = char.gold || 100;
    session.racialPassive = char.racial_passive || undefined;
    session.role = await ctx.auth.getAccountRole(playerId);

    if (char.inventory) {
      const parsed = typeof char.inventory === 'string' ? JSON.parse(char.inventory) : char.inventory;
      if (Array.isArray(parsed)) session.inventory = parsed;
    }
    if (char.equipment) {
      const parsed = typeof char.equipment === 'string' ? JSON.parse(char.equipment) : char.equipment;
      if (parsed && typeof parsed === 'object') session.equipment = normalizeEquipment(parsed);
    }
    if (char.character_quests) {
      const parsed = typeof char.character_quests === 'string' ? JSON.parse(char.character_quests) : char.character_quests;
      if (Array.isArray(parsed)) session.quests = parsed;
    }
    if (char.character_recipes) {
      const parsed = typeof char.character_recipes === 'string' ? JSON.parse(char.character_recipes) : char.character_recipes;
      if (Array.isArray(parsed)) session.learnedRecipes = parsed;
    }
    if (char.character_unlocked_zones) {
      const parsed = typeof char.character_unlocked_zones === 'string' ? JSON.parse(char.character_unlocked_zones) : char.character_unlocked_zones;
      if (Array.isArray(parsed)) session.unlockedZones = parsed;
    }

    ctx.playerSys.recalcStats(session);

    const zoneDef = getZoneDefinition(session.zoneId);
    if (char.position_x === 0 && char.position_y === 0 && char.position_z === 0) {
      session.position = { ...(zoneDef?.playerSpawn || { x: 0, y: 0, z: 0 }) };
    } else {
      session.position = { x: char.position_x, y: char.position_y, z: char.position_z };
    }
  }

  ctx.state.players.set(session.characterId, session);
  ctx.state.playerToSocket.set(session.characterId, socket.id);
  ctx.state.socketToPlayer.set(socket.id, session.characterId);
  ctx.registerPlayerInZone(session.characterId, session.zoneId);
  void ctx.presence.markOnline(session.characterId);

  ctx.sendToSocket(socket.id, {
    type: PacketType.CHARACTER_SELECT,
    timestamp: Date.now(),
    data: {
      characterId: session.characterId,
      characterName: session.characterName,
      characterClass: session.jobId,
      race: session.race,
      jobId: session.jobId,
      baseClass: session.baseClass,
      stats: session.stats,
      position: session.position,
      rotation: session.rotation,
      zoneId: session.zoneId,
      inventory: session.inventory,
      equipment: session.equipment,
      gold: session.gold,
      quests: session.quests,
      statPoints: session.statPoints,
      unspentStatPoints: session.unspentStatPoints,
      unspentSkillPoints: session.unspentSkillPoints,
      skillProficiencies: session.skillProficiencies,
      skillAdeptness: session.skillAdeptness,
      statBreakdown: session.statBreakdown,
      racialPassive: session.racialPassive,
      role: session.role,
      learnedRecipes: session.learnedRecipes || []
    }
  });

  ctx.sendZoneState(socket, session.zoneId);
  ctx.broadcastInZone(session.zoneId, {
    type: PacketType.ENTITY_SPAWN,
    timestamp: Date.now(),
    data: {
      id: session.characterId,
      type: 'player',
      position: session.position,
      rotation: session.rotation,
      data: { name: session.characterName, class: session.jobId, race: session.race, jobId: session.jobId, level: session.stats.level, health: session.stats.health, maxHealth: session.stats.maxHealth, modelFile: JOB_DEFINITIONS[session.jobId]?.modelFile, invisible: session.statusEffects?.some((e: any) => e.type === StatusEffectType.INVISIBLE) || false, role: session.role }
    }
  });
}

async function handleCharacterDelete(ctx: NetworkContext, socket: Socket, data: any): Promise<void> {
  const playerId = ctx.state.socketToPlayer.get(socket.id);
  if (!playerId) return;

  await ctx.auth.deleteCharacter(playerId, data.characterId);
  ctx.sendToSocket(socket.id, {
    type: PacketType.CHARACTER_DELETE,
    timestamp: Date.now(),
    data: { characterId: data.characterId }
  });
}

async function handleReturnToCharacterSelect(ctx: NetworkContext, socket: Socket, _data: any): Promise<void> {
  const characterId = ctx.findCharacterBySocket(socket.id);
  if (!characterId) return;

  const session = ctx.state.players.get(characterId);
  if (session) {
    await ctx.auth.saveCharacter(characterId, {
      level: session.stats.level,
      experience: session.stats.experience,
      position: session.position,
      zoneId: session.zoneId,
      statPoints: session.statPoints,
      unspentStatPoints: session.unspentStatPoints,
      unspentSkillPoints: session.unspentSkillPoints,
      skillProficiencies: session.skillProficiencies,
      skillAdeptness: session.skillAdeptness,
      jobId: session.jobId,
      nation: session.nation,
      lastSafeZoneId: session.lastSafeZoneId,
      inventory: session.inventory,
      equipment: session.equipment,
      gold: session.gold,
      quests: session.quests,
      recipes: session.learnedRecipes,
      unlockedZones: session.unlockedZones,
    }).catch(err => console.error('Failed to save character on logout:', err));

    ctx.cleanupPlayerZoneResources(session);

    ctx.broadcastInZone(session.zoneId, {
      type: PacketType.ENTITY_DESPAWN,
      timestamp: Date.now(),
      data: { entityId: characterId }
    });

    const partyResult = ctx.partySys.handleDisconnect(characterId);
    if (partyResult && partyResult.party.members.length > 0) {
      ctx.sendPartyUpdate(partyResult.party.partyId);
    }

    ctx.tradeSys.handleDisconnect(characterId);

    ctx.state.players.delete(characterId);
    ctx.state.playerToSocket.delete(characterId);
    ctx.unregisterPlayerFromZone(characterId);
    ctx.clearMovementThrottle(characterId);
    void ctx.presence.markOffline(characterId);

    ctx.state.socketToPlayer.set(socket.id, session.playerId);
  }

  const playerId = ctx.state.socketToPlayer.get(socket.id);
  if (!playerId) return;

  const characters = await ctx.auth.getCharacters(playerId);
  const characterInfos = characters.map(c => {
    const jobDef = JOB_DEFINITIONS[(c.job_id || c.class) as JobId];
    return {
      id: c.id,
      name: c.name,
      class: c.class || c.job_id,
      race: c.race || 'human',
      jobId: c.job_id || c.class,
      level: c.level,
      zoneId: c.zone_id || 'starter_zone',
      modelFile: jobDef?.modelFile || 'Adventurer.glb'
    };
  });

  ctx.sendToSocket(socket.id, {
    type: PacketType.CHARACTER_LIST,
    timestamp: Date.now(),
    data: { characters: characterInfos }
  });
}
