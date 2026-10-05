extends Node
## Development-only evidence for the V6 commerce screens (src/dev: never
## exported).  Runs the real Home, Locker, Shop (sections, detail sheet,
## Coin confirmation), Season Pass and the service-off states with the TEST
## ADAPTERS in place of the network: the test-double service
## (fake_commerce_service.gd) and the simulated store (test_store_adapter.gd,
## whose price strings read "(test price)").  Every shot is labelled so.
##
##   tools/gd.sh --path game --resolution 2532x1170 res://src/dev/commerce_capture.tscn -- \
##     --capture-dir=DIR --emulate-phone=3 --emulate-safe=59,0,59,21 --no-gamecenter
## (tools/capture_v6_commerce.sh runs the phone, SE and iPad sets.)

const FakeService := preload("res://src/dev/fake_commerce_service.gd")
const TestStore := preload("res://src/dev/test_store_adapter.gd")

var out_dir := ""
var only := ""
var svc
var store


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture-dir="):
			out_dir = a.get_slice("=", 1)
		elif a.begins_with("--only="):
			only = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _portraits_idle(max_s: float = 12.0) -> void:
	var t := 0.0
	while t < max_s:
		var ps := Portraits.shared()
		if ps.pending() == 0 and not ps._busy:
			break
		await get_tree().process_frame
		t += get_process_delta_time()
	await _wait(0.35)


func snap(shot: String) -> void:
	if only != "" and not Array(only.split(",")).any(func(o: String) -> bool: return shot.begins_with(o)):
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(shot + ".png"))
	printerr("CAPTURE %s %dx%d" % [shot, img.get_width(), img.get_height()])


func _setup_profile() -> void:
	# a V5 tester's save: a few Coin unlocks, a look, some rounds played
	Save.data = Save.migrate({"version": 3, "uid": "local-capture", "name": "Sleepy Otter", "coins": 345, "level": 6, "xp": 40,
		"owned": ["hat:crown", "outfit:robe", "color:plum"], "onboarded": true, "tutorial_done": true,
		"cosmetic": {"schema": 2, "outfit": "robe", "color": "plum", "hat": "crown", "hair": "curly", "skin": "tone6"},
		"stats": {"online": {"matches": 14}, "practice": {"matches": 6}}, "settings": {}})
	Save.data["onboarded"] = true


func _online() -> void:
	svc = FakeService.new()
	svc.install()
	store = TestStore.new()
	Purchases.use_adapter(store)
	svc.gc_player = "T:_capture"
	await Cloud.sign_in()
	var pid := Cloud.profile_id()
	svc.grant(pid, 1650)
	var s1: Dictionary = svc.wallet(pid)["season"]["s1"]
	s1["xp"] = 1450        # tier 8 (of 100 since Pass 9)
	s1["claimed"] = ["1:free"]
	svc.wallet(pid)["entitlements"]["card:after_hours"] = {"source": "season"}
	await Wallet.refresh()
	await _wait(0.5)
	Save.set_profile_style("card", "card:after_hours")


func _run() -> void:
	await _wait(0.5)
	_setup_profile()
	await _online()
	App.goto_title()
	await _wait(2.0)
	await snap("01_home_nav")
	# Locker
	NavShell.open("locker")
	await _wait(1.0)
	await _portraits_idle()
	await snap("02_locker_outfit")
	var lk := App.screen as CreatorScreen
	lk._select_tab("hat")
	await _wait(0.4)
	await _portraits_idle()
	await snap("03_locker_hat_view_in_shop")
	lk._select_tab("profile")
	await _wait(0.6)
	await snap("04_locker_profile")
	# Shop
	NavShell.open("shop")
	await _wait(1.0)
	await _portraits_idle()
	await snap("05_shop_featured")
	var shop := App.screen as ShopScreen
	shop.select_section("outfits")
	await _wait(0.5)
	await _portraits_idle()
	await snap("06_shop_outfits")
	shop.select_section("accessories")
	await _wait(0.5)
	await _portraits_idle()
	await snap("07_shop_accessories")
	shop.select_section("coins")
	await _wait(0.6)
	await snap("08_shop_coins_test_store")
	shop.select_section("season")
	await _wait(0.5)
	await snap("09_shop_season_offer")
	shop.select_section("outfits")
	await _wait(0.4)
	shop._open_detail("outfit:frog")
	await _wait(0.8)
	await _portraits_idle()
	await snap("10_shop_detail_preview")
	shop._preview_action("run")
	await _wait(0.6)
	await snap("11_shop_detail_run")
	shop._preview_action("idle")
	shop._confirm_spend("outfit:frog")
	await _wait(0.5)
	await snap("12_shop_coin_confirmation")
	App.screen.close_popover()
	for c in App.screen.get_children():
		if c.name == "ConfirmSpend" or c is ColorRect:
			c.queue_free()
	await _wait(0.3)
	shop._close_detail()
	shop.select_section("coins")
	await _wait(0.3)
	shop._open_detail("coins:1500")
	await _wait(0.5)
	await snap("13_shop_detail_coin_pack_test_store")
	shop._close_detail()
	shop.select_section("season")
	shop._open_detail("season:s1:premium")
	await _wait(0.5)
	await snap("14_shop_detail_season_premium")
	# Season Pass
	NavShell.open("pass")
	await _wait(1.2)
	await _portraits_idle()
	await snap("15_season_pass")
	var sp := App.screen as SeasonScreen
	sp.focus(10, "premium")
	sp.track_scroll.scroll_horizontal = int(sp.track_scroll.get_h_scroll_bar().max_value * 0.3)
	await _wait(0.6)
	await _portraits_idle()
	await snap("16_season_pass_premium_locked")
	sp.track_scroll.scroll_horizontal = int(sp.track_scroll.get_h_scroll_bar().max_value)
	sp.focus(30, "premium")
	await _wait(0.6)
	await snap("17_season_pass_tier30")
	# the shipped state today: no service in the build
	FakeService.uninstall()
	Purchases.use_adapter(StoreAdapter.new())
	Wallet.state = Wallet.blank_state()
	NavShell.open("shop")
	await _wait(1.0)
	(App.screen as ShopScreen).select_section("coins")
	await _wait(0.5)
	await snap("18_shop_service_off")
	NavShell.open("pass")
	await _wait(1.0)
	await snap("19_season_service_off")
	printerr("CAPTURE-DONE")
	get_tree().quit()
