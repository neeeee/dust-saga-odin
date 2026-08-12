package systems

import "core:encoding/base64"
import "core:encoding/json"
import "core:fmt"
import "core:math/rand"
import "core:net"

// Socket.IO transport layer, split from the core client (see networkclient.odin).
// Holds the WebSocket frame codec, the Engine.IO / Socket.IO framing, and the
// HTTP long-polling fallback transport. The Network_Client struct and the
// public send API live in networkclient.odin; everything here operates on
// ^Network_Client.

// ── receive loop (shared by both transports) ──────────────────────────────

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

// ── WebSocket framing ─────────────────────────────────────────────────────

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
					nc.sid = get_string_owned(obj, "sid")
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

// Reverse-map a wire integer to a Packet_Type, rejecting values that aren't
// named members of the enum. The valid-bit table is seeded from the enum
// itself on first use, so it stays in sync automatically — no hand-maintained
// switch to update when packets are added.
PACKET_TYPE_MAX_WIRE :: 189 // == int(Packet_Type.FLOATING_TEXT), the highest value
packet_type_valid: [PACKET_TYPE_MAX_WIRE + 1]bool
packet_type_valid_seeded: bool

int_to_packet_type :: proc(n: int) -> (Packet_Type, bool) {
	if !packet_type_valid_seeded {
		for pt in Packet_Type do packet_type_valid[int(pt)] = true
		packet_type_valid_seeded = true
	}
	if n < 0 || n > PACKET_TYPE_MAX_WIRE do return .CONNECT, false
	if !packet_type_valid[n] do return .CONNECT, false
	return cast(Packet_Type)n, true
}

// ── WebSocket send helpers ────────────────────────────────────────────────

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
					nc.sid = get_string_owned(obj, "sid")
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
