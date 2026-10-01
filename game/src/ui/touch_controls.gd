class_name TouchControls
extends CanvasLayer
## On-screen match controls.  Ownership and gesture rules live in
## TouchRouter (pure, unit-tested); this layer lays out the context buttons,
## feeds touch events to the router, writes intent to Controls and draws.
##
## Layout (standard; "mirrored" swaps sides):
##   left   movement stick (dynamic by default, optional fixed)
##   right  Jump (Dive while airborne), Sprint (hold-to-sprint mode only),
##          Gadget when carrying one; Night Watch: Tag + contextual Drive
##   cart   left steers, right Gas / Brake, small Exit
## Cancels every touch on focus loss, backgrounding, pause, scene change,
## role/state change (via the button set) and when a controller takes over.

var mc: MatchController
var surface: TouchSurface


func setup(controller: MatchController) -> void:
	mc = controller
	layer = 6
	surface = TouchSurface.new()
	surface.mc = mc
	surface.set_anchors_preset(Control.PRESET_FULL_RECT)
	surface.mouse_filter = Control.MOUSE_FILTER_STOP if OS.has_feature("mobile") or Controls.device == "touch" else Control.MOUSE_FILTER_IGNORE
	add_child(surface)
	Controls.device_changed.connect(surface._on_device)


func consume_spectate() -> bool:
	var v := surface.spectate_req
	surface.spectate_req = false
	return v


func cancel_all() -> void:
	if surface:
		surface.cancel_all()


## HUD regions (canvas rects) that must never start a stick or camera drag.
func set_reserved(rects: Array[Rect2]) -> void:
	if surface:
		surface.router.reserved = rects


class TouchSurface:
	extends Control
	var mc: MatchController
	var router := TouchRouter.new()
	var spectate_req := false
	var t := 0.0
	var _was_in_cart := false
	var _scale := 1.0
	var _mirror := false
	var _hold_sprint := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		_read_settings()

	func _read_settings() -> void:
		router.fixed_stick = String(Save.get_setting("stick_mode", "dynamic")) == "fixed"
		_hold_sprint = String(Save.get_setting("sprint_mode", "edge")) == "hold"
		router.edge_sprint = not _hold_sprint and bool(Save.get_setting("touch_sprint", true))
		router.sprint_on = float(Save.get_setting("sprint_threshold", 0.88))
		router.sprint_off = router.sprint_on - 0.12
		_scale = float(Save.get_setting("button_size", 1.0))
		_mirror = String(Save.get_setting("touch_layout", "standard")) == "mirrored"
		router.stick_radius = 92.0 * clampf(_scale, 0.85, 1.25)

	func _notification(what: int) -> void:
		match what:
			NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_EXIT_TREE:
				cancel_all()
			NOTIFICATION_VISIBILITY_CHANGED:
				if not is_visible_in_tree():
					cancel_all()

	func _on_device(kind: String) -> void:
		if kind != "touch":
			cancel_all()
		queue_redraw()

	func cancel_all() -> void:
		router.cancel_all()
		Controls.reset_touch()

	func _process(delta: float) -> void:
		t += delta
		router.view_size = size
		var zone := 0.45
		router.stick_zone_frac = zone
		_layout_buttons()
		_apply()
		queue_redraw()

	func _show() -> bool:
		return Controls.device == "touch"

	func _ctx() -> Dictionary:
		var info: Dictionary = mc.hud.info if mc.hud else {}
		var rs: Dictionary = info.get("rs", {})
		var st: int = rs.get("state", TC.PState.ACTIVE)
		var role: int = info.get("role", TC.Role.RUNNER)
		var in_cart := st == TC.PState.IN_CART or st == TC.PState.ENTERING
		var near_cart := false
		if role == TC.Role.PATROL and st == TC.PState.ACTIVE and rs.has("pos"):
			for i in mc.cart_views.size():
				var crs := mc._cart_rs(i)
				if crs.has("pos") and not bool(crs.get("occupied", false)) and (crs["pos"] as Vector3).distance_to(rs["pos"]) < mc.cfg.cart_enter_range_m + 1.2 and absf(float(crs.get("speed", 0.0))) < mc.cfg.cart_enter_max_speed:
					near_cart = true
		return {"st": st, "role": role, "in_cart": in_cart, "near_cart": near_cart, "gadget": int(info.get("gadget", 0)),
			"phase": int(info.get("phase", 0)), "airborne": not bool(rs.get("on_floor", true)), "watching": mc.spectate_slot >= 0}

	## Button centre measured from the bottom-right (or bottom-left when mirrored).
	func _at(right: float, bottom: float, dx: float, dy: float) -> Vector2:
		if _mirror:
			var left := UIKit.safe_margins(get_viewport()).position.x
			return Vector2(left + dx * _scale, bottom - dy * _scale)
		return Vector2(right - dx * _scale, bottom - dy * _scale)

	func _layout_buttons() -> void:
		var vs := size
		var safe := UIKit.safe_margins(get_viewport())
		var right := vs.x - safe.size.x
		var bottom := vs.y - safe.size.y
		var c := _ctx()
		var b := {}
		var s := _scale
		var playing: bool = c["phase"] == TC.Phase.PLAYING
		if c["watching"] or c["st"] == TC.PState.FINISHED:
			b["next"] = {"c": _at(right, bottom, 96, 96), "r": 60.0 * s, "label": "Next", "icon": "eye"}
			b["cheer"] = {"c": _at(right, bottom, 236, 72), "r": 50.0 * s, "label": "Cheer", "icon": "star"}
		elif c["in_cart"]:
			b["gas"] = {"c": _at(right, bottom, 98, 118), "r": 78.0 * s, "label": "Gas", "icon": ""}
			b["brake"] = {"c": _at(right, bottom, 262, 78), "r": 60.0 * s, "label": "Brake", "icon": ""}
			b["cart"] = {"c": _at(right, bottom, 84, 292), "r": 44.0 * s, "label": "Exit", "icon": "cart"}
		elif playing:
			b["jump"] = {"c": _at(right, bottom, 104, 104), "r": 74.0 * s, "label": "Dive" if bool(c["airborne"]) and c["role"] == TC.Role.RUNNER else "Jump", "icon": ""}
			if c["role"] == TC.Role.PATROL:
				if c["st"] == TC.PState.ACTIVE:
					b["tag"] = {"c": _at(right, bottom, 272, 86), "r": 62.0 * s, "label": "Tag", "icon": "whistle"}
				if c["near_cart"]:
					b["cart"] = {"c": _at(right, bottom, 122, 286), "r": 52.0 * s, "label": "Drive", "icon": "cart"}
			else:
				if c["gadget"] != TC.Gadget.NONE:
					b["gadget"] = {"c": _at(right, bottom, 266, 92), "r": 56.0 * s, "label": TC.GADGET_NAMES.get(c["gadget"], ""), "icon": Icons.gadget_icon(c["gadget"])}
				if _hold_sprint:
					b["sprint"] = {"c": _at(right, bottom, 108, 280), "r": 52.0 * s, "label": "Sprint", "icon": "bolt"}
		router.set_buttons(b)
		if _was_in_cart and not c["in_cart"]:
			Controls.touch_drive = 0.0
		_was_in_cart = c["in_cart"]
		# router space always has the stick on the left (mirrored layouts are
		# flipped on the way in and out)
		router.fixed_center = Vector2(maxf(safe.position.x, safe.size.x) + 170 * s, size.y - safe.size.y - 150 * s)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			var e := event as InputEventScreenTouch
			var p := _mirror_point(e.position)
			if e.pressed and not e.canceled:
				router.touch_down(e.index, p)
			else:
				router.touch_up(e.index)
			accept_event()
		elif event is InputEventScreenDrag:
			var d := event as InputEventScreenDrag
			router.drag(d.index, _mirror_point(d.position), d.screen_relative)
			accept_event()

	## Mirrored layout: the router always works with the stick zone on the left.
	func _mirror_point(p: Vector2) -> Vector2:
		return Vector2(size.x - p.x, p.y) if _mirror else p

	func _apply() -> void:
		var c := _ctx()
		# buttons are laid out in screen space; the router sees mirrored space
		if _mirror:
			var mb := {}
			for k in router.buttons:
				var bb: Dictionary = (router.buttons[k] as Dictionary).duplicate()
				bb["c"] = _mirror_point(bb["c"])
				mb[k] = bb
			router.buttons = mb
		for btn in router.take_edges():
			match btn:
				"jump":
					Controls.queue_press(TC.BTN_JUMP)
					_haptic(8)
				"tag":
					Controls.queue_press(TC.BTN_TAG)
					_haptic(12)
				"gadget":
					Controls.queue_press(TC.BTN_GADGET)
				"cart":
					Controls.queue_press(TC.BTN_INTERACT)
				"next":
					spectate_req = true
				"cheer":
					Controls.request_emote(1)
		var mv := router.move_vector()
		if _mirror:
			mv.x = -mv.x
		if c["in_cart"]:
			Controls.touch_steer = mv.x
			Controls.touch_move = Vector2.ZERO
		else:
			Controls.touch_move = mv
			Controls.touch_steer = 0.0
		var held := router.held()
		var drive := 0.0
		if held.has("gas"):
			drive += 1.0
		if held.has("brake"):
			drive -= 1.0
		Controls.touch_drive = drive if c["in_cart"] else 0.0
		var h := 0
		if held.has("jump"):
			h |= TC.BTN_JUMP
		Controls.touch_held = h
		Controls.touch_sprint = (router.sprinting or held.has("sprint")) and c["role"] == TC.Role.RUNNER and not c["in_cart"]
		Controls.touch_look_px += router.take_look_px()

	func _haptic(ms: int) -> void:
		if bool(Save.get_setting("haptics", true)) and OS.has_feature("mobile"):
			Input.vibrate_handheld(ms, 0.4)

	func _draw() -> void:
		if not _show():
			return
		var c := _ctx()
		var info: Dictionary = mc.hud.info if mc.hud else {}
		var sprint: float = info.get("sprint", 1.0)
		var R := router.stick_radius
		var active := router.stick_active()
		var base := router.stick_center if active else (router.fixed_center if router.fixed_stick else Vector2(size.x * 0.15, size.y * 0.72))
		var knob := base
		if active:
			knob = router.stick_center + (router.stick_pos - router.stick_center).limit_length(R)
		if _mirror:
			base = _mirror_point(base)
			knob = _mirror_point(knob)
		var alpha := 0.9 if active else 0.38
		draw_circle(base, R, Color(UIKit.NAVY, 0.28 * alpha))
		draw_arc(base, R, 0, TAU, 48, Color(UIKit.IVORY, 0.4 * alpha), 2.5, true)
		if c["role"] == TC.Role.RUNNER and not c["in_cart"]:
			# discreet sprint meter around the stick; brightens while sprinting
			var col := UIKit.AMBER if sprint > 0.15 else UIKit.BAD
			draw_arc(base, R + 8, -PI * 0.5, -PI * 0.5 + TAU * sprint, 48, Color(col, 0.75 if Controls.touch_sprint else 0.4), 5.0, true)
		draw_circle(knob, 38, Color(UIKit.AMBER, 0.9) if Controls.touch_sprint else Color(UIKit.IVORY, 0.45 * alpha + 0.2))
		if c["in_cart"]:
			var f0 := UIKit.font_w(650)
			draw_string(f0, base + Vector2(-30, R + 34), "Steer", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(UIKit.IVORY, 0.75))
		var f := UIKit.font_w(650)
		var held := router.held()
		for name in router.buttons:
			var b: Dictionary = router.buttons[name]
			var center: Vector2 = _mirror_point(b["c"]) if _mirror else b["c"]
			var pressed := held.has(name)
			var col := Color(UIKit.SLATE, 0.62)
			match name:
				"jump": col = Color(UIKit.TEAL, 0.62)
				"tag": col = Color(UIKit.PATROL, 0.72)
				"gadget": col = Color(UIKit.AMBER, 0.72)
				"gas": col = Color(UIKit.GOOD, 0.62)
				"brake": col = Color(UIKit.BAD, 0.6)
				"cart": col = Color(UIKit.PATROL, 0.62)
				"sprint": col = Color(UIKit.AMBER, 0.55)
			var r: float = b["r"]
			if pressed:
				col = col.lightened(0.25)
				r *= 0.95
			draw_circle(center, r, col)
			draw_arc(center, r, 0, TAU, 48, Color(UIKit.IVORY, 0.7), 2.5, true)
			var icon: String = b["icon"]
			if icon != "":
				Icons.draw_shape(self, icon, center - Vector2(0, 10), r * 0.3, Color(UIKit.IVORY, 0.95))
			var label: String = b["label"]
			var fs := 22 if r > 60 else 18
			var tw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(f, center + Vector2(-tw * 0.5, r * 0.42 if icon != "" else 8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UIKit.IVORY)
