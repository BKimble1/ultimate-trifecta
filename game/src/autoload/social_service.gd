extends Node
## Game Center identity, friends and private-room matchmaking (iOS).
## - Code rooms: everyone in a room uses the same GKMatchRequest.player_group
##   derived from the short room code; the host keeps adding players.
## - Friends: Apple's GKMatchmakerViewController invite UI (invite-only, no
##   strangers) and the friends list (permission requested only when opened).
## If Game Center is unavailable or declined, solo practice still works and the
## online buttons explain why they are disabled. Nothing here is mocked.

signal auth_changed(ok: bool)
signal invite_ready(transport: GameKitTransport)     # an accepted invite produced a match (we are a client)
signal room_matched(transport: GameKitTransport)     # code/invite matchmaking produced a GKMatch
signal room_failed(message: String)
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


func _on_auth(ok: bool) -> void:
	authenticated = ok
	if ok:
		var lp: Object = gc.get("local_player")
		local_player_id = String(lp.get("game_player_id"))
		team_player_id = String(lp.get("team_player_id"))
		display_name = String(lp.get("display_name"))
		multiplayer_restricted = bool(lp.get("is_multiplayer_gaming_restricted"))
		lp.call("register_listener")
		if not lp.is_connected("invite_accepted", _on_invite_accepted):
			lp.connect("invite_accepted", _on_invite_accepted)
		matchmaker = ClassDB.instantiate("GKMatchmaker")
	auth_changed.emit(ok)


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
		return {"ok": false, "message": "Game Center couldn't confirm your identity (%s)." % str(done["v"]["error"])}
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


func _request(code: String, host: bool) -> Object:
	var req: Object = ClassDB.instantiate("GKMatchRequest")
	req.set("min_players", 2)
	req.set("max_players", 8)
	req.set("player_group", code_group(code))
	req.set("player_attributes", ATTR_HOST if host else ATTR_JOINER)
	req.set("invite_message", "Join my Ultimate Trifecta room %s" % code)
	return req


## Host: open a code room. Returns the (not yet bound) transport.
func host_code_room(code: String) -> GameKitTransport:
	var t := GameKitTransport.new(true)
	_pending_transport = t
	_room_request = _request(code, true)
	_find_or_add()
	return t


## Join a room by code. Room discovery is retried by the NetSession if the
## match forms without the code's host (rare when two joiners meet first).
func join_code_room(code: String) -> GameKitTransport:
	var t := GameKitTransport.new(false)
	_pending_transport = t
	_room_request = _request(code, false)
	matchmaker.call("find_match", _room_request, func(m: Object, err: Variant) -> void:
		if err != null:
			room_failed.emit(str(err))
			return
		t.bind(m)
		room_matched.emit(t))
	return t


func _find_or_add() -> void:
	var t := _pending_transport
	if t == null or matchmaker == null:
		return
	if not t.bound():
		matchmaker.call("find_match", _room_request, func(m: Object, err: Variant) -> void:
			if err != null:
				if t == _pending_transport:
					room_failed.emit(str(err))
				return
			t.bind(m)
			room_matched.emit(t)
			_find_or_add())
	elif not _adding:
		_adding = true
		matchmaker.call("add_players", t.gk_match, _room_request, func(_e: Variant) -> void:
			_adding = false
			if t == _pending_transport and t.peers().size() < 7:
				_find_or_add())


## Host stops accepting code joins (room full / leaving).
func stop_matchmaking() -> void:
	if matchmaker != null:
		matchmaker.call("cancel")
	_pending_transport = null
	_adding = false


## Apple's invite UI: invite Game Center friends to this room (no automatch).
func invite_friends(t: GameKitTransport, code: String) -> void:
	if not online_ready():
		return
	var req := _request(code, true)
	var vc: Object = _static("GKMatchmakerViewController", "create_controller", [req])
	if vc == null:
		room_failed.emit("Could not open the Game Center invite screen.")
		return
	vc.set("matchmaking_mode", 3)  # invite only: friends, never strangers
	vc.set("can_start_with_minimum_players", true)
	if t.bound():
		vc.call("add_players_to_match", t.gk_match)
	else:
		matchmaker.call("cancel")
	vc.connect("did_find_match", func(m: Object) -> void:
		t.bind(m)
		room_matched.emit(t)
		_find_or_add())
	vc.connect("cancelled", func(_d: String) -> void: _find_or_add())
	vc.connect("failed_with_error", func(msg: String) -> void:
		room_failed.emit(msg)
		_find_or_add())
	_invite_vc = vc
	vc.call("present")


func _on_invite_accepted(_player: Object, invite: Object) -> void:
	# We were invited by a friend: join their room as a client.
	var t := GameKitTransport.new(false)
	var vc: Object = _static("GKMatchmakerViewController", "create_controller_from_invite", [invite])
	if vc == null:
		return
	vc.connect("did_find_match", func(m: Object) -> void:
		t.bind(m)
		invite_ready.emit(t))
	vc.connect("failed_with_error", func(msg: String) -> void: room_failed.emit(msg))
	_invite_vc = vc
	vc.call("present")


## Friends list (requests friends-list permission the first time).
func load_friends() -> void:
	if not online_ready():
		friends_loaded.emit([], "Game Center is not signed in.")
		return
	var lp: Object = gc.get("local_player")
	lp.call("load_friends", func(friends: Array, err: Variant) -> void:
		if err != null:
			friends_loaded.emit([], str(err))
			return
		var out: Array = []
		for f in friends:
			out.append({"name": String(f.get("display_name")), "id": String(f.get("game_player_id"))})
		friends_loaded.emit(out, ""))
