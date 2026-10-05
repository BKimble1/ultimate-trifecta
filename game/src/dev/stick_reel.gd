extends Node
## Development-only evidence (src/dev: never exported): the V7 forward-drift
## clips.  The same scripted thumb gestures on the same clear straight of the
## campus in a Practice round, run on the build before the fix and after it,
## recorded with Godot's Movie Maker at a fixed 30 fps clock (normal speed).
##
## Gestures are real InputEventScreenTouch / InputEventScreenDrag events,
## parsed by Input, so they travel TouchControls -> Controls -> the match
## command -> the simulation and the real follow camera.  A soft ring marks
## the finger and a cross where it touched down.  Bots stand still and
## nothing is parked on the straight.  These are scripted, emulated touches
## on desktop Linux, not device input.
##
##   tools/gd.sh --path game --resolution 1560x720 --write-movie OUT.avi --fixed-fps 30 \
##     res://src/dev/stick_reel.tscn -- --emulate-phone=1.92 --no-gamecenter
## (tools/capture_v7_reel.sh OUT stick NAME [ROOT] records and labels it.)

const FPS := 30.0
const Round := preload("res://tests/test_stick_round.gd")

var mc: MatchController
var corridor := {}
var _layer: CanvasLayer
var _finger: Control
var _finger_at := Vector2(-100, -100)
var _finger_down := false
var _touch_at := Vector2(-100, -100)
var _caption: Label
var _readout: Label
var _cam0 := 0.0
var _p0 := Vector3.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.layer = 128
	add_child(_layer)
	_finger = Control.new()
	_finger.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_finger.set_anchors_preset(Control.PRESET_FULL_RECT)
	_finger.draw.connect(_draw_finger)
	_layer.add_child(_finger)
	_caption = _label(26, Vector2(0, 18))
	_readout = _label(20, Vector2(0, 58))
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


func _draw_finger() -> void:
	if _touch_at.x >= 0.0:
		var c := Color(1.0, 0.85, 0.3, 0.9)
		_finger.draw_line(_touch_at - Vector2(10, 10), _touch_at + Vector2(10, 10), c, 3.0)
		_finger.draw_line(_touch_at - Vector2(10, -10), _touch_at + Vector2(10, -10), c, 3.0)
	if _finger_at.x < 0.0:
		return
	var r := 30.0
	_finger.draw_circle(_finger_at, r, Color(1, 1, 1, 0.28 if _finger_down else 0.12))
	_finger.draw_arc(_finger_at, r, 0.0, TAU, 40, Color(1, 1, 1, 0.8 if _finger_down else 0.35), 3.0, true)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Events arrive in window pixels, as iOS delivers them; the reel's
## positions are canvas units (where the controls are drawn).  The movie's
## window is smaller than the canvas, so convert (identity when equal).
func _win(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p


func _touch(at: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = _win(at)
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	_finger_at = at
	_finger_down = down
	if down:
		_touch_at = at
	_finger.queue_redraw()


func _drag(from: Vector2, to: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = 0
	e.position = _win(to)
	e.relative = _win(to) - _win(from)
	e.screen_relative = _win(to) - _win(from)
	e.velocity = (_win(to) - _win(from)) * FPS
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	_finger_at = to
	_finger.queue_redraw()


func _run() -> void:
	await _frames(2)
	for c in get_tree().root.get_children():
		if c is BootCurtain:
			c.queue_free()
	if App.screen and is_instance_valid(App.screen):
		App.screen.queue_free()
	App.screen = null
	Save.set_setting("touch_layout", "standard")
	Save.set_setting("touch_layout_v2", null)
	Save.set_setting("stick_mode", "dynamic")
	Controls.device = "touch"
	printerr("REEL canvas %s, canvas->window %s" % [str(get_viewport().get_visible_rect().size), str(get_viewport().get_final_transform())])
	get_tree().root.notification(Window.NOTIFICATION_WM_MOUSE_ENTER)   # GUI input without a pointer in the window
	if DisplayServer.get_name() == "headless":
		get_tree().root.size = Vector2i(1560, 720)          # (smoke runs; movies use a 1040x480 window = the same canvas)                      # (smoke runs)
	_caption.text = "Preparing a Practice round (not part of the comparison)"
	var s := NetSession.new()
	add_child(s)
	s.start_offline("u-reel", "Runner", {}, "runner")
	var info := {}
	s.match_starting.connect(func(i: Dictionary) -> void: info.merge(i, true), CONNECT_ONE_SHOT)
	s.host_start_match(5150)
	mc = MatchController.new()
	mc.setup(s, info, {"staged": false, "quality": 0})   # Low preset: affordable on llvmpipe
	get_tree().root.add_child(mc)
	for i in 3600:
		await get_tree().process_frame
		if mc.prepared and mc.sim.phase == TC.Phase.PLAYING:
			break
	mc.sim.bots.clear()
	for bp: SimPlayer in mc.sim.players:
		if bp.is_bot:
			bp.body.collision_layer = 0
	for c: SimCart in mc.sim.carts:
		c.body.collision_layer = 0
	corridor = Round._find_corridor(mc.get_world_3d(), 70.0)
	if corridor.is_empty():
		corridor = Round._find_corridor(mc.get_world_3d(), 45.0)
	var r: Object = mc.touch.surface.router
	var R: float = r.get("stick_radius")
	var z: Rect2 = r.call("zone")
	var corner := Vector2(z.position.x + 0.3 * R, z.end.y - 0.3 * R)
	var centre := z.get_center()
	await _case("1  Thumb lands near the bottom-left corner, then pushes exactly straight up", corner, 5.0,
		func(tt: float) -> Vector2: return Vector2(0, -R * minf(1.0, tt / 0.15)))
	await _case("2  Forward with a 6 degree thumb lean and a small wobble, held 8 s", centre, 8.0,
		func(tt: float) -> Vector2:
			return Vector2(0, -R * minf(1.0, tt / 0.15)).rotated(deg_to_rad(6.0)) + Vector2(R * 0.04 * sin(TAU * 1.3 * tt), 0))
	await _case("3  Long push past the stick's rim, eased back to a comfortable push, held", centre, 6.0,
		func(tt: float) -> Vector2:
			var reach := clampf(tt / 0.6, 0.0, 1.0) * 2.4
			if tt > 3.0:
				reach = lerpf(2.4, 0.9, clampf((tt - 3.0) / 0.5, 0.0, 1.0))
			return Vector2(R * 0.05 * sin(TAU * 1.1 * tt), -R * reach))
	_caption.text = "End"
	_readout.text = ""
	await _frames(int(FPS))
	get_tree().quit()


func _place() -> void:
	var p := mc.sim.player(mc.local_slot)
	var st: Vector2 = corridor["start"]
	var yaw: float = corridor["yaw"]
	p.body.global_position = Vector3(st.x, 0.1, st.y)
	p.vel = Vector3.ZERO
	p.body.velocity = Vector3.ZERO
	p.yaw = yaw
	if "sprint" in p:   # (builds before Pass 9 had a sprint meter)
		p.set("sprint", 1.0)
	p.clear_history()
	mc.camera.snap_to(p.body.global_position, yaw)
	mc.camera.set("_manual_t", 10.0)
	Controls.reset_touch()


func _case(title: String, at: Vector2, secs: float, path: Callable) -> void:
	_caption.text = title
	_readout.text = ""
	_place()
	_touch_at = Vector2(-100, -100)
	await _frames(int(FPS * 1.2))
	var p := mc.sim.player(mc.local_slot)
	_p0 = p.body.global_position
	_cam0 = mc.camera.yaw
	var yaw0: float = corridor["yaw"]
	var fwd := Vector2(-sin(yaw0), -cos(yaw0))
	var nrm := Vector2(-fwd.y, fwd.x)
	_touch(at, true)
	var last := at
	for i in int(secs * FPS):
		var to: Vector2 = at + (path.call(float(i + 1) / FPS) as Vector2)
		if to != last:
			_drag(last, to)
			last = to
		await get_tree().process_frame
		var rel := Vector2(p.body.global_position.x - _p0.x, p.body.global_position.z - _p0.z)
		_readout.text = "stick x %+.2f  y %+.2f   ·   camera turned %+.0f°   ·   %.1f m sideways, %.1f m forward" % [
			Controls.touch_move.x, Controls.touch_move.y, rad_to_deg(angle_difference(_cam0, mc.camera.yaw)), rel.dot(nrm), rel.dot(fwd)]
	_touch(last, false)
	await _frames(int(FPS * 1.2))
	printerr("REEL %s | %s" % [title, _readout.text])
