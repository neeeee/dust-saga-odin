package systems

import "core:encoding/json"
import "core:os"

// The skill bar is a client-side convenience: 10 slots holding skill names.
// The server resolves skills by name (send_skill_use → handleSkillUse), so it
// neither stores nor validates the bar — we persist it locally in skillbar.json.

// Index of the slot holding `name`, or -1 if absent.
skill_bar_find :: proc(p: ^Local_Player, name: string) -> int {
	for i in 0 ..< len(p.skill_bar) {
		if skill_bar_get(p, i) == name do return i
	}
	return -1
}

// First empty slot (lens == 0), or -1 if the bar is full.
skill_bar_next_free :: proc(p: ^Local_Player) -> int {
	for i in 0 ..< len(p.skill_bar) {
		if p.skill_bar_lens[i] == 0 do return i
	}
	return -1
}

skill_bar_clear :: proc(p: ^Local_Player, slot: int) {
	if slot < 0 || slot >= len(p.skill_bar) do return
	p.skill_bar_lens[slot] = 0
}

// Toggle a skill on/off the bar. Returns the affected slot and whether it was
// added (true) or removed (false). No-op (returns -1,false) when removing an
// absent skill or adding to a full bar.
skill_bar_toggle :: proc(p: ^Local_Player, name: string) -> (slot: int, added: bool) {
	existing := skill_bar_find(p, name)
	if existing >= 0 {
		skill_bar_clear(p, existing)
		return existing, false
	}
	free := skill_bar_next_free(p)
	if free < 0 do return -1, false
	skill_bar_set(p, free, name)
	return free, true
}

// ── persistence (skillbar.json: array of 10 names, "" = empty) ─────────────

SKILLBAR_PATH :: "skillbar.json"

load_skill_bar :: proc(p: ^Local_Player) {
	data, err := os.read_entire_file_from_path(SKILLBAR_PATH, allocator = context.allocator)
	if err != nil do return
	defer delete(data)
	v, ok := json_parse(data)
	if !ok do return
	items := as_dyn(array_of(v))
	for i in 0 ..< min(len(items), len(p.skill_bar)) {
		name := string_of(items[i])
		if len(name) > 0 do skill_bar_set(p, i, name)
	}
}

save_skill_bar :: proc(p: ^Local_Player) {
	a := make([dynamic]JSON_Value, len(p.skill_bar))
	defer delete(a)
	for i in 0 ..< len(p.skill_bar) {
		a[i] = json.String(skill_bar_get(p, i))
	}
	v: JSON_Value = json.Array(a)
	out, ok := json_marshal(&v)
	if !ok do return
	_ = os.write_entire_file_from_string(SKILLBAR_PATH, out)
}
