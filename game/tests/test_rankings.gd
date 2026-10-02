extends RefCounted
## V6 rankings: the round's standings per team (never a combined score),
## the series by Round Wins with shared places and no alphabetical
## tie-break, bots kept out of the friends' standings, partial play shown,
## the final standings before Return to lobby, cancelled rounds without
## standings or rewards, and the same results however often they arrive or
## are opened.
var t


func _row(slot: int, uid: String, name: String, role: int, o: Dictionary = {}) -> Dictionary:
	var r := {"slot": slot, "uid": uid, "name": name, "is_bot": false, "role": role, "stamps": 0, "finished": false,
		"finish_order": 0, "finish_time": -1.0, "times_captured": 0, "captures": 0, "unique_captures": 0,
		"present": true, "away_s": 0.0, "cosmetic": {}}
	r.merge(o, true)
	return r


func _round(mid: String, oc: int, rows: Array) -> Dictionary:
	return {"match_id": mid, "outcome": oc, "players": rows, "finished": 4, "needed": 4, "round_time": 200.0}


func test_round_standings_per_team() -> void:
	var rows := [
		_row(0, "me", "Comfy Frog", TC.Role.RUNNER, {"stamps": 3, "finished": true, "finish_order": 2, "finish_time": 150.0}),
		_row(1, "b1", "Snooze", TC.Role.RUNNER, {"is_bot": true, "stamps": 3, "finished": true, "finish_order": 1, "finish_time": 120.0}),
		_row(2, "a", "Zed Otter", TC.Role.RUNNER, {"stamps": 2, "times_captured": 1}),
		_row(3, "b", "Amy Owl", TC.Role.RUNNER, {"stamps": 2, "times_captured": 0}),
		_row(4, "c", "Away Newt", TC.Role.RUNNER, {"stamps": 1, "away_s": 150.0}),
		_row(5, "w1", "Night One", TC.Role.PATROL, {"captures": 5, "unique_captures": 2}),
		_row(6, "w2", "Night Two", TC.Role.PATROL, {"captures": 2, "unique_captures": 2}),
		_row(7, "b7", "Pillow", TC.Role.PATROL, {"is_bot": true, "captures": 9, "unique_captures": 3}),
	]
	var v := RoundRanking.round_view(_round("r1", TC.Outcome.RUNNERS_WIN, rows), "me", 0)
	var names := func(arr: Array) -> Array: return arr.map(func(x: Dictionary) -> String: return String(x["name"]))
	t.eq(names.call(v["runners"]), ["Snooze", "Comfy Frog", "Amy Owl", "Zed Otter", "Away Newt"],
		"runners: home order, then splashes, then fewer catches (never by name)")
	t.eq(names.call(v["watch"]), ["Pillow", "Night One", "Night Two"], "Night Watch: different runners, then tags")
	t.check((v["runners"] as Array).all(func(x: Dictionary) -> bool: return int(x["role"]) == TC.Role.RUNNER), "no Night Watch in the runners' list")
	t.check(not v.has("score") and (v["runners"] as Array).all(func(x: Dictionary) -> bool: return not x.has("score")), "no invented combined score")
	t.check(bool(v["me"]["me"]) and String(v["me"]["name"]) == "Comfy Frog", "you are found and marked")
	t.check(bool((v["runners"][0] as Dictionary)["is_bot"]), "a bot is marked as a bot")
	t.check(bool((v["runners"][4] as Dictionary)["away"]), "away for most of the round is marked")
	t.eq(names.call(v["celebrate"]), ["Comfy Frog", "Amy Owl", "Zed Otter", "Away Newt"], "the celebration puts people before bots")
	t.check(String(v["reason"]).contains("made it home"), "the real reason")
	var c := RoundRanking.round_view(_round("rc", TC.Outcome.CANCELLED, rows), "me", 0)
	t.check(bool(c["cancelled"]) and (c["runners"] as Array).is_empty() and (c["watch"] as Array).is_empty() and (c["celebrate"] as Array).is_empty(),
		"a cancelled round has no standings")


func test_series_ties_share_places_without_name_order() -> void:
	var ps := PartySeries.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	ps.start({"watch": 2, "rounds": 3}, rng)
	# Zoe and Abe both win every round they play; Mia joins late; a bot plays all
	var z := _row(0, "z", "Zoe Fox", TC.Role.RUNNER)
	var a := _row(1, "a", "Abe Owl", TC.Role.RUNNER)
	var bot := _row(2, "bot-2", "Snooze", TC.Role.PATROL, {"is_bot": true})
	ps.record_round(_round("s1", TC.Outcome.RUNNERS_WIN, [z, a, bot]))
	var m := _row(3, "m", "Mia Seal", TC.Role.PATROL)
	ps.record_round(_round("s2", TC.Outcome.RUNNERS_WIN, [z, a, bot, m]))
	var rows := RoundRanking.series_rows(ps.to_dict(), "a")
	var order: Array = rows.map(func(x: Dictionary) -> String: return String(x["name"]))
	t.eq(order, ["Zoe Fox", "Abe Owl", "Mia Seal"], "Zoe stays before Abe (recorded first), not sorted alphabetically")
	t.eq(int(rows[0]["place"]), 1, "first")
	t.eq(int(rows[1]["place"]), 1, "a tie shares first place")
	t.check(bool(rows[0]["tied"]) and String(rows[0]["label"]) == "T1" and String(rows[1]["label"]) == "T1", "shown as T1 for both")
	t.eq(int(rows[2]["place"]), 3, "the next place is third")
	t.eq(String(rows[2]["label"]), "3rd", "an untied place is an ordinal")
	t.eq(int(rows[2]["joined_round"]), 2, "a late joiner is marked")
	t.check(not order.has("Snooze"), "bots never appear in the friends' standings")
	t.check(bool(rows[1]["me"]), "you are marked")
	var steps := RoundRanking.podium(rows)
	t.eq(steps.size(), 2, "two podium steps")
	t.eq((steps[0]["rows"] as Array).size(), 2, "tied players share the top step")
	# a reversed insertion order gives the reversed display order (not names)
	var st2 := {"a": ps.standings["a"], "z": ps.standings["z"]}
	var r2 := PartySeries.leaderboard_of(st2)
	t.eq(r2.map(func(x: Dictionary) -> String: return String(x["name"])), ["Abe Owl", "Zoe Fox"], "within a tie: recorded order, whatever the names")


func test_results_screen_flow_and_idempotence() -> void:
	var root: Window = t.get_tree().root
	var saved_size: Vector2i = root.size
	root.size = Vector2i(2532, 1170)
	var me := Save.player_uid()
	var ps := PartySeries.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	ps.start({"watch": 1, "rounds": 1}, rng)
	var rows := [_row(0, me, "Tester", TC.Role.RUNNER, {"stamps": 3, "finished": true, "finish_order": 1, "finish_time": 140.0}),
		_row(1, "f1", "Pip Owl", TC.Role.PATROL, {"captures": 1, "unique_captures": 1}),
		_row(2, "bot-2", "Snooze", TC.Role.RUNNER, {"is_bot": true, "stamps": 2})]
	var res := _round("final-1", TC.Outcome.RUNNERS_WIN, rows)
	ps.record_round(res)
	res["series"] = ps.to_dict()
	res["round_index"] = 1
	res["rounds_total"] = 1
	var guest := NetSession.new()
	guest.mode = NetSession.Mode.CLIENT
	guest.local_slot = 0
	guest.series_view = res["series"]
	t.add_child(guest)
	var reward := {"coins": 41, "xp": 41, "lines": [["Played the round", 20], ["Made it home", 21]]}
	var r := ResultsScreen.new()
	r.results = res.duplicate(true)
	r.reward = reward
	r.session = guest
	App._ensure_background()
	App._show(r)
	for i in 10:
		await t.get_tree().process_frame
	var texts := _texts(r)
	t.check(texts.has("Runners") or texts.any(func(x: String) -> bool: return x.begins_with("Runners")), "the runners' table")
	t.check(texts.any(func(x: String) -> bool: return x.begins_with("Night Watch")), "the Night Watch's table, separately")
	t.check(texts.has("+41"), "the round's coins")
	t.eq(r._primary.text, "Final standings", "after the last round: the final standings come first")
	r._on_primary()
	for i in 4:
		await t.get_tree().process_frame
	t.eq(r.page, "final", "the final standings page")
	t.check(_texts(r).has("Final standings"), "titled")
	t.eq(r._primary.text, "Return to lobby", "and only then Return to lobby")
	# the host going back to the party room doesn't move a guest who is reading
	guest.lobby_changed.emit()
	await t.get_tree().process_frame
	t.check(App.screen == r and is_instance_valid(r), "nobody is ejected from their results")
	# reopening the same round's results: same rewards, nothing paid twice
	var r2 := ResultsScreen.new()
	r2.results = res.duplicate(true)
	r2.reward = {}   # Save.apply_results gives {} the second time
	r2.session = guest
	App._show(r2)
	for i in 6:
		await t.get_tree().process_frame
	t.check(_texts(r2).has("+41"), "reopened: the same reward summary (remembered per round)")
	# the wallet, when present, owns coins and Season XP
	RoundRewards.wallet_override = func(mid: String) -> Dictionary:
		return {"coins_collected": 3, "coins": 44, "lines": [["Coins collected", 3]], "season": {"xp_gained": 60, "tier": 4, "xp_in_tier": 120, "xp_for_tier": 300}} if mid == "final-1" else {}
	var r3 := ResultsScreen.new()
	r3.results = res.duplicate(true)
	r3.reward = {}
	r3.session = guest
	App._show(r3)
	for i in 6:
		await t.get_tree().process_frame
	var t3 := _texts(r3)
	t.check(t3.has("3") and t3.has("+44") and t3.any(func(x: String) -> bool: return x.begins_with("Season XP +60")), "coins collected, credited and Season XP from the wallet")
	RoundRewards.wallet_override = Callable()
	# a cancelled round: the cancellation, no tables, no rewards
	var r4 := ResultsScreen.new()
	r4.results = _round("cx-1", TC.Outcome.CANCELLED, rows)
	r4.reward = {}
	r4.session = guest
	App._show(r4)
	for i in 6:
		await t.get_tree().process_frame
	var t4 := _texts(r4)
	t.check(t4.has("Round cancelled"), "the cancellation is shown")
	t.check(not t4.any(func(x: String) -> bool: return x.begins_with("Night Watch")) and not t4.has("Rewards"), "with no standings and no rewards")
	App.screen.queue_free()
	App.screen = null
	App._clear_background()
	guest.queue_free()
	root.size = saved_size


func test_repeated_and_stale_results_packets_change_nothing() -> void:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(20, 0, 0.0, 1)
	var c: NetSession = rig.clients[0]
	await rig.wait_until(func() -> bool: return c.local_slot >= 0, 300)
	var got: Array = []
	c.results_received.connect(func(r: Dictionary) -> void: got.append(String(r.get("match_id", ""))))
	c.current_start = {"match_id": "m-now"}
	var send := func(mid: String) -> void:
		var b := Protocol.buf_for(Protocol.M.RESULTS)
		var u := JSON.stringify({"match_id": mid, "outcome": TC.Outcome.RUNNERS_WIN, "players": []}).to_utf8_buffer()
		b.put_u32(u.size())
		b.put_data(u)
		c._on_packet(c.host_peer, b.data_array)
	send.call("m-old")
	t.eq(got, [], "results for another round are ignored")
	send.call("m-now")
	send.call("m-now")
	send.call("m-now")
	t.eq(got, ["m-now"], "the same results three times are taken once")
	rig.teardown()


static func _texts(n: Node) -> Array:
	var out: Array = []
	for l in n.find_children("*", "Label", true, false):
		if (l as Label).is_visible_in_tree():
			out.append((l as Label).text)
	return out
