class_name ClassicLandmarks
extends RefCounted
## The six water landmarks and the horizon (V5).  Each water is one
## MeshInstance3D with the water shader (its own material: `active` and
## `stamped` are set per round by MatchController) plus its stonework,
## planting and props merged into the campus chunks.
##
## Objective markers: every water mesh also carries a ring of floating
## lanterns in the water's target colour (UV.x = 9).  The water shader hides
## them (collapses them below the surface) unless the water is an active
## objective, dims them once this player has stamped it, and bobs them; so a
## target reads by its lanterns and the slim shoreline glow, and decorative
## water never looks like one.  Same draw call as the water.
##
##   Founders' Fountain  turned stone basin with a lip and plinth step, a
##                       two-tier pedestal, four arcing jets and a plume
##                       (flowing-water material), ripples where they land,
##                       a warm up-light.
##   Froggy Pond         sandy, pebbly bank, reed beds and lilies in groups
##                       (dressing), flat stepping stones at each exit, the
##                       frog on its rock, a name board.
##   Splashdown Pool     tiled coping and deck, lane lines and wall lights
##                       in the water, the lifeguard chair, a diving board.
##   Old Quarry Lagoon   layered rock from the kit at every boulder, a stone
##                       ledge, scattered stones, work lanterns.
##   Lily Basin          carved coping, corner urns with clipped topiary,
##                       flower boxes clear of the exits, lilies.
##   Boathouse Inlet     plank dock with pilings and cleats, the boathouse
##                       with its boat doors, reeds in the corners.

var B: ClassicBuilder
var L: ClassicLayout
const STONE := Color(0.72, 0.70, 0.74)
const M_MARKER := 9.0
const M_FLOW := 20.0


func _init(builder: ClassicBuilder) -> void:
	B = builder
	L = builder.L


func water(i: int) -> void:
	var w: Dictionary = L.waters[i]
	var c: Vector2 = w["center"]
	var mi := MeshInstance3D.new()
	mi.name = "Water_%s" % w["id"]
	var mat := ShaderMaterial.new()
	mat.shader = ClassicBuilder.WATER_SHADER
	mat.set_shader_parameter("target_color", w["color"])
	var y: float = w["surface_y"]
	var k := MeshKit.new()
	var deco := B._kit_at(c.x, c.y)
	match String(w["shape"]):
		"circle":
			var r: float = w["radius"]
			_surface_disc(k, r + 0.3, r + 0.3, 40)
			mat.set_shader_parameter("shape_half", Vector2(r, r))
			mat.set_shader_parameter("shape_kind", 0.0)
		"ellipse":
			var rx: float = w["rx"]
			var rz: float = w["rz"]
			_surface_disc(k, rx + 0.6, rz + 0.6, 40)
			mat.set_shader_parameter("shape_half", Vector2(rx, rz))
			mat.set_shader_parameter("shape_kind", 0.0)
		"rect":
			var hs: Vector2 = w["size"] * 0.5
			_surface_rect(k, hs + Vector2(0.3, 0.3))
			mat.set_shader_parameter("shape_half", hs)
			mat.set_shader_parameter("shape_kind", 1.0)
	_markers(k, w)
	match String(w["id"]):
		"fountain":
			_fountain(w, deco, k, mat)
		"pond":
			_pond(w, deco)
		"pool":
			_pool(w, deco, mat)
		"quarry":
			_quarry(w, deco, mat)
		"garden":
			_garden(w, deco)
		"inlet":
			_inlet(w, deco, mat)
	mi.mesh = k.commit()
	mi.material_override = mat
	mi.position = Vector3(c.x, y, c.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	B.container.add_child(mi)
	B.water_nodes[w["id"]] = {"node": mi, "mat": mat, "index": i}


## Water surface: rings of vertices (so the gentle swell and the shore
## shading have something to work with), local to the water's centre.
func _surface_disc(k: MeshKit, rx: float, rz: float, seg: int) -> void:
	var rings := 5
	for r in rings:
		var f0 := float(r) / float(rings)
		var f1 := float(r + 1) / float(rings)
		for s in seg:
			var a0 := TAU * float(s) / float(seg)
			var a1 := TAU * float(s + 1) / float(seg)
			var p00 := Vector3(cos(a0) * rx * f0, 0, sin(a0) * rz * f0)
			var p01 := Vector3(cos(a1) * rx * f0, 0, sin(a1) * rz * f0)
			var p10 := Vector3(cos(a0) * rx * f1, 0, sin(a0) * rz * f1)
			var p11 := Vector3(cos(a1) * rx * f1, 0, sin(a1) * rz * f1)
			if r == 0:
				k.tri(Vector3.ZERO, p10, p11, Color.WHITE, 0.0, 0.0, Vector3.UP)
			else:
				k.tri(p00, p10, p11, Color.WHITE, 0.0, 0.0, Vector3.UP)
				k.tri(p00, p11, p01, Color.WHITE, 0.0, 0.0, Vector3.UP)


func _surface_rect(k: MeshKit, hs: Vector2) -> void:
	var nx := maxi(2, int(hs.x * 2.0 / 2.0))
	var nz := maxi(2, int(hs.y * 2.0 / 2.0))
	for iz in nz:
		for ix in nx:
			var x0 := -hs.x + hs.x * 2.0 * float(ix) / float(nx)
			var x1 := -hs.x + hs.x * 2.0 * float(ix + 1) / float(nx)
			var z0 := -hs.y + hs.y * 2.0 * float(iz) / float(nz)
			var z1 := -hs.y + hs.y * 2.0 * float(iz + 1) / float(nz)
			k.quad(Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1), Color.WHITE)


## Floating lanterns (objective markers, hidden unless active): a dark float,
## a glowing paper lantern in the target colour and a little cap.  UV.y
## carries each lantern's bob phase.
func _markers(k: MeshKit, w: Dictionary) -> void:
	var col: Color = w["color"]
	var pts: Array[Vector2] = []
	match String(w["shape"]):
		"circle":
			var r: float = float(w["radius"]) - 1.1
			for j in 6:
				var a := TAU * (float(j) + 0.5) / 6.0
				pts.append(Vector2(cos(a), sin(a)) * r)
		"ellipse":
			var rx: float = float(w["rx"]) - 1.6
			var rz: float = float(w["rz"]) - 1.6
			for j in 8:
				var a2 := TAU * (float(j) + 0.3) / 8.0
				pts.append(Vector2(cos(a2) * rx, sin(a2) * rz))
		"rect":
			var hs: Vector2 = w["size"] * 0.5 - Vector2(1.1, 1.1)
			var n := 4 if hs.x * hs.y < 30.0 else 6
			for j in n:
				var t := float(j) / float(n)
				# around the rectangle's perimeter
				var per := (hs.x + hs.y) * 4.0
				var d := t * per
				var p := Vector2.ZERO
				if d < hs.x * 2.0:
					p = Vector2(-hs.x + d, -hs.y)
				elif d < hs.x * 2.0 + hs.y * 2.0:
					p = Vector2(hs.x, -hs.y + (d - hs.x * 2.0))
				elif d < hs.x * 4.0 + hs.y * 2.0:
					p = Vector2(hs.x - (d - hs.x * 2.0 - hs.y * 2.0), hs.y)
				else:
					p = Vector2(-hs.x, hs.y - (d - hs.x * 4.0 - hs.y * 2.0))
				pts.append(p)
	for j in pts.size():
		var p3 := Vector3(pts[j].x, 0.0, pts[j].y)
		k.mat = M_MARKER
		k.param = float(j) * 1.7
		k.revolve(p3, PackedVector2Array([Vector2(0.26, -0.06), Vector2(0.3, 0.02), Vector2(0.22, 0.08)]), PackedColorArray([Color(0.12, 0.10, 0.10)]), 10)
		k.revolve(p3, PackedVector2Array([Vector2(0.06, 0.06), Vector2(0.2, 0.14), Vector2(0.23, 0.32), Vector2(0.18, 0.5), Vector2(0.05, 0.58)]),
			PackedColorArray([col.darkened(0.2), col, col.lightened(0.1), col, col.darkened(0.2)]), 10, PackedFloat32Array(), 0.75)
		k.revolve(p3, PackedVector2Array([Vector2(0.12, 0.56), Vector2(0.1, 0.64), Vector2(0.0, 0.7)]), PackedColorArray([Color(0.15, 0.12, 0.1)]), 8)
	k.mat = 0.0
	k.param = 0.0


# ---------------------------------------------------------------------------
# Founders' Fountain
# ---------------------------------------------------------------------------
func _fountain(w: Dictionary, deco: MeshKit, k: MeshKit, mat: ShaderMaterial) -> void:
	var c: Vector2 = w["center"]
	var r: float = w["radius"]
	var rim: float = w["rim_h"]
	var th: float = w.get("rim_t", 0.5)
	var base := Vector3(c.x, 0, c.y)
	var stone := Color(0.78, 0.74, 0.70)
	# basin wall: inner face, rolled lip, outer face, plinth step (colliders:
	# 20 boxes on the same ring, 0.55 m high)
	deco.mat = MeshKit.M_STONE
	deco.revolve(base, PackedVector2Array([Vector2(r, -0.5), Vector2(r, rim - 0.14), Vector2(r + 0.05, rim - 0.04), Vector2(r + 0.16, rim + 0.03),
		Vector2(r + th * 0.5, rim + 0.07), Vector2(r + th - 0.14, rim + 0.03), Vector2(r + th - 0.04, rim - 0.06), Vector2(r + th, rim - 0.16),
		Vector2(r + th, 0.2), Vector2(r + th + 0.12, 0.17), Vector2(r + th + 0.16, 0.05), Vector2(r + th + 0.22, 0.0)]),
		PackedColorArray([stone.darkened(0.45), stone.darkened(0.2), stone.lightened(0.04), stone.lightened(0.12), stone.lightened(0.16), stone.lightened(0.12),
		stone.lightened(0.04), stone, stone.darkened(0.06), stone.darkened(0.1), stone.darkened(0.16), stone.darkened(0.25)]), 48)
	# tiered centrepiece (collider: 1.3 m cylinder): pedestal, wide lower
	# bowl, a slim stem and an upper bowl
	deco.revolve(base, PackedVector2Array([Vector2(1.3, -1.4), Vector2(1.28, 0.45), Vector2(1.12, 0.6), Vector2(0.92, 0.72), Vector2(0.86, 0.95),
		Vector2(1.6, 1.08), Vector2(2.2, 1.22), Vector2(2.3, 1.36), Vector2(2.16, 1.44), Vector2(1.7, 1.42), Vector2(0.55, 1.5),
		Vector2(0.42, 1.8), Vector2(0.38, 2.2), Vector2(0.5, 2.5), Vector2(1.05, 2.66), Vector2(1.14, 2.78), Vector2(1.0, 2.84), Vector2(0.3, 2.9)]),
		PackedColorArray([stone.darkened(0.4), stone.darkened(0.15), stone, stone.darkened(0.05), stone, stone.lightened(0.05), stone.lightened(0.1),
		stone.lightened(0.16), stone.lightened(0.12), stone.darkened(0.1), stone.darkened(0.15), stone, stone.darkened(0.05), stone, stone.lightened(0.08),
		stone.lightened(0.14), stone.lightened(0.1), stone.darkened(0.1)]), 28)
	deco.mat = 0.0
	mat.set_shader_parameter("fountain", 1.0)
	# warm up-light around the basin
	B.glow_disc(Vector3(c.x, 0.06, c.y), r + 3.0)


## The fountain's flowing water (its own build step).
func fountain_jets(i: int) -> void:
	var w: Dictionary = L.waters[i]
	var c: Vector2 = w["center"]
	var base := Vector3(c.x, 0, c.y)
	var deco := B._kit_at(c.x, c.y)
	# water standing in both bowls (water surface colour, a touch emissive)
	deco.mat = M_FLOW
	deco.param = 0.0
	deco.disc(base + Vector3(0, 1.4, 0), 2.08, Color(0.42, 0.62, 0.78), 24, 0.25)
	deco.disc(base + Vector3(0, 2.78, 0), 1.02, Color(0.42, 0.62, 0.78), 16, 0.25)
	# jets: four arcs from the upper bowl into the basin and a central plume,
	# as slim tubes in the flowing-water material (parameter runs along)
	for j in 4:
		var a := TAU * (float(j) + 0.5) / 4.0
		var dir := Vector3(cos(a), 0, sin(a))
		var pts := PackedVector3Array()
		for s in 9:
			var t := float(s) / 8.0
			var horiz := lerpf(1.0, 4.3, t)
			var yy := 2.85 + 1.2 * sin(t * PI * 0.92) - 2.9 * t * t
			pts.append(base + dir * horiz + Vector3.UP * yy)
		_jet_tube(deco, pts, 0.07, 0.11)
	var plume := PackedVector3Array()
	for s in 6:
		plume.append(base + Vector3.UP * (2.85 + 1.25 * float(s) / 5.0))
	_jet_tube(deco, plume, 0.16, 0.05)
	deco.mat = 0.0
	deco.param = 0.0


func _jet_tube(k: MeshKit, pts: PackedVector3Array, r0: float, r1: float) -> void:
	var seg := 6
	var n := pts.size()
	for i in n - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var t := (b - a).normalized()
		var side := t.cross(Vector3.UP)
		if side.length() < 0.01:
			side = Vector3.RIGHT
		side = side.normalized()
		var up := side.cross(t).normalized()
		var ra := lerpf(r0, r1, float(i) / float(n - 1))
		var rb := lerpf(r0, r1, float(i + 1) / float(n - 1))
		for s in seg:
			var q0 := TAU * float(s) / float(seg)
			var q1 := TAU * float(s + 1) / float(seg)
			var d0 := side * cos(q0) + up * sin(q0)
			var d1 := side * cos(q1) + up * sin(q1)
			var col := Color(0.70, 0.84, 0.96)
			var ua := Vector2(M_FLOW, float(i) / float(n - 1))
			var ub := Vector2(M_FLOW, float(i + 1) / float(n - 1))
			k.tri_full(a + d0 * ra, b + d1 * rb, b + d0 * rb, d0, d1, d0, col, col, col, ua, ub, ub)
			k.tri_full(a + d0 * ra, a + d1 * ra, b + d1 * rb, d0, d1, d1, col, col, col, ua, ua, ub)
	# a little emission on the jets so they read against the night
	k.cu_emission_last((n - 1) * seg * 6, 0.55)


# ---------------------------------------------------------------------------
# Froggy Pond
# ---------------------------------------------------------------------------
func _pond(w: Dictionary, deco: MeshKit) -> void:
	var c: Vector2 = w["center"]
	var rx: float = w["rx"]
	var rz: float = w["rz"]
	# a soft lip of wet earth just inside the bank (meets the water line)
	deco.mat = MeshKit.M_GRAVEL
	var seg := 48
	for s in seg:
		var a0 := TAU * float(s) / float(seg)
		var a1 := TAU * float(s + 1) / float(seg)
		var o0 := Vector3(c.x + cos(a0) * (rx + 0.9), 0.02, c.y + sin(a0) * (rz + 0.9))
		var o1 := Vector3(c.x + cos(a1) * (rx + 0.9), 0.02, c.y + sin(a1) * (rz + 0.9))
		var i0 := Vector3(c.x + cos(a0) * (rx - 0.2), -0.42, c.y + sin(a0) * (rz - 0.2))
		var i1 := Vector3(c.x + cos(a1) * (rx - 0.2), -0.42, c.y + sin(a1) * (rz - 0.2))
		var wet := Color(0.26, 0.23, 0.19)
		var dry := Color(0.44, 0.39, 0.30)
		deco.tri_n(o0, o1, i1, Vector3.UP, Vector3.UP, Vector3.UP, dry, dry, wet)
		deco.tri_n(o0, i1, i0, Vector3.UP, Vector3.UP, Vector3.UP, dry, wet, wet)
	deco.mat = 0.0
	_exit_stones(w, deco)
	_name_board(Vector2(-105.5, 40.5), Vector2(1, 0.2).normalized(), "Froggy Pond", Color(0.45, 1.0, 0.45))


## Flat stepping stones flush with the ground into the water at each exit:
## a clear, quiet cue where the way in and out is.
func _exit_stones(w: Dictionary, deco: MeshKit) -> void:
	var c: Vector2 = w["center"]
	deco.mat = MeshKit.M_ROCK
	for e in w["exits"]:
		var ep := Vector2(e.x, e.z)
		var d := (c - ep).normalized()
		for s in 3:
			var p := ep + d * (0.4 + 0.9 * float(s)) + d.orthogonal() * (0.25 if s % 2 == 0 else -0.25)
			var y := ClassicBuilder.ground_y(L, p.x, p.y)
			if y < -0.1:
				y = float(w["surface_y"]) + 0.02
			deco.soft_blob(Vector3(p.x, y + 0.03, p.y), Vector3(0.42, 0.06, 0.34), Color(0.62, 0.60, 0.58), 3, 9, 0.0, 0.12, s)
	deco.mat = 0.0


func _name_board(p: Vector2, facing: Vector2, text: String, accent: Color) -> void:
	var k := B._kit_at(p.x, p.y, false, true)
	var nrm := Vector3(facing.x, 0, facing.y)
	var right := Vector3(-nrm.z, 0, nrm.x)
	k.mat = MeshKit.M_WOOD
	for sx: float in [-0.8, 0.8]:
		k.chamfer_box(Vector3(p.x, 0.6, p.y) + right * sx, Vector3(0.12, 1.2, 0.12), Color(0.38, 0.27, 0.19), 0.02)
	var w := float(text.length()) * 0.16 + 0.4
	var yaw := atan2(-right.z, right.x)
	k.chamfer_box(Vector3(p.x, 1.05, p.y), Vector3(w, 0.5, 0.08), Color(0.86, 0.80, 0.66), 0.03, yaw)
	k.mat = MeshKit.M_PLAIN
	k.chamfer_box(Vector3(p.x, 1.05, p.y) + right * (-w * 0.5 + 0.18) + nrm * 0.05, Vector3(0.18, 0.18, 0.02), accent, 0.02, yaw, null, true, 0.6)
	k.mat = 0.0
	for sg: float in [-1.0, 1.0]:
		var lb := Label3D.new()
		lb.text = text
		lb.font = ClassicArchitecture.SIGN_FONT
		lb.font_size = 48
		lb.pixel_size = 0.0058
		lb.modulate = Color(0.16, 0.18, 0.26)
		lb.shaded = true
		lb.outline_size = 0
		lb.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		lb.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		lb.position = Vector3(p.x, 1.05, p.y) + nrm * (0.045 * sg) + right * 0.1
		lb.basis = Basis.looking_at(-nrm * sg, Vector3.UP)
		lb.visibility_range_end = 32.0
		lb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lb.name = "Board_%s_%d" % [text.validate_node_name(), int(sg)]
		B.container.add_child(lb)


# ---------------------------------------------------------------------------
# Splashdown Pool
# ---------------------------------------------------------------------------
func _pool(w: Dictionary, deco: MeshKit, mat: ShaderMaterial) -> void:
	var c: Vector2 = w["center"]
	var hs: Vector2 = w["size"] * 0.5
	var y: float = w["surface_y"]
	var tile := Color(0.92, 0.94, 0.96)
	mat.set_shader_parameter("pool", 1.0)
	# rounded tiled coping around the edge, and the inner wall down to the water
	deco.mat = MeshKit.M_TILE
	for sd in 4:
		var horiz := sd < 2
		var sg := -1.0 if sd % 2 == 0 else 1.0
		var len := (hs.x * 2.0 + 1.2) if horiz else (hs.y * 2.0)
		var cc := c + (Vector2(0, sg * (hs.y + 0.3)) if horiz else Vector2(sg * (hs.x + 0.3), 0))
		var size := Vector3(len, 0.12, 0.6) if horiz else Vector3(0.6, 0.12, len)
		deco.chamfer_box(Vector3(cc.x, 0.04, cc.y), size, tile, 0.05)
		# inner wall: blue tiles to the waterline
		var wc := c + (Vector2(0, sg * hs.y) if horiz else Vector2(sg * hs.x, 0))
		var a := Vector3(wc.x, 0.0, wc.y) + (Vector3(-hs.x, 0, 0) if horiz else Vector3(0, 0, -hs.y))
		var b := Vector3(wc.x, 0.0, wc.y) + (Vector3(hs.x, 0, 0) if horiz else Vector3(0, 0, hs.y))
		var face := Vector3(0, 0, -sg) if horiz else Vector3(-sg, 0, 0)
		_quad_facing(deco, a, b, b + Vector3.UP * (y - 0.3), a + Vector3.UP * (y - 0.3), Color(0.55, 0.78, 0.86), face)
	deco.mat = 0.0
	# lane ropes: floats in red and white
	for lx in [-hs.x * 0.33, hs.x * 0.33]:
		var nb := 22
		for j in nb:
			var zz := -hs.y + 0.6 + float(j) * (hs.y * 2.0 - 1.2) / float(nb - 1)
			deco.soft_blob(Vector3(c.x + lx, y + 0.05, c.y + zz), Vector3(0.12, 0.08, 0.12), Color(1.0, 0.3, 0.3) if j % 2 == 0 else Color(1, 1, 1), 2, 6, 0.0, 0.0, 0, 0.25)
	# diving board on a tiled stand at the north end
	deco.mat = MeshKit.M_TILE
	deco.chamfer_box(Vector3(c.x, 0.25, c.y - hs.y - 2.2), Vector3(0.7, 0.5, 0.7), Color(0.6, 0.62, 0.66), 0.04)
	deco.mat = MeshKit.M_PLAIN
	deco.chamfer_box(Vector3(c.x, 0.52, c.y - hs.y - 1.2), Vector3(0.6, 0.08, 2.6), Color(0.3, 0.62, 0.9), 0.03)
	deco.mat = 0.0


func _quad_facing(k: MeshKit, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, facing: Vector3) -> void:
	if ((b - a).cross(c - a)).dot(facing) < 0.0:
		k.quad(a, b, c, d, col)
	else:
		k.quad(d, c, b, a, col)


# ---------------------------------------------------------------------------
# Old Quarry Lagoon
# ---------------------------------------------------------------------------
func _quarry(w: Dictionary, deco: MeshKit, mat: ShaderMaterial) -> void:
	var c: Vector2 = w["center"]
	var rx: float = w["rx"]
	var rz: float = w["rz"]
	mat.set_shader_parameter("deep_color", Color(0.05, 0.07, 0.17))
	mat.set_shader_parameter("shallow_color", Color(0.16, 0.30, 0.40))
	# a stony shelf ring at the waterline (wet rock), lit by work lanterns
	deco.mat = MeshKit.M_ROCK
	var seg := 48
	for s in seg:
		var a0 := TAU * float(s) / float(seg)
		var a1 := TAU * float(s + 1) / float(seg)
		var o0 := Vector3(c.x + cos(a0) * (rx + 0.8), 0.03, c.y + sin(a0) * (rz + 0.8))
		var o1 := Vector3(c.x + cos(a1) * (rx + 0.8), 0.03, c.y + sin(a1) * (rz + 0.8))
		var i0 := Vector3(c.x + cos(a0) * (rx - 0.2), -1.05, c.y + sin(a0) * (rz - 0.2))
		var i1 := Vector3(c.x + cos(a1) * (rx - 0.2), -1.05, c.y + sin(a1) * (rz - 0.2))
		var wet := Color(0.30, 0.28, 0.30)
		var dry := Color(0.55, 0.50, 0.46)
		deco.tri_n(o0, o1, i1, Vector3.UP, Vector3.UP, Vector3.UP, dry, dry, wet)
		deco.tri_n(o0, i1, i0, Vector3.UP, Vector3.UP, Vector3.UP, dry, wet, wet)
	deco.mat = 0.0
	_exit_stones(w, deco)
	# work lanterns on short posts beside the three gaps
	for lp in [c + Vector2(16.0, -6.6), c + Vector2(-6.4, 15.6), c + Vector2(-16.2, 6.4)]:
		var k := B._kit_at(lp.x, lp.y, false, true)
		k.mat = MeshKit.M_WOOD
		k.chamfer_box(Vector3(lp.x, 0.7, lp.y), Vector3(0.14, 1.4, 0.14), Color(0.4, 0.3, 0.2), 0.02)
		k.mat = MeshKit.M_GLASS
		k.soft_blob(Vector3(lp.x, 1.52, lp.y), Vector3(0.16, 0.2, 0.16), Color(1.0, 0.78, 0.45), 3, 8, 0.0, 0.0, 0, 2.2)
		k.mat = 0.0
		B.glow_disc(Vector3(lp.x, 0.1, lp.y), 4.5)
	_name_board(c + Vector2(4.5, 18.2), Vector2(0.2, 1).normalized(), "Old Quarry Lagoon", Color(0.75, 0.55, 1.0))


# ---------------------------------------------------------------------------
# Lily Basin
# ---------------------------------------------------------------------------
func _garden(w: Dictionary, deco: MeshKit) -> void:
	var c: Vector2 = w["center"]
	var hs: Vector2 = w["size"] * 0.5
	var rim2: float = w["rim_h"]
	var th2: float = w.get("rim_t", 0.5)
	var stone := Color(0.80, 0.78, 0.80)
	# carved coping: a rounded top over a slightly inset body (collider: the
	# same four 0.45 m boxes)
	deco.mat = MeshKit.M_STONE
	for sd in 4:
		var horiz := sd < 2
		var sg := -1.0 if sd % 2 == 0 else 1.0
		var cc := c + (Vector2(0, sg * (hs.y + th2 * 0.5)) if horiz else Vector2(sg * (hs.x + th2 * 0.5), 0))
		var length := (hs.x * 2.0 + th2 * 2.0) if horiz else (hs.y * 2.0)
		var body := Vector3(length, rim2 - 0.1, th2 - 0.06) if horiz else Vector3(th2 - 0.06, rim2 - 0.1, length)
		var cap := Vector3(length + 0.12, 0.14, th2 + 0.14) if horiz else Vector3(th2 + 0.14, 0.14, length + 0.12)
		deco.chamfer_box(Vector3(cc.x, (rim2 - 0.1) * 0.5, cc.y), body, stone.darkened(0.1), 0.04)
		deco.chamfer_box(Vector3(cc.x, rim2 - 0.05, cc.y), cap, stone.lightened(0.08), 0.06)
	# corner urns with clipped topiary balls
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var up := Vector3(c.x + sx * (hs.x + th2 * 0.5), rim2, c.y + sz * (hs.y + th2 * 0.5))
			deco.mat = MeshKit.M_STONE
			deco.revolve(up, PackedVector2Array([Vector2(0.2, 0.0), Vector2(0.14, 0.1), Vector2(0.24, 0.3), Vector2(0.34, 0.5), Vector2(0.36, 0.58), Vector2(0.3, 0.6)]),
				PackedColorArray([stone.darkened(0.2), stone.darkened(0.1), stone, stone.lightened(0.05), stone.lightened(0.12), stone]), 12)
			deco.mat = MeshKit.M_LEAF
			deco.soft_blob(up + Vector3(0, 0.95, 0), Vector3(0.48, 0.46, 0.48), Color(0.22, 0.46, 0.26), 5, 12, 0.1, 0.05, int(sx * 3 + sz))
			deco.mat = 0.0
	# flower boxes along the long sides, clear of the two exits on the axis
	var fk := B._kit_at(c.x, c.y, false, true)
	var blooms := [Color(0.98, 0.56, 0.74), Color(1.0, 0.86, 0.42), Color(0.95, 0.95, 0.92), Color(0.74, 0.58, 0.98)]
	for bi in 4:
		var side := -1.0 if bi % 2 == 0 else 1.0
		var bx := c.x + (-4.6 if bi < 2 else 4.6)
		var bz := c.y + side * (hs.y + th2 + 1.3)
		fk.mat = MeshKit.M_WOOD
		fk.chamfer_box(Vector3(bx, 0.18, bz), Vector3(2.6, 0.36, 0.8), Color(0.46, 0.33, 0.24), 0.05, 0.0, Color(0.24, 0.18, 0.13))
		fk.mat = MeshKit.M_LEAF
		for fi in 6:
			var fx := bx - 1.05 + float(fi) * 0.42
			fk.soft_blob(Vector3(fx, 0.42, bz + 0.1 * sin(float(fi * 3 + bi))), Vector3(0.22, 0.16, 0.22), Color(0.2, 0.42, 0.22), 3, 7, 0.2)
			fk.soft_blob(Vector3(fx + 0.05, 0.55, bz + 0.12 * cos(float(fi + bi))), Vector3(0.14, 0.11, 0.14), (blooms[(fi + bi) % 4] as Color), 3, 7, 0.25)
		fk.mat = 0.0
	_name_board(c + Vector2(-5.5, 16.2), Vector2(0, 1), "Lily Basin", Color(1.0, 0.5, 0.75))


# ---------------------------------------------------------------------------
# Boathouse Inlet
# ---------------------------------------------------------------------------
func _inlet(w: Dictionary, deco: MeshKit, mat: ShaderMaterial) -> void:
	var c: Vector2 = w["center"]
	mat.set_shader_parameter("shallow_color", Color(0.10, 0.30, 0.36))
	# a timber edge along the open shores (bank boards), stone at the corners
	var hs: Vector2 = w["size"] * 0.5
	deco.mat = MeshKit.M_WOOD
	for seg in [[Vector2(-hs.x, -hs.y), Vector2(-hs.x, hs.y)], [Vector2(hs.x, -hs.y), Vector2(hs.x, hs.y)], [Vector2(-hs.x, hs.y), Vector2(hs.x, hs.y)]]:
		var a: Vector2 = c + seg[0]
		var b: Vector2 = c + seg[1]
		deco.segment_box(a, b, -0.55, 0.62, 0.22, Color(0.40, 0.30, 0.22), 0.0, Color(0.50, 0.38, 0.27))
	deco.mat = 0.0
	# the boathouse's boat doors face the water: dark arch + barn doors ajar
	var bh := L.buildings.filter(func(b: Dictionary) -> bool: return b["id"] == "boathouse")
	if not bh.is_empty():
		var bd: Dictionary = bh[0]
		var bp: Vector2 = bd["pos"]
		var bs: Vector2 = bd["size"]
		var face_x := bp.x + bs.x * 0.5 + 0.06
		var k := B._kit_at(bp.x, bp.y)
		k.mat = MeshKit.M_PLAIN
		_quad_facing(k, Vector3(face_x, 4.2, bp.y - 2.6), Vector3(face_x, 4.2, bp.y + 2.6), Vector3(face_x, 0.0, bp.y + 2.6), Vector3(face_x, 0.0, bp.y - 2.6), Color(0.06, 0.06, 0.08), Vector3.RIGHT)
		k.mat = MeshKit.M_WOOD
		for sz: float in [-1.0, 1.0]:
			k.box(Vector3(face_x + 0.6, 2.1, bp.y + sz * 3.4), Vector3(1.2, 4.2, 0.12), Color(0.55, 0.36, 0.24), 0.4 * sz)
		k.chamfer_box(Vector3(face_x + 0.1, 4.45, bp.y), Vector3(0.24, 0.4, 6.2), Color(0.86, 0.82, 0.74), 0.04)
		k.mat = 0.0
		var kd := B._kit_at(bp.x, bp.y, false, true)
		kd.mat = MeshKit.M_GLASS
		kd.soft_blob(Vector3(face_x + 0.3, 4.9, bp.y), Vector3(0.2, 0.24, 0.2), Color(1.0, 0.8, 0.5), 3, 8, 0.0, 0.0, 0, 2.2)
		kd.mat = 0.0
		B.glow_disc(Vector3(face_x + 2.5, 0.1, bp.y), 5.0)
	# lanterns on the dock's outer pilings
	for z in [c.y - 8.0 + 0.0, c.y + 6.6]:
		B.glow_disc(Vector3(-13.5, 0.08, z), 3.0)
	_name_board(c + Vector2(4.5, 13.2), Vector2(0, 1), "Boathouse Inlet", Color(1.0, 0.62, 0.30))


# ---------------------------------------------------------------------------
# Horizon: the lake beyond the north rail, far shore and hills
# ---------------------------------------------------------------------------
func horizon() -> void:
	# the lake surface (dark, a hint of moonlight; merged with the chunks)
	var y := -0.5
	for xi in range(-240, 240, 40):
		var k := B._kit_at(clampf(float(xi) + 20.0, -150.0, 150.0), -149.0)
		k.quad(Vector3(xi, y, -300), Vector3(xi + 40, y, -300), Vector3(xi + 40, y, -146.5), Vector3(xi, y, -146.5), Color(0.06, 0.13, 0.26), 0.1)
	# the far shore: a dark band of trees (kit far LOD) on a low bank
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 64:
		var x := -260.0 + float(i) * 8.4 + rng.randf_range(-3, 3)
		var z := -262.0 + rng.randf_range(-10, 10)
		var s := rng.randf_range(2.0, 3.1)
		var sp: String = "fir"
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(x, -0.6, z))
		B._mm_add(B._far, ClassicBuilder.coarse_key(x, z, 3.0), sp, xf, Color(0.55, 0.6, 0.75), Color(1, 1, 1))
	for xi in range(-260, 260, 26):
		var k2 := B._kit_at(clampf(float(xi), -150.0, 150.0), -149.0)
		k2.soft_blob(Vector3(xi, -0.6, -268), Vector3(18, 3.0, 9), Color(0.08, 0.12, 0.13), 3, 8)
	# hills beyond the other edges so the world does not end abruptly
	for side in [[Vector2(-210, -150), Vector2(-210, 170)], [Vector2(210, -150), Vector2(210, 170)], [Vector2(-180, 200), Vector2(180, 200)]]:
		var a: Vector2 = side[0]
		var b: Vector2 = side[1]
		for j in 12:
			var p := a.lerp(b, float(j) / 11.0)
			var k3 := B._kit_at(clampf(p.x, -150.0, 150.0), clampf(p.y, -140.0, 140.0))
			k3.soft_blob(Vector3(p.x, -2.0, p.y), Vector3(30, 16 + float(j % 3) * 5.0, 30), Color(0.09, 0.14, 0.17), 4, 10, 0.0, 0.08, j)
