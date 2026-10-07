class_name ClassicArchitecture
extends RefCounted
## Buildings, walls, hedges, fences, lamps, benches, props and signs for the
## campus look (V5).  Visual only: every collider comes from ClassicLayout via
## ClassicBuilder.build_collision, so nothing here may stand where a runner
## walks unless a collider already does (porch roofs are wall-bracketed,
## steps are a few centimetres, signs stand beside the paths).
##
## A small modular kit shared by all buildings: brick or plaster walls on a
## dressed-stone plinth with quoins and a moulded cornice, recessed windows
## with lit interiors that vary (warm lamp, cooler screen glow, curtains
## half drawn), stone lintels and sills, roofs with thickness, a fascia, a
## ridge cap and chimneys, and readable entrances (lit door, transom, porch
## roof, a step and a name board).

var B: ClassicBuilder
var L: ClassicLayout

const BRICK := Color(0.64, 0.34, 0.30)
const TRIM := Color(0.90, 0.88, 0.84)
const STONE_TRIM := Color(0.74, 0.72, 0.70)
const IRON := Color(0.17, 0.19, 0.25)
const WOOD := Color(0.62, 0.42, 0.27)


func _init(builder: ClassicBuilder) -> void:
	B = builder
	L = builder.L


func _k(x: float, z: float, detail: bool = false) -> MeshKit:
	return B._kit_at(x, z, false, detail)


# ---------------------------------------------------------------------------
# Buildings
# ---------------------------------------------------------------------------
func building(bd: Dictionary) -> void:
	var pos: Vector2 = bd["pos"]
	var size: Vector2 = bd["size"]
	var h: float = bd["h"]
	var k := _k(pos.x, pos.y)
	var wall: Color = bd["wall"]
	var roof: Color = bd["roof"]
	var warm: float = float(bd.get("warm", 0.5))
	var id: String = bd["id"]
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var brick := wall.is_equal_approx(BRICK)
	var wall_mat := MeshKit.M_BRICK if brick else MeshKit.M_PLASTER
	if id == "tower":
		_tower(bd, k)
		return
	if id == "shed":
		_shed(bd, k)
		return
	if bd.has("dorm_id"):
		B.dorm_art.shell(bd)   # V6: a shell with a common room (ClassicDormArt)
		return
	if bd.get("dome", false):
		_observatory(bd, k)
		return
	var top_col := wall.lightened(0.1)
	k.mat = wall_mat
	k.box(Vector3(pos.x, h * 0.5, pos.y), Vector3(size.x, h, size.y), wall, 0.0, 0.0 if not bd.get("glass", false) else 0.25, top_col)
	# plinth, a moulded cornice and corner quoins in dressed stone
	k.mat = MeshKit.M_STONE
	k.chamfer_box(Vector3(pos.x, 0.35, pos.y), Vector3(size.x + 0.5, 0.7, size.y + 0.5), wall.darkened(0.25).lerp(STONE_TRIM.darkened(0.3), 0.5), 0.1)
	k.chamfer_box(Vector3(pos.x, h - 0.2, pos.y), Vector3(size.x + 0.6, 0.5, size.y + 0.6), STONE_TRIM.lerp(wall.lightened(0.25), 0.4), 0.12)
	k.chamfer_box(Vector3(pos.x, h - 0.55, pos.y), Vector3(size.x + 0.3, 0.2, size.y + 0.3), STONE_TRIM.lerp(wall.lightened(0.18), 0.4), 0.06)
	if not bd.get("glass", false):
		for cx: float in [-1.0, 1.0]:
			for cz: float in [-1.0, 1.0]:
				k.chamfer_box(Vector3(pos.x + cx * (hx - 0.05), (h - 0.7) * 0.5 + 0.35, pos.y + cz * (hz - 0.05)), Vector3(0.7, h - 1.4, 0.7), STONE_TRIM.lerp(wall.lightened(0.16), 0.5), 0.08)
	k.mat = 0.0
	if bd.get("glass", false):
		k.mat = MeshKit.M_GLASS
		k.box(Vector3(pos.x, h * 0.5, pos.y), Vector3(size.x + 0.05, h * 0.8, size.y + 0.05), Color(0.55, 0.9, 0.8), 0.0, 0.35)
		# glazing bars
		k.mat = MeshKit.M_METAL
		for i in int(size.y / 2.0) + 1:
			var zz := pos.y - hz + float(i) * size.y / float(int(size.y / 2.0))
			for sx: float in [-1.0, 1.0]:
				k.box(Vector3(pos.x + sx * (hx + 0.06), h * 0.5, zz), Vector3(0.08, h * 0.8, 0.1), Color(0.86, 0.9, 0.88))
		k.mat = 0.0
		roof_gable(k, pos, size, h, 3.0, roof, 0.2, wall, false)
		return
	var rise := minf(size.x, size.y) * (0.32 if size.x * size.y > 300.0 else 0.4)
	roof_gable(k, pos, size, h, rise, roof, 0.6, wall, brick)
	if bd.get("columns", false):
		k.mat = MeshKit.M_STONE
		for i in 6:
			var cz := pos.y - hz + 4.0 + float(i) * (size.y - 8.0) / 5.0
			# a fluted column: base, shaft with entasis, capital
			k.revolve(Vector3(pos.x + hx + 1.4, 0, cz), PackedVector2Array([Vector2(0.62, 0.0), Vector2(0.62, 0.3), Vector2(0.5, 0.42), Vector2(0.46, 0.6),
				Vector2(0.44, h * 0.5), Vector2(0.4, h - 1.6), Vector2(0.52, h - 1.35), Vector2(0.62, h - 1.0)]),
				PackedColorArray([TRIM.darkened(0.2), TRIM.darkened(0.1), TRIM, TRIM, TRIM, TRIM, TRIM.lightened(0.04), TRIM.lightened(0.06)]), 12)
		k.chamfer_box(Vector3(pos.x + hx + 1.4, h - 0.6, pos.y), Vector3(2.0, 0.8, size.y - 4.0), TRIM, 0.08)
		k.mat = 0.0
	if bd.get("dorm", false):
		_dorm_extras(bd, k)
	else:
		_entrance(bd, k, roof)


static func has_windows(bd: Dictionary) -> bool:
	return not (String(bd["id"]) in ["tower", "shed"] or bd.get("dome", false) or bd.get("glass", false) or bd.has("dorm_id"))


## One face's windows (a separate build step per face: the dorm has ~100).
func windows(bd: Dictionary, face: int) -> void:
	var pos: Vector2 = bd["pos"]
	var size: Vector2 = bd["size"]
	var h: float = bd["h"]
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var warm: float = float(bd.get("warm", 0.5))
	var k := _k(pos.x, pos.y)
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = hash(String(bd["id"])) + face * 7919
	match face:
		0: _window_face(k, Vector3(pos.x, 0, pos.y - hz), Vector3(-1, 0, 0), Vector3(0, 0, -1), size.x - 2.0, h - 0.8, warm, rng_b)
		1: _window_face(k, Vector3(pos.x, 0, pos.y + hz), Vector3(1, 0, 0), Vector3(0, 0, 1), size.x - 2.0, h - 0.8, warm, rng_b)
		2: _window_face(k, Vector3(pos.x - hx, 0, pos.y), Vector3(0, 0, 1), Vector3(-1, 0, 0), size.y - 2.0, h - 0.8, warm, rng_b)
		_: _window_face(k, Vector3(pos.x + hx, 0, pos.y), Vector3(0, 0, -1), Vector3(1, 0, 0), size.y - 2.0, h - 0.8, warm, rng_b)


## Windows on one face: a dark recess, the glass with a lit interior that
## varies, curtains, frame and mullions, a stone lintel and a sill.
func _window_face(k: MeshKit, origin: Vector3, right: Vector3, normal: Vector3, width: float, height: float, warm: float, rng: RandomNumberGenerator, y_start: float = 1.2) -> void:
	var cols := int(width / 3.2)
	var rows := int((height - y_start) / 3.0)
	if cols <= 0 or rows <= 0:
		return
	var up := Vector3.UP
	var spacing_x := width / float(cols)
	var yaw := atan2(-right.z, right.x)
	for r in rows:
		for c in cols:
			var lit := rng.randf() < warm
			var cx := -width * 0.5 + spacing_x * (float(c) + 0.5)
			var cy := y_start + 3.0 * float(r) + 0.9
			var ctr := origin + right * cx + up * cy
			var hw := right * 0.6
			var hh := up * 0.8
			# recess: the reveal reads as depth (dark band around the pane)
			k.mat = MeshKit.M_PLAIN
			var rv := ctr + normal * 0.04
			k.quad(rv - hw * 1.18 + hh * 1.12, rv + hw * 1.18 + hh * 1.12, rv + hw * 1.18 - hh * 1.12, rv - hw * 1.18 - hh * 1.12, Color(0.12, 0.11, 0.13))
			# the glass, pushed back: interior variation per window
			var g0 := ctr + normal * 0.05
			k.mat = MeshKit.M_GLASS
			if lit:
				var tone := rng.randf()
				var room := Color(1.0, 0.76, 0.42) if tone < 0.6 else (Color(0.96, 0.62, 0.34) if tone < 0.85 else Color(0.62, 0.72, 0.95))
				var em := rng.randf_range(0.6, 0.95)
				# brighter lower half (lamp light), dimmer ceiling, and
				# curtains drawn part-way on one or both sides
				k.quad(g0 - hw + hh, g0 + hw + hh, g0 + hw, g0 - hw, room.darkened(0.12), em * 0.85)
				k.quad(g0 - hw, g0 + hw, g0 + hw - hh, g0 - hw - hh, room, em)
				var cur := Color(0.70, 0.40, 0.26) if rng.randf() < 0.5 else Color(0.56, 0.46, 0.40)
				var cw := rng.randf_range(0.18, 0.32)
				var sides: Array = [-1.0, 1.0] if rng.randf() < 0.6 else [-1.0 if rng.randf() < 0.5 else 1.0]
				for side: float in sides:
					var e := g0 + right * (0.6 * side) + normal * 0.005
					var inner := e - right * (cw * side)
					_quad_facing(k, e + hh, inner + hh, inner - hh, e - hh, cur, normal)
					k.cu_emission_last(6, em * 0.45)
			else:
				k.quad(g0 - hw + hh, g0 + hw + hh, g0 + hw - hh, g0 - hw - hh, Color(0.10, 0.14, 0.24), 0.04)
				# a faint moon reflection streak on dark glass
				k.quad(g0 - hw * 0.2 + hh * 0.9 + normal * 0.003, g0 + hw * 0.1 + hh * 0.9 + normal * 0.003, g0 - hw * 0.5 - hh * 0.4 + normal * 0.003, g0 - hw * 0.8 - hh * 0.4 + normal * 0.003, Color(0.32, 0.38, 0.55), 0.12)
			k.mat = 0.0
			# painted frame, mullions, lintel and sill (near-field detail mesh)
			var kd := _k(ctr.x, ctr.z, true)
			var frame := TRIM
			var f0 := ctr + normal * 0.07
			var t := 0.09
			kd.mat = MeshKit.M_WOOD
			kd.quad(f0 - hw - right * t + hh + up * t, f0 + hw + right * t + hh + up * t, f0 + hw + right * t + hh, f0 - hw - right * t + hh, frame)
			kd.quad(f0 - hw - right * t - hh, f0 + hw + right * t - hh, f0 + hw + right * t - hh - up * t, f0 - hw - right * t - hh - up * t, frame)
			kd.quad(f0 - hw - right * t + hh, f0 - hw + hh, f0 - hw - hh, f0 - hw - right * t - hh, frame)
			kd.quad(f0 + hw + hh, f0 + hw + right * t + hh, f0 + hw + right * t - hh, f0 + hw - hh, frame)
			kd.quad(f0 - right * 0.035 + hh, f0 + right * 0.035 + hh, f0 + right * 0.035 - hh, f0 - right * 0.035 - hh, frame.darkened(0.08))
			kd.quad(f0 - hw + up * 0.035 + up * 0.15, f0 + hw + up * 0.035 + up * 0.15, f0 + hw - up * 0.035 + up * 0.15, f0 - hw - up * 0.035 + up * 0.15, frame.darkened(0.08))
			kd.mat = MeshKit.M_STONE
			kd.chamfer_box(ctr - hh - up * 0.14 + normal * 0.1, Vector3(1.55, 0.12, 0.24), STONE_TRIM.lightened(0.08), 0.03, yaw)
			kd.chamfer_box(ctr + hh + up * 0.2 + normal * 0.06, Vector3(1.6, 0.26, 0.14), STONE_TRIM, 0.04, yaw)
			kd.mat = 0.0


## Gable roof with thickness: slopes (shingle pattern), a fascia board along
## the eaves, a rounded ridge cap, gable ends in the wall material, and two
## chimneys on brick buildings.
func roof_gable(k: MeshKit, center: Vector2, size: Vector2, y0: float, rise: float, col: Color, overhang: float, wall: Color, chimneys: bool) -> void:
	var along_x := size.x >= size.y
	var L2 := (size.x if along_x else size.y) * 0.5 + overhang
	var W := (size.y if along_x else size.x) * 0.5 + overhang
	var th := 0.22
	var ax := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
	var aw := Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)
	var c := Vector3(center.x, y0, center.y)
	var eave_drop := overhang * rise / maxf(W - overhang, 0.1)
	var ridge := c + Vector3.UP * rise
	k.mat = MeshKit.M_ROOF
	for sg: float in [-1.0, 1.0]:
		var e0 := c + aw * (W * sg) - ax * L2 - Vector3.UP * eave_drop
		var e1 := c + aw * (W * sg) + ax * L2 - Vector3.UP * eave_drop
		var r0 := ridge - ax * L2
		var r1 := ridge + ax * L2
		var shade := col.darkened(0.1) if sg < 0.0 else col
		_quad_facing(k, r0, r1, e1, e0, shade, (aw * sg + Vector3.UP * (W / rise) * 0.25).normalized())
		# underside of the overhang (soffit), dark
		var s0 := e0 - Vector3.UP * th
		var s1 := e1 - Vector3.UP * th
		var i0 := c + aw * ((W - overhang) * sg) - ax * L2
		var i1 := c + aw * ((W - overhang) * sg) + ax * L2
		_quad_facing(k, s0, s1, i1, i0, col.darkened(0.55), Vector3.DOWN)
	k.mat = MeshKit.M_WOOD
	for sg: float in [-1.0, 1.0]:
		# fascia board along each eave
		var e0b := c + aw * (W * sg) - ax * L2 - Vector3.UP * eave_drop
		var e1b := c + aw * (W * sg) + ax * L2 - Vector3.UP * eave_drop
		_quad_facing(k, e0b, e1b, e1b - Vector3.UP * th, e0b - Vector3.UP * th, TRIM.darkened(0.12), aw * sg)
	# gable ends: wall triangles + bargeboards
	k.mat = MeshKit.M_PLASTER if not wall.is_equal_approx(BRICK) else MeshKit.M_BRICK
	for se: float in [-1.0, 1.0]:
		var g := c + ax * ((L2 - overhang) * se)
		var wl := g - aw * (W - overhang)
		var wr := g + aw * (W - overhang)
		var tp := g + Vector3.UP * rise
		_tri_facing(k, wl, wr, tp, wall.darkened(0.06), ax * se)
	k.mat = MeshKit.M_WOOD
	for se: float in [-1.0, 1.0]:
		var gb := c + ax * (L2 * se)
		for sg: float in [-1.0, 1.0]:
			var lo := gb + aw * (W * sg) - Vector3.UP * eave_drop
			var hi := gb + Vector3.UP * rise
			_quad_facing(k, lo, hi, hi - Vector3.UP * 0.3, lo - Vector3.UP * 0.3, TRIM.darkened(0.08), ax * se)
	# ridge cap
	k.mat = MeshKit.M_ROOF
	k.chamfer_box(ridge + Vector3.UP * 0.06, Vector3(L2 * 2.0 + 0.1, 0.18, 0.34) if along_x else Vector3(0.34, 0.18, L2 * 2.0 + 0.1), col.lightened(0.12), 0.06)
	k.mat = 0.0
	if chimneys:
		k.mat = MeshKit.M_BRICK
		for se: float in [-0.6, 0.6]:
			var cp := c + ax * ((L2 - overhang) * se) + aw * ((W - overhang) * 0.35)
			var base_y := y0 + rise * (1.0 - 0.35) - 0.2
			k.chamfer_box(Vector3(cp.x, base_y + 1.1, cp.z), Vector3(1.0, 2.2, 0.8), BRICK.darkened(0.08), 0.05)
			k.mat = MeshKit.M_STONE
			k.chamfer_box(Vector3(cp.x, base_y + 2.25, cp.z), Vector3(1.2, 0.18, 1.0), STONE_TRIM, 0.04)
			k.mat = MeshKit.M_BRICK
		k.mat = 0.0


func _quad_facing(k: MeshKit, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, facing: Vector3) -> void:
	# MeshKit quads are clockwise from the front; flip to face `facing`
	if ((b - a).cross(c - a)).dot(facing) < 0.0:
		k.quad(a, b, c, d, col)
	else:
		k.quad(d, c, b, a, col)


func _tri_facing(k: MeshKit, a: Vector3, b: Vector3, c: Vector3, col: Color, facing: Vector3) -> void:
	if ((b - a).cross(c - a)).dot(facing) < 0.0:
		k.tri(a, b, c, col)
	else:
		k.tri(a, c, b, col)


func _tower(bd: Dictionary, k: MeshKit) -> void:
	var pos: Vector2 = bd["pos"]
	var size: Vector2 = bd["size"]
	var h: float = bd["h"]
	var wall: Color = bd["wall"]
	var roof: Color = bd["roof"]
	var hx := size.x * 0.5
	var base_y: float = bd["base_y"]
	k.mat = MeshKit.M_STONE
	for sx: float in [-1.0, 1.0]:
		k.chamfer_box(Vector3(pos.x + sx * 2.6, base_y * 0.5, pos.y), Vector3(0.8, base_y, size.y), wall.darkened(0.1), 0.08)
	# the arch: a rounded soffit over the pedestrian tunnel
	var arch_pts := 9
	for i in arch_pts:
		var a0 := PI * float(i) / float(arch_pts)
		var a1 := PI * float(i + 1) / float(arch_pts)
		var p0 := Vector3(pos.x + cos(a0) * 2.2, base_y - 0.6 + sin(a0) * 0.6, pos.y)
		var p1 := Vector3(pos.x + cos(a1) * 2.2, base_y - 0.6 + sin(a1) * 0.6, pos.y)
		k.quad(p1 + Vector3(0, 0, -size.y * 0.5), p0 + Vector3(0, 0, -size.y * 0.5), p0 + Vector3(0, 0, size.y * 0.5), p1 + Vector3(0, 0, size.y * 0.5), wall.darkened(0.25))
	k.mat = MeshKit.M_STONE
	k.box(Vector3(pos.x, (base_y + h) * 0.5, pos.y), Vector3(size.x, h - base_y, size.y), wall)
	# string courses and a belfry band
	for yy in [base_y + 0.4, h - 6.4, h - 1.6]:
		k.chamfer_box(Vector3(pos.x, yy, pos.y), Vector3(size.x + 0.5, 0.35, size.y + 0.5), wall.lightened(0.15), 0.08)
	for face: Vector3 in [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
		var cpos: Vector3 = Vector3(pos.x, h - 4.0, pos.y) + face * (hx + 0.08)
		var right := Vector3.UP.cross(face).normalized()
		# clock face: glowing disc with a dark bezel
		k.mat = MeshKit.M_PLAIN
		for i in 24:
			var a0 := TAU * float(i) / 24.0
			var a1 := TAU * float(i + 1) / 24.0
			var q0 := cpos + (right * cos(a0) + Vector3.UP * sin(a0)) * 1.8
			var q1 := cpos + (right * cos(a1) + Vector3.UP * sin(a1)) * 1.8
			var o0 := cpos + (right * cos(a0) + Vector3.UP * sin(a0)) * 2.05 - face * 0.03
			var o1 := cpos + (right * cos(a1) + Vector3.UP * sin(a1)) * 2.05 - face * 0.03
			_tri_facing(k, cpos, q0, q1, Color(0.98, 0.94, 0.78), face)
			k.mat = MeshKit.M_METAL
			_quad_facing(k, q0, q1, o1, o0, Color(0.22, 0.20, 0.18), face)
			k.mat = MeshKit.M_PLAIN
		k.cu_emission_last(24 * 3, 0.9)
		# hour marks and hands pointing to 3:00
		k.mat = MeshKit.M_METAL
		for i in 12:
			var a := TAU * float(i) / 12.0
			k.box(cpos + face * 0.04 + (right * cos(a) + Vector3.UP * sin(a)) * 1.55, Vector3(0.12, 0.12, 0.12), Color(0.15, 0.13, 0.12))
		k.box(cpos + face * 0.05 + right * 0.55, Vector3(1.1, 0.18, 0.18).abs() if face.x == 0 else Vector3(0.18, 0.18, 1.1), Color(0.1, 0.1, 0.15))
		k.box(cpos + face * 0.06 + Vector3.UP * 0.75, Vector3(0.14, 1.5, 0.14), Color(0.1, 0.1, 0.15))
		k.mat = 0.0
	# copper spire: a curved, flared roof with a lantern finial
	k.mat = MeshKit.M_ROOF
	var prof := PackedVector2Array([Vector2(4.3, 0.0), Vector2(4.5, -0.2), Vector2(3.6, 0.6), Vector2(2.4, 2.4), Vector2(1.3, 4.8), Vector2(0.55, 7.0), Vector2(0.12, 8.2)])
	var cols := PackedColorArray([roof.darkened(0.3), roof.darkened(0.2), roof, roof.lightened(0.04), roof.lightened(0.08), roof.lightened(0.1), roof.lightened(0.12)])
	k.revolve(Vector3(pos.x, h, pos.y), prof, cols, 4, PackedFloat32Array(), 0.0, PI * 0.25)
	k.mat = 0.0
	k.soft_blob(Vector3(pos.x, h + 8.4, pos.y), Vector3(0.35, 0.35, 0.35), Color(1.0, 0.85, 0.4), 3, 8, 0.0, 0.0, 0, 1.5)


func _shed(bd: Dictionary, k: MeshKit) -> void:
	var pos: Vector2 = bd["pos"]
	var size: Vector2 = bd["size"]
	var h: float = bd["h"]
	var wall: Color = bd["wall"]
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	k.mat = MeshKit.M_WOOD
	k.box(Vector3(pos.x, h * 0.5, pos.y - hz + 0.3), Vector3(size.x, h, 0.6), wall)
	k.box(Vector3(pos.x - hx + 0.3, h * 0.5, pos.y), Vector3(0.6, h, size.y), wall)
	k.box(Vector3(pos.x + hx - 0.3, h * 0.5, pos.y), Vector3(0.6, h, size.y), wall)
	k.mat = 0.0
	roof_gable(k, pos, size, h, 2.0, bd["roof"], 0.6, wall, false)
	k.mat = MeshKit.M_ASPHALT
	k.quad(Vector3(pos.x - hx + 0.6, 0.06, pos.y - hz + 0.6), Vector3(pos.x + hx - 0.6, 0.06, pos.y - hz + 0.6), Vector3(pos.x + hx - 0.6, 0.06, pos.y + hz), Vector3(pos.x - hx + 0.6, 0.06, pos.y + hz), Color(0.3, 0.3, 0.32))
	k.mat = 0.0
	# sign + warm work light
	k.box(Vector3(pos.x, h + 0.2, pos.y + hz + 0.4), Vector3(9.0, 1.4, 0.2), Color(0.95, 0.75, 0.25))
	k.box(Vector3(pos.x, h + 0.2, pos.y + hz + 0.52), Vector3(8.0, 0.25, 0.05), Color(0.2, 0.15, 0.1))
	B.glow_disc(Vector3(pos.x, 0.12, pos.y + hz + 2.0), 9.0)
	k.blob(Vector3(pos.x, h - 0.6, pos.y + hz - 0.4), Vector3(0.5, 0.25, 0.5), Color(1.0, 0.9, 0.6), 2, 6, 2.0)


func _observatory(bd: Dictionary, k: MeshKit) -> void:
	var pos: Vector2 = bd["pos"]
	var size: Vector2 = bd["size"]
	var h: float = bd["h"]
	var wall: Color = bd["wall"]
	var roof: Color = bd["roof"]
	var hx := size.x * 0.5
	k.mat = MeshKit.M_STONE
	k.revolve(Vector3(pos.x, 0, pos.y), PackedVector2Array([Vector2(hx + 0.35, 0.0), Vector2(hx + 0.3, 0.6), Vector2(hx, 0.7), Vector2(hx, h - 0.4),
		Vector2(hx + 0.3, h - 0.3), Vector2(hx + 0.3, h)]), PackedColorArray([wall.darkened(0.3), wall.darkened(0.2), wall, wall, wall.lightened(0.2), wall.lightened(0.22)]), 24)
	var dome := PackedVector2Array()
	var dcol := PackedColorArray()
	for di in 9:
		var a := PI * 0.5 * float(di) / 8.0
		dome.append(Vector2(hx * cos(a), h + hx * 0.85 * sin(a)))
		dcol.append(roof.lightened(0.04 * float(di)))
	k.mat = MeshKit.M_METAL
	k.revolve(Vector3(pos.x, 0, pos.y), dome, dcol, 24, PackedFloat32Array(), 0.15)
	k.mat = 0.0
	k.box(Vector3(pos.x, h + hx * 0.4, pos.y + 1.0), Vector3(1.2, 2.2, hx * 1.6), Color(0.12, 0.14, 0.25))


## A readable entrance on the face toward the campus centre: a lit door with
## a transom, a bracketed porch roof (no posts: the colliders are the
## building's), a low step, a lantern each side and a name board.
func _entrance(bd: Dictionary, k: MeshKit, roof: Color) -> void:
	var pos: Vector2 = bd["pos"]
	var size: Vector2 = bd["size"]
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var to_c := (Vector2.ZERO - pos)
	var face_n := Vector2(signf(to_c.x), 0) if absf(to_c.x) * size.y > absf(to_c.y) * size.x else Vector2(0, signf(to_c.y))
	var fp := pos + face_n * (Vector2(hx, hz) * face_n.abs()).length()
	var right4 := Vector3(face_n.y, 0, -face_n.x)
	var nrm4 := Vector3(face_n.x, 0, face_n.y)
	var base4 := Vector3(fp.x, 0, fp.y) + nrm4 * 0.08
	var pyaw := atan2(-right4.z, right4.x)
	# door: dark recess, two leaves with glazing, lit transom
	k.mat = MeshKit.M_PLAIN
	_quad_facing(k, base4 - right4 * 1.15 + Vector3.UP * 2.75, base4 + right4 * 1.15 + Vector3.UP * 2.75, base4 + right4 * 1.15, base4 - right4 * 1.15, Color(0.1, 0.09, 0.1), nrm4)
	k.mat = MeshKit.M_WOOD
	for side: float in [-1.0, 1.0]:
		var dc := base4 + right4 * (0.5 * side) + nrm4 * 0.02
		_quad_facing(k, dc - right4 * 0.46 + Vector3.UP * 2.2, dc + right4 * 0.46 + Vector3.UP * 2.2, dc + right4 * 0.46, dc - right4 * 0.46, Color(0.40, 0.25, 0.17), nrm4)
	k.mat = MeshKit.M_GLASS
	for side: float in [-1.0, 1.0]:
		var gc := base4 + right4 * (0.5 * side) + nrm4 * 0.03 + Vector3.UP * 1.55
		_quad_facing(k, gc - right4 * 0.28 + Vector3.UP * 0.42, gc + right4 * 0.28 + Vector3.UP * 0.42, gc + right4 * 0.28 - Vector3.UP * 0.42, gc - right4 * 0.28 - Vector3.UP * 0.42, Color(1.0, 0.82, 0.52), nrm4)
	var tc := base4 + nrm4 * 0.03 + Vector3.UP * 2.48
	_quad_facing(k, tc - right4 * 0.95 + Vector3.UP * 0.2, tc + right4 * 0.95 + Vector3.UP * 0.2, tc + right4 * 0.95 - Vector3.UP * 0.2, tc - right4 * 0.95 - Vector3.UP * 0.2, Color(1.0, 0.84, 0.55), nrm4)
	k.cu_emission_last(18, 1.1)
	k.mat = MeshKit.M_STONE
	var trim := TRIM
	# surround, porch roof on brackets, step
	for side: float in [-1.0, 1.0]:
		k.chamfer_box(base4 + right4 * (1.28 * side) + Vector3.UP * 1.45 + nrm4 * 0.06, Vector3(0.24, 2.9, 0.16), STONE_TRIM, 0.04, pyaw)
	k.chamfer_box(base4 + Vector3.UP * 2.98 + nrm4 * 0.07, Vector3(2.9, 0.3, 0.2), STONE_TRIM.lightened(0.05), 0.05, pyaw)
	k.mat = MeshKit.M_WOOD
	k.chamfer_box(base4 + nrm4 * 1.0 + Vector3.UP * 3.25, Vector3(3.6, 0.22, 2.2), trim, 0.06, pyaw, trim.lightened(0.04))
	k.mat = MeshKit.M_ROOF
	k.chamfer_box(base4 + nrm4 * 1.0 + Vector3.UP * 3.48, Vector3(3.3, 0.26, 1.95), Color(roof.r, roof.g, roof.b).lightened(0.05), 0.1, pyaw)
	k.mat = MeshKit.M_WOOD
	for side: float in [-1.0, 1.0]:
		k.chamfer_box(base4 + nrm4 * 0.45 + right4 * (1.5 * side) + Vector3.UP * 2.9, Vector3(0.16, 0.6, 0.9), trim.darkened(0.08), 0.04, pyaw)
	k.mat = MeshKit.M_STONE
	k.chamfer_box(Vector3(fp.x, 0.05, fp.y) + nrm4 * 0.9, Vector3(3.4, 0.1, 1.6), Color(0.72, 0.7, 0.72), 0.04, pyaw, Color(0.8, 0.78, 0.8))
	k.mat = 0.0
	# wall lanterns either side
	for side: float in [-1.0, 1.0]:
		_wall_lantern(base4 + right4 * (1.75 * side) + Vector3.UP * 2.2, nrm4)
	B.glow_disc(Vector3(fp.x + face_n.x * 1.8, 0.11, fp.y + face_n.y * 1.8), 4.2)


func _wall_lantern(p: Vector3, nrm: Vector3) -> void:
	var kd := _k(p.x, p.z, true)
	kd.mat = MeshKit.M_METAL
	kd.box(p + nrm * 0.12 + Vector3.UP * 0.05, Vector3(0.08, 0.08, 0.08) + nrm.abs() * 0.18, IRON)
	kd.revolve(p + nrm * 0.24 - Vector3.UP * 0.2, PackedVector2Array([Vector2(0.05, 0.0), Vector2(0.12, 0.04), Vector2(0.12, 0.3), Vector2(0.16, 0.34), Vector2(0.02, 0.46)]),
		PackedColorArray([IRON, IRON, IRON, IRON.lightened(0.1), IRON]), 6)
	kd.mat = MeshKit.M_GLASS
	kd.revolve(p + nrm * 0.24 - Vector3.UP * 0.16, PackedVector2Array([Vector2(0.1, 0.0), Vector2(0.1, 0.24)]), PackedColorArray([Color(1.0, 0.85, 0.55)]), 6, PackedFloat32Array(), 2.0)
	kd.mat = 0.0


## The dorm: four doors (lit, trimmed, with porch hoods and steps), house
## banners, a canopy over the front door and a crest.
func _dorm_extras(bd: Dictionary, k: MeshKit) -> void:
	var pos: Vector2 = bd["pos"]
	var size: Vector2 = bd["size"]
	var h: float = bd["h"]
	var hz := size.y * 0.5
	for dd in L.dorm_doors:
		var dp: Vector2 = dd["pos"]
		var n: Vector2 = dd["normal"]
		var right3 := Vector3(n.y, 0, -n.x)
		var nn3 := Vector3(n.x, 0, n.y)
		var base := Vector3(dp.x, 0, dp.y) + nn3 * 0.08
		var door_yaw := -atan2(-right3.z, right3.x)
		k.mat = MeshKit.M_PLAIN
		_quad_facing(k, base - right3 * 1.25 + Vector3.UP * 2.95, base + right3 * 1.25 + Vector3.UP * 2.95, base + right3 * 1.25, base - right3 * 1.25, Color(0.1, 0.08, 0.09), nn3)
		k.mat = MeshKit.M_WOOD
		k.box(base + Vector3.UP * 1.15 + nn3 * 0.01, Vector3(2.3, 2.3, 0.08), Color(0.36, 0.22, 0.16), -door_yaw)
		k.mat = MeshKit.M_GLASS
		for side: float in [-1.0, 1.0]:
			k.box(base + right3 * (0.56 * side) + Vector3.UP * 1.62 + nn3 * 0.06, Vector3(0.5, 0.62, 0.03), Color(1.0, 0.78, 0.45), -door_yaw, 1.3)
		k.box(base + Vector3.UP * 2.56 + nn3 * 0.05, Vector3(2.2, 0.4, 0.03), Color(1.0, 0.8, 0.5), -door_yaw, 1.5)
		k.mat = MeshKit.M_METAL
		for side: float in [-1.0, 1.0]:
			k.box(base + right3 * (0.16 * side) + Vector3.UP * 1.05 + nn3 * 0.09, Vector3(0.06, 0.14, 0.05), Color(0.95, 0.8, 0.4), -door_yaw)
		k.mat = MeshKit.M_STONE
		for side2: float in [-1.0, 1.0]:
			k.chamfer_box(base + right3 * (1.32 * side2) + Vector3.UP * 1.5 + nn3 * 0.08, Vector3(0.28, 3.0, 0.18), TRIM, 0.04, -door_yaw)
		k.chamfer_box(base + Vector3.UP * 3.05 + nn3 * 0.1, Vector3(3.0, 0.3, 0.22), TRIM, 0.05, -door_yaw)
		# porch hood on brackets
		k.mat = MeshKit.M_ROOF
		k.chamfer_box(base + Vector3.UP * 3.4 + nn3 * 0.75, Vector3(3.4, 0.24, 3.4) * Vector3(absf(right3.x) + absf(n.x) * 0.45, 1, absf(right3.z) + absf(n.y) * 0.45), Color(0.30, 0.34, 0.50), 0.08)
		k.mat = MeshKit.M_WOOD
		for side3: float in [-1.0, 1.0]:
			k.chamfer_box(base + right3 * (1.5 * side3) + Vector3.UP * 3.05 + nn3 * 0.45, Vector3(0.16, 0.55, 0.16) + Vector3(absf(nn3.x), 0, absf(nn3.z)) * 0.7, TRIM.darkened(0.08), 0.04)
		k.mat = MeshKit.M_STONE
		k.chamfer_box(Vector3(dp.x, 0.05, dp.y) + nn3 * 0.62, Vector3(3.1, 0.1, 3.1) * Vector3(absf(right3.x) + absf(n.x) * 0.4, 1, absf(right3.z) + absf(n.y) * 0.4), Color(0.72, 0.70, 0.74), 0.04, 0.0, Color(0.80, 0.78, 0.82))
		k.mat = 0.0
		k.soft_blob(base + Vector3.UP * 3.15 + nn3 * 0.35, Vector3(0.24, 0.28, 0.24), Color(1.0, 0.85, 0.5), 3, 8, 0.0, 0.0, 0, 2.5)
		B.glow_disc(Vector3(dp.x + n.x * 2.0, 0.11, dp.y + n.y * 2.0), 5.0)
		# a welcome mat in house red
		k.mat = MeshKit.M_PLAIN
		k.quad(Vector3(dp.x, 0.09, dp.y) + nn3 * 0.3 - right3 * 1.0, Vector3(dp.x, 0.09, dp.y) + nn3 * 0.3 + right3 * 1.0, Vector3(dp.x, 0.09, dp.y) + nn3 * 1.6 + right3 * 1.0, Vector3(dp.x, 0.09, dp.y) + nn3 * 1.6 - right3 * 1.0, Color(0.72, 0.24, 0.24))
		k.mat = 0.0
	# hanging house banners either side of the front door (blue + gold duck crest colours)
	for bx: float in [-4.5, 4.5]:
		k.mat = MeshKit.M_PLAIN
		k.box(Vector3(pos.x + bx, h - 3.2, pos.y - hz - 0.12), Vector3(1.6, 4.2, 0.1), Color(0.24, 0.32, 0.78))
		k.box(Vector3(pos.x + bx, h - 4.6, pos.y - hz - 0.18), Vector3(0.9, 0.9, 0.06), Color(1.0, 0.8, 0.25), 0.0, 0.3)
		k.mat = MeshKit.M_METAL
		k.box(Vector3(pos.x + bx, h - 1.05, pos.y - hz - 0.2), Vector3(1.9, 0.08, 0.08), Color(0.85, 0.7, 0.35))
	k.mat = 0.0


# ---------------------------------------------------------------------------
# Walls, hedges, fences, bollards
# ---------------------------------------------------------------------------
func walls() -> void:
	for s in L.walls:
		var a: Vector2 = s["a"]
		var b: Vector2 = s["b"]
		var k := _k((a.x + b.x) * 0.5, (a.y + b.y) * 0.5)
		var d := b - a
		var mid := (a + b) * 0.5
		var h: float = s["h"]
		var t: float = s["t"]
		var yaw := atan2(-d.y, d.x)
		# dressed stone body with a rounded coping
		k.mat = MeshKit.M_STONE
		k.chamfer_box(Vector3(mid.x, (h - 0.1) * 0.5, mid.y), Vector3(d.length() + t, h - 0.1, t), Color(0.50, 0.48, 0.53), 0.05, yaw)
		k.chamfer_box(Vector3(mid.x, h - 0.06, mid.y), Vector3(d.length() + t + 0.1, 0.14, t + 0.12), Color(0.68, 0.66, 0.70), 0.06, yaw)
		k.mat = 0.0


## A stretch [t0, t1] of one hedge (long boundary hedges take several steps).
func hedge_part(i: int, t0: float, t1: float) -> void:
	var s: Dictionary = L.hedges[i]
	var a0: Vector2 = s["a"]
	var b0: Vector2 = s["b"]
	_hedge_piece(s, a0.lerp(b0, t0), a0.lerp(b0, t1), t1 >= 0.999)


func _hedge_piece(s: Dictionary, a: Vector2, b: Vector2, last: bool) -> void:
	var k := _k((a.x + b.x) * 0.5, (a.y + b.y) * 0.5)
	var h: float = s["h"]
	var t: float = s["t"]
	var col := Color(0.18, 0.40, 0.23)
	var d2 := b - a
	var mid := (a + b) * 0.5
	var L2 := a.distance_to(b)
	k.mat = MeshKit.M_LEAF
	# a clipped body with soft edges and a row of rounded tops
	k.chamfer_box(Vector3(mid.x, (h - 0.25) * 0.5, mid.y), Vector3(L2 + t * 0.2, h - 0.25, t), col.darkened(0.08), 0.18, atan2(-d2.y, d2.x), col.lightened(0.04))
	var n := int(L2 / 1.4)
	for i in (n + 1 if last else n):
		var p := a.lerp(b, float(i) / float(max(n, 1)))
		k.soft_blob(Vector3(p.x, h - 0.3, p.y), Vector3(t * 0.6, 0.42, t * 0.6), col.lightened(0.04 + 0.05 * float(i % 2)), 3, 7, 0.25)
	k.mat = 0.0


func fence(i: int) -> void:
	_fence(L.fences[i])


func bollards(from: int, to: int) -> void:
	for i in range(from, mini(to, L.cart_blockers.size())):
		_bollards(L.cart_blockers[i])


func _fence(s: Dictionary) -> void:
	var a: Vector2 = s["a"]
	var b: Vector2 = s["b"]
	var h: float = s["h"]
	var kind: String = s["kind"]
	var k := _k((a.x + b.x) * 0.5, (a.y + b.y) * 0.5)
	var L2 := a.distance_to(b)
	if kind == "buoy":
		k.segment_box(a, b, -0.35, 0.05, 0.05, Color(0.9, 0.9, 0.85))
		var n := int(L2 / 1.2)
		for i in n + 1:
			var p := a.lerp(b, float(i) / float(max(n, 1)))
			k.soft_blob(Vector3(p.x, -0.3, p.y), Vector3(0.28, 0.24, 0.28), Color(0.95, 0.25, 0.2) if i % 2 == 0 else Color(0.95, 0.95, 0.9), 3, 7)
		return
	if kind == "iron":
		k.mat = MeshKit.M_METAL
		var step := 2.0
		var n2 := int(L2 / step)
		for i in n2 + 1:
			var p2 := a.lerp(b, float(i) / float(max(n2, 1)))
			# square posts with ball finials
			k.box(Vector3(p2.x, h * 0.5, p2.y), Vector3(0.12, h, 0.12), IRON)
			k.soft_blob(Vector3(p2.x, h + 0.06, p2.y), Vector3(0.09, 0.09, 0.09), IRON.lightened(0.15), 2, 6)
		k.segment_box(a, b, h - 0.14, 0.07, 0.07, IRON)
		k.segment_box(a, b, 0.3, 0.07, 0.07, IRON)
		var bars := int(L2 / 0.22)
		var kd := _k((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, true)
		kd.mat = MeshKit.M_METAL
		for i in bars:
			var p3 := a.lerp(b, (float(i) + 0.5) / float(bars))
			kd.box(Vector3(p3.x, h * 0.5 - 0.02, p3.y), Vector3(0.035, h - 0.18, 0.035), IRON)
		kd.mat = 0.0
		k.mat = 0.0
		return
	# split-rail / lake rail: weathered wood posts with two rails
	var post_col := Color(0.45, 0.32, 0.22)
	k.mat = MeshKit.M_WOOD
	var n3 := int(L2 / 2.4)
	for i in n3 + 1:
		var p4 := a.lerp(b, float(i) / float(max(n3, 1)))
		k.chamfer_box(Vector3(p4.x, h * 0.5, p4.y), Vector3(0.16, h, 0.16), post_col, 0.03)
	k.segment_box(a, b, h * 0.45, 0.12, 0.12, post_col.lightened(0.1))
	k.segment_box(a, b, h * 0.85, 0.12, 0.12, post_col.lightened(0.1))
	k.mat = 0.0


func _bollards(s: Dictionary) -> void:
	if bool(s.get("hidden", false)):
		return   # V6: a dorm doorway's cart stop (its threshold is drawn by ClassicDormArt)
	var a: Vector2 = s["a"]
	var b: Vector2 = s["b"]
	var L2 := a.distance_to(b)
	var n := int(ceil(L2 / 2.0))
	var grey := Color(0.32, 0.33, 0.38)
	var band := Color(1.0, 0.82, 0.25)
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(max(n, 1)))
		var k := _k(p.x, p.y, true)
		k.mat = MeshKit.M_METAL
		# rounded-top bollard with a reflective band
		k.revolve(Vector3(p.x, 0, p.y), PackedVector2Array([Vector2(0.15, 0.0), Vector2(0.13, 0.6)]),
			PackedColorArray([grey.darkened(0.35), grey]), 7)
		k.revolve(Vector3(p.x, 0, p.y), PackedVector2Array([Vector2(0.135, 0.6), Vector2(0.135, 0.72)]), PackedColorArray([band]), 7, PackedFloat32Array(), 0.6)
		k.revolve(Vector3(p.x, 0, p.y), PackedVector2Array([Vector2(0.13, 0.72), Vector2(0.11, 0.87), Vector2(0.0, 0.93)]),
			PackedColorArray([grey, grey.lightened(0.1), grey.lightened(0.15)]), 7)
		k.mat = 0.0


# ---------------------------------------------------------------------------
# Lamps (three styles as navigation cues), benches, props
# ---------------------------------------------------------------------------
## Lamp style by place: twin-globe lamps around the fountain and the dorm
## (the heart of the campus), rustic post lanterns on the gravel trails and
## the woods, the classic cast-iron lamp everywhere else.  Collider: the
## same 0.14 m post in every style.
func lamps(from: int = 0, to: int = 1 << 30) -> void:
	for lp in L.lamps.slice(from, mini(to, L.lamps.size())):
		var style := 0
		if lp.distance_to(Vector2(0, 22)) < 20.0 or (lp.y > 88.0 and absf(lp.x) < 40.0):
			style = 1
		elif L.is_on_path(lp, 2.6) and not _near_stone_path(lp):
			style = 2
		_lamp(lp, style)


func _near_stone_path(p: Vector2) -> bool:
	for pth in L.paths:
		if not (pth["color"] as Color).is_equal_approx(Color(0.62, 0.56, 0.46)):
			var pts: PackedVector2Array = pth["pts"]
			for i in pts.size() - 1:
				if ClassicLayout._dist_to_segment(p, pts[i], pts[i + 1]) <= float(pth["w"]) * 0.5 + 2.6:
					return true
	return false


func _lamp(lp: Vector2, style: int) -> void:
	var k := _k(lp.x, lp.y, true)
	var b := Vector3(lp.x, 0, lp.y)
	k.mat = MeshKit.M_METAL
	if style == 2:
		# a timber post with a hanging lantern
		k.mat = MeshKit.M_WOOD
		k.chamfer_box(b + Vector3(0, 1.4, 0), Vector3(0.18, 2.8, 0.18), Color(0.40, 0.29, 0.20), 0.03)
		k.chamfer_box(b + Vector3(0.28, 2.72, 0), Vector3(0.7, 0.12, 0.12), Color(0.40, 0.29, 0.20), 0.02)
		k.mat = MeshKit.M_METAL
		k.revolve(b + Vector3(0.52, 2.08, 0), PackedVector2Array([Vector2(0.08, 0.0), Vector2(0.16, 0.06), Vector2(0.16, 0.08)]), PackedColorArray([IRON]), 6)
		k.revolve(b + Vector3(0.52, 2.44, 0), PackedVector2Array([Vector2(0.18, 0.0), Vector2(0.06, 0.16), Vector2(0.02, 0.24)]), PackedColorArray([IRON, IRON.lightened(0.1), IRON]), 6)
		k.mat = MeshKit.M_GLASS
		k.revolve(b + Vector3(0.52, 2.14, 0), PackedVector2Array([Vector2(0.13, 0.0), Vector2(0.15, 0.15), Vector2(0.13, 0.3)]), PackedColorArray([Color(1.0, 0.72, 0.42)]), 6, PackedFloat32Array(), 1.15)
		k.mat = 0.0
		B.glow_disc(Vector3(lp.x + 0.5, 0.1, lp.y), 3.6)
		return
	# a turned cast-iron post: stepped base, slim fluted shaft, collar
	k.revolve(b, PackedVector2Array([Vector2(0.27, 0.0), Vector2(0.26, 0.12), Vector2(0.17, 0.2), Vector2(0.16, 0.36), Vector2(0.09, 0.46),
		Vector2(0.075, 3.0), Vector2(0.12, 3.12), Vector2(0.16, 3.22), Vector2(0.06, 3.3)]),
		PackedColorArray([IRON.darkened(0.3), IRON.darkened(0.2), IRON, IRON, IRON, IRON.lightened(0.05), IRON.lightened(0.08), IRON.lightened(0.08), IRON]), 10)
	if style == 1:
		# twin globes on a curled cross-arm
		k.chamfer_box(b + Vector3(0, 3.36, 0), Vector3(1.1, 0.08, 0.08), IRON, 0.02)
		for sx: float in [-0.55, 0.55]:
			k.mat = MeshKit.M_GLASS
			k.soft_blob(b + Vector3(sx, 3.62, 0), Vector3(0.2, 0.22, 0.2), Color(1.0, 0.78, 0.48), 4, 10, 0.0, 0.0, 0, 1.0)
			k.mat = MeshKit.M_METAL
			k.revolve(b + Vector3(sx, 3.36, 0), PackedVector2Array([Vector2(0.03, 0.0), Vector2(0.1, 0.06), Vector2(0.1, 0.1)]), PackedColorArray([IRON]), 8)
			k.revolve(b + Vector3(sx, 3.8, 0), PackedVector2Array([Vector2(0.12, 0.0), Vector2(0.03, 0.08), Vector2(0.0, 0.14)]), PackedColorArray([IRON]), 8)
		k.mat = 0.0
		B.glow_disc(Vector3(lp.x, 0.1, lp.y), 5.0)
		return
	# glass lantern (warm, emissive) with a rounded cap and finial
	k.mat = MeshKit.M_GLASS
	k.revolve(b, PackedVector2Array([Vector2(0.06, 3.3), Vector2(0.2, 3.36), Vector2(0.27, 3.62), Vector2(0.24, 3.76)]),
		PackedColorArray([Color(1.0, 0.74, 0.44)]), 8, PackedFloat32Array(), 1.05)
	k.mat = MeshKit.M_METAL
	k.revolve(b, PackedVector2Array([Vector2(0.24, 3.74), Vector2(0.4, 3.8), Vector2(0.24, 3.94), Vector2(0.05, 4.12), Vector2(0.0, 4.16)]),
		PackedColorArray([IRON, IRON.lightened(0.1), IRON.lightened(0.12), IRON, IRON]), 8)
	k.mat = 0.0
	B.glow_disc(Vector3(lp.x, 0.1, lp.y), 4.4)


## part 0: quarry boulders and platforms, 1: ramps and benches, 2: props
func small_things(part: int = -1) -> void:
	if part == 0 or part < 0:
		_rocks_and_platforms()
	if part == 1 or part < 0:
		for rp2 in L.ramps:
			_ramp_visual(rp2)
		for bn in L.benches:
			_bench(bn)
	if part == 2 or part < 0:
		for pr in L.props:
			_prop(pr)


func _rocks_and_platforms() -> void:
	# quarry boulders: the kit's layered rock fitted to each collider box
	for r in L.rocks:
		var rp: Vector3 = r["pos"]
		var sz: Vector3 = r["size"]
		var xf := Transform3D(Basis(Vector3.UP, float(r["rot"])).scaled(sz * Vector3(1.04, 1.0, 1.04)), rp)
		var sd := int(rp.x * 13 + rp.z * 7)
		var tint := Color(1, 1, 1).lerp(Color(0.92, 0.94, 1.0), float(posmod(sd, 5)) / 4.0)
		B._mm_add(B._decor, ClassicBuilder.coarse_key(rp.x, rp.z), "rock_layer" if posmod(sd, 3) != 0 else "rock_round", xf, tint, Color(1, 1, 1))
	for p in L.platforms:
		var pc: Vector3 = p["center"]
		var ps: Vector3 = p["size"]
		var k2 := _k(pc.x, pc.z)
		if p.get("dock", false):
			_dock(p, k2)
		else:
			k2.mat = MeshKit.M_STONE
			k2.chamfer_box(pc - Vector3(0, ps.y * 0.5, 0) + Vector3(0, ps.y * 0.5, 0), ps, p["color"], 0.08)
			k2.mat = MeshKit.M_ROCK
			k2.box(Vector3(pc.x, pc.y * 0.5 - 0.3, pc.z), Vector3(ps.x * 0.9, pc.y, ps.z * 0.9), Color(0.45, 0.43, 0.48))
			k2.mat = 0.0


## The inlet dock: planks with gaps over stringers, pilings with caps that
## stand proud of the deck only at its corners and outer end, a cleat or
## two and a mooring rope - the deck itself stays clear to run and jump.
func _dock(p: Dictionary, k: MeshKit) -> void:
	var pc: Vector3 = p["center"]
	var ps: Vector3 = p["size"]
	var top := pc.y + ps.y * 0.5
	var wood := Color(0.55, 0.40, 0.28)
	k.mat = MeshKit.M_WOOD
	# stringers under the deck
	for sx: float in [-1.0, 1.0]:
		k.box(Vector3(pc.x + sx * ps.x * 0.38, top - 0.28, pc.z), Vector3(0.18, 0.24, ps.z), wood.darkened(0.4))
	var n := int(ps.z / 0.42)
	for i in n:
		var z := pc.z - ps.z * 0.5 + (float(i) + 0.5) * ps.z / float(n)
		var tone := wood.lerp(wood.darkened(0.18), float(posmod(i * 7, 5)) / 4.0)
		k.box(Vector3(pc.x, top - 0.05, z), Vector3(ps.x, 0.1, ps.z / float(n) - 0.05), tone, 0.0, 0.0, tone.lightened(0.05))
	# pilings
	for zz in range(int(-ps.z * 0.5), int(ps.z * 0.5) + 1, 3):
		for sx: float in [-1.0, 1.0]:
			var tall := absf(float(zz)) >= ps.z * 0.5 - 1.0 and (zz < 0 or true)
			var py := top + (0.45 if tall else -0.02)
			k.revolve(Vector3(pc.x + sx * (ps.x * 0.5 + 0.12), -1.8, pc.z + zz), PackedVector2Array([Vector2(0.15, 0.0), Vector2(0.15, py + 1.8 - 0.05), Vector2(0.12, py + 1.8)]),
				PackedColorArray([wood.darkened(0.55), wood.darkened(0.3), wood.darkened(0.2)]), 8)
	k.mat = MeshKit.M_METAL
	for zc in [-ps.z * 0.25, ps.z * 0.25]:
		k.box(Vector3(pc.x + ps.x * 0.5 - 0.15, top + 0.05, pc.z + zc), Vector3(0.1, 0.08, 0.36), IRON.lightened(0.2))
	k.mat = 0.0


func _ramp_visual(rp: Dictionary) -> void:
	var from: Vector3 = rp["from"]
	var to: Vector3 = rp["to"]
	var w: float = rp["w"]
	var k := _k(from.x, from.z)
	var d := to - from
	var x_axis := d.normalized()
	var z_axis := x_axis.cross(Vector3.UP).normalized()
	var y_axis := z_axis.cross(x_axis).normalized()
	var basis := Basis(x_axis * d.length(), y_axis * 0.4, z_axis * w)
	k.mat = MeshKit.M_STONE
	k.box_xf(Transform3D(basis, (from + to) * 0.5 - y_axis * 0.2), rp["color"])
	# step ridges
	var n := int(d.length() / 0.7)
	for i in n:
		var p := from.lerp(to, (float(i) + 0.5) / float(n))
		k.box(p + Vector3(0, 0.02, 0), Vector3(0.12, 0.06, w * 0.96), Color(0.7, 0.68, 0.7), atan2(-x_axis.z, x_axis.x))
	k.mat = 0.0


func _bench(bn: Dictionary) -> void:
	var p: Vector2 = bn["pos"]
	var yaw: float = bn["rot"]
	var k := _k(p.x, p.y, true)
	var wood := Color(0.66, 0.45, 0.29)
	var b := Basis(Vector3.UP, yaw)
	k.mat = MeshKit.M_WOOD
	# three seat slats and two back slats on cast-iron ends with armrests
	for i in 3:
		k.chamfer_box(Vector3(p.x, 0.46, p.y) + b * Vector3(0, 0, -0.17 + 0.17 * float(i)), Vector3(1.9, 0.06, 0.14), wood.darkened(0.04 * float(i)), 0.025, yaw, wood.lightened(0.06))
	for j in 2:
		k.chamfer_box(Vector3(p.x, 0.7 + 0.2 * float(j), p.y) + b * Vector3(0, 0, 0.3), Vector3(1.9, 0.12, 0.05), wood, 0.02, yaw, wood.lightened(0.06))
	k.mat = MeshKit.M_METAL
	for sx: float in [-0.86, 0.86]:
		var off := b * Vector3(sx, 0, 0)
		k.box(Vector3(p.x, 0.22, p.y) + off, Vector3(0.08, 0.45, 0.55), IRON, yaw)
		k.box(Vector3(p.x, 0.66, p.y) + off + b * Vector3(0, 0, 0.27), Vector3(0.08, 0.5, 0.08), IRON, yaw)
		k.chamfer_box(Vector3(p.x, 0.66, p.y) + off + b * Vector3(0, 0, 0.02), Vector3(0.09, 0.05, 0.5), IRON, 0.02, yaw)
	k.mat = 0.0


func _prop(pr: Dictionary) -> void:
	var p: Vector2 = pr["pos"]
	var k := _k(p.x, p.y)
	match String(pr["kind"]):
		"bike_rack":
			k.mat = MeshKit.M_METAL
			for i in 4:
				# hoops
				var cx := p.x - 1.5 + float(i)
				var prof := PackedVector2Array()
				for s in 7:
					var a := PI * float(s) / 6.0
					prof.append(Vector2(cos(a) * 0.32, sin(a) * 0.32 + 0.45))
				for s in 6:
					var a0 := Vector3(cx, prof[s].y, p.y + prof[s].x)
					var a1 := Vector3(cx, prof[s + 1].y, p.y + prof[s + 1].x)
					k.box((a0 + a1) * 0.5, Vector3(0.05, maxf(absf(a1.y - a0.y), 0.05), maxf(absf(a1.z - a0.z), 0.05)), Color(0.55, 0.6, 0.7))
				for sz: float in [-0.32, 0.32]:
					k.box(Vector3(cx, 0.22, p.y + sz), Vector3(0.05, 0.45, 0.05), Color(0.55, 0.6, 0.7))
			k.mat = 0.0
		"noticeboard":
			k.mat = MeshKit.M_WOOD
			k.chamfer_box(Vector3(p.x, 1.3, p.y), Vector3(2.0, 1.4, 0.15), Color(0.55, 0.4, 0.3), 0.04)
			k.chamfer_box(Vector3(p.x, 2.08, p.y), Vector3(2.3, 0.14, 0.4), Color(0.45, 0.3, 0.22), 0.04)
			for sx: float in [-0.9, 0.9]:
				k.box(Vector3(p.x + sx, 0.6, p.y), Vector3(0.1, 1.2, 0.1), Color(0.45, 0.3, 0.22))
			k.mat = 0.0
			k.box(Vector3(p.x, 1.35, p.y - 0.09), Vector3(1.7, 1.1, 0.02), Color(0.9, 0.85, 0.7), 0.0, 0.15)
			var rng := RandomNumberGenerator.new()
			rng.seed = 9
			for i in 6:
				k.box(Vector3(p.x - 0.6 + 0.24 * float(i), 1.35 + rng.randf_range(-0.3, 0.3), p.y - 0.105), Vector3(0.2, 0.26, 0.01), [Color(1, 0.6, 0.6), Color(0.6, 0.8, 1), Color(1, 0.95, 0.6)][i % 3], 0.0, 0.2)
		"lifeguard":
			k.mat = MeshKit.M_WOOD
			for sx: float in [-0.4, 0.4]:
				for sz: float in [-0.4, 0.4]:
					k.box(Vector3(p.x + sx, 1.0, p.y + sz), Vector3(0.1, 2.0, 0.1), Color(0.95, 0.95, 0.95))
			k.chamfer_box(Vector3(p.x, 1.6, p.y), Vector3(1.0, 0.1, 1.0), Color(0.95, 0.95, 0.95), 0.03)
			k.chamfer_box(Vector3(p.x, 2.0, p.y + 0.4), Vector3(1.0, 0.7, 0.1), Color(0.95, 0.95, 0.95), 0.03)
			k.mat = 0.0
			k.chamfer_box(Vector3(p.x, 2.55, p.y), Vector3(1.4, 0.08, 1.4), Color(0.95, 0.3, 0.25), 0.03)
			k.box(Vector3(p.x, 2.3, p.y), Vector3(0.05, 0.5, 0.05), Color(0.9, 0.9, 0.9))
		"gazebo":
			var cream := Color(0.95, 0.95, 0.92)
			k.mat = MeshKit.M_STONE
			k.revolve(Vector3(p.x, 0, p.y), PackedVector2Array([Vector2(3.3, 0.0), Vector2(3.25, 0.2), Vector2(3.1, 0.28), Vector2(0.0, 0.3)]),
				PackedColorArray([Color(0.7, 0.68, 0.66), Color(0.85, 0.82, 0.78), Color(0.88, 0.85, 0.8), Color(0.88, 0.85, 0.8)]), 12)
			k.mat = MeshKit.M_WOOD
			for i in 6:
				var a := TAU * float(i) / 6.0
				k.revolve(Vector3(p.x + cos(a) * 2.8, 0.28, p.y + sin(a) * 2.8), PackedVector2Array([Vector2(0.16, 0.0), Vector2(0.11, 0.14), Vector2(0.1, 2.4), Vector2(0.16, 2.52)]),
					PackedColorArray([cream.darkened(0.1), cream, cream, cream]), 8)
			# a softly flared roof with a finial
			var rf := Color(0.75, 0.35, 0.45)
			k.mat = MeshKit.M_ROOF
			k.revolve(Vector3(p.x, 2.78, p.y), PackedVector2Array([Vector2(3.0, -0.05), Vector2(3.7, 0.0), Vector2(3.5, 0.18), Vector2(2.2, 0.75), Vector2(0.8, 1.55), Vector2(0.2, 1.9), Vector2(0.0, 2.0)]),
				PackedColorArray([rf.darkened(0.35), rf.darkened(0.1), rf, rf.lightened(0.05), rf.lightened(0.08), rf.lightened(0.1), rf.lightened(0.1)]), 12)
			k.mat = 0.0
			k.soft_blob(Vector3(p.x, 4.85, p.y), Vector3(0.16, 0.2, 0.16), Color(1.0, 0.85, 0.45), 3, 6)
			# a lantern hanging inside
			k.soft_blob(Vector3(p.x, 2.5, p.y), Vector3(0.2, 0.25, 0.2), Color(1.0, 0.82, 0.5), 3, 8, 0.0, 0.0, 0, 2.0)
			B.glow_disc(Vector3(p.x, 0.32, p.y), 3.4)
		"canoe":
			k.soft_blob(Vector3(p.x, 0.2, p.y), Vector3(0.6, 0.25, 2.2), Color(0.85, 0.3, 0.2), 4, 12)
			k.soft_blob(Vector3(p.x, 0.32, p.y), Vector3(0.45, 0.06, 1.9), Color(0.25, 0.16, 0.12), 3, 10)
		"frog":
			# a frog statue on a mossy rock
			k.mat = MeshKit.M_ROCK
			k.soft_blob(Vector3(p.x, 0.2, p.y), Vector3(0.75, 0.32, 0.65), Color(0.42, 0.44, 0.38), 4, 10)
			k.mat = MeshKit.M_PLAIN
			k.soft_blob(Vector3(p.x, 0.68, p.y), Vector3(0.6, 0.42, 0.5), Color(0.32, 0.7, 0.32), 5, 12)
			k.soft_blob(Vector3(p.x, 0.62, p.y - 0.42), Vector3(0.4, 0.2, 0.12), Color(0.85, 0.85, 0.55), 3, 8)
			for sx: float in [-0.25, 0.25]:
				k.soft_blob(Vector3(p.x + sx, 1.02, p.y - 0.28), Vector3(0.17, 0.17, 0.17), Color(1, 1, 1), 3, 8)
				k.soft_blob(Vector3(p.x + sx, 1.04, p.y - 0.4), Vector3(0.07, 0.07, 0.05), Color(0.05, 0.05, 0.05), 2, 6)
			k.mat = 0.0


## Fictional name boards (Label3D, warm cream on a dark board): one at each
## building's main face and wayfinding fingerposts at the main junctions.
## Each label is drawn only near the camera.
const SIGN_FONT := preload("res://assets/fonts/Manrope-Bold.ttf")
func signs() -> void:
	var names_done := {}
	for bd in L.buildings:
		var id := String(bd["id"])
		var nm := String(bd["name"])
		if names_done.has(nm) or id in ["tower", "chapel_e"]:
			continue
		names_done[nm] = true
		var pos: Vector2 = bd["pos"]
		var size: Vector2 = bd["size"]
		var h: float = bd["h"]
		var to_c := (Vector2.ZERO - pos)
		var face_n := Vector2(signf(to_c.x), 0) if absf(to_c.x) * size.y > absf(to_c.y) * size.x else Vector2(0, signf(to_c.y))
		if id == "dorm" or bd.has("dorm_id"):
			face_n = Vector2(0, -1)
		if id == "chapel_w":
			pos = Vector2(0, -30)
			size = Vector2(22, 14)
			face_n = Vector2(0, 1)
		var fp := pos + face_n * (Vector2(size.x, size.y) * 0.5 * face_n.abs()).length()
		var y := minf(h - 1.4, 4.4) if id != "dorm" else 5.6
		if bd.has("dorm_id"):
			y = ClassicDorms.CEIL + 1.0   # V6: above the front porch hood
		if id == "chapel_w":
			y = 5.0
		_board(Vector3(fp.x, y, fp.y) + Vector3(face_n.x, 0, face_n.y) * 0.12, Vector3(face_n.x, 0, face_n.y), nm, 0.55 if nm.length() < 18 else 0.48)
	# wayfinding posts: [position, [[text, toward (x, z)], ...]]
	var posts := [
		[Vector2(4.2, 80.0), [["Puddlesworth Hall", Vector2(0, 112)], ["Founders' Fountain", Vector2(0, 22)]]],
		[Vector2(-81.0, 49.5), [["Froggy Pond", Vector2(-120, 46)], ["Noodle Commons", Vector2(-42, 66)]]],
		[Vector2(80.5, 35.5), [["Splashdown Pool", Vector2(112, 32)], ["Student Union", Vector2(42, 66)]]],
		[Vector2(95.5, -61.5), [["Lily Basin", Vector2(92, -88)], ["Greenhouse", Vector2(130, -88)]]],
		[Vector2(-103.5, -61.5), [["Old Quarry Lagoon", Vector2(-100, -90)], ["Stargazer Observatory", Vector2(-138, -118)]]],
		[Vector2(-23.5, -96.0), [["Boathouse Inlet", Vector2(-19, -137)], ["Bellweather Tower", Vector2(0, -30)]]],
	]
	if not L.legacy:
		# V6: the two new dorms from the yard junctions
		posts.append([Vector2(-76.8, 95.2), [["Lanternfield House", Vector2(-96, 104)], ["Puddlesworth Hall", Vector2(0, 103)]]])
		posts.append([Vector2(76.8, 95.2), [["Moonpenny Lodge", Vector2(96, 100)], ["Puddlesworth Hall", Vector2(0, 103)]]])
	for pst in posts:
		_fingerpost(pst[0], pst[1])


func _board(p: Vector3, nrm: Vector3, text: String, size_m: float) -> void:
	var right := Vector3(-nrm.z, 0, nrm.x)
	var w := maxf(2.0, float(text.length()) * size_m * 0.42 + 0.6)
	var k := _k(p.x, p.z, true)
	k.mat = MeshKit.M_WOOD
	k.chamfer_box(p - nrm * 0.05, Vector3(w, size_m * 1.5, 0.1) if absf(nrm.z) > 0.5 else Vector3(0.1, size_m * 1.5, w), Color(0.16, 0.18, 0.26), 0.03)
	k.mat = MeshKit.M_METAL
	k.chamfer_box(p - nrm * 0.06, Vector3(w + 0.12, size_m * 1.5 + 0.12, 0.06) if absf(nrm.z) > 0.5 else Vector3(0.06, size_m * 1.5 + 0.12, w + 0.12), Color(0.8, 0.66, 0.36), 0.02)
	k.mat = 0.0
	_label(p + nrm * 0.03, nrm, text, size_m, w)


func _label(p: Vector3, nrm: Vector3, text: String, size_m: float, width: float) -> void:
	var lb := Label3D.new()
	lb.text = text
	lb.font = SIGN_FONT
	lb.font_size = 64
	lb.pixel_size = size_m / 64.0 * 0.9
	lb.modulate = Color(1.0, 0.93, 0.78)
	lb.outline_size = 0
	lb.shaded = false
	lb.double_sided = false
	lb.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	lb.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	lb.width = width / lb.pixel_size
	lb.position = p
	lb.basis = Basis.looking_at(-nrm, Vector3.UP)
	lb.visibility_range_end = 45.0
	lb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lb.name = "Sign_" + text.validate_node_name()
	B.container.add_child(lb)


## A fingerpost beside a junction: a timber post with arrow boards pointing
## the way to each place (and naming it), a small lantern on top.
func _fingerpost(p: Vector2, boards: Array) -> void:
	var k := _k(p.x, p.y, true)
	k.mat = MeshKit.M_WOOD
	k.chamfer_box(Vector3(p.x, 1.25, p.y), Vector3(0.16, 2.5, 0.16), Color(0.38, 0.27, 0.19), 0.03)
	k.mat = MeshKit.M_METAL
	k.soft_blob(Vector3(p.x, 2.6, p.y), Vector3(0.12, 0.12, 0.12), Color(1.0, 0.84, 0.5), 3, 8, 0.0, 0.0, 0, 1.6)
	k.mat = 0.0
	for i in boards.size():
		var txt: String = boards[i][0]
		var to: Vector2 = boards[i][1]
		var d := (to - p).normalized()
		var y := 2.15 - 0.42 * float(i)
		var dir3 := Vector3(d.x, 0, d.y)
		var w := float(txt.length()) * 0.105 + 0.35
		var c := Vector3(p.x, y, p.y) + dir3 * (w * 0.5 + 0.05)
		var yaw := atan2(-d.y, d.x)
		k.mat = MeshKit.M_WOOD
		k.chamfer_box(c, Vector3(w, 0.3, 0.06), Color(0.86, 0.80, 0.66), 0.02, yaw)
		# arrow tip
		var tip := Vector3(p.x, y, p.y) + dir3 * (w + 0.22)
		var nrm := Vector3(-d.y, 0, d.x)
		k.tri(c + dir3 * w * 0.5 + Vector3.UP * 0.15 + nrm * 0.031, tip + nrm * 0.031, c + dir3 * w * 0.5 - Vector3.UP * 0.15 + nrm * 0.031, Color(0.86, 0.80, 0.66))
		k.tri(c + dir3 * w * 0.5 + Vector3.UP * 0.15 - nrm * 0.031, c + dir3 * w * 0.5 - Vector3.UP * 0.15 - nrm * 0.031, tip - nrm * 0.031, Color(0.86, 0.80, 0.66))
		k.mat = 0.0
		for sg: float in [1.0]:
			var lb := Label3D.new()
			lb.text = txt
			lb.font = SIGN_FONT
			lb.font_size = 48
			lb.pixel_size = 0.0042
			lb.modulate = Color(0.16, 0.18, 0.26)
			lb.outline_size = 0
			lb.shaded = true
			lb.alpha_cut = Label3D.ALPHA_CUT_DISCARD
			lb.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			lb.position = c + nrm * (0.036 * sg)
			lb.basis = Basis.looking_at(-nrm * sg, Vector3.UP)
			lb.double_sided = false
			lb.visibility_range_end = 32.0
			lb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			lb.name = "Fingerpost_%s_%d" % [txt.validate_node_name(), int(sg)]
			B.container.add_child(lb)
