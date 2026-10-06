extends RefCounted
## V4 pursuit scenarios (deterministic, real sim + physics): a human-like
## Night Watch - full stick, camera turned toward the runner with a 0.25 s
## lag, Tag pressed at a guessed "close" distance or when the tag-ready cue
## shows - against scripted runners.  Each scenario prints a PURSUIT line
## (closure, attempts, hits, time, escapes); docs/V4_NOTES.md keeps the
## before/after table.  Assertions hold the tuned behaviour:
##   the Night Watch closes on a running runner in the open; a runner's
##   finite tools (Turbo, a dive) are still real bursts; protected /
##   splashing / finished / captured runners can't be tagged; a cart exit
##   has its tag lockout.  Pass 9: both roles hold one steady full speed
##   (runner 6.0, Night Watch 6.6 m/s; V4-Pass 8: a 5.0 m/s jog with a
##   2.5 s sprint meter to 7.4), so the open-ground closure is 0.6 m/s.
var t
const R := TC.Role.RUNNER
const P := TC.Role.PATROL

static var _lane: Array = []   # [start, dir2] with a long free straight


func _free(sim: MatchSim, a: Vector3, d: Vector2, length: float) -> bool:
	var dir := Vector3(d.x, 0, d.y)
	var s := 0.0
	while s < length:
		var p0 := a + dir * s
		var p1 := a + dir * minf(s + 6.0, length)
		for h in [0.4, 1.2]:
			if not sim.has_los(p0 + Vector3(0, h, 0), p1 + Vector3(0, h, 0)):
				return false
		for side in [-1.2, 1.2]:
			var off: Vector3 = Vector3(-d.y, 0, d.x) * float(side)
			if not sim.has_los(p0 + off + Vector3(0, 0.6, 0), p1 + off + Vector3(0, 0.6, 0)):
				return false
		if CampusBuilder.water_at(sim.layout, Vector2(p1.x, p1.z)) >= 0 or absf(CampusBuilder.grid_y(sim.layout, p1.x, p1.z)) > 0.05:
			return false
		# inside the play area, clear of its edge (the rebuilt campus has open
		# ground beyond the boundary that a lane must not use)
		var q := Vector2(p1.x, p1.z)
		if not sim.layout.in_play(q) or CampusData.dist_to_edge(q, sim.layout.play_boundary) < 4.0:
			return false
		s += 6.0
	return true


## A long open straight on the campus (found once, then reused).
func _open_lane(sim: MatchSim) -> Array:
	if not _lane.is_empty():
		return _lane
	var b := CampusLayout.BOUNDS
	var best: Array = []
	for x in range(int(b.position.x) + 20, int(b.end.x) - 20, 10):
		for z in range(int(b.position.y) + 20, int(b.end.y) - 20, 10):
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				var a := Vector3(x, 0.05, z)
				if _free(sim, a - Vector3(d.x, 0, d.y) * 14.0, d, 125.0):
					best = [a, d]
					break
			if not best.is_empty():
				break
		if not best.is_empty():
			break
	_lane = best
	return best


## Human-like Night Watch input toward `target` for one tick.
class Chaser:
	var cam_yaw := 0.0
	var lag_s := 0.25
	var press_at := 2.6        # "looks close" distance; < 0: press on the cue only
	var use_cue := false
	var attempts := 0
	var _since := 99.0

	func cmd_for(sim: MatchSim, me: SimPlayer, target: SimPlayer, dt: float) -> InputCmd:
		var c := InputCmd.new()
		var rel := target.pos() - me.pos()
		var want := atan2(-rel.x, -rel.z)
		cam_yaw = lerp_angle(cam_yaw, want, 1.0 - exp(-dt / lag_s))
		c.cam_yaw = cam_yaw
		c.move = Vector2(-sin(cam_yaw), -cos(cam_yaw))
		var d := Vector2(rel.x, rel.z).length()
		var ready := me.tag_ready if use_cue else d <= press_at
		_since += dt
		# a person presses once and waits to see what happens (>= 0.4 s apart)
		if ready and _since >= 0.4 and me.tag_phase == SimPlayer.TagPhase.NONE and me.tag_cd <= 0.0 and me.state == TC.PState.ACTIVE and me.tag_lockout <= 0.0:
			c.pressed = TC.BTN_TAG
			attempts += 1
			_since = 0.0
		return c


## Runs one pursuit; `runner_fn(sim, runner, tick) -> InputCmd`.
func _pursue(label: String, gap: float, runner_fn: Callable, chaser: Chaser, max_s: float = 20.0, delay_ticks: int = 0, jitter: int = 0, hitch_at: int = -1, hitch_len: int = 0) -> Dictionary:
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2], [], 900)
	await h.release_patrol()
	var lane := _open_lane(h.sim)
	var a: Vector3 = lane[0]
	var d: Vector2 = lane[1]
	var yaw := atan2(-d.x, -d.y)
	h.place(0, a, yaw)
	h.place(1, a - Vector3(d.x, 0, d.y) * gap, yaw)
	chaser.cam_yaw = yaw
	var sim := h.sim
	var runner := sim.player(0)
	var cop := sim.player(1)
	var t0 := sim.tick
	var queue: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var gap0 := gap
	var gap3 := -1.0
	var caught_s := -1.0
	var hits := 0
	var last_cmd := InputCmd.new()
	for i in int(max_s * 60.0):
		var rc: InputCmd = runner_fn.call(sim, runner, i)
		var cc := chaser.cmd_for(sim, cop, runner, 1.0 / 60.0)
		var send := cc
		if delay_ticks > 0:
			# online: the host sees the chaser's input late (and jittery)
			queue.append({"due": i + delay_ticks + rng.randi_range(-jitter, jitter), "cmd": cc})
			send = null
			for q in queue.duplicate():
				if int(q["due"]) <= i:
					send = q["cmd"]
					queue.erase(q)
		if hitch_at >= 0 and i >= hitch_at and i < hitch_at + hitch_len:
			send = null       # a frame hitch: nothing new arrives
		if send == null:
			send = last_cmd.repeat_without_edges(0)
		last_cmd = send
		h.inputs = {0: rc, 1: send}
		await h.step()
		if i == 180:
			gap3 = runner.pos2().distance_to(cop.pos2())
		if runner.state == TC.PState.CAPTURED:
			hits += 1
			caught_s = float(sim.tick - t0) / 60.0
			break
	var closure := (gap0 - gap3) / 3.0 if gap3 >= 0.0 else -1.0
	var res := {"label": label, "caught_s": snappedf(caught_s, 0.1), "attempts": chaser.attempts, "hits": hits,
		"closure_mps": snappedf(closure, 0.01), "escaped": caught_s < 0.0}
	print("PURSUIT %-34s caught %5.1f s  attempts %d  hits %d  closure %.2f m/s%s" % [label, caught_s, chaser.attempts, hits, closure, "  ESCAPED" if caught_s < 0.0 else ""])
	h.free_sim()
	return res


## Full stick toward `dir` (Pass 9: the steady 6.0 m/s; was a 5.0 m/s jog).
static func run(dir: Vector2) -> Callable:
	return func(_sim: MatchSim, _r: SimPlayer, _i: int) -> InputCmd:
		var c := InputCmd.new()
		c.move = dir
		c.cam_yaw = atan2(-dir.x, -dir.y)
		return c


## Runs, and jumps then dives every 3 s (a deliberate dive each time).
static func dive_every(dir: Vector2, period_s: float) -> Callable:
	return func(_sim: MatchSim, _r: SimPlayer, i: int) -> InputCmd:
		var c := InputCmd.new()
		c.move = dir
		c.cam_yaw = atan2(-dir.x, -dir.y)
		var k := int(period_s * 60.0)
		if i % k == 0 or i % k == 12:
			c.pressed = TC.BTN_JUMP
		return c


## Weaves +-35 degrees off the lane every 1.2 s.
static func weave(dir: Vector2) -> Callable:
	return func(_sim: MatchSim, _r: SimPlayer, i: int) -> InputCmd:
		var c := InputCmd.new()
		var ang := deg_to_rad(35.0) * (1.0 if (i / 72) % 2 == 0 else -1.0)
		c.move = dir.rotated(ang)
		c.cam_yaw = atan2(-c.move.x, -c.move.y)
		return c


func _dir() -> Vector2:
	return _lane[1] if not _lane.is_empty() else Vector2(1, 0)


func test_pursuit_report_and_targets() -> void:
	# warm the lane search with a throwaway sim
	var h0 := SimHarness.new(t)
	h0.make([R, P])
	t.check(not _open_lane(h0.sim).is_empty(), "found an open straight for the pursuit scenarios")
	h0.free_sim()
	var d := _dir()
	var rows: Array = []
	for gap in [4.0, 8.0, 12.0]:
		rows.append(await _pursue("run %d m, presses at 2.6 m" % int(gap), gap, run(d), Chaser.new(), 25.0))
	var cue := Chaser.new()
	cue.use_cue = true
	rows.append(await _pursue("run 8 m, presses on the cue", 8.0, run(d), cue))
	rows.append(await _pursue("run + dive every 3 s 8 m", 8.0, dive_every(d, 3.0), Chaser.new(), 25.0))
	var close := Chaser.new()
	close.press_at = 9.0      # presses at once
	rows.append(await _pursue("close rear tag, both running 2.2 m", 2.2, run(d), close, 3.0))
	rows.append(await _pursue("weaving runner 6 m", 6.0, weave(d), Chaser.new()))
	rows.append(await _pursue("run 8 m, 100 ms input delay +-33 ms", 8.0, run(d), Chaser.new(), 20.0, 6, 2))
	rows.append(await _pursue("run 8 m, 250 ms hitch at 2 s", 8.0, run(d), Chaser.new(), 20.0, 0, 0, 120, 15))
	# --- targets (V4 tuning)
	var by := {}
	for r in rows:
		by[r["label"]] = r
	# Pass 9: 8 m at the 0.6 m/s closure is 13.3 s to zero gap; reach and the
	# lunge make the tag land sooner (V4-Pass 8 target vs a 5.0 m/s jog: 9 s)
	var closing := Rules.cfg.patrol_speed - Rules.cfg.runner_speed
	t.check(not by["run 8 m, presses at 2.6 m"]["escaped"] and float(by["run 8 m, presses at 2.6 m"]["caught_s"]) < 8.0 / closing,
		"the Night Watch runs down a runner at full speed from 8 m in the open (%.1f s, closure alone %.1f s)" % [float(by["run 8 m, presses at 2.6 m"]["caught_s"]), 8.0 / closing])
	t.check(float(by["run 8 m, presses at 2.6 m"]["closure_mps"]) >= closing - 0.1, "and steadily closes (%.2f m/s)" % float(by["run 8 m, presses at 2.6 m"]["closure_mps"]))
	t.check(not by["run 12 m, presses at 2.6 m"]["escaped"], "a long straight chase ends (12 m)")
	t.check(not by["run 8 m, presses on the cue"]["escaped"] and int(by["run 8 m, presses on the cue"]["attempts"]) <= 2,
		"pressing when Tag lights up catches with few presses (%d)" % int(by["run 8 m, presses on the cue"]["attempts"]))
	t.check(int(by["close rear tag, both running 2.2 m"]["hits"]) == 1, "a close rear tag while both run lands")
	t.check(not by["weaving runner 6 m"]["escaped"], "a weaving runner is caught in the open")
	t.check(not by["run 8 m, 100 ms input delay +-33 ms"]["escaped"], "online delay does not make the chase hopeless")
	t.check(not by["run 8 m, 250 ms hitch at 2 s"]["escaped"], "a short hitch does not lose the chase")


## Cart interception: the Night Watch starts seated in a cart 13 m behind a
## jogging runner, drives at them, hops out (validated exit, auto-brake) and
## finishes the chase on foot; Tag presses during the exit lockout do nothing.
func test_cart_interception() -> void:
	var h := SimHarness.new(t)
	h.make([R, P])
	await h.release_patrol()
	var lane := _open_lane(h.sim)
	var a: Vector3 = lane[0]
	var d: Vector2 = lane[1]
	var yaw := atan2(-d.x, -d.y)
	var sim := h.sim
	var c: SimCart = sim.carts[0]
	c.yaw = yaw
	# the lane is checked free from 14 m behind its start
	c.body.global_position = a - Vector3(d.x, 0, d.y) * 13.0 + Vector3(0, 0.25, 0)
	c.speed = 0.0
	h.place(1, c.pos() - c.right() * 1.5)
	await h.step()
	h.press(1, TC.BTN_INTERACT)
	await h.step(30)
	t.eq(sim.player(1).state, TC.PState.IN_CART, "seated")
	h.place(0, a + Vector3(d.x, 0, d.y) * 8.0, yaw)    # 21 m ahead of the cart
	var runner := sim.player(0)
	var cop := sim.player(1)
	var chaser := Chaser.new()
	chaser.cam_yaw = yaw
	var t0 := sim.tick
	var exit_s := -1.0
	var caught_s := -1.0
	var lockout_presses := 0
	for i in 60 * 30:   # (Pass 9: 30 s; the runner holds 6.0 m/s, the off-road cart tops out at 6.5)
		h.inputs[0] = run(d).call(sim, runner, i)
		var cmd := InputCmd.new()
		if cop.state == TC.PState.IN_CART:
			var rel := runner.pos() - c.pos()
			var want := atan2(-rel.x, -rel.z)
			cmd.steer = clampf(-wrapf(want - c.yaw, -PI, PI) * 2.0, -1.0, 1.0)
			cmd.drive = 1.0
			cmd.cam_yaw = want
			if Vector2(rel.x, rel.z).length() < 7.0:
				cmd.pressed = TC.BTN_INTERACT
		elif cop.state == TC.PState.ACTIVE:
			if exit_s < 0.0:
				exit_s = float(sim.tick - t0) / 60.0
			if cop.tag_lockout > 0.0:
				cmd = chaser.cmd_for(sim, cop, runner, 1.0 / 60.0)
				cmd.pressed = TC.BTN_TAG       # an eager press inside the lockout
				lockout_presses += 1
				t.check(cop.tag_phase == SimPlayer.TagPhase.NONE, "no tag starts inside the exit lockout")
			else:
				cmd = chaser.cmd_for(sim, cop, runner, 1.0 / 60.0)
		h.inputs[1] = cmd
		await h.step()
		if runner.state == TC.PState.CAPTURED:
			caught_s = float(sim.tick - t0) / 60.0
			break
	print("PURSUIT %-34s caught %5.1f s  out of the cart at %.1f s  (lockout presses ignored: %d)" % ["cart interception 21 m", caught_s, exit_s, lockout_presses])
	t.check(exit_s > 0.0, "the Night Watch hopped out next to the runner")
	t.check(caught_s > 0.0, "and caught them on foot (%.1f s)" % caught_s)
	h.free_sim()


## Pass 9: no sprint; the runner's bursts are finite tools.  Turbo opens the
## gap on a Night Watch running behind for its duration; the Night Watch on
## foot is slower than Turbo and than a dive, and faster than a plain run.
func test_turbo_is_still_an_escape_burst() -> void:
	var h := SimHarness.new(t)
	h.make([R, P])
	await h.release_patrol()
	var lane := _open_lane(h.sim)
	var a: Vector3 = lane[0]
	var d: Vector2 = lane[1]
	h.place(0, a, atan2(-d.x, -d.y))
	h.place(1, a - Vector3(d.x, 0, d.y) * 5.0, atan2(-d.x, -d.y))
	h.cmd(0).move = d
	h.cmd(1).move = d
	await h.step(45)
	var g0 := h.sim.player(0).pos2().distance_to(h.sim.player(1).pos2())
	h.sim.player(0).gadget = TC.Gadget.TURBO
	h.press(0, TC.BTN_GADGET)
	await h.step(120)
	var g1 := h.sim.player(0).pos2().distance_to(h.sim.player(1).pos2())
	print("PURSUIT turbo burst: gap %.1f m -> %.1f m over 2 s" % [g0, g1])
	t.check(g1 > g0 + 1.2, "2 s of Turbo opens the gap (%.1f -> %.1f m)" % [g0, g1])
	var cfg := Rules.cfg
	t.check(minf(cfg.runner_speed * cfg.turbo_multiplier, cfg.turbo_speed_cap) > cfg.patrol_speed, "the Night Watch is not faster than Turbo")
	t.check(cfg.dive_speed > cfg.patrol_speed, "nor than a dive")
	t.check(cfg.patrol_speed > cfg.runner_speed, "but is faster than a plain run")
	h.free_sim()
