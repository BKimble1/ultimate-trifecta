extends RefCounted
## Traversal of the rebuilt campus (acceptance gate 3), with the real
## simulation and movement (MatchSim + Motor, unchanged rules):
##  * every genuinely open passage can be run through (a breezeway, the
##    chapel's atrium, the bell tower's gap) or into (an open porch);
##  * where the runners' nav grid says "open", the runner's capsule fits
##    (no invisible walls the bots would walk into), sampled across campus;
##  * the traced walks are clear of colliders along their centre lines;
##  * the play area is closed: running at its edge never leaves it.
var t

const R := TC.Role.RUNNER
const P := TC.Role.PATROL


func _h() -> SimHarness:
	return SimHarness.new(t)


## Drives runner 0 from a to b (steering at b) for at most max_s seconds;
## returns [reached, seconds, lowest y].
func _run(h: SimHarness, a: Vector2, b: Vector2, max_s: float) -> Array:
	var r := h.sim.player(0)
	r.state = TC.PState.ACTIVE
	Motor.set_body_enabled(r.body, true)
	var dir := (b - a).normalized()
	h.place(0, Vector3(a.x, CampusBuilder.grid_y(h.sim.layout, a.x, a.y) + 0.05, a.y), atan2(-dir.x, -dir.y))
	var ticks := 0
	var low := INF
	while ticks < int(max_s * 60.0):
		h.cmd(0).move = (b - r.pos2()).normalized()
		await h.step()
		ticks += 1
		low = minf(low, r.pos().y)
		if r.pos2().distance_to(b) < 0.9:
			h.cmd(0).move = Vector2.ZERO
			return [true, float(ticks) / 60.0, low]
	h.cmd(0).move = Vector2.ZERO
	return [false, float(ticks) / 60.0, low]


## The open mouths of a passage: midpoints of its edges on the building's
## outline, with the outward direction.
func _mouths(bd: Dictionary, poly: PackedVector2Array) -> Array:
	var out: Array = []
	var foot: PackedVector2Array = bd["poly"]
	var pp := CampusData.ccw(poly)
	for i in pp.size():
		var a := pp[i]
		var b := pp[(i + 1) % pp.size()]
		var m := (a + b) * 0.5
		if a.distance_to(b) > 1.5 and (CampusData.dist_to_edge(m, foot) < 0.4 or not Geometry2D.is_point_in_polygon(m, foot)):
			var d := (b - a).normalized()
			out.append([m, Vector2(d.y, -d.x)])
	return out


func test_open_passages_are_walkable() -> void:
	var h := _h()
	h.make([R, P], [0, 1, 2], [], 41)
	await h.release_patrol()
	var lay := h.sim.layout
	var n := 0
	for bd in lay.buildings:
		if bool(bd["background"]):
			continue
		var lm := String(bd["landmark"]) if bd.get("landmark") != null else ""
		if lm == "bell_tower":
			var f := CampusTower.frame(bd)
			var c: Vector2 = f["c"]
			var back: Vector2 = f["back"]
			var reach := float(f["len"]) * 0.5 + 3.5
			var res: Array = await _run(h, c - back * reach, c + back * reach, (reach * 2.0) / 6.0 * 2.0 + 1.5)
			t.check(bool(res[0]), "%s: through the gap between the piers (%.2f s)" % [bd["id"], float(res[1])])
			n += 1
			continue
		for ps in bd["passages"]:
			var poly: PackedVector2Array = ps["poly"]
			var ms := _mouths(bd, poly)
			if ms.is_empty():
				continue
			if float(ps["clear"]) < 2.2:
				continue    # too low to run under: not a walk-through
			var best := [ms[0], ms[0]]
			var bdist := -1.0
			for i in ms.size():
				for j in range(i + 1, ms.size()):
					var dd := (ms[i][0] as Vector2).distance_to(ms[j][0])
					if dd > bdist:
						bdist = dd
						best = [ms[i], ms[j]]
			var a: Vector2 = (best[0][0] as Vector2) + (best[0][1] as Vector2) * 3.0
			if bdist > 0.0:
				# a breezeway: in at one mouth, out at the other
				var b: Vector2 = (best[1][0] as Vector2) + (best[1][1] as Vector2) * 3.0
				var res2: Array = await _run(h, a, b, a.distance_to(b) / 6.0 * 2.0 + 1.5)
				t.check(bool(res2[0]), "%s: through its open passage (%.1f m, %.2f s)" % [bd["id"], a.distance_to(b), float(res2[1])])
			else:
				# a porch: in from the mouth to near its back
				var inner := CampusData.centroid(poly)
				var res3: Array = await _run(h, a, inner, a.distance_to(inner) / 6.0 * 2.0 + 1.5)
				t.check(bool(res3[0]), "%s: into its open porch (%.2f s)" % [bd["id"], float(res3[1])])
			n += 1
	t.check(n >= 1, "open passages found (%d)" % n)
	print("[traversal] %d passages run through" % n)
	h.free_sim()


func _capsule_query(h: SimHarness, p: Vector2) -> bool:
	var cap := CapsuleShape3D.new()
	cap.radius = Motor.CHAR_RADIUS - 0.03
	cap.height = Motor.CHAR_HEIGHT - 0.06
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.collision_mask = TC.L_WORLD
	var y := CampusBuilder.grid_y(h.sim.layout, p.x, p.y)
	q.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, y + Motor.CHAR_HEIGHT * 0.5 + 0.12, p.y))
	for hit in h.sim.space_state().intersect_shape(q, 4):
		var co: Object = hit.get("collider")
		var shp: Variant = (co as CollisionObject3D).shape_owner_get_owner((co as CollisionObject3D).shape_find_owner(int(hit.get("shape", 0)))) if co is CollisionObject3D else null
		if shp is CollisionShape3D and (shp as CollisionShape3D).shape is HeightMapShape3D:
			continue
		return true
	return false


## Where the bots' grid is open, the runner fits: sampled every 6 m over
## the play area, the capsule (a touch slimmer than the real one) is free.
func test_open_nav_cells_fit_a_runner() -> void:
	var h := _h()
	h.make([R, P], [0, 1, 2], [], 43)
	await h.step()
	var lay := h.sim.layout
	var nav := NavGrid.shared(lay)
	var checked := 0
	var blocked: Array = []
	for cy in range(0, nav.dims.y, 3):
		for cx in range(0, nav.dims.x, 3):
			var c := Vector2i(cx, cy)
			if nav.foot.is_point_solid(c) or nav.foot.get_point_weight_scale(c) > 1.5:
				continue
			var p := nav.to_world(c)
			if not lay.in_play(p):
				continue
			checked += 1
			if _capsule_query(h, p):
				blocked.append(p)
	var frac := float(blocked.size()) / maxf(1.0, float(checked))
	print("[traversal] open nav cells checked %d, capsule blocked at %d (%.2f%%): %s" % [checked, blocked.size(), frac * 100.0, str(blocked.slice(0, 12))])
	t.check(checked > 1000, "enough open cells sampled (%d)" % checked)
	t.check(frac < 0.005, "the runner fits where the nav grid is open (%d of %d blocked)" % [blocked.size(), checked])
	h.free_sim()


## The traced walks are clear along their centre lines (a capsule every
## 3 m), apart from where they meet a building at a door.
func test_walks_are_clear() -> void:
	var h := _h()
	h.make([R, P], [0, 1, 2], [], 45)
	await h.step()
	var lay := h.sim.layout
	var checked := 0
	var blocked: Array = []
	for pth in lay.paths:
		var pts: PackedVector2Array = pth["pts"]
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var steps := maxi(1, int(a.distance_to(b) / 3.0))
			for s in steps + 1:
				var p := a.lerp(b, float(s) / float(steps))
				if not lay.in_play(p) or lay.building_at(p, 1.2) >= 0:
					continue
				checked += 1
				if _capsule_query(h, p):
					blocked.append([pth["id"], p])
	print("[traversal] walk samples %d, blocked %d: %s" % [checked, blocked.size(), str(blocked.slice(0, 16))])
	t.check(checked > 200, "walk samples (%d)" % checked)
	t.check(float(blocked.size()) / maxf(1.0, float(checked)) < 0.01, "walks are clear (%d of %d samples blocked)" % [blocked.size(), checked])
	h.free_sim()


## Running straight at the edge of the play area never leaves it.
func test_play_area_is_closed() -> void:
	var h := _h()
	h.make([R, P], [0, 1, 2], [], 47)
	await h.release_patrol()
	var lay := h.sim.layout
	var bnd := CampusData.ccw(lay.play_boundary)
	var c := CampusData.centroid(bnd)
	var tried := 0
	var n := bnd.size()
	for i in range(0, n, maxi(1, n / 12)):
		var e := (bnd[i] + bnd[(i + 1) % n]) * 0.5
		var out := (e - c).normalized()
		var start := e - out * 6.0
		if not lay.in_play(start) or lay.building_at(start, 1.0) >= 0 or lay.water_index_at(start, 1.0) >= 0:
			continue
		tried += 1
		await _run(h, start, e + out * 30.0, 4.0)
		var r := h.sim.player(0)
		t.check(Geometry2D.is_point_in_polygon(r.pos2(), bnd) or CampusData.dist_to_edge(r.pos2(), bnd) < 1.0, "edge %d: the runner stays inside the play area" % i)
	t.check(tried >= 4, "edge points tried (%d)" % tried)
	h.free_sim()
