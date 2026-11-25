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
	# (the other side may have created the file and not yet written it: wait
	# for its contents, which are never empty)
	await wait_for(func() -> bool: return FileAccess.file_exists(p) and FileAccess.get_file_as_string(p).strip_edges() != "", secs)
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
	# (build 32) a real round over the relay: the game's own round flow
	# (loading screen, MatchController), the guest's stick moving its runner
	say("starting a round")
	_round1_at = Time.get_ticks_msec()
	s.host_start_match()
	got = await wait_for(func() -> bool: return s.phase == TC.Phase.PLAYING, 180.0)
	check(got, "the round started for both (host PLAYING, phase %d)" % s.phase)
	if got:
		var gslot := int(e["slot"])
		var mc: Variant = a.get("match_ctrl")
		got = await wait_for(func() -> bool: return mc != null and is_instance_valid(mc) and (mc as MatchController).sim != null, 20.0)
		if check(got, "the host's match is running"):
			var sim: MatchSim = (mc as MatchController).sim
			var gp: SimPlayer = null
			for pl in sim.players:
				if int(pl.id) == gslot:
					gp = pl
			if check(gp != null, "the guest's runner is in the host's round"):
				check(await wait_file("guest_steering.txt", 60.0) != "", "the guest is in the round, steering")
				await get_tree().create_timer(1.0).timeout
				var p0 := gp.pos()
				await get_tree().create_timer(4.0).timeout
				var moved := gp.pos().distance_to(p0)
				check(moved > 2.0 and not gp.is_bot, "the guest's inputs reached the host and moved its %s (%.1f m in 4 s, input seq %d)" % ["Night Watch" if gp.role == TC.Role.PATROL else "runner", moved, gp.last_seq])
	put_file("host_saw_guest.txt", "1")
	if got:
		await _host_party_after_round(s, e, rt)
	check(await wait_file("host_paid.txt", 60.0) != "", "our round 1 payment was checked")
	var done := await wait_file("guest_checked.txt", 120.0)
	check(done != "", "the guest finished its checks")
	say("leaving the party (the guest should be told)")
	a.call("leave_room")
	await wait_file("guest_result.txt", 30.0)


## (build 33) After the first round: the guest leaves the next part of it
## and stays in the party, sees us as a hologram, the round ends and we're
## both in the lobby, we both ready up (us first), we promote the guest and
## the guest, now the leader, starts the next round.
func _host_party_after_round(s: NetSession, e: Dictionary, rt: RelayTransport) -> void:
	var a := app()
	var gslot := int(e["slot"])
	# (build 34) the series plays on: round 1 ends, results with the
	# countdown on both devices, round 2 starts by itself (nobody readies,
	# nobody sees the lobby)
	var mc1: Variant = a.get("match_ctrl")
	# (2.2 (35)) round 1 is a real paid round: the service settles rounds that
	# lasted at least a minute from their registration (economy
	# eligibility.min_round_s), so it plays on until then
	say("round 1 plays on to its first minute (the service pays rounds of a minute or more)")
	await wait_for(func() -> bool: return Time.get_ticks_msec() - _round1_at > 63000, 70.0)
	if mc1 != null and is_instance_valid(mc1) and (mc1 as MatchController).sim != null:
		(mc1 as MatchController).sim.end_tick = (mc1 as MatchController).sim.tick + 2
	var got := await wait_for(func() -> bool: return a.get("screen") is ResultsScreen, 40.0)
	check(got, "round 1 ended: our results")
	_check_round_paid("host")   # (alongside the checks that follow)
	var rs := a.get("screen") as ResultsScreen
	check(rs != null and rs.between_rounds() and not rs._primary.visible and rs.leave_btn.text == "Leave match",
		"between rounds: the standings and only Leave match (no Ready, no lobby)")
	check(s.next_round_in() > 0.0, "we count down to round 2 (%.1f s)" % s.next_round_in())
	put_file("host_results1.txt", "%.2f" % s.next_round_in())
	got = await wait_for(func() -> bool: return rs != null and is_instance_valid(rs) and rs.countdown.visible, 15.0)
	check(got, "the 5-second countdown shows on our results")
	var gcount := await wait_file("guest_saw_countdown.txt", 30.0)
	check(gcount != "", "the guest saw the countdown too (%s s left there)" % gcount)
	got = await wait_for(func() -> bool: return int((s.current_start.get("series", {}) as Dictionary).get("round", 0)) == 2 and s.phase == TC.Phase.PLAYING, 120.0)
	check(got, "round 2 started by itself and is playing")
	var lobby_seen := s.phase
	check(lobby_seen == TC.Phase.PLAYING, "(no lobby in between)")
	put_file("host_round2_on.txt", "1")
	var left := await wait_file("guest_left_round.txt", 60.0)
	if not check(left != "", "the guest left the round midway (pause › Back to lobby)"):
		return
	got = await wait_for(func() -> bool: return bool(s.roster[gslot].get("away", false)), 20.0)
	e = s.roster[gslot]
	check(got and bool(e["connected"]), "the guest is still in our party, out of the round (away, connected)")
	check(rt.peers().size() == 1, "still connected through the relay")
	var mc: Variant = a.get("match_ctrl")
	var sim: MatchSim = (mc as MatchController).sim if mc != null and is_instance_valid(mc) else null
	if check(sim != null, "our round is still on"):
		var gp := sim.player(gslot)
		check(gp != null and gp.is_bot and sim.bots.has(gslot), "a bot plays the guest's runner")
		check(s.phase == TC.Phase.PLAYING, "the round plays on (phase %d)" % s.phase)
	put_file("host_round_on.txt", "1")
	var holo := await wait_file("guest_saw_hologram.txt", 60.0)
	check(holo == "ok", "the guest sees us as a hologram in its lobby (%s)" % holo)
	# round 2 ends; round 3 starts by itself without the guest, who sits the
	# rest of the match out in the lobby (a bot plays the seat)
	if sim != null:
		sim.end_tick = sim.tick + 2
	got = await wait_for(func() -> bool: return int((s.current_start.get("series", {}) as Dictionary).get("round", 0)) == 3 and s.phase == TC.Phase.PLAYING, 120.0)
	check(got, "round 3 started by itself")
	mc = a.get("match_ctrl")
	var sim3: MatchSim = (mc as MatchController).sim if mc != null and is_instance_valid(mc) else null
	if check(sim3 != null, "our round 3 is on"):
		var gp3 := sim3.player(gslot)
		check(gp3 != null and gp3.is_bot, "the guest sits it out: a bot plays the seat")
	put_file("host_round3_on.txt", "1")
	check(await wait_file("guest_sat_out.txt", 60.0) == "ok", "the guest stayed in the lobby, the match in holograms")
	# the last round ends: the final standings, then Back to lobby
	if sim3 != null:
		sim3.end_tick = sim3.tick + 2
	got = await wait_for(func() -> bool: return a.get("screen") is ResultsScreen, 40.0)
	check(got, "the last round ended: our results")
	var rf := a.get("screen") as ResultsScreen
	check(rf != null and not rf.between_rounds() and rf._primary.text == "Final standings", "the last round leads to the final standings (%s)" % (rf._primary.text if rf else "-"))
	check(s.next_round_in() < 0.0, "no countdown after the last round")
	if rf != null:
		rf._on_primary()
		await get_tree().process_frame
		check(rf.page == "final" and rf._primary.text == "Back to lobby", "the podium, then one Back to lobby")
		await get_tree().create_timer(0.5).timeout
		rf._on_primary()
	else:
		a.call("back_to_party")
	got = await wait_for(func() -> bool: return s.phase == TC.Phase.LOBBY and a.get("screen") is LobbyScreen, 20.0)
	check(got, "back in the party lobby (host)")
	put_file("host_in_lobby.txt", "1")
	check(await wait_file("guest_in_lobby.txt", 60.0) != "", "the guest is in the lobby with us")
	var l := a.get("screen") as LobbyScreen
	if not check(l != null, "our lobby screen"):
		return
	await get_tree().create_timer(0.5).timeout
	var st: DormStage = a.get("stage")
	check(st != null and st.chars.size() == 2 and st.chars.values().all(func(v: CharacterView) -> bool: return not v.hologram),
		"two characters in our lobby, neither a hologram")
	# both ready, the host (leader) first
	check(l.primary_btn.text.begins_with("Ready") and not l.primary_btn.disabled, "our button is Ready (%s)" % l.primary_btn.text)
	l._on_primary()
	got = await wait_for(func() -> bool: return bool(s.roster[s.local_slot]["ready"]), 5.0)
	check(got, "we're ready first")
	await get_tree().process_frame
	check(l.primary_btn.text.begins_with("Start") and l.primary_btn.disabled, "then Start, waiting for the guest (%s, disabled %s)" % [l.primary_btn.text, l.primary_btn.disabled])
	var mine := _cell_for(l, s.local_slot)
	check(mine != null and mine.ready_mark.get_parent().visible, "a check beside our name")
	put_file("host_ready.txt", "1")
	got = await wait_for(func() -> bool: return bool(e["ready"]), 30.0)
	check(got, "the guest's Ready arrived")
	await get_tree().process_frame
	var gc := _cell_for(l, gslot)
	check(gc != null and gc.ready_mark.get_parent().visible, "a check beside the guest's name")
	check(not l.primary_btn.disabled, "everyone's ready: Start is on")
	# promote the guest
	check(s.can_promote(gslot), "we can promote the guest")
	s.promote(gslot)
	check(s.leader_slot == gslot and not s.is_leader(), "the guest leads now")
	put_file("host_promoted.txt", "1")
	got = await wait_for(func() -> bool: return s.phase != TC.Phase.LOBBY, 60.0)
	check(got, "the guest leader's Start reached us and we started the round")
	got = await wait_for(func() -> bool: return s.phase == TC.Phase.PLAYING, 180.0)
	check(got, "the next match is playing (phase %d)" % s.phase)
	check(s.roster[gslot] != null and not bool(s.roster[gslot].get("away", false)), "with the guest in it")
	mc = a.get("match_ctrl")
	if mc != null and is_instance_valid(mc) and (mc as MatchController).sim != null:
		var gp2 := (mc as MatchController).sim.player(gslot)
		check(gp2 != null and not gp2.is_bot, "as themselves (not a bot)")
	put_file("host_next_match.txt", "1")


func _cell_for(l: LobbyScreen, slot: int) -> LobbyScreen.SlotCell:
	for c in l.cells:
		if c.visible and c.slot == slot:
			return c
	return null


func _guest_entry(s: NetSession, player: String) -> Variant:
	for e in s.roster:
		if e != null and not bool(e["is_bot"]) and String(e["uid"]) == player:
			return e
	return null


var _round1_at := 0


## (2.2 (35)) Round 1's Coins and Season XP reached this player's wallet
## through the service, once: the round settled (host: its own confirmation
## after its report; guest: the wallet asks again after a confirmation that
## got there before the host's report), the balance holds the round's Coins,
## and the results screen shows them as added.
func _check_round_paid(who: String) -> void:
	var w: Node = get_node("/root/Wallet")
	var res: Dictionary = app().get("last_results")
	var mid := String(res.get("match_id", ""))
	var got := await wait_for(func() -> bool: return String(w.call("round_summary", mid).get("state", "")) != "pending", 60.0)
	var s: Dictionary = w.call("round_summary", mid)
	check(got and String(s["state"]) == "settled", "%s: round 1 settled by the service (%s %s)" % [who, s.get("state", ""), s.get("reason", "")])
	var coins := int(s.get("coins", 0))
	check(coins > 0 and coins == int(s.get("coins_projected", -1)), "%s: its Coins as the results projected (%d of %d; %d picked up)" % [who, coins,
		int(s.get("coins_projected", -1)), int(s.get("coins_collected", 0))])
	check(int(w.call("balance")) == coins, "%s: in the wallet's balance, once (%d)" % [who, int(w.call("balance"))])
	check(int(s.get("season_xp", 0)) > 0, "%s: and its Season XP (+%d)" % [who, int(s.get("season_xp", 0))])
	var rs: Variant = app().get("screen")
	if rs is ResultsScreen:
		var chips := (rs as ResultsScreen).find_child("Rewards", true, false)
		check(chips != null and chips.find_child("TapCoins", true, false) != null and String(chips.accessibility_name).begins_with("%d Coins" % coins)
			and not String(chips.accessibility_name).contains("being added"), "%s: the results say +%d Coins, added (%s)" % [who, coins,
			chips.accessibility_name if chips else "-"])
	put_file("%s_paid.txt" % who, "%d" % coins)


## (build 33) The guest's side of _host_party_after_round.
func _guest_party_after_round(s: NetSession, snaps: Array) -> void:
	var a := app()
	# (build 34) round 1 ends: our results stay up with the countdown, and
	# round 2 starts by itself (no Ready, no lobby)
	check(s.series_flow(), "the host plays the series on by itself")
	check(await wait_file("host_results1.txt", 120.0) != "", "the host's round 1 ended")
	var got := await wait_for(func() -> bool: return a.get("screen") is ResultsScreen, 30.0)
	check(got, "our round 1 results")
	_check_round_paid("guest")   # (alongside the checks that follow)
	var rs := a.get("screen") as ResultsScreen
	check(rs != null and rs.between_rounds() and not rs._primary.visible and rs.leave_btn.text == "Leave match", "between rounds: only Leave match")
	got = await wait_for(func() -> bool: return rs != null and is_instance_valid(rs) and rs.countdown.visible, 15.0)
	check(got, "the 5-second countdown shows on our results")
	put_file("guest_saw_countdown.txt", "%.1f" % s.next_round_in())
	var lobby_seen := [false]
	var watch := func() -> void:
		if a.get("screen") is LobbyScreen:
			lobby_seen[0] = true
	var n2: int = snaps[0]
	got = await wait_for(func() -> bool:
		watch.call()
		return a.get("match_ctrl") != null and int((s.current_start.get("series", {}) as Dictionary).get("round", 0)) == 2 and int(snaps[0]) - n2 >= 10, 120.0)
	check(got, "round 2 started by itself: we're in it (snapshots arrive)")
	check(not lobby_seen[0], "we never saw the lobby between rounds")
	check(await wait_file("host_round2_on.txt", 60.0) != "", "the host plays round 2")
	var mc: Variant = a.get("match_ctrl")
	if not check(mc != null and is_instance_valid(mc), "our round is on"):
		return
	got = await wait_for(func() -> bool: return (mc as MatchController).prepared, 60.0)
	check(s.host_supports(Protocol.CAP_STAY), "the host keeps us in the party when we leave a round")
	# leave the round midway, through the pause menu's own wiring
	(mc as MatchController).hud.open_pause()
	await get_tree().process_frame
	(mc as MatchController).hud._ask_leave()
	check((mc as MatchController).hud._confirm_head.text == "Back to the party?", "the pause menu asks: Back to the party?")
	(mc as MatchController).hud._confirm_leave()
	got = await wait_for(func() -> bool: return a.get("match_ctrl") == null and a.get("screen") is LobbyScreen, 10.0)
	check(got, "we left the round: back in the party lobby")
	check(a.get("session") == s and s.connected and s.left_round, "still in the party")
	put_file("guest_left_round.txt", "1")
	check(await wait_file("host_round_on.txt", 60.0) != "", "the host's round goes on")
	var hs := s.host_slot()
	var hkey := String(s.roster[hs]["uid"]) if s.roster[hs] != null else ""
	got = await wait_for(func() -> bool:
		var st0: DormStage = a.get("stage")
		return st0 != null and st0.chars.has(hkey) and (st0.chars[hkey] as CharacterView).hologram, 15.0)
	var st: DormStage = a.get("stage")
	check(got, "the host, still in the round, is a hologram on its mark")
	var l := a.get("screen") as LobbyScreen
	var hc := _cell_for(l, hs) if l != null else null
	check(hc != null and hc.round_chip.visible, "the host's card says In a round")
	var rep: Dictionary = st.views_report() if st != null else {}
	check(int(rep.get("views", 0)) == 2 and (rep.get("by_mark", {}) as Dictionary).values().all(func(n: int) -> bool: return n == 1),
		"two characters, one per mark (%s)" % str(rep))
	var n0: int = snaps[0]
	await get_tree().create_timer(1.0).timeout
	check(int(snaps[0]) - n0 <= 1, "no round snapshots reach the lobby (%d)" % (int(snaps[0]) - n0))
	put_file("guest_saw_hologram.txt", "ok" if got else "no")
	# round 3 starts without us: we sit the rest of the match out
	check(await wait_file("host_round3_on.txt", 90.0) != "", "the host's round 3 is on")
	await get_tree().create_timer(1.0).timeout
	var out_ok := a.get("match_ctrl") == null and a.get("screen") is LobbyScreen and s.sitting_out()
	check(out_ok, "we sit round 3 out in the party lobby")
	var st3: DormStage = a.get("stage")
	var holo3 := st3 != null and st3.chars.has(hkey) and (st3.chars[hkey] as CharacterView).hologram
	check(holo3, "the host is a hologram while the match goes on")
	put_file("guest_sat_out.txt", "ok" if out_ok and holo3 else "no")
	check(await wait_file("host_in_lobby.txt", 120.0) != "", "the host is back in the lobby")
	got = await wait_for(func() -> bool:
		var st1: DormStage = a.get("stage")
		return s.host_phase == TC.Phase.LOBBY and st1 != null and st1.chars.has(hkey) and not (st1.chars[hkey] as CharacterView).hologram, 20.0)
	check(got, "the round ended: we're both in the lobby, no hologram")
	l = a.get("screen") as LobbyScreen
	check(l != null, "on our lobby screen")
	# (build 34) the lobby after a series with bots: only the party's people
	var bot_cells := 0
	var people := 0
	if l != null:
		for c in l.cells:
			if c.visible and c.slot >= 0 and s.roster[c.slot] != null:
				people += 1
				if bool(s.roster[c.slot]["is_bot"]):
					bot_cells += 1
	var st4: DormStage = a.get("stage")
	check(people == 2 and bot_cells == 0 and st4 != null and st4.chars.size() == 2, "no bots in our lobby: 2 people, 2 characters (%d cards, %d bots, %d on stage)" % [people, bot_cells, st4.chars.size() if st4 else -1])
	check(l != null and not l.series_row.visible, "no series line in the lobby")
	put_file("guest_in_lobby.txt", "1")
	check(await wait_file("host_ready.txt", 60.0) != "", "the host readied up")
	got = await wait_for(func() -> bool:
		var c := _cell_for(l, hs)
		return s.roster[hs] != null and bool(s.roster[hs]["ready"]) and c != null and c.ready_mark.get_parent().visible, 10.0)
	check(got, "the host's Ready shows with a check beside its name")
	check(l.primary_btn.text.begins_with("Ready"), "our button is Ready (%s)" % l.primary_btn.text)
	l._on_primary()
	check(await wait_file("host_promoted.txt", 60.0) != "", "the host promoted us")
	got = await wait_for(func() -> bool: return s.is_leader(), 10.0)
	check(got, "we lead the party now")
	got = await wait_for(func() -> bool: return l.primary_btn.text.begins_with("Start") and not l.primary_btn.disabled, 10.0)
	check(got, "our button is Start, everyone ready (%s)" % l.primary_btn.text)
	var mine := _cell_for(l, s.local_slot)
	check(mine != null and mine.badge.visible and mine.badge.kind == "crown", "the crown is on our card")
	var n1: int = snaps[0]
	l._on_primary()
	got = await wait_for(func() -> bool: return a.get("match_ctrl") != null and int(snaps[0]) - n1 >= 10, 180.0)
	check(got, "our Start started the next round: its snapshots arrive (%d)" % (int(snaps[0]) - n1))
	check(await wait_file("host_next_match.txt", 120.0) != "", "the host plays it with us")


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
	var snaps := [0]
	s.snapshot_received.connect(func(_sn: Dictionary) -> void: snaps[0] += 1)
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
	# (build 32) the round: hold the stick forward once our match exists
	var steer := func() -> void:
		var mc: Variant = a.get("match_ctrl")
		if mc != null and is_instance_valid(mc):
			# (build 33) the stick of the game's own automation (Autopilot:
			# it heads for a door from whichever pad, in whichever of the three
			# dorms; a fixed "forward" ran into a wall of some of them once
			# roles and dorms were drawn afresh each round)
			var ap := Autopilot.new(7)
			(mc as MatchController).input_source = func(m: MatchController) -> InputCmd: return ap.cmd_for(m)
	# (a guest's own phase stays LOADING: its match follows the host's
	# snapshots, which flow once the round is playing)
	got = await wait_for(func() -> bool: return s.phase == TC.Phase.LOADING and int(snaps[0]) >= 10 and a.get("match_ctrl") != null, 200.0)
	check(got, "our round started: the host's snapshots arrive (%d)" % int(snaps[0]))
	if got:
		steer.call()
		put_file("guest_steering.txt", "1")
		var n0: int = snaps[0]
		await get_tree().create_timer(3.0).timeout
		check(int(snaps[0]) - n0 >= 20, "the host's snapshots keep arriving in the round (%d in 3 s)" % (int(snaps[0]) - n0))
	var saw := await wait_file("host_saw_guest.txt", 120.0)
	check(saw != "", "the host saw us (and our Ready)")
	await wait_for(func() -> bool: return absf(s.rtt - 0.1) > 0.0001, 10.0)
	check(absf(s.rtt - 0.1) > 0.0001, "pings round-trip (guest-measured RTT %.0f ms)" % (s.rtt * 1000.0))
	if got:
		await _guest_party_after_round(s, snaps)
	check(await wait_file("guest_paid.txt", 60.0) != "", "our round 1 payment was checked")
	put_file("guest_checked.txt", "1")
	got = await wait_for(func() -> bool: return not ends.is_empty() or a.get("session") == null, 30.0)
	check(got, "when the host leaves, our party ends (%s)" % (ends[0] if not ends.is_empty() else "session closed"))
	check(ends.is_empty() or String(ends[0]) in ["host_ended", "host_left"], "with the host-left reason")
