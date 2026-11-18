class_name Snowfall
extends Node3D
## (2.2 build 20) Season 1 snow: soft round flakes drifting down.
##
##  * Snowfall.window(wx, reduced): the snow past the dorm window behind the
##    menus and the party lobby (HolidayDecor).
##  * Snowfall.new() in a round (MatchController): a box of falling snow that
##    follows the camera, so it is always snowing where you look, with the
##    flakes left behind in the world (local_coords off) as the camera moves.
##    It stops while the camera is inside the home dorm, so it never snows
##    indoors.
## View only: nothing in the simulation knows about it.  Reduced Motion keeps
## it, slower and thinner; Battery Saver halves it.

static var _tex: ImageTexture

var _p: CPUParticles3D
var _indoors := false


## A soft white disc (made once).
static func flake_texture() -> ImageTexture:
	if _tex != null:
		return _tex
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_tex = ImageTexture.create_from_image(img)
	return _tex


static func _material(alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = flake_texture()
	mat.albedo_color = Color(0.93, 0.96, 1.0, alpha)
	mat.disable_receive_shadows = true
	return mat


static func _emitter(amount: int, lifetime: float, extents: Vector3, size: float, speed: float, alpha: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = maxi(8, amount)
	p.lifetime = lifetime
	p.preprocess = lifetime
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.direction = Vector3(0.18, -1.0, 0.05)
	p.spread = 14.0
	p.gravity = Vector3(0.0, -0.25, 0.0)
	p.initial_velocity_min = speed * 0.7
	p.initial_velocity_max = speed * 1.15
	# a slow sideways sway: a little tangential drift around the box's axis
	p.tangential_accel_min = -0.12
	p.tangential_accel_max = 0.12
	p.scale_amount_min = 0.55
	p.scale_amount_max = 1.25
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = _material(alpha)
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# flakes fade in and out, so ones born mid-air never pop
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.12, Color(1, 1, 1, 1))
	g.add_point(0.85, Color(1, 1, 1, 1))
	p.color_ramp = g
	mat_vertex_color(q.material as StandardMaterial3D)
	return p


static func mat_vertex_color(m: StandardMaterial3D) -> void:
	m.vertex_color_use_as_albedo = true


## The snow past the dorm window (seen through the opening behind the glass).
static func window(wx: float, reduced: bool) -> CPUParticles3D:
	var p := _emitter(170 if reduced else 280, 7.5, Vector3(4.2, 0.3, 3.0), 0.085, 0.38 if reduced else 0.55, 0.92)
	p.name = "Snowfall"
	p.position = Vector3(wx, 4.3, -7.4)
	return p


## A round's snow (quality: QualityPreset.STANDARD / BATTERY).
func setup(quality: int, reduced: bool) -> void:
	name = "Snow"
	var n := 1100 if quality == QualityPreset.STANDARD else 520
	if reduced:
		n = int(n * 0.6)
	_p = _emitter(n, 6.0, Vector3(14.0, 5.0, 14.0), 0.13, 0.9 if reduced else 1.25, 0.95)
	_p.local_coords = false
	# no warm-up simulation while the round is being prepared (1100 flakes
	# simulated for 6 s held a loading frame for a quarter of a second): the
	# flakes are born all through the box and fade in, so the snow fills in
	# over the reveal and countdown
	_p.preprocess = 0.0
	_p.position = Vector3(0, 3.5, 0)
	add_child(_p)


## Keep the snow over the camera; none while the camera is indoors.
func follow(cam: Vector3, indoors: bool) -> void:
	global_position = Vector3(cam.x, cam.y, cam.z)
	if indoors != _indoors:
		_indoors = indoors
		_p.visible = not indoors
		_p.emitting = not indoors
