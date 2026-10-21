package systems

// Monster model layer: loads the shipped monster glbs
// (assets/monster/monster_<serialid>_<Name>.glb — 261 of the 588 roster
// entries ship a model; the rest keep their capsule) and poses per-entity
// animation state against the shared species model. The glbs use the same
// clip-code namespace as the characters (animation-name suffix, e.g.
// "0001" = idle, "0155-0157" attack swings, "0171"/"0172" cast loop/end),
// so clip lookup reuses chara_code_of.
//
// Per-entity posing without per-entity GPU state: raylib 6 uploads meshes at
// LoadModel and this machine's old driver crashes on mesh re-uploads/unloads
// (clone → UploadMesh warns "already loaded"; UnloadMesh of fresh clones
// faults the driver), so instances do NOT clone the model. Each entity owns
// only a Monster_Instance — clip clock + applied pose — and monster_model_draw
// re-poses the shared model immediately before drawing it, the same trick as
// the chara armor pieces. Pose+draw are adjacent, so every instance renders
// its own pose.
//
// No battle scripts ship for monster models; skill playback is direct
// clip-code playback (see monster_play_skill_execution).

import "core:c"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

CLIP_CODE_MONSTER_IDLE      :: "0001"
CLIP_CODE_MONSTER_CAST_LOOP :: "0171"
CLIP_CODE_MONSTER_CAST_END  :: "0172"

// Basic attack swings, same xx55-57 convention as the chara weapon families.
monster_swing_codes := [3]string{"0155", "0156", "0157"}

Monster_Model :: struct {
	entry:      ^Model_Entry,   // refcounted assets cache handle
	anims:      [^]rl.ModelAnimation,
	anim_count: int,
	idle:       int,            // clip index of the idle code, -1 = none
	clips:      map[string]int, // clip code → anim index
	valid:      bool,
}

// Per-entity animation state against the shared species model (by value in
// Renderable, so entity removal needs no cleanup). One instance of a species
// poses the shared model per frame at draw time.
Monster_Instance :: struct {
	base:         ^Monster_Model, // shared cache entry (outlives the scene)
	clip:         int,            // action clip (swing/cast), -1 = idle
	clip_loop:    bool,
	anim_time:    f32,            // seconds into the current clip
	applied_clip: int,            // clip of the last advanced pose, -1 = none
	applied_frame: f32,
	swing_cycle:  int,            // skill swings played — cycles 0155→0156→0157
	valid:        bool,
}

monster_cache: map[string]^Monster_Model

// Acquire (load on first use) a monster model by its modelFile reference
// ("monster/monster_21201_Kobold.glb"). Failed loads are negatively cached
// so per-spawn calls can't retry-spam. The CACHE holds the single assets
// reference for the whole session (like the chara cache), so entities never
// release — see monster_models_shutdown.
monster_model_acquire :: proc(model_file: string) -> ^Monster_Model {
	if monster_cache == nil do monster_cache = make(map[string]^Monster_Model)
	if m, ok := monster_cache[model_file]; ok do return m

	m := new(Monster_Model)
	m.idle = -1

	glb_path := fmt.tprintf("assets/%s", model_file)
	entry := assets_model_acquire(glb_path)
	if entry != nil {
		m.entry = entry
		anim_count: c.int = 0
		m.anims = rl.LoadModelAnimations(assets_cstring(glb_path), &anim_count)
		m.anim_count = int(anim_count)
		m.clips = make(map[string]int)
		for i in 0..<m.anim_count {
			code := chara_code_of(chara_anim_name(&m.anims[i]))
			if _, exists := m.clips[code]; exists do continue
			m.clips[strings.clone(code)] = i
			if code == CLIP_CODE_MONSTER_IDLE do m.idle = i
		}
		m.valid = true
		rl.TraceLog(.INFO, "monster: loaded %s (%d clips, idle=%d)",
			assets_cstring(model_file), m.anim_count, m.idle)
	}

	key := strings.clone(model_file)
	monster_cache[key] = m // negatively cached when !valid
	return m
}

// Fresh per-entity animation state for a species model.
monster_instance_init :: proc(base: ^Monster_Model) -> Monster_Instance {
	mi := Monster_Instance{base = base, clip = -1, applied_clip = -1}
	if base != nil do mi.valid = base.valid
	return mi
}

// ── clip playback ────────────────────────────────────────────────────────

// Play a clip code on an instance. False when the species doesn't ship the
// code (the caller falls back); a playing clip replaces whatever ran.
monster_instance_play :: proc(mi: ^Monster_Instance, code: string, loop: bool) -> bool {
	if mi == nil || !mi.valid do return false
	idx, ok := mi.base.clips[code]
	if !ok do return false
	mi.clip = idx
	mi.clip_loop = loop
	mi.anim_time = 0
	return true
}

// Leave any action clip; the instance returns to its idle pose.
monster_instance_stop :: proc(mi: ^Monster_Instance) {
	if mi == nil do return
	mi.clip = -1
	mi.clip_loop = false
	mi.anim_time = 0
}

// Advance one instance's animation clock by dt: the action clip while one
// plays (one-shots fall back into the idle when they run out), the idle
// otherwise. The pose itself is applied at draw time (monster_model_draw).
monster_instance_update :: proc(mi: ^Monster_Instance, dt: f32) {
	if mi == nil || !mi.valid || mi.base == nil do return
	idx := mi.clip
	if idx < 0 do idx = mi.base.idle
	if idx < 0 || idx >= mi.base.anim_count do return
	anim := &mi.base.anims[idx]
	frames := f32(anim.keyframeCount)
	if frames <= 0 do return

	mi.anim_time += dt
	frame := mi.anim_time * CHARA_ANIM_FPS

	if mi.clip >= 0 && !mi.clip_loop && frame >= frames {
		monster_instance_stop(mi)
		if mi.base.idle < 0 do return
		idx = mi.base.idle
		frames = f32(mi.base.anims[idx].keyframeCount)
		if frames <= 0 do return
		frame = 0
	} else {
		frame = frame - f32(i32(frame / frames)) * frames // wrap looping clips
	}
	mi.applied_clip = idx
	mi.applied_frame = frame
}

// ── skill presentation ───────────────────────────────────────────────────

// Remote monster began channeling a skill: loop the cast stance (or, for
// species without the cast clips, the first swing as a stand-in tell).
monster_cast_start :: proc(mi: ^Monster_Instance) {
	if mi == nil do return
	if !monster_instance_play(mi, CLIP_CODE_MONSTER_CAST_LOOP, true) {
		monster_instance_play(mi, monster_swing_codes[0], true)
	}
}

// Skill execution for a monster entity: physical skills cycle the three
// attack swings; magical and support skills play the cast-end flourish.
// (No battle scripts ship for monster models — direct clip playback.)
monster_play_skill_execution :: proc(mi: ^Monster_Instance, kind: string) {
	if mi == nil do return
	if kind == "physical" {
		code := monster_swing_codes[mi.swing_cycle % len(monster_swing_codes)]
		mi.swing_cycle += 1
		monster_instance_play(mi, code, false)
	} else {
		if !monster_instance_play(mi, CLIP_CODE_MONSTER_CAST_END, false) {
			code := monster_swing_codes[mi.swing_cycle % len(monster_swing_codes)]
			mi.swing_cycle += 1
			monster_instance_play(mi, code, false)
		}
	}
}

// Draw one monster instance at the entity transform: re-pose the shared
// model with this instance's applied pose immediately before the draw so
// each instance renders independently (mirrors the avatar draw's +180° yaw
// offset and feet-on-origin placement).
monster_model_draw :: proc(mi: ^Monster_Instance, position: rl.Vector3, yaw_rad: f32, tint: rl.Color, scale: f32) {
	if mi == nil || !mi.valid || mi.base == nil do return
	if mi.applied_clip >= 0 && mi.applied_clip < mi.base.anim_count {
		rl.UpdateModelAnimation(
			mi.base.entry.model,
			mi.base.anims[mi.applied_clip],
			mi.applied_frame,
		)
	}
	axis, angle := euler_y_to_raylib(yaw_rad)
	rl.DrawModelEx(mi.base.entry.model, position, axis, angle + AVATAR_YAW_OFFSET_DEG, {scale, scale, scale}, tint)
}

// Frees the cache; call before assets_destroy at shutdown (afterwards the
// entity scene is already gone).
monster_models_shutdown :: proc() {
	for key, m in monster_cache {
		if m.valid {
			if m.anim_count > 0 do rl.UnloadModelAnimations(m.anims, i32(m.anim_count))
			if m.clips != nil {
				for code in m.clips do delete(code)
				delete(m.clips)
			}
			assets_model_release(m.entry)
		}
		delete_key(&monster_cache, key)
		delete(key)
		free(m)
	}
	delete(monster_cache)
	monster_cache = nil
}
