package login

import sys "../../systems"
import rl "vendor:raylib"

// Login scene: connects the socket, sends LOGIN, and on AUTH_SUCCESS hands
// off to the character-select scene. Also supports REGISTER (Tab toggles
// between the two forms). Mirrors the TS client's auth screen.

Mode :: enum {
	LOGIN,
	REGISTER,
}

state: struct {
	mode:           Mode,
	net:            ^sys.Network_Client,
	username:       [64]u8,
	username_len:   int,
	password:       [64]u8,
	password_len:   int,
	email:          [128]u8,
	email_len:      int,
	focus:          enum int {
		USER,
		PASS,
		EMAIL,
	},
	error_msg:      [256]u8,
	error_len:      int,
	busy:           bool,
	connected_once: bool,
}

init :: proc(net: ^sys.Network_Client) {
	state.net = net
	state.mode = .LOGIN
	state.focus = .USER
	state.username_len = 0
	state.password_len = 0
	state.email_len = 0
	state.error_len = 0
	state.busy = false
	state.connected_once = false

	if !sys.is_connected(net) {
		sys.connect(net)
	}
}

// Returns true once AUTH_SUCCESS arrives (caller advances to character select).
update :: proc(dt: f32) -> bool {
	sys.update_network(state.net)

	packets := sys.poll_inbound(state.net)
	for i in 0 ..< len(packets) {
		p := &packets[i]
		#partial switch p.type {
		case .AUTH_SUCCESS:
			sys.free_packet(p)
			return true
		case .AUTH_FAILURE:
			data := p.data != nil ? p.data^ : sys.json_null_value()
			o := sys.obj_of(data)
			set_error(sys.get_string(o, "message", "Authentication failed"))
			state.busy = false
		case:
		}
		sys.free_packet(p)
	}

	// Input into focused field.
	if rl.IsKeyPressed(.TAB) {
		switch state.focus {
		case .USER:
			state.focus = .PASS
		case .PASS:
			state.focus = state.mode == .REGISTER ? .EMAIL : .USER
		case .EMAIL:
			state.focus = .USER
		}
	}
	if rl.IsKeyPressed(.ENTER) do submit()
	if rl.IsKeyPressed(.BACKSPACE) do backspace()
	read_chars()

	// Toggle login/register with the R key (when not focused-typing).
	if rl.IsKeyPressed(.R) && (rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)) {
		state.mode = state.mode == .LOGIN ? .REGISTER : .LOGIN
		state.error_len = 0
	}
	return false
}

read_chars :: proc() {
	c := rl.GetCharPressed()
	for c != 0 {
		if c >= 32 && c < 127 {
			switch state.focus {
			case .USER:
				append_char(state.username[:], &state.username_len, u8(c))
			case .PASS:
				append_char(state.password[:], &state.password_len, u8(c))
			case .EMAIL:
				append_char(state.email[:], &state.email_len, u8(c))
			}
		}
		c = rl.GetCharPressed()
	}
}

append_char :: proc(buf: []u8, length: ^int, c: u8) {
	if length^ < len(buf) {
		buf[length^] = c
		length^ += 1
	}
}

backspace :: proc() {
	switch state.focus {
	case .USER:
		if state.username_len > 0 do state.username_len -= 1
	case .PASS:
		if state.password_len > 0 do state.password_len -= 1
	case .EMAIL:
		if state.email_len > 0 do state.email_len -= 1
	}
}

submit :: proc() {
	if state.busy do return
	if !sys.is_connected(state.net) {
		set_error("Not connected to server")
		return
	}
	if state.username_len == 0 || state.password_len == 0 {
		set_error("Enter username and password")
		return
	}
	state.busy = true
	state.error_len = 0
	user := string(state.username[:state.username_len])
	pass := string(state.password[:state.password_len])
	sys.set_auth_credentials(state.net, user, pass)
	if state.mode == .REGISTER {
		email := string(state.email[:state.email_len])
		sys.send_register(state.net, user, email, pass)
	} else {
		sys.send_login(state.net, user, pass)
	}
}

set_error :: proc(msg: string) {
	n := min(len(msg), len(state.error_msg))
	state.error_len = n
	copy(state.error_msg[:n], transmute([]u8)msg)
}

render :: proc() {
	rl.ClearBackground({18, 20, 30, 255})

	title := "DUST SAGA"
	tw := sys.measure_text(title, 48)
	sys.draw_text(title, 640 - tw / 2, 120, 48, rl.GOLD)
	sub := state.mode == .LOGIN ? "Sign In" : "Register"
	sw := sys.measure_text(sub, 24)
	sys.draw_text(sub, 640 - sw / 2, 185, 24, rl.LIGHTGRAY)

	cx := 490
	draw_field("Username", state.username[:state.username_len], cx, 260, state.focus == .USER)
	draw_field("Password", state.password[:state.password_len], cx, 330, state.focus == .PASS)
	if state.mode == .REGISTER {
		draw_field("Email", state.email[:state.email_len], cx, 400, state.focus == .EMAIL)
	}

	if state.error_len > 0 {
		sys.draw_text(string(state.error_msg[:state.error_len]), cx, 470, 18, rl.RED)
	}

	sys.draw_text("Tab: switch field   Enter: submit   Ctrl+R: toggle mode", cx, 620, 14, rl.GRAY)

	if state.busy {
		sys.draw_text("Connecting…", cx, 500, 16, rl.YELLOW)
	}
}

draw_field :: proc(label: string, value: []u8, x, y: int, focused: bool) {
	sys.draw_text(label, x, y - 22, 14, rl.LIGHTGRAY)
	rect := rl.Rectangle{f32(x), f32(y), 300, 34}
	bg := rl.Color{40, 40, 50, 255}
	if focused do bg = {60, 60, 80, 255}
	rl.DrawRectangleRec(rect, bg)
	rl.DrawRectangleLinesEx(rect, 2, focused ? rl.GOLD : rl.BLACK)

	sys.draw_text(string(value), x + 8, y + 8, 18, rl.WHITE)
}
