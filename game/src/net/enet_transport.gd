class_name EnetTransport
extends NetTransport
## ENet over UDP for desktop/LAN development clients and multi-process tests.
## Optional outbound shaping (latency/jitter/loss) using real time so separate
## processes can be tested under 80-150 ms RTT and packet loss.
## Not used by the iOS release UI (iOS internet play uses GameKitTransport).

const CH_RELIABLE := 0
const CH_UNRELIABLE := 1

var peer := ENetMultiplayerPeer.new()
var latency_ms := 0.0      # one-way added latency applied to outgoing packets
var jitter_ms := 0.0
var loss := 0.0
var rng := RandomNumberGenerator.new()
var _out: Array = []       # {t, peer, data, reliable}
var _peers: Dictionary = {}
var _open := false
var stats_sent := 0
var stats_dropped := 0


func host(port: int, max_clients: int = 15) -> Error:
	is_host = true
	kind = "enet"
	var err := peer.create_server(port, max_clients, 2)
	if err == OK:
		_wire()
	return err


func join(address: String, port: int) -> Error:
	is_host = false
	kind = "enet"
	var err := peer.create_client(address, port, 2)
	if err == OK:
		_wire()
	return err


func _wire() -> void:
	_open = true
	rng.randomize()
	peer.peer_connected.connect(func(id: int) -> void:
		_peers[id] = true
		peer_joined.emit(id))
	peer.peer_disconnected.connect(func(id: int) -> void:
		_peers.erase(id)
		peer_left.emit(id))


func peers() -> Array:
	return _peers.keys()


func is_open() -> bool:
	return _open and peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED


func send(to: int, data: PackedByteArray, reliable: bool) -> void:
	if not _open:
		return
	stats_sent += 1
	if not reliable and loss > 0.0 and rng.randf() < loss:
		stats_dropped += 1
		return
	if latency_ms <= 0.0 and jitter_ms <= 0.0:
		_raw_send(to, data, reliable)
		return
	var t := Time.get_ticks_usec() / 1000000.0 + maxf(0.0, (latency_ms + rng.randf_range(-jitter_ms, jitter_ms)) / 1000.0)
	_out.append({"t": t, "peer": to, "data": data, "reliable": reliable})


func _raw_send(to: int, data: PackedByteArray, reliable: bool) -> void:
	# a peer can leave while packets to it are still queued (shaped latency),
	# and when several drop at once ENet keeps the others as zombies (no
	# channels) until their own disconnect is polled: sending then errors
	if not _peers.has(to):
		return
	var pp := peer.get_peer(to)
	if pp == null or not pp.is_active():
		return
	peer.set_target_peer(to)
	peer.transfer_channel = CH_RELIABLE if reliable else CH_UNRELIABLE
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
	peer.put_packet(data)


func poll(_dt: float) -> void:
	if not _open:
		return
	if not _out.is_empty():
		var now := Time.get_ticks_usec() / 1000000.0
		# reliable packets keep their order: never send one before an earlier reliable one
		var keep: Array = []
		var reliable_blocked := false
		for o in _out:
			var due := float(o["t"]) <= now
			if bool(o["reliable"]):
				if due and not reliable_blocked:
					_raw_send(int(o["peer"]), o["data"], true)
				else:
					reliable_blocked = true
					keep.append(o)
			elif due:
				_raw_send(int(o["peer"]), o["data"], false)
			else:
				keep.append(o)
		_out = keep
	peer.poll()
	while peer.get_available_packet_count() > 0:
		var from := peer.get_packet_peer()
		var data := peer.get_packet()
		packet_received.emit(from, data)


func close() -> void:
	if _open:
		peer.close()
	_open = false
	_peers.clear()
