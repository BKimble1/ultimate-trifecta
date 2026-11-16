class_name RiftView
extends Node3D
## (2.2 build 16) A rift portal on the campus (MatchSim.rifts): a standing
## swirl of light (rift.gdshader) over a glowing ring on the ground, with
## sparks orbiting it and a soft light.  It grows open from a slit, and
## collapses with a flash when someone goes through.  Reduced Motion: no
## orbiting sparks, a slower swirl.

const SHADER := preload("res://assets/shaders/rift.gdshader")
const H := 2.7

var _mat: ShaderMaterial
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _sparks: Array = []
var _open := 0.0
var _want := 1.0
var _t := 0.0
var reduced := false
var _flash := 0.0


func _ready() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(2.0, H)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.position = Vector3(0, H * 0.5 + 0.05, 0)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("speed", 0.5 if reduced else 1.0)
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-1.5, -1.5, -1.5), Vector3(3, 3 + H, 3))
	add_child(mi)
	# the ring on the ground
	var disc := CylinderMesh.new()
	disc.top_radius = 1.25
	disc.bottom_radius = 1.25
	disc.height = 0.02
	disc.radial_segments = 40
	_ring = MeshInstance3D.new()
	_ring.mesh = disc
	_ring.position = Vector3(0, 0.03, 0)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ring_mat.albedo_color = Color(0.55, 0.4, 1.0, 0.5)
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	# sparks
	if not reduced:
		var sm := SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.12
		sm.radial_segments = 8
		sm.rings = 4
		var spm := StandardMaterial3D.new()
		spm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		spm.albedo_color = Color(0.85, 0.9, 1.0)
		spm.emission_enabled = true
		spm.emission = Color(0.7, 0.8, 1.0)
		for i in 8:
			var s := MeshInstance3D.new()
			s.mesh = sm
			s.material_override = spm
			s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(s)
			_sparks.append(s)
	scale = Vector3.ONE * 0.01


## Open (true) or close (false), animated.
func set_open(on: bool) -> void:
	var want := 1.0 if on else 0.0
	if want < _want and _open > 0.5:
		_flash = 1.0
	_want = want


func is_shown() -> bool:
	return _open > 0.02 or _want > 0.0


func _process(delta: float) -> void:
	_t += delta
	_open = move_toward(_open, _want, delta * (1.6 if _want > _open else 3.5))
	var e := _open * _open * (3.0 - 2.0 * _open)
	var pop := 1.0 + 0.08 * sin(clampf(_open, 0.0, 1.0) * PI) if _want > 0.0 else 1.0
	scale = Vector3.ONE * maxf(0.01, e * pop + _flash * 0.4)
	visible = _open > 0.01 or _flash > 0.0
	_flash = maxf(0.0, _flash - delta * 3.0)
	_mat.set_shader_parameter("open", clampf(e + _flash, 0.0, 1.0))
	var pulse := 0.4 + 0.2 * sin(_t * 3.0)
	_ring_mat.albedo_color = Color(0.55, 0.4, 1.0, pulse * e + _flash)
	for i in _sparks.size():
		var s: MeshInstance3D = _sparks[i]
		var a := _t * (1.2 + 0.15 * float(i)) + float(i) * TAU / float(_sparks.size())
		var rr := 1.05 + 0.15 * sin(_t * 2.0 + float(i))
		s.position = Vector3(cos(a) * rr, 0.4 + fmod(_t * 0.6 + float(i) * 0.37, 1.0) * H, sin(a) * rr)
