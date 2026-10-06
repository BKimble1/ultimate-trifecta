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
	var lay := CampusLayout.shared()
	for wi in lay.pool_size():
		# the objective pool (decorative waters are never round targets)
		var w: Dictionary = lay.waters[wi]
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


## V6: every dorm's doors are on different faces and far apart, so one
## watcher can't cover two, and carts are held well short of every door:
## driven flat out at each dorm from each side, a cart never gets within
## reach of a doorway (bollards around the yards, blockers across doors).
func test_dorm_doors_spread_and_cart_free() -> void:
	var lay := CampusLayout.shared()
	var cover := Rules.cfg.tag_reach_m + Rules.cfg.tag_lunge_speed * Rules.cfg.tag_lunge_s
	for dm in lay.dorms:
		var doors: Array = dm["geo"]["doors"]
		t.check(doors.size() >= 3, "%s: three entrances" % dm["id"])
		var min_gap := 1e9
		for a in doors:
			for b in doors:
				if a != b:
					min_gap = minf(min_gap, (a["approach"] as Vector2).distance_to(b["approach"]))
		t.check(min_gap >= cover * 2.0 + 4.0, "%s: no spot covers two doors within two lunges (closest approaches %.1f m)" % [dm["id"], min_gap])
	for dm in lay.dorms:
		# straight at each door from 40 m out (over lawns and walks: the real
		# halls have no yards), and straight at the hall from four sides
		var c0 := CampusData.centroid(dm["geo"]["footprint"])
		var approaches: Array = []
		for d0 in doors_of(dm):
			var nn: Vector2 = d0["normal"]
			var s0: Vector2 = (d0["pos"] as Vector2) + nn * 40.0
			approaches.append([Vector3(s0.x, 0.3, s0.y), Vector3(-nn.x, 0, -nn.y)])
		for dv in [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]:
			var s1: Vector2 = c0 + dv * 90.0
			approaches.append([Vector3(s1.x, 0.3, s1.y), Vector3(-dv.x, 0, -dv.y)])
		for ap in approaches:
			var h := _h()
			h.make([R, P], [0, 1, 2], [], 11, {"dorm": String(dm["id"])})
			await h.release_patrol()
			var c: SimCart = h.sim.carts[0]
			var dir: Vector3 = ap[1]
			c.yaw = atan2(-dir.x, -dir.z)
			var start: Vector3 = ap[0]
			# start on drivable ground (roads and lawns outside the yards)
			var cell := NavGrid.shared(lay).nearest_open(NavGrid.shared(lay).cart, Vector2(start.x, start.z), 12)
			var sw := NavGrid.shared(lay).to_world(cell)
			c.body.global_position = Vector3(sw.x, 0.3, sw.y)
			c.speed = 0.0
			h.place(1, c.pos() - c.right() * 1.5)
			await h.step()
			h.press(1, TC.BTN_INTERACT)
			await h.step(30)
			t.eq(h.sim.player(1).state, TC.PState.IN_CART, "driver seated")
			h.cmd(1).drive = 1.0
			var closest := 1e9
			for i in 360:
				await h.step()
				var p2 := Vector2(c.pos().x, c.pos().z)
				for d in doors_of(dm):
					closest = minf(closest, p2.distance_to(d["pos"]))
			t.check(closest >= 6.0, "%s: cart from %s held %.1f m from the nearest door" % [dm["id"], str(dir), closest])
			h.free_sim()


func doors_of(dm: Dictionary) -> Array:
	return dm["geo"]["doors"]
