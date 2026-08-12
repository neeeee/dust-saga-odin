import { getObeliskBuffValues, type InventoryItem, type ObeliskBuffValues } from '@dust-saga/shared';
import type { ItemSystem } from '../../systems/ItemSystem';

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
export function getObeliskBuffForWeapon(
  itemSys: ItemSystem,
  weapon: InventoryItem | null | undefined,
): ObeliskBuffValues | null {
  if (!weapon) return null;
  const def = itemSys.getItemDefinition(weapon.itemId);
  if (!def?.obeliskBuff) return null;
  return getObeliskBuffValues(weapon.enhancementLevel ?? 0);
}
