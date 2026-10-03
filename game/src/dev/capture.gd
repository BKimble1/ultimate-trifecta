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
		if scenario == "social_hub" or scenario == "social_service_host":
			App.dev_expect = 99   # hold the room open for the capture


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
	if _shots.has("lobby_%dp" % want_players) and _t > float(_shots["lobby_%dp" % want_players]) + 1.0:
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
