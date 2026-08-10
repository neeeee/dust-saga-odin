package main

import "core:fmt"
import rl "vendor:raylib"
import sys "systems"

import gameplay "scenes/gameplay"
import login "scenes/login"
import title_screen "scenes/title_screen"
import character_select "scenes/character_select"

// Main entry point and top-level state machine:
//   TITLE → LOGIN → CHARACTER_SELECT → GAMEPLAY
// Shared resources (network client, entity scene, local player, chat log) live
// here so they survive across scene transitions (e.g. reconnecting keeps the
// socket; logging out keeps the character list).

main :: proc() {
	rl.InitWindow(1280, 720, "Dust Saga")
	rl.SetTargetFPS(60)
	rl.SetExitKey(.KEY_NULL) // we handle ESC ourselves
	defer rl.CloseWindow()

	// Shared, long-lived state.
	net := sys.new_network_client(sys.DEFAULT_SERVER_HOST, sys.DEFAULT_SERVER_PORT)
	defer sys.destroy_network_client(net)

	scene := sys.scene_init()
	defer sys.scene_destroy(scene)

	player: sys.Local_Player
	sys.local_player_init(&player)
	defer sys.local_player_destroy(&player)

	chat: sys.Chat_Log
	sys.chat_init(&chat)
	defer sys.chat_destroy(&chat)

	state: sys.App_State = .TITLE
	title_screen.Init()

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()

		#partial switch state {
		case .TITLE:
			if title_screen.Update() {
				state = .LOGIN
				login.init(net)
			}

		case .LOGIN:
			if login.update(dt) {
				state = .CHARACTER_SELECT
				character_select.init(net)
			}

		case .CHARACTER_SELECT:
			// update() drains CHARACTER_LIST/NOTIFICATION; returns the chosen
			// character id once the user presses ENTER.
			chosen_id, chose := character_select.update(dt)
			if chose {
				_ = chosen_id
				state = .GAMEPLAY
				gameplay.init(net, scene, &player, &chat)
			}

		case .GAMEPLAY:
			requested, has_req := gameplay.update(dt)
			if has_req && requested == .CHARACTER_SELECT {
				// User logged out → back to character select.
				gameplay.shutdown()
				state = .CHARACTER_SELECT
				character_select.init(net)
			} else if has_req && requested == .TITLE {
				// Exit game timer expired.
				gameplay.shutdown()
				state = .TITLE
				title_screen.Init()
			}
		case:
		}

		// ── render ───────────────────────────────────────────────────────
		rl.BeginDrawing()
		#partial switch state {
		case .TITLE:
			title_screen.Render()
		case .LOGIN:
			login.render()
		case .CHARACTER_SELECT:
			character_select.render()
		case .GAMEPLAY:
			gameplay.render()
		case:
			rl.ClearBackground(rl.BLACK)
			rl.DrawText("Unknown state", 20, 20, 20, rl.RED)
		}
		rl.DrawFPS(10, 690)
		rl.EndDrawing()
	}
}

_ :: fmt.println
