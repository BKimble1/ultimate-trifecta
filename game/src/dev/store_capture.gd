extends "res://src/dev/season_final_capture.gd"
## App Store screenshots: the menu screens (development only; src/dev is
## never exported).  The real game's screens at a store screenshot size,
## with nothing stamped on them (--store-shot), in states that show the
## release's features.  It reuses the evidence drivers' fixtures:
##   season_final_capture.gd (its base: profile, test-double service,
##       Season states, snap + figure measure)
##   fake_commerce_service.gd + test_store_adapter.gd (the TEST-DOUBLE game
##       service and the simulated store: Season, Shop, wallet)
##   fake_friends.gd (the TEST-DOUBLE Game Center friends list and Friends
##       service; fictional players)
##   lobby_light_capture.gd's party (in-process loopback transport, no
##       network) and capture_pass8_match.gd's friend series (PartySeries)
## Every name is fictional; no real person's name appears.
##
##   --set=store  (default) the store shots:
##     s03_party     a full party of eight, everyone ready, in the dorm
##     s04_season    the Season Pass, Record Breaker on the stage (Tier 50)
##     s05_shop      the Shop's Featured page (Coin prices; the App Store
##                   outfits owned, so no store price shows)
##     s06_friends   Friends over the party room: friends online, in a
##                   party, in a round; one invited
##     s07_locker    the Locker (Outfit), a well-stocked wardrobe
##     s08_results   a friend series' final standings
##   --set=iap    App Review references for each product type (simulated
##                store: its "(test price)" shows, so each picture carries
##                a visible REFERENCE label and is not a store asset):
##     iap_coin_packs, iap_moonlight_runner, iap_starry_sleeper
##   --only=s04,s05  re-takes only those shots.
##
##   tools/capture_store_screenshots.sh OUT_DIR [iphone ipad]

const FakeFriends := preload("res://src/dev/fake_friends.gd")
const LobbyLight := preload("res://src/dev/lobby_light_capture.gd")

const ME := "Comfy Frog"
## the local player's look (owned in the fixture wallet)
const MY_LOOK := {"schema": 2, "outfit": "varsity_sprinter", "color": "tangerine", "skin": "tone3", "hair": "tuft",
	"hair_color": "brown", "hat": "none", "shoes": "sneakers", "face": "bright"}
## The party: seven friends in varied outfits (fictional, game-style names).
const PARTY := [
	["Sleepy Otter", {"outfit": "record_breaker"}],
	["Moonlit Owl", {"outfit": "dr_doom"}],
	["Bouncy Panda", {"outfit": "moonwalk_cadet", "skin": "tone6", "hair": "bob", "hair_color": "black"}],
	["Twinkly Gecko", {"outfit": "raincoat_explorer", "skin": "tone4", "hair": "curly", "hair_color": "black", "hat": "none"}],
	["Snug Koala", {"outfit": "pj", "pattern": "stripes", "color": "bubblegum", "skin": "tone7", "hair": "buns", "hair_color": "black",
		"hat": "nightcap", "shoes": "slippers"}],
	["Speedy Puffin", {"outfit": "duck"}],
	["Dreamy Newt", {"outfit": "pumpkin_pajamas", "skin": "tone2", "hair": "bob", "hair_color": "ginger", "hat": "none"}],
]
## Friends (Friends panel): in-game name, status, Game Center nickname
## (fictional handles).
const FRIENDS := [
	["T:_f0", "otterly.fast", "Sleepy Otter", "lobby", true],
	["T:_f1", "nightowl_88", "Quiet Badger", "online"],
	["T:_f2", "PillowFortPro", "Cozy Seal", "online"],
	["T:_f3", "quadsprinter", "Splashy Fox", "lobby"],
	["T:_f4", "moonbeam.runs", "Drowsy Moose", "match"],
	["T:_f5", "SockSlider", "Fuzzy Lamb", "offline"],
	["T:_f6", "lilnapper", "Wobbly Hedgehog", "offline"],
]
const IAP_LABEL := "REFERENCE ONLY · simulated store (\"(test price)\") · desktop render · retake on a device for App Review"

var _hub: LoopbackTransport.Hub
var _host: NetSession
var _clients: Array[NetSession] = []
var ff
var _pid := ""
var _ref_layer: CanvasLayer


func _wanted(shot: String) -> bool:
	return only == "" or Array(only.split(",")).any(func(o: String) -> bool: return shot.begins_with(o))


## A frame with nobody caught mid-blink or mid-fidget.
func snap(shot: String) -> void:
	_quiet_faces()
	await _wait(0.4)
	await _frames(4)       # layout and fades settled, however slow a frame is
	await super.snap(shot)


func _quiet_faces() -> void:
	var views: Array = []
	if App.stage != null:
		views.append_array(App.stage.chars.values())
	if App.screen != null and is_instance_valid(App.screen):
		views.append_array(App.screen.find_children("*", "CharacterView", true, false))
	for v in views:
		if v is CharacterView and is_instance_valid(v):
			(v as CharacterView)._blink_t = 1.0e6
			(v as CharacterView)._next_fidget = 1.0e6


func _store_profile() -> void:
	Save.data = Save.migrate({"version": 4, "uid": "local-store", "name": ME, "coins": 0, "level": 9, "xp": 120,
		"owned": [], "onboarded": true, "tutorial_done": true, "cosmetic": MY_LOOK.duplicate(),
		"stats": {"online": {"matches": 42}, "practice": {"matches": 9}}, "settings": {}})
	Save.data["onboarded"] = true
	Save.data["cosmetic"] = Cosmetics.sanitize(MY_LOOK)


func _look(over: Dictionary) -> Dictionary:
	var c: Dictionary = Cosmetics.DEFAULT.duplicate()
	for k in over:
		c[k] = over[k]
	return Cosmetics.sanitize(c)


func _run() -> void:
	await _wait(0.5)
	for n in get_tree().root.get_children():
		if n is BootCurtain:
			n.free()
	_store_profile()
	if shot_set == "iap":
		await _run_iap()
	else:
		await _run_store()
	printerr("CAPTURE-DONE")
	get_tree().quit()


# ------------------------------------------------------------------ service fixture
## A regular player on the TEST-DOUBLE service: Season 1 Premium at Tier 43
## (two rewards waiting), Coins, a wardrobe of Shop and Season outfits and
## both App Store outfits owned.
func _service_player() -> void:
	_pid = await _online("T:_store")
	svc.grant(_pid, 2650)
	_set_season(_pid, 13000, true)
	_claimed_through(_pid, 43, true, ["40:free", "40:premium"])
	var ent: Dictionary = svc.wallet(_pid)["entitlements"]
	for id in ["outfit:varsity_sprinter", "outfit:raincoat_explorer", "outfit:robe", "outfit:frog", "outfit:duck",
			"outfit:lantern_scout", "outfit:campus_courier"]:
		ent[id] = {"source": "coin_purchase"}
	for id in ["outfit:moonlight_runner", "outfit:starry_sleeper"]:
		ent[id] = {"source": "apple"}
	svc._bump(_pid)
	# the Shop's rotating offers on the fixture service clock (as
	# capture_shop_p8.gd: 2026-10-06 21:45:51 UTC, then real time)
	var t0 := float(Catalogue.parse_utc_ms("2026-10-06T21:45:51Z"))
	var wall0 := Time.get_unix_time_from_system() * 1000.0
	svc.clock_ms = func() -> float: return t0 + (Time.get_unix_time_from_system() * 1000.0 - wall0)
	await Wallet.refresh()
	await Offers.refresh()


func _run_store() -> void:
	await _service_player()
	# ---- the Season Pass: Record Breaker large on the stage, Tier 50 selected
	await _shot("s04_season", func(sp: SeasonScreen) -> void:
		sp.jump_to(50)
		await _wait(0.8), 2.0)
	# ---- the Shop's Featured page
	if _wanted("s05_shop"):
		ShopScreen.focus_section = "featured"
		ShopScreen.hide_owned = false
		App.goto_title()
		await _wait(0.8)
		NavShell.open("shop")
		await _wait(3.0)
		await _portraits_idle()
		var shop := App.screen as ShopScreen
		if shop:
			shop.scroll.scroll_vertical = 0
		await _wait(1.0)
		await snap("s05_shop")
	# ---- the Locker
	if _wanted("s07_locker"):
		App.goto_title()
		await _wait(0.8)
		NavShell.open("locker")
		await _wait(3.0)
		await _portraits_idle()
		await _wait(0.8)
		await snap("s07_locker")
	# ---- a friend series' final standings
	if _wanted("s08_results"):
		await _final_standings()
	# ---- the party room (in-process loopback transport): Friends over a
	# party of four, then the full party of eight
	FakeService.uninstall()
	svc = null
	if _wanted("s03_party") or _wanted("s06_friends"):
		App.goto_title()
		await _wait(0.6)
	if _wanted("s06_friends"):
		await _party(4)
		await _friends_over_party()
	if _wanted("s03_party"):
		await _party(8)
		await snap("s03_party")


# ------------------------------------------------------------------ party
func _party(n: int) -> void:
	if _hub == null:
		_hub = LoopbackTransport.Hub.new(7)
		var ht := LoopbackTransport.new(_hub, true)
		_host = NetSession.new()
		_host.name = "StoreCaptureHost"
		add_child(_host)
		_host.start_host(ht, "MOON42", Save.player_uid(), Save.party_name(), Save.data["cosmetic"], "any")
		App.session = _host
		App.party_code = "MOON42"
	while _clients.size() < n - 1:
		var i := _clients.size()
		var g: Array = PARTY[i]
		var ct := LoopbackTransport.new(_hub, false)
		var c := NetSession.new()
		c.name = "StoreCaptureGuest%d" % i
		add_child(c)
		c.start_client(ct, "MOON42", "guest-%d" % i, String(g[0]), _look(g[1]), "any")
		_clients.append(c)
		_hub.link((_host.transport as LoopbackTransport).id, ct.id)
		await _wait(0.25)
	if not (App.screen is LobbyScreen):
		App.show_lobby()
	# (frames, not seconds: at a store size a software-rendered frame can take
	# longer than a wait, and the loopback transport runs on physics ticks)
	await _until(func() -> bool: return _clients.all(func(c: NetSession) -> bool: return c.local_slot >= 0))
	for c in _clients:
		if c.local_slot >= 0:
			c.set_local_ready(true)
	await _until(func() -> bool: return _host.roster.filter(func(e: Variant) -> bool: return e != null and bool(e["ready"])).size() >= n - 1)
	await _frames(20)
	await _wait(3.0)
	await _portraits_idle()


## Waits (frames) until `cond` holds, at most `max_s` seconds.
func _until(cond: Callable, max_s: float = 30.0) -> void:
	var t0 := Time.get_ticks_msec()
	while not bool(cond.call()) and Time.get_ticks_msec() - t0 < int(max_s * 1000.0):
		await get_tree().physics_frame
	if not bool(cond.call()):
		printerr("STORE wait timed out")


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _physics_process(delta: float) -> void:
	if _hub != null:
		_hub.advance(delta)


# ------------------------------------------------------------------ friends
func _friends_over_party() -> void:
	ff = FakeFriends.new()
	var list: Array = []
	for f in FRIENDS:
		list.append([String(f[1]), String(f[0])])
	ff.native.set_friends(list)
	for f in FRIENDS:
		ff.mutual[String(f[0])] = {"name": String(f[2]), "status": String(f[3]), "in_your_party": f.size() > 4}
	ff.install()
	Social.available = true
	Social.authenticated = true
	Social.multiplayer_restricted = false
	Friends.call("reset_for_tests")
	await Cloud.sign_in()
	await Friends.call("refresh")
	var lobby: Control = App.screen
	var P: GDScript = load("res://src/ui/friends_panel.gd")
	var panel: Control = P.call("open", lobby)
	await _wait(1.5)
	await Friends.call("invite", "T:_f2")
	await _wait(1.2)
	if is_instance_valid(panel):
		panel.call("_refresh")
	await _wait(0.8)
	await snap("s06_friends")
	await _close_panels()
	ff.uninstall()
	ff = null


func _close_panels() -> void:
	var script: Script = load("res://src/ui/friends_panel.gd")
	for n in get_tree().root.find_children("*", "Control", true, false):
		if n.get_script() == script and not n.is_queued_for_deletion():
			n.call("close")
	await _wait(0.4)


# ------------------------------------------------------------------ results
## A three-round friend series recorded through PartySeries (Round Wins and
## shared places are the real rules' output): the Night Watch wins round 1
## (you and Sleepy Otter), the runners round 2, the Night Watch round 3 (you
## and Bouncy Panda).  The last round's results, then Final standings.
func _series_round(oc: int, watch: Array, k: int) -> Dictionary:
	var rows: Array = []
	var fin := 0
	for slot in 8:
		var nm := ME if slot == 0 else String(PARTY[slot - 1][0])
		var look: Dictionary = Save.data["cosmetic"] if slot == 0 else _look(PARTY[slot - 1][1])
		var r := {"slot": slot, "uid": Save.player_uid() if slot == 0 else "uid-%d" % slot, "name": nm, "is_bot": false,
			"role": TC.Role.PATROL if slot in watch else TC.Role.RUNNER, "present": true, "away_s": 0.0, "cosmetic": look}
		if slot in watch:
			var lead: bool = int(watch[0]) == slot
			r["captures"] = 3 if lead else 2
			r["unique_captures"] = 3 if lead else 1
		else:
			var home := oc == TC.Outcome.RUNNERS_WIN and fin < 4 and slot != 5
			r["stamps"] = 3 if home else [2, 1, 3, 2, 0, 1, 2, 1][slot]
			r["finished"] = home
			if home:
				fin += 1
				r["finish_order"] = fin
				r["finish_time"] = 121.0 + 14.0 * fin
			r["times_captured"] = 0 if home else 1 + (slot % 2)
		rows.append(r)
	return {"match_id": "store-s%d" % k, "outcome": oc, "players": rows, "finished": fin, "needed": 4, "watch": 2,
		"round_time": 177.0 if oc == TC.Outcome.RUNNERS_WIN else 240.0, "practice": false}


func _final_standings() -> void:
	App.goto_title()
	await _wait(0.6)
	var ps := PartySeries.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	ps.start({"watch": 2, "rounds": 3}, rng)
	var plan := [[TC.Outcome.PATROL_WIN, [0, 1]], [TC.Outcome.RUNNERS_WIN, [6, 7]], [TC.Outcome.PATROL_WIN, [0, 3]]]
	var last := {}
	for k in plan.size():
		last = _series_round(int(plan[k][0]), plan[k][1], k)
		ps.record_round(last)
	last = last.duplicate(true)
	last["series"] = ps.to_dict()
	last["round_index"] = 3
	last["rounds_total"] = 3
	var host := NetSession.new()
	host.mode = NetSession.Mode.HOST
	host.local_slot = 0
	host.series = ps
	host.series_view = last["series"]
	add_child(host)
	if App.screen and is_instance_valid(App.screen):
		App.screen.queue_free()
		App.screen = null
	var r := ResultsScreen.new()
	r.results = last
	r.reward = {"coins": 18, "xp": 40, "lines": [["Played the round", 10], ["Tags", 4], ["Team win", 4]]}
	r.session = host
	App._ensure_background()
	App._show(r)
	await _wait(2.2)
	await _portraits_idle()
	await snap("s08b_round_results")
	r._on_primary()          # the series is over: Final standings
	await _wait(2.0)
	await _portraits_idle()
	await snap("s08_results")
	host.queue_free()


# ------------------------------------------------------------------ IAP references
func _ref_label() -> void:
	_ref_layer = CanvasLayer.new()
	_ref_layer.layer = 121
	add_child(_ref_layer)
	var bg := PanelContainer.new()
	bg.add_theme_stylebox_override("panel", UIKit.box(Color(0.62, 0.08, 0.2, 0.9), 10, 0, Color.WHITE, 10))
	var l := UIKit.label(IAP_LABEL, 17, Color(1, 1, 1, 0.96), true, HORIZONTAL_ALIGNMENT_CENTER)
	bg.add_child(l)
	_ref_layer.add_child(bg)
	var vs := get_viewport().get_visible_rect().size
	bg.reset_size()
	var ms := bg.get_combined_minimum_size()
	bg.position = Vector2((vs.x - ms.x) * 0.5, vs.y - ms.y - 4.0)


func _run_iap() -> void:
	_pid = await _online("T:_review")
	svc.grant(_pid, 2650)
	await Wallet.refresh()
	await Offers.refresh()
	_ref_label()
	ShopScreen.hide_owned = false
	ShopScreen.focus_section = "coins"
	App.goto_title()
	await _wait(0.8)
	NavShell.open("shop")
	await _wait(3.0)
	await _portraits_idle()
	var shop := App.screen as ShopScreen
	if shop:
		shop.select_section("coins")
		await _wait(1.2)
		await snap("iap_coin_packs")
		for id in ["outfit:moonlight_runner", "outfit:starry_sleeper"]:
			shop.select_section("outfits")
			await _wait(0.6)
			shop._open_detail(id)
			await _wait(2.5)
			await _portraits_idle()
			await snap("iap_" + String(id).get_slice(":", 1))
			shop._close_detail()
			await _wait(0.6)
