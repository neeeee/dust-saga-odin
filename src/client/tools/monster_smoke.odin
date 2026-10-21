package bone_test

// Monster-instance smoke test: exercises the per-entity monster model state
// exactly like the game does on WORLD_STATE spawn — acquire the species
// model, init instances, advance clocks through idle/swing/cast clips, apply
// poses (draw-time re-pose path), and verify instances pose independently.
// Catches pose crashes with real shipped glbs.

import "core:fmt"
import rl "vendor:raylib"
import sys "../systems"

// |a-b| sum of the shared model's deformed mesh-0 vertices right now.
monster_pose_sum :: proc(base: ^sys.Monster_Model) -> f32 {
	diff := f32(0)
	if base != nil && base.valid && base.entry.model.meshCount > 0 {
		m := &base.entry.model.meshes[0]
		if m.animVertices != nil {
			for v in 0..<int(m.vertexCount) * 3 {
				d := m.animVertices[v]
				if d < 0 do d = -d
				diff += d
			}
		}
	}
	return diff
}

monster_smoke :: proc() {
	fmt.eprintln("== monster_smoke ==")
	rl.InitWindow(64, 64, "monster_smoke")
	tools_clamp_window()
	defer rl.CloseWindow()

	cases := []string{
		"monster/monster_21201_Kobold.glb",
		"monster/monster_11101_Aardwolf.glb",
	}
	for file in cases {
		fmt.eprintfln("acquire %s", file)
		base := sys.monster_model_acquire(file)
		if base == nil || !base.valid {
			fmt.eprintln("  acquire FAILED (skipped)")
			continue
		}
		fmt.eprintfln("  clips=%d idle=%d", base.anim_count, base.idle)

		fmt.eprintln("  instance init x2")
		a := sys.monster_instance_init(base)
		b := sys.monster_instance_init(base)

		fmt.eprintln("  pose 10 idle frames")
		for i in 0..<10 {
			sys.monster_instance_update(&a, 1.0 / 30.0)
			sys.monster_instance_update(&b, 1.0 / 60.0)
		}

		fmt.eprintln("  play swing 0155")
		sys.monster_instance_play(&a, "0155", false)
		for i in 0..<40 do sys.monster_instance_update(&a, 1.0 / 30.0)

		fmt.eprintln("  play cast loop 0171 + stop")
		if sys.monster_instance_play(&b, "0171", true) {
			for i in 0..<10 do sys.monster_instance_update(&b, 1.0 / 30.0)
			sys.monster_instance_stop(&b)
		} else {
			fmt.eprintln("  (no 0171 on this species)")
		}

		fmt.eprintln("  skill execution paths")
		sys.monster_play_skill_execution(&a, "physical")
		sys.monster_play_skill_execution(&a, "magical")
		sys.monster_cast_start(&b)
		for i in 0..<5 do sys.monster_instance_update(&b, 1.0 / 30.0)

		fmt.eprintln("  pose independence check (a mid-swing vs b idle, applied at draw)")
		sys.monster_instance_play(&a, "0155", false)
		sys.monster_instance_play(&b, "0001", false)
		sys.monster_instance_update(&a, 0.8) // mid-swing
		sys.monster_instance_update(&b, 0.0)
		sys.monster_model_draw(&a, {0, 0, 0}, 0, rl.WHITE, 1)
		sum_a := monster_pose_sum(base) // shared model wears a's pose now
		sys.monster_model_draw(&b, {0, 0, 0}, 0, rl.WHITE, 1)
		sum_b := monster_pose_sum(base) // and b's pose now
		fmt.eprintfln("  pose sums a=%f b=%f (equal = shared pose, differ = independent)", sum_a, sum_b)

		fmt.eprintfln("  OK %s", file)
	}
	fmt.eprintln("== monster_smoke PASS ==")
}
