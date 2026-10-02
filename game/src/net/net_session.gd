class_name NetSession
extends Node
## A private room. One player hosts (server-authoritative player host); the
## host runs MatchSim and is the only authority on stamps, captures, finishes
## and results. This is a convenience trust model for a private beta: the host
## device could cheat and the host is not an independent server.
## OFFLINE mode runs the same host path with bots for solo practice.
##
## Trust (protocol 4): a client binds to one host (the Game Center player the
## service named for the room, or the first announcing host on dev
## transports) and accepts host-only messages from nobody else; a later
## ANNOUNCE can never replace it.  With the service configured, the host
## admits only joiners whose admission credential verifies and belongs to the
## Game Center player who sent it, and takes their name from it.  Reconnects
## must present the per-slot rejoin key (or the same verified profile), so
## nobody can take over another player's slot.  Every read is bounded, enums
## and phases are checked, and peers are rate limited.

signal lobby_changed
signal match_starting(info: Dictionary)
signal results_received(results: Dictionary)
signal ended(reason: String)
signal events_received(events: Array)
signal snapshot_received(snap: Dictionary)
signal status_changed(text: String)
## client (invites): the host announced its code; fetch an admission for it,
## then call provide_admission()
signal admission_needed(code: String)
## the series (standings, completed rounds) changed
signal series_changed

enum Mode { OFFLINE, HOST, CLIENT }

## shown with a "BOT" tag everywhere (a tag player names can't contain)
const BOT_NAMES := ["Snooze", "Pillow", "Slipper", "Yawn", "Moonbeam", "Sockfoot", "Drowsy", "Pajamarama"]

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
## networking constants (tick rate, snapshot rate, timeouts) - the gameplay
## rules of a round come from round_cfg
var cfg: RulesConfig
## the immutable rules of the current round (PartySeries.rules_for)
var round_cfg: RulesConfig
## party settings (host edits them in the pre-series lobby; guests see the
## host's approved copy) - {watch, rounds, rev}
var settings: Dictionary = PartySeries.default_settings()
## host: the series in progress (null before the first Start)
var series: PartySeries = null
## everyone: the latest series view (host: its own; client: from the host)
var series_view: Dictionary = {}
## client: {active, next_round, total} from the lobby bytes
var series_brief: Dictionary = {}
## client: why ready was cleared ("" when nothing to say)
var settings_note := ""
## practice: "runner", "patrol" or "random"
var practice_role := "runner"
## tests and dev automation only: uid -> TC.Role forced after the fair draw
## (the Night Watch count is kept by swapping bots)
var role_override: Dictionary = {}

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

# trust (protocol 4)
## client: Game Center player (teamPlayerID) the service says hosts this room
var expected_host_uid := ""
## client: admission credential from the service, presented in HELLO
var admission := ""
## client: secret for reconnecting into our own slot (from WELCOME)
var rejoin_key := ""
## host: require a verified admission credential from every joiner
var require_admission := false
var admission_key: CryptoKey
var local_pid := ""                 # our verified profile id (service), if any
var _seen_jti: Dictionary = {}
var _rate: Dictionary = {}          # peer -> {w, input, other, strikes}
var _loaded: Dictionary = {}        # slot -> true: load acks for this round
## client: don't say HELLO until an admission credential is in hand
var hold_hello := false
var _clock := 0.0                   # seconds of session time (rate-limit windows)
var _loads_done := false
var _load_wait := 0.0
const LOAD_TIMEOUT_S := 15.0
const RATE_INPUT := 90              # per second
const RATE_OTHER := 25


func _init() -> void:
	cfg = Rules.cfg
	round_cfg = PartySeries.rules_for(Rules.cfg, PartySeries.DEFAULT_WATCH)
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
	practice_role = pref if pref in ["runner", "patrol", "random"] else "runner"
	settings = {"watch": PartySeries.DEFAULT_WATCH, "rounds": 1, "rev": 0}
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
	roster[0]["pid"] = local_pid
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
		"patrol_rounds": 0, "last_was_patrol": false, "role": -1, "pid": "", "rejoin_key": ""}


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
	if series != null and series.finished:
		return false   # the finished series is on show; Play again resets it
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
	if data.size() > 64 * 1024:
		return
	var b := Protocol.reader(data)
	var type := b.get_u8()
	if mode == Mode.HOST:
		if not _rate_ok(peer, type):
			return
		_host_packet(peer, type, b)
	elif mode == Mode.CLIENT:
		if type in Protocol.HOST_ONLY and (host_peer < 0 or peer != host_peer):
			return   # only our bound host may send these
		if peer == host_peer:
			_host_silence = 0.0
		_client_packet(peer, type, b)


## Host: per-peer budget per second (inputs vs everything else).  A peer that
## keeps flooding for three seconds is removed.
func _rate_ok(peer: int, type: int) -> bool:
	var now := int(_clock)   # session time (physics frames), not the wall clock
	var r: Dictionary = _rate.get(peer, {"w": now, "input": 0, "other": 0, "strikes": 0, "struck": false})
	if int(r["w"]) != now:
		if bool(r["struck"]):
			r["strikes"] = int(r["strikes"]) + 1
		else:
			r["strikes"] = 0
		r["w"] = now
		r["input"] = 0
		r["other"] = 0
		r["struck"] = false
	var key := "input" if type == Protocol.M.INPUT or type == Protocol.M.PONG or type == Protocol.M.PING else "other"
	r[key] = int(r[key]) + 1
	var ok := int(r[key]) <= (RATE_INPUT if key == "input" else RATE_OTHER)
	if not ok:
		r["struck"] = true
	_rate[peer] = r
	if int(r["strikes"]) >= 3:
		_rate.erase(peer)
		_remove_peer(peer, "flood")
		return false
	return ok


func _remove_peer(peer: int, _why: String) -> void:
	if _peer_slot.has(peer):
		var slot: int = _peer_slot[peer]
		kick(slot)
	else:
		transport.send(peer, Protocol.buf_for(Protocol.M.KICK).data_array, true)
		spectators.erase(peer)


# ---------------------------------------------------------------------------
# Host side
# ---------------------------------------------------------------------------
func _host_packet(peer: int, type: int, b: StreamPeerBuffer) -> void:
	match type:
		Protocol.M.HELLO:
			if b.get_available_bytes() < 2:
				return
			var ver := b.get_u16()
			if ver != Protocol.VERSION:
				_send_welcome(peer, -1, "version")
				return
			var uid := Protocol.get_str(b)
			var name := NameRules.safe_display(Protocol.get_str(b))
			var cos := Protocol.get_appearance(b)
			var pref: String = ["any", "runner", "patrol"][clampi(b.get_u8(), 0, 2)]
			var key := Protocol.get_str(b, 32)
			var token := Protocol.get_long_str(b)
			if transport.peer_uid(peer) != "":
				uid = transport.peer_uid(peer)   # Game Center identity wins
			var pid := ""
			if require_admission:
				var v := Admission.verify(token, admission_key, {"code": room_code, "gc": uid,
					"now": int(Time.get_unix_time_from_system()), "seen": _seen_jti})
				if not bool(v["ok"]):
					_send_welcome(peer, -1, "admission")
					return
				var claims: Dictionary = v["claims"]
				_seen_jti[String(claims["jti"])] = true
				pid = String(claims.get("sub", ""))
				# the service-approved name, not whatever the client typed
				name = NameRules.safe_display(String(claims.get("name", name)).get_slice("#", 0))
				if Save.is_blocked(pid, uid):
					_send_welcome(peer, -1, "not_allowed")
					return
			elif Save.is_blocked("", uid):
				_send_welcome(peer, -1, "not_allowed")
				return
			_host_admit(peer, uid, name, cos, pref, pid, key)
		Protocol.M.READY:
			if _peer_slot.has(peer) and (phase == TC.Phase.LOBBY or phase == TC.Phase.RESULTS) and b.get_available_bytes() >= 2:
				var e: Dictionary = roster[_peer_slot[peer]]
				e["ready"] = b.get_u8() == 1
				e["pref"] = ["any", "runner", "patrol"][clampi(b.get_u8(), 0, 2)]
				_broadcast_lobby()
		Protocol.M.COSMETIC:
			if _peer_slot.has(peer) and phase == TC.Phase.LOBBY:
				roster[_peer_slot[peer]]["cosmetic"] = Protocol.get_appearance(b)
				_broadcast_lobby()
		Protocol.M.EMOTE:
			if _peer_slot.has(peer) and b.get_available_bytes() >= 1:
				var em := b.get_u8()
				if em < TC.EMOTES.size():
					_host_emote(_peer_slot[peer], em)
		Protocol.M.INPUT:
			if _peer_slot.has(peer) and sim != null:
				var slot: int = _peer_slot[peer]
				var d := Protocol.decode_inputs(b)
				_queue_inputs(slot, d["cmds"])
				if int(d["emote"]) >= 0 and int(d["emote"]) < TC.EMOTES.size():
					_host_emote(slot, int(d["emote"]))
		Protocol.M.LOADED:
			if _peer_slot.has(peer) and b.get_available_bytes() >= 2 and b.get_u16() == round_no:
				_loaded[int(_peer_slot[peer])] = true
				_broadcast_lobby()   # everyone's loading screen shows who is ready
		Protocol.M.PING:
			if b.get_available_bytes() < 8:
				return
			var t := b.get_double()
			var r := Protocol.buf_for(Protocol.M.PONG)
			r.put_double(t)
			transport.send(peer, r.data_array, false)
		Protocol.M.PONG:
			if b.get_available_bytes() < 8:
				return
			var sent := b.get_double()
			var now := Time.get_ticks_usec() / 1000000.0
			if is_finite(sent) and now - sent >= 0.0 and now - sent < 10.0:
				_rtt[peer] = lerpf(float(_rtt.get(peer, now - sent)), now - sent, 0.3)
		Protocol.M.LEAVE:
			_on_peer_left(peer)


## Proof that a returning player owns a slot: the rejoin key the host gave
## them, or the same verified profile.
func _owns_slot(e: Dictionary, pid: String, key: String) -> bool:
	if key != "" and key == String(e.get("rejoin_key", "")):
		return true
	return pid != "" and pid == String(e.get("pid", ""))


func _host_admit(peer: int, uid: String, name: String, cosmetic: Dictionary, pref: String, pid: String = "", key: String = "") -> void:
	# reconnect into a reserved slot?
	for e in roster:
		if e != null and not bool(e["is_bot"]) and String(e["uid"]) == uid and not bool(e["connected"]) and _owns_slot(e, pid, key):
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
	# the same identity already connected: the same player on a new
	# connection, but only with proof (nobody can take over someone's slot)
	for e in roster:
		if e != null and String(e["uid"]) == uid and int(e["slot"]) != local_slot and not _owns_slot(e, pid, key) and not bool(e["is_bot"]):
			_send_welcome(peer, -1, "in_use")
			return
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
				roster[i]["pid"] = pid
				roster[i]["rejoin_key"] = Crypto.new().generate_random_bytes(12).hex_encode()
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
	# the rejoin key goes only to the slot's own player
	Protocol.put_str(b, String(roster[slot].get("rejoin_key", "")) if slot >= 0 and roster[slot] != null else "", 32)
	transport.send(peer, b.data_array, true)
	if not series_view.is_empty() and reason not in ["version", "admission", "not_allowed", "in_use"]:
		transport.send(peer, _series_bytes(), true)


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
	# protocol 5: party settings and where the series is
	b.put_u8(int(settings["watch"]))
	b.put_u8(int(settings["rounds"]))
	b.put_u16(int(settings["rev"]))
	var sstate := 0 if series == null else (2 if series.finished else 1)
	b.put_u8(sstate)
	b.put_u8(series.next_round() if series != null else 1)
	b.put_u8(series.rounds_total() if series != null else int(settings["rounds"]))
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
		if phase >= TC.Phase.LOADING and phase <= TC.Phase.PLAYING and (_loaded.has(i) or bool(e["is_bot"])): flags |= 16
		b.put_u8(flags)
		b.put_u8(["any", "runner", "patrol"].find(String(e["pref"])))
		b.put_8(int(e.get("role", -1)))
		Protocol.put_appearance(b, e["cosmetic"])
		Protocol.put_str(b, String(e.get("pid", "")), 40)
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
	# a friend party plays a series with the settings locked at its start;
	# practice is one round with the role the player chose
	if mode != Mode.OFFLINE and (series == null or not series.in_progress()):
		series = PartySeries.new()
		series.start(settings, rng)
		series_view = series.to_dict()
	var locked: Dictionary = series.settings if series != null else settings
	if mode == Mode.OFFLINE and tutorial and practice_role == "patrol":
		locked = {"watch": 1, "rounds": 1, "rev": 0}   # Night Watch training: you are the only watcher
	round_cfg = PartySeries.rules_for(Rules.cfg, int(locked["watch"]))
	var roles := {}
	if mode == Mode.OFFLINE:
		roles = _practice_roles(seed_v, int(locked["watch"]))
	else:
		var plist: Array = []
		for e in roster:
			plist.append({"slot": e["slot"], "uid": e["uid"], "is_bot": e["is_bot"]})
		roles = series.assign_roles(plist, seed_v)
	if tutorial and practice_role == "patrol":
		# Night Watch training: you watch, everyone else runs
		for e in roster:
			roles[e["slot"]] = TC.Role.PATROL if int(e["slot"]) == local_slot else TC.Role.RUNNER
	elif tutorial:
		# the runner tutorial: you run, the first other seats are the Night Watch
		var need := round_cfg.patrol_slots
		for e in roster:
			roles[e["slot"]] = TC.Role.RUNNER
		for e in roster:
			if need > 0 and int(e["slot"]) != local_slot:
				roles[e["slot"]] = TC.Role.PATROL
				need -= 1
	if not role_override.is_empty():
		roles = _apply_role_override(roles, round_cfg.patrol_slots)
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
		"training": ("watch" if practice_role == "patrol" else "runner") if tutorial else "",
		"settings": {"watch": int(locked["watch"]), "rounds": int(locked["rounds"]), "rev": int(locked["rev"])},
		"series": {"id": series.id if series != null else "", "round": series.next_round() if series != null else 1,
			"total": series.rounds_total() if series != null else 1},
	}
	phase = TC.Phase.LOADING
	_queues.clear()
	_last_seq.clear()
	_pending_events.clear()
	_loaded.clear()
	_load_wait = 0.0
	_loads_done = false
	if mode == Mode.HOST:
		for peer in transport.peers():
			_send_start(peer)
	_broadcast_lobby()
	match_starting.emit(current_start)


func _apply_role_override(roles: Dictionary, watch: int) -> Dictionary:
	for e in roster:
		if e != null and role_override.has(String(e["uid"])):
			roles[int(e["slot"])] = int(role_override[String(e["uid"])])
	var n := 0
	for s2 in roles:
		if roles[s2] == TC.Role.PATROL:
			n += 1
	for e in roster:
		if e == null or not bool(e["is_bot"]) or n == watch:
			continue
		var sl := int(e["slot"])
		if n > watch and roles[sl] == TC.Role.PATROL:
			roles[sl] = TC.Role.RUNNER
			n -= 1
		elif n < watch and roles[sl] == TC.Role.RUNNER:
			roles[sl] = TC.Role.PATROL
			n += 1
	return roles


## Practice: the player's chosen role (Random is a coin flip); bots fill
## the other Night Watch seats.
func _practice_roles(seed_v: int, watch: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v ^ 0x51ce
	var mine := practice_role
	if mine == "random":
		mine = "patrol" if rng.randf() < 0.5 else "runner"
	var roles := {}
	var others: Array = []
	for e in roster:
		if e == null:
			continue
		if int(e["slot"]) == local_slot:
			roles[int(e["slot"])] = TC.Role.PATROL if mine == "patrol" else TC.Role.RUNNER
		else:
			roles[int(e["slot"])] = TC.Role.RUNNER
			others.append({"slot": int(e["slot"]), "r": rng.randf()})
	others.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["r"] < b["r"])
	var need := watch - (1 if mine == "patrol" else 0)
	for i in mini(need, others.size()):
		roles[int(others[i]["slot"])] = TC.Role.PATROL
	return roles


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


## Client: our match scene is ready (load acknowledgement for this round).
func send_loaded() -> void:
	if mode == Mode.CLIENT and host_peer >= 0:
		var b := Protocol.buf_for(Protocol.M.LOADED)
		b.put_u16(round_no)
		transport.send(host_peer, b.data_array, true)


## Host: the round starts once every connected player has loaded (or after
## LOAD_TIMEOUT_S, so one slow device can't hold everyone).  Bots and
## disconnected players don't count.
func loads_complete(delta: float = 0.0) -> bool:
	if mode != Mode.HOST or _loads_done or current_start.is_empty() or phase == TC.Phase.LOBBY or phase == TC.Phase.RESULTS:
		return true
	_load_wait += delta
	if _load_wait >= LOAD_TIMEOUT_S:
		_loads_done = true
		return true
	for e in roster:
		if e != null and not bool(e["is_bot"]) and bool(e["connected"]) and int(e["slot"]) != local_slot and not _loaded.has(int(e["slot"])):
			return false
	_loads_done = true   # once everyone is in, later reconnects never pause the round
	return true


## Slots still loading (HUD: "Waiting for …").
func loading_names() -> Array:
	var out: Array = []
	if mode != Mode.HOST:
		return out
	for e in roster:
		if e != null and not bool(e["is_bot"]) and bool(e["connected"]) and int(e["slot"]) != local_slot and not _loaded.has(int(e["slot"])):
			out.append(String(e["name"]))
	return out if not _loads_done else []


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
	if series != null:
		series.record_round(results)   # idempotent by match id; cancelled rounds don't count
		series_view = series.to_dict()
	var start_series: Dictionary = current_start.get("series", {})
	results["series"] = series_view if series != null else {}
	results["round_index"] = int(start_series.get("round", 1))
	results["rounds_total"] = int(start_series.get("total", 1))
	# readiness for the next round starts over (nobody is rushed off results)
	for e in roster:
		if e != null and not bool(e["is_bot"]) and int(e["slot"]) != local_slot:
			e["ready"] = false
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
		if not (series != null and series.in_progress()):
			e["ready"] = false   # between rounds, readiness given on the results screen stands
		e["role"] = -1
	if series != null and series.finished:
		series = null   # Play again: a new series starts with the next Start
		series_view = {}
	_broadcast_lobby()
	series_changed.emit()


## Host: change the party settings (pre-series lobby only).  A real change
## clears everyone's ready and tells the guests.  Returns true if applied.
func host_set_settings(watch: int, rounds: int) -> bool:
	if not is_host() or mode == Mode.OFFLINE or phase != TC.Phase.LOBBY:
		return false
	if series != null and series.in_progress():
		return false   # locked mid-series; End series first
	var s := PartySeries.sanitize_settings({"watch": watch, "rounds": rounds, "rev": int(settings["rev"]) + 1})
	if s.is_empty() or (int(s["watch"]) == int(settings["watch"]) and int(s["rounds"]) == int(settings["rounds"])):
		return false
	settings = s
	for e in roster:
		if e != null and not bool(e["is_bot"]) and int(e["slot"]) != local_slot:
			e["ready"] = false
	_broadcast_lobby()
	return true


## Host: end the series now (between rounds).  Completed rounds stand.
func host_end_series() -> void:
	if not is_host() or series == null or not series.in_progress():
		return
	series.end_early()
	series_view = series.to_dict()
	_send_series_all()
	series_changed.emit()


func _series_bytes() -> PackedByteArray:
	var b := Protocol.buf_for(Protocol.M.SERIES)
	var u := JSON.stringify(_jsonable(series_view)).to_utf8_buffer()
	b.put_u32(u.size())
	b.put_data(u)
	return b.data_array


func _send_series_all() -> void:
	if mode == Mode.HOST and transport != null:
		transport.broadcast(_series_bytes(), true)


## Is a series under way (between rounds included)?  Everyone can ask.
func series_active() -> bool:
	if is_host():
		return series != null and series.in_progress()
	return int(series_brief.get("state", 0)) == 1


## 1-based round number about to be played next.
func next_round_number() -> int:
	if is_host():
		return series.next_round() if series != null and series.in_progress() else 1
	return int(series_brief.get("next_round", 1)) if series_active() else 1


func rounds_total() -> int:
	if is_host():
		return series.rounds_total() if series != null else int(settings["rounds"])
	return int(series_brief.get("total", settings["rounds"]))


## Host: this device's own match scene is ready (counts toward the loading
## screen's "ready" tally).
func mark_local_loaded() -> void:
	if is_host() and local_slot >= 0 and not _loaded.has(local_slot):
		_loaded[local_slot] = true
		_broadcast_lobby()


## Loading progress for the loading screen: [ready, total] connected humans.
func load_progress() -> Array:
	var ready := 0
	var total := 0
	for e in roster:
		if e == null or bool(e["is_bot"]) or not bool(e["connected"]):
			continue
		total += 1
		var slot := int(e["slot"])
		if is_host():
			if _loaded.has(slot):
				ready += 1
		elif bool(e.get("loaded", false)):
			ready += 1
	return [ready, total]


# ---------------------------------------------------------------------------
# Client side
# ---------------------------------------------------------------------------
func _client_packet(peer: int, type: int, b: StreamPeerBuffer) -> void:
	match type:
		Protocol.M.ANNOUNCE:
			if host_peer >= 0:
				return   # bound already: an announcement can never replace the host
			var is_h := b.get_u8() == 1
			var _uid := Protocol.get_str(b)
			var code := Protocol.get_str(b, 12)
			if not is_h:
				return
			if expected_host_uid != "" and transport.peer_uid(peer) != expected_host_uid:
				return   # not the Game Center player the service named as host
			if room_code == "" or code == room_code or transport.kind != "gamekit":
				host_peer = peer
				room_code = code
				if hold_hello and admission == "":
					admission_needed.emit(code)
				else:
					_send_hello()
		Protocol.M.WELCOME:
			local_slot = clampi(b.get_8(), -1, 7)
			var reason := Protocol.get_str(b)
			var key := Protocol.get_str(b, 32)
			if key != "":
				rejoin_key = key
				Save.remember_rejoin(room_code, key)
			connected = true
			if reason in ["version", "admission", "not_allowed", "in_use"]:
				_end(reason)
				return
			if local_slot < 0 and reason == "full":
				status_changed.emit("Room is full — watching until a slot opens.")
			lobby_changed.emit()
		Protocol.M.LOBBY:
			_read_lobby(b)
		Protocol.M.START:
			var parsed := Protocol.get_json(b)
			var fixed := _fix_start(parsed) if not parsed.is_empty() else {}
			if not fixed.is_empty():
				current_start = fixed
				round_no = int(fixed.get("round", round_no))
				settings = fixed["settings"]
				round_cfg = PartySeries.rules_for(Rules.cfg, int(settings["watch"]))
				phase = TC.Phase.LOADING
				_last_event_id = 0
				match_starting.emit(current_start)
		Protocol.M.SNAP:
			var snap := Protocol.decode_snapshot(b)
			if not snap.is_empty():
				snapshot_received.emit(snap)
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
			var parsed2 := Protocol.get_json(b)
			if not parsed2.is_empty():
				var fr := _fix_results(parsed2)
				if not fr.is_empty():
					var sv2 := PartySeries.sanitize_view(parsed2.get("series", {}))
					fr["series"] = sv2
					fr["round_index"] = clampi(int(parsed2.get("round_index", 1)), 1, 5)
					fr["rounds_total"] = clampi(int(parsed2.get("rounds_total", 1)), 1, 5)
					if not sv2.is_empty():
						series_view = sv2
						series_changed.emit()
					last_results = fr
					phase = TC.Phase.RESULTS
					results_received.emit(last_results)
		Protocol.M.PING:
			if b.get_available_bytes() < 8:
				return
			var t := b.get_double()
			var rb := Protocol.buf_for(Protocol.M.PONG)
			rb.put_double(t)
			transport.send(peer, rb.data_array, false)
		Protocol.M.PONG:
			if b.get_available_bytes() < 8:
				return
			var sent := b.get_double()
			var d := Time.get_ticks_usec() / 1000000.0 - sent
			if is_finite(d) and d >= 0.0 and d < 10.0:
				rtt = lerpf(rtt, d, 0.3)
		Protocol.M.SERIES:
			var sv := PartySeries.sanitize_view(Protocol.get_json(b))
			if not sv.is_empty():
				series_view = sv
				series_changed.emit()
		Protocol.M.HOST_END:
			_end("host_ended")
		Protocol.M.KICK:
			_end("kicked")


## Invites: the service vouched for us for the announced room.  The host it
## names must be the peer we bound to.
func provide_admission(token: String, host_uid: String) -> void:
	if host_peer >= 0 and host_uid != "" and transport.peer_uid(host_peer) != host_uid:
		_end("admission")
		return
	admission = token
	expected_host_uid = host_uid
	_send_hello()


func _send_hello() -> void:
	var b := Protocol.buf_for(Protocol.M.HELLO)
	b.put_u16(Protocol.VERSION)
	Protocol.put_str(b, local_uid)
	Protocol.put_str(b, local_name)
	Protocol.put_appearance(b, local_cosmetic)
	b.put_u8(["any", "runner", "patrol"].find(local_pref))
	Protocol.put_str(b, rejoin_key, 32)
	Protocol.put_long_str(b, admission)
	transport.send(host_peer, b.data_array, true)
	_hello_sent = true


func _read_lobby(b: StreamPeerBuffer) -> void:
	room_code = Protocol.get_str(b)
	var ph := b.get_u8()
	round_no = b.get_u16()
	var nspec := b.get_u8()
	var s_in := PartySeries.sanitize_settings({"watch": b.get_u8(), "rounds": b.get_u8(), "rev": b.get_u16()})
	var sstate := b.get_u8()
	var nxt := b.get_u8()
	var tot := b.get_u8()
	if not s_in.is_empty():
		if int(s_in["rev"]) != int(settings["rev"]) and has_meta("lobby_seen") and ph == TC.Phase.LOBBY:
			settings_note = "The host changed the party settings: %s. Tap Ready again when you're set." % PartySeries.summary(s_in)
		settings = s_in
	series_brief = {"state": sstate, "next_round": clampi(nxt, 1, 5), "total": clampi(tot, 1, 5)}
	for i in 8:
		if b.get_u8() == 0:
			roster[i] = null
			continue
		var uid := Protocol.get_str(b)
		var name := Protocol.get_str(b)
		var flags := b.get_u8()
		var pref: String = ["any", "runner", "patrol"][clampi(b.get_u8(), 0, 2)]
		var role := clampi(b.get_8(), -1, 1)
		var e := _entry(i, uid, NameRules.safe_display(name), (flags & 1) != 0, -1, Protocol.get_appearance(b), pref)
		e["pid"] = Protocol.get_str(b, 40)
		e["ready"] = (flags & 2) != 0
		e["connected"] = (flags & 4) != 0
		e["is_host"] = (flags & 8) != 0
		e["loaded"] = (flags & 16) != 0
		e["role"] = role
		roster[i] = e
	if ph == TC.Phase.LOBBY and phase == TC.Phase.RESULTS:
		phase = TC.Phase.LOBBY
	elif ph == TC.Phase.LOBBY:
		phase = TC.Phase.LOBBY
	set_meta("spectators", nspec)
	set_meta("lobby_seen", true)
	lobby_changed.emit()


## START from the host, checked field by field: {} if anything is off.
func _fix_start(d: Dictionary) -> Dictionary:
	if not (d.get("targets") is Array) or not (d.get("roster") is Array) or not (d.get("seed") is float or d.get("seed") is int):
		return {}
	var out := d.duplicate(true)
	out["seed"] = int(d["seed"])
	out["match_id"] = String(d.get("match_id", "")).substr(0, 64)
	out["round"] = int(d.get("round", 0))
	var st := PartySeries.sanitize_settings(d.get("settings", {}))
	if st.is_empty():
		return {}
	out["settings"] = st
	var se: Variant = d.get("series", {})
	var sd: Dictionary = se if se is Dictionary else {}
	out["series"] = {"id": String(sd.get("id", "")).substr(0, 16), "round": clampi(int(sd.get("round", 1)), 1, 5),
		"total": clampi(int(sd.get("total", 1)), 1, 5)}
	var t: Array = []
	for x in d["targets"]:
		if not (x is float or x is int) or int(x) < 0 or int(x) > 5 or t.has(int(x)):
			return {}
		t.append(int(x))
	if t.size() != 3:
		return {}
	out["targets"] = t
	var ro: Array = []
	var slots := {}
	var roster_in: Array = d["roster"]
	if roster_in.size() < 1 or roster_in.size() > 8:
		return {}
	for e in roster_in:
		if not (e is Dictionary):
			return {}
		var slot := int(e.get("slot", -1))
		var role := int(e.get("role", -1))
		if slot < 0 or slot > 7 or slots.has(slot) or not role in [TC.Role.RUNNER, TC.Role.PATROL]:
			return {}
		slots[slot] = true
		var c: Variant = e.get("cosmetic", {})
		ro.append({"slot": slot, "uid": String(e.get("uid", "")).substr(0, 64), "name": NameRules.safe_display(String(e.get("name", ""))),
			"is_bot": bool(e.get("is_bot", false)), "role": role, "cosmetic": Cosmetics.sanitize(c if c is Dictionary else {})})
	out["roster"] = ro
	return out


func _fix_results(d: Dictionary) -> Dictionary:
	if not (d.get("outcome") is float or d.get("outcome") is int) or not (d.get("players", []) is Array):
		return {}
	var out := d.duplicate(true)
	out["outcome"] = clampi(int(d["outcome"]), 0, TC.Outcome.CANCELLED)
	out["fastest_slot"] = int(d.get("fastest_slot", -1))
	out["needed"] = clampi(int(d.get("needed", 4)), 1, 7)
	out["watch"] = clampi(int(d.get("watch", 2)), 1, 3)
	# the away/eligibility share on guests is measured against it
	out["round_time"] = clampf(float(d.get("round_time", 0.0)), 0.0, 3600.0)
	var rows: Array = []
	for r in d.get("players", []):
		if not (r is Dictionary) or rows.size() >= 8:
			continue
		var rr: Dictionary = r.duplicate()
		if rr.has("name"):
			rr["name"] = NameRules.safe_display(String(rr["name"]))
		for k in ["slot", "role", "stamps", "finish_order", "times_captured", "captures", "unique_captures"]:
			rr[k] = int(r.get(k, 0))
		rr["away_s"] = float(r.get("away_s", 0.0))
		rr["present"] = bool(r.get("present", true))
		rr["was_human"] = bool(r.get("was_human", false))
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
	_clock += delta
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
		if host_peer >= 0 and not _hello_sent and not (hold_hello and admission == ""):
			_send_hello()
		if host_peer >= 0:
			_ping_t += delta
			if _ping_t > 1.0:
				_ping_t = 0.0
				var pb := Protocol.buf_for(Protocol.M.PING)
				pb.put_double(Time.get_ticks_usec() / 1000000.0)
				transport.send(host_peer, pb.data_array, false)
