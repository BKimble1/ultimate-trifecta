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
var cam: Camera3D
var i := 0
var wait := 0
var outdir := "user://shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		outdir = args[0]
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
	wait += 1
	if wait >= 4:
		var img := get_viewport().get_texture().get_image()
		img.save_png(outdir.path_join("%s.png" % s["name"]))
		wait = 0
		i += 1
