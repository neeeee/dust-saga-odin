package systems

// Runtime weapon-seat overrides from sheath_tuning.json (written by
// tools/sheath_tune.odin, hand-editable). Each entry overrides the baked seat
// for its weapon kind; absent entries — or a missing file — fall back to the
// baked constants in chara_models.odin, so a partially tuned table is fine.
//
// The `*_q` quaternions are authoritative (the tuner's freeform rotation
// writes them). The `*_e` euler-degree fields (XYZ order) are the readable
// fallback: entries with no `*_q` — older files, hand edits — convert from
// euler.
//
// The file is re-polled a couple times a second from the weapon draw path, so
// edits land in the running game (and the screenshot probes) without a
// restart.

import "core:encoding/json"
import "core:math"
import "core:os"
import rl "vendor:raylib"

Tuned_Seats :: struct {
	sheath_t: rl.Vector3,    // Bip01-relative carry translation
	sheath_q: rl.Quaternion, // carry orientation
	drawn_t:  rl.Vector3,    // right-hand grip translation
	drawn_q:  rl.Quaternion, // drawn grip orientation
}

chara_tuned:       map[Weapon_Kind]Tuned_Seats
chara_tuned_check: f64 // next rl.GetTime() at which the file is re-polled
chara_tuned_count: int // last loaded entry count, for change logging

chara_tuned_kind :: proc(name: string) -> Weapon_Kind {
	switch name {
	case "wand1h":   return .WAND
	case "sword1h":  return .SWORD
	case "axe1h":    return .AXE
	case "club1h":   return .BLUNT
	case "dagger":   return .DAGGER
	case "staff":    return .STAFF
	case "sword2h":  return .TWO_HANDED_SWORD
	case "axe2h":    return .TWO_HANDED_AXE
	case "hammer2h": return .TWO_HANDED_BLUNT
	case "spear2h":  return .TWO_HANDED_SPEAR
	case "lance":    return .SPEAR
	case "bow":      return .BOW
	case "crossbow": return .CROSSBOW
	case "claw":     return .KNUCKLES
	}
	return .NONE
}

// Re-reads sheath_tuning.json at most twice a second.
chara_tuning_tick :: proc() {
	now := rl.GetTime()
	if now < chara_tuned_check do return
	chara_tuned_check = now + 0.5
	chara_tuning_reload()
}

chara_tuning_reload :: proc() -> bool {
	data, err := os.read_entire_file_from_path("sheath_tuning.json", allocator = context.allocator)
	if err != nil {
		delete(chara_tuned)
		chara_tuned = nil
		chara_tuned_count = 0
		return false
	}
	defer delete(data)

	root, parsed := json_parse(data)
	if !parsed do return false
	defer json.destroy_value(root)

	tuned := make(map[Weapon_Kind]Tuned_Seats)
	for name, v in as_map(obj_of(root)) {
		kind := chara_tuned_kind(name)
		if kind == .NONE do continue
		e := obj_of(v)
		sheath_q := tuned_quat(e, "sheath_q")
		if tuned_quat_is_zero(sheath_q) {
			sheath_q = chara_euler_deg_to_quat(tuned_vec3(get_array(e, "sheath_e")))
		}
		drawn_q := tuned_quat(e, "drawn_q")
		if tuned_quat_is_zero(drawn_q) {
			drawn_q = chara_euler_deg_to_quat(tuned_vec3(get_array(e, "drawn_e")))
		}
		tuned[kind] = Tuned_Seats{
			sheath_t = tuned_vec3(get_array(e, "sheath_t")),
			sheath_q = sheath_q,
			drawn_t  = tuned_vec3(get_array(e, "drawn_t")),
			drawn_q  = drawn_q,
		}
	}
	delete(chara_tuned)
	chara_tuned = tuned
	if len(tuned) != chara_tuned_count {
		chara_tuned_count = len(tuned)
		rl.TraceLog(.INFO, "chara: sheath_tuning.json loaded (%d seat overrides)", chara_tuned_count)
	}
	return true
}

tuned_vec3 :: proc(a: JSON_Array) -> rl.Vector3 {
	d := as_dyn(a)
	v: rl.Vector3
	if len(d) > 0 do v.x = f32(number_of(d[0]))
	if len(d) > 1 do v.y = f32(number_of(d[1]))
	if len(d) > 2 do v.z = f32(number_of(d[2]))
	return v
}

tuned_quat :: proc(o: JSON_Object, key: string) -> rl.Quaternion {
	d := as_dyn(get_array(o, key))
	q: rl.Quaternion
	if len(d) > 0 do q.x = f32(number_of(d[0]))
	if len(d) > 1 do q.y = f32(number_of(d[1]))
	if len(d) > 2 do q.z = f32(number_of(d[2]))
	if len(d) > 3 do q.w = f32(number_of(d[3]))
	return q
}

// A json-absent quaternion reads back all zeros — the "missing" marker.
tuned_quat_is_zero :: proc "contextless" (q: rl.Quaternion) -> bool {
	return q.x == 0 && q.y == 0 && q.z == 0 && q.w == 0
}

// XYZ-intrinsic euler degrees -> quaternion, identical convention to the
// tuner's historical euler fields (so old sheath_tuning.json entries keep
// working through the *_e fallback).
chara_euler_deg_to_quat :: proc "contextless" (e: rl.Vector3) -> rl.Quaternion {
	d := math.PI / 180.0
	ex, ey, ez := f64(e.x), f64(e.y), f64(e.z)
	cx := math.cos(ex * d * 0.5); sx := math.sin(ex * d * 0.5)
	cy := math.cos(ey * d * 0.5); sy := math.sin(ey * d * 0.5)
	cz := math.cos(ez * d * 0.5); sz := math.sin(ez * d * 0.5)
	return rl.Quaternion(quaternion(
		x = sx * cy * cz - cx * sy * sz,
		y = cx * sy * cz + sx * cy * sz,
		z = cx * cy * sz - sx * sy * cz,
		w = cx * cy * cz + sx * sy * sz))
}
