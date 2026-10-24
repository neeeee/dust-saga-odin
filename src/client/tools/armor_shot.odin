package bone_test

// Visual worn-armor verification: drives the REAL game path (avatar create →
// applied pose → chara_avatar_update_armor → chara_avatar_draw_armor) for the
// full Fornid set on the human female (012) — helmet (rigid head-attach),
// torso, cuisses, sabatons — then screenshots front/side at an idle frame and
// a mid-run frame (the run frame maximizes pose-vs-bind deltas on the arms —
// where the flipped pose·bind⁻¹ order showed as horizontal pauldron wings).
// Output: armor_shot_*.png next to the exe.

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"
import sys "../systems"

strings_clone_to_cstring_shot :: proc(s: string) -> cstring {
	return strings.clone_to_cstring(s, context.temp_allocator)
}

armor_shot_pose :: proc(av: ^sys.Chara_Avatar, clip_idx: int, frame: f32) -> rl.BoundingBox {
	av.applied_clip = clip_idx
	av.applied_frame = frame
	av.blend_from = -1
	sys.chara_apply_current_pose(av, av.sub.model)
	sys.chara_avatar_update_armor(av)

	// ground truth: the transfer must map the WEARER's bind position of each
	// armor bone onto the wearer's posed bone (the armor meshes are skinned
	// against the master skeleton — see chara_avatar_update_armor).
	if hb, ok := sys.chara_avatar_bone_matrix(av, sys.CHARA_HEAD_BONE); ok {
		ht := rl.Vector3Transform({0, 0, 0}, hb)
		fmt.eprintfln("  head_t (%.4f,%.4f,%.4f) rigid_helmet=%v", ht.x, ht.y, ht.z,
			av.armor_rigid[sys.Chara_Armor_Layer.HELMET])
	}
	// shield world-space center: where the disc actually lands at this pose
	if se := av.shield_model; se != nil {
		seat := sys.chara_shield_seat()
		if attach, ok := sys.chara_avatar_socket_matrix(av, seat); ok {
			msh := &se.model.meshes[0]
			minv := rl.Vector3{1e9, 1e9, 1e9}
			maxv := rl.Vector3{-1e9, -1e9, -1e9}
			for v in 0..<int(msh.vertexCount) {
				minv.x = min(minv.x, msh.vertices[v * 3 + 0])
				minv.y = min(minv.y, msh.vertices[v * 3 + 1])
				minv.z = min(minv.z, msh.vertices[v * 3 + 2])
				maxv.x = max(maxv.x, msh.vertices[v * 3 + 0])
				maxv.y = max(maxv.y, msh.vertices[v * 3 + 1])
				maxv.z = max(maxv.z, msh.vertices[v * 3 + 2])
			}
			c := (minv + maxv) * 0.5
			base := sys.chara_held_base_matrix(av, {0, 0, 0}, 0, 1.0)
			wc := rl.Vector3Transform(c, base * attach)
			fmt.eprintfln("  shield center local (%.3f,%.3f,%.3f) world (%.4f,%.4f,%.4f)",
				c.x, c.y, c.z, wc.x, wc.y, wc.z)
			// exact seat translation for a desired world anchor: invert the
			// animated forearm frame and pull the target point into it
			if bone, ok2 := sys.chara_avatar_bone_matrix(av, "Bip01 L Forearm"); ok2 {
				want := rl.Vector3Transform({-0.223, 1.03, -0.02}, rl.MatrixInvert(base))
				t_needed := rl.Vector3Transform(want, rl.MatrixInvert(bone))
				fmt.eprintfln("  t for world(-0.223,1.03,-0.02): (%.5f, %.5f, %.5f)",
					t_needed.x, t_needed.y, t_needed.z)
			}
		}
	}
	le := av.armor_models[sys.Chara_Armor_Layer.LEGS]
	if le != nil {
		base := &av.cm.entry.model
		names := [3]string{"Bip01 L Thigh", "Bip01 L Calf", "Bip01 L Foot"}
		for name in names {
			ab := -1
			for b in 0..<int(le.model.skeleton.boneCount) {
				if sys.chara_bone_name(&le.model.skeleton.bones[b]) == name {
					ab = b
					break
				}
			}
			cb := -1
			for b in 0..<int(base.skeleton.boneCount) {
				if sys.chara_bone_name(&base.skeleton.bones[b]) == name {
					cb = b
					break
				}
			}
			if ab < 0 || cb < 0 {
				fmt.eprintfln("  probe %s: armor_bone=%d char_bone=%d", name, ab, cb)
				continue
			}
			bind_t := base.skeleton.bindPose[cb].translation
			mo := rl.Vector3Transform(bind_t, le.model.boneMatrices[ab])
			ct := av.sub.model.currentPose[cb].translation
			fmt.eprintfln("  probe %s: bind_t mapped -> (%.4f,%.4f,%.4f)  want char pose t (%.4f,%.4f,%.4f)",
				name, mo.x, mo.y, mo.z, ct.x, ct.y, ct.z)
		}
	}

	// per-layer per-mesh skinned bounds + NaN census: a layer that renders
	// "nothing" either collapsed (NaN from a bad matrix) or never skins
	for layer in 0..<sys.CHARA_ARMOR_LAYER_COUNT {
		e := av.armor_models[layer]
		if e == nil do continue
		for mi in 0..<int(e.model.meshCount) {
			mesh := &e.model.meshes[mi]
			if mesh.vertexCount <= 0 do continue
			if mesh.animVertices == nil {
				fmt.eprintfln("  layer%d mesh%d: %d verts, animVertices NIL (never skinned)",
					layer, mi, mesh.vertexCount)
				continue
			}
			nan := 0
			minv := rl.Vector3{1e9, 1e9, 1e9}
			maxv := rl.Vector3{-1e9, -1e9, -1e9}
			for v in 0..<int(mesh.vertexCount) {
				x := mesh.animVertices[v*3]
				y := mesh.animVertices[v*3+1]
				z := mesh.animVertices[v*3+2]
				if x != x || y != y || z != z {
					nan += 1
					continue
				}
				minv.x = min(minv.x, x); minv.y = min(minv.y, y); minv.z = min(minv.z, z)
				maxv.x = max(maxv.x, x); maxv.y = max(maxv.y, y); maxv.z = max(maxv.z, z)
			}
			fmt.eprintfln("  layer%d mesh%d: %d verts nan=%d bounds (%.2f,%.2f,%.2f)-(%.2f,%.2f,%.2f)",
				layer, mi, mesh.vertexCount, nan,
				minv.x, minv.y, minv.z, maxv.x, maxv.y, maxv.z)
		}
	}
	return sys.chara_skin_bounds(av.cm, &av.sub.model)
}

armor_shot_take :: proc(av: ^sys.Chara_Avatar, fname: string, cam_pos: rl.Vector3, target := rl.Vector3{0, 0.95, 0}) {
	// Body and armor must carry the SAME yaw offset — the game adds
	// AVATAR_YAW_OFFSET_DEG to both (the armor's inside
	// chara_avatar_draw_armor). At 0+180° the model faces -Z.
	cam := rl.Camera3D{
		position   = cam_pos,
		target     = target,
		up         = {0, 1, 0},
		fovy       = 38,
		projection = .PERSPECTIVE,
	}
	rl.BeginDrawing()
	rl.ClearBackground({168, 178, 200, 255})
	rl.BeginMode3D(cam)
	// thin ground quad for orientation
	rl.DrawPlane({0, 0, 0}, {4, 4}, {120, 140, 110, 255})
	sys.chara_avatar_draw_body(av, {0, 0, 0}, 0, rl.WHITE)
	sys.chara_avatar_draw_armor(av, {0, 0, 0}, 0, rl.WHITE)
	sys.chara_avatar_draw_shield(av, {0, 0, 0}, 0)
	rl.EndMode3D()
	rl.TakeScreenshot(strings_clone_to_cstring_shot(fname))
	rl.EndDrawing()
	fmt.eprintfln("armor_shot: wrote %s", fname)
}

armor_shot :: proc() {
	rl.InitWindow(640, 720, "armor_shot")
	tools_clamp_window()
	defer rl.CloseWindow()
	sys.assets_init()

	// One race per invocation: re-acquiring a second race after avatar
	// teardown crashes this machine's old GL driver (exit 0x7F).
	race := "012"
	cm := sys.chara_model_acquire(race)
	if cm == nil {
		fmt.eprintfln("armor_shot: race %s acquire FAILED", race)
		return
	}
	av := sys.chara_avatar_create(cm, 0, 0, 0)
	if av == nil {
		sys.chara_model_release(cm)
		return
	}
	av.armor_models[sys.Chara_Armor_Layer.HELMET] = sys.held_model_acquire(
		fmt.tprintf("item/EM_011103_01_%s.glb", race))
	av.armor_models[sys.Chara_Armor_Layer.TORSO] = sys.held_model_acquire(
		fmt.tprintf("item/EM_012203_02_%s.glb", race))
	av.armor_models[sys.Chara_Armor_Layer.LEGS] = sys.held_model_acquire(
		fmt.tprintf("item/EM_013203_03_%s.glb", race))
	av.armor_models[sys.Chara_Armor_Layer.BOOTS] = sys.held_model_acquire(
		fmt.tprintf("item/EM_015103_05_%s.glb", race))
	av.armor_models[sys.Chara_Armor_Layer.BACK] = sys.held_model_acquire(
		fmt.tprintf("item/EM_018023_12_%s.glb", race)) // Sacred King Cloak (MANTLE, part 12)
	// chara_avatar_sync_armor sets this in-game from the item's part code —
	// the tool bypasses sync, so mirror it: part 01 (helmets) is rigid
	av.armor_rigid[sys.Chara_Armor_Layer.HELMET] = true
	// left-arm shield (targe) — the tool bypasses chara_avatar_sync_shield too
	av.shield_model = sys.held_model_acquire("item/EM_017021_22_000.glb")
	sys.chara_avatar_refresh_body_hidden(av, true)
	te := av.armor_models[sys.Chara_Armor_Layer.TORSO]
	le := av.armor_models[sys.Chara_Armor_Layer.LEGS]
	fmt.eprintfln("armor_shot: torso entry=%v meshes=%d legs entry=%v meshes=%d",
		te != nil, te != nil ? int(te.model.meshCount) : -1,
		le != nil, le != nil ? int(le.model.meshCount) : -1)

	front := rl.Vector3{0, 1.35, -2.6}
	side := rl.Vector3{2.6, 1.35, 0.01}

	// isolation pass: torso only vs legs only (which piece is missing?)
	if te != nil {
		av.armor_models[sys.Chara_Armor_Layer.LEGS] = nil
		sys.chara_avatar_refresh_body_hidden(av, false)
		b := armor_shot_pose(av, av.cm.idle_anim, 0)
		av.lift = -b.min.y * av.scale
		armor_shot_take(av, "armor_shot_iso_torso.png", front)
		av.armor_models[sys.Chara_Armor_Layer.LEGS] = le
	}
	if le != nil {
		av.armor_models[sys.Chara_Armor_Layer.TORSO] = nil
		sys.chara_avatar_refresh_body_hidden(av, false)
		b := armor_shot_pose(av, av.cm.idle_anim, 0)
		av.lift = -b.min.y * av.scale
		armor_shot_take(av, "armor_shot_iso_legs.png", front)
		av.armor_models[sys.Chara_Armor_Layer.TORSO] = te
	}
	sys.chara_avatar_refresh_body_hidden(av, false)
	back := rl.Vector3{0, 1.35, 2.6}
	shoulder := rl.Vector3{-0.75, 1.55, -1.1} // right-shoulder close-up
	ankle := rl.Vector3{-0.5, 0.35, -1.3} // ankle close-up

	pose_take :: proc(av: ^sys.Chara_Avatar, clip_idx: int, frame: f32, name: string, cams: ..rl.Vector3) {
		b := armor_shot_pose(av, clip_idx, frame)
		av.lift = -b.min.y * av.scale
		i := 0
		for cam in cams {
			armor_shot_take(av, fmt.tprintf("%s_%d.png", name, i), cam)
			i += 1
		}
	}

	// combat stance clips: the sword-drawn idle (xx01) and an attack swing —
	// the in-game screenshots show the artifact in THIS stance
	combat := sys.chara_clip(av.cm, "1201")
	if combat < 0 do combat = av.cm.idle_anim
	atk := sys.chara_clip(av.cm, "1255")
	if atk < 0 do atk = combat

	if av.cm.idle_anim >= 0 {
		keys := f32(av.cm.anims[av.cm.idle_anim].keyframeCount)
		pose_take(av, av.cm.idle_anim, 0, "armor_shot_idle", front, side)
		pose_take(av, av.cm.idle_anim, keys * 0.5, "armor_shot_idle2", front)

		if combat != av.cm.idle_anim {
			ck := f32(av.cm.anims[combat].keyframeCount)
			pose_take(av, combat, 0, "armor_shot_combat", front, side, back)
			pose_take(av, combat, ck * 0.5, "armor_shot_combat2", front)
			// close-ups: right shoulder + ankle in combat stance
			cam_sh := rl.Vector3{-0.75, 1.5, -0.9}
			cam_an := rl.Vector3{-0.35, 0.3, -1.0}
			armor_shot_pose(av, combat, 0)
			armor_shot_take(av, "armor_shot_combat_shoulder.png", cam_sh)
			armor_shot_take(av, "armor_shot_combat_ankle.png", cam_an)
		}
		if atk != combat {
			ak := f32(av.cm.anims[atk].keyframeCount)
			pose_take(av, atk, ak * 0.5, "armor_shot_attack", front, side)
		}

		fr := f32(av.cm.anims[av.cm.run_anim].keyframeCount)
		pose_take(av, av.cm.run_anim, fr * 0.35, "armor_shot_run", front, side)

		// head close-up: helmet placement, hair hidden so nothing crowds it
		sys.chara_avatar_refresh_body_hidden(av, true)
		armor_shot_pose(av, av.cm.idle_anim, 0)
		armor_shot_take(av, "armor_shot_head.png", rl.Vector3{0, 1.55, -0.75}, rl.Vector3{0, 1.55, 0})
		armor_shot_take(av, "armor_shot_head_side.png", rl.Vector3{0.75, 1.55, 0}, rl.Vector3{0, 1.55, 0})
	}

	av.armor_models[sys.Chara_Armor_Layer.TORSO] = nil
	av.armor_models[sys.Chara_Armor_Layer.LEGS] = nil
	sys.chara_avatar_destroy(av)
}
