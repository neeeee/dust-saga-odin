package systems

import rl "vendor:raylib"

// Client-side item definitions (57 items, sourced from the server's admin API).
// The server is authoritative for stats/effects; these are for display (names,
// types, equippability, weapon-type for skill-req feedback).

Item_Type :: enum u8 {
	WEAPON,
	ARMOR,
	HELMET,
	BOOTS,
	GLOVES,
	LEGS,
	SHIELD,
	RING,
	NECKLACE,
	BELT,
	EARRING,
	CONSUMABLE,
	MATERIAL,
	QUEST,
	RECIPE,
	ACCESSORY,
}

Weapon_Kind :: enum u8 {
	NONE,
	SWORD,
	DAGGER,
	BOW,
	CROSSBOW,
	BLUNT,
	TWO_HANDED_BLUNT,
	AXE,
	TWO_HANDED_AXE,
	TWO_HANDED_SWORD,
	SPEAR,
	TWO_HANDED_SPEAR,
	STAFF,
	WAND,
	KNUCKLES,
}

Item_Def :: struct {
	name:            string,
	type:            Item_Type,
	equipment_slot:  string, // server slot key ("weapon", "armor", …) or "" if not equippable
	weapon_type:     Weapon_Kind, // .NONE for non-weapons
	rarity:          string, // "common", "uncommon", "rare", "epic", "legendary"
	required_level:  int,
}

item_defs: map[string]Item_Def

init_item_defs :: proc() {
	item_defs = make(map[string]Item_Def)
	item_defs["wooden_sword"] = Item_Def{name="Wooden Sword", type=.WEAPON, equipment_slot="weapon", weapon_type=.SWORD, rarity="common", required_level=1}
	item_defs["iron_sword"] = Item_Def{name="Iron Sword", type=.WEAPON, equipment_slot="weapon", weapon_type=.SWORD, rarity="uncommon", required_level=5}
	item_defs["steel_blade"] = Item_Def{name="Steel Blade", type=.WEAPON, equipment_slot="weapon", weapon_type=.SWORD, rarity="rare", required_level=10}
	item_defs["wooden_bow"] = Item_Def{name="Wooden Bow", type=.WEAPON, equipment_slot="weapon", weapon_type=.BOW, rarity="common", required_level=1}
	item_defs["hunter_crossbow"] = Item_Def{name="Hunter Crossbow", type=.WEAPON, equipment_slot="weapon", weapon_type=.CROSSBOW, rarity="uncommon", required_level=5}
	item_defs["rusty_dagger"] = Item_Def{name="Rusty Dagger", type=.WEAPON, equipment_slot="weapon", weapon_type=.DAGGER, rarity="common", required_level=1}
	item_defs["leather_armor"] = Item_Def{name="Leather Armor", type=.ARMOR, equipment_slot="armor", weapon_type=.NONE, rarity="common", required_level=1}
	item_defs["chainmail"] = Item_Def{name="Chainmail", type=.ARMOR, equipment_slot="armor", weapon_type=.NONE, rarity="uncommon", required_level=5}
	item_defs["plate_armor"] = Item_Def{name="Plate Armor", type=.ARMOR, equipment_slot="armor", weapon_type=.NONE, rarity="rare", required_level=10}
	item_defs["cloth_helmet"] = Item_Def{name="Cloth Hood", type=.HELMET, equipment_slot="helmet", weapon_type=.NONE, rarity="common", required_level=1}
	item_defs["iron_helmet"] = Item_Def{name="Iron Helmet", type=.HELMET, equipment_slot="helmet", weapon_type=.NONE, rarity="uncommon", required_level=5}
	item_defs["leather_boots"] = Item_Def{name="Leather Boots", type=.BOOTS, equipment_slot="boots", weapon_type=.NONE, rarity="common", required_level=1}
	item_defs["swift_boots"] = Item_Def{name="Swift Boots", type=.BOOTS, equipment_slot="boots", weapon_type=.NONE, rarity="rare", required_level=8}
	item_defs["copper_ring"] = Item_Def{name="Copper Ring", type=.RING, equipment_slot="ring_1", weapon_type=.NONE, rarity="common", required_level=1}
	item_defs["flame_amulet"] = Item_Def{name="Flame Amulet", type=.NECKLACE, equipment_slot="necklace", weapon_type=.NONE, rarity="rare", required_level=8}
	item_defs["mana_belt"] = Item_Def{name="Mana Belt", type=.BELT, equipment_slot="belt", weapon_type=.NONE, rarity="rare", required_level=8}
	item_defs["shadow_cloak"] = Item_Def{name="Shadow Cloak", type=.ARMOR, equipment_slot="armor", weapon_type=.NONE, rarity="epic", required_level=15}
	item_defs["frost_blade"] = Item_Def{name="Frost Blade", type=.WEAPON, equipment_slot="weapon", weapon_type=.SWORD, rarity="epic", required_level=15}
	item_defs["basic_staff"] = Item_Def{name="Basic Staff", type=.WEAPON, equipment_slot="weapon", weapon_type=.STAFF, rarity="common", required_level=1}
	item_defs["thunder_helm"] = Item_Def{name="Thunder Helm", type=.HELMET, equipment_slot="helmet", weapon_type=.NONE, rarity="epic", required_level=15}
	item_defs["plague_walkers"] = Item_Def{name="Plague Walkers", type=.BOOTS, equipment_slot="boots", weapon_type=.NONE, rarity="epic", required_level=15}
	item_defs["windstrider_boots"] = Item_Def{name="Windstrider Boots", type=.BOOTS, equipment_slot="boots", weapon_type=.NONE, rarity="legendary", required_level=20}
	item_defs["dragonscale_ring"] = Item_Def{name="Dragonscale Ring", type=.RING, equipment_slot="ring_1", weapon_type=.NONE, rarity="legendary", required_level=20}
	item_defs["health_potion"] = Item_Def{name="Health Potion", type=.CONSUMABLE, equipment_slot="", weapon_type=.NONE, rarity="common", required_level=1}
	item_defs["mana_potion"] = Item_Def{name="Mana Potion", type=.CONSUMABLE, equipment_slot="", weapon_type=.NONE, rarity="common", required_level=1}
	item_defs["wolf_pelt"] = Item_Def{name="Wolf Pelt", type=.MATERIAL, equipment_slot="", weapon_type=.NONE, rarity="common", required_level=0}
	item_defs["goblin_ear"] = Item_Def{name="Goblin Ear", type=.QUEST, equipment_slot="", weapon_type=.NONE, rarity="common", required_level=0}
	item_defs["ancient_scroll"] = Item_Def{name="Ancient Scroll", type=.MATERIAL, equipment_slot="", weapon_type=.NONE, rarity="rare", required_level=0}
	item_defs["fire_gem"] = Item_Def{name="Fire Gem", type=.MATERIAL, equipment_slot="", weapon_type=.NONE, rarity="uncommon", required_level=0}
	item_defs["ice_gem"] = Item_Def{name="Ice Gem", type=.MATERIAL, equipment_slot="", weapon_type=.NONE, rarity="uncommon", required_level=0}
	item_defs["lightning_gem"] = Item_Def{name="Lightning Gem", type=.MATERIAL, equipment_slot="", weapon_type=.NONE, rarity="uncommon", required_level=0}
	item_defs["holy_gem"] = Item_Def{name="Holy Gem", type=.MATERIAL, equipment_slot="", weapon_type=.NONE, rarity="uncommon", required_level=0}
	item_defs["dark_gem"] = Item_Def{name="Dark Gem", type=.MATERIAL, equipment_slot="", weapon_type=.NONE, rarity="uncommon", required_level=0}
	item_defs["poison_gem"] = Item_Def{name="Poison Gem", type=.MATERIAL, equipment_slot="", weapon_type=.NONE, rarity="uncommon", required_level=0}
	item_defs["fire_magic_gem"] = Item_Def{name="Fire Magic Gem", type=.MATERIAL, equipment_slot="", weapon_type=.NONE, rarity="rare", required_level=0}
	item_defs["ice_magic_gem"] = Item_Def{name="Ice Magic Gem", type=.MATERIAL, equipment_slot="", weapon_type=.NONE, rarity="rare", required_level=0}
	item_defs["lightning_magic_gem"] = Item_Def{name="Lightning Magic Gem", type=.MATERIAL, equipment_slot="", weapon_type=.NONE, rarity="rare", required_level=0}
	item_defs["holy_magic_gem"] = Item_Def{name="Holy Magic Gem", type=.MATERIAL, equipment_slot="", weapon_type=.NONE, rarity="rare", required_level=0}
	item_defs["dark_magic_gem"] = Item_Def{name="Dark Magic Gem", type=.MATERIAL, equipment_slot="", weapon_type=.NONE, rarity="rare", required_level=0}
	item_defs["poison_magic_gem"] = Item_Def{name="Poison Magic Gem", type=.MATERIAL, equipment_slot="", weapon_type=.NONE, rarity="rare", required_level=0}
	item_defs["rod_of_origin"] = Item_Def{name="Rod of Origin", type=.WEAPON, equipment_slot="weapon", weapon_type=.WAND, rarity="legendary", required_level=25}
	item_defs["eternal_torso"] = Item_Def{name="Eternal Torso", type=.ARMOR, equipment_slot="armor", weapon_type=.NONE, rarity="legendary", required_level=25}
	item_defs["example_gloves"] = Item_Def{name="Swift Gloves", type=.GLOVES, equipment_slot="gloves", weapon_type=.NONE, rarity="uncommon", required_level=5}
	item_defs["eternal_gloves"] = Item_Def{name="Eternal Gloves", type=.GLOVES, equipment_slot="gloves", weapon_type=.NONE, rarity="legendary", required_level=25}
	item_defs["eternal_legs"] = Item_Def{name="Eternal Legs", type=.LEGS, equipment_slot="legs", weapon_type=.NONE, rarity="legendary", required_level=25}
	item_defs["eternal_boots"] = Item_Def{name="Eternal Boots", type=.BOOTS, equipment_slot="boots", weapon_type=.NONE, rarity="legendary", required_level=25}
	item_defs["earring_of_power"] = Item_Def{name="Earring of Power", type=.EARRING, equipment_slot="earring_1", weapon_type=.NONE, rarity="epic", required_level=15}
	item_defs["trap"] = Item_Def{name="Trap", type=.MATERIAL, equipment_slot="", weapon_type=.NONE, rarity="common", required_level=1}
	item_defs["container"] = Item_Def{name="Glass Container", type=.MATERIAL, equipment_slot="", weapon_type=.NONE, rarity="common", required_level=1}
	item_defs["deadly_nightshade"] = Item_Def{name="Deadly Nightshade", type=.MATERIAL, equipment_slot="", weapon_type=.NONE, rarity="common", required_level=1}
	item_defs["antidote_herb"] = Item_Def{name="Antidote Herb", type=.MATERIAL, equipment_slot="", weapon_type=.NONE, rarity="common", required_level=1}
	item_defs["moonlight_herb"] = Item_Def{name="Moonlight Herb", type=.MATERIAL, equipment_slot="", weapon_type=.NONE, rarity="common", required_level=1}
	item_defs["aquilegia"] = Item_Def{name="Aquilegia", type=.MATERIAL, equipment_slot="", weapon_type=.NONE, rarity="common", required_level=1}
	item_defs["holy_water"] = Item_Def{name="Holy Water", type=.CONSUMABLE, equipment_slot="", weapon_type=.NONE, rarity="uncommon", required_level=1}
	item_defs["poison_vial"] = Item_Def{name="Poison Vial", type=.CONSUMABLE, equipment_slot="", weapon_type=.NONE, rarity="uncommon", required_level=1}
	item_defs["antidote"] = Item_Def{name="Antidote", type=.CONSUMABLE, equipment_slot="", weapon_type=.NONE, rarity="uncommon", required_level=1}
	item_defs["mysterious_potion"] = Item_Def{name="Mysterious Potion", type=.CONSUMABLE, equipment_slot="", weapon_type=.NONE, rarity="rare", required_level=1}
}

// Lookup helpers — call after init_item_defs (wired into init_game_data).

item_name :: proc "contextless" (id: string) -> string {
	if def, ok := item_defs[id]; ok do return def.name
	return id // unknown item → fallback to raw id
}

item_def :: proc "contextless" (id: string) -> (Item_Def, bool) {
	def, ok := item_defs[id]
	return def, ok
}

item_is_equippable :: proc "contextless" (id: string) -> bool {
	if def, ok := item_defs[id]; ok do return len(def.equipment_slot) > 0
	return false
}

item_rarity_color :: proc "contextless" (id: string) -> (rl.Color, bool) {
	rarity := "common"
	if def, ok := item_defs[id]; ok do rarity = def.rarity
	switch rarity {
	case "common":    return {180, 180, 180, 255}, true
	case "uncommon":  return {120, 200, 80, 255}, true
	case "rare":      return {80, 140, 230, 255}, true
	case "epic":      return {170, 80, 220, 255}, true
	case "legendary": return {230, 170, 50, 255}, true
	case:            return {180, 180, 180, 255}, false
	}
}
