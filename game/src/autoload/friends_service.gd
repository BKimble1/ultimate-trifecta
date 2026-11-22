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
##
## Friend tags (in-game friends, no Game Center friendship needed).  Every
## named player has a tag (ComfyFrog#4821: the approved name without spaces
## and a number).  Add friend sends a request by tag (POST
## /v1/friends/requests); the other player accepts or declines in their
## Friends panel (the Friends button counts requests waiting).  Accepted
## friends get status and invites exactly like Game Center friends, also
## when this player never shared a Game Center friends list.  Sign-in to the
## game service is still through Game Center (Cloud.api).

signal changed
signal invites_changed      # (party invites or friend requests waiting: the badge)

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
## (2.3) invites sent straight through Game Center (no game service needed):
## tid -> {"state": "sent" | "accepted" | "declined", "at": msec}
var gc_sent: Dictionary = {}
const GC_INVITE_TTL_MS := 90000
## tests: act as if Game Center could send invites
var gc_invite_test := false
## counters for tests and diagnostics
var beats := 0
var polls := 0
## Friend tags.  tags: idle | loading | ok | off (no tags on this service) |
## signed_out (no Game Center / sign-in) | network | unavailable
var tags := "idle"
var tags_message := ""
var my_tag := ""                 # "ComfyFrog#4821" ("" until known / no name yet)
var needs_name := false          # no approved name yet: no tag
var requests_in: Array = []      # [{id, created_at, from: {profile_id, name, tag}}]
var requests_out: Array = []     # [{id, created_at, to: {...}}]: "Requested"
var tag_friends: Array = []      # [{profile_id, name, tag, since}]: accepted in-game friends
var request_count := 0           # requests waiting (heartbeat / presence say so between loads)
var adding := false              # an Add friend request in flight
var answering: Dictionary = {}   # request id -> true while Accept / Decline is in flight
var _tags_loading := false

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
	Social.invite_answered.connect(_on_gc_answer)
	Social.invite_send_failed.connect(func(message: String) -> void:
		for k in gc_sent.keys():
			if String(gc_sent[k].get("state", "")) == "sent":
				gc_sent.erase(k)
		changed.emit()
		if App.screen is Control:
			UIKit.toast(App.screen as Control, "Invite not sent: %s" % message, 3.0))
	# (integration: Cloud may move an install between the sandbox and
	# production deployments once; Friends data is per deployment)
	if Cloud.has_signal("deployment_changed"):
		Cloud.connect("deployment_changed", _on_deployment_changed)


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


## The service offers friend tags (Add friend by tag).
func tags_on() -> bool:
	return Cloud.configured() and Cloud.has_feature("friend_tags")


## In-game friends are known (from the list, or from status).
func has_tag_friends() -> bool:
	if not tag_friends.is_empty():
		return true
	for e in presence.values():
		if String((e as Dictionary).get("source", "")) in ["tag", "both"]:
			return true
	return false


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
	# Game Center friends shared, or friends added by tag: someone can see it
	var someone := (access == "authorized" and shared) or has_tag_friends()
	return _foreground and feature_on() and share_status() and someone and Cloud.profile_id() != "" \
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
	# friend tags: the tag, requests waiting (the badge) and in-game friends
	# (their status needs heartbeats too), quietly once per sign-in
	if tags == "idle" and pid != "" and Cloud.signed_in() and tags_on() and not _tags_loading:
		_quiet_tags()
	var t: Variant = Cloud.profile.get("friend_tag")
	if t is String and String(t) != "":
		my_tag = String(t)
	_update_timers()


func _quiet_tags() -> void:
	await load_tags()
	_update_timers()
	if _should_beat():
		beat_now()


func _quiet_start() -> void:
	if bool(native.call("multiplayer_off")):
		access = "multiplayer_off"     # (Screen Time: no online friends at all)
		changed.emit()
		return
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


## Cloud moved this install to another deployment: its friend sets, status
## and invites are separate there.  Stop talking to the old one (its row
## simply expires within 60 s), forget what it said, and start again on the
## new one (upload, heartbeat, and a panel refresh if one is open).
func _on_deployment_changed(_from: Variant = null, _to: Variant = null) -> void:
	_hb_timer.stop()
	_poll_timer.stop()
	var keep_friends := friends
	_forget()
	friends = keep_friends     # (Game Center's list doesn't depend on the deployment)
	_pid = ""
	_last_sent = {}
	_toasted = {}
	service = "idle"
	_on_cloud()
	if _watchers > 0:
		refresh()


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
	tags = "idle"
	tags_message = ""
	my_tag = ""
	needs_name = false
	requests_in = []
	requests_out = []
	tag_friends = []
	request_count = 0
	answering = {}
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
	# in-game friends (by tag) need no Game Center friends list: their
	# requests and status load whatever Game Center's list allows
	if tags_on() and access != "multiplayer_off":
		await load_tags()
	if access not in ["authorized", "multiplayer_off"] and feature_on() and has_tag_friends():
		_update_timers()
		beat_now()
		await _poll()
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
			# (only friends this device actually has: its Game Center
			# friends, and friends added by tag)
			if tid != "" and (known.has(tid) or String(e.get("source", "")) in ["tag", "both"]):
				map[tid] = e
		presence = map
		party = r.get("party")
		# the service's word on what is still pending
		for tid in sent.keys():
			if not (map.has(tid) and bool(map[tid].get("invited", false))):
				sent.erase(tid)
		if not bool(r.get("shared", true)):
			shared = false
		_note_requests(r)
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
		if feature_on() and ((access == "authorized" and shared) or has_tag_friends()):
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
		_note_requests(r)
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
	toast.refresh(STATE_CHECK_S)


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


## (2.3) An in-game invite through Game Center: the friend gets Game
## Center's invitation and lands in this party.  Works without the game
## service; a solo home party goes online first.  {ok, message}.
func invite_gc(tid: String) -> Dictionary:
	var f := friend(tid)
	if f.is_empty() or not (f.get("player") is Object):
		return {"ok": false, "message": "This friend can't be invited right now."}
	if gc_state(tid) == "sent":
		return {"ok": true, "duplicate": true}
	if App.is_solo_party():
		if not await App.open_party():
			return {"ok": false, "message": "Sign in to Game Center to invite friends."}
		# the party room replaced home: its own Friends panel shows the invite
		if App.screen is Screen:
			FriendsPanel.open(App.screen as Screen)
	var s: Variant = App.session
	if s == null or not is_instance_valid(s) or not ((s as NetSession).transport is GameKitTransport):
		return {"ok": false, "message": "Invites need a Game Center party."}
	var ns := s as NetSession
	if not ns.transport.is_host:
		return {"ok": false, "message": "Only the party host can invite."}
	if not Social.invite_players(ns.transport as GameKitTransport, ns.room_code, [f["player"]]):
		return {"ok": false, "message": "Game Center couldn't send the invite. Check you're signed in."}
	gc_sent[tid] = {"state": "sent", "at": Time.get_ticks_msec()}
	changed.emit()
	return {"ok": true}


## (2.3) This player can send in-game Game Center invites now: signed in,
## and alone at home or hosting a Game Center party.
func can_gc_invite() -> bool:
	if gc_invite_test:
		return true
	if not Social.online_ready():
		return false
	if App.is_solo_party():
		return true
	var s: Variant = App.session
	return s != null and is_instance_valid(s) and (s as NetSession).is_host() and (s as NetSession).transport is GameKitTransport


## "" | "sent" | "accepted" | "declined" for an in-game Game Center invite
## (a "sent" one with no answer lapses after GC_INVITE_TTL_MS).
func gc_state(tid: String) -> String:
	if not gc_sent.has(tid):
		return ""
	var e: Dictionary = gc_sent[tid]
	if String(e["state"]) in ["sent", "declined"] and Time.get_ticks_msec() - int(e["at"]) > GC_INVITE_TTL_MS:
		gc_sent.erase(tid)
		return ""
	return String(e["state"])


## A friend's entry by team player id ({} when not in the list).
func friend(tid: String) -> Dictionary:
	for f in friends:
		if String(f.get("tid", "")) == tid:
			return f
	return {}


func _on_gc_answer(player: Object, response: int) -> void:
	if player == null or not is_instance_valid(player):
		return
	var tid := String(player.get("team_player_id"))
	var gid := String(player.get("game_player_id"))
	var who := ""
	for f in friends:
		if (tid != "" and String(f.get("tid", "")) == tid) or (gid != "" and String(f.get("gid", "")) == gid):
			tid = String(f["tid"])
			who = FriendsPanel.gc_display(String(f.get("name", "")))
			break
	if tid == "":
		return
	var ok := response == Social.INVITE_ACCEPTED
	gc_sent[tid] = {"state": "accepted" if ok else "declined", "at": Time.get_ticks_msec()}
	changed.emit()
	if App.screen is Control and who != "":
		UIKit.toast(App.screen as Control, ("%s is joining your party" if ok else "%s can't come right now") % who, 2.6)


func _start_party() -> Dictionary:
	var s: Variant = App.session
	if App.is_solo_party():
		# (2.2) your home party goes online, settings kept
		if not await App.open_party():
			return {"ok": false, "message": "Sign in to Game Center to invite friends."}
		if App.screen is Screen:
			FriendsPanel.open(App.screen as Screen)
		return {"ok": true}
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


## Party invites plus friend requests waiting (the Friends button's count).
func badge_count() -> int:
	return incoming.size() + maxi(request_count, requests_in.size())


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


## (Crash sweep) One accept at a time: a second tap while the "Leave this
## party?" question is up, or while the first is with the service, does
## nothing.  The question ends as "Not now" if its screen goes away (the
## old loop waited forever on a freed screen, and every later Accept was
## then ignored); a round that starts meanwhile wins (nobody is pulled out
## of it, even after the service said yes).
var _asking := false


func accept(iv: Dictionary) -> void:
	var id := String(iv.get("id", ""))
	if id == "" or accepting != "" or _asking or not can_show_invites():
		return     # (never pulls anyone out of a round)
	var scr: Variant = App.screen
	var who: String = invite_text(iv)[0].trim_suffix(" invited you")
	if in_party() and scr is Screen:
		var hosting := (App.session as NetSession).is_host() and (App.session as NetSession).human_count() > 1
		var q := ("Leave your party to join %s? Your party ends for everyone in it." if hosting else "Leave this party to join %s?") % who
		var answer := {"v": -1}
		_asking = true
		(scr as Screen).dialog(q, [["Leave and join", func() -> void: answer["v"] = 1], ["Not now", func() -> void: answer["v"] = 0]])
		while int(answer["v"]) < 0 and is_inside_tree() and is_instance_valid(scr) and App.screen == scr:
			await get_tree().process_frame
		_asking = false
		if int(answer["v"]) != 1 or not can_show_invites():
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
	if not can_show_invites():
		return     # (a round started while the service answered)
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


# ---------------------------------------------------------------- friend tags
const TAG_EXAMPLE := "ComfyFrog#4821"


## What a player typed into Add friend, checked as the service checks it
## (instant feedback; the service decides): {ok, tag} or {ok:false, message}.
## Case, spaces, a leading '@' and a full-width '＃' are forgiven.
static func parse_tag(typed: String) -> Dictionary:
	var s := typed.replace("＃", "#").strip_edges()
	if s.begins_with("@"):
		s = s.substr(1).strip_edges()
	if s == "":
		return {"ok": false, "message": "Type your friend's tag, like %s." % TAG_EXAMPLE}
	var i := s.rfind("#")
	if i < 0:
		return {"ok": false, "message": "Add the # and number, like %s." % TAG_EXAMPLE}
	var name := s.substr(0, i).replace(" ", "")
	var num := s.substr(i + 1).strip_edges()
	if RegEx.create_from_string("^[A-Za-z0-9_]{2,16}$").search(name) == null:
		return {"ok": false, "message": "That isn't a tag. Tags look like %s." % TAG_EXAMPLE}
	if RegEx.create_from_string("^[0-9]{1,4}$").search(num) == null or int(num) < 1:
		return {"ok": false, "message": "The number after # has 4 digits, like #4821."}
	return {"ok": true, "tag": "%s#%s" % [name, num.lpad(4, "0")]}


## The service's answer in the player's words (short).
static func tag_error_text(r: Dictionary) -> String:
	match String(r.get("error", "")):
		"game_center", "signed_out", "session_expired":
			return "Sign in to Game Center to add friends."
		"service_off", "no_route", "not_configured":
			return "Adding friends isn't available right now."
		"network":
			return "Can't reach the game service. Check your connection."
		"needs_name":
			return "Choose a player name first."
		"no_player":
			return "No player with that tag."
		"already_friends":
			return "Already friends."
		"self":
			return "That's your own tag."
	return Cloud.explain(r)


func _tags_failure(r: Dictionary) -> String:
	match String(r.get("error", "")):
		"service_off", "no_route":
			return "off"
		"network":
			return "network"
		"game_center", "signed_out", "session_expired":
			return "signed_out"
		"suspended":
			return "suspended"
	return "unavailable"


## The tag, requests both ways and in-game friends (GET /v1/friends/requests).
func load_tags() -> void:
	if _tags_loading:
		while _tags_loading and is_inside_tree():
			await get_tree().process_frame
		return
	if not tags_on():
		tags = "off"
		changed.emit()
		return
	_tags_loading = true
	if tags != "ok":
		tags = "loading"
		changed.emit()
	var r: Dictionary = await Cloud.api(HTTPClient.METHOD_GET, "/v1/friends/requests")
	_tags_loading = false
	if bool(r.get("ok", false)):
		tags = "ok"
		tags_message = ""
		_note_time(r)
		my_tag = String(r["tag"]) if r.get("tag") is String else ""
		needs_name = bool(r.get("needs_name", false))
		requests_in = _people(r.get("incoming"), "from")
		requests_out = _people(r.get("outgoing"), "to")
		var fl: Array = []
		for f in (r.get("friends") if r.get("friends") is Array else []):
			if f is Dictionary and String(f.get("profile_id", "")) != "":
				fl.append(f)
		tag_friends = fl
		_set_request_count(requests_in.size())
	else:
		tags = _tags_failure(r)
		tags_message = tag_error_text(r)
	changed.emit()


static func _people(list: Variant, key: String) -> Array:
	var out: Array = []
	if list is Array:
		for x in list:
			if x is Dictionary and String(x.get("id", "")) != "" and x.get(key) is Dictionary:
				out.append(x)
	return out


## Heartbeat / presence replies count the requests waiting (the badge); an
## open panel loads a new one at once.
func _note_requests(r: Dictionary) -> void:
	if not r.has("requests"):
		return
	var n := int(r["requests"])
	var had := request_count
	_set_request_count(n)
	if n != had and n != requests_in.size() and _watchers > 0 and not _tags_loading:
		load_tags()


func _set_request_count(n: int) -> void:
	if n == request_count:
		return
	request_count = n
	invites_changed.emit()
	changed.emit()


## Add friend: a request by tag.  {ok, state (pending | accepted), message}
## or {ok:false, message} (never throws; a second tap while one is in flight
## is {ok:false, busy:true}).
func add_friend(typed: String) -> Dictionary:
	var p := parse_tag(typed)
	if not bool(p["ok"]):
		return {"ok": false, "message": String(p["message"])}
	if adding:
		return {"ok": false, "busy": true}
	if my_tag != "" and String(p["tag"]).to_lower() == my_tag.to_lower():
		return {"ok": false, "error": "self", "message": "That's your own tag."}
	if not tags_on():
		return {"ok": false, "message": "Adding friends isn't available right now."}
	adding = true
	changed.emit()
	var r: Dictionary = await Cloud.api(HTTPClient.METHOD_POST, "/v1/friends/requests", {"tag": String(p["tag"])})
	adding = false
	var out := {}
	if bool(r.get("ok", false)):
		var st := String(r.get("state", "pending"))
		var who: Dictionary = r.get("friend", {}) if r.get("friend") is Dictionary else {}
		if st != "accepted" and r.get("request") is Dictionary:
			var rq: Dictionary = r["request"]
			who = rq.get("to", {}) if rq.get("to") is Dictionary else {}
			if not requests_out.any(func(x: Dictionary) -> bool: return String(x["id"]) == String(rq.get("id", ""))):
				requests_out.push_front(rq)
		var name := NameRules.safe_display(String(who["name"])) if who.get("name") is String and String(who["name"]) != "" else String(p["tag"])
		out = {"ok": true, "state": st, "message": ("You and %s are friends now." if st == "accepted" else "Request sent to %s.") % name}
		if st == "accepted":
			_after_new_friend()
	else:
		out = {"ok": false, "error": String(r.get("error", "")), "message": tag_error_text(r)}
	changed.emit()
	return out


## Accept or decline a friend request.  {ok, message}.
func answer_request(rq: Dictionary, yes: bool) -> Dictionary:
	var id := String(rq.get("id", ""))
	if id == "" or answering.has(id):
		return {"ok": false, "busy": true}
	answering[id] = true
	changed.emit()
	var r: Dictionary = await Cloud.api(HTTPClient.METHOD_POST, "/v1/friends/requests/%s/%s" % [id.uri_encode(), "accept" if yes else "decline"], {})
	answering.erase(id)
	var ok := bool(r.get("ok", false))
	var gone := int(r.get("http_status", 0)) == 410
	if ok or gone:
		requests_in = requests_in.filter(func(x: Dictionary) -> bool: return String(x["id"]) != id)
		_set_request_count(requests_in.size())
	var out := {"ok": ok, "message": ""}
	if ok and yes:
		var from: Dictionary = rq.get("from", {}) if rq.get("from") is Dictionary else {}
		var name := NameRules.safe_display(String(from["name"])) if from.get("name") is String and String(from["name"]) != "" else "your friend"
		out["message"] = "You and %s are friends now." % name
		_after_new_friend()
	elif not ok:
		out["message"] = "That request isn't there any more." if gone else tag_error_text(r)
	changed.emit()
	return out


## No longer friends in game (Game Center friends stay Game Center friends).
func remove_friend(pid: String) -> Dictionary:
	if pid == "":
		return {"ok": false}
	var r: Dictionary = await Cloud.api(HTTPClient.METHOD_DELETE, "/v1/friends/%s" % pid.uri_encode())
	if bool(r.get("ok", false)):
		tag_friends = tag_friends.filter(func(f: Dictionary) -> bool: return String(f.get("profile_id", "")) != pid)
		for tid in presence.keys():
			var e: Dictionary = presence[tid]
			if String(e.get("profile_id", "")) == pid and String(e.get("source", "")) == "tag":
				presence.erase(tid)
		changed.emit()
		return {"ok": true}
	return {"ok": false, "message": tag_error_text(r)}


## A friend was added: the lists, heartbeats (someone can see you now) and
## the panel's status catch up.
func _after_new_friend() -> void:
	await load_tags()
	_update_timers()
	beat_now()
	if _watchers > 0 and feature_on():
		_poll()


## The in-game friends status doesn't list (status unavailable, or before
## the first poll): [{profile_id, name, tag}].
func tag_friends_without_status() -> Array:
	var seen := {}
	for e in presence.values():
		seen[String((e as Dictionary).get("profile_id", ""))] = true
	return tag_friends.filter(func(f: Dictionary) -> bool: return not seen.has(String(f.get("profile_id", ""))))


## Join with code from the Friends panel: the same join as Play with Friends
## (its progress, Cancel and messages).  {ok} or {ok:false, message}.
func join_code(typed: String) -> Dictionary:
	var r := Social.parse_code(typed)
	if not bool(r["ok"]):
		return {"ok": false, "message": OnlineScreen.short_message(String(r["message"]))}
	if not Social.online_ready():
		return {"ok": false, "message": "Sign in to Game Center to join a party."}
	if App.match_ctrl != null or App.screen is LoadingScreen:
		return {"ok": false, "message": "Finish the round first."}
	var code := String(r["code"])
	if code == App.party_code and in_party():
		return {"ok": false, "message": "You're already in this party."}
	App.goto(OnlineScreen)
	var os: Variant = App.screen
	if os is OnlineScreen:
		(os as OnlineScreen).join_typed(code)
	return {"ok": true}


## Apple's invite sheet (Invite with Game Center), from here so it survives
## the Friends panel closing (a coroutine on a freed panel never resumes:
## from Home the sheet silently never opened).  False when it can't open.
func open_gc_sheet(recipients: Array = []) -> bool:
	if not Social.online_ready():
		return false
	if App.is_solo_party() and not await App.open_party():
		return false
	var s: Variant = App.session
	if s == null or not is_instance_valid(s) or not ((s as NetSession).transport is GameKitTransport) or not (s as NetSession).is_host():
		return false
	return Social.invite_friends((s as NetSession).transport as GameKitTransport, (s as NetSession).room_code, recipients)


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
	_asking = false
	adding = false
	_tags_loading = false
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
