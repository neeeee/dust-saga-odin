package gameplay

import sys "../../systems"
import "core:math"
import rl "vendor:raylib"

// Combat + targeting procs, split from the core orchestrator. All state lives
// in the package-level `state` (see gameplay.odin); these procs close over it.

// ── combat ────────────────────────────────────────────────────────────────

apply_combat :: proc(inp: sys.Input_State) {
	// Auto-attack (F): a toggle state, not a held key. F (or a double-click
	// on an enemy, see apply_targeting) engages it; F or Esc cancels. While
	// active the player keeps attacking its target on the cooldown gate.
	if inp.attack {
		if state.auto_attack_active {
			state.auto_attack_active = false
		} else if state.player.target_id != sys.INVALID_ENTITY {
			state.auto_attack_active = true
			try_auto_attack()
		} else {
			sys.push_notification(state.ctx, "No target.", "info")
		}
	}

	if state.auto_attack_active && state.player.target_id != sys.INVALID_ENTITY {
		try_auto_attack()
	}

	// Manual attack (Space), aimed at the cursor and gated by
	// MANUAL_ATTACK_COOLDOWN. Melee weapons (incl. staves and wands) sweep a
	// cone around the aim direction; bows/crossbows loose a single arrow.
	if inp.manual_attack {
		if f64(state.clock_ms - state.player.last_manual_attack_ms) >=
		   sys.COMBAT.MANUAL_ATTACK_COOLDOWN {
			dx, dz, aim_dist := aim_direction()
			sys.send_manual_attack(state.net, math.atan2(dx, dz))
			state.player.last_manual_attack_ms = state.clock_ms
			state.player.attack_anim_until_ms = state.clock_ms + 300
			if player_weapon_is_ranged() {
				spawn_arrow_tracer(dx, dz, aim_dist)
			}
		}
	}
}

// Aim direction (normalized XZ) for a manual attack: from the player toward
// the cursor's ground point. Falls back to screen-forward (opposite the
// camera orbit offset) when the cursor ray misses the ground plane or lands
// on the player. Also returns the aim distance (0 on fallback) so ranged
// tracers know how far the arrow flew.
aim_direction :: proc() -> (dx, dz, dist: f32) {
	ray := rl.GetScreenToWorldRay(rl.GetMousePosition(), state.player.camera)
	hit, point := sys.ray_ground_hit(ray, 0.0)
	if hit {
		px := point.x - state.player.position.x
		pz := point.z - state.player.position.z
		d := math.sqrt(px * px + pz * pz)
		if d > 0.25 {
			return px / d, pz / d, d
		}
	}
	return -math.sin(state.player.yaw), -math.cos(state.player.yaw), 0.0
}

// True when the equipped weapon is a bow/crossbow (ranged manual attack —
// server-authoritative; this only picks the client-side attack visuals).
player_weapon_is_ranged :: proc() -> bool {
	w := &state.player.inventory.equipment[sys.EQUIP_SLOT.WAPON]
	if w.item_id_len == 0 do return false
	def, ok := sys.item_def(sys.item_id_string(w))
	if !ok do return false
	return def.weapon_type == .BOW || def.weapon_type == .CROSSBOW
}

// Visual arrow for a ranged manual attack: a short-lived tracer from the
// player toward the aim point, capped at the ranged attack range.
spawn_arrow_tracer :: proc(dx, dz: f32, aim_dist: f32) {
	dist := sys.GAME.RANGED_ATTACK_RANGE
	if aim_dist > 0.0 {
		dist = math.min(aim_dist + 1.0, dist)
	}
	from := rl.Vector3{
		state.player.position.x + dx * 0.5,
		state.player.position.y + 1.2,
		state.player.position.z + dz * 0.5,
	}
	append(&state.arrows, Arrow_Tracer{
		from,
		{from.x + dx * dist, from.y, from.z + dz * dist},
		ARROW_TRACER_LIFE,
	})
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
	// Aiming a ground-targeted skill — the click is the cast confirm, not a
	// target-pick / click-to-move. update_ground_target handles it.
	if state.ground_target.active do return

	// E: talk to the targeted NPC / open a targeted loot bag (same
	// interactions as double-click).
	if inp.interact && state.player.target_id != sys.INVALID_ENTITY {
		idx := sys.find_index(state.scene, state.player.target_id)
		if idx >= 0 {
			kind := state.scene.metas[idx].kind
			if kind == .NPC {
				try_talk_to(idx)
			} else if kind == .LOOT {
				try_loot(idx)
			}
		}
	}

	// Tab cycle: nearest enemy in view distance.
	if inp.cycle_target != 0 {
		cycle_target(inp.cycle_target > 0)
	}

	// Left-click: ray-pick + double-click interaction.
	// Skip when orbiting camera (right-mouse held hides cursor).
	// Live cursor-over-UI test (the .focused flag is set by menu_update next,
	// so it's a frame stale on the click frame). Covers open menus + the bar.
	if !inp.mouse_left_pressed || state.chat_focused || cursor_over_ui() do return
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
				try_talk_to(idx)
			} else if kind == .ENEMY {
				// Double-click on an enemy: target it and engage auto-attack.
				state.auto_attack_active = true
				try_auto_attack()
			} else if kind == .LOOT {
				try_loot(idx)
			}
		}
		state.last_click_time_ms = 0
	} else {
		state.last_click_time_ms = now
		state.last_click_target = clicked
	}
}

// Send NPC_INTERACT for a targeted NPC, gated by an interaction range slightly
// tighter than the server's 5-unit check (fails locally with feedback instead
// of the packet being dropped silently).
try_talk_to :: proc(idx: int) {
	t := state.scene.transforms[idx]
	dx := state.player.position.x - t.position.x
	dz := state.player.position.z - t.position.z
	if math.sqrt(dx * dx + dz * dz) > 4.5 {
		sys.push_notification(state.ctx, "Move closer to talk.", "info")
		return
	}
	sys.send_npc_interact(state.net, target_string_id())
}

// Open the loot window for a targeted bag (double-click / E). Same range gate
// as the server's pickup check so the window can't open where pickups fail.
try_loot :: proc(idx: int) {
	t := state.scene.transforms[idx]
	dx := state.player.position.x - t.position.x
	dz := state.player.position.z - t.position.z
	if math.sqrt(dx * dx + dz * dz) > 4.5 {
		sys.push_notification(state.ctx, "Move closer to loot.", "info")
		return
	}
	open_loot_menu(state.scene.entity_ids[idx])
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
		// Loot bags are short boxes sitting on the ground — pick against a
		// lower, roomier sphere so clicking the visible box connects.
		if s.metas[i].kind == .LOOT {
			center = rl.Vector3{t.position.x, t.position.y + 0.35, t.position.z}
			r = 0.85
		}
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
