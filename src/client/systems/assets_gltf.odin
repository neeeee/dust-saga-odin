package systems

// GLB metadata parsing: raylib's LoadModel flattens the glTF node graph into
// model.meshes[] (one mesh per node-mesh primitive, depth-first over the
// default scene, parent before children) without keeping node names. Character
// variants are addressed by node name (CM_00_<race>_10_XXX faces,
// CM_00_<race>_11_XXX hairs), so we parse the glb's JSON chunk ourselves and
// rebuild that exact ordering into a node name -> mesh index map.
//
// The map's `total` is the sum of all primitives; it must equal the loaded
// model's meshCount. If it doesn't (a raylib loader change, unsupported
// primitive mode, etc.) the caller must treat the map as unusable and fall
// back to drawing the whole model — never trust a misaligned index map.

import "core:encoding/json"
import "core:os"
import "core:strings"
import rl "vendor:raylib"

Gltf_Mesh_Map :: struct {
	by_node: map[string][]int, // node name -> raylib mesh indices (one per primitive)
	total:   int,              // sum of all primitives; sanity-check against model.meshCount
}

// Extracts the node name -> mesh index map from a .glb file. The map, its
// keys and index slices live on the heap — free with gltf_mesh_map_free.
// Returns ok=false for non-GLB files, unparsable JSON chunks, or missing
// scene/nodes sections.
gltf_read_mesh_map :: proc(path: string) -> (mesh_map: Gltf_Mesh_Map, ok: bool) {
	data, err := os.read_entire_file_from_path(path, allocator = context.allocator)
	if err != nil do return
	defer delete(data)

	if len(data) < 20 || glb_read_u32(data, 0) != 0x46546C67 { // "glTF"
		return
	}
	json_len := glb_read_u32(data, 12)
	json_type := glb_read_u32(data, 16)
	if json_type != 0x4E4F534A || int(20 + json_len) > len(data) { // "JSON"
		return
	}

	root, parsed := json_parse(data[20 : 20 + json_len])
	if !parsed do return
	defer json.destroy_value(root)

	root_obj := obj_of(root)
	nodes_dyn := as_dyn(get_array(root_obj, "nodes"))
	if len(nodes_dyn) == 0 do return
	scenes_dyn := as_dyn(get_array(root_obj, "scenes"))
	if len(scenes_dyn) == 0 do return

	// Per-glTF-mesh primitive counts (each primitive becomes one raylib mesh).
	meshes_dyn := as_dyn(get_array(root_obj, "meshes"))
	mesh_prims := make([]int, len(meshes_dyn))
	defer delete(mesh_prims)
	for i in 0..<len(meshes_dyn) {
		mesh_obj := obj_of(meshes_dyn[i])
		mesh_prims[i] = len(as_dyn(get_array(mesh_obj, "primitives")))
	}

	mesh_map.by_node = make(map[string][]int)
	mesh_map.total = 0

	scene_idx := get_int(root_obj, "scene", 0)
	if scene_idx < 0 || scene_idx >= len(scenes_dyn) do scene_idx = 0
	roots_dyn := as_dyn(get_array(obj_of(scenes_dyn[scene_idx]), "nodes"))

	walker := Gltf_Walker{
		root        = root_obj,
		mesh_prims  = mesh_prims,
		out         = &mesh_map,
	}
	for i in 0..<len(roots_dyn) {
		gltf_walk_node(&walker, int_of(roots_dyn[i]))
	}
	return mesh_map, true
}

Gltf_Walker :: struct {
	root:       JSON_Object,
	mesh_prims: []int,
	out:        ^Gltf_Mesh_Map,
}

// Depth-first, parent mesh before children — the order raylib's glTF loader
// appends raylib meshes in.
gltf_walk_node :: proc(w: ^Gltf_Walker, node_index: int) {
	nodes_dyn := as_dyn(get_array(w.root, "nodes"))
	if node_index < 0 || node_index >= len(nodes_dyn) do return
	node := obj_of(nodes_dyn[node_index])

	mesh_index := field(node, "mesh")
	if !is_null(mesh_index) {
		mi := int_of(mesh_index)
		prims := 0
		if mi >= 0 && mi < len(w.mesh_prims) do prims = w.mesh_prims[mi]
		base := w.out.total
		w.out.total += prims

		name := get_string(node, "name")
		if len(name) > 0 && prims > 0 {
			// Node names repeat across nodes in practice never, but be safe:
			// grow the index run inside the same backing array.
			if entry, ok := w.out.by_node[name]; ok {
				for p in 0..<prims do entry[len(entry) + p] = base + p
				w.out.by_node[name] = entry[:len(entry) + prims]
			} else {
				run := make([]int, prims)
				for p in 0..<prims do run[p] = base + p
				w.out.by_node[strings.clone(name)] = run
			}
		}
	}

	children_dyn := as_dyn(get_array(node, "children"))
	for i in 0..<len(children_dyn) {
		gltf_walk_node(w, int_of(children_dyn[i]))
	}
}

gltf_mesh_map_free :: proc(mesh_map: ^Gltf_Mesh_Map) {
	for key, indices in mesh_map.by_node {
		delete(key)
		delete(indices)
	}
	delete(mesh_map.by_node)
	mesh_map.total = 0
}

glb_read_u32 :: proc(data: []byte, at: int) -> u32 {
	if at + 4 > len(data) do return 0
	return u32(data[at]) | u32(data[at + 1]) << 8 | u32(data[at + 2]) << 16 | u32(data[at + 3]) << 24
}
