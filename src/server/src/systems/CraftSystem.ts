import { PlayerSession, RecipeDefinition, CraftProfession } from '@dust-saga/shared';
import { getRecipe } from '@dust-saga/shared';
import type { ItemSystem } from './ItemSystem';

export interface CraftResult {
  success: boolean;
  error?: string;
  producedItemId?: string;
  producedQuantity?: number;
  consumedMaterials?: Array<{ itemId: string; quantity: number }>;
}

/**
 * Pure validation + execution of a craft request. The handler is responsible
 * for inventory mutation side-effects (this class returns what would be
 * consumed/produced so the handler can call PlayerSystem methods and emit
 * packets).
 */
export class CraftSystem {
  itemSys!: ItemSystem;
  /** Returns the recipe if the player knows it AND it matches the NPC's profession. */
  resolveCraftableRecipe(
    session: PlayerSession,
    recipeId: string,
    npcProfession: CraftProfession | undefined
  ): RecipeDefinition | null {
    const known = session.learnedRecipes || [];
    if (!known.includes(recipeId)) return null;
    const recipe = getRecipe(recipeId);
    if (!recipe) return null;
    if (npcProfession && recipe.profession !== npcProfession) return null;
    return recipe;
  }

  /** Pure validation: returns the consumption plan, or an error explaining why not. */
  planCraft(session: PlayerSession, recipe: RecipeDefinition): CraftResult {
    if (session.stats.level < recipe.requiredLevel) {
      return { success: false, error: `Requires level ${recipe.requiredLevel}` };
    }

    const consumed: Array<{ itemId: string; quantity: number }> = [];
    for (const mat of recipe.materials) {
      const have = session.inventory
        .filter(inv => inv.itemId === mat.itemId)
        .reduce((sum, inv) => sum + inv.quantity, 0);
      if (have < mat.quantity) {
        const name = this.itemSys.getItemDefinition(mat.itemId)?.name || mat.itemId;
        return { success: false, error: `Need ${mat.quantity}× ${name} (have ${have})` };
      }
      consumed.push({ itemId: mat.itemId, quantity: mat.quantity });
    }

    return {
      success: true,
      producedItemId: recipe.resultItemId,
      producedQuantity: recipe.resultQuantity,
      consumedMaterials: consumed,
    };
  }
}
