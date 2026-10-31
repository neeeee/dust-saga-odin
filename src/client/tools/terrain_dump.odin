package terrain_dump

// Diagnostic: loads a zone and dumps every terrain mesh's raylib CPU AABB,
// material slot, vertex count and degenerate flag as CSV/lines to stdout.
// Usage: terrain_dump [zone_id]
import "core:fmt"
import "core:os"
import rl "vendor:raylib"
import sys "../systems"

main :: proc() {
	rl.SetTraceLogLevel(.ERROR)
	rl.SetConfigFlags({rl.ConfigFlag.WINDOW_HIDDEN})
	rl.InitWindow(320, 240, "terrain dump")
	defer rl.CloseWindow()

	zone_id := "1001004"
	args := os.args
	if len(args) > 1 do zone_id = args[1]

	zone := sys.load_zone_map(zone_id)
	defer sys.zone_destroy(zone)
	model := zone.terrain.model

	for i in 0..<int(model.meshCount) {
		mesh := model.meshes[i]
		box := rl.GetMeshBoundingBox(mesh)
		mat := model.meshMaterial[i]
		r := max(box.max.x - box.min.x, max(box.max.y - box.min.y, box.max.z - box.min.z))
		degenerate := r <= 0.001 && mesh.vertexCount > 0
		fmt.eprintfln("mesh %v mat %v verts=%v tris=%v size=(%.2f,%.2f,%.2f) center=(%.1f,%.1f,%.1f)%v",
			i, mat, mesh.vertexCount, mesh.vertexCount / 3,
			box.max.x - box.min.x, box.max.y - box.min.y, box.max.z - box.min.z,
			(box.min.x + box.max.x) * 0.5, (box.min.y + box.max.y) * 0.5, (box.min.z + box.max.z) * 0.5,
			degenerate ? "  <-- DEGENERATE POINT MESH" : "")
	}
}
