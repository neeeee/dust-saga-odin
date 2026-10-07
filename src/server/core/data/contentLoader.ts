import { existsSync, readFileSync } from 'fs';
import { join } from 'path';
import {
  ItemDefinition, ItemType, ItemRarity, ItemStats, EquipmentSlot, WeaponType,
  EnemyDefinition, LootDrop, registerEnemyDefinition,
} from '@dust-saga/shared';
import { ItemSystem } from '../../systems/ItemSystem';

/**
 * Shipped-content loader: reads the game data CSVs from the client's assets
 * (UTF-16LE with BOM, '#' comment headers — same format family as fx.csv /
 * skill.csv) and registers everything the tables describe:
 *
 *   item.csv    (2,374 rows) → ItemDefinitions for every shipped item —
 *                equipment (weapons/armor/jewelry via one-hot slot columns),
 *                consumables, materials and souls.
 *   soul.csv    (180 rows)  → socketable-type flags + effect text, merged
 *                onto the matching SOUL items (soul id == item id).
 *   monster.csv (588 rows)  → EnemyDefinitions for the full monster roster.
 *
 * The shipped tables carry NO combat numbers (no stats, prices, HP or XP), so
 * this module derives deterministic placeholder values from the numeric ids —
 * same rules the Odin client mirrors in systems/items.odin, so display
 * (rarity/required level) always matches the server. The curves are fit to
 * the hand-authored entries (green_slime lvl1 vs basilisk lvl42). Replace the
 * derive* procs when real stat tables are found; ids/names/slots/types are
 * authoritative from the CSVs.
 *
 * Items register through ItemSystem.registerShippedItems (insert-if-absent in
 * both cache and DB — hand-authored items and admin edits always win).
 * Monsters register through shared registerEnemyDefinition (same no-overwrite
 * rule) before SpawnManager.initialize().
 */

// ── CSV plumbing ──────────────────────────────────────────────────────────

/** Quote-aware CSV line split (soul.csv descriptions contain commas). */
function splitCsvLine(line: string): string[] {
  const fields: string[] = [];
  let current = '';
  let inQuotes = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (c === '"') {
      inQuotes = !inQuotes;
    } else if (c === ',' && !inQuotes) {
      fields.push(current);
      current = '';
    } else {
      current += c;
    }
  }
  fields.push(current);
  return fields.map(f => f.trim());
}

/** Decode a UTF-16LE+BOM file and return its data lines ('#' comments and blanks dropped). */
function readCsvDataLines(path: string): string[][] {
  const buffer = readFileSync(path);
  let text = new TextDecoder('utf-16le').decode(buffer);
  if (text.startsWith('\ufeff')) text = text.slice(1);
  const rows: string[][] = [];
  for (const line of text.split(/\r?\n/)) {
    if (line.length === 0 || line.startsWith('#')) continue;
    rows.push(splitCsvLine(line));
  }
  return rows;
}

function fieldAsInt(fields: string[], idx: number): number | null {
  const raw = (fields[idx] ?? '').trim();
  if (raw === '') return null;
  const v = parseInt(raw, 10);
  return isNaN(v) ? null : v;
}

function fieldFlagged(fields: string[], idx: number): boolean {
  return (fields[idx] ?? '').trim() === '1';
}

// ── deterministic derivation (mirrored client-side in items.odin) ─────────

/** Stable per-item roll (0..99) shared with the client's display rules. */
function itemRoll(id: number): number {
  return (id * 31) % 100;
}

function itemRarity(id: number, equippable: boolean): ItemRarity {
  if (!equippable) return ItemRarity.COMMON;
  const roll = itemRoll(id);
  if (roll >= 98) return ItemRarity.LEGENDARY;
  if (roll >= 92) return ItemRarity.EPIC;
  if (roll >= 80) return ItemRarity.RARE;
  if (roll >= 55) return ItemRarity.UNCOMMON;
  return ItemRarity.COMMON;
}

function itemRequiredLevel(id: number, equippable: boolean): number {
  if (!equippable) return 1;
  return 1 + (Math.floor(id / 11) % 40);
}

// ── item.csv → ItemDefinition ─────────────────────────────────────────────

/** CSV item type → weapon type. Non-weapons return undefined. */
const WEAPON_TYPE_MAP: Record<string, WeaponType> = {
  '1H_SWORD': WeaponType.SWORD,
  '2H_SWORD': WeaponType.TWO_HANDED_SWORD,
  '1H_AXE': WeaponType.AXE,
  '2H_AXE': WeaponType.TWO_HANDED_AXE,
  '1H_BLUNT_WEAPON': WeaponType.BLUNT,
  '2H_BLUNT_WEAPON': WeaponType.TWO_HANDED_BLUNT,
  '1H_TRUMP_WEAPON': WeaponType.BLUNT,
  '2H_TRUMP_WEAPON': WeaponType.TWO_HANDED_BLUNT,
  'BOW': WeaponType.BOW,
  'CROSSBOW': WeaponType.CROSSBOW,
  'STAFF': WeaponType.STAFF,
  'WAND': WeaponType.WAND,
  'POLE_ARM': WeaponType.TWO_HANDED_SPEAR,
  'LANCE': WeaponType.SPEAR,
};

/** CSV item type → ItemType for non-weapon, non-slot-driven kinds. */
const ITEM_TYPE_MAP: Record<string, ItemType> = {
  'HELMET': ItemType.HELMET,
  'TORSO': ItemType.ARMOR,
  'CUISSES': ItemType.LEGS,
  'GLOVES': ItemType.GLOVES,
  'BOOTS': ItemType.BOOTS,
  'MANTLE': ItemType.ARMOR,      // no cloak slot exists; rides the torso slot
  'HORSE_SHIELD': ItemType.SHIELD,
  'FOOT_SHIELD': ItemType.SHIELD,
  'RING': ItemType.RING,
  'AMULET': ItemType.NECKLACE,
  'BELT': ItemType.BELT,
  'EARRING': ItemType.EARRING,
  'POTION': ItemType.CONSUMABLE,
  'BALM': ItemType.CONSUMABLE,
  'SOUL': ItemType.SOUL,
};

/**
 * Equipment slot from item.csv's one-hot 装備箇所 columns (3..17):
 * R Hand, L Hand, head, torso, gloves, legs, feet, cloak, ring, neck, waist,
 * ear, ammunition, egg, stall. Weapons come from R Hand; everything else maps
 * onto the server's 13 equipment slots (cloak rides armor, L Hand = shield).
 */
function slotFromColumns(fields: string[], isWeapon: boolean): EquipmentSlot | undefined {
  if (isWeapon && fieldFlagged(fields, 3)) return EquipmentSlot.WEAPON;
  if (fieldFlagged(fields, 4)) return EquipmentSlot.SHIELD;
  if (fieldFlagged(fields, 5)) return EquipmentSlot.HELMET;
  if (fieldFlagged(fields, 6)) return EquipmentSlot.ARMOR;
  if (fieldFlagged(fields, 7)) return EquipmentSlot.GLOVES;
  if (fieldFlagged(fields, 8)) return EquipmentSlot.LEGS;
  if (fieldFlagged(fields, 9)) return EquipmentSlot.BOOTS;
  if (fieldFlagged(fields, 10)) return EquipmentSlot.ARMOR; // cloak
  if (fieldFlagged(fields, 11)) return EquipmentSlot.RING_1;
  if (fieldFlagged(fields, 12)) return EquipmentSlot.NECKLACE;
  if (fieldFlagged(fields, 13)) return EquipmentSlot.BELT;
  if (fieldFlagged(fields, 14)) return EquipmentSlot.EARRING_1;
  return undefined;
}

const RARITY_ATTACK_BONUS: Record<string, number> = { common: 0, uncommon: 2, rare: 5, epic: 9, legendary: 14 };
const RARITY_DEFENSE_BONUS: Record<string, number> = { common: 0, uncommon: 1, rare: 2, epic: 4, legendary: 6 };
const ELEMENTAL_RESISTS: Array<keyof ItemStats> = [
  'fireResist', 'iceResist', 'lightningResist', 'poisonResist', 'darkResist', 'holyResist',
];

function deriveItemStats(id: number, csvType: string, rarity: ItemRarity, requiredLevel: number): ItemStats {
  const stats: ItemStats = {};
  const weaponType = WEAPON_TYPE_MAP[csvType];

  if (weaponType) {
    const twoHanded = csvType.startsWith('2H') || csvType === 'POLE_ARM';
    const magic = weaponType === WeaponType.STAFF || weaponType === WeaponType.WAND;
    const bonus = RARITY_ATTACK_BONUS[rarity] ?? 0;
    if (magic) {
      stats.magicAttack = 4 + Math.round(requiredLevel * 1.1) + bonus;
      stats.attack = 1;
    } else {
      stats.attack = 3 + Math.round(requiredLevel * 0.9 * (twoHanded ? 1.35 : 1)) + bonus;
      if (weaponType === WeaponType.BOW || weaponType === WeaponType.CROSSBOW) stats.accuracy = 2;
    }
    return stats;
  }

  switch (csvType) {
    case 'HELMET':
    case 'TORSO':
    case 'CUISSES':
    case 'GLOVES':
    case 'BOOTS':
    case 'MANTLE':
    case 'HORSE_SHIELD':
    case 'FOOT_SHIELD':
      stats.defense = 1 + Math.round(requiredLevel * 0.55) + (RARITY_DEFENSE_BONUS[rarity] ?? 0);
      if (csvType === 'TORSO' || csvType === 'MANTLE') stats.health = requiredLevel * 2;
      if (csvType === 'BOOTS') stats.dodge = 1;
      return stats;
    case 'RING':
    case 'AMULET':
    case 'BELT':
    case 'EARRING': {
      // One primary bonus + one elemental resist, both picked from the id so
      // every piece of jewelry differs but is stable across restarts.
      switch (id % 4) {
        case 0: stats.attack = 1 + Math.ceil(requiredLevel / 4); break;
        case 1: stats.magicAttack = 1 + Math.ceil(requiredLevel / 4); break;
        case 2: stats.health = 10 + requiredLevel * 2; break;
        default: stats.mana = 8 + Math.round(requiredLevel * 1.5); break;
      }
      const resist = ELEMENTAL_RESISTS[id % ELEMENTAL_RESISTS.length];
      (stats as any)[resist] = 2 + Math.floor(requiredLevel / 10);
      return stats;
    }
    case 'POTION':
      stats.health = 30 + (itemRoll(id) % 40) * 2;
      return stats;
    case 'BALM':
      stats.mana = 25 + (itemRoll(id) % 30) * 2;
      return stats;
    default:
      return stats;
  }
}

export interface ShippedContentStats {
  items: number;
  souls: number;
  monsters: number;
  skipped: number;
}

/**
 * Loads item.csv + soul.csv + monster.csv and registers everything. Call once
 * at boot after ItemSystem.initialize and before SpawnManager.initialize.
 */
export async function loadShippedContent(itemSys: ItemSystem): Promise<ShippedContentStats> {
  const result: ShippedContentStats = { items: 0, souls: 0, monsters: 0, skipped: 0 };
  const assetsDir = resolveAssetsDir();
  if (!assetsDir) {
    console.warn('[Content] Shipped assets not found — item/soul/monster tables skipped');
    return result;
  }

  // soul.csv first: id → effect text, merged onto the SOUL items below.
  const soulDescriptions = new Map<number, string>();
  try {
    for (const fields of readCsvDataLines(join(assetsDir, 'soul.csv'))) {
      const id = fieldAsInt(fields, 0);
      const description = (fields[14] ?? '').trim();
      if (id === null || description === '') continue;
      soulDescriptions.set(id, description);
    }
  } catch (error) {
    console.warn('[Content] soul.csv unreadable — souls load without effect text:', error);
  }

  const itemDefs: ItemDefinition[] = [];
  try {
    for (const fields of readCsvDataLines(join(assetsDir, 'item.csv'))) {
      const id = fieldAsInt(fields, 0);
      const name = (fields[1] ?? '').trim();
      const csvType = (fields[2] ?? '').trim().toUpperCase();
      if (id === null || name === '' || csvType === '') { result.skipped++; continue; }

      const weaponType = WEAPON_TYPE_MAP[csvType];
      const itemType = weaponType ? ItemType.WEAPON : (ITEM_TYPE_MAP[csvType] ?? ItemType.MATERIAL);
      const equipmentSlot = slotFromColumns(fields, weaponType !== undefined);
      const isSoul = csvType === 'SOUL';
      const equippable = equipmentSlot !== undefined;

      const def: ItemDefinition = {
        id: String(id),
        name,
        type: itemType,
        rarity: itemRarity(id, equippable),
        stats: isSoul ? {} : deriveItemStats(id, csvType, itemRarity(id, equippable), itemRequiredLevel(id, equippable)),
        description: isSoul
          ? (soulDescriptions.get(id) || 'A soul that can be socketed into equipment.')
          : '',
        maxStack: equippable || isSoul ? 1 : (itemType === ItemType.CONSUMABLE ? 20 : 99),
        sellPrice: equippable
          ? itemRequiredLevel(id, true) * 3 + (itemRoll(id) % 10)
          : (itemType === ItemType.CONSUMABLE ? 3 : 1 + (itemRoll(id) % 5)),
        requiredLevel: itemRequiredLevel(id, equippable),
      };
      if (equipmentSlot) def.equipmentSlot = equipmentSlot;
      if (weaponType) def.weaponType = weaponType;
      if (equippable && itemRoll(id) < 25) def.soulSlots = 1;
      itemDefs.push(def);
    }
  } catch (error) {
    console.error('[Content] item.csv unreadable — no shipped items registered:', error);
    return result;
  }

  // ── monster.csv → EnemyDefinitions ────────────────────────────────────────
  // The table is visual only (name, body radius, hand items, model scale), so
  // combat stats derive from a family ladder on the id, fit to the existing
  // curve (green_slime lvl 1: 40hp/5atk/15xp … basilisk lvl 42: 1800/80/900).
  const FAMILY_BASE_LEVEL: Record<number, number> = {
    11: 2, 12: 4, 13: 6, 21: 8, 22: 10,
    31: 12, 32: 14, 33: 16, 34: 18, 35: 20,
    41: 22, 42: 24, 43: 26, 44: 28,
    51: 30, 52: 32, 53: 34, 54: 36,
    70: 38, 71: 40, 72: 42,
    81: 44, 82: 46,
    90: 48, 93: 50, 97: 50, 99: 46,
  };

  const soulIds: number[] = [];
  const equipmentIds: number[] = [];
  for (const def of itemDefs) {
    const numeric = parseInt(def.id, 10);
    if (def.type === ItemType.SOUL) soulIds.push(numeric);
    else if (def.equipmentSlot) equipmentIds.push(numeric);
  }
  // Loot pools pick deterministically from these arrays.

  let monsters = 0;
  try {
    for (const fields of readCsvDataLines(join(assetsDir, 'monster.csv'))) {
      const id = fieldAsInt(fields, 0);
      const name = (fields[1] ?? '').trim();
      if (id === null || name === '') { result.skipped++; continue; }
      const bodyRadius = fieldAsInt(fields, 2) ?? 30;

      // Family = leading digits of the id (11xxx beasts → 11, 90xxx demons →
      // 90, …; 5-digit ids → first two digits via /1000).
      const family = Math.floor(id / 1000);
      let level = family === 95
        ? 1 + (id % 50) // the 95xxx batch is a mixed bag — spread it wide
        : (FAMILY_BASE_LEVEL[family] ?? 10 + (id % 25));
      level = Math.max(1, Math.min(50, level + (id % 3)));

      const drops: LootDrop[] = [];
      if (soulIds.length > 0) {
        drops.push({ itemId: String(soulIds[(id * 7) % soulIds.length]), quantity: 1, chance: 0.07 });
      }
      if (equipmentIds.length > 0) {
        drops.push({ itemId: String(equipmentIds[(id * 13) % equipmentIds.length]), quantity: 1, chance: 0.03 });
      }
      drops.push({ itemId: 'health_potion', quantity: 1, chance: 0.2 });

      const enemyDef: EnemyDefinition = {
        id: String(id),
        name,
        modelFile: `monster/monster_${id}_${name}.glb`,
        modelScale: (fieldAsInt(fields, 7) ?? 100) / 100,
        level,
        health: 25 + level * 42,
        attack: 4 + Math.round(level * 1.9),
        defense: Math.round(level * 0.7),
        speed: 2,
        experience: 14 + level * 21,
        aggroRange: 8,
        attackRange: Math.max(1.5, Math.min(4, bodyRadius * 0.02)),
        leashRange: 20,
        respawnTime: 15000 + level * 500,
        lootTable: { rolls: 1, drops },
        patrolSpeed: 1,
      };
      if (registerEnemyDefinition(enemyDef)) monsters++;
    }
  } catch (error) {
    console.error('[Content] monster.csv unreadable — no shipped monsters registered:', error);
  }

  // Items go through ItemSystem's insert-if-absent bulk path (DB upserts when
  // Postgres is connected; cache merge otherwise). `skipped` counts rows that
  // were already registered (hand-authored or a previous boot).
  const registeredItems = await itemSys.registerShippedItems(itemDefs).catch(err => {
    console.error('[Content] Item registration failed:', err);
    return 0;
  });

  result.items = registeredItems;
  result.monsters = monsters;
  result.souls = soulIds.length;
  return result;
}

/**
 * Resolve the shipped assets dir across run layouts:
 *   tsx (src/server)      → ../../.. = src → src/client/assets
 *   node dist             → ../../../.. = src → src/client/assets
 *   any cwd = src/server  → ../client/assets
 */
function resolveAssetsDir(): string | null {
  const candidates = [
    join(__dirname, '..', '..', '..', 'client', 'assets'),
    join(__dirname, '..', '..', '..', '..', 'client', 'assets'),
    join(process.cwd(), '..', 'client', 'assets'),
    join(process.cwd(), 'client', 'assets'),
  ];
  for (const dir of candidates) {
    if (existsSync(join(dir, 'item.csv'))) return dir;
  }
  return null;
}
