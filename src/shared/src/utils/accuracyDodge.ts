const AGI_BREAKPOINT_TABLE: Array<{ minAgi: number; bonus: number }> = [
  { minAgi: 140, bonus: 98 },
  { minAgi: 130, bonus: 85 },
  { minAgi: 120, bonus: 72 },
  { minAgi: 110, bonus: 61 },
  { minAgi: 100, bonus: 50 },
  { minAgi: 90, bonus: 41 },
  { minAgi: 80, bonus: 32 },
  { minAgi: 70, bonus: 25 },
  { minAgi: 60, bonus: 18 },
  { minAgi: 50, bonus: 13 },
  { minAgi: 40, bonus: 8 },
  { minAgi: 30, bonus: 5 },
  { minAgi: 20, bonus: 2 },
  { minAgi: 10, bonus: 1 },
];

export function getDodgeAgiBonus(totalAgi: number): number {
  for (const entry of AGI_BREAKPOINT_TABLE) {
    if (totalAgi >= entry.minAgi) return entry.bonus;
  }
  return 0;
}

export function calculateDodge(level: number, totalAgi: number, dodgeBonus: number): number {
  return level + totalAgi + getDodgeAgiBonus(totalAgi) + dodgeBonus;
}

export function calculateAccuracy(level: number, totalDex: number, accuracyBonus: number): number {
  return level + totalDex + accuracyBonus;
}

export function calculateHitChance(attackerAccuracy: number, defenderDodge: number): number {
  if (attackerAccuracy + defenderDodge * 0.6 === 0) return 1;
  return attackerAccuracy / (attackerAccuracy + defenderDodge * 0.6);
}
