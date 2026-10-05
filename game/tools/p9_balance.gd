extends SceneTree
## Pass 9 balance matrix: full bot rounds (the real simulation, physics and
## bots, headless) for every supported team configuration (1, 2 or 3 Night
## Watch of 8 players), several seeds each, rotating through the three home
## dorms and their curated water combinations.  The same file runs on the
## 1.8 code (sprint meter) and on 1.9 (one steady speed), so the two builds
## are compared on identical seeds, rosters, dorms and waters.
##
## Per round: outcome, runners home, captures, stamps, round length, first
## stamp / capture, route time of the runners who got home, Tag attempts and
## hits, dives, gadget uses by kind, Turbo value (gap to the nearest Night
## Watch at use and 3 s later; caught within 10 s or not), chase episodes (a
## Night Watch within 8 m of a runner: ended by a capture or by the runner
## getting 15 m clear) and the average runner speed while moving on foot.
##
## Usage (from the repo root):
##   tools/gd.sh --headless --fixed-fps 60 --path game -s res://tools/p9_balance.gd -- out.json [seeds] [watch list] [nav]
##     seeds      rounds per configuration (default 8)
##     watch list e.g. 1,2,3 (default)
##     nav        "old" turns the Pass 9 bot path fixes off (1.9 only), to
##                separate them from the movement change
## Deterministic for a seed on one machine; bot play, not people.

var _out_path := "user://p9_balance.json"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_path = args[0]
	var seeds := int(args[1]) if args.size() > 1 else 8
	var watches: Array = []
	for w in (args[2] if args.size() > 2 else "1,2,3").split(","):
		watches.append(int(w))
	var nav := args[3] if args.size() > 3 else "new"
	if nav == "old":
		(BotBrain as Script).set("pass9_nav", false)
		print("[p9bal] Pass 9 bot path fixes: ", (BotBrain as Script).get("pass9_nav"))
	var rows: Array = []
	var t0 := Time.get_ticks_msec()
	var dorms: Array = CampusDorms.ids()
	for w in watches:
		for s in seeds:
			var dorm: String = dorms[s % dorms.size()]
			var combos: Array = RulesLogic.curated_combos(dorm)
			var combo: Array = combos[(s * 7 + int(w) * 3) % combos.size()]
			var row := await _round(dorm, combo, 2000 + s * 13 + int(w), int(w))
			row["nav"] = nav
			rows.append(row)
			_save(rows)
			print("[p9bal] watch %d seed %d %s %s -> %s home %d caught %d (%.0f s)" % [w, s, dorm, str(combo), str(row["outcome"]), row["home"], row["captures"], float(Time.get_ticks_msec() - t0) / 1000.0])
	_save(rows)
	quit()


func _save(rows: Array) -> void:
	var f := FileAccess.open(_out_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(rows, " "))


func _make(dorm: String, combo: Array, seed_v: int, watch: int) -> MatchSim:
	var sim := MatchSim.new()
	root.add_child(sim)
	var cfg := PartySeries.rules_for(load("res://config/rules_default.tres") as RulesConfig, watch)
	var roster: Array = []
	for i in 8:
		var is_r := i < cfg.runner_slots
		roster.append({"slot": i, "uid": "b%d" % i, "name": "B%d" % i, "is_bot": true, "role": TC.Role.RUNNER if is_r else TC.Role.PATROL, "cosmetic": {}})
	sim.setup(cfg, CampusLayout.shared(), roster, seed_v, combo, "p9bal-%s-%d" % [dorm, seed_v],
		{"dorm": dorm, "bot_factory": func(s: MatchSim, p: SimPlayer) -> BotBrain: return BotBrain.new(s, p)})
	return sim


static func _nearest_watch(sim: MatchSim, p: SimPlayer) -> float:
	var best := 1e9
	for q in sim.players:
		if q.is_patrol() and (q.state == TC.PState.ACTIVE or q.state == TC.PState.IN_CART):
			best = minf(best, q.pos2().distance_to(p.pos2()))
	return best


func _round(dorm: String, combo: Array, seed_v: int, watch: int) -> Dictionary:
	var sim := _make(dorm, combo, seed_v, watch)
	while sim.phase != TC.Phase.PLAYING:
		await physics_frame
		sim.step({})
	var start := sim.tick
	var m := {"captures": 0, "stamps": 0, "first_capture": -1.0, "first_stamp": -1.0, "tag_miss": 0,
		"gadgets": {}, "turbo": [], "end_tick": -1}
	sim.event_emitted.connect(func(ev: Dictionary) -> void:
		var ty := int(ev["type"])
		var tnow := float(sim.tick - start) / 60.0
		if ty == TC.Ev.CAPTURE:
			m["captures"] = int(m["captures"]) + 1
			if float(m["first_capture"]) < 0.0:
				m["first_capture"] = tnow
		elif ty == TC.Ev.TAG_MISS:
			m["tag_miss"] = int(m["tag_miss"]) + 1
		elif ty == TC.Ev.SPLASH_STAMP:
			m["stamps"] = int(m["stamps"]) + 1
			if float(m["first_stamp"]) < 0.0:
				m["first_stamp"] = tnow
		elif ty == TC.Ev.GADGET_USE:
			var g := int(ev["v"])
			var gd: Dictionary = m["gadgets"]
			gd[str(g)] = int(gd.get(str(g), 0)) + 1
			var user := sim.player(int(ev["a"]))
			if g == TC.Gadget.TURBO and user != null and user.is_runner():
				(m["turbo"] as Array).append({"slot": user.id, "t": sim.tick, "gap0": _nearest_watch(sim, user), "gap3": -1.0, "caught10": false})
		elif ty == TC.Ev.MATCH_END:
			m["end_tick"] = sim.tick)
	var dives := 0
	var was_diving := {}
	var speed_sum := 0.0
	var speed_n := 0
	var chases := {}       # runner slot -> {t0, min}
	var chase_rows: Array = []
	var caught_at := {}    # runner slot -> tick of capture (this round)
	while sim.phase == TC.Phase.PLAYING:
		await physics_frame
		sim.step({})
		for p in sim.players:
			if not p.is_runner():
				continue
			if p.diving and not bool(was_diving.get(p.id, false)):
				dives += 1
			was_diving[p.id] = p.diving
			if p.state == TC.PState.CAPTURED and not caught_at.has(p.id):
				caught_at[p.id] = sim.tick
			elif p.state != TC.PState.CAPTURED:
				caught_at.erase(p.id)
			if p.state != TC.PState.ACTIVE:
				if chases.has(p.id):
					var c: Dictionary = chases[p.id]
					chase_rows.append({"len_s": float(sim.tick - int(c["t0"])) / 60.0, "end": "caught" if p.state == TC.PState.CAPTURED else "other"})
					chases.erase(p.id)
				continue
			var sp := Vector2(p.vel.x, p.vel.z).length()
			if p.on_floor and sp > 1.0:
				speed_sum += sp
				speed_n += 1
			var near := _nearest_watch(sim, p)
			if not chases.has(p.id) and near < 8.0:
				chases[p.id] = {"t0": sim.tick}
			elif chases.has(p.id) and near > 15.0:
				var c2: Dictionary = chases[p.id]
				chase_rows.append({"len_s": float(sim.tick - int(c2["t0"])) / 60.0, "end": "escaped"})
				chases.erase(p.id)
		for tu in m["turbo"]:
			var u := sim.player(int(tu["slot"]))
			if float(tu["gap3"]) < 0.0 and sim.tick - int(tu["t"]) >= 180:
				tu["gap3"] = _nearest_watch(sim, u) if u.state == TC.PState.ACTIVE else 0.0
			if sim.tick - int(tu["t"]) <= 600 and u.state == TC.PState.CAPTURED:
				tu["caught10"] = true
	for slot in chases:
		chase_rows.append({"len_s": float(sim.tick - int((chases[slot] as Dictionary)["t0"])) / 60.0, "end": "round_end"})
	var times: Array = []
	for p in sim.players:
		if p.is_runner() and p.finished_tick >= 0:
			times.append(float(p.finished_tick - start) / 60.0)
	times.sort()
	var esc := chase_rows.filter(func(r: Dictionary) -> bool: return r["end"] == "escaped").size()
	var cau := chase_rows.filter(func(r: Dictionary) -> bool: return r["end"] == "caught").size()
	var out := {"dorm": dorm, "targets": combo, "seed": seed_v, "watch": watch, "runners": sim.cfg.runner_slots, "needed": sim.cfg.runners_needed,
		"outcome": ["none", "runners", "watch", "cancelled"][sim.outcome], "home": sim.finished_count, "captures": int(m["captures"]),
		"stamps": int(m["stamps"]), "round_s": snappedf(float(int(m["end_tick"]) - start) / 60.0 if int(m["end_tick"]) > 0 else float(sim.tick - start) / 60.0, 0.1),
		"first_stamp_s": snappedf(float(m["first_stamp"]), 0.1), "first_capture_s": snappedf(float(m["first_capture"]), 0.1),
		"route_median_s": snappedf(float(times[times.size() / 2]), 0.1) if not times.is_empty() else -1.0,
		"route_first_s": snappedf(float(times[0]), 0.1) if not times.is_empty() else -1.0,
		"tags": int(m["captures"]) + int(m["tag_miss"]), "tag_hits": int(m["captures"]), "dives": dives,
		"gadgets": m["gadgets"], "turbo": m["turbo"], "chases": chase_rows.size(), "chase_escaped": esc, "chase_caught": cau,
		"runner_speed_moving": snappedf(speed_sum / maxf(1.0, float(speed_n)), 0.01)}
	sim.queue_free()
	await process_frame
	return out
