extends RefCounted
## RelayTransport (the party-code relay client) against a fake socket: the
## frame format of service/src/relay.js, the peers NetSession expects, and
## failures that end in a clear message instead of a hang.  The last test
## drives real NetSessions (host and two guests) through an in-process fake
## of the relay.  The real relay (wrangler dev, real WebSockets) is
## tools/relay_e2e.sh.
var t


## The calls RelayTransport makes on a WebSocketPeer.
class FakeSocket:
	extends RefCounted
	var state := WebSocketPeer.STATE_CONNECTING
	var inbox: Array = []    # [PackedByteArray, is_text]
	var outbox: Array = []   # PackedByteArray
	var url := ""
	var close_code := -1
	var closed_by_us := false
	var relay: FakeRelay = null
	var _text := false

	func connect_to_url(u: String, _tls: Variant = null) -> int:
		url = u
		state = WebSocketPeer.STATE_CONNECTING
		return OK

	func poll() -> void:
		if relay:
			relay.pump()

	func get_ready_state() -> int:
		return state

	func get_available_packet_count() -> int:
		return inbox.size()

	func get_packet() -> PackedByteArray:
		var p: Array = inbox.pop_front()
		_text = bool(p[1])
		return p[0]

	func was_string_packet() -> bool:
		return _text

	func send(b: PackedByteArray, _mode: int = 1) -> int:
		outbox.append(b)
		return OK

	func close(code: int = 1000, _reason: String = "") -> void:
		if state != WebSocketPeer.STATE_CLOSED:
			closed_by_us = true
			close_code = code
		state = WebSocketPeer.STATE_CLOSED
		if relay:
			relay.gone(self)

	func get_close_code() -> int:
		return close_code

	func deliver(b: PackedByteArray, text := false) -> void:
		inbox.append([b, text])

	func drop(code: int) -> void:
		close_code = code
		state = WebSocketPeer.STATE_CLOSED


## An in-process stand-in for the relay (service/src/relay.js RelayCore):
## the same frames and ids, no network.
class FakeRelay:
	extends RefCounted
	var host: FakeSocket = null
	var guests: Dictionary = {}   # peer -> FakeSocket
	var players: Dictionary = {}  # peer -> player
	var next := 2

	func add_host(s: FakeSocket) -> void:
		s.relay = self
		s.state = WebSocketPeer.STATE_OPEN
		host = s

	func add_guest(s: FakeSocket, player: String) -> int:
		s.relay = self
		s.state = WebSocketPeer.STATE_OPEN
		var p := next
		next += 1
		guests[p] = s
		players[p] = player
		host.deliver(_ctrl(1, p, player))
		return p

	func _ctrl(k: int, p: int, player: String) -> PackedByteArray:
		var b := PackedByteArray([0xFF, 0xFF, k, (p >> 8) & 0xFF, p & 0xFF])
		b.append_array(player.to_utf8_buffer())
		return b

	func pump() -> void:
		if host == null:
			return
		for f in host.outbox:
			var to := (int(f[0]) << 8) | int(f[1])
			var payload: PackedByteArray = f.slice(2)
			if to == 0:
				for g in guests.values():
					g.deliver(payload)
			elif guests.has(to):
				guests[to].deliver(payload)
		host.outbox.clear()
		for p in guests:
			var g: FakeSocket = guests[p]
			for f in g.outbox:
				host.deliver(RelayTransport.frame(p, f))
			g.outbox.clear()

	func gone(s: FakeSocket) -> void:
		if s == host:
			for g in guests.values():
				g.drop(RelayTransport.CLOSE_HOST_LEFT)
			guests.clear()
			return
		for p in guests.keys():
			if guests[p] == s:
				guests.erase(p)
				host.deliver(_ctrl(2, p, String(players[p])))


func _transport(host: bool) -> Array:
	var rt := RelayTransport.new(host)
	var s := FakeSocket.new()
	rt.ws = s
	var ev := {"joined": [], "left": [], "packets": [], "failed": [], "opened": 0}
	rt.peer_joined.connect(func(p: int) -> void: ev["joined"].append(p))
	rt.peer_left.connect(func(p: int) -> void: ev["left"].append(p))
	rt.packet_received.connect(func(p: int, d: PackedByteArray) -> void: ev["packets"].append([p, Array(d)]))
	rt.failed.connect(func(m: String) -> void: ev["failed"].append(m))
	rt.opened.connect(func() -> void: ev["opened"] += 1)
	return [rt, s, ev]


func test_relay_url() -> void:
	t.eq(RelayTransport.relay_url("https://svc.example.dev/", "ACDEFG", "host", "a.b+c/="),
		"wss://svc.example.dev/v1/relay/ACDEFG?role=host&token=a.b%2Bc%2F%3D", "https -> wss, token encoded")
	t.eq(RelayTransport.relay_url("http://127.0.0.1:8787", "QRTWXY", "guest", "tok"),
		"ws://127.0.0.1:8787/v1/relay/QRTWXY?role=guest&token=tok", "http -> ws (local development)")
	t.eq(RelayTransport.new(true).kind, "relay", "kind")


func test_relay_host_framing() -> void:
	var a := _transport(true)
	var rt: RelayTransport = a[0]
	var s: FakeSocket = a[1]
	var ev: Dictionary = a[2]
	t.eq(rt.host("wss://x/v1/relay/ACDEFG?role=host&token=t", "t"), OK, "connects")
	t.check(rt.is_open() and not rt.connected(), "connecting")
	rt.send(2, PackedByteArray([1]), true)
	t.eq(s.outbox.size(), 0, "nothing goes out before the socket is open")
	s.state = WebSocketPeer.STATE_OPEN
	rt.poll(0.016)
	t.eq(int(ev["opened"]), 1, "opened")
	t.eq(rt.peers(), [], "a host starts with no guests")
	t.eq(ev["joined"], [], "and announces none")
	# control frames: joined (with the verified player) and left
	s.deliver(PackedByteArray([0xFF, 0xFF, 1, 0, 2]) + "G:ann".to_utf8_buffer())
	s.deliver(PackedByteArray([0xFF, 0xFF, 1, 0, 3]) + "G:ben".to_utf8_buffer())
	rt.poll(0.016)
	t.eq(ev["joined"], [2, 3], "guests 2 and 3 joined")
	t.eq(rt.peers(), [2, 3], "peers() is the connected guests")
	t.eq(rt.peer_uid(3), "G:ben", "the relay-verified player of each guest")
	t.eq(rt.peer_uid(9), "", "nobody else")
	# guest -> host: [u16 from][payload]
	s.deliver(PackedByteArray([0, 2, 7, 8, 9]))
	s.deliver(PackedByteArray([0, 9, 1]))       # never announced: dropped
	s.deliver(PackedByteArray([0, 3]))          # no payload: dropped
	s.deliver("hi".to_utf8_buffer(), true)      # text: dropped
	rt.poll(0.016)
	t.eq(ev["packets"], [[2, [7, 8, 9]]], "only the announced guest's binary payload arrives, from its id")
	# host -> one guest / everyone
	rt.send(3, PackedByteArray([5, 6]), false)
	rt.send(4, PackedByteArray([5]), true)      # not a guest
	rt.broadcast(PackedByteArray([42]), true)
	t.eq(s.outbox.map(func(b: PackedByteArray) -> Array: return Array(b)), [[0, 3, 5, 6], [0, 0, 42]],
		"[u16 to][payload]; a broadcast is one frame to 0")
	var big := PackedByteArray()
	big.resize(RelayTransport.MAX_PAYLOAD + 1)
	rt.send(2, big, true)
	t.eq(s.outbox.size(), 2, "nothing over 64 KB")
	# a guest leaves
	s.deliver(PackedByteArray([0xFF, 0xFF, 2, 0, 2]))
	s.deliver(PackedByteArray([0xFF, 0xFF, 2, 0, 2]))   # (once)
	rt.poll(0.016)
	t.eq(ev["left"], [2], "left")
	t.eq(rt.peers(), [3], "gone from peers()")
	# the connection drops: every guest leaves, with a message
	s.drop(1006)
	rt.poll(0.016)
	t.eq(ev["left"], [2, 3], "everyone left with the connection")
	t.eq(ev["failed"], ["Lost the connection to the party."], "a short message, no socket error text")
	t.check(not rt.is_open(), "closed")
	# the host can connect again (App reconnects a dropped host)
	t.eq(rt.reopen("wss://x/v1/relay/ACDEFG?role=host&token=t2", "t2"), OK, "reopen")
	s.state = WebSocketPeer.STATE_OPEN
	rt.poll(0.016)
	t.check(rt.connected(), "open again")


func test_relay_guest_framing() -> void:
	var a := _transport(false)
	var rt: RelayTransport = a[0]
	var s: FakeSocket = a[1]
	var ev: Dictionary = a[2]
	rt.join("wss://x/v1/relay/ACDEFG?role=guest&token=t", "t", "G:host")
	rt.poll(0.016)
	t.eq(ev["joined"], [], "no host before the socket opens")
	s.state = WebSocketPeer.STATE_OPEN
	rt.poll(0.016)
	t.eq(ev["joined"], [RelayTransport.HOST_PEER], "the host appears as peer 1")
	t.eq(rt.peers(), [1], "one peer: the host")
	t.eq(rt.peer_uid(1), "G:host", "the host the service named (NetSession.expected_host_uid)")
	rt.send(1, PackedByteArray([3, 4]), true)
	rt.send(2, PackedByteArray([9]), true)      # not the host
	rt.broadcast(PackedByteArray([5]), false)
	t.eq(s.outbox.map(func(b: PackedByteArray) -> Array: return Array(b)), [[3, 4], [5]], "payload only, always to the host")
	s.deliver(PackedByteArray([1, 2, 3]))
	rt.poll(0.016)
	t.eq(ev["packets"], [[1, [1, 2, 3]]], "everything arrives from the host")
	s.drop(RelayTransport.CLOSE_HOST_LEFT)
	rt.poll(0.016)
	t.eq(ev["left"], [1], "the host left")
	t.eq(ev["failed"], ["The host left the party."], "in words")


## App connects (wait_open) before the session listens: what the host says
## at once (its ANNOUNCE) must wait for the session, never be emitted to
## nobody (found by tools/relay_e2e.sh: a fast guest sometimes never bound).
func test_relay_nothing_is_lost_before_the_session_listens() -> void:
	var rt := RelayTransport.new(false)
	var s := FakeSocket.new()
	rt.ws = s
	rt.join("wss://x", "t", "G:h")
	s.state = WebSocketPeer.STATE_OPEN
	s.deliver(PackedByteArray([1, 2, 3]))      # the host's first message is already here
	t.eq(await rt.wait_open(t.get_tree()), "", "open")
	t.eq(s.inbox.size(), 1, "still waiting in the socket")
	var joined: Array = []
	var got: Array = []
	rt.peer_joined.connect(func(p: int) -> void: joined.append(p))
	rt.packet_received.connect(func(p: int, d: PackedByteArray) -> void: got.append([p, Array(d)]))
	rt.poll(0.016)
	t.eq(joined, [1], "the session hears the host joined")
	t.eq(got, [[1, [1, 2, 3]]], "and then its first message")


func test_relay_connect_failures_end_with_a_message() -> void:
	# refused (the service said no: unknown code, not a member, ...)
	var a := _transport(false)
	var rt: RelayTransport = a[0]
	var s: FakeSocket = a[1]
	rt.join("wss://x", "t", "G:h")
	s.drop(1006)
	var msg: String = await rt.wait_open(t.get_tree())
	t.eq(msg, "Couldn't reach that party. Check the code and try again.", "a guest's refused connection")
	t.check(not msg.to_lower().contains("error") and not msg.contains("1006"), "no raw error text")
	var b := _transport(true)
	(b[0] as RelayTransport).host("wss://x", "t")
	(b[1] as FakeSocket).drop(1006)
	t.eq(await (b[0] as RelayTransport).wait_open(t.get_tree()), "Couldn't open your party online. Check your connection and try again.",
		"a host's")
	var c := _transport(false)
	(c[0] as RelayTransport).join("wss://x", "t", "G:h")
	(c[1] as FakeSocket).drop(RelayTransport.CLOSE_FULL)
	t.eq(await (c[0] as RelayTransport).wait_open(t.get_tree()), "That party is full.", "the relay's reason when it gives one")
	# no answer at all: gives up after about 8 s instead of hanging
	var d := _transport(false)
	var rd: RelayTransport = d[0]
	rd.join("wss://x", "t", "G:h")
	rd.poll(0.016)
	t.check(rd.is_open(), "still trying at first")
	rd._t0_ms -= int(RelayTransport.CONNECT_TIMEOUT_S * 1000.0) + 100
	var m2: String = await rd.wait_open(t.get_tree())
	t.eq(m2, "Couldn't reach the party. Check your connection and try again.", "timed out")
	t.check((d[1] as FakeSocket).closed_by_us, "the socket was closed")
	t.eq((d[2] as Dictionary)["failed"].size(), 1, "failed once")


## Real NetSessions over RelayTransport through the fake relay: the guests
## appear in the host's roster with the identity the relay vouched for,
## lobby and ready state flow both ways, and a removed guest is gone.
func test_relay_sessions_lobby() -> void:
	var relay := FakeRelay.new()
	var ht := RelayTransport.new(true)
	var hs := FakeSocket.new()
	ht.ws = hs
	ht.host("wss://x/v1/relay/ACDEFG?role=host", "t")
	relay.add_host(hs)
	var host := NetSession.new()
	host.name = "RelayHost"
	t.add_child(host)
	host.start_host(ht, "ACDEFG", "G:host", "Host", {}, "any")
	var guests: Array[NetSession] = []
	var ends := {}
	for i in 2:
		var gt := RelayTransport.new(false)
		var gs := FakeSocket.new()
		gt.ws = gs
		gt.join("wss://x/v1/relay/ACDEFG?role=guest", "t", "G:host")
		var g := NetSession.new()
		g.name = "RelayGuest%d" % i
		t.add_child(g)
		g.expected_host_uid = "G:host"
		g.start_client(gt, "ACDEFG", "claimed-%d" % i, "Guest%d" % i, {}, "any")
		g.ended.connect(func(r: String) -> void: ends[i] = r)
		relay.add_guest(gs, "G:guest%d" % i)
		guests.append(g)
	for _i in 120:
		await t.get_tree().physics_frame
		if host.human_count() == 3 and guests.all(func(g: NetSession) -> bool: return g.local_slot >= 1 and g.human_count() == 3):
			break
	t.eq(host.human_count(), 3, "both guests are in the host's roster")
	var uids: Array = []
	for e in host.roster:
		if e != null and not bool(e["is_bot"]):
			uids.append(String(e["uid"]))
	t.check(uids.has("G:guest0") and uids.has("G:guest1"), "with the player the relay vouched for, not the claimed one (%s)" % str(uids))
	for g in guests:
		t.check(g.local_slot >= 1, "each guest got a slot")
		t.eq(g.host_peer, RelayTransport.HOST_PEER, "bound to the host (peer 1)")
		t.eq(g.human_count(), 3, "guests see the whole roster")
	guests[0].set_local_ready(true)
	var slot0 := guests[0].local_slot
	for _i in 60:
		await t.get_tree().physics_frame
		if host.roster[slot0] != null and bool(host.roster[slot0]["ready"]):
			break
	t.check(host.roster[slot0] != null and bool(host.roster[slot0]["ready"]), "ready reaches the host")
	host.kick(guests[1].local_slot)
	for _i in 60:
		await t.get_tree().physics_frame
		if ends.has(1) and host.human_count() == 2:
			break
	t.eq(String(ends.get(1, "")), "kicked", "the removed guest's session ends")
	t.eq(host.human_count(), 2, "and leaves the host's roster")
	host.leave()
	for _i in 30:
		await t.get_tree().physics_frame
		if ends.has(0):
			break
	t.check(String(ends.get(0, "")) in ["host_ended", "host_left"], "the host leaving ends the guest's party (%s)" % String(ends.get(0, "")))
	for n in [host] + guests:
		if is_instance_valid(n):
			n.queue_free()
	await t.get_tree().process_frame
