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
	loaded:       bool, // parsed successfully from disk

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
	z.loaded = false
	return z
}

// Free the zone. Only the containers we make()'d are freed; the string fields
// (id/name/label/model/...) are non-owning views into either json.parse buffers
// (freed separately) or string literals, so we never delete them.
zone_destroy :: proc(z: ^Zone_Definition) {
	if z == nil do return
	if z.objects != nil do delete(z.objects)
	if z.structures != nil do delete(z.structures)
	if z.teleporters != nil do delete(z.teleporters)
	if z.lights != nil do delete(z.lights)
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
