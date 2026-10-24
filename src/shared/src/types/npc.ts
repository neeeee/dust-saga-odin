import { CraftProfession } from './recipes';

export enum NPCType {
  MERCHANT = 'merchant',
  QUEST_GIVER = 'quest_giver',
  BLACKSMITH = 'blacksmith',
  HEALER = 'healer',
  BANKER = 'banker',
  CRAFTSMAN = 'craftsman',
  GENERIC = 'generic'
}

/** Wire slot keys of the visible-equipment summary (see equipmentSummary). */
export type NPCVisualSlot = 'helmet' | 'armor' | 'gloves' | 'legs' | 'boots' | 'back' | 'weapon' | 'shield';

/**
 * Visual appearance for an NPC. Two mutually exclusive body kinds:
 *
 *  - Race variation (humanoid): `race` (or a direct chara `modelId`) picks
 *    one of the character-creator models, with face/hair/color variation and
 *    optional visible `equipment` — the exact pipeline players render
 *    through, so NPCs can wear any gear that has shipped visuals.
 *  - Enemy model: `monsterModel` points at a shipped monster glb, so beasts
 *    and monster-folk (wolf, kobold, ogre, …) can be NPCs.
 *
 * With no appearance the client falls back to the plain capsule.
 */
export interface NPCAppearance {
  /** Race id ('human' | 'elf' | 'dwarf' | 'myrine' | 'enkidu' | 'lapin'). */
  race?: string;
  /** Sex variant for races that ship one (human, elf). */
  female?: boolean;
  /** Direct chara-model code override ('011'..'063'); beats `race`. */
  modelId?: string;
  faceIndex?: number;
  hairIndex?: number;
  hairColor?: number;
  /** Enemy-model body: asset path, e.g. 'monster/monster_11108_Grey Wolf.glb'. */
  monsterModel?: string;
  /** Scale multiplier for the monster model (default 1). */
  modelScale?: number;
  /** Visible gear: item ids keyed by wire slot. Rendered on chara models only. */
  equipment?: Partial<Record<NPCVisualSlot, string>>;
}

export interface NPCDialog {
  id: string;
  text: string;
  options: Array<{
    text: string;
    nextDialogId?: string;
    action?: string;
    actionData?: any;
  }>;
}

export interface NPCDefinition {
  id: string;
  name: string;
  type: NPCType;
  position: { x: number; y: number; z: number };
  rotation: number;
  zoneId: string;
  dialogs: NPCDialog[];
  /** Body/clothing the client renders for this NPC (absent = plain capsule). */
  appearance?: NPCAppearance;
  shopItems?: string[];
  quests?: string[];
  /** For CRAFTSMAN NPCs: which profession this NPC crafts for. */
  craftProfession?: CraftProfession;
}

const CHARA_MODEL_BY_RACE: Record<string, { male: string; female?: string }> = {
  // Numeric codes on disk are race/gender pairs: 11/12 human m/f,
  // 21/22 elf m/f, 31 dwarf, 42 myrine, 51 enkidu, 63 lapin.
  human: { male: '011', female: '012' },
  elf: { male: '021', female: '022' },
  dwarf: { male: '031' },
  myrine: { male: '042' },
  enkidu: { male: '051' },
  lapin: { male: '063' },
};

/** Resolves a race id (+ sex) to its character-creator model code. */
export function charaModelForRace(race: string, female: boolean): string {
  const entry = CHARA_MODEL_BY_RACE[race];
  if (!entry) return '011';
  return (female && entry.female) ? entry.female : entry.male;
}

/**
 * Wire payload carried in the NPC entry of WORLD_STATE (and any per-entity
 * npc spawn): modelId/face/hair/hairColor + equipment for chara-model
 * appearances, modelFile/modelScale for enemy-model ones. Empty object when
 * the NPC has no appearance (client draws the capsule).
 */
export function npcAppearancePayload(npc: NPCDefinition): Record<string, unknown> {
  const ap = npc.appearance;
  if (!ap) return {};

  const out: Record<string, unknown> = {};
  const modelId = ap.modelId ?? (ap.race ? charaModelForRace(ap.race, ap.female ?? false) : null);
  if (modelId) {
    out.modelId = modelId;
    out.faceIndex = ap.faceIndex ?? 0;
    out.hairIndex = ap.hairIndex ?? 0;
    out.hairColor = ap.hairColor ?? 0;
    const equipment: Record<string, string> = {};
    for (const [slot, itemId] of Object.entries(ap.equipment ?? {})) {
      if (itemId) equipment[slot] = itemId;
    }
    if (Object.keys(equipment).length > 0) out.equipment = equipment;
  }
  if (ap.monsterModel) {
    out.modelFile = ap.monsterModel;
    out.modelScale = ap.modelScale ?? 1;
  }
  return out;
}
