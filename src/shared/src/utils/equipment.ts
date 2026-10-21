/**
 * Visible-equipment summary for the wire: slot name → item id (or null).
 * Carried on player spawn (ENTITY_SPAWN / WORLD_STATE) and on the
 * ENTITY_EQUIPMENT broadcast so every client can render other players'
 * armor and weapons.
 */
export function equipmentSummary(
  equipment: Record<string, any> | null | undefined
): Record<string, string | null> {
  const out: Record<string, string | null> = {};
  for (const slot of ['helmet', 'armor', 'gloves', 'legs', 'boots', 'back', 'weapon', 'shield']) {
    out[slot] = equipment?.[slot]?.itemId || null;
  }
  return out;
}
