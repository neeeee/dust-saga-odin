package systems

import "core:encoding/json"
import "core:fmt"
import "core:c"
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

	terrain_name: string
	source := get_object(root, "source")
	z.terrain = load_terrain_model(source, &terrain_name)
	z.collision_model = load_collision_model(
		get_string(source, "collision", ""),
		terrain_name,
	)
	z.ground_model = load_ground_model(terrain_name)
	z.decor_model = load_decor_model(terrain_name)
	layout: ^GLB_Terrain_Layout
	if z.terrain != nil && len(terrain_name) > 0 {
		z.terrain_alpha_modes, z.terrain_alpha_cutoffs, layout =
			glb_material_alpha(fmt.tprintf("%s/%s", MAPS_DIR, terrain_name))
	}
	if z.terrain != nil && layout != nil {
		// Every bake ships BOTH the detailed FM_* chip terrain and the
		// coarse default_ground heightmap for the same cells; both at full
		// opacity they slice through each other (doubled/hovering ground,
		// tan wedges mid-slope). The original engine only shows the default
		// ground where NO chip is placed — drop the covered cells before the
		// bounding spheres are built.
		grid := get_object(root, "grid")
		terrain_mask_default_ground(
			&z.terrain.model,
			layout,
			get_f32(grid, "chip_size", 0) * 0.01,
		)
	}
	if layout != nil {
		delete(layout.chip_meshes)
		free(layout)
	}
	if terrain_name != "" do delete(terrain_name)
	if z.terrain != nil {
		m := &z.terrain.model
		z.terrain_spheres = make([][4]f32, m.meshCount)
		for i in 0..<int(m.meshCount) {
			// The default_ground mask can leave an empty mesh (every cell
			// chipped): a zero-volume sphere so the frustum cull skips it —
			// GetMeshBoundingBox of an empty mesh would return infinities.
			if m.meshes[i].vertexCount <= 0 {
				z.terrain_spheres[i] = {0, 0, 0, 0}
				continue
			}
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
	parse_colliders(z, get_array(root, "colliders"))
	parse_instances(z, get_array(root, "instances"), get_array(root, "assets"))

	// Rasterize the terrain GLB into the collision/elevation heightfield
	// (no-op without a GLB), then derive the A* collision grid from it.
	terrain_heightfield_build(z)
	build_collision_grid(z)

	// Lighting environment (original env_settings) + static shadow bake —
	// after the terrain model and spheres exist.
	z.lighting = lighting_parse_environment(root)
	lighting_apply(z)

	// Skydome textures from source.sky (dungeons reference a rock texture
	// instead; the derived name simply fails to load there).
	sky_load_zone(z, get_string(source, "sky", ""))

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
// cache-acquired model (caller releases via zone_destroy) or nil, plus the
// basename so the collision GLB can be derived from the same name. Zones
// without the key — the older procedural maps — just get the fallback plane.
load_terrain_model :: proc(source: JSON_Object, basename: ^string) -> ^Model_Entry {
	if is_null(json.Value(source)) do return nil
	glb := get_string(source, "terrain_glb", "")
	if len(glb) == 0 do return nil

	name := glb
	if i := strings.last_index_byte(name, '/'); i >= 0 do name = name[i + 1:]
	if i := strings.last_index_byte(name, '\\'); i >= 0 do name = name[i + 1:]
	if !strings.has_suffix(name, ".glb") do return nil

	basename^ = strings.clone(name)

	path := fmt.tprintf("%s/%s", MAPS_DIR, name)
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

// The area's original collision proxies as a GLB. Preferred name: the JSON's
// own source.collision ("D01/D01_01_a_hit.dxg") — variant areas name their
// own proxy set, which the terrain-name derivation can't reach. Fallback:
// derive map_<terrain>_hit.glb from the terrain GLB basename for zones whose
// JSON lacks the field. nil when neither file exists; the zone then relies
// on the JSON colliders + instance footprints for blocking.
load_collision_model :: proc(collision_src, terrain_basename: string) -> ^Model_Entry {
	name := ""
	if len(collision_src) > 0 {
		s := collision_src
		if i := strings.last_index_byte(s, '/'); i >= 0 do s = s[i + 1:]
		if i := strings.last_index_byte(s, '\\'); i >= 0 do s = s[i + 1:]
		if strings.has_suffix(s, ".dxg") do s = s[:len(s) - 4]
		if len(s) > 0 do name = fmt.tprintf("map_%s.glb", s)
	}
	if len(name) == 0 && strings.has_suffix(terrain_basename, ".glb") {
		name = fmt.tprintf("%s_hit.glb", terrain_basename[:len(terrain_basename) - 4])
	}
	if len(name) == 0 do return nil
	path := fmt.tprintf("%s/%s", MAPS_DIR, name)
	return assets_model_acquire(path)
}

// The area's terrain-only GLB (chips + fill, no props): map_<terrain>_ground
// .glb next to the visual bake. Loaded purely for the heightfield build —
// never rendered. nil when the file doesn't exist; the heightfield then
// falls back to the legacy shape classifier on the visual bake.
load_ground_model :: proc(basename: string) -> ^Model_Entry {
	if len(basename) == 0 || !strings.has_suffix(basename, ".glb") do return nil
	path := fmt.tprintf("%s/%s_ground.glb", MAPS_DIR, basename[:len(basename) - 4])
	return assets_model_acquire(path)
}

// The area's foliage GLB (plants/grass/flowers — the ground export's
// <name>_decor.glb sidecar). Its triangles are excluded from structure
// walls: crossed billboard quads must never block movement or shots.
// nil when absent — no foliage exclusion.
load_decor_model :: proc(basename: string) -> ^Model_Entry {
	if len(basename) == 0 || !strings.has_suffix(basename, ".glb") do return nil
	path := fmt.tprintf("%s/%s_decor.glb", MAPS_DIR, basename[:len(basename) - 4])
	return assets_model_acquire(path)
}

// Terrain models already through terrain_mask_default_ground. Model entries
// are cache-shared (several zones reference one bake), and a second pass
// would misalign the cell grid: the first pass shrinks the default_ground
// mesh's bounding box, moving the grid origin. Keyed by the model pointer,
// process-lifetime.
dg_masked_models := map[rawptr]bool{}

// Drops default_ground cells that carry a terrain chip, in place on the
// loaded model.
//
// The bakes ship TWO copies of the terrain: the FM_* chip tiles (the
// detailed surface the player sees) and default_ground — the coarse base
// heightmap (one quad per map grid cell, e.g. 71×71 verts at 24u for
// map_F05_01) the ORIGINAL engine only renders on cells with no chip
// placed. The exporter bakes both at full opacity, so the coarse surface
// crosses the detailed one: tan wedges poking through slopes, the chip
// layer reading as hovering/doubled, and open seams wherever the two
// disagree (all F/D/E bakes; the T-town bakes only escape because their
// terrain is flat enough for both surfaces to coincide).
//
// The mask rebuilds the default_ground mesh keeping exactly the triangles
// whose grid cell no FM_* chip footprint touches — same rule as the
// original engine's chip-over-default rendering. cell_m is the map grid
// cell size in meters (JSON grid.chip_size / 100); no-op without it or
// without a default_ground/chips in the layout.
terrain_mask_default_ground :: proc(
	model: ^rl.Model,
	layout: ^GLB_Terrain_Layout,
	cell_m: f32,
) {
	if model == nil || layout == nil do return
	if dg_masked_models[model] do return
	dg := layout.default_ground_mesh
	if dg < 0 || dg >= int(model.meshCount) || cell_m <= 0 do return
	if len(layout.chip_meshes) == 0 do return

	src := &model.meshes[dg]
	n := int(src.vertexCount)
	if n == 0 || src.vertices == nil do return
	box := rl.GetMeshBoundingBox(src^)

	inv := 1.0 / cell_m
	cols := int(math.floor((box.max.x - box.min.x) * inv + 0.5)) + 1
	rows := int(math.floor((box.max.z - box.min.z) * inv + 0.5)) + 1
	if cols <= 0 || rows <= 0 || cols > 8192 || rows > 8192 do return

	// Chip footprints mark covered cells (a chip tile is grid-cell sized, so
	// its XZ bounding box lands on the cell it occupies).
	covered := make([]bool, cols * rows)
	defer delete(covered)
	for ci in layout.chip_meshes {
		if ci < 0 || ci >= int(model.meshCount) || ci == dg do continue
		b := rl.GetMeshBoundingBox(model.meshes[ci])
		gx0 := int(math.floor((b.min.x - box.min.x) * inv))
		gx1 := int(math.floor((b.max.x - box.min.x) * inv))
		gz0 := int(math.floor((b.min.z - box.min.z) * inv))
		gz1 := int(math.floor((b.max.z - box.min.z) * inv))
		if gx0 < 0 do gx0 = 0
		if gz0 < 0 do gz0 = 0
		if gx1 > cols - 1 do gx1 = cols - 1
		if gz1 > rows - 1 do gz1 = rows - 1
		for gz in gz0 ..= gz1 {
			for gx in gx0 ..= gx1 {
				covered[gz * cols + gx] = true
			}
		}
	}

	// Pass 1: a triangle survives only when none of its vertices sits in a
	// covered cell (grid triangles never span cells, so this is per-cell).
	tri_n := int(src.triangleCount)
	vertex_kept := make([]bool, n)
	kept_tri := 0
	for t in 0 ..< tri_n {
		i0, i1, i2 := t * 3, t * 3 + 1, t * 3 + 2
		if src.indices != nil {
			i0 = int(src.indices[t * 3])
			i1 = int(src.indices[t * 3 + 1])
			i2 = int(src.indices[t * 3 + 2])
		}
		if i0 >= n || i1 >= n || i2 >= n do continue
		blocked := false
		vv := [3]int{i0, i1, i2}
		for i in vv {
			x := src.vertices[i * 3]
			z := src.vertices[i * 3 + 2]
			gx := int(math.floor((x - box.min.x) * inv))
			gz := int(math.floor((z - box.min.z) * inv))
			if gx < 0 do gx = 0
			if gz < 0 do gz = 0
			if gx > cols - 1 do gx = cols - 1
			if gz > rows - 1 do gz = rows - 1
			if covered[gz * cols + gx] {
				blocked = true
				break
			}
		}
		if !blocked {
			kept_tri += 1
			vertex_kept[i0] = true
			vertex_kept[i1] = true
			vertex_kept[i2] = true
		}
	}
	if kept_tri == tri_n {
		dg_masked_models[model] = true
		return // nothing covered (or no triangles) — leave the mesh alone
	}

	// Pass 2: compact the kept vertices and rebuild every attribute array.
	// rl.MemAlloc matches the allocator raylib's UnloadModel/UnloadMesh
	// frees these arrays with (the mesh lives inside the cached model).
	remap := make([]int, n)
	new_n := 0
	for i in 0 ..< n {
		if vertex_kept[i] {
			remap[i] = new_n
			new_n += 1
		} else {
			remap[i] = -1
		}
	}

	nm := rl.Mesh{vertexCount = c.int(new_n), triangleCount = c.int(kept_tri)}
	if new_n > 0 {
		if src.vertices != nil {
			buf := ([^]f32)(rl.MemAlloc(c.uint(new_n * 3 * 4)))
			for i in 0 ..< n {
				if remap[i] < 0 do continue
				for k in 0 ..< 3 {
					buf[remap[i] * 3 + k] = src.vertices[i * 3 + k]
				}
			}
			nm.vertices = buf
		}
		if src.texcoords != nil {
			buf := ([^]f32)(rl.MemAlloc(c.uint(new_n * 2 * 4)))
			for i in 0 ..< n {
				if remap[i] < 0 do continue
				for k in 0 ..< 2 {
					buf[remap[i] * 2 + k] = src.texcoords[i * 2 + k]
				}
			}
			nm.texcoords = buf
		}
		if src.normals != nil {
			buf := ([^]f32)(rl.MemAlloc(c.uint(new_n * 3 * 4)))
			for i in 0 ..< n {
				if remap[i] < 0 do continue
				for k in 0 ..< 3 {
					buf[remap[i] * 3 + k] = src.normals[i * 3 + k]
				}
			}
			nm.normals = buf
		}
		if src.tangents != nil {
			buf := ([^]f32)(rl.MemAlloc(c.uint(new_n * 4 * 4)))
			for i in 0 ..< n {
				if remap[i] < 0 do continue
				for k in 0 ..< 4 {
					buf[remap[i] * 4 + k] = src.tangents[i * 4 + k]
				}
			}
			nm.tangents = buf
		}
		if src.colors != nil {
			buf := ([^]u8)(rl.MemAlloc(c.uint(new_n * 4)))
			for i in 0 ..< n {
				if remap[i] < 0 do continue
				for k in 0 ..< 4 {
					buf[remap[i] * 4 + k] = src.colors[i * 4 + k]
				}
			}
			nm.colors = buf
		}
		if kept_tri > 0 && src.indices != nil {
			buf := ([^]u16)(rl.MemAlloc(c.uint(kept_tri * 3 * 2)))
			w := 0
			for t in 0 ..< tri_n {
				i0, i1, i2 := t * 3, t * 3 + 1, t * 3 + 2
				i0 = int(src.indices[t * 3])
				i1 = int(src.indices[t * 3 + 1])
				i2 = int(src.indices[t * 3 + 2])
				if i0 >= n || i1 >= n || i2 >= n do continue
				if !vertex_kept[i0] || !vertex_kept[i1] || !vertex_kept[i2] do continue
				buf[w] = u16(remap[i0])
				buf[w + 1] = u16(remap[i1])
				buf[w + 2] = u16(remap[i2])
				w += 3
			}
			nm.indices = buf
		}
		rl.UploadMesh(&nm, false)
	}
	delete(remap)
	delete(vertex_kept)

	rl.UnloadMesh(src^) // frees the old CPU arrays and GPU buffers
	model.meshes[dg] = nm
	dg_masked_models[model] = true
}

glb_keys_has :: proc(keys: [dynamic][]u8, key: []u8) -> bool {
	for k in keys {
		if len(k) == len(key) {
			same := true
			for i in 0 ..< len(k) {
				if k[i] != key[i] {
					same = false
					break
				}
			}
			if same do return true
		}
	}
	return false
}

// chunk[start] is '"'; returns the index just past the closing quote.
glb_scan_string :: proc "contextless" (chunk: []u8, start: int) -> int {
	i := start + 1
	for i < len(chunk) {
		c := chunk[i]
		if c == '\\' {
			i += 2
			continue
		}
		if c == '"' {
			return i + 1
		}
		i += 1
	}
	return i
}

// End of a bare token (number / true / false / null / punctuation).
glb_prim_end :: proc "contextless" (chunk: []u8, start: int) -> int {
	i := start
	for i < len(chunk) {
		c := chunk[i]
		if c == ',' || c == ':' || c == '}' || c == ']' ||
		c == ' ' || c == '\t' || c == '\n' || c == '\r' {
			break
		}
		i += 1
	}
	return i
}

glb_is_ws :: proc "contextless" (c: u8) -> bool {
	return c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

// Renames duplicate object keys so core:json's strict parser (hard error on
// duplicates) accepts the bake exports: the Pandora exporter writes
// {"alphaMode":"MASK","alphaMode":"BLEND"} on its fx materials. Every later
// duplicate key is rewritten to "_dupN_<key>" (N = 2..) — value bytes pass
// through untouched, so structure and commas stay exactly as exported.
// Keys seen per object reference into `chunk`, which outlives the parse.
glb_json_dedupe :: proc(chunk: []u8) -> []u8 {
	Key_Frame :: struct {
		is_obj: bool,
		keys:   [dynamic][]u8,
	}

	out := make([dynamic]u8, 0, len(chunk))
	frames := make([dynamic]Key_Frame)
	defer {
		for f in frames {
			if f.keys != nil do delete(f.keys)
		}
		delete(frames)
	}

	i := 0
	for i < len(chunk) {
		c := chunk[i]
		if c == '{' || c == '[' {
			append(&frames, Key_Frame{is_obj = c == '{'})
			append(&out, c)
			i += 1
		} else if c == '}' || c == ']' {
			f := pop(&frames)
			if f.keys != nil do delete(f.keys)
			append(&out, c)
			i += 1
		} else if c == '"' {
			end := glb_scan_string(chunk, i)
			j := end
			for j < len(chunk) && glb_is_ws(chunk[j]) {
				j += 1
			}
			key_bytes := chunk[i:end]
			if j < len(chunk) && chunk[j] == ':' && len(frames) > 0 && frames[len(frames) - 1].is_obj {
				f := &frames[len(frames) - 1]
				if glb_keys_has(f.keys, key_bytes) {
					n := 2
					for {
						prefix := fmt.tprintf("_dup%d_", n)
						cand := make([]u8, len(key_bytes) + len(prefix))
						copy(cand, key_bytes[:1]) // opening quote
						copy(cand[1:], prefix)    // inserted inside the quotes
						copy(cand[1 + len(prefix):], key_bytes[1:])
						if !glb_keys_has(f.keys, cand) {
							for b in cand do append(&out, b)
							append(&f.keys, cand)
							break
						}
						delete(cand)
						n += 1
					}
				} else {
					for b in key_bytes do append(&out, b)
					append(&f.keys, key_bytes)
				}
			} else {
				for b in key_bytes do append(&out, b)
			}
			i = end
		} else if glb_is_ws(c) {
			append(&out, c)
			i += 1
		} else if c == ',' || c == ':' {
			append(&out, c)
			i += 1
		} else {
			end := glb_prim_end(chunk, i)
			for k in i ..< end do append(&out, chunk[k])
			i = end
		}
	}
	return out[:]
}

// Field lookups with keep-last semantics over the deduped chunk: the
// exporter's later value is the one the original engine honors
// ({"alphaMode":"MASK","alphaMode":"BLEND"} renders as BLEND).
glb_last_string :: proc(o: JSON_Object, key: string) -> string {
	for n := 8; n >= 2; n -= 1 {
		k := fmt.tprintf("_dup%d_%s", n, key)
		if has_field(o, k) {
			return get_string(o, k, "")
		}
	}
	return get_string(o, key, "")
}

glb_last_f32 :: proc(o: JSON_Object, key: string, default: f32) -> f32 {
	for n := 8; n >= 2; n -= 1 {
		k := fmt.tprintf("_dup%d_%s", n, key)
		if has_field(o, k) {
			return get_f32(o, k, default)
		}
	}
	return get_f32(o, key, default)
}

glb_u32_le :: proc "contextless" (data: []u8, off: int) -> u32 {
	return u32(data[off]) |
		u32(data[off + 1]) << 8 |
		u32(data[off + 2]) << 16 |
		u32(data[off + 3]) << 24
}

// The GLB's binary chunk payload, or nil when absent.
glb_bin_chunk :: proc "contextless" (data: []u8) -> []u8 {
	total := int(glb_u32_le(data, 8))
	off := 12
	for off + 8 <= len(data) && off + 8 <= total {
		clen := int(glb_u32_le(data, off))
		ctype := glb_u32_le(data, off + 4)
		if off + 8 + clen > len(data) do break
		if ctype == 0x004E4942 { // 'BIN'
			return data[off + 8 : off + 8 + clen]
		}
		off += 8 + clen
	}
	return nil
}

// True when any texel survives an alpha>=128 cut. False means the texture is
// a fully-transparent helper (bounding-box props) — every material on it
// renders nothing in the original client.
glb_image_has_opaque :: proc(image: rl.Image) -> bool {
	if image.data == nil || image.width <= 0 || image.height <= 0 do return true
	if image.format != .UNCOMPRESSED_R8G8B8A8 do return true
	pixels := ([^]u8)(image.data)[0 : int(image.width) * int(image.height) * 4]
	for i := 3; i < len(pixels); i += 4 {
		if pixels[i] >= 128 do return true
	}
	return false
}

// UV-space bounding box of the alpha>=128 texels (u0,v0,u1,v1, top-left
// origin like glTF UVs). ok=false when the image is missing, not RGBA8, or
// has no opaque texel at all.
glb_image_opaque_bbox :: proc(image: rl.Image) -> (bbox: [4]f32, ok: bool) {
	if image.data == nil || image.width <= 0 || image.height <= 0 do return {}, false
	if image.format != .UNCOMPRESSED_R8G8B8A8 do return {}, false
	w, h := int(image.width), int(image.height)
	pixels := ([^]u8)(image.data)[0 : w * h * 4]
	min_x, min_y := w, h
	max_x, max_y := -1, -1
	for y in 0 ..< h {
		for x in 0 ..< w {
			if pixels[(y*w + x)*4 + 3] >= 128 {
				if x < min_x do min_x = x
				if y < min_y do min_y = y
				if x > max_x do max_x = x
				if y > max_y do max_y = y
			}
		}
	}
	if max_x < 0 do return {}, false
	return {
		f32(min_x) / f32(w), f32(min_y) / f32(h),
		f32(max_x) / f32(w), f32(max_y) / f32(h),
	}, true
}

// True when the alpha channel is SOFT: a non-binary gradient (> 6% of
// texels between full transparent and full opaque). A real glTF MASK cutout
// is binary (0 or 255 with a thin AA fringe); soft alpha over complete RGB
// is an export artifact painted onto building-facade textures, and a
// spec-honest cutout of it dissolves the whole facade.
glb_image_alpha_soft :: proc(image: rl.Image) -> bool {
	if image.data == nil || image.width <= 0 || image.height <= 0 do return false
	if image.format != .UNCOMPRESSED_R8G8B8A8 do return false
	pixels := ([^]u8)(image.data)[0 : int(image.width) * int(image.height) * 4]
	soft: int = 0
	total: int = 0
	for i := 3; i < len(pixels); i += 4 {
		a := pixels[i]
		total += 1
		if a >= 8 && a <= 247 do soft += 1
	}
	return total > 0 && f32(soft) / f32(total) > 0.06
}

// Mesh-index extras gathered while parsing the GLB, used by
// terrain_mask_default_ground. Indices are RAYLIB mesh indices (the same
// flatten order the model loader produces), not glTF node/mesh indices.
GLB_Terrain_Layout :: struct {
	default_ground_mesh: int,     // raylib mesh index of the default_ground
	                               // primitive, -1 when the bake has none
	chip_meshes:         [dynamic]int, // raylib mesh indices of FM_* terrain
	                               // chip primitives (the detailed tile layer)
}

// UV bounding box (u0,v0,u1,v1) of a f32 VEC2 accessor, from its declared
// min/max when present, else by scanning the buffer data. ok=false when the
// accessor is missing, not VEC2/f32, or its bytes are out of range — callers
// treat that conservatively.
glb_uv_footprint :: proc(
	bin: []u8,
	views, accessors: [dynamic]json.Value,
	acc_i: int,
) -> (u0, v0, u1, v1: f32, ok: bool) {
	if acc_i < 0 || acc_i >= len(accessors) do return 0, 0, 0, 0, false
	a := obj_of(accessors[acc_i])
	if get_int(a, "componentType", 0) != 5126 do return 0, 0, 0, 0, false

	// Declared min/max (exporters list it for POSITION, often for UVs too).
	mn := as_dyn(get_array(a, "min"))
	mx := as_dyn(get_array(a, "max"))
	if len(mn) >= 2 && len(mx) >= 2 {
		u0, v0 = f32(number_of(mn[0])), f32(number_of(mn[1]))
		u1, v1 = f32(number_of(mx[0])), f32(number_of(mx[1]))
		if u0 > u1 { u0, u1 = u1, u0 }
		if v0 > v1 { v0, v1 = v1, v0 }
		return u0, v0, u1, v1, true
	}

	bv := get_int(a, "bufferView", -1)
	if bv < 0 || bv >= len(views) do return 0, 0, 0, 0, false
	v := obj_of(views[bv])
	off := get_int(v, "byteOffset", 0) + get_int(a, "byteOffset", 0)
	count := get_int(a, "count", 0)
	stride := get_int(v, "byteStride", 0)
	if stride < 8 { stride = 8 } // tight VEC2 f32
	if count <= 0 || off < 0 || off + count * stride > len(bin) {
		return 0, 0, 0, 0, false
	}
	u0, v0 = 1e9, 1e9
	u1, v1 = -1e9, -1e9
	for k in 0 ..< count {
		o := off + k * stride
		u := transmute(f32)(glb_u32_le(bin, o))
		vv := transmute(f32)(glb_u32_le(bin, o + 4))
		if u < u0 { u0 = u }
		if u > u1 { u1 = u }
		if vv < v0 { v0 = vv }
		if vv > v1 { v1 = vv }
	}
	return u0, v0, u1, v1, true
}

// Reads a GLB's JSON chunk and extracts the glTF alpha state for every
// material, plus which raylib meshes are the bake's default_ground and
// terrain chips (see GLB_Terrain_Layout).
//
// INDEXING: the returned arrays are indexed by RAYLIB MATERIAL SLOT, i.e.
// model.meshMaterial[i] may be used directly. The shipped raylib.dll loads
// one material slot per glTF material plus slot 0 (default white), and
// stores meshMaterial[mesh] = gltf_material_index + 1 (verified against the
// dll: map_T01_01.glb → 1694 meshes over 433 shared slots, values repeat
// across meshes; see tools/matprobe.odin). The previous scheme keyed a
// per-primitive sequence by that same slot value — on the T bakes the two
// sequences aligned by luck (materials indexed in first-use order with long
// same-mode runs), but e.g. map_F05_01.glb's first meshes alternate slots
// [1,2,1,2,…], swapping the alpha state of every mesh after them: grass
// cards went OPAQUE (solid green quads), foliage MASK/BLEND shuffled.
//
// Per glTF material: alphaMode (as Alpha_Mode) and alphaCutoff, plus three
// derived classes from the texture content:
//   OPAQUE material on a no-opaque-texel texture -> HIDDEN (bbox helper
//     props; the original client never shows them).
//   OPAQUE material on a texture also used by MASK materials -> MASK (the
//     bake's duplicated foliage cards: tree leaves ship a MASK material plus
//     an OPAQUE twin whose transparent texels' RGB is flat olive) — UNLESS
//     the material's UVs never touch the texture's opaque island, which
//     marks a SOLID part sharing the cutout sheet (tree trunks: real RGB
//     under alpha 0, meant to render opaque).
//   MASK material on a SOFT-alpha texture (non-binary gradient — export
//     garbage over complete RGB) -> OPAQUE (the bake's building facades:
//     ~98% of a facade's texels fall below its own cutoff, dissolving the
//     whole front; the original client ignores the channel).
// nil arrays on any failure (no file, not a GLB, no materials): the draw
// loop then leaves the shader on its OPAQUE default.
glb_material_alpha :: proc(
	path: string,
) -> (modes: []u8, cutoffs: []f32, layout: ^GLB_Terrain_Layout) {
	data, err := os.read_entire_file_from_path(path, allocator = context.allocator)
	if err != nil {
		return
	}
	defer delete(data)

	// GLB layout: 12-byte header ("glTF", version, length), then chunks of
	// (u32 length, u32 type, payload) — chunk 0 is always the JSON, the BIN
	// chunk holds the embedded images.
	if len(data) < 20 || data[0] != 'g' || data[1] != 'l' || data[2] != 'T' || data[3] != 'F' {
		return
	}
	json_len := int(glb_u32_le(data, 12))
	if json_len < 4 || 20 + json_len > len(data) {
		return
	}
	bin := glb_bin_chunk(data)

	chunk := glb_json_dedupe(data[20 : 20 + json_len])
	defer delete(chunk)
	root_v, perr := json.parse(chunk)
	if perr != .None {
		return
	}
	defer json.destroy_value(root_v)
	root := obj_of(root_v)
	if is_null(root_v) {
		return
	}

	// Decode each image once and flag two alpha-channel properties: no
	// opaque texel at all (invisible bbox-helper textures) and SOFT alpha
	// (a non-binary gradient — export garbage over valid RGB). Shared
	// images are common (47 textures per bake), hence the source-keyed cache.
	src_hidden := map[int]bool{}
	src_soft := map[int]bool{}
	src_bbox := map[int][4]f32{}
	src_bbox_ok := map[int]bool{}
	textures := as_dyn(get_array(root, "textures"))
	images := as_dyn(get_array(root, "images"))
	views := as_dyn(get_array(root, "bufferViews"))
	tex_hidden := make(map[int]bool)
	tex_soft := make(map[int]bool)
	tex_opaque := make(map[int][4]f32)
	tex_opaque_ok := make(map[int]bool)
	defer delete(tex_hidden)
	defer delete(tex_soft)
	defer delete(tex_opaque)
	defer delete(tex_opaque_ok)
	for ti in 0 ..< len(textures) {
		src := get_int(obj_of(textures[ti]), "source", -1)
		if src < 0 || src >= len(images) do continue
		if h, ok := src_hidden[src]; ok {
			tex_hidden[ti] = h
			tex_soft[ti] = src_soft[src]
			tex_opaque[ti] = src_bbox[src]
			tex_opaque_ok[ti] = src_bbox_ok[src]
			continue
		}
		hidden := false
		soft := false
		bbox: [4]f32
		bbox_ok := false
		img := obj_of(images[src])
		bv := get_int(img, "bufferView", -1)
		mime := get_string(img, "mimeType", "")
		ext: string = ".png"
		if mime == "image/jpeg" do ext = ".jpg"
		else if mime != "image/png" do bv = -1
		if bv >= 0 && bv < len(views) {
			v := obj_of(views[bv])
			off := get_int(v, "byteOffset", 0)
			ln := get_int(v, "byteLength", 0)
			if ln > 0 && off >= 0 && off + ln <= len(bin) {
				payload := bin[off : off + ln]
				decoded := rl.LoadImageFromMemory(assets_cstring(ext), raw_data(payload), c.int(ln))
				hidden, soft = !glb_image_has_opaque(decoded), glb_image_alpha_soft(decoded)
				bbox, bbox_ok = glb_image_opaque_bbox(decoded)
				rl.UnloadImage(decoded)
			}
		}
		src_hidden[src] = hidden
		src_soft[src] = soft
		src_bbox[src] = bbox
		src_bbox_ok[src] = bbox_ok
		tex_hidden[ti] = hidden
		tex_soft[ti] = soft
		tex_opaque[ti] = bbox
		tex_opaque_ok[ti] = bbox_ok
	}

	dyn := as_dyn(get_array(root, "materials"))
	if len(dyn) == 0 {
		return
	}

	// Per-GLTF-MATERIAL classification (Alpha_Mode + derived HIDDEN).
	mat_modes := make([]u8, len(dyn))
	mat_cutoffs := make([]f32, len(dyn))
	defer delete(mat_modes)
	defer delete(mat_cutoffs)
	for i in 0 ..< len(dyn) {
		o := obj_of(dyn[i])
		mat_modes[i] = u8(Alpha_Mode.OPAQUE)
		mat_cutoffs[i] = 0.5
		switch glb_last_string(o, "alphaMode") {
		case "MASK":
			mat_modes[i] = u8(Alpha_Mode.MASK)
		case "BLEND":
			mat_modes[i] = u8(Alpha_Mode.BLEND)
		}
		mat_cutoffs[i] = glb_last_f32(o, "alphaCutoff", 0.5)
	}

	// Textures also used by MASK materials: OPAQUE materials on them are the
	// bake's duplicated foliage cards (trees ship a MASK leaf material plus
	// an OPAQUE twin on the same texture). The original asset is a cutout —
	// and the exporter filled the transparent texels' RGB with flat olive —
	// so rendering the twin opaque painted solid blobs over the canopy.
	// Render those twins as MASK (their own cutoff; binary alpha either way).
	tex_has_mask := make(map[int]bool)
	mat_tex := make([]int, len(dyn))
	defer delete(tex_has_mask)
	defer delete(mat_tex)
	for i in 0 ..< len(dyn) {
		o := obj_of(dyn[i])
		pbr := obj_of(json.Value(get_object(o, "pbrMetallicRoughness")))
		bct := get_object(pbr, "baseColorTexture")
		mat_tex[i] = get_int(bct, "index", -1)
		if mat_modes[i] == u8(Alpha_Mode.MASK) {
			tex_has_mask[mat_tex[i]] = true
		}
	}

	twin_pending := make(map[int]bool) // material -> tentatively MASK, see below
	defer delete(twin_pending)
	for i in 0 ..< len(dyn) {
		if mat_modes[i] != u8(Alpha_Mode.OPAQUE) do continue
		o := obj_of(dyn[i])
		pbr := obj_of(json.Value(get_object(o, "pbrMetallicRoughness")))
		bct := get_object(pbr, "baseColorTexture")
		tex := get_int(bct, "index", -1)
		if h, ok := tex_hidden[tex]; ok && h {
			mat_modes[i] = u8(Alpha_Mode.HIDDEN)
		} else if tex_has_mask[tex] {
			mat_modes[i] = u8(Alpha_Mode.MASK)
			twin_pending[i] = true
		}
	}

	// MASK materials on SOFT-alpha textures: the alpha channel is export
	// garbage painted over complete RGB (the bake's building facades —
	// ~98% of a facade's texels fall below its own 0.392 cutoff, dissolving
	// the whole front). The original client ignores the channel, so force
	// those materials OPAQUE (alpha ignored). Real cutouts (foliage, cloth)
	// stay binary and keep their cutout.
	for i in 0 ..< len(dyn) {
		if mat_modes[i] != u8(Alpha_Mode.MASK) do continue
		o := obj_of(dyn[i])
		pbr := obj_of(json.Value(get_object(o, "pbrMetallicRoughness")))
		bct := get_object(pbr, "baseColorTexture")
		tex := get_int(bct, "index", -1)
		if soft, ok := tex_soft[tex]; ok && soft {
			mat_modes[i] = u8(Alpha_Mode.OPAQUE)
		}
	}

	// Layout pass: find the default_ground mesh and the FM_* terrain chips,
	// and — while visiting every primitive anyway — record whether each
	// provisionally-MASKed twin material's UVs touch its texture's opaque
	// island (see the twin revert below). raylib flattens ALL nodes in ARRAY
	// ORDER (its GLTF loader ignores scenes; non-triangle primitives are
	// skipped), emitting one mesh per triangle primitive — walk the same
	// order to keep indices in sync.
	nodes := as_dyn(get_array(root, "nodes"))
	meshes := as_dyn(get_array(root, "meshes"))
	accessors := as_dyn(get_array(root, "accessors"))
	if len(nodes) == 0 || len(meshes) == 0 {
		return modes, cutoffs, nil
	}
	layout = new(GLB_Terrain_Layout)
	layout.default_ground_mesh = -1
	twin_touches_opaque := make(map[int]bool) // default false = untouched
	defer delete(twin_touches_opaque)
	mesh_i := 0
	for ni in 0 ..< len(nodes) {
		n := obj_of(nodes[ni])
		mi := get_int(n, "mesh", -1)
		if mi < 0 || mi >= len(meshes) {
			continue
		}
		mesh := obj_of(meshes[mi])
		name := get_string(mesh, "name", "")
		for p in as_dyn(get_array(mesh, "primitives")) {
			po := obj_of(p)
			// glTF mode 4 (or absent) = triangles; anything else never
			// becomes a raylib mesh, so it must not consume an index.
			if get_int(po, "mode", 4) != 4 {
				continue
			}
			if name == "default_ground" && layout.default_ground_mesh < 0 {
				layout.default_ground_mesh = mesh_i
			} else if len(name) >= 3 && name[0] == 'F' && name[1] == 'M' && name[2] == '_' {
				append(&layout.chip_meshes, mesh_i)
			}
			mat := get_int(po, "material", -1)
			if mat >= 0 && twin_pending[mat] {
				attrs := obj_of(json.Value(get_object(po, "attributes")))
				obb, obb_ok := tex_opaque[mat_tex[mat]], tex_opaque_ok[mat_tex[mat]]
				uv_ok: bool
				u0, v0, u1, v1: f32
				if obb_ok {
					u0, v0, u1, v1, uv_ok =
						glb_uv_footprint(bin, views, accessors, get_int(attrs, "TEXCOORD_0", -1))
				}
				// Conservative: unknown footprint or unknown island counts
				// as touching (keeps the historical twin->MASK behavior).
				// A DEGENERATE footprint (every vertex on one texel — the
				// pine canopy tiers of map_F05_01.glb sample (0,0), alpha 0)
				// also counts as touching: it is not a solid part UV-mapped
				// onto the sheet, and un-MASKing it paints the single
				// texel's color over the whole primitive (dark blocks).
				if !obb_ok || !uv_ok || (u0 == u1 && v0 == v1) ||
				(u0 <= obb[2] && u1 >= obb[0] && v0 <= obb[3] && v1 >= obb[1]) {
					twin_touches_opaque[mat] = true
				}
			}
			mesh_i += 1
		}
	}

	// Twin revert: an OPAQUE material on a MASK-shared texture whose every
	// primitive's UVs form a proper 2D rect lying OUTSIDE the texture's
	// opaque island is a SOLID part sharing the cutout sheet — e.g.
	// map_F05_01.glb's OM_00_hd_tree03* trunk prims, whose bark lives in
	// the sheet's transparent region with the real RGB under alpha 0.
	// Forcing those through the cutout discarded the whole trunk (invisible
	// trees); render them OPAQUE as the glTF says. Degenerate (single-texel)
	// footprints are excluded — see the visit loop above.
	for m, _ in twin_pending {
		if !twin_touches_opaque[m] {
			mat_modes[m] = u8(Alpha_Mode.OPAQUE)
		}
	}

	// Material-slot arrays: entry m+1 = glTF material m's classification,
	// entry 0 = raylib's default (white) material — always OPAQUE. This is
	// exactly what model.meshMaterial indexes (see proc comment).
	modes = make([]u8, len(dyn) + 1)
	cutoffs = make([]f32, len(dyn) + 1)
	modes[0] = u8(Alpha_Mode.OPAQUE)
	cutoffs[0] = 0.5
	for i in 0 ..< len(dyn) {
		modes[i + 1] = mat_modes[i]
		cutoffs[i + 1] = mat_cutoffs[i]
	}
	if layout.default_ground_mesh < 0 && len(layout.chip_meshes) == 0 {
		delete(layout.chip_meshes)
		free(layout)
		layout = nil
	}
	return modes, cutoffs, layout
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

// Manual collision boxes: [{position:{x,z}, size:{w,d}, label?}] — the
// viewer-authored "this object blocks" list. Footprint-only (y ignored);
// never rendered.
parse_colliders :: proc(z: ^Zone_Definition, arr: JSON_Array) {
	if arr == nil do return
	dyn := as_dyn(arr)
	for i in 0 ..< len(dyn) {
		o := obj_of(dyn[i])
		pos := vec3_from(o, "position")
		sz := get_object(o, "size")
		append(
			&z.colliders,
			Collider {
				x     = pos.x,
				z     = pos.z,
				w     = get_f32(sz, "w", 1),
				d     = get_f32(sz, "d", 1),
				label = get_string_owned(o, "label", ""),
			},
		)
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

// The Pandora manifests' `instances` list: every world object placed on the
// map, referencing `assets[id].vra` by index. Positions are engine
// centimeters — the bake's world units are position / 100. Each instance is
// resolved through instance_collision into a blocking footprint and/or a
// no-stand radius; ground chips (kind "terrain_chip") are skipped — they are
// the terrain itself, already in the heightfield.
parse_instances :: proc(z: ^Zone_Definition, arr, assets_arr: JSON_Array) {
	if arr == nil || assets_arr == nil do return

	// asset id -> lowercased vra basename ("oz_26_mi_fence02a") + manifest kind
	names := map[int]string{}
	kinds := map[int]string{}
	defer {
		for _, v in names do delete(v)
		for _, v in kinds do delete(v)
		delete(names)
		delete(kinds)
	}
	assets_dyn := as_dyn(assets_arr)
	for i in 0 ..< len(assets_dyn) {
		a := obj_of(assets_dyn[i])
		kind := get_string(a, "kind", "")
		if kind == "terrain_chip" do continue
		name := get_string(a, "vra", "")
		if len(name) == 0 do continue
		if idx := strings.last_index_byte(name, '\\'); idx >= 0 do name = name[idx + 1:]
		if idx := strings.last_index_byte(name, '/'); idx >= 0 do name = name[idx + 1:]
		if strings.has_suffix(name, ".vra") do name = name[:len(name) - 4]
		lower := make([]u8, len(name))
		for c in 0 ..< len(name) {
			ch := name[c]
			if ch >= 'A' && ch <= 'Z' do ch = ch + ('a' - 'A')
			lower[c] = ch
		}
		id := get_int(a, "id", -1)
		names[id] = string(lower)
		kl := make([]u8, len(kind))
		for c in 0 ..< len(kind) {
			ch := kind[c]
			if ch >= 'A' && ch <= 'Z' do ch = ch + ('a' - 'A')
			kl[c] = ch
		}
		kinds[id] = string(kl)
	}

	dyn := as_dyn(arr)
	for i in 0 ..< len(dyn) {
		o := obj_of(dyn[i])
		pos := as_dyn(get_array(o, "position"))
		if len(pos) < 3 do continue
		scale_arr := as_dyn(get_array(o, "scale"))
		scale := f32(1)
		if len(scale_arr) >= 3 {
			scale = f32(max(max(number_of(scale_arr[0]), number_of(scale_arr[1])), number_of(scale_arr[2])))
		}
		if scale <= 0 do scale = 1
		quat := as_dyn(get_array(o, "rotation_quat_xyzw"))
		yaw := f32(0)
		if len(quat) >= 4 {
			yaw = quat_to_yaw({
				f32(number_of(quat[0])),
				f32(number_of(quat[1])),
				f32(number_of(quat[2])),
				f32(number_of(quat[3])),
			})
		}
		asset := get_int(o, "asset", -1)
		inst := Map_Instance{
			x     = f32(number_of(pos[0])) * 0.01,
			z     = f32(number_of(pos[2])) * 0.01,
			yaw   = yaw,
			scale = scale,
		}
		if k, ok := kinds[asset]; ok {
			inst.kind, _ = strings.clone(k)
		}
		instance_collision(names[asset], inst.kind, &inst)
		append(&z.instances, inst)
	}
}

// ── static world rendering ────────────────────────────────────────────────
//
// Drawn inside the gameplay BeginMode3D block. Everything is procedural
// primitives (per the "primitives first, GLB later" plan).

render_zone :: proc(z: ^Zone_Definition) {
	if z == nil do return

	// Per-frame lighting state: derive the camera position from the active
	// modelview (works under any BeginMode3D camera) and push it to both
	// lit programs — everything else is static per zone.
	mv := rlgl.GetMatrixModelview()
	inv := rl.MatrixInvert(mv)
	cam := rl.Vector3{inv[3, 0], inv[3, 1], inv[3, 2]}
	lighting_set_camera(cam)

	// Sky backdrop first: no depth test/write, so everything drawn later
	// composes over it and terrain fades into the matching fog color.
	sky_draw(z, cam)

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
		draw_terrain_culled(
			z.terrain.model,
			z.terrain_spheres,
			z.terrain_alpha_modes,
			z.terrain_alpha_cutoffs,
		)
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

	// Teleport pads: translucent glowing discs on the ground. Lifted onto
	// the terrain surface when the zone has a heightfield.
	for t in z.teleporters {
		pad_y := terrain_y_at(z, t.position.x, t.position.z)
		base := rl.Vector3{t.position.x, pad_y, t.position.z}
		top := rl.Vector3{t.position.x, pad_y + 0.08, t.position.z}
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

// Debug switch: draw every terrain mesh, skipping frustum culling. Set by
// diagnostic tools to separate culling bugs from shader/material bugs.
terrain_culling_disabled: bool

// Debug: when range_active, only meshes in [range_lo, range_hi) draw
// (culling bypassed); when force_active, all meshes cull normally EXCEPT
// those in the range, which always draw — both let tools attribute rendered
// pixels to meshes. Probe-only; the game leaves them false.
range_active: bool = false
force_active: bool = false
range_lo, range_hi: int = 0, 0
terrain_debug_flat: bool = false

// Draw each terrain mesh whose bounding sphere crosses the camera frustum.
// Meshes already sit in world space (the glTF loader bakes node transforms).
// modes/cutoffs carry the per-material glTF alpha state (see
// glb_material_alpha); the cutout shader is bound for the whole pass and its
// uniforms are set per visible mesh.
//
// NOTE: the shader MUST be bound (BeginShaderMode) before the per-mesh
// rl.SetShaderValue calls - raylib submits uniforms to the CURRENTLY bound
// program, and without an explicit bind they land on whatever drew last
// (the previous frame's tail), leaving meshes with stale discard state
// (building fronts vanishing depending on draw history).
draw_terrain_culled :: proc(model: rl.Model, spheres: [][4]f32, modes: []u8, cutoffs: []f32) {
	if model.meshCount == 0 do return
	if len(spheres) < int(model.meshCount) do return

	planes := frustum_planes()
	ident := rl.Matrix(1)
	sh := terrain_shader_get()
	for i in 0..<int(model.meshCount) {
		s := spheres[i]
		// Degenerate guard: some bakes contain point-sized helper/corrupt
		// meshes (zero-volume AABB) whose GPU data renders as huge garbage
		// triangles at camera-dependent positions — the original client
		// never shows them. Skip unconditionally.
		if s[3] <= 0.01 do continue
		visible := true
		if range_active {
			visible = i >= range_lo && i < range_hi
		} else if !terrain_culling_disabled {
			for p in planes {
				if p[0] * s[0] + p[1] * s[1] + p[2] * s[2] + p[3] < -s[3] {
					visible = false
					break
				}
			}
		}
		if force_active && i >= range_lo && i < range_hi do visible = true
		if !visible do continue
		mat := int(model.meshMaterial[i])
		// Bind the shader PER MESH: rl.SetShaderValue submits uniforms to the
		// CURRENTLY bound program, and without an explicit re-bind here some
		// meshes render with stale alpha-discard state (building fronts
		// vanishing depending on what drew before them).
		rl.BeginShaderMode(sh)
		terrain_shader_set_material(sh, mat, modes, cutoffs)
		if terrain_debug_flat && terrain_loc_dbg_flat >= 0 {
			// flat + tint by alpha mode: OPAQUE=red, MASK=green, BLEND=blue,
			// HIDDEN=black — shows which discard state each fragment has.
			flat: c.int = 1
			mode_tints := [4][3]f32{
				{1, 0, 0},
				{0, 1, 0},
				{0, 0, 1},
				{0, 0, 0},
			}
			tint: [3]f32 = {0.5, 0.5, 0.5}
			if mat >= 0 && mat < len(modes) {
				tint = mode_tints[int(modes[mat])]
			}
			rl.SetShaderValue(sh, terrain_loc_dbg_flat, &flat, .INT)
			rl.SetShaderValue(sh, terrain_loc_dbg_tint, &tint, .VEC3)
		} else if terrain_loc_dbg_flat >= 0 {
			flat: c.int = 0
			rl.SetShaderValue(sh, terrain_loc_dbg_flat, &flat, .INT)
		}
		rl.DrawMesh(model.meshes[i], model.materials[model.meshMaterial[i]], ident)
		rl.EndShaderMode()
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
