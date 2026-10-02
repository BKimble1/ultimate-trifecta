extends Node3D
## Dev tool: renders the campus from several viewpoints to PNGs.
## Usage: godot --path game res://src/dev_shots.tscn -- <outdir>

var shots := [
	{"name": "quad_fountain", "pos": Vector3(18, 9, 52), "look": Vector3(0, 1, 20)},
	{"name": "dorm_front", "pos": Vector3(-16, 7, 74), "look": Vector3(0, 3, 108)},
	{"name": "overview", "pos": Vector3(0, 150, 170), "look": Vector3(0, 0, 0)},
	{"name": "pool", "pos": Vector3(88, 10, 50), "look": Vector3(112, 0, 30)},
	{"name": "pond", "pos": Vector3(-96, 8, 60), "look": Vector3(-120, 0, 44)},
	{"name": "quarry", "pos": Vector3(-78, 12, -70), "look": Vector3(-100, -1, -92)},
	{"name": "garden", "pos": Vector3(70, 12, -66), "look": Vector3(92, 0, -88)},
	{"name": "inlet", "pos": Vector3(4, 9, -112), "look": Vector3(-19, 0, -137)},
	{"name": "shed", "pos": Vector3(60, 8, -100), "look": Vector3(60, 2, -128)},
	{"name": "tower", "pos": Vector3(10, 4, -8), "look": Vector3(0, 6, -30)},
]
## Follow-camera views along the representative route (dorm door -> path ->
## pond / garden -> return) at the game's camera distance, height and FOV:
## [name, runner position (x, z), heading toward (x, z)].  The same list
## renders V3 and V4 art for matched comparisons.
const ROUTE := [
	["route_1_dorm_door", Vector2(0, 92), Vector2(0, 40)],
	["route_2_quad_path", Vector2(-30, 64), Vector2(-90, 50)],
	["route_3_pond", Vector2(-98, 52), Vector2(-120, 46)],
	["route_4_trees", Vector2(-96, 34), Vector2(-112, 2)],
	["route_5_garden", Vector2(70, -72), Vector2(92, -88)],
	["route_6_fountain", Vector2(14, 38), Vector2(0, 22)],
	["route_7_return", Vector2(0, 50), Vector2(0, 100)],
]
var cam: Camera3D
var i := 0
var wait := 0
var outdir := "user://shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		outdir = args[0]
	QualityPreset.apply(1)
	if args.has("--route"):
		shots.clear()
	for r in ROUTE:
		var p: Vector2 = r[1]
		var to: Vector2 = r[2]
		var dir := (to - p).normalized()
		var target := Vector3(p.x, CampusBuilder.ground_y(CampusLayout.shared(), p.x, p.y) + 1.3, p.y)
		var pitch := 0.24
		var back := Vector3(-dir.x, 0, -dir.y) * 6.2 * cos(pitch)
		shots.append({"name": r[0], "pos": target + back + Vector3(0, 1.55 + 6.2 * sin(pitch) - 1.3, 0), "look": target + Vector3(dir.x, 0, dir.y) * 2.0, "fov": 66.0})
	DirAccess.make_dir_recursive_absolute(outdir)
	var lay := CampusLayout.shared()
	var b := CampusBuilder.new(lay)
	var t0 := Time.get_ticks_msec()
	var waters := b.build_visuals(self, 1)
	print("visuals built in %d ms" % (Time.get_ticks_msec() - t0))
	for id in ["fountain", "pond", "garden"]:
		(waters[id]["mat"] as ShaderMaterial).set_shader_parameter("active", 1.0)
	add_child(EnvFactory.make_environment())
	add_child(EnvFactory.make_moon())
	cam = Camera3D.new()
	cam.fov = 62
	cam.far = 600
	add_child(cam)


func _process(_d: float) -> void:
	if i >= shots.size():
		get_tree().quit()
		return
	var s: Dictionary = shots[i]
	cam.position = s["pos"]
	cam.look_at(s["look"])
	cam.fov = float(s.get("fov", 62.0))
	wait += 1
	if wait >= 4:
		var img := get_viewport().get_texture().get_image()
		img.save_png(outdir.path_join("%s.png" % s["name"]))
		wait = 0
		i += 1
