package systems

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import rl "vendor:raylib"

// Client-side item definitions. The bundled 57 entries mirror the server's
// hand-authored database; everything else (the ~2,400 shipped items with
// numeric ids) loads from assets/item.csv — the same table the server
// registers at boot — so names/types/slots/weapon kinds stay in sync without
// shipping numbers over the wire. The server stays authoritative for stats.

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
	SOUL,
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
	// Held-item glb ("item/EM_002904_20_000.glb"), weapons only, from the
	// RDR-SID column; empty = no model ships.
	model:           string,
	// Worn-armor appearance: RDR-SID + the EM part code (1=helmet, 2=torso,
	// 3=legs, 4=gloves, 5=boots, 12=cloak). Armor meshes are race-specific:
	// item/EM_<sid>_<part>_<chara model>.glb. 0/0 = no wearable model.
	armor_sid:       int,
	armor_part:      u8,
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

	// Everything shipped (numeric ids) — see load_item_csv below.
	load_item_csv()
}

// ── shipped item.csv ──────────────────────────────────────────────────────
// Loads every shipped item (numeric ids) for display metadata. Rarity and
// required level use the same deterministic id-derived rules as the server's
// content loader (core/data/contentLoader.ts), so both sides agree even
// though item.csv carries no combat numbers.

csv_flag :: proc(line: string, idx: int) -> bool {
	return csv_field_at(line, idx) == "1"
}

shipped_weapon_kind :: proc(type_str: string) -> (Weapon_Kind, bool) {
	switch type_str {
	case "1H_SWORD": return .SWORD, true
	case "2H_SWORD": return .TWO_HANDED_SWORD, true
	case "1H_AXE": return .AXE, true
	case "2H_AXE": return .TWO_HANDED_AXE, true
	case "1H_BLUNT_WEAPON", "1H_TRUMP_WEAPON": return .BLUNT, true
	case "2H_BLUNT_WEAPON", "2H_TRUMP_WEAPON": return .TWO_HANDED_BLUNT, true
	case "BOW": return .BOW, true
	case "CROSSBOW": return .CROSSBOW, true
	case "STAFF": return .STAFF, true
	case "WAND": return .WAND, true
	case "POLE_ARM": return .TWO_HANDED_SPEAR, true
	case "LANCE": return .SPEAR, true
	}
	return .NONE, false
}

// Equipment slot from the 装備箇所 one-hot columns (3..17). Mirrors the
// server's slotFromColumns: weapons come from R Hand, L Hand is the shield
// slot, cloak rides armor.
shipped_slot :: proc(line: string, is_weapon: bool) -> (string, bool) {
	if is_weapon && csv_flag(line, 3) do return "weapon", true
	if csv_flag(line, 4) do return "shield", true
	if csv_flag(line, 5) do return "helmet", true
	if csv_flag(line, 6) do return "armor", true
	if csv_flag(line, 7) do return "gloves", true
	if csv_flag(line, 8) do return "legs", true
	if csv_flag(line, 9) do return "boots", true
	if csv_flag(line, 10) do return "back", true // cloak/cape
	if csv_flag(line, 11) do return "ring_1", true
	if csv_flag(line, 12) do return "necklace", true
	if csv_flag(line, 13) do return "belt", true
	if csv_flag(line, 14) do return "earring_1", true
	return "", false
}

shipped_item_type :: proc(type_str: string, slot: string) -> Item_Type {
	switch slot {
	case "helmet": return .HELMET
	case "armor": return .ARMOR
	case "back": return .ARMOR // capes display as armor; their own slot
	case "legs": return .LEGS
	case "gloves": return .GLOVES
	case "boots": return .BOOTS
	case "shield": return .SHIELD
	case "ring_1": return .RING
	case "necklace": return .NECKLACE
	case "belt": return .BELT
	case "earring_1": return .EARRING
	case "weapon": return .WEAPON
	case:
	}
	switch type_str {
	case "POTION", "BALM": return .CONSUMABLE
	case "SOUL": return .SOUL
	}
	return .MATERIAL
}

// Same deterministic roll as the server's contentLoader (itemRarity).
shipped_rarity :: proc(id: int, equippable: bool) -> string {
	if !equippable do return "common"
	roll := (id * 31) % 100
	switch {
	case roll >= 98: return "legendary"
	case roll >= 92: return "epic"
	case roll >= 80: return "rare"
	case roll >= 55: return "uncommon"
	}
	return "common"
}

shipped_required_level :: proc(id: int, equippable: bool) -> int {
	if !equippable do return 1
	return 1 + (id / 11) % 40
}

// EM part code for a wearable item type — the middle segment of the shipped
// model files (item/EM_<sid>_<part>_<race>.glb). 0 = not a wearable shape.
shipped_armor_part :: proc "contextless" (type_str: string) -> u8 {
	switch type_str {
	case "HELMET":  return 1
	case "TORSO":   return 2
	case "CUISSES": return 3
	case "GLOVES":  return 4
	case "BOOTS":   return 5
	case "MANTLE":  return 12
	}
	return 0
}

load_item_csv :: proc() {
	data, err := os.read_entire_file_from_path("assets/item.csv", allocator = context.allocator)
	if err != nil {
		rl.TraceLog(.WARNING, "items: missing assets/item.csv — shipped items show as raw ids")
		return
	}
	defer delete(data)
	text := decode_utf16_file(data)
	defer delete(text)

	count := 0
	pos := 0
	for {
		line, next_pos, ok := battle_next_line(text, pos)
		if !ok do break
		pos = next_pos
		if len(line) == 0 || line[0] == '#' do continue

		id_str := csv_field_at(line, 0)
		name := csv_field_at(line, 1)
		type_str := csv_field_at(line, 2)
		id, valid := strconv.parse_int(id_str, 10)
		if !valid || len(name) == 0 || len(type_str) == 0 do continue
		if _, exists := item_defs[id_str]; exists do continue

		weapon_kind, is_weapon := shipped_weapon_kind(type_str)
		slot, equippable := shipped_slot(line, is_weapon)

		// Weapons: held-item glb keyed by the RDR-SID column (field 21),
		// e.g. sid 2904 → item/EM_002904_20_000.glb.
		model := ""
		armor_part := shipped_armor_part(type_str)
		armor_sid: int
		sid := csv_field_at(line, 21)
		sid_n, sid_ok := strconv.parse_int(sid, 10)
		if is_weapon {
			if sid_ok && sid_n > 0 {
				model = strings.clone(fmt.tprintf("item/EM_%06d_20_000.glb", sid_n))
			}
		} else if armor_part > 0 {
			// Armor: same RDR-SID column is the appearance id; meshes are
			// race-specific (Blaze Helm ships sid 11002's file, and items can
			// share — the per-item path resolves at render with the race).
			if sid_ok && sid_n > 0 do armor_sid = sid_n
		}

		def := Item_Def{
			name = strings.clone(name),
			type = shipped_item_type(type_str, slot),
			equipment_slot = slot,
			weapon_type = weapon_kind,
			rarity = shipped_rarity(id, equippable),
			required_level = shipped_required_level(id, equippable),
			model = model,
			armor_sid = armor_sid,
			armor_part = armor_part,
		}
		key := strings.clone(id_str)
		item_defs[key] = def
		count += 1
	}
	rl.TraceLog(.INFO, "items: %d shipped items loaded from item.csv", count)
}

// Held-item models: assets-cache handles keyed by the model path. Failed
// loads are negatively cached (nil value) so per-frame lookups never retry.
// The map holds the references for the session — assets_destroy unloads the
// world at shutdown regardless of refcounts.
held_models: map[string]^Model_Entry

held_model_acquire :: proc(model: string) -> ^Model_Entry {
	if len(model) == 0 do return nil
	if e, ok := held_models[model]; ok do return e
	e := assets_model_acquire(fmt.tprintf("assets/%s", model))
	key := strings.clone(model)
	held_models[key] = e // nil = known missing
	return e
}

// Resolve the equipped weapon's held model for an inventory item id.
held_model_for_item :: proc(item_id: string) -> ^Model_Entry {
	def, ok := item_def(item_id)
	if !ok do return nil
	return held_model_acquire(def.model)
}

// Model path for a wearable item's armor appearance on `race_id` (the chara
// model code, "011".."063") — armor meshes ship per race. Empty when the
// item carries no wearable model.
armor_model_path :: proc(def: Item_Def, race_id: string) -> string {
	if def.armor_part == 0 || def.armor_sid <= 0 do return ""
	return fmt.tprintf("item/EM_%06d_%02d_%s.glb", def.armor_sid, def.armor_part, race_id)
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
