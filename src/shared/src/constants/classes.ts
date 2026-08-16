import { JobId, BaseClass, JOB_DEFINITIONS, JobDefinition } from '../types/jobs';
import { Race, StatType, StatPoints, createDefaultStatPoints } from '../types/races';
import { RACE_DATA, MAX_LEVEL, MAX_STAT_VALUE, getLevelUpBonuses, getJobBaseStatModifier } from '../constants/races';

export { JobId, BaseClass, JOB_DEFINITIONS } from '../types/jobs';

const XP_TO_NEXT_LEVEL: Record<number, number> = {
  1: 18,
  2: 50,
  3: 126,
  4: 270,
  5: 506,
  6: 858,
  7: 1350,
  8: 2124,
  9: 3000,
  10: 4092,
  11: 5620,
  12: 6344,
  13: 10660,
  14: 12032,
  15: 15190,
  16: 18426,
  17: 22640,
  18: 27434,
  19: 32936,
  20: 45386,
  21: 59892,
  22: 76144,
  23: 94000,
  24: 114968,
  25: 137920,
  26: 163232,
  27: 190724,
  28: 220800,
  29: 253586,
  30: 288860,
  31: 458758,
  32: 571142,
  33: 697333,
  34: 829384,
  35: 977040,
  36: 1145500,
  37: 1327304,
  38: 1531818,
  39: 2000000,
  40: 4790225,
  41: 5365051,
  42: 6008858,
  43: 6729921,
  44: 7537511,
  45: 13306266,
  46: 15967519,
  47: 19161023,
  48: 22993228,
  49: 27591874,
  50: 55183748,
  51: 66220498,
  52: 79464597,
  53: 95357517,
  54: 114429020,
  55: 137314824,
  56: 164777789,
  57: 197733347,
  58: 237280016,
  59: 284736019,
};

export function getExperienceToNextLevel(level: number): number {
  if (level < 1) return 0;
  if (level >= 60) return Infinity;
  if (level in XP_TO_NEXT_LEVEL) return XP_TO_NEXT_LEVEL[level];
  return Math.floor(XP_TO_NEXT_LEVEL[54] * Math.pow(1.2, level - 54));
}

export function calculateMaxLP(job: JobDefinition, level: number, sta: number): number {
  const levelLPComponent = Math.ceil(level * (100 / job.lpPerLevel));
  const staMultiplier = Math.ceil(100 / job.lpPerSta);
  const staLPComponent = Math.ceil(sta * staMultiplier);
  return job.lpBase + levelLPComponent + staLPComponent;
}

export function calculateMaxMP(job: JobDefinition, level: number, spi: number): number {
  const levelMPComponent = Math.ceil(level * (100 / job.mpPerLevel));
  const spiMultiplier = Math.ceil(100 / job.mpPerSpi);
  const spiMPComponent = Math.ceil(spi * spiMultiplier);
  return job.mpBase + levelMPComponent + spiMPComponent;
}

export function calculateDerivedStats(
  race: Race,
  jobId: JobId,
  level: number,
  allocatedStats: StatPoints
): {
  maxHealth: number;
  maxMana: number;
  attack: number;
  defense: number;
  speed: number;
  magicAttack: number;
  critChance: number;
  baseStats: { STA: number; STR: number; AGI: number; DEX: number; SPI: number; INT: number };
} {
  const job = JOB_DEFINITIONS[jobId];
  const raceData = RACE_DATA[race];
  if (!job || !raceData) {
    return { maxHealth: 100, maxMana: 50, attack: 10, defense: 5, speed: 4, magicAttack: 8, critChance: 1, baseStats: { STA: 5, STR: 5, AGI: 5, DEX: 5, SPI: 5, INT: 5 } };
  }

  const baseClassId = job.baseClass === BaseClass.WARRIOR ? 0 : job.baseClass === BaseClass.SCOUT ? 1 : job.baseClass === BaseClass.ACOLYTE ? 2 : 3;
  const jobMod = getJobBaseStatModifier(baseClassId);

  const baseStats = {
    STA: raceData.baseStats.STA + (jobMod.STA || 0),
    STR: raceData.baseStats.STR + (jobMod.STR || 0),
    AGI: raceData.baseStats.AGI + (jobMod.AGI || 0),
    DEX: raceData.baseStats.DEX + (jobMod.DEX || 0),
    SPI: raceData.baseStats.SPI + (jobMod.SPI || 0),
    INT: raceData.baseStats.INT + (jobMod.INT || 0),
  };

  const totalSTA = baseStats.STA + allocatedStats.STA;
  const totalSTR = baseStats.STR + allocatedStats.STR;
  const totalAGI = baseStats.AGI + allocatedStats.AGI;
  const totalDEX = baseStats.DEX + allocatedStats.DEX;
  const totalSPI = baseStats.SPI + allocatedStats.SPI;
  const totalINT = baseStats.INT + allocatedStats.INT;

  const maxHealth = calculateMaxLP(job, level, totalSTA);
  const maxMana = calculateMaxMP(job, level, totalSPI);
  const attack = Math.floor(5 + totalSTR * 1.5 + totalDEX * 0.3);
  const defense = Math.floor(3 + totalSTA * 0.8 + totalSTR * 0.3);
  const speed = Math.floor(30 + totalAGI * 0.5);
  const magicAttack = Math.floor(5 + totalINT * 1.5 + totalSPI * 0.3);
  const critChance = 1 + Math.floor(totalDEX / 10);

  return { maxHealth, maxMana, attack, defense, speed, magicAttack, critChance, baseStats };
}

export function getStatPointsGainedAtLevel(level: number): number {
  if (level <= 1) return 0;
  return getLevelUpBonuses(level)[0];
}

export function getSkillPointsGainedAtLevel(level: number): number {
  if (level <= 1) return 0;
  return getLevelUpBonuses(level)[1];
}

export { MAX_LEVEL, MAX_STAT_VALUE, getExperienceToNextLevel as getExperienceToNext };
