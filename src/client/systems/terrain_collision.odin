package systems

import "core:math"
import "core:slice"
import "core:strings"
import rl "vendor:raylib"

// Terrain collision + elevation for GLB terrain zones (the Pandora maps).
//
// load_zone_map hands us the zone's models with every mesh already baked
// into world space (raylib's glTF loader flattens node transforms), so we
// rasterize their triangles once at zone load into a 2D heightfield:
//
//   heights[r*cols+c] — highest walk-surface at the cell center (max, so
//                       mountain chips layered over base terrain win)
//   valid[r*cols+c]   — at least one ground triangle covered the cell
//   walk[r*cols+c]    — valid, eroded one cell away from holes, clear of
//                       wall-segment clearance, JSON obstacles and margin
//                       (PATHFINDING ONLY — never gates movement)
//   stand[r*cols+c]   — walkable ground elevation (bands kept, props cut
//                       back to terrain), the default sampling field
//
// PROVENANCE FIRST. Two authored GLBs ride alongside the visual bake:
//
//   ground GLB  (map_<area>_ground.glb — pandora_export "ground") holds
//               exactly the area's terrain chips + default fill, no props.
//               When present its triangles are the ONLY terrain-class
//               surface: they always ground the actor and always raise the
//               field. Every visual-bake triangle is object-class —
//               canopies, wall trim, stall tops can never masquerade as
//               terrain (big flat-ish bake triangles near slopes used to).
//   hit GLB     (map_<area[_variant]>_hit.glb — pandora_export "hit" from
//               the original engine's own _hit.dxg, named from the JSON's
//               source.collision so variant areas get their own proxies)
//               supplies the blocking walls as Y-bounded segments.
//
// COLLISION PHILOSOPHY: movement-blocking collision comes ONLY from
// authored data, never guessed from the visual bake (grass tufts and fence
// panels share the same steep-triangle signature, so shape-based
// heuristics cannot tell them apart):
//   - the original engine's hit proxies: walls, buildings, arches —
//     exactly what the original game collided
//   - the JSON `colliders` list hand-authored per zone
//   - the manifest's world-object instances (see instance_collision):
//     fences and statues block; every other placed object gets a no-stand
//     disc so its baked top can never elevate the actor (walk through at
//     ground height)
// Stairs, ramps and terrain remain the only things that lift the actor.
//
// Without a ground GLB (older exports) the legacy shape classifier runs on
// the visual bake:
//
//   ground (≥4u edge, ≤70°)      — the terrain surface itself; rasterized in
//                                  ascending height so stacked chips layer
//   props (0.9–4u edge, ≤70°)    — benches, stairs, statue bodies, curbs-in-
//                                  waiting; rasterized only when the triangle
//                                  sits within TRI_MAX_CLEARANCE of the
//                                  ground so far — canopies, awnings, arch
//                                  crowns and wall caps never enter the field
//   decor (<0.9u edge)           — grass, bushes, potted plants, lamps,
//                                  trunk trim: ignored entirely, no collision
//   steep (>70°)                 — wall faces, trunks, canopy cones, ground
//                                  chip seams: ignored. Never rasterized,
//                                  never blocked — collision for walls is
//                                  authored, never guessed from the bake
// Object-class surfaces (both paths) may only lift the actor where the
// height-band verdicts kept them (real stairs, plazas — see the band pass
// in terrain_heightfield_build).
//
// MOVEMENT (terrain_move) is a kinematic character controller:
//   - grounded actors track the exact mesh surface — steps up to
//     MAX_STEP_UP, downhill snaps within tolerance; steeper rises block
//     like walls (the stand field carries 60-70° faces the exact sampler
//     refuses to snap up)
//   - drops beyond the tolerance detach into a gravity fall (GRAVITY,
//     MAX_FALL_SPEED) — walking off a ledge accelerates down instead of
//     teleporting to the bottom, and nothing can be climbed by repeated
//     airborne snaps
//   - walls are Y-bounded segments in a spatial hash: they never shove an
//     actor passing above or below them (bridges over street walls,
//     balconies) and block within their true vertical extent
//   - sheer >70° columns with no rasterized floor resolve by relocating
//     to the nearest ground at/below the fall's start height
//
// Everything else queries the fields:
//   terrain_height_at — bilinear stand elevation for anything on the map
//   terrain_move      — the controller above (WASD + click-to-move)
//   terrain_ray_hit   — exact ray trace over the bucketed mesh triangles
//                       and wall quads (clicks, reticle, aim)
//
// Zones without a GLB (the older procedural maps) never build a heightfield;
// every proc here degrades to the legacy flat behavior (y=0, A* grid from
// ground.size), so call sites don't need to branch.

// Triangles steeper than ~70° (normalized |ny| below this) never raise the
// heightfield; near-vertical planes would also extrapolate garbage heights
// across the half-cell raster reach.
TERRAIN_TRI_NY_MIN :: f32(0.34)

// Hit-proxy triangles flatter than this (normalized |ny|) are floors and
// never become wall segments.
WALL_TRI_NY_MAX :: f32(0.55)

// Actor collision radius for the geometric wall pass.
PLAYER_COLLIDE_RADIUS :: f32(0.45)

// Maximum ground rise terrain_move snaps the actor up in one move while
// grounded. The bake composites raisable surfaces into the stand field
// (fence rails, wall trim tiers, statue plinths — each within TRI_MAX_CLEARANCE of the last, so they
// stack all the way up towers); mounting them on touch is what lifted actors
// off the ground when they collided with walls. Dropping follows gravity;
// rises steeper than a step are walked through at the current height.
MAX_STEP_UP :: f32(0.5)

// Vertical model. Grounded actors follow the surface (steps up to
// MAX_STEP_UP, slopes, snap-downs within tolerance); anything beyond that
// detaches and falls with gravity — walking off a ledge accelerates instead
// of teleporting to the bottom, and step-up only works from ground contact,
// so band-kept wall trim can be climbed neither instantly nor by repeated
// snaps while falling past it.
GRAVITY        :: f32(22.0) // u/s²
MAX_FALL_SPEED :: f32(35.0) // u/s terminal velocity
ACTOR_HEIGHT   :: f32(1.7)  // standing capsule height for wall y-overlap

// A grounded actor whose surface drops more than this (plus distance
// traveled × slope allowance) leaves the ground and falls; smaller drops
// snap down in place so downhill walking stays planted.
SNAP_DOWN_BASE :: f32(0.65)

// Vertical movement state carried across frames by the local player.
Vertical_State :: struct {
	vy:           f32, // downward velocity (negative while falling)
	grounded:     bool,
	fall_start_y: f32, // height where the current fall detached
}

Wall_Seg :: struct {
	x1, z1: f32,
	x2, z2: f32,
	// Vertical span the segment blocks over. Original hit-proxy triangles
	// carry their true Y extent; authored footprints (JSON colliders,
	// fences) get a generous band around the local terrain height. Walls
	// never block an actor whose vertical span misses theirs — bridges over
	// ground-level walls, balconies above street furniture.
	y_min: f32,
	y_max: f32,
}

// Triangle XZ edge-length bands (see the classification table above).
// Ground classification needs real two-dimensional extent: a garden wall's
// top surface or a masonry course is a long thin strip (shortest XZ edge
// below GROUND_TRI_MIN_WIDTH) and demotes to the strip bucket, where the
// height-band verdict can cut it — long as it is, a wall top is an object
// ledge, not terrain. Hillside slope strips run ~1.2u wide, so the
// threshold must stay below that.
GROUND_TRI_MIN_EXTENT :: f32(4.0)
GROUND_TRI_MIN_WIDTH :: f32(1.0)
PROP_TRI_MIN_EXTENT :: f32(0.9)

// A prop triangle bottoms out more than this above the ground
// built so far → floating geometry (canopy, awning, arch crown, wall cap):
// no collision.
TRI_MAX_CLEARANCE :: f32(1.2)

// Prop triangles get a much tighter clearance than ground chips. Props
// tier-chain — stall counter → beams → canopy, low branch → higher
// branches — whenever each layer sits within reach of the last, which let
// the actor climb trees, awnings and market roofs one step at a time.
PROP_MAX_CLEARANCE :: f32(0.5)

// Demoted thin strips (terrace paving, walkways) sit on a base course
// above the terrain: 0.8-1.5 up. Wide enough to admit raised pavement,
// still below branch and canopy bottoms so trees don't return.
STRIP_MAX_CLEARANCE :: f32(1.5)

// Per-cell rise an actor can legitimately traverse on a kept prop surface
// (stairs, curbs, ramps). Prop-raised cells whose surface jumps more than
// this above every kept neighbor are object tops — stall counters, fence
// rails, branch forks, any uninstanced prop — and are cut back to the
// terrain beneath them. Genuine stairs stay well under this at 1u cells.
MAX_PROP_STEP_RISE :: f32(0.6)

// Heightfield resolution cap (~32 MB of f32 heights + flags). Bigger maps
// grow their cell size instead.
HF_MAX_CELLS :: 8_000_000

// Coarse A* grid cap (cells × ~13 B of pathfinder scratch ≈ ≤16 MB).
PF_MAX_CELLS :: 1_200_000

// Wall-segment spatial hash cell size (world units). Big enough that a
// bucket holds a manageable slice of a wall-heavy map, small enough that
// the per-move bucket test stays cheap.
SEG_GRID_CELL :: f32(4.0)

Terrain_Heightfield :: struct {
	origin_x: f32, // world X of the grid's min corner
	origin_z: f32, // world Z of the grid's min corner
	cell:     f32, // cell edge length (world units)
	cols:     int,
	rows:     int,
	min_y:    f32,
	max_y:    f32,
	heights:  []f32, // full surface incl. wall/structure tops
	stand:    []f32, // walkable ground elevation — spawn/A*/fallback snap
	valid:    []bool,
	walk:     []bool, // PATHFINDING ONLY: holes + wall clearance + margin.
	//                     Never gates movement (terrain_standable does).
	segs:     []Wall_Seg, // 2D wall lines from the hit proxies (movement)
	// Coarse spatial hash over segs (CSR): seg indices bucketed per
	// SEG_GRID_CELL cell, each segment registered against every cell its
	// XZ footprint (inflated by the actor radius) overlaps. The movement
	// wall pass queries one bucket instead of scanning every segment.
	seg_grid:       []i32, // CSR values: indices into segs
	seg_ptr:        []i32, // len = seg_grid_cols*seg_grid_rows + 1 (CSR)
	seg_grid_cols:  int,
	seg_grid_rows:  int,
	// Why each cell is blocked (HF_BLOCK_* codes); 0 = walkable. Build
	// diagnostics for the collision view / tooling.
	reasons: []u8,
	// Exact visual ground: every terrain-mesh triangle bucketed per cell
	// (CSR layout — mesh_ptr[cell] .. mesh_ptr[cell+1] index mesh_tris,
	// whose entries are triangle ids into mesh_coords, 9 floats each).
	// terrain_mesh_ground_at ray-samples these so actors stand on the
	// rendered geometry instead of the 1u-cell approximation — no floating
	// on slopes, pavement edges or wall bases. The first mesh_ground_count
	// ids are terrain-class (slopes/stairs chips — always grounding); the
	// rest are object-class (courses, branches, props — only grounding
	// where the band verdict kept a surface).
	mesh_coords:      []f32,
	mesh_ptr:         []i32,
	mesh_tris:        []i32,
	mesh_ground_count: int,
}

HF_BLOCK_NONE     :: u8(0)
HF_BLOCK_HOLE     :: u8(1) // never covered by ground geometry
HF_BLOCK_SLOPE    :: u8(2) // slope over the walk threshold
HF_BLOCK_STEP     :: u8(3) // reserved (step rule removed — walls-only mode)
HF_BLOCK_ERODE    :: u8(4) // adjacent to a blocked cell
HF_BLOCK_STEEP    :: u8(5) // steep structure face footprint
HF_BLOCK_OBSTACLE :: u8(6) // JSON structure / rock / manual collider
HF_BLOCK_MARGIN   :: u8(7) // map border
HF_BLOCK_HIT      :: u8(8) // original _hit.dxg collision proxy footprint
HF_BLOCK_WALL     :: u8(9) // wall-segment clearance (A* only; movement is geometric)
HF_NOSTAND        :: u8(10) // object footprint: walkable, but stand is re-derived
//                        from the ground (benches/boxes/barrels never lift)

// ── world-object instances ──────────────────────────────────────────────────
//
// The manifest's instance list is the authored object layer on top of the
// terrain bake. `kind` is the manifest's own asset class (authored
// provenance; currently "object" for everything placed). Collision policy
// per object name:
//
//   fences, statues        block: oriented footprint becomes wall segments —
//                           the actor stops at them, never mounts them
//   furniture & containers no-stand disc: walk through freely, but the
//   (bench, chair, table,  object's baked top is dissolved out of the stand
//    box, barrel, cask,    field so it can never elevate the actor
//    jar, crate, well...)
//   everything else        nothing: grass, trees, plants, rocks, flags and
//                           all decor interact with the actor in no way
//                           (their steep/decor triangles never raise the
//                           field anyway)
instance_collision :: proc(name, kind: string, inst: ^Map_Instance) {
	if len(name) == 0 do return
	_ = kind // reserved for richer manifest classes (trees/plants as decor)
	s := inst.scale
	if strings.contains(name, "fence") {
		inst.hl, inst.hw = 1.6 * s, 0.35 * s
		return
	}
	if strings.contains(name, "statue") {
		inst.hl, inst.hw = 1.2 * s, 1.2 * s
		inst.nostand_r = 2.2 * s
		return
	}
	r := f32(0)
	if strings.contains(name, "bench") {
		r = 3.0
	} else if strings.contains(name, "table") {
		r = 1.8
	} else if strings.contains(name, "chair") {
		r = 1.2
	} else if strings.contains(name, "crate") {
		r = 1.5
	} else if strings.contains(name, "barel") || strings.contains(name, "barrel") {
		r = 1.3
	} else if strings.contains(name, "cask") {
		r = 1.4
	} else if strings.contains(name, "jar") {
		r = 1.2
	} else if strings.contains(name, "tub") {
		r = 1.3
	} else if strings.contains(name, "box") {
		r = 1.7
	} else if strings.contains(name, "well") {
		r = 1.8
	} else if strings.contains(name, "tent") {
		r = 3.2
	} else if strings.contains(name, "tepee") {
		r = 2.6
	} else if strings.contains(name, "stable") {
		r = 3.2
	} else if strings.contains(name, "cart") {
		r = 2.6
	} else if strings.contains(name, "sign") {
		r = 0.9
	} else if strings.contains(name, "cross") {
		r = 1.2
	} else if strings.contains(name, "relic") {
		r = 1.6
	} else if strings.contains(name, "wood") {
		r = 1.8
	} else if strings.contains(name, "wepon") || strings.contains(name, "weapon") {
		r = 1.5
	} else if strings.contains(name, "plant") {
		r = 1.1
	}
	// Unclassified objects (wobj, street pavement slabs, town furniture,
	// future names) get NO disc: the band verdicts already judge their
	// surfaces — supported slab fields stay walkable (raised alleys,
	// bridges), ribbons (wall tops, rails) are cut. A blanket disc here
	// sank actors under walkable raised pavement.
	inst.nostand_r = r * s
}

// ── build ────────────────────────────────────────────────────────────────────

Tri_Sort_Ref :: struct {
	min_y: f32, // triangle's lowest vertex — sort key + clearance test
	base:  int, // offset into the flat 9-float coords array
}

// Prop-raised cell index keyed by surface height — the ascending sweep
// order for the slope-limit pass (lower cells decided first).
Height_Ref :: struct {
	h: f32,
	i: int,
}

height_ref_less :: proc(a, b: Height_Ref) -> bool {
	return a.h < b.h
}

tri_ref_less :: proc(a, b: Tri_Sort_Ref) -> bool {
	return a.min_y < b.min_y
}

// Build the heightfield + walkability for a terrain zone. Called from
// load_zone_map after the terrain model is acquired and the JSON obstacles
// are parsed; leaves the zone untouched when there is no GLB.
terrain_heightfield_build :: proc(zone: ^Zone_Definition) {
	if zone == nil || zone.terrain == nil do return
	model := zone.terrain.model
	if model.meshCount == 0 do return

	// 1. World bounds across every mesh.
	min_x, max_x := f32(1e30), f32(-1e30)
	min_z, max_z := f32(1e30), f32(-1e30)
	min_y, max_y := f32(1e30), f32(-1e30)
	for mi in 0 ..< int(model.meshCount) {
		box := rl.GetMeshBoundingBox(model.meshes[mi])
		min_x = min(min_x, box.min.x); max_x = max(max_x, box.max.x)
		min_z = min(min_z, box.min.z); max_z = max(max_z, box.max.z)
		min_y = min(min_y, box.min.y); max_y = max(max_y, box.max.y)
	}
	extent_x := max_x - min_x
	extent_z := max_z - min_z
	// NaN-poisoned bounds (a bad accessor somewhere in a big export) would
	// run the build off the rails — bail out to "no heightfield" instead.
	if !_f32_finite(extent_x) || !_f32_finite(extent_z) || extent_x <= 0 || extent_z <= 0 {
		return
	}

	// 2. Resolution: 1-unit cells, coarsening only if the map is huge.
	cell := f32(1)
	for (extent_x / cell) * (extent_z / cell) > HF_MAX_CELLS {
		cell += 1
	}
	cols := int(math.ceil_f32(extent_x / cell)) + 1
	rows := int(math.ceil_f32(extent_z / cell)) + 1
	total := cols * rows

	hf := new(Terrain_Heightfield)
	hf.origin_x = min_x
	hf.origin_z = min_z
	hf.cell = cell
	hf.cols = cols
	hf.rows = rows
	hf.min_y = min_y
	hf.max_y = max_y
	hf.heights = make([]f32, total)
	hf.stand = make([]f32, total)
	hf.valid = make([]bool, total)
	hf.walk = make([]bool, total)
	hf.reasons = make([]u8, total)
	zone.heightfield = hf

	// 3. Classify every triangle into ground / prop / strip / ignore (see
	//    the module comment). With a ground GLB (the area's terrain chips +
	//    fill, no props), provenance replaces shape heuristics: ground-model
	//    triangles are terrain-class — the walk surface, no size tests — and
	//    every visual-bake triangle is object-class, so canopies and trim
	//    can never masquerade as terrain the way big flat-ish bake triangles
	//    on slopes did. Without a ground GLB the legacy shape classifier
	//    runs on the visual bake (older exports). Coords go into flat
	//    9-float runs; the sort refs index them.
	ground_coords: [dynamic]f32
	prop_coords:   [dynamic]f32
	strip_coords:  [dynamic]f32
	ground_refs:   [dynamic]Tri_Sort_Ref
	prop_refs:     [dynamic]Tri_Sort_Ref
	strip_refs:    [dynamic]Tri_Sort_Ref
	defer delete(ground_coords)
	defer delete(prop_coords)
	defer delete(strip_coords)
	defer delete(ground_refs)
	defer delete(prop_refs)
	defer delete(strip_refs)

	if zone.ground_model != nil {
		_hf_classify_model(
			zone.ground_model.model, .GROUND_MODEL,
			&ground_coords, &prop_coords, &strip_coords,
			&ground_refs, &prop_refs, &strip_refs,
		)
		_hf_classify_model(
			model, .OBJECT_BAKE,
			&ground_coords, &prop_coords, &strip_coords,
			&ground_refs, &prop_refs, &strip_refs,
		)
	} else {
		_hf_classify_model(
			model, .LEGACY_SHAPE,
			&ground_coords, &prop_coords, &strip_coords,
			&ground_refs, &prop_refs, &strip_refs,
		)
	}

 	// 4. Ground pass: terrain chips in ascending height (stacked layers
 	//    composite via max). The clearance test against the field built so
 	//    far is what rejects big floating slabs — arch crowns, long wall
 	//    caps, roof plates — that would otherwise roof-in whole districts.
	slice.sort_by(ground_refs[:], tri_ref_less)
	_hf_raster_pass(hf, ground_coords[:], ground_refs[:], TRI_MAX_CLEARANCE)

	// Snapshot the ground-only surface. `stand` is reconciled against it
	// below; any prop contribution that fails the step/slope rules is cut
	// back to the exact terrain beneath the object.
	ground_h := make([]f32, total)
	ground_valid := make([]bool, total)
	defer delete(ground_h)
	defer delete(ground_valid)
	copy(ground_h, hf.heights)
	copy(ground_valid, hf.valid)

	// The ground snapshot is the DEFAULT stand everywhere — the band
	// verdicts below overwrite only prop-raised cells. Plain ground cells
	// previously kept stand == 0 from the allocator, so every stand-field
	// consumer (movement y fallback, stand_ref, telepads, entity pins,
	// cursor rays) sampled y=0 wherever the exact-mesh probe missed.
	for i in 0 ..< total {
		if ground_valid[i] do hf.stand[i] = ground_h[i]
	}

	// 5. Prop pass: benches / stairs / statue bodies — canopies and co.
	//    never land. Prop triangles only ever raise heights; nothing here
	//    blocks. Tight clearance so layered props (counters, beams, roof
	//    plates, branch tiers) don't chain into climbable stacks.
	slice.sort_by(prop_refs[:], tri_ref_less)
	_hf_raster_pass(hf, prop_coords[:], prop_refs[:], PROP_MAX_CLEARANCE)

	// 5b. Strip pass: long thin slabs the width demotion pulled out of the
	//     ground bucket — terrace paving fields, walkway strips. They sit
	//     up to ~1.5 above the terrain beneath (raised pavement on a base
	//     course), so they get a wider clearance than props; the band
	//     verdict below decides which strips are surface (paved plaza)
	//     and which are ledge (wall top).
	slice.sort_by(strip_refs[:], tri_ref_less)
	_hf_raster_pass(hf, strip_coords[:], strip_refs[:], STRIP_MAX_CLEARANCE)

	// 5c. Mesh ground buckets: concatenate all rasterized triangle coords
	//     and bucket them per cell (CSR) so movement can ray-sample the
	//     exact visual ground. Ids index the merged array; the ground and
	//     prop tris come first, then the strips. mesh_ground_count = the
	//     terrain-class prefix (ground_coords tris): those always ground
	//     the actor; object-class ones only on band-kept surfaces.
	{
		gp := len(ground_refs) + len(prop_refs)
		hf.mesh_ground_count = len(ground_refs)
		n_tris := gp + len(strip_refs)
		hf.mesh_coords = make([]f32, n_tris * 9)
		copy(hf.mesh_coords, ground_coords[:])
		copy(hf.mesh_coords[len(ground_coords):], prop_coords[:])
		copy(hf.mesh_coords[len(ground_coords) + len(prop_coords):], strip_coords[:])

		hf.mesh_ptr = make([]i32, total + 1)
		for pass in 0 ..< 3 {
			coords := ground_coords
			if pass == 1 do coords = prop_coords
			if pass == 2 do coords = strip_coords
			for t := 0; t < len(coords) / 9; t += 1 {
				tx0 := min(min(coords[t * 9], coords[t * 9 + 3]), coords[t * 9 + 6])
				tx1 := max(max(coords[t * 9], coords[t * 9 + 3]), coords[t * 9 + 6])
				tz0 := min(min(coords[t * 9 + 2], coords[t * 9 + 5]), coords[t * 9 + 8])
				tz1 := max(max(coords[t * 9 + 2], coords[t * 9 + 5]), coords[t * 9 + 8])
				cmin := max(0, int(math.floor_f32((tx0 - hf.origin_x) / cell)))
				cmax := min(cols - 1, int(math.floor_f32((tx1 - hf.origin_x) / cell)))
				rmin := max(0, int(math.floor_f32((tz0 - hf.origin_z) / cell)))
				rmax := min(rows - 1, int(math.floor_f32((tz1 - hf.origin_z) / cell)))
				for r := rmin; r <= rmax; r += 1 {
					for c := cmin; c <= cmax; c += 1 {
						hf.mesh_ptr[r * cols + c + 1] += 1
					}
				}
			}
		}
		for i in 0 ..< total do hf.mesh_ptr[i + 1] += hf.mesh_ptr[i]
		hf.mesh_tris = make([]i32, hf.mesh_ptr[total])
		cursor := make([]i32, total)
		defer delete(cursor)
		copy(cursor, hf.mesh_ptr[:total])
		base := 0
		for pass in 0 ..< 3 {
			coords := ground_coords
			if pass == 1 do coords = prop_coords
			if pass == 2 do coords = strip_coords
			for t := 0; t < len(coords) / 9; t += 1 {
				tx0 := min(min(coords[t * 9], coords[t * 9 + 3]), coords[t * 9 + 6])
				tx1 := max(max(coords[t * 9], coords[t * 9 + 3]), coords[t * 9 + 6])
				tz0 := min(min(coords[t * 9 + 2], coords[t * 9 + 5]), coords[t * 9 + 8])
				tz1 := max(max(coords[t * 9 + 2], coords[t * 9 + 5]), coords[t * 9 + 8])
				cmin := max(0, int(math.floor_f32((tx0 - hf.origin_x) / cell)))
				cmax := min(cols - 1, int(math.floor_f32((tx1 - hf.origin_x) / cell)))
				rmin := max(0, int(math.floor_f32((tz0 - hf.origin_z) / cell)))
				rmax := min(rows - 1, int(math.floor_f32((tz1 - hf.origin_z) / cell)))
				gid := base + t
				for r := rmin; r <= rmax; r += 1 {
					for c := cmin; c <= cmax; c += 1 {
						k := r * cols + c
						hf.mesh_tris[cursor[k]] = i32(gid)
						cursor[k] += 1
					}
				}
			}
			base += len(coords) / 9
		}
	}

	// 6. Plug pinholes: cells the raster missed between sparse edges but
	//    that are surrounded by covered neighbors. Two sweeps are enough
	//    for pixel-scale gaps; real holes (cave mouths) survive.
	dxs := [4]int{1, -1, 0, 0}
	dzs := [4]int{0, 0, 1, -1}
	for _ in 0 ..< 2 {
		filled := false
		for r in 0 ..< rows {
			for c in 0 ..< cols {
				i := r * cols + c
				if hf.valid[i] do continue
				sum := f32(0)
				n := 0
				for d in 0 ..< 4 {
					nc, nr := c + dxs[d], r + dzs[d]
					if nc < 0 || nc >= cols || nr < 0 || nr >= rows do continue
					ni := nr * cols + nc
					if !hf.valid[ni] do continue
					sum += hf.heights[ni]
					n += 1
				}
				if n >= 3 {
					hf.heights[i] = sum / f32(n)
					hf.valid[i] = true
					filled = true
				}
			}
		}
		if !filled do break
	}

	// 6b. Height-band verdicts on the prop contribution. Prop-raised cells
	//     group into bands: connected (8-neighborhood) cells whose heights
	//     step at most MAX_PROP_STEP_RISE between neighbors — one band per
	//     staircase, per plaza surface, per wall ledge + its course ladder.
	//     A band is walkable surface when any of these hold:
	//       landing  — a band cell borders non-prop terrain within 0.7 of
	//                  its own height (the surface meets the ground)
	//       merge    — the band is adjacent (within 0.7) to an already-
	//                  kept band (stairs onto a porch, porch onto its pad)
	//       interior — some band cell has all 4 neighbors in-band AND the
	//                  band covers at least BAND_MIN_AREA cells: a paved
	//                  plaza or terrace is a real surface with an inside;
	//                  a counter top is a stamp-sized island with none
	//     Every other band — wall tops, rails, branch forks, counter tops,
	//     ornaments — is cut back to the terrain snapshot beneath it.
	BAND_MIN_AREA :: 40
	nostand_cells: [dynamic]int
	defer delete(nostand_cells)
	{
		refs: [dynamic]Height_Ref
		defer delete(refs)
		for i in 0 ..< total {
			if !hf.valid[i] do continue
			if hf.heights[i] > ground_h[i] + 0.01 {
				append(&refs, Height_Ref{h = hf.heights[i], i = i})
			}
		}
		// Label bands over all prop-raised cells.
		band := make([]int, total)
		defer delete(band)
		stack: [dynamic]int
		defer delete(stack)
		next_band := 0
		for ref in refs {
			i := ref.i
			if band[i] != 0 do continue
			next_band += 1
			clear(&stack)
			append(&stack, i)
			band[i] = next_band
			for len(stack) > 0 {
				cur := stack[len(stack) - 1]
				pop(&stack)
				cu_r := cur / cols
				cu_c := cur % cols
				for dr := -1; dr <= 1; dr += 1 {
					for dc := -1; dc <= 1; dc += 1 {
						nc, nr := cu_c + dc, cu_r + dr
						if nc < 0 || nc >= cols || nr < 0 || nr >= rows do continue
						ni := nr * cols + nc
						if band[ni] != 0 do continue
						if !hf.valid[ni] do continue
						if hf.heights[ni] <= ground_h[ni] + 0.01 do continue
						if abs(hf.heights[ni] - hf.heights[cur]) > MAX_PROP_STEP_RISE do continue
						band[ni] = next_band
						append(&stack, ni)
					}
				}
			}
		}
		band_ok := make([dynamic]bool, next_band + 1)
		defer delete(band_ok)
		band_area := make([]int, next_band + 1)
		defer delete(band_area)
		band_interior := make([]bool, next_band + 1)
		defer delete(band_interior)
		band_max_h := make([]f32, next_band + 1)
		defer delete(band_max_h)
		band_max_ground := make([]f32, next_band + 1)
		defer delete(band_max_ground)
		for ref in refs {
			i := ref.i
			b := band[i]
			band_area[b] += 1
			if hf.heights[i] > band_max_h[b] do band_max_h[b] = hf.heights[i]
			if ground_h[i] > band_max_ground[b] do band_max_ground[b] = ground_h[i]
		}
		// Interior test: a band cell with all 4 neighbors in-band.
		for ref in refs {
			i := ref.i
			b := band[i]
			if band_interior[b] do continue
			cr := i / cols
			cc := i % cols
			interior := true
			for dr := -1; dr <= 1 && interior; dr += 1 {
				for dc := -1; dc <= 1; dc += 1 {
					if dr == 0 && dc == 0 do continue
					if dr != 0 && dc != 0 do continue // 4-neighborhood
					nc, nr := cc + dc, cr + dr
					if nc < 0 || nc >= cols || nr < 0 || nr >= rows {
						interior = false
						break
					}
					ni := nr * cols + nc
					if band[ni] != b {
						interior = false
						break
					}
				}
			}
			if interior do band_interior[b] = true
		}
		// TOP landing test: the climb must REACH something — a cell near the
		// band's top bordering non-prop terrain within 0.45 of its own
		// height — AND the band's top must sit within 2.5 of the highest
		// terrain beneath the band (supported: filled terrace, hillside
		// walkway). A landing anywhere along the chain (a tree trunk's
		// flare, a stall's base) or mere slope support would anchor
		// tree-branch ladders and stall canopies as walkable.
		for ref in refs {
			i := ref.i
			b := band[i]
			if band_ok[b] do continue
			if hf.heights[i] < band_max_h[b] - 0.7 do continue
			if band_max_h[b] - band_max_ground[b] > 2.5 do continue
			cr := i / cols
			cc := i % cols
			for dr := -1; dr <= 1 && !band_ok[b]; dr += 1 {
				for dc := -1; dc <= 1; dc += 1 {
					nc, nr := cc + dc, cr + dr
					if nc < 0 || nc >= cols || nr < 0 || nr >= rows do continue
					ni := nr * cols + nc
					if !hf.valid[ni] || band[ni] != 0 do continue
					if hf.heights[ni] > ground_h[ni] + 0.01 do continue
					if abs(hf.heights[i] - ground_h[ni]) <= 0.45 {
						band_ok[b] = true
						break
					}
				}
			}
		}
		// Base verdicts: top-landing, or a big band with an inside that is
		// SUPPORTED — its top sits at most 2.5 above the highest terrain
		// beneath it (a paved terrace on filled ground), which separates
		// plaza surfaces from floating canopies.
		for b in 1 ..= next_band {
			band_ok[b] = band_ok[b] ||
				(band_interior[b] && band_area[b] >= BAND_MIN_AREA &&
					band_max_h[b] - band_max_ground[b] <= 2.5)
		}
		// Band merge: a band adjacent (within 0.7) to a kept band at
		// matching height is part of the same structure.
		for _ in 0 ..< 4 {
			changed := false
			for ref in refs {
				i := ref.i
				b := band[i]
				if b == 0 || band_ok[b] do continue
				cr := i / cols
				cc := i % cols
				for dr := -1; dr <= 1 && !band_ok[b]; dr += 1 {
					for dc := -1; dc <= 1; dc += 1 {
						nc, nr := cc + dc, cr + dr
						if nc < 0 || nc >= cols || nr < 0 || nr >= rows do continue
						ni := nr * cols + nc
						nb := band[ni]
						if nb == 0 || nb == b || !band_ok[nb] do continue
						if abs(hf.heights[i] - hf.heights[ni]) <= 0.7 {
							band_ok[b] = true
							changed = true
							break
						}
					}
				}
			}
			if !changed do break
		}
		for ref in refs {
			i := ref.i
			b := band[i]
			// Per-cell support trim: even inside a kept band, a cell whose
			// surface sits more than 2.5 above the terrain directly beneath
			// it is overhead geometry (canopy, branch) — a slope-anchored
			// tree's canopy tracks the rising ground and would otherwise
			// pass every band-level support test. Walk through at grade.
			supported := ground_valid[i] && hf.heights[i] - ground_h[i] <= 2.5
			if b != 0 && band_ok[b] && supported {
				hf.stand[i] = hf.heights[i]
			} else if ground_valid[i] {
				hf.stand[i] = ground_h[i]
			} else {
				// no terrain snapshot beneath (prop over a hole/pinhole):
				// re-derive from neighbors in the dilution passes
				append(&nostand_cells, i)
			}
		}
	}

	// 7. Wall segments — authored collision only:
	//    a) the hit proxies: every steep triangle contributes ALL of its
	//       XZ-projecting edges as wall lines (vertical edges project to
	//       points and drop out on their own; the old longest-edge-only
	//       pick left gaps at tilted corners), each carrying the
	//       triangle's true Y extent. Floor-flavored proxies (high |ny|)
	//       are the walkable surface and never block.
	//    b) the zone's manual Collider boxes: their rectangle edges become
	//       segments so they block movement, not just pathfinding. Authored
	//       footprints carry no Y — they get a generous band around the
	//       local ground height.
	//    Nothing is ever derived from the visual bake (see the module
	//    comment: grass, trees and clutter never collide).
	segs: [dynamic]Wall_Seg
	if zone.collision_model != nil {
		cm := zone.collision_model.model
		for mi in 0 ..< int(cm.meshCount) {
			mesh := &cm.meshes[mi]
			verts := mesh.vertices
			if verts == nil do continue
			vcount := int(mesh.vertexCount)
			tri_n := vcount
			if mesh.indices != nil do tri_n = int(mesh.triangleCount) * 3
			for t := 0; t + 2 < tri_n; t += 3 {
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
				nx := (by - ay) * (cz - az) - (bz - az) * (cy - ay)
				ny := (bz - az) * (cx - ax) - (bx - ax) * (cz - az)
				nz := (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
				nlen := math.sqrt(nx * nx + ny * ny + nz * nz)
				if nlen < 1e-9 do continue
				if math.abs(ny) / nlen >= WALL_TRI_NY_MAX do continue
				// the wall piece's vertical extent (inflated so proxies
				// never leave hairline gaps at top/bottom)
				y_min := min(min(ay, by), cy) - 0.15
				y_max := max(max(ay, by), cy) + 0.15
				ex, ez := bx - ax, bz - az
				if ex * ex + ez * ez > 0.01 {
					append(&segs, Wall_Seg{ax, az, bx, bz, y_min, y_max})
				}
				ex, ez = cx - bx, cz - bz
				if ex * ex + ez * ez > 0.01 {
					append(&segs, Wall_Seg{bx, bz, cx, cz, y_min, y_max})
				}
				ex, ez = ax - cx, az - cz
				if ex * ex + ez * ez > 0.01 {
					append(&segs, Wall_Seg{cx, cz, ax, az, y_min, y_max})
				}
			}
		}
	}
	for &col in zone.colliders {
		xa, xb := col.x - col.w * 0.5, col.x + col.w * 0.5
		za, zb := col.z - col.d * 0.5, col.z + col.d * 0.5
		y_min, y_max := _seg_band_from_ground(hf, col.x, col.z)
		append(&segs, Wall_Seg{xa, za, xb, za, y_min, y_max})
		append(&segs, Wall_Seg{xb, za, xb, zb, y_min, y_max})
		append(&segs, Wall_Seg{xb, zb, xa, zb, y_min, y_max})
		append(&segs, Wall_Seg{xa, zb, xa, za, y_min, y_max})
	}
	// c) blocking world-object instances (fences, statues): the oriented
	//    rectangle around each. Fence segments placed end-to-end also get a
	//    center-to-center line between aligned neighbors so junctions never
	//    gap (player radius 0.45 cannot slip anything < 0.9u).
	for i in 0 ..< len(zone.instances) {
		inst := &zone.instances[i]
		if inst.hl <= 0 do continue
		fx, fz := math.cos(inst.yaw) * inst.hl, math.sin(inst.yaw) * inst.hl
		gx, gz := -math.sin(inst.yaw) * inst.hw, math.cos(inst.yaw) * inst.hw
		x0, z0 := inst.x - fx + gx, inst.z - fz + gz
		x1, z1 := inst.x + fx + gx, inst.z + fz + gz
		x2, z2 := inst.x + fx - gx, inst.z + fz - gz
		x3, z3 := inst.x - fx - gx, inst.z - fz - gz
		y_min, y_max := _seg_band_from_ground(hf, inst.x, inst.z)
		append(&segs, Wall_Seg{x0, z0, x1, z1, y_min, y_max})
		append(&segs, Wall_Seg{x1, z1, x2, z2, y_min, y_max})
		append(&segs, Wall_Seg{x2, z2, x3, z3, y_min, y_max})
		append(&segs, Wall_Seg{x3, z3, x0, z0, y_min, y_max})
	}
	for i in 0 ..< len(zone.instances) {
		a := &zone.instances[i]
		if a.hl < 1.5 do continue // chain fence-style boxes only, not statues
		for j in i + 1 ..< len(zone.instances) {
			b := &zone.instances[j]
			if b.hl < 1.5 do continue
			dx, dz := b.x - a.x, b.z - a.z
			d := math.sqrt(dx * dx + dz * dz)
			if d > 4.5 || d < 0.1 do continue
			// both headings agree with each other (mod 180°) and with the
			// line between the instances (it's a fence run, not a corner)
			d_yaw := _fold_pi(b.yaw - a.yaw)
			if math.abs(d_yaw) > 0.35 do continue
			bearing := math.atan2(dz, dx)
			d_bear := _fold_pi(bearing - a.yaw)
			if math.abs(d_bear) > 0.35 do continue
			y_min, y_max := _seg_band_from_ground(hf, (a.x + b.x) * 0.5, (a.z + b.z) * 0.5)
			append(&segs, Wall_Seg{a.x, a.z, b.x, b.z, y_min, y_max})
		}
	}
	hf.segs = segs[:]

	// 7b. Segment spatial hash (CSR over SEG_GRID_CELL cells, footprints
	//     inflated by the actor radius): the movement wall pass tests one
	//     bucket per frame instead of every segment on the map.
	{
		hf.seg_grid_cols = int(math.ceil_f32((f32(hf.cols) * hf.cell) / SEG_GRID_CELL)) + 1
		hf.seg_grid_rows = int(math.ceil_f32((f32(hf.rows) * hf.cell) / SEG_GRID_CELL)) + 1
		n_cells := hf.seg_grid_cols * hf.seg_grid_rows
		hf.seg_ptr = make([]i32, n_cells + 1)
		reach := PLAYER_COLLIDE_RADIUS + 0.1
		counts := make([]i32, n_cells)
		defer delete(counts)
		for seg in hf.segs {
			cmin := max(0, int(math.floor_f32((min(seg.x1, seg.x2) - reach - hf.origin_x) / SEG_GRID_CELL)))
			cmax := min(hf.seg_grid_cols - 1, int(math.floor_f32((max(seg.x1, seg.x2) + reach - hf.origin_x) / SEG_GRID_CELL)))
			rmin := max(0, int(math.floor_f32((min(seg.z1, seg.z2) - reach - hf.origin_z) / SEG_GRID_CELL)))
			rmax := min(hf.seg_grid_rows - 1, int(math.floor_f32((max(seg.z1, seg.z2) + reach - hf.origin_z) / SEG_GRID_CELL)))
			for r := rmin; r <= rmax; r += 1 {
				for c := cmin; c <= cmax; c += 1 {
					counts[r * hf.seg_grid_cols + c] += 1
				}
			}
		}
		for i in 0 ..< n_cells do hf.seg_ptr[i + 1] = hf.seg_ptr[i] + counts[i]
		hf.seg_grid = make([]i32, hf.seg_ptr[n_cells])
		for i in 0 ..< n_cells do counts[i] = 0
		for seg, si in hf.segs {
			cmin := max(0, int(math.floor_f32((min(seg.x1, seg.x2) - reach - hf.origin_x) / SEG_GRID_CELL)))
			cmax := min(hf.seg_grid_cols - 1, int(math.floor_f32((max(seg.x1, seg.x2) + reach - hf.origin_x) / SEG_GRID_CELL)))
			rmin := max(0, int(math.floor_f32((min(seg.z1, seg.z2) - reach - hf.origin_z) / SEG_GRID_CELL)))
			rmax := min(hf.seg_grid_rows - 1, int(math.floor_f32((max(seg.z1, seg.z2) + reach - hf.origin_z) / SEG_GRID_CELL)))
			for r := rmin; r <= rmax; r += 1 {
				for c := cmin; c <= cmax; c += 1 {
					k := r * hf.seg_grid_cols + c
					hf.seg_grid[hf.seg_ptr[k] + counts[k]] = i32(si)
					counts[k] += 1
				}
			}
		}
	}

	// 8. Walkability: uncovered cells (holes) block — nothing else. Walls
	//    are geometric segments; every tile-based bleed class (slope lips,
	//    steep faces, proxy footprints, their erosion halos) is gone from
	//    the mask. Hole cells still block movement (walking into a cliff
	//    face would teletransport the actor down its height).
	for r in 0 ..< rows {
		for c in 0 ..< cols {
			i := r * cols + c
			hf.walk[i] = hf.valid[i]
			hf.reasons[i] = HF_BLOCK_NONE
			if !hf.valid[i] do hf.reasons[i] = HF_BLOCK_HOLE
		}
	}

	// 8. Erode walkable one cell away from HOLES only (uncovered cells:
	//    cliff faces, voids) so the player's *center* never hangs over an
	//    edge. Walls, hit proxies and lips don't seed erosion — their halos
	//    were bleeding a blocked tile deep into open walkways.
	eroded := make([]bool, total)
	for r in 0 ..< rows {
		for c in 0 ..< cols {
			i := r * cols + c
			if !hf.walk[i] do continue
			ok := true
			for dr := -1; dr <= 1; dr += 1 {
				for dc := -1; dc <= 1; dc += 1 {
					nc, nr := c + dc, r + dr
					if nc < 0 || nc >= cols || nr < 0 || nr >= rows {
						ok = false
						break
					}
					if hf.reasons[nr * cols + nc] == HF_BLOCK_HOLE {
						ok = false
						break
					}
				}
				if !ok do break
			}
			eroded[i] = ok
			if !ok do hf.reasons[i] = HF_BLOCK_ERODE
		}
	}
	delete(hf.walk)
	hf.walk = eroded

	// 8b. Wall-segment clearance: rasterize the extracted wall lines into
	//     the walk mask inflated by the actor radius, so pathfinding (A*)
	//     routes around walls. Movement itself collides against the
	//     segments geometrically — this grid only steers it.
	{
		reach := 0.5 * cell + PLAYER_COLLIDE_RADIUS
		reach2 := reach * reach
		for seg in hf.segs {
			_hf_raster_seg_mask(hf, seg, reach, reach2)
		}
	}

	// 10. JSON obstacles (structures / rocks) block their footprint. Trees
	//     and bushes are decor — no collision.
	_hf_block_obstacles(hf, zone)

	// 11. Map border margin.
	margin := 2
	for r in 0 ..< rows {
		for c in 0 ..< cols {
			if c < margin || c >= cols - margin || r < margin || r >= rows - margin {
				hf.walk[r * cols + c] = false
				hf.reasons[r * cols + c] = HF_BLOCK_MARGIN
			}
		}
	}

	// 11b. No-stand discs from the manifest instances: solid-but-walkthrough
	//      objects (benches, barrels, boxes, jars...) whose baked tops must
	//      never lift the actor — the slope limiter already cuts isolated
	//      tops, the discs also cut ramp-connected ones. Cells stay
	//      walkable; their stand reverts to the terrain snapshot, and only
	//      cells with no snapshot fall back to neighbor re-derivation.
	for &inst in zone.instances {
		if inst.nostand_r <= 0 do continue
		r2 := inst.nostand_r * inst.nostand_r
		cmin := max(0, int(math.floor_f32((inst.x - inst.nostand_r - hf.origin_x) / cell)))
		cmax := min(cols - 1, int(math.ceil_f32((inst.x + inst.nostand_r - hf.origin_x) / cell)))
		rmin := max(0, int(math.floor_f32((inst.z - inst.nostand_r - hf.origin_z) / cell)))
		rmax := min(rows - 1, int(math.ceil_f32((inst.z + inst.nostand_r - hf.origin_z) / cell)))
		for r in rmin ..= rmax {
			pz := hf.origin_z + (f32(r) + 0.5) * cell
			for c := cmin; c <= cmax; c += 1 {
				px := hf.origin_x + (f32(c) + 0.5) * cell
				dx := px - inst.x
				dz := pz - inst.z
				if dx * dx + dz * dz > r2 do continue
				i := r * cols + c
				if !hf.valid[i] do continue
				if ground_valid[i] {
					hf.stand[i] = ground_h[i]
				} else {
					hf.reasons[i] = HF_NOSTAND
					append(&nostand_cells, i)
				}
			}
		}
	}

	// 12. Stand heights: what actor y-snapping samples. Kept prop surfaces
	//     and the ground snapshot are already in place; blocked cells
	//     (walls, holes, borders) inherit the average of clean walkable
	//     neighbors (two sweeps reach a cell deep) — without this, bilinear
	//     sampling near a wall blended the wall-top height into the
	//     player's y and elevated them on touch. HF_NOSTAND cells (props
	//     over groundless terrain) then relax inward from their edges.
	for _ in 0 ..< 2 {
		for r in 0 ..< rows {
			for c in 0 ..< cols {
				i := r * cols + c
				if hf.walk[i] && hf.reasons[i] != HF_NOSTAND do continue
				sum := f32(0)
				n := 0
				for dr := -1; dr <= 1; dr += 1 {
					for dc := -1; dc <= 1; dc += 1 {
						nc, nr := c + dc, r + dr
						if nc < 0 || nc >= cols || nr < 0 || nr >= rows do continue
						ni := nr * cols + nc
						if !hf.walk[ni] || hf.reasons[ni] == HF_NOSTAND do continue
						sum += hf.stand[ni]
						n += 1
					}
				}
				if n > 0 do hf.stand[i] = sum / f32(n)
			}
		}
	}
	// 12b. No-stand interiors (cells with no ground snapshot): relax
	//      inward from the disc edges until stable.
	if len(nostand_cells) > 0 {
		for _ in 0 ..< 12 {
			changed := false
			for i in nostand_cells {
				r := i / cols
				c := i % cols
				sum := f32(0)
				n := 0
				for dr := -1; dr <= 1; dr += 1 {
					for dc := -1; dc <= 1; dc += 1 {
						nc, nr := c + dc, r + dr
						if nc < 0 || nc >= cols || nr < 0 || nr >= rows do continue
						ni := nr * cols + nc
						if !hf.walk[ni] do continue
						sum += hf.stand[ni]
						n += 1
					}
				}
				if n > 0 {
					avg := sum / f32(n)
					if hf.stand[i] != avg {
						hf.stand[i] = avg
						changed = true
					}
				}
			}
			if !changed do break
		}
	}
}

// Fold an angle into (-PI/2, PI/2] — for line-direction compares where a
// heading and its reverse describe the same fence line.
_fold_pi :: proc "contextless" (a: f32) -> f32 {
	h := f32(math.PI * 0.5)
	v := a
	for v > h do v -= f32(math.PI)
	for v < -h do v += f32(math.PI)
	return v
}

// Vertical blocking band for an authored footprint (JSON collider, fence,
// statue) that carries no Y of its own: a generous span around the local
// stand height. Fences/statues are ~1-3u tall; the band keeps them solid
// for anyone at grade while letting bridge/balcony actors pass above.
_seg_band_from_ground :: proc(hf: ^Terrain_Heightfield, x, z: f32) -> (f32, f32) {
	g, ok := terrain_height_at(hf, x, z)
	if !ok {
		g = hf.min_y
		return g - 1.0, hf.max_y + 1.0
	}
	return g - 1.0, g + 3.0
}

// Rasterize a wall segment's clearance into the walk mask: cells whose
// center lies within `reach` of the segment block (conservative cell range
// around the segment's AABB). Pathfinding-only — movement uses the segment
// geometrically.
_hf_raster_seg_mask :: proc(hf: ^Terrain_Heightfield, seg: Wall_Seg, reach, reach2: f32) {
	cmin := max(0, int(math.floor_f32((min(seg.x1, seg.x2) - reach - hf.origin_x) / hf.cell)))
	cmax := min(hf.cols - 1, int(math.ceil_f32((max(seg.x1, seg.x2) + reach - hf.origin_x) / hf.cell)))
	rmin := max(0, int(math.floor_f32((min(seg.z1, seg.z2) - reach - hf.origin_z) / hf.cell)))
	rmax := min(hf.rows - 1, int(math.ceil_f32((max(seg.z1, seg.z2) + reach - hf.origin_z) / hf.cell)))
	for r in rmin ..= rmax {
		pz := hf.origin_z + (f32(r) + 0.5) * hf.cell
		for cc := cmin; cc <= cmax; cc += 1 {
			px := hf.origin_x + (f32(cc) + 0.5) * hf.cell
			if _seg_dist2(px, pz, seg) <= reach2 {
				i := r * hf.cols + cc
				hf.walk[i] = false
				hf.reasons[i] = HF_BLOCK_WALL
			}
		}
	}
}

// Squared distance from point (px, pz) to segment.
_seg_dist2 :: proc "contextless" (px, pz: f32, seg: Wall_Seg) -> f32 {
	ex := seg.x2 - seg.x1
	ez := seg.z2 - seg.z1
	dx := px - seg.x1
	dz := pz - seg.z1
	len2 := ex * ex + ez * ez
	t := f32(0)
	if len2 > 1e-9 {
		t = (dx * ex + dz * ez) / len2
		t = min(max(t, 0), 1)
	}
	cx := seg.x1 + ex * t - px
	cz := seg.z1 + ez * t - pz
	return cx * cx + cz * cz
}

// How a model's triangles classify (see terrain_heightfield_build step 3).
_Tri_Class :: enum {
	// Authored terrain (the ground GLB): every non-steep triangle is
	// terrain-class — no shape-size tests. Curbs, steps and slope chips of
	// any size are ground.
	GROUND_MODEL,
	// The visual bake when a ground GLB exists: everything is object-class
	// (prop or strip bucket) — canopies, wall trim, furniture may only ever
	// ground the actor via band-kept surfaces.
	OBJECT_BAKE,
	// Legacy: no ground GLB, shape heuristics on the visual bake.
	LEGACY_SHAPE,
}

// Iterate a model's triangles (indexed or straight runs) into the
// classifier. Meshes are already world-space (glTF loader flattening).
_hf_classify_model :: proc(
	model: rl.Model,
	mode: _Tri_Class,
	ground_coords, prop_coords, strip_coords: ^[dynamic]f32,
	ground_refs, prop_refs, strip_refs: ^[dynamic]Tri_Sort_Ref,
) {
	for mi in 0 ..< int(model.meshCount) {
		mesh := &model.meshes[mi]
		verts := mesh.vertices
		if verts == nil do continue
		vcount := int(mesh.vertexCount)
		if mesh.indices != nil {
			n := int(mesh.triangleCount) * 3
			for t := 0; t + 2 < n; t += 3 {
				i0, i1, i2 := int(mesh.indices[t]), int(mesh.indices[t + 1]), int(mesh.indices[t + 2])
				if i0 >= vcount || i1 >= vcount || i2 >= vcount do continue
				_hf_classify_one(
					verts[i0 * 3 : i0 * 3 + 3],
					verts[i1 * 3 : i1 * 3 + 3],
					verts[i2 * 3 : i2 * 3 + 3],
					mode,
					ground_coords, prop_coords, strip_coords,
					ground_refs, prop_refs, strip_refs,
				)
			}
		} else {
			for v := 0; v + 2 < vcount; v += 3 {
				_hf_classify_one(
					verts[v * 3 : v * 3 + 3],
					verts[(v + 1) * 3 : (v + 1) * 3 + 3],
					verts[(v + 2) * 3 : (v + 2) * 3 + 3],
					mode,
					ground_coords, prop_coords, strip_coords,
					ground_refs, prop_refs, strip_refs,
				)
			}
		}
	}
}

// Sort one triangle into the ground / prop / strip / ignore buckets.
_hf_classify_one :: proc(
	a, b, c: []f32,
	mode: _Tri_Class,
	ground_coords, prop_coords, strip_coords: ^[dynamic]f32,
	ground_refs, prop_refs, strip_refs: ^[dynamic]Tri_Sort_Ref,
) {
	ax, ay, az := a[0], a[1], a[2]
	bx, by, bz := b[0], b[1], b[2]
	cx, cy, cz := c[0], c[1], c[2]
	if !_f32_finite(ax) || !_f32_finite(ay) || !_f32_finite(az) ||
		!_f32_finite(bx) || !_f32_finite(by) || !_f32_finite(bz) ||
		!_f32_finite(cx) || !_f32_finite(cy) || !_f32_finite(cz) {
		return
	}

	// Normal + normalized |ny| (the ≤70° cutoff): steeper triangles never
	// raise the field, and near-vertical planes would extrapolate garbage
	// heights across the half-cell raster reach. Steep bake geometry never
	// blocks either — walls collide via the authored hit proxies / JSON
	// colliders, never via the visual bake (grass tufts, tree canopies and
	// ground chip seams are shape-identical to fence panels).
	nx := (by - ay) * (cz - az) - (bz - az) * (cy - ay)
	ny := (bz - az) * (cx - ax) - (bx - ax) * (cz - az)
	nz := (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
	nlen := math.sqrt(nx * nx + ny * ny + nz * nz)
	if nlen < 1e-9 do return
	if math.abs(ny) / nlen < TERRAIN_TRI_NY_MIN do return

	// XZ extent = longest projected edge; width = shortest projected edge.
	e0 := math.sqrt((bx - ax) * (bx - ax) + (bz - az) * (bz - az))
	e1 := math.sqrt((cx - bx) * (cx - bx) + (cz - bz) * (cz - bz))
	e2 := math.sqrt((ax - cx) * (ax - cx) + (az - cz) * (az - cz))
	extent := max(max(e0, e1), e2)
	width := min(min(e0, e1), e2)

	dst_coords := prop_coords
	dst_refs := prop_refs
	switch mode {
	case .GROUND_MODEL:
		// Authored terrain: everything non-steep is ground, whatever its
		// size — the shape bands below exist to separate props FROM
		// terrain, which provenance already did.
		dst_coords = ground_coords
		dst_refs = ground_refs
	case .LEGACY_SHAPE:
		if extent >= GROUND_TRI_MIN_EXTENT && width >= GROUND_TRI_MIN_WIDTH {
			dst_coords = ground_coords
			dst_refs = ground_refs
		} else if width < GROUND_TRI_MIN_WIDTH {
			// Long thin slab — terrace paving field, walkway strip, wall top.
			// Rasterized with the ground clearance (these sit up to ~1.2 above
			// the base course), then judged per height band.
			dst_coords = strip_coords
			dst_refs = strip_refs
		}
	case .OBJECT_BAKE:
		if width < GROUND_TRI_MIN_WIDTH {
			dst_coords = strip_coords
			dst_refs = strip_refs
		}
	}
	if mode != .GROUND_MODEL && extent < PROP_TRI_MIN_EXTENT {
		return // decor: grass, bushes, potted plants, lamp trim
	}
	append(
		dst_coords,
		ax, ay, az,
		bx, by, bz,
		cx, cy, cz,
	)
	append(dst_refs, Tri_Sort_Ref{min_y = min(min(ay, by), cy), base = len(dst_coords) - 9})
}

// Raster a classified, min-y-ascending run of triangles. Each triangle is
// skipped when its bottom sits more than `clearance` above the ground built
// so far (floating geometry: canopies, crowns, caps).
_hf_raster_pass :: proc(hf: ^Terrain_Heightfield, coords: []f32, refs: []Tri_Sort_Ref, clearance: f32) {
	for ref in refs {
		c := coords[ref.base : ref.base + 9]
		if clearance > 0 {
			cxc := (c[0] + c[3] + c[6]) / 3.0
			czc := (c[2] + c[5] + c[8]) / 3.0
			g, ok := _hf_surface_at(hf, cxc, czc)
			if ok && ref.min_y - g > clearance do continue
		}
		_hf_raster_coords(hf, c)
	}
}

// Raster one triangle (9 floats: ax,ay,az, bx,by,bz, cx,cy,cz) into the
// heightfield. Conservative XZ coverage: a cell counts when the triangle
// passes within a half-cell-diagonal of the cell center, with the height
// sampled at that closest point — plain cell-center tests miss the many
// sub-cell triangles these maps tile their plazas and trim strips with.
_hf_raster_coords :: proc(hf: ^Terrain_Heightfield, c: []f32) {
	ax, ay, az := c[0], c[1], c[2]
	bx, by, bz := c[3], c[4], c[5]
	cx, cy, cz := c[6], c[7], c[8]

	// Plane (nx, ny, nz)·p + d = 0.
	nx := (by - ay) * (cz - az) - (bz - az) * (cy - ay)
	ny := (bz - az) * (cx - ax) - (bx - ax) * (cz - az)
	nz := (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
	if !_f32_finite(ny) || (ny > -1e-9 && ny < 1e-9) do return
	d := -(nx * ax + ny * ay + nz * az)

	cell := hf.cell
	trix_min := min(min(ax, bx), cx)
	trix_max := max(max(ax, bx), cx)
	triz_min := min(min(az, bz), cz)
	triz_max := max(max(az, bz), cz)

	cmin := max(0, int(math.floor_f32((trix_min - hf.origin_x) / cell) - 1))
	cmax := min(hf.cols - 1, int(math.ceil_f32((trix_max - hf.origin_x) / cell) + 1))
	rmin := max(0, int(math.floor_f32((triz_min - hf.origin_z) / cell) - 1))
	rmax := min(hf.rows - 1, int(math.ceil_f32((triz_max - hf.origin_z) / cell) + 1))
	if cmin > cmax || rmin > rmax do return

	half_diag2 := 0.5 * cell * cell // (half cell diagonal)²

	// Barycentric (2D over XZ) for the inside fast path — most cells of a
	// large triangle contain their center and never need the closest-point
	// walk. NOTE the planar coordinates: the classic formula's Y terms here
	// are world Z, not height.
	denom := (bz - cz) * (ax - cx) + (cx - bx) * (az - cz)
	usable := math.abs(denom) > 1e-9
	inv_denom := f32(0)
	if usable do inv_denom = 1.0 / denom

	for r in rmin ..= rmax {
		pz := hf.origin_z + (f32(r) + 0.5) * cell
		for cc := cmin; cc <= cmax; cc += 1 {
			px := hf.origin_x + (f32(cc) + 0.5) * cell
			h: f32
			covered := false
			if usable {
				l1 := ((bz - cz) * (px - cx) + (cx - bx) * (pz - cz)) * inv_denom
				l2 := ((cz - az) * (px - cx) + (ax - cx) * (pz - cz)) * inv_denom
				l3 := 1.0 - l1 - l2
				if l1 >= 0 && l2 >= 0 && l3 >= 0 {
					h = l1 * ay + l2 * by + l3 * cy
					covered = true
				}
			}
			if !covered {
				qx, qz := _closest_tri_xz(px, pz, ax, az, bx, bz, cx, cz)
				dx := px - qx
				dz := pz - qz
				if dx * dx + dz * dz > half_diag2 do continue
				h = (-d - nx * qx - nz * qz) / ny
			}
			i := r * hf.cols + cc
			if !hf.valid[i] || h > hf.heights[i] {
				hf.heights[i] = h
				hf.valid[i] = true
			}
		}
	}
}

_f32_finite :: proc "contextless" (v: f32) -> bool {
	return v == v && v < 1e30 && v > -1e30
}

// Closest point on the XZ projection of triangle (A, B, C) to P — Ericson's
// region-based closest-point-on-triangle, 2D. Returns the projected point.
_closest_tri_xz :: proc "contextless" (
	px, pz: f32,
	ax, az: f32,
	bx, bz: f32,
	cx, cz: f32,
) -> (f32, f32) {
	abx := bx - ax; abz := bz - az
	acx := cx - ax; acz := cz - az
	apx := px - ax; apz := pz - az
	d1 := abx * apx + abz * apz
	d2 := acx * apx + acz * apz
	if d1 <= 0 && d2 <= 0 {
		return ax, az // vertex region A
	}
	bpx := px - bx; bpz := pz - bz
	d3 := abx * bpx + abz * bpz
	d4 := acx * bpx + acz * bpz
	if d3 >= 0 && d4 <= d3 {
		return bx, bz // vertex region B
	}
	vc := d1 * d4 - d3 * d2
	if vc <= 0 && d1 >= 0 && d3 <= 0 {
		v := d1 / (d1 - d3)
		return ax + abx * v, az + abz * v // edge region AB
	}
	cpx := px - cx; cpz := pz - cz
	d5 := abx * cpx + abz * cpz
	d6 := acx * cpx + acz * cpz
	if d6 >= 0 && d5 <= d6 {
		return cx, cz // vertex region C
	}
	vb := d5 * d2 - d1 * d6
	if vb <= 0 && d2 >= 0 && d6 <= 0 {
		w := d2 / (d2 - d6)
		return ax + acx * w, az + acz * w // edge region AC
	}
	va := d3 * d6 - d5 * d4
	if va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0 {
		w := (d4 - d3) / ((d4 - d3) + (d5 - d6))
		return bx + (cx - bx) * w, bz + (cz - bz) * w // edge region BC
	}
	tot := va + vb + vc
	if tot == 0 {
		return ax, az // degenerate triangle
	}
	inv := 1.0 / tot
	v := vb * inv
	w := vc * inv
	return ax + abx * v + acx * w, az + abz * v + acz * w // interior
}

// Cell value from a named field (heights or stand), valid=false when out
// of bounds or uncovered.
_hf_field_cell :: proc(hf: ^Terrain_Heightfield, field: []f32, c, r: int) -> (f32, bool) {
	if c < 0 || c >= hf.cols || r < 0 || r >= hf.rows do return 0, false
	i := r * hf.cols + c
	if !hf.valid[i] do return 0, false
	return field[i], true
}

// Full surface height at a grid cell (wall tops included), valid=false when
// out of bounds or uncovered.
_hf_height_cell :: proc(hf: ^Terrain_Heightfield, c, r: int) -> (f32, bool) {
	if c < 0 || c >= hf.cols || r < 0 || r >= hf.rows do return 0, false
	i := r * hf.cols + c
	if !hf.valid[i] do return 0, false
	return hf.heights[i], true
}

// Mark JSON obstacle footprints unwalkable. Only genuinely solid things:
// structure rects and rocks. Trees / bushes / other decor get no collision
// (matching the terrain-bake prop rules above).
_hf_block_obstacles :: proc(hf: ^Terrain_Heightfield, zone: ^Zone_Definition) {
	cell := hf.cell
	half := cell * 0.5

	for &s in zone.structures {
		hw := s.size_w * 0.5 + half
		hd := s.size_d * 0.5 + half
		cmin := max(0, int(math.floor_f32((s.position.x - hw - hf.origin_x) / cell)))
		cmax := min(hf.cols - 1, int(math.floor_f32((s.position.x + hw - hf.origin_x) / cell)))
		rmin := max(0, int(math.floor_f32((s.position.z - hd - hf.origin_z) / cell)))
		rmax := min(hf.rows - 1, int(math.floor_f32((s.position.z + hd - hf.origin_z) / cell)))
		for r := rmin; r <= rmax; r += 1 {
			for c := cmin; c <= cmax; c += 1 {
				hf.walk[r * hf.cols + c] = false
				hf.reasons[r * hf.cols + c] = HF_BLOCK_OBSTACLE
			}
		}
	}

	for &c in zone.colliders {
		hw := c.w * 0.5 + half
		hd := c.d * 0.5 + half
		cmin := max(0, int(math.floor_f32((c.x - hw - hf.origin_x) / cell)))
		cmax := min(hf.cols - 1, int(math.floor_f32((c.x + hw - hf.origin_x) / cell)))
		rmin := max(0, int(math.floor_f32((c.z - hd - hf.origin_z) / cell)))
		rmax := min(hf.rows - 1, int(math.floor_f32((c.z + hd - hf.origin_z) / cell)))
		for r := rmin; r <= rmax; r += 1 {
			for cc := cmin; cc <= cmax; cc += 1 {
				hf.walk[r * hf.cols + cc] = false
				hf.reasons[r * hf.cols + cc] = HF_BLOCK_OBSTACLE
			}
		}
	}

	for &o in zone.objects {
		if o.otype != "rock" do continue
		radius := 0.35 * o.scale + half
		cc := (o.position.x - hf.origin_x) / cell
		cr := (o.position.z - hf.origin_z) / cell
		spread := int(math.ceil(radius / cell)) + 1
		for dr := -spread; dr <= spread; dr += 1 {
			for dc := -spread; dc <= spread; dc += 1 {
				c := int(cc) + dc
				r := int(cr) + dr
				if c < 0 || c >= hf.cols || r < 0 || r >= hf.rows do continue
				cx := hf.origin_x + (f32(c) + 0.5) * cell
				cz := hf.origin_z + (f32(r) + 0.5) * cell
				dx := cx - o.position.x
				dz := cz - o.position.z
				if dx * dx + dz * dz <= radius * radius {
					hf.walk[r * hf.cols + c] = false
					hf.reasons[r * hf.cols + c] = HF_BLOCK_OBSTACLE
				}
			}
		}
	}
}

// ── queries ──────────────────────────────────────────────────────────────────

// Bilinear FULL-surface height (wall tops included) at a world point —
// the build-time sampler: raster clearance checks run before stand is
// finalized, so they must read heights, not stand.
_hf_surface_at :: proc(hf: ^Terrain_Heightfield, x, z: f32) -> (f32, bool) {
	return _hf_bilinear_at(hf, hf.heights, x, z)
}

// Bilinear stand height (walkable ground — wall tops excluded, they're
// diluted into the surrounding ground so sampling near a wall can't
// elevate the actor) at a world point. Falls back to the nearest covered
// cell when only some of the 2×2 stencil is valid; false when the point is
// outside the heightfield or in a hole.
terrain_height_at :: proc(hf: ^Terrain_Heightfield, x, z: f32) -> (f32, bool) {
	return _hf_bilinear_at(hf, hf.stand, x, z)
}

// Full-surface height (object tops included — rays and debug views) at a
// world point, sampled from the raw heights field.
terrain_full_height_at :: proc(hf: ^Terrain_Heightfield, x, z: f32) -> (f32, bool) {
	return _hf_bilinear_at(hf, hf.heights, x, z)
}

_hf_bilinear_at :: proc(hf: ^Terrain_Heightfield, field: []f32, x, z: f32) -> (f32, bool) {
	if hf == nil do return 0, false
	fx := (x - hf.origin_x) / hf.cell - 0.5
	fz := (z - hf.origin_z) / hf.cell - 0.5
	c0 := int(math.floor_f32(fx))
	r0 := int(math.floor_f32(fz))
	tx := fx - f32(c0)
	tz := fz - f32(r0)

	h00, ok00 := _hf_field_cell(hf, field, c0, r0)
	h10, ok10 := _hf_field_cell(hf, field, c0 + 1, r0)
	h01, ok01 := _hf_field_cell(hf, field, c0, r0 + 1)
	h11, ok11 := _hf_field_cell(hf, field, c0 + 1, r0 + 1)
	if ok00 && ok10 && ok01 && ok11 {
		h0 := h00 + (h10 - h00) * tx
		h1 := h01 + (h11 - h01) * tx
		return h0 + (h1 - h0) * tz, true
	}

	// Partial stencil: nearest covered cell wins (no interpolation).
	best := f32(0)
	best_d := f32(1e30)
	for dr := 0; dr <= 1; dr += 1 {
		for dc := 0; dc <= 1; dc += 1 {
			h, ok := _hf_field_cell(hf, field, c0 + dc, r0 + dr)
			if !ok do continue
			dx := (tx - f32(dc)) * (tx - f32(dc)) + (tz - f32(dr)) * (tz - f32(dr))
			if dx < best_d {
				best_d = dx
				best = h
			}
		}
	}
	if best_d < 1e29 do return best, true
	return 0, false
}

// Exact visual ground under (x, z): ray-samples the terrain mesh triangles
// bucketed at the surrounding cells and returns the highest surface no
// higher than `y_max`. Terrain-class triangles (slopes, stairs chips,
// plazas — the first mesh_ground_count ids) always ground the actor, so
// walking down slopes or across pavement is exact. Object-class triangles
// (the visual bake: courses, branches, counters, and — where the ground
// GLB has seams — the rendered floor itself) ground on any surface at or
// below the walk field + a step, and `field_ok=false` (probe-style
// callers) skips that field comparison entirely. Surfaces ABOVE the field
// are what this gate refuses: canopies, wall trim and counter tops must
// never ladder the actor upward. Surfaces steeper than ~60° only count as
// drops, never upward snaps.
terrain_mesh_ground_at :: proc(hf: ^Terrain_Heightfield, x, z, y_max, y_cur: f32, field_ok: bool, stand_ref: f32) -> (f32, bool) {
	if hf == nil || hf.mesh_coords == nil do return 0, false
	c := int(math.floor_f32((x - hf.origin_x) / hf.cell))
	r := int(math.floor_f32((z - hf.origin_z) / hf.cell))
	best := f32(0)
	found := false
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
				// XZ barycentric containment (exact for vertical rays).
				// The denominator pairs the SAME edges as the numerators
				// below (and as _hf_raster_coords) — pairing different
				// edges zeroes out on any triangle with two vertices at
				// equal height (every flat floor quad) and returns
				// garbage coverage/heights on near-flat ones.
				denom := (bz - cz2) * (ax - cx2) + (cx2 - bx) * (az - cz2)
				if abs(denom) < 1e-9 do continue
				l1 := ((bz - cz2) * (x - cx2) + (cx2 - bx) * (z - cz2)) / denom
				l2 := ((cz2 - az) * (x - cx2) + (ax - cx2) * (z - cz2)) / denom
				l3 := 1.0 - l1 - l2
				if l1 < 0 || l2 < 0 || l3 < 0 do continue
				h := l1 * ay + l2 * by + l3 * cy2
				if h > y_max do continue
				if tid >= hf.mesh_ground_count {
					// object-class (visual bake): surfaces at/below the
					// walk field + a step are ground — the rendered floor
					// must catch the actor even where the field's value is
					// phantom-high or the cell is a field hole (ground-GLB
					// seam). Only surfaces ABOVE the field are refused, so
					// canopies and wall courses can never ladder upward.
					// field_ok=false (probe callers) skips the comparison.
					if field_ok && h > stand_ref + MAX_STEP_UP do continue
				} else if h > y_cur {
					// terrain-class upward snap: the surface must be
					// walkable, not a cliff/wall face (normal within ~60°
					// of up)
					ny := (bz - az) * (cx2 - ax) - (bx - ax) * (cz2 - az)
					nx := (by - ay) * (cz2 - az) - (bz - az) * (cy2 - ay)
					nz := (bx - ax) * (cy2 - ay) - (by - ay) * (cx2 - ax)
					if ny * ny + nx * nx + nz * nz < 1e-9 do continue
					if ny < 0.5 * math.sqrt(ny * ny + nx * nx + nz * nz) do continue
				}
				if !found || h > best {
					best = h
					found = true
				}
			}
		}
	}
	return best, found
}

// Is the heightfield's walk surface at this spot a kept band surface
// (stair treads, paved plazas, walkways — stand == the band surface) as
// opposed to a cut/fallback one (stand == the terrain beneath an object)?
terrain_band_kept_at :: proc(hf: ^Terrain_Heightfield, x, z: f32) -> bool {
	if hf == nil do return false
	c := int(math.floor_f32((x - hf.origin_x) / hf.cell))
	r := int(math.floor_f32((z - hf.origin_z) / hf.cell))
	if c < 0 || c >= hf.cols || r < 0 || r >= hf.rows do return false
	i := r * hf.cols + c
	return hf.valid[i] && abs(hf.stand[i] - hf.heights[i]) <= 0.05
}

// Convenience for draw sites: terrain height or 0 (flat-planet fallback).
terrain_y_at :: proc(zone: ^Zone_Definition, x, wz: f32) -> f32 {
	if zone == nil || zone.heightfield == nil do return 0
	h, ok := terrain_height_at(zone.heightfield, x, wz)
	return h if ok else 0
}

// Nearest walkable fine cell to (x, z), scanning outward by Chebyshev rings.
// Returns the point unchanged when it is already walkable; false when
// nothing walkable is within `max_r` cells.
terrain_walkable_near :: proc(hf: ^Terrain_Heightfield, x, z: f32, max_r: int) -> (f32, f32, bool) {
	if terrain_walkable(hf, x, z) do return x, z, true
	c0 := int(math.floor_f32((x - hf.origin_x) / hf.cell))
	r0 := int(math.floor_f32((z - hf.origin_z) / hf.cell))
	for rad in 1 ..= max_r {
		for dr in -rad ..= rad {
			for dc in -rad ..= rad {
				if max(abs(dc), abs(dr)) != rad do continue
				c, r := c0 + dc, r0 + dr
				if c < 0 || c >= hf.cols || r < 0 || r >= hf.rows do continue
				if hf.walk[r * hf.cols + c] {
					return hf.origin_x + (f32(c) + 0.5) * hf.cell,
						hf.origin_z + (f32(r) + 0.5) * hf.cell,
						true
				}
			}
		}
	}
	return 0, 0, false
}

// Drop a world position onto standable ground: relocates XZ to the nearest
// walkable cell when the point lands inside a wall/cliff/roof footprint
// (flat-world spawn coordinates routinely do on the terrain bakes), then
// snaps y to the surface. No-op for zones without a heightfield.
terrain_place :: proc(zone: ^Zone_Definition, pos: rl.Vector3) -> rl.Vector3 {
	if zone == nil do return pos
	hf := zone.heightfield
	if hf == nil do return pos
	x, z := pos.x, pos.z
	if !terrain_standable(hf, x, z) {
		nx, nz, ok := terrain_walkable_near(hf, x, z, 6)
		if ok {
			x, z = nx, nz
		}
	}
	y := pos.y
	if h, ok := terrain_height_at(hf, x, z); ok do y = h
	return {x, y, z}
}

// Is the world point standable for MOVEMENT: covered by ground geometry
// and inside the map margin. Walls are not part of this — they collide
// geometrically via the extracted segments; the walk mask (terrain_walkable)
// is pathfinding-only and must never gate movement.
terrain_standable :: proc(hf: ^Terrain_Heightfield, x, z: f32) -> bool {
	if hf == nil do return false
	c := int(math.floor_f32((x - hf.origin_x) / hf.cell))
	r := int(math.floor_f32((z - hf.origin_z) / hf.cell))
	if c < 0 || c >= hf.cols || r < 0 || r >= hf.rows do return false
	i := r * hf.cols + c
	return hf.valid[i] && hf.reasons[i] != HF_BLOCK_MARGIN
}

// Is the world point routable for pathfinding (A* grid semantics: holes,
// wall clearance, obstacles, margin block).
terrain_walkable :: proc(hf: ^Terrain_Heightfield, x, z: f32) -> bool {
	if hf == nil do return false
	c := int(math.floor_f32((x - hf.origin_x) / hf.cell))
	r := int(math.floor_f32((z - hf.origin_z) / hf.cell))
	if c < 0 || c >= hf.cols || r < 0 || r >= hf.rows do return false
	return hf.walk[r * hf.cols + c]
}

// Best-effort walk surface under (x, z): the exact mesh sample first
// (terrain-class triangles always ground; object-class ground on anything
// at/below the field + a step — the rendered floor under a phantom field
// value or a ground-GLB seam must catch the actor), the stand field as
// fallback clamped to the highest local visual surface. This is the one
// probe both the movement resolver and the entity pin use.
_terrain_ground_at :: proc(hf: ^Terrain_Heightfield, x, z, y_top, y_cur: f32) -> (f32, bool) {
	stand_ref, field_ok := terrain_height_at(hf, x, z)
	if hg, ok := terrain_mesh_ground_at(hf, x, z, y_top, y_cur, field_ok, stand_ref); ok {
		return hg, true
	}
	if h, ok := terrain_height_at(hf, x, z); ok {
		// Conservative rasterization can paint phantom heights at cells no
		// triangle truly covers (border slopes): clamp the field value to
		// the highest local visual surface.
		if mt, mok := terrain_mesh_ground_at(hf, x, z, 1e30, -1e30, false, -1e30); mok {
			if h > mt do h = mt
		}
		// The field carries 60-70° slope faces the mesh's upward-snap gate
		// rejects on purpose; honoring them here would lift a grounded
		// actor more than a step (and "land" a faller on ground above his
		// frame-start height). Rises beyond y_top read as no ground.
		if h > y_top do return 0, false
		return h, true
	}
	return 0, false
}

// Can an actor move to (x, z)? Standability (holes, map edge) plus the
// slope rule: the walk surface there must not rise more than MAX_STEP_UP
// above `base` — the actor's feet while airborne (drifting forward into a
// hillside mid-fall is what buried actors inside steep slopes), or the
// walk surface under them while grounded. Measuring from the CURRENT
// surface rather than the feet keeps the gate honest where the exact mesh
// and the conservatively-rasterized field diverge: an actor grounded in a
// mesh pocket below the field must still be able to walk out, and a
// field-carried steep face still blocks because the base rises with it.
_terrain_step_ok :: proc(hf: ^Terrain_Heightfield, x, z, base: f32, grounded: bool) -> bool {
	if !terrain_standable(hf, x, z) do return false
	cap := base + MAX_STEP_UP
	if !grounded do cap = base + 0.05
	// Uncapped surface estimate: exact mesh up to the cap, merged with the
	// stand field (which carries 60-70° slope faces the mesh's upward-snap
	// steepness gate rejects on purpose).
	g_mesh, ok_mesh := _terrain_ground_at(hf, x, z, cap, base)
	g := g_mesh
	ok := ok_mesh
	if g_field, ok_field := terrain_height_at(hf, x, z); ok_field {
		g = max(g, g_field)
		ok = true
	}
	if ok && g > cap do return false
	return true
}

// Collision-resolving move with gravity. `pos` is the actor's current
// position; (dx, dz) the frame's intended displacement; `vert` the carried
// vertical state (see Vertical_State). Blocked destinations degrade to axis
// slides (wall-hugging); an actor already inside blocked terrain always
// accepts the move so it can escape. While grounded the actor tracks the
// surface exactly — steps up to MAX_STEP_UP, downhill snap within
// tolerance — and anything beyond detaches into a gravity fall (walking
// off a ledge accelerates down instead of teleporting; nothing can be
// climbed by repeated airborne snaps). Walls collide as Y-bounded
// segments: they never shove an actor passing above or below them. Zones
// without a heightfield pass through unchanged (legacy flat movement).
terrain_move :: proc(
	zone: ^Zone_Definition,
	pos:  rl.Vector3,
	dx, dz: f32,
	vert: Vertical_State,
	dt:   f32,
) -> (rl.Vector3, Vertical_State) {
	hf: ^Terrain_Heightfield = nil
	if zone != nil do hf = zone.heightfield
	if hf == nil {
		return {pos.x + dx, pos.y, pos.z + dz}, vert
	}

	y := pos.y
	px, pz := pos.x, pos.z
	nx, nz := px + dx, pz + dz

	// ---- horizontal ----
	// Holes and (while grounded) too-steep surfaces gate movement; walls
	// come from the geometric pass below. The gate measures rises against
	// `base`: the feet, lifted to the local walk surface when the actor
	// stands below it (exact-mesh pockets under the rasterized field).
	base := y
	if vert.grounded {
		if f, ok := terrain_height_at(hf, px, pz); ok && f > base do base = f
	}
	if !terrain_standable(hf, px, pz) {
		// Spawned / pushed into a hole: accept movement so the actor can
		// walk back onto solid ground.
		px, pz = nx, nz
	} else if _terrain_step_ok(hf, nx, nz, base, vert.grounded) {
		px, pz = nx, nz
	} else if dx != 0 && _terrain_step_ok(hf, nx, pz, base, vert.grounded) {
		px = nx // slide along Z-facing faces
	} else if dz != 0 && _terrain_step_ok(hf, px, nz, base, vert.grounded) {
		pz = nz // slide along X-facing faces
	}

	// ---- walls (geometric, Y-bounded, spatially hashed) ----
	// Push the actor's circle out of every wall segment it overlaps,
	// sliding along it. Two sweeps so corners settle. A segment whose
	// vertical span misses the actor's [feet, head] span never touches
	// them — ground-level fences don't shove bridge walkers, dungeon
	// walls don't block the balcony above.
	if len(hf.seg_grid) > 0 {
		r := PLAYER_COLLIDE_RADIUS
		top := y + ACTOR_HEIGHT
		for _ in 0 ..< 2 {
			// Bucket is re-derived per sweep: the pushout itself can move
			// the actor across a coarse cell boundary.
			sc := int(math.floor_f32((px - hf.origin_x) / SEG_GRID_CELL))
			sr := int(math.floor_f32((pz - hf.origin_z) / SEG_GRID_CELL))
			if sc < 0 || sc >= hf.seg_grid_cols || sr < 0 || sr >= hf.seg_grid_rows {
				break
			}
			k := sr * hf.seg_grid_cols + sc
			for p in hf.seg_ptr[k] ..< hf.seg_ptr[k + 1] {
					seg := &hf.segs[hf.seg_grid[p]]
					if seg.y_max <= y + 0.05 || seg.y_min >= top - 0.05 do continue
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
					ox := px - cx
					oz := pz - cz
					d2 := ox * ox + oz * oz
					if d2 >= r * r do continue
				if d2 > 1e-8 {
					d := math.sqrt(d2)
					px = cx + ox / d * r
					pz = cz + oz / d * r
				}
			}
		}
	}

	// ---- vertical ----
	out := vert
	dist := math.sqrt(dx * dx + dz * dz)
	snap_down := max(SNAP_DOWN_BASE, dist * 1.5)
	if vert.grounded {
		g, gok := _terrain_ground_at(hf, px, pz, y + MAX_STEP_UP, y)
		if gok && g >= y - snap_down {
			// Still planted: follow the surface up a step or down a slope.
			y = g
			out.vy = 0
		} else {
			// Surface dropped away (ledge, cliff) or vanished (hole edge):
			// detach and let gravity run — no instant teleport to the bottom.
			out.grounded = false
			out.vy = 0
			out.fall_start_y = y
		}
	}
	if !out.grounded {
		old_y := y
		new_y := y + out.vy * dt
		out.vy = max(out.vy - GRAVITY * dt, -MAX_FALL_SPEED)
		y = new_y
		// Landing: the highest surface at or below the frame-start height
		// (crossing it this frame means feet contact).
		land, lok := _terrain_ground_at(hf, px, pz, old_y, old_y)
		if lok && new_y <= land {
			y = land
			out.vy = 0
			out.grounded = true
		}
		// Buried inside terrain, or falling down a sheer (>70°, never
		// rasterized) column with no landing surface below: relocate to
		// the nearest walkable ground at/below the current height and
		// land there — the classic "slide down the cliff to its base".
		if !out.grounded {
			if g_field, ok_f := terrain_height_at(hf, px, pz); ok_f && new_y < g_field - 25 {
				nx2, nz2, wok := _terrain_lower_ground_near(hf, px, pz, min(old_y, new_y), 24)
				if wok {
					px, pz = nx2, nz2
					if y3, ok3 := terrain_height_at(hf, px, pz); ok3 {
						y = y3
						out.vy = 0
						out.grounded = true
					}
				}
			}
		}
		// Final failsafe (deep out-of-world fall the relocation couldn't
		// resolve): land at the nearest ground at/below where the fall
		// began — a fall must never end higher than it started.
		if !out.grounded && new_y < hf.min_y - 60 {
			nx2, nz2, wok := _terrain_lower_ground_near(hf, px, pz, out.fall_start_y, 24)
			if !wok {
				nx2, nz2, wok = terrain_walkable_near(hf, px, pz, 8)
			}
			if wok {
				px, pz = nx2, nz2
			}
			y2, ok2 := terrain_height_at(hf, px, pz)
			y = y2 if ok2 else 0
			out.vy = 0
			out.grounded = true
		}
	}
	return {px, y, pz}, out
}

// Nearest walkable cell whose stand surface sits at/below `y_max` — the
// landing spot for sheer-column and buried falls. Chebyshev ring scan like
// terrain_walkable_near; false when nothing qualifies within `max_r` cells.
_terrain_lower_ground_near :: proc(
	hf: ^Terrain_Heightfield,
	x, z, y_max: f32,
	max_r: int,
) -> (f32, f32, bool) {
	c0 := int(math.floor_f32((x - hf.origin_x) / hf.cell))
	r0 := int(math.floor_f32((z - hf.origin_z) / hf.cell))
	for rad in 0 ..= max_r {
		for dr in -rad ..= rad {
			for dc in -rad ..= rad {
				if max(abs(dc), abs(dr)) != rad do continue
				c, r := c0 + dc, r0 + dr
				if c < 0 || c >= hf.cols || r < 0 || r >= hf.rows do continue
				i := r * hf.cols + c
				if !hf.valid[i] || !hf.walk[i] do continue
				if hf.stand[i] > y_max do continue
				return hf.origin_x + (f32(c) + 0.5) * hf.cell,
					hf.origin_z + (f32(r) + 0.5) * hf.cell,
					true
			}
		}
	}
	return 0, 0, false
}

// Cursor ray vs the world. Traces the EXACT collision geometry: every
// bucketed mesh triangle (ground + object class — clicks land on what you
// see, including canopies and stall tops) via Möller–Trumbore along a 2D
// grid DDA, and every wall segment as its vertical quad — so clicks no
// longer pass through walls or resolve to a bilinear approximation above
// slopes. Misses return false (no plane fallback — the terrain edge is a
// real edge). Zones without a heightfield fall back to the legacy y=0
// plane.
terrain_ray_hit :: proc(zone: ^Zone_Definition, ray: rl.Ray) -> (bool, rl.Vector3) {
	if zone == nil || zone.heightfield == nil {
		return ray_ground_hit(ray, 0.0)
	}
	hf := zone.heightfield

	// Slab test against the heightfield's box (padded in Y for float noise
	// and walkable dips slightly below the mesh bounds).
	bmin := rl.Vector3{hf.origin_x, hf.min_y - 5, hf.origin_z}
	bmax := rl.Vector3{hf.origin_x + f32(hf.cols) * hf.cell, hf.max_y + 5, hf.origin_z + f32(hf.rows) * hf.cell}
	t0, t1, hits_box := _ray_box_range(ray.position, ray.direction, bmin, bmax)
	if !hits_box do return false, {}
	if t0 < 0 do t0 = 0
	if t1 > 2000 do t1 = 2000 // past any terrain these exports reach

	best_t := f32(1e30)
	found := false

	// 1. Wall quads: 2D ray/segment crossing, kept when the hit point
	//    lies inside the segment's vertical span.
	for seg in hf.segs {
		ex := seg.x2 - seg.x1
		ez := seg.z2 - seg.z1
		denom := ray.direction.x * ez - ray.direction.z * ex
		if abs(denom) < 1e-9 do continue
		ox := seg.x1 - ray.position.x
		oz := seg.z1 - ray.position.z
		t := (ox * ez - oz * ex) / denom
		u := (ox * ray.direction.z - oz * ray.direction.x) / denom
		if t <= 0.01 || t >= best_t do continue
		if u < 0 || u > 1 do continue
		hy := ray.position.y + ray.direction.y * t
		if hy < seg.y_min || hy > seg.y_max do continue
		best_t = t
		found = true
	}

	// 2. Mesh triangles: Amanatides–Woo DDA over the heightfield cells
	//    along the ray's XZ projection, testing each visited cell's bucket
	//    with Möller–Trumbore. A triangle is bucketed in every cell its
	//    AABB covers, so the cell containing any hit point holds the
	//    triangle that was hit.
	{
		p0 := _ray_at(ray, t0)
		p1 := _ray_at(ray, t1)
		c := int(math.floor_f32((p0.x - hf.origin_x) / hf.cell))
		r := int(math.floor_f32((p0.z - hf.origin_z) / hf.cell))
		lx := p1.x - p0.x
		lz := p1.z - p0.z
		len_xz := math.sqrt(lx * lx + lz * lz)
		if len_xz > 1e-6 {
			idx := lx / len_xz
			idz := lz / len_xz
			step_c := idx > 0 ? 1 : -1
			step_r := idz > 0 ? 1 : -1
			// param s along [0, len_xz]
			s := f32(0)
			s_delta_c := f32(1e30)
			if abs(idx) > 1e-9 do s_delta_c = hf.cell / abs(idx)
			s_delta_r := f32(1e30)
			if abs(idz) > 1e-9 do s_delta_r = hf.cell / abs(idz)
			s_next_c := f32(1e30)
			if abs(idx) > 1e-9 {
				bound_c := hf.origin_x + f32(c + (step_c > 0 ? 1 : 0)) * hf.cell
				s_next_c = abs((bound_c - p0.x) / idx)
			}
			s_next_r := f32(1e30)
			if abs(idz) > 1e-9 {
				bound_r := hf.origin_z + f32(r + (step_r > 0 ? 1 : 0)) * hf.cell
				s_next_r = abs((bound_r - p0.z) / idz)
			}
			for s <= len_xz {
				if c >= 0 && c < hf.cols && r >= 0 && r < hf.rows {
					k := r * hf.cols + c
					for p in hf.mesh_ptr[k] ..< hf.mesh_ptr[k + 1] {
						gid := int(hf.mesh_tris[p]) * 9
						co := hf.mesh_coords
						tt := _ray_tri_t(
							ray.position, ray.direction,
							co[gid], co[gid + 1], co[gid + 2],
							co[gid + 3], co[gid + 4], co[gid + 5],
							co[gid + 6], co[gid + 7], co[gid + 8],
						)
						if tt > 0.01 && tt < best_t {
							best_t = tt
							found = true
						}
					}
				}
				if s_next_c <= s_next_r {
					if s_next_c > len_xz do break
					s = s_next_c
					s_next_c += s_delta_c
					c += step_c
				} else {
					if s_next_r > len_xz do break
					s = s_next_r
					s_next_r += s_delta_r
					r += step_r
				}
			}
		} else {
			// Effectively vertical ray: just probe the one cell (3×3 for
			// boundary safety, matching terrain_mesh_ground_at).
			if c >= -1 && c <= hf.cols && r >= -1 && r <= hf.rows {
				for dr := -1; dr <= 1; dr += 1 {
					for dc := -1; dc <= 1; dc += 1 {
						cc, rr := c + dc, r + dr
						if cc < 0 || cc >= hf.cols || rr < 0 || rr >= hf.rows do continue
						k := rr * hf.cols + cc
						for p in hf.mesh_ptr[k] ..< hf.mesh_ptr[k + 1] {
							gid := int(hf.mesh_tris[p]) * 9
							co := hf.mesh_coords
							tt := _ray_tri_t(
								ray.position, ray.direction,
								co[gid], co[gid + 1], co[gid + 2],
								co[gid + 3], co[gid + 4], co[gid + 5],
								co[gid + 6], co[gid + 7], co[gid + 8],
							)
							if tt > 0.01 && tt < best_t {
								best_t = tt
								found = true
							}
						}
					}
				}
			}
		}
	}

	if !found do return false, {}
	return true, _ray_at(ray, best_t)
}

// Möller–Trumbore ray/triangle distance; -1 when parallel, outside, or
// behind the origin.
_ray_tri_t :: proc "contextless" (
	ro, rd: rl.Vector3,
	ax, ay, az, bx, by, bz, cx, cy, cz: f32,
) -> f32 {
	e1x, e1y, e1z := bx - ax, by - ay, bz - az
	e2x, e2y, e2z := cx - ax, cy - ay, cz - az
	px := rd.y * e2z - rd.z * e2y
	py := rd.z * e2x - rd.x * e2z
	pz := rd.x * e2y - rd.y * e2x
	det := e1x * px + e1y * py + e1z * pz
	if abs(det) < 1e-9 do return -1
	inv := 1.0 / det
	tx := ro.x - ax
	ty := ro.y - ay
	tz := ro.z - az
	u := (tx * px + ty * py + tz * pz) * inv
	if u < 0 || u > 1 do return -1
	qx := ty * e1z - tz * e1y
	qy := tz * e1x - tx * e1z
	qz := tx * e1y - ty * e1x
	v := (rd.x * qx + rd.y * qy + rd.z * qz) * inv
	if v < 0 || u + v > 1 do return -1
	return (e2x * qx + e2y * qy + e2z * qz) * inv
}

_ray_at :: proc "contextless" (ray: rl.Ray, t: f32) -> rl.Vector3 {
	return {
		ray.position.x + ray.direction.x * t,
		ray.position.y + ray.direction.y * t,
		ray.position.z + ray.direction.z * t,
	}
}

// Slab ray/AABB entry+exit range (slivers included: t0==t1 still hits).
_ray_box_range :: proc "contextless" (ro, rd, bmin, bmax: rl.Vector3) -> (f32, f32, bool) {
	tmin := f32(-1e30)
	tmax := f32(1e30)

	// X
	if abs(rd.x) < 1e-8 {
		if ro.x < bmin.x || ro.x > bmax.x do return 0, 0, false
	} else {
		inv := 1.0 / rd.x
		ta := (bmin.x - ro.x) * inv
		tb := (bmax.x - ro.x) * inv
		if ta > tb do ta, tb = tb, ta // negative direction swaps the slabs
		if ta > tmin do tmin = ta
		if tb < tmax do tmax = tb
	}
	// Y
	if abs(rd.y) < 1e-8 {
		if ro.y < bmin.y || ro.y > bmax.y do return 0, 0, false
	} else {
		inv := 1.0 / rd.y
		ta := (bmin.y - ro.y) * inv
		tb := (bmax.y - ro.y) * inv
		if ta > tb do ta, tb = tb, ta
		if ta > tmin do tmin = ta
		if tb < tmax do tmax = tb
	}
	// Z
	if abs(rd.z) < 1e-8 {
		if ro.z < bmin.z || ro.z > bmax.z do return 0, 0, false
	} else {
		inv := 1.0 / rd.z
		ta := (bmin.z - ro.z) * inv
		tb := (bmax.z - ro.z) * inv
		if ta > tb do ta, tb = tb, ta
		if ta > tmin do tmin = ta
		if tb < tmax do tmax = tb
	}

	if tmin > tmax do return 0, 0, false
	return tmin, tmax, true
}

// ── pathfinding bridge ───────────────────────────────────────────────────────

// Rebuild zone.collision_grid from the heightfield walk data: a coarse
// 2/4/8× downsample (capped by PF_MAX_CELLS) where a coarse cell is blocked
// when ANY fine cell inside it is unwalkable — conservative, so A* never
// routes through something terrain_move would refuse. Origin matches the
// heightfield so world_to_grid lines up with terrain_walkable.
collision_grid_from_heightfield :: proc(zone: ^Zone_Definition) {
	hf := zone.heightfield
	if hf == nil do return

	factor := 1
	for (hf.cols / factor) * (hf.rows / factor) > PF_MAX_CELLS {
		factor *= 2
	}
	cols := (hf.cols + factor - 1) / factor
	rows := (hf.rows + factor - 1) / factor
	total := cols * rows

	delete(zone.collision_grid)
	zone.collision_grid = nil
	resize(&zone.collision_grid, total)
	for i in 0 ..< total do zone.collision_grid[i] = false

	zone.collision_cols = cols
	zone.collision_rows = rows
	zone.collision_cell_size = hf.cell * f32(factor)
	zone.collision_origin_x = hf.origin_x
	zone.collision_origin_z = hf.origin_z

	for r in 0 ..< hf.rows {
		cr := r / factor
		for c in 0 ..< hf.cols {
			if hf.walk[r * hf.cols + c] do continue
			zone.collision_grid[cr * cols + (c / factor)] = true
		}
	}
}

// Nearest unblocked coarse cell to (c0, r0), scanning outward by Chebyshev
// rings. Lets a click on a cliff face / lake resolve to the closest standable
// point instead of dropping the move. False when nothing within `max_r`.
nearest_walkable_cell :: proc(zone: ^Zone_Definition, c0, r0, max_r: int) -> (int, int, bool) {
	for rad in 0 ..= max_r {
		for dr := -rad; dr <= rad; dr += 1 {
			for dc := -rad; dc <= rad; dc += 1 {
				if max(abs(dc), abs(dr)) != rad do continue
				c, r := c0 + dc, r0 + dr
				if !is_blocked(c, r, zone) do return c, r, true
			}
		}
	}
	return 0, 0, false
}

// ── debug visualization ──────────────────────────────────────────────────────

// Toggled from the F1 debug menu; render.odin draws blocked cells around
// the player when set.
debug_collision_vis: bool = false

// Toggled from the F1 debug menu; render.odin draws a bright vertical ray
// from the character's feet to the terrain ground sample — for screenshot
// analysis of elevation mismatches.
debug_ground_ray: bool = false

// Draw collision near `center`. Zones with original hit data render the
// proxy mesh itself as red wires — vertical quads flat against the wall
// models, exactly how the engine authored them — and every wall segment
// (proxy + terrain-derived fence/wall faces) within `radius` as a line at
// stand height. Fallback zones draw tiles only.
// Call inside BeginMode3D.
terrain_debug_draw :: proc(zone: ^Zone_Definition, center: rl.Vector3, radius: f32) {
	if zone == nil do return

	if hf := zone.heightfield; hf != nil {
		if zone.collision_model != nil {
			rl.DrawModelWires(zone.collision_model.model, {0, 0, 0}, 1.0, rl.Color{255, 70, 60, 200})
		}
		// The actual collision lines: proxy walls + authored collider boxes.
		r2 := radius * radius
		for seg in hf.segs {
			d1x := seg.x1 - center.x
			d1z := seg.z1 - center.z
			d2x := seg.x2 - center.x
			d2z := seg.z2 - center.z
			if d1x * d1x + d1z * d1z > r2 && d2x * d2x + d2z * d2z > r2 do continue
			y := terrain_y_at(zone, (seg.x1 + seg.x2) * 0.5, (seg.z1 + seg.z2) * 0.5) + 0.5
			rl.DrawLine3D(
				{seg.x1, y, seg.z1},
				{seg.x2, y, seg.z2},
				rl.Color{255, 160, 60, 220},
			)
		}
		return
	}

	// Legacy grid (procedural zones).
	if len(zone.collision_grid) == 0 do return
	cs := zone.collision_cell_size
	cmin := max(0, int(math.floor_f32((center.x - radius - zone.collision_origin_x) / cs)))
	cmax := min(zone.collision_cols - 1, int(math.ceil_f32((center.x + radius - zone.collision_origin_x) / cs)))
	rmin := max(0, int(math.floor_f32((center.z - radius - zone.collision_origin_z) / cs)))
	rmax := min(zone.collision_rows - 1, int(math.ceil_f32((center.z + radius - zone.collision_origin_z) / cs)))
	for r in rmin ..= rmax {
		for c in cmin ..= cmax {
			if !is_blocked(c, r, zone) do continue
			cx := zone.collision_origin_x + (f32(c) + 0.5) * cs
			cz := zone.collision_origin_z + (f32(r) + 0.5) * cs
			rl.DrawCube({cx, 0.06, cz}, cs * 0.9, 0.1, cs * 0.9, rl.Color{255, 70, 60, 100})
		}
	}
}
