extends RefCounted
## V6 gold coins in a round: where they go, who gets them, and that nothing
## can count one twice.
##  * the host's choice: seeded, spread out, clear of tonight's home doors and
##    the active waters' approaches, every candidate reachable on foot;
##  * the first valid collector (nearest, then lower slot), either role, bots
##    too; never while caught, splashing, home, waiting or driving;
##  * exactly one Coin per coin: a second pass, a replayed event, a
##    reconnect or a late snapshot can't add another; results rows carry
##    coins_picked (humans and bots) and a cancelled round still says so.
var t
const R := TC.Role.RUNNER
const P := TC.Role.PATROL


func _h() -> SimHarness:
	return SimHarness.new(t)


func test_candidate_spots_are_on_routes_and_reachable() -> void:
	var lay := CampusLayout.shared()
	var nav := NavGrid.shared(lay)
	t.check(lay.coin_spots.size() >= 20, "enough candidate spots (%d)" % lay.coin_spots.size())
	for i in lay.coin_spots.size():
		var p: Vector2 = lay.coin_spots[i]
		t.check(nav.is_walkable(p), "spot %d %s is on walkable ground" % [i, str(p)])
		t.check(CampusBuilder.water_at(lay, p) < 0, "spot %d is not in water" % i)
		for g in lay.gadget_spots:
			t.check(p.distance_to(g) >= 4.0, "spot %d is not on a gadget pickup" % i)
		for d in lay.dorm_doors:
			t.check(p.distance_to(d["pos"]) >= 10.0, "spot %d is away from every dorm door" % i)
		t.check(CampusDorms.district_of(p) == "" or not CampusDorms.in_room(CampusDorms.district_of(p), Vector3(p.x, 0, p.y)), "spot %d is outdoors" % i)
		for w in lay.waters:
			for e in w["exits"]:
				t.check(p.distance_to(Vector2((e as Vector3).x, (e as Vector3).z)) >= 6.0, "spot %d clear of %s's exits" % [i, w["id"]])
		for dm in lay.dorms:
			var path := nav.find_path(dm["geo"]["pads"][0]["pos"], p)
			t.check(path.size() >= 2 and path[-1].distance_to(p) < 1.0, "spot %d reachable on foot from %s" % [i, dm["id"]])


func test_round_coins_seeded_spread_and_clear() -> void:
	var lay := CampusLayout.shared()
	var cfg: RulesConfig = Rules.cfg
	var used := {}
	for d in CampusDorms.ids():
		var doors: Array = CampusDorms.geometry(d)["doors"]
		var combos := RulesLogic.curated_combos(d)
		for s in 120:
			var targets: Array = combos[s % combos.size()]
			var coins := RulesLogic.pick_coins(s * 7919 + 3, lay, d, targets, cfg)
			t.eq(coins, RulesLogic.pick_coins(s * 7919 + 3, lay, d, targets, cfg), "same seed, same coins")
			t.eq(coins.size(), cfg.coin_spawns_per_round, "%d coins a round" % cfg.coin_spawns_per_round)
			var ids := {}
			var min_gap := INF
			for c in coins:
				var p := Vector2(float(c["x"]), float(c["z"]))
				ids[c["id"]] = true
				used[c["id"]] = int(used.get(c["id"], 0)) + 1
				for dr in doors:
					t.check(p.distance_to(dr["pos"]) >= cfg.coin_door_clearance_m, "clear of tonight's doors")
				for wi in targets:
					var w: Dictionary = lay.waters[int(wi)]
					for e in w["exits"]:
						t.check(p.distance_to(Vector2((e as Vector3).x, (e as Vector3).z)) >= cfg.coin_water_clearance_m, "clear of an active water's exits")
					for j in w["jump_points"]:
						t.check(p.distance_to(j) >= cfg.coin_water_clearance_m, "clear of an active water's jump-in points")
				for o in coins:
					if o != c:
						min_gap = minf(min_gap, p.distance_to(Vector2(float(o["x"]), float(o["z"]))))
			t.eq(ids.size(), coins.size(), "round-scoped ids are unique")
			t.check(min_gap >= cfg.coin_min_spacing_m * 0.6, "coins are spread out (closest %.0f m)" % min_gap)
	t.check(used.size() >= lay.coin_spots.size() - 4, "the coins move around between rounds (%d of %d spots used)" % [used.size(), lay.coin_spots.size()])


func _coin_at(x: float, z: float, id: String = "s00") -> Dictionary:
	return {"id": id, "x": x, "z": z}


func test_first_valid_collector_and_no_double_credit() -> void:
	var h := _h()
	var a := Vector2(-20, 60)
	var b := Vector2(-20, 70)
	h.make([R, P, R], [0, 1, 2], [], 7, {"coins": [_coin_at(a.x, a.y, "s01"), _coin_at(b.x, b.y, "s02")]})
	await h.release_patrol()
	var got: Array = []
	h.sim.event_emitted.connect(func(ev: Dictionary) -> void:
		if int(ev["type"]) == TC.Ev.COIN_PICKUP:
			got.append([int(ev["a"]), int(ev["v"])]))
	# the same tick, the same distance: the lower slot gets it
	h.place(0, Vector3(a.x - 0.5, 0.05, a.y))
	h.place(1, Vector3(a.x + 0.5, 0.05, a.y))
	await h.step()
	t.eq(got, [[0, 0]], "a tie goes to the lower slot, once")
	# the Night Watch nearer the second coin than a runner: the watcher
	h.place(2, Vector3(b.x - 0.9, 0.05, b.y))
	h.place(1, Vector3(b.x + 0.3, 0.05, b.y))
	await h.step()
	t.eq(got, [[0, 0], [1, 1]], "the nearer player (here the Night Watch) gets it")
	# standing on a taken coin, walking off and back: nothing more
	for k in 3:
		h.place(0, Vector3(a.x, 0.05, a.y))
		await h.step(2)
		h.place(0, Vector3(a.x + 5.0, 0.05, a.y))
		await h.step(2)
	t.eq(got.size(), 2, "a taken coin never pays again")
	t.eq(h.sim.player(0).coins_picked, 1, "runner: exactly one")
	t.eq(h.sim.player(1).coins_picked, 1, "Night Watch: exactly one")
	t.eq(h.sim.player(2).coins_picked, 0, "the farther runner: none")
	t.eq(h.sim.coin_mask(), 0, "both coins are gone (snapshot mask)")
	var res := h.sim.build_results()
	var rows := {}
	for r in res["players"]:
		rows[int(r["slot"])] = r
	t.eq(int(rows[0]["coins_picked"]), 1, "results row: coins_picked (runner)")
	t.eq(int(rows[1]["coins_picked"]), 1, "results row: coins_picked (Night Watch)")
	t.eq(int(rows[2]["coins_picked"]), 0, "results row: coins_picked (none)")
	t.eq(res["coin_log"], [["s01", 0], ["s02", 1]], "the round's coin log names each coin's collector once")
	t.eq(int(res["coins_total"]), 2, "coins in the round")
	t.eq(String(res["home_dorm"]), h.sim.home_dorm, "results name the round's home dorm")
	h.free_sim()


func test_who_cannot_collect() -> void:
	var h := _h()
	var spots: Array = []
	for i in 6:
		spots.append(_coin_at(-30.0 + 5.0 * i, 45.0, "s%02d" % i))
	h.make([R, R, R, P, P], [0, 1, 2], [], 8, {"coins": spots})
	# before GO nothing is collected (the Night Watch waits in the shed)
	h.place(0, Vector3(-30, 0.05, 45))
	await h.step(3)
	t.eq(h.sim.player(0).coins_picked, 0, "nothing during the reveal / countdown")
	await h.release_patrol()
	t.eq(h.sim.player(0).coins_picked, 1, "collected once play starts")
	# caught
	var r1 := h.sim.player(1)
	r1.state = TC.PState.CAPTURED
	r1.penalty = 5.0
	h.place(1, Vector3(-25, 0.05, 45))
	await h.step(2)
	t.eq(r1.coins_picked, 0, "a caught runner can't collect")
	# home
	var r2 := h.sim.player(2)
	r2.state = TC.PState.FINISHED
	h.place(2, Vector3(-20, 0.05, 45))
	await h.step(2)
	t.eq(r2.coins_picked, 0, "a runner who is home can't collect")
	# in a cart
	var w := h.sim.player(3)
	w.state = TC.PState.IN_CART
	h.place(3, Vector3(-15, 0.05, 45))
	await h.step(2)
	t.eq(w.coins_picked, 0, "a Night Watch in a cart can't collect")
	t.eq(h.sim.coin_mask(), 0b111110, "those coins are still out")
	h.free_sim()


func test_bots_collect_but_results_mark_them() -> void:
	var h := _h()
	# a runner bot heading out with a coin just off its way
	h.make([R, P], [0, 1, 2], [0], 9, {"coins": [_coin_at(0, 72, "s00")]})
	await h.to_playing()
	h.place(0, Vector3(3.0, 0.05, 76))
	var k := 0
	while h.sim.player(0).coins_picked == 0 and k < 600:
		await h.step()
		k += 1
	t.eq(h.sim.player(0).coins_picked, 1, "a bot collects a coin beside its route (%.1f s)" % (float(k) / 60.0))
	var row: Dictionary = h.sim.build_results()["players"][0]
	t.check(bool(row["is_bot"]) and int(row["coins_picked"]) == 1, "the row says it was a bot (bots own no wallet)")
	h.free_sim()


func test_cancelled_round_still_reports() -> void:
	var h := _h()
	h.make([R, P], [0, 1, 2], [], 10, {"coins": [_coin_at(-20, 60, "s00")]})
	await h.release_patrol()
	h.place(0, Vector3(-20, 0.05, 60))
	await h.step()
	h.sim.cancel_match()
	var res: Dictionary = h.sim.results
	t.eq(int(res["outcome"]), TC.Outcome.CANCELLED, "cancelled")
	t.eq(int(res["players"][0]["coins_picked"]), 1, "the row still records the pickup (no settlement for a cancelled round: RULES.md)")
	t.eq(int(RulesLogic.compute_rewards(res, 0, Rules.cfg, false)["coins"]), 0, "and the round pays nothing")
	h.free_sim()


## The view: a coin hides once, from an event or the host's mask, and never
## comes back; one MultiMesh, one shared material for every coin.
func test_coin_view_dedups_and_shares_one_material() -> void:
	var v := CoinView.new()
	t.add_child(v)
	v.setup([_coin_at(0, 0, "s00"), _coin_at(5, 0, "s01"), _coin_at(10, 0, "s02")])
	t.eq(v.remaining(), 3, "three out")
	t.check(v.take(1), "an event hides coin 1")
	t.check(not v.take(1), "the same event again does nothing")
	v.set_mask(0b111)
	t.eq(v.remaining(), 2, "a stale mask can't bring a coin back")
	v.set_mask(0b001)
	t.eq(v.remaining(), 1, "the host's mask hides what was taken while we weren't listening")
	var v2 := CoinView.new()
	t.add_child(v2)
	v2.setup([_coin_at(0, 0)])
	t.check(v.mm.material_override == v2.mm.material_override, "every round's coins share one material")
	t.check(v.mm.multimesh.mesh == v2.mm.multimesh.mesh, "and one mesh")
	v.queue_free()
	v2.queue_free()
	await t.get_tree().process_frame


## Over the network: the guest learns of a pickup from the host's event once
## (a duplicated EVENTS packet is ignored), its own count from the private
## snapshot block, and the coins still out from every snapshot; a guest who
## reconnects gets the same round configuration and the same coins state.
func test_coins_over_the_network_replay_and_reconnect() -> void:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(40, 5, 0.0, 1, ["patrol", "runner"])
	var c0: NetSession = rig.clients[0]
	await rig.wait_until(func() -> bool: return c0.local_slot >= 0, 300)
	c0.set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.can_start(), 300)
	rig.host.host_start_match(31)
	await rig.wait_until(func() -> bool: return rig.mcs.size() == 2, 300)
	var hmc := rig.host_mc()
	await rig.wait_until(func() -> bool: return hmc.sim.phase == TC.Phase.PLAYING, 900)
	var hs: Dictionary = rig.started[rig.host]
	var cs: Dictionary = rig.started[c0]
	t.eq(cs["coins"], hs["coins"], "the guest has the host's coins")
	t.eq(String(cs["home_dorm"]), String(hs["home_dorm"]), "and the same home dorm")
	var slot := c0.local_slot
	var coin: Dictionary = hmc.sim.coins[0]
	var sp := hmc.sim.player(slot)
	sp.body.global_position = (coin["pos"] as Vector3) + Vector3(0, 0.05, 0)
	await rig.frames(20)
	t.eq(sp.coins_picked, 1, "the host credits the guest's runner")
	var evs: Array = (rig.client_events[c0] as Array).filter(func(e: Dictionary) -> bool: return int(e["type"]) == TC.Ev.COIN_PICKUP)
	t.eq(evs.size(), 1, "the guest saw one pickup event")
	await rig.wait_until(func() -> bool: return int(rig.mc_of(c0)._me.get("coins_picked", 0)) == 1, 120)
	t.eq(int(rig.mc_of(c0)._me.get("coins_picked", 0)), 1, "its own count arrives in the private snapshot block")
	t.eq(int(rig.mc_of(c0)._last_snap.get("coins", -1)) & 1, 0, "snapshots say coin 0 is gone")
	# a replayed EVENTS packet with the same event: ignored
	var before: int = (rig.client_events[c0] as Array).size()
	var data := Protocol.encode_events(evs)
	c0._on_packet(c0.host_peer, data)
	t.eq((rig.client_events[c0] as Array).size(), before, "a replayed pickup event is ignored")
	t.eq(sp.coins_picked, 1, "and the host never pays twice")
	# reconnect: same configuration, same coins state, no second coin
	var key := c0.rejoin_key
	rig.client_ts[0].close()
	await rig.frames(30)
	var c1 := rig.add_client("uid-c0", "Client0", "runner")
	c1.rejoin_key = key
	await rig.wait_until(func() -> bool: return c1.local_slot == slot and rig.started.has(c1), 300)
	var rs: Dictionary = rig.started.get(c1, {})
	t.eq(rs.get("coins", []), hs["coins"], "a reconnecting guest gets the round's coins unchanged")
	t.eq(String(rs.get("home_dorm", "")), String(hs["home_dorm"]), "and the round's home dorm")
	t.eq((rs.get("dorm", {}) as Dictionary).get("spawns", {}), (hs["dorm"] as Dictionary)["spawns"], "and the spawn mapping")
	await rig.wait_until(func() -> bool: return rig.mc_of(c1) != null and rig.mc_of(c1).stat_snapshots > 0, 300)
	t.eq(int(rig.mc_of(c1)._last_snap.get("coins", -1)) & 1, 0, "the taken coin stays gone after reconnecting")
	t.eq(sp.coins_picked, 1, "no extra credit from reconnecting")
	rig.teardown()
