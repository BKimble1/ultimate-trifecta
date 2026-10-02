class_name DormArt
extends RefCounted
## The look of the three V6 dorms (CampusDorms), built with the campus kit:
## the same MeshKit chunks, world shader and material ids as every other
## building (no new materials, textures or lights).  Visual only: the
## colliders come from CampusDorms.geometry via CampusBuilder.build_collision,
## and every surface here follows them (no door leaves, posts or furniture
## standing where a runner can walk unless a collider already does).
##
##   shell      outer facades with real openings, the common room's inner
##              walls, floor and ceiling, door reveals, plinth, cornice,
##              quoins, string course, roof (per style: brick gable with
##              chimneys, a teal hip-ish gable with a glowing lantern
##              cupola, a lodge gable facing the front)
##   windows    lit windows on the facades between the openings, night
##              glass on the room's inner walls
##   entrances  stone surrounds, lit transoms, porch hoods on brackets,
##              lanterns, flush thresholds, house banners
##   interior   warm plaster, wainscot, plank floor, rugs, beams, pendant
##              lights, fireplace, sofas, noticeboard, pigeonholes, plants
##   yard       monument name signs, planters
## Warmth inside comes from per-vertex emission (as the lit windows do) and
## the light field's warm channel stamped over the room (CampusKit).

var B: CampusBuilder
var A: CampusArchitecture
var L: CampusLayout

const STONE := Color(0.74, 0.72, 0.70)
const TRIM := Color(0.90, 0.88, 0.84)
const IRON := Color(0.17, 0.19, 0.25)
const WOOD_DARK := Color(0.36, 0.23, 0.16)


func _init(builder: CampusBuilder, arch: CampusArchitecture) -> void:
	B = builder
	A = arch
	L = builder.L


func _k(x: float, z: float, detail: bool = false) -> MeshKit:
	return B._kit_at(x, z, false, detail)


static func _v(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


## A vertical quad over the ground segment a-b from y0 to y1, facing `facing`.
func _wall_quad(k: MeshKit, a: Vector2, b: Vector2, y0: float, y1: float, facing: Vector3, col: Color, emis: float = 0.0) -> void:
	A._quad_facing(k, _v(a, y0), _v(b, y0), _v(b, y1), _v(a, y1), col, facing)
	if emis > 0.0:
		k.cu_emission_last(6, emis)


## A wall face along a->b with door openings ([centre distance from a,
## half width]) cut from 0 to door_h; full height elsewhere.
func _face_with_holes(k: MeshKit, a: Vector2, b: Vector2, y_top: float, holes: Array, door_h: float, facing: Vector3, col: Color, emis: float = 0.0) -> void:
	var dir := (b - a).normalized()
	var length := a.distance_to(b)
	var cuts: Array = []
	for hl in holes:
		cuts.append([float(hl[0]) - float(hl[1]), float(hl[0]) + float(hl[1])])
	cuts.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	var t := 0.0
	for c in cuts:
		if float(c[0]) > t + 0.001:
			_wall_quad(k, a + dir * t, a + dir * float(c[0]), 0.0, y_top, facing, col, emis)
		_wall_quad(k, a + dir * float(c[0]), a + dir * float(c[1]), door_h, y_top, facing, col, emis)
		t = float(c[1])
	if t < length - 0.001:
		_wall_quad(k, a + dir * t, b, 0.0, y_top, facing, col, emis)


func _wall_mat(d: Dictionary) -> float:
	match String(d["style"]):
		"brick":
			return MeshKit.M_BRICK
		"lodge":
			return MeshKit.M_WOOD
	return MeshKit.M_PLASTER


# ---------------------------------------------------------------------------
# Shell
# ---------------------------------------------------------------------------
func shell(bd: Dictionary) -> void:
	var id := String(bd["dorm_id"])
	var d := CampusDorms.def(id)
	var g := CampusDorms.geometry(id)
	var fp: Rect2 = g["footprint"]
	var room: Rect2 = g["room"]
	var h: float = d["h"]
	var T := CampusDorms.WALL_T
	var hw := CampusDorms.DOOR_W * 0.5
	var DH := CampusDorms.DOOR_H
	var C := CampusDorms.CEIL
	var wall: Color = d["wall"]
	var k := _k(fp.get_center().x, fp.get_center().y)
	var xw := fp.position.x
	var xe := fp.end.x
	var zf := fp.position.y
	var zb := fp.end.y
	var doors: Array = g["doors"]
	var front: Dictionary = doors[0]
	var side_z: float = (doors[1]["pos"] as Vector2).y
	var cx: float = (front["pos"] as Vector2).x
	# --- outer facades (with the openings)
	k.mat = _wall_mat(d)
	_face_with_holes(k, Vector2(xw, zf), Vector2(xe, zf), h, [[cx - xw, hw]], DH, Vector3(0, 0, -1), wall)
	_face_with_holes(k, Vector2(xw, zb), Vector2(xw, zf), h, [[zb - side_z, hw]], DH, Vector3(-1, 0, 0), wall.darkened(0.06))
	_face_with_holes(k, Vector2(xe, zf), Vector2(xe, zb), h, [[side_z - zf, hw]], DH, Vector3(1, 0, 0), wall.darkened(0.06))
	_wall_quad(k, Vector2(xe, zb), Vector2(xw, zb), 0.0, h, Vector3(0, 0, 1), wall.darkened(0.03))
	# --- the common room: inner walls (warm plaster above a wainscot), the
	# back wall (the closed block), floor and ceiling
	var inner: Color = d["inner"]
	var r0 := room.position
	var r1 := room.end
	k.mat = MeshKit.M_PLASTER
	_face_with_holes(k, Vector2(r0.x, r0.y), Vector2(r1.x, r0.y), C, [[cx - r0.x, hw]], DH, Vector3(0, 0, 1), inner, 0.22)
	_face_with_holes(k, Vector2(r0.x, r1.y), Vector2(r0.x, r0.y), C, [[r1.y - side_z, hw]], DH, Vector3(1, 0, 0), inner.darkened(0.04), 0.2)
	_face_with_holes(k, Vector2(r1.x, r0.y), Vector2(r1.x, r1.y), C, [[side_z - r0.y, hw]], DH, Vector3(-1, 0, 0), inner.darkened(0.04), 0.2)
	_wall_quad(k, Vector2(r1.x, r1.y), Vector2(r0.x, r1.y), 0.0, C, Vector3(0, 0, -1), inner.darkened(0.02), 0.22)
	# ceiling
	A._quad_facing(k, Vector3(r0.x, C, r0.y), Vector3(r1.x, C, r0.y), Vector3(r1.x, C, r1.y), Vector3(r0.x, C, r1.y), inner.lightened(0.08), Vector3.DOWN)
	k.cu_emission_last(6, 0.16)
	# door reveals: jambs and the lintel's underside, in dressed stone
	k.mat = MeshKit.M_STONE
	for dr in doors:
		var p: Vector2 = dr["pos"]
		var n_in: Vector2 = dr["n_in"]
		var tg: Vector2 = dr["tangent"]
		var lp: Vector2 = dr["line_p"]
		for sgn in [-1.0, 1.0]:
			var j0: Vector2 = p + tg * (hw * float(sgn))
			var j1: Vector2 = lp + tg * (hw * float(sgn))
			_wall_quad(k, j0, j1, 0.0, DH, Vector3(-tg.x * sgn, 0, -tg.y * sgn), STONE.darkened(0.1), 0.06)
		var s0: Vector2 = p - tg * hw
		var s1: Vector2 = p + tg * hw
		A._quad_facing(k, _v(s0, DH), _v(s1, DH), _v(s1 + n_in * T, DH), _v(s0 + n_in * T, DH), STONE.darkened(0.2), Vector3.DOWN)
	# plinth along the facades (not across the openings), cornice, a string
	# course at the first floor, quoins
	var plinth := wall.darkened(0.25).lerp(STONE.darkened(0.3), 0.5)
	var segs := [
		[Vector2(xw, zf), Vector2(cx - hw, zf)], [Vector2(cx + hw, zf), Vector2(xe, zf)],
		[Vector2(xw, zf), Vector2(xw, side_z - hw)], [Vector2(xw, side_z + hw), Vector2(xw, zb)],
		[Vector2(xe, zf), Vector2(xe, side_z - hw)], [Vector2(xe, side_z + hw), Vector2(xe, zb)],
		[Vector2(xw, zb), Vector2(xe, zb)],
	]
	for sg in segs:
		k.segment_box(sg[0], sg[1], 0.0, 0.62, 0.18, plinth)
	var cc := Vector2(fp.get_center().x, fp.get_center().y)
	k.chamfer_box(Vector3(cc.x, h - 0.2, cc.y), Vector3(fp.size.x + 0.6, 0.5, fp.size.y + 0.6), STONE.lerp(wall.lightened(0.25), 0.4), 0.12)
	k.chamfer_box(Vector3(cc.x, C + 0.32, cc.y), Vector3(fp.size.x + 0.24, 0.22, fp.size.y + 0.24), STONE.lerp(wall.lightened(0.18), 0.4), 0.05)
	for qx in [xw, xe]:
		for qz in [zf, zb]:
			k.chamfer_box(Vector3(qx, (h - 0.7) * 0.5 + 0.35, qz), Vector3(0.7, h - 1.4, 0.7), STONE.lerp(wall.lightened(0.16), 0.5), 0.08)
	k.mat = 0.0
	_roof(d, g, k)


func _roof(d: Dictionary, g: Dictionary, k: MeshKit) -> void:
	var fp: Rect2 = g["footprint"]
	var h: float = d["h"]
	var c := fp.get_center()
	var wall: Color = d["wall"]
	match String(d["style"]):
		"brick":
			A.roof_gable(k, c, fp.size, h, minf(fp.size.x, fp.size.y) * 0.4, d["roof"], 0.6, wall, true)
			# dormers along the front slope
			for i in 4:
				var dx := c.x - fp.size.x * 0.33 + float(i) * fp.size.x * 0.22
				_dormer(k, Vector3(dx, h + 1.4, fp.position.y + 2.2), d)
		"cupola":
			var rise := minf(fp.size.x, fp.size.y) * 0.34
			A.roof_gable(k, c, fp.size, h, rise, d["roof"], 0.7, wall, false)
			_cupola(k, Vector3(c.x, h + rise - 0.3, c.y), d)
		"lodge":
			var rise2 := fp.size.x * 0.48
			A.roof_gable(k, c, fp.size, h, rise2, d["roof"], 0.9, wall, false)
			# a stone chimney through the roof, a round window in the front gable
			k.mat = MeshKit.M_STONE
			k.chamfer_box(Vector3(c.x + fp.size.x * 0.22, h + rise2 * 0.75, c.y + fp.size.y * 0.15), Vector3(1.4, rise2 * 0.9 + 1.6, 1.2), STONE.darkened(0.15), 0.08)
			k.mat = MeshKit.M_GLASS
			var gw := Vector3(c.x, h + rise2 * 0.42, fp.position.y - 0.06)
			for i in 16:
				var a0 := TAU * float(i) / 16.0
				var a1 := TAU * float(i + 1) / 16.0
				A._tri_facing(k, gw, gw + Vector3(cos(a0), sin(a0), 0) * 0.85, gw + Vector3(cos(a1), sin(a1), 0) * 0.85, Color(1.0, 0.78, 0.46), Vector3(0, 0, -1))
			k.cu_emission_last(16 * 3, 0.9)
			k.mat = MeshKit.M_WOOD
			for i in 16:
				var a2 := TAU * float(i) / 16.0
				var a3 := TAU * float(i + 1) / 16.0
				A._quad_facing(k, gw + Vector3(cos(a2), sin(a2), 0) * 0.85, gw + Vector3(cos(a3), sin(a3), 0) * 0.85,
					gw + Vector3(cos(a3), sin(a3), -0.02) * 1.05, gw + Vector3(cos(a2), sin(a2), -0.02) * 1.05, TRIM.darkened(0.15), Vector3(0, 0, -1))
			k.mat = 0.0


func _dormer(k: MeshKit, base: Vector3, d: Dictionary) -> void:
	k.mat = _wall_mat(d)
	k.box(base, Vector3(1.8, 1.6, 1.4), (d["wall"] as Color).darkened(0.05))
	k.mat = MeshKit.M_GLASS
	k.box(base + Vector3(0, 0.05, -0.71), Vector3(1.0, 0.9, 0.04), Color(1.0, 0.8, 0.5), 0.0, 0.8)
	k.mat = MeshKit.M_ROOF
	k.chamfer_box(base + Vector3(0, 0.95, 0.05), Vector3(2.1, 0.3, 1.7), (d["roof"] as Color).lightened(0.06), 0.08)
	k.mat = 0.0


## Lanternfield's lantern cupola: glazed, glowing, on the ridge.
func _cupola(k: MeshKit, base: Vector3, d: Dictionary) -> void:
	k.mat = MeshKit.M_PLASTER
	k.chamfer_box(base + Vector3(0, 0.6, 0), Vector3(2.6, 1.2, 2.6), (d["wall"] as Color).lightened(0.05), 0.06)
	k.mat = MeshKit.M_GLASS
	k.box(base + Vector3(0, 1.85, 0), Vector3(2.1, 1.3, 2.1), Color(1.0, 0.80, 0.46), 0.0, 1.4)
	k.mat = MeshKit.M_WOOD
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			k.box(base + Vector3(sx * 1.05, 1.85, sz * 1.05), Vector3(0.16, 1.4, 0.16), TRIM)
	k.mat = MeshKit.M_ROOF
	k.revolve(base + Vector3(0, 2.5, 0), PackedVector2Array([Vector2(1.75, 0.0), Vector2(1.4, 0.35), Vector2(0.5, 1.1), Vector2(0.08, 1.6)]),
		PackedColorArray([(d["roof"] as Color).darkened(0.2), d["roof"], (d["roof"] as Color).lightened(0.06), (d["roof"] as Color).lightened(0.1)]), 4, PackedFloat32Array(), 0.0, PI * 0.25)
	k.mat = 0.0
	k.soft_blob(base + Vector3(0, 4.3, 0), Vector3(0.2, 0.24, 0.2), Color(1.0, 0.84, 0.42), 3, 8, 0.0, 0.0, 0, 1.6)


# ---------------------------------------------------------------------------
# Windows
# ---------------------------------------------------------------------------
func windows(bd: Dictionary) -> void:
	var id := String(bd["dorm_id"])
	var d := CampusDorms.def(id)
	var g := CampusDorms.geometry(id)
	var fp: Rect2 = g["footprint"]
	var h: float = d["h"]
	var warm: float = d["warm"]
	var C := CampusDorms.CEIL
	var hw := CampusDorms.DOOR_W * 0.5
	var k := _k(fp.get_center().x, fp.get_center().y)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id) + 77
	var xw := fp.position.x
	var xe := fp.end.x
	var zf := fp.position.y
	var zb := fp.end.y
	var bz: float = g["block_z"]
	var cx: float = (g["doors"][0]["pos"] as Vector2).x
	var up_y := C + 0.4
	var up_h := h - 0.4
	# front: ground floor beside the door (porch clear), upper floor across
	for span in [[xw + 0.9, cx - hw - 1.6], [cx + hw + 1.6, xe - 0.9]]:
		var a: float = span[0]
		var b: float = span[1]
		if b - a > 3.2:
			A._window_face(k, Vector3((a + b) * 0.5, 0, zf), Vector3(-1, 0, 0), Vector3(0, 0, -1), b - a, 4.3, warm, rng, 1.0)
			_inner_windows(k, Vector3((a + b) * 0.5, 0, zf + CampusDorms.WALL_T), Vector3(1, 0, 0), Vector3(0, 0, 1), b - a, (d["fabric"] as Color).lightened(0.1))
	# (the gap over the front door keeps the name board and the banners clear)
	for span2 in [[xw + 0.9, cx - 5.8], [cx + 5.8, xe - 0.9]]:
		var a2: float = span2[0]
		var b2: float = span2[1]
		if b2 - a2 > 3.2:
			A._window_face(k, Vector3((a2 + b2) * 0.5, 0, zf), Vector3(-1, 0, 0), Vector3(0, 0, -1), b2 - a2, up_h, warm, rng, up_y)
	# ends: upper floor over the room, both floors along the closed block
	for side in [-1.0, 1.0]:
		var x: float = xw if side < 0.0 else xe
		var nrm := Vector3(side, 0, 0)
		var right := Vector3(0, 0, side)
		A._window_face(k, Vector3(x, 0, (zf + bz) * 0.5), right, nrm, bz - zf - 1.2, up_h, warm, rng, up_y)
		if zb - bz > 4.0:
			A._window_face(k, Vector3(x, 0, (bz + zb) * 0.5), right, nrm, zb - bz - 1.0, h - 0.8, warm, rng, 1.2)
	A._window_face(k, Vector3((xw + xe) * 0.5, 0, zb), Vector3(1, 0, 0), Vector3(0, 0, 1), fp.size.x - 2.0, h - 0.8, warm, rng, 1.2)


## Night glass on the inside of the room's front wall, where the facade has
## its ground-floor windows: moonlit panes in a painted frame with a
## transom bar, and warm curtains drawn to the sides.
func _inner_windows(k: MeshKit, origin: Vector3, right: Vector3, normal: Vector3, width: float, curtain: Color = Color(0.70, 0.40, 0.26)) -> void:
	var cols := int(width / 3.2)
	if cols <= 0:
		return
	var sp := width / float(cols)
	for c in cols:
		var ctr := origin + right * (-width * 0.5 + sp * (float(c) + 0.5)) + Vector3.UP * 1.95 + normal * 0.02
		var hw := right * 0.55
		var hh := Vector3.UP * 0.72
		k.mat = MeshKit.M_GLASS
		A._quad_facing(k, ctr - hw + hh, ctr + hw + hh, ctr + hw, ctr - hw, Color(0.30, 0.38, 0.62), normal)
		k.cu_emission_last(6, 0.3)
		A._quad_facing(k, ctr - hw, ctr + hw, ctr + hw - hh, ctr - hw - hh, Color(0.16, 0.22, 0.40), normal)
		k.cu_emission_last(6, 0.25)
		k.mat = MeshKit.M_WOOD
		var f := ctr + normal * 0.012
		var t := 0.07
		var fr := TRIM.darkened(0.06)
		for e in [[f - hw - right * t + hh + Vector3.UP * t, f + hw + right * t + hh + Vector3.UP * t, f + hw + right * t + hh, f - hw - right * t + hh],
				[f - hw - right * t - hh, f + hw + right * t - hh, f + hw + right * t - hh - Vector3.UP * t, f - hw - right * t - hh - Vector3.UP * t],
				[f - hw - right * t + hh, f - hw + hh, f - hw - hh, f - hw - right * t - hh],
				[f + hw + hh, f + hw + right * t + hh, f + hw + right * t - hh, f + hw - hh],
				[f - hw + Vector3.UP * 0.03 + hh * 0.35, f + hw + Vector3.UP * 0.03 + hh * 0.35, f + hw - Vector3.UP * 0.03 + hh * 0.35, f - hw - Vector3.UP * 0.03 + hh * 0.35],
				[f - right * 0.025 + hh, f + right * 0.025 + hh, f + right * 0.025 - hh, f - right * 0.025 - hh]]:
			A._quad_facing(k, e[0], e[1], e[2], e[3], fr, normal)
		# sill and curtains
		k.box(ctr - hh - Vector3.UP * 0.1 + normal * 0.08, (right.abs() * 1.4 + normal.abs() * 0.16 + Vector3.UP * 0.06), fr)
		k.mat = MeshKit.M_PLAIN
		for sg in [-1.0, 1.0]:
			var cc := ctr + right * ((0.55 + 0.22) * float(sg)) + normal * 0.06
			A._quad_facing(k, cc - right * 0.24 + hh * 1.25, cc + right * 0.24 + hh * 1.25, cc + right * 0.2 - hh * 1.2, cc - right * 0.2 - hh * 1.2, curtain, normal)
			k.cu_emission_last(6, 0.12)
		k.mat = MeshKit.M_METAL
		k.box(ctr + hh * 1.3 + normal * 0.08, right.abs() * 2.0 + normal.abs() * 0.04 + Vector3.UP * 0.04, IRON.lightened(0.2))
		k.mat = 0.0


# ---------------------------------------------------------------------------
# Entrances
# ---------------------------------------------------------------------------
func entrances(bd: Dictionary) -> void:
	var id := String(bd["dorm_id"])
	var d := CampusDorms.def(id)
	var g := CampusDorms.geometry(id)
	var hw := CampusDorms.DOOR_W * 0.5
	var DH := CampusDorms.DOOR_H
	var accent: Color = d["accent"]
	for i in (g["doors"] as Array).size():
		var dr: Dictionary = g["doors"][i]
		var p: Vector2 = dr["pos"]
		var n: Vector2 = dr["normal"]
		var tg: Vector2 = dr["tangent"]
		var n3 := Vector3(n.x, 0, n.y)
		var t3 := Vector3(tg.x, 0, tg.y)
		var base := Vector3(p.x, 0, p.y)
		var k := _k(p.x, p.y)
		var main := i == 0
		# stone surround with a keystone, a lit fanlight above the opening
		k.mat = MeshKit.M_STONE
		for sgn in [-1.0, 1.0]:
			k.chamfer_box(base + t3 * ((hw + 0.18) * sgn) + Vector3.UP * (DH * 0.5 + 0.1) + n3 * 0.06, Vector3(0.36, DH + 0.2, 0.16).abs() if absf(t3.x) > 0.5 else Vector3(0.16, DH + 0.2, 0.36), STONE, 0.04)
		var lint := Vector3(CampusDorms.DOOR_W + 0.9, 0.34, 0.2) if absf(t3.x) > 0.5 else Vector3(0.2, 0.34, CampusDorms.DOOR_W + 0.9)
		k.chamfer_box(base + Vector3.UP * (DH + 0.2) + n3 * 0.07, lint, STONE.lightened(0.04), 0.05)
		k.chamfer_box(base + Vector3.UP * (DH + 0.42) + n3 * 0.1, Vector3(0.4, 0.5, 0.22) if absf(t3.x) > 0.5 else Vector3(0.22, 0.5, 0.4), TRIM, 0.04)
		k.mat = MeshKit.M_GLASS
		var fan := base + Vector3.UP * (DH + 0.85) + n3 * 0.05
		A._quad_facing(k, fan - t3 * 1.2, fan + t3 * 1.2, fan + t3 * 1.2 + Vector3.UP * 0.55, fan - t3 * 1.2 + Vector3.UP * 0.55, Color(1.0, 0.82, 0.52), n3)
		k.cu_emission_last(6, 1.3)
		k.mat = MeshKit.M_WOOD
		for m in 5:
			var mx := -1.2 + 0.6 * float(m)
			k.box(fan + t3 * mx + Vector3.UP * 0.275 + n3 * 0.02, Vector3(0.06, 0.6, 0.04) if absf(t3.x) > 0.5 else Vector3(0.04, 0.6, 0.06), TRIM)
		# porch hood on brackets (no posts: it is above head height)
		var depth := 2.2 if main else 1.4
		var width := CampusDorms.DOOR_W + (2.0 if main else 1.0)
		var hood_c := base + n3 * (depth * 0.5) + Vector3.UP * (DH + 1.45)
		k.mat = MeshKit.M_ROOF
		k.chamfer_box(hood_c, Vector3(width, 0.26, depth) if absf(t3.x) > 0.5 else Vector3(depth, 0.26, width), (d["roof"] as Color).lightened(0.05), 0.08)
		k.mat = MeshKit.M_WOOD
		for sgn in [-1.0, 1.0]:
			var bb: Vector3 = base + t3 * ((width * 0.5 - 0.35) * float(sgn))
			# a knee brace: a post against the wall and an arm under the hood
			k.box(bb + n3 * 0.1 + Vector3.UP * (DH + 0.85), Vector3(0.14, 0.9, 0.14), TRIM.darkened(0.12))
			var arm := Vector3(0.12, 0.14, depth * 0.9) if absf(t3.x) > 0.5 else Vector3(depth * 0.9, 0.14, 0.12)
			k.box(bb + n3 * (depth * 0.45) + Vector3.UP * (DH + 1.25), arm, TRIM.darkened(0.12))
			for kk in 3:
				var f := float(kk + 1) / 4.0
				k.box(bb + n3 * (0.1 + (depth * 0.8) * f * 0.5) + Vector3.UP * (DH + 0.45 + 0.8 * f), Vector3(0.1, 0.1, 0.1), TRIM.darkened(0.12))
		k.mat = 0.0
		k.soft_blob(hood_c - Vector3.UP * 0.32, Vector3(0.22, 0.26, 0.22), Color(1.0, 0.85, 0.5), 3, 8, 0.0, 0.0, 0, 2.4)
		# wall lanterns, a flush stone threshold, the warm pool in front
		for sgn in [-1.0, 1.0]:
			A._wall_lantern(base + t3 * ((hw + 0.75) * sgn) + Vector3.UP * 2.3, n3)
		k.mat = MeshKit.M_STONE
		var th := _v((p + (dr["line_p"] as Vector2)) * 0.5, 0.02)
		k.box(th, Vector3(CampusDorms.DOOR_W, 0.04, CampusDorms.WALL_T + 0.3) if absf(t3.x) > 0.5 else Vector3(CampusDorms.WALL_T + 0.3, 0.04, CampusDorms.DOOR_W), STONE.lightened(0.05))
		k.mat = 0.0
		B.glow_disc(Vector3(p.x + n.x * 2.0, 0.11, p.y + n.y * 2.0), 4.6 if main else 3.6)
		if main:
			# house banners either side of the front door, in the dorm's colours
			for sgn in [-1.0, 1.0]:
				var bp: Vector3 = base + t3 * (4.6 * float(sgn)) + n3 * 0.12 + Vector3.UP * 6.2
				if bp.y + 1.8 > float(d["h"]):
					bp.y = float(d["h"]) - 2.0
				k.mat = MeshKit.M_PLAIN
				k.box(bp, Vector3(1.4, 3.2, 0.08) if absf(t3.x) > 0.5 else Vector3(0.08, 3.2, 1.4), accent.darkened(0.15))
				k.box(bp - Vector3.UP * 0.7 + n3 * 0.05, Vector3(0.8, 0.8, 0.05) if absf(t3.x) > 0.5 else Vector3(0.05, 0.8, 0.8), TRIM.lerp(Color(1.0, 0.85, 0.3), 0.6), 0.0, 0.3)
				k.mat = MeshKit.M_METAL
				k.box(bp + Vector3.UP * 1.7 + n3 * 0.05, Vector3(1.7, 0.08, 0.08) if absf(t3.x) > 0.5 else Vector3(0.08, 0.08, 1.7), Color(0.85, 0.7, 0.35))
				k.mat = 0.0


# ---------------------------------------------------------------------------
# Interior: a warm common room
# ---------------------------------------------------------------------------
func interior(bd: Dictionary) -> void:
	var id := String(bd["dorm_id"])
	var d := CampusDorms.def(id)
	var g := CampusDorms.geometry(id)
	var room: Rect2 = g["room"]
	var C := CampusDorms.CEIL
	var r0 := room.position
	var r1 := room.end
	var c := room.get_center()
	var k := _k(c.x, c.y)
	var kd := _k(c.x, c.y, true)
	var accent: Color = d["accent"]
	var floor_c: Color = d["floor"]
	# plank floor (slightly above the ground) and two rugs
	k.mat = MeshKit.M_WOOD
	A._quad_facing(k, Vector3(r0.x, 0.02, r0.y), Vector3(r1.x, 0.02, r0.y), Vector3(r1.x, 0.02, r1.y), Vector3(r0.x, 0.02, r1.y), floor_c, Vector3.UP)
	k.cu_emission_last(6, 0.14)
	k.mat = MeshKit.M_PLAIN
	for rx in [-0.22, 0.22]:
		var rc := Vector2(c.x + room.size.x * float(rx), c.y + 0.6)
		var rs := Vector2(minf(room.size.x * 0.26, 9.0), 4.2)
		A._quad_facing(k, Vector3(rc.x - rs.x * 0.5, 0.035, rc.y - rs.y * 0.5), Vector3(rc.x + rs.x * 0.5, 0.035, rc.y - rs.y * 0.5),
			Vector3(rc.x + rs.x * 0.5, 0.035, rc.y + rs.y * 0.5), Vector3(rc.x - rs.x * 0.5, 0.035, rc.y + rs.y * 0.5), (d["fabric"] as Color).darkened(0.45), Vector3.UP)
		k.cu_emission_last(6, 0.1)
		A._quad_facing(k, Vector3(rc.x - rs.x * 0.4, 0.04, rc.y - rs.y * 0.38), Vector3(rc.x + rs.x * 0.4, 0.04, rc.y - rs.y * 0.38),
			Vector3(rc.x + rs.x * 0.4, 0.04, rc.y + rs.y * 0.38), Vector3(rc.x - rs.x * 0.4, 0.04, rc.y + rs.y * 0.38), (d["fabric"] as Color).darkened(0.2), Vector3.UP)
		k.cu_emission_last(6, 0.12)
	# wainscot band around the walls (wood, below the plaster)
	k.mat = MeshKit.M_WOOD
	var wc := WOOD_DARK.lightened(0.1)
	var hw := CampusDorms.DOOR_W * 0.5
	var side_z: float = (g["doors"][1]["pos"] as Vector2).y
	var cx: float = (g["doors"][0]["pos"] as Vector2).x
	for sg in [[Vector2(r0.x, r0.y), Vector2(cx - hw, r0.y), Vector3(0, 0, 1)], [Vector2(cx + hw, r0.y), Vector2(r1.x, r0.y), Vector3(0, 0, 1)],
			[Vector2(r1.x, r1.y), Vector2(r0.x, r1.y), Vector3(0, 0, -1)],
			[Vector2(r0.x, r0.y), Vector2(r0.x, side_z - hw), Vector3(1, 0, 0)], [Vector2(r0.x, side_z + hw), Vector2(r0.x, r1.y), Vector3(1, 0, 0)],
			[Vector2(r1.x, r0.y), Vector2(r1.x, side_z - hw), Vector3(-1, 0, 0)], [Vector2(r1.x, side_z + hw), Vector2(r1.x, r1.y), Vector3(-1, 0, 0)]]:
		var off: Vector3 = sg[2] * 0.012
		_wall_quad(k, (sg[0] as Vector2) + Vector2(off.x, off.z), (sg[1] as Vector2) + Vector2(off.x, off.z), 0.0, 1.05, sg[2], wc, 0.1)
		_wall_quad(k, (sg[0] as Vector2) + Vector2(off.x, off.z) * 2.0, (sg[1] as Vector2) + Vector2(off.x, off.z) * 2.0, 1.02, 1.12, sg[2], wc.lightened(0.15), 0.12)
	# ceiling beams across the room and pendant lights between them
	var nb := int(room.size.x / 4.5)
	for i in nb + 1:
		var bx := r0.x + room.size.x * float(i) / float(nb)
		k.box(Vector3(bx, C - 0.06, c.y), Vector3(0.3, 0.12, room.size.y), WOOD_DARK.lightened(0.25))
	k.mat = 0.0
	for i in nb:
		var px := r0.x + room.size.x * (float(i) + 0.5) / float(nb)
		kd.mat = MeshKit.M_METAL
		kd.box(Vector3(px, C - 0.3, c.y), Vector3(0.03, 0.5, 0.03), IRON)
		kd.mat = MeshKit.M_GLASS
		kd.soft_blob(Vector3(px, C - 0.68, c.y), Vector3(0.28, 0.2, 0.28), Color(1.0, 0.82, 0.52), 3, 8, 0.0, 0.0, 0, 1.6)
		kd.mat = 0.0
		B.glow_disc(Vector3(px, 0.06, c.y), 3.0)
	# a low fireplace on the back wall (its hearth is a collider; the mantel
	# stays under the follow camera's view when it backs up to the wall),
	# with the house crest above
	var fx := cx
	var bzw := r1.y
	k.mat = MeshKit.M_STONE
	k.chamfer_box(Vector3(fx, 0.72, bzw - 0.22), Vector3(2.8, 1.44, 0.44), STONE.darkened(0.1), 0.06)
	k.chamfer_box(Vector3(fx, 1.5, bzw - 0.27), Vector3(3.2, 0.14, 0.54), STONE.lightened(0.05), 0.04)
	k.chamfer_box(Vector3(fx, 0.08, bzw - 0.45), Vector3(2.6, 0.16, 0.9), STONE.darkened(0.25), 0.03)
	k.mat = MeshKit.M_PLAIN
	A._quad_facing(k, Vector3(fx - 0.75, 0.16, bzw - 0.445), Vector3(fx + 0.75, 0.16, bzw - 0.445), Vector3(fx + 0.75, 1.05, bzw - 0.445), Vector3(fx - 0.75, 1.05, bzw - 0.445), Color(0.08, 0.05, 0.04), Vector3(0, 0, -1))
	k.mat = 0.0
	k.soft_blob(Vector3(fx, 0.38, bzw - 0.5), Vector3(0.5, 0.26, 0.16), Color(1.0, 0.55, 0.18), 3, 8, 0.0, 0.0, 0, 2.2)
	k.soft_blob(Vector3(fx, 0.62, bzw - 0.5), Vector3(0.28, 0.22, 0.1), Color(1.0, 0.8, 0.3), 3, 8, 0.0, 0.0, 0, 2.6)
	B.glow_disc(Vector3(fx, 0.06, bzw - 1.6), 3.4)
	k.mat = MeshKit.M_PLAIN
	k.box(Vector3(fx, 2.55, bzw - 0.05), Vector3(1.4, 1.4, 0.06), accent.darkened(0.1), 0.0, 0.25)
	k.box(Vector3(fx, 2.55, bzw - 0.09), Vector3(0.75, 0.75, 0.04), Color(1.0, 0.85, 0.35), 0.0, 0.5)
	k.mat = 0.0
	# framed pictures and warm wall sconces along the back wall
	var nfr := int(room.size.x / 6.0)
	for i in nfr:
		var px2 := r0.x + room.size.x * (float(i) + 0.5) / float(nfr)
		if absf(px2 - fx) < 2.5:
			continue
		var kd3 := _k(px2, bzw, true)
		kd3.mat = MeshKit.M_WOOD
		kd3.box(Vector3(px2, 2.45, bzw - 0.04), Vector3(1.1, 0.8, 0.05), WOOD_DARK)
		kd3.mat = MeshKit.M_PLAIN
		kd3.box(Vector3(px2, 2.45, bzw - 0.07), Vector3(0.9, 0.6, 0.02), [Color(0.35, 0.5, 0.7), Color(0.7, 0.55, 0.35), Color(0.4, 0.6, 0.45)][i % 3], 0.0, 0.2)
		kd3.mat = MeshKit.M_GLASS
		for sg2 in [-1.0, 1.0]:
			kd3.soft_blob(Vector3(px2 + 1.2 * float(sg2), 2.9, bzw - 0.12), Vector3(0.1, 0.14, 0.08), Color(1.0, 0.8, 0.5), 3, 6, 0.0, 0.0, 0, 1.8)
		kd3.mat = 0.0
	# sofas (their colliders: two runs along the back wall), cushions
	for bx in g["boxes"]:
		if String(bx[2]) != "sofa":
			continue
		var sc: Vector3 = bx[0]
		var ss: Vector3 = bx[1]
		var fabric: Color = d["fabric"]
		k.mat = MeshKit.M_PLAIN
		k.chamfer_box(Vector3(sc.x, 0.24, sc.z), Vector3(ss.x, 0.48, ss.z), fabric.darkened(0.25), 0.1)
		k.chamfer_box(Vector3(sc.x, 0.52, sc.z + 0.05), Vector3(ss.x - 0.3, 0.16, ss.z - 0.25), fabric, 0.07)
		k.chamfer_box(Vector3(sc.x, 0.78, sc.z + ss.z * 0.38), Vector3(ss.x, 0.62, 0.26), fabric.darkened(0.1), 0.1)
		for sgn in [-1.0, 1.0]:
			k.chamfer_box(Vector3(sc.x + (ss.x * 0.5 - 0.14) * sgn, 0.62, sc.z), Vector3(0.28, 0.4, ss.z), fabric.darkened(0.15), 0.08)
		var n := int(ss.x / 1.6)
		for i in n:
			var cxp := sc.x - ss.x * 0.5 + (float(i) + 0.5) * ss.x / float(n)
			k.chamfer_box(Vector3(cxp, 0.78, sc.z + 0.2), Vector3(0.5, 0.4, 0.14), [Color(0.95, 0.86, 0.62), accent.lightened(0.15), fabric.lightened(0.3)][i % 3], 0.06)
		k.mat = 0.0
	# noticeboard on the front wall's inner face, pigeonholes and plants
	var kd2 := _k(c.x, c.y, true)
	kd2.mat = MeshKit.M_WOOD
	var nbx := cx + room.size.x * 0.3
	kd2.chamfer_box(Vector3(nbx, 1.75, r0.y + 0.06), Vector3(2.2, 1.3, 0.08), WOOD_DARK, 0.03)
	kd2.mat = MeshKit.M_PLAIN
	kd2.box(Vector3(nbx, 1.75, r0.y + 0.11), Vector3(1.9, 1.0, 0.02), Color(0.86, 0.78, 0.62), 0.0, 0.15)
	var nrng := RandomNumberGenerator.new()
	nrng.seed = hash(id)
	for i in 7:
		kd2.box(Vector3(nbx - 0.75 + 0.25 * float(i), 1.75 + nrng.randf_range(-0.3, 0.3), r0.y + 0.125), Vector3(0.2, 0.26, 0.01), [Color(1, 0.6, 0.6), Color(0.6, 0.8, 1), Color(1, 0.95, 0.6)][i % 3], 0.0, 0.25)
	kd2.mat = MeshKit.M_WOOD
	var pgx := cx - room.size.x * 0.3
	kd2.chamfer_box(Vector3(pgx, 1.5, r0.y + 0.2), Vector3(2.4, 1.8, 0.3), WOOD_DARK.lightened(0.15), 0.03)
	kd2.mat = MeshKit.M_PLAIN
	for row in 4:
		for col in 6:
			kd2.box(Vector3(pgx - 1.0 + 0.4 * float(col), 0.85 + 0.42 * float(row), r0.y + 0.36), Vector3(0.32, 0.32, 0.02), Color(0.16, 0.11, 0.08))
	kd2.mat = 0.0
	for corner in [Vector2(r0.x + 0.55, r1.y - 0.55), Vector2(r1.x - 0.55, r1.y - 0.55)]:
		kd2.mat = MeshKit.M_STONE
		kd2.revolve(_v(corner, 0.0), PackedVector2Array([Vector2(0.22, 0.0), Vector2(0.3, 0.5), Vector2(0.32, 0.55)]), PackedColorArray([Color(0.62, 0.38, 0.28), Color(0.7, 0.42, 0.3), Color(0.74, 0.46, 0.32)]), 8)
		kd2.mat = MeshKit.M_LEAF
		kd2.soft_blob(_v(corner, 1.0), Vector3(0.45, 0.6, 0.45), Color(0.24, 0.46, 0.26), 4, 8, 0.0, 0.08, int(corner.x))
		kd2.mat = 0.0
	# the room's warm light in the light field is stamped by CampusKit; a
	# soft warm pool on the floor near each door shows the way out
	for dr in g["doors"]:
		var ins: Vector2 = dr["inside"]
		B.glow_disc(Vector3(ins.x, 0.06, ins.y), 2.4)


# ---------------------------------------------------------------------------
# Yard: monument name signs
# ---------------------------------------------------------------------------
func yard_signs() -> void:
	for so in L.solids:
		if String(so.get("kind", "")) != "dorm_sign":
			continue
		var p: Vector2 = so["pos"]
		var s: Vector3 = so["size"]
		var d := CampusDorms.def(String(so.get("dorm", "")))
		var k := _k(p.x, p.y)
		k.mat = MeshKit.M_STONE
		k.chamfer_box(Vector3(p.x, 0.25, p.y), Vector3(s.x + 0.3, 0.5, s.z + 0.3), STONE.darkened(0.2), 0.06)
		k.chamfer_box(Vector3(p.x, s.y * 0.5 + 0.2, p.y), Vector3(s.x, s.y - 0.1, s.z), STONE, 0.08)
		k.mat = MeshKit.M_PLAIN
		k.box(Vector3(p.x, s.y * 0.62 + 0.2, p.y - s.z * 0.5 - 0.01), Vector3(s.x - 0.4, 0.5, 0.02), (d.get("accent", Color(0.3, 0.4, 0.7)) as Color).darkened(0.25))
		k.mat = 0.0
		B.glow_disc(Vector3(p.x, 0.1, p.y - 1.4), 2.6)
		if not d.is_empty():
			A._label(Vector3(p.x, s.y * 0.62 + 0.2, p.y - s.z * 0.5 - 0.03), Vector3(0, 0, -1), String(d["name"]), 0.32, s.x - 0.5)
