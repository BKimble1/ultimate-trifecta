extends SceneTree
## Development: plays one full bot round headless on the playable map and
## saves its real results for the results-screen capture (capture.gd
## "results" with --capture-results=path).  Seat 0 is shown as you and seat
## 1 as a second real player, so the round counts for Rankings.
## Usage: tools/gd.sh --headless --fixed-fps 60 --path game -s res://tools/make_results_fixture.gd -- out.var [seed]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://results_fixture.var"
	var seed_v := int(args[1]) if args.size() > 1 else 2026
	var map_id := CampusMaps.PLAY_DEFAULT
	var lay := CampusMaps.layout(map_id)
	var dorm: String = CampusDorms.ids(map_id, true)[seed_v % 3]
	var combos: Array = RulesLogic.curated_combos(dorm)
	var cfg := PartySeries.rules_for(load("res://config/rules_default.tres") as RulesConfig, 2)
	var roster: Array = []
	for i in 8:
		roster.append({"slot": i, "uid": "b%d" % i, "name": ["You", "Comfy Panda 38", "Moonbeam", "Snooze", "Pajamarama", "Yawn", "Pillow", "Sockfoot"][i],
			"is_bot": true, "role": TC.Role.RUNNER if i < cfg.runner_slots else TC.Role.PATROL, "cosmetic": Cosmetics.bot_cosmetic(seed_v + i * 13)})
	var sim := MatchSim.new()
	root.add_child(sim)
	sim.setup(cfg, lay, roster, seed_v, combos[seed_v % combos.size()], "fixture-%d" % seed_v,
		{"dorm": dorm, "bot_factory": func(s: MatchSim, p: SimPlayer) -> BotBrain: return BotBrain.new(s, p)})
	while sim.phase != TC.Phase.RESULTS and sim.phase != TC.Phase.ENDED:
		await physics_frame
		sim.step({})
	var res: Dictionary = sim.results if not sim.results.is_empty() else sim.build_results()
	for r in res["players"]:
		if int(r["slot"]) <= 1:
			r["is_bot"] = false
			r["was_human"] = true
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(var_to_str({"results": res, "reward": {}, "local_slot": 0}))
	f.close()
	print("fixture: outcome %d, you: finished %s in %.1f s" % [int(res["outcome"]), str(res["players"][0]["finished"]), float(res["players"][0]["finish_time"])])
	quit()
