import {
  ItemDefinition, ItemType, ItemRarity, EquipmentSlot, WeaponType,
  OnHitProc, ITEM_DATABASE,
} from '@dust-saga/shared';
import { DatabaseManager } from '../core/database/DatabaseManager';

/** Runtime list of valid proc effects (ProcEffectType is a string-union type,
 *  not an enum, so it has no runtime representation to enumerate). */
const VALID_PROC_EFFECTS = [
  'weaken', 'burn', 'sleep', 'freeze', 'drainLife', 'trip', 'stun',
  'poison', 'bleed', 'silence', 'castSpeedDown', 'slow',
];

const EQUIPPABLE_TYPES: ItemType[] = [
  ItemType.WEAPON, ItemType.ARMOR, ItemType.HELMET, ItemType.BOOTS,
  ItemType.GLOVES, ItemType.LEGS, ItemType.SHIELD, ItemType.EARRING,
  ItemType.NECKLACE, ItemType.BELT, ItemType.RING, ItemType.ACCESSORY,
];

/**
 * Loads item definitions from the DB at boot into a private cache and exposes
 * CRUD for the admin API. Mirrors QuestSystem: the shared `ITEM_DATABASE` is
 * used only as (a) a fallback when the DB is unavailable and (b) the one-time
 * seed source. All live lookups go through `getItemDefinition` so admin edits
 * are visible without a restart.
 */
export class ItemSystem {
  private db: DatabaseManager | null = null;
  private dbAvailable = false;
  private itemCache: Map<string, ItemDefinition> = new Map();

  async initialize(db: DatabaseManager): Promise<void> {
    this.db = db;
    this.dbAvailable = db.isPostgresConnected();
    await this.loadFromDb();
    // First boot: if the DB is connected but empty, seed it once from the
    // static definitions so starting content exists.
    if (this.dbAvailable && this.itemCache.size === 0) {
      await this.seedIfEmpty().catch(err => console.error('[ItemSystem] Seed failed:', err));
      await this.loadFromDb();
    }
  }

  async loadFromDb(): Promise<void> {
    const next = new Map<string, ItemDefinition>();

    if (this.db && this.dbAvailable) {
      try {
        const result = await this.db.postgres!.query(
          'SELECT id, name, description, type, rarity, stats, icon, max_stack, sell_price, required_level, equipment_slot, weapon_type, soul_slots, on_hit_procs, innate_procs, teaches_recipe, obelisk_buff FROM item_definitions'
        );
        for (const row of result.rows) {
          const def = this.rowToDefinition(row);
          if (def) next.set(def.id, def);
        }
        console.log(`[ItemSystem] Loaded ${next.size} item(s) from database`);
      } catch (error) {
        console.error('[ItemSystem] Failed to load items from database, falling back to static data:', error);
        for (const def of Object.values(ITEM_DATABASE)) next.set(def.id, def);
      }
    } else {
      // Dev mode (no DB): use the bundled static item data.
      for (const def of Object.values(ITEM_DATABASE)) next.set(def.id, def);
    }

    this.itemCache = next;
  }

  async reload(): Promise<void> {
    await this.loadFromDb();
  }

  getItemDefinition(id: string): ItemDefinition | undefined {
    return this.itemCache.get(id);
  }

  getAllItemDefinitions(): ItemDefinition[] {
    return [...this.itemCache.values()];
  }

  async createItem(def: ItemDefinition): Promise<{ success: boolean; error?: string }> {
    const validation = this.validateDefinition(def);
    if (!validation.valid) return { success: false, error: validation.error };

    if (this.db && this.dbAvailable) {
      try {
        await this.db.postgres!.query(
          `INSERT INTO item_definitions (id, name, description, type, rarity, stats, icon, max_stack, sell_price, required_level, equipment_slot, weapon_type, soul_slots, on_hit_procs, innate_procs, teaches_recipe, obelisk_buff)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17)
           ON CONFLICT (id) DO UPDATE SET
             name = EXCLUDED.name,
             description = EXCLUDED.description,
             type = EXCLUDED.type,
             rarity = EXCLUDED.rarity,
             stats = EXCLUDED.stats,
             icon = EXCLUDED.icon,
             max_stack = EXCLUDED.max_stack,
             sell_price = EXCLUDED.sell_price,
             required_level = EXCLUDED.required_level,
             equipment_slot = EXCLUDED.equipment_slot,
             weapon_type = EXCLUDED.weapon_type,
             soul_slots = EXCLUDED.soul_slots,
             on_hit_procs = EXCLUDED.on_hit_procs,
             innate_procs = EXCLUDED.innate_procs,
             teaches_recipe = EXCLUDED.teaches_recipe,
             obelisk_buff = EXCLUDED.obelisk_buff`,
          [
            def.id, def.name, def.description || '', def.type, def.rarity,
            JSON.stringify(def.stats || {}), def.icon || null,
            def.maxStack ?? 1, def.sellPrice ?? 0, def.requiredLevel ?? 1,
            def.equipmentSlot || null, def.weaponType || null, def.soulSlots ?? null,
            def.onHitProcs ? JSON.stringify(def.onHitProcs) : null,
            def.innateProcs ? JSON.stringify(def.innateProcs) : null,
            def.teachesRecipe || null,
            def.obeliskBuff === true,
          ]
        );
      } catch (error) {
        console.error('[ItemSystem] createItem DB write failed:', error);
        return { success: false, error: 'Database write failed' };
      }
    }

    this.itemCache.set(def.id, def);
    return { success: true };
  }

  async deleteItem(itemId: string): Promise<{ success: boolean; error?: string }> {
    if (!this.itemCache.has(itemId)) return { success: false, error: 'Item not found' };

    if (this.db && this.dbAvailable) {
      try {
        await this.db.postgres!.query('DELETE FROM item_definitions WHERE id = $1', [itemId]);
      } catch (error) {
        console.error('[ItemSystem] deleteItem DB write failed:', error);
        return { success: false, error: 'Database delete failed' };
      }
    }

    this.itemCache.delete(itemId);
    return { success: true };
  }

  private validateDefinition(def: ItemDefinition): { valid: boolean; error?: string } {
    if (!def.id || typeof def.id !== 'string') return { valid: false, error: 'Invalid or missing id' };
    if (!def.name || typeof def.name !== 'string') return { valid: false, error: 'Invalid or missing name' };
    if (!Object.values(ItemType).includes(def.type)) {
      return { valid: false, error: `Invalid type (must be one of: ${Object.values(ItemType).join(', ')})` };
    }
    if (!Object.values(ItemRarity).includes(def.rarity)) {
      return { valid: false, error: `Invalid rarity (must be one of: ${Object.values(ItemRarity).join(', ')})` };
    }
    if (!def.stats || typeof def.stats !== 'object') return { valid: false, error: 'Missing stats object' };
    if (typeof def.maxStack !== 'number' || def.maxStack < 1) return { valid: false, error: 'maxStack must be >= 1' };
    if (typeof def.sellPrice !== 'number' || def.sellPrice < 0) return { valid: false, error: 'sellPrice must be >= 0' };
    if (typeof def.requiredLevel !== 'number' || def.requiredLevel < 1) return { valid: false, error: 'requiredLevel must be >= 1' };

    // Per-type rules
    if (def.type === ItemType.WEAPON) {
      if (!def.weaponType || !Object.values(WeaponType).includes(def.weaponType)) {
        return { valid: false, error: `Weapons require a valid weaponType (one of: ${Object.values(WeaponType).join(', ')})` };
      }
      if (def.equipmentSlot && def.equipmentSlot !== EquipmentSlot.WEAPON) {
        return { valid: false, error: `Weapons must use equipmentSlot "${EquipmentSlot.WEAPON}"` };
      }
    }
    if (def.equipmentSlot !== undefined && !Object.values(EquipmentSlot).includes(def.equipmentSlot)) {
      return { valid: false, error: `Invalid equipmentSlot (must be one of: ${Object.values(EquipmentSlot).join(', ')})` };
    }
    if (EQUIPPABLE_TYPES.includes(def.type) && !def.equipmentSlot) {
      return { valid: false, error: `Equippable type "${def.type}" requires equipmentSlot` };
    }
    if (def.soulSlots !== undefined && (typeof def.soulSlots !== 'number' || def.soulSlots < 0)) {
      return { valid: false, error: 'soulSlots must be >= 0' };
    }

    // Proc arrays
    const procError = this.validateProcs(def.onHitProcs, 'onHitProcs');
    if (procError) return { valid: false, error: procError };
    const innateError = this.validateProcs(def.innateProcs, 'innateProcs');
    if (innateError) return { valid: false, error: innateError };

    if (def.teachesRecipe !== undefined && (typeof def.teachesRecipe !== 'string' || !def.teachesRecipe)) {
      return { valid: false, error: 'teachesRecipe must be a non-empty string' };
    }
    if (def.obeliskBuff !== undefined && typeof def.obeliskBuff !== 'boolean') {
      return { valid: false, error: 'obeliskBuff must be a boolean' };
    }
    return { valid: true };
  }

  private validateProcs(procs: OnHitProc[] | undefined, field: string): string | null {
    if (procs === undefined) return null;
    if (!Array.isArray(procs)) return `${field} must be an array`;
    const validEffects = new Set<string>(VALID_PROC_EFFECTS);
    for (const p of procs) {
      if (!p || typeof p.effect !== 'string' || !validEffects.has(p.effect)) {
        return `${field}[] has invalid effect (must be one of: ${VALID_PROC_EFFECTS.join(', ')})`;
      }
      if (typeof p.baseChance !== 'number' || p.baseChance < 0 || p.baseChance > 1) {
        return `${field}[] effect "${p.effect}" must have baseChance between 0 and 1`;
      }
    }
    return null;
  }

  private rowToDefinition(row: any): ItemDefinition | null {
    try {
      const stats = typeof row.stats === 'string' ? JSON.parse(row.stats) : row.stats;
      const def: ItemDefinition = {
        id: row.id,
        name: row.name,
        description: row.description || '',
        type: row.type as ItemType,
        rarity: row.rarity as ItemRarity,
        stats: stats || {},
        maxStack: row.max_stack ?? 1,
        sellPrice: row.sell_price ?? 0,
        requiredLevel: row.required_level ?? 1,
      };
      if (row.icon) def.icon = row.icon;
      if (row.equipment_slot) def.equipmentSlot = row.equipment_slot as EquipmentSlot;
      if (row.weapon_type) def.weaponType = row.weapon_type as WeaponType;
      if (row.soul_slots != null && typeof row.soul_slots === 'number') def.soulSlots = row.soul_slots;
      if (row.on_hit_procs) {
        def.onHitProcs = typeof row.on_hit_procs === 'string' ? JSON.parse(row.on_hit_procs) : row.on_hit_procs;
      }
      if (row.innate_procs) {
        def.innateProcs = typeof row.innate_procs === 'string' ? JSON.parse(row.innate_procs) : row.innate_procs;
      }
      if (row.teaches_recipe) def.teachesRecipe = row.teaches_recipe;
      if (row.obelisk_buff === true || row.obelisk_buff === 't' || row.obelisk_buff === 1) def.obeliskBuff = true;
      return def;
    } catch {
      return null;
    }
  }

  private async seedIfEmpty(): Promise<void> {
    if (!this.db || !this.dbAvailable) return;
      for (const def of Object.values(ITEM_DATABASE)) {
        await this.db.postgres!.query(
          `INSERT INTO item_definitions (id, name, description, type, rarity, stats, icon, max_stack, sell_price, required_level, equipment_slot, weapon_type, soul_slots, on_hit_procs, innate_procs, teaches_recipe, obelisk_buff)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17)
           ON CONFLICT (id) DO NOTHING`,
          [
            def.id, def.name, def.description || '', def.type, def.rarity,
            JSON.stringify(def.stats || {}), def.icon || null,
            def.maxStack ?? 1, def.sellPrice ?? 0, def.requiredLevel ?? 1,
            def.equipmentSlot || null, def.weaponType || null, def.soulSlots ?? null,
            def.onHitProcs ? JSON.stringify(def.onHitProcs) : null,
            def.innateProcs ? JSON.stringify(def.innateProcs) : null,
            def.teachesRecipe || null,
            def.obeliskBuff === true,
          ]
        );
      }
    console.log(`[ItemSystem] Seeded ${Object.keys(ITEM_DATABASE).length} item(s) into database`);
  }
}
