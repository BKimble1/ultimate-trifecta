class_name CampusLayout
extends RefCounted
## The campus, described as data: the reference campus's measured layer data
## (CampusData, game/data/campus/*.json; docs/campus/DATA_SCHEMA.md) turned
## into the gameplay description every system reads.  Visual meshes,
## collision, bot navigation, route analysis, spawns and the maps are all
## generated from this one description so they cannot drift.
## Coordinates: metres, +X east, +Z south (north is -Z). Ground is y = 0.
##
## Waters: the round's objective pool comes first (indices 0..5, in the order
## of the gameplay layer's "objective_pool"; the rules mark three of them per
## round from the curated route table), then every other water (decorative:
## you can fall in, it is never a target).  Each water is one or more
## polygons (or a circle) with a surface and a floor; shore exits, jump
## points and respawn pads are derived from its outline and the open ground
## around it, deterministically, so every client computes the same ones.
##
## Start dorms come from CampusDorms (gameplay layer "start_dorm" items).

## The play area's bounding box (the play boundary polygon lies inside it;
## outside it everything is background).  Fixed: the network, the maps and
## the out-of-bounds rule rely on it, and test_campus_layout checks the
## gameplay data against it.
const BOUNDS := Rect2(-720.0, -560.0, 1190.0, 1000.0)
const CAMPUS_NAME := "Campus"
## Spatial hash cell for the per-tick queries (roads, water).
const CELL := 16.0

var data: CampusData
var play_boundary := PackedVector2Array()

var buildings: Array[Dictionary] = []
var waters: Array[Dictionary] = []
var roads: Array[Dictionary] = []
var paths: Array[Dictionary] = []
var plazas: Array[Dictionary] = []     # paved areas (plaza/pavement/court): {"poly", "kind"}
var areas: Array[Dictionary] = []      # every area polygon: {"id", "kind", "poly"}
var walls: Array[Dictionary] = []      # low walls: runners hop, carts blocked
var hedges: Array[Dictionary] = []     # tall hedges: block everyone and sight
var fences: Array[Dictionary] = []     # fences/rails: block everyone, see-through
var cart_blockers: Array[Dictionary] = []  # bollard lines: block carts only
var trees: Array[Dictionary] = []
var rocks: Array[Dictionary] = []
var platforms: Array[Dictionary] = []  # raised walkable boxes (decks, bridges)
var ramps: Array[Dictionary] = []      # walkable inclines (character colliders)
var lamps: Array[Vector2] = []
var benches: Array[Dictionary] = []
var props: Array[Dictionary] = []
var solids: Array[Dictionary] = []
var dorm_doors: Array[Dictionary] = []
var dorm_pads: Array[Vector2] = []
var runner_spawns: Array[Vector2] = []
var patrol_spawns: Array[Vector2] = []
var cart_spawns: Array[Dictionary] = []
var gadget_spots: Array[Vector2] = []
var coin_spots: Array[Vector2] = []
var landmarks: Array[Dictionary] = []
var dorms: Array[Dictionary] = []
## kept for API compatibility (the fictional campus's V5 build); always false
var legacy := false

var _road_cells: Dictionary = {}       # Vector2i -> [[a, b, half_w], ...] (roads + lot aisles)
var _lot_cells: Dictionary = {}        # Vector2i -> [poly index]
var _lots: Array[PackedVector2Array] = []
var _path_cells: Dictionary = {}
var _water_cells: Dictionary = {}      # Vector2i -> [water index]
var _bld_cells: Dictionary = {}        # Vector2i -> [building index]

static var _shared: CampusLayout
static var _round_data: CampusLayout


static func shared() -> CampusLayout:
	if _shared == null:
		_shared = CampusLayout.new()
	return _shared


## Kept for API compatibility: there is one campus.
static func legacy_shared() -> CampusLayout:
	return shared()


## The round-configuration data (waters, spawns, coins).  The full layout is
## cheap to describe (meshes come later), so this is the shared layout.
static func round_data() -> CampusLayout:
	if _round_data == null:
		_round_data = shared()
	return _round_data


static func reset_shared() -> void:
	_shared = null
	_round_data = null
	CampusData.reset_shared()


func _init(p_data: CampusData = null, _unused: bool = false) -> void:
	data = p_data if p_data != null else CampusData.shared()
	_build_gameplay_frame()
	_build_buildings()
	_build_waters()
	_build_roads_and_paths()
	_build_areas()
	_build_barriers()
	_build_vegetation_and_props()
	_build_dorms()
	_build_water_points()
	_index()


# ---------------------------------------------------------------------------
# Gameplay frame: boundary, spawns, spots (gameplay layer)
# ---------------------------------------------------------------------------
func _gp(kind: String) -> Array:
	var out: Array = []
	for it in data.items("gameplay"):
		if String(it.get("kind", "")) == kind:
			out.append(it)
	return out


func _build_gameplay_frame() -> void:
	for it in _gp("boundary"):
		play_boundary = it.get("polygon", PackedVector2Array())
	if play_boundary.is_empty():
		var b := BOUNDS.grow(-4.0)
		play_boundary = PackedVector2Array([b.position, Vector2(b.end.x, b.position.y), b.end, Vector2(b.position.x, b.end.y)])
	for it in _gp("patrol_spawns"):
		for p in it.get("pts", []):
			patrol_spawns.append(_v2(p))
	for it in _gp("cart_spawns"):
		for p in it.get("spots", []):
			cart_spawns.append({"pos": _v2(p[0]), "yaw": deg_to_rad(float(p[1]))})
	for it in _gp("gadget_spots"):
		for p in it.get("pts", []):
			gadget_spots.append(_v2(p))
	for it in _gp("coin_spots"):
		for p in it.get("pts", []):
			coin_spots.append(_v2(p))
	for it in _gp("landmark_label"):
		landmarks.append({"name": String(it.get("label", "")), "pos": _v2(it.get("p", [0, 0]))})


static func _v2(p: Variant) -> Vector2:
	if p is Vector2:
		return p
	if p is Array and (p as Array).size() >= 2:
		return Vector2(float(p[0]), float(p[1]))
	return Vector2.ZERO


func in_play(p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p, play_boundary)


# ---------------------------------------------------------------------------
# Buildings
# ---------------------------------------------------------------------------
func _build_buildings() -> void:
	for it in data.items("buildings"):
		var poly: PackedVector2Array = CampusData.ccw(it.get("footprint", PackedVector2Array()))
		if poly.size() < 3:
			continue
		var parts: Array = []
		for p in it.get("parts", []):
			var pp: PackedVector2Array = CampusData.ccw(p.get("footprint", PackedVector2Array()))
			if pp.size() >= 3:
				parts.append({"poly": pp, "h": float(p.get("h", it.get("h", 8.0))), "base": float(p.get("base", 0.0)),
					"roof": p.get("roof", it.get("roof", {})), "rect": CampusData.bounds(pp), "wall": String(p.get("wall", ""))})
		var h := float(it.get("h", 0.0))
		if h <= 0.0:
			for p in parts:
				h = maxf(h, float(p["h"]))
		var passages: Array = []
		for ps in it.get("passages", []):
			var pg: PackedVector2Array = ps.get("polygon", PackedVector2Array())
			if pg.size() >= 3:
				passages.append({"poly": snap_to_outline(CampusData.ccw(pg), poly), "floor": float(ps.get("floor", 0.0)), "clear": float(ps.get("clear", 3.0))})
		var rect := CampusData.bounds(poly)
		buildings.append({
			"id": String(it.get("id", "")), "name": String(it.get("label", "")), "kind": String(it.get("kind", "")),
			"status": String(it.get("status", "existing")), "poly": poly, "rect": rect,
			"pos": rect.get_center(), "size": rect.size, "rot": 0.0, "h": h, "floors": int(it.get("floors", 0)),
			"roof": it.get("roof", {}), "parts": parts, "style": it.get("style", {}), "entrances": it.get("entrances", []),
			"passages": passages, "landmark": it.get("landmark", null), "background": bool(it.get("background", false)),
			"ref": it.get("ref", ""),
		})


## A passage traced a hair inside the footprint (an open pavilion's posts
## line, a pergola along a facade) would leave a thin solid ring round it:
## its corners within SNAP_CORNER of a footprint corner move onto it, the
## others within SNAP_EDGE of an outline edge onto that edge.
const SNAP_CORNER := 0.8
const SNAP_EDGE := 0.5


static func snap_to_outline(pg: PackedVector2Array, foot: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := foot.size()
	for q in pg:
		var best := q
		var bd := SNAP_CORNER
		for c in foot:
			if c.distance_to(q) < bd:
				bd = c.distance_to(q)
				best = c
		if best == q:
			bd = SNAP_EDGE
			for i in n:
				var e := Geometry2D.get_closest_point_to_segment(q, foot[i], foot[(i + 1) % n])
				if e.distance_to(q) < bd:
					bd = e.distance_to(q)
					best = e
		out.append(best)
	return CampusData.ccw(out) if absf(CampusData.area(out)) > 0.5 else pg


func building_by_id(id: String) -> Dictionary:
	for b in buildings:
		if b["id"] == id:
			return b
	return {}


## Index of the (non-background) building whose footprint holds p, or -1.
func building_at(p: Vector2, margin: float = 0.0) -> int:
	var key := _cell(p)
	for bi in _bld_cells.get(key, []):
		var b: Dictionary = buildings[bi]
		if (b["rect"] as Rect2).grow(margin).has_point(p):
			if margin <= 0.0:
				if Geometry2D.is_point_in_polygon(p, b["poly"]):
					return bi
			elif Geometry2D.is_point_in_polygon(p, b["poly"]) or CampusData.dist_to_edge(p, b["poly"]) <= margin:
				return bi
	return -1


# ---------------------------------------------------------------------------
# Water
# ---------------------------------------------------------------------------
const KIND_DEPTH := {
	# kind: [surface_y, floor_y, rim_h]
	"lake": [-0.55, -3.0, 0.0], "pond": [-0.4, -2.2, 0.0], "channel": [-0.35, -1.4, 0.0],
	"pool": [0.2, -1.1, 0.45], "fountain": [0.25, -1.2, 0.5],
}


func _water_from_items(ids: Array, pres: Dictionary) -> Dictionary:
	var polys: Array = []
	var kind := ""
	var surface := INF
	var floor_y := INF
	var rim_h := -1.0
	var rim_t := 0.5
	var edge := ""
	var features: Array = []
	var center := Vector2.ZERO
	var radius := 0.0
	var any := false
	var wade := false
	for id in ids:
		var it := data.item(String(id))
		if it.is_empty():
			continue
		any = true
		wade = wade or bool(it.get("wade", false))
		kind = String(it.get("kind", "pond"))
		var dep: Array = KIND_DEPTH.get(kind, KIND_DEPTH["pond"])
		surface = minf(surface, float(it.get("surface", dep[0])))
		floor_y = minf(floor_y, float(it.get("floor", dep[1])))
		rim_h = maxf(rim_h, float(it.get("rim_h", dep[2])))
		rim_t = maxf(rim_t, float(it.get("rim_t", 0.5)))
		edge = String(it.get("edge", edge))
		features.append_array(it.get("features", []))
		if it.has("circle"):
			center = it["center"]
			radius = float(it["radius"])
			var circ := PackedVector2Array()
			var seg := 32
			for i in seg:
				var a := TAU * float(i) / float(seg)
				circ.append(center + Vector2(cos(a), sin(a)) * radius)
			polys.append(circ)
		elif it.has("polygon"):
			polys.append(CampusData.ccw(it["polygon"]))
	if not any or polys.is_empty():
		return {}
	var rect := CampusData.bounds(polys[0])
	for p in polys:
		rect = rect.merge(CampusData.bounds(p))
	# label point: the centroid of the largest part, pulled inside if concave
	var big: PackedVector2Array = polys[0]
	for p in polys:
		if absf(CampusData.area(p)) > absf(CampusData.area(big)):
			big = p
	var c := CampusData.centroid(big)
	if not Geometry2D.is_point_in_polygon(c, big):
		c = _interior_point(big)
	var w := {
		"id": String(pres.get("id", ids[0])), "parts": ids, "name": String(pres.get("name", "")),
		"short": String(pres.get("short", pres.get("name", ""))), "kind": kind,
		"shape": "circle" if (radius > 0.0 and polys.size() == 1) else "poly", "polys": polys,
		"center": center if (radius > 0.0 and polys.size() == 1) else c, "radius": radius, "rect": rect,
		"surface_y": surface, "floor_y": floor_y, "rim_h": maxf(0.0, rim_h), "rim_t": rim_t, "edge": edge,
		"features": features, "objective": bool(pres.get("objective", false)),
		# a shallow decorative runnel: drawn, walked through, never a splash
		"wade": wade and not bool(pres.get("objective", false)),
		"color": _color(pres.get("color", [0.6, 0.8, 1.0])), "icon": String(pres.get("icon", "drop")),
		"exits": [], "pads": [], "jump_points": [],
	}
	return w


static func _color(v: Variant) -> Color:
	if v is Color:
		return v
	if v is Array and (v as Array).size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]))
	return Color(0.6, 0.8, 1.0)


## A point well inside a polygon (for labels and beacons on concave shapes).
static func _interior_point(poly: PackedVector2Array) -> Vector2:
	var r := CampusData.bounds(poly)
	var best := r.get_center()
	var best_d := -1.0
	var n := 12
	for i in n:
		for j in n:
			var p := r.position + Vector2((float(i) + 0.5) / n * r.size.x, (float(j) + 0.5) / n * r.size.y)
			if Geometry2D.is_point_in_polygon(p, poly):
				var d := CampusData.dist_to_edge(p, poly)
				if d > best_d:
					best_d = d
					best = p
	return best


func _build_waters() -> void:
	var used: Dictionary = {}
	for pool in _gp("objective_pool"):
		for e in pool.get("waters", []):
			var ids: Array = e.get("items", [e.get("id", "")])
			var pres: Dictionary = (e as Dictionary).duplicate()
			pres["objective"] = true
			var w := _water_from_items(ids, pres)
			if w.is_empty():
				continue
			waters.append(w)
			for id in ids:
				used[String(id)] = true
	for it in data.items("water"):
		var id := String(it.get("id", ""))
		if used.has(id):
			continue
		var w := _water_from_items([id], {"id": id, "name": String(it.get("label", "")), "objective": false})
		if not w.is_empty():
			waters.append(w)


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


## How many waters are in the round's objective pool (the first ones).
func pool_size() -> int:
	var n := 0
	for w in waters:
		if bool(w.get("objective", false)):
			n += 1
	return n


## True if the XZ point lies inside the water footprint (optionally grown by margin).
static func in_water_shape(w: Dictionary, p: Vector2, margin: float = 0.0) -> bool:
	if not (w["rect"] as Rect2).grow(margin + 0.01).has_point(p):
		return false
	if String(w["shape"]) == "circle":
		return p.distance_to(w["center"]) <= float(w["radius"]) + margin
	for poly in w["polys"]:
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
		if margin > 0.0 and CampusData.dist_to_edge(p, poly) <= margin:
			return true
	return false


## Water index at p (any water), or -1.  Spatially hashed: called per tick.
func water_index_at(p: Vector2, margin: float = 0.0) -> int:
	for wi in _water_cells.get(_cell(p), []):
		if in_water_shape(waters[wi], p, margin):
			return wi
	return -1


## Shore exits (where a runner resurfaces), jump points and respawn pads,
## from each water's outline: samples along the edge every few metres, on
## open walkable ground just outside (exits) and just inside (jump points);
## pads a few metres further out.  Deterministic: data order, fixed steps.
func _build_water_points() -> void:
	for w in waters:
		if bool(w.get("wade", false)):
			continue
		var step := 6.0
		var kind := String(w["kind"])
		if kind == "lake":
			step = 14.0
		elif kind == "pond":
			step = 9.0
		elif kind == "channel":
			step = 10.0
		# exits stand just outside the rim (its real width: a fountain's
		# wide coping puts them further out than a thin kerb does)
		var out_d := 1.3 + float(w["rim_h"]) * 1.2 + (float(w["rim_t"]) if float(w["rim_h"]) > 0.0 else 0.0)
		var exits: Array = []
		var jumps: Array = []
		var pads: Array = []
		for poly in w["polys"]:
			for s in CampusData.boundary_samples(poly, step):
				var at: Vector2 = s[0]
				var n: Vector2 = s[1]
				var e: Vector2 = at + n * out_d
				var pad: Vector2 = at + n * (out_d + 5.0)
				if not _open_ground(e, 0.6):
					continue
				exits.append(Vector3(e.x, 0.0, e.y))
				jumps.append(at - n * 0.8)
				if _open_ground(pad, 1.0) and pads.size() < 10:
					pads.append(pad)
		if exits.is_empty():
			# fall back to the label point's surroundings (never empty)
			var c: Vector2 = w["center"]
			exits.append(Vector3(c.x, 0.0, c.y + 4.0))
			jumps.append(c)
		var reach := 0.0
		for poly in w["polys"]:
			for q in poly:
				reach = maxf(reach, (q as Vector2).distance_to(w["center"]))
		if reach < SMALL_WATER_R:
			# a small basin: pads 5 m out would all sit within a lunge or two
			# of anyone guarding its rim, so they ring it ~15 m beyond the
			# exits instead (two campers can never cover the respawn)
			pads = _ring_pads(w["center"], reach + out_d + PAD_RING_OUT)
		if pads.is_empty():
			for e in exits.slice(0, 4):
				pads.append(Vector2(e.x, e.z))
		w["exits"] = exits
		w["jump_points"] = jumps
		w["pads"] = pads


const SMALL_WATER_R := 9.0    # basins smaller than this get a pad ring
const PAD_RING_OUT := 12.0    # the ring's distance beyond the exits


## Up to 10 respawn pads on open ground round a point, one per bearing,
## each at the first clear radius near `r`.
func _ring_pads(c: Vector2, r: float) -> Array:
	var out: Array = []
	for k in 12:
		var dir := Vector2.from_angle(TAU * float(k) / 12.0)
		for dr in [0.0, 2.0, -1.5, 4.0, 6.0]:
			var q := c + dir * (r + float(dr))
			if _open_ground(q, 1.0):
				out.append(q)
				break
		if out.size() >= 10:
			break
	return out


## Walkable, unobstructed ground: inside the play area, not water, not a
## building, not on a wall/hedge/fence.
func _open_ground(p: Vector2, clearance: float) -> bool:
	if not in_play(p):
		return false
	for w in waters:
		if in_water_shape(w, p, clearance):
			return false
	for b in buildings:
		if (b["rect"] as Rect2).grow(clearance).has_point(p) and (Geometry2D.is_point_in_polygon(p, b["poly"]) or CampusData.dist_to_edge(p, b["poly"]) < clearance):
			return false
	for lst in [walls, hedges, fences]:
		for s in lst:
			if CampusData.dist_to_segment(p, s["a"], s["b"]) < clearance + float(s.get("t", 0.4)) * 0.5:
				return false
	return true


# ---------------------------------------------------------------------------
# Roads (carts are fast here), paths, areas
# ---------------------------------------------------------------------------
func _build_roads_and_paths() -> void:
	for it in data.items("roads"):
		var pts: PackedVector2Array = it.get("pts", PackedVector2Array())
		if pts.size() >= 2:
			roads.append({"id": String(it.get("id", "")), "pts": pts, "w": float(it.get("w", 7.0)), "kind": String(it.get("kind", "campus")), "curb": bool(it.get("curb", true))})
	for it in data.items("paths"):
		var pts: PackedVector2Array = it.get("pts", PackedVector2Array())
		if pts.size() >= 2:
			paths.append({"id": String(it.get("id", "")), "pts": pts, "w": float(it.get("w", 3.0)), "surface": String(it.get("surface", "concrete"))})


const PAVED := ["plaza", "pavement", "court"]


func _build_areas() -> void:
	for it in data.items("areas"):
		var poly: PackedVector2Array = it.get("polygon", PackedVector2Array())
		if poly.size() < 3:
			continue
		var a := {"id": String(it.get("id", "")), "kind": String(it.get("kind", "")), "poly": CampusData.ccw(poly), "rect": CampusData.bounds(poly)}
		areas.append(a)
		if PAVED.has(a["kind"]):
			plazas.append(a)
		if a["kind"] == "parking":
			_lots.append(a["poly"])


func is_on_road(p: Vector2, margin: float = 0.0) -> bool:
	var key := _cell(p)
	for s in _road_cells.get(key, []):
		if CampusData.dist_to_segment(p, s[0], s[1]) <= float(s[2]) + margin:
			return true
	for li in _lot_cells.get(key, []):
		if Geometry2D.is_point_in_polygon(p, _lots[li]):
			return true
	return false


func is_on_path(p: Vector2, margin: float = 0.0) -> bool:
	for s in _path_cells.get(_cell(p), []):
		if CampusData.dist_to_segment(p, s[0], s[1]) <= float(s[2]) + margin:
			return true
	return false


static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	return CampusData.dist_to_segment(p, a, b)


# ---------------------------------------------------------------------------
# Barriers
# ---------------------------------------------------------------------------
func _build_barriers() -> void:
	for it in data.items("barriers"):
		var pts: PackedVector2Array = it.get("pts", PackedVector2Array())
		var kind := String(it.get("kind", ""))
		var h := float(it.get("h", 0.0))
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			if a.distance_to(b) < 0.05:
				continue
			match kind:
				"wall_low", "wall_retaining":
					walls.append({"a": a, "b": b, "h": h if h > 0.0 else 0.6, "t": float(it.get("t", 0.45)), "kind": kind})
				"hedge":
					hedges.append({"a": a, "b": b, "h": h if h > 0.0 else 1.5, "t": float(it.get("t", 1.0)), "kind": kind})
				"fence_iron", "fence_chain", "fence_construction", "rail":
					fences.append({"a": a, "b": b, "h": h if h > 0.0 else (1.0 if kind == "rail" else 1.8), "kind": kind, "t": 0.25})
				"bollards":
					cart_blockers.append({"a": a, "b": b})


# ---------------------------------------------------------------------------
# Trees, lamps, benches, props (placed from evidence by the data)
# ---------------------------------------------------------------------------
func _build_vegetation_and_props() -> void:
	for it in data.items("trees"):
		var p: Vector2 = it.get("pos", Vector2.ZERO)
		var r := float(it.get("r", 4.0))
		trees.append({"id": String(it.get("id", "")), "pos": p, "r": r, "h": float(it.get("h", 9.0)),
			"kind": String(it.get("kind", "deciduous")), "species": String(it.get("species", "")),
			"tint": fposmod(p.x * 0.131 + p.y * 0.071, 1.0), "obs": String(it.get("obs", "inferred")),
			"collide": String(it.get("kind", "")) != "shrub"})
	for it in data.items("props"):
		var kind := String(it.get("kind", ""))
		var p: Vector2 = it.get("p", Vector2.ZERO)
		var rot := deg_to_rad(float(it.get("rot", 0.0)))
		match kind:
			"lamp", "light_pole":
				lamps.append(p)
			"bench":
				benches.append({"pos": p, "rot": rot})
			_:
				props.append({"kind": kind, "pos": p, "rot": rot, "len": float(it.get("len", 0.0)), "id": String(it.get("id", ""))})


# ---------------------------------------------------------------------------
# Start dorms (CampusDorms)
# ---------------------------------------------------------------------------
func _build_dorms() -> void:
	for id in CampusDorms.ids():
		var g := CampusDorms.geometry(id)
		if g.is_empty():
			continue
		var e := CampusDorms.def(id).duplicate()
		e["geo"] = g
		dorms.append(e)
		dorm_doors.append_array(g["doors"])
		dorm_pads.append_array(g["respawn"])
		for pd in g["pads"]:
			runner_spawns.append(pd["pos"])
		for cl in g["cart_lines"]:
			cart_blockers.append({"a": cl[0], "b": cl[1], "hidden": true})


func dorm(id: String) -> Dictionary:
	for d in dorms:
		if String(d["id"]) == id:
			return d
	return {}


func home_doors(id: String) -> Array:
	var g := CampusDorms.geometry(id)
	return g.get("doors", []) if not g.is_empty() else []


func dorm_center(id: String) -> Vector2:
	var g := CampusDorms.geometry(id)
	if g.is_empty():
		return Vector2.ZERO
	return CampusData.centroid(g["room"])


# ---------------------------------------------------------------------------
# Spatial hash
# ---------------------------------------------------------------------------
static func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


func _add_seg(cells: Dictionary, a: Vector2, b: Vector2, hw: float, payload: Variant) -> void:
	var r := Rect2(a, Vector2.ZERO).expand(b).grow(hw)
	for cx in range(floori(r.position.x / CELL), floori(r.end.x / CELL) + 1):
		for cz in range(floori(r.position.y / CELL), floori(r.end.y / CELL) + 1):
			var k := Vector2i(cx, cz)
			if not cells.has(k):
				cells[k] = []
			cells[k].append(payload)


func _add_rect(cells: Dictionary, r: Rect2, payload: Variant) -> void:
	for cx in range(floori(r.position.x / CELL), floori(r.end.x / CELL) + 1):
		for cz in range(floori(r.position.y / CELL), floori(r.end.y / CELL) + 1):
			var k := Vector2i(cx, cz)
			if not cells.has(k):
				cells[k] = []
			cells[k].append(payload)


func _index() -> void:
	for r in roads:
		var pts: PackedVector2Array = r["pts"]
		var hw := float(r["w"]) * 0.5
		for i in pts.size() - 1:
			_add_seg(_road_cells, pts[i], pts[i + 1], hw, [pts[i], pts[i + 1], hw])
	for i in _lots.size():
		_add_rect(_lot_cells, CampusData.bounds(_lots[i]), i)
	for p in paths:
		var pts: PackedVector2Array = p["pts"]
		var hw := float(p["w"]) * 0.5
		for i in pts.size() - 1:
			_add_seg(_path_cells, pts[i], pts[i + 1], hw, [pts[i], pts[i + 1], hw])
	for i in waters.size():
		if not bool(waters[i].get("wade", false)):
			_add_rect(_water_cells, (waters[i]["rect"] as Rect2).grow(1.0), i)
	for i in buildings.size():
		_add_rect(_bld_cells, (buildings[i]["rect"] as Rect2).grow(1.0), i)
