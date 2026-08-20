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

// A ground AOE zone telegraph (Firestorm, Ice Tempest, Arrow Rain, ...) mirrored
// from AOE_ENTITY broadcasts. Fixed buffers keep it allocation-free; expiry is
// converted to local clock seconds so the render pass can drop stale zones.
AOE_Zone :: struct {
	id:          [64]u8,
	id_len:      int,
	skill_name:  [64]u8,
	name_len:    int,
	position:    rl.Vector3,
	radius:      f32,
	expire_at_s: f64,
}

// The local player's active song (song_* status effect). Songs toggle on/off
// server-side and each refresh re-broadcasts the effect list, so mirroring the
// presence/expiry of the effect is enough to drive the aura graphic.
Local_Song :: struct {
	active:     bool,
	type_str:   [24]u8,
	type_len:   int,
	expires_at: u64, // local ms, same clock as Status_Effect.expires_at
}

MAX_PARTY_MEMBERS :: 8

// One row of a PARTY_UPDATE members[] entry (shared/src/types/party.ts
// PartyMember). Fixed buffers, allocation-free after parse.
Party_Member_Info :: struct {
	char_id:    [64]u8,
	id_len:     int,
	name:       [32]u8,
	name_len:   int,
	level:      int,
	job_id:     [32]u8,
	job_len:    int,
	health:     f32,
	max_health: f32,
	is_leader:  bool,
	zone_id:    [32]u8,
	zone_len:   int,
}

// A pending party-loot roll / pool item pushed by PARTY_LOOT_ROLL.
Party_Loot_Roll :: struct {
	loot_id:   [64]u8,
	loot_len:  int,
	item_name: [48]u8,
	item_len:  int,
	quantity:  int,
	is_pool:   bool, // mode 'pool' (first-click take) vs 'need_greed' roll
}

// Client mirror of the server party (PartyData): membership, member stat
// snapshots (the server refreshes them on stat changes), pending loot rolls,
// and any invite awaiting the accept/decline dialog.
Party_State :: struct {
	in_party:   bool,
	party_id:   [64]u8,
	party_len:  int,
	leader_id:  [64]u8,
	leader_len: int,
	members:    [dynamic]Party_Member_Info,
	rolls:      [dynamic]Party_Loot_Roll,

	// Incoming invite (PARTY_INVITE) awaiting the accept/decline dialog.
	has_invite:         bool,
	invite_party_id:    [64]u8,
	invite_party_len:   int,
	invite_leader:      [32]u8,
	invite_leader_len:  int,
}

// One FRIEND_LIST entry (server FriendEntry).
Friend_Info :: struct {
	char_id: [64]u8,
	id_len:  int,
	name:    [32]u8,
	name_len: int,
	level:   int,
	online:  bool,
}

MAX_GUILD_MEMBERS :: 40

Guild_Member_Info :: struct {
	char_id: [64]u8,
	id_len:  int,
	name:    [32]u8,
	name_len: int,
	level:   int,
	rank:    [16]u8,
	rank_len: int,
	online:  bool,
}

Guild_Bank_Item :: struct {
	item_id:   [64]u8,
	item_len:  int,
	item_name: [48]u8,
	name_len:  int,
	quantity:  int,
}

Guild_Perms :: struct {
	invite:       bool,
	kick:         bool,
	promote:      bool,
	set_motd:     bool,
	bank_withdraw: bool,
	bank_deposit: bool,
}

// Client mirror of the server guild (GUILD_UPDATE payload): identity, XP,
// MOTD, bank, member rows, our rank + each rank's permissions.
Guild_State :: struct {
	in_guild:   bool,
	guild_id:   [64]u8,
	guild_len:  int,
	name:       [40]u8,
	name_len:   int,
	tag:        [8]u8,
	tag_len:    int,
	leader_id:  [64]u8,
	leader_len: int,
	level:      int,
	experience: int,
	xp_to_next: int,
	motd:       [255]u8,
	motd_len:   int,
	gold:       int,
	members:    [dynamic]Guild_Member_Info,
	bank:       [dynamic]Guild_Bank_Item,
	my_rank:    [16]u8,
	rank_len:   int,
	perms:      Guild_Perms, // effective permissions for my_rank

	// Incoming guild invite (GUILD_INVITE) awaiting the dialog.
	has_invite:      bool,
	invite_guild_id: [64]u8,
	invite_guild_len: int,
	invite_guild_name: [40]u8,
	invite_name_len: int,
	invite_by:       [32]u8,
	invite_by_len:   int,
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
	dialog:              Dialog_State,

	// Ground AOE zone telegraphs + the local player's active song aura.
	aoe_zones:           [dynamic]AOE_Zone,
	local_song:          Local_Song,

	// Party mirror (see Party_State).
	party:               Party_State,

	// Friends (server FriendSystem) + last whisper partner (for /r).
	friends:             [dynamic]Friend_Info,
	last_whisper:        [32]u8,
	last_whisper_len:    int,

	// Incoming friend request awaiting the accept/decline dialog.
	has_friend_req:      bool,
	friend_req_from:     [64]u8,
	friend_req_len:      int,
	friend_req_name:     [32]u8,
	friend_req_name_len: int,

	// Guild mirror (see Guild_State).
	guild:               Guild_State,

	// Ground loot bags (mirrors the server's activeLoot; keyed alongside the
	// scene entity that renders each bag).
	loot_bags:          [dynamic]Loot_Bag,

	// Overhead chat bubble for the local player (scene players keep theirs in
	// Scene.bubbles; the local player isn't part of the scene SoA).
	player_bubble:       Chat_Bubble,

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
	ctx.loot_bags = make([dynamic]Loot_Bag)
	ctx.pending_spawns = make([dynamic]JSON_Value)
	ctx.aoe_zones = make([dynamic]AOE_Zone)
	ctx.local_song = Local_Song{}
	ctx.party.members = make([dynamic]Party_Member_Info)
	ctx.party.rolls = make([dynamic]Party_Loot_Roll)
	ctx.friends = make([dynamic]Friend_Info)
	ctx.guild.members = make([dynamic]Guild_Member_Info)
	ctx.guild.bank = make([dynamic]Guild_Bank_Item)
	return ctx
}

game_context_destroy :: proc(ctx: ^Game_Context) {
	zone_destroy(ctx.zone) // nil-safe: frees the map + its owned strings
	ctx.zone = nil
	delete(ctx.notifications)
	delete(ctx.floating)
	delete(ctx.loot_bags)
	delete(ctx.pending_spawns)
	delete(ctx.aoe_zones)
	delete(ctx.party.members)
	delete(ctx.party.rolls)
	delete(ctx.friends)
	delete(ctx.guild.members)
	delete(ctx.guild.bank)
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
	case .NPC_DIALOG:
		handle_npc_dialog(ctx, p.data)
	case .QUEST_ACCEPT:
		handle_quest_accept(ctx, p.data)
	case .QUEST_PROGRESS:
		handle_quest_progress(ctx, p.data)
	case .QUEST_COMPLETE:
		handle_quest_complete(ctx, p.data)
	case .QUEST_ABANDON:
		handle_quest_abandon(ctx, p.data)
	case .ENHANCEMENT_RESULT:
		handle_enhancement_result(ctx, p.data)
	case .LOOT_SPAWN:
		handle_loot_spawn(ctx, p.data)
	case .LOOT_DESPAWN:
		handle_loot_despawn(ctx, p.data)
	case .LOOT_PICKUP:
		handle_loot_pickup(ctx, p.data)
	case .AOE_ENTITY:
		handle_aoe_entity(ctx, p.data)
	case .AOE_DESPAWN:
		handle_aoe_despawn(ctx, p.data)
	case .PARTY_UPDATE:
		handle_party_update(ctx, p.data)
	case .PARTY_INVITE:
		handle_party_invite(ctx, p.data)
	case .PARTY_DISBAND:
		handle_party_disband(ctx, p.data)
	case .PARTY_LOOT_ROLL:
		handle_party_loot_roll(ctx, p.data)
	case .PARTY_LOOT_RESULT:
		handle_party_loot_result(ctx, p.data)
	case .FRIEND_LIST:
		handle_friend_list(ctx, p.data)
	case .FRIEND_ADD_RESULT:
		handle_friend_add_result(ctx, p.data)
	case .FRIEND_STATUS:
		handle_friend_status(ctx, p.data)
	case .WHISPER:
		handle_whisper(ctx, p.data)
	case .FRIEND_REQUEST:
		handle_friend_request(ctx, p.data)
	case .GUILD_UPDATE:
		handle_guild_update(ctx, p.data)
	case .GUILD_INVITE:
		handle_guild_invite(ctx, p.data)
	case .ENTITY_GUILD_TAG:
		handle_entity_guild_tag(ctx, p.data)
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

	// Zone transition: drop all ground AOE telegraphs and the local song aura.
	clear(&ctx.aoe_zones)
	ctx.local_song = Local_Song{}

	// Party membership survives zone changes (server keeps it), but any
	// pending invite is stale after a zone switch.
	ctx.party.has_invite = false
	ctx.guild.has_invite = false
	ctx.has_friend_req = false

	// Refresh the friend list (online flags change with zone/reconnects).
	send_friend_list_request(ctx.net)

	spawn_entities_from_array(ctx, get_array(root, "enemies"), .ENEMY)
	spawn_entities_from_array(ctx, get_array(root, "npcs"), .NPC)
	spawn_entities_from_array(ctx, get_array(root, "players"), .PLAYER)
	spawn_entities_from_array(ctx, get_array(root, "summons"), .SUMMON)

	// Bags already on the ground when we joined (same shape as LOOT_SPAWN).
	clear(&ctx.loot_bags)
	bags := as_dyn(get_array(root, "lootBags"))
	for i in 0 ..< len(bags) {
		loot_spawn_bag(ctx, obj_of(bags[i]))
	}

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
		copy_string_to_buffer(ui.guild_tag[:], &ui.tag_len, get_string(d, "guildTag"))
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

// ── ground AOE zone telegraphs ──────────────────────────────────────────────

// Spawn (or refresh) a pulsing ground circle from an AOE_ENTITY broadcast:
// {id, type:'aoe', position, rotation, data:{skillName, radius, expiresAt}}.
// Cone one-shot payloads (coneVfx) carry no zone radius and are ignored.
handle_aoe_entity :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	root := obj_of(data^)
	if is_null(data^) do return

	d := get_object(root, "data")
	radius := get_f32(d, "radius", 0)
	expires_at := get_f64(d, "expiresAt", 0)
	if radius <= 0 || expires_at <= 0 do return

	id_str := get_string(root, "id")
	if len(id_str) == 0 do return

	z := AOE_Zone {
		radius       = radius,
		expire_at_s  = server_to_clock_seconds(ctx, u64(expires_at)),
	}
	copy_string_to_buffer(z.id[:], &z.id_len, id_str)
	copy_string_to_buffer(z.skill_name[:], &z.name_len, get_string(d, "skillName"))
	pos := vec3_from(root, "position")
	z.position = {pos[0], pos[1], pos[2]}

	// Replace any stale record for the same zone id.
	for i in 0..<len(ctx.aoe_zones) {
		if matches_name(ctx.aoe_zones[i].id[:], ctx.aoe_zones[i].id_len, id_str) {
			ctx.aoe_zones[i] = z
			return
		}
	}
	append(&ctx.aoe_zones, z)
}

// Remove a zone telegraph on AOE_DESPAWN: {entityId}.
handle_aoe_despawn :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	o := obj_of(data^)
	id_str := get_string(o, "entityId")
	if len(id_str) == 0 do return

	i := 0
	for i < len(ctx.aoe_zones) {
		if matches_name(ctx.aoe_zones[i].id[:], ctx.aoe_zones[i].id_len, id_str) {
			ordered_remove(&ctx.aoe_zones, i)
		} else {
			i += 1
		}
	}
}

// ── party ───────────────────────────────────────────────────────────────────

// PARTY_UPDATE: {partyId, leaderId, members[], settings, lootPool}.
// Members carry stat snapshots the server refreshes on stat changes; the
// gameplay panel shows the local player's live stats over their own row.
handle_party_update :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	root := obj_of(data^)
	if is_null(data^) do return

	p := &ctx.party
	p.in_party = true
	copy_string_to_buffer(p.party_id[:], &p.party_len, get_string(root, "partyId"))
	copy_string_to_buffer(p.leader_id[:], &p.leader_len, get_string(root, "leaderId"))

	clear(&p.members)
	dyn := as_dyn(get_array(root, "members"))
	for i in 0 ..< len(dyn) {
		if len(p.members) >= MAX_PARTY_MEMBERS do break
		o := obj_of(dyn[i])
		m := Party_Member_Info {
			level      = get_int(o, "level"),
			health     = get_f32(o, "health"),
			max_health = get_f32(o, "maxHealth"),
			is_leader  = get_bool(o, "isLeader"),
		}
		copy_string_to_buffer(m.char_id[:], &m.id_len, get_string(o, "characterId"))
		copy_string_to_buffer(m.name[:], &m.name_len, get_string(o, "characterName"))
		copy_string_to_buffer(m.job_id[:], &m.job_len, get_string(o, "jobId"))
		copy_string_to_buffer(m.zone_id[:], &m.zone_len, get_string(o, "zoneId"))
		append(&p.members, m)
	}
}

// PARTY_INVITE: {partyId, leaderName, settings, memberCount}. Stored; the
// gameplay layer opens the accept/decline dialog while has_invite is set.
handle_party_invite :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	root := obj_of(data^)
	if is_null(data^) do return

	p := &ctx.party
	p.has_invite = true
	copy_string_to_buffer(p.invite_party_id[:], &p.invite_party_len, get_string(root, "partyId"))
	copy_string_to_buffer(p.invite_leader[:], &p.invite_leader_len, get_string(root, "leaderName"))
}

// PARTY_DISBAND: we left, were kicked, or the party dissolved — clear all
// party state including pending loot rolls.
handle_party_disband :: proc(ctx: ^Game_Context, _data: ^JSON_Value) {
	p := &ctx.party
	p.in_party = false
	p.party_len = 0
	p.leader_len = 0
	p.has_invite = false
	p.invite_party_len = 0
	p.invite_leader_len = 0
	clear(&p.members)
	clear(&p.rolls)
}

// PARTY_LOOT_ROLL: {lootId, itemId, itemName, quantity, mode}. Pool items are
// first-click-take; need_greed items want a roll choice. The gameplay layer
// shows one window per pending entry.
handle_party_loot_roll :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	root := obj_of(data^)
	if is_null(data^) do return

	r := Party_Loot_Roll {
		quantity = get_int(root, "quantity", 1),
		is_pool  = get_string(root, "mode") == "pool",
	}
	loot_id := get_string(root, "lootId")
	if len(loot_id) == 0 do return
	copy_string_to_buffer(r.loot_id[:], &r.loot_len, loot_id)
	copy_string_to_buffer(r.item_name[:], &r.item_len, get_string(root, "itemName"))

	// Replace any stale entry for the same loot id.
	for i in 0 ..< len(ctx.party.rolls) {
		if matches_name(ctx.party.rolls[i].loot_id[:], ctx.party.rolls[i].loot_len, loot_id) {
			ctx.party.rolls[i] = r
			return
		}
	}
	append(&ctx.party.rolls, r)
}

// PARTY_LOOT_RESULT: resolved roll / pool claim — surface as a notification.
handle_party_loot_result :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	root := obj_of(data^)
	if is_null(data^) do return

	item := get_string(root, "itemName")
	winner := get_string(root, "winnerName")
	loot_id := get_string(root, "lootId")
	if len(loot_id) > 0 {
		i := 0
		for i < len(ctx.party.rolls) {
			if matches_name(ctx.party.rolls[i].loot_id[:], ctx.party.rolls[i].loot_len, loot_id) {
				ordered_remove(&ctx.party.rolls, i)
			} else {
				i += 1
			}
		}
	}
	if len(winner) > 0 {
		push_notification(ctx, fmt.tprintf("%s won %s", winner, item), "success")
	} else if len(item) > 0 {
		push_notification(ctx, fmt.tprintf("%s was not claimed", item), "info")
	}
}

// ── friends / whisper ───────────────────────────────────────────────────────

// FRIEND_LIST: {friends: [{characterId, name, level, online, ...}]}.
handle_friend_list :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	root := obj_of(data^)
	if is_null(data^) do return

	clear(&ctx.friends)
	dyn := as_dyn(get_array(root, "friends"))
	for i in 0 ..< len(dyn) {
		o := obj_of(dyn[i])
		f := Friend_Info {
			level  = get_int(o, "level"),
			online = get_bool(o, "online"),
		}
		copy_string_to_buffer(f.char_id[:], &f.id_len, get_string(o, "characterId"))
		copy_string_to_buffer(f.name[:], &f.name_len, get_string(o, "name"))
		append(&ctx.friends, f)
	}
}

// FRIEND_ADD_RESULT: {success, message} — plain notification.
handle_friend_add_result :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	o := obj_of(data^)
	if is_null(data^) do return
	msg := get_string(o, "message")
	if len(msg) > 0 {
		push_notification(ctx, msg, get_bool(o, "success") ? "success" : "error")
	}
}

// FRIEND_STATUS: {characterId, name, online} — update one entry in place and
// surface a "[name] came online / went offline" line.
handle_friend_status :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	o := obj_of(data^)
	if is_null(data^) do return

	id := get_string(o, "characterId")
	online := get_bool(o, "online")
	name := get_string(o, "name")

	for i in 0 ..< len(ctx.friends) {
		if !matches_name(ctx.friends[i].char_id[:], ctx.friends[i].id_len, id) do continue
		ctx.friends[i].online = online
		break
	}

	if len(name) > 0 {
		verb := online ? "came online." : "went offline."
		push_notification(ctx, fmt.tprintf("%s %s", name, verb), "info")
	}
}

// WHISPER (inbound echo + delivery): {fromName, toName, message}. Both sides
// render "From/To name: message"; incoming whispers set the /r reply target.
handle_whisper :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	o := obj_of(data^)
	if is_null(data^) do return

	from_name := get_string(o, "fromName")
	to_name := get_string(o, "toName")
	message := get_string(o, "message")
	if len(message) == 0 do return

	self_id := character_id_string(ctx.player)
	from_id := get_string(o, "from")
	if from_id == self_id {
		// Echo of our own whisper.
		if len(to_name) > 0 {
			chat_push(ctx.chat, .WHISPER, fmt.tprintf("To %s", to_name), message)
		}
		return
	}

	if len(from_name) > 0 {
		copy_string_to_buffer(ctx.last_whisper[:], &ctx.last_whisper_len, from_name)
		chat_push(ctx.chat, .WHISPER, fmt.tprintf("From %s", from_name), message)
	}
}

// FRIEND_REQUEST: {characterId, name, level} — stored; gameplay opens the
// accept/decline dialog while has_friend_req is set.
handle_friend_request :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	o := obj_of(data^)
	if is_null(data^) do return

	from := get_string(o, "characterId")
	if len(from) == 0 do return
	ctx.has_friend_req = true
	copy_string_to_buffer(ctx.friend_req_from[:], &ctx.friend_req_len, from)
	copy_string_to_buffer(ctx.friend_req_name[:], &ctx.friend_req_name_len, get_string(o, "name"))
}

// ── guild ───────────────────────────────────────────────────────────────────

// GUILD_UPDATE: full guild state (or {guildId: null} when guildless). Fills
// the Guild_State mirror, including the effective permissions for my rank.
handle_guild_update :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	root := obj_of(data^)
	if is_null(data^) do return

	g := &ctx.guild

	// guildId absent/null → we left / were kicked / it disbanded.
	guild_id := get_string(root, "guildId")
	if len(guild_id) == 0 {
		g.in_guild = false
		g.guild_len = 0
		g.name_len = 0
		g.tag_len = 0
		g.leader_len = 0
		g.motd_len = 0
		g.has_invite = false
		clear(&g.members)
		clear(&g.bank)
		return
	}

	g.in_guild = true
	copy_string_to_buffer(g.guild_id[:], &g.guild_len, guild_id)
	copy_string_to_buffer(g.name[:], &g.name_len, get_string(root, "name"))
	copy_string_to_buffer(g.tag[:], &g.tag_len, get_string(root, "tag"))
	copy_string_to_buffer(g.leader_id[:], &g.leader_len, get_string(root, "leaderId"))
	copy_string_to_buffer(g.motd[:], &g.motd_len, get_string(root, "motd"))
	copy_string_to_buffer(g.my_rank[:], &g.rank_len, get_string(root, "myRank"))
	g.level = get_int(root, "level", 1)
	g.experience = get_int(root, "experience")
	g.xp_to_next = get_int(root, "xpToNext", 1)
	g.gold = get_int(root, "gold")

	clear(&g.members)
	members := as_dyn(get_array(root, "members"))
	for i in 0 ..< len(members) {
		if len(g.members) >= MAX_GUILD_MEMBERS do break
		o := obj_of(members[i])
		m := Guild_Member_Info {
			level  = get_int(o, "level"),
			online = get_bool(o, "online"),
		}
		copy_string_to_buffer(m.char_id[:], &m.id_len, get_string(o, "characterId"))
		copy_string_to_buffer(m.name[:], &m.name_len, get_string(o, "name"))
		copy_string_to_buffer(m.rank[:], &m.rank_len, get_string(o, "rank"))
		append(&g.members, m)
	}

	clear(&g.bank)
	bank := as_dyn(get_array(root, "bankItems"))
	for i in 0 ..< len(bank) {
		o := obj_of(bank[i])
		b := Guild_Bank_Item {
			quantity = get_int(o, "quantity", 1),
		}
		copy_string_to_buffer(b.item_id[:], &b.item_len, get_string(o, "itemId"))
		copy_string_to_buffer(b.item_name[:], &b.name_len, get_string(o, "itemName"))
		append(&g.bank, b)
	}

	// Effective permissions for my rank (server resolves defaults + overrides).
	perms := get_object(root, "rankPerms")
	mine := get_object(perms, string(g.my_rank[:g.rank_len]))
	g.perms = Guild_Perms {
		invite        = get_bool(mine, "invite"),
		kick          = get_bool(mine, "kick"),
		promote       = get_bool(mine, "promote"),
		set_motd      = get_bool(mine, "setMotd"),
		bank_withdraw = get_bool(mine, "bankWithdraw"),
		bank_deposit  = get_bool(mine, "bankDeposit"),
	}
	// The leader implicitly has every permission.
	self_id := character_id_string(ctx.player)
	if matches_name(g.leader_id[:], g.leader_len, self_id) {
		g.perms = Guild_Perms{true, true, true, true, true, true}
	}
}

// GUILD_INVITE: {guildId, guildName, tag, inviterName} — stored; gameplay
// opens the accept/decline dialog while has_invite is set.
handle_guild_invite :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	root := obj_of(data^)
	if is_null(data^) do return

	g := &ctx.guild
	g.has_invite = true
	copy_string_to_buffer(g.invite_guild_id[:], &g.invite_guild_len, get_string(root, "guildId"))
	copy_string_to_buffer(g.invite_guild_name[:], &g.invite_name_len, get_string(root, "guildName"))
	copy_string_to_buffer(g.invite_by[:], &g.invite_by_len, get_string(root, "inviterName"))
}

// ENTITY_GUILD_TAG: {entityId, guildTag} — live nameplate tag update when a
// player joins/leaves a guild (empty tag clears it).
handle_entity_guild_tag :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	o := obj_of(data^)
	if is_null(data^) do return

	id := get_string(o, "entityId")
	if len(id) == 0 do return
	idx := find_index(ctx.scene, string_to_entity_id(id))
	if idx < 0 do return // not visible to us (other zone / despawned)

	copy_string_to_buffer(ctx.scene.ui[idx].guild_tag[:], &ctx.scene.ui[idx].tag_len, get_string(o, "guildTag"))
}

// ── ground loot bags ───────────────────────────────────────────────────────

// Spawn (or refresh) a loot bag entity from a LOOT_SPAWN / WORLD_STATE bag
// payload: {lootId, position, sourceName, items[{id,itemId,quantity,rarity}],
// assignedTo, assignmentExpiresAt}.
loot_spawn_bag :: proc(ctx: ^Game_Context, o: JSON_Object) {
	loot_id := get_string(o, "lootId")
	if len(loot_id) == 0 do return
	entity_id := string_to_entity_id(loot_id)

	// Replace any stale record for the same bag id.
	loot_remove_bag(ctx, entity_id)

	idx := add_entity(ctx.scene, entity_id)
	if idx < 0 do return
	set_entity_string_id(ctx.scene, idx, loot_id)

	pos := vec3_from(o, "position")
	ctx.scene.transforms[idx].position = {pos[0], pos[1], pos[2]}

	r := &ctx.scene.renderables[idx]
	r.shape = .BOX
	r.color = {230, 190, 70, 255}
	r.height = 0.9
	r.radius = 0.32
	ctx.scene.metas[idx].kind = .LOOT
	set_entity_name(ctx.scene, idx, get_string(o, "sourceName"))

	bag := Loot_Bag{entity_id = entity_id}
	copy_string_to_buffer(bag.loot_id[:], &bag.loot_len, loot_id)
	copy_string_to_buffer(bag.source[:], &bag.source_len, get_string(o, "sourceName"))
	copy_string_to_buffer(bag.assigned_to[:], &bag.assigned_len, get_string(o, "assignedTo"))

	items := as_dyn(get_array(o, "items"))
	n := min(len(items), MAX_LOOT_BAG_ITEMS)
	for i in 0 ..< n {
		it := obj_of(items[i])
		entry := &bag.items[i]
		copy_string_to_buffer(entry.entry_id[:], &entry.entry_len, get_string(it, "id"))
		copy_string_to_buffer(entry.item_id[:], &entry.item_len, get_string(it, "itemId"))
		entry.quantity = get_int(it, "quantity", 1)
	}
	bag.item_count = n
	append(&ctx.loot_bags, bag)
}

// Remove the scene entity + record for a bag (despawn / picked clean).
loot_remove_bag :: proc(ctx: ^Game_Context, entity_id: Entity_Id) {
	for i := 0; i < len(ctx.loot_bags); i += 1 {
		if ctx.loot_bags[i].entity_id == entity_id {
			for j := i; j < len(ctx.loot_bags) - 1; j += 1 {
				ctx.loot_bags[j] = ctx.loot_bags[j + 1]
			}
			resize(&ctx.loot_bags, len(ctx.loot_bags) - 1)
			break
		}
	}
	remove_entity(ctx.scene, entity_id)
}

loot_find_bag :: proc(ctx: ^Game_Context, entity_id: Entity_Id) -> ^Loot_Bag {
	for i in 0 ..< len(ctx.loot_bags) {
		if ctx.loot_bags[i].entity_id == entity_id do return &ctx.loot_bags[i]
	}
	return nil
}

handle_loot_spawn :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	if is_null(data^) do return
	loot_spawn_bag(ctx, obj_of(data^))
}

handle_loot_despawn :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	o := obj_of(data^)
	loot_id := get_string(o, "lootId")
	if len(loot_id) == 0 do return
	loot_remove_bag(ctx, string_to_entity_id(loot_id))
}

// LOOT_PICKUP arrives two ways: as the picker's ack {lootId, taken, rejected}
// and as the zone broadcast {lootId, by, taken}. In both, remove the taken
// quantities from the local bag copy; drop the bag when it runs empty (the
// picker's INVENTORY_UPDATE arrives as a separate packet).
handle_loot_pickup :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	o := obj_of(data^)
	loot_id := get_string(o, "lootId")
	if len(loot_id) == 0 do return
	bag := loot_find_bag(ctx, string_to_entity_id(loot_id))
	if bag == nil do return

	taken := as_dyn(get_array(o, "taken"))
	for i in 0 ..< len(taken) {
		t := obj_of(taken[i])
		item_id := get_string(t, "itemId")
		q := get_int(t, "quantity", 1)

		// Remove q units matching the item definition id (a stack may span
		// multiple entries; compaction keeps the array dense).
		e := 0
		for e < bag.item_count {
			if q <= 0 do break
			entry := &bag.items[e]
			if string(entry.item_id[:entry.item_len]) == item_id {
				take := min(entry.quantity, q)
				entry.quantity -= take
				q -= take
				if entry.quantity <= 0 {
					for j := e; j < bag.item_count - 1; j += 1 {
						bag.items[j] = bag.items[j + 1]
					}
					bag.item_count -= 1
					continue
				}
			}
			e += 1
		}
	}

	if bag.item_count == 0 do loot_remove_bag(ctx, bag.entity_id)
}

// Per-element floater colors (covers plain and magic_ prefixed types).
element_color :: proc(element: string) -> rl.Color {
	e := element
	if strings.has_prefix(e, "magic_") do e = e[len("magic_"):]
	switch e {
	case "fire":      return {255, 130, 40, 255}
	case "ice":       return {120, 200, 255, 255}
	case "lightning": return {255, 240, 90, 255}
	case "holy":      return {255, 250, 210, 255}
	case "dark":      return {190, 110, 255, 255}
	case "poison":    return {150, 240, 90, 255}
	case:             return {200, 150, 255, 255}
	}
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

	// Elemental bonus damage: the server sends it as a separate array on the
	// same DAMAGE packet — one additional floater line per element.
	if !missed {
		els := as_dyn(get_array(o, "elementalDamage"))
		for i in 0 ..< len(els) {
			el := obj_of(els[i])
			el_amount := get_int(el, "damage")
			if el_amount <= 0 do continue
			el_name := get_string(el, "element")
			push_floating(
				ctx, id, world_pos, el_amount,
				false, false, false, element_color(el_name),
			)
		}
	}
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
	sender := get_string(o, "sender", "")
	message := get_string(o, "message", "")
	channel := chat_channel_from_string(get_string(o, "channel", "zone"))
	chat_push(ctx.chat, channel, sender, message)
	attach_chat_bubble(ctx, sender, message, channel)
}

// Show the message over the speaker's head: the local player or a scene
// player whose entity name matches the sender. System messages get no bubble.
attach_chat_bubble :: proc(ctx: ^Game_Context, sender, message: string, channel: Chat_Channel) {
	if channel == .SYSTEM || len(sender) == 0 do return

	// The server prefixes GM/admin senders ("[GM] Alice"); entity names don't
	// carry the prefix, so strip it before matching.
	name := sender
	if strings.has_prefix(name, "[ADMIN] ") {
		name = name[len("[ADMIN] "):]
	} else if strings.has_prefix(name, "[GM] ") {
		name = name[len("[GM] "):]
	}

	if name == string(ctx.player.name[:ctx.player.name_len]) {
		chat_bubble_set(&ctx.player_bubble, message)
		return
	}

	s := ctx.scene
	for i in 0..<s.count {
		if s.metas[i].kind != .PLAYER do continue
		if s.ui[i].name_len == len(name) &&
		   string(s.ui[i].name_str[:s.ui[i].name_len]) == name {
			set_entity_chat_bubble(s, i, message)
			return
		}
	}
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

	// Quest log hydration (the payload carries the same `quests` array shape
	// the QUEST_* packets use).
	clear_quest_list(&p.quests)
	if has_field(o, "quests") {
		parse_quest_array(get_array(o, "quests"), &p.quests)
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
		free_owned_value(sub.data)
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

	now := now_ms_local()

	// The local player isn't part of the scene SoA, so mirror their active
	// song separately: the song_* effect only ever sits on the caster and is
	// re-broadcast (present or absent) whenever their effects change.
	song := &ctx.local_song
	song.active = false
	for i in 0..<len(dyn) {
		eff_obj := obj_of(dyn[i])
		t := get_string(eff_obj, "type")
		if !strings.has_prefix(t, "song_") do continue
		song.active = true
		n := min(len(t), len(song.type_str))
		copy(song.type_str[:n], transmute([]u8)t)
		song.type_len = n
		song.expires_at = now + u64(get_f64(eff_obj, "duration", 0))
		break
	}

	player_idx := find_index(ctx.scene, ctx.scene.player_id)
	if player_idx < 0 do return

	ef := &ctx.scene.effects[player_idx]
	ef.count = 0

	for i in 0..<len(dyn) {
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

// ── NPC dialog + quests ────────────────────────────────────────────────────

handle_npc_dialog :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	o := obj_of(data^)
	dialog_load_from_packet(&ctx.dialog, o)
}

// Hide the dialog and tell the server the conversation is over (clears the
// session's busy flag, which gates ATTACK/SKILL_USE server-side).
dialog_close_and_notify :: proc(ctx: ^Game_Context) {
	ctx.dialog.open = false
	send_npc_dialog_close(ctx.net)
}

handle_quest_accept :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	o := obj_of(data^)
	if has_field(o, "quests") {
		parse_quest_array(get_array(o, "quests"), &ctx.player.quests)
	}
	q := quest_find(ctx.player, get_string(o, "questId"))
	if q != nil {
		push_notification(ctx, fmt.tprintf("Quest accepted: %s", quest_title_string(q)), "success")
	} else {
		push_notification(ctx, "Quest accepted.", "success")
	}
	dialog_close_and_notify(ctx)
}

handle_quest_progress :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	o := obj_of(data^)
	if has_field(o, "quests") {
		parse_quest_array(get_array(o, "quests"), &ctx.player.quests)
	}
	msg := get_string(o, "message")
	if len(msg) > 0 {
		push_notification(ctx, msg, "info")
	}
}

handle_quest_complete :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	o := obj_of(data^)
	rew := get_object(o, "rewards")
	xp := get_int(rew, "experience")
	gold := get_int(rew, "gold")
	line := fmt.tprintf("Quest complete! +%d XP", xp)
	if gold > 0 {
		line = fmt.tprintf("%s, +%d gold", line, gold)
	}
	items := as_dyn(get_array(rew, "items"))
	for i in 0 ..< len(items) {
		it := obj_of(items[i])
		qty := get_int(it, "quantity")
		name := item_name(get_string(it, "itemId"))
		if qty > 1 {
			line = fmt.tprintf("%s, %s x%d", line, name, qty)
		} else {
			line = fmt.tprintf("%s, %s", line, name)
		}
	}
	push_notification(ctx, line, "success")
	dialog_close_and_notify(ctx)
}

handle_quest_abandon :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	o := obj_of(data^)
	if has_field(o, "quests") {
		parse_quest_array(get_array(o, "quests"), &ctx.player.quests)
	}
	push_notification(ctx, "Quest abandoned.", "info")
	dialog_close_and_notify(ctx)
}

// Enhancement outcome. Failures also produce a server NOTIFICATION (shown by
// handle_notification), so only successes raise one here.
handle_enhancement_result :: proc(ctx: ^Game_Context, data: ^JSON_Value) {
	if data == nil do return
	o := obj_of(data^)
	if !get_bool(o, "success") do return
	level := get_int(o, "enhancementLevel")
	elem := get_string(o, "enhancementElement")
	line := fmt.tprintf("Enhancement succeeded! +%d", level)
	if len(elem) > 0 {
		line = fmt.tprintf("%s (%s)", line, elem)
	}
	push_notification(ctx, line, "success")
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
	append(
		&ctx.floating,
		Floating_Text {
			entity_id = id,
			world_pos = world_pos,
			amount    = amount,
			color     = color,
			life      = 1.0,
			is_miss   = is_miss,
			is_heal   = is_heal,
			is_crit   = is_crit,
			stack_idx = stack,
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
