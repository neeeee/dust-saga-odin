package light_test

// Renders one zone view twice — lighting on, then lighting off — so the
// lighting system's contribution is directly diffable.
import "core:fmt"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import sys "../systems"

main :: proc() {
	rl.SetTraceLogLevel(.WARNING)
	rl.SetConfigFlags({rl.ConfigFlag.WINDOW_HIDDEN})
	rl.InitWindow(320, 240, "lighting test")
	defer rl.CloseWindow()
	rlgl.SetClipPlanes(0.01, 8000.0)

	zone := sys.load_zone_map("2002001")
	if zone == nil || !zone.loaded {
		fmt.eprintfln("FAILED to load zone")
		return
	}
	defer sys.zone_destroy(zone)

	modes := [2]string{"on", "off"}
	for tag, _ in modes {
		enabled := tag == "on"
		sys.lighting_enabled = enabled
		sys.lighting_refresh()
		target := rl.LoadRenderTexture(1280, 720)
		defer rl.UnloadRenderTexture(target)
		rl.BeginTextureMode(target)
		rl.ClearBackground(sys.lighting_clear_color())
		rl.BeginMode3D(rl.Camera3D{
			position = {-2135, -70, -6700},
			target   = {-2135, -81, -6711},
			up       = {0, 1, 0},
			fovy     = 60,
			projection = .PERSPECTIVE,
		})
		sys.render_zone(zone)
		rl.EndMode3D()
		rl.EndTextureMode()
		img := rl.LoadImageFromTexture(target.texture)
		rl.ImageFlipVertical(&img)
		name := fmt.tprintf("light_%s.png", tag)
		rl.ExportImage(img, sys.assets_cstring(name))
		rl.UnloadImage(img)
		fmt.eprintfln("wrote %s", name)
	}
}
