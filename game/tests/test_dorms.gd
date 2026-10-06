extends RefCounted
## V6 dorms: three playable dorms with real common rooms, a home dorm per
## round, spawning inside it, and the outside->inside threshold finish.
##  * geometry: doors, openings, pads (inside, apart, facing an exit, clear
##    line to it), respawn pads, ceilings, cart blockers;
##  * navigation: every pad reaches every door, every door's outside reaches
##    the inside, carts can't get in;
##  * the finish contract, door by door and dorm by dorm: start inside, walk
##    out, come back without all stamps, another dorm, standing against a
##    wall, wrong direction, height, a high-speed crossing, a crossing
##    through a wall (never), once only, finish before a same-tick tag;
##  * no tags during the reveal / countdown or inside the home dorm, the
##    pre-first-stamp respawn inside the home dorm, the doors don't snag,
##    bots leave and come back through the doors.
var t
const R := TC.Role.RUNNER
const P := TC.Role.PATROL


func _h() -> SimHarness:
	return SimHarness.new(t)


func test_three_dorms_with_real_doors_and_pads() -> void:
	var lay := CampusLayout.shared()
	t.check(lay.dorms.size() >= 3, "at least three playable dorms (%d)" % lay.dorms.size())
	var names := {}
	var walls := {}
	var hashes := {}
	for d in lay.dorms:
		var id := String(d["id"])
		var g: Dictionary = d["geo"]
		names[String(d["name"])] = true
		walls[str(d["wall"])] = true
		hashes[CampusDorms.geometry_hash(id)] = true
		var doors: Array = g["doors"]
		t.check(doors.size() >= 3, "%s: three entrances" % id)
		var faces := {}
		for dr in doors:
			faces[str(dr["normal"])] = true
		t.eq(faces.size(), doors.size(), "%s: each door on its own face" % id)
		var min_gap := INF
		for a in doors:
			for b in doors:
				if a != b:
					min_gap = minf(min_gap, (a["pos"] as Vector2).distance_to(b["pos"]))
		t.check(min_gap >= 12.0, "%s: doors far apart (closest %.1f m)" % [id, min_gap])
		t.check(CampusDorms.DOOR_W >= 3.0 and CampusDorms.DOOR_H >= 2.8, "openings wide and tall enough")
		var room: Rect2 = g["room"]
		t.check(room.size.x >= 20.0 and room.size.y >= 8.0, "%s: a real common room (%.0f x %.0f m)" % [id, room.size.x, room.size.y])
		var pads: Array = g["pads"]
		t.check(pads.size() >= 7, "%s: a pad for every runner (%d)" % [id, pads.size()])
		var furniture: Array = (g["boxes"] as Array).filter(func(bx: Array) -> bool: return String(bx[2]) in ["sofa", "hearth"])
		for i in pads.size():
			var pp: Vector2 = pads[i]["pos"]
			t.check(room.grow(-1.0).has_point(pp), "%s pad %d inside the room, clear of the walls" % [id, i])
			for j in range(i + 1, pads.size()):
				t.check(pp.distance_to(pads[j]["pos"]) >= 1.6, "%s pads %d/%d don't overlap" % [id, i, j])
			for dr in doors:
				t.check(pp.distance_to(dr["line_p"]) >= 2.4, "%s pad %d not in a doorway" % [id, i])
			for bx in furniture:
				var c: Vector3 = bx[0]
				var s: Vector3 = bx[1]
				t.check(not Rect2(c.x - s.x * 0.5, c.z - s.z * 0.5, s.x, s.z).grow(0.6).has_point(pp), "%s pad %d clear of furniture" % [id, i])
			# faces an exit: the pad's yaw points at one of the doors
			var yaw: float = pads[i]["yaw"]
			var face := Vector2(-sin(yaw), -cos(yaw))
			var best := -1.0
			for dr in doors:
				best = maxf(best, face.dot(((dr["line_p"] as Vector2) - pp).normalized()))
			t.check(best > 0.98, "%s pad %d faces an exit" % [id, i])
		for rp in g["respawn"]:
			t.check(room.grow(-0.8).has_point(rp), "%s: respawn pad inside the room" % id)
	t.eq(names.size(), lay.dorms.size(), "distinct dorm names")
	t.eq(walls.size(), lay.dorms.size(), "distinct facade colours")
	t.eq(hashes.size(), lay.dorms.size(), "distinct geometry fingerprints")
	t.eq(CampusDorms.geometry_hash("puddlesworth"), CampusDorms.geometry_hash("puddlesworth"), "fingerprint is stable")


## The colliders match the plan: doorways are clear to run through and
## lintelled above, walls beside them are solid, the room has a ceiling,
## carts are stopped at every door and the pads have a clear line to a door.
func test_collision_openings_ceiling_and_cart_blockers() -> void:
	var h := _h()
	h.make([R, P])
	await h.step()
	var ss := h.sim.space_state()
	var cap := CapsuleShape3D.new()
	cap.radius = Motor.CHAR_RADIUS
	cap.height = Motor.CHAR_HEIGHT
	for d in h.sim.layout.dorms:
		var id := String(d["id"])
		var g: Dictionary = d["geo"]
		for dr in g["doors"]:
			var mid: Vector2 = ((dr["pos"] as Vector2) + (dr["line_p"] as Vector2)) * 0.5
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = cap
			q.collision_mask = TC.L_WORLD
			q.transform = Transform3D(Basis.IDENTITY, Vector3(mid.x, 0.8, mid.y))
			t.check(ss.intersect_shape(q, 1).is_empty(), "%s %s: a runner fits in the doorway" % [id, dr["id"]])
			var tg: Vector2 = dr["tangent"]
			var beside: Vector2 = mid + tg * (CampusDorms.DOOR_W * 0.5 + 0.6)
			q.transform = Transform3D(Basis.IDENTITY, Vector3(beside.x, 0.8, beside.y))
			t.check(not ss.intersect_shape(q, 1).is_empty(), "%s %s: the wall beside it is solid" % [id, dr["id"]])
			var outside: Vector2 = dr["approach"]
			var inside: Vector2 = dr["inside"]
			var low := PhysicsRayQueryParameters3D.create(Vector3(outside.x, 1.0, outside.y), Vector3(inside.x, 1.0, inside.y), TC.L_WORLD)
			t.check(ss.intersect_ray(low).is_empty(), "%s %s: clear line through the opening" % [id, dr["id"]])
			var high := PhysicsRayQueryParameters3D.create(Vector3(outside.x, 3.6, outside.y), Vector3(inside.x, 3.6, inside.y), TC.L_WORLD)
			t.check(not ss.intersect_ray(high).is_empty(), "%s %s: lintel above the opening" % [id, dr["id"]])
			var cart := PhysicsRayQueryParameters3D.create(Vector3(outside.x, 0.6, outside.y), Vector3(inside.x, 0.6, inside.y), TC.L_CART_BLOCK)
			t.check(not ss.intersect_ray(cart).is_empty(), "%s %s: carts can't drive in" % [id, dr["id"]])
		var room: Rect2 = g["room"]
		var c := room.get_center()
		var up := ss.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(c.x, 1.0, c.y), Vector3(c.x, 20.0, c.y), TC.L_WORLD))
		t.check(not up.is_empty() and absf(float((up["position"] as Vector3).y) - CampusDorms.CEIL) < 0.05, "%s: ceiling at %.1f m" % [id, CampusDorms.CEIL])
		for pd in g["pads"]:
			var pp: Vector2 = pd["pos"]
			var dr2: Dictionary = g["doors"][int(pd["door"])]
			var lp: Vector2 = dr2["line_p"]
			var los := PhysicsRayQueryParameters3D.create(Vector3(pp.x, 1.2, pp.y), Vector3(lp.x, 1.2, lp.y), TC.L_WORLD)
			t.check(ss.intersect_ray(los).is_empty(), "%s: pad %s sees its exit" % [id, str(pp)])
	h.free_sim()


## Bots' grids: from every pad to every door's outside, and from outside
## every door to its inside; carts never reach a doorway.
func test_navigation_through_every_door() -> void:
	var lay := CampusLayout.shared()
	var nav := NavGrid.shared(lay)
	var shed: Vector2 = lay.cart_spawns[0]["pos"]
	for d in lay.dorms:
		var id := String(d["id"])
		var g: Dictionary = d["geo"]
		for dr in g["doors"]:
			var appr: Vector2 = dr["approach"]
			var ins: Vector2 = dr["inside"]
			t.check(nav.is_walkable(appr) and nav.is_walkable(ins), "%s %s: both sides walkable" % [id, dr["id"]])
			var through := nav.find_path(appr, ins)
			t.check(through.size() >= 2 and nav.path_length(through) < 8.0, "%s %s: straight through the door (%.1f m)" % [id, dr["id"], nav.path_length(through)])
			for pd in g["pads"]:
				var out := nav.find_path(pd["pos"], appr)
				t.check(out.size() >= 2 and nav.path_length(out) < (g["room"] as Rect2).size.x + 12.0, "%s: pad %s reaches the %s door" % [id, str(pd["pos"]), dr["id"]])
			t.check(not nav.is_drivable(ins), "%s %s: no cart inside" % [id, dr["id"]])
			t.check(nav.find_path(shed, ins, true).is_empty() or nav.find_path(shed, ins, true)[-1].distance_to(ins) > 3.0, "%s %s: carts can't path in" % [id, dr["id"]])
		for w in lay.waters:
			var pth := nav.find_path(g["pads"][0]["pos"], w["jump_points"][0])
			t.check(pth.size() >= 2, "%s: every water reachable on foot (%s)" % [id, w["id"]])


## Runners start inside on their own pads, facing an exit; the Night Watch
## starts outdoors at the shed; nobody can be tagged during the reveal or
## the countdown, even standing right next to a runner.
func test_spawn_inside_and_no_tags_before_go() -> void:
	for d in CampusDorms.ids():
		for watch in [1, 2, 3]:
			var roles: Array = []
			for i in 8:
				roles.append(P if i >= 8 - watch else R)
			var h := _h()
			h.make(roles, [0, 1, 2], [], 21, {"dorm": d})
			var g := CampusDorms.geometry(d)
			var room: Rect2 = g["room"]
			var seen := []
			for p in h.sim.players:
				if p.is_runner():
					t.check(CampusDorms.in_room(d, p.pos()), "%s/%dW: runner %d spawns inside" % [d, watch, p.id])
					for q in seen:
						t.check(p.pos2().distance_to(q) >= 1.6, "%s/%dW: runner %d has its own pad" % [d, watch, p.id])
					seen.append(p.pos2())
				else:
					for d2 in CampusDorms.ids():
						t.check(not CampusDorms.in_room(d2, p.pos()), "%s/%dW: Night Watch %d starts outdoors" % [d, watch, p.id])
			# a watcher next to runner 0 pressing Tag through reveal + countdown
			var r0 := h.sim.player(0)
			var w0 := h.sim.player(8 - watch)
			h.place(8 - watch, r0.pos() + Vector3(0, 0, 1.0), 0.0)
			w0.state = TC.PState.ACTIVE
			var tagged := false
			while h.sim.phase != TC.Phase.PLAYING:
				h.press(8 - watch, TC.BTN_TAG)
				await h.step()
				tagged = tagged or not h.events_of(TC.Ev.CAPTURE).is_empty() or w0.tag_phase != SimPlayer.TagPhase.NONE
			t.check(not tagged, "%s/%dW: no tag during the reveal or countdown" % [d, watch])
			t.check(room.has_point(r0.pos2()), "%s/%dW: runners wait inside until GO" % [d, watch])
			h.free_sim()


## The finish contract at every door of every dorm.
func test_threshold_finish_contract_every_door() -> void:
	for d in CampusDorms.ids():
		var h := _h()
		h.make([R, R, R, P], [0, 1, 2], [], 31, {"dorm": d})
		await h.release_patrol()
		h.place(3, Vector3(60, 0.05, -125))
		var doors: Array = h.sim.home_doors
		var r := h.sim.player(0)
		# starting inside with every stamp and standing still: nothing
		r.stamps = 7
		await h.step(30)
		t.eq(r.state, TC.PState.ACTIVE, "%s: standing inside is not a finish" % d)
		for i in doors.size():
			var dr: Dictionary = doors[i]
			var n_in: Vector2 = dr["n_in"]
			# walking OUT through the door with every stamp: nothing
			var ins: Vector2 = dr["inside"]
			h.place(0, Vector3(ins.x, 0.05, ins.y))
			h.cmd(0).move = -n_in
			await h.step(70)
			h.cmd(0).move = Vector2.ZERO
			t.eq(r.state, TC.PState.ACTIVE, "%s %s: running out is not a finish" % [d, dr["id"]])
			t.check(not CampusDorms.in_room(d, r.pos()), "%s %s: out through the door" % [d, dr["id"]])
			# standing against the wall beside the door, pushing in: nothing
			var beside: Vector2 = (dr["pos"] as Vector2) + (dr["normal"] as Vector2) * 0.5 + (dr["tangent"] as Vector2) * (CampusDorms.DOOR_W * 0.5 + 1.2)
			h.place(0, Vector3(beside.x, 0.05, beside.y))
			h.cmd(0).move = n_in
			await h.step(60)
			h.cmd(0).move = Vector2.ZERO
			t.eq(r.state, TC.PState.ACTIVE, "%s %s: pushing against the wall is not a finish" % [d, dr["id"]])
		# runner 1 without every stamp comes in: nothing (and is safe inside)
		var r1 := h.sim.player(1)
		r1.stamps = 3
		var in1 := await h.enter_door(1, 0, 60)
		t.check(not in1 and r1.state == TC.PState.ACTIVE, "%s: two stamps and back inside is not a finish" % d)
		t.check(r1.home_safe and not r1.is_taggable(), "%s: inside the home dorm nobody can be tagged" % d)
		# then with all three: in through each door in turn finishes once
		var fin := await h.enter_door(0, 2)
		t.check(fin, "%s: three stamps + running in through the %s door finishes" % [d, doors[2]["id"]])
		t.eq(r.finish_order, 1, "%s: finish order recorded" % d)
		t.eq(r.finish_door, String(doors[2]["id"]), "%s: which door" % d)
		t.eq(h.sim.finished_count, 1, "%s: one finish" % d)
		# finished once: walking back in again changes nothing
		var count := h.sim.finished_count
		await h.enter_door(0, 1)
		t.eq(h.sim.finished_count, count, "%s: a finish applies once" % d)
		h.free_sim()


## Another dorm is not home: running into it with every stamp does nothing.
func test_other_dorms_never_finish() -> void:
	for home in CampusDorms.ids():
		var h := _h()
		h.make([R, P], [0, 1, 2], [], 41, {"dorm": home})
		await h.release_patrol()
		var r := h.sim.player(0)
		r.stamps = 7
		for other in CampusDorms.ids():
			if other == home:
				continue
			for dr in CampusDorms.geometry(other)["doors"]:
				var n_in: Vector2 = dr["n_in"]
				var ap: Vector2 = (dr["pos"] as Vector2) + (dr["normal"] as Vector2) * 0.9
				h.place(0, Vector3(ap.x, 0.05, ap.y), atan2(-n_in.x, -n_in.y))
				h.cmd(0).move = n_in
				await h.step(50)
				h.cmd(0).move = Vector2.ZERO
				t.eq(r.state, TC.PState.ACTIVE, "home %s: %s's %s door is not a finish" % [home, other, dr["id"]])
				t.check(CampusDorms.in_room(other, r.pos()), "home %s: (it is enterable: %s)" % [home, other])
				t.check(r.is_taggable(), "home %s: no safety inside %s" % [home, other])
		h.free_sim()


## The swept threshold test itself: direction, width, height, step length.
func test_threshold_geometry() -> void:
	var dr: Dictionary = CampusDorms.geometry("puddlesworth")["doors"][0]
	var lp: Vector2 = dr["line_p"]
	var n: Vector2 = dr["n_in"]
	var tg: Vector2 = dr["tangent"]
	var v := func(p: Vector2, y: float = 0.05) -> Vector3: return Vector3(p.x, y, p.y)
	t.check(CampusDorms.crosses(dr, v.call(lp - n * 0.2), v.call(lp + n * 0.2)), "inward across the line: yes")
	t.check(not CampusDorms.crosses(dr, v.call(lp + n * 0.2), v.call(lp - n * 0.2)), "outward: no")
	t.check(not CampusDorms.crosses(dr, v.call(lp - n * 0.4), v.call(lp - n * 0.1)), "short of the line: no")
	t.check(not CampusDorms.crosses(dr, v.call(lp + n * 0.1), v.call(lp + n * 0.4)), "already inside: no")
	t.check(not CampusDorms.crosses(dr, v.call(lp - n * 0.2 + tg * 1.7), v.call(lp + n * 0.2 + tg * 1.7)), "beside the opening (through the wall line): no")
	t.check(CampusDorms.crosses(dr, v.call(lp - n * 0.2 + tg * 1.4), v.call(lp + n * 0.2 + tg * 1.4)), "near the jamb, inside the opening: yes")
	t.check(not CampusDorms.crosses(dr, v.call(lp - n * 0.2, 2.2), v.call(lp + n * 0.2, 2.2)), "too high (over the threshold): no")
	t.check(CampusDorms.crosses(dr, v.call(lp - n * 0.2, 1.2), v.call(lp + n * 0.2, 1.2)), "mid-jump through the opening: yes")
	t.check(CampusDorms.crosses(dr, v.call(lp - n * 1.2), v.call(lp + n * 1.4)), "a 2.6 m step (fast move between ticks): yes")
	t.check(not CampusDorms.crosses(dr, v.call(lp - n * 2.0), v.call(lp + n * 2.0)), "a 4 m jump in one tick is a teleport: no")
	t.check(CampusDorms.crosses(dr, v.call(lp - n * 0.3 - tg * 1.0), v.call(lp + n * 0.3 + tg * 1.0)), "diagonal through the opening: yes")


## A very fast crossing between two ticks still finishes, on that tick; a
## move that would carry a runner through the wall beside the door never
## does (the body is stopped, and the swept check refuses a blocked line).
func test_high_speed_crossing_and_never_through_a_wall() -> void:
	for d in CampusDorms.ids():
		var h := _h()
		h.make([R, R, P], [0, 1, 2], [], 51, {"dorm": d})
		await h.release_patrol()
		var dr: Dictionary = h.sim.home_doors[0]
		var lp: Vector2 = dr["line_p"]
		var n2: Vector2 = dr["n_in"]
		var n := Vector3(n2.x, 0, n2.y)
		var r := h.sim.player(0)
		r.stamps = 7
		h.place(0, Vector3(lp.x, 0.05, lp.y) - n * 0.45, atan2(-n.x, -n.z))
		await h.step()
		h.place(0, Vector3(lp.x, 0.05, lp.y) - n * 0.45, atan2(-n.x, -n.z))
		r.vel = n * 40.0   # 0.67 m in one tick
		r.body.velocity = r.vel
		r.diving = true    # a committed dive keeps its speed for the tick
		var t0 := h.sim.tick
		await h.step()
		t.eq(r.state, TC.PState.FINISHED, "%s: a 40 m/s crossing between ticks counts" % d)
		t.eq(r.finished_tick, t0 + 1, "%s: on that tick" % d)
		# through the wall beside the door: the body can't, and a forced
		# position change (tunnelling) is refused by the line check
		var r1 := h.sim.player(1)
		r1.stamps = 7
		var tg: Vector2 = dr["tangent"]
		var wall_out := Vector3(lp.x, 0.05, lp.y) - n * 1.0 + Vector3(tg.x, 0, tg.y) * 3.0
		h.place(1, wall_out, atan2(-n.x, -n.z))
		await h.step()
		h.place(1, wall_out, atan2(-n.x, -n.z))
		r1.vel = n * 40.0
		r1.body.velocity = r1.vel
		r1.diving = true
		await h.step(3)
		t.eq(r1.state, TC.PState.ACTIVE, "%s: a dive into the wall is not a finish" % d)
		t.check(not CampusDorms.in_room(d, r1.pos()), "%s: and does not go through" % d)
		t.check(h.sim.home_crossing(wall_out, Vector3(lp.x, 0.05, lp.y) + n * 0.6 + Vector3(tg.x, 0, tg.y) * 1.2).is_empty(),
			"%s: a crossing whose line is blocked by the wall never counts" % d)
		h.free_sim()


## Tags: a runner inside the home dorm is safe; the same runner just
## outside is fair game; finishing on the same tick beats a lunge.
func test_home_dorm_is_safe_and_finish_beats_tag() -> void:
	for d in CampusDorms.ids():
		var h := _h()
		h.make([R, P], [0, 1, 2], [], 61, {"dorm": d})
		await h.release_patrol()
		var dr: Dictionary = h.sim.home_doors[1]
		var ins: Vector2 = dr["inside"]
		var n2: Vector2 = dr["n_in"]
		var n := Vector3(n2.x, 0, n2.y)
		var face := atan2(-n.x, -n.z)
		# inside: a lunge from right behind never captures
		h.place(0, Vector3(ins.x, 0.05, ins.y), face)
		h.place(1, Vector3(ins.x, 0.05, ins.y) - n * 1.0, face)
		await h.step()
		h.press(1, TC.BTN_TAG)
		await h.step(30)
		t.eq(h.sim.player(0).state, TC.PState.ACTIVE, "%s: no tag inside the home dorm" % d)
		await h.step(60)
		# outside the door: captured
		var ap: Vector2 = dr["approach"]
		h.place(0, Vector3(ap.x, 0.05, ap.y) - n * 1.5, face)
		h.place(1, Vector3(ap.x, 0.05, ap.y) - n * 2.5, face)
		await h.step()
		h.press(1, TC.BTN_TAG)
		var ev := await h.wait_event(TC.Ev.CAPTURE, 40)
		t.check(not ev.is_empty(), "%s: tagged outside" % d)
		h.free_sim()


## Caught (or lost out of bounds) before the first splash: back inside
## tonight's home dorm, on the pad farthest from the Night Watch.
func test_pre_first_stamp_returns_inside_home_dorm() -> void:
	for d in CampusDorms.ids():
		var h := _h()
		h.make([R, P], [0, 1, 2], [], 71, {"dorm": d})
		await h.release_patrol()
		h.place(0, Vector3(-20, 0.05, 60), 0.0)
		h.place(1, Vector3(-20, 0.05, 61.2), 0.0)
		await h.step()
		h.press(1, TC.BTN_TAG)
		await h.wait_event(TC.Ev.CAPTURE, 60)
		# the watcher heads for the home dorm's front door meanwhile
		var front: Vector2 = h.sim.home_doors[0]["approach"]
		h.place(1, Vector3(front.x, 0.05, front.y))
		while h.sim.player(0).state == TC.PState.CAPTURED:
			await h.step()
		var r := h.sim.player(0)
		t.check(CampusDorms.in_room(d, r.pos()), "%s: respawned inside the home dorm" % d)
		var pick := RulesLogic.choose_pad(CampusDorms.geometry(d)["respawn"], [front])
		t.check(r.pos2().distance_to(pick) < 0.5, "%s: on the pad farthest from the Night Watch" % d)
		t.check(r.protect > 1.5, "%s: protected on return" % d)
		h.place(0, Vector3(0, -20, 0))
		await h.wait_event(TC.Ev.RECOVER, 10)
		t.check(CampusDorms.in_room(d, r.pos()), "%s: out-of-bounds recovery also returns inside" % d)
		h.free_sim()


## Door jambs don't snag: from many angles and offsets, and sliding along
## the wall, a runner pushing for the door gets in without getting stuck.
func test_doors_dont_snag() -> void:
	var worst := 0.0
	for d in CampusDorms.ids():
		var h := _h()
		h.make([R, P], [0, 1, 2], [], 81, {"dorm": d})
		await h.release_patrol()
		var r := h.sim.player(0)
		for dr in h.sim.home_doors:
			var n_in: Vector2 = dr["n_in"]
			var tg: Vector2 = dr["tangent"]
			var lp: Vector2 = dr["line_p"]
			for ang in [-60.0, -30.0, 0.0, 30.0, 60.0]:
				for off in [-1.0, 0.0, 1.0]:
					r.stamps = 7
					r.state = TC.PState.ACTIVE
					r.finished_tick = -1
					Motor.set_body_enabled(r.body, true)
					var dir := n_in.rotated(deg_to_rad(ang))
					var target: Vector2 = lp + tg * float(off)
					var start: Vector2 = target - dir * 6.0
					h.place(0, Vector3(start.x, 0.05, start.y), atan2(-dir.x, -dir.y))
					h.cmd(0).move = dir
					var ticks := 0
					while r.state != TC.PState.FINISHED and ticks < 240:
						await h.step()
						ticks += 1
						# steer for the door like a player would
						var to := (lp + n_in * 1.0 - r.pos2()).normalized()
						h.cmd(0).move = to
					h.cmd(0).move = Vector2.ZERO
					worst = maxf(worst, float(ticks) / 60.0)
					t.check(r.state == TC.PState.FINISHED and ticks < 150, "%s %s: in from %d deg, offset %.0f (%.2f s)" % [d, dr["id"], int(ang), off, float(ticks) / 60.0])
					h.sim.finished_count = 0
			# sliding along the outer wall into the opening
			for side in [-1.0, 1.0]:
				r.stamps = 7
				r.state = TC.PState.ACTIVE
				Motor.set_body_enabled(r.body, true)
				var wall_pt: Vector2 = (dr["pos"] as Vector2) + (dr["normal"] as Vector2) * 0.45 + tg * side * 4.0
				h.place(0, Vector3(wall_pt.x, 0.05, wall_pt.y))
				var push: Vector2 = (n_in * 0.6 - tg * float(side)).normalized()
				h.cmd(0).move = push
				var k := 0
				while r.state != TC.PState.FINISHED and k < 240:
					await h.step()
					k += 1
					if r.pos2().distance_to(lp) < 1.2:
						h.cmd(0).move = n_in
				h.cmd(0).move = Vector2.ZERO
				t.check(r.state == TC.PState.FINISHED, "%s %s: sliding along the wall into the door (%.2f s)" % [d, dr["id"], float(k) / 60.0])
				h.sim.finished_count = 0
		h.free_sim()
	print("[dorms] slowest scripted door entry: %.2f s" % worst)


## Bots use the doors: at GO runner bots leave the dorm, and a runner bot
## with every stamp comes home through one of tonight's doors.  A Night
## Watch bot doesn't chase a runner who is safe inside.
func test_bots_leave_and_come_home_through_the_doors() -> void:
	for d in CampusDorms.ids():
		var h := _h()
		h.make([R, R, R, R, P, P], [0, 1, 2], [0, 1, 2, 3], 91, {"dorm": d})
		await h.to_playing()
		await h.step(60 * 10)
		var out := 0
		for i in 4:
			if not CampusDorms.in_room(d, h.sim.player(i).pos()):
				out += 1
		t.check(out >= 3, "%s: runner bots are out of the dorm 10 s after GO (%d/4)" % [d, out])
		# home: a bot with every stamp, 40 m out on the main approach
		var r := h.sim.player(0)
		r.stamps = 7
		var front: Vector2 = h.sim.home_doors[0]["approach"]
		var far := front + (h.sim.home_doors[0]["normal"] as Vector2) * 38.0
		h.place(0, Vector3(far.x, 0.05, far.y))
		(h.sim.bots[0] as BotBrain).replan_t = 0.0
		var ticks := 0
		while r.state != TC.PState.FINISHED and ticks < 60 * 30:
			await h.step()
			ticks += 1
		t.eq(r.state, TC.PState.FINISHED, "%s: runner bot comes home through a door (%.1f s)" % [d, float(ticks) / 60.0])
		t.check(CampusDorms.has_dorm(d) and h.sim.home_doors.map(func(x: Dictionary) -> String: return x["id"]).has(r.finish_door), "%s: through a home door (%s)" % [d, r.finish_door])
		h.free_sim()


## The host picks tonight's dorm from the seed, never the same twice in a
## row, and publishes it with its geometry version and fingerprint, the
## spawn pads, the coins and the start timing in the round configuration.
func test_round_configuration_rotates_the_home_dorm() -> void:
	var s := NetSession.new()
	t.add_child(s)
	s.start_offline("u-dorm", "Tester", {}, "runner")
	var starts: Array = []
	s.match_starting.connect(func(i: Dictionary) -> void: starts.append(i))
	var seen := {}
	var prev := ""
	for k in 30:
		s.host_start_match(1000 + k * 37)
		var st: Dictionary = starts[-1]
		var d := String(st["home_dorm"])
		t.check(CampusDorms.has_dorm(d), "round %d: a real dorm (%s)" % [k, d])
		t.check(d != prev, "round %d: not last round's dorm" % k)
		var dm: Dictionary = st["dorm"]
		t.eq(String(dm["id"]), d, "configuration names it")
		t.eq(int(dm["ver"]), CampusDorms.VERSION, "with the geometry version")
		t.eq(String(dm["geo"]), CampusDorms.geometry_hash(d), "and its fingerprint")
		t.eq((dm["spawns"] as Dictionary).size(), (st["roster"] as Array).size(), "a spawn for every seat")
		t.check(RulesLogic.curated_combos(d).has(st["targets"]), "targets from %s's fair set" % d)
		t.eq((st["coins"] as Array).size(), Rules.cfg.coin_spawns_per_round, "the round's coins")
		t.check((st["timing"] as Dictionary).has("countdown_s"), "start timing")
		seen[d] = true
		prev = d
	t.eq(seen.size(), CampusDorms.ids().size(), "every dorm comes round")
	s.queue_free()


## A guest checks the configuration field by field; another build's dorm
## geometry is refused cleanly ("Update the game"), bad pads fall back.
func test_guest_refuses_other_dorm_geometry() -> void:
	var host := NetSession.new()
	t.add_child(host)
	host.start_offline("u-h", "Host", {}, "runner")
	var st := {}
	host.match_starting.connect(func(i: Dictionary) -> void: st.merge(i, true), CONNECT_ONE_SHOT)
	host.host_start_match(4242)
	var wire: Dictionary = JSON.parse_string(JSON.stringify(NetSession._jsonable(st)))
	var guest := NetSession.new()
	t.add_child(guest)
	var ok := guest._fix_start(wire.duplicate(true))
	t.eq(String(ok.get("home_dorm", "")), String(st["home_dorm"]), "a valid configuration is accepted as sent")
	t.eq((ok["dorm"] as Dictionary)["spawns"], (st["dorm"] as Dictionary)["spawns"], "spawn pads kept")
	t.eq(ok["coins"], st["coins"], "coins kept")
	var bad := wire.duplicate(true)
	bad["dorm"]["geo"] = "0000000000000000"
	t.check(guest._fix_start(bad).has("_incompatible"), "another geometry is incompatible")
	var bad2 := wire.duplicate(true)
	bad2["dorm"]["id"] = "nowhere_hall"
	t.check(guest._fix_start(bad2).has("_incompatible"), "an unknown dorm is incompatible")
	var bad3 := wire.duplicate(true)
	bad3["dorm"]["ver"] = CampusDorms.VERSION + 1
	t.check(guest._fix_start(bad3).has("_incompatible"), "another geometry version is incompatible")
	var odd := wire.duplicate(true)
	for k in (odd["dorm"]["spawns"] as Dictionary).keys():
		odd["dorm"]["spawns"][k] = 99
	odd["coins"].append({"id": "x", "x": 9999.0, "z": 0.0})
	odd["coins"].append({"id": "s00"})
	var fixed := guest._fix_start(odd)
	var defaults := MatchSim.default_spawns(fixed["roster"])
	for k in (fixed["dorm"]["spawns"] as Dictionary):
		t.eq(int(fixed["dorm"]["spawns"][k]), int(defaults[int(k)]), "an out-of-range pad falls back to the default")
	t.eq((fixed["coins"] as Array).size(), (st["coins"] as Array).size(), "malformed coins are dropped")
	# the real packet path: the guest leaves with "version"
	var reason := []
	guest.ended.connect(func(r: String) -> void: reason.append(r))
	var b := Protocol.buf_for(Protocol.M.START)
	var u := JSON.stringify(bad).to_utf8_buffer()
	b.put_u32(u.size())
	b.put_data(u)
	guest.mode = NetSession.Mode.CLIENT
	var rd := Protocol.reader(b.data_array)
	rd.get_u8()
	guest._client_packet(0, Protocol.M.START, rd)
	t.eq(reason, ["version"], "the guest ends cleanly with an update message")
	host.queue_free()
	guest.queue_free()
	await t.get_tree().process_frame


## Nothing with a collider (lamp posts, benches, tree trunks, props) stands
## in a start dorm's doorway or on the line from a door out to its approach
## point, where runners leave and come home.
func test_doorways_and_approaches_are_clear() -> void:
	var lay := CampusLayout.shared()
	var things: Array = []
	for l in lay.lamps:
		things.append(["lamp", l, 0.2])
	for b in lay.benches:
		things.append(["bench", b["pos"], 1.0])
	for tr in lay.trees:
		if bool(tr.get("collide", true)):
			things.append(["tree", tr["pos"], 0.45])
	for pr in lay.props:
		var ps := CampusArchitecture.prop_collider(pr)
		if ps != Vector3.ZERO:
			things.append([pr["kind"], pr["pos"], Vector2(ps.x, ps.z).length() * 0.5])
	t.check(lay.dorm_doors.size() >= 2, "start dorm doors found (%d)" % lay.dorm_doors.size())
	for d in lay.dorm_doors:
		var a: Vector2 = d["pos"]
		var b: Vector2 = d["approach"]
		var hw := float(d["w"]) * 0.5
		for it in things:
			var p: Vector2 = it[1]
			t.check(CampusData.dist_to_segment(p, a, b) >= hw + float(it[2]) - 0.3, "%s at %s keeps clear of %s's %s doorway" % [it[0], str(p), d["dorm"], d["id"]])


## The follow camera never clips into the dorm: from every pad and every
## door's inside, turned all the way round and pitched from low to high,
## the real camera's sweep leaves it outside every collider (walls, ceiling,
## lintels, furniture), under the ceiling while inside the room, and with a
## clear line to the runner (it may look in through an open doorway).
func test_camera_never_clips_into_the_dorm() -> void:
	var h := _h()
	h.make([R, P])
	await h.step()
	var cam := FollowCamera.new()
	h.sim.add_child(cam)
	await t.get_tree().process_frame
	var ss := h.sim.space_state()
	var probe := SphereShape3D.new()
	probe.radius = 0.12
	var worst := INF
	for d in CampusDorms.ids():
		var g := CampusDorms.geometry(d)
		var room: Rect2 = g["room"]
		var pts: Array = []
		for pd in g["pads"]:
			pts.append(pd["pos"])
		for dr in g["doors"]:
			pts.append(dr["inside"])
		for pp in pts:
			for yi in 8:
				for pitch in [-0.1, 0.32, 0.9]:
					var p := Vector3((pp as Vector2).x, 0.05, (pp as Vector2).y)
					cam.snap_to(p, TAU * float(yi) / 8.0)
					cam.pitch = pitch
					cam.target_pos = p
					for k in 12:
						cam.update_camera(1.0 / 60.0)
					var cp := cam.global_position
					var q := PhysicsShapeQueryParameters3D.new()
					q.shape = probe
					q.collision_mask = TC.L_WORLD
					q.transform = Transform3D(Basis.IDENTITY, cp)
					var clear := ss.intersect_shape(q, 1).is_empty()
					var los := ss.intersect_ray(PhysicsRayQueryParameters3D.create(cp, p + Vector3(0, 1.2, 0), TC.L_WORLD)).is_empty()
					if room.has_point(Vector2(cp.x, cp.z)):
						worst = minf(worst, CampusDorms.CEIL - cp.y)
						t.check(cp.y < CampusDorms.CEIL - 0.1, "%s: camera under the ceiling (%s)" % [d, str(cp)])
					t.check(clear and los, "%s: camera clear of every collider and sees the runner (pad %s, yaw %d/8, pitch %.2f -> %s)" % [d, str(pp), yi, pitch, str(cp)])
	print("[dorms] closest the camera came to a ceiling: %.2f m" % worst)
	cam.queue_free()
	h.free_sim()


## Door camping can't stop a departure: two watchers standing outside two
## of the home doors; a runner caught before any splash comes back inside on
## the pad by the third door, can't be tagged until it steps out, and is
## protected when it does.
func test_two_door_campers_cant_block_the_way_out() -> void:
	for d in CampusDorms.ids():
		var h := _h()
		h.make([R, P, P], [0, 1, 2], [], 77, {"dorm": d})
		await h.release_patrol()
		h.place(0, Vector3(-20, 0.05, 60), 0.0)
		h.place(1, Vector3(-20, 0.05, 61.2), 0.0)
		await h.step()
		h.press(1, TC.BTN_TAG)
		await h.wait_event(TC.Ev.CAPTURE, 60)
		var doors: Array = h.sim.home_doors
		for k in 2:
			var ap: Vector2 = doors[k]["approach"]
			h.place(1 + k, Vector3(ap.x, 0.05, ap.y))
		while h.sim.player(0).state == TC.PState.CAPTURED:
			await h.step()
		var r := h.sim.player(0)
		var third: Vector2 = CampusDorms.geometry(d)["respawn"][2]
		t.check(r.pos2().distance_to(third) < 0.5, "%s: back on the pad by the uncamped door" % d)
		t.check(not r.is_taggable(), "%s: safe (inside, protected)" % d)
		h.free_sim()
