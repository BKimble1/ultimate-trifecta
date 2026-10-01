class_name LoopbackTransport
extends NetTransport
## In-process transport for automated tests and local multi-client runs.
## Simulates one-way latency, jitter and packet loss on a simulated clock so
## tests are deterministic. Reliable packets are never lost and stay ordered.

class Hub:
	extends RefCounted
	var endpoints: Dictionary = {}   # id -> LoopbackTransport
	var next_id := 1
	var time := 0.0
	var latency_ms := 0.0            # one-way base latency
	var jitter_ms := 0.0
	var loss := 0.0                  # unreliable loss probability
	var frozen: Dictionary = {}      # endpoint id -> true: app frozen (sends/receives nothing)
	var rng := RandomNumberGenerator.new()
	var sent := 0
	var dropped := 0
	var bytes := 0

	func _init(seed_v: int = 1) -> void:
		rng.seed = seed_v

	func connect_ep(ep: LoopbackTransport) -> int:
		var id := next_id
		next_id += 1
		endpoints[id] = ep
		return id

	func advance(dt: float) -> void:
		time += dt
		for ep in endpoints.values():
			ep._deliver(time)

	func link(a: int, b: int) -> void:
		var ea: LoopbackTransport = endpoints[a]
		var eb: LoopbackTransport = endpoints[b]
		if not ea._links.has(b):
			ea._links[b] = true
			ea.peer_joined.emit(b)
		if not eb._links.has(a):
			eb._links[a] = true
			eb.peer_joined.emit(a)

	func unlink(a: int, b: int) -> void:
		if endpoints.has(a) and (endpoints[a] as LoopbackTransport)._links.erase(b):
			(endpoints[a] as LoopbackTransport).peer_left.emit(b)
		if endpoints.has(b) and (endpoints[b] as LoopbackTransport)._links.erase(a):
			(endpoints[b] as LoopbackTransport).peer_left.emit(a)

var hub: Hub
var id := 0
var _links: Dictionary = {}
var _queue: Array = []       # {t, from, data}
var _last_reliable_t: Dictionary = {}


func _init(h: Hub, host: bool) -> void:
	hub = h
	is_host = host
	kind = "loopback"
	id = hub.connect_ep(self)


func peers() -> Array:
	return _links.keys()


func send(peer: int, data: PackedByteArray, reliable: bool) -> void:
	if not _links.has(peer) or not hub.endpoints.has(peer) or hub.frozen.has(id):
		return
	hub.sent += 1
	hub.bytes += data.size()
	if not reliable and hub.loss > 0.0 and hub.rng.randf() < hub.loss:
		hub.dropped += 1
		return
	var delay := (hub.latency_ms + hub.rng.randf_range(-hub.jitter_ms, hub.jitter_ms)) / 1000.0
	var t := hub.time + maxf(0.0, delay)
	var dst: LoopbackTransport = hub.endpoints[peer]
	if reliable:
		var key := "%d>%d" % [id, peer]
		t = maxf(t, float(_last_reliable_t.get(key, 0.0)))
		_last_reliable_t[key] = t
	dst._queue.append({"t": t, "from": id, "data": data})


func _deliver(now: float) -> void:
	if _queue.is_empty() or hub.frozen.has(id):
		return
	_queue.sort_custom(func(a, b): return a["t"] < b["t"])
	while not _queue.is_empty() and float(_queue[0]["t"]) <= now:
		var pkt: Dictionary = _queue.pop_front()
		if _links.has(pkt["from"]):
			packet_received.emit(int(pkt["from"]), pkt["data"])


func close() -> void:
	for p in _links.keys():
		hub.unlink(id, p)
	hub.endpoints.erase(id)
