/**
 * Crafting system types.
 *
 * Players learn recipes by consuming RECIPE-type items (which drop from mobs
 * or are sold by crafting NPCs). At a crafting NPC, the player sees all
 * recipes they've learned that match the NPC's profession, and can craft the
 * result if they have the required materials and player level.
 *
 * Professions are tied to NPCs (one BLACKSMITH/ALCHEMIST/ENCHANTER per
 * nation capital), so a player must travel to the right NPC to craft a given
 * recipe.
 */

export enum CraftProfession {
  BLACKSMITH = 'blacksmith',
  ALCHEMIST = 'alchemist',
  ENCHANTER = 'enchanter',
}

export interface RecipeMaterial {
  itemId: string;
  quantity: number;
}

export interface RecipeDefinition {
  /** Stable id; also the value stored in `character_recipes` and taught by RECIPE items. */
  id: string;
  /** Output item id and quantity (what the player gets on success). */
  resultItemId: string;
  resultQuantity: number;
  profession: CraftProfession;
  /** Player level required to craft. */
  requiredLevel: number;
  /** Consumed materials on success. */
  materials: RecipeMaterial[];
  /** Optional: NPC id that teaches/crafts this (otherwise any NPC of the right profession). */
  npcId?: string;
  /** Display name (defaults to the result item's name). */
  name?: string;
}
