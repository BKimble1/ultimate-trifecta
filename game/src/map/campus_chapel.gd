class_name CampusChapel
extends RefCounted
## The prayer chapel: a faceted single-storey pavilion under one steep hip
## roof that rises from every facet of its outline to a glazed square
## cupola; glass walls between white columns on a brick base, a white
## entablature band, a few solid panels with plain bronze roundels, the
## pedimented portico from the data's entrances, and the walk-through
## atrium (the data's `passages`): open at both ends, brick walls with
## engaged white columns either side, brick pavers underfoot and a cedar
## ceiling with downlights at the passage's clear height.
##
## Collision stays generic (CampusBuilder: footprint minus passages, a slab
## over each passage from its clear height, portico columns), so the open
## atrium is walkable exactly where it is drawn open.  No inscription,
## cross or artwork is reproduced: the roundels and panels are plain.

const BRICK := Color(0.58, 0.30, 0.25)
const WHITE := Color(0.93, 0.92, 0.89)
const PANEL := Color(0.80, 0.78, 0.73)
const SHINGLE := Color(0.37, 0.35, 0.34)
const GLASS := Color(1.0, 0.80, 0.52)
const PAVER := Color(0.52, 0.29, 0.25)
const CEDAR := Color(0.64, 0.44, 0.28)
const BRONZE := Color(0.62, 0.46, 0.24)
const PITCH_DEG := 36.0
const EAVE := 0.8
const BASE_H := 0.95       # brick base under the glass
const BAND := 0.9          # entablature depth at the top of the wall
const COL_STEP := 2.6      # white columns along the glass walls


## The roof frame: the convex outline the roof follows, its centre, the
## eave height, inradius, the top ring's scale and the roof's top height.
static func frame(bd: Dictionary) -> Dictionary:
	var poly := CampusData.ccw(bd["poly"])
	var hull_raw := Geometry2D.convex_hull(poly)
	var hull := PackedVector2Array()
	for i in hull_raw.size() - 1:           # the hull repeats its first point
		hull.append(hull_raw[i])
	hull = CampusData.ccw(hull)
	var c := CampusData.centroid(hull)
	var r_in := INF
	for i in hull.size():
		r_in = minf(r_in, CampusData.dist_to_segment(c, hull[i], hull[(i + 1) % hull.size()]))
	r_in = maxf(r_in, 3.0)
	var wall_h := clampf(float(bd["h"]), 4.5, 8.0)
	var top_s := clampf(2.1 / r_in, 0.08, 0.4)
	var pitch := deg_to_rad(float((bd.get("roof", {}) as Dictionary).get("pitch", PITCH_DEG)))
	var rise := r_in * (1.0 - top_s) * tan(pitch)
	var obb := CampusArchitecture.obb_of(hull)
	return {"poly": poly, "hull": hull, "c": c, "r_in": r_in, "wall_h": wall_h, "top_s": top_s,
		"pitch": pitch, "top": wall_h + rise, "axis": obb["axis"]}


static func build(B: CampusBuilder, bd: Dictionary) -> void:
	var f := frame(bd)
	var c: Vector2 = f["c"]
	var k := B.kit_at(c.x, c.y)
	var kd := B.kit_at(c.x, c.y, false, true)
	var passages: Array = []
	for ps in bd["passages"]:
		passages.append(ps)
	_walls(k, kd, f, passages)
	_atrium(B, k, kd, f, passages)
	_roof(k, f)
	_cupola(k, kd, f)
	for e in bd["entrances"]:
		var p := CampusLayout._v2(e.get("p", [0, 0]))
		if _near_passage(p, passages, 1.2):
			if String(e.get("kind", "")) == "portico":
				var face := deg_to_rad(float(e.get("face", 0.0)))
				var n := Vector3(sin(face), 0, -cos(face))
				var rt := Vector3(-n.z, 0, n.x)
				B.arch.portico(k, Vector3(p.x, 0, p.y) + n * 0.06, n, rt, CampusArchitecture.portico_width(e), float(f["wall_h"]) - 0.4, WHITE)
			continue
		B.arch._entrance(bd, e, WHITE, [BRICK, MeshKit.M_BRICK])


static func _near_passage(p: Vector2, passages: Array, d: float) -> bool:
	for ps in passages:
		var poly: PackedVector2Array = ps["poly"]
		if Geometry2D.is_point_in_polygon(p, poly) or CampusData.dist_to_edge(p, poly) < d:
			return true
	return false


static func _in_passage(p: Vector2, passages: Array) -> bool:
	for ps in passages:
		if Geometry2D.is_point_in_polygon(p, ps["poly"]):
			return true
	return false


## Clear height of the passage containing `p` (or the eave height).
static func _clear_at(p: Vector2, passages: Array, wall_h: float) -> float:
	for ps in passages:
		if Geometry2D.is_point_in_polygon(p, ps["poly"]) or CampusData.dist_to_edge(p, ps["poly"]) < 0.3:
			return minf(float(ps["clear"]), wall_h - BAND)
	return wall_h - BAND


## The outer walls, edge by edge; where a passage meets the outline the wall
## opens (white portal columns either side, the band carried over).
static func _walls(k: MeshKit, kd: MeshKit, f: Dictionary, passages: Array) -> void:
	var poly: PackedVector2Array = f["poly"]
	var wall_h := float(f["wall_h"])
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var len := a.distance_to(b)
		if len < 0.3:
			continue
		var dir := (b - a) / len
		var out2 := Vector2(dir.y, -dir.x)
		# runs of closed / open wall along the edge
		var steps := maxi(2, int(len / 0.2))
		var runs: Array = []      # [t0, t1, open]
		var s0 := 0
		var prev := _in_passage(a + dir * (len * 0.5 / float(steps)) - out2 * 0.15, passages)
		for si in range(1, steps + 1):
			var o := prev
			if si < steps:
				o = _in_passage(a + dir * (len * (float(si) + 0.5) / float(steps)) - out2 * 0.15, passages)
			if si == steps or o != prev:
				runs.append([len * float(s0) / float(steps), len * float(si) / float(steps), prev])
				s0 = si
				prev = o
		for r in runs:
			var p0 := a + dir * float(r[0])
			var p1 := a + dir * float(r[1])
			if bool(r[2]):
				_opening(k, p0, p1, out2, wall_h, _clear_at((p0 + p1) * 0.5, passages, wall_h))
			else:
				_facade(k, kd, p0, p1, out2, wall_h, len)


## A closed stretch of wall: glass between white columns on a brick base
## (short facets get a solid panel with a bronze roundel instead).
static func _facade(k: MeshKit, kd: MeshKit, a: Vector2, b: Vector2, out2: Vector2, wall_h: float, edge_len: float) -> void:
	var len := a.distance_to(b)
	if len < 0.05:
		return
	var dir := (b - a) / len
	var out := Vector3(out2.x, 0, out2.y)
	var A := Vector3(a.x, 0, a.y)
	var Bv := Vector3(b.x, 0, b.y)
	var yaw := atan2(-dir.y, dir.x)
	var solid := edge_len < 5.0
	# brick base
	k.mat = MeshKit.M_BRICK
	_qf(k, A, Bv, Bv + Vector3(0, BASE_H, 0), A + Vector3(0, BASE_H, 0), BRICK, out)
	k.mat = MeshKit.M_STONE
	var cap := out * 0.06
	_qf(k, A + Vector3(0, BASE_H, 0) + cap, Bv + Vector3(0, BASE_H, 0) + cap, Bv + Vector3(0, BASE_H, 0) - out * 0.05, A + Vector3(0, BASE_H, 0) - out * 0.05, WHITE.darkened(0.08), Vector3.UP)
	var top := wall_h - BAND
	if solid:
		k.mat = MeshKit.M_PLASTER
		_qf(k, A + Vector3(0, BASE_H, 0), Bv + Vector3(0, BASE_H, 0), Bv + Vector3(0, top, 0), A + Vector3(0, top, 0), PANEL, out)
		var m := (a + b) * 0.5
		k.mat = MeshKit.M_METAL
		var rc := Vector3(m.x, top * 0.62, m.y) + out * 0.05
		var r := minf(0.42, len * 0.12)
		for sgi in 12:
			var a0 := TAU * float(sgi) / 12.0
			var a1 := TAU * float(sgi + 1) / 12.0
			var d0 := Vector3(dir.x, 0, dir.y) * cos(a0) * r + Vector3.UP * sin(a0) * r
			var d1 := Vector3(dir.x, 0, dir.y) * cos(a1) * r + Vector3.UP * sin(a1) * r
			_tf(k, rc, rc + d0, rc + d1, BRONZE.lightened(0.05 * sin(a0)), out)
	else:
		k.mat = MeshKit.M_GLASS
		_qf(k, A + Vector3(0, BASE_H, 0), Bv + Vector3(0, BASE_H, 0), Bv + Vector3(0, top, 0), A + Vector3(0, top, 0), GLASS.darkened(0.08), out)
		k.cu_emission_last(6, 0.5)
		# mullions and a transom (near-field detail)
		kd.mat = MeshKit.M_WOOD
		var nm := maxi(1, int(len / 0.9))
		for m2 in range(1, nm):
			var q := a + dir * (len * float(m2) / float(nm))
			kd.chamfer_box(Vector3(q.x, (BASE_H + top) * 0.5, q.y) + out * 0.04, Vector3(0.07, top - BASE_H, 0.08), WHITE, 0.01, yaw)
		var mid := (a + b) * 0.5
		kd.chamfer_box(Vector3(mid.x, BASE_H + (top - BASE_H) * 0.72, mid.y) + out * 0.04, Vector3(len, 0.1, 0.09), WHITE, 0.01, yaw)
		kd.mat = 0.0
	# white columns: at both ends and every COL_STEP
	k.mat = MeshKit.M_PLASTER
	var nc := maxi(1, int(round(len / COL_STEP)))
	for ci in nc + 1:
		var q2 := a + dir * (len * float(ci) / float(nc))
		var base := Vector3(q2.x, 0, q2.y) + out * 0.12
		k.revolve(base, PackedVector2Array([Vector2(0.24, 0.0), Vector2(0.24, 0.3), Vector2(0.19, 0.42), Vector2(0.18, top - 0.3), Vector2(0.23, top - 0.12), Vector2(0.25, top)]),
			PackedColorArray([WHITE.darkened(0.1), WHITE.darkened(0.06), WHITE, WHITE, WHITE.lightened(0.03), WHITE.lightened(0.05)]), 10)
	# entablature band
	k.mat = MeshKit.M_PLASTER
	var bo := out * 0.28
	_qf(k, A + Vector3(0, top, 0) + bo, Bv + Vector3(0, top, 0) + bo, Bv + Vector3(0, wall_h, 0) + bo, A + Vector3(0, wall_h, 0) + bo, WHITE, out)
	_qf(k, A + Vector3(0, top, 0), Bv + Vector3(0, top, 0), Bv + Vector3(0, top, 0) + bo, A + Vector3(0, top, 0) + bo, WHITE.darkened(0.3), Vector3.DOWN)
	_qf(k, A + Vector3(0, top + 0.18, 0) + bo * 1.15, Bv + Vector3(0, top + 0.18, 0) + bo * 1.15, Bv + Vector3(0, top + 0.3, 0) + bo * 1.15, A + Vector3(0, top + 0.3, 0) + bo * 1.15, WHITE.darkened(0.06), out)
	k.mat = 0.0


## An opening where a passage meets the outline: portal columns either side
## and the band (with a glazed transom up to it) carried over the opening.
static func _opening(k: MeshKit, a: Vector2, b: Vector2, out2: Vector2, wall_h: float, clear: float) -> void:
	var out := Vector3(out2.x, 0, out2.y)
	var A := Vector3(a.x, 0, a.y)
	var Bv := Vector3(b.x, 0, b.y)
	var top := wall_h - BAND
	k.mat = MeshKit.M_PLASTER
	for q in [A, Bv]:
		k.revolve(q + out * 0.2, PackedVector2Array([Vector2(0.3, 0.0), Vector2(0.3, 0.32), Vector2(0.24, 0.45), Vector2(0.22, clear - 0.3), Vector2(0.28, clear - 0.1), Vector2(0.31, clear)]),
			PackedColorArray([WHITE.darkened(0.1), WHITE.darkened(0.06), WHITE, WHITE, WHITE.lightened(0.03), WHITE.lightened(0.05)]), 12)
	# lintel between the clear height and the band
	if top > clear + 0.05:
		k.mat = MeshKit.M_GLASS
		_qf(k, A + Vector3(0, clear + 0.25, 0), Bv + Vector3(0, clear + 0.25, 0), Bv + Vector3(0, top, 0), A + Vector3(0, top, 0), GLASS, out)
		k.cu_emission_last(6, 0.4)
	k.mat = MeshKit.M_PLASTER
	_qf(k, A + Vector3(0, clear, 0), Bv + Vector3(0, clear, 0), Bv + Vector3(0, clear + 0.25, 0), A + Vector3(0, clear + 0.25, 0), WHITE, out)
	var bo := out * 0.28
	_qf(k, A + Vector3(0, top, 0) + bo, Bv + Vector3(0, top, 0) + bo, Bv + Vector3(0, wall_h, 0) + bo, A + Vector3(0, wall_h, 0) + bo, WHITE, out)
	_qf(k, A + Vector3(0, top, 0), Bv + Vector3(0, top, 0), Bv + Vector3(0, top, 0) + bo, A + Vector3(0, top, 0) + bo, WHITE.darkened(0.3), Vector3.DOWN)
	k.mat = 0.0


## The walk-through atrium: brick side walls with engaged columns, pavers,
## a cedar ceiling with downlights, a warm glow on the floor.
static func _atrium(B: CampusBuilder, k: MeshKit, kd: MeshKit, f: Dictionary, passages: Array) -> void:
	var poly: PackedVector2Array = f["poly"]
	var wall_h := float(f["wall_h"])
	for ps in passages:
		var pp: PackedVector2Array = CampusData.ccw(ps["poly"])
		var clear := minf(float(ps["clear"]), wall_h - BAND)
		var floor_y := float(ps.get("floor", 0.0)) + 0.085
		var idx := CampusData.triangulate(pp)
		# pavers and ceiling
		k.mat = MeshKit.M_PAVING
		for t in range(0, idx.size(), 3):
			CampusBuilder._tri_up(k, Vector3(pp[idx[t]].x, floor_y, pp[idx[t]].y), Vector3(pp[idx[t + 1]].x, floor_y, pp[idx[t + 1]].y), Vector3(pp[idx[t + 2]].x, floor_y, pp[idx[t + 2]].y), PAVER)
		k.mat = MeshKit.M_WOOD
		for t in range(0, idx.size(), 3):
			var a := Vector3(pp[idx[t]].x, clear, pp[idx[t]].y)
			var b := Vector3(pp[idx[t + 1]].x, clear, pp[idx[t + 1]].y)
			var c := Vector3(pp[idx[t + 2]].x, clear, pp[idx[t + 2]].y)
			_tf(k, a, b, c, CEDAR, Vector3.DOWN)
		k.mat = 0.0
		# side walls: passage edges that run inside the building
		var n := pp.size()
		for i in n:
			var a2 := pp[i]
			var b2 := pp[(i + 1) % n]
			var len := a2.distance_to(b2)
			if len < 0.3:
				continue
			var mid := (a2 + b2) * 0.5
			if CampusData.dist_to_edge(mid, poly) < 0.4 or not Geometry2D.is_point_in_polygon(mid, poly):
				continue      # an open end (on the outline) or outside
			var dir := (b2 - a2) / len
			var inward := Vector2(-dir.y, dir.x)     # into the passage (ccw)
			var nin := Vector3(inward.x, 0, inward.y)
			var A := Vector3(a2.x, 0, a2.y)
			var Bv := Vector3(b2.x, 0, b2.y)
			k.mat = MeshKit.M_BRICK
			_qf(k, A, Bv, Bv + Vector3(0, clear, 0), A + Vector3(0, clear, 0), BRICK.lightened(0.04), nin)
			k.mat = MeshKit.M_PLASTER
			var nc := maxi(1, int(round(len / 3.2)))
			for ci in nc + 1:
				var q := a2 + dir * (len * float(ci) / float(nc))
				k.chamfer_box(Vector3(q.x, clear * 0.5, q.y) + nin * 0.08, Vector3(0.42, clear, 0.16), WHITE, 0.04, atan2(-dir.y, dir.x))
			k.mat = 0.0
		# downlights in a row along the passage and their pools of light
		var obb := CampusArchitecture.obb_of(pp)
		var ax: Vector2 = obb["axis"]
		var size: Vector2 = obb["size"]
		if size.y > size.x:
			ax = Vector2(-ax.y, ax.x)
		var plen := maxf(size.x, size.y)
		var nl := maxi(1, int(plen / 3.0))
		for li in nl:
			var lp: Vector2 = (obb["center"] as Vector2) + ax * (plen * ((float(li) + 0.5) / float(nl) - 0.5))
			if not Geometry2D.is_point_in_polygon(lp, pp):
				continue
			kd.mat = MeshKit.M_GLASS
			kd.box(Vector3(lp.x, clear - 0.02, lp.y), Vector3(0.22, 0.03, 0.22), Color(1.0, 0.86, 0.62), 0.0, 1.0)
			kd.mat = 0.0
			B.glow_disc(Vector3(lp.x, floor_y + 0.01, lp.y), 1.6)


## The roof: one facet per side of the convex outline, from the eaves to a
## small top ring under the cupola; soffits under the eaves.
static func _roof(k: MeshKit, f: Dictionary) -> void:
	var hull: PackedVector2Array = f["hull"]
	var c: Vector2 = f["c"]
	var r_in := float(f["r_in"])
	var wall_h := float(f["wall_h"])
	var top := float(f["top"])
	var s := float(f["top_s"])
	var pitch := float(f["pitch"])
	var grow := 1.0 + EAVE / r_in
	var drop := EAVE * tan(pitch)
	var n := hull.size()
	k.mat = MeshKit.M_ROOF
	for i in n:
		var a := hull[i]
		var b := hull[(i + 1) % n]
		var ea := c + (a - c) * grow
		var eb := c + (b - c) * grow
		var ta := c + (a - c) * s
		var tb := c + (b - c) * s
		var mid := (a + b) * 0.5 - c
		var facing := (Vector3(mid.x, 0, mid.y).normalized() + Vector3.UP).normalized()
		var shade := SHINGLE.darkened(0.08 * (0.5 - 0.5 * mid.normalized().dot(Vector2(0.3, 0.95).normalized())))
		_qf(k, Vector3(ea.x, wall_h - drop, ea.y), Vector3(eb.x, wall_h - drop, eb.y), Vector3(tb.x, top, tb.y), Vector3(ta.x, top, ta.y), shade, facing)
		# soffit
		_qf(k, Vector3(a.x, wall_h, a.y), Vector3(b.x, wall_h, b.y), Vector3(eb.x, wall_h - drop, eb.y), Vector3(ea.x, wall_h - drop, ea.y), WHITE.darkened(0.35), Vector3.DOWN)
		# a hip cap along each hip line
		var hp := Vector3(ea.x, wall_h - drop, ea.y)
		var tp := Vector3(ta.x, top, ta.y)
		var hd := tp - hp
		var hm := (hp + tp) * 0.5
		var lb := Basis.looking_at(hd.normalized(), Vector3.UP)
		var xf := Transform3D(Basis(lb.x * 0.18, lb.y * 0.1, lb.z * hd.length()), hm + Vector3(0, 0.05, 0))
		k.box_xf(xf, SHINGLE.lightened(0.1))
	# fascia: a white edge along the eaves
	k.mat = MeshKit.M_PLASTER
	for i in n:
		var a2 := c + (hull[i] - c) * grow
		var b2 := c + (hull[(i + 1) % n] - c) * grow
		var m2 := (a2 + b2) * 0.5 - c
		var fo := Vector3(m2.x, 0, m2.y).normalized()
		_qf(k, Vector3(a2.x, wall_h - drop, a2.y), Vector3(b2.x, wall_h - drop, b2.y), Vector3(b2.x, wall_h - drop - 0.22, b2.y), Vector3(a2.x, wall_h - drop - 0.22, a2.y), WHITE, fo)
	# the cap of the top ring (under the cupola)
	k.mat = MeshKit.M_ROOF
	for i in n:
		var ta2 := c + (hull[i] - c) * s
		var tb2 := c + (hull[(i + 1) % n] - c) * s
		CampusBuilder._tri_up(k, Vector3(c.x, top, c.y), Vector3(ta2.x, top, ta2.y), Vector3(tb2.x, top, tb2.y), SHINGLE)
	k.mat = 0.0


## The cupola: a white square base, a glazed lantern lit from inside, a
## cornice, a small pyramid roof and a plain finial.
static func _cupola(k: MeshKit, kd: MeshKit, f: Dictionary) -> void:
	var c: Vector2 = f["c"]
	var top := float(f["top"])
	var ax: Vector2 = f["axis"]
	var yaw := atan2(-ax.y, ax.x)
	var cs := clampf(float(f["r_in"]) * float(f["top_s"]) * 1.45, 2.4, 4.0)
	var y0 := top - 0.3
	k.mat = MeshKit.M_PLASTER
	k.chamfer_box(Vector3(c.x, y0 + 0.65, c.y), Vector3(cs, 1.3, cs), WHITE, 0.05, yaw)
	# glazed lantern
	var gy0 := y0 + 1.3
	var gh := 2.1
	var ax3 := Vector3(ax.x, 0, ax.y)
	var aw3 := Vector3(-ax.y, 0, ax.x)
	k.mat = MeshKit.M_GLASS
	for side in [[ax3, aw3], [-ax3, aw3], [aw3, ax3], [-aw3, ax3]]:
		var nrm: Vector3 = side[0]
		var along: Vector3 = side[1]
		var fc := Vector3(c.x, gy0, c.y) + nrm * (cs * 0.5 - 0.12)
		_qf(k, fc - along * (cs * 0.5 - 0.15), fc + along * (cs * 0.5 - 0.15), fc + along * (cs * 0.5 - 0.15) + Vector3(0, gh, 0), fc - along * (cs * 0.5 - 0.15) + Vector3(0, gh, 0), GLASS, nrm)
		k.cu_emission_last(6, 0.75)
	k.mat = MeshKit.M_PLASTER
	for su: float in [-0.5, 0.5]:
		for sv: float in [-0.5, 0.5]:
			var q := Vector3(c.x, gy0 + gh * 0.5, c.y) + ax3 * (cs * su) + aw3 * (cs * sv)
			k.chamfer_box(q - ax3 * (0.11 * signf(su)) - aw3 * (0.11 * signf(sv)), Vector3(0.24, gh, 0.24), WHITE, 0.03, yaw)
	# muntins: a 3 x 2 grid on every side (detail)
	kd.mat = MeshKit.M_WOOD
	for side2 in [[ax3, aw3], [-ax3, aw3], [aw3, ax3], [-aw3, ax3]]:
		var nrm2: Vector3 = side2[0]
		var along2: Vector3 = side2[1]
		var fc2 := Vector3(c.x, gy0, c.y) + nrm2 * (cs * 0.5 - 0.1)
		var y_ := atan2(-along2.z, along2.x)
		for m in [-1.0 / 6.0, 1.0 / 6.0]:
			kd.chamfer_box(fc2 + along2 * ((cs - 0.3) * float(m) * 1.5) + Vector3(0, gh * 0.5, 0), Vector3(0.06, gh, 0.06), WHITE, 0.01, y_)
		kd.chamfer_box(fc2 + Vector3(0, gh * 0.5, 0), Vector3(cs - 0.3, 0.06, 0.06), WHITE, 0.01, y_)
	kd.mat = 0.0
	# cornice and roof
	var ry := gy0 + gh
	k.mat = MeshKit.M_PLASTER
	k.chamfer_box(Vector3(c.x, ry + 0.2, c.y), Vector3(cs + 0.5, 0.4, cs + 0.5), WHITE, 0.05, yaw)
	k.mat = MeshKit.M_ROOF
	var apex := Vector3(c.x, ry + 0.4 + cs * 0.42, c.y)
	var hs := cs * 0.5 + 0.3
	var corners := []
	for s in [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]:
		corners.append(Vector3(c.x, ry + 0.4, c.y) + ax3 * (hs * float(s[0])) + aw3 * (hs * float(s[1])))
	for i in 4:
		var e0: Vector3 = corners[i]
		var e1: Vector3 = corners[(i + 1) % 4]
		var mo := ((e0 + e1) * 0.5 - Vector3(c.x, ry + 0.4, c.y)).normalized()
		_tf(k, e0, e1, apex, SHINGLE.darkened(0.04 * float(i % 2)), (mo + Vector3.UP).normalized())
	k.mat = MeshKit.M_METAL
	k.revolve(apex - Vector3(0, 0.05, 0), PackedVector2Array([Vector2(0.09, 0.0), Vector2(0.09, 0.35), Vector2(0.16, 0.45), Vector2(0.09, 0.6), Vector2(0.03, 1.1)]),
		PackedColorArray([BRONZE.darkened(0.2), BRONZE.darkened(0.1), BRONZE, BRONZE.darkened(0.1), BRONZE.lightened(0.1)]), 8)
	k.mat = 0.0


static func _qf(k: MeshKit, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, facing: Vector3) -> void:
	if ((b - a).cross(c - a)).dot(facing) < 0.0:
		k.quad(a, b, c, d, col)
	else:
		k.quad(d, c, b, a, col)


static func _tf(k: MeshKit, a: Vector3, b: Vector3, c: Vector3, col: Color, facing: Vector3) -> void:
	if ((b - a).cross(c - a)).dot(facing) < 0.0:
		k.tri(a, b, c, col)
	else:
		k.tri(a, c, b, col)
