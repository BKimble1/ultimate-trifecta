extends RefCounted
## Motion pipeline: render-time interpolation between physics ticks,
## explicit discontinuities, frame-rate independent damping, stable springs,
## and the CharacterView velocity-history fix.
var t


class FakeMC:
	extends MatchController
	var states: Dictionary = {}

	func _player_rs(slot: int) -> Dictionary:
		return states.get(slot, {})


func _mc() -> FakeMC:
	var mc := FakeMC.new()
	mc.cfg = Rules.cfg
	mc.views = {0: null}
	return mc


func _rs(pos: Vector3, state: int = TC.PState.ACTIVE, yaw: float = 0.0) -> Dictionary:
	return {"pos": pos, "yaw": yaw, "state": state, "vel": Vector3.ZERO, "on_floor": true}


func test_render_state_interpolates_between_ticks() -> void:
	var mc := _mc()
	mc.states[0] = _rs(Vector3(0, 0, 0))
	mc._capture_tick()
	mc.states[0] = _rs(Vector3(0.1, 0, 0), TC.PState.ACTIVE, 0.2)
	mc._capture_tick()
	var r := mc._render_rs(0, 0.5)
	t.near((r["pos"] as Vector3).x, 0.05, 1e-5, "halfway between the last two ticks")
	t.near(float(r["yaw"]), 0.1, 1e-5, "yaw interpolates too")
	t.check(not mc._discont.has(0), "ordinary motion is not a discontinuity")
	mc.free()


func test_respawn_is_not_interpolated() -> void:
	var mc := _mc()
	mc.states[0] = _rs(Vector3(5, 0, 5), TC.PState.CAPTURED)
	mc._capture_tick()
	mc.states[0] = _rs(Vector3(40, 0, 40), TC.PState.ACTIVE)
	mc._capture_tick()
	t.check(mc._discont.has(0), "respawn flagged as a discontinuity")
	t.eq(mc._render_rs(0, 0.5)["pos"], Vector3(40, 0, 40), "rendered at the new spot, never sliding across the map")
	mc.free()


func test_splash_resurface_cart_and_reconnect_jumps_snap() -> void:
	var cases := [
		[TC.PState.SPLASHING, TC.PState.ACTIVE, Vector3(1.2, 0, 0)],   # resurfacing at a shore exit
		[TC.PState.ACTIVE, TC.PState.ENTERING, Vector3(0.3, 0, 0)],    # cart entry
		[TC.PState.EXITING, TC.PState.ACTIVE, Vector3(0.6, 0, 0)],     # cart exit
		[TC.PState.ACTIVE, TC.PState.ACTIVE, Vector3(6.0, 0, 0)],      # reconnect / big correction
	]
	for c in cases:
		var mc := _mc()
		mc.states[0] = _rs(Vector3.ZERO, int(c[0]))
		mc._capture_tick()
		mc.states[0] = _rs(c[2], int(c[1]))
		mc._capture_tick()
		t.check(mc._discont.has(0), "discontinuity %d -> %d is snapped" % [c[0], c[1]])
		t.eq(mc._render_rs(0, 0.3)["pos"], c[2], "no interpolation across it")
		mc.free()


func test_camera_damping_is_frame_rate_independent() -> void:
	var a := 0.0
	var b := 0.0
	for i in 30:
		a = FollowCamera.damp(a, 1.0, 0.2, 1.0 / 30.0)
	for i in 120:
		b = FollowCamera.damp(b, 1.0, 0.2, 1.0 / 120.0)
	t.near(a, b, 1e-6, "same result after 1 s at 30 and 120 fps")


func test_head_spring_is_stable_at_any_frame_rate() -> void:
	for dt in [1.0 / 120.0, 1.0 / 60.0, 1.0 / 20.0, 0.1, 0.5]:
		var x := Vector2.ZERO
		var v := Vector2.ZERO
		var peak := 0.0
		for i in int(3.0 / minf(dt, 0.1)):
			var st := CharacterSecondary.spring_step(x, v, Vector2(0.2, -0.1), dt)
			x = st[0]
			v = st[1]
			peak = maxf(peak, x.length())
		t.check(is_finite(x.x) and is_finite(x.y), "finite at dt=%.3f" % dt)
		t.check(peak <= CharacterSecondary.MAX_LAG + 1e-6, "bounded at dt=%.3f" % dt)
		t.check(x.distance_to(Vector2(0.2, -0.1)) < 0.01, "settles on target at dt=%.3f" % dt)


func test_character_acceleration_uses_previous_velocity() -> void:
	var root := Node3D.new()
	t.add_child(root)
	var v := CharacterView.new()
	root.add_child(v)
	v.setup(TC.Role.RUNNER, Cosmetics.DEFAULT, 0, "", false)
	v.apply_state({"pos": Vector3.ZERO, "yaw": 0.0, "vel": Vector3.ZERO, "state": TC.PState.ACTIVE, "on_floor": true}, 0.0, true)
	v._process(0.1)
	v.apply_state({"pos": Vector3.ZERO, "yaw": 0.0, "vel": Vector3(0, 0, -5), "state": TC.PState.ACTIVE, "on_floor": true})
	v._process(0.1)
	# V5: the derivative of a filtered velocity (CharacterView.ACC_TAU): a
	# 5 m/s step over 0.1 s reads ~43 m/s^2, never more than ACC_MAX
	var a0 := v.secondary.accel.z
	t.check(a0 < -30.0 and a0 >= -CharacterView.ACC_MAX, "forward acceleration seen by the head spring (old bug: always 0): %.1f" % a0)
	for i in 3:
		v.apply_state({"pos": Vector3.ZERO, "yaw": 0.0, "vel": Vector3(0, 0, -5), "state": TC.PState.ACTIVE, "on_floor": true})
		v._process(0.1)
	t.check(v.secondary.accel.length() < 0.5, "constant velocity: the acceleration dies away (%.3f)" % v.secondary.accel.length())
	root.queue_free()
