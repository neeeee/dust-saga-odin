"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getObeliskBuffForWeapon = getObeliskBuffForWeapon;
const shared_1 = require("@dust-saga/shared");
/**
 * Resolves the active Obelisk buff values for an equipped weapon, or `null` if
 * the weapon is not an Obelisk weapon / is unenhanced. Used at the two damage
 * sites (attacker magic-damage calc, target damage-taken) and for the Guardian
 * mutual-exclusion check.
 *
 * Reads the weapon directly rather than maintaining a status effect — this
 * mirrors the existing `session.equipment.weapon` reads in the damage pipeline
 * and means enhancement-level changes take effect immediately with no
 * buff-lifecycle bookkeeping.
 */
function getObeliskBuffForWeapon(itemSys, weapon) {
    if (!weapon)
        return null;
    const def = itemSys.getItemDefinition(weapon.itemId);
    if (!def?.obeliskBuff)
        return null;
    return (0, shared_1.getObeliskBuffValues)(weapon.enhancementLevel ?? 0);
}
