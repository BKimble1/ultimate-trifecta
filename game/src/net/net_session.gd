class_name NetSession
extends Node
## A private room. One player hosts (server-authoritative player host); the
## host runs MatchSim and is the only authority on stamps, captures, finishes
## and results. This is a convenience trust model for a private beta: the host
## device could cheat and the host is not an independent server.
## OFFLINE mode runs the same host path with bots for solo practice.

signal lobby_changed
signal match_starting(info: Dictionary)
signal results_received(results: Dictionary)
signal ended(reason: String)
signal events_received(events: Array)
signal snapshot_received(snap: Dictionary)
signal status_changed(text: String)

enum Mode { OFFLINE, HOST, CLIENT }

const BOT_NAMES := ["Bot Snooze", "Bot Pillow", "Bot Slipper", "Bot Yawn", "Bot Moonbeam", "Bot Sockfoot", "Bot Drowsy", "Bot Pajamarama"]

var mode: int = Mode.OFFLINE
var transport: NetTransport
var room_code := ""
var local_uid := ""
var local_name := "Player"
var local_cosmetic: Dictionary = {}
var local_pref := "any"
var local_slot := -1
var host_peer := -1
var roster: Array = []          # 8 entries: Dictionary or null
var spectators: Dictionary = {} # peer -> {uid, name}
var phase: int = TC.Phase.LOBBY
var round_no := 0
var prev_targets: Array = []
var current_start: Dictionary = {}
var last_results: Dictionary = {}
var sim: MatchSim = null
var tutorial := false
var cfg: RulesConfig

# host bookkeeping
var _peer_slot: Dictionary = {}     # peer -> slot
var _queues: Dictionary = {}        # slot -> Array[InputCmd]
var _last_seq: Dictionary = {}      # slot -> int
var _rtt: Dictionary = {}           # peer -> seconds
var _relevance: Dictionary = {}     # "recipient:slot" -> hold time
var _pending_events: Array = []
var stat_starved: Dictionary = {}   # slot -> ticks with no input available
var stat_skipped: Dictionary = {}   # slot -> inputs merged while catching up
var _snap_counter := 0
var _ping_t := 0.0

# client bookkeeping
var _last_event_id := 0
var _host_silence := 0.0
var _announce_t := 0.0
var _hello_sent := false
var _no_host_t := 0.0
var rtt := 0.1
var connected := false
var _ended := false
var muted: Dictionary = {}          # uid -> true (local block list: hide emotes)


func _init() -> void:
	cfg = Rules.cfg
	roster.resize(8)


func _ready() -> void:
	if cfg == null:
		cfg = RulesConfig.new()


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
func start_offline(uid: String, name: String, cosmetic: Dictionary, pref: String, is_tutorial: bool = false) -> void:
	mode = Mode.OFFLINE
	tutorial = is_tutorial
	_set_identity(uid, name, cosmetic, pref)
	roster.fill(null)
	roster[0] = _entry(0, uid, name, false, -1, cosmetic, pref)
	roster[0]["ready"] = true
	local_slot = 0
	room_code = "PRACTICE"
	connected = true


func start_host(t: NetTransport, code: String, uid: String, name: String, cosmetic: Dictionary, pref: String) -> void:
	mode = Mode.HOST
	transport = t
	room_code = code
	_set_identity(uid, name, cosmetic, pref)
	roster.fill(null)
	roster[0] = _entry(0, uid, name, false, -1, cosmetic, pref)
	local_slot = 0
	connected = true
	_wire_transport()
	_broadcast_lobby()


func start_client(t: NetTransport, code: String, uid: String, name: String, cosmetic: Dictionary, pref: String) -> void:
	mode = Mode.CLIENT
	transport = t
	room_code = code
	_set_identity(uid, name, cosmetic, pref)
	roster.fill(null)
	_wire_transport()
	status_changed.emit("Looking for room %s…" % code)


func _set_identity(uid: String, name: String, cosmetic: Dictionary, pref: String) -> void:
	local_uid = uid
	local_name = name
	local_cosmetic = Cosmetics.sanitize(cosmetic)
	local_pref = pref


func _entry(slot: int, uid: String, name: String, is_bot: bool, peer: int, cosmetic: Dictionary, pref: String) -> Dictionary:
	return {"slot": slot, "uid": uid, "name": name, "is_bot": is_bot, "peer": peer, "ready": false,
		"pref": pref, "cosmetic": Cosmetics.sanitize(cosmetic), "connected": true,
		"patrol_rounds": 0, "last_was_patrol": false, "role": -1}


func _wire_transport() -> void:
	transport.peer_joined.connect(_on_peer_joined)
	transport.peer_left.connect(_on_peer_left)
	transport.packet_received.connect(_on_packet)


func is_host() -> bool:
	return mode == Mode.HOST or mode == Mode.OFFLINE


func human_count() -> int:
	var n := 0
	for e in roster:
		if e != null and not bool(e["is_bot"]):
			n += 1
	return n


func can_start() -> bool:
	if not is_host() or phase != TC.Phase.LOBBY:
		return false
	for e in roster:
		if e != null and not bool(e["is_bot"]) and int(e["slot"]) != local_slot and not bool(e["ready"]):
			return false
	return true


# ---------------------------------------------------------------------------
# Transport events
# ---------------------------------------------------------------------------
func _on_peer_joined(peer: int) -> void:
	if mode == Mode.HOST:
		var b := Protocol.buf_for(Protocol.M.ANNOUNCE)
		b.put_u8(1)
		Protocol.put_str(b, local_uid)
		Protocol.put_str(b, room_code)
		transport.send(peer, b.data_array, true)
	elif mode == Mode.CLIENT:
		_announce_t = 0.0


func _on_peer_left(peer: int) -> void:
	if mode == Mode.HOST:
		spectators.erase(peer)
		if _peer_slot.has(peer):
			var slot: int = _peer_slot[peer]
			_peer_slot.erase(peer)
			_drop_slot(slot)
	elif mode == Mode.CLIENT and peer == host_peer:
		_end("host_left")


func _drop_slot(slot: int) -> void:
	var e: Variant = roster[slot]
	if e == null:
		return
	if phase == TC.Phase.LOBBY or phase == TC.Phase.RESULTS:
		roster[slot] = null
	else:
		e["connected"] = false
		e["peer"] = -1
		if sim != null:
			sim.set_disconnected(slot)
	_broadcast_lobby()


func _on_packet(peer: int, data: PackedByteArray) -> void:
	if data.is_empty():
		return
	var b := Protocol.reader(data)
	var type := b.get_u8()
	if mode == Mode.HOST:
		_host_packet(peer, type, b)
	elif mode == Mode.CLIENT:
		if peer == host_peer:
			_host_silence = 0.0
		_client_packet(peer, type, b)


# ---------------------------------------------------------------------------
# Host side
# ---------------------------------------------------------------------------
func _host_packet(peer: int, type: int, b: StreamPeerBuffer) -> void:
	match type:
		Protocol.M.HELLO:
			var ver := b.get_u16()
			var uid := Protocol.get_str(b)
			var name := Protocol.get_str(b)
			var cos := Protocol.get_appearance(b)
			var pref: String = ["any", "runner", "patrol"][clampi(b.get_u8(), 0, 2)]
			if ver != Protocol.VERSION:
				_send_welcome(peer, -1, "version")
				return
			if transport.peer_uid(peer) != "":
				uid = transport.peer_uid(peer)   # Game Center identity wins
			_host_admit(peer, uid, name, cos, pref)
		Protocol.M.READY:
			if _peer_slot.has(peer):
				var e: Dictionary = roster[_peer_slot[peer]]
				e["ready"] = b.get_u8() == 1
				e["pref"] = ["any", "runner", "patrol"][clampi(b.get_u8(), 0, 2)]
				_broadcast_lobby()
		Protocol.M.COSMETIC:
			if _peer_slot.has(peer) and phase == TC.Phase.LOBBY:
				roster[_peer_slot[peer]]["cosmetic"] = Protocol.get_appearance(b)
				_broadcast_lobby()
		Protocol.M.EMOTE:
			if _peer_slot.has(peer):
				var em := b.get_u8()
				_host_emote(_peer_slot[peer], em)
		Protocol.M.INPUT:
			if _peer_slot.has(peer) and sim != null:
				var slot: int = _peer_slot[peer]
				var d := Protocol.decode_inputs(b)
				_queue_inputs(slot, d["cmds"])
				if int(d["emote"]) >= 0:
					_host_emote(slot, int(d["emote"]))
		Protocol.M.PING:
			var t := b.get_double()
			var r := Protocol.buf_for(Protocol.M.PONG)
			r.put_double(t)
			transport.send(peer, r.data_array, false)
		Protocol.M.PONG:
			var sent := b.get_double()
			var now := Time.get_ticks_usec() / 1000000.0
			_rtt[peer] = lerpf(float(_rtt.get(peer, now - sent)), now - sent, 0.3)
		Protocol.M.LEAVE:
			_on_peer_left(peer)


func _host_admit(peer: int, uid: String, name: String, cosmetic: Dictionary, pref: String) -> void:
	# reconnect into a reserved slot?
	for e in roster:
		if e != null and not bool(e["is_bot"]) and String(e["uid"]) == uid and not bool(e["connected"]):
			if sim != null and phase >= TC.Phase.REVEAL and phase <= TC.Phase.PLAYING:
				if sim.resume(int(e["slot"]), uid):
					e["connected"] = true
					e["peer"] = peer
					_peer_slot[peer] = int(e["slot"])
					_queues[int(e["slot"])] = []
					_send_welcome(peer, int(e["slot"]), "resumed")
					_send_start(peer)
					_broadcast_lobby()
					return
			else:
				e["connected"] = true
				e["peer"] = peer
				_peer_slot[peer] = int(e["slot"])
				_send_welcome(peer, int(e["slot"]), "")
				_broadcast_lobby()
				return
	# duplicate identity already connected: treat as the same player reconnecting
	for e in roster:
		if e != null and String(e["uid"]) == uid and bool(e["connected"]) and int(e["peer"]) != peer and int(e["slot"]) != local_slot:
			_peer_slot.erase(int(e["peer"]))
			e["peer"] = peer
			_peer_slot[peer] = int(e["slot"])
			_send_welcome(peer, int(e["slot"]), "")
			if phase != TC.Phase.LOBBY:
				_send_start(peer)
			_broadcast_lobby()
			return
	var in_match := phase >= TC.Phase.LOADING and phase <= TC.Phase.PLAYING
	if not in_match:
		for i in roster.size():
			if roster[i] == null or (bool(roster[i]["is_bot"]) and phase == TC.Phase.LOBBY):
				roster[i] = _entry(i, uid, name, false, peer, cosmetic, pref)
				_peer_slot[peer] = i
				_send_welcome(peer, i, "")
				_broadcast_lobby()
				return
	# room full or round in progress: spectate until the next round
	spectators[peer] = {"uid": uid, "name": name, "cosmetic": cosmetic, "pref": pref}
	_send_welcome(peer, -1, "spectate" if in_match else "full")
	if in_match:
		_send_start(peer)
	_broadcast_lobby()


func _send_welcome(peer: int, slot: int, reason: String) -> void:
	var b := Protocol.buf_for(Protocol.M.WELCOME)
	b.put_8(slot)
	Protocol.put_str(b, reason)
	transport.send(peer, b.data_array, true)


func _host_emote(slot: int, em: int) -> void:
	if sim != null and phase == TC.Phase.PLAYING:
		sim.request_emote(slot, em)
	else:
		var ev := {"id": 0, "t": 0, "type": TC.Ev.EMOTE, "a": slot, "b": -1, "v": em, "pos": Vector3.ZERO}
		events_received.emit([ev])
		if mode == Mode.HOST:
			var data := Protocol.encode_events([ev])
			transport.broadcast(data, true)


func set_local_ready(ready: bool) -> void:
	if is_host():
		if roster[local_slot] != null:
			roster[local_slot]["ready"] = ready
			roster[local_slot]["pref"] = local_pref
		_broadcast_lobby()
		return
	var b := Protocol.buf_for(Protocol.M.READY)
	b.put_u8(1 if ready else 0)
	b.put_u8(["any", "runner", "patrol"].find(local_pref))
	transport.send(host_peer, b.data_array, true)


func set_local_pref(pref: String) -> void:
	local_pref = pref
	var e: Variant = roster[local_slot] if local_slot >= 0 else null
	set_local_ready(bool(e["ready"]) if e != null else false)


func set_local_cosmetic(c: Dictionary) -> void:
	local_cosmetic = Cosmetics.sanitize(c)
	if is_host():
		if local_slot >= 0 and roster[local_slot] != null:
			roster[local_slot]["cosmetic"] = local_cosmetic
		_broadcast_lobby()
	elif host_peer >= 0:
		var b := Protocol.buf_for(Protocol.M.COSMETIC)
		Protocol.put_appearance(b, local_cosmetic)
		transport.send(host_peer, b.data_array, true)


func send_emote(em: int) -> void:
	if is_host():
		_host_emote(local_slot, em)
	elif host_peer >= 0:
		var b := Protocol.buf_for(Protocol.M.EMOTE)
		b.put_u8(em)
		transport.send(host_peer, b.data_array, true)


func kick(slot: int) -> void:
	if mode != Mode.HOST or slot == local_slot or roster[slot] == null:
		return
	var peer := int(roster[slot]["peer"])
	if peer >= 0:
		var b := Protocol.buf_for(Protocol.M.KICK)
		transport.send(peer, b.data_array, true)
		_peer_slot.erase(peer)
	roster[slot] = null
	_broadcast_lobby()


func _lobby_bytes() -> PackedByteArray:
	var b := Protocol.buf_for(Protocol.M.LOBBY)
	Protocol.put_str(b, room_code)
	b.put_u8(phase)
	b.put_u16(round_no)
	b.put_u8(spectators.size())
	for i in 8:
		var e: Variant = roster[i]
		if e == null:
			b.put_u8(0)
			continue
		b.put_u8(1)
		Protocol.put_str(b, String(e["uid"]))
		Protocol.put_str(b, String(e["name"]))
		var flags := 0
		if bool(e["is_bot"]): flags |= 1
		if bool(e["ready"]): flags |= 2
		if bool(e["connected"]): flags |= 4
		if i == local_slot: flags |= 8
		b.put_u8(flags)
		b.put_u8(["any", "runner", "patrol"].find(String(e["pref"])))
		b.put_8(int(e.get("role", -1)))
		Protocol.put_appearance(b, e["cosmetic"])
	return b.data_array


func _broadcast_lobby() -> void:
	lobby_changed.emit()
	if mode == Mode.HOST and transport != null:
		transport.broadcast(_lobby_bytes(), true)


## Host: start the next round. Fills empty slots with clearly labelled bots,
## assigns roles fairly, picks shared targets from the seed.
func host_start_match(seed_override: int = -1) -> void:
	if not is_host():
		return
	round_no += 1
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var seed_v := seed_override if seed_override >= 0 else int(rng.randi() & 0x7FFFFFFF)
	# promote spectators into free slots first
	for peer in spectators.keys():
		for i in 8:
			if roster[i] == null or bool(roster[i]["is_bot"]):
				var sp: Dictionary = spectators[peer]
				roster[i] = _entry(i, sp["uid"], sp["name"], false, peer, sp["cosmetic"], sp["pref"])
				_peer_slot[peer] = i
				_send_welcome(peer, i, "")
				spectators.erase(peer)
				break
	var bot_i := 0
	for i in 8:
		if roster[i] == null or bool(roster[i]["is_bot"]):
			roster[i] = _entry(i, "bot-%d" % i, BOT_NAMES[(bot_i + seed_v) % BOT_NAMES.size()], true, -1, Cosmetics.bot_cosmetic(seed_v + i * 13), "any")
			bot_i += 1
	var plist: Array = []
	for e in roster:
		plist.append({"slot": e["slot"], "pref": e["pref"], "patrol_rounds": e["patrol_rounds"], "last_was_patrol": e["last_was_patrol"], "is_bot": e["is_bot"]})
	var roles := RulesLogic.assign_roles(plist, cfg.patrol_slots, seed_v)
	if tutorial:
		for e in roster:
			roles[e["slot"]] = TC.Role.RUNNER if int(e["slot"]) == local_slot else (TC.Role.PATROL if int(e["slot"]) <= 2 else TC.Role.RUNNER)
		if roles.values().count(TC.Role.PATROL) != cfg.patrol_slots:
			var need := cfg.patrol_slots
			for e in roster:
				roles[e["slot"]] = TC.Role.RUNNER
			for e in roster:
				if need > 0 and int(e["slot"]) != local_slot:
					roles[e["slot"]] = TC.Role.PATROL
					need -= 1
	var targets := RulesLogic.pick_targets(seed_v, prev_targets)
	prev_targets = targets
	var start_roster: Array = []
	for e in roster:
		e["role"] = roles[e["slot"]]
		e["ready"] = false
		start_roster.append({"slot": e["slot"], "uid": e["uid"], "name": e["name"], "is_bot": e["is_bot"], "role": e["role"], "cosmetic": e["cosmetic"]})
	current_start = {
		"match_id": "%s-%d-%08x" % [room_code, round_no, seed_v], "seed": seed_v, "targets": targets,
		"roster": start_roster, "practice": mode == Mode.OFFLINE, "tutorial": tutorial, "round": round_no,
	}
	phase = TC.Phase.LOADING
	_queues.clear()
	_last_seq.clear()
	_pending_events.clear()
	if mode == Mode.HOST:
		for peer in transport.peers():
			_send_start(peer)
	_broadcast_lobby()
	match_starting.emit(current_start)


func _start_bytes() -> PackedByteArray:
	var b := Protocol.buf_for(Protocol.M.START)
	var json := JSON.stringify(_jsonable(current_start))
	var u := json.to_utf8_buffer()
	b.put_u32(u.size())
	b.put_data(u)
	return b.data_array


func _send_start(peer: int) -> void:
	if current_start.is_empty():
		return
	transport.send(peer, _start_bytes(), true)


static func _jsonable(v: Variant) -> Variant:
	if v is Dictionary:
		var d := {}
		for k in v:
			d[str(k)] = _jsonable(v[k])
		return d
	if v is Array:
		var a: Array = []
		for x in v:
			a.append(_jsonable(x))
		return a
	if v is Vector3:
		return [v.x, v.y, v.z]
	return v


## Host: called by the match controller once its MatchSim exists.
func attach_sim(s: MatchSim) -> void:
	sim = s
	phase = TC.Phase.REVEAL
	s.event_emitted.connect(func(ev: Dictionary) -> void: _pending_events.append(ev))
	for e in roster:
		if e != null and not bool(e["is_bot"]) and not bool(e["connected"]):
			s.set_disconnected(int(e["slot"]))


func _queue_inputs(slot: int, cmds: Array) -> void:
	var q: Array = _queues.get(slot, [])
	var last := int(_last_seq.get(slot, -1))
	for c in cmds:
		var cmd: InputCmd = c
		if cmd.seq <= last:
			continue  # duplicate / late (already processed)
		var dup := false
		for existing in q:
			if (existing as InputCmd).seq == cmd.seq:
				dup = true
				break
		if not dup:
			q.append(cmd)
	q.sort_custom(func(a, b): return a.seq < b.seq)
	_queues[slot] = q


## Host: inputs for this tick (one per remote human; edges merged if we catch up).
func host_collect_inputs() -> Dictionary:
	var out := {}
	for slot in _queues.keys():
		var q: Array = _queues[slot]
		if q.is_empty():
			stat_starved[slot] = int(stat_starved.get(slot, 0)) + 1
			continue
		var cmd: InputCmd = q.pop_front()
		# stay near real time: if the buffer grows, skip ahead but keep button edges
		while q.size() > 6:
			var nxt: InputCmd = q.pop_front()
			nxt.pressed |= cmd.pressed
			cmd = nxt
			stat_skipped[slot] = int(stat_skipped.get(slot, 0)) + 1
		_last_seq[slot] = cmd.seq
		out[slot] = cmd
		var p := sim.player(slot) if sim else null
		if p:
			p.last_seq = cmd.seq
	return out


## Host: after sim.step — reliable events every tick, snapshots at 20 Hz.
func host_after_step(dt: float) -> void:
	if sim == null:
		return
	phase = sim.phase
	if mode == Mode.HOST:
		if not _pending_events.is_empty():
			transport.broadcast(Protocol.encode_events(_pending_events), true)
		_snap_counter += 1
		if _snap_counter >= cfg.snapshot_every_ticks:
			_snap_counter = 0
			for peer in transport.peers():
				var slot := int(_peer_slot.get(peer, -1))
				var rec: SimPlayer = sim.player(slot) if slot >= 0 else null
				if rec:
					rec.lag_ticks = int(round((float(_rtt.get(peer, 0.1)) * 0.5 + cfg.interp_delay_s) * cfg.sim_hz))
				var rel := _relevant_for(rec, dt * cfg.snapshot_every_ticks)
				var data := Protocol.encode_snapshot(sim, rec, rel, int(_last_seq.get(slot, -1)), rec != null)
				transport.send(peer, data, false)
		_ping_t += dt
		if _ping_t > 1.0:
			_ping_t = 0.0
			var pb := Protocol.buf_for(Protocol.M.PING)
			pb.put_double(Time.get_ticks_usec() / 1000000.0)
			transport.broadcast(pb.data_array, false)
	_pending_events.clear()


## Interest management: patrol clients only receive runners they could plausibly
## see or hear; runners only receive patrol nearby or in sight. Spectators and
## teammates get everything relevant to watching.
func _relevant_for(rec: SimPlayer, dt: float) -> Array:
	var out: Array = []
	for p in sim.players:
		if rec == null or p == rec or p.role == rec.role or rec.state == TC.PState.FINISHED:
			out.append(p)
			continue
		var key := "%d:%d" % [rec.id, p.id]
		var d := rec.pos().distance_to(p.pos())
		var rel := false
		if p.state == TC.PState.CAPTURED or p.state == TC.PState.FINISHED:
			rel = false
		elif d <= 45.0:
			rel = true
		elif d <= 90.0 and sim.has_los(rec.pos() + Vector3(0, 1.5, 0), p.pos() + Vector3(0, 1.0, 0)):
			rel = true
		if rel:
			_relevance[key] = 1.0
		else:
			_relevance[key] = float(_relevance.get(key, 0.0)) - dt
		if float(_relevance.get(key, 0.0)) > 0.0:
			out.append(p)
	return out


func host_match_finished(results: Dictionary) -> void:
	last_results = results
	phase = TC.Phase.RESULTS
	if results.get("outcome", 0) != TC.Outcome.CANCELLED:
		for e in roster:
			if e == null:
				continue
			e["last_was_patrol"] = int(e["role"]) == TC.Role.PATROL
			if int(e["role"]) == TC.Role.PATROL:
				e["patrol_rounds"] = int(e["patrol_rounds"]) + 1
	if mode == Mode.HOST:
		var b := Protocol.buf_for(Protocol.M.RESULTS)
		var u := JSON.stringify(_jsonable(results)).to_utf8_buffer()
		b.put_u32(u.size())
		b.put_data(u)
		transport.broadcast(b.data_array, true)
	results_received.emit(results)


## Host: back to the dorm lobby for a rematch (rematch cleanup).
func host_return_to_lobby() -> void:
	if not is_host():
		return
	sim = null
	phase = TC.Phase.LOBBY
	_queues.clear()
	_last_seq.clear()
	_relevance.clear()
	_pending_events.clear()
	for i in 8:
		var e: Variant = roster[i]
		if e == null:
			continue
		if bool(e["is_bot"]) and mode == Mode.HOST:
			roster[i] = null   # bots are re-filled at start
			continue
		if not bool(e["is_bot"]) and not bool(e["connected"]):
			roster[i] = null   # disconnected players free their slot between rounds
			continue
		e["ready"] = false
		e["role"] = -1
	_broadcast_lobby()


# ---------------------------------------------------------------------------
# Client side
# ---------------------------------------------------------------------------
func _client_packet(peer: int, type: int, b: StreamPeerBuffer) -> void:
	match type:
		Protocol.M.ANNOUNCE:
			var is_h := b.get_u8() == 1
			var _uid := Protocol.get_str(b)
			var code := Protocol.get_str(b)
			if is_h and (room_code == "" or code == room_code or transport.kind != "gamekit"):
				host_peer = peer
				room_code = code
				_send_hello()
		Protocol.M.WELCOME:
			local_slot = b.get_8()
			var reason := Protocol.get_str(b)
			connected = true
			if reason == "version":
				_end("version")
				return
			if local_slot < 0 and reason == "full":
				status_changed.emit("Room is full — watching until a slot opens.")
			lobby_changed.emit()
		Protocol.M.LOBBY:
			_read_lobby(b)
		Protocol.M.START:
			var n := b.get_u32()
			var r: Array = b.get_data(n)
			if r[0] != OK:
				return
			var parsed: Variant = JSON.parse_string((r[1] as PackedByteArray).get_string_from_utf8())
			if parsed is Dictionary:
				current_start = _fix_start(parsed)
				phase = TC.Phase.LOADING
				_last_event_id = 0
				match_starting.emit(current_start)
		Protocol.M.SNAP:
			snapshot_received.emit(Protocol.decode_snapshot(b))
		Protocol.M.EVENTS:
			var evs := Protocol.decode_events(b)
			var fresh: Array = []
			for e in evs:
				if int(e["id"]) == 0 or int(e["id"]) > _last_event_id:
					fresh.append(e)
					if int(e["id"]) > 0:
						_last_event_id = int(e["id"])
			if not fresh.is_empty():
				events_received.emit(fresh)
		Protocol.M.RESULTS:
			var n2 := b.get_u32()
			var r2: Array = b.get_data(n2)
			if r2[0] == OK:
				var parsed2: Variant = JSON.parse_string((r2[1] as PackedByteArray).get_string_from_utf8())
				if parsed2 is Dictionary:
					last_results = _fix_results(parsed2)
					phase = TC.Phase.RESULTS
					results_received.emit(last_results)
		Protocol.M.PING:
			var t := b.get_double()
			var rb := Protocol.buf_for(Protocol.M.PONG)
			rb.put_double(t)
			transport.send(peer, rb.data_array, false)
		Protocol.M.PONG:
			var sent := b.get_double()
			rtt = lerpf(rtt, Time.get_ticks_usec() / 1000000.0 - sent, 0.3)
		Protocol.M.HOST_END:
			_end("host_ended")
		Protocol.M.KICK:
			_end("kicked")


func _send_hello() -> void:
	var b := Protocol.buf_for(Protocol.M.HELLO)
	b.put_u16(Protocol.VERSION)
	Protocol.put_str(b, local_uid)
	Protocol.put_str(b, local_name)
	Protocol.put_appearance(b, local_cosmetic)
	b.put_u8(["any", "runner", "patrol"].find(local_pref))
	transport.send(host_peer, b.data_array, true)
	_hello_sent = true


func _read_lobby(b: StreamPeerBuffer) -> void:
	room_code = Protocol.get_str(b)
	var ph := b.get_u8()
	round_no = b.get_u16()
	var nspec := b.get_u8()
	for i in 8:
		if b.get_u8() == 0:
			roster[i] = null
			continue
		var uid := Protocol.get_str(b)
		var name := Protocol.get_str(b)
		var flags := b.get_u8()
		var pref: String = ["any", "runner", "patrol"][clampi(b.get_u8(), 0, 2)]
		var role := b.get_8()
		var e := _entry(i, uid, name, (flags & 1) != 0, -1, Protocol.get_appearance(b), pref)
		e["ready"] = (flags & 2) != 0
		e["connected"] = (flags & 4) != 0
		e["is_host"] = (flags & 8) != 0
		e["role"] = role
		roster[i] = e
	if ph == TC.Phase.LOBBY and phase == TC.Phase.RESULTS:
		phase = TC.Phase.LOBBY
	elif ph == TC.Phase.LOBBY:
		phase = TC.Phase.LOBBY
	set_meta("spectators", nspec)
	lobby_changed.emit()


func _fix_start(d: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	out["seed"] = int(d["seed"])
	var t: Array = []
	for x in d["targets"]:
		t.append(int(x))
	out["targets"] = t
	var ro: Array = []
	for e in d["roster"]:
		var c: Dictionary = e["cosmetic"]
		ro.append({"slot": int(e["slot"]), "uid": String(e["uid"]), "name": String(e["name"]), "is_bot": bool(e["is_bot"]), "role": int(e["role"]),
			"cosmetic": Cosmetics.sanitize(c)})
	out["roster"] = ro
	return out


func _fix_results(d: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	out["outcome"] = int(d["outcome"])
	out["fastest_slot"] = int(d.get("fastest_slot", -1))
	var rows: Array = []
	for r in d.get("players", []):
		var rr: Dictionary = r.duplicate()
		for k in ["slot", "role", "stamps", "finish_order", "times_captured", "captures", "unique_captures"]:
			rr[k] = int(r.get(k, 0))
		rows.append(rr)
	out["players"] = rows
	return out


func client_send_inputs(window: Array, emote: int = -1) -> void:
	if mode != Mode.CLIENT or host_peer < 0:
		return
	transport.send(host_peer, Protocol.encode_inputs(window, emote), false)


func leave() -> void:
	if transport != null:
		if mode == Mode.CLIENT and host_peer >= 0:
			transport.send(host_peer, Protocol.buf_for(Protocol.M.LEAVE).data_array, true)
		elif mode == Mode.HOST:
			transport.broadcast(Protocol.buf_for(Protocol.M.HOST_END).data_array, true)
		transport.poll(0.0)
	_end("left")


func _end(reason: String) -> void:
	if _ended:
		return
	_ended = true
	connected = false
	ended.emit(reason)
	if transport != null:
		var t := transport
		# give reliable goodbyes a moment, then close
		if is_inside_tree():
			get_tree().create_timer(0.3).timeout.connect(func() -> void: t.close())
		else:
			t.close()


# ---------------------------------------------------------------------------
# Per-frame
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if transport == null or _ended:
		return
	transport.poll(delta)
	if mode == Mode.CLIENT:
		if host_peer < 0:
			_no_host_t += delta
			if _no_host_t > 12.0 and transport.kind == "gamekit":
				_end("room_not_found")
		else:
			_host_silence += delta
			if _host_silence > cfg.host_timeout_s:
				_end("host_timeout")
		if host_peer >= 0 and not _hello_sent:
			_send_hello()
		if host_peer >= 0:
			_ping_t += delta
			if _ping_t > 1.0:
				_ping_t = 0.0
				var pb := Protocol.buf_for(Protocol.M.PING)
				pb.put_double(Time.get_ticks_usec() / 1000000.0)
				transport.send(host_peer, pb.data_array, false)
