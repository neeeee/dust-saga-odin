"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.BAR_KEYBIND_LABELS = exports.SKILL_BAR_KEYBINDS = exports.SLOT_KIND_COLORS = exports.SKILL_CATEGORY_COLORS = exports.MAX_SKILL_BARS = exports.SKILL_BAR_SIZE = exports.SkillBarSlotCategory = exports.SkillBarSlotKind = void 0;
exports.normalizeSlot = normalizeSlot;
exports.createEmptySkillBar = createEmptySkillBar;
exports.createDefaultLayout = createDefaultLayout;
var SkillBarSlotKind;
(function (SkillBarSlotKind) {
    SkillBarSlotKind["EMPTY"] = "empty";
    SkillBarSlotKind["SKILL"] = "skill";
    SkillBarSlotKind["ITEM"] = "item";
    SkillBarSlotKind["EQUIPMENT"] = "equipment";
    SkillBarSlotKind["MACRO"] = "macro";
})(SkillBarSlotKind || (exports.SkillBarSlotKind = SkillBarSlotKind = {}));
var SkillBarSlotCategory;
(function (SkillBarSlotCategory) {
    SkillBarSlotCategory["EMPTY"] = "empty";
    SkillBarSlotCategory["MELEE"] = "melee";
    SkillBarSlotCategory["TECHNIQUE"] = "technique";
    SkillBarSlotCategory["PRAYER"] = "prayer";
    SkillBarSlotCategory["MAGIC"] = "magic";
    SkillBarSlotCategory["SPECIAL"] = "special";
})(SkillBarSlotCategory || (exports.SkillBarSlotCategory = SkillBarSlotCategory = {}));
exports.SKILL_BAR_SIZE = 10;
exports.MAX_SKILL_BARS = 6;
exports.SKILL_CATEGORY_COLORS = {
    melee: '#c0392b',
    technique: '#27ae60',
    prayer: '#f39c12',
    magic: '#8e44ad',
    special: '#16a085',
};
// Colors for non-skill slot kinds (skills defer to SKILL_CATEGORY_COLORS).
exports.SLOT_KIND_COLORS = {
    [SkillBarSlotKind.EMPTY]: '#444444',
    [SkillBarSlotKind.SKILL]: '#c0392b',
    [SkillBarSlotKind.ITEM]: '#2e86de',
    [SkillBarSlotKind.EQUIPMENT]: '#d4a017',
    [SkillBarSlotKind.MACRO]: '#9b59b6',
};
exports.SKILL_BAR_KEYBINDS = [
    'Digit1', 'Digit2', 'Digit3', 'Digit4', 'Digit5',
    'Digit6', 'Digit7', 'Digit8', 'Digit9', 'Digit0'
];
exports.BAR_KEYBIND_LABELS = [
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['S1', 'S2', 'S3', 'S4', 'S5', 'S6', 'S7', 'S8', 'S9', 'S0'],
    ['C1', 'C2', 'C3', 'C4', 'C5', 'C6', 'C7', 'C8', 'C9', 'C0'],
];
function normalizeSlot(slot) {
    let kind = slot.kind;
    if (!kind || kind === SkillBarSlotKind.EMPTY) {
        if (slot.skillName)
            kind = SkillBarSlotKind.SKILL;
        else if (slot.macroId)
            kind = SkillBarSlotKind.MACRO;
        else if (slot.itemId)
            kind = SkillBarSlotKind.ITEM;
        else
            kind = SkillBarSlotKind.EMPTY;
    }
    return {
        kind,
        skillName: slot.skillName ?? null,
        itemId: slot.itemId ?? null,
        macroId: slot.macroId ?? null,
        category: slot.category ?? SkillBarSlotCategory.EMPTY,
        subCategory: slot.subCategory ?? '',
    };
}
function createEmptySkillBar() {
    return Array.from({ length: exports.SKILL_BAR_SIZE }, () => ({
        kind: SkillBarSlotKind.EMPTY,
        skillName: null,
        itemId: null,
        macroId: null,
        category: SkillBarSlotCategory.EMPTY,
        subCategory: '',
    }));
}
function createDefaultLayout() {
    return {
        bars: [createEmptySkillBar()],
        positions: [
            { x: 0, y: 0 },
        ],
    };
}
