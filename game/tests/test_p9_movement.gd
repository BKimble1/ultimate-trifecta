extends RefCounted
## Pass 9 movement contract (real sim + physics on the campus's longest open
## straight; the runner is moved back along the lane before its end, motion
## kept, so a scenario can run for 60 s with nothing in the way):
##   * one continuous analog speed: a held full input keeps the role's full
##     speed (runner 6.0 m/s) for as long as it is held, with no recurring
##     drops; walking and jogging are the same curve at smaller inputs; the
##     retired Sprint button adds nothing;
##   * dive (Pass 8 rules kept): one dive per airborne sequence and a landing
##     recovery that can't be skipped, so no jump/dive pattern beats simply
##     running or sustains the Night Watch's 6.6 m/s;
##   * the Night Watch closes on a runner at full speed in a straight chase.
## Each scenario prints a MOVE line (and the probe JSON when asked) so the
## before/after tables in docs/pass9/movement.md can be regenerated. The file
## also runs on the 1.8 build (P9_MOVE_BASELINE=1: no assertions), where the
## "+ Sprint" scenarios really sprint.
var t
const R := TC.Role.RUNNER
const P := TC.Role.PATROL
const DT := 1.0 / 60.0


func _lane(sim: MatchSim) -> Array:
	var tp = load("res://tests/test_pursuit.gd").new()
	return tp._open_lane(sim)


static func _gv(o: Object, k: String, dflt: Variant) -> Variant:
	return o.get(k) if k in o else dflt


## Runs `fn(sim, runner, tick) -> InputCmd` for `secs` on the open lane and
## returns the per-tick trace and summary. `settle_s`: the start-up excluded
## from the steadiness figures.
func run_scenario(label: String, secs: float, fn: Callable, settle_s: float = 0.5) -> Dictionary:
	var h := SimHarness.new(t)
	h.make([R, P])
	await h.release_patrol()
	var lane := _lane(h.sim)
	var a: Vector3 = lane[0]
	var d: Vector2 = lane[1]
	var dir := Vector3(d.x, 0, d.y)
	var yaw := atan2(-d.x, -d.y)
	h.place(0, h.on_ground(Vector2(a.x, a.z) - d * 10.0), yaw)
	# the Night Watch waits far away
	h.place(1, h.on_ground(Vector2(a.x, a.z) - d * 13.0 + Vector2(-d.y, d.x) * 6.0), yaw)
	var sim := h.sim
	var r := sim.player(0)
	var full := sim.cfg.runner_speed
	var travelled := 0.0
	var last_s := (r.pos() - a).dot(dir)
	var trace: Array = []
	var max_speed := 0.0
	var min_steady := 99.0
	var drops := 0          # ticks after settling more than 3 % under the steady speed while the input is full
	var dives := 0
	var jumps := 0
	var was_diving := false
	var fast_ticks := 0
	var n := int(secs * 60.0)
	for i in n:
		var c: InputCmd = fn.call(sim, r, i)
		h.inputs = {0: c}
		await h.step()
		var s := (r.pos() - a).dot(dir)
		travelled += s - last_s
		if s > 95.0:
			# back along the lane, at the same height over the ground there
			# (the campus has its real grades)
			var gp := r.body.global_position
			var back := gp - dir * 80.0
			back.y = CampusBuilder.grid_y(sim.layout, back.x, back.z) + gp.y - CampusBuilder.grid_y(sim.layout, gp.x, gp.z)
			r.body.global_position = back
			s -= 80.0
		last_s = s
		var sp := Vector2(r.vel.x, r.vel.z).length()
		max_speed = maxf(max_speed, sp)
		var mag := minf(c.move.length(), 1.0)
		var plain := r.on_floor and not r.diving and r.dive_land <= 0.0
		if i * DT >= settle_s and mag >= 0.999 and plain:
			min_steady = minf(min_steady, sp)
			if sp < full * 0.97:
				drops += 1
		if r.diving and not was_diving:
			dives += 1
		was_diving = r.diving
		if r.jumped_this_tick:
			jumps += 1
		var fast := bool(_gv(r, "fast", _gv(r, "sprinting", false)))
		if fast:
			fast_ticks += 1
		trace.append({"t": snappedf(i * DT, 0.001), "input": snappedf(mag, 0.001), "want": snappedf(full * mag, 0.01),
			"speed": snappedf(sp, 0.01), "fast": fast, "meter": snappedf(float(_gv(r, "sprint", -1.0)), 0.001),
			"state": r.state, "diving": r.diving, "dive_land": snappedf(r.dive_land, 0.001), "floor": r.on_floor})
	var avg := travelled / secs
	var res := {"label": label, "secs": secs, "avg_mps": snappedf(avg, 0.01), "max_mps": snappedf(max_speed, 0.01),
		"min_steady_mps": snappedf(min_steady if min_steady < 99.0 else -1.0, 0.01), "drop_ticks": drops,
		"fast_s": snappedf(fast_ticks * DT, 0.01), "dives": dives, "jumps": jumps, "trace": trace}
	print("MOVE %-34s avg %5.2f m/s  max %5.2f  min(full input, settled) %5.2f  drop ticks %4d  fast %5.1f s  jumps %d  dives %d" % [
		label, avg, max_speed, float(res["min_steady_mps"]), drops, fast_ticks * DT, jumps, dives])
	h.free_sim()
	return res


static func steady(d: Vector2, mag: float = 1.0, sprint: bool = false) -> Callable:
	return func(_sim: MatchSim, _r: SimPlayer, _i: int) -> InputCmd:
		var c := InputCmd.new()
		c.move = d * mag
		c.cam_yaw = atan2(-d.x, -d.y)
		if sprint:
			c.held = TC.BTN_SPRINT
		return c


## The stick held diagonally at full deflection with the camera turned 45
## degrees off the path, so the world direction stays on the open lane (the
## command's move is world-space; that a diagonal stick, W+D or a square-gate
## pad corner is magnitude 1 is covered per device by test_touch_input and
## test_controls).
static func diagonal_stick(d: Vector2) -> Callable:
	return func(_sim: MatchSim, _r: SimPlayer, _i: int) -> InputCmd:
		var c := InputCmd.new()
		c.move = d
		c.cam_yaw = atan2(-d.x, -d.y) + PI * 0.25
		return c


## A thumb at full deflection that wobbles off-axis by a few degrees (the
## touch router's straight-ahead tolerance and its full-speed radius are
## covered by test_p9_full_speed_touch; here the sim sees a full magnitude
## whose direction jitters).
static func wobble(d: Vector2, deg: float) -> Callable:
	return func(_sim: MatchSim, _r: SimPlayer, i: int) -> InputCmd:
		var c := InputCmd.new()
		var a := deg_to_rad(deg) * sin(float(i) * 0.37) * cos(float(i) * 0.11)
		c.move = d.rotated(a)
		c.cam_yaw = atan2(-d.x, -d.y)
		return c


## Presses Jump every `every` ticks (a fast tapper).
static func tap_jump(d: Vector2, every: int, sprint: bool) -> Callable:
	return func(_sim: MatchSim, _r: SimPlayer, i: int) -> InputCmd:
		var c := InputCmd.new()
		c.move = d
		c.cam_yaw = atan2(-d.x, -d.y)
		if sprint:
			c.held = TC.BTN_SPRINT
		if i % every == 0:
			c.pressed = TC.BTN_JUMP
		return c


## The best case for a jump/dive loop: jumps the first tick a jump is
## possible and dives at once after takeoff, every time.
static func dive_chain(d: Vector2, sprint: bool) -> Callable:
	return func(_sim: MatchSim, r: SimPlayer, _i: int) -> InputCmd:
		var c := InputCmd.new()
		c.move = d
		c.cam_yaw = atan2(-d.x, -d.y)
		if sprint:
			c.held = TC.BTN_SPRINT
		if r.on_floor and not r.diving:
			c.pressed = TC.BTN_JUMP
		elif not r.on_floor and not r.diving and r.air_t > 0.1:
			c.pressed = TC.BTN_JUMP
		return c


## Runs, and every `period_s` jumps and dives once (a deliberate dive).
static func single_dives(d: Vector2, period_s: float) -> Callable:
	return func(_sim: MatchSim, _r: SimPlayer, i: int) -> InputCmd:
		var c := InputCmd.new()
		c.move = d
		c.cam_yaw = atan2(-d.x, -d.y)
		var k := int(period_s * 60.0)
		if i % k == 0 or i % k == 12:
			c.pressed = TC.BTN_JUMP
		return c


## Jumps (no dive) whenever it can.
static func jump_only(d: Vector2) -> Callable:
	return func(_sim: MatchSim, r: SimPlayer, _i: int) -> InputCmd:
		var c := InputCmd.new()
		c.move = d
		c.cam_yaw = atan2(-d.x, -d.y)
		if r.on_floor:
			c.pressed = TC.BTN_JUMP
		return c


## (1.8 only) Sprint held until the meter is dry, released, re-pressed at
## half: Pass 8's fastest sustained way across flat ground.
static func sprint_release(d: Vector2, again: float) -> Callable:
	var st := {"on": true}
	return func(_sim: MatchSim, r: SimPlayer, _i: int) -> InputCmd:
		var c := InputCmd.new()
		c.move = d
		c.cam_yaw = atan2(-d.x, -d.y)
		var meter := float(_gv(r, "sprint", 1.0))
		var ex := bool(_gv(r, "sprint_exhausted", false))
		if st["on"] and (meter <= 0.001 or ex):
			st["on"] = false
		elif not st["on"] and meter >= again:
			st["on"] = true
		if st["on"]:
			c.held = TC.BTN_SPRINT
		return c


func _dir(sim: MatchSim) -> Vector2:
	return _lane(sim)[1]


func _scenarios(d: Vector2) -> Array:
	return [
		["walk (30 % input)", 20.0, steady(d, 0.3)],
		["jog (60 % input)", 20.0, steady(d, 0.6)],
		["full input held 60 s", 60.0, steady(d)],
		["full input + Sprint held 60 s", 60.0, steady(d, 1.0, true)],
		["full input, diagonal stick", 30.0, diagonal_stick(d)],
		["full input, direction wobble ±4°", 30.0, wobble(d, 4.0)],
		["Sprint release / re-press at 50 %", 30.0, sprint_release(d, 0.5)],
		["jump whenever possible", 25.0, jump_only(d)],
		["jump/dive taps 10/s", 25.0, tap_jump(d, 6, false)],
		["best jump/dive chain", 25.0, dive_chain(d, false)],
		["best jump/dive chain + Sprint", 25.0, dive_chain(d, true)],
		["run + one dive every 3 s", 25.0, single_dives(d, 3.0)],
	]


## The measurement pass (prints every scenario; writes JSON when
## P9_MOVE_OUT is set; P9_MOVE_TRACE keeps the per-tick traces).
func test_movement_probe_and_contract() -> void:
	var h0 := SimHarness.new(t)
	h0.make([R, P])
	var d := _dir(h0.sim)
	h0.free_sim()
	var rows := {}
	var out: Array = []
	for sc in _scenarios(d):
		var res: Dictionary = await run_scenario(sc[0], sc[1], sc[2])
		rows[sc[0]] = res
		var slim := res.duplicate()
		if OS.get_environment("P9_MOVE_TRACE").is_empty():
			slim.erase("trace")
		out.append(slim)
	var path := OS.get_environment("P9_MOVE_OUT")
	if not path.is_empty():
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(out, "  "))
	if not OS.get_environment("P9_MOVE_BASELINE").is_empty():
		return      # measuring an older build: no assertions
	var cfg := Rules.cfg
	var full := cfg.runner_speed
	t.near(full, 6.0, 0.001, "runner full-input speed 6.0 m/s")
	t.near(cfg.patrol_speed, 6.6, 0.001, "Night Watch full-input speed 6.6 m/s")
	# --- steady full input
	var hold: Dictionary = rows["full input held 60 s"]
	t.eq(int(hold["drop_ticks"]), 0, "60 s of full input: no tick more than 3 % under full speed after the start (%d)" % int(hold["drop_ticks"]))
	t.check(float(hold["min_steady_mps"]) >= full - 0.05, "slowest settled tick %.2f m/s" % float(hold["min_steady_mps"]))
	t.check(float(hold["max_mps"]) <= full + 0.01, "never above full speed (%.2f)" % float(hold["max_mps"]))
	t.check(float(hold["avg_mps"]) >= full - 0.1, "average over 60 s %.2f m/s (start-up included)" % float(hold["avg_mps"]))
	t.check(float(hold["fast_s"]) >= 59.0, "classified fast the whole time (%.1f s)" % float(hold["fast_s"]))
	var sp: Dictionary = rows["full input + Sprint held 60 s"]
	t.near(float(sp["avg_mps"]), float(hold["avg_mps"]), 0.005, "the old Sprint button adds nothing (%.3f vs %.3f)" % [sp["avg_mps"], hold["avg_mps"]])
	t.check(float(sp["max_mps"]) <= full + 0.01, "and can't push the peak past full speed (%.2f)" % float(sp["max_mps"]))
	for k in ["full input, diagonal stick", "full input, direction wobble ±4°"]:
		t.eq(int(rows[k]["drop_ticks"]), 0, "%s: steady (%d drop ticks, slowest %.2f)" % [k, int(rows[k]["drop_ticks"]), float(rows[k]["min_steady_mps"])])
	# --- the analog curve below full
	t.near(float(rows["walk (30 % input)"]["avg_mps"]), full * 0.3, 0.15, "30 %% input walks (%.2f m/s)" % float(rows["walk (30 % input)"]["avg_mps"]))
	t.near(float(rows["jog (60 % input)"]["avg_mps"]), full * 0.6, 0.15, "60 %% input jogs (%.2f m/s)" % float(rows["jog (60 % input)"]["avg_mps"]))
	t.check(float(rows["walk (30 % input)"]["fast_s"]) == 0.0 and float(rows["jog (60 % input)"]["fast_s"]) == 0.0, "walking and jogging are not fast")
	# --- jumps and dives
	var watch := cfg.patrol_speed
	for k in ["jump whenever possible", "jump/dive taps 10/s", "best jump/dive chain", "best jump/dive chain + Sprint"]:
		t.check(float(rows[k]["avg_mps"]) < float(hold["avg_mps"]), "%s is slower than simply running (%.2f vs %.2f)" % [k, rows[k]["avg_mps"], hold["avg_mps"]])
		t.check(float(rows[k]["avg_mps"]) < watch, "%s never sustains the Night Watch's %.1f m/s (%.2f)" % [k, watch, rows[k]["avg_mps"]])
	var one: Dictionary = rows["run + one dive every 3 s"]
	t.check(int(one["dives"]) >= 7, "a deliberate dive still happens every time (%d dives in 25 s)" % one["dives"])
	t.check(float(one["max_mps"]) >= cfg.dive_speed - 0.05, "and is still a burst to the dive speed (%.2f m/s peak)" % one["max_mps"])


## The straight chase: the same human-like Night Watch as test_pursuit,
## from 4, 8 and 12 m behind a runner holding full input, a dive-spamming
## runner, and (1.8) one sprinting in released bursts. At 6.6 vs 6.0 m/s the
## gap closes at 0.6 m/s: from 8 m that is ~13 s to zero, sooner with reach.
func test_watch_closes_on_a_full_speed_runner() -> void:
	var tp = load("res://tests/test_pursuit.gd").new()
	tp.t = t
	var h0 := SimHarness.new(t)
	h0.make([R, P])
	var d := _dir(h0.sim)
	h0.free_sim()
	var rows := {}
	for gap in [4.0, 8.0, 12.0]:
		rows["full %d" % int(gap)] = await tp._pursue("full input %d m" % int(gap), gap, steady(d), tp.Chaser.new(), 30.0)
	rows["dive"] = await tp._pursue("dive loop 8 m", 8.0, dive_chain(d, true), tp.Chaser.new(), 30.0)
	rows["bursts"] = await tp._pursue("sprint bursts (1.8) 8 m", 8.0, sprint_release(d, 0.5), tp.Chaser.new(), 30.0)
	var path := OS.get_environment("P9_PURSUIT_OUT")
	if not path.is_empty():
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(rows, "  "))
	if not OS.get_environment("P9_MOVE_BASELINE").is_empty():
		return
	for gap in [4.0, 8.0, 12.0]:
		var r: Dictionary = rows["full %d" % int(gap)]
		var theory: float = float(gap) / (Rules.cfg.patrol_speed - Rules.cfg.runner_speed)
		t.check(not r["escaped"], "from %d m the Watch catches a runner at full speed (%.1f s; closure alone %.1f s)" % [int(gap), float(r["caught_s"]), theory])
		t.check(float(r["caught_s"]) <= theory + 1.0, "no later than the closure time allows (%.1f vs %.1f s)" % [float(r["caught_s"]), theory])
	t.check(not rows["dive"]["escaped"], "a dive loop doesn't escape either (%.1f s)" % float(rows["dive"]["caught_s"]))
	t.check(float(rows["dive"]["caught_s"]) <= float(rows["full 8"]["caught_s"]) + 0.5, "and lasts no longer than just running (%.1f vs %.1f s)" % [float(rows["dive"]["caught_s"]), float(rows["full 8"]["caught_s"])])


## Accepted and rejected jump/dive edges, one at a time (Pass 8 rules kept).
func test_dive_edges() -> void:
	var h := SimHarness.new(t)
	h.make([R, P])
	await h.release_patrol()
	var lane := _lane(h.sim)
	var d: Vector2 = lane[1]
	var a: Vector3 = lane[0]
	h.place(0, a, atan2(-d.x, -d.y))
	var r := h.sim.player(0)
	var cfg := Rules.cfg
	h.cmd(0).move = d
	await h.step(30)
	h.press(0, TC.BTN_JUMP)
	await h.step(2)
	t.check(r.vel.y > 3.0, "a running jump takes off")
	await h.step(6)
	h.press(0, TC.BTN_JUMP)
	await h.step(1)
	t.check(r.diving, "the second press in the same jump dives")
	var v0 := Vector2(r.vel.x, r.vel.z).length()
	t.check(v0 >= cfg.dive_speed - 0.2 and v0 <= cfg.dive_speed + 0.2, "at the dive speed (%.2f m/s)" % v0)
	var lift_reset := false
	while r.diving:
		var before := r.vel.y
		h.press(0, TC.BTN_JUMP)
		await h.step(1)
		if r.diving and not r.on_floor and r.vel.y > before + 0.05:
			lift_reset = true
	t.check(not lift_reset, "presses during a dive don't renew its lift")
	t.check(r.dive_land > 0.0, "landing starts the recovery (%.2f s)" % r.dive_land)
	t.eq(r.jump_buf, 0.0, "and no press made during the dive is waiting")
	var took_off := false
	for i in int(cfg.dive_land_s * 60.0) + 12:
		if i < 6:
			h.press(0, TC.BTN_JUMP)
		await h.step(1)
		if r.vel.y > 3.0:
			took_off = true
	t.check(not took_off, "presses at the start of the recovery never fire a jump later")
	h.press(0, TC.BTN_JUMP)
	await h.step(6)
	h.press(0, TC.BTN_JUMP)
	await h.step(1)
	t.check(r.diving, "next dive")
	while r.diving:
		await h.step(1)
	while r.dive_land > cfg.jump_buffer_s * 0.5:
		await h.step(1)
	h.press(0, TC.BTN_JUMP)
	var fired_at := -1
	for i in 20:
		await h.step(1)
		if r.vel.y > 3.0:
			fired_at = i
			break
	t.check(fired_at >= 0, "a press in the last %.2f s of the recovery jumps when it ends (after %d ticks)" % [cfg.jump_buffer_s, fired_at])
	h.free_sim()


## The motor state carries "fast" and no meter; discrete changes clear the
## air actions; a respawn starts still and not fast.
func test_motor_state_round_trip_and_resets() -> void:
	var h := SimHarness.new(t)
	h.make([R, P])
	await h.release_patrol()
	var r := h.sim.player(0)
	t.check(not ("sprint" in r) and not ("sprint_exhausted" in r) and not ("sprinting" in r), "no sprint meter, latch or sprinting flag on a player")
	r.fast = true
	r.dive_land = 0.3
	r.jump_buf = 0.1
	var buf := StreamPeerBuffer.new()
	r.write_motor(buf)
	var size := buf.get_position()
	buf.seek(0)
	var d := r.read_motor(buf)
	t.eq(buf.get_position(), size, "read_motor consumes exactly what write_motor wrote (%d bytes)" % size)
	t.check(bool(d["fast"]) and not d.has("sprint") and not d.has("sprint_exhausted"), "fast travels; no meter fields")
	t.near(float(d["dive_land"]), 0.3, 0.001, "and the dive recovery")
	var q := h.sim.player(1)
	q.apply_motor(d)
	t.check(q.fast, "applied on the other side")
	r.diving = true
	r.end_air_actions()
	t.check(not r.diving and r.dive_land == 0.0 and r.jump_buf == 0.0, "discrete changes clear dive, recovery and buffer")
	h.sim._respawn(r)
	t.check(not r.fast, "respawn: not fast")
	h.free_sim()


## Bots run at the steady full speed (no pacing bursts) and still finish.
func test_bots_run_steadily() -> void:
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2], [0])
	await h.release_patrol()
	var r := h.sim.player(0)
	var fast_s := 0.0
	var moving_s := 0.0
	for i in 60 * 20:
		await h.step(1)
		var sp := Vector2(r.vel.x, r.vel.z).length()
		if r.state == TC.PState.ACTIVE and r.on_floor and sp > 1.0:   # (a splash's scripted wade is not running)
			moving_s += DT
			if r.fast:
				fast_s += DT
	t.check(moving_s > 10.0, "the bot runner is on the move (%.1f s of 20)" % moving_s)
	t.check(fast_s >= moving_s * 0.6, "mostly at full speed while moving (%.1f of %.1f s)" % [fast_s, moving_s])
	h.free_sim()


## Footsteps: walking is silent, a jog is heard close, full speed further.
func test_footstep_noise_follows_speed() -> void:
	var h := SimHarness.new(t)
	h.make([R, P])
	await h.release_patrol()
	var sim := h.sim
	var r := sim.player(0)
	var cop := sim.player(1)
	var lane := _lane(sim)
	var a: Vector3 = lane[0]
	var d: Vector2 = lane[1]
	var dir := Vector3(d.x, 0, d.y)
	var cfg := sim.cfg
	var heard := {}
	for case in [["walk", 0.3], ["jog", 0.65], ["full", 1.0]]:
		h.place(0, a, atan2(-d.x, -d.y))
		h.cmd(0).move = d * float(case[1])
		await h.step(40)
		var probes := {}
		for dist in [10.0, 18.0]:
			cop.body.global_position = r.pos() + Vector3(-d.y, 0, d.x) * dist
			probes[dist] = sim.noises_for(cop).size() > 0
		heard[case[0]] = probes
		h.cmd(0).move = Vector2.ZERO
		await h.step(30)
	t.check(not heard["walk"][10.0], "walking is silent at 10 m")
	t.check(heard["jog"][10.0] and not heard["jog"][18.0], "a jog is heard at 10 m, not 18 m (radius %.0f m)" % cfg.noise_jog_m)
	t.check(heard["full"][18.0], "full speed is heard at 18 m (radius %.0f m)" % cfg.noise_fast_m)
	h.free_sim()


## Prediction: a guest (100 ms RTT, jitter, 2 % loss) holds full input, then
## spams jump/dive; its prediction agrees with the host's (no big reconcile
## corrections) and its "fast" agrees.
func test_guest_prediction_of_full_speed_and_dives() -> void:
	var tn = load("res://tests/test_net.gd").new()
	tn.t = t
	var rig: NetRig = tn._rig(50, 8, 0.02, 1, ["patrol", "runner"])
	var client: NetSession = rig.clients[0]
	var script := func(_mc: MatchController) -> InputCmd:
		var c := InputCmd.new()
		var tk := Engine.get_physics_frames()
		c.move = Vector2(0, -1)
		c.cam_yaw = 0.0
		c.held = TC.BTN_SPRINT       # an old binding: must change nothing
		if (tk / 300) % 2 == 1 and tk % 9 == 0:
			c.pressed = TC.BTN_JUMP
		return c
	rig.inputs[client] = script
	await rig.wait_until(func() -> bool: return client.local_slot >= 0, 300)
	client.set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.can_start(), 300)
	rig.host.host_start_match(4242)
	await rig.wait_until(func() -> bool: return rig.mcs.size() == 2, 300)
	var hmc := rig.host_mc()
	var cmc := rig.mc_of(client)
	await rig.wait_until(func() -> bool: return hmc.sim.phase == TC.Phase.PLAYING, 900)
	var slot := client.local_slot
	var agree := 0
	var samples := 0
	for i in 60 * 10:
		await rig.frames(1)
		if i % 30 == 29:
			samples += 1
			if bool(_gv(cmc.pred, "fast", false)) == bool(_gv(hmc.sim.player(slot), "fast", false)):
				agree += 1
	var corr: Array = cmc.stat_corrections
	var big := corr.filter(func(e): return float(e) > 0.25).size()
	print("P9NET corrections %d, over 25 cm %d, fast agreement %d/%d" % [corr.size(), big, agree, samples])
	if not OS.get_environment("P9_MOVE_BASELINE").is_empty():
		rig.teardown()
		return
	t.check(big <= 2, "full speed and dives predict cleanly (%d corrections over 25 cm)" % big)
	t.check(agree >= samples - 3, "the guest's fast flag agrees with the host's (%d/%d samples)" % [agree, samples])
	rig.teardown()


## Protocol 8: the movement rules changed (no sprint meter), so a 1.8 build
## (protocol 7) must not join and desynchronize: its HELLO is refused with
## "version" (the player reads "That party is on a different version of the
## game. Update the game to join.") and it never gets a slot; a newer
## protocol is refused the same way; the current build stays in the room.
func test_old_protocol_is_refused_with_update_needed() -> void:
	t.eq(Protocol.VERSION, 10, "protocol 10 (Pass 9 movement semantics; 24-bit positions; the map, its data and hall versions in the lobby and START)")
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(20.0, 0.0, 0.0, 1)
	var c: NetSession = rig.clients[0]
	await rig.wait_until(func() -> bool: return c.local_slot >= 0, 300)
	var before := rig.host.roster.filter(func(e): return e != null).size()
	for ver in [9, 11]:
		var other := LoopbackTransport.new(rig.hub, false)
		rig.hub.link(other.id, rig.host_t.id)
		var got: Array = []
		other.packet_received.connect(func(_p: int, data: PackedByteArray) -> void: got.append(data))
		var b := Protocol.buf_for(Protocol.M.HELLO)
		b.put_u16(ver)
		Protocol.put_str(b, "uid-proto%d" % ver)
		Protocol.put_str(b, "Other Build")
		Protocol.put_appearance(b, Cosmetics.DEFAULT)
		b.put_u8(0)
		Protocol.put_str(b, "", 32)
		Protocol.put_long_str(b, "")
		other.send(rig.host_t.id, b.data_array, true)
		await rig.frames(30)
		var answer := []
		for data in got:
			var rb := Protocol.reader(data)
			if rb.get_u8() == Protocol.M.WELCOME:
				answer = [rb.get_8(), Protocol.get_str(rb)]
		t.eq(answer, [-1, "version"], "protocol %d is refused as another version" % ver)
	t.eq(rig.host.roster.filter(func(e): return e != null).size(), before, "and gets no slot")
	t.check(c.connected and not rig.ended_reason.has(c), "the current build stays in")
	t.check(FileAccess.get_file_as_string("res://src/autoload/app.gd").contains("Update the game to join."), "the refused player is told to update")
	rig.teardown()


## An open circle of radius `rad` (flat lawn, no water, walls, low walls or
## props on it or 1.5 m either side): [center] or [] when none.
static func _open_circle(sim: MatchSim, rad: float) -> Array:
	var ng := NavGrid.shared(sim.layout)
	var b := CampusLayout.shared().bounds
	var n := 64
	var ss := sim.space_state()
	var sph := SphereShape3D.new()
	sph.radius = 0.7
	for x in range(int(b.position.x) + 25, int(b.end.x) - 25, 6):
		for z in range(int(b.position.y) + 25, int(b.end.y) - 25, 6):
			var ok := true
			var prev := Vector3.INF
			# near level (the campus has its real grades): within 0.25 m of
			# the ground at its centre all round
			var g0 := CampusBuilder.grid_y(sim.layout, x, z)
			for k in n + 1:
				var a := TAU * float(k) / float(n)
				for r2 in [rad - 1.5, rad, rad + 1.5]:
					var q := Vector2(x, z) + Vector2(cos(a), sin(a)) * float(r2)
					var c := ng.to_cell(q)
					if not ng.foot.is_in_boundsv(c) or ng.foot.is_point_solid(c) or ng.low_wall_cells.has(c) \
							or CampusBuilder.water_at(sim.layout, q) >= 0 or absf(CampusBuilder.grid_y(sim.layout, q.x, q.y) - g0) > 0.25:
						ok = false
						break
				if not ok:
					break
				var p := Vector3(x + cos(a) * rad, CampusBuilder.grid_y(sim.layout, x + cos(a) * rad, z + sin(a) * rad), z + sin(a) * rad)
				if prev != Vector3.INF:
					# a body-sized sweep (posts, kerbs and props the grid doesn't hold)
					for hh in [0.3, 1.0]:
						var q := PhysicsShapeQueryParameters3D.new()
						q.shape = sph
						q.transform = Transform3D(Basis.IDENTITY, prev + Vector3(0, hh, 0))
						q.motion = p - prev
						q.collision_mask = TC.L_WORLD
						var hit := ss.cast_motion(q)
						if hit.size() == 2 and hit[0] < 1.0:
							ok = false
				prev = p
				if not ok:
					break
			if ok:
				return [Vector2(x, z)]
	return []


## The 60 s held trace online (brief §10): a guest runner over the loopback
## rig (50 ms +-8, 2 % loss) holds full input for a minute, running a wide
## circle on open lawn (a steady 0.43 rad/s turn: the speed magnitude is the
## same as on a straight).  Per tick: input magnitude, desired speed, host
## speed, guest predicted speed, state, fast and the reconciliation
## correction of each snapshot.  P9_NET_TRACE=path writes it as JSON.
func test_guest_holds_full_speed_for_a_minute_online() -> void:
	var tn = load("res://tests/test_net.gd").new()
	tn.t = t
	var rig: NetRig = tn._rig(50, 8, 0.02, 1, ["patrol", "runner"])
	var client: NetSession = rig.clients[0]
	var circle := {"c": Vector2.ZERO, "r": 14.0, "on": false}
	var script := func(mc: MatchController) -> InputCmd:
		var c := InputCmd.new()
		if not bool(circle["on"]) or mc.pred == null:
			return c
		var rel: Vector2 = mc.pred.pos2() - (circle["c"] as Vector2)
		var tang := Vector2(-rel.y, rel.x).normalized()
		var radial := rel.normalized() * clampf((float(circle["r"]) - rel.length()) * 0.25, -0.5, 0.5)
		c.move = (tang + radial).normalized()
		c.cam_yaw = atan2(-c.move.x, -c.move.y)
		return c
	rig.inputs[client] = script
	await rig.wait_until(func() -> bool: return client.local_slot >= 0, 300)
	client.set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.can_start(), 300)
	rig.host.host_start_match(4242)
	await rig.wait_until(func() -> bool: return rig.mcs.size() == 2, 300)
	var hmc := rig.host_mc()
	var cmc := rig.mc_of(client)
	await rig.wait_until(func() -> bool: return hmc.sim.phase == TC.Phase.PLAYING, 900)
	var found := _open_circle(hmc.sim, 14.0)
	t.check(not found.is_empty(), "an open lawn circle for the trace")
	if found.is_empty():
		rig.teardown()
		return
	circle["c"] = found[0]
	var slot := client.local_slot
	var hp := hmc.sim.player(slot)
	# keep the Night Watch bot out of it
	for q in hmc.sim.players:
		if q.is_patrol():
			q.body.collision_layer = 0
	hmc.sim.bots.clear()
	var c0: Vector2 = found[0]
	hp.body.global_position = Vector3(c0.x + 14.0, CampusBuilder.grid_y(hmc.sim.layout, c0.x + 14.0, c0.y) + 0.05, c0.y)
	hp.vel = Vector3.ZERO
	await rig.frames(30)
	circle["on"] = true
	var trace: Array = []
	var seen := cmc.stat_corrections.size()
	var host_min := 99.0
	var pred_min := 99.0
	var host_drops := 0
	var not_fast := 0
	var big := 0
	var worst := 0.0
	var top := Rules.cfg.runner_speed
	for i in 60 * 62:
		await rig.frames(1)
		var corr := 0.0
		while seen < cmc.stat_corrections.size():
			corr = maxf(corr, float(cmc.stat_corrections[seen]))
			seen += 1
		var hs := Vector2(hp.vel.x, hp.vel.z).length()
		var ps := Vector2(cmc.pred.vel.x, cmc.pred.vel.z).length() if cmc.pred else 0.0
		if i >= 120:
			host_min = minf(host_min, hs)
			pred_min = minf(pred_min, ps)
			host_drops += 1 if hs < top * 0.97 else 0
			not_fast += 0 if hp.fast else 1
			big += 1 if corr > 0.25 else 0
			worst = maxf(worst, corr)
		trace.append({"t": snappedf(i / 60.0, 0.001), "input": 1.0 if bool(circle["on"]) else 0.0, "want": top, "host": snappedf(hs, 0.01),
			"guest": snappedf(ps, 0.01), "state": hp.state, "fast": hp.fast, "corr": snappedf(corr, 0.001),
			"x": snappedf(hp.pos().x, 0.01), "z": snappedf(hp.pos().z, 0.01), "floor": hp.on_floor})
	circle["on"] = false
	print("P9NET60 host min %.3f  guest min %.3f m/s  host drops %d  not fast %d  corrections over 25 cm %d  worst %.3f m" % [host_min, pred_min, host_drops, not_fast, big, worst])
	var path := OS.get_environment("P9_NET_TRACE")
	if not path.is_empty():
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(trace))
	t.check(host_min >= top - 0.1 and host_drops == 0, "online, the host keeps the guest at full speed for 60 s (min %.2f, %d drops)" % [host_min, host_drops])
	t.check(pred_min >= top - 0.25, "the guest's own prediction never dips (min %.2f)" % pred_min)
	t.eq(not_fast, 0, "fast the whole minute")
	t.check(big <= 2, "reconciliation stays small (%d corrections over 25 cm, worst %.2f m)" % [big, worst])
	rig.teardown()
