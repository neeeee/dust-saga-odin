import { CraftProfession, RecipeDefinition } from '../types/recipes';

/**
 * Master recipe registry. Recipes are gated by:
 *   - Player level (requiredLevel)
 *   - Material availability (drops from mobs)
 *   - Profession (must craft at the right NPC)
 *
 * Players learn recipes by consuming RECIPE-type items (which drop from
 * enemies — see enemy loot tables). Once learned, the recipe is permanently
 * known and craftable at any matching-profession NPC.
 */
export const RECIPE_DATABASE: Record<string, RecipeDefinition> = {
  // ── BLACKSMITH ──────────────────────────────────────────────────────────
  recipe_leather_armor: {
    id: 'recipe_leather_armor',
    resultItemId: 'leather_armor',
    resultQuantity: 1,
    profession: CraftProfession.BLACKSMITH,
    requiredLevel: 1,
    materials: [{ itemId: 'wolf_pelt', quantity: 3 }],
  },
  recipe_leather_boots: {
    id: 'recipe_leather_boots',
    resultItemId: 'leather_boots',
    resultQuantity: 1,
    profession: CraftProfession.BLACKSMITH,
    requiredLevel: 1,
    materials: [{ itemId: 'wolf_pelt', quantity: 2 }],
  },
  recipe_iron_sword: {
    id: 'recipe_iron_sword',
    resultItemId: 'iron_sword',
    resultQuantity: 1,
    profession: CraftProfession.BLACKSMITH,
    requiredLevel: 2,
    materials: [
      { itemId: 'wolf_pelt', quantity: 5 },
      { itemId: 'goblin_ear', quantity: 2 },
    ],
  },
  recipe_hunter_crossbow: {
    id: 'recipe_hunter_crossbow',
    resultItemId: 'hunter_crossbow',
    resultQuantity: 1,
    profession: CraftProfession.BLACKSMITH,
    requiredLevel: 3,
    materials: [
      { itemId: 'wolf_pelt', quantity: 6 },
      { itemId: 'goblin_ear', quantity: 4 },
    ],
  },
  recipe_iron_helmet: {
    id: 'recipe_iron_helmet',
    resultItemId: 'iron_helmet',
    resultQuantity: 1,
    profession: CraftProfession.BLACKSMITH,
    requiredLevel: 4,
    materials: [{ itemId: 'goblin_ear', quantity: 6 }],
  },
  recipe_chainmail: {
    id: 'recipe_chainmail',
    resultItemId: 'chainmail',
    resultQuantity: 1,
    profession: CraftProfession.BLACKSMITH,
    requiredLevel: 5,
    materials: [
      { itemId: 'wolf_pelt', quantity: 8 },
      { itemId: 'goblin_ear', quantity: 5 },
    ],
  },
  recipe_frost_blade: {
    id: 'recipe_frost_blade',
    resultItemId: 'frost_blade',
    resultQuantity: 1,
    profession: CraftProfession.BLACKSMITH,
    requiredLevel: 8,
    materials: [
      { itemId: 'wolf_pelt', quantity: 10 },
      { itemId: 'goblin_ear', quantity: 5 },
      { itemId: 'ice_gem', quantity: 1 },
    ],
  },
  recipe_steel_blade: {
    id: 'recipe_steel_blade',
    resultItemId: 'steel_blade',
    resultQuantity: 1,
    profession: CraftProfession.BLACKSMITH,
    requiredLevel: 8,
    materials: [
      { itemId: 'wolf_pelt', quantity: 10 },
      { itemId: 'goblin_ear', quantity: 5 },
      { itemId: 'fire_gem', quantity: 1 },
    ],
  },
  recipe_plate_armor: {
    id: 'recipe_plate_armor',
    resultItemId: 'plate_armor',
    resultQuantity: 1,
    profession: CraftProfession.BLACKSMITH,
    requiredLevel: 10,
    materials: [
      { itemId: 'wolf_pelt', quantity: 15 },
      { itemId: 'goblin_ear', quantity: 10 },
      { itemId: 'fire_gem', quantity: 1 },
    ],
  },
  recipe_thunder_helm: {
    id: 'recipe_thunder_helm',
    resultItemId: 'thunder_helm',
    resultQuantity: 1,
    profession: CraftProfession.BLACKSMITH,
    requiredLevel: 12,
    materials: [
      { itemId: 'goblin_ear', quantity: 12 },
      { itemId: 'lightning_gem', quantity: 1 },
    ],
  },

  // ── ALCHEMIST ───────────────────────────────────────────────────────────
  recipe_health_potion: {
    id: 'recipe_health_potion',
    resultItemId: 'health_potion',
    resultQuantity: 3,
    profession: CraftProfession.ALCHEMIST,
    requiredLevel: 1,
    materials: [
      { itemId: 'moonlight_herb', quantity: 1 },
      { itemId: 'container', quantity: 1 },
    ],
  },
  recipe_mana_potion: {
    id: 'recipe_mana_potion',
    resultItemId: 'mana_potion',
    resultQuantity: 3,
    profession: CraftProfession.ALCHEMIST,
    requiredLevel: 1,
    materials: [
      { itemId: 'aquilegia', quantity: 1 },
      { itemId: 'container', quantity: 1 },
    ],
  },
  recipe_antidote: {
    id: 'recipe_antidote',
    resultItemId: 'antidote',
    resultQuantity: 2,
    profession: CraftProfession.ALCHEMIST,
    requiredLevel: 2,
    materials: [
      { itemId: 'antidote_herb', quantity: 1 },
      { itemId: 'container', quantity: 1 },
    ],
  },
  recipe_poison_vial: {
    id: 'recipe_poison_vial',
    resultItemId: 'poison_vial',
    resultQuantity: 2,
    profession: CraftProfession.ALCHEMIST,
    requiredLevel: 3,
    materials: [
      { itemId: 'deadly_nightshade', quantity: 1 },
      { itemId: 'container', quantity: 1 },
    ],
  },
  recipe_holy_water: {
    id: 'recipe_holy_water',
    resultItemId: 'holy_water',
    resultQuantity: 1,
    profession: CraftProfession.ALCHEMIST,
    requiredLevel: 5,
    materials: [
      { itemId: 'container', quantity: 1 },
      { itemId: 'holy_gem', quantity: 1 },
    ],
  },
  recipe_mysterious_potion: {
    id: 'recipe_mysterious_potion',
    resultItemId: 'mysterious_potion',
    resultQuantity: 1,
    profession: CraftProfession.ALCHEMIST,
    requiredLevel: 8,
    materials: [
      { itemId: 'moonlight_herb', quantity: 2 },
      { itemId: 'aquilegia', quantity: 2 },
      { itemId: 'container', quantity: 1 },
    ],
  },

  // ── ENCHANTER ───────────────────────────────────────────────────────────
  recipe_fire_magic_gem: {
    id: 'recipe_fire_magic_gem',
    resultItemId: 'fire_magic_gem',
    resultQuantity: 1,
    profession: CraftProfession.ENCHANTER,
    requiredLevel: 3,
    materials: [
      { itemId: 'fire_gem', quantity: 1 },
      { itemId: 'ancient_scroll', quantity: 1 },
    ],
  },
  recipe_ice_magic_gem: {
    id: 'recipe_ice_magic_gem',
    resultItemId: 'ice_magic_gem',
    resultQuantity: 1,
    profession: CraftProfession.ENCHANTER,
    requiredLevel: 3,
    materials: [
      { itemId: 'ice_gem', quantity: 1 },
      { itemId: 'ancient_scroll', quantity: 1 },
    ],
  },
  recipe_lightning_magic_gem: {
    id: 'recipe_lightning_magic_gem',
    resultItemId: 'lightning_magic_gem',
    resultQuantity: 1,
    profession: CraftProfession.ENCHANTER,
    requiredLevel: 3,
    materials: [
      { itemId: 'lightning_gem', quantity: 1 },
      { itemId: 'ancient_scroll', quantity: 1 },
    ],
  },
  recipe_holy_magic_gem: {
    id: 'recipe_holy_magic_gem',
    resultItemId: 'holy_magic_gem',
    resultQuantity: 1,
    profession: CraftProfession.ENCHANTER,
    requiredLevel: 5,
    materials: [
      { itemId: 'holy_gem', quantity: 1 },
      { itemId: 'ancient_scroll', quantity: 1 },
    ],
  },
  recipe_dark_magic_gem: {
    id: 'recipe_dark_magic_gem',
    resultItemId: 'dark_magic_gem',
    resultQuantity: 1,
    profession: CraftProfession.ENCHANTER,
    requiredLevel: 5,
    materials: [
      { itemId: 'dark_gem', quantity: 1 },
      { itemId: 'ancient_scroll', quantity: 1 },
    ],
  },
  recipe_poison_magic_gem: {
    id: 'recipe_poison_magic_gem',
    resultItemId: 'poison_magic_gem',
    resultQuantity: 1,
    profession: CraftProfession.ENCHANTER,
    requiredLevel: 5,
    materials: [
      { itemId: 'poison_gem', quantity: 1 },
      { itemId: 'ancient_scroll', quantity: 1 },
    ],
  },
  recipe_flame_amulet: {
    id: 'recipe_flame_amulet',
    resultItemId: 'flame_amulet',
    resultQuantity: 1,
    profession: CraftProfession.ENCHANTER,
    requiredLevel: 10,
    materials: [
      { itemId: 'fire_magic_gem', quantity: 1 },
      { itemId: 'wolf_pelt', quantity: 5 },
    ],
  },
};

export function getRecipe(id: string): RecipeDefinition | undefined {
  return RECIPE_DATABASE[id];
}

export function getRecipesByProfession(profession: CraftProfession): RecipeDefinition[] {
  return Object.values(RECIPE_DATABASE).filter(r => r.profession === profession);
}

export function getAllRecipes(): RecipeDefinition[] {
  return Object.values(RECIPE_DATABASE);
}
