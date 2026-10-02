class_name CampusKit
extends RefCounted
## V4 campus art kit (original, procedural; regenerated from this code - no
## external assets).  Two parts:
##
##  Tree variants   smooth, softly self-shaded meshes built once per session:
##                  three rounded broadleaf crowns (overlapping ellipsoid
##                  lobes) and two layered pines (revolved tiers with a
##                  drooping lip and a shaded underside), each with a rounded
##                  trunk whose root flare matches the collider radius.
##                  CampusBuilder draws them per 64x60 m chunk as MultiMesh
##                  instances (one transform + tint per tree), so chunks cull
##                  independently and the whole forest is a few draw calls.
##  Light field     a 2 m grid of soft ambient occlusion (around trunks,
##                  buildings, walls and hedges) and warm light (lamps, lit
##                  entrances, lit windows) that CampusBuilder bakes into the
##                  ground, paths and low geometry's vertex colours.  No
##                  runtime lights are added; the moon stays the one dynamic
##                  shadow-casting light.
##
## Tree meshes are authored at REF_H metres tall and scaled per instance.

const REF_H := 8.0
const BROAD_VARIANTS := 2
const PINE_VARIANTS := 2

static var _trees: Dictionary = {}   # "broad0" / "pine1" -> {"trunk": ArrayMesh, "crown": ArrayMesh}


## lod 0: near (smooth, the follow camera's surroundings); lod 1: far
## (same silhouette with a fraction of the triangles).
static func tree(kind: String, variant: int, lod: int = 0) -> Dictionary:
	var key := "%s%d_%d" % [kind, variant, lod]
	if not _trees.has(key):
		_trees[key] = _build_pine(variant, lod) if kind == "pine" else _build_broad(variant, lod)
	return _trees[key]


static func variant_of(t: Dictionary) -> int:
	var p: Vector2 = t["pos"]
	var n := PINE_VARIANTS if String(t["kind"]) == "pine" else BROAD_VARIANTS
	return posmod(int(floor(p.x * 3.7 + p.y * 1.3)), n)


static func _trunk(k: MeshKit, top: float, seg: int = 10) -> void:
	var prof := PackedVector2Array([Vector2(0.44, 0.0), Vector2(0.33, 0.18), Vector2(0.26, 0.7), Vector2(0.22, top * 0.6), Vector2(0.17, top)])
	var bark := Color(0.36, 0.26, 0.20)
	var cols := PackedColorArray([bark.darkened(0.45), bark.darkened(0.25), bark, bark.lightened(0.04), bark.lightened(0.06)])
	k.revolve(Vector3.ZERO, prof, cols, seg)


static func _build_broad(v: int, lod: int = 0) -> Dictionary:
	var trunk := MeshKit.new()
	_trunk(trunk, REF_H * 0.62, 7 if lod == 0 else 5)
	var crown := MeshKit.new()
	var g := Color(0.29, 0.52, 0.29)
	# lobes: centre, radii, lightness (lower = darker), seed
	var lobes: Array = [
		[Vector3(0, 5.0, 0), Vector3(2.4, 1.85, 2.4), 0.84],
	]
	match v:
		0:
			lobes += [[Vector3(1.05, 6.0, -0.45), Vector3(1.6, 1.4, 1.55), 1.0], [Vector3(-0.95, 5.75, 0.65), Vector3(1.5, 1.3, 1.5), 0.95], [Vector3(0.15, 6.75, 0.25), Vector3(1.3, 1.1, 1.3), 1.08]]
		_:
			lobes += [[Vector3(-1.1, 5.9, -0.6), Vector3(1.65, 1.45, 1.6), 1.0], [Vector3(1.0, 5.6, 0.8), Vector3(1.55, 1.35, 1.45), 0.94], [Vector3(-0.2, 6.85, 0.1), Vector3(1.25, 1.05, 1.25), 1.08]]
	for i in lobes.size():
		var lb: Array = lobes[i]
		var light: float = lb[2]
		var col_fn := func(n: Vector3) -> Color:
			# soft self-shading: lit tops, darker undersides, no texture
			var sh := 0.58 + 0.42 * smoothstep(-0.7, 0.85, n.y)
			var c := g * (sh * light)
			c += Color(0.07, 0.09, 0.05) * pow(maxf(n.y, 0.0), 2.0)
			return Color(c.r, c.g, c.b, 1.0)
		crown.lobe(lb[0], lb[1], col_fn, 5 if lod == 0 else 3, 8 if lod == 0 else 5, 0.55 + 0.1 * float(i), 0.07, 31 * v + i)
	return {"trunk": trunk.commit(), "crown": crown.commit()}


static func _build_pine(v: int, lod: int = 0) -> Dictionary:
	var trunk := MeshKit.new()
	_trunk(trunk, REF_H * 0.5, 7 if lod == 0 else 5)
	var crown := MeshKit.new()
	# a touch warmer and lighter than the faceted V3 pines: smooth shading
	# under the side moonlight otherwise reads darker and bluer
	var g := Color(0.27, 0.54, 0.31) if v == 0 else Color(0.3, 0.56, 0.31)
	var tiers := 3
	for i in tiers:
		var f := float(i) / float(tiers)
		var slim := 0.88 if v == 1 else 1.0
		var y0 := REF_H * (0.28 + 0.6 * f)
		var r := 2.55 * (1.0 - 0.62 * f) * slim
		var th := REF_H * (0.36 if v == 0 else 0.4)
		# a soft tier: shaded underside, drooping rim, rounded shoulder, tip
		# the underside closes onto the trunk (no hollow seen from below)
		var lt := 0.86 + 0.14 * f
		var sw := 0.45 + 0.35 * f
		var prof: PackedVector2Array
		var cols: PackedColorArray
		var sway: PackedFloat32Array
		if lod == 0:
			prof = PackedVector2Array([Vector2(0.12, y0 + 0.05), Vector2(r * 0.88, y0 - 0.22), Vector2(r * 1.0, y0 - 0.08),
				Vector2(r * 0.9, y0 + 0.14), Vector2(r * 0.5, y0 + th * 0.5), Vector2(0.03, y0 + th)])
			cols = PackedColorArray([g * 0.6, g * 0.72, g * (0.9 * lt), g * lt, g * (lt * 1.1), g * (lt * 1.2)])
			sway = PackedFloat32Array([sw * 0.3, sw, sw, sw, sw * 0.85, sw * 0.7])
		else:
			prof = PackedVector2Array([Vector2(0.12, y0 + 0.05), Vector2(r * 1.0, y0 - 0.08), Vector2(r * 0.5, y0 + th * 0.5), Vector2(0.03, y0 + th)])
			cols = PackedColorArray([g * 0.65, g * (0.9 * lt), g * (lt * 1.1), g * (lt * 1.2)])
			sway = PackedFloat32Array([sw * 0.3, sw, sw * 0.85, sw * 0.7])
		for ci in cols.size():
			cols[ci] = Color(cols[ci].r, cols[ci].g, cols[ci].b, 1.0)
		crown.revolve(Vector3.ZERO, prof, cols, 9 if lod == 0 else 6, sway, 0.0, 0.37 * float(i + v))
	return {"trunk": trunk.commit(), "crown": crown.commit()}


# ---------------------------------------------------------------------------
# Light field: soft AO + warm light on a 2 m grid
# ---------------------------------------------------------------------------
const CELL := 2.0
var _w := 0
var _d := 0
var ao: PackedFloat32Array      # 0 = open sky .. 1 = deeply occluded
var warm: PackedFloat32Array    # 0 .. ~1 warm light


func _init(layout: CampusLayout) -> void:
	var b := CampusLayout.BOUNDS
	_w = int(b.size.x / CELL) + 1
	_d = int(b.size.y / CELL) + 1
	ao = PackedFloat32Array()
	ao.resize(_w * _d)
	ao.fill(0.0)
	warm = PackedFloat32Array()
	warm.resize(_w * _d)
	warm.fill(0.0)
	for t in layout.trees:
		_stamp(ao, t["pos"], 3.6, 0.45, 1.6)
	for bd in layout.buildings:
		var pos: Vector2 = bd["pos"]
		var size: Vector2 = bd["size"]
		_stamp_rect(ao, Rect2(pos - size * 0.5, size), 3.2, 0.5)
		# lit windows spill a little warmth onto the ground along the walls
		if not bd.get("dome", false) and String(bd["id"]) not in ["shed", "tower"]:
			_stamp_rect(warm, Rect2(pos - size * 0.5, size), 3.0, 0.16 * float(bd.get("warm", 0.5)) * 2.0)
	for s in layout.walls + layout.hedges:
		var a: Vector2 = s["a"]
		var bb: Vector2 = s["b"]
		var n := int(a.distance_to(bb) / CELL) + 1
		for i in n + 1:
			_stamp(ao, a.lerp(bb, float(i) / float(n)), 1.8, 0.22, 1.0)
	for lp in layout.lamps:
		_stamp(warm, lp, 8.0, 0.75, 1.4)
	for dd in layout.dorm_doors:
		var dp: Vector2 = dd["pos"]
		var dn: Vector2 = dd["normal"]
		_stamp(warm, dp + dn * 2.0, 6.0, 0.8, 1.2)


func _stamp(grid: PackedFloat32Array, c: Vector2, radius: float, amount: float, power: float) -> void:
	var b := CampusLayout.BOUNDS
	var r := int(ceil(radius / CELL))
	var ci := int(round((c.x - b.position.x) / CELL))
	var cj := int(round((c.y - b.position.y) / CELL))
	for j in range(cj - r, cj + r + 1):
		if j < 0 or j >= _d:
			continue
		for i in range(ci - r, ci + r + 1):
			if i < 0 or i >= _w:
				continue
			var p := Vector2(b.position.x + i * CELL, b.position.y + j * CELL)
			var t := 1.0 - p.distance_to(c) / radius
			if t <= 0.0:
				continue
			var idx := j * _w + i
			grid[idx] = minf(1.0, grid[idx] + amount * pow(t, power))


func _stamp_rect(grid: PackedFloat32Array, rect: Rect2, falloff: float, amount: float) -> void:
	var b := CampusLayout.BOUNDS
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
	var b := CampusLayout.BOUNDS
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


const WARM := Color(0.42, 0.26, 0.09)


## Bakes light_at into a MeshKit's vertices from `from` (those at or below
## max_y) - the same as MeshKit.bake_range(light_at) without a call per vertex.
func bake(mk: MeshKit, from: int, max_y: float = 3.0) -> void:
	var v := mk._v
	var n := mk._n
	var c := mk._c
	var bx := CampusLayout.BOUNDS.position.x
	var bz := CampusLayout.BOUNDS.position.y
	var wmax := float(_w - 1) - 0.001
	var dmax := float(_d - 1) - 0.001
	for i in range(from, v.size()):
		var p := v[i]
		if p.y > max_y:
			continue
		# both grids, one bilinear lookup
		var fx := clampf((p.x - bx) / CELL, 0.0, wmax)
		var fz := clampf((p.z - bz) / CELL, 0.0, dmax)
		var gi := int(fx)
		var gj := int(fz)
		var tx := fx - gi
		var tz := fz - gj
		var i00 := gj * _w + gi
		var i10 := i00 + _w
		var ao_s := lerpf(lerpf(ao[i00], ao[i00 + 1], tx), lerpf(ao[i10], ao[i10 + 1], tx), tz)
		var wm_s := lerpf(lerpf(warm[i00], warm[i00 + 1], tx), lerpf(warm[i10], warm[i10 + 1], tx), tz)
		var h := clampf(1.0 - maxf(p.y, 0.0) / 2.5, 0.0, 1.0)
		var o := ao_s * h
		var wl := wm_s * clampf(1.0 - maxf(p.y, 0.0) / 4.0, 0.0, 1.0)
		var m := 1.0 - 0.5 * o
		var nn := n[i]
		if absf(nn.y) < 0.5 and p.y < 1.4:
			m *= lerpf(0.78, 1.0, clampf(p.y / 1.4, 0.0, 1.0))
		var add := wl * (clampf(nn.y, 0.0, 1.0) * 0.6 + 0.4)
		var col := c[i]
		c[i] = Color(col.r * m + WARM.r * add, col.g * m + WARM.g * add, col.b * m + WARM.b * add, col.a)
	mk._c = c


## [multiply, add] for a vertex near the ground (MeshKit.bake_range): AO
## darkens and warm light adds lamp colour; both fade with height, and walls
## get a soft darkening toward their foot.
func light_at(p: Vector3, n: Vector3) -> Array:
	var h := clampf(1.0 - maxf(p.y, 0.0) / 2.5, 0.0, 1.0)
	var o := sample(ao, p.x, p.z) * h
	var wl := sample(warm, p.x, p.z) * clampf(1.0 - maxf(p.y, 0.0) / 4.0, 0.0, 1.0)
	var m := 1.0 - 0.5 * o
	if absf(n.y) < 0.5 and p.y < 1.4:
		m *= lerpf(0.78, 1.0, clampf(p.y / 1.4, 0.0, 1.0))   # contact shade at a wall's foot
	var face := clampf(n.y, 0.0, 1.0) * 0.6 + 0.4
	return [Color(m, m, m), WARM * (wl * face)]
