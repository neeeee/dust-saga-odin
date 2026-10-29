package collision_probe

// Focused probe for the reported collision scenarios. Run from src/client:
//   odin run tools/collision_probe.odin -file -define:RAYLIB_SHARED=true

import "core:fmt"
import "core:math"
import sys "../systems"
import rl "vendor:raylib"

Point :: struct {
	name:    string,
	x, z:    f32,
	ref_dx:  f32, // offset for the ground reference sample
	ref_dz:  f32,
}

Cliff_Ref :: struct {
	jump: f32,
	x, z: f32,
}

points := [?]Point{
	{"grass tuft", -42.4, 83.7, -2.0, 0},
	{"tree area", -18.7, 66.0, 2.5, 0},
	{"bench A", 2.8, 85.0, -3.0, 0},
	{"bench B", 8.9, 113.2, 0, -3.0},
	{"fence 01a", 8.4, 42.0, 0, 2.5},
	{"fence 01b", -0.3, 63.1, 2.5, 0},
	{"fence A (rail)", -12.0, 41.9, -3.0, 0},
	{"fence B (rail)", -53.4, 51.6, -3.0, 0},
	{"tree 1 climb", -66.0, 46.5, -4.0, 0},
	{"tree 2 climb", -94.0, 49.6, -4.0, 0},
	{"stall 1 roof", -116.0, 51.9, -4.0, 0},
	{"stall 2", -196.0, 53.3, -4.0, 0},
	{"garden wall", -20.3, -69.1, -3.0, 0},
	{"rail fence (shot)", -51.5, 55.5, -3.0, 0},
	{"canopy roof (shot)", -42.2, 61.5, -4.0, 0},
	{"stall counter (shot)", -41.1, 63.5, 3.0, 0},
	{"tree trunk (shot)", 6.9, -52.3, -4.0, 0},
	{"wall base (shot)", -24.6, -24.4, 3.0, 0},
	{"alley sink 1", 26.8, -97.1, -3.0, 0},
	{"alley sink 2", 25.7, -105.1, 3.0, 0},
}

main :: proc() {
	rl.SetTraceLogLevel(.WARNING)
	rl.SetConfigFlags({rl.ConfigFlag.WINDOW_HIDDEN})
	rl.InitWindow(320, 240, "probe")
	defer rl.CloseWindow()

	zone := sys.load_zone_map("1003001")
	if zone == nil || !zone.loaded || zone.heightfield == nil {
		fmt.eprintfln("zone load failed")
		return
	}
	hf := zone.heightfield

	for p in points {
		h_here, h_here_ok := sys.terrain_height_at(hf, p.x, p.z)
		// movement-rule ground: anything at/below the field + a step
		h_mesh, mok := sys.terrain_mesh_ground_at(hf, p.x, p.z, 1e30, -1e30, h_here_ok, h_here)
		// terrain-class-only surface: what the GROUND geometry says here
		// (field gate "on" with an impossible reference rejects every
		// object-class triangle)
		h_terr, tok := sys.terrain_mesh_ground_at(hf, p.x, p.z, 1e30, -1e30, true, -1e30)
		h_eff := h_here
		if mok do h_eff = h_mesh
		h_ref, _ := sys.terrain_height_at(hf, p.x + p.ref_dx, p.z + p.ref_dz)
		// nearest wall segment
		best := f32(1e9)
		for seg in hf.segs {
			offs := [2]f32{0, 1}
			for off in offs {
				sx := seg.x1 + (seg.x2 - seg.x1) * off
				sz := seg.z1 + (seg.z2 - seg.z1) * off
				d := math.sqrt((sx - p.x) * (sx - p.x) + (sz - p.z) * (sz - p.z))
				best = min(best, d)
			}
		}
		fmt.eprintfln(
			"%-22s at (%6.1f,%6.1f): field=%6.2f mesh=%s terr=%s eff=%6.2f ref=%6.2f LIFT=%5.2f seg=%5.2f",
			p.name, p.x, p.z, h_here,
			mok ? fmt.aprintf("%6.2f", h_mesh) : "  n/a",
			tok ? fmt.aprintf("%6.2f", h_terr) : "  n/a",
			h_eff, h_ref, h_eff - h_ref, best,
		)
	}

	// Walk-through / walk-into simulations: 0.1u steps along a line.
	walk :: proc(zone: ^sys.Zone_Definition, x0, z0, x1, z1: f32, label: string) {
		pos := rl.Vector3{x0, 0, z0}
		if h, ok := sys.terrain_height_at(zone.heightfield, x0, z0); ok do pos.y = h
		vert := sys.Vertical_State{grounded = true}
		y_min, y_max := pos.y, pos.y
		dx, dz := x1 - x0, z1 - z0
		len := math.sqrt(dx * dx + dz * dz)
		dx, dz = dx / len, dz / len
		blocked_at := f32(-1)
		steps := int(len / 0.1)
		for i in 0 ..< steps {
			prev_x, prev_z := pos.x, pos.z
			pos, vert = sys.terrain_move(zone, pos, dx * 0.1, dz * 0.1, vert, 1.0 / 60.0)
			mvx := pos.x - prev_x
			mvz := pos.z - prev_z
			if math.sqrt(mvx * mvx + mvz * mvz) < 0.02 {
				blocked_at = f32(i) * 0.1
				break
			}
			y_min = min(y_min, pos.y)
			y_max = max(y_max, pos.y)
		}
		fmt.eprintfln(
			"%-28s (%6.1f,%6.1f)->(%6.1f,%6.1f): ended=(%6.2f,%6.2f) y=[%5.2f..%5.2f] span=%4.2f %s",
			label, x0, z0, x1, z1, pos.x, pos.z, y_min, y_max, y_max - y_min,
			blocked_at >= 0 ? fmt.aprintf("STOPPED at %.1fu", blocked_at) : "passed through",
		)
	}

	walk(zone, -46.4, 83.7, -38.4, 83.7, "grass spot, W->E")
	walk(zone, -18.7, 62.0, -18.7, 70.0, "tree spot, N->S")
	walk(zone, -1.2, 85.0, 6.8, 85.0, "bench A, W->E (walkthrough)")
	walk(zone, 8.9, 116.2, 8.9, 110.2, "bench B, N->S (walkthrough)")
	walk(zone, 8.4, 45.0, 8.4, 39.0, "fence 01a, N->S (must stop)")
	walk(zone, -3.0, 63.1, 3.0, 63.1, "fence 01b, W->E (must stop)")

	// Stand profile along the bench A walk line vs a parallel line 4u away
	// (no bench): any lift on the bench line that the parallel line doesn't
	// share is bench geometry leaking into stand.
	fmt.eprintfln("     bench A profile (x, stand@z=85, stand@z=89 parallel):")
	for x := f32(-1.5); x <= 7.0; x += 0.5 {
		h_bench, _ := sys.terrain_height_at(hf, x, 85.0)
		h_side, _ := sys.terrain_height_at(hf, x, 89.0)
		fmt.eprintfln("       %5.1f  %6.2f  %6.2f  %s", x, h_bench, h_side,
			h_bench - h_side > 0.25 ? "<-- LIFT" : "")
	}

	// Stair check across all 4 directions: longest monotonic ascending
	// stand runs (the stone plaza stairs). Ramps must survive the prop
	// slope-limit as gradual climbs, not cliffs.
	best_len, best_rise := 0, f32(0)
	best_x, best_z, best_dir := f32(0), f32(0), 0
	{
		dc4 := [4]int{1, -1, 0, 0}
		dr4 := [4]int{0, 0, 1, -1}
		for dir in 0 ..< 4 {
			dc, dr := dc4[dir], dr4[dir]
			run_len, run_rise := 1, f32(0)
			for r in 0 ..< hf.rows {
				for c in 0 ..< hf.cols {
					pr, pc := r - dr, c - dc
					if pr < 0 || pr >= hf.rows || pc < 0 || pc >= hf.cols {
						run_len, run_rise = 1, 0
						continue
					}
					i, ip := r * hf.cols + c, pr * hf.cols + pc
					if !hf.walk[i] || !hf.walk[ip] {
						run_len, run_rise = 1, 0
						continue
					}
					d := hf.stand[i] - hf.stand[ip]
					if d > 0.02 && d <= 0.62 {
						run_len += 1
						run_rise += d
						if run_len > best_len {
							best_len, best_rise = run_len, run_rise
							best_x = hf.origin_x + (f32(pc) + 0.5) * hf.cell
							best_z = hf.origin_z + (f32(pr) + 0.5) * hf.cell
							best_dir = dir
						}
					} else {
						run_len, run_rise = 1, 0
					}
				}
			}
		}
	}
	if best_len > 2 {
		fmt.eprintfln("     longest ascending run: %d cells, rise %.2f, from (%.1f, %.1f) dir=%d:",
			best_len, best_rise, best_x, best_z, best_dir)
		sx, sz := best_x, best_z
		dc4 := [4]f32{1, -1, 0, 0}
		dr4 := [4]f32{0, 0, 1, -1}
		dc, dr := dc4[best_dir], dr4[best_dir]
		for k := 0; k <= best_len; k += 1 {
			h, _ := sys.terrain_height_at(hf, sx, sz)
			fmt.eprintfln("       +%d: %.2f", k, h)
			sx += dc * hf.cell
			sz += dr * hf.cell
		}
		walk(zone, best_x - dc, best_z - dr, best_x + dc * f32(best_len + 2), best_z + dr * f32(best_len + 2),
			"stair run walk (should climb)")
	}
	// Cliff scan: adjacent WALKABLE cells with stand jumping > 1.0 — a cut
	// ramp shows up as base→cliff→plaza. Print the strongest few.
	{
		cliffs: [dynamic]Cliff_Ref
		for r in 1 ..< hf.rows - 1 {
			for c in 1 ..< hf.cols - 1 {
				i := r * hf.cols + c
				ix := i - 1
				iz := i - hf.cols
				if hf.walk[i] && hf.walk[ix] {
					d := abs(hf.stand[i] - hf.stand[ix])
					if d > 1.0 {
						append(&cliffs, Cliff_Ref{d, hf.origin_x + (f32(c) + 0.5) * hf.cell, hf.origin_z + (f32(r) + 0.5) * hf.cell})
					}
				}
				if hf.walk[i] && hf.walk[iz] {
					d := abs(hf.stand[i] - hf.stand[iz])
					if d > 1.0 {
						append(&cliffs, Cliff_Ref{d, hf.origin_x + (f32(c) + 0.5) * hf.cell, hf.origin_z + (f32(r) + 0.5) * hf.cell})
					}
				}
			}
		}
		fmt.eprintfln("     walkable-cell stand cliffs > 1.0: %d", len(cliffs))
		for cl, n in cliffs {
			if n >= 8 do break
			fmt.eprintfln("       jump=%5.2f at (%7.1f,%7.1f)", cl.jump, cl.x, cl.z)
		}
	}
	// Stair-cluster profiles: real tread stacks found in the bake at these
	// spots. The stand field must show a ramp (gradual rise), not
	// flat-then-cliff (a cut stair).
	stair_spots := [3]Point{
		{"stair (23,47)", 23.0, 47.1, 0, 0},
		{"stair (-38,51)", -38.3, 51.2, 0, 0},
		{"stair (69,-41)", 69.0, -41.4, 0, 0},
	}
	for sp in stair_spots {
		fmt.eprintfln("     %s profile along +x:", sp.name)
		for k := -4; k <= 6; k += 1 {
			x := sp.x + f32(k) * 0.7
			h, ok := sys.terrain_height_at(hf, x, sp.z)
			fmt.eprintfln("       x=%7.1f: %s", x, ok ? fmt.aprintf("%6.2f", h) : "  hole")
		}
	}
	// Whole-zone leftover-lift scan: walkable cells standing > 0.45 above
	// their 5x5 min, bucketed into 8u tiles. These are every remaining
	// spot in the zone that can still elevate the actor.
	{
		fmt.eprintfln("     leftover lift tiles (>0.45 above 5x5 min):")
		count := 0
		TILE :: 8
		for tr in 0 ..< (hf.rows + TILE - 1) / TILE {
			for tc := 0; tc < (hf.cols + TILE - 1) / TILE; tc += 1 {
				best, bx, bz := f32(0), f32(0), f32(0)
				for r in tr * TILE ..< min((tr + 1) * TILE, hf.rows) {
					for c in tc * TILE ..< min((tc + 1) * TILE, hf.cols) {
						i := r * hf.cols + c
						if !hf.walk[i] do continue
						mn := f32(1e30)
						for dr := -2; dr <= 2; dr += 1 {
							for dc := -2; dc <= 2; dc += 1 {
								nr, nc := r + dr, c + dc
								if nr < 0 || nr >= hf.rows || nc < 0 || nc >= hf.cols do continue
								ni := nr * hf.cols + nc
								if hf.walk[ni] && hf.stand[ni] < mn do mn = hf.stand[ni]
							}
						}
						if hf.stand[i] - mn > best {
							best = hf.stand[i] - mn
							bx = hf.origin_x + (f32(c) + 0.5) * hf.cell
							bz = hf.origin_z + (f32(r) + 0.5) * hf.cell
						}
					}
				}
				if best > 0.45 {
					fmt.eprintfln("       lift %5.2f at (%7.1f,%7.1f)", best, bx, bz)
					count += 1
					if count >= 24 do break
				}
			}
			if count >= 24 do break
		}
		if count == 0 do fmt.eprintfln("       none")
	}
	// Grid dump around a spot: stand | heights (X = not walkable).
	{
		cx, cz := f32(-20.3), f32(-69.1)
		fmt.eprintfln("     grid around (%.1f, %.1f): stand (X = not walkable):", cx, cz)
		row: [dynamic]u8
		defer delete(row)
		for z := cz + 7.0; z >= cz - 7.0; z -= 1.0 {
			clear(&row)
			for x := cx - 7.0; x <= cx + 7.0; x += 1.0 {
				h, ok := sys.terrain_height_at(hf, x, z)
				cell := "  X  "
				if ok && sys.terrain_standable(hf, x, z) {
					cell = fmt.aprintf("%5.1f", h)
				}
				for b in cell do append(&row, u8(b))
				append(&row, u8(' '))
			}
			fmt.eprintfln("       z=%6.1f %s", z, string(row[:]))
		}
		fmt.eprintfln("     same area, full HEIGHTS (stand before verdicts):")
		for z := cz + 7.0; z >= cz - 7.0; z -= 1.0 {
			clear(&row)
			for x := cx - 7.0; x <= cx + 7.0; x += 1.0 {
				h, ok := sys.terrain_full_height_at(hf, x, z)
				cell := "  X  "
				if ok {
					cell = fmt.aprintf("%5.1f", h)
				}
				for b in cell do append(&row, u8(b))
				append(&row, u8(' '))
			}
			fmt.eprintfln("       z=%6.1f %s", z, string(row[:]))
		}
	}
	// Phantom-stand scan: walkable cells where the actor's grounding (mesh
	// surface agreeing with stand) FAILS even though geometry exists — the
	// actor falls back to the field and floats above the nearest visual
	// surface. Severity = distance from stand down to the surface below.
	{
		phantoms := 0
		worst := f32(0)
		wx, wz := f32(0), f32(0)
		hist := [8]int{}
		nan_bits := u32(0x7FC0_0000)
		nan := transmute(f32) nan_bits
		for r in 0 ..< hf.rows {
			for c in 0 ..< hf.cols {
				i := r * hf.cols + c
				if !hf.walk[i] do continue
				x := hf.origin_x + (f32(c) + 0.5) * hf.cell
				z := hf.origin_z + (f32(r) + 0.5) * hf.cell
				_, m_any := sys.terrain_mesh_ground_at(hf, x, z, 1e30, -1e30, false, -1e30)
				if !m_any do continue // no geometry here at all
				_, m_f := sys.terrain_mesh_ground_at(hf, x, z, 1e30, 1e30, true, hf.stand[i])
				if m_f do continue // grounds exactly on the mesh: fine
				mh, m_b := sys.terrain_mesh_ground_at(hf, x, z, hf.stand[i] + 0.5, -1e30, true, hf.stand[i])
				d := f32(9)
				if m_b do d = hf.stand[i] - mh
				phantoms += 1
				b := 0
				for d > 0.5 && b < 7 {
					b += 1
				}
				hist[b] += 1
				if d > worst {
					worst = d
					wx, wz = x, z
				}
			}
		}
		fmt.eprintfln("     phantom stand cells (no agreeing mesh surface): %d  worst float %.2f at (%.1f,%.1f)", phantoms, worst, wx, wz)
		fmt.eprintfln("     float hist 0.5-1/1-2/2-3/3-4/4-5/5-6/6-7/7+: %v", hist)
	}
	sys.zone_destroy(zone)
}
