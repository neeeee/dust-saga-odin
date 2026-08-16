"use strict";
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
Object.defineProperty(exports, "__esModule", { value: true });
exports.CraftProfession = void 0;
var CraftProfession;
(function (CraftProfession) {
    CraftProfession["BLACKSMITH"] = "blacksmith";
    CraftProfession["ALCHEMIST"] = "alchemist";
    CraftProfession["ENCHANTER"] = "enchanter";
})(CraftProfession || (exports.CraftProfession = CraftProfession = {}));
