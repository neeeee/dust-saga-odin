package character_select

import "core:fmt"
import "core:math"
import "core:os"
import rl "vendor:raylib"
import "../../ui"
import sys "../../systems"

// Character-select scene: requests the CHARACTER_LIST, shows the player's
// characters, lets them pick one to enter the world (CHARACTER_SELECT), or
// create a new one in a mouse-driven creator screen (name box, race/class
// button grids, Create/Back buttons). On CHARACTER_SELECT response we hand
// off to gameplay. Model preview is a placeholder for now — model loading at
// creation time comes later.

Character_Entry :: struct {
	id:         [64]u8, id_len: int,
	name:       [64]u8, name_len: int,
	class:      [32]u8, class_len: int,
	race:       [32]u8, race_len: int,
	level:      int,
	zone_id:    [64]u8, zone_len: int,
	model_id:   [16]u8, model_len: int,
	face_index: int,
	hair_index: int,
	hair_color: int,
}

CREATE_CLASSES :: [4]string{"warrior", "mage", "scout", "acolyte"}
CREATE_RACES   :: [6]string{"human", "elf", "dwarf", "myrine", "enkidu", "lapin"}

// UI labels (the ids above are what the server protocol speaks).
CLASS_LABELS  :: [4]string{"Warrior", "Mage", "Scout", "Acolyte"}
RACE_LABELS   :: [6]string{"Human", "Elf", "Dwarf", "Myrine", "Enkidu", "Lapin"}
CLASS_COLORS  :: [4]rl.Color{
	{200, 85, 85, 255},   // warrior
	{95, 140, 230, 255},  // mage
	{95, 185, 120, 255},  // scout
	{230, 200, 110, 255}, // acolyte
}

NAME_MIN :: 3
NAME_MAX :: 20

// ── palette ────────────────────────────────────────────────────────────────

COL_BG       :: rl.Color{16, 18, 28, 255}
COL_PANEL    :: rl.Color{24, 27, 38, 255}
COL_PANEL_HV :: rl.Color{36, 41, 58, 255}
COL_BORDER   :: rl.Color{90, 96, 120, 255}
COL_BTN      :: rl.Color{55, 60, 75, 255}
COL_BTN_HOV  :: rl.Color{80, 90, 120, 255}
COL_BTN_DIS  :: rl.Color{40, 43, 54, 255}
COL_SEL      :: rl.Color{70, 110, 180, 255}
COL_SEL_HV   :: rl.Color{95, 135, 205, 255}
COL_CREATE   :: rl.Color{70, 130, 80, 255}
COL_CREATE_HV:: rl.Color{95, 165, 105, 255}
COL_INPUT_BG :: rl.Color{12, 14, 20, 255}

// ── fixed layout (1280x720 window) ─────────────────────────────────────────

LIST_ROW_X    :: 340.0
LIST_ROW_W    :: 600.0
LIST_ROW_H    :: 48.0
LIST_ROW_STEP :: 56.0
MAX_LIST_ROWS :: 8 // rows that fit above the bottom buttons

PREVIEW_PANEL :: rl.Rectangle{100, 120, 420, 540}
NAME_BOX      :: rl.Rectangle{580, 138, 430, 40}

DEBUG_LOG_PATH :: "chara_debug.txt"



// Creator model-preview state machine: NONE → (open) → LOADING → READY/FAILED.
// LOADING defers the actual glb load to the next update so the "Loading
// model…" frame gets drawn before the blocking load happens.
Model_State :: enum {
	NONE,
	LOADING,
	READY,
	FAILED,
}

state: struct {
	net:         ^sys.Network_Client,
	entries:     [dynamic]Character_Entry,
	requested:   bool,
	selected:    int,           // highlighted row
	chosen:      bool,          // set when user picks a character to enter
	error_msg:   [256]u8, error_len: int,

	// list-view double-click detection
	last_click_i: int,
	last_click_t: f64,

	// create-new screen
	creating:     bool,
	submitted:    bool,       // create request in flight, awaiting server reply
	name_focused: bool,
	new_name:     [64]u8, new_name_len: int,
	new_class:    int,
	new_race:     int,

	// widgets
	create_btn: ui.UI_Button,                 // list view
	enter_btn:  ui.UI_Button,                 // list view
	random_btn: ui.UI_Button,                 // creator
	race_btns:  [len(CREATE_RACES)]ui.UI_Button,
	class_btns: [len(CREATE_CLASSES)]ui.UI_Button,
	submit_btn: ui.UI_Button,                 // creator
	back_btn:   ui.UI_Button,                 // creator

	// 3d model preview + variant picks
	model_state: Model_State,
	anim_time:   f64,            // idle animation clock
	bounds_measured: bool,       // skinned-pose bounds captured this model?
	subset_bounds: rl.BoundingBox,
	female:      bool,             // sex pick (human/elf only)
	face_i:      int,              // index into cm.faces
	hair_i:      int,              // index into cm.hairs
	color_i:     int,              // index into cm.hair_colors
	cm:          ^sys.Chara_Model,
	subset:      sys.Chara_Subset,
	subset_valid: bool,
	cam:         rl.Camera3D,
	yaw:         f32,              // turntable angle, degrees
	dragging:    bool,
	grid_spacing: f32,
	model_offset: rl.Vector3,      // x/z centering + feet-to-ground lift

	sex_btns:   [2]ui.UI_Button,     // Male / Female (human, elf)
	face_prev:  ui.UI_Button,
	face_next:  ui.UI_Button,
	hair_prev:  ui.UI_Button,
	hair_next:  ui.UI_Button,
	color_prev: ui.UI_Button,
	color_next: ui.UI_Button,
}

init :: proc(net: ^sys.Network_Client) {
	state.net = net
	clear(&state.entries)
	state.requested = false
	state.selected = 0
	state.error_len = 0
	state.last_click_i = -1
	state.last_click_t = 0
	state.creating = false
	state.submitted = false
	state.name_focused = false
	state.new_name_len = 0
	state.new_class = 0
	state.new_race = 0
	state.model_state = .NONE
	state.anim_time = 0
	state.bounds_measured = false
	state.cm = nil
	state.subset_valid = false
	state.female = false
	state.face_i = 0
	state.hair_i = 0
	state.color_i = 0
	state.yaw = 0
	state.dragging = false
	state.grid_spacing = 1
	state.model_offset = {0, 0, 0}

	state.create_btn = ui.UI_Button{
		rect        = {410, 618, 220, 50},
		text        = "Create Character",
		base_color  = COL_SEL,
		hover_color = COL_SEL_HV,
		text_color  = rl.WHITE,
		font_size   = 20,
	}
	state.enter_btn = ui.UI_Button{
		rect        = {650, 618, 220, 50},
		text        = "Enter World",
		base_color  = COL_SEL,
		hover_color = COL_SEL_HV,
		text_color  = rl.WHITE,
		font_size   = 20,
	}
	state.random_btn = ui.UI_Button{
		rect        = {1022, 138, 138, 40},
		text        = "Random",
		base_color  = COL_BTN,
		hover_color = COL_BTN_HOV,
		text_color  = rl.WHITE,
		font_size   = 16,
	}
	state.submit_btn = ui.UI_Button{
		rect        = {580, 590, 284, 54},
		text        = "Create",
		base_color  = COL_CREATE,
		hover_color = COL_CREATE_HV,
		text_color  = rl.WHITE,
		font_size   = 22,
	}
	state.back_btn = ui.UI_Button{
		rect        = {876, 590, 284, 54},
		text        = "Back",
		base_color  = COL_BTN,
		hover_color = COL_BTN_HOV,
		text_color  = rl.WHITE,
		font_size   = 22,
	}

	// Sex picker (shown for human/elf only).
	state.sex_btns[0] = ui.UI_Button{rect = {580, 208, 284, 34}, text = "Male",   base_color = COL_BTN, hover_color = COL_BTN_HOV, text_color = rl.WHITE, font_size = 16}
	state.sex_btns[1] = ui.UI_Button{rect = {876, 208, 284, 34}, text = "Female", base_color = COL_BTN, hover_color = COL_BTN_HOV, text_color = rl.WHITE, font_size = 16}
	// ‹ › steppers for face, hair, and hair-color variants.
	state.face_prev  = ui.UI_Button{rect = {624, 502, 32, 32}, text = "<", base_color = COL_BTN, hover_color = COL_BTN_HOV, text_color = rl.WHITE, font_size = 18}
	state.face_next  = ui.UI_Button{rect = {700, 502, 32, 32}, text = ">", base_color = COL_BTN, hover_color = COL_BTN_HOV, text_color = rl.WHITE, font_size = 18}
	state.hair_prev  = ui.UI_Button{rect = {794, 502, 32, 32}, text = "<", base_color = COL_BTN, hover_color = COL_BTN_HOV, text_color = rl.WHITE, font_size = 18}
	state.hair_next  = ui.UI_Button{rect = {870, 502, 32, 32}, text = ">", base_color = COL_BTN, hover_color = COL_BTN_HOV, text_color = rl.WHITE, font_size = 18}
	state.color_prev = ui.UI_Button{rect = {964, 502, 32, 32}, text = "<", base_color = COL_BTN, hover_color = COL_BTN_HOV, text_color = rl.WHITE, font_size = 18}
	state.color_next = ui.UI_Button{rect = {1040, 502, 32, 32}, text = ">", base_color = COL_BTN, hover_color = COL_BTN_HOV, text_color = rl.WHITE, font_size = 18}

	race_labels := RACE_LABELS
	for i in 0..<len(CREATE_RACES) {
		col := i % 3
		row := i / 3
		state.race_btns[i] = ui.UI_Button{
			rect        = {580 + f32(col * 197), 312 + f32(row * 38), 186, 32},
			text        = race_labels[i],
			base_color  = COL_BTN,
			hover_color = COL_BTN_HOV,
			text_color  = rl.WHITE,
			font_size   = 16,
		}
	}
	class_labels := CLASS_LABELS
	for i in 0..<len(CREATE_CLASSES) {
		col := i % 2
		row := i / 2
		state.class_btns[i] = ui.UI_Button{
			rect        = {580 + f32(col * 296), 410 + f32(row * 38), 284, 32},
			text        = class_labels[i],
			base_color  = COL_BTN,
			hover_color = COL_BTN_HOV,
			text_color  = rl.WHITE,
			font_size   = 16,
		}
	}
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
		if p.data != nil {
			#partial switch p.type {
			case .CHARACTER_LIST:
				parse_list(p.data^)
			case .CHARACTER_CREATE:
				// Server accepted the new character.
				if state.creating {
					close_creator()
					state.requested = false // refresh the list
				}
			case .ERROR, .NOTIFICATION:
				o := sys.obj_of(p.data^)
				set_error(sys.get_string(o, "message"))
				if state.creating do state.submitted = false
			}
		}
		sys.free_packet(p)
	}

	// Deferred model load: the "Loading model…" frame draws before the
	// blocking glb load happens here.
	if state.creating && state.model_state == .LOADING {
		load_pending_model()
	}

	// Idle animation: drive the base model's pose (the preview subset shares
	// its bones/bone matrices, so the subset animates too).
	if state.creating && state.model_state == .READY && state.cm != nil {
		if state.cm.idle_anim >= 0 {
			anim := state.cm.anims[state.cm.idle_anim]
			frames := f32(anim.keyframeCount)
			if frames > 0 && anim.keyframePoses != nil {
				state.anim_time += f64(dt)
				f := f32(state.anim_time) * sys.CHARA_ANIM_FPS
				frame := f - f32(i32(f / frames)) * frames
				rl.UpdateModelAnimation(state.cm.entry.model, anim, frame)
			}
		}

		// Once the pose exists, measure the skinned model and frame the
		// camera on what is actually drawn (bind-pose bounds are junk on
		// these rigs).
		if !state.bounds_measured {
			state.bounds_measured = true
			state.subset_bounds = sys.chara_skin_bounds(state.cm, &state.subset.model)
			append_debug(fmt.tprintf("skin(%s): bounds=(%.2f,%.2f,%.2f)-(%.2f,%.2f,%.2f)",
				state.cm.id,
				state.subset_bounds.min.x, state.subset_bounds.min.y, state.subset_bounds.min.z,
				state.subset_bounds.max.x, state.subset_bounds.max.y, state.subset_bounds.max.z))
			fit_camera()
		}
	}

	if state.creating {
		handle_create_input(dt)
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
		sys.copy_string_to_buffer(e.model_id[:], &e.model_len, sys.get_string(c, "modelId"))
		e.face_index = sys.get_int(c, "faceIndex")
		e.hair_index = sys.get_int(c, "hairIndex")
		e.hair_color = sys.get_int(c, "hairColor")
		append(&state.entries, e)
		append_debug(fmt.tprintf("list: %s model=%s face=%d hair=%d color=%d",
			string(e.name[:e.name_len]), string(e.model_id[:e.model_len]),
			e.face_index, e.hair_index, e.hair_color))
	}
}

// ── list-view input ────────────────────────────────────────────────────────

row_rect :: proc(i: int) -> rl.Rectangle {
	return {LIST_ROW_X, 140 + f32(i) * LIST_ROW_STEP, LIST_ROW_W, LIST_ROW_H}
}

handle_select_input :: proc() {
	n := len(state.entries)

	// "Enter World" greys out (and stops working) with nothing to enter.
	state.enter_btn.base_color = n > 0 ? COL_SEL : COL_BTN_DIS
	state.enter_btn.hover_color = n > 0 ? COL_SEL_HV : COL_BTN_DIS

	// Click a row to select it; click the selected row again (double-click)
	// to enter the world.
	mouse := rl.GetMousePosition()
	for i in 0..<min(n, MAX_LIST_ROWS) {
		if !rl.CheckCollisionPointRec(mouse, row_rect(i)) do continue
		if rl.IsMouseButtonPressed(.LEFT) {
			now := rl.GetTime()
			if state.last_click_i == i && state.selected == i && now - state.last_click_t < 0.4 {
				enter_world()
				return
			}
			state.selected = i
			state.last_click_i = i
			state.last_click_t = now
		}
	}

	if n > 0 && ui.ui_is_clicked(state.enter_btn) {
		enter_world()
		return
	}
	if ui.ui_is_clicked(state.create_btn) {
		open_creator()
		return
	}

	// Keyboard conveniences.
	if rl.IsKeyPressed(.C) {
		open_creator()
		return
	}
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
}

// ── creator input ──────────────────────────────────────────────────────────

handle_create_input :: proc(dt: f32) {
	mouse := rl.GetMousePosition()

	// The name box owns keyboard focus while selected; clicking elsewhere
	// releases it.
	if rl.IsMouseButtonPressed(.LEFT) {
		state.name_focused = rl.CheckCollisionPointRec(mouse, NAME_BOX)
	}

	// Highlight whichever sex/race/class is currently picked.
	races := CREATE_RACES
	_, race_has_sex := sys.chara_model_for_race(races[state.new_race], state.female)
	for i in 0..<len(state.sex_btns) {
		sel := race_has_sex && (i == 1) == state.female
		state.sex_btns[i].base_color = sel ? COL_SEL : COL_BTN
		state.sex_btns[i].hover_color = sel ? COL_SEL_HV : COL_BTN_HOV
	}
	for i in 0..<len(state.race_btns) {
		sel := i == state.new_race
		state.race_btns[i].base_color = sel ? COL_SEL : COL_BTN
		state.race_btns[i].hover_color = sel ? COL_SEL_HV : COL_BTN_HOV
	}
	for i in 0..<len(state.class_btns) {
		sel := i == state.new_class
		state.class_btns[i].base_color = sel ? COL_SEL : COL_BTN
		state.class_btns[i].hover_color = sel ? COL_SEL_HV : COL_BTN_HOV
	}
	state.submit_btn.base_color = state.submitted ? COL_BTN_DIS : COL_CREATE
	state.submit_btn.hover_color = state.submitted ? COL_BTN_DIS : COL_CREATE_HV

	// Pickers: race picks the model (with a sex choice for human/elf).
	for i in 0..<len(state.race_btns) {
		if ui.ui_is_clicked(state.race_btns[i]) {
			if state.new_race != i {
				state.new_race = i
				state.face_i = 0
				state.hair_i = 0
				state.color_i = 0
				state.yaw = 0
				state.model_state = .LOADING
			}
		}
	}
	if race_has_sex {
		for i in 0..<len(state.sex_btns) {
			if ui.ui_is_clicked(state.sex_btns[i]) {
				female := i == 1
				if state.female != female {
					state.female = female
					state.face_i = 0
					state.hair_i = 0
					state.color_i = 0
					state.yaw = 0
					state.model_state = .LOADING
				}
			}
		}
	}
	for i in 0..<len(state.class_btns) {
		if ui.ui_is_clicked(state.class_btns[i]) do state.new_class = i
	}
	if state.model_state == .READY && state.cm != nil {
		faces := len(state.cm.faces)
		hairs := len(state.cm.hairs)
		colors := len(state.cm.hair_colors)
		if faces > 0 {
			if ui.ui_is_clicked(state.face_prev) do set_face((state.face_i + faces - 1) % faces)
			if ui.ui_is_clicked(state.face_next) do set_face((state.face_i + 1) % faces)
		}
		if hairs > 0 {
			if ui.ui_is_clicked(state.hair_prev) do set_hair((state.hair_i + hairs - 1) % hairs)
			if ui.ui_is_clicked(state.hair_next) do set_hair((state.hair_i + 1) % hairs)
		}
		if colors > 0 {
			if ui.ui_is_clicked(state.color_prev) do set_color((state.color_i + colors - 1) % colors)
			if ui.ui_is_clicked(state.color_next) do set_color((state.color_i + 1) % colors)
		}
	}
	if ui.ui_is_clicked(state.random_btn) {
		set_random_name()
	}
	if ui.ui_is_clicked(state.back_btn) {
		close_creator()
		return
	}
	if !state.submitted && ui.ui_is_clicked(state.submit_btn) {
		try_submit()
		return
	}

	// Turntable: drag inside the preview panel rotates the model; otherwise
	// it stands idle (the idle animation plays in update).
	if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse, PREVIEW_PANEL) {
		state.dragging = true
	}
	if state.dragging && rl.IsMouseButtonReleased(.LEFT) {
		state.dragging = false
	}
	if state.model_state == .READY && state.dragging {
		delta := rl.GetMouseDelta()
		state.yaw += delta.x * 0.5
	}

	// Name text entry — alphanumeric only, matching the server validator.
	if state.name_focused {
		c := rl.GetCharPressed()
		for c != 0 {
			alnum := (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
			if alnum && state.new_name_len < NAME_MAX {
				state.new_name[state.new_name_len] = u8(c)
				state.new_name_len += 1
			}
			c = rl.GetCharPressed()
		}
		if rl.IsKeyPressed(.BACKSPACE) && state.new_name_len > 0 {
			state.new_name_len -= 1
		}
	}

	// Keyboard conveniences.
	if rl.IsKeyPressed(.ESCAPE) {
		close_creator()
		return
	}
	if !state.submitted && rl.IsKeyPressed(.ENTER) {
		try_submit()
	}
}

set_face :: proc(i: int) {
	if i == state.face_i do return
	state.face_i = i
	rebuild_subset()
}

set_hair :: proc(i: int) {
	if i == state.hair_i do return
	state.hair_i = i
	rebuild_subset()
}

set_color :: proc(i: int) {
	if i == state.color_i do return
	state.color_i = i
	rebuild_subset()
}

rebuild_subset :: proc() {
	if state.cm == nil do return
	if state.subset_valid {
		sys.chara_subset_free(&state.subset)
		state.subset_valid = false
	}
	state.subset = sys.chara_subset_build(state.cm, state.face_i, state.hair_i, state.color_i)
	state.subset_valid = state.subset.model.meshCount > 0
	if state.subset_valid {
		fit_camera()
	}
}

// Runs one update after model_state went LOADING — the "Loading model…"
// frame has been drawn, so the short freeze from the blocking load is hidden.
load_pending_model :: proc() {
	races := CREATE_RACES
	model_id, _ := sys.chara_model_for_race(races[state.new_race], state.female)
	cm := sys.chara_model_acquire(model_id)

	if state.subset_valid {
		sys.chara_subset_free(&state.subset)
		state.subset_valid = false
	}
	old := state.cm
	state.cm = cm

	if cm == nil {
		state.model_state = .FAILED
	} else {
		state.model_state = .READY
		state.yaw = 0
		state.anim_time = 0
		state.bounds_measured = false
		// Default hair color, as an index into hair_colors.
		state.color_i = 0
		for i in 0..<len(cm.hair_colors) {
			if cm.hair_colors[i] == cm.default_color {
				state.color_i = i
				break
			}
		}
		rebuild_subset()
	}
	if old != nil && old != cm {
		sys.chara_model_release(old)
	}
}

fit_camera :: proc() {
	if state.cm == nil do return
	// Prefer bounds measured from the posed, skinned vertices; fall back to
	// the skeleton-derived ones before the first pose lands.
	bb := state.cm.bounds
	if state.bounds_measured do bb = state.subset_bounds
	size_x := bb.max.x - bb.min.x
	size_y := bb.max.y - bb.min.y
	size_z := bb.max.z - bb.min.z
	cy := (bb.min.y + bb.max.y) * 0.5

	// Center the body in x/z, feet on the ground plane.
	state.model_offset = {
		-(bb.min.x + bb.max.x) * 0.5,
		-bb.min.y,
		-(bb.min.z + bb.max.z) * 0.5,
	}

	// Frame to the taller panel (420x540, ~75% of the window): the model may
	// span ~67% of window height. The bind-pose Z span is unreliable (the rig
	// lies along Z), so depth only guards extreme cases.
	dist := max(size_x / 0.48, size_y / 0.49, size_z / 1.5) + 0.5

	// BeginMode3D projects with the full window, so world origin would land
	// at window center — outside the panel. Aim the camera so the model
	// projects at the panel's center instead.
	FOVY :: 40.0
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	panel_cx := PREVIEW_PANEL.x + PREVIEW_PANEL.width * 0.5
	panel_cy := PREVIEW_PANEL.y + PREVIEW_PANEL.height * 0.5
	world_per_px := (2 * dist * math.tan(f32(FOVY * 0.5 * (math.PI / 180.0)))) / sh
	aim_x := (sw * 0.5 - panel_cx) * world_per_px
	aim_y := (panel_cy - sh * 0.5) * world_per_px

	state.cam = rl.Camera3D{
		position   = {aim_x, cy + aim_y, dist},
		target     = {aim_x, cy + aim_y, 0},
		up         = {0, 1, 0},
		fovy       = f32(FOVY),
		projection = .PERSPECTIVE,
	}
	state.grid_spacing = size_y > 0.01 ? size_y / 4 : 1

	append_debug(fmt.tprintf("fit: sizes=(%.2f, %.2f, %.2f) dist=%.2f grid=%.2f bounds=(%.2f,%.2f,%.2f)-(%.2f,%.2f,%.2f)",
		size_x, size_y, size_z, dist, state.grid_spacing,
		bb.min.x, bb.min.y, bb.min.z, bb.max.x, bb.max.y, bb.max.z))
}

// Appends a line to chara_debug.txt next to the exe (gitignored): lets the
// camera-fit math be checked from the user's runs without console access.
append_debug :: proc(line: string) {
	existing, err := os.read_entire_file_from_path(DEBUG_LOG_PATH, allocator = context.temp_allocator)
	existing_str := ""
	if err == nil do existing_str = string(existing)
	combined := fmt.tprintf("%s%s\n", existing, line)
	_ = os.write_entire_file_from_string(DEBUG_LOG_PATH, combined)
}

open_creator :: proc() {
	state.creating = true
	state.submitted = false
	state.name_focused = true
	state.new_name_len = 0
	state.new_class = 0
	state.new_race = 0
	state.error_len = 0
	state.model_state = .LOADING
}

close_creator :: proc() {
	state.creating = false
	state.submitted = false
	state.name_focused = false
	state.new_name_len = 0
	state.error_len = 0
	if state.subset_valid {
		sys.chara_subset_free(&state.subset)
		state.subset_valid = false
	}
	if state.cm != nil {
		sys.chara_model_release(state.cm)
		state.cm = nil
	}
	state.model_state = .NONE
}

NAME_PART_A :: [10]string{"Ka", "Ael", "Bren", "Cor", "Dai", "El", "Fen", "Gal", "Hal", "Is"}
NAME_PART_B :: [10]string{"ra", "ith", "drin", "na", "ric", "va", "lyn", "mar", "wen", "dor"}

set_random_name :: proc() {
	part_a := NAME_PART_A
	part_b := NAME_PART_B
	a := part_a[int(rl.GetRandomValue(0, i32(len(part_a) - 1)))]
	b := part_b[int(rl.GetRandomValue(0, i32(len(part_b) - 1)))]
	sys.copy_string_to_buffer(state.new_name[:], &state.new_name_len, fmt.tprintf("%s%s", a, b))
	state.error_len = 0
}

try_submit :: proc() {
	if state.new_name_len < NAME_MIN {
		set_error(fmt.tprintf("Name must be at least %d characters", NAME_MIN))
		return
	}
	name := string(state.new_name[:state.new_name_len])
	classes := CREATE_CLASSES
	races := CREATE_RACES
	model_id, _ := sys.chara_model_for_race(races[state.new_race], state.female)
	sys.send_character_create(state.net, name, classes[state.new_class], races[state.new_race], model_id, state.face_i, state.hair_i, state.color_i)
	state.submitted = true
	state.error_len = 0
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

// Appearance for entering the world: the selected entry's persisted picks
// (model/face/hair/color echoed by CHARACTER_LIST). Only falls back to the
// creator's race/sex state when the entry carries no model id.
selected_appearance :: proc() -> sys.Local_Appearance {
	if state.selected >= 0 && state.selected < len(state.entries) {
		e := &state.entries[state.selected]
		if e.model_len > 0 {
			return sys.Local_Appearance{
				model_id = string(e.model_id[:e.model_len]),
				face_i   = e.face_index,
				hair_i   = e.hair_index,
				color_i  = e.hair_color,
			}
		}
	}
	races := CREATE_RACES
	model_id, _ := sys.chara_model_for_race(races[state.new_race], state.female)
	return sys.Local_Appearance{
		model_id = model_id,
		face_i   = state.face_i,
		hair_i   = state.hair_i,
		color_i  = state.color_i,
	}
}

// Returns the currently-highlighted character id (for main to know what to
// pass to gameplay once the WORLD_STATE arrives).
selected_character_id :: proc() -> string {
	if state.selected < 0 || state.selected >= len(state.entries) do return ""
	e := state.entries[state.selected]
	return string(e.id[:e.id_len])
}

display_name :: proc(id: string) -> string {
	if len(id) == 0 do return id
	c := id[0]
	if c >= 'a' && c <= 'z' do c -= 'a' - 'A'
	return fmt.tprintf("%c%s", c, id[1:])
}

// ── rendering ──────────────────────────────────────────────────────────────

render :: proc() {
	rl.ClearBackground(COL_BG)

	if state.creating {
		render_create()
		return
	}

	tw := sys.measure_text("Select Character", 36)
	sys.draw_text("Select Character", 640 - tw / 2, 60, 36, rl.GOLD)

	n := len(state.entries)
	if n == 0 {
		hint := "No characters yet — click Create Character below"
		hw := sys.measure_text(hint, 20)
		sys.draw_text(hint, 640 - hw / 2, 300, 20, rl.LIGHTGRAY)
	}

	// Character rows (click to select, double-click to play).
	mouse := rl.GetMousePosition()
	for i in 0..<min(n, MAX_LIST_ROWS) {
		r := row_rect(i)
		e := &state.entries[i]
		sel := i == state.selected
		hov := rl.CheckCollisionPointRec(mouse, r)

		col := COL_PANEL
		if sel do col = COL_SEL
		if hov && !sel do col = COL_PANEL_HV
		if hov && sel do col = COL_SEL_HV
		rl.DrawRectangleRec(r, col)
		rl.DrawRectangleLinesEx(r, 2, sel ? rl.GOLD : COL_BORDER)

		sys.draw_text(string(e.name[:e.name_len]), int(r.x) + 16, int(r.y) + 12, 22, rl.WHITE)
		info := fmt.tprintf("Lv %d  %s  ·  %s",
			e.level,
			display_name(string(e.race[:e.race_len])),
			display_name(string(e.class[:e.class_len])),
		)
		sys.draw_text(info,
			int(r.x + r.width) - sys.measure_text(info, 16) - 16,
			int(r.y) + 15, 16, rl.LIGHTGRAY)
	}
	if n > MAX_LIST_ROWS {
		more := fmt.tprintf("…and %d more (↑/↓ to reach them)", n - MAX_LIST_ROWS)
		mw := sys.measure_text(more, 14)
		sys.draw_text(more, 640 - mw / 2, 140 + MAX_LIST_ROWS * int(LIST_ROW_STEP) - 4, 14, rl.GRAY)
	}

	ui.ui_draw_button(state.create_btn)
	ui.ui_draw_button(state.enter_btn)

	hint := "Click: select    Double-click: enter world    C: create new"
	hw := sys.measure_text(hint, 14)
	sys.draw_text(hint, 640 - hw / 2, 684, 14, rl.GRAY)

	if state.error_len > 0 {
		msg := string(state.error_msg[:state.error_len])
		sys.draw_text(msg, 640 - sys.measure_text(msg, 16) / 2, 585, 16, rl.RED)
	}
}

render_create :: proc() {
	tw := sys.measure_text("Create Character", 32)
	sys.draw_text("Create Character", 640 - tw / 2, 56, 32, rl.GOLD)

	// Left: 3d preview viewport (subset model), fallback text when loading.
	panel := PREVIEW_PANEL
	render_preview(panel)

	race_labels := RACE_LABELS
	class_labels := CLASS_LABELS
	cap := fmt.tprintf("%s  ·  %s", race_labels[state.new_race], class_labels[state.new_class])
	cw := sys.measure_text(cap, 20)
	cx := int(panel.x + panel.width / 2)
	sys.draw_text(cap, cx - cw / 2, int(panel.y + panel.height) + 8, 20, rl.LIGHTGRAY)
	hint := "drag to rotate"
	hw := sys.measure_text(hint, 14)
	sys.draw_text(hint, cx - hw / 2, int(panel.y + panel.height) + 34, 14, rl.GRAY)

	// Right: name field.
	sys.draw_text("Name", 580, 116, 18, rl.LIGHTGRAY)
	rl.DrawRectangleRec(NAME_BOX, COL_INPUT_BG)
	rl.DrawRectangleLinesEx(NAME_BOX, 2, state.name_focused ? rl.GOLD : COL_BORDER)
	name_txt := string(state.new_name[:state.new_name_len])
	sys.draw_text(name_txt, 592, 148, 20, rl.WHITE)
	blink := f64(rl.GetTime()) * 2
	if state.name_focused && blink - math.floor(blink) < 1 {
		sys.draw_text("|", 592 + sys.measure_text(name_txt, 20) + 2, 145, 22, rl.GOLD)
	}
	cnt := fmt.tprintf("%d/%d", state.new_name_len, NAME_MAX)
	sys.draw_text(cnt,
		int(NAME_BOX.x + NAME_BOX.width) - sys.measure_text(cnt, 14) - 10,
		151, 14, rl.GRAY)

	// Right: sex picker (human/elf only).
	races_render := CREATE_RACES
	race_has_sex := false
	if state.creating {
		_, race_has_sex = sys.chara_model_for_race(races_render[state.new_race], state.female)
	}
	if race_has_sex {
		sys.draw_text("Gender", 580, 188, 18, rl.LIGHTGRAY)
		for i in 0..<len(state.sex_btns) do ui.ui_draw_button(state.sex_btns[i])
	}

	// Right: race and class grids.
	sys.draw_text("Race", 580, 294, 18, rl.LIGHTGRAY)
	for i in 0..<len(state.race_btns) do ui.ui_draw_button(state.race_btns[i])

	sys.draw_text("Class", 580, 392, 18, rl.LIGHTGRAY)
	for i in 0..<len(state.class_btns) do ui.ui_draw_button(state.class_btns[i])

	// Face / hair variant steppers + hair color swatches.
	sys.draw_text("Face", 580, 510, 16, rl.LIGHTGRAY)
	ui.ui_draw_button(state.face_prev)
	ui.ui_draw_button(state.face_next)
	if state.cm != nil && len(state.cm.faces) > 0 {
		fc := fmt.tprintf("%d/%d", state.face_i + 1, len(state.cm.faces))
		sys.draw_text(fc, 662, 510, 16, rl.WHITE)
	}

	sys.draw_text("Hair", 750, 510, 16, rl.LIGHTGRAY)
	ui.ui_draw_button(state.hair_prev)
	ui.ui_draw_button(state.hair_next)
	if state.cm != nil && len(state.cm.hairs) > 0 {
		hc := fmt.tprintf("%d/%d", state.hair_i + 1, len(state.cm.hairs))
		sys.draw_text(hc, 832, 510, 16, rl.WHITE)
	}

	sys.draw_text("Color", 920, 510, 16, rl.LIGHTGRAY)
	ui.ui_draw_button(state.color_prev)
	ui.ui_draw_button(state.color_next)
	if state.cm != nil && len(state.cm.hair_colors) > 0 {
		cc := fmt.tprintf("%d/%d", state.color_i + 1, len(state.cm.hair_colors))
		sys.draw_text(cc, 1002, 510, 16, rl.WHITE)
	}

	if state.error_len > 0 {
		sys.draw_text(string(state.error_msg[:state.error_len]), 580, 570, 14, rl.RED)
	} else if state.submitted {
		sys.draw_text("Creating...", 580, 570, 14, rl.GRAY)
	}

	ui.ui_draw_button(state.submit_btn)
	ui.ui_draw_button(state.back_btn)
}

render_preview :: proc(panel: rl.Rectangle) {
	rl.DrawRectangleRec(panel, COL_PANEL)

	switch state.model_state {
	case .READY:
		if state.subset_valid {
			// 3d viewport clipped to the panel; border redrawn after so the
			// model never paints over it.
			rl.BeginScissorMode(i32(panel.x), i32(panel.y), i32(panel.width), i32(panel.height))
			rl.BeginMode3D(state.cam)
			rl.DrawModelEx(state.subset.model, state.model_offset, {0, 1, 0}, state.yaw, {1, 1, 1}, rl.WHITE)
			rl.DrawGrid(8, state.grid_spacing)
			rl.EndMode3D()
			rl.EndScissorMode()
		}
	case .LOADING:
		draw_centered_in_panel(panel, "Loading model...", 18, rl.LIGHTGRAY)
	case .FAILED:
		draw_centered_in_panel(panel, "Model failed to load", 16, rl.RED)
	case .NONE:
		// Placeholder mannequin tinted by class, until the load kicks in.
		tint_colors := CLASS_COLORS
		tint := tint_colors[state.new_class]
		faded := rl.Color{tint.r, tint.g, tint.b, 60}
		cx := panel.x + panel.width / 2
		cy := panel.y + panel.height / 2 - 30
		rl.DrawCircleLines(i32(cx), i32(cy), 140, faded)
		rl.DrawCircleV({cx, cy - 100}, 32, tint)
		rl.DrawRectanglePro({cx - 44, cy - 60, 88, 120}, {}, 0, tint)
		rl.DrawRectanglePro({cx - 40, cy + 60, 32, 95}, {}, 0, tint)
		rl.DrawRectanglePro({cx + 8, cy + 60, 32, 95}, {}, 0, tint)
		rl.DrawRectanglePro({cx - 72, cy - 55, 24, 100}, {}, 0, tint)
		rl.DrawRectanglePro({cx + 48, cy - 55, 24, 100}, {}, 0, tint)
		rl.DrawEllipse(i32(cx), i32(cy + 172), 120, 20, {tint.r, tint.g, tint.b, 70})
	}

	rl.DrawRectangleLinesEx(panel, 2, COL_BORDER)
}

draw_centered_in_panel :: proc(panel: rl.Rectangle, text: string, size: int, color: rl.Color) {
	tw := sys.measure_text(text, size)
	sys.draw_text(text,
		int(panel.x + panel.width / 2) - tw / 2,
		int(panel.y + panel.height / 2) - size / 2,
		size, color)
}
