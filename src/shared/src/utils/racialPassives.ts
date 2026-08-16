import { RacialPassiveId } from '../types/races';
import { PlayerSession } from '../types/player';

export function applyRacialCritChance(passiveId: string | undefined, baseCritChance: number): number {
  if (passiveId === RacialPassiveId.MYRINE_ACUTE_SENSES) return baseCritChance + 0.05;
  return baseCritChance;
}

export function applyRacialDodgeChance(passiveId: string | undefined): number {
  if (passiveId === RacialPassiveId.MYRINE_SHARPNESS) return 0.05;
  return 0;
}

export function applyRacialIncomingDamage(passiveId: string | undefined, damage: number, damageType: 'physical' | 'magical'): number {
  if (damageType === 'physical' && passiveId === RacialPassiveId.ENKIDU_STONE_SKIN) {
    return Math.max(1, Math.floor(damage * 0.9));
  }
  if (damageType === 'magical' && passiveId === RacialPassiveId.LAPIN_MAGIC_RESISTANCE) {
    return Math.max(1, Math.floor(damage * 0.9));
  }
  return Math.max(1, damage);
}

export function applyRacialOutgoingDamage(passiveId: string | undefined, damage: number, weaponType?: string): number {
  if (!passiveId) return damage;
  if ((weaponType === 'axe' || weaponType === 'blunt') && passiveId === RacialPassiveId.DWARF_SPIRIT) {
    return Math.floor(damage * 1.1);
  }
  if (weaponType === 'twohand' && passiveId === RacialPassiveId.ENKIDU_STRONG_ARM) {
    return Math.floor(damage * 1.1);
  }
  return damage;
}

export function applyRacialPotionHealing(passiveId: string | undefined, baseHeal: number): number {
  if (passiveId === RacialPassiveId.HUMAN_BREWER) {
    return Math.floor(baseHeal * 1.15);
  }
  return baseHeal;
}

export function applyRacialMpCost(passiveId: string | undefined, baseMpCost: number): number {
  if (passiveId === RacialPassiveId.ELF_NATURES_HARMONY) {
    return Math.max(1, Math.floor(baseMpCost * 0.85));
  }
  return baseMpCost;
}

export function applyRacialAilmentDuration(passiveId: string | undefined, baseDurationMs: number): number {
  if (passiveId === RacialPassiveId.HUMAN_ADAPTABILITY) {
    return Math.max(0, Math.floor(baseDurationMs * 0.5));
  }
  return baseDurationMs;
}

export function checkSurviveFatal(passiveId: string | undefined): boolean {
  if (passiveId === RacialPassiveId.DWARF_FILIAL_PIETY) {
    return Math.random() < 0.03;
  }
  return false;
}

export function checkDamageToMpConversion(passiveId: string | undefined): boolean {
  if (passiveId === RacialPassiveId.MYRINE_CALMNESS) {
    return Math.random() < 0.05;
  }
  return false;
}

export function checkFatalDamageForParty(passiveId: string | undefined): boolean {
  if (passiveId === RacialPassiveId.DWARF_STRONGHEARTED) {
    return Math.random() < 0.01;
  }
  return false;
}

export function processRacialOnDamage(
  target: PlayerSession,
  incomingDamage: number,
  damageType: 'physical' | 'magical'
): { finalDamage: number; survivedFatal: boolean; mpConverted: number } {
  const passiveId = target.racialPassive;
  let finalDamage = applyRacialIncomingDamage(passiveId, incomingDamage, damageType);
  let survivedFatal = false;
  let mpConverted = 0;

  if (checkDamageToMpConversion(passiveId)) {
    mpConverted = Math.floor(finalDamage * 0.3);
    target.stats.mana = Math.min(target.stats.maxMana, target.stats.mana + mpConverted);
  }

  if (finalDamage >= target.stats.health && checkSurviveFatal(passiveId)) {
    finalDamage = target.stats.health - 1;
    survivedFatal = true;
  }

  return { finalDamage, survivedFatal, mpConverted };
}

export function getRangedRangeBonus(passiveId: string | undefined): number {
  if (passiveId === RacialPassiveId.ELF_HAWKEYE) return 3;
  return 0;
}

export function getCharmResist(passiveId: string | undefined): number {
  if (passiveId === RacialPassiveId.ELF_STEADFASTNESS) return 20;
  return 0;
}

export function getMpRegenBonus(passiveId: string | undefined): number {
  if (passiveId === RacialPassiveId.LAPIN_INNER_LIGHT) return 0.15;
  return 0;
}

export function getMeleeSkillBonus(passiveId: string | undefined): number {
  if (passiveId === RacialPassiveId.HUMAN_FIGHTING_SPIRIT) return 10;
  return 0;
}

export function hasLapinSupport(passiveId: string | undefined): boolean {
  return passiveId === RacialPassiveId.ENKIDU_LAPIN_SUPPORT;
}

export function hasEnkiduSupport(passiveId: string | undefined): boolean {
  return passiveId === RacialPassiveId.LAPIN_ENKIDU_SUPPORT;
}
