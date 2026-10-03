extends RefCounted
## V6 motion: the planted-foot lock (CharacterFootLock).  V5 register M8: a
## planted foot pivoted with the body in a 90-degree turn (0.78 m/s mean
## slide) and slid in a reversal (0.92 m/s).  Same rig as test_motion_v5.
var t


func _run(scenario: String, lock: bool, phase0: float = 0.0) -> Dictionary:
	var rig := MotionRig.new()
	t.add_child(rig)
	rig.start(scenario, Cosmetics.sanitize(Cosmetics.DEFAULT), phase0)
	rig.view.foot_lock.active = lock
	await rig.finished
	var m := rig.metrics()
	rig.cleanup()
	rig.queue_free()
	return m


func test_turns_keep_the_planted_foot_planted() -> void:
	for sc in ["turn90", "reverse"]:
		var off: Dictionary = await _run(sc, false)
		var on: Dictionary = await _run(sc, true)
		t.check(float(on["slide_mean"]) < 0.15, "%s: planted-foot slide %.3f m/s with the lock (%.3f without; V5 register M8)" % [
			sc, on["slide_mean"], off["slide_mean"]])
		t.check(float(on["slide_mean"]) < float(off["slide_mean"]) * 0.35, "%s: the lock removes most of the slide" % sc)
		t.near(float(on["pop_cm"]), float(off["pop_cm"]), 0.5, "%s: the upper body is untouched (largest snap %.2f vs %.2f cm)" % [
			sc, on["pop_cm"], off["pop_cm"]])


func test_straight_running_is_unchanged() -> void:
	# cadence already plants the foot in a straight run: the lock barely acts
	var rig := MotionRig.new()
	t.add_child(rig)
	rig.start("sprint", Cosmetics.sanitize(Cosmetics.DEFAULT), 0.0)
	var worst := 0.0
	while rig.running:
		await t.get_tree().process_frame
		if rig.m.state_t > 0.6:
			for k in 2:
				worst = maxf(worst, (rig.view.foot_lock.pull[k] as Vector3).length())
	t.check(worst < 0.06, "steady sprint: the lock pulls a planted foot at most %.3f m" % worst)
	rig.cleanup()
	rig.queue_free()


func test_lock_stays_out_of_the_way() -> void:
	var v := CharacterView.new()
	t.add_child(v)
	v.setup(TC.Role.RUNNER, Cosmetics.DEFAULT, 0, "", false, true)
	# a run on the spot (the lobby's "Try moves"): velocity, no travel
	for i in 40:
		v.apply_state({"pos": Vector3.ZERO, "yaw": 0.0, "vel": Vector3(0, 0, -5), "state": TC.PState.ACTIVE, "on_floor": true})
		v._process(1.0 / 60.0)
	t.eq(v.foot_lock.weight, 0.0, "no lock while running on the spot")
	# in the air and in other states
	v.apply_state({"pos": Vector3(0, 1, 0), "yaw": 0.0, "vel": Vector3(0, 4, -5), "state": TC.PState.ACTIVE, "on_floor": false})
	for i in 10:
		v._process(1.0 / 60.0)
	t.eq(v.foot_lock.weight, 0.0, "no lock in the air")
	# a teleport forgets the pins
	v.foot_lock.pinned = [true, true]
	v.reset_motion()
	t.eq(v.foot_lock.pinned, [false, false], "a teleport releases both feet")
	v.queue_free()
