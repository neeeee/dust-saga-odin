package wall_probe

// Diagnostic: dump everything the collision build produced around a world
// point — wall segments (with move flags), stand/heights/band state on a
// small grid, and the source meshes' steep triangles + texture names — so
// filter decisions (grass vs block vs riser) are made on real geometry.
//
// Run from src/client:
//   odin build tools\wall_probe.odin -file -o wall_probe.exe
//   .\wall_probe.exe <x> <z> [zoneId]

import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import sys "../systems"
import rl "vendor:raylib"

main :: proc() {
	rl.SetTraceLogLevel(.WARNING)
	rl.SetConfigFlags({rl.ConfigFlag.WINDOW_HIDDEN})
	rl.InitWindow(320, 240, "wall probe")
	defer rl.CloseWindow()

	if len(os.args) < 3 {
		fmt.eprintfln("usage: wall_probe <x> <z> [zoneId]")
		return
	}
	out_path := ""
	if len(os.args) > 1 && os.args[1] == "scan" {
		scan_platforms(os.args[2], len(os.args) > 3 && os.args[3] == "1")
		return
	}
	px := f32(os.args[1] == "" ? 0 : 0) // parsed below
	px = f32(parse_f32(os.args[1]))
	pz := f32(parse_f32(os.args[2]))

	zone: ^sys.Zone_Definition
	if len(os.args) > 3 {
		zone = sys.load_zone_map(os.args[3])
	} else {
		// scan the Pandora zones until one's heightfield covers the point
		infos, err := os.read_all_directory_by_path("assets/maps", context.allocator)
		if err != nil {
			fmt.eprintfln("cannot list assets/maps: %v", err)
			return
		}
		for info in infos {
			if info.type != .Regular do continue
			if !strings.has_suffix(info.name, ".json") do continue
			z := sys.load_zone_map(info.name[:len(info.name) - 5])
			if z == nil || z.heightfield == nil {
				if z != nil do sys.zone_destroy(z)
				continue
			}
			hf := z.heightfield
			c := int(math.floor_f32((px - hf.origin_x) / hf.cell))
			r := int(math.floor_f32((pz - hf.origin_z) / hf.cell))
			if c >= 0 && c < hf.cols && r >= 0 && r < hf.rows && hf.valid[r * hf.cols + c] {
				zone = z
				fmt.eprintfln("zone: %s", z.id)
				break
			}
			sys.zone_destroy(z)
		}
	}
	if zone == nil || zone.heightfield == nil {
		fmt.eprintfln("no zone covers (%.1f, %.1f)", px, pz)
		return
	}
	defer sys.zone_destroy(zone)
	hf := zone.heightfield

	fmt.eprintfln("== point (%.1f, %.1f) ==", px, pz)
	h, ok := sys.terrain_height_at(hf, px, pz)
	fh, _ := sys.terrain_full_height_at(hf, px, pz)
	band := sys.terrain_band_kept_at(hf, px, pz)
	fmt.eprintfln("stand=%v(%.2f) full=%.2f band_kept=%v standable=%v walk=%v",
		ok, h, fh, band, sys.terrain_standable(hf, px, pz), sys.terrain_walkable(hf, px, pz))

	fmt.eprintfln("-- wall segs within 5u --")
	for seg in hf.segs {
		mx := (seg.x1 + seg.x2) * 0.5
		mz := (seg.z1 + seg.z2) * 0.5
		if math.sqrt((mx - px) * (mx - px) + (mz - pz) * (mz - pz)) > 5 do continue
		fmt.eprintfln(
			"  (%8.2f,%8.2f)-(%8.2f,%8.2f) y[%6.2f..%6.2f] h=%4.1f move=%v",
			seg.x1, seg.z1, seg.x2, seg.z2, seg.y_min, seg.y_max, seg.y_max - seg.y_min, seg.move)
	}

	fmt.eprintfln("-- stand grid (5x5, 1u; '.' = stand was cut from heights) --")
	c0 := int(math.floor_f32((px - hf.origin_x) / hf.cell))
	r0 := int(math.floor_f32((pz - hf.origin_z) / hf.cell))
	for dr in -2 ..= 2 {
		line: [dynamic]u8
		defer delete(line)
		for dc in -2 ..= 2 {
			c, r := c0 + dc, r0 + dr
			if c < 0 || c >= hf.cols || r < 0 || r >= hf.rows {
				append(&line, "  ?   ")
				continue
			}
			i := r * hf.cols + c
			append(&line, fmt.aprintf("%5.1f%c", hf.stand[i], hf.stand[i] != hf.heights[i] ? '.' : ' '))
		}
		fmt.eprintfln("  %s", string(line[:]))
	}

	// Ground-model triangles near the point: provenance-check for the
	// structure-wall exclusion (same triangles in both exports should match
	// by centroid).
	if zone.ground_model != nil {
		fmt.eprintfln("-- ground-model triangles within 6u --")
		gm := &zone.ground_model.model
		for mi in 0 ..< int(gm.meshCount) {
			mesh := &gm.meshes[mi]
			verts := mesh.vertices
			if verts == nil do continue
			vcount := int(mesh.vertexCount)
			if vcount == 0 do continue
			tri_n := vcount
			if mesh.indices != nil do tri_n = int(mesh.triangleCount) * 3
			hits := 0
			for t := 0; t + 2 < tri_n && hits < 4; t += 3 {
				ia := [3]int{t, t + 1, t + 2}
				if mesh.indices != nil {
					ia[0] = int(mesh.indices[t])
					ia[1] = int(mesh.indices[t + 1])
					ia[2] = int(mesh.indices[t + 2])
					if ia[0] >= vcount || ia[1] >= vcount || ia[2] >= vcount do continue
				}
				ax, ay, az := verts[ia[0] * 3], verts[ia[0] * 3 + 1], verts[ia[0] * 3 + 2]
				bx, by, bz := verts[ia[1] * 3], verts[ia[1] * 3 + 1], verts[ia[1] * 3 + 2]
				cx, cy, cz := verts[ia[2] * 3], verts[ia[2] * 3 + 1], verts[ia[2] * 3 + 2]
				mx := (ax + bx + cx) / 3
				mz := (az + bz + cz) / 3
				if math.sqrt((mx - px) * (mx - px) + (mz - pz) * (mz - pz)) > 6 do continue
				hits += 1
				fmt.eprintfln(
					"  gm %-5d v=(%7.2f,%6.2f,%7.2f) y[%6.2f..%6.2f] c=(%7.2f,%7.2f)",
					mi, ax, ay, az, min(min(ay, by), cy), max(max(ay, by), cy), mx, mz)
			}
		}
	}

	// Walk-in simulation: from 5u out in each cardinal direction, walk
	// toward the point and log any detach/buried/fall-below-floor event.
	fmt.eprintfln("-- walk-in simulation --")
	dirs_x := [4]f32{1, -1, 0, 0}
	dirs_z := [4]f32{0, 0, 1, -1}
	for dir in 0 ..< 4 {
		dx := dirs_x[dir]
		dz := dirs_z[dir]
		start_x, start_z := px - dx * 5, pz - dz * 5
		pos := rl.Vector3{start_x, 0, start_z}
		if h, ok := sys.terrain_height_at(hf, start_x, start_z); ok {
			pos.y = h
		}
		floor_y := pos.y
		vert := sys.Vertical_State{grounded = true}
		events := 0
		stuck_run := 0
		last_x, last_z := pos.x, pos.z
		for step in 0 ..< 360 {
			pos, vert = sys.terrain_move(zone, pos, dx * 0.06, dz * 0.06, vert, 1.0 / 60.0)
			moved := math.sqrt((pos.x - last_x) * (pos.x - last_x) + (pos.z - last_z) * (pos.z - last_z))
			last_x, last_z = pos.x, pos.z
			if vert.grounded && moved < 0.005 {
				stuck_run += 1
				if stuck_run == 60 {
					// Real stuck only when nothing explains the block: the
					// ground ahead is standable, not a rise (the step gate
					// would rightly block that), and no movement wall is
					// holding the actor (walls blocking is walls working).
					ax, az := pos.x + dx * 0.6, pos.z + dz * 0.6
					f_ahead, fa_ok := sys.terrain_height_at(hf, ax, az)
					wall_holds := false
					if len(hf.seg_grid) > 0 {
						sc := int(math.floor_f32((pos.x - hf.origin_x) / sys.SEG_GRID_CELL))
						sr := int(math.floor_f32((pos.z - hf.origin_z) / sys.SEG_GRID_CELL))
						if sc >= 0 && sc < hf.seg_grid_cols && sr >= 0 && sr < hf.seg_grid_rows {
							k := sr * hf.seg_grid_cols + sc
							for p in hf.seg_ptr[k] ..< hf.seg_ptr[k + 1] {
								seg := hf.segs[hf.seg_grid[p]]
								if !seg.move do continue
								if seg.y_max <= pos.y + 0.05 || seg.y_min >= pos.y + 1.65 do continue
								ex := seg.x2 - seg.x1
								ez := seg.z2 - seg.z1
								d_x := pos.x - seg.x1
								d_z := pos.z - seg.z1
								l2 := ex * ex + ez * ez
								t := l2 > 1e-9 ? clamp((d_x * ex + d_z * ez) / l2, 0, 1) : 0
								cx := seg.x1 + ex * t - pos.x
								cz := seg.z1 + ez * t - pos.z
								if cx * cx + cz * cz < 0.7 * 0.7 {
									wall_holds = true
									break
								}
							}
						}
					}
					if !wall_holds && sys.terrain_standable(hf, ax, az) &&
						(!fa_ok || f_ahead <= pos.y + sys.MAX_STEP_UP) {
						fmt.eprintfln(
							"  dir %d step %3d STUCK in open ground at (%.2f, %.2f, %.2f)",
							dir, step, pos.x, pos.y, pos.z)
						events += 1
					}
				}
			} else {
				stuck_run = 0
			}
			if pos.y < floor_y - 1.0 && events < 12 {
				// sunk test: below the LOCAL field, not the (possibly far
				// away) start height
				f_here, f_ok := sys.terrain_height_at(hf, pos.x, pos.z)
				if f_ok && pos.y < f_here - 0.8 {
					events += 1
					fmt.eprintfln(
						"  dir %d step %3d SUNK at (%.2f, %.2f, %.2f) field=%.2f grounded=%v",
						dir, step, pos.x, pos.y, pos.z, f_here, vert.grounded)
				}
			}
			if !vert.grounded && events < 6 {
				events += 1
				mh, mok := sys.terrain_mesh_ground_at(
					hf, pos.x, pos.z, 1e30, 1e30, false, 1e30)
				ph, pok := sys.terrain_mesh_ground_at(
					hf, pos.x, pos.z, pos.y + sys.MAX_STEP_UP + 0.15, 1e30, false, 1e30)
				fh, fok := sys.terrain_height_at(hf, pos.x, pos.z)
				gh, gok := sys._terrain_ground_at(hf, pos.x, pos.z, pos.y + sys.MAX_STEP_UP, pos.y)
				fmt.eprintfln(
					"  dir %d step %3d DETACH at (%.2f, %.2f, %.2f) vy=%.2f | step=%v(%.2f) press-mesh=%v(%.2f) field=%v(%.2f)",
					dir, step, pos.x, pos.y, pos.z, vert.vy,
					gok, gh, pok, ph, fok, fh)
			}
		}
		if events == 0 {
			fmt.eprintfln("  dir %d: clean (ended (%.2f, %.2f, %.2f))", dir, pos.x, pos.y, pos.z)
		}
	}

	// Source geometry: triangles of every mesh near the point (any size),
	// mesh index cross-referenced against the GLB's node/material names.
	fmt.eprintfln("-- nearby mesh triangles (within 6u) --")
	model := zone.terrain.model
	for mi in 0 ..< int(model.meshCount) {
		mesh := &model.meshes[mi]
		verts := mesh.vertices
		if verts == nil do continue
		vcount := int(mesh.vertexCount)
		if vcount == 0 do continue
		tri_n := vcount
		if mesh.indices != nil do tri_n = int(mesh.triangleCount) * 3
		hits := 0
		for t := 0; t + 2 < tri_n && hits < 5; t += 3 {
			ia := [3]int{t, t + 1, t + 2}
			if mesh.indices != nil {
				ia[0] = int(mesh.indices[t])
				ia[1] = int(mesh.indices[t + 1])
				ia[2] = int(mesh.indices[t + 2])
				if ia[0] >= vcount || ia[1] >= vcount || ia[2] >= vcount do continue
			}
			ax, ay, az := verts[ia[0] * 3], verts[ia[0] * 3 + 1], verts[ia[0] * 3 + 2]
			bx, by, bz := verts[ia[1] * 3], verts[ia[1] * 3 + 1], verts[ia[1] * 3 + 2]
			cx, cy, cz := verts[ia[2] * 3], verts[ia[2] * 3 + 1], verts[ia[2] * 3 + 2]
			mx := (ax + bx + cx) / 3
			mz := (az + bz + cz) / 3
			if math.sqrt((mx - px) * (mx - px) + (mz - pz) * (mz - pz)) > 6 do continue
			ny := (bz - az) * (cx - ax) - (bx - ax) * (cz - az)
			nx := (by - ay) * (cz - az) - (bz - az) * (cy - ay)
			nz := (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
			nl := math.sqrt(nx * nx + ny * ny + nz * nz)
			if nl < 1e-9 do continue
			steep := abs(ny) / nl
			e0 := math.sqrt((bx - ax) * (bx - ax) + (bz - az) * (bz - az))
			e1 := math.sqrt((cx - bx) * (cx - bx) + (cz - bz) * (cz - bz))
			e2 := math.sqrt((ax - cx) * (ax - cx) + (az - cz) * (az - cz))
			extent := max(max(e0, e1), e2)
			if extent < 0.05 do continue
			hits += 1
			fmt.eprintfln(
				"  mesh %-5d v=(%7.2f,%6.2f,%7.2f) steep=%.2f ext=%.2f y[%6.2f..%6.2f] c=(%7.2f,%7.2f)",
				mi, ax, ay, az, steep, extent,
				min(min(ay, by), cy), max(max(ay, by), cy), mx, mz)
		}
	}
}

parse_f32 :: proc(s: string) -> f64 {
	v := 0.0
	neg := false
	i := 0
	if len(s) > 0 && (s[0] == '-' || s[0] == '+') {
		neg = s[0] == '-'
		i = 1
	}
	for c in s[i:] {
		if c >= '0' && c <= '9' {
			v = v * 10 + f64(c - '0')
		} else if c == '.' || c == ',' {
			frac := 0.0
			scale := 0.1
			for d in s[i + 1 :] {
				if d >= '0' && d <= '9' {
					frac += f64(d - '0') * scale
					scale *= 0.1
				}
			}
			v += frac
			break
		}
	}
	return neg ? -v : v
}

// List raised walkable platforms: walkable cells standing ≥1.5u above
// everything within 2 cells (lookout decks, plazas on pillars). Clustered
// by proximity so each structure prints once.
scan_platforms :: proc(zone_id: string, _detailed: bool) {
	zone := sys.load_zone_map(zone_id)
	if zone == nil || zone.heightfield == nil {
		fmt.eprintfln("zone %s has no heightfield", zone_id)
		return
	}
	defer sys.zone_destroy(zone)
	hf := zone.heightfield
	found := 0
	for r in 3 ..< hf.rows - 3 {
		for c in 3 ..< hf.cols - 3 {
			i := r * hf.cols + c
			if !hf.walk[i] do continue
			h := hf.stand[i]
			max_around := f32(-1e30)
			for dr in -2 ..= 2 {
				for dc in -2 ..= 2 {
					if abs(dc) <= 1 && abs(dr) <= 1 do continue // top itself
					j := (r + dr) * hf.cols + (c + dc)
					if hf.valid[j] && hf.stand[j] > max_around do max_around = hf.stand[j]
				}
			}
			if h - max_around > 1.5 {
				fmt.eprintfln(
					"platform near (%.1f, %.2f, %.1f): %.1fu above surroundings",
					hf.origin_x + (f32(c) + 0.5) * hf.cell, h,
					hf.origin_z + (f32(r) + 0.5) * hf.cell, h - max_around)
				found += 1
				if found >= 12 do return
			}
		}
	}
	if found == 0 do fmt.eprintfln("no raised platforms found")
}
