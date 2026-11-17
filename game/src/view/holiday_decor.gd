class_name HolidayDecor
extends RefCounted
## Season 1 (holiday) dressing for the dorm common room behind the menus
## and the party lobby (DormStage): a decorated tree with ornaments, fairy
## lights and a star in the back-right corner by the window, wrapped
## presents under it, a wreath on the back wall, a garland along the window
## head, twinkling string lights along the back and left walls, and snow
## falling past the window.
##
## The solid pieces go into the room's own merged mesh (the dorm shader:
## one draw call); the bulbs and star are one more mesh with
## festive_lights.gdshader (each bulb breathes at its own phase; steady with
## Reduced Motion).  Two warm lights: one small omni in the tree, plus the
## room's additive light pools.  Turn the theme off after the season by
## setting ENABLED false: the room falls back to its year-round look.
##
## The tree and presents are a walk-around obstacle too (HubRoom.CIRCLES).

const ENABLED := true

## the tree's foot (back-right corner, in front of the window's right
## curtain; between the home runner and the armchair in the home framing,
## behind the party in the lobby)
const TREE := Vector3(1.55, 0.0, -2.85)
const TREE_TOP := 2.58
## tiers: [base y, height, radius]
const TIERS := [
	[0.28, 0.98, 0.86],
	[0.66, 0.92, 0.72],
	[1.04, 0.86, 0.58],
	[1.42, 0.78, 0.44],
	[1.80, 0.78, 0.29],
]
const NEEDLE := Color("2b7148")
const NEEDLE_TIP := Color("5aae6c")
const ORNAMENT_COLS := [Color("d33a44"), Color("f2c14e"), Color("dfe6ee"), Color("3e7bd6"), Color("c04ad0")]
const BULB_COLS := [Color("ffd58a"), Color("ff6b6b"), Color("6fe0a0"), Color("6fb6ff"), Color("ffe9b8")]

## presents: [x, z, size x, size y, size z, yaw, paper, ribbon]
const PRESENTS := [
	[1.02, -2.28, 0.42, 0.30, 0.36, 0.30, Color("c7353e"), Color("f2c14e")],
	[1.62, -2.06, 0.50, 0.34, 0.42, -0.20, Color("2f8a5a"), Color("e8434f")],
	[2.18, -2.34, 0.34, 0.26, 0.34, 0.50, Color("3d6fd1"), Color("eef2f8")],
	[1.30, -1.78, 0.26, 0.20, 0.26, 0.15, Color("e8b64a"), Color("c7353e")],
	[0.72, -2.62, 0.30, 0.44, 0.30, -0.40, Color("2fa39a"), Color("f2c14e")],
	[2.02, -1.86, 0.40, 0.17, 0.48, 0.90, Color("8a5cc7"), Color("f2c14e")],
]


## Adds the solid pieces to the room's mesh `k` (dorm shader materials:
## alpha 0.8 fabric, 0.6 glossy, 0.9 wood, 1.0 plain).
static func build_solid(k: MeshKit, wx: float) -> void:
	_tree(k)
	_presents(k)
	_wreath(k, Vector3(2.62, 2.5, -3.43))
	_garland(k, wx)


## Adds the bulbs, star, tree light, light pools and the snowfall to `stage`.
static func build_lights(stage: DormStage, wx: float, reduced: bool) -> void:
	var b := MeshKit.new()
	_tree_bulbs(b)
	_star(b, TREE + Vector3(0, TREE_TOP + 0.13, 0.0))
	_wall_strings(b, wx)
	var mi := MeshInstance3D.new()
	mi.name = "HolidayLights"
	mi.mesh = b.commit()
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/shaders/festive_lights.gdshader")
	m.set_shader_parameter("twinkle", 0.0 if reduced else 1.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(mi)
	# warm glow from inside the tree onto the presents, the wall and the
	# curtain (no shadows; one light)
	var tl := OmniLight3D.new()
	tl.name = "TreeLight"
	tl.position = TREE + Vector3(0.0, 1.15, 0.55)
	tl.light_color = Color(1.0, 0.78, 0.5)
	tl.light_energy = 1.5
	tl.omni_range = 3.4
	tl.omni_attenuation = 1.5
	stage.add_child(tl)
	stage._light_pool(TREE + Vector3(0.0, 0.031, 0.75), Vector2(3.0, 2.2), Color(1.0, 0.74, 0.46), 0.15, 0.0)
	stage._light_pool(Vector3(TREE.x, 1.4, -3.45), Vector2(2.6, 2.8), Color(1.0, 0.7, 0.45), 0.1, 0.0, true)
	if not reduced:
		stage.add_child(_snowfall(wx))
		stage.add_child(_steam())


## A gentle pulse of the tree light (DormStage._process; nothing with
## Reduced Motion).
static func animate(stage: DormStage, t: float) -> void:
	var tl := stage.get_node_or_null("TreeLight") as OmniLight3D
	if tl:
		tl.light_energy = 1.5 + 0.14 * sin(t * 1.3) + 0.07 * sin(t * 3.1 + 1.0)


# ---------------------------------------------------------------------------
# (2.2 build 18) The side table: a mug of cocoa with marshmallows and a
# plate of cookies (solid; the steam is build_lights' little particles).

const COCOA_AT := Vector3(-1.78, 0.30, -2.06)


static func cocoa_and_cookies(k: MeshKit, at: Vector3) -> void:
	var gloss := 0.6
	# the mug: red with a cream band, cocoa inside, two marshmallows
	var mug := at + Vector3(0.1, 0.0, 0.05)
	k.cylinder(mug, 0.055, 0.1, Color("c7353e", gloss), 18)
	k.cylinder(mug + Vector3(0, 0.055, 0), 0.0565, 0.018, Color("f4ead6", gloss), 18, 0.0, false)
	k.cylinder(mug + Vector3(0, 0.094, 0), 0.047, 0.006, Color("6b3a1e"), 16)
	k.blob(mug + Vector3(-0.015, 0.103, 0.008), Vector3(0.016, 0.012, 0.016), Color("fbf6ee"), 3, 8)
	k.blob(mug + Vector3(0.018, 0.103, -0.01), Vector3(0.014, 0.011, 0.014), Color("fbf6ee"), 3, 8)
	# handle: a few small blobs in an arc on the mug's right
	for i in 5:
		var a := -PI * 0.5 + PI * float(i) / 4.0
		k.blob(mug + Vector3(0.062 + cos(a) * 0.028, 0.05 + sin(a) * 0.03, 0), Vector3(0.011, 0.011, 0.011), Color("c7353e", gloss), 3, 6)
	# the plate and three cookies with chocolate chips
	var plate := at + Vector3(-0.07, 0.0, 0.07)
	k.cylinder(plate, 0.13, 0.012, Color("f7f3ec", gloss), 24, 0.0, true, 0.15)
	var cookies := [Vector3(-0.04, 0.014, 0.02), Vector3(0.05, 0.014, -0.03), Vector3(0.0, 0.03, -0.0)]
	for ci in cookies.size():
		var cp := plate + (cookies[ci] as Vector3)
		k.cylinder(cp, 0.048, 0.014, Color("c98a4b"), 16)
		for d in 4:
			var da := float(d) * 1.7 + float(ci)
			k.blob(cp + Vector3(cos(da) * 0.024, 0.015, sin(da) * 0.024), Vector3(0.007, 0.004, 0.007), Color("4a2a16"), 2, 5)


## The cocoa's steam: a few soft puffs rising and fading (none with Reduced
## Motion).
static func _steam() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "CocoaSteam"
	p.position = COCOA_AT + Vector3(0.1, 0.17, 0.05)
	p.amount = 6
	p.lifetime = 2.6
	p.preprocess = 2.0
	p.direction = Vector3(0, 1, 0)
	p.spread = 12.0
	p.gravity = Vector3(0, 0.02, 0)
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.08
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(1, 1.4))
	p.scale_amount_curve = sc
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.set_color(1, Color(1, 1, 1, 0.0))
	g.add_point(0.25, Color(1, 0.97, 0.92, 0.32))
	p.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.07)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 16.0
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 2))
	m.albedo_texture = ImageTexture.create_from_image(img)
	q.material = m
	p.mesh = q
	return p


# ---------------------------------------------------------------------------
# The tree

## Radius of the tree's outline at height y (for lights and ornaments).
static func envelope(y: float) -> float:
	var r := 0.0
	for tr in TIERS:
		var base: float = tr[0]
		var h: float = tr[1]
		if y >= base and y <= base + h:
			r = maxf(r, float(tr[2]) * (1.0 - (y - base) / h))
	return r


static func _tree(k: MeshKit) -> void:
	# stand: a red skirt with a cream trim, a short trunk
	k.ellipse_disc(TREE + Vector3(0, 0.014, 0), 0.95, 0.88, Color("b8323c", FabricA.FABRIC), 28)
	k.ring(TREE + Vector3(0, 0.0, 0), 0.86, 0.97, 0.035, Color("f1e6cf", FabricA.FABRIC), 28)
	k.cylinder(TREE, 0.2, 0.18, Color("7a2a2f", FabricA.GLOSS), 16, 0.0, true, 0.17)
	k.cylinder(TREE + Vector3(0, 0.18, 0), 0.08, 0.3, Color("6b4630", FabricA.WOOD), 10)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1225
	for i in TIERS.size():
		var tr: Array = TIERS[i]
		_tier(k, TREE + Vector3(0, float(tr[0]), 0), float(tr[1]), float(tr[2]), 22 - i * 2, rng, i)
	# ornaments: round baubles hung around each tier's lower edge, a few
	# higher up; glossy so they catch the lamp and tree light
	var n := 0
	for i in TIERS.size():
		var tr: Array = TIERS[i]
		var count := 9 - i
		for j in count:
			var a := TAU * (float(j) + 0.5 * float(i % 2)) / float(count) + 0.3
			var y := float(tr[0]) + 0.16 + rng.randf_range(-0.03, 0.05)
			var r := envelope(y) * 0.97
			var c: Color = ORNAMENT_COLS[(n * 3 + i) % ORNAMENT_COLS.size()]
			var s := rng.randf_range(0.052, 0.07)
			var at := TREE + Vector3(cos(a) * r, y - s, sin(a) * r)
			k.soft_blob(at, Vector3(s, s, s), Color(c, FabricA.GLOSS), 4, 10)
			k.cylinder(at + Vector3(0, s * 0.85, 0), s * 0.32, s * 0.35, Color("d9c27a", FabricA.GLOSS), 6)
			n += 1


## One tier of branches: a cone whose rim zig-zags into branch tips that
## droop a little, lighter at the tips, with a dark underside (the home
## camera sits below the upper tiers).
static func _tier(k: MeshKit, base: Vector3, h: float, r: float, seg: int, rng: RandomNumberGenerator, idx: int) -> void:
	var apex := base + Vector3(0, h, 0)
	var rim: Array[Vector3] = []
	for s in seg * 2:
		var a := TAU * float(s) / float(seg * 2) + float(idx) * 0.37
		var tip := s % 2 == 0
		var rr := r * (1.0 if tip else 0.8) * rng.randf_range(0.95, 1.04)
		var dy := -0.07 if tip else 0.03
		rim.append(base + Vector3(cos(a) * rr, dy, sin(a) * rr))
	var inner := base + Vector3(0, h * 0.22, 0)
	for s in rim.size():
		var p0: Vector3 = rim[s]
		var p1: Vector3 = rim[(s + 1) % rim.size()]
		var n0 := _cone_n(p0 - base, h, r)
		var n1 := _cone_n(p1 - base, h, r)
		var na := (n0 + n1).normalized()
		var c0 := (NEEDLE_TIP if s % 2 == 0 else NEEDLE).darkened(0.04 * float(idx % 2))
		var c1 := (NEEDLE_TIP if (s + 1) % 2 == 0 else NEEDLE).darkened(0.04 * float(idx % 2))
		var ca := NEEDLE.darkened(0.25)
		k.tri_n(apex, p1, p0, Vector3.UP.lerp(na, 0.6).normalized(), n1, n0,
			Color(ca, FabricA.FABRIC), Color(c1, FabricA.FABRIC), Color(c0, FabricA.FABRIC))
		# underside, toward the trunk
		k.tri_n(inner, p0, p1, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN,
			Color(NEEDLE.darkened(0.55), FabricA.FABRIC), Color(NEEDLE.darkened(0.35), FabricA.FABRIC), Color(NEEDLE.darkened(0.35), FabricA.FABRIC))


static func _cone_n(rel: Vector3, h: float, r: float) -> Vector3:
	var d := Vector2(rel.x, rel.z)
	if d.length() < 0.0001:
		return Vector3.UP
	d = d.normalized()
	return Vector3(d.x * h, r, d.y * h).normalized()


# ---------------------------------------------------------------------------
# Presents

static func _presents(k: MeshKit) -> void:
	for p in PRESENTS:
		var size := Vector3(float(p[2]), float(p[3]), float(p[4]))
		_present(k, Vector3(float(p[0]), 0.0, float(p[1])), size, float(p[5]), p[6], p[7])
	# one small box stacked on the green one
	var g: Array = PRESENTS[1]
	_present(k, Vector3(float(g[0]) + 0.04, float(g[3]), float(g[1]) + 0.02), Vector3(0.26, 0.18, 0.24), 0.55, Color("e8434f"), Color("eef2f8"))


static func _present(k: MeshKit, foot: Vector3, size: Vector3, yaw: float, paper: Color, ribbon: Color) -> void:
	var c := foot + Vector3(0, size.y * 0.5, 0)
	k.chamfer_box(c, size, Color(paper, FabricA.PAPER), 0.025, yaw)
	# a ribbon both ways round the box, slightly proud of the paper
	var bw := 0.055
	k.chamfer_box(c, Vector3(size.x + 0.012, size.y + 0.012, bw), Color(ribbon, FabricA.GLOSS), 0.008, yaw)
	k.chamfer_box(c, Vector3(bw, size.y + 0.012, size.z + 0.012), Color(ribbon, FabricA.GLOSS), 0.008, yaw)
	# a bow: two loops and a knot on top
	var basis := Basis(Vector3.UP, yaw)
	var top := foot + Vector3(0, size.y + 0.02, 0)
	var loop := minf(0.09, minf(size.x, size.z) * 0.28)
	for sx in [-1.0, 1.0]:
		k.soft_blob(top + basis * Vector3(sx * loop * 0.85, loop * 0.35, 0), Vector3(loop, loop * 0.55, loop * 0.42), Color(ribbon, FabricA.GLOSS), 4, 8)
	k.soft_blob(top + Vector3(0, loop * 0.3, 0), Vector3(loop * 0.38, loop * 0.38, loop * 0.38), Color(ribbon.darkened(0.12), FabricA.GLOSS), 3, 8)


# ---------------------------------------------------------------------------
# Wall dressing

## A wreath: a ring of soft evergreen clumps with berries and a red bow.
static func _wreath(k: MeshKit, c: Vector3) -> void:
	var r := 0.3
	var rng := RandomNumberGenerator.new()
	rng.seed = 24
	for i in 16:
		var a := TAU * float(i) / 16.0
		var p := c + Vector3(cos(a) * r, sin(a) * r, 0.04)
		k.soft_blob(p, Vector3(0.11, 0.1, 0.06), Color(NEEDLE.lightened(rng.randf_range(0.0, 0.15)), FabricA.FABRIC), 3, 8)
	for i in 7:
		var a := TAU * float(i) / 7.0 + 0.4
		k.soft_blob(c + Vector3(cos(a) * r * 1.05, sin(a) * r * 1.05, 0.1), Vector3(0.028, 0.028, 0.028), Color(Color("d22a35"), FabricA.GLOSS), 3, 6)
	var bow := c + Vector3(0, -r - 0.02, 0.11)
	for sx in [-1.0, 1.0]:
		k.soft_blob(bow + Vector3(sx * 0.08, 0.02, 0), Vector3(0.09, 0.055, 0.03), Color(Color("c7353e"), FabricA.GLOSS), 4, 8)
		k.chamfer_box(bow + Vector3(sx * 0.05, -0.1, -0.01), Vector3(0.04, 0.16, 0.012), Color(Color("b52d36"), FabricA.GLOSS), 0.005, sx * 0.25)
	k.soft_blob(bow, Vector3(0.035, 0.035, 0.035), Color(Color("a8262f"), FabricA.GLOSS), 3, 8)


## A garland of evergreen along the window head, swagging between three
## pins, with red bows at the pins.
static func _garland(k: MeshKit, wx: float) -> void:
	var y0 := 3.36
	var z := -3.27
	var pins := [wx - 1.85, wx, wx + 1.85]
	for s in 2:
		var x0: float = pins[s]
		var x1: float = pins[s + 1]
		for i in 13:
			var u := float(i) / 12.0
			var x := lerpf(x0, x1, u)
			var y := y0 - 0.2 * sin(u * PI)
			k.soft_blob(Vector3(x, y, z), Vector3(0.1, 0.075, 0.07), Color(NEEDLE.lightened(0.05 * float(i % 3)), FabricA.FABRIC), 3, 7)
	for x in pins:
		var p := Vector3(float(x), y0 + 0.02, z + 0.05)
		for sx in [-1.0, 1.0]:
			k.soft_blob(p + Vector3(sx * 0.07, 0.0, 0), Vector3(0.075, 0.045, 0.03), Color(Color("c7353e"), FabricA.GLOSS), 4, 8)
		k.soft_blob(p, Vector3(0.03, 0.03, 0.03), Color(Color("a8262f"), FabricA.GLOSS), 3, 6)


# ---------------------------------------------------------------------------
# Bulbs (festive_lights shader)

static func _bulb(b: MeshKit, at: Vector3, col: Color, phase: float, r: float = 0.026) -> void:
	b.with(0.0, phase)
	b.soft_blob(at, Vector3(r, r * 1.25, r), col, 3, 7)


## Fairy lights spiralling up the tree, just outside its outline.
static func _tree_bulbs(b: MeshKit) -> void:
	var count := 104
	for i in count:
		var u := float(i) / float(count - 1)
		var y := lerpf(0.42, TREE_TOP - 0.18, u)
		var a := u * TAU * 5.2 + 0.6
		var r := envelope(y) * 0.92 + 0.03
		if r < 0.05:
			continue
		var col: Color = BULB_COLS[i % BULB_COLS.size()]
		_bulb(b, TREE + Vector3(cos(a) * r, y, sin(a) * r), col, fmod(float(i) * 0.6180339, 1.0), 0.024)


## A five-point star on top of the tree, facing the room (both faces).
static func _star(b: MeshKit, c: Vector3) -> void:
	b.with(1.0, 0.0)
	var outer := 0.17
	var inner := 0.075
	var pts: Array[Vector3] = []
	for i in 10:
		var a := PI * 0.5 + TAU * float(i) / 10.0
		var rr := outer if i % 2 == 0 else inner
		pts.append(c + Vector3(cos(a) * rr, sin(a) * rr, 0.0))
	var gold := Color("ffd76a")
	var core := Color("fff4cf")
	var n := Vector3(0, 0, 1)
	for i in 10:
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[(i + 1) % 10]
		b.tri_n(c + Vector3(0, 0, 0.025), p0, p1, n, n, n, core, gold, gold)
		b.tri_n(c - Vector3(0, 0, 0.025), p1, p0, -n, -n, -n, core, gold, gold)
	b.with(0.0, 0.0)


## String lights on a dark wire: swags along the back wall above the window
## and along the left wall.
static func _wall_strings(b: MeshKit, wx: float) -> void:
	var idx := 0
	# back wall: swags between pins, left and right of the window (the
	# garland's own bulbs dress the window), low enough to read in the home
	# framing; a higher run along the picture rail for the lobby framing
	for run in [[-5.85, wx - 2.05, 3.22], [wx + 2.05, 4.3, 3.22], [-5.85, 5.85, 4.25]]:
		var x0: float = run[0]
		var x_end: float = run[1]
		var y_top: float = run[2]
		var spans := maxi(1, int(round((x_end - x0) / 1.4)))
		var sw := (x_end - x0) / float(spans)
		for sp in spans:
			for i in 7:
				var u := (float(i) + 0.5) / 7.0
				var bx := x0 + sw * (float(sp) + u)
				_bulb(b, Vector3(bx, y_top - 0.22 * sin(u * PI), -3.33), BULB_COLS[idx % BULB_COLS.size()], fmod(float(idx) * 0.3819, 1.0))
				idx += 1
	# left wall, toward the camera
	var z := -3.3
	while z < 3.0:
		var z1 := z + 1.5
		for i in 7:
			var u := (float(i) + 0.5) / 7.0
			_bulb(b, Vector3(-5.86, 3.3 - 0.22 * sin(u * PI), lerpf(z, z1, u)), BULB_COLS[idx % BULB_COLS.size()], fmod(float(idx) * 0.3819, 1.0))
			idx += 1
		z = z1
	# along the garland under the window head
	for i in 15:
		var u := float(i) / 14.0
		var seg := 0 if u < 0.5 else 1
		var su := u * 2.0 - float(seg)
		var bx := lerpf(wx - 1.85 + 1.85 * float(seg), wx + 1.85 * float(seg), su)
		_bulb(b, Vector3(bx, 3.36 - 0.2 * sin(su * PI) - 0.07, -3.2), BULB_COLS[(idx + i) % BULB_COLS.size()], fmod(float(idx + i) * 0.7071, 1.0), 0.022)


## Snow drifting down past the window (seen only through the opening).
static func _snowfall(wx: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Snowfall"
	p.position = Vector3(wx, 4.2, -7.5)
	p.amount = 150
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(4.0, 0.3, 3.2)
	p.direction = Vector3(0.15, -1.0, 0.0)
	p.spread = 12.0
	p.gravity = Vector3(0.0, -0.35, 0.0)
	p.initial_velocity_min = 0.35
	p.initial_velocity_max = 0.6
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var q := QuadMesh.new()
	q.size = Vector2(0.045, 0.045)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.86, 0.9, 1.0, 0.85)
	q.material = mat
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## The dorm shader's surface treatments by vertex alpha (DormStage's
## constants, repeated so this file stands alone).
class FabricA:
	const WOOD := 0.9
	const FABRIC := 0.8
	const PAPER := 0.7
	const GLOSS := 0.6
