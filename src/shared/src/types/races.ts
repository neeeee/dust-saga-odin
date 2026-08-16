export enum Race {
  HUMAN = 'human',
  ELF = 'elf',
  DWARF = 'dwarf',
  MYRINE = 'myrine',
  ENKIDU = 'enkidu',
  LAPIN = 'lapin'
}

export enum RacialPassiveId {
  HUMAN_FIGHTING_SPIRIT = 'human_fighting_spirit',
  HUMAN_ADAPTABILITY = 'human_adaptability',
  HUMAN_BREWER = 'human_brewer',
  ELF_HAWKEYE = 'elf_hawkeye',
  ELF_NATURES_HARMONY = 'elf_natures_harmony',
  ELF_STEADFASTNESS = 'elf_steadfastness',
  DWARF_STRONGHEARTED = 'dwarf_stronghearted',
  DWARF_SPIRIT = 'dwarf_spirit',
  DWARF_FILIAL_PIETY = 'dwarf_filial_piety',
  MYRINE_ACUTE_SENSES = 'myrine_acute_senses',
  MYRINE_SHARPNESS = 'myrine_sharpness',
  MYRINE_CALMNESS = 'myrine_calmness',
  ENKIDU_STONE_SKIN = 'enkidu_stone_skin',
  ENKIDU_STRONG_ARM = 'enkidu_strong_arm',
  ENKIDU_LAPIN_SUPPORT = 'enkidu_lapin_support',
  LAPIN_MAGIC_RESISTANCE = 'lapin_magic_resistance',
  LAPIN_INNER_LIGHT = 'lapin_inner_light',
  LAPIN_ENKIDU_SUPPORT = 'lapin_enkidu_support',
}

export interface RacialPassiveChoice {
  id: RacialPassiveId;
  name: string;
  description: string;
}

export interface RaceData {
  id: Race;
  name: string;
  description: string;
  baseStats: Record<StatType, number>;
  passiveChoices: RacialPassiveChoice[];
}

export enum StatType {
  STA = 'STA',
  STR = 'STR',
  AGI = 'AGI',
  DEX = 'DEX',
  SPI = 'SPI',
  INT = 'INT'
}

export const STAT_TYPES: StatType[] = [
  StatType.STA,
  StatType.STR,
  StatType.AGI,
  StatType.DEX,
  StatType.SPI,
  StatType.INT
];

export interface StatPoints {
  STA: number;
  STR: number;
  AGI: number;
  DEX: number;
  SPI: number;
  INT: number;
}

export function createDefaultStatPoints(): StatPoints {
  return { STA: 0, STR: 0, AGI: 0, DEX: 0, SPI: 0, INT: 0 };
}
