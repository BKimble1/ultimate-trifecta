extends Node
## Development-only (src/dev is excluded from exports): renders the match
## loading loop from the actual game rig (V5).
##
##   tools/make_loading_loop_rig.sh   (renders, then packs the atlas)
##
## Three fully clothed representative runners (the shared skinned asset,
## the game's character shader and animation graph) run in place on a
## transparent background under a stable camera and a fixed light rig: a
## warm key, a cool moonlit rim and a soft fill, plus a soft contact shadow
## under each runner.  Frames are premultiplied by coverage (the viewport
## clears to transparent black), so the loading screen draws them with
## premultiplied blending over its own background: no seams on any width.
##
## The loop is exact: the run speed is solved so one gait cycle lasts a
## whole number of frames at the target rate (CharacterView.gait_rate), the
## runners are offset by fractions of that cycle, and after a pre-roll the
## secondary motion (hat springs) has settled into the same periodic motion,
## so the last frame leads into the first like any other pair.  Idle fidgets
## and blinks are off (they would break the period).
##
## Args: --out=DIR --fps=60 --frames=26 --size=1024x576 [--preroll=3.0]

var out_dir := "user://loading_loop"
var fps := 60
var frames := 26
var size := Vector2i(1024, 576)
var preroll := 3.0
var _vp: SubViewport
var _views: Array[CharacterView] = []
var _speed := 5.0
var _i := -1
var _pre := 0

## [cosmetic, x, z, phase offset (cycles), yaw offset]
const RUNNERS := [
	[{"outfit": "duck", "color": "sunny", "skin": "tone6", "hair": "curly", "hair_color": "black", "hat": "none", "shoes": "sneakers", "trim": "auto"}, -1.05, -0.35, 0.37, 0.16],
	[{"outfit": "pj", "pattern": "stripes", "color": "sky", "trim": "auto", "skin": "tone2", "hair": "tuft", "hair_color": "brown", "hat": "nightcap", "shoes": "slippers"}, 0.0, 0.25, 0.0, 0.0],
	[{"outfit": "frog", "color": "lime", "skin": "tone4", "hair": "bob", "hair_color": "auburn", "hat": "none", "shoes": "slippers", "trim": "auto"}, 1.05, -0.35, 0.71, -0.16],
]


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.get_slice("=", 1)
		elif a.begins_with("--fps="):
			fps = int(a.get_slice("=", 1))
		elif a.begins_with("--frames="):
			frames = int(a.get_slice("=", 1))
		elif a.begins_with("--size="):
			var v := a.get_slice("=", 1).split("x")
			size = Vector2i(int(v[0]), int(v[1]))
		elif a.begins_with("--preroll="):
			preroll = float(a.get_slice("=", 1))
	DirAccess.make_dir_recursive_absolute(out_dir)
	_speed = _solve_speed(float(fps) / float(frames))
	print("loop: %d frames at %d fps = %.3f s per gait cycle, run speed %.3f m/s" % [frames, fps, float(frames) / fps, _speed])
	_build()


## The ground speed whose gait rate is `cycles_per_s` (bisection on the
## character's own speed -> cadence curve), so N frames hold one cycle.
func _solve_speed(cycles_per_s: float) -> float:
	var lo := 3.0
	var hi := 7.0
	for i in 40:
		var mid := (lo + hi) * 0.5
		if CharacterView.gait_rate(mid) < cycles_per_s:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


func _build() -> void:
	_vp = SubViewport.new()
	_vp.size = size
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("7d86b8")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	# warm key from the front left, above (the shadow-casting light)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, -28, 0)
	key.light_color = Color(1.0, 0.88, 0.72)
	key.light_energy = 1.15
	key.shadow_enabled = true
	key.shadow_blur = 2.0
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = 8.0
	_vp.add_child(key)
	# cool moonlit rim from behind, right
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 150, 0)
	rim.light_color = Color(0.55, 0.72, 1.0)
	rim.light_energy = 0.9
	_vp.add_child(rim)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-8, 10, 0)
	fill.light_color = Color(0.8, 0.84, 1.0)
	fill.light_energy = 0.25
	fill.light_specular = 0.0
	_vp.add_child(fill)
	var cam := Camera3D.new()
	cam.fov = 16.5
	_vp.add_child(cam)
	cam.current = true
	# a slightly low, stable camera on a long lens: the group fills the frame
	# head to shoe with little perspective stretch
	cam.look_at_from_position(Vector3(0.0, 1.0, 6.6), Vector3(0.0, 0.72, 0.0))
	for r in RUNNERS:
		var v := CharacterView.new()
		v.lighting = "indoor"
		v.fidgets = false
		_vp.add_child(v)
		v.setup(TC.Role.RUNNER, Cosmetics.sanitize(r[0]), -1, "", false, true)
		v.position = Vector3(float(r[1]), 0.0, float(r[2]))
		# run toward the camera, turned a little to the side (three-quarter)
		v.face_toward(cam.global_position * Vector3(1, 0, 1))
		v.set_facing(v.rotation.y + float(r[4]))
		if v.name_label:
			v.name_label.visible = false
		_views.append(v)
		# soft contact shadow (premultiplied: black with partial alpha)
		var sh := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(1.15, 0.75)
		sh.mesh = q
		sh.rotation_degrees = Vector3(-90, 0, 0)
		sh.position = v.position + Vector3(0, 0.005, 0)
		var sm := ShaderMaterial.new()
		var shader := Shader.new()
		shader.code = "shader_type spatial;\nrender_mode unshaded, blend_mix, depth_draw_never, shadows_disabled;\nvoid fragment() {\n\tfloat d = length((UV - 0.5) * 2.0);\n\tALBEDO = vec3(0.0);\n\tALPHA = 0.42 * pow(clamp(1.0 - d, 0.0, 1.0), 1.6);\n}\n"
		sm.shader = shader
		sh.material_override = sm
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_vp.add_child(sh)
	# start each runner at its phase offset within the cycle
	for i in _views.size():
		var v := _views[i]
		v.set("_phase", float(RUNNERS[i][3]))


var _busy := false


## One loop frame per engine frame: advance every runner by exactly 1/fps,
## then save what was drawn.  Frames 0..N are written; frame N should match
## frame 0 (the packer checks it), and only 0..N-1 are packed.
func _process(_d: float) -> void:
	if _busy or _views.is_empty():
		return
	var dt := 1.0 / float(fps)
	for v in _views:
		var fwd := -v.global_transform.basis.z
		v.apply_state({"pos": v.global_position, "yaw": v.rotation.y, "state": TC.PState.ACTIVE, "vel": fwd * _speed, "on_floor": true})
		v.set_process(false)
		if "_blink_t" in v:
			v.set("_blink_t", 1000.0)   # no blink inside the loop
		v._process(dt)
	if _pre < int(preroll * fps):
		_pre += 1
		return
	_busy = true
	if _i < 0:
		_i = 0
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	img.save_png(out_dir.path_join("f_%03d.png" % _i))
	_i += 1
	if _i > frames:
		print("wrote %d frames to %s" % [frames + 1, out_dir])
		get_tree().quit()
		return
	_busy = false
