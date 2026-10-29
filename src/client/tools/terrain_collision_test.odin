package terrain_collision_test

// Headless smoke test for the terrain collision/elevation heightfields:
// loads real zone JSONs through load_zone_map (which builds the heightfield
// from the terrain GLB), then reports grid size, coverage, walkability, and
// what terrain_place does with the server's player spawns. Also probes
// terrain_ray_hit straight down at each spawn — it must hit the surface at
// (roughly) the heightfield height.
//
// Run from src/client (the assets/ paths are relative).

import "core:fmt"
import "core:math"
import "core:time"
import sys "../systems"
import rl "vendor:raylib"

Zone_Case :: struct {
	zone_id: string,
	spawn_x: f32,
	spawn_z: f32,
}

cases := [?]Zone_Case{
	{"1001001", -12, 52}, // T01_01 town — server playerSpawn (-12, 52)
	{"2001002", 20, 32},  // F01_02 field — server playerSpawn (20, 32)
	{"3001001", 0, 0},    // D01_01 dungeon
	{"1003001", 0, 12},   // T03 town — server playerSpawn (0, 12)
	{"3001101", 0, 0},    // D01_01_a variant — its own _hit proxies
	{"2002003", 0, 0},    // F02_03 field with hit proxies
	{"3001006", 191, -205}, // D01_06 — reported stuck point (191.1, -204.9)
}

main :: proc() {
	rl.SetTraceLogLevel(.WARNING)
	rl.SetConfigFlags({rl.ConfigFlag.WINDOW_HIDDEN})
	rl.InitWindow(320, 240, "terrain collision test")
	defer rl.CloseWindow()

	failed := 0
	for tc in cases {
		t0 := time.now()
		zone := sys.load_zone_map(tc.zone_id)
		load_ms := time.duration_milliseconds(time.since(t0))

		if zone == nil || !zone.loaded {
			fmt.eprintfln("FAIL %s: zone did not load", tc.zone_id)
			failed += 1
			continue
		}
		if zone.heightfield == nil {
			fmt.eprintfln("FAIL %s: no heightfield (terrain=%v)", tc.zone_id, zone.terrain != nil)
			failed += 1
			sys.zone_destroy(zone)
			continue
		}

		hf := zone.heightfield
		valid, walk := 0, 0
		for i in 0 ..< len(hf.valid) {
			if hf.valid[i] do valid += 1
			if hf.walk[i] do walk += 1
		}
		total := len(hf.valid)

		h, hok := sys.terrain_height_at(hf, tc.spawn_x, tc.spawn_z)

		// Cast from just above the stand height: the exact tracer hits ANY
		// bucketed surface (canopies included — correct for click picking),
		// and forested spawns sit under trees.
		ray := rl.Ray{
			position  = {tc.spawn_x, h + 2, tc.spawn_z},
			direction = {0, -1, 0},
		}
		hit, point := sys.terrain_ray_hit(zone, ray)
		ray_ok := hit && abs(point.y - h) < 0.5
		fmt.eprintfln("     ray: hit=%v point.y=%.2f stand_h=%.2f delta=%.2f", hit, point.y, h, point.y - h)

		// What the game actually does with a flat-world spawn: place it.
		placed := sys.terrain_place(zone, {tc.spawn_x, 0, tc.spawn_z})
		placed_walk := sys.terrain_standable(hf, placed.x, placed.z)

		fmt.eprintfln(
			"%s %s grid=%dx%d cell=%.1f load=%.0fms cover=%.1f%% walk=%.1f%%(of covered) raw_h=%.2f raw_walk=%v placed=(%.1f,%.2f,%.1f) placed_walk=%v ray_down=%v",
			ray_ok && hok && placed_walk && walk > 0 ? "OK  " : "FAIL",
			tc.zone_id, hf.cols, hf.rows, hf.cell, load_ms,
			f32(valid) / f32(total) * 100,
			valid > 0 ? f32(walk) / f32(valid) * 100 : 0,
			h, sys.terrain_standable(hf, tc.spawn_x, tc.spawn_z),
			placed.x, placed.y, placed.z, placed_walk, hit,
		)
		if !(ray_ok && hok && placed_walk && walk > 0) do failed += 1

		// Random-walk the movement resolver from the placed spawn: every
		// landing must sit on a walkable cell (or be an escape from a
		// blocked start), grounded moves must sit exactly on the probed
		// surface (no floating, no sinking), rises are limited to one step
		// per move, and airborne moves never rise at all (gravity only
		// pulls). Falls are legal — ledges detach instead of teleporting.
		pos := placed
		vert := sys.Vertical_State{grounded = true}
		last_ground_y := placed.y
		rng := rl.GetRandomValue(1, 1 << 30)
		bad_landing, bad_float, bad_rise, clamped := 0, 0, 0, 0
		airborne_steps := 0
		airborne_run := 0
		steps := 20000
		for i in 0 ..< steps {
			ang := f32(rng % 3600) * (2.0 * math.PI / 3600.0)
			rng = rl.GetRandomValue(1, 1 << 30)
			dist := 0.05 + f32(rng % 100) * 0.005
			prev_y := pos.y
			pos, vert = sys.terrain_move(
				zone, pos, math.cos(ang) * dist, math.sin(ang) * dist, vert, 1.0 / 60.0,
			)
			if !sys.terrain_standable(hf, pos.x, pos.z) {
				// Only legal if the resolver is in escape mode, i.e. the
				// previous cell was blocked too.
				bad_landing += 1
			}
			// Authoritative ground per the movement rule (same probe the
			// resolver uses): highest mesh surface under prev_y + step,
			// else the field clamped to the local visual surface.
			th, th_ok := sys._terrain_ground_at(hf, pos.x, pos.z, prev_y + sys.MAX_STEP_UP, prev_y)
			if vert.grounded {
				if th_ok {
					// Planted actors sit ON the surface they probed. Falls
					// relocated by the sheer-column/failsafe paths land on
					// the field while the exact probe may sit a hair higher
					// for one transient frame (it re-snaps next move).
					if pos.y > th + 0.06 do bad_float += 1
					if pos.y < th - 0.25 do clamped += 1
				}
				// Rises are measured from the last GROUNDED height: a fall
				// (sheer-column relocation included) may legitimately end
				// below it, never more than a step above it.
				if pos.y > last_ground_y + sys.MAX_STEP_UP + 0.01 {
					bad_rise += 1
					if bad_rise < 4 do fmt.eprintfln(
						"     RISE grounded (%.1f,%.2f,%.1f) last_ground=%.2f -> y=%.2f th_ok=%v th=%.2f",
						pos.x, pos.y, pos.z, last_ground_y, pos.y, th_ok, th)
				}
				last_ground_y = pos.y
			} else {
				airborne_steps += 1
				airborne_run += 1
				if pos.y > last_ground_y + 0.01 {
					bad_rise += 1
					if bad_rise < 4 do fmt.eprintfln(
						"     RISE airborne (%.1f,%.2f,%.1f) last_ground=%.2f -> y=%.2f",
						pos.x, pos.y, pos.z, last_ground_y, pos.y)
				}
				if airborne_run == 300 {
					// Dump every probe that could end this fall.
					fh, fok := sys.terrain_height_at(hf, pos.x, pos.z)
					mh, mok := sys.terrain_mesh_ground_at(
						hf, pos.x, pos.z, pos.y + 1.0, pos.y, false, fh)
					standable := sys.terrain_standable(hf, pos.x, pos.z)
					walkable := sys.terrain_walkable(hf, pos.x, pos.z)
					c := int(math.floor_f32((pos.x - hf.origin_x) / hf.cell))
					r := int(math.floor_f32((pos.z - hf.origin_z) / hf.cell))
					reason := u8(255)
					valid := false
					if c >= 0 && c < hf.cols && r >= 0 && r < hf.rows {
						reason = hf.reasons[r * hf.cols + c]
						valid = hf.valid[r * hf.cols + c]
					}
					fmt.eprintfln(
						"     FALLSTUCK pos=(%.1f,%.2f,%.1f) vy=%.2f cell=(%d,%d) valid=%v reason=%d standable=%v walkable=%v field=%v(%.2f) mesh=%v(%.2f) min_y=%.2f",
						pos.x, pos.y, pos.z, vert.vy, c, r, valid, reason,
						standable, walkable, fok, fh, mok, mh, hf.min_y)
				}
			}
			if vert.grounded do airborne_run = 0
		}
		movement_ok := bad_landing == 0 && bad_float == 0 && bad_rise == 0
		fmt.eprintfln(
			"     random walk %d steps: bad_landings=%d float=%d rise_violations=%d sunk=%d airborne=%d %s",
			steps, bad_landing, bad_float, bad_rise, clamped, airborne_steps, movement_ok ? "OK" : "FAIL",
		)
		if airborne_steps > 5000 {
			fmt.eprintfln(
				"     NOTE stuck falling: final=(%.1f,%.2f,%.1f) vy=%.2f grounded=%v",
				pos.x, pos.y, pos.z, vert.vy, vert.grounded)
		}
		if !movement_ok do failed += 1

		// ASCII overview of walkability (~90x45 chars), '#'=walkable,
		// '.'=covered-not-walkable, ' '=void. Boxes of '.' in open plazas
		// would mean prop collision is leaking back in.
		{
			step_c := max(1, hf.cols / 90)
			step_r := max(1, hf.rows / 45)
			fmt.eprintfln("     walk map (%dx%d cells/char, top=-z):", step_c, step_r)
			line: [dynamic]u8
			defer delete(line)
			for r0 := 0; r0 < hf.rows; r0 += step_r {
				clear(&line)
				for c0 := 0; c0 < hf.cols; c0 += step_c {
					walk_n, cov_n := 0, 0
					for r := r0; r < min(r0 + step_r, hf.rows); r += 1 {
						for c := c0; c < min(c0 + step_c, hf.cols); c += 1 {
							i := r * hf.cols + c
							if hf.valid[i] do cov_n += 1
							if hf.walk[i] do walk_n += 1
						}
					}
					ch := u8(' ')
					if cov_n > 0 {
						ch = '#' if walk_n > (cov_n / 2) else '.'
					}
					append(&line, ch)
				}
				fmt.eprintfln("     %s", string(line[:]))
			}

		{
			counts: [11]int
			for i in 0..<len(hf.reasons) do counts[min(int(hf.reasons[i]), 10)] += 1
			fmt.eprintfln("     reasons: walk=%d hole=%d slope=%d step=%d erode=%d steep=%d obstacle=%d margin=%d hit=%d wall=%d nostand=%d segs=%d",
				counts[0], counts[1], counts[2], counts[3], counts[4], counts[5], counts[6], counts[7], counts[8], counts[9], counts[10], len(hf.segs))
		}

			// Block-reason map for blocked cells (h=hole, s=slope, t=step,
			// e=erosion, w=steep wall, o=obstacle, m=margin).
			fmt.eprintfln("     reason map (h hole, s slope, t step, e erode, w steep, o obstacle, m margin):")
			for r0 := 0; r0 < hf.rows; r0 += step_r {
				clear(&line)
				for c0 := 0; c0 < hf.cols; c0 += step_c {
					counts: [11]int
					for r := r0; r < min(r0 + step_r, hf.rows); r += 1 {
						for c := c0; c < min(c0 + step_c, hf.cols); c += 1 {
							i := r * hf.cols + c
							counts[min(int(hf.reasons[i]), 10)] += 1
						}
					}
					ch := u8('#')
					if counts[0] < (counts[1] + counts[2] + counts[3] + counts[4] + counts[5] + counts[6] + counts[7]) {
						// dominant blocking reason in this block
						best, best_n := 1, counts[1]
						for k in 2 ..< 11 {
							if counts[k] > best_n {
								best, best_n = k, counts[k]
							}
						}
						reason_chars := "?hstewomxWN"
						ch = reason_chars[best]
					}
					append(&line, ch)
				}
				fmt.eprintfln("     %s", string(line[:]))
			}
		}

		// Second concurrent load genuinely reuses the cached model (the
		// first zone still holds a ref) → isolates JSON parse + heightfield
		// build cost from the GLB decode.
		t1 := time.now()
		zone2 := sys.load_zone_map(tc.zone_id)
		build_ms := time.duration_milliseconds(time.since(t1))
		fmt.eprintfln("     build only (shared model)=%.0fms", build_ms)
		sys.zone_destroy(zone2)
		sys.zone_destroy(zone)
	}

	if failed > 0 {
		fmt.eprintfln("DONE with %d failures", failed)
	} else {
		fmt.eprintfln("DONE all %d zones passed", len(cases))
	}
}
