class_name SeasonScreen
extends Screen
## Season Pass (V6): Season 1 · After Hours.  V7 layout (owner screenshot
## IMG_3017: the header and a service paragraph pushed the Premium row and
## Claim below the screen; name cards were empty strips).
##
##   top     Back, the navigation bar and the Coins chip (one 44 pt row)
##   header  one row: the season, your tier, the progress bar with the XP to
##           the next tier, and Claim all (n), or "Rewards unavailable right
##           now" when claiming can't work
##   track   the tiers on one horizontal track (finger swipes scroll it from
##           anywhere; a swipe never claims): every tier column has its Free
##           reward above and its Premium reward below, both rows always
##           whole.  The track lives in a region that takes the height the
##           header leaves and never asks for more; the cells size themselves
##           from it (V6 kept a 132-unit minimum that guaranteed overflow)
##   Pass 9  100 tiers (docs/pass9/season.md):
##           nav    one 44 pt row on top of the track: "You're at Tier 37"
##                  (scrolls to your tier), "Next reward · Tier 40 · 1,050
##                  XP" (scrolls to it), and the milestone shortcuts 30, 50
##                  and 100; 50 and 100 show their featured skin's face (the
##                  real portrait when the skin's art is in the build, a
##                  neutral head otherwise)
##           runs   a run of progress tiers (no reward on either track) is
##                  one narrow column ("36–39", a step per tier): the track
##                  shows every tier honestly and never advertises a reward
##                  that isn't there (58 columns for 100 tiers)
##           detail a featured skin adds its description, what it includes
##                  and a live preview slowly swaying around its three-quarter
##                  view (still under Reduced Motion); a progress run explains itself and offers the
##                  next reward; a claim waiting for the service, or a tier
##                  the game service doesn't have yet, says so
##   detail  the selected reward: its picture (an emote plays on a small live
##           runner), name, type, tier and track, its state, why an action is
##           unavailable, and one action fixed at the bottom
##   Pass 8  the same side panel has two pages, "Challenges" and "Reward":
##           Challenges · Earn Season XP (three daily and three weekly goals,
##           their progress, +XP and local reset time, one pinned goal) opens
##           first; tapping a reward shows its detail.  The header and the
##           track are untouched, so Free and Premium stay whole.
##
## States kept apart: progression (locked / earned), Premium entitlement,
## claimed, and whether claiming works right now (the service).  A reward can
## be earned while claiming is unavailable: it then reads "Earned", never
## "Ready to claim" over a dead button.  Rules shown and enforced by the
## service: XP only from eligible online rounds (never from Coins), no paid
## tier skips, Premium bought later lets you claim every Premium reward
## already earned, claiming is idempotent, claimed rewards are permanent.

## V6's fixed cell size (kept for callers); V7 cells size from the region.
const CELL := 132.0
const GAP := 8.0
const TIER_H := 28.0
## cell width : height
const CELL_ASPECT := 0.8
const CELL_MAX_H := 240.0
## the caption under a cell's art ("Outfit", "50 Coins")
const CAPTION_H := 24.0
const CAPTION_FS := 19
## the detail panel's share of the row beside the track (track 2.7 : 1)
const TRACK_RATIO := 2.7

var sid := "s1"
var track_scroll: ScrollContainer
var track_region: Control
var track_panel: PanelContainer
var columns: Dictionary = {}          # tier -> Control
var cells: Array = []                 # RewardCell
var tier_lbl: Label
var xp_lbl: Label
var bar: ProgressBar
var premium_chip: Label
var claim_all_btn: Button
## the header's short status when claiming is unavailable
var banner: Label
var detail_box: VBoxContainer
var detail_panel: PanelContainer
var _legend: Array = []
var cell_size := CELL
var cell_w := CELL * CELL_ASPECT
var focus_tier := 1
var focus_track := "free"
var _busy := false
var _d: Dictionary = {}
var _preview: Preview3D
var _preview_view: CharacterView
var _preview_emote := -1
var _preview_t := 0.0
## Pass 8: the side panel's pages ("challenges" | "reward") and the
## Challenges page's parts (ChallengeCard per goal, the group headers)
var side_page := "challenges"
var _side: VBoxContainer
var _tabs: Dictionary = {}
var challenge_page: VBoxContainer
var challenge_cards: Array = []
var _ch: Dictionary = {}
var _ch_timer: Timer
## Pass 9: the navigation row (NavChip: now, next reward, milestones by
## tier), the progress-run columns (ProgressRun), every column once in
## track order, and the featured skin on the live preview ("" = none)
var nav_row: HBoxContainer
var now_chip: NavChip
var next_chip: NavChip
var milestone_chips: Dictionary = {}
var runs: Array = []
var _cols: Array = []
var _preview_skin := ""
var _turn := 0.0
## the width of a run column relative to a reward column
const RUN_ASPECT := 0.56
## the featured preview's slow sway around its three-quarter view (phase
## radians a second; how far it turns each way): the face and both sides,
## always in the key light; still under Reduced Motion
const TURN_RATE := 0.55
const TURN_SWING := 0.85


func build() -> void:
	sid = Catalogue.current_season_id()
	if App.stage:
		App.stage.set_mode("home")
		App.sync_stage_local()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	TitleScreen.add_shades(self, 0.6, 0.45)
	back_action = func() -> void: NavShell.go_hub()
	content.add_theme_constant_override("separation", UIKit.SP_M)
	nav_bar("pass")

	var mid := UIKit.hbox(UIKit.SP_L)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(mid)
	var left := UIKit.vbox(UIKit.SP_M)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = TRACK_RATIO
	mid.add_child(left)
	left.add_child(_header())
	track_panel = UIKit.panel(Color(UIKit.SLATE, 0.93), UIKit.R_PANEL, UIKit.PAD_PANEL)
	track_panel.name = "TrackPanel"
	var tw := UIKit.vbox(UIKit.SP_S)
	track_panel.add_child(tw)
	tw.add_child(_nav_row())
	var tv := UIKit.hbox(UIKit.SP_S)
	tv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tw.add_child(tv)
	tv.add_child(_track_legend())
	track_scroll = UIKit.scroll_area(true)
	track_scroll.name = "Track"
	track_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	track_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track_scroll.follow_focus = true
	tv.add_child(track_scroll)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(GAP))
	track_scroll.add_child(row)
	# Pass 9: a run of progress tiers is one column
	var run_at := {}
	for run in Economy.progress_runs(sid):
		run_at[int(run[0])] = run
	var past := 0
	for t in Catalogue.season_tiers(sid):
		var n := int(t["tier"])
		if n <= past:
			continue
		if run_at.has(n):
			row.add_child(_run_column(int(run_at[n][0]), int(run_at[n][1])))
			past = int(run_at[n][1])
		else:
			row.add_child(_column(t))
	# the track takes the height the header leaves, and never more
	track_region = UIKit.region(track_panel)
	track_region.name = "TrackRegion"
	left.add_child(track_region)
	track_region.resized.connect(_fit_cells)

	detail_panel = UIKit.panel(Color(UIKit.SLATE, 0.96), UIKit.R_PANEL, 16)
	detail_panel.name = "DetailPanel"
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.size_flags_stretch_ratio = 1.0
	detail_panel.custom_minimum_size.x = 280.0
	mid.add_child(UIKit.region(detail_panel))
	(detail_panel.get_parent() as Control).size_flags_stretch_ratio = 1.0
	(detail_panel.get_parent() as Control).custom_minimum_size.x = 280.0
	_build_detail()
	_build_challenges()

	var st := season()
	var tier := maxi(1, Economy.tier_for_xp(sid, int(st["xp"])))
	var first := Wallet.claimable(sid) if bool(Wallet.can_transact()["ok"]) else []
	if not first.is_empty():
		focus(int(first[0]["tier"]), String(first[0]["track"]))
	else:
		# the next reward ahead (Pass 9: past progress tiers), else the last tier
		var nxt := Economy.next_reward_tier(sid, tier, bool(st["premium"]))
		var at := nxt if nxt > 0 else Economy.max_tier(sid)
		focus(at, best_track(at))
	_refresh()
	show_side("challenges")
	_scroll_to.call_deferred(focus_tier)
	Wallet.changed.connect(_refresh)
	Wallet.challenge_completed.connect(_on_challenge_completed)
	if Cloud.signed_in():
		Wallet.refresh()
	focus_first(claim_all_btn if claim_all_btn.visible else _cell(focus_tier, focus_track))
	UIKit.fade_in(track_panel)


## One row: the season, tier and Premium state, the bar with the XP to the
## next tier, and Claim all (or the short unavailable status).
func _header() -> Control:
	var p := UIKit.panel(Color(UIKit.SLATE, 0.93), UIKit.R_PANEL, 18)
	p.name = "Header"
	var h := UIKit.hbox(UIKit.SP_L)
	p.add_child(h)
	var em := CommerceArt.Pic.new("glyph", "moon", UIKit.AMBER, 46)
	em.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(em)
	var v := UIKit.vbox(6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(v)
	var s: Dictionary = Catalogue.season(sid)
	var tr := UIKit.hbox(UIKit.SP_M)
	var title := UIKit.styled("Season %d · %s" % [int(s.get("number", 1)), String(s.get("name", ""))], "headline")
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_stretch_ratio = 0.01
	tr.add_child(title)
	tier_lbl = UIKit.styled("", "num", UIKit.TEAL)
	tier_lbl.add_theme_font_size_override("font_size", 24)
	tier_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tr.add_child(tier_lbl)
	premium_chip = UIKit.styled("", "label", UIKit.AMBER)
	premium_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tr.add_child(premium_chip)
	v.add_child(tr)
	var br := UIKit.hbox(UIKit.SP_M)
	bar = ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("background", UIKit.box(Color(UIKit.NAVY, 0.7), 5, 0, Color.WHITE, 0))
	bar.add_theme_stylebox_override("fill", UIKit.box(UIKit.TEAL, 5, 0, Color.WHITE, 0))
	bar.max_value = 1.0
	bar.step = 0.001
	br.add_child(bar)
	xp_lbl = UIKit.styled("", "caption", UIKit.IVORY_MUTED)
	xp_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	br.add_child(xp_lbl)
	v.add_child(br)
	claim_all_btn = UIKit.primary("Claim all", Vector2(0, UIKit.row_h()), 24)
	claim_all_btn.name = "ClaimAll"
	claim_all_btn.custom_minimum_size.x = UIKit.row_h() * 2.4
	claim_all_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	claim_all_btn.pressed.connect(_claim_all)
	h.add_child(claim_all_btn)
	banner = UIKit.styled("Rewards unavailable right now", "label", UIKit.AMBER, HORIZONTAL_ALIGNMENT_RIGHT)
	banner.name = "Unavailable"
	banner.custom_minimum_size.y = UIKit.row_h()
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	banner.visible = false
	h.add_child(banner)
	return p


func _track_legend() -> Control:
	var v := UIKit.vbox(int(GAP))
	v.name = "Legend"
	v.add_child(spacer(TIER_H))
	for spec in [["Free", UIKit.IVORY], ["Premium", UIKit.AMBER]]:
		var l := UIKit.styled(String(spec[0]), "overline", spec[1])
		l.custom_minimum_size = Vector2(0, CELL + 12.0)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		v.add_child(l)
		_legend.append(l)
	return v


## Cells fill the track's height exactly: both rows, the tier numbers, the
## gaps and the scrollbar fit the region the header (and, Pass 9, the
## navigation row) leaves (phone and iPad alike); width follows the height.
## No minimum beyond a 44 pt target.
func _fit_cells() -> void:
	if not is_instance_valid(track_region):
		return
	var h := track_region.size.y
	if h < 2.0:
		return
	var sb := track_panel.get_theme_stylebox("panel")
	var inner := h - sb.get_margin(SIDE_TOP) - sb.get_margin(SIDE_BOTTOM)
	if is_instance_valid(nav_row):
		inner -= nav_row.get_combined_minimum_size().y + UIKit.SP_S
	var hbar := track_scroll.get_h_scroll_bar().get_combined_minimum_size().y
	var c := floorf((inner - hbar - TIER_H - GAP * 2.0 - 2.0) * 0.5)
	c = clampf(c, UIKit.touch_min(), CELL_MAX_H)
	var w := floorf(clampf(c * CELL_ASPECT, UIKit.touch_min(), 210.0))
	if absf(c - cell_size) < 1.0 and absf(w - cell_w) < 1.0:
		return
	cell_size = c
	cell_w = w
	for cell in cells:
		(cell as Control).custom_minimum_size = Vector2(w, c)
	for l in _legend:
		(l as Control).custom_minimum_size.y = c
	for run in runs:
		(run as Control).custom_minimum_size = Vector2(run_w(), c * 2.0 + GAP)
	for col in _cols:
		((col as Control).get_meta(&"tier_label") as Control).custom_minimum_size.x = run_w() if (col as Control).has_meta(&"run") else w
	_scroll_to.call_deferred(focus_tier)


## Pass 9: a progress-run column's width (narrower than a reward, never
## under 44 pt).
func run_w() -> float:
	return floorf(maxf(UIKit.touch_min(), cell_w * RUN_ASPECT))


func _column(t: Dictionary) -> Control:
	var tier := int(t["tier"])
	var v := UIKit.vbox(int(GAP))
	v.name = "Tier_%d" % tier
	var lbl := UIKit.styled("%d" % tier, "num", UIKit.IVORY_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	lbl.custom_minimum_size = Vector2(CELL * CELL_ASPECT, TIER_H)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.add_child(lbl)
	for track in ["free", "premium"]:
		var cell := RewardCell.new()
		cell.setup(self, tier, track)
		cell.pressed.connect(_on_cell.bind(tier, track))
		v.add_child(cell)
		cells.append(cell)
	columns[tier] = v
	v.set_meta(&"tier_label", lbl)
	v.set_meta(&"tiers", [tier, tier])
	_cols.append(v)
	return v


## Pass 9: one column for a run of progress tiers (no reward on either
## track): its tier range on top and one tall card with a step per tier.
func _run_column(first: int, last: int) -> Control:
	var v := UIKit.vbox(int(GAP))
	v.name = "Tiers_%d_%d" % [first, last]
	var lbl := UIKit.styled(("%d–%d" % [first, last]) if last > first else "%d" % first, "num", UIKit.IVORY_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	lbl.custom_minimum_size = Vector2(CELL * CELL_ASPECT * RUN_ASPECT, TIER_H)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UIKit.fit_text(lbl, [UIKit.T_LABEL, 19, 17, 15])
	v.add_child(lbl)
	var run := ProgressRun.new()
	run.setup(self, first, last)
	run.pressed.connect(_on_run.bind(first))
	v.add_child(run)
	runs.append(run)
	for n in range(first, last + 1):
		columns[n] = v
	v.set_meta(&"tier_label", lbl)
	v.set_meta(&"tiers", [first, last])
	v.set_meta(&"run", run)
	_cols.append(v)
	return v


func _cell(tier: int, track: String) -> Control:
	for c in cells:
		if c.tier == tier and c.track == track:
			return c
	return null


## Pass 9: the progress-run column holding `tier` (null for a reward tier).
func run_of(tier: int) -> ProgressRun:
	for r in runs:
		if r.first <= tier and tier <= r.last:
			return r
	return null


## A tap on a cell selects it; a blank Free slot explains that tier's
## Premium reward instead.
func _on_cell(tier: int, track: String) -> void:
	if track == "free" and Economy.reward_at(sid, tier, "free").is_empty():
		focus(tier, "premium", true)
	else:
		focus(tier, track)


## Pass 9: a tap on a progress run explains it (the player's own tier when
## it is inside the run).
func _on_run(first: int) -> void:
	var r := run_of(first)
	var tier := clampi(current_tier(), r.first, r.last) if r != null else first
	focus(tier, "progress")


## Bring a tier's column into view (a little left of centre), clamped.
## Pass 9: `animate` (the navigation's jumps) glides there unless Reduced
## Motion is on; a finger on the track always wins.
func _scroll_to(tier: int, animate: bool = false) -> void:
	await get_tree().process_frame
	if not is_instance_valid(track_scroll) or not columns.has(tier) or TouchScroll.is_dragging(track_scroll):
		return
	var col: Control = columns[tier]
	var room := track_scroll.get_h_scroll_bar().max_value - track_scroll.size.x
	var to := int(clampf(col.position.x - track_scroll.size.x * 0.35, 0.0, maxf(0.0, room)))
	if animate and not UIKit.reduced_motion() and is_inside_tree():
		Motion.animate(track_scroll, "scroll_horizontal", to, Motion.CAMERA)
	else:
		Motion.stop(track_scroll, "scroll_horizontal")
		track_scroll.scroll_horizontal = to


# ------------------------------------------------------------------ navigation
## Pass 9: the row above the track.  Every chip is a whole 44 pt target and
## only moves the track and the detail (no claim, no purchase here).
func _nav_row() -> Control:
	nav_row = UIKit.hbox(UIKit.SP_S)
	nav_row.name = "TrackNav"
	now_chip = NavChip.new()
	now_chip.setup(self, "NavNow", "You're at", "Tier 1", "flag")
	now_chip.pressed.connect(jump_current)
	nav_row.add_child(now_chip)
	next_chip = NavChip.new()
	next_chip.setup(self, "NavNext", "Next reward", "", "star")
	next_chip.pressed.connect(jump_next_reward)
	nav_row.add_child(next_chip)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nav_row.add_child(gap)
	var featured := Catalogue.season_featured(sid)
	for m in Catalogue.season_milestones(sid):
		var chip := NavChip.new()
		var skin := featured_skin(int(m)) if featured.has(int(m)) else ""
		chip.setup(self, "Milestone_%d" % int(m), "Tier", "%d" % int(m), "" if skin != "" else "medal", skin)
		chip.pressed.connect(jump_to.bind(int(m)))
		nav_row.add_child(chip)
		milestone_chips[int(m)] = chip
	return nav_row


## The wallet's Season state, read once per frame (a refresh of 88 cells
## and their columns asks for it a few hundred times); a wallet change
## (_refresh) reads it again at once.
var _st: Dictionary = {}
var _st_frame := -1


func season() -> Dictionary:
	var f := Engine.get_process_frames()
	if f != _st_frame or _st.is_empty():
		_st = Wallet.season_state(sid)
		_st_frame = f
	return _st


## The tier the player's recorded Season XP reaches (at least 1).
func current_tier() -> int:
	return maxi(1, Economy.tier_for_xp(sid, int(season()["xp"])))


## Pass 9: the featured skin at a tier ("outfit:dr_doom"; "" when none).
func featured_skin(tier: int) -> String:
	for track in ["premium", "free"]:
		var id := String(Economy.reward_at(sid, tier, track).get("item", ""))
		if id.begins_with("outfit:"):
			return id
	return ""


## The cell a jump to `tier` selects: a progress tier's run, a featured
## skin, a reward ready to claim, else the Free reward (the Premium one when
## there is none).
func best_track(tier: int) -> String:
	if not Economy.has_reward(sid, tier):
		return "progress"
	if Catalogue.season_featured(sid).has(tier) and not Economy.reward_at(sid, tier, "premium").is_empty():
		return "premium"
	for track in ["free", "premium"]:
		if cell_state(tier, track) == "claimable":
			return track
	return "free" if not Economy.reward_at(sid, tier, "free").is_empty() else "premium"


func jump_to(tier: int) -> void:
	var t := clampi(tier, 1, Economy.max_tier(sid))
	focus(t, best_track(t))
	_scroll_to(t, true)


func jump_current() -> void:
	jump_to(current_tier())


func jump_next_reward() -> void:
	var st := season()
	var n := Economy.next_reward_tier(sid, current_tier(), bool(st["premium"]))
	jump_to(n if n > 0 else Economy.max_tier(sid))


func _refresh_nav() -> void:
	if not is_instance_valid(nav_row):
		return
	var st := season()
	var xp := int(st["xp"])
	var tier := current_tier()
	now_chip.set_text_lines("You're at", "Tier %d" % tier)
	now_chip.accessibility_name = "Go to your tier, Season Pass Tier %d of %d" % [tier, Economy.max_tier(sid)]
	var n := Economy.next_reward_tier(sid, tier, bool(st["premium"]))
	if n > 0:
		var need := maxi(0, Economy.tier_xp(sid, n) - xp)
		next_chip.set_text_lines("Next reward", "Tier %d · %s XP" % [n, Catalogue.format_coins(need)])
		next_chip.accessibility_name = "Go to the next reward, Tier %d, %s Season XP away" % [n, Catalogue.format_coins(need)]
	else:
		next_chip.set_text_lines("Next reward", "All reached")
		next_chip.accessibility_name = "Every reward tier reached. Go to Tier %d" % Economy.max_tier(sid)
	for m in milestone_chips:
		var chip: NavChip = milestone_chips[m]
		var skin := featured_skin(int(m)) if Catalogue.season_featured(sid).has(int(m)) else ""
		var what := Catalogue.display_name(skin) if skin != "" else _tier_summary(int(m))
		chip.reached = tier >= int(m)
		chip.accessibility_name = "Go to Tier %d: %s%s" % [int(m), what, ", reached" if tier >= int(m) else ""]
		chip.queue_redraw()


## "Library Cardigan and Season 1 Finisher" (a tier's rewards, for screen readers).
func _tier_summary(tier: int) -> String:
	var parts: Array = []
	for track in ["premium", "free"]:
		var r := Economy.reward_at(sid, tier, track)
		if not r.is_empty():
			parts.append(reward_name(r))
	return " and ".join(parts) if not parts.is_empty() else "progress tier"


# ------------------------------------------------------------------ state
## Can rewards be claimed right now?  {ok, message}; the reason is short and
## product-facing (the full technical reason is in the release notes).
func claim_status() -> Dictionary:
	var can := Wallet.can_transact()
	if bool(can["ok"]):
		return {"ok": true, "reason": ""}
	var reason := ""
	match Wallet.service_state():
		"off":
			reason = "This test build has no game service, so rewards can't be claimed yet."
		"signed_out":
			reason = "Sign in with Game Center to claim rewards."
		"syncing":
			reason = "Checking your account…"
		"offline":
			reason = "You're offline. Claiming comes back when you reconnect."
		_:
			reason = String(can["message"])
	return {"ok": false, "reason": reason}


func _refresh() -> void:
	if not is_inside_tree():
		return
	_st_frame = -1
	var st := season()
	var xp := int(st["xp"])
	var prog := Economy.tier_progress(sid, xp)
	tier_lbl.text = "Tier %d / %d" % [maxi(1, int(prog["tier"])), Economy.max_tier(sid)]
	bar.value = float(prog["frac"])
	if int(prog["next"]) < 0:
		xp_lbl.text = "Every tier reached"
	else:
		xp_lbl.text = "%s / %s XP" % [Catalogue.format_coins(int(prog["into"])), Catalogue.format_coins(int(prog["into"]) + int(prog["need"]))]
	var prem := bool(st["premium"])
	premium_chip.text = "Premium" if prem else "Free track"
	premium_chip.add_theme_color_override("font_color", UIKit.AMBER if prem else UIKit.IVORY_MUTED)
	var n := Wallet.claimable(sid).size()
	var ok := bool(claim_status()["ok"])
	claim_all_btn.visible = ok
	banner.visible = not ok
	claim_all_btn.text = ("Claim all (%d)" % n) if n > 0 else "Nothing to claim"
	claim_all_btn.disabled = n == 0 or _busy
	tier_lbl.accessibility_name = "Season Pass tier %d of %d" % [maxi(1, int(prog["tier"])), Economy.max_tier(sid)]
	var tier := int(prog["tier"])
	for col in _cols:
		var span: Array = (col as Control).get_meta(&"tiers")
		var lbl: Label = (col as Control).get_meta(&"tier_label")
		lbl.add_theme_color_override("font_color", UIKit.TEAL if int(span[0]) <= tier and tier <= int(span[1]) else (UIKit.IVORY if int(span[1]) < tier else UIKit.IVORY_DIM))
	for c in cells:
		c.refresh()
	for r in runs:
		r.refresh()
	_refresh_nav()
	_refresh_detail()
	_refresh_challenges()


func cell_state(tier: int, track: String) -> String:
	var st := season()
	return Economy.cell_state(sid, tier, track, int(st["xp"]), bool(st["premium"]), st["claimed"])


## What a cell shows: the rules' state, except that a claimable reward is
## "earned" while claiming is unavailable (no claim affordance then).
## Pass 9: "pending" while its claim waits in the outbox (it finishes by
## itself), "service_update" when the game service's table doesn't have the
## tier yet (an older service: earned, never a Claim that does nothing).
func display_state(tier: int, track: String) -> String:
	var s := cell_state(tier, track)
	if s == "claimable":
		if Wallet.claim_pending(sid, tier, track):
			return "pending"
		if tier > int(season()["service_tiers"]):
			return "service_update"
		if not bool(claim_status()["ok"]):
			return "earned"
	return s


static func reward_name(r: Dictionary) -> String:
	if r.is_empty():
		return ""
	if r.has("coins"):
		return "%s Coins" % Catalogue.format_coins(int(r["coins"]))
	return Catalogue.display_name(String(r["item"]))


static func reward_type(r: Dictionary) -> String:
	if r.has("coins"):
		return "Coins"
	return Catalogue.type_label(String(r.get("item", "")))


## The short caption under a cell's art: what it is.
static func reward_caption(r: Dictionary) -> String:
	if r.is_empty():
		return ""
	if r.has("coins"):
		return "%s Coins" % Catalogue.format_coins(int(r["coins"]))
	return reward_type(r)


# ------------------------------------------------------------------ detail
var _from_empty := false


## Select a reward cell (or, Pass 9, a progress tier: track "progress",
## also chosen for any tier without a reward) and show its detail.
func focus(tier: int, track: String, from_empty: bool = false) -> void:
	if not Economy.has_reward(sid, tier):
		track = "progress"
	elif track == "progress":
		track = best_track(tier)
	focus_tier = tier
	focus_track = track
	_from_empty = from_empty
	for c in cells:
		UIKit.set_selected(c, c.tier == tier and c.track == track)
	for r in runs:
		UIKit.set_selected(r, track == "progress" and r.first <= tier and tier <= r.last)
	_refresh_detail()
	show_side("reward")


func _build_detail() -> void:
	var v := UIKit.vbox(UIKit.SP_M)
	v.name = "RewardPage"
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_side_box().add_child(v)
	var sc := UIKit.scroll_area()
	sc.name = "DetailInfo"
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	detail_box = UIKit.vbox(UIKit.SP_S)
	detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(detail_box)
	var over := UIKit.styled("", "overline", UIKit.IVORY_MUTED)
	# (one line that never widens the panel: "Tiers 41–44 · Progress")
	UIKit.fit_text(over, [UIKit.T_OVERLINE, 15, 14])
	detail_box.add_child(over)
	var art := RewardArt.new()
	art.name = "DetailArt"
	art.custom_minimum_size = Vector2(0, 180)
	art.screen = self
	detail_box.add_child(art)
	# Pass 9: a featured skin whose art isn't in this build says so plainly,
	# drawn inside its neutral picture (art.note); the label keeps the text
	# for screen readers and tests
	var note := UIKit.styled("", "caption", UIKit.IVORY_MUTED)
	note.name = "ArtNote"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 18)
	note.visible = false
	detail_box.add_child(note)
	var name_l := UIKit.styled("", "headline")
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_box.add_child(name_l)
	var type_l := UIKit.styled("", "caption", UIKit.IVORY_MUTED)
	detail_box.add_child(type_l)
	var state_l := UIKit.styled("", "body", UIKit.IVORY)
	state_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_box.add_child(state_l)
	# Pass 9: a featured skin's description and what it includes (after the
	# state, so its lock reason stays in view on the smallest phone)
	var blurb_l := UIKit.styled("", "body", UIKit.AMBER_HI)
	blurb_l.name = "Blurb"
	blurb_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_box.add_child(blurb_l)
	var incl_l := UIKit.styled("", "caption", UIKit.IVORY_MUTED)
	incl_l.name = "Includes"
	incl_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_box.add_child(incl_l)
	# why the action is unavailable, and the action itself, stay at the
	# bottom of the panel, outside the scroll: never below the fold
	var reason_l := UIKit.styled("", "caption", UIKit.AMBER)
	reason_l.name = "Reason"
	reason_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(reason_l)
	var action := UIKit.secondary("", Vector2(0, UIKit.row_h()), UIKit.T_LABEL + 2)
	action.name = "DetailAction"
	action.pressed.connect(_on_detail_action)
	v.add_child(action)
	_d = {"over": over, "art": art, "note": note, "name": name_l, "type": type_l, "blurb": blurb_l, "includes": incl_l, "state": state_l,
		"reason": reason_l, "action": action, "scroll": sc, "page": v}
	# wrapping labels get their width from the panel's allocated width, so
	# they never report a first-frame height for an unknown width
	detail_panel.resized.connect(_fit_detail)
	(detail_panel.get_parent() as Control).resized.connect(_fit_detail)


## The side panel's inner width, from the region it lives in (which never
## grows), not from the panel itself: a label sized from the panel's own
## width kept a once-widened panel wide (Pass 9: a long action label had
## pushed it past the screen edge on the iPhone SE).
func _side_w() -> float:
	if not is_instance_valid(detail_panel):
		return 0.0
	var sb := detail_panel.get_theme_stylebox("panel")
	var host := detail_panel.get_parent() as Control
	var outer := host.size.x if host != null and host.size.x > 1.0 else detail_panel.size.x
	return outer - sb.get_margin(SIDE_LEFT) - sb.get_margin(SIDE_RIGHT) - 10.0


func _fit_detail() -> void:
	if _d.is_empty() or not is_instance_valid(detail_panel):
		return
	var w := _side_w()
	if w < 10.0:
		return
	for k in ["name", "state", "reason", "note", "blurb", "includes"]:
		(_d[k] as Control).custom_minimum_size.x = w
	# the picture leaves the state and its reason in view on a short panel
	# (iPhone SE: 466 units for the whole Reward page)
	var page := (_d["page"] as Control).size.y
	var h := clampf(w * 0.58, 120.0, 260.0)
	if page > 1.0:
		h = clampf(minf(h, page * 0.3), 110.0, 260.0)
	if focus_track == "progress":
		h = clampf(minf(w * 0.48, maxf(page, 1.0) * 0.28), 100.0, 200.0)
	(_d["art"] as Control).custom_minimum_size.y = h
	if is_instance_valid(_preview):
		_preview.custom_minimum_size = Vector2(0, h)
	# the action's label is set a little smaller rather than widening the
	# panel ("Get Premium in the Shop" on a 323-unit SE panel)
	var action: Button = _d["action"]
	var f := action.get_theme_font("font")
	for fs in [UIKit.T_LABEL + 2, UIKit.T_LABEL, UIKit.T_CAPTION, 18]:
		action.add_theme_font_size_override("font_size", fs)
		if f.get_string_size(action.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 40.0 <= w + 10.0:
			break


func _refresh_detail() -> void:
	if _d.is_empty():
		return
	var action: Button = _d["action"]
	var state_l: Label = _d["state"]
	var reason_l: Label = _d["reason"]
	var art: RewardArt = _d["art"]
	action.visible = true
	action.disabled = false
	reason_l.text = ""
	for k in ["note", "blurb", "includes"]:
		(_d[k] as Label).text = ""
	if focus_track == "progress":
		_refresh_progress_detail()
	else:
		_refresh_reward_detail()
	for k in ["blurb", "includes"]:
		(_d[k] as Label).visible = (_d[k] as Label).text != ""
	art.note = (_d["note"] as Label).text
	art.accessibility_name = art.note
	reason_l.visible = reason_l.text != ""
	action.accessibility_name = "%s, %s%s" % [(_d["name"] as Label).text, action.text, ", unavailable" if action.disabled else ""]
	art.queue_redraw()
	_fit_detail()


func _refresh_reward_detail() -> void:
	var r := Economy.reward_at(sid, focus_tier, focus_track)
	var st := display_state(focus_tier, focus_track)
	var cs := claim_status()
	(_d["over"] as Label).text = "Tier %d · %s" % [focus_tier, "Premium track" if focus_track == "premium" else "Free track"]
	var art: RewardArt = _d["art"]
	art.reward = r
	art.run = []
	art.state = st
	art.request()
	_show_preview(r)
	(_d["name"] as Label).text = reward_name(r) if not r.is_empty() else "No Free reward at this tier"
	(_d["type"] as Label).text = reward_type(r) if not r.is_empty() else ""
	var id := String(r.get("item", ""))
	if id != "":
		(_d["blurb"] as Label).text = Catalogue.blurb(id) if Catalogue.kind(id) == "season_reward" else ""
		var inc := Catalogue.includes_text(id)
		(_d["includes"] as Label).text = ("Includes: " + inc) if inc != "" else ""
		if Catalogue.is_runner_item(id) and not Catalogue.has_art(id):
			(_d["note"] as Label).text = "Preview not available in this build."
	var action: Button = _d["action"]
	var state_l: Label = _d["state"]
	var reason_l: Label = _d["reason"]
	var xp := int(season()["xp"])
	var need := Economy.tier_xp(sid, focus_tier) - xp
	var into := "wallet" if r.has("coins") else "Locker"
	var lead := ("No Free reward at Tier %d. " % focus_tier) if _from_empty else ""
	match st:
		"empty":
			state_l.text = "The Free track skips this tier."
			action.visible = false
		"locked":
			state_l.text = lead + "Reach Tier %d: %s more Season XP from online rounds. No tier skips." % [focus_tier, Catalogue.format_coins(maxi(0, need))]
			if focus_track == "premium" and not bool(season()["premium"]):
				state_l.text += " Premium track: needs Premium too."
			action.visible = false
		"premium_locked":
			state_l.text = lead + "Reached. Premium (%s Coins in the Shop) unlocks it and every Premium reward you've earned." % Catalogue.format_coins(Catalogue.price(String(Catalogue.season(sid).get("premium_item", ""))))
			action.text = "Get Premium in the Shop" if bool(cs["ok"]) else "See Premium in the Shop"
			if not bool(cs["ok"]):
				reason_l.text = String(cs["reason"])
		"claimable":
			state_l.text = lead + "Earned at Tier %d. Claim it to add it to your %s." % [focus_tier, into]
			action.text = "Claim"
			action.disabled = _busy
		"earned":
			state_l.text = lead + "Earned at Tier %d, not claimed yet." % focus_tier
			reason_l.text = String(cs["reason"])
			action.text = "Claim"
			action.disabled = true
		"pending":
			state_l.text = lead + "Earned at Tier %d. Your claim is on its way: it finishes by itself when the game service answers, and never twice." % focus_tier
			action.text = "Claiming…"
			action.disabled = true
		"service_update":
			state_l.text = lead + "Earned at Tier %d, not claimed yet. It stays earned." % focus_tier
			reason_l.text = "The game service hasn't been updated for this tier yet, so it can't be claimed right now."
			action.text = "Claim"
			action.disabled = true
		"claimed":
			if r.has("coins"):
				state_l.text = lead + "Claimed: added to your Coins."
				action.visible = false
			else:
				state_l.text = lead + "Claimed. It's yours to keep, in your Locker."
				action.text = "Wear it in the Locker"


## Pass 9: a progress tier: no reward here, what it leads to, where you are.
func _refresh_progress_detail() -> void:
	var r := run_of(focus_tier)
	var first := r.first if r != null else focus_tier
	var last := r.last if r != null else focus_tier
	(_d["over"] as Label).text = ("Tiers %d–%d · Progress" % [first, last]) if last > first else "Tier %d · Progress" % first
	var art: RewardArt = _d["art"]
	art.reward = {}
	art.run = [first, last]
	art.state = ""
	art.request()
	_show_preview({})
	# the selected run column already shows its steps on the track; on a
	# short panel the words matter more than a second picture of them
	art.visible = (_d["page"] as Control).size.y >= 560.0
	(_d["name"] as Label).text = "Progress tiers" if last > first else "Progress tier"
	(_d["type"] as Label).text = "No reward on either track"
	var xp := int(season()["xp"])
	var tier := current_tier()
	var nxt := last + 1 if last < Economy.max_tier(sid) else -1
	var leads := ""
	if nxt > 0:
		var parts: Array = []
		for track in ["free", "premium"]:
			var w := Economy.reward_at(sid, nxt, track)
			if not w.is_empty():
				parts.append("%s (%s)" % [reward_name(w), "Free" if track == "free" else "Premium"])
		leads = "They count toward Tier %d: %s." % [nxt, " and ".join(parts)] if last > first else "It counts toward Tier %d: %s." % [nxt, " and ".join(parts)]
	var where := ""
	if tier > last:
		where = "Reached."
	elif tier >= first:
		where = "You're at Tier %d." % tier
	else:
		where = "Tier %d needs %s more Season XP." % [first, Catalogue.format_coins(maxi(0, Economy.tier_xp(sid, first) - xp))]
	if nxt > 0 and tier < nxt:
		where += " %s more Season XP to Tier %d." % [Catalogue.format_coins(maxi(0, Economy.tier_xp(sid, nxt) - xp)), nxt]
	(_d["state"] as Label).text = ("%s %s" % [leads, where]).strip_edges()
	var action: Button = _d["action"]
	action.visible = nxt > 0
	action.text = "Show Tier %d" % nxt


## Emote rewards play on one small live runner in the detail (created on
## first use, hidden and not rendered otherwise; one per screen).  Pass 9:
## a featured skin sways slowly on the same runner when its art is in the
## build (swaying around its three-quarter view; still under Reduced
## Motion); without the art the detail keeps its neutral picture.
func _show_preview(r: Dictionary) -> void:
	var art: Control = _d["art"]
	var id := String(r.get("item", ""))
	var eid := TC.EMOTES.find(String(Catalogue.split(id)[1])) if id.begins_with("emote:") else -1
	var skin := id if id.begins_with("outfit:") and Catalogue.season_featured(sid).has(focus_tier) and Catalogue.has_art(id) else ""
	if eid < 0 and skin == "":
		if is_instance_valid(_preview):
			_preview.visible = false
			if _preview_skin != "":
				# give the runner its own look back (the next emote shows on it)
				_preview_skin = ""
				_preview_view.set_appearance(TC.Role.RUNNER, Cosmetics.sanitize(Save.data["cosmetic"]))
				_preview_view.set_facing(PI + 0.3)
				_preview.cam.fov = 32.0
				_preview.aim(Vector3(0, 1.0, 3.4), Vector3(0, 0.82, 0))
		art.visible = true
		_preview_emote = -1
		return
	if not is_instance_valid(_preview):
		_preview = Preview3D.new(Vector2i(64, 64))
		_preview.name = "EmotePreview"
		_preview.vp.msaa_3d = get_tree().root.msaa_3d
		_preview.aim(Vector3(0, 1.0, 3.4), Vector3(0, 0.82, 0))
		detail_box.add_child(_preview)
		detail_box.move_child(_preview, art.get_index() + 1)
		_preview_view = _preview.show_character(TC.Role.RUNNER, Cosmetics.sanitize(Save.data["cosmetic"]), Vector3.ZERO, PI + 0.3)
		_preview_view.fidgets = false
	_preview.custom_minimum_size = Vector2(0, art.custom_minimum_size.y)
	_preview.visible = true
	art.visible = false
	if skin != "":
		_preview_emote = -1
		if _preview_skin != skin:
			_preview_skin = skin
			_turn = 0.0
			_preview_view.set_appearance(TC.Role.RUNNER, CommerceArt.preview_look(Save.data["cosmetic"], "outfit", String(Catalogue.split(skin)[1])))
			var rs := _preview_view.rs.duplicate()
			rs["emote"] = -1
			rs["emote_t"] = 0.0
			_preview_view.apply_state(rs)
			# the whole figure, framed like the Locker's outfit pictures
			_preview.cam.fov = 36.0
			_preview.aim(Vector3(0, 0.88, 2.7), Vector3(0, 0.8, 0))
		_preview_view.set_facing(PI + 0.35)
		return
	if _preview_skin != "":
		_preview_skin = ""
		_preview_view.set_appearance(TC.Role.RUNNER, Cosmetics.sanitize(Save.data["cosmetic"]))
		_preview_view.set_facing(PI + 0.3)
		_preview.cam.fov = 32.0
		_preview.aim(Vector3(0, 1.0, 3.4), Vector3(0, 0.82, 0))
	if _preview_emote != eid:
		_preview_emote = eid
		_preview_t = 0.0
		_play_preview()


func _play_preview() -> void:
	if not is_instance_valid(_preview_view) or _preview_emote < 0:
		return
	var rs := _preview_view.rs.duplicate()
	rs["emote"] = _preview_emote
	rs["emote_t"] = 1.0
	rs["vel"] = Vector3.ZERO
	rs["on_floor"] = true
	_preview_view.apply_state(rs)
	_preview_view.restart_emote(_preview_emote)


func _process(delta: float) -> void:
	if not is_instance_valid(_preview) or not _preview.is_visible_in_tree():
		return
	# Pass 9: a featured skin sways slowly (Reduced Motion: it stays put)
	if _preview_skin != "":
		if not UIKit.reduced_motion() and is_instance_valid(_preview_view):
			_turn += delta * TURN_RATE
			_preview_view.set_facing(PI + 0.35 + TURN_SWING * sin(_turn))
		return
	# the preview replays its move every few seconds (Reduced Motion: once)
	if _preview_emote < 0:
		return
	_preview_t += delta
	var dur := float(DormStage.EMOTE_S.get(String(TC.EMOTES[_preview_emote]), 2.4)) + 0.8
	if _preview_t >= dur and not UIKit.reduced_motion():
		_preview_t = 0.0
		_play_preview()


func _on_detail_action() -> void:
	if focus_track == "progress":
		var r := run_of(focus_tier)
		var nxt := (r.last if r != null else focus_tier) + 1
		if nxt <= Economy.max_tier(sid):
			jump_to(nxt)
		return
	var st := display_state(focus_tier, focus_track)
	match st:
		"premium_locked":
			ShopScreen.focus_section = "season"
			ShopScreen.focus_item = String(Catalogue.season(sid).get("premium_item", ""))
			NavShell.go("shop")
		"claimable":
			_claim([{"tier": focus_tier, "track": focus_track}])
		"claimed":
			NavShell.open("locker")


func _claim_all() -> void:
	_claim([])


func _claim(which: Array) -> void:
	if _busy or not bool(claim_status()["ok"]):
		return
	_busy = true
	_refresh()
	var r: Dictionary = await Wallet.claim(sid, which)
	_busy = false
	if not is_inside_tree():
		return
	if bool(r.get("ok", false)):
		var got: Array = r.get("claimed", [])
		if not got.is_empty():
			Sfx.play("pickup")
			UIKit.toast(self, ("Claimed %d reward%s" % [got.size(), "" if got.size() == 1 else "s"]) if got.size() != 1 else "Claimed!", 2.0)
		elif String(r.get("message", "")) == "":
			# another device or a retried request claimed it first, or this
			# screen was a step behind the service (the reply's snapshot has
			# already refreshed it)
			var sk: Array = r.get("skipped", [])
			var dup := sk.all(func(x: Variant) -> bool: return x is Dictionary and String(x.get("reason", "")) == "already_claimed")
			UIKit.toast(self, "Already claimed" if dup else "Nothing claimed: your Season Pass was refreshed", 2.0)
		if String(r.get("message", "")) != "":
			dialog(String(r["message"]))
	else:
		dialog(String(r.get("message", "")))
	_refresh()


## One reward cell on the track: its picture, what it is, and a small state
## mark in the corner (lock, plus, check).  Premium cells carry a thin gold
## edge; blank Free slots stay quiet.
class RewardCell:
	extends Button
	var screen: SeasonScreen
	var tier := 0
	var track := "free"
	var art: RewardArt
	var state := ""

	func setup(s: SeasonScreen, t: int, tr: String) -> void:
		screen = s
		tier = t
		track = tr
		name = "Cell_%d_%s" % [t, tr]
		var reward := Economy.reward_at(s.sid, t, tr)
		UIKit.make_card(self, Vector2(SeasonScreen.CELL * SeasonScreen.CELL_ASPECT, SeasonScreen.CELL), Color(UIKit.SLATE_HI, 0.96))
		var f := UIKit.face_of(self)
		if reward.is_empty():
			# a blank Free slot: quiet, aligned, still tappable (it explains
			# the tier's Premium reward)
			var q := UIKit.box(Color(UIKit.SLATE_LO, 0.18), UIKit.R_CARD, 0, Color.WHITE, 0)
			var qs := UIKit.box(Color(UIKit.SLATE_LO, 0.4), UIKit.R_CARD, 2, UIKit.TEAL, 0)
			f.styles = {"normal": q, "hover": q, "pressed": q, "disabled": q, "selected": qs}
		elif tr == "premium":
			var bg := UIKit.SLATE_HI.lerp(Color("6a5226"), 0.2)
			var n := UIKit.card_box(Color(bg, 0.97), UIKit.R_CARD, 1.0)
			n.border_width_top = 2
			n.border_color = Color(UIKit.AMBER, 0.55)
			var sel := UIKit.card_box(Color(bg.lightened(0.04), 0.97), UIKit.R_CARD, 1.0)
			sel.set_border_width_all(3)
			sel.border_color = UIKit.TEAL
			f.styles = {"normal": n, "hover": UIKit._with_bg(n, bg.lightened(0.05)), "pressed": UIKit.card_box(bg.darkened(0.08), UIKit.R_CARD, 0.0),
				"disabled": n, "selected": sel}
		art = RewardArt.new()
		art.screen = s
		art.cell = self
		art.reward = reward
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		f.add_child(art)
		art.request()

	func refresh() -> void:
		state = screen.display_state(tier, track)
		art.state = state
		art.queue_redraw()
		disabled = false
		var r := Economy.reward_at(screen.sid, tier, track)
		var label: String = {"locked": "locked", "premium_locked": "earned, needs Premium", "claimable": "ready to claim",
			"earned": "earned, claiming unavailable right now", "claimed": "claimed", "empty": "no Free reward",
			"pending": "earned, claim on its way", "service_update": "earned, the game service needs an update to claim it"}.get(state, state)
		accessibility_name = "Tier %d %s: %s, %s" % [tier, track, SeasonScreen.reward_name(r) if not r.is_empty() else "none", label]


## A reward's picture (cell or detail): a cached portrait of the real runner
## for outfits (full body), hats (close) and shoes (feet), the refined emote
## glyph, the badge, the name card as equipped (your name), or a Coin pile;
## in a cell also its caption and state mark.  Locked art stays readable
## (slightly muted), never darkened out.
class RewardArt:
	extends Control
	var screen: SeasonScreen
	var cell: Button
	var reward: Dictionary = {}
	## Pass 9: a progress run [first, last] (the detail's picture of it), and
	## a line drawn at the foot of the detail's picture ("Preview not
	## available in this build.")
	var run: Array = []
	var note := ""
	var state := ""
	var tex: Texture2D
	var pic_key := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func request() -> void:
		tex = null
		pic_key = ""
		if reward.has("item") and Catalogue.is_runner_item(String(reward["item"])):
			var id := String(reward["item"])
			var parts := Catalogue.split(id)
			var f := String(parts[0])
			if Cosmetics.entry(f, String(parts[1])).is_empty():
				queue_redraw()
				return
			var framing := CommerceArt.framing_for(f)
			if framing != "" and f != "emote":
				var look := CommerceArt.preview_look(Save.data["cosmetic"], f, String(parts[1]))
				var ps := Portraits.shared()
				pic_key = Portraits.key_for(look, TC.Role.RUNNER, framing)
				var t := ps.portrait(look, TC.Role.RUNNER, "pass:%s%s" % [id, "" if cell else ":detail"], framing)
				if ps.has_picture(pic_key):
					tex = t
				elif not ps.portrait_ready.is_connected(_on_pic):
					ps.portrait_ready.connect(_on_pic)
		queue_redraw()

	func _on_pic(k: String, t: Texture2D) -> void:
		if k == pic_key and is_instance_valid(self):
			tex = t
			queue_redraw()

	## The art's rect: the cell minus its padding and caption; the whole
	## control in the detail.
	func art_rect() -> Rect2:
		if cell == null:
			return Rect2(Vector2.ZERO, size)
		var pad := 8.0
		return Rect2(Vector2(pad, pad), Vector2(size.x - pad * 2.0, size.y - pad * 2.0 - SeasonScreen.CAPTION_H))

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if cell == null:
			draw_style_box(UIKit.box(Color(UIKit.NAVY, 0.38), UIKit.R_SMALL), r)
		if not run.is_empty() and screen != null:
			SeasonScreen.draw_steps(self, r.grow(-10.0), int(run[0]), int(run[1]), screen.current_tier(), true)
			return
		if cell == null and note != "":
			var nf := UIKit.font_w(500)
			var nfs := 17
			while nfs > 13 and nf.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs).x > size.x - 16.0:
				nfs -= 1
			draw_string(nf, Vector2(8.0, size.y - 10.0), note, HORIZONTAL_ALIGNMENT_CENTER, size.x - 16.0, nfs, UIKit.IVORY_MUTED)
		if reward.is_empty():
			# a quiet dash, centred
			var c0 := size * 0.5
			draw_line(c0 + Vector2(-8, 0), c0 + Vector2(8, 0), Color(UIKit.IVORY, 0.25), 3.0, true)
			return
		var dim := state == "locked"
		var ar := art_rect()
		var c := ar.get_center()
		var s := minf(ar.size.x, ar.size.y)
		if reward.has("coins"):
			CommerceArt.coin_pile(self, c, s * 0.28, int(reward["coins"]), dim)
		else:
			var id := String(reward["item"])
			var kind := String(Catalogue.split(id)[0])
			if kind == "badge":
				CommerceArt.badge(self, id, c, s * 0.44, dim)
			elif kind == "card":
				var w := ar.size.x * (0.96 if cell else 0.86)
				var h := minf(w / 2.5, ar.size.y * 0.8)
				var nm := Save.player_name()
				CommerceArt.name_card(self, Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h)), id, nm,
					String(Save.profile_style().get("badge", "")), int(clampf(h * 0.36, 14.0, 30.0)))
				if dim:
					draw_rect(Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h)), Color(UIKit.SLATE, 0.25))
			elif kind == "emote":
				var eid := TC.EMOTES.find(String(Catalogue.split(id)[1]))
				var col := UIKit.AMBER.lerp(Color("8d8a86"), 0.4) if dim else UIKit.AMBER
				Icons.draw_shape(self, Icons.emote_icon(eid) if eid >= 0 else "smile", c, s * (0.36 if cell else 0.4), col)
			elif tex != null:
				# a cell crops the portrait to fill it; the detail shows the
				# whole picture (the full figure, hat to shoes)
				var mod := Color(0.84, 0.84, 0.88) if dim else Color.WHITE
				if cell:
					_draw_cover(tex, ar, mod)
				else:
					draw_texture_rect(tex, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false, mod)
			else:
				var col2 := Color(UIKit.IVORY, 0.1)
				draw_circle(c + Vector2(0, -s * 0.16), s * 0.13, col2)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.2, s * 0.32), c + Vector2(-s * 0.16, s * 0.02),
					c + Vector2(0, -s * 0.03), c + Vector2(s * 0.16, s * 0.02), c + Vector2(s * 0.2, s * 0.32)]), col2)
		if cell == null:
			return
		# caption: what it is
		var f := UIKit.font_w(600)
		var cap := SeasonScreen.reward_caption(reward)
		var fs := SeasonScreen.CAPTION_FS
		var cy := size.y - 8.0 - SeasonScreen.CAPTION_H * 0.5 + (f.get_ascent(fs) - f.get_descent(fs)) * 0.5
		draw_string(f, Vector2(6.0, cy), cap, HORIZONTAL_ALIGNMENT_CENTER, size.x - 12.0, fs,
			UIKit.IVORY if state != "locked" else UIKit.IVORY_MUTED)
		# state marks (shape + colour, never colour alone)
		var corner := Vector2(size.x - 18.0, 18.0)
		match state:
			"locked":
				draw_circle(corner, 11.0, Color(UIKit.NAVY, 0.8), true, -1.0, true)
				Icons.draw_shape(self, "lock", corner, 7.0, UIKit.IVORY_MUTED)
			"premium_locked":
				draw_circle(corner, 11.0, UIKit.AMBER, true, -1.0, true)
				Icons.draw_shape(self, "lock", corner, 7.0, UIKit.NAVY)
			"claimable":
				var g := UIKit.box(Color(0, 0, 0, 0), UIKit.R_CARD, 2, Color(UIKit.AMBER, 0.85), 0)
				g.draw_center = false
				draw_style_box(g, r.grow(-3.0))
				draw_circle(corner, 11.0, UIKit.AMBER, true, -1.0, true)
				Icons.draw_shape(self, "plus", corner, 7.0, UIKit.NAVY)
			"claimed":
				draw_circle(corner, 11.0, UIKit.TEAL, true, -1.0, true)
				Icons.draw_shape(self, "check", corner, 7.0, UIKit.NAVY)
			"pending":
				# Pass 9: a claim on its way (an amber ring, no fill)
				draw_arc(corner, 9.5, 0.0, TAU, 20, UIKit.AMBER, 2.5, true)
				Icons.draw_shape(self, "rotate", corner, 6.0, UIKit.AMBER)

	## A square portrait cropped to cover `rect` (no letterbox bars).
	func _draw_cover(t: Texture2D, rect: Rect2, mod: Color) -> void:
		var src := t.get_size()
		if src.x <= 0.0 or src.y <= 0.0:
			return
		var k := maxf(rect.size.x / src.x, rect.size.y / src.y)
		var vis := rect.size / k
		draw_texture_rect_region(t, rect, Rect2((src - vis) * 0.5, vis), mod)


## Pass 9: the steps of a progress run, top to bottom: a dot per tier
## (filled teal when reached, ringed at your tier, quiet ahead) joined by a
## line, each with its number.  `big`: the detail's picture.
static func draw_steps(ci: CanvasItem, rect: Rect2, first: int, last: int, tier: int, big: bool = false) -> void:
	var n := last - first + 1
	if n <= 0 or rect.size.y < 4.0:
		return
	var f := UIKit.font_num(700)
	var fs := 22 if big else 19
	if big and rect.size.x > rect.size.y * 1.4:
		# a wide, short picture (the detail): the steps run left to right
		var stepx := rect.size.x / float(n)
		var d := clampf(minf(stepx * 0.12, rect.size.y * 0.1), 5.0, 12.0)
		var cy := rect.position.y + rect.size.y * 0.4
		for i in n:
			var t := first + i
			var x := rect.position.x + stepx * (float(i) + 0.5)
			if i < n - 1:
				ci.draw_line(Vector2(x + d + 3.0, cy), Vector2(x + stepx - d - 3.0, cy), Color(UIKit.IVORY, 0.45 if t < tier else 0.18), 2.5, true)
			if t <= tier:
				ci.draw_circle(Vector2(x, cy), d, UIKit.TEAL, true, -1.0, true)
			else:
				ci.draw_arc(Vector2(x, cy), d, 0.0, TAU, 18, Color(UIKit.IVORY, 0.35), 2.0, true)
			if t == tier:
				ci.draw_arc(Vector2(x, cy), d + 5.0, 0.0, TAU, 22, UIKit.TEAL, 2.5, true)
			var col := UIKit.TEAL if t == tier else (UIKit.IVORY if t <= tier else UIKit.IVORY_MUTED)
			var tw := f.get_string_size("%d" % t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			ci.draw_string(f, Vector2(x - tw * 0.5, cy + d + 10.0 + f.get_ascent(fs)), "%d" % t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		return
	var step := rect.size.y / float(n)
	var dot := clampf(step * 0.16, 4.0, 11.0 if big else 9.0)
	var x := rect.get_center().x - 26.0 if big else rect.position.x + maxf(dot + 6.0, rect.size.x * 0.28)
	for i in n:
		var t := first + i
		var y := rect.position.y + step * (float(i) + 0.5)
		if i < n - 1:
			ci.draw_line(Vector2(x, y + dot + 2.0), Vector2(x, y + step - dot - 2.0), Color(UIKit.IVORY, 0.45 if t < tier else 0.18), 2.0, true)
		var reached := t <= tier
		if reached:
			ci.draw_circle(Vector2(x, y), dot, UIKit.TEAL, true, -1.0, true)
		else:
			ci.draw_arc(Vector2(x, y), dot, 0.0, TAU, 18, Color(UIKit.IVORY, 0.35), 2.0, true)
		if t == tier:
			ci.draw_arc(Vector2(x, y), dot + 4.0, 0.0, TAU, 22, UIKit.TEAL, 2.0, true)
		var col := UIKit.TEAL if t == tier else (UIKit.IVORY if reached else UIKit.IVORY_MUTED)
		ci.draw_string(f, Vector2(x + dot + 8.0, y + (f.get_ascent(fs) - f.get_descent(fs)) * 0.5), "%d" % t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Pass 9: one column for a run of progress tiers (no reward on either
## track), as tall as both reward rows: a quiet card with a step per tier
## and "No reward" at the foot.  A tap explains it in the detail; a swipe
## that starts on it scrolls the track.
class ProgressRun:
	extends Button
	var screen: SeasonScreen
	var first := 0
	var last := 0
	var art: Control

	func setup(s: SeasonScreen, f: int, l: int) -> void:
		screen = s
		first = f
		last = l
		name = "Run_%d_%d" % [f, l]
		UIKit.make_card(self, Vector2(SeasonScreen.CELL * 0.5, SeasonScreen.CELL * 2.0 + SeasonScreen.GAP), Color(UIKit.SLATE_LO, 0.5))
		var face := UIKit.face_of(self)
		var q := UIKit.box(Color(UIKit.SLATE_LO, 0.32), UIKit.R_CARD, 0, Color.WHITE, 0)
		var qs := UIKit.box(Color(UIKit.SLATE_LO, 0.5), UIKit.R_CARD, 3, UIKit.TEAL, 0)
		face.styles = {"normal": q, "hover": q, "pressed": q, "disabled": q, "selected": qs}
		art = Control.new()
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.draw.connect(_draw_art)
		face.add_child(art)

	func refresh() -> void:
		var tier := screen.current_tier()
		var where := "reached" if tier > last else (("you're at Tier %d" % tier) if tier >= first else "ahead")
		accessibility_name = "%s: progress tier%s, no reward, %s" % [("Tiers %d to %d" % [first, last]) if last > first else "Tier %d" % first,
			"s" if last > first else "", where]
		art.queue_redraw()

	func _draw_art() -> void:
		var r := Rect2(Vector2.ZERO, art.size)
		var f := UIKit.font_w(600)
		var room := r.size.x - 10.0
		var fs := 17
		while fs > 13 and f.get_string_size("No reward", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
			fs -= 1
		# a narrow column says it on two lines rather than trimming it
		var lines := ["No reward"] if f.get_string_size("No reward", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= room else ["No", "reward"]
		var lh := f.get_height(fs)
		var foot := 14.0 + lh * float(lines.size())
		SeasonScreen.draw_steps(art, Rect2(r.position + Vector2(6, 10), r.size - Vector2(12, 10 + foot)), first, last, screen.current_tier())
		for i in lines.size():
			var cy := r.end.y - foot + 4.0 + lh * float(i) + f.get_ascent(fs)
			art.draw_string(f, Vector2(4.0, cy), String(lines[i]), HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 8.0, fs, UIKit.IVORY_DIM)


## Pass 9: a navigation chip on the row above the track: a small picture
## (an icon, or a featured skin's face) and two lines ("Next reward" /
## "Tier 40 · 1,050 XP").  A whole 44 pt target that only moves the view.
class NavChip:
	extends Button
	var screen: SeasonScreen
	var top_l: Label
	var main_l: Label
	var glyph := ""
	var skin := ""
	var reached := false
	var pic: Control
	var tex: Texture2D
	var pic_key := ""

	func setup(s: SeasonScreen, nm: String, top: String, main: String, icon_kind: String = "", skin_id: String = "") -> void:
		screen = s
		name = nm
		glyph = icon_kind
		skin = skin_id
		UIKit.make_card(self, Vector2(UIKit.touch_min(), UIKit.row_h()), Color(UIKit.SLATE_HI, 0.96))
		var m := MarginContainer.new()
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		m.add_theme_constant_override("margin_left", 10)
		m.add_theme_constant_override("margin_right", 14)
		m.add_theme_constant_override("margin_top", 4)
		m.add_theme_constant_override("margin_bottom", 4)
		UIKit.face_of(self).add_child(m)
		var h := UIKit.hbox(8)
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		m.add_child(h)
		pic = Control.new()
		pic.custom_minimum_size = Vector2(1, 1) * clampf(UIKit.row_h() * 0.62, 30.0, 52.0)
		pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pic.draw.connect(_draw_pic)
		h.add_child(pic)
		var v := UIKit.vbox(0)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_child(v)
		top_l = UIKit.styled(top, "caption", UIKit.IVORY_MUTED)
		top_l.add_theme_font_size_override("font_size", 16)
		v.add_child(top_l)
		main_l = UIKit.styled(main, "label", UIKit.IVORY)
		main_l.add_theme_font_size_override("font_size", 20)
		v.add_child(main_l)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for n in m.find_children("*", "Control", true, false):
			(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		UIKit.fit_card(self, m, 0.0)
		if skin != "":
			_request()

	func set_text_lines(top: String, main: String) -> void:
		top_l.text = top
		main_l.text = main

	## The featured skin's face: the cached head portrait when its art is
	## in the build (Portraits), a neutral head otherwise.
	func _request() -> void:
		var parts := Catalogue.split(skin)
		if Cosmetics.entry(String(parts[0]), String(parts[1])).is_empty():
			return
		var look := CommerceArt.preview_look(Save.data["cosmetic"], "outfit", String(parts[1]))
		var ps := Portraits.shared()
		pic_key = Portraits.key_for(look, TC.Role.RUNNER, "head")
		var t := ps.portrait(look, TC.Role.RUNNER, "pass:nav:%s" % skin, "head")
		if ps.has_picture(pic_key):
			tex = t
		elif not ps.portrait_ready.is_connected(_on_pic):
			ps.portrait_ready.connect(_on_pic)

	func _on_pic(k: String, t: Texture2D) -> void:
		if k == pic_key and is_instance_valid(self):
			tex = t
			pic.queue_redraw()

	func _draw_pic() -> void:
		var r := Rect2(Vector2.ZERO, pic.size)
		var c := r.get_center()
		var rad := minf(r.size.x, r.size.y) * 0.5
		if skin != "":
			pic.draw_circle(c, rad, Color(UIKit.NAVY, 0.7), true, -1.0, true)
			if tex != null:
				pic.draw_texture_rect(tex, r.grow(-2.0), false)
			else:
				# a neutral head and shoulders (the skin's art isn't in this build)
				pic.draw_circle(c + Vector2(0, -rad * 0.18), rad * 0.36, Color(UIKit.IVORY, 0.32), true, -1.0, true)
				pic.draw_arc(c + Vector2(0, rad * 0.9), rad * 0.62, PI * 1.08, PI * 1.92, 16, Color(UIKit.IVORY, 0.32), rad * 0.22, true)
			pic.draw_arc(c, rad - 1.0, 0.0, TAU, 32, UIKit.AMBER if reached else Color(UIKit.AMBER, 0.55), 2.0, true)
			return
		Icons.draw_shape(pic, glyph, c, rad * 0.8, UIKit.TEAL if glyph == "flag" else UIKit.AMBER)


# ------------------------------------------------------------------ challenges
## Pass 8 (docs/ECONOMY.md §10).  The side panel: a two-page switch
## ("Challenges" | "Reward", one 44 pt row) over its pages.
func _side_box() -> VBoxContainer:
	if _side != null:
		return _side
	_side = UIKit.vbox(UIKit.SP_S)
	_side.name = "Side"
	detail_panel.add_child(_side)
	var row := UIKit.hbox(UIKit.SP_S)
	row.name = "SideTabs"
	_side.add_child(row)
	for spec in [["challenges", "Challenges"], ["reward", "Reward"]]:
		var b := UIKit.quiet(String(spec[1]), Vector2(0, UIKit.row_h()), UIKit.T_CAPTION + 1)
		b.name = "Tab_" + String(spec[0])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(show_side.bind(String(spec[0])))
		row.add_child(b)
		_tabs[String(spec[0])] = b
	return _side


## Show one page of the side panel: "challenges" or "reward" (a tapped
## reward shows its detail; the Challenges tab comes back to the goals).
func show_side(page: String) -> void:
	side_page = page
	if is_instance_valid(challenge_page):
		challenge_page.visible = page == "challenges"
	if _d.has("page"):
		(_d["page"] as Control).visible = page == "reward"
	for k in _tabs:
		UIKit.set_selected(_tabs[k], k == page)
		(_tabs[k] as Button).accessibility_name = "%s%s" % [(_tabs[k] as Button).text, ", shown" if k == page else ""]
	if page == "challenges":
		_refresh_challenges()


## Challenges · Earn Season XP: the role line once, an honest status when
## the service can't show progress, then Daily and Weekly with their local
## reset time, one card per goal, and how pinning works.
func _build_challenges() -> void:
	challenge_page = UIKit.vbox(UIKit.SP_S)
	challenge_page.name = "ChallengesPage"
	challenge_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_side_box().add_child(challenge_page)
	# one line each (they shrink to fit a narrow phone panel)
	var head := UIKit.styled("Challenges · Earn Season XP", "label", UIKit.IVORY)
	head.name = "ChallengesHeading"
	UIKit.fit_text(head, [UIKit.T_LABEL, UIKit.T_CAPTION, 18, 17])
	challenge_page.add_child(head)
	var role := UIKit.styled(ChallengeRules.ROLE_LINE, "caption", UIKit.IVORY_MUTED)
	role.name = "RoleLine"
	UIKit.fit_text(role, [UIKit.T_CAPTION, 18, 17, 16])
	challenge_page.add_child(role)
	var status := UIKit.styled("", "caption", UIKit.AMBER)
	status.name = "ChallengeStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.visible = false
	challenge_page.add_child(status)
	var sc := UIKit.scroll_area()
	sc.name = "ChallengeList"
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	challenge_page.add_child(sc)
	var list := UIKit.vbox(UIKit.SP_S)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	var groups := {}
	for d in ChallengeRules.defs():
		var kind := String(d["period"])
		if not groups.has(kind):
			var gh := UIKit.styled("", "overline", UIKit.IVORY_MUTED)
			gh.name = "Group_" + kind
			UIKit.fit_text(gh, [UIKit.T_OVERLINE, 15, 14])
			list.add_child(gh)
			groups[kind] = gh
		var card := ChallengeCard.new()
		card.setup(self, String(d["id"]))
		card.pressed.connect(_toggle_pin.bind(String(d["id"])))
		list.add_child(card)
		challenge_cards.append(card)
	var hint := UIKit.styled("Tap a goal to pin it: it shows in your pause menu.", "caption", UIKit.IVORY_MUTED)
	hint.name = "PinHint"
	hint.add_theme_font_size_override("font_size", 18)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(hint)
	_ch = {"head": head, "role": role, "status": status, "scroll": sc, "list": list, "groups": groups, "hint": hint, "day": -1}
	detail_panel.resized.connect(_fit_challenges)
	# reset times and a new period are checked twice a minute (labels are
	# updated in place: nothing is rebuilt)
	_ch_timer = Timer.new()
	_ch_timer.wait_time = 30.0
	_ch_timer.timeout.connect(_on_challenge_tick)
	add_child(_ch_timer)
	_ch_timer.start()


## Wrapping labels get their width from the panel's allocated width.
func _fit_challenges() -> void:
	if _ch.is_empty() or not is_instance_valid(detail_panel):
		return
	var w := _side_w()
	if w < 10.0:
		return
	(_ch["status"] as Control).custom_minimum_size.x = w
	(_ch["hint"] as Control).custom_minimum_size.x = w - 24.0


func _refresh_challenges() -> void:
	if _ch.is_empty() or not is_inside_tree():
		return
	var st := Wallet.challenge_status()
	var status: Label = _ch["status"]
	status.text = String(st["text"])
	status.visible = status.text != ""
	var cards := Wallet.challenge_cards()
	var now := Wallet.server_now()
	for kind in _ch["groups"]:
		var end := 0
		for c in cards:
			if String(c["period"]) == kind:
				end = int(c["resets_at"])
		(_ch["groups"][kind] as Label).text = "%s · %s" % [ChallengeRules.period_label(String(kind)), ChallengeRules.reset_text(end, now)]
	for cc in challenge_cards:
		for c in cards:
			if String(c["id"]) == cc.id:
				cc.refresh(c, bool(st["live"]) and bool(c["known"]))
	_ch["day"] = ChallengeRules.day_start(now)


## A new UTC day while the screen is open: the old progress belongs to the
## old period, so ask the service for the new one.
func _on_challenge_tick() -> void:
	var day := ChallengeRules.day_start(Wallet.server_now())
	var rolled := int(_ch.get("day", -1)) >= 0 and day != int(_ch["day"])
	_refresh_challenges()
	if rolled and Cloud.signed_in() and not Wallet.syncing:
		Wallet.refresh()


func _toggle_pin(id: String) -> void:
	var was := Wallet.pinned_challenge_id() == id
	Wallet.pin_challenge("" if was else id)
	UIKit.toast(self, "Unpinned" if was else "Pinned: it shows in your pause menu", 1.6)


## A real milestone (the service reported a goal complete): said once.
func _on_challenge_completed(card: Dictionary) -> void:
	if not is_inside_tree():
		return
	UIKit.toast(self, "%s complete · %s" % [String(card.get("name", "")), ChallengeRules.xp_text(int(card.get("xp", 0)))], 2.4)
	Sfx.play("pickup")


## One goal: its name and task, its progress (bar and "4/6"), "+50 Season
## XP", a flag when pinned and a check when complete.  The whole card is one
## touch target that pins or unpins it (a swipe that starts on it scrolls
## the list instead).  Without the service's progress for this period the
## bar and count are hidden: the card is a readable preview, never a fake 0.
class ChallengeCard:
	extends Button
	var screen: SeasonScreen
	var id := ""
	var name_l: Label
	var task_l: Label
	var bar: ProgressBar
	var count_l: Label
	var xp_l: Label
	var mark: Icons.IconRect
	var _was_done := -1    # -1 before the first refresh: a goal already done doesn't pop
	var body: VBoxContainer
	var card: Dictionary = {}
	var live := false

	func setup(s: SeasonScreen, cid: String) -> void:
		screen = s
		id = cid
		name = "Challenge_" + cid
		UIKit.make_card(self, Vector2(0, UIKit.touch_min()), Color(UIKit.SLATE_HI, 0.96))
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var m := MarginContainer.new()
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		m.add_theme_constant_override("margin_left", 14)
		m.add_theme_constant_override("margin_right", 12)
		m.add_theme_constant_override("margin_top", 9)
		m.add_theme_constant_override("margin_bottom", 10)
		UIKit.face_of(self).add_child(m)
		body = UIKit.vbox(3)
		m.add_child(body)
		var r1 := UIKit.hbox(8)
		name_l = UIKit.styled("", "label", UIKit.IVORY)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UIKit.fit_text(name_l, [UIKit.T_LABEL - 1, UIKit.T_CAPTION - 1, 17])
		r1.add_child(name_l)
		mark = Icons.IconRect.new("flag", UIKit.AMBER, 22)
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mark.visible = false
		r1.add_child(mark)
		body.add_child(r1)
		task_l = UIKit.styled("", "caption", UIKit.IVORY_MUTED)
		task_l.add_theme_font_size_override("font_size", 18)
		UIKit.fit_text(task_l, [18, 16, 15])
		body.add_child(task_l)
		var r3 := UIKit.hbox(8)
		bar = ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.step = 0.001
		bar.custom_minimum_size = Vector2(36, 8)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_theme_stylebox_override("background", UIKit.box(Color(UIKit.NAVY, 0.7), 4, 0, Color.WHITE, 0))
		bar.add_theme_stylebox_override("fill", UIKit.box(UIKit.TEAL, 4, 0, Color.WHITE, 0))
		r3.add_child(bar)
		count_l = UIKit.styled("", "num", UIKit.IVORY)
		count_l.add_theme_font_size_override("font_size", 19)
		r3.add_child(count_l)
		xp_l = UIKit.styled("", "caption", UIKit.AMBER, HORIZONTAL_ALIGNMENT_RIGHT)
		xp_l.add_theme_font_size_override("font_size", 17)
		r3.add_child(xp_l)
		body.add_child(r3)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for n in m.find_children("*", "Control", true, false):
			(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.minimum_size_changed.connect(_fit)
		_fit()

	func _fit() -> void:
		if is_instance_valid(body):
			custom_minimum_size.y = maxf(UIKit.touch_min(), body.get_combined_minimum_size().y + 19.0)

	func refresh(c: Dictionary, is_live: bool) -> void:
		card = c
		live = is_live
		name_l.text = String(c["name"])
		task_l.text = String(c["task"])
		var goal := maxi(1, int(c["goal"]))
		var prog := clampi(int(c["progress"]), 0, goal)
		var done := live and bool(c["completed"])
		var pinned := bool(c["pinned"])
		bar.visible = live
		count_l.visible = live
		if live:
			bar.value = float(prog) / float(goal)
			count_l.text = "%d/%d" % [prog, goal]
		xp_l.text = ("Done · " if done else "") + ChallengeRules.xp_text(int(c["xp"]))
		xp_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL if not live else Control.SIZE_FILL
		xp_l.add_theme_color_override("font_color", UIKit.TEAL if done else (UIKit.AMBER if live else UIKit.IVORY_MUTED))
		mark.visible = done or pinned
		mark.kind = "check" if done else "flag"
		mark.col = UIKit.TEAL if done else UIKit.AMBER
		mark.queue_redraw()
		# Pass 8: a goal completed while its card is on screen confirms with
		# the shared motion (once; nothing under Reduced Motion)
		if done and _was_done == 0:
			Motion.confirm(mark)
		_was_done = 1 if done else 0
		UIKit.set_selected(self, pinned)
		var prog_t := ("%d of %d" % [prog, goal]) if live else "progress not available"
		accessibility_name = "%s, %s challenge: %s. %s. %s%s. %s" % [String(c["name"]), ChallengeRules.period_label(String(c["period"])), String(c["task"]),
			prog_t, ChallengeRules.xp_text(int(c["xp"])), ", complete" if done else "", "Pinned; tap to unpin" if pinned else "Tap to pin"]
