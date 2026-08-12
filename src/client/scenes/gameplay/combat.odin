package gameplay

import sys "../../systems"
import "core:math"
import rl "vendor:raylib"

// Combat + targeting procs, split from the core orchestrator. All state lives
// in the package-level `state` (see gameplay.odin); these procs close over it.

// ── combat ────────────────────────────────────────────────────────────────

apply_combat :: proc(inp: sys.Input_State) {
	// Auto-attack (F): gated by AUTO_ATTACK_BASE_COOLDOWN / attackSpeed.
	if inp.attack && state.player.target_id != sys.INVALID_ENTITY {
		try_auto_attack()
	}

	// Manual cone attack (Space): gated by MANUAL_ATTACK_COOLDOWN.
	if inp.manual_attack {
		if f64(state.clock_ms - state.player.last_manual_attack_ms) >=
		   sys.COMBAT.MANUAL_ATTACK_COOLDOWN {
			sys.send_manual_attack(state.net, state.player.yaw)
			state.player.last_manual_attack_ms = state.clock_ms
		}
	}
}

try_auto_attack :: proc() {
	if state.player.target_id == sys.INVALID_ENTITY do return
	cd := sys.COMBAT.AUTO_ATTACK_BASE_COOLDOWN
	if state.player.stats.cast_speed > 0 {
		cd = math.max(
			sys.COMBAT.AUTO_ATTACK_MIN_COOLDOWN,
			cd / f64(state.player.stats.cast_speed),
		)
	}
	if f64(state.clock_ms - state.player.last_auto_attack_ms) >= cd {
		sys.send_attack(state.net, target_string_id())
		state.player.last_auto_attack_ms = state.clock_ms
		state.player.attack_anim_until_ms = state.clock_ms + 300
	}
}

// ── targeting ─────────────────────────────────────────────────────────────

apply_targeting :: proc(inp: sys.Input_State) {
	// Tab cycle: nearest enemy in view distance.
	if inp.cycle_target != 0 {
		cycle_target(inp.cycle_target > 0)
	}

	// Left-click: ray-pick + double-click interaction.
	// Skip when orbiting camera (right-mouse held hides cursor).
	// Live cursor-over-menu test (any_menu_focused uses the .focused flag which
	// is only set by menu_update next, so it's a frame stale on the click frame).
	if !inp.mouse_left_pressed || state.chat_focused || cursor_over_any_menu() do return
	if rl.IsMouseButtonDown(.RIGHT) do return

	clicked := pick_target_id()
	now := state.clock_ms

	if clicked == sys.INVALID_ENTITY {
		state.last_click_time_ms = 0
		state.last_click_target = sys.INVALID_ENTITY

		// Click-to-move: ray-intersect ground plane.
		ray := rl.GetScreenToWorldRay(rl.GetMousePosition(), state.player.camera)
		hit, point := sys.ray_ground_hit(ray, 0.0)
		if hit && state.ctx.zone != nil {
			half := state.ctx.zone.ground.size / 2.0
			if point.x >= -half && point.x <= half && point.z >= -half && point.z <= half {
				delete(state.click_path)
				state.click_path = sys.compute_move_path(state.ctx.zone, state.player.position, point)
				state.click_path_index = 0
				state.click_move_active = len(state.click_path) > 0
			}
		}
		return
	}

	// Always target the clicked entity.
	state.scene.target_id = clicked
	state.player.target_id = clicked

	// Detect double-click on the same target.
	if clicked == state.last_click_target &&
	   state.last_click_time_ms > 0 &&
	   f64(now - state.last_click_time_ms) < DOUBLE_CLICK_MS {
		idx := sys.find_index(state.scene, clicked)
		if idx >= 0 {
			kind := state.scene.metas[idx].kind
			if kind == .NPC {
				sys.send_npc_interact(state.net, target_string_id())
			} else if kind == .ENEMY {
				try_auto_attack()
			}
		}
		state.last_click_time_ms = 0
	} else {
		state.last_click_time_ms = now
		state.last_click_target = clicked
	}
}

cycle_target :: proc(forward: bool) {
	s := state.scene
	pp := state.player.position
	best_idx := -1
	best_dist := sys.GAME.VIEW_DISTANCE * sys.GAME.VIEW_DISTANCE

	// Collect enemy indices; pick next after current.
	enemy_indices := make([dynamic]int)
	defer delete(enemy_indices)
	for i in 0 ..< s.count {
		if s.metas[i].kind != .ENEMY do continue
		append(&enemy_indices, i)
	}
	if len(enemy_indices) == 0 do return

	cur := sys.find_index(s, state.player.target_id)
	start := 0
	if cur >= 0 {
		// find current's position in enemy list
		for i in 0 ..< len(enemy_indices) {
			if enemy_indices[i] == cur {start = i; break}
		}
	}
	step := forward ? 1 : -1
	idx_in_list := (start + step) % len(enemy_indices)
	if idx_in_list < 0 do idx_in_list += len(enemy_indices)
	best_idx = enemy_indices[idx_in_list]

	if best_idx >= 0 {
		s.target_id = s.entity_ids[best_idx]
		state.player.target_id = s.entity_ids[best_idx]
	}
	_ = best_dist
	_ = pp
}

pick_target :: proc() {
	clicked := pick_target_id()
	if clicked != sys.INVALID_ENTITY {
		state.scene.target_id = clicked
		state.player.target_id = clicked
	}
}

pick_target_id :: proc() -> sys.Entity_Id {
	s := state.scene
	ray := rl.GetScreenToWorldRay(rl.GetMousePosition(), state.player.camera)
	closest := sys.INVALID_ENTITY
	closest_t := f32(math.F32_MAX)

	for i in 0 ..< s.count {
		if s.is_frozen[i] do continue
		t := &s.transforms[i]
		r := s.renderables[i].radius + 0.5
		center := rl.Vector3{t.position.x, t.position.y + 1.0, t.position.z}
		hit, dist := ray_sphere_distance(ray, center, r)
		if hit && dist < closest_t {
			closest_t = dist
			closest = s.entity_ids[i]
		}
	}
	return closest
}

// Returns (hit, distance) for a ray/sphere intersection; hit=false on miss.
ray_sphere_distance :: proc(ray: rl.Ray, center: rl.Vector3, radius: f32) -> (bool, f32) {
	oc := ray.position - center
	a := rl.Vector3DotProduct(ray.direction, ray.direction)
	b := 2.0 * rl.Vector3DotProduct(oc, ray.direction)
	c := rl.Vector3DotProduct(oc, oc) - radius * radius
	disc := b * b - 4 * a * c
	if disc < 0 do return false, 0
	sqrt_disc := math.sqrt(disc)
	t1 := (-b - sqrt_disc) / (2 * a)
	t2 := (-b + sqrt_disc) / (2 * a)
	t := t1
	if t < 0 do t = t2
	if t < 0 do return false, 0
	return true, t
}
