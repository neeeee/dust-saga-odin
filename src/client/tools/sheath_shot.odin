package bone_test

// Sheath/drawn placement verification: renders the human female avatar with
// one weapon per class, in both states, from front/side/back — output PNGs
// let the seat constants in chara_models.odin be tuned against the shipped
// game's reference screenshots WITHOUT guessing from in-game reports.
//
// Build & run from src/client:
//   odin build tools -out:bone_test.exe -define:RAYLIB_SHARED=true -extra-linker-flags:"/NODEFAULTLIB:msvcrt"
//   ./bone_test.exe sheath

import "core:fmt"
import "core:os"
import "core:strings"
import rl "vendor:raylib"
import sys "../systems"

Sheath_Shot_Weapon :: struct {
	name: string,
	glb:  string,
	kind: sys.Weapon_Kind,
}

sheath_shot_cstr :: proc(s: string) -> cstring {
	return strings.clone_to_cstring(s, context.temp_allocator)
}

sheath_shot_pose :: proc(av: ^sys.Chara_Avatar, clip_idx: int, frame: f32) {
	av.applied_clip = clip_idx
	av.applied_frame = frame
	av.blend_from = -1
	sys.chara_apply_current_pose(av, av.sub.model)
}

sheath_shot_take :: proc(av: ^sys.Chara_Avatar, entry: ^sys.Model_Entry, drawn: bool, name: string, cam_pos: rl.Vector3) {
	cam := rl.Camera3D{
		position   = cam_pos,
		target     = {0, 0.95, 0},
		up         = {0, 1, 0},
		fovy       = 38,
		projection = .PERSPECTIVE,
	}
	rl.BeginDrawing()
	rl.ClearBackground({168, 178, 200, 255})
	rl.BeginMode3D(cam)
	rl.DrawPlane({0, 0, 0}, {4, 4}, {120, 140, 110, 255})
	sys.chara_avatar_draw_body(av, {0, 0, 0}, 0, rl.WHITE)
	sys.chara_avatar_draw_held(av, entry, {0, 0, 0}, 0, rl.WHITE, drawn, 1.0)
	rl.EndMode3D()
	rl.TakeScreenshot(sheath_shot_cstr(name))
	rl.EndDrawing()
	fmt.eprintfln("sheath_shot: wrote %s", name)
}

sheath_shot_weapon :: proc(av: ^sys.Chara_Avatar, w: Sheath_Shot_Weapon, idle: int, frames: []string) {
	entry := sys.held_model_acquire(w.glb)
	if entry == nil {
		fmt.eprintfln("sheath_shot: %s — model %s MISSING", w.name, w.glb)
		return
	}
	av.weapon_kind = w.kind
	sys.chara_avatar_set_weapon_kind(av, w.kind)
	fam := sys.chara_weapon_family(w.kind)
	drawn_clip := sys.chara_clip(av.cm, fam.idle)

	// sheathed: neutral idle pose, weapon on the carry socket
	sheath_shot_pose(av, idle, 0)
	i := 0
	for v in frames {
		sheath_shot_take(av, entry, false, fmt.tprintf("sheath_%s_sheath_%s.png", w.name, v), sheath_shot_view(v))
		i += 1
	}
	// drawn: family drawn idle pose, weapon in the right hand
	if drawn_clip >= 0 {
		sheath_shot_pose(av, drawn_clip, 0)
		for v in frames {
			sheath_shot_take(av, entry, true, fmt.tprintf("sheath_%s_drawn_%s.png", w.name, v), sheath_shot_view(v))
		}
	}
}

sheath_shot_view :: proc(v: string) -> rl.Vector3 {
	case_v := v
	if case_v == "front" do return {0, 1.35, -2.6}
	if case_v == "back" do return {0, 1.35, 2.6}
	if case_v == "left" do return {2.6, 1.35, 0.01}
	return {0, 1.35, -2.6}
}

sheath_shot :: proc() {
	rl.InitWindow(640, 720, "sheath_shot")
	defer rl.CloseWindow()
	sys.assets_init()

	cm := sys.chara_model_acquire("012")
	if cm == nil {
		fmt.eprintfln("sheath_shot: race 012 acquire FAILED")
		return
	}
	av := sys.chara_avatar_create(cm, 0, 0, 0)
	if av == nil {
		sys.chara_model_release(cm)
		return
	}
	idle := av.cm.idle_anim

	weapons := []Sheath_Shot_Weapon{
		{name = "wand",     glb = "item/EM_002631_20_000.glb", kind = .WAND},
		{name = "staff",    glb = "item/EM_002801_20_000.glb", kind = .STAFF},
		{name = "crossbow", glb = "item/EM_002401_20_000.glb", kind = .CROSSBOW},
		{name = "zweihander", glb = "item/EM_000401_20_000.glb", kind = .TWO_HANDED_SWORD},
		{name = "hammer",   glb = "item/EM_001031_20_000.glb", kind = .TWO_HANDED_BLUNT},
		{name = "spear",    glb = "item/EM_001401_20_000.glb", kind = .TWO_HANDED_SPEAR},
		{name = "stiletto", glb = "item/EM_001801_20_000.glb", kind = .DAGGER},
		{name = "cestus",   glb = "item/EM_002001_20_000.glb", kind = .KNUCKLES},
	}
	// `sheath quick`: just the currently-tuned classes + the known-good 2h
	// sword as an orientation anchor.
	if len(os.args) > 2 && os.args[2] == "quick" {
		weapons = []Sheath_Shot_Weapon{
			{name = "wand",       glb = "item/EM_002631_20_000.glb", kind = .WAND},
			{name = "crossbow",   glb = "item/EM_002401_20_000.glb", kind = .CROSSBOW},
			{name = "zweihander", glb = "item/EM_000401_20_000.glb", kind = .TWO_HANDED_SWORD},
			{name = "spear",      glb = "item/EM_001401_20_000.glb", kind = .TWO_HANDED_SPEAR},
			{name = "axe",        glb = "item/EM_000801_20_000.glb", kind = .TWO_HANDED_AXE},
		}
	}

	frames := []string{"front", "left", "back"}
	for w in weapons {
		sheath_shot_weapon(av, w, idle, frames)
	}

	sys.chara_avatar_destroy(av)
}
