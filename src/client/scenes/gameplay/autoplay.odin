package gameplay

import "core:fmt"
import "core:os"
import sys "../../systems"
import rl "vendor:raylib"

// Automated play (systems/autoplay, -autoplay): samples elevation data to
// autoplay_log.csv while the wander driver (autoplay_drive_input, called
// inside poll_input) runs the character around at high speed.

wander: struct {
	log_in: f32, // seconds until the next CSV sample
	file:    ^os.File,
	opened:  bool,
}

// Samples one elevation CSV line. Called from gameplay.update every frame;
// internally throttled to ~5 samples/s.
autoplay_log_tick :: proc(dt: f32) {
	wander.log_in -= dt
	if wander.log_in > 0 do return
	wander.log_in = 0.2

	p := state.player
	zone := state.ctx.zone
	zone_id := "-"
	if zone != nil do zone_id = zone.id

	hf := zone != nil ? zone.heightfield : nil
	field_y, field_ok := f32(0), false
	if hf != nil {
		field_y, field_ok = sys.terrain_height_at(hf, p.position.x, p.position.z)
	}
	mesh_y, mesh_ok := f32(0), false
	if hf != nil {
		mesh_y, mesh_ok = sys.terrain_mesh_ground_at(
			hf,
			p.position.x, p.position.z,
			p.position.y + sys.MAX_STEP_UP, p.position.y,
			field_ok, field_y,
		)
	}
	delta := f32(0)
	if mesh_ok do delta = p.position.y - mesh_y

	if !wander.opened {
		wander.file, _ = os.create(sys.AUTO_LOG_PATH)
		header := "t,zone,x,y,z,field_y,mesh_y,delta,speed\n"
		os.write(wander.file, transmute([]u8)header)
		wander.opened = true
	}
	line := fmt.aprintf("%.2f,%s,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%d\n",
		rl.GetTime(), zone_id,
		p.position.x, p.position.y, p.position.z,
		field_ok ? field_y : -999.0,
		mesh_ok ? mesh_y : -999.0,
		delta,
		i32(sys.debug_move_mult),
	)
	os.write(wander.file, transmute([]u8)line)
	os.flush(wander.file)
}
