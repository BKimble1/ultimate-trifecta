class_name Fx
extends Node3D
## Short, restrained one-shot effects (CPU particles: cheap and predictable on
## mobile). Purely cosmetic.

var _drop_mesh: SphereMesh
var _quad: QuadMesh


func _ready() -> void:
	_drop_mesh = SphereMesh.new()
	_drop_mesh.radius = 0.09
	_drop_mesh.height = 0.18
	_drop_mesh.radial_segments = 6
	_drop_mesh.rings = 3
	_quad = QuadMesh.new()
	_quad.size = Vector2(0.18, 0.12)


func _emitter(pos: Vector3, amount: int, life: float, mesh: Mesh, col: Color, emission: float = 0.6) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.95
	p.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = emission
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p.material_override = m
	p.position = pos
	add_child(p)
	p.emitting = true
	get_tree().create_timer(life + 0.5).timeout.connect(p.queue_free)
	return p


func splash(pos: Vector3, col: Color, big: bool) -> void:
	var p := _emitter(pos + Vector3(0, 0.1, 0), 48 if big else 20, 1.1, _drop_mesh, col.lerp(Color(0.8, 0.95, 1.0), 0.5), 1.2)
	p.direction = Vector3.UP
	p.spread = 35.0
	p.initial_velocity_min = 4.0 if big else 2.5
	p.initial_velocity_max = 8.0 if big else 4.5
	p.gravity = Vector3(0, -14, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.6
	_ring(pos + Vector3(0, 0.05, 0), col, 3.5 if big else 2.0)


func _ring(pos: Vector3, col: Color, radius: float) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.85
	tm.outer_radius = 1.0
	tm.rings = 24
	tm.ring_segments = 6
	mi.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(col.r, col.g, col.b, 0.8)
	mi.material_override = m
	mi.position = pos
	mi.scale = Vector3(0.3, 0.3, 0.3)
	add_child(mi)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, 0.4, radius), 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.7)
	tw.chain().tween_callback(mi.queue_free)


## One expanding ripple from the splash point (water-local xz); the surface
## itself does not flash.
func flash_water(mat: ShaderMaterial, local_xz: Vector2 = Vector2.ZERO) -> void:
	mat.set_shader_parameter("splash_local", local_xz)
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("splash_flash", v), 1.0, 0.0, 1.4)


func whistle_burst(pos: Vector3) -> void:
	var p := _emitter(pos + Vector3(0, 1.6, 0), 14, 0.9, _drop_mesh, Color(1.0, 0.9, 0.3), 2.0)
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -1, 0)
	_ring(pos + Vector3(0, 0.1, 0), Color(1.0, 0.85, 0.3), 2.5)


func confetti(pos: Vector3) -> void:
	for col in [Color(1.0, 0.4, 0.5), Color(0.4, 0.8, 1.0), Color(1.0, 0.9, 0.3), Color(0.5, 1.0, 0.5)]:
		var p := _emitter(pos + Vector3(0, 1.5, 0), 14, 1.6, _quad, col, 0.8)
		p.direction = Vector3.UP
		p.spread = 60.0
		p.initial_velocity_min = 3.0
		p.initial_velocity_max = 6.0
		p.gravity = Vector3(0, -5, 0)
		p.angular_velocity_min = -360.0
		p.angular_velocity_max = 360.0
		p.particle_flag_rotate_y = true


func bump(pos: Vector3) -> void:
	var p := _emitter(pos + Vector3(0, 1.0, 0), 10, 0.5, _drop_mesh, Color(1.0, 1.0, 1.0), 1.5)
	p.spread = 180.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.0
	p.gravity = Vector3.ZERO


func poof(pos: Vector3) -> void:
	var p := _emitter(pos + Vector3(0, 0.6, 0), 16, 0.7, _drop_mesh, Color(0.75, 0.85, 1.0), 0.8)
	p.spread = 180.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.2
	p.gravity = Vector3(0, 1.5, 0)
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0


func turbo(pos: Vector3) -> void:
	var p := _emitter(pos + Vector3(0, 0.2, 0), 16, 0.5, _drop_mesh, Color(1.0, 0.6, 0.2), 1.6)
	p.spread = 40.0
	p.direction = Vector3.UP
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.0
