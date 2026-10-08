package bone_test

// Worn-armor repro/verification: pose the Striker trousers glb through the
// name-mapped path (chara_armor_remap + boneMatrices + chara_skin_model_cpu)
// and check the skinned bounds stay body-scale. The index-based path
// (UpdateModelAnimation with the chara anim) read out of bounds past 90 bones
// and mismatched joint names from index 20 — the stretched-flat-legs bug.

import "core:c"
import "core:fmt"
import "core:math"
import "core:strings"
import rl "vendor:raylib"
import sys "../systems"

armor_repro :: proc(race: string, armor_glb: string) {
	fmt.eprintfln("armor repro: race %s armor %s", race, armor_glb)
	cm := sys.chara_model_acquire(race)
	if cm == nil {
		fmt.eprintfln("  acquire %s FAILED", race)
		return
	}
	defer sys.chara_model_release(cm)

	if cm.idle_anim >= 0 {
		rl.UpdateModelAnimation(cm.entry.model, cm.anims[cm.idle_anim], 0)
	}
	if cm.entry.model.currentPose == nil {
		fmt.eprintfln("  no currentPose on base model")
		return
	}

	e := sys.held_model_acquire(armor_glb)
	if e == nil {
		fmt.eprintfln("  armor acquire FAILED")
		return
	}
	m := &e.model
	fmt.eprintfln("  armor bones=%d chara bones=%d",
		int(m.skeleton.boneCount), int(cm.entry.model.skeleton.boneCount))

	remap := sys.chara_armor_remap(e, cm)
	bad := 0
	for i in 0..<len(remap) {
		ci := remap[i]
		if ci < 0 || ci >= int(cm.entry.model.skeleton.boneCount) {
			bad += 1
			if bad <= 6 {
				nm := sys.chara_bone_name(&m.skeleton.bones[i])
				fmt.eprintfln("    BAD remap[%d] (%s) = %d", i, nm, ci)
			}
		}
	}
	fmt.eprintfln("  remap: %d entries, %d out-of-range", len(remap), bad)
	// spot checks: socket bones must land on their hand bones
	for i in 0..<int(m.skeleton.boneCount) {
		nm := sys.chara_bone_name(&m.skeleton.bones[i])
		if nm == "N56" || nm == "N52" {
			target := sys.chara_bone_name(&cm.entry.model.skeleton.bones[remap[i]])
			fmt.eprintfln("  socket %s -> chara %s", nm, target)
		}
	}

	for b in 0..<int(m.skeleton.boneCount) {
		if b >= len(remap) do break
		m.boneMatrices[b] = rl.MatrixInvert(sys.chara_pose_matrix(m.skeleton.bindPose[b])) *
			sys.chara_pose_matrix(cm.entry.model.currentPose[remap[b]])
	}
	sys.chara_skin_model_cpu(m)

	for mi in 0..<int(m.meshCount) {
		mesh := &m.meshes[mi]
		if mesh.vertexCount <= 0 do continue
		if mesh.animVertices == nil {
			fmt.eprintfln("  mesh[%d]: %d verts, GPU-skinning build (animVertices nil) — boneMatrices path",
				mi, int(mesh.vertexCount))
			continue
		}
		minv := rl.Vector3{1e9, 1e9, 1e9}
		maxv := rl.Vector3{-1e9, -1e9, -1e9}
		v := mesh.animVertices[:int(mesh.vertexCount) * 3]
		for k in 0..<len(v) / 3 {
			x, y, z := v[k * 3], v[k * 3 + 1], v[k * 3 + 2]
			if x < minv.x do minv.x = x
			if y < minv.y do minv.y = y
			if z < minv.z do minv.z = z
			if x > maxv.x do maxv.x = x
			if y > maxv.y do maxv.y = y
			if z > maxv.z do maxv.z = z
		}
		ext := math.max(maxv.x - minv.x, math.max(maxv.y - minv.y, maxv.z - minv.z))
		fmt.eprintfln("  mesh[%d]: %d verts skinned bounds (%.2f,%.2f,%.2f)-(%.2f,%.2f,%.2f) max-extent %.2fm %s",
			mi, int(mesh.vertexCount),
			minv.x, minv.y, minv.z, maxv.x, maxv.y, maxv.z, ext,
			ext < 3.0 ? "OK" : "*** STRETCHED ***")
	}
}
