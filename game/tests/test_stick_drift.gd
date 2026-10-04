extends RefCounted
## V7: forward movement must not wander.  Measured causes (tools/stick_probe.sh,
## docs/V7_NOTES.md): (1) the dynamic stick measured deflection from its
## ring centre clamped on screen, so a thumb landing near the bottom-left
## corner started at full deflection and an exact vertical push ran mostly
## sideways; (2) on foot the camera turned at a fixed rate toward the travel
## velocity, and movement is camera-relative, so any lean of more than about
## a degree swung camera and runner round together; (3) a drifting pad
## leaked into movement and look under a touch thumb.  Each test below fails
## on the V6/V7-pre-fix code.
var t

const VIEW := Vector2(1559, 720)       # 812x375 pt landscape, canvas units


func _router(mirrored := false) -> TouchRouter:
	var r := TouchRouter.new()
	r.view_size = VIEW
	r.stick_radius = 107.0
	# the resolved phone zone: one side below the top HUD band
	r.stick_zone = Rect2(Vector2(VIEW.x - 701.55 if mirrored else 0.0, 129.6), Vector2(701.55, 590.4))
	return r


func _zone_points(r: TouchRouter) -> Array[Vector2]:
	var z := r.zone()
	var out: Array[Vector2] = []
	for fx in [0.005, 0.03, 0.1, 0.25, 0.5, 0.75, 0.9, 0.97, 0.995]:
		for fy in [0.005, 0.03, 0.2, 0.5, 0.8, 0.97, 0.995]:
			out.append(z.position + z.size * Vector2(fx, fy))
	return out


## Touchdown alone never moves, wherever it lands (the ring may be drawn
## elsewhere to fit the screen), and an exact vertical push from there has no
## sideways part.  The knob is drawn at the ring plus the real offset.
func test_dynamic_touchdown_is_neutral_and_vertical_is_vertical() -> void:
	for mirrored in [false, true]:
		var r := _router(mirrored)
		var worst_d0 := 0.0
		var worst_x := 0.0
		var clamped := 0
		var knob_ok := true
		for p in _zone_points(r):
			r.touch_down(0, p)
			worst_d0 = maxf(worst_d0, r.move_vector().length())
			if r.stick_center.distance_to(p) > 1.0:
				clamped += 1
			for k in [0.3, 0.6, 1.0, 1.4]:
				var to := p + Vector2(0, -r.stick_radius * k)
				r.drag(0, to, to - r.stick_pos)
				var mv := r.move_vector()
				worst_x = maxf(worst_x, absf(mv.x))
				if mv.y <= 0.0:
					worst_x = INF
				var want := r.stick_center + (to - p).limit_length(r.stick_radius)
				knob_ok = knob_ok and r.knob_pos().distance_to(want) < 0.01
			r.touch_up(0)
		var tag := "mirrored" if mirrored else "standard"
		t.check(clamped > 0, "%s: some touchdowns need the ring drawn clamped (%d)" % [tag, clamped])
		t.eq(worst_d0, 0.0, "%s: touchdown alone is neutral at every accepted position (incl. corners)" % tag)
		t.check(worst_x < 1e-6, "%s: an exact vertical push has no sideways component (worst %.4f)" % [tag, worst_x])
		t.check(knob_ok, "%s: the knob is drawn at ring + the real offset" % tag)
		# the ring stays on screen
		r.touch_down(0, Vector2(4.0 if not mirrored else VIEW.x - 4.0, 715))
		var c := r.stick_center
		t.check(c.x - r.stick_radius >= 0.0 and c.x + r.stick_radius <= VIEW.x and c.y + r.stick_radius <= VIEW.y, "%s: the ring is drawn fully on screen (%s)" % [tag, str(c)])
		r.cancel_all()


## Fixed stick: a touch away from its fixed centre is a deliberate deflection.
func test_fixed_stick_keeps_its_contract() -> void:
	var r := _router()
	r.fixed_stick = true
	r.fixed_center = Vector2(210, 560)
	r.touch_down(0, Vector2(210 + 60, 560))
	t.check(r.move_vector().x > 0.3, "a touch right of the fixed centre steers right at once")
	t.eq(r.stick_center, Vector2(210, 560), "and the ring stays at its fixed centre")


## The base follows a thumb that overshoots, along the thumb's own direction:
## the direction read never jumps sideways, holding forward with wobble stays
## forward, and nothing of it survives the gesture.
func test_base_follow_never_turns_the_direction() -> void:
	var r := _router()
	var p := Vector2(350, 420)
	r.touch_down(0, p)
	var R := r.stick_radius
	var worst := 0.0
	var prev := Vector2.ZERO
	for i in 240:
		var tt := float(i) / 60.0
		var reach := minf(2.6, tt * 3.0)
		var to := p + Vector2(R * 0.05 * sin(TAU * 1.1 * tt), -R * reach)
		r.drag(0, to, to - r.stick_pos)
		var mv := r.move_vector()
		if prev != Vector2.ZERO and mv != Vector2.ZERO:
			worst = maxf(worst, absf(rad_to_deg(prev.angle_to(mv))))
		prev = mv
	t.check(r.follows > 0, "the base followed the overshooting thumb")
	t.check(worst < 1.0, "the direction never jumped while it followed (largest step %.2f deg)" % worst)
	t.check(absf(prev.x) < 1e-6 and prev.y > 0.99, "forward with a small wobble reads exactly forward (%s)" % str(prev))
	r.touch_up(0)
	t.eq(r.move_vector(), Vector2.ZERO, "lifting stops at once")
	r.touch_down(1, Vector2(300, 500))
	t.eq(r.move_vector(), Vector2.ZERO, "the next gesture starts neutral (no follow offset survives)")
	r.cancel_all()
	t.eq(r.move_vector(), Vector2.ZERO, "cancel clears it")


## The straight-ahead tolerance is narrow, continuous and keeps magnitude;
## deliberate angles, diagonals, strafe and reverse are untouched.
func test_straight_tolerance_is_narrow_and_continuous() -> void:
	var prev_out := 0.0
	var max_step := 0.0
	var mono := true
	for i in 361:
		var a := deg_to_rad(float(i) * 0.25)          # 0 .. 90 degrees right of forward
		for m in [0.4, 1.0]:
			var v: Vector2 = Vector2(sin(a), cos(a)) * m
			var o := TouchRouter.straighten(v)
			if i % 90 == 0:
				t.check(absf(o.length() - v.length()) < 1e-5, "magnitude kept")
			if m == 1.0:
				var oa := atan2(o.x, o.y)
				if i > 0:
					max_step = maxf(max_step, rad_to_deg(oa - prev_out))
					mono = mono and oa >= prev_out - 1e-6
				prev_out = oa
	t.check(mono, "the output angle never goes backwards")
	t.check(max_step < 0.45, "continuous: no snap anywhere (largest output step %.2f deg per 0.25 deg)" % max_step)
	var deg := func(d: float) -> float:
		var o := TouchRouter.straighten(Vector2(sin(deg_to_rad(d)), cos(deg_to_rad(d))))
		return rad_to_deg(atan2(o.x, o.y))
	t.near(deg.call(5.0), 0.0, 1e-4, "a 5 degree lean reads straight")
	t.near(deg.call(-5.0), 0.0, 1e-4, "both sides")
	t.check(deg.call(10.0) > 5.0, "a 10 degree heading still steers (%.1f)" % deg.call(10.0))
	t.near(deg.call(16.0), 16.0, 1e-3, "from 16 degrees the thumb's own angle")
	for d in [20.0, 45.0, 90.0, 135.0, -45.0, -90.0]:
		t.near(deg.call(d), d, 1e-3, "%d degrees untouched" % int(d))
	var back := TouchRouter.straighten(Vector2(sin(deg_to_rad(175.0)), cos(deg_to_rad(175.0))))
	t.check(absf(back.x) < 1e-6 and back.y < -0.99, "reverse has the same tolerance")


## A spare finger resting in the stick zone doesn't turn the camera; a real
## drag there does (once past ~3 mm, without a jump); the look side of the
## screen is immediate.
func test_spare_finger_needs_a_real_drag() -> void:
	var r := _router()
	r.touch_down(0, Vector2(300, 520))            # the stick
	r.touch_down(1, Vector2(520, 600))            # a spare finger in the stick zone
	var at := Vector2(520, 600)
	for i in 120:
		var j := Vector2(1.5 if i % 2 == 0 else -1.5, -0.75 if i % 2 == 0 else 0.75)
		r.drag(1, at + j, j)
		at += j
	t.eq(r.take_look_px(), Vector2.ZERO, "touch-screen jitter on a resting finger never turns the camera")
	for i in 30:
		r.drag(1, at + Vector2(2, 0), Vector2(2, 0))
		at += Vector2(2, 0)
	var look := r.take_look_px()
	t.check(look.x > 25.0 and look.x <= 60.0 - TouchRouter.LOOK_SLOP_PX + 2.0, "a real drag turns it, without paying out the slop as a jump (%s)" % str(look))
	r.touch_down(2, Vector2(1200, 400))           # the look side
	r.drag(2, Vector2(1203, 400), Vector2(3, 0))
	t.eq(r.take_look_px(), Vector2(3, 0), "a look on the camera side is immediate")
	t.check(absf(r.move_vector().x) < 1e-6, "none of it moved the stick")


## A finger on the touch stick owns movement even inside its dead zone; while
## touch is the device a drifting pad moves and turns nothing; a deliberate
## controller takes over normally.
func test_touch_owns_movement_and_pad_drift_is_ignored() -> void:
	var saved_dev := Controls.device
	var saved_joy := Controls.active_joy
	Controls.device = "touch"
	Controls.active_joy = 0
	var jm := InputEventJoypadMotion.new()
	jm.device = 0
	jm.axis = JOY_AXIS_LEFT_X
	jm.axis_value = 0.3
	Input.parse_input_event(jm)
	var jr := InputEventJoypadMotion.new()
	jr.device = 0
	jr.axis = JOY_AXIS_RIGHT_X
	jr.axis_value = 0.3
	Input.parse_input_event(jr)
	Input.flush_buffered_events()
	Controls.device = "touch"                     # (0.3 is below the switch threshold anyway)
	Controls.touch_stick_owned = true
	Controls.touch_move = Vector2.ZERO
	t.eq(Controls.get_move(), Vector2.ZERO, "thumb resting in the dead zone: the pad's drift doesn't walk the runner")
	Controls.touch_stick_owned = false
	t.eq(Controls.get_move(), Vector2.ZERO, "while touch is the device, pad drift is not movement")
	t.eq(Controls.consume_look(1.0 / 60.0), Vector2.ZERO, "nor camera look")
	Controls.device = "gamepad"
	t.check(Controls.get_move().x > 0.05, "a controller in use still moves")
	t.check(absf(Controls.consume_look(1.0 / 60.0).x) > 0.0, "and looks")
	jm.axis_value = 0.0
	jr.axis_value = 0.0
	Input.parse_input_event(jm)
	Input.parse_input_event(jr)
	Input.flush_buffered_events()
	Controls.reset_touch()
	t.check(not Controls.touch_stick_owned, "reset clears stick ownership")
	Controls.device = saved_dev
	Controls.active_joy = saved_joy


# --- camera: closed loop of camera-relative input and the follow camera -----

## Runs `secs` of a runner holding the stick at `lean_deg` (after the stick's
## own straight-ahead tolerance) at `spd` m/s; travel = the camera-relative
## command, optionally deflected by `deflect_deg` (a wall slide).  Returns
## the camera's yaw change in degrees.
func _loop(lean_deg: float, secs: float, dt: float, deflect_deg := 0.0, recenter := true, spd := 7.4) -> float:
	var cam := FollowCamera.new()
	t.add_child(cam)
	cam.auto_recenter = recenter
	cam.snap_to(Vector3.ZERO, 0.0)
	cam.set("_manual_t", 10.0)
	var pos := Vector2.ZERO
	var mv := TouchRouter.straighten(Vector2(sin(deg_to_rad(lean_deg)), cos(deg_to_rad(lean_deg))))
	var y0 := cam.yaw
	for i in int(secs / dt):
		var yaw := cam.yaw
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		var right := Vector2(cos(yaw), -sin(yaw))
		var v := (right * mv.x + fwd * mv.y).rotated(deg_to_rad(deflect_deg)) * spd
		pos += v * dt
		cam.move_input = mv
		cam.target_pos = Vector3(pos.x, 0.0, pos.y)
		cam.target_vel = Vector3(v.x, 0.0, v.y)
		cam.update_camera(dt)
	var d := rad_to_deg(angle_difference(y0, cam.yaw))
	cam.queue_free()
	return d


func test_camera_has_no_lean_feedback_loop() -> void:
	for lean in [0.0, 2.0, 4.0, 6.0, -6.0]:
		var d := _loop(lean, 10.0, 1.0 / 60.0)
		t.check(absf(d) < 0.5, "a %+.0f degree thumb lean held 10 s doesn't swing the camera (%.2f deg)" % [lean, d])
	var slide := _loop(0.0, 5.0, 1.0 / 60.0, 20.0)
	t.check(absf(slide) < 0.5, "a wall slide (travel 20 degrees off the stick) is not a new heading (%.2f deg)" % slide)


func test_camera_follows_deliberate_steering_gently() -> void:
	var d15 := _loop(15.0, 4.0, 1.0 / 60.0)
	t.check(d15 < -10.0 and d15 > -80.0, "holding 15 degrees right, the camera follows gently (%.1f deg in 4 s)" % d15)
	var dl := _loop(-15.0, 4.0, 1.0 / 60.0)
	t.near(dl, -d15, 0.5, "left mirrors right")
	var d30 := _loop(30.0, 4.0, 1.0 / 60.0)
	t.check(absf(d30) < 0.5, "a wider turn or strafe leaves the camera where the player put it (%.2f)" % d30)
	var off := _loop(15.0, 4.0, 1.0 / 60.0, 0.0, false)
	t.check(absf(off) < 1e-3, "recentering off: never")
	# frame-rate independent
	var d30fps := _loop(15.0, 4.0, 1.0 / 30.0)
	var d120 := _loop(15.0, 4.0, 1.0 / 120.0)
	t.check(absf(d30fps - d15) < 0.05 * absf(d15) and absf(d120 - d15) < 0.05 * absf(d15), "same at 30, 60 and 120 fps (%.1f / %.1f / %.1f)" % [d30fps, d15, d120])


func test_cart_camera_still_swings_behind_the_cart() -> void:
	var cam := FollowCamera.new()
	t.add_child(cam)
	cam.snap_to(Vector3.ZERO, 0.0)
	cam.set("_manual_t", 10.0)
	cam.in_cart = true
	var heading := deg_to_rad(40.0)
	for i in 120:
		cam.target_vel = Vector3(-sin(heading), 0.0, -cos(heading)) * 9.0
		cam.target_pos += cam.target_vel / 60.0
		cam.update_camera(1.0 / 60.0)
	t.check(rad_to_deg(cam.yaw) > 20.0, "a cart's own heading is followed (%.1f deg)" % rad_to_deg(cam.yaw))
	cam.queue_free()


## Diagnostics keep a small, bounded stick trace (numbers only).
func test_diagnostics_stick_trace_is_bounded() -> void:
	var was: bool = Diag.enabled
	Diag.set_enabled(true)
	Diag.clear()
	for gesture in 20:
		for i in 400:
			Diag.stick_tick(1.0 / 60.0, true, Vector2(91, -91), Vector2(0.1, 1.0), Vector2(0.0, 1.0), 0.0, 0.0, 0.0, Vector3(0, 0, -7.4), 0)
		Diag.stick_tick(1.0 / 60.0, false, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, 0.0, 0.0, 0.0, Vector3.ZERO, 0)
	var s: String = Diag.summary()
	t.check(s.contains("Move stick, last gestures"), "the summary has the stick table")
	var rows := 0
	var samples := 0
	var section := ""
	for line in s.split("\n"):
		if line.begins_with("Move stick"):
			section = "g"
		elif line.begins_with("Newest gesture"):
			section = "s"
		elif not line.begins_with("  "):
			section = ""
		elif section == "g":
			rows += 1
		elif section == "s":
			samples += 1
	t.eq(rows, Diag.STICK_GESTURES, "at most %d gestures kept" % Diag.STICK_GESTURES)
	t.check(samples <= Diag.STICK_SAMPLES and samples > 0, "and a short sampled trace (%d lines)" % samples)
	Diag.clear()
	Diag.set_enabled(was)
