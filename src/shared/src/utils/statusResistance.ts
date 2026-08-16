const DISORDER_CATEGORIES = new Set(['disorder', 'freeze', 'burn', 'curse', 'sleep', 'weakness', 'weaken']);

export function computeResist(totalStat: number, divisor: number, perStep: number, gearBonus: number = 0): number {
  return Math.floor(totalStat / divisor) * perStep + gearBonus;
}

export function computeAilmentResist(totalSTA: number, gearBonus: number = 0): number {
  return computeResist(totalSTA, 28, 7, gearBonus);
}

export function computeDisorderResist(totalSPI: number, gearBonus: number = 0): number {
  return computeResist(totalSPI, 28, 7, gearBonus);
}

export function computeDebuffAccuracy(
  casterSPI: number,
  proficiencyAdeptness: number,
  category: string
): number {
  const BASE_HIT_CHANCE = 20;
  const SPI_BONUS_PER_POINT = 0.30;
  const PROFICIENCY_BONUS_PER_POINT = DISORDER_CATEGORIES.has(category) ? 0.5 : 0.3;
  const accuracy = BASE_HIT_CHANCE + casterSPI * SPI_BONUS_PER_POINT + proficiencyAdeptness * PROFICIENCY_BONUS_PER_POINT;
  return Math.min(95, accuracy);
}

export function rollDebuffApplication(accuracy: number, resistPercent: number): { applied: boolean; roll: number } {
  const finalChance = Math.max(0, accuracy - resistPercent);
  const roll = Math.random() * 100;
  return { applied: roll < finalChance, roll };
}
