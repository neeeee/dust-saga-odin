package gameplay

import sys "../../systems"
import ui "../../ui/"
import "core:fmt"
import "core:math"
import "core:strings"
import rl "vendor:raylib"

BAR_BTN_SIZE :: 36
BAR_BTN_GAP :: 4
BAR_X :: 16

// Menu-bar Y: bottom-left, just under the chat input box (Pandora Saga layout).
menu_bar_y :: proc() -> i32 {
	return rl.GetScreenHeight() - 72
}

SHOP_CAT_ALL_ID :: 1
SHOP_CAT_WEAPONS_ID :: 2
SHOP_CAT_ARMOR_ID :: 3
SHOP_CAT_CONSUMABLES_ID :: 4
SHOP_CAT_MATERIALS_ID :: 5
SHOP_CAT_ACCESSORIES_ID :: 6
SHOP_ITEM_BASE_ID :: 100

bar_btn_rect :: proc(idx: int) -> rl.Rectangle {
	x := f32(BAR_X + idx * (BAR_BTN_SIZE + BAR_BTN_GAP))
	return {x, f32(menu_bar_y()), BAR_BTN_SIZE, BAR_BTN_SIZE}
}

// ── create procs ──────────────────────────────────────────────────────────

create_settings_menu :: proc() {
	// Content is rebuilt each frame by refresh_settings_menu (the key list
	// changes as the user rebinds).
	state.settings_menu = ui.menu_create("Settings — Keybinds", 300, 80, 420, 560)
	state.settings_menu.close_on_esc = true
}

create_skills_menu :: proc() {
	// Content is rebuilt each frame by refresh_skills_menu (it depends on the
	// player's live job / adeptness / caps).
	state.skills_menu = ui.menu_create("Skills", 300, 120, 460, 540)
	state.skills_menu.close_on_esc = true
}

create_friends_menu :: proc() {
	m := &state.friends_menu
	m^ = ui.menu_create("Friends", 400, 200, 350, 400)
	ui.menu_add_label(m, "Online - 2")
	ui.menu_add_separator(m)
	ui.menu_add_button(m, "xLuna      Lv 42")
	ui.menu_add_button(m, "DustKing   Lv 38")
	ui.menu_add_separator(m)
	ui.menu_add_button(m, "Add Friend")
	ui.menu_add_button(m, "Whisper")
}

create_party_menu :: proc() {
	// Content is custom-drawn (Pandora Saga PT panel, top-right); the ui.Menu
	// only carries the open/focused flags and the panel rect for hit-testing.
	m := &state.party_menu
	m^ = ui.menu_create("PT MEMBER", 0, 0, PARTY_PANEL_W, PARTY_PANEL_H)
}

// ── party panel (Pandora Saga style, top-right under the minimap area) ────

PARTY_PANEL_W :: 240
PARTY_PANEL_H :: 250
PARTY_HEADER_H :: 24
PARTY_ROW_H :: 52
PARTY_FOOTER_H :: 28

// Member rows shown in the panel. Until PARTY_UPDATE is wired up client-side,
// the local player is the sole row (party leader).
party_panel_rect :: proc() -> rl.Rectangle {
	sw := f32(rl.GetScreenWidth())
	return {sw - PARTY_PANEL_W - 12, 64, PARTY_PANEL_W, PARTY_PANEL_H}
}

party_row_rect :: proc(panel: rl.Rectangle, i: int) -> rl.Rectangle {
	return {panel.x + 6, panel.y + PARTY_HEADER_H + 6 + f32(i * PARTY_ROW_H), panel.width - 12, f32(PARTY_ROW_H - 4)}
}

party_footer_btn_rect :: proc(panel: rl.Rectangle, i: int) -> rl.Rectangle {
	bw := (panel.width - 24) / 2 - 3
	return {
		panel.x + 8 + f32(i) * (bw + 8),
		panel.y + panel.height - PARTY_FOOTER_H,
		bw,
		f32(PARTY_FOOTER_H - 6),
	}
}

update_party_panel :: proc() {
	m := &state.party_menu
	if !m.open do return

	// Anchored top-right; rect + focused are refreshed every frame (the panel
	// is custom-drawn, so ui.menu_update is not used for it).
	m.rect = party_panel_rect()
	m.focused = rl.CheckCollisionPointRec(rl.GetMousePosition(), m.rect)

	mouse := rl.GetMousePosition()
	if !state.chat_focused && rl.IsMouseButtonPressed(.LEFT) {
		if rl.CheckCollisionPointRec(mouse, party_footer_btn_rect(m.rect, 0)) {
			// Invite — TODO: target picker once party invites are wired.
		} else if rl.CheckCollisionPointRec(mouse, party_footer_btn_rect(m.rect, 1)) {
			sys.send(state.net, .PARTY_LEAVE)
		}
	}
}

draw_party_panel :: proc() {
	m := &state.party_menu
	if !m.open do return
	p := state.player

	rl.DrawRectangleRec(m.rect, rl.Color{15, 16, 22, 210})
	rl.DrawRectangleLinesEx(m.rect, 1, rl.Color{90, 90, 110, 220})

	// Header.
	sys.draw_text(fmt.tprintf("PT MEMBER  (%d/4)", 1), int(m.rect.x) + 8, int(m.rect.y) + 5, 14, rl.Color{220, 220, 235, 255})
	rl.DrawLine(
		i32(m.rect.x),
		i32(m.rect.y + PARTY_HEADER_H),
		i32(m.rect.x + m.rect.width),
		i32(m.rect.y + PARTY_HEADER_H),
		rl.Color{90, 90, 110, 220},
	)

	// Member rows: name + level, HP and MP bars.
	s := &p.stats
	row := party_row_rect(m.rect, 0)
	name := string(p.name[:p.name_len])
	sys.draw_text(fmt.tprintf("Lv%d", s.level), int(row.x) + 4, int(row.y), 12, rl.GRAY)
	sys.draw_text(name, int(row.x) + 36, int(row.y), 12, rl.Color{130, 180, 255, 255})
	bar_w := row.width - 8
	hp_ratio := s.max_health > 0 ? s.health / s.max_health : 0
	mp_ratio := s.max_mana > 0 ? s.mana / s.max_mana : 0
	draw_party_bar(row.x + 4, row.y + 18, bar_w, 10, hp_ratio, rl.Color{200, 40, 40, 255},
		fmt.tprintf("%d/%d", i32(s.health), i32(s.max_health)))
	draw_party_bar(row.x + 4, row.y + 32, bar_w, 8, mp_ratio, rl.Color{60, 110, 220, 255}, "")

	// Footer buttons.
	mouse := rl.GetMousePosition()
	labels := [2]string{"Invite", "Leave"}
	for i in 0 ..< 2 {
		btn := party_footer_btn_rect(m.rect, i)
		hov := rl.CheckCollisionPointRec(mouse, btn)
		col := hov ? rl.Color{75, 85, 115, 230} : rl.Color{55, 60, 75, 230}
		rl.DrawRectangleRec(btn, col)
		rl.DrawRectangleLinesEx(btn, 1, rl.Color{140, 140, 160, 255})
		tw := sys.measure_text(labels[i], 13)
		sys.draw_text(labels[i], int(btn.x + btn.width/2 - f32(tw)/2), int(btn.y) + 6, 13, rl.Color{220, 220, 235, 255})
	}
}

draw_party_bar :: proc(x, y, w, h: f32, ratio: f32, color: rl.Color, label: string) {
	r := math.clamp(ratio, 0, 1)
	rl.DrawRectangleRec({x, y, w, h}, rl.Color{30, 30, 30, 220})
	rl.DrawRectangleRec({x, y, w * r, h}, color)
	rl.DrawRectangleLinesEx({x, y, w, h}, 1, rl.BLACK)
	if len(label) > 0 {
		tw := f32(sys.measure_text(label, 10))
		sys.draw_text(label, int(x + w/2 - tw/2), int(y + h/2 - 5), 10, rl.WHITE)
	}
}

create_quest_list_menu :: proc() {
	m := &state.quest_list_menu
	m^ = ui.menu_create("Quests", 400, 150, 400, 450)
	m.close_on_esc = true
}

// Quest log: live view of the server-authoritative quest list. Abandon is a
// two-click action (first click arms the button, second confirms).
QUEST_LOG_BASE :: 9000

refresh_quest_list_menu :: proc() {
	m := &state.quest_list_menu
	ui.menu_clear(m)

	if len(state.player.quests) == 0 {
		ui.menu_add_label(m, "No quests yet.")
		ui.menu_add_label(m, "Talk to an NPC with a ! marker to find work.")
		ui.menu_auto_height(m, 560)
		return
	}

	shown := 0
	for i in 0 ..< len(state.player.quests) {
		q := &state.player.quests[i]
		if q.status == .TURNED_IN do continue
		shown += 1
		suffix := q.status == .COMPLETED ? "  — ready to turn in" : ""
		ui.menu_add_label(m, fmt.tprintf("%s%s", sys.quest_title_string(q), suffix))
		if q.status != .COMPLETED {
			for j in 0 ..< len(q.objectives) {
				o := &q.objectives[j]
				mark := o.current >= o.required ? "[x]" : "[ ]"
				ui.menu_add_label(
					m,
					fmt.tprintf("  %s %s %d/%d", mark, sys.objective_name_string(o), o.current, o.required),
				)
			}
		}
		if state.quest_log_abandon_idx == i {
			ui.menu_add_button_id(m, "Abandon? (click again)", QUEST_LOG_BASE + i)
		} else {
			ui.menu_add_button_id(m, "Abandon", QUEST_LOG_BASE + i)
		}
		ui.menu_add_separator(m)
	}
	if shown == 0 {
		ui.menu_add_label(m, "No active quests.")
	}
	ui.menu_auto_height(m, 560)
}

handle_quest_list_menu_clicks :: proc() {
	m := &state.quest_list_menu
	if !m.open do return
	for i in 0 ..< len(m.items) {
		item := &m.items[i]
		if item.kind != .BUTTON || !item.clicked do continue
		idx := item.id - QUEST_LOG_BASE
		if idx < 0 || idx >= len(state.player.quests) do continue
		if state.quest_log_abandon_idx == idx {
			sys.send_quest_abandon(state.net, sys.quest_id_string(&state.player.quests[idx]))
			state.quest_log_abandon_idx = -1
		} else {
			state.quest_log_abandon_idx = idx
		}
	}
}

// Button-id bases: equip a backpack item (6000 + inv index), use a consumable
// (8000 + inv index), unequip a slot (7000 + slot index).
INV_EQUIP_BASE   :: 6000
INV_UNEQUIP_BASE :: 7000
INV_USE_BASE     :: 8000

// "+N [Element]" suffix for an enhanced item, or "".
enh_suffix :: proc(it: ^sys.Inventory_Item) -> string {
	if it.enhancement_level <= 0 do return ""
	elem := string(it.enhancement_element[:it.enhancement_elem_len])
	if len(elem) > 0 {
		return fmt.tprintf(" +%d %s", it.enhancement_level, enhance_element_display(elem))
	}
	return fmt.tprintf(" +%d", it.enhancement_level)
}

refresh_inventory_menu :: proc() {
	m := &state.inventory_menu
	inv := &state.player.inventory
	ui.menu_clear(m)
	ui.menu_add_label(m, fmt.tprintf("Gold: %d", inv.gold))

	// Equipped slots (click to unequip).
	ui.menu_add_label(m, "— Equipped —")
	any_eq := false
	for slot in sys.EQUIP_SLOT {
		es := &inv.equipment[int(slot)]
		if es.item_id_len == 0 do continue
		any_eq = true
		label := fmt.tprintf("%-9s %s%s  [remove]", sys.EQUIP_SLOT_NAMES[int(slot)], sys.item_name(sys.item_id_string(es)), enh_suffix(es))
		ui.menu_add_button_id(m, label, INV_UNEQUIP_BASE + int(slot))
	}
	if !any_eq do ui.menu_add_label(m, "(nothing equipped)")

	ui.menu_add_separator(m)
	ui.menu_add_label(m, "— Backpack —")
	for i in 0 ..< len(inv.items) {
		it := &inv.items[i]
		id := sys.item_id_string(it)
		name := sys.item_name(id)
		if sys.item_is_equippable(id) {
			ui.menu_add_button_id(m, fmt.tprintf("%s%s x%d  [equip]", name, enh_suffix(it), it.quantity), INV_EQUIP_BASE + i)
		} else if def, ok := sys.item_def(id); ok && def.type == .CONSUMABLE {
			ui.menu_add_button_id(m, fmt.tprintf("%s x%d  [use]", name, it.quantity), INV_USE_BASE + i)
		} else {
			ui.menu_add_label(m, fmt.tprintf("%s%s x%d", name, enh_suffix(it), it.quantity))
		}
	}
	ui.menu_auto_height(m, 560)
}

handle_inventory_menu_clicks :: proc() {
	m := &state.inventory_menu
	if !m.open do return
	inv := &state.player.inventory
	for i in 0 ..< len(m.items) {
		item := &m.items[i]
		if item.kind != .BUTTON || !item.clicked do continue
		if item.id >= INV_UNEQUIP_BASE && item.id < INV_UNEQUIP_BASE + sys.EQUIP_SLOT_COUNT {
			slot := sys.EQUIP_SLOT(item.id - INV_UNEQUIP_BASE)
			sys.send_unequip_item(state.net, sys.EQUIP_SLOT_NAMES[int(slot)])
		} else if item.id >= INV_USE_BASE {
			idx := item.id - INV_USE_BASE
			if idx >= 0 && idx < len(inv.items) {
				sys.send_item_use(state.net, sys.item_id_string(&inv.items[idx]))
			}
		} else if item.id >= INV_EQUIP_BASE && item.id < INV_UNEQUIP_BASE {
			idx := item.id - INV_EQUIP_BASE
			if idx >= 0 && idx < len(inv.items) {
				sys.send_equip_item(state.net, sys.item_id_string(&inv.items[idx]))
			}
		}
	}
}

// ── weapon/gear enhancement window (Blacksmith Garn: "Enhance weapon") ────
// Two-column picker: enhancable equipment (left) and element gems (right),
// with the live success chance from the server's fail table. Selections are
// stored as item ids and re-resolved to inventory indices each frame, so the
// INVENTORY_UPDATE that follows an attempt (gem consumed) can't desync them.

ENH_WIN_W     :: 600
ENH_WIN_H     :: 420
ENH_ROW_H     :: 26
ENH_HDR_H     :: 22

// Fail % by current enhancement level (mirrors enhancementHandlers.ts).
ENHANCE_FAIL_PCT: [10]int = {0, 0, 5, 15, 25, 35, 50, 65, 80, 90}

ENH_COL_BTN     :: rl.Color{55, 60, 75, 255}
ENH_COL_BTN_HOV :: rl.Color{75, 85, 115, 255}
ENH_COL_SEL     :: rl.Color{45, 80, 55, 255}
ENH_COL_GOLD    :: rl.Color{255, 210, 90, 255}
ENH_COL_GREEN   :: rl.Color{120, 230, 120, 255}
ENH_COL_RED     :: rl.Color{235, 100, 100, 255}
ENH_COL_DIM     :: rl.Color{160, 160, 170, 255}

enh_window_rect :: proc() -> rl.Rectangle {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	return {sw / 2 - ENH_WIN_W / 2, sh / 2 - ENH_WIN_H / 2, f32(ENH_WIN_W), f32(ENH_WIN_H)}
}

enh_close_rect :: proc "contextless" (win: rl.Rectangle) -> rl.Rectangle {
	sz := f32(18.0)
	return {win.x + win.width - 12 - sz, win.y + (BAR_BTN_SIZE - sz) / 2 + 6, sz, sz}
}

enh_weapon_list_rect :: proc "contextless" (win: rl.Rectangle) -> rl.Rectangle {
	return {win.x + 10, win.y + 64, win.width / 2 - 15, win.height - 168}
}

enh_gem_list_rect :: proc "contextless" (win: rl.Rectangle) -> rl.Rectangle {
	return {win.x + win.width / 2 + 5, win.y + 64, win.width / 2 - 15, win.height - 168}
}

enh_row_rect :: proc "contextless" (list: rl.Rectangle, row: int) -> rl.Rectangle {
	return {list.x, list.y + f32(row * ENH_ROW_H), list.width, f32(ENH_ROW_H - 2)}
}

enh_enhance_btn_rect :: proc "contextless" (win: rl.Rectangle) -> rl.Rectangle {
	return {win.x + win.width - 162, win.y + win.height - 46, 150, 34}
}

enhance_weapon_id_string :: proc() -> string {
	return string(state.enhance_weapon_id[:state.enhance_weapon_id_len])
}

enhance_gem_id_string :: proc() -> string {
	return string(state.enhance_gem_id[:state.enhance_gem_id_len])
}

// Gem item id → element key the server assigns (GEM_ELEMENT_MAP).
enhance_gem_element :: proc "contextless" (gem_id: string) -> string {
	switch gem_id {
	case "fire_gem":              return "fire"
	case "ice_gem":               return "ice"
	case "lightning_gem":         return "lightning"
	case "holy_gem":              return "holy"
	case "dark_gem":              return "dark"
	case "poison_gem":            return "poison"
	case "fire_magic_gem":        return "magic_fire"
	case "ice_magic_gem":         return "magic_ice"
	case "lightning_magic_gem":   return "magic_lightning"
	case "holy_magic_gem":        return "magic_holy"
	case "dark_magic_gem":        return "magic_dark"
	case "poison_magic_gem":      return "magic_poison"
	case:                         return ""
	}
}

enhance_element_display :: proc "contextless" (elem: string) -> string {
	switch elem {
	case "fire":             return "Fire"
	case "ice":              return "Ice"
	case "lightning":        return "Lightning"
	case "holy":             return "Holy"
	case "dark":             return "Dark"
	case "poison":           return "Poison"
	case "magic_fire":       return "Magic Fire"
	case "magic_ice":        return "Magic Ice"
	case "magic_lightning":  return "Magic Lightning"
	case "magic_holy":       return "Magic Holy"
	case "magic_dark":       return "Magic Dark"
	case "magic_poison":     return "Magic Poison"
	case:                   return elem
	}
}

// Inventory indices of rows to show: equippable items (left) / gems (right).
collect_enh_rows :: proc(gems: bool) -> []int {
	rows := make([dynamic]int)
	inv := &state.player.inventory
	for i in 0 ..< len(inv.items) {
		id := sys.item_id_string(&inv.items[i])
		if gems {
			if strings.has_suffix(id, "_gem") do append(&rows, i)
		} else {
			if sys.item_is_equippable(id) do append(&rows, i)
		}
	}
	return rows[:]
}

// Current inventory index for a selected item id, or -1 if no longer held.
resolve_inv_index :: proc(id: string) -> int {
	if len(id) == 0 do return -1
	inv := &state.player.inventory
	for i in 0 ..< len(inv.items) {
		if sys.item_id_string(&inv.items[i]) == id do return i
	}
	return -1
}

resolve_enh_weapon_index :: proc() -> int {
	return resolve_inv_index(enhance_weapon_id_string())
}

resolve_enh_gem_index :: proc() -> int {
	return resolve_inv_index(enhance_gem_id_string())
}

// Mirror of the server's gate: item held, below +10, and gem element matches
// the item's existing element (empty = unelemented, anything goes).
enh_can_attempt :: proc(wi, gi: int) -> bool {
	inv := &state.player.inventory
	if wi < 0 || gi < 0 || wi >= len(inv.items) || gi >= len(inv.items) do return false
	w := &inv.items[wi]
	if w.enhancement_level >= 10 do return false
	welem := string(w.enhancement_element[:w.enhancement_elem_len])
	gelem := enhance_gem_element(sys.item_id_string(&inv.items[gi]))
	if len(gelem) == 0 do return false
	if len(welem) > 0 && welem != gelem do return false
	return true
}

open_enhancement_window :: proc() {
	ui.menu_open(&state.blacksmith_menu)
	state.enhance_weapon_id_len = 0
	state.enhance_gem_id_len = 0
}

update_blacksmith_menu :: proc() {
	m := &state.blacksmith_menu
	if !m.open do return
	m.rect = enh_window_rect()
	mouse := rl.GetMousePosition()
	m.focused = rl.CheckCollisionPointRec(mouse, m.rect)
	if state.chat_focused do return

	if !rl.IsMouseButtonPressed(.LEFT) do return

	if rl.CheckCollisionPointRec(mouse, enh_close_rect(m.rect)) {
		ui.menu_close(m)
		return
	}

	inv := &state.player.inventory

	wr := enh_weapon_list_rect(m.rect)
	for r, i in collect_enh_rows(false) {
		if rl.CheckCollisionPointRec(mouse, enh_row_rect(wr, i)) {
			sys.copy_string_to_buffer(
				state.enhance_weapon_id[:], &state.enhance_weapon_id_len,
				sys.item_id_string(&inv.items[r]),
			)
			return
		}
	}

	gr := enh_gem_list_rect(m.rect)
	for r, i in collect_enh_rows(true) {
		if rl.CheckCollisionPointRec(mouse, enh_row_rect(gr, i)) {
			sys.copy_string_to_buffer(
				state.enhance_gem_id[:], &state.enhance_gem_id_len,
				sys.item_id_string(&inv.items[r]),
			)
			return
		}
	}

	wi := resolve_enh_weapon_index()
	gi := resolve_enh_gem_index()
	if enh_can_attempt(wi, gi) && rl.CheckCollisionPointRec(mouse, enh_enhance_btn_rect(m.rect)) {
		sys.send_weapon_enhance(state.net, wi, []int{gi})
	}
}

draw_blacksmith_menu :: proc() {
	m := &state.blacksmith_menu
	if !m.open do return
	win := m.rect
	mouse := rl.GetMousePosition()
	inv := &state.player.inventory

	rl.DrawRectangleRec(win, rl.Color{18, 20, 28, 242})
	rl.DrawRectangleLinesEx(win, 2, rl.Color{140, 140, 160, 255})
	title := rl.Rectangle{win.x, win.y, win.width, 30}
	rl.DrawRectangleRec(title, rl.Color{40, 44, 56, 250})
	sys.draw_text("Enhancement", int(win.x + 10), int(win.y + 6), 16, rl.Color{220, 220, 235, 255})

	cr := enh_close_rect(win)
	hov := rl.CheckCollisionPointRec(mouse, cr)
	rl.DrawRectangleRec(cr, hov ? rl.Color{180, 60, 60, 255} : rl.Color{100, 100, 110, 200})
	sys.draw_text("X", int(cr.x + 5), int(cr.y + 3), 12, rl.WHITE)

	wr := enh_weapon_list_rect(win)
	gr := enh_gem_list_rect(win)
	sys.draw_text("Equipment", int(wr.x), int(wr.y - ENH_HDR_H), 14, ENH_COL_GOLD)
	sys.draw_text("Element Gems", int(gr.x), int(gr.y - ENH_HDR_H), 14, ENH_COL_GOLD)

	sel_w := enhance_weapon_id_string()
	sel_g := enhance_gem_id_string()

	wrows := collect_enh_rows(false)
	max_rows := int(wr.height / f32(ENH_ROW_H))
	for r, i in wrows {
		if i >= max_rows do break
		it := &inv.items[r]
		id := sys.item_id_string(it)
		name := sys.item_name(id)
		if it.enhancement_level > 0 {
			elem := string(it.enhancement_element[:it.enhancement_elem_len])
			name = fmt.tprintf("%s +%d", name, it.enhancement_level)
			if len(elem) > 0 {
				name = fmt.tprintf("%s %s", name, enhance_element_display(elem))
			}
		}
		row := enh_row_rect(wr, i)
		if id == sel_w {
			rl.DrawRectangleRec(row, ENH_COL_SEL)
		} else if rl.CheckCollisionPointRec(mouse, row) {
			rl.DrawRectangleRec(row, ENH_COL_BTN_HOV)
		} else {
			rl.DrawRectangleRec(row, ENH_COL_BTN)
		}
		sys.draw_text(name, int(row.x + 6), int(row.y + 5), 14, rl.Color{220, 220, 235, 255})
	}
	if len(wrows) == 0 {
		sys.draw_text("No enhancable equipment.", int(wr.x + 4), int(wr.y + 4), 13, ENH_COL_DIM)
	}

	grows := collect_enh_rows(true)
	max_rows = int(gr.height / f32(ENH_ROW_H))
	for r, i in grows {
		if i >= max_rows do break
		it := &inv.items[r]
		id := sys.item_id_string(it)
		row := enh_row_rect(gr, i)
		if id == sel_g {
			rl.DrawRectangleRec(row, ENH_COL_SEL)
		} else if rl.CheckCollisionPointRec(mouse, row) {
			rl.DrawRectangleRec(row, ENH_COL_BTN_HOV)
		} else {
			rl.DrawRectangleRec(row, ENH_COL_BTN)
		}
		label := fmt.tprintf("%s x%d", sys.item_name(id), it.quantity)
		sys.draw_text(label, int(row.x + 6), int(row.y + 5), 14, rl.Color{220, 220, 235, 255})
		elem := enhance_gem_element(id)
		if len(elem) > 0 {
			ew := sys.measure_text(elem, 12)
			sys.draw_text(elem, int(row.x + row.width - f32(ew) - 6), int(row.y + 6), 12, ENH_COL_DIM)
		}
	}
	if len(grows) == 0 {
		sys.draw_text("No element gems in bag.", int(gr.x + 4), int(gr.y + 4), 13, ENH_COL_DIM)
	}

	// Bottom status panel.
	panel := rl.Rectangle{win.x + 10, win.y + win.height - 108, win.width - 20, 96}
	rl.DrawRectangleRec(panel, rl.Color{28, 30, 40, 255})
	rl.DrawRectangleLinesEx(panel, 1, rl.Color{80, 80, 100, 200})

	info_y := int(panel.y + 8)
	wi := resolve_enh_weapon_index()
	gi := resolve_enh_gem_index()

	line1 := "Select equipment to enhance."
	line1_col := ENH_COL_DIM
	if wi >= 0 {
		w := &inv.items[wi]
		elem := string(w.enhancement_element[:w.enhancement_elem_len])
		if w.enhancement_level >= 10 {
			line1 = fmt.tprintf(
				"%s +%d %s — maximum level",
				sys.item_name(sys.item_id_string(w)), w.enhancement_level, enhance_element_display(elem),
			)
			line1_col = ENH_COL_GOLD
		} else {
			fail := ENHANCE_FAIL_PCT[w.enhancement_level]
			line1 = fmt.tprintf(
				"%s +%d %s → +%d   success %d%%",
				sys.item_name(sys.item_id_string(w)), w.enhancement_level,
				len(elem) > 0 ? enhance_element_display(elem) : "—",
				w.enhancement_level + 1, 100 - fail,
			)
			line1_col = rl.Color{220, 220, 235, 255}
		}
	}
	sys.draw_text(line1, int(panel.x + 8), info_y, 14, line1_col)
	info_y += 20

	line2 := "Select an element gem."
	line2_col := ENH_COL_DIM
	if wi >= 0 && gi >= 0 {
		if enh_can_attempt(wi, gi) {
			line2 = fmt.tprintf("Gem: %s", sys.item_name(enhance_gem_id_string()))
			line2_col = ENH_COL_GREEN
		} else {
			w := &inv.items[wi]
			welem := string(w.enhancement_element[:w.enhancement_elem_len])
			if len(welem) > 0 {
				line2 = fmt.tprintf(
					"Element mismatch — this gear is %s.", enhance_element_display(welem),
				)
			} else {
				line2 = "This gem cannot be used."
			}
			line2_col = ENH_COL_RED
		}
	}
	sys.draw_text(line2, int(panel.x + 8), info_y, 14, line2_col)

	sys.draw_text("One gem is consumed per attempt,", int(panel.x + 8), info_y + 22, 12, ENH_COL_DIM)
	sys.draw_text("success or failure.", int(panel.x + 8), info_y + 36, 12, ENH_COL_DIM)

	btn := enh_enhance_btn_rect(win)
	enabled := enh_can_attempt(wi, gi)
	btn_col: rl.Color
	if !enabled {
		btn_col = rl.Color{45, 45, 55, 255}
	} else if rl.CheckCollisionPointRec(mouse, btn) {
		btn_col = ENH_COL_BTN_HOV
	} else {
		btn_col = rl.Color{60, 120, 70, 255}
	}
	rl.DrawRectangleRec(btn, btn_col)
	rl.DrawRectangleLinesEx(btn, 1, rl.Color{140, 140, 160, enabled ? 255 : 120})
	blabel := "Enhance"
	bw := sys.measure_text(blabel, 16)
	sys.draw_text(
		blabel,
		int(btn.x + (btn.width - f32(bw)) / 2),
		int(btn.y + (btn.height - 16) / 2),
		16,
		enabled ? rl.WHITE : ENH_COL_DIM,
	)
}

// ── shop menu ────────────────────────────────────────────────────────────

create_shop_menu :: proc() {
	m := &state.shop_menu
	m^ = ui.menu_create("Shop", 200, 120, 520, 500)
	m.close_on_esc = true
}

shop_active_cat_id :: proc() -> int {
	switch state.shop_cache.category {
	case .ALL:
		return SHOP_CAT_ALL_ID
	case .WEAPONS:
		return SHOP_CAT_WEAPONS_ID
	case .ARMOR:
		return SHOP_CAT_ARMOR_ID
	case .CONSUMABLES:
		return SHOP_CAT_CONSUMABLES_ID
	case .MATERIALS:
		return SHOP_CAT_MATERIALS_ID
	case .ACCESSORIES:
		return SHOP_CAT_ACCESSORIES_ID
	case:
		return SHOP_CAT_ALL_ID
	}
}

refresh_shop_menu :: proc() {
	m := &state.shop_menu
	ui.menu_clear(m)

	cat := state.shop_cache.category
	active_id := shop_active_cat_id()

	ui.menu_add_button_id(m, "All", SHOP_CAT_ALL_ID)
	ui.menu_add_button_id(m, "Weapons", SHOP_CAT_WEAPONS_ID)
	ui.menu_add_button_id(m, "Armor", SHOP_CAT_ARMOR_ID)
	ui.menu_add_button_id(m, "Consumables", SHOP_CAT_CONSUMABLES_ID)
	ui.menu_add_button_id(m, "Materials", SHOP_CAT_MATERIALS_ID)
	ui.menu_add_button_id(m, "Accessories", SHOP_CAT_ACCESSORIES_ID)

	for id in SHOP_CAT_ALL_ID ..= SHOP_CAT_ACCESSORIES_ID {
		btn := ui.menu_find(m, id)
		if btn != nil && btn.id == active_id do btn.active = true
	}

	ui.menu_add_separator(m)

	if !state.shop_cache.loaded {
		ui.menu_add_label(m, "No shop data loaded.")
		return
	}

	clear(&state.shop_visible_indices)
	vis := 0
	for i in 0 ..< len(state.shop_cache.entries) {
		e := &state.shop_cache.entries[i]
		if !sys.entry_matches_category(e, cat) do continue
		name := string(e.name[:e.name_len])
		label := fmt.tprintf("%-24s %dg", name, e.price)
		ui.menu_add_button_id(m, label, SHOP_ITEM_BASE_ID + vis)
		append(&state.shop_visible_indices, i)
		btn := ui.menu_find(m, SHOP_ITEM_BASE_ID + vis)
		if btn != nil do btn.label_color = sys.shop_rarity_color(e.rarity)
		vis += 1
	}

	ui.menu_add_separator(m)
	ui.menu_add_label(m, fmt.tprintf("Gold: %d", state.player.inventory.gold))
}

update_shop_menu :: proc() {
	m := &state.shop_menu
	if !m.open do return

	for id in SHOP_CAT_ALL_ID ..= SHOP_CAT_ACCESSORIES_ID {
		btn := ui.menu_find(m, id)
		if btn != nil && btn.clicked {
			switch id {
			case SHOP_CAT_ALL_ID:
				state.shop_cache.category = .ALL
			case SHOP_CAT_WEAPONS_ID:
				state.shop_cache.category = .WEAPONS
			case SHOP_CAT_ARMOR_ID:
				state.shop_cache.category = .ARMOR
			case SHOP_CAT_CONSUMABLES_ID:
				state.shop_cache.category = .CONSUMABLES
			case SHOP_CAT_MATERIALS_ID:
				state.shop_cache.category = .MATERIALS
			case SHOP_CAT_ACCESSORIES_ID:
				state.shop_cache.category = .ACCESSORIES
			case:
			}
			refresh_shop_menu()
			return
		}
	}

	for i in 0 ..< len(m.items) {
		item := &m.items[i]
		if item.id >= SHOP_ITEM_BASE_ID && item.clicked {
			vis_idx := item.id - SHOP_ITEM_BASE_ID
			if vis_idx < len(state.shop_visible_indices) {
				entry_idx := state.shop_visible_indices[vis_idx]
				e := &state.shop_cache.entries[entry_idx]
				sys.send_npc_shop_buy(state.net, string(e.id[:e.id_len]))
			}
		}
	}
}

// ── init / update / draw ────────────────────────────────────────────────

init_menus :: proc() {
	create_settings_menu()
	create_skills_menu()
	create_friends_menu()
	create_party_menu()
	create_quest_list_menu()
	create_shop_menu()

	state.blacksmith_menu = ui.menu_create("Enhancement", 0, 0, f32(ENH_WIN_W), f32(ENH_WIN_H))
	state.blacksmith_menu.close_on_esc = true

	state.inventory_menu = ui.menu_create("Inventory", 800, 100, 460, 400)
	state.inventory_menu.close_on_esc = true

	sys.shop_cache_init(&state.shop_cache)
	state.shop_visible_indices = make([dynamic]int)

	state.click_path = make([dynamic]rl.Vector3)
	state.quest_log_abandon_idx = -1

	state.system_menu = ui.menu_create("System", 0, 0, 240, 220)
	state.system_menu.close_on_esc = false
	state.system_menu.closable = false

	// Character sheet (stat + skill point allocation). Refresh-populated.
	state.character_profile_menu = ui.menu_create("Character", 820, 120, 360, 560)
	state.character_profile_menu.close_on_esc = true

	// Admin/debug overlay (toggled with F1, not on the bar). Sends GM chat
	// commands the server honors for accounts with the gm/admin role.
	state.debug_menu = ui.menu_create("Debug (F1)", 20, 120, 360, 520)
	state.debug_menu.close_on_esc = true

	state.bar_buttons = make([dynamic]Bar_Button)
	append(&state.bar_buttons, Bar_Button{"Inv", &state.inventory_menu})
	append(&state.bar_buttons, Bar_Button{"Chr", &state.character_profile_menu})
	append(&state.bar_buttons, Bar_Button{"Skl", &state.skills_menu})
	append(&state.bar_buttons, Bar_Button{"Set", &state.settings_menu})
	append(&state.bar_buttons, Bar_Button{"Frn", &state.friends_menu})
	append(&state.bar_buttons, Bar_Button{"Pty", &state.party_menu})
	append(&state.bar_buttons, Bar_Button{"Qst", &state.quest_list_menu})
}

update_menus :: proc() {
	mouse := rl.GetMousePosition()

	for i in 0 ..< len(state.bar_buttons) {
		entry := &state.bar_buttons[i]
		r := bar_btn_rect(i)
		if !state.chat_focused &&
		   rl.CheckCollisionPointRec(mouse, r) &&
		   rl.IsMouseButtonPressed(.LEFT) {
			ui.menu_toggle(entry.menu)
		}
	}

	if state.inventory_menu.open do refresh_inventory_menu()
	if state.shop_menu.open do refresh_shop_menu()
	if state.quest_list_menu.open do refresh_quest_list_menu()
	if state.skills_menu.open do refresh_skills_menu()
	if state.character_profile_menu.open do refresh_character_menu()
	if state.debug_menu.open do refresh_debug_menu()
	if state.settings_menu.open do refresh_settings_menu()
	update_shop_menu()
	update_party_panel()
	update_blacksmith_menu()

	ui.menu_update(&state.inventory_menu)
	ui.menu_update(&state.settings_menu)
	ui.menu_update(&state.skills_menu)
	ui.menu_update(&state.friends_menu)
	ui.menu_update(&state.quest_list_menu)
	ui.menu_update(&state.accept_deny_menu)
	ui.menu_update(&state.soul_extraction_menu)
	ui.menu_update(&state.character_profile_menu)
	ui.menu_update(&state.loot_drop_menu)
	ui.menu_update(&state.loot_party_menu)
	ui.menu_update(&state.shop_menu)
	ui.menu_update(&state.system_menu)
	ui.menu_update(&state.debug_menu)

	// Capture a pending rebind (no-ops when not listening). Only while Settings
	// is open; closing the window cancels any dangling rebind so it can't
	// silently grab the next keypress elsewhere.
	if state.settings_menu.open {
		sys.poll_rebind()
	} else if sys.rebind_listening {
		sys.cancel_rebind()
	}

	// Action menus: read clicks AFTER menu_update sets them this frame.
	handle_system_menu_clicks()
	handle_inventory_menu_clicks()
	handle_character_menu_clicks()
	handle_debug_menu_clicks()
	handle_settings_menu_clicks()
	handle_skills_menu_clicks()
	handle_quest_list_menu_clicks()
}

draw_menu_bar :: proc() {
	mouse := rl.GetMousePosition()
	bar_w := f32(len(state.bar_buttons) * (BAR_BTN_SIZE + BAR_BTN_GAP) - BAR_BTN_GAP)
	rl.DrawRectangleRec(
		{f32(BAR_X) - 4, f32(menu_bar_y()) - 4, bar_w + 8, BAR_BTN_SIZE + 8},
		rl.Color{15, 16, 20, 200},
	)

	for i in 0 ..< len(state.bar_buttons) {
		entry := &state.bar_buttons[i]
		r := bar_btn_rect(i)
		hov := rl.CheckCollisionPointRec(mouse, r)
		active := entry.menu.open

		col := rl.Color{55, 60, 75, 230}
		if hov do col = rl.Color{75, 85, 115, 230}
		if active do col = rl.Color{70, 130, 210, 230}

		rl.DrawRectangleRec(r, col)
		rl.DrawRectangleLinesEx(r, 2, rl.Color{140, 140, 160, 255})

		tw := sys.measure_text(entry.label, 16)
		tx := int(r.x) + (BAR_BTN_SIZE - tw) / 2
		ty := menu_bar_y() + (BAR_BTN_SIZE - 16) / 2
		sys.draw_text(entry.label, tx, int(ty), 16, rl.Color{220, 220, 235, 255})
	}
}

	draw_menus :: proc() {
	ui.menu_draw(&state.inventory_menu)
	ui.menu_draw(&state.settings_menu)
	ui.menu_draw(&state.skills_menu)
	ui.menu_draw(&state.friends_menu)
	draw_party_panel()
	ui.menu_draw(&state.quest_list_menu)
	ui.menu_draw(&state.accept_deny_menu)
	draw_blacksmith_menu()
	ui.menu_draw(&state.soul_extraction_menu)
	ui.menu_draw(&state.character_profile_menu)
	ui.menu_draw(&state.loot_drop_menu)
	ui.menu_draw(&state.loot_party_menu)
	ui.menu_draw(&state.debug_menu)
	draw_system_menu()
}

draw_system_menu :: proc() {
	m := &state.system_menu
	if !m.open do return

	// Centered on the window (like Pandora Saga and most MMOs).
	refresh_system_menu()
	ui.menu_auto_height(m, 1000)
	m.rect.x = f32(rl.GetScreenWidth())/2.0 - m.rect.width/2.0
	m.rect.y = f32(rl.GetScreenHeight())/2.0 - m.rect.height/2.0

	ui.menu_draw(m)
}

refresh_system_menu :: proc() {
	m := &state.system_menu
	ui.menu_clear(m)

	now := state.clock_ms
	btns := [4]string{"System Settings", "Character Settings", "Logout", "Exit Game"}
	ids := [4]int{0, 1, 2, 3}

	for i in 0 ..< 4 {
		label := btns[i]
		// While a logout/exit countdown is active, show the remaining seconds.
		// The actual handoff fires in gameplay.update when the timer elapses;
		// clicking the entry again cancels it (handle_system_menu_clicks).
		if i == 2 && state.logout_start_ms > 0 {
			remaining := 30.0 - f64(now - state.logout_start_ms) / 1000.0
			if remaining > 0 do label = fmt.tprintf("Logout (%.0fs) — click to cancel", remaining)
		}
		if i == 3 && state.exit_start_ms > 0 {
			remaining := 30.0 - f64(now - state.exit_start_ms) / 1000.0
			if remaining > 0 do label = fmt.tprintf("Exit (%.0fs) — click to cancel", remaining)
		}
		ui.menu_add_button_id(m, label, ids[i])
	}
}

handle_system_menu_clicks :: proc() {
	m := &state.system_menu
	if !m.open do return

	for i in 0 ..< len(m.items) {
		item := &m.items[i]
		if item.kind == .BUTTON && item.clicked {
			switch item.id {
			case 0: // System Settings
				ui.menu_close(m)
				ui.menu_toggle(&state.settings_menu)
			case 1: // Character Settings (placeholder)
				ui.menu_close(m)
			case 2: // Logout — toggle the 30s countdown
				state.logout_start_ms = state.logout_start_ms > 0 ? 0 : state.clock_ms
			case 3: // Exit Game — toggle the 30s countdown
				state.exit_start_ms = state.exit_start_ms > 0 ? 0 : state.clock_ms
			case:
			}
			return
		}
	}
}

// ── skills + character (allocation) menus ─────────────────────────────────
// Button-id bases so handle_character_menu_clicks can tell a stat button from
// a skill-sub-category button. stat: 1000+attr (0..5), skill: 2000+subcat.
STAT_BTN_BASE  :: 1000
SKILL_BTN_BASE :: 2000

// Skills browser + bar-assigner. Each skill is a button: click toggles it onto
// the next free skill-bar slot (or off if already assigned). Lists the job's
// class-kit skills (level-gated) and the skill trees it can invest in (with
// current proficiency / cap and each skill's requirement).
SKILL_ASSIGN_BASE :: 5000 // button id = base + int(skill_id)

refresh_skills_menu :: proc() {
	m := &state.skills_menu
	p := state.player
	ui.menu_clear(m)
	if p.job_id == sys.INVALID_JOB_ID {
		ui.menu_add_label(m, "No job loaded.")
		return
	}
	job := sys.registry_get(&sys.job_registry, p.job_id)
	has_weapon := p.inventory.equipment[0].item_id_len > 0
	ui.menu_add_label(m, fmt.tprintf("Skill Points: %d", p.unspent_skill_points))
	ui.menu_add_label(m, fmt.tprintf("Job: %s   (click a skill to assign/clear)", job.name))
	ui.menu_add_separator(m)

	ui.menu_add_label(m, "-- Class Skills --")
	for i in 0 ..< len(job.kit_skill_ids) {
		sid := job.kit_skill_ids[i]
		sk := sys.registry_get(&sys.skill_registry, sid)
		name := sys.registry_name(&sys.skill_registry, sid)
		lvl := sys.skill_req_level(sk)
		can_assign := sk.kind != .PASSIVE && sys.skill_req_met(sk, p)
		if sk.requires.weapon_count > 0 && !has_weapon do can_assign = false
		tag := can_assign ? "OK" : (sk.kind == .PASSIVE ? "passive" : fmt.tprintf("Lv%d", lvl))
		if sk.requires.weapon_count > 0 && !has_weapon do tag = "no wpn"
		if can_assign {
			ui.menu_add_button_id(m, fmt.tprintf("[%s] %-18s %s", tag, name, bar_badge(p, name)), SKILL_ASSIGN_BASE + int(sid))
		} else {
			ui.menu_add_label(m, fmt.tprintf("[%s] %s", tag, name))
		}
	}
	ui.menu_add_separator(m)

	ui.menu_add_label(m, "-- Skill Trees --")
	for sc in sys.Sub_Category {
		prof := job.proficiency[sc]
		if prof.max_potential == 0 do continue
		adepts := p.skill_adeptness[sc]
		alloc := p.allocated_skill_points[sc]
		ui.menu_add_label(
			m,
			fmt.tprintf("%s: prof %.1f / pts %d / max %d", sys.sub_category_name(sc), adepts, alloc, prof.max_potential),
		)
		for j in 0 ..< len(sys.tree_skills[sc]) {
			sid := sys.tree_skills[sc][j]
			sk := sys.registry_get(&sys.skill_registry, sid)
			name := sys.registry_name(&sys.skill_registry, sid)
			pts := sys.skill_req_points(sk)
			can_assign := sk.kind != .PASSIVE && sys.skill_req_met(sk, p)
			if sk.requires.weapon_count > 0 && !has_weapon do can_assign = false
			tag := can_assign ? "OK" : (sk.kind == .PASSIVE ? "passive" : (pts > 0 ? fmt.tprintf("%d", pts) : "x"))
			if sk.requires.weapon_count > 0 && !has_weapon do tag = "no wpn"
			if can_assign {
				ui.menu_add_button_id(m, fmt.tprintf("   [%s] %-18s %s", tag, name, bar_badge(p, name)), SKILL_ASSIGN_BASE + int(sid))
			} else {
				ui.menu_add_label(m, fmt.tprintf("   [%s] %s", tag, name))
			}
		}
	}
	ui.menu_add_separator(m)

	ui.menu_add_label(m, "-- Skill Trees --")
	for sc in sys.Sub_Category {
		prof := job.proficiency[sc]
		if prof.max_potential == 0 do continue
		adepts := p.skill_adeptness[sc]        // use-grown proficiency
		alloc := p.allocated_skill_points[sc]  // spent skill points (the cap)
		ui.menu_add_label(
			m,
			fmt.tprintf("%s: prof %.1f / pts %d / max %d", sys.sub_category_name(sc), adepts, alloc, prof.max_potential),
		)
		for j in 0 ..< len(sys.tree_skills[sc]) {
			sid := sys.tree_skills[sc][j]
			sk := sys.registry_get(&sys.skill_registry, sid)
			name := sys.registry_name(&sys.skill_registry, sid)
			pts := sys.skill_req_points(sk)
			tag := sys.skill_req_met(sk, p) ? "OK" : (pts > 0 ? fmt.tprintf("%d", pts) : "x")
			if sk.requires.weapon_count > 0 && !has_weapon do tag = "no wpn"
			ui.menu_add_button_id(m, fmt.tprintf("   [%s] %-18s %s", tag, name, bar_badge(p, name)), SKILL_ASSIGN_BASE + int(sid))
		}
	}
	ui.menu_auto_height(m, 560)
}

// "<bar N slot M>" if the skill is on a hotbar, else empty.
bar_badge :: proc(p: ^sys.Local_Player, name: string) -> string {
	bar, slot := sys.skill_bar_find(p, name)
	if bar < 0 do return ""
	return fmt.tprintf("<%d-%d>", bar + 1, slot + 1)
}

// Handle skill-window clicks → toggle the skill on/off the bar + persist.
handle_skills_menu_clicks :: proc() {
	m := &state.skills_menu
	if !m.open do return
	p := state.player
	for i in 0 ..< len(m.items) {
		item := &m.items[i]
		if item.kind != .BUTTON || !item.clicked do continue
		idx := item.id - SKILL_ASSIGN_BASE
		if idx < 0 || idx >= sys.registry_count(&sys.skill_registry) do continue
		name := sys.registry_name(&sys.skill_registry, sys.Skill_Id(u16(idx)))
		_ , _ , _ = sys.skill_bar_toggle(p, name)
		sys.save_skill_bar(p)
	}
}

// Character sheet: spend stat points into the 6 attributes and skill points
// into the job's available sub-categories. Buttons send the allocation packet;
// the server's STATS_UPDATE reconciles unspent points + derived stats.
refresh_character_menu :: proc() {
	m := &state.character_profile_menu
	p := state.player
	ui.menu_clear(m)

	ui.menu_add_label(m, fmt.tprintf("Stat Points: %d", p.unspent_stat_points))
	for a in sys.Attr {
		total := sys.attr_total(p, a)
		cost := sys.attr_next_cost(p, a)
		affordable := p.unspent_stat_points >= cost && total < 99
		mark := affordable ? fmt.tprintf(" [+%d]", cost) : fmt.tprintf("  (%d)", cost)
		ui.menu_add_button_id(
			m,
			fmt.tprintf("%-4s %3d  tot %d%s", sys.attr_name(a), p.allocated_stats[a], total, mark),
			STAT_BTN_BASE + int(a),
		)
	}
	ui.menu_add_separator(m)

	ui.menu_add_label(m, fmt.tprintf("Skill Points: %d", p.unspent_skill_points))
	if p.job_id != sys.INVALID_JOB_ID {
		job := sys.registry_get(&sys.job_registry, p.job_id)
		for sc in sys.Sub_Category {
			prof := job.proficiency[sc]
			if prof.max_potential == 0 do continue
			adepts := p.skill_adeptness[sc]        // proficiency (grows via use)
			alloc := p.allocated_skill_points[sc]  // spent points — the cap [+ raises]
			can := p.unspent_skill_points > 0 && alloc < i32(prof.max_potential)
			mark := can ? "  [+]" : ""
			ui.menu_add_button_id(
				m,
				fmt.tprintf("%-12s %.0f/%d/%d%s", sys.sub_category_name(sc), adepts, alloc, prof.max_potential, mark),
				SKILL_BTN_BASE + int(sc),
			)
		}
	}
	ui.menu_add_separator(m)
	s := &p.stats
	ui.menu_add_label(
		m,
		fmt.tprintf("Lv %d   HP %.0f/%.0f   MP %.0f/%.0f", s.level, s.health, s.max_health, s.mana, s.max_mana),
	)
	ui.menu_add_label(m, fmt.tprintf("ATK %.0f  DEF %.0f  MATK %.0f", s.attack, s.defense, s.magic_attack))
	ui.menu_add_label(m, fmt.tprintf("SPD %.0f  Crit %.0f%%", s.speed, s.crit_chance))
	ui.menu_auto_height(m, 600)
}

// Read clicks from the character menu's buttons (must run AFTER menu_update).
handle_character_menu_clicks :: proc() {
	m := &state.character_profile_menu
	if !m.open do return
	p := state.player
	for i in 0 ..< len(m.items) {
		item := &m.items[i]
		if item.kind != .BUTTON || !item.clicked do continue
		if item.id >= STAT_BTN_BASE && item.id < STAT_BTN_BASE + sys.ATTR_COUNT {
			a := sys.Attr(item.id - STAT_BTN_BASE)
			// Gate on the server's exact rule: enough unspent points for the
			// escalating cost, and total (base + allocated) below the 99 cap.
			cost := sys.attr_next_cost(p, a)
			if p.unspent_stat_points >= cost && sys.attr_total(p, a) < 99 {
				sys.send_stat_allocate(state.net, sys.attr_name(a))
			}
		} else if item.id >= SKILL_BTN_BASE && item.id < SKILL_BTN_BASE + sys.SUB_CATEGORY_COUNT {
			sys.send_skill_allocate(state.net, sys.sub_category_name(sys.Sub_Category(item.id - SKILL_BTN_BASE)))
		}
	}
}

// ── debug / admin window (F1) ──────────────────────────────────────────────
// Sends GM chat commands (server honors them for gm/admin-role accounts) and
// shows live diagnostics. Add commands here as needed — the server's full set
// lives in src/server/.../chatHandlers.ts handleChatCommand.
Debug_Cmd :: struct { label, cmd: string }

DEBUG_COMMANDS: []Debug_Cmd = {
	{"Level Up", "/levelup"},
	{"Set Lv 10", "/setlevel 10"},
	{"Set Lv 20", "/setlevel 20"},
	{"Set Lv 30", "/setlevel 30"},
	{"Set Lv 40", "/setlevel 40"},
	{"Set Lv 50", "/setlevel 50"},
	{"Reset Stats", "/resetstats"},
	{"Reset Skills", "/resetskills"},
	{"Advance (see chat)", "/advance"},
	{"Spawn Dummy", "/spawn_dummy"},
	{"Kill All Enemies", "/killallenemies"},
	{"Dummy List", "/dummy_list"},
	{"Give Wooden Sword", "/giveitem wooden_sword 1"},
	{"Give Wooden Bow", "/giveitem wooden_bow 1"},
	{"Give Rusty Dagger", "/giveitem rusty_dagger 1"},
	{"Give Basic Staff", "/giveitem basic_staff 1"},
	{"Give Leather Armor", "/giveitem leather_armor 1"},
	{"Give Health Potion", "/giveitem health_potion 5"},
	{"List Item IDs (chat)", "/giveitem ?"},
}

DEBUG_CMD_BASE :: 3000

refresh_debug_menu :: proc() {
	m := &state.debug_menu
	p := state.player
	ui.menu_clear(m)

	// diagnostics
	ui.menu_add_label(m, fmt.tprintf("FPS %d   Entities %d", rl.GetFPS(), state.scene.count))
	zone := string(p.zone_id_buf[:p.zone_id_len])
	ui.menu_add_label(
		m,
		fmt.tprintf("Pos (%.1f, %.1f, %.1f)  Zone %s", p.position.x, p.position.y, p.position.z, zone),
	)
	job_name := "—"
	if p.job_id != sys.INVALID_JOB_ID do job_name = sys.registry_get(&sys.job_registry, p.job_id).name
	race_name := "—"
	if p.race != sys.INVALID_RACE_ID do race_name = sys.registry_get(&sys.race_registry, p.race).name
	ui.menu_add_label(m, fmt.tprintf("Job %s   Race %s   Lv %d", job_name, race_name, p.stats.level))
	tgt := p.target_id != sys.INVALID_ENTITY ? fmt.tprintf("%d", u32(p.target_id)) : "none"
	ui.menu_add_label(m, fmt.tprintf("Target %s", tgt))
	conn := "—"
	switch state.net.state {
	case .DISCONNECTED: conn = "DISCONNECTED"
	case .CONNECTING:   conn = "CONNECTING"
	case .OPEN:         conn = "OPEN"
	case .FAILED:       conn = "FAILED"
	}
	ui.menu_add_label(m, fmt.tprintf("Conn %s   reconnects %d", conn, state.net.reconnect_attempts))
	ui.menu_add_separator(m)

	// GM command buttons
	ui.menu_add_label(m, "— GM commands —")
	for i in 0 ..< len(DEBUG_COMMANDS) {
		ui.menu_add_button_id(m, DEBUG_COMMANDS[i].label, DEBUG_CMD_BASE + int(i))
	}
	ui.menu_auto_height(m, 560)
}

handle_debug_menu_clicks :: proc() {
	m := &state.debug_menu
	if !m.open do return
	for i in 0 ..< len(m.items) {
		item := &m.items[i]
		if item.kind != .BUTTON || !item.clicked do continue
		idx := item.id - DEBUG_CMD_BASE
		if idx >= 0 && idx < len(DEBUG_COMMANDS) {
			sys.send_chat(state.net, DEBUG_COMMANDS[idx].cmd)
		}
	}
}

// ── settings / keybind rebind ──────────────────────────────────────────────
// Each action is a button "Action Name  KEY". Click → start_rebind → the next
// key pressed (captured by sys.poll_rebind, called above) becomes the binding
// and persists to keybinds.json. Esc cancels.
SETTINGS_ACTION_BASE :: 4000
SETTINGS_RESET_ID     :: 4999

refresh_settings_menu :: proc() {
	m := &state.settings_menu
	ui.menu_clear(m)
	ui.menu_add_label(m, "Click a binding, then press a key. (Esc cancels.)")
	ui.menu_add_separator(m)
	for a in sys.Action {
		key_str := sys.key_name(sys.keybinds.keys[a])
		if sys.rebind_listening && sys.rebind_target == a do key_str = "... press a key"
		ui.menu_add_button_id(
			m,
			fmt.tprintf("%-16s %s", sys.action_name(a), key_str),
			SETTINGS_ACTION_BASE + int(a),
		)
	}
	ui.menu_add_separator(m)
	ui.menu_add_button_id(m, "Reset to Defaults", SETTINGS_RESET_ID)
	ui.menu_auto_height(m, 600)
}

handle_settings_menu_clicks :: proc() {
	m := &state.settings_menu
	if !m.open do return
	for i in 0 ..< len(m.items) {
		item := &m.items[i]
		if item.kind != .BUTTON || !item.clicked do continue
		if item.id == SETTINGS_RESET_ID {
			sys.keybinds = sys.keybind_defaults()
			sys.save_keybinds()
			sys.cancel_rebind()
			continue
		}
		idx := item.id - SETTINGS_ACTION_BASE
		if idx >= 0 && idx < sys.ACTION_COUNT {
			sys.start_rebind(sys.Action(idx))
		}
	}
}
