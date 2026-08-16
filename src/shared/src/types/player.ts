import { StatPoints, StatType, createDefaultStatPoints } from './races';
import { JobId, SkillProficiencies, createDefaultSkillProficiencies, BaseClass } from './jobs';
import { BuffData, StatBonusBreakdown, EffectiveStats } from './status';
import { SkillCooldownEntry, ActiveCast } from './skills';
import { StatusEffect } from './status';
import { InventoryItem } from './items';
import { QuestObjective } from './quests';

export enum AccountRole {
  PLAYER = 'player',
  GM = 'gm',
  ADMIN = 'admin',
}

export const ACCOUNT_ROLE_RANK: Record<AccountRole, number> = {
  [AccountRole.PLAYER]: 0,
  [AccountRole.GM]: 1,
  [AccountRole.ADMIN]: 2,
};

export function roleAtLeast(actual: AccountRole | string | undefined | null, min: AccountRole): boolean {
  const a = ACCOUNT_ROLE_RANK[(actual as AccountRole) || AccountRole.PLAYER] ?? 0;
  return a >= (ACCOUNT_ROLE_RANK[min] ?? 0);
}

export interface PlayerStats {
  health: number;
  maxHealth: number;
  mana: number;
  maxMana: number;
  attack: number;
  defense: number;
  speed: number;
  speedMultiplier: number;
  magicAttack: number;
  critChance: number;
  castSpeed: number;
  level: number;
  experience: number;
  experienceToNext: number;
}

export interface PlayerSession {
  playerId: string;
  socketId: string;
  username: string;
  characterId: string;
  characterName: string;
  race: string;
  racialPassive?: string;
  role: AccountRole;
  jobId: JobId;
  baseClass: BaseClass;
  stats: PlayerStats;
  statPoints: StatPoints;
  baseStats: { STA: number; STR: number; AGI: number; DEX: number; SPI: number; INT: number };
  unspentStatPoints: number;
  unspentSkillPoints: number;
  skillProficiencies: SkillProficiencies;
  skillAdeptness: SkillProficiencies;
  position: { x: number; y: number; z: number };
  rotation: { x: number; y: number; z: number; w: number };
  zoneId: string;
  targetId: string | null;
  lastAttackTime: number;
  lastManualAttackTime: number;
  lastRegenTick: number;
  invulnerableUntil: number;
  isDead: boolean;
  isResting: boolean;
  restStartedAt: number;
  currentNpcId: string | null;
  deathTime: number;
  nation: 'varik' | 'pfelstein' | 'latugan' | null;
  lastSafeZoneId: string;
  skillCooldowns: SkillCooldownEntry[];
  activeCast: ActiveCast | null;
  statusEffects: StatusEffect[];
  statBreakdown: StatBonusBreakdown | null;
  effectiveStats: EffectiveStats | null;
  inventory: InventoryItem[];
  gold: number;
  equipment: {
    weapon: any | null;
    armor: any | null;
    helmet: any | null;
    boots: any | null;
    gloves: any | null;
    legs: any | null;
    shield: any | null;
    earring_1: any | null;
    earring_2: any | null;
    necklace: any | null;
    belt: any | null;
    ring_1: any | null;
    ring_2: any | null;
  };
  socketedSouls?: (InventoryItem | null)[];
  quests: Array<{
    questId: string;
    status: string;
    objectives: QuestObjective[];
    startedAt: number;
    title?: string;
    description?: string;
    lastTurnedInAt?: number;
    completionCount?: number;
  }>;
  statsDirty?: boolean;
  resistCache?: Map<string, number>;
  lastQuestCell?: string | null;
  learnedRecipes?: string[];
  unlockedZones?: string[];
  inCutscene?: boolean;
  cutsceneReturnPosition?: { x: number; y: number; z: number };
  cutsceneReturnRotation?: { x: number; y: number; z: number; w: number };
}

export interface EnmityEntry {
  ce: number;
  ve: number;
  timestamp: number;
  ceDecayAccum?: number;
  veDecayAccum?: number;
}

export interface EnemyInstance {
  id: string;
  enemyType: string;
  position: { x: number; y: number; z: number };
  rotation: number;
  health: number;
  maxHealth: number;
  level: number;
  state: 'idle' | 'patrol' | 'chase' | 'attack' | 'return' | 'dead';
  targetId: string | null;
  spawnPosition: { x: number; y: number; z: number };
  lastAttackTime: number;
  deathTime: number;
  patrolPoints: Array<{ x: number; y: number; z: number }>;
  currentPatrolIndex: number;
  statusEffects: StatusEffect[];
  invulnerable?: boolean;
  enmityTable?: Record<string, EnmityEntry>;
}

export interface DamageInfo {
  attackerId: string;
  targetId: string;
  damage: number;
  isCritical: boolean;
  damageType: 'physical' | 'magical';
  elementalDamage?: Array<{ element: string; damage: number }>;
  missed?: boolean;
  physicalDamage?: number;
  physicalElementalDamage?: Array<{ element: string; damage: number }>;
  isRanged?: boolean;
}
