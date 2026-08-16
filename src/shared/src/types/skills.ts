import { StatusEffectType } from './status';
import type { BuffEffectTable } from './status';
import type { DebuffEffectTable } from '../constants/debuffs';

export enum SkillCategoryId {
  MELEE = 0,
  TECHNIQUE = 6,
  PRAYER = 12,
  MAGIC = 17,
  SPECIAL = 22
}

export enum DamageType {
  PHYSICAL = 'physical',
  MAGICAL = 'magical'
}

export enum PhysicalDamageSubType {
  SLASH = 'slash',
  THRUST = 'thrust',
  CLEAVE = 'cleave',
  BASH = 'bash',
  RANGED = 'ranged'
}

export enum MagicalDamageSubType {
  FIRE = 'fire',
  ICE = 'ice',
  LIGHTNING = 'lightning',
  DARK = 'dark',
  HOLY = 'holy',
  POISON = 'poison'
}

export type DamageSubType = PhysicalDamageSubType | MagicalDamageSubType;

export interface SkillRequirement {
  skillName: string;
  points: number;
}

export type SkillReqPoints = number | SkillRequirement[];

export enum AOETargetMode {
  SELF_CENTERED = 'self_centered',
  TARGET_CENTERED = 'target_centered',
  GROUND_TARGETED = 'ground_targeted',
  CONE = 'cone',
}

import { WeaponType } from './items';

export interface SkillDefinition {
  name: string;
  reqPoints: SkillReqPoints;
  reqLevel?: number;
  mpCost: number;
  castTime: number;
  cooldown: number;
  duration: number;
  description: string;
  damageType?: DamageType;
  damageSubType?: DamageSubType;
  skillType?: SkillType;
  isPassive?: boolean;
  isAOE?: boolean;
  aoeTargetMode?: AOETargetMode;
  aoeRadius?: number;
  range?: number;
  isBuff?: boolean;
  isDebuff?: boolean;
  hasDebuff?: boolean;
  selfBuffOnly?: boolean;
  isRevive?: boolean;
  buffEffectTable?: BuffEffectTable;
  debuffEffectTable?: DebuffEffectTable;
  debuffDuration?: number;
  basePower?: number;
  baseHits?: number;
  pulseCount?: number;
  pulseInterval?: number;
  consumableItem?: string;
  consumableItemQuantity?: number;
  createItems?: Array<{ itemId: string; quantity: number; consumeItems?: Array<{ itemId: string; quantity: number }> }>;
  sacrificeHeal?: boolean;
  hidden?: boolean;
  isSong?: boolean;
  mpDamage?: boolean;
  onHitEffects?: OnHitEffect[];
  healing?: HealingEffect;
  delayExplosion?: { minSeconds: number; maxSeconds: number };
  dispelBuff?: boolean;
  dispelDebuff?: boolean;
  revealInvisible?: boolean;
  summonObject?: SummonObject;
  banishObject?: boolean;
  banishRadius?: number;
  negateFieldSpells?: boolean;
  fieldSpellNegationRadius?: number;
  damageVsLowDefense?: boolean;
  fearAOE?: boolean;
  preventResurrect?: boolean;
  curse?: boolean;
  blockOnly?: boolean;
  shieldRequired?: boolean;
  requiredWeaponType?: WeaponType[];
  invisible?: { stationaryOnly: boolean; mpCostPerSec: number };
  barrier?: 'physical' | 'magical';
  elementalAbsorption?: { elements: string[]; convertTo: 'hp' | 'mp' };
  manaShield?: { mpPerHp: number };
  manaSwap?: boolean;
  soulSwap?: boolean;
  devotion?: boolean;
  magicalAid?: { mpRestorePercent: number };
  removeResistBuffs?: string[];
  misdirection?: boolean;
  lineOfSightRequired?: boolean;
  scalingStat?: 'STR' | 'DEX' | 'INT' | 'SPI' | 'AGI' | 'STA';
  proficiencyBonus?: number;
  elementalPower?: number;
  dualPhysical?: {
    basePower: number;
    damageSubType?: PhysicalDamageSubType;
    scalingStat?: 'STR' | 'DEX' | 'INT' | 'SPI' | 'AGI' | 'STA';
  };
  knockback?: number;
  coneAngle?: number;
  coneRange?: number;
  bladeWidth?: number;
  bladeCount?: number;
}

export interface SkillSubCategory {
  id: number;
  name: string;
  skills: Record<string, SkillDefinition>;
  hidden?: boolean;
}

export interface SkillCategoryData {
  name: string;
  skills: SkillSubCategory[];
}

export interface ClassSpecificSkill {
  reqLevel?: number;
  reqPoints?: SkillReqPoints;
  mpCost: number;
  castTime: number;
  cooldown: number;
  duration: number;
  description: string;
  damageType?: DamageType;
  damageSubType?: DamageSubType;
  skillType?: SkillType;
  isAOE?: boolean;
  aoeTargetMode?: AOETargetMode;
  aoeRadius?: number;
  range?: number;
  buffEffectTable?: BuffEffectTable;
  debuffEffectTable?: DebuffEffectTable;
  debuffDuration?: number;
  basePower?: number;
  baseHits?: number;
  pulseCount?: number;
  pulseInterval?: number;
  onHitEffects?: OnHitEffect[];
  healing?: HealingEffect;
  consumableItem?: string;
  consumableItemQuantity?: number;
  isPassive?: boolean;
  isBuff?: boolean;
  isDebuff?: boolean;
  hasDebuff?: boolean;
  selfBuffOnly?: boolean;
  isRevive?: boolean;
  isSong?: boolean;
  sacrificeHeal?: boolean;
  mpDamage?: boolean;
  createItems?: Array<{ itemId: string; quantity: number; consumeItems?: Array<{ itemId: string; quantity: number }> }>;
  hidden?: boolean;
  delayExplosion?: { minSeconds: number; maxSeconds: number };
  dispelBuff?: boolean;
  dispelDebuff?: boolean;
  revealInvisible?: boolean;
  summonObject?: SummonObject;
  banishObject?: boolean;
  negateFieldSpells?: boolean;
  fieldSpellNegationRadius?: number;
  damageVsLowDefense?: boolean;
  fearAOE?: boolean;
  preventResurrect?: boolean;
  curse?: boolean;
  blockOnly?: boolean;
  shieldRequired?: boolean;
  invisible?: { stationaryOnly: boolean; mpCostPerSec: number };
  barrier?: 'physical' | 'magical';
  elementalAbsorption?: { elements: string[]; convertTo: 'hp' | 'mp' };
  manaShield?: { mpPerHp: number };
  manaSwap?: boolean;
  soulSwap?: boolean;
  devotion?: boolean;
  magicalAid?: { mpRestorePercent: number };
  removeResistBuffs?: string[];
  misdirection?: boolean;
  lineOfSightRequired?: boolean;
  scalingStat?: 'STR' | 'DEX' | 'INT' | 'SPI' | 'AGI' | 'STA';
  proficiencyBonus?: number;
  dualPhysical?: {
    basePower: number;
    damageSubType?: PhysicalDamageSubType;
    scalingStat?: 'STR' | 'DEX' | 'INT' | 'SPI' | 'AGI' | 'STA';
  };
  knockback?: number;
  coneAngle?: number;
  coneRange?: number;
  bladeWidth?: number;
  bladeCount?: number;
}

export type ClassSpecificSkills = Record<string, ClassSpecificSkill>;

export interface SkillCooldownEntry {
  skillName: string;
  readyAt: number;
}

export interface ActiveCast {
  skillName: string;
  startedAt: number;
  castTime: number;
  targetId: string | null;
  aoePosition?: { x: number; y: number; z: number };
}

export interface SkillAllocation {
  skillId: number;
  points: number;
}

export type SkillAllocations = SkillAllocation[];

export enum SkillTargetType {
  SELF = 'self',
  SELF_OR_TARGET = 'self_or_target',
  PARTY = 'party',
  OTHER_ONLY = 'other_only'
}

export enum SkillType {
  DAMAGE_PHYSICAL = 'damage_physical',
  DAMAGE_MAGICAL = 'damage_magical',
  HEAL = 'heal',
  HEAL_OVER_TIME = 'heal_over_time',
  PARTY_HEAL = 'party_heal',
  HP_BUFF = 'hp_buff',
  MP_RESTORE = 'mp_restore',
  DRAIN_LIFE = 'drain_life',
  SACRIFICE_HEAL = 'sacrifice_heal',
  REVIVE = 'revive',
  BUFF = 'buff',
  DEBUFF = 'debuff',
  SONG = 'song',
  CRAFT = 'craft',
  UTILITY = 'utility',
  SUMMON = 'summon',
  FIELD_SPELL = 'field_spell',
  MP_DAMAGE = 'mp_damage',
  DISPEL = 'dispel',
  FEAR = 'fear',
  PASSIVE = 'passive',
  PROVOKE = 'provoke',
  INVISIBILITY = 'invisibility',
  BARRIER = 'barrier',
  MANA_SHIELD = 'mana_shield',
  ABSORPTION = 'absorption',
  MANA_SWAP = 'mana_swap',
  SOUL_SWAP = 'soul_swap',
  DEVOTION = 'devotion',
  KNOCKBACK = 'knockback',
}

// Skill types that may be freely cast on other players in non-PvP zones
// (buffs, heals, revives, and other purely beneficial effects).
export const BENEFICIAL_SKILL_TYPES: ReadonlySet<SkillType> = new Set<SkillType>([
  SkillType.HEAL,
  SkillType.HEAL_OVER_TIME,
  SkillType.PARTY_HEAL,
  SkillType.HP_BUFF,
  SkillType.MP_RESTORE,
  SkillType.SACRIFICE_HEAL,
  SkillType.REVIVE,
  SkillType.BUFF,
  SkillType.BARRIER,
  SkillType.MANA_SHIELD,
  SkillType.ABSORPTION,
  SkillType.MANA_SWAP,
  SkillType.SOUL_SWAP,
  SkillType.DEVOTION,
  SkillType.SONG,
  SkillType.DISPEL,
]);

export function isBeneficialSkillType(type: SkillType): boolean {
  return BENEFICIAL_SKILL_TYPES.has(type);
}

export interface OnHitEffect {
  type: StatusEffectType;
  chance?: number;
  potency?: number | { formula?: string; stat?: string; [key: string]: unknown };
  duration?: number;
}

export interface HealingEffect {
  type: 'single' | 'party' | 'over_time' | 'hp_buff';
  baseAmount?: number;
  statMultipliers?: Record<string, number>;
  percentOfMaxHp?: number;
  flatBonus?: number;
  tickInterval?: number;
  proficiencyStat?: string;
  mpCostScaling?: number;
}

export interface SummonObject {
  objectType: string;
  duration: number;
  hp?: number;
  defense?: number;
  aoeDamage?: number;
  attackDamage?: number;
  attackRange?: number;
  attackCooldown?: number;
}

export const SKILL_TARGET_RULES: Record<string, SkillTargetType> = {
  // Melee self buffs
  'Ossify': SkillTargetType.SELF,
  'Concentration': SkillTargetType.SELF,

  // Defensive self buffs
  'Providence': SkillTargetType.PARTY,
  'Quick Step': SkillTargetType.SELF,
  'Avoidance': SkillTargetType.SELF,
  'Mana Shield': SkillTargetType.SELF,
  'Clear Mind': SkillTargetType.SELF,
  'Elemental Absorption': SkillTargetType.SELF,
  'Parapet': SkillTargetType.SELF,
  'Auto-guard': SkillTargetType.SELF,
  'Defensive March': SkillTargetType.SELF,

  'Guardian': SkillTargetType.OTHER_ONLY,

  // Offensive self buffs
  'Toxify': SkillTargetType.SELF,
  'Rush': SkillTargetType.SELF,
  'Gloom': SkillTargetType.SELF,
  'Raging Soul': SkillTargetType.SELF,
  'War Cry': SkillTargetType.SELF,
  'Lunge': SkillTargetType.SELF,
  'Desperado': SkillTargetType.SELF,
  'Magical Aid': SkillTargetType.SELF,
  'Skill Focus': SkillTargetType.SELF,

  // Enchanter song buffs
  'Green Song': SkillTargetType.SELF,
  'Blue Song': SkillTargetType.SELF,
  'Red Song': SkillTargetType.SELF,
  'Yellow Song': SkillTargetType.SELF,

  // Scout buffs
  'Hide': SkillTargetType.SELF,
  'Snipers Nest': SkillTargetType.SELF,
  'Watchful Eye': SkillTargetType.SELF,
  'Horse Archer': SkillTargetType.SELF,
  'Cloak': SkillTargetType.SELF,
  'Invigorate': SkillTargetType.SELF,
  'Sprint': SkillTargetType.SELF,
  'Spurt': SkillTargetType.SELF,
  'Bolster': SkillTargetType.SELF_OR_TARGET,
  'Accelerate': SkillTargetType.SELF_OR_TARGET,
  'Move Stream': SkillTargetType.PARTY,
  
  'Dash': SkillTargetType.SELF,

    
  // Elemental resistances
  'Resist Fire': SkillTargetType.SELF_OR_TARGET,
  'Resist Ice': SkillTargetType.SELF_OR_TARGET,
  'Resist Lightning': SkillTargetType.SELF_OR_TARGET,
  'Resist Malice': SkillTargetType.SELF_OR_TARGET,
  'Resist Charm': SkillTargetType.SELF_OR_TARGET,
  
  // Ascetic buffs
  'Bless Weapon': SkillTargetType.SELF_OR_TARGET,
  'Mana Restore': SkillTargetType.SELF_OR_TARGET,
  'Speedy Gale': SkillTargetType.PARTY,
  'Devotion': SkillTargetType.OTHER_ONLY,
  'Mental Aid': SkillTargetType.SELF_OR_TARGET,
  'Third Eye': SkillTargetType.PARTY,
  'Physical Barrier': SkillTargetType.SELF_OR_TARGET,
  'Magical Barrier': SkillTargetType.SELF_OR_TARGET,
  
  // Prayer 
  'Lapis Mediow': SkillTargetType.PARTY,
  'Group Barrier': SkillTargetType.PARTY,
  'Tranquil Mind': SkillTargetType.PARTY,
  'Divine Aid': SkillTargetType.PARTY,
  'Restoration': SkillTargetType.PARTY,
  'Regenerate': SkillTargetType.SELF_OR_TARGET,
  'Velox': SkillTargetType.SELF_OR_TARGET,
  'Battle Prayer': SkillTargetType.SELF_OR_TARGET,
  'Enchantment': SkillTargetType.SELF_OR_TARGET,
  'Saltio': SkillTargetType.OTHER_ONLY,
  'Revive': SkillTargetType.OTHER_ONLY,
  'Locomitigation': SkillTargetType.SELF_OR_TARGET,
  'Spirit Protection': SkillTargetType.SELF_OR_TARGET,


  // Debuffs
  'Poison': SkillTargetType.OTHER_ONLY,
  'Mind Venom': SkillTargetType.OTHER_ONLY,
  'Weakness': SkillTargetType.OTHER_ONLY,
  'Weaken': SkillTargetType.OTHER_ONLY,
  'Undermine': SkillTargetType.OTHER_ONLY,
  'Impedimentia': SkillTargetType.OTHER_ONLY,
  'Tangled Fingers': SkillTargetType.OTHER_ONLY,
  'Befuddle': SkillTargetType.OTHER_ONLY,
};

export function isPassiveSkill(skill: SkillDefinition | ClassSpecificSkill): boolean {
  if (skill.skillType === SkillType.PASSIVE) return true;
  if ('isPassive' in skill && skill.isPassive) return true;
  if ('name' in skill && skill.name.includes('(Passive)')) return true;
  return false;
}

export function getSkillTargetType(skill: SkillDefinition | ClassSpecificSkill): SkillTargetType | undefined {
  if ('skillType' in skill && skill.skillType) {
    switch (skill.skillType) {
      case SkillType.REVIVE:
      case SkillType.DEBUFF:
      case SkillType.DAMAGE_PHYSICAL:
      case SkillType.DAMAGE_MAGICAL:
      case SkillType.DISPEL:
      case SkillType.MP_DAMAGE:
      case SkillType.FEAR:
      case SkillType.SONG:
        return SkillTargetType.OTHER_ONLY;
      case SkillType.HEAL:
      case SkillType.PARTY_HEAL:
        return SkillTargetType.PARTY;
      case SkillType.BUFF:
      case SkillType.HEAL_OVER_TIME:
      case SkillType.HP_BUFF:
      case SkillType.MP_RESTORE:
      case SkillType.DRAIN_LIFE:
      case SkillType.SACRIFICE_HEAL:
        return SkillTargetType.SELF;
      case SkillType.CRAFT:
      case SkillType.SUMMON:
      case SkillType.UTILITY:
      case SkillType.FIELD_SPELL:
        return undefined;
    }
  }
  return undefined;
}

export function meetsRequirements(
  reqPoints: SkillReqPoints,
  getSkillPoints: (skillName: string) => number
): boolean {
  if (typeof reqPoints === 'number') return true;
  return (reqPoints as SkillRequirement[]).every(
    r => getSkillPoints(r.skillName) >= r.points
  );
}

export function getRequiredProficiency(reqPoints: SkillReqPoints): number {
  if (typeof reqPoints === 'number') return reqPoints;
  return Math.max(...(reqPoints as SkillRequirement[]).map(r => r.points));
}
