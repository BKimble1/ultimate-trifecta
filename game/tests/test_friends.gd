extends RefCounted
## Friends (FINAL_RELEASE_SWEEP), the game's side, against the TEST DOUBLE
## (src/dev/fake_friends.gd: scripted Game Center friends and a scripted
## game service; the service's real rules are tested by
## service/test/friends.test.mjs).  Desktop headless: no device, no Game
## Center, no deployed service.
##   - the panel's states (checking, asking, denied, restricted, Screen Time,
##     signed out, no Game Center, empty, list) and the honest "Status
##     unavailable" when the service can't confirm anyone (no green dots)
##   - sorting: Online, In a party, In a round, Offline, unknown, then by name
##   - status is polled only while the panel is open; the heartbeat runs every
##     20 s in the foreground, sends a state change within seconds, and stops
##     (and clears its row) in the background
##   - Invite: "Invited ✓" only after the service confirmed it, repeated taps
##     send once, failures say why; from Home a party starts first, and an
##     existing party is never replaced
##   - incoming invites: a toast in the right half (never over the walk
##     stick), never during a round (held until it ends); Accept asks before
##     leaving a party and joins through the same code join; Decline
##   - revoked friend access clears this device and the service's copy
##   - Report / Block from a friend's row
##   - layout at SE, iPhone 14, 6.1", Pro Max, 6.9" and both iPads with long
##     names, each at its own point scale and safe area (touch targets as
##     on the device), the keyboard up included
##   - friend tags: the three actions (Invite, Join with code, Add friend),
##     your tag with Copy, Add friend's answers in a few words, "Requested",
##     incoming requests with Accept / Decline and the badge, in-game
##     friends without Game Center's friends list (status and Invite), Join
##     with code, and the signed-out states
var t

const FakeFriends := preload("res://src/dev/fake_friends.gd")
var ff
var _saved := {}

const DEVICES := [
	["SE", Vector2i(1334, 750)],
	["iPhone 14", Vector2i(2532, 1170)],
	["Pro Max", Vector2i(2778, 1284)],
	["iPad", Vector2i(2048, 1536)],
]
## Layout runs: [name, pixels, point scale, safe area in points (L, T, R, B),
## keyboard height in points (landscape, with the suggestions bar)]
const SHAPES := [
	["SE 667x375", Vector2i(1334, 750), 2.0, Rect2(0, 0, 0, 0), 200.0],
	["iPhone 14 844x390", Vector2i(2532, 1170), 3.0, Rect2(47, 0, 47, 21), 209.0],
	["6.1in 852x393", Vector2i(2556, 1179), 3.0, Rect2(59, 0, 59, 21), 209.0],
	["Pro Max 926x428", Vector2i(2778, 1284), 3.0, Rect2(47, 0, 47, 21), 209.0],
	["6.9in 956x440", Vector2i(2868, 1320), 3.0, Rect2(62, 0, 62, 21), 209.0],
	["iPad 1024x768", Vector2i(2048, 1536), 2.0, Rect2(0, 0, 0, 20), 398.0],
	["iPad 13in 1376x1032", Vector2i(2752, 2064), 2.0, Rect2(0, 0, 0, 20), 420.0],
]


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


## Game time under --fixed-fps 60 (timers advance by frames).
func _secs(s: float) -> void:
	await _frames(int(ceilf(s * 60.0)))


func _begin(size: Vector2i = Vector2i(2532, 1170), access: String = "authorized") -> void:
	var root: Window = t.get_tree().root
	_saved = {"size": root.size, "device": Controls.device, "emulate": Input.emulate_touch_from_mouse,
		"gc": [Social.available, Social.authenticated, Social.multiplayer_restricted, Social.auth_error],
		"data": Save.data.duplicate(true), "had_file": FileAccess.file_exists(Save.PATH),
		"file": FileAccess.get_file_as_string(Save.PATH) if FileAccess.file_exists(Save.PATH) else ""}
	Controls.device = "touch"
	Input.emulate_touch_from_mouse = true
	Save.data["onboarded"] = true
	Save.data["name"] = "Quiet Duck"
	(Save.data["settings"] as Dictionary).erase(Friends.SETTING)
	for n in root.get_children():
		if n is BootCurtain:
			n.free()
	Social.available = true
	Social.authenticated = true
	Social.multiplayer_restricted = false
	Social.auth_error = ""
	ff = FakeFriends.new()
	ff.native.access = access
	ff.native.set_friends([["Ada Lark", "T:_ada"], ["Bo", "T:_bo"], ["Cy Moss", "T:_cy"], ["Di Wren", "T:_di"], ["Eve", "T:_eve"],
		["Abe Fox", "T:_abe"]])
	ff.mutual = {
		"T:_ada": {"name": "Comfy Frog", "status": "online"},
		"T:_abe": {"name": "Busy Badger", "status": "online"},
		"T:_bo": {"name": "Snoozy Gecko", "status": "lobby"},
		"T:_cy": {"name": "Moonlit Koala", "status": "match"},
		"T:_di": {"name": "Sleepy Otter", "status": "offline"},
	}
	ff.install()
	Friends.reset_for_tests()
	root.size = size
	await _frames(2)


func _signin() -> void:
	await Cloud.sign_in()
	await _frames(6)


func _end() -> void:
	for n in t.get_tree().root.find_children("*", "Control", true, false):
		if n is FriendsPanel:
			n.queue_free()
	if App.match_ctrl != null:
		var mc := App.match_ctrl
		App.match_ctrl = null
		if is_instance_valid(mc):
			mc.free()
	if App.session != null and is_instance_valid(App.session):
		App._close_session(false)
	if App.screen and is_instance_valid(App.screen):
		App.screen.queue_free()
	App.screen = null
	App._clear_background()
	App.party_code = ""
	UIKit.emulation = {}
	UIKit.v7_emulated_keyboard_pt = -1.0
	await _frames(2)
	Friends.reset_for_tests()
	Social.reset_for_tests()
	ff.uninstall()
	Friends.reset_for_tests()
	Friends.access = "unknown"
	var root: Window = t.get_tree().root
	root.size = _saved["size"]
	Controls.device = _saved["device"]
	Input.emulate_touch_from_mouse = _saved["emulate"]
	var gc: Array = _saved["gc"]
	Social.available = gc[0]
	Social.authenticated = gc[1]
	Social.multiplayer_restricted = gc[2]
	Social.auth_error = gc[3]
	Save.data = _saved["data"]
	if bool(_saved["had_file"]):
		var f := FileAccess.open(Save.PATH, FileAccess.WRITE)
		f.store_string(String(_saved["file"]))
	elif FileAccess.file_exists(Save.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Save.PATH))
	await _frames(2)


func _home() -> TitleScreen:
	App._ensure_background()
	var s := TitleScreen.new()
	App._show(s)
	await _frames(6)
	return s


func _panel(scr: Control) -> FriendsPanel:
	return FriendsPanel.open(scr)


func _until(cond: Callable, max_frames: int = 600) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await t.get_tree().process_frame
	return cond.call()


func _names(p: FriendsPanel) -> Array:
	return p.rows_in_order().map(func(r: FriendsPanel.Row) -> String: return r.name_l.text)


# ------------------------------------------------------------------ states
func test_states_permission_and_unavailable() -> void:
	# asking the first time: opening Friends is the moment Apple's sheet shows
	await _begin(Vector2i(2532, 1170), "not_determined")
	ff.native.prompt_result = "authorized"
	await _signin()
	var home := await _home()
	t.check(home.friends_btn != null and home.friends_btn.is_visible_in_tree(), "Home has a Friends button")
	t.check(ff.native.calls.count("load") == 0, "nothing asked for friends before Friends was opened")
	home.friends_btn.pressed.emit()
	await _frames(2)
	var p: FriendsPanel = FriendsPanel.open(home)    # (the one the button opened)
	await _until(func() -> bool: return p.state_name() == "list" and Friends.service == "ok")
	t.check(ff.native.calls.has("load"), "opening Friends asked for the friends list")
	t.eq(p.state_name(), "list", "allowed: the list")
	t.eq(ff.uploaded.size(), 6, "the six teamPlayerIDs were shared")
	t.check(ff.uploaded.has("T:_ada") and not ff.uploaded.has("G:ada"), "teamPlayerIDs, never gamePlayerIDs")
	p.close()
	await _frames(3)
	t.check(InputOwner.owners().find("friends") < 0, "closing released input")
	await _end()
	for case in [["denied", "denied", "Settings"], ["restricted", "restricted", "Screen Time"]]:
		await _begin(Vector2i(2532, 1170), String(case[0]))
		await _signin()
		var h := await _home()
		var q := FriendsPanel.open(h)
		await _until(func() -> bool: return q.state_name() == String(case[1]))
		t.eq(q.state_name(), String(case[1]), "%s: its own state" % case[0])
		t.check(q.state_lbl.text.contains(String(case[2])), "%s: says where to change it (%s)" % [case[0], q.state_lbl.text])
		t.check(q.state_lbl.text.contains("Party codes still work"), "%s: party codes still work" % case[0])
		t.eq(q.rows_in_order().size(), 0, "%s: no rows" % case[0])
		t.check(ff.count(HTTPClient.METHOD_DELETE, "/v1/friends") >= 1, "%s: the service's copy is cleared" % case[0])
		q.close()
		await _end()
	# signed out of Game Center, no Game Center, Screen Time multiplayer, no friends
	for case in [["signed_out", "signed"], ["unavailable", "avail"], ["multiplayer_off", "mp"], ["empty", "none"]]:
		await _begin()
		match String(case[1]):
			"signed":
				ff.native.signed = false
			"avail":
				ff.native.avail = false
			"mp":
				ff.native.mp_off = true
			"none":
				ff.native.list = []
		var h2 := await _home()
		var q2 := FriendsPanel.open(h2)
		await _until(func() -> bool: return q2.state_name() == String(case[0]))
		t.eq(q2.state_name(), String(case[0]), "%s: its own state" % case[0])
		t.check(q2.state_lbl.text != "" and q2.state_lbl.is_visible_in_tree(), "%s: explained (%s)" % [case[0], q2.state_lbl.text])
		t.check(q2.play_btn.is_visible_in_tree(), "%s: party codes stay one tap away" % case[0])
		q2.close()
		await _end()


func test_sorting_and_honest_status() -> void:
	await _begin()
	await _signin()
	var home := await _home()
	var p := FriendsPanel.open(home)
	await _until(func() -> bool: return Friends.service == "ok" and p.rows_in_order().size() == 6)
	# online (Busy Badger, Comfy Frog) -> in a party -> in a round -> offline -> unknown
	t.eq(_names(p), ["Busy Badger", "Comfy Frog", "Snoozy Gecko", "Moonlit Koala", "Sleepy Otter", "Eve"], "sorted by status, then by name")
	var rows := p.rows_in_order()
	t.eq(rows.map(func(r: FriendsPanel.Row) -> String: return r.status_l.text.get_slice(" · ", 0)),
		["Online", "Online", "In a party", "In a round", "Offline", "Status unknown"], "status in words")
	t.check((rows[1] as FriendsPanel.Row).status_l.text.contains("Ada Lark"), "the Game Center name beside the verified game name")
	t.eq((rows[0] as FriendsPanel.Row).disc.status, "online", "a dot only for a confirmed status")
	t.eq((rows[5] as FriendsPanel.Row).disc.status, "unknown", "no dot for an unknown friend")
	t.check((rows[0] as FriendsPanel.Row).action_btn.is_visible_in_tree(), "Invite on an online friend")
	t.check(not (rows[4] as FriendsPanel.Row).action_btn.visible, "no Invite for an offline friend")
	t.check(not (rows[5] as FriendsPanel.Row).action_btn.visible, "no Invite for an unknown friend")
	# the service goes away: no stale green dots, "Status unavailable"
	ff.unavailable = true
	await Friends._poll()
	await _frames(2)
	t.eq(Friends.service, "unavailable", "the service answered 503")
	for r in p.rows_in_order():
		t.check((r as FriendsPanel.Row).status_l.text.begins_with("Game Center friend"), "unavailable: %s" % (r as FriendsPanel.Row).status_l.text)
		t.eq((r as FriendsPanel.Row).disc.status, "unavailable", "no dot while status is unavailable")
		t.check(not (r as FriendsPanel.Row).action_btn.visible, "no service Invite without status")
	t.check(p.service_lbl.is_visible_in_tree() and p.service_lbl.text.contains("unavailable"), "one restrained line says so")
	t.eq(_names(p), ["Abe Fox", "Ada Lark", "Bo", "Cy Moss", "Di Wren", "Eve"], "without status: Game Center names, by name")
	# a network failure: the same honesty, its own words
	ff.unavailable = false
	ff.network_down = true
	await Friends._poll()
	await _frames(2)
	t.eq(Friends.service, "network", "no connection")
	t.check(p.service_lbl.text.contains("connection"), "network: %s" % p.service_lbl.text)
	ff.network_down = false
	await Friends._poll()
	await _frames(2)
	t.eq(Friends.service, "ok", "back once the service answers")
	p.close()
	await _end()


# ------------------------------------------------------------------ cadence
func test_polling_only_while_open() -> void:
	await _begin()
	await _signin()
	var home := await _home()
	await _secs(1.0)
	var before: int = ff.count(HTTPClient.METHOD_GET, "/v1/friends/presence")
	t.eq(before, 0, "no status polling before Friends is opened")
	var p := FriendsPanel.open(home)
	await _secs(25.0)
	var open_polls: int = ff.count(HTTPClient.METHOD_GET, "/v1/friends/presence")
	t.check(open_polls >= 3 and open_polls <= 4, "about every 10 s while open (%d in 25 s)" % open_polls)
	p.close()
	await _secs(31.0)
	t.eq(ff.count(HTTPClient.METHOD_GET, "/v1/friends/presence"), open_polls, "nothing while closed")
	# failures back off
	var p2 := FriendsPanel.open(home)
	await _secs(1.0)
	ff.network_down = true
	var at: int = ff.calls.size()
	await _secs(60.0)
	var tries: int = ff.calls.slice(at).filter(func(c: Array) -> bool: return String(c[1]) == "/v1/friends/presence").size()
	t.check(tries <= 4, "backoff while failing (%d tries in 60 s, not 6)" % tries)
	ff.network_down = false
	p2.close()
	await _end()


func test_heartbeat_cadence_state_and_background() -> void:
	await _begin()
	await _signin()     # friend access already given: Friends starts quietly
	var home := await _home()
	await _until(func() -> bool: return Friends.shared)
	t.check(Friends.shared, "the friend set was shared at sign-in (no prompt: access was given before)")
	t.eq(ff.native.calls.count("status") >= 1, true, "checked access without asking")
	var b0: int = ff.count(HTTPClient.METHOD_POST, "/v1/presence")
	await _secs(41.0)
	var b1: int = ff.count(HTTPClient.METHOD_POST, "/v1/presence")
	t.check(b1 - b0 >= 2 and b1 - b0 <= 3, "a heartbeat every 20 s (%d in 41 s)" % (b1 - b0))
	var last: Dictionary = ff.calls.filter(func(c: Array) -> bool: return String(c[1]) == "/v1/presence" and int(c[0]) == HTTPClient.METHOD_POST)[-1][2]
	t.eq(String(last["state"]), "online", "Home: online")
	t.check(not last.has("room"), "no room on Home")
	t.eq(int(last["protocol"]), Protocol.VERSION, "the protocol (version checks)")
	# a party: the change goes out within a few seconds
	await App.host_room_gamekit()
	await _secs(4.0)
	last = ff.calls.filter(func(c: Array) -> bool: return String(c[1]) == "/v1/presence" and int(c[0]) == HTTPClient.METHOD_POST)[-1][2]
	t.eq(String(last["state"]), "lobby", "in a party: lobby")
	t.eq(String(last.get("room", "")), ff.room_code, "with the room (the service checks membership)")
	# a round: "match", and no request ever comes from the simulation (timers only)
	App.match_ctrl = MatchController.new()
	await _secs(4.0)
	last = ff.calls.filter(func(c: Array) -> bool: return String(c[1]) == "/v1/presence" and int(c[0]) == HTTPClient.METHOD_POST)[-1][2]
	t.eq(String(last["state"]), "match", "in a round: match")
	var mc := App.match_ctrl
	App.match_ctrl = null
	mc.free()
	# the background: this launch's row is cleared and heartbeats stop
	Friends._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	t.check(ff.count(HTTPClient.METHOD_DELETE, "/v1/presence") >= 1, "background clears the row")
	var del: Array = ff.calls.filter(func(c: Array) -> bool: return String(c[1]) == "/v1/presence" and int(c[0]) == HTTPClient.METHOD_DELETE)[-1]
	t.eq(String(del[2]["instance"]), Friends.instance, "only this launch's row")
	var paused_at: int = ff.count(HTTPClient.METHOD_POST, "/v1/presence")
	await _secs(45.0)
	t.eq(ff.count(HTTPClient.METHOD_POST, "/v1/presence"), paused_at, "no heartbeat in the background")
	Friends._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await _secs(4.0)
	t.check(ff.count(HTTPClient.METHOD_POST, "/v1/presence") > paused_at, "back in front: heartbeat again")
	# "Show when I'm playing" off: cleared and quiet
	Friends.set_share_status(false)
	var off_at: int = ff.count(HTTPClient.METHOD_POST, "/v1/presence")
	await _secs(25.0)
	t.eq(ff.count(HTTPClient.METHOD_POST, "/v1/presence"), off_at, "sharing off: no heartbeat")
	Friends.set_share_status(true)
	t.check(is_instance_valid(home) or App.screen is LobbyScreen, "(the party room replaced Home)")
	await _end()


# ------------------------------------------------------------------ invites
func test_invite_confirmed_dedup_and_errors() -> void:
	await _begin()
	await _signin()
	await App.host_room_gamekit()
	await _frames(4)
	t.check(App.screen is LobbyScreen, "in the party room")
	var lobby := App.screen as LobbyScreen
	t.check(lobby.invite_btn.is_visible_in_tree(), "the party room's Friends button")
	lobby.invite_btn.pressed.emit()
	await _frames(2)
	var p: FriendsPanel = null
	for c in lobby.get_children():
		if c is FriendsPanel:
			p = c
	t.check(p != null, "it opens the Friends panel")
	await _until(func() -> bool: return Friends.service == "ok" and p.rows_in_order().size() == 6)
	t.check(p.code_lbl.is_visible_in_tree() and p.code_lbl.text.contains(ff.room_code), "the party code stays visible")
	var row: FriendsPanel.Row = p.rows_in_order()[1]     # Comfy Frog (online)
	t.eq(row.name_l.text, "Comfy Frog", "the second online friend")
	row.action_btn.pressed.emit()
	row.action_btn.pressed.emit()     # a repeated tap
	await _frames(1)
	await _until(func() -> bool: return Friends.sent.has("T:_ada"))
	await _frames(2)
	t.eq(ff.count(HTTPClient.METHOD_POST, "/v1/invites"), 1, "two taps, one invite")
	t.check(row.chip.is_visible_in_tree() and row.chip.text == "Invited ✓", "Invited ✓ after the service confirmed it")
	t.check(not row.action_btn.visible, "no second Invite")
	# a failure says why and shows no tick
	ff.invite_error = {"status": 409, "body": {"ok": false, "error": "party_full", "message": "Your party is full."}}
	var r2: FriendsPanel.Row = p.rows_in_order()[0]     # Busy Badger
	r2.action_btn.pressed.emit()
	await _until(func() -> bool: return p._note.visible)
	t.check(p._note.text.contains("full"), "the reason: %s" % p._note.text)
	t.check(not Friends.sent.has("T:_abe") and r2.chip.text != "Invited ✓", "no Invited ✓ without a confirmed send")
	ff.invite_error = {}
	# the existing party is never replaced by inviting
	t.eq(ff.count(HTTPClient.METHOD_POST, "/v1/rooms"), 1, "still the one party")
	p.close()
	await _end()


func test_invite_from_home_starts_a_party_first() -> void:
	await _begin()
	await _signin()
	var home := await _home()
	var p := FriendsPanel.open(home)
	await _until(func() -> bool: return Friends.service == "ok" and p.rows_in_order().size() == 6)
	t.check(p.sub_lbl.text.contains("Create a party"), "Home says what Invite does: %s" % p.sub_lbl.text)
	t.check(p.create_btn.is_visible_in_tree() and not p.code_lbl.is_visible_in_tree(), "Home: Create party, no code yet")
	t.check(not p.gc_btn.is_visible_in_tree(), "no Apple invite screen button")
	t.eq(ff.count(HTTPClient.METHOD_POST, "/v1/rooms"), 0, "no party yet")
	var row: FriendsPanel.Row = p.rows_in_order()[1]
	row.action_btn.pressed.emit()
	await _until(func() -> bool: return Friends.sent.has("T:_ada"), 900)
	t.eq(ff.count(HTTPClient.METHOD_POST, "/v1/rooms"), 1, "a party was started")
	t.check(App.screen is LobbyScreen, "and its party room shown")
	t.eq(ff.count(HTTPClient.METHOD_POST, "/v1/invites"), 1, "then the invite went out for it")
	var reopened := false
	for c in (App.screen as Node).get_children():
		reopened = reopened or c is FriendsPanel
	t.check(reopened, "Friends stays open in the new party room (Invited ✓ shows there)")
	await _end()


## (build 31) Invite > Create party: your own lobby with a code (the game
## service room; no Apple invite screen), and Friends reopens there with the
## code to share and the friends to invite.
func test_create_party_shows_the_code_without_game_center() -> void:
	await _begin()
	await _signin()
	var home := await _home()
	var p := FriendsPanel.open(home)
	await _until(func() -> bool: return Friends.service == "ok")
	p.create_btn.pressed.emit()
	await _until(func() -> bool: return App.screen is LobbyScreen and Friends.in_party(), 900)
	t.eq(ff.count(HTTPClient.METHOD_POST, "/v1/rooms"), 1, "a party was created")
	t.check(not Social.sheet_open(), "no Apple invite screen")
	var np: FriendsPanel = null
	for c in (App.screen as Node).get_children():
		if c is FriendsPanel and not c.is_queued_for_deletion():
			np = c
	t.check(np != null, "Friends reopens in the new lobby")
	if np != null:
		await _secs(0.5)
		t.check(np.code_lbl.is_visible_in_tree() and np.code_lbl.text == App.party_code and App.party_code != "", "its code, big, to share: %s" % np.code_lbl.text)
		t.check(np.copy_btn.is_visible_in_tree() and np.code_share_btn.is_visible_in_tree(), "with Copy and Share")
		t.check(not np.create_btn.is_visible_in_tree(), "no second Create party")
		np.close()
	await _end()


func test_incoming_toast_never_in_a_round_and_accept_flow() -> void:
	await _begin()
	await _signin()
	var home := await _home()
	await _until(func() -> bool: return Friends.shared)
	var iv: Dictionary = ff.add_invite("Snoozy Gecko", "T:_bo")
	Friends.beat_now()
	await _secs(4.0)
	t.eq(Friends.incoming.size(), 1, "the heartbeat delivered the invite")
	t.check(Friends.toast.showing(), "a toast on Home")
	t.check(Friends.toast.title_l.text == "Snoozy Gecko invited you", "who invited you: %s" % Friends.toast.title_l.text)
	var vs: Vector2 = t.get_tree().root.get_visible_rect().size
	var r := Friends.toast.card.get_global_rect()
	t.check(r.position.x >= vs.x * 0.5, "the toast keeps to the right half (%s)" % str(r))
	t.check(Rect2(Vector2.ZERO, vs).encloses(r), "on screen (%s in %s)" % [str(r), str(vs)])
	t.check(minf(Friends.toast.accept_btn.size.y, Friends.toast.decline_btn.size.y) >= UIKit.touch_min() - 0.5, "full touch targets")
	t.eq(Friends.toast.accept_btn.focus_mode, Control.FOCUS_NONE, "it never takes controller focus")
	t.eq(Friends.toast.mouse_filter, Control.MOUSE_FILTER_IGNORE, "only the card itself takes touches")
	t.check(home.friends_btn.get_node("Badge").visible, "the Friends button counts it")
	# a round starts: the toast goes away at once and the invite waits
	App.match_ctrl = MatchController.new()
	await _secs(1.5)
	t.check(not Friends.toast.showing(), "never during a round")
	t.check(not Friends.can_show_invites(), "and it can't be accepted from a round")
	Friends.accept(iv)
	await _frames(3)
	t.eq(ff.count(HTTPClient.METHOD_POST, "/v1/invites/%s/accept" % iv["id"]), 0, "nobody is pulled out of a round")
	var mc := App.match_ctrl
	App.match_ctrl = null
	mc.free()
	await _secs(1.5)
	t.check(Friends.toast.showing(), "shown again once the round is over")
	# Accept with no party: no question, the same code join
	Friends.toast.accept_btn.pressed.emit()
	await _until(func() -> bool: return ff.count(HTTPClient.METHOD_POST, "/v1/rooms/ACDEFG/join") > 0, 900)
	t.eq(ff.count(HTTPClient.METHOD_POST, "/v1/invites/%s/accept" % iv["id"]), 1, "the service re-checked the invite")
	var join: Array = ff.calls.filter(func(c: Array) -> bool: return String(c[1]) == "/v1/rooms/ACDEFG/join")[0]
	t.eq((join[2] as Dictionary).keys().size(), 2, "the typed-code join body (build, protocol)")
	t.eq(int(join[2]["protocol"]), Protocol.VERSION, "with this build's protocol")
	await _until(func() -> bool: return App.screen is OnlineScreen and (App.screen as Screen).has_modal())
	t.check(App.screen is OnlineScreen, "joining shows Play with Friends' progress")
	var texts: Array = []
	for n in (App.screen as Node).find_children("*", "Label", true, false):
		texts.append((n as Label).text)
	t.check(texts.any(func(x: String) -> bool: return x.contains("That party is full")), "the join's own answer is shown (full)")
	await _end()


func test_toast_folds_into_the_badge() -> void:
	await _begin()
	await _signin()
	var home := await _home()
	await _until(func() -> bool: return Friends.shared)
	ff.add_invite("Comfy Frog", "T:_ada")
	Friends.beat_now()
	await _secs(4.0)
	t.check(Friends.toast.showing(), "shown")
	await _secs(16.0)
	t.check(not Friends.toast.showing(), "after about 15 s it folds away")
	t.eq(Friends.incoming.size(), 1, "the invite itself stays")
	t.check(home.friends_btn.get_node("Badge").visible, "counted on the Friends button")
	await _secs(3.0)
	t.check(not Friends.toast.showing(), "and the same invite doesn't pop up again")
	await _end()


func test_accept_in_a_party_asks_first_and_decline() -> void:
	await _begin()
	await _signin()
	await App.host_room_gamekit()
	await _frames(4)
	var lobby := App.screen as LobbyScreen
	var iv: Dictionary = ff.add_invite("Comfy Frog", "T:_ada", 300.0, false, "Host Otter")
	Friends.beat_now()
	await _secs(4.0)
	t.check(Friends.toast.showing(), "the toast in the party room")
	t.eq(Friends.toast.sub_l.text.get_slice(" · ", 0), "to Host Otter's party", "a guest's invite names the host's party, never posing as the host")
	Friends.toast.accept_btn.pressed.emit()
	await _frames(3)
	t.check(lobby.has_modal(), "in a party: asks first")
	var dlg_text := ""
	for n in lobby.find_children("*", "Label", true, false):
		if (n as Label).text.begins_with("Leave"):
			dlg_text = (n as Label).text
	t.check(dlg_text.contains("Comfy Frog"), "names who you'd join: %s" % dlg_text)
	# "Not now": nothing sent, the party stays
	var not_now: Button = null
	for b in lobby.find_children("*", "Button", true, false):
		if (b as Button).text == "Not now":
			not_now = b
	not_now.pressed.emit()
	await _frames(4)
	t.eq(ff.count(HTTPClient.METHOD_POST, "/v1/invites/%s/accept" % iv["id"]), 0, "Not now: nothing accepted")
	t.check(App.screen == lobby and Friends.in_party(), "still in the party")
	t.eq(Friends.incoming.size(), 1, "the invite is still in Friends")
	# Decline from the panel
	var p := FriendsPanel.open(lobby)
	await _frames(3)
	t.check(p.invites_box.is_visible_in_tree(), "the panel lists it")
	var dec: Button = null
	for b in p.invites_box.find_children("*", "Button", true, false):
		if (b as Button).text == "Decline":
			dec = b
	dec.pressed.emit()
	await _frames(4)
	t.eq(ff.count(HTTPClient.METHOD_POST, "/v1/invites/%s/decline" % iv["id"]), 1, "declined on the service")
	t.eq(Friends.incoming.size(), 0, "no invite left")
	t.check(not p.invites_box.visible, "gone from the panel")
	p.close()
	# expiry: an invite whose time is up disappears by itself
	var short: Dictionary = ff.add_invite("Busy Badger", "T:_abe", 1.5)
	Friends.beat_now()
	await _secs(4.0)
	t.check(Friends.incoming.any(func(x: Dictionary) -> bool: return String(x["id"]) == String(short["id"])), "a short-lived invite arrives")
	# (expiry is judged on the service's clock, i.e. real time: let it pass)
	OS.delay_msec(1600)
	await _secs(1.5)
	t.check(Friends.incoming.all(func(x: Dictionary) -> bool: return String(x["id"]) != String(short["id"])), "expired invites go")
	await _end()


func test_revoked_access_clears_friend_data() -> void:
	await _begin()
	await _signin()
	var home := await _home()
	var p := FriendsPanel.open(home)
	await _until(func() -> bool: return Friends.service == "ok" and p.rows_in_order().size() == 6)
	p.close()
	await _frames(2)
	# turned off in Settings while the game was in the background
	Friends._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	ff.native.access = "denied"
	Friends._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await _until(func() -> bool: return Friends.access == "denied")
	await _frames(4)
	t.eq(Friends.friends.size(), 0, "the friends list is gone from this device")
	t.eq(Friends.presence.size(), 0, "and their status")
	t.check(not Friends.shared, "nothing shared any more")
	t.check(ff.count(HTTPClient.METHOD_DELETE, "/v1/friends") >= 1, "the service was told to forget the set")
	var beats: int = ff.count(HTTPClient.METHOD_POST, "/v1/presence")
	await _secs(25.0)
	t.eq(ff.count(HTTPClient.METHOD_POST, "/v1/presence"), beats, "no heartbeat without friend access")
	# a friend removed from Game Center disappears too
	await _end()
	await _begin()
	await _signin()
	var h2 := await _home()
	var q := FriendsPanel.open(h2)
	await _until(func() -> bool: return Friends.service == "ok" and q.rows_in_order().size() == 6)
	ff.native.set_friends([["Ada Lark", "T:_ada"]])
	Friends.refresh()
	await _until(func() -> bool: return q.rows_in_order().size() == 1)
	t.eq(_names(q), ["Comfy Frog"], "only the friends Game Center still lists")
	t.eq(ff.uploaded, ["T:_ada"], "and the service's set was replaced")
	t.check(not Friends.presence.has("T:_bo"), "nothing kept for a removed friend")
	q.close()
	await _end()


## Integration: Cloud may move an install between deployments once
## (deployment_changed); Friends starts again there.  (This branch's Cloud
## has no such signal yet: the handler is called as the signal would.)
func test_deployment_move_resyncs() -> void:
	await _begin()
	await _signin()
	var home := await _home()
	var p := FriendsPanel.open(home)
	await _until(func() -> bool: return Friends.service == "ok" and p.rows_in_order().size() == 6)
	ff.add_invite("Comfy Frog", "T:_ada")
	Friends.beat_now()
	await _secs(4.0)
	t.eq(Friends.incoming.size(), 1, "an invite from the first deployment")
	var puts: int = ff.count(HTTPClient.METHOD_PUT, "/v1/friends")
	var beats: int = ff.count(HTTPClient.METHOD_POST, "/v1/presence")
	ff.incoming = []
	Friends._on_deployment_changed("production", "sandbox")
	t.eq(Friends.incoming.size(), 0, "its invites are dropped")
	t.eq(Friends.friends.size(), 6, "Game Center's list is kept")
	await _secs(5.0)
	t.check(ff.count(HTTPClient.METHOD_PUT, "/v1/friends") > puts, "the friend set is uploaded again")
	t.check(ff.count(HTTPClient.METHOD_POST, "/v1/presence") > beats, "heartbeats go to the new deployment")
	t.eq(Friends.service, "ok", "and the open panel shows status again")
	p.close()
	await _end()


func test_report_and_block_from_a_friend_row() -> void:
	await _begin()
	await _signin()
	var home := await _home()
	var p := FriendsPanel.open(home)
	await _until(func() -> bool: return Friends.service == "ok" and p.rows_in_order().size() == 6)
	var row: FriendsPanel.Row = p.rows_in_order()[2]    # Snoozy Gecko (verified profile)
	row.card.pressed.emit()
	await _frames(2)
	row = p.rows_in_order()[2]
	var labels: Array = row.actions.get_children().filter(func(c: Node) -> bool: return c is Button).map(func(b: Button) -> String: return b.text)
	t.check(labels.has("Report…") and labels.has("Block…"), "Report and Block where a verified profile is shown (%s)" % str(labels))
	var unknown: FriendsPanel.Row = p.rows_in_order()[5]   # Eve: not matched by the service
	unknown.card.pressed.emit()
	await _frames(2)
	unknown = p.rows_in_order()[5]
	labels = unknown.actions.get_children().filter(func(c: Node) -> bool: return c is Button).map(func(b: Button) -> String: return b.text)
	t.check(not labels.has("Report…"), "no Report without a verified profile")
	await _end()


# ------------------------------------------------------------------ layout
## (tools/check_v7_screens.sh-style runs pass --v7-size=WxH with the
## device's --emulate-phone / --emulate-safe: then only that size)
func _devices() -> Array:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--v7-size="):
			var p := a.get_slice("=", 1).split("x")
			return [["emulated " + a.get_slice("=", 1), Vector2i(int(p[0]), int(p[1]))]]
	return DEVICES


func test_layout_four_devices_long_names() -> void:
	for d in _devices():
		await _begin(d[1])
		ff.native.set_friends([["Bartholomew Quillfeather-Fan", "T:_long1"], ["Ada Lark", "T:_ada"], ["ÉmilieTheGreatest", "T:_long2"]])
		ff.mutual = {"T:_long1": {"name": "Wobbly Hedgehog", "status": "online"}, "T:_ada": {"name": "Comfy Frog", "status": "match"}}
		await _signin()
		await App.host_room_gamekit()
		await _frames(6)
		var lobby := App.screen as LobbyScreen
		var tag := String(d[0])
		var vs: Vector2 = t.get_tree().root.get_visible_rect().size
		var safe: Rect2 = UIKit.content_rect(t.get_tree().root.get_viewport())
		var fb := lobby.invite_btn.get_global_rect()
		t.check(safe.grow(0.5).encloses(fb), "%s: the party room's Friends button inside the safe area (%s)" % [tag, str(fb)])
		t.check(minf(fb.size.x, fb.size.y) >= UIKit.touch_min() - 0.5, "%s: a full touch target" % tag)
		var p := FriendsPanel.open(lobby)
		await _until(func() -> bool: return Friends.service == "ok" and p.rows_in_order().size() == 3)
		await _frames(3)
		var pr := p.panel.get_global_rect()
		var sm: Rect2 = UIKit.safe_margins(t.get_tree().root.get_viewport())
		t.check(pr.position.x >= sm.position.x - 0.5 and pr.end.x <= vs.x - sm.size.x + 0.5, "%s: the panel inside the safe area (%s)" % [tag, str(pr)])
		t.check(pr.position.y >= sm.position.y - 0.5 and pr.end.y <= vs.y - sm.size.y + 0.5, "%s: and clear of the home indicator" % tag)
		for row in p.rows_in_order():
			var rr: Rect2 = (row as FriendsPanel.Row).card.get_global_rect()
			t.check(pr.grow(0.5).encloses(rr), "%s: row inside the panel (%s)" % [tag, (row as FriendsPanel.Row).name_l.text])
			var ab: Button = (row as FriendsPanel.Row).action_btn
			if ab.visible:
				t.check(pr.grow(0.5).encloses(ab.get_global_rect()), "%s: Invite inside the panel" % tag)
				t.check(minf(ab.size.x, ab.size.y) >= UIKit.touch_min() - 0.5, "%s: Invite a full touch target" % tag)
				t.check(UIKit.v7_button_text_fits(ab), "%s: Invite not trimmed" % tag)
		for b in [p.close_btn, p.copy_btn, p.gc_btn]:
			if (b as Button).is_visible_in_tree():
				t.check(pr.grow(0.5).encloses((b as Button).get_global_rect()), "%s: %s inside the panel" % [tag, (b as Button).text])
				t.check(minf((b as Button).size.x, (b as Button).size.y) >= UIKit.touch_min() - 0.5, "%s: '%s' a full touch target" % [tag, (b as Button).text])
		var first: FriendsPanel.Row = p.rows_in_order()[0]
		t.eq(first.name_l.text, "Wobbly Hedgehog", "%s: the verified game name first" % tag)
		t.check(first.status_l.text.contains("Quillfeath"), "%s: with the Game Center name" % tag)
		p.close()
		await _frames(2)
		# the toast in the party room at this size
		var iv: Dictionary = ff.add_invite("Wobbly Hedgehog", "T:_long1")
		Friends.beat_now()
		await _secs(4.0)
		t.check(Friends.toast.showing(), "%s: toast shown" % tag)
		var tr := Friends.toast.card.get_global_rect()
		t.check(tr.position.x >= vs.x * 0.5 - 0.5 and tr.end.x <= vs.x - sm.size.x + 0.5, "%s: toast in the right half, inside the safe area (%s)" % [tag, str(tr)])
		t.check(not tr.intersects(lobby.bottom_bar.get_global_rect()), "%s: clear of the bottom row" % tag)
		t.check(tr.size.y <= vs.y * 0.4, "%s: a small card (%.0f of %.0f tall)" % [tag, tr.size.y, vs.y])
		t.check(Friends.toast.title_l.text.begins_with("Wobbly Hedgehog"), "%s: %s" % [tag, String(iv["id"])])
		await _end()


# ------------------------------------------------------------------ friend tags
func _tab(p: FriendsPanel, k: String) -> void:
	(p.tab_btns[k] as Button).pressed.emit()
	await _frames(2)


func _press(_p: FriendsPanel, b: Button) -> void:
	b.pressed.emit()
	await _until(func() -> bool: return not Friends.adding and Friends.answering.is_empty())
	await _frames(2)


func _buttons(n: Node, text: String) -> Array:
	return n.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == text and b.is_visible_in_tree())


## A label's one line is drawn whole (nothing trimmed).
func _fits(l: Label) -> bool:
	var f: Font = l.get_theme_font("font")
	var fs: int = l.get_theme_font_size("font_size")
	return f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= l.size.x + 0.5


func _request_cards(p: FriendsPanel) -> Array:
	return p.invites_box.get_children().filter(func(c: Node) -> bool: return String(c.name).begins_with("Request") and not c.is_queued_for_deletion())


func test_three_actions_your_tag_and_add_friend() -> void:
	await _begin()
	await _signin()
	var home := await _home()
	var p := FriendsPanel.open(home)
	await _until(func() -> bool: return Friends.service == "ok" and Friends.tags == "ok")
	await _frames(2)
	for k in ["invite", "join", "add"]:
		t.check((p.tab_btns[k] as Button).is_visible_in_tree(), "%s: one of the three actions at the top" % k)
	t.eq(p.tab, "invite", "Invite is first")
	t.check(p.invite_tab.visible and not p.join_tab.visible and not p.add_tab.visible, "only Invite's part shows")
	await _tab(p, "add")
	t.check(p.add_tab.is_visible_in_tree() and not p.invite_tab.visible, "Add friend shows its part")
	t.eq(p.tag_lbl.text, "QuietDuck#0007", "your tag")
	t.check(p.tag_copy_btn.is_visible_in_tree(), "with Copy")
	p.tag_copy_btn.pressed.emit()
	await _frames(1)
	t.check(p.add_msg.text.contains("copied"), "Copy says so: %s" % p.add_msg.text)
	ff.add_player("Comfy Frog", "ComfyFrog#4821", "T:_cf")
	ff.add_tag_friend("Busy Badger", "BusyBadger#0042", "T:_bb")
	# the answers, in a few words
	for c in [["", "Type your friend's tag"], ["ComfyFrog", "Add the #"], ["Comfy-Frog#12", "isn't a tag"], ["quietduck#0007", "your own tag"],
			["Nobody#1234", "No player with that tag"], ["BusyBadger#0042", "Already friends"]]:
		p.tag_edit.text = String(c[0])
		await _press(p, p.add_btn)
		t.check(p.add_msg.text.contains(String(c[1])), "'%s': %s" % [c[0], p.add_msg.text])
		t.check(p.add_msg.text.length() <= 60, "short (%d)" % p.add_msg.text.length())
	t.eq(ff.count(HTTPClient.METHOD_POST, "/v1/friends/requests"), 2, "typing mistakes never reach the service (only the two real tags)")
	# a real tag, any spelling; a second tap while it is going out does nothing
	p.tag_edit.text = "@comfyfrog#4821"
	Friends.adding = true
	p.add_btn.pressed.emit()
	await _frames(1)
	t.eq(ff.count(HTTPClient.METHOD_POST, "/v1/friends/requests"), 2, "a tap while one is in flight sends nothing")
	Friends.adding = false
	p.add_btn.pressed.emit()
	await _until(func() -> bool: return not Friends.adding)
	await _frames(2)
	t.eq(ff.count(HTTPClient.METHOD_POST, "/v1/friends/requests"), 3, "one request")
	t.check(p.add_msg.text.contains("Request sent to Comfy Frog"), p.add_msg.text)
	t.eq(p.tag_edit.text, "", "the field is cleared")
	p.tag_edit.text = "ComfyFrog#4821"
	await _press(p, p.add_btn)
	t.eq(Friends.requests_out.size(), 1, "asking again: still one request")
	var req: Array = p.sent_box.find_children("Requested", "Label", true, false)
	t.check(req.size() == 1 and (req[0] as Label).is_visible_in_tree(), "Sent: Requested")
	# the service is unreachable: says so
	ff.network_down = true
	p.tag_edit.text = "SomeOne#1111"
	await _press(p, p.add_btn)
	t.check(p.add_msg.text.contains("Can't reach"), p.add_msg.text)
	ff.network_down = false
	p.close()
	await _end()


func test_requests_badge_accept_and_decline() -> void:
	await _begin()
	await _signin()
	var home := await _home()
	await _until(func() -> bool: return Friends.shared and Friends.tags == "ok")
	ff.add_request("Comfy Frog", "ComfyFrog#4821", "T:_cf")
	ff.add_request("Sleepy Panda", "SleepyPanda#0101", "T:_sp", "offline")
	Friends.beat_now()
	await _secs(4.0)
	t.eq(Friends.badge_count(), 2, "the heartbeat counts requests waiting")
	var badge: Control = home.friends_btn.get_node("Badge")
	t.check(badge.visible, "a badge on the Friends button")
	t.check(home.friends_btn.accessibility_name.contains("2 waiting"), home.friends_btn.accessibility_name)
	var p := FriendsPanel.open(home)
	await _until(func() -> bool: return Friends.requests_in.size() == 2 and not _request_cards(p).is_empty())
	await _frames(2)
	var cards := _request_cards(p)
	t.check(cards.size() >= 1 and p.invites_box.is_visible_in_tree(), "requests at the top")
	var texts: Array = (cards[0] as Node).find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	t.check(texts.has("Comfy Frog wants to be friends") and texts.has("ComfyFrog#4821"), "who, and their tag: %s" % str(texts))
	await _press(p, _buttons(cards[0], "Accept")[0])
	await _until(func() -> bool: return Friends.requests_in.size() == 1 and _names(p).has("Comfy Frog"))
	t.eq(Friends.badge_count(), 1, "one left")
	t.check(_names(p).has("Comfy Frog"), "the new friend is on the list: %s" % str(_names(p)))
	var row: FriendsPanel.Row = null
	for r in p.rows_in_order():
		if (r as FriendsPanel.Row).name_l.text == "Comfy Frog":
			row = r
	t.check(row != null and row.status_l.text.begins_with("Online"), "with status, like any friend")
	t.check(row != null and row.action_btn.visible, "and Invite")
	t.check(p._note.text.contains("friends now"), p._note.text)
	await _until(func() -> bool: return not _request_cards(p).is_empty())
	cards = _request_cards(p)
	await _press(p, _buttons(cards[0], "Decline")[0])
	await _until(func() -> bool: return Friends.requests_in.is_empty())
	await _frames(2)
	t.eq(Friends.badge_count(), 0, "nothing waiting")
	t.check(not badge.visible, "the badge goes")
	t.check(not p.invites_box.visible, "and the cards")
	t.check(not _names(p).has("Sleepy Panda"), "declined: not a friend")
	p.close()
	await _end()


func test_in_game_friends_without_game_center_list() -> void:
	# Game Center's friends list is off, but friends added by tag still show,
	# with status and Invite, and this player's status still goes out
	await _begin(Vector2i(2532, 1170), "denied")
	ff.add_tag_friend("Comfy Frog", "ComfyFrog#4821", "T:_cf")
	await _signin()
	var home := await _home()
	var p := FriendsPanel.open(home)
	await _until(func() -> bool: return p.state_name() == "list" and Friends.service == "ok")
	await _frames(2)
	t.eq(_names(p), ["Comfy Frog"], "the in-game friend")
	t.check(p.hint_lbl.is_visible_in_tree() and p.hint_lbl.text.contains("Game Center friends"), "says why Game Center friends are missing: %s" % p.hint_lbl.text)
	t.check(ff.count(HTTPClient.METHOD_DELETE, "/v1/friends") >= 1, "the Game Center set is still cleared")
	var beats: int = ff.count(HTTPClient.METHOD_POST, "/v1/presence")
	await _secs(21.0)
	t.check(ff.count(HTTPClient.METHOD_POST, "/v1/presence") > beats, "heartbeats go: an in-game friend can see you")
	var row: FriendsPanel.Row = p.rows_in_order()[0]
	t.check(row.action_btn.visible, "Invite")
	row.action_btn.pressed.emit()
	await _until(func() -> bool: return Friends.sent.has("T:_cf"), 900)
	var sent: Array = ff.calls.filter(func(c: Array) -> bool: return String(c[1]) == "/v1/invites" and int(c[0]) == HTTPClient.METHOD_POST)
	t.check(sent.size() == 1 and String(sent[0][2]["to"]) == "T:_cf", "the invite goes to the friend's verified ID")
	# Remove (in-game friends only)
	for c in (App.screen as Node).get_children():
		if c is FriendsPanel:
			p = c
	await _until(func() -> bool: return p.rows_in_order().size() == 1)
	row = p.rows_in_order()[0]
	row.card.pressed.emit()
	await _frames(2)
	row = p.rows_in_order()[0]
	var rm: Array = _buttons(row.actions, "Remove…")
	t.check(rm.size() == 1, "Remove… on an in-game friend")
	if rm.size() == 1:
		(rm[0] as Button).pressed.emit()
		await _frames(2)
		var yes: Array = _buttons(row.actions, "Remove")
		t.check(yes.size() == 1, "asks first")
		if yes.size() == 1:
			(yes[0] as Button).pressed.emit()
			await _until(func() -> bool: return ff.tag_friends.is_empty())
	t.eq(ff.count(HTTPClient.METHOD_DELETE, "/v1/friends/p_cf"), 1, "removed on the service")
	await _end()


func test_join_with_code_from_friends() -> void:
	await _begin()
	await _signin()
	var home := await _home()
	var p := FriendsPanel.open(home)
	await _frames(3)
	await _tab(p, "join")
	t.check(p.code_edit.is_visible_in_tree() and p.join_btn.is_visible_in_tree(), "a code field and Join")
	p.code_edit.text = "AB"
	p.join_btn.pressed.emit()
	await _frames(2)
	t.check(p.join_msg.text.contains("6 characters"), "a mistake says what's wrong: %s" % p.join_msg.text)
	t.check(is_instance_valid(p) and p.is_inside_tree(), "and stays open")
	p.code_edit.text = "acd-efg"
	p.join_btn.pressed.emit()
	await _until(func() -> bool: return ff.count(HTTPClient.METHOD_POST, "/v1/rooms/ACDEFG/join") > 0, 900)
	t.eq(ff.count(HTTPClient.METHOD_POST, "/v1/rooms/ACDEFG/join"), 1, "the same join as a typed code")
	t.check(App.screen is OnlineScreen, "with Play with Friends' progress and messages")
	await _until(func() -> bool: return (App.screen as Screen).has_modal())
	var texts: Array = []
	for n in (App.screen as Node).find_children("*", "Label", true, false):
		texts.append((n as Label).text)
	t.check(texts.any(func(x: String) -> bool: return x.contains("That party is full")), "the join's own answer is shown")
	await _end()


func test_signed_out_of_game_center_says_so() -> void:
	await _begin()
	ff.identity_fail = true
	Social.authenticated = false
	var home := await _home()
	var p := FriendsPanel.open(home)
	await _until(func() -> bool: return Friends.tags == "signed_out")
	await _tab(p, "add")
	t.check(p.add_msg.text.contains("Sign in to Game Center"), "Add friend: %s" % p.add_msg.text)
	t.check(p.add_btn.disabled and not p.tag_edit.editable, "nothing to type into yet")
	t.check(not p.tag_copy_btn.visible, "no tag to copy")
	await _tab(p, "join")
	t.check(p.join_msg.text.contains("Sign in to Game Center"), "Join with code: %s" % p.join_msg.text)
	p.code_edit.text = "ACDEFG"
	p.join_btn.pressed.emit()
	await _frames(2)
	t.check(is_instance_valid(p) and p.is_inside_tree() and p.join_msg.text.contains("Sign in"), "Join explains instead of failing")
	# the service is unavailable: no crash, Add friend says why
	Social.authenticated = true
	ff.identity_fail = false
	ff.unavailable = true
	Friends.tags = "idle"
	await Friends.load_tags()
	t.check(Friends.tags in ["unavailable", "off"], "tags: %s" % Friends.tags)
	await _tab(p, "add")
	t.check(p.add_msg.text != "", "Add friend says why: %s" % p.add_msg.text)
	p.close()
	await _end()


## Every shape, at its own point scale and safe area: the three actions, the
## waiting cards, the tag, the fields, the keyboard.
func test_layout_devices_tags_and_keyboard() -> void:
	for d in SHAPES:
		var tag := String(d[0])
		UIKit.emulation = {"scale": float(d[2]), "safe": d[3]}
		await _begin(d[1])
		ff.native.set_friends([["Bartholomew Quillfeather-Fan", "T:_long1"], ["Ada Lark", "T:_ada"]])
		ff.mutual = {"T:_long1": {"name": "Wobbly Hedgehog", "status": "online"}, "T:_ada": {"name": "Comfy Frog", "status": "match"}}
		ff.add_tag_friend("Snoozy Gecko", "SnoozyGecko#0101", "T:_sg")
		ff.add_request("Bartholomew Q", "BartholomewQ#9999", "T:_bq")
		ff.add_request("Moonlit Koala", "MoonlitKoala#0420", "T:_mk")
		ff.my_tag = "WobblyHedgehog#4821"
		await _signin()
		await App.host_room_gamekit()
		await _frames(6)
		var lobby := App.screen as LobbyScreen
		var p := FriendsPanel.open(lobby)
		await _until(func() -> bool: return Friends.service == "ok" and Friends.tags == "ok" and p.rows_in_order().size() == 3)
		await _frames(4)
		var vs: Vector2 = t.get_tree().root.get_visible_rect().size
		var sm: Rect2 = UIKit.safe_margins(t.get_tree().root.get_viewport())
		var pr := p.panel.get_global_rect()
		var tm := UIKit.touch_min()
		t.check(pr.position.x >= sm.position.x - 0.5 and pr.end.x <= vs.x - sm.size.x + 0.5 and pr.end.y <= vs.y - sm.size.y + 0.5,
			"%s: the panel inside the safe area (%s)" % [tag, str(pr)])
		for k in ["invite", "join", "add"]:
			var b: Button = p.tab_btns[k]
			t.check(pr.grow(0.5).encloses(b.get_global_rect()), "%s: %s inside the panel" % [tag, k])
			t.check(minf(b.size.x, b.size.y) >= tm - 0.5, "%s: %s a full touch target (%s, %.0f)" % [tag, k, str(b.size), tm])
			var cap: Label = b.find_children("Caption", "Label", true, false)[0]
			t.check(_fits(cap) and b.get_global_rect().grow(0.5).encloses(cap.get_global_rect()), "%s: '%s' whole on its button" % [tag, cap.text])
		# a waiting card at the top: inside, its buttons full size and whole
		var cards: Array = p.invites_box.get_children().filter(func(c: Node) -> bool: return not c.is_queued_for_deletion())
		t.check(cards.size() >= 1, "%s: a request card" % tag)
		for c in cards:
			t.check(pr.grow(0.5).encloses((c as Control).get_global_rect()), "%s: card inside the panel" % tag)
			for b in (c as Node).find_children("*", "Button", true, false):
				t.check(pr.grow(0.5).encloses((b as Button).get_global_rect()), "%s: '%s' inside" % [tag, (b as Button).text])
				t.check(UIKit.v7_button_text_fits(b), "%s: '%s' not trimmed" % [tag, (b as Button).text])
				t.check((b as Button).size.y >= tm - 0.5, "%s: '%s' tall enough" % [tag, (b as Button).text])
		t.check(p.more_lbl.visible == (Friends.requests_in.size() > p.max_cards()), "%s: the rest are counted" % tag)
		# the list keeps room for at least one friend under the cards
		t.check(p.scroll.size.y >= tm, "%s: the list keeps its room (%.0f)" % [tag, p.scroll.size.y])
		var sr := p.scroll.get_global_rect()
		t.check(pr.grow(0.5).encloses(sr), "%s: the list inside the panel" % tag)
		for row in p.rows_in_order():
			var rr: Rect2 = (row as FriendsPanel.Row).card.get_global_rect()
			# (rows below the list's edge scroll into view: only their width is checked)
			t.check(rr.position.x >= pr.position.x - 0.5 and rr.end.x <= pr.end.x + 0.5, "%s: row inside the panel" % tag)
			var ab: Button = (row as FriendsPanel.Row).action_btn
			if ab.visible:
				t.check(UIKit.v7_button_text_fits(ab), "%s: Invite not trimmed" % tag)
				t.check(rr.grow(0.5).encloses(ab.get_global_rect()), "%s: Invite on its row" % tag)
		for b in [p.close_btn, p.copy_btn]:
			t.check(pr.grow(0.5).encloses((b as Button).get_global_rect()), "%s: %s inside" % [tag, (b as Button).text])
		# Add friend: the tag line and the field
		await _tab(p, "add")
		await _frames(2)
		for c in [p.tag_lbl, p.tag_copy_btn, p.tag_edit, p.add_btn, p.add_msg]:
			t.check(pr.grow(0.5).encloses((c as Control).get_global_rect()), "%s: %s inside the panel" % [tag, (c as Control).get_class()])
		t.check(_fits(p.tag_lbl), "%s: the tag whole (%s)" % [tag, p.tag_lbl.text])
		t.check(UIKit.v7_button_text_fits(p.add_btn) and UIKit.v7_button_text_fits(p.tag_copy_btn), "%s: Add / Copy not trimmed" % tag)
		t.check(not p.tag_lbl.get_global_rect().intersects(p.tag_copy_btn.get_global_rect()), "%s: the tag clear of Copy" % tag)
		t.check(not p.tag_edit.get_global_rect().intersects(p.add_btn.get_global_rect()), "%s: the field clear of Add" % tag)
		# the keyboard comes up over the field: it stays above, folding only what it must
		UIKit.v7_emulated_keyboard_pt = float(d[4])
		p.tag_edit.grab_focus()
		await _frames(12)
		var kr: Dictionary = p.keyboard_report()
		var limit: float = vs.y - float(kr["keyboard"])
		t.check(bool(kr["typing"]), "%s: typing" % tag)
		t.check((kr["field"] as Rect2).end.y <= limit + 0.5 and (kr["button"] as Rect2).end.y <= limit + 0.5,
			"%s: field and Add above the keyboard (%.0f, %.0f / %.0f)" % [tag, (kr["field"] as Rect2).end.y, (kr["button"] as Rect2).end.y, limit])
		t.check(p.close_btn.is_visible_in_tree(), "%s: Close stays" % tag)
		await _tab(p, "join")
		p.code_edit.grab_focus()
		await _frames(12)
		kr = p.keyboard_report()
		t.check((kr["field"] as Rect2).end.y <= limit + 0.5 and (kr["button"] as Rect2).end.y <= limit + 0.5,
			"%s: code field and Join above the keyboard" % tag)
		p.code_edit.release_focus()
		UIKit.v7_emulated_keyboard_pt = 0.0
		await _frames(8)
		t.check(p.tiles.visible and p._fold == 0, "%s: everything back when the keyboard goes" % tag)
		p.close()
		await _end()
