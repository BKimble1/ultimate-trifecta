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
var _bg: Node3D
# dev/automation flags (ignored in normal play)
var dev_local_bot := false
var dev_shots_dir := ""
var dev_quit_after := 0.0
var dev_seed := -1
var _dev_t := 0.0
var _dev_shot_i := 0
var _dev_next_shot := 2.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().set_auto_accept_quit(true)
	if OS.has_feature("mobile"):
		Engine.max_fps = 60
	Social.invite_ready.connect(_on_invite_ready)
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
	if OS.get_cmdline_user_args().has("--no-app"):
		return
	call_deferred("_boot")


func _process(delta: float) -> void:
	if dev_quit_after <= 0.0 and dev_shots_dir == "":
		return
	_dev_t += delta
	if dev_shots_dir != "" and _dev_t >= _dev_next_shot:
		_dev_next_shot += 4.0
		var img := get_viewport().get_texture().get_image()
		img.save_png(dev_shots_dir.path_join("shot_%03d.png" % _dev_shot_i))
		_dev_shot_i += 1
	if dev_quit_after > 0.0 and _dev_t >= dev_quit_after:
		get_tree().quit()


func _boot() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--autoplay="):
			# dev/automation hook: jump straight into practice as a role
			practice_role = a.split("=")[1]
			start_practice(practice_role, false)
			return
	goto_title()


# ---------------------------------------------------------------------------
# Screens
# ---------------------------------------------------------------------------
func _show(node: Control) -> void:
	if screen and is_instance_valid(screen):
		screen.queue_free()
	screen = node
	_ui_layer.add_child(node)


func _ensure_background() -> void:
	if _bg and is_instance_valid(_bg):
		return
	_bg = MenuBackground.new()
	get_tree().root.add_child.call_deferred(_bg)


func _clear_background() -> void:
	if _bg and is_instance_valid(_bg):
		_bg.queue_free()
	_bg = null


func goto_title(message: String = "") -> void:
	_end_match_scene()
	_ensure_background()
	Sfx.music("menu")
	var t := TitleScreen.new()
	_show(t)
	if message != "":
		t.show_message(message)
	elif _pending_message != "":
		t.show_message(_pending_message)
		_pending_message = ""


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
	session.start_offline(Save.player_uid(), Save.player_name(), Save.data["cosmetic"], "patrol" if role == "patrol" else "runner", tutorial)
	session.match_starting.connect(_on_match_starting)
	session.results_received.connect(_on_results)
	session.host_start_match(dev_seed)


# ---------------------------------------------------------------------------
# Online rooms
# ---------------------------------------------------------------------------
func host_room_gamekit() -> void:
	_close_session()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var code := Social.make_code(rng)
	var t := Social.host_code_room(code)
	_begin_session(NetSession.Mode.HOST, t, code)


func join_room_gamekit(code: String) -> void:
	_close_session()
	var c := Social.normalize_code(code)
	var t := Social.join_code_room(c)
	_begin_session(NetSession.Mode.CLIENT, t, c)


func _on_invite_ready(t: GameKitTransport) -> void:
	# a friend's invite was accepted: join their room
	if match_ctrl != null:
		return
	_close_session()
	_begin_session(NetSession.Mode.CLIENT, t, "")


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
	if mode == NetSession.Mode.HOST:
		session.start_host(t, code, Save.player_uid(), Save.player_name(), Save.data["cosmetic"], pref)
	else:
		session.start_client(t, code, Save.player_uid(), Save.player_name(), Save.data["cosmetic"], pref)
	session.match_starting.connect(_on_match_starting)
	session.results_received.connect(_on_results)
	session.ended.connect(_on_session_ended)
	show_lobby()


func show_lobby() -> void:
	_end_match_scene()
	_clear_background()
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
			msg = "That room is running a different version of the game."
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
	_end_match_scene()
	_clear_background()
	if screen and is_instance_valid(screen):
		screen.queue_free()
	screen = null
	var loading := LoadingScreen.new()
	loading.info = info
	_show(loading)
	await get_tree().process_frame
	await get_tree().process_frame
	match_ctrl = MatchController.new()
	match_ctrl.name = "Match"
	match_ctrl.setup(session, info, {"quality": int(Save.get_setting("quality", 1)), "reduced_motion": bool(Save.get_setting("reduced_motion", false))})
	match_ctrl.finished.connect(_on_match_finished)
	match_ctrl.quit_requested.connect(_on_match_quit)
	get_tree().root.add_child(match_ctrl)
	if screen == loading:
		loading.queue_free()
		screen = null


func _on_results(results: Dictionary) -> void:
	last_results = results


func _on_match_finished(results: Dictionary) -> void:
	last_results = results
	var practice := session != null and session.mode == NetSession.Mode.OFFLINE
	var reward := Save.apply_results(results, session.local_slot if session else -1, practice)
	if session and session.tutorial:
		Save.data["tutorial_done"] = true
		Save.mark()
	_end_match_scene()
	var r := ResultsScreen.new()
	r.results = results
	r.reward = reward
	r.session = session
	_show(r)


func _on_match_quit() -> void:
	if session and session.mode == NetSession.Mode.OFFLINE:
		_close_session()
		goto_title()
	else:
		leave_room()


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
	if session.is_host():
		session.host_return_to_lobby()
	show_lobby()


func _end_match_scene() -> void:
	if match_ctrl and is_instance_valid(match_ctrl):
		match_ctrl.queue_free()
	match_ctrl = null
	Controls.reset_touch()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		Controls.reset_touch()
		Save.save_now()
