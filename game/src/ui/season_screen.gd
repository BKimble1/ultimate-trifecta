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
##   track   30 tiers on one horizontal track (finger swipes scroll it from
##           anywhere; a swipe never claims): every tier column has its Free
##           reward above and its Premium reward below, both rows always
##           whole.  The track lives in a region that takes the height the
##           header leaves and never asks for more; the cells size themselves
##           from it (V6 kept a 132-unit minimum that guaranteed overflow)
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
	var tv := UIKit.hbox(UIKit.SP_S)
	track_panel.add_child(tv)
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
	for t in Catalogue.season_tiers(sid):
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

	var st := Wallet.season_state(sid)
	var tier := maxi(1, Economy.tier_for_xp(sid, int(st["xp"])))
	var first := Wallet.claimable(sid) if bool(Wallet.can_transact()["ok"]) else []
	if not first.is_empty():
		focus(int(first[0]["tier"]), String(first[0]["track"]))
	else:
		focus(mini(tier + (1 if tier < Economy.max_tier(sid) else 0), Economy.max_tier(sid)), "free" if not Economy.reward_at(sid, tier, "free").is_empty() else "premium")
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
## gaps and the scrollbar fit the region the header leaves (phone and iPad
## alike); width follows the height.  No minimum beyond a 44 pt target.
func _fit_cells() -> void:
	if not is_instance_valid(track_region):
		return
	var h := track_region.size.y
	if h < 2.0:
		return
	var sb := track_panel.get_theme_stylebox("panel")
	var inner := h - sb.get_margin(SIDE_TOP) - sb.get_margin(SIDE_BOTTOM)
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
	for t in columns:
		((columns[t] as Control).get_meta(&"tier_label") as Control).custom_minimum_size.x = w
	_scroll_to.call_deferred(focus_tier)


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
	return v


func _cell(tier: int, track: String) -> Control:
	for c in cells:
		if c.tier == tier and c.track == track:
			return c
	return null


## A tap on a cell selects it; a blank Free slot explains that tier's
## Premium reward instead.
func _on_cell(tier: int, track: String) -> void:
	if track == "free" and Economy.reward_at(sid, tier, "free").is_empty():
		focus(tier, "premium", true)
	else:
		focus(tier, track)


## Bring a tier's column into view (a little left of centre), clamped.
func _scroll_to(tier: int) -> void:
	await get_tree().process_frame
	if not is_instance_valid(track_scroll) or not columns.has(tier) or TouchScroll.is_dragging(track_scroll):
		return
	var col: Control = columns[tier]
	var room := track_scroll.get_h_scroll_bar().max_value - track_scroll.size.x
	track_scroll.scroll_horizontal = int(clampf(col.position.x - track_scroll.size.x * 0.35, 0.0, maxf(0.0, room)))


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
	var st := Wallet.season_state(sid)
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
	var tier := int(prog["tier"])
	for t in columns:
		var lbl: Label = (columns[t] as Control).get_meta(&"tier_label")
		lbl.add_theme_color_override("font_color", UIKit.TEAL if int(t) == tier else (UIKit.IVORY if int(t) < tier else UIKit.IVORY_DIM))
	for c in cells:
		c.refresh()
	_refresh_detail()
	_refresh_challenges()


func cell_state(tier: int, track: String) -> String:
	var st := Wallet.season_state(sid)
	return Economy.cell_state(sid, tier, track, int(st["xp"]), bool(st["premium"]), st["claimed"])


## What a cell shows: the rules' state, except that a claimable reward is
## "earned" while claiming is unavailable (no claim affordance then).
func display_state(tier: int, track: String) -> String:
	var s := cell_state(tier, track)
	if s == "claimable" and not bool(claim_status()["ok"]):
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


func focus(tier: int, track: String, from_empty: bool = false) -> void:
	focus_tier = tier
	focus_track = track
	_from_empty = from_empty
	for c in cells:
		UIKit.set_selected(c, c.tier == tier and c.track == track)
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
	detail_box.add_child(over)
	var art := RewardArt.new()
	art.name = "DetailArt"
	art.custom_minimum_size = Vector2(0, 180)
	art.screen = self
	detail_box.add_child(art)
	var name_l := UIKit.styled("", "headline")
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_box.add_child(name_l)
	var type_l := UIKit.styled("", "caption", UIKit.IVORY_MUTED)
	detail_box.add_child(type_l)
	var state_l := UIKit.styled("", "body", UIKit.IVORY)
	state_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_box.add_child(state_l)
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
	_d = {"over": over, "art": art, "name": name_l, "type": type_l, "state": state_l, "reason": reason_l, "action": action, "scroll": sc, "page": v}
	# wrapping labels get their width from the panel's allocated width, so
	# they never report a first-frame height for an unknown width
	detail_panel.resized.connect(_fit_detail)


func _fit_detail() -> void:
	if _d.is_empty() or not is_instance_valid(detail_panel):
		return
	var sb := detail_panel.get_theme_stylebox("panel")
	var w := detail_panel.size.x - sb.get_margin(SIDE_LEFT) - sb.get_margin(SIDE_RIGHT) - 10.0
	if w < 10.0:
		return
	for k in ["name", "state", "reason"]:
		(_d[k] as Control).custom_minimum_size.x = w
	(_d["art"] as Control).custom_minimum_size.y = clampf(w * 0.58, 130.0, 260.0)
	if is_instance_valid(_preview):
		_preview.custom_minimum_size = Vector2(0, (_d["art"] as Control).custom_minimum_size.y)


func _refresh_detail() -> void:
	if _d.is_empty():
		return
	var r := Economy.reward_at(sid, focus_tier, focus_track)
	var st := display_state(focus_tier, focus_track)
	var cs := claim_status()
	(_d["over"] as Label).text = "Tier %d · %s" % [focus_tier, "Premium track" if focus_track == "premium" else "Free track"]
	var art: RewardArt = _d["art"]
	art.reward = r
	art.state = st
	art.request()
	_show_preview(r)
	(_d["name"] as Label).text = reward_name(r) if not r.is_empty() else "No Free reward at this tier"
	(_d["type"] as Label).text = reward_type(r) if not r.is_empty() else ""
	var action: Button = _d["action"]
	var state_l: Label = _d["state"]
	var reason_l: Label = _d["reason"]
	action.visible = true
	action.disabled = false
	reason_l.text = ""
	var xp := int(Wallet.season_state(sid)["xp"])
	var need := int(Catalogue.season_tiers(sid)[focus_tier - 1]["xp"]) - xp
	var into := "wallet" if r.has("coins") else "Locker"
	var lead := ("No Free reward at Tier %d. " % focus_tier) if _from_empty else ""
	match st:
		"empty":
			state_l.text = "The Free track skips this tier."
			action.visible = false
		"locked":
			state_l.text = lead + "Reach Tier %d: %s more Season XP from online rounds. No tier skips." % [focus_tier, Catalogue.format_coins(maxi(0, need))]
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
		"claimed":
			if r.has("coins"):
				state_l.text = lead + "Claimed: added to your Coins."
				action.visible = false
			else:
				state_l.text = lead + "Claimed. It's yours to keep, in your Locker."
				action.text = "Wear it in the Locker"
	reason_l.visible = reason_l.text != ""
	action.accessibility_name = "%s, %s%s" % [(_d["name"] as Label).text, action.text, ", unavailable" if action.disabled else ""]
	_fit_detail()


## Emote rewards play on one small live runner in the detail (created on
## first use, hidden and not rendered otherwise; one per screen).
func _show_preview(r: Dictionary) -> void:
	var art: Control = _d["art"]
	var id := String(r.get("item", ""))
	var eid := TC.EMOTES.find(String(Catalogue.split(id)[1])) if id.begins_with("emote:") else -1
	if eid < 0:
		if is_instance_valid(_preview):
			_preview.visible = false
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
	# the preview replays its move every few seconds (Reduced Motion: once)
	if _preview_emote < 0 or not is_instance_valid(_preview) or not _preview.is_visible_in_tree():
		return
	_preview_t += delta
	var dur := float(DormStage.EMOTE_S.get(String(TC.EMOTES[_preview_emote]), 2.4)) + 0.8
	if _preview_t >= dur and not UIKit.reduced_motion():
		_preview_t = 0.0
		_play_preview()


func _on_detail_action() -> void:
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
		Sfx.play("pickup")
		UIKit.toast(self, ("Claimed %d reward%s" % [got.size(), "" if got.size() == 1 else "s"]) if got.size() != 1 else "Claimed!", 2.0)
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
			"earned": "earned, claiming unavailable right now", "claimed": "claimed", "empty": "no Free reward"}.get(state, state)
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

	## A square portrait cropped to cover `rect` (no letterbox bars).
	func _draw_cover(t: Texture2D, rect: Rect2, mod: Color) -> void:
		var src := t.get_size()
		if src.x <= 0.0 or src.y <= 0.0:
			return
		var k := maxf(rect.size.x / src.x, rect.size.y / src.y)
		var vis := rect.size / k
		draw_texture_rect_region(t, rect, Rect2((src - vis) * 0.5, vis), mod)


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
	var head := UIKit.styled("Challenges · Earn Season XP", "label", UIKit.IVORY)
	head.name = "ChallengesHeading"
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	challenge_page.add_child(head)
	var role := UIKit.styled(ChallengeRules.ROLE_LINE, "caption", UIKit.IVORY_MUTED)
	role.name = "RoleLine"
	role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	var sb := detail_panel.get_theme_stylebox("panel")
	var w := detail_panel.size.x - sb.get_margin(SIDE_LEFT) - sb.get_margin(SIDE_RIGHT) - 10.0
	if w < 10.0:
		return
	for k in ["head", "role", "status"]:
		(_ch[k] as Control).custom_minimum_size.x = w
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
		UIKit.set_selected(self, pinned)
		var prog_t := ("%d of %d" % [prog, goal]) if live else "progress not available"
		accessibility_name = "%s, %s challenge: %s. %s. %s%s. %s" % [String(c["name"]), ChallengeRules.period_label(String(c["period"])), String(c["task"]),
			prog_t, ChallengeRules.xp_text(int(c["xp"])), ", complete" if done else "", "Pinned; tap to unpin" if pinned else "Tap to pin"]
