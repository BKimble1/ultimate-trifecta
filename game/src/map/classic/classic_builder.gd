class_name ClassicBuilder
extends RefCounted
## The look of Moonbrook College, the classic map, as the 2.0 build drew it
## (restored from that source): merged per-chunk meshes for ground, paths,
## buildings and props with the light field baked into vertex colours; the
## Blender kit (ClassicKit) as chunked MultiMeshes with authored LODs and
## tree shadow proxies; the six water landmarks (ClassicLandmarks), the
## buildings and props (ClassicArchitecture) and the three dorms
## (ClassicDormArt).  Built in short staged steps under the loading screen
## (begin_visuals / step), with the same interface MatchController drives
## for the reference campus's CampusBuilder.
##
## Visual only.  The classic map's collision, navigation, dorm thresholds and
## waters come from the shared gameplay pipeline (CampusLayout, CampusBuilder,
## NavGrid, CampusDorms) over game/data/maps/classic, which
## tools/classic_export.gd writes from this same ClassicLayout; the test
## proves the two agree.

const CHUNK := Vector2(64.0, 60.0)
const WORLD_SHADER := preload("res://assets/shaders/world_vc.gdshader")
const FOLIAGE_SHADER := preload("res://assets/shaders/world_foliage.gdshader")
const WATER_SHADER := preload("res://assets/shaders/water.gdshader")
const GLOW_SHADER := preload("res://assets/shaders/glow_add.gdshader")
const DETAIL_A := preload("res://assets/campus/campus_detail_a.png")
const DETAIL_B := preload("res://assets/campus/campus_detail_b.png")

var L: ClassicLayout
var _chunks: Dictionary = {}
var _foliage: Dictionary = {}   # (unused since V4 trees became MultiMeshes)
var _detail: Dictionary = {}    # small props per chunk, drawn only near the camera
const DETAIL_M := 100.0
## the shared canopy material (MatchController feeds it the followed character)
var foliage_material: ShaderMaterial
var _glow_st: SurfaceTool
var _glow_count := 0


func _init(layout: ClassicLayout) -> void:
	L = layout


# ---------------------------------------------------------------------------
# Height function (the visuals' ground: the same water pits as the gameplay grid)
# ---------------------------------------------------------------------------
static func ground_y(layout: ClassicLayout, x: float, z: float) -> float:
	var p := Vector2(x, z)
	for w in layout.waters:
		if ClassicLayout.in_water_shape(w, p):
			return float(w["floor_y"])
	return 0.0


static var _grid_cache: PackedFloat32Array
static var _grid_layout: ClassicLayout


## 1 m height grid over BOUNDS (row-major z, x), cached per layout.
static func height_grid(layout: ClassicLayout) -> PackedFloat32Array:
	if _grid_layout == layout and not _grid_cache.is_empty():
		return _grid_cache
	var b := ClassicLayout.BOUNDS
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
				if ClassicLayout.in_water_shape(wt, p):
					data[zi * w + xi] = float(wt["floor_y"])
	_grid_cache = data
	_grid_layout = layout
	return data


static func grid_y(layout: ClassicLayout, x: float, z: float) -> float:
	var b := ClassicLayout.BOUNDS
	var xi := clampi(int(round(x - b.position.x)), 0, int(b.size.x))
	var zi := clampi(int(round(z - b.position.y)), 0, int(b.size.y))
	return height_grid(layout)[zi * (int(b.size.x) + 1) + xi]


static func water_at(layout: ClassicLayout, p: Vector2) -> int:
	for i in layout.waters.size():
		if ClassicLayout.in_water_shape(layout.waters[i], p):
			return i
	return -1


# ---------------------------------------------------------------------------
# Visuals
# ---------------------------------------------------------------------------
## detail: small near-field props (lamps, bollards, benches, window frames)
## in their own per-chunk mesh that stops drawing beyond DETAIL_M.
func _kit_at(x: float, z: float, foliage: bool = false, detail: bool = false) -> MeshKit:
	var key := chunk_key(x, z)
	var store := _foliage if foliage else (_detail if detail else _chunks)
	if not store.has(key):
		store[key] = MeshKit.new()
	return store[key]


static func chunk_key(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor((x - ClassicLayout.BOUNDS.position.x) / CHUNK.x)), int(floor((z - ClassicLayout.BOUNDS.position.y) / CHUNK.y)))


static func chunk_center(key: Vector2i, scale: float = 1.0) -> Vector3:
	var b := ClassicLayout.BOUNDS.position
	return Vector3(b.x + (float(key.x) + 0.5) * CHUNK.x * scale, 0.0, b.y + (float(key.y) + 0.5) * CHUNK.y * scale)


## Coarser batches (2 x 2 chunks): dressing and tree shadow proxies; the
## forest beyond the boundary uses 3 x 3.
static func coarse_key(x: float, z: float, scale: float = 2.0) -> Vector2i:
	return Vector2i(int(floor((x - ClassicLayout.BOUNDS.position.x) / (CHUNK.x * scale))), int(floor((z - ClassicLayout.BOUNDS.position.y) / (CHUNK.y * scale))))


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
var _rng: RandomNumberGenerator
var _quality := 1
var _root: Node3D
var _commit_keys: Array = []
var _commit_started := false
var _world_mat: ShaderMaterial
var kit: ClassicKit
var arch: ClassicArchitecture
var marks: ClassicLandmarks
var dorm_art: ClassicDormArt
var dressing: Dictionary = {}
var _trees: Dictionary = {}       # chunk key -> {species: [[Transform3D, tint, custom], ...]}
var _decor: Dictionary = {}       # coarse key -> {kind: [[Transform3D, tint, custom], ...]}
var _far: Dictionary = {}         # 3x coarse key -> {species: [...]} (forest beyond the bounds)
var _proxy: Dictionary = {}       # coarse key -> {family: [...]} (tree shadow casters)
var _ground_end: Dictionary = {}  # chunk key -> vertex count after the ground
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
	_rng = RandomNumberGenerator.new()
	_rng.seed = 77
	_quality = quality
	_root = root
	_step_i = 0
	_steps.clear()
	step_names.clear()
	_trees.clear()
	_decor.clear()
	_far.clear()
	_proxy.clear()
	_ground_end.clear()
	_commit_keys.clear()
	_commit_started = false
	_mm_queue.clear()
	_mm_started = false
	arch = ClassicArchitecture.new(self)
	marks = ClassicLandmarks.new(self)
	dorm_art = ClassicDormArt.new(self, arch)
	_add("kit", func() -> void:
		ClassicKit.load_kit(quality)
		dressing = ClassicDressing.load_baked())
	_add("light_trees", func() -> void:
		kit = ClassicKit.new(L, false)
		kit.stamp_trees())
	_add("light_buildings", func() -> void:
		kit.stamp_buildings()
		kit.stamp_barriers())
	_add("light_lamps", func() -> void:
		kit.stamp_lights()
		kit.stamp_paths())
	_add("light_decor", _stamp_decor)
	for gz in range(int(ceil(ClassicLayout.BOUNDS.size.y / CHUNK.y))):
		for gx in range(int(ceil(ClassicLayout.BOUNDS.size.x / CHUNK.x))):
			_add("ground", func() -> void: _ground_chunk(Vector2i(gx, gz)))
	_add("plazas", _plazas)
	_add("roads", _roads)
	for i0 in range(0, L.paths.size(), 2):
		_add("paths", func() -> void:
			for i in range(i0, mini(i0 + 2, L.paths.size())):
				_path(L.paths[i]))
	for bd in L.buildings:
		_add("building_" + String(bd["id"]), func() -> void: arch.building(bd))
		if ClassicArchitecture.has_windows(bd):
			for face in 4:
				_add("windows_" + String(bd["id"]), func() -> void: arch.windows(bd, face))
		if bd.has("dorm_id"):
			# V6 dorms: one step per part (each a few ms)
			_add("dorm_windows", func() -> void: dorm_art.windows(bd))
			_add("dorm_entrances", func() -> void: dorm_art.entrances(bd))
			_add("dorm_interior", func() -> void: dorm_art.interior(bd))
	_add("walls", arch.walls)
	for hi in L.hedges.size():
		var hl: float = (L.hedges[hi]["a"] as Vector2).distance_to(L.hedges[hi]["b"])
		var parts := maxi(1, int(ceil(hl / 70.0)))
		for pi in parts:
			_add("hedges", func() -> void: arch.hedge_part(hi, float(pi) / float(parts), float(pi + 1) / float(parts)))
	for fi in L.fences.size():
		_add("fence", func() -> void: arch.fence(fi))
	for bi in range(0, L.cart_blockers.size(), 2):
		_add("bollards", func() -> void: arch.bollards(bi, bi + 2))
	_add("trees", func() -> void:
		_place_trees()
		_merge_species())
	_add("decor", _place_decor)
	for part in 3:
		_add("small", func() -> void: arch.small_things(part))
	for li in range(0, L.lamps.size(), 10):
		_add("lamps", func() -> void: arch.lamps(li, li + 10))
	_add("light_texture", func() -> void: _field_tex = kit.field_texture())
	_add("horizon", marks.horizon)
	_add("shader_world", func() -> void: _warm_material(WORLD_SHADER))
	_add("shader_foliage", func() -> void: _warm_material(FOLIAGE_SHADER))
	_add("shader_water", func() -> void: _warm_material(WATER_SHADER))
	_add("containers", _containers)
	for wi in L.waters.size():
		_add("water_" + String(L.waters[wi]["id"]), func() -> void: marks.water(wi))
		if String(L.waters[wi]["id"]) == "fountain":
			_add("fountain_jets", func() -> void: marks.fountain_jets(wi))
	# signs add board geometry to the chunks: before they are committed
	_add("signs", arch.signs)
	_add("dorm_signs", dorm_art.yard_signs)
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


## V6: the round was cancelled mid-build (Cancel on the loading screen).
## Returns the chunk jobs still on the worker pool; the caller hands them
## to App, which waits for each only once it has finished, so cancelling
## never blocks a frame.
func abort() -> Array[int]:
	var ids: Array[int] = []
	for item in _commit_keys:
		ids.append(int(item[2]))
	_commit_keys.clear()
	_step_i = step_names.size()
	_release()
	return ids


## V6: the build is over (finished or cancelled).  Its step closures refer
## back to the builder, as do the architecture/landmark helpers, so without
## this the builder and everything it gathered (mesh kits, the light-field
## kit, tree and decor tables) stayed alive after every cold campus build.
## Only what the round reads afterwards is kept: container, water_nodes,
## foliage_material and step_names.
func _release() -> void:
	_steps.clear()
	arch = null
	marks = null
	dorm_art = null
	kit = null
	_root = null
	_rng = null
	_glow_st = null
	_world_mat = null
	_field_tex = null
	dressing = {}
	for d: Dictionary in [_chunks, _foliage, _detail, _trees, _decor, _far, _proxy, _ground_end]:
		d.clear()
	_mm_queue.clear()
	_commit_keys.clear()


## The name of the step step() will run next (diagnostics).
func next_step_name() -> String:
	return step_names[_step_i] if _step_i < step_names.size() else ""


## Fraction of the steps done (loading screen progress, never invented).
func progress() -> float:
	return float(_step_i) / float(maxi(step_names.size(), 1))


func _stamp_decor() -> void:
	for kind in dressing:
		if not (kind in ClassicDressing.MID):
			continue
		var a: PackedFloat32Array = dressing[kind]
		var r0: float = ClassicDressing.RADIUS[kind]
		for i in range(0, a.size(), ClassicDressing.STRIDE):
			kit.stamp_contact(Vector2(a[i], a[i + 2]), r0 * a[i + 4] * 1.8, 0.22)


func _mm_add(store: Dictionary, key: Vector2i, kind: String, xf: Transform3D, tint: Color, custom: Color) -> void:
	if not store.has(key):
		store[key] = {}
	var per: Dictionary = store[key]
	if not per.has(kind):
		per[kind] = []
	(per[kind] as Array).append([xf, tint, custom])


## One MultiMesh instance per tree, by species (visual only - the collider
## and nav cell come from ClassicLayout and are unchanged): uniform scale to
## its height, a turn, and a gentle tint.
func _place_trees() -> void:
	for t in L.trees:
		var p: Vector2 = t["pos"]
		var sp := ClassicKit.species_of(t)
		var s: float = float(t["h"]) / ClassicKit.REF_H
		var yaw := fposmod(p.x * 1.7 + p.y * 2.3, TAU)
		var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), Vector3(p.x, ground_y(L, p.x, p.y), p.y))
		_mm_add(_trees, chunk_key(p.x, p.y), sp, xf, ClassicKit.tint_of(t), Color(1, 1, 1))
		_mm_add(_proxy, coarse_key(p.x, p.y), "fir" if sp in ClassicKit.CONIFER else "oak", xf, Color(1, 1, 1), Color(1, 1, 1))


## Keeps tree batches few: a chunk with more than two species draws its
## rarest ones as the commonest species of the same family (broadleaf or
## conifer).  Visual only.
func _merge_species() -> void:
	for key in _trees:
		var per: Dictionary = _trees[key]
		while per.size() > 2:
			var names: Array = per.keys()
			names.sort_custom(func(a: String, b: String) -> bool: return (per[a] as Array).size() < (per[b] as Array).size())
			var rare: String = names[0]
			var fam := rare in ClassicKit.CONIFER
			var into := ""
			for nm in names.slice(1):
				if (String(nm) in ClassicKit.CONIFER) == fam:
					into = nm
			if into == "":
				into = names[names.size() - 1]
			(per[into] as Array).append_array(per[rare])
			per.erase(rare)


## The baked dressing list into chunked MultiMesh batches.
func _place_decor() -> void:
	var species := ClassicDressing.species_list()
	for kind in dressing:
		var a: PackedFloat32Array = dressing[kind]
		for i in range(0, a.size(), ClassicDressing.STRIDE):
			var p := Vector3(a[i], a[i + 1], a[i + 2])
			var s: float = a[i + 4]
			var sc := Vector3(s, s, s)
			var tint := Color(a[i + 5], a[i + 6], a[i + 7])
			var custom := Color(a[i + 8], a[i + 9], a[i + 10])
			var batch: String = kind
			if kind.begins_with("shrub"):
				# one shrub batch: the blooming shrub's flower heads take the
				# leaf colour on plain shrubs; tall ones are stretched
				batch = "shrub_bloom"
				if kind != "shrub_bloom":
					custom = Color(0.22, 0.42, 0.24) * tint.v
				if kind == "shrub_tall":
					sc = Vector3(s * 0.85, s * 1.55, s * 0.85)
			elif kind == "rock_flat":
				batch = "rock_round"
				sc = Vector3(s * 1.1, s * 0.4, s * 1.0)
			var xf := Transform3D(Basis(Vector3.UP, a[i + 3]).scaled(sc), p)
			if kind == ClassicDressing.FOREST:
				_mm_add(_far, coarse_key(p.x, p.z, 3.0), String(species[int(custom.r)]), xf, tint, Color(1, 1, 1))
			else:
				_mm_add(_decor, coarse_key(p.x, p.z), batch, xf, tint, custom)


## A material's shader is compiled on first use: one step per shader, so
## no other work shares those frames.  (Compiling on the worker pool
## deadlocked the renderer here; it stays on the main thread.)
func _warm_material(sh: Shader) -> void:
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("active" if sh == WATER_SHADER else "emission_boost", 1.0 if sh == WATER_SHADER else 1.6)
	sh.get_shader_uniform_list()


func _containers() -> void:
	_world_mat = ShaderMaterial.new()
	_world_mat.shader = WORLD_SHADER
	var fmat := ShaderMaterial.new()
	fmat.shader = FOLIAGE_SHADER
	var field_tex := _field_tex
	var field := kit.field_params()
	for m: ShaderMaterial in [_world_mat, fmat]:
		m.set_shader_parameter("detail_a", DETAIL_A)
		m.set_shader_parameter("detail_b", DETAIL_B)
		m.set_shader_parameter("detail_level", 1.0 if _quality >= 1 else 0.55)
		m.set_shader_parameter("light_field", field_tex)
		m.set_shader_parameter("field_on", 1.0)
		for pk in field:
			m.set_shader_parameter(pk, field[pk])
	foliage_material = fmat
	container = Node3D.new()
	container.name = "CampusVisuals"
	_root.add_child(container)


## Chunk meshes: every chunk's ArrayMesh is packed on the worker thread
## pool (the heaviest native work of the build), then each step adds the
## finished ones to the scene.  (V4 baked the light field into the vertex
## colours here; V5 samples it on the GPU, see ClassicKit.field_texture.)
func _commit_next() -> bool:
	if not _commit_started:
		_commit_started = true
		for pass_i in 3:
			var store: Dictionary = [_chunks, _foliage, _detail][pass_i]
			for key in store:
				var mk: MeshKit = store[key]
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
		# buildings and walls cast; the near-field detail (lamps, bollards,
		# frames) does not (V5: fewer shadow draws, softer ground)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (_quality >= 1 and pass_i == 0) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if pass_i == 2:
			# measured to the chunk's centre: covers the camera's surroundings
			mi.visibility_range_end = DETAIL_M if _quality >= 1 else DETAIL_M * 0.7
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		container.add_child(mi)
	return not _commit_keys.is_empty()


## Trees (by species) and dressing (by kind) for one chunk per call.  Each
## batch is one MultiMesh with the kit's authored LODs in Godot's mesh LOD
## (chosen per batch from its nearest point), so a chunk the camera stands
## in is drawn at full detail and far chunks at the light LODs.  Trees cast
## through a separate low-poly shadow proxy (Standard only).
const TREE_END_M := 240.0
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
			var mmi := _mmi(ClassicKit.lod_mesh("tree_" + kind), list, center, foliage_material, false)
			mmi.name = ("Trees_%s_%d_%d" if store == _trees else "Forest_%s_%d_%d") % [kind, key.x, key.y]
			mmi.visibility_range_end = TREE_END_M if _quality >= 1 else 160.0
			if store == _far:
				mmi.visibility_range_end += 80.0
			container.add_child(mmi)
		elif store == _proxy:
			if _quality < 1:
				continue
			# trees cast through low-poly proxies, one batch per family
			var sh := _mmi(ClassicKit.kit_mesh("tree_%s_2" % kind), list, center, _world_mat, false)
			sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			sh.name = "TreeShadows_%s_%d_%d" % [kind, key.x, key.y]
			sh.visibility_range_end = 150.0
			container.add_child(sh)
		else:
			var rock := kind.begins_with("rock")
			var mmi2 := _mmi(ClassicKit.lod_mesh(ClassicKit.DECOR_MESH[kind]), list, center, _world_mat if rock else foliage_material, kind == "flowers" or kind == "lilies" or kind == "shrub_bloom")
			mmi2.name = "Decor_%s_%d_%d" % [kind, key.x, key.y]
			# measured to the batch centre (128 x 120 m batches): near-only
			# pieces stop issuing draws once their batch is far away
			var vis := {"grass": 105.0, "flowers": 110.0, "shrub_bloom": 130.0, "reeds": 120.0, "lilies": 120.0}
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
	container.add_child(gmi)


# ---------------------------------------------------------------------------
# Ground
# ---------------------------------------------------------------------------
const GROUND_STEP := 2.0
var _noise: FastNoiseLite
var _noise2: FastNoiseLite


func ground_rows() -> int:
	return int(ClassicLayout.BOUNDS.size.y / GROUND_STEP)


## One chunk's ground: its share of the 2 m grid as an indexed mesh section
## (each vertex shared by up to six triangles), coloured on the CPU (lawn
## noise, forest floor, worn grass, banks) and lit on the GPU.
func _ground_chunk(key: Vector2i) -> void:
	var b := ClassicLayout.BOUNDS
	var nx := int(b.size.x / GROUND_STEP)
	var nz := ground_rows()
	var per_x := int(CHUNK.x / GROUND_STEP)
	var per_z := int(CHUNK.y / GROUND_STEP)
	var x0 := key.x * per_x
	var z0 := key.y * per_z
	var x1 := mini(x0 + per_x, nx)
	var z1 := mini(z0 + per_z, nz)
	if x0 >= x1 or z0 >= z1:
		return
	_ensure_noise()
	var k := _kit_at(b.position.x + x0 * GROUND_STEP + 1.0, b.position.y + z0 * GROUND_STEP + 1.0)
	var w := x1 - x0 + 1
	var ids := PackedInt32Array()
	ids.resize(w * (z1 - z0 + 1))
	for zi in range(z0, z1 + 1):
		var row := _ground_row_part(zi, x0, x1)
		for j in row.size():
			var e: Array = row[j]
			ids[(zi - z0) * w + j] = k.grid_vertex(e[0], e[1], e[2], Vector2(e[3], 1.0 if _mown(e[0]) else 0.0))
	for zi in range(z1 - z0):
		for xi in range(w - 1):
			var a := ids[zi * w + xi]
			var bb := ids[zi * w + xi + 1]
			var c := ids[(zi + 1) * w + xi + 1]
			var d := ids[(zi + 1) * w + xi]
			k.grid_tri(a, bb, c)
			k.grid_tri(a, c, d)


## The formal lawns get mowing stripes: the quad and the dorm grounds.
static func _mown(p: Vector3) -> bool:
	return (absf(p.x) < 74.0 and p.z > -12.0 and p.z < 84.0) or (absf(p.x) < 74.0 and p.z > 92.0 and p.z < 136.0)


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


## Unlit lawn colour at (x, z): two noise scales, forest floor under the
## groves (moss and needles), worn grass beside paths, sandy banks.
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


## Part of one row of ground vertices (columns x0..x1):
## [position, smooth normal, colour, material id].
func _ground_row_part(zi: int, x0: int, x1: int) -> Array:
	var b := ClassicLayout.BOUNDS
	var out: Array = []
	var z := b.position.y + zi * GROUND_STEP
	var near_water := []
	for w in L.waters:
		var c: Vector2 = w["center"]
		if absf(z - c.y) < 24.0:
			near_water.append(w)
	for xi in range(x0, x1 + 1):
		var x := b.position.x + xi * GROUND_STEP
		var y := grid_y(L, x, z)
		var hl := grid_y(L, x - GROUND_STEP, z)
		var hr := grid_y(L, x + GROUND_STEP, z)
		var hd := grid_y(L, x, z - GROUND_STEP)
		var hu := grid_y(L, x, z + GROUND_STEP)
		var n := Vector3((hl - hr) / (2.0 * GROUND_STEP), 1.0, (hd - hu) / (2.0 * GROUND_STEP)).normalized()
		var p := Vector3(x, y, z)
		var col := lawn_color(x, z)
		var mat := MeshKit.M_LAWN
		var low := minf(minf(y, hl), minf(minf(hr, hd), hu))
		if low < -0.1:
			col = col.lerp(MUD, 1.0 if y < -0.1 else 0.7)
			mat = MeshKit.M_GRAVEL
		else:
			# a sandy, pebbly band around the natural waters
			for w in near_water:
				if String(w["id"]) in ["pond", "quarry", "inlet"] and ClassicLayout.in_water_shape(w, Vector2(x, z), 2.2):
					col = col.lerp(SAND if String(w["id"]) != "pond" else SAND.lerp(MUD, 0.4), 0.65)
					mat = MeshKit.M_GRAVEL
		out.append([p, n, col, mat])
	return out


## The lawn colour packed for a verge (sRGB bytes r*65536 + g*256 + b);
## the shader lights it with the light field like the ground around it.
func _lawn_packed(x: float, z: float) -> float:
	var col := lawn_color(x, z)
	var r := clampi(int(round(col.r * 255.0)), 0, 255)
	var g := clampi(int(round(col.g * 255.0)), 0, 255)
	var bl := clampi(int(round(col.b * 255.0)), 0, 255)
	return float(r * 65536 + g * 256 + bl)


# ---------------------------------------------------------------------------
# Plazas, roads and paths
# ---------------------------------------------------------------------------
const PATH_Y := 0.075
const VERGE_Y := 0.062
const VERGE_W := 0.32


static func _path_mat(col: Color) -> float:
	if col.is_equal_approx(Color(0.62, 0.56, 0.46)):
		return MeshKit.M_GRAVEL
	if col.is_equal_approx(Color(0.55, 0.40, 0.28)):
		return MeshKit.M_WOOD
	return MeshKit.M_PAVING


## A path: paving (or gravel / boards) with a ragged lawn verge on both
## sides, in ~2 m pieces so the baked light and the lawn colour follow it.
func _path(pth: Dictionary) -> void:
	var pts: PackedVector2Array = pth["pts"]
	var pc: Color = pth["color"]
	var hw: float = float(pth["w"]) * 0.5
	var mat := _path_mat(pc)
	var vmat := 19.0 if mat == MeshKit.M_GRAVEL else MeshKit.M_VERGE
	var hin := hw - VERGE_W
	var hout := hw + VERGE_W
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		var d := (b - a) / seg
		var nrm := Vector2(-d.y, d.x)
		var pieces := maxi(1, int(ceil(seg / 2.0)))
		for s in pieces:
			var p0 := a + d * (seg * float(s) / float(pieces))
			var p1 := a + d * (seg * float(s + 1) / float(pieces))
			var mid := (p0 + p1) * 0.5
			var k := _kit_at(mid.x, mid.y)
			k.mat = mat
			k.quad(_v3(p0 - nrm * hin, PATH_Y), _v3(p1 - nrm * hin, PATH_Y), _v3(p1 + nrm * hin, PATH_Y), _v3(p0 + nrm * hin, PATH_Y), pc)
			k.mat = 0.0
			for sg: float in [-1.0, 1.0]:
				var outer := mid + nrm * sg * (hw + 0.25)
				if _paved(outer):
					# another path, a plaza or a road continues here: pave on
					k.mat = mat
					_quad_up(k, _v3(p0 + nrm * sg * hin, PATH_Y - 0.004), _v3(p1 + nrm * sg * hin, PATH_Y - 0.004), _v3(p1 + nrm * sg * hw, PATH_Y - 0.004), _v3(p0 + nrm * sg * hw, PATH_Y - 0.004), pc)
					k.mat = 0.0
					continue
				var lp := _lawn_packed(mid.x + nrm.x * sg * (hw + 0.6), mid.y + nrm.y * sg * (hw + 0.6))
				_verge_quad(k, p0 + nrm * sg * hin, p1 + nrm * sg * hin, p1 + nrm * sg * hout, p0 + nrm * sg * hout, pc, lp, vmat, sg < 0.0)
	for i in pts.size():
		var c := pts[i]
		var k2 := _kit_at(c.x, c.y)
		k2.mat = mat
		k2.disc(Vector3(c.x, PATH_Y + 0.0015, c.y), hin, pc, 16)
		k2.mat = 0.0
		var on_plaza := false
		for pl in L.plazas:
			if pl["shape"] == "circle":
				on_plaza = on_plaza or c.distance_to(pl["center"]) < float(pl["radius"]) + hw
			else:
				var phs: Vector2 = pl["size"] * 0.5 + Vector2(hw, hw)
				var pcn: Vector2 = pl["center"]
				on_plaza = on_plaza or (absf(c.x - pcn.x) < phs.x and absf(c.y - pcn.y) < phs.y)
		if not on_plaza and not L.is_on_road(c, hw):
			_verge_ring(k2, c, hin, hout, pc, _lawn_packed(c.x + hw, c.y), vmat, VERGE_Y - 0.004, 16)


## True where the ground is already paved (a plaza or road; a path other
## than the one being built is caught by is_on_path at the outer edge).
func _paved(p: Vector2) -> bool:
	if L.is_on_road(p, 0.2) or L.is_on_path(p, 0.0):
		return true
	for pl in L.plazas:
		if pl["shape"] == "circle":
			if p.distance_to(pl["center"]) < float(pl["radius"]):
				return true
		else:
			var hs: Vector2 = pl["size"] * 0.5
			var c: Vector2 = pl["center"]
			if absf(p.x - c.x) < hs.x and absf(p.y - c.y) < hs.y:
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


## A verge quad: inner edge (path side, alpha 0) a0-b0, outer edge a1-b1.
func _verge_quad(k: MeshKit, a0: Vector2, b0: Vector2, b1: Vector2, a1: Vector2, pc: Color, packed: float, vmat: float, flip: bool) -> void:
	var ci := Color(pc.r, pc.g, pc.b, 0.0)
	var co := Color(pc.r, pc.g, pc.b, 1.0)
	var uv := Vector2(vmat, packed)
	var A := _v3(a0, VERGE_Y)
	var B := _v3(b0, VERGE_Y)
	var C := _v3(b1, VERGE_Y)
	var D := _v3(a1, VERGE_Y)
	var up := Vector3.UP
	# clockwise seen from above
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


func _plazas() -> void:
	for pl in L.plazas:
		var c: Vector2 = pl["center"]
		var k := _kit_at(c.x, c.y)
		var pc: Color = pl["color"]
		if pl["shape"] == "circle":
			var r: float = pl["radius"]
			# a paved rosette: rings of slightly different stone
			k.mat = MeshKit.M_PAVING
			var rings := [0.0, r * 0.45, r * 0.52, r * 0.82, r * 0.88, r - VERGE_W]
			for ri in rings.size() - 1:
				var tone := pc.darkened(0.06) if ri % 2 == 1 else pc.lightened(0.02 * float(ri))
				_annulus(k, c, rings[ri], rings[ri + 1], 0.03, tone, 48)
			k.mat = 0.0
			_verge_ring(k, c, r - VERGE_W, r + VERGE_W, pc, _lawn_packed(c.x + r + 1.0, c.y), MeshKit.M_VERGE, 0.028, 48)
			continue
		var hs: Vector2 = pl["size"] * 0.5
		var tile_mat := MeshKit.M_PAVING
		if pc.is_equal_approx(Color(0.80, 0.82, 0.86)):
			tile_mat = MeshKit.M_TILE
		elif pc.is_equal_approx(Color(0.58, 0.62, 0.52)):
			tile_mat = MeshKit.M_GRAVEL
		elif pc.is_equal_approx(Color(0.40, 0.40, 0.42)):
			tile_mat = MeshKit.M_ASPHALT
		elif pc.is_equal_approx(Color(0.55, 0.40, 0.28)):
			tile_mat = MeshKit.M_WOOD
		var overlaps_water := false
		for w in L.waters:
			if float(w["surface_y"]) < 0.0 and Rect2(c - hs, hs * 2.0).grow(1.0).has_point(w["center"]):
				overlaps_water = true
		# 2 m tiles (1 m beside water so the opening follows the shore)
		var step := 1.0 if overlaps_water else 2.0
		var x0 := c.x - hs.x
		var z0 := c.y - hs.y
		var nx := int(ceil(hs.x * 2.0 / step))
		var nz := int(ceil(hs.y * 2.0 / step))
		k.mat = tile_mat
		for iz in nz:
			for ix in nx:
				var xa := x0 + ix * step
				var za := z0 + iz * step
				var xb := minf(xa + step, c.x + hs.x)
				var zb := minf(za + step, c.y + hs.y)
				if overlaps_water:
					var tc := Vector2((xa + xb) * 0.5, (za + zb) * 0.5)
					var wet := false
					for w2 in L.waters:
						if ClassicLayout.in_water_shape(w2, tc, 0.3):
							wet = true
							break
					if wet:
						continue
				var kk := _kit_at((xa + xb) * 0.5, (za + zb) * 0.5)
				kk.mat = tile_mat
				kk.quad(Vector3(xa, 0.03, za), Vector3(xb, 0.03, za), Vector3(xb, 0.03, zb), Vector3(xa, 0.03, zb), pc)
				kk.mat = 0.0
		k.mat = 0.0
		# a lawn verge around the plaza
		var corners := [Vector2(-hs.x, -hs.y), Vector2(hs.x, -hs.y), Vector2(hs.x, hs.y), Vector2(-hs.x, hs.y)]
		var vm := 19.0 if tile_mat == MeshKit.M_GRAVEL else MeshKit.M_VERGE
		if tile_mat in [MeshKit.M_PAVING, MeshKit.M_GRAVEL]:
			for ci in 4:
				var a: Vector2 = c + corners[ci]
				var b: Vector2 = c + corners[(ci + 1) % 4]
				var dd := (b - a).normalized()
				var out := Vector2(dd.y, -dd.x)
				var length := a.distance_to(b)
				var pieces := maxi(1, int(ceil(length / 2.0)))
				for s in pieces:
					var p0 := a + dd * (length * float(s) / float(pieces))
					var p1 := a + dd * (length * float(s + 1) / float(pieces))
					var m := (p0 + p1) * 0.5 + out
					_verge_quad(_kit_at(m.x, m.y), p0 - out * VERGE_W, p1 - out * VERGE_W, p1 + out * VERGE_W, p0 + out * VERGE_W, pc, _lawn_packed(m.x, m.y), vm, false)


func _annulus(k: MeshKit, c: Vector2, r0: float, r1: float, y: float, col: Color, seg: int) -> void:
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		var o0 := Vector3(c.x + cos(a0) * r1, y, c.y + sin(a0) * r1)
		var o1 := Vector3(c.x + cos(a1) * r1, y, c.y + sin(a1) * r1)
		if r0 <= 0.001:
			k.tri(Vector3(c.x, y, c.y), o0, o1, col, 0.0, 0.0, Vector3.UP)
			continue
		var i0 := Vector3(c.x + cos(a0) * r0, y, c.y + sin(a0) * r0)
		var i1 := Vector3(c.x + cos(a1) * r0, y, c.y + sin(a1) * r0)
		k.tri(i0, o0, o1, col, 0.0, 0.0, Vector3.UP)
		k.tri(i0, o1, i1, col, 0.0, 0.0, Vector3.UP)


## Roads: asphalt in 4 m pieces, a raised kerb on each side, glowing dashes.
func _roads() -> void:
	var asphalt := Color(0.17, 0.18, 0.22)
	var kerb := Color(0.50, 0.50, 0.54)
	for r in L.roads:
		var pts: PackedVector2Array = r["pts"]
		var hw: float = float(r["w"]) * 0.5
		for i in pts.size() - 1:
			var a := pts[i]
			var bb := pts[i + 1]
			var seg := a.distance_to(bb)
			var dir := (bb - a) / seg
			var nrm := Vector2(-dir.y, dir.x)
			var pieces := maxi(1, int(ceil(seg / 4.0)))
			for s in pieces:
				var p0 := a + dir * (seg * float(s) / float(pieces))
				var p1 := a + dir * (seg * float(s + 1) / float(pieces))
				var mid := (p0 + p1) * 0.5
				var k := _kit_at(mid.x, mid.y)
				k.mat = MeshKit.M_ASPHALT
				k.quad(_v3(p0 - nrm * hw, 0.05), _v3(p1 - nrm * hw, 0.05), _v3(p1 + nrm * hw, 0.05), _v3(p0 + nrm * hw, 0.05), asphalt)
				k.mat = MeshKit.M_STONE
				for sg: float in [-1.0, 1.0]:
					var e0 := p0 + nrm * sg * hw
					var e1 := p1 + nrm * sg * hw
					var o0 := p0 + nrm * sg * (hw + 0.35)
					var o1 := p1 + nrm * sg * (hw + 0.35)
					if sg > 0.0:
						k.quad(_v3(e0, 0.12), _v3(e1, 0.12), _v3(o1, 0.12), _v3(o0, 0.12), kerb)
						k.quad(_v3(e1, 0.12), _v3(e0, 0.12), _v3(e0, 0.05), _v3(e1, 0.05), kerb.darkened(0.25))
					else:
						k.quad(_v3(o0, 0.12), _v3(o1, 0.12), _v3(e1, 0.12), _v3(e0, 0.12), kerb)
						k.quad(_v3(e0, 0.12), _v3(e1, 0.12), _v3(e1, 0.05), _v3(e0, 0.05), kerb.darkened(0.25))
				k.mat = 0.0
			# centre-line dashes (slightly emissive so roads read at night)
			var sd := 2.0
			while sd < seg - 2.0:
				var q0 := a + dir * sd
				var q1 := a + dir * (sd + 1.6)
				_kit_at(q0.x, q0.y).ribbon(PackedVector2Array([q0, q1]), 0.22, 0.06, Color(0.95, 0.82, 0.35), 0.35, false)
				sd += 4.0
		for i in range(1, pts.size() - 1):
			var k3 := _kit_at(pts[i].x, pts[i].y)
			k3.mat = MeshKit.M_ASPHALT
			k3.disc(Vector3(pts[i].x, 0.052, pts[i].y), hw, asphalt, 16)
			k3.mat = 0.0


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
