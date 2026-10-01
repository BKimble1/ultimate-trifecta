class_name MenuBackground
extends Node3D
## Slow fly-over of the campus at night behind the menus.

var cam: Camera3D
var t := 0.0


func _ready() -> void:
	# let the menu UI present its first frames before the (heavier) campus
	# build, so launch never blocks on it
	set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var b := CampusBuilder.new(CampusLayout.shared())
	var waters := b.build_visuals(self, int(Save.get_setting("quality", 1)))
	for id in ["fountain", "pool", "garden"]:
		if waters.has(id):
			(waters[id]["mat"] as ShaderMaterial).set_shader_parameter("active", 1.0)
	add_child(EnvFactory.make_environment(int(Save.get_setting("quality", 1))))
	add_child(EnvFactory.make_moon(0))
	cam = Camera3D.new()
	cam.fov = 58
	cam.far = 500
	add_child(cam)
	cam.current = true
	# a few idle characters on the dorm lawn for life
	var names := ["", "", ""]
	for i in 3:
		var v := CharacterView.new()
		add_child(v)
		v.setup(TC.Role.RUNNER, Cosmetics.bot_cosmetic(i * 7 + 3), -1, names[i], false, true)
		v.global_position = Vector3(-3.0 + i * 3.0, 0, 90)
		v.apply_state({"pos": Vector3(-3.0 + i * 3.0, 0, 90), "yaw": 0.4 - i * 0.4, "state": TC.PState.ACTIVE, "vel": Vector3.ZERO, "on_floor": true, "emote": i % 3, "emote_t": 1.0}, 0.0, true)
	set_process(true)


func _process(delta: float) -> void:
	t += delta * 0.025
	var center := Vector3(0, 0, 40)
	cam.position = center + Vector3(sin(t) * 120.0, 46.0, cos(t) * 120.0)
	cam.look_at(Vector3(0, 4, 30))
