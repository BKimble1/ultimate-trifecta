class_name CampusBuilder
extends RefCounted
## Generates collision and visuals for the reference campus from CampusLayout.
##
## Collision (build_collision, the height field) is authoritative and comes
## from the data alone, so host and guests build identical worlds:
##   * one square 1 m height field over BOUNDS (flat ground at y = 0, every
##     water a basin at its floor with a bank: soft for ponds and the lake,
##     hard behind a rim for fountains and pools);
##   * buildings as convex prisms (the footprint minus genuine open passages
##     and the start dorms' interiors, which get a slab overhead);
##   * walls, hedges, fences, bollards (cart-only), tree trunks, lamp posts,
##     benches, water rims, decks and ramps;
##   * invisible walls along the play boundary.
##
## Visuals are built in short staged steps under the loading screen
## (begin_visuals / step), once per session:
##   * merged per-chunk meshes (MeshKit) for ground, surfaces (fields, lots,
##     plazas, roads, paths), buildings and props, with a material id per
##     vertex for the world shaders' detail patterns and the light field
##     (CampusKit) sampled on the GPU;
##   * the Blender kit (CampusKit) as chunked MultiMeshes: trees by species
##     with authored LODs, shrubs, rocks and the woods beyond the boundary;
##   * the waters (CampusLandmarks) and the buildings (CampusArchitecture).

const CHUNK := Vector2(64.0, 64.0)
const WORLD_SHADER := preload("res://assets/shaders/world_vc.gdshader")
const FOLIAGE_SHADER := preload("res://assets/shaders/world_foliage.gdshader")
const WATER_SHADER := preload("res://assets/shaders/water.gdshader")
const GLOW_SHADER := preload("res://assets/shaders/glow_add.gdshader")
const DETAIL_A := preload("res://assets/campus/campus_detail_a.png")
const DETAIL_B := preload("res://assets/campus/campus_detail_b.png")
## Near-field detail (lamps, bollards, window frames) stops drawing beyond this.
const DETAIL_M := 100.0
## Whole chunks (ground, surfaces, buildings) stop drawing beyond this
## (measured to the chunk centre; the night fog ends at 300 m).
const CHUNK_END_M := 380.0

var L: CampusLayout
var _chunks: Dictionary = {}     # chunk key -> MeshKit (ground, surfaces, buildings)
var _foliage: Dictionary = {}    # chunk key -> MeshKit (hedges, swaying things)
var _detail: Dictionary = {}     # chunk key -> MeshKit (near-field detail)
var _glow_st: SurfaceTool
var _glow_count := 0
## the shared canopy material (MatchController feeds it the followed character)
var foliage_material: ShaderMaterial


func _init(layout: CampusLayout) -> void:
	L = layout


# ---------------------------------------------------------------------------
# Height field (shared by collision + visuals)
# ---------------------------------------------------------------------------
static var _grid_cache: PackedFloat32Array
static var _grid_layout: CampusLayout
const BANK_SOFT := 2.6
const BANK_HARD := 0.6


static func ground_y(layout: CampusLayout, x: float, z: float) -> float:
	return grid_y(layout, x, z)


## 1 m height grid over BOUNDS (row-major z, x; sample (i, j) sits at
## BOUNDS.position + (i, j)), cached per layout.  Each water is scanline-
## filled, then a chamfer distance inward from its edge shapes the bank.
static func height_grid(layout: CampusLayout) -> PackedFloat32Array:
	if _grid_layout == layout and not _grid_cache.is_empty():
		return _grid_cache
	var b := CampusLayout.BOUNDS
	var w := int(b.size.x) + 1
	var d := int(b.size.y) + 1
	var data := PackedFloat32Array()
	data.resize(w * d)
	data.fill(0.0)
	for wt in layout.waters:
		var rect: Rect2 = (wt["rect"] as Rect2).grow(1.0)
		var i0 := clampi(int(floor(rect.position.x - b.position.x)), 0, w - 1)
		var j0 := clampi(int(floor(rect.position.y - b.position.y)), 0, d - 1)
		var i1 := clampi(int(ceil(rect.end.x - b.position.x)), 0, w - 1)
		var j1 := clampi(int(ceil(rect.end.y - b.position.y)), 0, d - 1)
		var rw := i1 - i0 + 1
		var rd := j1 - j0 + 1
		if rw <= 0 or rd <= 0:
			continue
		var inside := PackedByteArray()
		inside.resize(rw * rd)
		inside.fill(0)
		for poly in wt["polys"]:
			for jj in rd:
				var z := b.position.y + float(j0 + jj)
				var xs := scan_row(poly, z)
				for k in range(0, xs.size() - 1, 2):
					var xa := int(ceil(xs[k] - b.position.x)) - i0
					var xb := int(floor(xs[k + 1] - b.position.x)) - i0
					for ii in range(maxi(xa, 0), mini(xb, rw - 1) + 1):
						inside[jj * rw + ii] = 1
		var dist := chamfer_inside(inside, rw, rd)
		var bank := BANK_HARD if float(wt["rim_h"]) > 0.0 or String(wt["kind"]) in ["fountain", "pool"] else BANK_SOFT
		var fl := float(wt["floor_y"])
		for jj in rd:
			for ii in rw:
				var dd := dist[jj * rw + ii]
				if dd <= 0.0:
					continue
				var y := fl * smoothstep(0.0, bank, dd)
				var idx := (j0 + jj) * w + (i0 + ii)
				data[idx] = minf(data[idx], y)
	_grid_cache = data
	_grid_layout = layout
	return data


## x positions where a polygon's boundary crosses the horizontal line z,
## sorted (pairs bound the inside spans).
static func scan_row(poly: PackedVector2Array, z: float) -> PackedFloat32Array:
	var xs := PackedFloat32Array()
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var c := poly[(i + 1) % n]
		if (a.y <= z and c.y > z) or (c.y <= z and a.y > z):
			xs.append(a.x + (z - a.y) / (c.y - a.y) * (c.x - a.x))
	xs.sort()
	return xs


## Distance (m, 1 m cells) from each inside cell to the nearest outside
## cell: a two-pass 3-4 chamfer transform; 0 outside.
static func chamfer_inside(inside: PackedByteArray, w: int, d: int) -> PackedFloat32Array:
	var big := 1e6
	var dist := PackedFloat32Array()
	dist.resize(w * d)
	for i in w * d:
		dist[i] = big if inside[i] == 1 else 0.0
	for j in d:
		for i in w:
			var idx := j * w + i
			if dist[idx] == 0.0:
				continue
			var v := dist[idx]
			if i > 0:
				v = minf(v, dist[idx - 1] + 1.0)
			else:
				v = minf(v, 1.0)
			if j > 0:
				v = minf(v, dist[idx - w] + 1.0)
				if i > 0:
					v = minf(v, dist[idx - w - 1] + 1.414)
				if i < w - 1:
					v = minf(v, dist[idx - w + 1] + 1.414)
			else:
				v = minf(v, 1.0)
			dist[idx] = v
	for j in range(d - 1, -1, -1):
		for i in range(w - 1, -1, -1):
			var idx := j * w + i
			if dist[idx] == 0.0:
				continue
			var v := dist[idx]
			if i < w - 1:
				v = minf(v, dist[idx + 1] + 1.0)
			else:
				v = minf(v, 1.0)
			if j < d - 1:
				v = minf(v, dist[idx + w] + 1.0)
				if i < w - 1:
					v = minf(v, dist[idx + w + 1] + 1.414)
				if i > 0:
					v = minf(v, dist[idx + w - 1] + 1.414)
			else:
				v = minf(v, 1.0)
			dist[idx] = v
	return dist


static func grid_y(layout: CampusLayout, x: float, z: float) -> float:
	var b := CampusLayout.BOUNDS
	var xi := clampi(int(round(x - b.position.x)), 0, int(b.size.x))
	var zi := clampi(int(round(z - b.position.y)), 0, int(b.size.y))
	return height_grid(layout)[zi * (int(b.size.x) + 1) + xi]


static func water_at(layout: CampusLayout, p: Vector2) -> int:
	return layout.water_index_at(p)


# ---------------------------------------------------------------------------
# Collision
# ---------------------------------------------------------------------------
func build_collision(root: Node3D) -> void:
	var world := StaticBody3D.new()
	world.name = "WorldCollision"
	world.collision_layer = TC.L_WORLD
	world.collision_mask = 0
	var blockers := StaticBody3D.new()
	blockers.name = "CartBlockers"
	blockers.collision_layer = TC.L_CART_BLOCK
	blockers.collision_mask = 0
	# shapes go on the bodies before they enter the tree: added one by one to
	# a body already in the physics space, each one rebuilt the body's
	# compound shape
	_add_shape(world, ground_shape(L), Transform3D(Basis.IDENTITY, ground_shape_origin()))

	var dorm_of: Dictionary = {}
	for id in CampusDorms.ids():
		dorm_of[String(CampusDorms.geometry(id).get("building", ""))] = id
	for bd in L.buildings:
		if bool(bd["background"]):
			continue
		_building_collision(world, bd, String(dorm_of.get(bd["id"], "")))
	for s in L.walls:
		_seg(world, s["a"], s["b"], 0.0, s["h"], s["t"])
	for s in L.hedges:
		_seg(world, s["a"], s["b"], 0.0, s["h"], s["t"])
	for s in L.fences:
		_seg(world, s["a"], s["b"], 0.0, s["h"], 0.25)
	for s in L.cart_blockers:
		_seg(blockers, s["a"], s["b"], 0.0, 1.6, 0.5)
	for t in L.trees:
		if not bool(t.get("collide", true)):
			continue
		var tp: Vector2 = t["pos"]
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.42
		cyl.height = 4.0
		_add_shape(world, cyl, Transform3D(Basis.IDENTITY, Vector3(tp.x, grid_y(L, tp.x, tp.y) + 2.0, tp.y)))
	for r in L.rocks:
		_box(world, r["pos"] + Vector3(0, float(r["size"].y) * 0.5, 0), r["size"], float(r["rot"]))
	for p in L.platforms:
		_box(world, p["center"] - Vector3(0, float(p["size"].y) * 0.5, 0), p["size"], float(p.get("yaw", 0.0)))
	for rp in L.ramps:
		_ramp(world, rp["from"], rp["to"], rp["w"])
	for lp in L.lamps:
		var c2 := CylinderShape3D.new()
		c2.radius = 0.14
		c2.height = 3.4
		_add_shape(world, c2, Transform3D(Basis.IDENTITY, Vector3(lp.x, 1.7, lp.y)))
	for bn in L.benches:
		var bp: Vector2 = bn["pos"]
		_box(world, Vector3(bp.x, 0.25, bp.y), Vector3(1.9, 0.5, 0.7), float(bn["rot"]))
	for so in L.solids:
		var sp: Vector2 = so["pos"]
		var ss: Vector3 = so["size"]
		_box(world, Vector3(sp.x, ss.y * 0.5, sp.y), ss, float(so["rot"]))
	for pr in L.props:
		var ps := CampusArchitecture.prop_collider(pr)
		if ps != Vector3.ZERO:
			var pp: Vector2 = pr["pos"]
			_box(world, Vector3(pp.x, ps.y * 0.5, pp.y), ps, float(pr["rot"]))
	# water rims (fountains, pools): a low wall around every hard edge
	for wt in L.waters:
		var rim := float(wt.get("rim_h", 0.0))
		if rim <= 0.0:
			continue
		var th := float(wt.get("rim_t", 0.5))
		for poly in wt["polys"]:
			var cp := CampusData.ccw(poly)
			var n := cp.size()
			for i in n:
				var a := cp[i]
				var c := cp[(i + 1) % n]
				var dd := (c - a).normalized()
				var out := Vector2(dd.y, -dd.x) * (th * 0.5)
				_seg(world, a + out, c + out, 0.0, rim, th)
	# the play boundary: invisible walls, tall
	var bp2 := L.play_boundary
	for i in bp2.size():
		_seg(world, bp2[i], bp2[(i + 1) % bp2.size()], -2.0, 14.0, 1.0)
	root.add_child(world)
	root.add_child(blockers)


## One building: convex prisms of what is solid at ground level (the
## footprint or its parts, minus open passages and a start dorm's interior),
## raised parts from their base, and slabs over the open spaces.
func _building_collision(world: StaticBody3D, bd: Dictionary, dorm_id: String) -> void:
	for e in bd["entrances"]:
		for cp in CampusArchitecture.portico_columns(e):
			_box(world, Vector3(cp.x, 3.0, cp.y), Vector3(0.62, 6.0, 0.62))
	if bd.get("landmark") != null and String(bd["landmark"]) == "bell_tower":
		for so in CampusTower.solids(bd):
			for cv in CampusData.convex_pieces(so["poly"]):
				_prism(world, cv, float(so["base"]), float(so["h"]))
		return
	var holes: Array = []
	for ps in bd["passages"]:
		holes.append(ps["poly"])
	var g: Dictionary = CampusDorms.geometry(dorm_id) if dorm_id != "" else {}
	if not g.is_empty():
		holes.append_array(g["interior"])
	var parts: Array = bd["parts"]
	if parts.is_empty():
		parts = [{"poly": bd["poly"], "h": float(bd["h"]), "base": 0.0}]
	for part in parts:
		var h := float(part["h"])
		var base := float(part.get("base", 0.0))
		if h <= base + 0.05:
			continue
		if base < 1.0:
			for piece in CampusData.subtract(part["poly"], holes):
				for cv in CampusData.convex_pieces(piece):
					_prism(world, cv, 0.0, h)
		else:
			for cv in CampusData.convex_pieces(part["poly"]):
				_prism(world, cv, base, h)
	var top := float(bd["h"])
	for ps in bd["passages"]:
		var clear := float(ps["clear"])
		if top > clear + 0.05:
			for cv in CampusData.convex_pieces(ps["poly"]):
				_prism(world, cv, clear, top)
	if not g.is_empty():
		var ceil_y := float(g["ceil"])
		for ip in g["interior"]:
			for cv in CampusData.convex_pieces(ip):
				_prism(world, cv, ceil_y, maxf(top, ceil_y + 0.5))
		for bx in g["boxes"]:
			_box(world, bx[0], bx[1], float(bx[3]))


func _prism(body: CollisionObject3D, poly: PackedVector2Array, y0: float, y1: float) -> void:
	var pts := PackedVector3Array()
	for p in poly:
		pts.append(Vector3(p.x, y0, p.y))
		pts.append(Vector3(p.x, y1, p.y))
	var cs := ConvexPolygonShape3D.new()
	cs.points = pts
	_add_shape(body, cs, Transform3D.IDENTITY)


static var _hm_shape: HeightMapShape3D
static var _hm_layout: CampusLayout


## The ground height field, shared by every round's collision (host sim and
## client world alike), so the physics engine builds it once.  It is square
## on purpose: Jolt only makes a real height field from a square map (and
## falls back to a huge triangle mesh otherwise).  The extra rows lie beyond
## the play boundary at ground level.
static func ground_shape(layout: CampusLayout) -> HeightMapShape3D:
	if _hm_layout == layout and _hm_shape != null:
		return _hm_shape
	var b := CampusLayout.BOUNDS
	var w := int(b.size.x) + 1
	var d := int(b.size.y) + 1
	var n := maxi(w, d)
	var grid := height_grid(layout)
	var data := PackedFloat32Array()
	data.resize(n * n)
	data.fill(0.0)
	for zi in d:
		for xi in w:
			var v := grid[zi * w + xi]
			if v != 0.0:
				data[zi * n + xi] = v
	var hm := HeightMapShape3D.new()
	hm.map_width = n
	hm.map_depth = n
	hm.map_data = data
	_hm_shape = hm
	_hm_layout = layout
	return hm


## Where the square ground shape sits (its samples start at BOUNDS' corner).
static func ground_shape_origin() -> Vector3:
	var b := CampusLayout.BOUNDS
	var n := maxi(int(b.size.x), int(b.size.y))
	return Vector3(b.position.x + n * 0.5, 0.0, b.position.y + n * 0.5)


## Drops the static caches (tests that swap the campus data).
static func drop_caches() -> void:
	_grid_cache = PackedFloat32Array()
	_grid_layout = null
	_hm_shape = null
	_hm_layout = null


func _add_shape(body: CollisionObject3D, shape: Shape3D, xf: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xf
	body.add_child(cs)


func _box(body: CollisionObject3D, center: Vector3, size: Vector3, yaw: float = 0.0) -> void:
	var bs := BoxShape3D.new()
	bs.size = size
	_add_shape(body, bs, Transform3D(Basis(Vector3.UP, yaw), center))


func _seg(body: CollisionObject3D, a: Vector2, b: Vector2, y0: float, h: float, t: float) -> void:
	var dd := b - a
	var L2 := dd.length()
	if L2 < 0.01:
		return
	var yaw := atan2(-dd.y, dd.x)
	var c := (a + b) * 0.5
	_box(body, Vector3(c.x, y0 + h * 0.5, c.y), Vector3(L2 + t, h, t), yaw)


func _ramp(body: CollisionObject3D, from: Vector3, to: Vector3, w: float) -> void:
	var d := to - from
	var len := d.length()
	var x_axis := d.normalized()
	var z_axis := x_axis.cross(Vector3.UP).normalized()
	var y_axis := z_axis.cross(x_axis).normalized()
	var basis := Basis(x_axis * len, y_axis * 0.4, z_axis * w)
	var center := (from + to) * 0.5 - y_axis * 0.2
	var bs := BoxShape3D.new()
	bs.size = Vector3.ONE
	_add_shape(body, bs, Transform3D(basis, center))


# ---------------------------------------------------------------------------
# Visual chunks
# ---------------------------------------------------------------------------
## detail: small near-field props (lamps, bollards, benches, window frames)
## in their own per-chunk mesh that stops drawing beyond DETAIL_M.
func _kit_at(x: float, z: float, foliage: bool = false, detail: bool = false) -> MeshKit:
	var key := chunk_key(x, z)
	var store := _foliage if foliage else (_detail if detail else _chunks)
	if not store.has(key):
		store[key] = MeshKit.new()
	return store[key]


## The chunk mesh kit for a world point (public: architecture and landmarks).
func kit_at(x: float, z: float, foliage: bool = false, detail: bool = false) -> MeshKit:
	return _kit_at(x, z, foliage, detail)


static func chunk_key(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor((x - CampusLayout.BOUNDS.position.x) / CHUNK.x)), int(floor((z - CampusLayout.BOUNDS.position.y) / CHUNK.y)))


static func chunk_center(key: Vector2i, scale: float = 1.0) -> Vector3:
	var b := CampusLayout.BOUNDS.position
	return Vector3(b.x + (float(key.x) + 0.5) * CHUNK.x * scale, 0.0, b.y + (float(key.y) + 0.5) * CHUNK.y * scale)


## Coarser batches (2 x 2 chunks): tree shadow proxies; the woods beyond the
## boundary use 3 x 3.
static func coarse_key(x: float, z: float, scale: float = 2.0) -> Vector2i:
	return Vector2i(int(floor((x - CampusLayout.BOUNDS.position.x) / (CHUNK.x * scale))), int(floor((z - CampusLayout.BOUNDS.position.y) / (CHUNK.y * scale))))


## Builds the whole campus look at once (dev shots, tests).
func build_visuals(root: Node3D, quality: int = 1) -> Dictionary:
	begin_visuals(root, quality)
	while step():
		pass
	return water_nodes


# Staged build: the visual work as a queue of short steps (a building, a band
# of ground, one chunk's mesh) so a loading screen keeps animating while the
# campus is made.  A step returning true runs again (chunk commits).
var water_nodes: Dictionary = {}
var container: Node3D
var _steps: Array[Callable] = []
## a short name per step (diagnostics: dev_shots and test_campus_art time them)
var step_names: PackedStringArray = PackedStringArray()
var _step_i := 0
var _quality := 1
var _root: Node3D
var _commit_keys: Array = []
var _commit_started := false
var _world_mat: ShaderMaterial
var kit: CampusKit
var arch: CampusArchitecture
var marks: CampusLandmarks
var dorm_art: DormArt
var _trees: Dictionary = {}       # chunk key -> {species: [[Transform3D, tint, custom], ...]}
var _decor: Dictionary = {}       # coarse key -> {kind: [[Transform3D, tint, custom], ...]}
var _far: Dictionary = {}         # 3x coarse key -> {species: [...]} (woods beyond the bounds)
var _proxy: Dictionary = {}       # coarse key -> {family: [...]} (tree shadow casters)
var _field_tex: ImageTexture
var _mm_queue: Array = []
var _mm_started := false


func begin_visuals(root: Node3D, quality: int = 1) -> void:
	_chunks.clear()
	_foliage.clear()
	_detail.clear()
	_glow_st = SurfaceTool.new()
	_glow_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_glow_count = 0
	_quality = quality
	_root = root
	_step_i = 0
	_steps.clear()
	step_names.clear()
	_trees.clear()
	_decor.clear()
	_far.clear()
	_proxy.clear()
	_commit_keys.clear()
	_commit_started = false
	_mm_queue.clear()
	_mm_started = false
	water_nodes = {}
	arch = CampusArchitecture.new(self)
	marks = CampusLandmarks.new(self)
	dorm_art = DormArt.new(self, arch)
	_add("kit", func() -> void: CampusKit.load_kit(quality))
	_add("light_trees", func() -> void:
		kit = CampusKit.new(L, false)
		kit.stamp_trees())
	_add("light_buildings", func() -> void:
		kit.stamp_buildings()
		kit.stamp_barriers())
	_add("light_lamps", func() -> void:
		kit.stamp_lights()
		kit.stamp_paths())
	var nx := int(ceil(CampusLayout.BOUNDS.size.x / CHUNK.x))
	var nz := int(ceil(CampusLayout.BOUNDS.size.y / CHUNK.y))
	for gz in nz:
		for gx in nx:
			_add("ground", func() -> void: _ground_chunk(Vector2i(gx, gz)))
	for ai in range(0, L.areas.size(), 4):
		_add("areas", func() -> void:
			for i in range(ai, mini(ai + 4, L.areas.size())):
				_area(L.areas[i]))
	for ri in range(0, L.roads.size(), 3):
		_add("roads", func() -> void:
			for i in range(ri, mini(ri + 3, L.roads.size())):
				_road(L.roads[i]))
	for pi in range(0, L.paths.size(), 6):
		_add("paths", func() -> void:
			for i in range(pi, mini(pi + 6, L.paths.size())):
				_path(L.paths[i]))
	var dorm_buildings: Dictionary = {}
	for id in CampusDorms.ids():
		dorm_buildings[String(CampusDorms.geometry(id).get("building", ""))] = true
	for bd in L.buildings:
		if dorm_buildings.has(String(bd["id"])):
			continue      # DormArt builds it, with its open doorways
		_add("building_" + String(bd["id"]), func() -> void: arch.building(bd))
	for id in CampusDorms.ids():
		_add("dorm_" + id, func() -> void: dorm_art.dorm(id))
	_add("walls", arch.walls)
	for hi in range(0, L.hedges.size(), 8):
		_add("hedges", func() -> void: arch.hedges(hi, hi + 8))
	for fi in range(0, L.fences.size(), 8):
		_add("fences", func() -> void: arch.fences(fi, fi + 8))
	_add("bollards", func() -> void: arch.bollards(0, L.cart_blockers.size()))
	_add("trees", _place_trees)
	for li in range(0, L.lamps.size(), 20):
		_add("lamps", func() -> void: arch.lamps(li, li + 20))
	_add("small", arch.small_things)
	_add("light_texture", func() -> void: _field_tex = kit.field_texture())
	_add("background", marks.background)
	_add("shader_world", func() -> void: _warm_material(WORLD_SHADER))
	_add("shader_foliage", func() -> void: _warm_material(FOLIAGE_SHADER))
	_add("shader_water", func() -> void: _warm_material(WATER_SHADER))
	_add("containers", _containers)
	for wi in L.waters.size():
		_add("water_" + String(L.waters[wi]["id"]), func() -> void: marks.water(wi))
	_add("commit", _commit_next)
	_add("multimesh", _mm_next)
	_add("glow", _glow_mesh)


func _add(step_name: String, f: Callable) -> void:
	_steps.append(f)
	step_names.append(step_name)


## Runs the next step; true while there is more to do.
func step() -> bool:
	if _step_i >= _steps.size():
		return false
	var more: Variant = _steps[_step_i].call()
	if not (more is bool and more):
		_step_i += 1
	if _step_i < _steps.size():
		return true
	_release()
	return false


## The round was cancelled mid-build (Cancel on the loading screen).
## Returns the chunk jobs still on the worker pool; the caller waits for
## each only once it has finished, so cancelling never blocks a frame.
func abort() -> Array[int]:
	var ids: Array[int] = []
	for item in _commit_keys:
		ids.append(int(item[2]))
	_commit_keys.clear()
	_step_i = step_names.size()
	_release()
	return ids


## The build is over (finished or cancelled): drop everything only the
## build needed.  Only what the round reads afterwards is kept: container,
## water_nodes, foliage_material and step_names.
func _release() -> void:
	_steps.clear()
	arch = null
	marks = null
	dorm_art = null
	kit = null
	_root = null
	_glow_st = null
	_world_mat = null
	_field_tex = null
	for d: Dictionary in [_chunks, _foliage, _detail, _trees, _decor, _far, _proxy]:
		d.clear()
	_mm_queue.clear()
	_commit_keys.clear()


## The name of the step step() will run next (diagnostics).
func next_step_name() -> String:
	return step_names[_step_i] if _step_i < step_names.size() else ""


## Fraction of the steps done (loading screen progress, never invented).
func progress() -> float:
	return float(_step_i) / float(maxi(step_names.size(), 1))


func mm_add(store_name: String, p: Vector3, kind: String, xf: Transform3D, tint: Color, custom: Color) -> void:
	match store_name:
		"trees":
			_mm_add(_trees, chunk_key(p.x, p.z), kind, xf, tint, custom)
		"decor":
			_mm_add(_decor, coarse_key(p.x, p.z), kind, xf, tint, custom)
		"far":
			_mm_add(_far, coarse_key(p.x, p.z, 3.0), kind, xf, tint, custom)
		"proxy":
			_mm_add(_proxy, coarse_key(p.x, p.z), kind, xf, tint, custom)


func _mm_add(store: Dictionary, key: Vector2i, kind: String, xf: Transform3D, tint: Color, custom: Color) -> void:
	if not store.has(key):
		store[key] = {}
	var per: Dictionary = store[key]
	if not per.has(kind):
		per[kind] = []
	(per[kind] as Array).append([xf, tint, custom])


## One MultiMesh instance per tree, by species (visual only - the trunk
## collider and nav cell come from CampusLayout): uniform scale to its
## height, a turn, a gentle tint.  Shrubs go to the decor batches.
func _place_trees() -> void:
	for t in L.trees:
		var p: Vector2 = t["pos"]
		var y := grid_y(L, p.x, p.y)
		var yaw := fposmod(p.x * 1.7 + p.y * 2.3, TAU)
		if String(t["kind"]) == "shrub":
			var r := float(t["r"])
			var s := clampf(r / 0.9, 0.5, 2.6)
			var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s * 0.8, s)), Vector3(p.x, y, p.y))
			# bushes: rounded and tall forms (no spring bloom on an autumn night)
			var form := "shrub_round" if CampusKit._hash01(p.x, p.y, 3) < 0.65 else "shrub_tall"
			_mm_add(_decor, coarse_key(p.x, p.y), form, xf, CampusKit.tint_of(t), Color(0.22, 0.42, 0.24) * CampusKit.tint_of(t).v)
			continue
		var sp := CampusKit.species_of(t)
		var sc: float = float(t["h"]) / CampusKit.REF_H
		var xf2 := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc)), Vector3(p.x, y, p.y))
		_mm_add(_trees, chunk_key(p.x, p.y), sp, xf2, CampusKit.tint_of(t), Color(1, 1, 1))
		_mm_add(_proxy, coarse_key(p.x, p.y), "fir" if sp in CampusKit.CONIFER else "oak", xf2, Color(1, 1, 1), Color(1, 1, 1))
	_merge_species()


## Keeps tree batches few: a chunk with more than three species draws its
## rarest ones as the commonest species of the same family.  Visual only.
func _merge_species() -> void:
	for key in _trees:
		var per: Dictionary = _trees[key]
		while per.size() > 3:
			var names: Array = per.keys()
			names.sort_custom(func(a: String, b: String) -> bool: return (per[a] as Array).size() < (per[b] as Array).size())
			var rare: String = names[0]
			var fam := rare in CampusKit.CONIFER
			var into := ""
			for nm in names.slice(1):
				if (String(nm) in CampusKit.CONIFER) == fam:
					into = nm
			if into == "":
				into = names[names.size() - 1]
			(per[into] as Array).append_array(per[rare])
			per.erase(rare)


## A material's shader is compiled on first use: one step per shader, so no
## other work shares those frames (on the main thread).
func _warm_material(sh: Shader) -> void:
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("active" if sh == WATER_SHADER else "emission_boost", 1.0 if sh == WATER_SHADER else 1.6)
	sh.get_shader_uniform_list()


func world_material() -> ShaderMaterial:
	return _world_mat


func field_texture() -> ImageTexture:
	return _field_tex


func field_params() -> Dictionary:
	return kit.field_params() if kit != null else {}


func _containers() -> void:
	_world_mat = ShaderMaterial.new()
	_world_mat.shader = WORLD_SHADER
	var fmat := ShaderMaterial.new()
	fmat.shader = FOLIAGE_SHADER
	var field := kit.field_params()
	for m: ShaderMaterial in [_world_mat, fmat]:
		m.set_shader_parameter("detail_a", DETAIL_A)
		m.set_shader_parameter("detail_b", DETAIL_B)
		m.set_shader_parameter("detail_level", 1.0 if _quality >= 1 else 0.55)
		m.set_shader_parameter("light_field", _field_tex)
		m.set_shader_parameter("field_on", 1.0)
		for pk in field:
			m.set_shader_parameter(pk, field[pk])
	foliage_material = fmat
	container = Node3D.new()
	container.name = "CampusVisuals"
	_root.add_child(container)


## Chunk meshes: every chunk's ArrayMesh is packed on the worker thread
## pool (the heaviest native work of the build), then each step adds the
## finished ones to the scene.
func _commit_next() -> bool:
	if not _commit_started:
		_commit_started = true
		for pass_i in 3:
			var store: Dictionary = [_chunks, _foliage, _detail][pass_i]
			for key in store:
				var mk: MeshKit = store[key]
				if mk.is_empty():
					continue
				var out := []
				var tid := WorkerThreadPool.add_task(func() -> void: out.append(mk.commit()), false, "campus chunk")
				_commit_keys.append([pass_i, key, tid, out])
		return true
	var budget := Time.get_ticks_usec()
	while not _commit_keys.is_empty() and Time.get_ticks_usec() - budget < 3000:
		var item: Array = _commit_keys[0]
		if not WorkerThreadPool.is_task_completed(item[2]):
			return true
		WorkerThreadPool.wait_for_task_completion(item[2])
		_commit_keys.pop_front()
		var pass_i: int = item[0]
		var key: Vector2i = item[1]
		var mesh: ArrayMesh = (item[3] as Array)[0] if not (item[3] as Array).is_empty() else null
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = foliage_material if pass_i == 1 else _world_mat
		mi.name = (["Chunk_%d_%d", "Foliage_%d_%d", "Detail_%d_%d"][pass_i]) % [key.x, key.y]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (_quality >= 1 and pass_i == 0) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		if pass_i == 2:
			mi.visibility_range_end = DETAIL_M if _quality >= 1 else DETAIL_M * 0.7
		else:
			mi.visibility_range_end = CHUNK_END_M if _quality >= 1 else CHUNK_END_M * 0.8
		container.add_child(mi)
	return not _commit_keys.is_empty()


## Trees (by species) and decor (by kind) for one batch per call, each a
## MultiMesh with the kit's authored LODs.  Trees cast through a separate
## low-poly shadow proxy (Standard only).
const TREE_END_M := 260.0
func _mm_next() -> bool:
	if not _mm_started:
		_mm_started = true
		for key in _trees:
			_mm_queue.append([_trees, key, 1.0])
		for key in _decor:
			_mm_queue.append([_decor, key, 2.0])
		for key in _far:
			_mm_queue.append([_far, key, 3.0])
		for key in _proxy:
			_mm_queue.append([_proxy, key, 2.0])
	if _mm_queue.is_empty():
		return false
	var item: Array = _mm_queue.pop_front()
	var store: Dictionary = item[0]
	var key: Vector2i = item[1]
	var per: Dictionary = store[key]
	var center := chunk_center(key, item[2])
	for kind: String in per:
		var list: Array = per[kind]
		if store == _trees or store == _far:
			var mmi := _mmi(CampusKit.lod_mesh("tree_" + kind), list, center, foliage_material, false)
			mmi.name = ("Trees_%s_%d_%d" if store == _trees else "Woods_%s_%d_%d") % [kind, key.x, key.y]
			mmi.visibility_range_end = TREE_END_M if _quality >= 1 else 170.0
			if store == _far:
				mmi.visibility_range_end += 120.0
			container.add_child(mmi)
		elif store == _proxy:
			if _quality < 1:
				continue
			var sh := _mmi(CampusKit.kit_mesh("tree_%s_2" % kind), list, center, _world_mat, false)
			sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			sh.name = "TreeShadows_%s_%d_%d" % [kind, key.x, key.y]
			sh.visibility_range_end = 150.0
			container.add_child(sh)
		else:
			var rock := kind.begins_with("rock")
			var mesh_name: String = CampusKit.DECOR_MESH.get(kind, kind)
			var mmi2 := _mmi(CampusKit.lod_mesh(mesh_name), list, center, _world_mat if rock else foliage_material, kind == "flowers" or kind == "lilies" or kind == "shrub_bloom")
			mmi2.name = "Decor_%s_%d_%d" % [kind, key.x, key.y]
			var vis := {"grass": 105.0, "flowers": 110.0, "shrub_bloom": 150.0, "reeds": 120.0, "lilies": 120.0}
			mmi2.visibility_range_end = float(vis.get(kind, 200.0)) * (1.0 if _quality >= 1 else 0.75)
			container.add_child(mmi2)
	return not _mm_queue.is_empty()


func _mmi(mesh: Mesh, list: Array, center: Vector3, mat: Material, custom: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = custom
	mm.mesh = mesh
	mm.instance_count = list.size()
	var off := Transform3D(Basis.IDENTITY, -center)
	for i in list.size():
		mm.set_instance_transform(i, off * (list[i][0] as Transform3D))
		mm.set_instance_color(i, list[i][1])
		if custom:
			mm.set_instance_custom_data(i, list[i][2])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.position = center
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	return mmi


func _glow_mesh() -> void:
	if _glow_count <= 0:
		return
	var gm := ShaderMaterial.new()
	gm.shader = GLOW_SHADER
	gm.set_shader_parameter("color", Color(1.0, 0.78, 0.45))
	gm.set_shader_parameter("intensity", 0.32)
	gm.set_shader_parameter("mode", 0.0)
	var gmi := MeshInstance3D.new()
	gmi.mesh = _glow_st.commit()
	gmi.material_override = gm
	gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gmi.name = "LampPools"
	gmi.visibility_range_end = 220.0
	container.add_child(gmi)


# ---------------------------------------------------------------------------
# Ground
# ---------------------------------------------------------------------------
const GROUND_STEP := 2.0
var _noise: FastNoiseLite
var _noise2: FastNoiseLite
## areas that tint the ground under them (woods floor, farm fields, sand...)
const GROUND_TINT := ["woods", "farm", "sand", "gravel", "yard", "construction"]


## One chunk's ground: its share of the 2 m grid as an indexed mesh section,
## coloured on the CPU (lawn noise, woods floor, worn grass, banks) and lit
## on the GPU.
func _ground_chunk(key: Vector2i) -> void:
	var b := CampusLayout.BOUNDS
	var nx := int(b.size.x / GROUND_STEP)
	var nz := int(b.size.y / GROUND_STEP)
	var per_x := int(CHUNK.x / GROUND_STEP)
	var per_z := int(CHUNK.y / GROUND_STEP)
	var x0 := key.x * per_x
	var z0 := key.y * per_z
	var x1 := mini(x0 + per_x, nx)
	var z1 := mini(z0 + per_z, nz)
	if x0 >= x1 or z0 >= z1:
		return
	_ensure_noise()
	var rect := Rect2(b.position.x + x0 * GROUND_STEP, b.position.y + z0 * GROUND_STEP, (x1 - x0) * GROUND_STEP, (z1 - z0) * GROUND_STEP)
	var tinting: Array = []
	for a in L.areas:
		if String(a["kind"]) in GROUND_TINT and (a["rect"] as Rect2).intersects(rect):
			tinting.append(a)
	var near_water: Array = []
	for w in L.waters:
		if (w["rect"] as Rect2).grow(3.0).intersects(rect):
			near_water.append(w)
	var k := _kit_at(rect.position.x + 1.0, rect.position.y + 1.0)
	var w2 := x1 - x0 + 1
	var ids := PackedInt32Array()
	ids.resize(w2 * (z1 - z0 + 1))
	for zi in range(z0, z1 + 1):
		var z := b.position.y + zi * GROUND_STEP
		for xi in range(x0, x1 + 1):
			var x := b.position.x + xi * GROUND_STEP
			var e := _ground_vertex(x, z, tinting, near_water)
			ids[(zi - z0) * w2 + (xi - x0)] = k.grid_vertex(e[0], e[1], e[2], Vector2(e[3], 0.0))
	for zi in range(z1 - z0):
		for xi in range(w2 - 1):
			var a := ids[zi * w2 + xi]
			var bb := ids[zi * w2 + xi + 1]
			var c := ids[(zi + 1) * w2 + xi + 1]
			var d := ids[(zi + 1) * w2 + xi]
			k.grid_tri(a, bb, c)
			k.grid_tri(a, c, d)


func _ensure_noise() -> void:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.seed = 11
		_noise.frequency = 0.035
		_noise2 = FastNoiseLite.new()
		_noise2.seed = 23
		_noise2.frequency = 0.16


const LAWN_A := Color(0.17, 0.36, 0.26)
const LAWN_B := Color(0.29, 0.46, 0.26)
const MOSS := Color(0.17, 0.30, 0.18)
const NEEDLES := Color(0.29, 0.26, 0.17)
const WORN := Color(0.38, 0.46, 0.26)
const MUD := Color(0.30, 0.27, 0.22)
const SAND := Color(0.52, 0.47, 0.36)
const FARM := Color(0.36, 0.38, 0.22)
const DIRT := Color(0.40, 0.33, 0.25)


## Unlit lawn colour at (x, z): two noise scales, woods floor under the
## crowns (moss and needles), worn grass beside paths.
func lawn_color(x: float, z: float) -> Color:
	_ensure_noise()
	var t := 0.5 + 0.5 * _noise.get_noise_2d(x, z)
	var col := LAWN_A.lerp(LAWN_B, t)
	col = col.lightened(0.04 * _noise2.get_noise_2d(x, z))
	if kit != null:
		var cn := kit.sample(kit.canopy, x, z)
		if cn > 0.01:
			var floor_c := MOSS.lerp(NEEDLES, 0.5 + 0.5 * _noise2.get_noise_2d(x * 0.5, z * 0.5))
			col = col.lerp(floor_c, clampf(cn, 0.0, 1.0) * 0.75)
		var wr := kit.sample(kit.wear, x, z)
		if wr > 0.01:
			col = col.lerp(WORN, wr * 0.45)
	return col


## One ground vertex: [position, smooth normal, colour, material id].
func _ground_vertex(x: float, z: float, tinting: Array, near_water: Array) -> Array:
	var y := grid_y(L, x, z)
	var hl := grid_y(L, x - GROUND_STEP, z)
	var hr := grid_y(L, x + GROUND_STEP, z)
	var hd := grid_y(L, x, z - GROUND_STEP)
	var hu := grid_y(L, x, z + GROUND_STEP)
	var n := Vector3((hl - hr) / (2.0 * GROUND_STEP), 1.0, (hd - hu) / (2.0 * GROUND_STEP)).normalized()
	var col := lawn_color(x, z)
	var mat := MeshKit.M_LAWN
	var p2 := Vector2(x, z)
	for a in tinting:
		if (a["rect"] as Rect2).has_point(p2) and Geometry2D.is_point_in_polygon(p2, a["poly"]):
			match String(a["kind"]):
				"woods":
					col = col.lerp(MOSS.lerp(NEEDLES, 0.5 + 0.5 * _noise2.get_noise_2d(x * 0.5, z * 0.5)), 0.7)
				"farm":
					col = FARM.lerp(col, 0.25)
				"sand":
					col = SAND
					mat = MeshKit.M_GRAVEL
				"gravel", "construction":
					col = DIRT.lerp(SAND, 0.3 + 0.3 * _noise2.get_noise_2d(x, z))
					mat = MeshKit.M_GRAVEL
				"yard":
					col = col.darkened(0.04)
	var low := minf(minf(y, hl), minf(minf(hr, hd), hu))
	if low < -0.1:
		col = col.lerp(MUD, 1.0 if y < -0.1 else 0.7)
		mat = MeshKit.M_GRAVEL
	else:
		for w in near_water:
			if String(w["kind"]) in ["lake", "pond"] and CampusLayout.in_water_shape(w, p2, 2.0):
				col = col.lerp(SAND.lerp(MUD, 0.4), 0.55)
				mat = MeshKit.M_GRAVEL
				break
	return [Vector3(x, y, z), n, col, mat]


## The lawn colour packed for a verge (sRGB bytes r*65536 + g*256 + b);
## the shader lights it with the light field like the ground around it.
func lawn_packed(x: float, z: float) -> float:
	var col := lawn_color(x, z)
	var r := clampi(int(round(col.r * 255.0)), 0, 255)
	var g := clampi(int(round(col.g * 255.0)), 0, 255)
	var bl := clampi(int(round(col.b * 255.0)), 0, 255)
	return float(r * 65536 + g * 256 + bl)


# ---------------------------------------------------------------------------
# Surfaces: areas, roads, paths
# ---------------------------------------------------------------------------
const PATH_Y := 0.075
const VERGE_Y := 0.062
const VERGE_W := 0.32
const AREA_STYLE := {
	# kind: [y, colour, material id]
	"field_grass": [0.012, Color(0.22, 0.44, 0.24), MeshKit.M_LAWN],
	"field_turf": [0.016, Color(0.16, 0.42, 0.22), MeshKit.M_LAWN],
	"infield": [0.02, Color(0.50, 0.36, 0.25), MeshKit.M_GRAVEL],
	"track": [0.02, Color(0.50, 0.24, 0.20), MeshKit.M_ASPHALT],
	"court": [0.024, Color(0.20, 0.36, 0.44), MeshKit.M_ASPHALT],
	"bed": [0.018, Color(0.25, 0.19, 0.14), MeshKit.M_GRAVEL],
	"parking": [0.03, Color(0.17, 0.18, 0.22), MeshKit.M_ASPHALT],
	"pavement": [0.045, Color(0.58, 0.56, 0.52), MeshKit.M_PAVING],
	"plaza": [0.05, Color(0.66, 0.60, 0.52), MeshKit.M_PAVING],
	"lawn": [0.0, Color(0, 0, 0), MeshKit.M_LAWN],
}


## One surface polygon (fields, lots, plazas, courts, beds): triangulated
## flat, its triangles shared out to the chunks they sit in.
func _area(a: Dictionary) -> void:
	var kind := String(a["kind"])
	if not AREA_STYLE.has(kind) or kind == "lawn":
		return
	var st: Array = AREA_STYLE[kind]
	var y: float = st[0]
	var col: Color = st[1]
	var mat: float = st[2]
	var poly: PackedVector2Array = a["poly"]
	var idx := CampusData.triangulate(poly)
	if idx.is_empty():
		idx = _fan(poly)
	for t in range(0, idx.size(), 3):
		var p0 := poly[idx[t]]
		var p1 := poly[idx[t + 1]]
		var p2 := poly[idx[t + 2]]
		var c := (p0 + p1 + p2) / 3.0
		var k := _kit_at(c.x, c.y)
		k.mat = mat
		_tri_up(k, _v3(p0, y), _v3(p1, y), _v3(p2, y), col)
		k.mat = 0.0
	if kind == "parking":
		arch.lot_markings(a)
	elif kind in ["field_turf", "field_grass", "court", "track"]:
		arch.field_markings(a)


static func _fan(poly: PackedVector2Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in range(1, poly.size() - 1):
		out.append_array([0, i, i + 1])
	return out


## Roads: asphalt in 4 m pieces, a raised kerb on each side where the data
## says so, faint centre dashes on two-way streets.
func _road(r: Dictionary) -> void:
	var asphalt := Color(0.17, 0.18, 0.22)
	var kerb := Color(0.50, 0.50, 0.54)
	var pts: PackedVector2Array = r["pts"]
	var hw: float = float(r["w"]) * 0.5
	var curb := bool(r.get("curb", true)) and String(r.get("kind", "")) != "lot_aisle"
	for i in pts.size() - 1:
		var a := pts[i]
		var bb := pts[i + 1]
		var seg := a.distance_to(bb)
		if seg < 0.05:
			continue
		var dir := (bb - a) / seg
		var nrm := Vector2(-dir.y, dir.x)
		var pieces := maxi(1, int(ceil(seg / 4.0)))
		for s in pieces:
			var p0 := a + dir * (seg * float(s) / float(pieces))
			var p1 := a + dir * (seg * float(s + 1) / float(pieces))
			var mid := (p0 + p1) * 0.5
			var k := _kit_at(mid.x, mid.y)
			k.mat = MeshKit.M_ASPHALT
			_quad_up(k, _v3(p0 - nrm * hw, 0.05), _v3(p1 - nrm * hw, 0.05), _v3(p1 + nrm * hw, 0.05), _v3(p0 + nrm * hw, 0.05), asphalt)
			if curb:
				k.mat = MeshKit.M_STONE
				for sg: float in [-1.0, 1.0]:
					var e0 := p0 + nrm * sg * hw
					var e1 := p1 + nrm * sg * hw
					var o0 := p0 + nrm * sg * (hw + 0.35)
					var o1 := p1 + nrm * sg * (hw + 0.35)
					if L.is_on_road(mid + nrm * sg * (hw + 1.0)) or _paved_area(mid + nrm * sg * (hw + 1.0)):
						continue
					_quad_up(k, _v3(e0, 0.12), _v3(e1, 0.12), _v3(o1, 0.12), _v3(o0, 0.12), kerb)
					_quad_side(k, _v3(e0, 0.12), _v3(e1, 0.12), _v3(e1, 0.05), _v3(e0, 0.05), kerb.darkened(0.25), Vector3(-nrm.x * sg, 0, -nrm.y * sg))
			k.mat = 0.0
		if String(r.get("kind", "")) in ["street", "campus"] and hw >= 3.0:
			var sd := 2.0
			while sd < seg - 2.0:
				var q0 := a + dir * sd
				var q1 := a + dir * (sd + 1.6)
				_kit_at(q0.x, q0.y).ribbon(PackedVector2Array([q0, q1]), 0.18, 0.06, Color(0.95, 0.82, 0.35), 0.25, false)
				sd += 5.0
	for i in range(1, pts.size() - 1):
		var k3 := _kit_at(pts[i].x, pts[i].y)
		k3.mat = MeshKit.M_ASPHALT
		k3.disc(Vector3(pts[i].x, 0.051, pts[i].y), hw, asphalt, 16)
		k3.mat = 0.0


const PATH_COLORS := {
	"concrete": Color(0.66, 0.64, 0.60), "brick": Color(0.58, 0.36, 0.30), "asphalt": Color(0.24, 0.25, 0.28),
	"gravel": Color(0.62, 0.56, 0.46), "boardwalk": Color(0.55, 0.40, 0.28),
}


static func _path_mat(surface: String) -> float:
	match surface:
		"gravel":
			return MeshKit.M_GRAVEL
		"boardwalk":
			return MeshKit.M_WOOD
		"asphalt":
			return MeshKit.M_ASPHALT
		"brick":
			return MeshKit.M_BRICK
	return MeshKit.M_PAVING


## A path: paving with a soft lawn verge on both sides, in ~2 m pieces so
## the light field and the lawn colour follow it.
func _path(pth: Dictionary) -> void:
	var pts: PackedVector2Array = pth["pts"]
	var surface := String(pth.get("surface", "concrete"))
	var pc: Color = PATH_COLORS.get(surface, PATH_COLORS["concrete"])
	var hw: float = float(pth["w"]) * 0.5
	var mat := _path_mat(surface)
	var vmat := 19.0 if mat == MeshKit.M_GRAVEL else MeshKit.M_VERGE
	var hin := maxf(0.2, hw - VERGE_W)
	var hout := hw + VERGE_W
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		if seg < 0.05:
			continue
		var d := (b - a) / seg
		var nrm := Vector2(-d.y, d.x)
		var pieces := maxi(1, int(ceil(seg / 2.0)))
		for s in pieces:
			var p0 := a + d * (seg * float(s) / float(pieces))
			var p1 := a + d * (seg * float(s + 1) / float(pieces))
			var mid := (p0 + p1) * 0.5
			var k := _kit_at(mid.x, mid.y)
			k.mat = mat
			_quad_up(k, _v3(p0 - nrm * hin, PATH_Y), _v3(p1 - nrm * hin, PATH_Y), _v3(p1 + nrm * hin, PATH_Y), _v3(p0 + nrm * hin, PATH_Y), pc)
			k.mat = 0.0
			for sg: float in [-1.0, 1.0]:
				var outer := mid + nrm * sg * (hw + 0.25)
				if _paved(outer):
					k.mat = mat
					_quad_up(k, _v3(p0 + nrm * sg * hin, PATH_Y - 0.004), _v3(p1 + nrm * sg * hin, PATH_Y - 0.004), _v3(p1 + nrm * sg * hw, PATH_Y - 0.004), _v3(p0 + nrm * sg * hw, PATH_Y - 0.004), pc)
					k.mat = 0.0
					continue
				var lp := lawn_packed(mid.x + nrm.x * sg * (hw + 0.6), mid.y + nrm.y * sg * (hw + 0.6))
				_verge_quad(k, p0 + nrm * sg * hin, p1 + nrm * sg * hin, p1 + nrm * sg * hout, p0 + nrm * sg * hout, pc, lp, vmat)
	for i in pts.size():
		var c := pts[i]
		var k2 := _kit_at(c.x, c.y)
		k2.mat = mat
		k2.disc(Vector3(c.x, PATH_Y + 0.0015, c.y), hin, pc, 14)
		k2.mat = 0.0
		if not _paved_area(c) and not L.is_on_road(c, hw):
			_verge_ring(k2, c, hin, hout, pc, lawn_packed(c.x + hw, c.y), vmat, VERGE_Y - 0.004, 14)


## True where the ground is already paved (a road, a path, a plaza or lot).
func _paved(p: Vector2) -> bool:
	return L.is_on_road(p, 0.2) or L.is_on_path(p, 0.0) or _paved_area(p)


func _paved_area(p: Vector2) -> bool:
	for a in L.areas:
		if String(a["kind"]) in ["plaza", "pavement", "parking", "court", "track"] and (a["rect"] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, a["poly"]):
			return true
	return false


static func _v3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


## A horizontal quad facing up whatever the corner order.
static func _quad_up(k: MeshKit, A: Vector3, B: Vector3, C: Vector3, D: Vector3, col: Color) -> void:
	if ((B - A).cross(C - A)).y < 0.0:
		k.quad(A, B, C, D, col)
	else:
		k.quad(D, C, B, A, col)


static func _tri_up(k: MeshKit, A: Vector3, B: Vector3, C: Vector3, col: Color) -> void:
	if ((B - A).cross(C - A)).y < 0.0:
		k.tri(A, B, C, col, 0.0, 0.0, Vector3.UP)
	else:
		k.tri(A, C, B, col, 0.0, 0.0, Vector3.UP)


## A vertical quad facing `facing` whatever the corner order.
static func _quad_side(k: MeshKit, A: Vector3, B: Vector3, C: Vector3, D: Vector3, col: Color, facing: Vector3) -> void:
	if ((B - A).cross(C - A)).dot(facing) < 0.0:
		k.quad(A, B, C, D, col)
	else:
		k.quad(D, C, B, A, col)


## A verge quad: inner edge (path side, alpha 0) a0-b0, outer edge a1-b1.
func _verge_quad(k: MeshKit, a0: Vector2, b0: Vector2, b1: Vector2, a1: Vector2, pc: Color, packed: float, vmat: float) -> void:
	var ci := Color(pc.r, pc.g, pc.b, 0.0)
	var co := Color(pc.r, pc.g, pc.b, 1.0)
	var uv := Vector2(vmat, packed)
	var A := _v3(a0, VERGE_Y)
	var B := _v3(b0, VERGE_Y)
	var C := _v3(b1, VERGE_Y)
	var D := _v3(a1, VERGE_Y)
	var up := Vector3.UP
	if ((B - A).cross(C - A)).y < 0.0:
		k.tri_full(A, B, C, up, up, up, ci, ci, co, uv, uv, uv)
		k.tri_full(A, C, D, up, up, up, ci, co, co, uv, uv, uv)
	else:
		k.tri_full(A, C, B, up, up, up, ci, co, ci, uv, uv, uv)
		k.tri_full(A, D, C, up, up, up, ci, co, co, uv, uv, uv)


func _verge_ring(k: MeshKit, c: Vector2, r_in: float, r_out: float, pc: Color, packed: float, vmat: float, y: float, seg: int) -> void:
	var ci := Color(pc.r, pc.g, pc.b, 0.0)
	var co := Color(pc.r, pc.g, pc.b, 1.0)
	var uv := Vector2(vmat, packed)
	var up := Vector3.UP
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		var i0 := Vector3(c.x + cos(a0) * r_in, y, c.y + sin(a0) * r_in)
		var i1 := Vector3(c.x + cos(a1) * r_in, y, c.y + sin(a1) * r_in)
		var o0 := Vector3(c.x + cos(a0) * r_out, y, c.y + sin(a0) * r_out)
		var o1 := Vector3(c.x + cos(a1) * r_out, y, c.y + sin(a1) * r_out)
		k.tri_full(i0, o1, o0, up, up, up, ci, co, co, uv, uv, uv)
		k.tri_full(i0, i1, o1, up, up, up, ci, ci, co, uv, uv, uv)


# ---------------------------------------------------------------------------
# Fake light pools (one additive mesh for the whole campus)
# ---------------------------------------------------------------------------
func glow_disc(center: Vector3, r: float) -> void:
	var seg := 16
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		_glow_vert(center, Vector2(0, 0))
		_glow_vert(center + Vector3(cos(a0) * r, 0, sin(a0) * r), Vector2(1, 0))
		_glow_vert(center + Vector3(cos(a1) * r, 0, sin(a1) * r), Vector2(1, 0))
	_glow_count += 1


func _glow_vert(p: Vector3, uv: Vector2) -> void:
	_glow_st.set_uv(uv)
	_glow_st.set_normal(Vector3.UP)
	_glow_st.add_vertex(p)
