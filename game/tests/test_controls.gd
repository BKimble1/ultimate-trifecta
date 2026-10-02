extends RefCounted
## Controller / keyboard / touch input parity: every source feeds one
## ordered, bounded, expiring press queue (rapid jump-then-dive is never
## merged on any device), text fields and menus don't leak gameplay presses,
## stick drift can't steal movement or flip prompts while a finger is down,
## stick curves are predictable, and prompts follow the controller family.
var t
var _saved: Dictionary


func _begin() -> void:
	_saved = {"device": Controls.device, "joy": Controls.active_joy, "family": Controls.family, "name": Controls.controller_name}
	Controls.reset_touch()
	Controls.set_touch_points(0)


func _end() -> void:
	Controls.clear_edges()
	Controls.reset_touch()
	Controls.set_touch_points(0)
	Controls.device = _saved["device"]
	Controls.active_joy = _saved["joy"]
	Controls.family = _saved["family"]
	Controls.controller_name = _saved["name"]


func _key(code: Key, pressed: bool = true) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	return e


func _pad(button: JoyButton, pressed: bool = true, dev: int = 0) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = pressed
	e.device = dev
	return e


func _axis(axis: JoyAxis, v: float, dev: int = 0) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = v
	e.device = dev
	return e


func _ticks(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append(Controls.consume_pressed())
	return out


func test_rapid_jump_then_dive_is_two_presses_on_every_device() -> void:
	_begin()
	# keyboard: two Space taps between ticks
	for e in [_key(KEY_SPACE), _key(KEY_SPACE, false), _key(KEY_SPACE), _key(KEY_SPACE, false)]:
		Controls._input(e)
	t.eq(_ticks(3), [TC.BTN_JUMP, TC.BTN_JUMP, 0], "keyboard: jump, then dive on the next tick")
	# controller: two A presses between ticks
	for e in [_pad(JOY_BUTTON_A), _pad(JOY_BUTTON_A, false), _pad(JOY_BUTTON_A), _pad(JOY_BUTTON_A, false)]:
		Controls._input(e)
	t.eq(_ticks(3), [TC.BTN_JUMP, TC.BTN_JUMP, 0], "controller: jump, then dive on the next tick")
	# touch taps use the same queue
	Controls.queue_press(TC.BTN_JUMP)
	Controls.queue_press(TC.BTN_JUMP)
	t.eq(_ticks(3), [TC.BTN_JUMP, TC.BTN_JUMP, 0], "touch: same behaviour")
	_end()


func test_mixed_sources_keep_arrival_order() -> void:
	_begin()
	Controls.queue_press(TC.BTN_JUMP)             # touch
	Controls._input(_key(KEY_F))                  # keyboard tag
	Controls._input(_pad(JOY_BUTTON_A))           # controller jump (a second jump)
	Controls._input(_pad(JOY_BUTTON_Y))           # controller interact
	t.eq(_ticks(3), [TC.BTN_JUMP | TC.BTN_TAG, TC.BTN_JUMP | TC.BTN_INTERACT, 0],
		"different actions share a tick; a repeated action waits for the next one")
	_end()


func test_queue_is_bounded_and_stale_presses_expire() -> void:
	_begin()
	for i in 30:
		Controls.push_edge(TC.BTN_JUMP)
	t.check(Controls.pending_edges() <= Controls.MAX_EDGES, "queue is bounded")
	Controls.clear_edges()
	Controls.push_edge(TC.BTN_TAG)
	Controls._edges[0]["ms"] = Time.get_ticks_msec() - Controls.EDGE_TTL_MS - 50
	t.eq(Controls.consume_pressed(), 0, "a press older than the TTL never fires (menus, hitches)")
	Controls.push_edge(TC.BTN_GADGET)
	Controls.reset_touch()
	t.eq(Controls.consume_pressed(), 0, "reset (scene change / pause / cancel) clears every source")
	_end()


func test_text_fields_and_pause_do_not_leak_presses() -> void:
	_begin()
	var le := LineEdit.new()
	t.add_child(le)
	le.grab_focus()
	await t.get_tree().process_frame
	Controls._input(_key(KEY_SPACE))
	Controls._input(_key(KEY_E))
	t.eq(Controls.consume_pressed(), 0, "typing in a text field presses nothing in play")
	le.queue_free()
	await t.get_tree().process_frame
	Controls._input(_key(KEY_SPACE))
	t.eq(Controls.consume_pressed(), TC.BTN_JUMP, "keys work again once the field is gone")
	_end()


func test_drift_cannot_fight_touch_or_flip_prompts() -> void:
	_begin()
	Controls.device = "touch"
	Controls.active_joy = 0
	Controls._last_switch_ms = 0
	Controls.set_touch_points(1)
	Controls._input(_axis(JOY_AXIS_LEFT_X, 0.8))
	t.eq(Controls.device, "touch", "stick motion while a finger is down never takes over")
	Controls.touch_move = Vector2(0.2, 0.3)
	t.eq(Controls.get_move(), Vector2(0.2, 0.3), "the touch stick owns movement while held")
	Controls.touch_move = Vector2.ZERO
	Controls.set_touch_points(0)
	Controls._input(_axis(JOY_AXIS_LEFT_X, 0.3))
	t.eq(Controls.device, "touch", "small drift never switches device")
	Controls._input(_axis(JOY_AXIS_LEFT_X, 0.8))
	t.eq(Controls.device, "gamepad", "a deliberate push switches to the controller")
	Controls._input(InputEventScreenTouch.new())
	t.eq(Controls.device, "touch", "a touch switches straight back")
	Controls._input(_axis(JOY_AXIS_LEFT_X, 0.9))
	t.eq(Controls.device, "touch", "stick motion can't flip it again within the hold time")
	Controls._input(_pad(JOY_BUTTON_B))
	t.eq(Controls.device, "gamepad", "a button press switches at once")
	Controls._input(_pad(JOY_BUTTON_X, true, 3))
	t.eq(Controls.active_joy, 3, "the pad that pressed a button becomes the active one")
	_end()


func test_stick_curves() -> void:
	_begin()
	t.eq(InputRouter.radial(Vector2(0.1, 0.05), 0.15, 0.95), Vector2.ZERO, "inner radial dead zone")
	t.near(InputRouter.radial(Vector2(0.0, 0.96), 0.15, 0.95).length(), 1.0, 1e-6, "outer dead zone reaches full tilt")
	var d := InputRouter.radial(Vector2(0.4, 0.4), 0.15, 0.95)
	t.near(d.angle(), Vector2(1, 1).angle(), 1e-6, "direction kept")
	t.near(InputRouter.move_curve(1.0), 1.0, 1e-6, "full tilt = full speed")
	var prev := -1.0
	var mono := true
	for i in 21:
		var v := InputRouter.move_curve(i / 20.0)
		mono = mono and v >= prev
		prev = v
	t.check(mono, "move curve is monotonic")
	t.check(InputRouter.move_curve(0.5) < 0.5 and InputRouter.move_curve(0.5) > 0.4, "half tilt walks a little slower than linear")
	t.eq(Controls.stick_look(Vector2(0.1, 0.0), 1.0 / 60.0), Vector2.ZERO, "look dead zone")
	var first := Controls.stick_look(Vector2(1.0, 0.0), 1.0 / 60.0).x
	for i in 60:
		Controls.stick_look(Vector2(1.0, 0.0), 1.0 / 60.0)
	var held := Controls.stick_look(Vector2(1.0, 0.0), 1.0 / 60.0).x
	t.near(held / first, Controls.LOOK_BOOST, 0.01, "holding full tilt ramps to the faster turn")
	t.check(Controls.stick_look(Vector2(0.5, 0.0), 1.0 / 60.0).x < first * 0.5, "expo curve: half tilt turns well under half speed")
	_end()


func test_prompts_follow_the_controller_family() -> void:
	_begin()
	t.eq(InputRouter.family_of("Xbox Wireless Controller"), "xbox", "Xbox")
	t.eq(InputRouter.family_of("DualSense Wireless Controller"), "playstation", "DualSense")
	t.eq(InputRouter.family_of("DUALSHOCK 4 Wireless Controller"), "playstation", "DualShock 4")
	t.eq(InputRouter.family_of("Wireless Controller", {"vendor_id": 0x054c}), "playstation", "Sony by USB vendor")
	t.eq(InputRouter.family_of("Pro Controller"), "nintendo", "Switch Pro")
	t.eq(InputRouter.family_of("Backbone One"), "mfi", "MFi")
	t.eq(InputRouter.family_of("Gamepad 1"), "generic", "unknown")
	Controls.device = "gamepad"
	var expect := {"xbox": ["A", "LB", "RT"], "playstation": ["Cross", "L1", "R2"], "mfi": ["A", "L1", "R2"],
		"nintendo": ["Bottom button", "L", "ZR"], "generic": ["Bottom button", "L1", "R2"]}
	for fam in expect:
		Controls.family = fam
		t.eq([Controls.prompt("jump"), Controls.prompt("sprint"), Controls.prompt("accelerate")], expect[fam], "%s prompts" % fam)
	Controls.device = "keyboard"
	t.eq(Controls.prompt("jump"), "Space", "keyboard prompt")
	Controls.device = "touch"
	t.eq(Controls.prompt("jump"), "", "no prompt on touch (the buttons are the prompt)")
	_end()


func test_disconnect_and_backgrounding_clear_presses() -> void:
	_begin()
	Controls.active_joy = 5
	Controls.push_edge(TC.BTN_JUMP)
	Controls._on_joy(5, false)
	t.eq(Controls.pending_edges(), 0, "controller disconnect drops queued presses")
	t.eq(Controls.active_joy, -1 if Input.get_connected_joypads().is_empty() else Controls.active_joy, "active pad released")
	Controls.push_edge(TC.BTN_TAG)
	Controls._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	t.eq(Controls.consume_pressed(), 0, "backgrounding drops queued presses")
	_end()


func test_hud_splash_feed_coalesces_and_survives_freed_lines() -> void:
	var hud := MatchHUD.new()
	hud.feed_box = VBoxContainer.new()
	t.add_child(hud.feed_box)
	hud.feed_splash("Yawn", "Pool", TC.Role.RUNNER)
	hud.feed_splash("Snooze", "Pool", TC.Role.RUNNER)
	hud.feed_splash("Pillow", "Pool", TC.Role.RUNNER)
	t.eq(hud.feed_box.get_child_count(), 1, "splashes into the same water share one line")
	var line := (hud.feed_box.get_child(0) as PanelContainer).get_child(0) as Label
	t.eq(line.text, "Yawn, Snooze +1 splashed into Pool", "names coalesced")
	hud.feed_splash("Moonbeam", "Quarry", TC.Role.RUNNER)
	t.eq(hud.feed_box.get_child_count(), 2, "a different water gets its own line")
	# the Pool line is pushed out and freed; the next Pool splash starts a new line
	for c in hud.feed_box.get_children():
		hud.feed_box.remove_child(c)
		c.free()
	hud.feed_splash("Drowsy", "Pool", TC.Role.RUNNER)
	t.eq(hud.feed_box.get_child_count(), 1, "a freed line is never reused (no error, new line)")
	hud.feed_box.queue_free()
	hud.free()
