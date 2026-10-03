extends SceneTree
## Dorm balance harness (V6): the real simulation, physics and bots, headless.
## For every home dorm x three-water combination:
##   trip    six runner bots, the Night Watch kept in the shed: each bot's
##           time from GO to home (median) - fed back into route curation
##           (config/route_bot_times.json "dorms")
##   contact six runner bots and two Night Watch bots, a full round: time
##           from GO to the first runner seen by the Night Watch (first
##           contact), to the first capture, the first stamp (runners'
##           first objective) and the Night Watch's first arrival within
##           20 m of an active water (its first objective), runners home and
##           the outcome
## Usage (from the repo root):
##   tools/gd.sh --headless --fixed-fps 60 --path game -s res://tools/dorm_balance.gd -- [dorm|all] [trip|contact|both] [out.json] [seeds]
## Writes one JSON object per dorm x combo (and seed) to the out file; a
## summary per dorm is printed.  Deterministic for a seed; the numbers are
## bot play on this machine's physics, not people.

var _out_path := "user://dorm_balance.json"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var which := args[0] if args.size() > 0 else "all"
	var mode := args[1] if args.size() > 1 else "both"
	if args.size() > 2:
		_out_path = args[2]
	var seeds := int(args[3]) if args.size() > 3 else 1
	var only := int(args[4]) if args.size() > 4 else -1
	var dorms: Array = CampusDorms.ids() if which == "all" else [which]
	var rows: Array = []
	if FileAccess.file_exists(_out_path):
		var old: Variant = JSON.parse_string(FileAccess.get_file_as_string(_out_path))
		if old is Array:
			rows = (old as Array).filter(func(r: Dictionary) -> bool: return not dorms.has(String(r.get("dorm", ""))) or not (mode == "both" or String(r.get("mode", "")) == mode))
	var t0 := Time.get_ticks_msec()
	for d in dorms:
		var ci := -1
		for combo in RulesLogic.all_combos(6):
			ci += 1
			if only >= 0 and ci != only:
				continue
			for s in seeds:
				if mode == "trip" or mode == "both":
					rows.append(await _trip(d, combo, 500 + s))
				if mode == "contact" or mode == "both":
					rows.append(await _contact(d, combo, 900 + s))
			_save(rows)
			print("[balance] %s %s done (%.0f s)" % [d, str(combo), float(Time.get_ticks_msec() - t0) / 1000.0])
	_save(rows)
	quit()


func _save(rows: Array) -> void:
	var f := FileAccess.open(_out_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(rows, " "))


func _make(dorm: String, combo: Array, seed_v: int, watch_bots: bool) -> MatchSim:
	var sim := MatchSim.new()
	root.add_child(sim)
	var roster: Array = []
	for i in 8:
		var is_r := i < 6
		roster.append({"slot": i, "uid": "b%d" % i, "name": "B%d" % i, "is_bot": is_r or watch_bots, "role": TC.Role.RUNNER if is_r else TC.Role.PATROL, "cosmetic": {}})
	var cfg := PartySeries.rules_for(load("res://config/rules_default.tres") as RulesConfig, 2)
	sim.setup(cfg, CampusLayout.shared(), roster, seed_v, combo, "bal-%s-%d" % [dorm, seed_v],
		{"dorm": dorm, "bot_factory": func(s: MatchSim, p: SimPlayer) -> BotBrain: return BotBrain.new(s, p)})
	return sim


func _to_playing(sim: MatchSim) -> void:
	while sim.phase != TC.Phase.PLAYING:
		await physics_frame
		sim.step({})


func _trip(dorm: String, combo: Array, seed_v: int) -> Dictionary:
	var sim := _make(dorm, combo, seed_v, false)
	sim.cfg.runners_needed = 7
	await _to_playing(sim)
	var start := sim.tick
	var limit := sim.cfg.ticks(sim.cfg.match_duration_s)
	while sim.tick - start < limit:
		await physics_frame
		sim.step({})
		var done := 0
		for p in sim.players:
			if p.is_runner() and p.state == TC.PState.FINISHED:
				done += 1
		if done == 6:
			break
	var times: Array = []
	for p in sim.players:
		if p.is_runner() and p.finished_tick >= 0:
			times.append(float(p.finished_tick - start) / 60.0)
	times.sort()
	sim.queue_free()
	await process_frame
	return {"mode": "trip", "dorm": dorm, "targets": combo, "seed": seed_v, "finished": times.size(),
		"median_s": snappedf(float(times[times.size() / 2]), 0.1) if not times.is_empty() else -1.0,
		"min_s": snappedf(float(times[0]), 0.1) if not times.is_empty() else -1.0}


func _contact(dorm: String, combo: Array, seed_v: int) -> Dictionary:
	var sim := _make(dorm, combo, seed_v, true)
	await _to_playing(sim)
	var start := sim.tick
	# (lambdas capture locals by value: shared state lives in a dictionary)
	var m := {"first_contact": -1.0, "first_capture": -1.0, "first_stamp": -1.0, "watch_at_water": -1.0, "captures": 0}
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if int(ev["type"]) == TC.Ev.CAPTURE:
			m["captures"] = int(m["captures"]) + 1
			if float(m["first_capture"]) < 0.0:
				m["first_capture"] = float(sim.tick - start) / 60.0
		elif int(ev["type"]) == TC.Ev.SPLASH_STAMP and float(m["first_stamp"]) < 0.0:
			m["first_stamp"] = float(sim.tick - start) / 60.0)
	while sim.phase == TC.Phase.PLAYING:
		await physics_frame
		sim.step({})
		var tnow := float(sim.tick - start) / 60.0
		if float(m["first_contact"]) < 0.0:
			for p in sim.players:
				if p.is_runner() and p.spotted > 0.0:
					m["first_contact"] = tnow
					break
		if float(m["watch_at_water"]) < 0.0:
			for q in sim.players:
				if q.is_patrol():
					for wi in combo:
						if q.pos2().distance_to(sim.layout.waters[int(wi)]["center"]) < 20.0:
							m["watch_at_water"] = tnow
	var out := {"mode": "contact", "dorm": dorm, "targets": combo, "seed": seed_v,
		"first_contact_s": snappedf(float(m["first_contact"]), 0.1), "first_capture_s": snappedf(float(m["first_capture"]), 0.1),
		"first_stamp_s": snappedf(float(m["first_stamp"]), 0.1), "watch_first_water_s": snappedf(float(m["watch_at_water"]), 0.1),
		"captures": int(m["captures"]), "home": sim.finished_count, "outcome": sim.outcome}
	sim.queue_free()
	await process_frame
	return out
