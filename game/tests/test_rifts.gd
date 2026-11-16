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
