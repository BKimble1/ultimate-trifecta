extends "res://src/dev/capture_shop_p8.gd"
## FINAL_RELEASE_SWEEP Shop evidence (--capture=shop_final; src/dev is
## excluded from iOS exports): the Pass 8 capture's setup (device point scale
## and safe area, PNG + render report + layout report per shot) with the
## final Shop states.
##
## DEV FIXTURE, labelled on every shot: the test-double service
## (fake_commerce_service.gd: fixed fixture clock, the catalogue's schedule
## and cycle, a wallet with 2,650 Coins, Fluffy Robe and Moonlight Runner
## owned) and the simulated store (test_store_adapter.gd: "(test price)"
## strings, or no products at all for the "price unavailable" shot).  Not a
## deployed service, not a real App Store price or purchase; a desktop render.
##
## Shots: Featured (rotating offers), Always available (both App Store
## outfits, one owned), All skins with owned states, All skins with Hide
## owned, Accessories all owned and hidden (the explained empty state), an
## App Store outfit's detail, the six Coin packs with simulated prices and
## with no App Store products ("Not available"), the Season 1 tab, and
## Featured on a service clock past the written schedule (the rule's cycle).


func _steps() -> Array:
	return [
		["shop", _setup], ["shop", _final_own], ["shop", _featured], ["shop", _featured_always],
		["shop", _all_owned_states], ["shop", _all_hide_owned], ["shop", _acc_all_owned], ["shop", _detail_apple],
		["shop", _coins_sim], ["shop", _coins_unavailable], ["shop", _season_tab], ["shop", _after_schedule],
		["end", _quit],
	]


func _final_own() -> float:
	ShopScreen.hide_owned = false
	_own(["outfit:robe", "outfit:moonlight_runner"])
	return 1.5


func _own(ids: Array) -> void:
	var pid := Cloud.profile_id()
	if pid == "":
		return
	var w: Dictionary = svc.wallet(pid)
	for id in ids:
		w["entitlements"][String(id)] = {"source": "apple" if String(id) == "outfit:moonlight_runner" else "coin_purchase"}
	svc._bump(pid)
	await Wallet.refresh()


func _set_tag(extra: String) -> void:
	if _tag:
		_tag.text = _tag_text() + extra


func _all_owned_states() -> float:
	var s := _shop()
	if s:
		s.scroll.scroll_vertical = 0
		s.select_section("outfits")
	_later(3.0, "shop_all_skins_owned_states")
	return 3.6


func _all_hide_owned() -> float:
	var s := _shop()
	if s:
		var sw := s.body.find_child("HideOwned", true, false) as BaseButton
		if sw:
			sw.button_pressed = true
	_later(2.4, "shop_all_skins_hide_owned")
	return 3.0


func _acc_all_owned() -> float:
	_own(Catalogue.shop_items("accessories").map(func(it: Dictionary) -> String: return String(it["id"])))
	var s := _shop()
	if s:
		s.select_section("accessories")
	_later(2.4, "shop_accessories_all_owned_hidden")
	return 3.0


func _detail_apple() -> float:
	ShopScreen.hide_owned = false
	var s := _shop()
	if s:
		s.select_section("outfits")
		s._open_detail("outfit:starry_sleeper")
	_later(3.0, "shop_detail_app_store_outfit")
	return 3.6


func _coins_sim() -> float:
	var s := _shop()
	if s:
		s._close_detail()
		s.select_section("coins")
	_set_tag(" · Coin prices: simulated store \"(test price)\"")
	_later(2.0, "shop_coins_simulated_prices")
	return 2.6


## The App Store returns none of the products (before App Store Connect
## setup, or a region without them): each pack says "Not available".
func _coins_unavailable() -> float:
	store.catalog.clear()
	Purchases.load_products(true)
	_set_tag(" · simulated store returning NO products: price unavailable")
	_later(2.4, "shop_coins_price_unavailable")
	return 3.0


func _season_tab() -> float:
	var s := _shop()
	if s:
		s.select_section("season")
	_set_tag("")
	_later(2.0, "shop_season_tab")
	return 2.6


## The service's clock past the written schedule (2027-06-01): the rule's
## cycle keeps four offers in the Shop.
func _after_schedule() -> float:
	_set_fixture_time(_ms("2027-06-01T07:00:00Z"))
	Offers.refresh()
	var s := _shop()
	if s:
		s.select_section("featured")
		s.scroll.scroll_vertical = 0
	_set_tag(" · service clock 2027-06-01 (after the written schedule: the rule's cycle)")
	_later(3.5, "shop_featured_after_written_schedule")
	return 4.2
