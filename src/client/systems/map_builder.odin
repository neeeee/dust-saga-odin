package systems

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import rlgl "vendor:raylib/rlgl"
import rl "vendor:raylib"

// Loads a zone's map JSON (src/client/assets/maps/<zoneId>.json) into a
// Zone_Definition and provides helpers to render the static world and to detect
// teleport-pad entry (mirrors MapBuilder.checkTeleport in the TS client).

MAPS_DIR :: "assets/maps"

// Load `assets/maps/<zone_id>.json`. Returns a freshly-allocated, parsed
// Zone_Definition (loaded=false on any failure). Caller owns it; every string
// field is a heap clone (zone_destroy frees them).
load_zone_map :: proc(zone_id: string) -> ^Zone_Definition {
	z := zone_init()

	// fmt.tprintf allocates via context.temp_allocator — never delete() it.
	path := fmt.tprintf("%s/%s.json", MAPS_DIR, zone_id)

	data, err := os.read_entire_file_from_path(path, allocator = context.allocator)
	if err != nil {
		// Fall back to a procedural flat zone so the client still runs.
		z.loaded = false
		z.id, _ = strings.clone(zone_id)
		z.name, _ = strings.clone("Unknown Zone")
		z.ground = {
			color            = {0.35, 0.55, 0.25},
			size             = 120,
			height_variation = 0,
		}
		z.fog = {
			color   = {0.7, 0.85, 0.95},
			density = 0.003,
		}
		z.player_spawn = {0, 0, 0}
		return z
	}
	defer delete(data)

	root_v, perr := json.parse(data)
	if perr != .None {
		z.loaded = false
		z.id, _ = strings.clone(zone_id)
		return z
	}
	// The parse tree is heap-backed (json.parse clones every key/string with
	// context.allocator); all extraction below copies out via get_string_owned,
	// so the tree can be released when this scope ends.
	defer json.destroy_value(root_v)
	root := obj_of(root_v)
	if is_null(root_v) {
		z.loaded = false
		return z
	}

	z.id = get_string_owned(root, "id", zone_id)
	z.name = get_string_owned(root, "name")

	ground := get_object(root, "ground")
	z.ground.color = rgb_from(get_object(ground, "color"))
	z.ground.size = get_f32(ground, "size", 120)
	z.ground.height_variation = get_f32(ground, "heightVariation")

	fog := get_object(root, "fog")
	z.fog.color = rgb_from(get_object(fog, "color"))
	z.fog.density = get_f32(fog, "density", 0.003)

	z.player_spawn = vec3_from(root, "playerSpawn")

	z.terrain = load_terrain_model(get_object(root, "source"))
	if z.terrain != nil {
		m := &z.terrain.model
		z.terrain_spheres = make([][4]f32, m.meshCount)
		for i in 0..<int(m.meshCount) {
			box := rl.GetMeshBoundingBox(m.meshes[i])
			center := (box.min + box.max) * 0.5
			radius := 0.5 * math.sqrt(
				(box.max.x - box.min.x) * (box.max.x - box.min.x) +
				(box.max.y - box.min.y) * (box.max.y - box.min.y) +
				(box.max.z - box.min.z) * (box.max.z - box.min.z))
			z.terrain_spheres[i] = {center.x, center.y, center.z, radius}
		}
	}

	parse_objects(z, get_array(root, "objects"))
	parse_structures(z, get_array(root, "structures"))
	parse_teleporters(z, get_array(root, "teleporters"))
	parse_lights(z, get_array(root, "lights"))

	build_collision_grid(z)

	z.loaded = true
	return z
}

rgb_from :: proc(o: JSON_Object) -> RGB_F {
	if is_null(json.Value(o)) do return {0.5, 0.5, 0.5}
	return {get_f32(o, "r", 0.5), get_f32(o, "g", 0.5), get_f32(o, "b", 0.5)}
}

// Pandora map JSONs point at their whole-area terrain bake via
// source.terrain_glb ("pandora_export_out/map/map_D01_01.glb"); the exported
// file itself is copied next to the JSONs as assets/maps/<basename>. Returns a
// cache-acquired model (caller releases via zone_destroy) or nil. Zones
// without the key — the older procedural maps — just get the fallback plane.
load_terrain_model :: proc(source: JSON_Object) -> ^Model_Entry {
	if is_null(json.Value(source)) do return nil
	glb := get_string(source, "terrain_glb", "")
	if len(glb) == 0 do return nil

	basename := glb
	if i := strings.last_index_byte(basename, '/'); i >= 0 do basename = basename[i + 1:]
	if i := strings.last_index_byte(basename, '\\'); i >= 0 do basename = basename[i + 1:]
	if !strings.has_suffix(basename, ".glb") do return nil

	path := fmt.tprintf("%s/%s", MAPS_DIR, basename)
	entry := assets_model_acquire(path)
	if entry != nil {
		// glTF MASK materials (foliage/grass/road decals) need a fragment
		// discard the default shader lacks; swapping the shader on all
		// materials is safe — opaque textures never fall under the cutoff.
		sh := terrain_shader_get()
		for i in 0..<int(entry.model.materialCount) {
			entry.model.materials[i].shader = sh
		}
	}
	return entry
}

parse_objects :: proc(z: ^Zone_Definition, arr: json.Array) {
	if arr == nil do return

	for item in arr {
		obj, ok := item.(json.Object)
		if !ok do continue

		o := Map_Object {
			otype    = get_string_owned(obj, "type", ""),
			position = vec3_from(obj, "position"),
			scale    = get_f32(obj, "scale", 1.0),
			model    = get_string_owned(obj, "model", ""),
		}
		append(&z.objects, o)
	}
}

parse_structures :: proc(z: ^Zone_Definition, arr: JSON_Array) {
	dyn := as_dyn(arr)
	for i in 0 ..< len(dyn) {
		o := obj_of(dyn[i])
		s := Map_Structure {
			otype    = get_string_owned(o, "type"),
			position = vec3_from(o, "position"),
		}
		sz := get_object(o, "size")
		s.size_w = get_f32(sz, "w", 1)
		s.size_h = get_f32(sz, "h", 1)
		s.size_d = get_f32(sz, "d", 1)
		s.color = rgb_from(get_object(o, "color"))
		if has_field(o, "wallsColor") {
			s.walls_color = rgb_from(get_object(o, "wallsColor"))
			s.roof_color = rgb_from(get_object(o, "roofColor"))
			s.has_roof = true
		}
		append(&z.structures, s)
	}
}

parse_teleporters :: proc(z: ^Zone_Definition, arr: json.Array) {
	if arr == nil do return

	for item in arr {
		obj, ok := item.(json.Object)
		if !ok do continue

		t := Teleporter {
			id           = get_string_owned(obj, "id", ""),
			position     = vec3_from(obj, "position"),
			target_zone  = get_string_owned(obj, "targetZone", ""),
			target_spawn = get_string_owned(obj, "targetSpawn", ""),
			radius       = get_f32(obj, "radius", 2.0),
			label        = get_string_owned(obj, "label", ""),
		}
		append(&z.teleporters, t)
	}
}

parse_lights :: proc(z: ^Zone_Definition, arr: JSON_Array) {
	dyn := as_dyn(arr)
	for i in 0 ..< len(dyn) {
		o := obj_of(dyn[i])
		append(
			&z.lights,
			Map_Light {
				otype = get_string_owned(o, "type"),
				position = vec3_from(o, "position"),
				intensity = get_f32(o, "intensity", 0.5),
				range = get_f32(o, "range", 10),
				color = rgb_from(get_object(o, "color")),
			},
		)
	}
}

// ── static world rendering ────────────────────────────────────────────────
//
// Drawn inside the gameplay BeginMode3D block. Everything is procedural
// primitives (per the "primitives first, GLB later" plan).

render_zone :: proc(z: ^Zone_Definition) {
	if z == nil do return

	// Ground plane, for the procedural zones and the Unknown-Zone fallback.
	// Not drawn under a terrain bake: the bakes reach tens of meters below
	// y=0 (beaches, trenches), so a plane there slices straight through the
	// model. Field maps' inter-tile gaps show the clear color instead.
	gnd_color := to_color(z.ground.color)
	if z.terrain == nil {
		rl.DrawPlane({0, 0, 0}, {z.ground.size, z.ground.size}, gnd_color)
	}

	// Whole-area terrain bake, if this zone has one. Drawn mesh-by-mesh with
	// frustum culling — these models flatten to thousands of meshes and the
	// plain DrawModel would issue every one of them every frame.
	if z.terrain != nil {
		draw_terrain_culled(z.terrain.model, z.terrain_spheres)
	}

	// Structures (platforms / fences / houses) as boxes.
	for s in z.structures {
		center := rl.Vector3{s.position.x, s.position.y + s.size_h * 0.5, s.position.z}
		dims := rl.Vector3{s.size_w, s.size_h, s.size_d}
		col := to_color(s.color)
		if s.has_roof do col = to_color(s.walls_color)
		rl.DrawCubeV(center, dims, col)
		rl.DrawCubeWiresV(center, dims, rl.BLACK)
		if s.has_roof {
			roof_center := rl.Vector3{s.position.x, s.position.y + s.size_h + 0.4, s.position.z}
			rl.DrawCubeV(
				roof_center,
				{s.size_w * 1.1, 0.8, s.size_d * 1.1},
				to_color(s.roof_color),
			)
		}
	}

	// Objects (trees / rocks) as procedural shapes.
	for o in z.objects {
		draw_map_object(o)
	}

	// Teleport pads: translucent glowing discs on the ground.
	for t in z.teleporters {
		base := rl.Vector3{t.position.x, 0.0, t.position.z}
		top := rl.Vector3{t.position.x, 0.08, t.position.z}
		rl.DrawCylinderEx(base, top, t.radius, t.radius, 16, rl.Color{120, 200, 255, 120})
		rl.DrawCylinderWiresEx(base, top, t.radius, t.radius, 16, rl.Color{180, 220, 255, 220})
	}
}

// Frustum planes as (nx, ny, nz, d), normalized. Extracted from the active
// proj*view matrix (Gribb–Hartmann) — must be called inside BeginMode3D,
// where rlgl's internal matrices are the camera's. Raylib stores m<col*4+row>,
// so mathematical row k is m[k], m[4+k], m[8+k], m[12+k].
frustum_planes :: proc() -> [6][4]f32 {
	vp := rlgl.GetMatrixProjection() * rlgl.GetMatrixModelview()
	r0 := [4]f32{vp[0, 0], vp[0, 1], vp[0, 2], vp[0, 3]}
	r1 := [4]f32{vp[1, 0], vp[1, 1], vp[1, 2], vp[1, 3]}
	r2 := [4]f32{vp[2, 0], vp[2, 1], vp[2, 2], vp[2, 3]}
	r3 := [4]f32{vp[3, 0], vp[3, 1], vp[3, 2], vp[3, 3]}
	return {
		normalize4(add4(r3, r0)), // left
		normalize4(sub4(r3, r0)), // right
		normalize4(add4(r3, r1)), // bottom
		normalize4(sub4(r3, r1)), // top
		normalize4(add4(r3, r2)), // near
		normalize4(sub4(r3, r2)), // far
	}
}

add4 :: proc "contextless" (a, b: [4]f32) -> [4]f32 {
	return {a[0] + b[0], a[1] + b[1], a[2] + b[2], a[3] + b[3]}
}

sub4 :: proc "contextless" (a, b: [4]f32) -> [4]f32 {
	return {a[0] - b[0], a[1] - b[1], a[2] - b[2], a[3] - b[3]}
}

normalize4 :: proc "contextless" (p: [4]f32) -> [4]f32 {
	l := math.sqrt(p[0] * p[0] + p[1] * p[1] + p[2] * p[2])
	if l <= 0 do return p
	return {p[0] / l, p[1] / l, p[2] / l, p[3] / l}
}

// Draw each terrain mesh whose bounding sphere crosses the camera frustum.
// Meshes already sit in world space (the glTF loader bakes node transforms).
draw_terrain_culled :: proc(model: rl.Model, spheres: [][4]f32) {
	if model.meshCount == 0 do return
	if len(spheres) < int(model.meshCount) do return

	planes := frustum_planes()
	ident := rl.Matrix(1)
	for i in 0..<int(model.meshCount) {
		s := spheres[i]
		visible := true
		for p in planes {
			if p[0] * s[0] + p[1] * s[1] + p[2] * s[2] + p[3] < -s[3] {
				visible = false
				break
			}
		}
		if !visible do continue
		rl.DrawMesh(model.meshes[i], model.materials[model.meshMaterial[i]], ident)
	}
}

draw_map_object :: proc(o: Map_Object) {
	switch o.otype {
	case "tree":
		// trunk
		rl.DrawCylinder(
			o.position,
			0.15 * o.scale,
			0.2 * o.scale,
			2.0 * o.scale,
			6,
			rl.Color{90, 60, 35, 255},
		)
		// foliage
		foliage_y := o.position.y + 2.0 * o.scale
		rl.DrawSphere(
			{o.position.x, foliage_y + 0.6 * o.scale, o.position.z},
			1.2 * o.scale,
			rl.Color{40, 110, 50, 255},
		)
		rl.DrawSphere(
			{o.position.x, foliage_y + 1.4 * o.scale, o.position.z},
			0.9 * o.scale,
			rl.Color{55, 130, 60, 255},
		)
	case "rock":
		rl.DrawSphere(o.position, 0.6 * o.scale, rl.Color{130, 130, 135, 255})
	case "bush":
		rl.DrawSphere(o.position, 0.5 * o.scale, rl.Color{50, 120, 55, 255})
	case:
		rl.DrawCube(o.position, 0.5 * o.scale, 0.5 * o.scale, 0.5 * o.scale, rl.MAGENTA)
	}
}

// ── teleport detection ────────────────────────────────────────────────────

// If the player is standing inside a teleport pad, return its index; else -1.
// Cooldown handling is the caller's responsibility (mirrors the TS 3s cooldown).
check_teleport :: proc(z: ^Zone_Definition, player_pos: rl.Vector3) -> int {
	if z == nil do return -1
	// for [dynamic], the first loop var is the value, the second is the index.
	for t, i in z.teleporters {
		dx := t.position.x - player_pos.x
		dz := t.position.z - player_pos.z
		if dx * dx + dz * dz <= t.radius * t.radius {
			return i
		}
	}
	return -1
}
