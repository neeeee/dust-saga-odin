package charlight_test

// Character-lighting check: renders one avatar front/side through the lit
// entity shader on a neutral ground plane — verifies the wrap-lighting
// softness against the reference screenshots.
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"
import sys "../systems"

cstr :: proc(s: string) -> cstring {
	return strings.clone_to_cstring(s, context.temp_allocator)
}

main :: proc() {
	rl.SetTraceLogLevel(.WARNING)
	rl.InitWindow(640, 720, "charlight test")
	defer rl.CloseWindow()
	sys.assets_init()
	sys.lighting_time_hours = 12

	cm := sys.chara_model_acquire("012")
	if cm == nil {
		fmt.eprintfln("chara acquire FAILED")
		return
	}
	defer sys.chara_model_release(cm)
	av := sys.chara_avatar_create(cm, 0, 0, 0)
	if av == nil do return
	defer sys.chara_avatar_destroy(av)
	sys.chara_apply_current_pose(av, av.sub.model)

	views := [2]struct{name: string, pos: rl.Vector3}{
		{"front", {0, 1.35, -2.6}},
		{"side", {2.6, 1.35, 0.01}},
	}
	for v in views {
		cam := rl.Camera3D{
			position   = v.pos,
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
		rl.EndMode3D()
		rl.TakeScreenshot(cstr(fmt.tprintf("charlight_%s.png", v.name)))
		rl.EndDrawing()
		fmt.eprintfln("wrote charlight_%s.png", v.name)
	}
}
