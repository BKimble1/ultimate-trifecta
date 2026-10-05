extends RefCounted
## Pass 8 Shop rotation and Coin packs, client side, with the test-double
## service (its own clock and schedule; src/dev, never exported) and the
## simulated store: the service's time kept as a monotonic offset (device
## clock rollback/forward, sleep, restart), countdown wording, local
## departure time, Featured cards counting down by label text only and
## swapped in place at expiry, no purchase of an expired offer from a stale
## sheet, a confirmation, All skins, a deep link or the wallet, an offer that
## changed before acceptance, a lost reply replayed after expiry, ownership
## kept in the Locker, honest service-off / stale states, and the six
## compact Coin pack cards (StoreKit price or "Not available", computed
## "Best value" only from same-currency numeric prices).
var t
var rig
var mono := 1000000          # the device's monotonic clock (ms)
var wall := 0.0              # the device's wall clock (unix ms)
var svc_t := 0.0             # the service's clock (unix ms)
var _saved := {}

const T0 := "2026-10-06T21:45:51Z"
const MIN := 60 * 1000
const HOUR := 60 * MIN


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


func _begin(service: bool = true, store: bool = true) -> void:
	rig = preload("res://tests/commerce_rig.gd").new(t)
	await rig.begin(service, store)
	svc_t = float(Catalogue.parse_utc_ms(T0))
	wall = svc_t
	mono = 1000000
	Offers.ticks_override = func() -> int: return mono
	Offers.wall_override = func() -> float: return wall
	if service:
		rig.svc.clock_ms = func() -> float: return svc_t
		await rig.sign_in()
	_saved = {"size": t.get_tree().root.size}
	t.get_tree().root.size = Vector2i(1280, 720)
	for c in t.get_tree().root.get_children():
		if c is BootCurtain:
			c.queue_free()
	await _frames(2)


func _end() -> void:
	t.get_tree().root.size = _saved["size"]
	await rig.end()


## Time passes for everyone (device monotonic + wall, service).
func _advance(sec: float) -> void:
	mono += int(sec * 1000.0)
	wall += sec * 1000.0
	svc_t += sec * 1000.0


func _offer(oid: String, item: String, slot: int, s_ms: float, e_ms: float) -> Dictionary:
	return {"offer_id": oid, "item_id": item, "slot": slot, "price": Catalogue.price(item), "revision": 7, "starts_at": s_ms, "ends_at": e_ms}


## Four offers on the Coin outfits whose art exists in every build.
func _four(first_ends_in_s: float = 5.0) -> void:
	var now := svc_t
	rig.svc.use_schedule([
		_offer("T-lantern", "outfit:lantern_scout", 1, now - HOUR, now + first_ends_in_s * 1000.0),
		_offer("T-courier", "outfit:campus_courier", 2, now - HOUR, now + 2.0 * 86400000.0),
		_offer("T-rain", "outfit:raincoat_explorer", 3, now - HOUR, now + 101040.0 * 1000.0),
		_offer("T-varsity", "outfit:varsity_sprinter", 4, now - HOUR, now + 8049.0 * 1000.0),
		_offer("T-lantern2", "outfit:lantern_scout", 1, now + first_ends_in_s * 1000.0, now + first_ends_in_s * 1000.0 + 2.0 * 86400000.0),
	])


func _shop(sec: String = "featured") -> ShopScreen:
	ShopScreen.focus_section = sec
	App.goto(ShopScreen)
	await _frames(4)
	return App.screen as ShopScreen


func _ids(nodes: Array) -> Array:
	return nodes.map(func(n: Node) -> int: return n.get_instance_id())


# ------------------------------------------------------------------ time
func test_countdown_and_local_departure_wording() -> void:
	t.eq(Offers.countdown(101040), "1d 04h", "a day or more: days and hours")
	t.eq(Offers.countdown(86400), "1d 00h", "exactly a day")
	t.eq(Offers.countdown(86399), "23:59:59", "under a day: hours, minutes, seconds")
	t.eq(Offers.countdown(8049), "02:14:09", "02:14:09")
	t.eq(Offers.countdown(0), "00:00:00", "never negative")
	var leaves := float(Catalogue.parse_utc_ms("2026-10-07T00:00:00Z"))
	t.eq(Offers.local_text(leaves, 0), "Wednesday, Oct 7, 12:00 AM", "UTC device")
	t.eq(Offers.local_text(leaves, -420), "Tuesday, Oct 6, 5:00 PM", "a Pacific (PDT) device sees its own local time")
	t.eq(Offers.local_text(leaves, 60), "Wednesday, Oct 7, 1:00 AM", "a London (BST) device")
	t.eq(Catalogue.parse_utc_ms("2026-10-07T00:00:00.250Z"), Catalogue.parse_utc_ms("2026-10-07T00:00:00Z") + 250, "milliseconds parsed")


func test_service_time_is_a_monotonic_offset_device_clock_never_adds_time() -> void:
	await _begin()
	await Offers.refresh()
	t.check(Offers.trusted(), "synced with the service: trusted")
	t.eq(Offers.shop_status(), "live", "live")
	var act := Offers.active()
	t.eq(act.map(func(o: Dictionary) -> String: return String(o["item_id"])),
		["outfit:pumpkin_pajamas", "outfit:arcade_sprinter", "outfit:cloud_nine", "outfit:bedtime_bandit"],
		"the catalogue's schedule at %s, by slot" % T0)
	t.eq(Offers.seconds_left(act[0]), 8049, "slot 1 leaves at 00:00 UTC: 2h 14m 09s")
	t.eq(Offers.countdown(Offers.seconds_left(act[2])), "1d 02h", "slot 3 leaves a day later")
	t.eq(Offers.refresh_in_s(), 8049, "the Shop next changes at 00:00 UTC")
	# the player rolls the device clock back two days: no extra time
	wall -= 2.0 * 86400000.0
	t.eq(Offers.seconds_left(act[0]), 8049, "a clock rollback changes nothing")
	t.check(Offers.trusted(), "and the monotonic offset stays trusted")
	mono += 1000 * 1000
	t.eq(Offers.seconds_left(act[0]), 7049, "time passes by the monotonic clock")
	# the device clock jumps forward a day: the offer can only end sooner, and
	# the time is no longer trusted until the service answers again
	wall += 3.0 * 86400000.0
	t.eq(Offers.seconds_left(act[0]), 0, "a forward clock change can only shorten an offer")
	t.check(not Offers.trusted(), "and isn't trusted")
	t.eq(Offers.active(), [], "nothing on sale from an untrusted time")
	t.eq(Offers.shop_status(), "stale", "the Shop says: Connect to refresh Shop")
	var refused: Dictionary = await Wallet.spend("outfit:pumpkin_pajamas")
	t.eq(String(refused.get("state", "")), "failed", "and nothing can be bought")
	# the service answers again (its clock moved 1000 s): trusted, right time
	svc_t += 1000.0 * 1000.0
	await Offers.refresh()
	t.check(Offers.trusted(), "re-synced")
	t.eq(Offers.seconds_left(Offers.active()[0]), 7049, "the service's time, whatever the device says")
	# the device sleeps two hours with the app in the background: iOS's
	# monotonic clock pauses, the wall clock doesn't; the later one counts
	wall += 2.0 * HOUR
	svc_t += 2.0 * HOUR
	t.eq(Offers.seconds_left(act[0]), 0, "background across the end: the offer has ended")
	t.check(Offers.skewed(), "the clocks disagree: ask the service again")
	await Offers.refresh()
	t.eq(Offers.active()[0]["item_id"], "outfit:lantern_scout", "after the 00:00 UTC change: the next offer in slot 1")
	# a fresh app run with no network: the cache shows the last offers as
	# previews, never trusted for countdowns or buying
	Offers.reload_as_new_run()
	rig.svc.network_down = true
	t.check(not Offers.trusted(), "no sync in this run: not trusted")
	t.eq(Offers.shop_status(), "stale", "stale")
	t.eq(Offers.last_seen().size(), 4, "the last offers stay previewable offline")
	t.eq(Offers.active(), [], "but none is on sale")
	await _end()


# ------------------------------------------------------------------ Shop
func test_featured_counts_down_by_label_and_swaps_in_place_at_expiry() -> void:
	await _begin()
	_four(5.0)
	await Offers.refresh()
	var shop := await _shop()
	t.check(shop.rot_grid != null, "Featured has the rotating grid")
	var cards: Array = shop.rot_grid.get_children()
	t.eq(cards.map(func(c: Node) -> String: return (c as ShopScreen.ShopCard).id),
		["outfit:lantern_scout", "outfit:campus_courier", "outfit:raincoat_explorer", "outfit:varsity_sprinter"], "four offers, in slot order")
	shop._on_clock()
	t.eq(cards[0].when_l.text, "Leaves in 00:00:05", "list card: under a day")
	t.eq(cards[2].when_l.text, "Leaves in 1d 04h", "list card: a day or more")
	t.eq(cards[3].when_l.text, "Leaves in 02:14:09", "the brief's example")
	t.eq(shop.refresh_l.text, "Shop refreshes in 00:00:05", "the Shop's next change, labelled separately")
	t.check(shop.find_child("ReturnNote", true, false).text == "Owned skins stay in your Locker. Shop skins may return.", "the return note")
	t.check(shop.find_child("AlwaysAvailable", true, false) != null, "the Always available block")
	var grid_id := shop.rot_grid.get_instance_id()
	var before := _ids(cards)
	var nodes := shop.find_children("*", "", true, false).size()
	var v := App.stage.local_character() if App.stage else null
	var vid := v.get_instance_id() if v else 0
	for i in 3:
		_advance(1.0)
		shop._on_clock()
	t.eq(cards[0].when_l.text, "Leaves in 00:00:02", "ticks once a second")
	t.eq(_ids(shop.rot_grid.get_children()), before, "the same cards: only label text changed")
	t.eq(shop.find_children("*", "", true, false).size(), nodes, "no node created or freed by the countdown")
	shop.scroll.scroll_vertical = 30
	await _frames(2)
	var scroll_at := shop.scroll.scroll_vertical
	var old_pos: Vector2 = (cards[0] as Control).get_global_rect().position
	_advance(2.0)
	Offers._tick()
	await _frames(3)
	t.eq(shop.rot_grid.get_instance_id(), grid_id, "the grid wasn't rebuilt")
	var nc := shop.rot_grid.get_child(0) as Control
	t.eq(nc.scale, Vector2.ONE, "the new card's hit region is never scaled (Motion animates its visual)")
	t.eq(nc.get_global_rect().position, old_pos, "and sits exactly where the old card was")
	t.eq(shop.scroll.scroll_vertical, scroll_at, "the list kept its scroll position through the refresh (%d)" % scroll_at)
	var after: Array = shop.rot_grid.get_children()
	t.eq(after.size(), 4, "still four offers")
	t.check(after[0].get_instance_id() != before[0], "the ended offer's card was replaced in place")
	t.eq(String((after[0] as ShopScreen.ShopCard).offer["offer_id"]), "T-lantern2", "by the slot's next offer")
	t.eq(_ids(after.slice(1)), before.slice(1), "the other three cards untouched")
	shop._on_clock()
	t.eq((after[0] as ShopScreen.ShopCard).when_l.text, "Leaves in 2d 00h", "the new offer's own departure, not a restarted timer")
	if v:
		t.eq((App.stage.local_character() as Node).get_instance_id(), vid, "the one live preview kept running")
	await _end()


func test_refresh_feedback_respects_reduced_motion_and_focus() -> void:
	await _begin()
	var prev: Variant = Save.get_setting("reduced_motion", false)
	Save.set_setting("reduced_motion", true)
	_four(5.0)
	await Offers.refresh()
	var shop := await _shop()
	var first := shop.rot_grid.get_child(0) as Control
	first.grab_focus()
	_advance(6.0)
	Offers._tick()
	await _frames(3)
	var nc := shop.rot_grid.get_child(0) as Control
	t.check(nc != first, "swapped")
	t.eq(UIKit.face_of(nc).scale, Vector2.ONE, "Reduced Motion: no scale settle on the new card")
	t.check(not Motion.running(UIKit.face_of(nc)).has("scale"), "and no scale animation running")
	t.check(nc.has_focus(), "controller focus moved to the card that replaced the focused one")
	Save.set_setting("reduced_motion", prev)
	await _end()


func test_an_expired_offer_cannot_be_bought_anywhere() -> void:
	await _begin()
	_four(30.0)
	rig.svc.grant(Cloud.profile_id(), 2000)
	await Wallet.refresh()
	await Offers.refresh()
	var shop := await _shop()
	shop._open_detail("outfit:lantern_scout")
	await _frames(2)
	t.eq((shop._d["action"] as Button).text, "Buy for 1,200 Coins", "on sale: the offer's price")
	t.eq((shop._d["when"] as Label).text, "Leaves in 00:00:30", "the sheet's countdown")
	t.check((shop._d["leave"] as Label).text.begins_with("Leaves the Shop ") and (shop._d["leave"] as Label).text.ends_with("(your time)"),
		"and the local departure date and time: %s" % (shop._d["leave"] as Label).text)
	shop._on_action()
	await _frames(2)
	t.check(shop.find_child("ConfirmSpend", true, false) != null, "the confirmation is open")
	# the offer ends while the sheet and the confirmation are open
	_advance(31.0)
	rig.svc.use_schedule([_offer("T-courier", "outfit:campus_courier", 2, svc_t - HOUR, svc_t + HOUR)])
	Offers._tick()
	await _frames(3)
	await rig.until(func() -> bool: return shop.find_child("ConfirmSpend", true, false) == null)
	t.check(shop.find_child("ConfirmSpend", true, false) == null, "the confirmation closed itself")
	t.check((shop._d["action"] as Button).disabled, "the stale sheet can't buy")
	t.eq((shop._d["action"] as Button).text, "Not in current rotation", "and says why")
	t.check((shop._d["status"] as Label).text.contains("Shop skins may return"), "with the return note")
	# the wallet path refuses too (no request is even sent)
	var calls: int = rig.svc.calls.size()
	var r: Dictionary = await Wallet.spend("outfit:lantern_scout")
	t.eq(String(r["state"]), "offer_changed", "a plain item spend outside an offer: refused")
	t.eq(rig.svc.calls.size(), calls, "refused before reaching the service")
	# and the service refuses a direct request with the old offer
	var direct: Dictionary = await Cloud.api(HTTPClient.METHOD_POST, "/v1/wallet/spend",
		{"item_id": "outfit:lantern_scout", "price": 1200, "offer_id": "T-lantern", "idempotency_key": "direct-0001"})
	t.eq(String(direct.get("error", "")), "offer_changed", "the endpoint itself refuses the expired offer")
	var plain: Dictionary = await Cloud.api(HTTPClient.METHOD_POST, "/v1/wallet/spend",
		{"item_id": "outfit:lantern_scout", "price": 1200, "idempotency_key": "direct-0002"})
	t.eq(String(plain.get("reason", "")), "not_in_rotation", "no bypass with a plain item id")
	await Wallet.refresh()
	t.eq(Wallet.balance(), 2000, "nothing was charged")
	shop._close_detail()
	# All skins: previewable, labelled, not buyable
	shop.select_section("outfits")
	await _frames(3)
	var card: ShopScreen.ShopCard = null
	for c in shop.cards:
		if (c as ShopScreen.ShopCard).id == "outfit:lantern_scout":
			card = c
	t.check(card != null, "All skins lists it")
	t.check(card.when_l.text in ["Not in current rotation", "Not in rotation"], "labelled out of rotation (%s)" % card.when_l.text)
	shop._open_detail("outfit:lantern_scout")
	await _frames(2)
	t.check((shop._d["action"] as Button).disabled, "its sheet can't buy")
	t.eq(shop.preview_id, "outfit:lantern_scout", "but it can be previewed on the runner")
	# a deep link straight to the item
	ShopScreen.focus_item = "outfit:lantern_scout"
	shop = await _shop("outfits")
	await _frames(2)
	t.check((shop._d["action"] as Button).disabled, "a deep link can't buy it either")
	await _end()


func test_offer_changed_before_acceptance_charges_nothing() -> void:
	await _begin()
	_four(30.0)
	rig.svc.grant(Cloud.profile_id(), 2000)
	await Wallet.refresh()
	await Offers.refresh()
	# the device still counts 1 s left; the service's clock already passed
	# the end when it receives the purchase
	_advance(29.0)
	svc_t += 5000.0
	var r: Dictionary = await Wallet.spend("outfit:lantern_scout")
	t.eq(String(r["state"]), "offer_changed", "the service decided at acceptance")
	t.check(String(r["message"]).contains("Nothing was charged"), "a short offer-changed message: %s" % r["message"])
	t.eq(Wallet.balance(), 2000, "nothing charged")
	t.eq(Wallet.pending_ops(), 0, "nothing left to retry")
	t.check(not Wallet.owns("outfit", "lantern_scout"), "not granted")
	await _end()


func test_accepted_before_expiry_is_delivered_after_a_lost_reply() -> void:
	await _begin()
	_four(30.0)
	rig.svc.grant(Cloud.profile_id(), 2000)
	await Wallet.refresh()
	await Offers.refresh()
	rig.svc.drop_reply = true   # the service accepts it, the reply is lost
	var r: Dictionary = await Wallet.spend("outfit:lantern_scout")
	t.eq(String(r["state"]), "pending", "no answer: pending (a timeout isn't a no)")
	t.eq(int(rig.svc.wallet(Cloud.profile_id())["balance"]), 800, "the service charged it once")
	# the offer leaves; the app comes back later and retries with the same key
	_advance(120.0)
	rig.svc.drop_reply = false
	Wallet.reload()
	await Wallet.refresh()
	await rig.until(func() -> bool: return Wallet.pending_ops() == 0)
	t.eq(Wallet.pending_ops(), 0, "the retry was answered")
	t.check(Wallet.owns("outfit", "lantern_scout"), "delivered after the offer ended")
	t.eq(Wallet.balance(), 800, "charged exactly once")
	await _end()


func test_owned_skin_stays_in_the_locker_and_returns_owned() -> void:
	await _begin()
	_four(30.0)
	rig.svc.grant(Cloud.profile_id(), 2000)
	await Wallet.refresh()
	await Offers.refresh()
	var r: Dictionary = await Wallet.spend("outfit:lantern_scout")
	t.check(bool(r["ok"]), "bought through its offer")
	t.eq(String(r.get("offer", {}).get("offer_id", "")), "T-lantern", "that offer")
	_advance(31.0)
	rig.svc.use_schedule([_offer("T-courier", "outfit:campus_courier", 2, svc_t - HOUR, svc_t + HOUR)])
	await Offers.refresh()
	t.check(Offers.offer_for("outfit:lantern_scout").is_empty(), "out of rotation")
	t.check(Wallet.owns("outfit", "lantern_scout"), "still owned")
	NavShell.open("locker")
	await _frames(4)
	var loc := App.screen as CreatorScreen
	t.check(loc.shown_keys("outfit").has("lantern_scout"), "selectable in the Locker after its offer left")
	var always := 0
	for k in Cosmetics.keys_of("outfit"):
		var oid := Catalogue.id_for("outfit", String(k))
		if not Wallet.owns_id(oid) and Catalogue.source_of(oid) in ["shop", "apple"] and Catalogue.has_art(oid) and not Catalogue.is_rotation(oid):
			always += 1
	t.eq(int(loc.not_owned("outfit")["shop"]), always + 1, "the Locker's Shop link counts what's always sold plus the one rotating skin on sale now")
	# it returns under a new offer: owned, never offered again
	rig.svc.use_schedule([_offer("T-lantern9", "outfit:lantern_scout", 1, svc_t - MIN, svc_t + HOUR)])
	await Offers.refresh()
	var shop := await _shop()
	var card: ShopScreen.ShopCard = shop.rot_grid.get_child(0)
	t.eq(card.price_l.text, "Owned", "Owned, not a price")
	t.eq(card.when_l.text, "In your Locker", "and in the Locker")
	shop._open_detail("outfit:lantern_scout")
	await _frames(2)
	t.eq((shop._d["action"] as Button).text, "Wear it in the Locker", "never offered again")
	await _end()


func test_service_off_and_stale_states_are_honest() -> void:
	await _begin(false, false)
	t.eq(Offers.shop_status(), "off", "no service in the build: no rotation")
	var shop := await _shop()
	t.check(shop.rot_status.visible and shop.rot_status.text.contains("isn't set up in this build"), "Featured says why: %s" % shop.rot_status.text)
	t.eq(shop.rot_grid.get_child_count(), 0, "no made-up offers")
	t.check(shop.banner.visible, "the existing unavailable banner")
	t.eq(shop.refresh_l.text, "", "no countdown")
	shop.select_section("outfits")
	await _frames(2)
	shop._open_detail("outfit:varsity_sprinter")
	await _frames(2)
	t.check((shop._d["action"] as Button).disabled, "no purchase")
	t.eq(shop.preview_id, "outfit:varsity_sprinter", "browsing and preview still work")
	await rig.end()
	# configured but unreachable, after an earlier sync: Connect to refresh Shop
	await _begin()
	_four(3600.0)
	await Offers.refresh()
	Offers.reload_as_new_run()
	rig.svc.network_down = true
	shop = await _shop()
	await _frames(2)
	t.eq(Offers.shop_status(), "stale", "stale")
	t.check(shop.rot_status.text.begins_with("Connect to refresh Shop"), "the status says so: %s" % shop.rot_status.text)
	t.eq(shop.rot_grid.get_child_count(), 4, "the last offers stay previewable")
	t.check((shop.rot_grid.get_child(0) as ShopScreen.ShopCard).when_l.text in ["Connect to refresh Shop", "Refresh needed"], "no deceptive countdown on the card")
	t.eq(shop.refresh_l.text, "", "no refresh countdown")
	shop._open_detail("outfit:lantern_scout")
	await _frames(2)
	t.eq((shop._d["action"] as Button).text, "Connect to refresh Shop", "the sheet can't buy from a stale offer")
	t.check((shop._d["action"] as Button).disabled, "disabled")
	await _end()


# ------------------------------------------------------------------ Coin packs
const PRICES := {"250": ["$2.99", 2.99], "500": ["$4.99", 4.99], "1000": ["$9.99", 9.99], "1500": ["$13.99", 13.99],
	"3500": ["$29.99", 29.99], "7500": ["$59.99", 59.99]}


func _price_store(prices: Dictionary) -> void:
	for n in prices:
		var pid := "com.idlery.ultimatetrifecta.coins.%s" % n
		rig.store.catalog[pid]["display_price"] = String(prices[n][0])
		rig.store.catalog[pid]["price"] = float(prices[n][1])
	Purchases.load_products(true)
	await rig.until(func() -> bool: return Purchases.products_state == "loaded")


func test_coin_pack_cards_are_compact_priced_by_storekit_and_honest() -> void:
	await _begin()
	await _price_store(PRICES)
	var shop := await _shop("coins")
	await _frames(2)
	var packs: Array = shop.cards.filter(func(c: Node) -> bool: return (c as ShopScreen.ShopCard).pack)
	t.eq(packs.map(func(c: Node) -> String: return (c as ShopScreen.ShopCard).name_l.text),
		["250 Coins", "500 Coins", "1,000 Coins", "1,500 Coins", "3,500 Coins", "7,500 Coins"], "six packs, full quantities, in order")
	t.eq(packs.map(func(c: Node) -> String: return (c as ShopScreen.ShopCard).price_l.text),
		["$2.99", "$4.99", "$9.99", "$13.99", "$29.99", "$59.99"], "StoreKit's own localized prices")
	var grid := (packs[0] as Control).get_parent() as GridContainer
	t.check(grid.columns >= 2, "two or more per row on a landscape phone (%d)" % grid.columns)
	for c in packs:
		t.check((c as Control).size.y <= ShopScreen.ShopCard.pack_h() + 0.5, "compact: %s is %.0f tall" % [c.name, (c as Control).size.y])
		t.check((c as Control).size.y >= UIKit.touch_min() - 0.5, "still a full touch target")
	t.eq(Purchases.best_value_pack(), "com.idlery.ultimatetrifecta.coins.7500", "lowest price per Coin, from the numbers")
	var notes: Array = packs.map(func(c: Node) -> String: return (c as ShopScreen.ShopCard)._note.text if (c as ShopScreen.ShopCard)._note.visible else "")
	t.eq(notes, ["", "", "", "", "", "Best value"], "one Best value, on that pack")
	# mixed currencies: no claim
	var mixed := PRICES.duplicate(true)
	mixed["500"] = ["4,99 €", 4.99]
	await _price_store(mixed)
	t.eq(Purchases.best_value_pack(), "", "different currencies: no Best value")
	# equal value per Coin: no claim
	var flat := {}
	for n in PRICES:
		flat[n] = ["$%.2f" % (int(n) * 0.01), int(n) * 0.01]
	await _price_store(flat)
	t.eq(Purchases.best_value_pack(), "", "no pack is cheaper per Coin: no Best value")
	# a product the App Store doesn't return: honestly unavailable
	rig.store.catalog.erase("com.idlery.ultimatetrifecta.coins.250")
	Purchases.load_products(true)
	await rig.until(func() -> bool: return Purchases.products_state == "loaded")
	await _frames(2)
	t.eq((packs[0] as ShopScreen.ShopCard).price_l.text, "Not available", "a missing product: Not available")
	t.check(not (packs[0] as ShopScreen.ShopCard).price_l.text.contains("$"), "never a made-up price")
	t.eq(Purchases.best_value_pack(), "", "and no claim from a partial flat list")
	# a tap is the purchase: Apple's sheet, once
	t.eq(rig.store.purchases_started, 0, "showing the cards bought nothing")
	(packs[1] as Button).pressed.emit()
	await rig.until(func() -> bool: return Wallet.balance() == 500)
	t.eq(rig.store.purchases_started, 1, "one tap, one Apple sheet")
	t.eq(Wallet.balance(), 500, "+500 Coins")
	await _end()


func test_currency_marks_for_best_value() -> void:
	t.eq(Purchases.currency_mark("$0.99"), "$", "dollars")
	t.eq(Purchases.currency_mark("0,99\u00a0€"), "€", "euros with a no-break space")
	t.eq(Purchases.currency_mark("US$1.99"), "US$", "a prefixed code")
	t.eq(Purchases.currency_mark("¥160"), "¥", "yen")
	t.eq(Purchases.currency_mark("1'000.00 CHF"), "CHF", "Swiss grouping")
	t.check(Purchases.currency_mark("£4.99") != Purchases.currency_mark("$4.99"), "different currencies differ")


func test_all_six_packs_deliver_their_quantity_once() -> void:
	await _begin()
	await rig.until(func() -> bool: return Purchases.products_state == "loaded")
	var total := 0
	for n in [250, 500, 1000, 1500, 3500, 7500]:
		var pid := "com.idlery.ultimatetrifecta.coins.%d" % n
		t.eq(Catalogue.item_for_product(pid), "coins:%d" % n, "%s -> coins:%d" % [pid, n])
		t.eq(int(Catalogue.item("coins:%d" % n).get("coins", 0)), n, "coins:%d holds %d" % [n, n])
		t.check(Purchases.products.has(pid), "%s loaded from the store" % pid)
		var r := Purchases.buy(pid)
		t.check(bool(r["ok"]), "%s: Apple's sheet" % pid)
		total += n
		await rig.until(func() -> bool: return String(Purchases.states.get(pid, {}).get("state", "")) == "delivered")
		t.eq(Wallet.balance(), total, "%s adds %d Coins" % [pid, n])
	t.eq(rig.store.unfinished.size(), 0, "every transaction finished after delivery")
	t.eq(rig.store.finish_calls, 6, "once each")
	await _end()
