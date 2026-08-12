package systems

import "core:encoding/json"
import "core:fmt"
import "core:os"
import rl "vendor:raylib"

// Loads a zone's map JSON (src/client/assets/maps/<zoneId>.json) into a
// Zone_Definition and provides helpers to render the static world and to detect
// teleport-pad entry (mirrors MapBuilder.checkTeleport in the TS client).

MAPS_DIR :: "assets/maps"

// Load `assets/maps/<zone_id>.json`. Returns a freshly-allocated, parsed
// Zone_Definition (loaded=false on any failure). Caller owns it.
load_zone_map :: proc(zone_id: string) -> ^Zone_Definition {
	z := zone_init()
	z.id = zone_id

	// fmt.tprintf allocates via context.temp_allocator — never delete() it.
	path := fmt.tprintf("%s/%s.json", MAPS_DIR, zone_id)

	data, err := os.read_entire_file_from_path(path, allocator = context.allocator)
	if err != nil {
		// Fall back to a procedural flat zone so the client still runs.
		z.loaded = false
		z.name = "Unknown Zone"
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
		return z
	}
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

	// Ground plane.
	gnd_color := to_color(z.ground.color)
	rl.DrawPlane({0, 0, 0}, {z.ground.size, z.ground.size}, gnd_color)

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
