class_name BallSync
extends RefCounted
## (build 24) The party room's basketball, for everyone in the party.
##
## The host is the referee, as for walking around (HubSync): it starts the
## ball on a random free spot of the floor when the party room opens (each
## time you log in it is somewhere else), runs its physics (HubBall) and
## decides who has it.  Anyone walking around can pick it up when they are
## close (BALL_REQ); the holder dribbles as they walk and can shoot at the
## hoop, drop it, or pass it to someone else walking around in the party
## (only with other people in the party).  Whether a shot goes in is part
## luck and part distance: the host picks a clean shot or a near miss and
## the physics plays it out (a miss can still rattle in).  A made shot
## rains confetti on every device.
##
## The host sends the ball's state (BALL_STATE) whenever it changes hands
## or is thrown (reliably) and 15 times a second while it moves or is held,
## once a second while it rests (for anyone joining).  Guests run the same
## physics from each state, so it flies and bounces smoothly between
## corrections.  The holder drops it when they stop walking (back to their
## mark, onto the couch, into the plant) or leave; a round starting puts it
## away, and the next party room starts it somewhere new.
##
##   68 BALL_REQ    client -> host  (reliable)  u8 act, i8 arg (pass: target slot)
##   69 BALL_STATE  host -> clients            u16 seq, u8 phase, i8 holder, i8 pass_to,
##                                             i8 shooter, u8 make_seq, u8 flags,
##                                             i16 x3 pos (1/1024 m), i16 x3 vel (1/512 m/s)

signal made(slot: int, swish: bool)
signal sound(kind: int, at: Vector3, strength: float)
## who has it changed (pick up, catch, release)
signal changed
## something to tell the local player
signal notice(text: String)

const ACT_PICKUP := 1
const ACT_DROP := 2
const ACT_SHOOT := 3
const ACT_PASS := 4
enum Phase { FREE, HELD, SHOT, PASS }
const WINDUP_SHOT := 0.3
const WINDUP_PASS := 0.16
const SEND_S := 1.0 / 15.0
const REST_SEND_S := 1.0
const REACH_SLACK := 0.35
const REQ_COOL := 0.12
## the shooter's body doesn't knock their own shot away
const GHOST_S := 0.35
## a pass nobody caught is just a loose ball after this long
const PASS_S := 2.0
const CATCH_R := 0.42
const POS_Q := 1024.0
const VEL_Q := 512.0
## a shot's chance by distance to the rim: close in .. from far away
const P_CLOSE := 0.88
const P_FAR := 0.2

var session: NetSession
var sim := HubBall.new()
var phase := Phase.FREE
var holder := -1
var pass_to := -1
var make_seq := 0
var last_swish := false
## seconds since the phase last changed (this device's clock: the windup)
var phase_t := 0.0
## a guest's correction: where the ball was drawn minus where the host says
## it is; the view adds it and lets it fade, so a correction never jumps
var err := Vector3.ZERO
var spawned := false
var stat_denied := 0
var _seq := 0
var _last_seq := -1
var _send_t := 0.0
var _rest_t := 0.0
var _dirty := false
var _wind := 0.0
var _pass_t := 0.0
var _ghost_t := 0.0
var _req_t: Dictionary = {}
var _clock := 0.0
var _make_known := false
var rng := RandomNumberGenerator.new()
## (tests, captures) -1: the shot's luck decides; 0: a miss; 1: a make
var force_make := -1


func _init(s: NetSession) -> void:
	session = s
	rng.randomize()
	sim.rng.seed = rng.randi()


func in_room() -> bool:
	return session.phase == TC.Phase.LOBBY and session.mode != NetSession.Mode.OFFLINE


func hub() -> HubSync:
	return session.social.hub


## Does the local player have the ball (dribbling or winding up)?
func local_has() -> bool:
	return holder >= 0 and holder == session.local_slot


## Someone else from the party is walking around (somebody to pass to).
func others_walking() -> bool:
	for i in 8:
		if i == session.local_slot or session.roster[i] == null or bool(session.roster[i]["is_bot"]):
			continue
		if _mode(i) == HubSync.MODE_WALK:
			return true
	return false


## Other people in the party (passing is only for a party).
func party_has_others() -> bool:
	return session.human_count() > 1


## The ball is loose and close enough to the local runner (walking at
## `at`) to pick up.
func can_pickup(at: Vector2) -> bool:
	if phase != Phase.FREE or not in_room() or not spawned:
		return false
	var b := sim.pos + err
	return b.y <= HubBall.REACH_Y and Vector2(b.x, b.z).distance_to(at) <= HubBall.REACH


func request(act: int, arg: int = -1) -> void:
	if not in_room():
		return
	if session.is_host():
		_host_req(session.local_slot, act, arg)
		return
	if session.host_peer < 0:
		return
	var b := Protocol.buf_for(SocialProto.BALL_REQ)
	b.put_u8(act)
	b.put_8(clampi(arg, -1, 7))
	session.transport.send(session.host_peer, b.data_array, true)


# ---------------------------------------------------------------------------
# Host
# ---------------------------------------------------------------------------
func host_packet(peer: int, b: StreamPeerBuffer) -> void:
	var slot := int(session._peer_slot.get(peer, -1))
	if slot < 0 or b.get_available_bytes() < 2:
		stat_denied += 1
		return
	var act := b.get_u8()
	var arg := b.get_8()
	_host_req(slot, act, arg)


func _pose(slot: int) -> Dictionary:
	return hub().poses.get(slot, {})


func _mode(slot: int) -> int:
	if session.is_host():
		var p := _pose(slot)
		return int(p["mode"]) if not p.is_empty() else HubSync.MODE_MARK
	if slot == session.local_slot:
		return hub().local_mode
	return hub().mode_of(slot)


func _human(slot: int) -> bool:
	return slot >= 0 and slot < 8 and session.roster[slot] != null and not bool(session.roster[slot]["is_bot"])


func _host_req(slot: int, act: int, arg: int) -> void:
	if not in_room() or not _human(slot) or not spawned:
		stat_denied += 1
		return
	if _clock - float(_req_t.get(slot, -10.0)) < REQ_COOL:
		stat_denied += 1
		return
	_req_t[slot] = _clock
	var p := _pose(slot)
	if p.is_empty() or int(p["mode"]) != HubSync.MODE_WALK:
		stat_denied += 1
		return
	var at: Vector2 = p["pos"]
	match act:
		ACT_PICKUP:
			var bp := sim.pos
			if phase != Phase.FREE or bp.y > HubBall.REACH_Y + 0.15 \
					or Vector2(bp.x, bp.z).distance_to(at) > HubBall.REACH + REACH_SLACK:
				stat_denied += 1
				return
			_give(slot)
		ACT_DROP:
			if holder != slot or phase != Phase.HELD:
				stat_denied += 1
				return
			_release_drop(p)
		ACT_SHOOT:
			if holder != slot or phase != Phase.HELD:
				stat_denied += 1
				return
			_set_phase(Phase.SHOT)
			_wind = WINDUP_SHOT
		ACT_PASS:
			if holder != slot or phase != Phase.HELD or session.human_count() < 2:
				stat_denied += 1
				return
			var target := _pass_target(slot, at, arg)
			if target < 0:
				stat_denied += 1
				return
			pass_to = target
			_set_phase(Phase.PASS)
			_wind = WINDUP_PASS
		_:
			stat_denied += 1


## Who a pass goes to: the slot asked for if they are walking around, or
## the nearest party member who is.
func _pass_target(from_slot: int, at: Vector2, want: int) -> int:
	if want != from_slot and _human(want) and _mode(want) == HubSync.MODE_WALK:
		return want
	var best := -1
	var bd := INF
	for i in 8:
		if i == from_slot or not _human(i) or _mode(i) != HubSync.MODE_WALK:
			continue
		var d := (_pose(i)["pos"] as Vector2).distance_to(at)
		if d < bd:
			bd = d
			best = i
	return best


func _give(slot: int) -> void:
	holder = slot
	pass_to = -1
	sim.sleeping = true
	sim.vel = Vector3.ZERO
	_set_phase(Phase.HELD)
	changed.emit()


func _set_phase(ph: int) -> void:
	phase = ph
	phase_t = 0.0
	_dirty = true


static func _fwd(yaw: float) -> Vector2:
	return Vector2(-sin(yaw), -cos(yaw))


static func _pose_vel(p: Dictionary) -> Vector2:
	if p.is_empty() or int(p["mode"]) != HubSync.MODE_WALK:
		return Vector2.ZERO
	return _fwd(float(p["yaw"])) * float(p["speed"])


func _release_drop(p: Dictionary) -> void:
	var at: Vector2 = p["pos"]
	var f := _fwd(float(p["yaw"]))
	var v := _pose_vel(p)
	var start := Vector3(at.x + f.x * 0.22, 0.42, at.y + f.y * 0.22)
	_free_with(start, Vector3(v.x * 0.7, -0.6, v.y * 0.7), Vector3.ZERO)


func _free_with(start: Vector3, v: Vector3, spin: Vector3) -> void:
	var s := holder
	holder = -1
	sim.launch(start, v, spin)
	sim.shooter = s
	sim.ghost = {s: true} if s >= 0 else {}
	_ghost_t = GHOST_S
	_set_phase(Phase.FREE)
	changed.emit()


## The velocity that carries the ball from `a` to `b` in `t` seconds.
static func ballistic(a: Vector3, b: Vector3, t: float) -> Vector3:
	var d := b - a
	return Vector3(d.x / t, (d.y + 0.5 * HubBall.G * t * t) / t, d.z / t)


## The chance a shot from `at` goes in (distance to the rim; none from
## behind the backboard).
static func make_chance(at: Vector2) -> float:
	var rc := HubBall.rim_center()
	var to := at - Vector2(rc.x, rc.z)
	if to.dot(HubBall.HOOP_DIR) < -0.05:
		return 0.0
	var d := to.length()
	return clampf(P_CLOSE - (d - 1.0) * 0.13, P_FAR, P_CLOSE)


## Where a shot is aimed: the middle of the rim for a make, or a near miss
## (off the rim, short or long, or wide).
static func shot_aim(at: Vector2, make: bool, r: RandomNumberGenerator) -> Vector3:
	var rc := HubBall.rim_center()
	if make:
		return rc
	var dir := Vector2(rc.x, rc.z) - at
	dir = dir.normalized() if dir.length() > 0.01 else -HubBall.HOOP_DIR
	var side := Vector2(-dir.y, dir.x)
	var roll := r.randf()
	var off := Vector2.ZERO
	if roll < 0.55:
		# off the rim
		var ang := r.randf() * TAU
		off = Vector2(cos(ang), sin(ang)) * r.randf_range(0.11, 0.17)
	elif roll < 0.85:
		# short or long
		off = dir * (r.randf_range(0.17, 0.3) * (1.0 if r.randf() < 0.5 else -1.0))
	else:
		# wide
		off = side * (r.randf_range(0.2, 0.38) * (1.0 if r.randf() < 0.5 else -1.0))
	return rc + Vector3(off.x, 0.0, off.y)


static func shot_time(d: float) -> float:
	return 0.52 + 0.14 * d   # a high arc: it drops in at 55-70 degrees


func _launch_shot() -> void:
	var p := _pose(holder)
	if p.is_empty():
		_drop_here()
		return
	var at: Vector2 = p["pos"]
	var rc := HubBall.rim_center()
	var dir := Vector2(rc.x, rc.z) - at
	dir = dir.normalized() if dir.length() > 0.01 else -HubBall.HOOP_DIR
	# from up by the right shoulder (where the view holds it: HubBallView.SHOT_HOLD)
	var right := Vector2(-dir.y, dir.x)
	var rel := right * HubBallView.SHOT_HOLD.x - dir * HubBallView.SHOT_HOLD.z
	var start := Vector3(at.x + rel.x, HubBallView.SHOT_HOLD.y, at.y + rel.y)
	var make := rng.randf() < make_chance(at) if force_make < 0 else force_make == 1
	var aim := shot_aim(at, make, rng)
	var d := Vector2(aim.x - start.x, aim.z - start.z).length()
	var t := shot_time(d)
	var v := ballistic(start, aim, t)
	if not make:
		v *= rng.randf_range(0.985, 1.015)
	# backspin about the axis across the shot
	var spin := Vector3(-dir.y, 0.0, dir.x) * -14.0
	_free_with(start, v, spin)


func _launch_pass() -> void:
	var p := _pose(holder)
	var tp := _pose(pass_to)
	if p.is_empty() or tp.is_empty() or int(tp["mode"]) != HubSync.MODE_WALK:
		pass_to = -1
		_drop_here()
		return
	var at: Vector2 = p["pos"]
	var to: Vector2 = tp["pos"]
	var d0 := at.distance_to(to)
	var t := 0.22 + 0.11 * d0
	# lead the catcher a little
	var lead := to + _pose_vel(tp) * t * 0.8
	var dir := (lead - at).normalized() if lead.distance_to(at) > 0.01 else _fwd(float(p["yaw"]))
	var start := Vector3(at.x + dir.x * 0.22, 0.6, at.y + dir.y * 0.22)
	var aim := Vector3(lead.x, 0.55, lead.y)
	_pass_t = 0.0
	var target := pass_to
	_free_with(start, ballistic(start, aim, t), Vector3(-dir.y, 0.0, dir.x) * -6.0)
	pass_to = target
	sim.ghost[target] = true   # it catches it, it doesn't knock it away


func _drop_here() -> void:
	var p := _pose(holder)
	if p.is_empty():
		holder = -1
		pass_to = -1
		sim.launch(Vector3(sim.pos.x, 0.42, sim.pos.z), Vector3(0, -0.6, 0))
		_set_phase(Phase.FREE)
		changed.emit()
		return
	_release_drop(p)


func _host_tick(delta: float) -> void:
	if not spawned:
		spawned = true
		sim.place(HubBall.spawn_spot(rng))
		_dirty = true
	# the holder must still be walking around in the party
	if holder >= 0:
		var hp := _pose(holder)
		if not _human(holder) or hp.is_empty() or int(hp["mode"]) != HubSync.MODE_WALK:
			if hp.is_empty():
				holder = -1
				_drop_here()
			else:
				_release_drop(hp)
		else:
			var a: Vector2 = hp["pos"]
			sim.pos = Vector3(a.x, 0.45, a.y)   # (where it is if anything goes wrong)
	if phase == Phase.SHOT or phase == Phase.PASS:
		_wind -= delta
		if _wind <= 0.0 and holder >= 0:
			if phase == Phase.SHOT:
				_launch_shot()
			else:
				_launch_pass()
	if phase == Phase.FREE:
		_ghost_t -= delta
		if _ghost_t <= 0.0 and not sim.ghost.is_empty() and pass_to < 0:
			sim.ghost.clear()
		sim.players = _players_host()
		sim.step(delta)
		_events(true)
		if pass_to >= 0:
			_pass_t += delta
			var tp := _pose(pass_to)
			var b := sim.pos
			if not _human(pass_to) or tp.is_empty() or int(tp["mode"]) != HubSync.MODE_WALK or _pass_t > PASS_S:
				sim.ghost.erase(pass_to)
				pass_to = -1
				_dirty = true
			elif b.y > 0.15 and b.y < 1.2 and Vector2(b.x, b.z).distance_to(tp["pos"]) < CATCH_R:
				_give(pass_to)
	# send
	_send_t += delta
	_rest_t += delta
	var moving := phase != Phase.FREE or not sim.sleeping
	if _dirty:
		_dirty = false
		_send_t = 0.0
		_rest_t = 0.0
		_broadcast(true)
	elif moving and _send_t >= SEND_S:
		_send_t = 0.0
		_rest_t = 0.0
		_broadcast(false)
	elif _rest_t >= REST_SEND_S:
		_rest_t = 0.0
		_send_t = 0.0
		_broadcast(false)


func _players_host() -> Array:
	var out: Array = []
	var poses := hub().poses
	for s in poses:
		var p: Dictionary = poses[s]
		if int(p["mode"]) == HubSync.MODE_WALK and _human(int(s)) and int(s) != holder:
			out.append([p["pos"], _pose_vel(p), int(s)])
	return out


func _players_client() -> Array:
	var out: Array = []
	var h := hub()
	if h.local_mode == HubSync.MODE_WALK and session.local_slot != holder:
		out.append([h.local_pos, _fwd(h.local_yaw) * h.local_speed, session.local_slot])
	for i in 8:
		if i == session.local_slot or i == holder or not _human(i):
			continue
		var s := h.sample(i)
		if not s.is_empty() and int(s["mode"]) == HubSync.MODE_WALK:
			out.append([s["pos"], _fwd(float(s["yaw"])) * float(s["speed"]), i])
	return out


## The physics' events this frame: sounds for the view, and (the host's
## word only) a basket.
func _events(host: bool) -> void:
	for e in sim.events:
		if e.has("make"):
			if host:
				make_seq = (make_seq + 1) & 0xFF
				last_swish = bool(e["swish"])
				_dirty = true
				made.emit(int(e["shooter"]), last_swish)
			continue
		if e.has("rescue"):
			if host:
				_dirty = true
			continue
		sound.emit(int(e["kind"]), e["at"], float(e["strength"]))


func _broadcast(reliable: bool) -> void:
	_seq = (_seq + 1) & 0xFFFF
	var b := Protocol.buf_for(SocialProto.BALL_STATE)
	b.put_u16(_seq)
	b.put_u8(phase)
	b.put_8(holder)
	b.put_8(pass_to)
	b.put_8(clampi(sim.shooter, -1, 7))
	b.put_u8(make_seq)
	b.put_u8((1 if sim.sleeping else 0) | (2 if last_swish else 0))
	for c in [sim.pos.x, sim.pos.y, sim.pos.z]:
		b.put_16(clampi(int(round(float(c) * POS_Q)), -32767, 32767))
	for c in [sim.vel.x, sim.vel.y, sim.vel.z]:
		b.put_16(clampi(int(round(float(c) * VEL_Q)), -32767, 32767))
	session.transport.broadcast(b.data_array, reliable)


# ---------------------------------------------------------------------------
# Client
# ---------------------------------------------------------------------------
func client_packet(b: StreamPeerBuffer) -> void:
	if not in_room() or b.get_available_bytes() < 20:
		return
	var seq := b.get_u16()
	if not HubSync._newer(seq, _last_seq):
		return
	_last_seq = seq
	var ph := b.get_u8()
	var hold := b.get_8()
	var pto := b.get_8()
	var shooter := b.get_8()
	var mseq := b.get_u8()
	var flags := b.get_u8()
	var p := Vector3(float(b.get_16()), float(b.get_16()), float(b.get_16())) / POS_Q
	var v := Vector3(float(b.get_16()), float(b.get_16()), float(b.get_16())) / VEL_Q
	if ph > Phase.PASS or hold < -1 or hold > 7 or pto < -1 or pto > 7 or not is_finite(p.length()) or not is_finite(v.length()):
		return
	var was_free := phase == Phase.FREE and spawned
	if ph != phase:
		phase = ph
		phase_t = 0.0
	var hold_changed := hold != holder
	holder = hold
	pass_to = pto
	sim.shooter = shooter
	if _make_known and mseq != make_seq:
		last_swish = (flags & 2) != 0
		made.emit(shooter, last_swish)
	make_seq = mseq
	_make_known = true
	if phase == Phase.FREE:
		# a correction: draw from where it was, easing to the host's ball
		var drawn := sim.pos + err
		var jump := drawn.distance_to(p)
		sim.pos = p
		sim.vel = v
		sim.sleeping = (flags & 1) != 0
		if was_free and jump < 1.2:
			err = drawn - p
		elif not was_free:
			# just thrown: the view hands over from the hand to the flight
			err = Vector3.ZERO
			sim.touched_rim = false
		else:
			err = Vector3.ZERO
	else:
		sim.pos = p
		sim.vel = Vector3.ZERO
		sim.sleeping = true
		err = Vector3.ZERO
	spawned = true
	if hold_changed:
		changed.emit()


func _client_tick(delta: float) -> void:
	if phase == Phase.FREE and spawned:
		sim.players = _players_client()
		sim.ghost = {}
		if holder < 0 and sim.shooter >= 0 and phase_t < GHOST_S:
			sim.ghost[sim.shooter] = true
		if pass_to >= 0:
			sim.ghost[pass_to] = true
		sim.step(delta)
		_events(false)
	err *= exp(-delta * 9.0)
	if err.length() < 0.001:
		err = Vector3.ZERO


# ---------------------------------------------------------------------------
func tick(delta: float) -> void:
	_clock += delta
	if not in_room():
		if spawned or holder >= 0:
			clear()
		return
	phase_t += delta
	if session.is_host():
		_host_tick(delta)
	else:
		_client_tick(delta)


## A round started or the party room closed: the ball is put away (the next
## party room starts it somewhere new).
func clear() -> void:
	var had := holder >= 0
	spawned = false
	phase = Phase.FREE
	holder = -1
	pass_to = -1
	phase_t = 0.0
	err = Vector3.ZERO
	_last_seq = -1
	_make_known = false
	sim.ghost.clear()
	sim.place(Vector3(0, HubBall.R, 0))
	if had:
		changed.emit()
