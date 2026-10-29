package stuck_probe

// Dumps the collision state around a reported stuck point and simulates
// walking out of it at several speeds. Run from src/client.

import "core:fmt"
import "core:math"
import sys "../systems"
import rl "vendor:raylib"

STUCK_X, STUCK_Z :: f32(191.1), f32(-204.9)

reason_char :: proc(r: u8) -> u8 {
	chars := ".h#sewomHW" // 0=walk,1=hole,2=slope,3=step,4=erode,5=steep,6=obstacle,7=margin,8=hit,9=wall
	if int(r) < len(chars) do return chars[r]
	return '?'
}

walk_out :: proc(zone: ^sys.Zone_Definition, speed, dt: f32) {
	pos := rl.Vector3{STUCK_X, 0, STUCK_Z}
	if h, ok := sys.terrain_height_at(zone.heightfield, STUCK_X, STUCK_Z); ok do pos.y = h
	vert := sys.Vertical_State{grounded = true}
	fmt.eprintfln("  speed %.1f u/s (dt=%.3f, %.2fu/frame) from (%.2f,%.2f,%.2f):", speed, dt, speed * dt, pos.x, pos.y, pos.z)
	for dir in 0 ..< 8 {
		ang := f32(dir) * (math.PI / 4.0)
		dx := math.cos(ang) * speed * dt
		dz := math.sin(ang) * speed * dt
		p := pos
		v := vert
		frames := int(1.5 / dt)
		start := p
		moved := f32(0)
		for i in 0 ..< frames {
			prev := p
			p, v = sys.terrain_move(zone, p, dx, dz, v, dt)
			moved += math.sqrt((p.x - prev.x) * (p.x - prev.x) + (p.z - prev.z) * (p.z - prev.z))
		}
		net := math.sqrt((p.x - start.x) * (p.x - start.x) + (p.z - start.z) * (p.z - start.z))
		fmt.eprintfln(
			"    dir %d: net=(%+.2f,%+.2f) |net|=%5.2f path=%5.2f end_y=%6.2f %s",
			dir, p.x - start.x, p.z - start.z, net, moved, p.y,
			net > 0.8 ? "ESCAPED" : "STUCK",
		)
	}
}

// Settle an actor at (x, z) and require outward progress in all 8
// directions at normal walk speed. Returns the number of blocked dirs.
stuck_dirs :: proc(zone: ^sys.Zone_Definition, x, z, speed, dt: f32) -> (int, f32) {
	hf := zone.heightfield
	pos := rl.Vector3{x, 0, z}
	if h, ok := sys.terrain_height_at(hf, x, z); ok do pos.y = h
	blocked := 0
	worst := f32(0)
	for dir in 0 ..< 8 {
		ang := f32(dir) * (math.PI / 4.0)
		dx := math.cos(ang) * speed * dt
		dz := math.sin(ang) * speed * dt
		p := pos
		v := sys.Vertical_State{grounded = true}
		frames := int(1.0 / dt)
		net := f32(0)
		for i in 0 ..< frames {
			p, v = sys.terrain_move(zone, p, dx, dz, v, dt)
		}
		net = math.sqrt((p.x - pos.x) * (p.x - pos.x) + (p.z - pos.z) * (p.z - pos.z))
		worst = max(worst, net)
		if net < 0.5 {
			blocked += 1
		}
	}
	return blocked, worst
}

sweep_zone :: proc(zone_id: string, step: f32) {
	rl.SetTraceLogLevel(.WARNING)
	rl.SetConfigFlags({rl.ConfigFlag.WINDOW_HIDDEN})
	rl.InitWindow(320, 240, "stuck sweep")
	defer rl.CloseWindow()

	zone := sys.load_zone_map(zone_id)
	if zone == nil || zone.heightfield == nil {
		fmt.eprintfln("FAIL: zone %s did not load", zone_id)
		return
	}
	hf := zone.heightfield
	fmt.eprintfln("sweep %s (step %.0fu, walk-out 1s at 4.5 u/s):", zone_id, step)
	stuck := 0
	suspicious := 0
	checked := 0
	for wz := hf.origin_z + hf.cell; wz < hf.origin_z + f32(hf.rows) * hf.cell; wz += step {
		for wx := hf.origin_x + hf.cell; wx < hf.origin_x + f32(hf.cols) * hf.cell; wx += step {
			if !sys.terrain_standable(hf, wx, wz) do continue
			b, worst := stuck_dirs(zone, wx, wz, 4.5, 1.0 / 60.0)
			checked += 1
			if b >= 8 {
				stuck += 1
				h, _ := sys.terrain_height_at(hf, wx, wz)
				fmt.eprintfln("  PINNED (%.1f,%.2f,%.1f) stand=%.2f blocked=%d/8 worst_net=%.2f",
					wx, h, wz, h, b, worst)
			} else if b >= 6 do suspicious += 1
		}
	}
	fmt.eprintfln("  %d points checked, %d pinned, %d suspicious(6-7 dirs)", checked, stuck, suspicious)
	sys.zone_destroy(zone)
}

main :: proc() {
	rl.SetTraceLogLevel(.WARNING)
	rl.SetConfigFlags({rl.ConfigFlag.WINDOW_HIDDEN})
	rl.InitWindow(320, 240, "stuck probe")
	defer rl.CloseWindow()

	zone := sys.load_zone_map("3001006")
	if zone == nil || zone.heightfield == nil {
		fmt.eprintfln("FAIL: zone 3001006 did not load")
		return
	}
	hf := zone.heightfield
	fmt.eprintfln("zone 3001006 grid=%dx%d cell=%.1f origin=(%.1f,%.1f) min_y=%.2f max_y=%.2f segs=%d",
		hf.cols, hf.rows, hf.cell, hf.origin_x, hf.origin_z, hf.min_y, hf.max_y, len(hf.segs))

	h, hok := sys.terrain_height_at(hf, STUCK_X, STUCK_Z)
	prop_ok := sys.terrain_band_kept_at(hf, STUCK_X, STUCK_Z)
	mt, mt_ok := sys.terrain_mesh_ground_at(hf, STUCK_X, STUCK_Z, 1e30, -1e30, false, -1e30)
	fmt.eprintfln("stuck point (%.1f, %.1f): stand=%.2f(ok=%v) prop_ok=%v mesh=%.2f(%v)",
		STUCK_X, STUCK_Z, h, hok, prop_ok, mt, mt_ok)

	// Wall segments within 5u.
	fmt.eprintfln("wall segs within 5u:")
	for seg, si in hf.segs {
		ex := seg.x2 - seg.x1
		ez := seg.z2 - seg.z1
		dx2 := STUCK_X - seg.x1
		dz2 := STUCK_Z - seg.z1
		len2 := ex * ex + ez * ez
		t := f32(0)
		if len2 > 1e-9 {
			t = (dx2 * ex + dz2 * ez) / len2
			t = min(max(t, 0), 1)
		}
		cx := seg.x1 + ex * t
		cz := seg.z1 + ez * t
		d := math.sqrt((STUCK_X - cx) * (STUCK_X - cx) + (STUCK_Z - cz) * (STUCK_Z - cz))
		if d <= 5 {
			fmt.eprintfln("  seg %d (%.2f,%.2f)-(%.2f,%.2f) y=[%.2f..%.2f] dist=%.2f",
				si, seg.x1, seg.z1, seg.x2, seg.z2, seg.y_min, seg.y_max, d)
		}
	}

	walk_out(zone, 4.5, 1.0 / 60.0)
	sys.zone_destroy(zone)

	sweep_zone("3001006", 12.0)
	sweep_zone("3001001", 12.0)
	detail_at("3001006", 178.6, -84.6)
	detail_at("3001006", 182.0, -151.4)
	detail_at("3001006", 182.2, -167.2)
	detail_at("3001006", 171.6, -180.6)
	detail_at("3001001", 85.0, -71.0)

	float_zone := sys.load_zone_map("3001006")
	if float_zone != nil && float_zone.heightfield != nil {
		float_check(float_zone, []rl.Vector3{
			{182.0, 0, -151.4},
			{182.2, 0, -167.2},
			{171.6, 0, -180.6},
			{178.6, 0, -84.6},
		})
		sys.zone_destroy(float_zone)
	}
}

// Float check: field vs exact mesh vs where the movement rule puts the feet.
float_check :: proc(zone: ^sys.Zone_Definition, points: []rl.Vector3) {
	hf := zone.heightfield
	fmt.eprintfln("float check:")
	for p in points {
		field, fok := sys.terrain_height_at(hf, p.x, p.z)
		mt, mt_ok := sys.terrain_mesh_ground_at(hf, p.x, p.z, 1e30, -1e30, false, -1e30)
		// the movement-rule probe (same as the grounded branch)
		stand_ref, field_ok := sys.terrain_height_at(hf, p.x, p.z)
		g, gok := sys.terrain_mesh_ground_at(hf, p.x, p.z, field+sys.MAX_STEP_UP, field, field_ok, stand_ref)
		feet := field
		if gok do feet = g
		fmt.eprintfln("  (%.1f,%.1f): field=%.2f(ok=%v) mesh_top=%.2f(%v) -> feet=%.2f ring_gap=%.2f",
			p.x, p.z, field, fok, mt, mt_ok, feet, feet - field)
	}
}

// Drop test: start airborne at (x, y0, z) and fall. A healthy zone lands
// on rendered ground near the floor; a void fall never grounds.
drop_test :: proc(zone: ^sys.Zone_Definition, x, y0, z: f32) {
	p := rl.Vector3{x, y0, z}
	v := sys.Vertical_State{vy = 0, grounded = false, fall_start_y = y0}
	dt := f32(1.0 / 60.0)
	frames := 0
	for i in 0 ..< 600 {
		frames = i
		p, v = sys.terrain_move(zone, p, 0, 0, v, dt)
		if v.grounded do break
	}
	fmt.eprintfln("  drop (%.1f,%.2f,%.1f) -> (%.1f,%.2f,%.1f) %s after %d frames",
		x, y0, z, p.x, p.y, p.z, v.grounded ? "LANDED" : "STILL FALLING", frames)
}

// Full state dump + walk-out at an arbitrary point of a zone.
detail_at :: proc(zone_id: string, px, pz: f32) {
	rl.SetTraceLogLevel(.WARNING)
	rl.SetConfigFlags({rl.ConfigFlag.WINDOW_HIDDEN})
	rl.InitWindow(320, 240, "stuck detail")
	defer rl.CloseWindow()

	zone := sys.load_zone_map(zone_id)
	if zone == nil || zone.heightfield == nil do return
	hf := zone.heightfield
	fmt.eprintfln("detail %s at (%.1f, %.1f):", zone_id, px, pz)
	h, hok := sys.terrain_height_at(hf, px, pz)
	mt, mt_ok := sys.terrain_mesh_ground_at(hf, px, pz, 1e30, -1e30, false, -1e30)
	fmt.eprintfln("  stand=%.2f(ok=%v) mesh_any=%.2f(%v) prop_ok=%v", h, hok, mt, mt_ok,
		sys.terrain_band_kept_at(hf, px, pz))
	// where does rendered geometry actually sit around the field value?
	mr, mr_ok := sys.terrain_mesh_ground_at(hf, px, pz, h + 0.5, -1e30, false, -1e30)
	mb, mb_ok := sys.terrain_mesh_ground_at(hf, px, pz, h - 0.5, -1e30, false, -1e30)
	mdeep, mdeep_ok := sys.terrain_mesh_ground_at(hf, px, pz, h - 3.0, -1e30, false, -1e30)
	fmt.eprintfln("  mesh ≤ feet+0.5: %.2f(%v) | ≤ feet-0.5: %.2f(%v) | ≤ feet-3: %.2f(%v)",
		mr, mr_ok, mb, mb_ok, mdeep, mdeep_ok)
	// all triangles whose XZ barycentric contains the point
	{
		c := int(math.floor_f32((px - hf.origin_x) / hf.cell))
		r := int(math.floor_f32((pz - hf.origin_z) / hf.cell))
		fmt.eprintfln("  tris covering the point:")
		for dr := -1; dr <= 1; dr += 1 {
			for dc := -1; dc <= 1; dc += 1 {
				cc, rr := c + dc, r + dr
				if cc < 0 || cc >= hf.cols || rr < 0 || rr >= hf.rows do continue
				k := rr * hf.cols + cc
				for p in hf.mesh_ptr[k] ..< hf.mesh_ptr[k + 1] {
					tid := int(hf.mesh_tris[p])
					gid := tid * 9
					co := hf.mesh_coords
					ax, ay, az := co[gid], co[gid + 1], co[gid + 2]
					bx, by, bz := co[gid + 3], co[gid + 4], co[gid + 5]
					cx2, cy2, cz2 := co[gid + 6], co[gid + 7], co[gid + 8]
					denom := (bz - cz2) * (ax - cx2) + (cx2 - bx) * (az - cz2)
					if abs(denom) < 1e-9 do continue
					l1 := ((bz - cz2) * (px - cx2) + (cx2 - bx) * (pz - cz2)) / denom
					l2 := ((cz2 - az) * (px - cx2) + (ax - cx2) * (pz - cz2)) / denom
					l3 := 1.0 - l1 - l2
					if l1 < 0 || l2 < 0 || l3 < 0 do continue
					h_at := l1 * ay + l2 * by + l3 * cy2
					ext := max(max(ax, bx), cx2) - min(min(ax, bx), cx2)
					extz := max(max(az, bz), cz2) - min(min(az, bz), cz2)
					cls := "TERR"
					if tid >= hf.mesh_ground_count do cls = "OBJ "
					fmt.eprintfln("    %s x[%.1f..%.1f] z[%.1f..%.1f] (%.0fx%.0f) y=[%.2f,%.2f,%.2f] -> %.2f",
						cls,
						min(min(ax, bx), cx2), max(max(ax, bx), cx2),
						min(min(az, bz), cz2), max(max(az, bz), cz2),
						ext, extz, ay, by, cy2, h_at)
				}
			}
		}
	}

	c0 := int(math.floor_f32((px - hf.origin_x) / hf.cell)) - 4
	r0 := int(math.floor_f32((pz - hf.origin_z) / hf.cell)) - 4
	fmt.eprintfln("  stand | heights | reason, 9x9 (rows=z-, cols=x+):")
	for rr := 0; rr < 9; rr += 1 {
		fmt.eprint("    ")
		for cc := 0; cc < 9; cc += 1 {
			i := (r0 + rr) * hf.cols + (c0 + cc)
			fmt.eprintf("%6.2f ", hf.stand[i])
		}
		fmt.eprint(" |")
		for cc := 0; cc < 9; cc += 1 {
			i := (r0 + rr) * hf.cols + (c0 + cc)
			fmt.eprintf("%6.2f ", hf.heights[i])
		}
		fmt.eprint(" |")
		for cc := 0; cc < 9; cc += 1 {
			i := (r0 + rr) * hf.cols + (c0 + cc)
			fmt.eprintf("%c%c ", hf.valid[i] ? '#' : ' ', reason_char(hf.reasons[i]))
		}
		fmt.eprintfln("")
	}
	fmt.eprintfln("  segs within 6u:")
	for seg, si in hf.segs {
		ex := seg.x2 - seg.x1
		ez := seg.z2 - seg.z1
		dx2 := px - seg.x1
		dz2 := pz - seg.z1
		len2 := ex * ex + ez * ez
		t := f32(0)
		if len2 > 1e-9 {
			t = (dx2 * ex + dz2 * ez) / len2
			t = min(max(t, 0), 1)
		}
		cx := seg.x1 + ex * t
		cz := seg.z1 + ez * t
		d := math.sqrt((px - cx) * (px - cx) + (pz - cz) * (pz - cz))
		if d <= 6 {
			fmt.eprintfln("    seg %d (%.2f,%.2f)-(%.2f,%.2f) y=[%.2f..%.2f] dist=%.2f",
				si, seg.x1, seg.z1, seg.x2, seg.z2, seg.y_min, seg.y_max, d)
		}
	}
	walk_out_at(zone, px, pz, 4.5, 1.0 / 60.0)
	// reproduce the reported fall: airborne from the ledge height nearby
	drop_test(zone, px, 5.71, pz)
	drop_test(zone, px, 2.13, pz)
	sys.zone_destroy(zone)
}

walk_out_at :: proc(zone: ^sys.Zone_Definition, sx, sz, speed, dt: f32) {
	pos := rl.Vector3{sx, 0, sz}
	if h, ok := sys.terrain_height_at(zone.heightfield, sx, sz); ok do pos.y = h
	fmt.eprintfln("  walk-out at %.1f u/s:", speed)
	for dir in 0 ..< 8 {
		ang := f32(dir) * (math.PI / 4.0)
		dx := math.cos(ang) * speed * dt
		dz := math.sin(ang) * speed * dt
		p := pos
		v := sys.Vertical_State{grounded = true}
		for i in 0 ..< int(1.5 / dt) {
			p, v = sys.terrain_move(zone, p, dx, dz, v, dt)
		}
		net := math.sqrt((p.x - sx) * (p.x - sx) + (p.z - sz) * (p.z - sz))
		fmt.eprintfln("    dir %d: net=%5.2f end=(%.1f,%.2f,%.1f) %s", dir, net, p.x, p.y, p.z,
			net > 0.8 ? "ESCAPED" : "STUCK")
	}
}
