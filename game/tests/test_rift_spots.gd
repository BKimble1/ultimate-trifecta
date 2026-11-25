extends RefCounted
## Every rift spot on every map works: a runner who walks into it on foot is
## sent through, and comes out standing on open ground at the far end; where
## a cart can drive up to a spot, a cart driven into it goes through too.
var t

const R := TC.Role.RUNNER
const P := TC.Role.PATROL


## A ground point `d` metres from the spot that a runner can walk in from:
## on the walking grid, with a clear line at knee and chest height.
func _approach(h: SimHarness, at: Vector3, d: float, nav: NavGrid, cart: bool) -> Array:
	for k in 16:
		var a := TAU * float(k) / 16.0
		var dir := Vector2(cos(a), sin(a))
		var p2 := Vector2(at.x, at.z) + dir * d
		if cart:
			if not nav.is_drivable(p2) or not nav.is_drivable(Vector2(at.x, at.z) + dir * d * 0.5):
				continue
		elif not nav.is_walkable(p2) or not nav.is_walkable(Vector2(at.x, at.z) + dir * d * 0.5):
			continue
		var from := h.on_ground(p2)
		var clear := true
		# a runner's line at knee and chest height; a cart's whole width
		var side := Vector3(-dir.y, 0, dir.x)
		var lanes: Array = [[0.0, 0.5], [0.0, 1.2]]
		if cart:
			lanes = [[0.0, 0.35], [0.85, 0.35], [-0.85, 0.35], [0.0, 1.0]]
		for ln in lanes:
			var o: Vector3 = side * float(ln[0]) + Vector3(0, float(ln[1]), 0)
			var q := PhysicsRayQueryParameters3D.create(from + o, Vector3(at.x, from.y, at.z) + o, TC.L_WORLD | TC.L_CART_BLOCK)
			if not h.sim.space_state().intersect_ray(q).is_empty():
				clear = false
		if clear:
			return [from, -dir]
	return []


func _spot_report(id: String) -> Dictionary:
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2], [], 31, {"map": id, "pace": false})
	await h.release_patrol()
	h.sim.end_tick = 1 << 30      # (a long walk round every spot)
	var lay := h.sim.layout
	var nav := NavGrid.shared(lay)
	var sp := Rifts.spots(lay)
	var bad: Array = []
	var foot_ok := 0
	var cart_ok := 0
	var cart_tried := 0
	var r := h.sim.player(0)
	var w := h.sim.player(1)
	var skipped := 0
	for i in sp.size():
		if not Rifts.usable(lay, i):
			skipped += 1      # (never picked: nobody could stand there)
			continue
		var at := Rifts.world(lay, i)
		var to_i := (i + sp.size() / 2) % sp.size()
		while not Rifts.usable(lay, to_i):
			to_i = (to_i + 1) % sp.size()
		var ap := _approach(h, at, 4.0, nav, false)
		if ap.is_empty():
			bad.append("%d %s: no way to walk in" % [i, str(sp[i])])
			continue
		h.sim.rifts[0] = {"at": i, "to": to_i, "open": true, "wait": 0.0, "life": 60.0}
		h.sim.rifts[1] = {"at": 0, "to": 0, "open": false, "wait": 999.0, "life": 0.0}
		var dir: Vector2 = ap[1]
		h.place(0, ap[0], atan2(-dir.x, -dir.y))
		r.state = TC.PState.ACTIVE
		r.prev_pos = Vector3.INF
		h.cmd(0).move = dir
		var went := false
		for k in 90:
			await h.step()
			if not h.events_of(TC.Ev.RIFT).is_empty():
				went = true
				break
		h.cmd(0).move = Vector2.ZERO
		if not went:
			bad.append("%d %s (y %.2f, body %s): walking in did nothing" % [i, str(sp[i]), at.y, str(r.pos())])
			continue
		# out at the far end, standing on ground there
		await h.step(20)
		var to := Rifts.world(lay, to_i)
		var rp := r.pos()
		if Vector2(rp.x - to.x, rp.z - to.z).length() > 4.0 or absf(rp.y - h.gy(Vector2(rp.x, rp.z))) > 0.6:
			bad.append("%d -> %d: came out at %s, not standing by %s" % [i, to_i, str(rp), str(to)])
			continue
		foot_ok += 1
		# a cart, where one can drive up to it
		var cap := _approach(h, at, 9.0, nav, true)
		if cap.is_empty():
			continue
		cart_tried += 1
		h.sim.rifts[0] = {"at": i, "to": to_i, "open": true, "wait": 0.0, "life": 60.0}
		var c: SimCart = h.sim.carts[0]
		var cdir: Vector2 = cap[1]
		h.place(1, cap[0])
		w.state = TC.PState.IN_CART
		w.cart_id = 0
		c.occupant = 1
		c.exiting = false
		Motor.set_body_enabled(w.body, false)
		c.body.global_position = cap[0] + Vector3(0, 0.05, 0)
		c.yaw = atan2(-cdir.x, -cdir.y)
		c.body.rotation.y = c.yaw
		c.speed = 4.0
		h.cmd(1).drive = 1.0
		h.cmd(1).steer = 0.0
		var cwent := false
		for k in 150:
			await h.step()
			if not h.events_of(TC.Ev.RIFT).is_empty():
				cwent = true
				break
		h.cmd(1).drive = 0.0
		c.speed = 0.0
		c.occupant = -1
		w.cart_id = -1
		w.state = TC.PState.ACTIVE
		Motor.set_body_enabled(w.body, true)
		h.place(1, h.on_ground(Vector2(lay.patrol_spawns[0].x, lay.patrol_spawns[0].y)))
		if cwent:
			cart_ok += 1
		else:
			bad.append("%d %s: a cart driven in from %s did nothing (cart at %s)" % [i, str(sp[i]), str(cap[0]), str(c.pos())])
	h.free_sim()
	return {"n": sp.size() - skipped, "skipped": skipped, "foot": foot_ok, "cart": cart_ok, "cart_tried": cart_tried, "bad": bad}


func test_every_rift_spot_takes_a_runner_and_a_cart() -> void:
	for id in [CampusMaps.CLASSIC, CampusMaps.CAMPUS]:
		var rep: Dictionary = await _spot_report(id)
		print("RIFT SPOTS %s: %d usable spots (%d never picked), %d by foot, %d/%d by cart" % [id, rep["n"], rep["skipped"], rep["foot"], rep["cart"], rep["cart_tried"]])
		t.check(int(rep["skipped"]) * 20 <= int(rep["n"]), "%s: hardly any spot is left out (%d)" % [id, rep["skipped"]])
		for b in rep["bad"]:
			print("  RIFT BAD %s: %s" % [id, b])
		t.check((rep["bad"] as Array).is_empty(), "%s: every rift spot takes a runner on foot and a cart (%d problems)" % [id, (rep["bad"] as Array).size()])
		t.eq(int(rep["foot"]), int(rep["n"]), "%s: all %d spots work on foot" % [id, rep["n"]])


## (build 35) The view of a rift slot that hasn't opened yet is never drawn
## (it used to open at the world's origin: on Moonbrook a dead portal on the
## quad in front of the Bell Tower for the first 20-70 s of every round);
## an opened rift shows at its spot; a slot that moves collapses first.
func test_a_closed_rift_slot_draws_no_portal() -> void:
	var v := RiftView.new()
	t.add_child(v)
	var spot := Vector3(5, 0, 70)
	for i in 30:
		v.sync(spot, false)
		v._process(1.0 / 30.0)
	t.check(not v.visible, "a closed slot shows nothing")
	t.check(v.position.distance_to(Vector3.ZERO) > 1.0, "and nothing stays at the origin (%s)" % str(v.position))
	for i in 60:
		v.sync(spot, true)
		v._process(1.0 / 30.0)
	t.check(v.visible and v.position.distance_to(spot) < 0.1, "an open rift shows at its spot")
	var next := Vector3(-40, 0, -20)
	var shown_elsewhere := false
	for i in 90:
		v.sync(next, true)
		v._process(1.0 / 30.0)
		if v._want > 0.0 and v.position.distance_to(next) > 0.5:
			shown_elsewhere = true
	t.check(v.visible and v.position.distance_to(next) < 0.1, "a new rift in the slot opens at its own spot")
	t.check(not shown_elsewhere, "after collapsing where it was (never open at the old spot)")
	v.queue_free()


func test_pick_never_uses_a_spot_nobody_can_stand_on() -> void:
	for id in [CampusMaps.CLASSIC, CampusMaps.CAMPUS]:
		var lay := CampusMaps.layout(id)
		var rng := RandomNumberGenerator.new()
		rng.seed = 99
		var ok := true
		for k in 300:
			var rf := Rifts.pick(lay, rng, {})
			if rf.is_empty() or not Rifts.usable(lay, int(rf["at"])) or not Rifts.usable(lay, int(rf["to"])):
				ok = false
		t.check(ok, "%s: every picked rift starts and ends where a runner can stand" % id)
