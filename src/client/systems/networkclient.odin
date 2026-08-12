package systems

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:net"
import "core:strings"
import "core:time"

NET_DEBUG :: false
DEBUG_PRINTFLN :: proc($fmt_str: string, args: ..any) {
	when NET_DEBUG {
		fmt.printf("[net] " + fmt_str + "\n", ..args)
	}
}

net_log :: proc(fmt_str: string, args: ..any) {
	fmt.printf("[net] %s\n", fmt.tprintf(fmt_str, ..args))
}

// ─────────────────────────────────────────────────────────────────────────
//  Packet protocol — mirrors packages/shared/src/types/packets.ts exactly.
//  The numeric values MUST match the server's PacketType enum, since packets
//  are sent as raw integers over the wire.
// ─────────────────────────────────────────────────────────────────────────

Packet_Type :: enum u32 {
	// Connection
	CONNECT                    = 0,
	DISCONNECT                 = 1,
	HEARTBEAT                  = 2,

	// Auth / characters
	LOGIN                      = 10,
	REGISTER                   = 11,
	AUTH_SUCCESS               = 12,
	AUTH_FAILURE               = 13,
	CHARACTER_LIST             = 14,
	CHARACTER_CREATE           = 15,
	CHARACTER_SELECT           = 16,
	CHARACTER_DELETE           = 17,

	// Movement / world
	PLAYER_MOVE                = 20,
	PLAYER_POSITION_UPDATE     = 21,
	PLAYER_ROTATION_UPDATE     = 22,
	WORLD_STATE                = 23,

	// Combat
	ATTACK                     = 30,
	DAMAGE                     = 31,
	HEAL                       = 32,
	DEATH                      = 33,
	SKILL_USE                  = 34,
	COOLDOWN_UPDATE            = 35,
	MANUAL_ATTACK              = 36,

	// Chat
	CHAT_MESSAGE               = 40,

	// Zones / entities
	ENTER_ZONE                 = 50,
	LEAVE_ZONE                 = 51,
	ENTITY_SPAWN               = 52,
	ENTITY_DESPAWN             = 53,
	ENEMY_STATE_CHANGE         = 54,

	// Inventory
	INVENTORY_UPDATE           = 60,
	ITEM_USE                   = 61,
	ITEM_DROP                  = 62,
	ITEM_PICKUP                = 63,
	EQUIP_ITEM                 = 64,
	UNEQUIP_ITEM               = 65,
	LOOT_SPAWN                 = 66,
	LOOT_PICKUP                = 67,

	// Quests
	QUEST_LIST                 = 70,
	QUEST_ACCEPT               = 71,
	QUEST_PROGRESS             = 72,
	QUEST_COMPLETE             = 73,
	QUEST_ABANDON              = 74,

	// NPC
	NPC_INTERACT               = 80,
	NPC_DIALOG                 = 81,
	NPC_SHOP                   = 82,
	NPC_SHOP_BUY               = 83,
	NPC_SHOP_SELL              = 84,
	NPC_DIALOG_CLOSE           = 85,

	// Stats / progression
	STATS_UPDATE               = 90,
	EXPERIENCE_GAIN            = 91,
	LEVEL_UP                   = 92,
	STAT_ALLOCATE              = 93,
	JOB_ADVANCE                = 94,
	SKILL_BAR_UPDATE           = 95,
	STATUS_EFFECT_UPDATE       = 96,
	ENTITY_STATUS_EFFECTS      = 97,
	SONG_PULSE                 = 98,
	SKILL_ALLOCATE             = 99,
	RESPAWN_REQUEST            = 100,
	REVIVE_PLAYER              = 130,
	PLAYER_REVIVED             = 131,

	// Notifications
	NOTIFICATION               = 101,
	ERROR                      = 102,

	// Party
	PARTY_CREATE_REQUEST       = 110,
	PARTY_INVITE_REQUEST       = 111,
	PARTY_INVITE               = 112,
	PARTY_JOIN_REQUEST         = 113,
	PARTY_JOIN_RESPONSE        = 114,
	PARTY_LEAVE                = 115,
	PARTY_DISBAND              = 116,
	PARTY_KICK                 = 117,
	PARTY_UPDATE               = 118,
	PARTY_LOOT_ROLL            = 119,
	PARTY_LOOT_RESULT          = 120,
	PARTY_PROMOTE              = 121,

	// Enhancement / AOE
	WEAPON_ENHANCE             = 140,
	ENHANCEMENT_RESULT         = 141,
	AOE_ENTITY                 = 150,
	AOE_DESPAWN                = 151,

	// Trade
	TRADE_REQUEST              = 160,
	TRADE_INVITE               = 161,
	TRADE_RESPONSE             = 162,
	TRADE_OPEN                 = 163,
	TRADE_ADD_ITEM             = 164,
	TRADE_REMOVE_ITEM          = 165,
	TRADE_SET_GOLD             = 166,
	TRADE_UPDATE               = 167,
	TRADE_ACCEPT               = 168,
	TRADE_CANCEL               = 169,
	TRADE_CLOSE                = 170,

	// Misc gameplay
	BATCH_COMBAT               = 171,
	ZONE_HANDOFF               = 172,
	PLAYER_REST                = 173,
	SKILL_CANCEL               = 174,
	ENTITY_ANIMATION           = 175,
	RETURN_TO_CHARACTER_SELECT = 176,
	LOGOUT                     = 177,
	LOOT_OPEN                  = 178,
	LOOT_DESPAWN               = 179,
	LOOT_TAKE                  = 180,
	PARTY_LOOT_RULE_CHANGE     = 181,
	PARTY_LOOT_ROLL_SUBMIT     = 182,
	RECIPE_LEARN               = 183,
	CRAFT_REQUEST              = 184,
	CRAFT_RESULT               = 185,
	CUTSCENE_START             = 186,
	CUTSCENE_COMPLETE          = 187,
	CUTSCENE_END               = 188,
	FLOATING_TEXT              = 189,
}

// A decoded inbound packet. `data` is an owned (deep-cloned) JSON payload; the
// gameplay layer frees it via free_packet once consumed.
Packet :: struct {
	type:      Packet_Type,
	timestamp: u64, // server wall-clock ms
	data:      ^JSON_Value,
}

// ─────────────────────────────────────────────────────────────────────────
//  Network client — Socket.IO v4 over WebSocket (Engine.IO v4).
//
//  The server (packages/server) speaks Socket.IO with a single event named
//  "packet" carrying {type, timestamp, data}. Auth is application-layer (the
//  LOGIN packet), not part of the Socket.IO handshake, so we connect directly
//  to the websocket transport. Wire framing:
//
//    Engine.IO open  : server sends  `0{"sid":...,"pingInterval":25000,"pingTimeout":60000}`
//    Client keepalive: client sends   `2` (ping) -> server answers `3` (pong)
//    App packet      : both directions `42["packet",{"type":N,"timestamp":T,"data":{...}}]`
//
//  All socket I/O happens in update_network() on the main thread (non-blocking),
//  so the rest of the game code never deals with threads. The WS/polling frame
//  codec lives in networkclient_transport.odin.
// ─────────────────────────────────────────────────────────────────────────

Network_State :: enum {
	DISCONNECTED,
	CONNECTING, // TCP dial done, WS/Engine.IO handshake in progress
	OPEN, // Engine.IO open received, ready to send
	FAILED, // dropped; reconnect will retry with backoff
}

Transport :: enum {
	WEBSOCKET,
	POLLING,
}

Network_Client :: struct {
	state:                 Network_State,
	socket:                net.TCP_Socket,
	polling_socket:        net.TCP_Socket,
	connected:             bool,
	host:                  string,
	port:                  int,
	sid:                   string,
	ping_interval_ms:      u64,
	ping_timeout_ms:       u64,
	last_ping_sent_ms:     u64,
	last_pong_recv_ms:     u64,
	awaiting_pong:         bool,

	// Transport selection.
	transport:             Transport,
	polling_seq:           u64,
	last_poll_ms:          u64,
	polling_active:        bool,

	// Outbound packets queued while not yet open (mirrors TS NetworkClient).
	pending_send:          [dynamic]Packet,
	// Inbound packets awaiting the gameplay layer.
	inbound:               [dynamic]Packet,

	// Raw recv accumulator (WS frames can be split across TCP reads).
	out_buf:               [dynamic]u8,
	recv_buf:              [dynamic]u8,

	// WS handshake state: false until we've consumed the HTTP/1.1 101 response.
	ws_upgraded:           bool,
	reconnect_attempts:    int,
	last_reconnect_ms:     u64,
	current_delay_ms:      f64,

	// Credentials stored for automatic re-authentication after reconnect.
	auth_username:         string,
	auth_password:         string,
	auth_character_id_buf: [64]u8,
	auth_character_id_len: int,
	auth_sent:             bool,
	char_select_sent:      bool,
}

new_network_client :: proc(host: string, port: int) -> ^Network_Client {
	nc := new(Network_Client)
	nc.host = host
	nc.port = port
	nc.state = .DISCONNECTED
	nc.ping_interval_ms = 20000
	nc.ping_timeout_ms = 60000
	nc.transport = .WEBSOCKET
	nc.current_delay_ms = NET.RECONNECT_DELAY_MS
	return nc
}

destroy_network_client :: proc(nc: ^Network_Client) {
	disconnect(nc)
	close_polling_socket(nc)
	delete(nc.pending_send)
	delete(nc.inbound)
	delete(nc.recv_buf)
	free(nc)
}

// ── public API ────────────────────────────────────────────────────────────

// Begin a (re)connection attempt. The TCP dial is synchronous (localhost dev
// — fast); the WS/Engine.IO handshake then completes over update_network().
connect :: proc(nc: ^Network_Client) {
	if nc.state == .CONNECTING || nc.state == .OPEN do return
	if nc.socket != 0 {
		nc.socket = 0
	}
	nc.connected = false
	nc.ws_upgraded = false
	clear(&nc.recv_buf)
	nc.state = .CONNECTING

	host := net.Host {
		hostname = nc.host,
		port     = nc.port,
	}
	sock, err := net.dial_tcp_from_host(host)
	if err != nil || sock == 0 {
		net_log("connect: TCP dial failed (transport=%v), err=%v", nc.transport, err)
		if nc.transport == .WEBSOCKET {
			nc.transport = .POLLING
			nc.last_reconnect_ms = now_ms()
			nc.state = .FAILED
			return
		}
		nc.state = .FAILED
		nc.last_reconnect_ms = now_ms()
		return
	}
	nc.socket = sock

	if e := net.set_blocking(as_any_socket(sock), false); e != nil {
		if nc.transport == .WEBSOCKET {
			net.close(as_any_socket(sock))
			nc.socket = 0
			nc.transport = .POLLING
			nc.last_reconnect_ms = now_ms()
			nc.state = .FAILED
			return
		}
		nc.state = .FAILED
		return
	}

	if nc.transport == .WEBSOCKET {
		send_raw_http_upgrade(nc)
	} else {
		send_eio_polling_open(nc)
	}
	net_log("connect: TCP dial OK, transport=%v, sending handshake", nc.transport)
}

// Tear down the connection. Before closing the socket we send an explicit
// LOGOUT packet (server PacketType.LOGOUT = 177) so the server persists the
// player's position deterministically via its handleLogout handler, and flush
// any packets still buffered from this frame. The server's save-on-disconnect
// path also exists, but a raw WS close + immediate net.close() can drop the
// close frame before it reaches the server (non-blocking socket), leaving the
// save to a delayed ping-timeout — so we rely on the explicit LOGOUT instead.
// Mirrors the TS client's logoutToTitle() → sendLogout() → disconnect().
disconnect :: proc(nc: ^Network_Client) {
	if nc.socket != 0 && is_connected(nc) {
		flush_pending(nc)
		send(nc, .LOGOUT)
	}
	if nc.transport == .WEBSOCKET && nc.socket != 0 {
		_ = ws_send(nc, 0x8, []u8{0x03, 0xE8})
		net.close(as_any_socket(nc.socket))
		nc.socket = 0
	} else if nc.transport == .POLLING && nc.socket != 0 {
		send_eio_polling_close(nc)
		net.close(as_any_socket(nc.socket))
		nc.socket = 0
	}
	close_polling_socket(nc)
	nc.connected = false
	nc.state = .DISCONNECTED
	nc.ws_upgraded = false
	nc.polling_active = false
	nc.awaiting_pong = false
	net_log("disconnect: socket closed, transport=%v", nc.transport)
}

is_connected :: proc(nc: ^Network_Client) -> bool {
	return nc.state == .OPEN && nc.connected
}

set_auth_credentials :: proc(nc: ^Network_Client, username, password: string) {
	nc.auth_username = username
	nc.auth_password = password
}

set_character_id :: proc(nc: ^Network_Client, character_id: string) {
	n := min(len(character_id), len(nc.auth_character_id_buf))
	nc.auth_character_id_len = n
	if n > 0 {
		copy(nc.auth_character_id_buf[:n], transmute([]u8)character_id)
	}
}

clear_auth_credentials :: proc(nc: ^Network_Client) {
	nc.auth_username = ""
	nc.auth_password = ""
	nc.auth_character_id_len = 0
	nc.auth_sent = false
	nc.char_select_sent = false
}

has_auth_credentials :: proc(nc: ^Network_Client) -> bool {
	return len(nc.auth_username) > 0 && len(nc.auth_password) > 0
}

get_auth_username :: proc(nc: ^Network_Client) -> string {
	return nc.auth_username
}

get_auth_password :: proc(nc: ^Network_Client) -> string {
	return nc.auth_password
}

get_auth_character_id :: proc(nc: ^Network_Client) -> string {
	return string(nc.auth_character_id_buf[:nc.auth_character_id_len])
}

// Queue an outbound application packet. The `data` json.Value is serialized
// inline. If we're not yet OPEN, the packet is buffered and flushed once the
// handshake completes (like the TS client's pendingPackets).
send :: proc(nc: ^Network_Client, ptype: Packet_Type, data: ^JSON_Value = nil) {
	if !is_connected(nc) {
		owned: ^JSON_Value = nil
		if data != nil {
			owned = clone_value(data^)
		}
		append(&nc.pending_send, Packet{type = ptype, timestamp = now_ms(), data = owned})
		return
	}
	flush_one(nc, Packet{type = ptype, timestamp = now_ms(), data = data})
}

// Convenience: send a packet whose data is an object built from key/value pairs.
send_object :: proc(nc: ^Network_Client, ptype: Packet_Type, fields: []JSON_Field) {
	obj := build_object(fields)
	defer free_value(obj)
	send(nc, ptype, &obj^)
}

JSON_Field :: struct {
	key:   string,
	value: JSON_Value,
}

// Wrap a float in a JSON value (helper for building packet data).
json_float :: proc "contextless" (x: f32) -> json.Float {
	// Round to 4 decimal places to prevent massive payload bloat
	// (e.g., -50.0000000000000000 becomes -50.0)
	return json.Float(f64(math.round(f64(x) * 10000.0) / 10000.0))
}
json_int_v :: proc "contextless" (n: int) -> json.Integer {return json.Integer(i64(n))}
json_str :: proc "contextless" (s: string) -> json.String {return json.String(s)}

// ── typed convenience senders ─────────────────────────────────────────────
// Each builds the exact `data` shape the matching server handler expects (see
// packages/server/src/core/network/handlers/*.ts).

send_login :: proc(nc: ^Network_Client, username, password: string) {
	fields := make([dynamic]JSON_Field, 0, 2)
	defer delete(fields)
	append(&fields, JSON_Field{"username", json_str(username)})
	append(&fields, JSON_Field{"password", json_str(password)})
	send_object(nc, .LOGIN, fields[:])
}

send_register :: proc(nc: ^Network_Client, username, email, password: string) {
	fields := make([dynamic]JSON_Field, 0, 3)
	defer delete(fields)
	append(&fields, JSON_Field{"username", json_str(username)})
	append(&fields, JSON_Field{"email", json_str(email)})
	append(&fields, JSON_Field{"password", json_str(password)})
	send_object(nc, .REGISTER, fields[:])
}

send_character_list :: proc(nc: ^Network_Client) {
	send(nc, .CHARACTER_LIST)
}

send_character_create :: proc(nc: ^Network_Client, name, character_class, race: string) {
	fields := make([dynamic]JSON_Field, 0, 3)
	defer delete(fields)
	append(&fields, JSON_Field{"name", json_str(name)})
	append(&fields, JSON_Field{"characterClass", json_str(character_class)})
	append(&fields, JSON_Field{"race", json_str(race)})
	send_object(nc, .CHARACTER_CREATE, fields[:])
}

send_character_select :: proc(nc: ^Network_Client, character_id: string) {
	fields := make([dynamic]JSON_Field, 0, 1)
	defer delete(fields)
	append(&fields, JSON_Field{"characterId", json_str(character_id)})
	send_object(nc, .CHARACTER_SELECT, fields[:])
}

send_attack :: proc(nc: ^Network_Client, target_id: string) {
	fields := make([dynamic]JSON_Field, 0, 1)
	defer delete(fields)
	append(&fields, JSON_Field{"targetId", json_str(target_id)})
	send_object(nc, .ATTACK, fields[:])
}

send_manual_attack :: proc(nc: ^Network_Client, facing_angle: f32) {
	fields := make([dynamic]JSON_Field, 0, 1)
	defer delete(fields)
	append(&fields, JSON_Field{"facingAngle", json_float(facing_angle)})
	send_object(nc, .MANUAL_ATTACK, fields[:])
}

send_skill_use :: proc(nc: ^Network_Client, skill_name: string, target_id: string) {
	fields := make([dynamic]JSON_Field, 0, 2)
	defer delete(fields)
	append(&fields, JSON_Field{"skillName", json_str(skill_name)})
	if len(target_id) > 0 {
		append(&fields, JSON_Field{"targetId", json_str(target_id)})
	}
	send_object(nc, .SKILL_USE, fields[:])
}

send_chat :: proc(nc: ^Network_Client, message: string) {
	fields := make([dynamic]JSON_Field, 0, 1)
	defer delete(fields)
	append(&fields, JSON_Field{"message", json_str(message)})
	send_object(nc, .CHAT_MESSAGE, fields[:])
}

send_enter_zone :: proc(nc: ^Network_Client, zone_id: string) {
	fields := make([dynamic]JSON_Field, 0, 1)
	defer delete(fields)
	append(&fields, JSON_Field{"zoneId", json_str(zone_id)})
	send_object(nc, .ENTER_ZONE, fields[:])
}

send_npc_interact :: proc(nc: ^Network_Client, npc_id: string) {
	fields := make([dynamic]JSON_Field, 0, 1)
	defer delete(fields)
	append(&fields, JSON_Field{"npcId", json_str(npc_id)})
	send_object(nc, .NPC_INTERACT, fields[:])
}

// Stat-point allocation: add one point to `stat` ("STA"/"STR"/…).
// Assumed payload shape: { stat: "STR" }.
send_stat_allocate :: proc(nc: ^Network_Client, stat: string) {
	fields := make([dynamic]JSON_Field, 0, 1)
	defer delete(fields)
	append(&fields, JSON_Field{"stat", json_str(stat)})
	send_object(nc, .STAT_ALLOCATE, fields[:])
}

// Skill-point allocation: add `count` points to `sub_category` ("Slash"/…).
// Server (statHandlers.handleSkillAllocate) reads { subCategoryName, count }.
send_skill_allocate :: proc(nc: ^Network_Client, sub_category: string, count: int = 1) {
	fields := make([dynamic]JSON_Field, 0, 2)
	defer delete(fields)
	append(&fields, JSON_Field{"subCategoryName", json_str(sub_category)})
	append(&fields, JSON_Field{"count", json.Integer(count)})
	send_object(nc, .SKILL_ALLOCATE, fields[:])
}

// Drain inbound packets. Caller owns each Packet.data and must free_packet it.
poll_inbound :: proc(nc: ^Network_Client) -> []Packet {
	out := nc.inbound[:]
	clear(&nc.inbound)
	return out
}

free_packet :: proc(p: ^Packet) {
	if p.data != nil {
		free_value(p.data)
		p.data = nil
	}
}

// Pump the connection: service pings, drain the socket, handle reconnect.
update_network :: proc(nc: ^Network_Client) {
	flush_out_buf(nc)
	t := now_ms()

	switch nc.state {
	case .CONNECTING:
		if nc.transport == .POLLING {
			service_polling_connect(nc, t)
		} else {
			service_recv(nc)
		}
	case .OPEN:
		if nc.transport == .POLLING {
			service_polling_recv(nc, t)
			service_pings(nc, t)
		} else {
			service_recv(nc)
			service_pings(nc, t)
		}
		flush_pending(nc)
	case .FAILED:
		if t - nc.last_reconnect_ms >= u64(nc.current_delay_ms) &&
		   nc.reconnect_attempts < NET.MAX_RECONNECT_ATTEMPTS {
			nc.reconnect_attempts += 1
			nc.last_reconnect_ms = t
			nc.auth_sent = false
			nc.char_select_sent = false
			if nc.transport == .POLLING {
				nc.transport = .WEBSOCKET
			}
			net_log(
				"reconnect attempt #%d, delay=%.0fms, transport=%v",
				nc.reconnect_attempts,
				nc.current_delay_ms,
				nc.transport,
			)
			connect(nc)
		} else if nc.reconnect_attempts >= NET.MAX_RECONNECT_ATTEMPTS {
			if t - nc.last_reconnect_ms > u64(nc.current_delay_ms) {
				nc.last_reconnect_ms = t
				net_log("reconnect exhausted (%d attempts), giving up", nc.reconnect_attempts)
			}
		}
	case .DISCONNECTED:
	}
}

// ── internals ─────────────────────────────────────────────────────────────

as_any_socket :: proc "contextless" (s: net.TCP_Socket) -> net.Any_Socket {
	// Any_Socket is a union {TCP_Socket, UDP_Socket}; implicit coercion works.
	return s
}

build_object :: proc(fields: []JSON_Field) -> ^JSON_Value {
	obj := make(map[string]JSON_Value)
	for f in fields {
		obj[f.key] = f.value
	}
	v := new(JSON_Value)
	v^ = json.Object(obj)
	return v
}

// Recursively free a heap-owned json.Value tree produced by build_object /
// clone_value. Ownership rule: the ONLY things we `free`/`delete` here are the
// containers WE allocated with make() (map / dynamic) and the single heap node
// from new(). We must NOT free individual string values: those are either
//   (a) string literals the program passed in (e.g. json.String("username")) —
//       not heap-allocated by us, freeing them is the invalid-pointer crash; or
//   (b) strings owned by json.parse's allocator, which the container's own
//       delete() already releases. Manually freeing strings double-frees / frees
//       literals → SIGABRT. So: containers + the top node only.
free_value :: proc(v: ^JSON_Value) {
	if v == nil do return
	free_value_value(v^)
	free(v)
}

// Free the containers owned by a json.Value (its map/dynamic, recursively).
// Does NOT free the value node itself (the caller decides that).
free_value_value :: proc(v: JSON_Value) {
	#partial switch e in v {
	case json.Object:
		m := as_map(JSON_Object(e))
		for _, val in m {
			free_value_value(val) // recurse into nested containers only
		}
		delete(m) // releases the map + its key/value slots
	case json.Array:
		a := as_dyn(JSON_Array(e))
		for i in 0 ..< len(a) {
			free_value_value(a[i])
		}
		delete(a)
	case:
	// String/Integer/Float/Boolean/Null — nothing we own to free.
	}
}

flush_pending :: proc(nc: ^Network_Client) {
	if !is_connected(nc) do return
	for &p in nc.pending_send {
		flush_one(nc, p)
		if p.data != nil {
			free_value(p.data)
			p.data = nil
		}
	}
	clear(&nc.pending_send)
}

flush_one :: proc(nc: ^Network_Client, p: Packet) {
	obj := make(map[string]JSON_Value)
	obj["type"] = json.Integer(u64(p.type))
	obj["timestamp"] = json.Integer(i64(p.timestamp))
	if p.data != nil {
		obj["data"] = (p.data)^
	} else {
		obj["data"] = json.Object{}
	}

	arr := make([dynamic]JSON_Value, 2)
	arr[0] = json.String("packet")
	arr[1] = json.Object(obj)

	msg_value: JSON_Value = json.Array(arr)

	payload_json, ok := json_marshal(&msg_value)
	if !ok do return
	defer {
		delete(payload_json)
		delete(arr)
		delete(obj)
	}

	raw_frame := fmt.tprintf("42%s", payload_json)

	// Strip the excessive float precision to match JS JSON.stringify
	// e.g. "-50.0000000000000000" becomes "-50.0"
	frame, _ := strings.replace_all(raw_frame, ".0000000000000000", ".0")
	DEBUG_PRINTFLN("SEND frame: %s", frame)

	if nc.transport == .POLLING {
		send_eio_polling_post(nc, frame)
	} else {
		_ = ws_send_text(nc, transmute([]u8)frame)
	}
}

service_pings :: proc(nc: ^Network_Client, t: u64) {
	// ONLY check for timeout. We DO NOT send pings over WebSockets.
	if nc.awaiting_pong && t - nc.last_ping_sent_ms > nc.ping_timeout_ms {
		net_log(
			"service_pings: TIMEOUT (no pong for %dms), forcing disconnect",
			t - nc.last_ping_sent_ms,
		)
		nc.awaiting_pong = false
		disconnect(nc)
		nc.state = .FAILED
		nc.last_reconnect_ms = now_ms()
		nc.current_delay_ms = min(
			nc.current_delay_ms * NET.RECONNECT_BACKOFF_FACTOR,
			NET.RECONNECT_DELAY_MAX_MS,
		)
	}
}

// Deep-clone a json.Value into a heap-owned top node. Nested Objects/Arrays
// are cloned into fresh map/dynamic containers (which are themselves
// heap-backed handles), so the whole clone is owned by the returned node and
// freed by free_value. Scalar (String/Integer/...) values are copied by value.
clone_value :: proc(v: JSON_Value) -> ^JSON_Value {
	out := new(JSON_Value)
	out^ = clone_value_value(v)
	return out
}

// Internal: Deep clone the value (not the container itself)
clone_value_value :: proc(v: JSON_Value) -> JSON_Value {
	#partial switch e in v {
	case json.Object:
		src := as_map(JSON_Object(e))
		m := make(map[string]JSON_Value)
		// Reserve capacity to prevent reallocations
		reserve(&m, len(src))
		for key, val in src {
			m[key] = clone_value_value(val)
		}
		return json.Object(m)

	case json.Array:
		src := as_dyn(JSON_Array(e))
		a := make([dynamic]JSON_Value, len(src))
		// Copy each element
		for i in 0 ..< len(src) {
			a[i] = clone_value_value(src[i])
		}
		return json.Array(a)

	case json.String:
		// Strings are immutable in Odin, but if they're heap-allocated,
		// we need to clone them
		str := as_string(e)
		// Clone the string to new heap memory
		cloned := make([]u8, len(str))
		copy(cloned, str)
		return json.String(string(cloned))

	case:
		// Integer, Float, Boolean, Null - copy by value
		return v
	}
}

// ── time ──────────────────────────────────────────────────────────────────

// Wall-clock milliseconds since the UNIX epoch (Time._nsec is UNIX ns).
now_ms :: proc "contextless" () -> u64 {
	return u64(time.now()._nsec / 1_000_000)
}
