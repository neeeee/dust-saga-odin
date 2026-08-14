package gameplay

import sys "../../systems"
import "core:fmt"
import "core:math"
import rl "vendor:raylib"

// 2D HUD + 3D overlay rendering, split from the core orchestrator. All state
// lives in the package-level `state` (see gameplay.odin).

// ── render ────────────────────────────────────────────────────────────────

render :: proc() {
	if !state.initialized do return

	rl.ClearBackground(rl.SKYBLUE)

	rl.BeginMode3D(state.player.camera)
	if state.ctx.zone != nil {
		sys.render_zone(state.ctx.zone)
	}
	// Draw the local player as a capsule too (distinct color).
	draw_local_player()
	sys.render(state.scene, state.player.camera)
	draw_ground_reticle_3d()
	rl.EndMode3D()

	// 2D entity nameplates / health bars / target indicators.
	sys.render_entity_ui_2d(state.scene, state.player.camera)

	// 2D HUD.
	draw_hud()
	draw_target_window()
	draw_floating_text()
	draw_chat()
	draw_notifications()
	draw_ground_reticle_hint()
	draw_menu_bar()
	draw_menus()
	if state.player.is_dead do draw_death_overlay()
}

// Ground-target reticle: a ring + center marker on the ground under the cursor.
draw_ground_reticle_3d :: proc() {
	gt := &state.ground_target
	if !gt.active do return
	ray := rl.GetScreenToWorldRay(rl.GetMousePosition(), state.player.camera)
	hit, point := sys.ray_ground_hit(ray, 0.0)
	if !hit do return
	rl.DrawCircle3D(point, gt.radius, {0, 1, 0}, 0.0, rl.Color{230, 120, 40, 210})
	rl.DrawCube(point, 0.5, 0.5, 0.5, rl.Color{230, 120, 40, 230})
}

// 2D prompt shown while aiming a ground-targeted skill.
draw_ground_reticle_hint :: proc() {
	gt := &state.ground_target
	if !gt.active do return
	name := string(gt.skill_name[:gt.name_len])
	msg := fmt.tprintf("Aiming %s — click to cast, Esc to cancel", name)
	w := sys.measure_text(msg, 18)
	x := int(rl.GetScreenWidth()) / 2 - w / 2
	sys.draw_text(msg, x, 110, 18, rl.Color{230, 180, 60, 255})
}

draw_local_player :: proc() {
	p := state.player.position
	pos := rl.Vector3{p.x, p.y + 0.9, p.z}
	axis, angle := sys.euler_y_to_raylib(state.player.yaw)
	col := rl.Color{100, 180, 255, 255}
	if state.player.is_resting do col = {120, 120, 180, 255}
	if state.player.is_dead do col = {120, 120, 120, 255}
	rl.DrawModelEx(state.scene.model_capsule, pos, axis, angle, {1, 1, 1}, col)
}

draw_hud :: proc() {
	// Health + mana bars bottom-left.
	s := &state.player.stats
	hp_ratio := s.max_health > 0 ? s.health / s.max_health : 0
	mp_ratio := s.max_mana > 0 ? s.mana / s.max_mana : 0
	draw_bar(
		20,
		20,
		240,
		18,
		hp_ratio,
		rl.RED,
		fmt.tprintf("HP %d/%d", i32(s.health), i32(s.max_health)),
	)
	draw_bar(
		20,
		43,
		240,
		14,
		mp_ratio,
		rl.BLUE,
		fmt.tprintf("MP %d/%d", i32(s.mana), i32(s.max_mana)),
	)

	// Level + zone top-left.
	sys.draw_text(
		fmt.tprintf("Lv %d  %s", s.level, string(state.player.name[:state.player.name_len])),
		20,
		12,
		20,
		rl.WHITE,
	)

	// Skill bar bottom-center.
	draw_skill_bar()

	// Cast bar (centered, above skill bar).
	if state.player.casting.active {
		c := state.player.casting
		ratio := c.cast_time > 0 ? f32(c.elapsed / c.cast_time) : 1.0
		draw_bar(540, 620, 200, 16, ratio, rl.ORANGE, "")
	}

	// Connection status top-right.
	status_text := "Connected"
	if !sys.is_connected(state.net) do status_text = "Connecting…"
	sys.draw_text(status_text, 1130, 12, 16, sys.is_connected(state.net) ? rl.GREEN : rl.YELLOW)
}

draw_bar :: proc(x, y, w, h: i32, ratio: f32, color: rl.Color, label: string) {
	r := math.clamp(ratio, 0, 1)
	rl.DrawRectangle(x, y, w, h, rl.Color{30, 30, 30, 220})
	rl.DrawRectangle(x, y, i32(f32(w) * r), h, color)
	rl.DrawRectangleLines(x, y, w, h, rl.BLACK)
	if len(label) > 0 {
		sys.draw_text(label, int(x + 6), int(y + (h - 14) / 2), 12, rl.WHITE)
	}
}

draw_target_window :: proc() {
	s := state.scene
	if s.target_id == sys.INVALID_ENTITY do return
	idx := sys.find_index(s, s.target_id)
	if idx < 0 do return

	entity_ui := &s.ui[idx]
	meta := &s.metas[idx]
	ef := &s.effects[idx]

	name := string(entity_ui.name_str[:entity_ui.name_len])
	if len(name) == 0 do return

	screen_w := int(rl.GetScreenWidth())
	win_w := 250
	win_x := screen_w / 2 - win_w / 2
	win_y := 70

	kind := meta.kind

	name_col: rl.Color
	if kind == .ENEMY {
		name_col = {255, 100, 100, 255}
	} else if kind == .NPC {
		name_col = {255, 255, 100, 255}
	} else {
		name_col = {130, 180, 255, 255}
	}

	row_h := 20
	cur_y := win_y

	// Background panel.
	panel_h := row_h + 4
	show_hp := meta.max_health > 0.0
	if show_hp do panel_h += 24
	if ef.count > 0 do panel_h += 22

	rl.DrawRectangle(i32(win_x), i32(cur_y), i32(win_w), i32(panel_h), rl.Color{20, 20, 30, 210})
	rl.DrawRectangleLines(i32(win_x), i32(cur_y), i32(win_w), i32(panel_h), rl.Color{80, 80, 100, 200})

	// Row 1: name + level.
	if kind != .NPC && meta.level > 0 {
		sys.draw_text(fmt.tprintf("Lv%d", meta.level), win_x + 8, cur_y + 2, 14, rl.GRAY)
		sys.draw_text(name, win_x + 52, cur_y + 2, 14, name_col)
	} else {
		sys.draw_text(name, win_x + 8, cur_y + 2, 14, name_col)
	}
	cur_y += row_h

	// Row 2: health bar (enemies, players, summons — not NPCs).
	if show_hp {
		hp_ratio := meta.max_health > 0 ? meta.health / meta.max_health : 0
		hp_text := fmt.tprintf("%d / %d", i32(meta.health), i32(meta.max_health))
		bar_bg := rl.Color{60, 10, 10, 255}
		bar_fg: rl.Color
		if hp_ratio < 0.25 { bar_fg = rl.RED
		} else if hp_ratio < 0.5 { bar_fg = rl.YELLOW
		} else { bar_fg = {200, 40, 40, 255} }
		rl.DrawRectangle(i32(win_x + 8), i32(cur_y), i32(win_w - 16), 18, bar_bg)
		fill := i32(f32(win_w - 16) * math.clamp(hp_ratio, 0, 1))
		rl.DrawRectangle(i32(win_x + 8), i32(cur_y), fill, 18, bar_fg)
		rl.DrawRectangleLines(i32(win_x + 8), i32(cur_y), i32(win_w - 16), 18, rl.BLACK)
		sys.draw_text(hp_text, win_x + 14, cur_y + 2, 12, rl.WHITE)
		cur_y += 22
	}

	// Row 3: buff / debuff icons.
	if ef.count > 0 {
		icon_x := win_x + 8
		icon_size := 20
		now := sys.now_ms()
		for i in 0 ..< ef.count {
			e := &ef.effects[i]
			if e.expires_at > 0 && now >= e.expires_at do continue

			bg_col: rl.Color
			if e.is_buff { bg_col = {50, 140, 50, 200}
			} else { bg_col = {160, 40, 40, 200} }

			rl.DrawRectangle(i32(icon_x), i32(cur_y), i32(icon_size), i32(icon_size), bg_col)
			rl.DrawRectangleLines(i32(icon_x), i32(cur_y), i32(icon_size), i32(icon_size), rl.Color{40, 40, 40, 200})

			a, b := sys.status_effect_label(string(e.type_str[:e.type_len]))
			label := [2]byte{a, b}
			sys.draw_text(string(label[:]), icon_x + 2, cur_y + 3, 12, rl.WHITE)

			if e.expires_at > 0 {
				rem := f64(e.expires_at - now) / 1000.0
				if rem < 60 {
					sec := fmt.tprintf("%.0f", rem)
					sw := sys.measure_text(sec, 8)
					sys.draw_text(sec, icon_x + icon_size - sw - 1, cur_y + icon_size - 10, 8, {200, 200, 200, 200})
				} else {
					mn := fmt.tprintf("%dm", i32(rem / 60.0))
					sw := sys.measure_text(mn, 8)
					sys.draw_text(mn, icon_x + icon_size - sw - 1, cur_y + icon_size - 10, 8, {200, 200, 200, 200})
				}
			}

			icon_x += icon_size + 2
			if icon_x + icon_size > win_x + win_w - 4 do break
		}
	}
}

draw_skill_bar :: proc() {
	mouse := rl.GetMousePosition()
	p := state.player

	for bar in 0 ..< sys.SKILL_BAR_COUNT {
		if bar > 0 && !sys.skill_bar_has_skills(p, bar) do continue
		pos := p.skill_bar_pos[bar]
		bar_w := f32(sys.SLOTS_PER_BAR * (SKILL_SLOT_SIZE + SKILL_SLOT_GAP) - SKILL_SLOT_GAP)
		bg := rl.Rectangle{pos.x - 4, pos.y - 4, bar_w + 8, f32(SKILL_SLOT_SIZE) + 8}
		being_dragged := state.dragging_bar == bar
		rl.DrawRectangleRec(bg, being_dragged ? rl.Color{50, 60, 80, 240} : rl.Color{20, 20, 30, 200})

		for slot in 0 ..< sys.SLOTS_PER_BAR {
			rect := skill_slot_rect(bar, slot)
			name := sys.skill_bar_get(p, bar, slot)
			rl.DrawRectangleRec(rect, rl.Color{30, 30, 40, 220})
			rl.DrawRectangleLinesEx(rect, 1, rl.BLACK)
			if bar == 0 {
				sys.draw_text(fmt.tprintf("%d", (slot + 1) % 10), int(rect.x + 3), int(rect.y + 1), 10, rl.Color{150, 150, 150, 200})
			}
			if len(name) > 0 {
				cd_ms := sys.skill_cooldown_remaining(p, name)
				if cd_ms > 0 {
					rl.DrawRectangleRec(rect, rl.Color{0, 0, 0, 170})
					sys.draw_text(fmt.tprintf("%.0f", math.ceil(cd_ms / 1000.0)), int(rect.x + 10), int(rect.y + 10), 14, rl.WHITE)
				} else {
					tag := name
					if len(tag) > 3 do tag = tag[:3]
					sys.draw_text(tag, int(rect.x + 5), int(rect.y + 16), 11, rl.WHITE)
				}
				if p.casting.active && string(p.casting.skill_name[:p.casting.name_len]) == name {
					rl.DrawRectangleLinesEx(rect, 2, rl.ORANGE)
				}
				if rl.CheckCollisionPointRec(mouse, rect) && rl.IsMouseButtonPressed(.RIGHT) {
					sys.skill_bar_clear(p, bar, slot)
					sys.save_skill_bar(p)
				}
			}
		}
	}
}

draw_floating_text :: proc() {
	for &f in state.ctx.floating {
		// Behind-camera cull (same as nameplates in ecs.odin).
		cam := state.player.camera
		forward := rl.Vector3Normalize(cam.target - cam.position)
		if rl.Vector3DotProduct(forward, f.world_pos - cam.position) <= 0.0 do continue

		sp := rl.GetWorldToScreen(f.world_pos, cam)
		// GetWorldToScreen returns Vector2; off-screen cull only.
		alpha := u8(math.clamp(f.life, 0, 1) * 255.0)
		col := f.color
		col.a = alpha
		text: string = ""
		if f.is_miss {
			text = "miss"
		} else {
			text = fmt.tprintf("%s%d", f.is_heal ? "+" : "-", f.amount)
		}
		size := f.is_crit ? 22 : 16
		rise := int((1.0 - f.life) * 30)
		sys.draw_text(text, int(sp.x) - 8, int(sp.y) - 30 - rise, size, col)
	}
}

draw_chat :: proc() {
	// Last few chat lines bottom-left, above the HUD bars.
	y := 600
	start := len(state.chat.lines) - 8
	if start < 0 do start = 0
	for i in start ..< len(state.chat.lines) {
		line := state.chat.lines[i]
		sender := string(line.sender[:line.sender_len])
		message := string(line.message[:line.msg_len])
		text := fmt.tprintf("[%s] %s: %s", sys.chat_channel_name(line.channel), sender, message)
		col := sys.chat_channel_color(line.channel)
		sys.draw_text(text, 20, y, 14, col)
		y -= 18
	}

	// Chat input box.
	if state.chat_focused {
		box := rl.Rectangle{20, 620, 400, 24}
		rl.DrawRectangleRec(box, rl.Color{0, 0, 0, 200})
		rl.DrawRectangleLinesEx(box, 1, rl.WHITE)
		typed := string(state.chat_buf[:state.chat_len])
		sys.draw_text(fmt.tprintf("%s_", typed), 26, 624, 14, rl.WHITE)
	} else {
		sys.draw_text("Press Enter to chat", 20, 624, 12, rl.GRAY)
	}
}

draw_notifications :: proc() {
	y := 40
	for &n in state.ctx.notifications {
		alpha := u8(math.clamp(n.life, 0, 1) * 255.0)
		col := rl.WHITE
		if n.kind_len >= 5 && string(n.kind[:5]) == "error" do col = rl.RED
		col.a = alpha
		msg := string(n.message[:n.msg_len])
		sys.draw_text(msg, 540, y, 18, col)
		y += 24
	}
}

draw_death_overlay :: proc() {
	rl.DrawRectangle(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight(), rl.Color{80, 0, 0, 140})
	p := state.player

	// "You died" centered.
	msg := "You died"
	w := sys.measure_text(msg, 28)
	sys.draw_text(msg, int(rl.GetScreenWidth()) / 2 - w / 2, int(rl.GetScreenHeight()) / 2 - 20, 28, rl.WHITE)

	if p.respawn_sent {
		msg2 := "Respawning…"
		w2 := sys.measure_text(msg2, 18)
		sys.draw_text(msg2, int(rl.GetScreenWidth()) / 2 - w2 / 2, int(rl.GetScreenHeight()) / 2 + 40, 18, rl.Color{200, 200, 200, 255})
		return
	}

	// Respawn button (click to respawn at homepoint; or stay dead for revive).
	btn := death_respawn_btn_rect()
	mouse := rl.GetMousePosition()
	hov := rl.CheckCollisionPointRec(mouse, btn)
	col := hov ? rl.Color{70, 130, 210, 255} : rl.Color{55, 60, 75, 230}
	rl.DrawRectangleRec(btn, col)
	rl.DrawRectangleLinesEx(btn, 2, rl.WHITE)
	btn_msg := "Respawn at Homepoint"
	bw := sys.measure_text(btn_msg, 16)
	sys.draw_text(btn_msg, int(btn.x + btn.width / 2 - f32(bw) / 2), int(btn.y + 12), 16, rl.WHITE)
}
