class_name TouchControls
extends CanvasLayer
## On-screen controls with explicit touch ownership: a touch that starts on the
## stick, a button, or the camera area keeps that owner until it lifts, so the
## camera never steals jump/item/stick touches. Only buttons useful in the
## current state are shown.

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
	Controls.device_changed.connect(func(_k: String) -> void: surface.queue_redraw())


func consume_spectate() -> bool:
	var v := surface.spectate_req
	surface.spectate_req = false
	return v


class TouchSurface:
	extends Control
	var mc: MatchController
	var owners: Dictionary = {}       # touch index -> owner string
	var stick_center := Vector2.ZERO
	var stick_pos := Vector2.ZERO
	var stick_active := false
	var buttons: Dictionary = {}      # name -> {rect: Rect2 (centre, radius), label, visible}
	var held: Dictionary = {}         # button name -> true
	var spectate_req := false
	var t := 0.0
	const STICK_R := 92.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _process(delta: float) -> void:
		t += delta
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
			"phase": int(info.get("phase", 0)), "tag_cd": 0.0, "watching": mc.spectate_slot >= 0}

	func _layout_buttons() -> void:
		var vs := size
		var safe := UIKit.safe_margins(get_viewport())
		var right := vs.x - safe.size.x
		var bottom := vs.y - safe.size.y
		var c := _ctx()
		buttons.clear()
		var playing: bool = c["phase"] == TC.Phase.PLAYING
		if c["watching"] or c["st"] == TC.PState.FINISHED:
			buttons["next"] = {"c": Vector2(right - 90, bottom - 90), "r": 62.0, "label": "Next", "icon": "eye"}
			buttons["cheer"] = {"c": Vector2(right - 230, bottom - 70), "r": 54.0, "label": "Cheer", "icon": "star"}
			return
		if c["in_cart"]:
			buttons["gas"] = {"c": Vector2(right - 92, bottom - 120), "r": 80.0, "label": "GAS", "icon": ""}
			buttons["brake"] = {"c": Vector2(right - 260, bottom - 78), "r": 64.0, "label": "BRAKE", "icon": ""}
			buttons["cart"] = {"c": Vector2(right - 80, bottom - 300), "r": 50.0, "label": "Hop out", "icon": "cart"}
			return
		if not playing:
			return
		buttons["jump"] = {"c": Vector2(right - 100, bottom - 100), "r": 76.0, "label": "Jump" if c["role"] == TC.Role.PATROL else "Jump/Dive", "icon": ""}
		if c["role"] == TC.Role.PATROL:
			if c["st"] == TC.PState.ACTIVE:
				buttons["tag"] = {"c": Vector2(right - 270, bottom - 84), "r": 64.0, "label": "TAG", "icon": "whistle"}
			if c["near_cart"]:
				buttons["cart"] = {"c": Vector2(right - 120, bottom - 280), "r": 54.0, "label": "Drive", "icon": "cart"}
		else:
			if c["gadget"] != TC.Gadget.NONE:
				buttons["gadget"] = {"c": Vector2(right - 262, bottom - 90), "r": 58.0, "label": TC.GADGET_NAMES.get(c["gadget"], ""), "icon": Icons.gadget_icon(c["gadget"])}
		buttons["emote"] = {"c": Vector2(right - 60, safe.position.y + 260), "r": 36.0, "label": "Wave", "icon": ""}

	func _hit_button(p: Vector2) -> String:
		for name in buttons:
			var b: Dictionary = buttons[name]
			if p.distance_to(b["c"]) <= float(b["r"]) + 14.0:
				return name
		return ""

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			var e := event as InputEventScreenTouch
			if e.pressed:
				var btn := _hit_button(e.position)
				if btn != "":
					owners[e.index] = "btn:" + btn
					_press(btn)
				elif e.position.x < size.x * 0.42:
					owners[e.index] = "stick"
					stick_center = e.position
					stick_pos = e.position
					stick_active = true
				else:
					owners[e.index] = "look"
				accept_event()
			else:
				var o: String = owners.get(e.index, "")
				if o == "stick":
					stick_active = false
					Controls.touch_move = Vector2.ZERO
					Controls.touch_steer = 0.0
				elif o.begins_with("btn:"):
					held.erase(o.substr(4))
				owners.erase(e.index)
				accept_event()
		elif event is InputEventScreenDrag:
			var d := event as InputEventScreenDrag
			var o2: String = owners.get(d.index, "")
			if o2 == "stick":
				stick_pos = d.position
				# let the stick base follow a thumb that drifts far away
				var off := stick_pos - stick_center
				if off.length() > STICK_R * 1.6:
					stick_center = stick_pos - off.normalized() * STICK_R * 1.6
			elif o2 == "look":
				Controls.touch_look += d.relative
			accept_event()

	func _press(btn: String) -> void:
		held[btn] = true
		match btn:
			"jump":
				Controls.touch_pressed |= TC.BTN_JUMP
			"tag":
				Controls.touch_pressed |= TC.BTN_TAG
			"gadget":
				Controls.touch_pressed |= TC.BTN_GADGET
			"cart":
				Controls.touch_pressed |= TC.BTN_INTERACT
			"next":
				spectate_req = true
			"cheer":
				Controls.request_emote(1)
			"emote":
				Controls.request_emote(0)

	func _apply() -> void:
		var c := _ctx()
		if stick_active:
			var v := (stick_pos - stick_center) / STICK_R
			v = v.limit_length(1.0)
			if c["in_cart"]:
				Controls.touch_steer = v.x
				Controls.touch_move = Vector2.ZERO
			else:
				Controls.touch_move = Vector2(v.x, -v.y)
		else:
			Controls.touch_move = Vector2.ZERO
			Controls.touch_steer = 0.0
		var drive := 0.0
		if held.has("gas"):
			drive += 1.0
		if held.has("brake"):
			drive -= 1.0
		Controls.touch_drive = drive
		var h := 0
		if held.has("jump"):
			h |= TC.BTN_JUMP
		Controls.touch_held = h

	func _draw() -> void:
		if not _show():
			return
		var c := _ctx()
		# stick
		var info: Dictionary = mc.hud.info if mc.hud else {}
		var sprint: float = info.get("sprint", 1.0)
		var base := stick_center if stick_active else Vector2(size.x * 0.16, size.y * 0.72)
		var alpha := 0.9 if stick_active else 0.4
		draw_circle(base, STICK_R, Color(0.1, 0.12, 0.25, 0.35 * alpha))
		draw_arc(base, STICK_R, 0, TAU, 40, Color(1, 1, 1, 0.5 * alpha), 3.0)
		if c["role"] == TC.Role.RUNNER and not c["in_cart"]:
			# sprint ring = meter; glows when the thumb reaches the outer edge
			var thr := Controls.sprint_threshold
			draw_arc(base, STICK_R * thr, 0, TAU, 40, Color(1, 0.8, 0.3, 0.25 * alpha), 2.0)
			draw_arc(base, STICK_R + 9, -PI * 0.5, -PI * 0.5 + TAU * sprint, 40, UIKit.ACCENT if sprint > 0.15 else UIKit.BAD, 7.0)
		var knob := base
		if stick_active:
			knob = stick_center + (stick_pos - stick_center).limit_length(STICK_R)
		var sprinting: bool = stick_active and (stick_pos - stick_center).length() / STICK_R >= Controls.sprint_threshold and c["role"] == TC.Role.RUNNER
		draw_circle(knob, 40, Color(1.0, 0.8, 0.35, 0.85) if sprinting else Color(1, 1, 1, 0.55 * alpha + 0.2))
		if c["in_cart"]:
			draw_string(UIKit.font(true), base + Vector2(-34, STICK_R + 36), "STEER", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.8))
		# buttons
		var f := UIKit.font(true)
		for name in buttons:
			var b: Dictionary = buttons[name]
			var pressed := held.has(name)
			var col := Color(0.15, 0.2, 0.45, 0.55)
			match name:
				"jump": col = Color(0.3, 0.75, 1.0, 0.6)
				"tag": col = Color(1.0, 0.5, 0.25, 0.7)
				"gadget": col = Color(1.0, 0.82, 0.3, 0.7)
				"gas": col = Color(0.35, 0.9, 0.45, 0.65)
				"brake": col = Color(1.0, 0.4, 0.4, 0.6)
				"cart": col = Color(1.0, 0.6, 0.2, 0.7)
			if pressed:
				col = col.lightened(0.3)
			var r: float = b["r"]
			draw_circle(b["c"], r, col)
			draw_arc(b["c"], r, 0, TAU, 40, Color(1, 1, 1, 0.75), 3.0)
			var icon: String = b["icon"]
			if icon != "":
				Icons.draw_shape(self, icon, b["c"] - Vector2(0, 10), r * 0.32, Color(1, 1, 1, 0.95))
			var label: String = b["label"]
			var fs := 22 if r > 60 else 18
			var tw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(f, (b["c"] as Vector2) + Vector2(-tw * 0.5, r * 0.42 if icon != "" else 8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1))
