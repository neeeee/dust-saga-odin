import { Race, RaceData, RacialPassiveId } from '../types/races';

export const RACE_DATA: Record<Race, RaceData> = {
  [Race.HUMAN]: {
    id: Race.HUMAN,
    name: 'Human',
    description: 'Versatile and adaptable. Well-rounded in all disciplines.',
    baseStats: { STA: 5, STR: 5, AGI: 5, DEX: 5, SPI: 5, INT: 5 },
    passiveChoices: [
      { id: RacialPassiveId.HUMAN_FIGHTING_SPIRIT, name: 'Fighting Spirit', description: '+10 melee skill (1H)' },
      { id: RacialPassiveId.HUMAN_ADAPTABILITY, name: 'Adaptability', description: 'Ailment duration -50%' },
      { id: RacialPassiveId.HUMAN_BREWER, name: 'Brewer', description: 'Potion effectiveness +15%' },
    ]
  },
  [Race.ELF]: {
    id: Race.ELF,
    name: 'Elf',
    description: 'Graceful and magical. Natural affinity for ranged combat and spellcraft.',
    baseStats: { STA: 3, STR: 3, AGI: 6, DEX: 4, SPI: 7, INT: 7 },
    passiveChoices: [
      { id: RacialPassiveId.ELF_HAWKEYE, name: 'Hawkeye', description: '+3 ranged range' },
      { id: RacialPassiveId.ELF_NATURES_HARMONY, name: "Nature's Harmony", description: 'Spell MP cost -15%' },
      { id: RacialPassiveId.ELF_STEADFASTNESS, name: 'Steadfastness', description: 'Charm resistance +20' },
    ]
  },
  [Race.DWARF]: {
    id: Race.DWARF,
    name: 'Dwarf',
    description: 'Sturdy and resilient. Masters of heavy weapons and unwavering defense.',
    baseStats: { STA: 6, STR: 7, AGI: 5, DEX: 6, SPI: 3, INT: 3 },
    passiveChoices: [
      { id: RacialPassiveId.DWARF_STRONGHEARTED, name: 'Stronghearted', description: '1% chance take fatal damage for party member' },
      { id: RacialPassiveId.DWARF_SPIRIT, name: 'Dwarf Spirit', description: 'Axe/blunt damage +10%' },
      { id: RacialPassiveId.DWARF_FILIAL_PIETY, name: 'Filial Piety', description: '3% survive fatal with 1HP' },
    ]
  },
  [Race.MYRINE]: {
    id: Race.MYRINE,
    name: 'Myrine',
    description: 'Quick and elusive. Gifted with heightened reflexes and evasion.',
    baseStats: { STA: 5, STR: 5, AGI: 9, DEX: 6, SPI: 3, INT: 2 },
    passiveChoices: [
      { id: RacialPassiveId.MYRINE_ACUTE_SENSES, name: 'Acute Senses', description: 'Crit chance +5%' },
      { id: RacialPassiveId.MYRINE_SHARPNESS, name: 'Sharpness', description: '5% dodge' },
      { id: RacialPassiveId.MYRINE_CALMNESS, name: 'Calmness', description: 'Chance convert damage to MP' },
    ]
  },
  [Race.ENKIDU]: {
    id: Race.ENKIDU,
    name: 'Enkidu',
    description: 'Powerful and tough. A beast-like race with immense physical presence.',
    baseStats: { STA: 8, STR: 6, AGI: 4, DEX: 4, SPI: 6, INT: 2 },
    passiveChoices: [
      { id: RacialPassiveId.ENKIDU_STONE_SKIN, name: 'Stone Skin', description: 'Physical damage taken -10%' },
      { id: RacialPassiveId.ENKIDU_STRONG_ARM, name: 'Strong Arm', description: '2H weapon damage +10%' },
      { id: RacialPassiveId.ENKIDU_LAPIN_SUPPORT, name: 'Lapin Support', description: 'Boost Lapin party members\' physical defense' },
    ]
  },
  [Race.LAPIN]: {
    id: Race.LAPIN,
    name: 'Lapin',
    description: 'Gentle and magically attuned. A rabbit-like race with strong mystical affinity.',
    baseStats: { STA: 3, STR: 1, AGI: 6, DEX: 5, SPI: 9, INT: 6 },
    passiveChoices: [
      { id: RacialPassiveId.LAPIN_MAGIC_RESISTANCE, name: 'Magic Resistance', description: 'Magic resistance +10%' },
      { id: RacialPassiveId.LAPIN_INNER_LIGHT, name: 'Inner Light', description: 'MP regen +15%' },
      { id: RacialPassiveId.LAPIN_ENKIDU_SUPPORT, name: 'Enkidu Support', description: 'Boost Enkidu party members\' magic defense' },
    ]
  }
};

export function getRaceData(race: Race): RaceData {
  return RACE_DATA[race];
}

export const LEVEL_UP_BONUSES: Record<number, [number, number, number]> = {
  2: [6, 1, 0], 3: [6, 1, 0], 4: [6, 1, 0], 5: [6, 1, 0],
  6: [6, 1, 0], 7: [6, 1, 0], 8: [6, 1, 0], 9: [6, 1, 0],
  10: [8, 1, 0], 11: [8, 2, 0], 12: [8, 2, 0], 13: [8, 2, 0],
  14: [8, 2, 0], 15: [8, 2, 0], 16: [8, 2, 0], 17: [8, 2, 0],
  18: [8, 2, 0], 19: [8, 2, 0], 20: [10, 2, 0], 21: [10, 3, 0],
  22: [10, 3, 0], 23: [10, 3, 0], 24: [10, 3, 0], 25: [10, 3, 0],
  26: [10, 3, 0], 27: [10, 3, 0], 28: [10, 3, 0], 29: [10, 3, 0],
  30: [12, 3, 0], 31: [12, 3, 0], 32: [12, 3, 0], 33: [12, 3, 0],
  34: [12, 3, 0], 35: [12, 3, 0], 36: [12, 3, 0], 37: [12, 3, 0],
  38: [12, 3, 0], 39: [12, 3, 0], 40: [14, 3, 0], 41: [14, 3, 0],
  42: [14, 3, 0], 43: [14, 3, 0], 44: [14, 3, 0], 45: [14, 3, 0],
  46: [14, 3, 0], 47: [14, 3, 0], 48: [14, 3, 0], 49: [14, 3, 0],
  50: [16, 3, 0], 51: [8, 3, 0], 52: [8, 3, 0], 53: [8, 3, 0],
  54: [8, 3, 0], 55: [8, 3, 0], 56: [2, 2, 0], 57: [2, 2, 0],
  58: [2, 2, 0], 59: [2, 2, 0], 60: [2, 2, 0],
};

export function getLevelUpBonuses(level: number): [number, number, number] {
  return LEVEL_UP_BONUSES[level] || [2, 1, 0];
}

export const STAT_POINT_COSTS: Record<number, [number, number]> = {};
for (let i = 1; i <= 30; i++) STAT_POINT_COSTS[i] = [2, 1];
for (let i = 31; i <= 50; i++) STAT_POINT_COSTS[i] = [3, 1];
for (let i = 51; i <= 70; i++) STAT_POINT_COSTS[i] = [4, 1];
for (let i = 71; i <= 90; i++) STAT_POINT_COSTS[i] = [5, 1];
for (let i = 91; i <= 99; i++) STAT_POINT_COSTS[i] = [6, 1];

export function getStatPointCost(currentValue: number): [number, number] {
  return STAT_POINT_COSTS[currentValue + 1] || [6, 1];
}

export const MAX_LEVEL = 60;
export const MAX_STAT_VALUE = 99;

export const JOB_BASE_STAT_MODIFIERS: Record<number, Record<string, number>> = {
  0: { STA: 2, STR: 3, AGI: -1, DEX: 1, SPI: -1, INT: 0 },
  1: { STA: 0, STR: 2, AGI: 1, DEX: 2, SPI: -1, INT: 0 },
  2: { STA: 0, STR: 2, AGI: -1, DEX: 0, SPI: 1, INT: 2 },
  3: { STA: -1, STR: 1, AGI: -1, DEX: 1, SPI: 1, INT: 3 },
};

export function getJobBaseStatModifier(baseClass: number): Record<string, number> {
  return JOB_BASE_STAT_MODIFIERS[baseClass] || JOB_BASE_STAT_MODIFIERS[0];
}
