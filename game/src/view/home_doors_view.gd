class_name HomeDoorsView
extends Node3D
## Tonight's home doors (V6), in the world: a soft warm light curtain in each
## doorway of the home dorm (one additive mesh for all of them, the same glow
## shader as the water beacons) and a tall warm beacon over the front door.
## Dim while a runner still has waters to splash; bright, with a gentle pulse
## (none with Reduced Motion), once they have all three - the way home.  The
## Night Watch sees the doors dimly (where runners will come back).
## Presentation only; the finish is the host's threshold test.

const GLOW := preload("res://assets/shaders/glow_add.gdshader")

var _doors_mi: MeshInstance3D
var _beacon: MeshInstance3D
var _mat: ShaderMaterial
var _beacon_mat: ShaderMaterial
var _state := -1


func setup(dorm_id: String) -> void:
	var g := CampusDorms.geometry(dorm_id)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := CampusDorms.DOOR_W * 0.5 - 0.05
	var h := CampusDorms.DOOR_H - 0.05
	for dr in g["doors"]:
		# a quad filling the opening, halfway through the wall; UV.y runs from
		# the floor (0) to the lintel (1), so the glow is strongest low down
		var mid: Vector2 = ((dr["pos"] as Vector2) + (dr["line_p"] as Vector2)) * 0.5
		var tg: Vector2 = dr["tangent"]
		var a := Vector3(mid.x - tg.x * hw, 0.02, mid.y - tg.y * hw)
		var b := Vector3(mid.x + tg.x * hw, 0.02, mid.y + tg.y * hw)
		var n_out: Vector2 = dr["normal"]
		var nrm := Vector3(n_out.x, 0, n_out.y)
		for v in [[a, 0.0], [b, 0.0], [b + Vector3.UP * h, 1.0], [a, 0.0], [b + Vector3.UP * h, 1.0], [a + Vector3.UP * h, 1.0]]:
			st.set_normal(nrm)
			st.set_uv(Vector2(0.0, float(v[1])))
			st.add_vertex(v[0])
	_mat = ShaderMaterial.new()
	_mat.shader = GLOW
	_mat.set_shader_parameter("color", Color(1.0, 0.78, 0.42))
	_mat.set_shader_parameter("mode", 1.0)
	_mat.set_shader_parameter("intensity", 0.35)
	_doors_mi = MeshInstance3D.new()
	_doors_mi.name = "HomeDoorGlow"
	_doors_mi.mesh = st.commit()
	_doors_mi.material_override = _mat
	_doors_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_doors_mi)
	# the beacon: like a water's, warm gold, over the front door
	var front: Dictionary = g["doors"][0]
	var fp: Vector2 = (front["pos"] as Vector2) + (front["normal"] as Vector2) * 1.5
	var cm := CylinderMesh.new()
	cm.top_radius = 1.4
	cm.bottom_radius = 2.0
	cm.height = 30.0
	cm.cap_top = false
	cm.cap_bottom = false
	cm.radial_segments = 16
	_beacon_mat = ShaderMaterial.new()
	_beacon_mat.shader = GLOW
	_beacon_mat.set_shader_parameter("color", Color(1.0, 0.80, 0.45))
	_beacon_mat.set_shader_parameter("mode", 1.0)
	_beacon_mat.set_shader_parameter("intensity", 0.0)
	_beacon_mat.set_shader_parameter("fade_near", 10.0)
	_beacon = MeshInstance3D.new()
	_beacon.name = "HomeBeacon"
	_beacon.mesh = cm
	_beacon.material_override = _beacon_mat
	_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beacon.position = Vector3(fp.x, 15.5, fp.y)
	_beacon.visible = false
	add_child(_beacon)


## state: 0 dim (still splashing / spectating), 1 Night Watch, 2 going home.
func set_state(state: int, reduced_motion: bool) -> void:
	if state == _state:
		return
	_state = state
	_mat.set_shader_parameter("intensity", [0.35, 0.28, 0.95][clampi(state, 0, 2)])
	_mat.set_shader_parameter("pulse", 1.0 if state == 2 and not reduced_motion else 0.0)
	_beacon.visible = state == 2
	_beacon_mat.set_shader_parameter("intensity", 0.5 if state == 2 else 0.0)
