// Heap-backed dynamic literals are allowed here: tune_defaults stores a
// dynamic array's slice in the global tune_cats (plain slice literals are
// stack-backed and would dangle).
#+feature dynamic-literals
package bone_test



// Interactive weapon-placement tuner. Renders the avatar with the selected
// weapon class in the sheathed or drawn state; the seat translation/rotation
// is editable live and the whole table exports to src/client/sheath_tuning.json
// (Enter), which gets baked back into chara_models.odin.
//
// Build from src/client (run from anywhere, assets are located on startup):
//   odin build tools -out:tools/tools.exe -define:RAYLIB_SHARED=true -extra-linker-flags:"/NODEFAULTLIB:msvcrt"
//   ./tools/tools.exe tune
//
// Controls:
//   [ / ]   previous / next weapon category
//   TAB     sheathed <-> drawn
//   W/S     move up / down          A/D  move left / right
//   Q/E     move forward / back     (sheathed only: the seat origin)
//   I/K     pitch  -/+              J/L  yaw -/+     U/O  roll -/+
//           (sheathed only: seat orientation; drawn weapons don't roll)
//   SHIFT   coarse steps (5x)
//   ENTER   save sheath_tuning.json
//   ESC     quit (saves too)
//   Mouse drag orbits the camera, wheel zooms.

import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import rl "vendor:raylib"
import sys "../systems"

Tune_Category :: struct {
	name:  string, // json key
	label: string,
	glb:   string,
	kind:  sys.Weapon_Kind,
	// live state
	sheath_t: rl.Vector3, // Bip01-relative seat translation
	sheath_e: rl.Vector3, // seat orientation, euler degrees (XYZ order)
	drawn_t:  rl.Vector3, // right-hand grip translation
}

tune_cats: []Tune_Category
tune_idx:  int
tune_drawn := false
tune_av:   ^sys.Chara_Avatar
tune_idle: int

tune_cstr :: proc(s: string) -> cstring {
	return strings.clone_to_cstring(s, context.temp_allocator)
}

tune_euler_to_quat :: proc(e: rl.Vector3) -> rl.Quaternion {
	d := f64(math.PI) / 180.0
	ex, ey, ez := f64(e.x), f64(e.y), f64(e.z)
	cx := math.cos(ex * d * 0.5); sx := math.sin(ex * d * 0.5)
	cy := math.cos(ey * d * 0.5); sy := math.sin(ey * d * 0.5)
	cz := math.cos(ez * d * 0.5); sz := math.sin(ez * d * 0.5)
	// XYZ intrinsic order
	return rl.Quaternion(quaternion(
		x = sx * cy * cz - cx * sy * sz,
		y = cx * sy * cz + sx * cy * sz,
		z = cx * cy * sz - sx * sy * cz,
		w = cx * cy * cz + sx * sy * sz))
}

tune_quat_to_euler :: proc(q: rl.Quaternion) -> rl.Vector3 {
	x := f64(q.x); y := f64(q.y); z := f64(q.z); w := f64(q.w)
	// XYZ order (same construction as above, inverted)
	sin_p := clamp(-1.0, 1.0, 2.0 * (w * x - y * z))
	pitch := math.asin(sin_p)
	if math.abs(sin_p) < 0.9995 {
		roll := math.atan2(2.0 * (w * z + x * y), 1.0 - 2.0 * (x * x + z * z))
		yaw := math.atan2(2.0 * (w * y + z * x), 1.0 - 2.0 * (y * y + z * z))
		d := 180.0 / math.PI
		return {f32(roll * d), f32(yaw * d), f32(pitch * d)}
	}
	// gimbal lock: fake the third angle
	yaw := 2.0 * math.atan2(2.0 * (w * y + z * x) * math.sign(sin_p), 1.0)
	d := 180.0 / math.PI
	return {0, f32(yaw * d), f32(pitch * d * math.sign(sin_p))}
}

clamp :: proc "contextless" (lo, hi, v: f64) -> f64 {
	return math.min(hi, math.max(lo, v))
}

tune_defaults :: proc() {
	// [dynamic] (not a plain slice literal): slice literals are backed by the
	// STACK, so storing one in the global tune_cats left a dangling pointer
	// once this proc returned — the heap copy survives.
	cats := [dynamic]Tune_Category{
		{name = "wand1h",   label = "1h weapons (wand)",      glb = "item/EM_002631_20_000.glb", kind = .WAND},
		{name = "dagger",   label = "Dagger",                 glb = "item/EM_001801_20_000.glb", kind = .DAGGER},
		{name = "staff",    label = "Staff (2h rod)",         glb = "item/EM_002801_20_000.glb", kind = .STAFF},
		{name = "sword2h",  label = "2h Sword",               glb = "item/EM_000401_20_000.glb", kind = .TWO_HANDED_SWORD},
		{name = "axe2h",    label = "2h Axe",                 glb = "item/EM_000801_20_000.glb", kind = .TWO_HANDED_AXE},
		{name = "hammer2h", label = "2h Hammer",              glb = "item/EM_001211_20_000.glb", kind = .TWO_HANDED_BLUNT},
		{name = "spear2h",  label = "2h Spear / Pole Arm",    glb = "item/EM_001503_20_000.glb", kind = .TWO_HANDED_SPEAR},
		{name = "lance",    label = "Lance (1h)",             glb = "item/EM_001612_20_000.glb", kind = .SPEAR},
		{name = "bow",      label = "Bow",                    glb = "item/EM_002224_20_000.glb", kind = .BOW},
		{name = "crossbow", label = "Crossbow",               glb = "item/EM_002421_20_000.glb", kind = .CROSSBOW},
		{name = "claw",     label = "Claw (both hips)",       glb = "item/EM_002021_20_000.glb", kind = .KNUCKLES},
	}
	for &c in cats {
		c.sheath_t = sys.chara_sheath_seat(c.kind).t
		c.sheath_e = tune_quat_to_euler(sys.chara_sheath_seat(c.kind).q)
		c.drawn_t = sys.chara_drawn_grip_t(c.kind)
	}
	tune_cats = cats[:]
}

tune_pose :: proc(av: ^sys.Chara_Avatar, clip_idx: int) {
	av.applied_clip = clip_idx
	av.applied_frame = 0
	av.blend_from = -1
	sys.chara_apply_current_pose(av, av.sub.model)
}

tune_save :: proc() {
	parts: [dynamic]string
	append(&parts, "{\n")
	for c, i in tune_cats {
		q := tune_euler_to_quat(c.sheath_e)
		comma := i < len(tune_cats) - 1 ? "," : ""
		append(&parts, fmt.tprintf(
			"  \"%s\": { \"label\": \"%s\", \"sheath_t\": [%f, %f, %f], \"sheath_q\": [%.6f, %.6f, %.6f, %.6f], \"sheath_e\": [%.2f, %.2f, %.2f], \"drawn_t\": [%f, %f, %f] }%s\n",
			c.name, c.label,
			c.sheath_t.x, c.sheath_t.y, c.sheath_t.z,
			q.x, q.y, q.z, q.w,
			c.sheath_e.x, c.sheath_e.y, c.sheath_e.z,
			c.drawn_t.x, c.drawn_t.y, c.drawn_t.z,
			comma))
	}
	append(&parts, "}\n")
	out, _ := strings.concatenate(parts[:])
	_ = os.write_entire_file_from_string("sheath_tuning.json", out)
}

tune_adjust :: proc(e: ^Tune_Category, axis: int, sign: f32, step: f32) {
	if tune_drawn {
		// drawn grip: translation only (rotation is the fixed N52 seat)
		switch axis {
		case 0: e.drawn_t.x += sign * step
		case 1: e.drawn_t.y += sign * step
		case 2: e.drawn_t.z += sign * step
		}
	} else {
		switch axis {
		case 0: e.sheath_t.x += sign * step
		case 1: e.sheath_t.y += sign * step
		case 2: e.sheath_t.z += sign * step
		case 3: e.sheath_e.x += sign * step * 5.0
		case 4: e.sheath_e.y += sign * step * 5.0
		case 5: e.sheath_e.z += sign * step * 5.0
		}
	}
}

sheath_tune :: proc() {
	rl.InitWindow(900, 760, "sheath_tune")
	tools_clamp_window()
	rl.SetTargetFPS(60) // uncapped loop pegs a core on this old laptop
	defer rl.CloseWindow()
	sys.assets_init()
	tune_defaults()

	cm := sys.chara_model_acquire("012")
	if cm == nil {
		fmt.eprintfln("tune: race 012 acquire FAILED")
		return
	}
	tune_av = sys.chara_avatar_create(cm, 0, 0, 0)
	if tune_av == nil {
		sys.chara_model_release(cm)
		fmt.eprintfln("tune: avatar create FAILED")
		return
	}
	tune_idle = tune_av.cm.idle_anim

	cam_yaw, cam_pitch, cam_dist: f32 = 0.55, 0.25, 2.9

	last_mouse := rl.GetMousePosition()

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()
		e := &tune_cats[tune_idx]
		step := f32(0.01) * (rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT) ? 5.0 : 1.0)

		// ── input ──
		if rl.IsKeyPressed(.LEFT_BRACKET) do tune_idx = (tune_idx + len(tune_cats) - 1) % len(tune_cats)
		if rl.IsKeyPressed(.RIGHT_BRACKET) do tune_idx = (tune_idx + 1) % len(tune_cats)
		if rl.IsKeyPressed(.TAB) do tune_drawn = !tune_drawn

		if rl.IsKeyDown(.A) do tune_adjust(e, 0, -1, step)
		if rl.IsKeyDown(.D) do tune_adjust(e, 0, +1, step)
		if rl.IsKeyDown(.W) do tune_adjust(e, 1, +1, step)
		if rl.IsKeyDown(.S) do tune_adjust(e, 1, -1, step)
		if rl.IsKeyDown(.Q) do tune_adjust(e, 2, -1, step)
		if rl.IsKeyDown(.E) do tune_adjust(e, 2, +1, step)
		if !tune_drawn {
			if rl.IsKeyDown(.K) do tune_adjust(e, 3, -1, step)
			if rl.IsKeyDown(.I) do tune_adjust(e, 3, +1, step)
			if rl.IsKeyDown(.J) do tune_adjust(e, 4, -1, step)
			if rl.IsKeyDown(.L) do tune_adjust(e, 4, +1, step)
			if rl.IsKeyDown(.U) do tune_adjust(e, 5, -1, step)
			if rl.IsKeyDown(.O) do tune_adjust(e, 5, +1, step)
		}

		if rl.IsKeyPressed(.ENTER) do tune_save()

		// ── camera orbit (left-drag) + zoom ──
		mouse := rl.GetMousePosition()
		if rl.IsMouseButtonDown(.LEFT) {
			delta := mouse - last_mouse
			cam_yaw -= f32(delta.x) * 0.01
			cam_pitch = math.clamp(cam_pitch + f32(delta.y) * 0.01, -1.2, 1.35)
		}
		last_mouse = mouse
		cam_dist = math.clamp(cam_dist - rl.GetMouseWheelMove() * 0.25, 1.2, 6.0)

		// ── pose ──
		av := tune_av
		if av != nil {
			clip := tune_idle
			if tune_drawn {
				fam := sys.chara_weapon_family(e.kind)
				drawn_clip := sys.chara_clip(av.cm, fam.idle)
				if drawn_clip >= 0 do clip = drawn_clip
			}
			tune_pose(av, clip)
		}

		// ── camera matrix ──
		cy := math.cos(cam_yaw) * math.cos(cam_pitch)
		cz := math.sin(cam_yaw) * math.cos(cam_pitch)
		sy := math.sin(cam_pitch)
		target := rl.Vector3{0, 0.95, 0}
		cam_pos := target + rl.Vector3{cy, sy, cz} * cam_dist
		cam := rl.Camera3D{
			position   = cam_pos,
			target     = target,
			up         = {0, 1, 0},
			fovy       = 40,
			projection = .PERSPECTIVE,
		}

		// ── draw ──
		// acquire OUTSIDE BeginDrawing: LoadModel mid-frame corrupts GL state
		entry := sys.held_model_acquire(e.glb)
		rl.BeginDrawing()
		rl.ClearBackground({168, 178, 200, 255})
		rl.BeginMode3D(cam)
		rl.DrawPlane({0, 0, 0}, {4, 4}, {120, 140, 110, 255})
		if av != nil {
			// tuning overrides live for this frame
			sys.chara_debug_sheath_seat = tune_euler_to_quat(e.sheath_e)
			sys.chara_debug_sheath_seat_t = {e.sheath_t.x, e.sheath_t.y, e.sheath_t.z}
			sys.chara_debug_sheath_on = true
			sys.chara_debug_drawn_t = {e.drawn_t.x, e.drawn_t.y, e.drawn_t.z}
			sys.chara_debug_drawn_on = true

			sys.chara_avatar_draw_body(av, {0, 0, 0}, 0, rl.WHITE)
			if entry != nil {
				sys.chara_avatar_draw_held(av, entry, {0, 0, 0}, 0, rl.WHITE, tune_drawn, 1.0)
			}
			sys.chara_debug_sheath_on = false
			sys.chara_debug_drawn_on = false
		}
		rl.EndMode3D()

		// NOTE: never feed cstrings (tune_cstr results) into fmt %s — the
		// format pass reads them as strings with a garbage length.
		title := fmt.tprintf("[%s]  %s  —  %s", e.name, e.label, tune_drawn ? "DRAWN" : "SHEATHED")
		t1 := fmt.tprintf("sheath_t  %.3f %.3f %.3f", e.sheath_t.x, e.sheath_t.y, e.sheath_t.z)
		t2 := fmt.tprintf("sheath_e  %.1f %.1f %.1f", e.sheath_e.x, e.sheath_e.y, e.sheath_e.z)
		t3 := fmt.tprintf("drawn_t   %.3f %.3f %.3f", e.drawn_t.x, e.drawn_t.y, e.drawn_t.z)
		rl.DrawText(tune_cstr(title), 12, 10, 20, {20, 20, 30, 255})
		rl.DrawText(tune_cstr(t1), 12, 36, 16, {40, 40, 60, 255})
		rl.DrawText(tune_cstr(t2), 12, 56, 16, {40, 40, 60, 255})
		rl.DrawText(tune_cstr(t3), 12, 76, 16, {40, 40, 60, 255})
		rl.DrawText(tune_cstr("[ ] weapon   TAB sheath/drawn   WASD+QE move   IJKL+UO rotate"), 12, i32(rl.GetScreenHeight()) - 60, 16, {40, 40, 60, 255})
		rl.DrawText(tune_cstr("SHIFT coarse   ENTER save sheath_tuning.json   ESC quit   drag orbit, wheel zoom"), 12, i32(rl.GetScreenHeight()) - 38, 16, {40, 40, 60, 255})
		rl.EndDrawing()
	}
	tune_save()
}
