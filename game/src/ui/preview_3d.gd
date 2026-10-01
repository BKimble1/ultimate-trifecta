class_name Preview3D
extends SubViewportContainer
## Small isolated 3D stage (own world) for character previews and the lobby.

var vp: SubViewport
var stage: Node3D
var cam: Camera3D
var views: Array[CharacterView] = []


func _init(px: Vector2i = Vector2i(420, 480)) -> void:
	stretch = true
	custom_minimum_size = Vector2(px)
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_2X
	vp.size = px
	add_child(vp)
	stage = Node3D.new()
	vp.add_child(stage)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.9)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	stage.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_energy = 1.1
	key.light_color = Color(1.0, 0.92, 0.8)
	stage.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-2, 2.5, -2)
	rim.light_color = Color(0.5, 0.7, 1.0)
	rim.light_energy = 2.0
	rim.omni_range = 8.0
	stage.add_child(rim)
	cam = Camera3D.new()
	cam.fov = 40
	stage.add_child(cam)
	aim(Vector3(0, 1.3, 3.2), Vector3(0, 0.95, 0))
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func aim(from: Vector3, at: Vector3) -> void:
	cam.transform = Transform3D(Basis.looking_at(at - from, Vector3.UP), from)


func show_character(role: int, cosmetic: Dictionary, pos: Vector3 = Vector3.ZERO, yaw: float = PI, emote: int = -1) -> CharacterView:
	var v := CharacterView.new()
	stage.add_child(v)
	v.setup(role, cosmetic, -1, "", false, true)
	v.apply_state({"pos": pos, "yaw": yaw, "state": TC.PState.ACTIVE, "vel": Vector3.ZERO, "on_floor": true, "emote": emote, "emote_t": 1.0 if emote >= 0 else 0.0}, 0.0, true)
	views.append(v)
	return v


func clear() -> void:
	for v in views:
		v.queue_free()
	views.clear()
