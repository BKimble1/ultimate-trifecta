class_name CampusBuilder
extends RefCounted
## Generates collision for every map, and the visuals of the reference
## campus, from CampusLayout.  (Moonbrook College is drawn by ClassicBuilder;
## its collision comes from here like the campus's.)
##
## Collision (build_collision, the height field) is authoritative and comes
## from the map's data alone, so host and guests build identical worlds:
##   * a 1 m height field over the map's bounds, in square tiles (the map's
##     terrain, or flat ground at y = 0, with every water a basin cut down
##     from the ground at its edge to its floor: a soft bank for ponds and
##     the lake, a hard one behind a rim for fountains and pools, as the
##     water's data says);
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


## 1 m height grid over the map's bounds (row-major z, x; sample (i, j)
## sits at bounds.position + (i, j)), cached per layout.  Each water is scanline-
## filled, then a chamfer distance inward from its edge shapes the bank.
static func height_grid(layout: CampusLayout) -> PackedFloat32Array:
	if _grid_layout == layout and not _grid_cache.is_empty():
		return _grid_cache
	if _grid_task >= 0:
		# being computed on a worker (height_grid_step): take that result
		WorkerThreadPool.wait_for_task_completion(_grid_task)
		_grid_task = -1
		_grid_cache = _grid_result
		_grid_layout = _grid_task_layout
		_grid_result = PackedFloat32Array()
		if _grid_layout == layout:
			return _grid_cache
	_grid_cache = _compute_height_grid(layout)
	_grid_layout = layout
	return _grid_cache


static var _grid_task := -1
static var _grid_task_layout: CampusLayout
static var _grid_result: PackedFloat32Array


## The height grid on a worker thread (~50 ms of script on the real campus,
## mostly the lake's banks); true while it is not ready.  Loading polls it.
static func height_grid_step(layout: CampusLayout) -> bool:
	if _grid_layout == layout and not _grid_cache.is_empty():
		return false
	if _grid_task < 0:
		_grid_task_layout = layout
		_grid_task = WorkerThreadPool.add_task(func() -> void: _grid_result = _compute_height_grid(layout), false, "campus height grid")
		return true
	if not WorkerThreadPool.is_task_completed(_grid_task):
		return true
	height_grid(layout)
	return false


static func _compute_height_grid(layout: CampusLayout) -> PackedFloat32Array:
	var b := layout.bounds
	var w := int(b.size.x) + 1
	var d := int(b.size.y) + 1
	var data := _base_grid(layout, w, d)
	for wt in layout.waters:
		if bool(wt.get("flow", false)):
			continue      # a sloping channel: the terrain bake cut its bed
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
		if float(wt.get("bank", -1.0)) >= 0.0:
			bank = float(wt["bank"])
		var fl := float(wt["floor_y"])
		for jj in rd:
			for ii in rw:
				var dd := dist[jj * rw + ii]
				if dd <= 0.0:
					continue
				# from the ground at the edge down to the floor
				var idx := (j0 + jj) * w + (i0 + ii)
				var g0 := data[idx]
				data[idx] = minf(g0, lerpf(g0, fl, smoothstep(0.0, bank, dd)))
	return data


## The ground before the water beds: the map's terrain on the bounds' 1 m
## grid (the reference campus's terrain grid is exactly that grid), or flat.
static func _base_grid(layout: CampusLayout, w: int, d: int) -> PackedFloat32Array:
	var tr := layout.terrain
	if tr.is_empty():
		var flat := PackedFloat32Array()
		flat.resize(w * d)
		flat.fill(0.0)
		return flat
	var b := layout.bounds
	if int(tr["w"]) == w and int(tr["d"]) == d and is_equal_approx(float(tr["x0"]), b.position.x) and is_equal_approx(float(tr["z0"]), b.position.y):
		return (tr["h"] as PackedFloat32Array).duplicate()
	var out := PackedFloat32Array()
	out.resize(w * d)
	for j in d:
		for i in w:
			out[j * w + i] = layout.terrain_y(b.position + Vector2(i, j))
	return out


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
	var b := layout.bounds
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
	# the ground height field tiles have a body of their own: Jolt numbers a
	# hit's sub-shape in 32 bits, and a height field (~18 bits a tile) inside
	# a compound of the ~1,500 other shapes (~11 bits) would not fit, so the
	# whole compound failed to build and nothing collided
	var ground := StaticBody3D.new()
	ground.name = "GroundCollision"
	ground.collision_layer = TC.L_WORLD
	ground.collision_mask = 0
	# shapes go on the bodies before they enter the tree: added one by one to
	# a body already in the physics space, each one rebuilt the body's
	# compound shape
	for tile in ground_tiles(L):
		_attach(ground, tile[0], Transform3D(Basis.IDENTITY, tile[1]))
	for r in collision_recipe(L):
		_attach(world if int(r[0]) == RB_WORLD else blockers, r[1], r[2])
	root.add_child(ground)
	root.add_child(world)
	root.add_child(blockers)


# ---- the collision recipe: every shape but the ground, computed once per
# campus (the geometry work, ~120 ms cold, is the expensive part) in slices
# a loading frame can afford, and shared by every round's bodies (host sim
# and client world alike: Shape3D resources are shared, not copied)
const RB_WORLD := 0
const RB_BLOCK := 1
const RECIPE_SLICE := 12        # buildings per preparation step

var _rec: Array = []            # [[body, Shape3D, Transform3D]] being recorded

static var _recipe: Array = []
static var _recipe_layout: CampusLayout = null
static var _recipe_maker: CampusBuilder = null
static var _recipe_bi := 0


## One slice of the recipe; true while more remains (MatchController runs
## it during loading; collision_recipe finishes whatever is left).
static func collision_step(layout: CampusLayout) -> bool:
	if _recipe_layout == layout and _recipe_maker == null:
		return false
	if _recipe_layout != layout:
		_recipe_layout = layout
		_recipe = []
		_recipe_maker = CampusBuilder.new(layout)
		_recipe_bi = 0
	var m := _recipe_maker
	var n := layout.buildings.size()
	if _recipe_bi < n:
		var to2 := mini(_recipe_bi + RECIPE_SLICE, n)
		m._buildings_recipe(_recipe_bi, to2)
		_recipe_bi = to2
		return true
	m._rest_recipe()
	_recipe = m._rec
	_recipe_maker = null
	return false


## Puts shapes on a static body in a private physics space: the engine
## builds each shape now.  `keep`: the body stays, owning the build (the
## engine drops a shape's build with its last owner).  Only the ground tiles
## need this: the ~1,500 convex shapes cost ~8 ms cold in all.
static func _warm(items: Array, keep: bool = false) -> void:
	if items.is_empty():
		return
	if not _warm_space.is_valid():
		_warm_space = PhysicsServer3D.space_create()
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	for it in items:
		PhysicsServer3D.body_add_shape(body, (it[1] as Shape3D).get_rid(), it[2])
	PhysicsServer3D.body_set_space(body, _warm_space)
	if keep:
		_warm_bodies.append(body)
	else:
		PhysicsServer3D.free_rid(body)


static var _warm_bodies: Array[RID] = []


static func collision_recipe(layout: CampusLayout) -> Array:
	while collision_step(layout):
		pass
	return _recipe


func _buildings_recipe(from: int, to: int) -> void:
	var dorm_of: Dictionary = {}
	for id in CampusDorms.ids(L.map_id):
		dorm_of[String(CampusDorms.geometry(id).get("building", ""))] = id
	for bi in range(from, to):
		var bd: Dictionary = L.buildings[bi]
		if bool(bd["background"]):
			continue
		_building_collision(RB_WORLD, bd, String(dorm_of.get(bd["id"], "")))


func _rest_recipe() -> void:
	var world := RB_WORLD
	for s in L.walls:
		_gseg(world, s["a"], s["b"], s["h"], s["t"], String(s.get("kind", "")) == "wall_retaining")
	for s in L.hedges:
		_gseg(world, s["a"], s["b"], s["h"], s["t"])
	for s in L.fences:
		_gseg(world, s["a"], s["b"], s["h"], 0.25)
	for s in L.cart_blockers:
		_gseg(RB_BLOCK, s["a"], s["b"], 1.6, 0.5)
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
		_add_shape(world, c2, Transform3D(Basis.IDENTITY, Vector3(lp.x, grid_y(L, lp.x, lp.y) + 1.7, lp.y)))
	for bn in L.benches:
		var bp: Vector2 = bn["pos"]
		_box(world, Vector3(bp.x, grid_y(L, bp.x, bp.y) + 0.25, bp.y), Vector3(1.9, 0.5, 0.7), float(bn["rot"]))
	for so in L.solids:
		var sp: Vector2 = so["pos"]
		var ss: Vector3 = so["size"]
		var gy := float(so.get("base_y", grid_y(L, sp.x, sp.y)))
		if String(so.get("shape", "")) == "cyl":
			var cy := CylinderShape3D.new()
			cy.radius = ss.x * 0.5
			cy.height = ss.y
			_add_shape(world, cy, Transform3D(Basis.IDENTITY, Vector3(sp.x, gy + float(so.get("y", ss.y * 0.5)), sp.y)))
			continue
		_box(world, Vector3(sp.x, gy + ss.y * 0.5, sp.y), ss, float(so["rot"]))
	for pr in L.props:
		if not bool(pr.get("collide", true)):
			continue
		var ps := CampusArchitecture.prop_collider(pr)
		if ps != Vector3.ZERO:
			var pp: Vector2 = pr["pos"]
			_box(world, Vector3(pp.x, grid_y(L, pp.x, pp.y) + ps.y * 0.5, pp.y), ps, float(pr["rot"]))
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
				_gseg(world, a + out, c + out, rim, th)
	# the play boundary: invisible walls, tall (from 2 m under the ground)
	var bp2 := L.play_boundary
	for i in bp2.size():
		_gseg(world, bp2[i], bp2[(i + 1) % bp2.size()], 12.0, 1.0, false, 2.0)


## One building: convex prisms of what is solid at ground level (the
## footprint or its parts, minus open passages and a start dorm's interior),
## raised parts from their base, and slabs over the open spaces.
func _building_collision(world: int, bd: Dictionary, dorm_id: String) -> void:
	# heights are above the building's floor level; what stands on the ground
	# reaches down past the lowest grade round it (a building on a slope has
	# no gap under its low side)
	var fl := float(bd.get("floor_y", 0.0))
	var foot := minf(fl, float(bd.get("ground_min", fl))) - (0.2 if not L.terrain.is_empty() else 0.0)
	for e in CampusArchitecture.portico_entrances(bd):
		for cp in CampusArchitecture.portico_columns(e):
			_box(world, Vector3(cp.x, fl + 3.0, cp.y), Vector3(0.62, 6.0, 0.62))
	for cl in CampusArchitecture.passage_columns(bd):
		var cq: Vector2 = cl[0]
		var cyl := CylinderShape3D.new()
		cyl.radius = float(cl[1])
		cyl.height = float(cl[2])
		_add_shape(world, cyl, Transform3D(Basis.IDENTITY, Vector3(cq.x, fl + float(cl[2]) * 0.5, cq.y)))
	if bd.get("landmark") != null and String(bd["landmark"]) == "bell_tower":
		for so in CampusTower.solids(bd):
			for cv in CampusData.convex_pieces(so["poly"]):
				_prism(world, cv, foot if float(so["base"]) < 0.05 else fl + float(so["base"]), fl + float(so["h"]))
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
					_prism(world, cv, foot, fl + h)
		else:
			for cv in CampusData.convex_pieces(part["poly"]):
				_prism(world, cv, fl + base, fl + h)
	var top := float(bd["h"])
	for ps in bd["passages"]:
		var clear := float(ps["clear"])
		if top > clear + 0.05:
			for cv in CampusData.convex_pieces(ps["poly"]):
				_prism(world, cv, fl + clear, fl + top)
	if not g.is_empty():
		var ceil_y := float(g["ceil"])
		for ip in g["interior"]:
			for cv in CampusData.convex_pieces(ip):
				_prism(world, cv, fl + ceil_y, fl + maxf(top, ceil_y + 0.5))
		# lintels and furniture: CampusDorms places them on the floor already
		for bx in g["boxes"]:
			_box(world, bx[0], bx[1], float(bx[3]))


func _prism(body: int, poly: PackedVector2Array, y0: float, y1: float) -> void:
	var pts := PackedVector3Array()
	for p in poly:
		pts.append(Vector3(p.x, y0, p.y))
		pts.append(Vector3(p.x, y1, p.y))
	var cs := ConvexPolygonShape3D.new()
	cs.points = pts
	_add_shape(body, cs, Transform3D.IDENTITY)


## The ground height field, in tiles x tiles square tiles of tile_cells
## metres (tile_grid: 4 x 298 m on the reference campus, 2 x 160 m on
## Moonbrook College) shared by every round's collision (host sim and client
## world alike).
## Square on purpose: Jolt only makes a real height field from a square map
## (and falls back to a huge triangle mesh otherwise).  Tiles, not one
## field: Jolt builds a shape when a body using it enters a space (~100 ms
## for one 1191-sample field, ~7 ms for a 299-sample tile) and keeps the
## build while some body owns it, so loading builds the tiles one per step
## on bodies of a private space that stay (ground_tile_step).  A tile
## shares its edge samples with its neighbours; samples beyond the map's
## bounds repeat its edge.
const TILE_MAX := 298             # metres per tile at most (299 samples a side)


## [tiles a side, metres a tile] covering a layout's bounds.
static func tile_grid(layout: CampusLayout) -> Vector2i:
	var span := int(ceil(maxf(layout.bounds.size.x, layout.bounds.size.y)))
	var n := int(ceil(float(span) / float(TILE_MAX)))
	return Vector2i(n, int(ceil(float(span) / float(n))))


static var _tiles: Array = []     # [[HeightMapShape3D, Vector3 origin]]
static var _tiles_layout: CampusLayout
static var _warm_space := RID()


static func ground_tiles(layout: CampusLayout) -> Array:
	while ground_tile_step(layout):
		pass
	return _tiles


## Builds (and warms in the physics engine) the next ground tile; true
## while more remain.  Needs the height grid (computed here if not ready).
static func ground_tile_step(layout: CampusLayout, warm: bool = true) -> bool:
	if _tiles_layout != layout:
		_tiles = []
		_tiles_layout = layout
	var tg := tile_grid(layout)
	var tiles := tg.x
	var cells := tg.y
	var n := tiles * tiles
	if _tiles.size() >= n:
		return false
	var k := _tiles.size()
	var ti := k % tiles
	var tj := k / tiles
	var grid := height_grid(layout)
	var b := layout.bounds
	var w := int(b.size.x) + 1
	var d := int(b.size.y) + 1
	var s := cells + 1
	var data := PackedFloat32Array()
	var x0 := ti * cells
	for zi in s:
		# samples beyond the bounds repeat the edge (out of play either way)
		var gz := mini(tj * cells + zi, d - 1)
		var x1 := mini(x0 + s, w)
		var row := grid.slice(gz * w + mini(x0, w - 1), gz * w + x1) if x0 < w else PackedFloat32Array([grid[gz * w + w - 1]])
		var last := row[row.size() - 1]
		while row.size() < s:
			row.append(last)
		data.append_array(row)
	var hm := HeightMapShape3D.new()
	hm.map_width = s
	hm.map_depth = s
	hm.map_data = data
	var origin := Vector3(b.position.x + x0 + cells * 0.5, 0.0, b.position.y + tj * cells + cells * 0.5)
	_tiles.append([hm, origin])
	if warm:
		# built in the engine now (and kept), not when the round's world body
		# enters the tree
		_warm([[0, hm, Transform3D(Basis.IDENTITY, origin)]], true)
		# and once on a collision node (the first attach of a shape to a
		# node costs ~6 ms for a tile, paid here instead of in the round)
		var sb := StaticBody3D.new()
		_attach(sb, hm, Transform3D(Basis.IDENTITY, origin))
		sb.free()
	return _tiles.size() < n


## Drops the static caches (tests that swap the campus data).
static func drop_caches() -> void:
	_grid_cache = PackedFloat32Array()
	_grid_layout = null
	if _grid_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_grid_task)
		_grid_task = -1
	_tiles = []
	_tiles_layout = null
	for body in _warm_bodies:
		PhysicsServer3D.free_rid(body)
	_warm_bodies.clear()
	_recipe = []
	_recipe_layout = null
	_recipe_maker = null
	_recipe_bi = 0


## Records a shape for the recipe (body: RB_WORLD or RB_BLOCK).
func _add_shape(body: int, shape: Shape3D, xf: Transform3D) -> void:
	_rec.append([body, shape, xf])


static func _attach(body: CollisionObject3D, shape: Shape3D, xf: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xf
	body.add_child(cs)


func _box(body: int, center: Vector3, size: Vector3, yaw: float = 0.0) -> void:
	var bs := BoxShape3D.new()
	bs.size = size
	_add_shape(body, bs, Transform3D(Basis(Vector3.UP, yaw), center))


func _seg(body: int, a: Vector2, b: Vector2, y0: float, h: float, t: float) -> void:
	var dd := b - a
	var L2 := dd.length()
	if L2 < 0.01:
		return
	var yaw := atan2(-dd.y, dd.x)
	var c := (a + b) * 0.5
	_box(body, Vector3(c.x, y0 + h * 0.5, c.y), Vector3(L2 + t, h, t), yaw)


## A wall-like segment standing on the ground: on a slope it is split so
## each piece's top stays `h` above the ground under it (within 0.25 m) and
## its foot reaches below the lowest ground (`sink`).  A retaining wall
## (`retaining`) tops out `h` above its higher side.
func _gseg(body: int, a: Vector2, b: Vector2, h: float, t: float, retaining: bool = false, sink: float = 0.15) -> void:
	if L.terrain.is_empty():
		_seg(body, a, b, -sink if sink > 0.15 else 0.0, h + (sink if sink > 0.15 else 0.0), t)
		return
	var len := a.distance_to(b)
	if len < 0.01:
		return
	var n := maxi(1, int(ceil(len / 4.0)))
	var side := Vector2(-(b - a).y, (b - a).x).normalized() * (t * 0.5 + 0.6)
	for k in n:
		var p0 := a.lerp(b, float(k) / float(n))
		var p1 := a.lerp(b, float(k + 1) / float(n))
		var lo := INF
		var hi := -INF
		for q in [p0, p1, (p0 + p1) * 0.5]:
			for o in ([Vector2.ZERO, side, -side] if retaining else [Vector2.ZERO]):
				var gy := grid_y(L, (q as Vector2).x + (o as Vector2).x, (q as Vector2).y + (o as Vector2).y)
				lo = minf(lo, gy)
				hi = maxf(hi, gy)
		# pieces overlap a little so a sloping line leaves no gap at a joint
		var d := (p1 - p0).normalized() * (0.02 if n > 1 else 0.0)
		_seg(body, p0 - d, p1 + d, lo - sink, (hi - lo) + h + sink, t)


func _ramp(body: int, from: Vector3, to: Vector3, w: float) -> void:
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
	var k: MeshKit = store[key]
	k.lift = lift
	return k


## The level the thing being drawn stands on (its floor or the ground under
## it): every kit handed out (kit_at) lifts what is drawn by this, and
## instanced windows too.  Set by whoever draws, back to 0 afterwards.
var lift := 0.0


## The ground (finished: water beds cut) at a point of this map.
func gy(x: float, z: float) -> float:
	return grid_y(L, x, z)


## One window instance (CampusArchitecture._window): the glass, scaled to the
## window, in the room's colour with its emission; the frame at real size.
func window_add(ctr: Vector3, right: Vector3, normal: Vector3, width: float, height: float, room: Color, em: float, variant: int, trim: Color, frames: bool) -> void:
	var key := coarse_key(ctr.x, ctr.z)
	# a right-handed basis (x across to the viewer's right, y up, z out of
	# the wall): instances can't be mirrored without flipping their faces
	var across := Vector3.UP.cross(normal).normalized()
	if across.dot(right) < 0.0 and variant > 0:
		variant = 3 - variant      # the curtain stays on the same side
	right = across
	ctr.y += lift
	var xf := Transform3D(Basis(right * width, Vector3.UP * height * 2.0, normal), ctr + normal * 0.04)
	_mm_add(_win, key, "glass%d" % variant, xf, room, Color(0, 0, 0, em))
	if frames:
		_mm_add(_win, key, "frame", Transform3D(Basis(right, Vector3.UP, normal), ctr + normal * 0.07), trim, Color(1, 1, 1))


## The chunk mesh kit for a world point (public: architecture and landmarks).
func kit_at(x: float, z: float, foliage: bool = false, detail: bool = false) -> MeshKit:
	return _kit_at(x, z, foliage, detail)


## The reference campus's bounds: the look's chunk grid (this builder draws
## only that map).
const LOOK_BOUNDS := Rect2(-720.0, -560.0, 1190.0, 1000.0)


static func chunk_key(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor((x - LOOK_BOUNDS.position.x) / CHUNK.x)), int(floor((z - LOOK_BOUNDS.position.y) / CHUNK.y)))


static func chunk_center(key: Vector2i, scale: float = 1.0) -> Vector3:
	var b := LOOK_BOUNDS.position
	return Vector3(b.x + (float(key.x) + 0.5) * CHUNK.x * scale, 0.0, b.y + (float(key.y) + 0.5) * CHUNK.y * scale)


## Coarser batches (2 x 2 chunks): tree shadow proxies; the woods beyond the
## boundary use 3 x 3.
static func coarse_key(x: float, z: float, scale: float = 2.0) -> Vector2i:
	return Vector2i(int(floor((x - LOOK_BOUNDS.position.x) / (CHUNK.x * scale))), int(floor((z - LOOK_BOUNDS.position.y) / (CHUNK.y * scale))))


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
var _win: Dictionary = {}         # coarse key -> {glass0|glass1|glass2|frame: [...]} (instanced windows)
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
	_win.clear()
	_commit_keys.clear()
	_commit_started = false
	_mm_queue.clear()
	_mm_started = false
	water_nodes = {}
	arch = CampusArchitecture.new(self)
	marks = CampusLandmarks.new(self)
	dorm_art = DormArt.new(self, arch)
	_add("kit", func() -> void:
		height_grid_step(L)       # starts the height grid on a worker
		CampusKit.load_kit(quality))
	_add("light_kit", func() -> void: kit = CampusKit.new(L, false))
	_add_sliced("light_trees", L.trees.size(), func(i: int) -> void: kit.stamp_trees(i, i + 1))
	_add_sliced("light_buildings", L.buildings.size(), func(i: int) -> void: kit.stamp_buildings(i, i + 1))
	_add("light_barriers", func() -> void: kit.stamp_barriers())
	_add("light_lamps", func() -> void: kit.stamp_lights())
	_add_sliced("light_paths", L.paths.size(), func(i: int) -> void: kit.stamp_paths(i, i + 1))
	_add("ground_prep", _ground_prep)
	_add("ground", _ground_next)
	_add_sliced("areas", L.areas.size(), func(i: int) -> void: _area(L.areas[i]))
	_add_sliced("roads", L.roads.size(), func(i: int) -> void: _road(L.roads[i]))
	_add_sliced("paths", L.paths.size(), func(i: int) -> void: _path(L.paths[i]))
	var dorm_buildings: Dictionary = {}
	for id in CampusDorms.ids(L.map_id):
		dorm_buildings[String(CampusDorms.geometry(id).get("building", ""))] = true
	for bd in L.buildings:
		if dorm_buildings.has(String(bd["id"])):
			continue      # DormArt builds it, with its open doorways
		# drawn at its floor level (its foundation reaches the ground: _plinth)
		_add("building_" + String(bd["id"]), func() -> void:
			lift = float(bd.get("floor_y", 0.0))
			arch.building(bd)
			lift = 0.0
			_plinth(bd))
	for id in CampusDorms.ids(L.map_id):
		var dbd := L.building_by_id(String(CampusDorms.geometry(id).get("building", "")))
		_add("dorm_" + id, func() -> void:
			lift = float(dbd.get("floor_y", 0.0))
			dorm_art.exterior(id)
			lift = 0.0
			_plinth(dbd))
		_add("dorm_inside_" + id, func() -> void:
			lift = float(dbd.get("floor_y", 0.0))
			dorm_art.inside(id)
			lift = 0.0)
	_add("walls", arch.walls)
	_add_sliced("hedges", L.hedges.size(), func(i: int) -> void: arch.hedges(i, i + 1))
	_add_sliced("fences", L.fences.size(), func(i: int) -> void: arch.fences(i, i + 1))
	_add("bollards", func() -> void: arch.bollards(0, L.cart_blockers.size()))
	_add_sliced("trees", L.trees.size(), func(i: int) -> void: _place_tree(L.trees[i]))
	_add("trees_merge", _merge_species)
	_add_sliced("lamps", L.lamps.size(), func(i: int) -> void: arch.lamps(i, i + 1))
	_add("small", arch.small_things)
	var field_rows := int(LOOK_BOUNDS.size.y / CampusKit.CELL) + 1
	for j0 in range(0, field_rows, 120):
		_add("light_texture", func() -> void: kit.field_rows(j0, j0 + 120))
	_add("light_texture", func() -> void: _field_tex = kit.field_finish())
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


## A building on sloping ground: its foundation wall from its floor down to
## the lowest grade round it, in a stone tone, so its low side stands on the
## ground (a basement storey's windows are the building's own; this is the
## plain wall below them).  Nothing on flat ground.
func _plinth(bd: Dictionary) -> void:
	if bd.is_empty():
		return
	var fl := float(bd.get("floor_y", 0.0))
	var lo := float(bd.get("ground_min", fl))
	if fl - lo < 0.12:
		return
	var poly: PackedVector2Array = CampusData.ccw(bd["poly"])
	var c := CampusData.centroid(poly)
	var k := kit_at(c.x, c.y)
	var col := Color(0.52, 0.49, 0.46)
	k.mat = MeshKit.M_STONE
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		# the wall face, from just under the ground to the floor
		var ga := minf(gy(a.x, a.y), fl) - 0.3
		var gb := minf(gy(b.x, b.y), fl) - 0.3
		var nrm := Vector3(b.y - a.y, 0, -(b.x - a.x)).normalized()
		k.tri_n(Vector3(a.x, ga, a.y), Vector3(b.x, gb, b.y), Vector3(b.x, fl, b.y), nrm, nrm, nrm, col, col, col.lightened(0.05))
		k.tri_n(Vector3(a.x, ga, a.y), Vector3(b.x, fl, b.y), Vector3(a.x, fl, a.y), nrm, nrm, nrm, col, col.lightened(0.05), col.lightened(0.05))
	k.mat = 0.0


func _add(step_name: String, f: Callable) -> void:
	_steps.append(f)
	step_names.append(step_name)


## A step over n items that runs items until SLICE_US has passed and then
## yields (the same step runs again next time): batches size themselves to
## the items (a long road or a big building costs many small ones).
const SLICE_US := 6000


func _add_sliced(step_name: String, n: int, per_item: Callable) -> void:
	if n <= 0:
		return
	var cursor := [0]
	_add(step_name, func() -> bool:
		var t0 := Time.get_ticks_usec()
		while cursor[0] < n:
			per_item.call(cursor[0])
			cursor[0] += 1
			if Time.get_ticks_usec() - t0 >= SLICE_US:
				break
		return cursor[0] < n)


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
	for tid in _ground_tasks:
		ids.append(int(tid))
	_ground_tasks.clear()
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
	# (the light-field kit stays until the builder goes: a cancelled build's
	# ground tasks may still read it; they hold the builder until they end)
	_root = null
	_glow_st = null
	_world_mat = null
	_field_tex = null
	for d: Dictionary in [_chunks, _foliage, _detail, _trees, _decor, _far, _proxy, _win]:
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
func _place_tree(t: Dictionary) -> void:
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
		return
	var sp := CampusKit.species_of(t)
	var sc: float = float(t["h"]) / CampusKit.REF_H
	var xf2 := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc)), Vector3(p.x, y, p.y))
	_mm_add(_trees, chunk_key(p.x, p.y), sp, xf2, CampusKit.tint_of(t), Color(1, 1, 1))
	_mm_add(_proxy, coarse_key(p.x, p.y), "fir" if sp in CampusKit.CONIFER else "oak", xf2, Color(1, 1, 1), Color(1, 1, 1))


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
		for key in _win:
			_mm_queue.append([_win, key, 2.0])
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
		elif store == _win:
			var wm := _mmi(CampusArchitecture.window_mesh(kind), list, center, _world_mat, kind != "frame")
			wm.name = "Windows_%s_%d_%d" % [kind, key.x, key.y]
			wm.visibility_range_end = (DETAIL_M if kind == "frame" else CHUNK_END_M) * (1.0 if _quality >= 1 else 0.8)
			container.add_child(wm)
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
## The ground is generated chunk by chunk on the worker thread pool (each
## task writes only its own chunk's MeshKit and reads the layout, the
## height grid, the light field and the noise, all finished before): the
## real campus is ~300 chunks, most of the build's work.
var _ground_tasks: Array = []
var _ground_started := false


func _ground_keys() -> Array:
	var out: Array = []
	var nx := int(ceil(LOOK_BOUNDS.size.x / CHUNK.x))
	var nz := int(ceil(LOOK_BOUNDS.size.y / CHUNK.y))
	for gz in nz:
		for gx in nx:
			out.append(Vector2i(gx, gz))
	return out


func _ground_prep() -> bool:
	# the height grid comes from a worker (started with the build's first
	# step); waiting a few frames here beats a ~50 ms frame
	if height_grid_step(L):
		return true
	_ensure_noise()
	for key in _ground_keys():
		if not _chunks.has(key):
			_chunks[key] = MeshKit.new()
	_ground_started = false
	_ground_tasks.clear()
	return false


func _ground_next() -> bool:
	if not _ground_started:
		_ground_started = true
		for key in _ground_keys():
			_ground_tasks.append(WorkerThreadPool.add_task(_ground_chunk.bind(key, _chunks[key]), false, "campus ground"))
		return true
	while not _ground_tasks.is_empty():
		if not WorkerThreadPool.is_task_completed(int(_ground_tasks[0])):
			return true
		WorkerThreadPool.wait_for_task_completion(int(_ground_tasks.pop_front()))
	return false


## One ground chunk (on a worker): a 2 m grid, flat and cheap where no water
## is near, 4 m where the chunk lies wholly beyond the play area.
func _ground_chunk(key: Vector2i, k: MeshKit) -> void:
	var b := LOOK_BOUNDS
	var rect := Rect2(b.position + Vector2(key) * CHUNK, CHUNK).intersection(b)
	if rect.size.x <= 0.01 or rect.size.y <= 0.01:
		return
	var tinting: Array = []
	for a in L.areas:
		if String(a["kind"]) in GROUND_TINT and (a["rect"] as Rect2).intersects(rect):
			tinting.append(a)
	var near_water: Array = []
	for w in L.waters:
		if (w["rect"] as Rect2).grow(3.0).intersects(rect):
			near_water.append(w)
	var step := GROUND_STEP
	if near_water.is_empty() and not CampusData.bounds(L.play_boundary).grow(8.0).intersects(rect):
		step = GROUND_STEP * 2.0
	var nxs := int(ceil(rect.size.x / step - 0.001))
	var nzs := int(ceil(rect.size.y / step - 0.001))
	var w2 := nxs + 1
	var ids := PackedInt32Array()
	ids.resize(w2 * (nzs + 1))
	for zi in nzs + 1:
		var z := minf(rect.position.y + zi * step, rect.end.y)
		for xi in nxs + 1:
			var x := minf(rect.position.x + xi * step, rect.end.x)
			var e := _ground_vertex(x, z, tinting, near_water)
			ids[zi * w2 + xi] = k.grid_vertex(e[0], e[1], e[2], Vector2(e[3], 0.0))
	var z1 := nzs
	var z0 := 0
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
	var y := 0.0
	var hl := 0.0
	var hr := 0.0
	var hd := 0.0
	var hu := 0.0
	var n := Vector3.UP
	if not near_water.is_empty():
		# only around the waters is the ground anything but flat
		y = grid_y(L, x, z)
		hl = grid_y(L, x - GROUND_STEP, z)
		hr = grid_y(L, x + GROUND_STEP, z)
		hd = grid_y(L, x, z - GROUND_STEP)
		hu = grid_y(L, x, z + GROUND_STEP)
		n = Vector3((hl - hr) / (2.0 * GROUND_STEP), 1.0, (hd - hu) / (2.0 * GROUND_STEP)).normalized()
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
		_area_tri(poly[idx[t]], poly[idx[t + 1]], poly[idx[t + 2]], y, col, mat, 0)
	if kind == "parking":
		arch.lot_markings(a)
	elif kind in ["field_turf", "field_grass", "court", "track"]:
		arch.field_markings(a)


## One area triangle on the ground: split until no edge is over 6 m when
## the map has terrain (a lot or a field follows its grade), then draped.
func _area_tri(p0: Vector2, p1: Vector2, p2: Vector2, y: float, col: Color, mat: float, depth: int) -> void:
	if not L.terrain.is_empty() and depth < 8:
		var l01 := p0.distance_to(p1)
		var l12 := p1.distance_to(p2)
		var l20 := p2.distance_to(p0)
		var lm := maxf(l01, maxf(l12, l20))
		if lm > 6.0:
			if lm == l01:
				var m := (p0 + p1) * 0.5
				_area_tri(p0, m, p2, y, col, mat, depth + 1)
				_area_tri(m, p1, p2, y, col, mat, depth + 1)
			elif lm == l12:
				var m := (p1 + p2) * 0.5
				_area_tri(p0, p1, m, y, col, mat, depth + 1)
				_area_tri(p0, m, p2, y, col, mat, depth + 1)
			else:
				var m := (p2 + p0) * 0.5
				_area_tri(p0, p1, m, y, col, mat, depth + 1)
				_area_tri(m, p1, p2, y, col, mat, depth + 1)
			return
	var c := (p0 + p1 + p2) / 3.0
	var k := _kit_at(c.x, c.y)
	k.mat = mat
	_tri_up(k, _gv(p0, y), _gv(p1, y), _gv(p2, y), col)
	k.mat = 0.0


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
		var pieces := maxi(1, int(ceil(seg / (4.0 if L.terrain.is_empty() else 2.0))))
		for s in pieces:
			var p0 := a + dir * (seg * float(s) / float(pieces))
			var p1 := a + dir * (seg * float(s + 1) / float(pieces))
			var mid := (p0 + p1) * 0.5
			var k := _kit_at(mid.x, mid.y)
			k.mat = MeshKit.M_ASPHALT
			_quad_up(k, _gv(p0 - nrm * hw, 0.05), _gv(p1 - nrm * hw, 0.05), _gv(p1 + nrm * hw, 0.05), _gv(p0 + nrm * hw, 0.05), asphalt)
			if curb:
				k.mat = MeshKit.M_STONE
				for sg: float in [-1.0, 1.0]:
					var e0 := p0 + nrm * sg * hw
					var e1 := p1 + nrm * sg * hw
					var o0 := p0 + nrm * sg * (hw + 0.35)
					var o1 := p1 + nrm * sg * (hw + 0.35)
					if L.is_on_road(mid + nrm * sg * (hw + 1.0)) or _paved_area(mid + nrm * sg * (hw + 1.0)):
						continue
					_quad_up(k, _gv(e0, 0.12), _gv(e1, 0.12), _gv(o1, 0.12), _gv(o0, 0.12), kerb)
					_quad_side(k, _gv(e0, 0.12), _gv(e1, 0.12), _gv(e1, 0.05), _gv(e0, 0.05), kerb.darkened(0.25), Vector3(-nrm.x * sg, 0, -nrm.y * sg))
			k.mat = 0.0
		if String(r.get("kind", "")) in ["street", "campus"] and hw >= 3.0:
			var sd := 2.0
			while sd < seg - 2.0:
				var q0 := a + dir * sd
				var q1 := a + dir * (sd + 1.6)
				lift = gy(q0.x, q0.y)
				_kit_at(q0.x, q0.y).ribbon(PackedVector2Array([q0, q1]), 0.18, 0.06, Color(0.95, 0.82, 0.35), 0.25, false)
				lift = 0.0
				sd += 5.0
	for i in range(1, pts.size() - 1):
		var k3 := _kit_at(pts[i].x, pts[i].y)
		k3.mat = MeshKit.M_ASPHALT
		k3.disc(Vector3(pts[i].x, gy(pts[i].x, pts[i].y) + 0.051, pts[i].y), hw, asphalt, 16)
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
			_quad_up(k, _gv(p0 - nrm * hin, PATH_Y), _gv(p1 - nrm * hin, PATH_Y), _gv(p1 + nrm * hin, PATH_Y), _gv(p0 + nrm * hin, PATH_Y), pc)
			k.mat = 0.0
			for sg: float in [-1.0, 1.0]:
				var outer := mid + nrm * sg * (hw + 0.25)
				if _paved(outer):
					k.mat = mat
					_quad_up(k, _gv(p0 + nrm * sg * hin, PATH_Y - 0.004), _gv(p1 + nrm * sg * hin, PATH_Y - 0.004), _gv(p1 + nrm * sg * hw, PATH_Y - 0.004), _gv(p0 + nrm * sg * hw, PATH_Y - 0.004), pc)
					k.mat = 0.0
					continue
				var lp := lawn_packed(mid.x + nrm.x * sg * (hw + 0.6), mid.y + nrm.y * sg * (hw + 0.6))
				_verge_quad(k, p0 + nrm * sg * hin, p1 + nrm * sg * hin, p1 + nrm * sg * hout, p0 + nrm * sg * hout, pc, lp, vmat)
	for i in pts.size():
		var c := pts[i]
		var k2 := _kit_at(c.x, c.y)
		k2.mat = mat
		k2.disc(Vector3(c.x, gy(c.x, c.y) + PATH_Y + 0.0015, c.y), hin, pc, 14)
		k2.mat = 0.0
		if not _paved_area(c) and not L.is_on_road(c, hw):
			_verge_ring(k2, c, hin, hout, pc, lawn_packed(c.x + hw, c.y), vmat, VERGE_Y - 0.004, 14)


## True where the ground is already paved (a road, a path, a plaza or lot).
func _paved(p: Vector2) -> bool:
	return L.is_on_road(p, 0.2) or L.is_on_path(p, 0.0) or _paved_area(p)


func _paved_area(p: Vector2) -> bool:
	if _paved_cells.is_empty():
		_index_paved()
	for ai in _paved_cells.get(Vector2i(floori(p.x / PAVED_CELL), floori(p.y / PAVED_CELL)), []):
		var a: Dictionary = L.areas[ai]
		if (a["rect"] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, a["poly"]):
			return true
	return false


const PAVED_KINDS := ["plaza", "pavement", "parking", "court", "track"]
const PAVED_CELL := 32.0
var _paved_cells := {}          # cell -> [area index]: the paved areas there


## Paved areas by 32 m cell (every path piece asks twice: scanning all
## areas each time cost ~0.6 s of the build).
func _index_paved() -> void:
	_paved_cells[Vector2i(1 << 30, 0)] = []      # built, even if empty
	for ai in L.areas.size():
		var a: Dictionary = L.areas[ai]
		if not PAVED_KINDS.has(String(a["kind"])):
			continue
		var r: Rect2 = a["rect"]
		for cx in range(floori(r.position.x / PAVED_CELL), floori(r.end.x / PAVED_CELL) + 1):
			for cy in range(floori(r.position.y / PAVED_CELL), floori(r.end.y / PAVED_CELL) + 1):
				var key := Vector2i(cx, cy)
				if not _paved_cells.has(key):
					_paved_cells[key] = []
				(_paved_cells[key] as Array).append(ai)


static func _v3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


## A point `y` above the ground at p (draped surfaces: roads, paths, areas).
func _gv(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, grid_y(L, p.x, p.y) + y, p.y)


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
	var A := _gv(a0, VERGE_Y)
	var B := _gv(b0, VERGE_Y)
	var C := _gv(b1, VERGE_Y)
	var D := _gv(a1, VERGE_Y)
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
		var i0 := _gv(Vector2(c.x + cos(a0) * r_in, c.y + sin(a0) * r_in), y)
		var i1 := _gv(Vector2(c.x + cos(a1) * r_in, c.y + sin(a1) * r_in), y)
		var o0 := _gv(Vector2(c.x + cos(a0) * r_out, c.y + sin(a0) * r_out), y)
		var o1 := _gv(Vector2(c.x + cos(a1) * r_out, c.y + sin(a1) * r_out), y)
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
