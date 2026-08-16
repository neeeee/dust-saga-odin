"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getDodgeAgiBonus = getDodgeAgiBonus;
exports.calculateDodge = calculateDodge;
exports.calculateAccuracy = calculateAccuracy;
exports.calculateHitChance = calculateHitChance;
const AGI_BREAKPOINT_TABLE = [
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
function getDodgeAgiBonus(totalAgi) {
    for (const entry of AGI_BREAKPOINT_TABLE) {
        if (totalAgi >= entry.minAgi)
            return entry.bonus;
    }
    return 0;
}
function calculateDodge(level, totalAgi, dodgeBonus) {
    return level + totalAgi + getDodgeAgiBonus(totalAgi) + dodgeBonus;
}
function calculateAccuracy(level, totalDex, accuracyBonus) {
    return level + totalDex + accuracyBonus;
}
function calculateHitChance(attackerAccuracy, defenderDodge) {
    if (attackerAccuracy + defenderDodge * 0.6 === 0)
        return 1;
    return attackerAccuracy / (attackerAccuracy + defenderDodge * 0.6);
}
