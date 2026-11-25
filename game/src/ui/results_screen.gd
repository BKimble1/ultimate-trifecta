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
## (Play again / Final standings / Back to lobby), Chat (party rounds) and
## Leave.
## (build 34) Between the rounds of a series (a host that offers it,
## Protocol.CAP_SERIES) nobody goes back to the lobby or readies up, like a
## kart racer's cup: this round's outcome in a line, your part and your
## Coins / XP, the series standings, then a 5-second countdown (the host's,
## the same on every device) and the next round starts by itself.  The only
## action is Leave match (a guest sits the rest of the match out in the
## party lobby; the host or the leader ends it for everyone).  After the
## last round: Final standings, then Back to lobby.  An older host keeps the
## build 33 flow (Ready for round N).

var results: Dictionary
var reward: Dictionary
## (2.2) this round's run stats and Season Points (Rankings.record)
var rank: Dictionary = {}
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
## (build 34) the countdown to the next round of a series
var countdown: CountdownRing
var _last_tick := -1


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
	var sheet := UIKit.panel(Color(UIKit.SLATE, 0.95), UIKit.R_PANEL, 26)
	sheet.custom_minimum_size = Vector2(minf(720.0, get_viewport().get_visible_rect().size.x * 0.6), 0)
	sheet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sheet)
	# (2.2 build 16) the runner stands in the middle of the space left of the
	# panel (it stood off to its right, half behind it)
	var centre := func() -> void:
		if App.stage and is_instance_valid(App.stage) and sheet.is_inside_tree():
			var vw := get_viewport().get_visible_rect().size.x
			App.stage.set_home_x(sheet.get_global_rect().position.x * 0.5 / maxf(1.0, vw))
	sheet.item_rect_changed.connect(centre)
	centre.call_deferred()
	tree_exiting.connect(func() -> void:
		if App.stage and is_instance_valid(App.stage):
			App.stage.set_home_x(-1.0))
	# the summary scrolls by finger (UIKit.scroll_area); the actions never do
	var outer := UIKit.vbox(14)
	sheet.add_child(outer)
	_sc = UIKit.scroll_area()
	_sc.follow_focus = true
	outer.add_child(_sc)
	_v = UIKit.vbox(16)
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
		elif between_rounds():
			_ask_leave_match()
		else:
			UIKit.v7_back_chooses(self, dialog("Leave this party?", [["Leave", func() -> void: App.leave_room()], ["Stay", Callable()]])))
	_btns.add_child(leave)
	leave_btn = leave
	countdown = CountdownRing.new()
	countdown.name = "NextRound"
	countdown.visible = false
	outer.add_child(countdown)
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
		session.series_changed.connect(_on_series_changed)
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


## (build 34) Between two rounds of a series the host plays on by itself:
## the countdown, no lobby, no Ready.
func between_rounds() -> bool:
	return _party() and not final_only and session.series_flow() and not series_over() \
		and not bool(view_data.get("cancelled", false)) and not series_view().is_empty() \
		and int(results.get("rounds_total", 1)) > 1


## (build 34) The match was ended (the host or the leader left it) while we
## were between its rounds: everyone goes back to the party lobby.
func _on_series_changed() -> void:
	if not is_inside_tree() or final_only or not session.series_flow() or page == "final":
		return
	var v := session.series_view
	if bool(v.get("finished", false)) and bool(v.get("ended_early", false)) and int(results.get("round_index", 1)) < int(results.get("rounds_total", 1)):
		if session.is_host():
			App.back_to_party()
		else:
			App.show_lobby()
		if App.screen is Control:
			UIKit.toast(App.screen as Control, "Match ended. Back in the party.", 3.0)


func _process(_delta: float) -> void:
	if not is_instance_valid(countdown):
		return
	var on := between_rounds()
	var left := session.next_round_in() if on else -1.0
	# the results first (a few seconds), then the 5-second countdown
	var show := on and left >= 0.0 and left <= NetSession.NEXT_ROUND_COUNTDOWN_S + 0.05
	if show != countdown.visible:
		countdown.visible = show
		_fit_sheet.call_deferred()
	if not show:
		return
	var n := int(ceil(left))
	countdown.set_left(left, NetSession.NEXT_ROUND_COUNTDOWN_S, int(results.get("round_index", 1)) + 1)
	if n != _last_tick:
		_last_tick = n
		if n > 0:
			Sfx.play("count")


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
	# V8: the page arrives in reading order (title, celebration, teams,
	# rewards), 50 ms apart; buttons and rows are live at once
	var parts: Array = []
	for c in _v.get_children():
		if not c.is_queued_for_deletion():
			parts.append(c)
	Motion.stagger(parts)


## Pass 8 hierarchy, top to bottom (the actions sit below, outside the
## scroll, live at once):
##   1. your team won / lost and why ("4 runners home", "Time expired: 3/4
##      home"); a cancelled round says it doesn't count (never a loss)
##   2. your contribution (home order and time or waters; Night Watch:
##      tags and different runners)
##   3. the series standing ("Series: tied 1st · 2 Round Wins", the roles
##      context), party rounds
##   4. rewards: Season XP and Coins, pending kept apart from what was
##      added; the round's challenge lines go inside this card (the
##      challenges stream's add_challenge_lines in _fill_rewards)
##   then both teams' tables for the round.
func _round_page() -> void:
	if between_rounds():
		_between_page()
		return
	var d := view_data
	var practice := bool(results.get("practice", false)) or _practice()
	# (build 30) less is more: the result, one line why, your part; no
	# overlines, no repeated "your team won"
	var head := UIKit.vbox(2)
	var where := ("Practice" if practice else "Round %d of %d" % [int(results.get("round_index", 1)), int(results.get("rounds_total", 1))])
	var oc := int(d["outcome"])
	var t := headline(d)
	var tl := UIKit.styled(String(t[0]), "display", t[1])
	tl.name = "Outcome"
	tl.add_theme_font_size_override("font_size", 50)
	head.add_child(tl)
	var why := UIKit.styled(("%s · %s" % [where, String(t[2])]) if String(t[2]) != "" else where, "body", UIKit.IVORY_MUTED)
	why.name = "Why"
	why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(why)
	if not bool(d["cancelled"]):
		var mine := UIKit.styled(my_contribution(d.get("me", {})), "label", UIKit.TEAL)
		mine.name = "Contribution"
		mine.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		head.add_child(mine)
	# (2.3) the outcome on a coloured banner (gold for a win), the title
	# popping in, and confetti over the room when your team won
	var me: Dictionary = d.get("me", {})
	var won := not bool(d["cancelled"]) and not me.is_empty() and int(me["role"]) == int(d["winners"])
	var banner := PanelContainer.new()
	banner.name = "OutcomeBanner"
	var bsb := UIKit.box(Color(UIKit.AMBER, 0.16) if won else Color(UIKit.NAVY, 0.45), UIKit.R_CARD, 2 if won else 0, Color(UIKit.AMBER, 0.55), 22)
	bsb.content_margin_top = 14
	bsb.content_margin_bottom = 16
	banner.add_theme_stylebox_override("panel", bsb)
	banner.add_child(head)
	_v.add_child(banner)
	if not UIKit.reduced_motion():
		tl.pivot_offset = Vector2(0, 30)
		tl.scale = Vector2(0.7, 0.7)
		tl.modulate.a = 0.0
		var tw := tl.create_tween().set_parallel(true)
		tw.tween_property(tl, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(tl, "modulate:a", 1.0, 0.2)
		if won:
			var cf := Confetti.new()
			cf.set_anchors_preset(Control.PRESET_FULL_RECT)
			add_child(cf)
			move_child(cf, 1)
	if bool(d["cancelled"]):
		var note := UIKit.panel(Color(UIKit.NAVY, 0.5), UIKit.R_CARD, 18)
		var nl := UIKit.styled("This round doesn't count.", "body", UIKit.IVORY)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_child(nl)
		_v.add_child(note)
		if not series_view().is_empty() and _party():
			_series_so_far(true)
		return
	if not rank.is_empty():
		_v.add_child(_run_line())
	var party_series := _party() and not series_view().is_empty()
	# the series in one line
	if party_series:
		_series_so_far(false)
	var rw := _rewards_card()
	if rw != null:
		_v.add_child(rw)
	# (build 34) the tables say who won; the portrait strip above them went
	_v.add_child(_team_table("Runners", d["runners"], TC.Role.RUNNER, int(d["winners"]) == TC.Role.RUNNER))
	_v.add_child(_team_table("Night Watch", d["watch"], TC.Role.PATROL, int(d["winners"]) == TC.Role.PATROL))
	# the friends' standings so far (after the last round: Final standings)
	if party_series and not series_over() and not session.series_flow():
		_v.add_child(standings_table(series_view(), Save.player_uid(), 3))


## (build 34) Between the rounds of a series: the outcome in a line, your
## part, your Coins and XP, the standings so far; the countdown sits below.
func _between_page() -> void:
	var d := view_data
	var me: Dictionary = d.get("me", {})
	var won := not me.is_empty() and int(me["role"]) == int(d["winners"])
	var t := headline(d)
	var head := UIKit.vbox(2)
	var tl := UIKit.styled(String(t[0]), "display", t[1])
	tl.name = "Outcome"
	tl.add_theme_font_size_override("font_size", 46)
	head.add_child(tl)
	var why := UIKit.styled("Round %d of %d%s" % [int(results.get("round_index", 1)), int(results.get("rounds_total", 1)),
		(" · " + String(d.get("why_short", ""))) if String(d.get("why_short", "")) != "" else ""], "body", UIKit.IVORY_MUTED)
	why.name = "Why"
	head.add_child(why)
	var mine := UIKit.styled(my_contribution(me), "label", UIKit.TEAL)
	mine.name = "Contribution"
	head.add_child(mine)
	var banner := PanelContainer.new()
	banner.name = "OutcomeBanner"
	var bsb := UIKit.box(Color(UIKit.AMBER, 0.16) if won else Color(UIKit.NAVY, 0.45), UIKit.R_CARD, 2 if won else 0, Color(UIKit.AMBER, 0.55), 20)
	bsb.content_margin_top = 10
	bsb.content_margin_bottom = 12
	banner.add_theme_stylebox_override("panel", bsb)
	var bh := UIKit.hbox(16)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(head)
	var chips := _reward_chips()
	if chips != null:
		chips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bh.add_child(chips)
	banner.add_child(bh)
	_v.add_child(banner)
	if won and not UIKit.reduced_motion():
		var cf := Confetti.new()
		cf.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(cf)
		move_child(cf, 1)
	var st := standings_table(series_view(), Save.player_uid())
	st.name = "Standings"
	_v.add_child(st)


## (build 34) This round's Coins and Season XP as two numbers (the details
## are in the Season Pass and the wallet), or nothing when it pays nothing.
##
## (2.2 (35)) Only what the round pays: added (amber) or being added (muted,
## "adding…", until the service settles it; the chips follow the wallet).  A
## round that pays nothing (practice, bots only, away, …) no longer shows the
## Coins it would have paid as if they were added: one short muted reason
## instead.  Tap a number for its breakdown.
func _reward_chips() -> Control:
	var mid := String(results.get("match_id", ""))
	if RoundRewards.summary(mid, reward).is_empty():
		return null
	var h := UIKit.hbox(14)
	h.name = "Rewards"
	_fill_chips(h, mid)
	Wallet.round_updated.connect(func(m: String) -> void:
		if m == mid and is_instance_valid(h):
			_fill_chips(h, mid), CONNECT_REFERENCE_COUNTED)
	return h


func _fill_chips(h: HBoxContainer, mid: String) -> void:
	for c in h.get_children():
		h.remove_child(c)
		c.queue_free()
	var s := RoundRewards.summary(mid, reward)
	if s.is_empty():
		return
	var settled := bool(s["settled"])
	var pending := bool(s["pending"])
	if not settled and not pending:
		var why := short_reason(s)
		if why != "":
			var l := UIKit.styled(why, "caption", UIKit.IVORY_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
			l.name = "NoPay"
			h.add_child(l)
		h.accessibility_name = why
		return
	var coins := int(s["coins"]) if settled else int(s.get("coins_projected", 0))
	var xp := (int(s["season_xp"]) + int(s.get("challenge_xp", 0))) if settled else int(s.get("season_xp_projected", 0))
	var col := UIKit.AMBER if settled else UIKit.IVORY_MUTED
	if coins > 0:
		h.add_child(_tap_number("+%s" % Catalogue.format_coins(coins), "Coins" if settled else "adding…", col, "Coins", s.get("lines", [])))
		if settled and App.coin_fly_match != mid:
			App.coin_fly_match = mid
			App.coin_fly_pending = coins
	if xp > 0:
		h.add_child(_tap_number("+%d" % xp, "XP" if settled else "adding…", col, "XP", xp_lines(s)))
	h.accessibility_name = "%d Coins, %d Season XP%s" % [coins, xp, "" if settled else " (being added)"]


## (2.2 (35)) Why a round paid nothing, in a few words (between rounds).
static func short_reason(s: Dictionary) -> String:
	match String(s.get("state", "")):
		"practice":
			return "Practice: no Coins or XP"
		"not_eligible":
			match String(s.get("reason", "")):
				"few_humans":
					return "Coins and XP need 2+ players"
				"away":
					return "Away: no Coins or XP"
			return "This round pays nothing"
		"capped":
			return "Today's reward limit reached"
		"cancelled":
			return ""
		"rejected":
			return "Too short to pay" if String(s.get("reason", "")) == "too_short" else "Not added this round"
		"no_service", "unverified_room", "mismatch":
			return "Not added this round"
	return ""


## (2.2 (35)) The Season XP lines, with the challenge bonus when it counted.
static func xp_lines(s: Dictionary) -> Array:
	var out: Array = (s.get("season_lines", []) as Array).duplicate()
	if int(s.get("challenge_xp", 0)) > 0:
		out.append(["Challenges", int(s["challenge_xp"])])
	return out


## One line for a breakdown toast: "XP: Completed the round +50 · Splashes ×3 +30".
static func breakdown_text(what: String, lines: Array) -> String:
	var bits: Array[String] = []
	for l in lines:
		if l is Array and (l as Array).size() >= 2 and int(l[1]) != 0:
			bits.append("%s +%d" % [String(l[0]), int(l[1])])
	return ("%s: %s" % [what, " · ".join(bits)]) if not bits.is_empty() else ""


## A big number with its caption that shows its breakdown when tapped.
func _tap_number(n: String, label_text: String, col: Color, what: String, lines: Array) -> Control:
	var box := PanelContainer.new()
	box.name = "Tap" + what
	box.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var v := _big_number(n, label_text)
	((v.get_child(0)) as Label).add_theme_color_override("font_color", col)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in v.get_children():
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(v)
	var text := breakdown_text(what, lines)
	box.set_meta(&"breakdown", text)
	if text != "":
		box.tooltip_text = text
		box.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and not (ev as InputEventMouseButton).pressed:
				show_breakdown(text))
	return box


func show_breakdown(text: String) -> void:
	if text != "":
		UIKit.toast(self, text, 4.0)


## (build 34) Your run and Season Points in one line ("Run 2:31 · Best
## 2:10 · +120 Season Points"), replacing the two-column card.
func _run_line() -> Control:
	var bits: Array[String] = []
	var run := float(rank.get("run_time", -1.0))
	bits.append(("Run %s" % Rankings.fmt_time(run)) if run > 0.0 else "Not home")
	if bool(rank.get("new_best", false)):
		bits.append("New best!")
	elif float(rank.get("best", -1.0)) > 0.0:
		bits.append("Best %s" % Rankings.fmt_time(float(rank["best"])))
	if bool(rank.get("counted", false)):
		bits.append("+%d Season Points" % int(rank["points"]))
	var l := UIKit.styled(" · ".join(bits), "label", UIKit.AMBER if bool(rank.get("new_best", false)) else UIKit.IVORY)
	l.name = "RunCard"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## [title, colour, why] for the top of the round page, from your side:
## "Your team won!" / "Your team lost" (or the winning role when you
## watched), and the reason in the round's real numbers.
static func headline(d: Dictionary) -> Array:
	var oc := int(d.get("outcome", TC.Outcome.NONE))
	if bool(d.get("cancelled", false)):
		return ["Round cancelled", UIKit.IVORY, "The round was interrupted (a connection or the host ended it)."]
	var me: Dictionary = d.get("me", {})
	var runners_won := oc == TC.Outcome.RUNNERS_WIN
	var why := String(d.get("why_short", ""))
	if me.is_empty():
		return ["Runners win!" if runners_won else "Night Watch wins!", UIKit.TEAL if runners_won else UIKit.PATROL, why]
	var won := int(me["role"]) == int(d["winners"])
	var team := "Runners" if int(me["role"]) == TC.Role.RUNNER else "Night Watch"
	return ["Your team won!" if won else "Your team lost", UIKit.AMBER if won else UIKit.IVORY,
		"%s · %s" % [team, why] if why != "" else team]


## 2: what you did this round, in one card.
func _contribution_card(d: Dictionary) -> Control:
	var p := UIKit.panel(Color(UIKit.SLATE_HI, 0.85), UIKit.R_CARD, 18)
	p.name = "Contribution"
	var v := UIKit.vbox(2)
	v.add_child(UIKit.styled("You", "overline", UIKit.IVORY_MUTED))
	var me: Dictionary = d["me"]
	var l := UIKit.styled(my_contribution(me), "label", UIKit.IVORY)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	if not me.is_empty() and bool(me.get("away", false)):
		v.add_child(UIKit.styled("Away for too much of the round: no Round Win.", "caption", UIKit.IVORY_MUTED))
	p.add_child(v)
	return p


## (2.2) Your run and Season Points: the time from GO to home, your best,
## and what this round added to the Rankings (or why it doesn't count).
func _run_card() -> Control:
	var p := UIKit.panel(Color(UIKit.NAVY, 0.72), UIKit.R_CARD, 18)
	p.name = "RunCard"
	var h := UIKit.hbox(18)
	var run := float(rank.get("run_time", -1.0))
	var left := UIKit.vbox(0)
	left.add_child(UIKit.styled("YOUR RUN", "overline", UIKit.TEAL))
	var big := UIKit.styled(Rankings.fmt_time(run) if run > 0.0 else "Not home", "num", UIKit.IVORY)
	big.add_theme_font_size_override("font_size", 40)
	left.add_child(big)
	if bool(rank.get("new_best", false)):
		left.add_child(UIKit.chip("NEW PERSONAL BEST!", UIKit.AMBER, UIKit.NAVY, UIKit.T_OVERLINE + 1))
	elif float(rank.get("best", -1.0)) > 0.0:
		left.add_child(UIKit.styled("Best %s" % Rankings.fmt_time(float(rank["best"])), "caption", UIKit.IVORY_MUTED))
	h.add_child(left)
	var right := UIKit.vbox(2)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(UIKit.styled("SEASON POINTS", "overline", UIKit.AMBER))
	if bool(rank.get("counted", false)):
		var pts := UIKit.styled("+%d" % int(rank["points"]), "num", UIKit.AMBER)
		pts.add_theme_font_size_override("font_size", 34)
		right.add_child(pts)
		if not Rankings.boards_open():
			right.add_child(UIKit.styled("Leaderboards open in %s" % Rankings.time_to_start_text(), "caption", UIKit.IVORY_MUTED))
	else:
		var wl := UIKit.styled(String(rank.get("why", "")), "caption", UIKit.IVORY_MUTED)
		wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		right.add_child(wl)
	h.add_child(right)
	p.add_child(h)
	return p


## "Home 2nd · 2:31 · 3/3 waters" / "Not home · 2/3 waters · caught 1" /
## "3 tags · 2 different runners".
static func my_contribution(me: Dictionary) -> String:
	if me.is_empty():
		return "You watched this round."
	if int(me["role"]) == TC.Role.RUNNER:
		var c := int(me.get("caught", 0))
		var tail := " · caught %d" % c if c > 0 else " · never caught"
		if bool(me["finished"]):
			return "Home %s · %s · %d/3 waters%s" % [RoundRanking.ordinal(int(me["finish_order"])), _clock(float(me["finish_time"])), int(me["stamps"]), tail]
		return "Not home · %d/3 waters%s" % [int(me["stamps"]), tail]
	var tags := int(me.get("tags", 0))
	var n := int(me.get("distinct", 0))
	return "%d tag%s · %d different runner%s" % [tags, "" if tags == 1 else "s", n, "" if n == 1 else "s"]


func _final_page() -> void:
	var view := series_view()
	var head := UIKit.vbox(2)
	head.add_child(UIKit.styled("Final standings", "display", UIKit.AMBER))
	if bool(view.get("ended_early", false)):
		head.add_child(UIKit.styled("Ended early", "caption", UIKit.IVORY_MUTED))
	_v.add_child(head)
	var rows := RoundRanking.series_rows(view, Save.player_uid())
	if rows.is_empty():
		_v.add_child(UIKit.styled("No completed rounds.", "body", UIKit.IVORY_MUTED))
		return
	_v.add_child(_podium(rows))
	_v.add_child(standings_table(view, Save.player_uid()))
	# (build 34) the score by role in numbers; the per-round list went
	var tally := LobbyScreen._tally(view)
	var tl := UIKit.styled("Runners %d – %d Night Watch" % [tally[0], tally[1]], "caption", UIKit.IVORY_MUTED)
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_v.add_child(tl)


# ---------------------------------------------------------------------------
# Pieces
# ---------------------------------------------------------------------------
func _celebration(d: Dictionary) -> Control:
	var box := UIKit.vbox(8)
	var me: Dictionary = d["me"]
	var won := not me.is_empty() and int(me["role"]) == int(d["winners"])
	var cap := "Winners"
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
	UIKit.fit_text(nm, [UIKit.T_LABEL, UIKit.T_CAPTION, 17], true)
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
			vals = ["#%d · %s" % [int(r["finish_order"]), _clock(float(r["finish_time"]))] if bool(r["finished"]) else "Not home",
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
	var mid := String(results.get("match_id", ""))
	# (build 30) a round that pays nothing shows no rewards card at all
	if RoundRewards.summary(mid, reward).is_empty():
		return null
	var p := UIKit.panel(Color(UIKit.NAVY, 0.45), UIKit.R_CARD, 18)
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
	if s.is_empty():
		p.visible = false
		return
	p.visible = true
	var top := UIKit.hbox(18)
	if int(s["coins_collected"]) > 0:
		top.add_child(_big_number("%d" % int(s["coins_collected"]), "picked up"))
	if bool(s["settled"]):
		top.add_child(_tap_number("+%s" % Catalogue.format_coins(int(s["coins"])), "Coins added", UIKit.AMBER, "Coins", s.get("lines", [])))
		# (2.3) back in the lobby these coins fly into the coin counter
		if int(s["coins"]) > 0 and App.coin_fly_match != mid:
			App.coin_fly_match = mid
			App.coin_fly_pending = int(s["coins"])
		if int(s["season_xp"]) > 0:
			top.add_child(_tap_number("+%d" % (int(s["season_xp"]) + int(s.get("challenge_xp", 0))), "Season XP", UIKit.AMBER, "XP", xp_lines(s)))
	var msg := String(s["message"])
	if bool(s["pending"]):
		# (build 34) numbers over words
		msg = "+%s Coins · +%d XP (pending)" % [Catalogue.format_coins(int(s["coins_projected"])), int(s["season_xp_projected"])]
	elif bool(s["away"]) and msg == "":
		msg = "Away: no rewards"
	if msg == "" and top.get_child_count() == 0:
		p.visible = false
		return
	if msg != "":
		var ml := UIKit.styled(msg, "caption", UIKit.IVORY if bool(s["settled"]) else UIKit.IVORY_MUTED)
		ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ml.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ml.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(ml)
	v.add_child(top)
	add_challenge_lines(v, s.get("challenges", {}) if s.get("challenges") is Dictionary else {})
	if bool(s["settled"]) and int(s["season_xp"]) > 0:
		# (2.2 build 18) the bar fills from where you were to where you are
		# (through each tier gained, with a pop and a chime)
		var xb := XpBar.new()
		xb.name = "XpBar"
		xb.tier_from = int(s["tier_before"])
		xb.tier_to = int(s["tier_after"])
		xb.frac_from = float(s["frac_before"])
		xb.frac_to = float(s["frac_after"])
		xb.custom_minimum_size = Vector2(0, 46)
		v.add_child(xb)
	if bool(s["level_up"]):
		v.add_child(UIKit.styled("Level up! You're now level %d" % int(s["level"]), "label", UIKit.TEAL))


## Pass 8: the round's part in challenges (Wallet.round_summary()
## ["challenges"], docs/ECONOMY.md §10), a self-contained block for the
## rewards card, placed before the Season progress bar (which already
## includes any bonus): each goal this round completed ("Campus
## Contribution complete · +50 Season XP", marked pending until the service
## settles the round), the other goals it moved, and one honest sentence
## when it counted for nothing (inactive, practice training, too late).
## Adds nothing for a round with no challenge part.
static func add_challenge_lines(v: Container, ch: Dictionary) -> void:
	var st := String(ch.get("state", "none"))
	if st == "none" or st == "":
		return
	var pending := st == "pending"
	var moved: Array[String] = []
	for line in ch.get("lines", []):
		if not (line is Dictionary):
			continue
		var nm := String(line.get("name", ""))
		if bool(line.get("completed_now", false)):
			var row := UIKit.hbox(8)
			row.name = "ChallengeDone"
			var ic := Icons.IconRect.new("check", UIKit.IVORY_MUTED if pending else UIKit.TEAL, 22)
			ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(ic)
			var l := UIKit.styled("%s complete · %s%s" % [nm, ChallengeRules.xp_text(int(line.get("xp", 0))), " (pending)" if pending else ""],
				"label", UIKit.IVORY if pending else UIKit.AMBER)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
			v.add_child(row, true)
		else:
			var prog := int(line.get("progress", -1))
			moved.append(("%s %d/%d" % [nm, prog, int(line.get("goal", 0))]) if prog >= 0 else ("%s +%d" % [nm, int(line.get("inc", 0))]))
	var bits: Array[String] = []
	if not moved.is_empty():
		bits.append(("Challenges, pending: " if pending else "Challenges: ") + " · ".join(moved))
	if String(ch.get("message", "")) != "":
		bits.append(String(ch["message"]))
	for b in bits:
		var m := UIKit.styled(b, "caption", UIKit.IVORY_MUTED)
		m.name = "ChallengeNote"
		m.add_theme_font_size_override("font_size", 18)
		m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(m, true)


func _big_number(n: String, label_text: String) -> Control:
	var v := UIKit.vbox(0)
	var l := UIKit.label(n, 32, UIKit.AMBER)
	l.add_theme_font_override("font", UIKit.font_num(800))
	v.add_child(l)
	v.add_child(UIKit.styled(label_text, "caption", UIKit.IVORY_MUTED))
	return v


## 3: your series standing in words, with the roles context.  `with_table`:
## the friends' table too (a cancelled round shows nothing else).
func _series_so_far(with_table: bool = true) -> void:
	var view := series_view()
	var sv := UIKit.vbox(4)
	sv.name = "Series"
	var tally := LobbyScreen._tally(view)
	# (build 30) one line: your standing, then the roles' score, small
	var line := RoundRanking.series_line(view, Save.player_uid())
	var sl := UIKit.styled(("%s  ·  Runners %d – %d Night Watch" % [line, tally[0], tally[1]]) if line != "" else "Runners %d – %d Night Watch" % [tally[0], tally[1]],
		"label", UIKit.AMBER)
	sl.name = "SeriesLine"
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sv.add_child(sl)
	if with_table:
		sv.add_child(standings_table(view, Save.player_uid(), 3))
	_v.add_child(sv)


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
	# (build 30) "Played" only when it says something (a late join, rounds
	# away): everyone played every round is the usual case
	var uneven := false
	for r in rows:
		if int(r["played"]) != int(rows[0]["played"]) or int(r["joined_round"]) > 1 or int(r["partial"]) > 0:
			uneven = true
	var cols := [["Place", 70.0, HORIZONTAL_ALIGNMENT_LEFT], ["Player", -1.0, HORIZONTAL_ALIGNMENT_LEFT], ["Round Wins", 130.0, HORIZONTAL_ALIGNMENT_RIGHT]]
	if uneven:
		cols.append(["Played", 170.0, HORIZONTAL_ALIGNMENT_RIGHT])
	var hdr := UIKit.hbox(10)
	for spec in cols:
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
		if uneven:
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
	if between_rounds():
		return   # (build 34) the next round starts by itself
	if session.series_flow() and (page == "final" or series_over() or bool(view_data["cancelled"]) or int(results.get("rounds_total", 1)) <= 1) \
			and not (series_over() and page == "round" and not bool(view_data["cancelled"])):
		# (build 34) Back to lobby
		if session.is_host():
			App.back_to_party()
		else:
			App.show_lobby()
		return
	if series_over() and page == "round" and not bool(view_data["cancelled"]):
		page = "final"
		_build_page()
		_open_at_top(_sc)
		return
	# (build 33) the party leader goes back to the lobby to start the next
	# round; everyone else (a host that doesn't lead too) readies up here
	if series_over() or bool(view_data["cancelled"]) or session.is_leader():
		if session.is_host():
			App.back_to_party()
		else:
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


## Labels and waiting states.
func _refresh_actions() -> void:
	if not is_instance_valid(_primary):
		return
	if is_instance_valid(chat_btn):
		var n: int = session.social.chat.unread
		UIKit.face_of(chat_btn).caption = "Chat · %d" % n if n > 0 else "Chat"
		UIKit.face_of(chat_btn).queue_redraw()
	_primary.visible = true
	if is_instance_valid(leave_btn):
		leave_btn.visible = true
	if is_instance_valid(chat_btn):
		chat_btn.visible = true
	if _practice():
		_primary.text = "Play again"
		return
	if session.series_flow():
		# (build 34) between rounds: only Leave match (the countdown does the
		# rest); after the last round: Final standings, then Back to lobby
		_status.visible = false
		_status.text = ""
		if between_rounds():
			_primary.visible = false
			if is_instance_valid(chat_btn):
				chat_btn.visible = false
			leave_btn.text = "Leave match"
			leave_btn.accessibility_name = "Leave match"
			_fit_sheet.call_deferred()
			return
		if is_instance_valid(chat_btn):
			chat_btn.visible = false
		leave_btn.visible = false
		var to_final := series_over() and page == "round" and not bool(view_data["cancelled"])
		_primary.text = "Final standings" if to_final else "Back to lobby"
		UIKit._apply(_primary, UIKit.AMBER, UIKit.NAVY)
		_fit_sheet.call_deferred()
		return
	var over := series_over()
	var cancelled := bool(view_data["cancelled"]) and not final_only
	_status.visible = true
	if over and page == "round" and not cancelled:
		_primary.text = "Final standings"
		UIKit._apply(_primary, UIKit.AMBER, UIKit.NAVY)
		_status.text = ""
		_status.visible = false
		return
	if (session.is_host() and over) or (session.is_leader() and not cancelled):
		if over:
			_primary.text = "Return to lobby"
			_status.text = ""
			_status.visible = false
		else:
			_primary.text = "Next: round %d" % session.next_round_number()
			_status.text = "Starts when everyone's ready."
		UIKit._apply(_primary, UIKit.AMBER, UIKit.NAVY)
		return
	if over or cancelled:
		_primary.text = "Return to lobby"
		UIKit._apply(_primary, UIKit.AMBER, UIKit.NAVY)
		_status.text = "" if session.is_leader() else ("Waiting for the party leader to start another round." if cancelled else "Waiting for the party leader to start another series.")
		_status.visible = _status.text != ""
		return
	var e: Variant = session.roster[session.local_slot] if session.local_slot >= 0 else null
	var rdy := e != null and bool(e["ready"])
	_primary.text = "Not ready" if rdy else "Ready for round %d" % session.next_round_number()
	UIKit._apply(_primary, UIKit.SLATE_HI if rdy else UIKit.AMBER, UIKit.IVORY if rdy else UIKit.NAVY)
	_status.text = "Waiting for the party leader" if rdy else "Nothing starts until everyone's ready."


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


## (build 34) Leave match between the rounds of a series, after a confirm.
func _ask_leave_match() -> void:
	if has_modal():
		return
	if session.is_host() or session.is_leader():
		UIKit.v7_back_chooses(self, dialog("End the match for everyone?", [["End match", func() -> void: App.leave_series_match()], ["Keep playing", Callable()]]))
	else:
		UIKit.v7_back_chooses(self, dialog("Leave the match? You stay in the party.", [["Leave match", func() -> void: App.leave_series_match()], ["Stay", Callable()]]))


func _go_back() -> void:
	if _board and is_instance_valid(_board):
		_toggle_board()   # Back / B closes the scoreboard first
		return
	if between_rounds():
		_ask_leave_match()   # (build 34) never straight to the lobby mid-match
		return
	if page == "final" and not final_only:
		page = "round"   # Back from the final standings returns to the round
		_build_page()
		return
	if _practice():
		App.goto_title()
	else:
		App.show_lobby()


## (build 34) The countdown to the next round of a series: a ring that
## empties over the last seconds and the seconds left, big, with the round
## it leads to.
class CountdownRing:
	extends Control
	var left := 5.0
	var total := 5.0
	var next_round := 2
	var _cap: Label

	func _init() -> void:
		custom_minimum_size = Vector2(0, 112)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cap = UIKit.styled("", "label", UIKit.IVORY)
		_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cap.add_theme_font_override("font", UIKit.font_w(800))
		_cap.add_theme_font_size_override("font_size", 30)
		_cap.position = Vector2(126, 26)
		add_child(_cap)
		var sub := UIKit.styled("starts by itself", "caption", UIKit.IVORY_MUTED)
		sub.name = "Sub"
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sub.position = Vector2(126, 66)
		add_child(sub)

	func set_left(l: float, t: float, n: int) -> void:
		left = l
		total = maxf(0.1, t)
		next_round = n
		_cap.text = "Round %d" % n
		accessibility_name = "Round %d starts in %d" % [n, int(ceil(l))]
		queue_redraw()

	func _draw() -> void:
		var c := Vector2(54, size.y * 0.5)
		var r := 46.0
		draw_circle(c, r, Color(UIKit.NAVY, 0.6))
		draw_arc(c, r - 4.0, 0.0, TAU, 64, Color(UIKit.IVORY, 0.14), 7.0, true)
		var f := clampf(left / total, 0.0, 1.0)
		if f > 0.0:
			draw_arc(c, r - 4.0, -PI * 0.5, -PI * 0.5 + TAU * f, 64, UIKit.AMBER, 7.0, true)
		var n := str(int(ceil(left))) if left > 0.05 else "GO"
		var font := UIKit.font_num(800)
		var fs := 50 if n != "GO" else 34
		var sz := font.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(font, c + Vector2(-sz.x * 0.5, sz.y * 0.32), n, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UIKit.IVORY)


## (2.3) Confetti over the room for a win: a few seconds of falling paper
## in the game's colours, then it fades and frees itself.
class Confetti:
	extends Control
	var pieces: Array = []
	var t := 0.0
	const LIFE := 4.5

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var cols := [UIKit.AMBER, UIKit.TEAL, Color("ff7aa2"), Color("8fd3ff"), UIKit.IVORY]
		for i in 70:
			pieces.append({"x": rng.randf(), "y": rng.randf_range(-0.6, 0.0), "v": rng.randf_range(0.18, 0.34),
				"sway": rng.randf_range(0.5, 2.0), "r": rng.randf() * TAU, "w": rng.randf_range(-4.0, 4.0), "c": cols[i % cols.size()],
				"s": rng.randf_range(7.0, 12.0)})

	func _process(delta: float) -> void:
		t += delta
		if t > LIFE:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var fade := clampf((LIFE - t) / 1.0, 0.0, 1.0)
		for q in pieces:
			var y := float(q["y"]) + t * float(q["v"])
			if y < -0.05 or y > 1.05:
				continue
			var x := float(q["x"]) + sin(t * float(q["sway"]) + float(q["r"])) * 0.02
			var col: Color = q["c"]
			col.a *= fade
			var sz := float(q["s"])
			draw_set_transform(Vector2(x * size.x, y * size.y), float(q["r"]) + t * float(q["w"]), Vector2.ONE)
			draw_rect(Rect2(-sz, -sz * 0.4, sz * 2.0, sz * 0.8), col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)



## (2.2 build 18) The round's Season XP filling the tier bar: from where the
## round started to where it ended, through every tier gained (each one
## pops with a chime).  Reduced Motion: the end state at once.
class XpBar:
	extends Control
	var tier_from := 0
	var tier_to := 0
	var frac_from := 0.0
	var frac_to := 0.0
	var _t := 0.0
	var _shown_tier := 0
	var _pop := 0.0
	const DELAY := 0.5
	const PER_TIER := 0.9

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_shown_tier = tier_from
		if UIKit.reduced_motion():
			_t = 999.0
			_shown_tier = tier_to

	## progress 0..(tiers gained + 1): whole numbers are tier boundaries
	func _span() -> float:
		return float(maxi(0, tier_to - tier_from)) + 1.0

	func _process(delta: float) -> void:
		if _t >= DELAY + PER_TIER * _span() + 0.5:
			if _pop > 0.0:
				_pop = maxf(0.0, _pop - delta * 2.5)
				queue_redraw()
			return
		_t += delta
		_pop = maxf(0.0, _pop - delta * 2.5)
		var k := clampf((_t - DELAY) / PER_TIER, 0.0, _span())
		var tier_now := tier_from + mini(int(floor(k)), tier_to - tier_from)
		if tier_now != _shown_tier:
			_shown_tier = tier_now
			_pop = 1.0
			Sfx.play("reward", null, -4.0)
			Haptics.tap()
		queue_redraw()

	func _frac_now() -> float:
		var k := clampf((_t - DELAY) / PER_TIER, 0.0, _span())
		var gained := tier_to - tier_from
		if gained <= 0:
			return lerpf(frac_from, frac_to, _ease(k))
		var seg := int(floor(k))
		var u := k - float(seg)
		if seg == 0:
			return lerpf(frac_from, 1.0, _ease(u))
		if seg < gained:
			return _ease(u)
		return lerpf(0.0, frac_to, _ease(u)) if seg == gained else frac_to

	func _ease(u: float) -> float:
		return 1.0 - pow(1.0 - clampf(u, 0.0, 1.0), 3.0)

	func _draw() -> void:
		var f := UIKit.font_w(700)
		var tier_txt := "Tier %d" % _shown_tier
		var fs := int(22.0 + 6.0 * _pop)
		draw_string(f, Vector2(0, 22), tier_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UIKit.TEAL.lerp(UIKit.AMBER_HI, _pop))
		if tier_to > tier_from:
			var up := "Tier up!"
			var w := f.get_string_size(up, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			draw_string(f, Vector2(size.x - w, 20), up, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(UIKit.AMBER, clampf((_t - DELAY) / PER_TIER, 0.0, 1.0)))
		var r := Rect2(0, 30, size.x, 14)
		draw_style_box(UIKit.box(Color(UIKit.NAVY, 0.85), 999), r)
		var fr := clampf(_frac_now(), 0.0, 1.0)
		if fr > 0.0:
			var fw := maxf(r.size.y, r.size.x * fr)
			draw_style_box(UIKit.box(UIKit.TEAL.lerp(UIKit.AMBER, _pop * 0.6), 999), Rect2(r.position, Vector2(fw, r.size.y)))
			draw_rect(Rect2(r.position + Vector2(4, 2), Vector2(maxf(0.0, fw - 8.0), 3)), Color(1, 1, 1, 0.25))
