extends RefCounted
## V7 menus (brief §4-§7): the Locker, Season Pass and Shop measured by
## their final allocated rects at real landscape device sizes (iPhone SE,
## notched iPhones, a Pro Max, iPad, and the owner's 2048×946 / 1536×710
## screenshot aspects), not by requested minimum sizes:
##  - both Season rows whole inside the track and the safe area, the detail
##    action reachable, Claim all on screen, cells at least 44 pt;
##  - Locker categories whole, columns from the grid's final width, every
##    card's art inside its well (emote glyphs centred), state rows aligned,
##    Save look / Undo inside the panel;
##  - finger swipes that start on a glyph, a portrait, a label or a card's
##    empty corner scroll and never select, equip, claim or buy;
##  - Free / Premium / claim states and the service-off reasons;
##  - the emote icon set's drawn bounds; outfit pictures' neutral look.
## The service-on states use the test-double service and simulated store
## (tests/commerce_rig.gd); service-off is the shipped configuration.
var t
var rig
var _saved := {}

## px size, point scale, safe insets in points (left, top, right, bottom)
const DEVICES := {
	"se_667x375": [Vector2i(1334, 750), 2.0, Rect2(0, 0, 0, 0)],
	"x_812x375": [Vector2i(2436, 1125), 3.0, Rect2(44, 0, 44, 21)],
	"p14_844x390": [Vector2i(2532, 1170), 3.0, Rect2(47, 0, 47, 21)],
	"max_926x428": [Vector2i(2778, 1284), 3.0, Rect2(47, 0, 47, 21)],
	"ipad_1024x768": [Vector2i(2048, 1536), 2.0, Rect2(0, 24, 0, 20)],
	"shot_2048x946": [Vector2i(2048, 946), 2.426, Rect2(47, 0, 47, 21)],
	"shot_1536x710": [Vector2i(1536, 710), 1.821, Rect2(47, 0, 47, 21)],
}


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


func _begin(with_service: bool = true) -> void:
	rig = preload("res://tests/commerce_rig.gd").new(t)
	await rig.begin(with_service, with_service)
	if with_service:
		await rig.sign_in()
	_saved = {"emulate": Input.emulate_touch_from_mouse, "device": Controls.device, "size": t.get_tree().root.size,
		"emu": UIKit.emulation.duplicate()}
	Input.emulate_touch_from_mouse = true
	Controls.device = "touch"
	Save.data["onboarded"] = true
	t.get_tree().root.notification(Window.NOTIFICATION_WM_MOUSE_ENTER)
	for c in t.get_tree().root.get_children():
		if c is BootCurtain:
			c.queue_free()
	await _frames(2)


func _end() -> void:
	Input.emulate_touch_from_mouse = _saved["emulate"]
	Controls.device = _saved["device"]
	UIKit.emulation = _saved["emu"]
	t.get_tree().root.size = _saved["size"]
	await rig.end()


func _device(key: String) -> void:
	var d: Array = DEVICES[key]
	UIKit.emulation = {"scale": float(d[1]), "safe": d[2]}
	t.get_tree().root.size = d[0]
	await _frames(3)


func _safe() -> Rect2:
	var vp: Viewport = t.get_viewport()
	return UIKit.safe_rect(vp, vp.get_visible_rect().size)


func _inside(inner: Rect2, outer: Rect2) -> bool:
	return outer.grow(0.6).encloses(inner)


func _grant_everything() -> void:
	var pid := Cloud.profile_id()
	for it in Catalogue.all_items():
		var id := String(it["id"])
		if Catalogue.is_runner_item(id) or id.begins_with("card:") or id.begins_with("badge:"):
			if Catalogue.has_art(id):
				rig.svc.wallet(pid)["entitlements"][id] = {"source": "admin"}
	await Wallet.refresh()


# ------------------------------------------------------------------ Season Pass
func test_pass_rows_and_detail_action_fit_every_device() -> void:
	await _begin()
	rig.svc.wallet(Cloud.profile_id())["season"]["s1"]["xp"] = 3450   # tier 15
	await Wallet.refresh()
	var report: Array = []
	for key in DEVICES:
		await _device(key)
		App.goto(SeasonScreen)
		await _frames(6)
		var sp := App.screen as SeasonScreen
		var safe := _safe()
		for spec in [[1, "free"], [15, "premium"], [30, "premium"], [30, "free"]]:
			sp.focus(int(spec[0]), String(spec[1]))
			await sp._scroll_to(int(spec[0]))
			await _frames(2)
			var track := sp.track_scroll.get_global_rect()
			var hbar := sp.track_scroll.get_h_scroll_bar().get_combined_minimum_size().y
			var rows := {"free": [], "premium": []}
			for c in sp.cells:
				var r: Rect2 = (c as Control).get_global_rect()
				if r.end.x <= track.position.x or r.position.x >= track.end.x:
					continue
				(rows[c.track] as Array).append(r)
			for tr in rows:
				t.check(not (rows[tr] as Array).is_empty(), "%s: %s row in view" % [key, tr])
				for r in rows[tr]:
					t.check((r as Rect2).position.y >= track.position.y - 0.5 and (r as Rect2).end.y <= track.end.y - hbar + 0.5,
						"%s: %s cell whole inside the track (%s in %s)" % [key, tr, r, track])
					t.check((r as Rect2).end.y <= safe.end.y + 0.5, "%s: %s cell above the safe bottom (%.1f <= %.1f)" % [key, tr, (r as Rect2).end.y, safe.end.y])
					t.check((r as Rect2).size.y >= UIKit.touch_min() - 0.5 and (r as Rect2).size.x >= UIKit.touch_min() - 0.5,
						"%s: a cell is a full touch target" % key)
			var focused: Control = sp._cell(int(spec[0]), String(spec[1]))
			t.check(track.grow(0.5).encloses(focused.get_global_rect()), "%s: the selected tier %d is scrolled into view" % [key, spec[0]])
			var act: Button = sp._d["action"]
			if act.visible:
				t.check(_inside(act.get_global_rect(), safe), "%s: detail action inside the safe area" % key)
				t.check(_inside(act.get_global_rect(), sp.detail_panel.get_global_rect()), "%s: detail action inside its panel" % key)
				t.check(act.get_global_rect().size.y >= UIKit.touch_min() - 0.5, "%s: detail action is 44 pt" % key)
		t.check(_inside(sp.claim_all_btn.get_global_rect(), safe), "%s: Claim all on screen" % key)
		_check_top_row(sp, key)
		t.check(_inside(sp.track_region.get_global_rect(), safe), "%s: the track region inside the safe area" % key)
		t.check(_inside(sp.detail_panel.get_global_rect(), safe), "%s: the detail panel inside the safe area" % key)
		var fr: Rect2 = sp._cell(15, "free").get_global_rect()
		var pr: Rect2 = sp._cell(15, "premium").get_global_rect()
		t.near(fr.position.x, pr.position.x, 0.5, "%s: Free and Premium share the tier column" % key)
		report.append("%s view %s: free y %.0f-%.0f, premium y %.0f-%.0f, cell %.0fx%.0f, safe bottom %.0f, action y %.0f-%.0f" % [
			key, t.get_viewport().get_visible_rect().size, fr.position.y, fr.end.y, pr.position.y, pr.end.y, pr.size.x, pr.size.y,
			safe.end.y, (sp._d["action"] as Control).get_global_rect().position.y, (sp._d["action"] as Control).get_global_rect().end.y])
	for line in report:
		print("[pass bounds] " + line)
	await _end()


func test_pass_service_off_is_honest_and_still_fits() -> void:
	await _begin(false)
	for key in ["se_667x375", "p14_844x390", "ipad_1024x768"]:
		await _device(key)
		App.goto(SeasonScreen)
		await _frames(6)
		var sp := App.screen as SeasonScreen
		var safe := _safe()
		t.check(not sp.claim_all_btn.visible, "%s: no Claim all that can't work" % key)
		t.check(sp.banner.visible and sp.banner.text == "Rewards unavailable right now", "%s: the short status: %s" % [key, sp.banner.text])
		sp.focus(1, "free")
		await _frames(2)
		t.eq(sp.display_state(1, "free"), "earned", "%s: tier 1 is earned, not claimable while the service is off" % key)
		var state_t := (sp._d["state"] as Label).text
		t.check(not state_t.contains("Ready to claim"), "%s: never 'Ready to claim' over a dead button" % key)
		t.check(state_t.contains("It stays earned"), "%s: an earned reward doesn't look lost: %s" % [key, state_t])
		t.eq((sp._d["chip"] as Control).get("text_l").text, "Earned", "%s: the state chip says Earned" % key)
		# the reason is said once, on the pass's status line (not repeated in the detail)
		t.check(sp.status_l.text.contains("aren't available in this version"), "%s: the status line says why: %s" % [key, sp.status_l.text])
		t.check(not (sp._d["reason"] as Label).visible, "%s: no second copy of it in the detail" % key)
		var sr := sp.status_row.get_global_rect()
		t.check(_inside(sr, sp.track_panel.get_global_rect()) and _inside(sr, safe), "%s: the status line whole in the pass panel" % key)
		t.check((sp._d["action"] as Button).disabled, "%s: Claim is visibly unavailable" % key)
		t.check(_inside((sp._d["action"] as Control).get_global_rect(), safe), "%s: and on screen" % key)
		for c in sp.cells:
			var r: Rect2 = (c as Control).get_global_rect()
			var track := sp.track_scroll.get_global_rect()
			if r.end.x > track.position.x and r.position.x < track.end.x:
				t.check(r.end.y <= safe.end.y + 0.5, "%s: %s row whole with the service off" % [key, c.track])
		var texts: Array = sp.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
		t.check(not texts.any(func(s: String) -> bool: return s.contains("isn't set up in this build. Your items")), "%s: no developer paragraph in the browsing area" % key)
		# browsing and previewing still work
		sp._on_cell(2, "free")
		await _frames(1)
		t.eq([sp.focus_tier, sp.focus_track], [2, "premium"], "%s: a blank Free slot explains the tier's Premium reward" % key)
		sp.focus(1, "premium")
		await _frames(1)
		t.eq(sp.display_state(1, "premium"), "premium_locked", "%s: tier 1 Premium is reached, needs Premium" % key)
		t.eq((sp._d["action"] as Button).text, "View Premium", "%s: Premium resolves in the Shop, honestly worded" % key)
		t.check((sp._d["reason"] as Label).visible and (sp._d["reason"] as Label).text.contains("can't be bought right now"), "%s: with the reason" % key)
		var rr := (sp._d["reason"] as Control).get_global_rect()
		t.check(rr.end.y <= (sp._d["action"] as Control).get_global_rect().position.y + 0.5 and _inside(rr, sp.detail_panel.get_global_rect()),
			"%s: the reason sits whole right above the action" % key)
	await _end()


func test_pass_free_premium_and_claim_states() -> void:
	await _begin()
	var pid := Cloud.profile_id()
	rig.svc.wallet(pid)["season"]["s1"]["xp"] = 1450   # tier 8
	await Wallet.refresh()
	App.goto(SeasonScreen)
	await _frames(6)
	var sp := App.screen as SeasonScreen
	t.check(sp.claim_all_btn.visible and not sp.banner.visible, "service on: Claim all, no unavailable line")
	sp.focus(3, "free")
	t.eq(sp.display_state(3, "free"), "claimable", "earned and claimable")
	t.check((sp._d["state"] as Label).text.begins_with("Earned at Tier 3"), "says it's earned: %s" % (sp._d["state"] as Label).text)
	t.eq((sp._d["action"] as Button).text, "Claim", "one action: Claim")
	t.check(not (sp._d["action"] as Button).disabled and not (sp._d["reason"] as Label).visible, "available, no reason shown")
	sp.focus(4, "premium")
	t.eq(sp.display_state(4, "premium"), "premium_locked", "reached, needs Premium")
	t.eq((sp._d["action"] as Button).text, "Get Premium", "Premium in the Shop")
	sp.focus(20, "premium")
	t.eq(sp.display_state(20, "premium"), "locked", "not reached")
	t.eq((sp._d["action"] as Button).text, "View Premium", "a locked Premium reward without Premium: the requirement is never hidden")
	t.check((sp._d["state"] as Label).text.contains("XP to unlock") and (sp._d["state"] as Label).text.contains("Needs Premium"), "it says what's needed")
	sp.focus(19, "free")
	t.eq(sp.display_state(19, "free"), "locked", "a Free reward not reached")
	t.check(not (sp._d["action"] as Button).visible, "no action for a locked Free tier (nothing to buy, nothing to claim)")
	sp._on_cell(2, "free")
	t.eq([sp.focus_tier, sp.focus_track], [2, "premium"], "a blank Free slot selects the tier's Premium reward")
	t.check((sp._d["state"] as Label).text.begins_with("No Free reward at Tier 2"), "and says so")
	# late Premium: every Premium reward already earned becomes claimable
	rig.svc.wallet(pid)["season"]["s1"]["premium"] = true
	rig.svc.wallet(pid)["entitlements"]["season:s1:premium"] = {"source": "coin_purchase"}
	await Wallet.refresh()
	await _frames(2)
	t.eq(sp.display_state(4, "premium"), "claimable", "late Premium: tier 4 Premium claimable")
	var n := Wallet.claimable("s1").size()
	t.eq(sp.claim_all_btn.text, "Claim all (%d)" % n, "Claim all counts every earned reward")
	sp._claim_all()
	await rig.until(func() -> bool: return sp.claim_all_btn.text == "Nothing to claim")
	t.eq(sp.display_state(4, "premium"), "claimed", "claimed")
	var bal := Wallet.balance()
	sp._claim_all()
	await _frames(10)
	t.eq(Wallet.balance(), bal, "Claim all again grants nothing (idempotent)")
	await _end()


## Back, every navigation tab and the Coins chip: whole, inside the safe
## area, full touch targets.
func _check_top_row(scr: Screen, key: String) -> void:
	var safe := _safe()
	var top := scr.find_child("TopBar", true, false) as Control
	t.check(top != null, "%s: the top row exists" % key)
	if top == null:
		return
	for b in top.find_children("*", "BaseButton", true, false):
		var r := (b as Control).get_global_rect()
		t.check(_inside(r, safe), "%s %s: %s inside the safe area (%s)" % [key, scr.name, b.name, r])
		t.check(r.size.y >= UIKit.touch_min() - 0.5 and r.size.x >= UIKit.touch_min() - 0.5, "%s: %s is a full touch target" % [key, b.name])


# ------------------------------------------------------------------ Locker
func test_locker_bounds_at_every_device() -> void:
	await _begin()
	await _grant_everything()
	var report: Array = []
	for key in DEVICES:
		await _device(key)
		NavShell.open("locker")
		await _frames(6)
		var c := App.screen as CreatorScreen
		var safe := _safe()
		t.check(_inside(c.panel.get_global_rect(), safe), "%s: the item panel inside the safe area" % key)
		_check_top_row(c, key)
		var strip := (c.tab_btns["outfit"] as Control).get_parent().get_parent() as Control
		for k in c.tab_btns:
			t.check(_inside((c.tab_btns[k] as Control).get_global_rect(), strip.get_global_rect()), "%s: category %s whole" % [key, k])
		for tab in ["outfit", "move", "hat", "shoes", "face", "profile"]:
			c._select_tab(tab)
			await _frames(4)
			var panel_r := c.panel.get_global_rect()
			for g in c.grids:
				var grid := g as UIKit.AutoGrid
				var gw := grid.size.x
				t.check(gw <= c.scroll.size.x + 0.5, "%s %s: the grid fits the list's width" % [key, tab])
				t.eq(grid.columns, UIKit.columns_for(gw, grid.min_cell, grid.gap, grid.min_cols, grid.max_cols),
					"%s %s: columns come from the final width (%.0f)" % [key, tab, gw])
				t.check(grid.cell_w * grid.columns + grid.gap * (grid.columns - 1) <= gw + 0.5, "%s %s: the cells fit the row" % [key, tab])
			var rows := {}
			for card in c.cards:
				var cr: Rect2 = (card as Control).get_global_rect()
				t.check(cr.size.x <= panel_r.size.x, "%s %s: card narrower than the panel" % [key, tab])
				var well: Control = card.holder
				var wr := well.get_global_rect()
				t.check(cr.grow(0.5).encloses(wr), "%s %s: %s's well inside its card" % [key, tab, card.key])
				t.check(cr.grow(0.5).encloses((card.name_l as Control).get_global_rect()), "%s %s: %s's name inside its card" % [key, tab, card.key])
				var g2: Variant = card.get("glyph")
				if g2 is Control:
					var gr := (g2 as Control).get_global_rect()
					t.check(wr.grow(0.5).encloses(gr), "%s: %s glyph inside its well" % [key, card.key])
					t.near(gr.get_center().x, wr.get_center().x, 0.6, "%s: %s glyph centred across the well" % [key, card.key])
					t.near(gr.get_center().y, wr.get_center().y, 0.6, "%s: %s glyph centred down the well" % [key, card.key])
					# the drawn icon reaches E_EXTENT of the glyph's radius
					var rad := minf(gr.size.x, gr.size.y) * 0.45 * Icons.E_EXTENT
					t.check(wr.grow(-2.0).encloses(Rect2(gr.get_center() - Vector2(rad, rad), Vector2(rad, rad) * 2.0)),
						"%s: %s drawn emote inside the well with padding" % [key, card.key])
				if tab in ["outfit", "move"] and card == c.cards[0]:
					var g0 := (card as Control).get_parent() as GridContainer
					var off := Vector2.ZERO
					if g2 is Control:
						off = (g2 as Control).get_global_rect().get_center() - wr.get_center()
					report.append("%s %s: panel %.0fx%.0f, %d columns, card %.0fx%.0f, well %.0fx%.0f, glyph offset from well centre (%.1f, %.1f)" % [
						key, tab, panel_r.size.x, panel_r.size.y, g0.columns, cr.size.x, cr.size.y, wr.size.x, wr.size.y, off.x, off.y])
				var row_y := snappedf(cr.position.y, 1.0)
				var sy := snappedf((card.state_l as Control).get_global_rect().position.y, 0.1)
				if rows.has(row_y):
					t.near(sy, float(rows[row_y]), 0.6, "%s %s: state rows line up across a row" % [key, tab])
				else:
					rows[row_y] = sy
		# a change shows Save look / Undo, inside the panel and on screen
		c._select_tab("hat")
		await _frames(2)
		c._pick("hat", "none" if String(c.draft["hat"]) != "none" else "crown")
		await _frames(3)
		for b in [c.apply_btn, c.undo_btn]:
			t.check((b as Control).is_visible_in_tree(), "%s: %s shown for a change" % [key, (b as Button).text])
			t.check(_inside((b as Control).get_global_rect(), c.panel.get_global_rect()) and _inside((b as Control).get_global_rect(), safe),
				"%s: %s inside the panel and the safe area" % [key, (b as Button).text])
			t.check((b as Control).get_global_rect().size.y >= UIKit.touch_min() - 0.5, "%s: %s is 44 pt" % [key, (b as Button).text])
		c._on_cancel()
		await _frames(1)
	for line in report:
		print("[locker bounds] " + line)
	await _end()


# ------------------------------------------------------------------ Shop
func test_shop_bounds_at_every_device() -> void:
	await _begin()
	for key in DEVICES:
		await _device(key)
		App.goto(ShopScreen)
		await _frames(6)
		var shop := App.screen as ShopScreen
		var safe := _safe()
		t.check(_inside(shop.panel.get_global_rect(), safe), "%s: the Shop panel inside the safe area" % key)
		_check_top_row(shop, key)
		for sec in ["featured", "outfits", "accessories", "coins"]:
			shop.select_section(sec)
			await _frames(4)
			for b in shop.strip_btns.values():
				t.check(_inside((b as Control).get_global_rect(), (b as Control).get_parent().get_parent().get_global_rect()), "%s: section %s whole" % [key, (b as Button).text])
			var grid: UIKit.AutoGrid = null
			for c in shop.cards:
				if (c as Control).get_parent() is UIKit.AutoGrid:
					grid = (c as Control).get_parent()
			if grid != null:
				t.eq(grid.columns, UIKit.columns_for(grid.size.x, grid.min_cell, grid.gap, grid.min_cols, grid.max_cols), "%s %s: columns from the final width" % [key, sec])
				t.check(grid.size.x <= shop.scroll.size.x + 0.5, "%s %s: the grid fits the list" % [key, sec])
			for c in shop.cards:
				var cr := (c as Control).get_global_rect()
				t.check(cr.size.x <= shop.scroll.size.x + 0.5, "%s %s: card fits the list's width" % [key, sec])
				var art: Control = (c as ShopScreen.ShopCard).art
				t.check(cr.grow(0.5).encloses(art.get_global_rect()), "%s %s: %s picture inside its card (%s in %s)" % [key, sec, c.id, art.get_global_rect(), cr])
		for id in ["outfit:duck", "coins:1500", "season:s1:premium"]:
			shop._open_detail(id)
			await _frames(4)
			var act: Button = shop._d["action"]
			var st: Label = shop._d["status"]
			t.check(_inside(act.get_global_rect(), safe) and _inside(act.get_global_rect(), shop.panel.get_global_rect()), "%s %s: the action inside the panel and the safe area" % [key, id])
			t.check(act.get_global_rect().size.y >= UIKit.touch_min() - 0.5, "%s %s: the action is 44 pt" % [key, id])
			if st.visible:
				t.check(st.get_global_rect().end.y <= act.get_global_rect().position.y + 0.5, "%s %s: its status sits right above it" % [key, id])
			shop._close_detail()
			await _frames(2)
	await _end()


func test_outfit_pictures_use_a_neutral_look_and_the_runner_keeps_the_draft() -> void:
	await _begin()
	Save.data["cosmetic"] = Cosmetics.sanitize({"hat": "nightcap", "shoes": "slippers"})
	NavShell.open("locker")
	await _frames(4)
	var c := App.screen as CreatorScreen
	var checked := 0
	for card in c.cards:
		if card.field != "outfit":
			continue
		var look := CommerceArt.preview_look(c.draft, "outfit", card.key)
		t.eq(card.pic_key, Portraits.key_for(look, TC.Role.RUNNER, "body"), "%s card renders the curated look" % card.key)
		t.eq(String(look["hat"]), "none", "%s: no hat in the outfit picture" % card.key)
		t.check(String(look["shoes"]) == CommerceArt.PREVIEW_SHOES, "%s: plain shoes, not the player's slippers" % card.key)
		checked += 1
	t.check(checked >= 2, "outfit cards checked (%d)" % checked)
	t.eq(String(c.draft["hat"]), "nightcap", "the draft (the live runner) keeps the player's hat")
	t.eq(String(c.draft["shoes"]), "slippers", "and slippers")
	t.eq(CommerceArt.card_name(""), CommerceArt.SAMPLE_NAME, "a name card is never drawn without a name")
	t.eq(CommerceArt.card_name("Moon Pip"), "Moon Pip", "it shows the player's name")
	await _end()


# ------------------------------------------------------------------ swipes
func _px(p: Vector2) -> Vector2:
	return t.get_tree().root.get_final_transform() * p


func _press(at: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = _px(at)
	e.global_position = e.position
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	t.get_viewport().push_input(e)


func _swipe(from: Vector2, to: Vector2, steps: int = 12) -> void:
	_press(from, true)
	var prev := from
	for i in steps:
		var p := from.lerp(to, float(i + 1) / steps)
		var e := InputEventMouseMotion.new()
		e.position = _px(p)
		e.global_position = e.position
		e.relative = _px(p) - _px(prev)
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
		t.get_viewport().push_input(e)
		prev = p
		await t.get_tree().process_frame
	_press(to, false)
	await _frames(20)


func _tap(at: Vector2) -> void:
	_press(at, true)
	await _frames(2)
	_press(at, false)
	await _frames(3)


func test_swipes_from_glyphs_portraits_labels_and_blank_card_areas_never_select() -> void:
	await _begin()
	await _grant_everything()
	await _device("p14_844x390")
	NavShell.open("locker")
	await _frames(6)
	var c := App.screen as CreatorScreen
	# (on a notched phone all ten emotes fit without scrolling; on the SE
	# they scroll, so the glyph case runs there)
	for spec in [["outfit", "picture"], ["outfit", "label"], ["outfit", "corner"], ["face", "picture"], ["move", "glyph"]]:
		var tab := String(spec[0])
		if tab == "move":
			await _device("se_667x375")
			NavShell.open("locker")
			await _frames(6)
			c = App.screen as CreatorScreen
		c._select_tab(tab)
		await _frames(4)
		c.scroll.scroll_vertical = 0
		await _frames(2)
		var room := c.scroll.get_v_scroll_bar().max_value - c.scroll.size.y
		t.check(room > 80.0, "%s: a list long enough to scroll (%d)" % [tab, room])
		var card: Control = null
		for cd in c.cards:
			if String(c.draft[cd.field]) != String(cd.key) and c.scroll.get_global_rect().grow(-4.0).encloses((cd as Control).get_global_rect()):
				card = cd
				break
		t.check(card != null, "%s: an unselected card in view" % tab)
		if card == null:
			continue
		var start := Vector2.ZERO
		match String(spec[1]):
			"picture", "glyph":
				start = (card.holder as Control).get_global_rect().get_center()
			"label":
				start = (card.name_l as Control).get_global_rect().get_center()
			"corner":
				var cr := card.get_global_rect()
				start = cr.position + Vector2(4.0, cr.size.y - 4.0)
		var draft_before: Dictionary = c.draft.duplicate()
		var emoting_before := App.stage != null and App.stage.emoting(Save.player_uid())
		await _swipe(start, start + Vector2(4, -160))
		t.check(c.scroll.scroll_vertical > 40, "%s: a swipe from the card's %s scrolled (%d)" % [tab, spec[1], c.scroll.scroll_vertical])
		t.eq(c.draft, draft_before, "%s: and selected nothing" % tab)
		t.check(not c.apply_btn.visible, "%s: nothing to save after a swipe" % tab)
		if tab == "move" and App.stage:
			t.eq(App.stage.emoting(Save.player_uid()), emoting_before, "a swipe over an emote doesn't play it")
	# a tap still selects, once
	c._select_tab("move")
	await _frames(4)
	c.scroll.scroll_vertical = 0
	await _frames(2)
	var target: Variant = null
	for cd in c.cards:
		if String(cd.key) != String(c.draft["emote"]) and c.scroll.get_global_rect().grow(-4.0).encloses((cd as Control).get_global_rect()):
			target = cd
			break
	t.check(target != null, "an emote card to tap")
	if target != null:
		await _tap((target.glyph as Control).get_global_rect().get_center())
		t.eq(String(c.draft["emote"]), String(target.key), "a tap on the glyph selects that emote")
		t.check(c.apply_btn.visible, "and offers Save look")
		if App.stage:
			t.check(App.stage.emoting(Save.player_uid()), "and plays it on the runner")
	c._on_cancel()
	# Season Pass: a sideways swipe from a cell's art scrolls, never claims
	rig.svc.wallet(Cloud.profile_id())["season"]["s1"]["xp"] = 1450
	await Wallet.refresh()
	App.goto(SeasonScreen)
	await _frames(6)
	var sp := App.screen as SeasonScreen
	sp.track_scroll.scroll_horizontal = 0
	sp.focus(1, "free")
	await _frames(3)
	var cell: Control = sp._cell(3, "free")
	t.eq(sp.cell_state(3, "free"), "claimable", "tier 3 Free is claimable")
	await _swipe(cell.get_global_rect().get_center(), cell.get_global_rect().get_center() + Vector2(-220, 3))
	t.check(sp.track_scroll.scroll_horizontal > 40, "the track scrolled (%d)" % sp.track_scroll.scroll_horizontal)
	t.eq(sp.cell_state(3, "free"), "claimable", "a swipe never claims")
	t.eq([sp.focus_tier, sp.focus_track], [1, "free"], "nor changes the selection")
	# Shop: a swipe from a card's picture scrolls and opens nothing
	App.goto(ShopScreen)
	await _frames(6)
	var shop := App.screen as ShopScreen
	shop.select_section("accessories")
	await _frames(6)
	var sc: Variant = null
	for cd in shop.cards:
		if shop.scroll.get_global_rect().grow(-4.0).encloses((cd as Control).get_global_rect()) and (cd as ShopScreen.ShopCard).art != null:
			sc = cd
			break
	t.check(sc != null, "a Shop card in view")
	if sc != null:
		var p0: Vector2 = ((sc as ShopScreen.ShopCard).art as Control).get_global_rect().get_center()
		await _swipe(p0, p0 + Vector2(3, -170))
		t.check(shop.scroll.scroll_vertical > 40, "the Shop scrolled (%d)" % shop.scroll.scroll_vertical)
		t.check(shop.detail == null, "and opened nothing")
	await _end()


# ------------------------------------------------------------------ art
func test_emote_icons_are_one_centred_set() -> void:
	var shapes := Icons.emote_shapes()
	t.eq(shapes.size(), TC.EMOTES.size(), "every emote has an icon in the set")
	for e in TC.EMOTES:
		var kind := "e_" + String(e)
		t.check(shapes.has(kind), "%s drawn by the set" % kind)
		var b := Icons.shape_bounds(shapes.get(kind, []))
		t.check(b.get_center().length() < 0.01, "%s centred (%s)" % [kind, b.get_center()])
		t.near(maxf(b.size.x, b.size.y) * 0.5, Icons.E_EXTENT, 0.01, "%s reaches the shared extent" % kind)
		t.check(Rect2(-Vector2.ONE, Vector2.ONE * 2.0).encloses(b), "%s stays inside its circle's square" % kind)
		for s in shapes.get(kind, []):
			if String(s[0]) == "poly":
				t.check(not Geometry2D.triangulate_polygon(s[1]).is_empty(), "%s: every filled shape is a valid polygon" % kind)


# ------------------------------------------------------------------ controller
## A controller lands on something useful in every one of these screens,
## with the service on and off (V7: with claiming unavailable there is no
## Claim all to focus, so the selected reward takes focus).
func test_controller_focus_lands_in_each_screen() -> void:
	for with_service in [true, false]:
		await _begin(with_service)
		await _device("p14_844x390")
		Controls.device = "gamepad"
		for cls in [SeasonScreen, ShopScreen, CreatorScreen]:
			if cls == CreatorScreen:
				NavShell.open("locker")
			else:
				App.goto(cls)
			await _frames(20)
			var f: Control = t.get_viewport().gui_get_focus_owner()
			t.check(f != null and App.screen.is_ancestor_of(f) and f.is_visible_in_tree(),
				"%s (service %s) opens with a visible focused control (%s)" % [App.screen.get_script().get_global_name(), with_service, f.name if f else "none"])
		await _end()


## Entry animations fade only: from the first frame every control is hit
## where it is drawn (a scale settle shifted targets for a moment).
func test_entry_never_moves_hit_targets() -> void:
	await _begin()
	for cls in [SeasonScreen, ShopScreen, CreatorScreen]:
		if cls == CreatorScreen:
			NavShell.open("locker")
		else:
			App.goto(cls)
		await _frames(1)
		var scr := App.screen as Screen
		t.eq(scr.margin.scale, Vector2.ONE, "%s: the screen isn't scaled during its entry" % scr.name)
		for p in scr.find_children("*", "PanelContainer", true, false):
			t.eq((p as Control).scale, Vector2.ONE, "%s: %s isn't scaled during its entry" % [scr.name, p.name])
	await _end()
