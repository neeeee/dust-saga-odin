package title_screen

import "../../ui"
import "core:strings"
import rl "vendor:raylib"

state: struct {
	play_button: ui.UI_Button,
	quit_button: ui.UI_Button,
}

init :: proc() {
	state.play_button = ui.UI_Button {
		rect        = {300, 350, 200, 50},
		text        = "Play Game",
		base_color  = {70, 130, 180, 255}, // Steel Blue
		hover_color = {100, 160, 210, 255}, // Lighter Blue
		text_color  = rl.WHITE,
		font_size   = 24,
	}

	state.quit_button = ui.UI_Button {
		rect        = {300, 420, 200, 50},
		text        = "Quit",
		base_color  = {180, 70, 70, 255}, // Muted Red
		hover_color = {210, 100, 100, 255}, // Lighter Red
		text_color  = rl.WHITE,
		font_size   = 24,
	}
}

update :: proc() -> bool {
	if ui.ui_is_clicked(state.play_button) {
		return true
	}
	if ui.ui_is_clicked(state.quit_button) {
		rl.CloseWindow() // Force close
	}
	return false
}

render :: proc() {
	rl.ClearBackground({20, 20, 30, 255})

	title_text := "DUST SAGA"
	title_width := rl.MeasureText(strings.clone_to_cstring(title_text, context.temp_allocator), 40)
	rl.DrawText(
		strings.clone_to_cstring(title_text, context.temp_allocator),
		400 - title_width / 2,
		150,
		40,
		rl.GOLD,
	)

	rl.DrawText("An Odin MMO", 400 - 70, 200, 20, rl.LIGHTGRAY)

	ui.ui_draw_button(state.play_button)
	ui.ui_draw_button(state.quit_button)
}
