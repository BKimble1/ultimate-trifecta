class_name CampusData
extends RefCounted
## The reference campus's layer data (game/data/campus/*.json, written by
## tools/campus/build_data.py from the traced zones; schema in
## docs/campus/DATA_SCHEMA.md), loaded once per session, plus the geometry
## helpers every campus system shares.
##
## Frame: metres, +X east, +Z south (north is -Z), ground y = 0.  Polygons are
## PackedVector2Array in (x, z).  Nothing here names a real place: items carry
## neutral ids and evidence codes only.
##
## `campus_hash` identifies the exact data a build carries: the host publishes
## it in every round's configuration and a guest with other data refuses the
## round (two builds with different campuses never share a match).

const DIR := "res://data/campus/"
const LAYERS := ["buildings", "water", "roads", "paths", "areas", "barriers", "trees", "props", "gameplay"]

## name -> Array of item Dictionaries (polygons/polylines already converted)
var layers: Dictionary = {}
var campus_hash := ""
## convenience lookups
var by_id: Dictionary = {}

static var _shared: CampusData


static func shared() -> CampusData:
	if _shared == null:
		_shared = CampusData.new()
	return _shared


## Drops the cached data (tests that swap data sets).
static func reset_shared() -> void:
	_shared = null


func _init(dir: String = DIR) -> void:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for name in LAYERS:
		var path: String = dir + String(name) + ".json"
		var items: Array = []
		if FileAccess.file_exists(path):
			var raw := FileAccess.get_file_as_bytes(path)
			ctx.update(name.to_utf8_buffer())
			ctx.update(raw)
			var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
			if parsed is Dictionary:
				items = (parsed as Dictionary).get("items", [])
			elif parsed is Array:
				items = parsed
		var out: Array = []
		for it in items:
			if it is Dictionary:
				var d := _convert(it as Dictionary)
				out.append(d)
				if d.has("id"):
					by_id[String(d["id"])] = d
		layers[name] = out
	campus_hash = ctx.finish().hex_encode().substr(0, 16)


func items(layer: String) -> Array:
	return layers.get(layer, [])


func item(id: String) -> Dictionary:
	return by_id.get(id, {})


## JSON arrays of [x, z] become PackedVector2Array; nested parts/passages too.
static func _convert(it: Dictionary) -> Dictionary:
	var d := it.duplicate(true)
	for k in ["footprint", "polygon", "pts", "room", "zone_poly"]:
		if d.has(k) and d[k] is Array:
			d[k] = to_poly(d[k])
	for k in ["parts", "passages"]:
		if d.has(k) and d[k] is Array:
			var arr: Array = []
			for p in d[k]:
				if p is Dictionary:
					arr.append(_convert(p as Dictionary))
			d[k] = arr
	if d.has("circle") and d["circle"] is Array and (d["circle"] as Array).size() == 2:
		var c: Array = d["circle"]
		d["center"] = Vector2(float(c[0][0]), float(c[0][1]))
		d["radius"] = float(c[1])
	for k in ["pos", "p"]:
		if d.has(k) and d[k] is Array and (d[k] as Array).size() == 2:
			d[k] = Vector2(float(d[k][0]), float(d[k][1]))
	return d


static func to_poly(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in a:
		if q is Array and (q as Array).size() >= 2:
			out.append(Vector2(float(q[0]), float(q[1])))
		elif q is Vector2:
			out.append(q)
	return out


# ---------------------------------------------------------------------------
# Geometry helpers (pure, deterministic)
# ---------------------------------------------------------------------------
static func bounds(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r


static func area(poly: PackedVector2Array) -> float:
	var a := 0.0
	var n := poly.size()
	for i in n:
		var p := poly[i]
		var q := poly[(i + 1) % n]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


static func centroid(poly: PackedVector2Array) -> Vector2:
	var a := area(poly)
	if absf(a) < 1e-6:
		var s := Vector2.ZERO
		for p in poly:
			s += p
		return s / maxf(1.0, float(poly.size()))
	var c := Vector2.ZERO
	var n := poly.size()
	for i in n:
		var p := poly[i]
		var q := poly[(i + 1) % n]
		var f := p.x * q.y - q.x * p.y
		c += (p + q) * f
	return c / (6.0 * a)


## Counter-clockwise in the (x, z) plane with +z south, i.e. positive area.
static func ccw(poly: PackedVector2Array) -> PackedVector2Array:
	if area(poly) < 0.0:
		var r := poly.duplicate()
		r.reverse()
		return r
	return poly


static func inside(poly: PackedVector2Array, p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p, poly)


static func dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-9:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func dist_to_polyline(p: Vector2, pts: PackedVector2Array) -> float:
	var best := INF
	for i in pts.size() - 1:
		best = minf(best, dist_to_segment(p, pts[i], pts[i + 1]))
	return best


static func dist_to_edge(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	var n := poly.size()
	for i in n:
		best = minf(best, dist_to_segment(p, poly[i], poly[(i + 1) % n]))
	return best


## The nearest point on a polygon's boundary.
static func nearest_on_edge(p: Vector2, poly: PackedVector2Array) -> Vector2:
	var best := INF
	var out := p
	var n := poly.size()
	for i in n:
		var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % n])
		var d := p.distance_squared_to(q)
		if d < best:
			best = d
			out = q
	return out


static func polyline_length(pts: PackedVector2Array) -> float:
	var l := 0.0
	for i in pts.size() - 1:
		l += pts[i].distance_to(pts[i + 1])
	return l


static func perimeter(poly: PackedVector2Array) -> float:
	return polyline_length(poly) + (poly[poly.size() - 1].distance_to(poly[0]) if poly.size() > 1 else 0.0)


## Points every `step` metres along a closed polygon's boundary (with the
## outward normal at each), starting at vertex 0.
static func boundary_samples(poly: PackedVector2Array, step: float) -> Array:
	var out: Array = []
	var cp := ccw(poly)
	var n := cp.size()
	var carry := 0.0
	for i in n:
		var a := cp[i]
		var b := cp[(i + 1) % n]
		var seg := a.distance_to(b)
		if seg < 1e-6:
			continue
		var dir := (b - a) / seg
		# positive area (counter-clockwise in the x, z plane): the inside is
		# left of the direction of travel, the outward normal right of it
		var nrm := Vector2(dir.y, -dir.x)
		var t := carry
		while t < seg:
			out.append([a + dir * t, nrm])
			t += step
		carry = t - seg
	return out


## A polygon grown (d > 0) or shrunk (d < 0); the largest result piece.
static func offset(poly: PackedVector2Array, d: float) -> PackedVector2Array:
	var res := Geometry2D.offset_polygon(poly, d, Geometry2D.JOIN_MITER)
	var best := PackedVector2Array()
	var best_a := 0.0
	for r in res:
		var a := absf(area(r))
		if a > best_a:
			best_a = a
			best = r
	return best


## A polyline widened into a polygon (a road or path ribbon), square ends.
static func ribbon(pts: PackedVector2Array, w: float) -> Array[PackedVector2Array]:
	return Geometry2D.offset_polyline(pts, w * 0.5, Geometry2D.JOIN_ROUND, Geometry2D.END_SQUARE)


## Convex pieces of a simple polygon (for collision shapes).
static func convex_pieces(poly: PackedVector2Array) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for piece in Geometry2D.decompose_polygon_in_convex(poly):
		if piece.size() >= 3 and absf(area(piece)) > 0.05:
			out.append(piece)
	return out


## poly minus every hole (passages, rooms): the solid pieces that remain,
## as simple polygons (a piece that would keep a hole is split by a seam
## through the hole, so callers never see holes).
static func subtract(poly: PackedVector2Array, holes: Array) -> Array[PackedVector2Array]:
	var pieces: Array[PackedVector2Array] = [poly]
	for h in holes:
		var hp: PackedVector2Array = h
		var next: Array[PackedVector2Array] = []
		for pc in pieces:
			if not bounds(pc).grow(0.01).intersects(bounds(hp)):
				next.append(pc)
				continue
			var res := Geometry2D.clip_polygons(pc, hp)
			var outer: Array[PackedVector2Array] = []
			var inner: Array[PackedVector2Array] = []
			for r in res:
				if Geometry2D.is_polygon_clockwise(r) == Geometry2D.is_polygon_clockwise(pc):
					outer.append(r)
				else:
					inner.append(r)
			if inner.is_empty():
				next.append_array(outer)
			else:
				# the hole lies wholly inside: cut the piece in two through the hole
				for o in outer:
					next.append_array(_split_through(o, hp))
		pieces = next
	return pieces


static func _split_through(pc: PackedVector2Array, hole: PackedVector2Array) -> Array[PackedVector2Array]:
	var hb := bounds(hole)
	var pb := bounds(pc)
	var mid := hb.get_center().x
	var left := PackedVector2Array([Vector2(pb.position.x - 1.0, pb.position.y - 1.0), Vector2(mid, pb.position.y - 1.0), Vector2(mid, pb.end.y + 1.0), Vector2(pb.position.x - 1.0, pb.end.y + 1.0)])
	var right := PackedVector2Array([Vector2(mid, pb.position.y - 1.0), Vector2(pb.end.x + 1.0, pb.position.y - 1.0), Vector2(pb.end.x + 1.0, pb.end.y + 1.0), Vector2(mid, pb.end.y + 1.0)])
	var out: Array[PackedVector2Array] = []
	for half in [left, right]:
		for part in Geometry2D.intersect_polygons(pc, half):
			for r in Geometry2D.clip_polygons(part, hole):
				if not Geometry2D.is_polygon_clockwise(r) == Geometry2D.is_polygon_clockwise(part):
					continue
				if absf(area(r)) > 0.05:
					out.append(r)
	return out


## Triangulates a simple polygon (indices into poly); empty on failure.
static func triangulate(poly: PackedVector2Array) -> PackedInt32Array:
	return Geometry2D.triangulate_polygon(poly)


## Edge indices of a polygon by `cap`-sized cell: each edge is filed in
## every cell its box, grown by `cap`, touches (for near_edge_dist).
static func edge_buckets(poly: PackedVector2Array, cap: float) -> Dictionary:
	var out := {}
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var lo := Vector2i(floori((minf(a.x, b.x) - cap) / cap), floori((minf(a.y, b.y) - cap) / cap))
		var hi := Vector2i(floori((maxf(a.x, b.x) + cap) / cap), floori((maxf(a.y, b.y) + cap) / cap))
		for cx in range(lo.x, hi.x + 1):
			for cy in range(lo.y, hi.y + 1):
				var key := Vector2i(cx, cy)
				if not out.has(key):
					out[key] = PackedInt32Array()
				(out[key] as PackedInt32Array).append(i)
	return out


## Distance to the nearest edge, or `cap` when none is that close: only
## the edges filed in p's cell are tried (edge_buckets with the same cap).
static func near_edge_dist(p: Vector2, poly: PackedVector2Array, near: Dictionary, cap: float) -> float:
	var key := Vector2i(floori(p.x / cap), floori(p.y / cap))
	if not near.has(key):
		return cap
	var best := cap
	var n := poly.size()
	for i in near[key]:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % n])))
	return best
