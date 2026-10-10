package bone_test

// Bisect why the striker TORSO glb draws nothing in the avatar path while
// the legs glb (same texture, same 112-joint skeleton) draws fine.
// Shots: raw bind pose → culling off → mesh0 only → mesh1 only.

import "core:fmt"
import rl "vendor:raylib"
import sys "../systems"
import rlgl "vendor:raylib/rlgl"

torso_draw_probe :: proc() {
	rl.InitWindow(640, 720, "torso_draw_probe")
	defer rl.CloseWindow()

	entry := sys.held_model_acquire("item/EM_012211_02_022.glb")
	if entry == nil {
		fmt.eprintfln("probe: acquire FAILED")
		return
	}
	m := &entry.model
	fmt.eprintfln("probe: meshes=%d bones=%d", m.meshCount, m.skeleton.boneCount)

	// control: the legs glb through the identical raw path
	legs := sys.held_model_acquire("item/EM_013211_03_022.glb")

	// raw CPU vertex bounds per mesh, both files
	for mi in 0..<int(m.meshCount) {
		mesh := &m.meshes[mi]
		minv := rl.Vector3{1e9, 1e9, 1e9}
		maxv := rl.Vector3{-1e9, -1e9, -1e9}
		for v in 0..<int(mesh.vertexCount) {
			minv.x = min(minv.x, mesh.vertices[v*3]); minv.y = min(minv.y, mesh.vertices[v*3+1]); minv.z = min(minv.z, mesh.vertices[v*3+2])
			maxv.x = max(maxv.x, mesh.vertices[v*3]); maxv.y = max(maxv.y, mesh.vertices[v*3+1]); maxv.z = max(maxv.z, mesh.vertices[v*3+2])
		}
		fmt.eprintfln("probe: torso mesh%d vao=%d vbo0=%d verts=%d tris=%d vertsBounds (%.2f,%.2f,%.2f)-(%.2f,%.2f,%.2f)",
			mi, mesh.vaoId, mesh.vboId != nil ? mesh.vboId[0] : 0, mesh.vertexCount, mesh.triangleCount,
			minv.x, minv.y, minv.z, maxv.x, maxv.y, maxv.z)
	}
	if legs != nil {
		lm := &legs.model
		for mi in 0..<int(lm.meshCount) {
			mesh := &lm.meshes[mi]
			minv := rl.Vector3{1e9, 1e9, 1e9}
			maxv := rl.Vector3{-1e9, -1e9, -1e9}
			for v in 0..<int(mesh.vertexCount) {
				minv.x = min(minv.x, mesh.vertices[v*3]); minv.y = min(minv.y, mesh.vertices[v*3+1]); minv.z = min(minv.z, mesh.vertices[v*3+2])
				maxv.x = max(maxv.x, mesh.vertices[v*3]); maxv.y = max(maxv.y, mesh.vertices[v*3+1]); maxv.z = max(maxv.z, mesh.vertices[v*3+2])
			}
			fmt.eprintfln("probe: legs  mesh%d vao=%d vbo0=%d verts=%d tris=%d vertsBounds (%.2f,%.2f,%.2f)-(%.2f,%.2f,%.2f)",
				mi, mesh.vaoId, mesh.vboId != nil ? mesh.vboId[0] : 0, mesh.vertexCount, mesh.triangleCount,
				minv.x, minv.y, minv.z, maxv.x, maxv.y, maxv.z)
		}
	}

	cam := rl.Camera3D{
		position   = {0, 1.2, -2.2},
		target     = {0, 0.95, 0},
		up         = {0, 1, 0},
		fovy       = 45,
		projection = .PERSPECTIVE,
	}

	begin :: proc(cam: rl.Camera3D) {
		rl.BeginDrawing()
		rl.ClearBackground({168, 178, 200, 255})
		rl.BeginMode3D(cam)
	}
	end :: proc(fname: string) {
		rl.EndMode3D()
		rl.TakeScreenshot(strings_clone_to_cstring_shot(fname))
		rl.EndDrawing()
		fmt.eprintfln("probe: wrote %s", fname)
	}

	// 1: raw bind pose — torso, then legs as control
	begin(cam)
	rl.DrawModelEx(m^, {0, 0, 0}, {0, 1, 0}, 180, {1, 1, 1}, rl.WHITE)
	end("probe_raw.png")

	if legs != nil {
		begin(cam)
		rl.DrawModelEx(legs.model, {0, 0, 0}, {0, 1, 0}, 180, {1, 1, 1}, rl.WHITE)
		end("probe_raw_legs.png")
	}

	// 2: culling off
	begin(cam)
	rlgl.DisableBackfaceCulling()
	rl.DrawModelEx(m^, {0, 0, 0}, {0, 1, 0}, 180, {1, 1, 1}, rl.WHITE)
	rlgl.EnableBackfaceCulling()
	end("probe_nocull.png")

	// 3/4: per-mesh with per-mesh materials
	for mi in 0..<int(m.meshCount) {
		begin(cam)
		mat := m.materials[m.meshMaterial[mi]]
		rl.DrawMesh(m.meshes[mi], mat, rl.MatrixRotate({0, 1, 0}, 180 * 0.017453293))
		end(fmt.tprintf("probe_mesh%d.png", mi))
	}
}
