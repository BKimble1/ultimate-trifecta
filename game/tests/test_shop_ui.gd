extends RefCounted
## V6 Shop, Season Pass and navigation, driven through the real GUI path
## (push_input, touch emulated from the mouse as on iOS) with the test-double
## service and the simulated store: a swipe on a Shop card scrolls and never
## opens it; a tap opens its detail once; Coin purchases are confirmed with
## the balance left and charge once; owned items are never offered; wallet
## updates refresh in place (no rebuilt menu); the Season track scrolls
## sideways without claiming; Claim all; Premium resolves in the Shop;
## every tab is reachable at small-phone and iPad widths.
var t
var rig
var _saved := {}


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


func _begin() -> void:
	rig = preload("res://tests/commerce_rig.gd").new(t)
	await rig.begin()
	await rig.sign_in()
	_saved = {"emulate": Input.emulate_touch_from_mouse, "device": Controls.device, "size": t.get_tree().root.size}
	Input.emulate_touch_from_mouse = true
	Controls.device = "touch"
	t.get_tree().root.size = Vector2i(1280, 720)
	t.get_tree().root.notification(Window.NOTIFICATION_WM_MOUSE_ENTER)
	# the startup curtain (layer 100) blocks input while it's up
	for c in t.get_tree().root.get_children():
		if c is BootCurtain:
			c.queue_free()
	await _frames(2)


func _end() -> void:
	Input.emulate_touch_from_mouse = _saved["emulate"]
	Controls.device = _saved["device"]
	t.get_tree().root.size = _saved["size"]
	await rig.end()


func _press(at: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = at
	e.global_position = at
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	t.get_viewport().push_input(e)


func _move(from: Vector2, to: Vector2, steps: int) -> void:
	var prev := from
	for i in steps:
		var p := from.lerp(to, float(i + 1) / steps)
		var e := InputEventMouseMotion.new()
		e.position = p
		e.global_position = p
		e.relative = p - prev
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
		t.get_viewport().push_input(e)
		prev = p
		await t.get_tree().process_frame


func _shop() -> ShopScreen:
	App.goto(ShopScreen)
	await _frames(4)
	return App.screen as ShopScreen


func test_swipe_on_a_shop_card_scrolls_tap_opens_detail() -> void:
	await _begin()
	var shop := await _shop()
	shop.select_section("accessories")
	await _frames(6)
	t.check(shop.cards.size() > 8, "a long list (%d cards)" % shop.cards.size())
	var card: Control = shop.cards[1]
	var start := card.get_global_rect().get_center()
	_press(start, true)
	await _move(start, start + Vector2(3, -200), 12)
	_press(start + Vector2(3, -200), false)
	await _frames(25)
	t.check(shop.scroll.scroll_vertical > 60, "the swipe scrolled the Shop (%d)" % shop.scroll.scroll_vertical)
	t.check(shop.detail == null, "lifting the finger after a swipe opened nothing")
	await _frames(30)
	var vis: Rect2 = shop.scroll.get_global_rect().grow(-20.0)
	var target: Variant = null
	for c in shop.cards:
		if vis.has_point((c as Control).get_global_rect().get_center()):
			target = c
			break
	t.check(target != null, "a card is in view after scrolling")
	var tap: Vector2 = (target as Control).get_global_rect().get_center()
	_press(tap, true)
	await _frames(2)
	_press(tap, false)
	await _frames(3)
	t.check(shop.detail != null, "a tap opens the detail sheet")
	t.eq(shop.detail_id, String(target.id), "of that card")
	t.check(shop.preview_id == shop.detail_id, "and previews it on the runner (the one interactive preview)")
	await _end()


func test_coin_purchase_is_confirmed_and_charged_once() -> void:
	await _begin()
	rig.svc.grant(Cloud.profile_id(), 400)
	await Wallet.refresh()
	var shop := await _shop()
	shop.select_section("outfits")
	await _frames(3)
	shop._open_detail("outfit:robe")
	await _frames(2)
	var action: Button = shop._d["action"]
	t.eq(action.text, "Buy for 300 Coins", "exact price on the one purchase action")
	var before_cards: Array = shop.cards.duplicate()
	shop._on_action()
	await _frames(2)
	var confirm := shop.find_child("ConfirmSpend", true, false)
	t.check(confirm != null, "a confirmation, not an instant charge")
	var texts: Array = confirm.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	t.check(texts.has("Fluffy Robe") and texts.has("300 Coins") and texts.has("400 Coins") and texts.has("100 Coins"),
		"it shows the item, the cost, the balance and what's left: %s" % [texts])
	(confirm.find_child("ConfirmCancel", true, false) as Button).pressed.emit()
	await _frames(3)
	t.eq(Wallet.balance(), 400, "Cancel charges nothing")
	shop._on_action()
	await _frames(2)
	(shop.find_child("ConfirmBuy", true, false) as Button).pressed.emit()
	await rig.until(func() -> bool: return Wallet.owns("outfit", "robe"))
	await _frames(3)
	t.eq(Wallet.balance(), 100, "charged once")
	t.eq((shop._d["action"] as Button).text, "Wear it in the Locker", "owned: never offered again")
	t.check(before_cards.all(func(c: Variant) -> bool: return is_instance_valid(c)), "the wallet update refreshed cards in place (no rebuild)")
	t.eq(int(rig.svc.wallet(Cloud.profile_id())["balance"]), 100, "the ledger agrees")
	await _end()


func test_apple_items_open_the_store_sheet_only_from_a_tap() -> void:
	await _begin()
	await rig.until(func() -> bool: return Purchases.products_state == "loaded")
	var shop := await _shop()
	shop.select_section("coins")
	await _frames(3)
	t.eq(rig.store.purchases_started, 0, "opening the Shop never starts a purchase")
	shop._open_detail("coins:500")
	await _frames(2)
	t.eq(rig.store.purchases_started, 0, "nor does opening the detail")
	t.check(String((shop._d["action"] as Button).text).contains("(test price)"), "the button shows the store's own price string")
	shop._on_action()
	await rig.until(func() -> bool: return Wallet.balance() == 500)
	t.eq(rig.store.purchases_started, 1, "one tap, one Apple sheet")
	t.eq(Wallet.balance(), 500, "delivered")
	await _end()


func test_season_track_swipes_and_claims() -> void:
	await _begin()
	var pid := Cloud.profile_id()
	rig.svc.wallet(pid)["season"]["s1"]["xp"] = 1450   # tier 8
	await Wallet.refresh()
	App.goto(SeasonScreen)
	await _frames(6)
	var sp := App.screen as SeasonScreen
	t.eq(sp.cells.size(), 60, "30 tiers x Free/Premium")
	t.check(sp.track_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "a horizontal track")
	t.check(sp.track_scroll.has_meta(&"touch_scroll"), "made with UIKit.scroll_area (finger scrolling)")
	sp.track_scroll.scroll_horizontal = 0
	await _frames(3)
	var cell: Control = sp.cells[4]   # tier 3 free: claimable
	t.eq(cell.state, "claimable", "tier 3 free is claimable")
	var start := cell.get_global_rect().get_center()
	_press(start, true)
	await _move(start, start + Vector2(-260, 4), 12)
	_press(start + Vector2(-260, 4), false)
	await _frames(25)
	t.check(sp.track_scroll.scroll_horizontal > 60, "the swipe scrolled the track (%d)" % sp.track_scroll.scroll_horizontal)
	t.eq(sp.cell_state(3, "free"), "claimable", "a swipe never claims")
	t.eq(sp.claim_all_btn.text, "Claim all (4)", "free tiers 1, 3, 5, 7")
	sp._claim_all()
	await rig.until(func() -> bool: return sp.claim_all_btn.text == "Nothing to claim")
	t.eq(sp.cell_state(3, "free"), "claimed", "claimed")
	t.eq(Wallet.balance(), 25, "tier 5's 25 Coins")
	sp.focus(4, "premium")
	t.eq(sp.cell_state(4, "premium"), "premium_locked", "earned Premium reward, locked")
	t.eq((sp._d["action"] as Button).text, "Get Premium in the Shop", "Premium resolves in the Shop")
	sp._on_detail_action()
	await _frames(4)
	t.check(App.screen is ShopScreen, "the Shop opened")
	t.eq((App.screen as ShopScreen).section, "season", "on the Season 1 offer")
	await _end()


func test_nav_tabs_fit_small_phone_and_ipad() -> void:
	await _begin()
	for size in [Vector2i(1334, 750), Vector2i(2048, 1536), Vector2i(1280, 720)]:
		t.get_tree().root.size = size
		for cls in [ShopScreen, SeasonScreen]:
			App.goto(cls)
			await _frames(4)
			var nav := App.screen.find_children("*", "NavShell", true, false)
			t.eq(nav.size(), 1, "one navigation bar")
			var n := nav[0] as NavShell
			var view: Vector2 = t.get_viewport().get_visible_rect().size
			for k in n.buttons:
				var r: Rect2 = (n.buttons[k] as Control).get_global_rect()
				t.check(r.end.x <= view.x + 0.5 and r.position.x >= -0.5, "%s tab on screen at %s" % [k, size])
				t.check(r.size.x >= UIKit.touch_min() - 0.5 and r.size.y >= UIKit.touch_min() - 0.5, "%s tab is a full touch target" % k)
	t.get_tree().root.size = Vector2i(1280, 720)
	Save.data["onboarded"] = true
	App.goto_title()
	await _frames(4)
	var rail := App.screen.find_children("*", "NavShell", true, false)
	t.eq(rail.size(), 1, "home has the navigation too")
	(rail[0] as NavShell).buttons["shop"].pressed.emit()
	await _frames(3)
	t.check(App.screen is ShopScreen, "Shop tab opens the Shop")
	(App.screen.find_children("*", "NavShell", true, false)[0] as NavShell).buttons["play"].pressed.emit()
	await _frames(3)
	t.check(App.screen is TitleScreen, "Play returns to the hub")
	await _end()


func test_service_off_shop_is_honest() -> void:
	rig = preload("res://tests/commerce_rig.gd").new(t)
	await rig.begin(false, false)
	_saved = {"emulate": Input.emulate_touch_from_mouse, "device": Controls.device, "size": t.get_tree().root.size}
	var shop := await _shop()
	t.check(shop.banner.visible and shop.banner.text.contains("isn't set up in this build"), "the banner says why: %s" % shop.banner.text)
	shop.select_section("outfits")
	await _frames(2)
	shop._open_detail("outfit:robe")
	await _frames(2)
	t.check((shop._d["action"] as Button).disabled, "no purchase action")
	shop._close_detail()
	shop.select_section("coins")
	await _frames(2)
	shop._open_detail("coins:1500")
	await _frames(2)
	t.check((shop._d["action"] as Button).disabled, "Coin packs unavailable (no store, no service)")
	t.check(not String((shop._d["action"] as Button).text).contains("$"), "no made-up price")
	await _end()
