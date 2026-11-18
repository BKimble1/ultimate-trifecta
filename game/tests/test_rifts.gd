extends RefCounted
## (2.2 build 16) Rift portals: a few open on the campus from the seed, each
## leads far away; stepping in sends a player out at its far end and closes
## it; a new one opens elsewhere later.  Every spot is open ground.
var t

const R := TC.Role.RUNNER
const P := TC.Role.PATROL


func test_spots_are_open_ground() -> void:
	var L := CampusLayout.shared()
	var sp := Rifts.spots(L)
	t.check(sp.size() >= 12, "plenty of rift spots (%d)" % sp.size())
	t.check(sp.size() <= 255, "fit a byte")
	for v in sp:
		t.check(L.water_index_at(v, 1.0) < 0 and L.building_at(v, 0.5) < 0, "rift spot %s is dry open ground" % str(v))


func test_a_rift_sends_you_far_and_closes() -> void:
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2])
	await h.release_patrol()
	t.eq(h.sim.rifts.size(), Rifts.COUNT, "%d rift slots" % Rifts.COUNT)
	t.check(not bool(h.sim.rifts[0]["open"]) and not bool(h.sim.rifts[1]["open"]), "(2.2 build 17) none open at GO: they're rare")
	await h.step(int(Rifts.FIRST_WAIT.y * 60.0) + 5)
	t.check(bool(h.sim.rifts[0]["open"]), "the first opens a while into the round")
	var rf: Dictionary = h.sim.rifts[0]
	var at := Rifts.world(h.sim.layout, int(rf["at"]))
	var to := Rifts.world(h.sim.layout, int(rf["to"]))
	t.check(Vector2(at.x - to.x, at.z - to.z).length() >= Rifts.MIN_TRIP, "it leads far away")
	h.place(0, at + Vector3(0, 0.05, 0))
	var went := false
	for i in 10:
		await h.step()
		if not h.events_of(TC.Ev.RIFT).is_empty():
			went = true
			break
	t.check(went, "stepping in sends you through")
	var p := h.sim.player(0).pos()
	t.check(Vector2(p.x - to.x, p.z - to.z).length() < 3.0, "out at the far end (%s near %s)" % [str(p), str(to)])
	t.check(not bool(h.sim.rifts[0]["open"]), "and the rift closes")
	# a while later a new one opens somewhere else
	await h.step(int(Rifts.REOPEN_WAIT.y * 60.0) + 5)
	t.check(bool(h.sim.rifts[0]["open"]), "a new rift opens later")
	t.check(int(h.sim.rifts[0]["at"]) != int(rf["at"]) or int(h.sim.rifts[0]["to"]) != int(rf["to"]), "elsewhere")
	h.free_sim()


func test_rifts_never_sit_on_a_coin_or_a_power_up() -> void:
	var L := CampusLayout.shared()
	for v in Rifts.spots(L):
		for c in L.coin_spots:
			t.check((c as Vector2).distance_to(v) >= 3.5, "rift %s clear of coin %s" % [str(v), str(c)])
		for g in L.gadget_spots:
			t.check((g as Vector2).distance_to(v) >= 6.0, "rift %s clear of power-up %s" % [str(v), str(g)])


## (build 20) Open a rift at once (the round's own timing is tested above).
func _open(h: SimHarness) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	h.sim.rifts[0] = Rifts.pick(h.sim.layout, rng, {})
	return h.sim.rifts[0]


func test_touching_the_glowing_ring_takes_you_through() -> void:
	# a runner whose body reaches the visible ring goes through (1.1 m used to
	# let them run past the portal's edge with nothing happening)
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2])
	await h.release_patrol()
	var rf := _open(h)
	var at := Rifts.world(h.sim.layout, int(rf["at"]))
	h.place(0, at + Vector3(1.4, 0.05, 0))
	h.sim.player(0).prev_pos = Vector3.INF
	h.sim._check_rifts(0.0)
	t.eq(h.events_of(TC.Ev.RIFT).size(), 1, "1.4 m from the middle, inside the ring: through")
	h.free_sim()


func test_a_fast_step_across_the_portal_counts() -> void:
	# both ends of the tick's step outside the catch, the step across it
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2])
	await h.release_patrol()
	var rf := _open(h)
	var at := Rifts.world(h.sim.layout, int(rf["at"]))
	h.place(0, at + Vector3(2.2, 0.05, 0))
	h.sim.player(0).prev_pos = at + Vector3(-2.2, 0.05, 0)
	h.sim._check_rifts(0.0)
	t.eq(h.events_of(TC.Ev.RIFT).size(), 1, "a step straight across goes through")
	h.free_sim()


func test_walking_past_stays_put() -> void:
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2])
	await h.release_patrol()
	var rf := _open(h)
	var at := Rifts.world(h.sim.layout, int(rf["at"]))
	h.place(0, at + Vector3(2.4, 0.05, 0))
	h.sim.player(0).prev_pos = at + Vector3(2.4, 0.05, 1.0)
	h.sim._check_rifts(0.0)
	t.eq(h.events_of(TC.Ev.RIFT).size(), 0, "2.4 m away, walking past: nothing")
	t.check(bool(h.sim.rifts[0]["open"]), "and it stays open")
	h.free_sim()


func test_a_cart_drives_through_with_its_driver() -> void:
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2])
	await h.release_patrol()
	var rf := _open(h)
	var at := Rifts.world(h.sim.layout, int(rf["at"]))
	var to := Rifts.world(h.sim.layout, int(rf["to"]))
	var w := h.sim.player(1)
	var c: SimCart = h.sim.carts[0]
	# the Night Watch at the wheel of cart 0, driving into the rift
	c.occupant = w.id
	w.cart_id = 0
	w.state = TC.PState.IN_CART
	Motor.set_body_enabled(w.body, false)
	c.body.global_position = at + Vector3(0, -0.25, 0)
	c.speed = 8.0
	h.sim._check_rifts(0.0)
	t.eq(h.events_of(TC.Ev.RIFT).size(), 1, "the cart goes through")
	t.check(Vector2(c.pos().x - to.x, c.pos().z - to.z).length() < 4.0, "the cart comes out at the far end")
	t.check(Vector2(w.pos().x - to.x, w.pos().z - to.z).length() < 4.0, "with its driver")
	t.eq(c.speed, 8.0, "still rolling")
	h.free_sim()
