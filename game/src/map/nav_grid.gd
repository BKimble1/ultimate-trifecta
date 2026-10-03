class_name NavGrid
extends RefCounted
## 1 m navigation grids rasterised from CampusLayout: one for runners/patrol on
## foot (low walls cost extra and are hopped), one for carts (roads preferred,
## bollards/walls/hedges solid, inflated by cart half-width). Uses Godot's
## native AStarGrid2D so path queries are cheap on device.

const CELL := 1.0

var layout: CampusLayout
var origin := Vector2.ZERO
var dims := Vector2i.ZERO
var foot := AStarGrid2D.new()
var cart := AStarGrid2D.new()
var low_wall_cells: Dictionary = {}

static var _shared: NavGrid
## A grid being built in slices under the loading screen (V5).
static var _building: NavGrid
const FOOT_INF := 0.45
const CART_INF := 1.25
## The rasterisation in slices of similar cost (each ~12 ms or less on the
## desktop test machine; V4 built it in one ~50 ms block).
## [method, part, parts]: V6 splits the setup and the heavy passes into
## slices that keep the original order of every write (the finished grid is
## identical; test_prep_jobs), so no single loading step holds a frame for
## long (each pass was 14-18 ms here, the grid setup up to 15 ms; a phone is
## slower).
const PHASES := [["_r_setup", 0, 2], ["_r_setup", 1, 2],
	["_r_roads", 0, 3], ["_r_roads", 1, 3], ["_r_roads", 2, 3],
	["_r_buildings_hedges_fences", 0, 3], ["_r_buildings_hedges_fences", 1, 3], ["_r_buildings_hedges_fences", 2, 3],
	["_r_walls_blockers_trees", 0, 3], ["_r_walls_blockers_trees", 1, 3], ["_r_walls_blockers_trees", 2, 3],
	["_r_rocks", 0, 1],
	["_r_waters", 0, 3], ["_r_waters", 1, 3], ["_r_waters", 2, 3],
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
	origin = CampusLayout.BOUNDS.position
	dims = Vector2i(int(CampusLayout.BOUNDS.size.x), int(CampusLayout.BOUNDS.size.y))
	if not staged:
		_rasterize()


## The grids themselves: the foot grid in the first slice, the cart grid
## (with grass costing carts more than road: V5's one native region fill
## instead of 96,000 single-cell calls) in the second.
func _r_setup(part: int, _parts: int) -> void:
	var g: AStarGrid2D = foot if part == 0 else cart
	g.region = Rect2i(Vector2i.ZERO, dims)
	g.cell_size = Vector2(CELL, CELL)
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
	return Vector2i(clampi(int(floor(p.x - origin.x)), 0, dims.x - 1), clampi(int(floor(p.y - origin.y)), 0, dims.y - 1))


func to_world(c: Vector2i) -> Vector2:
	return Vector2(origin.x + float(c.x) + 0.5, origin.y + float(c.y) + 0.5)


func _cells_in_rect(r: Rect2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var a := to_cell(r.position)
	var b := to_cell(r.end)
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			out.append(Vector2i(x, y))
	return out


func _solid_box(g: AStarGrid2D, center: Vector2, half: Vector2, inflate: float) -> void:
	var r := Rect2(center - half - Vector2(inflate, inflate), (half + Vector2(inflate, inflate)) * 2.0)
	for c in _cells_in_rect(r):
		g.set_point_solid(c, true)


func _solid_segment(g: AStarGrid2D, a: Vector2, b: Vector2, half_t: float, inflate: float) -> void:
	var r := Rect2(a, Vector2.ZERO).expand(b).grow(half_t + inflate + 1.0)
	for c in _cells_in_rect(r):
		var w := to_world(c)
		if CampusLayout._dist_to_segment(w, a, b) <= half_t + inflate:
			g.set_point_solid(c, true)


func _solid_circle(g: AStarGrid2D, center: Vector2, radius: float) -> void:
	var r := Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0).grow(1.0)
	for c in _cells_in_rect(r):
		if to_world(c).distance_to(center) <= radius:
			g.set_point_solid(c, true)


func _rasterize() -> void:
	while step():
		pass


func _r_roads(part: int, parts: int) -> void:
	var sl := _slice(layout.roads.size(), part, parts)
	for ri in range(sl.x, sl.y):
		var r: Dictionary = layout.roads[ri]
		var pts: PackedVector2Array = r["pts"]
		for i in pts.size() - 1:
			var rect := Rect2(pts[i], Vector2.ZERO).expand(pts[i + 1]).grow(float(r["w"]) * 0.5 + 1.0)
			for c in _cells_in_rect(rect):
				if CampusLayout._dist_to_segment(to_world(c), pts[i], pts[i + 1]) <= float(r["w"]) * 0.5:
					cart.set_point_weight_scale(c, 1.0)


func _r_buildings_hedges_fences(part: int, parts: int) -> void:
	var nb := layout.buildings.size()
	var nh := layout.hedges.size()
	var sl := _slice(nb + nh + layout.fences.size(), part, parts)
	var foot_inf := FOOT_INF
	var cart_inf := CART_INF
	for bi in range(sl.x, mini(sl.y, nb)):
		var bd: Dictionary = layout.buildings[bi]
		var half: Vector2 = bd["size"] * 0.5
		var pos: Vector2 = bd["pos"]
		if bd["id"] == "tower":
			_solid_box(cart, pos, half, cart_inf)
			continue  # pedestrian arch under the tower
		if bd.has("dorm_id"):
			# V6 dorm: walls, the closed block and furniture block walking;
			# the common room and its doorways are open.  Carts: all solid.
			for r in CampusDorms.geometry(String(bd["dorm_id"]))["foot"]:
				var rr: Rect2 = r
				_solid_box(foot, rr.get_center(), rr.size * 0.5, foot_inf)
			_solid_box(cart, pos, half, cart_inf)
			continue
		if bd["id"] == "shed":
			var hz := half.y
			_solid_segment(foot, pos + Vector2(-half.x, -hz), pos + Vector2(half.x, -hz), 0.3, foot_inf)
			_solid_segment(foot, pos + Vector2(-half.x, -hz), pos + Vector2(-half.x, hz), 0.3, foot_inf)
			_solid_segment(foot, pos + Vector2(half.x, -hz), pos + Vector2(half.x, hz), 0.3, foot_inf)
			_solid_box(cart, pos, half, cart_inf)
			continue
		_solid_box(foot, pos, half, foot_inf)
		_solid_box(cart, pos, half, cart_inf)
	for hi in range(maxi(sl.x, nb), mini(sl.y, nb + nh)):
		var s: Dictionary = layout.hedges[hi - nb]
		_solid_segment(foot, s["a"], s["b"], float(s["t"]) * 0.5, foot_inf)
		_solid_segment(cart, s["a"], s["b"], float(s["t"]) * 0.5, cart_inf)
	for fi in range(maxi(sl.x, nb + nh), sl.y):
		var s: Dictionary = layout.fences[fi - nb - nh]
		var h: float = s["h"]
		if h <= 1.05:
			# split-rail: hop-able for runners (costly), solid for carts
			var rect := Rect2(s["a"], Vector2.ZERO).expand(s["b"]).grow(1.2)
			for c in _cells_in_rect(rect):
				if CampusLayout._dist_to_segment(to_world(c), s["a"], s["b"]) <= 0.6:
					foot.set_point_weight_scale(c, 6.0)
					low_wall_cells[c] = true
		else:
			_solid_segment(foot, s["a"], s["b"], 0.15, foot_inf)
		_solid_segment(cart, s["a"], s["b"], 0.15, cart_inf)


func _r_walls_blockers_trees(part: int, parts: int) -> void:
	var nw := layout.walls.size()
	var nb := layout.cart_blockers.size()
	var nt := layout.trees.size()
	var sl := _slice(nw + nb + nt + layout.solids.size(), part, parts)
	var foot_inf := FOOT_INF
	var cart_inf := CART_INF
	for wi in range(sl.x, mini(sl.y, nw)):
		var s: Dictionary = layout.walls[wi]
		var rect2 := Rect2(s["a"], Vector2.ZERO).expand(s["b"]).grow(1.2)
		for c in _cells_in_rect(rect2):
			if CampusLayout._dist_to_segment(to_world(c), s["a"], s["b"]) <= float(s["t"]) * 0.5 + 0.4:
				foot.set_point_weight_scale(c, 4.0)
				low_wall_cells[c] = true
		_solid_segment(cart, s["a"], s["b"], float(s["t"]) * 0.5, cart_inf)
	for bi in range(maxi(sl.x, nw), mini(sl.y, nw + nb)):
		var s: Dictionary = layout.cart_blockers[bi - nw]
		_solid_segment(cart, s["a"], s["b"], 0.25, cart_inf)
	for ti in range(maxi(sl.x, nw + nb), mini(sl.y, nw + nb + nt)):
		var t: Dictionary = layout.trees[ti - nw - nb]
		_solid_circle(foot, t["pos"], 0.45 + foot_inf)
		_solid_circle(cart, t["pos"], 0.45 + cart_inf)
	for si in range(maxi(sl.x, nw + nb + nt), sl.y):
		var so: Dictionary = layout.solids[si - nw - nb - nt]
		var ss: Vector3 = so["size"]
		var r := Vector2(ss.x, ss.z).length() * 0.5
		_solid_circle(foot, so["pos"], r + foot_inf * 0.5)
		_solid_circle(cart, so["pos"], r + cart_inf)


func _r_rocks(_part: int, _parts: int) -> void:
	for rk in layout.rocks:
		var rp: Vector3 = rk["pos"]
		var rs: Vector3 = rk["size"]
		_solid_circle(foot, Vector2(rp.x, rp.z), maxf(rs.x, rs.z) * 0.5 + FOOT_INF * 0.5)
		_solid_circle(cart, Vector2(rp.x, rp.z), maxf(rs.x, rs.z) * 0.5 + CART_INF)
	for lp in layout.lamps:
		_solid_circle(cart, lp, 0.2 + CART_INF)


func _r_waters(part: int, parts: int) -> void:
	var sl := _slice(layout.waters.size(), part, parts)
	for wi in range(sl.x, sl.y):
		var w: Dictionary = layout.waters[wi]
		var c2: Vector2 = w["center"]
		var ext := 16
		for cell in _cells_in_rect(Rect2(c2 - Vector2(ext, ext), Vector2(ext, ext) * 2.0)):
			var wp := to_world(cell)
			if CampusLayout.in_water_shape(w, wp, FOOT_INF + float(w.get("rim_t", 0.0)) + 0.1):
				foot.set_point_solid(cell, true)
			if CampusLayout.in_water_shape(w, wp, CART_INF + 0.5):
				cart.set_point_solid(cell, true)


func _r_edges(_part: int, _parts: int) -> void:
	# docks / ledge platforms are walkable over the pit
	for p in layout.platforms:
		var pc: Vector3 = p["center"]
		var ps: Vector3 = p["size"]
		if p.get("dock", false):
			for cell in _cells_in_rect(Rect2(Vector2(pc.x, pc.z) - Vector2(ps.x, ps.z) * 0.5 + Vector2(0.6, 0.6), Vector2(ps.x, ps.z) - Vector2(1.2, 1.2))):
				foot.set_point_solid(cell, false)
	# map edge (two cells deep) and the lake strip north of the rail
	var lake_rows := int(-146.0 - origin.y) + 1
	for g in [foot, cart]:
		g.fill_solid_region(Rect2i(0, 0, dims.x, 2))
		g.fill_solid_region(Rect2i(0, dims.y - 2, dims.x, 2))
		g.fill_solid_region(Rect2i(0, 0, 2, dims.y))
		g.fill_solid_region(Rect2i(dims.x - 2, 0, 2, dims.y))
		if lake_rows > 0:
			g.fill_solid_region(Rect2i(0, 0, dims.x, lake_rows))


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
## Measured (V6, src/dev/sim_profile.tscn): bot thinking was 97 % of a
## simulation tick, almost all of it A* on this 320x300 grid (~6 ms a path
## on the desktop test machine).  Replans cluster (round start, Night Watch
## chases every 0.5 s, flee/stuck replans), so single ticks reached 45-60 ms
## and pushed the 60 Hz physics loop into catch-up (6 ticks per frame): the
## "smooth, then suddenly very glitchy" pattern.  Bots now ask for paths
## here: a clear straight line needs no search; a path to the same goal from
## the same neighbourhood is reused; at most `budget_per_tick` searches run
## in one simulation tick and the rest wait a tick (the bot steers straight
## at its goal meanwhile).  Direct find_path() calls (tools, tests) are
## unchanged.
const CACHE_MAX := 192
const CACHE_BUCKET := 6          # start cells per cache key bucket (6 m)
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


func find_path_budgeted(a: Vector2, b: Vector2, for_cart: bool = false) -> PackedVector2Array:
	deferred = false
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
		# reuse from here only if the first leg is clear from this start
		if cached.size() >= 2 and _clear_line(g, ca, nearest_open(g, cached[1])):
			path_stats["cache"] += 1
			var out := cached.duplicate()
			out[0] = to_world(ca)
			return out
	var f := Engine.get_physics_frames()
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
	return path


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
	return true


func is_walkable(p: Vector2) -> bool:
	return not foot.is_point_solid(to_cell(p))


func is_drivable(p: Vector2) -> bool:
	return not cart.is_point_solid(to_cell(p))
