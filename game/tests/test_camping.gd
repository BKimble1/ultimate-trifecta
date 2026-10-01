extends RefCounted
## Anti-camping checks: geometry, not arbitrary timers, keeps targets and the
## dorm contestable. Two Night Watch players parked at a water cannot cover all
## of its exits or its respawn pads, and carts cannot be parked on the doors.
var t
const R := TC.Role.RUNNER
const P := TC.Role.PATROL


func _h() -> SimHarness:
	return SimHarness.new(t)


## Every point a camper could stand on at a water: its shore exits and its pads.
func _guard_spots(w: Dictionary) -> Array:
	var out: Array = []
	for e in w["exits"]:
		out.append(Vector2((e as Vector3).x, (e as Vector3).z))
	for p in w["pads"]:
		out.append(p)
	return out


func test_water_exits_and_pads_beat_two_campers() -> void:
	var cover := Rules.cfg.tag_reach_m + Rules.cfg.tag_lunge_speed * Rules.cfg.tag_lunge_s
	for w in CampusLayout.shared().waters:
		var exits: Array = w["exits"]
		var name: String = w["short"]
		t.check(exits.size() >= 2, "%s: at least two shore exits (%d)" % [name, exits.size()])
		t.check((w["jump_points"] as Array).size() >= 2, "%s: at least two jump-in approaches" % name)
		# a guard standing anywhere cannot reach every exit with one lunge
		var spots := _guard_spots(w)
		var held_all := false
		for g in spots:
			var covers := 0
			for e in exits:
				if (g as Vector2).distance_to(Vector2((e as Vector3).x, (e as Vector3).z)) <= cover * 2.0:
					covers += 1
			if covers == exits.size():
				held_all = true
		t.check(not held_all, "%s: no single spot covers every exit within two lunges" % name)
		# two campers anywhere on the shore: the chosen respawn pad is far from both
		var worst := 1e9
		for g1 in spots:
			for g2 in spots:
				var pad := RulesLogic.choose_pad(w["pads"], [g1, g2])
				worst = minf(worst, minf(pad.distance_to(g1), pad.distance_to(g2)))
		t.check(worst >= 15.0, "%s: respawn pad stays >= 15 m from two campers (worst %.1f m)" % [name, worst])


func test_respawn_away_from_campers_in_play() -> void:
	# Runner stamped the Fountain, gets tagged, and both Night Watch then camp
	# the Fountain's two nearest exits while the penalty runs.
	var h := _h()
	h.make([R, P, P], [0, 1, 2])
	await h.release_patrol()
	await h.splash_into(0, 0)
	h.place(0, Vector3(-20, 0.05, 60), 0.0)
	h.place(1, Vector3(-20, 0.05, 61.2), 0.0)
	await h.step()
	h.press(1, TC.BTN_TAG)
	var ev := await h.wait_event(TC.Ev.CAPTURE, 60)
	t.check(not ev.is_empty(), "runner captured")
	var exits: Array = h.sim.layout.waters[0]["exits"]
	h.place(1, (exits[0] as Vector3) + Vector3(0, 0.05, 0))
	h.place(2, (exits[1] as Vector3) + Vector3(0, 0.05, 0))
	while h.sim.player(0).state == TC.PState.CAPTURED:
		await h.step()
	var r := h.sim.player(0)
	var d1 := r.pos2().distance_to(h.sim.player(1).pos2())
	var d2 := r.pos2().distance_to(h.sim.player(2).pos2())
	t.check(minf(d1, d2) >= 12.0, "respawned away from both campers (%.1f m / %.1f m)" % [d1, d2])
	t.check(not r.is_taggable(), "and protected on arrival")
	h.free_sim()


func test_dorm_doors_spread_and_cart_free() -> void:
	var lay := CampusLayout.shared()
	t.check(lay.dorm_doors.size() >= 4, "four dorm entrances")
	var min_gap := 1e9
	for a in lay.dorm_doors:
		for b in lay.dorm_doors:
			if a != b:
				min_gap = minf(min_gap, (a["pos"] as Vector2).distance_to(b["pos"]))
	t.check(min_gap >= 15.0, "doors are far apart (closest pair %.1f m)" % min_gap)
	# Drive a cart flat out at the dorm from each side: bollards stop it well
	# short of every door, so a parked cart can never sit on a finish line.
	var approaches := [
		[Vector3(0, 0.3, 78), 0.0, Vector3(0, 0, 1)],        # from the north road, heading +Z
		[Vector3(-86, 0.3, 112), 0.0, Vector3(1, 0, 0)],     # from the west, heading +X
		[Vector3(86, 0.3, 112), 0.0, Vector3(-1, 0, 0)],     # from the east, heading -X
		[Vector3(0, 0.3, 146), 0.0, Vector3(0, 0, -1)],      # from the south, heading -Z
	]
	for ap in approaches:
		var h := _h()
		h.make([R, P], [0, 1, 2])
		await h.release_patrol()
		var c: SimCart = h.sim.carts[0]
		var dir: Vector3 = ap[2]
		c.yaw = atan2(-dir.x, -dir.z)
		c.body.global_position = ap[0]
		c.speed = 0.0
		h.place(1, c.pos() - c.right() * 1.5)
		await h.step()
		h.press(1, TC.BTN_INTERACT)
		await h.step(30)
		t.eq(h.sim.player(1).state, TC.PState.IN_CART, "driver seated")
		h.cmd(1).drive = 1.0
		var closest := 1e9
		var entered := false
		for i in 360:
			await h.step()
			var p2 := Vector2(c.pos().x, c.pos().z)
			for d in lay.dorm_doors:
				closest = minf(closest, p2.distance_to(d["pos"]))
			if lay.in_finish_zone(p2) != "":
				entered = true
		t.check(not entered, "cart from %s never reaches a finish zone" % str(dir))
		t.check(closest >= 8.0, "cart from %s held %.1f m from the nearest door" % [str(dir), closest])
		h.free_sim()
