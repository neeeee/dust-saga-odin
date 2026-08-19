package gameplay

import sys "../../systems"
import "core:fmt"
import "core:math"
import "core:strings"
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
	draw_arrow_tracers()
	draw_ground_reticle_3d()
	draw_aoe_zones()
	draw_song_auras()
	rl.EndMode3D()

	// 2D entity nameplates / health bars / target indicators.
	sys.render_entity_ui_2d(state.scene, state.player.camera)
	draw_local_player_bubble()

	// 2D HUD.
	draw_hud()
	draw_target_window()
	draw_quest_tracker()
	draw_floating_text()
	draw_chat()
	draw_notifications()
	draw_ground_reticle_hint()
	draw_menu_bar()
	draw_menus()
	draw_dialog()
	if state.player.is_dead do draw_death_overlay()
}

// Ranged manual-attack arrows: short-lived tracer lines fading out.
draw_arrow_tracers :: proc() {
	for &a in state.arrows {
		t := math.clamp(a.life / ARROW_TRACER_LIFE, 0, 1)
		alpha := u8(t * 255.0)
		rl.DrawLine3D(a.from, a.to, rl.Color{200, 160, 90, alpha})
		head := rl.Vector3{a.to.x, a.to.y, a.to.z}
		rl.DrawCube(head, 0.12, 0.12, 0.12, rl.Color{240, 220, 160, alpha})
	}
}

// Ground-target reticle: a ring + center marker on the ground under the cursor.
draw_ground_reticle_3d :: proc() {
	gt := &state.ground_target
	if !gt.active do return
	ray := rl.GetScreenToWorldRay(rl.GetMousePosition(), state.player.camera)
	hit, point := sys.ray_ground_hit(ray, 0.0)
	if !hit do return
	rl.DrawCircle3D(point, gt.radius, {1, 0, 0}, 90.0, rl.Color{230, 120, 40, 210})
	rl.DrawCube(point, 0.5, 0.5, 0.5, rl.Color{230, 120, 40, 230})
}

// ── ground AOE / song aura graphics ────────────────────────────────────────

AOE_PULSE_HZ :: 1.4
SONG_PULSE_HZ :: 0.9
SONG_AURA_RADIUS :: 1.6
RIM_SEGMENTS :: 40

// A flat disc + rim ring on the ground whose brightness and rim radius breathe
// at `hz`. `fade` scales the alpha (used to fade zones out at expiry).
draw_pulsing_disc :: proc(center: rl.Vector3, radius: f32, col: rl.Color, hz: f64, fade: f32) {
	t := f32(rl.GetTime())
	pulse := 0.5 + 0.5 * math.sin(t * f32(hz) * 2.0 * math.PI)
	f := math.clamp(fade, 0, 1)

	disc := rl.Color{col.r, col.g, col.b, u8((26 + 40 * pulse) * f)}
	// DrawCircle3D lays the disc in the XY plane; rotate 90° about X to lay it
	// flat on the XZ ground plane.
	rl.DrawCircle3D(center, radius, {1, 0, 0}, 90.0, disc)

	rim_r := radius * (0.92 + 0.08 * pulse)
	rim := rl.Color{col.r, col.g, col.b, u8((150 + 90 * pulse) * f)}
	for i in 0..<RIM_SEGMENTS {
		a0 := f32(i) / f32(RIM_SEGMENTS) * 2.0 * math.PI
		a1 := f32(i + 1) / f32(RIM_SEGMENTS) * 2.0 * math.PI
		rl.DrawLine3D(
			{center.x + math.cos(a0) * rim_r, center.y, center.z + math.sin(a0) * rim_r},
			{center.x + math.cos(a1) * rim_r, center.y, center.z + math.sin(a1) * rim_r},
			rim,
		)
	}
}

// Element-ish tint for a ground AOE zone from its skill name. "Arrow" is
// matched first so Arrow Storm/Rain don't hit the Thunderstorm branch.
aoe_zone_color :: proc(skill: string) -> rl.Color {
	switch {
	case strings.contains(skill, "Arrow"):
		return {230, 200, 130, 255}
	case strings.contains(skill, "Ice"):
		return {140, 210, 255, 255}
	case strings.contains(skill, "Fire") || strings.contains(skill, "Meteor"):
		return {255, 140, 70, 255}
	case strings.contains(skill, "Thunder"):
		return {255, 230, 110, 255}
	case strings.contains(skill, "Holy"):
		return {255, 245, 190, 255}
	case strings.contains(skill, "Dark") || strings.contains(skill, "Despair") ||
		strings.contains(skill, "Void") || strings.contains(skill, "Wasteland") ||
		strings.contains(skill, "Pestilence") || strings.contains(skill, "Swamp"):
		return {180, 110, 230, 255}
	case:
		return {200, 160, 255, 255}
	}
}

song_color :: proc(type_str: string) -> rl.Color {
	switch {
	case strings.contains(type_str, "green"):
		return {90, 220, 120, 255}
	case strings.contains(type_str, "blue"):
		return {90, 160, 255, 255}
	case strings.contains(type_str, "yellow"):
		return {240, 220, 90, 255}
	case strings.contains(type_str, "red"):
		return {255, 100, 90, 255}
	case:
		return {200, 160, 255, 255}
	}
}

// Pulsing circles for active ground AOE zones (Ice Tempest, Arrow Rain, ...),
// mirrored from AOE_ENTITY broadcasts; each fades out just before expiry.
draw_aoe_zones :: proc() {
	ctx := state.ctx
	if ctx == nil do return
	t := f64(rl.GetTime())
	for &z in ctx.aoe_zones {
		if t >= z.expire_at_s do continue
		fade := f32(min(z.expire_at_s - t, 0.4) / 0.4)
		center := rl.Vector3{z.position.x, z.position.y + 0.05, z.position.z}
		draw_pulsing_disc(
			center,
			z.radius,
			aoe_zone_color(string(z.skill_name[:z.name_len])),
			AOE_PULSE_HZ,
			fade,
		)
	}
}

// Pulsing circle under any entity with an active song_* status effect (i.e.
// the singer), plus the local player's own song mirrored from
// STATUS_EFFECT_UPDATE. Follows the caster as they move.
draw_song_auras :: proc() {
	ctx := state.ctx
	if ctx == nil do return
	now := sys.now_ms_local()

	s := state.scene
	for i in 0..<s.count {
		ef := &s.effects[i]
		for j in 0..<ef.count {
			e := &ef.effects[j]
			if now >= e.expires_at do continue
			type_str := string(e.type_str[:e.type_len])
			if !strings.has_prefix(type_str, "song_") do continue
			p := s.transforms[i].position
			draw_pulsing_disc(
				{p.x, p.y + 0.05, p.z},
				SONG_AURA_RADIUS,
				song_color(type_str),
				SONG_PULSE_HZ,
				1.0,
			)
			break
		}
	}

	song := &ctx.local_song
	if song.active && now < song.expires_at {
		p := state.player.position
		draw_pulsing_disc(
			{p.x, p.y + 0.05, p.z},
			SONG_AURA_RADIUS,
			song_color(string(song.type_str[:song.type_len])),
			SONG_PULSE_HZ,
			1.0,
		)
	}
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

// Overhead chat bubble over the local player's head (same anchor — y+2.5 —
// and style as the scene-entity bubbles drawn in ecs.odin).
draw_local_player_bubble :: proc() {
	if state.ctx == nil do return
	bubble := &state.ctx.player_bubble
	if !sys.chat_bubble_active(bubble) do return

	cam := state.player.camera
	p := state.player.position
	world := rl.Vector3{p.x, p.y + 2.5, p.z}
	forward := rl.Vector3Normalize(cam.target - cam.position)
	if rl.Vector3DotProduct(forward, world - cam.position) <= 0.0 do return

	sp := rl.GetWorldToScreen(world, cam)
	sys.draw_chat_bubble_at(bubble, i32(sp.x), i32(sp.y), 1.0)
}

draw_hud :: proc() {
	// Player plate top-left (Pandora Saga layout): buffs (not yet implemented)
	// go above, then name/level, then HP and MP bars.
	s := &state.player.stats
	hp_ratio := s.max_health > 0 ? s.health / s.max_health : 0
	mp_ratio := s.max_mana > 0 ? s.mana / s.max_mana : 0

	sys.draw_text(
		fmt.tprintf("Lv %d  %s", s.level, string(state.player.name[:state.player.name_len])),
		22,
		34,
		18,
		rl.WHITE,
	)
	draw_bar(
		20,
		56,
		240,
		18,
		hp_ratio,
		rl.RED,
		fmt.tprintf("HP %d/%d", i32(s.health), i32(s.max_health)),
	)
	draw_bar(
		20,
		78,
		240,
		14,
		mp_ratio,
		rl.BLUE,
		fmt.tprintf("MP %d/%d", i32(s.mana), i32(s.max_mana)),
	)

	// Auto-attack state indicator (F toggles, Esc cancels).
	if state.auto_attack_active {
		sys.draw_text("Auto-attack", 22, 100, 16, rl.Color{255, 200, 80, 255})
	}

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
		// Each concurrent floater on this entity gets its own screen row
		// (multi-hit hits + elemental lines stack downward).
		stack_off := f.stack_idx * 18
		sys.draw_text(text, int(sp.x) - 8, int(sp.y) - 30 - rise - stack_off, size, col)
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

// Active-quest tracker, top-right under the connection status.
draw_quest_tracker :: proc() {
	x := int(rl.GetScreenWidth()) - 330
	y := 44
	for i in 0 ..< len(state.player.quests) {
		q := &state.player.quests[i]
		if q.status == .TURNED_IN || q.status == .AVAILABLE do continue
		sys.draw_text(sys.quest_title_string(q), x, y, 14, rl.Color{255, 210, 90, 255})
		y += 18
		if q.status == .COMPLETED {
			sys.draw_text("  Return to the quest giver", x, y, 12, rl.Color{120, 230, 120, 255})
			y += 16
		} else {
			for j in 0 ..< len(q.objectives) {
				o := &q.objectives[j]
				done := o.current >= o.required
				col := done ? rl.Color{120, 230, 120, 255} : rl.Color{200, 200, 200, 255}
				sys.draw_text(
					fmt.tprintf("  %s %d/%d", sys.objective_name_string(o), o.current, o.required),
					x, y, 12, col,
				)
				y += 16
			}
		}
		y += 8
		if y > 300 do break
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
