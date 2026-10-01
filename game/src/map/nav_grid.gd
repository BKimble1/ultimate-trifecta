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


static func shared(lay: CampusLayout) -> NavGrid:
	if _shared == null or _shared.layout != lay:
		_shared = NavGrid.new(lay)
	return _shared


func _init(lay: CampusLayout) -> void:
	layout = lay
	origin = CampusLayout.BOUNDS.position
	dims = Vector2i(int(CampusLayout.BOUNDS.size.x), int(CampusLayout.BOUNDS.size.y))
	for g in [foot, cart]:
		g.region = Rect2i(Vector2i.ZERO, dims)
		g.cell_size = Vector2(CELL, CELL)
		g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		g.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		g.update()
	_rasterize()


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
	var foot_inf := 0.45
	var cart_inf := 1.25
	# grass costs carts more than road
	for y in dims.y:
		for x in dims.x:
			cart.set_point_weight_scale(Vector2i(x, y), 1.8)
	for r in layout.roads:
		var pts: PackedVector2Array = r["pts"]
		for i in pts.size() - 1:
			var rect := Rect2(pts[i], Vector2.ZERO).expand(pts[i + 1]).grow(float(r["w"]) * 0.5 + 1.0)
			for c in _cells_in_rect(rect):
				if CampusLayout._dist_to_segment(to_world(c), pts[i], pts[i + 1]) <= float(r["w"]) * 0.5:
					cart.set_point_weight_scale(c, 1.0)
	for bd in layout.buildings:
		var half: Vector2 = bd["size"] * 0.5
		var pos: Vector2 = bd["pos"]
		if bd["id"] == "tower":
			_solid_box(cart, pos, half, cart_inf)
			continue  # pedestrian arch under the tower
		if bd["id"] == "shed":
			var hz := half.y
			_solid_segment(foot, pos + Vector2(-half.x, -hz), pos + Vector2(half.x, -hz), 0.3, foot_inf)
			_solid_segment(foot, pos + Vector2(-half.x, -hz), pos + Vector2(-half.x, hz), 0.3, foot_inf)
			_solid_segment(foot, pos + Vector2(half.x, -hz), pos + Vector2(half.x, hz), 0.3, foot_inf)
			_solid_box(cart, pos, half, cart_inf)
			continue
		_solid_box(foot, pos, half, foot_inf)
		_solid_box(cart, pos, half, cart_inf)
	for s in layout.hedges:
		_solid_segment(foot, s["a"], s["b"], float(s["t"]) * 0.5, foot_inf)
		_solid_segment(cart, s["a"], s["b"], float(s["t"]) * 0.5, cart_inf)
	for s in layout.fences:
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
	for s in layout.walls:
		var rect2 := Rect2(s["a"], Vector2.ZERO).expand(s["b"]).grow(1.2)
		for c in _cells_in_rect(rect2):
			if CampusLayout._dist_to_segment(to_world(c), s["a"], s["b"]) <= float(s["t"]) * 0.5 + 0.4:
				foot.set_point_weight_scale(c, 4.0)
				low_wall_cells[c] = true
		_solid_segment(cart, s["a"], s["b"], float(s["t"]) * 0.5, cart_inf)
	for s in layout.cart_blockers:
		_solid_segment(cart, s["a"], s["b"], 0.25, cart_inf)
	for t in layout.trees:
		_solid_circle(foot, t["pos"], 0.45 + foot_inf)
		_solid_circle(cart, t["pos"], 0.45 + cart_inf)
	for rk in layout.rocks:
		var rp: Vector3 = rk["pos"]
		var rs: Vector3 = rk["size"]
		_solid_circle(foot, Vector2(rp.x, rp.z), maxf(rs.x, rs.z) * 0.5 + foot_inf * 0.5)
		_solid_circle(cart, Vector2(rp.x, rp.z), maxf(rs.x, rs.z) * 0.5 + cart_inf)
	for lp in layout.lamps:
		_solid_circle(cart, lp, 0.2 + cart_inf)
	for w in layout.waters:
		var c2: Vector2 = w["center"]
		var ext := 16
		for cell in _cells_in_rect(Rect2(c2 - Vector2(ext, ext), Vector2(ext, ext) * 2.0)):
			var wp := to_world(cell)
			if CampusLayout.in_water_shape(w, wp, foot_inf + float(w.get("rim_t", 0.0)) + 0.1):
				foot.set_point_solid(cell, true)
			if CampusLayout.in_water_shape(w, wp, cart_inf + 0.5):
				cart.set_point_solid(cell, true)
	# docks / ledge platforms are walkable over the pit
	for p in layout.platforms:
		var pc: Vector3 = p["center"]
		var ps: Vector3 = p["size"]
		if p.get("dock", false):
			for cell in _cells_in_rect(Rect2(Vector2(pc.x, pc.z) - Vector2(ps.x, ps.z) * 0.5 + Vector2(0.6, 0.6), Vector2(ps.x, ps.z) - Vector2(1.2, 1.2))):
				foot.set_point_solid(cell, false)
	# map edge
	for x in dims.x:
		for y in [0, 1, dims.y - 1, dims.y - 2]:
			foot.set_point_solid(Vector2i(x, y), true)
			cart.set_point_solid(Vector2i(x, y), true)
	for y in dims.y:
		for x in [0, 1, dims.x - 1, dims.x - 2]:
			foot.set_point_solid(Vector2i(x, y), true)
			cart.set_point_solid(Vector2i(x, y), true)
	# the lake strip north of the rail
	for y in range(0, int(-146.0 - origin.y) + 1):
		for x in dims.x:
			foot.set_point_solid(Vector2i(x, y), true)
			cart.set_point_solid(Vector2i(x, y), true)


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
