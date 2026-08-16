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
export declare function getCategoryForSubCategory(subCategoryId: number): string;
export declare function getCategoryColor(category: string): string;
