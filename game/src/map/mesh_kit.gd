class_name MeshKit
extends RefCounted
## Accumulates low-poly primitives into one ArrayMesh with vertex colours.
## UV2.x carries per-vertex emission strength, UV2.y carries wind sway.
## Merging keeps draw calls low on mobile GPUs.

var _st := SurfaceTool.new()
var _count := 0


func _init() -> void:
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)


func is_empty() -> bool:
	return _count == 0


func commit() -> ArrayMesh:
	if _count == 0:
		return null
	return _st.commit()


func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, emis: float = 0.0, sway: float = 0.0, n: Vector3 = Vector3.ZERO) -> void:
	var nn := n
	if nn == Vector3.ZERO:
		nn = (b - a).cross(c - a)
		if nn.length_squared() < 1e-12:
			return
		nn = -nn.normalized()
	var uv2 := Vector2(emis, sway)
	for v in [a, b, c]:
		_st.set_color(col)
		_st.set_normal(nn)
		_st.set_uv2(uv2)
		_st.add_vertex(v)
	_count += 1


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
