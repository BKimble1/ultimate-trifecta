class_name TouchControls
extends CanvasLayer
## On-screen match controls (V4 rebuild).
##  - Geometry: TouchLayout (pure) - sizes in points, clusters anchored to
##    the safe area, per-context action anchors from the Layout editor.
##  - Ownership and gestures: TouchRouter (pure) - one owner per finger,
##    move + look + action together, ordered press queue via Controls.
##  - This layer only feeds events to the router, writes intent to Controls
##    and draws.  Hit testing and drawing use the same resolved positions
##    (mirroring and safe insets included), so what you see is what you hit.
##
## Contexts (action cluster, right thumb by default):
##   runner  Jump (Dive in the air) primary; Gadget and hold-Sprint in fixed slots
##   patrol  Tag primary (lights up when a runner is in reach); Jump beside it;
##           Drive appears in its own reserved slot near a cart
##   cart    Gas primary, Brake beside it, a small separate Exit
##   watch   Next / Cheer while spectating or after finishing
## The layout is recomputed only when the view, safe area, context, visible
## set or settings change.  Every touch is cancelled on focus loss,
## backgrounding, pause, scene change and when a controller takes over.

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
		surface.set_reserved(rects)


## The saved layout (migrating the V3 button size / mirrored settings).
static func saved_layout() -> Dictionary:
	return TouchLayout.sanitize(Save.get_setting("touch_layout_v2", null), float(Save.get_setting("button_size", 1.0)),
		String(Save.get_setting("touch_layout", "standard")) == "mirrored")


## Labels per button name (the editor shows the same ones).
const LABELS := {"jump": "Jump", "tag": "Tag", "gadget": "Gadget", "cart": "Drive", "gas": "Gas", "brake": "Brake",
	"next": "Next", "cheer": "Cheer", "sprint": "Sprint"}
const ICONS := {"tag": "whistle", "cart": "cart", "next": "eye", "cheer": "star", "sprint": "bolt"}
const COLORS := {"jump": "teal", "tag": "patrol", "gadget": "amber", "gas": "good", "brake": "bad", "cart": "patrol", "sprint": "amber"}


static func button_color(name: String) -> Color:
	match String(COLORS.get(name, "")):
		"teal": return Color(UIKit.TEAL, 0.62)
		"patrol": return Color(UIKit.PATROL, 0.72)
		"amber": return Color(UIKit.AMBER, 0.68)
		"good": return Color(UIKit.GOOD, 0.62)
		"bad": return Color(UIKit.BAD, 0.6)
	return Color(UIKit.SLATE, 0.62)


## Draws one button exactly where it is hit-tested.  `state`: pressed,
## ready (glow), busy (0..1 cooldown remaining), off (unavailable).
static func draw_button(ci: CanvasItem, b: Dictionary, name: String, label: String, icon: String, opacity: float, state: Dictionary = {}) -> void:
	var center: Vector2 = b["c"]
	var r: float = b["r"]
	var col := button_color(name)
	var pressed := bool(state.get("pressed", false))
	var off := bool(state.get("off", false))
	if pressed:
		col = col.lightened(0.25)
		r *= 0.95
	if off:
		col = Color(UIKit.SLATE, 0.45)
	col.a *= opacity
	if bool(state.get("ready", false)) and not off:
		# a soft ring that breathes: in reach, press now
		# (Reduced Motion: a steady ring, same meaning)
		var pulse := 0.6 if UIKit.reduced_motion() else 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) / 1000.0 * TAU * 1.6)
		ci.draw_arc(center, r + 7.0 + 3.0 * pulse, 0, TAU, 56, Color(UIKit.AMBER, (0.55 + 0.35 * pulse) * opacity), 5.0, true)
	ci.draw_circle(center, r, col)
	ci.draw_arc(center, r, 0, TAU, 48, Color(UIKit.IVORY, 0.7 * opacity), 2.5, true)
	var busy := float(state.get("busy", 0.0))
	if busy > 0.01:
		ci.draw_arc(center, r - 5.0, -PI * 0.5, -PI * 0.5 + TAU * busy, 48, Color(UIKit.NAVY, 0.75 * opacity), 7.0, true)
	var f := UIKit.font_w(650)
	var text_col := Color(UIKit.IVORY, (0.55 if off else 1.0) * clampf(opacity + 0.15, 0.0, 1.0))
	if icon != "":
		Icons.draw_shape(ci, icon, center - Vector2(0, r * 0.16), r * 0.3, text_col)
	var fs := int(clampf(r * 0.3, 16.0, 26.0))
	var tw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(f, center + Vector2(-tw * 0.5, r * 0.46 if icon != "" else fs * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_col)


## The stick: base ring, the sprint threshold ring (runners, edge sprint)
## and the knob.
static func draw_stick(ci: CanvasItem, base: Vector2, knob: Vector2, R: float, knob_r: float, opacity: float, active: bool,
		sprint_ring: float = 0.0, sprinting: bool = false, meter: float = -1.0) -> void:
	var a := (0.9 if active else 0.42) * opacity
	ci.draw_circle(base, R, Color(UIKit.NAVY, 0.3 * a))
	ci.draw_arc(base, R, 0, TAU, 56, Color(UIKit.IVORY, 0.42 * a), 2.5, true)
	if sprint_ring > 0.0:
		# where edge-sprint begins: a dotted ring inside the rim
		var rr := R * sprint_ring
		for i in 24:
			var a0 := TAU * float(i) / 24.0
			ci.draw_arc(base, rr, a0, a0 + TAU / 48.0, 4, Color(UIKit.AMBER if sprinting else UIKit.IVORY, (0.8 if sprinting else 0.32) * a), 2.0, true)
	if meter >= 0.0:
		var col := UIKit.AMBER if meter > 0.15 else UIKit.BAD
		ci.draw_arc(base, R + 8, -PI * 0.5, -PI * 0.5 + TAU * meter, 48, Color(col, (0.75 if sprinting else 0.4) * opacity), 5.0, true)
	ci.draw_circle(knob, knob_r, Color(UIKit.AMBER, 0.9 * opacity) if sprinting else Color(UIKit.IVORY, (0.45 * a + 0.2)))


class TouchSurface:
	extends Control
	var mc: MatchController
	var router := TouchRouter.new()
	var spectate_req := false
	var t := 0.0
	var layout: Dictionary = {}
	var res: Dictionary = {}          # TouchLayout.resolve result in use
	var _sig := ""
	var _was_in_cart := false
	var _hold_sprint := false
	var _reserved: Array[Rect2] = []
	var _ctx_cache: Dictionary = {}
	var layout_builds := 0            # tests: how often the layout was recomputed

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		_read_settings()
		Save.changed.connect(_read_settings)

	func _read_settings() -> void:
		router.fixed_stick = String(Save.get_setting("stick_mode", "dynamic")) == "fixed"
		_hold_sprint = String(Save.get_setting("sprint_mode", "edge")) == "hold"
		router.edge_sprint = not _hold_sprint and bool(Save.get_setting("touch_sprint", true))
		router.sprint_on = float(Save.get_setting("sprint_threshold", 0.88))
		router.sprint_off = router.sprint_on - 0.12
		var l := TouchControls.saved_layout()
		if l != layout:
			layout = l
			_sig = ""

	func set_reserved(rects: Array[Rect2]) -> void:
		if rects != _reserved:
			_reserved = rects
			router.reserved = rects
			_sig = ""

	## Reserved HUD regions (pause, map) are not ours: GUI picking falls
	## through to the HUD's own buttons on the layer below.  (Before V4 the
	## full-screen surface swallowed those taps, so Pause could not be tapped.)
	func _has_point(point: Vector2) -> bool:
		return Rect2(Vector2.ZERO, size).has_point(point) and not router.in_reserved(point)

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
		Controls.set_touch_points(0)

	func _process(delta: float) -> void:
		t += delta
		router.view_size = size
		_ctx_cache = _ctx()
		_layout_buttons(_ctx_cache)
		_apply(_ctx_cache)
		queue_redraw()

	func _show() -> bool:
		return Controls.device == "touch"

	func _ctx() -> Dictionary:
		if mc == null:
			return {"st": TC.PState.ACTIVE, "role": TC.Role.RUNNER, "in_cart": false, "near_cart": false, "gadget": 0,
				"phase": TC.Phase.PLAYING, "airborne": false, "watching": false, "tag_ready": false, "tag_busy": 0.0}
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
			"phase": int(info.get("phase", 0)), "airborne": not bool(rs.get("on_floor", true)),
			"watching": mc.spectate_slot >= 0 or st == TC.PState.FINISHED,
			"tag_ready": bool(info.get("tag_ready", false)), "tag_busy": float(info.get("tag_busy", 0.0))}

	## Which buttons of the context are showing now (slots never move).
	func visible_set(c: Dictionary) -> Array:
		var ctx := TouchLayout.context_for(c["role"], c["in_cart"], c["watching"])
		var playing: bool = c["phase"] == TC.Phase.PLAYING
		match ctx:
			"watch":
				return ["next", "cheer"]
			"cart":
				return ["gas", "brake", "cart"]
			"patrol":
				if not playing:
					return []
				# Tag always shows (greyed while it can't be used, e.g. the
				# head start), so the primary never leaves a hole
				var out := ["jump", "tag"]
				if c["near_cart"]:
					out.append("cart")
				return out
		if not playing:
			return []
		var r := ["jump"]
		if c["gadget"] != TC.Gadget.NONE:
			r.append("gadget")
		if _hold_sprint:
			r.append("sprint")
		return r

	func _layout_buttons(c: Dictionary) -> void:
		var ctx := TouchLayout.context_for(c["role"], c["in_cart"], c["watching"])
		var vis := visible_set(c)
		var safe := UIKit.safe_rect(get_viewport(), size)
		var sig := "%s|%s|%s|%s|%s|%d" % [size, safe, ctx, vis, router.fixed_stick, layout.hash()]
		if sig != _sig:
			_sig = sig
			layout_builds += 1
			res = TouchLayout.resolve(layout, ctx, size, safe, UIKit.units_per_point(), _reserved)
			var b := {}
			for name in vis:
				if (res["buttons"] as Dictionary).has(name):
					b[name] = res["buttons"][name]
			router.set_buttons(b)   # vanished buttons release their fingers
			router.stick_radius = float(res["stick_r"])
			router.fixed_center = res["stick_c"]
			router.stick_zone = res["zone"]
		if _was_in_cart and not c["in_cart"]:
			Controls.touch_drive = 0.0
		_was_in_cart = c["in_cart"]

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			var e := event as InputEventScreenTouch
			if e.pressed and not e.canceled:
				router.touch_down(e.index, e.position)
			else:
				router.touch_up(e.index)
			accept_event()
		elif event is InputEventScreenDrag:
			var d := event as InputEventScreenDrag
			router.drag(d.index, d.position, d.screen_relative)
			accept_event()

	func _apply(c: Dictionary) -> void:
		for btn in router.take_edges():
			match btn:
				"jump":
					Controls.queue_press(TC.BTN_JUMP)
					_haptic(8)
				"tag":
					if c["st"] == TC.PState.ACTIVE:
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
		# a finger on the stick owns movement even at zero output (inside the
		# dead zone): a drifting pad can't move the runner under it
		Controls.touch_stick_owned = router.stick_active()
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
		Controls.set_touch_points(router.owners.size())

	func _haptic(ms: int) -> void:
		if bool(Save.get_setting("haptics", true)) and OS.has_feature("mobile"):
			Input.vibrate_handheld(ms, 0.4)

	const HINT_ACTIONS := {"jump": "jump", "tag": "tag", "gadget": "gadget", "cart": "interact", "gas": "accelerate",
		"brake": "brake", "next": "spectate_next", "cheer": "emote_1", "sprint": "sprint"}

	func label_of(name: String, c: Dictionary) -> String:
		match name:
			"jump":
				return "Dive" if bool(c.get("airborne", false)) and c.get("role", 0) == TC.Role.RUNNER else "Jump"
			"gadget":
				return String(TC.GADGET_NAMES.get(c.get("gadget", 0), "Gadget"))
			"cart":
				return "Exit" if bool(c.get("in_cart", false)) else "Drive"
		return String(TouchControls.LABELS.get(name, name.capitalize()))

	func icon_of(name: String, c: Dictionary) -> String:
		if name == "gadget":
			return Icons.gadget_icon(int(c.get("gadget", 0)))
		return String(TouchControls.ICONS.get(name, ""))

	## Controller / keyboard: the same context actions as the touch buttons,
	## as a compact glyph list at the bottom right (no touch buttons drawn).
	func _draw_hints() -> void:
		if Controls.device == "touch":
			return
		var c := _ctx_cache
		var rows: Array = []
		for name in router.buttons:
			if HINT_ACTIONS.has(name) and not (name == "sprint"):
				rows.append([HINT_ACTIONS[name], label_of(name, c)])
		if c.get("role", 0) == TC.Role.RUNNER and not bool(c.get("in_cart", false)) and c.get("phase", 0) == TC.Phase.PLAYING and not bool(c.get("watching", false)):
			rows.append(["sprint", "Sprint"])
		if rows.is_empty():
			return
		var safe := UIKit.safe_margins(get_viewport())
		var h := 34.0
		var gap := 10.0
		var f := UIKit.font_w(650)
		var fs := 20
		var w := 0.0
		for r in rows:
			w = maxf(w, Glyphs.width(String(r[0]), h) + 10.0 + f.get_string_size(String(r[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		var x := size.x - safe.size.x - 28.0 - w
		var y := size.y - safe.size.y - 28.0 - rows.size() * (h + gap) + gap
		draw_style_box(UIKit.box(Color(UIKit.NAVY, 0.45), 18), Rect2(x - 14, y - 12, w + 28, rows.size() * (h + gap) - gap + 24))
		for r in rows:
			var gw := Glyphs.draw(self, String(r[0]), Vector2(x, y + h * 0.5), h)
			draw_string(f, Vector2(x + gw + 10.0, y + h * 0.5 + fs * 0.36), String(r[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UIKit.IVORY)
			y += h + gap

	func _draw() -> void:
		if not _show():
			_draw_hints()
			return
		if res.is_empty():
			return
		var c := _ctx_cache
		var info: Dictionary = mc.hud.info if mc != null and mc.hud else {}
		var opacity := float(layout.get("opacity", 0.85))
		var R := router.stick_radius
		var active := router.stick_active()
		var base: Vector2 = router.stick_center if active else (router.fixed_center if router.fixed_stick else _idle_stick())
		var knob := base
		if active:
			knob = router.knob_pos()   # the ring as drawn + the real offset
		var runner_foot: bool = c.get("role", 0) == TC.Role.RUNNER and not bool(c.get("in_cart", false))
		TouchControls.draw_stick(self, base, knob, R, float(res["knob_r"]), opacity, active,
			router.sprint_on if runner_foot and router.edge_sprint else 0.0, Controls.touch_sprint,
			float(info.get("sprint", 1.0)) if runner_foot else -1.0)
		if bool(c.get("in_cart", false)):
			var f0 := UIKit.font_w(650)
			draw_string(f0, base + Vector2(-30, R + 34), "Steer", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(UIKit.IVORY, 0.75 * opacity))
		var held := router.held()
		for name in router.buttons:
			var st := {"pressed": held.has(name)}
			if name == "tag":
				st["off"] = c.get("st", TC.PState.ACTIVE) != TC.PState.ACTIVE
				st["ready"] = bool(c.get("tag_ready", false))
				st["busy"] = float(c.get("tag_busy", 0.0))
			elif name == "gadget":
				st["busy"] = clampf(float(info.get("gadget_cd", 0.0)) / maxf(0.1, mc.cfg.gadget_use_cooldown_s), 0.0, 1.0) if mc != null else 0.0
			TouchControls.draw_button(self, router.buttons[name], name, label_of(name, c), icon_of(name, c), opacity, st)

	## Where the dynamic stick rests while untouched: the layout's stick anchor.
	func _idle_stick() -> Vector2:
		return res.get("stick_c", Vector2(size.x * 0.15, size.y * 0.72))
