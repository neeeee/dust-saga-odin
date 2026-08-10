package gameplay

import sys "../../systems"
import ui "../../ui"
import "core:fmt"
import "core:math"
import rl "vendor:raylib"

// The gameplay scene owns the game context (network + scene + local player +
// chat + zone), runs the 3rd-person camera + movement loop, sends PLAYER_MOVE
// at the server's expected cadence, drives combat cooldowns and targeting, and
// renders the 3D world + 2D HUD/chat.
//
// This mirrors the orchestration in packages/client/src/core/GameClient.ts
// (gameLoop / update / setupNetworkHandlers), but renders with raylib
// primitives instead of Babylon.

CAMERA_DISTANCE :: 6.0
CAMERA_HEIGHT :: 4.0
CAMERA_LERP :: 8.0 // higher = snappier follow
TELEPORT_COOLDOWN_MS :: 3000.0
DOUBLE_CLICK_MS :: 500.0

State :: enum {
	IDLE,
	PLAYING,
	RETURNING,
}

Bar_Button :: struct {
	label: string,
	menu:  ^ui.Menu,
}

state: struct {
	ctx:                    ^sys.Game_Context,
	net:                    ^sys.Network_Client,
	scene:                  ^sys.Scene,
	player:                 ^sys.Local_Player,
	chat:                   ^sys.Chat_Log,
	status:                 State,

	// movement send throttle + clock
	last_move_send_ms:      u64,
	clock_ms:               u64,
	server_clock_offset_ms: u64,

	// chat typing buffer
	chat_buf:               [256]u8,
	chat_len:               int,
	chat_focused:           bool,
	// teleport cooldown
	last_teleport_ms:       u64,
	initialized:            bool,
	was_connected:          bool,

	// menus
	inventory_menu:         ui.Menu,
	settings_menu:          ui.Menu,
	skills_menu:            ui.Menu,
	friends_menu:           ui.Menu,
	party_menu:             ui.Menu,
	quest_list_menu:        ui.Menu,
	accept_deny_menu:       ui.Menu,
	blacksmith_menu:        ui.Menu,
	soul_extraction_menu:   ui.Menu,
	character_profile_menu: ui.Menu,
	loot_drop_menu:         ui.Menu,
	loot_party_menu:        ui.Menu,
	shop_menu:              ui.Menu,
	system_menu:            ui.Menu,
	shop_cache:             sys.Shop_Cache,
	shop_visible_indices:   [dynamic]int,
	bar_buttons:            [dynamic]Bar_Button,

	last_click_time_ms:     u64,
	last_click_target:      sys.Entity_Id,

	click_path:            [dynamic]rl.Vector3,
	click_path_index:      int,
	click_move_active:     bool,

	logout_start_ms:        u64,
	exit_start_ms:         u64,
}


// Allocate everything gameplay needs. The network client / scene / player /
// chat are passed in from main (which owns their lifetimes across state
// transitions so reconnecting keeps working).
init :: proc(
	net: ^sys.Network_Client,
	scene: ^sys.Scene,
	player: ^sys.Local_Player,
	chat: ^sys.Chat_Log,
) {
	state.net = net
	state.scene = scene
	state.player = player
	state.chat = chat
	state.ctx = sys.game_context_init(net, scene, player, chat)

	// Camera: third-person, looking down at the player from behind.
	sys.init_camera(state.player)

	state.status = .PLAYING
	state.initialized = true
	state.was_connected = true
	state.last_move_send_ms = sys.now_ms()
	state.clock_ms = sys.now_ms()
	init_menus()
}

shutdown :: proc() {
	if state.ctx != nil do sys.game_context_destroy(state.ctx)
	state.ctx = nil
	state.initialized = false
	state.status = .IDLE
	state.chat_focused = false
	state.chat_len = 0
}

// Called every frame from main. dt is seconds.
update :: proc(dt: f32) -> (requested: sys.App_State, has_request: bool) {
	if !state.initialized do return .TITLE, false

	state.clock_ms = sys.now_ms()

	// 1. Pump the network and dispatch inbound packets.
	sys.update_network(state.net)

	// Detect reconnection and re-authenticate.
	if sys.is_connected(state.net) && !state.was_connected {
		state.was_connected = true
		sys.net_log("gameplay: reconnected, clearing stale scene entities")
		sys.scene_clear(state.scene)
		state.ctx.zone_loaded = false
		state.ctx.clock_synced = false
		if sys.has_auth_credentials(state.net) {
			sys.net_log("gameplay: reconnected, sending LOGIN to re-authenticate")
			sys.send_login(
				state.net,
				sys.get_auth_username(state.net),
				sys.get_auth_password(state.net),
			)
			state.net.auth_sent = true
		}
	} else if !sys.is_connected(state.net) {
		state.was_connected = false
	}

	for &p in sys.poll_inbound(state.net) {
		sys.handle_packet(state.ctx, &p, true)
	}

	// 2. Input.
	inp := sys.poll_input(state.chat_focused, false, state.player, dt)
	handle_chat_input(inp)

	// 2b. ESC chain: close menus → unfocus chat → untarget → toggle system menu.
	apply_escape()

	// 2c. System menu button clicks (must happen before gameplay menus update).
	handle_system_menu_clicks(inp)

	if state.status == .RETURNING {
		return .CHARACTER_SELECT, true
	}

	if state.player.is_dead {
		// Allow only respawn request (R) while dead.
		if inp.toggle_rest || rl.IsKeyPressed(.R) {
			sys.send(state.net, .RESPAWN_REQUEST)
		}
		update_timers(dt)
		return .TITLE, false
	}

	// 3. Movement (input integration happens in poll_input). Send the local
	//    player's position to the server at a fixed cadence — UNCONDITIONALLY,
	//    even when idle. The server centers its enemy-interest broadcast on the
	//    last position it received from us (NetworkServer broadcastEntityStates,
	//    ~50-unit radius). If we only send while moving, our server-side
	//    position goes stale the moment we stop, and nearby enemies get culled
	//    from the broadcast → they appear frozen. The TS client sends every
	//    ~50ms regardless of input (GameClient.ts sendMovement block).
	apply_movement(inp, dt)
	send_movement_tick()

	// 4. Combat.
	apply_combat(inp)

	// 5. Targeting.
	apply_targeting(inp)

	// 6. Skill bar.
	if inp.skill_slot >= 0 {
		name := sys.skill_bar_get(state.player, inp.skill_slot)
		if len(name) > 0 {
			sys.send_skill_use(state.net, name, target_string_id())
		}
	}

	// 7. Interaction is handled via double-click in apply_targeting.
	if inp.toggle_rest {
		sys.send(state.net, .PLAYER_REST)
	}

	// 8. Teleport pads.
	check_teleports()

	// 9. Update entity scene (culling + interpolation) and cooldowns.
	ppos := [3]f32{state.player.position.x, state.player.position.y, state.player.position.z}
	sys.update(state.scene, dt, f64(rl.GetTime()), ppos, int(rl.GetFPS()))
	tick_cooldowns(dt)
	tick_notifications(dt)
	tick_floating(dt)
	tick_cast(dt)

	// 10. Camera follow.
	sys.update_camera(dt, state.player)

	// 11. Toggle inventory.
	if rl.IsKeyPressed(.I) do ui.menu_toggle(&state.inventory_menu)

	// 12. Menus.
	update_menus()

	// 13. Logout/exit timers.
	if state.logout_start_ms > 0 && f64(state.clock_ms - state.logout_start_ms) >= 30000.0 {
		return .CHARACTER_SELECT, true
	}
	if state.exit_start_ms > 0 && f64(state.clock_ms - state.exit_start_ms) >= 30000.0 {
		return .TITLE, true
	}

	return .TITLE, false
}

update_timers :: proc(dt: f32) {
	tick_notifications(dt)
	tick_floating(dt)
	ppos := [3]f32{state.player.position.x, state.player.position.y, state.player.position.z}
	sys.update(state.scene, dt, f64(rl.GetTime()), ppos, int(rl.GetFPS()))
	sys.update_camera(dt, state.player)
}

// ── movement ──────────────────────────────────────────────────────────────

// Input integration is done in poll_input; this is currently a no-op stub kept
// for clarity / future camera-relative movement work.
apply_movement :: proc(inp: sys.Input_State, dt: f32) {
	if inp.moving {
		cancel_click_to_move()
	}
	follow_click_path(dt)
}

follow_click_path :: proc(dt: f32) {
	if !state.click_move_active do return
	if state.click_path_index >= len(state.click_path) do return

	target := state.click_path[state.click_path_index]
	dx := target.x - state.player.position.x
	dz := target.z - state.player.position.z
	dist := math.sqrt(dx * dx + dz * dz)

	if dist < 0.5 {
		state.click_path_index += 1
		if state.click_path_index >= len(state.click_path) {
			state.click_move_active = false
		}
	} else {
		speed := sys.GAME.PLAYER_SPEED * dt
		if speed > dist do speed = dist
		state.player.position.x += (dx / dist) * speed
		state.player.position.z += (dz / dist) * speed
		state.player.yaw = math.atan2(dx, dz)
	}
}

	cancel_click_to_move :: proc() {
	state.click_move_active = false
	state.click_path_index = 0
	delete(state.click_path)
	state.click_path = make([dynamic]rl.Vector3)
}

// ── escape chain ───────────────────────────────────────────────────────

apply_escape :: proc() {
	esc := rl.IsKeyPressed(.ESCAPE)
	if !esc do return

	// 1. Close any open/focused menu.
	if any_menu_focused() do return
	for &entry in state.bar_buttons {
		if entry.menu.open && entry.menu.focused { ui.menu_close(entry.menu); return }
	}
	// Non-bar menus (checked individually for correctness).
	if state.inventory_menu.open     { ui.menu_close(&state.inventory_menu);     return }
	if state.settings_menu.open      { ui.menu_close(&state.settings_menu);      return }
	if state.skills_menu.open        { ui.menu_close(&state.skills_menu);        return }
	if state.friends_menu.open       { ui.menu_close(&state.friends_menu);       return }
	if state.party_menu.open         { ui.menu_close(&state.party_menu);         return }
	if state.quest_list_menu.open    { ui.menu_close(&state.quest_list_menu);    return }
	if state.accept_deny_menu.open   { ui.menu_close(&state.accept_deny_menu);   return }
	if state.blacksmith_menu.open    { ui.menu_close(&state.blacksmith_menu);    return }
	if state.soul_extraction_menu.open { ui.menu_close(&state.soul_extraction_menu); return }
	if state.character_profile_menu.open { ui.menu_close(&state.character_profile_menu); return }
	if state.loot_drop_menu.open     { ui.menu_close(&state.loot_drop_menu);     return }
	if state.loot_party_menu.open    { ui.menu_close(&state.loot_party_menu);    return }
	if state.shop_menu.open          { ui.menu_close(&state.shop_menu);          return }
	if state.system_menu.open        { ui.menu_close(&state.system_menu);        return }

	// 2. Unfocus chat.
	if state.chat_focused {
		state.chat_focused = false
		state.chat_len = 0
		return
	}

	// 3. Clear target.
	if state.player.target_id != sys.INVALID_ENTITY {
		state.scene.target_id = sys.INVALID_ENTITY
		state.player.target_id = sys.INVALID_ENTITY
		state.last_click_time_ms = 0
		state.last_click_target = sys.INVALID_ENTITY
		cancel_click_to_move()
		return
	}

	// 4. Toggle system menu.
	if state.system_menu.open {
		ui.menu_close(&state.system_menu)
	} else {
		ui.menu_open(&state.system_menu)
		state.logout_start_ms = 0
		state.exit_start_ms = 0
	}
}

// Throttle PLAYER_MOVE to MOVEMENT_SEND_RATE_MS and fire it regardless of
// whether the player is moving (see update() for why this must be
// unconditional). Mirrors the TS client's per-frame sendMovement cadence.
send_movement_tick :: proc() {
	if f64(state.clock_ms - state.last_move_send_ms) >= sys.NET.MOVEMENT_SEND_RATE_MS {
		send_player_move()
		state.last_move_send_ms = state.clock_ms
	}
}

send_player_move :: proc() {
	pos_fields := make([dynamic]sys.JSON_Field, 3)
	defer delete(pos_fields)
	pos_fields[0] = sys.JSON_Field{"x", sys.json_float(state.player.position.x)}
	pos_fields[1] = sys.JSON_Field{"y", sys.json_float(state.player.position.y)}
	pos_fields[2] = sys.JSON_Field{"z", sys.json_float(state.player.position.z)}
	pos := sys.build_object(pos_fields[:])

	// rotation as a quaternion facing yaw (Y-axis only).
	q := yaw_to_quat(state.player.yaw)
	rot_fields := make([dynamic]sys.JSON_Field, 4)
	defer delete(rot_fields)
	rot_fields[0] = sys.JSON_Field{"x", sys.json_float(q[0])}
	rot_fields[1] = sys.JSON_Field{"y", sys.json_float(q[1])}
	rot_fields[2] = sys.JSON_Field{"z", sys.json_float(q[2])}
	rot_fields[3] = sys.JSON_Field{"w", sys.json_float(q[3])}
	rot := sys.build_object(rot_fields[:])

	fields := make([dynamic]sys.JSON_Field, 2)
	defer delete(fields)
	fields[0] = sys.JSON_Field{"position", pos^}
	fields[1] = sys.JSON_Field{"rotation", rot^}
	sys.send_object(state.net, .PLAYER_MOVE, fields[:])
}

yaw_to_quat :: proc "contextless" (yaw: f32) -> [4]f32 {
	// quaternion for a rotation about Y by `yaw`.
	half := yaw * 0.5
	return {0, math.sin(half), 0, math.cos(half)}
}

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
	if !inp.mouse_left_pressed || state.chat_focused || any_menu_focused() do return
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

// ── teleports ─────────────────────────────────────────────────────────────

check_teleports :: proc() {
	if state.ctx.zone == nil do return
	idx := sys.check_teleport(state.ctx.zone, state.player.position)
	if idx < 0 do return
	if f64(state.clock_ms - state.last_teleport_ms) < TELEPORT_COOLDOWN_MS do return
	tp := state.ctx.zone.teleporters[idx]
	state.last_teleport_ms = state.clock_ms
	sys.send_enter_zone(state.net, tp.target_zone)
}

// ── chat ──────────────────────────────────────────────────────────────────

handle_chat_input :: proc(inp: sys.Input_State) {
	if inp.chat_toggle && !state.chat_focused {
		state.chat_focused = true
		state.chat_len = 0
		return
	}
	if !state.chat_focused do return

	if inp.chat_cancel {
		state.chat_focused = false
		state.chat_len = 0
		return
	}
	if inp.chat_backspace && state.chat_len > 0 {
		state.chat_len -= 1
	}
	if inp.chat_submit {
		msg := string(state.chat_buf[:state.chat_len])
		if len(msg) > 0 {
			sys.send_chat(state.net, msg)
		}
		state.chat_focused = false
		state.chat_len = 0
		return
	}
	// Append typed characters.
	c := rl.GetCharPressed()
	for c != 0 {
		if state.chat_len < len(state.chat_buf) && c >= 32 && c < 127 {
			state.chat_buf[state.chat_len] = u8(c)
			state.chat_len += 1
		}
		c = rl.GetCharPressed()
	}
}

// ── per-frame tickers ─────────────────────────────────────────────────────

tick_cooldowns :: proc(dt: f32) {
	ms := f64(dt * 1000.0)
	i := 0
	for i < len(state.player.cooldowns) {
		state.player.cooldowns[i].remaining_ms -= ms
		if state.player.cooldowns[i].remaining_ms <= 0 {
			delete_at_index(&state.player.cooldowns, i)
		} else {
			i += 1
		}
	}
}

tick_notifications :: proc(dt: f32) {
	i := 0
	for i < len(state.ctx.notifications) {
		state.ctx.notifications[i].life -= dt
		if state.ctx.notifications[i].life <= 0 {
			delete_at_index(&state.ctx.notifications, i)
		} else {
			i += 1
		}
	}
}

tick_floating :: proc(dt: f32) {
	i := 0
	for i < len(state.ctx.floating) {
		state.ctx.floating[i].life -= dt
		if state.ctx.floating[i].life <= 0 {
			delete_at_index(&state.ctx.floating, i)
		} else {
			i += 1
		}
	}
}

tick_cast :: proc(dt: f32) {
	if state.player.casting.active {
		state.player.casting.elapsed += f64(dt * 1000.0)
	}
}

// Remove element at `idx` from a [dynamic], shifting subsequent elements down.
// Order-preserving (unlike swap-remove); fine for our tiny lists.
delete_at_index :: proc(d: ^[dynamic]$T, idx: int) {
	last := len(d) - 1
	for i in idx ..< last {
		d^[i] = d^[i + 1]
	}
	resize(d, last)
}

// Resolve the current target's original server string id (for ATTACK / SKILL /
// NPC_INTERACT payloads). Returns "" if no target.
target_string_id :: proc() -> string {
	idx := sys.find_index(state.scene, state.player.target_id)
	if idx < 0 do return ""
	return sys.get_entity_string_id(state.scene, idx)
}

// ── camera ────────────────────────────────────────────────────────────────


// Component-wise lerp for Vector3 (avoids the deprecated Vector3Lerp wrapper).
v3lerp :: proc "contextless" (a, b: rl.Vector3, t: f32) -> rl.Vector3 {
	return {a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t}
}

// ── render ────────────────────────────────────────────────────────────────

render :: proc() {
	if !state.initialized do return

	rl.ClearBackground(rl.SKYBLUE)

	rl.BeginMode3D(state.player.camera)
	if state.ctx.zone != nil {
		sys.render_zone(state.ctx.zone)
	}
	// Draw the local player as a capsule too (distinct color).
	draw_local_player()
	sys.render(state.scene, state.player.camera)
	rl.EndMode3D()

	// 2D entity nameplates / health bars / target indicators.
	sys.render_entity_ui_2d(state.scene, state.player.camera)

	// 2D HUD.
	draw_hud()
	draw_target_window()
	draw_floating_text()
	draw_chat()
	draw_notifications()
	draw_menu_bar()
	draw_menus()
	if state.player.is_dead do draw_death_overlay()
}

draw_local_player :: proc() {
	p := state.player.position
	pos := rl.Vector3{p.x, p.y + 0.9, p.z}
	axis, angle := sys.euler_y_to_raylib(state.player.yaw)
	col := rl.Color{100, 180, 255, 255}
	if state.player.is_resting do col = {120, 120, 180, 255}
	if state.player.is_dead do col = {120, 120, 120, 255}
	rl.DrawModelEx(state.scene.model_capsule, pos, axis, angle, {1, 1, 1}, col)
}

draw_hud :: proc() {
	// Health + mana bars bottom-left.
	s := &state.player.stats
	hp_ratio := s.max_health > 0 ? s.health / s.max_health : 0
	mp_ratio := s.max_mana > 0 ? s.mana / s.max_mana : 0
	draw_bar(
		20,
		20,
		240,
		18,
		hp_ratio,
		rl.RED,
		fmt.tprintf("HP %d/%d", i32(s.health), i32(s.max_health)),
	)
	draw_bar(
		20,
		43,
		240,
		14,
		mp_ratio,
		rl.BLUE,
		fmt.tprintf("MP %d/%d", i32(s.mana), i32(s.max_mana)),
	)

	// Level + zone top-left.
	sys.draw_text(
		fmt.tprintf("Lv %d  %s", s.level, string(state.player.name[:state.player.name_len])),
		20,
		12,
		20,
		rl.WHITE,
	)

	// Skill bar bottom-center.
	draw_skill_bar()

	// Cast bar (centered, above skill bar).
	if state.player.casting.active {
		c := state.player.casting
		ratio := c.cast_time > 0 ? f32(c.elapsed / c.cast_time) : 1.0
		draw_bar(540, 620, 200, 16, ratio, rl.ORANGE, "")
	}

	// Connection status top-right.
	status_text := "Connected"
	if !sys.is_connected(state.net) do status_text = "Connecting…"
	sys.draw_text(status_text, 1130, 12, 16, sys.is_connected(state.net) ? rl.GREEN : rl.YELLOW)
}

	draw_bar :: proc(x, y, w, h: i32, ratio: f32, color: rl.Color, label: string) {
	r := math.clamp(ratio, 0, 1)
	rl.DrawRectangle(x, y, w, h, rl.Color{30, 30, 30, 220})
	rl.DrawRectangle(x, y, i32(f32(w) * r), h, color)
	rl.DrawRectangleLines(x, y, w, h, rl.BLACK)
	if len(label) > 0 {
		sys.draw_text(label, int(x + 6), int(y + (h - 14) / 2), 12, rl.WHITE)
	}
}

draw_target_window :: proc() {
	s := state.scene
	if s.target_id == sys.INVALID_ENTITY do return
	idx := sys.find_index(s, s.target_id)
	if idx < 0 do return

	ui := &s.ui[idx]
	meta := &s.metas[idx]
	ef := &s.effects[idx]

	name := string(ui.name_str[:ui.name_len])
	if len(name) == 0 do return

	screen_w := int(rl.GetScreenWidth())
	win_w := 250
	win_x := screen_w / 2 - win_w / 2
	win_y := 70

	kind := meta.kind

	name_col: rl.Color
	if kind == .ENEMY {
		name_col = {255, 100, 100, 255}
	} else if kind == .NPC {
		name_col = {255, 255, 100, 255}
	} else {
		name_col = {130, 180, 255, 255}
	}

	row_h := 20
	cur_y := win_y

	// Background panel.
	panel_h := row_h + 4
	show_hp := meta.max_health > 0.0
	if show_hp do panel_h += 24
	if ef.count > 0 do panel_h += 22

	rl.DrawRectangle(i32(win_x), i32(cur_y), i32(win_w), i32(panel_h), rl.Color{20, 20, 30, 210})
	rl.DrawRectangleLines(i32(win_x), i32(cur_y), i32(win_w), i32(panel_h), rl.Color{80, 80, 100, 200})

	// Row 1: name + level.
	if kind != .NPC && meta.level > 0 {
		sys.draw_text(fmt.tprintf("Lv%d", meta.level), win_x + 8, cur_y + 2, 14, rl.GRAY)
		sys.draw_text(name, win_x + 52, cur_y + 2, 14, name_col)
	} else {
		sys.draw_text(name, win_x + 8, cur_y + 2, 14, name_col)
	}
	cur_y += row_h

	// Row 2: health bar (enemies, players, summons — not NPCs).
	if show_hp {
		hp_ratio := meta.max_health > 0 ? meta.health / meta.max_health : 0
		hp_text := fmt.tprintf("%d / %d", i32(meta.health), i32(meta.max_health))
		bar_bg := rl.Color{60, 10, 10, 255}
		bar_fg: rl.Color
		if hp_ratio < 0.25 { bar_fg = rl.RED
		} else if hp_ratio < 0.5 { bar_fg = rl.YELLOW
		} else { bar_fg = {200, 40, 40, 255} }
		rl.DrawRectangle(i32(win_x + 8), i32(cur_y), i32(win_w - 16), 18, bar_bg)
		fill := i32(f32(win_w - 16) * math.clamp(hp_ratio, 0, 1))
		rl.DrawRectangle(i32(win_x + 8), i32(cur_y), fill, 18, bar_fg)
		rl.DrawRectangleLines(i32(win_x + 8), i32(cur_y), i32(win_w - 16), 18, rl.BLACK)
		sys.draw_text(hp_text, win_x + 14, cur_y + 2, 12, rl.WHITE)
		cur_y += 22
	}

	// Row 3: buff / debuff icons.
	if ef.count > 0 {
		icon_x := win_x + 8
		icon_size := 20
		now := sys.now_ms()
		for i in 0 ..< ef.count {
			e := &ef.effects[i]
			if e.expires_at > 0 && now >= e.expires_at do continue

			bg_col: rl.Color
			if e.is_buff { bg_col = {50, 140, 50, 200}
			} else { bg_col = {160, 40, 40, 200} }

			rl.DrawRectangle(i32(icon_x), i32(cur_y), i32(icon_size), i32(icon_size), bg_col)
			rl.DrawRectangleLines(i32(icon_x), i32(cur_y), i32(icon_size), i32(icon_size), rl.Color{40, 40, 40, 200})

			a, b := sys.status_effect_label(string(e.type_str[:e.type_len]))
			label := [2]byte{a, b}
			sys.draw_text(string(label[:]), icon_x + 2, cur_y + 3, 12, rl.WHITE)

			if e.expires_at > 0 {
				rem := f64(e.expires_at - now) / 1000.0
				if rem < 60 {
					sec := fmt.tprintf("%.0f", rem)
					sw := sys.measure_text(sec, 8)
					sys.draw_text(sec, icon_x + icon_size - sw - 1, cur_y + icon_size - 10, 8, {200, 200, 200, 200})
				} else {
					min := fmt.tprintf("%dm", i32(rem / 60.0))
					sw := sys.measure_text(min, 8)
					sys.draw_text(min, icon_x + icon_size - sw - 1, cur_y + icon_size - 10, 8, {200, 200, 200, 200})
				}
			}

			icon_x += icon_size + 2
			if icon_x + icon_size > win_x + win_w - 4 do break
		}
	}
}

draw_skill_bar :: proc() {
	for slot in 0 ..< 10 {
		x := 440 + slot * 44
		rect := rl.Rectangle{f32(x), 660, 40, 40}
		rl.DrawRectangleRec(rect, rl.Color{30, 30, 40, 220})
		rl.DrawRectangleLinesEx(rect, 1, rl.BLACK)
		name := sys.skill_bar_get(state.player, slot)
		label := fmt.tprintf("%d", (slot + 1) % 10)
		sys.draw_text(label, x + 4, 660 + 2, 12, rl.GRAY)
		if len(name) > 0 {
			sys.draw_text(name[:1], x + 16, 660 + 16, 12, rl.WHITE)
		}
	}
}

any_menu_focused :: proc() -> bool {
	return state.inventory_menu.focused   ||
	       state.settings_menu.focused    ||
	       state.skills_menu.focused      ||
	       state.friends_menu.focused     ||
	       state.party_menu.focused       ||
	       state.quest_list_menu.focused ||
	       state.shop_menu.focused      ||
	       state.system_menu.focused
}


draw_floating_text :: proc() {
	for &f in state.ctx.floating {
		sp := rl.GetWorldToScreen(f.world_pos, state.player.camera)
		// GetWorldToScreen returns Vector2; off-screen cull only.
		alpha := u8(math.clamp(f.life, 0, 1) * 255.0)
		col := f.color
		col.a = alpha
		text: string = ""
		if f.is_miss {
			text = "miss"
		} else {
			text = fmt.tprintf("%s%d", f.is_heal ? "+" : "-", f.amount)
		}
		size := f.is_crit ? 22 : 16
		rise := int((1.0 - f.life) * 30)
		sys.draw_text(text, int(sp.x) - 8, int(sp.y) - 30 - rise, size, col)
	}
}

draw_chat :: proc() {
	// Last few chat lines bottom-left, above the HUD bars.
	y := 600
	start := len(state.chat.lines) - 8
	if start < 0 do start = 0
	for i in start ..< len(state.chat.lines) {
		line := state.chat.lines[i]
		sender := string(line.sender[:line.sender_len])
		message := string(line.message[:line.msg_len])
		text := fmt.tprintf("[%s] %s: %s", sys.chat_channel_name(line.channel), sender, message)
		col := sys.chat_channel_color(line.channel)
		sys.draw_text(text, 20, y, 14, col)
		y -= 18
	}

	// Chat input box.
	if state.chat_focused {
		box := rl.Rectangle{20, 620, 400, 24}
		rl.DrawRectangleRec(box, rl.Color{0, 0, 0, 200})
		rl.DrawRectangleLinesEx(box, 1, rl.WHITE)
		typed := string(state.chat_buf[:state.chat_len])
		sys.draw_text(fmt.tprintf("%s_", typed), 26, 624, 14, rl.WHITE)
	} else {
		sys.draw_text("Press Enter to chat", 20, 624, 12, rl.GRAY)
	}
}

draw_notifications :: proc() {
	y := 40
	for &n in state.ctx.notifications {
		alpha := u8(math.clamp(n.life, 0, 1) * 255.0)
		col := rl.WHITE
		if n.kind_len >= 5 && string(n.kind[:5]) == "error" do col = rl.RED
		col.a = alpha
		msg := string(n.message[:n.msg_len])
		sys.draw_text(msg, 540, y, 18, col)
		y += 24
	}
}

draw_death_overlay :: proc() {
	rl.DrawRectangle(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight(), rl.Color{80, 0, 0, 140})
	msg := "You died — press R to respawn"
	w := sys.measure_text(msg, 28)
	half_w := int(rl.GetScreenWidth()) / 2 - w / 2
	half_h := int(rl.GetScreenHeight()) / 2
	sys.draw_text(msg, half_w, half_h, 28, rl.WHITE)
}
