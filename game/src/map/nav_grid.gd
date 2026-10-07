class_name NavGrid
extends RefCounted
## Navigation grids rasterised from a map's CampusLayout (cells of the map's
## nav_cell: 2 m on the reference campus, 1 m on Moonbrook College, as 2.0
## had them): one for runners/patrol
## on foot (low walls and rails cost extra and are hopped), one for carts
## (roads and parking preferred, bollards/walls/hedges solid, inflated by
## the cart's half-width).  Uses Godot's native AStarGrid2D so path queries
## are cheap on device.
##
## The reference campus is about 1.2 x 1.0 km: a 1 m grid would be 1.19 M
## cells per grid (measured ~99 MB each in AStarGrid2D), so cells are 2 m
## (~0.3 M cells, ~22 MB each).  Obstacles are polygons (traced footprints
## minus open passages, waters, the play boundary) filled by scanline spans
## after inflating them by the walker's clearance; lines (hedges, walls,
## fences) and points (trees, lamps, benches) by distance.  A start dorm's
## doorways are carved open along their axis afterwards so a door is always
## reachable whatever its angle to the grid.

var layout: CampusLayout
## cell size (m): the layout's nav_cell
var cell := 2.0
var origin := Vector2.ZERO
var dims := Vector2i.ZERO
var foot := AStarGrid2D.new()
var cart := AStarGrid2D.new()
var low_wall_cells: Dictionary = {}

static var _shared: NavGrid
## A grid being built in slices under the loading screen.
static var _building: NavGrid
const FOOT_INF := 0.45
const CART_INF := 1.25
## The rasterisation in slices of similar cost, in a fixed order (the
## finished grid is identical however it is stepped; test_prep_jobs).
const PHASES := [["_r_setup", 0, 2], ["_r_setup", 1, 2],
	["_r_outside", 0, 2], ["_r_outside", 1, 2],
	["_r_roads", 0, 4], ["_r_roads", 1, 4], ["_r_roads", 2, 4], ["_r_roads", 3, 4],
	["_r_buildings", 0, 4], ["_r_buildings", 1, 4], ["_r_buildings", 2, 4], ["_r_buildings", 3, 4],
	["_r_lines", 0, 3], ["_r_lines", 1, 3], ["_r_lines", 2, 3],
	["_r_points", 0, 4], ["_r_points", 1, 4], ["_r_points", 2, 4], ["_r_points", 3, 4],
	["_r_waters", 0, 2], ["_r_waters", 1, 2],
	["_r_slopes", 0, 2], ["_r_slopes", 1, 2],
	["_r_dorms", 0, 1],
	["_r_edges", 0, 1]]
var _phase := 0


static func shared(lay: CampusLayout) -> NavGrid:
	if _shared == null or _shared.layout != lay:
		if _building != null and _building.layout == lay:
			while _building.step():
				pass
			_shared = _building
			_building = null
		else:
			_shared = NavGrid.new(lay)
	return _shared


## Staged build for the loading screen: one slice per call, true while more
## remain.  The finished grid is exactly the one shared() would build.
static func build_step(lay: CampusLayout) -> bool:
	if _shared != null and _shared.layout == lay:
		return false
	if _building == null or _building.layout != lay:
		_building = NavGrid.new(lay, true)
		return true
	if _building.step():
		return true
	_shared = _building
	_building = null
	return false


func step() -> bool:
	if _phase < PHASES.size():
		var ph: Array = PHASES[_phase]
		call(String(ph[0]), int(ph[1]), int(ph[2]))
		_phase += 1
	return _phase < PHASES.size()


func _init(lay: CampusLayout, staged: bool = false) -> void:
	layout = lay
	cell = lay.nav_cell
	origin = lay.bounds.position
	dims = Vector2i(int(ceil(lay.bounds.size.x / cell)), int(ceil(lay.bounds.size.y / cell)))
	if not staged:
		_rasterize()


## The grids themselves: the foot grid in the first slice, the cart grid
## (grass costing carts more than road, one native region fill) in the
## second.
func _r_setup(part: int, _parts: int) -> void:
	var g: AStarGrid2D = foot if part == 0 else cart
	g.region = Rect2i(Vector2i.ZERO, dims)
	g.cell_size = Vector2(cell, cell)
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.update()
	if part == 1:
		cart.fill_weight_scale_region(Rect2i(Vector2i.ZERO, dims), 1.8)


## Slice `part` of `parts` over n items, in order.
static func _slice(n: int, part: int, parts: int) -> Vector2i:
	return Vector2i(n * part / parts, n * (part + 1) / parts)


func to_cell(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(floor((p.x - origin.x) / cell)), 0, dims.x - 1), clampi(int(floor((p.y - origin.y) / cell)), 0, dims.y - 1))


func to_world(c: Vector2i) -> Vector2:
	return Vector2(origin.x + (float(c.x) + 0.5) * cell, origin.y + (float(c.y) + 0.5) * cell)


func _cells_in_rect(r: Rect2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var a := to_cell(r.position)
	var b := to_cell(r.end)
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			out.append(Vector2i(x, y))
	return out


## Every cell whose centre lies inside `poly`, as row spans.  `fn` gets a
## Rect2i one row high per span.
func _spans(poly: PackedVector2Array, fn: Callable) -> void:
	if poly.size() < 3:
		return
	var r := CampusData.bounds(poly)
	var j0 := clampi(int(floor((r.position.y - origin.y) / cell - 0.5)), 0, dims.y - 1)
	var j1 := clampi(int(ceil((r.end.y - origin.y) / cell - 0.5)), 0, dims.y - 1)
	for j in range(j0, j1 + 1):
		var z := origin.y + (float(j) + 0.5) * cell
		var xs := CampusBuilder.scan_row(poly, z)
		for k in range(0, xs.size() - 1, 2):
			var i0 := maxi(int(ceil((xs[k] - origin.x) / cell - 0.5)), 0)
			var i1 := mini(int(floor((xs[k + 1] - origin.x) / cell - 0.5)), dims.x - 1)
			if i1 >= i0:
				fn.call(Rect2i(i0, j, i1 - i0 + 1, 1))


## A polygon grown by `inflate` (outer rings of the offset only).
static func _grown(poly: PackedVector2Array, inflate: float) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if inflate <= 0.0:
		out.append(poly)
		return out
	var res := Geometry2D.offset_polygon(poly, inflate, Geometry2D.JOIN_MITER)
	if res.is_empty():
		return out
	var big: PackedVector2Array = res[0]
	for r in res:
		if absf(CampusData.area(r)) > absf(CampusData.area(big)):
			big = r
	# outer rings share the largest ring's winding; holes wind the other way
	var cw := Geometry2D.is_polygon_clockwise(big)
	for r in res:
		if Geometry2D.is_polygon_clockwise(r) == cw:
			out.append(r)
	return out


func _solid_poly(g: AStarGrid2D, poly: PackedVector2Array, inflate: float) -> void:
	for gp in _grown(poly, inflate):
		_spans(gp, func(r: Rect2i) -> void: g.fill_solid_region(r, true))


func _weight_poly(g: AStarGrid2D, poly: PackedVector2Array, inflate: float, w: float) -> void:
	for gp in _grown(poly, inflate):
		_spans(gp, func(r: Rect2i) -> void: g.fill_weight_scale_region(r, w))


func _solid_segment(g: AStarGrid2D, a: Vector2, b: Vector2, half_t: float, inflate: float) -> void:
	var r := Rect2(a, Vector2.ZERO).expand(b).grow(half_t + inflate + cell)
	for c in _cells_in_rect(r):
		if CampusData.dist_to_segment(to_world(c), a, b) <= half_t + inflate:
			g.set_point_solid(c, true)


func _weight_segment(g: AStarGrid2D, a: Vector2, b: Vector2, reach: float, w: float, mark_low: bool) -> void:
	var r := Rect2(a, Vector2.ZERO).expand(b).grow(reach + cell)
	for c in _cells_in_rect(r):
		if CampusData.dist_to_segment(to_world(c), a, b) <= reach:
			g.set_point_weight_scale(c, maxf(g.get_point_weight_scale(c), w))
			if mark_low:
				low_wall_cells[c] = true


func _solid_circle(g: AStarGrid2D, center: Vector2, radius: float) -> void:
	var r := Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0).grow(cell)
	for c in _cells_in_rect(r):
		if to_world(c).distance_to(center) <= radius:
			g.set_point_solid(c, true)


func _rasterize() -> void:
	while step():
		pass


## Beyond the play boundary: solid for both, row by row (the complement of
## the boundary's spans).
func _r_outside(part: int, parts: int) -> void:
	var bnd := _inner_boundary()
	var sl := _slice(dims.y, part, parts)
	for j in range(sl.x, sl.y):
		var z := origin.y + (float(j) + 0.5) * cell
		var xs := CampusBuilder.scan_row(bnd, z) if bnd.size() >= 3 else PackedFloat32Array()
		var x := 0
		for k in range(0, xs.size() - 1, 2):
			var i0 := clampi(int(ceil((xs[k] - origin.x) / cell - 0.5)), 0, dims.x)
			var i1 := clampi(int(floor((xs[k + 1] - origin.x) / cell - 0.5)), -1, dims.x - 1)
			if i0 > x:
				foot.fill_solid_region(Rect2i(x, j, i0 - x, 1), true)
				cart.fill_solid_region(Rect2i(x, j, i0 - x, 1), true)
			x = maxi(x, i1 + 1)
		if x < dims.x:
			foot.fill_solid_region(Rect2i(x, j, dims.x - x, 1), true)
			cart.fill_solid_region(Rect2i(x, j, dims.x - x, 1), true)


var _inner_bnd := PackedVector2Array()


## The play boundary pulled in by the invisible wall's half thickness
## (CampusBuilder: 1 m, centred on the line) plus FOOT_INF, so no open cell
## puts a runner against that wall.
func _inner_boundary() -> PackedVector2Array:
	if _inner_bnd.is_empty() and layout.play_boundary.size() >= 3:
		var best := PackedVector2Array()
		for q in Geometry2D.offset_polygon(layout.play_boundary, -(0.5 + FOOT_INF)):
			if absf(CampusData.area(q)) > absf(CampusData.area(best)):
				best = q
		_inner_bnd = best if best.size() >= 3 else layout.play_boundary
	return _inner_bnd


## Roads and parking lots: carts at full speed there (weight 1).
func _r_roads(part: int, parts: int) -> void:
	var nr := layout.roads.size()
	var lots: Array = []
	for a in layout.areas:
		if String(a["kind"]) == "parking":
			lots.append(a["poly"])
	var sl := _slice(nr + lots.size(), part, parts)
	for ri in range(sl.x, mini(sl.y, nr)):
		var r: Dictionary = layout.roads[ri]
		var pts: PackedVector2Array = r["pts"]
		var hw := float(r["w"]) * 0.5
		for i in pts.size() - 1:
			var rect := Rect2(pts[i], Vector2.ZERO).expand(pts[i + 1]).grow(hw + cell)
			for c in _cells_in_rect(rect):
				if CampusData.dist_to_segment(to_world(c), pts[i], pts[i + 1]) <= hw:
					cart.set_point_weight_scale(c, 1.0)
	for li in range(maxi(sl.x, nr), sl.y):
		_weight_poly(cart, lots[li - nr], 0.0, 1.0)


## Buildings: on foot, the footprint minus its open passages (the bell
## tower: its piers); carts: the whole footprint.  Start dorms are done in
## _r_dorms.  Background buildings lie outside the play area anyway.
func _r_buildings(part: int, parts: int) -> void:
	var dorm_b: Dictionary = {}
	for id in CampusDorms.ids(layout.map_id):
		dorm_b[String(CampusDorms.geometry(id).get("building", ""))] = id
	var sl := _slice(layout.buildings.size(), part, parts)
	for bi in range(sl.x, sl.y):
		var bd: Dictionary = layout.buildings[bi]
		if bool(bd["background"]):
			continue
		_solid_poly(cart, bd["poly"], CART_INF)
		if dorm_b.has(String(bd["id"])):
			continue
		if bd.get("landmark") != null and String(bd["landmark"]) == "bell_tower":
			for so in CampusTower.solids(bd):
				if float(so["base"]) < 1.0:
					_solid_poly(foot, so["poly"], FOOT_INF)
			continue
		var holes: Array = []
		for ps in bd["passages"]:
			holes.append(ps["poly"])
		var parts_l: Array = bd["parts"]
		var polys: Array = []
		if parts_l.is_empty():
			polys.append(bd["poly"])
		else:
			for pt in parts_l:
				if float(pt.get("base", 0.0)) < 1.0:
					polys.append(pt["poly"])
		for poly in polys:
			for piece in CampusData.subtract(poly, holes):
				_solid_poly(foot, piece, FOOT_INF)
		for e in CampusArchitecture.portico_entrances(bd):
			for cp in CampusArchitecture.portico_columns(e):
				_solid_circle(foot, cp, 0.31 + FOOT_INF)
		for cl in CampusArchitecture.passage_columns(bd):
			_solid_circle(foot, cl[0], float(cl[1]) + FOOT_INF)


## Hedges and tall fences are solid; low walls and rails are hopped at a
## cost by runners; carts are stopped by all of them and by bollards.
func _r_lines(part: int, parts: int) -> void:
	var nh := layout.hedges.size()
	var nf := layout.fences.size()
	var nw := layout.walls.size()
	var sl := _slice(nh + nf + nw + layout.cart_blockers.size(), part, parts)
	for i in range(sl.x, sl.y):
		if i < nh:
			var s: Dictionary = layout.hedges[i]
			_solid_segment(foot, s["a"], s["b"], float(s["t"]) * 0.5, FOOT_INF)
			_solid_segment(cart, s["a"], s["b"], float(s["t"]) * 0.5, CART_INF)
		elif i < nh + nf:
			var s2: Dictionary = layout.fences[i - nh]
			if float(s2["h"]) <= 1.05:
				_weight_segment(foot, s2["a"], s2["b"], 0.9, 6.0, true)
			else:
				_solid_segment(foot, s2["a"], s2["b"], 0.15, FOOT_INF)
			_solid_segment(cart, s2["a"], s2["b"], 0.15, CART_INF)
		elif i < nh + nf + nw:
			var s3: Dictionary = layout.walls[i - nh - nf]
			var t := float(s3["t"]) * 0.5
			if float(s3["h"]) <= 1.1:
				_weight_segment(foot, s3["a"], s3["b"], t + 0.6, 4.0, true)
			else:
				_solid_segment(foot, s3["a"], s3["b"], t, FOOT_INF)
			_solid_segment(cart, s3["a"], s3["b"], t, CART_INF)
		else:
			var s4: Dictionary = layout.cart_blockers[i - nh - nf - nw]
			_solid_segment(cart, s4["a"], s4["b"], 0.25, CART_INF)


## Tree trunks block both; lamps and benches cost a runner a little (a
## 2 m cell is wider than a bench is deep) and stop carts; boulders and
## solid pieces (railings, signs, a fountain's column) block both.
func _r_points(part: int, parts: int) -> void:
	var nt := layout.trees.size()
	var nl := layout.lamps.size()
	var nb := layout.benches.size()
	var np := layout.props.size()
	var sl := _slice(nt + nl + nb + np + layout.rocks.size() + layout.solids.size(), part, parts)
	for i in range(sl.x, sl.y):
		if i < nt:
			var t: Dictionary = layout.trees[i]
			if not bool(t.get("collide", true)):
				continue
			_solid_circle(foot, t["pos"], 0.42 + FOOT_INF)
			_solid_circle(cart, t["pos"], 0.42 + CART_INF)
		elif i < nt + nl:
			var lp: Vector2 = layout.lamps[i - nt]
			_solid_circle(cart, lp, 0.2 + CART_INF)
		elif i < nt + nl + nb:
			var bn: Dictionary = layout.benches[i - nt - nl]
			var bp: Vector2 = bn["pos"]
			foot.set_point_weight_scale(to_cell(bp), maxf(foot.get_point_weight_scale(to_cell(bp)), 3.0))
			_solid_circle(cart, bp, 1.0 + CART_INF)
		elif i >= nt + nl + nb + np:
			var k := i - nt - nl - nb - np
			var so: Dictionary = layout.rocks[k] if k < layout.rocks.size() else layout.solids[k - layout.rocks.size()]
			var c3: Variant = so["pos"]
			var c2 := Vector2((c3 as Vector3).x, (c3 as Vector3).z) if c3 is Vector3 else (c3 as Vector2)
			var sz: Vector3 = so["size"]
			if String(so.get("shape", "")) == "cyl":
				_solid_circle(foot, c2, sz.x * 0.5 + FOOT_INF * 0.5)
				_solid_circle(cart, c2, sz.x * 0.5 + CART_INF)
				continue
			var box := CampusDorms._obox(c2, Vector2(sz.x, sz.z), float(so["rot"]))
			_solid_poly(foot, box, FOOT_INF * 0.5)
			_solid_poly(cart, box, CART_INF)
		else:
			var pr: Dictionary = layout.props[i - nt - nl - nb]
			if not bool(pr.get("collide", true)):
				continue
			var ps := CampusArchitecture.prop_collider(pr)
			if ps == Vector3.ZERO:
				continue
			var r := Vector2(ps.x, ps.z).length() * 0.5
			if r > 1.2:
				_solid_circle(foot, pr["pos"], r + FOOT_INF * 0.5)
			_solid_circle(cart, pr["pos"], r + CART_INF)


func _r_waters(part: int, parts: int) -> void:
	var sl := _slice(layout.waters.size(), part, parts)
	for wi in range(sl.x, sl.y):
		var w: Dictionary = layout.waters[wi]
		if bool(w.get("wade", false)):
			continue      # a shallow runnel: walked through
		var rim := float(w.get("rim_t", 0.0)) if float(w.get("rim_h", 0.0)) > 0.0 else 0.0
		for poly in w["polys"]:
			_solid_poly(foot, poly, FOOT_INF + rim + 0.1)
			_solid_poly(cart, poly, CART_INF + 0.5)


## Ground too steep to walk (or drive) on a map with terrain: cells whose
## steepest 1 m step is beyond the capsule's 50 degree floor limit (with a
## margin: tan 42) are solid on foot, beyond the cart's 35 degrees (tan 29)
## for carts.  The terrain bake lists them (terrain.json "steep", on this
## grid's 2 m cells), so loading reads a short list instead of scanning the
## whole ground.  Stairs and ramps have their own colliders above the ground.
func _r_slopes(part: int, parts: int) -> void:
	if layout.terrain.is_empty():
		return
	var st: Dictionary = (layout.terrain["meta"] as Dictionary).get("steep", {})
	if st.is_empty() or not is_equal_approx(float(st.get("cell", 0.0)), cell):
		return
	var key := "foot" if part == 0 else "cart"
	var g: AStarGrid2D = foot if part == 0 else cart
	var cells: Array = st.get(key, [])
	for k in range(0, cells.size() - 1, 2):
		var c := Vector2i(int(cells[k]), int(cells[k + 1]))
		if c.x >= 0 and c.y >= 0 and c.x < dims.x and c.y < dims.y:
			g.set_point_solid(c, true)


## Start dorms: their walls (footprint minus the open interior) and the
## furniture are solid on foot, then each doorway is carved open along its
## axis from the approach to the inside point.
func _r_dorms(_part: int, _parts: int) -> void:
	var passages_of := {}
	for bd in layout.buildings:
		passages_of[String(bd["id"])] = bd["passages"]
	for id in CampusDorms.ids(layout.map_id):
		var g := CampusDorms.geometry(id)
		var pas: Array = passages_of.get(String(g.get("building", "")), [])
		for poly in g["foot"]:
			_solid_poly(foot, poly, FOOT_INF)
		for dr in g["doors"]:
			var a: Vector2 = dr["approach"]
			var b: Vector2 = dr["inside"]
			# a door under a portico: the hall's walls take in the portico
			# floor, so the lane runs on out through it to its step, between
			# the columns (the capsule passes them; a 2 m cell does not)
			var out: Vector2 = dr["normal"]
			var reach := 0.0
			while reach < 8.0 and pas.any(func(ps: Dictionary) -> bool: return Geometry2D.is_point_in_polygon(a + out * (reach + 0.5), ps["poly"])):
				reach += 0.5
			if reach > 0.0:
				a += out * (reach + cell * 0.5)
			var n := maxi(2, int(a.distance_to(b) / (cell * 0.5)))
			for k in n + 1:
				var c := to_cell(a.lerp(b, float(k) / float(n)))
				foot.set_point_solid(c, false)
				foot.set_point_weight_scale(c, 1.0)


func _r_edges(_part: int, _parts: int) -> void:
	# a footbridge's lane is walkable over the water: carved along its axis
	# like a doorway, four-connected (diagonal steps need both side cells)
	for p in layout.platforms:
		if not p.has("carve"):
			continue
		var a: Vector2 = p["carve"][0]
		var b: Vector2 = p["carve"][1]
		var n := maxi(2, int(a.distance_to(b) / (cell * 0.25)))
		var prev := to_cell(a)
		for k in n + 1:
			var c := to_cell(a.lerp(b, float(k) / float(n)))
			for q in [c, Vector2i(c.x, prev.y)]:
				foot.set_point_solid(q, false)
				foot.set_point_weight_scale(q, 1.0)
			prev = c
	# docks / ledge platforms are walkable over the pit
	for p in layout.platforms:
		var pc: Vector3 = p["center"]
		var ps: Vector3 = p["size"]
		if p.get("dock", false):
			for cc in _cells_in_rect(Rect2(Vector2(pc.x, pc.z) - Vector2(ps.x, ps.z) * 0.5 + Vector2(0.6, 0.6), Vector2(ps.x, ps.z) - Vector2(1.2, 1.2))):
				foot.set_point_solid(cc, false)
	# map edge (one cell deep)
	for g in [foot, cart]:
		g.fill_solid_region(Rect2i(0, 0, dims.x, 1))
		g.fill_solid_region(Rect2i(0, dims.y - 1, dims.x, 1))
		g.fill_solid_region(Rect2i(0, 0, 1, dims.y))
		g.fill_solid_region(Rect2i(dims.x - 1, 0, 1, dims.y))


func nearest_open(g: AStarGrid2D, p: Vector2, max_r: int = 8) -> Vector2i:
	var c := to_cell(p)
	if not g.is_point_solid(c):
		return c
	for r in range(1, max_r + 1):
		var best := Vector2i(-1, -1)
		var bd := 1e9
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var q := c + Vector2i(dx, dy)
				if q.x < 0 or q.y < 0 or q.x >= dims.x or q.y >= dims.y:
					continue
				if g.is_point_solid(q):
					continue
				var d := to_world(q).distance_to(p)
				if d < bd:
					bd = d
					best = q
		if best.x >= 0:
			return best
	return c


## World-space path (XZ) from a to b. Empty if unreachable.
func find_path(a: Vector2, b: Vector2, for_cart: bool = false, smooth: bool = true) -> PackedVector2Array:
	var g := cart if for_cart else foot
	var ca := nearest_open(g, a)
	var cb := nearest_open(g, b)
	var cells := g.get_id_path(ca, cb)
	var out := PackedVector2Array()
	if cells.is_empty():
		return out
	if not smooth:
		for c in cells:
			out.append(to_world(c))
		return out
	# string-pull: keep a point only when the straight line from the last kept
	# point would cross a solid or costly cell
	var anchor := 0
	out.append(to_world(cells[0]))
	var i := 2
	while i < cells.size():
		if not _clear_line(g, cells[anchor], cells[i]):
			out.append(to_world(cells[i - 1]))
			anchor = i - 1
		i += 1
	out.append(to_world(cells[cells.size() - 1]))
	return out


# ---------------------------------------------------------------------------
# V6: bounded path work per simulation tick (bots)
# ---------------------------------------------------------------------------
## Measured (V6, src/dev/sim_profile.tscn, the earlier 320x300 1 m grid): bot
## thinking was 97 % of a simulation tick, almost all of it A* on that grid (~6 ms a path
## on the desktop test machine).  Replans cluster (round start, Night Watch
## chases every 0.5 s, flee/stuck replans), so single ticks reached 45-60 ms
## and pushed the 60 Hz physics loop into catch-up (6 ticks per frame): the
## "smooth, then suddenly very glitchy" pattern.  Bots now ask for paths
## here: a clear straight line needs no search; a path to the same goal from
## the same neighbourhood is reused; at most `budget_per_tick` searches run
## in one simulation tick and the rest wait a tick (the bot steers straight
## at its goal meanwhile).  Direct find_path() calls (tools, tests) are
## unchanged.
##
## V8: one search was still the stall.  Measured (src/dev/match_bench.tscn,
## whole bot-driven Practice rounds on the desktop test machine), single
## searches took 20-42 ms (long weighted foot routes, cart routes over the
## lawn), clustered about a second apart while a bot re-planned a far goal,
## and were 15 of the 15 worst frames.  A search now runs on a worker thread
## (one search per grid at a time: AStarGrid2D keeps per-search state in
## its points) and its answer is used on a tick fixed when it was asked:
## ASYNC_DELAY ticks later, and ASYNC_SPACING after the previous queued
## answer for that grid.  If the worker hasn't finished by then, that tick
## waits for it, so the bots' decisions, and every seeded round, are the
## same on every machine (only how long a wait is varies).  The main thread
## only reads the grids' solid/weight cells meanwhile (string-pulling,
## nearest open cell), which a search never writes.
const CACHE_MAX := 192
const CACHE_BUCKET := 3          # start cells per cache key bucket (6 m)
var budget_per_tick := 1
var deferred := false            # the last budgeted request had to wait
var path_stats := {"search": 0, "direct": 0, "cache": 0, "deferred": 0, "unreachable": 0}
const UNREACHABLE_TTL := 300     # ticks (5 s) an unreachable foot start/goal is not searched again
const UNREACHABLE_TTL_CART := 3600  # a cart goal off the road network stays off it (60 s)
var _cache: Dictionary = {}      # key -> PackedVector2Array (world)
var _cache_keys: Array = []
var _unreachable: Dictionary = {} # key -> physics frame of the failed search
## dev profiling only: set to [] to collect searches over 8 ms
var debug_slow_searches = null
var _budget_frame := -1
var _budget_used := 0
## V8: background searches (async_search = false: the V6 budgeted search on
## the calling thread, for tools)
const ASYNC_DELAY := 6           # ticks from request to answer (100 ms)
const ASYNC_SPACING := 2         # ticks between answers on one grid
const QUEUE_MAX := 8             # queued searches per grid (more: asked again next tick)
var async_search := true
var _queues := {false: [], true: []}   # for_cart -> Array[PathJob], oldest first
var _grid_lock := {false: Mutex.new(), true: Mutex.new()}
var stat_waited_us := 0          # main-thread time spent waiting at delivery
var debug_job_sleep_ms := 0      # tests: a slow worker
var stat_wait_n := 0


## One background search: written only by its worker until it completes.
class PathJob:
	extends RefCounted
	var key: Vector4i
	var ukey: Vector4i
	var cart := false
	var due := 0
	var task := -1
	var a: Vector2
	var b: Vector2
	var out := PackedVector2Array()
	var us := 0


func find_path_budgeted(a: Vector2, b: Vector2, for_cart: bool = false) -> PackedVector2Array:
	deferred = false
	if async_search:
		_collect(for_cart, Engine.get_physics_frames())
	var g := cart if for_cart else foot
	var ca := nearest_open(g, a)
	var cb := nearest_open(g, b)
	if ca == cb or _clear_line(g, ca, cb):
		path_stats["direct"] += 1
		return PackedVector2Array([to_world(ca), to_world(cb)])
	var key := Vector4i(int(for_cart), ca.x / CACHE_BUCKET, ca.y / CACHE_BUCKET, cb.x * 4096 + cb.y)
	# an unreachable cart goal (a dorm door, a lawn pocket) is unreachable
	# from the whole road network, so it is remembered by goal alone: a cart
	# moving through new neighbourhoods would otherwise search again from
	# each one (measured: ~20 ms each, every few ticks).  Foot goals keep the
	# start in the key (a runner boxed in somewhere must not block a goal for
	# everyone).
	var ukey := Vector4i(1, -1, -1, cb.x * 4096 + cb.y) if for_cart else key
	if _unreachable.has(ukey):
		if Engine.get_physics_frames() - int(_unreachable[ukey]) < (UNREACHABLE_TTL_CART if for_cart else UNREACHABLE_TTL):
			# a search from here to there explored the whole grid a moment
			# ago and found nothing: don't repeat it every tick
			path_stats["unreachable"] += 1
			return PackedVector2Array()
		_unreachable.erase(ukey)
	if _cache.has(key):
		var cached: PackedVector2Array = _cache[key]
		# reuse from here only if the first leg is clear from this start (a
		# first waypoint on a neighbouring cell is: string-pulling never tests
		# the first step, which may enter a costlier cell)
		var c1 := nearest_open(g, cached[1]) if cached.size() >= 2 else ca
		if cached.size() >= 2 and (_clear_line(g, ca, c1) or maxi(absi(c1.x - ca.x), absi(c1.y - ca.y)) <= 1):
			path_stats["cache"] += 1
			var out := cached.duplicate()
			out[0] = to_world(ca)
			return out
	var f := Engine.get_physics_frames()
	if async_search:
		# queued (now or earlier): steer at the goal until the answer is
		# due, then it is in the cache
		deferred = true
		var q: Array = _queues[for_cart]
		for j: PathJob in q:
			if j.key == key:
				path_stats["deferred"] += 1
				return PackedVector2Array()
		if q.size() >= QUEUE_MAX:
			path_stats["deferred"] += 1
			return PackedVector2Array()
		_start_job(key, ukey, a, b, for_cart, f)
		return PackedVector2Array()
	if f != _budget_frame:
		_budget_frame = f
		_budget_used = 0
	if _budget_used >= budget_per_tick:
		deferred = true
		path_stats["deferred"] += 1
		return PackedVector2Array()
	_budget_used += 1
	path_stats["search"] += 1
	var ts := Time.get_ticks_usec()
	var path := find_path(a, b, for_cart)
	if debug_slow_searches != null:
		var us := Time.get_ticks_usec() - ts
		if us > 8000 and debug_slow_searches.size() < 60:
			debug_slow_searches.append([snapped(a, Vector2(0.1, 0.1)), snapped(b, Vector2(0.1, 0.1)), for_cart, us / 1000.0, path.size()])
	_file(key, ukey, path, f)
	return path


func _file(key: Vector4i, ukey: Vector4i, path: PackedVector2Array, f: int) -> void:
	if path.is_empty():
		if _unreachable.size() > CACHE_MAX:
			_unreachable.clear()
		_unreachable[ukey] = f
	if path.size() >= 2:
		if not _cache.has(key):
			_cache_keys.append(key)
			if _cache_keys.size() > CACHE_MAX:
				_cache.erase(_cache_keys.pop_front())
		_cache[key] = path


func _start_job(key: Vector4i, ukey: Vector4i, a: Vector2, b: Vector2, for_cart: bool, f: int) -> void:
	var job := PathJob.new()
	job.key = key
	job.ukey = ukey
	job.cart = for_cart
	job.a = a
	job.b = b
	var q: Array = _queues[for_cart]
	job.due = f + ASYNC_DELAY
	if not q.is_empty():
		job.due = maxi(job.due, (q[-1] as PathJob).due + ASYNC_SPACING)
	path_stats["search"] += 1
	q.append(job)
	job.task = WorkerThreadPool.add_task(_run_job.bind(job), false, "path search")


## Worker thread: the search only (reads the grid, writes the job).  One
## search per grid at a time.
func _run_job(job: PathJob) -> void:
	var m: Mutex = _grid_lock[job.cart]
	m.lock()
	var ts := Time.get_ticks_usec()
	if debug_job_sleep_ms > 0:
		OS.delay_msec(debug_job_sleep_ms)
	job.out = find_path(job.a, job.b, job.cart)
	job.us = Time.get_ticks_usec() - ts
	m.unlock()


## The answers due by tick `f` on this grid, in order: waits for a worker
## that is not done yet, then files each path in the cache (or its goal as
## unreachable), where the request will find it.
func _collect(for_cart: bool, f: int) -> void:
	var q: Array = _queues[for_cart]
	while not q.is_empty() and (q[0] as PathJob).due <= f:
		var job: PathJob = q.pop_front()
		if not WorkerThreadPool.is_task_completed(job.task):
			stat_wait_n += 1
		var tw := Time.get_ticks_usec()
		WorkerThreadPool.wait_for_task_completion(job.task)
		stat_waited_us += Time.get_ticks_usec() - tw
		if debug_slow_searches != null and job.us > 8000 and debug_slow_searches.size() < 60:
			debug_slow_searches.append([snapped(job.a, Vector2(0.1, 0.1)), snapped(job.b, Vector2(0.1, 0.1)), job.cart, job.us / 1000.0, job.out.size()])
		_file(job.key, job.ukey, job.out, job.due)


## Searches still queued (both grids).
func pending() -> int:
	return (_queues[false] as Array).size() + (_queues[true] as Array).size()


static func settle_shared() -> void:
	if _shared != null:
		_shared.settle()


## Finish every background search now and file the answers (a round
## ending, tests).
func settle() -> void:
	_collect(false, 1 << 62)
	_collect(true, 1 << 62)


func path_length(path: PackedVector2Array) -> float:
	var L := 0.0
	for i in path.size() - 1:
		L += path[i].distance_to(path[i + 1])
	return L


func _clear_line(g: AStarGrid2D, a: Vector2i, b: Vector2i) -> bool:
	var d := b - a
	var steps := maxi(absi(d.x), absi(d.y))
	if steps == 0:
		return true
	var wa := g.get_point_weight_scale(a)
	for s in range(1, steps + 1):
		var t := float(s) / float(steps)
		var c := Vector2i(int(round(lerpf(a.x, b.x, t))), int(round(lerpf(a.y, b.y, t))))
		if g.is_point_solid(c):
			return false
		if g.get_point_weight_scale(c) > wa + 0.5:
			return false
	return g != foot or _clear_sides(g, a, b)


## (NP) On foot a straight walk is as wide as a runner: two lines
## CLEAR_HALF m either side of the centre line, sampled every half cell,
## cross no solid cell either.  The centre line alone, on 2 m cells, passed
## a building corner its cells' centres missed, and a bot slid on it
## for the rest of the round; stricter only keeps more of the raw path.
const CLEAR_HALF := 0.6


func _clear_sides(g: AStarGrid2D, a: Vector2i, b: Vector2i) -> bool:
	var wa := to_world(a)
	var wb := to_world(b)
	var len := wa.distance_to(wb)
	var n := (wb - wa).orthogonal() / len * CLEAR_HALF
	var steps := int(ceil(len / (cell * 0.5)))
	for s in range(1, steps):
		var p := wa.lerp(wb, float(s) / float(steps))
		if g.is_point_solid(to_cell(p + n)) or g.is_point_solid(to_cell(p - n)):
			return false
	return true


func is_walkable(p: Vector2) -> bool:
	return not foot.is_point_solid(to_cell(p))


func is_drivable(p: Vector2) -> bool:
	return not cart.is_point_solid(to_cell(p))
