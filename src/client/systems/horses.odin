package systems

// Horse mount layer: loads the shipped horse glbs (assets/horses/
// horse_<coat>_<barding>.glb — 37 coats × up to 8 barding variants; every file
// carries the same three clips, idle "0001" / walk "0015" / run "0018", in the
// shared clip-code namespace) and poses per-rider animation state against the
// shared model — the exact Monster_Instance pattern: instances never clone the
// model (this machine's driver crashes on mesh re-uploads), each rider owns
// only a clip clock, and horse_model_draw re-poses the shared model
// immediately before drawing it, so pose+draw adjacency keeps every instance
// independent.
//
// The rider is NOT attached to a bone — it renders at the player entity's
// transform with a fixed seat offset (see HORSE_RIDER_* below), and plays the
// characters' own mounted_* clips (0201/0217/…, 3xxx mounted weapon families
// — see chara_models/battle_script), so horses and riders can never desync
// poses; the horse simply mirrors its rider's gait.

import "core:c"
import "core:fmt"
import "core:math"
import "core:strings"
import rl "vendor:raylib"

CLIP_CODE_HORSE_IDLE :: "0001"
CLIP_CODE_HORSE_WALK :: "0015"
CLIP_CODE_HORSE_RUN  :: "0018"

// Seat of the rider over the horse, calibrated visually against the shipped
// reference shots (tools bone_test mount): the rider draws 1.63 up — the
// mounted clips (0201/0217/…) carry the Bip01 root at (−0.02, 0.15, −0.14),
// so hips land at 1.78, exactly the saddle marker's bind height — and 0.05
// toward the horse's head, which centers the butt on the saddle's seat
// (positive Z is toward the head; the marker bone itself sits at the pommel,
// too far forward). On top of this static seat the rider inherits the
// anchor bone's animated bob/sway (horse_instance_anchor_delta), so they
// move with the horse. Both models face +Z in bind pose and draw with the
// shared AVATAR_YAW_OFFSET_DEG, so the offsets apply along the facing.
HORSE_RIDER_LIFT    :: 1.63
HORSE_RIDER_FORWARD :: 0.05

// Bone whose animated motion the rider seat inherits — the saddle follows the
// back, so anchoring there makes the rider bob/sway with the gait instead of
// hovering statically over it. Delta is measured against the bone's bind
// position (see horse_instance_anchor_delta).
HORSE_ANCHOR_BONE :: "Bip01 Spine2"

Horse_Model :: struct {
	entry:      ^Model_Entry, // refcounted assets cache handle
	anims:      [^]rl.ModelAnimation,
	anim_count: int,
	idle:       int,            // clip index of the idle code, -1 = none
	clips:      map[string]int, // clip code → anim index
	lift:       f32,            // world-space feet offset (bind-pose min.y)
	anchor_bone: int,           // skeleton index of HORSE_ANCHOR_BONE, -1 none
	anchor_bind: rl.Vector3,    // anchor bone's bind (model-space) position
	valid:      bool,
}

// Per-rider animation state against the shared horse model (by value in
// Renderable, so entity removal needs no cleanup).
Horse_Instance :: struct {
	base:          ^Horse_Model, // shared cache entry (outlives the scene)
	clip:          int,          // gait clip currently selected, -1 = none yet
	clip_loop:     bool,
	anim_time:     f32,          // seconds into the current clip
	applied_clip:  int,          // clip of the last advanced pose, -1 = none
	applied_frame: f32,
	variant:       i32,          // coat id the instance was created with
	valid:         bool,
}

horse_cache: map[string]^Horse_Model

// Logical model path for a horse coat + barding variant, resolved against
// assets/ like the monster modelFile references.
horse_model_path :: proc(coat, barding: i32) -> string {
	return fmt.tprintf("horses/horse_%03d_%03d.glb", coat, barding)
}

// Acquire (load on first use) a horse model by its logical path. Failed loads
// are negatively cached. The CACHE holds the single assets reference for the
// whole session (like the monster cache) — see horse_models_shutdown.
horse_model_acquire :: proc(model_path: string) -> ^Horse_Model {
	if horse_cache == nil do horse_cache = make(map[string]^Horse_Model)
	if m, ok := horse_cache[model_path]; ok do return m

	m := new(Horse_Model)
	m.idle = -1

	glb_path := fmt.tprintf("assets/%s", model_path)
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
			if code == CLIP_CODE_HORSE_IDLE do m.idle = i
		}
		// Feet-on-origin lift from the raw mesh bounds: the horse skinned
		// meshes rest with hooves at y≈0 in bind space (verified against the
		// assembled render). The skeleton-based bounds used by the chara
		// avatars are wrong for this rig — its rein/arm bone chain binds
		// ~3.2 units below ground, which launched the whole model skyward.
		m.lift = -rl.GetModelBoundingBox(entry.model).min.y

		// Rider anchor: the seat bone's skeleton index + its bind position
		// (raylib bind poses are composed global/model-space at glb load).
		m.anchor_bone = -1
		skel := &entry.model.skeleton
		if skel.bones != nil && skel.bindPose != nil {
			for bi in 0..<int(skel.boneCount) {
				if chara_bone_name(&skel.bones[bi]) == HORSE_ANCHOR_BONE {
					m.anchor_bone = bi
					m.anchor_bind = skel.bindPose[bi].translation
					break
				}
			}
		}
		m.valid = true
		rl.TraceLog(.INFO, "horse: loaded %s (%d clips, idle=%d, lift=%.2f)",
			assets_cstring(model_path), m.anim_count, m.idle, m.lift)
	}

	key := strings.clone(model_path)
	horse_cache[key] = m // negatively cached when !valid
	return m
}

// Fresh per-rider animation state for a horse model.
horse_instance_init :: proc(base: ^Horse_Model, variant: i32) -> Horse_Instance {
	hi := Horse_Instance{base = base, clip = -1, applied_clip = -1, variant = variant}
	if base != nil do hi.valid = base.valid
	return hi
}

// Select a looping gait clip ("0001"/"0015"/"0018"); a no-op when already
// playing it, so the gait clock never stutters on per-frame re-picks. False
// when the model lacks the code.
horse_instance_set_gait :: proc(mi: ^Horse_Instance, code: string) -> bool {
	if mi == nil || !mi.valid do return false
	idx, ok := mi.base.clips[code]
	if !ok do return false
	if mi.clip == idx && mi.clip_loop do return true
	mi.clip = idx
	mi.clip_loop = true
	mi.anim_time = 0
	return true
}

// Leave any override; the instance returns to its idle gait.
horse_instance_stop :: proc(mi: ^Horse_Instance) {
	if mi == nil do return
	mi.clip = -1
	mi.clip_loop = false
	mi.anim_time = 0
}

// Advance one instance's clock by dt: the gait clip while one is selected,
// the idle otherwise. The pose itself is applied at draw time.
horse_instance_update :: proc(mi: ^Horse_Instance, dt: f32) {
	if mi == nil || !mi.valid || mi.base == nil do return
	idx := mi.clip
	if idx < 0 do idx = mi.base.idle
	if idx < 0 || idx >= mi.base.anim_count do return
	anim := &mi.base.anims[idx]
	frames := f32(anim.keyframeCount)
	if frames <= 0 do return

	mi.anim_time += dt
	frame := mi.anim_time * CHARA_ANIM_FPS
	frame = frame - f32(i32(frame / frames)) * frames // wrap looping gaits
	mi.applied_clip = idx
	mi.applied_frame = frame
}

// Apply the instance's pending pose to the shared model NOW. The draw path
// re-applies the same pose (idempotent), but splitting this out lets rider
// anchoring read the animated skeleton between pose and draw — pose it, read
// the anchor delta, place the rider, then draw (adjacency keeps instances
// independent, same as the monster layer).
horse_instance_pose :: proc(mi: ^Horse_Instance) {
	if mi == nil || !mi.valid || mi.base == nil do return
	if mi.applied_clip >= 0 && mi.applied_clip < mi.base.anim_count {
		rl.UpdateModelAnimation(
			mi.base.entry.model,
			mi.base.anims[mi.applied_clip],
			mi.applied_frame,
		)
	}
}

// Model-space translation delta of the seat anchor bone (animated pose vs
// bind) — the bob/sway the rider seat inherits. Zero until a pose has been
// applied (horse_instance_pose).
horse_instance_anchor_delta :: proc(mi: ^Horse_Instance) -> rl.Vector3 {
	if mi == nil || !mi.valid || mi.base == nil do return {0, 0, 0}
	b := mi.base
	if b.anchor_bone < 0 || b.entry.model.currentPose == nil do return {0, 0, 0}
	return b.entry.model.currentPose[b.anchor_bone].translation - b.anchor_bind
}

// Rotate a model-space anchor delta into world space — the same yaw + 180°
// offset the draw path applies, so the rider moves with the horse it sits on.
horse_delta_world :: proc "contextless" (yaw_rad: f32, delta: rl.Vector3) -> rl.Vector3 {
	return rl.Vector3RotateByAxisAngle(delta, {0, 1, 0}, yaw_rad + rl.PI)
}

// Debug helper for tools/mount_shot: print the animated-vs-bind translation
// delta of the candidate seat bones at the instance's current pose.
horse_probe_anchor :: proc(mi: ^Horse_Instance, label: string) {
	if mi == nil || !mi.valid || mi.base == nil do return
	skel := &mi.base.entry.model.skeleton
	if skel.bones == nil || mi.base.entry.model.currentPose == nil do return
	candidates := [6]string{"Bip01", "Bip01 Pelvis", "Bip01 Spine", "Bip01 Spine1", "Bip01 Spine2", "Dummy02"}
	for name in candidates {
		for bi in 0..<int(skel.boneCount) {
			if chara_bone_name(&skel.bones[bi]) != name do continue
			d := mi.base.entry.model.currentPose[bi].translation - skel.bindPose[bi].translation
			fmt.eprintfln("  anchor[%s] %s: delta (%+.4f, %+.4f, %+.4f)", label, name, d.x, d.y, d.z)
			break
		}
	}
}

// Draw one horse instance at `position` (feet-on-origin, like every entity):
// re-pose the shared model with this instance's pose immediately before the
// draw so each mounted player renders its own gait (mirrors the avatar draw's
// +180° yaw offset).
horse_model_draw :: proc(mi: ^Horse_Instance, position: rl.Vector3, yaw_rad: f32, tint: rl.Color, lift: f32, scale: f32) {
	if mi == nil || !mi.valid || mi.base == nil do return
	if mi.applied_clip >= 0 && mi.applied_clip < mi.base.anim_count {
		rl.UpdateModelAnimation(
			mi.base.entry.model,
			mi.base.anims[mi.applied_clip],
			mi.applied_frame,
		)
	}
	axis, angle := euler_y_to_raylib(yaw_rad)
	rl.DrawModelEx(mi.base.entry.model,
		{position.x, position.y + lift, position.z},
		axis, angle + AVATAR_YAW_OFFSET_DEG, {scale, scale, scale}, tint)
}

// Planar world-space offset from the horse's origin to where the rider's
// model origin must sit (toward the saddle, i.e. the horse's head side).
// The seat HEIGHT rides the rider avatar's own lift (HORSE_RIDER_LIFT — set
// by chara_avatar_update while mounted), so this offset's y stays zero.
// `yaw` is the entity's stored facing: the game-forward direction (where the
// models' +Z points after the draw-path yaw offset) is (−sin yaw, −cos yaw).
horse_rider_offset :: proc "contextless" (yaw: f32) -> rl.Vector3 {
	return {-math.sin(yaw) * HORSE_RIDER_FORWARD, 0, -math.cos(yaw) * HORSE_RIDER_FORWARD}
}

// Frees the cache; call before assets_destroy at shutdown.
horse_models_shutdown :: proc() {
	for key, m in horse_cache {
		if m.valid {
			if m.anim_count > 0 do rl.UnloadModelAnimations(m.anims, i32(m.anim_count))
			if m.clips != nil {
				for code in m.clips do delete(code)
				delete(m.clips)
			}
			assets_model_release(m.entry)
		}
		delete_key(&horse_cache, key)
		delete(key)
		free(m)
	}
	delete(horse_cache)
	horse_cache = nil
}
