class_name CampusTower
extends RefCounted
## The bell tower: six slender brick piers in two staggered columns that
## step down from the back to the front, a bell assembly hung in the open
## gap between the two tallest piers, tie beams across the gap high up, and
## an open walk-through between the columns at ground level.  Each pier has
## a stone base course, a deep vertical slot and a projecting stone cap.
##
## The layout comes from the traced footprint: its oriented bounding box
## gives the axis and the size, the first entrance's facing (or south) says
## which end is the front (the low piers).  `solids()` is the single source
## of the collision (CampusBuilder uses it), so what is drawn is what
## blocks; the gap stays open from the ground to the lowest tie beam.

const BRICK := Color(0.60, 0.31, 0.24)
const CAP := Color(0.80, 0.76, 0.70)
const SLOT := Color(0.09, 0.08, 0.10)
const IRON := Color(0.20, 0.21, 0.24)
const BRONZE := Color(0.58, 0.44, 0.24)
const PLAQUE := Color(0.46, 0.36, 0.22)

## Fractions of the tower height for the six piers: [row, side, height].
## Rows: 0 front, 1 middle, 2 back; sides: -1 left, +1 right (looking from
## the front).  The two columns step down unevenly, as the real one does.
const PIERS := [[2, -1, 1.0], [2, 1, 0.97], [1, -1, 0.70], [1, 1, 0.62], [0, -1, 0.40], [0, 1, 0.30]]
const MIN_GAP := 2.0       # clear width of the walk-through between the columns


## The frame of the tower: centre, unit axis toward the back, unit axis to
## the right, length (front to back), width, gap and height.
static func frame(bd: Dictionary) -> Dictionary:
	var ps_list: Array = bd.get("passages", [])
	if not ps_list.is_empty() and not (bd.get("parts", []) as Array).is_empty():
		# traced: the walk-through gap between the piers sets the axis
		var gobb := CampusArchitecture.obb_of(ps_list[0]["poly"])
		var gs: Vector2 = gobb["size"]
		var gax: Vector2 = gobb["axis"]
		var along := gax if gs.x >= gs.y else Vector2(-gax.y, gax.x)
		var face2 := Vector2(0, 1)
		var bk := -along if along.dot(face2) > 0.0 else along
		var top := 0.0
		for pt in bd["parts"]:
			top = maxf(top, float(pt["h"]))
		return {"c": gobb["center"], "back": bk, "right": Vector2(-bk.y, bk.x), "len": maxf(gs.x, gs.y),
			"w": minf(gs.x, gs.y) + 4.0, "gap": minf(gs.x, gs.y), "h": top, "traced": true}
	var obb := CampusArchitecture.obb_of(bd["poly"])
	var size: Vector2 = obb["size"]
	var ax: Vector2 = obb["axis"]
	var aw := Vector2(-ax.y, ax.x)
	var long_ax := ax if size.x >= size.y else aw
	var length := clampf(maxf(size.x, size.y), 5.0, 10.0)
	var width := clampf(minf(size.x, size.y), 4.6, 9.0)
	# the front (low piers) faces the first entrance, or south
	var face := Vector2(0, 1)
	var ents: Array = bd.get("entrances", [])
	if not ents.is_empty():
		var fd := deg_to_rad(float(ents[0].get("face", 180.0)))
		face = Vector2(sin(fd), -cos(fd))
	var back := -long_ax if long_ax.dot(face) > 0.0 else long_ax
	var right := Vector2(-back.y, back.x)
	var gap := clampf(width * 0.32, MIN_GAP, 2.6)
	return {"c": obb["center"], "back": back, "right": right, "len": length, "w": width,
		"gap": gap, "h": clampf(float(bd["h"]), 12.0, 40.0)}


## Every solid of the tower: [{poly, base, h}].  Piers (with their base
## course), tie beams across the gap, the bell assembly's footprint and the
## plaque plinth beside the walk-through.
static func solids(bd: Dictionary) -> Array:
	var f := frame(bd)
	var out: Array = []
	if bool(f.get("traced", false)):
		for pt in bd["parts"]:
			out.append({"poly": pt["poly"], "base": float(pt.get("base", 0.0)), "h": float(pt["h"]), "kind": "pier" if float(pt.get("base", 0.0)) < 1.0 else "bells"})
		var ff := {"c": plinth_center(f), "back": f["back"], "right": f["right"]}
		out.append({"poly": _rect(ff, 0.0, 0.0, 0.7, 1.1), "base": 0.0, "h": 1.05, "kind": "plinth"})
		return out
	for p in PIERS:
		var q := _pier_rect(f, int(p[0]), int(p[1]))
		out.append({"poly": _rect(f, q[0], q[1], q[2] + 0.1, q[3] + 0.1), "base": 0.0, "h": float(f["h"]) * float(p[2]), "kind": "pier"})
	var h := float(f["h"])
	for y in _beam_heights(h):
		out.append({"poly": _rect(f, float(f["len"]) / 3.0, 0.0, float(f["len"]) / 3.0, float(f["gap"]) + 0.2), "base": y, "h": y + 0.55, "kind": "beam"})
	out.append({"poly": _rect({"c": plinth_center(f), "back": f["back"], "right": f["right"]}, 0.0, 0.0, 0.7, 1.1), "base": 0.0, "h": 1.05, "kind": "plinth"})
	return out


## The plaque plinth stands in front of the pier beside the walk-through,
## clear of the gap's axis (the way through stays straight and open).
static func plinth_center(f: Dictionary) -> Vector2:
	var right: Vector2 = f.get("right", Vector2(-(f["back"] as Vector2).y, (f["back"] as Vector2).x))
	var gap := float(f.get("gap", MIN_GAP))
	return (f["c"] as Vector2) - (f["back"] as Vector2) * (float(f["len"]) * 0.5 + 1.5) + right * (gap * 0.5 + 1.2)


static func _beam_heights(h: float) -> PackedFloat32Array:
	return PackedFloat32Array([h * 0.36, h * 0.56])


## A pier's centre (u along back, v along right) and size (du, dv).
static func _pier_rect(f: Dictionary, row: int, side: int) -> Array:
	var length := float(f["len"])
	var width := float(f["w"])
	var gap := float(f["gap"])
	var du := length / 3.0 * 0.96
	var dv := (width - gap) * 0.5
	var u := (float(row) - 1.0) * length / 3.0
	# the columns are staggered: the middle row sits a little further out,
	# the front row a little further in
	var stagger: float = [-0.18, 0.22, 0.0][row]
	var v := float(side) * (gap * 0.5 + dv * 0.5 + stagger)
	return [u, v, du, dv]


static func _rect(f: Dictionary, u: float, v: float, du: float, dv: float) -> PackedVector2Array:
	var c: Vector2 = f["c"]
	var b: Vector2 = f["back"]
	var r: Vector2 = f["right"]
	var o := c + b * u + r * v
	var hu := b * (du * 0.5)
	var hv := r * (dv * 0.5)
	return CampusData.ccw(PackedVector2Array([o - hu - hv, o + hu - hv, o + hu + hv, o - hu + hv]))


static func build(B: CampusBuilder, bd: Dictionary) -> void:
	var f := frame(bd)
	if bool(f.get("traced", false)):
		_build_traced(B, bd, f)
		return
	var c: Vector2 = f["c"]
	var k := B.kit_at(c.x, c.y)
	var kd := B.kit_at(c.x, c.y, false, true)
	var h := float(f["h"])
	var back: Vector2 = f["back"]
	var right: Vector2 = f["right"]
	var yaw := atan2(-back.y, back.x)
	for p in PIERS:
		var q := _pier_rect(f, int(p[0]), int(p[1]))
		var ph := h * float(p[2])
		_pier(k, kd, f, q, ph, yaw, int(p[1]))
	# tie beams across the gap, between the middle and back rows
	k.mat = MeshKit.M_BRICK
	for y in _beam_heights(h):
		var o := c + back * (float(f["len"]) / 3.0)
		k.chamfer_box(Vector3(o.x, y + 0.275, o.y), Vector3(float(f["len"]) / 3.0, 0.55, float(f["gap"]) + 0.2), BRICK.darkened(0.05), 0.04, yaw, CAP)
	k.mat = 0.0
	_bells(k, f, yaw)
	_plinth(k, kd, f, yaw)
	# up-lights at the foot of every pier, aimed at the brick
	for p in PIERS:
		var q2 := _pier_rect(f, int(p[0]), int(p[1]))
		var o2 := c + back * float(q2[0]) + right * float(q2[1])
		var outward := right * signf(float(p[1]))
		var lp := o2 + outward * (float(q2[3]) * 0.5 + 0.45)
		kd.mat = MeshKit.M_METAL
		kd.chamfer_box(Vector3(lp.x, 0.1, lp.y), Vector3(0.28, 0.2, 0.28), IRON, 0.03, yaw)
		kd.mat = MeshKit.M_GLASS
		kd.box(Vector3(lp.x, 0.21, lp.y), Vector3(0.18, 0.03, 0.18), Color(1.0, 0.86, 0.62), yaw, 1.0)
		kd.mat = 0.0
		B.glow_disc(Vector3(lp.x, 0.05, lp.y), 1.4)


## The traced tower: each pier part a brick shaft (base course, slots, a
## stone cap), the raised part the bell frame with its bells, the plaque
## plinth beside the gap, up-lights at the piers' feet.
static func _build_traced(B: CampusBuilder, bd: Dictionary, f: Dictionary) -> void:
	var c: Vector2 = f["c"]
	var k := B.kit_at(c.x, c.y)
	var kd := B.kit_at(c.x, c.y, false, true)
	var back: Vector2 = f["back"]
	var yaw := atan2(-back.y, back.x)
	for pt in bd["parts"]:
		var obb := CampusArchitecture.obb_of(pt["poly"])
		var oc: Vector2 = obb["center"]
		var sz: Vector2 = obb["size"]
		var ax: Vector2 = obb["axis"]
		# the part's size along the tower's own axes
		var du := absf(ax.dot(back)) * sz.x + absf(Vector2(-ax.y, ax.x).dot(back)) * sz.y
		var dv := absf(ax.dot(f["right"])) * sz.x + absf(Vector2(-ax.y, ax.x).dot(f["right"])) * sz.y
		var base := float(pt.get("base", 0.0))
		var h := float(pt["h"])
		if base < 1.0:
			var side := 1 if (oc - c).dot(f["right"]) >= 0.0 else -1
			var q := [(oc - c).dot(back), (oc - c).dot(f["right"]), du, dv]
			_pier(k, kd, f, q, h, yaw, side)
		else:
			_bells_at(k, oc, back, f["right"], du, dv, base, h, yaw)
	_plinth(k, kd, f, yaw)
	for pt2 in bd["parts"]:
		if float(pt2.get("base", 0.0)) >= 1.0:
			continue
		var o2 := CampusData.centroid(pt2["poly"])
		var outward := (o2 - c).normalized()
		var lp := o2 + outward * 1.6
		kd.mat = MeshKit.M_METAL
		kd.chamfer_box(Vector3(lp.x, 0.1, lp.y), Vector3(0.28, 0.2, 0.28), IRON, 0.03, yaw)
		kd.mat = MeshKit.M_GLASS
		kd.box(Vector3(lp.x, 0.21, lp.y), Vector3(0.18, 0.03, 0.18), Color(1.0, 0.86, 0.62), yaw, 1.0)
		kd.mat = 0.0
		B.glow_disc(Vector3(lp.x, 0.05, lp.y), 1.4)


## An open iron bell frame filling the box (centre o, axes back/right,
## sizes du x dv) from y0 to y1, with graded bells hung inside.
static func _bells_at(k: MeshKit, o: Vector2, back: Vector2, right: Vector2, du: float, dv: float, y0: float, y1: float, yaw: float) -> void:
	k.mat = MeshKit.M_METAL
	for su: float in [-0.5, 0.5]:
		for sv: float in [-0.5, 0.5]:
			var p := o + back * (du * su * 0.9) + right * (dv * sv * 0.9)
			k.chamfer_box(Vector3(p.x, (y0 + y1) * 0.5, p.y), Vector3(0.14, y1 - y0, 0.14), IRON, 0.02, yaw)
	for t: float in [0.0, 0.5, 1.0]:
		var y := lerpf(y0, y1, t)
		k.chamfer_box(Vector3(o.x, y, o.y), Vector3(du * 0.92, 0.12, dv * 0.92), IRON, 0.02, yaw)
	var sizes := [0.5, 0.4, 0.32]
	for i in sizes.size():
		var r := float(sizes[i])
		var p3 := o + back * (du * ((float(i) + 0.5) / float(sizes.size()) - 0.5) * 0.6)
		var top := lerpf(y0, y1, 0.5) - 0.1
		var hb := r * 1.5
		k.revolve(Vector3(p3.x, top - hb, p3.y), PackedVector2Array([Vector2(r, 0.0), Vector2(r * 0.86, hb * 0.18), Vector2(r * 0.62, hb * 0.55), Vector2(r * 0.5, hb * 0.9), Vector2(0.1, hb)]),
			PackedColorArray([BRONZE.lightened(0.1), BRONZE, BRONZE.darkened(0.1), BRONZE.darkened(0.15), BRONZE.darkened(0.2)]), 12)
	# a louvred cap over the frame
	k.chamfer_box(Vector3(o.x, y1 + 0.15, o.y), Vector3(du + 0.2, 0.3, dv + 0.2), IRON.lightened(0.1), 0.04, yaw)
	k.mat = 0.0


## One pier: a base course, the brick shaft (warm up-lit at its foot), a
## deep vertical slot on the outer face and the inner face, and a stone cap.
static func _pier(k: MeshKit, kd: MeshKit, f: Dictionary, q: Array, ph: float, yaw: float, side: int) -> void:
	var c: Vector2 = f["c"]
	var back: Vector2 = f["back"]
	var right: Vector2 = f["right"]
	var o := c + back * float(q[0]) + right * float(q[1])
	var du := float(q[2])
	var dv := float(q[3])
	k.mat = MeshKit.M_STONE
	k.chamfer_box(Vector3(o.x, 0.3, o.y), Vector3(du + 0.12, 0.6, dv + 0.12), CAP.darkened(0.12), 0.04, yaw)
	k.mat = MeshKit.M_BRICK
	k.chamfer_box(Vector3(o.x, 0.6 + (ph - 0.6) * 0.5, o.y), Vector3(du, ph - 0.6, dv), BRICK, 0.05, yaw)
	k.mat = MeshKit.M_STONE
	k.chamfer_box(Vector3(o.x, ph + 0.12, o.y), Vector3(du + 0.16, 0.24, dv + 0.16), CAP, 0.04, yaw)
	k.mat = 0.0
	# slots: on the outer face (facing away from the gap) and the front face
	var slot_h := clampf(ph * 0.16, 1.4, 3.2)
	var y0 := ph * 0.58
	var outward := right * float(side)
	for face in [[outward, dv * 0.5, back], [-back, du * 0.5, right]]:
		var n2: Vector2 = face[0]
		var half := float(face[1])
		var along: Vector2 = face[2]
		var fc := o + n2 * (half + 0.01)
		var n3 := Vector3(n2.x, 0, n2.y)
		var a3 := Vector3(along.x, 0, along.y) * 0.2
		var base := Vector3(fc.x, y0, fc.y)
		kd.mat = MeshKit.M_PLAIN
		_quad_facing(kd, base - a3, base + a3, base + a3 + Vector3(0, slot_h, 0), base - a3 + Vector3(0, slot_h, 0), SLOT, n3)
		kd.mat = MeshKit.M_STONE
		kd.chamfer_box(base + n3 * 0.04 - Vector3(0, 0.08, 0), Vector3(0.56, 0.12, 0.56), CAP, 0.02, yaw)
		kd.mat = 0.0


## The bell assembly: an open iron frame hung between the two back piers
## near their tops, with a few bells of graded sizes.
static func _bells(k: MeshKit, f: Dictionary, yaw: float) -> void:
	var c: Vector2 = f["c"]
	var back: Vector2 = f["back"]
	var right: Vector2 = f["right"]
	var h := float(f["h"])
	var o := c + back * (float(f["len"]) / 3.0)
	var gw := float(f["gap"]) - 0.1
	var dl := float(f["len"]) / 3.0 * 0.8
	var y0 := h * 0.70
	var y1 := h * 0.93
	k.mat = MeshKit.M_METAL
	# corner posts and three horizontal rings
	for su: float in [-0.5, 0.5]:
		for sv: float in [-0.5, 0.5]:
			var p := o + back * (dl * su) + right * (gw * sv)
			k.chamfer_box(Vector3(p.x, (y0 + y1) * 0.5, p.y), Vector3(0.14, y1 - y0, 0.14), IRON, 0.02, yaw)
	for t: float in [0.0, 0.45, 1.0]:
		var y := lerpf(y0, y1, t)
		for sv: float in [-0.5, 0.5]:
			var p := o + right * (gw * sv)
			k.chamfer_box(Vector3(p.x, y, p.y), Vector3(dl + 0.14, 0.12, 0.12), IRON, 0.02, yaw)
		for su: float in [-0.5, 0.5]:
			var p2 := o + back * (dl * su)
			k.chamfer_box(Vector3(p2.x, y, p2.y), Vector3(0.12, 0.12, gw + 0.14), IRON, 0.02, yaw)
	# diagonal braces on the two open sides read as a lattice from below
	for sv: float in [-0.5, 0.5]:
		var a := o + right * (gw * sv) - back * (dl * 0.5)
		var b := o + right * (gw * sv) + back * (dl * 0.5)
		var m := (a + b) * 0.5
		var span := Vector2(dl, (y1 - y0) * 0.45)
		var ang := atan2(span.y, span.x)
		var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3(0, 0, 1), ang), Vector3(m.x, lerpf(y0, y1, 0.225), m.y))
		k.box_xf(xf.scaled_local(Vector3(span.length(), 0.08, 0.08)), IRON)
	# the bells: graded, hung from the middle ring
	var sizes := [0.62, 0.5, 0.42, 0.34]
	for i in sizes.size():
		var r := float(sizes[i])
		var t2 := (float(i) + 0.5) / float(sizes.size()) - 0.5
		var p3 := o + back * (dl * t2 * 0.9)
		var top := lerpf(y0, y1, 0.45) - 0.1
		var hb := r * 1.5
		k.revolve(Vector3(p3.x, top - hb, p3.y), PackedVector2Array([Vector2(r, 0.0), Vector2(r * 0.86, hb * 0.18), Vector2(r * 0.62, hb * 0.55), Vector2(r * 0.5, hb * 0.9), Vector2(0.1, hb)]),
			PackedColorArray([BRONZE.lightened(0.1), BRONZE, BRONZE.darkened(0.1), BRONZE.darkened(0.15), BRONZE.darkened(0.2)]), 12)
		k.chamfer_box(Vector3(p3.x, top - 0.02, p3.y), Vector3(0.1, 0.2, 0.1), IRON, 0.02, yaw)
	k.mat = 0.0


## A low plinth beside the walk-through with a blank bronze panel (no
## inscription is reproduced).
static func _plinth(k: MeshKit, kd: MeshKit, f: Dictionary, yaw: float) -> void:
	var c: Vector2 = f["c"]
	var back: Vector2 = f["back"]
	var o := plinth_center(f)
	k.mat = MeshKit.M_BRICK
	k.chamfer_box(Vector3(o.x, 0.48, o.y), Vector3(1.1, 0.96, 0.7), BRICK.darkened(0.04), 0.04, yaw + PI * 0.5, CAP)
	k.mat = MeshKit.M_STONE
	k.chamfer_box(Vector3(o.x, 1.0, o.y), Vector3(1.2, 0.1, 0.8), CAP, 0.03, yaw + PI * 0.5)
	kd.mat = MeshKit.M_METAL
	var fc := o - back * 0.36
	var n3 := Vector3(-back.x, 0, -back.y)
	var r3 := Vector3(back.y, 0, -back.x) * 0.36
	var b3 := Vector3(fc.x, 0.36, fc.y)
	_quad_facing(kd, b3 - r3, b3 + r3, b3 + r3 + Vector3(0, 0.44, 0), b3 - r3 + Vector3(0, 0.44, 0), PLAQUE, n3)
	kd.mat = 0.0


static func _quad_facing(k: MeshKit, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, facing: Vector3) -> void:
	if ((b - a).cross(c - a)).dot(facing) < 0.0:
		k.quad(a, b, c, d, col)
	else:
		k.quad(d, c, b, a, col)
