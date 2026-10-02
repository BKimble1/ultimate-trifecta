class_name CampusBuilder
extends RefCounted
## Generates collision and visuals for Moonbrook College from CampusLayout.

const CHUNK := Vector2(64.0, 60.0)
const WORLD_SHADER := preload("res://assets/shaders/world_vc.gdshader")
const FOLIAGE_SHADER := preload("res://assets/shaders/world_foliage.gdshader")
const WATER_SHADER := preload("res://assets/shaders/water.gdshader")
const GLOW_SHADER := preload("res://assets/shaders/glow_add.gdshader")

var L: CampusLayout
var _chunks: Dictionary = {}
var _foliage: Dictionary = {}   # tree canopies: separate chunks (near-camera parting, see-through)
var _detail: Dictionary = {}    # small props per chunk, drawn only near the camera
const DETAIL_M := 100.0
## the shared canopy material (MatchController feeds it the followed character)
var foliage_material: ShaderMaterial
var _glow_st: SurfaceTool
var _glow_count := 0


func _init(layout: CampusLayout) -> void:
	L = layout


# ---------------------------------------------------------------------------
# Height function (shared by collision + visuals)
# ---------------------------------------------------------------------------
static func ground_y(layout: CampusLayout, x: float, z: float) -> float:
	var p := Vector2(x, z)
	for w in layout.waters:
		if CampusLayout.in_water_shape(w, p):
			return float(w["floor_y"])
	return 0.0


static var _grid_cache: PackedFloat32Array
static var _grid_layout: CampusLayout


## 1 m height grid over BOUNDS (row-major z, x), cached per layout.
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
		var c: Vector2 = wt["center"]
		var ext := 16.0
		for zi in range(int(c.y - ext - b.position.y), int(c.y + ext - b.position.y) + 1):
			if zi < 0 or zi >= d:
				continue
			for xi in range(int(c.x - ext - b.position.x), int(c.x + ext - b.position.x) + 1):
				if xi < 0 or xi >= w:
					continue
				var p := Vector2(b.position.x + xi, b.position.y + zi)
				if CampusLayout.in_water_shape(wt, p):
					data[zi * w + xi] = float(wt["floor_y"])
	_grid_cache = data
	_grid_layout = layout
	return data


static func grid_y(layout: CampusLayout, x: float, z: float) -> float:
	var b := CampusLayout.BOUNDS
	var xi := clampi(int(round(x - b.position.x)), 0, int(b.size.x))
	var zi := clampi(int(round(z - b.position.y)), 0, int(b.size.y))
	return height_grid(layout)[zi * (int(b.size.x) + 1) + xi]


static func water_at(layout: CampusLayout, p: Vector2) -> int:
	for i in layout.waters.size():
		if CampusLayout.in_water_shape(layout.waters[i], p):
			return i
	return -1


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
	# shapes go on the bodies before they enter the tree: added one by one
	# to a body already in the physics space, each one rebuilt the body's
	# compound shape (~45 ms for the campus; ~5 ms this way)

	# Ground heightmap at 1 m resolution with real pits under every water body.
	_add_shape(world, ground_shape(L), Transform3D(Basis.IDENTITY, ground_shape_origin()))

	for bd in L.buildings:
		var pos: Vector2 = bd["pos"]
		var size: Vector2 = bd["size"]
		var h: float = bd["h"]
		var y0: float = float(bd.get("base_y", 0.0))
		if bd["id"] == "shed":
			# open front (south): back + two side walls + roof slab
			var hz := size.y * 0.5
			_box(world, Vector3(pos.x, h * 0.5, pos.y - hz + 0.3), Vector3(size.x, h, 0.6))
			_box(world, Vector3(pos.x - size.x * 0.5 + 0.3, h * 0.5, pos.y), Vector3(0.6, h, size.y))
			_box(world, Vector3(pos.x + size.x * 0.5 - 0.3, h * 0.5, pos.y), Vector3(0.6, h, size.y))
			_box(world, Vector3(pos.x, h - 0.3, pos.y), Vector3(size.x, 0.6, size.y))
			continue
		_box(world, Vector3(pos.x, y0 + (h - y0) * 0.5, pos.y), Vector3(size.x, h - y0, size.y), float(bd.get("rot", 0.0)))
	for s in L.walls:
		_seg(world, s["a"], s["b"], 0.0, s["h"], s["t"])
	for s in L.hedges:
		_seg(world, s["a"], s["b"], 0.0, s["h"], s["t"])
	for s in L.fences:
		_seg(world, s["a"], s["b"], 0.0, s["h"], 0.25)
	for s in L.cart_blockers:
		_seg(blockers, s["a"], s["b"], 0.0, 1.6, 0.5)
	for t in L.trees:
		var tp: Vector2 = t["pos"]
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.42
		cyl.height = 4.0
		_add_shape(world, cyl, Transform3D(Basis.IDENTITY, Vector3(tp.x, 2.0, tp.y)))
	for r in L.rocks:
		_box(world, r["pos"] + Vector3(0, float(r["size"].y) * 0.5, 0), r["size"], float(r["rot"]))
	for p in L.platforms:
		_box(world, p["center"] - Vector3(0, float(p["size"].y) * 0.5 - 0.0, 0) + Vector3(0, 0, 0), p["size"])
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
	# Water rims and fountain pedestal
	for wt in L.waters:
		var rim: float = float(wt.get("rim_h", 0.0))
		var c: Vector2 = wt["center"]
		if rim <= 0.0:
			continue
		var th: float = float(wt.get("rim_t", 0.5))
		if wt["shape"] == "circle":
			var r0: float = float(wt["radius"])
			var n := 20
			for i in n:
				var a := TAU * (float(i) + 0.5) / float(n)
				var seg_len := TAU * (r0 + th) / float(n) + 0.15
				var cpos := c + Vector2(cos(a), sin(a)) * (r0 + th * 0.5)
				_box(world, Vector3(cpos.x, rim * 0.5, cpos.y), Vector3(th, rim, seg_len), -a)
			var ped := CylinderShape3D.new()
			ped.radius = 1.3
			ped.height = 2.6
			_add_shape(world, ped, Transform3D(Basis.IDENTITY, Vector3(c.x, 0.0, c.y)))
		elif wt["shape"] == "rect":
			var hs: Vector2 = wt["size"] * 0.5
			_box(world, Vector3(c.x, rim * 0.5, c.y - hs.y - th * 0.5), Vector3(hs.x * 2.0 + th * 2.0, rim, th))
			_box(world, Vector3(c.x, rim * 0.5, c.y + hs.y + th * 0.5), Vector3(hs.x * 2.0 + th * 2.0, rim, th))
			_box(world, Vector3(c.x - hs.x - th * 0.5, rim * 0.5, c.y), Vector3(th, rim, hs.y * 2.0))
			_box(world, Vector3(c.x + hs.x + th * 0.5, rim * 0.5, c.y), Vector3(th, rim, hs.y * 2.0))
	# Invisible outer walls (tall) so nobody leaves the campus
	var bb := CampusLayout.BOUNDS.grow(1.0)
	_box(world, Vector3(bb.position.x, 5, bb.get_center().y), Vector3(1, 10, bb.size.y))
	_box(world, Vector3(bb.end.x, 5, bb.get_center().y), Vector3(1, 10, bb.size.y))
	_box(world, Vector3(bb.get_center().x, 5, bb.position.y), Vector3(bb.size.x, 10, 1))
	_box(world, Vector3(bb.get_center().x, 5, bb.end.y), Vector3(bb.size.x, 10, 1))
	root.add_child(world)
	root.add_child(blockers)


static var _hm_shape: HeightMapShape3D
static var _hm_layout: CampusLayout


## The ground heightmap shape, shared by every round's collision (host sim
## and client world alike), so the physics engine builds it once.  It is
## square on purpose: Jolt only makes a real height field from a square map
## and falls back to a ~190k-triangle mesh otherwise (161 ms to build and
## slower to query; measured 6 ms square).  The extra rows lie beyond the
## campus's outer walls at ground level.
static func ground_shape(layout: CampusLayout) -> HeightMapShape3D:
	if _hm_layout == layout and _hm_shape != null:
		return _hm_shape
	var b := CampusLayout.BOUNDS
	var w := int(b.size.x) + 1
	var d := int(b.size.y) + 1
	var n := maxi(w, d)
	var grid := height_grid(layout)
	var data := PackedFloat32Array()
	var pad := PackedFloat32Array()
	pad.resize(n - w)
	pad.fill(0.0)
	for zi in d:
		data.append_array(grid.slice(zi * w, zi * w + w))
		data.append_array(pad)
	var tail := PackedFloat32Array()
	tail.resize((n - d) * n)
	tail.fill(0.0)
	data.append_array(tail)
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
# Visuals
# ---------------------------------------------------------------------------
## detail: small near-field props (lamps, bollards, benches, window frames)
## in their own per-chunk mesh that stops drawing beyond DETAIL_M.
func _kit_at(x: float, z: float, foliage: bool = false, detail: bool = false) -> MeshKit:
	var key := Vector2i(int(floor((x - CampusLayout.BOUNDS.position.x) / CHUNK.x)), int(floor((z - CampusLayout.BOUNDS.position.y) / CHUNK.y)))
	var store := _foliage if foliage else (_detail if detail else _chunks)
	if not store.has(key):
		store[key] = MeshKit.new()
	return store[key]


## Builds the whole campus look at once (dev shots, tests).
func build_visuals(root: Node3D, quality: int = 1) -> Dictionary:
	begin_visuals(root, quality)
	while step():
		pass
	return water_nodes


# Staged build: the visual work as a queue of short steps (a building, a row
# of trees, one chunk's mesh) so a loading screen keeps animating while the
# campus is made.  A step returning true runs again (chunk commits).
var water_nodes: Dictionary = {}
var container: Node3D
var _steps: Array[Callable] = []
var _step_i := 0
var _rng: RandomNumberGenerator
var _quality := 1
var _root: Node3D
var _commit_keys: Array = []
var _world_mat: ShaderMaterial
## V4 art kit: light field, tree instances per chunk, where each chunk's
## ground ends (everything after it is baked from the light field)
var kit: CampusKit
var _trees: Dictionary = {}       # chunk key -> {variant key: [[Transform3D, Color], ...]}
var _ground_end: Dictionary = {}  # chunk key -> vertex count after the ground


func begin_visuals(root: Node3D, quality: int = 1) -> void:
	_chunks.clear()
	_foliage.clear()
	_detail.clear()
	_glow_st = SurfaceTool.new()
	_glow_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_glow_count = 0
	_rng = RandomNumberGenerator.new()
	_rng.seed = 77
	_quality = quality
	_root = root
	_step_i = 0
	_steps.clear()
	_trees.clear()
	_ground_end.clear()
	_steps.append(func() -> void: kit = CampusKit.new(L))
	for z0 in range(0, ground_rows(), 10):
		_steps.append(func() -> void: _ground_rows(z0, z0 + 10))
	_steps.append(func() -> void:
		for key in _chunks:
			_ground_end[key] = (_chunks[key] as MeshKit).vert_count())
	_steps.append(_flat_layers)
	for bd in L.buildings:
		_steps.append(func() -> void: _building(bd, _rng))
	_steps.append(func() -> void:
		for s in L.walls:
			var a: Vector2 = s["a"]
			_kit_at(a.x, a.y).segment_box(s["a"], s["b"], 0.0, s["h"], s["t"], Color(0.52, 0.50, 0.55), 0.0, Color(0.66, 0.64, 0.68)))
	_steps.append(func() -> void:
		for s in L.hedges:
			_hedge(s, _rng))
	_steps.append(func() -> void:
		for s in L.fences:
			_fence(s)
		for s in L.cart_blockers:
			_bollards(s))
	var trees: Array = L.trees
	for i0 in range(0, trees.size(), 12):
		_steps.append(func() -> void:
			for i in range(i0, mini(i0 + 12, trees.size())):
				_tree(trees[i]))
	_steps.append(_small_things)
	_steps.append(_lake)
	for kind in ["broad", "pine"]:
		for v in (CampusKit.BROAD_VARIANTS if kind == "broad" else CampusKit.PINE_VARIANTS):
			for lod in 2:
				_steps.append(func() -> void: CampusKit.tree(kind, v, lod))
	_steps.append(_containers)
	_steps.append(_commit_next)
	_steps.append(_tree_multimeshes)
	_steps.append(_glow_mesh)


## Runs the next step; true while there is more to do.
func step() -> bool:
	if _step_i >= _steps.size():
		return false
	var more: Variant = _steps[_step_i].call()
	if not (more is bool and more):
		_step_i += 1
	return _step_i < _steps.size()


## Fraction of the steps done (loading screen progress, never invented).
func progress() -> float:
	return float(_step_i) / float(maxi(_steps.size(), 1))


func _small_things() -> void:
	for r in L.rocks:
		var rp: Vector3 = r["pos"]
		var sz: Vector3 = r["size"]
		# layered boulder: a broad base and an offset cap, softly shaded
		var rk := _kit_at(rp.x, rp.z)
		var sd := int(rp.x * 13 + rp.z * 7)
		var stone := Color(0.47, 0.43, 0.40).lerp(Color(0.40, 0.40, 0.43), float(posmod(sd, 5)) / 4.0)
		rk.soft_blob(rp + Vector3(0, sz.y * 0.38, 0), sz * Vector3(0.58, 0.5, 0.56), stone, 5, 9, 0.0, 0.12, sd)
		rk.soft_blob(rp + Vector3(sz.x * 0.12, sz.y * 0.72, -sz.z * 0.08), sz * Vector3(0.36, 0.34, 0.34), stone.lightened(0.06), 4, 7, 0.0, 0.1, sd + 1)
	for p in L.platforms:
		var pc: Vector3 = p["center"]
		var ps: Vector3 = p["size"]
		var k2 := _kit_at(pc.x, pc.z)
		k2.box(pc - Vector3(0, ps.y * 0.5, 0), ps, p["color"])
		if p.get("dock", false):
			for zz in range(int(-ps.z * 0.5), int(ps.z * 0.5) + 1, 3):
				for sx in [-1.0, 1.0]:
					k2.cylinder(Vector3(pc.x + sx * ps.x * 0.45, -1.5, pc.z + zz), 0.12, 1.9, Color(0.35, 0.25, 0.18), 6)
		else:
			k2.box(Vector3(pc.x, pc.y * 0.5 - 0.3, pc.z), Vector3(ps.x * 0.9, pc.y, ps.z * 0.9), Color(0.45, 0.43, 0.48))
	for rp2 in L.ramps:
		_ramp_visual(rp2)
	for lp in L.lamps:
		_lamp(lp)
	for bn in L.benches:
		_bench(bn)
	for pr in L.props:
		_prop(pr)


func _containers() -> void:
	_world_mat = ShaderMaterial.new()
	_world_mat.shader = WORLD_SHADER
	container = Node3D.new()
	container.name = "CampusVisuals"
	_root.add_child(container)
	water_nodes = _waters(container)
	var fmat := ShaderMaterial.new()
	fmat.shader = FOLIAGE_SHADER
	foliage_material = fmat
	_commit_keys.clear()
	for key in _chunks:
		_commit_keys.append([0, key])
	for key in _foliage:
		_commit_keys.append([1, key])
	for key in _detail:
		_commit_keys.append([2, key])


## One chunk's mesh per call (the heaviest single pieces of the build).
func _commit_next() -> bool:
	if _commit_keys.is_empty():
		return false
	var item: Array = _commit_keys.pop_front()
	var pass_i: int = item[0]
	var key: Vector2i = item[1]
	var mk: MeshKit = [_chunks, _foliage, _detail][pass_i][key]
	if pass_i != 1 and kit != null:
		# paths, plazas, walls, props and building feet: baked soft AO and
		# warm lamp light (the ground was lit as it was built)
		kit.bake(mk, int(_ground_end.get(key, 0)) if pass_i == 0 else 0, 3.0)
	var mesh := mk.commit()
	if mesh != null:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = foliage_material if pass_i == 1 else _world_mat
		mi.name = (["Chunk_%d_%d", "Foliage_%d_%d", "Detail_%d_%d"][pass_i]) % [key.x, key.y]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _quality >= 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if pass_i == 2:
			# measured to the chunk's centre: covers the camera's surroundings
			mi.visibility_range_end = DETAIL_M if _quality >= 1 else DETAIL_M * 0.7
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		if pass_i == 1:
			# tree canopies stop drawing where the night fog has already
			# swallowed them (no dithered fade: a clean cut inside the fog)
			mi.visibility_range_end = 230.0 if _quality >= 1 else 150.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		container.add_child(mi)
	return not _commit_keys.is_empty()


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
	container.add_child(gmi)


const GROUND_STEP := 2.0
var _noise: FastNoiseLite


func _ground(_rng: RandomNumberGenerator) -> void:
	_ground_rows(0, ground_rows())


func ground_rows() -> int:
	return int(CampusLayout.BOUNDS.size.y / GROUND_STEP)


## One band of the 2 m ground grid (rows z0..z1).
func _ground_rows(z_from: int, z_to: int) -> void:
	var b := CampusLayout.BOUNDS
	var nx := int(b.size.x / GROUND_STEP)
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.seed = 11
		_noise.frequency = 0.035
		_noise2 = FastNoiseLite.new()
		_noise2.seed = 23
		_noise2.frequency = 0.16
	var row_a := _ground_row(z_from, nx)
	for zi in range(z_from, mini(z_to, ground_rows())):
		var row_b := _ground_row(zi + 1, nx)
		for xi in nx:
			var a: Array = row_a[xi]
			var bb: Array = row_a[xi + 1]
			var c: Array = row_b[xi + 1]
			var d: Array = row_b[xi]
			var k := _kit_at(b.position.x + xi * GROUND_STEP + 1.0, b.position.y + zi * GROUND_STEP + 1.0)
			k.tri_n(a[0], bb[0], c[0], a[1], bb[1], c[1], a[2], bb[2], c[2])
			k.tri_n(a[0], c[0], d[0], a[1], c[1], d[1], a[2], c[2], d[2])
		row_a = row_b


var _noise2: FastNoiseLite


## One row of ground vertices: [position, smooth normal, lit colour].
## Lawn tone from two noise scales (broad patches, fine variation), muddy
## banks into the water pits, then the kit's baked AO and warm light.
func _ground_row(zi: int, nx: int) -> Array:
	var b := CampusLayout.BOUNDS
	var out: Array = []
	var z := b.position.y + zi * GROUND_STEP
	var lawn_a := Color(0.24, 0.45, 0.30)
	var lawn_b := Color(0.33, 0.53, 0.30)
	var mud := Color(0.31, 0.29, 0.24)
	for xi in nx + 1:
		var x := b.position.x + xi * GROUND_STEP
		var y := grid_y(L, x, z)
		var hl := grid_y(L, x - GROUND_STEP, z)
		var hr := grid_y(L, x + GROUND_STEP, z)
		var hd := grid_y(L, x, z - GROUND_STEP)
		var hu := grid_y(L, x, z + GROUND_STEP)
		var n := Vector3((hl - hr) / (2.0 * GROUND_STEP), 1.0, (hd - hu) / (2.0 * GROUND_STEP)).normalized()
		var p := Vector3(x, y, z)
		var t := 0.5 + 0.5 * _noise.get_noise_2d(x, z)
		var col := lawn_a.lerp(lawn_b, t)
		col = col.lightened(0.04 * _noise2.get_noise_2d(x, z))
		var low := minf(minf(y, hl), minf(minf(hr, hd), hu))
		if low < -0.1:
			col = col.lerp(mud, 1.0 if y < -0.1 else 0.7)
		if kit != null:
			var lt: Array = kit.light_at(p, n)
			var m: Color = lt[0]
			var ad: Color = lt[1]
			col = Color(col.r * m.r + ad.r, col.g * m.g + ad.g, col.b * m.b + ad.b)
		out.append([p, n, col])
	return out


func _flat_layers() -> void:
	for pl in L.plazas:
		var c: Vector2 = pl["center"]
		var k := _kit_at(c.x, c.y)
		if pl["shape"] == "circle":
			k.disc(Vector3(c.x, 0.03, c.y), pl["radius"], pl["color"], 24)
		else:
			var hs: Vector2 = pl["size"] * 0.5
			var overlaps_water := false
			for w in L.waters:
				if float(w["surface_y"]) < 0.0 and Rect2(c - hs, hs * 2.0).grow(1.0).has_point(w["center"]):
					overlaps_water = true
			if not overlaps_water:
				k.quad(Vector3(c.x - hs.x, 0.03, c.y - hs.y), Vector3(c.x + hs.x, 0.03, c.y - hs.y), Vector3(c.x + hs.x, 0.03, c.y + hs.y), Vector3(c.x - hs.x, 0.03, c.y + hs.y), pl["color"])
			else:
				# tile the paving and leave the water open
				var x0 := c.x - hs.x
				var z0 := c.y - hs.y
				var nx := int(hs.x * 2.0)
				var nz := int(hs.y * 2.0)
				for iz in nz:
					for ix in nx:
						var tc := Vector2(x0 + ix + 0.5, z0 + iz + 0.5)
						var wet := false
						for w2 in L.waters:
							if CampusLayout.in_water_shape(w2, tc, 0.3):
								wet = true
								break
						if wet:
							continue
						k.quad(Vector3(x0 + ix, 0.03, z0 + iz), Vector3(x0 + ix + 1, 0.03, z0 + iz), Vector3(x0 + ix + 1, 0.03, z0 + iz + 1), Vector3(x0 + ix, 0.03, z0 + iz + 1), pl["color"])
	for r in L.roads:
		var pts: PackedVector2Array = r["pts"]
		for i in pts.size() - 1:
			var a := pts[i]
			var bb := pts[i + 1]
			var sub := PackedVector2Array([a, bb])
			_kit_at((a.x + bb.x) * 0.5, (a.y + bb.y) * 0.5).ribbon(sub, float(r["w"]) + 0.8, 0.045, Color(0.36, 0.36, 0.40), 0.0, false)
			_kit_at((a.x + bb.x) * 0.5, (a.y + bb.y) * 0.5).ribbon(sub, r["w"], 0.05, Color(0.17, 0.18, 0.22), 0.0, false)
			# centre-line dashes (slightly emissive so roads read at night)
			var dir := (bb - a).normalized()
			var L2 := a.distance_to(bb)
			var s := 2.0
			while s < L2 - 2.0:
				var p0 := a + dir * s
				var p1 := a + dir * (s + 1.6)
				_kit_at(p0.x, p0.y).ribbon(PackedVector2Array([p0, p1]), 0.22, 0.06, Color(0.95, 0.82, 0.35), 0.35, false)
				s += 4.0
		for i in range(1, pts.size() - 1):
			_kit_at(pts[i].x, pts[i].y).disc(Vector3(pts[i].x, 0.052, pts[i].y), float(r["w"]) * 0.5, Color(0.17, 0.18, 0.22), 12)
	for pth in L.paths:
		var pts2: PackedVector2Array = pth["pts"]
		var pc: Color = pth["color"]
		for i in pts2.size() - 1:
			var a2 := pts2[i]
			var b2 := pts2[i + 1]
			var pk := _kit_at((a2.x + b2.x) * 0.5, (a2.y + b2.y) * 0.5)
			pk.ribbon(PackedVector2Array([a2, b2]), pth["w"], 0.07, pc, 0.0, false)
			# worn edges: a slightly darker border each side (V4)
			var dd := (b2 - a2).normalized()
			var nn := Vector2(-dd.y, dd.x) * (float(pth["w"]) * 0.5 - 0.12)
			for sgn in [-1.0, 1.0]:
				pk.ribbon(PackedVector2Array([a2 + nn * sgn, b2 + nn * sgn]), 0.24, 0.074, pc.darkened(0.12), 0.0, false)
		for i in pts2.size():
			_kit_at(pts2[i].x, pts2[i].y).disc(Vector3(pts2[i].x, 0.072, pts2[i].y), float(pth["w"]) * 0.5, pth["color"], 10)


func _window_face(k: MeshKit, origin: Vector3, right: Vector3, up: Vector3, normal: Vector3, width: float, height: float, warm: float, rng: RandomNumberGenerator, y_start: float = 1.2) -> void:
	var cols := int(width / 3.2)
	var rows := int((height - y_start) / 3.0)
	if cols <= 0 or rows <= 0:
		return
	var spacing_x := width / float(cols)
	for r in rows:
		for c in cols:
			var lit := rng.randf() < warm
			var col := Color(1.0, 0.80, 0.45) if lit else Color(0.14, 0.18, 0.30)
			var em := 1.1 if lit else 0.05
			var cx := -width * 0.5 + spacing_x * (float(c) + 0.5)
			var cy := y_start + 3.0 * float(r) + 0.9
			var ctr := origin + right * cx + up * cy + normal * 0.06
			var hw := right * 0.6
			var hh := up * 0.8
			k.quad(ctr - hw + hh, ctr + hw + hh, ctr + hw - hh, ctr - hw - hh, col, em)
			# painted frame around the pane and a mullion cross (V4; near-field
			# detail mesh, so far facades keep their simpler look)
			var kd := _kit_at(ctr.x, ctr.z, false, true)
			var frame := Color(0.9, 0.88, 0.84)
			var f0 := ctr + normal * 0.03
			var t := 0.09
			kd.quad(f0 - hw - right * t + hh + up * t, f0 + hw + right * t + hh + up * t, f0 + hw + right * t + hh, f0 - hw - right * t + hh, frame)
			kd.quad(f0 - hw - right * t - hh, f0 + hw + right * t - hh, f0 + hw + right * t - hh - up * t, f0 - hw - right * t - hh - up * t, frame)
			kd.quad(f0 - hw - right * t + hh, f0 - hw + hh, f0 - hw - hh, f0 - hw - right * t - hh, frame)
			kd.quad(f0 + hw + hh, f0 + hw + right * t + hh, f0 + hw + right * t - hh, f0 + hw - hh, frame)
			kd.quad(f0 - right * 0.035 + hh, f0 + right * 0.035 + hh, f0 + right * 0.035 - hh, f0 - right * 0.035 - hh, frame.darkened(0.08))
			kd.quad(f0 - hw + up * 0.035 + up * 0.15, f0 + hw + up * 0.035 + up * 0.15, f0 + hw - up * 0.035 + up * 0.15, f0 - hw - up * 0.035 + up * 0.15, frame.darkened(0.08))
			# a projecting stone sill
			var sill_c := ctr - hh - up * 0.14 + normal * 0.08
			kd.box(sill_c, Vector3(1.5, 0.12, 0.22), Color(0.82, 0.81, 0.78), atan2(-right.z, right.x), 0.0, Color(0.9, 0.89, 0.86))


func _building(bd: Dictionary, rng: RandomNumberGenerator) -> void:
	var pos: Vector2 = bd["pos"]
	var size: Vector2 = bd["size"]
	var h: float = bd["h"]
	var k := _kit_at(pos.x, pos.y)
	var wall: Color = bd["wall"]
	var roof: Color = bd["roof"]
	var warm: float = float(bd.get("warm", 0.5))
	var id: String = bd["id"]
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	if id == "tower":
		# arch pillars + upper tower + clock + spire
		var base_y: float = bd["base_y"]
		for sx in [-1.0, 1.0]:
			k.box(Vector3(pos.x + sx * 2.6, base_y * 0.5, pos.y), Vector3(0.8, base_y, size.y), wall.darkened(0.1))
		k.box(Vector3(pos.x, (base_y + h) * 0.5, pos.y), Vector3(size.x, h - base_y, size.y), wall)
		for face: Vector3 in [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
			var cpos: Vector3 = Vector3(pos.x, h - 4.0, pos.y) + face * (hx + 0.08)
			var right := Vector3.UP.cross(face).normalized()
			# clock face: glowing disc made of a fan
			for i in 12:
				var a0 := TAU * float(i) / 12.0
				var a1 := TAU * float(i + 1) / 12.0
				var p0 := cpos + (right * cos(a0) + Vector3.UP * sin(a0)) * 1.8
				var p1 := cpos + (right * cos(a1) + Vector3.UP * sin(a1)) * 1.8
				k.tri(cpos, p1, p0, Color(0.98, 0.94, 0.78), 0.9)
				k.tri(cpos, p0, p1, Color(0.98, 0.94, 0.78), 0.9)
			# hands pointing to 3:00 (hour hand right, minute hand up)
			k.box(cpos + face * 0.05 + right * 0.55, Vector3(1.1, 0.18, 0.18).abs() if face.x == 0 else Vector3(0.18, 0.18, 1.1), Color(0.1, 0.1, 0.15))
			k.box(cpos + face * 0.06 + Vector3.UP * 0.75, Vector3(0.14, 1.5, 0.14), Color(0.1, 0.1, 0.15))
		k.cone(Vector3(pos.x, h, pos.y), 4.4, 8.0, roof, 4)
		k.blob(Vector3(pos.x, h + 8.4, pos.y), Vector3(0.35, 0.35, 0.35), Color(1.0, 0.85, 0.4), 2, 6, 1.5)
		k.box(Vector3(pos.x, base_y + 0.4, pos.y), Vector3(size.x + 0.6, 0.8, size.y + 0.6), wall.lightened(0.15))
		return
	if id == "shed":
		k.box(Vector3(pos.x, h * 0.5, pos.y - hz + 0.3), Vector3(size.x, h, 0.6), wall)
		k.box(Vector3(pos.x - hx + 0.3, h * 0.5, pos.y), Vector3(0.6, h, size.y), wall)
		k.box(Vector3(pos.x + hx - 0.3, h * 0.5, pos.y), Vector3(0.6, h, size.y), wall)
		k.gable_roof(pos, size, h, 2.0, roof)
		k.quad(Vector3(pos.x - hx + 0.6, 0.06, pos.y - hz + 0.6), Vector3(pos.x + hx - 0.6, 0.06, pos.y - hz + 0.6), Vector3(pos.x + hx - 0.6, 0.06, pos.y + hz), Vector3(pos.x - hx + 0.6, 0.06, pos.y + hz), Color(0.3, 0.3, 0.32))
		# sign + warm work light
		k.box(Vector3(pos.x, h + 0.2, pos.y + hz + 0.4), Vector3(9.0, 1.4, 0.2), Color(0.95, 0.75, 0.25))
		k.box(Vector3(pos.x, h + 0.2, pos.y + hz + 0.52), Vector3(8.0, 0.25, 0.05), Color(0.2, 0.15, 0.1))
		_glow_disc(Vector3(pos.x, 0.12, pos.y + hz + 2.0), 9.0)
		k.blob(Vector3(pos.x, h - 0.6, pos.y + hz - 0.4), Vector3(0.5, 0.25, 0.5), Color(1.0, 0.9, 0.6), 2, 6, 2.0)
		return
	if bd.get("dome", false):
		# drum with a plinth and cornice, under a smooth dome (V4)
		k.revolve(Vector3(pos.x, 0, pos.y), PackedVector2Array([Vector2(hx + 0.35, 0.0), Vector2(hx + 0.3, 0.6), Vector2(hx, 0.7), Vector2(hx, h - 0.4),
			Vector2(hx + 0.3, h - 0.3), Vector2(hx + 0.3, h)]), PackedColorArray([wall.darkened(0.3), wall.darkened(0.2), wall, wall, wall.lightened(0.2), wall.lightened(0.22)]), 20)
		var dome := PackedVector2Array()
		var dcol := PackedColorArray()
		for di in 7:
			var a := PI * 0.5 * float(di) / 6.0
			dome.append(Vector2(hx * cos(a), h + hx * 0.85 * sin(a)))
			dcol.append(roof.lightened(0.04 * float(di)))
		k.revolve(Vector3(pos.x, 0, pos.y), dome, dcol, 20, PackedFloat32Array(), 0.15)
		k.box(Vector3(pos.x, h + hx * 0.4, pos.y + 1.0), Vector3(1.2, 2.2, hx * 1.6), Color(0.12, 0.14, 0.25))
		return
	var top_col := wall.lightened(0.1)
	k.box(Vector3(pos.x, h * 0.5, pos.y), Vector3(size.x, h, size.y), wall, 0.0, 0.0 if not bd.get("glass", false) else 0.25, top_col)
	# plinth, a moulded cornice and corner quoins with soft edges (V4)
	k.chamfer_box(Vector3(pos.x, 0.35, pos.y), Vector3(size.x + 0.5, 0.7, size.y + 0.5), wall.darkened(0.25), 0.1)
	k.chamfer_box(Vector3(pos.x, h - 0.2, pos.y), Vector3(size.x + 0.6, 0.5, size.y + 0.6), wall.lightened(0.25), 0.12)
	k.chamfer_box(Vector3(pos.x, h - 0.55, pos.y), Vector3(size.x + 0.3, 0.2, size.y + 0.3), wall.lightened(0.18), 0.06)
	if not bd.get("glass", false):
		for cx in [-1.0, 1.0]:
			for cz in [-1.0, 1.0]:
				k.chamfer_box(Vector3(pos.x + cx * (hx - 0.05), (h - 0.7) * 0.5 + 0.35, pos.y + cz * (hz - 0.05)), Vector3(0.7, h - 1.4, 0.7), wall.lightened(0.16), 0.08)
	if bd.get("glass", false):
		k.box(Vector3(pos.x, h * 0.5, pos.y), Vector3(size.x + 0.05, h * 0.8, size.y + 0.05), Color(0.55, 0.9, 0.8), 0.0, 0.35)
		k.gable_roof(pos, size, h, 3.0, roof, 0.2)
		return
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = hash(id)
	_window_face(k, Vector3(pos.x, 0, pos.y - hz), Vector3(-1, 0, 0), Vector3.UP, Vector3(0, 0, -1), size.x - 2.0, h - 0.8, warm, rng_b)
	_window_face(k, Vector3(pos.x, 0, pos.y + hz), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), size.x - 2.0, h - 0.8, warm, rng_b)
	_window_face(k, Vector3(pos.x - hx, 0, pos.y), Vector3(0, 0, 1), Vector3.UP, Vector3(-1, 0, 0), size.y - 2.0, h - 0.8, warm, rng_b)
	_window_face(k, Vector3(pos.x + hx, 0, pos.y), Vector3(0, 0, -1), Vector3.UP, Vector3(1, 0, 0), size.y - 2.0, h - 0.8, warm, rng_b)
	if size.x * size.y > 300.0:
		k.gable_roof(pos, size, h, minf(size.x, size.y) * 0.32, roof)
	else:
		k.gable_roof(pos, size, h, minf(size.x, size.y) * 0.4, roof)
	if bd.get("columns", false):
		for i in 6:
			var cz := pos.y - hz + 4.0 + float(i) * (size.y - 8.0) / 5.0
			k.cylinder(Vector3(pos.x + hx + 1.4, 0, cz), 0.45, h - 1.0, Color(0.88, 0.86, 0.82), 8)
		k.box(Vector3(pos.x + hx + 1.4, h - 0.6, pos.y), Vector3(2.0, 0.8, size.y - 4.0), Color(0.88, 0.86, 0.82))
	if bd.get("dorm", false):
		for dd in L.dorm_doors:
			var dp: Vector2 = dd["pos"]
			var n: Vector2 = dd["normal"]
			var right3 := Vector3(n.y, 0, -n.x)
			var base := Vector3(dp.x, 0, dp.y) + Vector3(n.x, 0, n.y) * 0.08
			# double doors with small windows, lit transom, white trim and a step
			var nn3 := Vector3(n.x, 0, n.y)
			var door_yaw := -atan2(-right3.z, right3.x)   # box() takes yaw; Basis(UP, yaw) * x = right3
			k.box(base + Vector3.UP * 1.15 - nn3 * 0.02, Vector3(2.3, 2.3, 0.08), Color(0.36, 0.22, 0.16), -door_yaw)
			for side in [-1.0, 1.0]:
				k.box(base + right3 * (0.56 * side) + Vector3.UP * 1.62 + nn3 * 0.03, Vector3(0.5, 0.62, 0.03), Color(1.0, 0.78, 0.45), -door_yaw, 1.3)
				k.box(base + right3 * (0.16 * side) + Vector3.UP * 1.05 + nn3 * 0.06, Vector3(0.06, 0.14, 0.05), Color(0.95, 0.8, 0.4), -door_yaw)
			k.box(base + Vector3.UP * 1.15 + nn3 * 0.03, Vector3(0.05, 2.3, 0.04), Color(0.22, 0.13, 0.1), -door_yaw)
			k.box(base + Vector3.UP * 2.52 + nn3 * 0.02, Vector3(2.2, 0.36, 0.03), Color(1.0, 0.8, 0.5), -door_yaw, 1.5)
			for side2 in [-1.0, 1.0]:
				k.box(base + right3 * (1.25 * side2) + Vector3.UP * 1.4 + nn3 * 0.06, Vector3(0.18, 2.8, 0.14), Color(0.94, 0.92, 0.88), -door_yaw)
			k.box(base + Vector3.UP * 2.82 + nn3 * 0.06, Vector3(2.7, 0.18, 0.16), Color(0.94, 0.92, 0.88), -door_yaw)
			k.box(Vector3(dp.x, 0.04, dp.y) + nn3 * 0.55, Vector3(2.9, 0.08, 1.0), Color(0.7, 0.68, 0.72), -door_yaw, 0.0, Color(0.78, 0.76, 0.8))
			k.box(base + Vector3.UP * 2.8 + Vector3(n.x, 0, n.y) * 0.2, Vector3(2.8, 0.35, 2.8) * Vector3(absf(right3.x) + absf(n.x) * 0.3, 1, absf(right3.z) + absf(n.y) * 0.3), Color(0.9, 0.86, 0.78))
			k.blob(base + Vector3.UP * 3.2 + Vector3(n.x, 0, n.y) * 0.4, Vector3(0.28, 0.32, 0.28), Color(1.0, 0.85, 0.5), 2, 6, 2.5)
			_glow_disc(Vector3(dp.x + n.x * 2.0, 0.11, dp.y + n.y * 2.0), 5.0)
			k.quad(Vector3(dp.x, 0.09, dp.y) + Vector3(n.x, 0, n.y) * 0.3 - right3 * 1.3, Vector3(dp.x, 0.09, dp.y) + Vector3(n.x, 0, n.y) * 0.3 + right3 * 1.3, Vector3(dp.x, 0.09, dp.y) + Vector3(n.x, 0, n.y) * 2.2 + right3 * 1.3, Vector3(dp.x, 0.09, dp.y) + Vector3(n.x, 0, n.y) * 2.2 - right3 * 1.3, Color(0.75, 0.25, 0.25))
		# hanging house banners either side of the front door (blue + gold duck crest colours)
		for bx in [-4.5, 4.5]:
			k.box(Vector3(pos.x + bx, h - 3.2, pos.y - hz - 0.12), Vector3(1.6, 4.2, 0.1), Color(0.24, 0.32, 0.78))
			k.box(Vector3(pos.x + bx, h - 4.6, pos.y - hz - 0.18), Vector3(0.9, 0.9, 0.06), Color(1.0, 0.8, 0.25), 0.0, 0.3)
		k.box(Vector3(pos.x, 3.3, pos.y - hz - 1.2), Vector3(5.0, 0.25, 2.6), Color(0.3, 0.32, 0.5))
	else:
		# glowing entrance on the face toward campus centre, under a small
		# bracketed porch roof (V4: depth at the door)
		var to_c := (Vector2.ZERO - pos)
		var face_n := Vector2(signf(to_c.x), 0) if absf(to_c.x) * size.y > absf(to_c.y) * size.x else Vector2(0, signf(to_c.y))
		var fp := pos + face_n * (Vector2(hx, hz) * face_n.abs()).length()
		var right4 := Vector3(face_n.y, 0, -face_n.x)
		var nrm4 := Vector3(face_n.x, 0, face_n.y)
		var base4 := Vector3(fp.x, 0, fp.y) + nrm4 * 0.08
		k.quad(base4 - right4 * 1.0 + Vector3.UP * 2.4, base4 + right4 * 1.0 + Vector3.UP * 2.4, base4 + right4 * 1.0, base4 - right4 * 1.0, Color(0.95, 0.78, 0.5), 0.8)
		var pyaw := atan2(-right4.z, right4.x)
		var trim := Color(0.9, 0.88, 0.84)
		k.chamfer_box(base4 + nrm4 * 1.0 + Vector3.UP * 3.0, Vector3(3.4, 0.22, 2.2), trim, 0.06, pyaw, trim.lightened(0.04))
		k.chamfer_box(base4 + nrm4 * 1.0 + Vector3.UP * 3.24, Vector3(3.0, 0.26, 1.9), Color(roof.r, roof.g, roof.b).lightened(0.05), 0.08, pyaw)
		# wall brackets, not posts: the colliders are unchanged, so nothing
		# decorative may stand where runners walk
		for side in [-1.0, 1.0]:
			k.chamfer_box(base4 + nrm4 * 0.45 + right4 * (1.4 * side) + Vector3.UP * 2.7, Vector3(0.16, 0.5, 0.9), trim.darkened(0.08), 0.04, pyaw)
		k.chamfer_box(Vector3(fp.x, 0.08, fp.y) + nrm4 * 1.1, Vector3(3.2, 0.16, 2.0), Color(0.7, 0.68, 0.72), 0.05, pyaw, Color(0.78, 0.76, 0.8))
		_glow_disc(Vector3(fp.x + face_n.x * 1.6, 0.11, fp.y + face_n.y * 1.6), 3.6)


func _hedge(s: Dictionary, rng: RandomNumberGenerator) -> void:
	var a: Vector2 = s["a"]
	var b: Vector2 = s["b"]
	var k := _kit_at((a.x + b.x) * 0.5, (a.y + b.y) * 0.5)
	var h: float = s["h"]
	var t: float = s["t"]
	var col := Color(0.18, 0.40, 0.23)
	var d2 := b - a
	var mid := (a + b) * 0.5
	var L2 := a.distance_to(b)
	# a clipped body with soft edges and a row of rounded tops (V4)
	k.chamfer_box(Vector3(mid.x, (h - 0.25) * 0.5, mid.y), Vector3(L2 + t * 0.2, h - 0.25, t), col.darkened(0.08), 0.18, atan2(-d2.y, d2.x), col.lightened(0.04))
	var n := int(L2 / 1.4)
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(max(n, 1)))
		k.soft_blob(Vector3(p.x, h - 0.3, p.y), Vector3(t * 0.6, 0.42, t * 0.6), col.lightened(0.04 + 0.05 * float(i % 2)), 3, 7, 0.25)


func _fence(s: Dictionary) -> void:
	var a: Vector2 = s["a"]
	var b: Vector2 = s["b"]
	var h: float = s["h"]
	var kind: String = s["kind"]
	var k := _kit_at((a.x + b.x) * 0.5, (a.y + b.y) * 0.5)
	var L2 := a.distance_to(b)
	if kind == "buoy":
		k.segment_box(a, b, -0.35, 0.05, 0.05, Color(0.9, 0.9, 0.85))
		var n := int(L2 / 1.2)
		for i in n + 1:
			var p := a.lerp(b, float(i) / float(max(n, 1)))
			k.blob(Vector3(p.x, -0.3, p.y), Vector3(0.28, 0.28, 0.28), Color(0.95, 0.25, 0.2) if i % 2 == 0 else Color(0.95, 0.95, 0.9), 2, 6, 0.3)
		return
	var post_col := Color(0.14, 0.14, 0.18) if kind == "iron" else Color(0.45, 0.32, 0.22)
	var step := 1.6 if kind == "iron" else 2.4
	var n2 := int(L2 / step)
	for i in n2 + 1:
		var p2 := a.lerp(b, float(i) / float(max(n2, 1)))
		k.box(Vector3(p2.x, h * 0.5, p2.y), Vector3(0.14, h, 0.14), post_col)
	if kind == "iron":
		k.segment_box(a, b, h - 0.12, 0.08, 0.08, post_col)
		k.segment_box(a, b, 0.35, 0.08, 0.08, post_col)
		var bars := int(L2 / 0.25)
		for i in bars:
			var p3 := a.lerp(b, (float(i) + 0.5) / float(bars))
			k.box(Vector3(p3.x, h * 0.5, p3.y), Vector3(0.04, h - 0.1, 0.04), post_col)
	else:
		k.segment_box(a, b, h * 0.45, 0.12, 0.12, post_col.lightened(0.1))
		k.segment_box(a, b, h * 0.85, 0.12, 0.12, post_col.lightened(0.1))


func _bollards(s: Dictionary) -> void:
	var a: Vector2 = s["a"]
	var b: Vector2 = s["b"]
	var L2 := a.distance_to(b)
	var n := int(ceil(L2 / 2.0))
	var grey := Color(0.32, 0.33, 0.38)
	var band := Color(1.0, 0.82, 0.25)
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(max(n, 1)))
		var k := _kit_at(p.x, p.y, false, true)
		# rounded-top bollard with a reflective band
		k.revolve(Vector3(p.x, 0, p.y), PackedVector2Array([Vector2(0.14, 0.0), Vector2(0.13, 0.6)]),
			PackedColorArray([grey.darkened(0.25), grey]), 7)
		k.revolve(Vector3(p.x, 0, p.y), PackedVector2Array([Vector2(0.135, 0.6), Vector2(0.135, 0.72)]), PackedColorArray([band]), 7, PackedFloat32Array(), 0.6)
		k.revolve(Vector3(p.x, 0, p.y), PackedVector2Array([Vector2(0.13, 0.72), Vector2(0.12, 0.86), Vector2(0.0, 0.93)]),
			PackedColorArray([grey, grey.lightened(0.1), grey.lightened(0.15)]), 7)


func _tree(t: Dictionary) -> void:
	# one MultiMesh instance per tree (V4 kit): uniform scale to its height,
	# a turn and a gentle tint so no two neighbours look stamped
	var p: Vector2 = t["pos"]
	var kind := "pine" if String(t["kind"]) == "pine" else "broad"
	var v := CampusKit.variant_of(t)
	var h: float = t["h"]
	var tint: float = t["tint"]
	# trees use double-size chunks: fewer draw calls, still culled by region
	var key := Vector2i(int(floor((p.x - CampusLayout.BOUNDS.position.x) / (CHUNK.x * 2.0))), int(floor((p.y - CampusLayout.BOUNDS.position.y) / (CHUNK.y * 2.0))))
	var per: Dictionary = _trees.get(key, {})
	var vk := "%s%d" % [kind, v]
	var list: Array = per.get(vk, [])
	var s := h / CampusKit.REF_H
	var yaw := fposmod(p.x * 1.7 + p.y * 2.3, TAU)
	var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), Vector3(p.x, ground_y(L, p.x, p.y), p.y))
	var col := Color(1, 1, 1).lerp(Color(1.12, 1.06, 0.86), tint) if kind == "broad" else Color(0.95, 0.98, 1.0).lerp(Color(1.06, 1.08, 1.02), tint)
	list.append([xf, col])
	per[vk] = list
	_trees[key] = per


## Per chunk and variant: MultiMeshes for trunks (world material) and crowns
## (canopy material, which parts around the camera), near and far LOD.
## Visibility distance is measured to the chunk's centre (tree chunks are
## 128 x 120 m), so the near range covers past the camera's own chunk.
const TREE_NEAR_M := 80.0
func _tree_multimeshes() -> void:
	for key in _trees:
		var per: Dictionary = _trees[key]
		for vk in per:
			var list: Array = per[vk]
			var kind := "pine" if String(vk).begins_with("pine") else "broad"
			var variant := int(String(vk).substr(String(vk).length() - 1))
			# near LOD up to NEAR_M from the chunk, the light one beyond it
			for lod in 2:
				var meshes := CampusKit.tree(kind, variant, lod)
				for part in ["trunk", "crown"]:
					var mm := MultiMesh.new()
					mm.transform_format = MultiMesh.TRANSFORM_3D
					mm.use_colors = true
					mm.mesh = meshes[part]
					mm.instance_count = list.size()
					for i in list.size():
						mm.set_instance_transform(i, list[i][0])
						mm.set_instance_color(i, list[i][1] if part == "crown" else Color(1, 1, 1))
					var mmi := MultiMeshInstance3D.new()
					mmi.multimesh = mm
					mmi.material_override = foliage_material if part == "crown" else _world_mat
					mmi.name = "Trees_%s_%s_lod%d_%d_%d" % [vk, part, lod, key.x, key.y]
					# far trees cast no shadow (the shadow range ends well before)
					mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _quality >= 1 and lod == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					if lod == 0:
						mmi.visibility_range_end = TREE_NEAR_M
					else:
						mmi.visibility_range_begin = TREE_NEAR_M
						mmi.visibility_range_end = 230.0 if _quality >= 1 else 150.0
					mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
					container.add_child(mmi)


func _lamp(lp: Vector2) -> void:
	var k := _kit_at(lp.x, lp.y, false, true)
	var iron := Color(0.17, 0.19, 0.25)
	var b := Vector3(lp.x, 0, lp.y)
	# a turned cast-iron post: stepped base, slim shaft, collar
	k.revolve(b, PackedVector2Array([Vector2(0.27, 0.0), Vector2(0.26, 0.12), Vector2(0.17, 0.2), Vector2(0.16, 0.36), Vector2(0.09, 0.46),
		Vector2(0.075, 3.0), Vector2(0.12, 3.12), Vector2(0.16, 3.22), Vector2(0.06, 3.3)]),
		PackedColorArray([iron.darkened(0.3), iron.darkened(0.2), iron, iron, iron, iron.lightened(0.05), iron.lightened(0.08), iron.lightened(0.08), iron]), 8)
	# glass lantern (warm, emissive) with a rounded cap and finial
	k.revolve(b, PackedVector2Array([Vector2(0.06, 3.3), Vector2(0.2, 3.36), Vector2(0.27, 3.62), Vector2(0.24, 3.76)]),
		PackedColorArray([Color(1.0, 0.86, 0.56)]), 8, PackedFloat32Array(), 2.0)
	k.revolve(b, PackedVector2Array([Vector2(0.24, 3.74), Vector2(0.4, 3.8), Vector2(0.24, 3.94), Vector2(0.05, 4.12), Vector2(0.0, 4.16)]),
		PackedColorArray([iron, iron.lightened(0.1), iron.lightened(0.12), iron, iron]), 8)
	_glow_disc(Vector3(lp.x, 0.1, lp.y), 4.2)


func _bench(bn: Dictionary) -> void:
	var p: Vector2 = bn["pos"]
	var yaw: float = bn["rot"]
	var k := _kit_at(p.x, p.y, false, true)
	var wood := Color(0.66, 0.45, 0.29)
	var iron := Color(0.18, 0.19, 0.24)
	var b := Basis(Vector3.UP, yaw)
	# three seat slats and two back slats on cast-iron ends with armrests
	for i in 3:
		k.chamfer_box(Vector3(p.x, 0.46, p.y) + b * Vector3(0, 0, -0.17 + 0.17 * float(i)), Vector3(1.9, 0.06, 0.14), wood.darkened(0.04 * float(i)), 0.025, yaw, wood.lightened(0.06))
	for j in 2:
		k.chamfer_box(Vector3(p.x, 0.7 + 0.2 * float(j), p.y) + b * Vector3(0, 0, 0.3), Vector3(1.9, 0.12, 0.05), wood, 0.02, yaw, wood.lightened(0.06))
	for sx in [-0.86, 0.86]:
		var off := b * Vector3(sx, 0, 0)
		k.box(Vector3(p.x, 0.22, p.y) + off, Vector3(0.08, 0.45, 0.55), iron, yaw)
		k.box(Vector3(p.x, 0.66, p.y) + off + b * Vector3(0, 0, 0.27), Vector3(0.08, 0.5, 0.08), iron, yaw)
		k.box(Vector3(p.x, 0.66, p.y) + off + b * Vector3(0, 0, 0.02), Vector3(0.09, 0.05, 0.5), iron, yaw)


func _ramp_visual(rp: Dictionary) -> void:
	var from: Vector3 = rp["from"]
	var to: Vector3 = rp["to"]
	var w: float = rp["w"]
	var k := _kit_at(from.x, from.z)
	var d := to - from
	var x_axis := d.normalized()
	var z_axis := x_axis.cross(Vector3.UP).normalized()
	var y_axis := z_axis.cross(x_axis).normalized()
	var basis := Basis(x_axis * d.length(), y_axis * 0.4, z_axis * w)
	k.box_xf(Transform3D(basis, (from + to) * 0.5 - y_axis * 0.2), rp["color"])
	# steps texture: little ridges
	var n := int(d.length() / 0.7)
	for i in n:
		var p := from.lerp(to, (float(i) + 0.5) / float(n))
		k.box(p + Vector3(0, 0.02, 0), Vector3(0.12, 0.06, w * 0.96), Color(0.7, 0.68, 0.7), atan2(-x_axis.z, x_axis.x))


func _prop(pr: Dictionary) -> void:
	var p: Vector2 = pr["pos"]
	var k := _kit_at(p.x, p.y)
	match String(pr["kind"]):
		"bike_rack":
			for i in 4:
				k.box(Vector3(p.x - 1.5 + float(i), 0.4, p.y), Vector3(0.08, 0.8, 0.8), Color(0.6, 0.62, 0.7))
		"noticeboard":
			k.box(Vector3(p.x, 1.3, p.y), Vector3(2.0, 1.4, 0.15), Color(0.55, 0.4, 0.3))
			k.box(Vector3(p.x, 1.35, p.y - 0.09), Vector3(1.7, 1.1, 0.02), Color(0.9, 0.85, 0.7), 0.0, 0.15)
		"lifeguard":
			k.box(Vector3(p.x, 1.0, p.y), Vector3(0.9, 2.0, 0.9), Color(0.95, 0.95, 0.95))
			k.box(Vector3(p.x, 2.15, p.y), Vector3(1.0, 0.3, 1.0), Color(0.95, 0.3, 0.25))
		"gazebo":
			var cream := Color(0.95, 0.95, 0.92)
			k.revolve(Vector3(p.x, 0, p.y), PackedVector2Array([Vector2(3.3, 0.0), Vector2(3.25, 0.2), Vector2(3.1, 0.28), Vector2(0.0, 0.3)]),
				PackedColorArray([Color(0.7, 0.68, 0.66), Color(0.85, 0.82, 0.78), Color(0.88, 0.85, 0.8), Color(0.88, 0.85, 0.8)]), 12)
			for i in 6:
				var a := TAU * float(i) / 6.0
				k.revolve(Vector3(p.x + cos(a) * 2.8, 0.28, p.y + sin(a) * 2.8), PackedVector2Array([Vector2(0.16, 0.0), Vector2(0.11, 0.14), Vector2(0.1, 2.4), Vector2(0.16, 2.52)]),
					PackedColorArray([cream.darkened(0.1), cream, cream, cream]), 8)
			# a softly flared roof with a finial
			var rf := Color(0.75, 0.35, 0.45)
			k.revolve(Vector3(p.x, 2.78, p.y), PackedVector2Array([Vector2(3.0, -0.05), Vector2(3.7, 0.0), Vector2(3.5, 0.18), Vector2(2.2, 0.75), Vector2(0.8, 1.55), Vector2(0.2, 1.9), Vector2(0.0, 2.0)]),
				PackedColorArray([rf.darkened(0.35), rf.darkened(0.1), rf, rf.lightened(0.05), rf.lightened(0.08), rf.lightened(0.1), rf.lightened(0.1)]), 12)
			k.soft_blob(Vector3(p.x, 4.85, p.y), Vector3(0.16, 0.2, 0.16), Color(1.0, 0.85, 0.45), 3, 6)
		"canoe":
			k.soft_blob(Vector3(p.x, 0.2, p.y), Vector3(0.6, 0.25, 2.2), Color(0.85, 0.3, 0.2), 4, 10)
		"frog":
			k.soft_blob(Vector3(p.x, 0.5, p.y), Vector3(0.6, 0.45, 0.5), Color(0.3, 0.75, 0.3), 5, 10)
			k.soft_blob(Vector3(p.x - 0.25, 0.9, p.y - 0.3), Vector3(0.16, 0.16, 0.16), Color(1, 1, 1), 3, 6)
			k.soft_blob(Vector3(p.x + 0.25, 0.9, p.y - 0.3), Vector3(0.16, 0.16, 0.16), Color(1, 1, 1), 3, 6)


func _lake() -> void:
	# Big calm lake beyond the north rail: purely visual backdrop.
	var y := -0.5
	for xi in range(-200, 200, 40):
		var k := _kit_at(clampf(float(xi) + 20.0, -150.0, 150.0), -149.0)
		k.quad(Vector3(xi, y, -260), Vector3(xi + 40, y, -260), Vector3(xi + 40, y, -146.5), Vector3(xi, y, -146.5), Color(0.08, 0.16, 0.30), 0.1)
	# distant tree line silhouettes across the lake
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 40:
		var x := -220.0 + float(i) * 11.0 + rng.randf_range(-3, 3)
		var k2 := _kit_at(clampf(x, -150.0, 150.0), -149.0)
		# soft rounded silhouettes, not spikes (V4)
		var rr := rng.randf_range(7, 11)
		var hh := rng.randf_range(9, 14)
		k2.revolve(Vector3(x, -0.5, -255 + rng.randf_range(-6, 6)), PackedVector2Array([Vector2(rr, 0.0), Vector2(rr * 0.95, hh * 0.5), Vector2(rr * 0.7, hh * 0.85), Vector2(0.0, hh)]),
			PackedColorArray([Color(0.06, 0.1, 0.14), Color(0.07, 0.12, 0.16), Color(0.08, 0.13, 0.17), Color(0.08, 0.13, 0.17)]), 6)
	# hills beyond the other edges so the world does not end abruptly
	for side in [[Vector2(-175, -150), Vector2(-175, 150)], [Vector2(175, -150), Vector2(175, 150)], [Vector2(-160, 168), Vector2(160, 168)]]:
		var a: Vector2 = side[0]
		var b: Vector2 = side[1]
		for j in 14:
			var p := a.lerp(b, float(j) / 13.0)
			var k3 := _kit_at(clampf(p.x, -150.0, 150.0), clampf(p.y, -140.0, 140.0))
			k3.soft_blob(Vector3(p.x, 0, p.y), Vector3(16, 9 + float(j % 3) * 3.0, 16), Color(0.1, 0.17, 0.19), 4, 9, 0.0, 0.08, j)


func _glow_disc(center: Vector3, r: float) -> void:
	var seg := 12
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


func _waters(container: Node3D) -> Dictionary:
	var out := {}
	for i in L.waters.size():
		var w: Dictionary = L.waters[i]
		var c: Vector2 = w["center"]
		var mi := MeshInstance3D.new()
		mi.name = "Water_%s" % w["id"]
		var mat := ShaderMaterial.new()
		mat.shader = WATER_SHADER
		mat.set_shader_parameter("target_color", w["color"])
		var y: float = w["surface_y"]
		var k := MeshKit.new()
		var deco := _kit_at(c.x, c.y)
		match String(w["shape"]):
			"circle":
				var r: float = w["radius"]
				k.disc(Vector3(0, 0, 0), r + 0.3, Color.WHITE, 32)
				mat.set_shader_parameter("shape_half", Vector2(r, r))
				mat.set_shader_parameter("shape_kind", 0.0)
				var rim: float = w["rim_h"]
				var th: float = w.get("rim_t", 0.5)
				# a rounded stone rim (inner wall, soft lip, outer wall)
				var stone2 := Color(0.72, 0.70, 0.74)
				deco.revolve(Vector3(c.x, 0, c.y), PackedVector2Array([Vector2(r, -0.4), Vector2(r, rim - 0.12), Vector2(r + 0.06, rim - 0.02),
					Vector2(r + th * 0.5, rim + 0.06), Vector2(r + th - 0.06, rim - 0.02), Vector2(r + th, rim - 0.12), Vector2(r + th + 0.06, 0.0)]),
					PackedColorArray([stone2.darkened(0.3), stone2.darkened(0.1), stone2.lightened(0.08), stone2.lightened(0.16), stone2.lightened(0.08), stone2, stone2.darkened(0.15)]), 32)
				# tiered centrepiece: turned pedestal, two basins and a glowing jet
				deco.revolve(Vector3(c.x, 0, c.y), PackedVector2Array([Vector2(1.3, -1.4), Vector2(1.25, 0.6), Vector2(0.9, 1.0), Vector2(2.1, 1.2), Vector2(2.15, 1.4),
					Vector2(1.9, 1.48), Vector2(0.5, 1.5), Vector2(0.42, 2.0), Vector2(0.48, 2.6), Vector2(1.0, 2.75), Vector2(1.02, 2.9), Vector2(0.3, 2.95)]),
					PackedColorArray([stone2.darkened(0.25), stone2.darkened(0.1), stone2, stone2.lightened(0.05), stone2.lightened(0.12), stone2.lightened(0.1),
					stone2, stone2.darkened(0.05), stone2, stone2.lightened(0.08), stone2.lightened(0.12), stone2]), 16)
				deco.cone(Vector3(c.x, 2.95, c.y), 0.35, 1.4, Color(0.65, 0.85, 1.0), 8, 0.9)
			"ellipse":
				var rx: float = w["rx"]
				var rz: float = w["rz"]
				k.ellipse_disc(Vector3.ZERO, rx + 0.6, rz + 0.6, Color.WHITE, 32)
				mat.set_shader_parameter("shape_half", Vector2(rx, rz))
				mat.set_shader_parameter("shape_kind", 0.0)
				# reeds, lily pads and shore stones around the bank
				var rng := RandomNumberGenerator.new()
				rng.seed = i * 97 + 3
				for j in 26:
					var a := TAU * float(j) / 26.0 + rng.randf_range(-0.1, 0.1)
					var bank := c + Vector2(cos(a) * (rx + 0.9), sin(a) * (rz + 0.9))
					if j % 3 == 0:
						deco.soft_blob(Vector3(bank.x, 0.0, bank.y), Vector3(0.7, 0.42, 0.6), Color(0.47, 0.45, 0.5), 4, 7, 0.0, 0.15, j)
					elif j % 3 == 1 and w["id"] == "pond":
						for q in 3:
							deco.cylinder(Vector3(bank.x + rng.randf_range(-0.3, 0.3), 0.0, bank.y + rng.randf_range(-0.3, 0.3)), 0.04, rng.randf_range(0.9, 1.5), Color(0.35, 0.55, 0.25), 4, 0.0, true, 0.01, 0.8)
				if w["id"] == "pond":
					for j in 8:
						var lp := c + Vector2(rng.randf_range(-rx * 0.6, rx * 0.6), rng.randf_range(-rz * 0.6, rz * 0.6))
						deco.disc(Vector3(lp.x, y + 0.04, lp.y), 0.6, Color(0.25, 0.55, 0.28), 7)
			"rect":
				var hs: Vector2 = w["size"] * 0.5
				k.quad(Vector3(-hs.x - 0.3, 0, -hs.y - 0.3), Vector3(hs.x + 0.3, 0, -hs.y - 0.3), Vector3(hs.x + 0.3, 0, hs.y + 0.3), Vector3(-hs.x - 0.3, 0, hs.y + 0.3), Color.WHITE)
				mat.set_shader_parameter("shape_half", hs)
				mat.set_shader_parameter("shape_kind", 1.0)
				var rim2: float = w["rim_h"]
				if rim2 > 0.0:
					var th2: float = w.get("rim_t", 0.5)
					var stone := Color(0.72, 0.70, 0.74)
					deco.chamfer_box(Vector3(c.x, rim2 * 0.5, c.y - hs.y - th2 * 0.5), Vector3(hs.x * 2 + th2 * 2, rim2, th2), stone, 0.08, 0.0, stone.lightened(0.15))
					deco.chamfer_box(Vector3(c.x, rim2 * 0.5, c.y + hs.y + th2 * 0.5), Vector3(hs.x * 2 + th2 * 2, rim2, th2), stone, 0.08, 0.0, stone.lightened(0.15))
					deco.chamfer_box(Vector3(c.x - hs.x - th2 * 0.5, rim2 * 0.5, c.y), Vector3(th2, rim2, hs.y * 2), stone, 0.08, 0.0, stone.lightened(0.15))
					deco.chamfer_box(Vector3(c.x + hs.x + th2 * 0.5, rim2 * 0.5, c.y), Vector3(th2, rim2, hs.y * 2), stone, 0.08, 0.0, stone.lightened(0.15))
					if w["id"] == "garden":
						# Lily Basin's flower beds: low planters of soft blooms (near detail)
						var fk := _kit_at(c.x, c.y, false, true)
						var blooms := [Color(0.95, 0.55, 0.7), Color(1.0, 0.85, 0.4), Color(0.95, 0.95, 0.9), Color(0.7, 0.55, 0.95)]
						for bi in 6:
							var side := -1.0 if bi % 2 == 0 else 1.0
							var bx := c.x - hs.x + 1.5 + float(bi / 2) * (hs.x - 1.5)
							var bz := c.y + side * (hs.y + th2 + 1.4)
							fk.chamfer_box(Vector3(bx, 0.2, bz), Vector3(2.4, 0.4, 0.9), Color(0.5, 0.36, 0.26), 0.06, 0.0, Color(0.26, 0.2, 0.15))
							for fi in 5:
								var fx := bx - 0.9 + float(fi) * 0.45
								fk.soft_blob(Vector3(fx, 0.5, bz + 0.12 * sin(float(fi * 3 + bi))), Vector3(0.24, 0.2, 0.24), (blooms[(fi + bi) % 4] as Color), 3, 6, 0.2)
					for j in 5:
						deco.disc(Vector3(c.x - hs.x + 2.0 + float(j) * 2.5, y + 0.04, c.y + sin(float(j)) * 2.0), 0.5, Color(0.3, 0.6, 0.3), 7)
				elif w["id"] == "pool":
					var tile := Color(0.92, 0.94, 0.96)
					# coping edge + ladders + lane ropes + diving board
					deco.segment_box(c + Vector2(-hs.x - 0.3, -hs.y - 0.3), c + Vector2(hs.x + 0.3, -hs.y - 0.3), 0.0, 0.08, 0.6, tile)
					deco.segment_box(c + Vector2(-hs.x - 0.3, hs.y + 0.3), c + Vector2(hs.x + 0.3, hs.y + 0.3), 0.0, 0.08, 0.6, tile)
					deco.segment_box(c + Vector2(-hs.x - 0.3, -hs.y - 0.3), c + Vector2(-hs.x - 0.3, hs.y + 0.3), 0.0, 0.08, 0.6, tile)
					deco.segment_box(c + Vector2(hs.x + 0.3, -hs.y - 0.3), c + Vector2(hs.x + 0.3, hs.y + 0.3), 0.0, 0.08, 0.6, tile)
					for lx in [-hs.x * 0.33, hs.x * 0.33]:
						var nb := 18
						for j in nb:
							var zz := -hs.y + 0.6 + float(j) * (hs.y * 2.0 - 1.2) / float(nb - 1)
							deco.blob(Vector3(c.x + lx, y + 0.05, c.y + zz), Vector3(0.14, 0.1, 0.14), Color(1.0, 0.3, 0.3) if j % 2 == 0 else Color(1, 1, 1), 2, 5, 0.25)
					deco.box(Vector3(c.x, 0.5, c.y - hs.y - 1.2), Vector3(0.6, 0.12, 2.6), Color(0.95, 0.95, 0.9))
					deco.box(Vector3(c.x, 0.25, c.y - hs.y - 2.2), Vector3(0.6, 0.5, 0.6), Color(0.5, 0.5, 0.55))
		mi.mesh = k.commit()
		mi.material_override = mat
		mi.position = Vector3(c.x, y, c.y)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		container.add_child(mi)
		# dark pit interior below the surface
		out[w["id"]] = {"node": mi, "mat": mat, "index": i}
	return out
