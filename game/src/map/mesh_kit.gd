class_name MeshKit
extends RefCounted
## Accumulates primitives into one ArrayMesh with vertex colours.
## CUSTOM0 (RG float) carries per-vertex emission strength (x) and wind sway
## (y).  (Until V4 these lived in UV2, which kept UV2 from ever holding a
## lightmap unwrap; UV2 is now free.)  Merging keeps draw calls low on mobile.
##
## V4: raw arrays instead of SurfaceTool, so a finished chunk can have
## lighting baked into its vertex colours (bake_range) before commit, plus
## smooth-shaded primitives (tri_n, revolve, chamfer_box, lobe) next to the
## original faceted ones.
##
## V5: UV carries a material id (x) and one parameter (y) for the world
## shaders' detail patterns (see world_common.gdshaderinc).  Set `mat` (and
## `param`) before adding primitives; everything added takes them.

var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()
var _cu := PackedFloat32Array()   # 2 floats per vertex (emission, sway)
var _uv := PackedVector2Array()   # material id, parameter (V5)
var _count := 0
## V5: an indexed grid section (the ground) may come first; everything
## after _grid_end is plain triangles (one vertex each corner)
var _gidx := PackedInt32Array()
var _grid_end := 0
## material id / parameter for what is added next (world_common's table)
var mat := 0.0
var param := 0.0

const M_PLAIN := 0.0
const M_LAWN := 1.0
const M_PAVING := 2.0
const M_GRAVEL := 3.0
const M_ASPHALT := 4.0
const M_BRICK := 5.0
const M_ROOF := 6.0
const M_STONE := 7.0
const M_WOOD := 8.0
const M_LEAF := 10.0
const M_BARK := 11.0
const M_ROCK := 12.0
const M_METAL := 14.0
const M_GLASS := 15.0
const M_TILE := 16.0
const M_PLASTER := 17.0
const M_VERGE := 18.0


func is_empty() -> bool:
	return _count == 0


## Vertices so far (bake_range start marks).
func vert_count() -> int:
	return _v.size()


## Adds one grid vertex (indexed section) and returns its index.
func grid_vertex(p: Vector3, n: Vector3, col: Color, uv: Vector2) -> int:
	_v.append(p)
	_n.append(n)
	_c.append(col)
	_cu.append(0.0)
	_cu.append(0.0)
	_uv.append(uv)
	_grid_end = _v.size()
	return _grid_end - 1


func grid_tri(a: int, b: int, c: int) -> void:
	_gidx.append(a)
	_gidx.append(b)
	_gidx.append(c)
	_count += 1


func commit() -> ArrayMesh:
	if _count == 0:
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	if not _gidx.is_empty():
		# the grid's shared vertices, then one index per plain-triangle corner
		var idx := _gidx.duplicate()
		idx.append_array(PackedInt32Array(range(_grid_end, _v.size())))
		arr[Mesh.ARRAY_INDEX] = idx
	arr[Mesh.ARRAY_VERTEX] = _v
	arr[Mesh.ARRAY_NORMAL] = _n
	arr[Mesh.ARRAY_COLOR] = _c
	arr[Mesh.ARRAY_CUSTOM0] = _cu
	arr[Mesh.ARRAY_TEX_UV] = _uv
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {},
		Mesh.ARRAY_CUSTOM_RG_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	return m


## Multiplies (rgb) and adds (rgb) light to the vertices added since `from`
## (only those at or below max_y): fn(position, normal) -> [mul, add].
func bake_range(from: int, fn: Callable, max_y: float = INF) -> void:
	for i in range(from, _v.size()):
		if _v[i].y > max_y:
			continue
		var r: Array = fn.call(_v[i], _n[i])
		var mul: Color = r[0]
		var add: Color = r[1]
		var c := _c[i]
		_c[i] = Color(c.r * mul.r + add.r, c.g * mul.g + add.g, c.b * mul.b + add.b, c.a)


func _push(p: Vector3, n: Vector3, col: Color, emis: float, sway: float) -> void:
	_v.append(p)
	_n.append(n)
	_c.append(col)
	_cu.append(emis)
	_cu.append(sway)
	_uv.append(Vector2(mat, param))


## Sets the emission of the last n vertices (glowing faces built with
## helpers that take no emission argument).
func cu_emission_last(n: int, emis: float) -> void:
	var start := maxi(_v.size() - n, 0)
	for i in range(start, _v.size()):
		_cu[i * 2] = emis


## Sets mat/param and returns self (k.with(M_BRICK).box(...)).
func with(m: float, p: float = 0.0) -> MeshKit:
	mat = m
	param = p
	return self


## Raw smooth triangle with a colour (incl. alpha) and uv per corner.
func tri_full(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, ca: Color, cb: Color, cc: Color, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	_v.append(a)
	_v.append(b)
	_v.append(c)
	_n.append(na)
	_n.append(nb)
	_n.append(nc)
	_c.append(ca)
	_c.append(cb)
	_c.append(cc)
	for i in 6:
		_cu.append(0.0)
	_uv.append(ua)
	_uv.append(ub)
	_uv.append(uc)
	_count += 1


func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, emis: float = 0.0, sway: float = 0.0, n: Vector3 = Vector3.ZERO) -> void:
	var nn := n
	if nn == Vector3.ZERO:
		nn = (b - a).cross(c - a)
		if nn.length_squared() < 1e-12:
			return
		nn = -nn.normalized()
	# inlined _push (hot path)
	var uvv := Vector2(mat, param)
	_v.append(a)
	_v.append(b)
	_v.append(c)
	_n.append(nn)
	_n.append(nn)
	_n.append(nn)
	_c.append(col)
	_c.append(col)
	_c.append(col)
	_cu.append_array(PackedFloat32Array([emis, sway, emis, sway, emis, sway]))
	_uv.append(uvv)
	_uv.append(uvv)
	_uv.append(uvv)
	_count += 1


## Smooth-shaded triangle: a normal and a colour per corner.
func tri_n(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, ca: Color, cb: Color, cc: Color, emis: float = 0.0, sway_a: float = 0.0, sway_b: float = 0.0, sway_c: float = 0.0) -> void:
	if (b - a).cross(c - a).length_squared() < 1e-12:
		return
	var uvv := Vector2(mat, param)
	_v.append(a)
	_v.append(b)
	_v.append(c)
	_n.append(na)
	_n.append(nb)
	_n.append(nc)
	_c.append(ca)
	_c.append(cb)
	_c.append(cc)
	_cu.append_array(PackedFloat32Array([emis, sway_a, emis, sway_b, emis, sway_c]))
	_uv.append(uvv)
	_uv.append(uvv)
	_uv.append(uvv)
	_count += 1


## Surface of revolution around `base` (+Y): profile points (radius, height)
## from bottom to top, a colour per profile point, smooth normals from the
## profile's tangents.  Pines, trunks, posts, rounded rims and finials.
func revolve(base: Vector3, profile: PackedVector2Array, cols: PackedColorArray, seg: int = 12, sway: PackedFloat32Array = PackedFloat32Array(), emis: float = 0.0, yaw0: float = 0.0) -> void:
	var n := profile.size()
	var nrm2: Array[Vector2] = []
	for i in n:
		var t := profile[mini(i + 1, n - 1)] - profile[maxi(i - 1, 0)]
		var o := Vector2(t.y, -t.x)
		if o.length_squared() < 1e-10:
			o = Vector2(0, 1)
		nrm2.append(o.normalized())
	for s in seg:
		var a0 := yaw0 + TAU * float(s) / float(seg)
		var a1 := yaw0 + TAU * float(s + 1) / float(seg)
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		for i in n - 1:
			var p0 := profile[i]
			var p1 := profile[i + 1]
			var q00 := base + d0 * p0.x + Vector3.UP * p0.y
			var q01 := base + d1 * p0.x + Vector3.UP * p0.y
			var q10 := base + d0 * p1.x + Vector3.UP * p1.y
			var q11 := base + d1 * p1.x + Vector3.UP * p1.y
			var n00 := (d0 * nrm2[i].x + Vector3.UP * nrm2[i].y).normalized()
			var n01 := (d1 * nrm2[i].x + Vector3.UP * nrm2[i].y).normalized()
			var n10 := (d0 * nrm2[i + 1].x + Vector3.UP * nrm2[i + 1].y).normalized()
			var n11 := (d1 * nrm2[i + 1].x + Vector3.UP * nrm2[i + 1].y).normalized()
			var c0 := cols[mini(i, cols.size() - 1)]
			var c1 := cols[mini(i + 1, cols.size() - 1)]
			var s0 := sway[i] if sway.size() > i else 0.0
			var s1 := sway[i + 1] if sway.size() > i + 1 else 0.0
			# front faces are clockwise seen from outside
			tri_n(q00, q10, q11, n00, n10, n11, c0, c1, c1, emis, s0, s1, s1)
			tri_n(q00, q11, q01, n00, n11, n01, c0, c1, c0, emis, s0, s1, s0)


## Smooth ellipsoid lobe (latitude/longitude, normals from the ellipsoid),
## coloured by a callable(normal) -> Color for baked self-shading, or (V5,
## faster: no callable) by `col` with the soft_blob shading when color_fn is
## not given.  Colours are evaluated once per grid vertex.
func lobe(center: Vector3, radii: Vector3, color_fn: Callable, rings: int = 6, seg: int = 10, sway: float = 0.0, jitter: float = 0.0, seed_v: int = 0, col: Color = Color.WHITE) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var use_fn := color_fn.is_valid()
	var pts: Array = []
	var nrm: Array = []
	var cls: Array = []
	for r in rings + 1:
		var row: Array = []
		var nrow: Array = []
		var crow: Array = []
		var phi := PI * float(r) / float(rings)
		for s in seg + 1:
			var th := TAU * float(s % seg) / float(seg)
			var u := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var j := 1.0
			if jitter > 0.0 and r > 0 and r < rings and s < seg:
				j = 1.0 + rng.randf_range(-jitter, jitter)
			var p := u * radii * j
			row.append(center + p)
			var nn := Vector3(u.x / radii.x, u.y / radii.y, u.z / radii.z).normalized()
			nrow.append(nn)
			if use_fn:
				crow.append(color_fn.call(nn))
			else:
				var sh := 0.62 + 0.38 * smoothstep(-0.8, 0.9, nn.y)
				crow.append(Color(col.r * sh, col.g * sh, col.b * sh, col.a))
		# close the seam exactly
		row[seg] = row[0]
		crow[seg] = crow[0]
		pts.append(row)
		nrm.append(nrow)
		cls.append(crow)
	for r in rings:
		for s in seg:
			var a: Vector3 = pts[r][s]
			var b: Vector3 = pts[r][s + 1]
			var c: Vector3 = pts[r + 1][s + 1]
			var d: Vector3 = pts[r + 1][s]
			var na: Vector3 = nrm[r][s]
			var nb: Vector3 = nrm[r][s + 1]
			var nc: Vector3 = nrm[r + 1][s + 1]
			var nd: Vector3 = nrm[r + 1][s]
			var sa := sway * (0.6 + 0.4 * na.y)
			var sd := sway * (0.6 + 0.4 * nd.y)
			if r != 0:
				tri_n(b, a, d, nb, na, nd, cls[r][s + 1], cls[r][s], cls[r + 1][s], 0.0, sa, sa, sd)
			if r != rings - 1:
				tri_n(b, d, c, nb, nd, nc, cls[r][s + 1], cls[r + 1][s], cls[r + 1][s + 1], 0.0, sa, sd, sd)


## Smooth ellipsoid with soft self-shading (lit top, darker underside):
## rocks, hedge tops, shrubs, small rounded props.
func soft_blob(center: Vector3, radii: Vector3, col: Color, rings: int = 4, seg: int = 8, sway: float = 0.0, jitter: float = 0.0, seed_v: int = 0, emis: float = 0.0) -> void:
	var start := _v.size()
	lobe(center, radii, Callable(), rings, seg, sway, jitter, seed_v, col)
	if emis > 0.0:
		for i in range(start, _v.size()):
			_cu[i * 2] = emis


## Box with chamfered (softly lit) edges: faces inset by `bevel`, edge strips
## and corners carry the neighbouring faces' normals, so edges catch light
## like rounded stone or painted wood.  xf maps the unit cube to world
## (rotation + translation; size given separately so the bevel stays even).
func chamfer_box(center: Vector3, size: Vector3, col: Color, bevel: float = 0.06, yaw: float = 0.0, top_col: Variant = null, skip_bottom: bool = true, emis: float = 0.0) -> void:
	var h := size * 0.5
	var bv := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.9)
	var basis := Basis(Vector3.UP, yaw)
	var tc: Color = col if top_col == null else top_col
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	# faces
	for ai in 3:
		for sg in [-1.0, 1.0]:
			var n: Vector3 = axes[ai] * sg
			if ai == 1 and sg < 0.0 and skip_bottom:
				continue
			var u: Vector3 = axes[(ai + 1) % 3]
			var v: Vector3 = axes[(ai + 2) % 3]
			var hu: float = absf(h.dot(u)) - bv
			var hv: float = absf(h.dot(v)) - bv
			var c0 := n * absf(h.dot(n))
			var fc := tc if (ai == 1 and sg > 0.0) else (col.darkened(0.06) if ai == 0 else col)
			var q := [c0 - u * hu - v * hv, c0 + u * hu - v * hv, c0 + u * hu + v * hv, c0 - u * hu + v * hv]
			var nn: Vector3 = basis * n
			# orient clockwise from outside
			var A: Vector3 = center + basis * (q[0] as Vector3)
			var B: Vector3 = center + basis * (q[1] as Vector3)
			var C: Vector3 = center + basis * (q[2] as Vector3)
			var D: Vector3 = center + basis * (q[3] as Vector3)
			if (B - A).cross(C - A).dot(nn) > 0.0:
				tri_n(A, C, B, nn, nn, nn, fc, fc, fc, emis)
				tri_n(A, D, C, nn, nn, nn, fc, fc, fc, emis)
			else:
				tri_n(A, B, C, nn, nn, nn, fc, fc, fc, emis)
				tri_n(A, C, D, nn, nn, nn, fc, fc, fc, emis)
	# edge strips (between two faces) with the faces' normals at each side
	for ai in 3:
		var u2: Vector3 = axes[(ai + 1) % 3]
		var v2: Vector3 = axes[(ai + 2) % 3]
		var len: float = absf(h.dot(axes[ai])) - bv
		for su in [-1.0, 1.0]:
			for sv in [-1.0, 1.0]:
				var nu: Vector3 = u2 * su
				var nvv: Vector3 = v2 * sv
				if skip_bottom and ((nu.y < -0.5) or (nvv.y < -0.5)):
					continue
				var pu := nu * absf(h.dot(u2)) + nvv * (absf(h.dot(v2)) - bv)
				var pv := nvv * absf(h.dot(v2)) + nu * (absf(h.dot(u2)) - bv)
				var e: Vector3 = axes[ai] * len
				var A2: Vector3 = center + basis * (pu - e)
				var B2: Vector3 = center + basis * (pu + e)
				var C2: Vector3 = center + basis * (pv + e)
				var D2: Vector3 = center + basis * (pv - e)
				var n_u: Vector3 = basis * nu
				var n_v: Vector3 = basis * nvv
				var cu := tc if nu.y > 0.5 else col
				var cv := tc if nvv.y > 0.5 else col
				var out := (n_u + n_v).normalized()
				if (B2 - A2).cross(C2 - A2).dot(out) > 0.0:
					tri_n(A2, C2, B2, n_u, n_v, n_u, cu, cv, cu, emis)
					tri_n(A2, D2, C2, n_u, n_v, n_v, cu, cv, cv, emis)
				else:
					tri_n(A2, B2, C2, n_u, n_u, n_v, cu, cu, cv, emis)
					tri_n(A2, C2, D2, n_u, n_v, n_v, cu, cv, cv, emis)
	# corners
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				if skip_bottom and sy < 0.0:
					continue
				var cx := Vector3(sx * h.x, sy * (h.y - bv), sz * (h.z - bv))
				var cy := Vector3(sx * (h.x - bv), sy * h.y, sz * (h.z - bv))
				var cz := Vector3(sx * (h.x - bv), sy * (h.y - bv), sz * h.z)
				var X: Vector3 = center + basis * cx
				var Y: Vector3 = center + basis * cy
				var Z: Vector3 = center + basis * cz
				var nx: Vector3 = basis * Vector3(sx, 0, 0)
				var ny: Vector3 = basis * Vector3(0, sy, 0)
				var nz: Vector3 = basis * Vector3(0, 0, sz)
				var ccy := tc if sy > 0.0 else col
				var outc := (nx + ny + nz).normalized()
				if (Y - X).cross(Z - X).dot(outc) > 0.0:
					tri_n(X, Z, Y, nx, nz, ny, col, col, ccy, emis)
				else:
					tri_n(X, Y, Z, nx, ny, nz, col, ccy, col, emis)


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, emis: float = 0.0, sway: float = 0.0) -> void:
	# a-b-c-d in clockwise order when seen from the front (Godot front faces are clockwise)
	tri(a, b, c, col, emis, sway)
	tri(a, c, d, col, emis, sway)


## Oriented box. xf maps unit cube (-0.5..0.5) to world.
func box_xf(xf: Transform3D, col: Color, emis: float = 0.0, sway: float = 0.0, skip_bottom: bool = true, top_col: Variant = null) -> void:
	var p := [
		xf * Vector3(-0.5, -0.5, -0.5), xf * Vector3(0.5, -0.5, -0.5), xf * Vector3(0.5, -0.5, 0.5), xf * Vector3(-0.5, -0.5, 0.5),
		xf * Vector3(-0.5, 0.5, -0.5), xf * Vector3(0.5, 0.5, -0.5), xf * Vector3(0.5, 0.5, 0.5), xf * Vector3(-0.5, 0.5, 0.5),
	]
	var tc: Color = col if top_col == null else top_col
	quad(p[4], p[5], p[6], p[7], tc, emis, sway)          # top (+y)
	if not skip_bottom:
		quad(p[3], p[2], p[1], p[0], col.darkened(0.3), emis, sway)
	quad(p[7], p[6], p[2], p[3], col, emis, sway)          # +z
	quad(p[5], p[4], p[0], p[1], col, emis, sway)          # -z
	quad(p[6], p[5], p[1], p[2], col.darkened(0.06), emis, sway)  # +x
	quad(p[4], p[7], p[3], p[0], col.darkened(0.06), emis, sway)  # -x


func box(center: Vector3, size: Vector3, col: Color, yaw: float = 0.0, emis: float = 0.0, top_col: Variant = null) -> void:
	var b := Basis(Vector3.UP, yaw).scaled(size)
	box_xf(Transform3D(b, center), col, emis, 0.0, true, top_col)


## Box spanning a segment on the ground (walls, hedges, rails).
func segment_box(a: Vector2, b: Vector2, y0: float, h: float, t: float, col: Color, emis: float = 0.0, top_col: Variant = null) -> void:
	var d := b - a
	var L := d.length()
	if L < 0.01:
		return
	var yaw := atan2(-d.y, d.x)
	var c := (a + b) * 0.5
	var basis := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(L, h, t))
	box_xf(Transform3D(basis, Vector3(c.x, y0 + h * 0.5, c.y)), col, emis, 0.0, true, top_col)


func cylinder(base: Vector3, r: float, h: float, col: Color, seg: int = 8, emis: float = 0.0, top: bool = true, r_top: float = -1.0, sway: float = 0.0) -> void:
	var rt := r if r_top < 0.0 else r_top
	var top_y := base.y + h
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		var b0 := base + Vector3(cos(a0) * r, 0, sin(a0) * r)
		var b1 := base + Vector3(cos(a1) * r, 0, sin(a1) * r)
		var t0 := Vector3(base.x + cos(a0) * rt, top_y, base.z + sin(a0) * rt)
		var t1 := Vector3(base.x + cos(a1) * rt, top_y, base.z + sin(a1) * rt)
		var shade := col.darkened(0.08 * (0.5 + 0.5 * sin(a0 * 1.0)))
		quad(t1, t0, b0, b1, shade, emis, sway)
		if top and rt > 0.001:
			tri(Vector3(base.x, top_y, base.z), t0, t1, col.lightened(0.05), emis, sway)


func cone(base: Vector3, r: float, h: float, col: Color, seg: int = 8, emis: float = 0.0, sway: float = 0.0) -> void:
	var apex := base + Vector3(0, h, 0)
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		var b0 := base + Vector3(cos(a0) * r, 0, sin(a0) * r)
		var b1 := base + Vector3(cos(a1) * r, 0, sin(a1) * r)
		tri(apex, b0, b1, col.darkened(0.1 * (0.5 + 0.5 * cos(a0))), emis, sway)
		tri(base, b1, b0, col.darkened(0.3), emis, sway)


## Low-poly ellipsoid (faceted, charming).
func blob(center: Vector3, radii: Vector3, col: Color, rings: int = 4, seg: int = 7, emis: float = 0.0, sway: float = 0.0, jitter: float = 0.0, seed_v: int = 0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var pts: Array = []
	for r in rings + 1:
		var row: Array = []
		var v := float(r) / float(rings)
		var phi := PI * v
		for s in seg:
			var th := TAU * float(s) / float(seg) + (0.5 if r % 2 == 1 else 0.0) * TAU / float(seg)
			var j := 1.0
			if jitter > 0.0 and r > 0 and r < rings:
				j = 1.0 + rng.randf_range(-jitter, jitter)
			var p := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th)) * radii * j
			row.append(center + p)
		pts.append(row)
	for r in rings:
		for s in seg:
			var s1 := (s + 1) % seg
			var a: Vector3 = pts[r][s]
			var b: Vector3 = pts[r][s1]
			var c: Vector3 = pts[r + 1][s1]
			var d: Vector3 = pts[r + 1][s]
			var shade := col.lightened(0.08) if r == 0 else (col.darkened(0.12) if r == rings - 1 else col)
			if r == 0:
				tri(a, d, c, shade, emis, sway)
			elif r == rings - 1:
				tri(b, a, d, shade, emis, sway)
			else:
				quad(b, a, d, c, shade, emis, sway)


## Gable roof over a box footprint. Ridge runs along the longer axis.
func gable_roof(center: Vector2, size: Vector2, y0: float, rise: float, col: Color, overhang: float = 0.6) -> void:
	var hx := size.x * 0.5 + overhang
	var hz := size.y * 0.5 + overhang
	var y1 := y0 + rise
	if size.x >= size.y:
		var a := Vector3(center.x - hx, y0, center.y - hz)
		var b := Vector3(center.x + hx, y0, center.y - hz)
		var c := Vector3(center.x + hx, y0, center.y + hz)
		var d := Vector3(center.x - hx, y0, center.y + hz)
		var r0 := Vector3(center.x - hx, y1, center.y)
		var r1 := Vector3(center.x + hx, y1, center.y)
		quad(r1, r0, a, b, col.darkened(0.12))
		quad(r0, r1, c, d, col)
		tri(a, r0, d, col.darkened(0.25))
		tri(c, r1, b, col.darkened(0.25))
	else:
		var a2 := Vector3(center.x - hx, y0, center.y - hz)
		var b2 := Vector3(center.x + hx, y0, center.y - hz)
		var c2 := Vector3(center.x + hx, y0, center.y + hz)
		var d2 := Vector3(center.x - hx, y0, center.y + hz)
		var r2 := Vector3(center.x, y1, center.y - hz)
		var r3 := Vector3(center.x, y1, center.y + hz)
		quad(r2, r3, d2, a2, col.darkened(0.12))
		quad(r3, r2, b2, c2, col)
		tri(a2, b2, r2, col.darkened(0.25))
		tri(c2, d2, r3, col.darkened(0.25))


## Flat ribbon along a polyline at height y (roads, paths).
func ribbon(pts: PackedVector2Array, w: float, y: float, col: Color, emis: float = 0.0, joints: bool = true) -> void:
	var hw := w * 0.5
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var d := (b - a).normalized()
		var n := Vector2(-d.y, d.x) * hw
		quad(Vector3(a.x - n.x, y, a.y - n.y), Vector3(b.x - n.x, y, b.y - n.y), Vector3(b.x + n.x, y, b.y + n.y), Vector3(a.x + n.x, y, a.y + n.y), col, emis)
	if joints:
		for i in range(1, pts.size() - 1):
			disc(Vector3(pts[i].x, y + 0.002, pts[i].y), hw, col, 10, emis)


func disc(center: Vector3, r: float, col: Color, seg: int = 12, emis: float = 0.0) -> void:
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		tri(center, center + Vector3(cos(a0) * r, 0, sin(a0) * r), center + Vector3(cos(a1) * r, 0, sin(a1) * r), col, emis, 0.0, Vector3.UP)


func ellipse_disc(center: Vector3, rx: float, rz: float, col: Color, seg: int = 20, emis: float = 0.0) -> void:
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		tri(center, center + Vector3(cos(a0) * rx, 0, sin(a0) * rz), center + Vector3(cos(a1) * rx, 0, sin(a1) * rz), col, emis, 0.0, Vector3.UP)


func ring(center: Vector3, r_in: float, r_out: float, h: float, col: Color, seg: int = 16, emis: float = 0.0, top_col: Variant = null) -> void:
	var tc: Color = col if top_col == null else top_col
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		var c0 := Vector3(cos(a0), 0, sin(a0))
		var c1 := Vector3(cos(a1), 0, sin(a1))
		var top := Vector3(0, h, 0)
		var oi0 := center + c0 * r_out
		var oi1 := center + c1 * r_out
		var ii0 := center + c0 * r_in
		var ii1 := center + c1 * r_in
		quad(oi0 + top, oi1 + top, ii1 + top, ii0 + top, tc, emis)
		quad(oi1 + top, oi0 + top, oi0, oi1, col, emis)
		quad(ii0 + top, ii1 + top, ii1, ii0, col.darkened(0.15), emis)
