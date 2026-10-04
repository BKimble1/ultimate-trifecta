extends Node3D
## Development-only evidence (src/dev: never exported): fixed views of the
## real campus (CampusBuilder visuals, EnvFactory night environment and moon,
## the quality preset given), the same camera positions on any build, so
## before/after stills compare like for like.  Each view is a PNG in --out.
##   xvfb-run tools/gd.sh --path game --resolution 1280x720 res://src/dev/campus_views.tscn -- --out=DIR [--quality=1]
## Desktop llvmpipe rendering: composition and lighting evidence, not
## frame-rate or device evidence.

var out_dir := ""
var quality := 1
var cam: Camera3D


func _views() -> Array:
	var L := CampusLayout.shared()
	var out: Array = []
	var did := CampusDorms.default_id()
	var doors: Array = L.home_doors(did)
	if not doors.is_empty():
		var d: Dictionary = doors[0]
		var p: Vector3 = d["pos"] if d["pos"] is Vector3 else Vector3((d["pos"] as Vector2).x, 0, (d["pos"] as Vector2).y)
		var n: Vector3 = d["normal"] if d["normal"] is Vector3 else Vector3((d["normal"] as Vector2).x, 0, (d["normal"] as Vector2).y)
		out.append(["dorm_entrance", p + n * 8.0 + Vector3(0, 2.3, 0), p + Vector3(0, 1.6, 0)])
		out.append(["dorm_doorway_close", p + n * 3.2 + Vector3(0, 1.5, 0), p + Vector3(0, 1.2, 0)])
	out.append(["quad", Vector3(0, 2.6, 34), Vector3(0, 1.2, 0)])
	for wi in [0, 2, 4]:
		if wi >= L.waters.size():
			continue
		var c: Vector2 = L.waters[wi]["center"]
		var dir := (Vector2(0, 0) - c).normalized() if c.length() > 1.0 else Vector2(0, 1)
		var at := Vector3(c.x, 0.5, c.y)
		out.append(["water_%d" % wi, at + Vector3(dir.x, 0, dir.y) * 13.0 + Vector3(0, 2.6, 0), at])
	if L.waters.size() >= 2:
		var a: Vector2 = L.waters[0]["center"]
		var b: Vector2 = L.waters[1]["center"]
		var m := (a + b) * 0.5
		var f := (b - a).normalized()
		out.append(["chase_route", Vector3(m.x - f.x * 6.0, 2.2, m.y - f.y * 6.0), Vector3(m.x + f.x * 6.0, 1.0, m.y + f.y * 6.0)])
	out.append(["overview", Vector3(0, 45, 150), Vector3(0, 0, 20)])
	return out


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.get_slice("=", 1)
		elif a.begins_with("--quality="):
			quality = int(a.get_slice("=", 1))
	if out_dir == "":
		out_dir = OS.get_user_data_dir().path_join("campus_views")
	DirAccess.make_dir_recursive_absolute(out_dir)
	QualityPreset.apply(quality)
	add_child(EnvFactory.make_environment(quality))
	add_child(EnvFactory.make_moon(quality))
	var root := Node3D.new()
	add_child(root)
	CampusBuilder.new(CampusLayout.shared()).build_visuals(root, quality)
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.far = 600.0
	add_child(cam)
	cam.current = true
	_run.call_deferred()


func _run() -> void:
	for v in _views():
		cam.look_at_from_position(v[1], v[2])
		for i in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(out_dir.path_join("%s.png" % v[0]))
		printerr("VIEW %s" % v[0])
	get_tree().quit()
