extends Node
## Development-only evidence (src/dev: never exported): the V7 Pause clips.
## The same scripted taps in a Practice round on the build before V7 (1.5)
## and after: one thumb steers while a second finger taps Pause, the camera
## slider is dragged, Resume; Pause -> Leave match -> Stay -> Resume; Pause ->
## Leave match -> Leave.  Taps are real InputEventScreenTouch/ScreenDrag
## events at the controls' rendered centres (found by their text, so the
## same reel drives both builds), parsed by Input.  Soft rings mark fingers.
## A readout shows whether the menu is open, the round clock and the
## runner's speed; stills of the open menu (and the leave confirmation) are
## saved next to the movie.  Scripted, emulated touches on desktop Linux,
## not device input.
##
##   (tools/capture_v7_reel.sh OUT pause NAME [ROOT] records and labels it)

const FPS := 30.0

var mc: MatchController
var shots_dir := ""
var _layer: CanvasLayer
var _fingers: Control
var _at := {}        # finger index -> [pos, down]
var _caption: Label
var _readout: Label
var _quits := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--reel-stills="):
			shots_dir = a.get_slice("=", 1)
	_layer = CanvasLayer.new()
	_layer.layer = 128
	add_child(_layer)
	_fingers = Control.new()
	_fingers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fingers.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fingers.draw.connect(_draw_fingers)
	_layer.add_child(_fingers)
	_caption = _label(26, Vector2(0, 14))
	_readout = _label(20, Vector2(0, 52))
	_run.call_deferred()


func _label(sz: int, at: Vector2) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_TOP_WIDE)
	l.position = at
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(l)
	return l


func _draw_fingers() -> void:
	for i in _at:
		var p: Vector2 = _at[i][0]
		var down: bool = _at[i][1]
		_fingers.draw_circle(p, 30.0, Color(1, 1, 1, 0.3 if down else 0.1))
		_fingers.draw_arc(p, 30.0, 0.0, TAU, 40, Color(1, 1, 1, 0.85 if down else 0.3), 3.0, true)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
		_update_readout()


## Events arrive in window pixels, as iOS delivers them; the reel's
## positions are canvas units (where the controls are drawn).  The movie's
## window is smaller than the canvas, so convert (identity when equal).
func _win(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p


func _touch(i: int, at: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = _win(at)
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	_at[i] = [at, down]
	_fingers.queue_redraw()


func _drag(i: int, from: Vector2, to: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = i
	e.position = _win(to)
	e.relative = _win(to) - _win(from)
	e.screen_relative = _win(to) - _win(from)
	e.velocity = (_win(to) - _win(from)) * FPS
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	_at[i] = [to, true]
	_fingers.queue_redraw()


func _tap(i: int, at: Vector2) -> void:
	_touch(i, at, true)
	await _frames(3)
	_touch(i, at, false)
	await _frames(int(FPS * 0.6))
	_at.erase(i)
	_fingers.queue_redraw()


## A visible button in the HUD with this text (both builds), else null.
func _button(text: String) -> Button:
	for n in mc.hud.find_children("*", "Button", true, false):
		var b := n as Button
		if b.is_visible_in_tree() and b.text == text:
			return b
	return null


func _slider() -> HSlider:
	for n in mc.hud.find_children("*", "HSlider", true, false):
		if (n as HSlider).is_visible_in_tree():
			return n
	return null


func _menu_open() -> bool:
	return is_instance_valid(mc) and mc.hud and mc.hud.pause_panel != null and mc.hud.pause_panel.visible


func _update_readout() -> void:
	if not is_instance_valid(mc) or mc.sim == null:
		return
	var p := mc.sim.player(mc.local_slot)
	_readout.text = "menu %s   ·   round clock %.1f s   ·   runner %.1f m/s%s" % ["OPEN" if _menu_open() else "closed",
		mc.sim.round_time(), Vector2(p.vel.x, p.vel.z).length(), ("   ·   left the round" if _quits > 0 else "")]


func _shot(name: String) -> void:
	if shots_dir == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots_dir.path_join(name))


func _run() -> void:
	await get_tree().process_frame
	for c in get_tree().root.get_children():
		if c is BootCurtain:
			c.queue_free()
	if App.screen and is_instance_valid(App.screen):
		App.screen.queue_free()
	App.screen = null
	Save.set_setting("touch_layout", "standard")
	Save.set_setting("touch_layout_v2", null)
	Controls.device = "touch"
	printerr("REEL canvas %s, canvas->window %s" % [str(get_viewport().get_visible_rect().size), str(get_viewport().get_final_transform())])
	get_tree().root.notification(Window.NOTIFICATION_WM_MOUSE_ENTER)
	if DisplayServer.get_name() == "headless":
		get_tree().root.size = Vector2i(1560, 720)          # (smoke runs; movies use a 1040x480 window = the same canvas)
	_caption.text = "Preparing a Practice round (not part of the comparison)"
	var s := NetSession.new()
	add_child(s)
	s.start_offline("u-reel", "Runner", {}, "runner")
	var info := {}
	s.match_starting.connect(func(i: Dictionary) -> void: info.merge(i, true), CONNECT_ONE_SHOT)
	s.host_start_match(4242)
	mc = MatchController.new()
	mc.setup(s, info, {"staged": false, "quality": 0})   # Low preset: affordable on llvmpipe
	mc.quit_requested.connect(func() -> void: _quits += 1)
	get_tree().root.add_child(mc)
	for i in 3600:
		await get_tree().process_frame
		if mc.prepared and mc.sim.phase == TC.Phase.PLAYING:
			break
	mc.sim.bots.clear()
	var r: Object = mc.touch.surface.router
	var R: float = r.get("stick_radius")
	var stick: Vector2 = (r.call("zone") as Rect2).get_center()
	# 1: steering with one thumb, a second finger taps Pause
	_caption.text = "1  One thumb steers; a second finger taps Pause"
	_touch(0, stick, true)
	var cur := stick
	for k in 12:
		var to := stick + Vector2(0, -R * float(k + 1) / 12.0)
		_drag(0, cur, to)
		cur = to
		await _frames(1)
	await _frames(int(FPS * 1.2))
	await _tap(1, mc.hud.pause_btn.get_global_rect().get_center())
	await _frames(int(FPS * 0.8))
	await _shot("pause_menu.png")
	# 2: drag the camera slider, then Resume
	_caption.text = "2  Drag the camera slider, then tap Resume (thumb still down)"
	var sl := _slider()
	if sl != null and _menu_open():
		var sr := sl.get_global_rect()
		var a := Vector2(sr.position.x + sr.size.x * 0.3, sr.get_center().y)
		var b := Vector2(sr.position.x + sr.size.x * 0.65, sr.get_center().y)
		_touch(1, a, true)
		await _frames(2)
		var p := a
		for k in 15:
			var q := a.lerp(b, float(k + 1) / 15.0)
			_drag(1, p, q)
			p = q
			await _frames(1)
		_touch(1, b, false)
		_at.erase(1)
		await _frames(int(FPS * 0.5))
	var resume := _button("Resume")
	if resume != null:
		await _tap(1, resume.get_global_rect().get_center())
	else:
		await _tap(1, Vector2(780, 420))   # where 1.5 drew it: shows the tap going nowhere
	await _frames(int(FPS * 1.0))
	_touch(0, cur, false)
	_at.erase(0)
	await _frames(int(FPS * 1.0))
	if _menu_open():
		_caption.text = "(the menu did not take the taps: closing it with the Pause button)"
		await _tap(1, mc.hud.pause_btn.get_global_rect().get_center())
		await _frames(int(FPS * 1.0))
	# 3: Pause -> Leave match -> Stay -> Resume
	_caption.text = "3  Pause, Leave match, then Stay, then Resume"
	await _tap(1, mc.hud.pause_btn.get_global_rect().get_center())
	await _frames(int(FPS * 0.6))
	var leave := _button("Leave match")
	if leave != null:
		await _tap(1, leave.get_global_rect().get_center())
		await _frames(int(FPS * 0.8))
		await _shot("leave_confirm.png")
		var stay := _button("Stay")
		if stay != null:
			await _tap(1, stay.get_global_rect().get_center())
			await _frames(int(FPS * 0.6))
	resume = _button("Resume")
	if resume != null and _quits == 0:
		await _tap(1, resume.get_global_rect().get_center())
	await _frames(int(FPS * 1.2))
	if _quits == 0:
		# 4: Pause -> Leave match -> Leave
		_caption.text = "4  Pause, Leave match, Leave"
		if not _menu_open():
			await _tap(1, mc.hud.pause_btn.get_global_rect().get_center())
		await _frames(int(FPS * 0.6))
		leave = _button("Leave match")
		if leave != null:
			await _tap(1, leave.get_global_rect().get_center())
			await _frames(int(FPS * 0.8))
			var go := _button("Leave")
			if go != null:
				await _tap(1, go.get_global_rect().get_center())
	await _frames(int(FPS * 1.5))
	printerr("REEL pause: quits=%d menu_open_at_end=%s" % [_quits, _menu_open()])
	_caption.text = "End"
	await _frames(int(FPS * 0.5))
	get_tree().quit()
