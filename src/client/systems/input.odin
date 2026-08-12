package systems

import "core:math"
import "core:math/linalg"
import rl "vendor:raylib"

// Mirrors packages/client/src/core/input/InputManager.ts:
//   WASD move, Shift sprint, F auto-attack, Space manual attack, E interact,
//   digits 0-0 = skill bar slots, Tab cycle target, Enter toggle chat, Esc.
// When chat is focused or a dialog is active, gameplay keys are suppressed.

Input_State :: struct {
	// Movement (camera-relative, normalized).
	move_x:              f32,
	move_z:              f32,
	moving:              bool,
	sprint:              bool,

	// Combat / interaction edge triggers (true for the frame the key went down).
	attack:              bool, // F  — auto-attack request
	manual_attack:       bool, // Space — cone attack
	interact:            bool, // E
	cycle_target:        int, // -1 (prev), +1 (next), 0 none  (Tab / Shift+Tab)
	toggle_rest:         bool, // R

	// Skill bar: which slot index was pressed this frame, or -1.
	skill_slot:          int,

	// Chat.
	chat_focused:        bool,
	chat_toggle:         bool, // Enter pressed
	chat_submit:         bool, // Enter while focused → send
	chat_cancel:         bool, // Esc while focused → unfocus
	chat_backspace:      bool,

	// Mouse.
	mouse_left_pressed:  bool,
	mouse_right_pressed: bool,
	mouse_delta:         rl.Vector2,
}

poll_input :: proc(chat_focused, menu_open: bool, p: ^Local_Player, dt: f32) -> Input_State {
	state: Input_State
	state.skill_slot = -1

	// Chat input takes over the keyboard.
	if chat_focused {
		state.chat_focused = true
		state.chat_submit = rl.IsKeyPressed(.ENTER)
		state.chat_cancel = rl.IsKeyPressed(.ESCAPE)
		state.chat_backspace = rl.IsKeyPressed(.BACKSPACE) || rl.IsKeyPressedRepeat(.BACKSPACE)
		state.mouse_left_pressed = rl.IsMouseButtonPressed(.LEFT)
		state.mouse_right_pressed = rl.IsMouseButtonPressed(.RIGHT)
		state.mouse_delta = rl.GetMouseDelta()
		return state
	}

	// Enter opens the chat.
	state.chat_toggle = rl.IsKeyPressed(.ENTER)
	if state.chat_toggle {
		state.chat_focused = true
		return state
	}

	// A menu window is open → suppress gameplay keys (movement, skills, Tab,
	// combat, click-to-move). Mouse is still returned so menu dragging works;
	// the menus read clicks directly via menu_update.
	if menu_open {
		state.mouse_left_pressed = rl.IsMouseButtonPressed(.LEFT)
		state.mouse_right_pressed = rl.IsMouseButtonPressed(.RIGHT)
		state.mouse_delta = rl.GetMouseDelta()
		return state
	}

	// --- movement ---
	if rl.IsKeyDown(.W) do state.move_z -= 1.0
	if rl.IsKeyDown(.S) do state.move_z += 1.0
	if rl.IsKeyDown(.A) do state.move_x -= 1.0
	if rl.IsKeyDown(.D) do state.move_x += 1.0

	len := math.sqrt(state.move_x * state.move_x + state.move_z * state.move_z)
	if len > 0.0 {
		state.move_x /= len
		state.move_z /= len
		state.moving = true
	}

	move_dir := rl.Vector3{state.move_x, 0, state.move_z}
	if linalg.length(move_dir) > 0 {
		move_dir = linalg.normalize(move_dir)

		// Rotate movement vector by player's current yaw facing
		sin_y := math.sin(p.yaw)
		cos_y := math.cos(p.yaw)

		rotated_move := rl.Vector3 {
			move_dir.x * cos_y + move_dir.z * sin_y,
			0,
			move_dir.z * cos_y - move_dir.x * sin_y,
		}

		p.position += rotated_move * GAME.PLAYER_SPEED * dt
	}

	state.sprint = rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)

	// --- combat / interaction ---
	state.attack = rl.IsKeyDown(.F)
	state.manual_attack = rl.IsKeyPressed(.SPACE)
	state.interact = rl.IsKeyPressed(.E)
	state.toggle_rest = rl.IsKeyPressed(.R)

	// --- target cycling (Tab = next, Shift+Tab = previous) ---
	if rl.IsKeyPressed(.TAB) {
		if state.sprint {state.cycle_target = -1} else {state.cycle_target = 1}
	}

	// --- skill bar (1-9, 0) ---
	state.skill_slot = skill_slot_pressed()

	// --- mouse ---
	state.mouse_left_pressed = rl.IsMouseButtonPressed(.LEFT)
	state.mouse_right_pressed = rl.IsMouseButtonPressed(.RIGHT)
	state.mouse_delta = rl.GetMouseDelta()

	return state
}

MmoCamera :: struct {
	distance:     f32,
	pitch:        f32, // Up/Down rotation in radians
	yaw:          f32, // Left/Right rotation in radians
	sensitivity:  f32,
	min_pitch:    f32,
	max_pitch:    f32,
	min_distance: f32, // scroll-wheel zoom clamp (near)
	max_distance: f32, // scroll-wheel zoom clamp (far)
	zoom_step:    f32, // world units moved per scroll notch
}

cam_control := MmoCamera {
	distance     = 10.0,
	pitch        = 0.4,
	yaw          = 0.0,
	sensitivity  = 0.003,
	min_pitch    = -0.1,
	max_pitch    = 1.4,
	min_distance = 3.0,
	max_distance = 20.0,
	zoom_step    = 1.0,
}

// Set the camera's static fields once (up axis, field of view, projection).
// position/target are recomputed every frame by update_camera, so this only
// needs to run when the gameplay scene starts.
init_camera :: proc(p: ^Local_Player) {
	p.camera.up = {0, 1, 0}
	p.camera.fovy = 60.0
	p.camera.projection = .PERSPECTIVE
}

update_camera :: proc(dt: f32, p: ^Local_Player, block_zoom: bool) {
	// Aim at the player's chest; the camera orbits at cam_control.distance,
	// positioned from the current yaw/pitch. NOTE: this drives p.camera — the
	// same Camera3D the render loop passes to BeginMode3D — not a local copy.
	p.camera.target = p.position + rl.Vector3{0, 1.5, 0}

	offset := rl.Vector3 {
		math.sin(cam_control.yaw) * math.cos(cam_control.pitch),
		math.sin(cam_control.pitch),
		math.cos(cam_control.yaw) * math.cos(cam_control.pitch),
	}
	p.camera.position = p.camera.target + (offset * cam_control.distance)

	// Right-drag orbits the camera (yaw/pitch). While held, the player faces
	// the camera's yaw immediately (WoW-style "mouselook" turning).
	if rl.IsMouseButtonPressed(.RIGHT) {
		rl.DisableCursor() // hide cursor and lock to window center
	}

	if rl.IsMouseButtonDown(.RIGHT) {
		mouse_delta := rl.GetMouseDelta()

		// Orbiting updates camera yaw and pitch
		cam_control.yaw -= mouse_delta.x * cam_control.sensitivity
		cam_control.pitch += mouse_delta.y * cam_control.sensitivity
		cam_control.pitch = clamp(cam_control.pitch, cam_control.min_pitch, cam_control.max_pitch)

		// In WoW, holding RMB forces player to face camera direction immediately
		p.yaw = cam_control.yaw
	}

	if rl.IsMouseButtonReleased(.RIGHT) {
		rl.EnableCursor() // free the cursor
	}

	// Scroll-wheel zoom: GetMouseWheelMove() is positive scrolling up (toward
	// the user), which zooms in (shrinks the orbit radius). Skipped when the
	// cursor is over a menu so the wheel scrolls the menu instead.
	wheel := block_zoom ? 0.0 : rl.GetMouseWheelMove()
	if wheel != 0 {
		cam_control.distance = clamp(
			cam_control.distance - wheel * cam_control.zoom_step,
			cam_control.min_distance,
			cam_control.max_distance,
		)
	}
}

skill_slot_pressed :: proc() -> int {
	// Digits 1..9 → slots 0..8, digit 0 → slot 9 (matches the TS skill bar).
	if rl.IsKeyPressed(.ONE) do return 0
	if rl.IsKeyPressed(.TWO) do return 1
	if rl.IsKeyPressed(.THREE) do return 2
	if rl.IsKeyPressed(.FOUR) do return 3
	if rl.IsKeyPressed(.FIVE) do return 4
	if rl.IsKeyPressed(.SIX) do return 5
	if rl.IsKeyPressed(.SEVEN) do return 6
	if rl.IsKeyPressed(.EIGHT) do return 7
	if rl.IsKeyPressed(.NINE) do return 8
	if rl.IsKeyPressed(.ZERO) do return 9
	return -1
}
