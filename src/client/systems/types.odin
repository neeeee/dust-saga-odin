package systems

import rl "vendor:raylib"

// Game-state structs mirroring packages/shared/src/types/{player,items}.ts and
// the per-packet payloads the server sends. These hold the *local player's*
// authoritative-from-server state (the server is the source of truth; the
// client only renders + predicts movement).

// ── entity identity ───────────────────────────────────────────────────────

Entity_Id :: distinct u32
INVALID_ENTITY :: Entity_Id(0)

string_to_entity_id :: proc(s: string) -> Entity_Id {
	// FNV-1a over the id string → stable hash. +1 so we never collide with
	// INVALID_ENTITY (0).
	return Entity_Id(fnv1a_32(s) + 1)
}

fnv1a_32 :: proc "contextless" (s: string) -> u32 {
	h: u32 = 0x811C9DC5
	PRIME: u32 = 0x01000193
	for c in s {
		h = h ~ u32(c)
		h = h * PRIME
	}
	return h
}

Entity_Kind :: enum u8 {
	PLAYER,
	ENEMY,
	NPC,
	SUMMON,
	LOOT,
	AOE,
}

// ── stats (mirrors PlayerStats) ───────────────────────────────────────────

Player_Stats :: struct {
	health:             f32,
	max_health:         f32,
	mana:               f32,
	max_mana:           f32,
	attack:             f32,
	defense:            f32,
	speed:              f32,
	speed_multiplier:   f32,
	magic_attack:       f32,
	crit_chance:        f32,
	cast_speed:         f32,
	level:              int,
	experience:         i64,
	experience_to_next: i64,
}

// ── inventory / equipment (mirrors InventoryItem + Equipment) ─────────────

EQUIP_SLOT :: enum {
	WAPON,
	ARMOR,
	HELMET,
	BOOTS,
	GLOVES,
	LEGS,
	SHIELD,
	EARRING_1,
	EARRING_2,
	NECKLACE,
	BELT,
	RING_1,
	RING_2,
}
EQUIP_SLOT_COUNT :: len(EQUIP_SLOT)

Inventory_Item :: struct {
	item_id:              [64]u8,
	item_id_len:          int,
	quantity:             int,
	slot:                 int,
	enhancement_level:    int,
	enhancement_element:  [32]u8,
	enhancement_elem_len: int,
}

// Read the item_id of an Inventory_Item as an Odin string view (valid as long
// as the item lives — the bytes are owned by the struct, not a packet).
item_id_string :: proc "contextless" (it: ^Inventory_Item) -> string {
	return string(it.item_id[:it.item_id_len])
}

// Copy a string into a fixed [N]u8 buffer + companion length, truncating to
// fit. The single owned-buffer setter used across packet parsing and the
// character-select scene (replaces the former copy_field / copy_name dupes).
copy_string_to_buffer :: proc "contextless" (dst: []u8, dst_len: ^int, src: string) {
	n := min(len(src), len(dst))
	dst_len^ = n
	copy(dst[:n], transmute([]u8)src)
}

// Read the local player's character_id as an owned string view.
character_id_string :: proc "contextless" (p: ^Local_Player) -> string {
	return string(p.character_id_buf[:p.character_id_len])
}

Inventory :: struct {
	items:     [dynamic]Inventory_Item,
	gold:      i64,
	// equipment[slot] is an index into items, or -1 if empty.
	equipment: [EQUIP_SLOT_COUNT]int,
}

inventory_init :: proc(inv: ^Inventory) {
	inv.items = make([dynamic]Inventory_Item)
	for i in 0 ..< EQUIP_SLOT_COUNT {
		inv.equipment[i] = -1
	}
}

inventory_destroy :: proc(inv: ^Inventory) {
	delete(inv.items)
}

// ── chat ──────────────────────────────────────────────────────────────────

Chat_Channel :: enum u8 {
	GLOBAL,
	ZONE,
	PARTY,
	SYSTEM,
}

chat_channel_from_string :: proc "contextless" (s: string) -> Chat_Channel {
	switch s {
	case "global":
		return .GLOBAL
	case "party":
		return .PARTY
	case "system":
		return .SYSTEM
	case:
		return .ZONE
	}
}

chat_channel_color :: proc "contextless" (c: Chat_Channel) -> rl.Color {
	#partial switch c {
	case .GLOBAL:
		return {120, 200, 255, 255}
	case .PARTY:
		return {120, 255, 150, 255}
	case .SYSTEM:
		return {255, 220, 120, 255}
	case:
		return {220, 220, 220, 255}
	}
}

chat_channel_name :: proc "contextless" (c: Chat_Channel) -> string {
	#partial switch c {
	case .GLOBAL:
		return "global"
	case .PARTY:
		return "party"
	case .SYSTEM:
		return "system"
	case:
		return "zone"
	}
}

CHAT_MAX_LINES :: 50
CHAT_LINE_MAX :: 256

Chat_Line :: struct {
	channel:    Chat_Channel,
	sender:     [64]u8,
	sender_len: int,
	message:    [CHAT_LINE_MAX]u8,
	msg_len:    int,
}

Chat_Log :: struct {
	lines: [dynamic]Chat_Line,
}

chat_init :: proc(log: ^Chat_Log) {
	log.lines = make([dynamic]Chat_Line)
}

chat_destroy :: proc(log: ^Chat_Log) {
	delete(log.lines)
}

chat_push :: proc(log: ^Chat_Log, channel: Chat_Channel, sender, message: string) {
	line := Chat_Line {
		channel = channel,
	}
	line.sender_len = min(len(sender), len(line.sender))
	copy(line.sender[:line.sender_len], transmute([]u8)sender)
	line.msg_len = min(len(message), CHAT_LINE_MAX)
	copy(line.message[:line.msg_len], transmute([]u8)message)
	append(&log.lines, line)
	if len(log.lines) > CHAT_MAX_LINES {
		// drop oldest (index 0)
		_ = pop_front(&log.lines)
	}
}

// ── cooldown / cast state ─────────────────────────────────────────────────

Cast_State :: struct {
	skill_name: [64]u8,
	name_len:   int,
	cast_time:  f64, // total cast duration (ms)
	elapsed:    f64, // time since cast_start (ms)
	active:     bool,
}

Skill_Cooldown :: struct {
	skill_name:   [64]u8,
	name_len:     int,
	remaining_ms: f64, // counts down
}

// ── floating combat text ──────────────────────────────────────────────────

Floating_Text :: struct {
	entity_id: Entity_Id,
	world_pos: rl.Vector3,
	amount:    int,
	color:     rl.Color,
	life:      f32, // seconds remaining
	is_miss:   bool,
	is_heal:   bool,
	is_crit:   bool,
}

// ── the local player ──────────────────────────────────────────────────────

Local_Player :: struct {
	// identity
	player_id:             string,
	// character_id is the routing key compared in every damage/heal/death/stats
	// packet, so it must outlive the CHARACTER_SELECT packet that delivered it.
	// Stored in an owned fixed buffer.
	character_id_buf:      [64]u8,
	character_id_len:      int,
	name:                  [64]u8,
	name_len:              int,
	username:              string,
	token:                 string,
	role:                  string, // 'player' | 'gm' | 'admin'

	// class / job
	job_id:                Job_Id,
	base_class:            Base_Class,
	race:                  Race_Id,
	// zone id is stored in an owned fixed buffer (the server-sent string is a
	// view into a packet that gets freed after dispatch).
	zone_id_buf:           [64]u8,
	zone_id_len:           int,

	// transform (client-predicted; reconciled by server position updates)
	position:              rl.Vector3,
	yaw:                   f32, // facing angle (radians), atan2(dir.x, dir.z)
	camera:                rl.Camera3D,
	// progression
	stats:                 Player_Stats,
	unspent_stat_points:   int,
	unspent_skill_points:  int,
	// per-attribute stat allocations + per-sub-category skill points/proficiency
	// (server-authoritative; parsed from CHARACTER_SELECT / STATS_UPDATE).
	// allocated_stats      ← session.statPoints         (spent stat points)
	// allocated_skill_points ← session.skillProficiencies (spent skill points = the cap)
	// skill_adeptness      ← session.skillAdeptness      (use-grown proficiency, ≤ allocated)
	allocated_stats:         [Attr]i32,
	allocated_skill_points:  [Sub_Category]i32,
	skill_adeptness:         [Sub_Category]f32,

	// inventory
	inventory:             Inventory,

	// target
	target_id:             Entity_Id,
	is_dead:               bool,
	is_resting:            bool,

	// combat timers (client-side cooldown gating; server is authoritative)
	last_auto_attack_ms:   u64,
	last_manual_attack_ms: u64,
	attack_anim_until_ms:  u64,

	// cast / skills
	casting:               Cast_State,
	cooldowns:             [dynamic]Skill_Cooldown,
	skill_bar:             [10][64]u8, // 10 hotbar slots, skill name each
	skill_bar_lens:        [10]int,
}

local_player_init :: proc(p: ^Local_Player) {
	p.target_id = INVALID_ENTITY
	p.race = INVALID_RACE_ID
	p.job_id = INVALID_JOB_ID
	inventory_init(&p.inventory)
	p.cooldowns = make([dynamic]Skill_Cooldown)
}

local_player_destroy :: proc(p: ^Local_Player) {
	inventory_destroy(&p.inventory)
	delete(p.cooldowns)
}

// skill bar helpers
skill_bar_set :: proc(p: ^Local_Player, slot: int, name: string) {
	if slot < 0 || slot >= len(p.skill_bar) do return
	p.skill_bar_lens[slot] = min(len(name), len(p.skill_bar[slot]))
	copy(p.skill_bar[slot][:p.skill_bar_lens[slot]], transmute([]u8)name)
}

skill_bar_get :: proc(p: ^Local_Player, slot: int) -> string {
	if slot < 0 || slot >= len(p.skill_bar) do return ""
	return string(p.skill_bar[slot][:p.skill_bar_lens[slot]])
}

// Remaining cooldown (ms) for a skill by name, or 0 if not on cooldown.
skill_cooldown_remaining :: proc(p: ^Local_Player, name: string) -> f64 {
	for i in 0 ..< len(p.cooldowns) {
		cd := &p.cooldowns[i]
		if string(cd.skill_name[:cd.name_len]) == name do return cd.remaining_ms
	}
	return 0
}
