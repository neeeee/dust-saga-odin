package systems

import "core:math"
import "core:os"
import rl "vendor:raylib"

// Automated play test (-autoplay on the command line, or --autoplay): drives
// the whole client — login with user/pass, character select (FemHPaladin),
// then a fast wandering run in-world — while logging position + elevation
// data to autoplay_log.csv (time, zone, x, y, z, field height, mesh height,
// delta). The log is the collision troubleshooting dataset.

autoplay: struct {
	enabled: bool,
	heading: f32, // wander direction, radians (camera space)
	turn_in: f32, // seconds until the next heading change
}

AUTO_USER      :: "user"
AUTO_PASS      :: "pass"
AUTO_CHARACTER :: "FemHPaladin"
AUTO_SPEED     :: 25.0
AUTO_LOG_PATH  :: "autoplay_log.csv"

log_file: ^os.File
log_open: bool

autoplay_parse_args :: proc() {
	for a in os.args {
		if a == "-autoplay" || a == "--autoplay" do autoplay.enabled = true
	}
}

// Injects a fast wander pattern into the polled input (called from
// poll_input, BEFORE the camera-relative movement application). Direction
// changes every 1-3s; always sprinting at AUTO_SPEED. Near the terrain
// border the wander is overridden with steering back toward the map center,
// so the run never leaves the map.
autoplay_drive_input :: proc(state: ^Input_State, p: ^Local_Player, zone: ^Zone_Definition) {
	debug_move_mult = AUTO_SPEED

	autoplay.turn_in -= rl.GetFrameTime()
	if autoplay.turn_in <= 0 {
		autoplay.turn_in = 1.0 + f32(rl.GetRandomValue(0, 2000)) / 1000.0
		autoplay.heading += (f32(rl.GetRandomValue(0, 240)) - 120.0) * math.PI / 180.0
	}
	state.move_x = math.cos(autoplay.heading)
	state.move_z = math.sin(autoplay.heading)
	state.moving = true
	state.sprint = true

	// Border steering: outside the inner 30u of the terrain rect, walk
	// toward the map center instead. The injected move vector is
	// camera-relative (rotated by cam yaw downstream), so the world
	// direction is inverse-rotated into camera space here.
	hf := zone != nil ? zone.heightfield : nil
	if hf == nil do return
	m := f32(30.0)
	x0 := hf.origin_x + m
	x1 := hf.origin_x + f32(hf.cols) * hf.cell - m
	z0 := hf.origin_z + m
	z1 := hf.origin_z + f32(hf.rows) * hf.cell - m
	px, pz := p.position.x, p.position.z
	if px < x0 || px > x1 || pz < z0 || pz > z1 {
		cx := hf.origin_x + f32(hf.cols) * hf.cell * 0.5
		cz := hf.origin_z + f32(hf.rows) * hf.cell * 0.5
		wx, wz := cx - px, cz - pz
		len := math.sqrt(wx * wx + wz * wz)
		if len > 0.001 {
			wx /= len
			wz /= len
			sin_y := math.sin(cam_control.yaw)
			cos_y := math.cos(cam_control.yaw)
			state.move_x = wx * cos_y - wz * sin_y
			state.move_z = wx * sin_y + wz * cos_y
			state.moving = true
			state.sprint = true
		}
	}
}

autoplay_log_line :: proc(line: string) {
	if !log_open {
		log_file, _ = os.create(AUTO_LOG_PATH)
		header := "t,zone,x,y,z,field_y,mesh_y,delta,speed\n"
		os.write(log_file, transmute([]u8)header)
		log_open = true
	}
	os.write(log_file, transmute([]u8)line)
	os.flush(log_file)
}
