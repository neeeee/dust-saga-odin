package systems

// Per-entity visible equipment for remote players. The server carries a slot
// → item-id summary on the player spawn payload and broadcasts ENTITY_EQUIPMENT
// when it changes; this module stores it per entity so the avatar pipeline can
// render other players' armor and held weapon exactly like the local player's
// (chara_avatar_sync_armor / held_model_for_item).
//
// It also tracks each entity's weapon stance: attack/skill animation packets
// open a short "fighting" window (hand grip), expiring back to the sheathed
// carry socket; an explicit ENTITY_STANCE from the owner's sheath/draw toggle
// overrides the window until they toggle again.

entity_equipment:   map[Entity_Id]Inventory
entity_drawn_until: map[Entity_Id]f64
entity_stance_drawn: map[Entity_Id]bool

ENTITY_DRAWN_SECONDS :: 6.0

// Spawn/equipment payload slot name → client equip slot.
entity_equipment_slots := [8]struct {
	name: string,
	slot: EQUIP_SLOT,
}{
	{"helmet", .HELMET},
	{"armor", .ARMOR},
	{"gloves", .GLOVES},
	{"legs", .LEGS},
	{"boots", .BOOTS},
	{"back", .BACK},
	{"weapon", .WAPON},
	{"shield", .SHIELD},
}

// Fill an entity's equipment from the wire summary (also used for updates).
entity_equipment_apply :: proc(id: Entity_Id, root: JSON_Object) {
	inv: Inventory
	for &s in entity_equipment_slots {
		item_id := get_string(root, s.name)
		if len(item_id) == 0 do continue
		it := &inv.equipment[int(s.slot)]
		copy_string_to_buffer(it.item_id[:], &it.item_id_len, item_id)
	}
	if entity_equipment == nil do entity_equipment = make(map[Entity_Id]Inventory)
	entity_equipment[id] = inv
}

// Merge a spawn payload's optional "equipment" object (absent on old servers
// / non-player entities).
entity_equipment_from_spawn :: proc(id: Entity_Id, root: JSON_Object) {
	if !has_field(root, "equipment") do return
	eq := get_object(root, "equipment")
	if eq == nil do return
	entity_equipment_apply(id, eq)
}

entity_equipment_forget :: proc(id: Entity_Id) {
	delete_key(&entity_equipment, id)
	delete_key(&entity_drawn_until, id)
	if entity_stance_drawn != nil do delete_key(&entity_stance_drawn, id)
}

entity_equipment_clear_all :: proc() {
	if entity_equipment != nil do clear(&entity_equipment)
	if entity_drawn_until != nil do clear(&entity_drawn_until)
	if entity_stance_drawn != nil do clear(&entity_stance_drawn)
}

// Weapon_Kind of an entity's equipped weapon (.NONE when unknown — remote
// attacks fall back to the unarmed family).
entity_weapon_kind :: proc(id: Entity_Id) -> Weapon_Kind {
	inv, ok := entity_equipment[id]
	if !ok do return .NONE
	w := &inv.equipment[int(EQUIP_SLOT.WAPON)]
	if w.item_id_len == 0 do return .NONE
	if def, ok := item_def(item_id_string(w)); ok do return def.weapon_type
	return .NONE
}

// Attack/skill animation packets mark the entity as fighting; the drawn
// window expires back to the sheathed carry pose.
entity_mark_drawn :: proc(id: Entity_Id) {
	if entity_drawn_until == nil do entity_drawn_until = make(map[Entity_Id]f64)
	entity_drawn_until[id] = f64(now_ms_local()) / 1000.0 + ENTITY_DRAWN_SECONDS
}

// Explicit stance from the owner's sheath/draw toggle; sticks until they
// toggle again (unlike the combat auto-draw window).
entity_stance_set :: proc(id: Entity_Id, drawn: bool) {
	if entity_stance_drawn == nil do entity_stance_drawn = make(map[Entity_Id]bool)
	entity_stance_drawn[id] = drawn
}

entity_is_drawn :: proc(id: Entity_Id) -> bool {
	if v, ok := entity_stance_drawn[id]; ok do return v
	if entity_drawn_until == nil do return false
	return f64(now_ms_local()) / 1000.0 < entity_drawn_until[id]
}
