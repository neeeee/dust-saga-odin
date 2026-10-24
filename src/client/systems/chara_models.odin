package systems

// Character model layer: loads assets/chara/chara_XXX.glb plus its sibling
// chara_XXX_creator.json (face/hair variant node names, hair color textures)
// and builds drawable subsets: body meshes + ONE face + ONE hair, so character
// creation can preview any face/hair combination (the picks are independent —
// face variant 3 with hair variant 5 is fine).
//
// Subsets are shallow rl.Model values: the meshes/materials arrays are fresh,
// but the Mesh/Material structs inside are copies sharing the GPU buffers,
// bones and bind pose with the cached base model — nothing is re-uploaded.
// Hair color works by cloning the hair meshes' material and swapping the
// albedo texture for chara_XXX_hairtex/g{group}_c{color}.png.
//
// All selectors are INDEX-based (UI picks 0..count-1 into the creator.json
// arrays); the node-name plumbing stays internal.

import "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"


// Character model per race + sex. The numeric codes on disk are race/gender
// pairs: 11/12 human m/f, 21/22 elf m/f, 31 dwarf, 42 myrine, 51 enkidu,
// 63 lapin. has_sex tells the UI whether to offer a male/female choice.
chara_model_for_race :: proc(race_id: string, female: bool) -> (id: string, has_sex: bool) {
	switch race_id {
	case "human":  return (female ? "012" : "011"), true
	case "elf":    return (female ? "022" : "021"), true
	case "dwarf":  return "031", false
	case "myrine": return "042", false
	case "enkidu": return "051", false
	case "lapin":  return "063", false
	case:          return "011", false
	}
}

Chara_Hair_Opt :: struct {
	node:  string, // glb node name, heap-owned
	group: int,    // hair texture group (g{group}_c{color}.png)
}

Chara_Model :: struct {
	id:            string,             // heap-owned, e.g. "011"
	glb_path:      string,             // heap-owned
	faces:         [dynamic]string,    // resolved face node names
	face_meshes:   [dynamic][]int,     // parallel: raylib mesh indices per face
	hairs:         [dynamic]Chara_Hair_Opt,
	hair_meshes:   [dynamic][]int,     // parallel: raylib mesh indices per hair
	hair_colors:   [dynamic]int,       // color ids in UI order (0..5 typically)
	hair_tex:      map[int][dynamic]string, // color id -> one texture path per group
	default_color: int,

	entry:       ^Model_Entry, // GPU model (assets cache, refcounted)
	mesh_map_ok: bool,         // false => node->mesh mapping unusable, draw all
	is_variant:  []bool,       // per raylib mesh: belongs to a face/hair node?
	mesh_region: []u8,         // per raylib mesh: Body_Region of the default-
	                           // outfit piece it holds (0 = none/face/hair)
	bounds:      rl.BoundingBox, // bind-pose spatial extent (camera framing)
	anims:       [^]rl.ModelAnimation,
	anim_count:  int,
	clips:       map[string]int, // animation code ("0001") -> anim index
	idle_anim:   int,          // index of the idle clip (..._0001), -1 = none
	walk_anim:   int,          // ..._0015
	run_anim:    int,          // ..._0018
	refs:        int,
}

chara_cache: map[string]^Chara_Model

// Frees anything still cached. Call before assets_destroy at shutdown.
chara_shutdown :: proc() {
	for key, cm in chara_cache {
		cm.refs = 0
		chara_model_free(cm)
		delete_key(&chara_cache, key)
		delete(key)
	}
	delete(chara_cache)
}

// Acquires (loads on first use) the character model for `id` ("011".."063").
// Caller must chara_model_release. Returns nil on failure.
chara_model_acquire :: proc(id: string) -> ^Chara_Model {
	if cm, ok := chara_cache[id]; ok {
		cm.refs += 1
		return cm
	}
	if !asset_ready do return nil

	cm := chara_model_load(id)
	if cm == nil do return nil

	key := strings.clone(id)
	chara_cache[key] = cm
	cm.refs = 1
	return cm
}

// Drops one reference; unloaded at zero.
chara_model_release :: proc(cm: ^Chara_Model) {
	if cm == nil do return
	cm.refs -= 1
	if cm.refs > 0 do return
	for key, v in chara_cache {
		if v == cm {
			delete_key(&chara_cache, key)
			delete(key)
			break
		}
	}
	chara_model_free(cm)
}

chara_model_load :: proc(id: string) -> ^Chara_Model {
	def_json_path := fmt.tprintf("assets/chara/chara_%s_creator.json", id)
	glb_path := fmt.tprintf("assets/chara/chara_%s.glb", id)

	data, err := os.read_entire_file_from_path(def_json_path, allocator = context.allocator)
	if err != nil {
		rl.TraceLog(.WARNING, "chara: missing creator definition %s", assets_cstring(def_json_path))
		return nil
	}
	defer delete(data)

	root, parsed := json_parse(data)
	if !parsed {
		rl.TraceLog(.WARNING, "chara: unparsable creator definition %s", assets_cstring(def_json_path))
		return nil
	}
	defer json.destroy_value(root)
	root_obj := obj_of(root)

	entry := assets_model_acquire(glb_path)
	if entry == nil do return nil

	cm := new(Chara_Model)
	cm.id = strings.clone(id)
	cm.glb_path = strings.clone(glb_path)
	cm.entry = entry
	cm.hair_tex = make(map[int][dynamic]string)
	cm.default_color = get_int(root_obj, "defaultHairColor", 0)

	// Hair colors and their per-group textures (JSON keys are string ids).
	colors_dyn := as_dyn(get_array(root_obj, "hairColors"))
	for i in 0..<len(colors_dyn) {
		append(&cm.hair_colors, int_of(colors_dyn[i]))
	}
	tex_obj := get_object(root_obj, "hairTextures")
	for key, v in as_map(tex_obj) {
		color_id := 0
		for ch in key { // single-var string iteration yields the bytes
			if ch >= '0' && ch <= '9' do color_id = color_id * 10 + int(ch - '0')
		}
		paths_dyn := as_dyn(array_of(v))
		paths := make([dynamic]string, 0, len(paths_dyn))
		for i in 0..<len(paths_dyn) {
			append(&paths, strings.clone(string_of(paths_dyn[i])))
		}
		cm.hair_tex[color_id] = paths
	}

	// Node name -> raylib mesh indices; validity gates all variant picking.
	mesh_map, map_ok := gltf_read_mesh_map(glb_path)
	mesh_count := entry.model.meshCount
	cm.mesh_map_ok = map_ok && mesh_map.total == int(mesh_count)
	if map_ok && !cm.mesh_map_ok {
		rl.TraceLog(.WARNING,
			"chara: mesh map mismatch for %s (%d primitives vs %d raylib meshes) — variant picking disabled",
			assets_cstring(id), mesh_map.total, mesh_count)
	}

	if cm.mesh_map_ok {
		is_variant := make([]bool, mesh_count)

		// Body-region map: the default outfit ships as region pieces
		// (body_02 top+arms, body_03 leggings, body_04 hip band, body_05
		// feet — same convention on all 8 races; enkidu splits each across
		// two nodes, hence prefix matching). Equipment REPLACES these
		// (see chara_avatar_sync_armor).
		cm.mesh_region = make([]u8, mesh_count) // Body_Region.None == 0
		for name, indices in mesh_map.by_node {
			region := chara_body_region_of(name)
			if region == .None do continue
			for mi in indices {
				if mi >= 0 && int(mi) < int(mesh_count) {
					cm.mesh_region[mi] = u8(region)
				}
			}
		}

		// Resolve faces: keep only options whose node maps to real meshes, so
		// cm.faces and cm.face_meshes stay paired.
		faces_dyn := as_dyn(get_array(root_obj, "faces"))
		for i in 0..<len(faces_dyn) {
			name := string_of(faces_dyn[i])
			indices, found := mesh_map.by_node[name]
			if !found || len(indices) == 0 do continue
			append(&cm.faces, strings.clone(name))
			append(&cm.face_meshes, chara_indices_clone(indices))
			for mi in indices do is_variant[mi] = true
		}

		// Hairs: {node, group}, same resolve-and-pair.
		hairs_dyn := as_dyn(get_array(root_obj, "hairs"))
		for i in 0..<len(hairs_dyn) {
			h := obj_of(hairs_dyn[i])
			name := get_string(h, "node")
			indices, found := mesh_map.by_node[name]
			if !found || len(indices) == 0 do continue
			append(&cm.hairs, Chara_Hair_Opt{
				node  = strings.clone(name),
				group = get_int(h, "group", 0),
			})
			append(&cm.hair_meshes, chara_indices_clone(indices))
			for mi in indices do is_variant[mi] = true
		}

		cm.is_variant = is_variant
	}

	// The map's index slices were cloned above; the map itself is done.
	gltf_mesh_map_free(&mesh_map)

	// Camera framing extent. GetModelBoundingBox reads raw mesh vertices,
	// which for these skinned glbs does NOT match the assembled render; the
	// skeleton's bind-pose bone positions are the reliable frame. Log both —
	// a mismatch here was the too-close preview camera.
	cm.bounds = chara_skeleton_bounds(entry.model)
	vertex_bounds := rl.GetModelBoundingBox(entry.model)
	rl.TraceLog(.INFO,
		"chara: %s bounds skeleton=(%.1f,%.1f,%.1f)-(%.1f,%.1f,%.1f) vertices=(%.1f,%.1f,%.1f)-(%.1f,%.1f,%.1f)",
		assets_cstring(id),
		cm.bounds.min.x, cm.bounds.min.y, cm.bounds.min.z,
		cm.bounds.max.x, cm.bounds.max.y, cm.bounds.max.z,
		vertex_bounds.min.x, vertex_bounds.min.y, vertex_bounds.min.z,
		vertex_bounds.max.x, vertex_bounds.max.y, vertex_bounds.max.z)

	// Animations: glTF clips; the idle stance is the ..._0001 clip.
	anim_count: c.int
	anims := rl.LoadModelAnimations(assets_cstring(glb_path), &anim_count)
	cm.anims = anims
	cm.anim_count = int(anim_count)
	cm.idle_anim = -1
	cm.walk_anim = -1
	cm.run_anim = -1
	cm.clips = make(map[string]int, cm.anim_count)
	for i in 0..<cm.anim_count {
		name := chara_anim_name(&anims[i])
		code := chara_code_of(name)
		if len(code) > 0 {
			// chara_code_of returns a VIEW into the anim's name buffer —
			// map keys must own their memory (chara_model_free deletes them)
			if _, dup := cm.clips[code]; !dup do cm.clips[strings.clone(code)] = i
		}
		if cm.idle_anim < 0 && strings.ends_with(name, CLIP_CODE_IDLE) do cm.idle_anim = i
		if cm.walk_anim < 0 && strings.ends_with(name, CLIP_CODE_WALK) do cm.walk_anim = i
		if cm.run_anim < 0 && strings.ends_with(name, CLIP_CODE_RUN) do cm.run_anim = i
	}
	if cm.idle_anim < 0 && cm.anim_count > 0 do cm.idle_anim = 0
	chara_dump_animations(cm)

	rl.TraceLog(.INFO, "chara: %s ready (%d faces, %d hairs, %d colors, %d anims, idle %d)",
		assets_cstring(id), len(cm.faces), len(cm.hairs), len(cm.hair_colors),
		cm.anim_count, cm.idle_anim)
	return cm
}

// Animation clip name from the fixed 32-byte field (NUL-padded).
chara_anim_name :: proc(a: ^rl.ModelAnimation) -> string {
	for i in 0..<len(a.name) {
		if a.name[i] == 0 do return string(a.name[:i])
	}
	return string(a.name[:])
}

// Exact world-space bounds of `model` AS CURRENTLY POSED: skins every vertex
// by the base model's bone matrices (same linear-blend math the GPU runs),
// falling back to raw vertices where there is no skin data. Call after
// UpdateModelAnimation so the pose is current — bind-pose skeleton bounds are
// unreliable on these rigs (mixed up-axis conventions, stray weapon/cape
// bones), while this matches what is actually on screen.
chara_skin_bounds :: proc(cm: ^Chara_Model, model: ^rl.Model) -> rl.BoundingBox {
	bounds := rl.BoundingBox{
		min = {1e30, 1e30, 1e30},
		max = {-1e30, -1e30, -1e30},
	}
	bone_mats: [^]rl.Matrix
	if cm != nil && cm.entry != nil do bone_mats = cm.entry.model.boneMatrices

	for mi in 0..<int(model.meshCount) {
		mesh := &model.meshes[mi]
		n := int(mesh.vertexCount)
		if n <= 0 do continue

		if mesh.animVertices != nil {
			// CPU-skinned path: final positions already computed by raylib.
			for v in 0..<n {
				x := mesh.animVertices[v * 3]
				y := mesh.animVertices[v * 3 + 1]
				z := mesh.animVertices[v * 3 + 2]
				bounds.min.x = min(bounds.min.x, x)
				bounds.min.y = min(bounds.min.y, y)
				bounds.min.z = min(bounds.min.z, z)
				bounds.max.x = max(bounds.max.x, x)
				bounds.max.y = max(bounds.max.y, y)
				bounds.max.z = max(bounds.max.z, z)
			}
		} else if mesh.boneIndices != nil && mesh.boneWeights != nil && bone_mats != nil {
			for v in 0..<n {
				x := mesh.vertices[v * 3]
				y := mesh.vertices[v * 3 + 1]
				z := mesh.vertices[v * 3 + 2]
				ox, oy, oz: f32
				for k in 0..<4 {
					w := mesh.boneWeights[v * 4 + k]
					if w <= 0 do continue
					b := int(mesh.boneIndices[v * 4 + k])
					m := bone_mats[b]
					px := m[0, 0] * x + m[0, 1] * y + m[0, 2] * z + m[0, 3]
					py := m[1, 0] * x + m[1, 1] * y + m[1, 2] * z + m[1, 3]
					pz := m[2, 0] * x + m[2, 1] * y + m[2, 2] * z + m[2, 3]
					ox += w * px
					oy += w * py
					oz += w * pz
				}
				bounds.min.x = min(bounds.min.x, ox)
				bounds.min.y = min(bounds.min.y, oy)
				bounds.min.z = min(bounds.min.z, oz)
				bounds.max.x = max(bounds.max.x, ox)
				bounds.max.y = max(bounds.max.y, oy)
				bounds.max.z = max(bounds.max.z, oz)
			}
		} else if mesh.vertices != nil {
			for v in 0..<n {
				x := mesh.vertices[v * 3]
				y := mesh.vertices[v * 3 + 1]
				z := mesh.vertices[v * 3 + 2]
				bounds.min.x = min(bounds.min.x, x)
				bounds.min.y = min(bounds.min.y, y)
				bounds.min.z = min(bounds.min.z, z)
				bounds.max.x = max(bounds.max.x, x)
				bounds.max.y = max(bounds.max.y, y)
				bounds.max.z = max(bounds.max.z, z)
			}
		}
	}
	return bounds
}

// Spatial extent of the character in bind pose, from the skeleton (falls back
// to vertex bounds for non-skinned models).
chara_skeleton_bounds :: proc(model: rl.Model) -> rl.BoundingBox {
	if model.skeleton.boneCount <= 0 || model.skeleton.bindPose == nil {
		return rl.GetModelBoundingBox(model)
	}

	bone_count := int(model.skeleton.boneCount)
	bones := model.skeleton.bones
	pose := model.skeleton.bindPose

	worlds := make([]rl.Matrix, bone_count)
	defer delete(worlds)

	bounds := rl.BoundingBox{
		min = {1e30, 1e30, 1e30},
		max = {-1e30, -1e30, -1e30},
	}
	for i in 0..<bone_count {
		local := chara_pose_matrix(pose[i])
		parent := int(bones[i].parent)
		world := local
		if parent >= 0 && parent < i {
			world = worlds[parent] * local
		}
		worlds[i] = world
		bounds.min.x = min(bounds.min.x, world[0, 3])
		bounds.min.y = min(bounds.min.y, world[1, 3])
		bounds.min.z = min(bounds.min.z, world[2, 3])
		bounds.max.x = max(bounds.max.x, world[0, 3])
		bounds.max.y = max(bounds.max.y, world[1, 3])
		bounds.max.z = max(bounds.max.z, world[2, 3])
	}

	// Joints sit inside the body — pad for limb/armor extent.
	pad_x := (bounds.max.x - bounds.min.x) * 0.15 + 0.05
	pad_y := (bounds.max.y - bounds.min.y) * 0.05 + 0.05
	pad_z := (bounds.max.z - bounds.min.z) * 0.15 + 0.05
	bounds.min.x -= pad_x
	bounds.min.y -= pad_y
	bounds.min.z -= pad_z
	bounds.max.x += pad_x
	bounds.max.y += pad_y
	bounds.max.z += pad_z
	return bounds
}

// T*R*S matrix from a pose transforl. Native matrices use raylib layout:
// element [row, col] with memory row-major, so column c is [0,c],[1,c],[2,c].
chara_pose_matrix :: proc(t: rl.Transform) -> rl.Matrix {
	m := rl.QuaternionToMatrix(t.rotation)
	m[0, 0] *= t.scale.x
	m[1, 0] *= t.scale.x
	m[2, 0] *= t.scale.x
	m[0, 1] *= t.scale.y
	m[1, 1] *= t.scale.y
	m[2, 1] *= t.scale.y
	m[0, 2] *= t.scale.z
	m[1, 2] *= t.scale.z
	m[2, 2] *= t.scale.z
	m[0, 3] = t.translation.x
	m[1, 3] = t.translation.y
	m[2, 3] = t.translation.z
	return m
}

chara_indices_clone :: proc(indices: []int) -> []int {
	out := make([]int, len(indices))
	copy(out, indices)
	return out
}

chara_model_free :: proc(cm: ^Chara_Model) {
	for f in cm.faces do delete(f)
	delete(cm.faces)
	for m in cm.face_meshes do delete(m)
	delete(cm.face_meshes)
	for h in cm.hairs do delete(h.node)
	delete(cm.hairs)
	for m in cm.hair_meshes do delete(m)
	delete(cm.hair_meshes)
	delete(cm.hair_colors)
	for _, paths in cm.hair_tex {
		for p in paths do delete(p)
		delete(paths)
	}
	delete(cm.hair_tex)
	delete(cm.is_variant)
	delete(cm.mesh_region)
	// Keys are strings.clone'd at insertion (chara_code_of returns a view
	// into raylib's anim-name buffer — freeing that view corrupts the heap).
	for key in cm.clips {
		delete(key)
	}
	delete(cm.clips)
	delete(cm.glb_path)
	delete(cm.id)
	if cm.anims != nil {
		rl.UnloadModelAnimations(cm.anims, c.int(cm.anim_count))
	}
	assets_model_release(cm.entry)
	free(cm)
}

// ── subset building ────────────────────────────────────────────────────────

// A drawable model = body meshes + chosen face + chosen hair, with hair
// materials cloned for the chosen color. Free with chara_subset_free.
Chara_Subset :: struct {
	model:     rl.Model,
	base_mesh: [dynamic]int,          // per sub mesh: base model mesh index
	hair_maps: [dynamic][]rl.MaterialMap, // freshly allocated material maps
}

// Default-outfit regions a body mesh can cover, numbered to MATCH the EM
// part codes: equipment part 02 replaces body_02, 03→body_03, 04→body_04,
// 05→body_05 — each piece carries its own version of that region (the torso
// ships sleeved arms, the gloves ship hands, …), so equipping one hides the
// matching body mesh instead of drawing both (the shipped game swaps, not
// wraps — double arms under the torso's own sleeves read as clipping).
Body_Region :: enum u8 {
	None,
	Torso, // body_02: chest + arms
	Legs,  // body_03: leggings
	Hands, // body_04: hands + forearm bracers
	Feet,  // body_05: sandals/greaves
	Hair,  // CM_*_11_*: hair variants (helmets replace these, see sync_armor)
}

chara_body_region_of :: proc(name: string) -> Body_Region {
	switch {
	case strings.has_prefix(name, "body_02"): return .Torso
	case strings.has_prefix(name, "body_03"): return .Legs
	case strings.has_prefix(name, "body_04"): return .Hands
	case strings.has_prefix(name, "body_05"): return .Feet
	case strings.has_prefix(name, "CM_") && strings.contains(name, "_11_"):
		return .Hair // creator.json: _11_* are the hair style nodes
	}
	return .None
}

// Builds a shallow model sharing the base model's GPU data. face_i/hair_i are
// indices into cm.faces/cm.hairs; color_i indexes cm.hair_colors. Anything out
// of range (or a model without a valid mesh map) degrades to body-only / full
// model rather than failing.
chara_subset_build :: proc(cm: ^Chara_Model, face_i, hair_i, color_i: int) -> Chara_Subset {
	sub: Chara_Subset
	if cm == nil || cm.entry == nil do return sub
	base := &cm.entry.model

	face_indices: []int
	hair_indices: []int
	if cm.mesh_map_ok {
		if face_i >= 0 && face_i < len(cm.face_meshes) do face_indices = cm.face_meshes[face_i]
		if hair_i >= 0 && hair_i < len(cm.hair_meshes) do hair_indices = cm.hair_meshes[hair_i]
	}

	// Keep list: body first, then face, then hair (order is irrelevant for
	// drawing; body-first just makes the loop trivial).
	keep := make([dynamic]int, 0, base.meshCount)
	defer delete(keep)
	for i in 0..<base.meshCount {
		if len(cm.is_variant) == 0 || !cm.is_variant[i] do append(&keep, int(i))
	}
	for mi in face_indices do append(&keep, mi)
	for mi in hair_indices do append(&keep, mi)

	mesh_n := len(keep)
	hair_n := len(hair_indices)
	if mesh_n == 0 do return sub

	sub.model.meshes = make([^]rl.Mesh, mesh_n)
	sub.model.meshMaterial = make([^]c.int, mesh_n)
	for j in 0..<mesh_n {
		sub.model.meshes[j] = base.meshes[keep[j]]
		sub.model.meshMaterial[j] = base.meshMaterial[keep[j]]
		append(&sub.base_mesh, keep[j])
	}
	sub.model.meshCount = c.int(mesh_n)

	// Materials: copies of the base set (struct copies share texture ids —
	// never mutated) plus one clone per hair mesh for the color swap.
	mats_n := int(base.materialCount) + hair_n
	sub.model.materials = make([^]rl.Material, mats_n)
	for k in 0..<base.materialCount {
		sub.model.materials[k] = base.materials[k]
	}
	sub.model.materialCount = base.materialCount

	for j in 0..<mesh_n {
		mesh_index := keep[j]
		if hair_n == 0 || !chara_index_in(hair_indices, mesh_index) do continue
		if len(cm.is_variant) > 0 && !cm.is_variant[mesh_index] do continue

		src := sub.model.materials[sub.model.meshMaterial[j]]
		maps_copy := make([]rl.MaterialMap, rl.MAX_MATERIAL_MAPS)
		copy(maps_copy, src.maps[:rl.MAX_MATERIAL_MAPS])
		if tex := chara_hair_texture(cm, hair_i, color_i); tex.id > 0 {
			maps_copy[int(rl.MaterialMapIndex.ALBEDO)].texture = tex
		}
		new_mat := src
		new_mat.maps = transmute([^]rl.MaterialMap)raw_data(maps_copy)
		sub.model.materials[sub.model.materialCount] = new_mat
		sub.model.meshMaterial[j] = sub.model.materialCount
		sub.model.materialCount += 1
		append(&sub.hair_maps, maps_copy)
	}

	// Share animation state so DrawMesh skinning matches the base model.
	sub.model.transform = base.transform
	sub.model.skeleton = base.skeleton
	sub.model.currentPose = base.currentPose
	sub.model.boneMatrices = base.boneMatrices

	return sub
}

chara_subset_free :: proc(sub: ^Chara_Subset) {
	if sub.model.meshes != nil do free(sub.model.meshes)
	if sub.model.meshMaterial != nil do free(sub.model.meshMaterial)
	if sub.model.materials != nil do free(sub.model.materials)
	delete(sub.base_mesh)
	for m in sub.hair_maps do delete(m)
	delete(sub.hair_maps)
	sub.model = {}
}

// Albedo texture for (hair option, color index); invalid texture if absent.
// hairTextures is keyed by the hair's GROUP (style) and the array is indexed
// by color: hairTextures[group][color] = chara_XXX_hairtex/g{group}_c{color}.png
chara_hair_texture :: proc(cm: ^Chara_Model, hair_i, color_i: int) -> rl.Texture2D {
	if cm == nil do return {}
	if hair_i < 0 || hair_i >= len(cm.hairs) do return {}
	group := cm.hairs[hair_i].group
	paths, ok := cm.hair_tex[group]
	if !ok do return {}
	if color_i < 0 || color_i >= len(paths) do return {}
	// creator.json paths are relative to assets/chara/ (no prefix on disk).
	path := paths[color_i]
	if !strings.has_prefix(path, "assets/") {
		path = fmt.tprintf("assets/chara/%s", path)
	}
	return assets_texture(path)
}

chara_index_in :: proc(indices: []int, needle: int) -> bool {
	for v in indices {
		if v == needle do return true
	}
	return false
}


// ── in-game avatars ────────────────────────────────────────────────────────

// Movement clips. glTF clip names encode them: ..._0001 idle, ..._0015 walk,
// ..._0018 run.
Chara_Clip :: enum {
	IDLE,
	WALK,
	RUN,
}

// raylib bakes glTF clips to keyframes; playback rate tuned by eye.
CHARA_ANIM_FPS :: 60.0

// Cross-fade duration when the playing clip changes (swing → drawn idle,
// idle → walk, ...). Short enough to stay snappy, long enough to hide the cut.
CHARA_BLEND_TIME :: 0.25

ANIM_DUMP_PATH :: "chara_animations.txt"

// In-game characters stand at capsule-ish scale: 011 measures 1.80 posed
// units, which is the capsule height, so world scale is 1.0. Each race keeps
// its art height (lapin stays small, enkidu big).
AVATAR_HEIGHT     :: 1.8
CHARA_REF_HEIGHT  :: 1.80

// Appearance handed from character-select to gameplay for the local player.
Local_Appearance :: struct {
	model_id: string, // static constant from chara_model_for_race — no copy needed
	face_i:   int,
	hair_i:   int,
	color_i:  int,
}

// ── worn armor ─────────────────────────────────────────────────────────────
// Equipped armor renders like a normal MMO: each wearable item ships a glb
// per race (item/EM_<sid>_<part>_<race>.glb, part from items.odin). Torso/
// legs/gloves/boots/cloak pieces are skinned to the same 90-joint master
// skeleton as the characters (identical joint order, verified per race), so
// they play the avatar's current clip directly. Helmets are rigid single
// meshes, bone-attached to the head like the held weapon. Like weapons
// today, only the LOCAL player's armor is drawn — remote players don't
// broadcast equipment yet.
Chara_Armor_Layer :: enum u8 {
	HELMET,
	TORSO, // the server's armor slot
	LEGS,
	GLOVES,
	BOOTS,
	BACK, // capes (EM part 12), skinned like the rest
}
CHARA_ARMOR_LAYER_COUNT :: len(Chara_Armor_Layer)

CHARA_HEAD_BONE :: "Bip01 Head"

// A per-entity animated clone. It shares the cached Chara_Model's GPU meshes,
// materials and skeleton definition, but owns its bone-matrix / pose buffers:
// UpdateModelAnimation writes through the pointers below, so each avatar
// animates independently of the shared cache and of every other avatar.
Chara_Avatar :: struct {
	cm:          ^Chara_Model,
	sub:         Chara_Subset,
	anim_vertices: [dynamic][]f32, // per-avatar cloned skin arrays (owned)
	anim_normals:  [dynamic][]f32,
	current_clip: int,  // index into cm.anims, -1 until first update
	action_clip: int,   // action override (cast, emote, ...), -1 = none
	action_loop: bool,  // loop the action until cleared vs one-shot
	action_speed: f32,  // playback rate of the current action (attack speed)
	action_freeze: bool, // hold the current action frame (bow aim holds)
	attack_cycle: int,  // swings played — cycles the family's attack_1/2/3
	combat_idle:  int,  // weapon drawn idle (xx01) while fighting, -1 = none
	combat_run:   int,  // weapon drawn run (xx18) while fighting, -1 = none
	weapon_kind:  Weapon_Kind, // equipped family — drives the carry socket
	// block stance (buff_blocking_stance): block_stationary (0131) standing,
	// block_march (0130) moving — motion under the flag only happens with
	// Defensive March, since plain block can't move server-side.
	blocking:              bool,
	block_stationary_anim: int, // -1 = model lacks the clip
	block_march_anim:      int,
	// worn armor (local player): resolved appearance per layer. Models come
	// from the session held-model cache and are re-posed every frame with the
	// avatar's clip (see chara_avatar_update_armor).
	armor_sids:   [CHARA_ARMOR_LAYER_COUNT]int,        // item.csv RDR-SID, 0 = empty
	armor_parts:  [CHARA_ARMOR_LAYER_COUNT]int,        // EM part code
	armor_models: [CHARA_ARMOR_LAYER_COUNT]^Model_Entry,
	armor_rigid:  [CHARA_ARMOR_LAYER_COUNT]bool,       // helmets: bone-attach draw
	// SHIELD slot: rigid race-independent glb, always drawn on the left-arm
	// socket (see chara_avatar_draw_shield). Set by chara_avatar_sync_armor.
	shield_model: ^Model_Entry,
	// per sub mesh: the equipped armor replaces this body region (swapped out,
	// not wrapped over) — recomputed by chara_avatar_sync_armor
	body_hidden: [dynamic]bool,
	// pose blending: when the playing clip changes, cross-fade from the pose
	// actually on screen (applied_*) into the new clip over CHARA_BLEND_TIME
	applied_clip:  int,  // clip of the last applied pose, -1 = none yet
	applied_frame: f32,  // frame of the last applied pose
	blend_from:    int,  // clip being blended away, -1 = not blending
	blend_frame:   f32,  // frozen frame of blend_from
	blend_t:       f32,  // seconds since the blend started
	anim_time:   f64,
	scale:       f32,
	lift:        f32,   // world-space feet offset from the posed bounds
	measured:    bool,
	// Mount state (MOUNT_UPDATE / Local_Player.mounted): while set, the
	// avatar plays the mounted_* stances and rides at HORSE_RIDER_LIFT over
	// the horse model drawn beneath it (see horses.odin).
	mounted:     bool,
	base_lift:   f32,  // measured feet-on-origin lift (restored on dismount)
	// movement tracking (the owner computes speed, see ecs.update)
	prev_x:      f32,
	prev_z:      f32,
	has_prev:    bool,
	speed:       f32,
}

// Builds an avatar for `cm` with the chosen variants. Takes ownership of one
// reference to `cm` (the caller's acquire): destroy releases it. Returns nil
// if the subset can't be built (caller must then release cm itself).
chara_avatar_create :: proc(cm: ^Chara_Model, face_i, hair_i, color_i: int) -> ^Chara_Avatar {
	if cm == nil || cm.entry == nil do return nil
	av := new(Chara_Avatar)
	av.cm = cm
	av.sub = chara_subset_build(cm, face_i, hair_i, color_i)
	if av.sub.model.meshCount == 0 {
		chara_subset_free(&av.sub)
		free(av)
		return nil
	}

	// raylib skins these characters on the CPU: UpdateModelAnimation deforms
	// mesh.animVertices and re-uploads the mesh's GPU buffer. The subset's
	// meshes point at the SHARED cached buffers, so each avatar deep-copies
	// the animated arrays and uploads its own — otherwise every entity would
	// render in whichever pose was updated last.
	for i in 0..<int(av.sub.model.meshCount) {
		m := &av.sub.model.meshes[i]
		n := int(m.vertexCount)
		if n > 0 && m.vertices != nil {
			av_data := make([]f32, n * 3)
			src := m.animVertices != nil ? m.animVertices : m.vertices
			copy(av_data, src[:n * 3])
			m.animVertices = transmute([^]f32)raw_data(av_data)
			append(&av.anim_vertices, av_data)
		}
		if n > 0 && m.normals != nil {
			an_data := make([]f32, n * 3)
			src := m.animNormals != nil ? m.animNormals : m.normals
			copy(an_data, src[:n * 3])
			m.animNormals = transmute([^]f32)raw_data(an_data)
			append(&av.anim_normals, an_data)
		}
		if m.vertices != nil {
			rl.UploadMesh(m, false) // own VAO/VBOs, static until skinned
		}
	}

	av.scale = AVATAR_HEIGHT / CHARA_REF_HEIGHT
	av.current_clip = -1
	av.action_clip = -1
	av.action_speed = 1
	av.combat_idle = -1
	av.combat_run = -1
	av.block_stationary_anim = chara_clip(cm, CLIP_CODE_BLOCK_STATIONARY)
	av.block_march_anim = chara_clip(cm, CLIP_CODE_BLOCK_MARCH)
	av.applied_clip = -1
	av.blend_from = -1
	for i in 0..<int(av.sub.model.meshCount) do append(&av.body_hidden, false)
	return av
}

// Clip codes are the numeric suffix on each animation name
// (CA_00_011_00_000_0071 -> "0071") and are consistent across all character
// models — the shared semantic namespace. Gameplay slots reference codes;
// `cm.clips` resolves them to indices in O(1).
CLIP_CODE_IDLE            :: "0001"
CLIP_CODE_WALK            :: "0015"
CLIP_CODE_RUN             :: "0018"
CLIP_CODE_BLOCK_MARCH     :: "0130"
CLIP_CODE_BLOCK_STATIONARY :: "0131"
CLIP_CODE_CAST_LOOP       :: "0071"
CLIP_CODE_CAST_END        :: "0072"
CLIP_CODE_CAST_END_ATTACK :: "0073"

// Mounted stances (anim_ref.json). The unarmed set: vault on/off one-shots,
// idle, movement, gallop ("charge"). The armed set mirrors it; the block
// stance replaces both gaits while buff_blocking_stance holds.
CLIP_CODE_MOUNT               :: "0011"
CLIP_CODE_DISMOUNT            :: "0012"
CLIP_CODE_MOUNTED_IDLE        :: "0201"
CLIP_CODE_MOUNTED_MOVE        :: "0217"
CLIP_CODE_MOUNTED_CHARGE      :: "0218"
CLIP_CODE_MOUNTED_ARMED_IDLE   :: "0301"
CLIP_CODE_MOUNTED_ARMED_MOVE   :: "0316"
CLIP_CODE_MOUNTED_ARMED_CHARGE :: "0318"
CLIP_CODE_MOUNTED_BLOCK        :: "0331"

// Auto-attack clip codes per weapon kind: every family animates its basic
// swings as three ..._drawn_attack one-shots (codes f055/f056/f057). The
// castable families are shared by the whole castable weapon set — 1h sword,
// club, wand and axe ride 1h_castable; 2h rod and hammer ride 2h_castable.
// The remaining kinds map to their like-named family (2h axe has no family of
// its own and borrows the 2h_hammer swings). No weapon falls back to unarmed.
Chara_Weapon_Family :: struct {
	idle:               string, // weapon drawn idle (xx01)
	run:                string, // weapon drawn run (xx18)
	a1, a2, a3:         string, // basic swings (xx55..xx57)
	cast_start:         string, // cast channel loop; "" ⇒ family has none
	cast_finish:        string, // buff/debuff cast finish
	cast_finish_attack: string, // attack cast finish
	// Bow-style phased attacks: draw start → hold (loop) → release (the
	// release doubles as a basic swing). skill_* repeats the pattern for
	// Shot-category skills (arrow rain/storm). "" ⇒ the family just swings.
	ranged_start, ranged_hold, ranged_release: string,
	skill_start,  skill_hold,  skill_release:  string,
}

chara_weapon_family :: proc(kind: Weapon_Kind) -> (f: Chara_Weapon_Family) {
	switch kind {
	case .DAGGER:           return {idle = "1101", run = "1118", a1 = "1155", a2 = "1156", a3 = "1157"}
	case .SWORD, .AXE, .BLUNT, .WAND:
	                        return {idle = "1201", run = "1218", a1 = "1255", a2 = "1256", a3 = "1257",
	                                cast_start = "1271", cast_finish = "1272", cast_finish_attack = "1273"}
	case .SPEAR:            return {idle = "1301", run = "1318", a1 = "1355", a2 = "1356", a3 = "1357"}
	case .TWO_HANDED_SWORD: return {idle = "1401", run = "1418", a1 = "1455", a2 = "1456", a3 = "1457"}
	case .TWO_HANDED_AXE:   return {idle = "1501", run = "1518", a1 = "1555", a2 = "1556", a3 = "1557"}
	case .TWO_HANDED_SPEAR: return {idle = "1601", run = "1618", a1 = "1655", a2 = "1656", a3 = "1657"}
	case .TWO_HANDED_BLUNT: // 2h hammer: its own family's stance/swings — NOT a
	                        // rod — but acolytes cast spells with hammers, so
	                        // casting rides the 2h castable stances (1771-73)
	                        return {idle = "1501", run = "1518", a1 = "1555", a2 = "1556", a3 = "1557",
	                                cast_start = "1771", cast_finish = "1772", cast_finish_attack = "1773"}
	case .STAFF:            return {idle = "1701", run = "1718", a1 = "1755", a2 = "1756", a3 = "1757",
	                                cast_start = "1771", cast_finish = "1772", cast_finish_attack = "1773"}
	case .BOW:              return {idle = "1801", run = "1818", a1 = "1855", a2 = "1856", a3 = "1857",
	                                ranged_start = "1861", ranged_hold = "1862", ranged_release = "1855",
	                                skill_start = "1863",  skill_hold = "1864",  skill_release = "1856"}
	case .CROSSBOW:         return {idle = "1901", run = "1918", a1 = "1955", a2 = "1956", a3 = "1957",
	                                ranged_start = "1961", ranged_hold = "1962", ranged_release = "1955"}
	                                // 1963/1964 are the aim-up variant (elevated targets,
	                                // unused yet); crossbow skills loose the normal 1955.
	case .KNUCKLES:         return {idle = "2001", run = "2018", a1 = "2055", a2 = "2056", a3 = "2057"}
	case .NONE:             return {idle = "1001", run = "1018", a1 = "1055", a2 = "1056", a3 = "1057"}
	}
	return {idle = "1001", run = "1018", a1 = "1055", a2 = "1056", a3 = "1057"} // unreachable: every kind covered
}

chara_clip :: proc(cm: ^Chara_Model, code: string) -> int {
	if cm == nil do return -1
	idx, ok := cm.clips[code]
	if !ok do return -1
	return idx
}

// Mounted weapon families (the 3xxx codes): per-family drawn idles/runs and
// swings, generic mounted cast stances for the castable sets. Same shape as
// the on-foot families so every battle-script resolver works unchanged while
// riding; clips a model doesn't ship fall back at the play sites.
chara_mounted_weapon_family :: proc(kind: Weapon_Kind) -> (f: Chara_Weapon_Family) {
	switch kind {
	case .DAGGER:           return {idle = "3101", run = "3118", a1 = "3155", a2 = "3156", a3 = "3157",
	                                cast_start = "3271", cast_finish = "3272", cast_finish_attack = "3273"}
	case .SWORD, .AXE, .BLUNT, .WAND: // 1h weapons ride the 1h castable family
		                        return {idle = "3201", run = "3218", a1 = "3255", a2 = "3256", a3 = "3257",
		                                cast_start = "3271", cast_finish = "3272", cast_finish_attack = "3273"}
	case .SPEAR:            return {idle = "3601", run = "3618", a1 = "3655", a2 = "3656", a3 = "3657"} // 1h lance
	case .TWO_HANDED_SWORD: return {idle = "3401", run = "3418", a1 = "3455", a2 = "3456", a3 = "3457"}
	case .TWO_HANDED_AXE, .TWO_HANDED_BLUNT:
		                        return {idle = "3301", run = "3318", a1 = "3355", a2 = "3356", a3 = "3357"}
	case .TWO_HANDED_SPEAR: return {idle = "3501", run = "3518", a1 = "3555", a2 = "3556", a3 = "3557"}
	case .STAFF:            return {idle = "3701", run = "3718", a1 = "3755", a2 = "3756", a3 = "3757",
	                                cast_start = "3271", cast_finish = "3272", cast_finish_attack = "3273"}
	case .BOW:              return {idle = "3801", run = "3818", a1 = "3855", a2 = "3856", a3 = "3857",
	                                ranged_start = "3861", ranged_hold = "3862", ranged_release = "3855",
	                                skill_start = "3863",  skill_hold = "3864",  skill_release = "3856"}
	case .CROSSBOW:         return {idle = "3901", run = "3918", a1 = "3955", a2 = "3956", a3 = "3957",
	                                ranged_start = "3961", ranged_hold = "3962", ranged_release = "3955"}
	case .KNUCKLES:         return {idle = "3001", run = "3018", a1 = "3255", a2 = "3256", a3 = "3257"} // claws ride the 1h swings
	case .NONE:             return {idle = "0201", run = "0217", a1 = "3255", a2 = "3256", a3 = "3257"}
	}
	return {idle = "0201", run = "0217", a1 = "3255", a2 = "3256", a3 = "3257"} // unreachable: every kind covered
}

// The family for an avatar's CURRENT stance: mounted families while riding,
// the on-foot families otherwise. All battle-script motion resolution and
// cast stances go through this so a rider's swings, draws and casts swap to
// the 3xxx mounted clips as a unit.
chara_weapon_family_for :: proc(av: ^Chara_Avatar, kind: Weapon_Kind) -> (f: Chara_Weapon_Family) {
	if av != nil && av.mounted do return chara_mounted_weapon_family(kind)
	return chara_weapon_family(kind)
}

// Last '_'-separated token of an animation name (the clip code).
chara_code_of :: proc(name: string) -> string {
	last := -1
	for i in 0..<len(name) {
		if name[i] == '_' do last = i
	}
	if last < 0 || last + 1 >= len(name) do return ""
	return name[last + 1:]
}

// One-time reference dump: every animation of every loaded model as
// "<model>	<code>	<name>" in chara_animations.txt (gitignored), for
// cataloguing clip codes against gameplay meanings.
chara_dump_animations :: proc(cm: ^Chara_Model) {
	if cm == nil do return
	existing, err := os.read_entire_file_from_path(ANIM_DUMP_PATH, allocator = context.temp_allocator)
	sb := strings.builder_make(context.temp_allocator)
	if err == nil {
		strings.write_string(&sb, string(existing))
	}
	for i in 0..<cm.anim_count {
		name := chara_anim_name(&cm.anims[i])
		strings.write_string(&sb, cm.id)
		strings.write_byte(&sb, '\t')
		strings.write_string(&sb, chara_code_of(name))
		strings.write_byte(&sb, '\t')
		strings.write_string(&sb, name)
		strings.write_byte(&sb, '\n')
	}
	_ = os.write_entire_file_from_string(ANIM_DUMP_PATH, strings.to_string(sb))
}

// ── animation debug relay ────────────────────────────────────────────────
// Every clip play/freeze/stop on any avatar reports itself to the client
// console and (when a sink is set) to the server console over ANIM_DEBUG.
// Gameplay sets the sink to its network client at init.
anim_debug_relay: ^Network_Client

anim_debug_relay_set :: proc(nc: ^Network_Client) {
	anim_debug_relay = nc
}

anim_debug_msg :: proc(msg: string) {
	rl.TraceLog(.INFO, "[clip] %s", assets_cstring(msg))
	if anim_debug_relay != nil do send_anim_debug(anim_debug_relay, msg)
}

// Starts an action clip override by name code ("0071", "0072", ...). Looping
// actions run until chara_avatar_stop_action; one-shots return to the
// movement clip when they finish. No-op if the model lacks the clip.
chara_avatar_play_action :: proc(av: ^Chara_Avatar, code: string, loop: bool) {
	if av == nil do return
	chara_avatar_play_action_index(av, chara_clip(av.cm, code), loop)
}

// As play_action, but plays the first code the model actually ships —
// family clip first, neutral fallback last (see CLIP_CODE_*).
chara_avatar_play_action_any :: proc(av: ^Chara_Avatar, loop: bool, codes: ..string) {
	if av == nil do return
	for c in codes {
		idx := chara_clip(av.cm, c)
		if idx >= 0 {
			chara_avatar_play_action_index(av, idx, loop)
			return
		}
	}
}

chara_avatar_play_action_index :: proc(av: ^Chara_Avatar, clip_idx: int, loop: bool) {
	av.action_clip = clip_idx
	av.action_loop = loop
	av.action_speed = 1 // attack paths re-scale after playing
	av.action_freeze = false
	av.anim_time = 0
	av.current_clip = -1 // movement clip restarts fresh after the action
	if 0 <= clip_idx && clip_idx < av.cm.anim_count {
		anim_debug_msg(fmt.tprintf("play model=%s %s loop=%v",
			av.cm.id, chara_anim_name(&av.cm.anims[clip_idx]), loop))
	}
}

// Pin the avatar to `clip_idx`'s final frame (a bow aim hold): the action
// stays until another play/stop replaces it.
chara_avatar_freeze_action :: proc(av: ^Chara_Avatar, clip_idx: int) {
	if av == nil || clip_idx < 0 do return
	frames := f32(anim_keyframe_count(av, clip_idx))
	if frames <= 0 do return
	av.action_clip = clip_idx
	av.action_loop = false
	av.action_freeze = true
	av.anim_time = f64((frames - 1) / CHARA_ANIM_FPS)
	av.current_clip = -1
	if 0 <= clip_idx && clip_idx < av.cm.anim_count {
		anim_debug_msg(fmt.tprintf("freeze model=%s %s",
			av.cm.id, chara_anim_name(&av.cm.anims[clip_idx])))
	}
}

// Tracks the equipped weapon's animation family: combat idles use the family
// drawn idle (xx01) instead of the neutral stance, and the carry sockets in
// chara_avatar_draw_held pick by kind. Cheap enough to call every frame (one
// map lookup) — equipment swaps then apply instantly.
chara_avatar_set_weapon_kind :: proc(av: ^Chara_Avatar, kind: Weapon_Kind) {
	if av == nil do return
	fam := chara_weapon_family_for(av, kind)
	av.combat_idle = chara_clip(av.cm, fam.idle)
	av.combat_run = chara_clip(av.cm, fam.run)
	// Mounted family stances are spotty per model (the human male ships no
	// family run/idle clips at all) — the generic armed mounted stances are
	// the fallback when the family's own are missing.
	if av.mounted {
		if av.combat_idle < 0 do av.combat_idle = chara_clip(av.cm, CLIP_CODE_MOUNTED_ARMED_IDLE)
		if av.combat_run < 0 do av.combat_run = chara_clip(av.cm, CLIP_CODE_MOUNTED_ARMED_CHARGE)
	}
	av.weapon_kind = kind
}

chara_avatar_stop_action :: proc(av: ^Chara_Avatar) {
	if av == nil do return
	av.action_clip = -1
	av.anim_time = 0
	anim_debug_msg("stop")
}

// Plays one weapon attack swing on the avatar: the kind's family clips from
// chara_weapon_family (the mounted families while riding), cycled 1→2→3
// across consecutive swings. Clips the model lacks are skipped (the
// bow/crossbow sets ship only attack_1/2); no-op when the model has none of
// the family's clips at all.
chara_avatar_play_attack :: proc(av: ^Chara_Avatar, kind: Weapon_Kind) {
	if av == nil do return
	fam := chara_weapon_family_for(av, kind)
	family := [3]string{fam.a1, fam.a2, fam.a3}
	codes: [3]string
	n := 0
	for c in family {
		if chara_clip(av.cm, c) >= 0 {
			codes[n] = c
			n += 1
		}
	}
	if n == 0 do return
	chara_avatar_play_action(av, codes[av.attack_cycle % n], false)
	av.attack_cycle += 1
}

chara_avatar_destroy :: proc(av: ^Chara_Avatar) {	if av == nil do return
	// Unload the cloned GPU meshes. UnloadMesh also frees the CPU arrays, and
	// most of those are shared with the cached base model — nil them first so
	// only the avatar-owned anim arrays go away.
	for i in 0..<int(av.sub.model.meshCount) {
		m := &av.sub.model.meshes[i]
		if m.vaoId == 0 do continue
		m.vertices = nil
		m.texcoords = nil
		m.texcoords2 = nil
		m.normals = nil
		m.tangents = nil
		m.colors = nil
		m.indices = nil
		m.boneIndices = nil
		m.boneWeights = nil
		rl.UnloadMesh(m^)
	}
	for arr in av.anim_vertices do delete(arr)
	delete(av.anim_vertices)
	for arr in av.anim_normals do delete(arr)
	delete(av.anim_normals)
	delete(av.body_hidden)
	chara_subset_free(&av.sub)
	chara_model_release(av.cm)
	free(av)
}

// Advances the avatar's animation for one frame toward `clip` — toward the
// weapon drawn idle/run instead while `combat` — blending across clip changes,
// and, on the first call, measures the posed bounds for the ground lift.
chara_avatar_update :: proc(av: ^Chara_Avatar, clip: Chara_Clip, dt: f32, combat: bool) {
	if av == nil || av.cm == nil || av.cm.idle_anim < 0 do return

	// Action override (cast loop, cast finish, attack swing, ...) wins over
	// movement clips; one-shots auto-clear back to movement when they run out.
	clip_idx := -1
	if av.action_clip >= 0 {
		clip_idx = av.action_clip
		if !av.action_loop {
			frames := f32(anim_keyframe_count(av, clip_idx))
			if frames <= 0 || f32(av.anim_time) * CHARA_ANIM_FPS >= frames {
				av.action_clip = -1
				clip_idx = -1
			}
		}
	}

	if clip_idx < 0 {
		clip_idx = av.cm.idle_anim
		if av.mounted {
			// Mounted stances: the legs ride, the torso fights — unarmed
			// idle/move/charge 0201/0217/0218, armed riders use their weapon
			// family's mounted stance (combat_idle / 0316 / the family run
			// resolved into combat_run by set_weapon_kind). The block stance
			// replaces every gait while it holds.
			move_idx := chara_clip(av.cm, combat ? CLIP_CODE_MOUNTED_ARMED_MOVE : CLIP_CODE_MOUNTED_MOVE)
			idle_idx := combat && av.combat_idle >= 0 ? av.combat_idle : chara_clip(av.cm, combat ? CLIP_CODE_MOUNTED_ARMED_IDLE : CLIP_CODE_MOUNTED_IDLE)
			charge_idx := -1
			if combat {
				charge_idx = av.combat_run >= 0 ? av.combat_run : chara_clip(av.cm, CLIP_CODE_MOUNTED_ARMED_CHARGE)
			} else {
				charge_idx = chara_clip(av.cm, CLIP_CODE_MOUNTED_CHARGE)
			}
			block_idx := chara_clip(av.cm, CLIP_CODE_MOUNTED_BLOCK)
			#partial switch clip {
			case .IDLE:
				if av.blocking && block_idx >= 0 do clip_idx = block_idx
				else if idle_idx >= 0 do clip_idx = idle_idx
			case .WALK:
				if av.blocking && block_idx >= 0 do clip_idx = block_idx
				else if move_idx >= 0 do clip_idx = move_idx
				else if idle_idx >= 0 do clip_idx = idle_idx
			case .RUN:
				if av.blocking && block_idx >= 0 do clip_idx = block_idx
				else if charge_idx >= 0 do clip_idx = charge_idx
				else if move_idx >= 0 do clip_idx = move_idx
			case:
			}
			if clip_idx < 0 do clip_idx = av.cm.idle_anim
		} else {
		#partial switch clip {
		case .WALK:
			// Block stance rides block_march at any pace (plain block can't
			// move server-side — motion under the flag is Defensive March).
			if av.blocking && av.block_march_anim >= 0 {
				clip_idx = av.block_march_anim
			} else if av.cm.walk_anim >= 0 do clip_idx = av.cm.walk_anim
		case .RUN:
			// Drawn stance runs on the weapon family's drawn run (xx18); the
			// normal run (0018) is the sheathed/unarmed gait. Blocking wins
			// over both (block_march).
			if av.blocking && av.block_march_anim >= 0 {
				clip_idx = av.block_march_anim
			} else if combat && av.combat_run >= 0 {
				clip_idx = av.combat_run
			} else if av.cm.run_anim >= 0 {
				clip_idx = av.cm.run_anim
			}
		case .IDLE:
			// In combat the character holds the weapon family's drawn stance;
			// block stance (0131) wins over that too.
			if av.blocking && av.block_stationary_anim >= 0 {
				clip_idx = av.block_stationary_anim
			} else if combat && av.combat_idle >= 0 do clip_idx = av.combat_idle
		case:
		}
		}
		if clip_idx != av.current_clip {
			av.current_clip = clip_idx
			av.anim_time = 0
		} else {
			av.anim_time += f64(dt)
		}
	} else {
		if !av.action_freeze do av.anim_time += f64(dt * av.action_speed)
	}

	// When the clip on screen changes, cross-fade from the last applied pose
	// into the new clip (UpdateModelAnimationEx) over CHARA_BLEND_TIME.
	if clip_idx != av.applied_clip {
		av.blend_from = av.applied_clip
		av.blend_frame = av.applied_frame
		av.blend_t = 0
	}

	anim := &av.cm.anims[clip_idx]
	frames := f32(anim.keyframeCount)
	if frames > 0 && anim.keyframePoses != nil {
		f := f32(av.anim_time) * CHARA_ANIM_FPS
		frame := f - f32(i32(f / frames)) * frames
		blending := av.blend_from >= 0 && av.blend_from != clip_idx
		if blending {
			av.blend_t += dt
			if av.blend_t >= CHARA_BLEND_TIME do blending = false
		}
		if !blending do av.blend_from = -1
		av.applied_clip = clip_idx
		av.applied_frame = frame
		// Pose application happens at DRAW time (chara_avatar_draw_body): the
		// CPU-skinned vertex buffers and currentPose are shared per race
		// model, so skinning here would stamp this avatar's pose onto every
		// same-race character — update order, not draw order, would decide
		// who renders whose animation.
	}

	// One-time ground-lift measure reads the skinned vertices, so stamp this
	// avatar's pose first. Harmless at update time: every draw re-poses the
	// shared model before drawing anyway.
	if !av.measured {
		av.measured = true
		chara_apply_current_pose(av, av.sub.model)
		b := chara_skin_bounds(av.cm, &av.sub.model)
		av.base_lift = -b.min.y * av.scale
	}
	// Riders lift off their own feet: while mounted the avatar hangs at the
	// horse's saddle height (see horses.odin) instead of the ground.
	av.lift = av.mounted ? HORSE_RIDER_LIFT : av.base_lift
}

// Flip an avatar's mount state. While mounted the update loop plays the
// mounted_* stances (chara_avatar_update) and combat motion resolves through
// the mounted weapon families; the vault-on/vault-off one-shot covers the
// transition when the model ships it.
chara_avatar_set_mounted :: proc(av: ^Chara_Avatar, mounted: bool) {
	if av == nil || av.mounted == mounted do return
	av.mounted = mounted
	// combat_idle/combat_run re-resolve to the mounted families on the next
	// set_weapon_kind call (both owners call it every frame).
	chara_avatar_play_action_any(av, false, mounted ? CLIP_CODE_MOUNT : CLIP_CODE_DISMOUNT)
}

// Replays the avatar's current pose — the exact clip, frame and blend state
// chara_avatar_update just computed — onto `model`. Used for the body subset
// and for skinned armor pieces, whose glbs carry the same master skeleton in
// the same joint order (verified per race).
chara_apply_current_pose :: proc(av: ^Chara_Avatar, model: rl.Model) {
	if av == nil || av.cm == nil || av.applied_clip < 0 do return
	anim := &av.cm.anims[av.applied_clip]
	if av.blend_from >= 0 && av.blend_from != av.applied_clip && av.blend_t < CHARA_BLEND_TIME {
		rl.UpdateModelAnimationEx(model,
			av.cm.anims[av.blend_from], av.blend_frame,
			anim^, av.applied_frame, av.blend_t / CHARA_BLEND_TIME)
	} else {
		rl.UpdateModelAnimation(model, anim^, av.applied_frame)
	}
}

anim_keyframe_count :: proc(av: ^Chara_Avatar, clip_idx: int) -> i32 {
	if clip_idx < 0 || clip_idx >= av.cm.anim_count do return 0
	return av.cm.anims[clip_idx].keyframeCount
}

// ── held-item attachment ─────────────────────────────────────────────────
// The shipped rigs are classic Bip01 skeletons; the right hand is the weapon
// grip. raylib composes keyframePoses AND the bind pose into GLOBAL
// model-space transforms when loading a glb (BuildPoseFromParentJoints in
// rmodels.c), and UpdateModelAnimation keeps the interpolated global pose of
// the last applied clip in model.currentPose — the same pose the deformed
// vertices wear (v_anim = v_bind·bind⁻¹·anim, all global-space). The attach
// matrix is therefore just currentPose[hand] composed as a matrix — NO
// parent-chain walk (the poses are already global; chaining them again was
// the held-item "floating + flailing" bug).
//
// NOTE: currentPose/boneMatrices are shared per BASE model (the subset copy
// re-points at them). chara_avatar_draw_body poses the avatar immediately
// before its meshes, and the held/shield draws run after it in the same
// entity's draw sequence, so these reads always see the drawing avatar's own
// pose — never pose-read outside a body→held→armor→shield draw sequence.

CHARA_HAND_BONE :: "Bip01 R Hand"
CHARA_HAND_L_BONE :: "Bip01 L Hand"

chara_bone_name :: proc "contextless" (b: ^rl.BoneInfo) -> string {
	for i in 0..<len(b.name) {
		if b.name[i] == 0 do return string(b.name[:i])
	}
	return string(b.name[:])
}

// Global (model-space) matrix of `bone_name` in the avatar's currently
// applied pose. False when the rig lacks the bone or nothing has been posed.
chara_avatar_bone_matrix :: proc(av: ^Chara_Avatar, bone_name: string) -> (rl.Matrix, bool) {
	identity := rl.Matrix {
		1, 0, 0, 0,
		0, 1, 0, 0,
		0, 0, 1, 0,
		0, 0, 0, 1,
	}
	if av == nil || av.cm == nil do return identity, false

	skel := &av.sub.model.skeleton
	if skel.bones == nil || av.sub.model.currentPose == nil do return identity, false
	bone_count := int(skel.boneCount)

	bidx := -1
	for i in 0..<bone_count {
		if chara_bone_name(&skel.bones[i]) == bone_name {
			bidx = i
			break
		}
	}
	if bidx < 0 do return identity, false

	// Column-vector TRS compose (verified against raylib's deformed vertices
	// in tools/bone_test.odin: translation outermost, Vector3Transform = M·v).
	t := av.sub.model.currentPose[bidx]
	return rl.MatrixTranslate(t.translation.x, t.translation.y, t.translation.z) *
		rl.QuaternionToMatrix(t.rotation) *
		rl.MatrixScale(t.scale.x, t.scale.y, t.scale.z), true
}

// Global (model-space) BIND matrix of `bone_name` — where the bone sits in the
// rig's shipped rest pose. With chara_avatar_bone_matrix this forms the
// pose·bind⁻¹ delta for meshes authored in bind space (rigid helmets).
chara_avatar_bone_bind_matrix :: proc(av: ^Chara_Avatar, bone_name: string) -> (rl.Matrix, bool) {
	identity := rl.Matrix {
		1, 0, 0, 0,
		0, 1, 0, 0,
		0, 0, 1, 0,
		0, 0, 0, 1,
	}
	if av == nil || av.cm == nil do return identity, false

	skel := &av.sub.model.skeleton
	if skel.bones == nil do return identity, false
	bone_count := int(skel.boneCount)

	bidx := -1
	for i in 0..<bone_count {
		if chara_bone_name(&skel.bones[i]) == bone_name {
			bidx = i
			break
		}
	}
	if bidx < 0 do return identity, false

	t := skel.bindPose[bidx]
	return rl.MatrixTranslate(t.translation.x, t.translation.y, t.translation.z) *
		rl.QuaternionToMatrix(t.rotation) *
		rl.MatrixScale(t.scale.x, t.scale.y, t.scale.z), true
}

// The engine's weapon seat: item models are authored grip-at-origin and the
// game bolts them onto N-bone sockets under the hand bones — the N52 family
// (N52/N53/N54/N55/N58 share one local) for the right hand, N62 for the
// left; N50 is the same seat rolled 180°. Locals measured from the shipped
// master skeleton def CM_00_011_00_000.dxg (PandoraSaga/cpp/socket_probe.cpp
// = lbind[N52] of the def's inverse binds), conjugated into the exporter's
// X-flipped, 1/100-scaled glTF space (quat (x,-y,-z,w), translation
// (-x,y,z)/100). At idle this seats a staff's head behind the back at hip
// height and its shaft past the front hip — the shipped viewer's placement.
CHARA_GRIP_R_T :: rl.Vector3{-0.0926, -0.0025, 0.0344}
CHARA_GRIP_R_Q :: rl.Quaternion(quaternion(x = 0.6827, y = 0.1390, z = -0.1286, w = 0.7057))
CHARA_GRIP_L_T :: rl.Vector3{-0.0926, 0.0025, 0.0344}
CHARA_GRIP_L_Q :: rl.Quaternion(quaternion(x = -0.6871, y = 0.1384, z = 0.1085, w = 0.7050))

chara_grip_matrix :: proc "contextless" (left: bool) -> rl.Matrix {
	t := CHARA_GRIP_R_T
	q := CHARA_GRIP_R_Q
	if left {
		t = CHARA_GRIP_L_T
		q = CHARA_GRIP_L_Q
	}
	return rl.MatrixTranslate(t.x, t.y, t.z) * rl.QuaternionToMatrix(q)
}

// Drawn-grip seat translations per stance (right hand). The rotation is the
// N52 socket's (CHARA_GRIP_R_Q). The base translation puts the weapon's shaft
// axis through the FIST center (wrist + knuckle centroid — solved from the
// drawn idles; the same value falls out for every class). On top of that each
// stance slides the weapon along its own shaft axis to match the shipped
// game's grip point, measured against annotated screenshots: 2h weapons sat
// ~0.19 too far toward the head (butt poking out the back), 1h wands ~0.10
// too far toward the butt (riding high above the fist).
CHARA_GRIP_2H_T :: rl.Vector3{-0.05570, 0.18736, -0.00017}
CHARA_GRIP_1H_T :: rl.Vector3{-0.04973, -0.10244, 0.00830}
// Spears rest on the left hand when drawn — solved from the 2h_spear drawn
// idle against both hands (the generic 2h seat leaves a 6cm gap there).
CHARA_GRIP_SPEAR_T :: rl.Vector3{0.03198, 0.00163, 0.04010}

// Seat translation for a drawn weapon of `kind`. Bows and worn claws keep the
// raw N52 offset (no measured correction for bows yet).
chara_drawn_grip_t :: proc(kind: Weapon_Kind) -> rl.Vector3 {
	if t, ok := chara_tuned[kind]; ok do return t.drawn_t
	if kind == .BOW do return CHARA_GRIP_L_T // bows draw left-handed (N62)
	if kind == .TWO_HANDED_SPEAR do return CHARA_GRIP_SPEAR_T
	stance := chara_held_stance(kind)
	if stance == .HIP do return CHARA_GRIP_1H_T
	if stance == .BACK do return CHARA_GRIP_2H_T
	return CHARA_GRIP_R_T
}

// Drawn-grip rotation per weapon kind (right hand). Every class starts on the
// N52 socket orientation (CHARA_GRIP_R_Q); classes whose model axes disagree
// get their own quaternion baked here from tools/sheath_tune's
// sheath_tuning.json ("drawn_q"), same as the spear row above in _t.
chara_drawn_grip_q :: proc(kind: Weapon_Kind) -> rl.Quaternion {
	if t, ok := chara_tuned[kind]; ok do return t.drawn_q
	if kind == .BOW do return CHARA_GRIP_L_Q // bows draw left-handed (N62)
	// per-kind carve-outs land here as classes get tuned, e.g.
	// if kind == .CROSSBOW do return rl.Quaternion(quaternion(x = …, y = …, z = …, w = …))
	return CHARA_GRIP_R_Q
}

// ── sheathed carry ────────────────────────────────────────────────────────
// Where a weapon rides when it is not drawn. The engine's carry sockets are
// N-bones that ship inside the ARMOR glbs' master skeletons (111 bones vs the
// character's 90), all hanging off "Bip01": N22 = left hip (1h weapons),
// N35 = lower-back diagonal (2h melee/staves), N36 = upper back (bows). Each
// seat below is R = socket bind world · "Bip01" bind world⁻¹, measured from
// EM_012014_02_011.glb's bind pose — already in glTF space, so it composes
// directly with the chara rig's animated "Bip01" pose.
Chara_Held_Stance :: enum u8 {
	HANDS,    // always wielded (claws/knuckles — worn, not carried)
	HIP,      // sheathed on the left hip (1h weapons)
	BACK,     // sheathed diagonally on the back (2h weapons, staves)
	BACK_BOW, // sheathed diagonally, higher mount (bows)
	DUAL_HIP, // claws — one on each hip when sheathed
}

// Which carry the weapon class uses. 1h weapons ride the left hip, 2h weapons
// and staves the back, bows/crossbows the upper-back mount; claws stay on the
// fists in both stances.
chara_held_stance :: proc(kind: Weapon_Kind) -> Chara_Held_Stance {
	#partial switch kind {
	case .KNUCKLES: return .DUAL_HIP
	case .TWO_HANDED_SWORD, .TWO_HANDED_AXE, .TWO_HANDED_BLUNT, .STAFF, .TWO_HANDED_SPEAR:
	                return .BACK
	case .BOW:      return .BACK_BOW
	case .CROSSBOW: return .BACK_BOW // seat overridden to CHARA_SOCKET_CROSSBOW
	case:           return .HIP
	}
}

Chara_Socket_Seat :: struct {
	parent: string, // chara bone the socket hangs from ("Bip01")
	t:      rl.Vector3,
	q:      rl.Quaternion,
}

// Sheath seats: R = socket bind world · "Bip01" bind world⁻¹, measured from
// the armor skeletons' N-bones (N22 left hip, N35 back, N36 upper back) —
// this exact triple is the known-good set (wand on hip verified in-game).
// 1h weapons rest against the left side (z 0.377 floated at arm's length).
// HIP_R is its left-right mirror for dual-worn claws (derivation: the Bip01
// bind rotation maps a local-z flip to a model-x flip, so t' = (x, y, -z)
// and q' = (-qx, -qy, +qz, qw)).
CHARA_SOCKET_HIP      :: Chara_Socket_Seat{"Bip01", rl.Vector3{0.10000, 0.08000, -0.10000},  rl.Quaternion(quaternion(x = 0.04456, y = 0.91330, z = 0.39125,  w = -0.10401))}
CHARA_SOCKET_BACK     :: Chara_Socket_Seat{"Bip01", rl.Vector3{0.32243, 0.05753, -0.02948},  rl.Quaternion(quaternion(x = 0.58876, y = 0.60267, z = -0.30903, w = 0.44120))}
CHARA_SOCKET_BACK_BOW :: Chara_Socket_Seat{"Bip01", rl.Vector3{0.21956, 0.27277, 0.08754},   rl.Quaternion(quaternion(x = -0.67491, y = 0.56950, z = 0.31770, w = 0.34529))}
// 1h weapons ride the back as a near-vertical shaft hugging the spine
// (SHEATHED 1H REFERENCE): handle up behind the right shoulder, head down at
// the right thigh. Solved offline against the Bip01 idle frame (raw model
// space faces +z; see tools/seats_probe.odin) — NOT an N-socket measurement.
CHARA_SOCKET_BACK_1H  :: Chara_Socket_Seat{"Bip01", rl.Vector3{0.20626, 0.19618, -0.01196},  rl.Quaternion(quaternion(x = -0.52208, y = 0.48704, z = 0.42855, w = 0.55369))}
// Crossbow: diagonal across the back, butt (item +Z) at the left hip, prod
// (item -Z) up behind the right shoulder, limbs level (CROSSBOW REFERENCE).
// Rendered WITHOUT the end-for-end flip.
CHARA_SOCKET_CROSSBOW  :: Chara_Socket_Seat{"Bip01", rl.Vector3{0.10372, -0.01382, 0.03586}, rl.Quaternion(quaternion(x = 0.48073, y = 0.18492, z = -0.47469, w = 0.71370))}

// Shield: strapped to the outer face of the left forearm, disc plane vertical,
// face out (+x). Solved from the bind skeleton (mid-forearm, outward normal);
// ships as a starting seat — override via sheath_tuning.json's "shield" entry
// (sheath_t / sheath_q) or tune it in tools/sheath_tune's "shield" category.
CHARA_SOCKET_SHIELD :: Chara_Socket_Seat{"Bip01 L Forearm", rl.Vector3{-0.13922, -0.08206, -0.13019}, rl.Quaternion(quaternion(x = -0.09885, y = 0.70258, z = 0.11031, w = 0.69602))}

// The shield seat: baked constant, overridden by sheath_tuning.json's
// "shield" entry when present (see chara_tuning.odin).
chara_shield_seat :: proc() -> Chara_Socket_Seat {
	seat := CHARA_SOCKET_SHIELD
	if shield_tuned_on {
		seat.t = shield_tuned_t
		seat.q = shield_tuned_q
	}
	return seat
}

// The sheath seat for a weapon kind (stance defaults + per-kind overrides).
chara_sheath_seat :: proc(kind: Weapon_Kind) -> Chara_Socket_Seat {
	stance := chara_held_stance(kind)
	seat := CHARA_SOCKET_BACK_1H // 1h weapons: vertical shaft on the back
	if stance == .DUAL_HIP do seat = CHARA_SOCKET_HIP // claws: one on each hip
	if stance == .BACK do seat = CHARA_SOCKET_BACK
	if stance == .BACK_BOW do seat = CHARA_SOCKET_BACK_BOW
	if kind == .CROSSBOW do seat = CHARA_SOCKET_CROSSBOW
	if t, ok := chara_tuned[kind]; ok {
		seat.t = t.sheath_t
		seat.q = t.sheath_q
	}
	return seat
}

// Mirrors a seat across the character's left-right plane (claws: left hip
// socket -> right hip socket).
chara_mirror_seat :: proc "contextless" (seat: Chara_Socket_Seat) -> Chara_Socket_Seat {
	return {seat.parent, {seat.t.x, seat.t.y, -seat.t.z}, rl.Quaternion(quaternion(x = -seat.q.x, y = -seat.q.y, z = seat.q.z, w = seat.q.w))}
}

// Tuning hooks for tools/sheath_tune.odin: when enabled, chara_avatar_draw_held
// uses these instead of the baked seats. Inert outside the tuner.
chara_debug_sheath_seat:      rl.Quaternion // full seat orientation
chara_debug_sheath_seat_t:    rl.Vector3    // seat translation
chara_debug_sheath_on:        bool
chara_debug_drawn_t:          rl.Vector3
chara_debug_drawn_q:          rl.Quaternion // drawn-grip orientation
chara_debug_drawn_on:         bool
chara_debug_shield_t:         rl.Vector3    // shield seat translation
chara_debug_shield_q:         rl.Quaternion // shield seat orientation
chara_debug_shield_on:        bool

// World matrix of a carry socket on the avatar's current pose.
chara_avatar_socket_matrix :: proc(av: ^Chara_Avatar, seat: Chara_Socket_Seat) -> (rl.Matrix, bool) {
	bip, ok := chara_avatar_bone_matrix(av, seat.parent)
	if !ok do return rl.Matrix(1), false
	return bip * (rl.MatrixTranslate(seat.t.x, seat.t.y, seat.t.z) * rl.QuaternionToMatrix(seat.q)), true
}

// Draw the held-item model (weapons — see items.odin held_model_for_item).
// Drawn: bolted onto the right-hand grip. Sheathed (`drawn = false`): bolted
// onto the weapon class's carry socket — hip for 1h, back for 2h/ranged;
// claws (HANDS stance) stay on the fists either way. `scale_mul` is the
// item.csv per-race scale (lapin wand 0.7, enkidu staff 2.0). The world
// matrix mirrors what DrawModelEx gives the avatar (avatar scale, yaw + the
// +Z-pipeline 180° offset, position+lift) composed around the attach matrix,
// column-vector style: (T·R·S·attach)·v — attach applies first, the way the
// engine bolts items onto N-bones.
// Top-of-model world transform for a held model: position+lift, yaw + the
// pipeline's 180° offset, avatar scale * item scale.
chara_held_base_matrix :: proc(
	av:       ^Chara_Avatar,
	position: rl.Vector3,
	yaw_rad:  f32,
	scale_mul: f32,
) -> rl.Matrix {
	m := rl.MatrixTranslate(position.x, position.y + av.lift, position.z) *
		rl.MatrixRotate({0, 1, 0}, yaw_rad + AVATAR_YAW_OFFSET_DEG * 0.017453293)
	s := av.scale * scale_mul
	return m * rl.MatrixScale(s, s, s)
}

draw_held_meshes :: proc(entry: ^Model_Entry, m: rl.Matrix) {
	for i in 0..<int(entry.model.meshCount) {
		mat_idx := int(entry.model.meshMaterial[i])
		rl.DrawMesh(entry.model.meshes[i], entry.model.materials[mat_idx], m)
	}
}

chara_avatar_draw_held :: proc(
	av:        ^Chara_Avatar,
	entry:     ^Model_Entry,
	position:  rl.Vector3,
	yaw_rad:   f32,
	tint:      rl.Color,
	drawn:     bool,
	scale_mul: f32,
) {
	if av == nil || entry == nil do return

	chara_tuning_tick() // pick up sheath_tuning.json edits ~2x/second

	m := chara_held_base_matrix(av, position, yaw_rad, scale_mul)

	stance := chara_held_stance(av.weapon_kind)
	use_hand := drawn || stance == .HANDS
	attach: rl.Matrix
	ok := false
	if use_hand {
		// Bows are held left-handed once drawn — the right hand works the
		// string — so the bow bolts onto the left-hand N62 seat; everything
		// else grips the right hand.
		left := drawn && av.weapon_kind == .BOW
		if left {
			attach, ok = chara_avatar_bone_matrix(av, CHARA_HAND_L_BONE)
		} else {
			attach, ok = chara_avatar_bone_matrix(av, CHARA_HAND_BONE)
		}
		if ok {
			gt := CHARA_GRIP_R_T
			gq := CHARA_GRIP_R_Q
			if left {
				gt = CHARA_GRIP_L_T
				gq = CHARA_GRIP_L_Q
			}
			if drawn {
				gt = chara_drawn_grip_t(av.weapon_kind)
				gq = chara_drawn_grip_q(av.weapon_kind)
				if chara_debug_drawn_on {
					gt = chara_debug_drawn_t
					gq = chara_debug_drawn_q
				}
			}
			attach = attach * (rl.MatrixTranslate(gt.x, gt.y, gt.z) * rl.QuaternionToMatrix(gq))
		}
	} else {
		seat := chara_sheath_seat(av.weapon_kind)
		if chara_debug_sheath_on {
			seat.t = chara_debug_sheath_seat_t
			seat.q = chara_debug_sheath_seat
		}
		attach, ok = chara_avatar_socket_matrix(av, seat)
		if !ok do return
		// No per-kind flips here: seats are tuned per weapon kind against the
		// actual model (tools/sheath_tune + sheath_tuning.json), so what the
		// tuner shows is exactly what renders.
		m = m * attach
		draw_held_meshes(entry, m)
		if stance == .DUAL_HIP { // second claw on the right hip
			attach, ok = chara_avatar_socket_matrix(av, chara_mirror_seat(seat))
			if ok {
				m2 := chara_held_base_matrix(av, position, yaw_rad, scale_mul) * attach
				draw_held_meshes(entry, m2)
			}
		}
		return
	}
	if !ok do return
	m = m * attach

	draw_held_meshes(entry, m)
}

// Which default-outfit region each armor layer replaces when equipped — 1:1
// with the EM part codes (torso→body_02, legs→body_03, gloves→body_04 hands,
// boots→body_05). HELMET and BACK hide nothing here; the helmet's hair
// replacement is handled separately in chara_avatar_sync_armor.
chara_layer_body_region_mask :: proc(layer: Chara_Armor_Layer) -> u8 {
	#partial switch layer {
	case .TORSO: return 1 << u8(Body_Region.Torso)
	case .LEGS:  return 1 << u8(Body_Region.Legs)
	case .GLOVES: return 1 << u8(Body_Region.Hands)
	case .BOOTS: return 1 << u8(Body_Region.Feet)
	}
	return 0
}

// Race index for the item.csv per-race override columns (viewer decode):
// 11→0 12→1 21→2 22→3 31→4 42→5 51→6 63→7. Accepts the bare race code
// ("12") or the chara model id ("012") — ids on disk are the race code
// with a leading 0. Returns -1 when the code isn't digits; callers must
// bounds-check before indexing the per-race columns.
chara_race_index :: proc(id: string) -> i8 {
	if len(id) < 2 do return -1
	code := id
	if len(code) > 2 do code = code[len(code)-2:]
	if code[0] < '0' || code[0] > '9' || code[1] < '0' || code[1] > '9' do return -1
	rc := (int(code[0] - '0')) * 10 + int(code[1] - '0')
	race, sex := rc / 10, rc % 10
	if race <= 2 do return i8((race - 1) * 2 + (sex - 1))
	return i8(race + 1)
}

// Re-resolves the armor appearance per layer against the inventory's
// equipment. Cheap per frame (map lookups; the model path is only built on
// change): equipment swaps re-dress the avatar on the next update.
chara_avatar_sync_armor :: proc(av: ^Chara_Avatar, inv: ^Inventory) {
	if av == nil || av.cm == nil do return
	slots := [CHARA_ARMOR_LAYER_COUNT]EQUIP_SLOT {
		.HELMET, .ARMOR, .LEGS, .GLOVES, .BOOTS, .BACK,
	}
	for layer in 0..<CHARA_ARMOR_LAYER_COUNT {
		sid, part := 0, 0
		it := &inv.equipment[int(slots[layer])]
		if it.item_id_len > 0 {
			if def, ok := item_def(item_id_string(it)); ok {
				sid = def.armor_sid
				part = int(def.armor_part)
			}
		}
		if sid == av.armor_sids[layer] && part == av.armor_parts[layer] do continue
		av.armor_sids[layer] = sid
		av.armor_parts[layer] = part
		av.armor_models[layer] = nil
		av.armor_rigid[layer] = false
		if sid > 0 {
			path := fmt.tprintf("item/EM_%06d_%02d_%s.glb", sid, part, av.cm.id)
			av.armor_models[layer] = held_model_acquire(path)
			av.armor_rigid[layer] = part == 1
			if av.armor_models[layer] != nil {
				rl.TraceLog(.INFO, "chara: %s armor layer %d ← %s",
					assets_cstring(av.cm.id), layer, assets_cstring(path))
			}
		}
	}

	// Body-region replacement: hide the default-outfit meshes that equipped
	// layers replace (the pieces carry their own arms/legs — drawing both is
	// the double-limb clipping).
	hide_hair := false
	if av.armor_models[int(Chara_Armor_Layer.HELMET)] != nil {
		it := &inv.equipment[int(EQUIP_SLOT.HELMET)]
		if it.item_id_len > 0 {
			if def, ok := item_def(item_id_string(it)); ok {
				// Helmet hair override (item.csv cols 39..46): the helmet
				// REPLACES the hair with a helmet-fit style. We bake only the
				// full (variant-0) hair, so a nonzero override hides the hair
				// instead of letting it clip through the helmet.
				if ri := chara_race_index(av.cm.id); ri >= 0 && ri < 8 {
					hide_hair = def.hair_override[ri] != 0
				}
			}
		}
	}
	chara_avatar_refresh_body_hidden(av, hide_hair)
}

// Re-resolves the SHIELD slot's appearance: the item's rigid glb (EM part 22,
// race-independent — one file serves every race). Always drawn, sheathed or
// not, on the left-arm socket.
chara_avatar_sync_shield :: proc(av: ^Chara_Avatar, inv: ^Inventory) {
	if av == nil do return
	shield: ^Model_Entry
	sit := &inv.equipment[int(EQUIP_SLOT.SHIELD)]
	if sit.item_id_len > 0 {
		if def, ok := item_def(item_id_string(sit)); ok && len(def.model) > 0 {
			shield = held_model_acquire(def.model)
		}
	}
	av.shield_model = shield
}

// Recomputes av.body_hidden from the currently resolved armor layers.
chara_avatar_refresh_body_hidden :: proc(av: ^Chara_Avatar, hide_hair: bool) {
	if av == nil || av.cm == nil do return
	if len(av.body_hidden) != int(av.sub.model.meshCount) do return
	hide: u8 = 0
	if hide_hair do hide |= 1 << u8(Body_Region.Hair)
	for layer in 0..<CHARA_ARMOR_LAYER_COUNT {
		if av.armor_models[layer] != nil {
			hide |= chara_layer_body_region_mask(Chara_Armor_Layer(layer))
		}
	}
	for i in 0..<len(av.body_hidden) {
		region := Body_Region.None
		bi := av.sub.base_mesh[i]
		if bi >= 0 && int(bi) < len(av.cm.mesh_region) {
			region = Body_Region(av.cm.mesh_region[bi])
		}
		av.body_hidden[i] = region != .None &&
			(hide & (1 << u8(region))) != 0
	}
}

// Poses ONE skinned armor layer against the avatar's current clip — the same
// delta form raylib computes in UpdateModelAnimation (boneMatrices =
// pose·bind⁻¹, pose FIRST: Odin `*` mirrors raylib's MatrixMultiply argument
// order) — but the current pose comes from the WEARER's rig, by bone name,
// and the bind term is the WEARER's bind too (bind⁻¹·pose instead flings
// every vertex whose pose deviates from bind: arms → the horizontal pauldron
// wings). Several armor glbs bake a POSED skeleton as their bind (Fornid
// cuisses: splayed A-legs under a straight-authored mesh), so the armor's own
// bindPose can't be trusted — the meshes were skinned against the one master
// skeleton the characters use, which is exactly the wearer's bindPose.
//
// Called at draw time (chara_avatar_draw_armor): armor pieces are cached per
// sid+race and share their vertex buffers across every wearer, so each draw
// must re-skin with its own avatar's pose or the last updater wins.
chara_pose_armor_layer :: proc(av: ^Chara_Avatar, layer: int) {
	if av == nil || av.cm == nil do return
	if av.armor_rigid[layer] do return
	e := av.armor_models[layer]
	if e == nil do return
	base := &av.cm.entry.model
	if base.currentPose == nil do return
	m := &e.model
	remap := chara_armor_remap(e, av.cm)
	n_cur := int(base.skeleton.boneCount)
	for b in 0..<int(m.skeleton.boneCount) {
		if b >= len(remap) do break
		ci := remap[b]
		if ci < 0 || ci >= n_cur do continue // defense: bone stays identity
		m.boneMatrices[b] = chara_pose_matrix(base.currentPose[ci]) *
			rl.MatrixInvert(chara_pose_matrix(base.skeleton.bindPose[ci]))
	}
	chara_skin_model_cpu(m)
}

// Poses every equipped skinned armor layer with the avatar's current clip.
// The live pipeline poses per layer inside chara_avatar_draw_armor instead —
// this remains for tools, which set an explicit pose then draw.
chara_avatar_update_armor :: proc(av: ^Chara_Avatar) {
	if av == nil do return
	for layer in 0..<CHARA_ARMOR_LAYER_COUNT do chara_pose_armor_layer(av, layer)
}

// Armor glbs carry MORE bones than the character models (the N50..N62 grip
// sockets + extra dummies: 111 vs 90) and a different joint order from index
// 20 on, so UpdateModelAnimation can never be applied to them — it indexes
// the character animation's pose arrays with the armor's bone indices,
// reading out of bounds past 90 and mismatching names below that (the
// stretched-flat-legs bug). Instead: pose each armor bone against the
// character's blended global pose matched BY NAME, falling back to the
// nearest shared ancestor (sockets N5x → their hand bone), then skin exactly
// like raylib's CPU path. armor sid→race file names make entries single-race
// users, so one remap per Model_Entry is sound.
armor_remap_cache: map[^Model_Entry][]int

chara_armor_remap :: proc(e: ^Model_Entry, cm: ^Chara_Model) -> []int {
	if r, ok := armor_remap_cache[e]; ok do return r
	base := &cm.entry.model
	n_a := int(e.model.skeleton.boneCount)
	n_c := int(base.skeleton.boneCount)
	remap := make([]int, n_a)
	if n_a > 0 && n_c > 0 {
		name_to_c := make(map[string]int, n_c)
		for i in 0..<n_c {
			name_to_c[chara_bone_name(&base.skeleton.bones[i])] = i
		}
		for i in 0..<n_a {
			remap[i] = 0
			j := i
			for depth := 0; j >= 0 && depth < n_a; depth += 1 {
				if ci, ok := name_to_c[chara_bone_name(&e.model.skeleton.bones[j])]; ok {
					remap[i] = ci
					break
				}
				j = int(e.model.skeleton.bones[j].parent)
			}
		}
		delete(name_to_c)
	}
	armor_remap_cache[e] = remap
	return remap
}

// CPU skinning, a faithful port of raylib's UpdateModelAnimationVertexBuffers
// (rmodels.c): animVertex = bindVertex · boneMatrices[boneIndex], normals via
// transposed inverse bone matrices, then position/normal VBOs re-uploaded.
// On GPU-skinning builds animVertices is nil and every mesh is skipped, the
// draw path picks the boneMatrices up instead — both builds behave.
chara_skin_model_cpu :: proc(model: ^rl.Model) {
	normal_mats: [256]rl.Matrix
	normals_ready := false
	for mi in 0..<int(model.meshCount) {
		mesh := &model.meshes[mi]
		if mesh.boneIndices == nil || mesh.boneWeights == nil || mesh.animVertices == nil do continue
		normals_ok := mesh.normals != nil && mesh.animNormals != nil
		if normals_ok && !normals_ready {
			for b in 0..<int(model.skeleton.boneCount) {
				if b >= len(normal_mats) do break
				normal_mats[b] = rl.MatrixTranspose(rl.MatrixInvert(model.boneMatrices[b]))
			}
			normals_ready = true
		}
		bone_counter := 0
		for v in 0..<int(mesh.vertexCount) {
			for k in 0..<3 do mesh.animVertices[v * 3 + k] = 0
			if normals_ok {
				for k in 0..<3 do mesh.animNormals[v * 3 + k] = 0
			}
			for j4 := 0; j4 < 4; j4 += 1 {
				w := mesh.boneWeights[bone_counter]
				bi := int(mesh.boneIndices[bone_counter])
				bone_counter += 1
				if w == 0 do continue
				av := rl.Vector3Transform(
					{mesh.vertices[v * 3], mesh.vertices[v * 3 + 1], mesh.vertices[v * 3 + 2]},
					model.boneMatrices[bi])
				mesh.animVertices[v * 3 + 0] += av.x * w
				mesh.animVertices[v * 3 + 1] += av.y * w
				mesh.animVertices[v * 3 + 2] += av.z * w
				if normals_ok {
					an := rl.Vector3Transform(
						{mesh.normals[v * 3], mesh.normals[v * 3 + 1], mesh.normals[v * 3 + 2]},
						normal_mats[bi])
					mesh.animNormals[v * 3 + 0] += an.x * w
					mesh.animNormals[v * 3 + 1] += an.y * w
					mesh.animNormals[v * 3 + 2] += an.z * w
				}
			}
		}
		if mesh.vboId != nil {
			rlgl.UpdateVertexBuffer(mesh.vboId[0], rawptr(mesh.animVertices), mesh.vertexCount * 3 * 4, 0)
			if normals_ok {
				rlgl.UpdateVertexBuffer(mesh.vboId[2], rawptr(mesh.animNormals), mesh.vertexCount * 3 * 4, 0)
			}
		}
	}
}

// Draws the avatar's body subset mesh by mesh, skipping the body regions the
// equipped armor replaces (av.body_hidden — see chara_avatar_sync_armor).
// Composes the exact transform DrawModelEx would (T·R(yaw+offset)·S, column
// convention) and mirrors its tint handling.
chara_avatar_draw_body :: proc(av: ^Chara_Avatar, position: rl.Vector3, yaw_rad: f32, tint: rl.Color) {
	if av == nil do return
	// Pose the shared race model with THIS avatar's clip immediately before
	// drawing — the CPU-skinned vertex buffers (and currentPose) belong to
	// the one cached model per race, so pose+draw must be adjacent for every
	// avatar on screen (same trick as monster_model_draw and the mount). All
	// socket reads for this avatar (held item, shield, rigid helmet) must
	// happen after this call.
	chara_apply_current_pose(av, av.sub.model)
	axis, angle := euler_y_to_raylib(yaw_rad)
	m := rl.MatrixTranslate(position.x, position.y + av.lift, position.z) *
		rl.MatrixRotate(axis, (angle + AVATAR_YAW_OFFSET_DEG) * 0.017453293) *
		rl.MatrixScale(av.scale, av.scale, av.scale)
	for i in 0..<int(av.sub.model.meshCount) {
		if i < len(av.body_hidden) && av.body_hidden[i] do continue
		mat := &av.sub.model.materials[av.sub.model.meshMaterial[i]]
		albedo := int(rl.MaterialMapIndex.ALBEDO)
		diffuse := mat.maps[albedo].color
		mat.maps[albedo].color = rl.Color{
			u8((int(diffuse.r) * int(tint.r)) / 255),
			u8((int(diffuse.g) * int(tint.g)) / 255),
			u8((int(diffuse.b) * int(tint.b)) / 255),
			u8((int(diffuse.a) * int(tint.a)) / 255),
		}
		rl.DrawMesh(av.sub.model.meshes[i], mat^, m)
		mat.maps[albedo].color = diffuse
	}
}

// Draws the equipped armor pieces. Skinned pieces share the body's exact
// model transform; the rigid helmet composes the head bone's full
// pose·bind⁻¹ delta around the mesh's bind-space park→head translation.
// The meshes are authored upright near the origin (parked at the feet in
// the source packages), so applying the raw head frame laid them sideways,
// and position-only attach kept them level but stranded them when the head
// rotates away from bind (run: forehead sliding out of the helm). The delta
// is identical to position-only at bind and tracks the skull otherwise.
chara_avatar_draw_armor :: proc(av: ^Chara_Avatar, position: rl.Vector3, yaw_rad: f32, tint: rl.Color) {
	if av == nil do return
	axis, angle := euler_y_to_raylib(yaw_rad)
	for layer in 0..<CHARA_ARMOR_LAYER_COUNT {
		e := av.armor_models[layer]
		if e == nil do continue
		if av.armor_rigid[layer] {
			pose, ok := chara_avatar_bone_matrix(av, CHARA_HEAD_BONE)
			bind, ok2 := chara_avatar_bone_bind_matrix(av, CHARA_HEAD_BONE)
			if !ok || !ok2 do continue
			bind_t := rl.Vector3Transform({0, 0, 0}, bind)
			m := rl.MatrixTranslate(position.x, position.y + av.lift, position.z) *
				rl.MatrixRotate({0, 1, 0}, yaw_rad + AVATAR_YAW_OFFSET_DEG * 0.017453293)
			m = m * rl.MatrixScale(av.scale, av.scale, av.scale)
			m = m * (pose * rl.MatrixInvert(bind) *
				rl.MatrixTranslate(bind_t.x, bind_t.y, bind_t.z))
			for i in 0..<int(e.model.meshCount) {
				rl.DrawMesh(e.model.meshes[i], e.model.materials[int(e.model.meshMaterial[i])], m)
			}
		} else {
			// Re-skin the shared piece with THIS avatar's pose right before
			// its draw — pieces are cached per sid+race, so two wearers of
			// the same gear would otherwise share whoever skinned last.
			chara_pose_armor_layer(av, layer)
			rl.DrawModelEx(e.model,
				{position.x, position.y + av.lift, position.z},
				axis, angle + AVATAR_YAW_OFFSET_DEG, {av.scale, av.scale, av.scale}, tint)
		}
	}
}

// Draws the left-arm shield. Always visible — drawn weapon or sheathed —
// bolted to the left forearm socket (CHARA_SOCKET_SHIELD). Rigid single
// mesh, drawn untinted like the helmet path.
chara_avatar_draw_shield :: proc(av: ^Chara_Avatar, position: rl.Vector3, yaw_rad: f32) {
	if av == nil || av.shield_model == nil do return
	chara_tuning_tick() // pick up sheath_tuning.json "shield" edits ~2x/second
	seat := chara_shield_seat()
	if chara_debug_shield_on {
		seat.t = chara_debug_shield_t
		seat.q = chara_debug_shield_q
	}
	attach, ok := chara_avatar_socket_matrix(av, seat)
	if !ok do return
	m := chara_held_base_matrix(av, position, yaw_rad, 1.0) * attach
	draw_held_meshes(av.shield_model, m)
}
