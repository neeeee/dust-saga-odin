package ui

import "core:strings"
import rl "vendor:raylib"

UI_Button :: struct {
	rect:        rl.Rectangle,
	text:        string,
	base_color:  rl.Color,
	hover_color: rl.Color,
	text_color:  rl.Color,
	font_size:   i32,
}

// Dummy :: proc() {
// 	rl.ClearBackground(rl.WHITE)
// 	rl.DrawText("test", 0, 0, 20, rl.BLACK)
// }

ui_is_hovered :: proc(btn: UI_Button) -> bool {
	mouse_pos := rl.GetMousePosition()
	return rl.CheckCollisionPointRec(mouse_pos, btn.rect)
}

ui_is_clicked :: proc(btn: UI_Button) -> bool {
	return ui_is_hovered(btn) && rl.IsMouseButtonPressed(.LEFT)
}

ui_draw_button :: proc(btn: UI_Button) {
	// Determine which color to use based on hover state
	color := btn.base_color
	if ui_is_hovered(btn) {
		color = btn.hover_color
	}

	// Draw the filled background rectangle
	rl.DrawRectangleRec(btn.rect, color)

	// Draw a border
	rl.DrawRectangleLinesEx(btn.rect, 2, rl.BLACK)

	// Calculate centered text position
	text_width := rl.MeasureText(strings.clone_to_cstring(btn.text), btn.font_size)
	text_x := i32(btn.rect.x + (btn.rect.width - f32(text_width)) / 2.0)
	text_y := i32(btn.rect.y + (btn.rect.height - f32(btn.font_size)) / 2.0)

	// Draw the text
	rl.DrawText(strings.clone_to_cstring(btn.text), text_x, text_y, btn.font_size, btn.text_color)
}
