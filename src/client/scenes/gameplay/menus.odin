package gameplay

import sys "../../systems"
import ui "../../ui/"
import "core:fmt"
import "core:math"
import rl "vendor:raylib"

BAR_BTN_SIZE :: 36
BAR_BTN_GAP :: 4
BAR_Y :: 70
BAR_X :: 20

SHOP_CAT_ALL_ID :: 1
SHOP_CAT_WEAPONS_ID :: 2
SHOP_CAT_ARMOR_ID :: 3
SHOP_CAT_CONSUMABLES_ID :: 4
SHOP_CAT_MATERIALS_ID :: 5
SHOP_CAT_ACCESSORIES_ID :: 6
SHOP_ITEM_BASE_ID :: 100

bar_btn_rect :: proc(idx: int) -> rl.Rectangle {
	x := f32(BAR_X + idx * (BAR_BTN_SIZE + BAR_BTN_GAP))
	return {x, BAR_Y, BAR_BTN_SIZE, BAR_BTN_SIZE}
}

// ── create procs ──────────────────────────────────────────────────────────

create_settings_menu :: proc() {
	m := &state.settings_menu
	m^ = ui.menu_create("Settings", 300, 200, 400, 400)
	ui.menu_add_label(m, "Display")
	ui.menu_add_slider(m, "Master Volume", 0.8, 0.0, 1.0, 0.05)
	ui.menu_add_slider(m, "Music Volume", 0.5, 0.0, 1.0, 0.05)
	ui.menu_add_toggle(m, "Fullscreen", true)
	ui.menu_add_toggle(m, "Show FPS", false)
	ui.menu_add_separator(m)
	ui.menu_add_label(m, "Controls")
	ui.menu_add_button(m, "Key Bindings")
	ui.menu_add_separator(m)
	ui.menu_add_button(m, "Apply")
	ui.menu_add_button(m, "Close")
}

create_skills_menu :: proc() {
	m := &state.skills_menu
	m^ = ui.menu_create("Skills", 350, 200, 400, 400)
	ui.menu_add_label(m, "Skill Points: 5")
	ui.menu_add_separator(m)
	ui.menu_add_button(m, "Fireball      3/5")
	ui.menu_add_button(m, "Ice Shard     1/5")
	ui.menu_add_button(m, "Heal         2/5")
	ui.menu_add_button(m, "Shield       0/5")
	ui.menu_add_button(m, "Dash         4/5")
	ui.menu_add_separator(m)
	ui.menu_add_button(m, "Reset Skills")
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
	m := &state.party_menu
	m^ = ui.menu_create("Party", 300, 250, 350, 300)
	ui.menu_add_label(m, "Members: 1/4")
	ui.menu_add_separator(m)
	ui.menu_add_button(m, "Invite Player")
	ui.menu_add_button(m, "Leave Party")
}

create_quest_list_menu :: proc() {
	m := &state.quest_list_menu
	m^ = ui.menu_create("Quests", 400, 150, 400, 450)
	ui.menu_add_label(m, "Active Quests")
	ui.menu_add_separator(m)
	ui.menu_add_button(m, "The Lost Sword  (0/3)")
	ui.menu_add_button(m, "Gather Herbs   (5/10)")
}

refresh_inventory_menu :: proc() {
	m := &state.inventory_menu
	ui.menu_clear(m)
	ui.menu_add_label(m, fmt.tprintf("Gold: %d", state.player.inventory.gold))
	ui.menu_add_separator(m)
	for i in 0 ..< len(state.player.inventory.items) {
		it := &state.player.inventory.items[i]
		row := fmt.tprintf("%d. %s x%d", i + 1, sys.item_id_string(it), it.quantity)
		ui.menu_add_button(m, row)
	}
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
				name := string(e.name[:e.name_len])
				sys.net_log(fmt.tprintf("Buy: %s for %dg", name, e.price))
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

	state.inventory_menu = ui.menu_create("Inventory", 800, 100, 460, 400)
	state.inventory_menu.close_on_esc = true

	sys.shop_cache_init(&state.shop_cache)
	state.shop_visible_indices = make([dynamic]int)

	state.click_path = make([dynamic]rl.Vector3)

	state.system_menu = ui.menu_create("System", 0, 0, 240, 220)
	state.system_menu.close_on_esc = true
	state.system_menu.closable = false

	state.bar_buttons = make([dynamic]Bar_Button)
	append(&state.bar_buttons, Bar_Button{"Inv", &state.inventory_menu})
	append(&state.bar_buttons, Bar_Button{"Set", &state.settings_menu})
	append(&state.bar_buttons, Bar_Button{"Skl", &state.skills_menu})
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
	update_shop_menu()

	ui.menu_update(&state.inventory_menu)
	ui.menu_update(&state.settings_menu)
	ui.menu_update(&state.skills_menu)
	ui.menu_update(&state.friends_menu)
	ui.menu_update(&state.party_menu)
	ui.menu_update(&state.quest_list_menu)
	ui.menu_update(&state.accept_deny_menu)
	ui.menu_update(&state.blacksmith_menu)
	ui.menu_update(&state.soul_extraction_menu)
	ui.menu_update(&state.character_profile_menu)
	ui.menu_update(&state.loot_drop_menu)
	ui.menu_update(&state.loot_party_menu)
	ui.menu_update(&state.shop_menu)
	ui.menu_update(&state.system_menu)
}

draw_menu_bar :: proc() {
	mouse := rl.GetMousePosition()
	bar_w := f32(len(state.bar_buttons) * (BAR_BTN_SIZE + BAR_BTN_GAP) - BAR_BTN_GAP)
	rl.DrawRectangleRec(
		{f32(BAR_X) - 4, BAR_Y - 4, bar_w + 8, BAR_BTN_SIZE + 8},
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
		ty := BAR_Y + (BAR_BTN_SIZE - 16) / 2
		sys.draw_text(entry.label, tx, ty, 16, rl.Color{220, 220, 235, 255})
	}
}

	draw_menus :: proc() {
	ui.menu_draw(&state.inventory_menu)
	ui.menu_draw(&state.settings_menu)
	ui.menu_draw(&state.skills_menu)
	ui.menu_draw(&state.friends_menu)
	ui.menu_draw(&state.party_menu)
	ui.menu_draw(&state.quest_list_menu)
	ui.menu_draw(&state.accept_deny_menu)
	ui.menu_draw(&state.blacksmith_menu)
	ui.menu_draw(&state.soul_extraction_menu)
	ui.menu_draw(&state.character_profile_menu)
	ui.menu_draw(&state.loot_drop_menu)
	ui.menu_draw(&state.loot_party_menu)
	draw_system_menu()
}

draw_system_menu :: proc() {
	m := &state.system_menu
	if !m.open do return

	screen_w := rl.GetScreenWidth()
	m.rect.x = f32(screen_w) / 2.0 - m.rect.width / 2.0
	m.rect.y = 200.0

	refresh_system_menu()
	ui.menu_update(m)
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
		if i == 2 && state.logout_start_ms > 0 {
			elapsed := f64(now - state.logout_start_ms)
			remaining := 30.0 - elapsed / 1000.0
			if remaining > 0 {
				label = fmt.tprintf("Logout (%.0fs)", remaining)
			} else {
			ui.menu_add_button_id(m, label, ids[i])
			state.logout_start_ms = 0
			continue
			}
		}
		if i == 3 && state.exit_start_ms > 0 {
			elapsed := f64(now - state.exit_start_ms)
			remaining := 30.0 - elapsed / 1000.0
			if remaining > 0 {
				label = fmt.tprintf("Exit (%.0fs)", remaining)
			} else {
			ui.menu_add_button_id(m, label, ids[i])
			state.exit_start_ms = 0
			continue
			}
		}
		ui.menu_add_button_id(m, label, ids[i])
	}
}

handle_system_menu_clicks :: proc(inp: sys.Input_State) {
	m := &state.system_menu
	if !m.open do return
	if !inp.mouse_left_pressed do return
	if !m.focused do return

	for i in 0 ..< len(m.items) {
		item := &m.items[i]
		if item.kind == .BUTTON && item.clicked {
			if item.id == 0 {
				// System Settings — just close system menu and open settings
				ui.menu_close(m)
				ui.menu_toggle(&state.settings_menu)
			} else if item.id == 1 {
				// Character Settings — placeholder, just close
				ui.menu_close(m)
			} else if item.id == 2 {
				// Logout
				if state.logout_start_ms > 0 {
					state.logout_start_ms = 0
				} else {
					state.logout_start_ms = state.clock_ms
				}
			} else if item.id == 3 {
				// Exit Game
				if state.exit_start_ms > 0 {
					state.exit_start_ms = 0
				} else {
					state.exit_start_ms = state.clock_ms
				}
			}
			return
		}
	}
}
