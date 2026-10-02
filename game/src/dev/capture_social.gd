extends Node
## Development-only evidence for the V6 social work (created by capture.gd
## for --capture=social_*; src/dev/ is excluded from iOS exports).  Shots go
## through capture.gd's snap() (PNG + render report).  Scenarios:
##   social_hub      host of a LAN dev room (--capture-players=N): the menu
##                   composition, then Walk around (the host's stick is
##                   driven by this script), members walking (their
##                   headless clients run social_bot), Quick Chat bubbles,
##                   the chat drawer, a player card and the report sheet
##                   (the service is off in these runs: it says reports are
##                   unavailable and sends nothing)
##   social_bot      a headless client: walks a loop around its mark and
##                   sends a Quick Chat phrase now and then
##   social_names    the name sheet refusing a name, its suggestions, and a
##                   suggestion tapped
##   social_results  a recorded bot round (--capture-results=path) shown as
##                   round 3 of a friend series (two bot seats relabelled as
##                   friends, earlier rounds recorded through PartySeries):
##                   the round page, scrolled, then Final standings, scrolled
## Layout and behaviour evidence on desktop Linux (llvmpipe): not frame
## rate, pacing or device input.

var cap: Node
var scenario := ""
var _t := 0.0
var _step := 0
var _at := 0.0
var _phrase := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _snap(n: String) -> void:
	cap.call("snap", n)


func _next(delay: float) -> void:
	_step += 1
	_at = _t + delay


func _process(delta: float) -> void:
	_t += delta
	match scenario:
		"social_hub":
			_hub()
		"social_bot":
			_bot()
		"social_names":
			_names()
		"social_results":
			_results()


func _lobby() -> LobbyScreen:
	return App.screen as LobbyScreen if App.screen is LobbyScreen else null


func _hub() -> void:
	var s: NetSession = App.session
	var want := int(cap.get("want_players"))
	if s == null or _t < _at:
		return
	var l := _lobby()
	# (a shot is taken a frame later: every shot has a step of its own, and
	# the next action waits for it)
	match _step:
		0:
			if s.human_count() >= want and l != null:
				_next(5.0)
		1:
			_snap("hub_%dp_menu" % want)
			_next(1.0)
		2:
			if want > 1:
				l._set_walk(true)
			_next(0.5)
		3, 4, 5, 6, 7, 8:
			if want <= 1:
				_step = 10
				return
			# the host walks a short loop with its stick
			var dirs := [Vector2(0, 1), Vector2(1, 0.4), Vector2(0.3, -1), Vector2(-1, -0.2), Vector2(-0.4, 1), Vector2(0.6, 0.2)]
			if is_instance_valid(l) and l.hub:
				l.hub.stick = dirs[_step - 3] * 0.8
			_next(1.4)
		9:
			if is_instance_valid(l) and l.hub:
				l.hub.stick = Vector2.ZERO
			_snap("hub_%dp_walk" % want)
			_next(1.0)
		10:
			s.social.chat.send_quick(1, QuickChat.Channel.PARTY)
			_next(2.0)
		11:
			_snap("hub_%dp_bubbles" % want)
			_next(1.0)
		12:
			if is_instance_valid(l):
				l._open_chat()
			_next(2.0)
		13:
			_snap("hub_%dp_chat" % want)
			_next(1.0)
		14:
			for d in l.find_children("*", "ChatDrawer", true, false):
				(d as ChatDrawer).close()
			if want > 1 and is_instance_valid(l):
				l._set_walk(false)
			_next(2.5)
		15:
			var c: Variant = null
			for cell in l.cells:
				if cell.visible and cell.slot > 0 and s.roster[cell.slot] != null and not bool(s.roster[cell.slot]["is_bot"]):
					c = cell
					break
			if c == null:
				_step = 20
				return
			l._player_popover(c.slot, c)
			_next(1.5)
		16:
			_snap("hub_%dp_player_card" % want)
			_next(1.0)
		17:
			l.close_popover()
			for i in range(1, 8):
				if s.roster[i] != null and not bool(s.roster[i]["is_bot"]):
					l._report(s.roster[i])
					break
			_next(1.5)
		18:
			_snap("hub_%dp_report" % want)
			_next(1.0)
		19:
			_step = 20
		20:
			get_tree().quit()


func _bot() -> void:
	var s: NetSession = App.session
	if s == null or s.local_slot < 0 or s.phase != TC.Phase.LOBBY:
		return
	var mark: Vector3 = DormStage.MARKS[clampi(s.local_slot, 0, 7)]
	# a walk loop around the mark, a pause on the mark every so often
	var cyc := fmod(_t + float(s.local_slot) * 1.7, 14.0)
	if cyc < 10.0:
		var a := cyc / 10.0 * TAU
		var p := Vector2(mark.x + sin(a) * 1.1, mark.z - 0.6 + cos(a) * 0.9)
		var v := Vector2(cos(a), -sin(a))
		s.social.hub.set_local(HubSync.MODE_WALK, p, atan2(-v.x, -v.y), 1.3)
	else:
		s.social.hub.set_local(HubSync.MODE_MARK, Vector2(mark.x, mark.z), 0.0, 0.0)
	if _t > 6.0 + float(s.local_slot) and _t - _at > 9.0:
		_at = _t
		var ids := QuickChat.offered(QuickChat.Channel.PARTY)
		s.social.chat.send_quick(int(ids[(_phrase + s.local_slot) % ids.size()]), QuickChat.Channel.PARTY)
		_phrase += 1


func _sheet() -> NameSheet:
	var f := App.screen.find_children("*", "NameSheet", true, false)
	return f[0] if not f.is_empty() else null


func _type(text: String) -> void:
	var sheet := _sheet()
	sheet.field.text = text
	sheet._on_text(text)


func _names() -> void:
	if _t < _at:
		return
	match _step:
		0:
			if _t > 5.0 and App.screen is Screen:
				NameSheet.ask(App.screen as Screen, true)
				_next(1.5)
		1:
			_type("Tr1fecta Admin")
			_next(1.5)
		2:
			_snap("name_rejected_impersonation")
			_next(1.0)
		3:
			_type("add me on snap")
			_next(1.5)
		4:
			_snap("name_rejected_contact")
			_next(1.0)
		5:
			for b in _sheet().sugg_row.get_children():
				if not b.is_queued_for_deletion():
					(b as Button).pressed.emit()
					break
			_next(1.5)
		6:
			_snap("name_suggestion_tapped")
			_next(1.0)
		7:
			_type("Bob Builder")
			_next(1.5)
		8:
			_snap("name_harmless_lookalike_ok")
			_next(1.0)
		9:
			get_tree().quit()


func _results() -> void:
	if _t < _at:
		return
	match _step:
		0:
			if _t > 3.0:
				_show_series()
				_next(3.0)
		1:
			_snap("results_round")
			_next(1.0)
		2:
			_scroll(100000)
			_next(1.0)
		3:
			_snap("results_round_scrolled")
			_next(1.0)
		4:
			(App.screen as ResultsScreen)._on_primary()
			_next(2.0)
		5:
			_snap("results_final")
			_next(1.0)
		6:
			_scroll(100000)
			_next(1.0)
		7:
			_snap("results_final_scrolled")
			_next(1.0)
		8:
			get_tree().quit()


func _scroll(y: int) -> void:
	for sc in App.screen.find_children("*", "ScrollContainer", true, false):
		(sc as ScrollContainer).scroll_vertical = y


## The recorded round as the last round of a three-round friend series.
func _show_series() -> void:
	var d: Dictionary = str_to_var(FileAccess.get_file_as_string(String(cap.get("results_path"))))
	var res: Dictionary = (d["results"] as Dictionary).duplicate(true)
	var local := int(d["local_slot"])
	var me := Save.player_uid()
	var friends := {TC.Role.RUNNER: ["Snug Puffin 37", "Moonlit Koala"], TC.Role.PATROL: ["Cozy Walrus"]}
	var rows: Array = res.get("players", [])
	for r in rows:
		var row: Dictionary = r
		var role := int(row.get("role", TC.Role.RUNNER))
		if int(row.get("slot", -1)) == local:
			row["uid"] = me
			row["name"] = Save.player_name()
		elif bool(row.get("is_bot", false)) and not (friends[role] as Array).is_empty():
			row["name"] = (friends[role] as Array).pop_front()
			row["uid"] = "friend-" + String(row["name"]).replace(" ", "")
			row["is_bot"] = false
		elif String(row.get("uid", "")) == "":
			row["uid"] = "bot-%d" % int(row.get("slot", 0))
	var ps := PartySeries.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	ps.start({"watch": 2, "rounds": 3}, rng)
	for k in 2:
		var earlier: Array = []
		for r in rows:
			var e: Dictionary = (r as Dictionary).duplicate()
			if not bool(e.get("is_bot", false)):
				e["role"] = TC.Role.PATROL if (k + int(e.get("slot", 0))) % 3 == 0 else TC.Role.RUNNER
			earlier.append(e)
		ps.record_round({"match_id": "social-r%d" % (k + 1), "outcome": TC.Outcome.RUNNERS_WIN if k == 0 else TC.Outcome.PATROL_WIN,
			"round_time": 200.0, "players": earlier})
	res["match_id"] = "social-r3"
	ps.record_round(res)
	res["series"] = ps.to_dict()
	res["round_index"] = 3
	res["rounds_total"] = 3
	res["practice"] = false
	var s := NetSession.new()
	s.mode = NetSession.Mode.HOST
	s.local_slot = local
	s.series_view = res["series"]
	add_child(s)
	App._ensure_background()
	var rsc := ResultsScreen.new()
	rsc.results = res
	rsc.reward = d["reward"]
	rsc.session = s
	App._show(rsc)
