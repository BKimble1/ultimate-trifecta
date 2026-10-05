class_name MatchHUD
extends CanvasLayer
## In-match HUD. Keeps the screen focused on the world: compact corners,
## safe-area aware, colour always paired with an icon/shape.

var mc: MatchController
var root: Control
var chat: MatchChat
var timer_lbl: Label
var home_lbl: Label          # (Pass 8: the goal bar's sentence, goal_lbl)
var coin_lbl: Label
var coin_chip: PanelContainer
var _coin_shown := -1
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
var role_icon: Icons.IconRect
var round_lbl: Label
var coach_step := 0
# Pass 8: the team goal bar, the personal card and the pace cue
const PERSONAL_W := 312.0
const HOME_OVERLAY_S := 3.5       # "Home · 2nd to finish" in the middle, then watching a teammate
const PACE_CUE_S := 2.5           # how long a place change shows its small arrow
const DANGER_M := 20.0            # a spotted Night Watch this close gets the chip
var goal_bar: PanelContainer
var goal_row: HBoxContainer
var goal_row2: HBoxContainer
var goal_lbl: Label
var tracker: HomeTracker
var clock_box: HBoxContainer
var clock_icon: ClockIcon
var danger_chip: PanelContainer
var danger_lbl: Label
var personal: ObjectiveChips
## what the personal card shows now, as data (tests read it): rows of
## {type, text, ...} - see _personal_rows()
var personal_rows: Array = []
var _pace_place := -1
var _pace_delta := 0
var _pace_cue_t := 0.0
var _home_t := 0.0
var _home_seen := false
const SPRINT_HINT := "Sprint empty · ease off to recharge"
var sprint_hint: PanelContainer
var sprint_meter: SprintMeter
var _two_row := false
var _coach_moved := 0.0
var _coach_last := Vector3.INF
var _coach_look := 0.0
var _coach_yaw := 0.0
var _coach_flash := 0.0


func setup(controller: MatchController) -> void:
	mc = controller
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS   # the pause menu runs while Practice is paused
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIKit.theme()
	add_child(root)
	_build_stamp_pop()
	draw_layer = DrawLayer.new()
	(draw_layer as DrawLayer).hud = self
	draw_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	draw_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(draw_layer)

	# --- top centre (Pass 8): the team goal and the one round clock, on one
	# bar: a segmented tracker of real finishes (never splashes or catches),
	# the role's sentence and the clock -
	#   runner       [■■□□] Team home 2/4 · Need 2 more     2:31
	#   Night Watch  [■■□□] Runners home 2/4 · Hold until   0:48
	# On a narrow screen (iPad, or a long dorm-free sentence) the clock moves
	# to a second row under the sentence.  It never claims a win from time.
	var top := UIKit.vbox(4)
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.alignment = BoxContainer.ALIGNMENT_BEGIN
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	top.set_meta("anchor", "top")
	goal_bar = UIKit.panel(Color(UIKit.NAVY, 0.66), 22, 10)
	goal_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	goal_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var gv := UIKit.vbox(0)
	gv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	goal_row = UIKit.hbox(10)
	goal_row.alignment = BoxContainer.ALIGNMENT_CENTER
	goal_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tracker = HomeTracker.new()
	tracker.needed = mc.cfg.runners_needed
	tracker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	goal_row.add_child(tracker)
	goal_lbl = UIKit.label("", 19, UIKit.IVORY, true)
	goal_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	goal_lbl.add_theme_font_override("font", UIKit.font_w(700))
	goal_row.add_child(goal_lbl)
	home_lbl = goal_lbl
	clock_box = UIKit.hbox(4)
	clock_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	clock_icon = ClockIcon.new()
	clock_icon.custom_minimum_size = Vector2(24, 24)
	clock_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	clock_box.add_child(clock_icon)
	# the clock in tabular digits (no jitter as they change)
	timer_lbl = UIKit.label("4:00", 36, UIKit.IVORY, false, HORIZONTAL_ALIGNMENT_CENTER)
	timer_lbl.add_theme_font_override("font", UIKit.font_num(800))
	clock_box.add_child(timer_lbl)
	goal_row.add_child(clock_box)
	gv.add_child(goal_row)
	goal_row2 = UIKit.hbox(0)
	goal_row2.alignment = BoxContainer.ALIGNMENT_CENTER
	goal_row2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gv.add_child(goal_row2)
	goal_bar.add_child(gv)
	top.add_child(goal_bar)
	# a legitimately spotted Night Watch nearby (runners): a small chip under
	# the goal, only while that Watch is in your sight (MatchController.last_seen)
	danger_chip = UIKit.panel(Color(0.42, 0.12, 0.1, 0.82), 999, 8)
	danger_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	danger_chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var dh := UIKit.hbox(6)
	dh.add_child(Icons.IconRect.new("whistle", UIKit.PATROL, 20))
	danger_lbl = UIKit.label("", 18, UIKit.IVORY, true)
	dh.add_child(danger_lbl)
	danger_chip.add_child(dh)
	danger_chip.visible = false
	top.add_child(danger_chip)

	# --- top left: role badge, quiet round label, coins; then the personal
	# card (you: progress, your next action, your pace or your tags)
	var tl := UIKit.vbox(6)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.set_meta("anchor", "top_left")
	root.add_child(tl)
	var badge_row := UIKit.hbox(8)
	badge_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge := UIKit.panel(Color(UIKit.NAVY, 0.7), 999, 10)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bh0 := UIKit.hbox(6)
	role_icon = Icons.IconRect.new("whistle" if _my_role() == TC.Role.PATROL else "drop", UIKit.TEAL, 20)
	bh0.add_child(role_icon)
	role_lbl = UIKit.label("Runner", 18, UIKit.TEAL, true)
	bh0.add_child(role_lbl)
	badge.add_child(bh0)
	badge_row.add_child(badge)
	round_lbl = UIKit.label("", 17, UIKit.IVORY_MUTED, true)
	round_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sr: Dictionary = mc.start.get("series", {})
	if int(sr.get("total", 1)) > 1:
		round_lbl.text = "Round %d/%d" % [int(sr.get("round", 1)), int(sr.get("total", 1))]
	elif bool(mc.start.get("practice", false)):
		round_lbl.text = "Practice"
	badge_row.add_child(round_lbl)
	# V6: the coins this player has collected this round
	coin_chip = UIKit.panel(Color(UIKit.NAVY, 0.6), 999, 8)
	coin_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ch2 := UIKit.hbox(4)
	var ci := CoinIcon.new()
	ci.custom_minimum_size = Vector2(20, 20)
	ch2.add_child(ci)
	coin_lbl = UIKit.label("0", 17, Color(1.0, 0.86, 0.45), true, HORIZONTAL_ALIGNMENT_CENTER)
	coin_lbl.add_theme_font_override("font", UIKit.font_num(700))
	ch2.add_child(coin_lbl)
	coin_chip.add_child(ch2)
	coin_chip.visible = (mc.start.get("coins", []) as Array).size() > 0
	badge_row.add_child(coin_chip)
	tl.add_child(badge_row)
	personal = ObjectiveChips.new()
	personal.hud = self
	personal.custom_minimum_size = Vector2(PERSONAL_W, 132)
	personal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.add_child(personal)
	target_rows = [personal]

	# --- top right: compact minimap + pause
	var tr := UIKit.hbox(10)
	tr.set_meta("anchor", "top_right")
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tr)
	minimap = Minimap.new()
	(minimap as Minimap).hud = self
	minimap.custom_minimum_size = Vector2(150, 150)
	tr.add_child(minimap)
	# both map pictures are drawn once now (under the loading screen), not on
	# the first look at the map
	CampusMap.shared().texture(mc.layout, CampusMap.MINI_PX)
	CampusMap.shared().texture(mc.layout, CampusMap.FULL_PX)
	pause_btn = UIKit.icon_button("pause", "", 64)
	pause_btn.focus_mode = Control.FOCUS_NONE
	pause_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	pause_btn.pressed.connect(_toggle_pause)
	tr.add_child(pause_btn)

	# --- centre messages
	center_lbl = UIKit.outlined(UIKit.label("", 84, UIKit.AMBER, true, HORIZONTAL_ALIGNMENT_CENTER), 12)
	center_lbl.add_theme_font_override("font", UIKit.font_num(800))
	center_lbl.set_anchors_preset(Control.PRESET_CENTER)
	center_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center_lbl)
	sub_lbl = UIKit.outlined(UIKit.label("", 24, UIKit.IVORY, true, HORIZONTAL_ALIGNMENT_CENTER), 7)
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(sub_lbl)
	toast_lbl = UIKit.outlined(UIKit.label("", 28, UIKit.IVORY, true, HORIZONTAL_ALIGNMENT_CENTER), 8)
	toast_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast_lbl)

	banner = UIKit.panel(Color(UIKit.SLATE, 0.9), 22, 12)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bh := UIKit.hbox(10)
	bh.add_child(Icons.IconRect.new("house", Color(1.0, 0.9, 0.5), 36))
	banner_lbl = UIKit.label("All three splashed · Run home!", 24, UIKit.TEXT, true)
	bh.add_child(banner_lbl)
	banner.add_child(bh)
	banner.visible = false
	root.add_child(banner)

	# --- role reveal card
	reveal = UIKit.panel(Color(UIKit.SLATE, 0.96), UIKit.R_PANEL, 30)
	reveal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reveal.custom_minimum_size = Vector2(760, 0)
	root.add_child(reveal)

	# --- feed (bottom-left above the stick zone)
	feed_box = UIKit.vbox(2)
	feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(feed_box)

	# --- capture / finished overlay
	overlay = UIKit.panel(Color(UIKit.SLATE, 0.9), UIKit.R_PANEL, 20)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ov := UIKit.vbox(4)
	overlay_title = UIKit.label("", 34, UIKit.AMBER, true, HORIZONTAL_ALIGNMENT_CENTER)
	overlay_title.add_theme_font_override("font", UIKit.font_w(800))
	overlay_sub = UIKit.label("", 21, UIKit.IVORY, false, HORIZONTAL_ALIGNMENT_CENTER)
	ov.add_child(overlay_title)
	ov.add_child(overlay_sub)
	overlay.add_child(ov)
	overlay.visible = false
	root.add_child(overlay)
	spectate_lbl = UIKit.outlined(UIKit.label("", 24, UIKit.MUTED, true, HORIZONTAL_ALIGNMENT_CENTER), 7)
	spectate_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(spectate_lbl)

	coach = UIKit.panel(Color(UIKit.SLATE, 0.92), 22, 14)
	coach.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ch := UIKit.hbox(10)
	ch.add_child(Icons.IconRect.new("star", UIKit.TEAL, 30))
	coach_lbl = UIKit.label("", UIKit.T_BODY, UIKit.IVORY, true)
	coach_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	coach_lbl.custom_minimum_size = Vector2(560, 0)
	ch.add_child(coach_lbl)
	coach.add_child(ch)
	coach.visible = false
	root.add_child(coach)
	# Pass 8: the sprint latch (an empty meter needs a release to re-arm):
	# a short hint with a tinted meter, only while sprint is still held
	sprint_hint = UIKit.panel(Color(0.36, 0.13, 0.12, 0.86), 999, 8)
	sprint_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := UIKit.hbox(8)
	var sm := SprintMeter.new()
	sm.custom_minimum_size = Vector2(64, 14)
	sm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sh.add_child(sm)
	sprint_meter = sm
	sh.add_child(UIKit.label(SPRINT_HINT, 18, UIKit.IVORY, true))
	sprint_hint.add_child(sh)
	sprint_hint.visible = false
	root.add_child(sprint_hint)
	_build_pause()
	_build_reveal()
	chat = MatchChat.attach(self)   # (V6) party rounds: Quick Chat + drawer
	get_viewport().size_changed.connect(_layout)
	_layout()


func _my_role() -> int:
	if mc and mc.roster.has(mc.local_slot):
		return int(mc.roster[mc.local_slot]["role"])
	return TC.Role.SPECTATOR


func _build_reveal() -> void:
	for c in reveal.get_children():
		c.queue_free()
	var v := UIKit.vbox(10)
	var my_role: int = TC.Role.SPECTATOR
	if mc.roster.has(mc.local_slot):
		my_role = int(mc.roster[mc.local_slot]["role"])
	var is_patrol := my_role == TC.Role.PATROL
	var title := "You're on the Night Watch" if is_patrol else ("You're a Runner" if my_role == TC.Role.RUNNER else "Spectating")
	var sr: Dictionary = mc.start.get("series", {})
	if int(sr.get("total", 1)) > 1:
		v.add_child(UIKit.styled("Round %d of %d" % [int(sr.get("round", 1)), int(sr.get("total", 1))], "overline", UIKit.IVORY_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var ttl := UIKit.styled(title, "display", UIKit.PATROL if is_patrol else UIKit.TEAL, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(ttl)
	# V6: tonight's home dorm (the runners are standing in it)
	var dn := CampusDorms.display_name(mc.home_dorm)
	var home_row := UIKit.hbox(8)
	home_row.alignment = BoxContainer.ALIGNMENT_CENTER
	home_row.add_child(Icons.IconRect.new("house", Color(1.0, 0.86, 0.5), 26))
	home_row.add_child(UIKit.label(("Home tonight: %s" % dn) if not is_patrol else ("The runners' home tonight: %s" % dn), 22, Color(1.0, 0.9, 0.62), true))
	v.add_child(home_row)
	if my_role != TC.Role.SPECTATOR:
		var lines := TC.role_lines(my_role, mc.cfg, dn)
		var card := UIKit.styled(lines[0], "body", UIKit.IVORY, HORIZONTAL_ALIGNMENT_CENTER)
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.custom_minimum_size = Vector2(680, 0)
		v.add_child(card)
		var note := UIKit.styled(lines[1], "caption", UIKit.IVORY_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		v.add_child(note)
	var targets_row := UIKit.hbox(18)
	targets_row.alignment = BoxContainer.ALIGNMENT_CENTER
	for wi in mc.targets:
		var w: Dictionary = mc.layout.waters[int(wi)]
		var cell := UIKit.hbox(6)
		cell.add_child(Icons.IconRect.new(w["icon"], w["color"], 34))
		cell.add_child(UIKit.label(w["name"], 23, w["color"], true))
		targets_row.add_child(cell)
	v.add_child(UIKit.styled("Tonight's splash spots", "overline", UIKit.IVORY_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(targets_row)
	var teams := UIKit.hbox(30)
	teams.alignment = BoxContainer.ALIGNMENT_CENTER
	for role in [TC.Role.RUNNER, TC.Role.PATROL]:
		var col := UIKit.vbox(2)
		var n := 0
		for s2 in mc.roster:
			if int(mc.roster[s2]["role"]) == role:
				n += 1
		col.add_child(UIKit.label(("Runners (%d)" if role == TC.Role.RUNNER else "Night Watch (%d)") % n, 20, UIKit.TEAL if role == TC.Role.RUNNER else UIKit.PATROL, true))
		for s in mc.roster:
			var e: Dictionary = mc.roster[s]
			if int(e["role"]) == role:
				col.add_child(UIKit.label(String(e["name"]) + ("  · BOT" if bool(e["is_bot"]) else "") + ("  (you)" if int(s) == mc.local_slot else ""), 18, UIKit.IVORY))
		teams.add_child(col)
	v.add_child(teams)
	reveal.add_child(v)


# --- V7: the pause menu and one owner for every match overlay ---------------
#
# V6's pause panel sat on the HUD layer (5) under the full-screen gameplay
# touch surface (layer 6), which only stepped aside for the Pause button,
# the minimap and chat: on a phone every tap on Resume, the slider or Leave
# match went to the surface instead (test_pause_input reproduces it with
# real touches).  Now:
#  - the menu lives on its own modal layer above gameplay input, behind a
#    dim backdrop that stops touches reaching the round;
#  - every match overlay (pause, the leave confirmation, the map, the chat
#    drawer) is registered here; gameplay touch input is hidden while any
#    is open, and every change cancels held fingers, queued presses and
#    look/sprint/throttle state, so one overlay closing never re-enables
#    controls under another;
#  - Practice and the tutorial really pause (the scene tree: sim, bots,
#    physics, timers, animation); an online round keeps running for
#    everyone, and says so.
const MODAL_LAYER := 8
## frames after the last overlay closes during which the round reads
## neutral input (the press that chose Resume never becomes a jump)
const INPUT_GRACE_FRAMES := 3

var modal: CanvasLayer
var _backdrop: ColorRect
var _pause_main: Control
var _pause_confirm: Control
var _confirm_text: Label
var _status_lbl: Label
var _info_lbl: Label
var _overlays: Array[String] = []
var _grace := 0
var _froze_tree := false
var _leaving := false
var _round_over := false
var _last_toggle_frame := -1
var pause_opens := 0        # tests: each open and close fires once
var pause_closes := 0


func _build_pause() -> void:
	modal = CanvasLayer.new()
	modal.name = "Modal"
	modal.layer = MODAL_LAYER
	modal.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(modal)
	var mroot := Control.new()
	mroot.set_anchors_preset(Control.PRESET_FULL_RECT)
	mroot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mroot.theme = UIKit.theme()
	modal.add_child(mroot)
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0, 0, 0, 0.5)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP      # nothing reaches the round
	_backdrop.visible = false
	mroot.add_child(_backdrop)
	pause_panel = UIKit.panel(Color(UIKit.SLATE, 0.98), UIKit.R_PANEL, 24)
	pause_panel.visible = false
	pause_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	mroot.add_child(pause_panel)
	var stack := UIKit.vbox(0)
	pause_panel.add_child(stack)
	var bw := 440.0
	var row_h := maxf(52.0, UIKit.touch_min())
	# main view: title, status, the two useful quick settings, Resume, Leave
	var v := UIKit.vbox(12)
	_pause_main = v
	stack.add_child(v)
	var online := mc != null and mc.session != null and mc.session.mode != NetSession.Mode.OFFLINE
	v.add_child(UIKit.heading("Menu" if online else "Paused", 32))
	_status_lbl = UIKit.label("Online match continues." if online else "The round is paused.", 18, UIKit.IVORY_MUTED)
	v.add_child(_status_lbl)
	# Pass 8: where you stand - the team goal, your progress or tags, and
	# (party rounds after the first results) the series standing
	_info_lbl = UIKit.label("", 18, UIKit.IVORY, false)
	_info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_lbl.custom_minimum_size = Vector2(bw, 0)
	v.add_child(_info_lbl)
	var sens_row := UIKit.hbox(12)
	var sl_l := UIKit.label("Camera", 20)
	sl_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl_l.custom_minimum_size = Vector2(110, 0)
	sens_row.add_child(sl_l)
	var sl := HSlider.new()
	sl.min_value = 0.3
	sl.max_value = 2.5
	sl.step = 0.05
	sl.value = Controls.sensitivity
	sl.custom_minimum_size = Vector2(bw - 122, row_h)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.accessibility_name = "Camera sensitivity"
	sl.value_changed.connect(func(val: float) -> void:
		Controls.sensitivity = val
		Save.set_setting("sensitivity", val))
	sens_row.add_child(sl)
	v.add_child(sens_row)
	var rm := CheckButton.new()
	rm.text = "Reduced motion"
	rm.button_pressed = mc.reduced_motion
	rm.custom_minimum_size = Vector2(bw, row_h)
	rm.toggled.connect(func(on: bool) -> void:
		mc.reduced_motion = on
		Save.set_setting("reduced_motion", on))
	v.add_child(rm)
	var resume := UIKit.primary("Resume", Vector2(bw, maxf(76.0, row_h)), 26)
	resume.pressed.connect(close_pause)
	v.add_child(resume)
	var leave := UIKit.quiet("Leave match", Vector2(bw, row_h), 20)
	leave.pressed.connect(_ask_leave)
	v.add_child(leave)
	# leave confirmation, in place of the main view (one overlay at a time)
	var c := UIKit.vbox(14)
	_pause_confirm = c
	c.visible = false
	stack.add_child(c)
	c.add_child(UIKit.heading("Leave match?", 30))
	_confirm_text = UIKit.label("", 19, UIKit.IVORY_MUTED)
	_confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_text.custom_minimum_size = Vector2(bw, 0)
	c.add_child(_confirm_text)
	var stay := UIKit.primary("Stay", Vector2(bw, maxf(72.0, row_h)), 24)
	stay.pressed.connect(_cancel_leave)
	c.add_child(stay)
	var go := UIKit.quiet("Leave", Vector2(bw, row_h), 20)
	go.pressed.connect(_confirm_leave)
	c.add_child(go)
	pause_panel.set_meta("resume", resume)
	pause_panel.set_meta("leave", leave)
	pause_panel.set_meta("stay", stay)
	pause_panel.set_meta("go", go)
	pause_panel.set_meta("slider", sl)
	pause_panel.set_meta("reduced", rm)


## The pause menu's short "where you stand" lines (Pass 8).
func pause_info() -> String:
	if mc == null or info.is_empty():
		return ""
	var role := int(info.get("role", TC.Role.SPECTATOR))
	var lines: Array[String] = []
	var goal := goal_text(role, int(info.get("finished", 0)))
	if role == TC.Role.PATROL:
		goal += " " + clock_text(float(info.get("time_left", 0.0)))
	lines.append(goal)
	if role == TC.Role.RUNNER:
		var st := int((info.get("rs", {}) as Dictionary).get("state", 0))
		if st == TC.PState.FINISHED:
			lines.append(home_line())
		else:
			lines.append("You: %d/3 waters · %s" % [_bits(int(info.get("stamps", 0))), pace_label()])
	elif role == TC.Role.PATROL:
		var tags := int(info.get("tags", 0))
		var d := int(info.get("distinct", 0))
		lines.append("You: %d tag%s · %d different runner%s" % [tags, "" if tags == 1 else "s", d, "" if d == 1 else "s"])
	var sr: Dictionary = mc.start.get("series", {})
	var sl := series_line()
	if int(sr.get("total", 1)) > 1:
		lines.append("Round %d/%d%s" % [int(sr.get("round", 1)), int(sr.get("total", 1)), (" · " + sl) if sl != "" else " · no series results yet"])
	return "\n".join(lines)


## Tests and tools: the pause menu's state and its controls.
func paused() -> bool:
	return pause_panel != null and pause_panel.visible


func resume_button() -> Button:
	return pause_panel.get_meta("resume") as Button


func leave_button() -> Button:
	return pause_panel.get_meta("leave") as Button


func confirm_leave_button() -> Button:
	return pause_panel.get_meta("go") as Button


func cancel_leave_button() -> Button:
	return pause_panel.get_meta("stay") as Button


func confirming_leave() -> bool:
	return paused() and _pause_confirm.visible


func game_frozen() -> bool:
	return _froze_tree


## An overlay opened (pause, confirm, map, chat): gameplay input goes away.
func overlay_opened(who: String) -> void:
	if not _overlays.has(who):
		_overlays.append(who)
	_gate_input()


## An overlay closed: gameplay input comes back only when none is left.
func overlay_closed(who: String) -> void:
	_overlays.erase(who)
	_gate_input()
	if _overlays.is_empty():
		_grace = INPUT_GRACE_FRAMES


func overlays() -> Array[String]:
	return _overlays.duplicate()


## The round reads neutral input while an overlay owns the screen, and for a
## few frames after the last one closes.
func blocks_gameplay_input() -> bool:
	return not _overlays.is_empty() or _grace > 0


func _gate_input() -> void:
	var any := not _overlays.is_empty()
	if mc != null and is_instance_valid(mc) and mc.touch != null:
		mc.touch.cancel_all()          # every held finger, stick, look, sprint, throttle
		mc.touch.visible = not any
	Controls.clear_edges()             # queued presses
	Controls.reset_touch()


func open_pause() -> void:
	if paused() or _leaving or _round_over or Engine.get_process_frames() == _last_toggle_frame:
		return
	_last_toggle_frame = Engine.get_process_frames()
	if map_view != null:
		close_map()                   # pause comes first; the map closes under it
	Diag.mark("pause_open")
	pause_opens += 1
	_pause_main.visible = true
	_pause_confirm.visible = false
	_info_lbl.text = pause_info()
	_info_lbl.visible = _info_lbl.text != ""
	_backdrop.visible = true
	pause_panel.visible = true
	_fit_pause()
	overlay_opened("pause")
	_freeze(true)
	(pause_panel.get_meta("resume") as Button).grab_focus()


func close_pause() -> void:
	if not paused() or Engine.get_process_frames() == _last_toggle_frame:
		return
	_last_toggle_frame = Engine.get_process_frames()
	Diag.mark("pause_close")
	pause_closes += 1
	if _pause_confirm.visible:      # closed from under a confirmation (results)
		_pause_confirm.visible = false
		_overlays.erase("confirm")
	pause_panel.visible = false
	_backdrop.visible = false
	_freeze(false)
	overlay_closed("pause")


## The round has ended (results arrived): the menu, a leave confirmation and
## the map close under the results banner, and Pause stays shut for the
## few seconds before the results screen.  Nothing reopens later.
func round_over() -> void:
	if _round_over:
		return
	_round_over = true
	if paused():
		_last_toggle_frame = -1
		close_pause()
	close_map()
	pause_btn.disabled = true


## Compatibility: the pause action and the HUD button toggle.
func _toggle_pause() -> void:
	if paused():
		if confirming_leave():
			_cancel_leave()
		else:
			close_pause()
	else:
		open_pause()


## Practice and the tutorial (offline) really stop: the scene tree pauses
## (the sim, bots, physics, timers, animation and particles of the round all
## stop together), while the HUD and this menu keep running (ALWAYS).  An
## online round is shared: it is never paused from here.
func _freeze(on: bool) -> void:
	var offline := mc != null and is_instance_valid(mc) and mc.session != null and mc.session.mode == NetSession.Mode.OFFLINE
	if on and offline and not _froze_tree:
		_froze_tree = true
		get_tree().paused = true
	elif not on and _froze_tree:
		_froze_tree = false
		get_tree().paused = false


func _ask_leave() -> void:
	if _leaving or not paused():
		return
	var online := mc.session != null and mc.session.mode != NetSession.Mode.OFFLINE
	if not online:
		_confirm_text.text = "This practice round ends. Nothing is earned."
	elif mc.session.is_host():
		_confirm_text.text = "You're hosting: leaving ends the match and the party for everyone."
	else:
		_confirm_text.text = "You'll leave the party. The others play on, and this round earns you nothing."
	_pause_main.visible = false
	_pause_confirm.visible = true
	overlay_opened("confirm")
	_fit_pause()
	(pause_panel.get_meta("stay") as Button).grab_focus()


func _cancel_leave() -> void:
	if not confirming_leave():
		return
	_pause_confirm.visible = false
	_pause_main.visible = true
	overlay_closed("confirm")
	_fit_pause()
	(pause_panel.get_meta("leave") as Button).grab_focus()


func _confirm_leave() -> void:
	if _leaving or not confirming_leave():
		return
	_leaving = true                   # fires once, however it is pressed
	Diag.mark("pause_leave")
	_freeze(false)                    # the next screen starts unpaused
	pause_panel.visible = false
	_backdrop.visible = false
	_overlays.clear()
	_gate_input()
	mc.leave_match()


## The panel sits centred in the safe area and never larger than it.
func _fit_pause() -> void:
	if pause_panel == null:
		return
	var vs := get_viewport().get_visible_rect().size
	var sm := UIKit.safe_margins(get_viewport())
	var area := Rect2(sm.position, vs - sm.position - sm.size)
	pause_panel.reset_size()
	var ps := pause_panel.get_combined_minimum_size()
	pause_panel.size = ps
	pause_panel.position = (area.position + (area.size - ps) * 0.5).floor()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			# Practice: the app going to the background pauses the round
			if mc != null and is_instance_valid(mc) and mc.prepared and mc.session != null \
					and mc.session.mode == NetSession.Mode.OFFLINE and not paused() and not _leaving:
				open_pause()
		NOTIFICATION_EXIT_TREE:
			if _froze_tree:
				_froze_tree = false
				get_tree().paused = false


func _process(_delta: float) -> void:
	var tp := Prof.t()
	_process_hud()
	Prof.add("hud_process", tp)


func _process_hud() -> void:
	if _grace > 0:
		_grace -= 1
	_reserve_touch_regions()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if paused():
			_toggle_pause()
		elif map_view != null:
			close_map()
		else:
			open_pause()
		get_viewport().set_input_as_handled()
	elif paused() and event.is_action_pressed("ui_cancel"):
		_toggle_pause()              # Back: confirm -> menu -> round
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map") or (map_view != null and event.is_action_pressed("ui_cancel")):
		if map_view != null:
			close_map()
		elif not pause_panel.visible:
			open_map()
		get_viewport().set_input_as_handled()


var map_view: FullMap
var _map_refresh := 0.0


func open_map() -> void:
	if map_view != null or pause_panel.visible:
		return
	Diag.mark("map_open")
	overlay_opened("map")   # no stray finger moves or turns you under the map
	map_view = FullMap.new()
	map_view.hud = self
	map_view.build()
	root.add_child(map_view)
	map_view.close_btn.grab_focus()


func close_map() -> void:
	if map_view == null:
		return
	map_view.queue_free()
	map_view = null
	overlay_closed("map")


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
	_fit_pause()


## Touches on the pause button and minimap must never start the stick or
## camera.  V7: measured every frame from the settled layout (V6 measured
## once, deferred from a resize, before containers had sorted), and exactly
## the buttons' own rects: V6 grew them by 12 units, so a touch in that ring
## fell through the gameplay surface onto nothing and was lost.  Both layers
## are untransformed, so the HUD's canvas rects are the surface's local
## coordinates.
func _reserve_touch_regions() -> void:
	if mc == null or mc.touch == null or not is_instance_valid(pause_btn):
		return
	var rects: Array[Rect2] = [pause_btn.get_global_rect(), minimap.get_global_rect()]
	if chat != null:
		rects.append_array(chat.reserved())
	mc.touch.set_reserved(rects)


func set_spectating(slot: int) -> void:
	_spectating = slot


## Host: players whose match is still loading (the round waits for them).
func set_waiting(names: Array) -> void:
	if names.is_empty():
		if _waiting_lbl:
			_waiting_lbl.visible = false
		return
	if _waiting_lbl == null:
		_waiting_lbl = UIKit.outlined(UIKit.label("", 24, UIKit.IVORY, true, HORIZONTAL_ALIGNMENT_CENTER), 6)
		_waiting_lbl.set_anchors_preset(Control.PRESET_CENTER)
		_waiting_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_waiting_lbl)
	_waiting_lbl.visible = true
	var shown := names.slice(0, 3)
	_waiting_lbl.text = "Waiting for %s to load…" % ", ".join(PackedStringArray(shown)) + (" (+%d)" % (names.size() - 3) if names.size() > 3 else "")
	_waiting_lbl.position = (get_viewport().get_visible_rect().size - _waiting_lbl.get_combined_minimum_size()) * 0.5 - Vector2(0, 120)


var _waiting_lbl: Label


func toast(text: String, col: Color = UIKit.TEXT) -> void:
	toast_lbl.text = text
	toast_lbl.add_theme_color_override("font_color", col)
	toast_t = 2.4


## Event feed: at most three short lines on soft pills (legible over any
## background), fading after 4 s.
func feed(text: String, role: int) -> PanelContainer:
	var col := UIKit.TEAL if role == TC.Role.RUNNER else (UIKit.PATROL if role == TC.Role.PATROL else UIKit.IVORY_MUTED)
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", UIKit.box(Color(UIKit.NAVY, 0.5), 14, 0, Color.WHITE, 6))
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UIKit.label(text, 18, col, true)
	pill.add_child(l)
	pill.set_meta("t", 4.0)
	feed_box.add_child(pill)
	while feed_box.get_child_count() > 3:
		var old_c := feed_box.get_child(0)
		feed_box.remove_child(old_c)
		old_c.queue_free()
	return pill


## Other runners' splashes into the same water within a few seconds share one
## line ("Yawn, Snooze +1 splashed into Pool") instead of stacking up.
var _splash_lines: Dictionary = {}   # water short name -> {pill, names}


func feed_splash(who: String, water: String, role: int) -> void:
	var cur: Dictionary = _splash_lines.get(water, {})
	var pv: Variant = cur.get("pill")
	# the pill may already be freed (faded out or pushed off the feed)
	if is_instance_valid(pv) and float((pv as PanelContainer).get_meta("t", 0.0)) > 0.5:
		var pill := pv as PanelContainer
		var names: Array = cur["names"]
		if not names.has(who):
			names.append(who)
		var shown := ", ".join(PackedStringArray(names.slice(0, 2))) + (" +%d" % (names.size() - 2) if names.size() > 2 else "")
		(pill.get_child(0) as Label).text = "%s splashed into %s" % [shown, water]
		pill.set_meta("t", 4.0)
		return
	_splash_lines[water] = {"pill": feed("%s splashed into %s" % [who, water], role), "names": [who]}


## Compact stamp celebration under the home counter: the water's icon, its
## name and progress; a quick pop (none with Reduced Motion), then it fades.
var _stamp_pop: PanelContainer


## V8: built once with the HUD and reused (V6-V7 built a new panel on every
## stamp: the first splash also paid for its layout and font glyphs).  It
## animates through the single-owner motion layer: a quick fade and settle
## in, a hold, a fade out; a new stamp retargets it from where it is.
var _stamp_icon: Icons.IconRect
var _stamp_title: Label
var _stamp_sub: Label
var _stamp_sb: StyleBoxFlat


func _build_stamp_pop() -> void:
	var p := PanelContainer.new()
	_stamp_sb = UIKit.box(Color(UIKit.SLATE, 0.92), 22, 2, Color(0.5, 0.8, 1.0, 0.9), 12)
	p.add_theme_stylebox_override("panel", _stamp_sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := UIKit.hbox(10)
	_stamp_icon = Icons.IconRect.new("drop", Color.WHITE, 34)
	h.add_child(_stamp_icon)
	var tv := UIKit.vbox(0)
	_stamp_title = UIKit.label("Stamped", 24, UIKit.IVORY, true)
	_stamp_sub = UIKit.label("0 of 3 splashes", 17, UIKit.IVORY_MUTED)
	tv.add_child(_stamp_title)
	tv.add_child(_stamp_sub)
	h.add_child(tv)
	p.add_child(h)
	p.modulate.a = 0.0
	root.add_child(p)
	_stamp_pop = p


func stamp_pop(w: Dictionary, count: int, total: int) -> void:
	if _stamp_pop == null:
		_build_stamp_pop()
	var p := _stamp_pop
	if _stamp_sb is StyleBoxFlat:
		(_stamp_sb as StyleBoxFlat).border_color = Color(w["color"], 0.9)
	_stamp_icon.kind = String(w["icon"])
	_stamp_icon.col = w["color"]
	_stamp_icon.queue_redraw()
	_stamp_title.text = "%s stamped" % w["short"]
	_stamp_sub.text = "%d of %d splashes" % [count, total] if count < total else "All splashed — run home!"
	p.reset_size()
	var vs := get_viewport().get_visible_rect().size
	var sz := p.get_combined_minimum_size()
	# under the goal bar (and the danger chip when it shows)
	var below := (goal_bar.get_parent() as Control).get_global_rect().end.y if goal_bar != null else _safe.position.y + 118.0
	p.position = Vector2((vs.x - sz.x) * 0.5, below + 10.0)
	p.pivot_offset = sz * 0.5
	Motion.stop(p, "modulate:a")
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.08)
	tw.tween_interval(1.7)
	tw.tween_property(p, "modulate:a", 0.0, 0.3)
	Motion.own(p, "modulate:a", tw)
	if not UIKit.reduced_motion():
		p.scale = Vector2(0.86, 0.86)
		Motion.animate(p, "scale", Vector2.ONE, 0.2, Tween.TRANS_BACK, Tween.EASE_OUT)
	else:
		p.scale = Vector2.ONE
	Motion.confirm(_stamp_icon)


## A collected coin (V6): the chip pulses once and a small "+1" rises from
## it and fades (no motion with Reduced Motion: it just appears and fades).
var _plus: Label


func coin_pop() -> void:
	if coin_chip == null:
		return
	coin_chip.visible = true
	if _plus == null:
		_plus = UIKit.outlined(UIKit.label("+1", 22, Color(1.0, 0.86, 0.45), true, HORIZONTAL_ALIGNMENT_CENTER), 5)
		_plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(_plus)
	var r := coin_chip.get_global_rect()
	_plus.position = Vector2(r.end.x + 4.0, r.position.y)
	_plus.modulate.a = 1.0
	var tw := _plus.create_tween()
	if not UIKit.reduced_motion():
		tw.tween_property(_plus, "position:y", r.position.y - 22.0, 0.6).set_ease(Tween.EASE_OUT)
		coin_chip.pivot_offset = coin_chip.size * 0.5
		var tc := coin_chip.create_tween()
		tc.tween_property(coin_chip, "scale", Vector2(1.12, 1.12), 0.08)
		tc.tween_property(coin_chip, "scale", Vector2.ONE, 0.16)
	else:
		tw.tween_interval(0.5)
	tw.tween_property(_plus, "modulate:a", 0.0, 0.35)


class CoinIcon:
	extends Control

	func _draw() -> void:
		CoinView.draw_icon(self, size * 0.5, minf(size.x, size.y) * 0.45)


func emote_bubble(slot: int, emote_id: int) -> void:
	emotes[slot] = {"id": emote_id, "t": 2.2}


func refresh(delta: float) -> void:
	_t += delta
	info = mc.local_info()
	var phase: int = info.get("phase", TC.Phase.REVEAL)
	var role: int = info.get("role", TC.Role.RUNNER)
	var vs := get_viewport().get_visible_rect().size
	# the team goal and the one round clock
	var tl: float = info.get("time_left", 0.0)
	var fin: int = info.get("finished", 0)
	_refresh_goal(tl, fin, phase, role)
	var coins: int = info.get("coins", 0)
	if coins != _coin_shown:
		_coin_shown = coins
		coin_lbl.text = str(coins)
	role_lbl.text = "Night Watch" if role == TC.Role.PATROL else ("Runner" if role == TC.Role.RUNNER else "Spectating")
	role_lbl.add_theme_color_override("font_color", UIKit.PATROL if role == TC.Role.PATROL else UIKit.TEAL)
	if role_icon:
		role_icon.kind = "whistle" if role == TC.Role.PATROL else ("drop" if role == TC.Role.RUNNER else "eye")
		role_icon.col = UIKit.PATROL if role == TC.Role.PATROL else UIKit.TEAL
	var st: int = (info.get("rs", {}) as Dictionary).get("state", 0)
	banner.visible = false   # V2: the "head back" state lives in the personal card
	_refresh_pace(delta, phase)
	personal_rows = ObjectiveChips.fit(_personal_rows(phase, role), PERSONAL_W)
	var ph := personal.wanted_height()
	if absf(personal.custom_minimum_size.y - ph) > 0.5:
		personal.custom_minimum_size.y = ph
		personal.size.y = ph
	personal.queue_redraw()
	_refresh_danger(role, phase)
	var hint := sprint_hint_wanted(info)
	if sprint_hint.visible != hint:
		sprint_hint.visible = hint
	if hint:
		sprint_meter.value = float(info.get("sprint", 0.0))
		sprint_meter.rearm = rearm_fraction()
		sprint_meter.queue_redraw()
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
			# the capture contract, in the round's real values, short: who
			# caught you and the countdown; stamps kept; where you come back
			# and the protection you get there
			var pen: float = info.get("penalty", 0.0)
			overlay.visible = true
			var since := mc.cfg.capture_penalty_s - pen
			if since < 1.3 and mc.caught_by != "":
				overlay_title.text = "Caught by %s · back in %d" % [mc.caught_by, int(ceil(pen))]
			else:
				overlay_title.text = "Caught · back in %d" % int(ceil(pen))
			overlay_sub.text = "%d/3 waters kept · back at %s · protected %d s" % [_bits(int(info.get("stamps", 0))), return_place(), int(mc.cfg.respawn_protect_s)]
			var ps := int(ceil(pen))
			if ps != _last_penalty_sec and ps <= 3 and ps > 0:
				Sfx.play("tick")
			_last_penalty_sec = ps
		elif st == TC.PState.ACTIVE and float(rs.get("protect", 0.0)) > 0.0 and role == TC.Role.RUNNER:
			sub_lbl.text = "Protected · %d" % int(ceil(float(rs.get("protect", 0.0))))
		elif st == TC.PState.FINISHED:
			# a few seconds of "Home · 2nd to finish · Waiting for team", then
			# the view follows a teammate (the personal card keeps the line)
			if not _home_seen:
				_home_seen = true
				_home_t = _t
			if _t - _home_t < HOME_OVERLAY_S:
				overlay.visible = true
				overlay_title.text = home_line()
				overlay_sub.text = "Waiting for team · %s" % ("they need %d more" % maxi(0, mc.cfg.runners_needed - fin) if fin < mc.cfg.runners_needed else "that's enough!")
	if _spectating >= 0 and mc.roster.has(_spectating):
		spectate_lbl.text = "Watching %s  ·  next: %s" % [mc.roster[_spectating]["name"], "Tab" if Controls.device == "keyboard" else ("RB" if Controls.device == "gamepad" else "⟳")]
	else:
		spectate_lbl.text = ""
	for slot in emotes.keys():
		emotes[slot]["t"] = float(emotes[slot]["t"]) - delta
		if float(emotes[slot]["t"]) <= 0.0:
			emotes.erase(slot)
	_update_coach(delta, phase, role)
	if map_view != null:
		_map_refresh -= delta
		if _map_refresh <= 0.0:
			_map_refresh = 0.5
			map_view.refresh_team()
		if phase == TC.Phase.RESULTS or phase == TC.Phase.ENDED:
			close_map()
	_place(vs)
	draw_layer.queue_redraw()
	minimap.queue_redraw()


func _place(vs: Vector2) -> void:
	# the goal bar follows its sentence's width, centred (one or two rows)
	_fit_goal_bar(vs)
	var top := goal_bar.get_parent() as Control
	var ts := top.get_combined_minimum_size()
	top.size = ts
	top.position = Vector2(floorf((vs.x - ts.x) * 0.5), _safe.position.y)
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
	# the sprint hint: centred, above the thumb clusters (and the toasts),
	# never under a thumb
	var hs := sprint_hint.get_combined_minimum_size()
	sprint_hint.size = hs
	var bottom := vs.y * 0.62 - 8.0
	if mc != null and mc.touch != null and mc.touch.surface != null:
		var res: Dictionary = mc.touch.surface.res
		for bn in res.get("buttons", {}):
			var b: Dictionary = res["buttons"][bn]
			bottom = minf(bottom, (b["c"] as Vector2).y - float(b["hit"]) - 12.0)
		if res.has("stick_c"):
			bottom = minf(bottom, (res["stick_c"] as Vector2).y - float(res["stick_r"]) - 12.0)
	sprint_hint.position = Vector2(floorf((vs.x - hs.x) * 0.5), floorf(maxf(vs.y * 0.4, bottom - hs.y)))


func _hint(kind: String) -> String:
	var d := Controls.device
	var table := {
		"move": {"touch": "put your left thumb down and drag", "gamepad": "left stick", "keyboard": "W A S D"},
		"look": {"touch": "drag on the right side of the screen", "gamepad": "right stick", "keyboard": "hold right mouse and drag (or I J K L)"},
		"jump": {"touch": "tap Jump", "gamepad": "press A / Cross", "keyboard": "press Space"},
		"sprint": {"touch": "push the stick all the way to its outer ring", "gamepad": "hold LB or RB", "keyboard": "hold Shift"},
		"tag": {"touch": "tap Tag"},
		"interact": {"touch": "tap Drive (Exit in the cart)"},
	}
	if d != "touch" and kind in ["tag", "interact"]:
		return "press %s" % Controls.prompt(kind)
	return String(table[kind].get(d, table[kind]["touch"]))


var _coach_watch_t := 0.0


func _update_coach(delta: float, phase: int, role: int) -> void:
	var tut := bool(mc.start.get("tutorial", false))
	if tut and role == TC.Role.PATROL and phase == TC.Phase.PLAYING:
		_update_watch_coach(delta)
		return
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
		["Jump into any glowing water! The card top-left suggests a good next one and points the way.", stamps != 0],
		["SPLASH! Two more spots to go. Each one has its own shape and colour.", stamps == 7],
		["All three! Now run back inside %s through any of its glowing doors." % CampusDorms.display_name(mc.home_dorm), st == TC.PState.FINISHED],
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


## Guided Night Watch training (V4): find a runner, wait for Tag to light
## up, tag, see the capture and protection rules, then try a cart.
func _update_watch_coach(delta: float) -> void:
	var rs: Dictionary = info.get("rs", {})
	var st: int = rs.get("state", 0)
	var rel: float = info.get("release_left", 0.0)
	var pen_s := int(mc.cfg.capture_penalty_s)
	var prot_s := int(mc.cfg.respawn_protect_s)
	if coach_step == 2:
		_coach_watch_t += delta
	var steps := [
		["Runners have a head start. Get ready: %s to move, %s to look." % [_hint("move"), _hint("look")], rel <= 0.0],
		["Chase the nearest runner. A ring appears under them when they're close and in sight.", int(info.get("tag_aim", -1)) >= 0],
		["Wait for Tag to light up, then %s. Pressing early just misses." % _hint("tag"), mc.my_catches >= 1],
		["Caught! They keep their splashes and come back in %d s near their last splash, protected for %d s — you can't tag them then." % [pen_s, prot_s], _coach_watch_t > 6.0],
		["Carts are fast on the roads. Walk up to a cart and %s." % _hint("interact"), st == TC.PState.IN_CART],
		["Drive close to a runner, %s to hop out, then finish on foot." % _hint("interact"), mc.my_catches >= 2],
		["That's the Night Watch! Stop %d runners getting home before time runs out." % mc.cfg.runners_needed, false],
	]
	while coach_step < steps.size() - 1 and bool(steps[coach_step][1]):
		coach_step += 1
		_coach_flash = 0.6
		Sfx.play("pickup")
	coach_lbl.text = steps[coach_step][0]
	_coach_flash = maxf(0.0, _coach_flash - delta)
	coach.modulate = Color(1, 1, 1, 1).lerp(Color(1.4, 1.4, 1.0, 1), _coach_flash)
	coach.visible = true


## Runners not yet home (captured ones are still out).  From the round's
## roster and the authoritative home count: a guest's snapshot doesn't carry
## runners it can't see, so their states can't be counted directly.
func runners_out() -> int:
	var n := 0
	for slot in mc.roster:
		if int(mc.roster[slot]["role"]) == TC.Role.RUNNER:
			n += 1
	return maxi(0, n - int(info.get("finished", 0)))


# --- Pass 8: team goal, personal next action, runner pace -----------------

## The sentence on the goal bar.  Exact home count; never a win claimed
## from the clock.
func goal_text(role: int, fin: int) -> String:
	var need := mc.cfg.runners_needed
	if role == TC.Role.PATROL:
		return "Runners home %d/%d · Hold until" % [fin, need]
	if role == TC.Role.RUNNER:
		if fin >= need:
			return "Team home %d/%d" % [fin, need]
		return "Team home %d/%d · Need %d more" % [fin, need, need - fin]
	return "Runners home %d/%d" % [fin, need]


static func clock_text(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


## Urgency: 0 calm, 1 under 30 s (amber), 2 under 10 s (coral, an alarm
## clock shape).  Colour always comes with the icon's shape.
static func clock_urgency(t: float, playing: bool) -> int:
	if not playing:
		return 0
	if t < 10.0:
		return 2
	if t < 30.0:
		return 1
	return 0


func _refresh_goal(tl: float, fin: int, phase: int, role: int) -> void:
	goal_lbl.text = goal_text(role, fin)
	tracker.needed = mc.cfg.runners_needed
	tracker.home = fin
	tracker.role = role
	tracker.queue_redraw()
	timer_lbl.text = clock_text(tl)
	var u := clock_urgency(tl, phase == TC.Phase.PLAYING)
	timer_lbl.add_theme_color_override("font_color", [UIKit.IVORY, UIKit.AMBER, UIKit.BAD][u])
	if clock_icon.urgency != u:
		clock_icon.urgency = u
		clock_icon.queue_redraw()
	# a calm 1 Hz breath in the last ten seconds (none with Reduced Motion)
	var s := 1.0
	if u == 2 and not mc.reduced_motion:
		s = 1.0 + 0.05 * maxf(0.0, sin(_t * TAU))
	clock_box.pivot_offset = clock_box.size * 0.5
	clock_box.scale = Vector2(s, s)


## The goal bar on one row when it fits between the personal column and
## the minimap, else the clock under the sentence.
func _fit_goal_bar(vs: Vector2) -> void:
	if goal_bar == null:
		return
	var left_edge := _safe.position.x + 4.0 + PERSONAL_W + 12.0
	var tr := pause_btn.get_parent() as Control
	var right_edge := vs.x - _safe.size.x - tr.get_combined_minimum_size().x - 12.0
	var room := 2.0 * minf(vs.x * 0.5 - left_edge, right_edge - vs.x * 0.5)
	var one_row := goal_row.get_combined_minimum_size().x + (clock_box.get_combined_minimum_size().x + 10.0 if _two_row else 0.0) + 20.0
	var want_two := one_row > room
	if want_two == _two_row:
		return
	_two_row = want_two
	clock_box.get_parent().remove_child(clock_box)
	(goal_row2 if _two_row else goal_row).add_child(clock_box)


## A runner's pace entry this frame ({} if none yet), and the runner count.
func my_pace() -> Dictionary:
	var p: Dictionary = info.get("pace", {})
	return p.get(mc.local_slot, {})


func pace_label() -> String:
	var phase := int(info.get("phase", TC.Phase.REVEAL))
	var over := phase == TC.Phase.RESULTS or phase == TC.Phase.ENDED
	var e := my_pace()
	var st := int((info.get("rs", {}) as Dictionary).get("state", 0))
	if over and st != TC.PState.FINISHED:
		return "Runner pace: Not home"
	return RunnerPace.label(e, mc.runner_count(), over)


## Event-driven place change: a small arrow beside the pace for a moment
## when the published place really changes (no bounce, no celebration).
func _refresh_pace(delta: float, phase: int) -> void:
	_pace_cue_t = maxf(0.0, _pace_cue_t - delta)
	var e := my_pace()
	if e.is_empty() or phase != TC.Phase.PLAYING:
		return
	var p := int(e["place"])
	if _pace_place > 0 and p != _pace_place:
		_pace_delta = 1 if p < _pace_place else -1
		_pace_cue_t = PACE_CUE_S
	_pace_place = p


## "Home · 2nd to finish" (the shared place when two crossed on one tick).
func home_line() -> String:
	var e := my_pace()
	if not e.is_empty() and bool(e.get("home", false)):
		return "Home · %s%s to finish" % ["tied " if bool(e.get("tied", false)) else "", RoundRanking.ordinal(int(e["place"]))]
	var fo := int(info.get("finish_order", mc.my_finish_order))
	return "Home · %s to finish" % RoundRanking.ordinal(fo) if fo > 0 else "Home"


func home_now() -> void:
	_home_seen = true
	_home_t = _t


## Where a caught runner comes back: the last stamped water's pads, or
## inside tonight's dorm before the first stamp.
func return_place() -> String:
	var stamps := int(info.get("stamps", 0))
	var tg: Array = info.get("targets", [])
	if stamps == 0 or tg.is_empty():
		return "inside " + CampusDorms.display_name(mc.home_dorm)
	# the host knows the last stamped water; a guest sees the order of its
	# own stamp events - the HUD uses the authoritative bit set and the
	# most recent stamp it was told about
	var wi := mc.last_stamp_water if mc.last_stamp_water >= 0 else -1
	if wi < 0:
		for i in range(tg.size() - 1, -1, -1):
			if stamps & (1 << i):
				wi = int(tg[i])
				break
	return String(mc.layout.waters[wi]["short"]) if wi >= 0 else "your last splash"


static func _bits(v: int) -> int:
	var n := 0
	for i in 3:
		if v & (1 << i):
			n += 1
	return n


## The suggested next goal for this runner: [kind, index] - ["water", target
## index] for a remaining target, ["door", door index] with all three, or
## [] when nothing applies.  The host's route suggestion when it has one,
## else the nearest remaining target / door by straight line.  Any
## remaining water is still valid; this is only a good next one.
func suggested_goal() -> Array:
	var role := int(info.get("role", 0))
	var rs: Dictionary = info.get("rs", {})
	if role != TC.Role.RUNNER or not rs.has("pos"):
		return []
	var stamps := int(info.get("stamps", 0))
	var tg: Array = info.get("targets", [])
	var pos: Vector3 = rs["pos"]
	var g := int(info.get("next_goal", RunnerPace.NO_GOAL))
	if _bits(stamps) >= tg.size():
		var doors := mc.layout.home_doors(mc.home_dorm)
		if g >= RunnerPace.DOOR_GOAL and g - RunnerPace.DOOR_GOAL < doors.size():
			return ["door", g - RunnerPace.DOOR_GOAL]
		var best := 0
		var bd := INF
		for i in doors.size():
			var d := (doors[i]["pos"] as Vector2).distance_to(Vector2(pos.x, pos.z))
			if d < bd:
				bd = d
				best = i
		return ["door", best]
	if g >= 0 and g < tg.size() and (stamps & (1 << g)) == 0:
		return ["water", g]
	var bi := -1
	var bdist := INF
	for i in tg.size():
		if stamps & (1 << i):
			continue
		var c: Vector2 = mc.layout.waters[int(tg[i])]["center"]
		var d2 := c.distance_to(Vector2(pos.x, pos.z))
		if d2 < bdist:
			bdist = d2
			bi = i
	return ["water", bi] if bi >= 0 else []


func _bearing(me: Vector3, p: Vector2) -> float:
	var cam := mc.camera
	return wrapf(atan2(p.x - me.x, -(p.y - me.z)) + (cam.yaw if cam else 0.0), -PI, PI)


## What the personal card shows (data first, so tests read the same words
## the screen draws).  Rows: {type: waters|goal|pace|line|guard, text, ...}.
func _personal_rows(phase: int, role: int) -> Array:
	var rows: Array = []
	var rs: Dictionary = info.get("rs", {})
	if not rs.has("pos") or role == TC.Role.SPECTATOR:
		return rows
	var pos: Vector3 = rs["pos"]
	var st := int(rs.get("state", 0))
	var tg: Array = info.get("targets", [])
	var stamps := int(info.get("stamps", 0))
	var over := phase == TC.Phase.RESULTS or phase == TC.Phase.ENDED
	if role == TC.Role.PATROL:
		var tags := int(info.get("tags", 0))
		var dist := int(info.get("distinct", 0))
		rows.append({"type": "line", "icon": "whistle", "col": UIKit.PATROL,
			"text": "You: %d tag%s · %d different runner%s" % [tags, "" if tags == 1 else "s", dist, "" if dist == 1 else "s"]})
		var tag_txt := ""
		var tag_col := UIKit.IVORY_MUTED
		var tag_icon := "bolt"
		if st == TC.PState.WAITING:
			tag_txt = "In the shed · out in %d" % int(ceil(float(info.get("release_left", 0.0))))
			tag_icon = "lock"
		elif st == TC.PState.IN_CART or st == TC.PState.ENTERING:
			tag_txt = "Driving · hop out to tag"
			tag_icon = "cart"
		elif bool(info.get("tag_ready", false)):
			tag_txt = "Tag ready"
			tag_col = UIKit.AMBER
		elif float(info.get("tag_busy", 0.0)) > 0.0:
			tag_txt = "Tag recharging"
		else:
			tag_txt = "Tag lights up in reach"
		if not over:
			rows.append({"type": "line", "icon": tag_icon, "col": tag_col, "text": tag_txt, "small": true})
		var guard: Array = []
		for i in tg.size():
			var w: Dictionary = mc.layout.waters[int(tg[i])]
			var c: Vector2 = w["center"]
			guard.append({"icon": w["icon"], "col": w["color"], "bearing": _bearing(pos, c), "dist": c.distance_to(Vector2(pos.x, pos.z))})
		rows.append({"type": "guard", "text": "Waters to guard", "waters": guard})
		return rows
	# runner
	var ws: Array = []
	for i in tg.size():
		var w2: Dictionary = mc.layout.waters[int(tg[i])]
		ws.append({"icon": w2["icon"], "col": w2["color"], "done": (stamps & (1 << i)) != 0, "short": w2["short"]})
	var n := _bits(stamps)
	if st == TC.PState.FINISHED:
		rows.append({"type": "line", "icon": "house", "col": UIKit.TEAL, "text": home_line(), "check": true})
		var fin := int(info.get("finished", 0))
		rows.append({"type": "line", "icon": "eye", "col": UIKit.IVORY_MUTED, "small": true,
			"text": "Waiting for team · need %d more" % maxi(0, mc.cfg.runners_needed - fin) if fin < mc.cfg.runners_needed else "Your team made it"})
		return rows
	rows.append({"type": "waters", "text": "You: %d/%d waters" % [n, tg.size()], "waters": ws})
	if over:
		rows.append({"type": "pace", "text": pace_label(), "delta": 0, "approx": false})
		return rows
	if st == TC.PState.CAPTURED:
		rows.append({"type": "goal", "icon": "eye", "col": UIKit.BAD, "text": "Caught · back in %d" % int(ceil(float(info.get("penalty", 0.0)))),
			"bearing": INF, "dist": -1.0, "emph": true})
	else:
		var sg := suggested_goal()
		if not sg.is_empty() and String(sg[0]) == "door":
			var doors := mc.layout.home_doors(mc.home_dorm)
			var d: Dictionary = doors[int(sg[1])]
			var dp: Vector2 = d["pos"]
			rows.append({"type": "goal", "icon": "house", "col": Color(1.0, 0.86, 0.5), "emph": true, "door": int(sg[1]),
				"text": "Return inside %s" % CampusDorms.display_name(mc.home_dorm), "bearing": _bearing(pos, dp), "dist": dp.distance_to(Vector2(pos.x, pos.z))})
		elif not sg.is_empty():
			var w3: Dictionary = mc.layout.waters[int(tg[int(sg[1])])]
			var c3: Vector2 = w3["center"]
			rows.append({"type": "goal", "icon": w3["icon"], "col": w3["color"], "emph": true, "target": int(sg[1]),
				"text": "Next: %s" % String(w3["short"]), "bearing": _bearing(pos, c3), "dist": c3.distance_to(Vector2(pos.x, pos.z))})
	var e := my_pace()
	rows.append({"type": "pace", "text": pace_label(), "delta": _pace_delta if _pace_cue_t > 0.0 else 0,
		"approx": bool(e.get("approx", false)), "fade": clampf(_pace_cue_t / 0.6, 0.0, 1.0)})
	return rows


## "Sprint empty · ease off to recharge": a runner in play whose sprint
## latched empty (SimPlayer.sprint_exhausted) and who is still holding
## sprint.  It goes the moment either stops.
static func sprint_hint_wanted(i: Dictionary) -> bool:
	if int(i.get("role", -1)) != TC.Role.RUNNER or int(i.get("phase", -1)) != TC.Phase.PLAYING:
		return false
	var st := int((i.get("rs", {}) as Dictionary).get("state", TC.PState.ACTIVE))
	if st != TC.PState.ACTIVE and st != TC.PState.STUMBLE and st != TC.PState.EXITING:
		return false
	return bool(i.get("sprint_exhausted", false)) and bool(i.get("sprint_held", false))


## The meter level at which a released sprint re-arms (the round's rules,
## when they have it).
func rearm_fraction() -> float:
	if mc != null and mc.cfg != null and "sprint_rearm_fraction" in mc.cfg:
		return float(mc.cfg.get("sprint_rearm_fraction"))
	return -1.0


## The danger chip: a Night Watch you can actually see, close by.
func _refresh_danger(role: int, phase: int) -> void:
	var near := INF
	var in_cart := false
	if role == TC.Role.RUNNER and phase == TC.Phase.PLAYING:
		for slot in mc.last_seen:
			var ls: Dictionary = mc.last_seen[slot]
			if bool(ls.get("live", false)) and float(ls.get("dist", INF)) < near:
				near = float(ls.get("dist", INF))
				in_cart = bool(ls.get("cart", false))
	var show := near <= DANGER_M
	if show:
		danger_lbl.text = "%s in sight · %d m" % ["Watch cart" if in_cart else "Night Watch", int(near)]
	if danger_chip.visible != show:
		danger_chip.visible = show


## "Series: tied 1st · 2 Round Wins" for the pause menu and the map (party
## rounds after the first results; "" before - never a fake place).
func series_line() -> String:
	if mc.session == null or mc.session.mode == NetSession.Mode.OFFLINE:
		return ""
	return RoundRanking.series_line(mc.session.series_view, Save.player_uid())


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
			var a := clampf(spotted / 1.0, 0.0, 1.0) * (0.65 if hud.mc.reduced_motion else 0.55 + 0.2 * sin(hud._t * 8.0))
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
			# Pass 8: the loudest close noise gets a word of context beside
			# its chevron ("footsteps nearby" / "cart nearby"): still only a
			# bearing, never a position or who it is
			var loudest: Dictionary = {}
			for n in info.get("noises", []):
				if float(n["loud"]) >= 0.5 and (loudest.is_empty() or float(n["loud"]) > float(loudest["loud"])):
					loudest = n
			if not loudest.is_empty():
				var rl: Vector3 = (loudest["pos"] as Vector3) - (me["pos"] as Vector3)
				var al := atan2(rl.x, -rl.z) + cam.yaw
				var pl := center + Vector2(sin(al), -cos(al)) * minf(vs.x, vs.y) * 0.36
				var txt := "cart nearby" if String(loudest["kind"]) == "cart" else "footsteps nearby"
				var fl := UIKit.font_w(600)
				var tw0 := fl.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
				var at := (pl + (center - pl).normalized() * 34.0) - Vector2(tw0 * 0.5, -5.0)
				draw_string_outline(fl, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color(UIKit.NAVY, 0.8))
				draw_string(fl, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(UIKit.IVORY, 0.85))
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
			# like name labels: fade out with distance, never through walls
			var head := v.global_position + Vector3(0, 1.6, 0)
			var cam3 := hud.mc.camera
			if cam3 == null or cam3.global_position.distance_to(head) > 28.0:
				continue
			if int(slot) != hud.mc.local_slot:
				var q := PhysicsRayQueryParameters3D.create(cam3.global_position, head, TC.L_WORLD)
				if not hud.mc.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
					continue
			var sp := hud.world_to_screen(v.global_position + Vector3(0, 2.6, 0))
			if sp.x < -1000:
				continue
			var label: String = TC.EMOTE_LABELS.get(TC.EMOTES[int(hud.emotes[slot]["id"])], "!")
			var f := UIKit.font(true)
			var tw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
			draw_style_box(UIKit.box(Color(UIKit.IVORY, 0.94), 16), Rect2(sp - Vector2(tw * 0.5 + 12, 22), Vector2(tw + 24, 40)))
			draw_string(f, sp + Vector2(-tw * 0.5, 8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, UIKit.NAVY)
		# patrol: splash markers in the world (brief, location only)
		for m in info.get("markers", []):
			var w: Dictionary = hud.mc.layout.waters[int(m["water"])]
			var c: Vector2 = w["center"]
			var sp2 := hud.world_to_screen(Vector3(c.x, 3.0, c.y))
			if sp2.x > -1000:
				var pulse := 1.0 if hud.mc.reduced_motion else 1.0 + 0.2 * sin(hud._t * 10.0)
				draw_arc(sp2, 26.0 * pulse, 0, TAU, 24, w["color"], 4.0)
				Icons.draw_shape(self, w["icon"], sp2, 14, w["color"])
				draw_string(UIKit.font(true), sp2 + Vector2(-40, 48), "SPLASH!", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, w["color"])
		# sprint meter for non-touch devices (touch draws it on the stick)
		if Controls.device != "touch" and int(info.get("role", 0)) == TC.Role.RUNNER:
			# (Pass 8) tinted and hatched while the sprint latch is on
			var base := Vector2(vs.x * 0.5 - 90, vs.y - hud._safe.size.y - 26)
			SprintMeter.paint(self, Rect2(base, Vector2(180, 14)), float(info.get("sprint", 1.0)),
				bool(info.get("sprint_exhausted", false)), hud.rearm_fraction())


## Pass 8: the personal card (top left), drawn from MatchHUD.personal_rows -
## data first so tests read the words the screen shows.
##   runner     "You: 2/3 waters" + three distinct water marks (checked when
##              stamped); one emphasised next action ("Next: Pond" with a
##              camera-relative arrow and metres, "Return inside <dorm>",
##              "Caught · back in 4"); "Runner pace: 3rd/6" with a small
##              arrow for a moment after a real place change
##   home       "Home · 2nd to finish", then "Waiting for team"
##   Night Watch "You: 3 tags · 2 different runners", the Tag state, and the
##              three waters to guard as compact arrows
## Colour is always paired with a shape (each water its own icon, checks,
## arrows), and nothing here takes touches.
class ObjectiveChips:
	extends Control
	var hud: MatchHUD
	const ROW := 40.0
	const ROW2 := 54.0                # a row whose words take two lines
	const SMALL := 32.0
	const GAP := 6.0

	func _row_h(r: Dictionary) -> float:
		if (r.get("lines", []) as Array).size() == 2:
			return ROW2
		return SMALL if (String(r["type"]) == "pace" or bool(r.get("small", false))) else ROW

	## The card's height for its rows (the HUD lays the column out with it).
	func wanted_height() -> float:
		var h := 0.0
		for r in hud.personal_rows:
			h += _row_h(r) + GAP
		return maxf(0.0, h - GAP)

	## [room in canvas units, font, size] for a row's words at width w.
	static func _metrics(r: Dictionary, w: float) -> Array:
		match String(r["type"]):
			"waters":
				return [w - 130.0, UIKit.font_w(700), 19]
			"goal":
				return [w - (124.0 if float(r.get("bearing", INF)) != INF else 52.0), UIKit.font_w(700), 19]
			"pace":
				return [w - 60.0, UIKit.font_w(600), 17]
		if bool(r.get("small", false)):
			return [w - 60.0, UIKit.font_w(600), 17]
		return [w - 60.0, UIKit.font_w(700), 19]

	## Words that don't fit one line move to two (split after the first
	## "·", or "Return inside" over the dorm's name): nothing on the card is
	## cut.
	static func fit(rows: Array, w: float) -> Array:
		for r in rows:
			if String(r["type"]) == "guard":
				continue
			var m := _metrics(r, w)
			var t := String(r["text"])
			if (m[1] as Font).get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(m[2])).x <= float(m[0]):
				continue
			if t.begins_with("Return inside "):
				r["lines"] = ["Return inside", t.trim_prefix("Return inside ")]
			elif t.contains(" · "):
				var i := t.find(" · ")
				r["lines"] = [t.substr(0, i), t.substr(i + 3)]
		return rows

	## Lines whose words would still be cut at this width (tests: none).
	func clipped_rows() -> Array:
		var out: Array = []
		for r in hud.personal_rows:
			if String(r["type"]) == "guard":
				continue
			var m := _metrics(r, size.x)
			var lines: Array = r.get("lines", [String(r["text"])])
			for ln in lines:
				if (m[1] as Font).get_string_size(String(ln), HORIZONTAL_ALIGNMENT_LEFT, -1, int(m[2])).x > float(m[0]) + 0.5:
					out.append(String(ln))
		return out

	## A row's words: one line centred, or two (for a goal the first is
	## small and muted - "Return inside" over the dorm's name - else the
	## second is).
	func _words(x: float, y: float, h: float, r: Dictionary, room: float, f: Font, fs: int, col: Color) -> void:
		var lines: Array = r.get("lines", [])
		if lines.size() == 2:
			var goal := String(r["type"]) == "goal"
			var small_f := UIKit.font_w(600)
			draw_string(small_f if goal else f, Vector2(x, y + 22), String(lines[0]), HORIZONTAL_ALIGNMENT_LEFT, room, 16 if goal else fs,
				UIKit.IVORY_MUTED if goal else col)
			draw_string(f if goal else small_f, Vector2(x, y + 45), String(lines[1]), HORIZONTAL_ALIGNMENT_LEFT, room, fs if goal else 16,
				col if goal else UIKit.IVORY_MUTED)
			return
		draw_string(f, Vector2(x, y + h * 0.5 + (6 if fs <= 17 else 7)), String(r["text"]), HORIZONTAL_ALIGNMENT_LEFT, room, fs, col)

	func _draw() -> void:
		var y := 0.0
		for r in hud.personal_rows:
			var h := _row_h(r)
			match String(r["type"]):
				"waters":
					_waters(y, h, r)
				"goal":
					_goal(y, h, r)
				"pace":
					_pace(y, h, r)
				"line":
					_line(y, h, r)
				"guard":
					_guard(y, h, r)
			y += h + GAP

	func _bg(y: float, h: float, emph: bool, border: Color = UIKit.AMBER) -> void:
		draw_style_box(UIKit.box(Color(UIKit.SLATE, 0.92) if emph else Color(UIKit.NAVY, 0.62), 999, 2 if emph else 0, border), Rect2(0, y, size.x, h))

	func _waters(y: float, h: float, r: Dictionary) -> void:
		_bg(y, h, false)
		_words(16, y, h, r, size.x - 130, UIKit.font_w(700), 19, UIKit.IVORY)
		var ws: Array = r["waters"]
		var x := size.x - 22.0 - 34.0 * float(ws.size() - 1)
		for w in ws:
			var c := Vector2(x, y + h * 0.5)
			var col: Color = w["col"]
			if bool(w["done"]):
				draw_circle(c, 14.0, col)
				Icons.draw_shape(self, "check", c, 8, UIKit.NAVY)
			else:
				draw_arc(c, 13.0, 0, TAU, 24, Color(col, 0.9), 2.0, true)
				Icons.draw_shape(self, String(w["icon"]), c, 8, col)
			x += 34.0

	func _arrow(c: Vector2, a: float, col: Color) -> void:
		var dir := Vector2(sin(a), -cos(a))
		var sd := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([c + dir * 9.0, c - dir * 6.0 + sd * 6.0, c - dir * 6.0 - sd * 6.0]), col)

	func _goal(y: float, h: float, r: Dictionary) -> void:
		var col: Color = r["col"]
		_bg(y, h, true, col if float(r.get("bearing", INF)) != INF else UIKit.BAD)
		Icons.draw_shape(self, String(r["icon"]), Vector2(22, y + h * 0.5), 12, col)
		var has_dir := float(r.get("bearing", INF)) != INF
		_words(42, y, h, r, size.x - (124.0 if has_dir else 52.0), UIKit.font_w(700), 19, UIKit.IVORY)
		if has_dir:
			_arrow(Vector2(size.x - 74, y + h * 0.5), float(r["bearing"]), UIKit.IVORY)
			draw_string(UIKit.font_num(600), Vector2(size.x - 60, y + h * 0.5 + 6), "%dm" % int(r["dist"]), HORIZONTAL_ALIGNMENT_LEFT, 56, 17, Color(UIKit.IVORY, 0.85))

	func _pace(y: float, h: float, r: Dictionary) -> void:
		var f := UIKit.font_w(600)
		var t := String(r["text"])
		var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var w := minf(size.x, 34.0 + tw + 36.0)
		draw_style_box(UIKit.box(Color(UIKit.NAVY, 0.5), 999), Rect2(0, y, w, h))
		# a small flag shape: pace is a race-style position, not the team's result
		var fc := Vector2(18, y + h * 0.5)
		draw_line(fc + Vector2(-5, 8), fc + Vector2(-5, -8), UIKit.IVORY_MUTED, 2.0)
		draw_colored_polygon(PackedVector2Array([fc + Vector2(-4, -8), fc + Vector2(7, -4), fc + Vector2(-4, 0)]), UIKit.IVORY_MUTED)
		draw_string(f, Vector2(34, y + h * 0.5 + 6), t, HORIZONTAL_ALIGNMENT_LEFT, size.x - 60, 17, UIKit.IVORY_MUTED)
		var d := int(r.get("delta", 0))
		if d != 0:
			var c := Vector2(minf(34.0 + tw + 14.0, w - 12.0), y + h * 0.5)
			var a := 1.0 if UIKit.reduced_motion() else clampf(float(r.get("fade", 1.0)), 0.0, 1.0)
			var col := Color(UIKit.TEAL, a) if d > 0 else Color(UIKit.IVORY_MUTED, a)
			var s := -1.0 if d > 0 else 1.0
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, 6 * s), c + Vector2(-6, -4 * s), c + Vector2(6, -4 * s)]), col)

	func _line(y: float, h: float, r: Dictionary) -> void:
		var col: Color = r["col"]
		var small := bool(r.get("small", false))
		_bg(y, h, false)
		Icons.draw_shape(self, String(r["icon"]), Vector2(20, y + h * 0.5), 10 if small else 12, col)
		_words(38, y, h, r, size.x - 60, UIKit.font_w(600 if small else 700), 17 if small else 19, col if col != UIKit.IVORY_MUTED else UIKit.IVORY)
		if bool(r.get("check", false)):
			Icons.draw_shape(self, "check", Vector2(size.x - 22, y + h * 0.5), 10, UIKit.TEAL)

	func _guard(y: float, h: float, r: Dictionary) -> void:
		_bg(y, h, false)
		var ws: Array = r["waters"]
		var cw := size.x / float(maxi(1, ws.size()))
		for i in ws.size():
			var w: Dictionary = ws[i]
			var x0 := cw * float(i)
			Icons.draw_shape(self, String(w["icon"]), Vector2(x0 + 20, y + h * 0.5), 11, w["col"])
			_arrow(Vector2(x0 + 42, y + h * 0.5), float(w["bearing"]), UIKit.IVORY)
			draw_string(UIKit.font_num(600), Vector2(x0 + 54, y + h * 0.5 + 6), "%dm" % int(w["dist"]), HORIZONTAL_ALIGNMENT_LEFT, cw - 56, 16, Color(UIKit.IVORY, 0.85))


## Pass 8: a sprint meter.  While the latch is on (ran dry, sprint still
## held) it is coral with diagonal hatching - a shape as well as a colour -
## with a tick at the re-arm level when the rules give one.
class SprintMeter:
	extends Control
	var value := 0.0
	var rearm := -1.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		SprintMeter.paint(self, Rect2(Vector2.ZERO, size), value, true, rearm)

	static func paint(ci: CanvasItem, r: Rect2, v: float, latched: bool, rearm_at: float) -> void:
		ci.draw_style_box(UIKit.box(Color(0, 0, 0, 0.45), 8), r)
		var fill := Rect2(r.position, Vector2(r.size.x * clampf(v, 0.0, 1.0), r.size.y))
		if not latched:
			ci.draw_style_box(UIKit.box(UIKit.ACCENT if v > 0.15 else UIKit.BAD, 8), fill)
			return
		ci.draw_style_box(UIKit.box(Color(UIKit.BAD, 0.75), 8), fill)
		var x := fill.position.x + 4.0
		while x < fill.end.x:
			var x2 := minf(x + r.size.y * 0.6, fill.end.x)
			ci.draw_line(Vector2(x, fill.end.y - 2.0), Vector2(x2, fill.position.y + 2.0), Color(UIKit.NAVY, 0.55), 2.0)
			x += 8.0
		if rearm_at > 0.0 and rearm_at < 1.0:
			var tx := r.position.x + r.size.x * rearm_at
			ci.draw_line(Vector2(tx, r.position.y - 3.0), Vector2(tx, r.end.y + 3.0), UIKit.IVORY, 2.0)


## The team's home tracker: one segment per required finish, filled for each
## runner actually home (a house shape in each filled slot, so it never
## reads as colour alone).
class HomeTracker:
	extends Control
	var needed := 4
	var home := 0
	var role := 0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _get_minimum_size() -> Vector2:
		return Vector2(float(needed) * 18.0 - 4.0, 24.0)

	func _draw() -> void:
		var col := UIKit.TEAL if role != TC.Role.PATROL else UIKit.RUNNER
		for i in needed:
			var r := Rect2(float(i) * 18.0, 2.0, 14.0, 20.0)
			if i < home:
				draw_style_box(UIKit.box(col, 4), r)
				Icons.draw_shape(self, "house", r.get_center(), 5.0, UIKit.NAVY)
			else:
				draw_style_box(UIKit.box(Color(UIKit.IVORY, 0.0), 4, 2, Color(UIKit.IVORY, 0.55)), r)


## A small clock face beside the round clock; under ten seconds it becomes
## an alarm clock (bells), so urgency is a shape as well as a colour.
class ClockIcon:
	extends Control
	var urgency := 0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.38
		var col: Color = [UIKit.IVORY_MUTED, UIKit.AMBER, UIKit.BAD][clampi(urgency, 0, 2)]
		if urgency == 2:
			for s in [-1.0, 1.0]:
				draw_circle(c + Vector2(s * r * 0.85, -r * 0.95), r * 0.38, col)
		draw_arc(c, r, 0, TAU, 24, col, 2.0, true)
		draw_line(c, c + Vector2(0, -r * 0.65), col, 2.0)
		draw_line(c, c + Vector2(r * 0.5, 0), col, 2.0)


class Minimap:
	extends Control
	var hud: MatchHUD
	var _ring := PackedVector2Array()
	var _uv := PackedVector2Array()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = "Map"
		accessibility_name = "Map"

	## Tap (or click) the minimap: the full map.  V7: from any finger (the
	## engine emulates the mouse from the first finger only, so a second
	## finger's tap while steering used to do nothing); the first finger's
	## emulated mouse twin is ignored, so a tap opens the map once.
	func _gui_input(e: InputEvent) -> void:
		var tap := false
		if e is InputEventScreenTouch:
			tap = (e as InputEventScreenTouch).pressed
		elif e is InputEventMouseButton and e.device != InputEvent.DEVICE_ID_EMULATION:
			var mb := e as InputEventMouseButton
			tap = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
		if tap:
			accept_event()
			hud.open_map()

	func _draw() -> void:
		var s := size
		var half := minf(s.x, s.y) * 0.5
		var c := s * 0.5
		# the baked campus, clipped to a disc by drawing it as a textured
		# polygon (no shader, no extra node)
		if _ring.size() == 0 or not is_equal_approx(_uv[0].x, 1.0 - 0.0) or _ring[0] != c + Vector2(half, 0):
			_ring.clear()
			_uv.clear()
			for i in 48:
				var a := TAU * float(i) / 48.0
				var d := Vector2(cos(a), sin(a))
				_ring.append(c + d * (half - 1.0))
				_uv.append(Vector2(0.5, 0.5) + d * 0.5 * (half - 1.0) / half)
		draw_circle(c, half, Color(0.05, 0.08, 0.16, 0.85))
		var tex := CampusMap.shared().texture(hud.mc.layout, CampusMap.MINI_PX)
		draw_polygon(_ring, PackedColorArray([Color(1, 1, 1, 0.94)]), _uv, tex)
		MapPainter.paint(self, hud, c, half, false)


## Live things on the map, over the baked campus picture (CampusMap): your
## arrow and where the camera looks, your team (grouped when close), tonight's
## three waters as distinct markers (done ones checked), the dorm, and - per
## the information policy - only host-sent cues for opponents: splash
## markers (Night Watch) and fading "last seen" rings, never live dots
## through walls.  The full map labels what fits without overlap.
class MapPainter:
	## What the map shows right now, as data (tests check the information
	## policy here): [{kind, pos, ...}] in map units for a square of
	## half-size `half` centred on `c`.  kinds: target, home, team, cart,
	## splash, seen (an opponent: live while in sight, else fading), me.
	static func items(hud: MatchHUD, c: Vector2, half: float, full: bool) -> Array:
		var out: Array = []
		var info := hud.info
		var me: Dictionary = info.get("rs", {})
		var L := hud.mc.layout
		var to_map := func(p: Vector2) -> Vector2: return CampusMap.to_map(p, c, half)
		var tg: Array = info.get("targets", [])
		var stamps: int = info.get("stamps", 0)
		var role: int = info.get("role", 0)
		# Pass 8: the personal card's suggestion is marked on the map too
		var sg: Array = hud.suggested_goal() if role == TC.Role.RUNNER else []
		for i in L.waters.size():
			var ti := tg.find(i)
			if ti >= 0:
				var w: Dictionary = L.waters[i]
				out.append({"kind": "target", "pos": to_map.call(w["center"]), "water": i,
					"done": (stamps & (1 << ti)) != 0 and role == TC.Role.RUNNER,
					"next": not sg.is_empty() and String(sg[0]) == "water" and int(sg[1]) == ti})
		# V6: tonight's home dorm and each of its doors (the way back in)
		out.append({"kind": "home", "pos": to_map.call(L.dorm_center(hud.mc.home_dorm)), "dorm": hud.mc.home_dorm})
		var doors := L.home_doors(hud.mc.home_dorm)
		for di in doors.size():
			var d: Dictionary = doors[di]
			out.append({"kind": "door", "pos": to_map.call(d["pos"]), "normal": d["normal"], "door": di,
				"next": not sg.is_empty() and String(sg[0]) == "door" and int(sg[1]) == di})
		# your team (same role, openly shown); close teammates share one mark
		var groups: Array = []
		for slot in hud.mc.roster:
			if int(slot) == hud.mc.local_slot or int(hud.mc.roster[slot]["role"]) != role:
				continue
			var rs := hud.mc._player_rs(int(slot))
			if not rs.has("pos") or int(rs.get("state", 0)) == TC.PState.FINISHED:
				continue
			var pp: Vector3 = rs["pos"]
			var mp: Vector2 = to_map.call(Vector2(pp.x, pp.z))
			var joined := false
			for gr in groups:
				if (gr["pos"] as Vector2).distance_to(mp) < (16.0 if full else 7.0):
					(gr["names"] as Array).append(String(hud.mc.roster[slot]["name"]))
					(gr["slots"] as Array).append(int(slot))
					joined = true
					break
			if not joined:
				groups.append({"kind": "team", "pos": mp, "names": [String(hud.mc.roster[slot]["name"])], "slots": [int(slot)], "role": role})
		out.append_array(groups)
		if role == TC.Role.PATROL:
			for i in hud.mc.cart_views.size():
				var crs := hud.mc._cart_rs(i)
				if crs.has("pos"):
					var cp: Vector3 = crs["pos"]
					out.append({"kind": "cart", "pos": to_map.call(Vector2(cp.x, cp.z))})
			for m in info.get("markers", []):
				var w2: Dictionary = L.waters[int(m["water"])]
				out.append({"kind": "splash", "pos": to_map.call(w2["center"]),
					"left": clampf(float(m.get("t", 0.0)) / maxf(0.1, hud.mc.cfg.splash_marker_s), 0.0, 1.0)})
		# opponents: only what your own sight recorded (MatchController.
		# last_seen): live while in sight, then frozen where last seen,
		# hollow and fading with its age, gone after the TTL
		var now := Time.get_ticks_msec()
		for slot in hud.mc.last_seen:
			var ls: Dictionary = hud.mc.last_seen[slot]
			var age := float(now - int(ls["ms"])) / 1000.0
			if age > MatchController.LAST_SEEN_TTL_S:
				continue
			var lp: Vector3 = ls["pos"]
			var live := bool(ls.get("live", false))
			out.append({"kind": "seen", "pos": to_map.call(Vector2(lp.x, lp.z)), "slot": int(slot), "live": live,
				"fade": clampf(1.0 - age / MatchController.LAST_SEEN_TTL_S, 0.0, 1.0), "age": age,
				"cart": bool(ls.get("cart", false)), "yaw": float(ls.get("yaw", 0.0)),
				"near": live and role == TC.Role.RUNNER and float(ls.get("dist", INF)) <= MatchHUD.DANGER_M,
				"opp": TC.Role.RUNNER if role == TC.Role.PATROL else TC.Role.PATROL})
		if me.has("pos"):
			var mp2: Vector3 = me["pos"]
			out.append({"kind": "me", "pos": to_map.call(Vector2(mp2.x, mp2.z)), "yaw": float(me.get("yaw", 0.0)),
				"cam": hud.mc.camera.yaw if hud.mc.camera else INF})
		return out

	## A team mark: runners a disc, the Night Watch a diamond (shape and colour).
	static func _team_mark(ci: CanvasItem, p: Vector2, r: float, role: int, col: Color) -> void:
		if role == TC.Role.PATROL:
			var o := r + 2.0
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -o), p + Vector2(o, 0), p + Vector2(0, o), p + Vector2(-o, 0)]), Color(UIKit.NAVY, 0.9))
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)]), col)
		else:
			ci.draw_circle(p, r + 2.0, Color(UIKit.NAVY, 0.9))
			ci.draw_circle(p, r, col)

	## An opponent you can see now: a solid badge of its role's shape (the
	## Night Watch a diamond with a whistle, a cart glyph while driving; a
	## runner a disc with a drop) and a short tick for its facing; a nearby
	## Night Watch also gets an amber ring.  Lost from sight: the same shape
	## hollow, frozen at the last point, dimming with age.
	static func _seen_mark(ci: CanvasItem, it: Dictionary, full: bool, opp_col: Color) -> void:
		var p: Vector2 = it["pos"]
		var r := 9.0 if full else 5.5
		var watch := int(it.get("opp", TC.Role.PATROL)) == TC.Role.PATROL
		if bool(it["live"]):
			if bool(it.get("near", false)):
				ci.draw_arc(p, r + (6.0 if full else 4.0), 0, TAU, 24, Color(UIKit.AMBER, 0.95), 2.0, true)
			var yaw := float(it.get("yaw", 0.0))
			var fw := Vector2(-sin(yaw), -cos(yaw))
			ci.draw_line(p + fw * r, p + fw * (r + (7.0 if full else 4.0)), Color(UIKit.IVORY, 0.9), 2.0, true)
			if watch:
				_team_mark(ci, p, r, TC.Role.PATROL, Color(opp_col, 0.95))
				Icons.draw_shape(ci, "cart" if bool(it.get("cart", false)) else "whistle", p, r * 0.55, UIKit.NAVY)
			else:
				ci.draw_circle(p, r + 1.5, Color(UIKit.NAVY, 0.85))
				ci.draw_circle(p, r, Color(opp_col, 0.95))
				Icons.draw_shape(ci, "drop", p, r * 0.55, UIKit.NAVY)
			return
		var a := 0.2 + 0.65 * float(it["fade"])
		var col := Color(opp_col, a)
		if watch:
			ci.draw_polyline(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0), p + Vector2(0, -r)]), col, 2.0, true)
		else:
			ci.draw_arc(p, r, 0, TAU, 18, col, 2.0, true)

	static func paint(ci: CanvasItem, hud: MatchHUD, c: Vector2, half: float, full: bool) -> void:
		var L := hud.mc.layout
		if full:
			var tex := CampusMap.shared().texture(L, CampusMap.FULL_PX)
			ci.draw_texture_rect(tex, Rect2(c - Vector2.ONE * half, Vector2.ONE * half * 2.0), false)
		var role := int(hud.info.get("role", 0))
		var f := UIKit.font_w(700)
		var labels: Array = []
		var blocked: Array = []
		var k := 1.0 if full else 0.55
		var tc := UIKit.PATROL if role == TC.Role.PATROL else UIKit.RUNNER
		var opp := UIKit.RUNNER if role == TC.Role.PATROL else UIKit.PATROL
		var me_item: Dictionary = {}
		for it in items(hud, c, half, full):
			var p: Vector2 = it["pos"]
			match String(it["kind"]):
				"target":
					# tonight's waters: a round badge in the water's colour with its icon
					var w: Dictionary = L.waters[int(it["water"])]
					var done := bool(it["done"])
					var col: Color = w["color"]
					var r := 15.0 * k
					if bool(it.get("next", false)):
						# the personal card's suggestion: a still ring (any
						# remaining water counts; this is a good next one)
						ci.draw_arc(p, r + 7.0 * k, 0, TAU, 32, Color(UIKit.IVORY, 0.9), 2.5 if full else 1.5, true)
					ci.draw_circle(p, r + 3.0 * k, Color(UIKit.NAVY, 0.85))
					ci.draw_circle(p, r, col.darkened(0.55) if done else col)
					Icons.draw_shape(ci, String(w["icon"]), p, r * 0.6, UIKit.NAVY if not done else Color(col, 0.55))
					if done:
						# checked for your stamp; the water's own shape stays readable
						var cp := p + Vector2(r * 0.75, -r * 0.75)
						ci.draw_circle(cp, r * 0.5, UIKit.TEAL)
						Icons.draw_shape(ci, "check", cp, r * 0.32, UIKit.NAVY)
					blocked.append(Rect2(p - Vector2.ONE * (r + 3.0), Vector2.ONE * (r + 3.0) * 2.0))
					if full:
						labels.append({"at": p, "text": String(w["short"]) + (" · done" if done else ""), "size": 18, "prio": 3, "col": UIKit.IVORY, "r": r})
				"door":
					# a small warm wedge at each home door, pointing out;
					# the suggested door (all three stamped) is larger and ringed
					var nn: Vector2 = it["normal"]
					var nx := bool(it.get("next", false))
					var dr := (7.0 if full else 4.0) * (1.5 if nx else 1.0)
					var tip := p + nn * dr * 1.4
					var sd := Vector2(-nn.y, nn.x) * dr * 0.8
					if nx:
						ci.draw_arc(p + nn * dr * 0.5, dr * 1.6, 0, TAU, 24, Color(1.0, 0.86, 0.5, 0.9), 2.0 if full else 1.5, true)
					ci.draw_colored_polygon(PackedVector2Array([p - sd, p + sd, tip]), Color(1.0, 0.86, 0.5))
					ci.draw_polyline(PackedVector2Array([p - sd, tip, p + sd]), Color(UIKit.NAVY, 0.85), 1.5, true)
				"home":
					var hr := 14.0 * k
					ci.draw_circle(p, hr + 3.0 * k, Color(UIKit.NAVY, 0.85))
					ci.draw_circle(p, hr, Color(1.0, 0.86, 0.5))
					Icons.draw_shape(ci, "house", p, hr * 0.62, UIKit.NAVY)
					blocked.append(Rect2(p - Vector2.ONE * (hr + 3.0), Vector2.ONE * (hr + 3.0) * 2.0))
					if full:
						labels.append({"at": p, "text": String(CampusDorms.def(String(it.get("dorm", ""))).get("short", "Home")), "size": 18, "prio": 4, "col": Color(1.0, 0.9, 0.62), "r": hr})
				"team":
					# your team in its role's colour and shape: runners round,
					# the Night Watch a diamond; close teammates share one mark
					var names: Array = it["names"]
					var n := names.size()
					var rr := (7.5 if n == 1 else 10.0) * k
					_team_mark(ci, p, rr, int(it.get("role", role)), tc)
					if n > 1 and full:
						ci.draw_string(UIKit.font_num(800), p + Vector2(-rr, 5.0), str(n), HORIZONTAL_ALIGNMENT_CENTER, rr * 2.0, 14, UIKit.NAVY)
					blocked.append(Rect2(p - Vector2.ONE * (rr + 2.0), Vector2.ONE * (rr + 2.0) * 2.0))
					if full:
						labels.append({"at": p, "text": String(names[0]) + ("  +%d" % (n - 1) if n > 1 else ""), "size": 15, "prio": 1, "col": Color(UIKit.IVORY, 0.9), "r": rr})
				"cart":
					Icons.draw_shape(ci, "cart", p, 11 if full else 6, UIKit.PATROL)
				"splash":
					# a splash just happened there: a still ring that fades (no pulsing)
					ci.draw_arc(p, (22.0 if full else 11.0), 0, TAU, 32, Color(1, 1, 1, 0.3 + 0.6 * float(it["left"])), 2.5 if full else 1.5, true)
				"seen":
					_seen_mark(ci, it, full, opp)
					if full and not bool(it["live"]):
						# its age, beside the frozen mark (expanded map only)
						var at := p + Vector2(10, 5)
						ci.draw_string(UIKit.font_num(700), at, "%ds" % int(ceil(float(it["age"]))), HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
							Color(UIKit.IVORY, 0.35 + 0.5 * float(it["fade"])))
				"me":
					me_item = it
		# you, on top: an arrow and a soft wedge for where the camera looks
		if not me_item.is_empty():
			var mpos: Vector2 = me_item["pos"]
			var yaw: float = me_item["yaw"]
			var fw := Vector2(-sin(yaw), -cos(yaw))
			var sd := Vector2(-fw.y, fw.x)
			var kk := 1.7 if full else 1.0
			if float(me_item["cam"]) != INF:
				var cy: float = me_item["cam"]
				var vf := Vector2(-sin(cy), -cos(cy))
				var vs := Vector2(-vf.y, vf.x)
				var ln := (46.0 if full else 22.0)
				ci.draw_colored_polygon(PackedVector2Array([mpos, mpos + (vf + vs * 0.55) * ln, mpos + (vf - vs * 0.55) * ln]), Color(1, 1, 1, 0.13))
			var tri := PackedVector2Array([mpos + fw * 9.0 * kk, mpos - fw * 5.0 * kk + sd * 5.5 * kk, mpos - fw * 2.5 * kk, mpos - fw * 5.0 * kk - sd * 5.5 * kk])
			var outline := PackedVector2Array()
			for pnt in tri:
				outline.append(mpos + (pnt - mpos) * 1.35)
			ci.draw_colored_polygon(outline, Color(UIKit.NAVY, 0.9))
			ci.draw_colored_polygon(tri, Color(1, 1, 1))
			blocked.append(Rect2(mpos - Vector2.ONE * 12.0 * kk, Vector2.ONE * 24.0 * kk))
		if full:
			var area := Rect2(c - Vector2.ONE * half, Vector2.ONE * half * 2.0).grow(-6.0)
			for lb in CampusMap.place_labels(labels, f, area, blocked):
				var rect: Rect2 = lb["rect"]
				ci.draw_style_box(UIKit.box(Color(UIKit.NAVY, 0.72), 8), rect)
				ci.draw_string(f, rect.position + Vector2(5, rect.size.y - 6), String(lb["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(lb["size"]), lb["col"])
		else:
			ci.draw_arc(c, half - 1.0, 0, TAU, 48, Color(1, 1, 1, 0.35), 2.0, true)


## The full map: tap the minimap or press Map; Close (or Back / Map again).
## Left: the map, as large as fits.  Right: a compact panel (Pass 8) - the
## team goal, the series standing (party rounds, after the first results),
## the legend "You · Team · Watch in sight · Last seen" (plus waters and
## home), then the expanded standings: runners see the live Runner pace of
## every runner (BOT marked, with one help line); the Night Watch sees its
## own team and its tags.  A small help button explains the map.  The round
## keeps running; touch controls are set aside while it is open so a finger
## can't move or turn you underneath.
class FullMap:
	extends Control
	var hud: MatchHUD
	var canvas: Control
	var team_box: VBoxContainer
	var close_btn: Button
	var help_btn: Button
	var help_card: Control
	var home_lbl: Label
	var series_lbl: Label
	var list_title: Label
	var _rows_sig := ""

	const PACE_HELP := "Pace follows splashes and route remaining. Your team wins by getting enough runners home."

	func build() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		var dim := ColorRect.new()
		dim.color = Color(UIKit.NAVY, 0.84)
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dim)
		canvas = MapCanvas.new()
		(canvas as MapCanvas).hud = hud
		canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
		canvas.accessibility_name = "Campus map"
		add_child(canvas)
		var side := UIKit.panel(Color(UIKit.SLATE, 0.97), UIKit.R_PANEL, 18)
		side.name = "Side"
		side.custom_minimum_size = Vector2(390, 0)
		var v := UIKit.vbox(8)
		var head := UIKit.hbox(8)
		var title := UIKit.styled("Map", "headline")
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		head.add_child(title)
		help_btn = UIKit.icon_button("info")
		help_btn.tooltip_text = "What the map shows"
		help_btn.accessibility_name = "What the map shows"
		help_btn.pressed.connect(_toggle_help)
		head.add_child(help_btn)
		close_btn = UIKit.secondary("Close", Vector2(130, 0))
		close_btn.pressed.connect(func() -> void: hud.close_map())
		head.add_child(close_btn)
		v.add_child(head)
		home_lbl = UIKit.styled("", "label", UIKit.AMBER)
		v.add_child(home_lbl)
		series_lbl = UIKit.styled("", "caption", UIKit.IVORY_MUTED)
		series_lbl.add_theme_font_size_override("font_size", 18)
		v.add_child(series_lbl)
		# the legend: You · Team · Watch in sight · Last seen, then waters / home
		var role := int(hud.info.get("role", 0))
		var team_col := UIKit.PATROL if role == TC.Role.PATROL else UIKit.RUNNER
		var opp_col := UIKit.RUNNER if role == TC.Role.PATROL else UIKit.PATROL
		var legend := GridContainer.new()
		legend.columns = 2
		legend.add_theme_constant_override("h_separation", 14)
		legend.add_theme_constant_override("v_separation", 2)
		var opp_kind := "seen_runner" if role == TC.Role.PATROL else "seen_watch"
		var lost_kind := "lost_runner" if role == TC.Role.PATROL else "lost_watch"
		for r in [["arrow", "You", UIKit.IVORY], ["team_watch" if role == TC.Role.PATROL else "team_runner", "Team", team_col],
				[opp_kind, "Runner in sight" if role == TC.Role.PATROL else "Watch in sight", opp_col], [lost_kind, "Last seen", opp_col],
				["star", "Tonight's waters", UIKit.AMBER], ["house", "Home doors", Color(1.0, 0.86, 0.5)]]:
			var row := UIKit.hbox(6)
			row.add_child(LegendMark.make(String(r[0]), r[2]))
			var l := UIKit.styled(String(r[1]), "caption", UIKit.IVORY_MUTED)
			l.add_theme_font_size_override("font_size", 17)
			row.add_child(l)
			legend.add_child(row)
		v.add_child(legend)
		list_title = UIKit.styled("Runner pace" if role == TC.Role.RUNNER else "Your team", "overline", UIKit.IVORY_MUTED)
		v.add_child(list_title)
		var sc := UIKit.scroll_area()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sc.custom_minimum_size = Vector2(0, 110)
		team_box = UIKit.vbox(4)
		team_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(team_box)
		v.add_child(sc)
		side.add_child(v)
		add_child(side)
		refresh_team()
		Motion.settle_in(side, UIKit.T_FAST)

	func _toggle_help() -> void:
		if help_card != null and is_instance_valid(help_card):
			help_card.queue_free()
			help_card = null
			return
		var role := int(hud.info.get("role", 0))
		var p := UIKit.panel(Color(UIKit.SLATE_HI, 0.99), UIKit.R_PANEL, 18)
		var v := UIKit.vbox(6)
		var lines := ["The white arrow is you; the light wedge is where your camera looks.",
			"Tonight's three waters have their own shapes; a check means you've splashed there. A ring marks the one your card suggests - any of them counts.",
			"Your team is shown in its colour and shape; close teammates share one mark with a count.",
			"Opponents appear only while you can see them, with a short line for their facing. When you lose sight the mark stays where you last saw them, hollow, with its age, and goes after %d s." % int(MatchController.LAST_SEEN_TTL_S)]
		if role == TC.Role.PATROL:
			lines.append("Carts are drawn as cart icons; a white ring marks a splash that just happened.")
		else:
			lines.append(PACE_HELP)
		for ln in lines:
			var l := UIKit.styled(ln, "caption", UIKit.IVORY)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(420, 0)
			v.add_child(l)
		p.add_child(v)
		add_child(p)
		var side := get_node("Side") as Control
		p.position = Vector2(side.position.x - p.get_combined_minimum_size().x - 12, side.position.y)
		help_card = p
		Motion.appear(p, 6.0, UIKit.T_FAST)

	## The expanded standings, rebuilt only when what they say changes.
	func refresh_team() -> void:
		var mc := hud.mc
		var role := int(hud.info.get("role", 0))
		var fin := int(hud.info.get("finished", 0))
		home_lbl.text = hud.goal_text(role, fin) + ((" " + MatchHUD.clock_text(float(hud.info.get("time_left", 0.0)))) if role == TC.Role.PATROL else "")
		var sl := hud.series_line()
		series_lbl.text = sl
		series_lbl.visible = sl != ""
		var rows := standings_rows()
		var sig := JSON.stringify(rows)
		if sig == _rows_sig:
			return
		_rows_sig = sig
		for c in team_box.get_children():
			c.queue_free()
		for r in rows:
			var row := UIKit.hbox(8)
			var pl := UIKit.styled(String(r["place"]), "num", UIKit.AMBER if bool(r["me"]) else UIKit.IVORY_MUTED)
			pl.custom_minimum_size = Vector2(44, 0)
			row.add_child(pl)
			row.add_child(Icons.IconRect.new(String(r["icon"]), UIKit.PATROL if role == TC.Role.PATROL else UIKit.TEAL, 20))
			var nl := UIKit.styled(String(r["name"]), "label", UIKit.AMBER if bool(r["me"]) else UIKit.IVORY)
			nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			UIKit.fit_text(nl, [18, 16])
			row.add_child(nl)
			var wl := UIKit.styled(String(r["what"]), "caption", UIKit.IVORY_MUTED)
			wl.add_theme_font_size_override("font_size", 16)
			row.add_child(wl)
			team_box.add_child(row)
		if role == TC.Role.RUNNER:
			var help := UIKit.styled(PACE_HELP, "caption", UIKit.IVORY_MUTED)
			help.add_theme_font_size_override("font_size", 16)
			help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			help.custom_minimum_size = Vector2(320, 0)
			team_box.add_child(help)
		elif role == TC.Role.PATROL:
			var mine := UIKit.styled("You: %d tags · %d different runners" % [int(hud.info.get("tags", 0)), int(hud.info.get("distinct", 0))], "caption", UIKit.AMBER)
			mine.add_theme_font_size_override("font_size", 17)
			team_box.add_child(mine)

	## As data (tests): [{place, name, what, icon, me, bot, slot}].
	## Runners: every runner by published pace (shared places "T3"), BOT
	## marked; places come only from the host's pace (none yet: "–").
	## Night Watch: its own team, as before (no pace for the Watch).
	func standings_rows() -> Array:
		var mc := hud.mc
		var role := int(hud.info.get("role", 0))
		var out: Array = []
		if role == TC.Role.SPECTATOR:
			return out
		var pace: Dictionary = hud.info.get("pace", {})
		var phase := int(hud.info.get("phase", 0))
		var over := phase == TC.Phase.RESULTS or phase == TC.Phase.ENDED
		for slot in mc.roster:
			var e: Dictionary = mc.roster[slot]
			if int(e["role"]) != role:
				continue
			var rs := mc._player_rs(int(slot))
			var st := int(rs.get("state", TC.PState.ACTIVE))
			var me := int(slot) == mc.local_slot
			var name := ("You" if me else String(e["name"])) + ("  · BOT" if bool(e["is_bot"]) else "")
			if role == TC.Role.PATROL:
				var what := "Driving" if st == TC.PState.IN_CART or st == TC.PState.ENTERING else "On foot"
				if not bool(rs.get("connected", true)):
					what = "Away"
				out.append({"place": "", "name": name, "what": what, "icon": "whistle", "me": me, "bot": bool(e["is_bot"]), "slot": int(slot), "_k": int(slot)})
				continue
			var pe: Dictionary = pace.get(int(slot), {})
			var place := "–"
			var k := 100 + int(slot)
			if not pe.is_empty():
				place = ("T%d" if bool(pe["tied"]) else "%d") % int(pe["place"])
				k = int(pe["place"]) * 10
			var what2 := ""
			if bool(pe.get("home", false)) or st == TC.PState.FINISHED:
				what2 = "Home"
			elif over:
				what2 = "Not home · %d/3" % int(pe.get("stamps", FullMap._bits(int(rs.get("stamps", 0)))))
			else:
				var n := int(pe.get("stamps", FullMap._bits(int(rs.get("stamps", 0)))))
				what2 = "%d/3 waters" % n
				if st == TC.PState.CAPTURED:
					what2 += " · caught"
				elif not bool(rs.get("connected", true)):
					what2 += " · away"
			out.append({"place": place, "name": name, "what": what2, "icon": "house" if what2 == "Home" else "drop", "me": me,
				"bot": bool(e["is_bot"]), "slot": int(slot), "_k": k})
		out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["_k"]) < int(b["_k"]) if int(a["_k"]) != int(b["_k"]) else int(a["slot"]) < int(b["slot"]))
		for r in out:
			r.erase("_k")
		return out

	static func _bits(v: int) -> int:
		var n := 0
		for i in 3:
			if v & (1 << i):
				n += 1
		return n

	## Laid out as soon as it enters the tree, so its first frame is already
	## in place (V5: the panel showed at the top left for one frame).
	func _ready() -> void:
		_place()

	func _process(_d: float) -> void:
		_place()

	func _place() -> void:
		var vs := get_viewport().get_visible_rect().size
		var safe := UIKit.safe_margins(get_viewport())
		var side := get_node("Side") as Control
		var sw := side.get_combined_minimum_size()
		var avail_h := vs.y - safe.position.y - safe.size.y - 32
		side.position = Vector2(vs.x - safe.size.x - 16 - sw.x, safe.position.y + 16)
		side.size = Vector2(sw.x, avail_h)
		var avail := Rect2(safe.position.x + 16, safe.position.y + 16, side.position.x - safe.position.x - 32, avail_h)
		var half := minf(avail.size.x, avail.size.y) * 0.5
		canvas.position = avail.get_center() - Vector2.ONE * half
		canvas.size = Vector2.ONE * half * 2.0
		canvas.queue_redraw()


## A tiny legend mark matching the map's own markers.
class LegendMark:
	extends Control
	var kind := "dot"
	var col := Color.WHITE

	static func make(k: String, c: Color) -> LegendMark:
		var m := LegendMark.new()
		m.kind = k
		m.col = c
		m.custom_minimum_size = Vector2(24, 24)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return m

	func _draw() -> void:
		var c := size * 0.5
		match kind:
			"arrow":
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -9), c + Vector2(7, 7), c + Vector2(0, 3), c + Vector2(-7, 7)]), col)
			"team_runner":
				MapPainter._team_mark(self, c, 7.0, TC.Role.RUNNER, col)
			"team_watch":
				MapPainter._team_mark(self, c, 7.0, TC.Role.PATROL, col)
			"seen_watch", "seen_runner", "lost_watch", "lost_runner":
				var it := {"pos": c, "live": kind.begins_with("seen"), "fade": 0.7, "yaw": 0.0, "cart": false,
					"opp": TC.Role.PATROL if kind.ends_with("watch") else TC.Role.RUNNER}
				MapPainter._seen_mark(self, it, true, col)
			"ring":
				draw_arc(c, 7.0, 0, TAU, 18, col, 2.0, true)
			"dot":
				draw_circle(c, 7.0, col)
			_:
				draw_circle(c, 10.0, col)
				Icons.draw_shape(self, kind, c, 6.0, UIKit.NAVY)


class MapCanvas:
	extends Control
	var hud: MatchHUD

	func _draw() -> void:
		MapPainter.paint(self, hud, size * 0.5, minf(size.x, size.y) * 0.5, true)
