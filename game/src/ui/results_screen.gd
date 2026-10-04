class_name ResultsScreen
extends Screen
## Round and series results (V6 redesign; replaces V4/V5's compact grid).
##
## After every round, in this order, all present at once (motion is a short
## fade that never holds anything back; none with Reduced Motion):
##   1. the outcome and its real reason ("4 of 4 runners needed made it home,
##      2:31 into the round")
##   2. a small celebration: the winning team's portraits (cached portraits,
##      no live 3D per card), people before bots, "You" ringed in gold
##   3. the round's standings, one team at a time and never combined:
##      Runners by home order (with times), then splashes, then fewer
##      catches; Night Watch by different runners tagged, then tags.  "You",
##      BOT and "away" (too much of the round missed: no Round Win) marked
##   4. rewards: coins collected and credited, the breakdown, Season XP
##      progress (RoundRewards: the wallet when present, else this device's
##      reward; remembered per round, so reopening never pays or shows twice)
##   5. the series so far (between rounds): Round Wins, ties share a place
## A cancelled round shows the cancellation, no standings and no rewards.
## After the series' last round the primary action is "Final standings":
## a podium (shared places share a step), every friend's Round Wins with
## shared places ("T1"), rounds played, late joins and away rounds, then the
## role tally and every round - and only then "Return to lobby".
## Actions never scroll and never wait for an animation: the primary
## (Play again / Next: round N / Ready for round N / Final standings /
## Return to lobby), Chat (party rounds) and Leave.  Nothing starts or
## ejects on its own: the host starts the next round only when everyone has
## tapped Ready, and a guest leaves the results only by choice.

var results: Dictionary
var reward: Dictionary
var session: NetSession
## show only the series' final standings (the host ended the series early)
var final_only := false
var page := "round"            # round | final
var view_data: Dictionary = {}
var _board: PanelContainer
var _primary: Button
var _status: Label
var leave_btn: Button
var chat_btn: Button
var _sc: ScrollContainer
var _v: VBoxContainer
var _btns: HFlowContainer


func build() -> void:
	Diag.context("results")
	if App.stage:
		App.stage.set_mode("home", false)
		App.sync_stage_local()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	TitleScreen.add_shades(self, 0.6, 0.0)
	page = "final" if final_only else "round"
	view_data = RoundRanking.round_view(results, Save.player_uid(), session.local_slot if session else -1)
	var me: Dictionary = view_data["me"]
	var won := not bool(view_data["cancelled"]) and not me.is_empty() and int(me["role"]) == int(view_data["winners"])
	if App.stage and not final_only:
		App.stage.emote(Save.player_uid(), 1 if won else 3, 3.5)

	var row := UIKit.hbox(0)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)
	row.add_child(UIKit.spacer_h())
	var sheet := UIKit.panel(Color(UIKit.SLATE, 0.95), UIKit.R_PANEL, 20)
	sheet.custom_minimum_size = Vector2(minf(720.0, get_viewport().get_visible_rect().size.x * 0.6), 0)
	sheet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sheet)
	# the summary scrolls by finger (UIKit.scroll_area); the actions never do
	var outer := UIKit.vbox(10)
	sheet.add_child(outer)
	_sc = UIKit.scroll_area()
	_sc.follow_focus = true
	outer.add_child(_sc)
	_v = UIKit.vbox(12)
	_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sc.add_child(_v)
	_status = UIKit.styled("", "caption", UIKit.IVORY_MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.visible = false
	_btns = HFlowContainer.new()   # one row; wraps only on a narrow sheet
	_btns.add_theme_constant_override("h_separation", 10)
	_btns.add_theme_constant_override("v_separation", 10)
	# (V7) actions one touch target tall (they were 92 units: the summary
	# above them showed two table rows on a 667x375 phone)
	var tm := UIKit.touch_min()
	_primary = UIKit.primary("", Vector2(260, tm), 26)
	_primary.pressed.connect(_on_primary)
	_btns.add_child(_primary)
	if _party():
		chat_btn = UIKit.icon_button("chat", "Chat")
		chat_btn.accessibility_name = "Chat with everyone"
		chat_btn.custom_minimum_size.y = tm
		chat_btn.pressed.connect(_open_chat)
		_btns.add_child(chat_btn)
	var leave := UIKit.quiet("Menu" if _practice() else "Leave", Vector2(0, tm))
	leave.pressed.connect(func() -> void:
		if _practice():
			App.goto_title()
		else:
			UIKit.v7_back_chooses(self, dialog("Leave this party?", [["Leave", func() -> void: App.leave_room()], ["Stay", Callable()]])))
	_btns.add_child(leave)
	leave_btn = leave
	outer.add_child(_btns)
	outer.add_child(_status)
	_build_page()
	_fit_sheet.call_deferred()
	_v.minimum_size_changed.connect(func() -> void: _fit_sheet.call_deferred())
	_btns.resized.connect(func() -> void: _fit_sheet.call_deferred())
	_status.minimum_size_changed.connect(func() -> void: _fit_sheet.call_deferred())
	focus_first(_primary)
	if _party():
		session.lobby_changed.connect(_refresh_actions)
		session.series_changed.connect(_refresh_actions)
	_refresh_actions()
	UIKit.appear(sheet, Vector2.ZERO, UIKit.T_SHEET)
	if not final_only:
		Sfx.play("cheer" if won else "pop")
	_open_at_top(_sc)


func _practice() -> bool:
	return session == null or session.mode == NetSession.Mode.OFFLINE


func _party() -> bool:
	return session != null and session.mode != NetSession.Mode.OFFLINE


func series_view() -> Dictionary:
	var view: Dictionary = session.series_view if session else {}
	if results.has("series") and results["series"] is Dictionary and not (results["series"] as Dictionary).is_empty():
		view = results["series"]
	return view


func series_over() -> bool:
	return _party() and (bool(series_view().get("finished", false)) or final_only)


# ---------------------------------------------------------------------------
# Pages
# ---------------------------------------------------------------------------
func _build_page() -> void:
	for c in _v.get_children():
		c.queue_free()
	if page == "final":
		_final_page()
	else:
		_round_page()
	_refresh_actions()


func _round_page() -> void:
	var d := view_data
	var practice := bool(results.get("practice", false)) or _practice()
	var head := UIKit.vbox(2)
	if not practice:
		head.add_child(UIKit.styled("Round %d of %d" % [int(results.get("round_index", 1)), int(results.get("rounds_total", 1))], "overline", UIKit.IVORY_MUTED))
	else:
		head.add_child(UIKit.styled("Practice with bots", "overline", UIKit.IVORY_MUTED))
	var oc := int(d["outcome"])
	var title := "Runners win!" if oc == TC.Outcome.RUNNERS_WIN else ("Night Watch wins!" if oc == TC.Outcome.PATROL_WIN else "Round cancelled")
	var tl := UIKit.styled(title, "display", UIKit.TEAL if oc == TC.Outcome.RUNNERS_WIN else (UIKit.PATROL if oc == TC.Outcome.PATROL_WIN else UIKit.IVORY))
	head.add_child(tl)
	var why := UIKit.styled(String(d["reason"]), "body", UIKit.IVORY_MUTED)
	why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(why)
	_v.add_child(head)
	if bool(d["cancelled"]):
		var note := UIKit.panel(Color(UIKit.NAVY, 0.5), UIKit.R_CARD, 18)
		var nl := UIKit.styled("No standings and no rewards for an interrupted round. It doesn't use up a round of the series.", "body", UIKit.IVORY)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_child(nl)
		_v.add_child(note)
		if not series_view().is_empty() and _party():
			_series_so_far()
		return
	_v.add_child(_celebration(d))
	_v.add_child(_team_table("Runners", d["runners"], TC.Role.RUNNER, int(d["winners"]) == TC.Role.RUNNER))
	_v.add_child(_team_table("Night Watch", d["watch"], TC.Role.PATROL, int(d["winners"]) == TC.Role.PATROL))
	_v.add_child(_rewards_card())
	# (after the last round the footer and the Final standings button say so)
	if _party() and not series_view().is_empty() and not series_over():
		_series_so_far()


func _final_page() -> void:
	var view := series_view()
	var head := UIKit.vbox(2)
	head.add_child(UIKit.styled("Series over" + (" · ended early" if bool(view.get("ended_early", false)) else ""), "overline", UIKit.IVORY_MUTED))
	head.add_child(UIKit.styled("Final standings", "display", UIKit.AMBER))
	var sub := UIKit.styled("Each winning team member earns a Round Win. Ties share a place.", "caption", UIKit.IVORY_MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(sub)
	_v.add_child(head)
	var rows := RoundRanking.series_rows(view, Save.player_uid())
	if rows.is_empty():
		_v.add_child(UIKit.styled("No completed rounds.", "body", UIKit.IVORY_MUTED))
		return
	_v.add_child(_podium(rows))
	_v.add_child(standings_table(view, Save.player_uid()))
	var tally := LobbyScreen._tally(view)
	var tl := UIKit.styled("By role: Runners won %d · Night Watch won %d (roles change between rounds)" % [tally[0], tally[1]], "caption", UIKit.IVORY_MUTED)
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_v.add_child(tl)
	_v.add_child(_rounds_list(view))


# ---------------------------------------------------------------------------
# Pieces
# ---------------------------------------------------------------------------
func _celebration(d: Dictionary) -> Control:
	var box := UIKit.vbox(8)
	var me: Dictionary = d["me"]
	var won := not me.is_empty() and int(me["role"]) == int(d["winners"])
	var cap := "Your team won" if won else ("Winning team" if me.is_empty() else "Winning team · your team lost this one")
	box.add_child(UIKit.styled(cap, "overline", UIKit.AMBER if won else UIKit.IVORY_MUTED))
	var strip := UIKit.hbox(12)
	for r in d["celebrate"]:
		strip.add_child(_portrait_card(r, int(d["winners"])))
	box.add_child(strip)
	return box


func _portrait_card(r: Dictionary, role: int) -> Control:
	var me := bool(r["me"])
	var p := UIKit.panel(Color(UIKit.SLATE_HI, 0.95) if me else Color(UIKit.NAVY, 0.45), UIKit.R_CARD, 10)
	if me:
		var sb := UIKit.box(Color(UIKit.SLATE_HI, 0.95), UIKit.R_CARD, 3, UIKit.AMBER, 10)
		p.add_theme_stylebox_override("panel", sb)
	var v := UIKit.vbox(2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var av := LobbyScreen.Avatar.new()
	av.custom_minimum_size = Vector2(62, 62)
	av.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	av.set_entry(r["cosmetic"], role, "results%d" % get_instance_id())
	v.add_child(av)
	var nm := UIKit.styled("You" if me else String(r["name"]), "label", UIKit.AMBER if me else UIKit.IVORY, HORIZONTAL_ALIGNMENT_CENTER)
	nm.custom_minimum_size = Vector2(124, 0)
	UIKit.fit_text(nm, [UIKit.T_LABEL, UIKit.T_CAPTION, 17])
	v.add_child(nm)
	var tag := "BOT" if bool(r["is_bot"]) else (_short_stat(r))
	v.add_child(UIKit.styled(tag, "caption", UIKit.IVORY_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	p.add_child(v)
	return p


static func _short_stat(r: Dictionary) -> String:
	if int(r["role"]) == TC.Role.RUNNER:
		if bool(r["finished"]):
			return "Home #%d" % int(r["finish_order"])
		return "%d/3 splashes" % int(r["stamps"])
	return "%d caught" % int(r["distinct"])


static func _clock(t: float) -> String:
	if t < 0.0:
		return "–"
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


## One team's standings: a header row and one row per player, never mixed
## with the other team's numbers.
func _team_table(title: String, rows: Array, role: int, winners: bool) -> Control:
	var box := UIKit.vbox(6)
	# the team's title and its own column names on one line
	var h := UIKit.hbox(10)
	var ic := Icons.IconRect.new("drop" if role == TC.Role.RUNNER else "whistle", UIKit.RUNNER if role == TC.Role.RUNNER else UIKit.PATROL, 24)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var tl := UIKit.styled(title + ("  ·  won" if winners else ""), "headline", UIKit.RUNNER if role == TC.Role.RUNNER else UIKit.PATROL)
	tl.add_theme_font_size_override("font_size", 23)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tl)
	var cols := ["Home", "Splashes", "Caught"] if role == TC.Role.RUNNER else ["Different", "Tags"]
	for c in cols:
		var cl := UIKit.styled(c, "overline", UIKit.IVORY_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
		cl.custom_minimum_size = Vector2(COL_W, 0)
		cl.size_flags_vertical = Control.SIZE_SHRINK_END
		h.add_child(cl)
	var tail := Control.new()
	tail.custom_minimum_size = Vector2(8, 0)
	h.add_child(tail)
	box.add_child(h)
	for r in rows:
		var vals: Array
		if role == TC.Role.RUNNER:
			vals = ["#%d · %s" % [int(r["finish_order"]), _clock(float(r["finish_time"]))] if bool(r["finished"]) else "–",
				"%d/3" % int(r["stamps"]), str(int(r["caught"]))]
		else:
			vals = [str(int(r["distinct"])), str(int(r["tags"]))]
		box.add_child(_player_row(r, role, vals))
	if rows.is_empty():
		box.add_child(UIKit.styled("Nobody on this team.", "caption", UIKit.IVORY_MUTED))
	return box


const COL_W := 118.0


func _cells(texts: Array, header: bool) -> Control:
	var h := UIKit.hbox(10)
	for i in texts.size():
		var l := UIKit.styled(String(texts[i]), "overline" if header else "num", UIKit.IVORY_MUTED, HORIZONTAL_ALIGNMENT_LEFT if i < 2 else HORIZONTAL_ALIGNMENT_RIGHT)
		if i == 0:
			l.custom_minimum_size = Vector2(48, 0)
		elif i == 1:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			l.custom_minimum_size = Vector2(COL_W, 0)
		h.add_child(l)
	return h


func _player_row(r: Dictionary, role: int, vals: Array) -> Control:
	var me := bool(r["me"])
	var p := PanelContainer.new()
	var sb := UIKit.box(Color(UIKit.SLATE_HI, 0.9) if me else Color(UIKit.NAVY, 0.4), UIKit.R_SMALL, 2 if me else 0, UIKit.AMBER, 8)
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(0, 56)
	var h := UIKit.hbox(10)
	var av := LobbyScreen.Avatar.new()
	av.custom_minimum_size = Vector2(48, 48)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	av.set_entry(r["cosmetic"], role, "row%d_%d" % [get_instance_id(), int(r["slot"])])
	h.add_child(av)
	var nv := UIKit.vbox(0)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.alignment = BoxContainer.ALIGNMENT_CENTER
	var nm := UIKit.styled(String(r["name"]), "label", UIKit.AMBER if me else UIKit.IVORY)
	nm.custom_minimum_size = Vector2(120, 0)
	UIKit.fit_text(nm, [UIKit.T_LABEL, UIKit.T_CAPTION, 17])
	nv.add_child(nm)
	var tags: Array[String] = []
	if me:
		tags.append("You")
	if bool(r["is_bot"]):
		tags.append("BOT")
	if bool(r["away"]):
		tags.append("away (no Round Win)")
	if not tags.is_empty():
		var tg := UIKit.styled(" · ".join(tags), "caption", UIKit.IVORY_MUTED)
		tg.add_theme_font_size_override("font_size", 17)
		nv.add_child(tg)
	h.add_child(nv)
	for val in vals:
		var l := UIKit.styled(String(val), "num", UIKit.IVORY, HORIZONTAL_ALIGNMENT_RIGHT)
		l.custom_minimum_size = Vector2(COL_W, 0)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(l)
	p.add_child(h)
	p.accessibility_name = "%s%s: %s" % [String(r["name"]), " (you)" if me else "", String(r["line"])]
	return p


func _rewards_card() -> Control:
	var p := UIKit.panel(Color(UIKit.NAVY, 0.45), UIKit.R_CARD, 14)
	var mid := String(results.get("match_id", ""))
	_fill_rewards(p, mid)
	# the wallet settles the round with the game service: the card follows
	Wallet.round_updated.connect(func(m: String) -> void:
		if m == mid and is_instance_valid(p):
			_fill_rewards(p, mid), CONNECT_REFERENCE_COUNTED)
	return p


## Coins and Season XP from the Wallet (docs/ECONOMY.md §9): added amounts
## only once the service has settled the round; while it is pending, what
## the round is expected to pay, said to be not yet added; otherwise the
## wallet's own sentence (practice, no service, not eligible, …).
func _fill_rewards(p: Control, mid: String) -> void:
	for c in p.get_children():
		c.queue_free()
	var s := RoundRewards.summary(mid, reward)
	var v := UIKit.vbox(4)
	p.add_child(v)
	v.add_child(UIKit.styled("Rewards", "overline", UIKit.IVORY_MUTED))
	if s.is_empty():
		v.add_child(UIKit.styled("No rewards for this round.", "body", UIKit.IVORY_MUTED))
		return
	var top := UIKit.hbox(18)
	if int(s["coins_collected"]) > 0:
		top.add_child(_big_number("%d" % int(s["coins_collected"]), "picked up"))
	if bool(s["settled"]):
		top.add_child(_big_number("+%s" % Catalogue.format_coins(int(s["coins"])), "Coins added"))
		if int(s["season_xp"]) > 0:
			top.add_child(_big_number("+%d" % int(s["season_xp"]), "Season XP"))
	var msg := String(s["message"])
	if bool(s["pending"]):
		msg += " Expected: +%s Coins · +%d Season XP (not added yet)." % [Catalogue.format_coins(int(s["coins_projected"])), int(s["season_xp_projected"])]
	elif bool(s["away"]) and msg == "":
		msg = "You were away for most of this round, so it pays nothing."
	if msg == "" and top.get_child_count() == 0:
		msg = "No rewards for this round."
	if msg != "":
		var ml := UIKit.styled(msg, "caption", UIKit.IVORY if bool(s["settled"]) else UIKit.IVORY_MUTED)
		ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ml.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ml.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(ml)
	v.add_child(top)
	if bool(s["settled"]) or bool(s["pending"]):
		var bits: Array[String] = []
		for line in (s["lines"] as Array) + (s["season_lines"] as Array):
			bits.append("%s %+d" % [line[0], int(line[1])])
		if not bits.is_empty():
			var det := UIKit.styled(" · ".join(bits), "caption", UIKit.IVORY_MUTED)
			det.add_theme_font_size_override("font_size", 18)
			det.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(det)
	if bool(s["settled"]) and int(s["season_xp"]) > 0:
		var tier := int(s["tier_after"])
		v.add_child(UIKit.styled("Season tier %d%s" % [tier, "  ·  tier up!" if tier > int(s["tier_before"]) else ""], "label", UIKit.TEAL))
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.step = 0.001
		bar.value = float(s["frac_after"])
		bar.custom_minimum_size = Vector2(0, 14)
		v.add_child(bar)
	if bool(s["level_up"]):
		v.add_child(UIKit.styled("Level up! You're now level %d" % int(s["level"]), "label", UIKit.TEAL))


func _big_number(n: String, label_text: String) -> Control:
	var v := UIKit.vbox(0)
	var l := UIKit.label(n, 32, UIKit.AMBER)
	l.add_theme_font_override("font", UIKit.font_num(800))
	v.add_child(l)
	v.add_child(UIKit.styled(label_text, "caption", UIKit.IVORY_MUTED))
	return v


func _series_so_far() -> void:
	var view := series_view()
	var p := UIKit.panel(Color(UIKit.NAVY, 0.45), UIKit.R_CARD, 16)
	var sv := UIKit.vbox(8)
	var tally := LobbyScreen._tally(view)
	sv.add_child(UIKit.styled("Series so far", "overline", UIKit.IVORY_MUTED))
	var note := UIKit.styled("Runners %d – %d Night Watch by role. Your Round Wins are below." % [tally[0], tally[1]], "caption", UIKit.IVORY_MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sv.add_child(note)
	sv.add_child(standings_table(view, Save.player_uid(), 3))
	p.add_child(sv)
	_v.add_child(p)


func _podium(rows: Array) -> Control:
	var steps := RoundRanking.podium(rows)
	var h := UIKit.hbox(14)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	var heights := {1: 0.0, 2: 16.0, 3: 28.0}
	for st in steps:
		var col := UIKit.vbox(6)
		col.alignment = BoxContainer.ALIGNMENT_END
		var pad := Control.new()
		pad.custom_minimum_size = Vector2(0, float(heights.get(int(st["place"]), 44.0)))
		col.add_child(pad)
		var faces := UIKit.hbox(6)
		faces.alignment = BoxContainer.ALIGNMENT_CENTER
		for r in (st["rows"] as Array).slice(0, 3):
			var av := LobbyScreen.Avatar.new()
			av.custom_minimum_size = Vector2(56, 56)
			var cos: Dictionary = _cosmetic_of(String(r["uid"]))
			av.set_entry(cos, TC.Role.RUNNER, "pod%d_%s" % [get_instance_id(), String(r["uid"])])
			faces.add_child(av)
		col.add_child(faces)
		var names: Array[String] = []
		for r in st["rows"]:
			names.append("You" if bool(r["me"]) else String(r["name"]))
		var nl := UIKit.styled(", ".join(names), "label", UIKit.IVORY, HORIZONTAL_ALIGNMENT_CENTER)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nl.custom_minimum_size = Vector2(170, 0)
		col.add_child(nl)
		var step := UIKit.panel(Color(UIKit.AMBER if int(st["place"]) == 1 else UIKit.SLATE_HI, 0.92), UIKit.R_SMALL, 8)
		var sl := UIKit.styled(("Tied " if (st["rows"] as Array).size() > 1 else "") + RoundRanking.ordinal(int(st["place"])) + " · %d %s" % [int(st["rows"][0]["wins"]), "win" if int(st["rows"][0]["wins"]) == 1 else "wins"],
			"label", UIKit.NAVY if int(st["place"]) == 1 else UIKit.IVORY, HORIZONTAL_ALIGNMENT_CENTER)
		step.add_child(sl)
		col.add_child(step)
		h.add_child(col)
	return h


## The look of a series player for the podium (from the round results or
## the roster; a plain look otherwise).
func _cosmetic_of(uid: String) -> Dictionary:
	for r in results.get("players", []):
		if String(r.get("uid", "")) == uid and r.get("cosmetic") is Dictionary:
			return r["cosmetic"]
	if session != null:
		for e in session.roster:
			if e != null and String(e["uid"]) == uid:
				return e["cosmetic"]
	if uid == Save.player_uid():
		return Save.data["cosmetic"]
	return Cosmetics.DEFAULT


## The friends' standings: place (shared places "T1", no name order), name,
## Round Wins, and rounds played with late joins and away rounds.  Bots
## never appear.  `limit` > 0 shows only the top rows (plus you).
static func standings_table(view: Dictionary, my_uid: String, limit: int = 0) -> Control:
	var rows := RoundRanking.series_rows(view, my_uid)
	var box := UIKit.vbox(6)
	if rows.is_empty():
		box.add_child(UIKit.styled("No completed rounds yet.", "caption", UIKit.IVORY_MUTED))
		return box
	var hdr := UIKit.hbox(10)
	for spec in [["Place", 70.0, HORIZONTAL_ALIGNMENT_LEFT], ["Player", -1.0, HORIZONTAL_ALIGNMENT_LEFT], ["Round Wins", 130.0, HORIZONTAL_ALIGNMENT_RIGHT],
			["Played", 170.0, HORIZONTAL_ALIGNMENT_RIGHT]]:
		var l := UIKit.styled(String(spec[0]), "overline", UIKit.IVORY_MUTED, int(spec[2]))
		if float(spec[1]) > 0.0:
			l.custom_minimum_size = Vector2(float(spec[1]), 0)
		else:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hdr.add_child(l)
	box.add_child(hdr)
	var shown := 0
	for r in rows:
		var me := bool(r["me"])
		if limit > 0 and shown >= limit and not me:
			continue
		shown += 1
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", UIKit.box(Color(UIKit.SLATE_HI, 0.9) if me else Color(UIKit.NAVY, 0.35), UIKit.R_SMALL, 2 if me else 0, UIKit.AMBER, 8))
		p.custom_minimum_size = Vector2(0, 56)
		var h := UIKit.hbox(10)
		var place := UIKit.styled(String(r["label"]), "num", UIKit.AMBER if int(r["place"]) == 1 else UIKit.IVORY_MUTED)
		place.custom_minimum_size = Vector2(70, 0)
		place.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(place)
		var nv := UIKit.vbox(0)
		nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nm := UIKit.styled(String(r["name"]), "label", UIKit.AMBER if me else UIKit.IVORY)
		nm.custom_minimum_size = Vector2(120, 0)
		UIKit.fit_text(nm, [UIKit.T_LABEL, UIKit.T_CAPTION, 17])
		nv.add_child(nm)
		var tg: Array[String] = []
		if me:
			tg.append("You")
		if bool(r["tied"]):
			tg.append("tied")
		if not tg.is_empty():
			var tl := UIKit.styled(" · ".join(tg), "caption", UIKit.IVORY_MUTED)
			tl.add_theme_font_size_override("font_size", 17)
			nv.add_child(tl)
		h.add_child(nv)
		var w := UIKit.label(str(int(r["wins"])), 28, UIKit.AMBER if me else UIKit.IVORY, false, HORIZONTAL_ALIGNMENT_RIGHT)
		w.add_theme_font_override("font", UIKit.font_num(800))
		w.custom_minimum_size = Vector2(130, 0)
		w.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(w)
		var played := "%d round%s" % [int(r["played"]), "" if int(r["played"]) == 1 else "s"]
		var extra: Array[String] = []
		if int(r["joined_round"]) > 1:
			extra.append("joined round %d" % int(r["joined_round"]))
		if int(r["partial"]) > 0:
			extra.append("away %d" % int(r["partial"]))
		var pv := UIKit.vbox(0)
		pv.custom_minimum_size = Vector2(170, 0)
		pv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pv.add_child(UIKit.styled(played, "num", UIKit.IVORY_MUTED, HORIZONTAL_ALIGNMENT_RIGHT))
		if not extra.is_empty():
			var ex := UIKit.styled(" · ".join(extra), "caption", UIKit.IVORY_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
			ex.add_theme_font_size_override("font_size", 16)
			pv.add_child(ex)
		h.add_child(pv)
		p.add_child(h)
		p.accessibility_name = "%s, %s, %d Round %s, %s" % [String(r["label"]), String(r["name"]), int(r["wins"]), "Win" if int(r["wins"]) == 1 else "Wins", played]
		box.add_child(p)
	return box


static func _ordinal(n: int) -> String:
	return RoundRanking.ordinal(n)


## Every completed round: who won and the role you played.
func _rounds_list(view: Dictionary) -> Control:
	var v := UIKit.vbox(4)
	v.add_child(UIKit.styled("Rounds", "overline", UIKit.IVORY_MUTED))
	var uid := Save.player_uid()
	for rd in view.get("rounds", []):
		var mine := ""
		for p in rd.get("players", []):
			if String(p.get("uid", "")) == uid:
				mine = "you were a runner" if int(p["role"]) == TC.Role.RUNNER else "you were Night Watch"
		var who := "Runners won" if int(rd["outcome"]) == TC.Outcome.RUNNERS_WIN else "Night Watch won"
		v.add_child(UIKit.label("Round %d: %s%s" % [int(rd["round"]), who, (" · " + mine) if mine != "" else ""], 18, UIKit.IVORY_MUTED))
	return v


## (V5 API) How one player did, in words.
static func contribution(r: Dictionary) -> String:
	if r.is_empty():
		return "You watched this round."
	if int(r.get("role", 0)) == TC.Role.RUNNER:
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


static func _why(r: Dictionary) -> String:
	return RoundRanking.reason(r)


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------
func _on_primary() -> void:
	if _practice():
		App.rematch()
		return
	if series_over() and page == "round" and not bool(view_data["cancelled"]):
		page = "final"
		_build_page()
		_open_at_top(_sc)
		return
	if session.is_host():
		App.back_to_party()
		return
	if series_over() or bool(view_data["cancelled"]):
		App.show_lobby()
		return
	_guest_ready()


func _guest_ready() -> void:
	if session == null or session.local_slot < 0:
		return
	var e: Variant = session.roster[session.local_slot]
	var rdy := e != null and bool(e["ready"])
	session.set_local_ready(not rdy)
	_refresh_actions()


func _open_chat() -> void:
	if has_modal() or not _party():
		return
	var d := ChatDrawer.open(self, session, "results")
	d.closed.connect(_refresh_actions)


## The summary is as tall as its content, up to what the screen leaves
## once the (never scrolling) actions are placed.
func _fit_sheet() -> void:
	if not is_instance_valid(_sc):
		return
	# (V7) what the screen really leaves: its safe margins and the sheet's
	# own padding (V6 reserved a fixed 120 units, ~40 too many on an SE)
	var sheet := _sc.get_parent().get_parent() as Control
	var pad := 24.0
	if sheet is PanelContainer:
		var sb := (sheet as PanelContainer).get_theme_stylebox("panel")
		pad = sb.get_margin(SIDE_TOP) + sb.get_margin(SIDE_BOTTOM)
	var avail := get_viewport().get_visible_rect().size.y - float(margin.get_theme_constant("margin_top") + margin.get_theme_constant("margin_bottom")) \
		- pad - _btns.get_combined_minimum_size().y - (_status.get_combined_minimum_size().y + 10.0 if _status.visible else 0.0) - 10.0 - 2.0
	_sc.custom_minimum_size.y = clampf(_v.get_combined_minimum_size().y, 0.0, maxf(160.0, avail))


## Labels and waiting states; nothing starts on its own.
func _refresh_actions() -> void:
	if not is_instance_valid(_primary):
		return
	if is_instance_valid(chat_btn):
		var n: int = session.social.chat.unread
		UIKit.face_of(chat_btn).caption = "Chat · %d" % n if n > 0 else "Chat"
		UIKit.face_of(chat_btn).queue_redraw()
	if _practice():
		_primary.text = "Play again"
		return
	var over := series_over()
	var cancelled := bool(view_data["cancelled"]) and not final_only
	_status.visible = true
	if over and page == "round" and not cancelled:
		_primary.text = "Final standings"
		UIKit._apply(_primary, UIKit.AMBER, UIKit.NAVY)
		_status.text = "That was the last round. Final standings next."
		return
	if session.is_host():
		if over:
			_primary.text = "Return to lobby"
			_status.text = "Everyone returns to the party room. A new series keeps these settings."
		else:
			_primary.text = "Next: round %d" % session.next_round_number()
			_status.text = "Back to the party room · round %d starts when everyone's ready." % session.next_round_number()
		UIKit._apply(_primary, UIKit.AMBER, UIKit.NAVY)
		return
	if over or cancelled:
		_primary.text = "Return to lobby"
		UIKit._apply(_primary, UIKit.AMBER, UIKit.NAVY)
		_status.text = "Waiting for the host to start another round." if cancelled else "Waiting for the host to start another series."
		return
	var e: Variant = session.roster[session.local_slot] if session.local_slot >= 0 else null
	var rdy := e != null and bool(e["ready"])
	_primary.text = "Not ready" if rdy else "Ready for round %d" % session.next_round_number()
	UIKit._apply(_primary, UIKit.SLATE_HI if rdy else UIKit.AMBER, UIKit.IVORY if rdy else UIKit.NAVY)
	_status.text = "Waiting for the host" if rdy else "Nothing starts until everyone's ready."


## The full round scoreboard in a centred sheet (both teams, full width).
func _toggle_board() -> void:
	if _board and is_instance_valid(_board):
		_board.queue_free()
		_board = null
		return
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
	var vs := get_viewport().get_visible_rect().size
	var sheet := UIKit.panel(Color(UIKit.SLATE_HI, 0.99), UIKit.R_PANEL, 22)
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	sheet.custom_minimum_size = Vector2(minf(900.0, vs.x * 0.8), 0)
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
	var sc := UIKit.scroll_area()
	sc.custom_minimum_size = Vector2(0, minf(vs.y * 0.62, 640.0))
	var inner := UIKit.vbox(14)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(_team_table("Runners", view_data["runners"], TC.Role.RUNNER, int(view_data["winners"]) == TC.Role.RUNNER))
	inner.add_child(_team_table("Night Watch", view_data["watch"], TC.Role.PATROL, int(view_data["winners"]) == TC.Role.PATROL))
	sc.add_child(inner)
	v.add_child(sc)
	add_child(_board)
	focus_first(close)
	UIKit.soft_focus.call_deferred(close)
	UIKit.appear(sheet, Vector2.ZERO, UIKit.T_FAST)


func _go_back() -> void:
	if _board and is_instance_valid(_board):
		_toggle_board()   # Back / B closes the scoreboard first
		return
	if page == "final" and not final_only:
		page = "round"   # Back from the final standings returns to the round
		_build_page()
		return
	if _practice():
		App.goto_title()
	else:
		App.show_lobby()
