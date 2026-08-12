import { Socket } from 'socket.io';
import {
  Packet, PacketType, PlayerSession,
  StatType, JobId, Race,
  SKILL_TARGET_RULES, SkillTargetType,
  StatusEffectType, StatusEffect, EnemyInstance,
  PartyVisibility, LootRule, MAX_LOOT_POOL,
} from '@dust-saga/shared';
import { AuthManager } from '../auth/AuthManager';
import { CombatSystem } from '../ecs/systems/CombatSystem';
import { AISystem } from '../ecs/systems/AISystem';
import { LootSystem } from '../ecs/systems/LootSystem';
import { PlayerSystem } from '../ecs/systems/PlayerSystem';
import { SkillSystem } from '../ecs/systems/SkillSystem';
import { PartySystem } from '../ecs/systems/PartySystem';
import { EnmitySystem } from '../ecs/systems/EnmitySystem';
import { TradeSystem } from '../ecs/systems/TradeSystem';
import { SpawnManager } from '../world/SpawnManager';
import { SummonManager } from '../world/SummonManager';
import { DummyMeta } from '../world/DummyManager';
import { QuestSystem } from '../../systems/QuestSystem';
import { CraftSystem } from '../../systems/CraftSystem';
import { CutsceneSystem } from '../../systems/CutsceneSystem';
import { ItemSystem } from '../../systems/ItemSystem';
import { PresenceService } from '../presence/PresenceService';
import { ZoneOwnership } from '../presence/ZoneOwnership';

export interface ServerGameState {
  players: Map<string, PlayerSession>;
  socketToPlayer: Map<string, string>;
  playerToSocket: Map<string, string>;
}

export type PacketHandler = (ctx: NetworkContext, socket: Socket, data: any) => void | Promise<void>;

export interface NetworkContext {
  readonly state: ServerGameState;
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
  readonly presence: PresenceService;
  readonly zoneOwnership: ZoneOwnership;

  findCharacterBySocket(socketId: string): string | undefined;
  findPlayerByCharacterId(characterId: string): PlayerSession | undefined;
  findZoneOfEntity(entityId: string): string;
  findZoneOfEnemy(enemyId: string): string | undefined;
  sendToSocket(socketId: string, packet: Packet): void;
  sendToPlayer(characterId: string, packet: Packet): void;
  broadcastInZone(zoneId: string, packet: Packet, excludeCharacterId?: string): void;
  sendZoneState(socket: Socket, zoneId: string, includePlayerId?: string): void;
  registerPlayerInZone(characterId: string, zoneId: string): void;
  unregisterPlayerFromZone(characterId: string): void;
  movePlayerToZone(characterId: string, newZoneId: string): void;
  cleanupPlayerZoneResources(session: PlayerSession): void;
  cancelRest(session: PlayerSession): void;
  completeZoneHandoffDeparture(session: PlayerSession): void;
  initiateZoneHandoff(session: PlayerSession): Promise<boolean>;
  resolveZoneHandoff(characterId: string): Promise<PlayerSession | null>;
  forEachPlayerInZone(zoneId: string, cb: (id: string, player: PlayerSession) => void): void;

  isPartyMember(characterId: string, targetId: string): boolean;
  refreshPartyForMember(characterId: string): void;
  sendPartyUpdate(partyId: string): void;
  broadcastEntityEffects(session: PlayerSession): void;

  handlePlayerDeath(session: PlayerSession): void;
  handleEnemyKill(enemyId: string, killerId: string): void;
  checkQuestCellEntry(session: PlayerSession): void;
  startCutscene(session: PlayerSession, cutsceneId: string): boolean;
  completeCutscene(session: PlayerSession): void;
  handleRevivePlayerBySession(caster: PlayerSession, targetId: string): void;
  /** Strip any Guardian link involving the given character (both protector and protected sides), syncing each affected player. */
  breakGuardianLinksFor(characterId: string): void;
  applyPlayerDamage(target: PlayerSession, damage: number, attackerId: string, damageType: string, isCritical: boolean, zoneId: string, attackerPosition?: { x: number; y: number; z: number }): { redirected: boolean; damageTaken: number };
  damageEnemy(enemy: EnemyInstance, damage: number, attackerId?: string): { died: boolean; actualDamage: number };
  getEnemyEffectiveDefense(enemy: EnemyInstance): number;
  sendDamageDebug(session: PlayerSession, result: { debugCalc?: string }): void;
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
  } | null;

  findClosestEntityToPosition(session: PlayerSession, pos: { x: number; y: number; z: number }, radius: number): { id: string; distance: number } | null;
  findAllEntitiesInRadius(session: PlayerSession, pos: { x: number; y: number; z: number }, radius: number): Array<{ id: string; distance: number }>;
  applyAOEDamageToTargets(session: PlayerSession, skillName: string, aoePosition: { x: number; y: number; z: number }, aoeRadius: number, primaryResult?: any): void;
  applySingleTargetSkillDamage(session: PlayerSession, skillName: string, targetId: string, result: any): void;
  processOnHitProcs(session: PlayerSession, targetId: string, damageDealt: number, isPhysical: boolean): void;
  processGloomRecoil(session: PlayerSession): void;
  spawnAOEZone(session: PlayerSession, skillName: string, position: { x: number; y: number; z: number }, radius: number): void;
  executeAOESkillInternal(session: PlayerSession, skillName: string, aoePosition: { x: number; y: number; z: number }): void;
  executeConeSkillInternal(session: PlayerSession, skillName: string, targetId: string | null): void;
  consumeDebuffsOnHit(targetSession: PlayerSession): void;
  shouldApplyDebuff(effect: StatusEffect, targetId: string, casterId?: string): boolean;
  hasActiveDebuff(targetId: string, effectType: StatusEffectType, skillName?: string): boolean;
  getDebuffResist(targetId: string, category: string): number;
  removeBlockingProtectedBuffs(blockerId: string): void;
  removeSongProximityBuffs(caster: PlayerSession): void;
  applySongPulseImmediate(caster: PlayerSession): void;

  getLastMoveBroadcast(characterId: string): number;
  setLastMoveBroadcast(characterId: string, time: number): void;
  clearMovementThrottle(characterId: string): void;
  updatePlayerSpatialPosition(characterId: string, position: { x: number; z: number }): void;

  spawnDummy(session: PlayerSession): void;
  despawnDummy(dummyId: string, session: PlayerSession): void;
  setDummyProperty(dummyId: string, prop: string, value: string, session: PlayerSession): void;
  setDummyClass(dummyId: string, jobIdStr: string, session: PlayerSession): void;
  setDummyGear(dummyId: string, preset: string, session: PlayerSession): void;
  toggleDummyPvp(dummyId: string, session: PlayerSession): void;
  toggleDummyWalk(dummyId: string, session: PlayerSession): void;
  toggleDummyParty(dummyId: string, session: PlayerSession): void;
  readonly dummyMeta: Map<string, DummyMeta>;
}
