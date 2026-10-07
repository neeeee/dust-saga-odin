package systems

// Battle-script interpreter. The shipped 1,072 battle scripts
// (assets/battle_script/{atk_pc,skill,item}/*.csv) are per-model UTF-16LE
// timelines of <motion>/<wait>/<fx>/<se>/<hit> ops that time attacks and
// skill executions: animation clip codes, sound paths, effect references and
// the damage marker. This module decodes and parses them lazily, then plays
// them back on the local avatar:
//
//   MOTION  → chara_avatar_play_action with the same 4-digit clip codes the
//             client already uses (one-shot, returns to locomotion).
//   SE      → audio_play at the scripted time (path minus the leading "./").
//   FX      → resolves type/id through fx.csv; logged stub until the .vra
//             particle renderer exists (next round).
//   HIT     → no-op marker; the server's DAMAGE packet stays authoritative
//             for impact feedback.
//   others  → parsed and skipped with a one-time log per op name
//             (reset_motion is redundant — our one-shot actions already
//             return to locomotion; motion_type uses 2-digit generic motion
//             ids with no clip mapping in the client yet).
//
// item_use scripts are deferred until the client has an in-world item-use
// flow; their parse path already works (same op syntax), only the trigger is
// missing.
//
// File naming: "<category>[<model_int*1000 as %07d>_<key>].csv" where key is
// the attack clip code (atk_pc) or the skill.csv serial id (skill), e.g.
// model 011 attack 1055 → atk_pc/atk_pc[0011000_1055].csv.

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import rl "vendor:raylib"

// ── op model ──────────────────────────────────────────────────────────────

Battle_Op_Kind :: enum {
	MOTION,  // play clip `code` (one-shot)
	FX,      // effect reference — stub, logged once
	SE,      // play `se_path` at `at`
	HIT,     // damage timing marker — no-op
	SKIPPED, // parsed but not playable this round
}

Battle_Op :: struct {
	kind:    Battle_Op_Kind,
	at:      f32,   // seconds into the script when the op fires
	code:    string, // MOTION clip code, heap-owned
	se_path: string, // SE path (asset-root-relative), heap-owned
	fx_type: int,
	fx_id:   int,
}

Battle_Script :: struct {
	ops:   [dynamic]Battle_Op,
	total: f32, // full timeline duration (debug aid)
}

Battle_Playback :: struct {
	script:  ^Battle_Script,
	idx:     int,
	elapsed: f32,
}

battle_scripts: map[string]^Battle_Script // "<cat>,<model>,<key>"; nil value = known missing
battle_playback: Battle_Playback

// One-time verification logs (see battle script plan.md).
battle_logged_first_load:    bool
battle_logged_first_fallback: bool
battle_logged_fx_stub:       bool
battle_unknown_ops:          map[string]bool

// ── data tables ───────────────────────────────────────────────────────────

skill_serials:        map[string]int // display name -> skill.csv serial id
skill_serials_loaded: bool

fx_paths:        map[string]string // "<type>,<id>" -> .vra path
fx_paths_loaded: bool

// Serial id for a skill display name ("Provoke", "Heave", …). Loads
// assets/skill.csv (UTF-16LE, '#' comment headers, col 1 = serial, col 2 =
// name) on first use. First row wins on duplicate names.
battle_skill_serial :: proc(name: string) -> (int, bool) {
	if !skill_serials_loaded {
		skill_serials_loaded = true
		skill_serials = make(map[string]int)
		data, err := os.read_entire_file_from_path("assets/skill.csv", allocator = context.allocator)
		if err != nil {
			rl.TraceLog(.WARNING, "battle_script: missing assets/skill.csv")
			return 0, false
		}
		defer delete(data)
		text := decode_utf16_file(data)
		defer delete(text)
		pos := 0
		for {
			line, next_pos, ok := battle_next_line(text, pos)
			if !ok do break
			pos = next_pos
			if len(line) == 0 || line[0] == '#' do continue
			serial_str := csv_field_at(line, 0)
			name_str := battle_trim(csv_field_at(line, 1))
			serial, parsed := strconv.parse_int(serial_str, 10)
			if !parsed || len(name_str) == 0 do continue
			if _, exists := skill_serials[name_str]; exists do continue
			key := strings.clone(name_str)
			skill_serials[key] = serial
		}
		rl.TraceLog(.INFO, "battle_script: skill.csv loaded (%d skills)", len(skill_serials))
	}
	serial, ok := skill_serials[name]
	return serial, ok
}

// fx.csv row for "<fx>,type,id": TYPE,ID,PATH,#comment (UTF-16LE, '#' section
// banners). Loads the table on first use. The returned path slices into the
// owned map value.
battle_fx_path :: proc(fx_type, fx_id: int) -> (string, bool) {
	if !fx_paths_loaded {
		fx_paths_loaded = true
		fx_paths = make(map[string]string)
		data, err := os.read_entire_file_from_path("assets/fx.csv", allocator = context.allocator)
		if err != nil {
			rl.TraceLog(.WARNING, "battle_script: missing assets/fx.csv")
			return "", false
		}
		defer delete(data)
		text := decode_utf16_file(data)
		defer delete(text)
		pos := 0
		for {
			line, next_pos, ok := battle_next_line(text, pos)
			if !ok do break
			pos = next_pos
			if len(line) == 0 || line[0] == '#' do continue
			type_str := csv_field_at(line, 0)
			id_str := csv_field_at(line, 1)
			path_str := battle_trim(csv_field_at(line, 2))
			ft, ok1 := strconv.parse_int(type_str, 10)
			fid, ok2 := strconv.parse_int(id_str, 10)
			if !ok1 || !ok2 || len(path_str) == 0 do continue
			key := fmt.tprintf("%d,%d", ft, fid)
			if _, exists := fx_paths[key]; exists do continue
			owned_key := strings.clone(key)
			owned_path := strings.clone(path_str)
			fx_paths[owned_key] = owned_path
		}
		rl.TraceLog(.INFO, "battle_script: fx.csv loaded (%d entries)", len(fx_paths))
	}
	key := fmt.tprintf("%d,%d", fx_type, fx_id)
	path, ok := fx_paths[key]
	return path, ok
}

// ── script cache + loading ────────────────────────────────────────────────

battle_script_path :: proc(category, model_id, key: string) -> (string, bool) {
	mi, ok := strconv.parse_int(model_id, 10)
	if !ok do return "", false
	prefix := fmt.tprintf("%07d", mi * 1000)
	switch category {
	case "atk_pc":
		return fmt.tprintf("assets/battle_script/atk_pc/atk_pc[%s_%s].csv", prefix, key), true
	case "skill":
		return fmt.tprintf("assets/battle_script/skill/skill_exec[%s_%s].csv", prefix, key), true
	}
	return "", false
}

// Cached script lookup; nil result is negatively cached, so a missing script
// costs one failed file read ever.
battle_get_script :: proc(category, model_id, key: string) -> ^Battle_Script {
	if battle_scripts == nil do battle_scripts = make(map[string]^Battle_Script)
	lookup := fmt.tprintf("%s,%s,%s", category, model_id, key)
	if s, ok := battle_scripts[lookup]; ok do return s

	s := battle_load_script(category, model_id, key)
	owned := strings.clone(lookup)
	battle_scripts[owned] = s

	if s != nil {
		if !battle_logged_first_load {
			battle_logged_first_load = true
			rl.TraceLog(.INFO, "battle_script: first script loaded (%s %s/%s: %d ops, %.2fs)",
				assets_cstring(category), assets_cstring(model_id), assets_cstring(key),
				len(s.ops), s.total)
		}
	} else {
		if !battle_logged_first_fallback {
			battle_logged_first_fallback = true
			rl.TraceLog(.INFO, "battle_script: first fallback — no script for %s %s/%s",
				assets_cstring(category), assets_cstring(model_id), assets_cstring(key))
		}
	}
	return s
}

battle_load_script :: proc(category, model_id, key: string) -> ^Battle_Script {
	path, ok := battle_script_path(category, model_id, key)
	if !ok do return nil
	data, err := os.read_entire_file_from_path(path, allocator = context.allocator)
	if err != nil do return nil
	defer delete(data)
	text := decode_utf16_file(data)
	defer delete(text)
	return battle_parse_script(text)
}

battle_parse_script :: proc(text: string) -> ^Battle_Script {
	s := new(Battle_Script)
	t := f32(0)
	pos := 0
	for {
		line, next_pos, ok := battle_next_line(text, pos)
		if !ok do break
		pos = next_pos
		if len(line) == 0 || line[0] != '<' do continue
		close := strings.index_byte(line, '>')
		if close <= 1 do continue
		name := line[1:close]
		args := line[min(close + 1, len(line)):]
		if len(args) > 0 && args[0] == ',' do args = args[1:]

		// Numeric args after the motion code (unk, 50.0, 1.0) have unverified
		// meaning; clips play one-shot at native speed for now.
		switch name {
		case "motion":
			code := csv_field_at(args, 0)
			if len(code) > 0 {
				append(&s.ops, Battle_Op{kind = .MOTION, at = t, code = strings.clone(code)})
			}
		case "wait":
			v, ok := strconv.parse_f32(csv_field_at(args, 0))
			if ok do t += v
		case "fx":
			ft, ok1 := strconv.parse_int(csv_field_at(args, 0), 10)
			fid, ok2 := strconv.parse_int(csv_field_at(args, 1), 10)
			if ok1 && ok2 {
				append(&s.ops, Battle_Op{kind = .FX, at = t, fx_type = ft, fx_id = fid})
			}
		case "se":
			p := csv_field_at(args, 0)
			if strings.has_prefix(p, "./") do p = p[2:]
			if len(p) > 0 {
				append(&s.ops, Battle_Op{kind = .SE, at = t, se_path = strings.clone(p)})
			}
		case "hit":
			append(&s.ops, Battle_Op{kind = .HIT, at = t})
		case:
			battle_note_unknown_op(name)
		}
	}
	s.total = t
	if len(s.ops) == 0 {
		delete(s.ops)
		free(s)
		return nil
	}
	return s
}

battle_note_unknown_op :: proc(name: string) {
	if battle_unknown_ops == nil do battle_unknown_ops = make(map[string]bool)
	if battle_unknown_ops[name] do return
	battle_unknown_ops[name] = true
	rl.TraceLog(.INFO, "battle_script: skipping op <%s> (not supported yet)", assets_cstring(name))
}

// ── playback ──────────────────────────────────────────────────────────────

// Start a script; returns it (nil when none exists). A new start replaces any
// playback in flight.
battle_start :: proc(category, model_id, key: string) -> ^Battle_Script {
	script := battle_get_script(category, model_id, key)
	if script == nil do return nil
	battle_playback.script = script
	battle_playback.idx = 0
	battle_playback.elapsed = 0
	return script
}

// Advance the running script: fire every op whose time has come. Call once
// per frame with the local avatar.
battle_script_update :: proc(av: ^Chara_Avatar, dt: f32) {
	pb := &battle_playback
	if pb.script == nil do return
	pb.elapsed += dt

	ops := pb.script.ops
	for pb.idx < len(ops) {
		op := &ops[pb.idx]
		if op.at > pb.elapsed do break
		pb.idx += 1
		switch op.kind {
		case .MOTION:
			if av != nil && chara_clip(av.cm, op.code) >= 0 {
				chara_avatar_play_action(av, op.code, false)
			}
		case .SE:
			audio_play(op.se_path, 1.0)
		case .FX:
			if !battle_logged_fx_stub {
				battle_logged_fx_stub = true
				if path, ok := battle_fx_path(op.fx_type, op.fx_id); ok {
					rl.TraceLog(.INFO, "battle_script: fx stub type=%d id=%d -> %s",
						op.fx_type, op.fx_id, assets_cstring(path))
				} else {
					rl.TraceLog(.INFO, "battle_script: fx stub type=%d id=%d (no fx.csv row)",
						op.fx_type, op.fx_id)
				}
			}
		case .HIT, .SKIPPED:
			// HIT: the server's DAMAGE packet stays authoritative for impact
			// feedback. SKIPPED: parsed but not playable this round.
		}
	}
	if pb.idx >= len(ops) do pb.script = nil
}

// True when the script carries a motion the model can actually play — used
// by the skill path to decide whether the default execution animation should
// still run underneath a motionless (fx/se-only) script.
battle_script_has_motion :: proc(script: ^Battle_Script, av: ^Chara_Avatar) -> bool {
	if script == nil || av == nil do return false
	for &op in script.ops {
		if op.kind == .MOTION && chara_clip(av.cm, op.code) >= 0 do return true
	}
	return false
}

// Auto-attack entry point. Picks the family swing exactly like
// chara_avatar_play_attack (advancing attack_cycle once either way), then
// plays the model's atk_pc script for that code — its motion/se/hit timeline
// replaces the plain swing — falling back to the bare clip when the model
// ships no script.
battle_script_start_attack :: proc(av: ^Chara_Avatar, kind: Weapon_Kind) {
	if av == nil do return
	fam := chara_weapon_family(kind)
	family := [3]string{fam.a1, fam.a2, fam.a3}
	codes: [3]string
	n := 0
	for c in family {
		if chara_clip(av.cm, c) >= 0 {
			codes[n] = c
			n += 1
		}
	}
	if n == 0 do return
	code := codes[av.attack_cycle % n]
	av.attack_cycle += 1

	if battle_start("atk_pc", av.cm.id, code) != nil do return
	chara_avatar_play_action(av, code, false)
}

// Skill-execution entry point: resolves the skill's serial id by display
// name, then starts the model's skill_exec script. Returns nil when the name
// isn't in skill.csv or the model has no script (caller falls back).
battle_script_start_skill :: proc(av: ^Chara_Avatar, skill_name: string) -> ^Battle_Script {
	if av == nil do return nil
	serial, ok := battle_skill_serial(skill_name)
	if !ok do return nil
	key := fmt.tprintf("%d", serial)
	return battle_start("skill", av.cm.id, key)
}

// ── shutdown ──────────────────────────────────────────────────────────────

battle_script_shutdown :: proc() {
	if battle_scripts != nil {
		for _, s in battle_scripts {
			if s == nil do continue
			for &op in s.ops {
				if op.code != "" do delete(op.code)     // heap-cloned at parse
				if op.se_path != "" do delete(op.se_path)
			}
			delete(s.ops)
			free(s)
		}
		for key in battle_scripts do delete(key)
		delete(battle_scripts)
		battle_scripts = nil
	}
	battle_playback.script = nil
	battle_playback.idx = 0
	battle_playback.elapsed = 0

	if fx_paths != nil {
		for key, path in fx_paths {
			delete(key)
			delete(path)
		}
		delete(fx_paths)
		fx_paths = nil
	}
	fx_paths_loaded = false

	if skill_serials != nil {
		for key in skill_serials do delete(key)
		delete(skill_serials)
		skill_serials = nil
	}
	skill_serials_loaded = false

	if battle_unknown_ops != nil {
		for key in battle_unknown_ops do delete(key)
		delete(battle_unknown_ops)
		battle_unknown_ops = nil
	}
}

// ── text helpers ──────────────────────────────────────────────────────────

// Decode a UTF-16LE + BOM file (every shipped script/CSV) into an owned UTF-8
// string; files without the BOM are copied through as-is (ASCII/UTF-8). The
// caller owns and must delete the result.
decode_utf16_file :: proc(data: []u8) -> string {
	if !(len(data) >= 2 && data[0] == 0xFF && data[1] == 0xFE) {
		raw := make([]u8, len(data), context.allocator)
		copy(raw, data)
		return string(raw)
	}

	out := make([dynamic]u8, 0, len(data) / 2, context.allocator)
	i := 2
	for i + 1 < len(data) {
		u := u16(data[i]) | (u16(data[i + 1]) << 8)
		i += 2

		r: rune
		if u >= 0xD800 && u <= 0xDBFF {
			// High surrogate: pair with the next low surrogate or substitute.
			if i + 1 < len(data) {
				lo := u16(data[i]) | (u16(data[i + 1]) << 8)
				if lo >= 0xDC00 && lo <= 0xDFFF {
					r = 0x10000 + ((rune(u) - 0xD800) << 10) + (rune(lo) - 0xDC00)
					i += 2
				} else {
					r = 0xFFFD
				}
			} else {
				r = 0xFFFD
			}
		} else if u >= 0xDC00 && u <= 0xDFFF {
			r = 0xFFFD // lone low surrogate
		} else {
			r = rune(u)
		}
		battle_append_rune(&out, r)
	}

	res := make([]u8, len(out), context.allocator)
	copy(res, out[:])
	delete(out)
	return string(res)
}

battle_append_rune :: proc(out: ^[dynamic]u8, r: rune) {
	switch {
	case r <= 0x7F:
		append(out, u8(r))
	case r <= 0x7FF:
		append(out, u8(0xC0 | (r >> 6)))
		append(out, u8(0x80 | (r & 0x3F)))
	case r <= 0xFFFF:
		append(out, u8(0xE0 | (r >> 12)))
		append(out, u8(0x80 | ((r >> 6) & 0x3F)))
		append(out, u8(0x80 | (r & 0x3F)))
	case:
		append(out, u8(0xF0 | (r >> 18)))
		append(out, u8(0x80 | ((r >> 12) & 0x3F)))
		append(out, u8(0x80 | ((r >> 6) & 0x3F)))
		append(out, u8(0x80 | (r & 0x3F)))
	}
}

// Line reader over CRLF/LF text: returns the line at `pos` (a slice view
// into `text`, '\r' stripped) and the position of the next line. No
// allocation.
battle_next_line :: proc(text: string, pos: int) -> (line: string, next_pos: int, ok: bool) {
	if pos >= len(text) do return "", pos, false
	end := pos
	for end < len(text) && text[end] != '\n' {
		end += 1
	}
	line = text[pos:end]
	if len(line) > 0 && line[len(line) - 1] == '\r' do line = line[:len(line) - 1]
	return line, end + 1, true
}

// Field `want` (0-based) of a CSV line, as a slice view into `s` — no
// allocation. Handles double-quoted fields with the simple toggle rule: any
// comma inside quotes doesn't split. (Escaped "" pairs at a field end can
// misparse, but every field this reads — ids, names, paths — is plain.)
csv_field_at :: proc(s: string, want: int) -> string {
	field := 0
	in_quotes := false
	start := 0
	i := 0
	for i <= len(s) {
		if i < len(s) && s[i] == '"' {
			in_quotes = !in_quotes
		} else if i == len(s) || s[i] == ',' && !in_quotes {
			if field == want do return s[start:i]
			field += 1
			start = i + 1
			if field > want do break
		}
		i += 1
	}
	return ""
}

battle_trim :: proc(s: string) -> string {
	if len(s) == 0 do return s
	b, e := 0, len(s)
	for b < e && (s[b] == ' ' || s[b] == '\t') do b += 1
	for e > b && (s[e - 1] == ' ' || s[e - 1] == '\t') do e -= 1
	return s[b:e]
}
