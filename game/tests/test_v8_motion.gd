extends RefCounted
## V8 authored locomotion transitions, through tests/motion_rig.gd (the
## 60 Hz mini-motor with the RulesConfig values, real engine frames):
##   * a stop from a run plants (the stop_l / stop_r clips), once, after the
##     body has stopped; a walk does not;
##   * a start from a standstill shows the drive layer in step with the gait
##     and lets it go; hard braking shows the brake layer;
##   * sharp turns and reversals are led by the head and chest (turn lead),
##     on the side the body turns to, easing off afterwards;
##   * none of it adds a snap or foot slide to the scenarios (bounds as V5/V6).
var t


func _run(scenario: String, sample: Callable = Callable()) -> MotionRig:
	var rig := MotionRig.new()
	t.add_child(rig)
	var c := Cosmetics.DEFAULT.duplicate()
	c["hat"] = "nightcap"
	rig.start(scenario, Cosmetics.sanitize(c), 0.0)
	while rig.running:
		await t.get_tree().process_frame
		if sample.is_valid():
			sample.call(rig)
	await t.get_tree().process_frame
	return rig


func _done(rig: MotionRig) -> void:
	rig.cleanup()
	rig.queue_free()


func test_asset_has_the_v8_clips() -> void:
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/runner_manifest.json"))
	for k in ["loco_accel", "loco_brake", "lead_l", "lead_r", "add_zero", "stop_l", "stop_r"]:
		t.check((m["clips"] as Dictionary).has(k), "clip %s is in the asset" % k)


func test_a_stop_from_a_run_plants_once() -> void:
	var max_brake := [0.0]
	var stop_at := [-1.0]
	var speed_at_stop := [-1.0]
	var rig: MotionRig = await _run("stop", func(r: MotionRig) -> void:
		max_brake[0] = maxf(max_brake[0], r.view._brake_w)
		if stop_at[0] < 0.0 and r.view.stat_stops > 0:
			stop_at[0] = r._sim_t
			speed_at_stop[0] = Vector2(r.m.vel.x, r.m.vel.z).length())
	t.eq(rig.view.stat_stops, 1, "the stop from a run plays the planted stop once")
	t.check(speed_at_stop[0] >= 0.0 and speed_at_stop[0] < 0.3, "only once the body has stopped (%.2f m/s)" % speed_at_stop[0])
	t.check(max_brake[0] > 0.4, "braking sat the body back first (brake layer %.2f)" % max_brake[0])
	var m := rig.metrics()
	t.check(float(m["pop_cm"]) < 9.0, "no snap (%.1f cm, V5 bound 9)" % m["pop_cm"])
	t.check(float(m["slide_mean"]) < 0.3, "planted feet don't slide (%.2f m/s)" % m["slide_mean"])
	_done(rig)
	var walk: MotionRig = await _run("walk_start_stop")
	t.eq(walk.view.stat_stops, 0, "a stop from a walk does not plant")
	_done(walk)


func test_a_start_drives_then_lets_go() -> void:
	var w := []
	var rig: MotionRig = await _run("start", func(r: MotionRig) -> void:
		w.append([r._sim_t, r.view._accel_w]))
	var peak := 0.0
	var late := 0.0
	for e in w:
		if float(e[0]) > 0.5 and float(e[0]) < 0.9:
			peak = maxf(peak, float(e[1]))
		if float(e[0]) > 1.4:
			late = maxf(late, float(e[1]))
	t.check(peak > 0.6, "the first steps show the drive posture (%.2f)" % peak)
	t.check(late < 0.15, "and running on, it has let go (%.2f)" % late)
	var m := rig.metrics()
	t.check(float(m["pop_cm"]) < 9.0, "no snap (%.1f cm)" % m["pop_cm"])
	t.check(float(m["slide_mean"]) < 0.3, "no foot slide (%.2f m/s)" % m["slide_mean"])
	_done(rig)


func test_turns_are_led_by_head_and_chest() -> void:
	for sc in ["reverse", "turn90"]:
		var peak := [0.0]
		var sign_at_peak := [0.0]
		var rig: MotionRig = await _run(sc, func(r: MotionRig) -> void:
			if r.view._lead_w > peak[0]:
				peak[0] = r.view._lead_w
				sign_at_peak[0] = r.view._lead_sign)
		t.check(peak[0] > (0.7 if sc == "reverse" else 0.4), "%s: the turn is led (%.2f)" % [sc, peak[0]])
		t.check(sign_at_peak[0] != 0.0, "%s: on one side" % sc)
		var m := rig.metrics()
		t.check(float(m["pop_cm"]) < 10.0, "%s: no snap (%.1f cm)" % [sc, m["pop_cm"]])
		t.check(float(m["slide_mean"]) < 0.45, "%s: planted foot slide %.2f m/s" % [sc, m["slide_mean"]])
		t.check(rig.view._lead_w < 0.1, "%s: and eases off afterwards (%.2f)" % [sc, rig.view._lead_w])
		_done(rig)


## Terrain contact (prototype): on a 20 % ramp the planted ankle follows
## the ground under it (V6: the origin's plane, so the front foot sank into
## the slope and the back one floated), with one ground sample per step.
func test_terrain_contact_on_a_ramp() -> void:
	var res := {}
	for probe in [false, true]:
		var errs: Array = []
		var rig := MotionRig.new()
		t.add_child(rig)
		rig.start("ramp", Cosmetics.sanitize(Cosmetics.DEFAULT), 0.0)
		if probe:
			rig.view.terrain_contact = true
			rig.view.ground_fn = func(p: Vector3) -> float: return rig.m.ground(p)
		# the final pose exists only while the modifiers run: read it from the
		# last one's signal (as the rig records)
		var last: SkeletonModifier3D = null
		for c in rig.view.skeleton.get_children():
			if c is SkeletonModifier3D and (c as SkeletonModifier3D).active:
				last = c
		var sample := func() -> void:
			if rig._sim_t < 0.8:
				return
			var sk := rig.view.skeleton
			for k in 2:
				if not bool(rig.view.foot_lock.pinned[k]):
					continue
				var a := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("foot.L" if k == 0 else "foot.R")).origin
				errs.append(a.y - rig.m.ground(a))
		last.modification_processed.connect(sample)
		while rig.running:
			await t.get_tree().process_frame
		last.modification_processed.disconnect(sample)
		var m := rig.metrics()
		var mean := 0.0
		for e in errs:
			mean += float(e)
		mean /= maxf(1.0, errs.size())
		var dev := 0.0
		for e in errs:
			dev = maxf(dev, absf(float(e) - mean))
		res[probe] = {"dev": dev, "n": errs.size(), "slide": float(m["slide_mean"]), "pop": float(m["pop_cm"]),
			"samples": rig.view.foot_lock.ground_samples}
		rig.cleanup()
		rig.queue_free()
		await t.get_tree().process_frame
	print("TERRAIN " + JSON.stringify(res))
	t.check(int(res[true]["n"]) > 20 and int(res[false]["n"]) > 20, "planted frames measured (%d / %d)" % [res[false]["n"], res[true]["n"]])
	t.check(float(res[false]["dev"]) > 0.03, "reproduced: on the origin's plane a planted ankle is %.1f cm off the slope" % (float(res[false]["dev"]) * 100.0))
	t.check(float(res[true]["dev"]) < float(res[false]["dev"]) * 0.5, "with ground contact it follows the slope (%.1f cm)" % (float(res[true]["dev"]) * 100.0))
	t.check(float(res[true]["slide"]) < 0.3, "no foot slide (%.2f m/s)" % res[true]["slide"])
	t.check(float(res[true]["pop"]) < 10.0, "no snap (%.1f cm)" % res[true]["pop"])
	t.check(int(res[true]["samples"]) <= 14, "one ground sample per step (%d in 1.6 s of running)" % res[true]["samples"])
