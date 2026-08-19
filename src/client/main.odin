package main

import "core:fmt"
import "core:mem"
import sys "systems"
import rl "vendor:raylib"

import character_select "scenes/character_select"
import gameplay "scenes/gameplay"
import login "scenes/login"
import title_screen "scenes/title_screen"

// Main entry point and top-level state machine:
//   TITLE → LOGIN → CHARACTER_SELECT → GAMEPLAY
// Shared resources (network client, entity scene, local player, chat log) live
// here so they survive across scene transitions (e.g. reconnecting keeps the
// socket; logging out keeps the character list).
//
// A per-frame Dynamic_Arena backs context.temp_allocator so all the transient
// allocations made by gameplay/UI code each frame (fmt.tprintf HUD strings,
// strings.clone_to_cstring for raylib text APIs, etc.) are bulk-freed at frame
// end instead of accumulating on the heap for the whole session.

main :: proc() {
	rl.InitWindow(1280, 720, "Dust Saga")
	rl.SetTargetFPS(60)
	rl.SetExitKey(.KEY_NULL) // we handle ESC ourselves
	defer rl.CloseWindow()

	// Custom image cursor: hide the OS cursor everywhere and draw this
	// texture at the mouse position, topmost, every frame.
	CURSOR_PATH :: "assets/images/cursor.png"
	CURSOR_SIZE :: 64.0
	cursor_tex := rl.LoadTexture(CURSOR_PATH)
	defer rl.UnloadTexture(cursor_tex)
	rl.SetTextureFilter(cursor_tex, .BILINEAR)
	rl.HideCursor()

	frame_arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&frame_arena)
	defer mem.dynamic_arena_destroy(&frame_arena)

	// Static game data (races / jobs / skills) — registries populated once.
	sys.init_game_data()
	defer sys.destroy_game_data()

	// Rebindable keybinds (keybinds.json, falls back to WASD defaults).
	sys.load_keybinds()

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
	title_screen.init()

	for !rl.WindowShouldClose() && !gameplay.quit_requested {
		// All transient per-frame allocations land in the frame arena.
		context.temp_allocator = mem.dynamic_arena_allocator(&frame_arena)
		dt := rl.GetFrameTime()

		#partial switch state {
		case .TITLE:
			if title_screen.update() {
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
				title_screen.init()
			}
		case:
		}

		// ── render ───────────────────────────────────────────────────────
		rl.BeginDrawing()
		#partial switch state {
		case .TITLE:
			title_screen.render()
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

		// Custom cursor, drawn last so it sits above every scene's UI.
		// Skipped during right-drag mouselook — DisableCursor locks the
		// pointer at the window center there, so nothing should be drawn.
		if cursor_tex.id > 0 && !rl.IsMouseButtonDown(.RIGHT) {
			mouse := rl.GetMousePosition()
			src := rl.Rectangle{0, 0, f32(cursor_tex.width), f32(cursor_tex.height)}
			dst := rl.Rectangle{mouse.x, mouse.y, CURSOR_SIZE, CURSOR_SIZE}
			rl.DrawTexturePro(cursor_tex, src, dst, {}, 0, rl.WHITE)
		}
		rl.EndDrawing()

		// Reset the frame arena — all per-frame temp allocations are freed here.
		mem.dynamic_arena_free_all(&frame_arena)
	}
}

_ :: fmt.println
