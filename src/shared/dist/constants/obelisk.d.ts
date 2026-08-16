/**
 * Obelisk weapon buff.
 *
 * While an Obelisk weapon (`ItemDefinition.obeliskBuff === true`) is equipped,
 * the wielder gains two enhancement-level-scaled effects:
 *   - `resistIgnore`: flat magic-resistance points ignored on the wielder's own
 *     magic attacks (subtracted from the target's effective elemental resist,
 *     floored at 0 — penetration, not amplification).
 *   - `damageReduction`: flat percent reduction to ALL incoming damage
 *     (physical + magical) applied to what reaches HP.
 *
 * The buff is inactive at +0; the table starts at +1. Mutually exclusive with
 * the Guardian skill (BUFF_DAMAGE_REDIRECT).
 */
export interface ObeliskBuffValues {
    /** Magic-resistance points ignored on the wielder's magic attacks. */
    resistIgnore: number;
    /** Percent reduction to incoming physical + magical damage (0-100). */
    damageReduction: number;
}
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
export declare const OBELISK_BUFF_TABLE: ReadonlyArray<{
    minLevel: number;
} & ObeliskBuffValues>;
/**
 * Returns the Obelisk buff values for a given enhancement level, or `null` if
 * the weapon is unenhanced (+0) / below the first tier. Levels above 10 clamp
 * to the top tier.
 */
export declare function getObeliskBuffValues(enhancementLevel: number): ObeliskBuffValues | null;
