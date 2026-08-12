import { Router } from 'express';
import type { ItemSystem } from '../../../../../systems/ItemSystem';
import type { ApiServices } from '../../../index';

/**
 * Human-readable shape of an ItemDefinition, surfaced at `GET /schema` for the
 * admin UI. Kept as a plain object so it serializes straight to JSON.
 */
export const ITEM_SCHEMA = {
  id: 'string (required, unique)',
  name: 'string (required)',
  description: 'string',
  type: 'weapon | armor | helmet | boots | gloves | legs | shield | earring | necklace | belt | ring | accessory | consumable | material | recipe | quest',
  rarity: 'common | uncommon | rare | epic | legendary',
  stats: 'ItemStats — { attack?, defense?, health?, STA?, STR?, ..., weaponElement?, weaponElementPower? }',
  icon: 'string? (asset path / icon id)',
  maxStack: 'number (>= 1, default 1)',
  sellPrice: 'number (>= 0, default 0)',
  requiredLevel: 'number (>= 1, default 1)',
  equipmentSlot: 'string? — required for equippable types (weapon | armor | helmet | boots | gloves | legs | shield | earring_1 | earring_2 | necklace | belt | ring_1 | ring_2)',
  weaponType: 'string? — required for weapons (sword | dagger | bow | crossbow | blunt | 2h_blunt | axe | 2h_axe | 2h_sword | spear | 2h_spear | staff | wand | knuckles)',
  soulSlots: 'number? (>= 0, weapon soul socket count)',
  onHitProcs: '[{ effect, baseChance, chancePerLevel?, minLevel?, duration?, potency?, element? }]? — soul procs',
  innateProcs: '[{ effect, baseChance, ... }]? — weapon innate procs (often enhancement-gated)',
  obeliskBuff: 'boolean? — marks an Obelisk weapon: grants magic-resist-ignore (on magic attacks) + damage-taken reduction scaling with enhancement level (OBELISK_BUFF_TABLE). Mutually exclusive with Guardian.',
  teachesRecipe: 'string? — recipe id taught when a RECIPE item is consumed',
};

export function createItemsRouter(services: ApiServices): Router {
  const router = Router();
  const itemSys: ItemSystem = services.itemSys;

  router.get('/schema', (_req, res) => {
    res.json(ITEM_SCHEMA);
  });

  router.get('/', (req, res) => {
    let items = itemSys.getAllItemDefinitions();
    const typeFilter = req.query.type as string | undefined;
    const rarityFilter = req.query.rarity as string | undefined;
    const minLevel = req.query.minLevel ? parseInt(req.query.minLevel as string, 10) : undefined;
    const maxLevel = req.query.maxLevel ? parseInt(req.query.maxLevel as string, 10) : undefined;
    const search = req.query.search as string | undefined;
    if (typeFilter) items = items.filter(i => i.type === typeFilter);
    if (rarityFilter) items = items.filter(i => i.rarity === rarityFilter);
    if (typeof minLevel === 'number' && !Number.isNaN(minLevel)) items = items.filter(i => i.requiredLevel >= minLevel);
    if (typeof maxLevel === 'number' && !Number.isNaN(maxLevel)) items = items.filter(i => i.requiredLevel <= maxLevel);
    if (search) {
      const q = search.toLowerCase();
      items = items.filter(i => i.id.toLowerCase().includes(q) || i.name.toLowerCase().includes(q));
    }
    res.json({ count: items.length, items });
  });

  router.get('/:id', (req, res) => {
    const def = itemSys.getItemDefinition(req.params.id);
    if (!def) {
      res.status(404).json({ error: 'Item not found' });
      return;
    }
    res.json(def);
  });

  router.post('/', async (req, res) => {
    const result = await itemSys.createItem(req.body);
    if (!result.success) {
      res.status(400).json({ error: result.error });
      return;
    }
    res.status(201).json({ success: true, id: req.body.id });
  });

  router.put('/:id', async (req, res) => {
    const body = { ...req.body, id: req.params.id };
    const result = await itemSys.createItem(body);
    if (!result.success) {
      res.status(400).json({ error: result.error });
      return;
    }
    res.json({ success: true, id: body.id });
  });

  router.delete('/:id', async (req, res) => {
    const result = await itemSys.deleteItem(req.params.id);
    if (!result.success) {
      res.status(404).json({ error: result.error });
      return;
    }
    res.json({ success: true });
  });

  router.post('/reload', async (_req, res) => {
    await itemSys.reload();
    res.json({ success: true, count: itemSys.getAllItemDefinitions().length });
  });

  return router;
}
