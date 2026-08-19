package gameplay

import sys "../../systems"
import ui "../../ui"
import "core:fmt"
import rl "vendor:raylib"

// NPC conversation window (Pandora Saga style): bottom-center panel with the
// NPC's name, the current dialog page text (a blurb, a quest offer, or an
// active-quest progress report), and a button stack. All state lives in
// ctx.dialog (filled by the NPC_DIALOG packet handler); buttons are rebuilt
// every frame from that state.

DIALOG_W       :: 640
DIALOG_PAD     :: 12.0
DIALOG_TITLE_H :: 30.0
DIALOG_OPT_H   :: 30.0
DIALOG_OPT_GAP :: 6.0
DIALOG_TEXT_FZ :: 16
DIALOG_LINE_H  :: 20

DIALOG_COL_BG      :: rl.Color{18, 20, 28, 242}
DIALOG_COL_BORDER  :: rl.Color{140, 140, 160, 255}
DIALOG_COL_TITLEBG :: rl.Color{40, 44, 56, 250}
DIALOG_COL_BTN     :: rl.Color{55, 60, 75, 255}
DIALOG_COL_BTN_HOV :: rl.Color{75, 85, 115, 255}
DIALOG_COL_GOLD    :: rl.Color{255, 210, 90, 255}
DIALOG_COL_GREEN   :: rl.Color{120, 230, 120, 255}
DIALOG_COL_RED     :: rl.Color{235, 100, 100, 255}
DIALOG_COL_TEXT    :: rl.Color{225, 225, 230, 255}
DIALOG_COL_DIM     :: rl.Color{170, 170, 180, 255}

Dialog_Btn_Kind :: enum u8 {
	NEXT_PAGE,
	CLOSE,
	SHOW_OFFER,
	SHOW_ACTIVE,
	ACCEPT,
	TURN_IN,
	ABANDON,
	BACK,
	OPEN_SHOP,
	OPEN_ENHANCEMENT,
}

Dialog_Btn :: struct {
	kind:    Dialog_Btn_Kind,
	label:   string,
	index:   int,
	next_id: string,
	quest_id: string,
}

dialog_text_width :: proc "contextless" () -> f32 {
	return f32(DIALOG_W) - 2 * DIALOG_PAD
}

wrap_lines :: proc(text: string, max_w: f32, fz: int) -> []string {
	// Per-frame transient (rebuilt every frame by update/draw): allocate on
	// the temp allocator so it's reclaimed with the frame arena.
	lines := make([dynamic]string, context.temp_allocator)
	line := ""
	i := 0
	for i <= len(text) {
		j := i
		for j < len(text) && text[j] != ' ' do j += 1
		word := text[i:j]
		if len(line) == 0 {
			line = word
		} else {
			cand := fmt.tprintf("%s %s", line, word)
			if f32(sys.measure_text(cand, fz)) > max_w {
				append(&lines, line)
				line = word
			} else {
				line = cand
			}
		}
		if j >= len(text) do break
		i = j + 1
	}
	append(&lines, line)
	return lines[:]
}

dialog_selected_offer :: proc(d: ^sys.Dialog_State) -> ^sys.Dialog_Offer {
	if d.offer_count == 0 do return nil
	idx := clamp(d.selected_offer, 0, d.offer_count - 1)
	return &d.offers[idx]
}

dialog_selected_active :: proc(d: ^sys.Dialog_State) -> ^sys.Dialog_Active {
	if d.active_count == 0 do return nil
	idx := clamp(d.selected_active, 0, d.active_count - 1)
	return &d.actives[idx]
}

dialog_body_lines :: proc(d: ^sys.Dialog_State) -> int {
	switch d.mode {
	case .NPC_PAGE:
		return len(wrap_lines(sys.dialog_page_text_string(d), dialog_text_width(), DIALOG_TEXT_FZ))
	case .QUEST_OFFER:
		of := dialog_selected_offer(d)
		if of == nil do return 1
		lines := 1
		lines += len(wrap_lines(sys.dialog_offer_text_string(of), dialog_text_width(), DIALOG_TEXT_FZ))
		lines += 1
		if of.required_level > state.player.stats.level do lines += 1
		return lines
	case .QUEST_ACTIVE:
		aq := dialog_selected_active(d)
		if aq == nil do return 1
		lines := 1 + aq.objective_count
		lines += len(wrap_lines(sys.dialog_active_text_string(aq), dialog_text_width(), DIALOG_TEXT_FZ))
		return lines
	}
	return 1
}

// Rebuild the visible button list from the dialog state (pure — used by both
// update and draw so hit-testing and rendering always agree).
build_dialog_buttons :: proc(d: ^sys.Dialog_State) -> []Dialog_Btn {
	// Per-frame transient (see wrap_lines): frame-arena backed, freed at
	// frame end; labels are tprintf results on the same arena.
	btns := make([dynamic]Dialog_Btn, context.temp_allocator)
	switch d.mode {
	case .NPC_PAGE:
		for i in 0 ..< d.page_option_count {
			po := &d.page_options[i]
			label := sys.dialog_option_label_string(po)
			action := sys.dialog_option_action_string(po)
			if po.has_next {
				append(&btns, Dialog_Btn{kind = .NEXT_PAGE, label = label, next_id = sys.dialog_option_next_string(po)})
			} else if action == "accept_quest" && po.quest_id_len > 0 {
				append(&btns, Dialog_Btn{kind = .ACCEPT, label = label, quest_id = sys.dialog_option_quest_string(po)})
			} else if action == "open_shop" {
				append(&btns, Dialog_Btn{kind = .OPEN_SHOP, label = label})
			} else if action == "open_enhancement" {
				append(&btns, Dialog_Btn{kind = .OPEN_ENHANCEMENT, label = label})
			} else {
				append(&btns, Dialog_Btn{kind = .CLOSE, label = label})
			}
		}
		for i in 0 ..< d.offer_count {
			of := &d.offers[i]
			append(
				&btns,
				Dialog_Btn{kind = .SHOW_OFFER, label = fmt.tprintf("[!] %s", sys.dialog_offer_title_string(of)), index = i},
			)
		}
		for i in 0 ..< d.active_count {
			aq := &d.actives[i]
			mark := aq.turn_in_ready ? "[?]" : "[ ]"
			progress := ""
			for j in 0 ..< aq.objective_count {
				vo := &aq.objectives[j]
				if vo.current < vo.required {
					progress = fmt.tprintf(" (%d/%d)", vo.current, vo.required)
					break
				}
			}
			append(
				&btns,
				Dialog_Btn{
					kind  = .SHOW_ACTIVE,
					label = fmt.tprintf("%s %s%s", mark, sys.dialog_active_title_string(aq), progress),
					index = i,
				},
			)
		}
	case .QUEST_OFFER:
		of := dialog_selected_offer(d)
		if of != nil {
			append(&btns, Dialog_Btn{kind = .ACCEPT, label = "Accept Quest", quest_id = sys.dialog_offer_id_string(of)})
			append(&btns, Dialog_Btn{kind = .BACK, label = "Decline"})
		}
	case .QUEST_ACTIVE:
		aq := dialog_selected_active(d)
		if aq != nil {
			if aq.turn_in_ready {
				append(&btns, Dialog_Btn{kind = .TURN_IN, label = "Turn In", quest_id = sys.dialog_active_id_string(aq)})
			}
			append(&btns, Dialog_Btn{kind = .BACK, label = "Back"})
			append(
				&btns,
				Dialog_Btn{kind = .ABANDON, label = d.abandon_confirm ? "Abandon? (click again)" : "Abandon Quest"},
			)
		}
	}
	return btns[:]
}

dialog_button_rect :: proc "contextless" (panel: rl.Rectangle, i, count: int) -> rl.Rectangle {
	y := panel.y + panel.height - DIALOG_PAD - f32(count-i) * (DIALOG_OPT_H + DIALOG_OPT_GAP) +
		DIALOG_OPT_GAP
	return {panel.x + DIALOG_PAD, y, panel.width - 2 * DIALOG_PAD, DIALOG_OPT_H}
}

dialog_close_rect :: proc "contextless" (panel: rl.Rectangle) -> rl.Rectangle {
	sz := f32(18.0)
	return {panel.x + panel.width - DIALOG_PAD - sz, panel.y + (DIALOG_TITLE_H - sz) / 2, sz, sz}
}

dialog_panel_rect :: proc(d: ^sys.Dialog_State) -> rl.Rectangle {
	btns := build_dialog_buttons(d)
	body_h := f32(dialog_body_lines(d) * DIALOG_LINE_H + 8)
	h := DIALOG_TITLE_H + DIALOG_PAD + body_h + DIALOG_PAD +
		f32(len(btns)) * (DIALOG_OPT_H + DIALOG_OPT_GAP)
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	y := sh - h - 150
	if y < 60 do y = 60
	return {sw / 2 - f32(DIALOG_W) / 2, y, f32(DIALOG_W), h}
}

// ── actions ────────────────────────────────────────────────────────────────

close_dialog :: proc() {
	state.ctx.dialog.open = false
	sys.send_npc_dialog_close(state.net)
}

open_shop_from_dialog :: proc() {
	d := &state.ctx.dialog
	sys.shop_cache_clear(&state.shop_cache)
	sys.shop_cache_set_npc(&state.shop_cache, sys.dialog_npc_id_string(d))
	for i in 0 ..< d.shop_count {
		e := &d.shop_entries[i]
		sys.shop_cache_add(
			&state.shop_cache,
			string(e.id[:e.id_len]),
			string(e.name[:e.name_len]),
			e.category,
			e.rarity,
			e.price,
		)
	}
	ui.menu_open(&state.shop_menu)
	close_dialog()
}

perform_dialog_action :: proc(b: Dialog_Btn) {
	d := &state.ctx.dialog
	switch b.kind {
	case .NEXT_PAGE:
		sys.send_npc_interact(state.net, sys.dialog_npc_id_string(d), b.next_id)
	case .CLOSE:
		close_dialog()
	case .SHOW_OFFER:
		d.mode = .QUEST_OFFER
		d.selected_offer = b.index
		d.abandon_confirm = false
	case .SHOW_ACTIVE:
		d.mode = .QUEST_ACTIVE
		d.selected_active = b.index
		d.abandon_confirm = false
	case .ACCEPT:
		sys.send_quest_accept(state.net, b.quest_id)
		close_dialog()
	case .TURN_IN:
		sys.send_quest_complete(state.net, b.quest_id)
		close_dialog()
	case .ABANDON:
		if !d.abandon_confirm {
			d.abandon_confirm = true
			return
		}
		aq := dialog_selected_active(d)
		if aq != nil {
			sys.send_quest_abandon(state.net, sys.dialog_active_id_string(aq))
		}
		close_dialog()
	case .BACK:
		d.mode = .NPC_PAGE
		d.abandon_confirm = false
	case .OPEN_SHOP:
		open_shop_from_dialog()
	case .OPEN_ENHANCEMENT:
		open_enhancement_window()
		close_dialog()
	}
}

update_dialog :: proc() {
	d := &state.ctx.dialog
	if !d.open do return

	d.rect = dialog_panel_rect(d)
	if state.chat_focused do return

	mouse := rl.GetMousePosition()
	cr := dialog_close_rect(d.rect)
	if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse, cr) {
		close_dialog()
		return
	}

	btns := build_dialog_buttons(d)
	for b, i in btns {
		br := dialog_button_rect(d.rect, i, len(btns))
		if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse, br) {
			perform_dialog_action(b)
			return
		}
	}
}

// ── draw ───────────────────────────────────────────────────────────────────

draw_dialog :: proc() {
	d := &state.ctx.dialog
	if !d.open do return

	panel := d.rect
	mouse := rl.GetMousePosition()

	rl.DrawRectangleRec(panel, DIALOG_COL_BG)
	rl.DrawRectangleLinesEx(panel, 2, DIALOG_COL_BORDER)

	title_rect := rl.Rectangle{panel.x, panel.y, panel.width, DIALOG_TITLE_H}
	rl.DrawRectangleRec(title_rect, DIALOG_COL_TITLEBG)
	sys.draw_text(sys.dialog_npc_name_string(d), int(panel.x + DIALOG_PAD), int(panel.y + 6), 16, rl.Color{220, 220, 235, 255})

	cr := dialog_close_rect(panel)
	hov := rl.CheckCollisionPointRec(mouse, cr)
	rl.DrawRectangleRec(cr, hov ? rl.Color{180, 60, 60, 255} : rl.Color{100, 100, 110, 200})
	xw := sys.measure_text("X", 12)
	sys.draw_text("X", int(cr.x + (cr.width - f32(xw)) / 2), int(cr.y + 3), 12, rl.WHITE)

	body_x := panel.x + DIALOG_PAD
	body_y := panel.y + DIALOG_TITLE_H + DIALOG_PAD
	text_w := dialog_text_width()

	switch d.mode {
	case .NPC_PAGE:
		body_y = draw_wrapped(sys.dialog_page_text_string(d), body_x, body_y, text_w, DIALOG_COL_TEXT)
	case .QUEST_OFFER:
		of := dialog_selected_offer(d)
		if of != nil {
			sys.draw_text(sys.dialog_offer_title_string(of), int(body_x), int(body_y), DIALOG_TEXT_FZ, DIALOG_COL_GOLD)
			body_y += DIALOG_LINE_H
			body_y = draw_wrapped(sys.dialog_offer_text_string(of), body_x, body_y, text_w, DIALOG_COL_TEXT)
			rewards := fmt.tprintf("Rewards: %s", sys.dialog_offer_rewards_string(of))
			sys.draw_text(rewards, int(body_x), int(body_y), DIALOG_TEXT_FZ, DIALOG_COL_GREEN)
			body_y += DIALOG_LINE_H
			if of.required_level > state.player.stats.level {
				sys.draw_text(
					fmt.tprintf("Requires level %d", of.required_level),
					int(body_x), int(body_y), DIALOG_TEXT_FZ, DIALOG_COL_RED,
				)
			}
		}
	case .QUEST_ACTIVE:
		aq := dialog_selected_active(d)
		if aq != nil {
			sys.draw_text(sys.dialog_active_title_string(aq), int(body_x), int(body_y), DIALOG_TEXT_FZ, DIALOG_COL_GOLD)
			body_y += DIALOG_LINE_H
			for j in 0 ..< aq.objective_count {
				vo := &aq.objectives[j]
				done := vo.current >= vo.required
				mark := done ? "[x]" : "[ ]"
				col := done ? DIALOG_COL_GREEN : DIALOG_COL_TEXT
				sys.draw_text(
					fmt.tprintf("%s %s %d/%d", mark, sys.objective_name_string(vo), vo.current, vo.required),
					int(body_x + 8), int(body_y), DIALOG_TEXT_FZ, col,
				)
				body_y += DIALOG_LINE_H
			}
			body_y = draw_wrapped(sys.dialog_active_text_string(aq), body_x, body_y, text_w, DIALOG_COL_TEXT)
		}
	}

	btns := build_dialog_buttons(d)
	for b, i in btns {
		br := dialog_button_rect(panel, i, len(btns))
		hov := rl.CheckCollisionPointRec(mouse, br)
		bg := hov ? DIALOG_COL_BTN_HOV : DIALOG_COL_BTN
		rl.DrawRectangleRec(br, bg)
		rl.DrawRectangleLinesEx(br, 1, DIALOG_COL_BORDER)
		col := rl.Color{220, 220, 235, 255}
		if b.kind == .SHOW_OFFER || b.kind == .ACCEPT do col = DIALOG_COL_GOLD
		if b.kind == .TURN_IN do col = DIALOG_COL_GREEN
		if b.kind == .ABANDON && d.abandon_confirm do col = DIALOG_COL_RED
		tw := sys.measure_text(b.label, 15)
		sys.draw_text(
			b.label,
			int(br.x + (br.width - f32(tw)) / 2),
			int(br.y + (br.height - 15) / 2),
			15,
			col,
		)
	}
}

draw_wrapped :: proc(text: string, x, y_in: f32, max_w: f32, color: rl.Color) -> f32 {
	y := y_in
	for line in wrap_lines(text, max_w, DIALOG_TEXT_FZ) {
		sys.draw_text(line, int(x), int(y), DIALOG_TEXT_FZ, color)
		y += DIALOG_LINE_H
	}
	return y
}
