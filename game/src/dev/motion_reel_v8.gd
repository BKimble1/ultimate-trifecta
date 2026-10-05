extends Node3D
## Development-only evidence (src/dev: never exported): the V8 motion clips.
## Gameplay scenarios from the motion tests (tests/motion_rig.gd: the 60 Hz
## mini-motor with the RulesConfig values -> interpolation -> CharacterView,
## the same path as a match) on the game's own night lighting and a lawn
## with a 1 m grid (so planted feet and slides can be read), each scenario
## seen from behind at about the follow camera's distance and then from the
## side.  The same file runs on the build-6 checkout for "before".  Record
## with Movie Maker at a fixed 30 fps clock (normal speed):
##   tools/gd.sh --path game --write-movie OUT.avi --fixed-fps 30 res://src/dev/motion_reel_v8.tscn -- [--scenarios=a,b] [--views=game,side]
## (tools/capture_v8_motion.sh OUT NAME [ROOT] records and labels it; the V5 motion_reel.tscn is the studio-light version.)
## Desktop rendering of scripted input, not device footage.
## Pass 8: --look=JSON wears another look (an outfit through the same
## scenarios, e.g. --look={"outfit":"moonwalk_cadet","hat":"none"}); its
## name goes into the caption.

const SCENARIOS := ["start", "stop", "reverse", "turn90", "sprint", "jump_run", "tag_miss", "tag_hit", "splash", "cart"]
const LOOK := {"outfit": "pj", "hat": "nightcap", "shoes": "slippers", "pattern": "stripes", "skin": "tone3", "color": "sky"}

var scenarios: Array = SCENARIOS.duplicate()
var look: Dictionary = LOOK.duplicate()
var views: Array = ["game", "side"]
var cam: Camera3D
var rig: MotionRig
var _i := -1
var _caption: Label
var _sub: Label
var _cam_at := Vector3.ZERO


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scenarios="):
			scenarios = Array(a.get_slice("=", 1).split(","))
		elif a.begins_with("--views="):
			views = Array(a.get_slice("=", 1).split(","))
		elif a.begins_with("--look="):
			look.merge(JSON.parse_string(a.substr(a.find("=") + 1)), true)
	add_child(EnvFactory.make_environment(1))
	add_child(EnvFactory.make_moon(1))
	var lawn := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	lawn.mesh = pm
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode cull_disabled;
void fragment() {
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 g = abs(fract(w.xz) - 0.5);
	float line = 1.0 - smoothstep(0.47, 0.49, max(g.x, g.y));
	ALBEDO = mix(vec3(0.20, 0.38, 0.25), vec3(0.32, 0.52, 0.36), 1.0 - line);
	ROUGHNESS = 0.95;
}"""
	sm.shader = sh
	lawn.material_override = sm
	add_child(lawn)
	cam = Camera3D.new()
	cam.fov = 55.0
	add_child(cam)
	cam.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	_caption = _label(layer, 26, 14)
	_sub = _label(layer, 18, 50)
	_next.call_deferred()


func _label(layer: CanvasLayer, sz: int, y: float) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_TOP_WIDE)
	l.position = Vector2(0, y)
	layer.add_child(l)
	return l


func _next() -> void:
	if rig:
		rig.cleanup()
		rig.queue_free()
		rig = null
	_i += 1
	if _i >= scenarios.size() * views.size():
		_caption.text = "End"
		_sub.text = ""
		for k in 15:
			await get_tree().process_frame
		get_tree().quit()
		return
	var sc: String = scenarios[_i / views.size()]
	var view: String = views[_i % views.size()]
	_caption.text = sc.replace("_", " ")
	if look.has("outfit") and String(look["outfit"]) != String(LOOK["outfit"]):
		_caption.text = "%s  ·  %s" % [Cosmetics.entry("outfit", String(look["outfit"])).get("name", ""), _caption.text]
	_sub.text = "from behind (follow-camera distance)" if view == "game" else "from the side"
	rig = MotionRig.new()
	add_child(rig)
	rig.start(sc, Cosmetics.sanitize(look.duplicate()), 0.0)
	rig.cam.current = false
	cam.current = true
	_cam_at = Vector3.ZERO
	set_meta("view", view)


func _process(delta: float) -> void:
	if rig == null:
		return
	var p := rig.view.global_position
	var target := p + Vector3(0, 0.9, 0)
	if _cam_at == Vector3.ZERO:
		_cam_at = target
	# a follow camera's lag (not locked to the pelvis: the body's own motion shows)
	_cam_at = _cam_at.lerp(target, 1.0 - exp(-delta / 0.12))
	if String(get_meta("view", "game")) == "game":
		cam.look_at_from_position(_cam_at + Vector3(0.0, 1.6, 4.6), _cam_at + Vector3(0, 0.1, -1.2))
	else:
		cam.look_at_from_position(_cam_at + Vector3(4.2, 0.5, 0.0), _cam_at)
	if not rig.running:
		_next()
