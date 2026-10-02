extends RefCounted
## V5 motion: transitions start from the pose on screen (no snaps), a floor
## contact flicker never plays half a jump, teleports cut and reset history,
## secondary motion is bounded under hitches and irregular frames, the
## nightcap is not flung by hitches or teleports, gait cadence matches ground
## travel at the rule speeds, the animation LOD has hysteresis and keeps real
## time, and the menu idle API.  Scenarios run through tests/motion_rig.gd
## (a 60 Hz mini-motor with the RulesConfig values, interpolated like
## MatchController, real engine frames).  The V4 values in the messages were
## measured with the same rig on dcebf4e (docs/v5/motion_register.md).
var t


func _run(scenario: String, phase0: float = 0.0) -> MotionRig:
	var rig := MotionRig.new()
	t.add_child(rig)
	var c := Cosmetics.DEFAULT.duplicate()
	c["hat"] = "nightcap"
	rig.start(scenario, Cosmetics.sanitize(c), phase0)
	await rig.finished
	return rig


func _done(rig: MotionRig) -> void:
	rig.cleanup()
	rig.queue_free()


## Upper-body snap bounds (third difference, cm).  Steady sprinting peaks at
## ~3.7 cm; V4 values are the same rig on the V4 code.
func test_transitions_do_not_snap() -> void:
	var bounds := {
		"start": [9.0, 35.1], "stop": [9.0, 25.2], "walk_start_stop": [9.0, 30.7], "reverse": [10.0, 28.6],
		"speeds": [10.0, 26.3], "kerb": [10.0, 51.3], "flicker": [6.0, 103.3], "emote": [10.0, 16.4],
		"jump_run": [14.0, 55.9], "tag_miss": [18.0, 27.8], "cart": [14.0, 38.1], "correction": [10.0, 23.2],
	}
	for sc in bounds:
		var rig: MotionRig = await _run(sc)
		var m := rig.metrics()
		t.check(float(m["pop_cm"]) < float(bounds[sc][0]), "%s: largest upper-body snap %.1f cm (bound %.0f, V4 %.1f) at %.2f s %s" % [
			sc, m["pop_cm"], bounds[sc][0], bounds[sc][1], m["pop_t"], m["pop_joint"]])
		_done(rig)


func test_contact_flicker_never_plays_air() -> void:
	var rig: MotionRig = await _run("flicker")
	var air := 0
	var flick := 0
	for f in rig.frames:
		if String(f["mode"]) == "air":
			air += 1
	# the rig flickers on_floor for a tick every 0.35 s from 0.6 s
	flick = int((rig.length - 0.6) / 0.35)
	t.check(flick >= 4, "the scenario flickered %d times" % flick)
	t.eq(air, 0, "a one-tick floor contact flicker never shows the air pose")
	_done(rig)


func test_landings_and_jumps_fire_once() -> void:
	for sc in [["jump_run", 1], ["jump_idle", 1], ["kerb", 1], ["flicker", 0], ["hitch", 0]]:
		var rig := MotionRig.new()
		t.add_child(rig)
		rig.start(String(sc[0]))
		var lands := 0
		var prev := 9.0
		while rig.running:
			await t.get_tree().process_frame
			var sl: float = rig.view._since_land
			if sl < prev - 0.001:
				lands += 1
			prev = sl
		t.eq(lands, int(sc[1]), "%s: %d landing(s) (animation, squash and sound)" % [sc[0], lands])
		_done(rig)


func test_hitch_and_teleport_do_not_fling_the_cap() -> void:
	for sc in [["hitch", 39.1], ["respawn", 40.6], ["jump_idle", 32.0]]:
		var rig: MotionRig = await _run(String(sc[0]))
		var m := rig.metrics()
		t.check(float(m["hat_tip_step_cm"]) < 12.0, "%s: nightcap tip moves %.1f cm in one frame at most (V4 %.1f)" % [sc[0], m["hat_tip_step_cm"], sc[1]])
		t.check(float(m["lag_step"]) < 0.08, "%s: head spring step %.3f rad" % [sc[0], m["lag_step"]])
		_done(rig)


func test_teleport_cuts_pose_and_resets_history() -> void:
	var cam := Camera3D.new()
	t.add_child(cam)
	cam.current = true
	var v := CharacterView.new()
	t.add_child(v)
	v.setup(TC.Role.RUNNER, Cosmetics.DEFAULT, 0, "", false, true)
	var rs := {"pos": Vector3.ZERO, "yaw": 0.0, "vel": Vector3(0, 0, -5), "state": TC.PState.ACTIVE, "on_floor": true}
	v.apply_state(rs, 0.0, true)
	for i in 20:
		rs["pos"] = Vector3(0, 0, -5.0 * i / 60.0)
		v.apply_state(rs.duplicate())
		await t.get_tree().process_frame
	# captured where it stands, then respawned 30 m away
	rs["state"] = TC.PState.CAPTURED
	rs["vel"] = Vector3.ZERO
	v.apply_state(rs.duplicate())
	await t.get_tree().process_frame
	t.check(v.pose_fade.fading(), "an ordinary state change fades from the shown pose")
	for i in 10:
		await t.get_tree().process_frame
	rs["state"] = TC.PState.ACTIVE
	rs["pos"] = Vector3(30, 0, 0)
	v.apply_state(rs.duplicate())
	await t.get_tree().process_frame
	t.check(not v.pose_fade.fading(), "a teleport cuts the pose instead of fading across the map")
	t.eq(v._mode, "ground", "and lands straight in the new state")
	t.near(v.secondary._lag.length(), 0.0, 0.02, "head spring history reset")
	t.check(v._vel_f.is_equal_approx(Vector3.ZERO), "velocity filter restarts from the new velocity")
	# the MatchController also flags cart EXITING -> ACTIVE (no movement): no cut
	for i in 5:
		await t.get_tree().process_frame
	v.apply_state(rs.duplicate(), 0.0, true)
	t.check(v._have_prev and not v._cut, "a flagged discontinuity that did not move keeps its history and does not cut")
	v.queue_free()
	cam.queue_free()


func test_secondary_bounded_under_irregular_frames() -> void:
	# a predicting client: 60 Hz velocity steps, render frames of 4..40 ms,
	# corrections that change the velocity by 2 m/s in one tick
	var v := CharacterView.new()
	t.add_child(v)
	v.setup(TC.Role.RUNNER, Cosmetics.DEFAULT, 0, "", false, true)
	v.apply_state({"pos": Vector3.ZERO, "yaw": 0.0, "vel": Vector3.ZERO, "state": TC.PState.ACTIVE, "on_floor": true}, 0.0, true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var vel := Vector3(0, 0, -5)
	var worst := 0.0
	for i in 240:
		if i % 4 == 0:
			vel = Vector3(rng.randf_range(-2, 2), 0, -5 + rng.randf_range(-2, 2))
		var dt: float = [0.004, 0.012, 0.0167, 0.029, 0.04][i % 5]
		v.apply_state({"pos": Vector3.ZERO, "yaw": 0.0, "vel": vel, "state": TC.PState.ACTIVE, "on_floor": true})
		v._process(dt)
		worst = maxf(worst, v.secondary.accel.length())
	t.check(worst <= CharacterView.ACC_MAX + 1e-3, "acceleration fed to the springs stays bounded (%.1f m/s^2)" % worst)
	# one 1 m/s correction arriving in a 4 ms frame or in a 40 ms frame:
	# V4 divided by the frame (250 vs 25 m/s^2); now both <= 1 / ACC_TAU
	for dt in [0.004, 0.04]:
		v.reset_motion()
		v.apply_state({"pos": Vector3.ZERO, "yaw": 0.0, "vel": Vector3(0, 0, -5), "state": TC.PState.ACTIVE, "on_floor": true})
		v._process(1.0 / 60.0)
		v.apply_state({"pos": Vector3.ZERO, "yaw": 0.0, "vel": Vector3(1, 0, -5), "state": TC.PState.ACTIVE, "on_floor": true})
		v._process(dt)
		var a := v.secondary.accel.length()
		t.check(a <= 1.0 / CharacterView.ACC_TAU + 0.01 and a > 5.0, "1 m/s step in a %.0f ms frame -> %.1f m/s^2" % [dt * 1000.0, a])
	v.queue_free()


func test_gait_cadence_matches_ground_travel() -> void:
	# runner jog, Night Watch on foot, runner sprint, Turbo cap
	var cfg: RulesConfig = Rules.cfg
	for spd in [1.3, cfg.runner_speed, cfg.patrol_speed, cfg.runner_sprint_speed, cfg.turbo_speed_cap]:
		var v := CharacterView.new()
		t.add_child(v)
		v.setup(TC.Role.RUNNER, Cosmetics.DEFAULT, 0, "", false, true)
		var rs := {"pos": Vector3.ZERO, "yaw": 0.0, "vel": Vector3(0, 0, -spd), "state": TC.PState.ACTIVE, "on_floor": true}
		v.apply_state(rs, 0.0, true)
		for i in 30:
			v._process(1.0 / 60.0)
		var p0 := v._phase
		for i in 60:
			v._process(1.0 / 60.0)
		var cps := v._phase - p0
		var bs := clampf(spd, CharacterView.LOCO_POINTS["walk"], CharacterView.LOCO_POINTS["sprint"])
		var expect: float = spd / v._m_per_cycle(bs)
		t.near(cps, expect, 0.02, "%.1f m/s: %.2f cycles/s = ground speed / stride of the pose shown (%.2f m)" % [spd, cps, v._m_per_cycle(bs)])
		t.near(cps, CharacterView.gait_rate(spd), 0.02, "%.1f m/s: matches CharacterView.gait_rate" % spd)
		v.queue_free()
	# steady running keeps the planted foot planted (residual is key interpolation)
	for sc in ["nw_run", "sprint"]:
		var rig: MotionRig = await _run(sc)
		var m := rig.metrics()
		t.check(float(m["slide_mean"]) < 0.7, "%s: planted foot slides %.2f m/s on average (V4 ~0.55-0.59)" % [sc, m["slide_mean"]])
		_done(rig)


func test_start_and_stop_land_on_a_step() -> void:
	var rig: MotionRig = await _run("stop")
	var v := rig.view
	var off := fposmod(v._phase * 2.0, 1.0)
	t.check(minf(off, 1.0 - off) < 0.02, "a stop finishes its step and holds a half-cycle pose (phase %.3f)" % v._phase)
	t.near(v._move_w, 0.0, 0.01, "and the legs have blended to the idle stance")
	var m := rig.metrics()
	t.check(float(m["slide_mean"]) < 0.3, "stop: planted-foot slide %.2f m/s" % m["slide_mean"])
	_done(rig)


func test_lod_has_hysteresis_and_keeps_time() -> void:
	var cam := Camera3D.new()
	t.add_child(cam)
	cam.current = true
	var v := CharacterView.new()
	t.add_child(v)
	v.setup(TC.Role.RUNNER, Cosmetics.DEFAULT, 0, "", false, false)
	v.apply_state({"pos": Vector3.ZERO, "yaw": 0.0, "vel": Vector3(0, 0, -5), "state": TC.PState.ACTIVE, "on_floor": true}, 0.0, true)
	var seq := [[30.0, false], [45.0, false], [49.0, true], [45.0, true], [43.0, true], [41.0, false], [45.0, false]]
	var total := 0.0
	for s in seq:
		cam.global_position = Vector3(0, 0, float(s[0]))
		for i in 4:
			v._process(1.0 / 60.0)
			total += 1.0 / 60.0
		t.eq(v._far, bool(s[1]), "camera at %.0f m: %s" % [s[0], "throttled" if s[1] else "full rate"])
	t.near(v.anim_time_advanced + v._anim_acc, total, 1e-5, "advanced + pending = real elapsed time across LOD changes")
	# a local character never throttles
	v.is_local = true
	cam.global_position = Vector3(0, 0, 80)
	var adv := v.anim_time_advanced
	v._process(1.0 / 60.0)
	t.check(v.anim_time_advanced > adv, "the local character updates every frame at any distance")
	v.queue_free()
	cam.queue_free()


func test_menu_idle_api() -> void:
	var v := CharacterView.new()
	v.lighting = "indoor"
	t.add_child(v)
	v.setup(TC.Role.RUNNER, Cosmetics.DEFAULT, -1, "", false, true)
	t.check(v.menu_idle, "menu idle is on by default under indoor (menu stage) lighting")
	t.near(v.hat_spring.get_drag(0), 0.7, 1e-4, "the nightcap is better damped in menus")
	v.set_menu_idle(false)
	t.check(not v.menu_idle, "set_menu_idle(false) turns it off")
	t.near(v.hat_spring.get_drag(0), 0.45, 1e-4, "and restores the gameplay spring")
	v.set_menu_idle(true)
	var g := CharacterView.new()
	t.add_child(g)
	g.setup(TC.Role.RUNNER, Cosmetics.DEFAULT, 1, "", false, false)
	t.check(not g.menu_idle, "gameplay characters (outdoor lighting) are not in menu idle")
	g.queue_free()
	v.apply_state({"pos": Vector3.ZERO, "yaw": PI, "vel": Vector3.ZERO, "state": TC.PState.ACTIVE, "on_floor": true}, 0.0, true)
	var seen := {}
	var blinks := 0
	var was := false
	for i in 1500:   # 25 s
		v._process(1.0 / 60.0)
		if v._fidget_on:
			seen[v._fidget] = true
		var b := float(v._face.get("blink", 0.0)) > 0.5
		if b and not was:
			blinks += 1
		was = b
	t.check(seen.size() >= 1, "restrained fidgets play while idle in a menu: %s" % str(seen.keys()))
	for f in seen:
		t.check(CharacterView.MENU_FIDGETS.has(f), "%s is a menu fidget" % f)
	t.check(blinks >= 4 and blinks <= 14, "%d blinks in 25 s" % blinks)
	v.queue_free()
	var rig: MotionRig = await _run("menu_idle")
	var m := rig.metrics()
	t.check(float(m["pop_cm"]) < 2.5, "24 s of menu idle without a snap (%.2f cm)" % m["pop_cm"])
	t.check(float(m["hat_tip_range_cm"]) < 12.0, "nightcap tip stays within %.1f cm of rest" % m["hat_tip_range_cm"])
	_done(rig)


func test_asset_has_the_v5_clips() -> void:
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/runner_manifest.json"))
	for k in ["fidget_shift", "fidget_bounce"] + CharacterView.ACTS:
		t.check((m["clips"] as Dictionary).has(k), "clip %s is in the asset" % k)
	t.eq((m["bones"] as Array).size(), 23, "the rig keeps its 23 bones")
	for k in CharacterView.LOCO_M_PER_CYCLE:
		t.near(float(m["loco_m_per_cycle"][k]), float(CharacterView.LOCO_M_PER_CYCLE[k]), 1e-4, "%s stride unchanged" % k)


func _cam(scenario: String) -> Dictionary:
	var cr := CameraRig.new()
	t.add_child(cr)
	await t.get_tree().physics_frame
	cr.start(scenario)
	await cr.finished
	var m := cr.metrics()
	cr.cleanup()
	cr.queue_free()
	return m


func test_camera_ignores_posts_but_not_walls() -> void:
	# V4: a 14 cm lamp post or a tree trunk crossing the line pulled the
	# camera ~3 m in within one frame, then it eased back over ~0.7 s
	for sc in ["cam_lamp", "cam_trunk"]:
		var m: Dictionary = await _cam(sc)
		t.check(float(m["jump_m"]) < 0.2, "%s: no camera jump (%.2f m in one frame; V4 ~3 m)" % [sc, m["jump_m"]])
		t.eq(int(m["pull_frames"]), 0, "%s: the camera keeps its distance" % sc)
	var w: Dictionary = await _cam("cam_wall")
	t.check(float(w["dist_min"]) < 3.0, "a wall behind the runner still pulls the camera in (%.2f m)" % w["dist_min"])
	t.eq(int(w["blocked_frames"]), 0, "and the runner is never hidden behind it")
	for sc in ["cam_ramp", "cam_hitch", "cam_turn"]:
		var m2: Dictionary = await _cam(sc)
		t.check(float(m2["jump_m"]) < 0.1, "%s: camera moves with its pivot (largest extra move %.3f m)" % [sc, m2["jump_m"]])


func test_run_on_the_spot_keeps_its_facing() -> void:
	# the lobby's "Try moves" (DormStage) runs and sprints on the spot with
	# a velocity that points out of the character's back: no travel, so the
	# body must keep facing the camera and the legs must still cycle
	var v := CharacterView.new()
	v.lighting = "indoor"
	t.add_child(v)
	v.setup(TC.Role.RUNNER, Cosmetics.DEFAULT, -1, "", false, true)
	var yaw := 2.4
	var back := Vector3(sin(yaw), 0, cos(yaw))
	v.apply_state({"pos": Vector3(1, 0, 1), "yaw": yaw, "state": TC.PState.ACTIVE, "vel": Vector3.ZERO, "on_floor": true}, 0.0, true)
	v._process(1.0 / 60.0)
	var p0 := v._phase
	for i in 60:
		v.apply_state({"pos": Vector3(1, 0, 1), "yaw": yaw, "state": TC.PState.ACTIVE, "vel": back * Rules.cfg.runner_sprint_speed,
			"on_floor": true, "sprinting": true})
		v._process(1.0 / 60.0)
	t.near(wrapf(v.rotation.y - yaw, -PI, PI), 0.0, 0.01, "the lobby runner keeps facing the camera")
	t.check(v._phase - p0 > 1.5, "and its legs keep cycling (%.2f cycles in 1 s)" % (v._phase - p0))
	v.queue_free()
