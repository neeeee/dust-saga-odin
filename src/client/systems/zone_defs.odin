package systems

import "core:math"
import rl "vendor:raylib"

// Client-side zone/map definition. This matches the JSON files in
// src/client/assets/maps/*.json (a richer, raylib-oriented schema than the
// server's ZoneDefinition — the server's zoneDef inside WORLD_STATE is only
// used for spawn metadata; these map files drive the static world rendering).

RGB_F :: struct {
	r, g, b: f32,
}

Zone_Ground :: struct {
	color:            RGB_F,
	size:             f32,
	height_variation: f32,
}

Zone_Fog :: struct {
	color:   RGB_F,
	density: f32,
}

Map_Object :: struct {
	otype:    string, // "tree" | "rock" | "bush"
	position: rl.Vector3,
	scale:    f32,
	model:    string, // GLB filename (used once GLB loading is wired up)
}

Map_Structure :: struct {
	otype:       string, // "platform" | "fence" | "house"
	position:    rl.Vector3,
	size_w:      f32,
	size_h:      f32,
	size_d:      f32,
	color:       RGB_F,
	walls_color: RGB_F,
	roof_color:  RGB_F,
	has_roof:    bool,
}

Teleporter :: struct {
	id:           string,
	position:     rl.Vector3,
	target_zone:  string,
	target_spawn: string,
	radius:       f32,
	label:        string,
}

Map_Light :: struct {
	otype:     string, // "point" | "directional"
	position:  rl.Vector3,
	intensity: f32,
	range:     f32,
	color:     RGB_F,
}

// Manually-authored collision box (XZ footprint, heightless): the per-zone
// "objects that should have collision" list, authored from the map viewer
// while the geometric classifier stays walls-only. Purely blocking — never
// rendered. `label` names the object it covers ("bench_03") for debugging.
Collider :: struct {
	x:     f32,
	z:     f32,
	w:     f32,
	d:     f32,
	label: string,
}

// One placed world object from the Pandora manifest's `instances` list —
// the authored object placement the bake was exported from. Positions are
// engine centimeters (world = position / 100); yaw comes from the instance
// quaternion. `kind` is the manifest asset's class ("terrain_chip" |
// "object") — authored provenance for the collision policy resolved at
// parse time (see instance_collision in terrain_collision.odin): blocking
// objects carry an oriented footprint (hl/hw), never-elevate objects a
// no-stand disc radius, everything else zeros (no interaction at all).
Map_Instance :: struct {
	x, z:       f32,
	yaw:        f32,
	scale:      f32,
	kind:       string, // owned lowercase manifest kind ("" when unknown)
	hl, hw:     f32, // blocking oriented box half-extents (0 = doesn't block)
	nostand_r:  f32, // no-stand disc radius (0 = may raise stand)
}

Map_Lights :: [dynamic]Map_Light
Map_Structs :: [dynamic]Map_Structure

Zone_Definition :: struct {
	id:           string,
	name:         string,
	ground:       Zone_Ground,
	fog:          Zone_Fog,
	player_spawn: rl.Vector3,
	objects:      [dynamic]Map_Object,
	structures:   [dynamic]Map_Structure,
	teleporters:  [dynamic]Teleporter,
	lights:       [dynamic]Map_Light,
	colliders:    [dynamic]Collider,
	instances:    [dynamic]Map_Instance,
	loaded:       bool, // parsed successfully from disk

	// Whole-area terrain GLB (Pandora maps: source.terrain_glb in the JSON).
	// Owned by the assets cache — release via assets_model_release, never
	// UnloadModel directly. nil for the older procedural zones (no GLB).
	terrain: ^Model_Entry,
	// Per-mesh bounding spheres (cx, cy, cz, r) for the terrain model —
	// raylib's glTF loader flattens these maps into thousands of meshes
	// (up to ~38k), so render_zone frustum-culls them one sphere each.
	terrain_spheres: [][4]f32,
	// Per-material glTF alpha state for the terrain bake (see
	// glb_material_alpha): raylib's loaded materials drop alphaMode /
	// alphaCutoff, so the cutout shader receives them as per-draw uniforms.
	// nil → every material runs the shader's OPAQUE default path.
	terrain_alpha_modes:   []u8,
	terrain_alpha_cutoffs: []f32,
	// The area's original _hit.dxg collision proxies, exported to GLB by the
	// Pandora pipeline and named from the JSON's own source.collision field
	// (variant areas name their own proxy set; terrain-name derivation is
	// the fallback). When present its triangles are the authoritative
	// blocking walls (the original engine's own semantics: ground is
	// walkable, these volumes block). nil → the JSON colliders + instance
	// footprints carry the blocking.
	collision_model: ^Model_Entry,
	// The area's terrain-only GLB (chips + default fill, no props — exported
	// by `pandora_export ground`). When present, its triangles are the sole
	// terrain-class collision surface: actors ground on authored ground, and
	// every visual-bake triangle is object-class (canopies, trim, furniture
	// can only ground via band-kept surfaces). nil → the legacy shape
	// classifier runs on the visual bake.
	ground_model: ^Model_Entry,
	// The area's foliage GLB (<terrain>_decor.glb — plants, grass, flowers
	// from the same export). Its triangles are excluded from structure
	// walls: crossed billboard quads must never block anything. nil → no
	// foliage exclusion.
	decor_model: ^Model_Entry,
	// Rasterized collision/elevation data built from the terrain GLB (see
	// terrain_collision.odin). nil for procedural zones — every terrain_move /
	// terrain_height_at call site degrades to the legacy flat behavior.
	heightfield: ^Terrain_Heightfield,

	collision_grid:      [dynamic]bool,
	collision_cols:      int,
	collision_rows:      int,
	collision_cell_size: f32,
	collision_origin_x:  f32,
	collision_origin_z:  f32,
}

zone_init :: proc() -> ^Zone_Definition {
	z := new(Zone_Definition)
	z.objects = make([dynamic]Map_Object)
	z.structures = make([dynamic]Map_Structure)
	z.teleporters = make([dynamic]Teleporter)
	z.lights = make([dynamic]Map_Light)
	z.colliders = make([dynamic]Collider)
	z.instances = make([dynamic]Map_Instance)
	z.loaded = false
	return z
}

// Free a non-empty string owned by this module. Zone strings are produced by
// get_string_owned / strings.clone (heap) or left as "" — never literals — so
// anything with length is safe to delete.
zone_str_free :: proc(s: string) {
	if len(s) > 0 do delete(s)
}

// Free the zone. String fields are heap clones made at load time (see
// load_zone_map); zone_str_free releases them. Containers made in zone_init /
// filled during parse are deleted directly.
zone_destroy :: proc(z: ^Zone_Definition) {
	if z == nil do return
	zone_str_free(z.id)
	zone_str_free(z.name)
	for o in z.objects {
		zone_str_free(o.otype)
		zone_str_free(o.model)
	}
	if z.objects != nil do delete(z.objects)
	for s in z.structures {
		zone_str_free(s.otype)
	}
	if z.structures != nil do delete(z.structures)
	for t in z.teleporters {
		zone_str_free(t.id)
		zone_str_free(t.target_zone)
		zone_str_free(t.target_spawn)
		zone_str_free(t.label)
	}
	if z.teleporters != nil do delete(z.teleporters)
	for l in z.lights {
		zone_str_free(l.otype)
	}
	if z.lights != nil do delete(z.lights)
	if z.terrain != nil {
		assets_model_release(z.terrain)
		z.terrain = nil
	}
	for c in z.colliders {
		zone_str_free(c.label)
	}
	if z.colliders != nil do delete(z.colliders)
	for inst in z.instances {
		zone_str_free(inst.kind)
	}
	if z.instances != nil do delete(z.instances)
	if z.collision_model != nil {
		assets_model_release(z.collision_model)
		z.collision_model = nil
	}
	if z.ground_model != nil {
		assets_model_release(z.ground_model)
		z.ground_model = nil
	}
	if z.decor_model != nil {
		assets_model_release(z.decor_model)
		z.decor_model = nil
	}
	if z.terrain_spheres != nil do delete(z.terrain_spheres)
	if z.terrain_alpha_modes != nil do delete(z.terrain_alpha_modes)
	if z.terrain_alpha_cutoffs != nil do delete(z.terrain_alpha_cutoffs)
	if z.heightfield != nil {
		if z.heightfield.heights != nil do delete(z.heightfield.heights)
		if z.heightfield.stand != nil do delete(z.heightfield.stand)
		if z.heightfield.valid != nil do delete(z.heightfield.valid)
		if z.heightfield.walk != nil do delete(z.heightfield.walk)
		if z.heightfield.segs != nil do delete(z.heightfield.segs)
		if z.heightfield.seg_grid != nil do delete(z.heightfield.seg_grid)
		if z.heightfield.seg_ptr != nil do delete(z.heightfield.seg_ptr)
		if z.heightfield.reasons != nil do delete(z.heightfield.reasons)
		if z.heightfield.mesh_coords != nil do delete(z.heightfield.mesh_coords)
		if z.heightfield.mesh_ptr != nil do delete(z.heightfield.mesh_ptr)
		if z.heightfield.mesh_tris != nil do delete(z.heightfield.mesh_tris)
		free(z.heightfield)
		z.heightfield = nil
	}
	if z.collision_grid != nil do delete(z.collision_grid)
	free(z)
}

// Convert an RGB_F (0..1 floats) to a raylib Color (0..255 u8).
to_color :: proc "contextless" (c: RGB_F) -> rl.Color {
	return rl.Color {
		u8(math.clamp(c.r, 0, 1) * 255.0),
		u8(math.clamp(c.g, 0, 1) * 255.0),
		u8(math.clamp(c.b, 0, 1) * 255.0),
		255,
	}
}
