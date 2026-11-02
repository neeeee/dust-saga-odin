package matprobe

// Probe: what does the shipped raylib.dll put in Model.meshMaterial /
// materialCount for a GLB — per-primitive slots (old) or gltf material
// index + 1 (new)? Prints stats to decide the alpha-mode indexing scheme.
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

main :: proc() {
	rl.SetTraceLogLevel(.ERROR)
	rl.SetConfigFlags({rl.ConfigFlag.WINDOW_HIDDEN})
	rl.InitWindow(320, 240, "matprobe")
	defer rl.CloseWindow()

	paths := [?]string{
		"assets/maps/map_T01_01.glb",
		"assets/maps/map_F05_01.glb",
		"assets/maps/map_D01_01.glb",
	}
	for path in paths {
		model := rl.LoadModel(strings.clone_to_cstring(path, context.temp_allocator))
		fmt.printfln("%s: meshCount=%v materialCount=%v", path, model.meshCount, model.materialCount)
		n := int(model.meshCount)
		if n > 0 && model.meshMaterial != nil {
			mm := model.meshMaterial[:]
			slots := map[int]int{}
			mono := true
			prev := -1
			for i in 0 ..< n {
				m := int(mm[i])
				slots[m] += 1
				if m <= prev {
					mono = false
				}
				prev = m
			}
			fmt.printfln(
				"  meshMaterial distinct=%v monotonic=%v first10=%v",
				len(slots),
				mono,
				mm[:min(n, 10)],
			)
			items := 0
			for k, v in slots {
				if items >= 10 {
					break
				}
				fmt.printfln("    slot %v: %v meshes", k, v)
				items += 1
			}
		}
		rl.UnloadModel(model)
	}
}
