package bone_test

// Minimal repro for the creator crash: load a chara glb + its clips and
// drive UpdateModelAnimation over the idle clip exactly like the creator
// preview does. If the model's skeleton and the animation's bone arrays
// mismatch, raylib reads past the pose array and faults inside the lerp.

import "core:c"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

crash_test_load :: proc(model_id: string) {
	path := fmt.tprintf("assets/chara/chara_%s.glb", model_id)
	model := rl.LoadModel(strings.clone_to_cstring(path, context.temp_allocator))
	fmt.eprintfln("%s: meshes=%d bones=%d", model_id, model.meshCount, model.skeleton.boneCount)
	anim_count: c.int = 0
	anims := rl.LoadModelAnimations(strings.clone_to_cstring(path, context.temp_allocator), &anim_count)
	fmt.eprintfln("%s: anims=%d", model_id, int(anim_count))
	idle := -1
	for i in 0..<int(anim_count) {
		nm := anim_name(&anims[i])
		if strings.has_suffix(nm, "0001") {
			idle = int(i)
			break
		}
	}
	if idle < 0 {
		fmt.eprintfln("%s: no idle clip", model_id)
		return
	}
	anim := &anims[idle]
	fmt.eprintfln("%s: idle=%s frames=%d anim.bones=%d (model bones %d)",
		model_id, anim_name(anim), int(anim.keyframeCount), int(anim.boneCount),
		int(model.skeleton.boneCount))
	if int(anim.boneCount) < int(model.skeleton.boneCount) {
		fmt.eprintfln("  *** MISMATCH: model has more bones than the anim — raylib will read past the pose array")
	}
	for f in 0..<int(anim.keyframeCount) {
		rl.UpdateModelAnimation(model, anim^, f32(f))
	}
	fmt.eprintfln("%s: survived full idle sweep", model_id)
	rl.UnloadModelAnimations(anims, c.int(anim_count))
}
