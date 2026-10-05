extends RefCounted
## Pass 8 movement contract (real sim + physics on the campus's longest open
## straight; the runner is shifted back along the lane before its end so a
## scenario can run for 30 s with nothing in the way):
##   * sprint: from a full meter a held sprint is one uninterrupted burst;
##     held on after exhaustion it never restarts into short bursts; a release
##     plus a meaningful reserve re-arms it, and the next press sprints at once;
##   * dive: one dive per airborne sequence, landing recovery can't be skipped
##     by buffered presses, so a jump/dive loop is never a sustained faster
##     way to travel than sprinting and can't hold off the Night Watch.
## Each scenario prints a MOVE line (and the probe JSON when asked) so the
## before/after table in docs/pass8/movement.md can be regenerated.
var t
const R := TC.Role.RUNNER
const P := TC.Role.PATROL
const DT := 1.0 / 60.0


func _lane(sim: MatchSim) -> Array:
	var tp = load("res://tests/test_pursuit.gd").new()
	return tp._open_lane(sim)


## Runs `fn(sim, runner, tick) -> InputCmd` for `secs` on the open lane and
## returns the per-tick trace and summary.
func run_scenario(label: String, secs: float, fn: Callable, start_meter: float = 1.0) -> Dictionary:
	var h := SimHarness.new(t)
	h.make([R, P])
	await h.release_patrol()
	var lane := _lane(h.sim)
	var a: Vector3 = lane[0]
	var d: Vector2 = lane[1]
	var dir := Vector3(d.x, 0, d.y)
	var yaw := atan2(-d.x, -d.y)
	var start := a - dir * 10.0
	h.place(0, start, yaw)
	# the Night Watch waits far away
	h.place(1, a - dir * 13.0 + Vector3(-d.y, 0, d.x) * 6.0, yaw)
	var sim := h.sim
	var r := sim.player(0)
	r.sprint = start_meter
	var travelled := 0.0
	var last_s := (r.pos() - a).dot(dir)
	var trace: Array = []
	var toggles := 0
	var bursts: Array = []
	var burst_t := 0.0
	var was_sprinting := false
	var max_speed := 0.0
	var dives := 0
	var jumps := 0
	var was_diving := false
	var n := int(secs * 60.0)
	for i in n:
		h.inputs = {0: fn.call(sim, r, i)}
		await h.step()
		var s := (r.pos() - a).dot(dir)
		travelled += s - last_s
		if s > 95.0:
			# treadmill: back 80 m along the straight, motion kept
			r.body.global_position -= dir * 80.0
			s -= 80.0
		last_s = s
		var sp := Vector2(r.vel.x, r.vel.z).length()
		max_speed = maxf(max_speed, sp)
		if r.sprinting != was_sprinting:
			toggles += 1
			if was_sprinting:
				bursts.append(snappedf(burst_t, 0.01))
			burst_t = 0.0
		if r.sprinting:
			burst_t += DT
		was_sprinting = r.sprinting
		if r.diving and not was_diving:
			dives += 1
		was_diving = r.diving
		if r.jumped_this_tick:
			jumps += 1
		trace.append({"t": snappedf(i * DT, 0.001), "speed": snappedf(sp, 0.01), "sprinting": r.sprinting,
			"meter": snappedf(r.sprint, 0.001), "exhausted": bool(r.get("sprint_exhausted")) if "sprint_exhausted" in r else false,
			"diving": r.diving, "dive_land": snappedf(r.dive_land, 0.001), "floor": r.on_floor})
	if was_sprinting:
		bursts.append(snappedf(burst_t, 0.01))
	var avg := travelled / secs
	var res := {"label": label, "secs": secs, "avg_mps": snappedf(avg, 0.01), "max_mps": snappedf(max_speed, 0.01),
		"sprint_toggles": toggles, "bursts_s": bursts, "dives": dives, "jumps": jumps, "trace": trace}
	print("MOVE %-30s avg %5.2f m/s  max %5.2f  sprint toggles %3d  bursts %s  jumps %d  dives %d" % [label, avg, max_speed, toggles,
		str(bursts.slice(0, 8)) + ("..." if bursts.size() > 8 else ""), jumps, dives])
	h.free_sim()
	return res


static func jog(d: Vector2) -> Callable:
	return func(_sim: MatchSim, _r: SimPlayer, _i: int) -> InputCmd:
		var c := InputCmd.new()
		c.move = d
		c.cam_yaw = atan2(-d.x, -d.y)
		return c


## Holds sprint the whole time (a thumb parked at the stick's edge, or the
## sprint button held down).
static func sprint_hold(d: Vector2) -> Callable:
	return func(_sim: MatchSim, _r: SimPlayer, _i: int) -> InputCmd:
		var c := InputCmd.new()
		c.move = d
		c.cam_yaw = atan2(-d.x, -d.y)
		c.held = TC.BTN_SPRINT
		return c


## Releases when the meter empties (or the exhausted latch shows) and presses
## again once the meter is back above `again`.
static func sprint_release(d: Vector2, again: float) -> Callable:
	var st := {"on": true}
	return func(_sim: MatchSim, r: SimPlayer, _i: int) -> InputCmd:
		var c := InputCmd.new()
		c.move = d
		c.cam_yaw = atan2(-d.x, -d.y)
		var exhausted: bool = bool(r.get("sprint_exhausted")) if "sprint_exhausted" in r else false
		if st["on"] and (r.sprint <= 0.001 or exhausted):
			st["on"] = false
		elif not st["on"] and r.sprint >= again:
			st["on"] = true
		if st["on"]:
			c.held = TC.BTN_SPRINT
		return c


## Presses Jump every `every` ticks (a fast tapper), optionally holding sprint.
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
	return func(_sim: MatchSim, r: SimPlayer, i: int) -> InputCmd:
		var c := InputCmd.new()
		c.move = d
		c.cam_yaw = atan2(-d.x, -d.y)
		var k := int(period_s * 60.0)
		if i % k == 0:
			c.pressed = TC.BTN_JUMP
		elif i % k == 12:
			c.pressed = TC.BTN_JUMP
		return c


func _dir(sim: MatchSim) -> Vector2:
	return _lane(sim)[1]


func _scenarios(d: Vector2) -> Array:
	return [
		["jog", 25.0, jog(d)],
		["sprint held 30 s", 30.0, sprint_hold(d)],
		["sprint, release, re-press at 50%", 30.0, sprint_release(d, 0.5)],
		["jump taps 5/s", 25.0, tap_jump(d, 12, false)],
		["jump/dive taps 10/s", 25.0, tap_jump(d, 6, false)],
		["jump/dive taps 10/s + sprint", 25.0, tap_jump(d, 6, true)],
		["best jump/dive chain", 25.0, dive_chain(d, false)],
		["best jump/dive chain + sprint", 25.0, dive_chain(d, true)],
		["run + one dive every 3 s", 25.0, single_dives(d, 3.0)],
	]


## The measurement pass (prints every scenario; writes JSON when
## P8_MOVE_OUT is set).
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
		if not OS.get_environment("P8_MOVE_TRACE").is_empty():
			pass
		else:
			slim.erase("trace")
		out.append(slim)
	var path := OS.get_environment("P8_MOVE_OUT")
	if not path.is_empty():
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(out, "  "))
	if not OS.get_environment("P8_MOVE_BASELINE").is_empty():
		return      # measuring an older build: no assertions
	var cfg := RulesConfig.new()
	# --- sprint contract
	var hold: Dictionary = rows["sprint held 30 s"]
	var hb: Array = hold["bursts_s"]
	t.check(hb.size() == 1, "held from full: one burst, never restarted while still held (%d bursts: %s)" % [hb.size(), str(hb)])
	t.check(hb.size() >= 1 and absf(float(hb[0]) - cfg.sprint_capacity_s) < 0.1, "and it lasts the whole meter (%.2f s of %.2f)" % [float(hb[0]) if hb.size() > 0 else -1.0, cfg.sprint_capacity_s])
	var rel: Dictionary = rows["sprint, release, re-press at 50%"]
	var rb: Array = rel["bursts_s"]
	var shortest := 99.0
	for b in rb:
		shortest = minf(shortest, float(b))
	t.check(rb.size() >= 3, "released and re-pressed, sprint comes back (%d bursts)" % rb.size())
	t.check(shortest >= 1.0, "every re-armed burst is a real one (shortest %.2f s)" % shortest)
	t.check(float(rel["avg_mps"]) > float(rows["jog"]["avg_mps"]) + 0.5, "sprinting in bursts beats jogging (%.2f vs %.2f m/s)" % [rel["avg_mps"], rows["jog"]["avg_mps"]])
	# --- dive contract
	var watch := cfg.patrol_speed
	for k in ["best jump/dive chain", "jump/dive taps 10/s", "best jump/dive chain + sprint", "jump/dive taps 10/s + sprint"]:
		t.check(float(rows[k]["avg_mps"]) < watch, "%s: never sustains the Night Watch's %.1f m/s (%.2f)" % [k, watch, rows[k]["avg_mps"]])
	t.check(float(rows["best jump/dive chain"]["avg_mps"]) < float(rel["avg_mps"]), "a dive loop is not faster than sprinting in bursts (%.2f vs %.2f)" % [rows["best jump/dive chain"]["avg_mps"], rel["avg_mps"]])
	var one: Dictionary = rows["run + one dive every 3 s"]
	t.check(int(one["dives"]) >= 7, "a deliberate dive still happens every time (%d dives in 25 s)" % one["dives"])
	t.check(float(one["max_mps"]) > cfg.runner_speed + 2.0, "and a single dive is still a burst (%.2f m/s peak)" % one["max_mps"])


## The chase: the same human-like Night Watch as test_pursuit runs down a
## runner from 8 m who sprints and spams jump/dive at the best possible rate
## (V4-V8: the loop held 8+ m/s and out-ran the 6.6 m/s Watch), and one who
## only sprints in re-armed bursts.
func test_dive_loop_does_not_out_run_the_watch() -> void:
	var tp = load("res://tests/test_pursuit.gd").new()
	tp.t = t
	var h0 := SimHarness.new(t)
	h0.make([R, P])
	var d := _dir(h0.sim)
	h0.free_sim()
	var dive: Dictionary = await tp._pursue("dive loop + sprint 8 m", 8.0, dive_chain(d, true), tp.Chaser.new(), 25.0)
	var bursts: Dictionary = await tp._pursue("sprint bursts (re-press 50%) 8 m", 8.0, sprint_release(d, 0.5), tp.Chaser.new(), 25.0)
	if not OS.get_environment("P8_MOVE_BASELINE").is_empty():
		return
	t.check(not dive["escaped"], "a dive loop no longer escapes the Night Watch (caught after %.1f s)" % float(dive["caught_s"]))
	t.check(float(bursts["caught_s"]) < 0.0 or float(bursts["caught_s"]) >= float(dive["caught_s"]), "sprinting in bursts lasts at least as long as dive spam (%.1f vs %.1f s)" % [bursts["caught_s"], dive["caught_s"]])


## Accepted and rejected jump/dive edges, one at a time.
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
	# a running jump still takes off (and the second press dives, once)
	h.press(0, TC.BTN_JUMP)
	await h.step(2)
	t.check(r.vel.y > 3.0, "a running jump takes off")
	await h.step(6)
	h.press(0, TC.BTN_JUMP)
	await h.step(1)
	t.check(r.diving, "the second press in the same jump dives")
	var v0 := Vector2(r.vel.x, r.vel.z).length()
	t.check(v0 >= cfg.dive_speed - 0.2 and v0 <= cfg.dive_speed + 0.2, "at the dive speed (%.2f m/s)" % v0)
	var vy0 := r.vel.y
	# more presses during the dive: no new lift, no extension, nothing queued
	var lift_reset := false
	while r.diving:
		var before := r.vel.y
		h.press(0, TC.BTN_JUMP)
		await h.step(1)
		# (gravity only lowers vel.y while airborne; the landing tick resets it to 0)
		if r.diving and not r.on_floor and r.vel.y > before + 0.05:
			lift_reset = true
	t.check(not lift_reset, "presses during a dive don't renew its lift (started at %.1f m/s up)" % vy0)
	t.check(r.dive_land > 0.0, "landing starts the recovery (%.2f s)" % r.dive_land)
	t.eq(r.jump_buf, 0.0, "and no press made during the dive is waiting")
	# early presses in the recovery don't survive it
	var took_off := false
	for i in int(cfg.dive_land_s * 60.0) + 12:
		if i < 6:
			h.press(0, TC.BTN_JUMP)
		await h.step(1)
		if r.vel.y > 3.0:
			took_off = true
	t.check(not took_off, "presses at the start of the recovery never fire a jump later")
	# ...but a press close to its end is kept and fires as soon as it ends
	h.press(0, TC.BTN_JUMP)
	await h.step(6)
	h.press(0, TC.BTN_JUMP)
	await h.step(1)
	t.check(r.diving, "next dive")
	while r.diving:
		await h.step(1)
	var waited := 0
	while r.dive_land > cfg.jump_buffer_s * 0.5:
		await h.step(1)
		waited += 1
	h.press(0, TC.BTN_JUMP)
	var fired_at := -1
	for i in 20:
		await h.step(1)
		if r.vel.y > 3.0:
			fired_at = i
			break
	t.check(fired_at >= 0, "a press in the last %.2f s of the recovery jumps when it ends (after %d ticks)" % [cfg.jump_buffer_s, fired_at])
	# a dive is not possible during the recovery even if airborne (walked off a kerb)
	await h.step(40)
	h.free_sim()


## The latch and the dive recovery travel with the motor state (prediction,
## reconcile, reconnect) and discrete changes clear the stale ones.
func test_motor_state_round_trip_and_resets() -> void:
	var h := SimHarness.new(t)
	h.make([R, P])
	await h.release_patrol()
	var r := h.sim.player(0)
	r.sprint_exhausted = true
	r.sprint = 0.2
	r.dive_land = 0.3
	r.jump_buf = 0.1
	var buf := StreamPeerBuffer.new()
	r.write_motor(buf)
	buf.seek(0)
	var d := r.read_motor(buf)
	t.check(bool(d["sprint_exhausted"]), "the exhausted latch is in the motor state")
	t.near(float(d["dive_land"]), 0.3, 0.001, "and the dive recovery")
	var q := h.sim.player(1)
	q.apply_motor(d)
	t.check(q.sprint_exhausted, "applied on the other side")
	# a splash, a capture or a cart ends a dive, its recovery and a buffered press
	r.diving = true
	r.end_air_actions()
	t.check(not r.diving and r.dive_land == 0.0 and r.jump_buf == 0.0, "discrete changes clear dive, recovery and buffer")
	# a respawn refills the meter and clears the latch
	h.sim._respawn(r)
	t.check(not r.sprint_exhausted and r.sprint == 1.0, "respawn: full meter, latch off")
	h.free_sim()


## Bots follow the same latch and still sprint again after re-arming.
func test_bots_rearm_their_sprint() -> void:
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2], [0])
	await h.release_patrol()
	var r := h.sim.player(0)
	var bursts := 0
	var was := false
	for i in 60 * 25:
		await h.step(1)
		if r.sprinting and not was:
			bursts += 1
		was = r.sprinting
	t.check(bursts >= 2, "a bot runner sprints more than once in 25 s (%d bursts)" % bursts)
	h.free_sim()


## Prediction: a guest (100 ms RTT, jitter, 2 % loss) holds sprint until the
## meter is dry and keeps holding, then spams jump/dive. Its own prediction
## agrees with the host (no big reconcile corrections; the latch agrees).
func test_guest_prediction_of_latch_and_dives() -> void:
	var tn = load("res://tests/test_net.gd").new()
	tn.t = t
	var rig: NetRig = tn._rig(50, 8, 0.02, 1, ["patrol", "runner"])
	var client: NetSession = rig.clients[0]
	var script := func(_mc: MatchController) -> InputCmd:
		var c := InputCmd.new()
		var tk := Engine.get_physics_frames()
		c.move = Vector2(0, -1)
		c.cam_yaw = 0.0
		c.held = TC.BTN_SPRINT
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
			if not ("sprint_exhausted" in cmc.pred) or cmc.pred.get("sprint_exhausted") == hmc.sim.player(slot).get("sprint_exhausted"):
				agree += 1
	var corr: Array = cmc.stat_corrections
	var big := corr.filter(func(e): return float(e) > 0.25).size()
	print("P8NET corrections %d, over 25 cm %d, latch agreement %d/%d" % [corr.size(), big, agree, samples])
	if not OS.get_environment("P8_NET_DEBUG").is_empty():
		for b in cmc.stat_big:
			print("P8BIG " + str(b))
	if not OS.get_environment("P8_MOVE_BASELINE").is_empty():
		rig.teardown()
		return
	t.check(big <= 2, "dives and the latch predict cleanly (%d corrections over 25 cm)" % big)
	t.check(agree >= samples - 2, "the guest's latch agrees with the host's (%d/%d samples)" % [agree, samples])
	rig.teardown()
