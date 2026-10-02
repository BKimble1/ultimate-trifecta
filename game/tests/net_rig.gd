class_name NetRig
extends Node
## In-process network rig: one host NetSession + N client NetSessions over a
## LoopbackTransport hub with configurable latency/jitter/loss. Each match
## controller lives in its own SubViewport (own World3D = own physics space),
## so client prediction collides against its own copy of the campus.
## Label for reports: "simulated network clients (in-process, loopback)".

var hub: LoopbackTransport.Hub
var host: NetSession
var clients: Array[NetSession] = []
var host_t: LoopbackTransport
var client_ts: Array[LoopbackTransport] = []
var mcs: Dictionary = {}          # session -> MatchController
var vps: Dictionary = {}          # session -> SubViewport
var started: Dictionary = {}      # session -> start info
var ended_reason: Dictionary = {} # session -> reason
var results: Dictionary = {}      # session -> results
var host_events: Array = []
var client_events: Dictionary = {}
var inputs: Dictionary = {}       # session -> Callable(mc) -> InputCmd
var host_positions: Dictionary = {} # slot -> {tick: pos}
var pass_through := true


func setup(latency_ms: float, jitter_ms: float, loss: float, n_clients: int, prefs: Array = []) -> void:
	hub = LoopbackTransport.Hub.new(42)
	hub.latency_ms = latency_ms
	hub.jitter_ms = jitter_ms
	hub.loss = loss
	host_t = LoopbackTransport.new(hub, true)
	host = NetSession.new()
	host.name = "Host"
	add_child(host)
	host.start_host(host_t, "TEST1", "uid-host", "Host", {}, prefs[0] if prefs.size() > 0 else "any")
	# V4 friend parties draw roles fairly at random; tests that need a role
	# layout ask for it explicitly
	for i in prefs.size():
		var uid := "uid-host" if i == 0 else "uid-c%d" % (i - 1)
		if String(prefs[i]) == "patrol":
			host.role_override[uid] = TC.Role.PATROL
		elif String(prefs[i]) == "runner":
			host.role_override[uid] = TC.Role.RUNNER
	_wire(host)
	for i in n_clients:
		add_client("uid-c%d" % i, "Client%d" % i, prefs[i + 1] if prefs.size() > i + 1 else "any")


func add_client(uid: String, name: String, pref: String = "any") -> NetSession:
	var ct := LoopbackTransport.new(hub, false)
	var c := NetSession.new()
	c.name = "Client_" + uid
	add_child(c)
	c.start_client(ct, "TEST1", uid, name, {}, pref)
	clients.append(c)
	client_ts.append(ct)
	_wire(c)
	hub.link(host_t.id, ct.id)
	return c


func _wire(s: NetSession) -> void:
	s.match_starting.connect(func(info: Dictionary) -> void:
		started[s] = info
		_spawn_mc(s, info))
	s.ended.connect(func(reason: String) -> void: ended_reason[s] = reason)
	s.results_received.connect(func(r: Dictionary) -> void: results[s] = r)
	if s == host:
		s.events_received.connect(func(evs: Array) -> void: pass)
	else:
		client_events[s] = []
		s.events_received.connect(func(evs: Array) -> void: (client_events[s] as Array).append_array(evs))


func _spawn_mc(s: NetSession, info: Dictionary) -> void:
	if mcs.has(s) and is_instance_valid(mcs[s]):
		mcs[s].queue_free()
	if not vps.has(s):
		var vp := SubViewport.new()
		vp.own_world_3d = true
		vp.size = Vector2i(64, 64)
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(vp)
		vps[s] = vp
	var mc := MatchController.new()
	mc.setup(s, info, {"visuals": false, "quality": 0})
	if inputs.has(s):
		mc.input_source = inputs[s]
	else:
		mc.input_source = func(_m: MatchController) -> InputCmd: return InputCmd.new()
	(vps[s] as SubViewport).add_child(mc)
	mcs[s] = mc
	if s == host:
		mc.sim.event_emitted.connect(func(ev: Dictionary) -> void: host_events.append(ev))


func _physics_process(delta: float) -> void:
	if pass_through:
		hub.advance(delta)
	# record authoritative host positions for interpolation-error measurement
	var hm: MatchController = mcs.get(host)
	if hm and is_instance_valid(hm) and hm.sim:
		for p in hm.sim.players:
			if not host_positions.has(p.id):
				host_positions[p.id] = {}
			host_positions[p.id][hm.sim.tick] = p.pos()


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func wait_until(cond: Callable, max_frames: int = 600) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


func host_mc() -> MatchController:
	return mcs.get(host)


func mc_of(s: NetSession) -> MatchController:
	return mcs.get(s)


func teardown() -> void:
	for s in [host] + clients:
		if is_instance_valid(s) and s.transport:
			s.transport.close()
	queue_free()
