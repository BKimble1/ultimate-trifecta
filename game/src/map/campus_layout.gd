class_name CampusLayout
extends RefCounted
## Moonbrook College — the single V1 campus, described as data.
## Visual meshes, collision, bot navigation grids, route analysis and spawn
## logic are all generated from this one description so they cannot drift.
## Coordinates: metres, +X east, +Z south (north is -Z). Ground is y = 0.
##
## V6: three playable dorms with real common rooms (CampusDorms).  The
## V5 campus is still built first, exactly as before (`legacy` stops there:
## tests prove it hashes to the recorded V4/V5 values), then the dorm
## districts are rebuilt on top of it: Puddlesworth Hall's single box
## becomes a shell with a common room, Lanternfield House and Moonpenny
## Lodge go up on the open lawns west and east of it, with their yards,
## approaches and props.  Everything outside CampusDorms.DISTRICTS stays
## as V5 had it (test_campus_art checks it collider by collider and cell by
## cell).

const BOUNDS := Rect2(-160.0, -150.0, 320.0, 300.0)
const CAMPUS_NAME := "Moonbrook College"

var buildings: Array[Dictionary] = []
var waters: Array[Dictionary] = []
var roads: Array[Dictionary] = []
var paths: Array[Dictionary] = []
var plazas: Array[Dictionary] = []
var walls: Array[Dictionary] = []      # low stone walls: runners hop, carts blocked
var hedges: Array[Dictionary] = []     # tall hedges: block everyone and sight
var fences: Array[Dictionary] = []     # fences/rails: block everyone, see-through
var cart_blockers: Array[Dictionary] = []  # bollard lines: block carts only
var trees: Array[Dictionary] = []
var rocks: Array[Dictionary] = []
var platforms: Array[Dictionary] = []  # raised walkable boxes (dock, ledge)
var ramps: Array[Dictionary] = []      # walkable inclines (character colliders)
var lamps: Array[Vector2] = []
var benches: Array[Dictionary] = []
var props: Array[Dictionary] = []
var dorm_doors: Array[Dictionary] = []
var dorm_pads: Array[Vector2] = []
var runner_spawns: Array[Vector2] = []
var patrol_spawns: Array[Vector2] = []
var cart_spawns: Array[Dictionary] = []
var gadget_spots: Array[Vector2] = []
var landmarks: Array[Dictionary] = []
## V6: the three dorms ({def + "geo": CampusDorms.geometry}) and the
## candidate spots for the round's collectible coins (the host picks a few)
var dorms: Array[Dictionary] = []
var coin_spots: Array[Vector2] = []
## V6: small static colliders of new props (monument signs):
## [{pos: Vector2, size: Vector3, rot: float, kind: String}]
var solids: Array[Dictionary] = []
## true: the V5 campus only (no V6 dorm districts) - proofs and the dressing
var legacy := false

static var _shared: CampusLayout
static var _legacy_shared: CampusLayout


static func shared() -> CampusLayout:
	if _shared == null:
		_shared = CampusLayout.new()
	return _shared


## The V5 campus (no V6 dorm districts), shared: the V6 dressing keeps the
## V5 pieces outside the districts, and the proofs compare against it.
static func legacy_shared() -> CampusLayout:
	if _legacy_shared == null:
		_legacy_shared = CampusLayout.new(true)
	return _legacy_shared


func _init(p_legacy: bool = false) -> void:
	legacy = p_legacy
	_build_buildings()
	_build_waters()
	_build_roads_and_paths()
	_build_boundaries_and_barriers()
	_build_dorm()
	_build_spawns()
	_build_trees_and_props()
	if not legacy:
		_build_dorm_districts()
		_build_coin_spots()


# ---------------------------------------------------------------------------
# Buildings
# ---------------------------------------------------------------------------
func _bld(id: String, name: String, pos: Vector2, size: Vector2, h: float, wall: Color, roof: Color, extra: Dictionary = {}) -> void:
	var d := {"id": id, "name": name, "pos": pos, "size": size, "h": h, "wall": wall, "roof": roof, "rot": 0.0}
	d.merge(extra, true)
	buildings.append(d)


func _build_buildings() -> void:
	var brick := Color(0.64, 0.34, 0.30)
	var stone := Color(0.60, 0.60, 0.68)
	var cream := Color(0.86, 0.80, 0.66)
	var slate := Color(0.26, 0.30, 0.42)
	var teal := Color(0.20, 0.42, 0.46)
	_bld("dorm", "Puddlesworth Hall", Vector2(0, 112), Vector2(44, 18), 11.0, brick, slate, {"dorm": true, "warm": 0.9})
	_bld("library", "Inkwell Library", Vector2(-50, 18), Vector2(22, 34), 13.0, stone, Color(0.32, 0.26, 0.40), {"warm": 0.55, "columns": true})
	_bld("science", "Beaker Hall", Vector2(50, 18), Vector2(22, 34), 12.0, Color(0.45, 0.55, 0.66), teal, {"warm": 0.35})
	_bld("chapel_w", "Bellweather Tower", Vector2(-7, -30), Vector2(8, 14), 10.0, cream, slate, {"warm": 0.4})
	_bld("chapel_e", "Bellweather Tower", Vector2(7, -30), Vector2(8, 14), 10.0, cream, slate, {"warm": 0.4})
	_bld("tower", "Bellweather Tower", Vector2(0, -30), Vector2(6, 6), 26.0, cream, Color(0.22, 0.48, 0.42), {"arch": true, "clock": true, "warm": 0.2, "base_y": 4.2})
	_bld("dining", "Noodle Commons", Vector2(-42, 66), Vector2(26, 16), 8.0, Color(0.80, 0.56, 0.36), Color(0.45, 0.22, 0.22), {"warm": 0.8})
	_bld("union", "Student Union", Vector2(42, 66), Vector2(26, 16), 8.0, Color(0.52, 0.62, 0.48), Color(0.30, 0.26, 0.40), {"warm": 0.7})
	_bld("rec", "Splashdown Rec Center", Vector2(141, 32), Vector2(18, 40), 9.0, Color(0.34, 0.56, 0.74), Color(0.92, 0.92, 0.95), {"warm": 0.5})
	_bld("greenhouse", "Greenhouse", Vector2(130, -88), Vector2(14, 22), 6.0, Color(0.55, 0.85, 0.75), Color(0.70, 0.95, 0.88), {"glass": true, "warm": 0.3})
	_bld("boathouse", "Boathouse", Vector2(-46, -126), Vector2(18, 12), 7.0, Color(0.55, 0.38, 0.26), Color(0.30, 0.20, 0.18), {"warm": 0.6})
	_bld("shed", "Grounds Shed", Vector2(60, -132), Vector2(26, 9), 6.0, Color(0.36, 0.42, 0.34), Color(0.72, 0.44, 0.18), {"warm": 0.9})
	_bld("mapleton", "Mapleton Hall", Vector2(-118, -24), Vector2(20, 24), 10.0, brick, slate, {"warm": 0.45})
	_bld("paintbox", "Paintbox Studios", Vector2(118, -28), Vector2(20, 20), 8.0, Color(0.78, 0.48, 0.60), Color(0.35, 0.30, 0.55), {"warm": 0.6})
	_bld("observatory", "Stargazer Observatory", Vector2(-138, -118), Vector2(12, 12), 6.0, Color(0.70, 0.70, 0.78), Color(0.85, 0.85, 0.92), {"dome": true, "warm": 0.3})
	_bld("cafe", "Night Owl Cafe", Vector2(-140, 112), Vector2(16, 12), 6.0, Color(0.85, 0.66, 0.40), Color(0.50, 0.25, 0.20), {"warm": 0.9})
	_bld("music", "Tuba Hall", Vector2(140, 112), Vector2(18, 14), 8.0, Color(0.52, 0.44, 0.70), slate, {"warm": 0.6})

	landmarks = [
		{"name": "Bellweather Tower", "pos": Vector2(0, -30)},
		{"name": "Puddlesworth Hall", "pos": Vector2(0, 112)},
		{"name": "Grounds Shed", "pos": Vector2(60, -130)},
	]


# ---------------------------------------------------------------------------
# Water locations (6). Each has >= 2 approaches/exits and respawn pads.
# ---------------------------------------------------------------------------
func _build_waters() -> void:
	waters.append({
		"id": "fountain", "name": "Founders' Fountain", "short": "Fountain",
		"shape": "circle", "center": Vector2(0, 22), "radius": 6.0,
		"surface_y": 0.25, "floor_y": -1.4, "rim_h": 0.55, "rim_t": 0.6,
		"color": Color(1.0, 0.82, 0.25), "icon": "star",
		"exits": [Vector3(0, 0, 13.4), Vector3(0, 0, 30.6), Vector3(8.6, 0, 22), Vector3(-8.6, 0, 22)],
		"pads": [Vector2(0, 2), Vector2(18, 34), Vector2(-18, 34), Vector2(-20, 8), Vector2(20, 8)],
		"jump_points": [Vector2(0, 14.2), Vector2(0, 29.8), Vector2(7.8, 22), Vector2(-7.8, 22)],
	})
	waters.append({
		"id": "pond", "name": "Froggy Pond", "short": "Pond",
		"shape": "ellipse", "center": Vector2(-120, 46), "rx": 11.0, "rz": 8.0,
		"surface_y": -0.35, "floor_y": -2.0, "rim_h": 0.0,
		"color": Color(0.45, 1.0, 0.45), "icon": "leaf",
		"exits": [Vector3(-106.5, 0, 46), Vector3(-116, 0, 35.5), Vector3(-121, 0, 56.5), Vector3(-133.5, 0, 46)],
		"pads": [Vector2(-96, 52), Vector2(-104, 26), Vector2(-112, 70), Vector2(-142, 40)],
		"jump_points": [Vector2(-107.6, 46), Vector2(-115.5, 37), Vector2(-121, 55), Vector2(-132.4, 46)],
	})
	waters.append({
		"id": "pool", "name": "Splashdown Pool", "short": "Pool",
		"shape": "rect", "center": Vector2(112, 32), "size": Vector2(10, 24),
		"surface_y": -0.4, "floor_y": -2.2, "rim_h": 0.0,
		"color": Color(0.30, 0.85, 1.0), "icon": "drop",
		"exits": [Vector3(105.2, 0, 22), Vector3(105.2, 0, 42), Vector3(118.8, 0, 22), Vector3(118.8, 0, 42)],
		"pads": [Vector2(88, 22), Vector2(112, 60), Vector2(98, 6), Vector2(126, 6)],
		"jump_points": [Vector2(106.2, 26), Vector2(106.2, 38), Vector2(117.8, 30), Vector2(112, 19.2), Vector2(112, 44.8)],
	})
	waters.append({
		"id": "quarry", "name": "Old Quarry Lagoon", "short": "Quarry",
		"shape": "ellipse", "center": Vector2(-100, -90), "rx": 13.0, "rz": 10.0,
		"surface_y": -1.0, "floor_y": -3.2, "rim_h": 0.0,
		"color": Color(0.75, 0.55, 1.0), "icon": "diamond",
		"exits": [Vector3(-85.5, 0, -90), Vector3(-100, 0, -78.5), Vector3(-114.5, 0, -90)],
		"pads": [Vector2(-80, -74), Vector2(-104, -66), Vector2(-124, -76), Vector2(-86, -112)],
		"jump_points": [Vector2(-86.4, -90), Vector2(-100, -79.4), Vector2(-113.6, -90), Vector2(-100, -98.0)],
	})
	waters.append({
		"id": "garden", "name": "Lily Basin", "short": "Garden",
		"shape": "rect", "center": Vector2(92, -88), "size": Vector2(14, 7),
		"surface_y": 0.2, "floor_y": -1.2, "rim_h": 0.45, "rim_t": 0.5,
		"color": Color(1.0, 0.50, 0.75), "icon": "flower",
		"exits": [Vector3(92, 0, -93.6), Vector3(92, 0, -82.4), Vector3(100.6, 0, -88), Vector3(83.4, 0, -88)],
		"pads": [Vector2(92, -66), Vector2(70, -96), Vector2(114, -74), Vector2(96, -112)],
		"jump_points": [Vector2(92, -92.8), Vector2(92, -83.2), Vector2(99.8, -88), Vector2(84.2, -88)],
	})
	waters.append({
		"id": "inlet", "name": "Boathouse Inlet", "short": "Inlet",
		"shape": "rect", "center": Vector2(-19, -137), "size": Vector2(18, 18),
		"surface_y": -0.45, "floor_y": -2.0, "rim_h": 0.0,
		"color": Color(1.0, 0.62, 0.30), "icon": "anchor",
		"exits": [Vector3(-19, 0, -126.4), Vector3(-8.4, 0, -134), Vector3(-29.6, 0, -134)],
		"pads": [Vector2(-20, -104), Vector2(6, -116), Vector2(-40, -110), Vector2(10, -138)],
		"jump_points": [Vector2(-19, -127.2), Vector2(-9.2, -136), Vector2(-28.8, -134), Vector2(-14, -142)],
	})


func water_by_id(id: String) -> Dictionary:
	for w in waters:
		if w["id"] == id:
			return w
	return {}


func water_index(id: String) -> int:
	for i in waters.size():
		if waters[i]["id"] == id:
			return i
	return -1


## True if the XZ point lies inside the water footprint (optionally grown by margin).
static func in_water_shape(w: Dictionary, p: Vector2, margin: float = 0.0) -> bool:
	var c: Vector2 = w["center"]
	match String(w["shape"]):
		"circle":
			return p.distance_to(c) <= float(w["radius"]) + margin
		"ellipse":
			var rx: float = float(w["rx"]) + margin
			var rz: float = float(w["rz"]) + margin
			var d := p - c
			return (d.x * d.x) / (rx * rx) + (d.y * d.y) / (rz * rz) <= 1.0
		"rect":
			var s: Vector2 = w["size"] * 0.5 + Vector2(margin, margin)
			return absf(p.x - c.x) <= s.x and absf(p.y - c.y) <= s.y
	return false


# ---------------------------------------------------------------------------
# Roads (carts are fast here) and footpaths
# ---------------------------------------------------------------------------
func _road(pts: Array, w: float = 7.0) -> void:
	roads.append({"pts": PackedVector2Array(pts), "w": w})


func _path(pts: Array, w: float = 3.0, color: Color = Color(0.66, 0.62, 0.56)) -> void:
	paths.append({"pts": PackedVector2Array(pts), "w": w, "color": color})


func _build_roads_and_paths() -> void:
	# College Loop (ring road)
	_road([Vector2(-78, -58), Vector2(78, -58), Vector2(78, 88), Vector2(-78, 88), Vector2(-78, -58)])
	# Library Lane cuts east-west north of the quad
	_road([Vector2(-78, -14), Vector2(78, -14)], 6.5)
	# Shed spur
	_road([Vector2(60, -58), Vector2(60, -122)], 6.5)
	# Boathouse lane
	_road([Vector2(-20, -58), Vector2(-20, -100), Vector2(-34, -112)], 6.0)
	# Rec center lane + parking
	_road([Vector2(78, 66), Vector2(124, 66)], 6.5)
	# Back service road behind dorm row (east-west, connects the two loop corners south)
	_road([Vector2(-78, 88), Vector2(-120, 88), Vector2(-120, 140), Vector2(120, 140), Vector2(120, 88), Vector2(78, 88)], 6.0)
	# Quarry access
	_road([Vector2(-78, -58), Vector2(-110, -58), Vector2(-130, -70)], 6.0)
	# East access to garden/greenhouse
	_road([Vector2(78, -58), Vector2(116, -58), Vector2(140, -70)], 6.0)

	var stone := Color(0.70, 0.66, 0.60)
	var gravel := Color(0.62, 0.56, 0.46)
	var plank := Color(0.55, 0.40, 0.28)
	# Central spine: dorm -> fountain -> chapel arch -> north lawn -> inlet
	_path([Vector2(0, 103), Vector2(0, 31)], 4.0, stone)
	_path([Vector2(0, 13), Vector2(0, -23)], 4.0, stone)
	_path([Vector2(0, -37), Vector2(0, -58), Vector2(-6, -90), Vector2(-19, -122)], 3.2, stone)
	# Fountain diagonals to quad corners
	_path([Vector2(-5, 27), Vector2(-24, 44), Vector2(-25, 56)], 3.0, stone)
	_path([Vector2(5, 27), Vector2(24, 44), Vector2(25, 56)], 3.0, stone)
	_path([Vector2(-5, 17), Vector2(-28, 0), Vector2(-34, -14)], 3.0, stone)
	_path([Vector2(5, 17), Vector2(28, 0), Vector2(34, -14)], 3.0, stone)
	_path([Vector2(-9, 22), Vector2(-36, 22)], 3.0, stone)
	_path([Vector2(9, 22), Vector2(36, 22)], 3.0, stone)
	# Quad perimeter walks along the faces of library / science
	_path([Vector2(-36, -14), Vector2(-36, 54), Vector2(-25, 58), Vector2(-24, 78), Vector2(-14, 90), Vector2(-26, 100)], 3.0, stone)
	_path([Vector2(36, -14), Vector2(36, 54), Vector2(25, 58), Vector2(24, 78), Vector2(14, 90), Vector2(26, 100)], 3.0, stone)
	# Dorm ring walk (connects all four entrances; hedged corners)
	_path([Vector2(-26, 100), Vector2(-26, 124), Vector2(26, 124), Vector2(26, 100), Vector2(-26, 100)], 3.0, stone)
	_path([Vector2(0, 124), Vector2(0, 137)], 3.0, stone)
	_path([Vector2(-26, 112), Vector2(-60, 112), Vector2(-78, 98)], 3.0, stone)
	_path([Vector2(26, 112), Vector2(60, 112), Vector2(78, 98)], 3.0, stone)
	# West: woods trails to Froggy Pond
	_path([Vector2(-78, 46), Vector2(-106, 46)], 3.0, gravel)
	_path([Vector2(-78, 4), Vector2(-94, 4), Vector2(-114, 36)], 2.6, gravel)
	_path([Vector2(-78, 80), Vector2(-102, 74), Vector2(-120, 57)], 2.6, gravel)
	_path([Vector2(-133, 46), Vector2(-146, 30), Vector2(-146, -6)], 2.4, gravel)
	# Library back walk and west lawn
	_path([Vector2(-64, -14), Vector2(-64, 56), Vector2(-58, 82)], 2.8, stone)
	# East: pool gates
	_path([Vector2(78, 32), Vector2(100, 32)], 3.0, stone)
	_path([Vector2(112, 50), Vector2(112, 66)], 3.0, stone)
	_path([Vector2(78, -14), Vector2(98, -4), Vector2(112, 8), Vector2(112, 14)], 3.0, stone)
	_path([Vector2(64, -14), Vector2(64, 56), Vector2(58, 82)], 2.8, stone)
	# North-west: quarry approaches
	_path([Vector2(-78, -58), Vector2(-84, -72), Vector2(-86, -88)], 3.0, gravel)
	_path([Vector2(-100, -58), Vector2(-100, -79)], 3.0, gravel)
	_path([Vector2(-114, -90), Vector2(-130, -96), Vector2(-136, -108)], 2.6, gravel)
	_path([Vector2(-100, -100), Vector2(-90, -112), Vector2(-60, -118), Vector2(-46, -116)], 2.6, gravel)
	_path([Vector2(-118, -36), Vector2(-118, -58)], 2.6, gravel)
	# North-east: Lily Basin garden
	_path([Vector2(92, -58), Vector2(92, -82)], 3.0, stone)
	_path([Vector2(92, -94), Vector2(92, -112), Vector2(76, -120), Vector2(66, -124)], 3.0, stone)
	_path([Vector2(70, -88), Vector2(84, -88)], 3.0, stone)
	_path([Vector2(100, -88), Vector2(122, -88)], 3.0, stone)
	_path([Vector2(118, -38), Vector2(118, -58)], 2.6, stone)
	# North: inlet shores and dock
	_path([Vector2(-20, -100), Vector2(-19, -126)], 3.0, gravel)
	_path([Vector2(-8, -126), Vector2(-8, -134), Vector2(4, -120), Vector2(20, -100), Vector2(40, -80), Vector2(60, -70)], 2.6, gravel)
	_path([Vector2(-30, -134), Vector2(-36, -120)], 2.6, plank)
	_path([Vector2(20, -58), Vector2(20, -100)], 2.6, gravel)
	# Library Lane crossings are part of the spine; diagonal short-cut NE/NW lawns
	_path([Vector2(-34, -14), Vector2(-54, -40), Vector2(-60, -58)], 2.6, gravel)
	_path([Vector2(34, -14), Vector2(54, -40), Vector2(60, -58)], 2.6, gravel)

	plazas.append({"shape": "circle", "center": Vector2(0, 22), "radius": 14.0, "color": stone})
	plazas.append({"shape": "rect", "center": Vector2(0, 96), "size": Vector2(18, 12), "color": stone})
	plazas.append({"shape": "rect", "center": Vector2(112, 32), "size": Vector2(26, 38), "color": Color(0.80, 0.82, 0.86)})
	plazas.append({"shape": "rect", "center": Vector2(92, -88), "size": Vector2(34, 30), "color": Color(0.58, 0.62, 0.52)})
	plazas.append({"shape": "rect", "center": Vector2(60, -122), "size": Vector2(30, 14), "color": Color(0.40, 0.40, 0.42)})
	plazas.append({"shape": "rect", "center": Vector2(-19, -122), "size": Vector2(24, 7), "color": plank})
	plazas.append({"shape": "rect", "center": Vector2(0, -30), "size": Vector2(26, 22), "color": stone})


func is_on_road(p: Vector2, margin: float = 0.0) -> bool:
	for r in roads:
		var pts: PackedVector2Array = r["pts"]
		var hw: float = float(r["w"]) * 0.5 + margin
		for i in pts.size() - 1:
			if _dist_to_segment(p, pts[i], pts[i + 1]) <= hw:
				return true
	return false


func is_on_path(p: Vector2, margin: float = 0.0) -> bool:
	for r in paths:
		var pts: PackedVector2Array = r["pts"]
		var hw: float = float(r["w"]) * 0.5 + margin
		for i in pts.size() - 1:
			if _dist_to_segment(p, pts[i], pts[i + 1]) <= hw:
				return true
	return false


static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


# ---------------------------------------------------------------------------
# Barriers: walls (hop-able), hedges, fences, bollards (cart-only)
# ---------------------------------------------------------------------------
func _wall(a: Vector2, b: Vector2, h: float = 0.6, t: float = 0.5) -> void:
	walls.append({"a": a, "b": b, "h": h, "t": t})


func _hedge(a: Vector2, b: Vector2, h: float = 1.6, t: float = 1.1) -> void:
	hedges.append({"a": a, "b": b, "h": h, "t": t})


func _fence(a: Vector2, b: Vector2, h: float = 1.6, kind: String = "iron") -> void:
	fences.append({"a": a, "b": b, "h": h, "kind": kind})


func _bollards(a: Vector2, b: Vector2) -> void:
	cart_blockers.append({"a": a, "b": b})


func _build_boundaries_and_barriers() -> void:
	var b := BOUNDS
	# Outer boundary: tall hedge on west/east/south, lake rail on north.
	_hedge(Vector2(b.position.x, b.position.y + 4), Vector2(b.position.x, b.end.y), 2.6, 2.0)
	_hedge(Vector2(b.end.x, b.position.y + 4), Vector2(b.end.x, b.end.y), 2.6, 2.0)
	_hedge(Vector2(b.position.x, b.end.y), Vector2(b.end.x, b.end.y), 2.6, 2.0)
	# Lake shore rail (north) with the inlet opening x -28..-10; the inlet itself is
	# closed toward the lake by a buoy line so nobody can swim out.
	_fence(Vector2(b.position.x, -146.5), Vector2(-28, -146.5), 1.3, "rail")
	_fence(Vector2(-10, -146.5), Vector2(b.end.x, -146.5), 1.3, "rail")
	_fence(Vector2(-28, -146.5), Vector2(-10, -146.5), 1.3, "buoy")

	# Pool deck fence with three gates (W, N, S); gates carry bollards.
	_fence(Vector2(99, 14), Vector2(110.5, 14))
	_fence(Vector2(113.5, 14), Vector2(125, 14))
	_fence(Vector2(125, 14), Vector2(125, 30.5))
	_fence(Vector2(125, 33.5), Vector2(125, 50))
	_fence(Vector2(99, 50), Vector2(110.5, 50))
	_fence(Vector2(113.5, 50), Vector2(125, 50))
	_fence(Vector2(99, 14), Vector2(99, 30.5))
	_fence(Vector2(99, 33.5), Vector2(99, 50))
	_bollards(Vector2(110.5, 14), Vector2(113.5, 14))
	_bollards(Vector2(110.5, 50), Vector2(113.5, 50))
	_bollards(Vector2(99, 30.5), Vector2(99, 33.5))
	_bollards(Vector2(125, 30.5), Vector2(125, 33.5))

	# Lily Basin garden: square hedge ring with four openings.
	var g := Vector2(92, -88)
	_hedge(g + Vector2(-17, -15), g + Vector2(-2, -15))
	_hedge(g + Vector2(2, -15), g + Vector2(17, -15))
	_hedge(g + Vector2(-17, 15), g + Vector2(-2, 15))
	_hedge(g + Vector2(2, 15), g + Vector2(17, 15))
	_hedge(g + Vector2(-17, -15), g + Vector2(-17, -2))
	_hedge(g + Vector2(-17, 2), g + Vector2(-17, 15))
	_hedge(g + Vector2(17, -15), g + Vector2(17, -2))
	_hedge(g + Vector2(17, 2), g + Vector2(17, 15))
	# Inner low walls create two hop shortcuts near the basin
	_wall(g + Vector2(-11, -8), g + Vector2(-11, 8), 0.6)
	_wall(g + Vector2(11, -8), g + Vector2(11, 8), 0.6)
	for side in [Vector2(-2, -15), Vector2(-2, 15), Vector2(-17, -2), Vector2(17, -2)]:
		var a: Vector2 = g + side
		if side.y == -15 or side.y == 15:
			_bollards(a, a + Vector2(4, 0))
		else:
			_bollards(a, a + Vector2(0, 4))

	# Woods edge: split-rail fence keeps carts out of the pond woods; three foot gaps
	_fence(Vector2(-92, -6), Vector2(-92, 1), 1.0, "split")
	_fence(Vector2(-92, 7), Vector2(-92, 43), 1.0, "split")
	_fence(Vector2(-92, 49), Vector2(-92, 74), 1.0, "split")
	_fence(Vector2(-92, 80), Vector2(-92, 84), 1.0, "split")
	_bollards(Vector2(-92, 1), Vector2(-92, 7))
	_bollards(Vector2(-92, 43), Vector2(-92, 49))
	_bollards(Vector2(-92, 74), Vector2(-92, 80))

	# Quad: bollards wherever footpaths meet the roads around the quad
	_bollards(Vector2(-8, -10.5), Vector2(8, -10.5))
	_bollards(Vector2(-6, 84.5), Vector2(6, 84.5))
	# Dorm grounds are a cart-free pedestrian zone (bollards on every side)
	_bollards(Vector2(-74.4, 91.8), Vector2(74.4, 91.8))
	_bollards(Vector2(-74.4, 136.6), Vector2(74.4, 136.6))
	_bollards(Vector2(-74.4, 91.8), Vector2(-74.4, 136.6))
	_bollards(Vector2(74.4, 91.8), Vector2(74.4, 136.6))
	# Quad low walls (hop shortcuts), carts cannot cross onto the lawns
	_wall(Vector2(-39, -10), Vector2(-39, 1), 0.6)
	_wall(Vector2(39, -10), Vector2(39, 1), 0.6)
	_wall(Vector2(-30, -10.5), Vector2(-8, -10.5), 0.6)
	_wall(Vector2(8, -10.5), Vector2(30, -10.5), 0.6)
	_wall(Vector2(-30, 84.5), Vector2(-6, 84.5), 0.6)
	_wall(Vector2(6, 84.5), Vector2(30, 84.5), 0.6)
	_wall(Vector2(-60, 84.5), Vector2(-40, 84.5), 0.6)
	_wall(Vector2(40, 84.5), Vector2(60, 84.5), 0.6)
	_wall(Vector2(-74.5, 0), Vector2(-74.5, 30), 0.6)
	_wall(Vector2(74.5, 0), Vector2(74.5, 30), 0.6)
	_wall(Vector2(-74.5, 52), Vector2(-74.5, 82), 0.6)
	_wall(Vector2(74.5, 38), Vector2(74.5, 60), 0.6)
	_wall(Vector2(-60, -54.5), Vector2(-26, -54.5), 0.6)
	_wall(Vector2(26, -54.5), Vector2(54, -54.5), 0.6)

	# Quarry rim: boulders ring with gaps E, S(road side), W; a raised ledge to the north.
	var q := Vector2(-100, -90)
	for i in 22:
		var ang := TAU * float(i) / 22.0
		var gap_e := absf(wrapf(ang - 0.0, -PI, PI)) < 0.32
		var gap_s := absf(wrapf(ang - PI * 0.5, -PI, PI)) < 0.30
		var gap_w := absf(wrapf(ang - PI, -PI, PI)) < 0.30
		var gap_n := absf(wrapf(ang + PI * 0.5, -PI, PI)) < 0.45
		if gap_e or gap_s or gap_w or gap_n:
			continue
		var p := q + Vector2(cos(ang) * 17.0, sin(ang) * 14.0)
		rocks.append({"pos": Vector3(p.x, 0, p.y), "size": Vector3(4.2, 1.8 + 0.6 * float(i % 3), 3.6), "rot": ang})
	# Carts cannot enter the quarry ring
	_bollards(q + Vector2(17, -4), q + Vector2(17, 4))
	_bollards(q + Vector2(-5, 14), q + Vector2(5, 14))
	_bollards(q + Vector2(-17, -4), q + Vector2(-17, 4))
	_bollards(q + Vector2(-7, -14.5), q + Vector2(7, -14.5))
	# North ledge platform (jump spot), with a ramp from the west
	platforms.append({"center": Vector3(-100, 2.2, -104.5), "size": Vector3(9, 0.6, 4.5), "color": Color(0.55, 0.52, 0.56)})
	ramps.append({"from": Vector3(-114, 0, -104.5), "to": Vector3(-104.5, 2.5, -104.5), "w": 3.0, "color": Color(0.55, 0.52, 0.56)})
	_bollards(Vector2(-116, -103), Vector2(-116, -106))

	# Inlet dock (walkable, flush) — runs out over the water on the east side
	platforms.append({"center": Vector3(-13.5, -0.05, -136), "size": Vector3(3.0, 0.3, 16), "color": Color(0.55, 0.40, 0.28), "dock": true})
	# Inlet shore is cart-free: bollards along the boardwalk and the east shore
	_bollards(Vector2(-34, -124.5), Vector2(-5, -124.5))
	_bollards(Vector2(-5, -124.5), Vector2(-5, -146))
	_bollards(Vector2(-34, -124.5), Vector2(-34, -146))

	# Chapel arch: the tower base is open (pedestrian tunnel); carts blocked by bollards
	_bollards(Vector2(-3, -21.5), Vector2(3, -21.5))
	_bollards(Vector2(-3, -38.5), Vector2(3, -38.5))

	# Dorm corner fins: hedges angled out from each corner (beyond the ring walk)
	# so nobody can watch two entrances from one comfortable spot.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var corner := Vector2(22.0 * sx, 112.0 + 9.0 * sz)
			var out := Vector2(sx, sz).normalized()
			_hedge(corner + out * 7.5, corner + out * 16.0, 1.8, 1.2)


func _build_dorm() -> void:
	# Each entrance: door centre on the wall face, outward normal, finish box.
	dorm_doors = [
		{"id": "north", "name": "Front Door", "pos": Vector2(0, 103), "normal": Vector2(0, -1)},
		{"id": "west", "name": "West Door", "pos": Vector2(-22, 112), "normal": Vector2(-1, 0)},
		{"id": "east", "name": "East Door", "pos": Vector2(22, 112), "normal": Vector2(1, 0)},
		{"id": "south", "name": "Back Door", "pos": Vector2(0, 121), "normal": Vector2(0, 1)},
	]
	dorm_pads = [Vector2(0, 92), Vector2(-10, 94), Vector2(10, 94), Vector2(0, 132), Vector2(-34, 110), Vector2(34, 110)]


## V5 runner spawns (outdoors on the dorm's front lawn).  V6 replaces them
## with pads inside every dorm (_build_dorm_districts); they stay here
## because the V5 tree scatter keeps its distance from them.
func _build_spawns() -> void:
	runner_spawns = [Vector2(-6, 96), Vector2(-2, 98), Vector2(2, 98), Vector2(6, 96), Vector2(-4, 92), Vector2(4, 92)]
	patrol_spawns = [Vector2(50, -125), Vector2(70, -125)]
	cart_spawns = [
		{"pos": Vector2(54, -122), "yaw": 0.0},
		{"pos": Vector2(66, -122), "yaw": 0.0},
	]
	gadget_spots = [
		Vector2(-66, 40), Vector2(10, -46), Vector2(-60, 52), Vector2(-104, 14),
		Vector2(122, 74), Vector2(104, -98), Vector2(-118, -104), Vector2(-34, -136),
		Vector2(68, 0),
	]


# ---------------------------------------------------------------------------
# Trees, lamps, benches, props (deterministic scatter)
# ---------------------------------------------------------------------------
func _blocked_for_scatter(p: Vector2, clearance: float) -> bool:
	if not BOUNDS.grow(-4.0).has_point(p):
		return true
	if is_on_road(p, clearance + 0.5) or is_on_path(p, clearance):
		return true
	for w in waters:
		if in_water_shape(w, p, clearance + 2.5):
			return true
	for bd in buildings:
		var hs: Vector2 = bd["size"] * 0.5 + Vector2(clearance + 1.5, clearance + 1.5)
		var bp: Vector2 = bd["pos"]
		if absf(p.x - bp.x) < hs.x and absf(p.y - bp.y) < hs.y:
			return true
	for pl in plazas:
		if pl["shape"] == "circle":
			if p.distance_to(pl["center"]) < float(pl["radius"]) + clearance:
				return true
		else:
			var hs2: Vector2 = pl["size"] * 0.5 + Vector2(clearance, clearance)
			var c: Vector2 = pl["center"]
			if absf(p.x - c.x) < hs2.x and absf(p.y - c.y) < hs2.y:
				return true
	for lst in [walls, hedges, fences]:
		for s in lst:
			if _dist_to_segment(p, s["a"], s["b"]) < clearance + 1.0:
				return true
	for r in rocks:
		var rp: Vector3 = r["pos"]
		if p.distance_to(Vector2(rp.x, rp.z)) < clearance + 3.0:
			return true
	for sp in runner_spawns + patrol_spawns + gadget_spots:
		if p.distance_to(sp) < clearance + 2.0:
			return true
	for cs in cart_spawns:
		if p.distance_to(cs["pos"]) < clearance + 3.0:
			return true
	for w in waters:
		for pad in w["pads"]:
			if p.distance_to(pad) < clearance + 2.0:
				return true
		for e in w["exits"]:
			if p.distance_to(Vector2(e.x, e.z)) < clearance + 2.0:
				return true
	for d in dorm_doors:
		if p.distance_to(d["pos"]) < clearance + 4.0:
			return true
	for t in trees:
		if p.distance_to(t["pos"]) < clearance + float(t["r"]) + 1.6:
			return true
	return false


func _build_trees_and_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3003
	# Dense woods around Froggy Pond (west), the quarry (north-west) and lake shore.
	var groves := [
		{"rect": Rect2(-156, -8, 62, 92), "count": 95, "kind": "pine"},
		{"rect": Rect2(-156, -146, 46, 40), "count": 18, "kind": "pine"},
		{"rect": Rect2(-80, -146, 50, 20), "count": 12, "kind": "round"},
		{"rect": Rect2(100, -146, 56, 30), "count": 14, "kind": "round"},
		{"rect": Rect2(130, 74, 26, 72), "count": 16, "kind": "round"},
		{"rect": Rect2(-156, 90, 30, 56), "count": 12, "kind": "round"},
	]
	for gr in groves:
		var rect: Rect2 = gr["rect"]
		var placed := 0
		var tries := 0
		while placed < int(gr["count"]) and tries < 2000:
			tries += 1
			var p := Vector2(rng.randf_range(rect.position.x, rect.end.x), rng.randf_range(rect.position.y, rect.end.y))
			var r := rng.randf_range(0.9, 1.4)
			if _blocked_for_scatter(p, r + 0.8):
				continue
			trees.append({"pos": p, "r": r, "h": rng.randf_range(6.0, 9.5), "kind": gr["kind"], "tint": rng.randf()})
			placed += 1
	# Avenue trees along the loop road and lawns (spaced, leave carts room).
	var avenue_pts: Array[Vector2] = []
	for x in range(-66, 67, 12):
		avenue_pts.append(Vector2(x, -63.5))
		avenue_pts.append(Vector2(x, 93.5) if absf(x) > 12 else Vector2(x, 999))
	for z in range(-46, 85, 12):
		avenue_pts.append(Vector2(-84, z))
		avenue_pts.append(Vector2(84, z))
	for x in range(-24, 25, 12):
		avenue_pts.append(Vector2(x, -8))
	for p in avenue_pts:
		if p.y > 900:
			continue
		if not _blocked_for_scatter(p, 1.2):
			trees.append({"pos": p, "r": 1.1, "h": rng.randf_range(6.5, 8.5), "kind": "round", "tint": rng.randf()})
	# Lawn clusters inside the quad and around buildings
	var lawn_rects := [Rect2(-34, 30, 26, 26), Rect2(8, 30, 26, 26), Rect2(-34, -8, 26, 20), Rect2(8, -8, 26, 20),
		Rect2(-74, -50, 40, 30), Rect2(34, -50, 40, 30), Rect2(90, -50, 50, 40), Rect2(-74, 96, 40, 44), Rect2(34, 96, 40, 44),
		Rect2(84, 74, 40, 12), Rect2(-60, -120, 30, 50), Rect2(20, -110, 30, 40)]
	for lr in lawn_rects:
		var n := 0
		var tries2 := 0
		while n < 5 and tries2 < 300:
			tries2 += 1
			var p2 := Vector2(rng.randf_range(lr.position.x, lr.end.x), rng.randf_range(lr.position.y, lr.end.y))
			if _blocked_for_scatter(p2, 2.0):
				continue
			trees.append({"pos": p2, "r": rng.randf_range(0.9, 1.3), "h": rng.randf_range(5.5, 8.0), "kind": "round" if rng.randf() < 0.7 else "pine", "tint": rng.randf()})
			n += 1

	# Lamps every ~16 m along paths (fake light pools keep this cheap on mobile)
	for pth in paths:
		var pts: PackedVector2Array = pth["pts"]
		var acc := 8.0
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var seg := a.distance_to(b)
			var dir := (b - a).normalized()
			var side := Vector2(-dir.y, dir.x) * (float(pth["w"]) * 0.5 + 0.6)
			var s := acc
			while s < seg:
				var lp := a + dir * s + side
				var ok := true
				for other in lamps:
					if other.distance_to(lp) < 10.0:
						ok = false
						break
				if ok:
					lamps.append(lp)
				s += 16.0
			acc = s - seg
	# Benches near lamps on the quad
	var bench_spots := [Vector2(-12, 34), Vector2(12, 34), Vector2(-12, 10), Vector2(12, 10), Vector2(-40, 40), Vector2(40, 40),
		Vector2(-110, 56), Vector2(84, -78), Vector2(100, -98), Vector2(-24, -118), Vector2(-90, -76), Vector2(104, 54)]
	for bp2 in bench_spots:
		benches.append({"pos": bp2, "rot": rng.randf_range(-0.3, 0.3)})
	# Bins / planters / bikes as small props (non-colliding decor except planters)
	props.append({"kind": "bike_rack", "pos": Vector2(-14, 100), "rot": 0.0})
	props.append({"kind": "bike_rack", "pos": Vector2(14, 100), "rot": 0.0})
	props.append({"kind": "noticeboard", "pos": Vector2(6, 90), "rot": 0.0})
	props.append({"kind": "lifeguard", "pos": Vector2(121.5, 32), "rot": -PI * 0.5})
	props.append({"kind": "gazebo", "pos": Vector2(82, -98), "rot": 0.0})
	props.append({"kind": "canoe", "pos": Vector2(-36, -132), "rot": 0.4})
	props.append({"kind": "frog", "pos": Vector2(-108, 52), "rot": 1.0})


# ---------------------------------------------------------------------------
# V6: the dorm districts (CampusDorms)
# ---------------------------------------------------------------------------


func _build_dorm_districts() -> void:
	# Puddlesworth's V5 box gives way to the three dorm shells
	var keep: Array[Dictionary] = []
	for b in buildings:
		if String(b["id"]) != "dorm":
			keep.append(b)
	buildings = keep
	dorm_doors.clear()
	dorm_pads.clear()
	runner_spawns.clear()
	for d in CampusDorms.DORMS:
		var id := String(d["id"])
		var g := CampusDorms.geometry(id)
		buildings.append({"id": "dorm_" + id, "name": d["name"], "pos": d["pos"], "size": d["size"], "h": d["h"],
			"wall": d["wall"], "roof": d["roof"], "rot": 0.0, "dorm": true, "dorm_id": id, "warm": d["warm"]})
		var e: Dictionary = d.duplicate()
		e["geo"] = g
		dorms.append(e)
		dorm_doors.append_array(g["doors"])
		dorm_pads.append_array(g["respawn"])
		for pd in g["pads"]:
			runner_spawns.append(pd["pos"])
		for cl in g["cart_lines"]:
			# a raised threshold carts can't cross: no bollards drawn in a doorway
			cart_blockers.append({"a": cl[0], "b": cl[1], "hidden": true})
	# nothing V5 put in a district may now stand inside a dorm or in a
	# doorway (V6 additions below are placed by hand and checked by tests)
	trees.assign(trees.filter(func(t: Dictionary) -> bool: return not _district_conflict(t["pos"], 1.6)))
	lamps.assign(lamps.filter(func(l: Vector2) -> bool: return not _district_conflict(l, 0.4)))
	benches.assign(benches.filter(func(b: Dictionary) -> bool: return not _district_conflict(b["pos"], 0.9)))
	props.assign(props.filter(func(pr: Dictionary) -> bool: return not _district_conflict(pr["pos"], 0.8)))
	landmarks.append({"name": "Lanternfield House", "pos": Vector2(-96, 114)})
	landmarks.append({"name": "Moonpenny Lodge", "pos": Vector2(96, 113)})
	# a third Night Watch spawn at the shed (V5 put two of three on one spot)
	patrol_spawns.append(Vector2(60, -125))
	var stone := Color(0.70, 0.66, 0.60)
	# Puddlesworth Hall: paved aprons at its three doors
	plazas.append({"shape": "rect", "center": Vector2(0, 102.25), "size": Vector2(8, 1.5), "color": stone})
	plazas.append({"shape": "rect", "center": Vector2(-23.6, 108), "size": Vector2(3.2, 5.6), "color": stone})
	plazas.append({"shape": "rect", "center": Vector2(23.6, 108), "size": Vector2(3.2, 5.6), "color": stone})
	# the west and east yards are cart-free like Puddlesworth's grounds
	for sx in [-1.0, 1.0]:
		_bollards(Vector2(116.4 * sx, 91.8), Vector2(74.4 * sx, 91.8))
		_bollards(Vector2(116.4 * sx, 91.8), Vector2(116.4 * sx, 136.6))
		_bollards(Vector2(116.4 * sx, 136.6), Vector2(74.4 * sx, 136.6))
	# Lanternfield House (west): forecourt, three approaches, lamps, benches
	plazas.append({"shape": "rect", "center": Vector2(-96, 98.25), "size": Vector2(14, 11.5), "color": stone})
	_path([Vector2(-89, 98), Vector2(-78, 98)], 3.0, stone)
	_path([Vector2(-110.5, 109), Vector2(-117, 109)], 2.6, stone)
	_path([Vector2(-81.5, 109), Vector2(-74.1, 101)], 2.6, stone)
	# Moonpenny Lodge (east)
	plazas.append({"shape": "rect", "center": Vector2(96, 96), "size": Vector2(14, 8), "color": stone})
	_path([Vector2(89, 97), Vector2(78, 98)], 3.0, stone)
	_path([Vector2(83.5, 105), Vector2(74.1, 101)], 2.6, stone)
	_path([Vector2(108.5, 105), Vector2(117, 105)], 2.6, stone)
	for lp in [Vector2(-104.2, 93.4), Vector2(-87.8, 93.4), Vector2(-115.2, 111.6), Vector2(-76.4, 106.3),
			Vector2(87.8, 92.9), Vector2(104.2, 92.9), Vector2(113.2, 107.0), Vector2(80.0, 100.6)]:
		lamps.append(lp)
	for bp in [[Vector2(-101.5, 101.8), 0.0], [Vector2(-90.5, 101.8), 0.0], [Vector2(91.6, 98.2), 0.0], [Vector2(100.4, 98.2), 0.0]]:
		benches.append({"pos": bp[0], "rot": bp[1]})
	props.append({"kind": "bike_rack", "pos": Vector2(-106.5, 102.4), "rot": 0.0})
	props.append({"kind": "bike_rack", "pos": Vector2(86.0, 94.8), "rot": 0.0})
	# monument name signs at each yard's forecourt (small colliders)
	solids.append({"pos": Vector2(-105.8, 94.2), "size": Vector3(2.8, 1.25, 0.55), "rot": 0.0, "kind": "dorm_sign", "dorm": "lanternfield"})
	solids.append({"pos": Vector2(86.0, 93.8), "size": Vector3(2.8, 1.25, 0.55), "rot": 0.0, "kind": "dorm_sign", "dorm": "moonpenny"})
	# a few yard trees, placed by hand (colliders like every layout tree)
	for tp in [[Vector2(-113.5, 97.0), "round"], [Vector2(-79.5, 94.0), "round"], [Vector2(-104.0, 130.5), "round"],
			[Vector2(-89.5, 131.0), "pine"], [Vector2(-113.5, 121.0), "round"],
			[Vector2(80.5, 94.5), "round"], [Vector2(113.0, 97.0), "round"], [Vector2(89.5, 131.0), "round"],
			[Vector2(103.0, 131.5), "pine"], [Vector2(112.5, 121.0), "round"]]:
		var tpos: Vector2 = tp[0]
		trees.append({"pos": tpos, "r": 1.1, "h": 7.0 + fposmod(tpos.x * 0.37 + tpos.y * 0.11, 1.5), "kind": tp[1], "tint": fposmod(tpos.x * 0.13 + tpos.y * 0.07, 1.0)})


## True when p (with clearance r) collides with V6 dorm geometry: a dorm
## footprint, a door's approach or inside, a pad.  (Only V6 additions are
## checked, so V5 things outside the dorms never move.)
func _district_conflict(p: Vector2, r: float) -> bool:
	if CampusDorms.district_of(p) == "":
		return false
	for d in dorms:
		var g: Dictionary = d["geo"]
		if (g["footprint"] as Rect2).grow(r + 0.2).has_point(p):
			return true
		for dr in g["doors"]:
			if p.distance_to(dr["approach"]) < r + 2.5 or p.distance_to(dr["pos"]) < r + 2.0:
				return true
	return false


## The dorm entry by id ({} if unknown): the definition plus "geo".
func dorm(id: String) -> Dictionary:
	for d in dorms:
		if String(d["id"]) == id:
			return d
	return {}


## Tonight's home doors (all doors of that dorm).
func home_doors(id: String) -> Array:
	var d := dorm(id)
	return (d["geo"] as Dictionary)["doors"] if not d.is_empty() else []


func dorm_center(id: String) -> Vector2:
	var d := dorm(id)
	return d["pos"] if not d.is_empty() else Vector2(0, 112)


## Candidate places for the round's gold coins (V6): on runner routes (the
## footpaths and walks), away from doors, waters and gadget spots.  The host
## picks a few per round (RulesLogic.pick_coins); test_dorms checks every one
## is reachable on foot from every dorm and clear of the places runners
## must use.
func _build_coin_spots() -> void:
	coin_spots = [
		Vector2(0, 70), Vector2(-24, 44), Vector2(24, 44), Vector2(-30, 3), Vector2(30, 3),
		Vector2(0, -5), Vector2(0, -48), Vector2(-36, 30), Vector2(36, 30), Vector2(-64, 20),
		Vector2(64, 20), Vector2(-88, 46), Vector2(-84, 4), Vector2(-90, 77), Vector2(90, 32),
		Vector2(88, -9), Vector2(-54, -40), Vector2(54, -40), Vector2(20, -80), Vector2(-6, -90),
		Vector2(118, -47), Vector2(40, -80), Vector2(-75, -115), Vector2(-50, 112), Vector2(50, 112),
		Vector2(-24.5, 70), Vector2(24.5, 70), Vector2(-118, -47), Vector2(-146, 12), Vector2(116, -88),
	]
