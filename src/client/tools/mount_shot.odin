package bone_test

// Mounted-rider visual verification: draws the REAL game path (horse gait
// instance + avatar mounted stances + seat offset) for a few key poses and
// screenshots them — the same composition sys.render uses for scene entities
// and draw_local_player uses for the local player. Also renders a seat-
// calibration strip (rider drawn at several forward offsets) so the seat
// constant is eyeball-checkable. Output: mount_shot_*.png next to the exe.

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"
import sys "../systems"

strings_clone_to_cstring_mount :: proc(s: string) -> cstring {
	return strings.clone_to_cstring(s, context.temp_allocator)
}

mount_shot_take :: proc(hi: ^sys.Horse_Instance, av: ^sys.Chara_Avatar, fname: string, cam_pos: rl.Vector3, forward: f32, target := rl.Vector3{0, 1.5, 0}) {
	cam := rl.Camera3D{
		position   = cam_pos,
		target     = target,
		up         = {0, 1, 0},
		fovy       = 40,
		projection = .PERSPECTIVE,
	}
	rl.BeginDrawing()
	rl.ClearBackground({168, 178, 200, 255})
	rl.BeginMode3D(cam)
	rl.DrawPlane({0, 0, 0}, {8, 8}, {120, 140, 110, 255})
	// The exact pair sys.render draws for a mounted entity: pose the horse,
	// anchor the rider seat to the animated spine (bob/sway delta included),
	// draw the rider, then the horse. `forward` overrides the seat constant
	// (used by the calibration strip).
	sys.horse_instance_pose(hi)
	rider_pos := rl.Vector3{0, 0, -forward}
	rider_pos += sys.horse_delta_world(0, sys.horse_instance_anchor_delta(hi))
	sys.chara_avatar_draw_body(av, rider_pos, 0, rl.WHITE)
	sys.horse_model_draw(hi, {0, 0, 0}, 0, rl.WHITE, hi.base.lift, 1.0)
	rl.EndMode3D()
	rl.TakeScreenshot(strings_clone_to_cstring_mount(fname))
	rl.EndDrawing()
	fmt.eprintfln("mount_shot: wrote %s (forward=%.2f)", fname, forward)
}

mount_shot_pose :: proc(av: ^sys.Chara_Avatar, clip_idx: int, frame: f32) {
	av.applied_clip = clip_idx
	av.applied_frame = frame
	av.blend_from = -1
	av.lift = sys.HORSE_RIDER_LIFT
	sys.chara_apply_current_pose(av, av.sub.model)
}

mount_shot :: proc() {
	rl.InitWindow(800, 600, "mount_shot")
	tools_locate_assets()
	defer rl.CloseWindow()
	sys.assets_init()

	hi := new(sys.Horse_Instance)
	hi^ = sys.horse_instance_init(sys.horse_model_acquire(sys.horse_model_path(20, 0)), 20)
	if !hi.valid {
		fmt.eprintfln("mount_shot: horse model FAILED to load")
		return
	}

	// One race per invocation — re-acquiring a second race after avatar
	// teardown crashes this machine's old GL driver (see armor_shot).
	cm := sys.chara_model_acquire("011")
	if cm == nil {
		fmt.eprintfln("mount_shot: chara acquire FAILED")
		return
	}
	av := sys.chara_avatar_create(cm, 0, 0, 0)
	if av == nil {
		sys.chara_model_release(cm)
		return
	}
	av.mounted = true

	idle := sys.chara_clip(cm, sys.CLIP_CODE_MOUNTED_IDLE)
	move := sys.chara_clip(cm, sys.CLIP_CODE_MOUNTED_MOVE)
	charge := sys.chara_clip(cm, sys.CLIP_CODE_MOUNTED_CHARGE)
	armed_idle := sys.chara_clip(cm, sys.CLIP_CODE_MOUNTED_ARMED_IDLE)
	lance_a1 := sys.chara_clip(cm, "3655")

	side := rl.Vector3{3.4, 2.0, 0.01}
	front := rl.Vector3{0, 2.0, -3.6}

	// Seat calibration strip: mounted idle pose at several forward offsets
	// (world -Z with the shared yaw offset = toward the horse's head). The
	// best-looking value bakes into HORSE_RIDER_FORWARD (horses.odin).
	if idle >= 0 {
		sys.horse_instance_set_gait(hi, sys.CLIP_CODE_HORSE_IDLE)
		sys.horse_instance_update(hi, 1.0 / 60.0)
		mount_shot_pose(av, idle, 0)
		cal_offsets := [4]f32{0.20, 0.05, -0.10, -0.25}
		for f in cal_offsets {
			mount_shot_take(hi, av, fmt.tprintf("mount_shot_cal_%.2f.png", f), side, f)
		}
	}

	// Horse gait keys (idle / walk / run) for the horse under each pose.
	h_idle := sys.CLIP_CODE_HORSE_IDLE
	h_walk := sys.CLIP_CODE_HORSE_WALK
	seat := f32(sys.HORSE_RIDER_FORWARD)

	// Barding-variant strip: idle pose on coats/variants so the default look
	// is eyeball-checkable (server default variant = 10).
	if idle >= 0 {
		sys.horse_instance_set_gait(hi, h_idle)
		sys.horse_instance_update(hi, 1.0 / 60.0)
		mount_shot_pose(av, idle, 0)
		coats := [4]i32{10, 20, 30, 40}
		for v in coats {
			vi := new(sys.Horse_Instance)
			vi^ = sys.horse_instance_init(sys.horse_model_acquire(sys.horse_model_path(v, 0)), v)
			if vi.valid {
				sys.horse_instance_set_gait(vi, h_idle)
				sys.horse_instance_update(vi, 1.0 / 60.0)
				mount_shot_take(vi, av, fmt.tprintf("mount_shot_coat_%03d.png", v), side, seat)
			}
		}
	}

	if idle >= 0 {
		sys.horse_instance_set_gait(hi, h_idle)
		sys.horse_instance_update(hi, 1.0 / 60.0)
		mount_shot_pose(av, idle, 0)
		mount_shot_take(hi, av, "mount_shot_idle.png", side, seat)
		mount_shot_take(hi, av, "mount_shot_idle_front.png", front, seat)
	}
	if move >= 0 {
		mk := f32(cm.anims[move].keyframeCount)
		sys.horse_instance_set_gait(hi, h_walk)
		sys.horse_instance_update(hi, 1.0 / 60.0)
		mount_shot_pose(av, move, mk * 0.5)
		mount_shot_take(hi, av, "mount_shot_move.png", side, seat)
	}
	if charge >= 0 {
		ck := f32(cm.anims[charge].keyframeCount)
		sys.horse_instance_set_gait(hi, sys.CLIP_CODE_HORSE_RUN)
		sys.horse_instance_update(hi, 1.0 / 60.0)
		mount_shot_pose(av, charge, ck * 0.4)
		mount_shot_take(hi, av, "mount_shot_charge.png", side, seat)
	}
	if armed_idle >= 0 {
		sys.horse_instance_set_gait(hi, h_idle)
		sys.horse_instance_update(hi, 1.0 / 60.0)
		mount_shot_pose(av, armed_idle, 0)
		mount_shot_take(hi, av, "mount_shot_armed.png", side, seat)
	}
	if lance_a1 >= 0 {
		lk := f32(cm.anims[lance_a1].keyframeCount)
		sys.horse_instance_set_gait(hi, h_walk)
		sys.horse_instance_update(hi, 1.0 / 60.0)
		mount_shot_pose(av, lance_a1, lk * 0.5)
		mount_shot_take(hi, av, "mount_shot_lance_attack.png", side, seat)
	}

	// The REAL per-frame path (update_local_avatar / ecs.update): set the
	// mount flag, run chara_avatar_update for each gait + combat stance, and
	// screenshot what actually resolves — validates the mounted branch inside
	// chara_avatar_update end to end.
	av.mounted = true
	{
		sys.horse_instance_set_gait(hi, h_idle)
		sys.horse_instance_update(hi, 1.0 / 60.0)
		sys.chara_avatar_set_weapon_kind(av, sys.Weapon_Kind.NONE)
		av.blocking = false
		sys.chara_avatar_update(av, .IDLE, 1.0 / 60.0, false)
		clip_name := sys.chara_anim_name(&av.cm.anims[av.applied_clip])
		fmt.eprintfln("  update path idle (sheathed): %s", clip_name)
		mount_shot_take(hi, av, "mount_shot_path_idle.png", side, seat)
		sys.chara_avatar_update(av, .RUN, 1.0 / 60.0, false)
		fmt.eprintfln("  update path gallop (sheathed): %s",
			sys.chara_anim_name(&av.cm.anims[av.applied_clip]))
		// combat=true resolves the armed family (weapon .NONE rides the
		// 0301/0316 armed stances)
		sys.chara_avatar_set_weapon_kind(av, sys.Weapon_Kind.SWORD)
		sys.chara_avatar_update(av, .IDLE, 1.0 / 60.0, true)
		fmt.eprintfln("  update path idle (armed 1h): %s",
			sys.chara_anim_name(&av.cm.anims[av.applied_clip]))
		sys.chara_avatar_update(av, .RUN, 1.0 / 60.0, true)
		fmt.eprintfln("  update path gallop (armed 1h): %s",
			sys.chara_anim_name(&av.cm.anims[av.applied_clip]))
		mount_shot_take(hi, av, "mount_shot_path_armed_run.png", side, seat)
	}
	av.mounted = false
	sys.chara_avatar_update(av, .IDLE, 1.0 / 60.0, false)
	fmt.eprintfln("  update path dismounted idle: %s",
		sys.chara_anim_name(&av.cm.anims[av.applied_clip]))

	// Anchor-bone probe: for idle/walk/run at several frames, print the
	// model-space translation delta (animated vs bind) of the candidate seat
	// bones — the bone whose delta tracks the visible back bob becomes the
	// rider anchor (HORSE_ANCHOR_BONE).
	{
		av.mounted = true
		mount_shot_pose(av, idle, 0)
		probe_gaits := [3]string{sys.CLIP_CODE_HORSE_IDLE, sys.CLIP_CODE_HORSE_WALK, sys.CLIP_CODE_HORSE_RUN}
		probe_names := [3]string{"idle", "walk", "run"}
		for g in 0..<3 {
			mi2 := new(sys.Horse_Instance)
			mi2^ = sys.horse_instance_init(hi.base, 20)
			sys.horse_instance_set_gait(mi2, probe_gaits[g])
			frames := [4]f32{0.0, 0.25, 0.5, 0.75}
			for fi in 0..<4 {
				fk := f32(hi.base.anims[hi.base.clips[probe_gaits[g]]].keyframeCount)
				mi2.anim_time = frames[fi] * fk / f32(sys.CHARA_ANIM_FPS)
				sys.horse_instance_update(mi2, 0)
				sys.horse_instance_pose(mi2)
				sys.horse_probe_anchor(mi2, fmt.tprintf("%s@%.2f", probe_names[g], frames[fi]))
			}
		}
	}

	fmt.eprintfln("mount_shot: done")
}
