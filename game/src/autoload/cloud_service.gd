extends Node
## Client for the Ultimate Trifecta service (service/): verified Game Center
## sign-in, the player's online profile and name, blocks, reports, profile
## deletion, and party rooms with admission.  Autoload "Cloud".
##
## Configuration lives in res://config/service.cfg.  With no URL configured
## the service is "off": practice and local play work, online names stay
## local, and nothing pretends to be verified.  Network failures are reported
## as such and never treated as success.
##
## FINAL_RELEASE_SWEEP: two deployments, one build (docs/final/commerce.md).
## service.cfg names the App Store deployment (production_url,
## production_admission_public_key) and the sandbox one (sandbox_url,
## sandbox_admission_public_key); the old single url /
## admission_public_key is a development fallback.  Each deployment has its
## own database and credits only its own App Store environment, so which one
## an install talks to is a routing choice, never a permission:
##  - at launch, from a hint: on iOS the App Store receipt's kind (UTShare
##    receipt_kind(): "sandboxReceipt" -> sandbox (TestFlight, Xcode and
##    simulator builds), "receipt" -> production (App Store)); no receipt
##    URL, an unknown name, or an older native library without the call ->
##    production.  Production is the safe default: it credits only
##    Production-signed purchases, and the sandbox only holds an isolated
##    economy worth nothing.  Desktop and tests use the sandbox.
##  - automatically, once per launch, when a deployment refuses a verified
##    Apple purchase as the other environment's (409 sandbox_purchase in App
##    Review, production_purchase): move_to() signs out here, signs in there
##    with the same Game Center player (the same appAccountToken) and the
##    still-unfinished transaction is delivered there.  The move is kept for
##    this install (user://service_route.cfg) while its receipt kind stays
##    the same, and waits while a party is open (a room lives in one
##    deployment).
## There is no user-facing switch.  Everything else calls the service only
## through this node, so it follows the routing by itself.

signal changed
## FINAL_RELEASE_SWEEP: the install moved to another deployment
signal deployment_changed(from: String, to: String)

const CFG_PATH := "res://config/service.cfg"
const ROUTE_PATH := "user://service_route.cfg"
const TIMEOUT_S := 12.0
## UTShare.receipt_kind() answers (native/ut_share/src/ut_share_platform.h)
enum Receipt { UNAVAILABLE = -1, NONE = 0, APP_STORE = 1, SANDBOX = 2, OTHER = 3 }
## per-request timeout (dev evidence runs on a software renderer raise it:
## a 1 fps frame rate there is not a network failure)
var timeout_s := TIMEOUT_S

var base_url := ""
var admission_key: CryptoKey
## the configured deployments: "production" / "sandbox" (or "single", the
## development fallback) -> {url, key_pem}
var endpoints: Dictionary = {}
## the deployment in use ("" when the service is off)
var deployment := ""
## why: receipt | default | desktop | moved | only | off
var route_reason := ""
## the receipt kind read at launch (Receipt; -2 before it was asked)
var receipt_kind := -2
## where the automatic move is remembered (tests point it elsewhere)
var route_path := ROUTE_PATH
## tests: the native receipt query (func() -> int) and the platform (1 iOS, 0 not)
var receipt_override: Callable
var ios_override := -1
## tests: one HTTP layer per deployment ("production"/"sandbox" -> Callable)
var transport_overrides: Dictionary = {}
var _moved_this_run := false
var _pending_move: Array = []    # [target, reason] waiting for the party to end
var _move_timer: Timer
var token := ""
var token_exp_ms := 0
var profile: Dictionary = {}       # profile_id, display_name, discriminator, needs_name, status, ...
var state := "off"                 # off | signed_out | signing_in | ready | error
## /v1/config: the owner's real support/privacy links (null until set) and
## the minimum client build.  Empty when the service is off or unreachable.
var service_config: Dictionary = {}
var last_error := ""
var _signing_in := false
## tests and the dev harness can replace the HTTP layer: func(method, path, body, headers) -> {status, body}
var transport_override: Callable
## tests replace Game Center's identity signature: func() -> {ok, player_id, ...}
var identity_override: Callable


func _ready() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG_PATH) == OK:
		load_endpoints(cf)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--service-url="):
			# development captures: one explicit endpoint
			var pem := String(endpoints.get("single", {}).get("key_pem", ""))
			endpoints = {"single": {"url": a.get_slice("=", 1).trim_suffix("/"), "key_pem": pem}}
	apply_route()
	_move_timer = Timer.new()
	_move_timer.wait_time = 2.0
	_move_timer.timeout.connect(_try_pending_move)
	add_child(_move_timer)
	if base_url != "":
		fetch_config.call_deferred()


# ------------------------------------------------------------------ routing
## Reads the deployments from service.cfg: the production / sandbox pair, or
## the single development url.
func load_endpoints(cf: ConfigFile) -> void:
	endpoints = {}
	for d in ["production", "sandbox"]:
		var u := String(cf.get_value("service", d + "_url", "")).strip_edges().trim_suffix("/")
		if u != "":
			endpoints[d] = {"url": u, "key_pem": String(cf.get_value("service", d + "_admission_public_key", ""))}
	var single := String(cf.get_value("service", "url", "")).strip_edges().trim_suffix("/")
	if endpoints.is_empty() and single != "":
		endpoints["single"] = {"url": single, "key_pem": String(cf.get_value("service", "admission_public_key", ""))}


## The App Store receipt kind from the native library (Receipt), or
## UNAVAILABLE where there is none (desktop, an older library).
func read_receipt_kind() -> int:
	if receipt_override.is_valid():
		return int(receipt_override.call())
	if ClassDB.class_exists("UTShare") and ClassDB.class_has_method("UTShare", "receipt_kind"):
		return int(ClassDB.class_call_static("UTShare", "receipt_kind"))
	return Receipt.UNAVAILABLE


func _on_ios() -> bool:
	return OS.get_name() == "iOS" if ios_override < 0 else ios_override == 1


## The routing decision (pure): {deployment, reason}.  `moved` is the
## remembered automatic move ({deployment, receipt_kind}) or {}.
static func pick_route(available: Array, on_ios: bool, kind: int, moved: Dictionary) -> Dictionary:
	if available.is_empty():
		return {"deployment": "", "reason": "off"}
	if not (available.has("production") and available.has("sandbox")):
		return {"deployment": String(available[0]), "reason": "only"}
	var m := String(moved.get("deployment", ""))
	if m in ["production", "sandbox"] and int(moved.get("receipt_kind", -9)) == kind:
		return {"deployment": m, "reason": "moved"}
	if not on_ios:
		return {"deployment": "sandbox", "reason": "desktop"}
	match kind:
		Receipt.SANDBOX:
			return {"deployment": "sandbox", "reason": "receipt"}
		Receipt.APP_STORE:
			return {"deployment": "production", "reason": "receipt"}
	# no receipt URL (current iOS always has one, simulators and Xcode builds
	# included: "sandboxReceipt"; only a future removal of the deprecated
	# call would answer nothing), an unknown name, or no native answer:
	# production, the safe default
	return {"deployment": "production", "reason": "default"}


## Chooses the deployment for this launch and points the client at it.
func apply_route() -> void:
	receipt_kind = read_receipt_kind()
	var r := pick_route(_available(), _on_ios(), receipt_kind, _load_move())
	route_reason = String(r["reason"])
	_use(String(r["deployment"]))
	state = "signed_out" if configured() else "off"


func _available() -> Array:
	var out: Array = []
	for d in ["production", "sandbox", "single"]:
		if endpoints.has(d):
			out.append(d)
	return out


func _use(d: String) -> void:
	deployment = d
	var e: Dictionary = endpoints.get(d, {})
	base_url = String(e.get("url", ""))
	var pem := String(e.get("key_pem", ""))
	admission_key = Admission.load_public_key(pem) if pem != "" else null


## The wallet environment this deployment's snapshots carry ("production" /
## "sandbox"), or "" when it isn't known (the development single endpoint).
func wallet_environment() -> String:
	return deployment if deployment in ["production", "sandbox"] else ""


func _load_move() -> Dictionary:
	var cf := ConfigFile.new()
	if cf.load(route_path) != OK:
		return {}
	return {"deployment": String(cf.get_value("route", "deployment", "")), "receipt_kind": int(cf.get_value("route", "receipt_kind", -9)),
		"reason": String(cf.get_value("route", "reason", ""))}


func _save_move(d: String, reason: String) -> void:
	var cf := ConfigFile.new()
	cf.set_value("route", "deployment", d)
	cf.set_value("route", "receipt_kind", receipt_kind)
	cf.set_value("route", "reason", reason)
	cf.set_value("route", "at", int(Time.get_unix_time_from_system()))
	cf.save(route_path)


## Can this install move to `target` now (both deployments configured, not
## already there, not moved yet in this launch)?
func can_move_to(target: String) -> bool:
	return target in ["production", "sandbox"] and endpoints.has("production") and endpoints.has("sandbox") \
		and deployment != target and not _moved_this_run


## A party is open (its room lives in this deployment): a move waits.
func _party_open() -> bool:
	var app := get_node_or_null("/root/App")
	if app == null:
		return false
	var s: Variant = app.get("session")
	return String(app.get("party_code")) != "" or (s is Object and is_instance_valid(s))


## Moves this install to the other deployment after it refused a verified
## purchase as the other environment's (`reason`: the refusal's code).
## Signs out here, signs in there with the same Game Center player, keeps the
## choice for this install.  Returns false when it can't move now (with a
## party open it moves by itself once the party ends).
func move_to(target: String, reason: String) -> bool:
	if not can_move_to(target):
		return false
	if _party_open():
		_pending_move = [target, reason]
		if _move_timer and _move_timer.is_stopped():
			_move_timer.start()
		return false
	_moved_this_run = true
	_pending_move = []
	var from := deployment
	var name_before: Variant = profile.get("display_name")
	if signed_in():
		await sign_out()
	_use(target)
	route_reason = "moved"
	_save_move(target, reason)
	token = ""
	token_exp_ms = 0
	profile = {}
	service_config = {}
	state = "signed_out"
	deployment_changed.emit(from, target)
	changed.emit()
	fetch_config()
	var s := await sign_in()
	# the same player, a new profile there: keep the approved name (that
	# deployment moderates it again)
	if bool(s.get("ok", false)) and bool(profile.get("needs_name", false)) and name_before is String and String(name_before) != "":
		await set_display_name(String(name_before))
	return true


func _try_pending_move() -> void:
	if _pending_move.is_empty():
		_move_timer.stop()
		return
	if not _party_open():
		var p: Array = _pending_move
		_move_timer.stop()
		move_to(String(p[0]), String(p[1]))


## The deployment a move waits for ("" when none).
func pending_move() -> String:
	return "" if _pending_move.is_empty() else String(_pending_move[0])


## Tests: forget this run's move and the remembered one.
func reset_route_for_tests() -> void:
	_moved_this_run = false
	_pending_move = []
	DirAccess.remove_absolute(ProjectSettings.globalize_path(route_path))


func fetch_config() -> void:
	var r := await _http(HTTPClient.METHOD_GET, "/v1/config", null, false)
	if int(r["status"]) == 200 and bool(r["body"].get("ok", true)):
		service_config = r["body"]
		changed.emit()


## A configured https link from the service (support_url, privacy_url), or "".
func link(key: String) -> String:
	var v: Variant = service_config.get(key)
	return String(v) if v is String and String(v).begins_with("https://") else ""


## True when the service says this build is too old for online play.
func update_required() -> bool:
	return int(service_config.get("min_build", 0)) > App.build_number()


func configured() -> bool:
	return base_url != "" or transport_override.is_valid() or transport_overrides.has(deployment)


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
	if transport_overrides.has(deployment):
		return await (transport_overrides[deployment] as Callable).call(method, path, body, headers)
	if transport_override.is_valid():
		return await transport_override.call(method, path, body, headers)
	var h := HTTPRequest.new()
	h.timeout = timeout_s
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


## Unauthenticated GET of public service data (Pass 8: the Shop's offers
## and the service's clock).  {ok, ..., http_status}.
func public_get(path: String) -> Dictionary:
	if not configured():
		return {"ok": false, "error": "service_off", "message": "The game service isn't set up in this build.", "http_status": 0}
	var r := await _http(HTTPClient.METHOD_GET, path, null, false)
	var out: Dictionary = r["body"]
	out["http_status"] = int(r["status"])
	if not out.has("ok"):
		out["ok"] = int(r["status"]) == 200
	return out


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


# ------------------------------------------------------------------ chat (V6)
## Does the deployed service offer `f` ("chat", "message_reports")?  An
## older deployment has no feature list, so typed chat stays unavailable.
func has_feature(f: String) -> bool:
	var fs: Variant = service_config.get("features", [])
	return fs is Array and (fs as Array).has(f)


## The service checks a typed message and, if it passes, signs the approved
## text (ChatToken).  {ok, text, token} or {ok:false, error, reason, message}.
func chat_check(room_code: String, channel: int, text: String) -> Dictionary:
	return await api(HTTPClient.METHOD_POST, "/v1/chat/check", {"room_code": room_code, "channel": channel, "text": text})


## Report one typed message: the signed message itself is the evidence.
func report_message(token: String, reason: String, details: String = "") -> Dictionary:
	return await api(HTTPClient.METHOD_POST, "/v1/reports/message", {"token": token, "reason": reason,
		"details": details.substr(0, 500), "build": App.build_number()})


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
