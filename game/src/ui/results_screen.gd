class_name ResultsScreen
extends Screen
## Round and series results (V4).  The outcome and why it happened come
## first, then *your* round (role, contribution, rewards), then the series
## so far - or, after the last round, the final friends leaderboard - and one
## clear next action:
##   practice           Play again (primary) · Menu
##   series continues   host: Next round (back to the party room)
##                      guest: Ready for round N (or "Waiting for the host")
##   series over        host: Play again (party room, same settings)
##                      guest: Back to the party room
## The full scoreboard for this round is one tap away in a drawer.  The
## player's character is on the dorm stage, celebrating or shrugging.

var results: Dictionary
var reward: Dictionary
var session: NetSession
## show only the series' final standings (the host ended the series early)
var final_only := false
var _board: PanelContainer
var _primary: Button
var _status: Label
var leave_btn: Button


func build() -> void:
	Diag.context("results")
	if App.stage:
		App.stage.set_mode("home", false)
		App.sync_stage_local()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	TitleScreen.add_shades(self, 0.55, 0.0)
	var practice := session != null and session.mode == NetSession.Mode.OFFLINE
	var view: Dictionary = session.series_view if session else {}
	if results.has("series") and not (results["series"] as Dictionary).is_empty():
		view = results["series"]
	var series_over := not practice and bool(view.get("finished", false))
	var oc := int(results.get("outcome", 0))
	var me := _my_row()
	var my_role := int(me.get("role", -1))
	var won := (oc == TC.Outcome.RUNNERS_WIN and my_role == TC.Role.RUNNER) or (oc == TC.Outcome.PATROL_WIN and my_role == TC.Role.PATROL)
	if App.stage and not final_only:
		App.stage.emote(Save.player_uid(), 1 if won else 3, 3.5)

	var row := UIKit.hbox(0)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)
	row.add_child(UIKit.spacer_h())
	var sheet := UIKit.panel(Color(UIKit.SLATE, 0.95), UIKit.R_PANEL, 26)
	sheet.custom_minimum_size = Vector2(minf(640.0, get_viewport().get_visible_rect().size.x * 0.58), 0)
	sheet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sheet)
	# the summary scrolls when it must; the actions below it never do
	var outer := UIKit.vbox(14)
	sheet.add_child(outer)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	outer.add_child(sc)
	var v := UIKit.vbox(12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)

	if not final_only:
		var round_i := int(results.get("round_index", 1))
		var total := int(results.get("rounds_total", 1))
		if not practice:
			v.add_child(UIKit.styled("Round %d of %d" % [round_i, total], "overline", UIKit.IVORY_MUTED))
		var title := "Runners win!" if oc == TC.Outcome.RUNNERS_WIN else ("Night Watch wins!" if oc == TC.Outcome.PATROL_WIN else "Round cancelled")
		v.add_child(UIKit.styled(title, "display", UIKit.TEAL if oc == TC.Outcome.RUNNERS_WIN else (UIKit.PATROL if oc == TC.Outcome.PATROL_WIN else UIKit.IVORY)))
		var why := UIKit.styled(_why(results), "body", UIKit.IVORY_MUTED)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(why)
		# your round
		var yr := UIKit.panel(Color(UIKit.SLATE_HI, 0.9), UIKit.R_CARD, 18)
		var yv := UIKit.vbox(6)
		var role_txt := "Runner" if my_role == TC.Role.RUNNER else ("Night Watch" if my_role == TC.Role.PATROL else "Watching")
		var yh := UIKit.hbox(10)
		yh.add_child(UIKit.chip(role_txt, UIKit.RUNNER if my_role == TC.Role.RUNNER else UIKit.PATROL, UIKit.NAVY, 18))
		var res_l := UIKit.styled("Your team won" if won else ("Your team lost" if my_role >= 0 and oc != TC.Outcome.CANCELLED else ""), "label", UIKit.AMBER if won else UIKit.IVORY_MUTED)
		res_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		yh.add_child(res_l)
		yv.add_child(yh)
		var contrib := UIKit.styled(contribution(me), "headline")
		contrib.add_theme_font_size_override("font_size", 24)
		contrib.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		yv.add_child(contrib)
		var fastest := int(results.get("fastest_slot", -1))
		if fastest >= 0:
			for r in results.get("players", []):
				if int(r["slot"]) == fastest:
					var ftime := float(results.get("fastest_time", r.get("finish_time", 0.0)))
					var who := "You" if r == me else String(r["name"])
					var fl := UIKit.styled("Fastest Trifecta: %s · %d:%02d" % [who, int(ftime) / 60, int(ftime) % 60], "caption", UIKit.IVORY_MUTED)
					yv.add_child(fl)
		yr.add_child(yv)
		v.add_child(yr)
		_rewards(v)
	# the series
	if not practice and not view.is_empty():
		if series_over or final_only:
			v.add_child(UIKit.styled("Series over" + (" (ended early)" if bool(view.get("ended_early", false)) else ""), "title", UIKit.AMBER))
			v.add_child(standings_table(view, Save.player_uid()))
			v.add_child(_rounds_list(view))
		else:
			var tally := LobbyScreen._tally(view)
			var sp := UIKit.panel(Color(UIKit.NAVY, 0.45), UIKit.R_SMALL, 14)
			var sv := UIKit.vbox(6)
			sv.add_child(UIKit.styled("Series so far · Runners %d – %d Night Watch" % [tally[0], tally[1]], "label"))
			var note := UIKit.styled("A tally by role (roles change between rounds). Your Round Wins are in the standings.", "caption", UIKit.IVORY_MUTED)
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			sv.add_child(note)
			sv.add_child(standings_table(view, Save.player_uid(), 3))
			sp.add_child(sv)
			v.add_child(sp)
	if bool(results.get("practice", false)):
		v.add_child(UIKit.styled("Practice round with bots · half rewards", "caption", UIKit.IVORY_MUTED))
	# actions
	_status = UIKit.styled("", "caption", UIKit.IVORY_MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.visible = false   # shown when there is something to say (parties)
	var btns := HFlowContainer.new()   # one row; wraps only on a narrow sheet
	btns.add_theme_constant_override("h_separation", 10)
	btns.add_theme_constant_override("v_separation", 10)
	if practice:
		_primary = UIKit.primary("Play again", Vector2(260, 92), 30)
		_primary.pressed.connect(func() -> void: App.rematch())
	elif session.is_host():
		var nxt := session.next_round_number()
		_primary = UIKit.primary("Play again" if series_over or final_only else "Next: round %d" % nxt, Vector2(260, 92), 30)
		_primary.pressed.connect(func() -> void: App.back_to_party())
	else:
		_primary = UIKit.primary("", Vector2(260, 92), 28)
		_primary.pressed.connect(_guest_primary)
	btns.add_child(_primary)
	if not final_only:
		var board_b := UIKit.quiet("Scoreboard", Vector2(160, 92))
		board_b.pressed.connect(_toggle_board)
		btns.add_child(board_b)
	var leave := UIKit.quiet("Menu" if practice else "Leave", Vector2(0, 92))
	leave.pressed.connect(func() -> void:
		if practice:
			App.goto_title()
		else:
			dialog("Leave this party?", [["Leave", func() -> void: App.leave_room()], ["Stay", Callable()]]))
	btns.add_child(leave)
	outer.add_child(btns)
	outer.add_child(_status)
	leave_btn = leave
	_fit_sheet.call_deferred(sc, v, btns)
	v.minimum_size_changed.connect(func() -> void: _fit_sheet.call_deferred(sc, v, btns))
	btns.resized.connect(func() -> void: _fit_sheet.call_deferred(sc, v, btns))
	_status.minimum_size_changed.connect(func() -> void: _fit_sheet.call_deferred(sc, v, btns))
	focus_first(_primary)
	if session and not practice:
		session.lobby_changed.connect(_refresh_actions)
		session.series_changed.connect(_refresh_actions)
	_refresh_actions()
	UIKit.appear(sheet, Vector2.ZERO, UIKit.T_SHEET)
	if not final_only:
		Sfx.play("cheer" if won else "pop")
	_open_at_top(sc)


func _my_row() -> Dictionary:
	var uid := Save.player_uid()
	var slot := session.local_slot if session else -1
	for r in results.get("players", []):
		if String(r.get("uid", "")) == uid and uid != "":
			return r
	for r in results.get("players", []):
		if int(r["slot"]) == slot:
			return r
	return {}


## Why the round ended, with the round's real numbers.
static func _why(r: Dictionary) -> String:
	var fin := int(r.get("finished", 0))
	var need := int(r.get("needed", 4))
	var t := int(r.get("round_time", 0))
	match int(r.get("outcome", 0)):
		TC.Outcome.RUNNERS_WIN:
			return "%d of %d runners needed made it home, %d:%02d into the round." % [fin, need, t / 60, t % 60]
		TC.Outcome.PATROL_WIN:
			return "Time ran out with %d of the %d runners needed home. The Night Watch held them off." % [fin, need]
		TC.Outcome.CANCELLED:
			return "The round was interrupted, so it doesn't count and pays nothing."
	return ""


func _rewards(v: VBoxContainer) -> void:
	var rw := UIKit.hbox(14)
	if bool(reward.get("away", false)):
		rw.add_child(UIKit.styled("You were away for most of this round, so it pays nothing.", "caption", UIKit.IVORY_MUTED))
	elif reward.is_empty() or int(reward.get("coins", 0)) == 0:
		rw.add_child(UIKit.styled("No rewards for this round.", "caption", UIKit.IVORY_MUTED))
	else:
		var coins := UIKit.label("+%d ¢" % int(reward.get("coins", 0)), 30, UIKit.AMBER)
		coins.add_theme_font_override("font", UIKit.font_num(800))
		rw.add_child(coins)
		var bits: Array[String] = []
		for line in reward.get("lines", []):
			bits.append("%s %+d" % [line[0], int(line[1])])
		var det := UIKit.styled(" · ".join(bits), "caption", UIKit.IVORY_MUTED)
		det.add_theme_font_size_override("font_size", 18)
		det.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		det.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		det.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rw.add_child(det)
	v.add_child(rw)
	if bool(reward.get("level_up", false)):
		v.add_child(UIKit.styled("Level up! You're now level %d" % int(reward.get("level", 1)), "label", UIKit.TEAL))


func _guest_primary() -> void:
	if session == null or session.local_slot < 0:
		return
	var e: Variant = session.roster[session.local_slot]
	var rdy := e != null and bool(e["ready"])
	if bool(session.series_view.get("finished", false)):
		App.show_lobby()
		return
	session.set_local_ready(not rdy)
	_refresh_actions()


## The summary is as tall as its content, up to what the screen leaves
## once the (never scrolling) actions are placed.
func _fit_sheet(sc: ScrollContainer, v: Control, btns: Control) -> void:
	if not is_instance_valid(sc):
		return
	var avail := get_viewport().get_visible_rect().size.y - 120.0 - btns.get_combined_minimum_size().y \
		- (_status.get_combined_minimum_size().y + 14.0 if _status.visible else 0.0) - 14.0
	sc.custom_minimum_size.y = clampf(v.get_combined_minimum_size().y, 0.0, maxf(160.0, avail))


## Guests: ready for the next round from here, or "Waiting for the host";
## the host sees who it is waiting for (nothing starts on its own).
func _refresh_actions() -> void:
	if not is_instance_valid(_primary) or session == null or session.mode == NetSession.Mode.OFFLINE:
		return
	_status.visible = true
	var over := bool(session.series_view.get("finished", false)) or final_only
	if session.is_host():
		if over:
			_status.text = "Play again takes everyone back to the party room with the same settings."
		else:
			_status.text = "Back to the party room · round %d starts when everyone's ready." % session.next_round_number()
		return
	var e: Variant = session.roster[session.local_slot] if session.local_slot >= 0 else null
	var rdy := e != null and bool(e["ready"])
	if over:
		_primary.text = "Back to the party room"
		_status.text = "Waiting for the host to start another series."
	else:
		_primary.text = "Not ready" if rdy else "Ready for round %d" % session.next_round_number()
		UIKit._apply(_primary, UIKit.SLATE_HI if rdy else UIKit.AMBER, UIKit.IVORY if rdy else UIKit.NAVY)
		_status.text = "Waiting for the host" if rdy else "Nothing starts until everyone's ready."


static func contribution(r: Dictionary) -> String:
	if r.is_empty():
		return "You watched this round."
	if int(r["role"]) == TC.Role.RUNNER:
		var t := "%d of 3 splashes" % int(r.get("stamps", 0))
		if bool(r.get("finished", false)):
			var ft := float(r.get("finish_time", 0.0))
			t += "  ·  home #%d at %d:%02d" % [int(r.get("finish_order", 0)), int(ft) / 60, int(ft) % 60]
		var c := int(r.get("times_captured", 0))
		t += "  ·  caught %d time%s" % [c, "" if c == 1 else "s"] if c > 0 else "  ·  never caught"
		return t
	var tags := int(r.get("captures", 0))
	var n := int(r.get("unique_captures", 0))
	return "%d tag%s  ·  %d different runner%s caught" % [tags, "" if tags == 1 else "s", n, "" if n == 1 else "s"]


## The friends leaderboard: humans by Round Wins, ties share a place.  Bots
## never appear.  `limit` > 0 shows only the top rows (plus you).
static func standings_table(view: Dictionary, my_uid: String, limit: int = 0) -> Control:
	var rows := PartySeries.leaderboard_of(view.get("standings", {}))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 6)
	if rows.is_empty():
		var l := UIKit.label("No completed rounds yet.", 18, UIKit.IVORY_MUTED)
		return l
	for h in ["", "Player", "Round Wins", "Rounds"]:
		grid.add_child(UIKit.label(h, 16, UIKit.IVORY_MUTED, true))
	var shown := 0
	for r in rows:
		var me := String(r["uid"]) == my_uid
		if limit > 0 and shown >= limit and not me:
			continue
		shown += 1
		var col := UIKit.AMBER if me else UIKit.IVORY
		var place := int(r["place"])
		var pl := UIKit.label(_ordinal(place), 18, UIKit.AMBER if place == 1 else UIKit.IVORY_MUTED, true)
		grid.add_child(pl)
		var name := String(r["name"]) + ("  (you)" if me else "")
		var nm := UIKit.label(name, 18, col, me)
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nm.custom_minimum_size = Vector2(190, 0)
		grid.add_child(nm)
		grid.add_child(UIKit.label(str(int(r["wins"])), 18, col, true))
		var played := "%d" % int(r["played"])
		if int(r["joined_round"]) > 1:
			played += " · joined round %d" % int(r["joined_round"])
		if int(r["partial"]) > 0:
			played += " · away %d" % int(r["partial"])
		grid.add_child(UIKit.label(played, 16, UIKit.IVORY_MUTED))
	return grid


static func _ordinal(n: int) -> String:
	match n:
		1: return "1st"
		2: return "2nd"
		3: return "3rd"
	return "%dth" % n


## Every completed round: who won and the role you played.
func _rounds_list(view: Dictionary) -> Control:
	var v := UIKit.vbox(4)
	var uid := Save.player_uid()
	for rd in view.get("rounds", []):
		var mine := ""
		for p in rd.get("players", []):
			if String(p.get("uid", "")) == uid:
				mine = "you were a runner" if int(p["role"]) == TC.Role.RUNNER else "you were Night Watch"
		var who := "Runners won" if int(rd["outcome"]) == TC.Outcome.RUNNERS_WIN else "Night Watch won"
		v.add_child(UIKit.label("Round %d: %s%s" % [int(rd["round"]), who, (" · " + mine) if mine != "" else ""], 17, UIKit.IVORY_MUTED))
	return v


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
	head.add_child(UIKit.label("This round", 24, UIKit.IVORY, true))
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
	var mine := _my_row()
	var rows: Array = results.get("players", []).duplicate()
	rows.sort_custom(func(a, b): return _board_key(a) < _board_key(b))
	var name_w := clampf(vs.x * 0.2, 170.0, 240.0)
	for r in rows:
		var me: bool = r == mine
		var col := UIKit.AMBER if me else UIKit.IVORY
		var nm := UIKit.label(String(r["name"]) + ("  · BOT" if bool(r["is_bot"]) else ""), 18, col, me)
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nm.custom_minimum_size = Vector2(name_w, 0)
		grid.add_child(nm)
		grid.add_child(UIKit.label("Runner" if int(r["role"]) == TC.Role.RUNNER else "Night Watch", 17, UIKit.TEAL if int(r["role"]) == TC.Role.RUNNER else UIKit.PATROL))
		grid.add_child(UIKit.label(contribution(r), 17, col))
	v.add_child(grid)
	add_child(_board)
	focus_first(close)
	UIKit.soft_focus.call_deferred(close)
	UIKit.appear(sheet, Vector2.ZERO, UIKit.T_FAST)


## Runners first, in the order they got home, then by splashes; then the
## Night Watch by different runners caught.
static func _board_key(r: Dictionary) -> Array:
	var fin := bool(r.get("finished", false))
	var order := int(r.get("finish_order", 0)) if fin else 99
	return [int(r["role"]), order, -int(r.get("stamps", 0)), -int(r.get("unique_captures", 0)), int(r["slot"])]


func _go_back() -> void:
	if _board and is_instance_valid(_board):
		_toggle_board()   # Back / B closes the scoreboard first
		return
	if session == null or session.mode == NetSession.Mode.OFFLINE:
		App.goto_title()
	else:
		App.show_lobby()
