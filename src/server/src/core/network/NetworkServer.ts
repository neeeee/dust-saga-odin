import { Server as SocketIOServer, Socket } from 'socket.io';
import { createAdapter } from '@socket.io/redis-adapter';
import type { RedisClientType } from 'redis';
import {
  Packet, PacketType, PlayerSession, Validator,
  JOB_DEFINITIONS, RACE_DATA, createDefaultStatPoints, createDefaultSkillProficiencies, createDefaultSkillAdeptness,
  getBaseClassForJob, calculateDerivedStats, getExperienceToNextLevel, getStatPointsGainedAtLevel,
  getSkillPointsGainedAtLevel, MAX_LEVEL,
  getDesignJobId,
  StatType, JobId, Race, processRacialOnDamage, applyRacialPotionHealing,
  getAdvancementOptions, BaseClass,
  REGEN_CONFIG, REST_REGEN_CONFIG, SKILL_TARGET_RULES, SkillTargetType, SkillType,
  PartyVisibility, LootRule, MAX_LOOT_POOL,
  GROUND_TARGETED_AOE_SKILLS, DEFAULT_AOE_RADIUS,
  AOETargetMode,
  StatusEffectType, StatusEffect, EnemyInstance,
  BuffData, resolveStatTieredValue,
  OnHitProc,
  getEffectiveStats,
  computeAilmentResist, computeDisorderResist, computeDebuffAccuracy, rollDebuffApplication,
  calculateWeaponElementalDamage,
  calculateDodge,
  calculateHitChance,
  NATION_ZONE_MAP,
  ZoneType,
  normalizeEquipment,
  getEnemyDefinition, getZoneDefinition, NPC_DATABASE, getNPCsInZone,
  SpatialEntry,
  SUMMON_STATS, BANISH_RADIUS,
  getGloomRecoilRate,
  isZonePvpEnabled,
  QuestStatus, QuestType,
  worldToCell, cellLabel,
} from '@dust-saga/shared';
import { AuthManager } from '../auth/AuthManager';
import { CombatSystem } from '../ecs/systems/CombatSystem';
import { AISystem } from '../ecs/systems/AISystem';
import { LootSystem, LootInstance } from '../ecs/systems/LootSystem';
import { PlayerSystem } from '../ecs/systems/PlayerSystem';
import { SkillSystem } from '../ecs/systems/SkillSystem';
import { PartySystem } from '../ecs/systems/PartySystem';
import { EnmitySystem } from '../ecs/systems/EnmitySystem';
import { TradeSystem } from '../ecs/systems/TradeSystem';
import { SpawnManager } from '../world/SpawnManager';
import { SummonManager } from '../world/SummonManager';
import { DummyManager, DummyMeta } from '../world/DummyManager';
import { SpatialIndexManager } from '../world/SpatialIndexManager';
import { AOEZoneManager } from '../world/AOEZoneManager';
import { SongProximityManager } from '../world/SongProximityManager';
import { BlockingProximityManager } from '../world/BlockingProximityManager';
import { KnockbackManager } from '../world/KnockbackManager';
import { SummonCombatDeps } from '../world/SummonManager';
import { MovementThrottle } from '../world/MovementThrottle';
import { ZoneRegistry } from '../world/ZoneInstance';
import { QuestSystem } from '../../systems/QuestSystem';
import { CraftSystem } from '../../systems/CraftSystem';
import { CutsceneSystem } from '../../systems/CutsceneSystem';
import { ItemSystem } from '../../systems/ItemSystem';
import { PresenceService } from '../presence/PresenceService';
import { PacketRelay } from '../presence/PacketRelay';
import { ZoneOwnership } from '../presence/ZoneOwnership';
import { ZoneHandoff } from '../presence/ZoneHandoff';
import { randomUUID } from 'crypto';
import { NetworkContext, ServerGameState, PacketHandler } from './NetworkContext';
import { registerAllHandlers } from './handlers';
import { collectProcs, buildProcStatusEffect, getProcResistCategory, isDrainLifeProc, getDarkRecoilPercent } from '../combat/ProcSystem';
import { getObeliskBuffForWeapon } from '../combat/obeliskBuff';

const STA_DEBUFF_CATEGORIES = new Set(['ailment', 'stun', 'trip', 'knockdown', 'knockback', 'bleed']);
const SPI_DEBUFF_CATEGORIES = new Set(['disorder', 'freeze', 'burn', 'curse', 'sleep', 'weakness', 'weaken']);

export class NetworkServer implements NetworkContext {
  private io: SocketIOServer;
  readonly auth: AuthManager;
  readonly combat: CombatSystem;
  readonly ai: AISystem;
  readonly loot: LootSystem;
  readonly playerSys: PlayerSystem;
  readonly skillSys: SkillSystem;
  readonly partySys: PartySystem;
  readonly enmity: EnmitySystem;
  readonly tradeSys: TradeSystem;
  readonly spawnMgr: SpawnManager;
  readonly summonMgr: SummonManager;
  readonly questSys: QuestSystem;
  readonly craftSys: CraftSystem;
  readonly cutsceneSys: CutsceneSystem;
  readonly itemSys: ItemSystem;
  readonly state: ServerGameState;
  private tickRate: number = 30;
  private handlers: Map<PacketType, PacketHandler>;

  readonly dummyMgr: DummyManager;
  readonly spatialMgr: SpatialIndexManager;
  readonly aoeZoneMgr: AOEZoneManager;
  readonly songMgr: SongProximityManager;
  readonly blockingMgr: BlockingProximityManager;
  readonly knockbackMgr: KnockbackManager;
  private summonCombatDeps: SummonCombatDeps;
  readonly movementThrottle: MovementThrottle = new MovementThrottle();

  readonly zoneRegistry: ZoneRegistry = new ZoneRegistry();

  readonly presence: PresenceService;
  private readonly packetRelay: PacketRelay;
  readonly zoneOwnership: ZoneOwnership;
  readonly zoneHandoff: ZoneHandoff;

  static readonly INTEREST_RADIUS = 50;
  static readonly INTEREST_RADIUS_SQ = 50 * 50;
  private aiTickBucket: number = 0;
  private readonly AI_TICK_STAGGER = 4;

  private addToZonePlayerIndex(zoneId: string, characterId: string): void {
    this.zoneRegistry.getOrCreate(zoneId).addPlayer(characterId);
  }

  private removeFromZonePlayerIndex(characterId: string): void {
    this.zoneRegistry.removePlayerFromAll(characterId);
  }

  private movePlayerZoneIndex(characterId: string, newZoneId: string): void {
    this.removeFromZonePlayerIndex(characterId);
    this.addToZonePlayerIndex(newZoneId, characterId);
  }

  constructor(httpServer: any, presenceOpts: { redis: RedisClientType | null; isRedisConnected: () => boolean } = { redis: null, isRedisConnected: () => false }) {
    this.io = new SocketIOServer(httpServer, {
      cors: {
        origin: process.env.CLIENT_URL || 'http://localhost:3000',
        methods: ['GET', 'POST']
      },
      pingTimeout: 60000,
      pingInterval: 25000
    });

    const shardId = process.env.SHARD_ID || `shard-${randomUUID()}`;
    this.presence = new PresenceService(shardId, presenceOpts.redis, presenceOpts.isRedisConnected);
    this.packetRelay = new PacketRelay(
      shardId,
      presenceOpts.redis,
      presenceOpts.isRedisConnected,
      this.presence,
      (id, pkt) => {
        const sid = this.state.playerToSocket.get(id);
        if (sid) this.sendToSocket(sid, pkt);
      },
    );
    this.zoneOwnership = new ZoneOwnership(shardId, presenceOpts.redis, presenceOpts.isRedisConnected);
    this.zoneHandoff = new ZoneHandoff(presenceOpts.redis, presenceOpts.isRedisConnected);
    console.log(`Shard ID: ${shardId}`);

    this.auth = AuthManager.getInstance();
    this.combat = new CombatSystem({ getEntity: () => undefined, getEntitiesWithComponent: () => [], getAllEntities: () => [], addComponent: () => {}, removeComponent: () => {}, createEntity: () => ({ id: '', components: new Map() }), removeEntity: () => {} } as any);
    this.ai = new AISystem({ getEntity: () => undefined, getEntitiesWithComponent: () => [], getAllEntities: () => [], addComponent: () => {}, removeComponent: () => {}, createEntity: () => ({ id: '', components: new Map() }), removeEntity: () => {} } as any);
    this.loot = new LootSystem({ getEntity: () => undefined, getEntitiesWithComponent: () => [], getAllEntities: () => [], addComponent: () => {}, removeComponent: () => {}, createEntity: () => ({ id: '', components: new Map() }), removeEntity: () => {} } as any);
    this.playerSys = new PlayerSystem({ getEntity: () => undefined, getEntitiesWithComponent: () => [], getAllEntities: () => [], addComponent: () => {}, removeComponent: () => {}, createEntity: () => ({ id: '', components: new Map() }), removeEntity: () => {} } as any);
    this.skillSys = new SkillSystem();
    this.enmity = new EnmitySystem();
    this.tradeSys = new TradeSystem();
    this.ai.enmitySys = this.enmity;
    this.spawnMgr = new SpawnManager();
    this.summonMgr = new SummonManager();
    this.questSys = new QuestSystem();
    this.craftSys = new CraftSystem();
    this.cutsceneSys = new CutsceneSystem();
    this.itemSys = new ItemSystem();
    // Wire item lookups into systems that consume ItemDefinition at runtime,
    // so they read the ItemSystem cache (DB-backed, hot-reloadable) instead of
    // the static ITEM_DATABASE import.
    this.combat.itemSys = this.itemSys;
    this.loot.itemSys = this.itemSys;
    this.playerSys.itemSys = this.itemSys;
    this.skillSys.itemSys = this.itemSys;
    this.tradeSys.itemSys = this.itemSys;
    this.craftSys.itemSys = this.itemSys;
    this.partySys = new PartySystem({
      redis: presenceOpts.redis,
      isConnected: presenceOpts.isRedisConnected,
      shardId,
    });
    this.state = {
      players: new Map(),
      socketToPlayer: new Map(),
      playerToSocket: new Map()
    };

    this.handlers = registerAllHandlers();

    this.setupCallbacks();
    this.setupEventHandlers();
    this.setupPlayerCallbacks();

    this.tradeSys.init({
      sendToPlayer: (id, pkt) => this.sendToPlayer(id, pkt),
      findPlayer: (id) => this.findPlayerByCharacterId(id),
    });

    this.dummyMgr = new DummyManager({
      getPlayers: () => this.state.players,
      registerPlayerInZone: (id, zone) => this.registerPlayerInZone(id, zone),
      unregisterPlayerFromZone: (id) => this.unregisterPlayerFromZone(id),
      clearMovementThrottle: (id) => this.clearMovementThrottle(id),
      broadcastInZone: (zone, pkt) => this.broadcastInZone(zone, pkt),
      sendToPlayer: (id, pkt) => this.sendToPlayer(id, pkt),
      sendPartyUpdate: (partyId) => this.sendPartyUpdate(partyId),
      recalcStats: (s) => this.playerSys.recalcStats(s),
      getPartySys: () => this.partySys,
      getPlayerSys: () => this.playerSys,
      getTickRate: () => this.tickRate,
      getItemDef: (id: string) => this.itemSys.getItemDefinition(id),
    });

    this.spatialMgr = new SpatialIndexManager({
      getPlayers: () => this.state.players,
      getSpawnManager: () => this.spawnMgr,
    });

    this.aoeZoneMgr = new AOEZoneManager({
      getPlayers: () => this.state.players,
      getSpawnManager: () => this.spawnMgr,
      getSkillSystem: () => this.skillSys,
      broadcastInZone: (zone, pkt) => this.broadcastInZone(zone, pkt),
      applyAOEDamageToTargets: (caster, skillName, pos, radius) => this.applyAOEDamageToTargets(caster, skillName, pos, radius),
      onEntityEnterAOE: (caster, skillName, targetId, pos, radius) => this.onEntityEnterAOE(caster, skillName, targetId, pos, radius),
    });

    this.songMgr = new SongProximityManager({
      getPlayers: () => this.state.players,
      getSkillSystem: () => this.skillSys,
      getPlayerSys: () => this.playerSys,
      isPartyMember: (a, b) => this.isPartyMember(a, b),
      queryPlayersNear: (x, z, r, zid) => this.queryPlayersNear(x, z, r, zid),
      broadcastInZone: (zone, pkt) => this.broadcastInZone(zone, pkt),
      sendToPlayer: (id, pkt) => this.sendToPlayer(id, pkt),
      broadcastEntityEffects: (s) => this.broadcastEntityEffects(s),
      onRedSongPulse: (caster, skill, radius) => this.applyRedSongDamage(caster, skill, radius),
    });

    this.blockingMgr = new BlockingProximityManager({
      getPlayers: () => this.state.players,
      getPlayerSys: () => this.playerSys,
      queryPlayersNear: (x, z, r, zid) => this.queryPlayersNear(x, z, r, zid),
      sendToPlayer: (id, pkt) => this.sendToPlayer(id, pkt),
      broadcastEntityEffects: (s) => this.broadcastEntityEffects(s),
    });

    this.knockbackMgr = new KnockbackManager({
      getSpawnManager: () => this.spawnMgr,
      forEachPlayerInZone: (zid, cb) => this.forEachPlayerInZone(zid, cb),
      getTickRate: () => this.tickRate,
    });

    this.summonCombatDeps = {
      getSpawnManager: () => this.spawnMgr,
      getEnmity: () => this.enmity,
      getTickRate: () => this.tickRate,
      broadcastInZone: (zone, pkt) => this.broadcastInZone(zone, pkt),
      damageEnemy: (enemy, dmg, att) => this.damageEnemy(enemy, dmg, att),
      getEnemyEffectiveDefense: (enemy) => this.getEnemyEffectiveDefense(enemy),
      handleEnemyKill: (id, killer) => this.handleEnemyKill(id, killer),
      shouldApplyDebuff: (eff, tid, cid) => this.shouldApplyDebuff(eff, tid, cid),
    };
  }

  /**
   * Attach the Socket.IO Redis adapter so `io.to('zone:X')` room broadcasts
   * propagate across processes. No-op for gameplay in single-process mode; this
   * only enables cross-shard broadcast for the upcoming sharded deployment.
   * Clients must already be connected. Caller owns their lifecycle.
   */
  useRedisAdapter(pubClient: RedisClientType, subClient: RedisClientType): void {
    this.io.adapter(createAdapter(pubClient, subClient));
    console.log('Socket.IO Redis adapter attached (cross-instance broadcast enabled)');
  }

  /**
   * Start the cross-shard packet relay so `sendToPlayer` can deliver packets to
   * players hosted on other shards. The caller owns the lifecycle of the
   * dedicated subscribe client (subscribe mode is exclusive in node-redis).
   */
  async usePacketRelay(subClient: RedisClientType): Promise<void> {
    await this.packetRelay.start(subClient);
  }

  async stopPacketRelay(): Promise<void> {
    await this.packetRelay.stop();
  }

  /**
   * Start cross-shard party state sync. The caller owns the lifecycle of the
   * dedicated subscribe client.
   */
  async usePartySync(subClient: RedisClientType): Promise<void> {
    await this.partySys.startSync(subClient);
  }

  async stopPartySync(): Promise<void> {
    await this.partySys.stopSync();
  }

  get dummyMeta(): Map<string, DummyMeta> {
    return this.dummyMgr.dummyMeta;
  }

  findCharacterBySocket(socketId: string): string | undefined {
    return this.state.socketToPlayer.get(socketId);
  }

  findPlayerByCharacterId(characterId: string): PlayerSession | undefined {
    return this.state.players.get(characterId);
  }

  findZoneOfEntity(entityId: string): string {
    const enemyZone = this.spawnMgr.findZoneOfEnemy(entityId);
    if (enemyZone) return enemyZone;
    for (const [, session] of this.state.players) {
      if (session.characterId === entityId) return session.zoneId;
    }
    return 'starter_zone';
  }

  findZoneOfEnemy(enemyId: string): string | undefined {
    return this.spawnMgr.findZoneOfEnemy(enemyId);
  }

  sendToSocket(socketId: string, packet: Packet): void {
    this.io.to(socketId).emit('packet', packet);
  }

  registerPlayerInZone(characterId: string, zoneId: string): void {
    this.addToZonePlayerIndex(zoneId, characterId);
    this.insertPlayerSpatial(characterId);
    const socketId = this.state.playerToSocket.get(characterId);
    if (socketId) {
      this.io.of('/').sockets.get(socketId)?.join(`zone:${zoneId}`);
    }
  }

  unregisterPlayerFromZone(characterId: string): void {
    const zoneId = this.getZoneIdForCharacter(characterId);
    this.removeFromZonePlayerIndex(characterId);
    this.removePlayerSpatial(characterId);
    if (zoneId) {
      const socketId = this.state.playerToSocket.get(characterId);
      if (socketId) {
        this.io.of('/').sockets.get(socketId)?.leave(`zone:${zoneId}`);
      }
    }
  }

  movePlayerToZone(characterId: string, newZoneId: string): void {
    const oldZoneId = this.getZoneIdForCharacter(characterId);
    const socketId = this.state.playerToSocket.get(characterId);
    if (socketId) {
      if (oldZoneId) {
        this.io.of('/').sockets.get(socketId)?.leave(`zone:${oldZoneId}`);
      }
      this.io.of('/').sockets.get(socketId)?.join(`zone:${newZoneId}`);
    }
    this.removePlayerSpatial(characterId);
    this.movePlayerZoneIndex(characterId, newZoneId);
    this.insertPlayerSpatial(characterId);
  }

  private getZoneIdForCharacter(characterId: string): string | undefined {
    return this.zoneRegistry.zoneOf(characterId);
  }

  forEachPlayerInZone(zoneId: string, cb: (id: string, player: PlayerSession) => void): void {
    const zone = this.zoneRegistry.get(zoneId);
    if (!zone) return;
    for (const id of zone.players) {
      const p = this.state.players.get(id);
      if (p) cb(id, p);
    }
  }

  /**
   * Tear down all zone-local resources a player owns (AOE zones, summons, song
   * buffs, dummies). Called on EVERY zone transition — same-shard or cross-shard
   * — BEFORE mutating `session.zoneId`. This fixes the long-standing leak where
   * summons/AOE/song persisted in the old zone after the player left.
   *
   * Does NOT touch state maps, presence, party, trade, or DB — those are handled
   * by disconnect (same-shard) or initiateZoneHandoff (cross-shard).
   */
  cleanupPlayerZoneResources(session: PlayerSession): void {
    const characterId = session.characterId;

    if (session.isResting) {
      this.cancelRest(session);
    }

    this.aoeZoneMgr.cleanupOwner(characterId);

    const despawnedSummons = this.summonMgr.despawnAllForOwner(characterId);
    for (const summonId of despawnedSummons) {
      this.broadcastInZone(session.zoneId, {
        type: PacketType.ENTITY_DESPAWN,
        timestamp: Date.now(),
        data: { entityId: summonId },
      });
    }

    this.removeSongProximityBuffs(session);

    this.dummyMgr.cleanupOwner(characterId, session.zoneId);

    session.activeCast = null;
  }

  cancelRest(session: PlayerSession): void {
    if (!session.isResting) return;
    session.isResting = false;
    this.broadcastInZone(session.zoneId, {
      type: PacketType.PLAYER_REST,
      timestamp: Date.now(),
      data: { characterId: session.characterId, isResting: false }
    });
  }

  /**
   * Full teardown for cross-shard handoff: zone resource cleanup + state-map
   * removal + presence update. Called after the session has been serialized to
   * Redis via ZoneHandoff.initiate. Does NOT save to DB (the old shard already
   * saved) or mark presence offline (the player is still online, now on the new
   * shard).
   */
  completeZoneHandoffDeparture(session: PlayerSession): void {
    const characterId = session.characterId;

    this.cleanupPlayerZoneResources(session);

    this.broadcastInZone(session.zoneId, {
      type: PacketType.ENTITY_DESPAWN,
      timestamp: Date.now(),
      data: { entityId: characterId },
    });

    this.state.players.delete(characterId);
    this.state.playerToSocket.delete(characterId);
    this.unregisterPlayerFromZone(characterId);
    this.clearMovementThrottle(characterId);
  }

  async resolveZoneHandoff(characterId: string): Promise<PlayerSession | null> {
    return this.zoneHandoff.resolve(characterId);
  }

  async initiateZoneHandoff(session: PlayerSession): Promise<boolean> {
    return this.zoneHandoff.initiate(session.characterId, session);
  }

  sendToPlayer(characterId: string, packet: Packet): void {
    const socketId = this.state.playerToSocket.get(characterId);
    if (socketId) {
      this.sendToSocket(socketId, packet);
      return;
    }
    // Not local — route via cross-shard relay (fire-and-forget, no-op without Redis)
    this.packetRelay.relay(characterId, packet);
  }

  broadcastInZone(zoneId: string, packet: Packet, excludeCharacterId?: string): void {
    if (excludeCharacterId) {
      const excludeSocket = this.state.playerToSocket.get(excludeCharacterId);
      if (excludeSocket) {
        this.io.to(`zone:${zoneId}`).except(excludeSocket).emit('packet', packet);
      } else {
        this.io.to(`zone:${zoneId}`).emit('packet', packet);
      }
    } else {
      this.io.to(`zone:${zoneId}`).emit('packet', packet);
    }
  }

  broadcastEntityEffects(session: PlayerSession): void {
    this.broadcastInZone(session.zoneId, {
      type: PacketType.ENTITY_STATUS_EFFECTS,
      timestamp: Date.now(),
      data: { entityId: session.characterId, effects: session.statusEffects }
    }, session.characterId);
  }

  updatePlayerSpatialPosition(characterId: string, position: { x: number; z: number }): void {
    this.spatialMgr.updatePlayerSpatialPosition(characterId, position);
  }

  insertPlayerSpatial(characterId: string): void {
    this.spatialMgr.insertPlayerSpatial(characterId);
  }

  removePlayerSpatial(characterId: string): void {
    this.spatialMgr.removePlayerSpatial(characterId);
  }

  insertEnemySpatial(enemy: EnemyInstance): void {
    this.spatialMgr.insertEnemySpatial(enemy);
  }

  removeEnemySpatial(enemyId: string): void {
    this.spatialMgr.removeEnemySpatial(enemyId);
  }

  queryEnemiesNear(x: number, z: number, radius: number, zoneId: string): SpatialEntry<EnemyInstance>[] {
    return this.spatialMgr.queryEnemiesNear(x, z, radius, zoneId);
  }

  queryPlayersNear(x: number, z: number, radius: number, zoneId: string): SpatialEntry<PlayerSession>[] {
    return this.spatialMgr.queryPlayersNear(x, z, radius, zoneId);
  }

  isPartyMember(characterId: string, targetId: string): boolean {
    const party = this.partySys.getPartyForMember(characterId);
    if (!party) return false;
    return party.members.some(m => m.characterId === targetId);
  }

  refreshPartyForMember(characterId: string): void {
    const partyId = this.partySys.getPartyForMember(characterId)?.partyId;
    if (!partyId) return;
    const session = this.state.players.get(characterId);
    if (session) this.partySys.updateMemberStats(characterId, session);
    this.sendPartyUpdate(partyId);
  }

  sendPartyUpdate(partyId: string): void {
    const partyData = this.partySys.getPartyData(partyId);
    if (!partyData) return;

    const pool = this.loot.listPartyPool(partyId);
    for (const member of partyData.members) {
      this.sendToPlayer(member.characterId, {
        type: PacketType.PARTY_UPDATE,
        timestamp: Date.now(),
        data: {
          partyId: partyData.partyId,
          leaderId: partyData.leaderId,
          members: partyData.members,
          settings: partyData.settings,
          lootPool: pool
        }
      });
    }
  }

  handlePlayerDeath(session: PlayerSession): void {
    session.stats.health = 0;
    session.isDead = true;
    session.isResting = false;
    session.deathTime = Date.now();
    session.activeCast = null;

    this.spawnMgr.iterateAllEnemies(enemy => {
      if (enemy.targetId === session.characterId) {
        this.enmity.removePlayer(enemy, session.characterId);
        const topTarget = this.enmity.getTopTarget(enemy);
        if (topTarget) {
          enemy.targetId = topTarget.characterId;
          if (enemy.state === 'return') {
            enemy.state = 'chase';
          }
        } else {
          enemy.state = 'return';
          enemy.targetId = null;
        }
      } else if (enemy.enmityTable?.[session.characterId]) {
        this.enmity.removePlayer(enemy, session.characterId);
      }
    });

    this.sendToPlayer(session.characterId, {
      type: PacketType.DEATH,
      timestamp: Date.now(),
      data: { entityId: session.characterId, isDead: true }
    });

    this.broadcastInZone(session.zoneId, {
      type: PacketType.STATS_UPDATE,
      timestamp: Date.now(),
      data: { entityId: session.characterId, health: 0, maxHealth: session.stats.maxHealth }
    }, session.characterId);
    this.refreshPartyForMember(session.characterId);
  }

  grantQuestKillCredit(killer: PlayerSession, enemyType: string, zoneId: string): void {
    const creditRecipients: PlayerSession[] = [killer];
    const party = this.partySys.getPartyForMember(killer.characterId);
    if (party) {
      for (const member of party.members) {
        if (member.characterId === killer.characterId) continue;
        const memberSession = this.findPlayerByCharacterId(member.characterId);
        if (!memberSession) continue;
        if (memberSession.zoneId !== zoneId) continue;
        const dx = memberSession.position.x - killer.position.x;
        const dz = memberSession.position.z - killer.position.z;
        if (Math.sqrt(dx * dx + dz * dz) <= 50) {
          creditRecipients.push(memberSession);
        }
      }
    }

    for (const recipient of creditRecipients) {
      const progress = this.questSys.onEnemyKill(recipient, enemyType);
      if (progress.progressed.length === 0 && progress.completed.length === 0) continue;

      const message = progress.completed.map(qid => {
        const def = this.questSys.getQuestDefinition(qid);
        return `Quest "${def?.title || qid}" completed! Return to the NPC.`;
      }).join('\n');

      this.sendToPlayer(recipient.characterId, {
        type: PacketType.QUEST_PROGRESS,
        timestamp: Date.now(),
        data: {
          quests: recipient.quests,
          completed: progress.completed,
          ...(message ? { message } : {}),
        }
      });
    }
  }

  checkQuestCellEntry(session: PlayerSession): void {
    const hasExploreObjective = session.quests.some(
      q => q.status === QuestStatus.IN_PROGRESS && q.objectives.some(
        o => (o.type === QuestType.EXPLORE || o.type === QuestType.ESCORT) && o.cell && o.currentCount < o.requiredCount
      )
    );
    if (!hasExploreObjective) return;

    const zoneDef = getZoneDefinition(session.zoneId);
    if (!zoneDef) return;

    const cell = worldToCell(session.position.x, session.position.z, zoneDef.size);
    if (!cell) return;
    const label = cellLabel(cell);
    if (session.lastQuestCell === label) return;
    session.lastQuestCell = label;

    const progress = this.questSys.onCellEnter(session, label, session.zoneId);
    if (progress.progressed.length === 0 && progress.completed.length === 0) return;

    const message = progress.completed.map(qid => {
      const def = this.questSys.getQuestDefinition(qid);
      return `Quest "${def?.title || qid}" completed! Return to the NPC.`;
    }).join('\n');

    this.sendToPlayer(session.characterId, {
      type: PacketType.QUEST_PROGRESS,
      timestamp: Date.now(),
      data: {
        quests: session.quests,
        completed: progress.completed,
        ...(message ? { message } : {}),
      }
    });
  }

  startCutscene(session: PlayerSession, cutsceneId: string): boolean {
    const cs = this.cutsceneSys.getCutscene(cutsceneId);
    if (!cs) return false;
    if (session.inCutscene) return false;

    session.inCutscene = true;
    session.cutsceneReturnPosition = { ...session.position };
    session.cutsceneReturnRotation = { ...session.rotation };
    session.currentNpcId = 'cutscene';

    this.sendToPlayer(session.characterId, {
      type: PacketType.CUTSCENE_START,
      timestamp: Date.now(),
      data: { cutsceneId, steps: cs.steps }
    });
    return true;
  }

  completeCutscene(session: PlayerSession): void {
    if (!session.inCutscene) return;

    session.inCutscene = false;
    session.currentNpcId = null;

    if (session.cutsceneReturnPosition) {
      session.position = { ...session.cutsceneReturnPosition };
      session.cutsceneReturnPosition = undefined;
    }
    if (session.cutsceneReturnRotation) {
      session.rotation = { ...session.cutsceneReturnRotation };
      session.cutsceneReturnRotation = undefined;
    }

    this.sendToPlayer(session.characterId, {
      type: PacketType.CUTSCENE_END,
      timestamp: Date.now(),
      data: {
        position: session.position,
        rotation: session.rotation,
      }
    });
  }

  /**
   * Unified loot distribution for an enemy kill. Replaces the four duplicated
   * paths that used to inline this (handleEnemyKill, combat.onDeath,
   * executeConeSkillInternal, applyAOEDamageToTargets). Honors the active
   * party's loot rule (FFA / ROUND_ROBIN / NEED_GREED / POOL) so AOE and cone
   * kills no longer bypass party distribution.
   */
  handleEnemyLoot(
    killer: PlayerSession,
    enemyType: string,
    enemyPosition: { x: number; y: number; z: number }
  ): void {
    const enemyDef = getEnemyDefinition(enemyType);
    if (!enemyDef) return;
    const drops = this.loot.rollLootTable(enemyDef.lootTable);
    if (drops.length === 0) return;

    const sourceName = enemyDef.name || enemyType;
    const party = this.partySys.getPartyForMember(killer.characterId);

    // Solo: simple FFA bag (only the killer is around, but the bag broadcasts
    // to the zone so anyone passing by could grab it).
    if (!party || party.members.length <= 1) {
      const bag = this.loot.spawnFFA(drops, enemyPosition, killer.zoneId, sourceName);
      if (bag) this.broadcastLootSpawn(bag);
      return;
    }

    const rule = this.loot.ruleOf(party.settings.lootRule);

    switch (rule) {
      case LootRule.FFA: {
        const bag = this.loot.spawnFFA(drops, enemyPosition, killer.zoneId, sourceName, party.partyId, rule);
        if (bag) this.broadcastLootSpawn(bag);
        break;
      }
      case LootRule.ROUND_ROBIN: {
        const member = this.loot.pickRoundRobin(party);
        const bag = this.loot.spawnAssigned(drops, enemyPosition, killer.zoneId, sourceName, member.characterId, party.partyId, rule);
        if (bag) this.broadcastLootSpawn(bag);
        break;
      }
      case LootRule.POOL: {
        for (const d of drops) {
          const entry = this.loot.addToPartyPool(party.partyId, d);
          if (!entry) continue;
          for (const m of party.members) {
            this.sendToPlayer(m.characterId, {
              type: PacketType.PARTY_LOOT_ROLL,
              timestamp: Date.now(),
              data: { lootId: entry.lootId, itemId: entry.itemId, itemName: entry.itemName, quantity: entry.quantity, mode: 'pool' }
            });
          }
        }
        this.sendPartyUpdate(party.partyId);
        break;
      }
      case LootRule.NEED_GREED: {
        for (const d of drops) {
          const entry = this.loot.startNeedGreedRoll(party.partyId, party.members, d);
          if (!entry) continue;
          for (const m of party.members) {
            this.sendToPlayer(m.characterId, {
              type: PacketType.PARTY_LOOT_ROLL,
              timestamp: Date.now(),
              data: { lootId: entry.lootId, itemId: entry.itemId, itemName: entry.itemName, quantity: entry.quantity, mode: 'need_greed' }
            });
          }
        }
        break;
      }
      default: {
        const bag = this.loot.spawnFFA(drops, enemyPosition, killer.zoneId, sourceName);
        if (bag) this.broadcastLootSpawn(bag);
      }
    }
  }

  private broadcastLootSpawn(bag: LootInstance): void {
    this.broadcastInZone(bag.zoneId, {
      type: PacketType.LOOT_SPAWN,
      timestamp: Date.now(),
      data: {
        lootId: bag.id,
        position: bag.position,
        sourceName: bag.sourceName,
        itemCount: bag.items.length,
        items: bag.items.map(i => ({ id: i.id, itemId: i.itemId, quantity: i.quantity, rarity: i.rarity })),
        assignedTo: bag.assignedTo,
        assignmentExpiresAt: bag.assignmentExpiresAt,
      }
    });
  }

  /** Tick loot bag expiry + need/greed roll timeouts. Broadcasts LOOT_DESPAWN. */
  tickLootExpiry(): void {
    const expiredBags = this.loot.tickExpiry();
    for (const bag of expiredBags) {
      this.broadcastInZone(bag.zoneId, {
        type: PacketType.LOOT_DESPAWN,
        timestamp: Date.now(),
        data: { lootId: bag.id }
      });
    }
    const expiredRolls = this.loot.expiredRolls();
    for (const r of expiredRolls) {
      const result = this.loot.resolveRoll(r.partyId, r.lootId);
      if (!result) continue;
      const party = this.partySys.getPartyData(r.partyId);
      if (!party) continue;
      for (const m of party.members) {
        this.sendToPlayer(m.characterId, {
          type: PacketType.PARTY_LOOT_RESULT,
          timestamp: Date.now(),
          data: {
            lootId: r.lootId,
            itemId: result.entry.itemId,
            itemName: result.entry.itemName,
            quantity: result.entry.quantity,
            winnerId: result.winnerId,
          }
        });
      }
      if (result.winnerId) {
        const ws = this.state.players.get(result.winnerId);
        if (ws) {
          this.playerSys.addItemToInventory(ws, result.entry.itemId, result.entry.quantity);
          this.sendToPlayer(result.winnerId, {
            type: PacketType.INVENTORY_UPDATE,
            timestamp: Date.now(),
            data: { inventory: ws.inventory, equipment: ws.equipment }
          });
        }
      }
    }
  }

  handleEnemyKill(enemyId: string, killerId: string): void {
    const enemy = this.spawnMgr.getEnemy(enemyId);
    if (!enemy) return;

    const enemyDef = getEnemyDefinition(enemy.enemyType);

    const killer = this.findPlayerByCharacterId(killerId);
    if (killer && enemyDef) {
      this.playerSys.grantExperience(killer, enemyDef.experience);
      this.sendToPlayer(killer.characterId, {
        type: PacketType.EXPERIENCE_GAIN,
        timestamp: Date.now(),
        data: { experience: enemyDef.experience, totalExperience: killer.stats.experience, level: killer.stats.level }
      });
      this.sendToPlayer(killer.characterId, {
        type: PacketType.STATS_UPDATE,
        timestamp: Date.now(),
        data: { characterId: killer.characterId, stats: killer.stats }
      });

      this.grantQuestKillCredit(killer, enemy.enemyType, killer.zoneId);

      this.handleEnemyLoot(killer, enemy.enemyType, enemy.position);
    }

    enemy.state = 'dead';
    enemy.deathTime = Date.now();

    const zone = this.findZoneOfEntity(enemyId);
    this.broadcastInZone(zone, {
      type: PacketType.DEATH,
      timestamp: Date.now(),
      data: { entityId: enemyId, killerId }
    });
    this.broadcastInZone(zone, {
      type: PacketType.ENTITY_DESPAWN,
      timestamp: Date.now(),
      data: { entityId: enemyId }
    });
  }

  handleRevivePlayerBySession(caster: PlayerSession, targetId: string): void {
    const reviveTarget = this.state.players.get(targetId);
    if (!reviveTarget || !reviveTarget.isDead) return;

    const dx = caster.position.x - reviveTarget.position.x;
    const dz = caster.position.z - reviveTarget.position.z;
    if (Math.sqrt(dx * dx + dz * dz) > 10) {
      this.sendToPlayer(caster.characterId, {
        type: PacketType.SKILL_USE,
        timestamp: Date.now(),
        data: { skillName: '', error: 'too_far' }
      });
      return;
    }

    reviveTarget.isDead = false;
    reviveTarget.deathTime = 0;
    reviveTarget.stats.health = Math.floor(reviveTarget.stats.maxHealth * 0.5);
    reviveTarget.stats.mana = Math.floor(reviveTarget.stats.maxMana * 0.5);
    reviveTarget.invulnerableUntil = Date.now() + 3000;
    reviveTarget.activeCast = null;
    this.playerSys.recalcStats(reviveTarget);
    this.sendToPlayer(targetId, {
      type: PacketType.PLAYER_REVIVED,
      timestamp: Date.now(),
      data: { characterId: targetId, zoneId: reviveTarget.zoneId, position: reviveTarget.position, health: reviveTarget.stats.health, maxHealth: reviveTarget.stats.maxHealth, invulnerable: true, revivedBy: caster.characterName }
    });
    this.sendToPlayer(targetId, {
      type: PacketType.STATS_UPDATE,
      timestamp: Date.now(),
      data: { characterId: targetId, stats: reviveTarget.stats }
    });
    this.broadcastInZone(reviveTarget.zoneId, {
      type: PacketType.STATS_UPDATE,
      timestamp: Date.now(),
      data: { entityId: targetId, health: reviveTarget.stats.health, maxHealth: reviveTarget.stats.maxHealth }
    }, targetId);
    this.refreshPartyForMember(targetId);
  }

  applyPlayerDamage(target: PlayerSession, damage: number, attackerId: string, damageType: string, isCritical: boolean, zoneId: string, attackerPosition?: { x: number; y: number; z: number }): { redirected: boolean; damageTaken: number } {
    if (damage <= 0) return { redirected: false, damageTaken: 0 };

    this.cancelRest(target);

    if (target.statusEffects) {
      const invIdx = target.statusEffects.findIndex(e => e.type === StatusEffectType.INVISIBLE);
      if (invIdx !== -1) {
        target.statusEffects.splice(invIdx, 1);
        target.effectiveStats = null;
        this.sendToPlayer(target.characterId, {
          type: PacketType.STATUS_EFFECT_UPDATE,
          timestamp: Date.now(),
          data: { effects: target.statusEffects }
        });
        this.broadcastEntityEffects(target);
      }
    }

    if (!target.statusEffects || target.statusEffects.length === 0) {
      return this._applyRawDamage(target, damage, attackerId, damageType, isCritical, zoneId);
    }

    let negationIdx = -1;
    let protectedIdx = -1;
    let selfBlockIdx = -1;

    for (let i = 0; i < target.statusEffects.length; i++) {
      const e = target.statusEffects[i];
      if (negationIdx === -1 && e.type === StatusEffectType.BUFF_DAMAGE_NEGATION && e.buffData?.damageNegationThreshold) {
        negationIdx = i;
      } else if (protectedIdx === -1 && e.type === StatusEffectType.BUFF_BLOCKING_PROTECTED && e.buffData?.blockingProtectedBy) {
        protectedIdx = i;
      } else if (selfBlockIdx === -1 && e.type === StatusEffectType.BUFF_BLOCKING_STANCE && e.buffData?.blockingStance) {
        selfBlockIdx = i;
      }
    }

    if (negationIdx !== -1) {
      const negationEffect = target.statusEffects[negationIdx];
      if (damage <= (negationEffect.buffData!.damageNegationThreshold!)) {
        return { redirected: false, damageTaken: 0 };
      }
    }

    // Elemental absorption check
    for (let i = target.statusEffects.length - 1; i >= 0; i--) {
      const e = target.statusEffects[i];
      if (e.buffData?.elementalAbsorption) {
        const abs = e.buffData.elementalAbsorption;
        if (abs.elements.includes(damageType) || (damageType !== 'physical' && abs.elements.includes('all'))) {
          const amount = Math.floor(damage * 0.5);
          if (abs.convertTo === 'hp') {
            target.stats.health = Math.min(target.stats.maxHealth, target.stats.health + amount);
          } else {
            target.stats.mana = Math.min(target.stats.maxMana, target.stats.mana + amount);
          }
          return { redirected: false, damageTaken: 0 };
        }
      }
    }

    // Barrier check — consume one barrier matching damage type
    const barrierType = damageType === 'physical' ? StatusEffectType.BARRIER_PHYSICAL : StatusEffectType.BARRIER_MAGICAL;
    for (let i = 0; i < target.statusEffects.length; i++) {
      if (target.statusEffects[i].type === barrierType) {
        target.statusEffects.splice(i, 1);
        target.effectiveStats = null;
        this.sendToPlayer(target.characterId, {
          type: PacketType.STATUS_EFFECT_UPDATE,
          timestamp: Date.now(),
          data: { effects: target.statusEffects }
        });
        this.broadcastEntityEffects(target);
        return { redirected: false, damageTaken: 0 };
      }
    }

    // Mana Shield check — convert portion of damage to MP drain
    for (let i = 0; i < target.statusEffects.length; i++) {
      const e = target.statusEffects[i];
      if (e.type === StatusEffectType.BUFF_MANA_SHIELD && e.buffData?.manaShield) {
        const mpAvailable = target.stats.mana;
        if (mpAvailable > 0) {
          const mpDrain = Math.min(mpAvailable, damage);
          target.stats.mana -= mpDrain;
          damage = Math.max(0, damage - mpDrain);
          this.sendToPlayer(target.characterId, {
            type: PacketType.STATS_UPDATE,
            timestamp: Date.now(),
            data: { characterId: target.characterId, stats: target.stats }
          });
    if (damage <= 0) return { redirected: false, damageTaken: 0 };

    if (target.currentNpcId) return { redirected: false, damageTaken: 0 };
        }
        break;
      }
    }

    if (protectedIdx !== -1) {
      const protectedEffect = target.statusEffects[protectedIdx];
      const blockerId = protectedEffect.buffData!.blockingProtectedBy!;
      const blocker = this.state.players.get(blockerId);
      let blockStance = false;
      if (blocker && !blocker.isDead && blocker.statusEffects) {
        for (let i = 0; i < blocker.statusEffects.length; i++) {
          if (blocker.statusEffects[i].type === StatusEffectType.BUFF_BLOCKING_STANCE) {
            blockStance = true;
            break;
          }
        }
      }
      if (blocker && !blocker.isDead && blockStance) {
        const reducedDamage = Math.floor(damage * 0.4);
        blocker.stats.health = Math.max(0, blocker.stats.health - reducedDamage);
        this.sendToPlayer(blocker.characterId, {
          type: PacketType.DAMAGE,
          timestamp: Date.now(),
          data: { attackerId, targetId: blocker.characterId, damage: reducedDamage, isCritical: false, damageType, blockedFrom: target.characterId }
        });
        this.sendToPlayer(blocker.characterId, {
          type: PacketType.STATS_UPDATE,
          timestamp: Date.now(),
          data: { characterId: blocker.characterId, stats: blocker.stats, statBreakdown: blocker.statBreakdown, skillProficiencies: blocker.skillProficiencies, skillAdeptness: blocker.skillAdeptness }
        });
        this.broadcastInZone(zoneId, {
          type: PacketType.STATS_UPDATE,
          timestamp: Date.now(),
          data: { entityId: blocker.characterId, health: blocker.stats.health, maxHealth: blocker.stats.maxHealth }
        });
        if (blocker.stats.health <= 0) {
          this.handlePlayerDeath(blocker);
        } else {
          this.tryInterruptCast(blocker);
        }
        if (attackerId && this.spawnMgr.getEnemy(attackerId) && Math.random() < 0.5) {
          blocker.statusEffects.push({
            id: `block_kd_${Date.now()}`,
            type: StatusEffectType.KNOCKDOWN,
            sourceId: attackerId,
            targetId: blocker.characterId,
            potency: 0,
            appliedAt: Date.now(),
            duration: 2000,
            tickInterval: 0,
            lastTickAt: Date.now(),
            stacks: 1,
            skillName: 'Blocking',
            debuffCategory: 'knockdown',
          });
          this.sendToPlayer(blocker.characterId, {
            type: PacketType.STATUS_EFFECT_UPDATE,
            timestamp: Date.now(),
            data: { effects: blocker.statusEffects }
          });
          this.broadcastEntityEffects(blocker);
        }
        return { redirected: true, damageTaken: 0 };
      }
    }

    if (selfBlockIdx !== -1) {
      const reducedDamage = Math.floor(damage * 0.4);
      target.stats.health = Math.max(0, target.stats.health - reducedDamage);
      this.tryInterruptCast(target);
      return { redirected: false, damageTaken: reducedDamage };
    }

    return this._applyRawDamage(target, damage, attackerId, damageType, isCritical, zoneId);
  }

  private _applyRawDamage(target: PlayerSession, damage: number, attackerId: string, damageType: string, isCritical: boolean, zoneId: string): { redirected: boolean; damageTaken: number } {
    // Obelisk buff: flat % reduction to ALL damage taken (physical + magical),
    // applied to whatever reaches HP. Obelisk and Guardian are mutually
    // exclusive, so the guardian branch below never co-occurs with this.
    const obelisk = getObeliskBuffForWeapon(this.itemSys, target.equipment?.weapon);
    if (obelisk && obelisk.damageReduction > 0) {
      damage = Math.floor(damage * (1 - obelisk.damageReduction / 100));
      if (damage <= 0) return { redirected: false, damageTaken: 0 };
    }
    const guardian = this.findGuardian(target.characterId);
    if (guardian && !guardian.isDead) {
      guardian.stats.health = Math.max(0, guardian.stats.health - damage);
      this.sendToPlayer(guardian.characterId, {
        type: PacketType.DAMAGE,
        timestamp: Date.now(),
        data: { attackerId, targetId: guardian.characterId, damage, isCritical, damageType, redirectedFrom: target.characterId }
      });
      this.sendToPlayer(guardian.characterId, {
        type: PacketType.STATS_UPDATE,
        timestamp: Date.now(),
        data: { characterId: guardian.characterId, stats: guardian.stats, statBreakdown: guardian.statBreakdown, skillProficiencies: guardian.skillProficiencies, skillAdeptness: guardian.skillAdeptness }
      });
      this.broadcastInZone(zoneId, {
        type: PacketType.STATS_UPDATE,
        timestamp: Date.now(),
        data: { entityId: guardian.characterId, health: guardian.stats.health, maxHealth: guardian.stats.maxHealth }
      });
      if (guardian.stats.health <= 0) {
        this.handlePlayerDeath(guardian);
      } else {
        this.tryInterruptCast(guardian);
      }
      return { redirected: true, damageTaken: 0 };
    } else {
      target.stats.health = Math.max(0, target.stats.health - damage);
      this.tryInterruptCast(target);
      return { redirected: false, damageTaken: damage };
    }
  }

  private applyRemoveResistBuffs(target: { statusEffects: StatusEffect[] }, appliedEffect: StatusEffect): void {
    if (!appliedEffect.removeResistBuffs || appliedEffect.removeResistBuffs.length === 0) return;
    const toRemove = appliedEffect.removeResistBuffs;
    for (let i = target.statusEffects.length - 1; i >= 0; i--) {
      const e = target.statusEffects[i];
      if (e.buffData?.resistMods) {
        const hasMatching = Object.keys(e.buffData.resistMods).some(key => toRemove.includes(key));
        if (hasMatching) {
          target.statusEffects.splice(i, 1);
        }
      }
    }
  }

  private applySkillKnockback(target: { position: { x: number; y: number; z: number }; statusEffects: StatusEffect[]; currentNpcId?: string | null }, attackerPos: { x: number; z: number }, distance: number): void {
    if (distance <= 0) return;
    if (target.statusEffects.some(e => e.type === StatusEffectType.STUN || e.type === StatusEffectType.FREEZE)) return;
    if (target.currentNpcId) return;
    const dx = target.position.x - attackerPos.x;
    const dz = target.position.z - attackerPos.z;
    const len = Math.sqrt(dx * dx + dz * dz);
    if (len < 0.01) return;
    target.statusEffects.push({
      id: `kb_${Date.now()}_${Math.random()}`,
      type: StatusEffectType.BUFF_GENERIC,
      sourceId: '',
      targetId: '',
      potency: 0,
      appliedAt: Date.now(),
      duration: 500,
      tickInterval: 0,
      lastTickAt: 0,
      stacks: 0,
      skillName: 'knockback',
      debuffCategory: 'knockback',
      knockbackVelocity: { dx: dx / len, dz: dz / len, remaining: distance },
    });
  }

  private tryInterruptCast(target: PlayerSession): void {
    if (!target.activeCast) return;
    const baseStats = target.baseStats || { STA: 0, STR: 0, AGI: 0, DEX: 0, SPI: 0, INT: 0 };
    const gearSpi = target.statBreakdown?.gear?.SPI || 0;
    const buffSpi = target.statBreakdown?.buffs?.SPI || 0;
    const totalSPI = (target.statPoints.SPI || 0) + baseStats.SPI + gearSpi + buffSpi;
    const interruptChance = Math.max(0.05, 0.5 - totalSPI * 0.002);
    if (Math.random() < interruptChance) {
      const skillName = target.activeCast.skillName;
      target.activeCast = null;
      this.sendToPlayer(target.characterId, {
        type: PacketType.COOLDOWN_UPDATE,
        timestamp: Date.now(),
        data: { skillName, type: 'cast_cancel' }
      });
    }
  }

  damageEnemy(enemy: EnemyInstance, damage: number, attackerId?: string): { died: boolean; actualDamage: number } {
    enemy.health = Math.max(0, enemy.health - damage);
    const actualDamage = damage;
    if (enemy.invulnerable) {
      enemy.health = enemy.maxHealth;
      return { died: false, actualDamage };
    }
    if (attackerId) {
      const def = getEnemyDefinition(enemy.enemyType);
      if (!def || def.aggroRange > 0) {
        this.enmity.addDamageEnmity(enemy, attackerId, damage);
      }
    }
    return { died: enemy.health <= 0, actualDamage };
  }

  getEnemyEffectiveDefense(enemy: EnemyInstance): number {
    let defense = enemy.level * 0.5;
    const def = getEnemyDefinition(enemy.enemyType);
    if (def) defense = def.defense || 0;
    for (const effect of enemy.statusEffects) {
      if (effect.type === StatusEffectType.DEBUFF_DEFENSE_DOWN) {
        defense = Math.floor(defense * (1 - (effect.potency || 0)));
      }
    }
    return defense;
  }

  sendDamageDebug(session: PlayerSession, result: { debugCalc?: string }): void {
    if (result.debugCalc) {
      this.sendToPlayer(session.characterId, {
        type: PacketType.CHAT_MESSAGE,
        timestamp: Date.now(),
        data: { sender: 'Damage', message: result.debugCalc, channel: 'system' }
      });
    }
  }

  getTargetStatsForEntity(id: string): {
    defense: number;
    magicDefense: number;
    health: number;
    level: number;
    dodge: number;
    damageTakenMultiplier?: number;
    physicalDamageReduction?: number;
    fireResist?: number;
    iceResist?: number;
    lightningResist?: number;
    darkResist?: number;
    holyResist?: number;
    poisonResist?: number;
  } | null {
    const enemy = this.spawnMgr.getEnemy(id);
    if (enemy) {
      const def = getEnemyDefinition(enemy.enemyType);
      return {
        defense: this.getEnemyEffectiveDefense(enemy),
        magicDefense: Math.floor((def?.defense || 0) * 0.3),
        health: enemy.health,
        level: enemy.level,
        dodge: Math.floor(enemy.level * 0.5),
        fireResist: def?.fireResist || 0,
        iceResist: def?.iceResist || 0,
        lightningResist: def?.lightningResist || 0,
        darkResist: def?.darkResist || 0,
        holyResist: def?.holyResist || 0,
        poisonResist: def?.poisonResist || 0,
      };
    }
    const player = this.state.players.get(id);
    if (player) {
      const eff = getEffectiveStats(player.stats, player.statPoints, player.statusEffects || []);
      return {
        defense: eff.defense,
        magicDefense: Math.floor(eff.defense * 0.3),
        health: player.stats.health,
        level: player.stats.level,
        dodge: calculateDodge(player.stats.level, (player.statPoints.AGI || 0) + ((player.baseStats || { AGI: 0 }).AGI || 0), eff.dodgeBonus),
        damageTakenMultiplier: eff.damageTakenMultiplier,
        physicalDamageReduction: eff.physicalDamageReduction,
        fireResist: player.statBreakdown?.gearCombat?.fireResist || 0,
        iceResist: player.statBreakdown?.gearCombat?.iceResist || 0,
        lightningResist: player.statBreakdown?.gearCombat?.lightningResist || 0,
        darkResist: player.statBreakdown?.gearCombat?.darkResist || 0,
        holyResist: player.statBreakdown?.gearCombat?.holyResist || 0,
        poisonResist: player.statBreakdown?.gearCombat?.poisonResist || 0,
      };
    }
    return null;
  }

  findClosestEntityToPosition(session: PlayerSession, pos: { x: number; y: number; z: number }, radius: number): { id: string; distance: number } | null {
    let closest: { id: string; distance: number } | null = null;

    const nearEnemies = this.queryEnemiesNear(pos.x, pos.z, radius, session.zoneId);
    for (const entry of nearEnemies) {
      const dx = entry.x - pos.x;
      const dz = entry.z - pos.z;
      const dist = Math.sqrt(dx * dx + dz * dz);
      if (dist <= radius && (!closest || dist < closest.distance)) {
        closest = { id: entry.id, distance: dist };
      }
    }

    const nearPlayers = this.queryPlayersNear(pos.x, pos.z, radius, session.zoneId);
    for (const entry of nearPlayers) {
      if (entry.id === session.characterId) continue;
      const dx = entry.x - pos.x;
      const dz = entry.z - pos.z;
      const dist = Math.sqrt(dx * dx + dz * dz);
      if (dist <= radius && (!closest || dist < closest.distance)) {
        closest = { id: entry.id, distance: dist };
      }
    }

    return closest;
  }

  findAllEntitiesInRadius(session: PlayerSession, pos: { x: number; y: number; z: number }, radius: number): Array<{ id: string; distance: number }> {
    const results: Array<{ id: string; distance: number }> = [];

    const nearEnemies = this.queryEnemiesNear(pos.x, pos.z, radius, session.zoneId);
    for (const entry of nearEnemies) {
      const dx = entry.x - pos.x;
      const dz = entry.z - pos.z;
      const dist = Math.sqrt(dx * dx + dz * dz);
      if (dist <= radius) {
        results.push({ id: entry.id, distance: dist });
      }
    }

    const nearPlayers = this.queryPlayersNear(pos.x, pos.z, radius, session.zoneId);
    for (const entry of nearPlayers) {
      if (entry.id === session.characterId) continue;
      const dx = entry.x - pos.x;
      const dz = entry.z - pos.z;
      const dist = Math.sqrt(dx * dx + dz * dz);
      if (dist <= radius) {
        results.push({ id: entry.id, distance: dist });
      }
    }

    return results;
  }

  consumeDebuffsOnHit(targetSession: PlayerSession): void {
    const idx = targetSession.statusEffects.findIndex(e => e.consumable);
    if (idx !== -1) {
      targetSession.statusEffects.splice(idx, 1);
      this.playerSys.recalcStats(targetSession);
      this.sendToPlayer(targetSession.characterId, {
        type: PacketType.STATUS_EFFECT_UPDATE,
        timestamp: Date.now(),
        data: { effects: targetSession.statusEffects }
      });
      this.sendToPlayer(targetSession.characterId, {
        type: PacketType.STATS_UPDATE,
        timestamp: Date.now(),
        data: { characterId: targetSession.characterId, stats: targetSession.stats }
      });
      this.broadcastEntityEffects(targetSession);
    }
  }

  shouldApplyDebuff(effect: StatusEffect, targetId: string, casterId?: string): boolean {
    if (!effect.debuffCategory) return true;
    const casterSession = casterId ? this.state.players.get(casterId) : null;
    let accuracy = 65;
    if (casterSession) {
      const baseStats = casterSession.baseStats || { STA: 0, STR: 0, AGI: 0, DEX: 0, SPI: 0, INT: 0 };
      const totalSPI = (casterSession.statPoints.SPI || 0) + baseStats.SPI;
      const subCategory = effect.skillName ? this.skillSys.getSubCategoryForSkill(effect.skillName) : null;
      const prof = subCategory ? (casterSession.skillAdeptness[subCategory] || 0) : 0;
      accuracy = computeDebuffAccuracy(totalSPI, prof, effect.debuffCategory);
    }
    const resistPercent = this.getDebuffResist(targetId, effect.debuffCategory);
    const { applied, roll } = rollDebuffApplication(accuracy, resistPercent);
    if (casterId && process.env.DEBUG_DEBUFF_ROLLS === '1') {
      this.sendToPlayer(casterId, {
        type: PacketType.CHAT_MESSAGE,
        timestamp: Date.now(),
        data: { sender: 'Debug', message: `Debuff: ${accuracy.toFixed(0)}% acc - ${resistPercent.toFixed(0)}% ${effect.debuffCategory} resist = ${Math.max(0, accuracy - resistPercent).toFixed(0)}% final (roll ${roll.toFixed(0)}) → ${applied ? 'applied' : 'resisted'}`, channel: 'system' }
      });
    }
    return applied;
  }

  getDebuffResist(targetId: string, category: string): number {
    const player = this.state.players.get(targetId);
    if (player) {
      if (!player.resistCache) player.resistCache = new Map();
      const cached = player.resistCache.get(category);
      if (cached !== undefined) return cached;

      const baseStats = player.baseStats || { STA: 0, STR: 0, AGI: 0, DEX: 0, SPI: 0, INT: 0 };
      const totalSTA = (player.statPoints.STA || 0) + baseStats.STA;
      const totalSPI = (player.statPoints.SPI || 0) + baseStats.SPI;
      const gc = player.statBreakdown?.gearCombat;
      let result = 0;
      if (STA_DEBUFF_CATEGORIES.has(category)) {
        const gearKey = `${category}Resist` as keyof typeof gc;
        const gearBonus = (gc as any)?.[gearKey] || 0;
        result = computeAilmentResist(totalSTA, gearBonus);
      } else if (SPI_DEBUFF_CATEGORIES.has(category)) {
        const gearKey = `${category}Resist` as keyof typeof gc;
        const gearBonus = (gc as any)?.[gearKey] || 0;
        result = computeDisorderResist(totalSPI, gearBonus);
      }
      player.resistCache.set(category, result);
      return result;
    }
    const enemy = this.spawnMgr.getEnemy(targetId);
    if (enemy) {
      return category === 'ailment' ? (enemy as any).ailmentResist || 0 : (enemy as any).disorderResist || 0;
    }
    return 0;
  }

  hasActiveDebuff(targetId: string, effectType: StatusEffectType, skillName?: string): boolean {
    const player = this.state.players.get(targetId);
    if (player) {
      return player.statusEffects.some(e => e.type === effectType && (!skillName || e.skillName === skillName) && e.duration > 0);
    }
    const enemy = this.spawnMgr.getEnemy(targetId);
    if (enemy) {
      return enemy.statusEffects.some(e => e.type === effectType && (!skillName || e.skillName === skillName) && e.duration > 0);
    }
    return false;
  }

  processOnHitProcs(session: PlayerSession, targetId: string, damageDealt: number, isPhysical: boolean): void {
    if (!isPhysical || damageDealt <= 0) return;

    const { procs, enhancementLevel, enhancementElement } = collectProcs(session, this.itemSys);

    for (const proc of procs) {
      if (proc.minLevel && enhancementLevel < proc.minLevel) continue;

      let chance = proc.baseChance + (proc.chancePerLevel || 0) * enhancementLevel;
      if (chance <= 0) continue;

      const resistCategory = getProcResistCategory(proc);
      if (resistCategory) {
        const resistPercent = this.getDebuffResist(targetId, resistCategory);
        chance *= (1 - resistPercent / 100);
      }

      if (Math.random() >= chance) continue;

      this.applyProcEffect(proc, session, targetId, damageDealt);
    }

    if (enhancementElement === 'dark') {
      const recoilMultiplier = getDarkRecoilPercent(enhancementLevel);
      const recoilDamage = Math.floor(damageDealt * recoilMultiplier);
      if (recoilDamage > 0) {
        session.stats.health = Math.max(0, session.stats.health - recoilDamage);
        this.sendToPlayer(session.characterId, {
          type: PacketType.STATS_UPDATE,
          timestamp: Date.now(),
          data: { characterId: session.characterId, stats: session.stats, statBreakdown: session.statBreakdown }
        });
        if (session.stats.health <= 0) {
          this.handlePlayerDeath(session);
        }
      }
    }
  }

  private applyProcEffect(proc: OnHitProc, session: PlayerSession, targetId: string, damageDealt: number): void {
    if (isDrainLifeProc(proc)) {
      const healAmount = Math.floor(damageDealt * (proc.potency || 0));
      if (healAmount > 0) {
        session.stats.health = Math.min(session.stats.maxHealth, session.stats.health + healAmount);
        this.sendToPlayer(session.characterId, {
          type: PacketType.STATS_UPDATE,
          timestamp: Date.now(),
          data: { characterId: session.characterId, stats: session.stats, statBreakdown: session.statBreakdown }
        });
      }
      return;
    }

    const effect = buildProcStatusEffect(proc, session.characterId, targetId);
    if (!effect) return;

    if (this.hasActiveDebuff(targetId, effect.type, effect.skillName)) return;

    const enemy = this.spawnMgr.getEnemy(targetId);
    if (enemy) {
      enemy.statusEffects.push(effect);
      this.enmity.addDebuffEnmity(enemy, session.characterId, effect.potency, true);
      this.broadcastInZone(session.zoneId, {
        type: PacketType.ENTITY_STATUS_EFFECTS,
        timestamp: Date.now(),
        data: { entityId: targetId, effects: enemy.statusEffects }
      });
      return;
    }

    const player = this.state.players.get(targetId);
    if (player) {
      player.statusEffects.push(effect);
      this.sendToPlayer(targetId, {
        type: PacketType.STATUS_EFFECT_UPDATE,
        timestamp: Date.now(),
        data: { effects: player.statusEffects }
      });
      this.broadcastEntityEffects(player);
    }
  }

  processGloomRecoil(session: PlayerSession): void {
    const darkAuras = session.statusEffects?.filter(
      e => e.type === StatusEffectType.WEAPON_AURA && e.buffData?.weaponAura?.element === 'dark'
    ) || [];

    if (darkAuras.length === 0) return;

    const darknessAdeptness = session.skillAdeptness?.['Darkness'] || 0;
    const recoilRate = getGloomRecoilRate(darknessAdeptness);

    const effective = getEffectiveStats(session.stats, session.statPoints, session.statusEffects || []);
    const auraMult = effective.auraDamageMultiplier || 1;

    let totalRecoil = 0;
    for (const aura of darkAuras) {
      const { minDamage, maxDamage } = aura.buffData!.weaponAura!;
      const avgDamage = ((minDamage + maxDamage) / 2) * auraMult;
      totalRecoil += Math.floor(avgDamage * recoilRate);
    }

    if (totalRecoil > 0) {
      session.stats.health = Math.max(0, session.stats.health - totalRecoil);
      this.sendToPlayer(session.characterId, {
        type: PacketType.STATS_UPDATE,
        timestamp: Date.now(),
        data: { characterId: session.characterId, stats: session.stats, statBreakdown: session.statBreakdown }
      });
      if (session.stats.health <= 0) {
        this.handlePlayerDeath(session);
      }
    }
  }

  private findGuardian(targetId: string): PlayerSession | null {
    // Obelisk buff is mutually exclusive with Guardian: an Obelisk weapon
    // wielder cannot be protected by Guardian, so never redirect their damage.
    const target = this.state.players.get(targetId);
    if (target && getObeliskBuffForWeapon(this.itemSys, target.equipment?.weapon)) {
      return null;
    }
    for (const [, session] of this.state.players) {
      const guardianEffect = session.statusEffects?.find(
        e => e.type === StatusEffectType.BUFF_DAMAGE_REDIRECT && e.buffData?.damageRedirectTargetId === targetId
      );
      if (guardianEffect) return session;
    }
    return null;
  }

  /**
   * Breaks any Guardian link involving `characterId`, in both directions, and
   * syncs every affected player. Called when a party link that justifies
   * Guardian is severed (party leave/kick/disconnect). This deliberately does
   * NOT consult findGuardian's Obelisk gate — cleanup must remove lingering
   * protector-side redirects regardless of the target's weapon.
   */
  breakGuardianLinksFor(characterId: string): void {
    const session = this.state.players.get(characterId);
    if (!session || !session.statusEffects) return;

    // Direction 1: this character is the PROTECTOR. Strip own redirect and the
    // protected target's BUFF_GUARDED marker.
    const redirectFx = session.statusEffects.find(
      e => e.type === StatusEffectType.BUFF_DAMAGE_REDIRECT && e.buffData?.damageRedirectTargetId,
    );
    if (redirectFx) {
      const guardedId = redirectFx.buffData!.damageRedirectTargetId!;
      session.statusEffects = session.statusEffects.filter(e => e !== redirectFx);
      this.playerSys.recalcStats(session);
      this.syncGuardianRemoval(characterId);
      const guarded = this.state.players.get(guardedId);
      if (guarded) {
        guarded.statusEffects = guarded.statusEffects.filter(e => e.type !== StatusEffectType.BUFF_GUARDED);
        this.syncGuardianRemoval(guardedId);
      }
    }

    // Direction 2: this character is PROTECTED. Strip own BUFF_GUARDED and the
    // protector's BUFF_DAMAGE_REDIRECT that targets them.
    const guardedFx = session.statusEffects.find(e => e.type === StatusEffectType.BUFF_GUARDED);
    if (guardedFx) {
      session.statusEffects = session.statusEffects.filter(e => e !== guardedFx);
      this.syncGuardianRemoval(characterId);
      for (const [, protector] of this.state.players) {
        const fx = protector.statusEffects?.find(
          e => e.type === StatusEffectType.BUFF_DAMAGE_REDIRECT && e.buffData?.damageRedirectTargetId === characterId,
        );
        if (fx) {
          protector.statusEffects = protector.statusEffects!.filter(e => e !== fx);
          this.playerSys.recalcStats(protector);
          this.syncGuardianRemoval(protector.characterId);
          break;
        }
      }
    }
  }

  /** Recalc + status/stat/entity-effects sync for a player who lost a Guardian buff. */
  private syncGuardianRemoval(characterId: string): void {
    const s = this.state.players.get(characterId);
    if (!s) return;
    this.sendToPlayer(characterId, {
      type: PacketType.STATUS_EFFECT_UPDATE,
      timestamp: Date.now(),
      data: { effects: s.statusEffects },
    });
    this.sendToPlayer(characterId, {
      type: PacketType.STATS_UPDATE,
      timestamp: Date.now(),
      data: { characterId, stats: s.stats, statBreakdown: s.statBreakdown, skillProficiencies: s.skillProficiencies, skillAdeptness: s.skillAdeptness },
    });
    this.broadcastEntityEffects(s);
  }

  private setupCallbacks(): void {
    this.combat.onDeath((targetId, killerId) => {
      const enemy = this.spawnMgr.getEnemy(targetId);
      if (!enemy) return;

      const enemyDef = getEnemyDefinition(enemy.enemyType);
      if (!enemyDef) return;

      const killer = this.findPlayerByCharacterId(killerId);
      if (killer) {
        this.playerSys.grantExperience(killer, enemyDef.experience);
        this.sendToPlayer(killer.characterId, {
          type: PacketType.EXPERIENCE_GAIN,
          timestamp: Date.now(),
          data: { experience: enemyDef.experience, totalExperience: killer.stats.experience, level: killer.stats.level }
        });
        this.sendToPlayer(killer.characterId, {
          type: PacketType.STATS_UPDATE,
          timestamp: Date.now(),
          data: { characterId: killer.characterId, stats: killer.stats }
        });

        this.grantQuestKillCredit(killer, enemy.enemyType, killer.zoneId);

        this.handleEnemyLoot(killer, enemy.enemyType, enemy.position);
      }

      enemy.state = 'dead';
      enemy.deathTime = Date.now();

      this.broadcastInZone(
        this.findZoneOfEntity(targetId),
        {
          type: PacketType.DEATH,
          timestamp: Date.now(),
          data: { entityId: targetId, killerId }
        }
      );

      this.broadcastInZone(
        this.findZoneOfEntity(targetId),
        {
          type: PacketType.ENTITY_DESPAWN,
          timestamp: Date.now(),
          data: { entityId: targetId }
        }
      );
    });

    this.ai.onEnemyAttack((enemyId, targetId, _rawDamage) => {
      const target = this.findPlayerByCharacterId(targetId);
      if (!target) return;

      if (target.invulnerableUntil > Date.now()) return;

      const enemy = this.spawnMgr.getEnemy(enemyId);
      if (!enemy || enemy.state === 'dead') return;

      const result = this.combat.processEnemyAttack(enemy, target);
      if (!result) return;

      if (result.missed) {
        this.broadcastInZone(target.zoneId, {
          type: PacketType.DAMAGE,
          timestamp: Date.now(),
          data: { attackerId: enemyId, targetId, damage: 0, isCritical: false, damageType: 'physical', missed: true }
        });
      } else {
        const dmgResult = this.applyPlayerDamage(target, result.damage, enemyId, 'physical', result.isCritical || false, target.zoneId, enemy.position);

        if (!dmgResult.redirected) {
          this.sendToPlayer(targetId, {
            type: PacketType.DAMAGE,
            timestamp: Date.now(),
            data: { attackerId: enemyId, targetId, damage: dmgResult.damageTaken, isCritical: result.isCritical, damageType: 'physical' }
          });

          this.sendToPlayer(targetId, {
            type: PacketType.STATS_UPDATE,
            timestamp: Date.now(),
            data: { characterId: targetId, stats: target.stats, statBreakdown: target.statBreakdown, skillProficiencies: target.skillProficiencies, skillAdeptness: target.skillAdeptness }
          });

          this.broadcastInZone(target.zoneId, {
            type: PacketType.DAMAGE,
            timestamp: Date.now(),
            data: { attackerId: enemyId, targetId, damage: dmgResult.damageTaken, isCritical: result.isCritical, damageType: 'physical' }
          }, targetId);

          this.broadcastInZone(target.zoneId, {
          type: PacketType.STATS_UPDATE,
          timestamp: Date.now(),
          data: { entityId: targetId, health: target.stats.health, maxHealth: target.stats.maxHealth }
        });

        this.refreshPartyForMember(targetId);

        if (target.stats.health <= 0) {
          this.handlePlayerDeath(target);
        }
      } else {
        this.broadcastInZone(target.zoneId, {
          type: PacketType.DAMAGE,
          timestamp: Date.now(),
          data: { attackerId: enemyId, targetId, damage: 0, isCritical: false, damageType: 'physical' }
        });
      }
      }
    });

    this.ai.onEnemyAttackSummon((enemyId, summonId, damage) => {
      const summon = this.summonMgr.getSummon(summonId);
      if (!summon) return;

      const enemy = this.spawnMgr.getEnemy(enemyId);
      if (!enemy || enemy.state === 'dead') return;

      const actualDamage = Math.max(1, damage - Math.floor(summon.defense * 0.5));
      const dead = this.summonMgr.damageSummon(summonId, actualDamage);

      this.broadcastInZone(summon.zoneId, {
        type: PacketType.DAMAGE,
        timestamp: Date.now(),
        data: { attackerId: enemyId, targetId: summonId, damage: actualDamage, isCritical: false, damageType: 'physical' },
      });

      if (dead) {
        this.summonMgr.despawnSummon(summonId);
        this.broadcastInZone(summon.zoneId, {
          type: PacketType.ENTITY_DESPAWN,
          timestamp: Date.now(),
          data: { entityId: summonId },
        });
      }
    });

    this.ai.onEnemyRespawn((enemyId) => {
      const enemy = this.spawnMgr.getEnemy(enemyId);
      if (!enemy) return;
      const zoneId = this.findZoneOfEnemy(enemyId);
      if (!zoneId) return;
      const def = getEnemyDefinition(enemy.enemyType);

      this.broadcastInZone(zoneId, {
        type: PacketType.ENTITY_SPAWN,
        timestamp: Date.now(),
        data: {
          id: enemy.id,
          type: 'enemy',
          position: enemy.position,
          rotation: { x: 0, y: enemy.rotation, z: 0, w: 1 },
          data: {
            enemyType: enemy.enemyType,
            name: def?.name || enemy.enemyType,
            health: enemy.health,
            maxHealth: enemy.maxHealth,
            level: enemy.level,
            state: enemy.state,
            modelFile: def?.modelFile || 'Enemy Small.glb'
          }
        }
      });
    });

    this.ai.onEnemyAggro((enemyId, enemyType, targetId, enemyPos, spawnPos) => {
    });
  }

  private setupPlayerCallbacks(): void {
    this.playerSys.onLevelUp((characterId: string, newLevel: number) => {
      const session = this.findPlayerByCharacterId(characterId);
      if (!session) return;

      this.sendToPlayer(characterId, {
        type: PacketType.LEVEL_UP,
        timestamp: Date.now(),
        data: {
          level: newLevel,
          statPoints: session.statPoints,
          unspentStatPoints: session.unspentStatPoints,
          unspentSkillPoints: session.unspentSkillPoints,
          stats: session.stats
        }
      });

      this.broadcastInZone(session.zoneId, {
        type: PacketType.STATS_UPDATE,
        timestamp: Date.now(),
        data: { entityId: characterId, health: session.stats.health, maxHealth: session.stats.maxHealth, level: newLevel }
      });
      this.refreshPartyForMember(characterId);
    });
  }

  private setupEventHandlers(): void {
    this.io.on('connection', (socket: Socket) => {
      console.log(`Client connected: ${socket.id}`);

      socket.on('packet', (packet: Packet) => {
        this.handlePacket(socket, packet);
      });

      socket.on('disconnect', () => {
        console.log(`Client disconnected: ${socket.id}`);
        this.handleDisconnect(socket);
      });

      socket.on('error', (error: Error) => {
        console.error(`Socket error for ${socket.id}:`, error);
      });
    });
  }

  private async handlePacket(socket: Socket, packet: Packet): Promise<void> {
    try {
      if (packet.type === PacketType.HEARTBEAT) {
        this.sendToSocket(socket.id, { type: PacketType.HEARTBEAT, timestamp: Date.now(), data: {} });
        return;
      }

      if (packet.type === PacketType.PLAYER_MOVE) {
        const cid = this.findCharacterBySocket(socket.id);
        const sess = cid ? this.state.players.get(cid) : null;
        if (sess?.isDead) return;
      }

      const handler = this.handlers.get(packet.type);
      if (handler) {
        await handler(this, socket, packet.data);
      }
    } catch (error) {
      console.error(`Error handling packet ${packet.type}:`, error);
    }
  }

  private handleDisconnect(socket: Socket): void {
    const characterId = this.findCharacterBySocket(socket.id);
    if (characterId) {
      const session = this.state.players.get(characterId);
      if (session) {
        this.auth.saveCharacter(characterId, {
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
        }).catch(err => console.error('Failed to save character on disconnect:', err));

        this.aoeZoneMgr.cleanupOwner(characterId);

        const despawnedSummons = this.summonMgr.despawnAllForOwner(characterId);
        for (const summonId of despawnedSummons) {
          this.broadcastInZone(session.zoneId, {
            type: PacketType.ENTITY_DESPAWN,
            timestamp: Date.now(),
            data: { entityId: summonId },
          });
        }

        this.removeSongProximityBuffs(session);

        this.dummyMgr.cleanupOwner(characterId, session.zoneId);

        this.broadcastInZone(session.zoneId, {
          type: PacketType.ENTITY_DESPAWN,
          timestamp: Date.now(),
          data: { entityId: characterId }
        });

        const result = this.partySys.handleDisconnect(characterId);
        // Break any Guardian link involving the disconnecting player (cleans up
        // the partner still online). Must run while the disconnecting session
        // is still present in state.players.
        this.breakGuardianLinksFor(characterId);
        if (result && result.party.members.length > 0) {
          this.sendPartyUpdate(result.party.partyId);
          for (const m of result.party.members) {
            this.sendToPlayer(m.characterId, {
              type: PacketType.CHAT_MESSAGE,
              timestamp: Date.now(),
              data: {
                sender: 'Party',
                message: `${session.characterName} has disconnected.`,
                channel: 'party'
              }
            });
          }
        }

        this.tradeSys.handleDisconnect(characterId);
      }
      this.state.players.delete(characterId);
      this.state.playerToSocket.delete(characterId);
      this.unregisterPlayerFromZone(characterId);
      this.clearMovementThrottle(characterId);
      void this.presence.markOffline(characterId);
    }
    this.state.socketToPlayer.delete(socket.id);
  }

  sendZoneState(socket: Socket, zoneId: string, includePlayerId?: string): void {
    const zoneDef = getZoneDefinition(zoneId);
    if (!zoneDef) return;

    const enemies = this.spawnMgr.getEnemiesInZone(zoneId);
    const enemyData: any[] = [];
    enemies.forEach(enemy => {
      if (enemy.state !== 'dead') {
        const def = getEnemyDefinition(enemy.enemyType);
        enemyData.push({
          id: enemy.id,
          type: 'enemy',
          position: enemy.position,
          rotation: { x: 0, y: enemy.rotation, z: 0, w: 1 },
          data: {
            enemyType: enemy.enemyType,
            name: def?.name || enemy.enemyType,
            health: enemy.health,
            maxHealth: enemy.maxHealth,
            level: enemy.level,
            state: enemy.state,
            modelFile: def?.modelFile || 'Enemy Small.glb'
          }
        });
      }
    });

    const npcs = getNPCsInZone(zoneId);
    const npcData = npcs.map(npc => ({
      id: npc.id,
      type: 'npc',
      position: npc.position,
      rotation: { x: 0, y: npc.rotation, z: 0, w: 1 },
      data: {
        name: npc.name,
        npcType: npc.type,
        modelFile: npc.modelFile
      }
    }));

    const otherPlayers: any[] = [];
    this.state.players.forEach(player => {
      if (player.zoneId !== zoneId) return;
      if (player.characterId === this.findCharacterBySocket(socket.id) && player.characterId !== includePlayerId) return;
      otherPlayers.push({
        id: player.characterId,
        type: 'player',
        position: player.position,
        rotation: player.rotation,
        data: { name: player.characterName, class: player.jobId, race: player.race, jobId: player.jobId, level: player.stats.level, health: player.stats.health, maxHealth: player.stats.maxHealth, modelFile: JOB_DEFINITIONS[player.jobId]?.modelFile, invisible: player.statusEffects?.some(e => e.type === StatusEffectType.INVISIBLE) || false, isResting: player.isResting, role: player.role }
      });
    });

    const summons = this.summonMgr.getSummonsInZone(zoneId);
    const summonData = summons.map(s => ({
      id: s.id,
      type: 'summon',
      position: s.position,
      rotation: { x: 0, y: s.rotation, z: 0, w: 1 },
      data: {
        summonType: s.summonType,
        ownerId: s.ownerId,
        ownerName: s.ownerName,
        health: s.health,
        maxHealth: s.maxHealth,
        defense: s.defense,
        element: s.element,
        duration: s.duration,
      },
    }));

    this.sendToSocket(socket.id, {
      type: PacketType.WORLD_STATE,
      timestamp: Date.now(),
      data: {
        zoneId,
        zoneDef,
        enemies: enemyData,
        npcs: npcData,
        players: otherPlayers,
        summons: summonData,
      }
    });
  }

  removeBlockingProtectedBuffs(blockerId: string): void {
    this.blockingMgr.removeProtectedBuffs(blockerId);
  }

  removeSongProximityBuffs(caster: PlayerSession): void {
    for (const [targetId, target] of this.state.players) {
      if (target.zoneId !== caster.zoneId) continue;
      if (!target.statusEffects?.length) continue;

      const toRemove = target.statusEffects.filter(e =>
        e.songProximityBuff && e.sourceId === caster.characterId
      );
      if (toRemove.length === 0) continue;

      for (const e of toRemove) {
        e.lastInRangeAt = Date.now();
        e.appliedAt = Date.now();
        e.duration = 5000;
      }
      target.effectiveStats = null;

      if (targetId !== caster.characterId) {
        this.sendToPlayer(targetId, {
          type: PacketType.STATUS_EFFECT_UPDATE,
          timestamp: Date.now(),
          data: { effects: target.statusEffects }
        });
        this.sendToPlayer(targetId, {
          type: PacketType.STATS_UPDATE,
          timestamp: Date.now(),
          data: { characterId: targetId, stats: target.stats, statBreakdown: target.statBreakdown, skillProficiencies: target.skillProficiencies, skillAdeptness: target.skillAdeptness }
        });
        this.broadcastEntityEffects(target);
      }
    }
  }

  executeAOESkillInternal(session: PlayerSession, skillName: string, aoePosition: { x: number; y: number; z: number }): void {
    const characterId = session.characterId;
    const skill = this.skillSys.findSkillDefinition(skillName);
    const aoeRadius = skill?.aoeRadius || DEFAULT_AOE_RADIUS;

    const firstTarget = this.findClosestEntityToPosition(session, aoePosition, aoeRadius);
    const firstTargetId = firstTarget?.id || null;

    const result = this.skillSys.executeSkill(session, skillName, firstTargetId, (id) => this.getTargetStatsForEntity(id));
    this.sendDamageDebug(session, result);
    this.playerSys.recalcStats(session);

    this.sendToPlayer(characterId, {
      type: PacketType.STATS_UPDATE,
      timestamp: Date.now(),
      data: { characterId, stats: session.stats, statBreakdown: session.statBreakdown, skillProficiencies: session.skillProficiencies, skillAdeptness: session.skillAdeptness }
    });

    if (this.skillSys.lastProficiencyGain) {
      const pg = this.skillSys.lastProficiencyGain;
      this.sendToPlayer(characterId, {
        type: PacketType.CHAT_MESSAGE,
        timestamp: Date.now(),
        data: { sender: 'Proficiency', message: `${pg.subCategory} +${pg.amount} (${Math.floor(pg.newAdeptness)}/${pg.cap})`, channel: 'system' }
      });
      this.skillSys.lastProficiencyGain = undefined;
    }

    this.sendToPlayer(characterId, {
      type: PacketType.COOLDOWN_UPDATE,
      timestamp: Date.now(),
      data: {
        skillName,
        type: 'used',
        mpCost: skill?.mpCost || 0,
        cooldownRemaining: session.skillCooldowns.find(c => c.skillName === skillName)?.readyAt
          ? Math.max(0, (session.skillCooldowns.find(c => c.skillName === skillName)!.readyAt - Date.now()))
          : 0
      }
    });

    this.broadcastInZone(session.zoneId, {
      type: PacketType.ENTITY_ANIMATION,
      timestamp: Date.now(),
      data: { entityId: characterId, animation: 'Attack' }
    }, characterId);

    this.sendToPlayer(characterId, {
      type: PacketType.STATS_UPDATE,
      timestamp: Date.now(),
      data: { characterId, stats: session.stats, statBreakdown: session.statBreakdown }
    });

    if (session.statusEffects.length > 0) {
      this.sendToPlayer(characterId, {
        type: PacketType.STATUS_EFFECT_UPDATE,
        timestamp: Date.now(),
        data: { effects: session.statusEffects }
      });
    }

    if (result.summonObject) {
      const summon = this.summonMgr.spawnSummon(
        characterId,
        session.characterName,
        session.zoneId,
        result.summonObject,
        aoePosition,
        session.rotation?.y || 0,
        result.element,
      );
      if (summon) {
        this.broadcastInZone(session.zoneId, {
          type: PacketType.ENTITY_SPAWN,
          timestamp: Date.now(),
          data: {
            id: summon.id,
            type: 'summon',
            position: summon.position,
            rotation: { x: 0, y: summon.rotation, z: 0, w: 1 },
            data: {
              summonType: summon.summonType,
              ownerId: summon.ownerId,
              ownerName: summon.ownerName,
              health: summon.health,
              maxHealth: summon.maxHealth,
              defense: summon.defense,
              element: summon.element,
              duration: summon.duration,
            },
          },
        });
      }
    }

    if (result.banishObject) {
      const banishRadius = result.banishRadius || BANISH_RADIUS;
      const targets = this.summonMgr.getSummonsInRadius(session.zoneId, { x: aoePosition.x, z: aoePosition.z }, banishRadius);
      for (const s of targets) {
        this.summonMgr.despawnSummon(s.id);
        this.broadcastInZone(s.zoneId, {
          type: PacketType.ENTITY_DESPAWN,
          timestamp: Date.now(),
          data: { entityId: s.id },
        });
      }
    }

    if (result.damage) {
      this.applyAOEDamageToTargets(session, skillName, aoePosition, aoeRadius, result);
    }

    if (!result.summonObject && !result.banishObject) {
      this.spawnAOEZone(session, skillName, aoePosition, aoeRadius);
    }

    if (result.statusEffects && result.statusEffects.length > 0) {
      const targets = this.findAllEntitiesInRadius(session, aoePosition, aoeRadius);
      for (const target of targets) {
        const enemy = this.spawnMgr.getEnemy(target.id);
        if (enemy && enemy.state !== 'dead') {
          let anyApplied = false;
          let maxPotency = 0;
          for (const effect of result.statusEffects) {
            if (!this.shouldApplyDebuff(effect, target.id, session.characterId)) continue;
            if (this.hasActiveDebuff(target.id, effect.type, effect.skillName)) continue;
            const cloned = { ...effect, targetId: target.id };
            enemy.statusEffects.push(cloned);
            this.applyRemoveResistBuffs(enemy, cloned);
            anyApplied = true;
            if (effect.potency > maxPotency) maxPotency = effect.potency;
          }
          this.enmity.addDebuffEnmity(enemy, session.characterId, maxPotency, anyApplied);
          this.broadcastInZone(session.zoneId, {
            type: PacketType.ENTITY_STATUS_EFFECTS,
            timestamp: Date.now(),
            data: { entityId: target.id, effects: enemy.statusEffects }
          });
        }
      }
    }
  }

  executeConeSkillInternal(session: PlayerSession, skillName: string, targetId: string | null): void {
    const characterId = session.characterId;
    const skill = this.skillSys.findSkillDefinition(skillName);
    if (!skill) return;

    this.skillSys.executeSkill(session, skillName, targetId, (id) => this.getTargetStatsForEntity(id));
    this.playerSys.recalcStats(session);

    const facingAngle = session.rotation?.y || 0;
    const originX = session.position.x;
    const originZ = session.position.z;
    const coneAngleRad = ((skill.coneAngle || 45) * Math.PI) / 180;
    const coneRange = skill.coneRange || 8;
    const bladeWidth = skill.bladeWidth || 1.5;
    const bladeCount = skill.bladeCount || 1;
    const halfWidth = bladeWidth / 2;

    const bladeDirs: Array<{ x: number; z: number }> = [];
    for (let i = 0; i < bladeCount; i++) {
      const t = bladeCount === 1 ? 0.5 : i / (bladeCount - 1);
      const angle = facingAngle - coneAngleRad / 2 + t * coneAngleRad;
      bladeDirs.push({ x: Math.sin(angle), z: Math.cos(angle) });
    }

    this.broadcastInZone(session.zoneId, {
      type: PacketType.AOE_ENTITY,
      timestamp: Date.now(),
      data: {
        id: `cone_${characterId}_${Date.now()}`,
        position: { x: originX, y: session.position.y, z: originZ },
        data: {
          skillName,
          coneVfx: true,
          facingAngle,
          coneAngle: skill.coneAngle || 45,
          range: coneRange,
          bladeCount,
          bladeWidth,
        },
      },
    });

    const broadRadius = coneRange + halfWidth;
    const candidates = [
      ...this.queryEnemiesNear(originX, originZ, broadRadius, session.zoneId),
      ...this.queryPlayersNear(originX, originZ, broadRadius, session.zoneId),
    ];

    for (const entry of candidates) {
      if (entry.id === characterId) continue;
      if (this.state.players.has(entry.id)) {
        if (this.isPartyMember(characterId, entry.id)) continue;
        if (!isZonePvpEnabled(session.zoneId)) continue;
      }

      const enemy = this.spawnMgr.getEnemy(entry.id);
      if (enemy && enemy.state === 'dead') continue;
      const playerTarget = this.state.players.get(entry.id);

      const dx = entry.x - originX;
      const dz = entry.z - originZ;

      let totalDamage = 0;
      let anyCrit = false;
      let dmgType = 'physical';
      let allElemental: Array<{ element: string; damage: number }> = [];
      let totalPhysical = 0;
      let allPhysicalElemental: Array<{ element: string; damage: number }> = [];

      for (const dir of bladeDirs) {
        const projLen = dx * dir.x + dz * dir.z;
        if (projLen < 0 || projLen > coneRange) continue;
        const perpX = dx - projLen * dir.x;
        const perpZ = dz - projLen * dir.z;
        if (Math.sqrt(perpX * perpX + perpZ * perpZ) > halfWidth) continue;

        const result = this.skillSys.calculateAOEDamage(session, skillName, entry.id, (id) => this.getTargetStatsForEntity(id));
        if (!result?.damage) continue;

        totalDamage += result.damage;
        if (result.isCritical) anyCrit = true;
        dmgType = result.damageType || 'physical';
        if (result.elementalDamage) allElemental.push(...result.elementalDamage);
        if (result.physicalDamage) totalPhysical += result.physicalDamage;
        if (result.physicalElementalDamage) allPhysicalElemental.push(...result.physicalElementalDamage);
      }

      if (totalDamage === 0) continue;

      if (enemy) {
        const { died: mainDied } = this.damageEnemy(enemy, totalDamage, characterId);
        for (const el of allElemental) this.damageEnemy(enemy, el.damage, characterId);
        if (totalPhysical && enemy.health > 0) {
          this.damageEnemy(enemy, totalPhysical, characterId);
          for (const el of allPhysicalElemental) this.damageEnemy(enemy, el.damage, characterId);
        }

        this.broadcastInZone(session.zoneId, {
          type: PacketType.DAMAGE,
          timestamp: Date.now(),
          data: {
            attackerId: characterId,
            targetId: entry.id,
            damage: totalDamage,
            isCritical: anyCrit,
            damageType: dmgType,
            skillName,
            elementalDamage: allElemental.length ? allElemental : undefined,
            physicalDamage: totalPhysical || undefined,
            physicalElementalDamage: allPhysicalElemental.length ? allPhysicalElemental : undefined,
          }
        });

        const died = mainDied || enemy.health <= 0;
        if (died) {
          enemy.state = 'dead';
          enemy.deathTime = Date.now();
          const enemyDef = getEnemyDefinition(enemy.enemyType);
          if (enemyDef) {
            this.playerSys.grantExperience(session, enemyDef.experience);
            this.sendToPlayer(characterId, {
              type: PacketType.EXPERIENCE_GAIN,
              timestamp: Date.now(),
              data: { experience: enemyDef.experience, totalExperience: session.stats.experience, level: session.stats.level }
            });
            this.handleEnemyLoot(session, enemy.enemyType, enemy.position);
          }
          this.broadcastInZone(session.zoneId, { type: PacketType.DEATH, timestamp: Date.now(), data: { entityId: entry.id, killerId: characterId } });
          this.broadcastInZone(session.zoneId, { type: PacketType.ENTITY_DESPAWN, timestamp: Date.now(), data: { entityId: entry.id } });
        } else {
          this.broadcastInZone(session.zoneId, {
            type: PacketType.STATS_UPDATE,
            timestamp: Date.now(),
            data: { entityId: entry.id, health: enemy.health, maxHealth: enemy.maxHealth }
          });
          this.processOnHitProcs(session, entry.id, totalDamage, dmgType === 'physical');
        }
      } else if (playerTarget) {
        const total = totalDamage
          + allElemental.reduce((s, e) => s + e.damage, 0)
          + totalPhysical
          + allPhysicalElemental.reduce((s, e) => s + e.damage, 0);
        const dmgResult = this.applyPlayerDamage(playerTarget, total, characterId, dmgType, anyCrit, session.zoneId);
        this.broadcastInZone(session.zoneId, {
          type: PacketType.DAMAGE,
          timestamp: Date.now(),
          data: {
            attackerId: characterId,
            targetId: entry.id,
            damage: dmgResult.redirected ? 0 : dmgResult.damageTaken,
            isCritical: anyCrit,
            damageType: dmgType,
            skillName,
            elementalDamage: dmgResult.redirected ? [] : (allElemental.length ? allElemental : undefined),
            missed: dmgResult.redirected ? true : undefined,
            physicalDamage: totalPhysical || undefined,
            physicalElementalDamage: allPhysicalElemental.length ? allPhysicalElemental : undefined,
          }
        });
        if (!dmgResult.redirected) {
          this.sendToPlayer(entry.id, {
            type: PacketType.STATS_UPDATE,
            timestamp: Date.now(),
            data: { characterId: entry.id, stats: playerTarget.stats, statBreakdown: playerTarget.statBreakdown, skillProficiencies: playerTarget.skillProficiencies, skillAdeptness: playerTarget.skillAdeptness }
          });
          this.broadcastInZone(session.zoneId, {
            type: PacketType.STATS_UPDATE,
            timestamp: Date.now(),
            data: { entityId: entry.id, health: playerTarget.stats.health, maxHealth: playerTarget.stats.maxHealth }
          }, characterId);
          this.refreshPartyForMember(entry.id);
          if (playerTarget.stats.health <= 0) {
            this.handlePlayerDeath(playerTarget);
          }
        }
        this.consumeDebuffsOnHit(playerTarget);
      }
    }

    this.sendToPlayer(characterId, {
      type: PacketType.STATS_UPDATE,
      timestamp: Date.now(),
      data: { characterId, stats: session.stats, statBreakdown: session.statBreakdown, skillProficiencies: session.skillProficiencies, skillAdeptness: session.skillAdeptness }
    });

    if (this.skillSys.lastProficiencyGain) {
      const pg = this.skillSys.lastProficiencyGain;
      this.sendToPlayer(characterId, {
        type: PacketType.CHAT_MESSAGE,
        timestamp: Date.now(),
        data: { sender: 'Proficiency', message: `${pg.subCategory} +${pg.amount} (${Math.floor(pg.newAdeptness)}/${pg.cap})`, channel: 'system' }
      });
      this.skillSys.lastProficiencyGain = undefined;
    }

    this.sendToPlayer(characterId, {
      type: PacketType.COOLDOWN_UPDATE,
      timestamp: Date.now(),
      data: {
        skillName,
        type: 'used',
        mpCost: skill.mpCost || 0,
        cooldownRemaining: session.skillCooldowns.find(c => c.skillName === skillName)?.readyAt
          ? Math.max(0, (session.skillCooldowns.find(c => c.skillName === skillName)!.readyAt - Date.now()))
          : 0
      }
    });

    this.broadcastInZone(session.zoneId, {
      type: PacketType.ENTITY_ANIMATION,
      timestamp: Date.now(),
      data: { entityId: characterId, animation: 'Attack' }
    }, characterId);
  }

  applyDevotionRefund(session: PlayerSession, skillName: string, devotionFx: StatusEffect): void {
    const skillDef = this.skillSys.findSkillDefinition(skillName);
    const mpCost = skillDef?.mpCost || 0;
    if (mpCost <= 0) return;

    const partnerId = devotionFx.buffData!.devotionLink!.partnerId;
    const partner = this.state.players.get(partnerId);

    session.stats.mana += mpCost;
    if (partner) {
      const partnerContribution = Math.min(partner.stats.mana, mpCost);
      partner.stats.mana -= partnerContribution;
      const remainder = mpCost - partnerContribution;
      if (remainder > 0) {
        session.stats.mana = Math.max(0, session.stats.mana - remainder);
      }
      this.sendToPlayer(partnerId, {
        type: PacketType.STATS_UPDATE,
        timestamp: Date.now(),
        data: { characterId: partnerId, stats: partner.stats, statBreakdown: partner.statBreakdown }
      });
      this.refreshPartyForMember(partnerId);
    }
  }

  handleAOECastCompletion(session: PlayerSession, castResult: { skillName: string; aoePosition: { x: number; y: number; z: number }; targetId: string | null }): void {
    const skill = this.skillSys.findSkillDefinition(castResult.skillName);
    if (!skill) return;

    const devotionFx = session.statusEffects?.find(e => e.buffData?.devotionLink);
    if (devotionFx) {
      this.applyDevotionRefund(session, castResult.skillName, devotionFx);
    }

    this.executeAOESkillInternal(session, castResult.skillName, castResult.aoePosition);
  }

  applyAOEDamageToTargets(
    session: PlayerSession,
    skillName: string,
    aoePosition: { x: number; y: number; z: number },
    aoeRadius: number,
    primaryResult?: any
  ): void {
    const characterId = session.characterId;
    const targets = this.findAllEntitiesInRadius(session, aoePosition, aoeRadius);
    const skill = this.skillSys.findSkillDefinition(skillName);
    const batchEvents: Array<{ type: PacketType; data: any }> = [];

    for (const target of targets) {
      if (target.id !== characterId && this.state.players.has(target.id)) {
        if (this.isPartyMember(characterId, target.id)) continue;
        if (!isZonePvpEnabled(session.zoneId)) continue;
      }

      const targetResult = primaryResult && primaryResult.damage
        ? primaryResult
        : this.skillSys.calculateAOEDamage(session, skillName, target.id, (id) => this.getTargetStatsForEntity(id));

      if (!targetResult?.damage) continue;

      const enemy = this.spawnMgr.getEnemy(target.id);
      if (enemy) {
        const { died: mainDied } = this.damageEnemy(enemy, targetResult.damage, characterId);
        if (targetResult.elementalDamage) {
          for (const el of targetResult.elementalDamage) {
            this.damageEnemy(enemy, el.damage, characterId);
          }
        }
        if (targetResult.physicalDamage && enemy.health > 0) {
          this.damageEnemy(enemy, targetResult.physicalDamage, characterId);
          if (targetResult.physicalElementalDamage) {
            for (const el of targetResult.physicalElementalDamage) {
              this.damageEnemy(enemy, el.damage, characterId);
            }
          }
          if (enemy.health > 0) {
            this.processOnHitProcs(session, target.id, targetResult.physicalDamage, true);
            this.processGloomRecoil(session);
          }
        } else if ((targetResult.damageType || 'physical') === 'physical' && enemy.health > 0) {
          this.processGloomRecoil(session);
        }
        if (skill?.knockback && enemy.health > 0) {
          this.applySkillKnockback(enemy, session.position, skill.knockback);
        }
        const died = mainDied || enemy.health <= 0;
        batchEvents.push({
          type: PacketType.DAMAGE,
          data: {
            attackerId: characterId,
            targetId: target.id,
            damage: targetResult.damage,
            isCritical: targetResult.isCritical || false,
            damageType: targetResult.damageType || 'physical',
            skillName,
            elementalDamage: targetResult.elementalDamage,
            physicalDamage: targetResult.physicalDamage ?? undefined,
            physicalElementalDamage: targetResult.physicalElementalDamage,
          }
        });

        if (died) {
          enemy.state = 'dead';
          enemy.deathTime = Date.now();
          const enemyDef = getEnemyDefinition(enemy.enemyType);
          if (enemyDef) {
            this.playerSys.grantExperience(session, enemyDef.experience);
            this.sendToPlayer(characterId, {
              type: PacketType.EXPERIENCE_GAIN,
              timestamp: Date.now(),
              data: { experience: enemyDef.experience, totalExperience: session.stats.experience, level: session.stats.level }
            });
            this.sendToPlayer(characterId, {
              type: PacketType.STATS_UPDATE,
              timestamp: Date.now(),
              data: { characterId, stats: session.stats }
            });
            this.handleEnemyLoot(session, enemy.enemyType, enemy.position);
          }
          batchEvents.push({
            type: PacketType.DEATH,
            data: { entityId: target.id, killerId: characterId }
          });
          batchEvents.push({
            type: PacketType.ENTITY_DESPAWN,
            data: { entityId: target.id }
          });
        } else {
          batchEvents.push({
            type: PacketType.STATS_UPDATE,
            data: { entityId: target.id, health: enemy.health, maxHealth: enemy.maxHealth }
          });
        }

        if (targetResult.statusEffects && targetResult.statusEffects.length > 0) {
          let anyApplied = false;
          let maxPotency = 0;
          for (const effect of targetResult.statusEffects) {
            if (!this.shouldApplyDebuff(effect, target.id, characterId)) continue;
            if (this.hasActiveDebuff(target.id, effect.type, effect.skillName)) continue;
            const applied = { ...effect, targetId: target.id };
            enemy.statusEffects.push(applied);
            anyApplied = true;
            if (applied.potency > maxPotency) maxPotency = applied.potency;
          }
          if (anyApplied) {
            this.enmity.addDebuffEnmity(enemy, characterId, maxPotency, true);
            batchEvents.push({
              type: PacketType.ENTITY_STATUS_EFFECTS,
              data: { entityId: target.id, effects: enemy.statusEffects }
            });
          }
        }

        if (enemy.state !== 'dead') {
          this.processOnHitProcs(session, target.id, targetResult.damage, (targetResult.damageType || 'physical') === 'physical');
        }
      } else {
        const playerTarget = this.state.players.get(target.id);
        if (playerTarget && target.id !== characterId) {
          const coneTotalDmg = targetResult.damage
            + (targetResult.elementalDamage?.reduce((s: number, e: any) => s + e.damage, 0) || 0)
            + (targetResult.physicalDamage || 0)
            + (targetResult.physicalElementalDamage?.reduce((s: number, e: any) => s + e.damage, 0) || 0);
          const coneDmgRslt = this.applyPlayerDamage(playerTarget, coneTotalDmg, characterId, targetResult.damageType || 'physical', targetResult.isCritical || false, session.zoneId);
          if (!coneDmgRslt.redirected) {
            if (targetResult.physicalDamage && targetResult.physicalDamage > 0) {
              this.processOnHitProcs(session, target.id, targetResult.physicalDamage, true);
              this.processGloomRecoil(session);
            } else if ((targetResult.damageType || 'physical') === 'physical') {
              this.processGloomRecoil(session);
            }
            if (skill?.knockback && playerTarget.stats.health > 0) {
              this.applySkillKnockback(playerTarget, session.position, skill.knockback);
            }
          }
          batchEvents.push({
            type: PacketType.DAMAGE,
            data: {
              attackerId: characterId,
              targetId: target.id,
              damage: coneDmgRslt.redirected ? 0 : coneDmgRslt.damageTaken,
              isCritical: targetResult.isCritical || false,
              damageType: targetResult.damageType || 'physical',
              skillName,
              elementalDamage: coneDmgRslt.redirected ? [] : targetResult.elementalDamage,
              missed: coneDmgRslt.redirected ? true : undefined,
              physicalDamage: targetResult.physicalDamage ?? undefined,
              physicalElementalDamage: targetResult.physicalElementalDamage,
            }
          });
          if (!coneDmgRslt.redirected) {
            this.sendToPlayer(target.id, {
              type: PacketType.STATS_UPDATE,
              timestamp: Date.now(),
              data: { characterId: target.id, stats: playerTarget.stats, statBreakdown: playerTarget.statBreakdown, skillProficiencies: playerTarget.skillProficiencies, skillAdeptness: playerTarget.skillAdeptness }
            });
            if (!targetResult.physicalDamage) {
              this.processOnHitProcs(session, target.id, targetResult.damage, (targetResult.damageType || 'physical') === 'physical');
            }
            batchEvents.push({
              type: PacketType.STATS_UPDATE,
              data: { entityId: target.id, health: playerTarget.stats.health, maxHealth: playerTarget.stats.maxHealth }
            });
            this.refreshPartyForMember(target.id);
            if (playerTarget.stats.health <= 0) {
              this.handlePlayerDeath(playerTarget);
            }
          }
          this.consumeDebuffsOnHit(playerTarget);
        }
      }
    }

    if (batchEvents.length > 0) {
      this.broadcastInZone(session.zoneId, {
        type: PacketType.BATCH_COMBAT,
        timestamp: Date.now(),
        data: { events: batchEvents }
      });
    }
  }

  applySingleTargetSkillDamage(
    session: PlayerSession,
    skillName: string,
    targetId: string,
    result: any
  ): void {
    const characterId = session.characterId;
    const hits = result.hits;
    const skillDef = this.skillSys.findSkillDefinition(skillName);

    if (hits && hits.length > 1) {
      let enemyDied = false;
      const enemy = this.spawnMgr.getEnemy(targetId);
      if (enemy) {
        for (const hit of hits) {
          if (hit.damage > 0) {
            const { died } = this.damageEnemy(enemy, hit.damage, characterId);
            if (died) enemyDied = true;
            if (enemy.health > 0) {
              this.processOnHitProcs(session, targetId, hit.damage, (result.damageType || 'physical') === 'physical');
            }
          }
          if (hit.elementalDamage) {
            for (const el of hit.elementalDamage) {
              this.damageEnemy(enemy, el.damage, characterId);
            }
          }
          if ((result.damageType || 'physical') === 'physical' && enemy.health > 0 && hit.damage > 0) {
            this.processGloomRecoil(session);
          }
          this.broadcastInZone(session.zoneId, {
            type: PacketType.DAMAGE,
            timestamp: Date.now(),
            data: {
              attackerId: characterId,
              targetId,
              damage: hit.damage,
              isCritical: hit.isCritical,
              damageType: result.damageType || 'physical',
              skillName,
              elementalDamage: hit.elementalDamage,
            }
          });
        }
        this.broadcastInZone(session.zoneId, {
          type: PacketType.STATS_UPDATE,
          timestamp: Date.now(),
          data: { entityId: targetId, health: enemy.health, maxHealth: enemy.maxHealth }
        });
        if (enemyDied || enemy.health <= 0) {
          this.handleEnemyKill(targetId, characterId);
        }
        return;
      }

      const playerTarget = this.state.players.get(targetId);
      if (playerTarget && targetId !== characterId) {
        for (const hit of hits) {
          const hitTotal = hit.damage + (hit.elementalDamage?.reduce((s: number, e: any) => s + e.damage, 0) || 0);
          const coneDmgResult = this.applyPlayerDamage(playerTarget, hitTotal, characterId, result.damageType || 'physical', hit.isCritical, session.zoneId);
          if (!coneDmgResult.redirected && hit.damage > 0 && (result.damageType || 'physical') === 'physical') {
            this.processGloomRecoil(session);
          }
          this.broadcastInZone(session.zoneId, {
            type: PacketType.DAMAGE,
            timestamp: Date.now(),
            data: {
              attackerId: characterId,
              targetId,
              damage: coneDmgResult.redirected ? 0 : coneDmgResult.damageTaken,
              isCritical: hit.isCritical,
              damageType: result.damageType || 'physical',
              skillName,
              elementalDamage: coneDmgResult.redirected ? [] : hit.elementalDamage,
              missed: coneDmgResult.redirected ? true : undefined,
            }
          });
          if (!coneDmgResult.redirected && hit.damage > 0) {
            this.processOnHitProcs(session, targetId, hit.damage, (result.damageType || 'physical') === 'physical');
          }
        }
        if (playerTarget.stats.health > 0) {
          this.sendToPlayer(targetId, {
            type: PacketType.STATS_UPDATE,
            timestamp: Date.now(),
            data: { characterId: targetId, stats: playerTarget.stats, statBreakdown: playerTarget.statBreakdown, skillProficiencies: playerTarget.skillProficiencies, skillAdeptness: playerTarget.skillAdeptness }
          });
        }
        if (playerTarget.stats.health <= 0) {
          this.handlePlayerDeath(playerTarget);
        }
      }
      return;
    }

    const enemy = this.spawnMgr.getEnemy(targetId);
    if (enemy) {
      const { died: mainDied } = this.damageEnemy(enemy, result.damage!, characterId);
      if (result.elementalDamage) {
        for (const el of result.elementalDamage) {
          this.damageEnemy(enemy, el.damage, characterId);
        }
      }
      if (enemy.health > 0) {
        this.processOnHitProcs(session, targetId, result.damage || 0, (result.damageType || 'physical') === 'physical');
      }
      if ((result.damageType || 'physical') === 'physical' && enemy.health > 0) {
        this.processGloomRecoil(session);
      }
      if (skillDef?.knockback && enemy.health > 0) {
        this.applySkillKnockback(enemy, session.position, skillDef.knockback);
      }
      const died = mainDied || enemy.health <= 0;
      this.broadcastInZone(session.zoneId, {
        type: PacketType.DAMAGE,
        timestamp: Date.now(),
        data: {
          attackerId: characterId,
          targetId,
          damage: result.damage,
          isCritical: result.isCritical || false,
          damageType: result.damageType || 'physical',
          skillName,
          elementalDamage: result.elementalDamage,
        }
      });
      this.broadcastInZone(session.zoneId, {
        type: PacketType.STATS_UPDATE,
        timestamp: Date.now(),
        data: { entityId: targetId, health: enemy.health, maxHealth: enemy.maxHealth }
      });
      if (died) {
        this.handleEnemyKill(targetId, characterId);
      }
      return;
    }

    const playerTarget = this.state.players.get(targetId);
    if (playerTarget && targetId !== characterId) {
      const totalPvpDmg = (result.damage || 0) + (result.elementalDamage?.reduce((s: number, e: any) => s + e.damage, 0) || 0);
      const skillPvpDmgResult = this.applyPlayerDamage(playerTarget, totalPvpDmg, characterId, result.damageType || 'physical', result.isCritical || false, session.zoneId);
      if (!skillPvpDmgResult.redirected && (result.damageType || 'physical') === 'physical' && result.damage > 0) {
        this.processGloomRecoil(session);
      }
      if (skillDef?.knockback && !skillPvpDmgResult.redirected && playerTarget.stats.health > 0) {
        this.applySkillKnockback(playerTarget, session.position, skillDef.knockback);
      }
      this.broadcastInZone(session.zoneId, {
        type: PacketType.DAMAGE,
        timestamp: Date.now(),
        data: {
          attackerId: characterId,
          targetId,
          damage: skillPvpDmgResult.redirected ? 0 : skillPvpDmgResult.damageTaken,
          isCritical: result.isCritical || false,
          damageType: result.damageType || 'physical',
          skillName,
          elementalDamage: skillPvpDmgResult.redirected ? [] : result.elementalDamage,
          missed: skillPvpDmgResult.redirected ? true : undefined,
        }
      });
      if (!skillPvpDmgResult.redirected) {
        this.sendToPlayer(targetId, {
          type: PacketType.STATS_UPDATE,
          timestamp: Date.now(),
          data: { characterId: targetId, stats: playerTarget.stats, statBreakdown: playerTarget.statBreakdown, skillProficiencies: playerTarget.skillProficiencies, skillAdeptness: playerTarget.skillAdeptness }
        });
        if (result.damage > 0) {
          this.processOnHitProcs(session, targetId, result.damage, (result.damageType || 'physical') === 'physical');
        }
        if (playerTarget.stats.health <= 0) {
          this.handlePlayerDeath(playerTarget);
        }
      }
    }
  }

  spawnAOEZone(session: PlayerSession, skillName: string, position: { x: number; y: number; z: number }, radius: number): void {
    this.aoeZoneMgr.spawnAOEZone(session, skillName, position, radius);
  }

  private tickAOEZones(now: number): void {
    this.aoeZoneMgr.tickAOEZones(now);
  }

  applySongPulseImmediate(caster: PlayerSession): void {
    this.songMgr.applySongPulseImmediate(caster);
  }

  private tickSongProximity(now: number): void {
    this.songMgr.tick(now);
  }

  private applyRedSongDamage(
    caster: PlayerSession,
    skill: NonNullable<ReturnType<typeof this.skillSys.findSkillDefinition>>,
    songRadius: number
  ): void {
    if (!caster.position) return;
    const basePower = skill.basePower || 2;
    const totalSpi = (caster.baseStats?.SPI || 0) + (caster.statPoints?.SPI || 0);
    const exorcismProf = caster.skillProficiencies?.['Exorcism'] || 0;
    const baseDamage = Math.floor(basePower * (totalSpi * 0.5 + exorcismProf * 0.3 + caster.stats.level * 0.2));
    const mpDamage = Math.floor(baseDamage * 0.5);

    const enemiesInZone = this.spawnMgr.getEnemiesInZone(caster.zoneId);
    for (const [enemyId, enemy] of enemiesInZone) {
      if (enemy.health <= 0) continue;
      if (!enemy.position) continue;

      const dx = caster.position.x - enemy.position.x;
      const dz = caster.position.z - enemy.position.z;
      const dist = Math.sqrt(dx * dx + dz * dz);
      if (dist > songRadius) continue;

      const variance = 0.9 + Math.random() * 0.2;
      const hpDamage = Math.max(1, Math.floor(baseDamage * variance));

      const { died } = this.damageEnemy(enemy, hpDamage, caster.characterId);

      this.broadcastInZone(caster.zoneId, {
        type: PacketType.DAMAGE,
        timestamp: Date.now(),
        data: {
          attackerId: caster.characterId,
          targetId: enemyId,
          damage: hpDamage,
          isCritical: false,
          damageType: 'magical',
          skillName: skill.name,
        }
      });

      if (died) {
        this.handleEnemyKill(enemyId, caster.characterId);
      }
    }

    for (const [targetId, target] of this.state.players) {
      if (targetId === caster.characterId) continue;
      if (target.isDead) continue;
      if (target.zoneId !== caster.zoneId) continue;
      if (!target.position || !caster.position) continue;
      if (this.isPartyMember(caster.characterId, targetId)) continue;

      const dx = caster.position.x - target.position.x;
      const dz = caster.position.z - target.position.z;
      const dist = Math.sqrt(dx * dx + dz * dz);
      if (dist > songRadius) continue;

      const variance = 0.9 + Math.random() * 0.2;
      const hpDmg = Math.max(1, Math.floor(baseDamage * variance));
      const mpDmg = Math.max(1, Math.floor(mpDamage * variance));

      const dmgResult = this.applyPlayerDamage(target, hpDmg, caster.characterId, 'magical', false, target.zoneId);
      if (!dmgResult.redirected) {
        target.stats.mana = Math.max(0, target.stats.mana - mpDmg);
        this.sendToPlayer(targetId, {
          type: PacketType.DAMAGE,
          timestamp: Date.now(),
          data: { attackerId: caster.characterId, targetId, damage: dmgResult.damageTaken, isCritical: false, damageType: 'magical', skillName: skill.name, mpDamage: mpDmg }
        });
        this.sendToPlayer(targetId, {
          type: PacketType.STATS_UPDATE,
          timestamp: Date.now(),
          data: { characterId: targetId, stats: target.stats, statBreakdown: target.statBreakdown }
        });
        if (target.stats.health <= 0) {
          this.handlePlayerDeath(target);
        }
      }
    }
  }

  private tickBlockingProximity(now: number): void {
    this.blockingMgr.tick(now);
  }

  /** Combat callback invoked by AOEZoneManager when an entity newly enters a zone. */
  private onEntityEnterAOE(
    caster: PlayerSession,
    skillName: string,
    targetId: string,
    position: { x: number; y: number; z: number },
    radius: number
  ): void {
    this.damageEntityInAOE(caster, skillName, targetId, position, radius);
    this.applyAOEDebuffsOnEnter(caster, skillName, targetId);
  }

  private damageEntityInAOE(
    session: PlayerSession,
    skillName: string,
    targetId: string,
    aoePosition: { x: number; y: number; z: number },
    aoeRadius: number
  ): void {
    const enemy = this.spawnMgr.getEnemy(targetId);
    if (enemy && enemy.state !== 'dead') {
      const targetStats = this.getTargetStatsForEntity(targetId);
      const result = this.skillSys.calculateAOEDamage(session, skillName, targetId, () => targetStats);
      if (result?.damage) {
        const { died } = this.damageEnemy(enemy, result.damage, session.characterId);
        this.broadcastInZone(session.zoneId, {
          type: PacketType.DAMAGE,
          timestamp: Date.now(),
          data: {
            attackerId: session.characterId,
            targetId,
            damage: result.damage,
            isCritical: result.isCritical || false,
            damageType: result.damageType || 'physical',
            skillName,
            elementalDamage: result.elementalDamage,
          }
        });
        if (!died) {
          this.broadcastInZone(session.zoneId, {
            type: PacketType.STATS_UPDATE,
            timestamp: Date.now(),
            data: { entityId: targetId, health: enemy.health, maxHealth: enemy.maxHealth }
          });
        } else {
          this.handleEnemyKill(targetId, session.characterId);
        }
      }
    }
  }

  private applyAOEDebuffsOnEnter(caster: PlayerSession, skillName: string, targetId: string): void {
    const skill = this.skillSys.findSkillDefinition(skillName);
    if (!skill?.debuffEffectTable) return;

    const debuffEffects = this.skillSys.buildDebuffEffects(caster, skill);
    if (debuffEffects.length === 0) return;

    const enemy = this.spawnMgr.getEnemy(targetId);
    if (enemy && enemy.state !== 'dead') {
      let changed = false;
      let maxPotency = 0;
      for (const effect of debuffEffects) {
        if (enemy.statusEffects.some(e => e.type === effect.type && e.skillName === skillName)) continue;
        const applied = { ...effect, targetId };
        enemy.statusEffects.push(applied);
        this.applyRemoveResistBuffs(enemy, applied);
        changed = true;
        if (effect.potency > maxPotency) maxPotency = effect.potency;
      }
      if (changed) {
        this.enmity.addDebuffEnmity(enemy, caster.characterId, maxPotency, true);
        this.broadcastInZone(caster.zoneId, {
          type: PacketType.ENTITY_STATUS_EFFECTS,
          timestamp: Date.now(),
          data: { entityId: targetId, effects: enemy.statusEffects }
        });
      }
    }

    const player = this.state.players.get(targetId);
    if (player && targetId !== caster.characterId) {
      let changed = false;
      for (const effect of debuffEffects) {
        if (!this.shouldApplyDebuff(effect, targetId, caster.characterId)) continue;
        if (player.statusEffects.some(e => e.type === effect.type && e.skillName === skillName)) continue;
        const applied = { ...effect, targetId };
        player.statusEffects.push(applied);
        changed = true;
      }
      if (changed) {
        this.playerSys.recalcStats(player);
        this.sendToPlayer(targetId, {
          type: PacketType.STATUS_EFFECT_UPDATE,
          timestamp: Date.now(),
          data: { effects: player.statusEffects }
        });
        this.sendToPlayer(targetId, {
          type: PacketType.STATS_UPDATE,
          timestamp: Date.now(),
          data: { characterId: targetId, stats: player.stats }
        });
      }
    }
  }

  gameLoop(_elapsedMs?: number): void {
    const now = Date.now();

    this.tickPlayerUpdates(now);
    this.tickAOEZones(now);
    this.tickSongProximity(now);
    this.tickBlockingProximity(now);
    this.tickEnemyStatusEffects(now);
    this.tickDummies();
    this.tickSummons(now);
    this.tickAI(now);
    this.tickEntityAOEEntries();
    this.tickKnockback();
    this.updateEnemySpatialHash();
    this.broadcastEntityStates();
    this.tickLootExpiry();
  }

  private tickPlayerUpdates(now: number): void {
    this.state.players.forEach(session => {
      if (session.isDead) return;

      if (session.resistCache) session.resistCache.clear();

      this.skillSys.updateCooldowns(session);

      const castResult = this.skillSys.checkCasting(session);
      if (castResult?.completed) {
        if (castResult.aoePosition) {
          this.handleAOECastCompletion(session, { skillName: castResult.skillName, aoePosition: castResult.aoePosition!, targetId: castResult.targetId });
          this.sendToPlayer(session.characterId, {
            type: PacketType.STATS_UPDATE,
            timestamp: Date.now(),
            data: { characterId: session.characterId, stats: session.stats }
          });
            this.sendToPlayer(session.characterId, {
              type: PacketType.STATUS_EFFECT_UPDATE,
              timestamp: Date.now(),
              data: { effects: session.statusEffects }
            });
          return;
        }
        const completedSkillDef = this.skillSys.findSkillDefinition(castResult.skillName);
        if (completedSkillDef?.aoeTargetMode === AOETargetMode.CONE) {
          const devotionFx = session.statusEffects?.find(e => e.buffData?.devotionLink);
          if (devotionFx) {
            this.applyDevotionRefund(session, castResult.skillName, devotionFx);
          }
          this.executeConeSkillInternal(session, castResult.skillName, castResult.targetId);
          this.sendToPlayer(session.characterId, {
            type: PacketType.STATS_UPDATE,
            timestamp: Date.now(),
            data: { characterId: session.characterId, stats: session.stats }
          });
          this.sendToPlayer(session.characterId, {
            type: PacketType.STATUS_EFFECT_UPDATE,
            timestamp: Date.now(),
            data: { effects: session.statusEffects }
          });
          return;
        }
        const result = this.skillSys.executeSkill(session, castResult.skillName, castResult.targetId, (id) => this.getTargetStatsForEntity(id));
        this.sendDamageDebug(session, result);
        this.playerSys.recalcStats(session);

        // Clear the client cast bar + start the cooldown for EVERY completion
        // path. Previously this send sat at the very end of the damage path, so
        // early-returning branches (Guardian apply/toggle, songs, defensive
        // march) left the caster's cast bar visually "stuck" even though the
        // server had already finalized the cast.
        this.sendToPlayer(session.characterId, {
          type: PacketType.COOLDOWN_UPDATE,
          timestamp: Date.now(),
          data: {
            skillName: castResult.skillName,
            type: 'used',
            mpCost: this.skillSys.findSkillDefinition(castResult.skillName)?.mpCost || 0,
            cooldownRemaining: session.skillCooldowns.find(c => c.skillName === castResult.skillName)?.readyAt
              ? Math.max(0, (session.skillCooldowns.find(c => c.skillName === castResult.skillName)!.readyAt - Date.now()))
              : 0
          }
        });

        if (result.songToggledOff) {
          this.removeSongProximityBuffs(session);
          this.sendToPlayer(session.characterId, {
            type: PacketType.STATUS_EFFECT_UPDATE,
            timestamp: Date.now(),
            data: { effects: session.statusEffects }
          });
          this.sendToPlayer(session.characterId, {
            type: PacketType.STATS_UPDATE,
            timestamp: Date.now(),
            data: { characterId: session.characterId, stats: session.stats, statBreakdown: session.statBreakdown, skillProficiencies: session.skillProficiencies, skillAdeptness: session.skillAdeptness }
          });
          this.broadcastEntityEffects(session);
          return;
        }

        const devotionFx = session.statusEffects?.find(e => e.buffData?.devotionLink);
        if (devotionFx && result.success) {
          this.applyDevotionRefund(session, castResult.skillName, devotionFx);
        }

        if (result.defensiveMarchToggledOff) {
          this.removeBlockingProtectedBuffs(session.characterId);
          this.sendToPlayer(session.characterId, {
            type: PacketType.STATUS_EFFECT_UPDATE,
            timestamp: Date.now(),
            data: { effects: session.statusEffects }
          });
          this.broadcastEntityEffects(session);
          return;
        }

        if (result.guardianToggledOff) {
          this.sendToPlayer(session.characterId, {
            type: PacketType.STATUS_EFFECT_UPDATE,
            timestamp: Date.now(),
            data: { effects: session.statusEffects }
          });
          this.broadcastEntityEffects(session);
          if (result.guardianRemovedTarget) {
            const guarded = this.state.players.get(result.guardianRemovedTarget);
            if (guarded) {
              guarded.statusEffects = guarded.statusEffects.filter(e => e.type !== StatusEffectType.BUFF_GUARDED);
              this.sendToPlayer(result.guardianRemovedTarget, {
                type: PacketType.STATUS_EFFECT_UPDATE,
                timestamp: Date.now(),
                data: { effects: guarded.statusEffects }
              });
              this.broadcastEntityEffects(guarded);
            }
          }
          return;
        }

        if (result.guardianApplied) {
          const guardedId = result.guardianApplied;
          const guarded = this.state.players.get(guardedId);
          if (guarded) {
            guarded.statusEffects = guarded.statusEffects.filter(e => e.type !== StatusEffectType.BUFF_GUARDED);
            guarded.statusEffects.push({
              id: `buff_${Date.now()}_guarded_${session.characterId}`,
              type: StatusEffectType.BUFF_GUARDED,
              sourceId: session.characterId,
              targetId: guardedId,
              potency: 0,
              appliedAt: Date.now(),
              duration: 300000,
              tickInterval: 0,
              lastTickAt: Date.now(),
              stacks: 1,
              skillName: 'Guardian',
              buffData: { guardedBy: session.characterId },
            });
            this.playerSys.recalcStats(guarded);
            this.sendToPlayer(guardedId, {
              type: PacketType.STATUS_EFFECT_UPDATE,
              timestamp: Date.now(),
              data: { effects: guarded.statusEffects }
            });
            this.broadcastEntityEffects(guarded);
          }
          this.sendToPlayer(session.characterId, {
            type: PacketType.STATUS_EFFECT_UPDATE,
            timestamp: Date.now(),
            data: { effects: session.statusEffects }
          });
          this.broadcastEntityEffects(session);
          return;
        }

        if (result.createdItems && result.createdItems.length > 0) {
          for (const ci of result.createdItems) {
            if (ci.consumeItems) {
              let canCraft = true;
              for (const mat of ci.consumeItems) {
                const count = session.inventory.filter(i => i.itemId === mat.itemId).reduce((s, i) => s + i.quantity, 0);
                if (count < mat.quantity) { canCraft = false; break; }
              }
              if (!canCraft) continue;
              for (const mat of ci.consumeItems) {
                let remaining = mat.quantity;
                for (let i = session.inventory.length - 1; i >= 0 && remaining > 0; i--) {
                  if (session.inventory[i].itemId === mat.itemId) {
                    const take = Math.min(session.inventory[i].quantity, remaining);
                    session.inventory[i].quantity -= take;
                    remaining -= take;
                    if (session.inventory[i].quantity <= 0) session.inventory.splice(i, 1);
                  }
                }
              }
            }
            this.playerSys.addItemToInventory(session, ci.itemId, ci.quantity);
            this.sendToPlayer(session.characterId, {
              type: PacketType.NOTIFICATION,
              timestamp: Date.now(),
              data: { message: `Created: ${ci.itemId} x${ci.quantity}` }
            });
          }
          this.sendToPlayer(session.characterId, {
            type: PacketType.INVENTORY_UPDATE,
            timestamp: Date.now(),
            data: { inventory: session.inventory, equipment: session.equipment }
          });
          return;
        }

        this.sendToPlayer(session.characterId, {
          type: PacketType.STATS_UPDATE,
          timestamp: Date.now(),
          data: { characterId: session.characterId, stats: session.stats, statBreakdown: session.statBreakdown, skillProficiencies: session.skillProficiencies, skillAdeptness: session.skillAdeptness }
        });

    if (this.skillSys.lastProficiencyGain) {
      const pg = this.skillSys.lastProficiencyGain;
      this.sendToPlayer(session.characterId, {
        type: PacketType.CHAT_MESSAGE,
        timestamp: Date.now(),
        data: { sender: 'Proficiency', message: `${pg.subCategory} +${pg.amount} (${Math.floor(pg.newAdeptness)}/${pg.cap})`, channel: 'system' }
      });
      this.skillSys.lastProficiencyGain = undefined;
    }

    if (this.skillSys.lastCooldownDebug) {
      const cd = this.skillSys.lastCooldownDebug;
      if (cd.cooldownReduction > 0) {
        this.sendToPlayer(session.characterId, {
          type: PacketType.CHAT_MESSAGE,
          timestamp: Date.now(),
          data: { sender: 'Cooldown', message: `${cd.skillName}: ${cd.baseCd}s -> ${cd.effective.toFixed(1)}s (-${cd.cooldownReduction}% INT=${cd.totalINT})`, channel: 'system' }
        });
      }
      this.skillSys.lastCooldownDebug = undefined;
    }

        if (this.skillSys.lastBuffDebug) {
          this.sendToPlayer(session.characterId, {
            type: PacketType.CHAT_MESSAGE,
            timestamp: Date.now(),
            data: { sender: 'Debug', message: this.skillSys.lastBuffDebug, channel: 'system' }
          });
          this.skillSys.lastBuffDebug = undefined;
        }

        this.broadcastInZone(session.zoneId, {
          type: PacketType.ENTITY_ANIMATION,
          timestamp: Date.now(),
          data: { entityId: session.characterId, animation: 'Attack' }
        }, session.characterId);

        if (result.missed && castResult.targetId) {
          this.broadcastInZone(session.zoneId, {
            type: PacketType.DAMAGE,
            timestamp: Date.now(),
            data: {
              attackerId: session.characterId,
              targetId: castResult.targetId,
              damage: 0,
              isCritical: false,
              damageType: result.damageType || 'physical',
              skillName: castResult.skillName,
              missed: true
            }
          });
        } else if (result.damage && castResult.targetId) {
          const enemy = this.spawnMgr.getEnemy(castResult.targetId);
          if (enemy) {
            const { died } = this.damageEnemy(enemy, result.damage, session.characterId);
            if (result.elementalDamage) {
              for (const el of result.elementalDamage) {
                this.damageEnemy(enemy, el.damage, session.characterId);
              }
            }
            this.broadcastInZone(session.zoneId, {
              type: PacketType.DAMAGE,
              timestamp: Date.now(),
              data: { attackerId: session.characterId, targetId: castResult.targetId, damage: result.damage, isCritical: result.isCritical || false, damageType: result.damageType || 'physical', skillName: castResult.skillName, elementalDamage: result.elementalDamage, missed: result.missed || undefined }
            });
            if (died) {
              this.handleEnemyKill(castResult.targetId, session.characterId);
            } else {
              this.broadcastInZone(session.zoneId, {
                type: PacketType.STATS_UPDATE,
                timestamp: Date.now(),
                data: { entityId: castResult.targetId, health: enemy.health, maxHealth: enemy.maxHealth }
              });
            }
          } else {
            const playerTarget = this.state.players.get(castResult.targetId);
            if (playerTarget) {
              const totalDmg = result.damage + (result.elementalDamage?.reduce((s: number, e: any) => s + e.damage, 0) || 0);
              const pvpDmgResult = this.applyPlayerDamage(playerTarget, totalDmg, session.characterId, result.damageType || 'physical', result.isCritical || false, session.zoneId);
              if (!pvpDmgResult.redirected) {
                this.sendToPlayer(castResult.targetId, {
                  type: PacketType.STATS_UPDATE,
                  timestamp: Date.now(),
                  data: { characterId: castResult.targetId, stats: playerTarget.stats, statBreakdown: playerTarget.statBreakdown, skillProficiencies: playerTarget.skillProficiencies, skillAdeptness: playerTarget.skillAdeptness }
                });
                this.broadcastInZone(session.zoneId, {
                  type: PacketType.STATS_UPDATE,
                  timestamp: Date.now(),
                  data: { entityId: castResult.targetId, health: playerTarget.stats.health, maxHealth: playerTarget.stats.maxHealth }
                }, session.characterId);
                this.refreshPartyForMember(castResult.targetId);
                if (playerTarget.stats.health <= 0) {
                  this.handlePlayerDeath(playerTarget);
                }
              }
              this.broadcastInZone(session.zoneId, {
                type: PacketType.DAMAGE,
                timestamp: Date.now(),
                data: { attackerId: session.characterId, targetId: castResult.targetId, damage: pvpDmgResult.redirected ? 0 : pvpDmgResult.damageTaken, isCritical: result.isCritical || false, damageType: result.damageType || 'physical', skillName: castResult.skillName, elementalDamage: pvpDmgResult.redirected ? [] : result.elementalDamage, missed: result.missed || undefined }
              });
              this.consumeDebuffsOnHit(playerTarget);
            }
          }
        }

        if (result.revived && castResult.targetId) {
          this.handleRevivePlayerBySession(session, castResult.targetId);
        }

        if (result.healing) {
          const healTargetId = castResult.targetId && castResult.targetId !== session.characterId ? castResult.targetId : null;
          const healTarget = healTargetId ? this.state.players.get(healTargetId) : null;
          if (healTarget) {
            if (healTarget.isDead) return;
            healTarget.stats.health = Math.min(healTarget.stats.maxHealth, healTarget.stats.health + result.healing);
            this.broadcastInZone(session.zoneId, {
              type: PacketType.HEAL,
              timestamp: Date.now(),
              data: { targetId: castResult.targetId, amount: result.healing }
            });
            this.sendToPlayer(castResult.targetId!, {
              type: PacketType.STATS_UPDATE,
              timestamp: Date.now(),
              data: { characterId: castResult.targetId, stats: healTarget.stats }
            });
            this.broadcastInZone(session.zoneId, {
              type: PacketType.STATS_UPDATE,
              timestamp: Date.now(),
              data: { entityId: castResult.targetId, health: healTarget.stats.health, maxHealth: healTarget.stats.maxHealth }
            }, session.characterId);
            this.refreshPartyForMember(castResult.targetId!);
          } else {
            if (!session.isDead) {
              session.stats.health = Math.min(session.stats.maxHealth, session.stats.health + result.healing);
              this.sendToPlayer(session.characterId, {
                type: PacketType.HEAL,
                timestamp: Date.now(),
                data: { targetId: session.characterId, amount: result.healing }
              });
              this.refreshPartyForMember(session.characterId);
            }
          }
        }

        if (result.mpRestored) {
          this.sendToPlayer(session.characterId, {
            type: PacketType.HEAL,
            timestamp: Date.now(),
            data: { targetId: session.characterId, amount: result.mpRestored, mpRestore: true }
          });
        }

        if (result.manaSwap && castResult.targetId) {
          const target = this.state.players.get(castResult.targetId);
          if (target) {
            const casterMana = session.stats.mana;
            const targetMana = target.stats.mana;
            session.stats.mana = targetMana;
            target.stats.mana = casterMana;
            this.sendToPlayer(session.characterId, {
              type: PacketType.STATS_UPDATE,
              timestamp: Date.now(),
              data: { characterId: session.characterId, stats: session.stats, statBreakdown: session.statBreakdown }
            });
            this.sendToPlayer(castResult.targetId, {
              type: PacketType.STATS_UPDATE,
              timestamp: Date.now(),
              data: { characterId: castResult.targetId, stats: target.stats, statBreakdown: target.statBreakdown }
            });
            this.refreshPartyForMember(session.characterId);
            this.refreshPartyForMember(castResult.targetId);
          }
        }

        if (result.soulSwap && castResult.targetId) {
          const target = this.state.players.get(castResult.targetId);
          if (target) {
            const casterBuffs = session.statusEffects.filter(e => !e.type.startsWith('DEBUFF_') && e.type !== StatusEffectType.CURSE);
            const targetBuffs = target.statusEffects.filter(e => !e.type.startsWith('DEBUFF_') && e.type !== StatusEffectType.CURSE);
            session.statusEffects = [...session.statusEffects.filter(e => e.type.startsWith('DEBUFF_') || e.type === StatusEffectType.CURSE), ...targetBuffs.map(b => ({ ...b, sourceId: session.characterId, targetId: session.characterId }))];
            target.statusEffects = [...target.statusEffects.filter(e => e.type.startsWith('DEBUFF_') || e.type === StatusEffectType.CURSE), ...casterBuffs.map(b => ({ ...b, sourceId: target.characterId, targetId: target.characterId }))];
            this.playerSys.recalcStats(session);
            this.playerSys.recalcStats(target);
            this.sendToPlayer(session.characterId, {
              type: PacketType.STATUS_EFFECT_UPDATE,
              timestamp: Date.now(),
              data: { effects: session.statusEffects }
            });
            this.sendToPlayer(castResult.targetId, {
              type: PacketType.STATUS_EFFECT_UPDATE,
              timestamp: Date.now(),
              data: { effects: target.statusEffects }
            });
            this.sendToPlayer(session.characterId, {
              type: PacketType.STATS_UPDATE,
              timestamp: Date.now(),
              data: { characterId: session.characterId, stats: session.stats, statBreakdown: session.statBreakdown }
            });
            this.sendToPlayer(castResult.targetId, {
              type: PacketType.STATS_UPDATE,
              timestamp: Date.now(),
              data: { characterId: castResult.targetId, stats: target.stats, statBreakdown: target.statBreakdown }
            });
            this.broadcastEntityEffects(session);
            this.broadcastEntityEffects(target);
          }
        }

        this.sendToPlayer(session.characterId, {
          type: PacketType.STATS_UPDATE,
          timestamp: Date.now(),
          data: { characterId: session.characterId, stats: session.stats }
        });

        this.sendToPlayer(session.characterId, {
          type: PacketType.STATUS_EFFECT_UPDATE,
          timestamp: Date.now(),
          data: { effects: session.statusEffects }
        });
        this.broadcastEntityEffects(session);

        const castSkill = this.skillSys.findSkillDefinition(castResult.skillName);
        if (castSkill) {
          const castTargetType = SKILL_TARGET_RULES[castResult.skillName];
          if (castSkill.duration > 0 && castResult.targetId && castResult.targetId !== session.characterId && !castSkill.debuffEffectTable && !castSkill.isDebuff) {
            const shouldApply = !castTargetType
              || castTargetType === SkillTargetType.SELF_OR_TARGET
              || castTargetType === SkillTargetType.PARTY
              || castTargetType === SkillTargetType.OTHER_ONLY;
            if (shouldApply) {
              const tSession = this.state.players.get(castResult.targetId);
              if (tSession) {
                this.skillSys.applyBuffToTarget(tSession, session.characterId, castSkill, session);
                this.playerSys.recalcStats(tSession);
                if (this.skillSys.lastBuffDebug) {
                  this.sendToPlayer(session.characterId, {
                    type: PacketType.CHAT_MESSAGE,
                    timestamp: Date.now(),
                    data: { sender: 'Debug', message: this.skillSys.lastBuffDebug, channel: 'system' }
                  });
                  this.skillSys.lastBuffDebug = undefined;
                }
                this.sendToPlayer(castResult.targetId, {
                  type: PacketType.STATUS_EFFECT_UPDATE,
                  timestamp: Date.now(),
                  data: { effects: tSession.statusEffects }
                });
                this.sendToPlayer(castResult.targetId, {
                  type: PacketType.STATS_UPDATE,
                  timestamp: Date.now(),
                  data: { characterId: castResult.targetId, stats: tSession.stats }
                });
                this.broadcastEntityEffects(tSession);
              }
            }
          }

          if (castTargetType === SkillTargetType.PARTY) {
            const partyMembers = this.partySys.getPartyMembers(session.characterId);
            for (const memberId of partyMembers) {
              if (memberId === session.characterId) continue;
              const memberSession = this.state.players.get(memberId);
              if (!memberSession || memberSession.isDead || memberSession.stats.health <= 0) continue;
              if (memberSession.zoneId !== session.zoneId) continue;

              if (castSkill.duration > 0) {
                this.skillSys.applyBuffToTarget(memberSession, session.characterId, castSkill, session);
                this.playerSys.recalcStats(memberSession);
                if (this.skillSys.lastBuffDebug) {
                  this.sendToPlayer(session.characterId, {
                    type: PacketType.CHAT_MESSAGE,
                    timestamp: Date.now(),
                    data: { sender: 'Debug', message: this.skillSys.lastBuffDebug, channel: 'system' }
                  });
                  this.skillSys.lastBuffDebug = undefined;
                }
                this.sendToPlayer(memberId, {
                  type: PacketType.STATUS_EFFECT_UPDATE,
                  timestamp: Date.now(),
                  data: { effects: memberSession.statusEffects }
                });
                this.sendToPlayer(memberId, {
                  type: PacketType.STATS_UPDATE,
                  timestamp: Date.now(),
                  data: { characterId: memberId, stats: memberSession.stats }
                });
                this.broadcastInZone(session.zoneId, {
                  type: PacketType.STATS_UPDATE,
                  timestamp: Date.now(),
                  data: { entityId: memberId, health: memberSession.stats.health, maxHealth: memberSession.stats.maxHealth }
                }, memberId);
                this.broadcastEntityEffects(memberSession);
              }

    if (result.healing && !session.isDead) {
                memberSession.stats.health = Math.min(memberSession.stats.maxHealth, memberSession.stats.health + result.healing);
                this.sendToPlayer(memberId, {
                  type: PacketType.HEAL,
                  timestamp: Date.now(),
                  data: { targetId: memberId, amount: result.healing }
                });
                this.sendToPlayer(memberId, {
                  type: PacketType.STATS_UPDATE,
                  timestamp: Date.now(),
                  data: { characterId: memberId, stats: memberSession.stats }
                });
                this.broadcastInZone(session.zoneId, {
                  type: PacketType.STATS_UPDATE,
                  timestamp: Date.now(),
                  data: { entityId: memberId, health: memberSession.stats.health, maxHealth: memberSession.stats.maxHealth }
                }, session.characterId);
                this.refreshPartyForMember(memberId);
              }

              if (result.maxHpIncrease) {
                const hpIncrease = this.skillSys.calculateMaxHpBuff(memberSession, castSkill);
                const healthRatio = memberSession.stats.maxHealth > 0 ? memberSession.stats.health / memberSession.stats.maxHealth : 1;
                memberSession.stats.maxHealth += hpIncrease;
                memberSession.stats.health = Math.min(memberSession.stats.maxHealth, Math.floor(memberSession.stats.maxHealth * healthRatio) + hpIncrease);
                this.sendToPlayer(memberId, {
                  type: PacketType.STATS_UPDATE,
                  timestamp: Date.now(),
                  data: { characterId: memberId, stats: memberSession.stats }
                });
                this.broadcastInZone(session.zoneId, {
                  type: PacketType.STATS_UPDATE,
                  timestamp: Date.now(),
                  data: { entityId: memberId, health: memberSession.stats.health, maxHealth: memberSession.stats.maxHealth }
                }, session.characterId);
                this.refreshPartyForMember(memberId);
              }

              if (result.mpRestored) {
                memberSession.stats.mana = Math.min(memberSession.stats.maxMana, memberSession.stats.mana + result.mpRestored);
                this.sendToPlayer(memberId, {
                  type: PacketType.HEAL,
                  timestamp: Date.now(),
                  data: { targetId: memberId, amount: result.mpRestored, mpRestore: true }
                });
              }
            }
          }
        }
        if (result.statusEffects && result.statusEffects.length > 0 && castResult.targetId) {
          const debuffTarget = this.state.players.get(castResult.targetId);
          if (debuffTarget) {
            for (const effect of result.statusEffects) {
              if (!this.shouldApplyDebuff(effect, castResult.targetId, session.characterId)) continue;
              if (this.hasActiveDebuff(castResult.targetId, effect.type, effect.skillName)) continue;
              effect.targetId = castResult.targetId;
              debuffTarget.statusEffects.push(effect);
            }
            this.playerSys.recalcStats(debuffTarget);
            this.sendToPlayer(castResult.targetId, {
              type: PacketType.STATUS_EFFECT_UPDATE,
              timestamp: Date.now(),
              data: { effects: debuffTarget.statusEffects }
            });
            this.sendToPlayer(castResult.targetId, {
              type: PacketType.STATS_UPDATE,
              timestamp: Date.now(),
              data: { characterId: castResult.targetId, stats: debuffTarget.stats }
            });
            this.broadcastEntityEffects(debuffTarget);
          } else {
            const debuffEnemy = this.spawnMgr.getEnemy(castResult.targetId);
            if (debuffEnemy && debuffEnemy.state !== 'dead') {
               let anyApplied = false;
               let maxPotency = 0;
               for (const effect of result.statusEffects) {
                 if (!this.shouldApplyDebuff(effect, castResult.targetId, session.characterId)) continue;
                 if (this.hasActiveDebuff(castResult.targetId, effect.type, effect.skillName)) continue;
                 effect.targetId = castResult.targetId;
                 debuffEnemy.statusEffects.push(effect);
                 anyApplied = true;
                 if (effect.potency > maxPotency) maxPotency = effect.potency;
               }
                const debuffEnemyDef = getEnemyDefinition(debuffEnemy.enemyType);
                if (!debuffEnemyDef || debuffEnemyDef.aggroRange > 0) {
                  this.enmity.addDebuffEnmity(debuffEnemy, session.characterId, maxPotency, anyApplied);
                }
              this.broadcastInZone(session.zoneId, {
                type: PacketType.ENTITY_STATUS_EFFECTS,
                timestamp: Date.now(),
                data: { entityId: castResult.targetId, effects: debuffEnemy.statusEffects }
              });
            }
          }
        }

        if (!result.damage && (!result.statusEffects || result.statusEffects.length === 0) && !result.provoked && !result.healing && castResult.targetId) {
          const fallbackSkillDef = this.skillSys.findSkillDefinition(castResult.skillName);
          if (fallbackSkillDef) {
            const fst = fallbackSkillDef.skillType;
            if (fst === SkillType.DEBUFF || fst === SkillType.FEAR || fst === SkillType.DISPEL) {
              const fallbackEnemy = this.spawnMgr.getEnemy(castResult.targetId);
              if (fallbackEnemy && fallbackEnemy.state !== 'dead') {
                this.enmity.addDebuffEnmity(fallbackEnemy, session.characterId, 0, false);
              }
            }
          }
        }
      }

      if (session.statusEffects && session.statusEffects.length > 0) {
        const tick = this.skillSys.tickStatusEffects(session, now);
        if (tick.damage > 0) {
          const dotDmgResult = this.applyPlayerDamage(session, tick.damage, '', 'magical', false, session.zoneId);
          if (!dotDmgResult.redirected) {
            this.sendToPlayer(session.characterId, {
              type: PacketType.DAMAGE,
              timestamp: Date.now(),
              data: { attackerId: '', targetId: session.characterId, damage: dotDmgResult.damageTaken, isCritical: false, damageType: 'magical', skillName: 'dot' }
            });
            if (session.stats.health <= 0) {
              this.handlePlayerDeath(session);
            }
          }
        }
        if (tick.mpDamage > 0) {
          session.stats.mana = Math.max(0, session.stats.mana - tick.mpDamage);
          this.sendToPlayer(session.characterId, {
            type: PacketType.DAMAGE,
            timestamp: Date.now(),
            data: { attackerId: '', targetId: session.characterId, damage: tick.mpDamage, isCritical: false, damageType: 'magical', skillName: 'mp_drain' }
          });
        }
        if (tick.mpRestored > 0) {
          session.stats.mana = Math.min(session.stats.maxMana, session.stats.mana + tick.mpRestored);
        }
        if (tick.healed > 0) {
          session.stats.health = Math.min(session.stats.maxHealth, session.stats.health + tick.healed);
        }
        if (tick.expired.length > 0) {
          this.playerSys.recalcStats(session);
          this.sendToPlayer(session.characterId, {
            type: PacketType.STATS_UPDATE,
            timestamp: Date.now(),
            data: { characterId: session.characterId, stats: session.stats, statBreakdown: session.statBreakdown }
          });
          this.sendToPlayer(session.characterId, {
            type: PacketType.STATUS_EFFECT_UPDATE,
            timestamp: Date.now(),
            data: { effects: session.statusEffects }
          });
          this.broadcastEntityEffects(session);
        }
      }

      if (session.stats.health > 0 && now - session.lastRegenTick >= REGEN_CONFIG.TICK_INTERVAL_MS) {
        let lpGain: number;
        let mpGain: number;

        if (session.isResting) {
          const restTicksElapsed = Math.floor((now - session.restStartedAt) / REGEN_CONFIG.TICK_INTERVAL_MS);
          let rampUp = 1;
          if (restTicksElapsed <= 1) rampUp = REST_REGEN_CONFIG.RAMP_TICK_0;
          else if (restTicksElapsed === 2) rampUp = REST_REGEN_CONFIG.RAMP_TICK_1;

          const lpRegen = Math.floor(session.stats.maxHealth / REST_REGEN_CONFIG.HP_DIVISOR)
            + Math.floor(session.statPoints.STA / REST_REGEN_CONFIG.HP_STA_DIVISOR);
          const mpRegen = Math.floor(session.stats.maxMana / REST_REGEN_CONFIG.MP_DIVISOR)
            + Math.floor(session.statPoints.SPI / REST_REGEN_CONFIG.MP_SPI_DIVISOR);
          lpGain = Math.floor(lpRegen * rampUp);
          mpGain = Math.floor(mpRegen * rampUp);
        } else {
          const inCombat = now - session.lastAttackTime < REGEN_CONFIG.OUT_OF_COMBAT_DELAY_MS;
          const lpRegen = Math.floor(session.stats.maxHealth / REGEN_CONFIG.LP_DIVISOR)
            + Math.floor(session.statPoints.STA / REGEN_CONFIG.LP_STA_DIVISOR);
          const mpRegen = Math.floor(session.stats.maxMana / REGEN_CONFIG.MP_DIVISOR)
            + Math.floor(session.statPoints.SPI / REGEN_CONFIG.MP_SPI_DIVISOR);
          lpGain = inCombat ? Math.floor(lpRegen * REGEN_CONFIG.IN_COMBAT_LP_MULTIPLIER) : lpRegen;
          mpGain = inCombat ? Math.floor(mpRegen * REGEN_CONFIG.IN_COMBAT_MP_MULTIPLIER) : mpRegen;
        }

        let changed = false;
        if (lpGain > 0 && session.stats.health < session.stats.maxHealth) {
          session.stats.health = Math.min(session.stats.maxHealth, session.stats.health + lpGain);
          changed = true;
        }
        if (mpGain > 0 && session.stats.mana < session.stats.maxMana) {
          session.stats.mana = Math.min(session.stats.maxMana, session.stats.mana + mpGain);
          changed = true;
        }

        session.lastRegenTick = now;

        if (changed) {
          this.sendToPlayer(session.characterId, {
            type: PacketType.STATS_UPDATE,
            timestamp: Date.now(),
            data: { characterId: session.characterId, stats: session.stats }
          });
          this.broadcastInZone(session.zoneId, {
            type: PacketType.STATS_UPDATE,
            timestamp: Date.now(),
            data: { entityId: session.characterId, health: session.stats.health, maxHealth: session.stats.maxHealth }
          }, session.characterId);
          this.refreshPartyForMember(session.characterId);
        }
      }

      const blockStanceEffect = session.statusEffects?.find(
        e => e.type === StatusEffectType.BUFF_BLOCKING_STANCE && e.buffData?.blockingStance
      );
      if (blockStanceEffect) {
        const lastDrain = (blockStanceEffect as any).lastMpDrainAt || blockStanceEffect.appliedAt;
        if (now - lastDrain >= 2000) {
          (blockStanceEffect as any).lastMpDrainAt = now;
          session.stats.mana = Math.max(0, session.stats.mana - 2);
          this.sendToPlayer(session.characterId, {
            type: PacketType.STATS_UPDATE,
            timestamp: Date.now(),
            data: { characterId: session.characterId, stats: session.stats, statBreakdown: session.statBreakdown, skillProficiencies: session.skillProficiencies, skillAdeptness: session.skillAdeptness }
          });
          if (session.stats.mana <= 0) {
            session.statusEffects = session.statusEffects.filter(e => e !== blockStanceEffect);
            this.removeBlockingProtectedBuffs(session.characterId);
            this.playerSys.recalcStats(session);
            this.sendToPlayer(session.characterId, {
              type: PacketType.CHAT_MESSAGE,
              timestamp: Date.now(),
              data: { sender: 'System', message: 'Blocking ended - out of MP', channel: 'system' }
            });
            this.sendToPlayer(session.characterId, {
              type: PacketType.STATUS_EFFECT_UPDATE,
              timestamp: Date.now(),
              data: { effects: session.statusEffects }
            });
            this.sendToPlayer(session.characterId, {
              type: PacketType.STATS_UPDATE,
              timestamp: Date.now(),
              data: { characterId: session.characterId, stats: session.stats, statBreakdown: session.statBreakdown, skillProficiencies: session.skillProficiencies, skillAdeptness: session.skillAdeptness }
            });
            this.broadcastEntityEffects(session);
          }
        }
      }

      const guardianRedirectFx = session.statusEffects?.find(
        e => e.type === StatusEffectType.BUFF_DAMAGE_REDIRECT && e.buffData?.damageRedirectTargetId
      );
      if (guardianRedirectFx && session.position) {
        const guardedCharId = guardianRedirectFx.buffData!.damageRedirectTargetId!;
        const guardedPlayer = this.state.players.get(guardedCharId);
        if (guardedPlayer && guardedPlayer.position) {
          const gdx = session.position.x - guardedPlayer.position.x;
          const gdy = session.position.y - guardedPlayer.position.y;
          const gdz = session.position.z - guardedPlayer.position.z;
          const gdist = Math.sqrt(gdx * gdx + gdy * gdy + gdz * gdz);
          if (gdist > 20) {
            session.statusEffects = session.statusEffects.filter(e => e !== guardianRedirectFx);
            this.playerSys.recalcStats(session);
            this.sendToPlayer(session.characterId, {
              type: PacketType.CHAT_MESSAGE,
              timestamp: Date.now(),
              data: { sender: 'System', message: 'Guardian link broken - target too far away', channel: 'system' }
            });
            this.sendToPlayer(session.characterId, {
              type: PacketType.STATUS_EFFECT_UPDATE,
              timestamp: Date.now(),
              data: { effects: session.statusEffects }
            });
            this.sendToPlayer(session.characterId, {
              type: PacketType.STATS_UPDATE,
              timestamp: Date.now(),
              data: { characterId: session.characterId, stats: session.stats, statBreakdown: session.statBreakdown, skillProficiencies: session.skillProficiencies, skillAdeptness: session.skillAdeptness }
            });
            this.broadcastEntityEffects(session);
            guardedPlayer.statusEffects = guardedPlayer.statusEffects.filter(e => e.type !== StatusEffectType.BUFF_GUARDED);
            this.sendToPlayer(guardedCharId, {
              type: PacketType.STATUS_EFFECT_UPDATE,
              timestamp: Date.now(),
              data: { effects: guardedPlayer.statusEffects }
            });
            this.broadcastEntityEffects(guardedPlayer);
          }
        }
      }

      if (session.statsDirty) {
        this.playerSys.recalcStats(session);
        session.statsDirty = false;
      }
    });
  }

  private tickEnemyStatusEffects(now: number): void {
    this.spawnMgr.iterateAllEnemies((enemy, enemyId) => {
      if (enemy.state === 'dead') return;
      if (!enemy.statusEffects || enemy.statusEffects.length === 0) return;

      const fakeSession: any = {
        stats: { health: enemy.health, maxHealth: enemy.maxHealth, mana: 0, maxMana: 0, attack: 0, defense: 0, speed: 0, speedMultiplier: 1, magicAttack: 0, critChance: 0, castSpeed: 1, level: enemy.level, experience: 0, experienceToNext: 0 },
        statPoints: { STR: 0, AGI: 0, INT: 0, SPI: 0, DEX: 0, STA: 0 },
        statusEffects: enemy.statusEffects,
        skillCooldowns: [],
        activeCast: null,
      };

      const tick = this.skillSys.tickStatusEffects(fakeSession, now);

      enemy.statusEffects = fakeSession.statusEffects;

      const zoneId = this.findZoneOfEnemy(enemyId);
      if (!zoneId) return;

      if (tick.damage > 0) {
        const { died } = this.damageEnemy(enemy, tick.damage);
        this.broadcastInZone(zoneId, {
          type: PacketType.DAMAGE,
          timestamp: Date.now(),
          data: { attackerId: '', targetId: enemyId, damage: tick.damage, isCritical: false, damageType: 'magical', skillName: 'dot' }
        });
        this.broadcastInZone(zoneId, {
          type: PacketType.STATS_UPDATE,
          timestamp: Date.now(),
          data: { entityId: enemyId, health: enemy.health, maxHealth: enemy.maxHealth }
        });
        if (died) {
          enemy.state = 'dead';
          enemy.deathTime = now;
          this.broadcastInZone(zoneId, {
            type: PacketType.DEATH,
            timestamp: Date.now(),
            data: { entityId: enemyId, killerId: '' }
          });
          this.broadcastInZone(zoneId, {
            type: PacketType.ENTITY_DESPAWN,
            timestamp: Date.now(),
            data: { entityId: enemyId }
          });
        }
      }

      if (tick.expired.length > 0) {
        this.broadcastInZone(zoneId, {
          type: PacketType.ENTITY_STATUS_EFFECTS,
          timestamp: Date.now(),
          data: { entityId: enemyId, effects: enemy.statusEffects }
        });
      }
    });
  }

  private tickSummons(now: number): void {
    this.summonMgr.tick(now, this.summonCombatDeps);
  }

  private findClosestEnemyToPosition(zoneId: string, pos: { x: number; y: number; z: number }, range: number): string | null {
    const zoneEnemies = this.spawnMgr.getEnemiesInZone(zoneId);
    let closestId: string | null = null;
    let closestDist = range;
    for (const [id, enemy] of zoneEnemies) {
      if (enemy.state === 'dead') continue;
      const dx = enemy.position.x - pos.x;
      const dz = enemy.position.z - pos.z;
      const dist = Math.sqrt(dx * dx + dz * dz);
      if (dist < closestDist) {
        closestDist = dist;
        closestId = id;
      }
    }
    return closestId;
  }

  private tickAI(now: number): void {
    this.aiTickBucket = (this.aiTickBucket + 1) % this.AI_TICK_STAGGER;

    const reusableZonePlayers = new Map<string, Map<string, { position: { x: number; y: number; z: number }; characterId: string }>>();

    for (const zoneId of this.spawnMgr.getZoneIds()) {
      const zonePlayerIds = this.zoneRegistry.get(zoneId)?.players;
      let zonePlayers = reusableZonePlayers.get(zoneId);
      if (!zonePlayers) {
        zonePlayers = new Map();
        reusableZonePlayers.set(zoneId, zonePlayers);
      }
      zonePlayers.clear();
      if (zonePlayerIds) {
        for (const cid of zonePlayerIds) {
          const s = this.state.players.get(cid);
          if (!s || s.isDead || s.invulnerableUntil > now) continue;
          if (s.currentNpcId) continue;
          if (s.statusEffects?.some(e => e.type === StatusEffectType.INVISIBLE)) continue;
          if (s.statusEffects?.some(e => e.buffData?.misdirection)) continue;
          zonePlayers.set(cid, { position: s.position, characterId: cid });
        }
      }

      const zoneSummons = new Map<string, { position: { x: number; y: number; z: number }; summonId: string }>();
      for (const summon of this.summonMgr.getSummonsInZone(zoneId)) {
        zoneSummons.set(summon.id, { position: summon.position, summonId: summon.id });
      }

      this.ai.updateDecisions(
        this.spawnMgr.getEnemiesInZone(zoneId),
        zonePlayers,
        zoneSummons,
        this.AI_TICK_STAGGER / this.tickRate,
        this.aiTickBucket,
        this.AI_TICK_STAGGER
      );

      this.ai.updateMovement(
        this.spawnMgr.getEnemiesInZone(zoneId),
        zonePlayers,
        zoneSummons,
        1 / this.tickRate
      );
    }
  }

  private tickEntityAOEEntries(): void {
    this.aoeZoneMgr.tickEntityAOEEntries();
  }

  private tickKnockback(): void {
    this.knockbackMgr.tick();
  }

  private updateEnemySpatialHash(): void {
    this.spatialMgr.updateEnemySpatialHash();
  }

  private broadcastEntityStates(): void {
    const INTEREST_RADIUS = NetworkServer.INTEREST_RADIUS;

    for (const zoneId of this.spawnMgr.getZoneIds()) {
      const zoneEnemies = this.spawnMgr.getEnemiesInZone(zoneId);
      if (!zoneEnemies) continue;
      const zonePlayerIds = this.zoneRegistry.get(zoneId)?.players;
      if (!zonePlayerIds || zonePlayerIds.size === 0) continue;

      for (const characterId of zonePlayerIds) {
        const player = this.state.players.get(characterId);
        if (!player || !player.position) continue;

        const px = player.position.x;
        const pz = player.position.z;

        const visible = this.queryEnemiesNear(px, pz, INTEREST_RADIUS, zoneId);

        if (visible.length > 0) {
          this.sendToPlayer(characterId, {
            type: PacketType.PLAYER_POSITION_UPDATE,
            timestamp: Date.now(),
            data: {
              entities: visible.map(e => ({
                id: e.id,
                position: e.data.position,
                rotation: { x: 0, y: e.data.rotation, z: 0, w: 1 },
                state: e.data.state,
                health: e.data.health,
                maxHealth: e.data.maxHealth,
                targetId: e.data.targetId
              }))
            }
          });
        }
      }

      const zoneSummons = this.summonMgr.getSummonsInZone(zoneId);
      if (zoneSummons.length > 0) {
        const summonStates = zoneSummons.map(s => ({
          id: s.id,
          position: s.position,
          rotation: { x: 0, y: s.rotation, z: 0, w: 1 },
          health: s.health,
          maxHealth: s.maxHealth,
          summonType: s.summonType,
          ownerId: s.ownerId,
        }));
        for (const characterId of zonePlayerIds) {
          this.sendToPlayer(characterId, {
            type: PacketType.PLAYER_POSITION_UPDATE,
            timestamp: Date.now(),
            data: { summons: summonStates },
          });
        }
      }
    }
  }

  spawnDummy(session: PlayerSession): void {
    this.dummyMgr.spawnDummy(session);
  }

  despawnDummy(dummyId: string, session: PlayerSession): void {
    this.dummyMgr.despawnDummy(dummyId, session);
  }

  setDummyProperty(dummyId: string, prop: string, value: string, session: PlayerSession): void {
    this.dummyMgr.setDummyProperty(dummyId, prop, value, session);
  }

  setDummyClass(dummyId: string, jobIdStr: string, session: PlayerSession): void {
    this.dummyMgr.setDummyClass(dummyId, jobIdStr, session);
  }

  setDummyGear(dummyId: string, preset: string, session: PlayerSession): void {
    this.dummyMgr.setDummyGear(dummyId, preset, session);
  }

  toggleDummyPvp(dummyId: string, session: PlayerSession): void {
    this.dummyMgr.toggleDummyPvp(dummyId, session);
  }

  toggleDummyWalk(dummyId: string, session: PlayerSession): void {
    this.dummyMgr.toggleDummyWalk(dummyId, session);
  }

  toggleDummyParty(dummyId: string, session: PlayerSession): void {
    this.dummyMgr.toggleDummyParty(dummyId, session);
  }

  private tickDummies(): void {
    this.dummyMgr.tick();
  }

  async saveAllCharacters(): Promise<void> {
    const sessions = [...this.state.players.values()];
    const BATCH_SIZE = 50;
    for (let i = 0; i < sessions.length; i += BATCH_SIZE) {
      const batch = sessions.slice(i, i + BATCH_SIZE);
      await Promise.all(batch.map(session =>
        this.auth.saveCharacter(session.characterId, {
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
        }).catch(err => console.error(`Failed to save ${session.characterId}:`, err))
      ));
    }
    console.log(`Saved ${sessions.length} character(s)`);
  }

  getSpawnManager(): SpawnManager {
    return this.spawnMgr;
  }

  populateEnemySpatialHash(): void {
    this.spatialMgr.populateEnemySpatialHash();
  }

  getGameState(): ServerGameState {
    return this.state;
  }

  getTickRate(): number {
    return this.tickRate;
  }

  getLastMoveBroadcast(characterId: string): number {
    return this.movementThrottle.get(characterId);
  }

  setLastMoveBroadcast(characterId: string, time: number): void {
    this.movementThrottle.set(characterId, time);
  }

  clearMovementThrottle(characterId: string): void {
    this.movementThrottle.clear(characterId);
  }
}
