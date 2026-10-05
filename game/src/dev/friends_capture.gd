extends Node
## Development-only evidence for Friends (FINAL_RELEASE_SWEEP; src/dev:
## never exported).  Renders the real screens at a device shape and stamps
## every picture "desktop render · test-double service": the Game Center
## side and the game service are the TEST DOUBLE in src/dev/fake_friends.gd
## (fictional players), never a device, Game Center or a deployment.
##
##   --mode=after (default)  the Friends entry points, the panel in each
##                           state, invites and the toast
##   --mode=before           the same entry points as they were at the
##                           baseline (run from a checkout of that commit;
##                           only classes that existed then are used)
##
##   tools/capture_friends.sh OUT_DIR [se p14 pmax ipad]

const STAMP := "desktop render · test-double service (fictional players; not Game Center or a live service)"
const STAMP_BEFORE := "BEFORE (baseline) · desktop render (fictional names)"

var out_dir := ""
var mode := "after"
var only := ""
var ff
var F: Node     # the Friends autoload (looked up: the baseline has none)
var _tag: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture-dir="):
			out_dir = a.get_slice("=", 1)
		elif a.begins_with("--mode="):
			mode = a.get_slice("=", 1)
		elif a.begins_with("--only="):
			only = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	_tag = Label.new()
	_tag.add_theme_font_size_override("font_size", 15)
	_tag.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_tag.add_theme_constant_override("outline_size", 4)
	_tag.position = Vector2(8, 0)
	layer.add_child(_tag)
	_run.call_deferred()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _label(t: String) -> void:
	_tag.text = t
	_tag.position.y = get_viewport().get_visible_rect().size.y - 22.0


func snap(shot: String, what: String) -> void:
	if only != "" and not shot.begins_with(only):
		return
	_label("%s · %s" % [STAMP_BEFORE if mode == "before" else STAMP, what])
	await _wait(0.6)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(shot + ".png"))
	printerr("CAPTURE %s %dx%d %s" % [shot, img.get_width(), img.get_height(), what])


func _profile() -> void:
	Save.data = Save.migrate({"version": 4, "uid": "local-capture", "name": "Quiet Duck", "coins": 0, "level": 7, "xp": 40,
		"owned": [], "onboarded": true, "tutorial_done": true,
		"cosmetic": {"schema": 2, "outfit": "pj", "hat": "nightcap", "shoes": "slippers", "color": "sky", "hair": "tuft", "skin": "tone4"},
		"settings": {}})
	Save.data["onboarded"] = true
	Social.available = true
	Social.authenticated = true
	Social.multiplayer_restricted = false
	Social.display_name = "Player"


func _run() -> void:
	_profile()
	for n in get_tree().root.get_children():
		if n is BootCurtain:
			n.free()
	if mode == "before":
		await _before()
	else:
		await _after()
	printerr("CAPTURE-DONE")
	get_tree().quit()


# ------------------------------------------------------------------ before
func _before() -> void:
	App.goto_title()
	await _wait(2.5)
	await snap("b01_home", "Home: no Friends entry")
	App.goto(OnlineScreen)
	await _wait(1.0)
	await snap("b02_play_with_friends", "Play with Friends: 'Show Game Center friends'")
	var os: Node = App.screen
	if os.has_method("_on_friends"):
		os.get("friends_status").visible = true
		os.get("_friends_hint").visible = false
		os.call("_on_friends", [{"name": "Comfy Frog", "id": "G:1"}, {"name": "Snoozy Gecko", "id": "G:2"}, {"name": "Moonlit Koala", "id": "G:3"}], "")
		await _wait(0.6)
		await snap("b03_play_with_friends_list", "the old friends list: names only, no status, no invite")
	App._begin_session(NetSession.Mode.HOST, GameKitTransport.new(true), "QRTWXY")
	await _wait(2.5)
	await snap("b04_lobby", "party room: Invite opens Apple's sheet (host only)")


# ------------------------------------------------------------------ after
func _friends_fixture() -> void:
	ff = load("res://src/dev/fake_friends.gd").new()
	ff.native.set_friends([["Ada Lark", "T:_ada"], ["Bo Reyes", "T:_bo"], ["Cy Moss", "T:_cy"], ["Di Wren", "T:_di"],
		["Eve Sato", "T:_eve"], ["Abe Fox", "T:_abe"], ["Wolfgang Amadeus Mozart-Fan", "T:_long"], ["Juniper Q", "T:_jun"]])
	ff.mutual = {
		"T:_ada": {"name": "Comfy Frog", "status": "online"},
		"T:_abe": {"name": "Busy Badger", "status": "online"},
		"T:_bo": {"name": "Snoozy Gecko", "status": "lobby"},
		"T:_cy": {"name": "Moonlit Koala", "status": "match"},
		"T:_di": {"name": "Sleepy Otter", "status": "offline"},
		"T:_long": {"name": "Wobbly Hedgehog", "status": "online"},
	}
	ff.install()


func _panel_on(scr: Control) -> Control:
	var P: GDScript = load("res://src/ui/friends_panel.gd")
	return P.call("open", scr)


func _close_panels() -> void:
	# (find_children's type filter only knows engine classes: match the script)
	var script: Script = load("res://src/ui/friends_panel.gd")
	for n in get_tree().root.find_children("*", "Control", true, false):
		if n.get_script() == script and not n.is_queued_for_deletion():
			n.call("close")
	await _wait(0.3)


## A fresh Friends state with this Game Center / service setup.
func _state(access: String, setup: Callable = Callable()) -> void:
	await _close_panels()
	ff.native.access = access
	ff.native.avail = true
	ff.native.signed = true
	ff.native.mp_off = false
	ff.unavailable = false
	ff.network_down = false
	if setup.is_valid():
		setup.call()
	F.call("reset_for_tests")


func _after() -> void:
	F = get_tree().root.get_node("Friends")
	_friends_fixture()
	F.call("reset_for_tests")
	await Cloud.sign_in()
	App.goto_title()
	await _wait(3.0)
	await snap("a01_home", "Home: Friends at the top right")
	var home: Control = App.screen
	# the panel's states, opened from Home
	await _state("authorized")
	_panel_on(home)
	await _wait(1.5)
	await snap("a02_panel_home_list", "Friends from Home: sorted by status; Invite starts a party")
	await _state("authorized", func() -> void: ff.native.load_error = "")
	var p: Control = _panel_on(home)
	var rows: Array = p.call("rows_in_order")
	if rows.size() > 2:
		(rows[2] as Control).get("card").emit_signal("pressed")
	await _wait(0.8)
	await snap("a03_panel_row_actions", "a friend's row: Report and Block (verified profile)")
	await _state("not_determined", func() -> void: ff.native.prompt_result = "not_determined")
	_panel_on(home)
	await _wait(1.0)
	await snap("a04_panel_asking", "asking for friends-list access (Apple's sheet shows over this on iOS)")
	await _state("denied")
	_panel_on(home)
	await _wait(1.0)
	await snap("a05_panel_denied", "friends-list access off")
	await _state("restricted")
	_panel_on(home)
	await _wait(1.0)
	await snap("a06_panel_restricted", "friends list restricted (Screen Time)")
	await _state("authorized", func() -> void: ff.native.signed = false)
	_panel_on(home)
	await _wait(1.0)
	await snap("a07_panel_signed_out", "Game Center signed out")
	await _state("authorized", func() -> void: ff.native.mp_off = true)
	_panel_on(home)
	await _wait(1.0)
	await snap("a08_panel_screen_time", "multiplayer off (Screen Time)")
	await _state("authorized", func() -> void: ff.unavailable = true)
	_panel_on(home)
	await _wait(1.2)
	await snap("a09_panel_status_unavailable", "service unavailable: 'Status unavailable', no dots")
	await _state("authorized", func() -> void: ff.network_down = true)
	_panel_on(home)
	await _wait(1.2)
	await snap("a10_panel_network", "network failure")
	var keep: Array = ff.native.list
	await _state("authorized", func() -> void: ff.native.list = [])
	_panel_on(home)
	await _wait(1.0)
	await snap("a11_panel_empty", "no Game Center friends")
	await _state("authorized", func() -> void: ff.native.list = keep)
	# loading: the friends list not answered yet
	F.set("access", "checking")
	var lp: Control = _panel_on(home)
	lp.call("_refresh")
	await snap("a12_panel_loading", "loading")
	await _state("authorized")
	ff.native.avail = false
	F.call("reset_for_tests")
	_panel_on(home)
	await _wait(1.0)
	await snap("a13_panel_no_game_center", "no Game Center on this device")
	await _state("authorized")
	# an invite arrives on Home
	F.call("reset_for_tests")
	await F.call("refresh")
	ff.add_invite("Snoozy Gecko", "T:_bo")
	F.call("beat_now")
	await _wait(4.0)
	await snap("a14_toast_home", "an invite arrives: a small card, right half")
	ff.incoming = []
	F.call("beat_now")
	await _wait(4.0)
	# Play with Friends
	App.goto(OnlineScreen)
	await _wait(1.2)
	await snap("a15_play_with_friends", "Play with Friends: the Friends entry")
	# the party room
	await App.host_room_gamekit()
	await _wait(3.0)
	await snap("a16_lobby", "party room: Friends in the top bar")
	ff.mutual["T:_long"] = {"name": "Wobbly Hedgehog", "status": "lobby", "in_your_party": true}
	var lobby: Control = App.screen
	var lp2: Control = _panel_on(lobby)
	await _wait(1.5)
	await F.call("invite", "T:_ada")
	await _wait(1.2)
	lp2.call("_refresh")
	await snap("a17_panel_lobby_invited", "in a party: Invited ✓ after the service confirmed it; party code; Game Center sheet")
	await _close_panels()
	var iv: Dictionary = ff.add_invite("Busy Badger", "T:_abe", 300.0, false, "Host Otter")
	F.call("beat_now")
	await _wait(4.0)
	await snap("a18_toast_lobby", "an invite in the party room (a guest's invite names the host's party)")
	_panel_on(lobby)
	await _wait(1.0)
	await snap("a19_panel_invites", "invites waiting, in the panel")
	await _close_panels()
	F.call("accept", iv)
	await _wait(1.0)
	await snap("a20_accept_confirm", "Accept while in a party: asks first")
