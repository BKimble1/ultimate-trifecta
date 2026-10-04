class_name TouchLayoutEditor
extends Screen
## Settings > Controls > Edit layout (V4): drag the movement or action
## cluster, adjust size and opacity within safe limits, mirror, reset, and
## try the controls live.  The preview uses the same TouchLayout.resolve and
## the same drawing as a match, so what is placed here is what is hit there.
## Anchors are stored normalized to the safe area, per context for the
## action cluster; Done saves, Cancel / Back leaves the saved layout alone.

const CTX_NAMES := [["runner", "Runner"], ["patrol", "Night Watch"], ["cart", "Cart"]]

var layout: Dictionary = {}
var ctx := "runner"
var canvas: EditorCanvas
var size_slider: HSlider
var opacity_slider: HSlider
var mirror_btn: Button
var try_btn: Button
var note: Label
var _ctx_buttons: Dictionary = {}
## where to go afterwards (Settings by default)
var return_to: GDScript


func build() -> void:
	layout = TouchControls.saved_layout()
	var dim := ColorRect.new()
	dim.color = Color(UIKit.NAVY, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	move_child(dim, 0)
	canvas = EditorCanvas.new()
	canvas.ed = self
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(canvas)
	move_child(canvas, 1)
	# the panel sits in the top band, clear of both thumb clusters
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := UIKit.hbox(14)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := UIKit.heading("Touch layout", 34)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(title)
	for c in CTX_NAMES:
		var b := UIKit.quiet(String(c[1]), Vector2(150, 56), 20)
		b.toggle_mode = true
		_toggle_style(b)
		b.button_pressed = c[0] == ctx
		b.pressed.connect(_set_ctx.bind(String(c[0])))
		top.add_child(b)
		_ctx_buttons[c[0]] = b
		focus_first(b)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(sp)
	var cancel := UIKit.quiet("Cancel", Vector2(140, 56), 20)
	cancel.pressed.connect(_go_back)
	top.add_child(cancel)
	var done := UIKit.secondary("Done", Vector2(150, 56), 22)
	done.pressed.connect(_save)
	top.add_child(done)
	content.add_child(top)
	var row := UIKit.hbox(14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(UIKit.label("Size", 20, UIKit.IVORY_MUTED))
	size_slider = _slider(TouchLayout.SIZE_MIN, TouchLayout.SIZE_MAX, float(layout["size"]))
	size_slider.value_changed.connect(func(v: float) -> void:
		layout["size"] = v
		canvas.queue_redraw())
	row.add_child(size_slider)
	row.add_child(UIKit.label("Opacity", 20, UIKit.IVORY_MUTED))
	opacity_slider = _slider(TouchLayout.OPACITY_MIN, TouchLayout.OPACITY_MAX, float(layout["opacity"]))
	opacity_slider.value_changed.connect(func(v: float) -> void:
		layout["opacity"] = v
		canvas.queue_redraw())
	row.add_child(opacity_slider)
	mirror_btn = UIKit.quiet("Mirrored", Vector2(150, 56), 20)
	mirror_btn.toggle_mode = true
	_toggle_style(mirror_btn)
	mirror_btn.button_pressed = bool(layout["mirror"])
	mirror_btn.toggled.connect(_set_mirror)
	row.add_child(mirror_btn)
	var reset := UIKit.quiet("Reset", Vector2(120, 56), 20)
	reset.pressed.connect(_reset)
	row.add_child(reset)
	try_btn = UIKit.quiet("Try it", Vector2(130, 56), 20)
	try_btn.toggle_mode = true
	_toggle_style(try_btn)
	try_btn.toggled.connect(func(on: bool) -> void:
		canvas.try_mode = on
		canvas.router.cancel_all()
		_hint())
	row.add_child(try_btn)
	content.add_child(row)
	# the hint line stays in the top band, above every control
	note = UIKit.label("", 18, UIKit.IVORY_MUTED)
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(note)
	_hint()


## Selected tabs and switched-on toggles read as selected (teal), not just focused.
func _toggle_style(b: Button) -> void:
	var on := UIKit.box(Color(UIKit.TEAL, 0.32), UIKit.R_BUTTON, 2, UIKit.TEAL)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)


func _slider(lo: float, hi: float, v: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.05
	s.value = v
	s.custom_minimum_size = Vector2(170, 56)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return s


func _hint(extra: String = "") -> void:
	if not is_instance_valid(note):
		return
	if extra != "":
		note.text = extra
	elif canvas.try_mode:
		note.text = "Try it: move, look and press together. Nothing is sent to a game."
	else:
		note.text = "Drag the stick or the buttons to move them. Each role keeps its own button position."


func _set_ctx(c: String) -> void:
	ctx = c
	for k in _ctx_buttons:
		(_ctx_buttons[k] as Button).set_pressed_no_signal(k == c)
	canvas.router.cancel_all()
	canvas.queue_redraw()


## Mirroring flips the saved anchors too, so a custom spot stays custom.
func _set_mirror(on: bool) -> void:
	if bool(layout["mirror"]) == on:
		return
	layout["mirror"] = on
	var mv: Array = layout["move"]
	if mv.size() == 2:
		layout["move"] = [1.0 - float(mv[0]), float(mv[1])]
	var act: Dictionary = layout["action"]
	for k in act:
		act[k] = [1.0 - float(act[k][0]), float(act[k][1])]
	canvas.queue_redraw()


func _reset() -> void:
	layout = TouchLayout.default_layout()
	size_slider.set_value_no_signal(1.0)
	opacity_slider.set_value_no_signal(float(layout["opacity"]))
	mirror_btn.set_pressed_no_signal(false)
	_hint("Back to the recommended layout.")
	canvas.queue_redraw()


func _save() -> void:
	Save.set_setting("touch_layout_v2", TouchLayout.sanitize(layout))
	# older builds and the controller hints read these
	Save.set_setting("button_size", float(layout["size"]))
	Save.set_setting("touch_layout", "mirrored" if bool(layout["mirror"]) else "standard")
	_leave()


func _go_back() -> void:
	_leave()


func _leave() -> void:
	App.goto(return_to if return_to != null else SettingsScreen)


## The live preview and drag surface.
class EditorCanvas:
	extends Control
	var ed: TouchLayoutEditor
	var router := TouchRouter.new()
	var try_mode := false
	var res: Dictionary = {}
	var _drag := ""          # "move" | "action" while dragging a cluster
	var _drag_from := Vector2.ZERO
	var _anchor_from := Vector2.ZERO
	var _touch_seen := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _reserved() -> Array:
		# the match HUD's map + pause corner (top right, canvas units as in
		# MatchHUD) stays clear
		var m := UIKit.safe_margins(get_viewport())
		return [Rect2(size.x - m.size.x - 250.0, m.position.y, 250.0, 190.0)]

	func _resolve() -> void:
		var safe := UIKit.safe_rect(get_viewport(), size)
		res = TouchLayout.resolve(ed.layout, ed.ctx, size, safe, UIKit.units_per_point(), _reserved())
		router.view_size = size
		router.set_buttons(res["buttons"])
		router.stick_radius = res["stick_r"]
		router.fixed_center = res["stick_c"]
		router.stick_zone = res["zone"]
		router.fixed_stick = String(Save.get_setting("stick_mode", "dynamic")) == "fixed"
		router.edge_sprint = ed.ctx == "runner" and String(Save.get_setting("sprint_mode", "edge")) == "edge"

	func _process(_d: float) -> void:
		if try_mode:
			router.move_vector()   # updates the sprint state for the drawing
			router.take_edges()
			router.take_look_px()
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			_touch_seen = true
			var e := event as InputEventScreenTouch
			_pointer(e.index, e.position, e.pressed and not e.canceled, Vector2.ZERO, false)
			accept_event()
		elif event is InputEventScreenDrag:
			var d := event as InputEventScreenDrag
			_pointer(d.index, d.position, true, d.screen_relative, true)
			accept_event()
		elif not _touch_seen and event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var m := event as InputEventMouseButton
			_pointer(0, m.position, m.pressed, Vector2.ZERO, false)
			accept_event()
		elif not _touch_seen and event is InputEventMouseMotion and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			var mm := event as InputEventMouseMotion
			_pointer(0, mm.position, true, mm.relative, true)
			accept_event()

	func _pointer(index: int, p: Vector2, down: bool, rel: Vector2, motion: bool) -> void:
		_resolve()
		if try_mode:
			if motion:
				router.drag(index, p, rel)
			elif down:
				router.touch_down(index, p)
			else:
				router.touch_up(index)
			return
		if index != 0 and _drag != "":
			return
		if motion:
			if _drag == "":
				return
			var safe := UIKit.safe_rect(get_viewport(), size)
			var np := TouchLayout.normalize(_anchor_from + (p - _drag_from), safe)
			if _drag == "move":
				ed.layout["move"] = np
			else:
				(ed.layout["action"] as Dictionary)[ed.ctx] = np
			queue_redraw()
			return
		if down:
			_drag = _hit_cluster(p)
			_drag_from = p
			_anchor_from = res["move_anchor"] if _drag == "move" else res["action_anchor"]
		else:
			if _drag != "":
				_resolve()
				# store where it actually landed (clamped / pushed clear)
				var safe2 := UIKit.safe_rect(get_viewport(), size)
				if _drag == "move":
					ed.layout["move"] = TouchLayout.normalize(res["move_anchor"], safe2)
				else:
					(ed.layout["action"] as Dictionary)[ed.ctx] = TouchLayout.normalize(res["action_anchor"], safe2)
				if bool(res["clamped"]):
					ed._hint("Moved to fit the screen and keep clear of the other controls.")
			_drag = ""

	func _hit_cluster(p: Vector2) -> String:
		if p.distance_to(res["move_anchor"]) <= float(res["stick_r"]) * 1.15:
			return "move"
		for name in res["buttons"]:
			var b: Dictionary = res["buttons"][name]
			if p.distance_to(b["c"]) <= float(b["hit"]):
				return "action"
		return ""

	func _draw() -> void:
		_resolve()
		var safe := UIKit.safe_rect(get_viewport(), size)
		# safe area and the HUD corner, faint
		draw_rect(safe, Color(UIKit.IVORY, 0.12), false, 2.0)
		# the HUD band (objectives, timer, map) where controls never go
		var band := size.y * TouchLayout.TOP_BAND
		draw_line(Vector2(safe.position.x, band), Vector2(safe.end.x, band), Color(UIKit.IVORY, 0.14), 2.0)
		var opacity := float(ed.layout.get("opacity", 0.85))
		var R: float = res["stick_r"]
		var base: Vector2 = res["move_anchor"]
		var knob := base
		var active := try_mode and router.stick_active()
		if active:
			base = router.stick_center
			knob = router.knob_pos()
		var runner := ed.ctx == "runner"
		TouchControls.draw_stick(self, base, knob, R, float(res["knob_r"]), opacity, active or _drag == "move",
			router.sprint_on if runner and router.edge_sprint else 0.0, try_mode and router.sprinting, 1.0 if runner else -1.0)
		var held := router.held() if try_mode else {}
		var c := {"role": TC.Role.PATROL if ed.ctx == "patrol" else TC.Role.RUNNER, "in_cart": ed.ctx == "cart", "gadget": TC.Gadget.TURBO}
		var hold_sprint := String(Save.get_setting("sprint_mode", "edge")) == "hold"
		for name in res["buttons"]:
			if name == "sprint" and not hold_sprint:
				continue   # edge sprint: no button (its slot stays reserved)
			var label := String(TouchControls.LABELS.get(name, name))
			if name == "cart":
				label = "Exit" if ed.ctx == "cart" else "Drive"
			var icon := String(TouchControls.ICONS.get(name, ""))
			if name == "gadget":
				icon = Icons.gadget_icon(TC.Gadget.TURBO)
			TouchControls.draw_button(self, res["buttons"][name], name, label, icon, opacity, {"pressed": held.has(name)})
		if _drag == "action":
			var ext_c: Vector2 = res["action_anchor"]
			draw_arc(ext_c, 18.0, 0, TAU, 24, UIKit.AMBER, 3.0, true)
		if try_mode:
			var bits: Array[String] = []
			var mv := router.move_vector()
			if mv.length() > 0.05:
				bits.append("Sprinting" if router.sprinting and runner else "Moving")
			for name in held:
				bits.append(String(TouchControls.LABELS.get(name, name)))
			var f := UIKit.font_w(650)
			var txt := " · ".join(bits) if not bits.is_empty() else "Touch anywhere to try"
			var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
			draw_string(f, Vector2(size.x * 0.5 - tw * 0.5, size.y * 0.42), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(UIKit.IVORY, 0.85))
