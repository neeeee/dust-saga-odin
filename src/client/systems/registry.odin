package systems

import "core:fmt"

// Generic content registry — the backbone of the data-oriented game-data layer.
//
// Content (jobs, races, skills, items, …) is keyed by a human-memorable string
// ID ("warrior", "Slice", "human") in source/data files. At load the registry
// interns each name to a stable `distinct u16` index, so runtime lookups are
// O(1) map lookups (name→id) or direct array indexing (id→item), with no string
// hashing on the hot path. The distinct types (Job_Id, Race_Id, Skill_Id, …)
// are declared in game_data.odin; each kind is its own distinct type so they
// can't be accidentally mixed at compile time.
//
// `ID` MUST be a `distinct u16`.

INVALID_INDEX :: u16(0xFFFF) // sentinel; registries never hand out this index

Registry :: struct($T: typeid, $ID: typeid) {
	items: [dynamic]T,
	by_key: map[string]ID,
	keys:  [dynamic]string, // ID → name (parallel to items)
}

registry_init :: proc(r: ^Registry($T, $ID)) {
	r.items = make([dynamic]T)
	r.by_key = make(map[string]ID)
	r.keys = make([dynamic]string)
}

registry_destroy :: proc(r: ^Registry($T, $ID)) {
	delete(r.items)
	delete(r.by_key)
	delete(r.keys)
}

registry_count :: proc(r: ^Registry($T, $ID)) -> int {
	return len(r.items)
}

// Add `item` under `name`, returning its stable ID. Idempotent: re-adding an
// existing name returns the original ID and leaves the stored item unchanged.
registry_add :: proc(r: ^Registry($T, $ID), name: string, item: T) -> ID {
	if id, ok := r.by_key[name]; ok do return id
	id := ID(u16(len(r.items)))
	append(&r.items, item)
	append(&r.keys, name)
	r.by_key[name] = id
	return id
}

// Reserve `name` with a zero-value placeholder and return a pointer the caller
// fills in field-by-field. The pointer is valid only while the registry's item
// array is not grown by another add — fine during init-time population.
registry_reserve :: proc(r: ^Registry($T, $ID), name: string) -> (^T, ID) {
	if id, ok := r.by_key[name]; ok do return &r.items[int(id)], id
	id := ID(u16(len(r.items)))
	append(&r.items, T{})
	append(&r.keys, name)
	r.by_key[name] = id
	return &r.items[int(id)], id
}

registry_lookup :: proc(r: ^Registry($T, $ID), name: string) -> (ID, bool) {
	id, ok := r.by_key[name]
	return id, ok
}

registry_has :: proc(r: ^Registry($T, $ID), name: string) -> bool {
	_, ok := r.by_key[name]
	return ok
}

registry_get :: proc(r: ^Registry($T, $ID), id: ID) -> ^T {
	return &r.items[int(id)]
}

registry_name :: proc(r: ^Registry($T, $ID), id: ID) -> string {
	return r.keys[int(id)]
}

// Log every registered name ↔ id pair, for debugging data loads.
registry_dump :: proc(r: ^Registry($T, $ID), label: string) {
	fmt.printf("[data] %s: %d entries\n", label, len(r.items))
	for i in 0 ..< len(r.items) {
		fmt.printf("  %v -> %s\n", ID(u16(i)), r.keys[i])
	}
}
