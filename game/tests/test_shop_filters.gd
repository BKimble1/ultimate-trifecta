extends RefCounted
## FINAL_RELEASE_SWEEP Shop (brief section 5), with the test-double service
## and the simulated store: the Hide owned switch hides only owned items in
## All skins / Accessories and explains an all-owned grid; it never hides
## Featured, the Coin packs or Season Premium; every listed card opens that
## same item with its own art, name, source and price; both direct App Store
## outfits and all six Coin packs are always reachable (live, stale, service
## off); previewing changes presentation only (Back, filtering, a cancelled
## purchase, a section change or the Shop closing restore the real look and
## the save never changes); and past the written offer schedule the Shop
## still shows four rotating offers.
var t
var rig
var svc_t := 0.0
var _saved := {}

const APPLE := ["outfit:moonlight_runner", "outfit:starry_sleeper"]


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


func _begin(service: bool = true, at: String = "2026-10-06T21:45:51Z") -> void:
	rig = preload("res://tests/commerce_rig.gd").new(t)
	await rig.begin(service, true)
	svc_t = float(Catalogue.parse_utc_ms(at))
	ShopScreen.hide_owned = false
	if service:
		rig.svc.clock_ms = func() -> float: return svc_t
		await rig.sign_in()
		await Offers.refresh()
	await rig.until(func() -> bool: return Purchases.products_state == "loaded")
	if _saved.is_empty():
		_saved = {"size": t.get_tree().root.size}
	t.get_tree().root.size = Vector2i(1280, 720)
	for c in t.get_tree().root.get_children():
		if c is BootCurtain:
			c.queue_free()
	await _frames(2)


func _end() -> void:
	ShopScreen.hide_owned = false
	t.get_tree().root.size = _saved["size"]
	_saved = {}
	await rig.end()


func _shop(sec: String = "featured") -> ShopScreen:
	ShopScreen.focus_section = sec
	App.goto(ShopScreen)
	await _frames(4)
	return App.screen as ShopScreen


func _own(ids: Array) -> void:
	var w: Dictionary = rig.svc.wallet(Cloud.profile_id())
	for id in ids:
		w["entitlements"][String(id)] = {"source": "apple" if APPLE.has(id) else "coin_purchase"}
	rig.svc._bump(Cloud.profile_id())
	await Wallet.refresh()


func _card_ids(shop: ShopScreen, grid_name: String) -> Array:
	var g := shop.body.find_child(grid_name, true, false)
	if g == null:
		return []
	return g.get_children().filter(func(c: Node) -> bool: return c is ShopScreen.ShopCard and not c.is_queued_for_deletion()) \
		.map(func(c: ShopScreen.ShopCard) -> String: return c.id)


func test_hide_owned_hides_only_owned_and_explains_an_all_owned_grid() -> void:
	await _begin()
	await _own(["outfit:robe", "outfit:moonlight_runner"])
	var shop := await _shop("outfits")
	var row := shop.body.find_child("FilterRow", true, false) as Control
	t.check(row != null, "All skins has the filter row")
	var sw := shop.body.find_child("HideOwned", true, false) as BaseButton
	t.check(sw != null and sw.toggle_mode, "one switch, not a dropdown")
	t.check(sw.size.y >= 44.0 and sw.focus_mode != Control.FOCUS_NONE, "a 44 pt, controller-focusable control")
	var all: Array = Catalogue.shop_items("outfits").map(func(it: Dictionary) -> String: return String(it["id"]))
	t.eq((shop.body.find_child("FilterCount", true, false) as Label).text, "%d skins · 2 owned" % all.size(), "how many, and how many owned")
	var before := _card_ids(shop, "Grid_outfits")
	t.eq(before.size(), all.size(), "every Shop skin is listed")
	t.check(before.has("outfit:robe") and before.has("outfit:moonlight_runner"), "owned ones too (shown Owned)")
	sw.button_pressed = true
	await _frames(3)
	var after := _card_ids(shop, "Grid_outfits")
	t.eq(after.size(), all.size() - 2, "Hide owned: exactly the owned ones are gone")
	t.check(not after.has("outfit:robe") and not after.has("outfit:moonlight_runner"), "owned hidden")
	t.check(after.has("outfit:frog") and after.has("outfit:starry_sleeper"), "everything else stays")
	t.check(after.all(func(id: String) -> bool: return not Wallet.owns_id(id)), "no owned card left")
	# something becomes owned while the grid is on show (a purchase on
	# another device, a wallet sync arriving late): the filter follows
	await _own(["outfit:frog"])
	await _frames(3)
	t.check(not _card_ids(shop, "Grid_outfits").has("outfit:frog"), "a newly owned skin leaves the filtered grid")
	t.eq(_card_ids(shop, "Grid_outfits").size(), all.size() - 3, "and only it")
	t.eq((shop.body.find_child("FilterCount", true, false) as Label).text, "%d skins · 3 owned" % all.size(), "the count follows")
	# the filter never touches Featured, the Coin packs or Season Premium
	shop.select_section("featured")
	await _frames(3)
	t.check(shop.body.find_child("FilterRow", true, false) == null, "no filter on Featured")
	t.eq(_card_ids(shop, "Grid_always"), APPLE, "both App Store outfits stay in Always available, owned or not")
	shop.select_section("coins")
	await _frames(3)
	t.eq(_card_ids(shop, "Grid_coins").size(), 6, "six Coin packs, filter or not")
	t.check(shop.body.find_child("FilterRow", true, false) == null, "no filter on Coins")
	shop.select_section("season")
	await _frames(3)
	t.check(shop.cards.any(func(c: Variant) -> bool: return (c as ShopScreen.ShopCard).id == "season:s1:premium"), "Season Premium stays")
	t.check(shop.body.find_child("Link_pass", true, false) != null, "and the Season Pass is one tap away (rewards are earned there, never sold)")
	# the choice is kept while the game runs
	shop.select_section("outfits")
	await _frames(3)
	t.check((shop.body.find_child("HideOwned", true, false) as BaseButton).button_pressed, "still on when coming back")
	t.check(not _card_ids(shop, "Grid_outfits").has("outfit:robe"), "and still hiding")
	# everything in Accessories owned: a sentence, never an empty grid
	await _own(Catalogue.shop_items("accessories").map(func(it: Dictionary) -> String: return String(it["id"])))
	shop.select_section("accessories")
	await _frames(3)
	t.check(shop.body.find_child("Grid_accessories", true, false) == null, "no empty grid")
	var note := shop.body.find_child("AllOwned", true, false) as Label
	t.check(note != null and note.visible and note.text.contains("Turn off Hide owned"), "it says why and how: %s" % (note.text if note else ""))
	(shop.body.find_child("HideOwned", true, false) as BaseButton).button_pressed = false
	await _frames(3)
	t.eq(_card_ids(shop, "Grid_accessories").size(), Catalogue.shop_items("accessories").size(), "off again: all of them, shown Owned")
	t.check(shop.cards.all(func(c: Variant) -> bool: return String(shop.state_of((c as ShopScreen.ShopCard).id)["kind"]) == "owned"), "each one Owned")
	await _end()


func test_every_listed_card_opens_that_item_with_its_own_art_name_source_and_price() -> void:
	await _begin()
	await _own(["outfit:duck"])
	var shop := await _shop("outfits")
	var saved: Dictionary = Cosmetics.sanitize(Save.data["cosmetic"])
	for sec in ["outfits", "accessories", "featured"]:
		shop.select_section(sec)
		await _frames(3)
		var list: Array = shop.cards.duplicate()
		t.check(list.size() > 0, "%s lists cards" % sec)
		for c in list:
			var card := c as ShopScreen.ShopCard
			if not is_instance_valid(card) or card.pack:
				continue
			var id := card.id
			t.eq(card.name_l.text, Catalogue.display_name(id), "%s: the card's name" % id)
			var st := shop.state_of(id, card.offer)
			t.eq(card.price_l.text, String(st["text"]), "%s: the card's price or state" % id)
			if Catalogue.is_runner_item(id) and ShopScreen.THUMB_FRAMING.has(String(Catalogue.split(id)[0])):
				var parts := Catalogue.split(id)
				var want := Portraits.key_for(CommerceArt.preview_look(shop.saved, String(parts[0]), String(parts[1])), TC.Role.RUNNER,
					String(ShopScreen.THUMB_FRAMING[String(parts[0])]))
				t.eq((card.art as ShopScreen.ShopPic).pic_key, want, "%s: its own portrait" % id)
			t.eq(card.src_l != null and card.src_l.text == "App Store", Catalogue.kind(id) == "apple_skin", "%s: an App Store line only on direct outfits" % id)
			t.check(card.when_l == null or Catalogue.is_rotation(id), "%s: a Leaves line only on rotating skins" % id)
			card.pressed.emit()
			await _frames(1)
			t.eq(shop.detail_id, id, "%s: the card opens that item" % id)
			if Catalogue.is_runner_item(id):
				t.eq(shop.preview_id, id, "%s: and previews it" % id)
			var heads: Array = shop.detail.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
			t.check(heads.has(Catalogue.display_name(id)), "%s: the sheet names it" % id)
			var kind_line := Catalogue.type_label(id) + shop._kind_note(id)
			t.check(heads.has(kind_line), "%s: the sheet says what and where from (%s)" % [id, kind_line])
			if Catalogue.kind(id) == "apple_skin":
				t.check(kind_line.ends_with("· App Store"), "direct outfit: App Store")
			shop._close_detail()
			await _frames(1)
			t.eq(shop.preview_id, "", "%s: closing ends the preview" % id)
			var v := App.stage.local_character() if App.stage else null
			if v:
				t.eq(v.cosmetic, saved, "%s: the real look again" % id)
	t.eq(Cosmetics.sanitize(Save.data["cosmetic"]), saved, "the save never changed")
	await _end()


func test_both_direct_outfits_and_six_coin_packs_are_always_reachable() -> void:
	for mode in ["live", "offline", "off"]:
		await _begin(mode != "off")
		if mode == "offline":
			# the connection drops: no session, the offers' time untrusted
			rig.svc.network_down = true
			Cloud.token = ""
			Cloud.state = "error"
			Offers.reload_as_new_run()
		var shop := await _shop("featured")
		t.eq(_card_ids(shop, "Grid_always"), APPLE, "%s: both App Store outfits in Featured › Always available" % mode)
		shop.select_section("outfits")
		await _frames(3)
		var sk := _card_ids(shop, "Grid_outfits")
		t.check(sk.has(APPLE[0]) and sk.has(APPLE[1]), "%s: and in All skins" % mode)
		shop.select_section("coins")
		await _frames(3)
		var packs := _card_ids(shop, "Grid_coins")
		t.eq(packs, Catalogue.shop_items("coins").map(func(it: Dictionary) -> String: return String(it["id"])), "%s: six Coin packs, smallest first" % mode)
		for id in APPLE:
			shop._open_detail(id)
			await _frames(2)
			var action := shop._d["action"] as Button
			var status := shop._d["status"] as Label
			if mode == "live":
				t.check(not action.disabled and action.text.contains("(test price)"), "%s: %s offers Apple's price (simulated): %s" % [mode, id, action.text])
			else:
				t.check(action.disabled and status.text != "", "%s: %s says why it can't be bought: %s" % [mode, id, status.text])
			shop._close_detail()
		await _end()


func test_preview_changes_presentation_only() -> void:
	await _begin()
	var shop := await _shop("outfits")
	var saved: Dictionary = Cosmetics.sanitize(Save.data["cosmetic"])
	var v: CharacterView = App.stage.local_character()
	var try := func(id: String) -> void:
		shop._open_detail(id)
	# Back from the sheet
	try.call("outfit:lantern_scout")
	await _frames(1)
	t.eq(String(v.cosmetic.get("outfit", "")), "lantern_scout", "previewing shows the skin")
	shop._go_hub()   # (Back with the sheet open closes the sheet)
	await _frames(1)
	t.eq(v.cosmetic, saved, "Back restores the real look")
	# a section change
	try.call("outfit:frog")
	shop.select_section("accessories")
	await _frames(1)
	t.eq(v.cosmetic, saved, "a section change restores it")
	# the filter
	shop.select_section("outfits")
	try.call("outfit:frog")
	shop._close_detail()
	(shop.body.find_child("HideOwned", true, false) as BaseButton).button_pressed = true
	await _frames(2)
	t.eq(shop.preview_id, "", "no stale preview after filtering")
	t.eq(v.cosmetic, saved, "filtering keeps the real look")
	# a cancelled App Store purchase: still previewing in the sheet, nothing saved
	rig.store.next_outcome = "cancel"
	try.call("outfit:starry_sleeper")
	shop._on_action()
	await rig.until(func() -> bool: return String(Purchases.states.get("com.idlery.ultimatetrifecta.skin.starry_sleeper", {}).get("state", "")) == "cancelled")
	t.eq(String(v.cosmetic.get("outfit", "")), "starry_sleeper", "the sheet still previews after a cancel")
	t.eq(Cosmetics.sanitize(Save.data["cosmetic"]), saved, "nothing was saved")
	# the Shop is closed from elsewhere with the sheet open (a match starting,
	# an invite): the real look comes back with it
	t.check(shop.preview_id != "", "still previewing when it closes")
	App.screen = null
	shop.queue_free()
	await _frames(2)
	t.eq(v.cosmetic, saved, "leaving the Shop any way restores the real look")
	t.eq(Cosmetics.sanitize(Save.data["cosmetic"]), saved, "and the save never changed")
	await _end()


func test_past_the_written_schedule_the_shop_still_rotates() -> void:
	await _begin(true, "2027-06-01T07:00:00Z")
	var sec := Catalogue.offers_section()
	var last := 0
	for o in sec.get("schedule", []):
		last = maxi(last, Catalogue.parse_utc_ms(String(o["ends_at_utc"])))
	t.check(svc_t > float(last), "the service clock is past the written schedule")
	t.eq(Offers.shop_status(), "live", "the Shop's time is trusted")
	var shop := await _shop("featured")
	var ids := _card_ids(shop, "Grid_featured")
	t.eq(ids.size(), 4, "four rotating offers: %s" % [ids])
	t.eq(Offers.active().size(), 4, "from the service")
	t.check(ids.all(func(id: String) -> bool: return Catalogue.is_rotation(id)), "all rotating skins")
	var o: Dictionary = Offers.active()[0]
	t.check(String(o["offer_id"]).begins_with("r1-2027"), "with the rule's own ids: %s" % o["offer_id"])
	rig.svc.grant(Cloud.profile_id(), 2000)
	await Wallet.refresh()
	var r: Dictionary = await Wallet.spend(String(o["item_id"]), o)
	t.check(bool(r["ok"]), "a computed offer can be bought: %s" % r.get("message", ""))
	t.eq(Wallet.balance(), 2000 - int(o["price"]), "at its price, once")
	await _end()
