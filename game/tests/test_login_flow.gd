extends RefCounted
## 2.2 build 15: what greets a player arriving home (LoginFlow), the daily
## present (DailyGift) and the Season Pass offer (PassOffer).
var t


func test_switched_off_under_test() -> void:
	t.check(not LoginFlow.enabled, "no greeting over screens under test")


func _rig() -> Variant:
	return preload("res://tests/commerce_rig.gd").new(t)


## The present is due once a day (the service says so), opens after its taps,
## adds the day's Coins once, and isn't due again until tomorrow.
func test_daily_present_opens_once_a_day() -> void:
	var rig: Variant = _rig()
	await rig.begin()
	await rig.sign_in()
	await Wallet.refresh()
	var list: Array = Catalogue.data()["economy"]["daily_gift"]["coins"]
	t.check(DailyGift.due(), "a present waits on the first visit")
	t.eq(int(Wallet.daily_state()["coins"]), int(list[0]), "day one's amount")
	var host := Screen.new()
	t.add_child(host)
	var g := DailyGift.open(host)
	await t.get_tree().process_frame
	t.check(host.has_modal(), "it sits over the screen")
	for i in DailyGift.TAPS - 1:
		g._on_tap()
	t.check(not g._opened, "not open before the last tap")
	t.check(g.present.energy > 0.5, "pumped up by the taps (%.2f)" % g.present.energy)
	g._on_tap()
	await rig.until(func() -> bool: return g.reveal.visible, 200)
	t.check(g.reveal.visible, "the burst shows the Coins")
	t.eq(Wallet.balance(), int(list[0]), "+%d Coins from the service" % int(list[0]))
	t.check(not DailyGift.due(), "not due again today")
	g._on_collect()
	await rig.until(func() -> bool: return not is_instance_valid(g) or not g.is_inside_tree(), 60)
	t.check(not host.has_modal(), "collected and closed")
	# the service never grants it twice
	var again: Dictionary = await Wallet.claim_daily()
	t.eq(int(again["granted"]), 0, "a second claim today grants nothing")
	t.eq(Wallet.balance(), int(list[0]), "balance unchanged")
	host.queue_free()
	await rig.end()


## The Season Pass offer counts its contents from the catalogue and sells
## Premium for its real Apple price.
func test_pass_offer_contents_and_price() -> void:
	var c := PassOffer.contents()
	t.check(int(c["outfits"]) >= 3 and int(c["rewards"]) > 20 and int(c["coins"]) > 0, "counted from the season table (%s)" % str(c))
	t.eq(Catalogue.product_of(PassOffer.premium_item()), PassOffer.PRODUCT, "the pass's Apple product")
	for it in PassOffer.SHOWCASE:
		t.check(Catalogue.season_tier_of(String(it[0])).size() > 0, "%s is a Season reward" % it[0])
	var rig: Variant = _rig()
	await rig.begin()
	await rig.sign_in()
	await rig.until(func() -> bool: return Purchases.products_state == "loaded")
	var host := Screen.new()
	t.add_child(host)
	var root := PassOffer.popup(host)
	await t.get_tree().process_frame
	var buy := root.find_child("BuyApple", true, false) as Button
	t.check(buy != null and buy.text.contains("(test price)"), "the button shows the store's own price (%s)" % (buy.text if buy else "-"))
	buy.pressed.emit()
	await rig.until(func() -> bool: return Wallet.premium("s1"), 200)
	t.check(Wallet.premium("s1"), "bought from the poster: Premium unlocked")
	await rig.until(func() -> bool: return buy.text == "Premium unlocked", 30)
	t.eq(buy.text, "Premium unlocked", "the poster says so")
	host.queue_free()
	await rig.end()


## The event poster's timing: due on the first visit, then not again for a
## while, then after a few launches.
func test_event_poster_cadence() -> void:
	var keep := {}
	for k in ["promo_seen_at", "promo_seen_launch", "launches"]:
		keep[k] = Save.get_setting(k, 0)
	Save.set_setting("promo_seen_at", 0)
	t.check(ChampionPromo.due(), "due the first time")
	Save.set_setting("promo_seen_at", Rankings.now())
	Save.set_setting("promo_seen_launch", 10)
	Save.set_setting("launches", 10)
	LoginFlow.away_s = 0
	t.check(not ChampionPromo.due(), "not again right away")
	Save.set_setting("promo_seen_at", Rankings.now() - ChampionPromo.PROMO_MIN_GAP_S - 5)
	Save.set_setting("launches", 10 + ChampionPromo.PROMO_EVERY_LAUNCHES)
	t.check(ChampionPromo.due(), "back after a few launches")
	Save.set_setting("launches", 11)
	LoginFlow.away_s = LoginFlow.AWAY_S
	t.check(ChampionPromo.due(), "back after time away")
	LoginFlow.away_s = 0
	for k in keep:
		Save.set_setting(k, keep[k])


## (2.2 build 16) the Season Pass track goes full screen and back.
func test_pass_track_maximizes() -> void:
	var stage := DormStage.new()
	t.add_child(stage)
	App.stage = stage
	App.goto(SeasonScreen)
	await t.get_tree().process_frame
	await t.get_tree().process_frame
	var sp := App.screen as SeasonScreen
	var w0 := sp.track_scroll.size.x
	sp.max_btn.pressed.emit()
	for i in 4:
		await t.get_tree().process_frame
	t.check(sp.maximized and not sp.fig_zone.visible and not sp._side_host.visible, "maximized: stage column and side panel step aside")
	t.check(sp.track_scroll.size.x > w0 * 1.4, "the track is much wider (%d -> %d)" % [w0, sp.track_scroll.size.x])
	sp.back_action.call()
	await t.get_tree().process_frame
	t.check(not sp.maximized and sp.fig_zone.visible, "Back restores the reward view")
	App.goto(TitleScreen)
	await t.get_tree().process_frame
	stage.queue_free()
	App.stage = null


## (2.2 build 16) Albums: every album has its music file and cover; choosing
## one saves it and the menu music plays it.
func test_albums_play_in_the_menus() -> void:
	var keep: Variant = Save.get_setting("album", Albums.DEFAULT)
	for a in Albums.LIST:
		t.check(ResourceLoader.exists("res://assets/audio/%s.ogg" % String(a["stream"])), "%s has its music" % a["title"])
		if String(a["cover"]) != "":
			t.check(Albums.cover(String(a["id"])) != null, "%s has its cover" % a["title"])
	t.eq(Albums.current(), String(keep), "the saved album")
	Albums.choose("stardust")
	t.eq(Albums.current(), "stardust", "chosen")
	t.eq(Albums.stream_key(), "album_stardust", "the menu music is its file")
	Albums.choose("not_an_album")
	t.eq(Albums.current(), "stardust", "an unknown id changes nothing")
	Save.set_setting("album", keep)
