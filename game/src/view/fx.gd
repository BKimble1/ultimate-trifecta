class_name Fx
extends Node3D
## Short, restrained one-shot effects.  Purely cosmetic.
##
## Particles are CPUParticles3D (cheap and predictable on mobile) drawn as
## soft round billboards, kept in small pools and reused instead of being
## created and freed per effect.  Water ripples are sources in each water
## material's ripple array (several at once per pond), aged here every frame.

const POOL_MAX := 10              # emitters per kind
const RIPPLE_SLOTS := 6           # == water.gdshader RIPPLES
const RIPPLE_LIFE := 1.8

static var _soft_tex: GradientTexture2D
static var _ring_tex: GradientTexture2D
static var _drop_mats: Dictionary = {}

var _pools: Dictionary = {}       # kind -> Array[CPUParticles3D]
var _busy_until: Dictionary = {}  # emitter -> msec
var _foam_pool: Array[MeshInstance3D] = []
var _ripples: Dictionary = {}     # ShaderMaterial -> Array[Vector4] (x, z, age, strength)
var _drop_mesh: QuadMesh
var _quad: QuadMesh


func _ready() -> void:
	_drop_mesh = QuadMesh.new()
	_drop_mesh.size = Vector2(0.16, 0.16)
	_quad = QuadMesh.new()
	_quad.size = Vector2(0.18, 0.12)


static func soft_texture() -> GradientTexture2D:
	if _soft_tex == null:
		var g := Gradient.new()
		g.set_offset(0, 0.0)
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_offset(1, 1.0)
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.85))
		_soft_tex = GradientTexture2D.new()
		_soft_tex.gradient = g
		_soft_tex.fill = GradientTexture2D.FILL_RADIAL
		_soft_tex.fill_from = Vector2(0.5, 0.5)
		_soft_tex.fill_to = Vector2(0.5, 0.0)
		_soft_tex.width = 64
		_soft_tex.height = 64
	return _soft_tex


static func ring_texture() -> GradientTexture2D:
	if _ring_tex == null:
		var g := Gradient.new()
		g.set_offset(0, 0.0)
		g.set_color(0, Color(1, 1, 1, 0))
		g.set_offset(1, 1.0)
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.62, Color(1, 1, 1, 0.15))
		g.add_point(0.8, Color(1, 1, 1, 0.95))
		g.add_point(0.9, Color(1, 1, 1, 0.5))
		_ring_tex = GradientTexture2D.new()
		_ring_tex.gradient = g
		_ring_tex.fill = GradientTexture2D.FILL_RADIAL
		_ring_tex.fill_from = Vector2(0.5, 0.5)
		_ring_tex.fill_to = Vector2(0.5, 0.0)
		_ring_tex.width = 128
		_ring_tex.height = 128
	return _ring_tex


## Soft round billboard material for particles (colour from the emitter's
## colour/ramp, alpha from the texture).
static func drop_material(emission: float = 0.6) -> StandardMaterial3D:
	var key := snappedf(emission, 0.1)
	if _drop_mats.has(key):
		return _drop_mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = soft_texture()
	# water drops: never brighter than the tint (no blown-out white dots)
	m.albedo_color = Color(1, 1, 1, 1) * (0.85 + emission * 0.1)
	m.albedo_color.a = 1.0
	m.no_depth_test = false
	m.disable_receive_shadows = true
	_drop_mats[key] = m
	return m


static func _fade_ramp(col: Color, a: float = 0.75) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(col, a))
	g.set_color(1, Color(col, 0.0))
	g.add_point(0.6, Color(col, a * 0.8))
	return g


static func _shrink_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(0.7, 0.8))
	c.add_point(Vector2(1.0, 0.25))
	return c


## A continuous emitter for water dripping off a runner (CharacterView owns
## one per character, created on first use).
static func make_drip_emitter() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = 12
	p.lifetime = 0.55
	p.explosiveness = 0.0
	p.randomness = 0.6
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.08)
	p.mesh = q
	p.material_override = drop_material(0.4)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.22, 0.45, 0.16)
	p.direction = Vector3.DOWN
	p.spread = 10.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.6
	p.gravity = Vector3(0, -9.0, 0)
	p.color_ramp = _fade_ramp(Color(0.75, 0.9, 1.0))
	p.scale_amount_curve = _shrink_curve()
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func _emitter(kind: String, pos: Vector3, amount: int, life: float, col: Color, emission: float = 0.6) -> CPUParticles3D:
	var pool: Array = _pools.get(kind, [])
	_pools[kind] = pool
	var now := Time.get_ticks_msec()
	var p: CPUParticles3D = null
	for e in pool:
		if int(_busy_until.get(e, 0)) <= now:
			p = e
			break
	if p == null:
		if pool.size() >= POOL_MAX:
			# oldest one is recycled (never more than POOL_MAX alive per kind)
			p = pool.pop_front()
			pool.append(p)
		else:
			p = CPUParticles3D.new()
			p.one_shot = true
			p.emitting = false
			p.explosiveness = 0.95
			p.mesh = _drop_mesh
			p.local_coords = false
			p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			p.scale_amount_curve = _shrink_curve()
			add_child(p)
			pool.append(p)
	p.amount = maxi(1, amount)
	p.lifetime = life
	p.material_override = drop_material(emission)
	p.color_ramp = _fade_ramp(col)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINT
	p.gravity = Vector3(0, -9.8, 0)
	p.global_position = pos
	_busy_until[p] = now + int((life + 0.2) * 1000.0)
	# restart after the caller has set direction/spread/velocities this frame
	p.restart.call_deferred()
	return p


## Flat soft foam ring on the water surface, expanding and fading.
func _foam(pos: Vector3, col: Color, radius: float, life: float = 0.9) -> void:
	var mi: MeshInstance3D = null
	for f in _foam_pool:
		if not f.visible:
			mi = f
			break
	if mi == null:
		if _foam_pool.size() >= POOL_MAX:
			mi = _foam_pool.pop_front()
			_foam_pool.append(mi)
		else:
			mi = MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(2, 2)
			q.orientation = PlaneMesh.FACE_Y
			mi.mesh = q
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_texture = ring_texture()
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			_foam_pool.append(mi)
	var mat := mi.material_override as StandardMaterial3D
	# mostly white-blue foam; the water colour only tints it
	mat.albedo_color = Color(col.lerp(Color(0.86, 0.94, 1.0), 0.8), 0.34)
	mi.visible = true
	mi.global_position = pos + Vector3(0, 0.03, 0)
	mi.scale = Vector3.ONE * 0.25
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius, life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func() -> void: mi.visible = false)


## Water entry: the contact crown/burst, shaped by how the runner went in
## (0 walk-in: small crown; 1 jump: tall cannonball column; 2 dive: wide sheet).
func splash_impact(pos: Vector3, kind: int, col: Color, reduced: bool = false) -> void:
	var tint := col.lerp(Color(0.8, 0.91, 0.98), 0.7)
	var k := 0.6 if reduced else 1.0
	# soft white burst: a few large, faint puffs where the body went in
	var mist := _emitter("mist", pos + Vector3(0, 0.25, 0), int(10 * k), 0.55, Color(0.9, 0.96, 1.0), 0.2)
	mist.color_ramp = _fade_ramp(Color(0.9, 0.96, 1.0), 0.32)
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	mist.emission_sphere_radius = 0.35
	mist.direction = Vector3.UP
	mist.spread = 60.0
	mist.initial_velocity_min = 0.6
	mist.initial_velocity_max = 1.6
	mist.gravity = Vector3(0, -2.0, 0)
	mist.scale_amount_min = 3.5 if kind != 0 else 2.5
	mist.scale_amount_max = 6.0 if kind != 0 else 4.0
	match kind:
		1:
			var p := _emitter("crown", pos + Vector3(0, 0.15, 0), int(46 * k), 1.0, tint, 1.0)
			p.direction = Vector3.UP
			p.spread = 16.0
			p.initial_velocity_min = 4.5
			p.initial_velocity_max = 7.5
			p.gravity = Vector3(0, -15, 0)
			p.scale_amount_min = 0.35
			p.scale_amount_max = 1.4
			var r := _emitter("crown_ring", pos + Vector3(0, 0.1, 0), int(30 * k), 0.8, tint, 0.8)
			r.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
			r.emission_ring_axis = Vector3.UP
			r.emission_ring_radius = 0.45
			r.emission_ring_inner_radius = 0.35
			r.emission_ring_height = 0.0
			r.direction = Vector3.UP
			r.spread = 28.0
			r.initial_velocity_min = 2.5
			r.initial_velocity_max = 4.0
			r.gravity = Vector3(0, -12, 0)
			r.scale_amount_min = 0.3
			r.scale_amount_max = 1.0
			_foam(pos, col, 1.9)
		2:
			var p := _emitter("sheet", pos + Vector3(0, 0.1, 0), int(54 * k), 0.85, tint, 0.9)
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
			p.emission_ring_axis = Vector3.UP
			p.emission_ring_radius = 0.6
			p.emission_ring_inner_radius = 0.2
			p.emission_ring_height = 0.0
			p.direction = Vector3.UP
			p.spread = 62.0
			p.initial_velocity_min = 2.4
			p.initial_velocity_max = 4.6
			p.gravity = Vector3(0, -12, 0)
			p.scale_amount_min = 0.35
			p.scale_amount_max = 1.3
			_foam(pos, col, 2.3, 1.0)
		_:
			var p := _emitter("crown", pos + Vector3(0, 0.1, 0), int(28 * k), 0.8, tint, 0.8)
			p.direction = Vector3.UP
			p.spread = 30.0
			p.initial_velocity_min = 2.6
			p.initial_velocity_max = 4.4
			p.gravity = Vector3(0, -13, 0)
			p.scale_amount_min = 0.3
			p.scale_amount_max = 1.1
			_foam(pos, col, 1.5)


## The runner ducks under before reappearing at the shore: a small gulp of
## bubbles and foam.
func duck_under(pos: Vector3, reduced: bool = false) -> void:
	var p := _emitter("bubbles", pos + Vector3(0, 0.05, 0), 10 if reduced else 16, 0.6, Color(0.85, 0.95, 1.0), 0.6)
	p.direction = Vector3.UP
	p.spread = 40.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.0
	p.gravity = Vector3(0, -6, 0)
	p.scale_amount_min = 0.4
	p.scale_amount_max = 0.9
	_foam(pos, Color(0.8, 0.95, 1.0), 1.2, 0.6)


## Popping out at the shore exit: water shaken off in every direction.
func shore_pop(pos: Vector3, reduced: bool = false) -> void:
	var p := _emitter("shake", pos + Vector3(0, 0.8, 0), 12 if reduced else 24, 0.6, Color(0.8, 0.93, 1.0), 0.5)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.3
	p.direction = Vector3.UP
	p.spread = 100.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.6
	p.gravity = Vector3(0, -9, 0)
	p.scale_amount_min = 0.4
	p.scale_amount_max = 0.8


## Generic splash (splash bomb hits): soft spray + foam.
func splash(pos: Vector3, col: Color, big: bool) -> void:
	var p := _emitter("crown", pos + Vector3(0, 0.1, 0), 40 if big else 18, 1.0, col.lerp(Color(0.8, 0.95, 1.0), 0.5), 1.0)
	p.direction = Vector3.UP
	p.spread = 35.0
	p.initial_velocity_min = 4.0 if big else 2.5
	p.initial_velocity_max = 7.0 if big else 4.5
	p.gravity = Vector3(0, -14, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.6
	_foam(pos, col, 3.0 if big else 1.8)


## One expanding ripple on a water surface.  `w` = {"mat": ShaderMaterial,
## "center": Vector2} (CampusBuilder water).  Up to RIPPLE_SLOTS ripples run
## at once per water; a new one replaces the oldest.
func ripple(w: Dictionary, pos: Vector3, strength: float = 1.0) -> void:
	if not w.has("mat"):
		return
	var mat: ShaderMaterial = w["mat"]
	var c: Vector2 = w.get("center", Vector2.ZERO)
	var arr: Array = _ripples.get(mat, [])
	var src := Vector4(pos.x - c.x, pos.z - c.y, 0.0, strength)
	if arr.size() < RIPPLE_SLOTS:
		arr.append(src)
	else:
		var oldest := 0
		for i in arr.size():
			if (arr[i] as Vector4).z > (arr[oldest] as Vector4).z:
				oldest = i
		arr[oldest] = src
	_ripples[mat] = arr
	_push_ripples(mat, arr)


## Back-compat name used by older call sites.
func flash_water(mat: ShaderMaterial, local_xz: Vector2 = Vector2.ZERO) -> void:
	ripple({"mat": mat, "center": Vector2.ZERO}, Vector3(local_xz.x, 0, local_xz.y), 1.0)


func active_ripples(mat: ShaderMaterial) -> int:
	return (_ripples.get(mat, []) as Array).size()


func _push_ripples(mat: ShaderMaterial, arr: Array) -> void:
	var packed: Array[Vector4] = []
	for i in RIPPLE_SLOTS:
		packed.append(arr[i] if i < arr.size() else Vector4(0, 0, RIPPLE_LIFE, 0))
	mat.set_shader_parameter("ripples", packed)


func _process(delta: float) -> void:
	for mat in _ripples.keys():
		var arr: Array = _ripples[mat]
		var keep: Array = []
		for r in arr:
			var v: Vector4 = r
			v.z += delta
			if v.z < RIPPLE_LIFE:
				keep.append(v)
		_push_ripples(mat, keep)
		if keep.is_empty():
			_ripples.erase(mat)
		else:
			_ripples[mat] = keep


func whistle_burst(pos: Vector3) -> void:
	var p := _emitter("whistle", pos + Vector3(0, 1.6, 0), 14, 0.9, Color(1.0, 0.9, 0.3), 2.0)
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -1, 0)
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.4
	_foam(pos, Color(1.0, 0.85, 0.3), 2.5, 0.7)


func confetti(pos: Vector3) -> void:
	for col in [Color(1.0, 0.4, 0.5), Color(0.4, 0.8, 1.0), Color(1.0, 0.9, 0.3), Color(0.5, 1.0, 0.5)]:
		var p := _emitter("confetti", pos + Vector3(0, 1.5, 0), 14, 1.6, col, 0.8)
		p.mesh = _quad
		p.material_override = _confetti_mat()
		p.direction = Vector3.UP
		p.spread = 60.0
		p.initial_velocity_min = 3.0
		p.initial_velocity_max = 6.0
		p.gravity = Vector3(0, -5, 0)
		p.angular_velocity_min = -360.0
		p.angular_velocity_max = 360.0
		p.particle_flag_rotate_y = true


var _conf_mat: StandardMaterial3D


func _confetti_mat() -> StandardMaterial3D:
	if _conf_mat == null:
		_conf_mat = StandardMaterial3D.new()
		_conf_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_conf_mat.vertex_color_use_as_albedo = true
		_conf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_conf_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return _conf_mat


func bump(pos: Vector3) -> void:
	var p := _emitter("bump", pos + Vector3(0, 1.0, 0), 10, 0.5, Color(1.0, 1.0, 1.0), 1.5)
	p.spread = 180.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.0
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2


func poof(pos: Vector3) -> void:
	var p := _emitter("poof", pos + Vector3(0, 0.6, 0), 16, 0.7, Color(0.75, 0.85, 1.0), 0.8)
	p.spread = 180.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.2
	p.gravity = Vector3(0, 1.5, 0)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 3.5


func turbo(pos: Vector3) -> void:
	var p := _emitter("turbo", pos + Vector3(0, 0.2, 0), 16, 0.5, Color(1.0, 0.6, 0.2), 1.6)
	p.spread = 40.0
	p.direction = Vector3.UP
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
