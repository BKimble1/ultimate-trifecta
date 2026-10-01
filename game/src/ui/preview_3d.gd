class_name Preview3D
extends Control
## Small isolated 3D stage (own world) for inline character previews.
##
## Sizing strategy (measured: a stretched SubViewportContainer renders at
## canvas-unit size, e.g. 400x470 px shown at 650x764 px on a 2532x1170
## phone = 1.63x upscale and soft): the SubViewport here renders at the
## *displayed pixel size* (control size x canvas-to-window scale) and a
## TextureRect draws it 1:1.  Nothing else resizes the viewport.
## Full-screen menu stages (home, lobby) do not use this: they render in
## the root viewport directly.

var vp: SubViewport
var stage: Node3D
var cam: Camera3D
var views: Array[CharacterView] = []
var tex: TextureRect


func _init(min_canvas: Vector2i = Vector2i(420, 480)) -> void:
	custom_minimum_size = Vector2(min_canvas)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	vp.size = min_canvas
	add_child(vp)
	tex = TextureRect.new()
	tex.texture = vp.get_texture()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tex)
	stage = Node3D.new()
	vp.add_child(stage)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("8fa3c8")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	we.environment = env
	stage.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 28, 0)
	key.light_energy = 1.2
	key.light_color = Color(1.0, 0.92, 0.82)
	stage.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, -150, 0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.6, 0.72, 1.0)
	stage.add_child(fill)
	cam = Camera3D.new()
	cam.fov = 32
	stage.add_child(cam)
	aim(Vector3(0, 1.05, 4.0), Vector3(0, 0.78, 0))
	resized.connect(_fit)


func _ready() -> void:
	get_viewport().size_changed.connect(_fit)
	_fit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		_fit()


## Render-target size = displayed size in window pixels.
func _fit() -> void:
	if not is_inside_tree():
		return
	var scale := get_viewport().get_final_transform().get_scale() * get_global_transform_with_canvas().get_scale()
	var px := (size * scale).round()
	var want := Vector2i(clampi(int(px.x), 16, 4096), clampi(int(px.y), 16, 4096))
	if vp.size != want:
		vp.size = want


func aim(from: Vector3, at: Vector3) -> void:
	cam.transform = Transform3D(Basis.looking_at(at - from, Vector3.UP), from)


## yaw PI faces the camera (characters face -Z at yaw 0).
func show_character(role: int, cosmetic: Dictionary, pos: Vector3 = Vector3.ZERO, yaw: float = PI, emote: int = -1) -> CharacterView:
	var v := CharacterView.new()
	v.lighting = "indoor"
	stage.add_child(v)
	v.setup(role, cosmetic, -1, "", false, true)
	v.apply_state({"pos": pos, "yaw": yaw, "state": TC.PState.ACTIVE, "vel": Vector3.ZERO, "on_floor": true, "emote": emote, "emote_t": 1.0 if emote >= 0 else 0.0}, 0.0, true)
	views.append(v)
	return v


func clear() -> void:
	for v in views:
		v.queue_free()
	views.clear()
