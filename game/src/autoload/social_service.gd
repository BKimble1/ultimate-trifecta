extends Node
## Game Center identity, friends and private-room matchmaking (iOS).
## - Code rooms: everyone in a room uses the same GKMatchRequest.player_group
##   derived from the short room code; the host keeps adding players.
## - Friends: Apple's GKMatchmakerViewController invite UI (invite-only, no
##   strangers; optionally with a friend pre-selected) and the friends list
##   (permission requested only when the player opens Friends).
## Identity domains (Final): every friend is reported by its teamPlayerID, the
## same team-scoped ID the service verifies for a signed-in player
## (identity_signature), so presence and invites match people across the
## two; gamePlayerID and the display name are kept only for Apple's own UI
## and for showing the row.  Native names are checked against the pinned
## GodotApplePlugins source (GKLocalPlayer.load_friends,
## load_friends_authorization_status; GKPlayer team_player_id,
## game_player_id, display_name; GKMatchRequest recipients).
## If Game Center is unavailable or declined, solo practice still works and the
## online buttons explain why they are disabled. Nothing here is mocked.
##
## Crash sweep (friends / invites; docs/final/friends.md "Game Center
## hardening").  The rules every path here follows:
##   - GameKit completion handlers may run off the main thread
##     (GodotApplePlugins calls the Callable from the handler's queue), so
##     every one hands over to the main thread (call_deferred) before it
##     touches a transport, a signal the UI listens to, or another plugin
##     call (several plugin methods trap off the main thread:
##     MainActor.assumeIsolated).
##   - One Apple sheet at a time (sheet_open): a second GKMatchmaker
##     controller replaced the first one's wrapper while it was still on
##     screen; the wrapper owns the sheet's delegate, so the sheet left up
##     could never be cancelled or closed.  The wrapper is dropped only after
##     its own signal has finished (deferred), never inside it.
##   - Answers for a party that has ended meanwhile (cancelled join, closed
##     party, a replaced request) are dropped and their match disconnected,
##     never bound to a dead transport.
##   - Nothing calls GameKit while signed out, and authentication answering
##     again (GameKit re-runs its handler when the app returns from the
##     background) registers the invite listener only once, so an accepted
##     invite arrives once.  The same invite twice is handled once.
##   - add_players retries back off (a failing request used to re-ask at
##     once, from inside its own answer: unbounded recursion).
## `kit` is the seam the desktop tests use in place of GameKit.

signal auth_changed(ok: bool)
signal invite_ready(transport: GameKitTransport)     # an accepted invite produced a match (we are a client)
signal room_matched(transport: GameKitTransport)     # code/invite matchmaking produced a GKMatch
signal room_failed(message: String)
signal invite_joining                              # (2.3) an accepted invite is connecting
## friends: [{tid (teamPlayerID), gid (gamePlayerID), name, player (GKPlayer)}];
## error: "" or denied | restricted | signed_out | error
signal friends_loaded(friends: Array, error: String)

## Party codes (same alphabet as the service: no look-alikes such as 0/O,
## 1/I/L, 5/S, 8/B, 2/Z, U/V).
const CODE_ALPHABET := "ACDEFGHJKMNPQRTWXY34679"
const CODE_LEN := 6
## Game Center player attributes: a match only forms when the attributes of
## its players OR to all ones, so a party match always contains its host (a
## group of joiners alone can never complete one: no orphan matches).
const ATTR_HOST := 0xFFFF0000
const ATTR_JOINER := 0x0000FFFF
## must match application/bundle_identifier in export_presets.cfg (tested)
const BUNDLE_ID := "com.idlery.ultimatetrifecta"

var available := false
## (build 32) see _request / _retry_simpler
var simple_requests := false
var _room_code := ""
var _room_is_host := false
var authenticated := false
var auth_error := ""
var multiplayer_restricted := false
var local_player_id := ""
var team_player_id := ""     # stable per developer team; what the service verifies
var display_name := ""
var gc: Object = null
var matchmaker: Object = null
var _pending_transport: GameKitTransport = null
var _room_request: Object = null
var _adding := false
var _invite_vc: Object = null
var _listening := false
var _add_fail := 0
## the Apple sheet up now: "" | invite | invite_accept | gc_friends
var _sheet := ""
var _sheet_at := -1.0e12
const SHEET_STALE_MS := 180000.0   # (a sheet whose delegate never answered: no longer blocks)
const SHEET_GAP_MS := 1500.0       # Game Center's own screens never answer: a double tap opens one
var _accepting_invite: Object = null
var _accepting_at := -1.0e12
## Tests: stands in for the GameKit classes (new_request, create_controller,
## create_controller_from_invite, show_type, new_matchmaker).  null on iOS.
var kit: Object = null


func _ready() -> void:
	available = OS.get_name() == "iOS" and ClassDB.class_exists("GameCenterManager")


func status_text() -> String:
	if not available:
		return "Online rooms need Game Center on iPhone. Practice works offline."
	if authenticated:
		if multiplayer_restricted:
			return "Multiplayer is restricted on this account (Screen Time). Practice still works."
		return "Signed in to Game Center as %s" % display_name
	if auth_error != "":
		return "Game Center sign-in unavailable: %s. Practice still works." % auth_error
	return "Signing in to Game Center…"


func online_ready() -> bool:
	return available and authenticated and not multiplayer_restricted


func authenticate() -> void:
	if not available or gc != null:
		return
	gc = ClassDB.instantiate("GameCenterManager")
	gc.connect("authentication_result", _on_auth)
	gc.connect("authentication_error", func(msg: String) -> void:
		auth_error = msg
		authenticated = false
		auth_changed.emit(false))
	gc.call("authenticate")


## GameKit answers again whenever the app returns from the background (and
## when the player changes in Settings): this must be safe to run any number
## of times.
func _on_auth(ok: bool) -> void:
	var lp: Object = gc.get("local_player") if ok and gc != null else null
	if ok and lp == null:
		ok = false
	authenticated = ok
	if ok:
		local_player_id = String(lp.get("game_player_id"))
		team_player_id = String(lp.get("team_player_id"))
		display_name = String(lp.get("display_name"))
		multiplayer_restricted = bool(lp.get("is_multiplayer_gaming_restricted"))
		if not _listening:
			lp.call("register_listener")     # (once: a second registration delivered each invite twice)
			_listening = true
		if not lp.is_connected("invite_accepted", _on_invite_accepted):
			lp.connect("invite_accepted", _on_invite_accepted)
		if matchmaker == null:
			matchmaker = _new_matchmaker()
	auth_changed.emit(ok)


func _new_matchmaker() -> Object:
	if kit != null:
		return kit.call("new_matchmaker")
	return ClassDB.instantiate("GKMatchmaker") if ClassDB.class_exists("GKMatchmaker") and ClassDB.can_instantiate("GKMatchmaker") else null


## An Apple sheet (matchmaker / invite / Game Center screen) is up.
func sheet_open() -> bool:
	if _sheet == "":
		return false
	var limit := SHEET_GAP_MS if _sheet == "gc_friends" else SHEET_STALE_MS
	if Time.get_ticks_msec() - _sheet_at > limit:
		_sheet = ""
		return false
	return true


func _sheet_up(kind: String) -> void:
	_sheet = kind
	_sheet_at = Time.get_ticks_msec()


## (deferred: the plugin's signal has finished emitting before the wrapper
## that emitted it may be released)
func _sheet_closed(vc: Object) -> void:
	if vc == _invite_vc:
		_invite_vc = null
	_sheet = ""


## Game Center identity-verification signature for the service sign-in:
## {ok, player_id (teamPlayerID), bundle_id, timestamp (ms), salt, signature
## (base64), public_key_url} or {ok:false, message}.
func identity_signature() -> Dictionary:
	if not available:
		return {"ok": false, "message": "Online play needs Game Center on iPhone or iPad."}
	if not authenticated:
		return {"ok": false, "message": "Sign in to Game Center (Settings › Game Center) to play online."}
	var lp: Object = gc.get("local_player")
	var done := {"v": null}
	lp.call("fetch_items_for_identity_verification_signature", func(values: Dictionary, error: Variant) -> void:
		done["v"] = {"values": values, "error": error})
	var waited := 0.0
	while done["v"] == null and waited < 20.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if done["v"] == null:
		return {"ok": false, "message": "Game Center didn't answer. Try again."}
	if done["v"]["error"] != null:
		return {"ok": false, "message": "Game Center couldn't confirm your identity (%s)." % error_text(done["v"]["error"])}
	var v: Dictionary = done["v"]["values"]
	var b64 := func(x: Variant) -> String:
		return Marshalls.raw_to_base64(x) if x is PackedByteArray else String(x)
	return {
		"ok": true, "player_id": team_player_id, "bundle_id": BUNDLE_ID,
		"timestamp": int(v.get("timestamp", 0)), "salt": b64.call(v.get("salt", PackedByteArray())),
		"signature": b64.call(v.get("data", v.get("signature", PackedByteArray()))),
		"public_key_url": String(v.get("url", v.get("public_key_url", ""))),
	}


## Calls a static method on a GDExtension class.
func _static(cls: String, method: String, args: Array) -> Variant:
	var callargs: Array = [cls, method]
	callargs.append_array(args)
	return ClassDB.callv("class_call_static", callargs)


static func make_code(rng: RandomNumberGenerator) -> String:
	var s := ""
	for i in CODE_LEN:
		s += CODE_ALPHABET[rng.randi() % CODE_ALPHABET.length()]
	return s


## Strict normalisation of a typed party code, matching the service: only
## case, spaces and dashes are forgiven; anything else is an explicit error
## (never silently dropped or truncated).  {ok, code} or {ok:false, message}.
static func parse_code(typed: String) -> Dictionary:
	var s := typed.to_upper().replace(" ", "").replace("-", "").replace("\t", "")
	if s.length() == 0:
		return {"ok": false, "message": "Enter the %d-character party code." % CODE_LEN}
	if s.length() != CODE_LEN:
		return {"ok": false, "message": "Party codes have %d characters (that one has %d)." % [CODE_LEN, s.length()]}
	for ch in s:
		if not CODE_ALPHABET.contains(ch):
			return {"ok": false, "message": "\"%s\" isn't used in party codes. Check the code and try again." % ch}
	return {"ok": true, "code": s}


## Code (already valid) or "".
static func normalize_code(code: String) -> String:
	var r := parse_code(code)
	return String(r["code"]) if bool(r["ok"]) else ""


## Stable 31-bit group number for a room code (Game Center player_group).
static func code_group(code: String) -> int:
	var v := 7
	for ch in normalize_code(code):
		v = (v * 33 + CODE_ALPHABET.find(ch) + 1) & 0x3FFFFFFF
	return maxi(v, 1)


## null where GameKit isn't there (desktop): callers then report that
## matchmaking is unavailable instead of failing on a null object.
func _request(code: String, host: bool) -> Object:
	var req: Object = _new_request()
	if req == null:
		return null
	_room_code = code
	_room_is_host = host
	req.set("min_players", 2)
	req.set("max_players", max_players())
	req.set("player_group", code_group(code))
	# (build 32) after Game Center called a request invalid, the simpler
	# one: no host/joiner roles
	if not simple_requests:
		req.set("player_attributes", ATTR_HOST if host else ATTR_JOINER)
	req.set("invite_message", "Join my Ultimate Trifecta room %s" % code)
	return req


## (build 32) Game Center's own limit for a real-time match (peer to peer),
## never more than the party's 8: asking for more than it allows makes every
## request "invalid".
func max_players() -> int:
	var m := 8
	if ClassDB.class_exists("GKMatchRequest"):
		var allowed: Variant = _static("GKMatchRequest", "max_players_allowed_for_match", [0])
		if (allowed is int) and int(allowed) >= 2:
			m = mini(m, int(allowed))
	return m


## (build 32) Game Center said the request is invalid: once, retry with the
## simpler request (no roles).  True when a retry was started.
func _retry_simpler(err: Variant) -> bool:
	if error_code(err) != GKERR_MATCH_REQUEST_INVALID or simple_requests:
		return false
	simple_requests = true
	push_warning("Game Center: match request invalid; retrying without player attributes")
	return true


## Host: open a code room. Returns the (not yet bound) transport.
func host_code_room(code: String) -> GameKitTransport:
	var t := GameKitTransport.new(true)
	_pending_transport = t
	_room_request = _request(code, true)
	_find_or_add()
	return t


func _new_request() -> Object:
	if kit != null:
		return kit.call("new_request")
	return ClassDB.instantiate("GKMatchRequest") if ClassDB.class_exists("GKMatchRequest") and ClassDB.can_instantiate("GKMatchRequest") else null


## A match nobody will use (its party ended, or another request won).
func _drop_match(m: Variant, t: GameKitTransport = null) -> void:
	if not (m is Object) or not is_instance_valid(m) or (t != null and t.gk_match == m):
		return
	if kit != null:
		kit.call("drop", m)
	else:
		(m as Object).call("disconnect")


## Join a room by code. Room discovery is retried by the NetSession if the
## match forms without the code's host (rare when two joiners meet first).
func join_code_room(code: String) -> GameKitTransport:
	var t := GameKitTransport.new(false)
	_pending_transport = t
	_room_request = _request(code, false)
	if not online_ready() or matchmaker == null or _room_request == null:
		room_failed.emit.call_deferred("Game Center matchmaking isn't available.")
		return t
	matchmaker.call("find_match", _room_request, func(m: Variant, err: Variant) -> void:
		_on_join_found.call_deferred(t, m, err))
	return t


func _on_join_found(t: GameKitTransport, m: Variant, err: Variant) -> void:
	if t != _pending_transport:
		_drop_match(m, t)     # (the join was cancelled or replaced meanwhile)
		return
	if err != null or not (m is Object) or not is_instance_valid(m):
		if _retry_simpler(err) and matchmaker != null:
			_room_request = _request(_room_code, false)
			matchmaker.call("find_match", _room_request, func(m2: Variant, err2: Variant) -> void:
				_on_join_found.call_deferred(t, m2, err2))
			return
		room_failed.emit(error_text(err) if err != null else "Game Center couldn't find that party.")
		return
	t.bind(m)
	room_matched.emit(t)


func _find_or_add() -> void:
	var t := _pending_transport
	if t == null or matchmaker == null or _room_request == null or _invite_live or not online_ready():
		return
	_room_gen += 1
	var gen := _room_gen
	if not t.bound():
		matchmaker.call("find_match", _room_request, func(m: Variant, err: Variant) -> void:
			_on_host_found.call_deferred(gen, t, m, err))
	elif not _adding:
		_adding = true
		matchmaker.call("add_players", t.gk_match, _room_request, func(e: Variant) -> void:
			_on_host_added.call_deferred(gen, t, e))


func _on_host_found(gen: int, t: GameKitTransport, m: Variant, err: Variant) -> void:
	if gen != _room_gen or t != _pending_transport:
		_drop_match(m, t)   # (2.3) replaced by an in-game invite, or the party ended: not a failure
		return
	if err != null or not (m is Object) or not is_instance_valid(m):
		if _retry_simpler(err):
			_room_request = _request(_room_code, true)
			_find_or_add()
			return
		room_failed.emit(error_text(err) if err != null else "Game Center couldn't open your party.")
		return
	t.bind(m)
	room_matched.emit(t)
	_find_or_add()


func _on_host_added(gen: int, t: GameKitTransport, err: Variant) -> void:
	_adding = false
	if gen != _room_gen or t != _pending_transport or t.peers().size() >= 7:
		return
	if err == null or error_code(err) == GKERR_CANCELLED:
		_add_fail = 0
		_find_or_add()
		return
	if _retry_simpler(err):
		_room_request = _request(_room_code, true)
		_find_or_add()
		return
	# a failing request waits before asking again (1, 2, 4 … 30 s)
	_add_fail += 1
	var wait := minf(pow(2.0, float(_add_fail - 1)), 30.0)
	get_tree().create_timer(wait).timeout.connect(func() -> void:
		if gen == _room_gen and t == _pending_transport:
			_find_or_add())


# ---------------------------------------------------------------------------
# 2.3: in-game invites (Game Center delivers them; no Apple sheet)
# ---------------------------------------------------------------------------
## GKInviteRecipientResponse as GodotApplePlugins maps it.
const INVITE_ACCEPTED := 0
const INVITE_DECLINED := 1
## (player, response) for each friend invited from the game's own list.
signal invite_answered(player: Object, response: int)
## An in-game invite couldn't be sent (message for the player).
signal invite_send_failed(message: String)
var _room_gen := 0
var _invite_live := false
var _invite_queue: Array = []     # [t, players] waiting while an invite is going out


## Invites these Game Center friends (GKPlayer objects from load_friends)
## to the party `t` hosts: Game Center sends each a notification, and their
## answers arrive on invite_answered.  The code room keeps working: its
## search pauses while the invite is out and resumes after.  False where
## Game Center can't send it (signed out, no GameKit).
func invite_players(t: GameKitTransport, _code: String, players: Array) -> bool:
	if not online_ready() or matchmaker == null or t == null:
		return false
	var picked: Array = players.filter(func(p: Variant) -> bool: return p is Object and is_instance_valid(p))
	if picked.is_empty():
		return false
	if _invite_live:
		# (one invite request at a time: a second used to cancel the first
		# mid-flight; it goes out when the first is done)
		_invite_queue.append([t, picked])
		return true
	return _send_invites(t, picked)


func _send_invites(t: GameKitTransport, picked: Array) -> bool:
	var req: Object = _new_request()
	if req == null:
		return false
	# no player group or attributes: those are for automatch, not invites
	req.set("min_players", 2)
	req.set("max_players", max_players())
	req.set("recipients", picked)
	req.set("invite_message", "Join my Ultimate Trifecta party!")
	req.set("recipient_response", func(p: Object, r: int) -> void:
		invite_answered.emit.call_deferred(p, r))
	_room_gen += 1          # the code room's open request ends quietly
	_invite_live = true
	matchmaker.call("cancel")
	_adding = false
	var done := func(err: Variant) -> void:
		_invite_live = false
		if err != null and error_code(err) != GKERR_CANCELLED:
			invite_send_failed.emit(error_text(err))
		while not _invite_queue.is_empty():
			var nx: Array = _invite_queue.pop_front()
			if nx[0] == _pending_transport and _send_invites(nx[0], nx[1]):
				return
		_find_or_add()       # back to welcoming code joiners
	if t.bound():
		matchmaker.call("add_players", t.gk_match, req, func(err: Variant) -> void:
			done.call_deferred(err))
	else:
		# (the whole answer on the main thread: binding is not thread-safe)
		matchmaker.call("find_match", req, func(m: Variant, err: Variant) -> void:
			(func() -> void:
				if m is Object and is_instance_valid(m) and err == null:
					if t == _pending_transport and not t.bound():
						t.bind(m)
						room_matched.emit(t)
					else:
						_drop_match(m, t)
				done.call(err)).call_deferred())
	return true


# ---------------------------------------------------------------------------
# 2.2: Quick Match (random players through Game Center automatch)
# ---------------------------------------------------------------------------
## Every Quick Match request of this protocol version shares one player
## group, so only games that can play together are matched.
const QUICK_GROUP_BASE := 0x51000000
signal quick_found(m: Object)
signal quick_failed(message: String)
var _quick_req: Object = null
var _quick_live := false


func quick_match_start() -> bool:
	if matchmaker == null or not online_ready():
		return false
	var req: Object = _new_request()
	if req == null:
		return false
	req.set("min_players", 2)
	req.set("max_players", max_players())
	req.set("player_group", QUICK_GROUP_BASE + Protocol.VERSION)
	_quick_req = req
	_quick_live = true
	matchmaker.call("find_match", req, func(m: Variant, err: Variant) -> void:
		_on_quick.call_deferred(m, err))
	return true


func _on_quick(m: Variant, err: Variant) -> void:
	if not _quick_live:
		_drop_match(m)
		return
	_quick_live = false
	if err != null or not (m is Object) or not is_instance_valid(m):
		quick_failed.emit(error_text(err))
		return
	quick_found.emit(m)


func quick_match_cancel() -> void:
	if _quick_live and matchmaker != null:
		matchmaker.call("cancel")
	_quick_live = false


## (2.2) Apple's Game Center Friends screen: your friends list, and "Add
## Friends", which sends a friend request by Game Center nickname.  False
## where Game Center isn't there.
func show_friends_list() -> bool:
	if not online_ready():
		return false
	if sheet_open():
		return true     # (one is up or opening: a double tap opens one)
	if kit != null:
		kit.call("show_type", 5)
	elif ClassDB.class_exists("GKGameCenterViewController"):
		ClassDB.class_call_static("GKGameCenterViewController", "show_type", 5)   # LOCAL_PLAYER_FRIENDS_LIST
	else:
		return false
	_sheet_up("gc_friends")
	return true


## (2.2) Leaderboards: a score sent to one board (Game Center keeps the best
## of the current 30-day occurrence).  Fire and forget; a failure is logged.
func submit_score(board_id: String, value: int) -> void:
	if not online_ready() or gc == null or not ClassDB.class_exists("GKLeaderboard"):
		return
	var lp: Object = gc.get("local_player")
	if lp == null:
		return
	ClassDB.class_call_static("GKLeaderboard", "load_leaderboards", PackedStringArray([board_id]), func(boards: Variant, err: Variant) -> void:
		if err != null or not (boards is Array) or (boards as Array).is_empty():
			push_warning("leaderboard %s unavailable: %s" % [board_id, error_text(err)])
			return
		var b: Object = (boards as Array)[0]
		b.call("submit_score", value, 0, lp, func(e: Variant) -> void:
			if e != null:
				push_warning("score to %s failed: %s" % [board_id, error_text(e)])))


## (2.2) One page of a leaderboard's current occurrence, for the Rankings
## screen.  done.call({ok, entries: [{rank, name, score, text, me}], me:
## {...} or {}, total, starts, ends, error}).
func load_board(board_id: String, friends_only: bool, first_entry: int, count: int, on_done: Callable) -> void:
	# (the answer reaches the Rankings screen on the main thread)
	var done := func(v: Dictionary) -> void: on_done.call_deferred(v)
	var first := first_entry
	if not online_ready() or not ClassDB.class_exists("GKLeaderboard"):
		done.call({"ok": false, "error": "signed_out"})
		return
	ClassDB.class_call_static("GKLeaderboard", "load_leaderboards", PackedStringArray([board_id]), func(boards: Variant, err: Variant) -> void:
		if err != null or not (boards is Array) or (boards as Array).is_empty():
			done.call({"ok": false, "error": error_text(err) if err != null else "missing"})
			return
		var b: Object = (boards as Array)[0]
		var starts := float(b.get("startDate"))
		var dur := float(b.get("duration"))
		b.call("load_local_player_entries", 1 if friends_only else 0, 2, first, count, func(local: Variant, entries: Variant, total: Variant, e: Variant) -> void:
			if e != null:
				done.call({"ok": false, "error": error_text(e)})
				return
			var out: Array = []
			var my_id := local_match_id()
			if entries is Array:
				for en in entries:
					if en != null:
						out.append(_entry_dict(en, my_id))
			done.call({"ok": true, "entries": out, "me": _entry_dict(local, my_id) if local != null else {},
				"total": int(total) if total != null else out.size(), "starts": starts, "ends": starts + dur if dur > 0.0 else 0.0})))


func _entry_dict(en: Object, my_id: String) -> Dictionary:
	var pl: Object = en.get("player")
	var pid := ""
	var name := "Player"
	if pl != null:
		pid = String(pl.get("team_player_id")) if String(pl.get("team_player_id")) != "" else String(pl.get("game_player_id"))
		name = String(pl.get("display_name"))
	return {"rank": int(en.get("rank")), "score": int(en.get("score")), "text": String(en.get("formattedScore")),
		"name": NameRules.safe_display(name, pid), "me": pid != "" and pid == my_id}


## (2.2) Apple's Game Center leaderboard screen for one board.
func show_leaderboard(id: String, friends_only: bool = false) -> bool:
	if not online_ready() or not ClassDB.class_exists("GKGameCenterViewController"):
		return false
	ClassDB.class_call_static("GKGameCenterViewController", "show_leaderboard_time_period", id, 1 if friends_only else 0, 2)
	return true


## The local player's id as GameKitTransport names remote players.
func local_match_id() -> String:
	return team_player_id if team_player_id != "" else local_player_id


## Host stops accepting code joins (room full / leaving).
func stop_matchmaking() -> void:
	if matchmaker != null and authenticated:
		matchmaker.call("cancel")
	_pending_transport = null
	_adding = false
	_add_fail = 0
	_invite_queue.clear()


## Apple's invite UI: invite Game Center friends to this room (no automatch).
## `recipients` (GKPlayer objects from load_friends) pre-selects friends in
## Apple's sheet (GKMatchRequest.recipients); the player still sends it there.
## False when it didn't open: signed out, no GameKit, not this party's
## transport, or another Apple sheet already up (a double tap opens one).
func invite_friends(t: GameKitTransport, code: String, recipients: Array = []) -> bool:
	if not online_ready() or matchmaker == null or t == null:
		return false
	if sheet_open():
		return false
	var req := _request(code, true)
	if req == null:
		room_failed.emit("Could not open the Game Center invite screen.")
		return false
	var picked: Array = recipients.filter(func(p: Variant) -> bool: return p is Object and is_instance_valid(p))
	if not picked.is_empty():
		req.set("recipients", picked)
	var vc: Object = _create_controller(req)
	if vc == null:
		room_failed.emit("Could not open the Game Center invite screen.")
		return false
	vc.set("matchmaking_mode", 3)  # invite only: friends, never strangers
	vc.set("can_start_with_minimum_players", true)
	if t.bound():
		vc.call("add_players_to_match", t.gk_match)
	else:
		matchmaker.call("cancel")
	vc.connect("did_find_match", func(m: Object) -> void: _on_sheet_match.call_deferred(vc, t, m))
	vc.connect("cancelled", func(_d: String) -> void: _on_sheet_end.call_deferred(vc, ""))
	vc.connect("failed_with_error", func(msg: String) -> void: _on_sheet_end.call_deferred(vc, msg))
	_invite_vc = vc
	_sheet_up("invite")
	vc.call("present")
	return true


func _create_controller(req: Object) -> Object:
	if kit != null:
		return kit.call("create_controller", req)
	if not ClassDB.class_exists("GKMatchmakerViewController"):
		return null
	return _static("GKMatchmakerViewController", "create_controller", [req])


func _on_sheet_match(vc: Object, t: GameKitTransport, m: Variant) -> void:
	_sheet_closed(vc)
	if not (m is Object) or not is_instance_valid(m):
		_find_or_add()
		return
	if t != _pending_transport:
		_drop_match(m, t)    # (the party this sheet was for ended while it was up)
		return
	t.bind(m)
	room_matched.emit(t)
	_find_or_add()


func _on_sheet_end(vc: Object, message: String) -> void:
	_sheet_closed(vc)
	if message != "":
		room_failed.emit(message)
	_find_or_add()


func _on_invite_accepted(_player: Object, invite: Object) -> void:
	# We were invited by a friend: join their room as a client.  (2.3)
	# Straight into the party (no Apple sheet); the sheet only if that fails.
	if invite == null or not is_instance_valid(invite) or not authenticated or matchmaker == null:
		return
	var now := Time.get_ticks_msec()
	if invite == _accepting_invite or (_accepting_invite != null and now - _accepting_at < 10000.0):
		return    # (the same invite again, or one already joining: handled once)
	_accepting_invite = invite
	_accepting_at = now
	var t := GameKitTransport.new(false)
	if matchmaker.has_method("match_for_invite"):
		invite_joining.emit()
		matchmaker.call("match_for_invite", invite, func(m: Variant, err: Variant) -> void:
			_on_invite_match.call_deferred(invite, t, m, err))
		return
	_accepting_invite = null
	_invite_sheet(invite, t)


func _on_invite_match(invite: Object, t: GameKitTransport, m: Variant, err: Variant) -> void:
	_accepting_invite = null
	if m is Object and is_instance_valid(m) and err == null:
		t.bind(m)
		invite_ready.emit(t)
	elif is_instance_valid(invite):
		_invite_sheet(invite, t)


## Apple's invite sheet for an accepted invite (the fallback).  Never over
## another sheet (it would replace that sheet's delegate, see above).
func _invite_sheet(invite: Object, t: GameKitTransport) -> void:
	if not authenticated or invite == null or not is_instance_valid(invite):
		return
	if sheet_open():
		room_failed.emit("Close the Game Center screen, then accept the invite again.")
		return
	var vc: Object = null
	if kit != null:
		vc = kit.call("create_controller_from_invite", invite)
	elif ClassDB.class_exists("GKMatchmakerViewController"):
		vc = _static("GKMatchmakerViewController", "create_controller_from_invite", [invite])
	if vc == null:
		return
	vc.connect("did_find_match", func(m: Object) -> void:
		(func() -> void:
			_sheet_closed(vc)
			if m != null and is_instance_valid(m):
				t.bind(m)
				invite_ready.emit(t)).call_deferred())
	vc.connect("cancelled", func(_d: String) -> void: _sheet_closed.call_deferred(vc))
	vc.connect("failed_with_error", func(msg: String) -> void:
		(func() -> void:
			_sheet_closed(vc)
			room_failed.emit(msg)).call_deferred())
	_invite_vc = vc
	_sheet_up("invite_accept")
	vc.call("present")


## Tests: forget sheets, queues and the invite being joined.
func reset_for_tests() -> void:
	_sheet = ""
	_invite_vc = null
	_invite_queue.clear()
	_invite_live = false
	_accepting_invite = null
	_accepting_at = -1.0e12
	_add_fail = 0
	_adding = false


# ---------------------------------------------------------------- friends
## GKFriendsAuthorizationStatus raw values (GameKit): notDetermined 0,
## restricted 1, denied 2, authorized 3.
const FRIENDS_ACCESS := ["not_determined", "restricted", "denied", "authorized"]
## GodotApplePlugins GKError.Code values for the friend-list errors.
const GKERR_NOT_AUTHENTICATED := 14
const GKERR_CANCELLED := 4
const GKERR_MATCH_REQUEST_INVALID := 13
const GKERR_FRIEND_LIST_RESTRICTED := 26
const GKERR_FRIEND_LIST_DENIED := 27


## A readable message from a GodotApplePlugins GKError (or anything else).
static func error_text(err: Variant) -> String:
	if err is Object and is_instance_valid(err):
		var m := String((err as Object).get("message")) if "message" in (err as Object) else ""
		if m != "":
			return m
	return str(err)


static func error_code(err: Variant) -> int:
	if err is Object and is_instance_valid(err) and "code" in (err as Object):
		return int((err as Object).get("code"))
	return -1


## Friends-list access without asking (no prompt): `done.call(status)` with
## not_determined | restricted | denied | authorized | unavailable.
func friends_access(done: Callable) -> void:
	if not online_ready() or gc == null:
		done.call("unavailable")
		return
	var lp: Object = gc.get("local_player")
	lp.call("load_friends_authorization_status", func(status: int, err: Variant) -> void:
		var code: String = "unavailable" if err != null and status == 0 else (String(FRIENDS_ACCESS[status]) if status >= 0 and status < 4 else "unavailable")
		# (GameKit may answer off the main thread: hand over to it)
		done.call_deferred(code))


## The friends list.  The first call asks for friends-list permission with
## NSGKFriendListUsageDescription (Apple shows its sheet); later calls answer
## at once.  Emits friends_loaded.
func load_friends() -> void:
	if not online_ready() or gc == null:
		friends_loaded.emit([], "signed_out")
		return
	var lp: Object = gc.get("local_player")
	lp.call("load_friends", func(friends: Array, err: Variant) -> void:
		_friends_answer.call_deferred(friends, err))


func _friends_answer(friends: Array, err: Variant) -> void:
	if err != null:
		var c := error_code(err)
		var why := "denied" if c == GKERR_FRIEND_LIST_DENIED else ("restricted" if c == GKERR_FRIEND_LIST_RESTRICTED else
			("signed_out" if c == GKERR_NOT_AUTHENTICATED else "error"))
		friends_loaded.emit([], why)
		return
	var out: Array = []
	for f in friends:
		if not (f is Object) or not is_instance_valid(f):
			continue
		var tid := String((f as Object).get("team_player_id"))
		if tid == "":
			continue    # (no team-scoped ID: nothing the service could ever match)
		out.append({"tid": tid, "gid": String((f as Object).get("game_player_id")), "name": String((f as Object).get("display_name")), "player": f})
	friends_loaded.emit(out, "")
