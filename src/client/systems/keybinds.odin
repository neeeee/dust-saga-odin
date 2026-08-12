package systems

import "core:encoding/json"
import "core:fmt"
import "core:os"
import rl "vendor:raylib"

// Rebindable keybinds. Every gameplay/menu action goes through an `Action`
// enum whose key lives in a global table; poll_input and the menu keybinds
// read `bind_down`/`bind_pressed` instead of hardcoding rl.KeyboardKeys. The
// table defaults to WASD + standard MMO binds, is rebindable from the Settings
// menu, and persists to keybinds.json.

Action :: enum u8 {
	// movement
	Move_Up,
	Move_Down,
	Move_Left,
	Move_Right,
	Sprint,

	// combat / interaction
	Attack,       // held — auto-attack
	Manual_Attack, // cone attack
	Interact,
	Toggle_Rest,
	Cycle_Target, // Shift+Cycle_Target = reverse

	// skill bar (slots 0..9)
	Skill_1,
	Skill_2,
	Skill_3,
	Skill_4,
	Skill_5,
	Skill_6,
	Skill_7,
	Skill_8,
	Skill_9,
	Skill_0,

	// UI / menu toggles
	Menu_Inventory,
	Menu_Character,
	Menu_Skills,
	Menu_Debug,

	// chat
	Chat_Toggle,
}
ACTION_COUNT :: len(Action)

// Maps skill-bar slot index (0..9) → Skill_1..Skill_0 action.
SKILL_SLOT_ACTION: [10]Action = {
	.Skill_1, .Skill_2, .Skill_3, .Skill_4, .Skill_5,
	.Skill_6, .Skill_7, .Skill_8, .Skill_9, .Skill_0,
}

KeyBinds :: struct {
	keys: [Action]rl.KeyboardKey,
}

// Global bind table — loaded once at boot, mutated only through rebind procs.
keybinds: KeyBinds

// Default bindings (WASD + standard). Returned fresh so the settings "reset"
// just calls this.
keybind_defaults :: proc() -> KeyBinds {
	kb: KeyBinds
	kb.keys[.Move_Up] = .W
	kb.keys[.Move_Down] = .S
	kb.keys[.Move_Left] = .A
	kb.keys[.Move_Right] = .D
	kb.keys[.Sprint] = .LEFT_SHIFT
	kb.keys[.Attack] = .F
	kb.keys[.Manual_Attack] = .SPACE
	kb.keys[.Interact] = .E
	kb.keys[.Toggle_Rest] = .R
	kb.keys[.Cycle_Target] = .TAB
	kb.keys[.Skill_1] = .ONE
	kb.keys[.Skill_2] = .TWO
	kb.keys[.Skill_3] = .THREE
	kb.keys[.Skill_4] = .FOUR
	kb.keys[.Skill_5] = .FIVE
	kb.keys[.Skill_6] = .SIX
	kb.keys[.Skill_7] = .SEVEN
	kb.keys[.Skill_8] = .EIGHT
	kb.keys[.Skill_9] = .NINE
	kb.keys[.Skill_0] = .ZERO
	kb.keys[.Menu_Inventory] = .I
	kb.keys[.Menu_Character] = .C
	kb.keys[.Menu_Skills] = .K
	kb.keys[.Menu_Debug] = .F1
	kb.keys[.Chat_Toggle] = .ENTER
	return kb
}

// Human-readable action labels (Settings menu + persisted JSON keys).
action_name :: proc "contextless" (a: Action) -> string {
	switch a {
	case .Move_Up:        return "Move Up"
	case .Move_Down:      return "Move Down"
	case .Move_Left:      return "Move Left"
	case .Move_Right:     return "Move Right"
	case .Sprint:         return "Sprint"
	case .Attack:         return "Attack"
	case .Manual_Attack:  return "Manual Attack"
	case .Interact:       return "Interact"
	case .Toggle_Rest:    return "Toggle Rest"
	case .Cycle_Target:   return "Cycle Target"
	case .Skill_1:        return "Skill Slot 1"
	case .Skill_2:        return "Skill Slot 2"
	case .Skill_3:        return "Skill Slot 3"
	case .Skill_4:        return "Skill Slot 4"
	case .Skill_5:        return "Skill Slot 5"
	case .Skill_6:        return "Skill Slot 6"
	case .Skill_7:        return "Skill Slot 7"
	case .Skill_8:        return "Skill Slot 8"
	case .Skill_9:        return "Skill Slot 9"
	case .Skill_0:        return "Skill Slot 0"
	case .Menu_Inventory: return "Inventory"
	case .Menu_Character: return "Character"
	case .Menu_Skills:    return "Skills"
	case .Menu_Debug:     return "Debug"
	case .Chat_Toggle:    return "Toggle Chat"
	}
	return "?"
}

// ── key ↔ name (for display + persistence) ────────────────────────────────
// Single source: KEY_NAMES drives both directions.

Key_Name_Entry :: struct {
	name: string,
	key:  rl.KeyboardKey,
}

KEY_NAMES := []Key_Name_Entry {
	{"A", .A}, {"B", .B}, {"C", .C}, {"D", .D}, {"E", .E}, {"F", .F},
	{"G", .G}, {"H", .H}, {"I", .I}, {"J", .J}, {"K", .K}, {"L", .L},
	{"M", .M}, {"N", .N}, {"O", .O}, {"P", .P}, {"Q", .Q}, {"R", .R},
	{"S", .S}, {"T", .T}, {"U", .U}, {"V", .V}, {"W", .W}, {"X", .X},
	{"Y", .Y}, {"Z", .Z},
	{"0", .ZERO}, {"1", .ONE}, {"2", .TWO}, {"3", .THREE}, {"4", .FOUR},
	{"5", .FIVE}, {"6", .SIX}, {"7", .SEVEN}, {"8", .EIGHT}, {"9", .NINE},
	{"Space", .SPACE}, {"Tab", .TAB}, {"Enter", .ENTER}, {"Esc", .ESCAPE},
	{"L-Shift", .LEFT_SHIFT}, {"R-Shift", .RIGHT_SHIFT},
	{"L-Ctrl", .LEFT_CONTROL}, {"R-Ctrl", .RIGHT_CONTROL},
	{"Up", .UP}, {"Down", .DOWN}, {"Left", .LEFT}, {"Right", .RIGHT},
	{"F1", .F1}, {"F2", .F2}, {"F3", .F3}, {"F4", .F4}, {"F5", .F5},
	{"F6", .F6}, {"F7", .F7}, {"F8", .F8}, {"F9", .F9}, {"F10", .F10},
	{"F11", .F11}, {"F12", .F12},
}

key_name :: proc "contextless" (k: rl.KeyboardKey) -> string {
	for e in KEY_NAMES {
		if e.key == k do return e.name
	}
	return "?"
}

key_from_name :: proc "contextless" (s: string) -> (rl.KeyboardKey, bool) {
	for e in KEY_NAMES {
		if e.name == s do return e.key, true
	}
	return .ESCAPE, false
}

// ── query helpers (the only way gameplay code should read keys) ────────────

bind_down :: proc "contextless" (a: Action) -> bool {
	return rl.IsKeyDown(keybinds.keys[a])
}

bind_pressed :: proc "contextless" (a: Action) -> bool {
	return rl.IsKeyPressed(keybinds.keys[a])
}

bind_released :: proc "contextless" (a: Action) -> bool {
	return rl.IsKeyReleased(keybinds.keys[a])
}

// ── persistence (keybinds.json next to the executable) ─────────────────────

KEYBINDS_PATH :: "keybinds.json"

load_keybinds :: proc() {
	keybinds = keybind_defaults()
	data, err := os.read_entire_file_from_path(KEYBINDS_PATH, allocator = context.allocator)
	if err != nil do return
	defer delete(data)
	v, pok := json_parse(data)
	if !pok do return
	obj := obj_of(v)
	for a in Action {
		s := get_string(obj, action_name(a))
		if k, kok := key_from_name(s); kok do keybinds.keys[a] = k
	}
}

save_keybinds :: proc() {
	obj := make(map[string]JSON_Value)
	for a in Action {
		obj[action_name(a)] = json.String(key_name(keybinds.keys[a]))
	}
	v: JSON_Value = json.Object(obj)
	out, ok := json_marshal(&v)
	delete(obj)
	if !ok do return
	_ = os.write_entire_file_from_string(KEYBINDS_PATH, out)
}

// ── rebind flow (Settings menu drives this) ────────────────────────────────
// Click an action in Settings → start_rebind(action). Each frame the menu
// calls poll_rebind(): if the user presses a key it's assigned + saved; Esc
// cancels. While listening, the action's button shows "press a key…".

rebind_target:   Action = .Move_Up
rebind_listening: bool

start_rebind :: proc(a: Action) {
	rebind_target = a
	rebind_listening = true
}

cancel_rebind :: proc() {
	rebind_listening = false
}

// Returns true if a rebind was completed this frame (so the caller can close
// the listening state). False while still waiting / on cancel.
poll_rebind :: proc() -> bool {
	if !rebind_listening do return false
	if rl.IsKeyPressed(.ESCAPE) {
		rebind_listening = false
		return false
	}
	k := rl.GetKeyPressed()
	if k == .KEY_NULL do return false
	// Drain any extras so they don't leak into the next consumer.
	for rl.GetKeyPressed() != .KEY_NULL {}
	keybinds.keys[rebind_target] = k
	rebind_listening = false
	save_keybinds()
	return true
}

_ :: fmt.println
