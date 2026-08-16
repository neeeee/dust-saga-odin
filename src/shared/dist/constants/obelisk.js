"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.OBELISK_BUFF_TABLE = void 0;
exports.getObeliskBuffValues = getObeliskBuffValues;
/**
 * Enhancement-level → effect table. Indexed by the minimum level that grants
 * the tier; `getObeliskBuffValues` clamps to the highest applicable tier.
 *   +1-4 → 5 / 0
 *   +5   → 10 / 0
 *   +6   → 15 / 10
 *   +7   → 17 / 15
 *   +8   → 18 / 20
 *   +9   → 19 / 25
 *   +10  → 20 / 30
 */
exports.OBELISK_BUFF_TABLE = [
    { minLevel: 1, resistIgnore: 5, damageReduction: 0 },
    { minLevel: 5, resistIgnore: 10, damageReduction: 0 },
    { minLevel: 6, resistIgnore: 15, damageReduction: 10 },
    { minLevel: 7, resistIgnore: 17, damageReduction: 15 },
    { minLevel: 8, resistIgnore: 18, damageReduction: 20 },
    { minLevel: 9, resistIgnore: 19, damageReduction: 25 },
    { minLevel: 10, resistIgnore: 20, damageReduction: 30 },
];
/**
 * Returns the Obelisk buff values for a given enhancement level, or `null` if
 * the weapon is unenhanced (+0) / below the first tier. Levels above 10 clamp
 * to the top tier.
 */
function getObeliskBuffValues(enhancementLevel) {
    if (enhancementLevel < 1)
        return null;
    const clamped = Math.min(enhancementLevel, 10);
    let values = null;
    for (const tier of exports.OBELISK_BUFF_TABLE) {
        if (clamped >= tier.minLevel) {
            values = { resistIgnore: tier.resistIgnore, damageReduction: tier.damageReduction };
        }
    }
    return values;
}
