extends RefCounted
## Night Watch bots and the waters.  A Night Watch has no reason to enter a
## water, but its patrol route and splash investigations are centred on the
## waters.  On Moonbrook College's Boathouse Inlet the nearest open nav cell
## to the water's centre is on the dock, which the foot grid doesn't connect
## to the shore, so every path there came back empty; the bot then steered
## straight at the centre, splashed, resurfaced at a shore exit (11 m from
## the centre, never inside the 8 m "arrived" radius, so the stop never
## advanced) and walked straight back in: a splash every ~2.1 s
## (practice --autoplay=runner --local-bot --seed=3: SPLASH_NOSTAMP a=1 b=5
## from t=17.8 s on).
var t
const R := TC.Role.RUNNER
const P := TC.Role.PATROL
const WINDOW_S := 30.0


## The offline practice round `--autoplay=runner --local-bot --seed=N
## --no-gamecenter --skip-onboarding` sets up (NetSession.host_start_match,
## MatchController._prep_sim): Moonbrook College, every seat a bot.
func _practice_round(seed_v: int) -> SimHarness:
	var map_id := CampusMaps.PLAY_DEFAULT
	var lay := CampusMaps.layout(map_id)
	var watch := PartySeries.DEFAULT_WATCH
	var cfg := PartySeries.rules_for(Rules.cfg, watch)
	# NetSession._practice_roles: slot 0 (the local player) runs, the others
	# drawn in seat order fill the Night Watch
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v ^ 0x51ce
	var others: Array = []
	for i in range(1, 8):
		others.append({"slot": i, "r": rng.randf()})
	others.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["r"] < b["r"])
	var roles: Array = []
	roles.resize(8)
	roles.fill(R)
	for i in mini(watch, others.size()):
		roles[int(others[i]["slot"])] = P
	var dorm := CampusDorms.pick(map_id, seed_v, "")
	var targets := RulesLogic.pick_targets(seed_v, [], RulesLogic.curated_combos(dorm, lay.pool_size()))
	var roster: Array = []
	for i in 8:
		roster.append({"slot": i, "uid": "bot-%d" % i, "name": "B%d" % i, "is_bot": true, "role": roles[i], "cosmetic": {}})
	var h := SimHarness.new(t)
	h.sim = MatchSim.new()
	t.add_child(h.sim)
	h.sim.setup(cfg, lay, roster, seed_v, targets, "practice-%d" % seed_v,
		{"practice": true, "patrol_release_extra_s": 0.0, "dorm": dorm,
		"coins": RulesLogic.pick_coins(seed_v, lay, dorm, targets, cfg),
		"bot_factory": func(s: MatchSim, p: SimPlayer) -> BotBrain: return BotBrain.new(s, p)})
	return h


## Records every splash of a Night Watch player from now on (sim.events
## holds one tick's events only): slot -> [seconds].
static func _watch_splashes(sim: MatchSim) -> Dictionary:
	var out := {}
	sim.event_emitted.connect(func(e: Dictionary) -> void:
		var ty := int(e["type"])
		if ty != TC.Ev.SPLASH_STAMP and ty != TC.Ev.SPLASH_NOSTAMP:
			return
		var p := sim.player(int(e["a"]))
		if p == null or not p.is_patrol():
			return
		if not out.has(p.id):
			out[p.id] = []
		(out[p.id] as Array).append(snappedf(float(int(e["t"])) / float(sim.cfg.sim_hz), 0.01)))
	return out


## The most splashes one Night Watch made inside any WINDOW_S window.
static func _worst_window(splashes: Dictionary) -> Array:
	var worst := [0, -1]
	for slot in splashes:
		var ts: Array = splashes[slot]
		for i in ts.size():
			var n := 0
			for j in range(i, ts.size()):
				if float(ts[j]) - float(ts[i]) < WINDOW_S:
					n += 1
			if n > int(worst[0]):
				worst = [n, int(slot)]
	return worst


## The reported round: practice seed 3, every seat a bot, 90 s of play.
func test_practice_seed3_night_watch_does_not_splash_loop() -> void:
	var h := _practice_round(3)
	t.check(h.sim.targets.has(5), "seed 3 practice still goes to the Boathouse Inlet (targets %s)" % str(h.sim.targets))
	var splashes := _watch_splashes(h.sim)
	await h.to_playing()
	var start := h.sim.tick
	while h.sim.tick - start < h.sim.cfg.ticks(90.0) and h.sim.phase == TC.Phase.PLAYING:
		await h.step()
	var worst := _worst_window(splashes)
	print("PATROL_WATER seed=3 patrol splashes %s" % str(splashes))
	t.check(int(worst[0]) <= 1, "no Night Watch bot splashes more than once in %d s (slot %d: %d)" % [int(WINDOW_S), int(worst[1]), int(worst[0])])
	h.free_sim()


## The situation itself, set up directly: a Night Watch bot on foot where
## the seed 3 one left its cart by the inlet, on its way to watch the inlet.
func test_night_watch_beside_inlet_watches_from_the_bank() -> void:
	var h := SimHarness.new(t)
	h.make([R, P, R, R, R, R, R, R], [0, 2, 5], [1], 3, {"map": CampusMaps.CLASSIC})
	await h.release_patrol()
	var splashes := _watch_splashes(h.sim)
	var wi := 5
	t.check(String(h.sim.layout.waters[wi]["id"]) == "inlet", "water 5 is the Boathouse Inlet")
	var b: BotBrain = h.sim.bots[1]
	b.patrol_stops = [h.sim.layout.waters[wi]["center"], h.sim.layout.waters[0]["center"]]
	b.stop_i = 0
	h.place(1, h.on_ground(Vector2(-3.5, -134.2)))
	var p := h.sim.player(1)
	var nearest := 1e9
	var start := h.sim.tick
	while h.sim.tick - start < h.sim.cfg.ticks(WINDOW_S):
		await h.step()
		if p.state == TC.PState.ACTIVE:
			nearest = minf(nearest, p.pos2().distance_to(h.sim.layout.waters[wi]["center"]))
	t.check(not splashes.has(1), "the Night Watch bot stays out of the inlet (%s)" % str(splashes.get(1, [])))
	t.check(nearest < 14.0, "it still goes and watches the inlet from the bank (closest %.1f m)" % nearest)
	t.check(b.stop_i > 0, "and moves on along its route afterwards")
	h.free_sim()


## Every water on every playable map: a Night Watch bot sent to watch it
## (a patrol stop, a splash marker to investigate) stands on the bank and
## moves on; it never walks in.
func test_night_watch_never_walks_into_any_water() -> void:
	for map_id in CampusMaps.ORDER:
		var lay := CampusMaps.layout(map_id)
		for wi in lay.waters.size():
			var w: Dictionary = lay.waters[wi]
			if (w["exits"] as Array).is_empty() or not lay.bounds.has_point(w["center"]):
				continue      # a runnel waded through, scenery beyond the play area
			var h := SimHarness.new(t)
			h.make([R, P, R, R, R, R, R, R], [0, 1, 2], [1], 5, {"map": map_id})
			await h.release_patrol()
			var splashes := _watch_splashes(h.sim)
			var b: BotBrain = h.sim.bots[1]
			var other := (wi + 1) % lay.waters.size()
			b.patrol_stops = [w["center"], lay.waters[other]["center"]]
			b.stop_i = 0
			# start from the farthest shore exit, 6 m further out (on open ground)
			var ex: Vector3 = w["exits"][0]
			var c: Vector2 = w["center"]
			for e in w["exits"]:
				if Vector2(e.x, e.z).distance_to(c) > Vector2(ex.x, ex.z).distance_to(c):
					ex = e
			var out := Vector2(ex.x, ex.z) + (Vector2(ex.x, ex.z) - c).normalized() * 6.0
			if not b.nav.is_walkable(out):
				out = Vector2(ex.x, ex.z)
			h.place(1, h.on_ground(out))
			var start := h.sim.tick
			while h.sim.tick - start < h.sim.cfg.ticks(20.0) and b.stop_i == 0:
				await h.step()
			t.check(not splashes.has(1), "%s %s: the Night Watch bot stays out of the water (splashes at %s)" % [map_id, w["name"], str(splashes.get(1, []))])
			t.check(b.stop_i > 0, "%s %s: it reaches the bank and moves on (at %s)" % [map_id, w["name"], str(h.sim.player(1).pos2().snapped(Vector2(0.1, 0.1)))])
			h.free_sim()
