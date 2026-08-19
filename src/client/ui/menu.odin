package ui

import "core:fmt"
import "core:math"
import "core:strings"
import rl "vendor:raylib"

MENU_TITLE_H :: 30.0
MENU_ITEM_H   :: 28.0
MENU_PAD      :: 6.0
MENU_BORDER   :: 2
MENU_CLOSE_SZ :: 20.0
MENU_CHECK_SZ :: 18.0
MENU_LBL_FZ   :: 16

MENU_COL_BG       :: rl.Color{20, 22, 28, 235}
MENU_COL_BORDER   :: rl.Color{140, 140, 160, 255}
MENU_COL_TITLE_BG :: rl.Color{40, 44, 56, 250}
MENU_COL_TITLE    :: rl.Color{220, 220, 235, 255}
MENU_COL_BTN      :: rl.Color{55, 60, 75, 255}
MENU_COL_BTN_HOV  :: rl.Color{75, 85, 115, 255}
MENU_COL_BTN_TXT  :: rl.Color{220, 220, 235, 255}
MENU_COL_TOG_OFF  :: rl.Color{60, 60, 70, 255}
MENU_COL_TOG_ON   :: rl.Color{70, 130, 210, 255}
MENU_COL_SLD_TRK  :: rl.Color{50, 50, 60, 255}
MENU_COL_SLD_FIL  :: rl.Color{70, 130, 210, 255}
MENU_COL_SLD_HDL  :: rl.Color{200, 200, 215, 255}
MENU_COL_LABEL    :: rl.Color{190, 190, 200, 255}
MENU_COL_SEP      :: rl.Color{80, 80, 100, 255}
MENU_COL_CLOSE    :: rl.Color{100, 100, 110, 200}
MENU_COL_CLOSE_HV :: rl.Color{180, 60, 60, 255}

Menu_Item_Kind :: enum {
	BUTTON,
	TOGGLE,
	SLIDER,
	LABEL,
	SEPARATOR,
}

Menu_Item :: struct {
	kind:        Menu_Item_Kind,
	id:          int,
	label:       string,
	clicked:     bool,
	checked:     bool,
	value:       f32,
	min_value:   f32,
	max_value:   f32,
	step:        f32,
	slider_drag: bool,
	label_color: rl.Color,
	active:      bool,
}

Menu :: struct {
	title:        string,
	rect:         rl.Rectangle,
	open:         bool,
	focused:      bool,
	items:        [dynamic]Menu_Item,
	next_id:      int,
	scroll_y:     f32,
	max_scroll:   f32,
	dragging:     bool,
	drag_off:     rl.Vector2,
	bg_color:     rl.Color,
	border_color: rl.Color,
	title_bg:     rl.Color,
	title_color:  rl.Color,
	item_h:       f32,
	padding:      f32,
	close_on_esc: bool,
	closable:     bool,
}

// ── internal helpers ───────────────────────────────────────────────────────

draw_str :: proc(text: string, x, y: i32, size: i32, color: rl.Color) {
	// temp allocator (frame arena): the cstring only needs to live for the
	// DrawText call, and cloning on the heap here would leak per item/frame.
	rl.DrawText(strings.clone_to_cstring(text, context.temp_allocator), x, y, size, color)
}

measure_str :: proc(text: string, size: i32) -> i32 {
	return rl.MeasureText(strings.clone_to_cstring(text, context.temp_allocator), size)
}

slider_update_value :: proc(item: ^Menu_Item, m: ^Menu) {
	lw := f32(measure_str(item.label, MENU_LBL_FZ))
	track_x := m.rect.x + m.padding + lw + 10
	track_w := m.rect.width - 2*m.padding - lw - 60
	if track_w < 20 do track_w = 20

	mouse := rl.GetMousePosition()
	ratio := math.clamp((mouse.x - track_x) / track_w, 0, 1)
	raw := item.min_value + ratio*(item.max_value - item.min_value)
	if item.step > 0 {
		raw = math.round(raw / item.step) * item.step
	}
	item.value = math.clamp(raw, item.min_value, item.max_value)
}

// ── create / destroy ──────────────────────────────────────────────────────

menu_create :: proc(title: string, x, y, w, h: f32) -> Menu {
	m: Menu
	m.title = title
	m.rect = {x, y, w, h}
	m.open = false
	m.items = make([dynamic]Menu_Item)
	m.next_id = 1
	m.bg_color = MENU_COL_BG
	m.border_color = MENU_COL_BORDER
	m.title_bg = MENU_COL_TITLE_BG
	m.title_color = MENU_COL_TITLE
	m.item_h = MENU_ITEM_H
	m.padding = MENU_PAD
	m.close_on_esc = true
	m.closable = true
	return m
}

menu_destroy :: proc(m: ^Menu) {
	delete(m.items)
	m.open = false
}

// ── add items (return item id) ─────────────────────────────────────────────

menu_add_button :: proc(m: ^Menu, label: string) -> int {
	id := m.next_id
	m.next_id += 1
	append(&m.items, Menu_Item {
		kind = .BUTTON,
		id = id,
		label = label,
		label_color = MENU_COL_BTN_TXT,
	})
	return id
}

menu_add_button_id :: proc(m: ^Menu, label: string, id: int) {
	append(&m.items, Menu_Item {
		kind = .BUTTON,
		id = id,
		label = label,
		label_color = MENU_COL_BTN_TXT,
	})
	if id >= m.next_id do m.next_id = id + 1
}

menu_add_toggle :: proc(m: ^Menu, label: string, checked: bool) -> int {
	id := m.next_id
	m.next_id += 1
	append(&m.items, Menu_Item {
		kind = .TOGGLE,
		id = id,
		label = label,
		checked = checked,
		label_color = MENU_COL_BTN_TXT,
	})
	return id
}

menu_add_slider :: proc(m: ^Menu, label: string, value, min_v, max_v, step: f32) -> int {
	id := m.next_id
	m.next_id += 1
	append(&m.items, Menu_Item {
		kind = .SLIDER,
		id = id,
		label = label,
		value = value,
		min_value = min_v,
		max_value = max_v,
		step = step,
		label_color = MENU_COL_BTN_TXT,
	})
	return id
}

menu_add_label :: proc(m: ^Menu, label: string) -> int {
	id := m.next_id
	m.next_id += 1
	append(&m.items, Menu_Item {
		kind = .LABEL,
		id = id,
		label = label,
		label_color = MENU_COL_LABEL,
	})
	return id
}

menu_add_separator :: proc(m: ^Menu) {
	id := m.next_id
	m.next_id += 1
	append(&m.items, Menu_Item {
		kind = .SEPARATOR,
		id = id,
	})
}

// ── clear / find ──────────────────────────────────────────────────────────

menu_clear :: proc(m: ^Menu) {
	delete(m.items)
	m.items = make([dynamic]Menu_Item)
	m.next_id = 1
	// NOTE: scroll_y is intentionally preserved. Dynamic menus call menu_clear
	// every frame to rebuild; resetting scroll here would wipe the position
	// menu_update just set, making the wheel never accumulate (1-frame jitter).
	// menu_update clamps scroll_y to [0, max_scroll], so a content shrink
	// self-corrects next frame.
}

menu_find :: proc(m: ^Menu, id: int) -> ^Menu_Item {
	for i in 0 ..< len(m.items) {
		if m.items[i].id == id do return &m.items[i]
	}
	return nil
}

// ── open / close / toggle / position ──────────────────────────────────────

menu_open :: proc(m: ^Menu) {
	m.open = true
	m.focused = true
	m.scroll_y = 0 // start at the top on (re)open
}

menu_close :: proc(m: ^Menu) {
	m.open = false
	m.focused = false
	for i in 0 ..< len(m.items) {
		m.items[i].slider_drag = false
	}
}

menu_toggle :: proc(m: ^Menu) {
	if m.open {
		menu_close(m)
	} else {
		menu_open(m)
	}
}

menu_set_pos :: proc(m: ^Menu, x, y: f32) {
	m.rect.x = x
	m.rect.y = y
}

menu_center :: proc(m: ^Menu) {
	m.rect.x = (f32(rl.GetScreenWidth()) - m.rect.width) / 2
	m.rect.y = (f32(rl.GetScreenHeight()) - m.rect.height) / 2
}

menu_resize :: proc(m: ^Menu, w, h: f32) {
	m.rect.width = w
	m.rect.height = h
}

menu_auto_height :: proc(m: ^Menu, max_h: f32) {
	content_h := f32(len(m.items)) * (m.item_h + m.padding) + m.padding
	needed := MENU_TITLE_H + content_h
	m.rect.height = math.min(needed, max_h)
}

// ── update (input) ────────────────────────────────────────────────────────

menu_update :: proc(m: ^Menu) {
	if !m.open do return

	for i in 0 ..< len(m.items) {
		m.items[i].clicked = false
	}

	mouse := rl.GetMousePosition()
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())

	m.rect.x = math.clamp(m.rect.x, -m.rect.width + 100, sw - 100)
	m.rect.y = math.clamp(m.rect.y, -MENU_TITLE_H, sh - 50)

	if m.close_on_esc && rl.IsKeyPressed(.ESCAPE) {
		menu_close(m)
		return
	}

	m.focused = rl.CheckCollisionPointRec(mouse, m.rect)

	// title bar drag
	title_rect := rl.Rectangle{m.rect.x, m.rect.y, m.rect.width, MENU_TITLE_H}
	if m.dragging {
		if rl.IsMouseButtonReleased(.LEFT) {
			m.dragging = false
		} else {
			m.rect.x = mouse.x - m.drag_off.x
			m.rect.y = mouse.y - m.drag_off.y
		}
	} else if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse, title_rect) {
		if m.closable {
			cx := m.rect.x + m.rect.width - m.padding - MENU_CLOSE_SZ
			cy := m.rect.y + (MENU_TITLE_H - MENU_CLOSE_SZ) / 2
			cr := rl.Rectangle{cx, cy, MENU_CLOSE_SZ, MENU_CLOSE_SZ}
			if rl.CheckCollisionPointRec(mouse, cr) {
				menu_close(m)
				return
			}
		}
		m.dragging = true
		m.drag_off = {mouse.x - m.rect.x, mouse.y - m.rect.y}
	}

	// scroll
	content_h := f32(len(m.items)) * (m.item_h + m.padding) + m.padding
	visible_h := m.rect.height - MENU_TITLE_H - m.padding
	m.max_scroll = math.max(0, content_h - visible_h)
	if m.max_scroll > 0 && rl.CheckCollisionPointRec(mouse, m.rect) {
		wheel := rl.GetMouseWheelMove()
		if wheel != 0 {
			m.scroll_y -= wheel * 20
			m.scroll_y = math.clamp(m.scroll_y, 0, m.max_scroll)
		}
	}

	if m.dragging do return
	if !m.focused do return

	// item interaction
	content_top := m.rect.y + MENU_TITLE_H + m.padding
	clip_bot := m.rect.y + m.rect.height

	for i in 0 ..< len(m.items) {
		item := &m.items[i]
		iy := content_top + f32(i)*(m.item_h + m.padding) - m.scroll_y
		if iy + m.item_h < m.rect.y + MENU_TITLE_H do continue
		if iy > clip_bot do continue

		ir := rl.Rectangle{m.rect.x + m.padding, iy, m.rect.width - 2*m.padding, m.item_h}
		hov := rl.CheckCollisionPointRec(mouse, ir)

		#partial switch item.kind {
		case .BUTTON:
			if hov && rl.IsMouseButtonPressed(.LEFT) do item.clicked = true
		case .TOGGLE:
			if hov && rl.IsMouseButtonPressed(.LEFT) {
				item.checked = !item.checked
				item.clicked = true
			}
		case .SLIDER:
			if hov && rl.IsMouseButtonPressed(.LEFT) do item.slider_drag = true
		}
	}

	// active slider drags (mouse may have left the track)
	for i in 0 ..< len(m.items) {
		item := &m.items[i]
		if item.kind == .SLIDER && item.slider_drag {
			if rl.IsMouseButtonReleased(.LEFT) {
				item.slider_drag = false
			} else {
				slider_update_value(item, m)
			}
		}
	}
}

// ── draw ──────────────────────────────────────────────────────────────────

menu_draw :: proc(m: ^Menu) {
	if !m.open do return

	rl.DrawRectangleRec(m.rect, m.bg_color)
	rl.DrawRectangleLinesEx(m.rect, MENU_BORDER, m.border_color)

	// title bar
	tr := rl.Rectangle{m.rect.x, m.rect.y, m.rect.width, MENU_TITLE_H}
	rl.DrawRectangleRec(tr, m.title_bg)

	tx := i32(m.rect.x + m.padding)
	ty := i32(m.rect.y + (MENU_TITLE_H - 20) / 2)
	draw_str(m.title, tx, ty, 20, m.title_color)

	// close button
	if m.closable {
		cx := m.rect.x + m.rect.width - m.padding - MENU_CLOSE_SZ
		cy := m.rect.y + (MENU_TITLE_H - MENU_CLOSE_SZ) / 2
		cr := rl.Rectangle{cx, cy, MENU_CLOSE_SZ, MENU_CLOSE_SZ}
		mouse := rl.GetMousePosition()
		cc := MENU_COL_CLOSE
		if rl.CheckCollisionPointRec(mouse, cr) do cc = MENU_COL_CLOSE_HV
		rl.DrawRectangleRec(cr, cc)
		draw_str("X", i32(cx) + 5, i32(cy) + 2, 16, rl.WHITE)
	}

	// separator below title
	rl.DrawLine(
		i32(m.rect.x), i32(m.rect.y + MENU_TITLE_H),
		i32(m.rect.x + m.rect.width), i32(m.rect.y + MENU_TITLE_H),
		m.border_color,
	)

	// scissor for content area
	sc_x := i32(m.rect.x)
	sc_y := i32(m.rect.y + MENU_TITLE_H)
	sc_w := i32(m.rect.width)
	sc_h := i32(m.rect.height - MENU_TITLE_H)
	rl.BeginScissorMode(sc_x, sc_y, sc_w, sc_h)

	content_top := m.rect.y + MENU_TITLE_H + m.padding
	clip_bot := m.rect.y + m.rect.height

	for i in 0 ..< len(m.items) {
		item := &m.items[i]
		iy := content_top + f32(i)*(m.item_h + m.padding) - m.scroll_y
		if iy + m.item_h < m.rect.y + MENU_TITLE_H do continue
		if iy > clip_bot do continue

		ir := rl.Rectangle{m.rect.x + m.padding, iy, m.rect.width - 2*m.padding, m.item_h}

		switch item.kind {
		case .BUTTON:
			draw_btn_item(item, ir)
		case .TOGGLE:
			draw_tog_item(item, ir)
		case .SLIDER:
			draw_sld_item(item, ir, m)
		case .LABEL:
			draw_lbl_item(item, ir)
		case .SEPARATOR:
			draw_sep_item(ir)
		}
	}

	rl.EndScissorMode()

	// scrollbar
	if m.max_scroll > 0 do draw_scrollbar(m)
}

// ── item draw helpers ─────────────────────────────────────────────────────

draw_btn_item :: proc(item: ^Menu_Item, r: rl.Rectangle) {
	mouse := rl.GetMousePosition()
	hov := rl.CheckCollisionPointRec(mouse, r)
	c := MENU_COL_BTN
	if hov do c = MENU_COL_BTN_HOV
	if item.active do c = {c.r, c.g, min(c.b + 25, 255), c.a}
	rl.DrawRectangleRec(r, c)
	rl.DrawRectangleLinesEx(r, 1, MENU_COL_BORDER)
	tw := measure_str(item.label, MENU_LBL_FZ)
	lx := i32(r.x + (r.width - f32(tw)) / 2)
	ly := i32(r.y + (r.height - f32(MENU_LBL_FZ)) / 2)
	draw_str(item.label, lx, ly, MENU_LBL_FZ, item.label_color)
}

draw_tog_item :: proc(item: ^Menu_Item, r: rl.Rectangle) {
	mouse := rl.GetMousePosition()
	if rl.CheckCollisionPointRec(mouse, r) {
		rl.DrawRectangleRec(r, {40, 42, 52, 255})
	}
	bx := r.x + 4
	by := r.y + (r.height - MENU_CHECK_SZ) / 2
	bc := MENU_COL_TOG_OFF
	if item.checked do bc = MENU_COL_TOG_ON
	rl.DrawRectangleRec({bx, by, MENU_CHECK_SZ, MENU_CHECK_SZ}, bc)
	rl.DrawRectangleLinesEx({bx, by, MENU_CHECK_SZ, MENU_CHECK_SZ}, 1, MENU_COL_BORDER)
	if item.checked {
		tw := measure_str("v", MENU_LBL_FZ)
		draw_str("v", i32(bx) + i32((MENU_CHECK_SZ - f32(tw)) / 2), i32(by) + 1, MENU_LBL_FZ, rl.WHITE)
	}
	draw_str(
		item.label,
		i32(bx + MENU_CHECK_SZ + 8),
		i32(r.y + (r.height - f32(MENU_LBL_FZ)) / 2),
		MENU_LBL_FZ,
		item.label_color,
	)
}

draw_sld_item :: proc(item: ^Menu_Item, r: rl.Rectangle, m: ^Menu) {
	draw_str(
		item.label,
		i32(r.x),
		i32(r.y + (r.height - f32(MENU_LBL_FZ)) / 2),
		MENU_LBL_FZ,
		item.label_color,
	)

	track_x := r.x + f32(measure_str(item.label, MENU_LBL_FZ)) + 10
	track_w := r.width - f32(measure_str(item.label, MENU_LBL_FZ)) - 60
	if track_w < 20 do track_w = 20
	track_y := r.y + (r.height - 6) / 2

	rl.DrawRectangleRec({track_x, track_y, track_w, 6}, MENU_COL_SLD_TRK)

	rng := item.max_value - item.min_value
	ratio := rng > 0 ? (item.value - item.min_value) / rng : 0
	fill_w := track_w * math.clamp(ratio, 0, 1)
	rl.DrawRectangleRec({track_x, track_y, fill_w, 6}, MENU_COL_SLD_FIL)

	handle_x := track_x + fill_w - 6
	if handle_x < track_x do handle_x = track_x
	rl.DrawRectangleRec({handle_x, track_y - 5, 12, 16}, MENU_COL_SLD_HDL)

	val_str: string
	if item.step >= 1.0 {
		val_str = fmt.tprintf("%d", i32(item.value))
	} else {
		val_str = fmt.tprintf("%.1f", item.value)
	}
	vw := f32(measure_str(val_str, MENU_LBL_FZ))
	draw_str(
		val_str,
		i32(r.x + r.width - vw - 4),
		i32(r.y + (r.height - f32(MENU_LBL_FZ)) / 2),
		MENU_LBL_FZ,
		item.label_color,
	)
}

draw_lbl_item :: proc(item: ^Menu_Item, r: rl.Rectangle) {
	draw_str(
		item.label,
		i32(r.x),
		i32(r.y + (r.height - f32(MENU_LBL_FZ)) / 2),
		MENU_LBL_FZ,
		item.label_color,
	)
}

draw_sep_item :: proc(r: rl.Rectangle) {
	y := i32(r.y + r.height / 2)
	rl.DrawLine(i32(r.x), y, i32(r.x + r.width), y, MENU_COL_SEP)
}

draw_scrollbar :: proc(m: ^Menu) {
	bx := m.rect.x + m.rect.width - 8
	by := m.rect.y + MENU_TITLE_H
	bh := m.rect.height - MENU_TITLE_H

	rl.DrawRectangleRec({bx, by, 6, bh}, {40, 40, 50, 150})

	total := m.max_scroll + bh
	if total <= 0 do return
	thumb_h := bh * (bh / total)
	thumb_y := by + (m.scroll_y / m.max_scroll) * (bh - thumb_h)
	rl.DrawRectangleRec({bx, thumb_y, 6, thumb_h}, {100, 100, 120, 200})
}
