class_name HubSync
extends RefCounted
## Walk around in the party room (V6): where each party member is standing.
##
## Each device moves its own runner (HubWalk) and sends its pose at 10 Hz
## while walking (unreliable; a switch between walking and standing on the
## mark is sent reliably).  The host is the referee: it accepts a pose only
## from a seated human, in the party room, newer than the last one, and it
## clamps it to the walkable floor (HubRoom) and to a plausible distance
## for the time since that player's previous pose, so nobody can teleport,
## stand inside furniture or leave the room.  The host sends every walker's
## pose to everyone at 10 Hz while anyone walks; receivers keep a short
## buffer per player and draw them 150 ms in the past, interpolated.  Poses
## exist only for the current roster (no avatars for people who aren't in
## the party) and are dropped when a round starts.
##
## (build 20) Things to do in the room (HubRoom props): bouncing on the
## couch and hiding in the plant are pose modes, so everyone sees them.  The
## host gives each to one person at a time, only within reach, and tells a
## device that asked too late (HUB_DENY); it walks on.  The floor lamp is
## one switch for the whole party: a guest asks the host (HUB_ACT), the host
## flips it and every HUB_STATE carries it.  While anyone is on the couch,
## in the plant or the lamp is off, the host repeats the state once a
## second, so someone joining sees the room as it is.

signal changed
## (build 20) the host said no: someone else got there first
signal denied(mode: int, taken: bool)
## (build 20) the floor lamp went off or on
signal lamp_changed(on: bool)

const SEND_S := 0.1
const INTERP_S := 0.15
const MODE_MARK := 0
const MODE_WALK := 1
## (build 20) bouncing on the couch / hiding in the plant
const MODE_COUCH := 2
const MODE_PLANT := 3
const ACT_LAMP := 0
## the lamp switch can't be flicked faster than this (seconds)
const LAMP_COOLDOWN := 0.35
## with anything going on in the room, the state goes out at least this often
const IDLE_BCAST_S := 1.0
const KEEP := 6

var session: NetSession
## session time in seconds, advanced by tick() (physics frames), so poses
## are timed by the same clock that sends them
var clock := 0.0
var now_fn: Callable = func() -> float: return clock

## local
var local_mode := MODE_MARK
var local_pos := Vector2.ZERO
var local_yaw := 0.0
var local_speed := 0.0
var _seq := 0
var _send_t := 0.0
var _mode_sent := MODE_MARK
## host: slot -> {mode, pos, yaw, speed, seq, at}
var poses: Dictionary = {}
var _bcast_t := 0.0
var _active_until := 0.0
## everyone: slot -> [{at, mode, pos, yaw, speed}] (receive time order)
var samples: Dictionary = {}
var _last_seq: Dictionary = {}
## poses rejected or clamped by the host (tests / diagnostics)
var stat_clamped := 0
var stat_dropped := 0
## (build 20) the floor lamp (everyone; the host's word)
var lamp_on := true
var _lamp_t := -10.0
var _idle_t := 0.0


## The room prop a pose mode uses (MODE_COUCH -> "couch"), or "".
static func prop_of(mode: int) -> String:
	match mode:
		MODE_COUCH:
			return HubRoom.PROP_COUCH
		MODE_PLANT:
			return HubRoom.PROP_PLANT
	return ""


static func is_act(mode: int) -> bool:
	return mode == MODE_COUCH or mode == MODE_PLANT


func _init(s: NetSession) -> void:
	session = s


func in_room() -> bool:
	return session.phase == TC.Phase.LOBBY and session.mode != NetSession.Mode.OFFLINE


## The local runner's pose this frame (HubWalk).  mode MARK = back on its
## mark in the menu composition.
func set_local(mode: int, pos: Vector2, yaw: float, speed: float) -> void:
	var changed_mode := mode != local_mode
	local_mode = mode
	local_pos = HubRoom.resolve(pos)
	local_yaw = yaw
	local_speed = clampf(speed, 0.0, HubRoom.WALK_SPEED * 1.5)
	if session.is_host():
		if session.local_slot >= 0:
			_host_store(session.local_slot, local_mode, local_pos, local_yaw, local_speed)
		return
	if changed_mode:
		_send_pose(true)


func _send_pose(reliable: bool) -> void:
	if session.host_peer < 0 or not in_room():
		return
	_seq = (_seq + 1) & 0xFFFF
	var b := Protocol.buf_for(SocialProto.HUB_POSE)
	_put_pose(b, _seq, local_mode, local_pos, local_yaw, local_speed)
	session.transport.send(session.host_peer, b.data_array, reliable)
	_mode_sent = local_mode


static func _put_pose(b: StreamPeerBuffer, seq: int, mode: int, pos: Vector2, yaw: float, speed: float) -> void:
	b.put_u16(seq)
	b.put_u8(mode)
	b.put_16(clampi(int(round(pos.x * SocialProto.POS_SCALE)), -32767, 32767))
	b.put_16(clampi(int(round(pos.y * SocialProto.POS_SCALE)), -32767, 32767))
	b.put_u16(int(fposmod(yaw, TAU) / TAU * 65535.0) & 0xFFFF)
	b.put_u8(clampi(int(speed / 4.0 * 255.0), 0, 255))


static func _get_pose(b: StreamPeerBuffer) -> Dictionary:
	if b.get_available_bytes() < 10:
		return {}
	var seq := b.get_u16()
	var mode := b.get_u8()
	var x := float(b.get_16()) / SocialProto.POS_SCALE
	var z := float(b.get_16()) / SocialProto.POS_SCALE
	var yaw := float(b.get_u16()) / 65535.0 * TAU
	var speed := float(b.get_u8()) / 255.0 * 4.0
	if mode > MODE_PLANT or not is_finite(x) or not is_finite(z):
		return {}
	return {"seq": seq, "mode": mode, "pos": Vector2(x, z), "yaw": yaw, "speed": speed}


static func _newer(seq: int, last: int) -> bool:
	if last < 0:
		return true
	var d := (seq - last) & 0xFFFF
	return d > 0 and d < 32768


# ---------------------------------------------------------------------------
# Host
# ---------------------------------------------------------------------------
func host_packet(peer: int, b: StreamPeerBuffer) -> void:
	var slot := int(session._peer_slot.get(peer, -1))
	if slot < 0 or not in_room() or session.roster[slot] == null or bool(session.roster[slot]["is_bot"]):
		stat_dropped += 1
		return
	var p := _get_pose(b)
	if p.is_empty() or not _newer(int(p["seq"]), int(_last_seq.get(slot, -1))):
		stat_dropped += 1
		return
	_last_seq[slot] = int(p["seq"])
	_host_store(slot, int(p["mode"]), p["pos"], float(p["yaw"]), float(p["speed"]))


func _host_store(slot: int, mode: int, pos: Vector2, yaw: float, speed: float) -> void:
	var now: float = now_fn.call()
	var prev: Dictionary = poses.get(slot, {})
	var q := HubRoom.resolve(pos)
	if not prev.is_empty() and is_act(int(prev["mode"])) and int(prev["mode"]) == mode:
		q = prev["pos"]   # (build 20) on the couch / in the plant: nobody slides around
	elif not prev.is_empty() and int(prev["mode"]) != MODE_MARK and mode != MODE_MARK:
		# no teleporting: at most a little more than walking speed allows
		var from: Vector2 = prev["pos"]
		var dt := clampf(now - float(prev["at"]), 0.05, 1.0)
		var max_d := HubRoom.WALK_SPEED * 1.6 * dt + 0.25
		if from.distance_to(q) > max_d:
			q = HubRoom.step(from, (q - from).normalized() * max_d)
			stat_clamped += 1
	elif q.distance_to(pos) > 0.01:
		stat_clamped += 1   # inside furniture or off the floor
	if is_act(mode) and (prev.is_empty() or int(prev["mode"]) != mode):
		# (build 20) the couch / the plant: one person at a time, from
		# walking (not straight off the mark), within reach of where the host
		# has them (after the teleport clamp)
		var prop := prop_of(mode)
		var near := not prev.is_empty() and int(prev["mode"]) != MODE_MARK \
			and HubRoom.prop_dist(prop, q) <= HubRoom.REACH + HubRoom.REACH_SLACK
		var taken := occupant_host(mode, slot) >= 0
		if not near or taken:
			mode = MODE_WALK
			_deny(slot, prop_mode(prop), taken)
	var mode_changed := prev.is_empty() or int(prev["mode"]) != mode
	poses[slot] = {"mode": mode, "pos": q, "yaw": yaw, "speed": clampf(speed, 0.0, HubRoom.WALK_SPEED * 1.5), "seq": int(prev.get("seq", 0)) + 1, "at": now}
	if mode != MODE_MARK or mode_changed:
		_active_until = now + 1.5
	if slot != session.local_slot:
		_store_sample(slot, mode, q, yaw, float(poses[slot]["speed"]))
	if mode_changed:
		changed.emit()


static func prop_mode(prop: String) -> int:
	return MODE_COUCH if prop == HubRoom.PROP_COUCH else (MODE_PLANT if prop == HubRoom.PROP_PLANT else MODE_WALK)


## Host: who is using the prop of `mode` (a slot other than `but`), or -1.
func occupant_host(mode: int, but: int = -1) -> int:
	for s in poses:
		if int(s) != but and int(poses[s]["mode"]) == mode and session.roster[int(s)] != null:
			return int(s)
	return -1


## Anyone: who else is on the couch / in the plant (-1: free).  The host
## knows; a guest goes by the poses it has heard.
func occupant(mode: int) -> int:
	if session.is_host():
		return occupant_host(mode, session.local_slot)
	for i in 8:
		if i != session.local_slot and session.roster[i] != null and mode_of(i) == mode:
			return i
	return -1


func _deny(slot: int, mode: int, taken: bool) -> void:
	stat_dropped += 1
	if slot == session.local_slot:
		local_mode = MODE_WALK
		denied.emit(mode, taken)
		return
	var peer := -1
	for pr in session._peer_slot:
		if int(session._peer_slot[pr]) == slot:
			peer = int(pr)
	if peer < 0:
		return
	var b := Protocol.buf_for(SocialProto.HUB_DENY)
	b.put_u8(mode)
	b.put_u8(1 if taken else 0)
	session.transport.send(peer, b.data_array, true)


## Flick the floor lamp's switch (the local player is by it).
func request_lamp() -> void:
	if not in_room():
		return
	if session.is_host():
		_host_lamp(session.local_slot)
		return
	if session.host_peer < 0:
		return
	var b := Protocol.buf_for(SocialProto.HUB_ACT)
	b.put_u8(ACT_LAMP)
	session.transport.send(session.host_peer, b.data_array, true)


func host_act(peer: int, b: StreamPeerBuffer) -> void:
	var slot := int(session._peer_slot.get(peer, -1))
	if slot < 0 or not in_room() or session.roster[slot] == null or bool(session.roster[slot]["is_bot"]) or b.get_available_bytes() < 1:
		stat_dropped += 1
		return
	if b.get_u8() == ACT_LAMP:
		_host_lamp(slot)


func _host_lamp(slot: int) -> void:
	var now: float = now_fn.call()
	var p: Dictionary = poses.get(slot, {})
	# only someone walking around and standing by the lamp, and not
	# flicker-fast
	if p.is_empty() or int(p["mode"]) != MODE_WALK or now - _lamp_t < LAMP_COOLDOWN \
			or HubRoom.prop_dist(HubRoom.PROP_LAMP, p["pos"]) > HubRoom.REACH + HubRoom.REACH_SLACK:
		stat_dropped += 1
		return
	_lamp_t = now
	lamp_on = not lamp_on
	_active_until = now + 1.5
	_bcast_t = SEND_S   # out on the next tick
	lamp_changed.emit(lamp_on)


func client_deny(b: StreamPeerBuffer) -> void:
	if b.get_available_bytes() < 2:
		return
	var mode := b.get_u8()
	var taken := b.get_u8() == 1
	if is_act(mode) and local_mode == mode:
		local_mode = MODE_WALK
		_mode_sent = MODE_WALK   # the host already has us walking
		denied.emit(mode, taken)


func _broadcast() -> void:
	var b := Protocol.buf_for(SocialProto.HUB_STATE)
	b.put_u8(0 if lamp_on else 1)
	var slots: Array = []
	for s in poses:
		if session.roster[int(s)] != null and not bool(session.roster[int(s)]["is_bot"]):
			slots.append(int(s))
	b.put_u8(slots.size())
	for s in slots:
		var p: Dictionary = poses[s]
		b.put_u8(s)
		_put_pose(b, int(p["seq"]) & 0xFFFF, int(p["mode"]), p["pos"], float(p["yaw"]), float(p["speed"]))
	session.transport.broadcast(b.data_array, false)


# ---------------------------------------------------------------------------
# Client
# ---------------------------------------------------------------------------
func client_packet(b: StreamPeerBuffer) -> void:
	if not in_room() or b.get_available_bytes() < 2:
		return
	var on := (b.get_u8() & 1) == 0
	if on != lamp_on:
		lamp_on = on
		lamp_changed.emit(on)
	var n := b.get_u8()
	if n > 8:
		return
	for i in n:
		if b.get_available_bytes() < 11:
			return
		var slot := b.get_u8()
		var p := _get_pose(b)
		if p.is_empty() or slot > 7 or slot == session.local_slot:
			continue
		if session.roster[slot] == null or bool(session.roster[slot]["is_bot"]):
			continue   # no avatar for anyone who isn't in the party
		if not _newer(int(p["seq"]), int(_last_seq.get(slot, -1))):
			continue
		_last_seq[slot] = int(p["seq"])
		var mode_before := mode_of(slot)
		_store_sample(slot, int(p["mode"]), HubRoom.resolve(p["pos"]), float(p["yaw"]), float(p["speed"]))
		if mode_of(slot) != mode_before:
			changed.emit()


func _store_sample(slot: int, mode: int, pos: Vector2, yaw: float, speed: float) -> void:
	var arr: Array = samples.get(slot, [])
	arr.append({"at": now_fn.call(), "mode": mode, "pos": pos, "yaw": yaw, "speed": speed})
	while arr.size() > KEEP:
		arr.pop_front()
	samples[slot] = arr


## Is this party member walking (else on their mark)?
func mode_of(slot: int) -> int:
	var arr: Array = samples.get(slot, [])
	return int(arr[-1]["mode"]) if not arr.is_empty() else MODE_MARK


## Interpolated pose of a party member, INTERP_S in the past:
## {mode, pos, yaw, speed} or {} when we have nothing for them.
func sample(slot: int) -> Dictionary:
	var arr: Array = samples.get(slot, [])
	if arr.is_empty():
		return {}
	if arr.size() == 1:
		return arr[0]
	var t: float = now_fn.call() - INTERP_S
	if t <= float(arr[0]["at"]):
		return arr[0]
	if t >= float(arr[-1]["at"]):
		return arr[-1]
	for i in range(arr.size() - 1):
		var a: Dictionary = arr[i]
		var c: Dictionary = arr[i + 1]
		if t >= float(a["at"]) and t <= float(c["at"]):
			var u := (t - float(a["at"])) / maxf(0.001, float(c["at"]) - float(a["at"]))
			if (a["pos"] as Vector2).distance_to(c["pos"]) > 3.0:
				u = 1.0   # a jump (back to the mark, a correction): no slide across the room
			return {"mode": int(c["mode"]), "pos": (a["pos"] as Vector2).lerp(c["pos"], u),
				"yaw": lerp_angle(float(a["yaw"]), float(c["yaw"]), u), "speed": lerpf(float(a["speed"]), float(c["speed"]), u)}
	return arr[-1]


# ---------------------------------------------------------------------------
func tick(delta: float) -> void:
	clock += delta
	if not in_room():
		if not poses.is_empty() or not samples.is_empty() or not lamp_on:
			clear()
		return
	var now: float = now_fn.call()
	if session.is_host():
		# a seat that emptied has no pose
		for s in poses.keys():
			if session.roster[int(s)] == null:
				poses.erase(s)
				samples.erase(s)
		_bcast_t += delta
		_idle_t += delta
		if _bcast_t >= SEND_S and now <= _active_until:
			_bcast_t = 0.0
			_idle_t = 0.0
			_broadcast()
		elif _idle_t >= IDLE_BCAST_S and (not lamp_on or occupant_host(MODE_COUCH) >= 0 or occupant_host(MODE_PLANT) >= 0):
			# (build 20) the room as it is, for anyone who just came in
			_idle_t = 0.0
			_broadcast()
	else:
		for s in samples.keys():
			if session.roster[int(s)] == null:
				samples.erase(s)
		_send_t += delta
		if local_mode == MODE_WALK and _send_t >= SEND_S:
			_send_t = 0.0
			_send_pose(false)
		elif local_mode != _mode_sent:
			_send_pose(true)


## A round started (or the party room went away): everyone is back to the
## menu composition, nothing more is sent.
func clear() -> void:
	poses.clear()
	samples.clear()
	_last_seq.clear()
	local_mode = MODE_MARK
	_mode_sent = MODE_MARK
	_active_until = 0.0
	if not lamp_on:
		lamp_on = true
		lamp_changed.emit(true)
	changed.emit()
