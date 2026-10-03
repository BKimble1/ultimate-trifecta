class_name CoinView
extends Node3D
## The round's gold coins (V6), presentation only: the host decides who
## collects what (MatchSim._check_coins); this shows the coins still out.
##
## Cheap by construction: every coin is one instance of a single MultiMesh
## with one shared material (spin and bob in the vertex shader), so a round
## costs one draw call and no material is created per pickup.  The material
## and the sparkle are made once per session and warmed under the loading
## screen (prepare); a pickup only flips that instance's custom data and
## restarts a pooled sparkle.

const SHADER := preload("res://assets/shaders/coin.gdshader")
const HEIGHT := 0.85

static var _mat: ShaderMaterial
static var _mesh: ArrayMesh
static var _spark_mat: StandardMaterial3D
static var _spark_mesh: QuadMesh

var mm: MultiMeshInstance3D
var count := 0
var _alive: PackedByteArray = PackedByteArray()
var _sparks: Array[CPUParticles3D] = []
var _spark_i := 0


## The shared mesh and material (session-wide).
static func shared_material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
	return _mat


static func coin_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	# a thick disc with a raised centre, standing up (faces along +-Z)
	var out := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	for part in [[0.34, 0.075], [0.24, 0.1]]:
		var cm := CylinderMesh.new()
		cm.top_radius = part[0]
		cm.bottom_radius = part[0]
		cm.height = part[1]
		cm.radial_segments = 20
		cm.rings = 1
		var a: Array = cm.get_mesh_arrays()
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var pv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		for i in idx:
			# rotate +90 deg about X: the cylinder's axis becomes Z
			var p: Vector3 = pv[i]
			var q: Vector3 = pn[i]
			v.append(Vector3(p.x, -p.z, p.y))
			n.append(Vector3(q.x, -q.z, q.y))
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh = out
	return _mesh


## coins: the round configuration's list [{id, x, z}].
func setup(coins: Array) -> void:
	count = coins.size()
	var m := MultiMesh.new()
	m.transform_format = MultiMesh.TRANSFORM_3D
	m.use_custom_data = true
	m.mesh = coin_mesh()
	m.instance_count = count
	_alive.resize(count)
	for i in count:
		var c: Dictionary = coins[i]
		m.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(float(c["x"]), HEIGHT, float(c["z"]))))
		m.set_instance_custom_data(i, Color(fposmod(float(c["x"]) * 0.13 + float(c["z"]) * 0.07, 1.0), 0, 0, 1))
		_alive[i] = 1
	mm = MultiMeshInstance3D.new()
	mm.name = "Coins"
	mm.multimesh = m
	mm.material_override = shared_material()
	mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mm)
	for k in 2:
		_sparks.append(_make_spark())


func _make_spark() -> CPUParticles3D:
	if _spark_mat == null:
		_spark_mat = StandardMaterial3D.new()
		_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_spark_mat.vertex_color_use_as_albedo = true
		_spark_mat.albedo_color = Color(1.0, 0.85, 0.4)
		_spark_mesh = QuadMesh.new()
		_spark_mesh.size = Vector2(0.12, 0.12)
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 10
	p.lifetime = 0.55
	p.explosiveness = 1.0
	p.mesh = _spark_mesh
	p.material_override = _spark_mat
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.4
	p.initial_velocity_max = 2.6
	p.gravity = Vector3(0, -3.0, 0)
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.2
	p.color = Color(1.0, 0.82, 0.35)
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


## Loading-time warm-up: the coin material and the sparkle are drawn once
## (far below the campus) before the round shows, so the first coin on
## screen or the first pickup compiles nothing.
func warm() -> void:
	for p in _sparks:
		p.global_position = Vector3(0, -80, 0)
		p.restart()


func is_out(i: int) -> bool:
	return i >= 0 and i < count and _alive[i] == 1


## Coins still out, from the host (bit i = coin i): reconnects and late
## snapshots converge on the host's state; a coin never comes back.
func set_mask(mask: int) -> void:
	for i in mini(count, 16):
		if (mask & (1 << i)) == 0 and _alive[i] == 1:
			_hide(i)


## A pickup event: hide that coin (once) and sparkle where it was.
func take(i: int) -> bool:
	if not is_out(i):
		return false
	_hide(i)
	var t := mm.multimesh.get_instance_transform(i).origin
	var p := _sparks[_spark_i % _sparks.size()]
	_spark_i += 1
	p.global_position = t
	p.restart()
	return true


func _hide(i: int) -> void:
	_alive[i] = 0
	var cd := mm.multimesh.get_instance_custom_data(i)
	mm.multimesh.set_instance_custom_data(i, Color(cd.r, 0, 0, 0))


func remaining() -> int:
	var n := 0
	for a in _alive:
		n += a
	return n


## A small gold coin for HUD chips (no texture).
static func draw_icon(ci: CanvasItem, c: Vector2, r: float) -> void:
	ci.draw_circle(c, r, Color(0.62, 0.42, 0.10))
	ci.draw_circle(c, r * 0.86, Color(1.0, 0.78, 0.26))
	ci.draw_arc(c, r * 0.56, 0, TAU, 20, Color(0.86, 0.58, 0.14), maxf(1.0, r * 0.14), true)
	ci.draw_circle(c + Vector2(-r * 0.3, -r * 0.32), r * 0.16, Color(1.0, 0.95, 0.75, 0.8))
