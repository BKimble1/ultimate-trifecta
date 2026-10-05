extends Node
## Friends (FINAL_RELEASE_SWEEP), autoload "Friends": which Game Center
## friends are playing Ultimate Trifecta right now, and party invites.
## Design, API and privacy: docs/final/friends.md; the service side is
## service/src/friends.js.
##
## Identity.  Game Center gives this device the player's authorised friends
## (Social.load_friends: teamPlayerID, gamePlayerID, display name).  The
## game uploads their teamPlayerIDs (PUT /v1/friends); the service keeps
## only keyed hashes and shows a friend's status only when that friend's own
## game uploaded this player too (a mutual claim from two verified
## sessions), with no block either way.  Presence and invites use the
## teamPlayerID only; gamePlayerID and the GKPlayer object are kept for
## Apple's invite sheet.
##
## Presence.  While the game is in the foreground and friend access is on,
## a heartbeat every 20 s (POST /v1/presence) says what this launch is
## actually doing: online in the menus, in a party lobby (with the room
## code; the service checks membership) or in a round.  A change (party
## joined, round started) is sent within a few seconds; nothing runs per
## frame (a 1 s timer compares the state) and no request is ever made from
## the simulation.  Going to the background, signing out, turning "Show when
## I'm playing" off or losing friend access clears this launch's row.
## The heartbeat reply carries invites waiting for this player.
##
## Status polling (GET /v1/friends/presence) runs only while a Friends
## panel is open (watch()), every ~10 s with backoff on failures, and stops
## when it closes or the app goes to the background.  Without a working
## service every row says "Status unavailable": nothing is ever shown as
## online that the service didn't confirm.
##
## Invites.  invite(tid) sends one for the party this player is in (a
## party is started first from Home, where there is none to replace);
## "Invited ✓" only after the service confirmed it.  Incoming invites show
## as a small toast (never during a round: it waits for the results or the
## lobby), and in the Friends panel.  accept() asks before leaving a current
## party, has the service re-check everything, then joins through the same
## path as a typed code (App.join_room_gamekit: service admission and Game
## Center matchmaking for the code).

signal changed
signal invites_changed

const HEARTBEAT_S := 20.0
const POLL_S := 10.0
const STATE_CHECK_S := 1.0
const MIN_BEAT_GAP_S := 3.0
const MAX_BACKOFF_S := 120.0
const MAX_POLL_BACKOFF_S := 60.0
const SYNC_MIN_S := 600.0
const MAX_FRIENDS := 500
const SETTING := "friends_status"

## the Game Center side (Social); tests and labelled captures replace it
## (src/dev/fake_friends.gd)
var native: Object
## unknown | checking | unavailable (no Game Center here) | signed_out |
## multiplayer_off (Screen Time) | not_determined | authorized | denied |
## restricted (friend list, Screen Time) | error
var access := "unknown"
var friends: Array = []          # [{tid, gid, name, player}] from Game Center
var presence: Dictionary = {}    # tid -> the service's entry (mutual friends only)
var party: Variant = null        # the service's view of this player's party
## off (no service in this build) | idle | loading | ok | unavailable |
## network | signed_out | suspended
var service := "idle"
var service_message := ""
var incoming: Array = []         # invites waiting for this player
var sent: Dictionary = {}        # tid -> {id, expires_at}: confirmed by the service
var sending: Dictionary = {}     # tid -> true while a send is in flight
var loading_friends := false
var shared := false              # this launch uploaded its friend set
var instance := ""               # this launch's presence row
var accepting := ""              # the invite being accepted
## counters for tests and diagnostics
var beats := 0
var polls := 0

var _seq := 0
var _watchers := 0
var _foreground := true
var _last_sent: Dictionary = {}
var _last_beat_ms := -1.0e12
var _beat_fail := 0
var _poll_fail := 0
var _beating := false
var _beat_again := false
var _polling := false
var _refreshing := false
var _synced_sig := ""
var _synced_at_ms := -1.0e12
var _skew_ms := 0.0
var _pid := ""
var _started := false
var _revoked_remote := false
var _toasted: Dictionary = {}
var _hb_timer: Timer
var _poll_timer: Timer
var _check_timer: Timer
var _layer: CanvasLayer
var toast: InviteToast


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS    # (Practice pauses the tree; a round there is still "in a round")
	native = NativeFriends.new()
	instance = _new_instance()
	_hb_timer = _timer(_on_heartbeat_timer)
	_poll_timer = _timer(_on_poll_timer)
	_check_timer = _timer(_on_check)
	_check_timer.wait_time = STATE_CHECK_S
	_check_timer.one_shot = false
	_check_timer.start()
	_layer = CanvasLayer.new()
	_layer.layer = 12
	add_child(_layer)
	toast = InviteToast.new()
	_layer.add_child(toast)
	Cloud.changed.connect(_on_cloud)
	Social.auth_changed.connect(func(_ok: bool) -> void: _on_cloud())


func _timer(cb: Callable) -> Timer:
	var t := Timer.new()
	t.one_shot = true
	t.timeout.connect(cb)
	add_child(t)
	return t


static func _new_instance() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return "g%08x%08x%04x" % [rng.randi(), rng.randi(), rng.randi() & 0xffff]


# ---------------------------------------------------------------- state
## The service offers Friends (and this build has a service).
func feature_on() -> bool:
	return Cloud.configured() and Cloud.has_feature("friends")


## "Show when I'm playing" (on by default once friend access is given).
func share_status() -> bool:
	return bool(Save.get_setting(SETTING, true))


func set_share_status(on: bool) -> void:
	(Save.data["settings"] as Dictionary)[SETTING] = on
	Save.mark()
	if on:
		_update_timers()
		beat_now()
	else:
		_clear_presence()
		_update_timers()
	changed.emit()


func server_now_ms() -> float:
	return Time.get_unix_time_from_system() * 1000.0 + _skew_ms


func _note_time(r: Dictionary) -> void:
	if r.has("server_time"):
		_skew_ms = float(r["server_time"]) - Time.get_unix_time_from_system() * 1000.0


## True while this player is in an online party (the invite target).
func in_party() -> bool:
	var s: Variant = App.session
	return s != null and is_instance_valid(s) and (s as NetSession).mode != NetSession.Mode.OFFLINE and App.party_code != ""


## What this launch is doing, from the real game state: {state, room}.
func derive_state() -> Dictionary:
	var s: Variant = App.session
	var online := s != null and is_instance_valid(s) and (s as NetSession).mode != NetSession.Mode.OFFLINE
	var room := App.party_code if online else ""
	if App.match_ctrl != null or App.screen is LoadingScreen:
		return {"state": "match", "room": room}
	if online and room != "":
		return {"state": "lobby", "room": room}
	return {"state": "online", "room": ""}


func _should_beat() -> bool:
	# (an explicit sign-out stops it; an expired token is renewed by Cloud.api)
	return _foreground and feature_on() and share_status() and access == "authorized" and shared and Cloud.profile_id() != "" \
		and Cloud.state != "signed_out"


func _update_timers() -> void:
	if _should_beat():
		if _hb_timer.is_stopped() and not _beating:
			_hb_timer.start(HEARTBEAT_S)
	else:
		_hb_timer.stop()
	if _watchers > 0 and _foreground:
		if _poll_timer.is_stopped() and not _polling:
			_poll_timer.start(POLL_S)
	else:
		_poll_timer.stop()


## Account changes: a new sign-in starts Friends quietly (no prompt) when
## friend access was already given; signing out or deleting the profile
## forgets everything this device held.
func _on_cloud() -> void:
	var pid := Cloud.profile_id()
	if pid != _pid:
		if _pid != "":
			_forget()
		_pid = pid
	if not _started and pid != "" and Cloud.signed_in() and feature_on() and native.call("signed_in"):
		_started = true
		_quiet_start()
	_update_timers()


func _quiet_start() -> void:
	var st: String = await native.call("status")
	if st == "authorized":
		access = "authorized"
		await _load_friends()
		if access == "authorized":
			await _sync()
			beat_now()
	elif st in ["denied", "restricted"]:
		access = st
		await _revoke()
	_update_timers()
	changed.emit()


## Everything this device knows about friends goes (sign-out, deleted or
## switched profile, revoked access).
func _forget() -> void:
	friends = []
	presence = {}
	party = null
	sent = {}
	sending = {}
	shared = false
	_synced_sig = ""
	_started = false
	_revoked_remote = false
	_set_incoming([])
	_update_timers()
	changed.emit()


# ---------------------------------------------------------------- panel
## A Friends panel opened (true) or closed (false): status is polled only
## while one is open.
func watch(on: bool) -> void:
	_watchers = maxi(0, _watchers + (1 if on else -1))
	if on and _watchers == 1:
		_poll_fail = 0
		refresh()
	_update_timers()


func watching() -> bool:
	return _watchers > 0


## The panel's full refresh: Game Center access (asking the first time),
## the friends list, the upload, then everyone's status.
func refresh() -> void:
	if _refreshing:
		return
	_refreshing = true
	if not bool(native.call("available")):
		access = "unavailable"
	elif not bool(native.call("signed_in")):
		access = "signed_out"
	elif bool(native.call("multiplayer_off")):
		access = "multiplayer_off"
	else:
		if access not in ["authorized"]:
			access = "checking"
			changed.emit()
		var st: String = await native.call("status")
		if st == "not_determined":
			# opening Friends is the moment to ask: Apple shows its sheet
			access = "not_determined"
			changed.emit()
			await _load_friends()
		elif st == "authorized":
			access = "authorized"
			await _load_friends()
		elif st in ["denied", "restricted"]:
			access = st
		else:
			access = "error"
	if access in ["denied", "restricted"]:
		await _revoke()
	elif access == "authorized":
		if feature_on():
			if await _sync():
				_update_timers()
				beat_now()
				await _poll()
		else:
			service = "off"
			presence = {}
	_refreshing = false
	_update_timers()
	changed.emit()


func _load_friends() -> void:
	loading_friends = true
	changed.emit()
	var r: Dictionary = await native.call("load")
	loading_friends = false
	var err := String(r.get("error", ""))
	if err == "":
		access = "authorized"
		var seen := {}
		var list: Array = []
		for f in r.get("friends", []):
			var tid := String(f.get("tid", ""))
			if tid == "" or seen.has(tid):
				continue
			seen[tid] = true
			list.append(f)
		friends = list
		# a friend no longer authorised: nothing of theirs stays here
		for k in presence.keys():
			if not seen.has(k):
				presence.erase(k)
		for k in sent.keys():
			if not seen.has(k):
				sent.erase(k)
	else:
		access = err if err in ["denied", "restricted", "signed_out"] else "error"
		friends = []
		presence = {}


## Upload the friend set (only when it changed, or every 10 minutes).
func _sync() -> bool:
	var ids: Array = []
	for f in friends:
		ids.append(String(f["tid"]))
	ids.sort()
	ids = ids.slice(0, MAX_FRIENDS)
	var sig := ",".join(PackedStringArray(ids)).sha256_text()
	var now := Time.get_ticks_msec()
	if shared and sig == _synced_sig and now - _synced_at_ms < SYNC_MIN_S * 1000.0:
		return true
	if not shared:
		service = "loading"
		changed.emit()
	var r: Dictionary = await Cloud.api(HTTPClient.METHOD_PUT, "/v1/friends", {"ids": ids})
	if bool(r.get("ok", false)):
		shared = true
		_revoked_remote = false
		_synced_sig = sig
		_synced_at_ms = now
		return true
	_service_failed(r)
	return false


## Friend access was turned off (Settings › Game Center, Screen Time): drop
## the list here and ask the service to forget the set, presence and invites.
func _revoke() -> void:
	var had := shared or not friends.is_empty()
	friends = []
	presence = {}
	sent = {}
	shared = false
	_synced_sig = ""
	_set_incoming([])
	_update_timers()
	if feature_on() and Cloud.profile_id() != "" and (had or not _revoked_remote):
		_revoked_remote = true
		await Cloud.api(HTTPClient.METHOD_DELETE, "/v1/friends")


func _service_failed(r: Dictionary) -> void:
	var e := String(r.get("error", ""))
	service_message = String(r.get("message", ""))
	match e:
		"service_off":
			service = "off"
		"network":
			service = "network"
		"game_center", "signed_out", "session_expired":
			service = "signed_out"
		"suspended":
			service = "suspended"
		_:
			service = "unavailable"    # (5xx, not configured, an older service, anything else)
	presence = {}
	party = null


func _poll() -> bool:
	if _polling:
		return false
	_polling = true
	if service != "ok":
		service = "loading"
		changed.emit()
	var r: Dictionary = await Cloud.api(HTTPClient.METHOD_GET, "/v1/friends/presence")
	_polling = false
	polls += 1
	var ok := bool(r.get("ok", false))
	if ok:
		_poll_fail = 0
		_note_time(r)
		service = "ok"
		service_message = ""
		var map := {}
		var known := {}
		for f in friends:
			known[String(f["tid"])] = true
		for e in r.get("friends", []):
			var tid := String(e.get("id", ""))
			if known.has(tid):     # (only friends this device actually has)
				map[tid] = e
		presence = map
		party = r.get("party")
		# the service's word on what is still pending
		for tid in sent.keys():
			if not (map.has(tid) and bool(map[tid].get("invited", false))):
				sent.erase(tid)
		if not bool(r.get("shared", true)):
			shared = false
	else:
		_poll_fail += 1
		_service_failed(r)
	changed.emit()
	if _watchers > 0 and _foreground:
		var wait := POLL_S if ok else minf(POLL_S * pow(2.0, _poll_fail), MAX_POLL_BACKOFF_S)
		if ok and r.has("poll_s"):
			wait = clampf(float(r["poll_s"]), 5.0, 60.0)
		_poll_timer.start(wait)
	return ok


func _on_poll_timer() -> void:
	if _watchers > 0 and _foreground:
		if access == "authorized" and feature_on() and shared:
			await _poll()
		elif access == "authorized" and feature_on():
			refresh()


# ---------------------------------------------------------------- heartbeat
func beat_now() -> void:
	if not _should_beat():
		return
	var since := (Time.get_ticks_msec() - _last_beat_ms) / 1000.0
	if since < MIN_BEAT_GAP_S:
		# (never push back a beat that is already due sooner)
		var wait := MIN_BEAT_GAP_S - since
		if _hb_timer.is_stopped() or _hb_timer.time_left > wait:
			_hb_timer.start(wait)
		return
	_beat()


func _on_heartbeat_timer() -> void:
	if _should_beat():
		_beat()


func _beat() -> void:
	if _beating:
		_beat_again = true
		return
	_beating = true
	_hb_timer.stop()
	var st := derive_state()
	_seq += 1
	_last_sent = st
	_last_beat_ms = Time.get_ticks_msec()
	var body := {"instance": instance, "seq": _seq, "state": st["state"], "protocol": Protocol.VERSION, "build": App.build_number()}
	if String(st["room"]) != "":
		body["room"] = st["room"]
	var r: Dictionary = await Cloud.api(HTTPClient.METHOD_POST, "/v1/presence", body)
	_beating = false
	beats += 1
	var ok := bool(r.get("ok", false))
	if ok:
		_beat_fail = 0
		_note_time(r)
		_set_incoming(r.get("invites", []))
	else:
		_beat_fail += 1
		if String(r.get("error", "")) == "suspended":
			service = "suspended"
	if not _should_beat():
		return
	if _beat_again:
		_beat_again = false
		beat_now()
		return
	_hb_timer.start(HEARTBEAT_S if ok else minf(HEARTBEAT_S * pow(2.0, _beat_fail), MAX_BACKOFF_S))


## This launch's row goes (background, sign-out, sharing turned off).
func _clear_presence() -> void:
	_last_sent = {}
	if feature_on() and Cloud.profile_id() != "" and Cloud.signed_in():
		Cloud.api(HTTPClient.METHOD_DELETE, "/v1/presence", {"instance": instance})


## 1 s: a state change goes out within a few seconds; an invite that waited
## for the round to end is shown; expired invites go.
func _on_check() -> void:
	if not _foreground:
		return
	if _should_beat() and not _beating and derive_state() != _last_sent:
		beat_now()
	_expire_invites()
	toast.refresh()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			_set_foreground(false)
		NOTIFICATION_APPLICATION_RESUMED:
			_set_foreground(true)


func _set_foreground(on: bool) -> void:
	if on == _foreground:
		return
	_foreground = on
	if not on:
		_clear_presence()
		_update_timers()
		toast.refresh()
		return
	# back: friend access may have been changed in Settings meanwhile
	_update_timers()
	if access == "authorized" or _started:
		_recheck_access()


func _recheck_access() -> void:
	if not bool(native.call("signed_in")):
		return
	var st: String = await native.call("status")
	if st in ["denied", "restricted"] and access != st:
		access = st
		await _revoke()
		changed.emit()
	elif st == "authorized":
		if access != "authorized":
			access = "authorized"
			await _load_friends()
			await _sync()
		beat_now()
		if _watchers > 0:
			_poll()
	_update_timers()


# ---------------------------------------------------------------- invites
## Send an invite for this player's party; from Home a party is started
## first (there is none to replace).  {ok, ...} or {ok:false, message}.
func invite(tid: String) -> Dictionary:
	if sending.has(tid):
		return {"ok": false, "busy": true}
	if sent.has(tid):
		return {"ok": true, "duplicate": true}
	sending[tid] = true
	changed.emit()
	if not in_party():
		var started := await _start_party()
		if not bool(started.get("ok", false)):
			sending.erase(tid)
			changed.emit()
			return started
	var r: Dictionary = await Cloud.api(HTTPClient.METHOD_POST, "/v1/invites", {"to": tid})
	sending.erase(tid)
	if bool(r.get("ok", false)):
		var iv: Dictionary = r.get("invite", {})
		sent[tid] = {"id": String(iv.get("id", "")), "expires_at": float(iv.get("expires_at", 0))}
		if presence.has(tid):
			var e: Dictionary = presence[tid]
			e["invited"] = true
			e["can_invite"] = false
			e["why"] = "invited"
	changed.emit()
	if _watchers > 0 and bool(r.get("ok", false)):
		_poll_timer.start(2.0)    # the panel catches up soon
	return r


func _start_party() -> Dictionary:
	var s: Variant = App.session
	if s != null and is_instance_valid(s) and (s as NetSession).mode != NetSession.Mode.OFFLINE:
		return {"ok": false, "message": "Your party is still starting. Try again in a moment."}
	var err := {"m": ""}
	var cb := func(message: String, _code: String) -> void: err["m"] = message
	App.party_error.connect(cb)
	await App.host_room_gamekit()
	if App.party_error.is_connected(cb):
		App.party_error.disconnect(cb)
	if not in_party():
		return {"ok": false, "message": String(err["m"]) if String(err["m"]) != "" else "Couldn't start a party. Try again."}
	# the new party room: its own Friends panel shows the invite going out
	if App.screen is Screen:
		FriendsPanel.open(App.screen as Screen)
	return {"ok": true}


func _set_incoming(list: Variant) -> void:
	var clean: Array = []
	if list is Array:
		for iv in list:
			if iv is Dictionary and String(iv.get("id", "")) != "" and float(iv.get("expires_at", 0)) > server_now_ms():
				clean.append(iv)
	var before := incoming.map(func(x: Dictionary) -> String: return String(x["id"]))
	var after := clean.map(func(x: Dictionary) -> String: return String(x["id"]))
	incoming = clean
	if before != after:
		invites_changed.emit()
		changed.emit()
	toast.refresh()


func _expire_invites() -> void:
	if incoming.is_empty():
		return
	var now := server_now_ms()
	var keep := incoming.filter(func(iv: Dictionary) -> bool: return float(iv.get("expires_at", 0)) > now)
	if keep.size() != incoming.size():
		_set_incoming(keep)


func _drop_invite(id: String) -> void:
	_set_incoming(incoming.filter(func(iv: Dictionary) -> bool: return String(iv["id"]) != id))


func badge_count() -> int:
	return incoming.size()


## Never during a round (or its loading): the invite waits for the results
## or the lobby.
func can_show_invites() -> bool:
	return _foreground and App.match_ctrl == null and not (App.screen is LoadingScreen)


## The toast shows each invite once; the panel always lists them.
func next_toast() -> Dictionary:
	for iv in incoming:
		if not _toasted.has(String(iv["id"])) and String(iv["id"]) != accepting:
			return iv
	return {}


func mark_toasted(id: String) -> void:
	_toasted[id] = true


## "Comfy Frog invited you" + the party it is for.
static func invite_text(iv: Dictionary) -> Array:
	var from: Dictionary = iv.get("from", {})
	var who := NameRules.safe_display(String(from.get("name", ""))) if from.get("name") is String and String(from.get("name")) != "" else "A friend"
	var party_of := "to their party"
	if not bool(iv.get("from_host", true)):
		var host: Variant = iv.get("host_name")
		party_of = ("to %s's party" % NameRules.safe_display(String(host))) if host is String and String(host) != "" else "to a party they're in"
	return ["%s invited you" % who, party_of]


func accept(iv: Dictionary) -> void:
	var id := String(iv.get("id", ""))
	if id == "" or accepting != "" or not can_show_invites():
		return     # (never pulls anyone out of a round)
	var scr: Variant = App.screen
	var who: String = invite_text(iv)[0].trim_suffix(" invited you")
	if in_party() and scr is Screen:
		var hosting := (App.session as NetSession).is_host() and (App.session as NetSession).human_count() > 1
		var q := ("Leave your party to join %s? Your party ends for everyone in it." if hosting else "Leave this party to join %s?") % who
		var answer := {"v": -1}
		(scr as Screen).dialog(q, [["Leave and join", func() -> void: answer["v"] = 1], ["Not now", func() -> void: answer["v"] = 0]])
		while int(answer["v"]) < 0 and is_inside_tree():
			await get_tree().process_frame
		if int(answer["v"]) != 1:
			return
	accepting = id
	toast.refresh()
	var r: Dictionary = await Cloud.api(HTTPClient.METHOD_POST, "/v1/invites/%s/accept" % id.uri_encode(),
		{"build": App.build_number(), "protocol": Protocol.VERSION})
	accepting = ""
	_drop_invite(id)
	if not bool(r.get("ok", false)):
		_say(Cloud.explain(r))
		return
	var code := String(r.get("code", ""))
	if code == App.party_code and in_party():
		_say("You're already in this party.")
		return
	App.goto(OnlineScreen)
	var os: Variant = App.screen
	if os is OnlineScreen:
		(os as OnlineScreen).join_invited(code, who)


func decline(iv: Dictionary) -> void:
	var id := String(iv.get("id", ""))
	_drop_invite(id)
	_toasted[id] = true
	await Cloud.api(HTTPClient.METHOD_POST, "/v1/invites/%s/decline" % id.uri_encode(), {})


func _say(text: String) -> void:
	var scr: Variant = App.screen
	if scr is Screen and is_instance_valid(scr):
		(scr as Screen).dialog(text)


## Tests: back to a fresh launch (keeps the adapter).
func reset_for_tests() -> void:
	_forget()
	access = "unknown"
	service = "idle"
	service_message = ""
	beats = 0
	polls = 0
	_seq = 0
	_watchers = 0
	_foreground = true
	_last_sent = {}
	_last_beat_ms = -1.0e12
	_beat_fail = 0
	_poll_fail = 0
	_beating = false
	_beat_again = false
	_polling = false
	_refreshing = false
	_synced_at_ms = -1.0e12
	_skew_ms = 0.0
	_toasted = {}
	accepting = ""
	_pid = Cloud.profile_id()
	_hb_timer.stop()
	_poll_timer.stop()
	toast.refresh()


## The Game Center side, through Social (the shipped adapter).
class NativeFriends:
	extends RefCounted

	func available() -> bool:
		return Social.available

	func signed_in() -> bool:
		return Social.available and Social.authenticated and Social.gc != null

	func multiplayer_off() -> bool:
		return Social.multiplayer_restricted

	## not_determined | restricted | denied | authorized | unavailable (no prompt)
	func status() -> String:
		return await Waiter.wait(func(done: Callable) -> void: Social.friends_access(done), 15.0, "unavailable")

	## {friends, error}; asks for permission the first time
	func load() -> Dictionary:
		return await Waiter.wait(func(done: Callable) -> void:
			Social.friends_loaded.connect(func(list: Array, err: String) -> void: done.call({"friends": list, "error": err}), CONNECT_ONE_SHOT)
			Social.load_friends(), 45.0, {"friends": [], "error": "error"})


## Awaits a native callback, with a timeout (the callback may come at once).
class Waiter:
	extends RefCounted
	signal done

	static func wait(start: Callable, timeout_s: float, timeout_value: Variant) -> Variant:
		var w := Waiter.new()
		var box := {"done": false, "v": null}
		var finish := func(v: Variant) -> void:
			if bool(box["done"]):
				return
			box["done"] = true
			box["v"] = v
			w.done.emit()
		start.call(finish)
		if not bool(box["done"]):
			(Engine.get_main_loop() as SceneTree).create_timer(timeout_s).timeout.connect(func() -> void: finish.call(timeout_value))
			await w.done
		return box["v"]
