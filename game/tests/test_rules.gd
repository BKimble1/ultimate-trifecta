extends RefCounted
## Pure rule logic (no physics).
var t


func test_combos_and_permutations() -> void:
	var all := RulesLogic.all_combos(6)
	t.eq(all.size(), 20, "20 three-target combinations of six waters")
	var cur := RulesLogic.curated_combos()
	# real scale (route_analysis.gd): the combinations whose ideal run fits
	# 85% of the round, and never fewer than the three shortest
	t.check(cur.size() >= 3 and cur.size() <= 20, "curated set exists (%d)" % cur.size())
	for c in cur:
		t.eq(c.size(), 3, "three targets")
		t.check(c[0] != c[1] and c[1] != c[2] and c[0] != c[2], "distinct targets")
		var perms := RulesLogic.permutations3(c)
		t.eq(perms.size(), 6, "six orders")
		var seen := {}
		for p in perms:
			seen[str(p)] = true
		t.eq(seen.size(), 6, "orders unique")


func test_route_table_fairness() -> void:
	var rt := RulesLogic.route_table()
	t.check(not rt.is_empty(), "route table present")
	t.eq((rt.get("unreachable", ["x"]) as Array).size(), 0, "every water reachable from the dorm")
	var lens: Array = []
	for cb in rt["combos"]:
		if (rt["curated"] as Array).has(cb["targets"]):
			lens.append(float(cb["length_m"]))
	lens.sort()
	t.check(float(lens[-1]) / float(lens[0]) <= 1.35, "curated routes comparable (max/min %.2f)" % (float(lens[-1]) / float(lens[0])))


func test_pick_targets_seeded_no_repeat() -> void:
	var cur := RulesLogic.curated_combos()
	var a := RulesLogic.pick_targets(123, [])
	var b := RulesLogic.pick_targets(123, [])
	t.eq(a, b, "same seed -> same targets for everyone")
	var prev := a
	for s in range(1, 200):
		var nxt := RulesLogic.pick_targets(s * 7919, prev)
		t.check(not RulesLogic._same_set(nxt, prev), "no immediate repeat (seed %d)" % s)
		t.check(cur.has(nxt), "choice is from the curated set")
		prev = nxt


func test_choose_pad_maximises_distance() -> void:
	var pads := [Vector2(0, 0), Vector2(20, 0), Vector2(0, 20)]
	var pick := RulesLogic.choose_pad(pads, [Vector2(1, 1), Vector2(18, 2)])
	t.eq(pick, Vector2(0, 20), "pad farthest from the nearest patrol")


func test_tag_geometry() -> void:
	var cfg: RulesConfig = Rules.cfg
	var f := Vector3(0, 0, -1)
	t.check(RulesLogic.tag_geometry_ok(Vector3.ZERO, f, Vector3(0, 0, -1.4), cfg), "in reach ahead")
	t.check(not RulesLogic.tag_geometry_ok(Vector3.ZERO, f, Vector3(0, 0, -(cfg.tag_reach_m + 0.2)), cfg), "out of reach")
	t.check(not RulesLogic.tag_geometry_ok(Vector3.ZERO, f, Vector3(0, 0, 1.0), cfg), "behind")
	t.check(not RulesLogic.tag_geometry_ok(Vector3.ZERO, f, Vector3(0, 2.0, -1.0), cfg), "too high")


func test_rewards_unique_captures_no_idle_survival() -> void:
	var cfg: RulesConfig = Rules.cfg
	var res := {"match_id": "m1", "outcome": TC.Outcome.PATROL_WIN, "fastest_slot": -1, "players": [
		{"slot": 0, "role": TC.Role.PATROL, "unique_captures": 2, "captures": 5},
		{"slot": 1, "role": TC.Role.RUNNER, "stamps": 0, "finished": false},
	]}
	var r0 := RulesLogic.compute_rewards(res, 0, cfg, false)
	var rc: Dictionary = Catalogue.economy()["round_coins"]
	t.eq(int(r0["xp"]), cfg.coins_participation + 2 * cfg.coins_unique_capture + cfg.coins_team_win, "patrol XP per unique runner, not per capture")
	t.eq(int(r0["coins"]), int(rc["completed"]) + 2 * int(rc["watch_distinct_tag"]) + int(rc["team_win"]), "V6 Coins per unique runner, not per capture")
	var r1 := RulesLogic.compute_rewards(res, 1, cfg, false)
	t.eq(int(r1["xp"]), cfg.coins_participation, "idle survival earns nothing extra (XP)")
	t.eq(int(r1["coins"]), int(rc["completed"]), "idle survival earns nothing extra (Coins)")
	var cancelled := res.duplicate(true)
	cancelled["outcome"] = TC.Outcome.CANCELLED
	t.eq(int(RulesLogic.compute_rewards(cancelled, 0, cfg, false)["coins"]), 0, "cancelled rounds pay nothing")


func test_level_curve() -> void:
	var cfg: RulesConfig = Rules.cfg
	var lx := RulesLogic.add_xp(1, 0, cfg.level_xp_base + 5, cfg)
	t.eq(int(lx[0]), 2, "levels up")
	t.eq(int(lx[1]), 5, "carries remainder")


func test_input_cmd_roundtrip() -> void:
	var c := InputCmd.new()
	c.seq = 123456
	c.move = Vector2(0.3, -0.71)
	c.steer = -0.5
	c.drive = 1.0
	c.cam_yaw = 4.2
	c.held = TC.BTN_SPRINT | TC.BTN_JUMP
	c.pressed = TC.BTN_TAG
	c.quantize()
	var b := StreamPeerBuffer.new()
	c.write(b)
	t.eq(b.data_array.size(), 12, "12 bytes per input")
	b.seek(0)
	var d := InputCmd.read(b)
	t.eq(d.seq, c.seq, "seq")
	t.check(d.move.is_equal_approx(c.move), "move exact after quantize")
	t.near(d.cam_yaw, c.cam_yaw, 0.0001, "yaw")
	t.eq(d.held, c.held, "held")
	t.eq(d.pressed, c.pressed, "pressed")


func test_save_reward_ledger_once() -> void:
	var saved := Save.data.duplicate(true)
	Save.data = Save.default_profile()
	var res := {"match_id": "room-1-abc", "outcome": TC.Outcome.RUNNERS_WIN, "fastest_slot": 0, "players": [
		{"slot": 0, "role": TC.Role.RUNNER, "stamps": 3, "finished": true, "times_captured": 1, "is_bot": false},
		{"slot": 1, "role": TC.Role.PATROL, "unique_captures": 1, "is_bot": true},
	]}
	var r1 := Save.apply_results(res, 0, false)
	var coins := int(Save.data["coins"])
	t.check(int(r1.get("coins", 0)) > 0, "first application pays")
	var r2 := Save.apply_results(res, 0, false)
	t.check(r2.is_empty(), "same match id never pays twice")
	t.eq(int(Save.data["coins"]), coins, "coins unchanged on replay")
	t.eq(int(Save.data["stats"]["online"]["with_bots"]), 1, "bot-filled match identifiable in stats")
	var pr := Save.apply_results({"match_id": "PRACTICE-1-x", "outcome": TC.Outcome.PATROL_WIN, "fastest_slot": -1, "players": [{"slot": 0, "role": TC.Role.RUNNER, "stamps": 1, "finished": false, "is_bot": false}]}, 0, true)
	t.eq(int(Save.data["stats"]["practice"]["matches"]), 1, "practice recorded separately")
	t.check(int(pr["coins"]) < Rules.cfg.coins_participation + 5 + 1, "practice rewards reduced")
	# versioned migration from a v1 profile
	var v1 := {"version": 1, "uid": "x", "name": "Old", "coins": 50, "stats": {"matches": 3, "wins": 2}}
	var m := Save.migrate(v1)
	t.eq(int(m["version"]), Save.VERSION, "migrated to current version")
	t.eq(int(m["stats"]["online"]["matches"]), 3, "v1 stats preserved as online stats")
	t.eq(int(m["coins"]), 50, "coins preserved")
	Save.data = saved
	Save.save_now()
