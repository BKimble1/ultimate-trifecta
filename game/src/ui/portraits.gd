class_name Portraits
extends Node
## Head-and-shoulders portraits of runners for the party panel and player
## sheets, rendered once per look in a small off-screen viewport (the same
## CharacterView and asset as everywhere else) and cached by appearance.
## Requests are queued and rendered one per frame pair; until a portrait is
## ready the caller gets a soft placeholder in the runner's colour.
## Headless runs (tests, servers) never render and always get placeholders.

signal portrait_ready(key: String, tex: Texture2D)

const SIZE := 160
const MAX_CACHE := 48

static var _inst: Portraits
var _cache: Dictionary = {}      # key -> Texture2D
var _order: Array = []           # LRU keys
var _queue: Array = []           # [{key, role, app}]
var _busy := false
var _vp: SubViewport
var _view: CharacterView
var _cam: Camera3D


static func shared() -> Portraits:
	if _inst == null or not is_instance_valid(_inst):
		_inst = Portraits.new()
		_inst.name = "Portraits"
		(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_inst)
	return _inst


static func key_of(app: Dictionary, role: int) -> String:
	return "%d:%s" % [role, Cosmetics.encode(app).hex_encode()]


## Cached portrait, or a placeholder now and `portrait_ready` later.
func portrait(app: Dictionary, role: int = TC.Role.RUNNER) -> Texture2D:
	var a := Cosmetics.sanitize(app)
	var k := key_of(a, role)
	if _cache.has(k):
		_order.erase(k)
		_order.append(k)
		return _cache[k]
	if DisplayServer.get_name() != "headless" and not _queue.any(func(q: Dictionary) -> bool: return q["key"] == k):
		_queue.append({"key": k, "role": role, "app": a})
	return placeholder(a)


static func placeholder(app: Dictionary) -> Texture2D:
	var g := Gradient.new()
	var c := Cosmetics.color_of(app)
	g.set_color(0, c.lightened(0.2))
	g.set_color(1, Color(c.darkened(0.3), 0.0))
	g.add_point(0.62, c)
	g.add_point(0.66, Color(c, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	return t


func _ensure_rig() -> void:
	if _vp != null:
		return
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("8a8fb0")
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, 25, 0)
	key.light_color = Color(1.0, 0.9, 0.78)
	key.light_energy = 1.2
	_vp.add_child(key)
	_view = CharacterView.new()
	_view.lighting = "indoor"
	_view.fidgets = false
	_vp.add_child(_view)
	_view.setup(TC.Role.RUNNER, Cosmetics.DEFAULT, -1, "", false, true)
	_view.apply_state({"pos": Vector3.ZERO, "yaw": PI + 0.35, "state": TC.PState.ACTIVE, "vel": Vector3.ZERO, "on_floor": true}, 0.0, true)
	_view.set_process(false)
	_cam = Camera3D.new()
	_cam.fov = 24
	_vp.add_child(_cam)
	_cam.current = true
	_cam.look_at_from_position(Vector3(0.0, 1.25, 1.85), Vector3(0.0, 1.13, 0.0))


func _process(_d: float) -> void:
	if _busy or _queue.is_empty():
		return
	_render(_queue.pop_front())


func _render(q: Dictionary) -> void:
	_busy = true
	_ensure_rig()
	_view.set_appearance(int(q["role"]), q["app"])
	_view.tree.active = false
	_view.anim.play("idle")
	_view.anim.seek(0.6, true)
	_view.anim.pause()
	for n in _view._face_idx:
		_view.base_mesh.set_blend_shape_value(_view._face_idx[n], 0.0)
	var base: Dictionary = Cosmetics.face_keys(q["app"])
	for n in base:
		if _view._face_idx.has(n):
			_view.base_mesh.set_blend_shape_value(_view._face_idx[n], float(base[n]))
	if _view._face_idx.has("smile"):
		_view.base_mesh.set_blend_shape_value(_view._face_idx["smile"], 0.5)
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	var tex := ImageTexture.create_from_image(img)
	var k := String(q["key"])
	_cache[k] = tex
	_order.append(k)
	while _order.size() > MAX_CACHE:
		_cache.erase(_order.pop_front())
	_busy = false
	portrait_ready.emit(k, tex)
