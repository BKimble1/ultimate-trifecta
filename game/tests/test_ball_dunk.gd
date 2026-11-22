extends RefCounted
## (build 33) Dunks and blocks (BallSync, HubBall, HubWalk, HubBallView).
##
## Close to the rim and facing it, Shoot becomes Dunk; the dunk is the
## host's (a SHOT flagged F_DUNK) and every guest lays out the same gather,
## jump, slam, hang and drop from where it started; the slam always goes
## in; the dunker's body, the ball and the bending rim never pass through
## each other.  Close to a shooter in their windup (or a dunker in their
## gather, or a shot just released) Block jumps you at them: in the window
## and close enough the host swats the ball away (sideways and down, the
## physics takes over), otherwise it is a whiff; a guest's block is judged
## by when the guest saw it (within a grace window), under real latency.
var t


static func _yaw_to(from: Vector2, to: Vector2) -> float:
	var d := to - from
	return atan2(-d.x, -d.y)


static func _rim() -> Vector2:
	var rc := HubBall.rim_center()
	return Vector2(rc.x, rc.z)


## A spot `d` from the middle of the rim, `a` radians round from the way
## the hoop faces.
static func _spot(d: float, a: float = 0.0) -> Vector2:
	return _rim() + HubBall.HOOP_DIR.rotated(a) * d


func _rig(n: int, latency: float = 20.0, jitter: float = 0.0) -> NetRig:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(latency, jitter, 0.0, n)
	await rig.wait_until(func() -> bool:
		for c in rig.clients:
			if c.local_slot < 0:
				return false
		return rig.host.human_count() == rig.clients.size() + 1 and rig.host.social.ball.spawned, 400)
	await rig.frames(8)
	return rig


func _done(rig: NetRig) -> void:
	rig.teardown()
	await t.get_tree().process_frame
	await t.get_tree().process_frame


func _walk_to(rig: NetRig, s: NetSession, p: Vector2, yaw: float = 0.0) -> void:
	s.social.hub.set_local(HubSync.MODE_MARK, p, yaw, 0.0)
	await rig.frames(4)
	s.social.hub.set_local(HubSync.MODE_WALK, p, yaw, 0.0)
	await rig.frames(14)


## Puts the ball at `s`'s feet and has them pick it up.
func _give(rig: NetRig, s: NetSession, at: Vector2, yaw: float) -> bool:
	var hb := rig.host.social.ball
	await _walk_to(rig, s, at, yaw)
	hb.sim.place(Vector3(at.x + 0.35, HubBall.R, at.y))
	hb._dirty = true
	await rig.frames(12)
	s.social.ball.request(BallSync.ACT_PICKUP)
	await rig.wait_until(func() -> bool: return s.social.ball.holder == s.local_slot, 90)
	await rig.frames(6)
	return hb.holder == s.local_slot


# ---------------------------------------------------------------------------
# The dunk
# ---------------------------------------------------------------------------
func test_dunk_range() -> void:
	var rim := _rim()
	for d in [0.3, 0.8, 1.2, 1.45]:
		for a in [-1.0, 0.0, 0.7]:
			var at := _spot(d, a)
			t.check(BallSync.dunk_ok(at, _yaw_to(at, rim)), "%.2f m out, %.1f rad round, facing the rim: a dunk" % [d, a])
	var far := _spot(1.7)
	t.check(not BallSync.dunk_ok(far, _yaw_to(far, rim)), "1.7 m out: too far (a shot)")
	var close := _spot(1.2)
	t.check(not BallSync.dunk_ok(close, _yaw_to(close, rim) + PI), "facing away from the rim: no dunk")
	t.check(not BallSync.dunk_ok(close, _yaw_to(close, rim) + 1.5), "facing well off to the side: no dunk")
	t.check(BallSync.dunk_ok(close, _yaw_to(close, rim) + 0.9), "roughly facing it (50 degrees off): a dunk")
	var behind := rim - HubBall.HOOP_DIR * 0.9
	t.check(not BallSync.dunk_ok(behind, _yaw_to(behind, rim)), "from behind the backboard: no dunk")
	# the host's slack: a guest's pose is a little old
	var edge := _spot(BallSync.DUNK_RANGE + 0.2)
	t.check(not BallSync.dunk_ok(edge, _yaw_to(edge, rim)) and BallSync.dunk_ok(edge, _yaw_to(edge, rim), BallSync.DUNK_SLACK), "the host allows a little more than the button")
	# the path: in to the slam, back a little hanging, out a little landing,
	# always on open floor in front of the hoop
	var ok := 0
	for a in [-1.2, -0.9, -0.5, 0.0, 0.3, 0.6, 0.9, 1.25]:
		for d in [0.25, 1.0, 1.45]:
			var from := _spot(d, a)
			if not HubRoom.is_free(from) or not BallSync.dunk_ok(from, _yaw_to(from, rim)):
				continue
			ok += 1
			var u := BallSync.dunk_dir(from)
			var at_slam := (BallSync.dunk_body(from, BallSync.WINDUP_DUNK) - rim).dot(u)
			t.near(at_slam, BallSync.DUNK_SLAM_D, 0.02, "the slam from %.2f m, %.1f rad round: %.2f m from the rim" % [d, a, at_slam])
			var prev := from
			var worst := 0.0
			for i in 121:
				var tt := float(i) / 120.0 * (BallSync.WINDUP_DUNK + BallSync.DUNK_AFTER_S)
				var p := BallSync.dunk_body(from, tt)
				worst = maxf(worst, p.distance_to(prev))
				prev = p
				if not HubRoom.is_free(p):
					t.check(false, "the dunk path is on open floor (%s at %.2f s)" % [p, tt])
					break
			t.check(worst < 0.06, "the path is smooth (%.3f m a step of 1/60 s)" % worst)
			var end := BallSync.dunk_body(from, BallSync.WINDUP_DUNK + BallSync.DUNK_AFTER_S)
			t.near((end - rim).dot(u), BallSync.DUNK_LAND_D, 0.02, "lands %.2f m out" % (end - rim).dot(u))
	t.check(ok >= 12, "most of the floor in front of the hoop can dunk (%d of 24 spots)" % ok)
	# (the beanbag beside the hoop: no dunking through it)
	var bb := Vector2(4.0, 1.1)
	var side_on := rim + (bb - rim).normalized().rotated(0.45) * 1.2
	if HubRoom.is_free(side_on) and BallSync.dunk_ok(side_on, _yaw_to(side_on, rim)):
		var u2 := BallSync.dunk_dir(side_on)
		for k in 8:
			t.check(HubRoom.is_free(rim + u2 * lerpf(BallSync.DUNK_HANG_D, BallSync.DUNK_TAKEOFF_D, float(k) / 7.0)), "beside the beanbag: the way in curves round it")


func test_the_slam_always_goes_in_clean() -> void:
	var made := 0
	var clean := 0
	var n := 0
	for a in [-1.31, -0.9, -0.4, 0.0, 0.5, 1.0, 1.31]:
		for d in [0.2, 0.9, 1.5]:
			var from := _spot(d, a)
			var b := HubBall.new()
			var u := BallSync.dunk_dir(from)
			b.launch(BallSync.dunk_release(from), Vector3(-u.x * BallSync.DUNK_REL_V.x, BallSync.DUNK_REL_V.y, -u.y * BallSync.DUNK_REL_V.x))
			n += 1
			var got := false
			for i in 90:
				b.step(1.0 / 60.0)
				for e in b.events:
					if e.has("make"):
						got = true
						if bool(e["swish"]):
							clean += 1
				if got:
					break
			if got:
				made += 1
			else:
				t.check(false, "a slam from %.1f m, %.1f rad round goes in" % [d, a])
	t.eq(made, n, "every slam goes in (%d of %d)" % [made, n])
	t.eq(clean, n, "without touching the rim (%d of %d)" % [clean, n])


func test_dunk_is_synced_host_to_guest_under_latency() -> void:
	# 60 ms each way with 15 ms of jitter; the dunker and a friend watching
	var rig: NetRig = await _rig(2, 60.0, 15.0)
	var c0: NetSession = rig.clients[0]
	var c1: NetSession = rig.clients[1]
	var hb := rig.host.social.ball
	var from := _spot(1.25, 0.3)
	var face := _yaw_to(from, _rim())
	t.check(await _give(rig, c0, from, face), "the guest picks the ball up")
	var made := {"host": 0, "c0": 0, "c1": 0}
	hb.made.connect(func(_s: int, _w: bool) -> void: made["host"] += 1)
	c0.social.ball.made.connect(func(_s: int, _w: bool) -> void: made["c0"] += 1)
	c1.social.ball.made.connect(func(_s: int, _w: bool) -> void: made["c1"] += 1)
	hb.force_make = 0   # (a dunk doesn't care: luck is for shots)
	c0.social.ball.request(BallSync.ACT_SHOOT, BallSync.ARG_DUNK, face)
	await rig.wait_until(func() -> bool: return hb.phase == BallSync.Phase.SHOT, 60)
	t.check(hb.dunk, "the host makes it a dunk")
	t.check(hb.dunk_from.distance_to(from) < 0.05, "from where the dunker stands")
	await rig.wait_until(func() -> bool: return c1.social.ball.phase == BallSync.Phase.SHOT and c0.social.ball.phase == BallSync.Phase.SHOT, 60)
	for c in [c0, c1]:
		var cb: BallSync = c.social.ball
		t.check(cb.dunk, "a guest knows it is a dunk")
		t.check(cb.dunk_from.distance_to(hb.dunk_from) < 0.01, "and where it started (%s / %s)" % [cb.dunk_from, hb.dunk_from])
		t.eq(cb.dunker(), c0.local_slot, "and who is dunking")
	# every device lays out the same path: the guests one way's latency behind
	var worst := 0.0
	var phase_lag := 0.0
	while hb.phase == BallSync.Phase.SHOT:
		await rig.frames(1)
		var hp := BallSync.dunk_body(hb.dunk_from, hb.dunk_clock())
		var gb: BallSync = c1.social.ball
		if gb.dunker() >= 0:
			worst = maxf(worst, BallSync.dunk_body(gb.dunk_from, gb.dunk_clock()).distance_to(hp))
			phase_lag = maxf(phase_lag, hb.dunk_clock() - gb.dunk_clock())
	t.check(worst < 0.35, "a guest draws the dunker where the host has them, latency behind (worst %.2f m)" % worst)
	t.check(phase_lag < 0.12, "its clock a one-way latency behind (%.3f s)" % phase_lag)
	# the slam
	t.check(hb.released_dunk and not hb.released_shot, "released as a dunk")
	await rig.wait_until(func() -> bool: return made["c1"] > 0 and made["c0"] > 0, 120)
	t.eq(made["host"], 1, "it goes in (host)")
	t.eq(made["c0"], 1, "the dunker's device celebrates")
	t.eq(made["c1"], 1, "and the friend's")
	t.check(c1.social.ball.released_dunk and c0.social.ball.released_dunk, "every device knows it was a dunk (the hang, the clang)")
	t.eq(c1.social.ball.dunker(), c0.local_slot, "the hang is drawn after the release too")
	await rig.frames(int(BallSync.DUNK_AFTER_S * 60.0) + 10)
	t.eq(c1.social.ball.dunker(), -1, "and it ends")
	await rig.frames(300)
	t.check(HubBall.reachable(hb.sim.pos), "the ball settles where it can be picked up (%s)" % hb.sim.pos)
	await _done(rig)


func test_a_dunk_asked_for_out_of_range_is_a_shot() -> void:
	# (and a host that doesn't know dunks reads ARG_DUNK as a shot's arg)
	var rig: NetRig = await _rig(1)
	var c0: NetSession = rig.clients[0]
	var hb := rig.host.social.ball
	var from := _spot(2.6, 0.0)
	var face := _yaw_to(from, _rim())
	t.check(await _give(rig, c0, from, face), "picked up")
	c0.social.ball.request(BallSync.ACT_SHOOT, BallSync.ARG_DUNK, face)
	await rig.wait_until(func() -> bool: return hb.phase == BallSync.Phase.SHOT, 60)
	t.check(not hb.dunk, "out of range: the host makes it a shot")
	await _done(rig)


# ---------------------------------------------------------------------------
# The block
# ---------------------------------------------------------------------------
## Gives the ball to `shooter` facing the hoop at `at`, `blocker` standing
## `gap` away (between them and the hoop, a little to the side).
func _setup_block(rig: NetRig, shooter: NetSession, blocker: NetSession, at: Vector2, gap: float) -> Vector2:
	var face := _yaw_to(at, _rim())
	await _give(rig, shooter, at, face)
	var to := (_rim() - at).normalized()
	var bp := at + to.rotated(0.35) * gap
	await _walk_to(rig, blocker, bp, _yaw_to(bp, at))
	return bp


func test_block_in_the_window_swats_the_shot_away() -> void:
	var rig: NetRig = await _rig(2)
	var c0: NetSession = rig.clients[0]
	var c1: NetSession = rig.clients[1]
	var hb := rig.host.social.ball
	var at := _spot(2.4, 0.2)
	var bp: Vector2 = await _setup_block(rig, c0, c1, at, 1.3)
	var seen := {"host": 0, "c0": 0, "c1": 0, "jumps": 0}
	hb.blocked.connect(func(_b: int, _s: int) -> void: seen["host"] += 1)
	c0.social.ball.blocked.connect(func(_b: int, _s: int) -> void: seen["c0"] += 1)
	c1.social.ball.blocked.connect(func(_b: int, _s: int) -> void: seen["c1"] += 1)
	c0.social.ball.jumped.connect(func(_s: int) -> void: seen["jumps"] += 1)
	var made := [0]
	hb.made.connect(func(_s: int, _w: bool) -> void: made[0] += 1)
	hb.force_make = 1
	c0.social.ball.request(BallSync.ACT_SHOOT, -1, _yaw_to(at, _rim()))
	var cb: BallSync = c1.social.ball
	await rig.wait_until(func() -> bool: return cb.phase == BallSync.Phase.SHOT and cb.phase_t > 0.2, 60)
	# the shooter can't block their own shot; the blocker is offered Block
	t.eq(c0.social.ball.block_target(at), -1, "nobody blocks their own shot")
	t.eq(cb.block_target(bp), c0.local_slot, "Block is offered %.1f m from the shooter" % bp.distance_to(at))
	t.eq(cb.block_target(at + (bp - at).normalized() * 2.4), -1, "but not from 2.4 m away")
	cb.request_block(bp, _yaw_to(bp, at))
	t.check(not cb.jump_of(c1.local_slot).is_empty(), "the blocker jumps at once on their own device")
	await rig.wait_until(func() -> bool: return hb.stat_blocks > 0, 60)
	var called := hb._clock
	await rig.wait_until(func() -> bool: return seen["c1"] > 0, 60)
	t.eq(hb.stat_blocks, 1, "the host calls it a block")
	t.check(hb._clock - called > 0.05, "the ball leaves as the blocker's hand comes up, not before (%.2f s later)" % (hb._clock - called))
	t.eq(seen["host"], 1, "(host)")
	t.check(hb.phase == BallSync.Phase.FREE and hb.released_blocked and hb.holder == -1, "the ball is loose, swatted")
	var away := Vector2(hb.sim.vel.x, hb.sim.vel.z)
	var from_blocker := (Vector2(hb.sim.pos.x, hb.sim.pos.z) - bp).normalized()
	t.check(away.normalized().dot(from_blocker) > 0.2, "away from the blocker (%.2f)" % away.normalized().dot(from_blocker))
	t.check(hb.sim.vel.y < 0.6 and away.length() > 2.0, "sideways and down, hard (%s)" % hb.sim.vel)
	await rig.wait_until(func() -> bool: return seen["c0"] > 0, 30)
	t.eq(seen["c0"], 1, "the shooter's device sees the block")
	t.eq(seen["jumps"], 1, "and the blocker's jump")
	t.check(not c0.social.ball.released_shot, "no follow-through for a blocked shot")
	await rig.frames(240)
	t.eq(made[0], 0, "no basket")
	t.check(HubBall.reachable(hb.sim.pos), "the ball ends up somewhere it can be picked up (%s)" % hb.sim.pos)
	# a cooldown: the blocker can't jump again at once
	t.check(not cb.block_ready() or cb._clock - cb._my_block_t >= BallSync.BLOCK_COOL, "a short cooldown")
	await _done(rig)


func test_a_block_outside_the_window_is_a_whiff() -> void:
	var rig: NetRig = await _rig(2)
	var c0: NetSession = rig.clients[0]
	var c1: NetSession = rig.clients[1]
	var hb := rig.host.social.ball
	var at := _spot(2.4, 0.2)
	var bp: Vector2 = await _setup_block(rig, c0, c1, at, 1.3)
	var made := [0]
	hb.made.connect(func(_s: int, _w: bool) -> void: made[0] += 1)
	hb.force_make = 1
	c0.social.ball.request(BallSync.ACT_SHOOT, -1, _yaw_to(at, _rim()))
	var cb: BallSync = c1.social.ball
	# too late: the shot is well on its way
	await rig.wait_until(func() -> bool: return cb.phase == BallSync.Phase.FREE and cb.phase_t > BallSync.BLOCK_FLIGHT_S + 0.1, 120)
	t.eq(cb.block_target(bp), -1, "Block isn't offered once the shot is away")
	var jumps0 := hb.jump_seq
	cb.request_block(bp, _yaw_to(bp, at))
	t.check(not cb.jump_of(c1.local_slot).is_empty(), "pressed anyway (it was up a moment ago): the runner jumps")
	await rig.wait_until(func() -> bool: return hb.jump_seq != jumps0, 30)
	t.eq(hb.stat_whiffs, 1, "a whiff")
	t.eq(hb.stat_blocks, 0, "no block")
	await rig.wait_until(func() -> bool: return made[0] > 0, 120)
	t.eq(made[0], 1, "the shot goes on in")
	# too far: during a windup, from across the room
	await rig.frames(240)
	await _give(rig, c0, at, _yaw_to(at, _rim()))
	var far := at + Vector2(-2.6, 0.9)
	await _walk_to(rig, c1, far, _yaw_to(far, at))
	await rig.frames(70)   # (past the cooldown)
	c0.social.ball.request(BallSync.ACT_SHOOT, -1, _yaw_to(at, _rim()))
	await rig.wait_until(func() -> bool: return cb.phase == BallSync.Phase.SHOT and cb.phase_t > 0.15, 60)
	t.eq(cb.block_target(far), -1, "no Block from %.1f m away" % far.distance_to(at))
	cb.request_block(far, _yaw_to(far, at))
	await rig.frames(20)
	t.eq(hb.stat_blocks, 0, "too far: no block")
	t.eq(hb.stat_whiffs, 2, "another whiff")
	# the shooter asking to block their own shot (a forged request): no
	var whiffs := hb.stat_whiffs
	var denied := hb.stat_denied
	t.eq(hb.holder, c0.local_slot, "(still winding up)")
	c0.social.ball.request(BallSync.ACT_BLOCK, c0.local_slot, 0.0, 0.3)
	await rig.frames(12)
	t.check(hb.stat_blocks == 0 and hb.stat_denied == denied + 1 and hb.stat_whiffs == whiffs, "nobody blocks their own shot (refused)")
	await _done(rig)


func test_a_guest_blocks_under_latency() -> void:
	# 60 ms each way, 20 ms jitter: the blocker saw the windup late and the
	# request takes as long again; the host judges it by when they saw it
	var rig: NetRig = await _rig(2, 60.0, 20.0)
	var c0: NetSession = rig.clients[0]
	var c1: NetSession = rig.clients[1]
	var hb := rig.host.social.ball
	var at := _spot(2.4, -0.2)
	var bp: Vector2 = await _setup_block(rig, c0, c1, at, 1.2)
	var cb: BallSync = c1.social.ball
	hb.force_make = 1
	c0.social.ball.request(BallSync.ACT_SHOOT, -1, _yaw_to(at, _rim()))
	# late in the windup as the blocker sees it: by the time it reaches the
	# host the ball is in the air
	await rig.wait_until(func() -> bool: return cb.phase == BallSync.Phase.SHOT and cb.phase_t >= BallSync.WINDUP_SHOT - 0.05, 90)
	var host_then := hb.shot_clock()
	cb.request_block(bp, _yaw_to(bp, at))
	var claim := cb.shot_clock()
	await rig.wait_until(func() -> bool: return hb.stat_blocks + hb.stat_whiffs > 0, 60)
	t.check(hb.shot_clock() < 0.0 or hb.phase == BallSync.Phase.FREE, "the host had already let the shot go")
	t.eq(hb.stat_blocks, 1, "a block: the guest pressed in time (at %.2f s of their windup; the host was at %.2f s)" % [claim, host_then])
	await rig.wait_until(func() -> bool: return hb.released_blocked, 30)
	t.check(hb.released_blocked, "the ball is swatted out of the air")
	await rig.wait_until(func() -> bool: return cb.released_blocked, 30)
	t.check(cb.released_blocked, "and the blocker's device sees it")
	await rig.frames(70)
	# a forged claim: "I pressed long ago" isn't believed past the grace window
	await _give(rig, c0, at, _yaw_to(at, _rim()))
	await _walk_to(rig, c1, bp, _yaw_to(bp, at))
	await rig.frames(70)
	var blocks := hb.stat_blocks
	c0.social.ball.request(BallSync.ACT_SHOOT, -1, _yaw_to(at, _rim()))
	await rig.wait_until(func() -> bool: return hb.phase == BallSync.Phase.FREE and hb.phase_t > 0.45, 120)
	cb._my_block_t = -10.0
	cb.request(BallSync.ACT_BLOCK, c0.local_slot, 0.0, 0.3)
	await rig.frames(20)
	t.eq(hb.stat_blocks, blocks, "a claim older than the grace window is judged now: too late")
	await _done(rig)


func test_block_a_dunk_in_the_gather_not_after_takeoff() -> void:
	var rig: NetRig = await _rig(2)
	var c0: NetSession = rig.clients[0]
	var c1: NetSession = rig.clients[1]
	var hb := rig.host.social.ball
	var cb: BallSync = c1.social.ball
	var from := _spot(1.3, 0.0)
	var face := _yaw_to(from, _rim())
	var bp := _spot(1.0, 0.9)
	await _give(rig, c0, from, face)
	await _walk_to(rig, c1, bp, _yaw_to(bp, from))
	c0.social.ball.request(BallSync.ACT_SHOOT, BallSync.ARG_DUNK, face)
	await rig.wait_until(func() -> bool: return cb.phase == BallSync.Phase.SHOT and cb.dunk and cb.phase_t > 0.12, 60)
	t.eq(cb.block_target(bp), c0.local_slot, "Block is offered against a dunker in their gather")
	cb.request_block(bp, _yaw_to(bp, from))
	await rig.wait_until(func() -> bool: return hb.stat_blocks + hb.stat_whiffs > 0, 60)
	t.eq(hb.stat_blocks, 1, "the dunk is blocked")
	await rig.wait_until(func() -> bool: return hb.released_blocked, 30)
	t.check(not hb.released_dunk and hb.released_blocked, "no slam")
	await rig.frames(240)
	# after takeoff it's too late
	await _give(rig, c0, from, face)
	await _walk_to(rig, c1, bp, _yaw_to(bp, from))
	await rig.frames(70)
	var made := [0]
	hb.made.connect(func(_s: int, _w: bool) -> void: made[0] += 1)
	c0.social.ball.request(BallSync.ACT_SHOOT, BallSync.ARG_DUNK, face)
	await rig.wait_until(func() -> bool: return cb.phase == BallSync.Phase.SHOT and cb.dunk and cb.phase_t > BallSync.DUNK_BLOCK_T + 0.08, 90)
	t.eq(cb.block_target(bp), -1, "no Block once they're in the air")
	cb.request_block(bp, _yaw_to(bp, from))
	await rig.wait_until(func() -> bool: return made[0] > 0, 120)
	t.eq(hb.stat_blocks, 1, "too late: a whiff")
	t.eq(made[0], 1, "the dunk goes in")
	await _done(rig)


# ---------------------------------------------------------------------------
# Older builds (20+) still play together
# ---------------------------------------------------------------------------
static func _state(seq: int, ph: int, holder: int, flags: int, pos: Vector3, extra: bool) -> StreamPeerBuffer:
	var b := StreamPeerBuffer.new()
	b.big_endian = false
	b.put_u16(seq)
	b.put_u8(ph)
	b.put_8(holder)
	b.put_8(-1)
	b.put_8(holder)
	b.put_u8(0)
	b.put_u8(flags)
	for c in [pos.x, pos.y, pos.z]:
		b.put_16(int(round(c * BallSync.POS_Q)))
	for i in 3:
		b.put_16(0)
	if extra:
		b.put_8(-1)
		b.put_u8(0)
		b.put_u8(0)
		b.put_u8(0)
		for i in 4:
			b.put_16(0)
	b.seek(0)
	return b


func test_older_builds_still_play_together() -> void:
	var rig: NetRig = await _rig(1)
	var c0: NetSession = rig.clients[0]
	var hb := rig.host.social.ball
	var cb: BallSync = c0.social.ball
	t.check(BallSync.F_DUNK > BallSync.F_SWISH and BallSync.F_BLOCKED > BallSync.F_SWISH, "the new flags are bits older builds never read")
	# an old host's 20-byte state, read by a build 33 guest
	var old := _state(30000, BallSync.Phase.HELD, rig.host.local_slot, 0, Vector3(1.0, 0.45, 0.5), false)
	t.eq(old.get_size(), 20, "(an old state is 20 bytes)")
	cb.client_packet(old)
	t.eq(cb.holder, rig.host.local_slot, "a build 33 guest reads an old host's state")
	t.check(not cb.dunk and cb.dunker() == -1, "no dunk from an old host")
	# a build 33 state: the old 20 bytes as before (what a build 24-32 guest
	# reads: a plain SHOT, so it draws a jump shot), the jump appended
	var neu := _state(30001, BallSync.Phase.SHOT, rig.host.local_slot, BallSync.F_DUNK, Vector3(3.6, 0.45, -0.1), true)
	t.eq(neu.get_size(), 32, "(a build 33 state: 20 bytes as before, 12 appended)")
	cb.client_packet(neu)
	t.check(cb.dunk and cb.dunk_from.distance_to(Vector2(3.6, -0.1)) < 0.01, "the dunk is read from the flags and the position")
	await rig.frames(40)
	# an old guest's 2-byte request (no facing, no claim) on a build 33 host
	var at := _spot(2.6)
	await _walk_to(rig, c0, at)
	hb.sim.place(Vector3(at.x + 0.3, HubBall.R, at.y))
	hb._dirty = true
	await rig.frames(12)
	var req := Protocol.buf_for(SocialProto.BALL_REQ)
	req.put_u8(BallSync.ACT_PICKUP)
	req.put_8(-1)
	c0.transport.send(c0.host_peer, req.data_array, true)
	await rig.wait_until(func() -> bool: return hb.holder == c0.local_slot, 30)
	t.eq(hb.holder, c0.local_slot, "an old guest's pick-up works")
	await rig.frames(12)
	var shoot := Protocol.buf_for(SocialProto.BALL_REQ)
	shoot.put_u8(BallSync.ACT_SHOOT)
	shoot.put_8(-1)
	c0.transport.send(c0.host_peer, shoot.data_array, true)
	await rig.wait_until(func() -> bool: return hb.phase == BallSync.Phase.SHOT, 30)
	t.check(hb.phase == BallSync.Phase.SHOT and not hb.dunk, "and its shot is a shot")
	# an old guest's block can't be asked for: the act is unknown to it, and
	# a build 33 guest's block on an old host is refused (a whiff)
	await _done(rig)
