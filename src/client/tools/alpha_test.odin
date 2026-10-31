package alpha_test

// Visual check for the terrain alpha-cutout fix: loads a Pandora map through
// the real game path (load_zone_map), renders it offscreen (RenderTexture —
// hidden windows don't give a drawable default framebuffer), and exports a
// PNG. Compare against the in-game artifacts: foliage must show holes instead
// of solid sky-blue cards, road decals must blend into the ground, and no
// fallback plane may slice the model.
//
// Output: alpha_test_<zone>.png next to the exe.

import "core:fmt"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import sys "../systems"

main :: proc() {
	rl.SetTraceLogLevel(.WARNING)
	rl.SetConfigFlags({rl.ConfigFlag.WINDOW_HIDDEN})
	rl.InitWindow(320, 240, "terrain alpha test")
	defer rl.CloseWindow()
	rlgl.SetClipPlanes(0.01, 8000.0)

	// T03 plaza (trees/roads/walls), then T01_01 center.
	run_case("1003001", 0, 5, 26, 0, 4, 0)
	run_case("1001001", -12, 6, 110, -12, 3, 52)
	run_case("99999999", 0, 40, 80, 0, 0, 0)
	// T01_04 town: wv_bldg01* facades carry soft-alpha MASK textures.
	run_case("1001004", 0, 10, 60, 0, 4, -10)
	// T01_04 from spawn across the plaza: smithy front (left) / atel front.
	run_case("1001004", 0, 2.5, -24, -20, 6, 26)
	run_case("1001004", 0, 2.5, -24, 25, 5, 25)
	// T01_04 in-game view: third-person cam (yaw 0, pitch 0.5, dist 8) at
	// spawn looks toward -Z — the gate02 / north-edge buildings.
	run_case("1001004", 0, 5.3, -17, 0, 1.5, -24)
	// F03_01 grass fields: BLEND fx cards + MASK grass cutouts.
	run_case("2003001", 0, 4, 12, 0, 1, -14)
}

run_case :: proc(zone_id: string, px, py, pz, tx, ty, tz: f32) {
	zone := sys.load_zone_map(zone_id)
	if zone == nil || !zone.loaded {
		fmt.eprintfln("FAILED to load zone %s", zone_id)
		return
	}
	defer sys.zone_destroy(zone)

	target := rl.LoadRenderTexture(1280, 720)
	defer rl.UnloadRenderTexture(target)

	rl.BeginTextureMode(target)
	rl.ClearBackground(rl.SKYBLUE)
	rl.BeginMode3D(rl.Camera3D{
		position   = {px, py, pz},
		target     = {tx, ty, tz},
		up         = {0, 1, 0},
		fovy       = 60,
		projection = .PERSPECTIVE,
	})
	sys.render_zone(zone)
	rl.EndMode3D()
	rl.EndTextureMode()

	img := rl.LoadImageFromTexture(target.texture)
	defer rl.UnloadImage(img)
	rl.ImageFlipVertical(&img)

	out := fmt.tprintf("alpha_test_%s_%v_%v_%v.png", zone_id, px, py, pz)
	ok := rl.ExportImage(img, sys.assets_cstring(out))
	fmt.eprintfln("%s -> %s (terrain=%v)", ok ? "wrote" : "EXPORT FAILED", out, zone.terrain != nil)
}
