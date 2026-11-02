package envprobe

// Prints the parsed Zone_Lighting for a zone id — diagnosing environment
// parsing (fog color/range, sun, ambient).
import "core:fmt"
import rl "vendor:raylib"
import sys "../systems"

main :: proc() {
	rl.SetTraceLogLevel(.ERROR)
	rl.SetConfigFlags({rl.ConfigFlag.WINDOW_HIDDEN})
	rl.InitWindow(320, 240, "envprobe")
	defer rl.CloseWindow()
	zones := [5]string{"3001001", "2005001", "1001001", "2001001", "2002001"}
	for zone_id, _ in zones {
		z := sys.load_zone_map(zone_id)
		if z == nil || !z.loaded {
			fmt.printfln("%s: LOAD FAILED", zone_id)
			continue
		}
		e := z.lighting
		fmt.printfln(
			"%s: has=%v sun=(%.2f,%.2f,%.2f) suncol=(%.2f,%.2f,%.2f) fog=(%.2f,%.2f,%.2f) %.0f..%.0f",
			zone_id, e.has_env, e.sun_dir.x, e.sun_dir.y, e.sun_dir.z,
			e.sun_col[0], e.sun_col[1], e.sun_col[2],
			e.fog_col[0], e.fog_col[1], e.fog_col[2], e.fog_near, e.fog_far,
		)
		fmt.printfln("  global env: has=%v fog %.0f..%.0f enabled=%v",
			sys.lighting_env.has_env, sys.lighting_env.fog_near, sys.lighting_env.fog_far, sys.lighting_enabled)
		fmt.printfln("  clear rgb: %v", sys.lighting_clear_color())
		sys.lighting_time_hours = 21.5
		e2 := z.lighting
		sys.Lighting_Apply_Time_Test(&e2, z.id)
		fmt.printfln("  night env: fog=(%.2f,%.2f,%.2f) %.0f..%.0f sun=(%.2f,%.2f,%.2f)",
			e2.fog_col[0], e2.fog_col[1], e2.fog_col[2], e2.fog_near, e2.fog_far, e2.sun_col[0], e2.sun_col[1], e2.sun_col[2])
		sys.lighting_time_hours = -1
		sys.zone_destroy(z)
	}
}
