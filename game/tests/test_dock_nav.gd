extends RefCounted
## Docks on the foot nav grid, and shore exits out of the water.
##  * Moonbrook College's Boathouse Inlet dock meets the bank at its root,
##    but the water's inflated margin (and the deck carved short of its
##    edges) left a solid row between them: the dock was an island on the
##    grid, so a path from any shore exit to the water's centre (whose
##    nearest open cell is on the dock) or to the runner jump point at the
##    dock's head came back empty.  The dock's lane is carved through to the
##    bank like a footbridge's.
##  * A scenery water with no bank in the play area (the reference campus's
##    woods_pond_west) had its one shore exit at the centre's fallback, in
##    the water itself: anyone resurfacing there splashed again at once.
var t


static func _dock_rect(pf: Dictionary) -> Rect2:
	var c: Vector3 = pf["center"]
	var s: Vector3 = pf["size"]
	return Rect2(Vector2(c.x, c.z) - Vector2(s.x, s.z) * 0.5, Vector2(s.x, s.z))


func test_inlet_dock_reached_from_the_shore() -> void:
	var lay := CampusMaps.layout(CampusMaps.CLASSIC)
	var nav := NavGrid.shared(lay)
	var w := lay.water_by_id("inlet")
	t.check(not w.is_empty(), "the classic map has the Boathouse Inlet")
	if w.is_empty():
		return
	var dock := {}
	for pf in lay.platforms:
		if pf.get("dock", false) and lay.water_index_at(_dock_rect(pf).get_center()) == lay.water_index("inlet"):
			dock = pf
	t.check(not dock.is_empty(), "the inlet has its dock")
	if dock.is_empty():
		return
	var rect := _dock_rect(dock)
	var centre: Vector2 = w["center"]
	var on_dock := nav.to_world(nav.nearest_open(nav.foot, centre))
	t.check(rect.has_point(on_dock), "the water centre's nearest open cell is on the dock (%s)" % on_dock)
	var targets: Array = [centre]
	for j in w["jump_points"]:
		if rect.has_point(j):
			targets.append(j)
	t.check(targets.size() >= 2, "a runner jump point on the dock (%d)" % (targets.size() - 1))
	for e in w["exits"]:
		var e2 := Vector2(e.x, e.z)
		for g: Vector2 in targets:
			var path := nav.find_path(e2, g)
			t.check(path.size() >= 2 and rect.has_point(path[path.size() - 1]),
				"inlet exit %s: a foot path onto the dock toward %s (%d points)" % [e2, g, path.size()])
	# the lane opens the bank, never the water: every open cell over the
	# inlet is on the deck
	var wr: Rect2 = w["rect"]
	var stray: Array = []
	for cc in nav._cells_in_rect(wr):
		var p := nav.to_world(cc)
		if not nav.foot.is_point_solid(cc) and lay.water_index_at(p) >= 0 and not rect.has_point(p):
			stray.append(p)
	t.check(stray.is_empty(), "no open cell over the inlet off the dock (%s)" % [stray.slice(0, 4)])


## Every dock (on any map) is joined to a shore exit of its water.
func test_docks_meet_their_banks() -> void:
	var n := 0
	for id in CampusMaps.ids():
		var lay := CampusMaps.layout(id)
		var docks := lay.platforms.filter(func(pf: Dictionary) -> bool: return pf.get("dock", false))
		if docks.is_empty():
			continue
		var nav := NavGrid.shared(lay)
		for pf: Dictionary in docks:
			var rect := _dock_rect(pf)
			var wi := lay.water_index_at(rect.get_center())
			if wi < 0:
				continue
			var reached := 0
			var exits: Array = lay.waters[wi]["exits"]
			for e in exits:
				var path := nav.find_path(Vector2(e.x, e.z), rect.get_center())
				if path.size() >= 2 and rect.has_point(path[path.size() - 1]):
					reached += 1
			t.check(reached == exits.size(), "%s dock at %s: reached from %d of %d shore exits" % [id, rect.get_center(), reached, exits.size()])
			n += 1
	t.check(n >= 1, "docks found (%d)" % n)


## Nobody resurfaces in the water: every shore exit of every water (play
## area or scenery) stands on dry ground.
func test_shore_exits_are_out_of_the_water() -> void:
	for id in CampusMaps.ids():
		var lay := CampusMaps.layout(id)
		for wi in lay.waters.size():
			var w: Dictionary = lay.waters[wi]
			if bool(w.get("wade", false)):
				continue
			var exits: Array = w["exits"]
			t.check(not exits.is_empty(), "%s %s: has a shore exit" % [id, w["id"]])
			for e in exits:
				var e2 := Vector2(e.x, e.z)
				t.check(CampusBuilder.water_at(lay, e2) < 0, "%s %s: exit %s is out of the water" % [id, w["id"], e2])
