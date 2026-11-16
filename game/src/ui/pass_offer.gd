class_name PassOffer
extends RefCounted
## The Season Pass offer (2.2 build 15): a poster over the Season Pass when
## it opens (a player without Premium; at most once every SHOW_GAP_S), and
## again from the pass's "Get Premium" button.  Three Premium outfits stand
## in 3D on the right (tiers 1, 100 and 15); the left says what Premium holds
## (all counted from the catalogue) and sells it two ways:
##   * from Apple (com.idlery.ultimatetrifecta.pass.s1, a permanent
##     non-consumable at StoreKit's own localized price, never a stored one)
##   * for Coins (the Shop's confirm sheet, as before)
## No made-up "was" price: the only prices shown are real ones.

const PRODUCT := "com.idlery.ultimatetrifecta.pass.s1"
const SHOW_GAP_S := 10 * 60
## the outfits on the poster: [item, tier] (left, centre, right)
const SHOWCASE := [["outfit:night_owl", 1], ["outfit:dr_doom", 100], ["outfit:glow_jogger", 15]]

static var _last_shown_ms := -SHOW_GAP_S * 1000


static func premium_item() -> String:
	return String(Catalogue.season(Catalogue.current_season_id()).get("premium_item", "season:s1:premium"))


## Premium's contents, counted from the season table: {rewards, outfits, coins}.
static func contents() -> Dictionary:
	var sid := Catalogue.current_season_id()
	var rewards := 0
	var outfits := 0
	var coins := 0
	for t in Catalogue.season_tiers(sid):
		var r: Variant = t.get("premium")
		if r is Dictionary and not (r as Dictionary).is_empty():
			rewards += 1
			coins += int((r as Dictionary).get("coins", 0))
			if String((r as Dictionary).get("item", "")).begins_with("outfit:"):
				outfits += 1
	return {"rewards": rewards, "outfits": outfits, "coins": coins}


## On opening the Season Pass: the offer, unless Premium is owned or it was
## shown a moment ago.  Returns true if shown.
static func show_on_open(screen: Screen) -> bool:
	if Wallet.premium(Catalogue.current_season_id()) or App.dev_automation or not LoginFlow.enabled:
		return false
	if Time.get_ticks_msec() - _last_shown_ms < SHOW_GAP_S * 1000:
		return false
	popup(screen)
	return true


static func popup(screen: Screen) -> Control:
	_last_shown_ms = Time.get_ticks_msec()
	var root := Control.new()
	root.name = "PassOffer"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.08, 0.84)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var vis := screen.get_viewport().get_visible_rect().size
	var poster := Poster.new()
	poster.big = true
	var w := minf(vis.x * 0.9, 1240.0)
	var h := minf(vis.y * 0.88, w * 0.58)
	poster.custom_minimum_size = Vector2(w, h)
	poster.size = Vector2(w, h)
	poster.position = (vis - Vector2(w, h)) * 0.5
	root.add_child(poster)
	var close := func() -> void:
		if is_instance_valid(root):
			Motion.vanish(root, root.queue_free, 0.15)
	_fill(poster, screen, close)
	screen.add_child(root)
	if not UIKit.reduced_motion():
		poster.pivot_offset = poster.size * 0.5
		poster.scale = Vector2.ONE * 0.86
		poster.modulate.a = 0.0
		var tw := poster.create_tween().set_parallel(true)
		tw.tween_property(poster, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(poster, "modulate:a", 1.0, 0.18)
	screen.push_modal(root, close)
	Sfx.play("whoosh")
	return root


## (2.2 build 16) the same poster as a banner inside a page (the Shop's
## Season 1 section): no close button, its own size.
static func banner(screen: Screen, sz: Vector2) -> Control:
	var poster := Poster.new()
	poster.name = "PassBanner"
	poster.big = true
	poster.custom_minimum_size = sz
	poster.size = sz
	_fill(poster, screen, Callable())
	return poster


static func _fill(poster: Poster, screen: Screen, close: Callable) -> void:
	var sz := poster.custom_minimum_size
	# (2.2 build 16) a narrow banner (the Shop's panel) stacks: the outfits
	# on top, the words and buttons under them
	var tall := sz.x < 900.0
	poster.tall = tall
	var st_pos := Vector2(sz.x * 0.05, sz.y * 0.11) if tall else Vector2(sz.x * 0.47, sz.y * 0.06)
	var st_size := Vector2(sz.x * 0.9, sz.y * 0.36) if tall else Vector2(sz.x * 0.5, sz.y * 0.8)
	# the outfits, in their own little 3D stage
	var stage := Preview3D.new(Vector2i(int(st_size.x), int(st_size.y)))
	stage.name = "Outfits"
	stage.position = st_pos
	stage.size = st_size
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	poster.add_child(stage)
	stage.aim(Vector3(0, 1.15, 5.6), Vector3(0, 0.95, 0))
	var xs := [-1.15, 0.0, 1.15]
	var zs := [0.25, -0.2, 0.25]
	for i in SHOWCASE.size():
		# shown as the Shop shows outfits: no hat, high-tops
		var look := Cosmetics.DEFAULT.duplicate()
		look["hat"] = "none"
		look["shoes"] = "sneakers"
		var s := Catalogue.split(String(SHOWCASE[i][0]))
		look[String(s[0])] = String(s[1])
		stage.show_character(TC.Role.RUNNER, Cosmetics.sanitize(look), Vector3(xs[i], 0, zs[i]), PI - float(xs[i]) * 0.28)
	# their names and tiers under them
	var tags := UIKit.hbox(0)
	tags.position = Vector2(st_pos.x, st_pos.y + st_size.y - (0.0 if tall else sz.y * 0.06))
	tags.custom_minimum_size = Vector2(st_size.x, 0)
	tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	poster.add_child(tags)
	for it in [SHOWCASE[0], SHOWCASE[1], SHOWCASE[2]]:
		var tv := UIKit.vbox(0)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var nm := UIKit.styled(Catalogue.display_name(String(it[0])), "label", UIKit.IVORY, HORIZONTAL_ALIGNMENT_CENTER)
		nm.add_theme_font_size_override("font_size", 19)
		tv.add_child(nm)
		tv.add_child(UIKit.styled("TIER %d" % int(it[1]), "overline", UIKit.AMBER, HORIZONTAL_ALIGNMENT_CENTER))
		tags.add_child(tv)
	# the words and buttons, left
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 32)
	m.add_theme_constant_override("margin_right", 24)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	poster.add_child(m)
	var v := UIKit.vbox(10)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(v)
	var top := UIKit.hbox(10)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sname := String(Catalogue.season(Catalogue.current_season_id()).get("name", ""))
	var ov := UIKit.chip(("SEASON %d · %s" % [int(Catalogue.season(Catalogue.current_season_id()).get("number", 1)), sname]).to_upper(),
		Color("ff7aa2"), UIKit.NAVY, UIKit.T_OVERLINE + 2)
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(ov)
	top.add_child(UIKit.spacer_h())
	if close.is_valid():
		var x := UIKit.icon_button("close")
		x.name = "Close"
		x.accessibility_name = "Close"
		x.pressed.connect(close)
		top.add_child(x)
	v.add_child(top)
	if tall:
		var gap := Control.new()
		gap.custom_minimum_size.y = sz.y * 0.4
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(gap)
	var text_w := (sz.x - 64.0) if tall else sz.x * 0.44
	var title := UIKit.outlined(UIKit.label("PREMIUM PASS", 46 if tall else 58, UIKit.AMBER_HI, true), 11)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(title)
	var c := contents()
	var sub := UIKit.label("Unlock the Premium track: %d more rewards, and every one you've already reached is yours at once." % int(c["rewards"]),
		23, UIKit.IVORY, false)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size.x = text_w
	sub.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sub)
	var stats := UIKit.hbox(10)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.custom_minimum_size.x = text_w
	stats.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for st in [["shirt", str(int(c["outfits"])), "outfits"], ["star", str(int(c["rewards"])), "rewards"],
			["coin", Catalogue.format_coins(int(c["coins"])), "Coins back"]]:
		stats.add_child(_stat(String(st[0]), String(st[1]), String(st[2])))
	v.add_child(stats)
	v.add_child(UIKit.spacer_v())
	# the two ways to buy it
	var row := UIKit.hbox(12)
	row.name = "BuyRow"
	var buy := UIKit.primary("Get Premium", Vector2(text_w * 0.62, 92), 28)
	buy.name = "BuyApple"
	row.add_child(buy)
	var coins := UIKit.quiet("%s Coins" % Catalogue.format_coins(Catalogue.price(premium_item())), Vector2(0, 92), UIKit.T_LABEL + 1)
	coins.name = "BuyCoins"
	coins.icon = null
	row.add_child(coins)
	v.add_child(row)
	var fine := UIKit.styled("", "caption", UIKit.IVORY_MUTED)
	fine.name = "Fine"
	fine.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fine.custom_minimum_size.x = text_w
	fine.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(fine)
	var paint := func() -> void:
		if not is_instance_valid(buy):
			return
		var pv := Purchases.view(PRODUCT)
		var st := String(pv["state"])
		if Wallet.premium(Catalogue.current_season_id()):
			buy.text = "Premium unlocked"
			buy.disabled = true
			coins.visible = false
			fine.text = "Every Premium reward you've reached is ready to claim in the Season Pass."
			return
		buy.disabled = false
		if bool(pv["can_buy"]):
			buy.text = "Get Premium · %s" % String(pv["price"])
		elif st in ["purchasing", "pending_approval", "delivering"]:
			buy.text = String(pv["button"])
		else:
			buy.text = "Get Premium"
		var msg := String(pv["message"])
		fine.text = "One purchase for Season %d, yours to keep. Not a subscription. Cosmetic only: tiers are earned by playing." % \
			int(Catalogue.season(Catalogue.current_season_id()).get("number", 1))
		if not bool(pv["can_buy"]) and msg != "" and not st in ["purchasing", "pending_approval"]:
			fine.text = msg
	paint.call()
	buy.pressed.connect(func() -> void:
		var pv := Purchases.view(PRODUCT)
		if bool(pv["can_buy"]):
			var r := Purchases.buy(PRODUCT)
			if not bool(r.get("ok", false)):
				screen.dialog(String(r.get("message", "")))
		elif String(pv["message"]) != "":
			screen.dialog(String(pv["message"]))
		paint.call())
	coins.pressed.connect(func() -> void:
		if close.is_valid():
			close.call()
		if screen is ShopScreen:
			(screen as ShopScreen)._buy_premium_with_coins()
			return
		ShopScreen.focus_section = "season"
		ShopScreen.focus_item = premium_item()
		NavShell.go("shop"))
	var on_change := func(_a: Variant = null) -> void: paint.call()
	Purchases.state_changed.connect(on_change)
	Purchases.products_changed.connect(on_change)
	Wallet.changed.connect(on_change)
	poster.tree_exiting.connect(func() -> void:
		for sg in [Purchases.state_changed, Purchases.products_changed, Wallet.changed]:
			if (sg as Signal).is_connected(on_change):
				(sg as Signal).disconnect(on_change))
	if Purchases.products_state in ["idle", "failed"]:
		Purchases.load_products()
	UIKit.soft_focus.call_deferred(buy)
	poster.accessibility_name = "Season Pass Premium. %d outfits, %d rewards, %s Coins back." % [int(c["outfits"]), int(c["rewards"]), Catalogue.format_coins(int(c["coins"]))]


static func _stat(icon: String, n: String, what: String) -> Control:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", UIKit.box(Color(UIKit.NAVY, 0.6), 16, 1, Color(UIKit.IVORY, 0.12), 12))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := UIKit.hbox(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var ic := Icons.IconRect.new(icon, UIKit.AMBER, 30)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var tv := UIKit.vbox(0)
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(UIKit.styled(n, "num", UIKit.IVORY))
	var wl := UIKit.styled(what, "caption", UIKit.IVORY_MUTED)
	wl.add_theme_font_size_override("font_size", 17)
	tv.add_child(wl)
	h.add_child(tv)
	return p


## The Pass poster: a festive magenta-to-midnight backdrop, rays from behind
## the outfits, snow-white and gold confetti, a gold frame; a lit stage arc
## under the three outfits.
class Poster:
	extends GlamPoster
	var tall := false

	func _ready() -> void:
		top_col = Color("5a1e78")
		bot_col = Color("101446")
		ray_col = Color(1.0, 0.7, 0.95, 0.06)
		glow_col = Color(1.0, 0.6, 0.85, 0.05)
		focus = Vector2(0.5, 0.3) if tall else Vector2(0.72, 0.5)
		confetti_x = Vector2(0.0, 1.0) if tall else Vector2(0.45, 1.0)
		confetti_cols = [UIKit.AMBER, Color("ff7aa2"), Color("8fd3ff"), UIKit.IVORY, UIKit.AMBER_HI]
		super._ready()

	func _paint_art(c: Vector2) -> void:
		# the stage: a lit ellipse the outfits stand on
		var ped := Vector2(size.x * 0.5, size.y * 0.44) if tall else Vector2(size.x * 0.72, size.y * 0.78)
		for k in 5:
			var e := PackedVector2Array()
			var rx := size.x * ((0.4 if tall else 0.25) - 0.035 * k)
			for j in 40:
				var a := TAU * float(j) / 40.0
				e.append(ped + Vector2(cos(a) * rx, sin(a) * rx * 0.16))
			fill_clipped(e, Color(1.0, 0.75, 0.95, 0.07 + 0.03 * k))
		# a soft spotlight cone from the top
		var sp := PackedVector2Array([Vector2(c.x - size.x * 0.04, 0), Vector2(c.x + size.x * 0.04, 0),
			Vector2(ped.x + size.x * 0.24, ped.y), Vector2(ped.x - size.x * 0.24, ped.y)])
		fill_clipped(sp, Color(1, 0.95, 1, 0.045 + 0.015 * sin(t * 1.4)))
