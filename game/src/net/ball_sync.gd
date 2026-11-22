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
##   68 BALL_REQ    client -> host  (reliable)  u8 act, i8 arg (pass: target slot;
##                                             shoot: ARG_DUNK asks for a dunk), u16 yaw
##                                             (build 25), u16 claim ms (build 33, block)
##   69 BALL_STATE  host -> clients            u16 seq, u8 phase, i8 holder, i8 pass_to,
##                                             i8 shooter, u8 make_seq, u8 flags,
##                                             i16 x3 pos (1/1024 m), i16 x3 vel (1/512 m/s)
##                                             (build 33, appended) i8 jumper, u8 jump_seq,
##                                             u8 jump age (1/100 s), u8 jump bits,
##                                             i16 x2 jump from, i16 x2 jump to
##
## (build 33) Dunks and blocks, additive (older builds ignore what they don't
## know): close to the rim and facing it, Shoot is Dunk.  The guest asks
## for a shot with ARG_DUNK (an older host just takes it as a shot); the
## host makes it a dunk when the dunker is in range.  It is a SHOT phase
## flagged F_DUNK (an older guest draws a jump shot and the ball dropping
## through the net): the gather step, the jump, the slam (always a make
## unless blocked), the hang on the rim and the drop are laid out on every
## device from where the dunk started (the state's position during it) and
## the phase's clock, so the dunker's body path needs nothing more.
## Someone without the ball close to a shooter in their windup (or a
## dunker in their gather), or to a shot just released, can Block: their
## runner jumps at once and asks the host (ACT_BLOCK) with how far into the
## shot they saw it; the host takes that claim when it is plausible (not
## ahead of its own clock, at most BLOCK_GRACE_S behind it: one round trip
## and some), checks the window and the reach at that moment (the shot's
## flight is kept for it) and swats the ball away, or calls it a whiff.
## Every jump (hit or whiff) goes out in the state so everyone sees it.

signal made(slot: int, swish: bool)
signal sound(kind: int, at: Vector3, strength: float)
## who has it changed (pick up, catch, release)
signal changed
## something to tell the local player
signal notice(text: String)
## (build 33) a block swatted the ball away (every device)
signal blocked(blocker: int, shooter: int)
## (build 33) someone jumped to block (every device)
signal jumped(slot: int)

const ACT_PICKUP := 1
const ACT_DROP := 2
const ACT_SHOOT := 3
const ACT_PASS := 4
## (build 33)
const ACT_BLOCK := 6
const ARG_DUNK := 1
const F_SLEEP := 1
const F_SWISH := 2
const F_DUNK := 4
const F_BLOCKED := 8
enum Phase { FREE, HELD, SHOT, PASS }
## (build 25) a real shooting form (HubBallView draws it); (build 30) a
## little longer for the whole of it: the gather to the chest, the dip, the
## rise to the set point and the release
const WINDUP_SHOT := 0.6
## a shot goes the way the shooter faces; within this angle of the hoop it
## is lined up on the rim (an aim assist), the make chance easing off
## toward the edge of it
const AIM_ASSIST := 0.2443   # 14 degrees
## a shot not at the hoop flies this far (where the hoop would be, within these)
const FREE_SHOT_D := Vector2(1.6, 4.5)
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

# --- (build 33) the dunk
## horizontal distance from the runner to the middle of the rim
const DUNK_RANGE := 1.5
## (the host's allowance: its pose of a guest is a little old)
const DUNK_SLACK := 0.3
## from in front of the hoop: within this of the way it faces (75 degrees)
const DUNK_FRONT := 1.31
## and facing the rim roughly (70 degrees)
const DUNK_FACE := 1.22
## the windup: the gather step (to where they take off), the load, the
## jump (in toward the rim near the top of it) and the slam
const WINDUP_DUNK := 0.9
const DUNK_T_GATHER := 0.3
const DUNK_T_TAKEOFF := 0.4
const DUNK_T_APEX := 0.76
## the body's distance from the middle of the rim: taking off (the ball,
## carried up in front of the chin, comes up outside the rim), at the slam
## (the ball over the rim, the big head in front of it), hanging, landed
const DUNK_TAKEOFF_D := 0.8
const DUNK_SLAM_D := 0.63
const DUNK_HANG_D := 0.59
const DUNK_LAND_D := 0.72
## the jump: the hips this high at the top and hanging on the rim.  A
## cartoon jump: the rim is at 1.8 m, a runner's shoulders at 0.84 and their
## arms 0.32 long, and the ball has to clear the rim in front of the chin
## (the head is too big for hands over it)
const DUNK_APEX := 1.02
const DUNK_HANG := 0.86
## after the release: hanging, then letting go and the drop and landing
const DUNK_LET_GO := 0.5
const DUNK_AFTER_S := 1.15
## the ball leaves the hands over the rim's near side, thrown down and in
## through it (clear of the rim: a make)
const DUNK_REL_H := 0.16
const DUNK_REL_Y := 0.1
const DUNK_REL_V := Vector2(2.2, -2.6)
const DUNK_GHOST_S := 1.4

# --- (build 33) the block
## the Block button shows this close to a shooter (horizontal)
const BLOCK_RANGE := 1.8
const BLOCK_SLACK := 0.45
## a shot can still be blocked this long after it leaves the hands ...
const BLOCK_FLIGHT_S := 0.22
## ... with the ball this close (horizontal)
const BLOCK_BALL_R := 1.5
## a dunk until the dunker takes off
const DUNK_BLOCK_T := 0.4
## the host takes a guest's claim at most this far behind its own clock
const BLOCK_GRACE_S := 0.25
const BLOCK_COOL := 1.0
## the jump (seconds) and the lunge toward the shooter
const BLOCK_JUMP_S := 0.7
const BLOCK_LUNGE := 0.8
const BLOCK_STOP := 0.85
const BLOCK_LUNGE_S := 0.3
## the swat lands this far into the blocker's jump (the hand is up)
const BLOCK_HIT_T := 0.17

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
var _shot_yaw := 0.0
## (build 25) the last release was a shot (the view's follow-through and the
## shooter's camera); everyone knows (clients: from the phase change)
var released_shot := false
## (build 33) the shot winding up is a dunk (SHOT), the last release was a
## dunk (FREE) / was swatted away by a block; where the dunk started
var dunk := false
var released_dunk := false
var released_blocked := false
var dunk_from := Vector2.ZERO
## who is jumping to block: slot -> {t0 (this device's clock), from, to
## (Vector2), hit, mine}
var jumps: Dictionary = {}
var jump_seq := 0
var stat_blocks := 0
var stat_whiffs := 0
var _jump_known := false
var _jump_last := -1
var _block_t: Dictionary = {}
var _my_block_t := -10.0
## the host: the shot's flight just after the release [[clock, pos]]
var _hist: Array = []
## the host: a block called, the swat to come (when, [blocker, shooter, at])
var _swat_at := -1.0
var _swat_by: Array = []
## clients: the last jump that was a block (its blocker), for the swat
var _hit_by := -1


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


## (build 25) `yaw`: the way the runner faces as they shoot (the shot goes
## that way); NAN: their last pose's.
func request(act: int, arg: int = -1, yaw: float = NAN, claim: float = -1.0) -> void:
	if not in_room():
		return
	if session.is_host():
		_host_req(session.local_slot, act, arg, yaw, claim)
		return
	if session.host_peer < 0:
		return
	var b := Protocol.buf_for(SocialProto.BALL_REQ)
	b.put_u8(act)
	b.put_8(clampi(arg, -1, 7))
	if is_finite(yaw) or act == ACT_BLOCK:
		# (build 25) appended: a build 24 host reads the first two bytes only
		b.put_u16(int(fposmod(yaw if is_finite(yaw) else 0.0, TAU) / TAU * 65535.0) & 0xFFFF)
	if act == ACT_BLOCK:
		# (build 33) how far into the shot this device saw it (ms; none: 0xFFFF)
		b.put_u16(clampi(int(round(claim * 1000.0)), 0, 0xFFFE) if claim >= 0.0 else 0xFFFF)
	session.transport.send(session.host_peer, b.data_array, true)


# ---------------------------------------------------------------------------
# (build 33) Dunks
# ---------------------------------------------------------------------------
static func rim2() -> Vector2:
	var rc := HubBall.rim_center()
	return Vector2(rc.x, rc.z)


## Can a runner at `at` facing `yaw` dunk?  (In range of the rim, in front
## of the hoop, facing it roughly; `slack`: the host's allowance.)
static func dunk_ok(at: Vector2, yaw: float, slack: float = 0.0) -> bool:
	var to := at - rim2()
	var d := to.length()
	if d > DUNK_RANGE + slack:
		return false
	if d > 0.05 and absf(HubBall.HOOP_DIR.angle_to(to)) > DUNK_FRONT + slack * 0.4:
		return false
	if d > 0.4 and absf(_fwd(yaw).angle_to(-to)) > DUNK_FACE + slack:
		return false
	return true


## The way from the rim to the dunker (their approach; in front of the hoop).
## The way in is open floor: where they take off, slam, hang and land
## (the beanbag and the floor lamp are close to the hoop on either side,
## so from there the dunker curves in a little more from the front).
static func dunk_dir(from: Vector2) -> Vector2:
	var to := from - rim2()
	if to.length() < 0.05:
		return HubBall.HOOP_DIR
	var a := clampf(HubBall.HOOP_DIR.angle_to(to), -DUNK_FRONT, DUNK_FRONT)
	for i in 14:
		var u := HubBall.HOOP_DIR.rotated(a)
		if _lane_free(u):
			return u
		a = move_toward(a, 0.0, 0.1)
	return HubBall.HOOP_DIR


static func _lane_free(u: Vector2) -> bool:
	var rc := rim2()
	for k in 6:
		if not HubRoom.is_free(rc + u * lerpf(DUNK_HANG_D, DUNK_TAKEOFF_D + 0.05, float(k) / 5.0)):
			return false
	return true


## The way a dunker faces (at the rim).
static func dunk_yaw(from: Vector2) -> float:
	var u := dunk_dir(from)
	return atan2(u.x, u.y)


static func _out(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - (1.0 - x) * (1.0 - x)


## Where the dunker stands (the floor under them) `t` seconds into a dunk
## that started at `from`: the gather step and the jump carry them in to
## the slam, they swing back a little hanging on the rim, and push off it
## as they let go (their head clears the rim all the way).
static func dunk_body(from: Vector2, t: float) -> Vector2:
	var u := dunk_dir(from)
	var rc := rim2()
	var d0 := maxf(0.0, (from - rc).dot(u))
	var side := (from - rc) - u * (from - rc).dot(u)
	var d: float
	var a := DUNK_T_APEX - 0.06
	if t < DUNK_T_TAKEOFF:
		var x := t / DUNK_T_TAKEOFF
		d = lerpf(d0, DUNK_TAKEOFF_D, BallMoves.ease3(x) * 0.4 + _out(x) * 0.6)
		side *= 1.0 - BallMoves.ease3(x)
	elif t < a:
		d = lerpf(DUNK_TAKEOFF_D, DUNK_TAKEOFF_D - 0.03, (t - DUNK_T_TAKEOFF) / (a - DUNK_T_TAKEOFF))
		side = Vector2.ZERO
	elif t < WINDUP_DUNK:
		d = lerpf(DUNK_TAKEOFF_D - 0.03, DUNK_SLAM_D, BallMoves.ease3((t - a) / 0.12))
		side = Vector2.ZERO
	elif t < WINDUP_DUNK + DUNK_LET_GO:
		d = lerpf(DUNK_SLAM_D, DUNK_HANG_D, BallMoves.ease3((t - WINDUP_DUNK) / 0.15))
		side = Vector2.ZERO
	else:
		d = lerpf(DUNK_HANG_D, DUNK_LAND_D, _out((t - WINDUP_DUNK - DUNK_LET_GO) / 0.25))
		side = Vector2.ZERO
	return rc + u * d + side


## Where the slammed ball leaves the hands (stage space).
static func dunk_release(from: Vector2) -> Vector3:
	var u := dunk_dir(from)
	var rc := HubBall.rim_center()
	return rc + Vector3(u.x, 0.0, u.y) * DUNK_REL_H + Vector3(0, DUNK_REL_Y, 0)


## Who is dunking (-1 nobody) and how far into it (seconds).
func dunker() -> int:
	if phase == Phase.SHOT and dunk and holder >= 0:
		return holder
	if phase == Phase.FREE and released_dunk and phase_t < DUNK_AFTER_S:
		return sim.shooter
	return -1


func dunk_clock() -> float:
	if phase == Phase.SHOT and dunk:
		return phase_t
	if phase == Phase.FREE and released_dunk and phase_t < DUNK_AFTER_S:
		return WINDUP_DUNK + phase_t
	return -1.0


# ---------------------------------------------------------------------------
# (build 33) Blocks
# ---------------------------------------------------------------------------
## How far into the shot now (the windup, then the flight); -1 no shot.
func shot_clock() -> float:
	if phase == Phase.SHOT:
		return phase_t
	if phase == Phase.FREE and released_shot:
		return WINDUP_SHOT + phase_t
	return -1.0


## The shooter whose shot can be blocked right now (-1 none).
func block_shooter() -> int:
	if phase == Phase.SHOT and holder >= 0:
		if phase_t <= (DUNK_BLOCK_T if dunk else WINDUP_SHOT):
			return holder
	elif phase == Phase.FREE and released_shot and phase_t <= BLOCK_FLIGHT_S:
		return sim.shooter
	return -1


## Where a runner stands as this device sees them (a dunk's path included).
func slot_pos(s: int) -> Variant:
	if s < 0:
		return null
	if s == dunker():
		return dunk_body(dunk_from, dunk_clock())
	if session.is_host():
		var p := _pose(s)
		return null if p.is_empty() else p["pos"]
	if s == session.local_slot:
		return hub().local_pos
	var smp := hub().sample(s)
	return null if smp.is_empty() else smp["pos"]


## The shooter the local runner (at `at`) can block now, or -1.
func block_target(at: Vector2) -> int:
	if not in_room() or not spawned or local_has() or _clock - _my_block_t < BLOCK_COOL:
		return -1
	if not jump_of(session.local_slot).is_empty():
		return -1
	var s := block_shooter()
	if s < 0 or s == session.local_slot:
		return -1
	if phase == Phase.FREE:
		var b := sim.pos + err
		return s if Vector2(b.x, b.z).distance_to(at) <= BLOCK_BALL_R else -1
	var sp: Variant = slot_pos(s)
	if sp == null:
		return -1
	return s if (sp as Vector2).distance_to(at) <= BLOCK_RANGE else -1


## Where a block's lunge ends: toward the shooter, stopping short of them.
static func lunge_to(from: Vector2, toward: Vector2) -> Vector2:
	var d := toward - from
	var l := d.length()
	if l < 0.01:
		return from
	return HubRoom.resolve(from + d / l * clampf(l - BLOCK_STOP, 0.0, BLOCK_LUNGE))


## The local runner jumps to block (at `at`, facing `yaw`): at once on this
## device, and the host decides.
func request_block(at: Vector2, yaw: float) -> void:
	if not in_room() or not spawned or local_has() or _clock - _my_block_t < BLOCK_COOL:
		return
	var me := session.local_slot
	var tg := block_target(at)
	var claim := shot_clock() if tg >= 0 else -1.0
	_my_block_t = _clock
	if session.is_host():
		_host_req(me, ACT_BLOCK, tg, yaw, claim)
		return
	var sp: Variant = slot_pos(tg) if tg >= 0 else null
	var toward: Vector2 = sp if sp != null else at + _fwd(yaw)
	jumps[me] = {"t0": _clock, "from": at, "to": lunge_to(at, toward), "hit": false, "mine": true}
	jumped.emit(me)
	request(ACT_BLOCK, tg, yaw, claim)


## Can the local runner jump to block at all right now (the cooldown)?
func block_ready() -> bool:
	return _clock - _my_block_t >= BLOCK_COOL and jump_of(session.local_slot).is_empty()


## A jump in progress: {t (seconds in), from, to, hit} or {}.
func jump_of(s: int) -> Dictionary:
	var j: Dictionary = jumps.get(s, {})
	if j.is_empty():
		return {}
	var t := _clock - float(j["t0"])
	if t >= BLOCK_JUMP_S or t < 0.0:
		return {}
	return {"t": t, "from": j["from"], "to": j["to"], "hit": j["hit"]}


## Where a jumping runner is over the floor `t` into the jump.
static func jump_pos(j: Dictionary, t: float) -> Vector2:
	return (j["from"] as Vector2).lerp(j["to"], _out(t / BLOCK_LUNGE_S))


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
	var yaw := NAN
	if b.get_available_bytes() >= 2:
		yaw = float(b.get_u16()) / 65535.0 * TAU
	var claim := -1.0
	if b.get_available_bytes() >= 2:
		var c := b.get_u16()
		claim = -1.0 if c == 0xFFFF else float(c) / 1000.0
	_host_req(slot, act, arg, yaw, claim)


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


func _host_req(slot: int, act: int, arg: int, yaw: float = NAN, claim: float = -1.0) -> void:
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
			# (build 25) the way they face as they shoot (else their pose's)
			_shot_yaw = yaw if is_finite(yaw) else float(p["yaw"])
			# (build 33) asked for a dunk, and in range: a dunk
			dunk = arg == ARG_DUNK and dunk_ok(at, _shot_yaw, DUNK_SLACK)
			if dunk:
				dunk_from = at
			_set_phase(Phase.SHOT)
			_wind = WINDUP_DUNK if dunk else WINDUP_SHOT
		ACT_BLOCK:
			_host_block(slot, arg, claim, at, yaw if is_finite(yaw) else float(p["yaw"]))
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
	dunk = false
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
	released_shot = false
	var at: Vector2 = p["pos"]
	var f := _fwd(float(p["yaw"]))
	var v := _pose_vel(p)
	# (build 30) from beside the right hand, where it is dribbled (clear of
	# the legs)
	var rt := Vector2(-f.y, f.x)
	var start := Vector3(at.x + f.x * 0.12 + rt.x * 0.37, 0.42, at.y + f.y * 0.12 + rt.y * 0.37)
	_free_with(start, Vector3(v.x * 0.7, -0.6, v.y * 0.7), Vector3.ZERO)


func _free_with(start: Vector3, v: Vector3, spin: Vector3) -> void:
	var s := holder
	holder = -1
	dunk = false
	released_dunk = false
	released_blocked = false
	_hist.clear()
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
	# (build 30) in terms of the rim and the ball (both bigger)
	var rr := HubBall.RIM_R
	if roll < 0.55:
		# off the rim
		var ang := r.randf() * TAU
		off = Vector2(cos(ang), sin(ang)) * r.randf_range(rr - HubBall.R * 0.4, rr + HubBall.R * 0.15)
	elif roll < 0.85:
		# short or long
		off = dir * (r.randf_range(rr * 0.98, rr * 1.72) * (1.0 if r.randf() < 0.5 else -1.0))
	else:
		# wide
		off = side * (r.randf_range(rr * 1.15, rr * 2.2) * (1.0 if r.randf() < 0.5 else -1.0))
	return rc + Vector3(off.x, 0.0, off.y)


static func shot_time(d: float) -> float:
	return 0.52 + 0.14 * d   # a high arc: it drops in at 55-70 degrees


## Where a shot from `at`, facing `yaw`, goes: {dir (Vector2), rim (bool:
## lined up on the hoop), off (radians off the hoop)}.
static func shot_line(at: Vector2, yaw: float) -> Dictionary:
	var f := Vector2(-sin(yaw), -cos(yaw))
	var rc := HubBall.rim_center()
	var to := Vector2(rc.x, rc.z) - at
	if to.length() < 0.05:
		return {"dir": f, "rim": true, "off": 0.0}
	var off := absf(f.angle_to(to))
	if off <= AIM_ASSIST:
		return {"dir": to.normalized(), "rim": true, "off": off}
	return {"dir": f, "rim": false, "off": off}


## The set point the ball leaves from (HubBallView.SHOT_HOLD), shooting along `dir`.
static func shot_start(at: Vector2, dir: Vector2) -> Vector3:
	var right := Vector2(-dir.y, dir.x)
	var rel := right * HubBallView.SHOT_HOLD.x - dir * HubBallView.SHOT_HOLD.z
	return Vector3(at.x + rel.x, HubBallView.SHOT_HOLD.y, at.y + rel.y)


func _launch_shot() -> void:
	var p := _pose(holder)
	if p.is_empty():
		_drop_here()
		return
	var at: Vector2 = p["pos"]
	var line := shot_line(at, _shot_yaw)
	var dir: Vector2 = line["dir"]
	var start := shot_start(at, dir)
	var make := false
	var aim: Vector3
	if bool(line["rim"]):
		# facing the hoop: lined up on the rim; a little off makes it harder
		var k := float(line["off"]) / AIM_ASSIST
		var chance := make_chance(at) * (1.0 - 0.45 * k * k)
		make = rng.randf() < chance if force_make < 0 else force_make == 1
		aim = shot_aim(at, make, rng)
	else:
		# facing elsewhere: it flies that way, as far as the hoop is
		var rc := HubBall.rim_center()
		var dd := clampf(Vector2(rc.x, rc.z).distance_to(at), FREE_SHOT_D.x, FREE_SHOT_D.y)
		aim = Vector3(start.x + dir.x * dd, HubBall.RIM_Y, start.z + dir.y * dd)
	var d := Vector2(aim.x - start.x, aim.z - start.z).length()
	var t := shot_time(d)
	var v := ballistic(start, aim, t)
	if not make:
		v *= rng.randf_range(0.985, 1.015)
	# backspin about the axis across the shot
	var spin := Vector3(-dir.y, 0.0, dir.x) * -14.0
	_free_with(start, v, spin)
	released_shot = true
	_hist = [[_clock, start]]


## (build 33) The slam: the ball leaves the hands just inside the rim's near
## side, thrown down through it (a make); the dunker's body is ghosted
## while they hang and drop.
func _launch_dunk() -> void:
	var s := holder
	var u := dunk_dir(dunk_from)
	var start := dunk_release(dunk_from)
	var v := Vector3(-u.x * DUNK_REL_V.x, DUNK_REL_V.y, -u.y * DUNK_REL_V.x)
	_free_with(start, v, Vector3(u.y, 0.0, -u.x) * 9.0)
	released_shot = false
	released_dunk = true
	sim.ghost[s] = true
	_ghost_t = DUNK_GHOST_S


## (build 33) A block: the jump (everyone sees it), and whether it is in
## time and close enough.  `claim`: how far into the shot the blocker saw it.
func _host_block(slot: int, target: int, claim: float, at: Vector2, yaw: float) -> void:
	if _clock - float(_block_t.get(slot, -10.0)) < BLOCK_COOL - 0.15 or holder == slot:
		stat_denied += 1
		return
	_block_t[slot] = _clock
	var shooter := -1
	if phase == Phase.SHOT and holder >= 0:
		shooter = holder
	elif phase == Phase.FREE and released_shot and phase_t < 1.0:
		shooter = sim.shooter
	var now := shot_clock()
	var c := now
	if claim >= 0.0 and now >= 0.0 and claim <= now + 0.05 and now - claim <= BLOCK_GRACE_S:
		c = claim   # (the blocker saw it then: one-way latency behind, and the request took as long)
	var hit := shooter >= 0 and shooter != slot and (target < 0 or target == shooter) and _block_ok(at, shooter, c)
	var sp: Variant = slot_pos(shooter) if shooter >= 0 else null
	var toward: Vector2 = sp if sp != null else at + _fwd(yaw)
	_jump(slot, at, lunge_to(at, toward), hit)
	if hit:
		stat_blocks += 1
		# the ball leaves when the blocker's hand is up (BLOCK_HIT_T into
		# their jump, which began when they pressed: a guest's one round
		# trip ago, the claim says)
		var waited := clampf(now - c, 0.0, BLOCK_GRACE_S) if c >= 0.0 and now >= 0.0 else 0.0
		_swat_at = _clock + maxf(0.0, BLOCK_HIT_T - waited)
		_swat_by = [slot, shooter, at]
	else:
		stat_whiffs += 1


func _block_ok(at: Vector2, shooter: int, c: float) -> bool:
	if c < 0.0:
		return false
	if phase == Phase.SHOT and dunk:
		return c <= DUNK_BLOCK_T + 0.02 and dunk_body(dunk_from, c).distance_to(at) <= BLOCK_RANGE + BLOCK_SLACK
	if c <= WINDUP_SHOT:
		var p := _pose(shooter)
		return not p.is_empty() and (p["pos"] as Vector2).distance_to(at) <= BLOCK_RANGE + BLOCK_SLACK
	if c <= WINDUP_SHOT + BLOCK_FLIGHT_S + 0.02:
		# the ball where it was then
		var b: Variant = _hist_at(c - WINDUP_SHOT)
		if b == null:
			return false
		var bp: Vector3 = b
		return bp.y < 2.8 and Vector2(bp.x, bp.z).distance_to(at) <= BLOCK_BALL_R + BLOCK_SLACK * 0.5
	return false


## The ball `t` seconds after the release (the host's record), or null.
func _hist_at(t: float) -> Variant:
	if _hist.is_empty():
		return null
	var want := float(_hist[0][0]) + t
	var best: Variant = _hist[0][1]
	for h in _hist:
		if float(h[0]) <= want + 0.0001:
			best = h[1]
	return best


## The ball swatted away: sideways and down, off the blocker's hand.
func _swat(blocker: int, shooter: int, at: Vector2) -> void:
	var start := sim.pos
	if phase == Phase.SHOT:
		start = _hands_ball(shooter)
	var away := Vector2(start.x - at.x, start.z - at.y)
	away = away.normalized() if away.length() > 0.02 else _fwd(_shot_yaw)
	var side := Vector2(-away.y, away.x) * (1.0 if rng.randf() < 0.5 else -1.0)
	var dir := (away * 0.8 + side * rng.randf_range(0.45, 0.85)).normalized()
	var sp := rng.randf_range(2.6, 3.4)
	var v := Vector3(dir.x * sp, rng.randf_range(-1.4, 0.5), dir.y * sp)
	if phase == Phase.SHOT:
		holder = shooter
	_free_with(start, v, Vector3(dir.y, rng.randf_range(-6.0, 6.0), -dir.x) * 12.0)
	sim.shooter = shooter
	sim.ghost = {shooter: true, blocker: true}
	_ghost_t = 0.3
	released_shot = false
	released_blocked = true
	blocked.emit(blocker, shooter)


## Where the ball is in a shooter's hands during the windup (stage space).
func _hands_ball(s: int) -> Vector3:
	var at: Vector2
	var yaw := _shot_yaw
	var local: Vector3
	if dunk:
		at = dunk_body(dunk_from, phase_t)
		yaw = dunk_yaw(dunk_from)
		local = BallMoves.dunk(phase_t, BallMoves.POCKET, 1, Vector3.INF)["ball"]
	else:
		var p := _pose(s)
		at = p["pos"] if not p.is_empty() else Vector2(sim.pos.x, sim.pos.z)
		local = BallMoves.shot(clampf(phase_t / WINDUP_SHOT, 0.0, 1.0), BallMoves.POCKET, 1)["ball"]
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, 0.0, at.y)) * local


func _jump(slot: int, from: Vector2, to: Vector2, hit: bool) -> void:
	jump_seq = (jump_seq + 1) & 0xFF
	_jump_last = slot
	jumps[slot] = {"t0": _clock, "from": from, "to": to, "hit": hit, "mine": slot == session.local_slot}
	_dirty = true
	jumped.emit(slot)


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
	# (build 30) from the chest, clear of it (HubBallView's chest pass)
	var start := Vector3(at.x + dir.x * 0.42, 0.75, at.y + dir.y * 0.42)
	var aim := Vector3(lead.x, 0.6, lead.y)
	_pass_t = 0.0
	released_shot = false
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
			# (build 33) a dunk: where it started (everyone lays it out from there)
			if phase == Phase.SHOT and dunk:
				a = dunk_from
			sim.pos = Vector3(a.x, 0.45, a.y)   # (where it is if anything goes wrong)
	if _swat_at >= 0.0 and _clock >= _swat_at:
		# (build 33) a block's swat: the ball out of the hands or the air
		_swat_at = -1.0
		var sb: int = _swat_by[1]
		if (phase == Phase.SHOT and holder == sb) or (phase == Phase.FREE and released_shot and sim.shooter == sb):
			_swat(int(_swat_by[0]), sb, _swat_by[2])
	if phase == Phase.SHOT or phase == Phase.PASS:
		_wind -= delta
		if _wind <= 0.0 and holder >= 0:
			if phase == Phase.SHOT:
				if dunk:
					_launch_dunk()
				else:
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
		if released_shot and phase_t < BLOCK_FLIGHT_S + BLOCK_GRACE_S:
			_hist.append([_clock, sim.pos])
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
	var dk := (phase == Phase.SHOT and dunk) or (phase == Phase.FREE and released_dunk)
	b.put_u8((F_SLEEP if sim.sleeping else 0) | (F_SWISH if last_swish else 0) | (F_DUNK if dk else 0) \
		| (F_BLOCKED if phase == Phase.FREE and released_blocked else 0))
	for c in [sim.pos.x, sim.pos.y, sim.pos.z]:
		b.put_16(clampi(int(round(float(c) * POS_Q)), -32767, 32767))
	for c in [sim.vel.x, sim.vel.y, sim.vel.z]:
		b.put_16(clampi(int(round(float(c) * VEL_Q)), -32767, 32767))
	# (build 33, appended: older builds stop reading before it) the last jump to block
	var j: Dictionary = jumps.get(_jump_last, {})
	b.put_8(_jump_last if not j.is_empty() else -1)
	b.put_u8(jump_seq)
	b.put_u8(clampi(int((_clock - float(j.get("t0", _clock))) * 100.0), 0, 255))
	b.put_u8(1 if bool(j.get("hit", false)) else 0)
	var jf: Vector2 = j.get("from", Vector2.ZERO)
	var jt: Vector2 = j.get("to", Vector2.ZERO)
	for c in [jf.x, jf.y, jt.x, jt.y]:
		b.put_16(clampi(int(round(float(c) * POS_Q)), -32767, 32767))
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
	var f_dunk := (flags & F_DUNK) != 0
	var f_blk := (flags & F_BLOCKED) != 0
	var swatted := f_blk and ph == Phase.FREE and (ph != phase or not released_blocked)
	if ph != phase and ph == Phase.FREE:
		# (build 33) a dunk's release / a block's swat is no jump shot
		released_shot = phase == Phase.SHOT and not f_dunk and not f_blk
		released_dunk = phase == Phase.SHOT and f_dunk
	if ph == Phase.FREE:
		released_blocked = f_blk
	if ph != phase:
		phase = ph
		phase_t = 0.0
	if ph == Phase.SHOT:
		dunk = f_dunk
		if dunk:
			dunk_from = Vector2(p.x, p.z)
	elif ph != Phase.FREE:
		dunk = false
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
	# (build 33) the last jump to block
	if b.get_available_bytes() >= 12:
		var jumper := b.get_8()
		var jseq := b.get_u8()
		var age := float(b.get_u8()) / 100.0
		var hit := (b.get_u8() & 1) != 0
		var jp: Array = []
		for i in 4:
			jp.append(float(b.get_16()) / POS_Q)
		if _jump_known and jseq != jump_seq and jumper >= 0 and jumper <= 7:
			var mine: Dictionary = jumps.get(jumper, {})
			if jumper == session.local_slot and not mine.is_empty() and _clock - float(mine["t0"]) < 0.9:
				mine["hit"] = hit   # (this device jumped when the button was pressed)
			else:
				jumps[jumper] = {"t0": _clock - age, "from": Vector2(jp[0], jp[1]), "to": Vector2(jp[2], jp[3]), "hit": hit, "mine": false}
				jumped.emit(jumper)
			if hit:
				_hit_by = jumper
		jump_seq = jseq
		_jump_known = true
	if swatted:
		blocked.emit(_hit_by, shooter)
	if hold_changed:
		changed.emit()


func _client_tick(delta: float) -> void:
	if phase == Phase.FREE and spawned:
		sim.players = _players_client()
		sim.ghost = {}
		if holder < 0 and sim.shooter >= 0 and phase_t < (DUNK_GHOST_S if released_dunk else GHOST_S):
			sim.ghost[sim.shooter] = true
		if released_blocked and phase_t < 0.3:
			for s in jumps:
				sim.ghost[s] = true
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
	for s in jumps.keys():
		if _clock - float(jumps[s]["t0"]) > BLOCK_JUMP_S + 2.0:
			jumps.erase(s)
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
	dunk = false
	released_dunk = false
	released_blocked = false
	released_shot = false
	jumps.clear()
	_swat_at = -1.0
	_hit_by = -1
	_jump_known = false
	_jump_last = -1
	_hist.clear()
	if had:
		changed.emit()
