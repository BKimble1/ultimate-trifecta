extends Node
## Development probe (--start-probe=out.json): the start of a practice round
## as a player lives it.  From the moment the round exists it holds the
## stick fully forward (the real touch path: Controls.touch_move), and logs
## every frame: real frame time, the phase, whether the loading screen is up,
## and the local runner's position.  At exit it writes the timeline (loading
## closed, reveal, countdown, GO), frames over 33 ms with their phase, and
## how long after GO the held stick actually moved the runner.

var out_path := ""
var _t0 := 0
var _last := 0
var frames: Array = []
var events: Array = []
var _phase := -1
var _loading := false
var _go_at := -1.0
var _go_pos := Vector3.INF
var moved_after_go := -1.0
var quit_after := 30.0
## --start-probe-shots=DIR: every rendered frame from the round's preparation
## to 2 s after GO is saved (small), to see the hand-over frame by frame
var shots_dir := ""
## --start-probe-touch: instead of a held key, a finger goes down on the
## stick while the loading screen is still up and keeps pushing forward
## (the reported "can't move at the start")
var touch_mode := false
var _touch_down := false
var _drag_i := 0
var _shot_i := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -1000
	_t0 = Time.get_ticks_usec()
	_last = _t0


func _now() -> float:
	return float(Time.get_ticks_usec() - _t0) / 1e6


func _process(_d: float) -> void:
	var now_us := Time.get_ticks_usec()
	var ft := float(now_us - _last) / 1000.0
	_last = now_us
	var t := _now()
	var mc: MatchController = App.match_ctrl if is_instance_valid(App.match_ctrl) else null
	var loading := App.screen is LoadingScreen
	if loading != _loading:
		events.append({"t": t, "ev": "loading_shown" if loading else "loading_gone"})
		_loading = loading
	var ph := -1
	var pos := Vector3.INF
	if mc != null:
		if touch_mode:
			_touch_step(loading)
		elif not Input.is_action_pressed("move_forward"):
			Input.action_press("move_forward")   # held from before GO, like a thumb on the stick
		var info: Dictionary = mc.hud.info if mc.hud else {}
		ph = int(info.get("phase", -1))
		var rs: Dictionary = info.get("rs", {})
		if rs.has("pos"):
			pos = rs["pos"]
		if mc.prepared and not events.any(func(e: Dictionary) -> bool: return e["ev"] == "prepared"):
			events.append({"t": t, "ev": "prepared"})
	if ph != _phase:
		events.append({"t": t, "ev": "phase", "phase": ph})
		_phase = ph
		if ph == TC.Phase.PLAYING:
			_go_at = t
			_go_pos = pos
	if _go_at >= 0.0 and moved_after_go < 0.0 and pos != Vector3.INF and _go_pos != Vector3.INF and Vector2(pos.x - _go_pos.x, pos.z - _go_pos.z).length() > 0.1:
		moved_after_go = t - _go_at
		events.append({"t": t, "ev": "first_move", "after_go_s": moved_after_go})
	if touch_mode and _go_at > 0.0 and t - _go_at > 0.5 and not events.any(func(e: Dictionary) -> bool: return e["ev"] == "touch_debug") and mc != null and mc.touch != null:
		var sf = mc.touch.surface
		events.append({"ev": "touch_debug", "t": t, "device": Controls.device, "vis": sf.is_visible_in_tree(), "stick": sf.router.stick_index,
			"owners": str(sf.router.owners), "adopted": str(sf.get("_adopted")), "zone": str(sf.router.zone()), "size": str(sf.size),
			"vp": str(get_viewport().get_visible_rect().size), "move": str(Controls.get_move()), "filter": sf.mouse_filter, "rmove": str(sf.router.move_vector()), "tm": str(Controls.touch_move), "org": str(sf.router.stick_origin), "spos": str(sf.router.stick_pos), "rad": sf.router.stick_radius})
	frames.append({"t": snappedf(t, 0.001), "ms": snappedf(ft, 0.1), "phase": ph, "loading": loading})
	if shots_dir != "" and mc != null and mc.prepared and (_go_at < 0.0 or t - _go_at < 2.0) and _shot_i < 400:
		var img := get_viewport().get_texture().get_image()
		if img != null and not img.is_empty():
			img.resize(img.get_width() / 2, img.get_height() / 2)
			img.save_jpg(shots_dir.path_join("f%03d_t%.2f_ph%d%s.jpg" % [_shot_i, t, ph, "_L" if loading else ""]), 0.8)
			_shot_i += 1
	if t > quit_after:
		_write()
		get_tree().quit()


func _touch_step(loading: bool) -> void:
	# injected events are in window pixels: canvas points mapped through the
	# viewport's stretch transform
	var vis := get_viewport().get_visible_rect().size
	var xf := get_viewport().get_final_transform()
	var base := xf * Vector2(vis.x * 0.16, vis.y * 0.72)
	var ws := xf.get_scale() * vis
	if not _touch_down:
		if not loading:
			return   # the point is a finger that went down UNDER the loading screen
		var e := InputEventScreenTouch.new()
		e.index = 0
		e.position = base
		e.pressed = true
		Input.parse_input_event(e)
		_touch_down = true
		events.append({"t": _now(), "ev": "finger_down_under_loading"})
		return
	_drag_i += 1
	var d := InputEventScreenDrag.new()
	d.index = 0
	# pushed 80 % of the stick's radius forward (whatever the screen scale)
	var mc: MatchController = App.match_ctrl
	var rad := 92.0
	if mc != null and mc.touch != null:
		rad = mc.touch.surface.router.stick_radius
	var off := Vector2(0, -rad * 0.8 * xf.get_scale().y - float(_drag_i % 2))   # held forward, a hair of jitter
	d.position = base + off
	d.relative = Vector2(0, -1.0 if _drag_i % 2 == 0 else 1.0)
	d.screen_relative = d.relative
	Input.parse_input_event(d)


func _write() -> void:
	var slow: Array = frames.filter(func(f: Dictionary) -> bool: return float(f["ms"]) > 33.0 and float(f["t"]) > 0.5)
	var rep := {"events": events, "slow_frames": slow, "frames": frames.size(), "moved_after_go_s": moved_after_go}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(rep, " "))
	print("START_PROBE events=", JSON.stringify(events))
	print("START_PROBE slow frames (t, ms, phase, loading): ", slow.map(func(x: Dictionary) -> Array: return [x["t"], x["ms"], x["phase"], x["loading"]]))
	print("START_PROBE moved_after_go_s=", moved_after_go)
