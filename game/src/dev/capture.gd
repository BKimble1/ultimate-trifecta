extends Node
## Development-only evidence capture (created only from --capture=<scenario>;
## src/dev/ is excluded from iOS exports).
##
## Saves lossless PNGs of the real running game at moments chosen from actual
## game state (screen shown, player state transitions, events), plus a diag
## report of the measured render path next to them. Scenarios:
##   home      title screen, then the wardrobe
##   account   first-launch Create Your Runner + name sheet, Settings >
##             Profile, the Delete Game Profile confirmation (nothing saved)
##   lobby     a LAN room; waits for --capture-players=N humans (others are
##             headless --net-join processes), then captures the room
##   runner    practice as a runner (bot-driven: --local-bot): reveal,
##             outdoors, water entry / mid-splash / recovery, results
##   patrol    practice as Night Watch (bot-driven): shed, cart driving, an
##             on-foot tag, results
##   results   re-displays the results of a recorded round (the runner and
##             patrol scenarios save <scenario>_results.var; pass it with
##             --capture-results=path) for layout checks at other aspects,
##             then opens the scoreboard drawer

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
		"lobby":
			_lobby()
		"runner", "patrol":
			_match()
		"results":
			_results()


func _home() -> void:
	if _t > 7.0 and not _shots.has("home"):
		snap("home")
	elif _t > 8.0 and not _scheduled.has("wardrobe_open"):
		_scheduled["wardrobe_open"] = true
		App.goto(CreatorScreen)
		later(3.0, "wardrobe")
	elif _t > 12.0 and _shots.has("wardrobe"):
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
	if ph == TC.Phase.PLAYING:
		if _next_play_shot == 0.0:
			_next_play_shot = _t + 4.0
		if _t >= _next_play_shot and _play_shots < 6:
			_next_play_shot = _t + 9.0
			snap("%s_play_%d" % [scenario, _play_shots])
			_play_shots += 1
	if scenario == "runner":
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


func _on_sim_event(ev: Dictionary) -> void:
	var mc: MatchController = App.match_ctrl
	if mc == null:
		return
	if int(ev["type"]) == TC.Ev.CAPTURE and int(ev.get("b", -1)) == mc.local_slot and _captures < 2:
		_captures += 1
		later(0.35, "tag_capture_%d" % _captures)
