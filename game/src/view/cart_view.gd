class_name CartView
extends Node3D
## A chunky, slightly ridiculous Night Watch golf cart. Presentation only:
## body roll/pitch, spinning wheels and the beacon are cosmetic overlays.

var chassis: Node3D
var wheels: Array[Node3D] = []
var front_wheels: Array[Node3D] = []
var beacon: MeshInstance3D
var beacon_light: OmniLight3D
var head_beam: MeshInstance3D
var splash_fx: Node3D
var wheel_rot: float = 0.0
var vis_yaw: float = 0.0
var roll: float = 0.0
var pitch: float = 0.0
var prev_speed: float = 0.0
var t: float = 0.0
var rs: Dictionary = {}
var engine: AudioStreamPlayer3D


func setup(index: int) -> void:
	PropKit.init_meshes()
	var sph := PropKit.sphere
	var box := PropKit.box
	var cyl := PropKit.cyl
	chassis = Node3D.new()
	add_child(chassis)
	var accent := Color(1.0, 0.55, 0.15) if index == 0 else Color(0.25, 0.75, 0.95)
	var white := Color(0.92, 0.93, 0.96)
	# tub body
	_mi(chassis, box, PropKit.mat(white), Vector3(0, 0.55, 0.1), Vector3(1.5, 0.5, 2.5))
	_mi(chassis, sph, PropKit.mat(white), Vector3(0, 0.62, -1.05), Vector3(1.5, 0.6, 0.7))
	_mi(chassis, box, PropKit.mat(accent), Vector3(0, 0.62, 0.1), Vector3(1.54, 0.12, 2.52))
	# bench seat + back
	_mi(chassis, box, PropKit.mat(Color(0.2, 0.22, 0.3)), Vector3(0, 0.95, 0.35), Vector3(1.3, 0.2, 0.7))
	_mi(chassis, box, PropKit.mat(Color(0.2, 0.22, 0.3)), Vector3(0, 1.3, 0.72), Vector3(1.3, 0.6, 0.15))
	# canopy on posts
	for px in [-0.68, 0.68]:
		for pz in [-0.65, 0.95]:
			_mi(chassis, cyl, PropKit.mat(Color(0.7, 0.72, 0.78)), Vector3(px, 1.55, pz), Vector3(0.06, 1.3, 0.06))
	_mi(chassis, box, PropKit.mat(accent), Vector3(0, 2.22, 0.15), Vector3(1.6, 0.12, 2.0))
	_mi(chassis, box, PropKit.mat(white), Vector3(0, 2.32, 0.15), Vector3(1.4, 0.1, 1.8))
	# steering column + wheel
	_mi(chassis, cyl, PropKit.mat(Color(0.15, 0.15, 0.2)), Vector3(-0.35, 1.05, -0.45), Vector3(0.05, 0.6, 0.05), Vector3(0.6, 0, 0))
	_mi(chassis, cyl, PropKit.mat(Color(0.15, 0.15, 0.2)), Vector3(-0.35, 1.32, -0.3), Vector3(0.36, 0.04, 0.36), Vector3(0.9, 0, 0))
	# headlights (emissive) + soft beam
	for hx in [-0.5, 0.5]:
		_mi(chassis, sph, PropKit.mat(Color(1.0, 0.95, 0.75), 0.0, Color.WHITE, 2.5), Vector3(hx, 0.7, -1.38), Vector3(0.24, 0.24, 0.12))
	head_beam = MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.3
	bm.bottom_radius = 1.6
	bm.height = 7.0
	bm.cap_top = false
	bm.cap_bottom = false
	head_beam.mesh = bm
	var gm := ShaderMaterial.new()
	gm.shader = preload("res://assets/shaders/glow_add.gdshader")
	gm.set_shader_parameter("color", Color(1.0, 0.9, 0.7))
	gm.set_shader_parameter("intensity", 0.07)
	gm.set_shader_parameter("mode", 2.0)
	head_beam.material_override = gm
	head_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head_beam.rotation = Vector3(-PI * 0.5 + 0.12, 0, 0)
	head_beam.position = Vector3(0, 0.55, -4.8)
	chassis.add_child(head_beam)
	# rotating orange beacon on the roof (funny, not police)
	beacon = _mi(chassis, sph, PropKit.mat(Color(1.0, 0.6, 0.1), 0.0, Color.WHITE, 2.0), Vector3(0, 2.48, 0.15), Vector3(0.3, 0.26, 0.3))
	beacon_light = OmniLight3D.new()
	beacon_light.light_color = Color(1.0, 0.6, 0.2)
	beacon_light.light_energy = 1.2
	beacon_light.omni_range = 7.0
	beacon_light.position = Vector3(0, 2.6, 0.15)
	chassis.add_child(beacon_light)
	# electric motor hum (looped), pitch follows speed
	engine = AudioStreamPlayer3D.new()
	var st: AudioStream = load("res://assets/audio/cart_loop.wav")
	if st is AudioStreamWAV:
		var w := st as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate) - 1
	engine.stream = st
	engine.max_distance = 45.0
	engine.unit_size = 5.0
	engine.volume_db = -12.0
	add_child(engine)
	# wheels
	for wx in [-0.72, 0.72]:
		for wz in [-0.85, 0.95]:
			var pivot := Node3D.new()
			pivot.position = Vector3(wx, 0.32, wz)
			add_child(pivot)
			var spin := Node3D.new()
			pivot.add_child(spin)
			_mi(spin, cyl, PropKit.mat(Color(0.1, 0.1, 0.12)), Vector3.ZERO, Vector3(0.62, 0.26, 0.62), Vector3(0, 0, PI * 0.5))
			_mi(spin, cyl, PropKit.mat(Color(0.85, 0.85, 0.9)), Vector3(0.0, 0, 0), Vector3(0.3, 0.28, 0.3), Vector3(0, 0, PI * 0.5))
			_mi(spin, box, PropKit.mat(Color(0.6, 0.6, 0.65)), Vector3.ZERO, Vector3(0.29, 0.5, 0.08))
			wheels.append(spin)
			if wz < 0.0:
				front_wheels.append(pivot)


func _mi(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3, scl: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.scale = scl
	mi.rotation = rot
	parent.add_child(mi)
	return mi


## rs: pos, yaw, speed, steer, occupied, slowed
func apply_state(state_rs: Dictionary, delta: float, snap: bool = false) -> void:
	rs = state_rs
	var tp: Vector3 = rs.get("pos", global_position)
	if snap or global_position.distance_to(tp) > 8.0:
		global_position = tp
	else:
		global_position = global_position.lerp(tp, clampf(delta * 30.0, 0.0, 1.0))
	var yaw: float = rs.get("yaw", 0.0)
	vis_yaw = yaw if snap else lerp_angle(vis_yaw, yaw, clampf(delta * 18.0, 0.0, 1.0))
	rotation.y = vis_yaw


func _process(delta: float) -> void:
	if chassis == null:
		return
	t += delta
	var speed: float = rs.get("speed", 0.0)
	var steer: float = rs.get("steer", 0.0)
	wheel_rot -= speed * delta / 0.31
	for w in wheels:
		w.rotation.x = wheel_rot
	for fw in front_wheels:
		fw.rotation.y = lerpf(fw.rotation.y, -steer * 0.45, clampf(delta * 10.0, 0.0, 1.0))
	var acc := (speed - prev_speed) / maxf(delta, 0.001)
	prev_speed = speed
	roll = lerpf(roll, steer * clampf(absf(speed) / 11.0, 0.0, 1.0) * 0.09, clampf(delta * 6.0, 0.0, 1.0))
	pitch = lerpf(pitch, clampf(-acc * 0.006, -0.06, 0.06), clampf(delta * 5.0, 0.0, 1.0))
	chassis.rotation = Vector3(pitch, 0, roll)
	var occupied: bool = rs.get("occupied", false)
	var slowed: bool = rs.get("slowed", false)
	beacon_light.visible = occupied
	beacon_light.light_energy = 0.8 + 0.6 * absf(sin(t * 6.0))
	beacon.rotation.y = t * 8.0
	head_beam.visible = occupied
	if engine:
		if occupied and not engine.playing:
			engine.play()
		elif not occupied and engine.playing:
			engine.stop()
		engine.pitch_scale = 0.7 + clampf(absf(speed) / 11.0, 0.0, 1.0) * 0.9
		engine.volume_db = linear_to_db(maxf(Sfx.sfx_volume, 0.001)) - 14.0 + clampf(absf(speed) / 11.0, 0.0, 1.0) * 6.0
	chassis.position.y = (0.03 * sin(t * 30.0) if occupied and absf(speed) > 1.0 else 0.0) + (0.05 * sin(t * 20.0) if slowed else 0.0)
