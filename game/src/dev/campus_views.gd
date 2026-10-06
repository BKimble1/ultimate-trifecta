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
var world_env: Node


var extra: Array = []      # --view=name:x,y,z:tx,ty,tz (repeatable)
var only_extra := false


func _views() -> Array:
	if only_extra:
		return extra
	var L := CampusLayout.shared()
	var out: Array = []
	# each start dorm's doors, from outside
	for did in CampusDorms.ids():
		var doors: Array = L.home_doors(did)
		for di in doors.size():
			var d: Dictionary = doors[di]
			var p := Vector3((d["pos"] as Vector2).x, 0, (d["pos"] as Vector2).y)
			var n := Vector3((d["normal"] as Vector2).x, 0, (d["normal"] as Vector2).y)
			out.append(["dorm_%s_%s" % [did, d["id"]], p + n * 9.0 + Vector3(0, 2.3, 0), p + Vector3(0, 1.8, 0)])
		var g := CampusDorms.geometry(did)
		if not g.is_empty() and not (g["pads"] as Array).is_empty():
			var pad: Vector2 = g["pads"][0]["pos"]
			var dr: Dictionary = doors[0]
			var lp: Vector2 = dr["line_p"]
			var back := (pad - lp).normalized()
			out.append(["dorm_%s_inside" % did, Vector3(pad.x + back.x * 3.0, 1.8, pad.y + back.y * 3.0), Vector3(lp.x, 1.4, lp.y)])
	# landmarks: from the south-west at a walker's height and from above
	for bd in L.buildings:
		if bd.get("landmark") == null or String(bd["landmark"]) == "":
			continue
		var c := CampusData.centroid(bd["poly"])
		var r := sqrt(absf(CampusData.area(bd["poly"]))) * 0.5 + 6.0
		out.append(["lm_%s" % bd["id"], Vector3(c.x - r * 1.6, 2.0, c.y + r * 1.6), Vector3(c.x, minf(float(bd["h"]) * 0.45, 9.0), c.y)])
		out.append(["lm_%s_high" % bd["id"], Vector3(c.x - r * 2.2, r * 1.6 + 8.0, c.y + r * 2.2), Vector3(c.x, 2.0, c.y)])
	for wi in L.waters.size():
		var w: Dictionary = L.waters[wi]
		var c2: Vector2 = w["center"]
		var rr := maxf(6.0, (w["rect"] as Rect2).size.length() * 0.5)
		out.append(["water_%s" % w["id"], Vector3(c2.x + rr * 0.7, 2.6 + rr * 0.15, c2.y + rr * 1.2), Vector3(c2.x, 0.3, c2.y)])
	var cc := CampusLayout.BOUNDS.get_center()
	out.append(["overview", Vector3(cc.x, 260.0, cc.y + 420.0), Vector3(cc.x, 0, cc.y)])
	out.append_array(extra)
	return out


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.get_slice("=", 1)
		elif a.begins_with("--quality="):
			quality = int(a.get_slice("=", 1))
		elif a.begins_with("--view="):
			var parts := a.get_slice("=", 1).split(":")
			var p0 := parts[1].split_floats(",")
			var p1 := parts[2].split_floats(",")
			extra.append([parts[0], Vector3(p0[0], p0[1], p0[2]), Vector3(p1[0], p1[1], p1[2])])
		elif a == "--only-views":
			only_extra = true
	if out_dir == "":
		out_dir = OS.get_user_data_dir().path_join("campus_views")
	DirAccess.make_dir_recursive_absolute(out_dir)
	QualityPreset.apply(quality)
	world_env = EnvFactory.make_environment(quality)
	add_child(world_env)
	add_child(EnvFactory.make_moon(quality))
	var root := Node3D.new()
	add_child(root)
	CampusBuilder.new(CampusLayout.shared()).build_visuals(root, quality)
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.far = 1400.0
	add_child(cam)
	cam.current = true
	_run.call_deferred()


func _run() -> void:
	for v in _views():
		# overviews look across the whole campus: no distance fog for them
		var env: Environment = world_env.get("environment") if world_env != null else null
		if env != null:
			env.fog_enabled = not String(v[0]).begins_with("overview")
		cam.look_at_from_position(v[1], v[2])
		for i in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(out_dir.path_join("%s.png" % v[0]))
		printerr("VIEW %s" % v[0])
	get_tree().quit()
