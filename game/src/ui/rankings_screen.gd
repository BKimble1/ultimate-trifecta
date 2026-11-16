class_name RankingsScreen
extends Screen
## Rankings (2.2): this season's Game Center leaderboards, your own run
## stats, and the Season Champion prize.
##
##   header   Rankings · the season's name · "Ends in 12d 4h"
##   left     the champion prize (the poster, small) with Official Rules,
##            and Your stats (season points, rounds counted, best runs)
##   right    Season Points | Fastest Run, Everyone | Friends, the top of
##            the board with gold/silver/bronze places, your row pinned
## States are honest: loading, signed out of Game Center, no scores yet,
## couldn't load (Try again).  Data comes from Game Center only; nothing is
## invented (development captures can pass --rank-sample, labelled SAMPLE).

const PAGE := 25
var board := Rankings.BOARD_POINTS
var friends_only := false
var list_box: VBoxContainer
var state_lbl: Label
var tabs: Array[Button] = []
var scopes: Array[Button] = []
var _req := 0
## tests/captures: replaces Social.load_board: func(id, friends, first, n, done)
var loader: Callable


func build() -> void:
	if App.stage:
		App.stage.set_mode("home")
	TitleScreen.add_shades(self, 0.7, 0.6)
	var h := header("Rankings")
	h.add_child(UIKit.spacer_h())
	# (2.3) one chip for the season: its name and the time left
	var sn := UIKit.chip("%s  ·  ends in %s" % [Rankings.season_name(), Rankings.time_left_text()], Color(UIKit.AMBER, 0.18), UIKit.AMBER_HI, UIKit.T_LABEL)
	sn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(sn)
	var body := UIKit.hbox(22)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)
	# --- left: the prize + your stats
	var left := UIKit.vbox(16)
	left.custom_minimum_size.x = 380
	body.add_child(left)
	var prize := ChampionPromo.banner(self)
	left.add_child(prize)
	left.add_child(_my_stats())
	# --- right: the boards
	var right := UIKit.panel(Color(UIKit.SLATE, 0.95), UIKit.R_PANEL, 22)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var rv := UIKit.vbox(14)
	right.add_child(rv)
	var tr := UIKit.hbox(12)
	var ids := [Rankings.BOARD_POINTS, Rankings.BOARD_FASTEST]
	var seg := UIKit.segmented(["Season Points", "Fastest Run"], 0, func(i: int) -> void:
		board = String(ids[i])
		_load())
	tr.add_child(seg)
	for b in seg.get_meta(&"buttons"):
		tabs.append(b)
	tr.add_child(UIKit.spacer_h())
	var scope := UIKit.segmented(["Everyone", "Friends"], 0, func(i: int) -> void:
		friends_only = i == 1
		_load(), UIKit.TEAL)
	tr.add_child(scope)
	for b in scope.get_meta(&"buttons"):
		scopes.append(b)
	rv.add_child(tr)
	state_lbl = UIKit.styled("", "body", UIKit.IVORY_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	state_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(state_lbl)
	var sc := UIKit.scroll_area()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(sc)
	list_box = UIKit.vbox(8)
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list_box)
	var foot := UIKit.hbox(10)
	var how := UIKit.styled("Online rounds count · new board every 30 days", "caption", UIKit.IVORY_MUTED)
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(how)
	var gc := UIKit.quiet("Game Center", Vector2(0, UIKit.touch_min()), UIKit.T_CAPTION)
	gc.pressed.connect(func() -> void:
		if not Social.show_leaderboard(board, friends_only):
			UIKit.toast(self, "Sign in to Game Center to see the full leaderboard."))
	foot.add_child(gc)
	rv.add_child(foot)
	_load()
	focus_first(tabs[0])


## (the segmented controls paint themselves)
func _paint_tabs() -> void:
	pass


func _load() -> void:
	_req += 1
	var req := _req
	for c in list_box.get_children():
		c.queue_free()
	state_lbl.text = "Loading…"
	state_lbl.visible = true
	var done := func(r: Dictionary) -> void:
		if req != _req or not is_inside_tree():
			return
		_show(r)
	if not Rankings.boards_open() and not loader.is_valid() and not App.dev_rank_sample:
		# the preseason: Game Center's boards start with the first season
		state_lbl.text = "The leaderboards open with %s in %s. Until then, online rounds count toward Your stats." % [
			Rankings.season_name(Rankings.FIRST_SEASON), Rankings.time_to_start_text()]
		return
	var ld: Callable = loader if loader.is_valid() else (Callable(Social, "load_board") if not App.dev_rank_sample else Callable(self, "_sample"))
	ld.call(board, friends_only, 1, PAGE, done)


func _show(r: Dictionary) -> void:
	for c in list_box.get_children():
		c.queue_free()
	if not bool(r.get("ok", false)):
		var e := String(r.get("error", ""))
		state_lbl.text = "Sign in to Game Center (iPhone Settings › Game Center) to see the Rankings." if e == "signed_out" \
			else "The leaderboard couldn't load right now. Check your connection and try again."
		if e != "signed_out":
			var again := UIKit.secondary("Try again", Vector2(220, UIKit.touch_min()))
			again.pressed.connect(_load)
			list_box.add_child(again)
		return
	var entries: Array = r.get("entries", [])
	state_lbl.visible = entries.is_empty() or bool(r.get("sample", false))
	state_lbl.text = "No scores yet this season. Play an online round to be the first!" if entries.is_empty() else "SAMPLE DATA (development capture)"
	var mine_shown := false
	for en in entries:
		list_box.add_child(_row(en))
		mine_shown = mine_shown or bool(en.get("me", false))
	var me: Dictionary = r.get("me", {})
	if not me.is_empty() and not mine_shown:
		list_box.add_child(UIKit.styled("···", "label", UIKit.IVORY_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
		list_box.add_child(_row(me))


func _row(en: Dictionary) -> Control:
	var rank := int(en.get("rank", 0))
	var me := bool(en.get("me", false))
	var medal: Color = [UIKit.AMBER, Color("d9dee8"), Color("e09a5c")][rank - 1] if rank >= 1 and rank <= 3 else Color(UIKit.NAVY, 0.6)
	var p := PanelContainer.new()
	var bg := Color(UIKit.TEAL, 0.2) if me else Color(UIKit.SLATE_HI, 0.7)
	var sb := UIKit.box(bg, UIKit.R_CARD, 2 if me else 0, UIKit.TEAL, 16)
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", sb)
	var h := UIKit.hbox(16)
	var badge := UIKit.chip("%d" % rank, medal, UIKit.NAVY if rank <= 3 else UIKit.IVORY, UIKit.T_LABEL)
	badge.custom_minimum_size = Vector2(64, 44)
	(badge.get_child(0) as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(badge)
	if rank == 1:
		var cr := Icons.IconRect.new("crown", UIKit.AMBER, 26)
		cr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(cr)
	var nm := UIKit.styled(String(en.get("name", "Player")) + ("  (you)" if me else ""), "label", UIKit.IVORY)
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	h.add_child(nm)
	var score := int(en.get("score", 0))
	var txt := Rankings.fmt_time(float(score) / 100.0) if board == Rankings.BOARD_FASTEST else ("%d pts" % score)
	var sl := UIKit.styled(txt, "num", UIKit.AMBER if rank <= 3 else UIKit.IVORY)
	h.add_child(sl)
	p.add_child(h)
	p.accessibility_name = "Rank %d, %s, %s%s" % [rank, en.get("name", ""), txt, ", you" if me else ""]
	return p


func _my_stats() -> Control:
	# (2.3) your numbers as tiles: a big figure over a small label
	var p := UIKit.panel(Color(UIKit.SLATE, 0.95), UIKit.R_PANEL, 22)
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := UIKit.vbox(14)
	p.add_child(v)
	v.add_child(UIKit.styled("YOUR STATS", "overline", UIKit.TEAL))
	var ps := Rankings.period_stats()
	var b := Rankings.bests()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	for pair in [[str(int(ps["points"])), "Points"], [str(int(ps["rounds"])), "Rounds"],
			[Rankings.fmt_time(float(ps["best_run"])), "Best run"], [Rankings.fmt_time(float(b["practice"])), "Practice best"]]:
		var tile := PanelContainer.new()
		var tb := UIKit.box(Color(UIKit.NAVY, 0.45), UIKit.R_CARD, 0, Color.WHITE, 16)
		tb.content_margin_top = 12
		tb.content_margin_bottom = 12
		tile.add_theme_stylebox_override("panel", tb)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tv := UIKit.vbox(2)
		var num := UIKit.styled(String(pair[0]), "num", UIKit.IVORY)
		num.add_theme_font_size_override("font_size", 32)
		tv.add_child(num)
		var cap := UIKit.styled(String(pair[1]), "caption", UIKit.IVORY_MUTED)
		tv.add_child(cap)
		tile.add_child(tv)
		grid.add_child(tile)
	v.add_child(grid)
	return p


## Development captures only (--rank-sample): labelled sample rows.
func _sample(_id: String, _friends: bool, _first: int, _n: int, done: Callable) -> void:
	var names := ["Sleepy Otter 42", "Comfy Panda 38", "Moonlit Fox 17", "Snug Puffin 37", "Drowsy Newt 76", "Quiet Frog 28", "Bouncy Koala 61", "Dreamy Gecko 12"]
	var out: Array = []
	for i in names.size():
		var sc := 980 - i * 85 if board == Rankings.BOARD_POINTS else 7420 + i * 610
		out.append({"rank": i + 1, "name": names[i], "score": sc, "me": i == 4})
	done.call({"ok": true, "entries": out, "me": {}, "sample": true})
