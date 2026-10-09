"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.loadShippedContent = loadShippedContent;
const fs_1 = require("fs");
const path_1 = require("path");
const shared_1 = require("@dust-saga/shared");
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
function splitCsvLine(line) {
    const fields = [];
    let current = '';
    let inQuotes = false;
    for (let i = 0; i < line.length; i++) {
        const c = line[i];
        if (c === '"') {
            inQuotes = !inQuotes;
        }
        else if (c === ',' && !inQuotes) {
            fields.push(current);
            current = '';
        }
        else {
            current += c;
        }
    }
    fields.push(current);
    return fields.map(f => f.trim());
}
/** Decode a UTF-16LE+BOM file and return its data lines ('#' comments and blanks dropped). */
function readCsvDataLines(path) {
    const buffer = (0, fs_1.readFileSync)(path);
    let text = new TextDecoder('utf-16le').decode(buffer);
    if (text.startsWith('\ufeff'))
        text = text.slice(1);
    const rows = [];
    for (const line of text.split(/\r?\n/)) {
        if (line.length === 0 || line.startsWith('#'))
            continue;
        rows.push(splitCsvLine(line));
    }
    return rows;
}
function fieldAsInt(fields, idx) {
    const raw = (fields[idx] ?? '').trim();
    if (raw === '')
        return null;
    const v = parseInt(raw, 10);
    return isNaN(v) ? null : v;
}
function fieldFlagged(fields, idx) {
    return (fields[idx] ?? '').trim() === '1';
}
// ── deterministic derivation (mirrored client-side in items.odin) ─────────
/** Stable per-item roll (0..99) shared with the client's display rules. */
function itemRoll(id) {
    return (id * 31) % 100;
}
function itemRarity(id, equippable) {
    if (!equippable)
        return shared_1.ItemRarity.COMMON;
    const roll = itemRoll(id);
    if (roll >= 98)
        return shared_1.ItemRarity.LEGENDARY;
    if (roll >= 92)
        return shared_1.ItemRarity.EPIC;
    if (roll >= 80)
        return shared_1.ItemRarity.RARE;
    if (roll >= 55)
        return shared_1.ItemRarity.UNCOMMON;
    return shared_1.ItemRarity.COMMON;
}
function itemRequiredLevel(id, equippable) {
    if (!equippable)
        return 1;
    return 1 + (Math.floor(id / 11) % 40);
}
// ── item.csv → ItemDefinition ─────────────────────────────────────────────
/** CSV item type → weapon type. Non-weapons return undefined. */
const WEAPON_TYPE_MAP = {
    '1H_SWORD': shared_1.WeaponType.SWORD,
    '2H_SWORD': shared_1.WeaponType.TWO_HANDED_SWORD,
    '1H_AXE': shared_1.WeaponType.AXE,
    '2H_AXE': shared_1.WeaponType.TWO_HANDED_AXE,
    '1H_BLUNT_WEAPON': shared_1.WeaponType.BLUNT,
    '2H_BLUNT_WEAPON': shared_1.WeaponType.TWO_HANDED_BLUNT,
    '1H_TRUMP_WEAPON': shared_1.WeaponType.BLUNT,
    '2H_TRUMP_WEAPON': shared_1.WeaponType.TWO_HANDED_BLUNT,
    'BOW': shared_1.WeaponType.BOW,
    'CROSSBOW': shared_1.WeaponType.CROSSBOW,
    'STAFF': shared_1.WeaponType.STAFF,
    'WAND': shared_1.WeaponType.WAND,
    'POLE_ARM': shared_1.WeaponType.TWO_HANDED_SPEAR,
    'LANCE': shared_1.WeaponType.SPEAR,
};
/** CSV item type → ItemType for non-weapon, non-slot-driven kinds. */
const ITEM_TYPE_MAP = {
    'HELMET': shared_1.ItemType.HELMET,
    'TORSO': shared_1.ItemType.ARMOR,
    'CUISSES': shared_1.ItemType.LEGS,
    'GLOVES': shared_1.ItemType.GLOVES,
    'BOOTS': shared_1.ItemType.BOOTS,
    'MANTLE': shared_1.ItemType.ARMOR, // cape appearance; its own slot since BACK exists
    'HORSE_SHIELD': shared_1.ItemType.SHIELD,
    'FOOT_SHIELD': shared_1.ItemType.SHIELD,
    'RING': shared_1.ItemType.RING,
    'AMULET': shared_1.ItemType.NECKLACE,
    'BELT': shared_1.ItemType.BELT,
    'EARRING': shared_1.ItemType.EARRING,
    'POTION': shared_1.ItemType.CONSUMABLE,
    'BALM': shared_1.ItemType.CONSUMABLE,
    'SOUL': shared_1.ItemType.SOUL,
};
/**
 * Equipment slot from item.csv's one-hot 装備箇所 columns (3..17):
 * R Hand, L Hand, head, torso, gloves, legs, feet, cloak, ring, neck, waist,
 * ear, ammunition, egg, stall. Weapons come from R Hand; everything else maps
 * onto the server's 14 equipment slots (cloak → BACK, L Hand = shield).
 */
function slotFromColumns(fields, isWeapon) {
    if (isWeapon && fieldFlagged(fields, 3))
        return shared_1.EquipmentSlot.WEAPON;
    if (fieldFlagged(fields, 4))
        return shared_1.EquipmentSlot.SHIELD;
    if (fieldFlagged(fields, 5))
        return shared_1.EquipmentSlot.HELMET;
    if (fieldFlagged(fields, 6))
        return shared_1.EquipmentSlot.ARMOR;
    if (fieldFlagged(fields, 7))
        return shared_1.EquipmentSlot.GLOVES;
    if (fieldFlagged(fields, 8))
        return shared_1.EquipmentSlot.LEGS;
    if (fieldFlagged(fields, 9))
        return shared_1.EquipmentSlot.BOOTS;
    if (fieldFlagged(fields, 10))
        return shared_1.EquipmentSlot.BACK; // cloak/cape
    if (fieldFlagged(fields, 11))
        return shared_1.EquipmentSlot.RING_1;
    if (fieldFlagged(fields, 12))
        return shared_1.EquipmentSlot.NECKLACE;
    if (fieldFlagged(fields, 13))
        return shared_1.EquipmentSlot.BELT;
    if (fieldFlagged(fields, 14))
        return shared_1.EquipmentSlot.EARRING_1;
    return undefined;
}
const RARITY_ATTACK_BONUS = { common: 0, uncommon: 2, rare: 5, epic: 9, legendary: 14 };
const RARITY_DEFENSE_BONUS = { common: 0, uncommon: 1, rare: 2, epic: 4, legendary: 6 };
const ELEMENTAL_RESISTS = [
    'fireResist', 'iceResist', 'lightningResist', 'poisonResist', 'darkResist', 'holyResist',
];
function deriveItemStats(id, csvType, rarity, requiredLevel) {
    const stats = {};
    const weaponType = WEAPON_TYPE_MAP[csvType];
    if (weaponType) {
        const twoHanded = csvType.startsWith('2H') || csvType === 'POLE_ARM';
        const magic = weaponType === shared_1.WeaponType.STAFF || weaponType === shared_1.WeaponType.WAND;
        const bonus = RARITY_ATTACK_BONUS[rarity] ?? 0;
        if (magic) {
            stats.magicAttack = 4 + Math.round(requiredLevel * 1.1) + bonus;
            stats.attack = 1;
        }
        else {
            stats.attack = 3 + Math.round(requiredLevel * 0.9 * (twoHanded ? 1.35 : 1)) + bonus;
            if (weaponType === shared_1.WeaponType.BOW || weaponType === shared_1.WeaponType.CROSSBOW)
                stats.accuracy = 2;
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
            if (csvType === 'TORSO' || csvType === 'MANTLE')
                stats.health = requiredLevel * 2;
            if (csvType === 'BOOTS')
                stats.dodge = 1;
            return stats;
        case 'RING':
        case 'AMULET':
        case 'BELT':
        case 'EARRING': {
            // One primary bonus + one elemental resist, both picked from the id so
            // every piece of jewelry differs but is stable across restarts.
            switch (id % 4) {
                case 0:
                    stats.attack = 1 + Math.ceil(requiredLevel / 4);
                    break;
                case 1:
                    stats.magicAttack = 1 + Math.ceil(requiredLevel / 4);
                    break;
                case 2:
                    stats.health = 10 + requiredLevel * 2;
                    break;
                default:
                    stats.mana = 8 + Math.round(requiredLevel * 1.5);
                    break;
            }
            const resist = ELEMENTAL_RESISTS[id % ELEMENTAL_RESISTS.length];
            stats[resist] = 2 + Math.floor(requiredLevel / 10);
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
/**
 * Loads item.csv + soul.csv + monster.csv and registers everything. Call once
 * at boot after ItemSystem.initialize and before SpawnManager.initialize.
 */
async function loadShippedContent(itemSys) {
    const result = { items: 0, souls: 0, monsters: 0, skipped: 0 };
    const assetsDir = resolveAssetsDir();
    if (!assetsDir) {
        console.warn('[Content] Shipped assets not found — item/soul/monster tables skipped');
        return result;
    }
    // soul.csv first: id → effect text, merged onto the SOUL items below.
    const soulDescriptions = new Map();
    try {
        for (const fields of readCsvDataLines((0, path_1.join)(assetsDir, 'soul.csv'))) {
            const id = fieldAsInt(fields, 0);
            const description = (fields[14] ?? '').trim();
            if (id === null || description === '')
                continue;
            soulDescriptions.set(id, description);
        }
    }
    catch (error) {
        console.warn('[Content] soul.csv unreadable — souls load without effect text:', error);
    }
    const itemDefs = [];
    try {
        for (const fields of readCsvDataLines((0, path_1.join)(assetsDir, 'item.csv'))) {
            const id = fieldAsInt(fields, 0);
            const name = (fields[1] ?? '').trim();
            const csvType = (fields[2] ?? '').trim().toUpperCase();
            if (id === null || name === '' || csvType === '') {
                result.skipped++;
                continue;
            }
            const weaponType = WEAPON_TYPE_MAP[csvType];
            const itemType = weaponType ? shared_1.ItemType.WEAPON : (ITEM_TYPE_MAP[csvType] ?? shared_1.ItemType.MATERIAL);
            const equipmentSlot = slotFromColumns(fields, weaponType !== undefined);
            const isSoul = csvType === 'SOUL';
            const equippable = equipmentSlot !== undefined;
            const def = {
                id: String(id),
                name,
                type: itemType,
                rarity: itemRarity(id, equippable),
                stats: isSoul ? {} : deriveItemStats(id, csvType, itemRarity(id, equippable), itemRequiredLevel(id, equippable)),
                description: isSoul
                    ? (soulDescriptions.get(id) || 'A soul that can be socketed into equipment.')
                    : '',
                maxStack: equippable || isSoul ? 1 : (itemType === shared_1.ItemType.CONSUMABLE ? 20 : 99),
                sellPrice: equippable
                    ? itemRequiredLevel(id, true) * 3 + (itemRoll(id) % 10)
                    : (itemType === shared_1.ItemType.CONSUMABLE ? 3 : 1 + (itemRoll(id) % 5)),
                requiredLevel: itemRequiredLevel(id, equippable),
            };
            if (equipmentSlot)
                def.equipmentSlot = equipmentSlot;
            if (weaponType)
                def.weaponType = weaponType;
            if (equippable && itemRoll(id) < 25)
                def.soulSlots = 1;
            itemDefs.push(def);
        }
    }
    catch (error) {
        console.error('[Content] item.csv unreadable — no shipped items registered:', error);
        return result;
    }
    // ── monster.csv → EnemyDefinitions ────────────────────────────────────────
    // The table is visual only (name, body radius, hand items, model scale), so
    // combat stats derive from a family ladder on the id, fit to the existing
    // curve (green_slime lvl 1: 40hp/5atk/15xp … basilisk lvl 42: 1800/80/900).
    const FAMILY_BASE_LEVEL = {
        11: 2, 12: 4, 13: 6, 21: 8, 22: 10,
        31: 12, 32: 14, 33: 16, 34: 18, 35: 20,
        41: 22, 42: 24, 43: 26, 44: 28,
        51: 30, 52: 32, 53: 34, 54: 36,
        70: 38, 71: 40, 72: 42,
        81: 44, 82: 46,
        90: 48, 93: 50, 97: 50, 99: 46,
    };
    const soulIds = [];
    const equipmentIds = [];
    for (const def of itemDefs) {
        const numeric = parseInt(def.id, 10);
        if (def.type === shared_1.ItemType.SOUL)
            soulIds.push(numeric);
        else if (def.equipmentSlot)
            equipmentIds.push(numeric);
    }
    // Loot pools pick deterministically from these arrays.
    let monsters = 0;
    try {
        for (const fields of readCsvDataLines((0, path_1.join)(assetsDir, 'monster.csv'))) {
            const id = fieldAsInt(fields, 0);
            const name = (fields[1] ?? '').trim();
            if (id === null || name === '') {
                result.skipped++;
                continue;
            }
            const bodyRadius = fieldAsInt(fields, 2) ?? 30;
            // Family = leading digits of the id (11xxx beasts → 11, 90xxx demons →
            // 90, …; 5-digit ids → first two digits via /1000).
            const family = Math.floor(id / 1000);
            let level = family === 95
                ? 1 + (id % 50) // the 95xxx batch is a mixed bag — spread it wide
                : (FAMILY_BASE_LEVEL[family] ?? 10 + (id % 25));
            level = Math.max(1, Math.min(50, level + (id % 3)));
            const drops = [];
            if (soulIds.length > 0) {
                drops.push({ itemId: String(soulIds[(id * 7) % soulIds.length]), quantity: 1, chance: 0.07 });
            }
            if (equipmentIds.length > 0) {
                drops.push({ itemId: String(equipmentIds[(id * 13) % equipmentIds.length]), quantity: 1, chance: 0.03 });
            }
            drops.push({ itemId: 'health_potion', quantity: 1, chance: 0.2 });
            const enemyDef = {
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
            if ((0, shared_1.registerEnemyDefinition)(enemyDef))
                monsters++;
        }
    }
    catch (error) {
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
function resolveAssetsDir() {
    const candidates = [
        (0, path_1.join)(__dirname, '..', '..', '..', 'client', 'assets'),
        (0, path_1.join)(__dirname, '..', '..', '..', '..', 'client', 'assets'),
        (0, path_1.join)(process.cwd(), '..', 'client', 'assets'),
        (0, path_1.join)(process.cwd(), 'client', 'assets'),
    ];
    for (const dir of candidates) {
        if ((0, fs_1.existsSync)((0, path_1.join)(dir, 'item.csv')))
            return dir;
    }
    return null;
}
