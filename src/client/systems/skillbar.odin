package systems

import "core:encoding/json"
import "core:fmt"
import "core:os"

// 8 skill bars × 10 slots, client-side. Persisted per-character
// (skillbar_<characterId>.json). The server resolves skills by name.

SKILL_BAR_COUNT :: 8
SLOTS_PER_BAR :: 10
SKILL_SLOT_SIZE :: 36
SKILL_SLOT_GAP :: 4

// ── per-slot helpers ───────────────────────────────────────────────────────

skill_bar_get :: proc(p: ^Local_Player, bar, slot: int) -> string {
	if bar < 0 || bar >= SKILL_BAR_COUNT do return ""
	if slot < 0 || slot >= SLOTS_PER_BAR do return ""
	return string(p.skill_bars[bar][slot][:p.skill_bar_lens[bar][slot]])
}

skill_bar_set :: proc(p: ^Local_Player, bar, slot: int, name: string) {
	if bar < 0 || bar >= SKILL_BAR_COUNT do return
	if slot < 0 || slot >= SLOTS_PER_BAR do return
	p.skill_bar_lens[bar][slot] = min(len(name), len(p.skill_bars[bar][slot]))
	copy(p.skill_bars[bar][slot][:p.skill_bar_lens[bar][slot]], transmute([]u8)name)
}

skill_bar_clear :: proc(p: ^Local_Player, bar, slot: int) {
	if bar < 0 || bar >= SKILL_BAR_COUNT do return
	if slot < 0 || slot >= SLOTS_PER_BAR do return
	p.skill_bar_lens[bar][slot] = 0
}

// Does bar have at least one skill?
skill_bar_has_skills :: proc(p: ^Local_Player, bar: int) -> bool {
	if bar < 0 || bar >= SKILL_BAR_COUNT do return false
	for slot in 0 ..< SLOTS_PER_BAR {
		if p.skill_bar_lens[bar][slot] > 0 do return true
	}
	return false
}

// Find a skill across ALL bars → (bar, slot) or (-1, -1).
skill_bar_find :: proc(p: ^Local_Player, name: string) -> (int, int) {
	for bar in 0 ..< SKILL_BAR_COUNT {
		for slot in 0 ..< SLOTS_PER_BAR {
			if skill_bar_get(p, bar, slot) == name do return bar, slot
		}
	}
	return -1, -1
}

// Next free slot across ALL bars → (bar, slot) or (-1, -1).
skill_bar_next_free :: proc(p: ^Local_Player) -> (int, int) {
	for bar in 0 ..< SKILL_BAR_COUNT {
		for slot in 0 ..< SLOTS_PER_BAR {
			if p.skill_bar_lens[bar][slot] == 0 do return bar, slot
		}
	}
	return -1, -1
}

// Toggle a skill on/off across all bars. Returns (bar, slot, added).
skill_bar_toggle :: proc(p: ^Local_Player, name: string) -> (bar: int, slot: int, added: bool) {
	b, s := skill_bar_find(p, name)
	if b >= 0 {
		skill_bar_clear(p, b, s)
		return b, s, false
	}
	fb, fs := skill_bar_next_free(p)
	if fb < 0 do return -1, -1, false
	skill_bar_set(p, fb, fs, name)
	return fb, fs, true
}

// ── character-specific persistence ─────────────────────────────────────────
// File: skillbar_<characterId>.json — an array of 8 bars, each {slots, x, y}.

load_skill_bar :: proc(p: ^Local_Player) {
	char_id := character_id_string(p)
	if len(char_id) == 0 do return
	path := fmt.tprintf("skillbar_%s.json", char_id)
	data, err := os.read_entire_file_from_path(path, allocator = context.allocator)
	if err != nil do return
	defer delete(data)
	v, ok := json_parse(data)
	if !ok do return
	defer json.destroy_value(v) // parse tree is heap-backed
	bars := as_dyn(array_of(v))
	for bi in 0 ..< min(len(bars), SKILL_BAR_COUNT) {
		bar_obj := obj_of(bars[bi])
		slots := as_dyn(array_of(get_array(bar_obj, "slots")))
		for si in 0 ..< min(len(slots), SLOTS_PER_BAR) {
			name := string_of(slots[si])
			if len(name) > 0 do skill_bar_set(p, bi, si, name)
		}
		if has_field(bar_obj, "x") {
			p.skill_bar_pos[bi].x = f32(get_f64(bar_obj, "x", f64(p.skill_bar_pos[bi].x)))
			p.skill_bar_pos[bi].y = f32(get_f64(bar_obj, "y", f64(p.skill_bar_pos[bi].y)))
		}
	}
}

save_skill_bar :: proc(p: ^Local_Player) {
	char_id := character_id_string(p)
	if len(char_id) == 0 do return
	path := fmt.tprintf("skillbar_%s.json", char_id)

	all_bars := make([dynamic]JSON_Value, SKILL_BAR_COUNT)
	defer delete(all_bars)
	for bi in 0 ..< SKILL_BAR_COUNT {
		// Sub-arrays on the temp allocator — build_object stores
		// json.Array(slot_arr) by reference, so these must outlive the
		// serialization. The frame arena frees them at frame end; no
		// manual delete needed (which was causing double-frees when the
		// loop reused the stack slot).
		slot_arr := make([dynamic]JSON_Value, SLOTS_PER_BAR, allocator = context.temp_allocator)
		for si in 0 ..< SLOTS_PER_BAR {
			slot_arr[si] = json.String(skill_bar_get(p, bi, si))
		}
		bar_fields := make([dynamic]JSON_Field, 3, allocator = context.temp_allocator)
		bar_fields[0] = JSON_Field{"slots", json.Array(slot_arr)}
		bar_fields[1] = JSON_Field{"x", json.Float(f64(p.skill_bar_pos[bi].x))}
		bar_fields[2] = JSON_Field{"y", json.Float(f64(p.skill_bar_pos[bi].y))}
		bar_obj := build_object(bar_fields[:])
		all_bars[bi] = bar_obj^
		free(bar_obj) // shell node; its map value lives on in all_bars
	}
	v: JSON_Value = json.Array(all_bars)
	out, ok := json_marshal(&v)
	if !ok do return
	defer delete(out) // json_marshal output is heap-allocated
	_ = os.write_entire_file_from_string(path, out)

	// Free the per-bar maps. Only the maps: their "slots" values are
	// temp-arena dynamics that die with the frame arena (delete on them
	// would go through the wrong allocator).
	for i in 0 ..< len(all_bars) {
		if o, o_ok := all_bars[i].(json.Object); o_ok {
			delete(as_map(o))
		}
	}
}
