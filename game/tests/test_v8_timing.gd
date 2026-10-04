extends RefCounted
## V8 timing coherence: the remote jitter buffer (arrival statistics, a
## monotonic presentation clock, startup/underrun policies for players and
## carts, velocity-aware curves only where safe), correction offsets kept
## out of the body's heading, and remote cosmetic beats on the presentation
## timeline.  Loopback conditions are seeded test inputs, not claims about
## Game Center links.
var t
const R := TC.Role.RUNNER
const P := TC.Role.PATROL


func _rig(lat: float, jit: float, loss: float, prefs: Array) -> NetRig:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(lat, jit, loss, 1, prefs)
	return rig


func _start(rig: NetRig) -> bool:
	var client: NetSession = rig.clients[0]
	await rig.wait_until(func() -> bool: return client.local_slot >= 0, 300)
	client.set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.can_start(), 300)
	rig.host.host_start_match(5151)
	await rig.wait_until(func() -> bool: return rig.mcs.size() == 2, 300)
	var hmc := rig.host_mc()
	var cmc := rig.mc_of(client)
	return await rig.wait_until(func() -> bool: return hmc.sim.phase == TC.Phase.PLAYING and cmc.prepared, 1200)


static func _p95(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return float(s[mini(s.size() - 1, int(0.95 * s.size()))])


## Over seeded loopback conditions (clean; 160 ms RTT with jitter, loss and
## duplicates; 250 ms RTT with heavy jitter and burst loss): remote time
## never steps back, the delay stays bounded, underruns stay rare and
## bounded, and a remote teammate is drawn close to where the host had it
## at the drawn time.
func test_presentation_clock_monotonic_and_bounded() -> void:
	var conds := [
		{"name": "clean", "lat": 20.0, "jit": 2.0, "loss": 0.0, "dup": 0.0, "burst": 0.0},
		{"name": "rtt160_j25_loss3_dup5", "lat": 80.0, "jit": 25.0, "loss": 0.03, "dup": 0.05, "burst": 0.0},
		{"name": "rtt250_j40_loss5_burst", "lat": 125.0, "jit": 40.0, "loss": 0.05, "dup": 0.0, "burst": 0.3},
	]
	for c in conds:
		var rig := _rig(float(c["lat"]), float(c["jit"]), float(c["loss"]), ["runner", "runner"])
		rig.hub.duplicate = float(c["dup"])
		if float(c["burst"]) > 0.0:
			rig.hub.burst_period_s = 4.0
			rig.hub.burst_s = float(c["burst"])
		var ok: bool = await _start(rig)
		t.check(ok, "%s: the round started" % c["name"])
		if not ok:
			rig.teardown()
			continue
		var client: NetSession = rig.clients[0]
		var cmc := rig.mc_of(client)
		var hmc := rig.host_mc()
		await rig.frames(60)
		var mate := -1
		for p in hmc.sim.players:
			if p.role == R and p.id != client.local_slot and p.is_bot:
				mate = p.id
				break
		var last := -INF
		var back := 0
		var errs: Array = []
		var resync0 := cmc.stat_pres_resyncs
		var under0 := cmc.stat_underrun_ticks
		var max_delay := 0.0
		var n := 60 * 10
		for i in n:
			await rig.frames(1)
			var rt := cmc.remote_time()
			if rt < last - 1e-6:
				back += 1
			last = rt
			max_delay = maxf(max_delay, cmc._jb_delay)
			var hist: Dictionary = rig.host_positions.get(mate, {})
			var k := int(floor(rt))
			if hist.has(k) and hist.has(k + 1):
				var truth: Vector3 = (hist[k] as Vector3).lerp(hist[k + 1], rt - k)
				var rs := cmc._player_rs(mate)
				if rs.has("pos") and int(rs.get("state", 0)) == TC.PState.ACTIVE:
					errs.append(Vector2((rs["pos"] as Vector3).x - truth.x, (rs["pos"] as Vector3).z - truth.z).length())
		var np := cmc.net_presentation()
		print("NETPRES %s %s err_p95 %.3f samples %d" % [c["name"], JSON.stringify(np), _p95(errs), errs.size()])
		t.eq(back, 0, "%s: remote time never steps back" % c["name"])
		t.eq(cmc.stat_pres_backward, 0, "%s: the clock itself never ran backward" % c["name"])
		t.eq(cmc.stat_pres_resyncs - resync0, 0, "%s: no resync (cut) needed" % c["name"])
		t.check(max_delay <= MatchController.JB_MAX, "%s: delay bounded (%.1f ticks)" % [c["name"], max_delay])
		var under := cmc.stat_underrun_ticks - under0
		var allow := 0.02 if c["name"] == "clean" else (0.08 if float(c["burst"]) == 0.0 else 0.15)
		t.check(under <= int(n * allow), "%s: underruns %d of %d ticks (allowed %d)" % [c["name"], under, n, int(n * allow)])
		t.check(errs.size() > n / 3, "%s: teammate measured (%d samples)" % [c["name"], errs.size()])
		t.check(_p95(errs) < (0.25 if c["name"] == "clean" else 0.6), "%s: drawn within %.2f m of the host's path (p95)" % [c["name"], _p95(errs)])
		rig.teardown()
		await t.get_tree().physics_frame


## Hermite only where it is safe: exact at the samples, bounded bend, and
## the straight line for reversals, stops against walls, big bends; on the
## floor the height is linear.
func test_curve_is_safe() -> void:
	var a := Vector3(0, 0, 0)
	var b := Vector3(0, 0, -0.5)
	var v := Vector3(0, 0, -10)   # 10 m/s for 0.05 s = 0.5 m
	t.check(MatchController._curve_pos(a, b, v, v, 0.05, 0.0, true, true).distance_to(a) < 1e-4, "starts at the first sample")
	t.check(MatchController._curve_pos(a, b, v, v, 0.05, 1.0, true, true).distance_to(b) < 1e-4, "ends at the second")
	# a turn: velocities rotate 30 degrees over the span
	var va := Vector3(0, 0, -6)
	var vb := va.rotated(Vector3.UP, deg_to_rad(30.0))
	var b2 := a + (va + vb) * 0.5 * 0.05
	var mid := MatchController._curve_pos(a, b2, va, vb, 0.05, 0.5, true, true)
	t.check(mid.distance_to(a.lerp(b2, 0.5)) <= 0.25, "a turn bends at most 25 cm off the chord")
	t.check(mid.distance_to(a.lerp(b2, 0.5)) > 1e-4, "and does curve")
	# reversal: straight line
	var rev := MatchController._curve_pos(a, Vector3(0, 0, 0.05), Vector3(0, 0, -5), Vector3(0, 0, 5), 0.05, 0.5, true, true)
	t.check(rev.distance_to(Vector3(0, 0, 0.025)) < 1e-4, "a reversal is not curved (no overshoot)")
	# a stop against a wall: the velocity says 0.5 m, the body moved 5 cm
	var wall := MatchController._curve_pos(a, Vector3(0, 0, -0.05), v, v, 0.05, 0.5, true, true)
	t.check(wall.distance_to(Vector3(0, 0, -0.025)) < 1e-4, "velocities that don't explain the move: straight line")
	# airborne: the height follows the arc; grounded: linear height
	var up := Vector3(0, 4, 0)
	var dn := Vector3(0, 3.2, 0)
	var air := MatchController._curve_pos(Vector3.ZERO, Vector3(0, 0.18, -0.3), Vector3(0, 0, -6) + up, Vector3(0, 0, -6) + dn, 0.05, 0.5, true, false)
	var gnd := MatchController._curve_pos(Vector3.ZERO, Vector3(0, 0.18, -0.3), Vector3(0, 0, -6) + up, Vector3(0, 0, -6) + dn, 0.05, 0.5, true, true)
	t.check(absf(gnd.y - 0.09) < 1e-4, "grounded: linear height")
	t.check(air.y > gnd.y, "airborne: the arc (%.3f above the chord)" % (air.y - gnd.y))


## Startup, bracket and underrun policies for remote players and carts.
func test_startup_and_underrun_policies() -> void:
	var rig := _rig(30, 3, 0.0, ["patrol", "runner"])
	var ok: bool = await _start(rig)
	t.check(ok, "round started")
	var client: NetSession = rig.clients[0]
	var cmc := rig.mc_of(client)
	await rig.frames(30)
	var lay := CampusLayout.shared()
	# a wall segment and a point 1.0 m in front of it, running at it
	var w: Dictionary = lay.walls[0]
	var wa: Vector2 = w["a"]
	var wb: Vector2 = w["b"]
	var mid2 := (wa + wb) * 0.5
	var nrm := (wb - wa).normalized().orthogonal()
	var from2 := mid2 + nrm * (float(w["t"]) * 0.5 + 1.0)
	var y := 0.0
	var from := Vector3(from2.x, y, from2.y)
	var toward := Vector3(-nrm.x, 0, -nrm.y) * 7.0
	var slot := -1
	for s in cmc.views:
		if s != client.local_slot:
			slot = s
			break
	var base := {"pos": from, "yaw": 0.0, "vel": toward, "state": TC.PState.ACTIVE, "state_t": 1.0, "on_floor": true,
		"diving": false, "tag_phase": 0}
	cmc._bufs[slot] = [{"tick": 100, "e": base.duplicate()}, {"tick": 103, "e": base.duplicate()}]
	cmc._seen_tick[slot] = 103
	cmc._last_snap["tick"] = 103
	cmc._pres_ok = true
	cmc._pres_tick = 98.0
	t.check((cmc._interp_player(slot)["pos"] as Vector3).distance_to(from) < 1e-4, "startup: holds the oldest sample")
	cmc._pres_tick = 103.0 + 6.0 * 3.0   # 0.3 s past the newest: extrapolation caps at 0.1 s
	var ex: Vector3 = cmc._interp_player(slot)["pos"]
	var moved := Vector2(ex.x - from.x, ex.z - from.z).length()
	t.check(moved <= 7.0 * MatchController.EXTRAP_MAX_S + 1e-3, "underrun: at most %.2f m of extrapolation (%.2f)" % [7.0 * MatchController.EXTRAP_MAX_S, moved])
	var gap := CampusLayout._dist_to_segment(Vector2(ex.x, ex.z), wa, wb) - float(w["t"]) * 0.5
	t.check(gap >= 0.3, "and it stops short of the wall (%.2f m clear)" % gap)
	var air := base.duplicate()
	air["on_floor"] = false
	cmc._bufs[slot] = [{"tick": 100, "e": base.duplicate()}, {"tick": 103, "e": air}]
	t.check((cmc._interp_player(slot)["pos"] as Vector3).distance_to(from) < 1e-4, "airborne: holds (no guessed arc)")
	# carts: startup holds the oldest (V4-V7 showed the newest, then stepped back)
	var ce := {"pos": Vector3(1, 0, 1), "yaw": 0.0, "speed": 0.0, "steer": 0.0, "occupant": -1, "slowed": false}
	var ce2 := ce.duplicate()
	ce2["pos"] = Vector3(1, 0, -2)
	ce2["speed"] = 6.0
	cmc._cart_bufs[0] = [{"tick": 200, "e": ce}, {"tick": 203, "e": ce2}]
	cmc._pres_tick = 190.0
	t.check((cmc._cart_rs(0)["pos"] as Vector3).distance_to(Vector3(1, 0, 1)) < 1e-4, "cart startup: holds the oldest")
	cmc._pres_tick = 201.5
	var mid: Vector3 = cmc._cart_rs(0)["pos"]
	t.check(mid.z < 1.0 and mid.z > -2.0, "cart bracket: between the samples (z %.2f)" % mid.z)
	cmc._pres_tick = 230.0
	var cx: Vector3 = cmc._cart_rs(0)["pos"]
	t.check(cx.distance_to(Vector3(1, 0, -2)) <= 6.0 * MatchController.EXTRAP_MAX_S + 1e-3, "cart underrun: bounded extrapolation, then hold")
	rig.teardown()


## The local player's decaying reconcile offset is presentation, not travel:
## it must not turn the body (V5-V7 derived the heading from the drawn
## position, offset included).
func test_correction_offset_does_not_turn_the_body() -> void:
	var dev_with := await _run_with_correction(true)
	var dev_without := await _run_with_correction(false)
	t.check(dev_without > 8.0, "reproduced: read as travel, a 0.5 m sideways correction turns the body %.1f deg" % dev_without)
	t.check(dev_with < 1.5, "excluded from travel: the body keeps its heading (%.2f deg)" % dev_with)


func _run_with_correction(mark: bool) -> float:
	var v := CharacterView.new()
	t.add_child(v)
	v.setup(TC.Role.RUNNER, Cosmetics.DEFAULT, 0, "", false, true)
	var dt := 1.0 / 60.0
	var base := Vector3.ZERO
	var corr := Vector3.ZERO
	var worst := 0.0
	for i in 150:
		base += Vector3(0, 0, -5.0) * dt
		if i == 60:
			corr = Vector3(0.5, 0, 0)       # a reconcile moved the prediction 0.5 m sideways
		corr = corr.lerp(Vector3.ZERO, clampf(dt * 12.0, 0.0, 1.0))
		var rs := {"pos": base + corr, "yaw": 0.0, "vel": Vector3(0, 0, -5), "state": TC.PState.ACTIVE, "on_floor": true}
		if mark:
			rs["corr"] = corr
		v.apply_state(rs, dt, i == 0)
		v._process(dt)
		if i > 30:
			worst = maxf(worst, absf(rad_to_deg(wrapf(v.rotation.y, -PI, PI))))
	v.queue_free()
	await t.get_tree().process_frame
	return worst


## (process_frame is emitted before the nodes' _process: two of them make
## sure the match controller has presented what was queued)
func _presented() -> void:
	await t.get_tree().process_frame
	await t.get_tree().process_frame


## Another player's splash/bump beat waits for the presentation time to
## reach the event's tick; its HUD line does not wait; each beat is shown
## once; the local player's own events are immediate.
func test_remote_beats_follow_the_presentation_time() -> void:
	var rig := _rig(30, 3, 0.0, ["runner", "runner"])
	var ok: bool = await _start(rig)
	t.check(ok, "round started")
	var client: NetSession = rig.clients[0]
	var cmc := rig.mc_of(client)
	await rig.frames(30)
	var other := -1
	for s in cmc.views:
		if s != client.local_slot:
			other = s
			break
	var now := cmc.remote_time()
	var ev := {"id": 900001, "t": int(now) + 12, "type": TC.Ev.BUMP, "a": other, "b": 0, "v": 0, "pos": Vector3(0, -50, 0)}
	cmc._local_events.append(ev)
	await _presented()
	t.eq(cmc._beats.size(), 1, "a remote bump 12 ticks ahead of the drawn time waits")
	t.check(not cmc._beat_ids.has(900001), "not shown yet")
	await rig.frames(20)
	await _presented()
	t.eq(cmc._beats.size(), 0, "shown once the drawn time reaches its tick")
	t.check(cmc._beat_ids.has(900001), "and recorded by id")
	# a repeat of the same event id shows no second beat
	var shown := cmc.stat_beats_shown
	cmc._local_events.append(ev.duplicate())
	await _presented()
	t.eq(cmc.stat_beats_shown, shown, "a repeated event id shows no second beat")
	var mine := {"id": 900002, "t": int(cmc.remote_time()) + 30, "type": TC.Ev.BUMP, "a": client.local_slot, "b": 0, "v": 0, "pos": Vector3(0, -50, 0)}
	cmc._local_events.append(mine)
	await _presented()
	t.check(cmc._beat_ids.has(900002) and cmc._beats.is_empty(), "the local player's own event is immediate")
	rig.teardown()
