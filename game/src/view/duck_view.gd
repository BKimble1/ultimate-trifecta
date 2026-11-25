class_name DuckView
extends Node3D
## (build 35) A thrown Squeaky Duck on the campus (MatchSim.decoys; guests:
## the snapshot's effects list).  Until build 34 nothing drew it at all, so
## the duck looked like it did nothing.  Now: a big yellow rubber duck that
## arcs from the thrower, lands with a pop, waddles and squeaks (positional,
## every SQUEAK_EVERY s), a pulsing ring on the ground showing how far its
## daze reaches, and a "SQUEAK!" sign above it that shows through walls so
## a Night Watch knows where the noise is.  Reduced Motion: no waddle.

const SQUEAK_EVERY := 0.85

var reduced := false
var daze_r := 8.0
var _duck: Node3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _label: Label3D
var _t := 0.0
var _squeak_t := 0.0
var _land_pop := 0.0
var _flying := false
var live := false


func _ready() -> void:
	PropKit.init_meshes()
	_duck = Node3D.new()
	add_child(_duck)
	var yellow := StandardMaterial3D.new()
	yellow.albedo_color = Color(1.0, 0.84, 0.18)
	yellow.emission_enabled = true
	yellow.emission = Color(0.55, 0.4, 0.0)
	yellow.roughness = 0.35
	var orange := StandardMaterial3D.new()
	orange.albedo_color = Color(1.0, 0.5, 0.12)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.08, 0.1)
	var sp := SphereMesh.new()
	sp.radius = 0.5
	sp.height = 1.0
	sp.radial_segments = 16
	sp.rings = 10
	_part(sp, yellow, Vector3(0, 0.3, 0), Vector3(0.75, 0.52, 0.6))        # body
	_part(sp, yellow, Vector3(0, 0.72, -0.2), Vector3(0.42, 0.42, 0.42))   # head
	_part(sp, yellow, Vector3(0, 0.42, 0.3), Vector3(0.24, 0.3, 0.2))      # tail
	_part(sp, orange, Vector3(0, 0.68, -0.48), Vector3(0.22, 0.09, 0.2))   # bill
	for sx in [-1.0, 1.0]:
		_part(sp, dark, Vector3(0.12 * sx, 0.8, -0.36), Vector3(0.06, 0.07, 0.05))
	# the reach of its squeak: a ring on the ground
	var disc := TorusMesh.new()
	disc.inner_radius = 0.95
	disc.outer_radius = 1.0
	disc.rings = 64
	disc.ring_segments = 6
	_ring = MeshInstance3D.new()
	_ring.mesh = disc
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ring_mat.albedo_color = Color(1.0, 0.85, 0.25, 0.3)
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position = Vector3(0, 0.04, 0)
	add_child(_ring)
	# the sign: readable from across the campus and through walls
	_label = Label3D.new()
	_label.text = "SQUEAK!"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0016
	_label.font_size = 40
	_label.outline_size = 12
	_label.modulate = Color(1.0, 0.9, 0.3)
	_label.outline_modulate = Color(0.35, 0.2, 0.0)
	_label.position = Vector3(0, 2.0, 0)
	_label.render_priority = 10
	add_child(_label)
	visible = false


func _part(mesh: Mesh, mat: Material, pos: Vector3, scl: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	_duck.add_child(mi)


## Where the duck is this frame: in the air (`flying`, no squeak, no ring
## yet) or on the ground.  `heading` turns it the way it waddles.
func show_at(pos: Vector3, flying: bool, heading: Vector3 = Vector3.ZERO) -> void:
	if not live:
		_t = 0.0
		_squeak_t = 0.25
	live = true
	visible = true
	if _flying and not flying:
		_land_pop = 1.0
		_squeak_t = 0.0
	_flying = flying
	position = pos
	if heading.length() > 0.1:
		_duck.rotation.y = atan2(heading.x, heading.z)


func hide_duck() -> void:
	live = false
	visible = false
	_flying = false


func _process(delta: float) -> void:
	if not live:
		return
	_t += delta
	_land_pop = maxf(0.0, _land_pop - delta * 2.5)
	var s := 1.0 + _land_pop * 0.45
	_duck.scale = Vector3(s, s * (1.0 - _land_pop * 0.25), s)
	if not reduced and not _flying:
		_duck.rotation.z = sin(_t * 9.0) * 0.18
		_duck.position.y = absf(sin(_t * 9.0)) * 0.12
	_ring.visible = not _flying
	var grow := clampf(_t * 3.0, 0.0, 1.0) if not _flying else 0.0
	var pulse := 0.85 + 0.15 * sin(_t * 6.0)
	_ring.scale = Vector3(daze_r * grow * pulse, 0.05, daze_r * grow * pulse)
	_ring_mat.albedo_color = Color(1.0, 0.85, 0.25, 0.55 + 0.4 * _land_pop)
	_label.visible = not _flying
	_label.scale = Vector3.ONE * (1.0 + 0.25 * absf(sin(_t * 6.0)) + _land_pop)
	if not _flying:
		_squeak_t -= delta
		if _squeak_t <= 0.0:
			_squeak_t = SQUEAK_EVERY
			Sfx.play("squeak", global_position, 1.0, randf_range(0.9, 1.25))
