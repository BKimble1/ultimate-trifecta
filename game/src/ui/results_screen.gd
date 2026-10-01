class_name ResultsScreen
extends Screen
## Results: outcome first, then *your* contribution and rewards, then one
## primary action (Rematch / Play again).  The full scoreboard is one tap
## away in a drawer.  The player's character is on the dorm stage (the same
## asset as everywhere else), celebrating or shrugging.

var results: Dictionary
var reward: Dictionary
var session: NetSession
var _board: PanelContainer


func build() -> void:
	if App.stage:
		App.stage.set_mode("home", false)
		App.sync_stage_local()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shade := TextureRect.new()
	shade.texture = TitleScreen._side_gradient()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	move_child(shade, 0)
	var oc := int(results.get("outcome", 0))
	var my_slot := session.local_slot if session else -1
	var me: Dictionary = {}
	for r in results.get("players", []):
		if int(r["slot"]) == my_slot:
			me = r
	var my_role := int(me.get("role", -1))
	var won := (oc == TC.Outcome.RUNNERS_WIN and my_role == TC.Role.RUNNER) or (oc == TC.Outcome.PATROL_WIN and my_role == TC.Role.PATROL)
	if App.stage:
		App.stage.emote(Save.player_uid(), 1 if won else 3, 3.5)

	var row := UIKit.hbox(0)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)
	row.add_child(UIKit.spacer_h())
	var sheet := UIKit.panel(Color(UIKit.SLATE, 0.95), UIKit.R_PANEL, 28)
	sheet.custom_minimum_size = Vector2(minf(600.0, get_viewport().get_visible_rect().size.x * 0.56), 0)
	sheet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sheet)
	var v := UIKit.vbox(14)
	sheet.add_child(v)
	var title := "Runners win!" if oc == TC.Outcome.RUNNERS_WIN else ("Night Watch wins!" if oc == TC.Outcome.PATROL_WIN else "Round cancelled")
	var head := UIKit.heading(title, 46, UIKit.TEAL if oc == TC.Outcome.RUNNERS_WIN else (UIKit.PATROL if oc == TC.Outcome.PATROL_WIN else UIKit.IVORY))
	v.add_child(head)
	var sub := "%d of %d runners made it home" % [int(results.get("finished", 0)), int(results.get("needed", 4))]
	if oc == TC.Outcome.RUNNERS_WIN:
		sub += " in %d:%02d" % [int(results.get("round_time", 0)) / 60, int(results.get("round_time", 0)) % 60]
	v.add_child(UIKit.label(sub, 20, UIKit.IVORY_MUTED))
	# your round
	var yr := UIKit.panel(Color(UIKit.NAVY, 0.55), UIKit.R_SMALL, 16)
	var yv := UIKit.vbox(6)
	yv.add_child(UIKit.label("Your round" + ("  ·  your team won" if won else ""), 18, UIKit.AMBER if won else UIKit.IVORY_MUTED, true))
	yv.add_child(UIKit.label(_contribution(me), 24, UIKit.IVORY, true))
	var fastest := int(results.get("fastest_slot", -1))
	if fastest >= 0:
		for r in results.get("players", []):
			if int(r["slot"]) == fastest:
				var ftime := float(results.get("fastest_time", r.get("finish_time", 0.0)))
				var who := "You" if int(r["slot"]) == my_slot else String(r["name"])
				yv.add_child(UIKit.label("Fastest Trifecta: %s  (%d:%02d)" % [who, int(ftime) / 60, int(ftime) % 60], 18, UIKit.IVORY_MUTED))
	yr.add_child(yv)
	v.add_child(yr)
	# rewards (cosmetic coins)
	var rw := UIKit.hbox(14)
	if reward.is_empty():
		rw.add_child(UIKit.label("No rewards for this round.", 20, UIKit.IVORY_MUTED))
	else:
		var coins := UIKit.label("+%d coins" % int(reward.get("coins", 0)), 30, UIKit.AMBER)
		coins.add_theme_font_override("font", UIKit.font_w(700))
		rw.add_child(coins)
		var bits: Array[String] = []
		for line in reward.get("lines", []):
			bits.append("%s %+d" % [line[0], int(line[1])])
		var det := UIKit.label("  ·  ".join(bits), 16, UIKit.IVORY_MUTED)
		det.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		det.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		det.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rw.add_child(det)
	v.add_child(rw)
	if bool(reward.get("level_up", false)):
		v.add_child(UIKit.label("Level up! You're now level %d" % int(reward.get("level", 1)), 22, UIKit.TEAL, true))
	if bool(results.get("practice", false)):
		v.add_child(UIKit.label("Practice round with bots (half rewards).", 16, UIKit.IVORY_MUTED))
	var practice := session != null and session.mode == NetSession.Mode.OFFLINE
	var btns := UIKit.hbox(12)
	var again := UIKit.primary("Play again" if practice else "Rematch", Vector2(300, 96), 32)
	again.pressed.connect(func() -> void: App.rematch())
	btns.add_child(again)
	var board_b := UIKit.quiet("Scoreboard", Vector2(160, 96), 22)
	board_b.pressed.connect(_toggle_board)
	btns.add_child(board_b)
	v.add_child(btns)
	var leave := UIKit.quiet("Menu" if practice else "Leave room", Vector2(472, 72), 22)
	leave.pressed.connect(func() -> void:
		if practice:
			App.goto_title()
		else:
			App.leave_room())
	v.add_child(leave)
	focus_first(again)
	UIKit.appear(sheet, Vector2.ZERO, UIKit.T_SHEET)
	Sfx.play("cheer" if won else "pop")


func _contribution(r: Dictionary) -> String:
	if r.is_empty():
		return "You watched this round."
	if int(r["role"]) == TC.Role.RUNNER:
		var t := "%d/3 splashes" % int(r.get("stamps", 0))
		if bool(r.get("finished", false)):
			var ft := float(r.get("finish_time", 0.0))
			t += "  ·  home #%d at %d:%02d" % [int(r.get("finish_order", 0)), int(ft) / 60, int(ft) % 60]
		if int(r.get("times_captured", 0)) > 0:
			t += "  ·  caught %dx" % int(r["times_captured"])
		return t
	var n := int(r.get("unique_captures", 0))
	return "Caught %d different runner%s" % [n, "" if n == 1 else "s"]


## The full scoreboard: a centred sheet over a dimmed backdrop (tap outside
## or Close to dismiss), sized to the screen so it never covers the results
## sheet partially on narrower aspects (16:9 phones, 4:3 iPad).
func _toggle_board() -> void:
	if _board and is_instance_valid(_board):
		_board.queue_free()
		_board = null
		return
	var vs := get_viewport().get_visible_rect().size
	_board = PanelContainer.new()
	_board.add_theme_stylebox_override("panel", UIKit.box(Color(UIKit.NAVY, 0.72), 0, 0, Color.WHITE, 0))
	_board.set_anchors_preset(Control.PRESET_FULL_RECT)
	_board.mouse_filter = Control.MOUSE_FILTER_STOP
	_board.gui_input.connect(func(ev: InputEvent) -> void:
		if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed):
			_toggle_board())
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(center)
	var sheet := UIKit.panel(Color(UIKit.SLATE_HI, 0.99), UIKit.R_PANEL, 22)
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(sheet)
	var v := UIKit.vbox(10)
	sheet.add_child(v)
	var head := UIKit.hbox(12)
	head.add_child(UIKit.label("Scoreboard", 24, UIKit.IVORY, true))
	head.add_child(UIKit.spacer_h())
	var close := UIKit.quiet("Close", Vector2(140, maxf(56.0, UIKit.touch_min() * 0.8)), 20)
	close.pressed.connect(_toggle_board)
	head.add_child(close)
	v.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 6)
	for h in ["Player", "Role", "Round"]:
		grid.add_child(UIKit.label(h, 16, UIKit.IVORY_MUTED, true))
	var my_slot := session.local_slot if session else -1
	var rows: Array = results.get("players", []).duplicate()
	rows.sort_custom(func(a, b): return [int(a["role"]), -int(a.get("stamps", 0)) - (10 if bool(a.get("finished", false)) else 0)] < [int(b["role"]), -int(b.get("stamps", 0)) - (10 if bool(b.get("finished", false)) else 0)])
	var name_w := clampf(vs.x * 0.2, 170.0, 240.0)
	for r in rows:
		var me := int(r["slot"]) == my_slot
		var col := UIKit.AMBER if me else UIKit.IVORY
		var nm := UIKit.label(String(r["name"]) + ("  · BOT" if bool(r["is_bot"]) else ""), 18, col, me)
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nm.custom_minimum_size = Vector2(name_w, 0)
		grid.add_child(nm)
		grid.add_child(UIKit.label("Runner" if int(r["role"]) == TC.Role.RUNNER else "Night Watch", 17, UIKit.TEAL if int(r["role"]) == TC.Role.RUNNER else UIKit.PATROL))
		grid.add_child(UIKit.label(_contribution(r), 17, col))
	v.add_child(grid)
	add_child(_board)
	focus_first(close)
	close.call_deferred("grab_focus")
	UIKit.appear(sheet, Vector2.ZERO, UIKit.T_FAST)


func _go_back() -> void:
	if _board and is_instance_valid(_board):
		_toggle_board()   # Back / B closes the scoreboard first
		return
	if session == null or session.mode == NetSession.Mode.OFFLINE:
		App.goto_title()
	else:
		App.leave_room()
