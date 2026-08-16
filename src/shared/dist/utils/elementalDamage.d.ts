import { StatusEffect } from '../types/status';
export interface ElementalDamageLine {
    element: string;
    damage: number;
}
/**
 * Caller resolves the weapon's base element/power from the item definition
 * (via ItemSystem) and passes it in directly, so this util stays free of any
 * data-source dependency and works equally for static or DB-backed items.
 */
export declare function calculateWeaponElementalDamage(weaponElement: string | null | undefined, weaponElementPower: number | undefined, statusEffects: StatusEffect[], attackerSPI: number, attackerINT: number, attackerLevel: number, targetResists: Record<string, number | undefined>, enhancementElement?: string | null, enhancementLevel?: number, auraDamageMultiplier?: number): ElementalDamageLine[];
export declare function getMagicEnhancementElement(enhancementElement?: string | null): string | null;
export declare function getMagicEnhancementBoost(enhancementElement: string | null | undefined, enhancementLevel: number | undefined, spellElement: string | null | undefined): number;
export declare function computeElementalDamageLine(basePower: number, attackerSPI: number, attackerINT: number, attackerLevel: number, element: string, targetResists: Record<string, number | undefined>): ElementalDamageLine;
