class_name PickupHologram
extends Node3D
## (2.3) A power-up on the campus: a small projector on the ground and the
## item itself as a hologram above it (Speed Sneakers, Squeaky Duck, Pillow
## Shield), turning slowly and bobbing, in the item's own colour.  V5-2.2
## drew every power-up as the same gold cube with a "?".

const SHADER := preload("res://assets/shaders/hologram.gdshader")
const TINTS := {TC.Gadget.TURBO: Color(0.3, 1.0, 0.85), TC.Gadget.DECOY: Color(1.0, 0.85, 0.3),
	TC.Gadget.SHIELD: Color(0.72, 0.6, 1.0), TC.Gadget.SPLASH_BOMB: Color(0.4, 0.75, 1.0), TC.Gadget.CLOAK: Color(0.85, 0.95, 1.0)}

var kind := TC.Gadget.TURBO
var base_y := 0.0
var item: Node3D
var beam: MeshInstance3D
var _mat: ShaderMaterial


static func make(g: int, ground_y: float) -> PickupHologram:
	var h := PickupHologram.new()
	h.kind = g
	h.base_y = ground_y
	h._build()
	return h


func _build() -> void:
	var tint: Color = TINTS.get(kind, Color(0.3, 1.0, 0.85))
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("tint", tint)
	PropKit.init_meshes()
	# the projector: a dark puck with a glowing ring on top
	var puck := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.42
	cm.bottom_radius = 0.48
	cm.height = 0.12
	cm.radial_segments = 24
	puck.mesh = cm
	puck.material_override = PropKit.mat(Color(0.12, 0.14, 0.2), 0.0, Color.WHITE, 0.4)
	puck.position = Vector3(0, 0.06, 0)
	add_child(puck)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.3
	tm.outer_radius = 0.38
	tm.rings = 24
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = tint
	ring.material_override = rm
	ring.position = Vector3(0, 0.13, 0)
	ring.scale = Vector3(1, 0.4, 1)
	add_child(ring)
	# the light it throws up
	beam = MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.62
	bm.bottom_radius = 0.3
	bm.height = 1.1
	bm.cap_top = false
	bm.cap_bottom = false
	bm.radial_segments = 20
	beam.mesh = bm
	var bmat := _mat.duplicate() as ShaderMaterial
	bmat.set_shader_parameter("strength", 0.45)
	beam.material_override = bmat
	beam.position = Vector3(0, 0.68, 0)
	add_child(beam)
	# the item
	item = Node3D.new()
	item.position = Vector3(0, 1.0, 0)
	item.scale = Vector3.ONE * 1.6
	add_child(item)
	# a soft glow the item sits in, so it reads from across a lawn at night
	# (a translucent sphere, not a light: 16 spots can't each cost a light)
	var halo := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.75
	hs.height = 1.5
	hs.radial_segments = 16
	hs.rings = 8
	halo.mesh = hs
	var hm := _mat.duplicate() as ShaderMaterial
	hm.set_shader_parameter("strength", 0.12)
	halo.material_override = hm
	halo.position = Vector3(0, 1.0, 0)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)
	match kind:
		TC.Gadget.TURBO:
			_sneaker()
		TC.Gadget.DECOY:
			_duck()
		TC.Gadget.CLOAK:
			_cloak()
		_:
			_pillow()


func _part(mesh: Mesh, pos: Vector3, scl: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat
	mi.position = pos
	mi.scale = scl
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	item.add_child(mi)
	return mi


func _sphere() -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = 16
	s.rings = 10
	return s


func _sneaker() -> void:
	# a running shoe: a thick sole, the rounded upper, the toe and the heel
	# collar, laces as three bars; tipped forward a little as if mid-stride
	var box := BoxMesh.new()
	var sp := _sphere()
	_part(box, Vector3(0, -0.12, 0), Vector3(0.66, 0.08, 0.26))
	_part(sp, Vector3(0.12, -0.02, 0), Vector3(0.5, 0.2, 0.25))
	_part(sp, Vector3(-0.12, 0.06, 0), Vector3(0.4, 0.34, 0.25))
	_part(sp, Vector3(-0.22, 0.2, 0), Vector3(0.2, 0.16, 0.22))
	for k in 3:
		_part(box, Vector3(0.0 + float(k) * 0.09, 0.08 - float(k) * 0.035, 0), Vector3(0.025, 0.02, 0.2), Vector3(0, 0, -0.5))
	item.rotation.z = -0.12


func _duck() -> void:
	var sp := _sphere()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.5
	cone.height = 1.0
	_part(sp, Vector3(0, -0.04, 0), Vector3(0.52, 0.36, 0.4))
	_part(sp, Vector3(0.2, 0.22, 0), Vector3(0.28, 0.28, 0.28))
	_part(cone, Vector3(0.4, 0.2, 0), Vector3(0.12, 0.16, 0.12), Vector3(0, 0, -PI * 0.5))
	_part(sp, Vector3(-0.26, 0.04, 0), Vector3(0.14, 0.2, 0.14), Vector3(0, 0, 0.6))


## (2.2 build 17) the Invisibility Cloak: a hooded cape, draped
func _cloak() -> void:
	var sp := _sphere()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.18
	cone.bottom_radius = 0.5
	cone.height = 1.0
	cone.radial_segments = 16
	_part(cone, Vector3(0, -0.06, 0), Vector3(0.62, 0.5, 0.36))   # the cape
	_part(sp, Vector3(0, 0.26, 0), Vector3(0.3, 0.3, 0.28))       # the hood
	_part(sp, Vector3(0, 0.24, 0.06), Vector3(0.18, 0.18, 0.12))  # its opening


func _pillow() -> void:
	# a puffy pillow held up like a shield, with a stitched seam
	var sp := _sphere()
	_part(sp, Vector3.ZERO, Vector3(0.62, 0.46, 0.2))
	for k in 4:
		var a := TAU * float(k) / 4.0 + PI * 0.25
		_part(sp, Vector3(cos(a) * 0.27, sin(a) * 0.2, 0), Vector3(0.16, 0.16, 0.14))
	var tm := TorusMesh.new()
	tm.inner_radius = 0.42
	tm.outer_radius = 0.46
	_part(tm, Vector3.ZERO, Vector3(0.62, 0.46, 0.5), Vector3(PI * 0.5, 0, 0))


## Turning and bobbing (Reduced Motion: still).
func animate(t: float, i: int, still: bool) -> void:
	if still:
		return
	item.rotation.y = t * 1.3 + float(i)
	item.position.y = 1.05 + sin(t * 2.0 + float(i)) * 0.08
	_mat.set_shader_parameter("strength", 0.9 + 0.1 * sin(t * 3.0 + float(i)))
