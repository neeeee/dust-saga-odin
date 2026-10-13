package bone_test

// Visual worn-armor verification: drives the REAL game path (avatar create →
// applied pose → chara_avatar_update_armor → chara_avatar_draw_armor) for the
// striker torso+trousers, then screenshots front/side at an idle frame and a
// mid-run frame (the run frame maximizes pose-vs-bind deltas on the arms —
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

armor_shot_take :: proc(av: ^sys.Chara_Avatar, fname: string, cam_pos: rl.Vector3) {
	// Body and armor must carry the SAME yaw offset — the game adds
	// AVATAR_YAW_OFFSET_DEG to both (the armor's inside
	// chara_avatar_draw_armor). At 0+180° the model faces -Z.
	cam := rl.Camera3D{
		position   = cam_pos,
		target     = {0, 0.95, 0},
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

	// 022 only: re-acquiring a second race after avatar teardown crashes this
	// machine's old GL driver (exit 0x7F) — run per-race invocations instead.
	race := "022"
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
	av.armor_models[sys.Chara_Armor_Layer.TORSO] = sys.held_model_acquire(
		fmt.tprintf("item/EM_012211_02_%s.glb", race))
	av.armor_models[sys.Chara_Armor_Layer.LEGS] = sys.held_model_acquire(
		fmt.tprintf("item/EM_013211_03_%s.glb", race))
	sys.chara_avatar_refresh_body_hidden(av, false)
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
	}

	av.armor_models[sys.Chara_Armor_Layer.TORSO] = nil
	av.armor_models[sys.Chara_Armor_Layer.LEGS] = nil
	sys.chara_avatar_destroy(av)
}
