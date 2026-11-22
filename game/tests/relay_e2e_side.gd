extends Node
## One side (host or guest) of tools/relay_e2e.sh; loaded by
## tests/relay_e2e.gd once the autoloads exist (see there).

var role := ""
var dir := ""
var fails: Array[String] = []
var t0 := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--relay-e2e="):
			role = a.get_slice("=", 1)
		elif a.begins_with("--e2e-dir="):
			dir = a.substr(a.find("=") + 1)
	t0 = Time.get_ticks_msec()
	_run.call_deferred()


func say(s: String) -> void:
	print("E2E %s [%5.1fs] %s" % [role, (Time.get_ticks_msec() - t0) / 1000.0, s])


func check(ok: bool, what: String) -> bool:
	say(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		fails.append(what)
	return ok


func app() -> Node:
	return get_node("/root/App")


func cloud() -> Node:
	return get_node("/root/Cloud")


func wait_for(cond: Callable, secs: float) -> bool:
	var until := Time.get_ticks_msec() + int(secs * 1000.0)
	while Time.get_ticks_msec() < until:
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


func wait_file(name: String, secs: float) -> String:
	var p := dir.path_join(name)
	await wait_for(func() -> bool: return FileAccess.file_exists(p), secs)
	return FileAccess.get_file_as_string(p).strip_edges() if FileAccess.file_exists(p) else ""


func put_file(name: String, text: String) -> void:
	var f := FileAccess.open(dir.path_join(name), FileAccess.WRITE)
	f.store_string(text)
	f.close()


func finish() -> void:
	if fails.is_empty():
		say("PASS")
	else:
		say("FAILED: %s" % ", ".join(fails))
	put_file(role + "_result.txt", "PASS" if fails.is_empty() else "FAIL " + ", ".join(fails))
	var a := app()
	if a.get("session") != null:
		a.call("_close_session", false)
	for _i in 10:
		await get_tree().process_frame
	get_tree().quit(0 if fails.is_empty() else 1)


## Signed in as the player the script set up (its session token is minted
## with this run's SESSION_KEY and verified by the Worker like any other).
func sign_in_as(me: Dictionary) -> void:
	var c := cloud()
	# (a sign-in other autoloads started at launch fails here: no Game Center
	# on this machine; let it finish before taking over the session)
	await wait_for(func() -> bool: return not bool(c.get("_signing_in")), 10.0)
	c.set("token", String(me["token"]))
	c.set("token_exp_ms", int(me["expires_at"]))
	c.set("state", "ready")
	c.call("_set_profile", me["profile"])
	var pem := FileAccess.get_file_as_string(dir.path_join("admission_public.pem"))
	c.set("admission_key", Admission.load_public_key(pem))
	await c.call("fetch_config")
	check(bool(c.call("signed_in")), "signed in as %s (%s)" % [me["profile"]["display_name"], me["player"]])


func _run() -> void:
	var me: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(role + ".json")))
	if not (me is Dictionary):
		check(false, "read %s.json" % role)
		await finish()
		return
	var save: Node = get_node("/root/Save")
	(save.get("data") as Dictionary)["onboarded"] = true
	await sign_in_as(me)
	var c := cloud()
	check(bool(c.call("configured")) and String(c.get("base_url")).begins_with("http://127.0.0.1"), "the game talks to the local service (%s)" % c.get("base_url"))
	check(bool(c.call("has_feature", "relay")), "the service offers the relay (/v1/config features)")
	check(bool(c.call("relay_ready")), "so code parties use it")
	if role == "host":
		await _host(me)
	else:
		await _guest(me)
	await finish()


func _host(me: Dictionary) -> void:
	var a := app()
	var errs: Array = []
	a.connect("party_error", func(m: String, code: String) -> void: errs.append([m, code]))
	await a.call("host_room_gamekit")
	var s: NetSession = a.get("session")
	if not check(s != null and errs.is_empty(), "host_room_gamekit opened a party (%s)" % str(errs)):
		return
	check(s.mode == NetSession.Mode.HOST, "as its host")
	check(s.transport is RelayTransport and (s.transport as RelayTransport).connected(), "over the relay (RelayTransport, connected)")
	check(s.require_admission and s.admission_key != null, "requiring a verified admission credential from joiners")
	var code := String(a.get("party_code"))
	check(code.length() == 6, "the service gave the party code %s" % code)
	put_file("code.txt", code)
	say("waiting for the guest to join %s" % code)
	var guest_player := String(JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("guest.json")))["player"])
	var guest_pid := String(JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("guest.json")))["profile"]["profile_id"])
	var got := await wait_for(func() -> bool: return _guest_entry(s, guest_player) != null, 40.0)
	check(got, "the guest appears in the host's roster")
	if not got:
		return
	var e: Dictionary = _guest_entry(s, guest_player)
	say("roster entry: slot %d, uid %s, name %s, pid %s" % [int(e["slot"]), e["uid"], e["name"], e["pid"]])
	check(int(e["slot"]) >= 1, "in a guest slot")
	check(String(e["pid"]) == guest_pid, "admitted with the service's admission credential (profile %s)" % e["pid"])
	check(String(e["name"]) == String(me.get("guest_name", "Guest Otter")), "with the service-approved name (%s)" % e["name"])
	var rt := s.transport as RelayTransport
	check(rt.peers().size() == 1 and rt.peer_uid(int(e["peer"])) == guest_player, "the relay vouched for the guest's Game Center player")
	got = await wait_for(func() -> bool: return bool(_guest_entry(s, guest_player)["ready"]) if _guest_entry(s, guest_player) != null else false, 20.0)
	check(got, "the guest's Ready reached the host through the relay")
	# the guest pings the host every second (PING -> PONG through the relay)
	got = await wait_for(func() -> bool: return rt.stats_in >= 6, 10.0)
	check(got, "the guest's steady traffic keeps arriving (%d frames in, %d out)" % [rt.stats_in, rt.stats_out])
	# the heartbeat told the service who is connected
	var hb: Dictionary = await cloud().call("room_heartbeat", code, "", [guest_pid])
	var members: Array = hb.get("members", [])
	check(members.any(func(m: Dictionary) -> bool: return String(m["profile_id"]) == guest_pid and String(m["state"]) == "connected"),
		"the room heartbeat keeps the guest's place (connected)")
	put_file("host_saw_guest.txt", "1")
	var done := await wait_file("guest_checked.txt", 40.0)
	check(done != "", "the guest finished its checks")
	say("leaving the party (the guest should be told)")
	a.call("leave_room")
	await wait_file("guest_result.txt", 30.0)


func _guest_entry(s: NetSession, player: String) -> Variant:
	for e in s.roster:
		if e != null and not bool(e["is_bot"]) and String(e["uid"]) == player:
			return e
	return null


func _guest(me: Dictionary) -> void:
	var code := await wait_file("code.txt", 60.0)
	if not check(code != "", "got the host's code"):
		return
	var c := cloud()
	# not in the party yet: the relay refuses (and says so quickly, in words)
	var probe := RelayTransport.new(false)
	var t1 := Time.get_ticks_msec()
	probe.join(String(c.call("relay_url", code, "guest")), String(c.get("token")), "")
	var why: String = await probe.wait_open(get_tree())
	check(why == "Couldn't reach that party. Check the code and try again.", "before joining, the relay refuses a guest: \"%s\" (%d ms)" % [why, Time.get_ticks_msec() - t1])
	var a := app()
	var errs: Array = []
	a.connect("party_error", func(m: String, k: String) -> void: errs.append([m, k]))
	var ends: Array = []
	await a.call("join_room_gamekit", code)
	var s: NetSession = a.get("session")
	if not check(s != null and errs.is_empty(), "join_room_gamekit joined by code (%s)" % str(errs)):
		return
	# (heard before App's own handler, which closes the session)
	s.ended.disconnect(Callable(a, "_on_session_ended"))
	s.ended.connect(func(r: String) -> void:
		say("our party ended: %s" % r)
		ends.append(r))
	s.ended.connect(Callable(a, "_on_session_ended"))
	check(s.mode == NetSession.Mode.CLIENT and s.transport is RelayTransport, "as a guest over the relay")
	check(s.admission != "", "holding the service's admission credential")
	var got := await wait_for(func() -> bool: return s.local_slot >= 1 and s.human_count() == 2, 30.0)
	check(got, "the host admitted us: slot %d, %d players in the lobby" % [s.local_slot, s.human_count()])
	check(s.host_peer == RelayTransport.HOST_PEER, "bound to the host the service named")
	var names: Array = []
	for e in s.roster:
		if e != null and not bool(e["is_bot"]):
			names.append(String(e["name"]))
	say("lobby as the guest sees it: %s" % ", ".join(names))
	check(names.has(String(me.get("host_name", "Host Otter"))), "the host's name is in our lobby")
	s.set_local_ready(true)
	var saw := await wait_file("host_saw_guest.txt", 40.0)
	check(saw != "", "the host saw us (and our Ready)")
	await wait_for(func() -> bool: return absf(s.rtt - 0.1) > 0.0001, 10.0)
	check(absf(s.rtt - 0.1) > 0.0001, "pings round-trip (guest-measured RTT %.0f ms)" % (s.rtt * 1000.0))
	put_file("guest_checked.txt", "1")
	got = await wait_for(func() -> bool: return not ends.is_empty() or a.get("session") == null, 30.0)
	check(got, "when the host leaves, our party ends (%s)" % (ends[0] if not ends.is_empty() else "session closed"))
	check(ends.is_empty() or String(ends[0]) in ["host_ended", "host_left"], "with the host-left reason")
