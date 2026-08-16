package systems

import "core:encoding/json"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

// ── game context ──────────────────────────────────────────────────────────
//
// Aggregates everything the gameplay layer and the packet dispatcher touch:
// the network client, the entity scene, the local player, the chat log, the
// loaded zone, and transient UI flags (notifications, floating text). The
// gameplay scene owns one of these and hands it to handle_packet() for each
// inbound packet drained from the network client.

Notification :: struct {
	message:  [256]u8,
	msg_len:  int,
	kind:     [32]u8, // "error" | "info" | ...
	kind_len: int,
	life:     f32, // seconds remaining on screen
}

Game_Context :: struct {
	net:                 ^Network_Client,
	scene:               ^Scene,
	player:              ^Local_Player,
	chat:                ^Chat_Log,
	zone:                ^Zone_Definition,
	zone_loaded:         bool,
	engine_ready:        bool,
	notifications:       [dynamic]Notification,
	floating:            [dynamic]Floating_Text,

	// Pending ENTITY_SPAWN packets that arrived before WORLD_STATE finished
	// loading (mirrors the TS client's pendingSpawns).
	pending_spawns:      [dynamic]JSON_Value,

	// Clock sync: server timestamp of the first packet we saw, mapped to our
	// local clock, so entity interpolation lines up with server time.
	server_time_base_ms: u64,
	local_time_base_ms:  u64,
	clock_synced:        bool,
}

game_context_init :: proc(
	net: ^Network_Client,
	scene: ^Scene,
	player: ^Local_Player,
	chat: ^Chat_Log,
) -> ^Game_Context {
	ctx := new(Game_Context)
	ctx.net = net
	ctx.scene = scene
	ctx.player = player
	ctx.chat = chat
	ctx.notifications = make([dynamic]Notification)
	ctx.floating = make([dynamic]Floating_Text)
	ctx.pending_spawns = make([dynamic]JSON_Value)
	return ctx
}

game_context_destroy :: proc(ctx: ^Game_Context) {
	delete(ctx.notifications)
	delete(ctx.floating)
	delete(ctx.pending_spawns)
	free(ctx)
}

// Convert a server timestamp (ms) to a clock comparable with get_time()-style
// seconds used by the interpolation buffer.
server_to_clock_seconds :: proc(ctx: ^Game_Context, server_ms: u64) -> f64 {
	if !ctx.clock_synced do return f64(rl.GetTime())
	elapsed_ms := f64(server_ms - ctx.server_time_base_ms)
	return f64(ctx.local_time_base_ms) / 1000.0 + elapsed_ms / 1000.0
}

sync_clock :: proc(ctx: ^Game_Context, server_ms: u64) {
	if ctx.clock_synced do return
	ctx.server_time_base_ms = server_ms
	ctx.local_time_base_ms = now_ms_local()
	ctx.clock_synced = true
}

now_ms_local :: proc "contextless" () -> u64 {
	return u64(rl.GetTime() * 1000.0)
}

// ── dispatch ──────────────────────────────────────────────────────────────

// Process one inbound packet. `free_after` should be true for packets drained
// from the network client (so we free the cloned data); false for replayed
// BATCH_COMBAT sub-events.
handle_packet :: proc(ctx: ^Game_Context, p: ^Packet, free_after: bool) {
	if p.data != nil {
		sync_clock(ctx, p.timestamp)
	}

	#partial switch p.type {
	case .WORLD_STATE:
		handle_world_state(ctx, p.data)
	case .PLAYER_POSITION_UPDATE:
		handle_position_update(ctx, p.data)
	case .ENTITY_SPAWN:
		handle_entity_spawn(ctx, p.data)
	case .ENTITY_DESPAWN:
		handle_entity_despawn(ctx, p.data)
	case .DAMAGE:
		handle_damage(ctx, p.data)
	case .HEAL:
		handle_heal(ctx, p.data)
	case .DEATH:
		handle_death(ctx, p.data)
	case .PLAYER_REVIVED:
		handle_player_revived(ctx, p.data)
	case .STATS_UPDATE:
		handle_stats_update(ctx, p.data)
	case .EXPERIENCE_GAIN:
		handle_experience(ctx, p.data)
	case .LEVEL_UP:
		handle_level_up(ctx, p.data)
	case .INVENTORY_UPDATE:
		handle_inventory_update(ctx, p.data)
	case .CHAT_MESSAGE:
		handle_chat(ctx, p.data)
	case .NOTIFICATION:
		handle_notification(ctx, p.data)
	case .ERROR:
		handle_error(ctx, p.data)
	case .COOLDOWN_UPDATE:
		handle_cooldown(ctx, p.data)
	case .SKILL_USE:
		handle_skill_use(ctx, p.data)
	case .STATUS_EFFECT_UPDATE:
		handle_status_effect_update(ctx, p.data)
	case .ENTITY_STATUS_EFFECTS:
		handle_entity_status_effects(ctx, p.data)
	case .ENEMY_STATE_CHANGE:
		handle_enemy_state(ctx, p.data)
	case .CHARACTER_SELECT:
		handle_character_select(ctx, p.data)
	case .CHARACTER_LIST:
	// handled by the character-select scene directly
	case .AUTH_SUCCESS:
		handle_auth_success_reconnect(ctx)
	case .AUTH_FAILURE:
	// handled by the login scene directly
	case .BATCH_COMBAT:
		handle_batch_combat(ctx, p.data)
	case:
	}

	if free_after && p.data != nil do free_packet(p)
}

// ── individual handlers ───────────────────────────────────────────────────

handle_world_state :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	root := obj_of(data^)
	if is_null(data^) do return

	// zone_id is a non-owning string view into the parsed packet data. The
	// packet is freed by handle_packet's caller after dispatch, so copy the id
	// into the player's owned fixed buffer for long-term use (HUD display).
	zone_id := get_string(root, "zoneId", "")
	copy_string_to_buffer(ctx.player.zone_id_buf[:], &ctx.player.zone_id_len, zone_id)

	// Load the static map (rendering); the server's zoneDef is metadata-only.
	if ctx.zone != nil do zone_destroy(ctx.zone)
	ctx.zone = load_zone_map(zone_id)
	ctx.zone_loaded = true
	ctx.engine_ready = true

	// Reset the entity scene and spawn everything from the snapshot.
	scene_clear(ctx.scene)
	ctx.scene.player_id = string_to_entity_id(character_id_string(ctx.player))

	spawn_entities_from_array(ctx, get_array(root, "enemies"), .ENEMY)
	spawn_entities_from_array(ctx, get_array(root, "npcs"), .NPC)
	spawn_entities_from_array(ctx, get_array(root, "players"), .PLAYER)
	spawn_entities_from_array(ctx, get_array(root, "summons"), .SUMMON)

	// Only reset position to spawn on first character select (position will
	// be 0,0,0). On reconnect, CHARACTER_SELECT already restored the saved
	// position, so don't overwrite it with spawn.
	pos := ctx.player.position
	if pos.x == 0 && pos.y == 0 && pos.z == 0 {
		if ctx.zone.loaded {
			ctx.player.position = ctx.zone.player_spawn
		} else {
			sp := vec3_from(root, "playerSpawn")
			ctx.player.position = as_vector3(sp)
		}
	}

	// Replay any spawns that arrived during load.
	for &ps in ctx.pending_spawns {
		handle_entity_spawn(ctx, &ps)
	}
	clear(&ctx.pending_spawns)
}

as_vector3 :: proc "contextless" (v: Vec3) -> rl.Vector3 {
	return {v[0], v[1], v[2]}
}

spawn_entities_from_array :: proc(ctx: ^Game_Context, arr: JSON_Array, kind: Entity_Kind) {
	dyn := as_dyn(arr)
	for i in 0 ..< len(dyn) {
		spawn_one_entity(ctx, obj_of(dyn[i]), kind)
	}
}

spawn_one_entity :: proc(ctx: ^Game_Context, o: JSON_Object, kind: Entity_Kind) {
	id_str := get_string(o, "id")
	if len(id_str) == 0 do return
	id := string_to_entity_id(id_str)
	if id == ctx.scene.player_id do return
	idx := add_entity(ctx.scene, id)
	if idx < 0 do return
	set_entity_string_id(ctx.scene, idx, id_str)

	t := &ctx.scene.transforms[idx]
	pos := vec3_from(o, "position")
	t.position = {pos[0], pos[1], pos[2]}
	rot := quat_from(o, "rotation")
	t.rotation = {0, quat_to_yaw(rot), 0}

	meta := &ctx.scene.metas[idx]
	meta.kind = kind

	d := get_object(o, "data")
	ui := &ctx.scene.ui[idx]
	r := &ctx.scene.renderables[idx]

	#partial switch kind {
	case .ENEMY:
		r.color = {200, 80, 80, 255}
		r.height = 1.6
		r.radius = 0.5
		meta.max_health = get_f32(d, "maxHealth", 100)
		meta.health = get_f32(d, "health", meta.max_health)
		meta.level = get_int(d, "level")
		set_entity_state(ctx.scene, idx, get_string(d, "state"))
		set_entity_name(ctx.scene, idx, get_string(d, "name"))
	case .NPC:
		r.color = {80, 180, 220, 255}
		r.height = 1.7
		r.radius = 0.5
		set_entity_name(ctx.scene, idx, get_string(d, "name"))
	case .PLAYER:
		r.color = {80, 220, 120, 255}
		r.height = 1.8
		r.radius = 0.5
		set_entity_name(ctx.scene, idx, get_string(d, "name"))
		meta.level = get_int(d, "level")
	case .SUMMON:
		r.color = {180, 120, 220, 255}
		r.height = 1.5
		r.radius = 0.45
		set_entity_name(ctx.scene, idx, get_string(d, "summonType"))
	case:
	}

	ui.health_ratio = meta.max_health > 0 ? meta.health / meta.max_health : 0.0
}

handle_position_update :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	root := obj_of(data^)
	if is_null(data^) do return

	// Form 1: batched enemies/summons.
	entities := get_array(root, "entities")
	if len(as_dyn(entities)) > 0 {
		dyn := as_dyn(entities)
		for i in 0 ..< len(dyn) {
			apply_entity_position(ctx, obj_of(dyn[i]))
		}
	}
	summons := get_array(root, "summons")
	if len(as_dyn(summons)) > 0 {
		dyn := as_dyn(summons)
		for i in 0 ..< len(dyn) {
			apply_entity_position(ctx, obj_of(dyn[i]))
		}
	}

	// Form 2: single other-player update.
	if len(as_dyn(entities)) == 0 && len(as_dyn(summons)) == 0 {
		character_id := get_string(root, "characterId")
		if len(character_id) == 0 do return
		id := string_to_entity_id(character_id)
		idx := find_index(ctx.scene, id)
		if idx == -1 {
			if id == ctx.scene.player_id do return
			idx = add_entity(ctx.scene, id)
			if idx >= 0 {
				ctx.scene.renderables[idx] = {
					shape  = .CAPSULE,
					color  = {80, 220, 120, 255},
					height = 1.8,
					radius = 0.5,
				}
				ctx.scene.metas[idx].kind = .PLAYER
			}
		}
		if idx >= 0 {
			pos := vec3_from(root, "position")
			push_interp(ctx, idx, pos)
			ctx.scene.metas[idx].is_invisible = get_bool(root, "invisible")
		}
	}
}

apply_entity_position :: proc(ctx: ^Game_Context, o: JSON_Object) {
	id_str := get_string(o, "id")
	if len(id_str) == 0 do return
	id := string_to_entity_id(id_str)
	idx := find_index(ctx.scene, id)
	if idx == -1 do return
	push_interp(ctx, idx, vec3_from(o, "position"))

	meta := &ctx.scene.metas[idx]
	if has_field(o, "health") {
		meta.health = get_f32(o, "health")
		h := meta.health
		m := meta.max_health > 0 ? meta.max_health : 1
		ctx.scene.ui[idx].health_ratio = h / m
	}
	if has_field(o, "state") {
		set_entity_state(ctx.scene, idx, get_string(o, "state"))
	}
}

push_interp :: proc(ctx: ^Game_Context, idx: int, pos: Vec3) {
	if idx < 0 do return
	t := server_to_clock_seconds(ctx, ctx.net.last_pong_recv_ms)
	// Use wall-clock time for the buffer; server timestamps are coarse.
	add_position_snapshot(&ctx.scene.interp_bufs[idx], pos[0], pos[1], pos[2], f64(rl.GetTime()))
}

handle_entity_spawn :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if !ctx.engine_ready {
		if data != nil do append(&ctx.pending_spawns, data^)
		return
	}
	if data == nil do return
	o := obj_of(data^)
	if is_null(data^) do return
	type_str := get_string(o, "type")
	kind: Entity_Kind = .PLAYER
	switch type_str {
	case "enemy":
		kind = .ENEMY
	case "npc":
		kind = .NPC
	case "summon":
		kind = .SUMMON
	case "player":
		kind = .PLAYER
	case:
	}
	spawn_one_entity(ctx, o, kind)
}

handle_entity_despawn :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	o := obj_of(data^)
	id_str := get_string(o, "entityId")
	if len(id_str) == 0 do return
	remove_entity(ctx.scene, string_to_entity_id(id_str))
}

handle_damage :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	o := obj_of(data^)
	target_id := get_string(o, "targetId")
	if len(target_id) == 0 do return

	missed := get_bool(o, "missed")
	amount := get_int(o, "damage")
	is_crit := get_bool(o, "isCritical")

	id := string_to_entity_id(target_id)
	idx := find_index(ctx.scene, id)
	world_pos: rl.Vector3
	if idx >= 0 {
		world_pos = ctx.scene.transforms[idx].position
		meta := &ctx.scene.metas[idx]
		if missed {
			amount = 0
		} else {
			meta.health -= f32(amount)
			m := meta.max_health > 0 ? meta.max_health : 1
			ctx.scene.ui[idx].health_ratio = max(0, meta.health) / m
		}
	} else if target_id == character_id_string(ctx.player) {
		world_pos = ctx.player.position
		ctx.player.stats.health -= f32(amount)
	}

	col := rl.Color{255, 80, 80, 255}
	if is_crit do col = rl.YELLOW
	push_floating(ctx, id, world_pos, amount, missed, false, is_crit, col)
}

handle_heal :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	o := obj_of(data^)
	target_id := get_string(o, "targetId")
	amount := get_int(o, "amount")
	if len(target_id) == 0 do return
	id := string_to_entity_id(target_id)
	idx := find_index(ctx.scene, id)
	world_pos: rl.Vector3
	if idx >= 0 {
		world_pos = ctx.scene.transforms[idx].position
		meta := &ctx.scene.metas[idx]
		meta.health += f32(amount)
	} else if target_id == character_id_string(ctx.player) {
		world_pos = ctx.player.position
		ctx.player.stats.health += f32(amount)
	}
	push_floating(ctx, id, world_pos, amount, false, true, false, rl.Color{80, 255, 120, 255})
}

handle_death :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	o := obj_of(data^)
	entity_id := get_string(o, "entityId")
	if len(entity_id) == 0 do return

	if entity_id == character_id_string(ctx.player) {
		ctx.player.is_dead = get_bool(o, "isDead", true)
		ctx.player.death_start_ms = 0
		ctx.player.respawn_sent = false
		return
	}
	id := string_to_entity_id(entity_id)
	idx := find_index(ctx.scene, id)
	if idx >= 0 {
		ctx.scene.metas[idx].health = 0
		ctx.scene.ui[idx].health_ratio = 0
		set_entity_state(ctx.scene, idx, "dead")
	}
}

// Server respawns the player at their homepoint → clears the death state,
// updates position + HP/MP so gameplay can resume immediately.
handle_player_revived :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	o := obj_of(data^)
	p := ctx.player
	p.is_dead = false
	p.is_resting = false
	p.death_start_ms = 0
	p.respawn_sent = false
	// Update position (respawn point).
	pos := get_object(o, "position")
	if !is_null(json.Value(pos)) {
		p.position.x = get_f32(pos, "x", p.position.x)
		p.position.y = get_f32(pos, "y", p.position.y)
		p.position.z = get_f32(pos, "z", p.position.z)
	}
	// Full HP/MP.
	s := &p.stats
	s.health = get_f32(o, "health", s.max_health)
	s.max_health = get_f32(o, "maxHealth", s.max_health)
}

// Parse the player's per-attribute allocations and per-sub-category skill
// points/proficiency from a CHARACTER_SELECT / STATS_UPDATE payload. All are
// optional; absent fields keep the existing value. Server field names:
//   statPoints          { STA, STR, AGI, DEX, SPI, INT } — spent stat points
//   skillProficiencies  { Slash, Thrust, … }            — spent skill points (the cap)
//   skillAdeptness      { Slash, Thrust, … }            — use-grown proficiency (≤ cap)
parse_allocated_stats :: proc(p: ^Local_Player, o: JSON_Object) {
	if !has_field(o, "statPoints") do return
	sp := get_object(o, "statPoints")
	for a in Attr {
		p.allocated_stats[a] = i32(get_f64(sp, attr_name(a), f64(p.allocated_stats[a])))
	}
}

parse_skill_proficiencies :: proc(p: ^Local_Player, o: JSON_Object) {
	if !has_field(o, "skillProficiencies") do return
	sp := get_object(o, "skillProficiencies")
	for sc in Sub_Category {
		p.allocated_skill_points[sc] = i32(
			get_f64(sp, sub_category_name(sc), f64(p.allocated_skill_points[sc])),
		)
	}
}

parse_skill_adeptness :: proc(p: ^Local_Player, o: JSON_Object) {
	if !has_field(o, "skillAdeptness") do return
	sa := get_object(o, "skillAdeptness")
	for sc in Sub_Category {
		p.skill_adeptness[sc] = f32(get_f64(sa, sub_category_name(sc), f64(p.skill_adeptness[sc])))
	}
}

handle_stats_update :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	o := obj_of(data^)

	// Self-targeted: carries `characterId` + `stats`.
	if has_field(o, "characterId") {
		cid := get_string(o, "characterId")
		if cid != character_id_string(ctx.player) do return
		stats := get_object(o, "stats")
		if !is_null(json.Value(stats)) {
			s := &ctx.player.stats
			s.health = get_f32(stats, "health", s.health)
			s.max_health = get_f32(stats, "maxHealth", s.max_health)
			s.mana = get_f32(stats, "mana", s.mana)
			s.max_mana = get_f32(stats, "maxMana", s.max_mana)
			s.attack = get_f32(stats, "attack", s.attack)
			s.defense = get_f32(stats, "defense", s.defense)
			s.level = get_int(stats, "level", s.level)
			s.experience = i64(get_f64(stats, "experience", f64(s.experience)))
			s.experience_to_next = i64(
				get_f64(stats, "experienceToNext", f64(s.experience_to_next)),
			)
		}
		if has_field(o, "unspentStatPoints") {
			ctx.player.unspent_stat_points = get_int(o, "unspentStatPoints")
		}
		if has_field(o, "unspentSkillPoints") {
			ctx.player.unspent_skill_points = get_int(o, "unspentSkillPoints")
		}
		parse_allocated_stats(ctx.player, o)
		parse_skill_proficiencies(ctx.player, o)
		parse_skill_adeptness(ctx.player, o)
		return
	}

	// Other-entity variant: {entityId, health, maxHealth, level?}
	if has_field(o, "entityId") {
		id := string_to_entity_id(get_string(o, "entityId"))
		idx := find_index(ctx.scene, id)
		if idx >= 0 {
			meta := &ctx.scene.metas[idx]
			meta.health = get_f32(o, "health")
			meta.max_health = get_f32(o, "maxHealth", meta.max_health)
			if has_field(o, "level") do meta.level = get_int(o, "level")
			m := meta.max_health > 0 ? meta.max_health : 1
			ctx.scene.ui[idx].health_ratio = meta.health / m
		}
	}
}

handle_experience :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	o := obj_of(data^)
	ctx.player.stats.experience = i64(
		get_f64(o, "totalExperience", f64(ctx.player.stats.experience)),
	)
	ctx.player.stats.level = get_int(o, "level", ctx.player.stats.level)
}

handle_level_up :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	o := obj_of(data^)
	ctx.player.stats.level = get_int(o, "level", ctx.player.stats.level)
	if has_field(o, "unspentStatPoints") {
		ctx.player.unspent_stat_points = get_int(o, "unspentStatPoints")
	}
	if has_field(o, "unspentSkillPoints") {
		ctx.player.unspent_skill_points = get_int(o, "unspentSkillPoints")
	}
	if has_field(o, "stats") {
		stats := get_object(o, "stats")
		s := &ctx.player.stats
		s.max_health = get_f32(stats, "maxHealth", s.max_health)
		s.health = s.max_health
		s.max_mana = get_f32(stats, "maxMana", s.max_mana)
	}
	push_notification(ctx, fmt.tprintf("Level Up! → %d", ctx.player.stats.level), "info")
}

handle_inventory_update :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	o := obj_of(data^)
	inv := &ctx.player.inventory
	clear(&inv.items)

	items := get_array(o, "inventory")
	dyn := as_dyn(items)
	for i in 0 ..< len(dyn) {
		it := obj_of(dyn[i])
		item: Inventory_Item
		// Copy strings into the item's owned fixed buffers so the inventory
		// outlives the packet (whose data is freed after dispatch).
		copy_string_to_buffer(item.item_id[:], &item.item_id_len, get_string(it, "itemId"))
		item.quantity = get_int(it, "quantity")
		item.slot = get_int(it, "slot")
		item.enhancement_level = get_int(it, "enhancementLevel")
		copy_string_to_buffer(
			item.enhancement_element[:],
			&item.enhancement_elem_len,
			get_string(it, "enhancementElement"),
		)
		append(&inv.items, item)
	}
	// equipment (13 slots) — store each equipped item directly (the server
	// removes equipped items from inventory, so they aren't in items[]).
	eq := get_object(o, "equipment")
	for slot in EQUIP_SLOT {
		name := EQUIP_SLOT_NAMES[int(slot)]
		es := &inv.equipment[int(slot)]
		es.item_id_len = 0 // clear (empty until proven otherwise)
		if has_field(eq, name) {
			eq_it := get_object(eq, name)
			if !is_null(json.Value(eq_it)) {
				copy_string_to_buffer(es.item_id[:], &es.item_id_len, get_string(eq_it, "itemId"))
				es.quantity = get_int(eq_it, "quantity")
				es.enhancement_level = get_int(eq_it, "enhancementLevel")
				copy_string_to_buffer(
					es.enhancement_element[:],
					&es.enhancement_elem_len,
					get_string(eq_it, "enhancementElement"),
				)
			}
		}
	}
}

// copy_field/copy_name were here — consolidated into copy_string_to_buffer
// (types.odin). Call sites below use that directly.

// String names for each equipment slot, parallel to the EQUIP_SLOT enum order.
EQUIP_SLOT_NAMES: [EQUIP_SLOT_COUNT]string = {
	"weapon",
	"armor",
	"helmet",
	"boots",
	"gloves",
	"legs",
	"shield",
	"earring_1",
	"earring_2",
	"necklace",
	"belt",
	"ring_1",
	"ring_2",
}

handle_chat :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	o := obj_of(data^)
	chat_push(
		ctx.chat,
		chat_channel_from_string(get_string(o, "channel", "zone")),
		get_string(o, "sender", ""),
		get_string(o, "message", ""),
	)
}

handle_notification :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	o := obj_of(data^)
	push_notification(ctx, get_string(o, "message"), get_string(o, "type", "info"))
}

handle_error :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	o := obj_of(data^)
	push_notification(ctx, get_string(o, "message"), "error")
}

handle_cooldown :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	o := obj_of(data^)
	kind := get_string(o, "type")
	skill := get_string(o, "skillName")
	switch kind {
	case "cast_start":
		ctx.player.casting.active = true
		ctx.player.casting.cast_time = get_f64(o, "castTime")
		ctx.player.casting.elapsed = 0
		copy_string_to_buffer(ctx.player.casting.skill_name[:], &ctx.player.casting.name_len, skill)
	case "cast_cancel":
		ctx.player.casting.active = false
	case "used":
		ctx.player.casting.active = false
		// Track remaining cooldown for the HUD.
		remaining := get_f64(o, "cooldownRemaining")
		found := false
		for i in 0 ..< len(ctx.player.cooldowns) {
			if matches_name(
				ctx.player.cooldowns[i].skill_name[:],
				ctx.player.cooldowns[i].name_len,
				skill,
			) {
				ctx.player.cooldowns[i].remaining_ms = remaining
				found = true
				break
			}
		}
		if !found {
			cd := Skill_Cooldown {
				remaining_ms = remaining,
			}
			copy_string_to_buffer(cd.skill_name[:], &cd.name_len, skill)
			append(&ctx.player.cooldowns, cd)
		}
	case:
	}
}

// Inbound SKILL_USE only carries an `error` field (the server's rejection
// reason). Successes produce no SKILL_USE echo — COOLDOWN_UPDATE / DAMAGE / etc.
// handle the positive feedback. Show rejections as a notification.
handle_skill_use :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	o := obj_of(data^)
	if !has_field(o, "error") do return
	skill := get_string(o, "skillName")
	err := get_string(o, "error")
	push_notification(ctx, fmt.tprintf("%s: %s", skill, skill_error_message(err)), "error")
}

skill_error_message :: proc "contextless" (err: string) -> string {
	switch err {
	case "cooldown":                   return "still on cooldown"
	case "no_mana":                    return "not enough MP"
	case "dead":                       return "you are dead"
	case "casting":                    return "already casting"
	case "gcd":                        return "not ready yet"
	case "not_found":                  return "unknown skill"
	case "passive":                    return "passive skill"
	case "insufficient_level":         return "level too low"
	case "insufficient_proficiency":   return "proficiency too low"
	case "silenced":                   return "silenced"
	case "no_target":                  return "no target"
	case "wrong_weapon":               return "wrong weapon type"
	case "no_shield":                  return "requires a shield"
	case "not_blocking":               return "must be blocking"
	case "blocking":                   return "can't use while blocking"
	case "field_blocked":              return "blocked by a field"
	case "pvp_disabled":               return "PvP is disabled here"
	case "out_of_range":               return "out of range"
	case "no_los":                     return "no line of sight"
	case "no_materials":               return "missing materials"
	case "party_member":               return "can't target a party member"
	case "not_in_party":               return "target not in your party"
	case "target_obelisk":             return "target is Obelisk-protected"
	case:                              return err
	}
}

handle_enemy_state :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	o := obj_of(data^)
	id := string_to_entity_id(get_string(o, "entityId", "enemy"))
	idx := find_index(ctx.scene, id)
	if idx >= 0 {
		set_entity_state(ctx.scene, idx, get_string(o, "state"))
	}
}

// CHARACTER_SELECT (server response): the full local-player state hydration.
// Mirrors characterHandlers.ts:230-258.
handle_character_select :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	o := obj_of(data^)
	if is_null(data^) do return

	p := ctx.player
	copy_string_to_buffer(p.character_id_buf[:], &p.character_id_len, get_string(o, "characterId"))
	copy_string_to_buffer(p.name[:], &p.name_len, get_string(o, "characterName"))
	// Load this character's skill bar (per-character file).
	load_skill_bar(p)
	// job_id / base_class are interned at the packet boundary (views are safe —
	// consumed before free_packet). base_class is kept as a typed enum even
	// though it's derivable from the job, since the server sends it explicitly.
	job_str := get_string(o, "jobId")
	if jid, ok := job_by_name(job_str); ok {
		p.job_id = jid
	} else {
		p.job_id = INVALID_JOB_ID
		net_log("character select: unknown job '%s'", job_str)
	}
	p.base_class = base_class_from_string(get_string(o, "baseClass"))
	// race is interned to a Race_Id (view is safe — consumed before free_packet).
	race_str := get_string(o, "race")
	if rid, ok := race_by_name(race_str); ok {
		p.race = rid
	} else {
		p.race = INVALID_RACE_ID
		net_log("character select: unknown race '%s'", race_str)
	}
	copy_string_to_buffer(p.zone_id_buf[:], &p.zone_id_len, get_string(o, "zoneId"))

	pos := vec3_from(o, "position")
	p.position = {pos[0], pos[1], pos[2]}

	stats := get_object(o, "stats")
	if !is_null(json.Value(stats)) {
		s := &p.stats
		s.health = get_f32(stats, "health")
		s.max_health = get_f32(stats, "maxHealth")
		s.mana = get_f32(stats, "mana")
		s.max_mana = get_f32(stats, "maxMana")
		s.attack = get_f32(stats, "attack")
		s.defense = get_f32(stats, "defense")
		s.speed = get_f32(stats, "speed")
		s.speed_multiplier = get_f32(stats, "speedMultiplier", 1.0)
		s.crit_chance = get_f32(stats, "critChance")
		s.cast_speed = get_f32(stats, "castSpeed")
		s.level = get_int(stats, "level")
		s.experience = i64(get_f64(stats, "experience"))
		s.experience_to_next = i64(get_f64(stats, "experienceToNext"))
	}

	// If the character was saved while dead (health <= 0), restore the dead
	// state so the death overlay shows and they can choose to respawn.
	if p.stats.health <= 0 && p.stats.max_health > 0 {
		p.is_dead = true
		p.death_start_ms = 0
		p.respawn_sent = false
	}

	if has_field(o, "unspentStatPoints") {
		p.unspent_stat_points = get_int(o, "unspentStatPoints")
	}
	if has_field(o, "unspentSkillPoints") {
		p.unspent_skill_points = get_int(o, "unspentSkillPoints")
	}
	parse_allocated_stats(p, o)
	parse_skill_proficiencies(p, o)
	parse_skill_adeptness(p, o)
	if has_field(o, "gold") {
		p.inventory.gold = i64(get_f64(o, "gold"))
	}

	// Inventory + equipment: the CHARACTER_SELECT payload has `inventory` and
	// `equipment` at the top level, the same shape INVENTORY_UPDATE expects.
	// Reuse that handler but pass the *packet's own* data node — do NOT build a
	// wrapper object, which would alias the inventory/equipment arrays and then
	// double-free them when both the wrapper and the packet are freed.
	if has_field(o, "inventory") {
		handle_inventory_update(ctx, data)
	}

	// The scene's player_id is set once WORLD_STATE arrives; set it now so any
	// packets that arrive before WORLD_STATE route correctly.
	ctx.scene.player_id = string_to_entity_id(character_id_string(p))
}

handle_batch_combat :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	o := obj_of(data^)
	events := get_array(o, "events")
	dyn := as_dyn(events)
	for i in 0 ..< len(dyn) {
		ev := obj_of(dyn[i])
		// event.type is a numeric PacketType, event.data is its payload.
		ev_type := field(ev, "type")
		ev_data := field(ev, "data")
		ptype, ok := int_to_packet_type(int(number_of(ev_type)))
		if !ok do continue
		sub := Packet {
			type = ptype,
			data = clone_value(ev_data),
		}
		handle_packet(ctx, &sub, false)
		free_value(sub.data)
	}
}

// ── status effects ──────────────────────────────────────────────────────────

handle_entity_status_effects :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	root := obj_of(data^)
	entity_id := get_string(root, "entityId")
	idx := find_index(ctx.scene, string_to_entity_id(entity_id))
	if idx < 0 do return

	now := now_ms_local()
	effects_arr := get_array(root, "effects")
	dyn := as_dyn(effects_arr)

	ef := &ctx.scene.effects[idx]
	ef.count = 0

	for i in 0 ..< len(dyn) {
		if ef.count >= MAX_STATUS_EFFECTS do break
		eff_obj := obj_of(dyn[i])
		e := &ef.effects[ef.count]

		t := get_string(eff_obj, "type")
		n := min(len(t), len(e.type_str))
		copy(e.type_str[:n], transmute([]u8)t)
		e.type_len = n
		e.is_buff = is_status_buff(t)

		duration := get_f64(eff_obj, "duration", 0)
		e.expires_at = now + u64(duration)

		ef.count += 1
	}
}

handle_status_effect_update :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	root := obj_of(data^)
	effects_arr := get_array(root, "effects")
	dyn := as_dyn(effects_arr)

	player_idx := find_index(ctx.scene, ctx.scene.player_id)
	if player_idx < 0 do return

	now := now_ms_local()
	ef := &ctx.scene.effects[player_idx]
	ef.count = 0

	for i in 0 ..< len(dyn) {
		if ef.count >= MAX_STATUS_EFFECTS do break
		eff_obj := obj_of(dyn[i])
		e := &ef.effects[ef.count]

		t := get_string(eff_obj, "type")
		n := min(len(t), len(e.type_str))
		copy(e.type_str[:n], transmute([]u8)t)
		e.type_len = n
		e.is_buff = is_status_buff(t)

		duration := get_f64(eff_obj, "duration", 0)
		e.expires_at = now + u64(duration)

		ef.count += 1
	}
}

// ── helpers ───────────────────────────────────────────────────────────────

matches_name :: proc "contextless" (buf: []u8, buf_len: int, s: string) -> bool {
	if buf_len != len(s) do return false
	for i in 0 ..< buf_len {
		if buf[i] != u8(s[i]) do return false
	}
	return true
}

push_notification :: proc(ctx: ^Game_Context, message, kind: string) {
	n := Notification {
		life = 4.0,
	}
	n.msg_len = min(len(message), len(n.message))
	copy(n.message[:n.msg_len], transmute([]u8)message)
	n.kind_len = min(len(kind), len(n.kind))
	copy(n.kind[:n.kind_len], transmute([]u8)kind)
	append(&ctx.notifications, n)
	if len(ctx.notifications) > 6 {
		_ = pop_front(&ctx.notifications)
	}
}

push_floating :: proc(
	ctx: ^Game_Context,
	id:    Entity_Id,
	world_pos: rl.Vector3,
	amount:    int,
	is_miss, is_heal, is_crit: bool,
	color:     rl.Color,
) {
	stack := 0
	for f in ctx.floating {
		if f.entity_id == id do stack += 1
	}
	offset_y := f32(stack * 14)
	append(
		&ctx.floating,
		Floating_Text {
			entity_id = id,
			world_pos = {world_pos.x, world_pos.y + offset_y, world_pos.z},
			amount    = amount,
			color     = color,
			life      = 1.0,
			is_miss   = is_miss,
			is_heal   = is_heal,
			is_crit   = is_crit,
		},
	)
}

handle_auth_success_reconnect :: proc(ctx: ^Game_Context) {
	nc := ctx.net
	fmt.printf(
		"[net] AUTH_SUCCESS in gameplay: auth_sent=%v char_select_sent=%v has_char_id=%v\n",
		nc.auth_sent,
		nc.char_select_sent,
		nc.auth_character_id_len > 0,
	)
	if nc.char_select_sent || !nc.auth_sent do return
	nc.auth_sent = true
	char_id := get_auth_character_id(nc)
	if len(char_id) > 0 {
		nc.char_select_sent = true
		send_character_select(nc, char_id)
		fmt.printf("[net] gameplay: re-auth complete, sending CHARACTER_SELECT id=%s\n", char_id)
	} else {
		fmt.printf("[net] gameplay: re-auth complete, but no character_id stored\n")
	}
}
