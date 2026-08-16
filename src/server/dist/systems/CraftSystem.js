"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.CraftSystem = void 0;
const shared_1 = require("@dust-saga/shared");
/**
 * Pure validation + execution of a craft request. The handler is responsible
 * for inventory mutation side-effects (this class returns what would be
 * consumed/produced so the handler can call PlayerSystem methods and emit
 * packets).
 */
class CraftSystem {
    /** Returns the recipe if the player knows it AND it matches the NPC's profession. */
    resolveCraftableRecipe(session, recipeId, npcProfession) {
        const known = session.learnedRecipes || [];
        if (!known.includes(recipeId))
            return null;
        const recipe = (0, shared_1.getRecipe)(recipeId);
        if (!recipe)
            return null;
        if (npcProfession && recipe.profession !== npcProfession)
            return null;
        return recipe;
    }
    /** Pure validation: returns the consumption plan, or an error explaining why not. */
    planCraft(session, recipe) {
        if (session.stats.level < recipe.requiredLevel) {
            return { success: false, error: `Requires level ${recipe.requiredLevel}` };
        }
        const consumed = [];
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
exports.CraftSystem = CraftSystem;
