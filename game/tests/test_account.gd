extends RefCounted
## Game profile flows against a scripted service (no network): first launch
## shows Create Your Runner and then the name sheet; Delete Game Profile
## re-confirms with Game Center, deletes the online profile first, keeps
## everything when the service fails, and only then wipes this device; with
## no service configured it deletes on this device only.
var t
var calls: Array = []
var fail_delete := false
var _saved_data: Dictionary
var _saved_file := ""
var _had_file := false


func _begin() -> void:
	_saved_data = Save.data.duplicate(true)
	_had_file = FileAccess.file_exists(Save.PATH)
	_saved_file = FileAccess.get_file_as_string(Save.PATH) if _had_file else ""
	calls.clear()
	fail_delete = false


func _end() -> void:
	Cloud.transport_override = Callable()
	Cloud.identity_override = Callable()
	Cloud.token = ""
	Cloud.profile = {}
	Cloud.state = "signed_out" if Cloud.configured() else "off"
	Save.data = _saved_data
	if _had_file:
		var f := FileAccess.open(Save.PATH, FileAccess.WRITE)
		f.store_string(_saved_file)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Save.PATH))
	if App.screen and is_instance_valid(App.screen):
		App.screen.queue_free()
	App.screen = null
	App._clear_background()
	await t.get_tree().process_frame


func _fake_service() -> void:
	Cloud.identity_override = func() -> Dictionary:
		calls.append(["identity"])
		return {"ok": true, "player_id": "T:test", "bundle_id": Social.BUNDLE_ID, "timestamp": 1, "salt": "c2FsdA==",
			"signature": "c2ln", "public_key_url": "https://static.gc.apple.com/public-key/gc-prod-10.cer"}
	Cloud.transport_override = func(method: int, path: String, body: Variant, headers: PackedStringArray) -> Dictionary:
		calls.append([method, path, body, Array(headers).filter(func(h: String) -> bool: return h.begins_with("Authorization")).size() > 0])
		if path == "/v1/auth/gamecenter":
			return {"status": 200, "body": {"ok": true, "token": "tok-%d" % calls.size(),
				"expires_at": int(Time.get_unix_time_from_system() * 1000.0) + 3600000,
				"profile": {"profile_id": "p_test", "display_name": "Pip", "discriminator": "0042", "needs_name": false}}}
		if path == "/v1/me" and method == HTTPClient.METHOD_DELETE:
			if fail_delete:
				return {"status": 0, "body": {"ok": false, "error": "network", "message": "offline"}}
			return {"status": 200, "body": {"ok": true, "deleted_at": 1}}
		if path == "/v1/me/appearance":
			return {"status": 200, "body": {"ok": true}}
		return {"status": 404, "body": {"ok": false, "error": "not_found", "message": "nope"}}


func _settings() -> SettingsScreen:
	var s := SettingsScreen.new()
	App._ensure_background()
	App._show(s)
	await t.get_tree().process_frame
	return s


func _texts(n: Node, out: Array) -> Array:
	if n is Label:
		out.append((n as Label).text)
	for c in n.get_children():
		_texts(c, out)
	return out


func test_first_launch_creates_runner_then_name() -> void:
	_begin()
	Save.data["onboarded"] = false
	App.goto_title()
	await t.get_tree().process_frame
	t.check(App.screen is CreatorScreen and (App.screen as CreatorScreen).first_run, "first launch opens Create Your Runner")
	var c := App.screen as CreatorScreen
	c._on_apply()
	await t.get_tree().process_frame
	var sheet: NameSheet = null
	for ch in c.get_children():
		if ch is NameSheet:
			sheet = ch
	t.check(sheet != null, "then asks for a player name")
	if sheet:
		t.check(sheet.local_only, "first-launch name is kept on this device until the service checks it")
		sheet.field.text = "Moon Pip"
		sheet._on_text(sheet.field.text)
		sheet._save()
		await t.get_tree().process_frame
		await t.get_tree().process_frame
		t.eq(String(Save.data["name"]), "Moon Pip", "name saved")
		t.check(bool(Save.data["onboarded"]), "onboarding finished")
		t.check(App.screen is TitleScreen, "home screen after onboarding")
	await _end()


func test_delete_reconfirms_and_deletes_online_before_local() -> void:
	_begin()
	_fake_service()
	Save.data["coins"] = 777
	Save.data["onboarded"] = true
	Save.data["blocked"] = [{"pid": "p_x", "uid": "", "name": "X"}]
	Cloud.token = "old-session"
	Cloud.state = "ready"
	var s: SettingsScreen = await _settings()
	await s._delete_profile()
	var paths := calls.map(func(c: Array) -> String: return String(c[1]) if c.size() > 1 else String(c[0]))
	t.eq(paths, ["identity", "/v1/auth/gamecenter", "/v1/me"], "a fresh Game Center sign-in comes right before the delete")
	t.eq(calls[2][2], {"confirm": "DELETE"}, "delete is explicitly confirmed")
	t.check(bool(calls[2][3]), "delete is authenticated with the new session")
	t.eq(int(Save.data["coins"]), 0, "local progress wiped after the online delete succeeded")
	t.eq((Save.data["blocked"] as Array).size(), 0, "block list wiped")
	t.check(not bool(Save.data["onboarded"]), "next launch starts fresh")
	t.check(not Cloud.signed_in() and Cloud.profile.is_empty(), "signed out, no profile kept in memory")
	var on_disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(Save.PATH))
	t.eq(int((on_disk as Dictionary).get("coins", -1)), 0, "wipe is written to disk")
	await _end()


func test_failed_online_delete_keeps_everything() -> void:
	_begin()
	_fake_service()
	fail_delete = true
	Save.data["coins"] = 555
	Save.data["onboarded"] = true
	var s: SettingsScreen = await _settings()
	await s._delete_profile()
	t.eq(int(Save.data["coins"]), 555, "nothing local is removed when the service didn't confirm")
	var shown := " ".join(_texts(s, []))
	t.check(shown.contains("wasn't deleted"), "the player is told it wasn't deleted")
	t.check(App.screen == s, "stays in Settings with a Try again option")
	await _end()


func test_without_service_deletes_on_device_only() -> void:
	_begin()
	t.check(not Cloud.configured(), "no service configured in tests")
	Save.data["coins"] = 321
	Save.data["onboarded"] = true
	var s: SettingsScreen = await _settings()
	await s._delete_profile()
	t.eq(calls.size(), 0, "no network calls")
	t.eq(int(Save.data["coins"]), 0, "local profile wiped")
	await _end()


func test_profile_section_offers_rename_and_delete() -> void:
	_begin()
	Save.data["onboarded"] = true
	var s: SettingsScreen = await _settings()
	var labels := []
	for b in s.find_children("*", "Button", true, false):
		labels.append((b as Button).text)
	t.check("Change name" in labels and "Delete Game Profile" in labels, "Profile section has Change name and Delete Game Profile")
	t.check(" ".join(_texts(s, [])).contains("Player name:"), "shows the player name")
	await _end()


func test_session_is_reused_and_renewed_once_when_expired() -> void:
	_begin()
	_fake_service()
	var r1: Dictionary = await Cloud.set_appearance(Cosmetics.DEFAULT)
	var r2: Dictionary = await Cloud.set_appearance(Cosmetics.DEFAULT)
	t.check(bool(r1.get("ok", false)) and bool(r2.get("ok", false)), "calls succeed")
	var auths := calls.filter(func(c: Array) -> bool: return c.size() > 1 and String(c[1]) == "/v1/auth/gamecenter").size()
	t.eq(auths, 1, "one sign-in for two calls (session reused)")
	t.eq(Cloud.state, "ready", "state is ready after a successful sign-in")
	# the server says the session expired: sign in again once and retry
	var expired_once := {"v": true}
	var inner: Callable = Cloud.transport_override
	Cloud.transport_override = func(method: int, path: String, body: Variant, headers: PackedStringArray) -> Dictionary:
		if path == "/v1/me/appearance" and expired_once["v"]:
			expired_once["v"] = false
			calls.append([method, path, body, true])
			return {"status": 401, "body": {"ok": false, "error": "session_expired", "message": "expired"}}
		return inner.call(method, path, body, headers)
	calls.clear()
	var r3: Dictionary = await Cloud.set_appearance(Cosmetics.DEFAULT)
	t.check(bool(r3.get("ok", false)), "retried after renewing")
	t.eq(calls.map(func(c: Array) -> String: return String(c[1]) if c.size() > 1 else String(c[0])),
		["/v1/me/appearance", "identity", "/v1/auth/gamecenter", "/v1/me/appearance"], "expired session renewed once, then retried")
	await _end()


func test_report_and_block_requests_match_the_service_contract() -> void:
	_begin()
	_fake_service()
	var inner: Callable = Cloud.transport_override
	Cloud.transport_override = func(method: int, path: String, body: Variant, headers: PackedStringArray) -> Dictionary:
		if path == "/v1/reports" or path == "/v1/blocks" or path.begins_with("/v1/blocks/"):
			calls.append([method, path, body, true])
			return {"status": 200, "body": {"ok": true, "receipt": "R-ABC123"}}
		return inner.call(method, path, body, headers)
	# every reason the lobby offers is one the service accepts
	var service_reasons := ["name", "harassment", "cheating", "inappropriate", "other"]
	for rr in LobbyScreen.REPORT_REASONS:
		t.check(service_reasons.has(String(rr[0])), "report reason %s is accepted by the service" % rr[0])
	var r: Dictionary = await Cloud.report("p_target", "harassment", "x".repeat(900), {"room_code": "ACD347", "build": App.build_number()})
	t.check(bool(r.get("ok", false)) and String(r.get("receipt", "")) == "R-ABC123", "report returns the receipt")
	var rep: Array = calls.filter(func(c: Array) -> bool: return c.size() > 1 and String(c[1]) == "/v1/reports")[0]
	t.eq(rep[0], HTTPClient.METHOD_POST, "POST /v1/reports")
	t.eq(String(rep[2]["profile_id"]), "p_target", "target is the opaque profile id")
	t.eq(String(rep[2]["details"]).length(), 500, "details bounded to 500 characters")
	t.eq(String(rep[2]["context"]["room_code"]), "ACD347", "room code included as context")
	await Cloud.block("p_target")
	await Cloud.unblock("p_target")
	var paths := calls.filter(func(c: Array) -> bool: return c.size() > 1 and String(c[1]).begins_with("/v1/blocks")).map(func(c: Array) -> Array: return [c[0], c[1]])
	t.eq(paths, [[HTTPClient.METHOD_POST, "/v1/blocks"], [HTTPClient.METHOD_DELETE, "/v1/blocks/p_target"]], "block and unblock endpoints")
	await _end()
