package systems

import "core:fmt"
import "core:math"
import "core:strings"
import rl "vendor:raylib"

// ── components ────────────────────────────────────────────────────────────

Transform :: struct {
	position: rl.Vector3,
	rotation: rl.Vector3, // Euler angles in degrees
	scale:    rl.Vector3,
}

// Renderable: the model to draw. For the procedural-primitives pass we share a
// handful of cached meshes (capsule/cylinder/box) rather than one model per
// entity; `shape` selects which.
Render_Shape :: enum u8 {
	NONE,
	CAPSULE, // players, enemies, summons, NPCs
	BOX,     // loot beacons, props
}

Renderable :: struct {
	shape:          Render_Shape,
	color:          rl.Color,
	height:         f32,   // visual height for the capsule/box
	radius:         f32,   // visual radius
	draw_wireframe: bool,
}

Interp_Point :: struct {
	x:    f32,
	y:    f32,
	z:    f32,
	time: f64,
}
Interp_Buffer :: struct {
	points: [16]Interp_Point,
	head:   int,
	count:  int,
}

// Per-entity metadata carried alongside the transform for rendering + logic.
Entity_Meta :: struct {
	kind:        Entity_Kind,
	health:      f32,
	max_health:  f32,
	level:       int,
	state:       [16]u8, // enemy state string ("idle"/"chase"/...), 0-terminated len kept separately
	state_len:   int,
	is_invisible: bool,
	is_resting:  bool,
}

Entity_UI :: struct {
	health_ratio: f32,
	show_name:    bool,
	name_str:     [32]u8,
	name_len:     int,
}

MAX_STATUS_EFFECTS :: 16

Status_Effect :: struct {
	type_str:   [24]u8,
	type_len:   int,
	is_buff:    bool,
	expires_at: u64,
}

Entity_Effects :: struct {
	count:   int,
	effects: [MAX_STATUS_EFFECTS]Status_Effect,
}

MAX_ENTITIES :: 1024

// ── scene (SoA) ───────────────────────────────────────────────────────────

Scene :: struct {
	active:            [MAX_ENTITIES]bool,
	entity_ids:        [MAX_ENTITIES]Entity_Id,
	// Original server-side string id for each entity (needed to send targetId,
	// npcId, etc. back to the server). Fixed buffer to stay allocation-free.
	string_ids:        [MAX_ENTITIES][64]u8,
	string_id_lens:    [MAX_ENTITIES]int,

	transforms:        [MAX_ENTITIES]Transform,
	renderables:       [MAX_ENTITIES]Renderable,
	metas:             [MAX_ENTITIES]Entity_Meta,
	ui:                [MAX_ENTITIES]Entity_UI,
	interp_bufs:       [MAX_ENTITIES]Interp_Buffer,
	effects:           [MAX_ENTITIES]Entity_Effects,
	bubbles:           [MAX_ENTITIES]Chat_Bubble,

	is_frozen:         [MAX_ENTITIES]bool,
	casts_shadow:      [MAX_ENTITIES]bool,
	dist_sq_to_player: [MAX_ENTITIES]f32,

	// Shared procedural models (built once in scene_init). All entities of a
	// given shape draw the same model, tinted/scaled per-entity.
	model_capsule:     rl.Model,
	model_box:         rl.Model,
	models_loaded:     bool,

	dynamic_avatar_cap: int,
	player_id:          Entity_Id,
	target_id:          Entity_Id, // selection indicator
	count:              int,
}

scene_init :: proc() -> ^Scene {
	s := new(Scene)
	s.dynamic_avatar_cap = 48
	s.target_id = INVALID_ENTITY

	// Build shared procedural models once. LoadModelFromMesh takes ownership of
	// the mesh, so we unload the *model* (not the mesh) on destroy.
	capsule_mesh := build_capsule_mesh(0.5, 1.8)
	box_mesh := rl.GenMeshCube(1, 1, 1)
	s.model_capsule = rl.LoadModelFromMesh(capsule_mesh)
	s.model_box = rl.LoadModelFromMesh(box_mesh)
	s.models_loaded = true
	return s
}

scene_destroy :: proc(s: ^Scene) {
	if s.models_loaded {
		rl.UnloadModel(s.model_capsule)
		rl.UnloadModel(s.model_box)
	}
	free(s)
}

// A capsule approximation: a cylinder body + two sphere caps. raylib has no
// direct capsule generator, so we approximate with a tall cylinder; it reads
// fine at game distances and is one draw call.
build_capsule_mesh :: proc(radius: f32, height: f32) -> rl.Mesh {
	m := rl.GenMeshCylinder(radius, height, 12)
	return m
}

find_index :: proc(s: ^Scene, id: Entity_Id) -> int {
	for i in 0..<s.count {
		if s.entity_ids[i] == id do return i
	}
	return -1
}

// Add an entity and return its index (swap-and-pop slot). Returns -1 if full.
add_entity :: proc(s: ^Scene, id: Entity_Id) -> int {
	if s.count >= MAX_ENTITIES do return -1
	idx := find_index(s, id)
	if idx != -1 do return idx // already present
	idx = s.count
	s.entity_ids[idx] = id
	s.active[idx] = true
	s.string_id_lens[idx] = 0
	s.transforms[idx] = {
		position = {0, 0, 0},
		rotation = {0, 0, 0},
		scale = {1, 1, 1},
	}
	s.renderables[idx] = {shape = .CAPSULE, color = rl.WHITE, height = 1.8, radius = 0.5}
	s.metas[idx] = {}
	s.ui[idx] = {}
	s.interp_bufs[idx] = {}
	s.bubbles[idx] = {}
	s.is_frozen[idx] = false
	s.casts_shadow[idx] = false
	s.count += 1
	return idx
}

remove_entity :: proc(s: ^Scene, id: Entity_Id) {
	idx := find_index(s, id)
	if idx == -1 do return

	// Swap-and-pop. No per-entity model to unload (shared meshes).
	last_idx := s.count - 1
	if idx != last_idx {
		s.entity_ids[idx] = s.entity_ids[last_idx]
		s.string_ids[idx] = s.string_ids[last_idx]
		s.string_id_lens[idx] = s.string_id_lens[last_idx]
		s.transforms[idx] = s.transforms[last_idx]
		s.renderables[idx] = s.renderables[last_idx]
		s.metas[idx] = s.metas[last_idx]
		s.ui[idx] = s.ui[last_idx]
		s.interp_bufs[idx] = s.interp_bufs[last_idx]
		s.bubbles[idx] = s.bubbles[last_idx]
		s.is_frozen[idx] = s.is_frozen[last_idx]
		s.casts_shadow[idx] = s.casts_shadow[last_idx]
	}
	s.count -= 1
	if s.target_id == id do s.target_id = INVALID_ENTITY
}

// Reset the scene (used on zone change / character-select return).
scene_clear :: proc(s: ^Scene) {
	s.count = 0
	s.target_id = INVALID_ENTITY
}

// Set a fixed-size name on an entity's UI slot.
set_entity_name :: proc(s: ^Scene, idx: int, name: string) {
	if idx < 0 || idx >= s.count do return
	n := min(len(name), len(s.ui[idx].name_str))
	s.ui[idx].name_len = n
	copy(s.ui[idx].name_str[:n], transmute([]u8)name)
	s.ui[idx].show_name = n > 0
}

set_entity_state :: proc(s: ^Scene, idx: int, state: string) {
	if idx < 0 || idx >= s.count do return
	n := min(len(state), len(s.metas[idx].state))
	s.metas[idx].state_len = n
	copy(s.metas[idx].state[:n], transmute([]u8)state)
}

// Store the server's original string id for an entity.
set_entity_string_id :: proc(s: ^Scene, idx: int, id: string) {
	if idx < 0 || idx >= s.count do return
	n := min(len(id), len(s.string_ids[idx]))
	s.string_id_lens[idx] = n
	copy(s.string_ids[idx][:n], transmute([]u8)id)
}

// Show `message` over the entity's head for the next CHAT_BUBBLE_DURATION_MS.
set_entity_chat_bubble :: proc(s: ^Scene, idx: int, message: string) {
	if idx < 0 || idx >= s.count do return
	chat_bubble_set(&s.bubbles[idx], message)
}

// Get the string id for an entity index, or "" if unset.
get_entity_string_id :: proc(s: ^Scene, idx: int) -> string {
	if idx < 0 || idx >= s.count do return ""
	return string(s.string_ids[idx][:s.string_id_lens[idx]])
}

euler_y_to_raylib :: proc "contextless" (y_rad: f32) -> (axis: rl.Vector3, angle: f32) {
	return {0, 1, 0}, y_rad * (180.0 / rl.PI)
}

// ── rendering ─────────────────────────────────────────────────────────────

render_entity_ui_2d :: proc(s: ^Scene, camera: rl.Camera3D) {
	screen_w := f32(rl.GetScreenWidth())
	screen_h := f32(rl.GetScreenHeight())

	for i in 0..<s.count {
		ui := &s.ui[i]
		t := &s.transforms[i]
		meta := &s.metas[i]

		if s.is_frozen[i] do continue
		if !ui.show_name && ui.health_ratio <= 0 && meta.kind != .NPC && !chat_bubble_active(&s.bubbles[i]) {
			continue
		}

		// Behind-camera cull: keep only entities in the camera's forward
		// hemisphere. GetWorldToScreen does not clip points behind the camera,
		// so without this they project to bogus on-screen positions and their
		// nameplates draw over the scene (e.g. behind the player).
		forward := rl.Vector3Normalize(camera.target - camera.position)
		to_entity := t.position - camera.position
		if rl.Vector3DotProduct(forward, to_entity) <= 0.0 do continue

		// Label position ~2.5 units above the entity origin.
		world_pos := rl.Vector3{t.position.x, t.position.y + 2.5, t.position.z}
		screen_pos := rl.GetWorldToScreen(world_pos, camera)

		if screen_pos.x < -50 || screen_pos.x > screen_w + 50 do continue
		if screen_pos.y < -50 || screen_pos.y > screen_h + 50 do continue

		dist := math.sqrt(s.dist_sq_to_player[i])
		ui_scale := math.clamp(1.0 - (dist / 60.0), 0.3, 1.0)

		ix := i32(screen_pos.x)
		iy := i32(screen_pos.y)
		font_sz := i32(16 * ui_scale)

		// Target indicator: blue circle at entity feet.
		if s.entity_ids[i] == s.target_id {
			feet_pos := rl.Vector3{t.position.x, t.position.y + 0.05, t.position.z}
			feet_sp := rl.GetWorldToScreen(feet_pos, camera)
			fx := i32(feet_sp.x)
			fy := i32(feet_sp.y)
			circle_r := i32(14 * ui_scale)
			rl.DrawCircleV(rl.Vector2{f32(fx), f32(fy)}, f32(circle_r), rl.Color{40, 100, 200, 100})
			rl.DrawCircleLinesV(rl.Vector2{f32(fx), f32(fy)}, f32(circle_r + 1), rl.Color{80, 160, 255, 180})
		}

		// NPC indicator: yellow "!" above the nameplate.
		if meta.kind == .NPC {
			mark_sz := i32(14 * ui_scale)
			mark_c := strings.clone_to_cstring("!", context.temp_allocator)
			mark_w := rl.MeasureText(mark_c, mark_sz)
			rl.DrawText(mark_c, ix - mark_w / 2, iy - 38, mark_sz, rl.YELLOW)
		}

		// Loot bags: gold label with the drop source, no level prefix.
		if meta.kind == .LOOT && ui.show_name && ui.name_len > 0 {
			name_c := strings.clone_to_cstring(
				string(ui.name_str[:ui.name_len]),
				context.temp_allocator,
			)
			text_w := rl.MeasureText(name_c, font_sz)
			rl.DrawText(name_c, ix - text_w / 2, iy - 20, font_sz, rl.Color{230, 190, 70, 255})
		} else if ui.show_name && ui.name_len > 0 {
			name_c := strings.clone_to_cstring(
				fmt.tprintf("Lv%d %s", meta.level, string(ui.name_str[:ui.name_len])),
				context.temp_allocator,
			)
			text_w := rl.MeasureText(name_c, font_sz)
			name_color := rl.WHITE
			if meta.kind == .ENEMY do name_color = {255, 150, 150, 255}
			if meta.kind == .NPC do name_color = {255, 255, 100, 255}
			rl.DrawText(name_c, ix - text_w / 2, iy - 20, font_sz, name_color)
		}

		// Health bar.
		if ui.health_ratio > 0.0 && ui.health_ratio < 1.0 {
			bar_w := i32(40 * ui_scale)
			bar_h := i32(4 * ui_scale)
			fill_w := i32(f32(bar_w) * ui.health_ratio)

			rl.DrawRectangle(ix - bar_w / 2, iy - 4, bar_w, bar_h, rl.Color{80, 0, 0, 255})

			bar_color := rl.GREEN
			if ui.health_ratio < 0.25 { bar_color = rl.RED
			} else if ui.health_ratio < 0.5 { bar_color = rl.YELLOW }
			rl.DrawRectangle(ix - bar_w / 2, iy - 4, fill_w, bar_h, bar_color)
			rl.DrawRectangleLines(ix - bar_w / 2, iy - 4, bar_w, bar_h, rl.BLACK)
		}

		// Target indicator: a small triangle above the targeted entity.
		if s.entity_ids[i] == s.target_id {
			rl.DrawPoly(
				rl.Vector2{f32(ix), f32(iy) - 34.0},
				3, 6 * ui_scale, 0.0,
				rl.YELLOW,
			)
		}

		// Overhead chat bubble (above the nameplate).
		draw_chat_bubble_at(&s.bubbles[i], ix, iy, ui_scale)
	}
}

// Draws a chat bubble anchored at (ix, iy) — the projected nameplate anchor —
// with a tail pointing down at the speaker's head. Slightly transparent, and
// fades out over the final half-second of its life.
draw_chat_bubble_at :: proc(bubble: ^Chat_Bubble, ix, iy: i32, scale: f32) {
	if bubble.msg_len == 0 || !chat_bubble_active(bubble) do return

	s := math.clamp(scale, 0.5, 1.0)
	text := string(bubble.message[:bubble.msg_len])
	font_sz := i32(14 * s)
	text_w := i32(measure_text(text, int(font_sz)))
	pad_x := i32(8 * s)
	pad_y := i32(4 * s)
	bw := text_w + pad_x * 2
	bh := font_sz + pad_y * 2

	fade := f32(1.0)
	remaining := bubble.expires_at - now_ms_local()
	if remaining < 500 do fade = math.clamp(f32(remaining) / 500.0, 0, 1)

	rec := rl.Rectangle{
		x      = f32(ix - bw / 2),
		y      = f32(iy - 44) - f32(bh),
		width  = f32(bw),
		height = f32(bh),
	}
	bg := rl.Color{250, 250, 250, u8(205 * fade)}
	rl.DrawRectangleRounded(rec, 0.4, 6, bg)
	rl.DrawRectangleRoundedLines(rec, 0.4, 6, rl.Color{70, 70, 90, u8(220 * fade)})

	// Speech-tail triangle pointing down at the head.
	cxf := f32(ix)
	ty := rec.y + rec.height - 0.5
	rl.DrawTriangle(
		{cxf + 5 * s, ty},
		{cxf - 5 * s, ty},
		{cxf, ty + 7 * s},
		bg,
	)

	draw_text(
		text,
		int(ix - text_w / 2),
		int(rec.y) + int(pad_y),
		int(font_sz),
		rl.Color{30, 30, 40, u8(235 * fade)},
	)
}

// Update: cull, then drive interpolation for non-player entities from their
// snapshot buffers. The local player's position is set directly by gameplay.
update :: proc(s: ^Scene, dt: f32, current_time: f64, player_pos: [3]f32, current_fps: int) {
	cull_and_sort(s, player_pos, current_fps)

	for i in 0..<s.count {
		if s.is_frozen[i] do continue
		if s.entity_ids[i] == s.player_id do continue

		interp_pos := get_interpolated_position(&s.interp_bufs[i], current_time, 0.15)
		// Only adopt the interpolated position once we have real samples (the
		// buffer returns {0,0,0} when it has < 2 points).
		if interp_pos[0] != 0 || interp_pos[1] != 0 || interp_pos[2] != 0 {
			s.transforms[i].position = {interp_pos[0], interp_pos[1], interp_pos[2]}
		}
	}
}

render :: proc(s: ^Scene, camera: rl.Camera3D) {
	rl.BeginMode3D(camera)

	for i in 0..<s.count {
		if s.is_frozen[i] do continue
		r := &s.renderables[i]
		t := &s.transforms[i]
		if r.shape == .NONE do continue

		// Sit the capsule/box so its base is on the entity origin.
		pos := rl.Vector3{t.position.x, t.position.y + r.height * 0.5, t.position.z}
		// t.rotation.y is stored as radians (the yaw we compute from input /
		// server quaternion); euler_y_to_raylib expects radians too.
		axis, angle := euler_y_to_raylib(t.rotation.y)
		scl := rl.Vector3{r.radius / 0.5, r.height / 1.8, r.radius / 0.5}

		#partial switch r.shape {
		case .CAPSULE:
			if r.draw_wireframe {
				rl.DrawModelWiresEx(s.model_capsule, pos, axis, angle, scl, r.color)
			} else {
				rl.DrawModelEx(s.model_capsule, pos, axis, angle, scl, r.color)
			}
		case .BOX:
			rl.DrawModelEx(s.model_box, pos, axis, angle, scl, r.color)
		case:
		}
	}

	rl.EndMode3D()
}

is_status_buff :: proc(type_str: string) -> bool {
	if type_str == "haste" do return true
	if type_str == "weapon_aura" do return true
	if type_str == "invisible" do return true
	if strings.has_prefix(type_str, "buff_") do return true
	if strings.has_prefix(type_str, "song_") do return true
	if strings.has_prefix(type_str, "barrier_") do return true
	return false
}

status_effect_label :: proc(type_str: string) -> (byte, byte) {
	if type_str == "poison" do return 'P', 's'
	if type_str == "burn" do return 'B', 'r'
	if type_str == "freeze" do return 'F', 'r'
	if type_str == "stun" do return 'S', 't'
	if type_str == "silence" do return 'S', 'i'
	if type_str == "sleep" do return 'S', 'l'
	if type_str == "bleed" do return 'B', 'l'
	if type_str == "root" do return 'R', 'o'
	if type_str == "slow" do return 'S', 'w'
	if type_str == "fear" do return 'F', 'e'
	if type_str == "curse" do return 'C', 'u'
	if type_str == "haste" do return 'H', 'a'
	if type_str == "mp_drain" do return 'M', 'd'
	if len(type_str) >= 2 do return type_str[0], type_str[1]
	return '?', '?'
}
