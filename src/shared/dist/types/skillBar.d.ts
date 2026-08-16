export declare enum SkillBarSlotKind {
    EMPTY = "empty",
    SKILL = "skill",
    ITEM = "item",
    EQUIPMENT = "equipment",
    MACRO = "macro"
}
export interface SkillBarSlot {
    kind: SkillBarSlotKind;
    skillName: string | null;
    itemId?: string | null;
    macroId?: string | null;
    category: SkillBarSlotCategory;
    subCategory: string;
}
export declare enum SkillBarSlotCategory {
    EMPTY = "empty",
    MELEE = "melee",
    TECHNIQUE = "technique",
    PRAYER = "prayer",
    MAGIC = "magic",
    SPECIAL = "special"
}
export declare const SKILL_BAR_SIZE = 10;
export declare const MAX_SKILL_BARS = 6;
export declare const SKILL_CATEGORY_COLORS: Record<string, string>;
export declare const SLOT_KIND_COLORS: Record<SkillBarSlotKind, string>;
export declare const SKILL_BAR_KEYBINDS: string[];
export declare const BAR_KEYBIND_LABELS: string[][];
export interface SkillBarLayout {
    bars: SkillBarSlot[][];
    positions: {
        x: number;
        y: number;
    }[];
    v?: number;
}
export declare function normalizeSlot(slot: Partial<SkillBarSlot>): SkillBarSlot;
export declare function createEmptySkillBar(): SkillBarSlot[];
export declare function createDefaultLayout(): SkillBarLayout;
