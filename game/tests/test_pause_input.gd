extends RefCounted
## V7: Pause, Resume and Leave through real input.  Touches are parsed by
## Input exactly as iOS delivers them (InputEventScreenTouch/ScreenDrag with
## finger indexes; the engine emulates the mouse from the first finger only)
## and land at the controls' actual rendered positions.  Directly calling
## _toggle_pause() or emitting pressed proves nothing here.
var t
var _saved := {}


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


func _touch(i: int, at: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = at
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _drag(i: int, from: Vector2, to: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = i
	e.position = to
	e.relative = to - from
	e.screen_relative = to - from
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _tap(i: int, at: Vector2) -> void:
	_touch(i, at, true)
	await _frames(2)
	_touch(i, at, false)
	await _frames(3)


func _begin(mirrored := false, role := "runner") -> MatchController:
	_saved = {"device": Controls.device, "size": t.get_tree().root.size, "emu": Input.emulate_touch_from_mouse,
		"layout": Save.get_setting("touch_layout", "standard"), "layout2": Save.get_setting("touch_layout_v2", null)}
	# the profile is shared with other test runs: say which layout we mean
	Save.set_setting("touch_layout", "mirrored" if mirrored else "standard")
	Save.set_setting("touch_layout_v2", null)
	Controls.device = "touch"
	Input.emulate_touch_from_mouse = false
	t.get_tree().root.size = Vector2i(1280, 720)
	t.get_tree().root.notification(Window.NOTIFICATION_WM_MOUSE_ENTER)
	for c in t.get_tree().root.get_children():
		if c is BootCurtain:
			c.queue_free()
	# during a round App shows no screen (the loading screen has gone); the
	# test process may still have Home up on App's layer 10
	if App.screen and is_instance_valid(App.screen):
		App.screen.queue_free()
	App.screen = null
	MatchController.drop_campus_cache()
	var s := NetSession.new()
	t.add_child(s)
	s.start_offline("u-pause", "Tester", {}, role)
	var info := {}
	s.match_starting.connect(func(i: Dictionary) -> void: info.merge(i, true), CONNECT_ONE_SHOT)
	s.host_start_match(4242)
	var mc := MatchController.new()
	mc.setup(s, info, {"quality": 0, "staged": false})
	t.add_child(mc)
	await _frames(6)
	return mc


func _end(mc: MatchController) -> void:
	var s: Variant = mc.session
	mc.queue_free()
	if is_instance_valid(s):
		(s as Node).queue_free()
	await _frames(2)
	MatchController.drop_campus_cache()
	Controls.device = _saved["device"]
	Input.emulate_touch_from_mouse = _saved["emu"]
	Save.set_setting("touch_layout", _saved["layout"])
	Save.set_setting("touch_layout_v2", _saved["layout2"])
	t.get_tree().root.size = _saved["size"]


func _center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


func test_pause_with_one_finger() -> void:
	var mc := await _begin()
	t.check(mc.prepared, "practice round prepared")
	await _tap(0, _center(mc.hud.pause_btn))
	t.check(mc.hud.paused(), "a single tap on Pause opens the menu")
	await _end(mc)


func test_pause_while_another_finger_moves() -> void:
	var mc := await _begin()
	var stick := Vector2(220, 520)
	_touch(0, stick, true)
	await _frames(2)
	_drag(0, stick, stick + Vector2(60, -30))
	await _frames(2)
	t.check(Controls.touch_move.length() > 0.1, "the first finger is moving the runner")
	await _tap(1, _center(mc.hud.pause_btn))
	t.check(mc.hud.paused(), "a second finger's tap on Pause opens the menu")
	t.check(Controls.touch_move.length() < 0.01, "and the moving finger no longer moves the runner")
	_touch(0, stick + Vector2(60, -30), false)
	await _frames(2)
	await _end(mc)


func test_menu_buttons_take_taps() -> void:
	var mc := await _begin()
	await _tap(0, _center(mc.hud.pause_btn))
	t.check(mc.hud.paused(), "menu open")
	await _frames(2)
	await _tap(0, _center(mc.hud.resume_button()))
	t.check(not mc.hud.paused(), "a tap on Resume closes the menu")
	await _tap(0, _center(mc.hud.pause_btn))
	await _frames(2)
	var quit := [0]
	mc.quit_requested.connect(func() -> void: quit[0] += 1)
	await _tap(0, _center(mc.hud.leave_button()))
	t.check(mc.hud.confirming_leave() or quit[0] == 1, "a tap on Leave match reaches the leave flow")
	await _end(mc)


func _slider_drag(sl: HSlider, frac_from: float, frac_to: float) -> void:
	var r := sl.get_global_rect()
	var a := Vector2(r.position.x + r.size.x * frac_from, r.get_center().y)
	var b := Vector2(r.position.x + r.size.x * frac_to, r.get_center().y)
	_touch(0, a, true)
	await _frames(1)
	_drag(0, a, b)
	await _frames(1)
	_touch(0, b, false)
	await _frames(2)


## Practice really pauses: the sim, the round clock and the bots stand
## still for as long as the menu is open, and pick up exactly where they
## were (no catch-up jump) on Resume.
func test_practice_freezes_and_resumes_without_a_jump() -> void:
	var mc := await _begin()
	await t.get_tree().physics_frame
	await _frames(10)
	var tick0: int = mc.sim.tick
	await _tap(0, _center(mc.hud.pause_btn))
	t.check(mc.hud.paused() and mc.hud.game_frozen() and t.get_tree().paused, "Practice: the menu pauses the round")
	var frozen_at: int = mc.sim.tick
	var bots := {}
	for p: SimPlayer in mc.sim.players:
		bots[p.id] = p.body.global_position if p.body != null else Vector3.ZERO
	for i in 120:
		await t.get_tree().physics_frame
	t.eq(mc.sim.tick, frozen_at, "the round clock stands still while paused (two seconds of frames)")
	var moved := 0
	for p: SimPlayer in mc.sim.players:
		if p.body != null and p.body.global_position.distance_to(bots[p.id]) > 0.001:
			moved += 1
	t.eq(moved, 0, "no player or bot moves while paused")
	t.check(frozen_at >= tick0, "it had been running (%d -> %d)" % [tick0, frozen_at])
	await _tap(0, _center(mc.hud.resume_button()))
	t.check(not t.get_tree().paused and not mc.hud.paused(), "Resume unpauses")
	var before: int = mc.sim.tick
	await t.get_tree().physics_frame
	await t.get_tree().physics_frame
	var step: int = mc.sim.tick - before
	t.check(step >= 1 and step <= 2 * Engine.max_physics_steps_per_frame, "it continues from the same tick, no catch-up jump (%d ticks in 2 frames)" % step)
	await _end(mc)


## Twenty times: open -> adjust the camera slider -> Resume, and
## open -> Leave -> Stay; every action fires once; then Leave for real.
func test_twenty_cycles_then_leave() -> void:
	var mc := await _begin()
	var hud: MatchHUD = mc.hud
	var sens0 := Controls.sensitivity
	# start from the default: the last drag ends on 1.2, which an earlier,
	# interrupted run may have left saved, and then nothing would move
	Controls.sensitivity = 1.0
	var quits := [0]
	mc.quit_requested.connect(func() -> void: quits[0] += 1)
	for i in 20:
		await _tap(0, _center(hud.pause_btn))
		await _slider_drag(hud.pause_panel.get_meta("slider") as HSlider, 0.3, 0.6 if i % 2 == 0 else 0.4)
		await _tap(0, _center(hud.resume_button()))
		await _tap(0, _center(hud.pause_btn))
		await _tap(0, _center(hud.leave_button()))
		if i == 0 or i == 19:
			t.check(hud.confirming_leave(), "cycle %d: Leave asks first" % i)
		await _tap(0, _center(hud.cancel_leave_button()))
		await _tap(0, _center(hud.resume_button()))
	t.eq(hud.pause_opens, 40, "40 opens, each once")
	t.eq(hud.pause_closes, 40, "40 closes, each once")
	t.eq(quits[0], 0, "Stay never leaves")
	t.check(not t.get_tree().paused and hud.overlays().is_empty() and mc.touch.visible, "back in the round: unpaused, no overlay, touch controls back")
	t.check(absf(Controls.sensitivity - 1.0) > 0.01, "the camera slider took the finger")
	Controls.sensitivity = sens0
	Save.set_setting("sensitivity", sens0)
	# leave for real: once, even if tapped twice
	await _tap(0, _center(hud.pause_btn))
	await _tap(0, _center(hud.leave_button()))
	var go := _center(hud.confirm_leave_button())
	await _tap(0, go)
	await _tap(0, go)
	t.eq(quits[0], 1, "Leave fires once")
	t.check(not t.get_tree().paused, "and the tree is unpaused for the next screen")
	await _end(mc)
	# and a new match starts normally
	var mc2 := await _begin()
	t.check(mc2.prepared and not t.get_tree().paused and mc2.touch.visible, "the next match starts unpaused with touch controls")
	await _tap(0, _center(mc2.hud.pause_btn))
	t.check(mc2.hud.paused(), "and its Pause works")
	await _tap(0, _center(mc2.hud.resume_button()))
	await _end(mc2)


## A finger held from before the menu doesn't move the runner after Resume;
## a fresh gesture does.  Resume's own press never becomes a jump.
func test_no_stale_finger_or_jump_after_resume() -> void:
	var mc := await _begin()
	var stick := Vector2(220, 520)
	_touch(0, stick, true)
	await _frames(2)
	_drag(0, stick, stick + Vector2(40, 0))
	await _frames(2)
	await _tap(1, _center(mc.hud.pause_btn))
	await _tap(2, _center(mc.hud.resume_button()))
	_drag(0, stick + Vector2(40, 0), stick + Vector2(90, 0))
	await _frames(3)
	t.check(Controls.touch_move.length() < 0.01, "the finger held from before the menu doesn't move the runner")
	t.eq(Controls.touch_held, 0, "nothing is held")
	_touch(0, stick + Vector2(90, 0), false)
	await _frames(2)
	_touch(3, stick, true)
	await _frames(1)
	_drag(3, stick, stick + Vector2(60, 0))
	await _frames(2)
	t.check(Controls.touch_move.length() > 0.1, "a fresh gesture moves it")
	_touch(3, stick + Vector2(60, 0), false)
	await _frames(2)
	await _end(mc)


## Map and Pause, one overlay at a time (V7 policy: gameplay < map or chat
## drawer < pause menu < leave confirmation; the top one owns input, Back
## closes it, and closing one never brings the controls back under another).
## The map opens from a second finger's tap on the minimap while the first
## steers; it covers Pause, so a tap there does nothing underneath; Close
## brings the round back, and Pause then opens normally.  The pause key over
## the map closes the map first.  The app going to the background pauses
## Practice.
func test_map_pause_background() -> void:
	var mc := await _begin()
	var hud: MatchHUD = mc.hud
	var stick := Vector2(220, 520)
	_touch(0, stick, true)
	await _frames(2)
	_drag(0, stick, stick + Vector2(50, 0))
	await _frames(2)
	await _tap(1, _center(hud.minimap))
	t.check(hud.map_view != null, "a second finger's tap on the minimap opens the map")
	t.check(not mc.touch.visible and Controls.touch_move.length() < 0.01, "the map hides gameplay touch and stops the runner")
	_touch(0, stick + Vector2(50, 0), false)
	await _frames(2)
	await _tap(0, _center(hud.pause_btn))
	t.check(not hud.paused() and hud.map_view != null, "the map covers Pause: a tap there reaches nothing beneath it")
	t.check(not mc.touch.visible and Controls.touch_held == 0, "and starts no gameplay input")
	await _tap(0, _center(hud.map_view.close_btn))
	t.check(hud.map_view == null and mc.touch.visible and hud.overlays().is_empty(), "Close: back to the round")
	await _tap(0, _center(hud.pause_btn))
	t.check(hud.paused(), "then Pause opens")
	await _tap(0, _center(hud.resume_button()))
	# controller / keyboard: pause over the map closes the map, then pauses
	hud.open_map()
	await _frames(2)
	await _action("pause")
	t.check(hud.map_view == null and not hud.paused(), "the pause key over the map closes the map")
	t.check(mc.touch.visible, "and the controls come back")
	await _action("pause")
	t.check(hud.paused() and not mc.touch.visible, "the pause key then opens the menu")
	await _tap(0, _center(hud.leave_button()))
	await _action("ui_cancel")
	t.check(hud.paused() and not hud.confirming_leave(), "Back from the confirmation returns to the menu")
	await _action("ui_cancel")
	t.check(not hud.paused() and mc.touch.visible and hud.overlays().is_empty(), "Back from the menu returns to the round")
	hud.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	await _frames(2)
	t.check(hud.paused() and t.get_tree().paused, "the app going to the background pauses Practice")
	hud.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await _frames(3)
	t.check(hud.paused() and t.get_tree().paused, "and coming back leaves it paused until you choose")
	await _tap(0, _center(hud.resume_button()))
	t.check(not t.get_tree().paused, "Resume")
	await _end(mc)


func _action(a: String) -> void:
	var e := InputEventAction.new()
	e.action = a
	e.pressed = true
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	await _frames(2)
	var u := InputEventAction.new()
	u.action = a
	u.pressed = false
	Input.parse_input_event(u)
	Input.flush_buffered_events()
	await _frames(2)


## Night Watch in a cart: holding Gas with one finger, a second finger's tap
## on Pause opens the menu and releases the throttle; after Resume the cart
## doesn't drive on until Gas is pressed again.  On foot, Tag can't fire from
## the Resume tap.
func test_night_watch_cart_and_tag() -> void:
	var mc := await _begin(false, "patrol")
	t.eq(int(mc.hud.info.get("role", -1)), TC.Role.PATROL, "Practice as Night Watch")
	var sim: MatchSim = mc.sim
	var p := sim.player(mc.local_slot)
	var c: SimCart = sim.carts[0]
	c.occupant = p.id
	p.cart_id = c.id
	Motor.set_body_enabled(p.body, false)
	sim._set_state(p, TC.PState.IN_CART)
	await _frames(4)
	var gas: Dictionary = mc.touch.surface.router.buttons.get("gas", {})
	t.check(not gas.is_empty(), "the cart controls are up")
	if gas.is_empty():
		await _end(mc)
		return
	_touch(0, gas["c"], true)
	await _frames(2)
	t.eq(Controls.touch_drive, 1.0, "holding Gas")
	await _tap(1, _center(mc.hud.pause_btn))
	t.check(mc.hud.paused(), "a second finger's tap on Pause opens the menu over the cart")
	t.eq(Controls.touch_drive, 0.0, "and the throttle is released")
	await _tap(2, _center(mc.hud.resume_button()))
	await _frames(2)
	t.eq(Controls.touch_drive, 0.0, "the finger still on Gas from before doesn't drive on after Resume")
	_touch(0, gas["c"], false)
	await _frames(2)
	_touch(3, gas["c"], true)
	await _frames(2)
	t.eq(Controls.touch_drive, 1.0, "a fresh press drives")
	_touch(3, gas["c"], false)
	await _frames(2)
	await _end(mc)
	# on foot, either role: tapping Resume (or Pause) never queues a Jump or Tag
	for role in ["patrol", "runner"]:
		var m2 := await _begin(false, role)
		var e0 := Controls.edges_pushed
		await _tap(0, _center(m2.hud.pause_btn))
		await _tap(0, _center(m2.hud.resume_button()))
		await _frames(6)
		t.eq(Controls.edges_pushed, e0, "%s: Pause and Resume taps queue no Jump or Tag" % role)
		var jb: Dictionary = m2.touch.surface.router.buttons.get("jump", {})
		if not jb.is_empty():
			await _tap(0, jb["c"])
			t.check(Controls.edges_pushed > e0, "%s: (while a tap on Jump does)" % role)
		await _end(m2)


## Mirrored / custom layouts: Pause keeps its own reserved region (the
## action buttons never sit on it) and the region is exactly the button.
func test_pause_region_matches_the_button_in_every_layout() -> void:
	for mirrored in [false, true]:
		await _region_case(mirrored)


func _region_case(mirrored: bool) -> void:
	var mc := await _begin(mirrored)
	await _frames(3)
	var reserved: Array = mc.touch.surface.router.reserved
	var pr: Rect2 = mc.hud.pause_btn.get_global_rect()
	t.check(reserved.has(pr), "the reserved region is exactly the Pause button")
	var vs: Vector2 = t.get_viewport().get_visible_rect().size
	t.check(Rect2(Vector2.ZERO, vs).encloses(pr), "Pause is on screen")
	t.check(pr.size.x >= UIKit.touch_min() - 0.5, "and at least a 44 pt target")
	for corner in [pr.position + Vector2(3, 3), pr.end - Vector2(3, 3)]:
		await _tap(0, corner)
		t.check(mc.hud.paused(), "a tap near the button's edge opens the menu")
		await _tap(0, _center(mc.hud.resume_button()))
	await _end(mc)
