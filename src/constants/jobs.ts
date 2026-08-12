import { StatPoints, StatType } from './races';
import { getMinAdeptness, ALL_SUB_CATEGORIES } from '../constants/jobSkillValues';
import { PROFICIENCY_CONFIG } from '../constants/game';

export enum BaseClass {
  WARRIOR = 'warrior',
  SCOUT = 'scout',
  ACOLYTE = 'acolyte',
  MAGE = 'mage'
}

export enum JobId {
  WARRIOR = 'warrior',
  GLADIATOR = 'gladiator',
  JUGGERNAUT = 'juggernaut',
  DRAGOON = 'dragoon',
  KNIGHT = 'knight',
  WARLORD = 'warlord',
  PALADIN = 'paladin',
  SCOUT = 'scout',
  ARCHER = 'archer',
  SNIPER = 'sniper',
  HUNTER = 'hunter',
  PROVOCATEUR = 'provocateur',
  ASSASSIN = 'assassin',
  SABOTEUR = 'saboteur',
  ACOLYTE = 'acolyte',
  PRIEST = 'priest',
  CLERIC = 'cleric',
  ENCHANTER = 'enchanter',
  ASCETIC = 'ascetic',
  MONK = 'monk',
  EXORCIST = 'exorcist',
  MAGE = 'mage',
  WIZARD = 'wizard',
  WARLOCK = 'warlock',
  CONJURER = 'conjurer',
  SORCERER = 'sorcerer',
  CORRUPTOR = 'corruptor',
  SHADOWBLADE = 'shadowblade',
}

export interface JobDefinition {
  id: JobId;
  name: string;
  baseClass: BaseClass;
  tier: 1 | 2 | 3;
  parentJob: JobId | null;
  description: string;
  modelFile: string;
  baseStatModifiers: Partial<Record<StatType, number>>;
  lpBase: number;
  lpPerLevel: number;
  lpPerSta: number;
  mpBase: number;
  mpPerLevel: number;
  mpPerSpi: number;
}

export type SkillCategoryKey = 'melee' | 'technique' | 'prayer' | 'magic' | 'special';

export interface SkillProficiencies {
  melee: number;
  technique: number;
  prayer: number;
  magic: number;
  special: number;
  [subCategoryName: string]: number;
}

const ALL_SUB_CATEGORY_NAMES = [
  'Slash', 'Thrust', 'Cleave', 'Bash', 'Defend',
  'Shot', 'Alchemy', 'Assassination', 'Trap', 'Dodge',
  'Grace', 'Blessing', 'Exorcism', 'Hymn',
  'Elemental', 'Invocation', 'Darkness', 'Confusion',
  'Racial', 'Horsemanship',
] as const;

export const SUB_CATEGORY_TO_CATEGORY: Record<string, SkillCategoryKey> = {
  'Slash': 'melee', 'Thrust': 'melee', 'Cleave': 'melee', 'Bash': 'melee', 'Defend': 'melee',
  'Shot': 'technique', 'Alchemy': 'technique', 'Assassination': 'technique', 'Trap': 'technique', 'Dodge': 'technique',
  'Grace': 'prayer', 'Blessing': 'prayer', 'Exorcism': 'prayer', 'Hymn': 'prayer',
  'Elemental': 'magic', 'Invocation': 'magic', 'Darkness': 'magic', 'Confusion': 'magic',
  'Racial': 'special', 'Horsemanship': 'special',
  'Ranged': 'technique',
};

export function getCategoryTotal(proficiencies: SkillProficiencies, category: SkillCategoryKey): number {
  let total = 0;
  for (const [subName, cat] of Object.entries(SUB_CATEGORY_TO_CATEGORY)) {
    if (cat === category) {
      total += proficiencies[subName] || 0;
    }
  }
  return total;
}

export function recalculateCategoryTotals(proficiencies: SkillProficiencies): void {
  (Object.keys(SUB_CATEGORY_TO_CATEGORY) as string[]).reduce((acc, subName) => {
    const cat = SUB_CATEGORY_TO_CATEGORY[subName];
    acc[cat] = (acc[cat] || 0) + (proficiencies[subName] || 0);
    return acc;
  }, proficiencies as Record<string, number>);
  for (const cat of ['melee', 'technique', 'prayer', 'magic', 'special'] as SkillCategoryKey[]) {
    proficiencies[cat] = getCategoryTotal(proficiencies, cat);
  }
}

export function createDefaultSkillProficiencies(): SkillProficiencies {
  const proficiencies: SkillProficiencies = { melee: 0, technique: 0, prayer: 0, magic: 0, special: 0 };
  for (const subName of ALL_SUB_CATEGORIES) {
    proficiencies[subName] = 0;
  }
  return proficiencies;
}

export function createDefaultSkillAdeptness(designJobId: number): SkillProficiencies {
  const proficiencies: SkillProficiencies = { melee: 0, technique: 0, prayer: 0, magic: 0, special: 0 };
  for (const subName of ALL_SUB_CATEGORIES) {
    proficiencies[subName] = getMinAdeptness(designJobId, subName);
  }
  for (const cat of ['melee', 'technique', 'prayer', 'magic', 'special'] as SkillCategoryKey[]) {
    proficiencies[cat] = getCategoryTotal(proficiencies, cat);
  }
  return proficiencies;
}

export function getValidSubCategoryNames(): string[] {
  return [...ALL_SUB_CATEGORY_NAMES];
}

export interface ProficiencyGainResult {
  gained: boolean;
  subCategory: string;
  amount: number;
  newAdeptness: number;
  cap: number;
}

export function calculateProficiencyGain(
  currentAdeptness: number,
  maxProficiency: number,
  hasCastTime: boolean
): ProficiencyGainResult | null {
  if (maxProficiency <= 0 || currentAdeptness >= maxProficiency) {
    return null;
  }

  const ratio = currentAdeptness / maxProficiency;
  let gain: number;

  if (ratio < PROFICIENCY_CONFIG.TIER_1_RATIO) {
    gain = PROFICIENCY_CONFIG.TIER_1_GAIN_MIN
      + Math.random() * (PROFICIENCY_CONFIG.TIER_1_GAIN_MAX - PROFICIENCY_CONFIG.TIER_1_GAIN_MIN);
  } else if (ratio < PROFICIENCY_CONFIG.TIER_2_RATIO) {
    gain = PROFICIENCY_CONFIG.TIER_2_GAIN;
  } else {
    gain = PROFICIENCY_CONFIG.TIER_3_GAIN;
  }

  if (!hasCastTime) {
    gain *= PROFICIENCY_CONFIG.INSTANT_CAST_MULTIPLIER;
  }

  gain = Math.round(gain * 10) / 10;
  const newAdeptness = Math.round(Math.min(currentAdeptness + gain, maxProficiency) * 10) / 10;

  return {
    gained: true,
    subCategory: '',
    amount: Math.round((newAdeptness - currentAdeptness) * 10) / 10,
    newAdeptness,
    cap: maxProficiency,
  };
}

export interface CharacterInfo {
  id: string;
  name: string;
  race: string;
  jobId: JobId;
  level: number;
  experience: number;
  experienceToNext: number;
  position: { x: number; y: number; z: number };
  rotation: { x: number; y: number; z: number; w: number };
  zoneId: string;
}

export function getBaseClassForJob(jobId: JobId): BaseClass {
  const job = JOB_DEFINITIONS[jobId];
  return job ? job.baseClass : BaseClass.WARRIOR;
}

export function getAvailableJobs(baseClass: BaseClass, tier: 1 | 2 | 3): JobId[] {
  return Object.values(JOB_DEFINITIONS)
    .filter(j => j.baseClass === baseClass && j.tier === tier)
    .map(j => j.id);
}

export function getAdvancementOptions(currentJob: JobId): JobId[] {
  const current = JOB_DEFINITIONS[currentJob];
  if (!current) return [];
  if (current.tier === 3) return [];
  return Object.values(JOB_DEFINITIONS)
    .filter(j => j.parentJob === currentJob)
    .map(j => j.id);
}

export const JOB_DEFINITIONS: Record<JobId, JobDefinition> = {
  [JobId.WARRIOR]: {
    id: JobId.WARRIOR,
    name: 'Warrior',
    baseClass: BaseClass.WARRIOR,
    tier: 1,
    parentJob: null,
    description: 'A mighty fighter with high health and physical power.',
    modelFile: 'Adventurer.glb',
    baseStatModifiers: { STR: 3, STA: 2 },
    lpBase: 98, lpPerLevel: 5.847, lpPerSta: 15.5,
    mpBase: 16, mpPerLevel: 44.55, mpPerSpi: 48.3
  },
  [JobId.GLADIATOR]: {
    id: JobId.GLADIATOR,
    name: 'Gladiator',
    baseClass: BaseClass.WARRIOR,
    tier: 2,
    parentJob: JobId.WARRIOR,
    description: 'An offensive warrior specializing in two-handed weapons and raw damage.',
    modelFile: 'Adventurer.glb',
    baseStatModifiers: { STR: 4, STA: 2, DEX: 1 },
    lpBase: 148, lpPerLevel: 3.188, lpPerSta: 8.465,
    mpBase: 28, mpPerLevel: 36.7, mpPerSpi: 39.5
  },
  [JobId.JUGGERNAUT]: {
    id: JobId.JUGGERNAUT,
    name: 'Juggernaut',
    baseClass: BaseClass.WARRIOR,
    tier: 3,
    parentJob: JobId.GLADIATOR,
    description: 'An unstoppable force of destruction with devastating power.',
    modelFile: 'Adventurer.glb',
    baseStatModifiers: { STR: 6, STA: 3, DEX: 2 },
    lpBase: 298, lpPerLevel: 1.9601, lpPerSta: 2.2836,
    mpBase: 98, mpPerLevel: 32.2, mpPerSpi: 34.8
  },
  [JobId.DRAGOON]: {
    id: JobId.DRAGOON,
    name: 'Dragoon',
    baseClass: BaseClass.WARRIOR,
    tier: 3,
    parentJob: JobId.GLADIATOR,
    description: 'A lance-wielding warrior with superior mounted combat abilities.',
    modelFile: 'Adventurer.glb',
    baseStatModifiers: { STR: 5, STA: 3, AGI: 2 },
    lpBase: 149, lpPerLevel: 2.0033, lpPerSta: 3.572,
    mpBase: 98, mpPerLevel: 30.9, mpPerSpi: 33.3
  },
  [JobId.KNIGHT]: {
    id: JobId.KNIGHT,
    name: 'Knight',
    baseClass: BaseClass.WARRIOR,
    tier: 2,
    parentJob: JobId.WARRIOR,
    description: 'A defensive warrior specializing in shields and party protection.',
    modelFile: 'King.glb',
    baseStatModifiers: { STR: 2, STA: 4, SPI: 1 },
    lpBase: 149, lpPerLevel: 2.975, lpPerSta: 7.881,
    mpBase: 118, mpPerLevel: 29.15, mpPerSpi: 31.4
  },
  [JobId.WARLORD]: {
    id: JobId.WARLORD,
    name: 'Warlord',
    baseClass: BaseClass.WARRIOR,
    tier: 3,
    parentJob: JobId.KNIGHT,
    description: 'A commanding presence on the battlefield with supreme leadership abilities.',
    modelFile: 'King.glb',
    baseStatModifiers: { STR: 3, STA: 5, SPI: 3 },
    lpBase: 498, lpPerLevel: 1.1493, lpPerSta: 2.0618,
    mpBase: 179, mpPerLevel: 25.8, mpPerSpi: 20.589
  },
  [JobId.PALADIN]: {
    id: JobId.PALADIN,
    name: 'Paladin',
    baseClass: BaseClass.WARRIOR,
    tier: 3,
    parentJob: JobId.KNIGHT,
    description: 'A holy knight combining strong defense with healing abilities.',
    modelFile: 'King.glb',
    baseStatModifiers: { STR: 3, STA: 5, SPI: 3 },
    lpBase: 398, lpPerLevel: 1.4285, lpPerSta: 2.2322,
    mpBase: 178, mpPerLevel: 24.7, mpPerSpi: 19.94
  },
  [JobId.SCOUT]: {
    id: JobId.SCOUT,
    name: 'Scout',
    baseClass: BaseClass.SCOUT,
    tier: 1,
    parentJob: null,
    description: 'A swift hunter with ranged attacks and survival skills.',
    modelFile: 'Farmer.glb',
    baseStatModifiers: { AGI: 3, DEX: 2 },
    lpBase: 84, lpPerLevel: 7.23, lpPerSta: 19.2,
    mpBase: 44, mpPerLevel: 37.2, mpPerSpi: 40
  },
  [JobId.ARCHER]: {
    id: JobId.ARCHER,
    name: 'Archer',
    baseClass: BaseClass.SCOUT,
    tier: 2,
    parentJob: JobId.SCOUT,
    description: 'A ranged specialist with mastery of bows and crossbows.',
    modelFile: 'Farmer.glb',
    baseStatModifiers: { AGI: 4, DEX: 3, STR: 1 },
    lpBase: 109, lpPerLevel: 4.4, lpPerSta: 11.67,
    mpBase: 48, mpPerLevel: 31.2, mpPerSpi: 33.3
  },
  [JobId.SNIPER]: {
    id: JobId.SNIPER,
    name: 'Sniper',
    baseClass: BaseClass.SCOUT,
    tier: 3,
    parentJob: JobId.ARCHER,
    description: 'An elite marksman with devastating precision at extreme range.',
    modelFile: 'Farmer.glb',
    baseStatModifiers: { AGI: 5, DEX: 4, STR: 2 },
    lpBase: 198, lpPerLevel: 3.333, lpPerSta: 3.803,
    mpBase: 69, mpPerLevel: 21.95, mpPerSpi: 20.146
  },
  [JobId.HUNTER]: {
    id: JobId.HUNTER,
    name: 'Hunter',
    baseClass: BaseClass.SCOUT,
    tier: 3,
    parentJob: JobId.ARCHER,
    description: 'A skilled tracker with traps and survival expertise.',
    modelFile: 'Farmer.glb',
    baseStatModifiers: { AGI: 5, DEX: 3, STR: 2 },
    lpBase: 151, lpPerLevel: 3.111, lpPerSta: 4.464,
    mpBase: 56, mpPerLevel: 22.6, mpPerSpi: 19.7
  },
  [JobId.PROVOCATEUR]: {
    id: JobId.PROVOCATEUR,
    name: 'Provocateur',
    baseClass: BaseClass.SCOUT,
    tier: 2,
    parentJob: JobId.SCOUT,
    description: 'A cunning agent specializing in stealth and subterfuge.',
    modelFile: 'Punk.glb',
    baseStatModifiers: { AGI: 5, DEX: 2 },
    lpBase: 109, lpPerLevel: 4.007, lpPerSta: 10.63,
    mpBase: 48, mpPerLevel: 33.1, mpPerSpi: 35.97
  },
  [JobId.ASSASSIN]: {
    id: JobId.ASSASSIN,
    name: 'Assassin',
    baseClass: BaseClass.SCOUT,
    tier: 3,
    parentJob: JobId.PROVOCATEUR,
    description: 'A deadly shadow operative with lethal critical hits.',
    modelFile: 'Punk.glb',
    baseStatModifiers: { AGI: 7, DEX: 3, STR: 2 },
    lpBase: 149, lpPerLevel: 2.123, lpPerSta: 3.922,
    mpBase: 53, mpPerLevel: 24.44, mpPerSpi: 20.58
  },
  [JobId.SABOTEUR]: {
    id: JobId.SABOTEUR,
    name: 'Saboteur',
    baseClass: BaseClass.SCOUT,
    tier: 3,
    parentJob: JobId.PROVOCATEUR,
    description: 'A master of traps and disruption tactics.',
    modelFile: 'Punk.glb',
    baseStatModifiers: { AGI: 5, DEX: 3, INT: 3 },
    lpBase: 205, lpPerLevel: 2.53, lpPerSta: 3.773,
    mpBase: 59, mpPerLevel: 22.6, mpPerSpi: 17.92
  },
  [JobId.ACOLYTE]: {
    id: JobId.ACOLYTE,
    name: 'Acolyte',
    baseClass: BaseClass.ACOLYTE,
    tier: 1,
    parentJob: null,
    description: 'A devout healer with holy magic and support abilities.',
    modelFile: 'Beach Character.glb',
    baseStatModifiers: { SPI: 3, INT: 2 },
    lpBase: 73, lpPerLevel: 8.16, lpPerSta: 21.51,
    mpBase: 58, mpPerLevel: 18.06, mpPerSpi: 19.48
  },
  [JobId.PRIEST]: {
    id: JobId.PRIEST,
    name: 'Priest',
    baseClass: BaseClass.ACOLYTE,
    tier: 2,
    parentJob: JobId.ACOLYTE,
    description: 'A holy healer with powerful restoration and blessing magic.',
    modelFile: 'Beach Character.glb',
    baseStatModifiers: { SPI: 5, INT: 3 },
    lpBase: 88, lpPerLevel: 4.475, lpPerSta: 11.874,
    mpBase: 198, mpPerLevel: 14, mpPerSpi: 15.08
  },
  [JobId.CLERIC]: {
    id: JobId.CLERIC,
    name: 'Cleric',
    baseClass: BaseClass.ACOLYTE,
    tier: 3,
    parentJob: JobId.PRIEST,
    description: 'A supreme healer with divine resurrection and protection magic.',
    modelFile: 'Beach Character.glb',
    baseStatModifiers: { SPI: 7, INT: 5 },
    lpBase: 199, lpPerLevel: 2.75, lpPerSta: 3.745,
    mpBase: 235, mpPerLevel: 8.875, mpPerSpi: 9.897
  },
  [JobId.ENCHANTER]: {
    id: JobId.ENCHANTER,
    name: 'Enchanter',
    baseClass: BaseClass.ACOLYTE,
    tier: 3,
    parentJob: JobId.PRIEST,
    description: 'A mystic who strengthens allies with powerful support enchantments.',
    modelFile: 'Beach Character.glb',
    baseStatModifiers: { SPI: 5, INT: 4, DEX: 2 },
    lpBase: 197, lpPerLevel: 3.33, lpPerSta: 3.745,
    mpBase: 253, mpPerLevel: 8.24, mpPerSpi: 8.861
  },
  [JobId.ASCETIC]: {
    id: JobId.ASCETIC,
    name: 'Ascetic',
    baseClass: BaseClass.ACOLYTE,
    tier: 2,
    parentJob: JobId.ACOLYTE,
    description: 'A martial artist combining physical power with spiritual energy.',
    modelFile: 'Beach Character.glb',
    baseStatModifiers: { SPI: 3, STR: 3, AGI: 2 },
    lpBase: 89, lpPerLevel: 3.883, lpPerSta: 10.298,
    mpBase: 163, mpPerLevel: 16.72, mpPerSpi: 18
  },
  [JobId.MONK]: {
    id: JobId.MONK,
    name: 'Monk',
    baseClass: BaseClass.ACOLYTE,
    tier: 3,
    parentJob: JobId.ASCETIC,
    description: 'An ascetic warrior with devastating chi-enhanced strikes.',
    modelFile: 'Beach Character.glb',
    baseStatModifiers: { SPI: 4, STR: 5, AGI: 3 },
    lpBase: 299, lpPerLevel: 1.961, lpPerSta: 2.681,
    mpBase: 189, mpPerLevel: 12.9, mpPerSpi: 14
  },
  [JobId.EXORCIST]: {
    id: JobId.EXORCIST,
    name: 'Exorcist',
    baseClass: BaseClass.ACOLYTE,
    tier: 3,
    parentJob: JobId.ASCETIC,
    description: 'A spiritual warrior who purifies evil with sacred combat arts.',
    modelFile: 'Beach Character.glb',
    baseStatModifiers: { SPI: 5, INT: 4, STR: 3 },
    lpBase: 203, lpPerLevel: 2.578, lpPerSta: 3.83,
    mpBase: 197, mpPerLevel: 8.5, mpPerSpi: 9.16
  },
  [JobId.MAGE]: {
    id: JobId.MAGE,
    name: 'Mage',
    baseClass: BaseClass.MAGE,
    tier: 1,
    parentJob: null,
    description: 'A powerful spellcaster with devastating magical abilities.',
    modelFile: 'Witch.glb',
    baseStatModifiers: { INT: 3, SPI: 2 },
    lpBase: 59, lpPerLevel: 8.44, lpPerSta: 22.48,
    mpBase: 89, mpPerLevel: 17.6, mpPerSpi: 18.9
  },
  [JobId.WIZARD]: {
    id: JobId.WIZARD,
    name: 'Wizard',
    baseClass: BaseClass.MAGE,
    tier: 2,
    parentJob: JobId.MAGE,
    description: 'A master of elemental magic with devastating area spells.',
    modelFile: 'Witch.glb',
    baseStatModifiers: { INT: 5, SPI: 3 },
    lpBase: 73, lpPerLevel: 5.753, lpPerSta: 15.28,
    mpBase: 253, mpPerLevel: 10.57, mpPerSpi: 11.41
  },
  [JobId.WARLOCK]: {
    id: JobId.WARLOCK,
    name: 'Warlock',
    baseClass: BaseClass.MAGE,
    tier: 3,
    parentJob: JobId.WIZARD,
    description: 'An arcane supreme with mastery over all elements.',
    modelFile: 'Witch.glb',
    baseStatModifiers: { INT: 7, SPI: 5 },
    lpBase: 148, lpPerLevel: 4.006, lpPerSta: 5.405,
    mpBase: 254, mpPerLevel: 5.915, mpPerSpi: 6.366
  },
  [JobId.CONJURER]: {
    id: JobId.CONJURER,
    name: 'Conjurer',
    baseClass: BaseClass.MAGE,
    tier: 3,
    parentJob: JobId.WIZARD,
    description: 'A wise scholar combining magic with support summoning.',
    modelFile: 'Witch.glb',
    baseStatModifiers: { INT: 6, SPI: 6, DEX: 2 },
    lpBase: 142, lpPerLevel: 3.756, lpPerSta: 4.95,
    mpBase: 254, mpPerLevel: 7.45, mpPerSpi: 8.016
  },
  [JobId.SORCERER]: {
    id: JobId.SORCERER,
    name: 'Sorcerer',
    baseClass: BaseClass.MAGE,
    tier: 2,
    parentJob: JobId.MAGE,
    description: 'A dark caster wielding forbidden arcane powers.',
    modelFile: 'Witch.glb',
    baseStatModifiers: { INT: 4, SPI: 2, AGI: 2 },
    lpBase: 73, lpPerLevel: 4.86, lpPerSta: 12.88,
    mpBase: 119, mpPerLevel: 12.63, mpPerSpi: 13.63
  },
  [JobId.CORRUPTOR]: {
    id: JobId.CORRUPTOR,
    name: 'Corruptor',
    baseClass: BaseClass.MAGE,
    tier: 3,
    parentJob: JobId.SORCERER,
    description: 'A dark summoner who corrupts and weakens enemies.',
    modelFile: 'Witch.glb',
    baseStatModifiers: { INT: 6, SPI: 4, AGI: 2 },
    lpBase: 166, lpPerLevel: 3.53, lpPerSta: 4.84,
    mpBase: 203, mpPerLevel: 9.4, mpPerSpi: 12.3
  },
  [JobId.SHADOWBLADE]: {
    id: JobId.SHADOWBLADE,
    name: 'Shadowblade',
    baseClass: BaseClass.MAGE,
    tier: 3,
    parentJob: JobId.SORCERER,
    description: 'A hybrid of shadow magic and blade arts.',
    modelFile: 'Punk.glb',
    baseStatModifiers: { INT: 5, AGI: 3, DEX: 3 },
    lpBase: 151, lpPerLevel: 3.339, lpPerSta: 5.26,
    mpBase: 195, mpPerLevel: 11.23, mpPerSpi: 10.14
  },
};
