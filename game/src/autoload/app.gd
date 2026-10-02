extends Node
## App flow: launch -> title -> (practice | online room) -> lobby -> loading ->
## role reveal/countdown -> match -> results -> rematch/leave.

var session: NetSession
var screen: Node
var match_ctrl: MatchController
var last_results: Dictionary = {}
var practice_role := "runner"
var _pending_message := ""
var _ui_layer: CanvasLayer
## the dorm common room behind every menu (home, wardrobe, lobby)
var stage: DormStage
# dev/automation flags (ignored in normal play)
var dev_local_bot := false
var dev_shots_dir := ""
var dev_quit_after := 0.0
var dev_seed := -1
var dev_report := ""
var dev_rounds := 1
var dev_expect := 8
var _dev_rounds_done := 0
var _dev_report_rows: Array = []
var _dev_t := 0.0
var _dev_pf := -1
var _dev_win: Dictionary = {}
var _dev_shot_i := 0
var _dev_next_shot := 2.0
## automation / capture runs skip first-launch onboarding
var dev_automation := false


## Client version code sent to the service (rooms record it for version
## messages): marketing version 1.1 -> 101.  Compatibility between players is
## decided by Protocol.VERSION.
static func build_number() -> int:
	var v := String(ProjectSettings.get_setting("application/config/version", "1.0")).split(".")
	return int(v[0]) * 100 + (int(v[1]) if v.size() > 1 else 0)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().set_auto_accept_quit(true)
	QualityPreset.apply(int(Save.get_setting("quality", 1)))
	Social.invite_ready.connect(_on_invite_ready)
	Social.auth_changed.connect(_on_gc_auth)
	# automation runs (simulator evidence) skip the Game Center sign-in sheet
	if not OS.get_cmdline_user_args().has("--no-gamecenter"):
		Social.authenticate()
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 10
	add_child(_ui_layer)
	for a in OS.get_cmdline_user_args():
		if a == "--local-bot":
			dev_local_bot = true
		elif a.begins_with("--shots="):
			dev_shots_dir = a.split("=")[1]
			DirAccess.make_dir_recursive_absolute(dev_shots_dir)
		elif a.begins_with("--quit-after="):
			dev_quit_after = float(a.split("=")[1])
		elif a.begins_with("--seed="):
			dev_seed = int(a.split("=")[1])
		elif a.begins_with("--report="):
			dev_report = a.split("=")[1]
		elif a.begins_with("--rounds="):
			dev_rounds = int(a.split("=")[1])
		elif a.begins_with("--expect="):
			dev_expect = int(a.split("=")[1])
		elif a.begins_with("--quality="):
			# dev/automation: pick the graphics preset for a measured run
			Save.set_setting("quality", int(a.split("=")[1]))
		elif a.begins_with("--name="):
			# dev/automation: e.g. long-name layout checks
			Save.data["name"] = a.substr(a.find("=") + 1)
		elif a.begins_with("--gc-sim="):
			# dev/automation: show the Game Center states on desktop captures
			# (unavailable is the real desktop state; the others are labelled
			# simulations of what iOS reports)
			match a.split("=")[1]:
				"declined":
					Social.available = true
					Social.auth_error = "The user canceled the sign-in"
				"restricted":
					Social.available = true
					Social.authenticated = true
					Social.multiplayer_restricted = true
				"signing_in":
					Social.available = true
				"ready":
					# signed in (simulated): shows the online screen as on iOS;
					# nothing that needs the real Game Center is invoked
					Social.available = true
					Social.authenticated = true
					Social.display_name = "Player"
		elif a.begins_with("--sim-pad="):
			# dev/automation: render controller prompts on desktop captures
			# (labelled simulation: no physical controller is attached)
			Controls.device = "gamepad"
			Controls.family = a.get_slice("=", 1)
		elif a == "--random-cosmetic":
			# dev/automation: soak and lobby-capture clients wear varied outfits
			Save.data["cosmetic"] = Cosmetics.bot_cosmetic(hash(Save.player_uid()))
	for a in OS.get_cmdline_user_args():
		for p in ["--autoplay=", "--capture=", "--shots=", "--net-", "--report=", "--skip-onboarding"]:
			if a.begins_with(p):
				dev_automation = true
	_dev_tools(OS.get_cmdline_user_args())
	if OS.get_cmdline_user_args().has("--no-app"):
		return
	call_deferred("_boot")


## Development-only diagnostics and evidence capture. The scripts live in
## src/dev/ (excluded from iOS exports) and are loaded by path, so a release
## build simply finds nothing to load.
func _dev_tools(args: PackedStringArray) -> void:
	var diag_overlay := args.has("--diag")
	if args.has("--beta-diag"):
		# dev evidence: the in-game beta diagnostics on, summary printed at exit
		Diag.enabled = true
		Diag._apply_measuring()
		tree_exiting.connect(func() -> void: print("BETA_DIAG_SUMMARY_BEGIN\n%s\nBETA_DIAG_SUMMARY_END" % Diag.summary()))
	var diag_report := ""
	var capture := ""
	var capture_dir := ""
	var capture_label := ""
	var capture_players := 1
	var capture_results := ""
	for a in args:
		if a.begins_with("--diag-report="):
			diag_report = a.split("=")[1]
		elif a.begins_with("--capture="):
			capture = a.split("=")[1]
		elif a.begins_with("--capture-dir="):
			capture_dir = a.split("=")[1]
		elif a.begins_with("--capture-label="):
			capture_label = a.substr(a.find("=") + 1)
		elif a.begins_with("--capture-players="):
			capture_players = int(a.split("=")[1])
		elif a.begins_with("--capture-results="):
			capture_results = a.substr(a.find("=") + 1)
	if (diag_overlay or diag_report != "") and ResourceLoader.exists("res://src/dev/diag.gd"):
		var dg: Node = (load("res://src/dev/diag.gd") as GDScript).new()
		dg.set("show_overlay", diag_overlay)
		dg.set("report_path", diag_report)
		add_child(dg)
	if capture != "" and ResourceLoader.exists("res://src/dev/capture.gd"):
		var cp: Node = (load("res://src/dev/capture.gd") as GDScript).new()
		cp.set("scenario", capture)
		cp.set("out_dir", capture_dir if capture_dir != "" else OS.get_user_data_dir().path_join("capture"))
		cp.set("label", capture_label)
		cp.set("want_players", capture_players)
		cp.set("results_path", capture_results)
		add_child(cp)
		if capture == "lobby":
			dev_expect = 99   # hold the room open for the capture


## Background resource loads whose requester went away before they finished
## (the loading screen closed while its loop was still loading).  They are
## collected when done and dropped, so the loader holds nothing; a new
## requester can take one over instead of asking twice.
var _orphan_loads: PackedStringArray = []
var _orphan_timer: Timer


func adopt_threaded_load(path: String) -> void:
	if not _orphan_loads.has(path):
		_orphan_loads.append(path)
	_start_reaper()


func _start_reaper() -> void:
	if _orphan_timer == null:
		_orphan_timer = Timer.new()
		_orphan_timer.wait_time = 0.25
		_orphan_timer.timeout.connect(_reap_threaded_loads)
		add_child(_orphan_timer)
	_orphan_timer.start()


## True when `path` was an orphaned request: the caller now owns it (poll it
## and load_threaded_get it) instead of requesting it again.
func claim_threaded_load(path: String) -> bool:
	if not _orphan_loads.has(path):
		return false
	_orphan_loads.remove_at(_orphan_loads.find(path))
	return true


## V6: worker-pool jobs of a round cancelled while it was being prepared;
## each is waited for (which releases it) only once it has finished.
var _orphan_tasks: Array[int] = []


func adopt_worker_tasks(ids: Array[int]) -> void:
	if ids.is_empty():
		return
	_orphan_tasks.append_array(ids)
	_start_reaper()


func _reap_threaded_loads() -> void:
	for id in _orphan_tasks.duplicate():
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
			_orphan_tasks.erase(id)
	for p in _orphan_loads.duplicate():
		var st := ResourceLoader.load_threaded_get_status(p)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			ResourceLoader.load_threaded_get(p)     # taken and let go
		_orphan_loads.remove_at(_orphan_loads.find(p))
	if _orphan_loads.is_empty() and _orphan_tasks.is_empty() and _orphan_timer:
		_orphan_timer.stop()


func _process(delta: float) -> void:
	if dev_quit_after <= 0.0 and dev_shots_dir == "" and dev_report == "":
		return
	_dev_t += delta
	if dev_shots_dir != "" and _dev_t >= _dev_next_shot:
		_dev_next_shot += 4.0
		var img := get_viewport().get_texture().get_image()
		img.save_png(dev_shots_dir.path_join("shot_%03d.png" % _dev_shot_i))
		_dev_shot_i += 1
	if dev_quit_after > 0.0 and _dev_t >= dev_quit_after:
		get_tree().quit()
	if dev_report != "":
		# per-window frame cost (V6 soak): script time in _process and
		# _physics_process, physics steps per frame, growth counters
		var pf := Engine.get_physics_frames()
		var steps := pf - _dev_pf if _dev_pf >= 0 else 1
		_dev_pf = pf
		_dev_win["frames"] = int(_dev_win.get("frames", 0)) + 1
		_dev_win["proc_max"] = maxf(float(_dev_win.get("proc_max", 0.0)), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		_dev_win["phys_max"] = maxf(float(_dev_win.get("phys_max", 0.0)), Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		_dev_win["proc_sum"] = float(_dev_win.get("proc_sum", 0.0)) + Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		_dev_win["phys_sum"] = float(_dev_win.get("phys_sum", 0.0)) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		_dev_win["steps_max"] = maxi(int(_dev_win.get("steps_max", 0)), steps)
		if steps >= 2:
			_dev_win["multi"] = int(_dev_win.get("multi", 0)) + 1
	if dev_report != "" and int(_dev_t) % 5 == 0 and int(_dev_t - delta) % 5 != 0:
		var st := "no session"
		if session:
			var readies := []
			for e in session.roster:
				if e != null:
					readies.append("%s%s" % [e["slot"], "R" if bool(e["ready"]) else "-"])
			st = "mode=%d phase=%d slot=%d host_peer=%d humans=%d roster=%s connected=%s peers=%s" % [session.mode, session.phase, session.local_slot, session.host_peer, session.human_count(), str(readies), session.connected, str(session.transport.peers() if session.transport else [])]
		printerr("SOAK t=%.0f %s match=%s fps=%.0f" % [_dev_t, st, match_ctrl != null, Engine.get_frames_per_second()])
		var n := maxi(1, int(_dev_win.get("frames", 1)))
		printerr("COST t=%.0f frames=%d proc_avg=%.2f proc_max=%.2f phys_avg=%.2f phys_max=%.2f steps_max=%d multi=%d objects=%d nodes=%d orphans=%d mem_mb=%.1f" % [
			_dev_t, n, float(_dev_win.get("proc_sum", 0.0)) / n, float(_dev_win.get("proc_max", 0.0)),
			float(_dev_win.get("phys_sum", 0.0)) / n, float(_dev_win.get("phys_max", 0.0)), int(_dev_win.get("steps_max", 0)), int(_dev_win.get("multi", 0)),
			Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
		_dev_win = {}


func _boot() -> void:
	var cs := get_tree().current_scene
	if cs != null and cs.scene_file_path != "" and cs.scene_file_path != "res://src/main.tscn":
		return   # tools / dev scenes run without the menu flow
	var args := OS.get_cmdline_user_args()
	var lag := 0.0
	var jitter := 0.0
	var loss := 0.0
	for a in args:
		if a.begins_with("--lag="):
			lag = float(a.split("=")[1])
		elif a.begins_with("--jitter="):
			jitter = float(a.split("=")[1])
		elif a.begins_with("--loss="):
			loss = float(a.split("=")[1])
	for a in args:
		if a.begins_with("--net-host"):
			var port := int(a.split("=")[1]) if a.contains("=") else 7787
			host_room_enet(port)
			_shape(lag, jitter, loss)
			_dev_autostart()
			return
		if a.begins_with("--net-join="):
			var addr := a.split("=")[1]
			var port2 := 7787
			if addr.contains(":"):
				port2 = int(addr.split(":")[1])
				addr = addr.split(":")[0]
			join_room_enet(addr, port2)
			_shape(lag, jitter, loss)
			# dev/automation: ready up (after --ready-after=S seconds in the
			# room, for recordings of the ready response; default at once)
			var ready_after := 0.0
			for a2 in args:
				if a2.begins_with("--ready-after="):
					ready_after = float(a2.get_slice("=", 1))
			if session:
				var joined_at := {"t": -1.0}
				session.lobby_changed.connect(func() -> void:
					if session and session.local_slot >= 0 and session.phase == TC.Phase.LOBBY:
						if joined_at["t"] < 0.0:
							joined_at["t"] = Time.get_ticks_msec() / 1000.0
							if ready_after > 0.0:
								get_tree().create_timer(ready_after).timeout.connect(func() -> void:
									if session and session.local_slot >= 0 and session.phase == TC.Phase.LOBBY:
										session.set_local_ready(true))
						var e: Variant = session.roster[session.local_slot]
						if e != null and not bool(e["ready"]) and ready_after <= 0.0:
							session.set_local_ready(true))
			return
	for a in args:
		if a.begins_with("--autoplay="):
			# dev/automation hook: jump straight into practice as a role
			practice_role = a.split("=")[1]
			start_practice("runner" if practice_role == "tutorial" else practice_role, practice_role == "tutorial")
			return
	get_tree().root.add_child(BootCurtain.new())
	goto_title()


func _shape(lag: float, jitter: float, loss: float) -> void:
	if session and session.transport is EnetTransport:
		var et := session.transport as EnetTransport
		et.latency_ms = lag
		et.jitter_ms = jitter
		et.loss = loss


func _dev_autostart() -> void:
	# host: start as soon as the expected humans are in and ready
	var timer := Timer.new()
	timer.wait_time = 0.5
	timer.autostart = true
	add_child(timer)
	timer.timeout.connect(func() -> void:
		if session == null or match_ctrl != null or session.phase != TC.Phase.LOBBY:
			return
		if session.human_count() >= dev_expect and session.can_start():
			session.host_start_match(dev_seed))


func _dev_record(results: Dictionary, reward: Dictionary) -> void:
	if dev_report == "":
		return
	var row := {"round": _dev_rounds_done + 1, "mode": ["offline", "host", "client"][session.mode] if session else "?",
		"slot": session.local_slot if session else -1, "outcome": int(results.get("outcome", 0)),
		"finished": int(results.get("finished", 0)), "round_time": results.get("round_time", 0.0),
		"reward_coins": int(reward.get("coins", 0)), "rtt_ms": snappedf(session.rtt * 1000.0, 1) if session else 0.0}
	if match_ctrl:
		var corr: Array = match_ctrl.stat_corrections
		var avg := 0.0
		var mx := 0.0
		for e in corr:
			avg += e
			mx = maxf(mx, e)
		row["snapshots"] = match_ctrl.stat_snapshots
		row["corr_avg_m"] = snappedf(avg / maxf(1.0, corr.size()), 0.0001)
		row["corr_max_m"] = snappedf(mx, 0.001)
		row["fps_avg"] = Engine.get_frames_per_second()
	if session and session.transport is EnetTransport:
		var et := session.transport as EnetTransport
		row["sent"] = et.stats_sent
		row["dropped_by_shaper"] = et.stats_dropped
		row["lag_ms"] = et.latency_ms
		row["loss"] = et.loss
	if session and session.mode == NetSession.Mode.HOST:
		row["host_starved"] = session.stat_starved
		row["host_skipped"] = session.stat_skipped
		var humans := 0
		for r in results.get("players", []):
			if not bool(r.get("is_bot", false)):
				humans += 1
		row["humans"] = humans
	_dev_report_rows.append(row)
	var f := FileAccess.open(dev_report, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_dev_report_rows, "  "))


# ---------------------------------------------------------------------------
# Screens
# ---------------------------------------------------------------------------
func _show(node: Control) -> void:
	Controls.clear_edges()   # a press that opened/closed a menu never reaches play
	if screen and is_instance_valid(screen):
		screen.queue_free()
	screen = node
	_ui_layer.add_child(node)


func _ensure_background() -> void:
	if stage and is_instance_valid(stage):
		return
	stage = DormStage.new()
	stage.name = "DormStage"
	get_tree().root.add_child(stage)
	sync_stage_local()


func _clear_background() -> void:
	if stage and is_instance_valid(stage):
		stage.queue_free()
	stage = null


## Home/wardrobe: only the local player's character on the stage.
func sync_stage_local() -> void:
	if stage == null or not is_instance_valid(stage):
		return
	var in_room := session != null and is_instance_valid(session) and session.mode != NetSession.Mode.OFFLINE
	stage.sync_party([{"key": Save.player_uid(), "role": TC.Role.RUNNER, "cosmetic": Save.data["cosmetic"],
		"name": Save.player_name(), "is_bot": false, "local": true, "arrive": false}], not in_room)


func goto_title(message: String = "") -> void:
	_end_match_scene()
	_ensure_background()
	Sfx.music("menu")
	if not bool(Save.data.get("onboarded", false)) and not dev_automation:
		_onboarding(message)
		return
	var t := TitleScreen.new()
	_show(t)
	if message != "":
		t.show_message(message)
	elif _pending_message != "":
		t.show_message(_pending_message)
		_pending_message = ""


## First launch: Create Your Runner, then a player name (kept on this device
## until the service checks it at the first online party).
func _onboarding(message: String = "") -> void:
	var c := CreatorScreen.new()
	c.first_run = true
	c.on_done = func() -> void:
		await NameSheet.ask(c, true)
		Save.data["onboarded"] = true
		Save.save_now()
		sync_cloud_appearance()
		goto_title()
	_show(c)
	if message != "":
		UIKit.toast(c, message, 3.0)


## Game Center signed in: sign in to the game service too (verified on the
## server from Game Center's identity signature).
func _on_gc_auth(ok: bool) -> void:
	if ok and Cloud.configured() and not Cloud.signed_in():
		var r: Dictionary = await Cloud.sign_in()
		if bool(r.get("ok", false)):
			sync_cloud_appearance()


## The runner's look lives on this device (coins and owned items are local);
## the service keeps a copy for the profile.  Pushed only when it differs.
func sync_cloud_appearance() -> void:
	if not Cloud.signed_in():
		return
	var mine := Cosmetics.sanitize(Save.data["cosmetic"])
	var theirs: Variant = Cloud.profile.get("appearance")
	if theirs is Dictionary and Cosmetics.sanitize(theirs) == mine:
		return
	var r: Dictionary = await Cloud.set_appearance(mine)
	if bool(r.get("ok", false)):
		Cloud.profile["appearance"] = mine


func goto(screen_class: GDScript) -> void:
	_ensure_background()
	_show(screen_class.new())


# ---------------------------------------------------------------------------
# Practice (offline, same rules + controllers, bots fill every other slot)
# ---------------------------------------------------------------------------
func start_practice(role: String, tutorial: bool) -> void:
	_close_session()
	practice_role = role
	session = NetSession.new()
	session.name = "Session"
	add_child(session)
	session.start_offline(Save.player_uid(), Save.player_name(), Save.data["cosmetic"], role if role in ["runner", "patrol", "random"] else "runner", tutorial)
	session.match_starting.connect(_on_match_starting)
	session.results_received.connect(_on_results)
	session.host_start_match(dev_seed)


# ---------------------------------------------------------------------------
# Online rooms
# ---------------------------------------------------------------------------
## Create a party.  With the service configured: the service creates the
## room atomically and returns its code; the host then opens the Game Center
## match for that code and keeps the room alive with heartbeats.  Without it
## (builds with no service URL) the room is an unverified Game Center room.
func host_room_gamekit() -> void:
	if not await _confirm_party_switch():
		return
	_close_session()
	if Cloud.configured():
		var req := _party_req
		var r: Dictionary = await Cloud.create_room(8)
		if req != _party_req:
			if bool(r.get("ok", false)):
				Cloud.leave_room(String(r["room"]["code"]))
			return
		if not bool(r.get("ok", false)):
			party_error.emit(Cloud.explain(r), String(r.get("error", "")))
			return
		var code := String(r["room"]["code"])
		var t := Social.host_code_room(code)
		_begin_session(NetSession.Mode.HOST, t, code)
		session.require_admission = Cloud.admission_key != null
		session.admission_key = Cloud.admission_key
		session.local_pid = Cloud.profile_id()
		if session.roster[0] != null:
			session.roster[0]["pid"] = session.local_pid
		_start_room_heartbeat(code)
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var code2 := Social.make_code(rng)
	_begin_session(NetSession.Mode.HOST, Social.host_code_room(code2), code2)


## Join a party by code: the service checks the code, room state, capacity,
## version and blocks and hands back an admission credential plus the host's
## Game Center player; we then join that Game Center match and present it.
func join_room_gamekit(code: String) -> void:
	var parsed := Social.parse_code(code)
	if not bool(parsed["ok"]):
		party_error.emit(String(parsed["message"]), "code_format")
		return
	var c := String(parsed["code"])
	if not await _confirm_party_switch():
		return
	_close_session()
	var adm := ""
	var host_gc := ""
	if Cloud.configured():
		var req := _party_req
		var r: Dictionary = await Cloud.join_room(c)
		if req != _party_req:
			if bool(r.get("ok", false)):
				Cloud.leave_room(c)
			return
		if not bool(r.get("ok", false)):
			party_error.emit(Cloud.explain(r), String(r.get("error", "")))
			return
		adm = String(r["admission"])
		host_gc = String(r["host_gc_player"])
	var t := Social.join_code_room(c)
	_begin_session(NetSession.Mode.CLIENT, t, c)
	session.admission = adm
	session.expected_host_uid = host_gc
	session.local_pid = Cloud.profile_id()
	party_code = c


## Invites converge on the same path: once the invited match forms, the host
## announces its room code and we join that code through the service (so an
## invite gets the same checks and credential as typing the code).
func _on_invite_ready(t: GameKitTransport) -> void:
	if match_ctrl != null:
		return
	if not await _confirm_party_switch():
		t.close()
		return
	_close_session()
	_begin_session(NetSession.Mode.CLIENT, t, "")
	session.local_pid = Cloud.profile_id()
	if Cloud.configured():
		session.status_changed.emit("Joining your friend's party…")
		session.hold_hello = true
		session.admission_needed.connect(func(code: String) -> void:
			var r: Dictionary = await Cloud.join_room(code)
			if session == null or not is_instance_valid(session):
				return
			if not bool(r.get("ok", false)):
				_close_session(false)
				goto_title(Cloud.explain(r))
				return
			party_code = code
			session.provide_admission(String(r["admission"]), String(r["host_gc_player"])))


signal party_error(message: String, code: String)
var party_code := ""
var _party_req := 0   # bumped by cancel: a cancelled request's result is dropped


## The player cancelled while the service / Game Center was still working.
func cancel_party_request() -> void:
	_party_req += 1
	Social.stop_matchmaking()
	if session and is_instance_valid(session) and session.mode == NetSession.Mode.CLIENT and session.host_peer < 0:
		_close_session(false)
var _hb_timer: Timer


## Already in a party and about to switch to another: ask first.
func _confirm_party_switch() -> bool:
	if session == null or not is_instance_valid(session) or session.mode == NetSession.Mode.OFFLINE:
		return true
	if screen and screen is Screen:
		var answer := {"v": -1}
		(screen as Screen).dialog("Leave your current party to join this one?", [["Switch", func() -> void: answer["v"] = 1], ["Stay", func() -> void: answer["v"] = 0]])
		while int(answer["v"]) < 0 and is_inside_tree():
			await get_tree().process_frame
		if int(answer["v"]) != 1:
			return false
	if session and is_instance_valid(session) and party_code != "" and Cloud.configured():
		Cloud.leave_room(party_code)
	return true


## Host: keep the service's room record alive and in step with the lobby.
func _start_room_heartbeat(code: String) -> void:
	party_code = code
	if _hb_timer == null:
		_hb_timer = Timer.new()
		_hb_timer.wait_time = 15.0
		add_child(_hb_timer)
		_hb_timer.timeout.connect(_room_heartbeat)
	_hb_timer.start()
	_room_heartbeat()


func _room_heartbeat() -> void:
	if session == null or not is_instance_valid(session) or session.mode != NetSession.Mode.HOST or party_code == "":
		if _hb_timer:
			_hb_timer.stop()
		return
	var st := "open"
	match session.phase:
		TC.Phase.LOADING:
			st = "loading"
		TC.Phase.REVEAL, TC.Phase.COUNTDOWN, TC.Phase.PLAYING:
			st = "in_match"
		TC.Phase.RESULTS, TC.Phase.ENDED:
			st = "results"
	var pids: Array = []
	for e in session.roster:
		if e != null and not bool(e["is_bot"]) and bool(e["connected"]) and String(e.get("pid", "")) != "":
			pids.append(String(e["pid"]))
	var r: Dictionary = await Cloud.room_heartbeat(party_code, st, pids)
	if not bool(r.get("ok", false)) and String(r.get("error", "")) == "bad_transition":
		await Cloud.room_heartbeat(party_code, "", pids)   # keep alive; state catches up next beat


## Desktop/LAN development rooms (debug builds only; not shown on iOS release).
func host_room_enet(port: int = 7787) -> void:
	_close_session()
	var t := EnetTransport.new()
	if t.host(port) != OK:
		goto_title("Could not open a LAN room on port %d." % port)
		return
	_begin_session(NetSession.Mode.HOST, t, "LAN%d" % port)


func join_room_enet(address: String, port: int = 7787) -> void:
	_close_session()
	var t := EnetTransport.new()
	if t.join(address, port) != OK:
		goto_title("Could not reach %s:%d." % [address, port])
		return
	_begin_session(NetSession.Mode.CLIENT, t, "")


func _begin_session(mode: int, t: NetTransport, code: String) -> void:
	session = NetSession.new()
	session.name = "Session"
	add_child(session)
	var pref: String = String(Save.get_setting("role_pref", "any"))
	# (V6) the name other players see: service-approved, else curated
	if mode == NetSession.Mode.HOST:
		session.start_host(t, code, Save.player_uid(), Save.party_name(), Save.data["cosmetic"], pref)
	else:
		session.start_client(t, code, Save.player_uid(), Save.party_name(), Save.data["cosmetic"], pref)
		session.rejoin_key = Save.rejoin_key_for(code)
	session.match_starting.connect(_on_match_starting)
	session.results_received.connect(_on_results)
	session.ended.connect(_on_session_ended)
	session.series_changed.connect(_on_series_changed)
	show_lobby()


func show_lobby() -> void:
	_end_match_scene()
	_ensure_background()
	Sfx.music("menu")
	var l := LobbyScreen.new()
	l.session = session
	_show(l)


func _on_session_ended(reason: String) -> void:
	var msg := ""
	match reason:
		"host_left", "host_timeout", "host_ended":
			msg = "The host left the room, so this round was cancelled (no rewards for an interrupted round)."
		"kicked":
			msg = "You were removed from the room by the host."
		"room_not_found":
			msg = "Couldn't find that room. Check the code and that the host's room is open."
		"version":
			msg = "That party is on a different version of the game. Update the game to join."
		"admission":
			msg = "Couldn't confirm your place in that party. Try joining with the code again."
		"not_allowed":
			msg = "You can't join this party."
		"in_use":
			msg = "That player is already in the party on another device."
		"left":
			msg = ""
		_:
			msg = "Connection ended (%s)." % reason
	if match_ctrl != null and reason != "left":
		# keep rewards withheld: cancelled rounds never pay out
		pass
	_close_session(false)
	goto_title(msg)


func leave_room() -> void:
	if session:
		session.leave()
	_close_session()
	goto_title()


func _close_session(send_leave: bool = true) -> void:
	if party_code != "" and Cloud.configured():
		Cloud.leave_room(party_code)
	party_code = ""
	if _hb_timer:
		_hb_timer.stop()
	if session and is_instance_valid(session):
		if send_leave and session.connected and session.mode != NetSession.Mode.OFFLINE:
			session.leave()
		for c in session.ended.get_connections():
			session.ended.disconnect(c["callable"])
		session.queue_free()
	session = null


# ---------------------------------------------------------------------------
# Match lifecycle
# ---------------------------------------------------------------------------
func _on_match_starting(info: Dictionary) -> void:
	InputOwner.clear()   # (V6) no menu, chat or walk control survives into the round
	_end_match_scene()
	_clear_background()
	if screen and is_instance_valid(screen):
		screen.queue_free()
	screen = null
	var loading := LoadingScreen.new()
	loading.info = info
	loading.session = session
	_show(loading)
	match_ctrl = MatchController.new()
	match_ctrl.name = "Match"
	match_ctrl.setup(session, info, {"quality": int(Save.get_setting("quality", 1)), "reduced_motion": bool(Save.get_setting("reduced_motion", false))})
	match_ctrl.finished.connect(_on_match_finished)
	match_ctrl.quit_requested.connect(_on_match_quit)
	match_ctrl.stage_report = loading.set_stage
	loading.match_ctrl = match_ctrl
	loading.done.connect(func() -> void:
		if screen == loading:
			screen = null
		loading.queue_free())
	if dev_local_bot and session.mode == NetSession.Mode.CLIENT:
		var ap := Autopilot.new(hash(Save.player_uid()))
		match_ctrl.input_source = func(m: MatchController) -> InputCmd: return ap.cmd_for(m)
	# the match prepares itself in short steps under the loading screen
	get_tree().root.add_child(match_ctrl)


func _on_results(results: Dictionary) -> void:
	last_results = results


func _on_match_finished(results: Dictionary) -> void:
	last_results = results
	var practice := session != null and session.mode == NetSession.Mode.OFFLINE
	var reward := Save.apply_results(results, session.local_slot if session else -1, practice, Save.player_uid())
	_dev_record(results, reward)
	if dev_report != "":
		_dev_rounds_done += 1
		if _dev_rounds_done >= dev_rounds:
			get_tree().create_timer(1.0).timeout.connect(func() -> void: get_tree().quit())
		elif session and session.is_host():
			_end_match_scene()
			session.host_return_to_lobby()
			return
		else:
			_end_match_scene()
			show_lobby()
			return
	if session and session.tutorial:
		Save.data["tutorial_done"] = true
		Save.mark()
	_end_match_scene()
	_ensure_background()
	Sfx.music("menu")
	var r := ResultsScreen.new()
	r.results = results
	r.reward = reward
	r.session = session
	_show(r)


## V6: Cancel / Leave party on the loading screen, usable at any point of
## the preparation: practice goes back to the title, an online player
## leaves the party.  The half-prepared round is freed (MatchController
## hands any unfinished background work to App).
func cancel_round() -> void:
	Diag.mark("round_cancelled")
	_on_match_quit()


func _on_match_quit() -> void:
	if session and session.mode == NetSession.Mode.OFFLINE:
		_close_session()
		goto_title()
	else:
		leave_room()


## Everyone back to the party room (host: between rounds, or Play again
## after a series - settings are kept).
func back_to_party() -> void:
	if session == null or not is_instance_valid(session):
		goto_title()
		return
	if session.is_host():
		Diag.mark("rematch")
		session.host_return_to_lobby()
	show_lobby()


## The series' final standings on their own (the host ended it early).
func show_series_final() -> void:
	if session == null or not is_instance_valid(session):
		return
	_ensure_background()
	var r := ResultsScreen.new()
	r.results = {}
	r.reward = {}
	r.session = session
	r.final_only = true
	_show(r)


## Guests in the party room see the final standings when the host ends the
## series (once per series).
func _on_series_changed() -> void:
	if session == null or session.is_host() or match_ctrl != null:
		return
	var v: Dictionary = session.series_view
	var key := "final_shown_" + String(v.get("id", ""))
	if bool(v.get("finished", false)) and bool(v.get("ended_early", false)) and screen is LobbyScreen and not session.has_meta(key):
		session.set_meta(key, true)
		show_series_final()


func rematch() -> void:
	if session == null:
		goto_title()
		return
	if session.mode == NetSession.Mode.OFFLINE:
		var tut := false
		session.tutorial = tut
		session.host_return_to_lobby()
		session.host_start_match()
		return
	back_to_party()


func _end_match_scene() -> void:
	if match_ctrl and is_instance_valid(match_ctrl):
		match_ctrl.release_campus()   # rematches reuse the campus look
		match_ctrl.queue_free()
	match_ctrl = null
	Controls.reset_touch()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		Controls.reset_touch()
		Save.save_now()
