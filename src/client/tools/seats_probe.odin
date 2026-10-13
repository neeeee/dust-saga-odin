package bone_test

// seats: dumps the numbers needed to solve sheath seats / drawn grips offline
// (Bip01 bind + idle matrices, per-seat attach axes in model space, and both
// hand bones in the drawn idles of the axe — known-good left-hand rest — and
// the spear, whose left-hand rest needs fixing). Feed the output to the
// offline solver; verify results with `bone_test.exe sheath quick`.
//
// Run: ./bone_test.exe seats

import "core:fmt"
import rl "vendor:raylib"
import sys "../systems"

seats_dump :: proc(label: string, m: rl.Matrix) {
	o := rl.Vector3Transform({0, 0, 0}, m)
	x := rl.Vector3Transform({1, 0, 0}, m)
	y := rl.Vector3Transform({0, 1, 0}, m)
	z := rl.Vector3Transform({0, 0, 1}, m)
	fmt.eprintfln("%s origin=(%.5f, %.5f, %.5f)", label, o.x, o.y, o.z)
	fmt.eprintfln("%s ax=(%.5f, %.5f, %.5f) ay=(%.5f, %.5f, %.5f) az=(%.5f, %.5f, %.5f)",
		label, x.x-o.x, x.y-o.y, x.z-o.z, y.x-o.x, y.y-o.y, y.z-o.z, z.x-o.x, z.y-o.y, z.z-o.z)
}

seats_seat :: proc(label: string, seat: sys.Chara_Socket_Seat, bip: rl.Matrix, flip: bool) {
	m := bip * (rl.MatrixTranslate(seat.t.x, seat.t.y, seat.t.z) * rl.QuaternionToMatrix(seat.q))
	if flip do m = m * rl.MatrixRotate({0, 1, 0}, 3.14159265)
	seats_dump(label, m)
}

seats_apply :: proc(av: ^sys.Chara_Avatar, clip: int) {
	av.applied_clip = clip
	av.applied_frame = 0
	av.blend_from = -1
	sys.chara_apply_current_pose(av, av.sub.model)
}

seats_probe :: proc() {
	rl.InitWindow(64, 64, "seats")
	tools_clamp_window()
	defer rl.CloseWindow()
	sys.assets_init()

	cm := sys.chara_model_acquire("012")
	if cm == nil do return
	av := sys.chara_avatar_create(cm, 0, 0, 0)
	if av == nil do return

	bip0, ok0 := sys.chara_avatar_bone_matrix(av, "Bip01")
	if ok0 do seats_dump("bip_ascreated", bip0)

	seats_apply(av, av.cm.idle_anim)
	bip1, ok1 := sys.chara_avatar_bone_matrix(av, "Bip01")
	if ok1 do seats_dump("bip_idle", bip1)

	if ok0 {
		seats_seat("seat_HIP", sys.CHARA_SOCKET_HIP, bip0, false)
		seats_seat("seat_BACK", sys.CHARA_SOCKET_BACK, bip0, false)
		seats_seat("seat_BACK_BOW", sys.CHARA_SOCKET_BACK_BOW, bip0, false)
		seats_seat("seat_CROSSBOW", sys.CHARA_SOCKET_CROSSBOW, bip0, true)
	}

	// drawn idles: 2h axe (known-good left-hand rest) and 2h spear (to fix)
	kinds := [2]sys.Weapon_Kind{.TWO_HANDED_AXE, .TWO_HANDED_SPEAR}
	for kind in kinds {
		fam := sys.chara_weapon_family(kind)
		clip := sys.chara_clip(av.cm, fam.idle)
		fmt.eprintfln("kind=%v fam_idle=%s clip=%d", kind, fam.idle, clip)
		if clip < 0 do continue
		seats_apply(av, clip)
		rh, okr := sys.chara_avatar_bone_matrix(av, sys.CHARA_HAND_BONE)
		lh, okl := sys.chara_avatar_bone_matrix(av, "Bip01 L Hand")
		if okr do seats_dump(fmt.tprintf("%v_RHand", kind), rh)
		if okl do seats_dump(fmt.tprintf("%v_LHand", kind), lh)
		gt := sys.chara_drawn_grip_t(kind)
		if okr {
			attach := rh * (rl.MatrixTranslate(gt.x, gt.y, gt.z) * rl.QuaternionToMatrix(sys.CHARA_GRIP_R_Q))
			seats_dump(fmt.tprintf("%v_weapon", kind), attach)
		}
	}
}
