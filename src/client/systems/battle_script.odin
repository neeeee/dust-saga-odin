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
import "core:encoding/json"
import "core:math"
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
	speed:   f32, // action playback rate for MOTION ops (attack speed)
}

battle_scripts: map[string]^Battle_Script // "<cat>,<model>,<key>"; nil value = known missing
// One playback per acting entity (local player + remotes), keyed by entity id.
battle_playbacks: map[Entity_Id]Battle_Playback

// ── phased actions (bow draw start → hold → release) ──────────────────────

Battle_Phased_Phase :: enum { START, HOLD, RELEASE }

Battle_Phased :: struct {
	phase:      Battle_Phased_Phase,
	start_idx:  int,  // the draw clip — frozen on its last frame while aiming
	hold:       string, // hold clip to loop (attack draws); "" = freeze the draw
	release:    string, // the shot / skill effect
	release_at: f64,    // local clock seconds when the release fires
	skill:      bool, // a Shot-skill draw (its release suppresses a re-exec)
}
phased_actions: map[Entity_Id]Battle_Phased

// When each entity's last phased release fired (local clock seconds): an
// execution packet arriving just after the channel draw loosed must not
// start a second draw (mirrors the local player's re-exec suppress window).
phased_released_at: map[Entity_Id]f64
SHOT_RELEASE_SUPPRESS_S :: 1.5

// Entities whose release fired this frame (drained by gameplay to loose
// arrows on the release frame).
battle_release_events: [dynamic]Entity_Id
battle_logged_first_hold:  bool
battle_logged_first_flush: bool

// Entities currently channeling a cast (CAST_START/CAST_CANCEL broadcasts),
// by expiry in local clock seconds. The sweep in battle_script_update ends
// the loop even when a cancel is lost (disconnect, zone edge cases).
remote_cast_ends: map[Entity_Id]f64
REMOTE_CAST_GRACE_S :: 1.5

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

// Start a script for `entity`; returns it (nil when none exists). A new start
// replaces that entity's playback in flight. `speed` scales MOTION clips.
battle_start :: proc(entity: Entity_Id, category, model_id, key: string, speed: f32) -> ^Battle_Script {
	script := battle_get_script(category, model_id, key)
	if script == nil do return nil
	if phased_actions != nil do delete_key(&phased_actions, entity) // script supersedes a draw
	battle_playbacks[entity] = Battle_Playback{script = script, speed = speed}
	return script
}

// Drop an entity's playback and any phased draw in flight (entity removed /
// playback superseded).
battle_playback_stop :: proc(entity: Entity_Id) {
	if battle_playbacks != nil do delete_key(&battle_playbacks, entity)
	if phased_actions != nil do delete_key(&phased_actions, entity)
}

// Start a phased draw (bow-style): `start` plays one-shot, then the aim holds
// — `hold` looping when the family ships a dedicated hold clip, otherwise the
// draw's last frame frozen (skill channels: the shipped 1864 carries a whole
// nock-and-raise sequence we don't want) — until `hold_ms` elapses and
// `release` plays the shot. `release_lead_ms` fires the release that much
// early (attack cycles lead so the shot reads before the next swing); skill
// channels pass 0 — they must hold until the cast actually completes.
// Returns false when the model doesn't ship the clips — the caller falls
// back to the plain swing path.
battle_start_phased :: proc(entity: Entity_Id, av: ^Chara_Avatar, start, hold, release: string, hold_ms, release_lead_ms: f64, freeze_hold, is_skill: bool) -> bool {
	if av == nil do return false
	if chara_clip(av.cm, start) < 0 || chara_clip(av.cm, release) < 0 do return false
	if !freeze_hold && chara_clip(av.cm, hold) < 0 do return false

	battle_playback_stop(entity) // a fresh draw supersedes script playback
	hold_eff := math.max(hold_ms - release_lead_ms, hold_ms * 0.4)

	chara_avatar_play_action(av, start, false)
	if phased_actions == nil do phased_actions = make(map[Entity_Id]Battle_Phased)
	phased_actions[entity] = Battle_Phased{
		start_idx  = chara_clip(av.cm, start),
		hold       = hold,
		release    = release,
		release_at = f64(now_ms_local()) / 1000.0 + hold_eff / 1000.0,
		skill      = is_skill,
	}
	return true
}

// Advance every phased action: start clip finishes → hold loop; deadline
// passes → release one-shot; release finishes → done.
battle_phased_update :: proc(scene: ^Scene, local_avatar: ^Chara_Avatar) {
	if phased_actions == nil do return
	now := f64(now_ms_local()) / 1000.0
	finished: [dynamic]Entity_Id
	for entity, &pa in phased_actions {
		av := local_avatar
		if entity != scene.player_id {
			av = nil
			idx := find_index(scene, entity)
			if idx >= 0 do av = scene.renderables[idx].avatar
		}
		if av == nil {
			append(&finished, entity) // owner gone
			continue
		}

		if pa.phase != .RELEASE {
			if now >= pa.release_at {
				chara_avatar_play_action(av, pa.release, false)
				pa.phase = .RELEASE
				if pa.skill {
					if phased_released_at == nil do phased_released_at = make(map[Entity_Id]f64)
					phased_released_at[entity] = now
				}
				append(&battle_release_events, entity)
			} else if pa.phase == .START {
				// Switch to the hold JUST BEFORE the draw clip ends: if it
				// auto-clears first, the avatar falls to its locomotion pose
				// for a frame and the hold then blends back up from idle —
				// the sag-to-neutral the cast frames showed.
				frames := f32(anim_keyframe_count(av, pa.start_idx))
				end_frame := f32(av.anim_time) * CHARA_ANIM_FPS
				if (frames > 0 && end_frame >= frames - 2) || av.action_clip < 0 {
					if pa.hold != "" {
						chara_avatar_play_action(av, pa.hold, true)
					} else {
						chara_avatar_freeze_action(av, pa.start_idx)
					}
					pa.phase = .HOLD
				}
			}
		} else if av.action_clip < 0 {
			append(&finished, entity)
		}
	}
	for e in finished do delete_key(&phased_actions, e)
	delete(finished)
}

// True while `entity` has a phased action (draw → hold → release) in flight.
battle_phased_active :: proc(entity: Entity_Id) -> bool {
	if phased_actions == nil do return false
	_, ok := phased_actions[entity]
	return ok
}

// True shortly after `entity`'s phased release fired — a skill execution for
// a Shot-category skill within this window is the packet for the draw that
// just loosed, not a request to draw again.
battle_phased_released_recently :: proc(entity: Entity_Id) -> bool {
	if phased_released_at == nil do return false
	t, ok := phased_released_at[entity]
	if !ok do return false
	return f64(now_ms_local()) / 1000.0 - t < SHOT_RELEASE_SUPPRESS_S
}

// Hand the caller this frame's release events (entity ids); the caller owns
// and frees the returned array.
battle_take_release_events :: proc() -> [dynamic]Entity_Id {
	out := battle_release_events
	battle_release_events = nil
	return out
}

// ── release-synced impact feedback ────────────────────────────────────────
// The local player's ranged damage result is held until the arrow's release
// frame so the floating number and impact sound land with the shot. The
// server stays authoritative and instant — on high ping the DAMAGE packet
// usually arrives after the release anyway and displays immediately, so
// nothing waits on the network twice.

held_impacts: [dynamic]^JSON_Value

// Called from handle_damage: true when the result belongs to the local
// player's phased ranged attack and is held until its release.
battle_hold_local_impact :: proc(ctx: ^Game_Context, data: ^JSON_Value) -> bool {
	if data == nil do return false
	id := ctx.scene.player_id
	if phased_actions == nil do return false
	pa, ok := phased_actions[id]
	if !ok || pa.phase == .RELEASE do return false
	attacker := get_string(obj_of(data^), "attackerId")
	if len(attacker) == 0 do return false
	if string_to_entity_id(attacker) != id do return false
	append(&held_impacts, clone_value(data^)) // caller frees the original
	if !battle_logged_first_hold {
		battle_logged_first_hold = true
		rl.TraceLog(.INFO, "battle_script: holding local impact until arrow release")
	}
	return true
}

// Replay (and free) everything held for the release that just fired.
battle_flush_held_impacts :: proc(ctx: ^Game_Context) {
	if len(held_impacts) == 0 do return
	if !battle_logged_first_flush {
		battle_logged_first_flush = true
		rl.TraceLog(.INFO, "battle_script: flushing %d held impact(s) on release", len(held_impacts))
	}
	for d in held_impacts {
		handle_damage(ctx, d)
		json.destroy_value(d^)
	}
	clear(&held_impacts)
}

// True when impact results are waiting for a release.
battle_held_impacts_pending :: proc() -> bool {
	return len(held_impacts) > 0
}

// Drop held impacts without replaying (zone change / shutdown).
battle_held_impacts_clear :: proc() {
	for d in held_impacts do json.destroy_value(d^)
	clear(&held_impacts)
}

// Advance every running script: fire each owner's ops whose time has come.
// The local player owns no scene entity, so it resolves to `local_avatar`;
// every other owner resolves through the scene. Call once per frame.
battle_script_update :: proc(scene: ^Scene, local_avatar: ^Chara_Avatar, dt: f32) {
	// Phased draws and cast sweeps run even when no script has ever loaded —
	// a bow user never touches the script cache (their attacks are phased),
	// and gating on it here stalled the whole machinery: draws never held or
	// released, and held damage numbers never flushed.
	battle_phased_update(scene, local_avatar)
	battle_cast_sweep(scene)

	if battle_playbacks == nil do return
	finished: [dynamic]Entity_Id
	for entity, &pb in battle_playbacks {
		av := local_avatar
		if entity != scene.player_id {
			av = nil
			idx := find_index(scene, entity)
			if idx >= 0 do av = scene.renderables[idx].avatar
		}
		if av == nil {
			append(&finished, entity) // owner gone — drop the playback
			continue
		}
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
					av.action_speed = pb.speed
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
		if pb.idx >= len(ops) do append(&finished, entity)
	}
	for e in finished do delete_key(&battle_playbacks, e)
	delete(finished)
}

// End remote cast loops whose cast should have finished by now but whose
// CAST_CANCEL / execution animation never arrived.
battle_cast_sweep :: proc(scene: ^Scene) {
	if remote_cast_ends == nil do return
	now := f64(now_ms_local()) / 1000.0
	expired: [dynamic]Entity_Id
	for entity, end_s in remote_cast_ends {
		if now < end_s do continue
		append(&expired, entity)
		if entity == scene.player_id do continue // local player never loops remotely
		idx := find_index(scene, entity)
		if idx < 0 do continue
		battle_cast_stop_visuals(&scene.renderables[idx])
	}
	for e in expired do delete_key(&remote_cast_ends, e)
	delete(expired)
}

// End an entity's channeling pose on whichever model path it renders with.
battle_cast_stop_visuals :: proc(r: ^Renderable) {
	if r == nil do return
	if r.avatar != nil {
		chara_avatar_stop_action(r.avatar)
	} else if r.monster.valid {
		monster_instance_stop(&r.monster)
	}
}

// Track a channeling entity so the sweep can end the loop even when the
// cancel/execution packet is lost.
battle_cast_track :: proc(entity: Entity_Id, cast_time_ms: int) {
	if remote_cast_ends == nil do remote_cast_ends = make(map[Entity_Id]f64)
	remote_cast_ends[entity] = f64(now_ms_local()) / 1000.0 + f64(cast_time_ms) / 1000.0 + REMOTE_CAST_GRACE_S
}

// Remote character began channeling: play exactly what the caster plays —
// the Shot draw sequence for Shot-category skills (Arrow Rain/Storm), the
// weapon family's cast stance (neutral cast loop when the weapon is unknown)
// for everything else — until the execution animation or a cancel replaces
// it. The phased draw is self-terminating (its hold deadline fires the
// release), so only the looping stances are tracked for the lost-packet sweep.
battle_cast_start :: proc(entity: Entity_Id, av: ^Chara_Avatar, cast_time_ms: int, anim_category: string, weapon: Weapon_Kind) {
	if av == nil do return
	if battle_anim_is_shot(anim_category) {
		s, h, r := battle_shot_draw_codes(weapon)
		if battle_start_phased(entity, av, s, h, r, f64(cast_time_ms), 0, false, true) do return
	}
	fam := chara_weapon_family(weapon)
	chara_avatar_play_action_any(av, true, fam.cast_start, CLIP_CODE_CAST_LOOP)
	battle_cast_track(entity, cast_time_ms)
}

// Remote entity's cast was cancelled or interrupted: drop the loop — and any
// phased channel draw in flight, which would otherwise revive into its hold
// and loose at the deadline despite the cancel.
battle_cast_cancel :: proc(entity: Entity_Id, r: ^Renderable) {
	if remote_cast_ends != nil do delete_key(&remote_cast_ends, entity)
	battle_playback_stop(entity)
	battle_cast_stop_visuals(r)
}

// Drop an entity's cast state without touching its avatar (entity removal).
battle_cast_forget :: proc(entity: Entity_Id) {
	if remote_cast_ends != nil do delete_key(&remote_cast_ends, entity)
	if phased_released_at != nil do delete_key(&phased_released_at, entity)
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

// Playback rate that fits the swing into `interval_ms` (0 = native): a clip
// runs frames/FPS seconds; speed it up so it fills the attacker's attack
// interval. Never slows a clip below native.
battle_action_speed :: proc(av: ^Chara_Avatar, code: string, interval_ms: f64) -> f32 {
	if interval_ms <= 0 || av == nil do return 1
	idx := chara_clip(av.cm, code)
	if idx < 0 do return 1
	frames := f32(anim_keyframe_count(av, idx))
	if frames <= 0 do return 1
	speed := (frames / CHARA_ANIM_FPS) / (f32(interval_ms) / 1000.0)
	return math.clamp(speed, 1.0, 4.0)
}

battle_action_speed_any :: proc(av: ^Chara_Avatar, codes: []string, interval_ms: f64) -> f32 {
	for c in codes {
		if chara_clip(av.cm, c) >= 0 do return battle_action_speed(av, c, interval_ms)
	}
	return 1
}

// Auto-attack entry point (local player and remote entities alike). Picks the
// family swing exactly like chara_avatar_play_attack (advancing attack_cycle
// once either way), then plays the model's atk_pc script for that code — its
// motion/se/hit timeline replaces the plain swing — falling back to the bare
// clip when the model ships no script. `interval_ms` scales the swing to the
// attacker's attack speed.
battle_script_start_attack :: proc(entity: Entity_Id, av: ^Chara_Avatar, kind: Weapon_Kind, interval_ms: f64) {
	if av == nil do return
	fam := chara_weapon_family(kind)
	// Bow-style families draw → aim → loose instead of swinging; plain
	// swings remain the fallback when the model lacks the phased clips.
	if fam.ranged_start != "" {
		// attack cycles lead the release so the shot reads before the next
		// swing takes the action slot
		idx := chara_clip(av.cm, fam.ranged_release)
		lead := f64(150)
		if idx >= 0 {
			frames := f32(anim_keyframe_count(av, idx))
			if frames > 0 do lead = f64(math.min(frames / CHARA_ANIM_FPS * 500.0, 400))
		}
		if battle_start_phased(entity, av, fam.ranged_start, fam.ranged_hold, fam.ranged_release, interval_ms, lead, false, false) do return
	}
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

	speed := battle_action_speed(av, code, interval_ms)
	if battle_start(entity, "atk_pc", av.cm.id, code, speed) != nil do return
	chara_avatar_play_action(av, code, false)
	av.action_speed = speed
}

// Skill-execution entry point: resolves the skill's serial id by display
// name, then starts the model's skill_exec script. Returns nil when the name
// isn't in skill.csv or the model has no script (caller falls back).
battle_script_start_skill :: proc(entity: Entity_Id, av: ^Chara_Avatar, skill_name: string) -> ^Battle_Script {
	if av == nil do return nil
	serial, ok := battle_skill_serial(skill_name)
	if !ok do return nil
	key := fmt.tprintf("%d", serial)
	return battle_start(entity, "skill", av.cm.id, key, 1)
}

// Which default execution animation backs a skill whose battle script carries
// no playable motion (or has none at all).
Battle_Skill_Fallback :: enum {
	WEAPON_SWING, // physical damage — the attacker's weapon family
	CAST_ATTACK,  // magical damage — cast finish flourish with attack
	CAST_SUPPORT, // everything else — plain cast finish
}

// Wire name for a skill's sub-category, mirroring the server's `anim`
// category strings (the shipped sub-category → animation mapping).
sub_category_anim_name :: proc "contextless" (sc: Sub_Category) -> string {
	switch sc {
	case .SLASH:         return "Slash"
	case .THRUST:        return "Thrust"
	case .CLEAVE:        return "Cleave"
	case .BASH:          return "Bash"
	case .DEFEND:        return "Block"
	case .SHOT:          return "Shoot"
	case .ASSASSINATION: return "Slash"
	case .TRAP:          return "Throw"
	case .DODGE:         return "Dash"
	case .GRACE:         return "CastHeal"
	case .BLESSING:      return "CastBuff"
	case .EXORCISM:      return "Cast"
	case .HYMN:          return "Cast"
	case .ELEMENTAL:     return "Cast"
	case .INVOCATION:    return "Cast"
	case .DARKNESS:      return "Cast"
	case .CONFUSION:     return "Cast"
	case .ALCHEMY:       return "Cast"
	case .HORSEMANSHIP:  return "Charge"
	case .RACIAL:        return "Attack"
	}
	return ""
}

// Draw/hold/release codes for a Shot-category skill: the family's dedicated
// skill sequence when it ships one (bow 1863/1864 → 1856), else the plain
// ranged draw (crossbow skills loose the normal bolt, 1955).
battle_shot_draw_codes :: proc(kind: Weapon_Kind) -> (start, hold, release: string) {
	fam := chara_weapon_family(kind)
	if fam.skill_start != "" do return fam.skill_start, fam.skill_hold, fam.skill_release
	return fam.ranged_start, fam.ranged_hold, fam.ranged_release
}

// True when the category names a Shot-family skill (bow/crossbow draws).
// The server emits "Shoot" (the TS enum value); the local sub-category
// mapper produces "Shot" — accept both.
battle_anim_is_shot :: proc "contextless" (anim_category: string) -> bool {
	return anim_category == "Shoot" || anim_category == "Shot"
}

// Execution animation for a server-confirmed skill, shared by the local
// player and remote entities: the model's skill_exec battle script plays its
// motion/se timeline when one ships. Otherwise the shipped sub-category
// mapping (`anim_category`: "Slash", "Shot", "CastHeal", …) picks the family
// — weapon swings for melee/shot categories, cast flourishes otherwise —
// falling back to the damage-kind hint when the category is unknown.
// `weapon` is the attacker's equipped weapon kind (remotes without weapon
// data pass .NONE); `interval_ms` times swings to the attacker's attack speed.
battle_play_skill_execution :: proc(entity: Entity_Id, av: ^Chara_Avatar, skill_name: string, fallback: Battle_Skill_Fallback, weapon: Weapon_Kind, anim_category: string, interval_ms: f64) {
	if av == nil do return
	script := battle_script_start_skill(entity, av, skill_name)
	if script != nil && battle_script_has_motion(script, av) do return

	swing := false
	cast_attack := false
	switch anim_category {
	case "Slash", "Thrust", "Cleave", "Bash", "Shot", "Shoot", "Attack":
		swing = true
	case "Cast":
		cast_attack = true
	case "CastHeal", "CastBuff", "Block", "Dash", "Charge", "Roar", "Trip", "Throw":
		// cast-finish family
	case:
		// unknown category — the kind hint decides
		if fallback == .WEAPON_SWING do swing = true
		if fallback == .CAST_ATTACK do cast_attack = true
	}

	fam := chara_weapon_family(weapon)
	if swing {
		// Shot-category skills (arrow rain/storm) draw → aim → loose their
		// own skill draw (bow 1863/64 → 1856), matching the caster's channel;
		// crossbows fall back to the plain ranged draw's bolt. When the cast
		// channel's draw is still in flight (or loosed a beat ago) the
		// execution IS that draw — don't start a second one over it.
		if battle_anim_is_shot(anim_category) {
			if battle_phased_active(entity) || battle_phased_released_recently(entity) do return
			s, h, r := battle_shot_draw_codes(weapon)
			if battle_start_phased(entity, av, s, h, r, interval_ms, 0, false, true) do return
		}
		battle_script_start_attack(entity, av, weapon, interval_ms)
		return
	}

	codes := [2]string{fam.cast_finish, CLIP_CODE_CAST_END}
	if cast_attack do codes = [2]string{fam.cast_finish_attack, CLIP_CODE_CAST_END_ATTACK}
	chara_avatar_play_action_any(av, false, codes[0], codes[1])
	av.action_speed = battle_action_speed_any(av, codes[:], interval_ms)
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
	if battle_playbacks != nil {
		clear(&battle_playbacks)
		delete(battle_playbacks)
		battle_playbacks = nil
	}

	if remote_cast_ends != nil {
		clear(&remote_cast_ends)
		delete(remote_cast_ends)
		remote_cast_ends = nil
	}

	if phased_actions != nil {
		clear(&phased_actions)
		delete(phased_actions)
		phased_actions = nil
	}

	if phased_released_at != nil {
		clear(&phased_released_at)
		delete(phased_released_at)
		phased_released_at = nil
	}

	if battle_release_events != nil {
		delete(battle_release_events)
		battle_release_events = nil
	}

	battle_held_impacts_clear()

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
