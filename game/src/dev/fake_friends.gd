extends RefCounted
## TEST DOUBLE (src/dev: never exported).  Stand-ins for the two sides of
## Friends, for client tests and labelled desktop captures:
##   Native   Game Center's friends list and friends-list permission (what
##            Social does on iOS through GodotApplePlugins)
##   service  the Friends routes of the game service (service/src/friends.js,
##            tested on its own with node --test), answering through
##            Cloud.transport_override: friend upload, mutual-friend status,
##            heartbeats, invites, accept/decline, and the room join the
##            accept hands over to.  "Mutual" is scripted here (`mutual`), not
##            computed: the real rules are the service's and its tests'.
## Nothing here is a device, Game Center or a deployment.
##
## Use: var ff := FakeFriends.new(); ff.install(); ... ff.uninstall()

var native: Native
## tid -> {name, status (online|lobby|match|offline), profile_id, why?,
## in_your_party?}: friends whose own game uploaded this player too
var mutual: Dictionary = {}
var uploaded: Array = []         # the last PUT /v1/friends ids
var incoming: Array = []         # invites waiting for this player
var invited: Dictionary = {}     # tid -> invite id (sent by this player)
var calls: Array = []            # [method, path, body]
var network_down := false
var unavailable := false         # the service answers 503
var invite_error: Dictionary = {}    # a forced error for POST /v1/invites
var accept_reply: Dictionary = {"ok": true, "code": "ACDEFG", "host_name": "Host Otter", "from_name": "Comfy Frog"}
var join_reply: Dictionary = {"status": 409, "body": {"ok": false, "error": "full", "message": "That party is full."}}
var room_code := "QRTWXY"
var clock_ms: Callable
var _n := 0


func _init() -> void:
	native = Native.new()


func now_ms() -> float:
	return float(clock_ms.call()) if clock_ms.is_valid() else Time.get_unix_time_from_system() * 1000.0


func install() -> void:
	Cloud.transport_override = handle
	Cloud.identity_override = func() -> Dictionary:
		return {"ok": true, "player_id": "T:_me", "bundle_id": Social.BUNDLE_ID, "timestamp": 1, "salt": "c2FsdA==",
			"signature": "c2ln", "public_key_url": "https://static.gc.apple.com/public-key/gc-prod-10.cer"}
	Cloud.service_config = {"ok": true, "features": ["chat", "message_reports", "shop_offers", "friends"], "min_build": 0}
	Friends.native = native


func uninstall() -> void:
	Cloud.transport_override = Callable()
	Cloud.identity_override = Callable()
	Cloud.service_config = {}
	Cloud.token = ""
	Cloud.profile = {}
	Cloud.state = "signed_out" if Cloud.configured() else "off"
	Friends.native = Friends.NativeFriends.new()


func count(method: int, path: String) -> int:
	return calls.filter(func(c: Array) -> bool: return int(c[0]) == method and String(c[1]) == path).size()


func add_invite(from_name: String, from_tid: String, seconds: float = 300.0, from_host: bool = true, host_name: String = "") -> Dictionary:
	_n += 1
	var iv := {"id": "inv_test%04d" % _n, "created_at": now_ms(), "expires_at": now_ms() + seconds * 1000.0,
		"from": {"id": from_tid, "profile_id": "p_" + from_tid.trim_prefix("T:_"), "name": from_name},
		"from_host": from_host, "host_name": host_name if host_name != "" else (from_name if from_host else "Host Otter")}
	incoming.append(iv)
	return iv


func _ok(body: Dictionary, status: int = 200) -> Dictionary:
	body["ok"] = true
	body["server_time"] = now_ms()
	return {"status": status, "body": body}


func _live_invites() -> Array:
	return incoming.filter(func(iv: Dictionary) -> bool: return float(iv["expires_at"]) > now_ms())


func handle(method: int, path: String, body: Variant, _headers: PackedStringArray) -> Dictionary:
	calls.append([method, path, body])
	if network_down:
		return {"status": 0, "body": {"ok": false, "error": "network", "message": "Couldn't reach the game service. Check your connection."}}
	if path == "/v1/auth/gamecenter":
		return _ok({"token": "tok-friends", "expires_at": int(now_ms()) + 3600000,
			"profile": {"profile_id": "p_me", "display_name": "Quiet Duck", "discriminator": "0007", "needs_name": false}})
	if unavailable:
		return {"status": 503, "body": {"ok": false, "error": "not_configured", "message": "Friends aren't set up on this server."}}
	if path == "/v1/friends" and method == HTTPClient.METHOD_PUT:
		uploaded = (body as Dictionary).get("ids", [])
		return _ok({"count": uploaded.size(), "synced_at": now_ms()})
	if path == "/v1/friends" and method == HTTPClient.METHOD_DELETE:
		uploaded = []
		return _ok({})
	if path == "/v1/friends/presence":
		var out: Array = []
		var party_in := Friends.in_party()
		for tid in uploaded:
			if not mutual.has(tid):
				continue
			var m: Dictionary = mutual[tid]
			var st := String(m.get("status", "offline"))
			var inp := bool(m.get("in_your_party", false))
			var why: Variant = m.get("why")
			if inp:
				why = "in_your_party"
			elif st == "offline":
				why = "offline"
			elif invited.has(tid):
				why = "invited"
			out.append({"id": tid, "profile_id": String(m.get("profile_id", "p_" + String(tid).trim_prefix("T:_"))), "name": m.get("name"),
				"discriminator": "0001", "status": st, "in_your_party": inp, "invited": invited.has(tid), "can_invite": why == null, "why": why})
		return _ok({"poll_s": 10, "shared": not uploaded.is_empty(), "friends": out,
			"party": {"joinable": true, "why": null, "members": 1, "capacity": 8, "host": true} if party_in else null})
	if path == "/v1/presence" and method == HTTPClient.METHOD_POST:
		return _ok({"status": String((body as Dictionary).get("state", "online")), "room_verified": (body as Dictionary).has("room"),
			"stale": false, "written": true, "interval_s": 20, "ttl_s": 60, "invites": _live_invites()})
	if path == "/v1/presence" and method == HTTPClient.METHOD_DELETE:
		return _ok({})
	if path == "/v1/invites" and method == HTTPClient.METHOD_POST:
		if not invite_error.is_empty():
			return {"status": int(invite_error.get("status", 409)), "body": invite_error.get("body", {})}
		var to := String((body as Dictionary).get("to", ""))
		if not mutual.has(to):
			return {"status": 404, "body": {"ok": false, "error": "not_friend", "message": "You can invite Game Center friends who also play Ultimate Trifecta and have Friends turned on."}}
		_n += 1
		invited[to] = "inv_sent%04d" % _n
		return _ok({"invite": {"id": invited[to], "to": to, "expires_at": now_ms() + 300000.0}}, 201)
	if path == "/v1/invites" and method == HTTPClient.METHOD_GET:
		return _ok({"invites": _live_invites()})
	if path.begins_with("/v1/invites/") and path.ends_with("/accept"):
		var id := path.get_slice("/", 3)
		incoming = incoming.filter(func(iv: Dictionary) -> bool: return String(iv["id"]) != id)
		if bool(accept_reply.get("ok", false)):
			return _ok(accept_reply.duplicate())
		return {"status": int(accept_reply.get("status", 409)), "body": accept_reply.duplicate()}
	if path.begins_with("/v1/invites/") and path.ends_with("/decline"):
		var id2 := path.get_slice("/", 3)
		incoming = incoming.filter(func(iv: Dictionary) -> bool: return String(iv["id"]) != id2)
		return _ok({})
	if path == "/v1/rooms" and method == HTTPClient.METHOD_POST:
		return _ok({"room": {"room_id": "room_test", "code": room_code, "state": "forming", "capacity": 8, "members": 1, "protocol": Protocol.VERSION,
			"build": App.build_number(), "heartbeat_interval_s": 15}, "slot": 0}, 201)
	if path.begins_with("/v1/rooms/") and path.ends_with("/join"):
		return join_reply.duplicate(true)
	if path.begins_with("/v1/rooms/"):
		return _ok({"room": {"code": room_code, "state": "open"}, "members": []})
	if path == "/v1/me/appearance":
		return _ok({})
	return {"status": 404, "body": {"ok": false, "error": "no_route", "message": "Not found."}}


## Game Center's side: availability, sign-in, Screen Time, friends-list
## permission (the first load asks, then answers `prompt_result`).
class Native:
	extends RefCounted
	var avail := true
	var signed := true
	var mp_off := false
	var access := "authorized"       # not_determined | authorized | denied | restricted
	var prompt_result := "authorized"
	var list: Array = []             # [{tid, gid, name, player}]
	var load_error := ""
	var calls: Array = []

	func available() -> bool:
		return avail

	func signed_in() -> bool:
		return avail and signed

	func multiplayer_off() -> bool:
		return mp_off

	func status() -> String:
		calls.append("status")
		return access

	func load() -> Dictionary:
		calls.append("load")
		if access == "not_determined":
			access = prompt_result     # Apple's sheet answered
		if access == "denied" or access == "restricted":
			return {"friends": [], "error": access}
		if load_error != "":
			return {"friends": [], "error": load_error}
		return {"friends": list.duplicate(true), "error": ""}

	## Fictional friends: [name, tid] pairs.
	func set_friends(pairs: Array) -> void:
		list = []
		for p in pairs:
			list.append({"tid": String(p[1]), "gid": "G:" + String(p[1]).trim_prefix("T:_"), "name": String(p[0]), "player": null})
