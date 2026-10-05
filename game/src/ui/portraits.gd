class_name Portraits
extends Node
## Head-and-shoulders portraits of runners for the party panel and player
## sheets, rendered once per look in a small off-screen viewport (the same
## CharacterView and asset as everywhere else) and cached by appearance.
## Until a portrait is ready the caller gets a soft placeholder in the
## runner's colour.  Headless runs (tests, servers) never render.
##
## V4 (smoothness):
##  - No CPU readback.  A portrait is rendered once, then copied on the GPU
##    into a cell of a bounded atlas viewport that is never cleared; callers
##    get an AtlasTexture of that cell.  (V3 read every portrait back with
##    get_image, a GPU sync point.)
##  - The portrait viewport uses the main view's MSAA level, so it reuses the
##    character pipelines already compiled for the dorm stage instead of
##    compiling 4x variants on the first portrait.
##  - Jobs: one in flight, three frames each; a newer request from the
##    same owner (a party cell) replaces its queued older one, and the queue
##    is bounded, so stale looks are never rendered.

signal portrait_ready(key: String, tex: Texture2D)
## A cell was reused for another look: holders of `key` should ask again.
signal portrait_evicted(key: String)

## V5: 240 px cells (wardrobe item cards show the picture at ~150 canvas
## units, ~240 px on an @3x phone), 8x5 cells (1920x1200 RGBA8, ~9 MB).
const SIZE := 240
const COLS := 8
const ROWS := 5
const MAX_CACHE := COLS * ROWS
const MAX_QUEUE := 24
const COPY_SHADER := "shader_type canvas_item;\nrender_mode blend_disabled;\nvoid fragment() { COLOR = texture(TEXTURE, UV); }\n"

static var _inst: Portraits
var _cache: Dictionary = {}      # key -> AtlasTexture
var _cell_of: Dictionary = {}    # key -> cell index
var _order: Array = []           # LRU keys
var _queue: Array = []           # [{key, role, app, owner}]
var _busy := false
var _vp: SubViewport
var _view: CharacterView
var _cam: Camera3D
var _atlas: SubViewport
var _copy: TextureRect
var renders := 0                 # portraits rendered (diagnostics/tests)
var dropped := 0                 # stale requests skipped


static func shared() -> Portraits:
	if _inst == null or not is_instance_valid(_inst):
		_inst = Portraits.new()
		_inst.name = "Portraits"
		(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_inst)
	return _inst


## V7: the look this renderer gives a portrait (framing, lights, the
## character shader's treatment).  Bump it when those change; the asset's own
## version (CharacterArt.VERSION, generated with runner.glb) changes by itself.
const LOOK_VERSION := 1


## The art a cached picture shows: the character asset build plus this
## renderer's look.  Part of every key, so pictures of an older asset or look
## are never reused for the current one.
static func art_version() -> String:
	return "%s.%d" % [CharacterArt.VERSION, LOOK_VERSION]


static func key_of(app: Dictionary, role: int) -> String:
	return "%s:%d:%s" % [art_version(), role, Cosmetics.encode(app).hex_encode()]


## Cached portrait, or a placeholder now and `portrait_ready` later.
## `owner` (e.g. a party cell): its newer request replaces its queued one.
## `framing`: "head" (portraits, face/hair thumbnails), "hat" (V6: hat
## thumbnails, room for tall hats), "body" (outfit thumbnails) or "feet" (shoes).
func portrait(app: Dictionary, role: int = TC.Role.RUNNER, owner: String = "", framing: String = "head") -> Texture2D:
	var a := Cosmetics.sanitize(app)
	var k := key_of(a, role) + ("" if framing == "head" else ":" + framing)
	if _cache.has(k):
		_order.erase(k)
		_order.append(k)
		return _cache[k]
	if DisplayServer.get_name() != "headless":
		_enqueue({"key": k, "role": role, "app": a, "owner": owner, "framing": framing})
	return placeholder(a)


## The cache key `portrait` uses for a look and framing.
static func key_for(app: Dictionary, role: int, framing: String = "head") -> String:
	return key_of(Cosmetics.sanitize(app), role) + ("" if framing == "head" else ":" + framing)


## Camera per framing: [position, look-at, fov].
const FRAMINGS := {
	"head": [Vector3(0.0, 1.25, 1.85), Vector3(0.0, 1.13, 0.0), 24.0],
	"body": [Vector3(0.0, 0.85, 2.6), Vector3(0.0, 0.8, 0.0), 36.0],
	"feet": [Vector3(0.35, 0.55, 1.45), Vector3(0.0, 0.1, 0.0), 26.0],
	# V6: hat cards (the head framing cut off tall hats: party hat, crown,
	# pompom, owl ears)
	"hat": [Vector3(0.0, 1.33, 2.15), Vector3(0.0, 1.27, 0.0), 26.0],
}


func _enqueue(q: Dictionary) -> void:
	var owner := String(q["owner"])
	for i in range(_queue.size() - 1, -1, -1):
		var old: Dictionary = _queue[i]
		if old["key"] == q["key"]:
			return
		if owner != "" and String(old["owner"]) == owner:
			_queue.remove_at(i)
			dropped += 1
	_queue.append(q)
	while _queue.size() > MAX_QUEUE:
		_queue.pop_front()
		dropped += 1


func pending() -> int:
	return _queue.size()


## Cancel on the shared renderer if there is one (never creates it: safe
## during teardown).
static func cancel_shared(prefix: String) -> void:
	if _inst != null and is_instance_valid(_inst):
		_inst.cancel(prefix)


## Drop queued requests whose owner starts with `prefix` (the wardrobe's
## previous category): they will never be shown, so they are never rendered.
func cancel(prefix: String) -> void:
	for i in range(_queue.size() - 1, -1, -1):
		if String(_queue[i]["owner"]).begins_with(prefix):
			_queue.remove_at(i)
			dropped += 1


## True when `key` is cached (a picture, not the placeholder).
func has_picture(key: String) -> bool:
	return _cache.has(key)


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
	# the main view's level (Standard and Battery Saver both use 2x): same
	# pipelines as the dorm stage, no 4x variants compiled on first use
	_vp.msaa_3d = get_tree().root.msaa_3d
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
	# the atlas: never cleared, each portrait drawn into its own cell
	_atlas = SubViewport.new()
	_atlas.size = Vector2i(SIZE * COLS, SIZE * ROWS)
	_atlas.transparent_bg = true
	_atlas.disable_3d = true
	_atlas.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	_atlas.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_atlas)
	_copy = TextureRect.new()
	_copy.size = Vector2(SIZE, SIZE)
	_copy.texture = _vp.get_texture()
	var sm := Shader.new()
	sm.code = COPY_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sm
	_copy.material = mat   # overwrite the cell (alpha too), no blending
	_atlas.add_child(_copy)


func _process(_d: float) -> void:
	if _busy or _queue.is_empty():
		return
	_render(_queue.pop_front())


func _free_cell() -> int:
	if _cell_of.size() < MAX_CACHE:
		var used := {}
		for k in _cell_of:
			used[_cell_of[k]] = true
		for i in MAX_CACHE:
			if not used.has(i):
				return i
	var oldest: String = _order.pop_front()
	var cell: int = _cell_of[oldest]
	_cell_of.erase(oldest)
	_cache.erase(oldest)
	portrait_evicted.emit(oldest)
	return cell


func _render(q: Dictionary) -> void:
	_busy = true
	Diag.mark("lobby_portrait")
	if _vp == null:
		# a new rig's first render comes out with untinted (grey) skin, even
		# after a settle frame: render it once unseen, which also compiles
		# the portrait pipelines before the first real portrait
		_ensure_rig()
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		if not is_inside_tree():
			return
	_view.set_appearance(int(q["role"]), q["app"])
	_view.tree.active = false
	_view.anim.play("idle")
	_view.anim.seek(0.6, true)
	_view.anim.pause()
	# the look's held face and a small smile, on the head that is shown
	# (Pass 9: a complete skin's own head)
	_view.show_face({"smile": 0.5})
	var fr: Array = FRAMINGS.get(String(q.get("framing", "head")), FRAMINGS["head"])
	_cam.fov = float(fr[2])
	_cam.look_at_from_position(fr[0], fr[1])
	# one settle frame: per-instance tints of parts just shown (a new outfit,
	# hair, the first portrait) reach the renderer a frame later, and a
	# portrait rendered at once came out with the default grey skin
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	# next frame: copy the finished portrait into its atlas cell (GPU only)
	var cell := _free_cell()
	_copy.position = Vector2((cell % COLS) * SIZE, (cell / COLS) * SIZE)
	_atlas.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var tex := AtlasTexture.new()
	tex.atlas = _atlas.get_texture()
	tex.region = Rect2(_copy.position, Vector2(SIZE, SIZE))
	var k := String(q["key"])
	_cache[k] = tex
	_cell_of[k] = cell
	_order.append(k)
	renders += 1
	_busy = false
	portrait_ready.emit(k, tex)
