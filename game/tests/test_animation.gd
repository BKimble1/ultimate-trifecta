extends RefCounted
## V3 animation and splash presentation: gait cadence matches the asset,
## footsteps come from the gait phase, distant characters keep real time,
## the visual facing never takes the long way round, landing sounds survive
## on_floor flicker, the splash plays from authoritative time (late joiners
## included), and the impact class travels from the sim through the wire.
var t


func _view(local := false) -> CharacterView:
	var v := CharacterView.new()
	t.add_child(v)
	v.setup(TC.Role.RUNNER, Cosmetics.DEFAULT, 0, "", false, local)
	v.apply_state({"pos": Vector3.ZERO, "yaw": 0.0, "vel": Vector3.ZERO, "state": TC.PState.ACTIVE, "on_floor": true}, 0.0, true)
	return v


func test_gait_cadence_matches_the_asset() -> void:
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/runner_manifest.json"))
	var mpc: Dictionary = m["loco_m_per_cycle"]
	for k in CharacterView.LOCO_M_PER_CYCLE:
		t.near(float(mpc[k]), float(CharacterView.LOCO_M_PER_CYCLE[k]), 1e-4, "%s metres per cycle match runner_manifest.json" % k)
	var run := CharacterView.gait_rate(5.0)
	t.near(run, 5.0 / 2.2, 1e-3, "run at 5 m/s: %.2f cycles/s" % run)
	t.check(run < 2.5, "no longer scurrying (V2: 2.94 cycles/s)")
	t.near(CharacterView.gait_rate(7.0), 7.0 / 2.75, 1e-3, "sprint at 7 m/s")
	# Pass 9: the steady full-input speeds (no sprint bursts) keep a running
	# cadence, neither a scurry nor a stroll
	for spd in [Rules.cfg.runner_speed, Rules.cfg.patrol_speed]:
		var r := CharacterView.gait_rate(spd)
		t.check(r > 2.0 and r < 2.7, "steady %.1f m/s: %.2f cycles/s" % [spd, r])
	var walk := CharacterView.gait_rate(1.3)
	t.check(walk > 1.5 and walk < 2.1, "walk at 1.3 m/s: %.2f cycles/s" % walk)
	for k in ["walk", "run", "sprint", "air_rise", "air_apex", "air_fall", "land_soft", "land_hard", "splash_walk",
			"splash_jump", "splash_dive", "recover", "fidget_yawn", "fidget_look", "ready", "tag_miss"]:
		t.check((m["clips"] as Dictionary).has(k), "clip %s is in the asset" % k)
	t.near(float(m["clips"]["splash_jump"]["length"]), Rules.cfg.splash_sequence_s, 0.02, "splash clips last the sim's splash sequence")


func test_footsteps_follow_the_gait_phase() -> void:
	var v := _view()
	var steps := 0
	v.apply_state({"pos": Vector3.ZERO, "yaw": 0.0, "vel": Vector3(0, 0, -5), "state": TC.PState.ACTIVE, "on_floor": true})
	v._process(1.0 / 60.0)   # the first ground frame starts the count at the current phase
	var k0 := v._step_k
	for i in 120:
		v.apply_state({"pos": Vector3(0, 0, -5.0 * i / 60.0), "yaw": 0.0, "vel": Vector3(0, 0, -5), "state": TC.PState.ACTIVE, "on_floor": true})
		var before := v._step_k
		v._process(1.0 / 60.0)
		if v._step_k != before:
			steps += 1
	var expect := 2.0 * 2.0 * CharacterView.gait_rate(5.0)
	t.check(absf(steps - expect) <= 1.0, "2 s at 5 m/s: %d foot strikes (gait says %.1f)" % [steps, expect])
	t.check(v._step_k - k0 == steps, "every strike moves forward exactly once")
	v.queue_free()


func test_distant_characters_keep_real_time() -> void:
	# no camera: every view counts as distant and is throttled
	var v := _view()
	var total := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 61:
		var dt := rng.randf_range(1.0 / 120.0, 1.0 / 20.0)
		total += dt
		v._process(dt)
	t.near(v.anim_time_advanced + v._anim_acc, total, 1e-5, "advanced + pending = real elapsed time (V2 multiplied the last delta)")
	t.check(v.anim_time_advanced > total * 0.9, "and most of it is already applied")
	v.queue_free()


func test_visual_yaw_never_takes_the_long_way() -> void:
	var v := _view()
	var unwrapped := 0.0
	var prev := v.rotation.y
	var backwards := false
	var target := 0.0
	for i in 40:
		target = wrapf(target + 0.2, -PI, PI)   # turning left through +-180
		v.apply_state({"pos": Vector3.ZERO, "yaw": target, "vel": Vector3.ZERO, "state": TC.PState.ACTIVE, "on_floor": true})
		v._process(1.0 / 60.0)
		var d := wrapf(v.rotation.y - prev, -PI, PI)
		if d < -1e-4:
			backwards = true
		unwrapped += d
		prev = v.rotation.y
	t.check(not backwards, "a steady left turn through 180 degrees never spins back")
	t.check(unwrapped > 6.5, "and keeps up with the sim (turned %.2f rad)" % unwrapped)
	# an instant aim snap is smoothed, not drawn as a jump
	v.apply_state({"pos": Vector3.ZERO, "yaw": wrapf(target + 1.5, -PI, PI), "vel": Vector3.ZERO, "state": TC.PState.ACTIVE, "on_floor": true})
	var before := v.rotation.y
	v._process(1.0 / 60.0)
	var step := absf(wrapf(v.rotation.y - before, -PI, PI))
	t.check(step > 0.2 and step < 1.0, "a 1.5 rad aim turn is spread over frames (first frame %.2f rad)" % step)
	v.queue_free()


func test_landing_sound_survives_on_floor_flicker() -> void:
	var v := _view()
	var rs := {"pos": Vector3.ZERO, "yaw": 0.0, "vel": Vector3.ZERO, "state": TC.PState.ACTIVE, "on_floor": true}
	v._process(1.0 / 60.0)
	var lands_before := v._since_land
	# a prediction correction flips on_floor for two frames while falling slowly
	for f in [false, false, true]:
		rs["on_floor"] = f
		rs["vel"] = Vector3(0, -4.0, 0) if not f else Vector3.ZERO
		v.apply_state(rs)
		v._process(1.0 / 60.0)
	t.check(v._since_land > lands_before, "a 2-frame flicker is not a landing")
	# a real fall
	for i in 30:
		rs["on_floor"] = false
		rs["vel"] = Vector3(0, -2.0 - 0.3 * i, 0)
		v.apply_state(rs)
		v._process(1.0 / 60.0)
	rs["on_floor"] = true
	rs["vel"] = Vector3.ZERO
	v.apply_state(rs)
	v._process(1.0 / 60.0)
	t.check(v._since_land < 0.05, "a half-second fall lands once")
	var at := v._since_land
	rs["on_floor"] = false
	v.apply_state(rs)
	v._process(1.0 / 60.0)
	rs["on_floor"] = true
	v.apply_state(rs)
	v._process(1.0 / 60.0)
	t.check(v._since_land > at, "an immediate re-contact does not land again")
	v.queue_free()


func test_splash_plays_from_authoritative_time() -> void:
	var fx := Fx.new()
	t.add_child(fx)
	# a fresh splash: contact beat fires (crown emitter created)
	var a := _view()
	a.fx = fx
	a.apply_state({"pos": Vector3.ZERO, "yaw": 0.0, "vel": Vector3.ZERO, "state": TC.PState.SPLASHING, "state_t": 0.0,
		"impact": TC.Impact.JUMP, "on_floor": false})
	a._process(1.0 / 60.0)
	t.eq(a._mode, "splash", "splash state")
	t.eq(a._splash_kind, TC.Impact.JUMP, "jump impact clip chosen")
	t.check(fx._pools.has("crown"), "contact spray on a fresh splash")
	# a late joiner first sees a runner 0.8 s into the splash
	var fx2 := Fx.new()
	t.add_child(fx2)
	var b := _view()
	b.fx = fx2
	b.apply_state({"pos": Vector3.ZERO, "yaw": 0.0, "vel": Vector3.ZERO, "state": TC.PState.SPLASHING, "state_t": 0.8,
		"impact": TC.Impact.DIVE, "on_floor": false})
	b._process(1.0 / 60.0)
	t.near(b._splash_t, 0.8, 1e-6, "late joiner starts at the authoritative time")
	t.check(not fx2._pools.has("crown") and not fx2._pools.has("sheet"), "no contact spray for a splash that started before they joined")
	t.check((b._splash_beats & 3) == 3, "earlier beats are marked done, not replayed")
	# local clock advances smoothly between coarse snapshot times, re-syncs on drift
	for i in 6:
		b.apply_state({"pos": Vector3.ZERO, "yaw": 0.0, "vel": Vector3.ZERO, "state": TC.PState.SPLASHING, "state_t": 0.8,
			"impact": TC.Impact.DIVE, "on_floor": false})
		b._process(1.0 / 60.0)
	t.near(b._splash_t, 0.8 + 6.0 / 60.0 + 1.0 / 60.0 - 1.0 / 60.0, 0.02, "advances with frame time between 20 Hz state_t updates")
	b.apply_state({"pos": Vector3.ZERO, "yaw": 0.0, "vel": Vector3.ZERO, "state": TC.PState.SPLASHING, "state_t": 1.3,
		"impact": TC.Impact.DIVE, "on_floor": false})
	b._process(1.0 / 60.0)
	t.near(b._splash_t, 1.3, 1e-6, "re-syncs when the authoritative time is far ahead")
	# resurfacing: recovery is an upper-body overlay, the legs keep the ground state
	b.apply_state({"pos": Vector3(3, 0, 0), "yaw": 0.0, "vel": Vector3(0, 0, -5), "state": TC.PState.ACTIVE, "on_floor": true})
	b._process(1.0 / 60.0)
	t.eq(b._mode, "ground", "after resurfacing the runner is in normal locomotion at once")
	t.check(bool(b.tree.get("parameters/recover/active")), "with the shake-off playing on the upper body")
	t.check(b.drips != null and b._drip_t > 0.0, "and dripping")
	a.queue_free()
	b.queue_free()
	fx.queue_free()
	fx2.queue_free()


func test_impact_class_comes_from_the_sim() -> void:
	var h := SimHarness.new(t)
	var sim := h.make([TC.Role.RUNNER, TC.Role.RUNNER, TC.Role.RUNNER, TC.Role.PATROL])
	await h.to_playing()
	# 0: dropped from 1.2 m (a fall/jump in), 1: walks in at the surface, 2: dives in
	var w: Dictionary = sim.layout.waters[0]
	var c: Vector2 = w["center"]
	var off := SimHarness.drop_offset(w)
	h.place(0, Vector3(c.x + off, float(w["surface_y"]) + 1.2, c.y))
	h.place(1, Vector3(c.x + off, float(w["surface_y"]) + 0.1, c.y + 1.0))
	h.place(2, Vector3(c.x + off, float(w["surface_y"]) + 1.2, c.y - 1.0))
	var seen: Array = []
	sim.event_emitted.connect(func(e: Dictionary) -> void: seen.append(e))
	await h.step()
	sim.player(2).diving = true   # airborne now: a committed dive
	for i in 90:
		await h.step()
	var by_slot := {}
	for e in seen:
		if int(e["type"]) in [TC.Ev.SPLASH_STAMP, TC.Ev.SPLASH_NOSTAMP]:
			by_slot[int(e["a"])] = int(e["m"])
	t.eq(by_slot.get(0, -1), TC.Impact.JUMP, "fall in -> jump splash")
	t.eq(by_slot.get(1, -1), TC.Impact.WALK, "step in -> walk-in splash")
	t.eq(by_slot.get(2, -1), TC.Impact.DIVE, "dive in -> dive splash")
	for e in seen:
		if int(e["type"]) == TC.Ev.SPLASH_STAMP:
			t.check(int(e["v"]) >= 0 and int(e["b"]) == 0, "objective fields keep their meaning (b = water, v = target)")
	# through the wire: event field and snapshot byte
	var evs := [{"id": 7, "t": 100, "type": TC.Ev.SPLASH_STAMP, "a": 2, "b": 0, "v": 1, "pos": Vector3(1, 2, 3), "m": TC.Impact.DIVE}]
	var bytes := Protocol.encode_events(evs)
	var buf := StreamPeerBuffer.new()
	buf.data_array = bytes
	buf.get_u8()
	var back: Array = Protocol.decode_events(buf)
	t.eq(int(back[0]["m"]), TC.Impact.DIVE, "event m survives the wire")
	t.eq([int(back[0]["b"]), int(back[0]["v"])], [0, 1], "objective fields unchanged")
	h.free_sim()
