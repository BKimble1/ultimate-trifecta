class_name ClassicKit
extends RefCounted
## Campus art kit (V5; original, generated - no external assets).
##
##  Mesh kit      vegetation and rocks authored offline by the Blender
##                generator (tools/campus/build_kit.py) into one MeshLibrary,
##                game/assets/campus/campus_kit.res: eight tree species with
##                three LODs each, three shrubs, grass, flowers, reeds,
##                lilies and three rock shapes.  Nothing heavy is generated
##                at runtime; ClassicBuilder places them as chunked MultiMesh
##                instances.
##  Species       which tree each ClassicLayout tree is drawn as.  Collider
##                trees keep their place, radius and collider; only the look
##                is chosen here: groves of related species (a conifer stand,
##                a birch glade, mixed oaks) from a low-frequency field, linden
##                avenues along the loop road, autumn maples and blossom trees
##                as accents on the quad, the dorm lawns and Lily Basin.
##  Light field   a 2 m grid of soft ambient occlusion (trunks, buildings,
##                walls, hedges, shrubs, rocks), warm light (lamps, entrances,
##                lit windows), cool light (the pool's and fountain's glow),
##                a canopy field (forest floor under groves) and a path field
##                (worn grass beside the paths).  AO/warm/cool become a small
##                texture the world shaders sample per fragment (V4 baked
##                them into vertex colours on the CPU); canopy and wear tint
##                the ground's vertex colours.  No runtime lights are added;
##                the moon stays the one dynamic shadow-casting light.

const KIT_PATH := "res://assets/campus/campus_kit.res"
const REF_H := 8.0   # trees are authored 8 m tall and scaled per instance
const BROAD := ["oak", "linden", "maple", "birch", "blossom"]
const CONIFER := ["fir", "spruce", "pine"]

static var _kit: Dictionary = {}   # mesh name -> ArrayMesh
static var _lod: Dictionary = {}   # base name -> ArrayMesh with native LODs
static var _lod_scale := -1.0

## dressing kind -> kit mesh base name
const DECOR_MESH := {"grass": "grass_tuft", "flowers": "flowers", "lilies": "lilies", "rock_flat": "rock_flat", "rock_round": "rock_round",
	"rock_layer": "rock_layer", "shrub_round": "shrub_round", "shrub_tall": "shrub_tall", "shrub_bloom": "shrub_bloom", "reeds": "reeds"}
## LOD switch distances in metres (Standard, at any render height): one per
## authored LOD after the first; a distance beyond the authored LODs is an
## empty LOD (the batch draws nothing there, so tufts and flowers end).
const LOD_M := {"tree": [30.0, 90.0], "shrub": [24.0, 70.0], "rock": [30.0], "grass": [36.0], "flowers": [40.0], "reeds": [60.0], "lilies": [70.0]}
## Godot picks a mesh LOD by screen-space error: measured on the 4.7.2 Mobile
## renderer, a LOD key k switches at ~520 * k metres at a 720 px render
## height and proportionally further on taller renders, so keys are scaled
## by 720 / render height to keep the distances above on every device.
const KEY_PER_M := 1.0 / 520.0


## Loads the MeshLibrary once per session (~0.2 MB, a few ms).
static func load_kit(quality: int = 1) -> void:
	var h := 720.0
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null and tree.root.size.y > 0:
		h = float(tree.root.size.y) * tree.root.scaling_3d_scale
	# Battery Saver also raises the LOD threshold (3x): ease it to ~1.5x
	var sc := (720.0 / maxf(h, 1.0)) * (2.0 if quality < 1 else 1.0)
	if not is_equal_approx(sc, _lod_scale):
		_lod.clear()
		_lod_scale = sc
	if not _kit.is_empty():
		return
	var lib := load(KIT_PATH) as MeshLibrary
	if lib == null:
		push_error("campus kit missing: %s" % KIT_PATH)
		return
	for id in lib.get_item_list():
		_kit[lib.get_item_name(id)] = lib.get_item_mesh(id)


## The authored LODs of `base` (base_0, base_1, ...) in one ArrayMesh: the
## vertex arrays are concatenated and each lower LOD is an index range of
## its own, registered as a native mesh LOD.
static func lod_mesh(base: String) -> Mesh:
	if _lod.has(base):
		return _lod[base]
	if _kit.is_empty():
		load_kit()
	var parts: Array[ArrayMesh] = []
	for i in 3:
		var m: ArrayMesh = _kit.get("%s_%d" % [base, i])
		if m != null:
			parts.append(m)
	if parts.is_empty():
		push_error("campus kit: no mesh %s" % base)
		return null
	var dists: Array = LOD_M.get(base.get_slice("_", 0), [])
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var cu := PackedFloat32Array()
	var idx: Array[PackedInt32Array] = []
	for m in parts:
		var a := m.surface_get_arrays(0)
		var off := v.size()
		v.append_array(a[Mesh.ARRAY_VERTEX])
		n.append_array(a[Mesh.ARRAY_NORMAL])
		c.append_array(a[Mesh.ARRAY_COLOR])
		uv.append_array(a[Mesh.ARRAY_TEX_UV])
		cu.append_array(a[Mesh.ARRAY_CUSTOM0])
		var ii: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var shifted := PackedInt32Array()
		shifted.resize(ii.size())
		for j in ii.size():
			shifted[j] = ii[j] + off
		idx.append(shifted)
	var lods := {}
	var sc := maxf(_lod_scale, 0.01)
	for li in range(1, mini(parts.size(), dists.size() + 1)):
		lods[float(dists[li - 1]) * KEY_PER_M * sc] = idx[li]
	if dists.size() >= parts.size():
		# an empty last LOD: one degenerate triangle
		lods[float(dists[parts.size() - 1]) * KEY_PER_M * sc] = PackedInt32Array([0, 0, 0])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_CUSTOM0] = cu
	arr[Mesh.ARRAY_INDEX] = idx[0]
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], lods, Mesh.ARRAY_CUSTOM_RG_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	out.resource_name = base
	_lod[base] = out
	return out


static func kit_mesh(mesh_name: String) -> Mesh:
	if _kit.is_empty():
		load_kit()
	return _kit.get(mesh_name)


static func has_mesh(mesh_name: String) -> bool:
	if _kit.is_empty():
		load_kit()
	return _kit.has(mesh_name)


static func _hash01(x: float, z: float, salt: int = 0) -> float:
	var h := hash(Vector3i(int(floor(x * 10.0)), int(floor(z * 10.0)), salt))
	return float(posmod(h, 10007)) / 10007.0


## Grove field: one of four stands per ~26 m cell (smoothed by jitter so the
## boundaries are not a grid).
static func _grove(p: Vector2) -> int:
	var j := Vector2(sin(p.y * 0.11) * 6.0, cos(p.x * 0.09) * 6.0)
	var c := ((p + j) / 26.0).floor()
	return posmod(hash(Vector2i(int(c.x), int(c.y))), 4)


## The species a layout tree is drawn as (visual only).
static func species_of(t: Dictionary) -> String:
	var p: Vector2 = t["pos"]
	var pine := String(t["kind"]) == "pine"
	var r := _hash01(p.x, p.y, 7)
	# avenue trees along the College Loop and the quad's north row
	var avenue := (absf(absf(p.x) - 84.0) < 0.01 or absf(p.y + 63.5) < 0.01 or absf(p.y - 93.5) < 0.01)
	if avenue and not pine:
		return "linden"
	if absf(p.y + 8.0) < 0.01 and absf(p.x) <= 24.0:
		return "maple"
	# the pond woods: conifer stands, birch glades and mixed oak groves
	if p.x < -92.0 and p.y > -10.0 and p.y < 86.0:
		match _grove(p):
			0, 1:
				return "fir" if r < 0.8 else "oak"
			2:
				return "birch" if r < 0.6 else ("oak" if r < 0.85 else "fir")
			_:
				return "oak" if r < 0.65 else ("fir" if r < 0.85 else "birch")
	# north-west quarry woods: stout pines and spruce on the rocky ground
	if p.x < -100.0 and p.y < -100.0:
		return "pine" if r < 0.6 else "spruce"
	# Lily Basin / greenhouse side: blossom and linden
	if p.x > 60.0 and p.y < -60.0:
		if pine:
			return "spruce"
		return "blossom" if r < 0.45 else ("linden" if r < 0.75 else "birch")
	# dorm lawns: blossom, birch, the odd maple
	if p.y > 94.0 and absf(p.x) < 80.0:
		if pine:
			return "fir"
		return "blossom" if r < 0.4 else ("birch" if r < 0.7 else "maple")
	# the quad (between library and science): warm maples among oaks
	if absf(p.x) < 40.0 and p.y > -12.0 and p.y < 60.0:
		if pine:
			return "spruce"
		return "maple" if r < 0.45 else ("oak" if r < 0.8 else "blossom")
	if pine:
		return "fir" if r < 0.5 else ("spruce" if r < 0.8 else "pine")
	return "oak" if r < 0.45 else ("linden" if r < 0.7 else ("maple" if r < 0.85 else "birch"))


## Per-instance tint for a tree (crowns vary a little in value and warmth).
static func tint_of(t: Dictionary) -> Color:
	var p: Vector2 = t["pos"]
	var a := _hash01(p.x, p.y, 13)
	var b := _hash01(p.x, p.y, 17)
	var v := 0.9 + 0.2 * a
	return Color(v * (0.97 + 0.06 * b), v, v * (1.03 - 0.06 * b))


# ---------------------------------------------------------------------------
# Light field: soft AO + warm/cool light + canopy + path wear on a 2 m grid
# ---------------------------------------------------------------------------
const CELL := 2.0
var _w := 0
var _d := 0
var ao: PackedFloat32Array      # 0 = open sky .. 1 = deeply occluded
var warm: PackedFloat32Array    # 0 .. ~1 warm light
var cool: PackedFloat32Array    # 0 .. ~1 cool (pool / fountain) light
var canopy: PackedFloat32Array  # 0 .. 1 under tree crowns (forest floor)
var wear: PackedFloat32Array    # 0 .. 1 beside paths (worn grass)
var _layout: ClassicLayout


## The field is filled in stages (begin + stamp_* calls) so the staged build
## keeps each step short; `fill_all` does everything at once.
func _init(layout: ClassicLayout, fill: bool = true) -> void:
	_layout = layout
	var b := ClassicLayout.BOUNDS
	_w = int(b.size.x / CELL) + 1
	_d = int(b.size.y / CELL) + 1
	for g in ["ao", "warm", "cool", "canopy", "wear"]:
		var arr := PackedFloat32Array()
		arr.resize(_w * _d)
		arr.fill(0.0)
		set(g, arr)
	if fill:
		stamp_trees()
		stamp_buildings()
		stamp_barriers()
		stamp_lights()
		stamp_paths()


func stamp_trees() -> void:
	for t in _layout.trees:
		_stamp(ao, t["pos"], 3.6, 0.45, 1.6)
		_stamp(canopy, t["pos"], 5.0, 0.55, 0.8)


func stamp_buildings() -> void:
	for bd in _layout.buildings:
		var pos: Vector2 = bd["pos"]
		var size: Vector2 = bd["size"]
		if bd.has("dorm_id"):
			# V6 dorm: shade around the closed part only; the common room is
			# lit warm inside (and spills a little out of its doors)
			var g := ClassicDorms.geometry(String(bd["dorm_id"]))
			var room: Rect2 = g["room"]
			var fp: Rect2 = g["footprint"]
			_stamp_rect(ao, Rect2(fp.position.x, room.end.y, fp.size.x, fp.end.y - room.end.y), 3.2, 0.5)
			_stamp_rect(warm, room, 1.2, 0.95)
			continue
		_stamp_rect(ao, Rect2(pos - size * 0.5, size), 3.2, 0.5)
		# lit windows spill a little warmth onto the ground along the walls
		if not bd.get("dome", false) and String(bd["id"]) not in ["shed", "tower"]:
			_stamp_rect(warm, Rect2(pos - size * 0.5, size), 3.0, 0.16 * float(bd.get("warm", 0.5)) * 2.0)


func stamp_barriers() -> void:
	for s in _layout.walls + _layout.hedges:
		var a: Vector2 = s["a"]
		var bb: Vector2 = s["b"]
		var n := int(a.distance_to(bb) / CELL) + 1
		for i in n + 1:
			_stamp(ao, a.lerp(bb, float(i) / float(n)), 1.8, 0.22, 1.0)
	for r in _layout.rocks:
		var rp: Vector3 = r["pos"]
		_stamp(ao, Vector2(rp.x, rp.z), 3.4, 0.35, 1.2)


func stamp_lights() -> void:
	for lp in _layout.lamps:
		_stamp(warm, lp, 8.0, 0.75, 1.4)
	for dd in _layout.dorm_doors:
		var dp: Vector2 = dd["pos"]
		var dn: Vector2 = dd["normal"]
		_stamp(warm, dp + dn * 2.0, 6.0, 0.8, 1.2)
	for w in _layout.waters:
		var c: Vector2 = w["center"]
		match String(w["id"]):
			"pool":
				_stamp_rect(cool, Rect2(c - w["size"] * 0.5, w["size"]), 5.0, 0.55)
			"fountain":
				_stamp(cool, c, 11.0, 0.35, 1.0)
				_stamp(warm, c, 13.0, 0.25, 1.0)


func stamp_paths() -> void:
	for pth in _layout.paths:
		var pts: PackedVector2Array = pth["pts"]
		var hw: float = float(pth["w"]) * 0.5
		for i in pts.size() - 1:
			_stamp_segment(wear, pts[i], pts[i + 1], hw + 2.2, hw, 0.7)


## Extra soft contact shade under decorative things (shrubs, rocks).
func stamp_contact(p: Vector2, radius: float, amount: float) -> void:
	_stamp(ao, p, radius, amount, 1.3)


func _stamp(grid: PackedFloat32Array, c: Vector2, radius: float, amount: float, power: float) -> void:
	var b := ClassicLayout.BOUNDS
	var r := int(ceil(radius / CELL))
	var ci := int(round((c.x - b.position.x) / CELL))
	var cj := int(round((c.y - b.position.y) / CELL))
	for j in range(maxi(cj - r, 0), mini(cj + r + 1, _d)):
		for i in range(maxi(ci - r, 0), mini(ci + r + 1, _w)):
			var p := Vector2(b.position.x + i * CELL, b.position.y + j * CELL)
			var t := 1.0 - p.distance_to(c) / radius
			if t <= 0.0:
				continue
			var idx := j * _w + i
			grid[idx] = minf(1.0, grid[idx] + amount * pow(t, power))


## Distance-to-segment stamp: full `amount` inside `inner`, fading to 0 at `outer`.
func _stamp_segment(grid: PackedFloat32Array, a: Vector2, bb: Vector2, outer: float, inner: float, amount: float) -> void:
	var b := ClassicLayout.BOUNDS
	var lo := Vector2(minf(a.x, bb.x), minf(a.y, bb.y)) - Vector2(outer, outer)
	var hi := Vector2(maxf(a.x, bb.x), maxf(a.y, bb.y)) + Vector2(outer, outer)
	for j in range(maxi(0, int((lo.y - b.position.y) / CELL)), mini(_d, int((hi.y - b.position.y) / CELL) + 2)):
		for i in range(maxi(0, int((lo.x - b.position.x) / CELL)), mini(_w, int((hi.x - b.position.x) / CELL) + 2)):
			var p := Vector2(b.position.x + i * CELL, b.position.y + j * CELL)
			var d := ClassicLayout._dist_to_segment(p, a, bb)
			if d >= outer:
				continue
			var v := amount * (1.0 - smoothstep(inner, outer, d))
			var idx := j * _w + i
			grid[idx] = maxf(grid[idx], v)


func _stamp_rect(grid: PackedFloat32Array, rect: Rect2, falloff: float, amount: float) -> void:
	var b := ClassicLayout.BOUNDS
	var big := rect.grow(falloff)
	for j in range(maxi(0, int((big.position.y - b.position.y) / CELL)), mini(_d, int((big.end.y - b.position.y) / CELL) + 2)):
		for i in range(maxi(0, int((big.position.x - b.position.x) / CELL)), mini(_w, int((big.end.x - b.position.x) / CELL) + 2)):
			var p := Vector2(b.position.x + i * CELL, b.position.y + j * CELL)
			var dx := maxf(maxf(rect.position.x - p.x, p.x - rect.end.x), 0.0)
			var dz := maxf(maxf(rect.position.y - p.y, p.y - rect.end.y), 0.0)
			var dist := Vector2(dx, dz).length()
			if dist >= falloff:
				continue
			var idx := j * _w + i
			grid[idx] = minf(1.0, grid[idx] + amount * (1.0 - dist / falloff))


## Bilinear sample of a grid at world (x, z).
func sample(grid: PackedFloat32Array, x: float, z: float) -> float:
	var b := ClassicLayout.BOUNDS
	var fx := clampf((x - b.position.x) / CELL, 0.0, float(_w - 1) - 0.001)
	var fz := clampf((z - b.position.y) / CELL, 0.0, float(_d - 1) - 0.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := grid[j * _w + i]
	var bb := grid[j * _w + i + 1]
	var c := grid[(j + 1) * _w + i]
	var d := grid[(j + 1) * _w + i + 1]
	return lerpf(lerpf(a, bb, tx), lerpf(c, d, tx), tz)


## the light colours (sRGB); world_common's FIELD_WARM / FIELD_COOL match
const WARM := Color(0.42, 0.26, 0.09)
const COOL := Color(0.05, 0.20, 0.24)


## V5: the light field as a small texture (R ao, G warm, B cool; one texel
## per 2 m cell, ~100 KB) that the world shaders sample per fragment, so no
## vertex is baked on the CPU and the MultiMesh vegetation is lit by it too.
func field_texture() -> ImageTexture:
	var bytes := PackedByteArray()
	bytes.resize(_w * _d * 4)
	for i in _w * _d:
		bytes[i * 4] = clampi(int(ao[i] * 255.0 + 0.5), 0, 255)
		bytes[i * 4 + 1] = clampi(int(warm[i] * 255.0 + 0.5), 0, 255)
		bytes[i * 4 + 2] = clampi(int(cool[i] * 255.0 + 0.5), 0, 255)
		bytes[i * 4 + 3] = 255
	var img := Image.create_from_data(_w, _d, false, Image.FORMAT_RGBA8, bytes)
	return ImageTexture.create_from_image(img)


## Shader parameters that place the field texture in the world.
func field_params() -> Dictionary:
	var b := ClassicLayout.BOUNDS
	return {"field_origin": b.position - Vector2(CELL, CELL) * 0.5, "field_size": Vector2(_w, _d) * CELL}
