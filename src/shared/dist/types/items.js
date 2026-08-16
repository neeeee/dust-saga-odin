"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.DEFAULT_EQUIPMENT = exports.EquipmentSlot = exports.ItemRarity = exports.RANGED_WEAPON_TYPES = exports.WeaponType = exports.ItemType = void 0;
exports.normalizeEquipment = normalizeEquipment;
var ItemType;
(function (ItemType) {
    ItemType["WEAPON"] = "weapon";
    ItemType["ARMOR"] = "armor";
    ItemType["HELMET"] = "helmet";
    ItemType["BOOTS"] = "boots";
    ItemType["GLOVES"] = "gloves";
    ItemType["LEGS"] = "legs";
    ItemType["SHIELD"] = "shield";
    ItemType["EARRING"] = "earring";
    ItemType["NECKLACE"] = "necklace";
    ItemType["BELT"] = "belt";
    ItemType["RING"] = "ring";
    ItemType["ACCESSORY"] = "accessory";
    ItemType["CONSUMABLE"] = "consumable";
    ItemType["MATERIAL"] = "material";
    ItemType["RECIPE"] = "recipe";
    ItemType["QUEST"] = "quest";
})(ItemType || (exports.ItemType = ItemType = {}));
var WeaponType;
(function (WeaponType) {
    WeaponType["SWORD"] = "sword";
    WeaponType["DAGGER"] = "dagger";
    WeaponType["BOW"] = "bow";
    WeaponType["CROSSBOW"] = "crossbow";
    WeaponType["BLUNT"] = "blunt";
    WeaponType["TWO_HANDED_BLUNT"] = "2h_blunt";
    WeaponType["AXE"] = "axe";
    WeaponType["TWO_HANDED_AXE"] = "2h_axe";
    WeaponType["TWO_HANDED_SWORD"] = "2h_sword";
    WeaponType["SPEAR"] = "spear";
    WeaponType["TWO_HANDED_SPEAR"] = "2h_spear";
    WeaponType["STAFF"] = "staff";
    WeaponType["WAND"] = "wand";
    WeaponType["KNUCKLES"] = "knuckles";
})(WeaponType || (exports.WeaponType = WeaponType = {}));
exports.RANGED_WEAPON_TYPES = new Set([WeaponType.BOW, WeaponType.CROSSBOW]);
var ItemRarity;
(function (ItemRarity) {
    ItemRarity["COMMON"] = "common";
    ItemRarity["UNCOMMON"] = "uncommon";
    ItemRarity["RARE"] = "rare";
    ItemRarity["EPIC"] = "epic";
    ItemRarity["LEGENDARY"] = "legendary";
})(ItemRarity || (exports.ItemRarity = ItemRarity = {}));
var EquipmentSlot;
(function (EquipmentSlot) {
    EquipmentSlot["WEAPON"] = "weapon";
    EquipmentSlot["ARMOR"] = "armor";
    EquipmentSlot["HELMET"] = "helmet";
    EquipmentSlot["BOOTS"] = "boots";
    EquipmentSlot["GLOVES"] = "gloves";
    EquipmentSlot["LEGS"] = "legs";
    EquipmentSlot["SHIELD"] = "shield";
    EquipmentSlot["EARRING_1"] = "earring_1";
    EquipmentSlot["EARRING_2"] = "earring_2";
    EquipmentSlot["NECKLACE"] = "necklace";
    EquipmentSlot["BELT"] = "belt";
    EquipmentSlot["RING_1"] = "ring_1";
    EquipmentSlot["RING_2"] = "ring_2";
})(EquipmentSlot || (exports.EquipmentSlot = EquipmentSlot = {}));
exports.DEFAULT_EQUIPMENT = {
    weapon: null,
    armor: null,
    helmet: null,
    boots: null,
    gloves: null,
    legs: null,
    shield: null,
    earring_1: null,
    earring_2: null,
    necklace: null,
    belt: null,
    ring_1: null,
    ring_2: null,
};
function normalizeEquipment(equipment) {
    if (!equipment)
        return { ...exports.DEFAULT_EQUIPMENT };
    const norm = { ...exports.DEFAULT_EQUIPMENT };
    for (const key of Object.keys(exports.DEFAULT_EQUIPMENT)) {
        if (equipment[key] !== undefined && equipment[key] !== null) {
            norm[key] = equipment[key];
        }
    }
    return norm;
}
