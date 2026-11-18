extends Node
## Development-only evidence capture (created only from --capture=<scenario>;
## src/dev/ is excluded from iOS exports).
##
## Saves lossless PNGs of the real running game at moments chosen from actual
## game state (screen shown, player state transitions, events), plus a diag
## report of the measured render path next to them. Scenarios:
##   home      title screen, then the wardrobe
##   creator   a scripted tour of Create Your Runner (tabs, items, colours,
##             Run/Idle preview, turning); nothing is applied or saved
##   account   first-launch Create Your Runner + name sheet, Settings >
##             Profile, the Delete Game Profile confirmation (nothing saved)
##   lobby     a LAN room; waits for --capture-players=N humans (others are
##             headless --net-join processes), then captures the room
##   runner    practice as a runner (bot-driven: --local-bot): reveal,
##             outdoors, water entry / mid-splash / recovery, caught and
##             protected (if the bot runner is tagged), results
##   patrol    practice as Night Watch (bot-driven): shed, cart driving, an
##             on-foot tag, results
##   dorm      (V6) the runner scenario plus the home dorm: the reveal and
##             countdown inside it, the first steps out through a door, a
##             coin pickup (+1), the way home and the crossing back inside
##             (pick the dorm with --seed; the bot plays every step)
##   results   re-displays the results of a recorded round (the runner and
##             patrol scenarios save <scenario>_results.var; pass it with
##             --capture-results=path) for layout checks at other aspects,
##             then opens the scoreboard drawer
##   startup   normal boot (boot curtain over the title), then Practice as a
##             runner: loading screen, role reveal and countdown (for clips)
##   logo_*    (Pass 8) startup-logo evidence: logo_startup (every frame of
##             the real boot curtain and its fade), logo_variants (the
##             lockup drawn several ways); see logo_capture.gd
##   emotes    a LAN room (--capture-players=N): presses the real Emote and
##             Try moves buttons and tiles (Dance, Wave, Ha!, Sprint, Jump)
##   transition  the host of a LAN series (--net-host, --expect=2, a
##             headless --net-join client): round 1's results, the real
##             "Next: round 2" button, the party room, the host's "Start round 2"
##             once the guest is ready again, then round 2's
##             loading, reveal and countdown (for the multi-round clip)
##   series    the final results of a three-round friend series: a recorded
##             round (--capture-results=path) is played as round 3 after two
##             earlier rounds, all recorded through PartySeries (real Round
##             Wins, standings and role tally); two bot seats are relabelled
##             as friends.  Layout evidence only: no network play happens.
##   store_match  App Store screenshots of a staged practice round
##             (store_match_capture.gd; tools/capture_store_screenshots.sh)
## --store-shot (store_shot.gd): PNGs saved RGB, no overlay; nothing stamped.

const StoreShot := preload("res://src/dev/store_shot.gd")

var scenario := ""
var out_dir := ""
var label := ""
var want_players := 1
var _t := 0.0
var _shots: Dictionary = {}
var _scheduled: Dictionary = {}
var _pending: Array = []    # [{at, name}]
var _prev_state := -1
var _splashes := 0
var _recoveries := 0
var _cart_shots := 0
var _tag_shot := false
var _next_play_shot := 0.0
var _play_shots := 0
var _results_seen := -1.0
var _diag: Node
var _captures := 0
var results_path := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(out_dir)
	StoreShot.quiet_overlays()
	var dg: GDScript = load("res://src/dev/diag.gd")
	_diag = dg.new()
	add_child(_diag)
	# --capture-steps=N (with a low --fixed-fps): up to N fixed 60 Hz ticks
	# per drawn frame, so a whole round needs fewer software-rendered frames
	# (the simulation's ticks are the same; only fewer frames are drawn)
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--capture-steps="):
			Engine.max_physics_steps_per_frame = clampi(int(String(a).get_slice("=", 1)), 1, 30)
	if scenario.begins_with("social_"):
		# V6 social evidence (hub, chat, names, rankings): its own driver
		var sc: Node = (load("res://src/dev/capture_social.gd") as GDScript).new()
		sc.set("cap", self)
		sc.set("scenario", scenario)
		add_child(sc)
		if scenario == "social_hub" or scenario == "social_service_host" or scenario == "social_props":
			App.dev_expect = 99   # hold the room open for the capture
	elif scenario.begins_with("logo_"):
		# Pass 8 startup-logo evidence: its own driver
		var lg: Node = (load("res://src/dev/logo_capture.gd") as GDScript).new()
		lg.set("cap", self)
		lg.set("scenario", scenario)
		add_child(lg)
	elif scenario == "v7_screens":
		# V7 screens evidence (Friends, Settings, home, party, results,
		# dialogs) with measured layout: its own driver
		var v7: Node = (load("res://src/dev/capture_v7_screens.gd") as GDScript).new()
		v7.set("cap", self)
		add_child(v7)
	elif scenario == "maps_ui":
		# the map chooser: Practice, host and guest, controller focus
		var mu: Node = (load("res://src/dev/capture_maps_ui.gd") as GDScript).new()
		mu.set("cap", self)
		add_child(mu)
	elif scenario == "shop_final":
		# FINAL_RELEASE_SWEEP Shop: filters, App Store outfits, Coin packs with
		# simulated / unavailable prices, owned states, the offer cycle (DEV
		# FIXTURE service and store; labelled on every shot)
		var sf: Node = (load("res://src/dev/capture_shop_final.gd") as GDScript).new()
		sf.set("cap", self)
		add_child(sf)
	elif scenario == "shop_p8":
		# Pass 8 Shop rotation and Coin packs (DEV FIXTURE service clock,
		# schedule and store; labelled on every shot), V7 layout reports
		var p8: Node = (load("res://src/dev/capture_shop_p8.gd") as GDScript).new()
		p8.set("cap", self)
		add_child(p8)
	elif scenario == "store_match":
		# App Store screenshots (tools/capture_store_screenshots.sh): the
		# Pass 8 match driver's staging, store framing, nothing stamped
		var sm: Node = (load("res://src/dev/store_match_capture.gd") as GDScript).new()
		sm.set("cap", self)
		add_child(sm)
	elif scenario == "film":
		# website footage: a director's camera over a real bot round
		# (film_director.gd; tools/capture_film.sh)
		add_child((load("res://src/dev/film_director.gd") as GDScript).new())
	elif scenario == "pass8_match":
		# Pass 8 match clarity evidence (HUD states, map, results) with
		# measured HUD rects: its own driver (--p8-part=runner|patrol|results)
		var p8: Node = (load("res://src/dev/capture_pass8_match.gd") as GDScript).new()
		p8.set("cap", self)
		add_child(p8)


func snap(shot_name: String) -> void:
	if _shots.has(shot_name):
		return
	_shots[shot_name] = _t
	if DisplayServer.get_name() == "headless":
		printerr("CAPTURE-HEADLESS %s t=%.1f" % [shot_name, _t])   # timing only (no image)
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	if StoreShot.on():
		StoreShot.save_rgb(img, path)   # --store-shot: RGB, nothing stamped
	else:
		img.save_png(path)
	var rep: Dictionary = _diag.snapshot()
	rep["shot"] = shot_name
	rep["label"] = label
	rep["t"] = snappedf(_t, 0.01)
	var f := FileAccess.open(out_dir.path_join(shot_name + ".json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(rep, "  "))
	printerr("CAPTURE %s %dx%d t=%.1f" % [path, img.get_width(), img.get_height(), _t])


func later(delay: float, shot_name: String) -> void:
	_pending.append({"at": _t + delay, "name": shot_name})


func _process(delta: float) -> void:
	_t += delta
	for p in _pending.duplicate():
		if _t >= float(p["at"]):
			_pending.erase(p)
			snap(String(p["name"]))
	match scenario:
		"home":
			_home()
		"v22":
			_v22()
		"v25":
			_v25()
		"v26":
			_v26()
		"rift26":
			_rift26()
		"snow21":
			_snow21()
		"map22":
			_map22()
		"b18":
			_b18()
		"audit18":
			_audit18()
		"ko18":
			_ko18()
		"screens":
			_screens()
		"account":
			_account()
		"creator":
			_creator_tour()
		"lobby":
			_lobby()
		"runner", "patrol", "dorm":
			_match()
		"props23":
			_props23()
		"results":
			_results()
		"series":
			_series()
		"startup":
			_startup()
		"transition":
			_transition()
		"emotes":
			_emotes()
		"layout":
			_layout_editor()


## 2.2 evidence: the home lobby, the playlist sheet, the champion poster,
## Rankings (labelled sample rows) and the Official Rules.
func _v22() -> void:
	var steps := [[6.0, "home"], [7.0, "modes"], [9.0, "close"], [10.0, "promo"], [12.5, "close"], [13.5, "rankings"], [17.0, "rules"], [19.0, "quit"]]
	for st in steps:
		var key := "v22_%s" % str(st)
		if _t < float(st[0]) or _scheduled.has(key):
			continue
		_scheduled[key] = true
		match String(st[1]):
			"home":
				snap("v22_home")
			"modes":
				(App.screen as LobbyScreen)._mode_sheet()
				later(1.2, "v22_playlists")
			"close":
				if App.screen is Screen:
					(App.screen as Screen)._go_back()
			"promo":
				ChampionPromo.maybe_show(App.screen as Screen, true)
				later(1.6, "v22_champion_poster")
			"rankings":
				App.goto(RankingsScreen)
				later(2.0, "v22_rankings")
			"rules":
				ChampionPromo.open_rules(App.screen as Screen)
				later(1.0, "v22_rules")
			"quit":
				get_tree().quit()


## 2.2 build 15 evidence: home's coloured tabs, the daily present (idle,
## pumped, burst, the reveal), the event poster, the Season Pass with its
## offer poster.  (No game service here: the present is the preview.)
func _v25() -> void:
	var steps := [[6.0, "home"], [6.5, "gift"], [8.0, "tap"], [8.6, "tap"], [9.0, "tap"], [10.0, "tap"], [12.4, "close"],
		[13.5, "promo"], [16.0, "close"], [17.0, "pass"], [21.5, "close"], [22.5, "shot_pass"], [24.0, "quit"]]
	for st in steps:
		var key := "v25_%s" % str(st)
		if _t < float(st[0]) or _scheduled.has(key):
			continue
		_scheduled[key] = true
		match String(st[1]):
			"home":
				snap("v25_home_tabs")
			"gift":
				Save.set_setting("gift_day", "")
				DailyGift.open(App.screen as Screen)
				later(1.0, "v25_gift")
			"tap":
				var g := (App.screen as Node).find_child("DailyGift", true, false) as DailyGift
				if g:
					g._on_tap()
					if g._taps == 3:
						later(0.12, "v25_gift_pumped")
					elif g._taps == DailyGift.TAPS:
						later(0.25, "v25_gift_burst")
						later(1.9, "v25_gift_reveal")
			"close":
				var gg := (App.screen as Node).find_child("DailyGift", true, false)
				if gg:
					(gg as DailyGift)._on_collect()
				elif App.screen is Screen and (App.screen as Screen).has_modal():
					(App.screen as Screen)._go_back()
			"promo":
				ChampionPromo.maybe_show(App.screen as Screen, true)
				later(1.2, "v25_event_poster")
				later(1.9, "v25_event_poster_b")
			"pass":
				NavShell.open("pass")
				get_tree().create_timer(0.6).timeout.connect(func() -> void:
					if App.screen is Screen and not (App.screen as Screen).has_modal():
						PassOffer.popup(App.screen as Screen))
				later(3.0, "v25_pass_offer")
			"shot_pass":
				snap("v25_pass_screen")
			"quit":
				get_tree().quit()


## 2.2 build 16 evidence: Locker Music and Emotes, Settings › Audio, the
## Season Pass full screen.
func _v26() -> void:
	var steps := [[6.0, "locker_music"], [9.0, "locker_emotes"], [12.0, "settings"], [15.0, "pass"], [19.0, "pass_max"],
		[22.0, "quit"]]
	for st in steps:
		var key := "v26_%s" % str(st)
		if _t < float(st[0]) or _scheduled.has(key):
			continue
		_scheduled[key] = true
		match String(st[1]):
			"locker_music":
				CreatorScreen.open_category = "albums"
				NavShell.open("locker")
				later(2.4, "v26_locker_music")
			"locker_emotes":
				(App.screen as CreatorScreen)._select_tab("move")
				later(1.6, "v26_locker_emotes")
			"settings":
				SettingsScreen.open_tab = 2
				App.goto(SettingsScreen)
				later(1.6, "v26_settings_audio")
			"pass":
				NavShell.open("pass")
				get_tree().create_timer(1.0).timeout.connect(func() -> void:
					if App.screen is Screen and (App.screen as Screen).has_modal():
						(App.screen as Screen)._go_back())
				later(3.0, "v26_pass")
			"pass_max":
				if App.screen is SeasonScreen:
					(App.screen as SeasonScreen).set_maximized(true)
				later(1.5, "v26_pass_full")
			"quit":
				get_tree().quit()


## 2.2 build 18 evidence: home (Season pill, cocoa), the posters, the Shop
## (Season 1, Accessories with sets, Coins from the +), the Locker's looks.
func _b18() -> void:
	var steps := [[6.0, "home"], [7.5, "promo"], [10.0, "close"], [11.0, "pass_offer"], [14.0, "close"],
		[15.0, "shop"], [18.5, "shop_season"], [22.0, "shop_acc"], [25.0, "shop_coins"], [27.5, "locker"], [31.0, "quit"]]
	for st in steps:
		var key := "b18_%s" % str(st)
		if _t < float(st[0]) or _scheduled.has(key):
			continue
		_scheduled[key] = true
		match String(st[1]):
			"home":
				snap("b18_home")
			"promo":
				ChampionPromo.maybe_show(App.screen as Screen, true)
				later(1.8, "b18_event_poster")
			"pass_offer":
				PassOffer.popup(App.screen as Screen)
				later(2.4, "b18_pass_offer")
			"close":
				if App.screen is Screen and (App.screen as Screen).has_modal():
					(App.screen as Screen)._go_back()
			"shop":
				NavShell.open("shop")
				later(3.0, "b18_shop_featured")
			"shop_season":
				(App.screen as ShopScreen).select_section("season")
				later(3.0, "b18_shop_season")
			"shop_acc":
				(App.screen as ShopScreen).select_section("accessories")
				later(2.4, "b18_shop_accessories")
			"shop_coins":
				(App.screen as ShopScreen).select_section("coins")
				later(2.0, "b18_shop_coins")
			"locker":
				NavShell.open("locker")
				later(3.0, "b18_locker")
			"quit":
				get_tree().quit()


## UI audit (after build 18): every menu screen and tab, one shot each.
func _audit18() -> void:
	var steps := [
		[6.0, "home"], [7.0, "modes"], [9.0, "close"], [9.5, "friends"], [12.0, "close"],
		[12.5, "practice"], [15.0, "online"], [17.5, "howto"], [20.0, "rankings"],
		[23.0, "settings0"], [25.0, "settings1"], [26.5, "settings2"], [28.0, "settings3"], [29.5, "settings4"],
		[31.0, "locker_outfit"], [34.0, "locker_colours"], [36.0, "locker_face"], [38.0, "locker_hat"], [40.0, "locker_shoes"],
		[42.0, "locker_profile"], [44.0, "shop_skins"], [47.0, "shop_detail"], [49.5, "pass"], [53.0, "gift"], [56.0, "quit"]]
	for st in steps:
		var key := "a18_%s" % str(st)
		if _t < float(st[0]) or _scheduled.has(key):
			continue
		_scheduled[key] = true
		var what := String(st[1])
		match what:
			"home":
				snap("a18_home")
			"modes":
				(App.screen as LobbyScreen)._mode_sheet()
				later(1.2, "a18_playlists")
			"friends":
				FriendsPanel.open(App.screen as Screen)
				later(1.6, "a18_friends")
			"close":
				if App.screen is Screen and (App.screen as Screen).has_modal():
					(App.screen as Screen)._go_back()
			"practice":
				App.goto(PracticeScreen)
				later(1.8, "a18_practice")
			"online":
				App.goto(OnlineScreen)
				later(1.8, "a18_online")
			"howto":
				App.goto(HowToScreen)
				later(1.8, "a18_howto")
			"rankings":
				App.goto(RankingsScreen)
				later(2.2, "a18_rankings")
			"settings0", "settings1", "settings2", "settings3", "settings4":
				var ti := int(what.substr(8))
				if ti == 0:
					SettingsScreen.open_tab = 0
					App.goto(SettingsScreen)
				elif App.screen is SettingsScreen:
					(App.screen as SettingsScreen).show_tab(ti)
				later(1.2, "a18_settings_%d" % ti)
			"locker_outfit":
				NavShell.open("locker")
				later(2.4, "a18_locker_outfit")
			"locker_colours", "locker_face", "locker_hat", "locker_shoes", "locker_profile":
				if App.screen is CreatorScreen:
					(App.screen as CreatorScreen)._select_tab(what.substr(7))
				later(1.6, "a18_" + what)
			"shop_skins":
				NavShell.open("shop")
				get_tree().create_timer(0.8).timeout.connect(func() -> void:
					if App.screen is ShopScreen:
						(App.screen as ShopScreen).select_section("outfits"))
				later(2.4, "a18_shop_skins")
			"shop_detail":
				if App.screen is ShopScreen:
					(App.screen as ShopScreen)._open_detail("outfit:frog")
				later(1.4, "a18_shop_detail")
			"pass":
				NavShell.open("pass")
				get_tree().create_timer(1.0).timeout.connect(func() -> void:
					if App.screen is Screen and (App.screen as Screen).has_modal():
						(App.screen as Screen)._go_back())
				later(3.0, "a18_pass")
			"gift":
				NavShell.go_hub()
				get_tree().create_timer(1.5).timeout.connect(func() -> void:
					Save.set_setting("gift_day", "")
					if App.screen is Screen:
						DailyGift.open(App.screen as Screen))
				later(2.8, "a18_gift")
			"quit":
				get_tree().quit()


## 2.2 build 18 evidence: knocked out in a round (--autoplay=runner).
func _ko18() -> void:
	var mc: MatchController = App.match_ctrl
	if mc == null or not is_instance_valid(mc) or mc.sim == null or mc.hud == null:
		return
	if int(mc.local_info().get("phase", 0)) != TC.Phase.PLAYING:
		return
	var s := mc.sim
	var me := s.player(mc.local_slot)
	if not _scheduled.has("k1") and s.patrol_release_left() <= 0.0:
		_scheduled["k1"] = _t
		var by: SimPlayer = null
		for p in s.players:
			if p.is_patrol():
				by = p
				break
		if by != null:
			s._capture(me, by)
			mc.caught_by = by.display_name
		later(1.2, "ko18_caught")
	elif _scheduled.has("k1") and not _scheduled.has("k2") and _t > float(_scheduled["k1"]) + 4.5:
		_scheduled["k2"] = _t
		snap("ko18_out_watching")
	elif _scheduled.has("k2") and _t > float(_scheduled["k2"]) + 2.0:
		get_tree().quit()


## 2.2 build 16 evidence: a rift in a round (--autoplay=runner).
func _rift26() -> void:
	var mc: MatchController = App.match_ctrl
	if mc == null or not is_instance_valid(mc) or mc.sim == null or mc.hud == null:
		return
	if int(mc.local_info().get("phase", 0)) != TC.Phase.PLAYING:
		return
	var s := mc.sim
	var me := s.player(mc.local_slot)
	if not _scheduled.has("r1") and not s.rifts.is_empty():
		_scheduled["r1"] = _t
		if not bool(s.rifts[0]["open"]):
			s.rifts[0] = Rifts.pick(s.layout, s._rift_rng, {})   # (rare now: open one for the picture)
		var at := Rifts.world(s.layout, int(s.rifts[0]["at"]))
		me.body.global_position = at + Vector3(0, 0.05, 5.0)
		me.yaw = 0.0
		later(2.0, "r26_rift")
	elif _scheduled.has("r1") and not _scheduled.has("r2") and _t > float(_scheduled["r1"]) + 3.0:
		_scheduled["r2"] = _t
		mc.hud.actions.toggle_row()
		later(0.6, "r26_emote_wheel")
	elif _scheduled.has("r2") and not _scheduled.has("r3") and _t > float(_scheduled["r2"]) + 1.5:
		_scheduled["r3"] = _t
		mc.hud.actions._close_row()
		if mc.hud.chat != null:
			mc.hud.chat.open_drawer()
			later(1.0, "r26_chat")
	elif _scheduled.has("r3") and _t > float(_scheduled["r3"]) + 2.5:
		get_tree().quit()


## (build 21) Snow evidence (a practice round as a runner, --autoplay):
## the runner is put at the edge of a snow drift facing across it (the bot
## then runs its own way, through or past), shots as the prints appear,
## another drift, then beside a hiding bush to show the snow on top.
func _snow21() -> void:
	var mc: MatchController = App.match_ctrl
	if mc == null or not is_instance_valid(mc) or mc.sim == null:
		return
	if int(mc.local_info().get("phase", 0)) != TC.Phase.PLAYING or mc.snow_cover.is_empty():
		return
	var s := mc.sim
	var me := s.player(mc.local_slot)
	var ps: Array = mc.snow_cover["patches"]
	var put := func(p: Vector2, toward: Vector2) -> void:
		print("SNOW put at %s (snow %.2f)" % [str(p), SnowCover.amount_at(mc.snow_cover, p)])
		me.body.global_position = Vector3(p.x, CampusBuilder.grid_y(s.layout, p.x, p.y) + 0.1, p.y)
		var d := toward - p
		me.yaw = atan2(-d.x, -d.y)
		mc.camera.snap_to(me.body.global_position, me.yaw)
	var steps := [[0.0, "a"], [0.8, "s1"], [3.5, "back"], [3.55, "s2"], [4.2, "b"], [7.7, "back2"], [7.75, "s3"], [8.3, "c"], [10.5, "s4"], [11.5, "quit"]]
	if not _scheduled.has("snow_t0"):
		_scheduled["snow_t0"] = _t
	var t0 := float(_scheduled["snow_t0"])
	for st in steps:
		var key := "snow_%s" % String(st[1])
		if _t < t0 + float(st[0]) or _scheduled.has(key):
			continue
		_scheduled[key] = true
		match String(st[1]):
			"a", "b":
				# in the middle of a drift: the runner's own way out leaves prints
				var q: Vector4 = ps[0 if String(st[1]) == "a" else mini(1, ps.size() - 1)]
				var c := Vector2(q.x, q.y)
				_scheduled["snow_patch"] = q
				put.call(c, c + Vector2(1, 0))
			"back", "back2":
				# from the drift's edge, looking back across it at the prints
				var q2: Vector4 = _scheduled.get("snow_patch", ps[0])
				var c2 := Vector2(q2.x, q2.y)
				var mp := Vector2(me.body.global_position.x, me.body.global_position.z)
				var away := (mp - c2).normalized() if mp.distance_to(c2) > 0.5 else Vector2(1, 0)
				put.call(c2 + away * (q2.z * 0.45), c2)
			"c":
				if not mc.bush_views.is_empty():
					var bp := (mc.bush_views[0] as Node3D).global_position
					put.call(Vector2(bp.x + 3.5, bp.z + 3.5), Vector2(bp.x, bp.z))
			"quit":
				print("SNOW prints placed: %d" % (mc.prints.placed if mc.prints else -1))
				get_tree().quit()
			_:
				print("SNOW shot %s: runner at %s" % [String(st[1]), str(me.body.global_position)])
				snap("snow21_%s" % String(st[1]))


## (build 22) Map clean-up evidence (a practice round as a runner, the bot
## standing still): road crossings, the home dorm's interior from its room
## and from a door, and a building close up.  Each stop: the runner is put
## there facing the subject, a shot a moment later.
const MAP22_STOPS := [
	["xing_a", Vector2(5.0, 87.0), Vector2(0.0, 88.0)],
	["xing_b", Vector2(-28.0, -6.0), Vector2(-36.0, -14.0)],
	["xing_c", Vector2(-73.0, 9.0), Vector2(15.7, 88.0)],
	["xing_d", Vector2(73.0, 37.0), Vector2(78.0, 32.0)],
]


func _map22() -> void:
	var mc: MatchController = App.match_ctrl
	if mc == null or not is_instance_valid(mc) or mc.sim == null:
		return
	if int(mc.local_info().get("phase", 0)) != TC.Phase.PLAYING:
		return
	var s := mc.sim
	var me := s.player(mc.local_slot)
	if not _scheduled.has("map_t0"):
		_scheduled["map_t0"] = _t
		_scheduled["map_i"] = 0
		_scheduled["map_next"] = _t
	if _t < float(_scheduled["map_next"]):
		return
	var stops: Array = []
	# each crossing: from 6 m along the road, looking at it
	for st0 in MAP22_STOPS:
		var x: Vector2 = st0[2]
		var dir := Vector2.RIGHT
		var best := INF
		for r in s.layout.roads:
			var pts: PackedVector2Array = r["pts"]
			for j in pts.size() - 1:
				var dd := CampusData.dist_to_segment(x, pts[j], pts[j + 1])
				if dd < best:
					best = dd
					dir = (pts[j + 1] - pts[j]).normalized()
		stops.append([st0[0], x - dir * 6.0, x])
	# a building close up (window boxes, downpipes, foundation shrubs)
	stops.append(["bldg_library", Vector2(-31.0, 12.0), Vector2(-39.0, 20.0)])
	stops.append(["bldg_dining", Vector2(-30.0, 52.0), Vector2(-42.0, 58.0)])
	# the home dorm: inside its room (looking across it) and from its door
	var g := CampusDorms.geometry(mc.home_dorm)
	if not g.is_empty():
		var room: PackedVector2Array = g["room"]
		var c := Vector2.ZERO
		for v in room:
			c += v
		c /= float(room.size())
		var far := room[0]
		for v in room:
			if (v as Vector2).distance_to(c) > far.distance_to(c):
				far = v
		stops.append(["dorm_room", c + (c - far).normalized() * 1.5, far])
		stops.append(["dorm_room2", c + (far - c).normalized() * 2.0, c - (far - c)])
		var dr: Dictionary = (g["doors"] as Array)[0]
		stops.append(["dorm_door", (dr["pos"] as Vector2) + (dr["normal"] as Vector2) * 6.0, dr["pos"]])
	var i := int(_scheduled["map_i"])
	var step := int(_scheduled.get("map_step", 0))
	if i >= stops.size():
		get_tree().quit()
		return
	var st: Array = stops[i]
	if step == 0:
		# an overhead camera for the crossings (the follow camera sits too low
		# to read road markings); the follow camera again otherwise
		var oc: Variant = _scheduled.get("map_cam")
		if oc != null and is_instance_valid(oc):
			(oc as Node).queue_free()
			_scheduled.erase("map_cam")
			mc.camera.make_current()
		if String(st[0]).begins_with("xing"):
			var cam := Camera3D.new()
			mc.add_child(cam)
			var xp: Vector2 = st[2]
			var gy0 := CampusBuilder.grid_y(s.layout, xp.x, xp.y)
			var back := ((st[1] as Vector2) - xp).normalized()
			cam.look_at_from_position(Vector3(xp.x + back.x * 7.0, gy0 + 11.0, xp.y + back.y * 7.0), Vector3(xp.x, gy0, xp.y))
			cam.fov = 55.0
			cam.make_current()
			_scheduled["map_cam"] = cam
		var p: Vector2 = st[1]
		var to: Vector2 = st[2]
		var gy := CampusBuilder.grid_y(s.layout, p.x, p.y)
		if String(st[0]).begins_with("dorm_room"):
			gy = float(g.get("floor", 0.0))
		me.body.global_position = Vector3(p.x, gy + 0.1, p.y)
		var d := to - p
		me.yaw = atan2(-d.x, -d.y)
		mc.camera.snap_to(me.body.global_position, me.yaw)
		_scheduled["map_step"] = 1
		_scheduled["map_next"] = _t + 1.2
	else:
		snap("map22_%s" % String(st[0]))
		_scheduled["map_step"] = 0
		_scheduled["map_i"] = i + 1
		_scheduled["map_next"] = _t + 0.6


func _home() -> void:
	if _t > 7.0 and not _shots.has("home"):
		snap("home")
	elif _t > 8.0 and not _scheduled.has("wardrobe_open"):
		_scheduled["wardrobe_open"] = true
		App.goto(CreatorScreen)
		later(3.0, "wardrobe")
	elif _t > 12.0 and _shots.has("wardrobe"):
		get_tree().quit()


const CREATOR_TOUR := [
	[1.5, "open"], [3.0, "pick", "outfit", "robe"], [4.5, "pick", "pattern", "plain"], [6.0, "tab", 1],
	[7.0, "pick", "color", "coral"], [8.0, "pick", "trim", "gold"], [9.0, "tab", 1], [10.0, "pick", "face", "bright"],
	[11.0, "tab", 1], [12.0, "pick", "hair", "bob"], [13.0, "pick", "hair_color", "auburn"], [14.0, "tab", 1],
	[15.0, "pick", "hat", "none"], [15.5, "tab", 1], [16.6, "pick", "shoes", "sneakers"], [17.5, "tab", 1],
	[19.0, "run"], [22.0, "turn"], [25.0, "run"], [27.0, "end"],
]


func _creator_tour() -> void:
	for step in CREATOR_TOUR:
		var key := "tour_%s" % str(step)
		if _t < float(step[0]) or _scheduled.has(key):
			continue
		_scheduled[key] = true
		var c: CreatorScreen = App.screen as CreatorScreen
		match String(step[1]):
			"open":
				App.goto(CreatorScreen)
				later(1.4, "creator_outfit_tiles")   # thumbnails render a few frames apart
			"pick":
				if c and Cosmetics.CATALOG.get(String(step[2]), {}).has(String(step[3])):
					c._pick(String(step[2]), String(step[3]))
			"tab":
				if c:
					c._step_tab(int(step[2]))
					later(0.9, "creator_tab_%s" % c.tab)
			"run":
				if c:
					c.run_btn.pressed.emit()
			"turn":
				if c:
					var tw := c.create_tween()
					for i in 60:
						tw.tween_callback(c.drag_turn.bind(9.0)).set_delay(1.0 / 30.0)
			"end":
				get_tree().quit()


func _account() -> void:
	if _t > 5.0 and not _scheduled.has("onboard"):
		_scheduled["onboard"] = true
		App._onboarding()
		later(2.5, "first_run_creator")
	elif _t > 8.5 and not _scheduled.has("name"):
		_scheduled["name"] = true
		NameSheet.ask(App.screen, true)
		later(1.0, "first_run_name")
	elif _t > 11.0 and not _scheduled.has("settings"):
		_scheduled["settings"] = true
		App.goto(SettingsScreen)
		later(2.0, "settings_profile")
	elif _t > 14.0 and not _scheduled.has("delete"):
		_scheduled["delete"] = true
		(App.screen as SettingsScreen)._confirm_delete()
		later(1.0, "delete_confirm")
	elif _t > 16.5 and _shots.has("delete_confirm"):
		get_tree().quit()


## Settings > Edit layout: the runner and Night Watch clusters, a dragged
## action cluster, then Try it with two fingers down (synthetic touches
## through the editor's own router).
func _layout_editor() -> void:
	var steps := [[5.0, "open"], [8.0, "patrol"], [10.5, "drag"], [13.0, "try"], [16.0, "end"]]
	for st in steps:
		var key := "layout_" + String(st[1])
		if _t < float(st[0]) or _scheduled.has(key):
			continue
		_scheduled[key] = true
		var ed := App.screen as TouchLayoutEditor
		match String(st[1]):
			"open":
				App.goto(TouchLayoutEditor)
				later(2.0, "layout_runner")
			"patrol":
				if ed:
					ed._set_ctx("patrol")
					later(1.0, "layout_patrol")
			"drag":
				if ed:
					var c := ed.canvas
					c._resolve()
					var a: Vector2 = c.res["action_anchor"]
					c._pointer(0, a, true, Vector2.ZERO, false)
					c._pointer(0, a + Vector2(-260, -60), true, Vector2(-260, -60), true)
					c._pointer(0, a + Vector2(-260, -60), false, Vector2.ZERO, false)
					later(1.0, "layout_dragged")
			"try":
				if ed:
					ed.try_btn.button_pressed = true
					var c2 := ed.canvas
					c2._resolve()
					var z: Rect2 = c2.res["zone"]
					c2._pointer(1, z.get_center(), true, Vector2.ZERO, false)
					c2._pointer(1, z.get_center() + Vector2(30, -110), true, Vector2(30, -110), true)
					c2._pointer(2, c2.res["buttons"]["tag"]["c"], true, Vector2.ZERO, false)
					later(1.0, "layout_try")
			"end":
				get_tree().quit()


## Menu screens in turn: online sheet, practice, settings, how-to.
func _screens() -> void:
	var seq := [[6.0, OnlineScreen, "online"], [9.0, PracticeScreen, "practice"], [12.0, SettingsScreen, "settings"], [15.0, HowToScreen, "howto"]]
	for st in seq:
		var key := "open_" + String(st[2])
		if _t > float(st[0]) and not _scheduled.has(key):
			_scheduled[key] = true
			App.goto(st[1])
			later(2.2, String(st[2]))
	if _t > 18.0 and _shots.has("howto"):
		get_tree().quit()


func _lobby() -> void:
	var s: NetSession = App.session
	if s == null:
		return
	if s.human_count() >= want_players and not _scheduled.has("lobby_wait"):
		_scheduled["lobby_wait"] = true
		later(4.0, "lobby_%dp" % want_players)
	if _shots.has("lobby_%dp" % want_players) and _t > float(_shots["lobby_%dp" % want_players]) + 1.0 and not _scheduled.has("chat"):
		# (2.2) typed chat, filtered on the devices: one message with a bad
		# word (it goes out bleeped), the bubble over the head, the drawer
		_scheduled["chat"] = true
		s.social.chat.send_text("nice run %s!" % Marshalls.base64_to_utf8("ZnVjaw=="), s.social.chat.my_channel(false))
		later(1.2, "lobby_chat_bubble")
	if _shots.has("lobby_chat_bubble") and not _scheduled.has("drawer"):
		_scheduled["drawer"] = true
		(App.screen as LobbyScreen)._open_chat()
		later(1.5, "lobby_chat_drawer")
	if _shots.has("lobby_chat_drawer") and _t > float(_shots["lobby_chat_drawer"]) + 1.0:
		get_tree().quit()


## 2.3 evidence (--autoplay=runner --capture=props23): a power-up hologram,
## a hiding bush, a runner hidden in it, and the Speed Sneakers bar.
func _props23() -> void:
	var mc: MatchController = App.match_ctrl
	if mc == null or not is_instance_valid(mc) or mc.sim == null or mc.hud == null:
		return
	if int(mc.local_info().get("phase", 0)) != TC.Phase.PLAYING:
		return
	var s := mc.sim
	var me := s.player(mc.local_slot)
	if not _scheduled.has("p1"):
		_scheduled["p1"] = _t
		var pk: Vector3 = s.pickups[0]["pos"]
		me.body.global_position = pk + Vector3(0, 0.05, 3.6)
		me.yaw = 0.0
		later(2.0, "p23_hologram")
	elif not _scheduled.has("p2") and _t > float(_scheduled["p1"]) + 3.0:
		_scheduled["p2"] = _t
		var bp: Vector2 = s.hide_bushes[0]
		me.body.global_position = Vector3(bp.x + 2.4, CampusBuilder.grid_y(s.layout, bp.x + 2.4, bp.y) + 0.05, bp.y + 1.2)
		me.yaw = PI * 0.5 - 0.35
		later(2.0, "p23_bush")
	elif not _scheduled.has("p3") and _t > float(_scheduled["p2"]) + 3.0:
		_scheduled["p3"] = _t
		var bp2: Vector2 = s.hide_bushes[0]
		me.body.global_position = Vector3(bp2.x + 1.3, CampusBuilder.grid_y(s.layout, bp2.x + 1.3, bp2.y) + 0.05, bp2.y)
		var c := InputCmd.new()
		c.pressed = TC.BTN_INTERACT
		s._intent_hide(me, c)
		later(1.2, "p23_hidden")
	elif not _scheduled.has("p4") and _t > float(_scheduled["p3"]) + 3.0:
		_scheduled["p4"] = _t
		s.unhide(me)
		me.gadget = TC.Gadget.TURBO
		var c2 := InputCmd.new()
		c2.pressed = TC.BTN_GADGET
		s._intent_gadget(me, c2)
		later(2.5, "p23_powerbar")
	elif _scheduled.has("p4") and _t > float(_scheduled["p4"]) + 4.0:
		get_tree().quit()


func _match() -> void:
	if App.screen is ResultsScreen:
		if _results_seen < 0.0:
			_results_seen = _t
			later(2.0, "%s_results" % scenario)
			var rs := App.screen as ResultsScreen
			var f := FileAccess.open(out_dir.path_join("%s_results.var" % scenario), FileAccess.WRITE)
			if f:
				f.store_string(var_to_str({"results": rs.results, "reward": rs.reward,
					"local_slot": rs.session.local_slot if rs.session else -1}))
		elif _t > _results_seen + 3.0:
			get_tree().quit()
		return
	var mc: MatchController = App.match_ctrl
	if mc == null or not is_instance_valid(mc) or mc.hud == null:
		return
	if mc.sim != null and not mc.sim.event_emitted.is_connected(_on_sim_event):
		mc.sim.event_emitted.connect(_on_sim_event)
	var info := mc.local_info()
	var rs: Dictionary = info.get("rs", {})
	var st: int = int(rs.get("state", -1))
	var ph: int = int(info.get("phase", 0))
	if ph == TC.Phase.REVEAL and not _scheduled.has("reveal"):
		_scheduled["reveal"] = true
		later(1.5, "%s_reveal" % scenario)
	if scenario == "dorm":
		_dorm_shots(mc, info, rs, st, ph)
	if ph == TC.Phase.PLAYING:
		if _next_play_shot == 0.0:
			_next_play_shot = _t + 4.0
		if _t >= _next_play_shot and _play_shots < 6:
			_next_play_shot = _t + 9.0
			snap("%s_play_%d" % [scenario, _play_shots])
			_play_shots += 1
		# the full map once, a few seconds into the chase
		if _play_shots >= 2 and not _scheduled.has("map"):
			_scheduled["map"] = true
			mc.hud.open_map()
			later(1.0, "%s_map" % scenario)
			get_tree().create_timer(2.5).timeout.connect(func() -> void:
				if is_instance_valid(mc) and mc.hud:
					mc.hud.close_map())
	if scenario == "runner" or scenario == "dorm":
		if st == TC.PState.SPLASHING and _prev_state != TC.PState.SPLASHING and _splashes < 2:
			_splashes += 1
			snap("water_%d_entry" % _splashes)
			later(0.7, "water_%d_mid" % _splashes)
			if _splashes == 1:
				# the whole sequence, one frame every 0.15 s (entry to recovery)
				for k in 17:
					later(0.05 + 0.15 * k, "water_seq_%02d" % k)
		if _prev_state == TC.PState.SPLASHING and st == TC.PState.ACTIVE and _recoveries < 2:
			_recoveries += 1
			later(0.25, "water_%d_recovery" % _recoveries)
		if st == TC.PState.FINISHED and _prev_state != TC.PState.FINISHED:
			later(0.4, "runner_home")
		# the capture contract: "Caught by … · back in 6…", then "Protected"
		if st == TC.PState.CAPTURED and _prev_state != TC.PState.CAPTURED and not _scheduled.has("caught"):
			_scheduled["caught"] = true
			later(0.6, "runner_caught")
		if _prev_state == TC.PState.CAPTURED and st == TC.PState.ACTIVE and not _scheduled.has("protected"):
			_scheduled["protected"] = true
			later(0.4, "runner_protected")
	else:
		if st == TC.PState.IN_CART and _cart_shots < 3 and absf(float(rs.get("steer", 0.0))) >= 0.0:
			if not _shots.has("cart_drive_%d" % _cart_shots) and (_cart_shots == 0 or _t > float(_shots.get("cart_drive_%d" % (_cart_shots - 1), 0.0)) + 6.0):
				if _prev_state == TC.PState.IN_CART:
					snap("cart_drive_%d" % _cart_shots)
					_cart_shots += 1
		var tp: int = int(rs.get("tag_phase", 0))
		if tp == 2 and not _tag_shot:
			_tag_shot = true
			snap("tag_lunge")
	_prev_state = st


## V6 dorm evidence: inside at the countdown, out through a door, a coin,
## the way back and the crossing in (all from real game state).
var _was_inside := false
var _coin_shots := 0


func _dorm_shots(mc: MatchController, info: Dictionary, rs: Dictionary, st: int, ph: int) -> void:
	if not rs.has("pos"):
		return
	var p: Vector3 = rs["pos"]
	var inside := CampusDorms.in_room(mc.home_dorm, p)
	if ph == TC.Phase.COUNTDOWN and not _scheduled.has("countdown"):
		_scheduled["countdown"] = true
		later(0.5, "dorm_%s_countdown" % mc.home_dorm)
	if ph == TC.Phase.PLAYING:
		if _was_inside and not inside and not _scheduled.has("departure") and st == TC.PState.ACTIVE:
			_scheduled["departure"] = true
			snap("dorm_%s_departure" % mc.home_dorm)
			later(0.8, "dorm_%s_departure_b" % mc.home_dorm)
		# a coin still out on the way, a few metres ahead of the runner
		if not _scheduled.has("coin_route") and mc.coin_view != null:
			var cl: Array = mc.start.get("coins", [])
			for ci in cl.size():
				var cp := Vector2(float(cl[ci]["x"]), float(cl[ci]["z"]))
				var dd := Vector2(p.x, p.z).distance_to(cp)
				var cam := get_viewport().get_camera_3d()
				if mc.coin_view.is_out(ci) and dd > 4.0 and dd < 9.0 and cam != null and cam.is_position_in_frustum(Vector3(cp.x, 1.0, cp.y)):
					_scheduled["coin_route"] = true
					snap("dorm_coin_route")
					break
		var coins := int(info.get("coins", 0))
		if coins > _coin_shots and _coin_shots < 2:
			_coin_shots = coins
			later(0.2, "dorm_coin_%d" % coins)
		if int(info.get("stamps", 0)) == 7 and st == TC.PState.ACTIVE:
			for d in mc.layout.home_doors(mc.home_dorm):
				var dist := Vector2(p.x, p.z).distance_to(d["pos"])
				if dist < 14.0 and not _scheduled.has("approach"):
					_scheduled["approach"] = true
					snap("dorm_%s_return_approach" % mc.home_dorm)
				if dist < 3.5 and not _scheduled.has("doorway"):
					_scheduled["doorway"] = true
					snap("dorm_%s_return_doorway" % mc.home_dorm)
		if st == TC.PState.FINISHED and not _scheduled.has("home"):
			_scheduled["home"] = true
			snap("dorm_%s_home" % mc.home_dorm)
	_was_inside = inside


## Results of a recorded round shown again (same ResultsScreen code), then
## the scoreboard drawer opened.
func _results() -> void:
	if _t > 3.0 and not _scheduled.has("show"):
		_scheduled["show"] = true
		var d: Dictionary = str_to_var(FileAccess.get_file_as_string(results_path))
		var s := NetSession.new()
		s.local_slot = int(d["local_slot"])
		add_child(s)
		App._ensure_background()
		var r := ResultsScreen.new()
		r.results = d["results"]
		r.reward = d["reward"]
		r.session = s
		# (2.2) the run card, as after a real round (nothing sent anywhere)
		r.rank = Rankings.record(d["results"], int(d["local_slot"]), false, false)
		App._show(r)
		later(2.5, "results")
	elif _shots.has("results") and _t > float(_shots["results"]) + 0.6 and not _scheduled.has("drawer"):
		# (wait until the "results" PNG is written: snap() awaits the frame)
		_scheduled["drawer"] = true
		(App.screen as ResultsScreen)._toggle_board()
		later(1.5, "results_drawer")
	elif _shots.has("results_drawer") and _t > float(_shots["results_drawer"]) + 1.0:
		get_tree().quit()


func _startup() -> void:
	if _t > 4.0 and not _scheduled.has("go"):
		_scheduled["go"] = true
		snap("startup_title")
		App.start_practice("runner", false)
	if _t > 6.0 and App.screen is LoadingScreen and not _shots.has("startup_loading"):
		snap("startup_loading")
	var mc: MatchController = App.match_ctrl
	if mc != null and is_instance_valid(mc) and mc.round_live() and not _scheduled.has("live"):
		_scheduled["live"] = _t
	if _scheduled.has("live") and _t > float(_scheduled["live"]) + 9.0:
		get_tree().quit()


func _transition() -> void:
	if App.screen is ResultsScreen and not _scheduled.has("res"):
		_scheduled["res"] = _t
		later(1.5, "transition_results")
	if _scheduled.has("res") and not _scheduled.has("next") and _t > float(_scheduled["res"]) + 6.0:
		_scheduled["next"] = _t
		_press("Next: round 2")
	if _scheduled.has("next") and App.screen is LobbyScreen and not _scheduled.has("party"):
		_scheduled["party"] = true
		later(0.8, "transition_party")
	# the host starts round 2 once the guest is ready again, as a person would
	if _shots.has("transition_party") and not _scheduled.has("start2") and App.session != null and App.session.can_start():
		_scheduled["start2"] = _t
		_press("Start round 2")
	var mc: MatchController = App.match_ctrl
	if _scheduled.has("next") and mc != null and is_instance_valid(mc) and mc.round_live() and not _scheduled.has("live2"):
		_scheduled["live2"] = _t
		later(1.0, "transition_round2")
	if _scheduled.has("live2") and _t > float(_scheduled["live2"]) + 8.0:
		get_tree().quit()


## Press a visible button by its tooltip (icon buttons) or its label text
## (tiles), the same signal a tap or controller press emits.
func _press(text: String) -> bool:
	for b in get_tree().root.find_children("*", "Button", true, false):
		var btn := b as Button
		if not btn.is_visible_in_tree():
			continue
		var hit := btn.tooltip_text == text or btn.text == text
		if not hit:
			for l in btn.find_children("*", "Label", true, false):
				if (l as Label).text == text:
					hit = true
					break
		if hit:
			btn.pressed.emit()
			return true
	printerr("CAPTURE no button '%s'" % text)
	return false


const EMOTE_STEPS := [
	[2.0, "Emote"], [3.4, "Dance"], [3.0, "shot:lobby_emote_picker"], [5.0, "shot:lobby_emote_dance"],
	[8.0, "Emote"], [9.2, "Wave"], [12.0, "Emote"], [13.2, "Ha!"], [16.0, "Try moves"], [17.2, "Sprint"],
	[17.4, "shot:lobby_try_sprint"], [20.0, "Try moves"], [21.2, "Jump"], [25.0, "quit"],
]


func _emotes() -> void:
	var s: NetSession = App.session
	if s == null or not (App.screen is LobbyScreen) or s.human_count() < want_players:
		return
	if not _scheduled.has("t0"):
		_scheduled["t0"] = _t + 2.0
	var t := _t - float(_scheduled["t0"])
	for st in EMOTE_STEPS:
		var key := "em_%s_%s" % [st[0], st[1]]
		if t < float(st[0]) or _scheduled.has(key):
			continue
		_scheduled[key] = true
		var what := String(st[1])
		if what == "quit":
			get_tree().quit()
		elif what.begins_with("shot:"):
			snap(what.substr(5))
		else:
			_press(what)


func _series() -> void:
	if _t > 3.0 and not _scheduled.has("show"):
		_scheduled["show"] = true
		var d: Dictionary = str_to_var(FileAccess.get_file_as_string(results_path))
		var res: Dictionary = (d["results"] as Dictionary).duplicate(true)
		var local := int(d["local_slot"])
		# one bot seat on each side becomes a friend
		var need := {TC.Role.RUNNER: "Pip", TC.Role.PATROL: "Rowan"}
		var rows: Array = res.get("players", [])
		for r in rows:
			var row: Dictionary = r
			var role := int(row.get("role", TC.Role.RUNNER))
			if int(row.get("slot", -1)) == local:
				row["uid"] = Save.player_uid()
			elif bool(row.get("is_bot", false)) and need.has(role):
				row["name"] = need[role]
				row["uid"] = "friend-" + String(need[role])
				row["is_bot"] = false
				need.erase(role)
			elif String(row.get("uid", "")) == "":
				row["uid"] = "bot-%d" % int(row.get("slot", 0))
		var ps := PartySeries.new()
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		ps.start({"watch": 2, "rounds": 3}, rng)
		# rounds 1 and 2: the same people, roles rotated (bots keep theirs)
		var me := Save.player_uid()
		var plan := [
			{"outcome": TC.Outcome.RUNNERS_WIN, me: TC.Role.RUNNER, "friend-Pip": TC.Role.PATROL, "friend-Rowan": TC.Role.RUNNER},
			{"outcome": TC.Outcome.PATROL_WIN, me: TC.Role.PATROL, "friend-Pip": TC.Role.RUNNER, "friend-Rowan": TC.Role.RUNNER},
		]
		for k in plan.size():
			var earlier: Array = []
			for r in rows:
				var e: Dictionary = (r as Dictionary).duplicate()
				if plan[k].has(String(e.get("uid", ""))):
					e["role"] = plan[k][String(e["uid"])]
				earlier.append(e)
			ps.record_round({"match_id": "series-r%d" % (k + 1), "outcome": plan[k]["outcome"], "round_time": 200.0, "players": earlier})
		res["match_id"] = "series-r3"
		ps.record_round(res)
		res["series"] = ps.to_dict()
		res["round_index"] = 3
		res["rounds_total"] = 3
		res["practice"] = false
		var s := NetSession.new()
		s.mode = NetSession.Mode.HOST
		s.local_slot = local
		s.series_view = res["series"]
		add_child(s)
		App._ensure_background()
		var rsc := ResultsScreen.new()
		rsc.results = res
		rsc.reward = d["reward"]
		rsc.session = s
		App._show(rsc)
		later(2.5, "series_final")
	elif _shots.has("series_final") and _t > float(_shots["series_final"]) + 0.6 and not _scheduled.has("scroll"):
		_scheduled["scroll"] = true
		# the standings sit below the round: scroll the sheet to them
		for sc in App.screen.find_children("*", "ScrollContainer", true, false):
			(sc as ScrollContainer).scroll_vertical = 100000
		later(0.8, "series_final_standings")
	elif _shots.has("series_final_standings") and _t > float(_shots["series_final_standings"]) + 1.0:
		get_tree().quit()


func _on_sim_event(ev: Dictionary) -> void:
	var mc: MatchController = App.match_ctrl
	if mc == null:
		return
	if int(ev["type"]) == TC.Ev.CAPTURE and int(ev.get("b", -1)) == mc.local_slot and _captures < 2:
		_captures += 1
		later(0.35, "tag_capture_%d" % _captures)
