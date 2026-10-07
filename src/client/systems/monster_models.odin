package systems

// Monster model layer: loads the shipped monster glbs
// (assets/monster/monster_<serialid>_<Name>.glb — 261 of the 588 roster
// entries ship a model; the rest keep their capsule) and plays their
// embedded idle clip. The glbs use the same clip-code namespace as the
// characters (name suffix "0001" = idle), so the clip lookup reuses
// chara_code_of.
//
// All instances of one monster SHARE the model and its animated pose: one
// UpdateModelAnimation per loaded model per frame poses every instance of
// that monster identically. Per-instance poses (walk/chase/attack) need the
// avatar-style per-entity clone and are a follow-up.

import "core:c"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

CLIP_CODE_MONSTER_IDLE :: "0001"

Monster_Model :: struct {
	entry:      ^Model_Entry, // refcounted assets cache handle
	anims:      [^]rl.ModelAnimation,
	anim_count: int,
	idle:       int,   // clip index of the idle code, -1 = none
	anim_time:  f32,   // shared pose clock (seconds into the idle clip)
	valid:      bool,
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
		for i in 0..<m.anim_count {
			if chara_code_of(chara_anim_name(&m.anims[i])) == CLIP_CODE_MONSTER_IDLE {
				m.idle = i
				break
			}
		}
		m.valid = true
		rl.TraceLog(.INFO, "monster: loaded %s (%d clips, idle=%d)",
			assets_cstring(model_file), m.anim_count, m.idle)
	}

	key := strings.clone(model_file)
	monster_cache[key] = m // negatively cached when !valid
	return m
}

// Advance the shared idle pose of every loaded monster model. One call per
// frame; each model costs one UpdateModelAnimation regardless of instance
// count. All instances of a monster animate in lockstep.
monster_models_update :: proc(dt: f32) {
	for _, m in monster_cache {
		if !m.valid || m.idle < 0 do continue
		anim := &m.anims[m.idle]
		frames := f32(anim.keyframeCount)
		if frames <= 0 do continue
		m.anim_time += dt
		frame := m.anim_time * CHARA_ANIM_FPS
		frame = frame - f32(i32(frame / frames)) * frames
		rl.UpdateModelAnimation(m.entry.model, anim^, frame)
	}
}

// Draw one monster instance at the entity transform. Mirrors the avatar
// draw: same +180° yaw offset (same asset pipeline faces +Z) and feet on
// the entity origin.
monster_model_draw :: proc(m: ^Monster_Model, position: rl.Vector3, yaw_rad: f32, tint: rl.Color, scale: f32) {
	if m == nil || !m.valid do return
	axis, angle := euler_y_to_raylib(yaw_rad)
	rl.DrawModelEx(m.entry.model, position, axis, angle + AVATAR_YAW_OFFSET_DEG, {scale, scale, scale}, tint)
}

// Frees the cache; call before assets_destroy at shutdown (afterwards the
// entity scene is already gone).
monster_models_shutdown :: proc() {
	for key, m in monster_cache {
		if m.valid {
			if m.anim_count > 0 do rl.UnloadModelAnimations(m.anims, i32(m.anim_count))
			assets_model_release(m.entry)
		}
		delete_key(&monster_cache, key)
		delete(key)
		free(m)
	}
	delete(monster_cache)
	monster_cache = nil
}
