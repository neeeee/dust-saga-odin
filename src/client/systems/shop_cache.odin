package systems

import rl "vendor:raylib"

Shop_Category :: enum {
	ALL,
	WEAPONS,
	ARMOR,
	CONSUMABLES,
	MATERIALS,
	ACCESSORIES,
}

Shop_Rarity :: enum {
	COMMON,
	UNCOMMON,
	RARE,
	EPIC,
	LEGENDARY,
}

Shop_Entry :: struct {
	id:        [64]u8,
	id_len:    int,
	name:      [64]u8,
	name_len:  int,
	category:  Shop_Category,
	rarity:    Shop_Rarity,
	price:     i64,
}

Shop_Cache :: struct {
	entries:    [dynamic]Shop_Entry,
	category:   Shop_Category,
	npc_id:     [64]u8,
	npc_id_len: int,
	loaded:     bool,
}

shop_cache_init :: proc(sc: ^Shop_Cache) {
	sc.entries = make([dynamic]Shop_Entry)
	sc.category = .ALL
	sc.loaded = false
}

shop_cache_destroy :: proc(sc: ^Shop_Cache) {
	delete(sc.entries)
	sc.loaded = false
}

shop_cache_clear :: proc(sc: ^Shop_Cache) {
	delete(sc.entries)
	sc.entries = make([dynamic]Shop_Entry)
	sc.category = .ALL
	sc.loaded = false
}

shop_cache_set_npc :: proc(sc: ^Shop_Cache, npc_id: string) {
	sc.npc_id_len = min(len(npc_id), len(sc.npc_id))
	copy(sc.npc_id[:sc.npc_id_len], transmute([]u8)npc_id)
}

shop_cache_add :: proc(
	sc:    ^Shop_Cache,
	id:    string,
	name:  string,
	cat:   Shop_Category,
	rar:   Shop_Rarity,
	price: i64,
) {
	e: Shop_Entry
	e.id_len = min(len(id), len(e.id))
	copy(e.id[:e.id_len], transmute([]u8)id)
	e.name_len = min(len(name), len(e.name))
	copy(e.name[:e.name_len], transmute([]u8)name)
	e.category = cat
	e.rarity = rar
	e.price = price
	append(&sc.entries, e)
	sc.loaded = true
}

shop_cache_find :: proc(sc: ^Shop_Cache, id: string) -> ^Shop_Entry {
	for i in 0 ..< len(sc.entries) {
		e := &sc.entries[i]
		if len(id) == e.id_len && string(e.id[:e.id_len]) == id {
			return e
		}
	}
	return nil
}

entry_matches_category :: proc "contextless" (e: ^Shop_Entry, cat: Shop_Category) -> bool {
	if cat == .ALL do return true
	return e.category == cat
}

shop_rarity_color :: proc "contextless" (r: Shop_Rarity) -> rl.Color {
	#partial switch r {
	case .COMMON:    return {200, 200, 200, 255}
	case .UNCOMMON:  return {30, 255, 0, 255}
	case .RARE:      return {0, 112, 255, 255}
	case .EPIC:      return {163, 53, 238, 255}
	case .LEGENDARY: return {255, 128, 0, 255}
	case:            return {200, 200, 200, 255}
	}
}

shop_category_name :: proc "contextless" (cat: Shop_Category) -> string {
	#partial switch cat {
	case .ALL:         return "All"
	case .WEAPONS:     return "Weapons"
	case .ARMOR:       return "Armor"
	case .CONSUMABLES: return "Consumables"
	case .MATERIALS:   return "Materials"
	case .ACCESSORIES: return "Accessories"
	case:              return "?"
	}
}
