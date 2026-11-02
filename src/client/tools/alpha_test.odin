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
	// Deterministic day lighting for the standard cases (the env now
	// follows the wall clock otherwise).
	sys.lighting_time_hours = 12

	// T03 plaza (trees/roads/walls), then T01_01 center.
	run_case("1003001", 0, 5, 26, 0, 4, 0)
	run_case("1001001", -12, 6, 110, -12, 3, 52)
	run_case("99999999", 0, 40, 80, 0, 0, 0)
	// Ground-doubling probe: F05_01 (zone 2005001) wide + ground level.
	run_case("2005001", 200, 90, 420, 100, 5, 100)
	run_case("2005001", 0, 6, 40, 0, 2, 0)
	// D01_01 dungeon.
	run_case("3001001", 0, 8, 40, 0, 2, 0)
	run_case("3001001", 0, 30, 120, 0, 0, 0)
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
	// Shared-bake double load (2005001 + 2005301 both use map_F05_01.glb):
	// the default_ground mask must not re-run on the second zone.
	run_case("2005301", 0, 6, 40, 0, 2, 0)
	// F02_01 / F01_02 / E01_01 spot checks.
	run_case("2002001", 0, 6, 40, 0, 2, 0)
	run_case("2001002", 0, 6, 40, 0, 2, 0)
	run_case("9001001", 0, 6, 20, 0, 2, 0)
	// Pine close-up: tree03E at (2.63, -0.82) world (meters).
	run_case("2005001", 273, 9, -70, 263, 12, -82)
	// 2002001 at the user's reported position (canyon pit).
	run_case("2002001", 169, -10, -1055, 169, -19, -1069)
	// The 21:18 comparison shots: same vantage, lighting on/off below.
	run_case("2002001", -2135, -70, -6700, -2135, -81, -6711)
	// The user's F01_01 spot (day).
	run_case("2001001", -356.4, 6, -494, -356.4, 4.3, -508.9)
	// The user's real vantage (-213.5, -671.1) from altitude, day + night.
	sys.lighting_time_hours = 12
	run_case("2002001", -213.5, 60, -656, -213.5, -8, -671)
	sys.lighting_time_hours = 21.5
	run_case("2002001", -213.5, 61, -656, -213.5, -8, -671)
	sys.lighting_time_hours = 12
	// Night on the F02 field (the original game's dark-blue fog look).
	sys.lighting_time_hours = 21.5
	run_case("2002001", 0, 6, 40, 0, 2, 0)
	run_case("2002001", 30, 14, 12, 0, 4, 0)
	sys.lighting_time_hours = 12
	// Alpha-mode debug flat renders (red=OPAQUE green=MASK blue=BLEND black=HIDDEN).
	sys.terrain_debug_flat = true
	run_case("2005001", 0, 6, 40, 0, 2, 0)
	run_case("1003001", 0, 5, 26, 0, 4, 0)
	sys.terrain_debug_flat = false
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
	rl.ClearBackground(sys.lighting_clear_color())
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

	out := fmt.tprintf("alpha_test_%s_%s_%v_%v_%v.png", zone_id, sys.terrain_debug_flat ? "dbg" : "cam", px, py, pz)
	ok := rl.ExportImage(img, sys.assets_cstring(out))
	fmt.eprintfln("%s -> %s (terrain=%v)", ok ? "wrote" : "EXPORT FAILED", out, zone.terrain != nil)
}
