extends RefCounted
## V4 party settings, random fair roles and multi-round series: every
## 1/2/3 Night Watch x 1/3/5 round combination, the required-home policy,
## role counts and human/bot constraints, first-round fairness and rotation,
## idempotent round recording, cancelled rounds, eligibility after a
## disconnect, tie places, and the settings/series traffic between host and
## guests (ready reset, guests see the host's settings, reconnect gets the
## series).
var t


func _players(humans: int) -> Array:
	var out: Array = []
	for i in 8:
		out.append({"slot": i, "uid": ("h%d" % i) if i < humans else "bot-%d" % i, "is_bot": i >= humans})
	return out


func test_settings_combinations_and_rules_copy() -> void:
	var base: RulesConfig = Rules.cfg
	var before := [base.patrol_slots, base.runner_slots, base.runners_needed]
	var expect_home := {1: 5, 2: 4, 3: 4}
	for w in [1, 2, 3]:
		for r in [1, 3, 5]:
			var s := PartySeries.sanitize_settings({"watch": w, "rounds": r})
			t.check(not s.is_empty(), "%d watch / %d rounds is valid" % [w, r])
			var c := PartySeries.rules_for(base, w)
			t.eq([c.patrol_slots, c.runner_slots, c.runners_needed], [w, 8 - w, expect_home[w]], "rules for %d Night Watch" % w)
			t.eq(c.match_duration_s, base.match_duration_s, "other rules unchanged")
			var line := PartySeries.summary(s)
			t.check(line.contains("%d Night Watch" % w) and line.contains("%d runners" % (8 - w)) and line.contains("%d home to win" % expect_home[w]), "summary: " + line)
			t.check(line.begins_with("Single round") if r == 1 else line.begins_with("%d rounds" % r), "rounds in the summary")
	t.eq([base.patrol_slots, base.runner_slots, base.runners_needed], before, "the global default is never modified")
	for bad in [{"watch": 0, "rounds": 3}, {"watch": 4, "rounds": 3}, {"watch": 2, "rounds": 2}, {"watch": "2", "rounds": 3}, {}, "x"]:
		t.check(PartySeries.sanitize_settings(bad).is_empty(), "rejected: %s" % str(bad))


func test_role_counts_and_human_constraints() -> void:
	for w in [1, 2, 3]:
		var ps := PartySeries.new()
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		ps.start({"watch": w, "rounds": 3}, rng)
		for humans in range(1, 9):
			for sd in 20:
				var roles := ps.assign_roles(_players(humans), sd * 7919 + humans)
				var watch_total := 0
				var human_watch := 0
				var human_run := 0
				for slot in roles:
					if roles[slot] == TC.Role.PATROL:
						watch_total += 1
						if slot < humans:
							human_watch += 1
					elif slot < humans:
						human_run += 1
				if watch_total != w:
					t.eq(watch_total, w, "Night Watch count (%d humans, seed %d)" % [humans, sd])
				if humans >= 2:
					t.check(human_run >= 1, "at least one human runner")
					t.eq(human_watch, mini(w, humans - 1), "humans on the Night Watch = min(watch, humans - 1)")
	t.check(true, "role sweep done")


func test_first_round_is_an_equal_draw_and_later_rounds_rotate() -> void:
	var ps := PartySeries.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	ps.start({"watch": 2, "rounds": 5}, rng)
	var counts := {0: 0, 1: 0, 2: 0, 3: 0}
	var n := 4000
	for sd in n:
		var roles := ps.assign_roles(_players(4), sd)
		for s in 4:
			if roles[s] == TC.Role.PATROL:
				counts[s] += 1
	for s in 4:
		t.near(float(counts[s]) / n, 0.5, 0.05, "human %d is Night Watch half the time in round 1" % s)
	# rotation: record rounds and check nobody repeats before everyone has had a turn
	var turns := {"h0": 0, "h1": 0, "h2": 0, "h3": 0}
	for round_i in 4:
		var roles := ps.assign_roles(_players(4), 1000 + round_i)
		var rows: Array = []
		for s in 8:
			var uid := ("h%d" % s) if s < 4 else "bot-%d" % s
			rows.append({"slot": s, "uid": uid, "name": uid, "is_bot": s >= 4, "role": roles[s], "present": true, "away_s": 0.0})
			if s < 4 and roles[s] == TC.Role.PATROL:
				turns[uid] += 1
		ps.record_round({"match_id": "m%d" % round_i, "outcome": TC.Outcome.RUNNERS_WIN, "round_time": 200.0, "players": rows})
		if round_i == 1:
			t.eq(turns.values(), [1, 1, 1, 1], "after two rounds of 2 Night Watch, all four humans had one turn")
	t.eq(turns.values(), [2, 2, 2, 2], "after four rounds, two turns each")


func test_one_human_policy() -> void:
	var ps := PartySeries.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	ps.start({"watch": 2, "rounds": 3}, rng)
	var watch := 0
	var n := 4000
	for sd in n:
		var roles := ps.assign_roles(_players(1), sd)
		if roles[0] == TC.Role.PATROL:
			watch += 1
		var total := 0
		for s in roles:
			if roles[s] == TC.Role.PATROL:
				total += 1
		if total != 2:
			t.eq(total, 2, "bots fill the rest of the Night Watch")
	t.near(float(watch) / n, 2.0 / 8.0, 0.03, "alone: Night Watch with the odds of any seat (2 of 8)")


func _round(ps: PartySeries, mid: String, outcome: int, rows: Array) -> bool:
	return ps.record_round({"match_id": mid, "outcome": outcome, "round_time": 200.0, "players": rows})


func test_round_recording_scores_and_ties() -> void:
	var ps := PartySeries.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	ps.start({"watch": 2, "rounds": 3}, rng)
	var a := {"slot": 0, "uid": "a", "name": "Ann", "is_bot": false, "role": TC.Role.RUNNER, "stamps": 3, "finished": true, "present": true, "away_s": 0.0}
	var b := {"slot": 1, "uid": "b", "name": "Bea", "is_bot": false, "role": TC.Role.PATROL, "captures": 3, "unique_captures": 2, "present": true, "away_s": 0.0}
	var c := {"slot": 2, "uid": "c", "name": "Cal", "is_bot": false, "role": TC.Role.RUNNER, "present": true, "away_s": 150.0, "was_human": true}
	var bot := {"slot": 3, "uid": "bot-3", "name": "Snooze", "is_bot": true, "role": TC.Role.RUNNER, "present": true, "away_s": 0.0}
	t.check(_round(ps, "r1", TC.Outcome.RUNNERS_WIN, [a, b, c, bot]), "round 1 recorded")
	t.check(not _round(ps, "r1", TC.Outcome.RUNNERS_WIN, [a, b, c, bot]), "the same round twice counts once")
	t.check(not _round(ps, "rx", TC.Outcome.CANCELLED, [a, b, c, bot]), "a cancelled round doesn't count")
	t.eq(ps.rounds.size(), 1, "one completed round")
	t.eq(ps.next_round(), 2, "round 2 is next")
	t.check(not ps.standings.has("bot-3"), "bots are not in the friends standings")
	t.eq(int(ps.standings["a"]["wins"]), 1, "runner on the winning team gets a Round Win")
	t.eq(int(ps.standings["b"]["wins"]), 0, "Night Watch lost that round")
	t.eq(int(ps.standings["b"]["tags"]), 3, "tags kept as a personal stat")
	t.eq(int(ps.standings["c"]["wins"]), 0, "away for most of the round: no win (a bot covered)")
	t.eq(int(ps.standings["c"]["partial"]), 1, "and marked partial")
	# round 2: Night Watch wins; a late joiner appears
	var a2 := a.duplicate(); a2["role"] = TC.Role.PATROL
	var b2 := b.duplicate(); b2["role"] = TC.Role.RUNNER
	var d := {"slot": 4, "uid": "d", "name": "Dee", "is_bot": false, "role": TC.Role.RUNNER, "present": true, "away_s": 0.0}
	_round(ps, "r2", TC.Outcome.PATROL_WIN, [a2, b2, d])
	t.eq(int(ps.standings["d"]["joined_round"]), 2, "late joiner joined in round 2")
	t.eq(int(ps.standings["d"]["played"]), 1, "and played one round")
	var lb := ps.leaderboard()
	t.eq(lb[0]["name"], "Ann", "two wins leads")
	t.eq(int(lb[0]["place"]), 1, "first place")
	var places := {}
	for r in lb:
		places[r["name"]] = int(r["place"])
	t.eq(places["Bea"], places["Cal"], "zero-win ties share a place")
	t.eq(ps.team_tally(), {"runners": 1, "watch": 1}, "role-team tally")
	t.check(not ps.finished, "series still going")
	_round(ps, "r3", TC.Outcome.RUNNERS_WIN, [a, b, d])
	t.check(ps.finished, "three of three rounds: series over")
	t.check(not _round(ps, "r4", TC.Outcome.RUNNERS_WIN, [a]), "nothing records after the series ends")
	var ps2 := PartySeries.new()
	ps2.start({"watch": 1, "rounds": 5}, rng)
	_round(ps2, "x1", TC.Outcome.RUNNERS_WIN, [a])
	ps2.end_early()
	t.check(ps2.finished and ps2.ended_early, "host can end a series early")
	t.eq(ps2.rounds.size(), 1, "completed rounds stand")


func test_series_view_is_sanitized() -> void:
	var ps := PartySeries.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	ps.start({"watch": 3, "rounds": 5}, rng)
	_round(ps, "q1", TC.Outcome.RUNNERS_WIN, [{"slot": 0, "uid": "a", "name": "Ann", "is_bot": false, "role": 0, "present": true, "away_s": 0.0}])
	var v := PartySeries.sanitize_view(JSON.parse_string(JSON.stringify(ps.to_dict())))
	t.eq(int(v["settings"]["watch"]), 3, "settings survive the wire")
	t.eq(int(v["standings"]["a"]["wins"]), 1, "standings survive the wire")
	t.check(PartySeries.sanitize_view({"settings": {"watch": 9, "rounds": 3}}).is_empty(), "bad settings: whole view rejected")
	var big := {"settings": {"watch": 2, "rounds": 3}, "rounds": [], "standings": {}}
	for i in 50:
		big["standings"]["u%d" % i] = {"wins": 99999, "name": "x"}
	var bv := PartySeries.sanitize_view(big)
	t.check((bv["standings"] as Dictionary).size() <= 16, "standings bounded")
	t.eq(int(bv["standings"].values()[0]["wins"]), 9999, "numbers clamped")


func test_settings_and_series_over_the_network() -> void:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(30, 5, 0.0, 2)
	await rig.wait_until(func() -> bool: return rig.host.human_count() == 3, 300)
	for c in rig.clients:
		c.set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.can_start(), 300)
	t.check(rig.host.host_set_settings(3, 5), "host changes the settings in the lobby")
	t.check(not rig.host.can_start(), "a settings change clears the guests' ready")
	await rig.wait_until(func() -> bool: return int(rig.clients[0].settings["watch"]) == 3, 300)
	t.eq([int(rig.clients[0].settings["watch"]), int(rig.clients[0].settings["rounds"])], [3, 5], "guests see the host's settings")
	t.check(rig.clients[0].settings_note.contains("changed"), "guests are told why ready was cleared")
	t.check(not rig.clients[0].host_set_settings(1, 1), "a guest can't change settings")
	for c in rig.clients:
		c.set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.can_start(), 300)
	rig.host.host_start_match(77)
	t.check(not rig.host.host_set_settings(2, 3), "settings are locked once the series starts")
	await rig.wait_until(func() -> bool: return rig.started.has(rig.clients[0]) and rig.started.has(rig.clients[1]), 300)
	var info: Dictionary = rig.started[rig.clients[0]]
	t.eq(int(info["settings"]["watch"]), 3, "START carries the locked settings")
	t.eq([int(info["series"]["round"]), int(info["series"]["total"])], [1, 5], "Round 1 of 5")
	t.eq(rig.clients[0].round_cfg.runners_needed, 4, "client rules: 5 runners, 4 home")
	var patrols := 0
	var human_patrol := 0
	for e in info["roster"]:
		if int(e["role"]) == TC.Role.PATROL:
			patrols += 1
			if not bool(e["is_bot"]):
				human_patrol += 1
	t.eq(patrols, 3, "three Night Watch")
	t.eq(human_patrol, 2, "two of three humans on the Night Watch (one human runner kept)")
	rig.queue_free()
