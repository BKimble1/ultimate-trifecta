extends RefCounted
## Pass 8: the live Runner pace (RunnerPace, PaceFields, protocol 7).
## Ordering rules (home order, stamps, remaining route with every visit
## order, shared places within the tolerance, unknown routes), bots in the
## denominator, playable routes (real doors, no line through a building),
## the debounce, the budget (no path search, a bounded 2 Hz update), and
## the snapshot block (runners only, no positions or others' goals).
var t


func _e(slot: int, stamps: int, cost: float, home: bool = false, tick: int = -1) -> Dictionary:
	return {"slot": slot, "home": home, "tick": tick, "stamps": stamps, "cost": cost}


func test_order_rules_and_shared_places() -> void:
	var r := RunnerPace.rank([
		_e(0, 1, 30.0), _e(1, 3, 0.0, true, 900), _e(2, 2, 200.0), _e(3, 2, 120.0),
		_e(4, 3, 0.0, true, 700), _e(5, 1, 32.5), _e(6, 0, 10.0)], 4.0)
	t.eq(int(r[4]["place"]), 1, "home first, in finish order (earlier tick)")
	t.eq(int(r[1]["place"]), 2, "then the second home")
	t.check(bool(r[4]["home"]) and not bool(r[4]["tied"]), "home flagged, not tied")
	t.eq(int(r[3]["place"]), 3, "2 stamps, shorter route remaining")
	t.eq(int(r[2]["place"]), 4, "2 stamps, longer route")
	t.eq(int(r[0]["place"]), 5, "1 stamp: 30 m and 32.5 m are within 4 m...")
	t.eq(int(r[5]["place"]), 5, "...so they share 5th")
	t.check(bool(r[0]["tied"]) and bool(r[5]["tied"]), "and both say tied")
	t.eq(int(r[6]["place"]), 7, "0 stamps last even when nearest to a water (shared places skip: 1 2 3 4 5 5 7)")
	# same-tick finishes share a place; the tolerance is anchored (no chaining)
	var r2 := RunnerPace.rank([_e(0, 3, 0, true, 500), _e(1, 3, 0, true, 500), _e(2, 1, 10.0), _e(3, 1, 13.0), _e(4, 1, 16.0)], 4.0)
	t.check(int(r2[0]["place"]) == 1 and int(r2[1]["place"]) == 1 and bool(r2[0]["tied"]), "two crossings on one tick share 1st")
	t.check(int(r2[2]["place"]) == 3 and int(r2[3]["place"]) == 3, "10 m and 13 m share 3rd")
	t.eq(int(r2[4]["place"]), 5, "16 m is 6 m behind the group's first: its own place (no chaining through 13 m)")
	# stable slot order never breaks a tie: identical routes share
	var r3 := RunnerPace.rank([_e(5, 2, 50.0), _e(2, 2, 50.0)], 4.0)
	t.eq(int(r3[5]["place"]), int(r3[2]["place"]), "equal routes share a place whatever the slots")


func test_unknown_routes_are_never_an_invented_place() -> void:
	var r := RunnerPace.rank([_e(0, 2, 40.0), _e(1, 2, -1.0), _e(2, 2, 10.0), _e(3, 1, 5.0), _e(4, 1, INF)], 4.0)
	t.check(int(r[0]["place"]) == 1 and int(r[1]["place"]) == 1 and int(r[2]["place"]) == 1, "a stamp group with an unknown route shares one place")
	t.check(bool(r[0]["approx"]) and bool(r[1]["approx"]) and bool(r[2]["approx"]), "flagged approximate (stamp-based)")
	t.check(int(r[3]["place"]) == 4 and int(r[4]["place"]) == 4 and bool(r[4]["approx"]), "the next stamp group too")
	t.eq(RunnerPace.label({}, 6), "Runner pace: updating", "no pace yet: 'updating', not a place")
	t.eq(RunnerPace.label({"place": 3, "tied": false, "home": false}, 6), "Runner pace: 3rd/6", "the brief's wording")
	t.eq(RunnerPace.label({"place": 2, "tied": true, "home": false}, 6), "Runner pace: tied 2nd/6", "a shared place says so")
	t.eq(RunnerPace.label({"place": 4, "tied": false, "home": false}, 6, true), "Runner pace: Not home", "after the round: Not home, never a made-up finish")
	t.eq(RunnerPace.label({"place": 1, "tied": false, "home": true}, 6, true), "Runner pace: 1st/6", "a finish stays a finish")


func test_every_visit_order_is_enumerated() -> void:
	var p3 := RunnerPace.permutations([0, 1, 2])
	t.eq(p3.size(), 6, "three remaining waters: six orders")
	var seen := {}
	for o in p3:
		seen[str(o)] = true
		t.eq((o as Array).size(), 3, "each order visits all three")
	t.eq(seen.size(), 6, "all distinct")
	t.eq(RunnerPace.permutations([2, 0]).size(), 2, "two remaining: two orders")
	t.eq(RunnerPace.permutations([1]).size(), 1, "one remaining: one")


func _sim(h: SimHarness) -> MatchSim:
	# 6 runners (slot 5 a bot) and 2 Night Watch, tonight's dorm the default
	var roles := [TC.Role.RUNNER, TC.Role.RUNNER, TC.Role.RUNNER, TC.Role.RUNNER, TC.Role.RUNNER, TC.Role.RUNNER, TC.Role.PATROL, TC.Role.PATROL]
	var s := h.make(roles, [0, 1, 2], [5], 21)
	PaceFields.settle()              # tests only: the worker's fields, now
	return s


func test_routes_are_playable_and_orders_are_optimal() -> void:
	var h := SimHarness.new(t)
	var sim := _sim(h)
	var pc := sim.pace
	pc.update(sim)
	t.check(pc.ready, "fields built (PaceFields: %s)" % str(PaceFields.stats))
	var lay := sim.layout
	# a water's own entry points cost nothing to reach
	for wi in [0, 1, 2]:
		var f := PaceFields.field(PaceFields.water_key(wi))
		for jp in lay.waters[wi]["jump_points"]:
			t.check(PaceFields.metres(f, PaceFields.cell_of(jp)) <= 0.01, "water %d: an entry point is a source" % wi)
	# a route is never shorter than the straight line, and buildings force
	# detours: never a line through a building or across the water
	var f0 := PaceFields.field(PaceFields.water_key(0))
	var srcs: Array = []
	for jp in lay.waters[0]["jump_points"]:
		srcs.append(jp)
	for e in lay.waters[0]["exits"]:
		srcs.append(Vector2((e as Vector3).x, (e as Vector3).z))
	var worst_ratio := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var n := 0
	for i in 400:
		var p := Vector2(rng.randf_range(-150, 150), rng.randf_range(-140, 140))
		# open ground only: a point inside a building (the real library is
		# 65 x 86 m) is looked up at an open cell up to 8 m away
		if lay.building_at(p) >= 0 or lay.water_index_at(p, 1.0) >= 0:
			continue
		var c := PaceFields.cell_of(p)
		var m := PaceFields.metres(f0, c)
		if m == INF:
			continue
		var straight := INF
		for s in srcs:
			straight = minf(straight, (s as Vector2).distance_to(p))
		n += 1
		t.check(m >= straight - 3.0, "never shorter than the straight line (%.1f m vs %.1f m at %s)" % [m, straight, str(p)])
		if straight > 20.0:
			worst_ratio = maxf(worst_ratio, m / straight)
	t.check(n > 200, "most of the campus is reachable (%d of 400 samples)" % n)
	t.check(worst_ratio > 1.3, "obstacles really bend routes (a %.2f detour)" % worst_ratio)
	# behind tonight's dorm (no door on that side): the way home goes round
	var g := CampusDorms.geometry(sim.home_dorm)
	# behind the dorm: outside the wall farthest from every door
	var fp: PackedVector2Array = CampusData.ccw(g["footprint"])
	var behind := Vector2.INF
	var far := -1.0
	for i in fp.size():
		var a := fp[i]
		var b := fp[(i + 1) % fp.size()]
		if a.distance_to(b) < 6.0:
			continue
		var dd := (b - a).normalized()
		var q := (a + b) * 0.5 + Vector2(dd.y, -dd.x) * 3.0
		var near := INF
		for d in g["doors"]:
			near = minf(near, (d["pos"] as Vector2).distance_to(q))
		if near > far and h.sim.layout.building_at(q, 0.5) < 0:
			far = near
			behind = q
	var hf := PaceFields.field(PaceFields.home_key(sim.home_dorm))
	var straight_door := INF
	var by_route := INF
	var best_door := -1
	var nav := NavGrid.shared(h.sim.layout)
	for di in (g["doors"] as Array).size():
		var d: Dictionary = g["doors"][di]
		straight_door = minf(straight_door, (d["approach"] as Vector2).distance_to(behind))
		var pth := nav.find_path(behind, d["approach"])
		if pth.size() >= 2 and nav.path_length(pth) < by_route:
			by_route = nav.path_length(pth)
			best_door = di
	var hm := PaceFields.metres(hf, PaceFields.cell_of(behind))
	t.check(hm != INF and hm > straight_door + 3.0, "behind the dorm, home is round the building (%.1f m by route vs %.1f m straight)" % [hm, straight_door])
	var door := PaceFields.label_at(hf, PaceFields.cell_of(behind))
	t.eq(door, best_door, "and the suggested door is the nearest by route, never through the building (door %d)" % door)
	# the pace's route = the best of every order, checked by hand
	var p0 := sim.player(0)
	h.place(0, Vector3(-30, 0.05, 40))
	p0.stamps = 0
	var r := pc.route_of(p0)
	var cell := PaceFields.cell_of(p0.pos2())
	var best := INF
	var first := -1
	for order in RunnerPace.permutations([0, 1, 2]):
		var cost := PaceFields.metres(PaceFields.field(PaceFields.water_key(int(order[0]))), cell)
		for k in range(1, 3):
			var a := int(order[k - 1])
			var b := int(order[k])
			var leg := INF
			for e in lay.waters[a]["exits"]:
				leg = minf(leg, PaceFields.metres(PaceFields.field(PaceFields.water_key(b)), PaceFields.cell_of(Vector2((e as Vector3).x, (e as Vector3).z))))
			cost += leg
		var last := int(order[2])
		var home := INF
		for e2 in lay.waters[last]["exits"]:
			home = minf(home, PaceFields.metres(hf, PaceFields.cell_of(Vector2((e2 as Vector3).x, (e2 as Vector3).z))))
		cost += home
		if cost < best:
			best = cost
			first = int(order[0])
	t.check(absf(float(r[0]) - best) < 0.01, "remaining route is the best of the six orders (%.1f vs %.1f)" % [float(r[0]), best])
	t.eq(int(r[1]), first, "and the suggested next water is that order's first")
	h.free_sim()


func test_pace_in_a_round_with_bots() -> void:
	var h := SimHarness.new(t)
	var sim := _sim(h)
	var pc := sim.pace
	var lay := sim.layout
	var fw: Vector2 = lay.waters[0]["center"]
	# 0: next to the fountain, nothing stamped; 1: far away, nothing stamped
	h.place(0, Vector3(fw.x, 0.05, fw.y - 9.0))
	h.place(1, Vector3(-80, 0.05, -74))
	# 2: far away but one stamp; 3: home already; 4: two stamps; 5 (a bot)
	h.place(2, Vector3(-80, 0.05, -70))
	sim.player(2).stamps = 1
	sim.player(3).finished_tick = 800
	sim.player(3).stamps = 7
	sim.player(3).state = TC.PState.FINISHED
	sim.player(4).stamps = 3
	h.place(4, Vector3(fw.x + 9.0, 0.05, fw.y))
	sim.player(5).stamps = 0
	h.place(5, Vector3(fw.x, 0.05, fw.y + 40.0))
	pc.update(sim)
	var pl := pc.places
	t.eq(pc.runners, 6, "every runner counts, the bot included (denominator 6)")
	t.eq(pl.size(), 6, "six places published")
	t.eq(int(pl[3]["place"]), 1, "home runner first")
	t.eq(int(pl[4]["place"]), 2, "two stamps next")
	t.eq(int(pl[2]["place"]), 3, "one stamp beats a shorter route with none")
	t.check(int(pl[0]["place"]) < int(pl[1]["place"]), "same stamps: the nearer remaining route ahead (%d vs %d)" % [int(pl[0]["place"]), int(pl[1]["place"])])
	t.check(int(pl[5]["place"]) > int(pl[0]["place"]), "the bot is ranked like anyone else")
	t.check(int(pc.next_goal.get(4, -1)) == 2, "two stamps (fountain, pond): the pool is next (%d)" % int(pc.next_goal.get(4, -1)))
	# a catch costs pace: the hold left is added at jog speed; stamps stay
	var before := float(pc.route_of(sim.player(0))[0])
	sim.player(0).state = TC.PState.CAPTURED
	sim.player(0).penalty = 6.0
	var caught := float(pc.route_of(sim.player(0))[0])
	t.check(caught >= 6.0 * sim.cfg.runner_speed - 0.01, "caught: the hold counts (%.1f m vs %.1f m before)" % [caught, before])
	sim.player(0).state = TC.PState.ACTIVE
	# a stamp change publishes at once; a route-only change after two updates
	var rev := pc.revision
	sim.player(1).stamps = 7
	pc.update(sim)
	t.check(pc.revision == rev + 1 and int(pc.places[1]["place"]) == 2, "a third stamp moves the runner up at once (%d)" % int(pc.places[1]["place"]))
	rev = pc.revision
	var a0 := int(pc.places[0]["place"])
	var a5 := int(pc.places[5]["place"])
	# swap who is near and who is far (same stamps): needs to hold for 1 s
	h.place(0, Vector3(fw.x, 0.05, fw.y + 40.0))
	h.place(5, Vector3(fw.x, 0.05, fw.y - 9.0))
	pc.update(sim)
	t.eq(pc.revision, rev, "a route-only change isn't published on its first update")
	t.eq(int(pc.places[0]["place"]), a0, "(no flicker)")
	pc.update(sim)
	t.eq(pc.revision, rev + 1, "it is once it held for two updates")
	t.check(int(pc.places[5]["place"]) < int(pc.places[0]["place"]) and int(pc.places[5]["place"]) == mini(a0, a5), "the order swapped")
	h.free_sim()


func test_budget_and_no_path_search() -> void:
	var h := SimHarness.new(t)
	var sim := _sim(h)
	var pc := sim.pace
	pc.update(sim)
	var nav := NavGrid.shared(sim.layout)
	var searches := int(nav.path_stats["search"])
	var t0 := Time.get_ticks_usec()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var each: Array[float] = []
	for i in 200:
		# runners spread over the campus with mixed stamps and states
		for s in 6:
			var p := sim.player(s)
			p.stamps = rng.randi() % 8
			h.place(s, Vector3(rng.randf_range(-120, 120), 0.05, rng.randf_range(-120, 120)))
		var tu := Time.get_ticks_usec()
		pc.update(sim)
		each.append(float(Time.get_ticks_usec() - tu))
	var us := float(Time.get_ticks_usec() - t0) / 200.0
	var cost := pc.cost_us()
	each.sort()
	print("[pace budget] update p50 %.0f us, p95 %.0f us, p99 %.0f us, max %.0f us (200 updates, 6 runners); mean incl. placement %.0f us; fields %s" % [
		each[100], each[190], each[198], each[199], us, str(PaceFields.stats)])
	t.check(float(cost["mean"]) < 2000.0, "a 2 Hz update of six runners costs well under a frame (mean %.0f us)" % float(cost["mean"]))
	t.eq(int(nav.path_stats["search"]), searches, "pace never starts a path search")
	t.check(float(PaceFields.stats["extract_ms"]) > 0.0 and (PaceFields.stats["fields"] as Dictionary).size() >= 4, "field build times recorded")
	# the request itself (on the main thread, in loading) is cheap
	PaceFields.clear()
	var tr := Time.get_ticks_usec()
	PaceFields.request(sim.layout, [3, 4, 5], sim.home_dorm)
	var req_ms := float(Time.get_ticks_usec() - tr) / 1000.0
	t.check(req_ms < 20.0, "requesting fields only starts a worker (%.2f ms on the main thread)" % req_ms)
	PaceFields.settle()
	h.free_sim()


func test_snapshot_block_is_runners_only_and_positionless() -> void:
	var h := SimHarness.new(t)
	var sim := _sim(h)
	await h.to_playing()
	sim.pace.update(sim)
	var runner := sim.player(0)
	var watch := sim.player(6)
	var data := Protocol.encode_snapshot(sim, runner, sim.players, 0, true)
	var b := Protocol.reader(data)
	b.get_u8()
	var s := Protocol.decode_snapshot(b)
	var me: Dictionary = s.get("me", {})
	var pace: Dictionary = me.get("pace", {})
	t.eq(pace.size(), 6, "a runner gets every runner's place")
	for slot in pace:
		var keys: Array = (pace[slot] as Dictionary).keys()
		keys.sort()
		t.eq(keys, ["approx", "home", "place", "stamps", "tied"], "only place, flags and stamps: no position, no destination")
	t.eq(int(me.get("next_goal", -1)), int(sim.pace.next_goal.get(0, RunnerPace.NO_GOAL)), "and only its own next goal")
	t.eq(int(pace[0]["place"]), int(sim.pace.places[0]["place"]), "places survive the wire")
	var sb := StreamPeerBuffer.new()
	Protocol.put_pace(sb, sim, runner)
	t.eq(sb.data_array.size(), 2 + 3 * 6, "the block is 2 + 3 bytes per runner")
	var wd := Protocol.encode_snapshot(sim, watch, sim.players, 0, true)
	var wb := Protocol.reader(wd)
	wb.get_u8()
	var ws := Protocol.decode_snapshot(wb)
	t.eq((ws["me"]["pace"] as Dictionary).size(), 0, "the Night Watch gets no pace")
	t.eq(int(ws["me"]["next_goal"]), RunnerPace.NO_GOAL, "and no runner's goal")
	t.check(data.size() < 1000, "the snapshot still fits one packet (%d bytes)" % data.size())
	t.eq(Protocol.VERSION, 9, "protocol 9 (Pass 9 steady movement; the Pass 8 pace block kept; 24-bit positions for the rebuilt campus)")
	h.free_sim()


func test_pace_reaches_a_guest_runner_not_the_guest_watch() -> void:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(20, 0, 0.0, 2, ["runner", "runner", "patrol"])
	var c0: NetSession = rig.clients[0]
	var c1: NetSession = rig.clients[1]
	await rig.wait_until(func() -> bool: return c0.local_slot >= 0 and c1.local_slot >= 0 and rig.host.human_count() == 3, 300)
	for c in rig.clients:
		c.set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.can_start(), 200)
	rig.host.host_start_match(77)
	var ok := await rig.wait_until(func() -> bool: return rig.host.sim != null and rig.host.sim.phase == TC.Phase.PLAYING \
		and rig.mc_of(c0) != null and rig.mc_of(c0).prepared and rig.mc_of(c1) != null and rig.mc_of(c1).prepared, 1500)
	t.check(ok, "party round playing")
	PaceFields.settle()
	await rig.wait_until(func() -> bool: return rig.host.sim.pace != null and not rig.host.sim.pace.places.is_empty(), 200)
	await rig.frames(12)
	var g0 := rig.mc_of(c0)
	var g1 := rig.mc_of(c1)
	var runner_mc: MatchController = g0 if int(g0.roster[g0.local_slot]["role"]) == TC.Role.RUNNER else g1
	var watch_mc: MatchController = g1 if runner_mc == g0 else g0
	var ri := runner_mc.local_info()
	t.eq((ri["pace"] as Dictionary).size(), runner_mc.runner_count(), "the guest runner sees every runner's pace (bots included)")
	t.check((ri["pace"] as Dictionary).has(runner_mc.local_slot), "including its own place")
	var wi := watch_mc.local_info()
	if int(watch_mc.roster[watch_mc.local_slot]["role"]) == TC.Role.PATROL:
		t.eq((wi["pace"] as Dictionary).size(), 0, "the guest Night Watch gets none")
	runner_mc.hud.refresh(0.016)
	var rows: Array = runner_mc.hud.personal_rows
	var pace_rows := rows.filter(func(r: Dictionary) -> bool: return String(r["type"]) == "pace")
	t.eq(pace_rows.size(), 1, "the runner's card shows one pace line")
	if not pace_rows.is_empty():
		t.check(String(pace_rows[0]["text"]).begins_with("Runner pace: ") and String(pace_rows[0]["text"]).ends_with("/%d" % runner_mc.runner_count()),
			"'Runner pace: Nth/%d' (%s)" % [runner_mc.runner_count(), String(pace_rows[0]["text"])])
	rig.teardown()
	await t.get_tree().process_frame
	await t.get_tree().process_frame
