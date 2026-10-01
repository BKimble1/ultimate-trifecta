class_name PropKit
extends RefCounted
## Shared primitive meshes and the prop material (carts, pickups, beacons).
## Characters use the skinned asset in CharacterView instead.

const SHADER := preload("res://assets/shaders/prop.gdshader")

static var _mat_cache: Dictionary = {}
static var sphere: SphereMesh
static var capsule: CapsuleMesh
static var cyl: CylinderMesh
static var box: BoxMesh
static var cone: CylinderMesh


static func init_meshes() -> void:
	if sphere != null:
		return
	sphere = SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 18
	sphere.rings = 10
	capsule = CapsuleMesh.new()
	capsule.radius = 0.5
	capsule.height = 2.0
	capsule.radial_segments = 16
	capsule.rings = 6
	cyl = CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	cyl.height = 1.0
	cyl.radial_segments = 12
	box = BoxMesh.new()
	cone = CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.5
	cone.height = 1.0
	cone.radial_segments = 12


static func mat(col: Color, stripes: float = 0.0, stripe_col: Color = Color.WHITE, emission: float = 0.0, rim: float = 0.12) -> ShaderMaterial:
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
