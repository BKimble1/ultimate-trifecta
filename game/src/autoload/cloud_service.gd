extends Node
## Client for the Ultimate Trifecta service (service/): verified Game Center
## sign-in, the player's online profile and name, blocks, reports, profile
## deletion, and party rooms with admission.  Autoload "Cloud".
##
## Configuration lives in res://config/service.cfg.  With no URL configured
## the service is "off": practice and local play work, online names stay
## local, and nothing pretends to be verified.  Network failures are reported
## as such and never treated as success.

signal changed

const CFG_PATH := "res://config/service.cfg"
const TIMEOUT_S := 12.0

var base_url := ""
var admission_key: CryptoKey
var token := ""
var token_exp_ms := 0
var profile: Dictionary = {}       # profile_id, display_name, discriminator, needs_name, status, ...
var state := "off"                 # off | signed_out | signing_in | ready | error
var last_error := ""
var _signing_in := false
## tests and the dev harness can replace the HTTP layer: func(method, path, body, headers) -> {status, body}
var transport_override: Callable
## tests replace Game Center's identity signature: func() -> {ok, player_id, ...}
var identity_override: Callable


func _ready() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG_PATH) == OK:
		base_url = String(cf.get_value("service", "url", "")).strip_edges().trim_suffix("/")
		admission_key = Admission.load_public_key(String(cf.get_value("service", "admission_public_key", "")))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--service-url="):
			base_url = a.get_slice("=", 1).trim_suffix("/")
	state = "signed_out" if configured() else "off"


func configured() -> bool:
	return base_url != "" or transport_override.is_valid()


func signed_in() -> bool:
	return state == "ready" and token != ""


func profile_id() -> String:
	return String(profile.get("profile_id", ""))


## "Name#1234" for the verified online name, or "" if none yet.
func full_name() -> String:
	var n: Variant = profile.get("display_name")
	if n == null or String(n) == "":
		return ""
	return "%s#%s" % [n, profile.get("discriminator", "0000")]


# ------------------------------------------------------------------ HTTP
func _http(method: int, path: String, body: Variant, auth: bool) -> Dictionary:
	var headers := PackedStringArray(["Accept: application/json"])
	if body != null:
		headers.append("Content-Type: application/json")
	if auth and token != "":
		headers.append("Authorization: Bearer %s" % token)
	if transport_override.is_valid():
		return await transport_override.call(method, path, body, headers)
	var h := HTTPRequest.new()
	h.timeout = TIMEOUT_S
	add_child(h)
	var err := h.request(base_url + path, headers, method, JSON.stringify(body) if body != null else "")
	if err != OK:
		h.queue_free()
		return {"status": 0, "body": {"ok": false, "error": "network", "message": "Couldn't reach the game service. Check your connection."}}
	var res: Array = await h.request_completed
	h.queue_free()
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"status": 0, "body": {"ok": false, "error": "network", "message": "Couldn't reach the game service. Check your connection."}}
	var parsed: Variant = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if not (parsed is Dictionary):
		return {"status": int(res[1]), "body": {"ok": false, "error": "bad_response", "message": "The game service sent an unexpected reply."}}
	return {"status": int(res[1]), "body": parsed}


## Authenticated call; signs in (or back in) with Game Center when needed.
func api(method: int, path: String, body: Variant = null) -> Dictionary:
	if not configured():
		return {"ok": false, "error": "service_off", "message": "Online profiles aren't set up in this build."}
	if not signed_in() or Time.get_unix_time_from_system() * 1000.0 > token_exp_ms - 60000:
		var s := await sign_in()
		if not bool(s.get("ok", false)):
			return s
	var r := await _http(method, path, body, true)
	if int(r["status"]) == 401 and String(r["body"].get("error", "")) in ["session_expired", "signed_out"]:
		token = ""
		var s2 := await sign_in()
		if not bool(s2.get("ok", false)):
			return s2
		r = await _http(method, path, body, true)
	var out: Dictionary = r["body"]
	out["http_status"] = int(r["status"])
	if out.has("profile") and out["profile"] is Dictionary:
		_set_profile(out["profile"])
	return out


func _set_profile(p: Dictionary) -> void:
	profile = p
	Save.data["cloud_profile"] = {"profile_id": p.get("profile_id", ""), "display_name": p.get("display_name"),
		"discriminator": p.get("discriminator")}
	Save.mark()
	changed.emit()


# ------------------------------------------------------------------ sign-in
## Verified sign-in: Game Center signs our identity, the service checks it.
func sign_in() -> Dictionary:
	if not configured():
		return {"ok": false, "error": "service_off", "message": "Online profiles aren't set up in this build."}
	if _signing_in:
		while _signing_in:
			await get_tree().process_frame
		return {"ok": signed_in(), "error": "" if signed_in() else last_error}
	_signing_in = true
	state = "signing_in"
	changed.emit()
	var ident: Dictionary
	if identity_override.is_valid():
		ident = await identity_override.call()
	else:
		ident = await Social.identity_signature()
	var out: Dictionary
	var ok := false
	token = ""
	if not bool(ident.get("ok", false)):
		out = {"ok": false, "error": "game_center", "message": String(ident.get("message", "Sign in to Game Center to play online."))}
	else:
		var body := {"player_id": ident["player_id"], "bundle_id": ident["bundle_id"], "timestamp": ident["timestamp"],
			"salt": ident["salt"], "signature": ident["signature"], "public_key_url": ident["public_key_url"]}
		var r := await _http(HTTPClient.METHOD_POST, "/v1/auth/gamecenter", body, false)
		out = r["body"]
		if int(r["status"]) == 200 and bool(out.get("ok", false)) and String(out.get("token", "")) != "":
			token = String(out["token"])
			token_exp_ms = int(out.get("expires_at", 0))
			ok = true
			_set_profile(out["profile"])
	_signing_in = false
	# (not signed_in(): that reads `state`, which is still "signing_in" here)
	state = "ready" if ok else "error"
	last_error = "" if ok else String(out.get("message", "Sign-in failed."))
	changed.emit()
	return out


func sign_out() -> Dictionary:
	var r := {"ok": true}
	if signed_in():
		var res := await _http(HTTPClient.METHOD_POST, "/v1/auth/signout", {}, true)
		r = res["body"]
	token = ""
	state = "signed_out" if configured() else "off"
	changed.emit()
	return r


# ------------------------------------------------------------------ profile
func set_display_name(name: String) -> Dictionary:
	return await api(HTTPClient.METHOD_POST, "/v1/me/name", {"name": NameRules.normalize(name)})


func check_name(name: String) -> Dictionary:
	return await api(HTTPClient.METHOD_POST, "/v1/names/check", {"name": NameRules.normalize(name)})


func set_appearance(app: Dictionary) -> Dictionary:
	return await api(HTTPClient.METHOD_PUT, "/v1/me/appearance", {"appearance": Cosmetics.sanitize(app)})


func refresh_profile() -> Dictionary:
	return await api(HTTPClient.METHOD_GET, "/v1/me")


## Deletes the online profile.  The service requires a sign-in from the last
## few minutes, so this signs in again first (Game Center confirms it's you).
func delete_profile() -> Dictionary:
	token = ""
	var s := await sign_in()
	if not bool(s.get("ok", false)):
		return s
	var r := await api(HTTPClient.METHOD_DELETE, "/v1/me", {"confirm": "DELETE"})
	if bool(r.get("ok", false)):
		token = ""
		profile = {}
		state = "signed_out"
		changed.emit()
	return r


# ------------------------------------------------------------------ safety
func report(target_pid: String, reason: String, details: String, context: Dictionary) -> Dictionary:
	return await api(HTTPClient.METHOD_POST, "/v1/reports", {"profile_id": target_pid, "reason": reason,
		"details": details.substr(0, 500), "context": context})


func block(target_pid: String) -> Dictionary:
	return await api(HTTPClient.METHOD_POST, "/v1/blocks", {"profile_id": target_pid})


func unblock(target_pid: String) -> Dictionary:
	return await api(HTTPClient.METHOD_DELETE, "/v1/blocks/%s" % target_pid.uri_encode())


func list_blocks() -> Dictionary:
	return await api(HTTPClient.METHOD_GET, "/v1/blocks")


# ------------------------------------------------------------------ rooms
func create_room(capacity: int = 8) -> Dictionary:
	return await api(HTTPClient.METHOD_POST, "/v1/rooms", {"build": App.build_number(), "protocol": Protocol.VERSION, "capacity": capacity})


func join_room(code: String) -> Dictionary:
	return await api(HTTPClient.METHOD_POST, "/v1/rooms/%s/join" % code.uri_encode(), {"build": App.build_number(), "protocol": Protocol.VERSION})


func room_heartbeat(code: String, room_state: String, connected_pids: Array) -> Dictionary:
	var body := {"connected": connected_pids}
	if room_state != "":
		body["state"] = room_state
	return await api(HTTPClient.METHOD_POST, "/v1/rooms/%s/heartbeat" % code.uri_encode(), body)


func leave_room(code: String) -> Dictionary:
	return await api(HTTPClient.METHOD_POST, "/v1/rooms/%s/leave" % code.uri_encode(), {})


func kick_from_room(code: String, pid: String) -> Dictionary:
	return await api(HTTPClient.METHOD_POST, "/v1/rooms/%s/kick" % code.uri_encode(), {"profile_id": pid})


## Player-facing wording for the service's error codes.
static func explain(r: Dictionary) -> String:
	var m := String(r.get("message", ""))
	match String(r.get("error", "")):
		"network":
			return "Couldn't reach the game service. Check your connection and try again."
		"service_off":
			return "Online parties aren't set up in this build."
		"game_center":
			return m if m != "" else "Sign in to Game Center (Settings › Game Center) to play online."
	return m if m != "" else "Something went wrong. Please try again."
