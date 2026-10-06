class_name DormArt
extends RefCounted
## The look of the start dorms (CampusDorms), built with the campus kit: the
## same MeshKit chunks, world shader and material ids as every other
## building.  Visual only: the colliders come from CampusDorms.geometry via
## CampusBuilder.build_collision, and every surface here follows them.
##
##   exterior   the traced building through the generic generator
##              (CampusArchitecture.building) with the dorm's doorways cut
##              open: no wall, window or door leaf across them; a portico
##              at a doorway is still drawn
##   doorways   reveals and a soffit through the wall, a stone surround, a
##              lit transom, lanterns, a flush threshold, a porch hood where
##              there is no portico, a warm pool of light either side
##   interior   the commons: plaster walls over a wainscot (open where the
##              door corridors meet them), plank floor, rugs, ceiling with
##              beams and pendant lights, the furniture whose colliders the
##              data defines (sofas, tables, a hearth, shelves), a few
##              pictures and plants
## Warmth inside comes from per-vertex emission and the light field's warm
## channel stamped over the room (CampusKit).

var B: CampusBuilder
var A: CampusArchitecture
var L: CampusLayout

const STONE := Color(0.74, 0.72, 0.70)
const TRIM := Color(0.90, 0.88, 0.84)
const IRON := Color(0.17, 0.19, 0.25)
const WOOD_DARK := Color(0.36, 0.23, 0.16)
const INNER := Color(0.86, 0.76, 0.62)
const FLOOR := Color(0.55, 0.38, 0.25)
const FABRIC := Color(0.36, 0.30, 0.46)
const ACCENT := Color(0.30, 0.42, 0.66)


func _init(builder: CampusBuilder, arch: CampusArchitecture) -> void:
	B = builder
	A = arch
	L = builder.L


func _k(x: float, z: float, detail: bool = false) -> MeshKit:
	return B.kit_at(x, z, false, detail)


static func _v(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


static func _col(d: Dictionary, key: String, fallback: Color) -> Color:
	var v: Variant = d.get(key)
	if v is Array and (v as Array).size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]))
	return fallback


## A vertical quad over the ground segment a-b from y0 to y1, facing `facing`.
func _wall_quad(k: MeshKit, a: Vector2, b: Vector2, y0: float, y1: float, facing: Vector3, col: Color, emis: float = 0.0) -> void:
	A._quad_facing(k, _v(a, y0), _v(b, y0), _v(b, y1), _v(a, y1), col, facing)
	if emis > 0.0:
		k.cu_emission_last(6, emis)


## One start dorm, inside and out (the staged build calls the halves as
## two steps).
func dorm(id: String) -> void:
	exterior(id)
	inside(id)


## The building through the generic generator, its doorways cut open.
func exterior(id: String) -> void:
	var g := CampusDorms.geometry(id)
	var bd := L.building_by_id(String(g.get("building", "")))
	if g.is_empty() or bd.is_empty():
		return
	var holes: Array = []
	for dr in g["doors"]:
		holes.append({"pos": dr["pos"], "normal": dr["normal"], "w": float(dr["w"]), "h": CampusDorms.DOOR_H})
	A.building(bd, holes)


## The doorways' dressing and the open interior.
func inside(id: String) -> void:
	var g := CampusDorms.geometry(id)
	var bd := L.building_by_id(String(g.get("building", "")))
	if g.is_empty() or bd.is_empty():
		return
	var d := CampusDorms.def(id)
	_doorways(bd, g, d)
	_interior(g, d)


# ---------------------------------------------------------------------------
# Doorways
# ---------------------------------------------------------------------------
func _doorways(bd: Dictionary, g: Dictionary, d: Dictionary) -> void:
	var DH := CampusDorms.DOOR_H
	var porticos: Array = []
	for e in bd["entrances"]:
		if String(e.get("kind", "")) == "portico":
			porticos.append(CampusLayout._v2(e.get("p", [0, 0])))
	var roof_c := _col(d, "roof", Color(0.24, 0.25, 0.29))
	for i in (g["doors"] as Array).size():
		var dr: Dictionary = g["doors"][i]
		var p: Vector2 = dr["pos"]
		var n: Vector2 = dr["normal"]
		var tg: Vector2 = dr["tangent"]
		var n_in: Vector2 = dr["n_in"]
		var hw := float(dr["w"]) * 0.5
		var t := float(dr["wall_t"])
		var n3 := Vector3(n.x, 0, n.y)
		var t3 := Vector3(tg.x, 0, tg.y)
		var yaw := atan2(-tg.y, tg.x)
		var base := Vector3(p.x, 0, p.y)
		var k := _k(p.x, p.y)
		var kd := _k(p.x, p.y, true)
		var main := i == 0
		# the cut through the wall: its sides are the corridor's walls
		# (_interior); here the soffit and the lintel's inner face up to the
		# ceiling
		var inner := p + n_in * t
		var C := float(g["ceil"])
		k.mat = MeshKit.M_PLASTER
		A._quad_facing(k, _v(p - tg * hw, DH), _v(p + tg * hw, DH), _v(inner + tg * hw, DH), _v(inner - tg * hw, DH), INNER.darkened(0.3), Vector3.DOWN)
		if C > DH + 0.05:
			_wall_quad(k, inner - tg * hw, inner + tg * hw, DH, C, Vector3(n_in.x, 0, n_in.y), INNER.darkened(0.1), 0.2)
		# stone surround with a keystone, a lit transom over the opening
		k.mat = MeshKit.M_STONE
		for sgn2: float in [-1.0, 1.0]:
			k.chamfer_box(base + t3 * ((hw + 0.18) * sgn2) + Vector3.UP * (DH * 0.5 + 0.1) + n3 * 0.06, Vector3(0.36, DH + 0.2, 0.16), STONE, 0.04, yaw)
		k.chamfer_box(base + Vector3.UP * (DH + 0.2) + n3 * 0.07, Vector3(hw * 2.0 + 0.9, 0.34, 0.2), STONE.lightened(0.04), 0.05, yaw)
		k.chamfer_box(base + Vector3.UP * (DH + 0.42) + n3 * 0.1, Vector3(0.4, 0.5, 0.22), TRIM, 0.04, yaw)
		k.mat = MeshKit.M_GLASS
		var fan := base + Vector3.UP * (DH + 0.85) + n3 * 0.05
		var fw := minf(hw * 0.8, 1.3)
		A._quad_facing(k, fan - t3 * fw, fan + t3 * fw, fan + t3 * fw + Vector3.UP * 0.55, fan - t3 * fw + Vector3.UP * 0.55, Color(1.0, 0.82, 0.52), n3)
		k.cu_emission_last(6, 1.3)
		kd.mat = MeshKit.M_WOOD
		for m in 5:
			var mx := -fw + fw * 0.5 * float(m)
			kd.box(fan + t3 * mx + Vector3.UP * 0.275 + n3 * 0.02, Vector3(0.06, 0.6, 0.04), TRIM, yaw)
		kd.mat = 0.0
		# a porch hood on brackets where no portico stands
		var has_portico := not CampusArchitecture._passage_near(p, bd["passages"]).is_empty()
		for pp in porticos:
			if (pp as Vector2).distance_to(p) < hw + 1.5:
				has_portico = true
		if not has_portico:
			var depth := 2.2 if main else 1.4
			var width := hw * 2.0 + (2.0 if main else 1.0)
			var hood_c := base + n3 * (depth * 0.5) + Vector3.UP * (DH + 1.45)
			k.mat = MeshKit.M_ROOF
			k.chamfer_box(hood_c, Vector3(width, 0.26, depth), roof_c.lightened(0.05), 0.08, yaw)
			k.mat = MeshKit.M_WOOD
			for sgn3: float in [-1.0, 1.0]:
				var bb: Vector3 = base + t3 * ((width * 0.5 - 0.35) * sgn3)
				k.chamfer_box(bb + n3 * 0.1 + Vector3.UP * (DH + 0.85), Vector3(0.14, 0.9, 0.14), TRIM.darkened(0.12), 0.02, yaw)
				k.chamfer_box(bb + n3 * (depth * 0.45) + Vector3.UP * (DH + 1.25), Vector3(0.12, 0.14, depth * 0.9), TRIM.darkened(0.12), 0.02, yaw)
			k.mat = 0.0
			k.soft_blob(hood_c - Vector3.UP * 0.32, Vector3(0.22, 0.26, 0.22), Color(1.0, 0.85, 0.5), 3, 8, 0.0, 0.0, 0, 2.4)
		# lanterns, a flush stone threshold, the warm pools either side
		for sgn4: float in [-1.0, 1.0]:
			A.wall_lantern(base + t3 * ((hw + 0.75) * sgn4) + n3 * 0.02, n3)
		k.mat = MeshKit.M_STONE
		var th := (p + inner) * 0.5
		k.box(Vector3(th.x, 0.02, th.y), Vector3(hw * 2.0, 0.04, t + 0.3), STONE.lightened(0.05), yaw)
		k.mat = 0.0
		B.glow_disc(Vector3(p.x + n.x * 2.0, 0.11, p.y + n.y * 2.0), 4.6 if main else 3.6)
		var ins: Vector2 = dr["inside"]
		B.glow_disc(Vector3(ins.x, 0.06, ins.y), 2.4)


# ---------------------------------------------------------------------------
# Interior: the commons
# ---------------------------------------------------------------------------
## The open interior as polygons: the commons and the door corridors merged,
## clipped to the building's footprint.
static func open_space(g: Dictionary) -> Array[PackedVector2Array]:
	var parts: Array[PackedVector2Array] = []
	for ip in g["interior"]:
		var poly: PackedVector2Array = ip
		var merged := false
		for i in parts.size():
			var outer := _outer(Geometry2D.merge_polygons(parts[i], poly))
			if outer.size() == 1:
				parts[i] = outer[0]
				merged = true
				break
		if not merged:
			parts.append(poly)
	var out: Array[PackedVector2Array] = []
	var foot: PackedVector2Array = g["footprint"]
	for pc in parts:
		for q in _outer(Geometry2D.intersect_polygons(pc, foot)):
			out.append(CampusData.ccw(q))
	return out


## The outer rings of a Clipper result (holes wind the other way).
static func _outer(res: Array) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if res.is_empty():
		return out
	var big: PackedVector2Array = res[0]
	for r in res:
		if absf(CampusData.area(r)) > absf(CampusData.area(big)):
			big = r
	var cw := Geometry2D.is_polygon_clockwise(big)
	for r in res:
		if Geometry2D.is_polygon_clockwise(r) == cw:
			out.append(r)
	return out


## Is the edge a-b a doorway mouth (on the outer wall where a door is)?
static func _mouth(a: Vector2, b: Vector2, doors: Array) -> bool:
	var m := (a + b) * 0.5
	for dr in doors:
		var p: Vector2 = dr["pos"]
		var n: Vector2 = dr["normal"]
		# on the outer face (the corridor reaches 0.4 m past it)
		if absf((m - p).dot(n)) < 0.45 and absf((m - p).dot(Vector2(-n.y, n.x))) <= float(dr["w"]) * 0.5 + 0.2:
			return true
	return false


func _interior(g: Dictionary, d: Dictionary) -> void:
	var room: PackedVector2Array = CampusData.ccw(g["room"])
	if room.size() < 3:
		return
	var C := float(g["ceil"])
	var c := CampusData.centroid(room)
	var k := _k(c.x, c.y)
	var kd := _k(c.x, c.y, true)
	var style: Dictionary = d.get("interior", {}) if d.get("interior") is Dictionary else {}
	var brick := String(style.get("wall", "plaster")) == "brick"
	var inner := _col(style, "inner", _col(d, "inner", INNER))
	var floor_c := _col(style, "floor", _col(d, "floor", FLOOR))
	var fabric := _col(d, "fabric", FABRIC)
	var accent := _col(d, "accent", ACCENT)
	var doors: Array = g["doors"]
	var longest := -1
	var longest_len := 0.0
	var longest_poly := PackedVector2Array()
	for sp in open_space(g):
		var kc := _k(CampusData.centroid(sp).x, CampusData.centroid(sp).y)
		# floor and ceiling
		var idx := CampusData.triangulate(sp)
		kc.mat = MeshKit.M_WOOD
		for t in range(0, idx.size(), 3):
			CampusBuilder._tri_up(kc, _v(sp[idx[t]], 0.02), _v(sp[idx[t + 1]], 0.02), _v(sp[idx[t + 2]], 0.02), floor_c)
		kc.cu_emission_last(idx.size(), 0.14)
		kc.mat = MeshKit.M_PLASTER
		for t in range(0, idx.size(), 3):
			A._tri_facing(kc, _v(sp[idx[t]], C), _v(sp[idx[t + 1]], C), _v(sp[idx[t + 2]], C), inner.darkened(0.1), Vector3.DOWN)
		kc.cu_emission_last(idx.size(), 0.18)
		# walls: plaster above a wainscot, open only at the doorway mouths
		var n := sp.size()
		for i in n:
			var a := sp[i]
			var b := sp[(i + 1) % n]
			var len := a.distance_to(b)
			if len < 0.05 or _mouth(a, b, doors):
				continue
			var dir := (b - a) / len
			var nin := Vector3(-dir.y, 0, dir.x)      # into the space (ccw)
			var kw := _k((a.x + b.x) * 0.5, (a.y + b.y) * 0.5)
			if brick:
				# an exposed-brick lounge (the reference's commons): brick to the
				# ceiling, a string of warm bulbs along the top of the wall
				kw.mat = MeshKit.M_BRICK
				_wall_quad(kw, a, b, 0.0, C, nin, Color(0.56, 0.31, 0.24), 0.16)
				kw.mat = 0.0
				var kb := _k((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, true)
				kb.mat = MeshKit.M_GLASS
				var nbulb := int(len / 0.9)
				for bi in nbulb:
					var q := a.lerp(b, (float(bi) + 0.5) / float(nbulb)) + Vector2(nin.x, nin.z) * 0.12
					var sag := 0.12 * sin(PI * fmod(float(bi) / 3.0, 1.0))
					kb.box(Vector3(q.x, C - 0.35 - sag, q.y), Vector3(0.07, 0.09, 0.07), Color(1.0, 0.8, 0.45), 0.0, 1.6)
				kb.mat = 0.0
			else:
				kw.mat = MeshKit.M_PLASTER
				_wall_quad(kw, a, b, 1.12, C, nin, inner, 0.22)
				kw.mat = MeshKit.M_WOOD
				_wall_quad(kw, a, b, 0.0, 1.12, nin, WOOD_DARK.lightened(0.1), 0.1)
				var off := Vector2(nin.x, nin.z) * 0.02
				_wall_quad(kw, a + off, b + off, 1.02, 1.12, nin, WOOD_DARK.lightened(0.25), 0.12)
				kw.mat = 0.0
			# the longest wall of the commons (for pictures and plants)
			var mid := (a + b) * 0.5
			if len > longest_len and CampusData.dist_to_edge(mid, room) < 0.3:
				longest_len = len
				longest = i
				longest_poly = sp
	# ceiling lights along each corridor, from the doorway to the commons
	for dr in doors:
		var lp0: Vector2 = dr["line_p"]
		var n_in: Vector2 = dr["n_in"]
		var dist := 2.0
		while dist < 60.0:
			var q := lp0 + n_in * dist
			if Geometry2D.is_point_in_polygon(q, room):
				break
			var kq := _k(q.x, q.y, true)
			kq.mat = MeshKit.M_GLASS
			kq.box(Vector3(q.x, C - 0.03, q.y), Vector3(0.5, 0.05, 0.5), Color(1.0, 0.86, 0.62), 0.0, 0.9)
			kq.mat = 0.0
			B.glow_disc(Vector3(q.x, 0.06, q.y), 1.8)
			dist += 4.5
	# beams across the room's short axis and pendant lights between them
	var obb := CampusArchitecture.obb_of(room)
	var ax: Vector2 = obb["axis"]
	var size: Vector2 = obb["size"]
	if size.y > size.x:
		ax = Vector2(-ax.y, ax.x)
		size = Vector2(size.y, size.x)
	var aw := Vector2(-ax.y, ax.x)
	var oc: Vector2 = obb["center"]
	var yaw := atan2(-ax.y, ax.x)
	var nb := maxi(1, int(size.x / 4.5))
	k.mat = MeshKit.M_WOOD
	for i in nb + 1:
		var bp := oc + ax * (-size.x * 0.5 + size.x * float(i) / float(nb))
		k.box(Vector3(bp.x, C - 0.06, bp.y), Vector3(0.3, 0.12, size.y), WOOD_DARK.lightened(0.3), yaw, 0.22)
	k.mat = 0.0
	for i in nb:
		var lp := oc + ax * (-size.x * 0.5 + size.x * (float(i) + 0.5) / float(nb))
		if not Geometry2D.is_point_in_polygon(lp, room):
			continue
		kd.mat = MeshKit.M_METAL
		kd.box(Vector3(lp.x, C - 0.3, lp.y), Vector3(0.03, 0.5, 0.03), IRON)
		kd.mat = MeshKit.M_GLASS
		kd.soft_blob(Vector3(lp.x, C - 0.68, lp.y), Vector3(0.28, 0.2, 0.28), Color(1.0, 0.82, 0.52), 3, 8, 0.0, 0.0, 0, 1.6)
		kd.mat = 0.0
		B.glow_disc(Vector3(lp.x, 0.06, lp.y), 3.0)
	# rugs along the long axis
	k.mat = MeshKit.M_PLAIN
	for rx: float in [-0.22, 0.22]:
		var rc := oc + ax * (size.x * rx)
		var rs := Vector2(minf(size.x * 0.26, 9.0), minf(4.2, size.y * 0.45))
		for layer in 2:
			var sh := 1.0 if layer == 0 else 0.8
			var y := 0.035 + 0.005 * float(layer)
			var hx := ax * (rs.x * 0.5 * sh)
			var hz := aw * (rs.y * 0.5 * (1.0 if layer == 0 else 0.76))
			A._quad_facing(k, _v(rc - hx - hz, y), _v(rc + hx - hz, y), _v(rc + hx + hz, y), _v(rc - hx + hz, y), fabric.darkened(0.45 if layer == 0 else 0.2), Vector3.UP)
			k.cu_emission_last(6, 0.1)
	k.mat = 0.0
	# furniture: the visuals of the colliders the data defines
	for bx in g["boxes"]:
		_furniture(k, bx, fabric, accent)
	# pictures and sconces on the longest closed wall, plants in its corners
	if longest >= 0:
		var lpn := longest_poly.size()
		var a2 := longest_poly[longest]
		var b2 := longest_poly[(longest + 1) % lpn]
		var dir2 := (b2 - a2).normalized()
		var nin2 := Vector2(-dir2.y, dir2.x)
		var wl := a2.distance_to(b2)
		var nfr := int(wl / 6.0)
		var wyaw := atan2(-dir2.y, dir2.x)
		for i in nfr:
			var q := a2 + dir2 * (wl * (float(i) + 0.5) / float(nfr)) + nin2 * 0.04
			kd.mat = MeshKit.M_WOOD
			kd.box(Vector3(q.x, 2.45, q.y), Vector3(1.1, 0.8, 0.05), WOOD_DARK, wyaw)
			kd.mat = MeshKit.M_PLAIN
			var q2 := q + nin2 * 0.03
			kd.box(Vector3(q2.x, 2.45, q2.y), Vector3(0.9, 0.6, 0.02), [Color(0.35, 0.5, 0.7), Color(0.7, 0.55, 0.35), Color(0.4, 0.6, 0.45)][i % 3], wyaw, 0.2)
			kd.mat = MeshKit.M_GLASS
			for sg: float in [-1.0, 1.0]:
				var s3 := q + dir2 * (0.95 * sg) + nin2 * 0.08
				kd.soft_blob(Vector3(s3.x, 2.9, s3.y), Vector3(0.1, 0.14, 0.08), Color(1.0, 0.8, 0.5), 3, 6, 0.0, 0.0, 0, 1.8)
			kd.mat = 0.0
		for corner in [a2 + dir2 * 0.55 + nin2 * 0.55, b2 - dir2 * 0.55 + nin2 * 0.55]:
			kd.mat = MeshKit.M_STONE
			kd.revolve(_v(corner, 0.0), PackedVector2Array([Vector2(0.22, 0.0), Vector2(0.3, 0.5), Vector2(0.32, 0.55)]), PackedColorArray([Color(0.62, 0.38, 0.28), Color(0.7, 0.42, 0.3), Color(0.74, 0.46, 0.32)]), 8)
			kd.mat = MeshKit.M_LEAF
			kd.soft_blob(_v(corner, 1.0), Vector3(0.45, 0.6, 0.45), Color(0.24, 0.46, 0.26), 4, 8, 0.0, 0.08, int(corner.x))
			kd.mat = 0.0


## One piece of furniture over its collider box [center, size, kind, yaw].
func _furniture(k: MeshKit, bx: Array, fabric: Color, accent: Color) -> void:
	var sc: Vector3 = bx[0]
	var ss: Vector3 = bx[1]
	var yaw := float(bx[3])
	var ax := Vector3(cos(yaw), 0, -sin(yaw))
	var az := Vector3(sin(yaw), 0, cos(yaw))
	var g := Vector3(sc.x, 0, sc.z)
	match String(bx[2]):
		"sofa":
			k.mat = MeshKit.M_PLAIN
			k.chamfer_box(g + Vector3(0, 0.24, 0), Vector3(ss.x, 0.48, ss.z), fabric.darkened(0.25), 0.1, yaw)
			k.chamfer_box(g + Vector3(0, 0.52, 0) - az * 0.05, Vector3(ss.x - 0.3, 0.16, ss.z - 0.25), fabric, 0.07, yaw)
			k.chamfer_box(g + Vector3(0, 0.78, 0) + az * (ss.z * 0.38), Vector3(ss.x, 0.62, 0.26), fabric.darkened(0.1), 0.1, yaw)
			for sgn: float in [-1.0, 1.0]:
				k.chamfer_box(g + ax * ((ss.x * 0.5 - 0.14) * sgn) + Vector3(0, 0.62, 0), Vector3(0.28, 0.4, ss.z), fabric.darkened(0.15), 0.08, yaw)
			var nc := maxi(1, int(ss.x / 1.6))
			for i in nc:
				var cx := -ss.x * 0.5 + (float(i) + 0.5) * ss.x / float(nc)
				k.chamfer_box(g + ax * cx + az * 0.2 + Vector3(0, 0.78, 0), Vector3(0.5, 0.4, 0.14), [Color(0.95, 0.86, 0.62), accent.lightened(0.15), fabric.lightened(0.3)][i % 3], 0.06, yaw)
		"table":
			k.mat = MeshKit.M_WOOD
			k.chamfer_box(g + Vector3(0, ss.y - 0.04, 0), Vector3(ss.x, 0.08, ss.z), WOOD_DARK.lightened(0.2), 0.03, yaw)
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					k.box(g + ax * ((ss.x * 0.5 - 0.1) * sx) + az * ((ss.z * 0.5 - 0.1) * sz) + Vector3(0, (ss.y - 0.08) * 0.5, 0), Vector3(0.08, ss.y - 0.08, 0.08), WOOD_DARK, yaw)
		"hearth":
			k.mat = MeshKit.M_STONE
			k.chamfer_box(g + Vector3(0, ss.y * 0.5, 0), ss, STONE.darkened(0.1), 0.06, yaw)
			k.chamfer_box(g + Vector3(0, ss.y + 0.07, 0), Vector3(ss.x + 0.4, 0.14, ss.z + 0.1), STONE.lightened(0.05), 0.04, yaw)
			k.mat = MeshKit.M_PLAIN
			var fc := g - az * (ss.z * 0.5 + 0.005)
			A._quad_facing(k, fc - ax * (ss.x * 0.27) + Vector3(0, 0.16, 0), fc + ax * (ss.x * 0.27) + Vector3(0, 0.16, 0), fc + ax * (ss.x * 0.27) + Vector3(0, ss.y * 0.73, 0), fc - ax * (ss.x * 0.27) + Vector3(0, ss.y * 0.73, 0), Color(0.08, 0.05, 0.04), -az)
			k.mat = 0.0
			k.soft_blob(fc - az * 0.05 + Vector3(0, 0.38, 0), Vector3(0.5, 0.26, 0.16), Color(1.0, 0.55, 0.18), 3, 8, 0.0, 0.0, 0, 2.2)
			k.soft_blob(fc - az * 0.05 + Vector3(0, 0.62, 0), Vector3(0.28, 0.22, 0.1), Color(1.0, 0.8, 0.3), 3, 8, 0.0, 0.0, 0, 2.6)
			var gp := g - az * (ss.z * 0.5 + 1.2)
			B.glow_disc(Vector3(gp.x, 0.06, gp.z), 3.4)
		"shelf":
			k.mat = MeshKit.M_WOOD
			k.chamfer_box(g + Vector3(0, ss.y * 0.5, 0), ss, WOOD_DARK.lightened(0.12), 0.03, yaw)
			k.mat = MeshKit.M_PLAIN
			var rows := maxi(1, int(ss.y / 0.45))
			for r in rows:
				var fy := 0.3 + float(r) * (ss.y - 0.4) / float(rows)
				k.box(g - az * (ss.z * 0.5 + 0.005) + Vector3(0, fy + 0.15, 0), Vector3(ss.x - 0.16, 0.3, 0.01), [Color(0.55, 0.25, 0.22), Color(0.25, 0.35, 0.5), Color(0.6, 0.5, 0.3)][r % 3], yaw, 0.1)
		_:
			pass
	k.mat = 0.0
