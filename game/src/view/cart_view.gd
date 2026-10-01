class_name CartView
extends Node3D
## Night Watch golf cart (presentation only).  Built from a handful of merged
## meshes: one body (tub, bumpers, seats, dash, canopy, lights, decals), four
## tyre+hub wheels, a steering wheel and the roof beacon.  The driver's seat
## and the steering wheel match the character's seated rig
## (tools/character/anims.py WHEEL_C / STEER_DEG), so hands sit on the rim.
## Position/yaw come from the controller already interpolated at render
## time; roll/pitch/wheel spin are cosmetic overlays.

## where the driver's character origin sits (cart-local, -Z forward)
const SEAT := Vector3(-0.35, 0.75, 0.25)
## steering wheel centre/axis (= SEAT + the rig's wheel point) and turn ratio
const WHEEL_POS := Vector3(-0.35, 1.25, -0.02)
const WHEEL_AXIS := Vector3(0, 0.8, 0.6)
const STEER_DEG := 50.0

static var _body_mesh: Dictionary = {}   # accent colour -> ArrayMesh
static var _wheel_mesh: ArrayMesh
static var _steer_mesh: ArrayMesh
static var _beacon_mesh: ArrayMesh
static var _mat: ShaderMaterial

var chassis: Node3D
var wheels: Array[Node3D] = []
var front_wheels: Array[Node3D] = []
var steering: Node3D
var beacon: MeshInstance3D
var beacon_light: OmniLight3D
var head_beam: MeshInstance3D
var wheel_rot: float = 0.0
var roll: float = 0.0
var pitch: float = 0.0
var prev_speed: float = 0.0
var t: float = 0.0
var rs: Dictionary = {}
var engine: AudioStreamPlayer3D


static func _material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = preload("res://assets/shaders/world_vc.gdshader")
		_mat.set_shader_parameter("moon_rim_color", Color(0.4, 0.5, 0.85))
	return _mat


static func _build_body(accent: Color) -> ArrayMesh:
	var k := MeshKit.new()
	var white := Color("eef0f4")
	var white_d := Color("cfd4de")
	var dark := Color("2a2f3c")
	var seat := Color("3a4258")
	# tub: lower body with rounded nose, side skirts, accent stripe
	k.box(Vector3(0, 0.5, 0.15), Vector3(1.42, 0.42, 2.3), white, 0.0, 0.0, white)
	k.box(Vector3(0, 0.52, -1.0), Vector3(1.36, 0.46, 0.5), white, 0.0, 0.0, white)
	k.blob(Vector3(0, 0.56, -1.22), Vector3(0.68, 0.26, 0.24), white, 4, 12)
	k.box(Vector3(0, 0.62, 0.15), Vector3(1.46, 0.08, 2.32), accent)
	k.box(Vector3(0, 0.3, -1.38), Vector3(1.3, 0.14, 0.12), dark)            # front bumper
	k.box(Vector3(0, 0.3, 1.33), Vector3(1.3, 0.14, 0.12), dark)             # rear bumper
	for sx in [-1.0, 1.0]:
		k.box(Vector3(sx * 0.72, 0.36, 0.15), Vector3(0.04, 0.14, 1.2), white_d)
	# floor + dash + steering column base
	k.box(Vector3(0, 0.72, -0.35), Vector3(1.3, 0.04, 1.1), dark)
	k.box(Vector3(0, 1.0, -0.72), Vector3(1.32, 0.42, 0.22), dark, 0.0, 0.0, Color("3a4152"))
	# slanted steering column from the dash up to the wheel hub
	var col_a := Vector3(-0.35, 0.98, -0.66)
	var col_b := WHEEL_POS - WHEEL_AXIS.normalized() * 0.03
	var cd := col_b - col_a
	var ang := atan2(cd.z, cd.y)
	k.box_xf(Transform3D(Basis(Vector3.RIGHT, ang) * Basis.from_scale(Vector3(0.05, cd.length(), 0.05)), (col_a + col_b) * 0.5), Color("1d2029"))
	# bench seat + backrest (driver sits at SEAT, cushion top ~0.85)
	k.box(Vector3(0, 0.8, 0.3), Vector3(1.28, 0.14, 0.62), seat, 0.0, 0.0, seat.lightened(0.08))
	k.box(Vector3(0, 1.15, 0.62), Vector3(1.28, 0.56, 0.14), seat, 0.0, 0.0, seat.lightened(0.06))
	# canopy: four posts and a roof with an accent edge
	for px in [-0.66, 0.66]:
		for pz in [-0.58, 0.72]:
			k.cylinder(Vector3(px, 0.62, pz), 0.035, 1.55, Color("c4c9d4"), 6)
	k.box(Vector3(0, 2.2, 0.07), Vector3(1.5, 0.08, 1.75), accent)
	k.box(Vector3(0, 2.26, 0.07), Vector3(1.38, 0.06, 1.6), white)
	# lights: headlights (emissive), taillights, side "WATCH" decal blocks
	for hx in [-0.48, 0.48]:
		k.blob(Vector3(hx, 0.66, -1.42), Vector3(0.13, 0.11, 0.05), Color("fff2c9"), 3, 10, 2.4)
		k.box(Vector3(hx, 0.58, 1.31), Vector3(0.2, 0.08, 0.03), Color("ff5b5b"), 0.0, 1.2)
	for sx in [-1.0, 1.0]:
		k.box(Vector3(sx * 0.715, 0.48, -0.15), Vector3(0.02, 0.12, 0.7), accent)
	return k.commit()


static func _build_wheel() -> ArrayMesh:
	var k := MeshKit.new()
	# tyre (axis along X), sidewall, hub cap and lug ring
	var tyre := Color("16181d")
	for i in 14:
		var a0 := TAU * float(i) / 14.0
		var a1 := TAU * float(i + 1) / 14.0
		var r := 0.31
		var w := 0.13
		var p0 := Vector3(0, cos(a0) * r, sin(a0) * r)
		var p1 := Vector3(0, cos(a1) * r, sin(a1) * r)
		k.quad(p0 + Vector3(w, 0, 0), p1 + Vector3(w, 0, 0), p1 + Vector3(-w, 0, 0), p0 + Vector3(-w, 0, 0), tyre)
	for sx in [-1.0, 1.0]:
		for i in 14:
			var a0 := TAU * float(i) / 14.0
			var a1 := TAU * float(i + 1) / 14.0
			var o0 := Vector3(sx * 0.13, cos(a0) * 0.31, sin(a0) * 0.31)
			var o1 := Vector3(sx * 0.13, cos(a1) * 0.31, sin(a1) * 0.31)
			var i0 := Vector3(sx * 0.14, cos(a0) * 0.17, sin(a0) * 0.17)
			var i1 := Vector3(sx * 0.14, cos(a1) * 0.17, sin(a1) * 0.17)
			if sx > 0:
				k.quad(o1, o0, i0, i1, Color("22252c"))
				k.tri(Vector3(sx * 0.15, 0, 0), i1, i0, Color("d7dbe3"))
			else:
				k.quad(o0, o1, i1, i0, Color("22252c"))
				k.tri(Vector3(sx * 0.15, 0, 0), i0, i1, Color("d7dbe3"))
	return k.commit()


static func _build_steering() -> ArrayMesh:
	var k := MeshKit.new()
	# rim in the local XZ plane (axis +Y), three spokes; rotated to WHEEL_AXIS by the node
	k.ring(Vector3(0, -0.015, 0), 0.15, 0.185, 0.03, Color("1d2029"), 20)
	for i in 3:
		var a := TAU * float(i) / 3.0 + PI * 0.5
		var d := Vector3(cos(a), 0, sin(a))
		k.box(d * 0.08, Vector3(0.16 if absf(d.x) > 0.5 else 0.03, 0.02, 0.03 if absf(d.x) > 0.5 else 0.16), Color("3a3f4c"))
	k.cylinder(Vector3(0, -0.02, 0), 0.045, 0.04, Color("ffc668"), 8)
	return k.commit()


func setup(index: int) -> void:
	var accent := Color("ffa05c") if index == 0 else Color("6fd8cc")
	var key := accent.to_html()
	if not _body_mesh.has(key):
		_body_mesh[key] = _build_body(accent)
	if _wheel_mesh == null:
		_wheel_mesh = _build_wheel()
		_steer_mesh = _build_steering()
	chassis = Node3D.new()
	add_child(chassis)
	var body := MeshInstance3D.new()
	body.mesh = _body_mesh[key]
	body.material_override = _material()
	chassis.add_child(body)
	steering = Node3D.new()
	steering.position = WHEEL_POS
	chassis.add_child(steering)
	var spin := MeshInstance3D.new()
	spin.mesh = _steer_mesh
	spin.material_override = _material()
	# the rim is modelled around +Y; tilt +Y onto WHEEL_AXIS
	spin.basis = Basis(Quaternion(Vector3.UP, WHEEL_AXIS.normalized()))
	spin.position = Vector3.ZERO
	steering.add_child(spin)
	steering.set_meta("spin", spin)
	head_beam = MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.25
	bm.bottom_radius = 1.5
	bm.height = 7.0
	bm.cap_top = false
	bm.cap_bottom = false
	head_beam.mesh = bm
	var gm := ShaderMaterial.new()
	gm.shader = preload("res://assets/shaders/glow_add.gdshader")
	gm.set_shader_parameter("color", Color(1.0, 0.92, 0.75))
	gm.set_shader_parameter("intensity", 0.06)
	gm.set_shader_parameter("mode", 2.0)
	head_beam.material_override = gm
	head_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head_beam.rotation = Vector3(PI * 0.5 + 0.1, 0, 0)
	head_beam.position = Vector3(0, 0.55, -4.9)
	chassis.add_child(head_beam)
	PropKit.init_meshes()
	beacon = MeshInstance3D.new()
	beacon.mesh = PropKit.sphere
	beacon.material_override = PropKit.mat(Color(1.0, 0.62, 0.2), 0.0, Color.WHITE, 1.6)
	beacon.position = Vector3(0, 2.38, 0.07)
	beacon.scale = Vector3(0.26, 0.22, 0.26)
	chassis.add_child(beacon)
	beacon_light = OmniLight3D.new()
	beacon_light.light_color = Color(1.0, 0.62, 0.25)
	beacon_light.light_energy = 1.0
	beacon_light.omni_range = 6.0
	beacon_light.position = Vector3(0, 2.5, 0.07)
	chassis.add_child(beacon_light)
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
	for wx in [-0.7, 0.7]:
		for wz in [-0.88, 0.92]:
			var pivot := Node3D.new()
			pivot.position = Vector3(wx, 0.31, wz)
			add_child(pivot)
			var wspin := MeshInstance3D.new()
			wspin.mesh = _wheel_mesh
			wspin.material_override = _material()
			pivot.add_child(wspin)
			wheels.append(wspin)
			if wz < 0.0:
				front_wheels.append(pivot)


## rs: pos, yaw, speed, steer, occupied, slowed (render-time values)
func apply_state(state_rs: Dictionary, _delta: float = 0.0, _snap: bool = false) -> void:
	rs = state_rs
	if rs.has("pos"):
		global_position = rs["pos"]
	rotation.y = float(rs.get("yaw", rotation.y))


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
		fw.rotation.y = FollowCamera.damp(fw.rotation.y, -steer * 0.45, 0.06, delta)
	var spin: Node3D = steering.get_meta("spin")
	# steer > 0 turns right (sim: yaw -= steer...): clockwise as the driver sees it
	spin.basis = Basis(Quaternion(Vector3.UP, WHEEL_AXIS.normalized())) * Basis(Vector3.UP, deg_to_rad(-steer * STEER_DEG))
	var acc := (speed - prev_speed) / maxf(delta, 0.001)
	prev_speed = speed
	roll = FollowCamera.damp(roll, steer * clampf(absf(speed) / 11.0, 0.0, 1.0) * 0.08, 0.15, delta)
	pitch = FollowCamera.damp(pitch, clampf(-acc * 0.005, -0.05, 0.05), 0.2, delta)
	chassis.rotation = Vector3(pitch, 0, roll)
	var occupied: bool = rs.get("occupied", false)
	var slowed: bool = rs.get("slowed", false)
	beacon_light.visible = occupied
	beacon_light.light_energy = 0.7 + 0.5 * absf(sin(t * 6.0))
	beacon.rotation.y = t * 8.0
	head_beam.visible = occupied
	if engine:
		if occupied and not engine.playing:
			engine.play()
		elif not occupied and engine.playing:
			engine.stop()
		engine.pitch_scale = 0.7 + clampf(absf(speed) / 11.0, 0.0, 1.0) * 0.9
		engine.volume_db = linear_to_db(maxf(Sfx.sfx_volume, 0.001)) - 14.0 + clampf(absf(speed) / 11.0, 0.0, 1.0) * 6.0
	chassis.position.y = (0.012 * sin(t * 26.0) if occupied and absf(speed) > 1.0 else 0.0) + (0.04 * sin(t * 20.0) if slowed else 0.0)
