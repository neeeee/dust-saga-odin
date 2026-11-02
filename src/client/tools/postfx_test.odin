package postfx_test

// Visual check for the postfx chain (bloom + vibrance) and blob shadows:
// renders a zone through the same postfx path the gameplay scene uses, plus
// a test blob disc, then screenshots the backbuffer.
import "core:fmt"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import sys "../systems"

main :: proc() {
	rl.SetTraceLogLevel(.INFO)
	rl.SetConfigFlags({rl.ConfigFlag.MSAA_4X_HINT})
	rl.InitWindow(1280, 720, "postfx test")
	defer rl.CloseWindow()
	rlgl.SetClipPlanes(0.01, 8000.0)
	sys.lighting_time_hours = 12

	zone := sys.load_zone_map("1001004")
	if zone == nil || !zone.loaded {
		fmt.eprintfln("FAILED to load zone")
		return
	}
	defer sys.zone_destroy(zone)

	rl.BeginDrawing()
	sys.postfx_begin(sys.lighting_clear_color())
	rl.BeginMode3D(rl.Camera3D{
		position   = {0, 2.5, -24},
		target     = {0, 5, 26},
		up         = {0, 1, 0},
		fovy       = 60,
		projection = .PERSPECTIVE,
	})
	sys.render_zone(zone)
	sys.blob_shadow_draw(0, 4.3, -10, 1.0)
	rl.EndMode3D()
	sys.postfx_end()
	rl.TakeScreenshot("postfx_shot.png")
	rl.EndDrawing()
	fmt.eprintfln("wrote postfx_shot.png")
}
