export declare enum SkillAnimationType {
    SLASH = "Slash",
    THRUST = "Thrust",
    CLEAVE = "Cleave",
    BASH = "Bash",
    DEFEND = "Block",
    SHOOT = "Shoot",
    CAST = "Cast",
    HEAL = "CastHeal",
    DASH = "Dash",
    BUFF = "CastBuff",
    THROW = "Throw",
    ROAR = "Roar",
    CHARGE = "Charge",
    TRIP = "Trip",
    GENERIC = "Attack"
}
export declare function getSkillAnimationName(skillName: string, subCategory: string, castTime: number, isPassive: boolean): string;
export type SkillAnimKind = 'physical' | 'magical' | 'support';
/**
 * Kind hint for the ENTITY_ANIMATION 'Skill' payload: the client picks the
 * default execution pose (weapon swing / attack cast finish / plain cast
 * finish) from it when the skill has no battle script for that model.
 */
export declare function skillAnimKind(def?: {
    damageType?: string;
} | null): SkillAnimKind;
/**
 * Fine animation category for a skill definition ("Slash", "Shot", "Cast",
 * "CastHeal", …) — the shipped sub-category mapping, so skills without a
 * per-model battle script still play the right family of animation. Returns
 * '' when the skill is passive or unknown (caller falls back to the kind
 * hint).
 */
export declare function skillAnimCategory(def?: {
    name?: string;
    castTime?: number;
    isPassive?: boolean;
} | null): string;
export declare function getCategoryForSubCategory(subCategoryId: number): string;
export declare function getCategoryColor(category: string): string;
