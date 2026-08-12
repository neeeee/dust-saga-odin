package character_select

import "core:fmt"
import rl "vendor:raylib"
import sys "../../systems"

// Character-select scene: requests the CHARACTER_LIST, shows the player's
// characters, lets them pick one to enter the world (CHARACTER_SELECT), or
// create a new one. On CHARACTER_SELECT response we hand off to gameplay.

Character_Entry :: struct {
	id:        [64]u8, id_len: int,
	name:      [64]u8, name_len: int,
	class:     [32]u8, class_len: int,
	race:      [32]u8, race_len: int,
	level:     int,
	zone_id:   [64]u8, zone_len: int,
}

CREATE_CLASSES :: [4]string{"warrior", "mage", "archer", "cleric"}
CREATE_RACES   :: [6]string{"human", "elf", "dwarf", "myrine", "enkidu", "lapin"}

state: struct {
	net:         ^sys.Network_Client,
	entries:     [dynamic]Character_Entry,
	requested:   bool,
	selected:    int,           // highlighted row
	chosen:      bool,          // set when user picks a character to enter

	// create-new sub-form
	creating:    bool,
	new_name:    [64]u8, new_name_len: int,
	new_class:   int,
	new_race:    int,
	error_msg:   [256]u8, error_len: int,
}

init :: proc(net: ^sys.Network_Client) {
	state.net = net
	clear(&state.entries)
	state.requested = false
	state.selected = 0
	state.creating = false
	state.new_name_len = 0
	state.new_class = 0
	state.new_race = 0
	state.error_len = 0
}

shutdown :: proc() {
	clear(&state.entries)
}

// Returns (chosen_character_id, true) when the user picks a character to enter
// the world. main then transitions to GAMEPLAY, which sends CHARACTER_SELECT
// (already done in enter_world) and processes the response.
update :: proc(dt: f32) -> (chosen_id: string, has_choice: bool) {
	sys.update_network(state.net)

	if !state.requested && sys.is_connected(state.net) {
		sys.send_character_list(state.net)
		state.requested = true
	}

	packets := sys.poll_inbound(state.net)
	for i in 0..<len(packets) {
		p := &packets[i]
		if p.type == .CHARACTER_LIST && p.data != nil {
			parse_list(p.data^)
		} else if p.type == .NOTIFICATION && p.data != nil {
			o := sys.obj_of(p.data^)
			set_error(sys.get_string(o, "message"))
		}
		sys.free_packet(p)
	}

	if state.creating {
		handle_create_input()
	} else {
		handle_select_input()
	}

	if state.chosen {
		state.chosen = false
		return selected_character_id(), true
	}
	return "", false
}

parse_list :: proc(data: sys.JSON_Value) {
	clear(&state.entries)
	root := sys.obj_of(data)
	if sys.is_null(data) do return
	arr := sys.get_array(root, "characters")
	dyn := sys.as_dyn(arr)
	for i in 0..<len(dyn) {
		c := sys.obj_of(dyn[i])
		e: Character_Entry
		sys.copy_string_to_buffer(e.id[:], &e.id_len, sys.get_string(c, "id"))
		sys.copy_string_to_buffer(e.name[:], &e.name_len, sys.get_string(c, "name"))
		sys.copy_string_to_buffer(e.class[:], &e.class_len, sys.get_string(c, "class"))
		sys.copy_string_to_buffer(e.race[:], &e.race_len, sys.get_string(c, "race"))
		e.level = sys.get_int(c, "level")
		sys.copy_string_to_buffer(e.zone_id[:], &e.zone_len, sys.get_string(c, "zoneId"))
		append(&state.entries, e)
	}
}


handle_select_input :: proc() {
	n := len(state.entries)
	if n == 0 do return
	if rl.IsKeyPressed(.DOWN) {
		state.selected = (state.selected + 1) % n
	}
	if rl.IsKeyPressed(.UP) {
		state.selected -= 1
		if state.selected < 0 do state.selected = n - 1
	}
	if rl.IsKeyPressed(.ENTER) {
		enter_world()
	}
	if rl.IsKeyPressed(.C) do state.creating = true
}

handle_create_input :: proc() {
	c := rl.GetCharPressed()
	for c != 0 {
		if c >= 32 && c < 127 && state.new_name_len < len(state.new_name) {
			state.new_name[state.new_name_len] = u8(c)
			state.new_name_len += 1
		}
		c = rl.GetCharPressed()
	}
	if rl.IsKeyPressed(.BACKSPACE) && state.new_name_len > 0 {
		state.new_name_len -= 1
	}
	if rl.IsKeyPressed(.LEFT) {
		if rl.IsKeyDown(.LEFT_SHIFT) {
			state.new_race = (state.new_race + len(CREATE_RACES) - 1) % len(CREATE_RACES)
		} else {
			state.new_class = (state.new_class + len(CREATE_CLASSES) - 1) % len(CREATE_CLASSES)
		}
	}
	if rl.IsKeyPressed(.RIGHT) {
		if rl.IsKeyDown(.LEFT_SHIFT) {
			state.new_race = (state.new_race + 1) % len(CREATE_RACES)
		} else {
			state.new_class = (state.new_class + 1) % len(CREATE_CLASSES)
		}
	}
	if rl.IsKeyPressed(.ENTER) do submit_create()
	if rl.IsKeyPressed(.ESCAPE) do state.creating = false
}

submit_create :: proc() {
	if state.new_name_len == 0 {
		set_error("Enter a name")
		return
	}
	name := string(state.new_name[:state.new_name_len])
	classes := CREATE_CLASSES
	races := CREATE_RACES
	sys.send_character_create(state.net, name, classes[state.new_class], races[state.new_race])
	state.error_len = 0
	// The server replies with NOTIFICATION on success/failure; on success it
	// also re-sends CHARACTER_LIST, so we drop back to the list view.
	state.creating = false
	state.requested = false
}

// Public entry point: called when the user picks a character. Sends SELECT and
// flags that main should transition to gameplay (gameplay then processes the
// CHARACTER_SELECT + WORLD_STATE response).
enter_world :: proc() {
	if state.selected < 0 || state.selected >= len(state.entries) do return
	e := state.entries[state.selected]
	id := string(e.id[:e.id_len])
	sys.set_character_id(state.net, id)
	sys.send_character_select(state.net, id)
	state.chosen = true
}

set_error :: proc(msg: string) {
	n := min(len(msg), len(state.error_msg))
	state.error_len = n
	copy(state.error_msg[:n], transmute([]u8)msg)
}

// Returns the currently-highlighted character id (for main to know what to
// pass to gameplay once the WORLD_STATE arrives).
selected_character_id :: proc() -> string {
	if state.selected < 0 || state.selected >= len(state.entries) do return ""
	e := state.entries[state.selected]
	return string(e.id[:e.id_len])
}

render :: proc() {
	rl.ClearBackground({16, 18, 28, 255})

	tw := sys.measure_text("Select Character", 36)
	sys.draw_text("Select Character", 640 - tw / 2, 80, 36, rl.GOLD)

	if state.creating {
		render_create()
		return
	}

	if len(state.entries) == 0 {
		hint := "No characters yet — press C to create one"
		hw := sys.measure_text(hint, 20)
		sys.draw_text(hint, 640 - hw / 2, 280, 20, rl.LIGHTGRAY)
		return
	}

	// Character list.
	y := 160
	for i in 0..<len(state.entries) {
		e := &state.entries[i]
		col := i == state.selected ? rl.GOLD : rl.LIGHTGRAY
		row := fmt.tprintf("%s  —  Lv %d  %s/%s  (%s)",
			string(e.name[:e.name_len]),
			e.level,
			string(e.race[:e.race_len]),
			string(e.class[:e.class_len]),
			string(e.zone_id[:e.zone_len]),
		)
		sys.draw_text(row, 360, y, 22, col)
		y += 36
	}

	sys.draw_text("↑/↓: choose   ENTER: enter world   C: create new",
		360, 640, 16, rl.GRAY)

	if state.error_len > 0 {
		sys.draw_text(string(state.error_msg[:state.error_len]), 360, 600, 16, rl.RED)
	}
}

render_create :: proc() {
	sys.draw_text("Create Character", 470, 140, 28, rl.GOLD)

	sys.draw_text("Name:", 360, 200, 18, rl.LIGHTGRAY)
	sys.draw_text(string(state.new_name[:state.new_name_len]), 500, 200, 18, rl.WHITE)

	sys.draw_text("Class:", 360, 250, 18, rl.LIGHTGRAY)
	classes := CREATE_CLASSES
	cls := fmt.tprintf("< %s >", classes[state.new_class])
	sys.draw_text(cls, 500, 250, 18, rl.WHITE)

	sys.draw_text("Race:", 360, 300, 18, rl.LIGHTGRAY)
	races := CREATE_RACES
	race := fmt.tprintf("< %s >", races[state.new_race])
	sys.draw_text(race, 500, 300, 18, rl.WHITE)

	sys.draw_text("Type name. ←/→: class  Shift+←/→: race  ENTER: create  ESC: cancel",
		300, 420, 14, rl.GRAY)

	if state.error_len > 0 {
		sys.draw_text(string(state.error_msg[:state.error_len]), 360, 380, 16, rl.RED)
	}
}
