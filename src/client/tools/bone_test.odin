package bone_test

// Diagnostic for the held-item attachment (see chara_models.odin). Loads the
// human character model + clips and verifies that TRS(currentPose[hand])
// tracks the deformed hand-vertex centroid — the calibration that proved:
// raylib composes keyframePoses/bindPose into GLOBAL model-space poses at
// load, boneMatrices are LOCAL bind-relative deltas, and this binding is
// COLUMN-vector (Vector3Transform = M·v, translation outermost: T·R·S).
//
// Build & run from src/client (the static vendor raylib.lib crashes on old
// CPUs — link the shipped DLL instead):
//   odin build tools -out:bone_test.exe -define:RAYLIB_SHARED=true -extra-linker-flags:"/NODEFAULTLIB:msvcrt"
//   ./bone_test.exe

import "core:c"
import "core:math"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"
import sys "../systems"

cstr :: proc(s: string) -> cstring {
	return strings.clone_to_cstring(s, context.temp_allocator)
}

bone_name :: proc(b: ^rl.BoneInfo) -> string {
	for i in 0..<len(b.name) {
		if b.name[i] == 0 do return string(b.name[:i])
	}
	return string(b.name[:])
}

anim_name :: proc(a: ^rl.ModelAnimation) -> string {
	for i in 0..<len(a.name) {
		if a.name[i] == 0 do return string(a.name[:i])
	}
	return string(a.name[:])
}

transform_matrix :: proc(t: rl.Transform) -> rl.Matrix {
	return rl.MatrixTranslate(t.translation.x, t.translation.y, t.translation.z) *
		(rl.QuaternionToMatrix(t.rotation) * rl.MatrixScale(t.scale.x, t.scale.y, t.scale.z))
}

print_matrix :: proc(label: string, m: rl.Matrix) {
	fmt.eprintfln("%s: %f %f %f %f / %f %f %f %f / %f %f %f %f / %f %f %f %f",
		label,
		m[0, 0], m[0, 1], m[0, 2], m[0, 3],
		m[1, 0], m[1, 1], m[1, 2], m[1, 3],
		m[2, 0], m[2, 1], m[2, 2], m[2, 3],
		m[3, 0], m[3, 1], m[3, 2], m[3, 3])
	origin := rl.Vector3Transform({0, 0, 0}, m)
	x := rl.Vector3Transform({1, 0, 0}, m)
	fmt.eprintfln("%s: origin->(%f,%f,%f)  +x->(%f,%f,%f)",
		label, origin.x, origin.y, origin.z, x.x, x.y, x.z)
}

main :: proc() {
	// visible tiny window: hidden-window contexts crash on this old GPU driver
	fmt.eprintln("pre-init")
	rl.InitWindow(64, 64, "bone_test")
	fmt.eprintln("window up")
	defer rl.CloseWindow()

	// creator-crash repro: sweep every race's idle clip like the preview does
	races := []string{"011", "012", "021", "022", "031", "042", "051", "063"}
	for id in races {
		crash_test_load(id)
	}
	sys.assets_init()
	// full creator pipeline (acquire + subset + race switch), elf first
	creator_repro("021")
	creator_repro("011")

	// ── character model ────────────────────────────────────────────────────
	fmt.eprintln("loading glb...")
	model := rl.LoadModel("assets/chara/chara_011.glb")
	fmt.eprintln("glb loaded")
	fmt.eprintfln("chara_011: meshes=%d bones=%d", model.meshCount, model.skeleton.boneCount)
	print_matrix("model.transform", model.transform)

	anim_count: c.int = 0
	anims := rl.LoadModelAnimations("assets/chara/chara_011.glb", &anim_count)
	idle := -1
	for i in 0..<int(anim_count) {
		if strings.has_suffix(anim_name(&anims[i]), "0001") {
			idle = int(i)
			break
		}
	}
	fmt.eprintfln("anims=%d idle_clip=%d", int(anim_count), idle)

	hand := -1
	for i in 0..<int(model.skeleton.boneCount) {
		if bone_name(&model.skeleton.bones[i]) == "Bip01 R Hand" {
			hand = int(i)
			break
		}
	}
	fmt.eprintfln("hand_bone_index=%d", hand)

	// Bone chain from hand to root (names + parents).
	fmt.eprintln("bone chain (hand → root):")
	i := hand
	depth := 0
	for i >= 0 && depth < 20 {
		fmt.eprintfln("  [%d] %s (parent=%d)", i, bone_name(&model.skeleton.bones[i]),
			model.skeleton.bones[i].parent)
		if model.skeleton.bones[i].parent < 0 do break
		i = int(model.skeleton.bones[i].parent)
		depth += 1
	}

	rl.UpdateModelAnimation(model, anims[idle], 0)

	// raylib's own runtime bone matrices (what its skinning uses).
	if model.boneMatrices != nil {
		print_matrix("boneMatrices[hand] (idle f0)", model.boneMatrices[hand])
	} else {
		fmt.eprintln("boneMatrices: nil")
	}
	if model.currentPose != nil {
		p := model.currentPose[hand]
		fmt.eprintfln("currentPose[hand]: t=(%f,%f,%f) s=(%f,%f,%f)",
			p.translation.x, p.translation.y, p.translation.z,
			p.scale.x, p.scale.y, p.scale.z)
	}

	// Chain walks over keyframe poses — BOTH orders (this is a row-vector
	// library: application order is v·A·B, so a child→root chain composes as
	// local_hand·…·local_root).
	bone_count := int(model.skeleton.boneCount)
	poses := anims[idle].keyframePoses[0][:bone_count]

	// Do frame-0 poses equal the bind pose?
	same := 0
	for b in 0..<bone_count {
		bp := model.skeleton.bindPose[b]
		fp := poses[b]
		if abs(bp.translation.x - fp.translation.x) < 1e-4 &&
			abs(bp.translation.y - fp.translation.y) < 1e-4 &&
			abs(bp.translation.z - fp.translation.z) < 1e-4 {
			same += 1
		}
	}
	fmt.eprintfln("frame0 vs bindPose: %d/%d bones equal translation", same, bone_count)

	// Ground truth: centroid of deformed vertices rigged to the hand bone.
	centroid := rl.Vector3{}
	found := 0
	for mi in 0..<int(model.meshCount) {
		mesh := &model.meshes[mi]
		if mesh.animVertices == nil || mesh.boneIndices == nil do continue
		n := int(mesh.vertexCount)
		for v in 0..<n {
			for w in 0..<4 {
				if mesh.boneIndices[v*4 + w] == u8(hand) && mesh.boneWeights[v*4 + w] > 0.5 {
					centroid.x += mesh.animVertices[v*3]
					centroid.y += mesh.animVertices[v*3+1]
					centroid.z += mesh.animVertices[v*3+2]
					found += 1
				}
			}
		}
	}
	if found > 0 {
		fmt.eprintfln("deformed hand-vertex centroid (%d verts): (%f,%f,%f)",
			found, centroid.x/f32(found), centroid.y/f32(found), centroid.z/f32(found))
	} else {
		fmt.eprintln("no hand-weighted vertices found")
	}

	// Row-vector local TRS: v·S·R·T → combined = S·R·T
	trs_rowvec :: proc(t: rl.Transform) -> rl.Matrix {
		return rl.MatrixScale(t.scale.x, t.scale.y, t.scale.z) *
			rl.QuaternionToMatrix(t.rotation) *
			rl.MatrixTranslate(t.translation.x, t.translation.y, t.translation.z)
	}

	m_child_first := trs_rowvec(poses[hand])
	i = hand
	for model.skeleton.bones[i].parent >= 0 && int(model.skeleton.bones[i].parent) != i {
		i = int(model.skeleton.bones[i].parent)
		m_child_first = m_child_first * trs_rowvec(poses[i])
	}
	fmt.eprintfln("child->root walk origin: (%f,%f,%f)",
		rl.Vector3Transform({0, 0, 0}, m_child_first).x,
		rl.Vector3Transform({0, 0, 0}, m_child_first).y,
		rl.Vector3Transform({0, 0, 0}, m_child_first).z)

	m_root_first := transform_matrix(poses[hand])
	i = hand
	for model.skeleton.bones[i].parent >= 0 && int(model.skeleton.bones[i].parent) != i {
		i = int(model.skeleton.bones[i].parent)
		m_root_first = transform_matrix(poses[i]) * m_root_first
	}
	fmt.eprintfln("root->child walk origin: (%f,%f,%f)",
		rl.Vector3Transform({0, 0, 0}, m_root_first).x,
		rl.Vector3Transform({0, 0, 0}, m_root_first).y,
		rl.Vector3Transform({0, 0, 0}, m_root_first).z)

	// ── hypothesis: boneMatrices = AnimGlobal·BindGlobal⁻¹ (a DELTA) ───────
	// Then the bone-riding matrix is BindGlobal · boneMatrices, and its
	// origin should land on the deformed hand. Try all four combinations of
	// {trs order} × {chain order} for BindGlobal.
	delta := model.boneMatrices[hand]

	combos := [4]string{"trs_rowvec·child->root", "trs_rowvec·root->child", "trs_colvec·child->root", "trs_colvec·root->child"}
	for ci in 0..<4 {
		mb: rl.Matrix
		trs := ci < 2 ? trs_rowvec(model.skeleton.bindPose[hand]) : transform_matrix(model.skeleton.bindPose[hand])
		mb = trs
		i = hand
		for model.skeleton.bones[i].parent >= 0 && int(model.skeleton.bones[i].parent) != i {
			i = int(model.skeleton.bones[i].parent)
			parent_local := ci < 2 ? trs_rowvec(model.skeleton.bindPose[i]) : transform_matrix(model.skeleton.bindPose[i])
			mb = (ci % 2 == 0) ? (mb * parent_local) : (parent_local * mb)
		}
		attach := mb * delta
		p := rl.Vector3Transform({0, 0, 0}, attach)
		fmt.eprintfln("bindGlobal[%s]·delta origin: (%f,%f,%f)", combos[ci], p.x, p.y, p.z)
	}

	// Same walk over the bind pose.
	mb := transform_matrix(model.skeleton.bindPose[hand])
	i = hand
	for model.skeleton.bones[i].parent >= 0 && int(model.skeleton.bones[i].parent) != i {
		i = int(model.skeleton.bones[i].parent)
		mb = transform_matrix(model.skeleton.bindPose[i]) * mb
	}
	print_matrix("bindPose chain walk [hand]", mb)

	// ── FINAL formula check: attach = TRS(currentPose[hand]) ───────────────
	// currentPose is the interpolated GLOBAL pose raylib keeps per bone —
	// verify it against the deformed hand-vertex centroid, idle AND attack.
	verify_pose := proc(label: string, clip: int, frame: c.int, model: rl.Model, anims: [^]rl.ModelAnimation, hand: int) {
		rl.UpdateModelAnimation(model, anims[clip], f32(frame))
		p := model.currentPose[hand]
		// Column-vector convention (Vector3Transform = M·v, translation in the
		// last column): translation must be OUTERMOST → T·R·S.
		origin := rl.Vector3Transform({0, 0, 0},
			rl.MatrixTranslate(p.translation.x, p.translation.y, p.translation.z) *
				rl.QuaternionToMatrix(p.rotation) *
				rl.MatrixScale(p.scale.x, p.scale.y, p.scale.z))
		raw_t := p.translation
		fmt.eprintfln("  raw currentPose t=(%f,%f,%f)", raw_t.x, raw_t.y, raw_t.z)
		cent := rl.Vector3{}
		n_found := 0
		for mi in 0..<int(model.meshCount) {
			mesh := &model.meshes[mi]
			if mesh.animVertices == nil || mesh.boneIndices == nil do continue
			n := int(mesh.vertexCount)
			for v in 0..<n {
				for w in 0..<4 {
					if mesh.boneIndices[v*4 + w] == u8(hand) && mesh.boneWeights[v*4 + w] > 0.5 {
						cent.x += mesh.animVertices[v*3]
						cent.y += mesh.animVertices[v*3+1]
						cent.z += mesh.animVertices[v*3+2]
						n_found += 1
					}
				}
			}
		}
		if n_found > 0 {
			dx := origin.x - cent.x/f32(n_found)
			dy := origin.y - cent.y/f32(n_found)
			dz := origin.z - cent.z/f32(n_found)
			fmt.eprintfln("%s f%d: currentPose attach=(%f,%f,%f)  deformed centroid=(%f,%f,%f)  delta=%f",
				label, frame, origin.x, origin.y, origin.z,
				cent.x/f32(n_found), cent.y/f32(n_found), cent.z/f32(n_found),
				math.sqrt(dx*dx + dy*dy + dz*dz))
		}
	}

	verify_pose("idle(0001)", idle, 0, model, anims, hand)
	verify_pose("idle(0001)", idle, 20, model, anims, hand)

	// ── weapon-axis probe: where do the hand's local axes + the rod's long
	// axis (item local Z, bounds z -0.949..0.862) land in model space? ─────
	axes_probe :: proc(label: string, model: rl.Model, hand: int) {
		p := model.currentPose[hand]
		m := rl.MatrixTranslate(p.translation.x, p.translation.y, p.translation.z) *
			rl.QuaternionToMatrix(p.rotation) *
			rl.MatrixScale(p.scale.x, p.scale.y, p.scale.z)
		o := rl.Vector3Transform({0, 0, 0}, m)
		px := rl.Vector3Transform({1, 0, 0}, m)
		py := rl.Vector3Transform({0, 1, 0}, m)
		pz := rl.Vector3Transform({0, 0, 1}, m)
		fmt.eprintfln("%s attach o=(%f,%f,%f)", label, o.x, o.y, o.z)
		fmt.eprintfln("  hand+X dir (%f,%f,%f)", px.x-o.x, px.y-o.y, px.z-o.z)
		fmt.eprintfln("  hand+Y dir (%f,%f,%f)", py.x-o.x, py.y-o.y, py.z-o.z)
		fmt.eprintfln("  hand+Z dir (%f,%f,%f)", pz.x-o.x, pz.y-o.y, pz.z-o.z)
		// Erola rod endpoints in hand space: grip at origin, head +Z 0.862m,
		// tail -Z 0.949m (item model local).
		hz := rl.Vector3Transform({0, 0, 0.862}, m)
		tz := rl.Vector3Transform({0, 0, -0.949}, m)
		fmt.eprintfln("  rod +Z(0.862) end -> (%f,%f,%f)  rod -Z(0.949) end -> (%f,%f,%f)",
			hz.x, hz.y, hz.z, tz.x, tz.y, tz.z)
	}
	rl.UpdateModelAnimation(model, anims[idle], 0)
	axes_probe("idle f0", model, hand)
	kp := anims[idle].keyframePoses[0][hand]
	fmt.eprintfln("keyframePoses[0][hand]: t=(%f,%f,%f)", kp.translation.x, kp.translation.y, kp.translation.z)

	// N52 grip seat (same constants as chara_models.odin): where do the rod's
	// endpoints land with the grip bolted on? Expect head behind the back
	// (~ -z), tail past the front hip (~ +z), shaft near-horizontal.
	grip := rl.MatrixTranslate(-0.0926, -0.0025, 0.0344) *
		rl.QuaternionToMatrix(rl.Quaternion(quaternion(x = 0.6827, y = 0.1390, z = -0.1286, w = 0.7057)))
	p := model.currentPose[hand]
	hm := rl.MatrixTranslate(p.translation.x, p.translation.y, p.translation.z) *
		rl.QuaternionToMatrix(p.rotation) *
		rl.MatrixScale(p.scale.x, p.scale.y, p.scale.z)
	am := hm * grip
	g0 := rl.Vector3Transform({0, 0, 0}, am)
	gh := rl.Vector3Transform({0, 0, 0.862}, am)
	gt := rl.Vector3Transform({0, 0, -0.949}, am)
	fmt.eprintfln("grip seat: grip=(%f,%f,%f) rod head(+Z)=(%f,%f,%f) rod tail(-Z)=(%f,%f,%f)",
		g0.x, g0.y, g0.z, gh.x, gh.y, gh.z, gt.x, gt.y, gt.z)
	atk := -1
	for i in 0..<int(anim_count) {
		if strings.has_suffix(anim_name(&anims[i]), "1055") {
			atk = int(i)
			break
		}
	}
	if atk >= 0 {
		verify_pose("attack(1055)", atk, 3, model, anims, hand)
		verify_pose("attack(1055)", atk, 10, model, anims, hand)
		verify_pose("attack(1055)", atk, 20, model, anims, hand)
	}

	// ── item models ────────────────────────────────────────────────────────
	paths := [2]string{"assets/item/EM_002904_20_000.glb", "assets/item/EM_000001_20_000.glb"}
	for path in paths {
		it := rl.LoadModel(cstr(path))
		if it.meshCount == 0 {
			fmt.eprintfln("%s: LOAD FAILED", path)
			continue
		}
		print_matrix(fmt.tprintf("%s transform", path), it.transform)
		for mi in 0..<int(it.meshCount) {
			mesh := &it.meshes[mi]
			if mesh.vertexCount <= 0 do continue
			minv := rl.Vector3{1e9, 1e9, 1e9}
			maxv := rl.Vector3{-1e9, -1e9, -1e9}
			v := mesh.vertices[:int(mesh.vertexCount) * 3]
			for k in 0..<len(v) / 3 {
				x, y, z := v[k*3], v[k*3+1], v[k*3+2]
				if x < minv.x do minv.x = x
				if y < minv.y do minv.y = y
				if z < minv.z do minv.z = z
				if x > maxv.x do maxv.x = x
				if y > maxv.y do maxv.y = y
				if z > maxv.z do maxv.z = z
			}
			fmt.eprintfln("%s mesh[%d]: verts=%d bounds min=(%f,%f,%f) max=(%f,%f,%f)",
				path, mi, mesh.vertexCount, minv.x, minv.y, minv.z, maxv.x, maxv.y, maxv.z)
		}
	}
}
