package gameplay

import sys "../../systems"
import ui "../../ui"
import "core:math"
import rl "vendor:raylib"

// The gameplay scene owns the game context (network + scene + local player +
// chat + zone), runs the 3rd-person camera + movement loop, sends PLAYER_MOVE
// at the server's expected cadence, drives combat cooldowns and targeting, and
// renders the 3D world + 2D HUD/chat.
//
// This file holds the core orchestrator (state + lifecycle + update loop +
// movement + tickers + chat). Combat/targeting live in combat.odin; rendering
// lives in render.odin; menus live in menus.odin.
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

// Set by the Exit Game countdown; main watches it to break the run loop. The
// deferred destroy_network_client sends the final LOGOUT on the way out.
quit_requested: bool

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
	character_profile_menu: ui.Menu,	loot_drop_menu:         ui.Menu,
	loot_party_menu:        ui.Menu,
	shop_menu:              ui.Menu,
	system_menu:            ui.Menu,
	debug_menu:             ui.Menu,
	shop_cache:             sys.Shop_Cache,
	shop_visible_indices:   [dynamic]int,
	bar_buttons:            [dynamic]Bar_Button,

	last_click_time_ms:     u64,
	last_click_target:      sys.Entity_Id,

	click_path:             [dynamic]rl.Vector3,
	click_path_index:       int,
	click_move_active:      bool,

	// Skill bar drag state.
	dragging_bar:           int,  // -1 = not dragging
	drag_offset:            rl.Vector2,

	// Ground-targeted skill aiming: when active, a reticle follows the cursor
	// and the next left-click casts at that ground point (Esc cancels).
	ground_target:          Ground_Target,

	logout_start_ms:        u64,
	exit_start_ms:          u64,
}

Ground_Target :: struct {
	active:     bool,
	skill_name: [64]u8,
	name_len:   int,
	radius:     f32,
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

	// 2. Death check — BEFORE gameplay input. When dead, no movement/skills/
	//    menus run. The player chooses to respawn via the overlay button
	//    (Pandora Saga: you respawn at your homepoint, or stay dead waiting
	//    for a Priest/Cleric/Enchanter revive). If the player disconnects
	//    while dead, they reconnect dead in the same place.
	if state.player.is_dead {
		p := state.player
		if !p.respawn_sent {
			mouse := rl.GetMousePosition()
			btn := death_respawn_btn_rect()
			if rl.CheckCollisionPointRec(mouse, btn) && rl.IsMouseButtonPressed(.LEFT) {
				sys.send(state.net, .RESPAWN_REQUEST)
				p.respawn_sent = true
			}
		}
		update_timers(dt)
		return .TITLE, false
	}

	// 3. Input.
	inp := sys.poll_input(state.chat_focused, state.player, dt)
	handle_chat_input(inp)

	// 2b. ESC chain: close menus → unfocus chat → untarget → toggle system menu.
	apply_escape()

	if state.status == .RETURNING {
		return .CHARACTER_SELECT, true
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

	// 5. Targeting (suppressed while aiming a ground-targeted skill).
	apply_targeting(inp)

	// 5b. Ground-targeted skill aiming: confirm/cancel an armed reticle.
	update_ground_target(inp)

	// 6. Skill bar — keyboard (digits 1-0 → bar 0) + mouse click on any bar.
	//    Ground-targeted skills arm the reticle; TARGET_CENTERED AOE sends
	//    aoePosition from the target's ground position.
	handle_skill_bar_input(inp)

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
	sys.update_camera(dt, state.player, cursor_over_ui())

	// 11. Menu shortcuts — routed through menu_keybind (rebindable + auto-
	// suppressed while chatting).
	menu_keybind(&state.inventory_menu, .Menu_Inventory)
	menu_keybind(&state.character_profile_menu, .Menu_Character)
	menu_keybind(&state.skills_menu, .Menu_Skills)
	menu_keybind(&state.debug_menu, .Menu_Debug)

	// 12. Menus.
	update_menus()

	// 13. Logout/exit countdowns. When they elapse, perform the actual
	//     handoff (previously this only switched scenes and never told the
	//     server, so the character stayed online until ping-timeout).
	if state.logout_start_ms > 0 && f64(state.clock_ms - state.logout_start_ms) >= 30000.0 {
		state.logout_start_ms = 0
		// RETURN_TO_CHARACTER_SELECT saves the char server-side and drops the
		// session but keeps the socket/auth, so char-select can re-list without
		// re-authenticating.
		sys.send(state.net, .RETURN_TO_CHARACTER_SELECT)
		return .CHARACTER_SELECT, true
	}
	if state.exit_start_ms > 0 && f64(state.clock_ms - state.exit_start_ms) >= 30000.0 {
		state.exit_start_ms = 0
		// Signal main to break the loop; its deferred destroy_network_client
		// sends the final LOGOUT (save + disconnect) on the way out.
		quit_requested = true
		return .GAMEPLAY, false
	}

	return .TITLE, false
}

update_timers :: proc(dt: f32) {
	tick_notifications(dt)
	tick_floating(dt)
	ppos := [3]f32{state.player.position.x, state.player.position.y, state.player.position.z}
	sys.update(state.scene, dt, f64(rl.GetTime()), ppos, int(rl.GetFPS()))
	sys.update_camera(dt, state.player, cursor_over_ui())
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
	clear(&state.click_path)
}

// ── escape chain ───────────────────────────────────────────────────────────

apply_escape :: proc() {
	esc := rl.IsKeyPressed(.ESCAPE)
	if !esc do return

	// Cancel a ground-target reticle first (before the menu/escape chain).
	if state.ground_target.active {
		state.ground_target.active = false
		return
	}

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

// Ground-targeted skill aiming. While a ground skill is armed, a reticle follows
// the cursor (drawn in render.odin); Esc cancels, a left-click on the world
// casts at that ground point. Movement/camera still work while aiming.
update_ground_target :: proc(inp: sys.Input_State) {
	gt := &state.ground_target
	if !gt.active do return

	if rl.IsKeyPressed(.ESCAPE) {
		gt.active = false
		return
	}

	if inp.mouse_left_pressed && !cursor_over_ui() {
		ray := rl.GetScreenToWorldRay(rl.GetMousePosition(), state.player.camera)
		hit, point := sys.ray_ground_hit(ray, 0.0)
		if hit && state.ctx.zone != nil {
			half := state.ctx.zone.ground.size / 2.0
			if point.x >= -half && point.x <= half && point.z >= -half && point.z <= half {
				name := string(gt.skill_name[:gt.name_len])
				sys.send_skill_use_ground(state.net, name, point.x, point.y, point.z)
			}
		}
		gt.active = false
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

any_menu_focused :: proc() -> bool {
	return state.inventory_menu.open       && state.inventory_menu.focused ||
	       state.settings_menu.open        && state.settings_menu.focused ||
	       state.skills_menu.open          && state.skills_menu.focused ||
	       state.friends_menu.open         && state.friends_menu.focused ||
	       state.party_menu.open           && state.party_menu.focused ||
	       state.quest_list_menu.open      && state.quest_list_menu.focused ||
	       state.accept_deny_menu.open     && state.accept_deny_menu.focused ||
	       state.blacksmith_menu.open      && state.blacksmith_menu.focused ||
	       state.soul_extraction_menu.open && state.soul_extraction_menu.focused ||
	       state.character_profile_menu.open && state.character_profile_menu.focused ||
	       state.loot_drop_menu.open       && state.loot_drop_menu.focused ||
	       state.loot_party_menu.open      && state.loot_party_menu.focused ||
	       state.shop_menu.open            && state.shop_menu.focused ||
	       state.system_menu.open          && state.system_menu.focused ||
	       state.debug_menu.open           && state.debug_menu.focused
}

// True if the cursor is over UI chrome — the menu bar (always present) or any
// open menu window. Used for two gates: (a) the scroll wheel goes to a menu
// rather than zooming the camera, and (b) click-to-move won't walk the
// character when clicking on the bar / a window.
cursor_over_ui :: proc() -> bool {
	mouse := rl.GetMousePosition()

	// Skill bars (draggable hotbars).
	if cursor_over_skill_bar() do return true

	// Menu bar (top-left button strip) — always interactable.
	if len(state.bar_buttons) > 0 {
		bar_w := f32(len(state.bar_buttons) * (BAR_BTN_SIZE + BAR_BTN_GAP) - BAR_BTN_GAP)
		bar_rect := rl.Rectangle{f32(BAR_X) - 4, f32(BAR_Y) - 4, bar_w + 8, BAR_BTN_SIZE + 8}
		if rl.CheckCollisionPointRec(mouse, bar_rect) do return true
	}

	if state.inventory_menu.open       && rl.CheckCollisionPointRec(mouse, state.inventory_menu.rect) do return true
	if state.settings_menu.open        && rl.CheckCollisionPointRec(mouse, state.settings_menu.rect) do return true
	if state.skills_menu.open          && rl.CheckCollisionPointRec(mouse, state.skills_menu.rect) do return true
	if state.friends_menu.open         && rl.CheckCollisionPointRec(mouse, state.friends_menu.rect) do return true
	if state.party_menu.open           && rl.CheckCollisionPointRec(mouse, state.party_menu.rect) do return true
	if state.quest_list_menu.open      && rl.CheckCollisionPointRec(mouse, state.quest_list_menu.rect) do return true
	if state.accept_deny_menu.open     && rl.CheckCollisionPointRec(mouse, state.accept_deny_menu.rect) do return true
	if state.blacksmith_menu.open      && rl.CheckCollisionPointRec(mouse, state.blacksmith_menu.rect) do return true
	if state.soul_extraction_menu.open && rl.CheckCollisionPointRec(mouse, state.soul_extraction_menu.rect) do return true
	if state.character_profile_menu.open && rl.CheckCollisionPointRec(mouse, state.character_profile_menu.rect) do return true
	if state.loot_drop_menu.open       && rl.CheckCollisionPointRec(mouse, state.loot_drop_menu.rect) do return true
	if state.loot_party_menu.open      && rl.CheckCollisionPointRec(mouse, state.loot_party_menu.rect) do return true
	if state.shop_menu.open            && rl.CheckCollisionPointRec(mouse, state.shop_menu.rect) do return true
	if state.system_menu.open          && rl.CheckCollisionPointRec(mouse, state.system_menu.rect) do return true
	if state.debug_menu.open           && rl.CheckCollisionPointRec(mouse, state.debug_menu.rect) do return true
	return false
}

// Toggle a menu via its rebindable action, suppressed while the chat input has
// focus so typing a letter doesn't pop a window. Every menu-open shortcut goes
// through this — the chat gate lives in one place, and the key comes from the
// settings keybind table (so e.g. inventory on I, J, or whatever the user set).
menu_keybind :: proc(m: ^ui.Menu, action: sys.Action) {
	if !state.chat_focused && sys.bind_pressed(action) do ui.menu_toggle(m)
}

// Centered rect for the "Respawn at Homepoint" button on the death overlay.
death_respawn_btn_rect :: proc() -> rl.Rectangle {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	return {sw / 2 - 130, sh / 2 + 30, 260, 40}
}

// ── skill bar layout + input ───────────────────────────────────────────────
SKILL_SLOT_SIZE :: 36
SKILL_SLOT_GAP  :: 4

skill_slot_rect :: proc "contextless" (bar, slot: int) -> rl.Rectangle {
	pos := state.player.skill_bar_pos[bar]
	return {
		pos.x + f32(slot * (SKILL_SLOT_SIZE + SKILL_SLOT_GAP)),
		pos.y,
		f32(SKILL_SLOT_SIZE),
		f32(SKILL_SLOT_SIZE),
	}
}

skill_bar_bg_rect :: proc "contextless" (bar: int) -> rl.Rectangle {
	pos := state.player.skill_bar_pos[bar]
	w := f32(sys.SLOTS_PER_BAR * (SKILL_SLOT_SIZE + SKILL_SLOT_GAP) - SKILL_SLOT_GAP)
	return {pos.x - 4, pos.y - 4, w + 8, f32(SKILL_SLOT_SIZE) + 8}
}

// Returns true if the cursor is over any visible skill bar (so click-to-move
// and camera zoom don't fire when clicking bars).
cursor_over_skill_bar :: proc() -> bool {
	mouse := rl.GetMousePosition()
	for bar in 0 ..< sys.SKILL_BAR_COUNT {
		if bar > 0 && !sys.skill_bar_has_skills(state.player, bar) do continue
		if rl.CheckCollisionPointRec(mouse, skill_bar_bg_rect(bar)) do return true
	}
	return false
}

// Handles keyboard (digits 1-0 → bar 0) + mouse click activation + dragging.
handle_skill_bar_input :: proc(inp: sys.Input_State) {
	mouse := rl.GetMousePosition()
	p := state.player

	// --- Dragging (move a bar by its background) ---
	if state.dragging_bar >= 0 {
		if rl.IsMouseButtonDown(.LEFT) {
			p.skill_bar_pos[state.dragging_bar] = mouse - state.drag_offset
		} else {
			state.dragging_bar = -1
			sys.save_skill_bar(p)
		}
		return
	}

	// --- Determine which skill to activate ---
	name := ""

	if inp.skill_slot >= 0 {
		state.ground_target.active = false
		name = sys.skill_bar_get(p, 0, inp.skill_slot)
	}

	if inp.mouse_left_pressed && cursor_over_skill_bar() {
		for bar in 0 ..< sys.SKILL_BAR_COUNT {
			if bar > 0 && !sys.skill_bar_has_skills(p, bar) do continue
			for slot in 0 ..< sys.SLOTS_PER_BAR {
				if p.skill_bar_lens[bar][slot] == 0 do continue
				if rl.CheckCollisionPointRec(mouse, skill_slot_rect(bar, slot)) {
					name = sys.skill_bar_get(p, bar, slot)
					state.ground_target.active = false
					break
				}
			}
			if len(name) > 0 do break
		}
		// Click on bar background (not a slot) → start dragging.
		if len(name) == 0 {
			for bar in 0 ..< sys.SKILL_BAR_COUNT {
				if bar > 0 && !sys.skill_bar_has_skills(p, bar) do continue
				if rl.CheckCollisionPointRec(mouse, skill_bar_bg_rect(bar)) {
					state.dragging_bar = bar
					state.drag_offset = mouse - p.skill_bar_pos[bar]
					return
				}
			}
		}
	}

	if len(name) == 0 do return

	// --- Activate ---
	sk := sys.get_skill(name)
	if sk == nil {
		sys.send_skill_use(state.net, name, target_string_id())
		return
	}
	if sk.targeting.aoe_mode == .GROUND_TARGETED {
		gt := &state.ground_target
		gt.active = true
		sys.copy_string_to_buffer(gt.skill_name[:], &gt.name_len, name)
		gt.radius = sk.targeting.aoe_radius > 0 ? sk.targeting.aoe_radius : sys.DEFAULT_AOE_RADIUS
	} else if sk.targeting.aoe_mode == .TARGET_CENTERED && sk.targeting.aoe_radius > 0 {
		idx := sys.find_index(state.scene, p.target_id)
		if idx >= 0 {
			pos := state.scene.transforms[idx].position
			sys.send_skill_use_ground(state.net, name, pos.x, pos.y, pos.z)
		}
	} else {
		sys.send_skill_use(state.net, name, target_string_id())
	}
}

// ── camera ────────────────────────────────────────────────────────────────

// Component-wise lerp for Vector3 (avoids the deprecated Vector3Lerp wrapper).
v3lerp :: proc "contextless" (a, b: rl.Vector3, t: f32) -> rl.Vector3 {
	return {a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t}
}
