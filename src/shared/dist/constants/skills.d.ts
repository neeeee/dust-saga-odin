import { SkillCategoryData, SkillCategoryId, SkillDefinition } from "../types/skills";
export declare const GROUND_TARGETED_AOE_SKILLS: Set<string>;
export declare const DEFAULT_AOE_RADIUS = 5;
export declare const SKILL_CATEGORIES: Record<number, SkillCategoryData>;
export declare const CLASS_SKILL_DATA: Record<number, {
    skills: SkillCategoryData["skills"];
}>;
export declare const CATEGORY_ID_TO_KEY: Record<SkillCategoryId, 'melee' | 'technique' | 'prayer' | 'magic' | 'special'>;
export declare const CATEGORY_DISPLAY_NAMES: Record<string, string>;
export declare const CATEGORY_LEVEL_SKILLS: Record<SkillCategoryId, Record<string, SkillDefinition>>;
export declare function findSkillDefinition(skillName: string): import("../types/skills").SkillDefinition | null;
