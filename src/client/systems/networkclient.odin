package systems

import "core:encoding/base64"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:math/rand"
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
//  so the rest of the game code never deals with threads.
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

// ── typed convenience senders ────────────────────────────────────────────
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
// clone_value. The top node is always heap-allocated and freed here; nested
// Objects/Arrays are freed via their owning containers (map / dynamic), and
// we recurse only into heap nodes we know we allocated. Crucially, we must
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

service_recv :: proc(nc: ^Network_Client) {
	if nc.socket == 0 do return
	buf: [8192]u8
	for {
		n, err := net.recv(nc.socket, buf[:])
		if n > 0 {
			DEBUG_PRINTFLN(
				"RECV %d bytes: state=%v ws_upgraded=%v buf_len=%d",
				n,
				nc.state,
				nc.ws_upgraded,
				len(nc.recv_buf) + n,
			)
			append(&nc.recv_buf, ..buf[:n])
			consume_recv_buffer(nc)
		}
		// Nothing more right now, or a real error.
		if err != .Would_Block && err != .None {
			net_log("service_recv: net.recv err -> %v", err)
			if err == .Connection_Closed {
				handle_disconnect(nc)
			}
			return
		}
		if n <= 0 do return // would-block or clean — done for this frame
		if n < len(buf) do break
	}
}

handle_disconnect :: proc(nc: ^Network_Client) {
	net_log("handle_disconnect: connection lost, transport=%v, state=%v", nc.transport, nc.state)
	if nc.socket != 0 {
		net.close(as_any_socket(nc.socket))
		nc.socket = 0
	}
	close_polling_socket(nc)
	nc.connected = false
	nc.state = .FAILED
	nc.ws_upgraded = false
	nc.polling_active = false
	nc.awaiting_pong = false
	nc.last_reconnect_ms = now_ms()
	nc.current_delay_ms = min(
		nc.current_delay_ms * NET.RECONNECT_BACKOFF_FACTOR,
		NET.RECONNECT_DELAY_MAX_MS,
	)
}

// If we haven't yet completed the HTTP/1.1 101 upgrade, peel it off the front
// of recv_buf; everything after the \r\n\r\n is the WS byte stream.
consume_recv_buffer :: proc(nc: ^Network_Client) {
	if !nc.ws_upgraded {
		// Find end of HTTP response headers.
		hdr_sep: string = "\r\n\r\n"
		hdr_end := find_subslice(nc.recv_buf[:], transmute([]u8)hdr_sep)
		if hdr_end < 0 do return // need more bytes
		nc.ws_upgraded = true
		// Discard headers; keep the remainder as WS bytes.
		remainder := nc.recv_buf[hdr_end + 4:]
		copy(nc.recv_buf[:], remainder)
		shrink_dynamic(&nc.recv_buf, len(remainder))
	}
	// Now decode as many complete WS frames as are present.
	for {
		consumed, ok := decode_one_ws_frame(nc, nc.recv_buf[:])
		if !ok do break
		if consumed < len(nc.recv_buf) {
			remainder := nc.recv_buf[consumed:]
			copy(nc.recv_buf[:], remainder)
		}
		shrink_dynamic(&nc.recv_buf, max(0, len(nc.recv_buf) - consumed))
	}
}

find_subslice :: proc "contextless" (haystack, needle: []u8) -> int {
	if len(needle) == 0 || len(haystack) < len(needle) do return -1
	for i in 0 ..= len(haystack) - len(needle) {
		match := true
		for j in 0 ..< len(needle) {
			if haystack[i + j] != needle[j] {match = false; break}
		}
		if match do return i
	}
	return -1
}

// Shrink a [dynamic]u8's logical length without reallocating (capacity kept).
// Used to drop consumed bytes from the front of the recv accumulator.
shrink_dynamic :: proc(d: ^[dynamic]u8, n: int) {
	resize(d, n)
}

// Decode one WebSocket frame. Server→client frames are unmasked. Returns
// (bytes_consumed, true) if a full frame was processed.
decode_one_ws_frame :: proc(nc: ^Network_Client, buf: []u8) -> (consumed: int, ok: bool) {
	if len(buf) < 2 do return 0, false
	b0 := buf[0]
	b1 := buf[1]
	opcode := int(b0 & 0x0F)
	masked := (b1 & 0x80) != 0
	length: u64 = u64(b1 & 0x7F)

	idx := 2
	switch {
	case length == 126:
		if len(buf) < idx + 2 do return 0, false
		length = u64(buf[idx]) << 8 | u64(buf[idx + 1])
		idx += 2
	case length == 127:
		if len(buf) < idx + 8 do return 0, false
		l: u64 = 0
		for i in 0 ..< 8 {l = (l << 8) | u64(buf[idx + i])}
		length = l
		idx += 8
	}

	mask: [4]u8
	if masked {
		if len(buf) < idx + 4 do return 0, false
		copy(mask[:], buf[idx:idx + 4])
		idx += 4
	}

	if u64(len(buf)) < u64(idx) + length do return 0, false
	payload := buf[idx:idx + int(length)]
	if masked {
		for i in 0 ..< len(payload) {
			payload[i] = payload[i] ~ mask[i % 4]
		}
	}

	// We only emit FIN=1 frames here; fragmentation isn't used by Socket.IO.
	handle_ws_payload(nc, opcode, payload)
	return idx + int(length), true
}

handle_ws_payload :: proc(nc: ^Network_Client, opcode: int, payload: []u8) {
	switch opcode {
	case 0x1:
		// text
		handle_eio_frame(nc, payload)
	case 0x2:
		// binary
		handle_eio_frame(nc, payload)
	case 0x9:
		// ping
		_ = ws_send(nc, 0xA, payload) // pong
	case 0xA:
		// pong
		nc.last_pong_recv_ms = now_ms()
		nc.awaiting_pong = false
	case 0x8:
		// close
		if len(payload) >= 2 {
			close_code := int(payload[0]) << 8 | int(payload[1])
			reason := string(payload[2:])
			net_log("WS CLOSE received: code=%d reason='%s'", close_code, reason)
		}
		handle_disconnect(nc)
	case:
	}
}

// ── Engine.IO / Socket.IO framing ─────────────────────────────────────────

handle_eio_frame :: proc(nc: ^Network_Client, payload: []u8) {
	if len(payload) == 0 do return
	code := payload[0]
	rest := payload[1:]

	switch code {
	case '0':
		// Engine.IO open: `0{"sid":...,"pingInterval":...,"pingTimeout":...}`
		nc.state = .OPEN
		nc.reconnect_attempts = 0
		nc.current_delay_ms = NET.RECONNECT_DELAY_MS
		nc.last_pong_recv_ms = now_ms()
		nc.last_ping_sent_ms = now_ms()
		nc.awaiting_pong = false
		if len(rest) > 0 {
			if v, ok := json_parse(rest); ok {
				obj := obj_of(v)
				if !is_null(v) {
					nc.sid = get_string(obj, "sid")
					nc.ping_interval_ms = u64(get_f64(obj, "pingInterval", 20000))
					nc.ping_timeout_ms = u64(get_f64(obj, "pingTimeout", 60000))
				}
			}
		}
		net_log(
			"EIO OPEN PARSED: ping_interval=%dms, ping_timeout=%dms",
			nc.ping_interval_ms,
			nc.ping_timeout_ms,
		)
		connect_pkt: string = "40"
		_ = ws_send_text(nc, transmute([]u8)connect_pkt)
		net_log(
			"EIO open: sid=%s ping_interval=%dms ping_timeout=%dms (reconnect #%d)",
			nc.sid,
			nc.ping_interval_ms,
			nc.ping_timeout_ms,
			nc.reconnect_attempts,
		)
	case '3':
		nc.last_pong_recv_ms = now_ms()
		nc.awaiting_pong = false
	case '4':
		handle_sio_frame(nc, rest)
	case '1':
		net_log("EIO close: server closed the connection")
		handle_disconnect(nc)
	case '2':
		pong: string = "3"
		ok := ws_send_text(nc, transmute([]u8)pong)
		if !ok {
			net_log("!!! FAILED TO SEND PONG !!!")
		}
		net_log("SERVER PING RECEIVED! Sending pong...")
	case:
	}
}

handle_sio_frame :: proc(nc: ^Network_Client, payload: []u8) {
	if len(payload) == 0 do return
	code := payload[0]
	rest := payload[1:]

	switch code {
	case '0':
		// Socket.IO CONNECT ack — the socket is now truly usable.
		// `connected` gates emit()/flush_pending(); only set it here so we
		// never send 42[...] events before the server accepts the namespace.
		nc.connected = true
		flush_pending(nc)
		net_log(
			"SIO CONNECT ack: socket is usable, pending=%d, has_auth=%v has_char=%v",
			len(nc.pending_send),
			len(nc.auth_username) > 0,
			nc.auth_character_id_len > 0,
		)
	case '4':
		// Socket.IO manager error (e.g. namespace refused)
		// Reconnect will be attempted by update_network's .FAILED path.
		handle_disconnect(nc)
	case '2':
		// event: 42[...]
		handle_sio_event(nc, rest)
	case:
	}
}

handle_sio_event :: proc(nc: ^Network_Client, rest: []u8) {
	if len(rest) == 0 do return

	v, ok := json_parse(rest)
	if !ok do return
	arr := array_of(v)
	dyn := as_dyn(arr)
	if len(dyn) < 2 do return

	if string_of(dyn[0]) != "packet" do return

	pkt_obj := obj_of(dyn[1])
	if is_null(dyn[1]) do return

	ptype_u := u32(get_f64(pkt_obj, "type"))
	ptype, pt_ok := int_to_packet_type(int(ptype_u))
	DEBUG_PRINTFLN("SIO event: pt_ok=%v type=%v", pt_ok, ptype)
	if !pt_ok do return

	data_v := field(pkt_obj, "data")
	owned := clone_value(data_v) // deep clone → survives recv scratch
	append(
		&nc.inbound,
		Packet{type = ptype, timestamp = u64(get_f64(pkt_obj, "timestamp")), data = owned},
	)
}

int_to_packet_type :: proc(n: int) -> (Packet_Type, bool) {
	if n < 0 || n > 189 do return .CONNECT, false
	switch n {
	case 0:
		return .CONNECT, true
	case 1:
		return .DISCONNECT, true
	case 2:
		return .HEARTBEAT, true
	case 10:
		return .LOGIN, true
	case 11:
		return .REGISTER, true
	case 12:
		return .AUTH_SUCCESS, true
	case 13:
		return .AUTH_FAILURE, true
	case 14:
		return .CHARACTER_LIST, true
	case 15:
		return .CHARACTER_CREATE, true
	case 16:
		return .CHARACTER_SELECT, true
	case 17:
		return .CHARACTER_DELETE, true
	case 20:
		return .PLAYER_MOVE, true
	case 21:
		return .PLAYER_POSITION_UPDATE, true
	case 22:
		return .PLAYER_ROTATION_UPDATE, true
	case 23:
		return .WORLD_STATE, true
	case 30:
		return .ATTACK, true
	case 31:
		return .DAMAGE, true
	case 32:
		return .HEAL, true
	case 33:
		return .DEATH, true
	case 34:
		return .SKILL_USE, true
	case 35:
		return .COOLDOWN_UPDATE, true
	case 36:
		return .MANUAL_ATTACK, true
	case 40:
		return .CHAT_MESSAGE, true
	case 50:
		return .ENTER_ZONE, true
	case 51:
		return .LEAVE_ZONE, true
	case 52:
		return .ENTITY_SPAWN, true
	case 53:
		return .ENTITY_DESPAWN, true
	case 54:
		return .ENEMY_STATE_CHANGE, true
	case 60:
		return .INVENTORY_UPDATE, true
	case 61:
		return .ITEM_USE, true
	case 62:
		return .ITEM_DROP, true
	case 63:
		return .ITEM_PICKUP, true
	case 64:
		return .EQUIP_ITEM, true
	case 65:
		return .UNEQUIP_ITEM, true
	case 66:
		return .LOOT_SPAWN, true
	case 67:
		return .LOOT_PICKUP, true
	case 70:
		return .QUEST_LIST, true
	case 71:
		return .QUEST_ACCEPT, true
	case 72:
		return .QUEST_PROGRESS, true
	case 73:
		return .QUEST_COMPLETE, true
	case 74:
		return .QUEST_ABANDON, true
	case 80:
		return .NPC_INTERACT, true
	case 81:
		return .NPC_DIALOG, true
	case 82:
		return .NPC_SHOP, true
	case 83:
		return .NPC_SHOP_BUY, true
	case 84:
		return .NPC_SHOP_SELL, true
	case 85:
		return .NPC_DIALOG_CLOSE, true
	case 90:
		return .STATS_UPDATE, true
	case 91:
		return .EXPERIENCE_GAIN, true
	case 92:
		return .LEVEL_UP, true
	case 93:
		return .STAT_ALLOCATE, true
	case 94:
		return .JOB_ADVANCE, true
	case 95:
		return .SKILL_BAR_UPDATE, true
	case 96:
		return .STATUS_EFFECT_UPDATE, true
	case 97:
		return .ENTITY_STATUS_EFFECTS, true
	case 98:
		return .SONG_PULSE, true
	case 99:
		return .SKILL_ALLOCATE, true
	case 100:
		return .RESPAWN_REQUEST, true
	case 101:
		return .NOTIFICATION, true
	case 102:
		return .ERROR, true
	case 110:
		return .PARTY_CREATE_REQUEST, true
	case 111:
		return .PARTY_INVITE_REQUEST, true
	case 112:
		return .PARTY_INVITE, true
	case 113:
		return .PARTY_JOIN_REQUEST, true
	case 114:
		return .PARTY_JOIN_RESPONSE, true
	case 115:
		return .PARTY_LEAVE, true
	case 116:
		return .PARTY_DISBAND, true
	case 117:
		return .PARTY_KICK, true
	case 118:
		return .PARTY_UPDATE, true
	case 119:
		return .PARTY_LOOT_ROLL, true
	case 120:
		return .PARTY_LOOT_RESULT, true
	case 121:
		return .PARTY_PROMOTE, true
	case 130:
		return .REVIVE_PLAYER, true
	case 131:
		return .PLAYER_REVIVED, true
	case 140:
		return .WEAPON_ENHANCE, true
	case 141:
		return .ENHANCEMENT_RESULT, true
	case 150:
		return .AOE_ENTITY, true
	case 151:
		return .AOE_DESPAWN, true
	case 160:
		return .TRADE_REQUEST, true
	case 161:
		return .TRADE_INVITE, true
	case 162:
		return .TRADE_RESPONSE, true
	case 163:
		return .TRADE_OPEN, true
	case 164:
		return .TRADE_ADD_ITEM, true
	case 165:
		return .TRADE_REMOVE_ITEM, true
	case 166:
		return .TRADE_SET_GOLD, true
	case 167:
		return .TRADE_UPDATE, true
	case 168:
		return .TRADE_ACCEPT, true
	case 169:
		return .TRADE_CANCEL, true
	case 170:
		return .TRADE_CLOSE, true
	case 171:
		return .BATCH_COMBAT, true
	case 172:
		return .ZONE_HANDOFF, true
	case 173:
		return .PLAYER_REST, true
	case 174:
		return .SKILL_CANCEL, true
	case 175:
		return .ENTITY_ANIMATION, true
	case 176:
		return .RETURN_TO_CHARACTER_SELECT, true
	case 177:
		return .LOGOUT, true
	case 178:
		return .LOOT_OPEN, true
	case 179:
		return .LOOT_DESPAWN, true
	case 180:
		return .LOOT_TAKE, true
	case 181:
		return .PARTY_LOOT_RULE_CHANGE, true
	case 182:
		return .PARTY_LOOT_ROLL_SUBMIT, true
	case 183:
		return .RECIPE_LEARN, true
	case 184:
		return .CRAFT_REQUEST, true
	case 185:
		return .CRAFT_RESULT, true
	case 186:
		return .CUTSCENE_START, true
	case 187:
		return .CUTSCENE_COMPLETE, true
	case 188:
		return .CUTSCENE_END, true
	case 189:
		return .FLOATING_TEXT, true
	case:
		return .CONNECT, false
	}
}

// ── WebSocket framing helpers ─────────────────────────────────────────────

make_ws_key :: proc() -> string {
	// 16 random bytes base64-encoded = the Sec-WebSocket-Key.
	key_bytes: [16]u8
	_ = rand.read(key_bytes[:])
	enc, _ := base64.encode(key_bytes[:])
	return enc
}

// Send the HTTP Upgrade that opens the WebSocket on the websocket transport
// directly (EIO=4, transport=websocket). Server replies HTTP/1.1 101 and the
// socket becomes a WS stream.
send_raw_http_upgrade :: proc(nc: ^Network_Client) {
	key := make_ws_key()
	defer delete(key)
	req := fmt.tprintf(
		"GET /socket.io/?EIO=4&transport=websocket HTTP/1.1\r\n" +
		"Host: %s:%d\r\n" +
		"Upgrade: websocket\r\n" +
		"Connection: Upgrade\r\n" +
		"Sec-WebSocket-Key: %s\r\n" +
		"Sec-WebSocket-Version: 13\r\n" +
		"\r\n",
		nc.host,
		nc.port,
		key,
	)
	_, _ = net.send(nc.socket, transmute([]u8)req)
}

// Mask+send a WebSocket frame from client to server (client frames MUST be
// masked per RFC 6455).
ws_send :: proc(nc: ^Network_Client, opcode: int, payload: []u8) -> bool {
	if nc.socket == 0 do return false

	mask: [4]u8
	_ = rand.read(mask[:])

	plen := len(payload)
	header: [10]u8
	hlen := 0
	header[0] = u8(0x80 | (opcode & 0x0F)) // FIN + opcode
	if plen <= 125 {
		header[1] = u8(0x80 | plen)
		hlen = 2
	} else if plen <= 0xFFFF {
		header[1] = u8(0x80 | 126)
		header[2] = u8((plen >> 8) & 0xFF)
		header[3] = u8(plen & 0xFF)
		hlen = 4
	} else {
		header[1] = u8(0x80 | 127)
		ulen := u64(plen)
		for i in 0 ..< 8 {
			header[2 + i] = u8((ulen >> cast(u64)(56 - 8 * i)) & 0xFF)
		}
		hlen = 10
	}
	copy(header[hlen:hlen + 4], mask[:])
	hlen += 4

	masked := make([]u8, plen)
	defer delete(masked)
	for i in 0 ..< plen {
		masked[i] = payload[i] ~ mask[i % 4]
	}

	// APPEND to buffer instead of sending directly
	for i in 0 ..< hlen {
		append(&nc.out_buf, header[i])
	}
	for b in masked {
		append(&nc.out_buf, b)
	}

	return true
}

ws_send_text :: proc(nc: ^Network_Client, payload: []u8) -> bool {
	return ws_send(nc, 0x1, payload)
}

// Safely flush the out_buf to the non-blocking socket.
// Handles partial writes correctly so the WS stream never gets corrupted.
flush_out_buf :: proc(nc: ^Network_Client) {
	if nc.socket == 0 || len(nc.out_buf) == 0 do return

	for len(nc.out_buf) > 0 {
		n, _ := net.send(nc.socket, nc.out_buf[:])
		if n > 0 {
			// Remove the sent bytes from the front of the buffer
			if n >= len(nc.out_buf) {
				clear(&nc.out_buf)
			} else {
				remainder := nc.out_buf[n:]
				copy(nc.out_buf[:], remainder)
				shrink_dynamic(&nc.out_buf, len(remainder))
			}
		} else {
			// n <= 0 means the OS buffer is full (Would_Block) or the connection dropped.
			// Either way, we stop sending for this frame. If the connection dropped,
			// service_recv() will detect the Connection_Closed error on the next read.
			break
		}
	}
}

// Deep-clone a json.Value into a heap-owned node. Takes the value by value so
// it can be fed map elements (which aren't addressable) directly.
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

// ── HTTP long-polling transport ───────────────────────────────────────────

close_polling_socket :: proc(nc: ^Network_Client) {
	if nc.polling_socket != 0 {
		net.close(as_any_socket(nc.polling_socket))
		nc.polling_socket = 0
	}
}

send_eio_polling_open :: proc(nc: ^Network_Client) {
	nc.polling_seq = 0
	req := fmt.tprintf(
		"GET /socket.io/?EIO=4&transport=polling HTTP/1.1\r\n" +
		"Host: %s:%d\r\n" +
		"Connection: keep-alive\r\n" +
		"\r\n",
		nc.host,
		nc.port,
	)
	req_bytes: []u8 = transmute([]u8)req
	_, _ = net.send(nc.socket, req_bytes)
}

send_eio_polling_get :: proc(nc: ^Network_Client) {
	req := fmt.tprintf(
		"GET /socket.io/?EIO=4&transport=polling&sid=%s&t=%d HTTP/1.1\r\n" +
		"Host: %s:%d\r\n" +
		"Connection: keep-alive\r\n" +
		"\r\n",
		nc.sid,
		nc.polling_seq,
		nc.host,
		nc.port,
	)
	req_bytes: []u8 = transmute([]u8)req
	_, _ = net.send(nc.socket, req_bytes)
}

send_eio_polling_post :: proc(nc: ^Network_Client, body: string) {
	payload := fmt.tprintf("%d:%s", len(body), body)
	req := fmt.tprintf(
		"POST /socket.io/?EIO=4&transport=polling&sid=%s&t=%d HTTP/1.1\r\n" +
		"Host: %s:%d\r\n" +
		"Content-Type: text/plain;charset=UTF-8\r\n" +
		"Content-Length: %d\r\n" +
		"Connection: keep-alive\r\n" +
		"\r\n%s",
		nc.sid,
		nc.polling_seq,
		nc.host,
		nc.port,
		len(payload),
		payload,
	)
	req_bytes: []u8 = transmute([]u8)req
	_, _ = net.send(nc.socket, req_bytes)
	nc.polling_seq += 1
}

send_eio_polling_close :: proc(nc: ^Network_Client) {
	if nc.sid != "" {
		send_eio_polling_post(nc, "1")
	}
}

service_polling_connect :: proc(nc: ^Network_Client, t: u64) {
	if nc.socket == 0 do return
	buf: [8192]u8
	for {
		n, err := net.recv(nc.socket, buf[:])
		if n > 0 {
			append(&nc.recv_buf, ..buf[:n])
		}
		if err != .Would_Block && err != .None {
			if err == .Connection_Closed {
				handle_disconnect(nc)
			}
			return
		}
		if n <= 0 do return
		if n < len(buf) do break
	}
	handle_polling_http_response(nc, t)
}

handle_polling_http_response :: proc(nc: ^Network_Client, t: u64) {
	for len(nc.recv_buf) > 0 {
		hdr_sep: string = "\r\n\r\n"
		hdr_end := find_subslice(nc.recv_buf[:], transmute([]u8)hdr_sep)
		if hdr_end < 0 do return

		chunked_str: string = "Transfer-Encoding: chunked"
		chunked_hdr := transmute([]u8)chunked_str
		is_chunked := find_subslice(nc.recv_buf[:hdr_end], chunked_hdr) >= 0

		body_start := hdr_end + 4
		body_end := len(nc.recv_buf)
		if is_chunked {
			body_end = parse_chunked_body_end(nc.recv_buf[body_start:])
			if body_end < 0 {
				shrink_dynamic(&nc.recv_buf, 0)
				return
			}
			body_end += body_start
		}

		if body_end > body_start {
			body := nc.recv_buf[body_start:body_end]
			handle_polling_body(nc, body)
		}

		if body_end < len(nc.recv_buf) {
			remainder := nc.recv_buf[body_end:]
			copy(nc.recv_buf[:], remainder)
			shrink_dynamic(&nc.recv_buf, len(remainder))
		} else {
			shrink_dynamic(&nc.recv_buf, 0)
		}
	}
}

parse_chunked_body_end :: proc(buf: []u8) -> int {
	total: int = 0
	i := 0
	crlf_str: string = "\r\n"
	crlf_bytes := transmute([]u8)crlf_str
	for {
		if i >= len(buf) do return -1
		crlf := find_subslice(buf[i:], crlf_bytes)
		if crlf < 0 do return -1
		size_str := string(buf[i:i + crlf])
		chunk_size: int = 0
		ok := scan_int(size_str, &chunk_size)
		if !ok || chunk_size == 0 {
			return total + crlf + 4
		}
		data_start := i + crlf + 2
		data_end := data_start + chunk_size
		if data_end + 2 > len(buf) do return -1
		total = data_end + 2
		i = data_end + 2
	}
}

scan_int :: proc "contextless" (s: string, out: ^int) -> bool {
	n := 0
	for c in s {
		if c >= '0' && c <= '9' {
			n = n * 10 + int(c - '0')
		} else {
			return false
		}
	}
	out^ = n
	return true
}

handle_polling_body :: proc(nc: ^Network_Client, body: []u8) {
	if len(body) == 0 do return
	i := 0
	for i < len(body) {
		code := body[i]
		rest := body[i + 1:]
		// Find the next packet boundary: Engine.IO packets are either a single
		// digit code followed by JSON (for open/close), or '4' followed by SIO
		// framing. In polling, multiple packets are separated by newlines.
		next_start := find_next_packet_start(rest)
		if next_start >= 0 {
			process_polling_packet(nc, code, rest[:next_start])
			i += 1 + next_start
		} else {
			process_polling_packet(nc, code, rest)
			break
		}
	}
}

find_next_packet_start :: proc(buf: []u8) -> int {
	depth := 0
	in_string := false
	escape := false
	for i in 0 ..< len(buf) {
		c := buf[i]
		if escape {
			escape = false
			continue
		}
		if c == '\\' && in_string {
			escape = true
			continue
		}
		if c == '"' {
			in_string = !in_string
			continue
		}
		if in_string do continue
		if c == '{' || c == '[' {
			depth += 1
		} else if c == '}' || c == ']' {
			depth -= 1
			if depth < 0 do return -1
		} else if c == '\n' && depth == 0 {
			return i
		}
	}
	return -1
}

process_polling_packet :: proc(nc: ^Network_Client, code: u8, payload: []u8) {
	switch code {
	case '0':
		nc.state = .OPEN
		nc.reconnect_attempts = 0
		nc.current_delay_ms = NET.RECONNECT_DELAY_MS
		nc.last_pong_recv_ms = now_ms()
		nc.last_ping_sent_ms = now_ms()
		if len(payload) > 0 {
			if v, ok := json_parse(payload); ok {
				obj := obj_of(v)
				if !is_null(v) {
					nc.sid = get_string(obj, "sid")
					nc.ping_interval_ms = u64(get_f64(obj, "pingInterval", 20000))
					nc.ping_timeout_ms = u64(get_f64(obj, "pingTimeout", 60000))
				}
			}
		}
		connect_pkt: string = "40"
		send_eio_polling_post(nc, connect_pkt)
	case '3':
		nc.last_pong_recv_ms = now_ms()
	case '4':
		handle_sio_frame(nc, payload)
	case '1':
		handle_disconnect(nc)
	case '2':
		pong: string = "3"
		send_eio_polling_post(nc, pong)
	case:
	}
}

service_polling_recv :: proc(nc: ^Network_Client, t: u64) {
	if nc.socket == 0 do return
	if t - nc.last_poll_ms < u64(NET.POLLING_INTERVAL_MS / 2) do return
	nc.last_poll_ms = t
	send_eio_polling_get(nc)
	buf: [8192]u8
	for {
		n, err := net.recv(nc.socket, buf[:])
		if n > 0 {
			append(&nc.recv_buf, ..buf[:n])
		}
		if err != .Would_Block && err != .None {
			if err == .Connection_Closed {
				handle_disconnect(nc)
			}
			return
		}
		if n <= 0 do return
		if n < len(buf) do break
	}
	handle_polling_http_response(nc, t)
}

// ── time ──────────────────────────────────────────────────────────────────

// Wall-clock milliseconds since the UNIX epoch (Time._nsec is UNIX ns).
now_ms :: proc "contextless" () -> u64 {
	return u64(time.now()._nsec / 1_000_000)
}
