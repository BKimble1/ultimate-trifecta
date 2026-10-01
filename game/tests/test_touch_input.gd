extends RefCounted
## Touch ownership / cancellation (TouchRouter) and look normalisation.
## Each test is one of the brief's interaction cases, driven with synthetic
## pointer events in canvas units on a 1558x720 (phone landscape) canvas.
var t

const JUMP := Vector2(1450, 610)
const GAS := Vector2(1450, 600)
const BRAKE := Vector2(1290, 640)


func _router() -> TouchRouter:
	var r := TouchRouter.new()
	r.view_size = Vector2(1558, 720)
	r.set_buttons({"jump": {"c": JUMP, "r": 74.0}})
	return r


func test_walk_drag_and_jump_together() -> void:
	var r := _router()
	r.touch_down(0, Vector2(250, 520))             # left thumb: stick
	r.drag(0, Vector2(250, 440), Vector2(0, -80))  # push forward
	r.touch_down(1, Vector2(1000, 300))            # right thumb: camera
	r.drag(1, Vector2(1040, 300), Vector2(120, 0))
	r.touch_down(2, JUMP)                          # third finger: jump
	var mv := r.move_vector()
	t.check(mv.y > 0.7 and absf(mv.x) < 0.05, "stick moves forward while other fingers act (%s)" % str(mv))
	t.eq(r.take_look_px(), Vector2(120, 0), "camera drag accumulates unscaled pixels")
	t.check(r.is_held("jump"), "jump held")
	t.eq(r.take_edges(), ["jump"] as Array[String], "one jump press edge")
	t.eq(r.take_edges().size(), 0, "edges are consumed once")


func test_second_finger_in_stick_zone_never_moves() -> void:
	var r := _router()
	r.touch_down(0, Vector2(250, 520))
	r.drag(0, Vector2(330, 520), Vector2(80, 0))
	var before := r.move_vector()
	r.touch_down(1, Vector2(300, 400))             # also in the stick zone
	r.drag(1, Vector2(150, 300), Vector2(-150, -100))
	t.eq(r.stick_index, 0, "the first finger keeps the stick")
	t.eq(r.move_vector(), before, "second finger does not move the character")
	t.eq(r.take_look_px(), Vector2(-150, -100), "second finger becomes a camera drag")
	r.touch_up(1)
	t.eq(r.stick_index, 0, "lifting the second finger leaves the stick alone")


func test_sliding_action_finger_keeps_its_button() -> void:
	var r := _router()
	r.touch_down(5, JUMP)
	r.drag(5, Vector2(900, 200), Vector2(-500, -400))
	t.check(r.is_held("jump"), "a finger that slides off Jump still owns Jump")
	t.eq(r.take_look_px(), Vector2.ZERO, "sliding an action finger never turns the camera")
	t.check(not r.stick_active(), "and never grabs the stick")
	r.touch_up(5)
	t.check(not r.is_held("jump"), "lifting releases Jump")


func test_rapid_jump_then_dive_are_two_ticks() -> void:
	var r := _router()
	r.touch_down(0, JUMP)
	r.touch_up(0)
	r.touch_down(1, JUMP)      # second tap within the same frame
	r.touch_up(1)
	var edges := r.take_edges()
	t.eq(edges.size(), 2, "both taps are recorded")
	Controls.reset_touch()
	for e in edges:
		Controls.queue_press(TC.BTN_JUMP)
	var first := Controls.consume_pressed()
	var second := Controls.consume_pressed()
	var third := Controls.consume_pressed()
	t.check(first & TC.BTN_JUMP != 0 and second & TC.BTN_JUMP != 0, "jump on one tick, dive press on the next")
	t.eq(third, 0, "no phantom press afterwards")


func test_leaving_cart_while_holding_gas_clears_it() -> void:
	var r := _router()
	r.set_buttons({"gas": {"c": GAS, "r": 78.0}, "brake": {"c": BRAKE, "r": 60.0}})
	r.touch_down(3, GAS)
	t.check(r.is_held("gas"), "gas held in the cart")
	r.set_buttons({"jump": {"c": JUMP, "r": 74.0}})   # hopped out: on-foot layout
	t.check(not r.is_held("gas"), "gas released when its button disappears")
	t.check(not r.is_held("jump"), "the same finger does not become a Jump hold")
	r.drag(3, Vector2(1300, 500), Vector2(-150, -100))
	t.eq(r.take_look_px(), Vector2.ZERO, "and does not turn the camera either")
	t.eq(r.take_edges(), ["gas"] as Array[String], "only the original gas press edge exists")


func test_pause_while_moving_cancels_everything() -> void:
	var r := _router()
	r.touch_down(0, Vector2(250, 520))
	r.drag(0, Vector2(250, 420), Vector2(0, -100))
	r.touch_down(1, JUMP)
	r.cancel_all()                                  # pause menu / app backgrounded
	t.eq(r.move_vector(), Vector2.ZERO, "movement stops on cancel")
	t.check(r.held().is_empty(), "no button stays held")
	r.drag(0, Vector2(250, 300), Vector2(0, -120))  # stale drag from the old finger
	t.eq(r.move_vector(), Vector2.ZERO, "stale drags after cancel are ignored")
	t.eq(r.take_look_px(), Vector2.ZERO, "and do not reach the camera")


func test_resume_after_interruption_works_normally() -> void:
	var r := _router()
	r.touch_down(0, Vector2(250, 520))
	r.cancel_all()
	r.touch_up(0)                                   # lift arriving after the cancel is harmless
	r.touch_down(4, Vector2(260, 500))
	r.drag(4, Vector2(340, 500), Vector2(80, 0))
	t.check(r.move_vector().x > 0.6, "a fresh touch after resuming drives the stick again")


func test_dead_zone_sneak_and_no_diagonal_boost() -> void:
	var r := _router()
	r.touch_down(0, Vector2(400, 500))
	var c := r.stick_center
	r.drag(0, c + Vector2(6, 0), Vector2(6, 0))
	t.eq(r.move_vector(), Vector2.ZERO, "inside the radial dead zone: no movement")
	r.drag(0, c + Vector2(0, -0.4 * r.stick_radius), Vector2.ZERO)
	var sneak := r.move_vector().length()
	t.check(sneak > 0.25 and sneak < r.dead_zone + 0.4, "partial deflection stays a sneak (%.2f)" % sneak)
	r.drag(0, c + Vector2(200, -200), Vector2.ZERO)
	t.check(r.move_vector().length() <= 1.0001, "diagonal at the rim is not faster than straight")
	t.near(r.move_vector().length(), 1.0, 0.001, "full deflection reaches 1")


func test_sprint_hysteresis() -> void:
	var r := _router()
	r.touch_down(0, Vector2(400, 500))
	var c := r.stick_center
	var R := r.stick_radius
	r.drag(0, c + Vector2(0, -0.92 * R), Vector2.ZERO)
	r.move_vector()
	t.check(r.sprinting, "edge of the stick starts a sprint")
	r.drag(0, c + Vector2(0, -0.8 * R), Vector2.ZERO)
	r.move_vector()
	t.check(r.sprinting, "small wobble below the edge keeps sprinting (hysteresis)")
	r.drag(0, c + Vector2(0, -0.6 * R), Vector2.ZERO)
	r.move_vector()
	t.check(not r.sprinting, "clearly easing off stops the sprint")


func test_dynamic_stick_spawn_is_clamped_and_fixed_stick_option() -> void:
	var r := _router()
	r.touch_down(0, Vector2(4, 715))
	t.check(r.stick_center.x >= r.stick_radius and r.stick_center.y <= 720 - r.stick_radius, "stick ring stays on screen (%s)" % str(r.stick_center))
	r.cancel_all()
	r.fixed_stick = true
	r.fixed_center = Vector2(210, 560)
	r.touch_down(1, Vector2(120, 420))
	t.eq(r.stick_center, Vector2(210, 560), "fixed stick option uses its fixed centre")


func test_reserved_regions_never_start_stick_or_camera() -> void:
	var r := _router()
	r.reserved = [Rect2(Vector2(1460, 20), Vector2(80, 80))]   # pause button
	r.touch_down(0, Vector2(1490, 50))
	r.drag(0, Vector2(1300, 120), Vector2(-190, 70))
	t.eq(r.take_look_px(), Vector2.ZERO, "a touch on the pause button never drags the camera")
	t.check(not r.stick_active(), "or moves the character")


func test_look_is_displacement_not_rate() -> void:
	Controls.reset_touch()
	Controls.sensitivity = 1.0
	Controls.invert_y = false
	Controls.touch_look_px = Vector2(300, 0)
	var a := Controls.consume_look(1.0 / 30.0)
	Controls.touch_look_px = Vector2(300, 0)
	var b := Controls.consume_look(1.0 / 120.0)
	t.near(a.x, b.x, 0.0001, "the same finger travel turns the same angle at any frame rate")
	var pts := 300.0 / maxf(1.0, DisplayServer.screen_get_scale())
	t.near(a.x, pts * Controls.TOUCH_RAD_PER_PT, 0.0001, "radians = points x TOUCH_RAD_PER_PT")


func test_controller_takeover_and_focus_loss_release_touch_intent() -> void:
	var s := TouchControls.TouchSurface.new()
	s.router.view_size = Vector2(1558, 720)
	s.router.set_buttons({"gas": {"c": GAS, "r": 74.0}})
	for kind in ["gamepad", "focus"]:
		s.router.touch_down(0, Vector2(250, 520))   # steering thumb
		s.router.drag(0, Vector2(330, 520), Vector2(80, 0))
		s.router.touch_down(1, GAS)                  # gas held
		Controls.touch_move = s.router.move_vector()
		Controls.touch_drive = 1.0
		Controls.touch_sprint = true
		if kind == "gamepad":
			s._on_device("gamepad")                  # a controller takes over mid-drive
		else:
			s._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		t.check(s.router.held().is_empty() and s.router.move_vector() == Vector2.ZERO, "%s: no finger keeps an owner" % kind)
		t.check(Controls.touch_move == Vector2.ZERO and Controls.touch_drive == 0.0 and not Controls.touch_sprint,
			"%s: no stuck stick, gas or sprint" % kind)
		s.router.touch_up(0)
		s.router.touch_up(1)
	s._on_device("touch")                            # back to touch: fresh fingers work
	s.router.touch_down(5, Vector2(260, 500))
	s.router.drag(5, Vector2(340, 500), Vector2(80, 0))
	t.check(s.router.move_vector().x > 0.6, "touch works again after switching back")
	s.free()
	Controls.reset_touch()
