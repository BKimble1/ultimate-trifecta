class_name CharacterView
extends Node3D
## Procedural chunky character with a blended, state-driven pose.
## Presentation only: it follows authoritative/interpolated state and never
## moves gameplay. Squash, tumbles and limb flail are overlays on a stable
## gameplay capsule.

const SHADER := preload("res://assets/shaders/character.gdshader")

static var _mat_cache: Dictionary = {}
static var _sphere: SphereMesh
static var _capsule: CapsuleMesh
static var _cyl: CylinderMesh
static var _box: BoxMesh
static var _cone: CylinderMesh

var role: int = TC.Role.RUNNER
var cosmetic: Dictionary = Cosmetics.DEFAULT
var slot: int = -1
var is_local := false

var body: Node3D
var torso: MeshInstance3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var eyes: Array[Node3D] = []
var pupils: Array[Node3D] = []
var brows: Array[Node3D] = []
var mouth: MeshInstance3D
var hat_tip: Node3D
var flashlight: SpotLight3D
var beam: MeshInstance3D
var name_label: Label3D
var dizzy: Node3D
var bubble: MeshInstance3D
var _meshes: Array[GeometryInstance3D] = []

# animation state
var phase: float = 0.0
var pose := {}
var blink_t := 2.0
var squash: float = 0.0
var head_spring := Vector2.ZERO
var head_vel := Vector2.ZERO
var tip_spring := Vector2.ZERO
var tip_vel := Vector2.ZERO
var prev_vel := Vector3.ZERO
var prev_air := false
var vis_yaw: float = 0.0
var celebrate_t: float = 0.0
var t_accum: float = 0.0
var hidden_for_state := false
var reduced_motion := false
var rs: Dictionary = {}


static func _init_meshes() -> void:
	if _sphere != null:
		return
	_sphere = SphereMesh.new()
	_sphere.radius = 0.5
	_sphere.height = 1.0
	_sphere.radial_segments = 18
	_sphere.rings = 10
	_capsule = CapsuleMesh.new()
	_capsule.radius = 0.5
	_capsule.height = 2.0
	_capsule.radial_segments = 16
	_capsule.rings = 6
	_cyl = CylinderMesh.new()
	_cyl.top_radius = 0.5
	_cyl.bottom_radius = 0.5
	_cyl.height = 1.0
	_cyl.radial_segments = 12
	_box = BoxMesh.new()
	_cone = CylinderMesh.new()
	_cone.top_radius = 0.0
	_cone.bottom_radius = 0.5
	_cone.height = 1.0
	_cone.radial_segments = 12


static func mat(col: Color, stripes: float = 0.0, stripe_col: Color = Color.WHITE, emission: float = 0.0, rim: float = 0.45) -> ShaderMaterial:
	var key := "%s|%.1f|%s|%.2f|%.2f" % [col.to_html(), stripes, stripe_col.to_html(), emission, rim]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("albedo", col)
	m.set_shader_parameter("stripes", stripes)
	m.set_shader_parameter("stripe_color", stripe_col)
	m.set_shader_parameter("emission", emission)
	m.set_shader_parameter("rim_strength", rim)
	_mat_cache[key] = m
	return m


func setup(p_role: int, p_cosmetic: Dictionary, p_slot: int, display_name: String, is_bot: bool, local: bool = false) -> void:
	_init_meshes()
	role = p_role
	cosmetic = Cosmetics.sanitize(p_cosmetic)
	slot = p_slot
	is_local = local
	for c in get_children():
		c.queue_free()
	_meshes.clear()
	eyes.clear()
	pupils.clear()
	brows.clear()
	_build()
	_build_label(display_name, is_bot)


func _part(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3, scl: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.scale = scl
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	_meshes.append(mi)
	return mi


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _build() -> void:
	var skin: Color = Cosmetics.SKINS[int(cosmetic["skin"])]
	var prim: Color = Cosmetics.COLORS[int(cosmetic["color"])]
	var outfit: String = cosmetic["outfit"]
	var kind: String = Cosmetics.OUTFITS[outfit]["kind"]
	var patrol := role == TC.Role.PATROL
	var torso_m: Material
	var leg_m: Material
	var arm_m: Material
	var hand_m := mat(skin)
	var skin_m := mat(skin)
	if patrol:
		var navy := Color(0.16, 0.22, 0.44)
		torso_m = mat(navy, 3.0, Color(1.0, 0.85, 0.15), 0.0)
		leg_m = mat(navy.darkened(0.2))
		arm_m = mat(navy)
	else:
		match kind:
			"pj":
				var stripes: float = float(Cosmetics.OUTFITS[outfit].get("stripes", 0.0))
				torso_m = mat(prim, stripes, prim.lightened(0.55))
				leg_m = mat(prim, stripes * 0.6, prim.lightened(0.55))
				arm_m = mat(prim)
			"swim":
				torso_m = skin_m
				leg_m = skin_m
				arm_m = skin_m
			"robe":
				torso_m = mat(prim.lightened(0.35))
				leg_m = skin_m
				arm_m = mat(prim.lightened(0.35))
			"duck":
				torso_m = mat(Color(1.0, 0.86, 0.22))
				leg_m = mat(Color(1.0, 0.86, 0.22))
				arm_m = mat(Color(1.0, 0.86, 0.22))
			"frog":
				torso_m = mat(Color(0.38, 0.78, 0.36), 0.0)
				leg_m = mat(Color(0.38, 0.78, 0.36))
				arm_m = mat(Color(0.38, 0.78, 0.36))
			_:
				torso_m = mat(prim)
				leg_m = mat(prim)
				arm_m = mat(prim)

	body = _pivot(self, Vector3(0, 0.42, 0))
	torso = _part(body, _capsule, torso_m, Vector3(0, 0.33, 0), Vector3(0.68, 0.40, 0.62))
	if not patrol and kind == "swim":
		_part(body, _cyl, mat(prim), Vector3(0, 0.08, 0), Vector3(0.70, 0.22, 0.64))
	if not patrol and kind == "robe":
		_part(body, _cyl, mat(prim.darkened(0.2)), Vector3(0, 0.22, 0), Vector3(0.72, 0.06, 0.66))
		_part(body, _sphere, mat(prim.lightened(0.5)), Vector3(0, 0.66, -0.05), Vector3(0.62, 0.18, 0.56))
	if not patrol and kind == "frog":
		_part(body, _sphere, mat(Color(0.85, 0.95, 0.7)), Vector3(0, 0.3, -0.2), Vector3(0.42, 0.5, 0.25))
	if patrol:
		# hi-vis belt + badge
		_part(body, _cyl, mat(Color(0.12, 0.12, 0.15)), Vector3(0, 0.10, 0), Vector3(0.70, 0.08, 0.64))
		_part(body, _sphere, mat(Color(1.0, 0.82, 0.25), 0.0, Color.WHITE, 0.4), Vector3(-0.14, 0.52, -0.3), Vector3(0.1, 0.12, 0.05))

	# head
	head = _pivot(body, Vector3(0, 0.80, 0))
	_part(head, _sphere, skin_m, Vector3(0, 0.08, 0), Vector3(0.74, 0.70, 0.70))
	var white := mat(Color(1, 1, 1), 0.0, Color.WHITE, 0.08, 0.2)
	var black := mat(Color(0.06, 0.06, 0.1), 0.0, Color.WHITE, 0.0, 0.0)
	for sx in [-1.0, 1.0]:
		var e := _part(head, _sphere, white, Vector3(0.13 * sx, 0.13, -0.27), Vector3(0.2, 0.24, 0.12))
		eyes.append(e)
		var pu := _part(head, _sphere, black, Vector3(0.13 * sx, 0.12, -0.33), Vector3(0.1, 0.12, 0.05))
		pupils.append(pu)
		var br := _part(head, _box, mat(Color(0.25, 0.16, 0.12)), Vector3(0.13 * sx, 0.29, -0.3), Vector3(0.14, 0.035, 0.04))
		brows.append(br)
		_part(head, _sphere, mat(Color(1.0, 0.55, 0.6)), Vector3(0.22 * sx, -0.02, -0.25), Vector3(0.09, 0.06, 0.04))
	mouth = _part(head, _sphere, mat(Color(0.35, 0.08, 0.12)), Vector3(0, -0.07, -0.32), Vector3(0.14, 0.06, 0.05))
	if patrol and int(cosmetic["color"]) % 2 == 0:
		_part(head, _sphere, mat(Color(0.3, 0.2, 0.15)), Vector3(0, -0.01, -0.33), Vector3(0.24, 0.07, 0.07))  # mustache
	_build_hat(patrol, prim, kind)

	# arms (pivot at shoulders)
	arm_l = _pivot(body, Vector3(-0.33, 0.56, 0))
	arm_r = _pivot(body, Vector3(0.33, 0.56, 0))
	for arm in [arm_l, arm_r]:
		_part(arm, _capsule, arm_m, Vector3(0, -0.2, 0), Vector3(0.18, 0.15, 0.18))
		_part(arm, _sphere, hand_m if kind != "duck" or patrol else mat(Color(1.0, 0.6, 0.15)), Vector3(0, -0.42, 0), Vector3(0.18, 0.18, 0.18))
	if patrol:
		var fl := _pivot(arm_r, Vector3(0, -0.45, -0.08))
		_part(fl, _cyl, mat(Color(0.2, 0.2, 0.24)), Vector3(0, 0, -0.08), Vector3(0.08, 0.26, 0.08), Vector3(PI * 0.5, 0, 0))
		_part(fl, _cyl, mat(Color(1.0, 0.95, 0.75), 0.0, Color.WHITE, 2.5), Vector3(0, 0, -0.22), Vector3(0.1, 0.02, 0.1), Vector3(PI * 0.5, 0, 0))
		flashlight = SpotLight3D.new()
		flashlight.light_color = Color(1.0, 0.95, 0.8)
		flashlight.light_energy = 3.0
		flashlight.spot_range = 22.0
		flashlight.spot_angle = 22.0
		flashlight.spot_attenuation = 0.8
		flashlight.shadow_enabled = false
		flashlight.position = Vector3(0, 0, -0.25)
		fl.add_child(flashlight)
		beam = MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.06
		bm.bottom_radius = 3.0
		bm.height = 12.0
		bm.radial_segments = 14
		bm.cap_top = false
		bm.cap_bottom = false
		beam.mesh = bm
		var gm := ShaderMaterial.new()
		gm.shader = preload("res://assets/shaders/glow_add.gdshader")
		gm.set_shader_parameter("color", Color(1.0, 0.92, 0.7))
		gm.set_shader_parameter("intensity", 0.18)
		gm.set_shader_parameter("mode", 2.0)
		beam.material_override = gm
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.position = Vector3(0, 0, -6.2)
		beam.rotation = Vector3(-PI * 0.5, 0, 0)
		fl.add_child(beam)
		# whistle on a lanyard
		_part(body, _cyl, mat(Color(0.85, 0.85, 0.9), 0.0, Color.WHITE, 0.2), Vector3(0.1, 0.45, -0.32), Vector3(0.06, 0.12, 0.06), Vector3(PI * 0.5, 0, 0))

	# legs (pivot at hips)
	leg_l = _pivot(body, Vector3(-0.15, 0.02, 0))
	leg_r = _pivot(body, Vector3(0.15, 0.02, 0))
	var shoes: String = cosmetic["shoes"]
	for leg in [leg_l, leg_r]:
		_part(leg, _capsule, leg_m, Vector3(0, -0.17, 0), Vector3(0.2, 0.14, 0.2))
		if patrol:
			_part(leg, _sphere, mat(Color(0.1, 0.1, 0.12)), Vector3(0, -0.36, -0.05), Vector3(0.24, 0.16, 0.34))
		else:
			match shoes:
				"slippers":
					_part(leg, _sphere, mat(Color(1.0, 0.86, 0.92)), Vector3(0, -0.36, -0.06), Vector3(0.26, 0.17, 0.36))
					for ex in [-0.05, 0.05]:
						_part(leg, _sphere, mat(Color(1.0, 0.86, 0.92)), Vector3(ex, -0.24, -0.16), Vector3(0.05, 0.16, 0.04), Vector3(-0.4, 0, 0))
				"sneakers":
					_part(leg, _sphere, mat(prim.darkened(0.3)), Vector3(0, -0.35, -0.05), Vector3(0.25, 0.18, 0.36))
					_part(leg, _cyl, mat(Color(0.95, 0.95, 0.95)), Vector3(0, -0.42, -0.05), Vector3(0.26, 0.04, 0.37))
				"flippers":
					_part(leg, _sphere, mat(Color(0.2, 0.7, 0.9)), Vector3(0, -0.4, -0.18), Vector3(0.3, 0.07, 0.6))

	# dizzy stars (capture) and protection bubble
	dizzy = _pivot(self, Vector3(0, 1.85, 0))
	for i in 3:
		var a := TAU * float(i) / 3.0
		_part(dizzy, _sphere, mat(Color(1.0, 0.9, 0.3), 0.0, Color.WHITE, 1.5), Vector3(cos(a) * 0.35, 0, sin(a) * 0.35), Vector3(0.1, 0.1, 0.1))
	dizzy.visible = false
	bubble = MeshInstance3D.new()
	bubble.mesh = _sphere
	var bmat := StandardMaterial3D.new()
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.albedo_color = Color(0.6, 0.9, 1.0, 0.18)
	bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bubble.material_override = bmat
	bubble.scale = Vector3(1.5, 2.0, 1.5)
	bubble.position = Vector3(0, 0.9, 0)
	bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bubble.visible = false
	add_child(bubble)


func _build_hat(patrol: bool, prim: Color, kind: String) -> void:
	if patrol:
		var navy := Color(0.14, 0.2, 0.4)
		_part(head, _cyl, mat(navy), Vector3(0, 0.36, 0), Vector3(0.62, 0.16, 0.62))
		_part(head, _cyl, mat(navy.darkened(0.3)), Vector3(0, 0.3, -0.18), Vector3(0.5, 0.03, 0.42))
		_part(head, _sphere, mat(Color(1.0, 0.82, 0.25), 0.0, Color.WHITE, 0.5), Vector3(0, 0.38, -0.31), Vector3(0.1, 0.1, 0.04))
		return
	if kind == "duck":
		_part(head, _sphere, mat(Color(1.0, 0.86, 0.22)), Vector3(0, 0.2, 0.02), Vector3(0.8, 0.62, 0.78))
		_part(head, _sphere, mat(Color(1.0, 0.55, 0.12)), Vector3(0, 0.36, -0.35), Vector3(0.3, 0.09, 0.22))
		for sx in [-1.0, 1.0]:
			_part(head, _sphere, mat(Color.WHITE), Vector3(0.12 * sx, 0.5, -0.24), Vector3(0.12, 0.12, 0.08))
			_part(head, _sphere, mat(Color(0.05, 0.05, 0.08)), Vector3(0.12 * sx, 0.5, -0.28), Vector3(0.06, 0.06, 0.04))
		return
	if kind == "frog":
		for sx in [-1.0, 1.0]:
			_part(head, _sphere, mat(Color(0.38, 0.78, 0.36)), Vector3(0.17 * sx, 0.44, -0.05), Vector3(0.22, 0.2, 0.22))
			_part(head, _sphere, mat(Color.WHITE), Vector3(0.17 * sx, 0.47, -0.13), Vector3(0.13, 0.13, 0.08))
			_part(head, _sphere, mat(Color(0.05, 0.05, 0.08)), Vector3(0.17 * sx, 0.47, -0.17), Vector3(0.06, 0.07, 0.04))
	match String(cosmetic["hat"]):
		"nightcap":
			_part(head, _cyl, mat(prim.lightened(0.5)), Vector3(0, 0.33, 0), Vector3(0.66, 0.08, 0.66))
			var cap := _pivot(head, Vector3(0, 0.36, 0.0))
			_part(cap, _cone, mat(prim), Vector3(0, 0.18, 0.04), Vector3(0.6, 0.38, 0.6), Vector3(0.3, 0, 0))
			hat_tip = _pivot(cap, Vector3(0, 0.34, 0.14))
			_part(hat_tip, _cone, mat(prim), Vector3(0, 0.0, 0.12), Vector3(0.22, 0.3, 0.22), Vector3(1.3, 0, 0))
			_part(hat_tip, _sphere, mat(Color(1, 1, 1)), Vector3(0, -0.06, 0.28), Vector3(0.16, 0.16, 0.16))
		"swimcap":
			_part(head, _sphere, mat(prim), Vector3(0, 0.2, 0.02), Vector3(0.78, 0.55, 0.74))
			_part(head, _cyl, mat(Color(0.15, 0.15, 0.2)), Vector3(0, 0.16, 0), Vector3(0.76, 0.04, 0.72))
			for sx in [-1.0, 1.0]:
				_part(head, _cyl, mat(Color(0.5, 0.85, 1.0), 0.0, Color.WHITE, 0.3), Vector3(0.13 * sx, 0.16, -0.33), Vector3(0.2, 0.05, 0.2), Vector3(PI * 0.5, 0, 0))
		"party":
			_part(head, _cone, mat(prim, 4.0, Color(1, 0.9, 0.3)), Vector3(0.08, 0.55, 0), Vector3(0.32, 0.42, 0.32), Vector3(0, 0, -0.2))
			hat_tip = _pivot(head, Vector3(0.16, 0.78, 0))
			_part(hat_tip, _sphere, mat(Color(1, 0.9, 0.3), 0.0, Color.WHITE, 0.4), Vector3.ZERO, Vector3(0.1, 0.1, 0.1))
		"headphones":
			_part(head, _cyl, mat(Color(0.2, 0.2, 0.25)), Vector3(0, 0.42, 0), Vector3(0.7, 0.05, 0.12), Vector3(0, 0, PI * 0.5))
			for sx in [-1.0, 1.0]:
				_part(head, _sphere, mat(prim), Vector3(0.36 * sx, 0.1, 0), Vector3(0.14, 0.24, 0.24))
		"crown":
			_part(head, _cyl, mat(Color(1.0, 0.82, 0.25), 0.0, Color.WHITE, 0.3), Vector3(0, 0.42, 0), Vector3(0.48, 0.14, 0.48))
			for i in 5:
				var a := TAU * float(i) / 5.0
				_part(head, _cone, mat(Color(1.0, 0.82, 0.25), 0.0, Color.WHITE, 0.3), Vector3(cos(a) * 0.2, 0.55, sin(a) * 0.2), Vector3(0.1, 0.14, 0.1))


func _build_label(display_name: String, is_bot: bool) -> void:
	name_label = Label3D.new()
	name_label.text = (display_name + "  [BOT]") if is_bot else display_name
	name_label.font_size = 30
	name_label.outline_size = 8
	name_label.pixel_size = 0.0011
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.no_depth_test = false
	name_label.fixed_size = true
	name_label.position = Vector3(0, 2.1, 0)
	name_label.modulate = Color(1.0, 0.65, 0.35) if role == TC.Role.PATROL else Color(0.6, 0.95, 1.0)
	name_label.outline_modulate = Color(0.05, 0.05, 0.12)
	if is_local:
		name_label.visible = false
	add_child(name_label)


func set_flash(v: float, col: Color = Color.WHITE) -> void:
	for m in _meshes:
		if is_instance_valid(m):
			m.set_instance_shader_parameter("flash", v)
			m.set_instance_shader_parameter("flash_color", col)


## rs keys: pos, yaw, vel, state, on_floor, diving, sprinting, tag_phase,
## protect, in_cart, steer, emote, emote_t, spotted, celebrate
func apply_state(state_rs: Dictionary, delta: float, snap: bool = false) -> void:
	rs = state_rs
	var target_pos: Vector3 = rs.get("pos", global_position)
	if snap or global_position.distance_to(target_pos) > 6.0:
		global_position = target_pos
	else:
		global_position = global_position.lerp(target_pos, clampf(delta * 30.0, 0.0, 1.0))
	var yaw: float = rs.get("yaw", 0.0)
	vis_yaw = lerp_angle(vis_yaw, yaw, clampf(delta * 16.0, 0.0, 1.0)) if not snap else yaw
	rotation.y = vis_yaw


func _process(delta: float) -> void:
	if body == null or rs.is_empty():
		return
	t_accum += delta
	var st: int = rs.get("state", TC.PState.ACTIVE)
	var vel: Vector3 = rs.get("vel", Vector3.ZERO)
	var speed := Vector2(vel.x, vel.z).length()
	var on_floor: bool = rs.get("on_floor", true)
	var diving: bool = rs.get("diving", false)
	var sprinting: bool = rs.get("sprinting", false)
	var tag_phase: int = rs.get("tag_phase", 0)
	var in_cart: bool = st == TC.PState.IN_CART or st == TC.PState.ENTERING
	var captured := st == TC.PState.CAPTURED
	var splashing := st == TC.PState.SPLASHING
	var finished := st == TC.PState.FINISHED
	var stumble := st == TC.PState.STUMBLE
	var emote: int = rs.get("emote", -1)
	var emote_t: float = rs.get("emote_t", 0.0)

	visible = not finished or bool(rs.get("show_finished", false))
	dizzy.visible = captured and float(rs.get("state_t", 0.0)) < 4.5
	if dizzy.visible:
		dizzy.rotation.y += delta * 6.0
	bubble.visible = float(rs.get("protect", 0.0)) > 0.0 and not captured
	if bubble.visible:
		var pulse := 0.12 + 0.08 * sin(t_accum * 12.0)
		(bubble.material_override as StandardMaterial3D).albedo_color.a = pulse
	if flashlight:
		flashlight.visible = not in_cart
		beam.visible = not in_cart

	# --- target pose
	var tp := {
		"bob": 0.0, "lean": 0.0, "roll": 0.0, "body_y": 0.42,
		"arm_l": Vector3(0, 0, -0.15), "arm_r": Vector3(0, 0, 0.15),
		"leg_l": Vector3.ZERO, "leg_r": Vector3.ZERO, "head": Vector3.ZERO,
		"scale": Vector3.ONE, "spin": 0.0,
	}
	var gait := clampf(speed / 7.0, 0.0, 1.2)
	if on_floor and speed > 0.3 and not diving and not in_cart:
		phase += delta * (5.0 + speed * 1.55)
	var s := sin(phase)
	var c := cos(phase)
	if in_cart:
		var steer: float = rs.get("steer", 0.0)
		tp["body_y"] = 0.62
		tp["leg_l"] = Vector3(-1.45, 0, 0)
		tp["leg_r"] = Vector3(-1.45, 0, 0)
		tp["arm_l"] = Vector3(1.1, 0, -0.25 + steer * 0.3)
		tp["arm_r"] = Vector3(1.1, 0, 0.25 + steer * 0.3)
		tp["lean"] = -0.08
		tp["roll"] = -steer * 0.12
		tp["head"] = Vector3(0, -steer * 0.25, 0)
	elif captured:
		var ct: float = rs.get("state_t", 0.0)
		tp["body_y"] = 0.2
		tp["leg_l"] = Vector3(-1.4, 0, -0.4)
		tp["leg_r"] = Vector3(-1.4, 0, 0.4)
		tp["arm_l"] = Vector3(0.3 + sin(ct * 5.0) * 0.3, 0, -0.9)
		tp["arm_r"] = Vector3(0.3 - sin(ct * 5.0) * 0.3, 0, 0.9)
		tp["roll"] = sin(ct * 4.0) * 0.15
		tp["head"] = Vector3(sin(ct * 3.0) * 0.2, sin(ct * 4.0) * 0.3, 0)
	elif splashing:
		var spt: float = rs.get("state_t", 0.0)
		tp["body_y"] = 0.42 - 1.2 * clampf(1.0 - absf(spt - 0.6) / 0.6, 0.0, 1.0)
		tp["arm_l"] = Vector3(0, 0, -2.6)
		tp["arm_r"] = Vector3(0, 0, 2.6)
		tp["spin"] = spt * 4.0
	elif diving:
		tp["lean"] = -1.35
		tp["body_y"] = 0.75
		tp["arm_l"] = Vector3(3.0, 0, -0.2)
		tp["arm_r"] = Vector3(3.0, 0, 0.2)
		tp["leg_l"] = Vector3(-0.35, 0, -0.1)
		tp["leg_r"] = Vector3(-0.25, 0, 0.1)
		tp["head"] = Vector3(0.9, 0, 0)
	elif stumble:
		var stt: float = rs.get("state_t", 0.0)
		tp["roll"] = sin(stt * 22.0) * 0.45 * (1.0 - stt / 0.6)
		tp["lean"] = 0.35
		tp["arm_l"] = Vector3(sin(stt * 25.0) * 1.5, 0, -1.2)
		tp["arm_r"] = Vector3(-sin(stt * 25.0) * 1.5, 0, 1.2)
		tp["leg_l"] = Vector3(0.6, 0, 0)
		tp["head"] = Vector3(-0.3, sin(stt * 18.0) * 0.5, 0)
	elif not on_floor:
		var vy := vel.y
		tp["leg_l"] = Vector3(0.9, 0, -0.1)
		tp["leg_r"] = Vector3(0.2, 0, 0.1)
		tp["arm_l"] = Vector3(-0.3 + clampf(vy * 0.2, -0.8, 0.8), 0, -1.6)
		tp["arm_r"] = Vector3(-0.3 + clampf(vy * 0.2, -0.8, 0.8), 0, 1.6)
		tp["lean"] = -0.15
	else:
		var amp := 0.25 + 0.75 * clampf(gait, 0.0, 1.0)
		if sprinting:
			amp *= 1.35
		tp["leg_l"] = Vector3(s * 0.95 * amp, 0, 0)
		tp["leg_r"] = Vector3(-s * 0.95 * amp, 0, 0)
		tp["arm_l"] = Vector3(-s * 1.1 * amp, 0, -0.18 - 0.1 * gait)
		tp["arm_r"] = Vector3(s * 1.1 * amp, 0, 0.18 + 0.1 * gait)
		tp["bob"] = absf(c) * 0.09 * gait
		tp["lean"] = -0.12 * gait - (0.14 if sprinting else 0.0)
		tp["roll"] = s * 0.05 * gait
		if speed < 0.3:
			var br := sin(t_accum * 2.2)
			tp["bob"] = br * 0.012
			tp["arm_l"] = Vector3(0.05 * br, 0, -0.12)
			tp["arm_r"] = Vector3(-0.05 * br, 0, 0.12)
			tp["head"] = Vector3(0, sin(t_accum * 0.7) * 0.25, 0)
	# tag lunge overlays
	if tag_phase == 1:
		tp["lean"] = 0.3
		tp["arm_l"] = Vector3(-1.2, 0, -0.5)
		tp["arm_r"] = Vector3(-1.2, 0, 0.5)
	elif tag_phase == 2:
		tp["lean"] = -0.55
		tp["arm_l"] = Vector3(2.6, 0, -0.1)
		tp["arm_r"] = Vector3(2.6, 0, 0.1)
		tp["leg_l"] = Vector3(0.8, 0, 0)
		tp["leg_r"] = Vector3(-0.7, 0, 0)
	elif tag_phase == 3:
		tp["lean"] = -0.2
		tp["arm_l"] = Vector3(0.6, 0, -0.3)
		tp["arm_r"] = Vector3(0.6, 0, 0.3)
	# emotes / celebration
	if finished or bool(rs.get("celebrate", false)):
		celebrate_t += delta
		tp["arm_l"] = Vector3(0, 0, -2.7 + sin(celebrate_t * 10.0) * 0.3)
		tp["arm_r"] = Vector3(0, 0, 2.7 - sin(celebrate_t * 10.0) * 0.3)
		tp["bob"] = absf(sin(celebrate_t * 6.0)) * 0.35
		tp["spin"] = celebrate_t * 3.0
	elif emote >= 0 and emote_t > 0.0 and not in_cart:
		var et := t_accum
		match TC.EMOTES[emote]:
			"wave":
				tp["arm_r"] = Vector3(0, 0, 2.5 + sin(et * 14.0) * 0.4)
			"cheer":
				tp["arm_l"] = Vector3(0, 0, -2.8)
				tp["arm_r"] = Vector3(0, 0, 2.8)
				tp["bob"] = absf(sin(et * 9.0)) * 0.25
			"laugh":
				tp["lean"] = 0.25 + sin(et * 18.0) * 0.08
				tp["arm_l"] = Vector3(0.4, 0, -0.5)
				tp["arm_r"] = Vector3(0.4, 0, 0.5)
			"shrug":
				tp["arm_l"] = Vector3(0.3, 0, -1.2)
				tp["arm_r"] = Vector3(0.3, 0, 1.2)
				tp["head"] = Vector3(0, 0, 0.3)
			"dance":
				tp["roll"] = sin(et * 8.0) * 0.3
				tp["arm_l"] = Vector3(sin(et * 8.0) * 1.2, 0, -1.4)
				tp["arm_r"] = Vector3(-sin(et * 8.0) * 1.2, 0, 1.4)
				tp["bob"] = absf(sin(et * 8.0)) * 0.12
			"point":
				tp["arm_r"] = Vector3(1.6, 0, 0.2)
	else:
		celebrate_t = 0.0

	# landing squash + jump stretch
	var air := not on_floor
	if prev_air and not air:
		squash = clampf(-prev_vel.y * 0.05, 0.08, 0.32)
	if not prev_air and air and vel.y > 2.0:
		squash = -0.15
	prev_air = air
	prev_vel = vel
	squash = move_toward(squash, 0.0, delta * 1.6)
	if reduced_motion:
		squash *= 0.4
	tp["scale"] = Vector3(1.0 + squash * 0.6, 1.0 - squash, 1.0 + squash * 0.6)

	# --- blend toward target pose
	var k := clampf(delta * 14.0, 0.0, 1.0)
	if pose.is_empty():
		pose = tp.duplicate()
	for key in tp:
		var v: Variant = tp[key]
		if v is Vector3:
			pose[key] = (pose[key] as Vector3).lerp(v, k)
		else:
			pose[key] = lerpf(float(pose[key]), float(v), k)
	body.position = Vector3(0, float(pose["body_y"]) + float(pose["bob"]), 0)
	body.rotation = Vector3(float(pose["lean"]), float(pose["spin"]), float(pose["roll"]))
	body.scale = pose["scale"]
	arm_l.rotation = pose["arm_l"]
	arm_r.rotation = pose["arm_r"]
	leg_l.rotation = pose["leg_l"]
	leg_r.rotation = pose["leg_r"]

	# secondary motion: head lags body acceleration (spring), hat tip jiggles
	var accel := (vel - prev_vel) / maxf(delta, 0.001)
	var force := Vector2(-accel.z, accel.x) * 0.0015
	head_vel += (-head_spring * 90.0 - head_vel * 9.0 + force * 60.0) * delta
	head_spring += head_vel * delta
	head_spring = head_spring.limit_length(0.35)
	var hp: Vector3 = pose["head"]
	head.rotation = Vector3(hp.x + head_spring.x, hp.y, hp.z + head_spring.y)
	if hat_tip:
		tip_vel += (-tip_spring * 60.0 - tip_vel * 5.0 + Vector2(speed * 0.02 + float(pose["bob"]) * 2.0, float(pose["roll"])) * 30.0) * delta
		tip_spring += tip_vel * delta
		hat_tip.rotation = Vector3(tip_spring.x, 0, tip_spring.y)

	# face: blinking, surprised when spotted/captured, determined when sprinting
	blink_t -= delta
	var eye_y := 1.0
	if blink_t < 0.12:
		eye_y = 0.15
	if blink_t < 0.0:
		blink_t = randf_range(2.0, 4.5)
	var surprised := captured or stumble or bool(rs.get("spotted", false))
	for i in eyes.size():
		var es := 1.25 if surprised else 1.0
		eyes[i].scale = Vector3(0.2 * es, 0.24 * es * eye_y, 0.12)
		pupils[i].scale = Vector3(0.1, 0.12 * eye_y, 0.05)
	var brow_tilt := 0.35 if (sprinting or tag_phase > 0) else (-0.25 if surprised else 0.0)
	brows[0].rotation.z = -brow_tilt
	brows[1].rotation.z = brow_tilt
	brows[0].position.y = 0.29 + (0.05 if surprised else 0.0)
	brows[1].position.y = 0.29 + (0.05 if surprised else 0.0)
	mouth.scale = Vector3(0.14, 0.12 if (surprised or finished) else 0.06, 0.05)

	# protection / spotted flashes
	var flash := 0.0
	if float(rs.get("protect", 0.0)) > 0.0:
		flash = 0.25 + 0.25 * sin(t_accum * 18.0)
	if float(rs.get("bump_protect", 0.0)) > 0.0:
		flash = maxf(flash, 0.2)
	set_flash(flash, Color(0.6, 0.9, 1.0))
