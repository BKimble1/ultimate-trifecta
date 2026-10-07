extends RefCounted
## The reference campus's ground and its stairs (NP.3): the terrain bake is
## loaded and real-scale, Moonbrook College stays flat; stairs are walked
## up, down and jumped from with the unchanged motor, their collision ramp
## follows their nosings, carts stay off them, the ground tiles meet at
## their seams, and a raised hall's threshold is crossed at its own floor.
var t
const R := TC.Role.RUNNER
const P := TC.Role.PATROL


func _stair(building: String, kind: String = "") -> Dictionary:
	for st in CampusLayout.shared().stairs:
		if String(st["building"]) == building and (kind == "" or String(st["kind"]) == kind):
			return st
	return {}


func test_terrain_is_the_measured_ground() -> void:
	var L := CampusLayout.shared()
	t.check(not L.terrain.is_empty(), "the campus has its baked ground")
	var meta: Dictionary = L.terrain["meta"]
	t.eq(int(L.terrain["w"]), int(L.bounds.size.x) + 1, "one sample a metre across the bounds (x)")
	t.eq(int(L.terrain["d"]), int(L.bounds.size.y) + 1, "and (z)")
	var rg: Array = meta["range_m"]
	t.check(float(rg[0]) > -25.0 and float(rg[1]) < 10.0, "real grades, not exaggerated (%.1f..%.1f m)" % [float(rg[0]), float(rg[1])])
	t.check(String(meta["source"]).contains("3DEP"), "from the public bare-earth DEM")
	var wh := L.building_by_id("west_hall")
	t.check(absf(float(wh["floor_y"])) < 0.3, "the default start hall stands at the origin (%.2f m)" % float(wh["floor_y"]))
	var nh := L.building_by_id("north_hall")
	t.check(float(nh["floor_y"]) > 4.0, "North Hall stands on its rise (%.2f m)" % float(nh["floor_y"]))
	# every water level is absolute and lies on (not above) its banks
	for w in L.waters:
		if String(w["kind"]) in ["pond", "lake"] and w.get("surface_y") != null:
			var c: Vector2 = w["center"]
			t.check(float(w["floor_y"]) < float(w["surface_y"]), "%s: its bed under its surface" % w["id"])
	var C := CampusMaps.layout(CampusMaps.CLASSIC)
	t.check(C.terrain.is_empty(), "Moonbrook College stays flat, as in 2.0")
	t.eq(C.terrain_y(Vector2(10, 10)), 0.0, "(its ground is y = 0)")


func test_stair_collision_follows_the_nosings() -> void:
	var L := CampusLayout.shared()
	t.check(L.stairs.size() >= 20, "entrances with a step have stairs (%d)" % L.stairs.size())
	t.check(not _stair("north_hall", "portico").is_empty(), "North Hall's front stair")
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2], [], 3)
	await h.step()
	var ss := h.sim.space_state()
	var worst := 0.0
	for st in L.stairs:
		var prof := CampusStairs.profile(st)
		var length := float(prof[-1][0])
		for f in [0.1, 0.3, 0.5, 0.7, 0.9]:
			var d := length * float(f)
			var want := CampusLayout.stair_surface(st, d)
			# (off the centre line: a stair may have a centre handrail)
			for side in [-0.3, -0.15, 0.15, 0.3]:
				var p := CampusStairs.at(st, d, want + 3.0, float(side) * float(st["w"]))
				var hit := ss.intersect_ray(PhysicsRayQueryParameters3D.create(p, p - Vector3(0, 6.0, 0), TC.L_WORLD))
				var y := float((hit["position"] as Vector3).y) if not hit.is_empty() else -99.0
				worst = maxf(worst, absf(y - want))
				t.check(absf(y - want) < 0.04, "%s stair: walking surface at %.1f m out (%.2f, want %.2f)" % [st["building"], d, y, want])
		# the surface never sits more than a riser over a tread (feet on the steps)
		var nos: Array = st["nosings"]
		for k in range(1, nos.size()):
			var mid := (float(nos[k - 1]) + float(nos[k])) * 0.5
			var tread := float(st["top"]) - float(st["rise"]) * float(k)
			t.check(CampusLayout.stair_surface(st, mid) - tread <= float(st["rise"]) + 0.001, "%s: within a riser of tread %d" % [st["building"], k])
		# a cart can't drive onto it
		var q := PhysicsShapeQueryParameters3D.new()
		var probe := SphereShape3D.new()
		probe.radius = 0.3
		q.shape = probe
		q.collision_mask = TC.L_CART_BLOCK
		q.transform = Transform3D(Basis.IDENTITY, CampusStairs.at(st, length * 0.5, CampusLayout.stair_surface(st, length * 0.5) + 0.6))
		t.check(not ss.intersect_shape(q, 1).is_empty(), "%s stair: closed to carts" % st["building"])
	print("[terrain] stairs: %d; the ramp is never more than %.3f m off the nosing line" % [L.stairs.size(), worst])
	h.free_sim()


func test_walk_up_down_and_jump_from_the_landing() -> void:
	var st := _stair("north_hall", "portico")
	if st.is_empty():
		t.check(false, "North Hall's front stair")
		return
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2], [], 7)
	await h.release_patrol()
	var r := h.sim.player(0)
	var prof := CampusStairs.profile(st)
	var length := float(prof[-1][0])
	var n: Vector2 = st["dir"]
	# a quarter of the width off the centre line (its centre handrail
	# divides the stair into two flights)
	var lane: Vector2 = (st["tg"] as Vector2) * (float(st["w"]) * 0.25)
	var foot: Vector2 = st["p"] + lane + n * (length + 2.5)
	# up: from the walk below to the portico
	h.place(0, h.on_ground(foot), atan2(n.x, n.y))
	h.cmd(0).move = -n
	var ticks := 0
	while ticks < 60 * 6 and (r.pos2() - (st["p"] as Vector2)).dot(n) > 0.2:
		await h.step()
		ticks += 1
	h.cmd(0).move = Vector2.ZERO
	await h.step(10)
	var up_s := float(ticks) / 60.0
	t.check((r.pos2() - (st["p"] as Vector2)).dot(n) <= 0.2, "up the stair to the portico (%.2f s for %.1f m)" % [up_s, length + 2.5])
	t.check(absf(r.pos().y - float(st["top"])) < 0.12, "standing on the portico floor (%.2f, floor %.2f)" % [r.pos().y, float(st["top"])])
	# the climb costs about what the same run on level ground does: the ramp
	# adds no time and no shortcut
	t.check(up_s < (length + 2.5) / Rules.cfg.runner_speed * 1.5 + 0.5, "at running pace (%.2f s)" % up_s)
	# down again, past the foot
	h.cmd(0).move = n
	ticks = 0
	while ticks < 60 * 6 and (r.pos2() - (st["p"] as Vector2)).dot(n) < length + 2.0:
		await h.step()
		ticks += 1
	h.cmd(0).move = Vector2.ZERO
	await h.step(20)
	var gy := h.gy(r.pos2())
	t.check((r.pos2() - (st["p"] as Vector2)).dot(n) >= length + 2.0, "down the stair (%.2f s)" % (float(ticks) / 60.0))
	t.check(absf(r.pos().y - gy) < 0.15, "back on the walk (%.2f, ground %.2f)" % [r.pos().y, gy])
	# a jump from the landing comes down on the stair, not through it
	var ld: Array = []
	for l in st["landings"]:
		if float(l[0]) > 0.01:
			ld = l
	t.check(not ld.is_empty(), "the stair has an intermediate landing")
	if not ld.is_empty():
		var mid := (float(ld[0]) + float(ld[1])) * 0.5
		var lp := CampusStairs.at(st, mid, float(ld[2]) + 0.05, float(st["w"]) * 0.25)
		h.place(0, lp, atan2(n.x, n.y))
		await h.step(5)
		h.cmd(0).move = n
		h.press(0, TC.BTN_JUMP)
		var peak := -INF
		for i in 90:
			await h.step()
			peak = maxf(peak, r.pos().y)
		h.cmd(0).move = Vector2.ZERO
		await h.step(30)
		var d := (r.pos2() - (st["p"] as Vector2)).dot(n)
		var surf := CampusLayout.stair_surface(st, d) if d <= length + float(st["going"]) else h.gy(r.pos2())
		t.check(peak > float(ld[2]) + 0.5, "a real jump off the landing (peak %.2f)" % peak)
		t.check(r.pos().y >= surf - 0.1, "landed on the stair or the walk, not inside it (%.2f vs %.2f)" % [r.pos().y, surf])
		t.check(r.body.is_on_floor(), "and standing")
	h.free_sim()


## Every stair is climbed from the walk at its foot up to its top edge at
## running pace: the walk meets it flush (no lip a runner stops at) and
## nothing stands on it.
func test_every_stair_is_climbed_from_its_walk() -> void:
	var L := CampusLayout.shared()
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2], [], 5)
	await h.release_patrol()
	var r := h.sim.player(0)
	var n := 0
	for st in L.stairs:
		var dir: Vector2 = st["dir"]
		var length := float(st["length"]) + float(st["going"])
		# a quarter of the width off the centre line (a centre handrail)
		var lane: Vector2 = (st["tg"] as Vector2) * (float(st["w"]) * 0.25)
		var a: Vector2 = (st["p"] as Vector2) + lane + dir * (length + 2.5)
		var b: Vector2 = (st["p"] as Vector2) + lane + dir * 0.3
		r.state = TC.PState.ACTIVE
		Motor.set_body_enabled(r.body, true)
		h.place(0, h.on_ground(a), atan2(dir.x, dir.y))
		var ok := false
		var ticks := 0
		var budget := int(((length + 2.2) / Rules.cfg.runner_speed * 1.6 + 0.6) * 60.0)
		while ticks < budget:
			h.cmd(0).move = (b - r.pos2()).normalized()
			await h.step()
			ticks += 1
			if r.pos2().distance_to(b) < 0.5:
				ok = true
				break
		h.cmd(0).move = Vector2.ZERO
		# up at its top edge (on the stair, not under it)
		var want := CampusLayout.stair_surface(st, 0.3)
		t.check(ok and r.pos().y > want - 0.4, "%s stair %d (%d risers): climbed from its walk (%.2f s, at %.2f, surface %.2f)" % [
			st["building"], n, int(st["risers"]), float(ticks) / 60.0, r.pos().y, want])
		n += 1
	t.check(n >= 20, "stairs climbed (%d)" % n)
	h.free_sim()


func test_ground_tiles_meet_at_their_seams() -> void:
	var L := CampusLayout.shared()
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2], [], 9)
	await h.step()
	var ss := h.sim.space_state()
	var g := CampusBuilder.tile_grid(L)
	var tile := float(g.y)
	var worst := 0.0
	var n := 0
	for i in range(1, g.x):
		var sx := L.bounds.position.x + tile * float(i)
		var z := L.bounds.position.y + 7.3
		while z < L.bounds.end.y - 7.0:
			var ys: Array = []
			for dx in [-0.02, 0.02]:
				var p := Vector3(sx + float(dx), 40.0, z)
				var hit := ss.intersect_ray(PhysicsRayQueryParameters3D.create(p, p - Vector3(0, 80.0, 0), TC.L_WORLD))
				ys.append(float((hit["position"] as Vector3).y) if not hit.is_empty() else -99.0)
			# (a building or a stair over the seam is not the ground)
			if L.building_at(Vector2(sx, z), 1.0) < 0:
				worst = maxf(worst, absf(float(ys[0]) - float(ys[1])))
				n += 1
			z += 13.0
	t.check(n > 100, "seam samples (%d)" % n)
	t.check(worst < 0.05, "the tiles share their edge samples (worst step %.3f m)" % worst)
	h.free_sim()


func test_raised_threshold_counts_at_its_own_floor() -> void:
	var g := CampusDorms.geometry("north_hall")
	var dr: Dictionary = g["doors"][0]
	var fl := float(dr["floor_y"])
	t.check(fl > 4.0, "North Hall's doors are at its raised floor (%.2f)" % fl)
	var lp: Vector2 = dr["line_p"]
	var n: Vector2 = dr["n_in"]
	var v := func(p: Vector2, y: float) -> Vector3: return Vector3(p.x, y, p.y)
	t.check(CampusDorms.crosses(dr, v.call(lp - n * 0.2, fl + 0.05), v.call(lp + n * 0.2, fl + 0.05)), "in across the threshold at the floor: yes")
	t.check(not CampusDorms.crosses(dr, v.call(lp - n * 0.2, fl - 1.2), v.call(lp + n * 0.2, fl - 1.2)), "below the raised floor (under the porch): no")
	t.check(not CampusDorms.crosses(dr, v.call(lp - n * 0.2, 0.05), v.call(lp + n * 0.2, 0.05)), "at the old flat level: no")
	t.check(not CampusDorms.in_room("north_hall", v.call(CampusData.centroid(g["room"]), fl - 2.0)), "under the room is not in it")
	t.check(CampusDorms.in_room("north_hall", v.call(CampusData.centroid(g["room"]), fl + 0.05)), "on its floor is")
