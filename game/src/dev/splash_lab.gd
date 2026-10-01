extends Node3D
## Development-only splash check (src/dev is excluded from exports).
##   tools/gd.sh --path game --fixed-fps 60 res://src/dev/splash_lab.tscn -- --capture-dir=DIR [--reduced] [--front]
## Three runners meet one pond at the same moment, by walking in, jumping in
## and diving in, through the same presentation path as gameplay
## (CharacterView.apply_state with authoritative SPLASHING state + state_t,
## the match Fx node, the real water shader).  A fourth runner "joins late":
## it is first seen 0.8 s into its splash and must show that beat, not the
## start.  After 1.5 s each runner reappears at its shore exit, as the sim
## resurfaces them.  Saves a frame every 0.1 s and a contact sheet, then quits.

const SURFACE_Y := -0.3
const T_ENTER := 0.7
const LANES := [-2.6, 0.0, 2.6]
const KINDS := [TC.Impact.WALK, TC.Impact.JUMP, TC.Impact.DIVE]
const LATE_X := 5.0

var out_dir := ""
var reduced := false
var front := false   # camera across the pond, facing the runners
var fx: Fx
var water_mat: ShaderMaterial
var views: Array[CharacterView] = []
var late: CharacterView
var cam: Camera3D
var _t := 0.0
var _next_shot := 0.4
var _frames: Array[Image] = []
var _labels: Array = []
var _done := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture-dir="):
			out_dir = a.split("=")[1]
		elif a == "--reduced":
			reduced = true
		elif a == "--front":
			front = true
	if out_dir == "":
		out_dir = OS.get_user_data_dir().path_join("splash_lab")
	DirAccess.make_dir_recursive_absolute(out_dir)
	add_child(EnvFactory.make_environment(1))
	add_child(EnvFactory.make_moon(1))
	fx = Fx.new()
	add_child(fx)
	_build_pond()
	for i in 3:
		var v := _runner(["sky", "bubblegum", "lime"][i], ["tuft", "bob", "curly"][i])
		views.append(v)
	late = _runner("sunny", "buns")
	late.visible = false
	cam = Camera3D.new()
	cam.fov = 46
	add_child(cam)
	cam.current = true
	if front:
		cam.look_at_from_position(Vector3(1.0, 1.5, -4.4), Vector3(1.0, -0.1, 0.8))
	else:
		cam.look_at_from_position(Vector3(1.2, 2.4, 7.2), Vector3(1.2, 0.2, -0.4))


func _build_pond() -> void:
	# 16 x 8 m pond with a grass bank around it (ground at y = 0)
	var water := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(16, 8)
	pm.subdivide_width = 48
	pm.subdivide_depth = 24
	water.mesh = pm
	water_mat = ShaderMaterial.new()
	water_mat.shader = preload("res://assets/shaders/water.gdshader")
	water_mat.set_shader_parameter("shape_half", Vector2(8, 4))
	water_mat.set_shader_parameter("shape_kind", 1.0)
	water_mat.set_shader_parameter("target_color", Color("6fd8cc"))
	water.material_override = water_mat
	water.position = Vector3(1.0, SURFACE_Y, -2.0)
	add_child(water)
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color(0.22, 0.34, 0.24)
	grass.roughness = 0.95
	for b in [[Vector3(1.0, -0.5, 4.5), Vector3(30, 1, 5)], [Vector3(1.0, -0.5, -8.5), Vector3(30, 1, 5)],
			[Vector3(-10.5, -0.5, -2.0), Vector3(7, 1, 8)], [Vector3(12.5, -0.5, -2.0), Vector3(7, 1, 8)]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = b[1]
		mi.mesh = bm
		mi.material_override = grass
		mi.position = b[0]
		add_child(mi)


func _runner(color: String, hair: String) -> CharacterView:
	var v := CharacterView.new()
	v.reduced_motion = reduced
	v.fx = fx
	v.water_at = func(_p: Vector3) -> Dictionary:
		return {"mat": water_mat, "center": Vector2(1.0, -2.0), "color": Color(0.6, 0.85, 1.0)}
	add_child(v)
	var c := Cosmetics.DEFAULT.duplicate()
	c["color"] = color
	c["hair"] = hair
	c["hat"] = "none" if hair != "tuft" else "nightcap"
	v.setup(TC.Role.RUNNER, c, views.size(), "", false, false)
	return v


## Authoritative-looking state for lane i at time t (what the sim would send).
func _lane_rs(i: int, t: float) -> Dictionary:
	var x: float = LANES[i]
	var kind: int = KINDS[i]
	var shore_z := 2.0           # water edge at z = 2 (pond is z -6..2)
	var entry := Vector3(x, SURFACE_Y, 0.6)
	if t < T_ENTER:
		# approach: run toward -Z and meet the water at T_ENTER
		var u := t - T_ENTER                      # negative
		var speed := 5.0 if kind == TC.Impact.WALK else (5.0 if kind == TC.Impact.JUMP else 8.6)
		var pos := entry + Vector3(0, 0, -u * speed)
		pos.y = 0.0 if pos.z > shore_z else SURFACE_Y
		var vel := Vector3(0, 0, -speed)
		var floor_ok := true
		var diving := false
		if kind != TC.Impact.WALK and u > -0.45:
			# airborne for the last 0.45 s: a jump (or a jump then a dive)
			var ta := u + 0.45
			pos.y = 6.4 * ta - 9.5 * ta * ta
			vel.y = 6.4 - 19.0 * ta
			floor_ok = false
			diving = kind == TC.Impact.DIVE and ta > 0.12
		return {"pos": pos, "yaw": 0.0, "vel": vel, "state": TC.PState.ACTIVE, "on_floor": floor_ok, "diving": diving}
	var st := t - T_ENTER
	if st < 1.5:
		return {"pos": entry, "yaw": 0.0, "vel": Vector3.ZERO, "state": TC.PState.SPLASHING, "state_t": st, "impact": kind,
			"on_floor": false}
	# resurfaced at the shore exit, hopping out and jogging away
	var et := st - 1.5
	var exit_p := Vector3(x + 0.6, 0.0, 2.6)
	var hop := maxf(0.0, 3.5 * et - 9.5 * et * et)
	return {"pos": exit_p + Vector3(0, hop, 2.5 * et), "yaw": PI, "vel": Vector3(0, 3.5 - 19.0 * et if hop > 0.0 else 0.0, 2.5),
		"state": TC.PState.ACTIVE, "on_floor": hop <= 0.0}


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	for i in 3:
		views[i].apply_state(_lane_rs(i, _t))
	# late joiner: first seen 0.8 s into its splash (same impact as lane 1)
	var late_st := _t - T_ENTER + 0.8
	if late_st >= 0.8 and late_st < 1.5:
		late.visible = true
		late.apply_state({"pos": Vector3(LATE_X, SURFACE_Y, -1.0), "yaw": 0.0, "vel": Vector3.ZERO, "state": TC.PState.SPLASHING,
			"state_t": late_st, "impact": TC.Impact.JUMP, "on_floor": false})
	elif late_st >= 1.5:
		late.apply_state({"pos": Vector3(LATE_X + 0.6, 0.0, 2.6), "yaw": PI, "vel": Vector3.ZERO, "state": TC.PState.ACTIVE, "on_floor": true})
	if _t >= _next_shot and _t <= 3.4:
		_next_shot += 0.1
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		_frames.append(img)
		var lab := "t=%.1f  (splash %.1f s)  ripples=%d" % [_t, _t - T_ENTER, fx.active_ripples(water_mat)]
		_labels.append(lab)
		img.save_png(out_dir.path_join("splash_%02d.png" % (_frames.size() - 1)))
	if _t > 3.5 and not _done:
		_done = true
		_save_sheet()
		get_tree().quit()


func _save_sheet() -> void:
	var cols := 5
	var w := _frames[0].get_width() / 2
	var h := _frames[0].get_height() / 2
	var rows := int(ceil(_frames.size() / float(cols)))
	var sheet := Image.create(w * cols, h * rows, false, Image.FORMAT_RGBA8)
	for i in _frames.size():
		var f := _frames[i]
		f.convert(Image.FORMAT_RGBA8)
		f.resize(w, h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(f, Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	sheet.save_png(out_dir.path_join("splash_sheet.png"))
	var fl := FileAccess.open(out_dir.path_join("splash_sheet.txt"), FileAccess.WRITE)
	fl.store_string("\n".join(PackedStringArray(_labels)))
	printerr("SPLASHLAB %s frames=%d" % [out_dir, _frames.size()])
