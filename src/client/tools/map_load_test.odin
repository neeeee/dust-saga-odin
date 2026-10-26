package map_load_test

// Headless smoke test for the Pandora terrain bakes: push every
// assets/maps/map_*.glb through the real raylib loader and report meshes,
// materials, and how many materials got a real (non-default) albedo texture.
// A "textured=0" line means the embedded PNGs didn't decode and the terrain
// would render flat white in-game.

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

names := [?]string{
	"map_D01_01.glb",
	"map_D01_02.glb",
	"map_D01_03.glb",
	"map_D01_04.glb",
	"map_D01_05.glb",
	"map_D01_06.glb",
	"map_E01_01.glb",
	"map_F01.glb",
	"map_F02_01.glb",
	"map_F02_02.glb",
	"map_F02_03.glb",
	"map_F03_01.glb",
	"map_F03_02.glb",
	"map_F03_03.glb",
	"map_F04_01.glb",
	"map_F04_02.glb",
	"map_F04_03.glb",
	"map_F05.glb",
	"map_F06_01.glb",
	"map_F07_01.glb",
	"map_T01_01.glb",
	"map_T01_02.glb",
	"map_T01_03.glb",
	"map_T01_04.glb",
	"map_T02.glb",
	"map_T03.glb",
	"map_T04.glb",
}

main :: proc() {
	rl.SetTraceLogLevel(.WARNING)
	rl.SetConfigFlags({rl.ConfigFlag.WINDOW_HIDDEN})
	rl.InitWindow(320, 240, "map glb load test")
	defer rl.CloseWindow()

	default_tex := rlgl.GetTextureIdDefault()
	failed := 0

	for name in names {
		path := strings.clone_to_cstring(fmt.tprintf("assets/maps/%s", name), context.temp_allocator)
		model := rl.LoadModel(path)
		if model.meshCount == 0 {
			fmt.eprintfln("FAIL %s (meshCount=0)", name)
			failed += 1
			continue
		}

		textured := 0
		for i in 0..<int(model.materialCount) {
			tex := model.materials[i].maps[rl.MaterialMapIndex.ALBEDO].texture
			if tex.id != 0 && tex.id != default_tex do textured += 1
		}

		verts := 0
		for i in 0..<int(model.meshCount) do verts += int(model.meshes[i].vertexCount)

		// Union AABB across meshes — verifies the glTF node transforms are
		// baked into vertices (bounds must match the known world footprints,
		// e.g. T01_01 ≈ x[-216,193] z[-155,259]).
		min := rl.Vector3{1e9, 1e9, 1e9}
		max := rl.Vector3{-1e9, -1e9, -1e9}
		for i in 0..<int(model.meshCount) {
			box := rl.GetMeshBoundingBox(model.meshes[i])
			min = rl.Vector3Min(min, box.min)
			max = rl.Vector3Max(max, box.max)
		}

		status := "OK  "
		if textured == 0 {
			status = "NOTEX"
			failed += 1
		}
		fmt.eprintfln("%s %s meshes=%d mats=%d textured=%d verts=%d aabb=[%.0f,%.0f]x[%.0f,%.0f]y[%.0f,%.0f]",
			status, name, model.meshCount, model.materialCount, textured, verts,
			min.x, max.x, min.y, max.y, min.z, max.z)
		rl.UnloadModel(model)
	}

	if failed > 0 {
		fmt.eprintfln("DONE with %d failures", failed)
	} else {
		fmt.eprintfln("DONE all %d loaded", len(names))
	}
}
