extends RefCounted
## V4 party settings, random fair roles and multi-round series: every
## 1/2/3 Night Watch x 1/3/5 round combination, the required-home policy,
## role counts and human/bot constraints, (build 33) a fresh random draw
## every round with its statistics and the streak rule,
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
			# the map first (two maps), then the rounds
			var rounds_txt := "Single round" if r == 1 else "%d rounds" % r
			t.check(line.begins_with("%s · %s" % [CampusMaps.title(CampusMaps.PLAY_DEFAULT), rounds_txt]), "map, then rounds in the summary: " + line)
	t.eq([base.patrol_slots, base.runner_slots, base.runners_needed], before, "the global default is never modified")
	for bad in [{"watch": 0, "rounds": 3}, {"watch": 4, "rounds": 3}, {"watch": 2, "rounds": 2}, {"watch": "2", "rounds": 3}, {}, "x"]:
		t.check(PartySeries.sanitize_settings(bad).is_empty(), "rejected: %s" % str(bad))


func test_role_counts_and_human_constraints() -> void:
	# (build 33) a fresh random draw every round: the Night Watch count is
	# always the setting; with two or more humans they are never all on the
	# Night Watch while a bot could take the seat; a party of humans only
	# keeps the draw as it fell
	for w in [1, 2, 3]:
		var ps := PartySeries.new()
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		ps.start({"watch": w, "rounds": 3}, rng)
		for humans in range(1, 9):
			for sd in 40:
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
				if humans >= 2 and humans < 8 and human_run < 1:
					t.check(false, "%d humans, %d Night Watch, seed %d: at least one human runner while a bot could watch" % [humans, w, sd])
				if human_watch > mini(w, humans):
					t.check(false, "no more humans on the Night Watch than seats")
	t.check(true, "role sweep done")


## (build 33) Statistics of the draw: over many rounds each human is the
## Night Watch about the expected share, both outcomes happen for each of
## two friends, and the role is not predictable from the last round.
func test_roles_are_random_every_round() -> void:
	var ps := PartySeries.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	ps.start({"watch": 2, "rounds": 5}, rng)
	var n := 6000
	# two friends and six bots, 2 Night Watch: each seat 2/8, minus the rare
	# both-friends draw (1/28) handed to a bot: 1/4 - 1/56 for each friend
	var exp2 := 0.25 - 1.0 / 56.0
	var counts := {0: 0, 1: 0}
	var both := 0
	var none := 0
	var same_as_last := 0
	var prev: Dictionary = {}
	for sd in n:
		var roles := ps.assign_roles(_players(2), sd * 2654435761 % 2147483647)
		var a: bool = roles[0] == TC.Role.PATROL
		var b: bool = roles[1] == TC.Role.PATROL
		counts[0] += 1 if a else 0
		counts[1] += 1 if b else 0
		both += 1 if a and b else 0
		none += 1 if not a and not b else 0
		if not prev.is_empty() and roles[0] == prev[0] and roles[1] == prev[1]:
			same_as_last += 1
		prev = roles
	for s in 2:
		t.near(float(counts[s]) / n, exp2, 0.02, "friend %d is Night Watch about %.1f%% of rounds" % [s, exp2 * 100.0])
	t.eq(both, 0, "never both friends on the Night Watch (a bot takes the seat)")
	t.check(none > n / 3, "often both friends run (%d of %d)" % [none, n])
	t.check(counts[0] > n / 8 and counts[0] < n - n / 8 and counts[1] > n / 8, "each friend gets both roles, many times")
	t.check(same_as_last > n / 3 and same_as_last < n - n / 10, "the roles aren't a pattern: as often the same as last round as chance makes them (%d)" % same_as_last)
	# four humans, 2 Night Watch: each seat 2/8 (four humans can't all watch)
	var c4 := {0: 0, 1: 0, 2: 0, 3: 0}
	for sd in n:
		var roles := ps.assign_roles(_players(4), sd + 99)
		for s in 4:
			if roles[s] == TC.Role.PATROL:
				c4[s] += 1
	for s in 4:
		t.near(float(c4[s]) / n, 0.25, 0.025, "human %d of four is Night Watch a quarter of the time" % s)
	# one human: the odds of any seat (2 of 8)
	var one := 0
	for sd in n:
		if ps.assign_roles(_players(1), sd + 7)[0] == TC.Role.PATROL:
			one += 1
	t.near(float(one) / n, 0.25, 0.02, "alone: Night Watch with the odds of any seat (2 of 8)")


## (build 33) The light fairness rule: two Night Watch rounds in a row make
## a human less likely to be drawn again, never excluded.
func test_a_watch_streak_lowers_the_chance() -> void:
	var ps := PartySeries.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	ps.start({"watch": 2, "rounds": 3}, rng)
	var n := 6000
	var streaky := 0
	var fresh := 0
	for sd in n:
		var pl := _players(2)
		pl[0]["streak"] = 2
		pl[1]["streak"] = 0
		var roles := ps.assign_roles(pl, sd * 31 + 5)
		streaky += 1 if roles[0] == TC.Role.PATROL else 0
		fresh += 1 if roles[1] == TC.Role.PATROL else 0
	var ps_ := float(streaky) / n
	var pf := float(fresh) / n
	t.check(ps_ < pf * 0.6, "after two Night Watch rounds in a row: drawn less often (%.3f vs %.3f)" % [ps_, pf])
	t.check(streaky > n / 40, "but never excluded (%d of %d)" % [streaky, n])
	# one Night Watch round is no streak
	var one_round := 0
	for sd in n:
		var pl := _players(2)
		pl[0]["streak"] = 1
		if ps.assign_roles(pl, sd * 17 + 3)[0] == TC.Role.PATROL:
			one_round += 1
	t.near(float(one_round) / n, 0.25 - 1.0 / 56.0, 0.02, "a single Night Watch round changes nothing")


## (build 33) Through the host over the network: a party of two friends gets
## both role layouts across rounds (never the same one every time), and the
## host counts the Night Watch streak each round.
func test_party_rounds_draw_roles_afresh() -> void:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(60, 20, 0.0, 1)
	await rig.wait_until(func() -> bool: return rig.host.human_count() == 2, 300)
	# (the draw only: no match scenes)
	for s in [rig.host, rig.clients[0]]:
		for c in s.match_starting.get_connections():
			s.match_starting.disconnect(c["callable"])
	var layouts := {}
	var host_watch := 0
	var guest_watch := 0
	for round in 24:
		rig.host.host_start_match(1000 + round * 7)
		var roles := {}
		for e in rig.host.roster:
			roles[String(e["uid"])] = int(e["role"])
		layouts["%d%d" % [roles["uid-host"], roles["uid-c0"]]] = true
		host_watch += 1 if roles["uid-host"] == TC.Role.PATROL else 0
		guest_watch += 1 if roles["uid-c0"] == TC.Role.PATROL else 0
		var res := {"match_id": rig.host.current_start["match_id"], "outcome": TC.Outcome.RUNNERS_WIN, "round_time": 200.0, "players": []}
		rig.host.host_match_finished(res)
		var streak := int(rig.host.roster[0]["watch_streak"])
		if roles["uid-host"] == TC.Role.PATROL:
			t.check(streak >= 1, "the host counts a Night Watch round into the streak")
		else:
			t.eq(streak, 0, "a runner round ends the streak")
		rig.host.host_return_to_lobby()
		if rig.host.series != null and rig.host.series.finished:
			rig.host.host_return_to_lobby()
	t.check(layouts.size() >= 2, "different role layouts across rounds (%s)" % str(layouts.keys()))
	t.check(host_watch > 0 and guest_watch > 0, "each friend is Night Watch some rounds (host %d, guest %d of 24)" % [host_watch, guest_watch])
	t.check(host_watch < 24 and guest_watch < 24, "and a runner others")
	rig.teardown()


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
	t.check(human_patrol <= 2, "never all three humans on the Night Watch (one human runner kept; %d)" % human_patrol)
	rig.queue_free()


## A whole 3-round friend series over the loopback network: round
## boundaries, ready gating between rounds, fair Night Watch rotation,
## results that can't be counted twice, a guest who leaves and comes back
## between rounds keeping their standing, then the finish and a reset.
func test_three_round_series_end_to_end() -> void:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(20, 3, 0.0, 2)
	await rig.wait_until(func() -> bool: return rig.host.human_count() == 3, 300)
	t.eq(int(rig.host.settings["rounds"]), PartySeries.DEFAULT_ROUNDS, "friend parties default to 3 rounds")
	for c in rig.clients:
		c.set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.can_start(), 300)
	var seen_rounds: Array = []
	for round in [1, 2, 3]:
		rig.host.host_start_match(100 + round)
		await rig.wait_until(func() -> bool: return rig.started.has(rig.clients[0]) and int(rig.started[rig.clients[0]]["series"]["round"]) == round, 300)
		var info: Dictionary = rig.started[rig.clients[0]]
		seen_rounds.append([int(info["series"]["round"]), int(info["series"]["total"])])
		t.eq(info["settings"]["watch"], 2, "round %d: the series' locked settings" % round)
		var hmc := rig.host_mc()
		await rig.wait_until(func() -> bool: return hmc.sim != null and hmc.sim.phase == TC.Phase.PLAYING, 1200)
		hmc.sim.end_tick = hmc.sim.tick + 2          # time runs out: Night Watch win
		var last: NetSession = rig.clients[-1]    # the rejoined guest from round 2 on
		await rig.wait_until(func() -> bool: return rig.results.has(last) and int(rig.results[last].get("round_index", 0)) == round, 1200)
		var res: Dictionary = rig.results.get(last, {})
		t.eq([int(res["round_index"]), int(res["rounds_total"])], [round, 3], "round %d results say Round %d of 3" % [round, round])
		# the same results again (a repeated packet / reopened screen) change nothing
		var before := JSON.stringify(rig.host.series.to_dict())
		rig.host.series.record_round(rig.host.last_results)
		t.eq(JSON.stringify(rig.host.series.to_dict()), before, "round %d can't be counted twice" % round)
		if round < 3:
			rig.host.host_return_to_lobby()
			await rig.frames(10)
			t.check(rig.host.series.in_progress(), "the series continues")
			t.check(not rig.host.can_start(), "the next round waits for the guests to be ready")
			if round == 1:
				# a guest drops between rounds and comes back with the same identity
				rig.client_ts[1].close()
				await rig.frames(40)
				var back := rig.add_client("uid-c1", "Client1", "any")
				await rig.wait_until(func() -> bool: return back.local_slot >= 0, 300)
			for c in rig.clients:
				if c.connected and c.local_slot >= 0:
					c.set_local_ready(true)
			await rig.wait_until(func() -> bool: return rig.host.can_start(), 300)
	t.eq(seen_rounds, [[1, 3], [2, 3], [3, 3]], "Round 1 of 3, 2 of 3, 3 of 3")
	var view: Dictionary = rig.host.series.to_dict()
	t.check(bool(view["finished"]), "finished after the third round")
	t.check(not rig.host.can_start(), "the final standings are on show (no accidental start)")
	var st: Dictionary = view["standings"]
	var turns := 0
	for uid in ["uid-host", "uid-c0", "uid-c1"]:
		t.check(st.has(uid), "%s has one standing for the whole series" % uid)
		t.eq(int(st[uid]["played"]), 3, "%s played all three rounds (reconnecting kept the standing)" % uid)
		turns += int(st[uid]["watch_turns"])
		t.eq(int(st[uid]["watch_turns"]) + int(st[uid]["runner_turns"]), 3, "%s has a role every round" % uid)
	# (build 33) roles are a fresh draw each round: never all three friends
	# on the Night Watch in a round
	t.check(turns <= 6, "at most two of the three on the Night Watch in a round (%d turns in 3 rounds)" % turns)
	var board := PartySeries.leaderboard_of(st)
	t.eq(board.size(), 3, "three people on the leaderboard (bots kept out)")
	# Play again: a fresh series with the same settings
	rig.host.host_return_to_lobby()
	t.check(rig.host.series == null, "the finished series is cleared for the next one")
	t.eq(int(rig.host.settings["rounds"]), 3, "settings are kept")
	rig.teardown()


## Rewards: a short drop-out keeps the round's reward; being away for most
## of it (a bot covered) gives none; either way the round is recorded once.
func test_reward_eligibility_and_dedup() -> void:
	var row := {"slot": 2, "uid": "u-elig", "role": TC.Role.RUNNER, "stamps": 2, "finished": false, "is_bot": false, "present": true, "away_s": 3.0}
	var res := {"match_id": "ELIG-1-%d" % Time.get_ticks_usec(), "outcome": TC.Outcome.RUNNERS_WIN, "fastest_slot": -1, "round_time": 180.0, "players": [row]}
	var r1 := Save.apply_results(res, 2, false, "u-elig")
	t.check(int(r1.get("coins", 0)) > 0 and not r1.has("away"), "a 3 s drop-out in a 180 s round keeps the reward")
	t.eq(Save.apply_results(res, 2, false, "u-elig"), {}, "the same round never pays twice")
	var row2 := row.duplicate()
	row2["away_s"] = 120.0
	var res2 := {"match_id": "ELIG-2-%d" % Time.get_ticks_usec(), "outcome": TC.Outcome.RUNNERS_WIN, "fastest_slot": -1, "round_time": 180.0, "players": [row2]}
	var r2 := Save.apply_results(res2, 2, false, "u-elig")
	t.check(bool(r2.get("away", false)) and int(r2.get("coins", -1)) == 0, "away for two thirds of the round: no reward")
	# a guest's copy of the results keeps the round length
	var ns := NetSession.new()
	var fixed := ns._fix_results(JSON.parse_string(JSON.stringify(res)))
	ns.free()
	t.eq(float(fixed.get("round_time", 0.0)), 180.0, "guests' results keep the round length")


func _practice_start(pref: String, seed_v: int, tutorial: bool = false) -> Dictionary:
	var s := NetSession.new()
	t.add_child(s)
	s.start_offline("u-prac", "Tester", {}, pref, tutorial)
	var info := {}
	var grab := func(i: Dictionary) -> void: info.merge(i, true)
	s.match_starting.connect(grab, CONNECT_ONE_SHOT)
	s.host_start_match(seed_v)
	var mine := -1
	var watch := 0
	for e in info.get("roster", []):
		if int(e["role"]) == TC.Role.PATROL:
			watch += 1
		if String(e["uid"]) == "u-prac":
			mine = int(e["role"])
	s.queue_free()
	return {"mine": mine, "watch": watch, "n": (info.get("roster", []) as Array).size(), "settings": info.get("settings", {}),
		"practice": bool(info.get("practice", false))}


## Solo practice: the player picks Runner, Night Watch or Random; bots fill
## the other seats and the Night Watch count stays the round's setting.
func test_offline_practice_role_choice() -> void:
	for seed_v in [11, 12, 13]:
		var r := _practice_start("runner", seed_v)
		t.eq(r["mine"], TC.Role.RUNNER, "Runner chosen -> runner (seed %d)" % seed_v)
		t.eq(r["watch"], int(r["settings"]["watch"]), "bots fill the Night Watch seats")
		t.eq(r["n"], PartySeries.SLOTS, "a full roster of %d" % PartySeries.SLOTS)
		t.check(r["practice"], "marked as practice")
		var w := _practice_start("patrol", seed_v)
		t.eq(w["mine"], TC.Role.PATROL, "Night Watch chosen -> Night Watch (seed %d)" % seed_v)
		t.eq(w["watch"], int(w["settings"]["watch"]), "still the set number of Night Watch, you included")
	var seen := {}
	for seed_v in range(1, 41):
		var x := _practice_start("random", seed_v)
		seen[x["mine"]] = true
		t.eq(x["watch"], int(x["settings"]["watch"]), "Random keeps the Night Watch count (seed %d)" % seed_v)
	t.check(seen.has(TC.Role.RUNNER) and seen.has(TC.Role.PATROL), "Random gives both roles over 40 rounds")
	var tr := _practice_start("patrol", 5, true)
	t.eq(tr["mine"], TC.Role.PATROL, "Night Watch training: you watch")
	t.eq(tr["watch"], 1, "Night Watch training: you are the only watcher")
