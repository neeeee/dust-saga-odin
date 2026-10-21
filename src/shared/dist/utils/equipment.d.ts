/**
 * Visible-equipment summary for the wire: slot name → item id (or null).
 * Carried on player spawn (ENTITY_SPAWN / WORLD_STATE) and on the
 * ENTITY_EQUIPMENT broadcast so every client can render other players'
 * armor and weapons.
 */
export declare function equipmentSummary(equipment: Record<string, any> | null | undefined): Record<string, string | null>;
