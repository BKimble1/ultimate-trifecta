extends RefCounted
## V8 hot paths and presentation ownership.
var t
const R := TC.Role.RUNNER
const P := TC.Role.PATROL


func _view() -> CharacterView:
	var v := CharacterView.new()
	t.add_child(v)
	v.setup(TC.Role.RUNNER, Cosmetics.DEFAULT, 0, "", false, false)
	v.apply_state({"pos": Vector3.ZERO, "yaw": 0.0, "vel": Vector3.ZERO, "state": TC.PState.ACTIVE, "on_floor": true}, 0.0, true)
	return v


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


## V7 and earlier: the match controller hid a view whose render state said
## "not visible", then the view's own _process re-showed it from its last
## (stale) state the same frame.  Visibility now has one owner.
func test_view_visibility_has_one_owner() -> void:
	var v := _view()
	await _frames(2)
	t.check(v.visible, "an active character is shown")
	v.hide_view()
	await _frames(3)
	t.check(not v.visible, "a view its owner hid stays hidden (no re-show from its last state)")
	v.apply_state({"pos": Vector3(2, 0, 0), "yaw": 0.0, "vel": Vector3.ZERO, "state": TC.PState.FINISHED, "on_floor": true}, 0.0, false)
	v.visible = true
	await _frames(2)
	t.check(v.visible, "the view no longer decides its own visibility from its state")
	t.check(not MatchController.view_shown({"pos": Vector3.ZERO, "state": TC.PState.FINISHED}), "finished: hidden by the owner")
	t.check(not MatchController.view_shown({"pos": Vector3.ZERO, "state": TC.PState.ACTIVE, "visible": false}), "out of interest: hidden")
	t.check(not MatchController.view_shown({}), "nothing to show: hidden")
	t.check(MatchController.view_shown({"pos": Vector3.ZERO, "state": TC.PState.CAPTURED}), "captured: shown")
	v.queue_free()


## End to end over the loopback rig: an opponent the host stops sending
## (out of the client's interest set) must disappear on the client and stay
## gone, not linger as a frozen ghost; back in range, it reappears where it
## really is, without sliding across the map.
func test_pruned_opponent_does_not_linger_as_a_ghost() -> void:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(40, 4, 0.0, 0, ["runner"])
	var client := rig.add_client("uid-c0", "Client0", "patrol")
	rig.host.role_override["uid-c0"] = TC.Role.PATROL
	await rig.wait_until(func() -> bool: return client.local_slot >= 0, 300)
	client.set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.can_start(), 300)
	rig.host.host_start_match(9090)
	var started := await rig.wait_until(func() -> bool: return rig.mcs.size() == 2, 300)
	t.check(started, "the round started")
	if not started:
		rig.teardown()
		return
	var hmc := rig.host_mc()
	var cmc := rig.mc_of(client)
	await rig.wait_until(func() -> bool: return hmc.sim.phase == TC.Phase.PLAYING and cmc.prepared, 1200)
	hmc.sim.bots.clear()
	var me := hmc.sim.player(client.local_slot)
	var opp: SimPlayer = null
	for p in hmc.sim.players:
		if p.role != me.role and p.state == TC.PState.ACTIVE:
			opp = p
			break
	t.check(opp != null, "an opponent to watch")
	if opp == null:
		rig.teardown()
		return
	var hold := func(at: Vector3) -> void:
		opp.body.global_position = at
		opp.vel = Vector3.ZERO
		opp.body.velocity = Vector3.ZERO
		opp.clear_history()
	var nav := NavGrid.shared(CampusLayout.shared())
	var open_near := func(c: Vector3, r: float) -> Vector3:
		for k in 16:
			var q := c + Vector3(r * cos(k * TAU / 16.0), 0.1, r * sin(k * TAU / 16.0))
			if nav.is_walkable(Vector2(q.x, q.z)):
				return q
		return c + Vector3(r, 0.1, 0)
	# near: in the interest set and shown
	var near: Vector3 = open_near.call(me.pos(), 6.0)
	for i in 90:
		hold.call(near)
		await rig.frames(1)
	var v: CharacterView = cmc.views[opp.id]
	t.check(v.visible, "an opponent 6 m away is shown")
	# far (beyond 90 m): the host stops sending it after the 1 s hold
	var far: Vector3 = open_near.call(me.pos(), 120.0)
	var shown_late := 0
	for i in 60 * 4:
		hold.call(far)
		await rig.frames(1)
		if i > 60 * 2 and v.visible:
			shown_late += 1
	t.eq(shown_late, 0, "pruned opponent stays hidden (frames shown after pruning: %d)" % shown_late)
	# back near: shown again at its real place (cut, not a slide)
	var max_off := 0.0
	var seen := false
	for i in 60 * 2:
		hold.call(near)
		await rig.frames(1)
		if v.visible:
			seen = true
			max_off = maxf(max_off, Vector2(v.global_position.x - near.x, v.global_position.z - near.z).length())
	t.check(seen, "shown again once back in range")
	t.check(max_off < 1.0, "reappears where it is, no slide from the old place (max %.2f m)" % max_off)
	rig.teardown()


## Effects: ramps/curves are cached and shared (bounded), a warmed pool
## covers simultaneous bursts without creating emitters mid-round, and an
## emitter only rewrites a property when it changes.
func test_fx_reuse_and_bounded_prewarm() -> void:
	var fx := Fx.new()
	t.add_child(fx)
	await _frames(1)
	fx.warm()
	var pooled := fx.pooled()
	var total := 0
	for k in pooled:
		if k != "foam":
			total += int(pooled[k])
	t.check(total <= Fx.WARM_SETS * 13 + 4, "prewarm is bounded (%d emitters)" % total)
	t.check(int(pooled.get("crown", 0)) >= 3 and int(pooled.get("mist", 0)) >= 3, "several of each splash kind ready (%s)" % str(pooled))
	var ramps := Fx._ramps.size()
	# a crowded moment: five splashes and a capture at once, on warm pools
	var at := Vector3(0, -80, 0)
	for k in [TC.Impact.WALK, TC.Impact.WALK, TC.Impact.JUMP, TC.Impact.DIVE, TC.Impact.WALK]:
		fx.splash_impact(at, k, Color(0.4, 0.8, 1.0))
	fx.whistle_burst(at)
	var after := fx.pooled()
	var grew := 0
	for k in after:
		grew += maxi(0, int(after[k]) - int(pooled.get(k, 0)))
	t.check(grew <= 2, "simultaneous bursts reuse warm emitters (%d new)" % grew)
	t.eq(Fx._ramps.size(), ramps, "no new colour ramp for repeated colours")
	var r1 := Fx._fade_ramp(Color(0.2, 0.5, 0.9))
	var r2 := Fx._fade_ramp(Color(0.2, 0.5, 0.9))
	var r3 := Fx._fade_ramp(Color(0.9, 0.5, 0.2))
	t.check(r1 == r2, "the same colour shares one ramp")
	t.check(r1 != r3, "another colour has its own (one burst never recolours another)")
	for i in Fx.RAMP_CACHE_MAX + 20:
		Fx._fade_ramp(Color(float(i) / 300.0, 0.3, 0.6))
	t.check(Fx._ramps.size() <= Fx.RAMP_CACHE_MAX, "the ramp cache is bounded (%d)" % Fx._ramps.size())
	fx.queue_free()


## The governor's window is a fixed ring: bounded, and its percentiles are
## those of the last WINDOW_S of frames.
func test_governor_ring_window() -> void:
	var g := QualityGovernor.new()
	t.add_child(g)
	g.preset = 1
	g.target_ms = 16.7
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var hist: Array = []
	for i in 2000:
		var ms := rng.randf_range(14.0, 19.0) if i % 50 != 0 else 40.0
		hist.append(ms)
		g.feed(ms, 1.0 / 60.0)
	t.check(g._n <= QualityGovernor.RING, "the ring never grows past its size (%d)" % g._n)
	var keep := int(round(QualityGovernor.WINDOW_S * 60.0))
	t.check(absi(g._n - keep) <= 1, "it holds the last %.0f s of frames (%d)" % [QualityGovernor.WINDOW_S, g._n])
	var last: Array = hist.slice(hist.size() - g._n)
	last.sort()
	t.near(g._percentile(0.75), float(last[mini(last.size() - 1, int(0.75 * last.size()))]), 1e-3, "p75 as a full sort")
	t.near(g._percentile(0.9), float(last[mini(last.size() - 1, int(0.9 * last.size()))]), 1e-3, "p90 as a full sort")
	g.queue_free()


## Distant characters animate on an elapsed-time schedule: ~20 Hz at 30,
## 60 and 120 fps (V5-V7: 10/20/40 Hz), and staggered so they don't all
## advance on the same frame.
func test_far_animation_is_elapsed_time_and_staggered() -> void:
	# a camera 100 m away: every view is distant (and nothing else's camera counts)
	var cam := Camera3D.new()
	t.add_child(cam)
	cam.global_position = Vector3(0, 0, 100)
	cam.current = true
	for fps in [30.0, 60.0, 120.0]:
		var v := _view()
		v.set_process(false)          # driven below with the frame rate under test
		await _frames(1)
		var dt: float = 1.0 / float(fps)
		var adv := 0
		var last := v.anim_time_advanced
		for i in int(fps * 2.0):
			v._process(dt)
			if v.anim_time_advanced != last:
				adv += 1
				last = v.anim_time_advanced
		t.check(v._far, "no camera: the view counts as distant")
		t.check(absi(adv - 40) <= 2, "%.0f fps: %d updates in 2 s (~20 Hz)" % [fps, adv])
		t.near(v.anim_time_advanced + v._anim_acc, 2.0, dt * 1.5, "%.0f fps: no time lost" % fps)
		v.queue_free()
	var views: Array = []
	for s in 8:
		var w := CharacterView.new()
		t.add_child(w)
		w.set_process(false)
		w.setup(TC.Role.RUNNER, Cosmetics.DEFAULT, s, "", false, false)
		w.apply_state({"pos": Vector3.ZERO, "yaw": 0.0, "vel": Vector3.ZERO, "state": TC.PState.ACTIVE, "on_floor": true}, 0.0, true)
		views.append(w)
	await _frames(1)
	var worst := 0
	var lasts: Array = views.map(func(w: CharacterView) -> float: return w.anim_time_advanced)
	for i in 120:
		var same := 0
		for k in views.size():
			var w: CharacterView = views[k]
			w._process(1.0 / 60.0)
			if w.anim_time_advanced != float(lasts[k]):
				same += 1
				lasts[k] = w.anim_time_advanced
		worst = maxi(worst, same)
	t.check(worst <= 4, "8 distant characters: at most %d advance on one frame (staggered)" % worst)
	for w in views:
		(w as CharacterView).queue_free()
	cam.queue_free()


## Adaptive quality: a slow pace with an idle GPU is CPU-bound - the render
## scale stays (it could only blur); a GPU-bound one steps down as before;
## thermal still steps down.
func test_governor_attributes_the_cause() -> void:
	var root: Window = t.get_tree().root
	var saved_scale: float = root.scaling_3d_scale
	var g := QualityGovernor.new()
	t.add_child(g)
	g.set_process(false)
	g.preset = 1
	g.target_ms = 16.7
	g._thermal = 0
	for i in 60 * 4:
		g.feed(16.7, 1.0 / 60.0, 6.0)
	for i in 60 * 8:
		g.feed(24.0, 1.0 / 60.0, 6.0)        # slow, GPU 6 ms of a 16.7 ms budget
	t.eq(g.level, 0, "CPU-bound: the scale stays")
	t.eq(g.cause, "cpu", "judged CPU-bound")
	for i in 60 * 4:
		g.feed(24.0, 1.0 / 60.0, 15.5)       # slow and the GPU is the bottleneck
	t.eq(g.level, 1, "GPU-bound: one step down")
	t.eq(g.cause, "gpu", "judged GPU-bound")
	g._thermal = 2
	for i in 60 * 6:
		g.feed(16.7, 1.0 / 60.0, 6.0)
	t.check(g.level >= 1, "thermal still steps down whatever the cause")
	g.queue_free()
	await t.get_tree().process_frame
	root.scaling_3d_scale = saved_scale
