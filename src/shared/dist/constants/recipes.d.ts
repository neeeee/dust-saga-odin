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
export declare const RECIPE_DATABASE: Record<string, RecipeDefinition>;
export declare function getRecipe(id: string): RecipeDefinition | undefined;
export declare function getRecipesByProfession(profession: CraftProfession): RecipeDefinition[];
export declare function getAllRecipes(): RecipeDefinition[];
