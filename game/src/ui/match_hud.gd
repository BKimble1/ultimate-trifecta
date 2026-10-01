class_name MatchHUD
extends CanvasLayer
## In-match HUD. Keeps the screen focused on the world: compact corners,
## safe-area aware, colour always paired with an icon/shape.

var mc: MatchController
var root: Control
var timer_lbl: Label
var home_lbl: Label
var role_lbl: Label
var target_rows: Array = []
var toast_lbl: Label
var toast_t := 0.0
var center_lbl: Label
var sub_lbl: Label
var banner: PanelContainer
var banner_lbl: Label
var reveal: PanelContainer
var feed_box: VBoxContainer
var overlay: PanelContainer
var overlay_title: Label
var overlay_sub: Label
var spectate_lbl: Label
var draw_layer: Control
var compass: Control
var minimap: Control
var pause_btn: Button
var pause_panel: PanelContainer
var info: Dictionary = {}
var emotes: Dictionary = {}   # slot -> {id, t}
var _safe := Rect2()
var _spectating := -1
var _t := 0.0
var _last_penalty_sec := -1
# tutorial coach
var coach: PanelContainer
var coach_lbl: Label
var coach_step := 0
var _coach_moved := 0.0
var _coach_last := Vector3.INF
var _coach_look := 0.0
var _coach_yaw := 0.0
var _coach_flash := 0.0


func setup(controller: MatchController) -> void:
	mc = controller
	layer = 5
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIKit.theme()
	add_child(root)
	draw_layer = DrawLayer.new()
	(draw_layer as DrawLayer).hud = self
	draw_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	draw_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(draw_layer)

	# --- top centre: timer, home count, compass
	var top := UIKit.vbox(2)
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.alignment = BoxContainer.ALIGNMENT_BEGIN
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	top.set_meta("anchor", "top")
	timer_lbl = UIKit.outlined(UIKit.label("4:00", 46, UIKit.TEXT, true, HORIZONTAL_ALIGNMENT_CENTER), 10)
	top.add_child(timer_lbl)
	home_lbl = UIKit.outlined(UIKit.label("0/4 HOME", 24, UIKit.GOOD, true, HORIZONTAL_ALIGNMENT_CENTER), 8)
	top.add_child(home_lbl)
	compass = Compass.new()
	(compass as Compass).hud = self
	compass.custom_minimum_size = Vector2(520, 44)
	compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(compass)

	# --- top left: role + targets
	var tl := UIKit.vbox(6)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.set_meta("anchor", "top_left")
	root.add_child(tl)
	role_lbl = UIKit.outlined(UIKit.label("RUNNER", 22, UIKit.RUNNER, true), 8)
	tl.add_child(role_lbl)
	for i in 3:
		var row := UIKit.hbox(8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := Icons.IconRect.new("star", Color.WHITE, 38)
		var nm := UIKit.outlined(UIKit.label("Target", 25, UIKit.TEXT, true), 7)
		var st := UIKit.outlined(UIKit.label("", 22, UIKit.GOOD, true), 7)
		row.add_child(ic)
		row.add_child(nm)
		row.add_child(st)
		tl.add_child(row)
		target_rows.append({"row": row, "icon": ic, "name": nm, "state": st})

	# --- top right: minimap + pause
	var tr := UIKit.hbox(10)
	tr.set_meta("anchor", "top_right")
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tr)
	minimap = Minimap.new()
	(minimap as Minimap).hud = self
	minimap.custom_minimum_size = Vector2(190, 190)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.add_child(minimap)
	pause_btn = UIKit.button("II", Color(0.2, 0.24, 0.45, 0.85), Vector2(64, 64), 26)
	pause_btn.focus_mode = Control.FOCUS_NONE
	pause_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	pause_btn.pressed.connect(_toggle_pause)
	tr.add_child(pause_btn)

	# --- centre messages
	center_lbl = UIKit.outlined(UIKit.label("", 96, UIKit.ACCENT, true, HORIZONTAL_ALIGNMENT_CENTER), 14)
	center_lbl.set_anchors_preset(Control.PRESET_CENTER)
	center_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center_lbl)
	sub_lbl = UIKit.outlined(UIKit.label("", 30, UIKit.TEXT, true, HORIZONTAL_ALIGNMENT_CENTER), 9)
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(sub_lbl)
	toast_lbl = UIKit.outlined(UIKit.label("", 34, UIKit.TEXT, true, HORIZONTAL_ALIGNMENT_CENTER), 10)
	toast_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast_lbl)

	banner = UIKit.panel(Color(0.12, 0.45, 0.25, 0.92), 22, 12)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bh := UIKit.hbox(10)
	bh.add_child(Icons.IconRect.new("house", Color(1.0, 0.9, 0.5), 36))
	banner_lbl = UIKit.label("ALL THREE SPLASHED — RUN HOME!", 26, UIKit.TEXT, true)
	bh.add_child(banner_lbl)
	banner.add_child(bh)
	banner.visible = false
	root.add_child(banner)

	# --- role reveal card
	reveal = UIKit.panel(Color(0.10, 0.12, 0.28, 0.95), 30, 28)
	reveal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reveal.custom_minimum_size = Vector2(760, 0)
	root.add_child(reveal)

	# --- feed (bottom-left above the stick zone)
	feed_box = UIKit.vbox(2)
	feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(feed_box)

	# --- capture / finished overlay
	overlay = UIKit.panel(Color(0.10, 0.12, 0.28, 0.88), 26, 20)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ov := UIKit.vbox(4)
	overlay_title = UIKit.label("", 40, UIKit.ACCENT, true, HORIZONTAL_ALIGNMENT_CENTER)
	overlay_sub = UIKit.label("", 24, UIKit.TEXT, false, HORIZONTAL_ALIGNMENT_CENTER)
	ov.add_child(overlay_title)
	ov.add_child(overlay_sub)
	overlay.add_child(ov)
	overlay.visible = false
	root.add_child(overlay)
	spectate_lbl = UIKit.outlined(UIKit.label("", 24, UIKit.MUTED, true, HORIZONTAL_ALIGNMENT_CENTER), 7)
	spectate_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(spectate_lbl)

	coach = UIKit.panel(Color(0.12, 0.36, 0.26, 0.92), 22, 14)
	coach.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ch := UIKit.hbox(10)
	ch.add_child(Icons.IconRect.new("star", UIKit.ACCENT, 34))
	coach_lbl = UIKit.label("", 26, UIKit.TEXT, true)
	coach_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	coach_lbl.custom_minimum_size = Vector2(560, 0)
	ch.add_child(coach_lbl)
	coach.add_child(ch)
	coach.visible = false
	root.add_child(coach)
	_build_pause()
	_build_reveal()
	get_viewport().size_changed.connect(_layout)
	_layout()


func _build_reveal() -> void:
	for c in reveal.get_children():
		c.queue_free()
	var v := UIKit.vbox(10)
	var my_role: int = TC.Role.SPECTATOR
	if mc.roster.has(mc.local_slot):
		my_role = int(mc.roster[mc.local_slot]["role"])
	var is_patrol := my_role == TC.Role.PATROL
	var title := "YOU'RE ON THE NIGHT WATCH" if is_patrol else ("YOU'RE A RUNNER" if my_role == TC.Role.RUNNER else "SPECTATING")
	v.add_child(UIKit.label(title, 44, UIKit.PATROL if is_patrol else UIKit.RUNNER, true, HORIZONTAL_ALIGNMENT_CENTER))
	var card := UIKit.label(TC.PATROL_CARD if is_patrol else TC.RUNNER_CARD, 28, UIKit.TEXT, false, HORIZONTAL_ALIGNMENT_CENTER)
	card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.custom_minimum_size = Vector2(700, 0)
	v.add_child(card)
	var targets_row := UIKit.hbox(18)
	targets_row.alignment = BoxContainer.ALIGNMENT_CENTER
	for wi in mc.targets:
		var w: Dictionary = mc.layout.waters[int(wi)]
		var cell := UIKit.hbox(6)
		cell.add_child(Icons.IconRect.new(w["icon"], w["color"], 34))
		cell.add_child(UIKit.label(w["name"], 24, w["color"], true))
		targets_row.add_child(cell)
	v.add_child(UIKit.label("Tonight's splash spots", 20, UIKit.MUTED, false, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(targets_row)
	var teams := UIKit.hbox(30)
	teams.alignment = BoxContainer.ALIGNMENT_CENTER
	for role in [TC.Role.RUNNER, TC.Role.PATROL]:
		var col := UIKit.vbox(2)
		col.add_child(UIKit.label("Runners (6)" if role == TC.Role.RUNNER else "Night Watch (2)", 22, UIKit.RUNNER if role == TC.Role.RUNNER else UIKit.PATROL, true))
		for s in mc.roster:
			var e: Dictionary = mc.roster[s]
			if int(e["role"]) == role:
				col.add_child(UIKit.label(String(e["name"]) + ("  · BOT" if bool(e["is_bot"]) else "") + ("  (you)" if int(s) == mc.local_slot else ""), 20, UIKit.TEXT))
		teams.add_child(col)
	v.add_child(teams)
	reveal.add_child(v)


func _build_pause() -> void:
	pause_panel = UIKit.panel(Color(0.08, 0.10, 0.24, 0.97), 30, 26)
	pause_panel.visible = false
	pause_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	var v := UIKit.vbox(14)
	v.add_child(UIKit.label("Paused (the round keeps running)", 30, UIKit.TEXT, true, HORIZONTAL_ALIGNMENT_CENTER))
	var sens_row := UIKit.hbox(10)
	sens_row.add_child(UIKit.label("Camera sensitivity", 24))
	var sl := HSlider.new()
	sl.min_value = 0.3
	sl.max_value = 2.5
	sl.step = 0.05
	sl.value = Controls.sensitivity
	sl.custom_minimum_size = Vector2(260, 40)
	sl.value_changed.connect(func(val: float) -> void:
		Controls.sensitivity = val
		Save.set_setting("sensitivity", val))
	sens_row.add_child(sl)
	v.add_child(sens_row)
	var rm := CheckButton.new()
	rm.text = "Reduced camera motion"
	rm.button_pressed = mc.reduced_motion
	rm.toggled.connect(func(on: bool) -> void:
		mc.reduced_motion = on
		Save.set_setting("reduced_motion", on))
	v.add_child(rm)
	var resume := UIKit.button("Resume", Color(0.3, 0.7, 0.45))
	resume.pressed.connect(_toggle_pause)
	v.add_child(resume)
	var leave := UIKit.button("Leave match", UIKit.BAD)
	leave.pressed.connect(func() -> void: mc.leave_match())
	v.add_child(leave)
	pause_panel.add_child(v)
	root.add_child(pause_panel)
	pause_panel.set_meta("resume", resume)


func _toggle_pause() -> void:
	pause_panel.visible = not pause_panel.visible
	if pause_panel.visible:
		(pause_panel.get_meta("resume") as Button).grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()
		get_viewport().set_input_as_handled()


func _layout() -> void:
	_safe = UIKit.safe_margins(get_viewport())
	var vs := get_viewport().get_visible_rect().size
	for c in root.get_children():
		if not (c is Control):
			continue
		var a: String = String(c.get_meta("anchor", ""))
		var cs: Vector2 = (c as Control).get_combined_minimum_size()
		match a:
			"top":
				c.position = Vector2((vs.x - cs.x) * 0.5, _safe.position.y)
			"top_left":
				c.position = _safe.position + Vector2(4, 0)
			"top_right":
				c.position = Vector2(vs.x - _safe.size.x - cs.x, _safe.position.y)
	pause_panel.position = (vs - pause_panel.get_combined_minimum_size()) * 0.5


func set_spectating(slot: int) -> void:
	_spectating = slot


func toast(text: String, col: Color = UIKit.TEXT) -> void:
	toast_lbl.text = text
	toast_lbl.add_theme_color_override("font_color", col)
	toast_t = 2.4


func feed(text: String, role: int) -> void:
	var l := UIKit.outlined(UIKit.label(text, 20, UIKit.RUNNER if role == TC.Role.RUNNER else (UIKit.PATROL if role == TC.Role.PATROL else UIKit.MUTED), true), 6)
	l.set_meta("t", 6.0)
	feed_box.add_child(l)
	while feed_box.get_child_count() > 5:
		feed_box.get_child(0).queue_free()
		feed_box.remove_child(feed_box.get_child(0))


func emote_bubble(slot: int, emote_id: int) -> void:
	emotes[slot] = {"id": emote_id, "t": 2.2}


func refresh(delta: float) -> void:
	_t += delta
	info = mc.local_info()
	var phase: int = info.get("phase", TC.Phase.REVEAL)
	var role: int = info.get("role", TC.Role.RUNNER)
	var vs := get_viewport().get_visible_rect().size
	# timer
	var tl: float = info.get("time_left", 0.0)
	timer_lbl.text = "%d:%02d" % [int(tl) / 60, int(tl) % 60]
	timer_lbl.add_theme_color_override("font_color", UIKit.BAD if tl < 30.0 and phase == TC.Phase.PLAYING else UIKit.TEXT)
	var fin: int = info.get("finished", 0)
	home_lbl.text = "%d / %d RUNNERS HOME" % [fin, mc.cfg.runners_needed]
	role_lbl.text = "NIGHT WATCH" if role == TC.Role.PATROL else ("RUNNER" if role == TC.Role.RUNNER else "SPECTATOR")
	role_lbl.add_theme_color_override("font_color", UIKit.PATROL if role == TC.Role.PATROL else UIKit.RUNNER)
	# targets with stamp states
	var stamps: int = info.get("stamps", 0)
	var tg: Array = info.get("targets", [])
	for i in target_rows.size():
		var row: Dictionary = target_rows[i]
		if i >= tg.size():
			(row["row"] as Control).visible = false
			continue
		var w: Dictionary = mc.layout.waters[int(tg[i])]
		var ic: Icons.IconRect = row["icon"]
		ic.kind = w["icon"]
		var done := (stamps & (1 << i)) != 0 and role == TC.Role.RUNNER
		ic.col = (w["color"] as Color).darkened(0.45) if done else w["color"]
		ic.queue_redraw()
		(row["name"] as Label).text = w["short"]
		(row["state"] as Label).text = "SPLASHED" if done else ""
	var all_done := role == TC.Role.RUNNER and stamps == 7
	var st: int = (info.get("rs", {}) as Dictionary).get("state", 0)
	banner.visible = all_done and phase == TC.Phase.PLAYING and st != TC.PState.FINISHED
	# countdown / reveal / release
	reveal.visible = phase == TC.Phase.REVEAL
	center_lbl.text = ""
	sub_lbl.text = ""
	if phase == TC.Phase.REVEAL or phase == TC.Phase.COUNTDOWN:
		var cd: float = info.get("countdown", 0.0)
		if cd <= mc.cfg.start_countdown_s + 0.01:
			reveal.visible = false
			center_lbl.text = str(int(ceil(cd))) if cd > 0.0 else "GO!"
	elif phase == TC.Phase.PLAYING:
		var rel: float = info.get("release_left", 0.0)
		var rt := mc.cfg.match_duration_s - tl
		if rt < 1.0:
			center_lbl.text = "GO!"
		if rel > 0.0:
			sub_lbl.text = ("Head start! Night Watch released in %d" % int(ceil(rel))) if role != TC.Role.PATROL else ("Runners have a head start… you're released in %d" % int(ceil(rel)))
	elif phase == TC.Phase.RESULTS or phase == TC.Phase.ENDED:
		var res: Dictionary = mc.sim.results if mc.sim else mc._client_results
		var oc: int = res.get("outcome", 0)
		center_lbl.text = "RUNNERS WIN!" if oc == TC.Outcome.RUNNERS_WIN else ("NIGHT WATCH WINS!" if oc == TC.Outcome.PATROL_WIN else "ROUND ENDED")
	# toast + feed fade
	toast_t = maxf(0.0, toast_t - delta)
	toast_lbl.modulate.a = clampf(toast_t / 0.4, 0.0, 1.0)
	for c in feed_box.get_children():
		var t: float = float(c.get_meta("t", 0.0)) - delta
		c.set_meta("t", t)
		(c as Control).modulate.a = clampf(t / 1.0, 0.0, 1.0)
	# overlay: captured / finished / spectating
	overlay.visible = false
	var rs: Dictionary = info.get("rs", {})
	if role != TC.Role.SPECTATOR and phase == TC.Phase.PLAYING:
		if st == TC.PState.CAPTURED:
			var pen: float = info.get("penalty", 0.0)
			overlay.visible = true
			overlay_title.text = "CAUGHT!  %d" % int(ceil(pen))
			overlay_sub.text = "Your splashes are safe. You'll pop back near your last splash spot."
			var ps := int(ceil(pen))
			if ps != _last_penalty_sec and ps <= 3 and ps > 0:
				Sfx.play("tick")
			_last_penalty_sec = ps
		elif st == TC.PState.FINISHED:
			overlay.visible = true
			overlay_title.text = "HOME SAFE!"
			overlay_sub.text = "Cheer your team on — they need %d more." % maxi(0, mc.cfg.runners_needed - fin)
	if _spectating >= 0 and mc.roster.has(_spectating):
		spectate_lbl.text = "Watching %s  ·  next: %s" % [mc.roster[_spectating]["name"], "Tab" if Controls.device == "keyboard" else ("RB" if Controls.device == "gamepad" else "⟳")]
	else:
		spectate_lbl.text = ""
	for slot in emotes.keys():
		emotes[slot]["t"] = float(emotes[slot]["t"]) - delta
		if float(emotes[slot]["t"]) <= 0.0:
			emotes.erase(slot)
	_update_coach(delta, phase, role)
	_place(vs)
	draw_layer.queue_redraw()
	compass.queue_redraw()
	minimap.queue_redraw()


func _place(vs: Vector2) -> void:
	var cl := center_lbl.get_combined_minimum_size()
	center_lbl.position = Vector2((vs.x - cl.x) * 0.5, vs.y * 0.30 - cl.y * 0.5)
	center_lbl.size = cl
	var sl := sub_lbl.get_combined_minimum_size()
	sub_lbl.position = Vector2((vs.x - sl.x) * 0.5, vs.y * 0.24)
	sub_lbl.size = sl
	var tl := toast_lbl.get_combined_minimum_size()
	toast_lbl.position = Vector2((vs.x - tl.x) * 0.5, vs.y * 0.62)
	toast_lbl.size = tl
	var bs := banner.get_combined_minimum_size()
	banner.position = Vector2((vs.x - bs.x) * 0.5, _safe.position.y + 132)
	banner.size = bs
	var rv := reveal.get_combined_minimum_size()
	reveal.position = (vs - rv) * 0.5
	reveal.size = rv
	var os := overlay.get_combined_minimum_size()
	overlay.position = Vector2((vs.x - os.x) * 0.5, vs.y * 0.18)
	overlay.size = os
	var fs := feed_box.get_combined_minimum_size()
	feed_box.position = Vector2(_safe.position.x + 6, vs.y * 0.42 - fs.y)
	var cs := coach.get_combined_minimum_size()
	coach.position = Vector2((vs.x - cs.x) * 0.5, vs.y * 0.66)
	coach.size = cs
	var ss := spectate_lbl.get_combined_minimum_size()
	spectate_lbl.position = Vector2((vs.x - ss.x) * 0.5, vs.y - _safe.size.y - 150)
	spectate_lbl.size = ss


func _hint(kind: String) -> String:
	var d := Controls.device
	var table := {
		"move": {"touch": "put your left thumb down and drag", "gamepad": "left stick", "keyboard": "W A S D"},
		"look": {"touch": "drag on the right side of the screen", "gamepad": "right stick", "keyboard": "hold right mouse and drag (or I J K L)"},
		"jump": {"touch": "tap Jump", "gamepad": "press A / Cross", "keyboard": "press Space"},
		"sprint": {"touch": "push the stick all the way to its outer ring", "gamepad": "hold LB or RB", "keyboard": "hold Shift"},
	}
	return String(table[kind].get(d, table[kind]["touch"]))


func _update_coach(delta: float, phase: int, role: int) -> void:
	var tut := bool(mc.start.get("tutorial", false))
	if not tut or role != TC.Role.RUNNER or phase < TC.Phase.PLAYING or phase > TC.Phase.PLAYING:
		coach.visible = false
		return
	var rs: Dictionary = info.get("rs", {})
	if not rs.has("pos"):
		return
	var p: Vector3 = rs["pos"]
	if _coach_last != Vector3.INF:
		_coach_moved += Vector2(p.x - _coach_last.x, p.z - _coach_last.z).length()
	_coach_last = p
	_coach_look += absf(wrapf(mc.camera.yaw - _coach_yaw, -PI, PI))
	_coach_yaw = mc.camera.yaw
	var stamps: int = info.get("stamps", 0)
	var st: int = rs.get("state", 0)
	var steps := [
		["Move: %s." % _hint("move"), _coach_moved > 4.0],
		["Look around: %s." % _hint("look"), _coach_look > 1.2],
		["Jump: %s." % _hint("jump"), not bool(rs.get("on_floor", true)) and (rs.get("vel", Vector3.ZERO) as Vector3).y > 2.0],
		["Dive: jump, then %s again while in the air." % _hint("jump").replace("tap ", "tap ").replace("press ", "press "), bool(rs.get("diving", false))],
		["Sprint: %s. It refills quickly." % _hint("sprint"), bool(rs.get("sprinting", false))],
		["Follow a glowing beam (see the compass at the top) and jump into that water!", stamps != 0],
		["SPLASH! Two more spots to go. Each one has its own shape and colour.", stamps == 7],
		["All three! Now run home through ANY of the dorm's four doors.", st == TC.PState.FINISHED],
		["You did the Trifecta! The Night Watch is out now — cheer on your team.", false],
	]
	while coach_step < steps.size() - 1 and bool(steps[coach_step][1]):
		coach_step += 1
		_coach_flash = 0.6
		Sfx.play("pickup")
	var rel: float = info.get("release_left", 0.0)
	var txt: String = steps[coach_step][0]
	if rel > 0.0 and coach_step < 7:
		txt += "\n(Night Watch is still in the shed: %ds)" % int(ceil(rel))
	coach_lbl.text = txt
	_coach_flash = maxf(0.0, _coach_flash - delta)
	coach.modulate = Color(1, 1, 1, 1).lerp(Color(1.4, 1.4, 1.0, 1), _coach_flash)
	coach.visible = true


func world_to_screen(p: Vector3) -> Vector2:
	var cam := mc.camera
	if cam == null or cam.is_position_behind(p):
		return Vector2(-9999, -9999)
	return cam.unproject_position(p)


# ---------------------------------------------------------------------------
class DrawLayer:
	extends Control
	var hud: MatchHUD

	func _draw() -> void:
		var info := hud.info
		var vs := size
		# spotted cue: restrained edge vignette + eye icon (driven by real detection)
		var spotted: float = info.get("spotted", 0.0)
		if spotted > 0.0 and int(info.get("role", 0)) == TC.Role.RUNNER:
			var a := clampf(spotted / 1.0, 0.0, 1.0) * (0.55 + 0.2 * sin(hud._t * 8.0))
			var col := Color(1.0, 0.35, 0.3, 0.32 * a)
			for i in 6:
				var w := 18.0 + float(i) * 10.0
				draw_rect(Rect2(0, 0, vs.x, w), Color(col.r, col.g, col.b, col.a / float(i + 1)))
				draw_rect(Rect2(0, vs.y - w, vs.x, w), Color(col.r, col.g, col.b, col.a / float(i + 1)))
			Icons.draw_shape(self, "eye", Vector2(vs.x * 0.5, hud._safe.position.y + 170), 22, Color(1.0, 0.5, 0.4, a + 0.3))
		# noise direction chevrons around a ring (visual equivalent of audio)
		var cam := hud.mc.camera
		var me: Dictionary = info.get("rs", {})
		if cam and me.has("pos"):
			var center := Vector2(vs.x * 0.5, vs.y * 0.55)
			for n in info.get("noises", []):
				var rel: Vector3 = (n["pos"] as Vector3) - (me["pos"] as Vector3)
				var ang := atan2(rel.x, -rel.z) + cam.yaw
				var dir := Vector2(sin(ang), -cos(ang))
				var loud: float = n["loud"]
				var r := minf(vs.x, vs.y) * 0.36
				var p := center + dir * r
				var kind: String = n["kind"]
				var ncol := Color(1.0, 0.75, 0.4, 0.35 + 0.55 * loud) if kind == "cart" else Color(0.8, 0.9, 1.0, 0.35 + 0.55 * loud)
				var tip := p + dir * 16.0
				var side := Vector2(-dir.y, dir.x) * 12.0
				draw_colored_polygon(PackedVector2Array([tip, p - side, p + side]), ncol)
				if kind == "cart":
					Icons.draw_shape(self, "cart", p - dir * 22.0, 11, ncol)
				else:
					draw_circle(p - dir * 18.0 + side * 0.4, 4.0, ncol)
					draw_circle(p - dir * 24.0 - side * 0.4, 4.0, ncol)
		# emote bubbles above characters
		for slot in hud.emotes:
			var v: CharacterView = hud.mc.views.get(slot)
			if v == null or not v.visible:
				continue
			var sp := hud.world_to_screen(v.global_position + Vector3(0, 2.6, 0))
			if sp.x < -1000:
				continue
			var label: String = TC.EMOTE_LABELS.get(TC.EMOTES[int(hud.emotes[slot]["id"])], "!")
			var f := UIKit.font(true)
			var tw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
			draw_style_box(UIKit.box(Color(1, 1, 1, 0.92), 16), Rect2(sp - Vector2(tw * 0.5 + 12, 22), Vector2(tw + 24, 40)))
			draw_string(f, sp + Vector2(-tw * 0.5, 8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, UIKit.INK)
		# patrol: splash markers in the world (brief, location only)
		for m in info.get("markers", []):
			var w: Dictionary = hud.mc.layout.waters[int(m["water"])]
			var c: Vector2 = w["center"]
			var sp2 := hud.world_to_screen(Vector3(c.x, 3.0, c.y))
			if sp2.x > -1000:
				var pulse := 1.0 + 0.2 * sin(hud._t * 10.0)
				draw_arc(sp2, 26.0 * pulse, 0, TAU, 24, w["color"], 4.0)
				Icons.draw_shape(self, w["icon"], sp2, 14, w["color"])
				draw_string(UIKit.font(true), sp2 + Vector2(-40, 48), "SPLASH!", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, w["color"])
		# sprint meter for non-touch devices (touch draws it on the stick)
		if Controls.device != "touch" and int(info.get("role", 0)) == TC.Role.RUNNER:
			var sp3: float = info.get("sprint", 1.0)
			var base := Vector2(vs.x * 0.5 - 90, vs.y - hud._safe.size.y - 26)
			draw_style_box(UIKit.box(Color(0, 0, 0, 0.45), 8), Rect2(base, Vector2(180, 14)))
			draw_style_box(UIKit.box(UIKit.ACCENT if sp3 > 0.15 else UIKit.BAD, 8), Rect2(base, Vector2(180 * sp3, 14)))


class Compass:
	extends Control
	var hud: MatchHUD

	func _draw() -> void:
		var info := hud.info
		var me: Dictionary = info.get("rs", {})
		var cam := hud.mc.camera
		var w := size.x
		var h := size.y
		draw_style_box(UIKit.box(Color(0.05, 0.07, 0.18, 0.55), 14), Rect2(Vector2.ZERO, size))
		if cam == null or not me.has("pos"):
			return
		var pos: Vector3 = me["pos"]
		var fov := deg_to_rad(150.0)
		var items: Array = []
		var role: int = info.get("role", 0)
		var stamps: int = info.get("stamps", 0)
		var tg: Array = info.get("targets", [])
		for i in tg.size():
			var wt: Dictionary = hud.mc.layout.waters[int(tg[i])]
			var done := (stamps & (1 << i)) != 0 and role == TC.Role.RUNNER
			if done:
				continue
			items.append({"p": wt["center"], "icon": wt["icon"], "col": wt["color"]})
		var home := role == TC.Role.RUNNER and stamps == 7
		var dist_items: Array = []
		if home or role == TC.Role.PATROL:
			# nearest entrance only (keeps the compass readable)
			var best: Dictionary = hud.mc.layout.dorm_doors[0]
			var bd := 1e9
			for d in hud.mc.layout.dorm_doors:
				var dd := (d["pos"] as Vector2).distance_to(Vector2(pos.x, pos.z))
				if dd < bd:
					bd = dd
					best = d
			items.append({"p": best["pos"], "icon": "house", "col": Color(1.0, 0.9, 0.55) if home else Color(1, 1, 1, 0.55)})
		for m in info.get("markers", []):
			var wt2: Dictionary = hud.mc.layout.waters[int(m["water"])]
			items.append({"p": wt2["center"], "icon": "drop", "col": Color(1, 1, 1)})
		# heading ticks
		for k in 8:
			var ang := float(k) * TAU / 8.0
			var rel := wrapf(ang - (-cam.yaw), -PI, PI)
			if absf(rel) < fov * 0.5:
				var x := w * 0.5 + rel / (fov * 0.5) * (w * 0.5 - 16)
				var lbl: String = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][k]
				draw_string(UIKit.font(true), Vector2(x - 8, h * 0.75), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.45))
		for it in items:
			var p: Vector2 = it["p"]
			var dx := p.x - pos.x
			var dz := p.y - pos.z
			var bearing := atan2(dx, -dz)
			var rel2 := wrapf(bearing + cam.yaw, -PI, PI)
			var x2 := w * 0.5 + clampf(rel2 / (fov * 0.5), -1.0, 1.0) * (w * 0.5 - 18)
			var dist := Vector2(dx, dz).length()
			var col: Color = it["col"]
			if absf(rel2) > fov * 0.5:
				col.a = 0.55
			Icons.draw_shape(self, it["icon"], Vector2(x2, h * 0.42), 13, col)
			if not dist_items.has(it["icon"]):
				draw_string(UIKit.font(), Vector2(x2 - 14, h - 2), "%dm" % int(dist), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.7))
		draw_line(Vector2(w * 0.5, 2), Vector2(w * 0.5, 9), Color(1, 1, 1, 0.8), 2.0)


class Minimap:
	extends Control
	var hud: MatchHUD

	func _draw() -> void:
		var info := hud.info
		var me: Dictionary = info.get("rs", {})
		var s := size
		var c := s * 0.5
		var radius := minf(s.x, s.y) * 0.5
		draw_circle(c, radius, Color(0.06, 0.09, 0.2, 0.75))
		var L := hud.mc.layout
		var b := CampusLayout.BOUNDS
		var scale := (radius * 2.0 - 10.0) / maxf(b.size.x, b.size.y)
		var to_map := func(p: Vector2) -> Vector2:
			return c + (p - b.get_center()) * scale
		for r in L.roads:
			var pts: PackedVector2Array = r["pts"]
			for i in pts.size() - 1:
				draw_line(to_map.call(pts[i]), to_map.call(pts[i + 1]), Color(0.45, 0.5, 0.7, 0.8), 2.5)
		for bd in L.buildings:
			var bp: Vector2 = bd["pos"]
			var bs: Vector2 = bd["size"]
			var tl: Vector2 = to_map.call(bp - bs * 0.5)
			draw_rect(Rect2(tl, bs * scale), Color(0.6, 0.62, 0.8, 0.85))
		var tg: Array = info.get("targets", [])
		var stamps: int = info.get("stamps", 0)
		var role: int = info.get("role", 0)
		for i in L.waters.size():
			var w: Dictionary = L.waters[i]
			var wp: Vector2 = to_map.call(w["center"])
			var ti := tg.find(i)
			if ti >= 0:
				var done := (stamps & (1 << ti)) != 0 and role == TC.Role.RUNNER
				Icons.draw_shape(self, w["icon"], wp, 9, (w["color"] as Color).darkened(0.5) if done else w["color"])
			else:
				draw_circle(wp, 3.5, Color(0.4, 0.6, 0.9, 0.7))
		Icons.draw_shape(self, "house", to_map.call(Vector2(0, 112)), 8, Color(1.0, 0.9, 0.55))
		# teammates (same role only) and own arrow
		var my_role := role
		for slot in hud.mc.roster:
			if int(slot) == hud.mc.local_slot:
				continue
			if int(hud.mc.roster[slot]["role"]) != my_role:
				continue
			var rs := hud.mc._player_rs(int(slot))
			if rs.has("pos") and int(rs.get("state", 0)) != TC.PState.FINISHED:
				var pp: Vector3 = rs["pos"]
				draw_circle(to_map.call(Vector2(pp.x, pp.z)), 3.5, UIKit.PATROL if my_role == TC.Role.PATROL else UIKit.RUNNER)
		if my_role == TC.Role.PATROL:
			for i in hud.mc.cart_views.size():
				var crs := hud.mc._cart_rs(i)
				if crs.has("pos"):
					var cp: Vector3 = crs["pos"]
					Icons.draw_shape(self, "cart", to_map.call(Vector2(cp.x, cp.z)), 6, UIKit.PATROL)
			for m in info.get("markers", []):
				var w2: Dictionary = L.waters[int(m["water"])]
				draw_arc(to_map.call(w2["center"]), 10.0 + 3.0 * sin(hud._t * 10.0), 0, TAU, 16, Color(1, 1, 1), 2.0)
		if me.has("pos"):
			var mp: Vector3 = me["pos"]
			var mpos: Vector2 = to_map.call(Vector2(mp.x, mp.z))
			var yaw: float = me.get("yaw", 0.0)
			var f := Vector2(-sin(yaw), -cos(yaw))
			var sd := Vector2(-f.y, f.x)
			draw_colored_polygon(PackedVector2Array([mpos + f * 9.0, mpos - f * 5.0 + sd * 5.0, mpos - f * 5.0 - sd * 5.0]), Color(1, 1, 1))
		draw_arc(c, radius - 1.0, 0, TAU, 48, Color(1, 1, 1, 0.35), 2.0)
