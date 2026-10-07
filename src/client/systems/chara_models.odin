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
			if _, dup := cm.clips[code]; !dup do cm.clips[code] = i
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
	hair_maps: [dynamic][]rl.MaterialMap, // freshly allocated material maps
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
	attack_cycle: int,  // swings played — cycles the family's attack_1/2/3
	combat_idle:  int,  // weapon drawn idle (xx01) while fighting, -1 = none
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
	av.combat_idle = -1
	av.applied_clip = -1
	av.blend_from = -1
	return av
}

// Clip codes are the numeric suffix on each animation name
// (CA_00_011_00_000_0071 -> "0071") and are consistent across all character
// models — the shared semantic namespace. Gameplay slots reference codes;
// `cm.clips` resolves them to indices in O(1).
CLIP_CODE_IDLE            :: "0001"
CLIP_CODE_WALK            :: "0015"
CLIP_CODE_RUN             :: "0018"
CLIP_CODE_CAST_LOOP       :: "0071"
CLIP_CODE_CAST_END        :: "0072"
CLIP_CODE_CAST_END_ATTACK :: "0073"

// Auto-attack clip codes per weapon kind: every family animates its basic
// swings as three ..._drawn_attack one-shots (codes f055/f056/f057). The
// castable families are shared by the whole castable weapon set — 1h sword,
// club, wand and axe ride 1h_castable; 2h rod and hammer ride 2h_castable.
// The remaining kinds map to their like-named family (2h axe has no family of
// its own and borrows the 2h_hammer swings). No weapon falls back to unarmed.
Chara_Weapon_Family :: struct {
	idle:               string, // weapon drawn idle (xx01)
	a1, a2, a3:         string, // basic swings (xx55..xx57)
	cast_start:         string, // cast channel loop; "" ⇒ family has none
	cast_finish:        string, // buff/debuff cast finish
	cast_finish_attack: string, // attack cast finish
}

chara_weapon_family :: proc(kind: Weapon_Kind) -> (f: Chara_Weapon_Family) {
	switch kind {
	case .DAGGER:           return {idle = "1101", a1 = "1155", a2 = "1156", a3 = "1157"}
	case .SWORD, .AXE, .BLUNT, .WAND:
	                        return {idle = "1201", a1 = "1255", a2 = "1256", a3 = "1257",
	                                cast_start = "1271", cast_finish = "1272", cast_finish_attack = "1273"}
	case .SPEAR:            return {idle = "1301", a1 = "1355", a2 = "1356", a3 = "1357"}
	case .TWO_HANDED_SWORD: return {idle = "1401", a1 = "1455", a2 = "1456", a3 = "1457"}
	case .TWO_HANDED_AXE:   return {idle = "1501", a1 = "1555", a2 = "1556", a3 = "1557"}
	case .TWO_HANDED_SPEAR: return {idle = "1601", a1 = "1655", a2 = "1656", a3 = "1657"}
	case .STAFF, .TWO_HANDED_BLUNT:
	                        return {idle = "1701", a1 = "1755", a2 = "1756", a3 = "1757",
	                                cast_start = "1771", cast_finish = "1772", cast_finish_attack = "1773"}
	case .BOW:              return {idle = "1801", a1 = "1855", a2 = "1856", a3 = "1857"}
	case .CROSSBOW:         return {idle = "1901", a1 = "1955", a2 = "1956", a3 = "1957"}
	case .KNUCKLES:         return {idle = "2001", a1 = "2055", a2 = "2056", a3 = "2057"}
	case .NONE:             return {idle = "1001", a1 = "1055", a2 = "1056", a3 = "1057"}
	}
	return {idle = "1001", a1 = "1055", a2 = "1056", a3 = "1057"} // unreachable: every kind covered
}

chara_clip :: proc(cm: ^Chara_Model, code: string) -> int {
	if cm == nil do return -1
	idx, ok := cm.clips[code]
	if !ok do return -1
	return idx
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
	av.anim_time = 0
	av.current_clip = -1 // movement clip restarts fresh after the action
}

// Tracks the equipped weapon's animation family so combat idles use the
// family drawn idle (xx01) instead of the neutral stance. Cheap enough to
// call every frame (one map lookup) — equipment swaps then apply instantly.
chara_avatar_set_weapon_kind :: proc(av: ^Chara_Avatar, kind: Weapon_Kind) {
	if av == nil do return
	fam := chara_weapon_family(kind)
	av.combat_idle = chara_clip(av.cm, fam.idle)
}

chara_avatar_stop_action :: proc(av: ^Chara_Avatar) {
	if av == nil do return
	av.action_clip = -1
	av.anim_time = 0
}

// Plays one weapon attack swing on the avatar: the kind's family clips from
// chara_weapon_family, cycled 1→2→3 across consecutive swings. Clips the
// model lacks are skipped (the bow/crossbow sets ship only attack_1/2);
// no-op when the model has none of the family's clips at all.
chara_avatar_play_attack :: proc(av: ^Chara_Avatar, kind: Weapon_Kind) {
	if av == nil do return
	fam := chara_weapon_family(kind)
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

chara_avatar_destroy :: proc(av: ^Chara_Avatar) {
	if av == nil do return
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
	chara_subset_free(&av.sub)
	chara_model_release(av.cm)
	free(av)
}

// Advances the avatar's animation for one frame toward `clip` — toward the
// weapon drawn idle instead while `combat` — blending across clip changes,
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
		#partial switch clip {
		case .WALK:
			if av.cm.walk_anim >= 0 do clip_idx = av.cm.walk_anim
		case .RUN:
			if av.cm.run_anim >= 0 do clip_idx = av.cm.run_anim
		case .IDLE:
			// In combat the character holds the weapon family's drawn stance.
			if combat && av.combat_idle >= 0 do clip_idx = av.combat_idle
		case:
		}
		if clip_idx != av.current_clip {
			av.current_clip = clip_idx
			av.anim_time = 0
		} else {
			av.anim_time += f64(dt)
		}
	} else {
		av.anim_time += f64(dt)
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
			if av.blend_t < CHARA_BLEND_TIME {
				rl.UpdateModelAnimationEx(av.sub.model,
					av.cm.anims[av.blend_from], av.blend_frame,
					anim^, frame, av.blend_t / CHARA_BLEND_TIME)
			} else {
				blending = false
			}
		}
		if !blending {
			av.blend_from = -1
			rl.UpdateModelAnimation(av.sub.model, anim^, frame)
		}
		av.applied_clip = clip_idx
		av.applied_frame = frame
	}

	if !av.measured {
		av.measured = true
		b := chara_skin_bounds(av.cm, &av.sub.model)
		av.lift = -b.min.y * av.scale
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
// re-points at them), so this reads the pose of whichever avatar updated
// last. True for the local player — update_local_avatar runs after the scene
// update — which is the only holder today. Remote held items will need a
// per-avatar pose snapshot.

CHARA_HAND_BONE :: "Bip01 R Hand"

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

// Draw a held-item model (weapons — see items.odin held_model_for_item)
// attached to the avatar's right-hand bone. The world matrix mirrors what
// DrawModelEx gives the avatar (avatar scale, yaw + the +Z-pipeline 180°
// offset, position+lift) composed around the bone's model-space attach
// matrix and the N52 grip seat, column-vector style: (T·R·S·bone·grip)·v —
// the grip applies first, the way the engine bolts items onto N-bones.
chara_avatar_draw_held :: proc(
	av:        ^Chara_Avatar,
	entry:     ^Model_Entry,
	position:  rl.Vector3,
	yaw_rad:   f32,
	tint:      rl.Color,
) {
	if av == nil || entry == nil do return
	bone, ok := chara_avatar_bone_matrix(av, CHARA_HAND_BONE)
	if !ok do return

	m := rl.MatrixTranslate(position.x, position.y + av.lift, position.z) *
		rl.MatrixRotate({0, 1, 0}, yaw_rad + AVATAR_YAW_OFFSET_DEG * 0.017453293)
	m = m * rl.MatrixScale(av.scale, av.scale, av.scale)
	m = m * bone
	m = m * chara_grip_matrix(false)

	for i in 0..<int(entry.model.meshCount) {
		mat_idx := int(entry.model.meshMaterial[i])
		rl.DrawMesh(entry.model.meshes[i], entry.model.materials[mat_idx], m)
	}
}
