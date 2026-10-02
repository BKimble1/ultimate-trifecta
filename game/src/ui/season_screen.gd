class_name SeasonScreen
extends Screen
## Season Pass (V6): Season 1 · After Hours.
##
##   top     the navigation bar and the Coins chip
##   header  the season, your exact tier, XP to the next tier with a bar,
##           Premium status, and Claim all (n)
##   track   30 tiers side by side on one smooth horizontal track (finger
##           swipes scroll it from anywhere; a swipe never claims): each
##           tier has its Free reward above and its Premium reward below,
##           each locked / ready to claim / claimed / Premium-locked
##   detail  the focused reward, readable: picture, name, what it is, which
##           tier and track, its state and one action (Claim, Get Premium in
##           the Shop, or Wear it in the Locker)
##
## Rules shown and enforced by the service: XP only from eligible online
## rounds (never from Coins), no paid tier skips, Premium bought later lets
## you claim every Premium reward already earned, claiming is idempotent,
## claimed rewards are permanent.  No end date is set for this beta, so no
## countdown is shown.  Reward pictures are cached portraits (bounded queue).

const CELL := 132.0
const GAP := 10.0

var sid := "s1"
var track_scroll: ScrollContainer
var columns: Dictionary = {}          # tier -> Control
var cells: Array = []                 # RewardCell
var tier_lbl: Label
var xp_lbl: Label
var bar: ProgressBar
var premium_chip: Label
var claim_all_btn: Button
var banner: Label
var detail_box: VBoxContainer
var focus_tier := 1
var focus_track := "free"
var _busy := false
var _d: Dictionary = {}


func build() -> void:
	sid = Catalogue.current_season_id()
	if App.stage:
		App.stage.set_mode("home")
		App.sync_stage_local()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	TitleScreen.add_shades(self, 0.6, 0.45)
	back_action = func() -> void: NavShell.go_hub()
	var top := UIKit.hbox(14)
	content.add_child(top)
	var back := UIKit.icon_button("back")
	back.tooltip_text = "Back"
	back.accessibility_name = "Back"
	back.pressed.connect(_go_back)
	top.add_child(back)
	var nav := NavShell.make("pass")
	nav.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nav)
	top.add_child(WalletChip.new())

	var mid := UIKit.hbox(14)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(mid)
	var left := UIKit.vbox(10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(left)
	left.add_child(_header())
	banner = UIKit.styled("", "caption", UIKit.AMBER)
	banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(banner)
	var tp := UIKit.panel(Color(UIKit.SLATE, 0.93), UIKit.R_PANEL, 12)
	tp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(tp)
	var tv := UIKit.hbox(8)
	tp.add_child(tv)
	tv.add_child(_track_legend())
	track_scroll = UIKit.scroll_area(true)
	track_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	track_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track_scroll.follow_focus = true
	tv.add_child(track_scroll)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(GAP))
	track_scroll.add_child(row)
	for t in Catalogue.season_tiers(sid):
		row.add_child(_column(t))

	var view := get_viewport().get_visible_rect().size
	var dp := UIKit.panel(Color(UIKit.SLATE, 0.96), UIKit.R_PANEL, 18)
	dp.name = "DetailPanel"
	dp.custom_minimum_size = Vector2(clampf(view.x * 0.27, 300.0, 420.0), 0)
	dp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(dp)
	detail_box = UIKit.vbox(10)
	dp.add_child(detail_box)
	_build_detail()

	var st := Wallet.season_state(sid)
	var tier := maxi(1, Economy.tier_for_xp(sid, int(st["xp"])))
	var first := Wallet.claimable(sid)
	if not first.is_empty():
		focus(int(first[0]["tier"]), String(first[0]["track"]))
	else:
		focus(mini(tier + (1 if tier < Economy.max_tier(sid) else 0), Economy.max_tier(sid)), "free" if not Economy.reward_at(sid, tier, "free").is_empty() else "premium")
	_refresh()
	_scroll_to.call_deferred(focus_tier)
	Wallet.changed.connect(_refresh)
	if Cloud.signed_in():
		Wallet.refresh()
	focus_first(claim_all_btn)
	Motion.settle_in(tp)


func _header() -> Control:
	var p := UIKit.panel(Color(UIKit.SLATE, 0.93), UIKit.R_PANEL, 18)
	var h := UIKit.hbox(18)
	p.add_child(h)
	var em := CommerceArt.Pic.new("glyph", "moon", UIKit.AMBER, 64)
	em.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(em)
	var v := UIKit.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var s: Dictionary = Catalogue.season(sid)
	v.add_child(UIKit.styled("Season %d" % int(s.get("number", 1)), "overline", UIKit.IVORY_MUTED))
	var tr := UIKit.hbox(14)
	var title := UIKit.styled(String(s.get("name", "")), "title")
	tr.add_child(title)
	tier_lbl = UIKit.styled("", "num", UIKit.TEAL)
	tier_lbl.add_theme_font_size_override("font_size", 26)
	tier_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tr.add_child(tier_lbl)
	premium_chip = UIKit.styled("", "label", UIKit.AMBER)
	premium_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tr.add_child(premium_chip)
	v.add_child(tr)
	bar = ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	bar.add_theme_stylebox_override("background", UIKit.box(Color(UIKit.NAVY, 0.7), 6, 0, Color.WHITE, 0))
	bar.add_theme_stylebox_override("fill", UIKit.box(UIKit.TEAL, 6, 0, Color.WHITE, 0))
	bar.max_value = 1.0
	bar.step = 0.001
	v.add_child(bar)
	xp_lbl = UIKit.styled("", "caption", UIKit.IVORY_MUTED)
	xp_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(xp_lbl)
	var how := UIKit.styled("Season XP comes from online rounds with friends, never from Coins. No tier skips.", "caption", UIKit.IVORY_DIM)
	how.add_theme_font_size_override("font_size", 18)
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(how)
	claim_all_btn = UIKit.primary("Claim all", Vector2(240, 84), 24)
	claim_all_btn.name = "ClaimAll"
	claim_all_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	claim_all_btn.pressed.connect(_claim_all)
	h.add_child(claim_all_btn)
	return p


func _track_legend() -> Control:
	var v := UIKit.vbox(int(GAP))
	v.add_child(spacer(30))
	for spec in [["Free", UIKit.IVORY], ["Premium", UIKit.AMBER]]:
		var l := UIKit.styled(String(spec[0]), "overline", spec[1])
		l.custom_minimum_size = Vector2(0, CELL + 12.0)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		v.add_child(l)
	return v


func _column(t: Dictionary) -> Control:
	var tier := int(t["tier"])
	var v := UIKit.vbox(int(GAP))
	v.name = "Tier_%d" % tier
	var lbl := UIKit.styled("%d" % tier, "num", UIKit.IVORY_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	lbl.custom_minimum_size = Vector2(CELL, 30)
	v.add_child(lbl)
	for track in ["free", "premium"]:
		var cell := RewardCell.new()
		cell.setup(self, tier, track)
		cell.pressed.connect(focus.bind(tier, track))
		v.add_child(cell)
		cells.append(cell)
	columns[tier] = v
	v.set_meta(&"tier_label", lbl)
	return v


func _scroll_to(tier: int) -> void:
	await get_tree().process_frame
	if not is_instance_valid(track_scroll) or not columns.has(tier):
		return
	var col: Control = columns[tier]
	track_scroll.scroll_horizontal = int(maxf(0.0, col.position.x - track_scroll.size.x * 0.35))


# ------------------------------------------------------------------ state
func _refresh() -> void:
	if not is_inside_tree():
		return
	var st := Wallet.season_state(sid)
	var xp := int(st["xp"])
	var prog := Economy.tier_progress(sid, xp)
	tier_lbl.text = "Tier %d / %d" % [int(prog["tier"]), Economy.max_tier(sid)]
	bar.value = float(prog["frac"])
	if int(prog["next"]) < 0:
		xp_lbl.text = "%s Season XP · every tier reached." % Catalogue.format_coins(xp)
	else:
		var nxt := Economy.reward_at(sid, int(prog["next"]), "free")
		var nxt_p := Economy.reward_at(sid, int(prog["next"]), "premium")
		var what := reward_name(nxt) if not nxt.is_empty() else reward_name(nxt_p)
		xp_lbl.text = "%s / %s XP to Tier %d · next: %s" % [
			Catalogue.format_coins(int(prog["into"])), Catalogue.format_coins(int(prog["into"]) + int(prog["need"])), int(prog["next"]), what]
	var prem := bool(st["premium"])
	premium_chip.text = "Premium" if prem else "Free track"
	premium_chip.add_theme_color_override("font_color", UIKit.AMBER if prem else UIKit.IVORY_MUTED)
	var n := Wallet.claimable(sid).size()
	var can := Wallet.can_transact()
	claim_all_btn.text = ("Claim all (%d)" % n) if n > 0 else "Nothing to claim"
	claim_all_btn.disabled = n == 0 or _busy or not bool(can["ok"])
	banner.text = "" if bool(can["ok"]) else String(can["message"])
	banner.visible = banner.text != ""
	var tier := int(prog["tier"])
	for t in columns:
		var lbl: Label = (columns[t] as Control).get_meta(&"tier_label")
		lbl.add_theme_color_override("font_color", UIKit.TEAL if int(t) == tier else (UIKit.IVORY if int(t) < tier else UIKit.IVORY_DIM))
	for c in cells:
		c.refresh()
	_refresh_detail()


func cell_state(tier: int, track: String) -> String:
	var st := Wallet.season_state(sid)
	return Economy.cell_state(sid, tier, track, int(st["xp"]), bool(st["premium"]), st["claimed"])


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


# ------------------------------------------------------------------ detail
func focus(tier: int, track: String) -> void:
	focus_tier = tier
	focus_track = track
	for c in cells:
		UIKit.set_selected(c, c.tier == tier and c.track == track)
	_refresh_detail()


func _build_detail() -> void:
	detail_box.add_child(UIKit.styled("", "overline", UIKit.IVORY_MUTED))
	var art := RewardArt.new()
	art.custom_minimum_size = Vector2(0, 170)
	art.screen = self
	detail_box.add_child(art)
	var name_l := UIKit.styled("", "headline")
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_box.add_child(name_l)
	var type_l := UIKit.styled("", "caption", UIKit.IVORY_MUTED)
	detail_box.add_child(type_l)
	var state_l := UIKit.styled("", "body", UIKit.IVORY)
	state_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	state_l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_box.add_child(state_l)
	var action := UIKit.secondary("", Vector2(0, 84))
	action.name = "DetailAction"
	action.pressed.connect(_on_detail_action)
	detail_box.add_child(action)
	_d = {"over": detail_box.get_child(0), "art": art, "name": name_l, "type": type_l, "state": state_l, "action": action}


func _refresh_detail() -> void:
	if _d.is_empty():
		return
	var r := Economy.reward_at(sid, focus_tier, focus_track)
	var st := cell_state(focus_tier, focus_track)
	(_d["over"] as Label).text = "Tier %d · %s" % [focus_tier, "Premium track" if focus_track == "premium" else "Free track"]
	(_d["art"] as RewardArt).reward = r
	(_d["art"] as RewardArt).request()
	(_d["name"] as Label).text = reward_name(r) if not r.is_empty() else "No Free reward at this tier"
	(_d["type"] as Label).text = reward_type(r) if not r.is_empty() else ""
	var action: Button = _d["action"]
	var state_l: Label = _d["state"]
	action.visible = true
	action.disabled = false
	var xp := int(Wallet.season_state(sid)["xp"])
	var need := int(Catalogue.season_tiers(sid)[focus_tier - 1]["xp"]) - xp
	match st:
		"empty":
			state_l.text = "This tier's reward is on the Premium track."
			action.visible = false
		"locked":
			state_l.text = "Reach Tier %d to unlock (%s more Season XP)." % [focus_tier, Catalogue.format_coins(maxi(0, need))]
			action.visible = false
		"premium_locked":
			state_l.text = "You've reached this tier. Unlock Premium (%s Coins in the Shop) to claim it — every Premium reward you've earned becomes claimable." % Catalogue.format_coins(Catalogue.price(String(Catalogue.season(sid).get("premium_item", ""))))
			action.text = "Get Premium in the Shop"
		"claimable":
			state_l.text = "Ready to claim. It goes straight to your %s." % ("wallet" if r.has("coins") else "Locker")
			action.text = "Claim"
			action.disabled = _busy or not bool(Wallet.can_transact()["ok"])
		"claimed":
			if r.has("coins"):
				state_l.text = "Claimed: added to your Coins."
				action.visible = false
			else:
				state_l.text = "Claimed. It's yours to keep, in your Locker."
				action.text = "Wear it in the Locker"
	action.accessibility_name = "%s, %s" % [(_d["name"] as Label).text, action.text]


func _on_detail_action() -> void:
	var st := cell_state(focus_tier, focus_track)
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
	if _busy:
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


## One reward cell on the track.
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
		UIKit.make_card(self, Vector2(SeasonScreen.CELL, SeasonScreen.CELL + 12.0),
			Color(UIKit.SLATE_HI, 0.96) if tr == "free" else Color("3a3020"))
		art = RewardArt.new()
		art.screen = s
		art.cell = self
		art.reward = Economy.reward_at(s.sid, t, tr)
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		UIKit.face_of(self).add_child(art)
		art.request()

	func refresh() -> void:
		state = screen.cell_state(tier, track)
		art.state = state
		art.queue_redraw()
		modulate.a = 0.45 if state == "empty" else 1.0
		disabled = false
		var r := Economy.reward_at(screen.sid, tier, track)
		var label: String = {"locked": "locked", "premium_locked": "earned, needs Premium", "claimable": "ready to claim",
			"claimed": "claimed", "empty": "no reward"}.get(state, state)
		accessibility_name = "Tier %d %s: %s, %s" % [tier, track, SeasonScreen.reward_name(r) if not r.is_empty() else "none", label]


## A reward's picture (cell or detail): a cached portrait for runner items,
## the badge/name card, Coins; with the state drawn over it.
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
			var look := Cosmetics.sanitize(Save.data["cosmetic"])
			look[f] = String(parts[1])
			var framing: String = {"outfit": "body", "hat": "head", "shoes": "feet"}.get(f, "")
			if framing != "":
				var ps := Portraits.shared()
				pic_key = Portraits.key_for(look, TC.Role.RUNNER, framing)
				var t := ps.portrait(look, TC.Role.RUNNER, "pass:%s" % id, framing)
				if ps.has_picture(pic_key):
					tex = t
				elif not ps.portrait_ready.is_connected(_on_pic):
					ps.portrait_ready.connect(_on_pic)
		queue_redraw()

	func _on_pic(k: String, t: Texture2D) -> void:
		if k == pic_key and is_instance_valid(self):
			tex = t
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var c := size * 0.5
		var s := minf(size.x, size.y)
		if cell == null:
			draw_style_box(UIKit.box(Color(UIKit.NAVY, 0.38), UIKit.R_SMALL), r)
		if reward.is_empty():
			var f0 := UIKit.font_w(600)
			var txt := "—"
			draw_string(f0, Vector2(c.x - 8, c.y + 8), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, UIKit.IVORY_DIM)
			return
		var dim := state in ["locked"]
		if reward.has("coins"):
			CommerceArt.coin(self, c + Vector2(0, -s * 0.08), s * 0.24, dim)
			var f := UIKit.font_num(800)
			var t2 := Catalogue.format_coins(int(reward["coins"]))
			var fs := int(clampf(s * 0.15, 16.0, 30.0))
			var w := f.get_string_size(t2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(f, Vector2(c.x - w * 0.5, c.y + s * 0.34), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UIKit.AMBER)
		else:
			var id := String(reward["item"])
			var kind := String(Catalogue.split(id)[0])
			if kind == "badge":
				CommerceArt.badge(self, id, c, s * 0.3)
			elif kind == "card":
				var cr := Rect2(c - Vector2(size.x * 0.44, s * 0.17), Vector2(size.x * 0.88, s * 0.34))
				CommerceArt.name_card(self, cr, id, "", "", 14)
			elif tex != null:
				draw_texture_rect(tex, Rect2(c - Vector2(s, s) * 0.46, Vector2(s, s) * 0.92), false, Color(1, 1, 1, 0.5 if dim else 1.0))
			elif kind == "emote":
				var eid := TC.EMOTES.find(String(Catalogue.split(id)[1]))
				Icons.draw_shape(self, Icons.emote_icon(eid) if eid >= 0 else "smile", c, s * 0.24, Color(UIKit.AMBER, 0.5 if dim else 1.0))
			else:
				var col := Color(UIKit.IVORY, 0.1)
				draw_circle(c + Vector2(0, -s * 0.16), s * 0.13, col)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.2, s * 0.32), c + Vector2(-s * 0.16, s * 0.02),
					c + Vector2(0, -s * 0.03), c + Vector2(s * 0.16, s * 0.02), c + Vector2(s * 0.2, s * 0.32)]), col)
		# state marks (shape + colour, never colour alone)
		var corner := Vector2(size.x - 20.0, 20.0)
		match state:
			"locked":
				draw_rect(r, Color(UIKit.NAVY, 0.35))
				Icons.draw_shape(self, "lock", corner, 10.0, UIKit.IVORY_MUTED)
			"premium_locked":
				draw_rect(r, Color(UIKit.NAVY, 0.25))
				draw_circle(corner, 13.0, UIKit.AMBER)
				Icons.draw_shape(self, "lock", corner, 8.0, UIKit.NAVY)
			"claimable":
				var g := UIKit.box(Color(0, 0, 0, 0), UIKit.R_CARD, 3, UIKit.AMBER, 0)
				g.draw_center = false
				draw_style_box(g, r.grow(-2.0))
				draw_circle(corner, 12.0, UIKit.AMBER)
				Icons.draw_shape(self, "plus", corner, 8.0, UIKit.NAVY)
			"claimed":
				draw_circle(corner, 13.0, UIKit.TEAL)
				Icons.draw_shape(self, "check", corner, 8.0, UIKit.NAVY)
