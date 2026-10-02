extends Node3D
## Development-only clip source (src/dev is excluded from exports).
##   xvfb-run tools/gd.sh --path game --resolution 1280x720 --fixed-fps 30 --write-movie out.avi \
##       res://src/dev/motion_reel.tscn -- --reel=runner|watch [--label=V5]
## Plays MotionRig scenarios (tests/motion_rig.gd: the same 60 Hz mini-motor
## and interpolation path as the measurements) one after another under the
## game's night lighting, with a fixed three-quarter camera that follows the
## character exactly (no smoothing, so the clip shows the character's own
## motion).  The same file renders the V4 code for side-by-side clips.
## No water or spray effects: the splash shows the body only.

const REELS := {
	"runner": ["start", "stop", "reverse", "turn90", "jump_run", "dive", "splash", "emote"],
	"watch": ["tag_miss", "tag_hit", "cart", "nw_run"],
	"menu": ["menu_idle"],
}

var reel := "runner"
var label_text := ""
var cam: Camera3D
var label: Label
var cart: Node3D
var _rig: MotionRig
var _names: Array = []
var _offset := Vector3(3.6, 1.9, 3.6)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--reel="):
			reel = a.split("=")[1]
		elif a.begins_with("--label="):
			label_text = a.split("=")[1]
	add_child(EnvFactory.make_environment(1))
	add_child(EnvFactory.make_moon(1))
	var lawn := MeshInstance3D.new()
	var lp := PlaneMesh.new()
	lp.size = Vector2(400, 400)
	lawn.mesh = lp
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(0.25, 0.46, 0.30)
	lm.roughness = 0.95
	lm.uv1_scale = Vector3(200, 200, 1)
	lawn.material_override = lm
	add_child(lawn)
	# a grid of paving stones so ground travel and foot planting read
	var stones := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.02, 0.9)
	mm.mesh = bm
	mm.instance_count = 41 * 41
	var k := 0
	for x in 41:
		for z in 41:
			mm.set_instance_transform(k, Transform3D(Basis(), Vector3((x - 20) * 1.0, 0.0, (z - 20) * 1.0)))
			k += 1
	stones.multimesh = mm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.42, 0.44, 0.48)
	sm.roughness = 0.9
	stones.material_override = sm
	add_child(stones)
	cam = Camera3D.new()
	cam.fov = 40
	add_child(cam)
	var cl := CanvasLayer.new()
	add_child(cl)
	label = Label.new()
	label.position = Vector2(24, 18)
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 8)
	cl.add_child(label)
	_names = (REELS.get(reel, REELS["runner"]) as Array).duplicate()
	if reel == "menu":
		_offset = Vector3(0.0, 1.1, 3.4)
	_next()


func _next() -> void:
	if _rig:
		_rig.cleanup()
		_rig.queue_free()
		_rig = null
	if cart:
		cart.queue_free()
		cart = null
	if _names.is_empty():
		get_tree().quit()
		return
	var n: String = _names.pop_front()
	_rig = MotionRig.new()
	add_child(_rig)
	var c := Cosmetics.DEFAULT.duplicate()
	c["hat"] = "nightcap"
	_rig.start(n, Cosmetics.sanitize(c), 0.0)
	cam.current = true
	_rig.finished.connect(_next, CONNECT_ONE_SHOT)
	label.text = "%s  ·  %s  ·  fixed 30 fps clock (Movie Maker), llvmpipe" % [label_text, n.replace("_", " ")]


func _process(_delta: float) -> void:
	if _rig == null or _rig.view == null:
		return
	var v := _rig.view
	var p := v.global_position
	if _rig.scenario == "menu_idle":
		cam.look_at_from_position(Vector3(0.0, 1.1, 3.4), Vector3(0, 0.75, 0))
		return
	# cart sequence: a cart under the seat while seated
	var st: int = int(v.rs.get("state", 0))
	if _rig.scenario == "cart" and st in [TC.PState.ENTERING, TC.PState.IN_CART] and cart == null:
		var cv := CartView.new()
		add_child(cv)
		cv.setup(0)
		cart = cv
	if cart and st in [TC.PState.ENTERING, TC.PState.IN_CART]:
		var yaw := v.rotation.y
		var cpos := p - Basis(Vector3.UP, yaw) * CartView.SEAT
		(cart as CartView).apply_state({"pos": cpos, "yaw": yaw, "speed": Vector2(_rig.m.vel.x, _rig.m.vel.z).length(),
			"steer": float(v.rs.get("steer", 0.0)), "occupied": true})
	var ground := Vector3(p.x, 0.0, p.z)
	var off := _offset * (1.8 if _rig.scenario == "cart" else 1.0)
	cam.look_at_from_position(ground + off, ground + Vector3(0, 0.75, 0))
