export enum SkillBarSlotKind {
  EMPTY = 'empty',
  SKILL = 'skill',
  ITEM = 'item',
  EQUIPMENT = 'equipment',
  MACRO = 'macro',
}

export interface SkillBarSlot {
  kind: SkillBarSlotKind;
  skillName: string | null;   // SKILL
  itemId?: string | null;     // ITEM / EQUIPMENT
  macroId?: string | null;    // MACRO
  category: SkillBarSlotCategory;
  subCategory: string;
}

export enum SkillBarSlotCategory {
  EMPTY = 'empty',
  MELEE = 'melee',
  TECHNIQUE = 'technique',
  PRAYER = 'prayer',
  MAGIC = 'magic',
  SPECIAL = 'special'
}

export const SKILL_BAR_SIZE = 10;

export const MAX_SKILL_BARS = 6;

export const SKILL_CATEGORY_COLORS: Record<string, string> = {
  melee: '#c0392b',
  technique: '#27ae60',
  prayer: '#f39c12',
  magic: '#8e44ad',
  special: '#16a085',
};

// Colors for non-skill slot kinds (skills defer to SKILL_CATEGORY_COLORS).
export const SLOT_KIND_COLORS: Record<SkillBarSlotKind, string> = {
  [SkillBarSlotKind.EMPTY]: '#444444',
  [SkillBarSlotKind.SKILL]: '#c0392b',
  [SkillBarSlotKind.ITEM]: '#2e86de',
  [SkillBarSlotKind.EQUIPMENT]: '#d4a017',
  [SkillBarSlotKind.MACRO]: '#9b59b6',
};

export const SKILL_BAR_KEYBINDS = [
  'Digit1', 'Digit2', 'Digit3', 'Digit4', 'Digit5',
  'Digit6', 'Digit7', 'Digit8', 'Digit9', 'Digit0'
];

export const BAR_KEYBIND_LABELS: string[][] = [
  ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
  ['S1', 'S2', 'S3', 'S4', 'S5', 'S6', 'S7', 'S8', 'S9', 'S0'],
  ['C1', 'C2', 'C3', 'C4', 'C5', 'C6', 'C7', 'C8', 'C9', 'C0'],
];

export interface SkillBarLayout {
  bars: SkillBarSlot[][];
  // Normalized viewport fractions (0..1) when v >= 2; legacy absolute pixels when absent.
  positions: { x: number; y: number }[];
  v?: number;
}

export function normalizeSlot(slot: Partial<SkillBarSlot>): SkillBarSlot {
  let kind = slot.kind;
  if (!kind || kind === SkillBarSlotKind.EMPTY) {
    if (slot.skillName) kind = SkillBarSlotKind.SKILL;
    else if (slot.macroId) kind = SkillBarSlotKind.MACRO;
    else if (slot.itemId) kind = SkillBarSlotKind.ITEM;
    else kind = SkillBarSlotKind.EMPTY;
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

export function createEmptySkillBar(): SkillBarSlot[] {
  return Array.from({ length: SKILL_BAR_SIZE }, () => ({
    kind: SkillBarSlotKind.EMPTY,
    skillName: null,
    itemId: null,
    macroId: null,
    category: SkillBarSlotCategory.EMPTY,
    subCategory: '',
  }));
}

export function createDefaultLayout(): SkillBarLayout {
  return {
    bars: [createEmptySkillBar()],
    positions: [
      { x: 0, y: 0 },
    ],
  };
}
