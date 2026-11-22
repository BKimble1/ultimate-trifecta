class_name RelayTransport
extends NetTransport
## Party-code transport over the game service's WebSocket relay
## (service/src/relay.js: GET /v1/relay/<CODE>?role=host|guest, one Durable
## Object per room code).  Joining by code needs no Game Center matchmaking:
## the host and every guest each open one WebSocket to the relay, which only
## forwards bytes.  Reliable and unreliable both ride the WebSocket (TCP), so
## everything arrives, in order.
##
## Framing (u16 big-endian):
##   host -> relay   [u16 to][payload]        to = 0: every guest (one frame)
##   relay -> host   [u16 from][payload]
##   relay -> host   [0xFFFF][u8 kind][u16 peer][utf8 player]  1 joined, 2 left
##   guest <-> relay [payload]                always to / from the host
## The host is peer 1 and guests are 2, 3, ...  A "joined" frame names the
## guest's verified Game Center player (the one its admission credential is
## bound to), so peer_uid() is what the relay vouched for, as GameKit's
## player ids are.  A guest's one peer is the host (HOST_PEER), whose player
## is the host the service named for the room.

signal opened
## the connection could not be made, or was lost: a short, human message
signal failed(message: String)

const HOST_PEER := 1
const BROADCAST := 0
const CONTROL := 0xFFFF
const CTRL_JOINED := 1
const CTRL_LEFT := 2
const MAX_PAYLOAD := 64 * 1024
const CONNECT_TIMEOUT_S := 8.0
## close codes the relay uses (service/src/relay.js CLOSE)
const CLOSE_HOST_LEFT := 4000
const CLOSE_REPLACED := 4001
const CLOSE_NO_HOST := 4002
const CLOSE_FULL := 4003

enum State { IDLE, CONNECTING, OPEN, CLOSED, FAILED }

## a WebSocketPeer, or a stand-in with the same calls (tests)
var ws: Variant = null
var state: int = State.IDLE
var url := ""
var last_error := ""
var close_code := -1
var _guests: Dictionary = {}     # host: peer -> verified player
var _host_uid := ""              # guest: the host's player (the service named it)
var _t0_ms := 0
var stats_in := 0
var stats_out := 0
## host: reconnects tried since the connection was last open (App)
var reconnects := 0
var _greeted := false            # the session has been told the connection is up


func _init(host: bool) -> void:
	is_host = host
	kind = "relay"


## wss://<service>/v1/relay/<CODE>?role=host|guest&token=<session>
## (https -> wss, http -> ws).  The token also goes in the Authorization
## header; the query copy is for WebSocket clients that can't set headers.
static func relay_url(base: String, code: String, role: String, token: String) -> String:
	var b := base.strip_edges().trim_suffix("/")
	if b.begins_with("https://"):
		b = "wss://" + b.substr(8)
	elif b.begins_with("http://"):
		b = "ws://" + b.substr(7)
	return "%s/v1/relay/%s?role=%s&token=%s" % [b, code.uri_encode(), role, token.uri_encode()]


## Host: open the relay for our room (the service checks it is ours).
func host(relay: String, token: String) -> Error:
	is_host = true
	return _open(relay, token)


## Guest: connect to the room's host; host_uid is the Game Center player
## the service's join named as host (NetSession.expected_host_uid).
func join(relay: String, token: String, host_uid: String) -> Error:
	is_host = false
	_host_uid = host_uid
	return _open(relay, token)


## Host: connect again after the connection was lost (the relay then tells
## us again about any guest still there).
func reopen(relay: String, token: String) -> Error:
	if state == State.CONNECTING or state == State.OPEN:
		return OK
	if ws is WebSocketPeer:
		ws = null   # a closed WebSocketPeer starts over as a new one
	_guests.clear()
	return _open(relay, token)


func _open(relay: String, token: String) -> Error:
	url = relay
	close_code = -1
	last_error = ""
	if ws == null:
		ws = WebSocketPeer.new()
	if ws is WebSocketPeer:
		var p := ws as WebSocketPeer
		# a frame is up to 64 KB plus its header; a burst of snapshots and
		# events queues several
		p.inbound_buffer_size = 1 << 20
		p.outbound_buffer_size = 1 << 20
		p.max_queued_packets = 4096
		p.handshake_headers = PackedStringArray(["Authorization: Bearer %s" % token])
	var err: int = ws.connect_to_url(relay)
	_t0_ms = Time.get_ticks_msec()
	if err != OK:
		_fail("Couldn't reach the party. Check your connection and try again.")
		return err as Error
	state = State.CONNECTING
	return OK


func peers() -> Array:
	if state != State.OPEN:
		return []
	if is_host:
		return _guests.keys()
	return [HOST_PEER]


func peer_uid(peer: int) -> String:
	if is_host:
		return String(_guests.get(peer, ""))
	return _host_uid if peer == HOST_PEER else ""


func is_open() -> bool:
	return state == State.CONNECTING or state == State.OPEN


func connected() -> bool:
	return state == State.OPEN


func send(peer: int, data: PackedByteArray, _reliable: bool) -> void:
	if state != State.OPEN or data.is_empty() or data.size() > MAX_PAYLOAD:
		return
	if is_host:
		if not _guests.has(peer):
			return
		_put(frame(peer, data))
	elif peer == HOST_PEER:
		_put(data)


func broadcast(data: PackedByteArray, _reliable: bool) -> void:
	if state != State.OPEN or data.is_empty() or data.size() > MAX_PAYLOAD:
		return
	if is_host:
		if not _guests.is_empty():
			_put(frame(BROADCAST, data))
	else:
		_put(data)


func _put(bytes: PackedByteArray) -> void:
	stats_out += 1
	ws.send(bytes, WebSocketPeer.WRITE_MODE_BINARY)


## [u16 to][payload]
static func frame(to: int, payload: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(2)
	out[0] = (to >> 8) & 0xFF
	out[1] = to & 0xFF
	out.append_array(payload)
	return out


func poll(_dt: float) -> void:
	if ws == null or state == State.IDLE or state == State.CLOSED or state == State.FAILED:
		return
	ws.poll()
	if state == State.CONNECTING:
		_check_connect()
	if state == State.OPEN:
		if not _greeted:
			# (here, not in _check_connect: wait_open() connects before the
			# session listens, and nothing may be emitted to nobody - the
			# host's first message waits in the socket until now)
			_greeted = true
			if not is_host:
				peer_joined.emit(HOST_PEER)
		while ws.get_available_packet_count() > 0:
			var data: PackedByteArray = ws.get_packet()
			if ws.was_string_packet():
				continue
			stats_in += 1
			_on_frame(data)
			if state != State.OPEN:
				return
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			close_code = int(ws.get_close_code())
			_lost(_explain(close_code, true))


## Connecting: open, refused or timed out (emits nothing but opened / failed).
func _check_connect() -> void:
	var st: int = ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		state = State.OPEN
		reconnects = 0
		_greeted = false
		opened.emit()
	elif st == WebSocketPeer.STATE_CLOSED:
		close_code = int(ws.get_close_code())
		_fail(_explain(close_code, false))
	elif Time.get_ticks_msec() - _t0_ms > int(CONNECT_TIMEOUT_S * 1000.0):
		ws.close(1000, "timeout")
		_fail("Couldn't reach the party. Check your connection and try again.")


func _on_frame(data: PackedByteArray) -> void:
	if not is_host:
		if not data.is_empty():
			packet_received.emit(HOST_PEER, data)
		return
	if data.size() < 3:
		return
	var from := (data[0] << 8) | data[1]
	if from == CONTROL:
		if data.size() < 5:
			return
		var k := data[2]
		var peer := (data[3] << 8) | data[4]
		if peer < 2 or peer == CONTROL:
			return
		if k == CTRL_JOINED:
			var who := data.slice(5).get_string_from_utf8() if data.size() > 5 else ""
			if _guests.has(peer):
				return
			_guests[peer] = who
			peer_joined.emit(peer)
		elif k == CTRL_LEFT:
			if _guests.erase(peer):
				peer_left.emit(peer)
		return
	if not _guests.has(from):
		return   # a guest the relay never announced
	packet_received.emit(from, data.slice(2))


## The connection dropped after it was open: everyone on the other side is
## gone (the session sees them leave).
func _lost(message: String) -> void:
	state = State.CLOSED
	last_error = message
	var gone: Array = peers_snapshot()
	_guests.clear()
	for p in gone:
		peer_left.emit(p)
	failed.emit(message)


func peers_snapshot() -> Array:
	return _guests.keys() if is_host else [HOST_PEER]


func _fail(message: String) -> void:
	state = State.FAILED
	last_error = message
	failed.emit(message)


## Player-facing words for a close (never raw socket errors).
func _explain(code: int, was_open: bool) -> String:
	match code:
		CLOSE_HOST_LEFT:
			return "The host left the party."
		CLOSE_NO_HOST:
			return "That party's host isn't connected right now. Try again in a moment."
		CLOSE_FULL:
			return "That party is full."
		CLOSE_REPLACED:
			return "You joined this party from another connection."
	if was_open:
		return "Lost the connection to the party."
	if is_host:
		return "Couldn't open your party online. Check your connection and try again."
	return "Couldn't reach that party. Check the code and try again."


func close() -> void:
	if ws != null and (state == State.CONNECTING or state == State.OPEN):
		ws.close(1000, "bye")
		# one last poll flushes the close frame
		ws.poll()
	state = State.CLOSED
	_guests.clear()


## Wait (polling) until the connection is open or has failed; at most
## CONNECT_TIMEOUT_S.  Returns "" when open, else the message to show.
func wait_open(tree: SceneTree) -> String:
	while state == State.CONNECTING:
		await tree.process_frame
		if ws != null and state == State.CONNECTING:
			ws.poll()
			_check_connect()
	if state == State.OPEN:
		return ""
	return last_error if last_error != "" else "Couldn't reach the party. Check your connection and try again."
