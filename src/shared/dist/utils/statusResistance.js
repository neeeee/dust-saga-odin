"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.computeResist = computeResist;
exports.computeAilmentResist = computeAilmentResist;
exports.computeDisorderResist = computeDisorderResist;
exports.computeDebuffAccuracy = computeDebuffAccuracy;
exports.rollDebuffApplication = rollDebuffApplication;
const DISORDER_CATEGORIES = new Set(['disorder', 'freeze', 'burn', 'curse', 'sleep', 'weakness', 'weaken']);
function computeResist(totalStat, divisor, perStep, gearBonus = 0) {
    return Math.floor(totalStat / divisor) * perStep + gearBonus;
}
function computeAilmentResist(totalSTA, gearBonus = 0) {
    return computeResist(totalSTA, 28, 7, gearBonus);
}
function computeDisorderResist(totalSPI, gearBonus = 0) {
    return computeResist(totalSPI, 28, 7, gearBonus);
}
function computeDebuffAccuracy(casterSPI, proficiencyAdeptness, category) {
    const BASE_HIT_CHANCE = 20;
    const SPI_BONUS_PER_POINT = 0.30;
    const PROFICIENCY_BONUS_PER_POINT = DISORDER_CATEGORIES.has(category) ? 0.5 : 0.3;
    const accuracy = BASE_HIT_CHANCE + casterSPI * SPI_BONUS_PER_POINT + proficiencyAdeptness * PROFICIENCY_BONUS_PER_POINT;
    return Math.min(95, accuracy);
}
function rollDebuffApplication(accuracy, resistPercent) {
    const finalChance = Math.max(0, accuracy - resistPercent);
    const roll = Math.random() * 100;
    return { applied: roll < finalChance, roll };
}
