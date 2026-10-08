package bone_test

// Full creator-pipeline repro: chara_model_acquire → chara_subset_build →
// per-frame UpdateModelAnimation on the base model, exactly like the
// character-select creator preview (character_select.odin).

import "core:c"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"
import sys "../systems"

creator_repro :: proc(model_id: string) {
	marker :: proc(m: string) {
		fmt.eprintfln(">>> %s", m)
	}

	marker(fmt.tprintf("%s acquire", model_id))
	cm := sys.chara_model_acquire(model_id)
	if cm == nil {
		fmt.eprintfln("creator repro %s: acquire FAILED", model_id)
		return
	}
	marker("subset build")
	subset := sys.chara_subset_build(cm, 0, 0, 0)
	defer sys.chara_subset_free(&subset)

	if cm.idle_anim >= 0 {
		anim := cm.anims[cm.idle_anim]
		frames := f32(anim.keyframeCount)
		f := f32(0)
		for step in 0..<1200 {
			f += 1.0 / 60.0 * sys.CHARA_ANIM_FPS
			frame := f - f32(i32(f / frames)) * frames
			if step % 100 == 0 do marker(fmt.tprintf("step %d", step))
			rl.UpdateModelAnimation(cm.entry.model, anim, frame)
			if step == 600 {
				// race switch mid-preview: acquire another model, animate it,
				// then release — the creator does this on every race click
				other_id := model_id == "021" ? "011" : "021"
				marker("mid: acquire other")
				other := sys.chara_model_acquire(other_id)
				if other != nil {
					if other.idle_anim >= 0 {
						marker("mid: pose other")
						rl.UpdateModelAnimation(other.entry.model, other.anims[other.idle_anim], 0)
					}
					marker("mid: release other")
					sys.chara_model_release(other)
					marker("mid: released")
				}
				marker("mid: pose primary again")
				rl.UpdateModelAnimation(cm.entry.model, anim, frame)
				marker("mid: ok")
			}
		}
	}
	fmt.eprintfln("creator repro %s: survived", model_id)
	marker("release primary")
	sys.chara_model_release(cm)
	marker("released primary")
}
