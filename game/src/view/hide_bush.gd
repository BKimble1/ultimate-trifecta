class_name HideBush
extends Node3D
## (2.3) A bush a runner can hide in: a big round shrub of overlapping leafy
## clumps (larger and rounder than the campus's decorative shrubs, so it
## reads as a place to hide), a few pale blossoms, and a soft dark patch on
## the grass under it.  rustle() shakes it when someone ducks in or jumps
## out and throws a puff of leaves.

const CLUMPS := [[Vector3(0, 0.62, 0), 0.82], [Vector3(0.55, 0.5, 0.2), 0.6], [Vector3(-0.52, 0.5, 0.15), 0.62],
	[Vector3(0.15, 0.48, -0.55), 0.6], [Vector3(-0.2, 0.46, 0.55), 0.58], [Vector3(0.3, 0.98, -0.1), 0.5], [Vector3(-0.28, 0.95, 0.12), 0.48]]

var _shake := 0.0
var _body: Node3D
var _t := 0.0


static func make(p: Vector2, ground_y: float) -> HideBush:
	var b := HideBush.new()
	b.position = Vector3(p.x, ground_y, p.y)
	b.rotation.y = fmod(absf(p.x * 12.9898 + p.y * 78.233), TAU)
	b._build()
	return b


func _build() -> void:
	PropKit.init_meshes()
	_body = Node3D.new()
	add_child(_body)
	var sp := SphereMesh.new()
	sp.radius = 0.5
	sp.height = 1.0
	sp.radial_segments = 12
	sp.rings = 7
	var greens := [Color(0.16, 0.36, 0.17), Color(0.2, 0.43, 0.2), Color(0.13, 0.31, 0.15), Color(0.24, 0.47, 0.22)]
	for i in CLUMPS.size():
		var c: Array = CLUMPS[i]
		var mi := MeshInstance3D.new()
		mi.mesh = sp
		var r := float(c[1]) * 2.0
		mi.scale = Vector3(r, r * 0.86, r)
		mi.position = c[0]
		mi.material_override = PropKit.mat(greens[i % greens.size()], 0.0, Color.WHITE, 0.25)
		_body.add_child(mi)
	# a few blossoms on the crown
	var fl := SphereMesh.new()
	fl.radius = 0.07
	fl.height = 0.14
	fl.radial_segments = 6
	fl.rings = 4
	var fm := PropKit.mat(Color(1.0, 0.86, 0.92), 0.0, Color.WHITE, 0.6)
	for k in 7:
		var a := TAU * float(k) / 7.0 + 0.4
		var m := MeshInstance3D.new()
		m.mesh = fl
		m.material_override = fm
		m.position = Vector3(cos(a) * 0.62, 0.9 + 0.18 * sin(a * 3.0), sin(a) * 0.62)
		_body.add_child(m)
	# a soft shadow patch on the grass
	var patch := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 1.25
	pm.bottom_radius = 1.25
	pm.height = 0.02
	pm.radial_segments = 20
	patch.mesh = pm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.03, 0.08, 0.04, 0.55)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	patch.material_override = sm
	patch.position = Vector3(0, 0.02, 0)
	add_child(patch)
	set_process(false)


## Someone ducked in (true) or jumped out (false): a shake and leaves.
func rustle(_entering: bool) -> void:
	_shake = 1.0
	_t = 0.0
	set_process(true)
	var fx: Variant = get_parent().get("fx") if get_parent() != null else null
	if fx != null and fx.has_method("poof"):
		fx.call("poof", global_position + Vector3(0, 0.9, 0))


func _process(delta: float) -> void:
	_t += delta
	_shake = maxf(0.0, _shake - delta * 1.6)
	var w := sin(_t * 28.0) * 0.06 * _shake
	_body.rotation = Vector3(w, 0, w * 0.7)
	_body.scale = Vector3.ONE * (1.0 + 0.05 * _shake * sin(_t * 19.0))
	if _shake <= 0.0:
		_body.rotation = Vector3.ZERO
		_body.scale = Vector3.ONE
		set_process(false)
