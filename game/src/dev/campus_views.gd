extends Node3D
## Development-only evidence (src/dev: never exported): fixed views of a
## map (its own look: CampusBuilder for the reference campus, ClassicBuilder
## for Moonbrook College; EnvFactory night environment and moon, the quality
## preset given), the same camera positions on any build, so before/after
## stills compare like for like.  Each view is a PNG in --out.
##   xvfb-run tools/gd.sh --path game --resolution 1280x720 res://src/dev/campus_views.tscn -- --out=DIR [--quality=1]
##     [--map=<id>] [--view=name:x,y,z:tx,ty,tz[:hfov] ...] [--only-views] [--preview]
## --preview: only the map chooser's preview (PREVIEW framing per map, a
## soft fill light so buildings, paths, trees and water read at card size).
## Desktop llvmpipe rendering: composition and lighting evidence, not
## frame-rate or device evidence.

var out_dir := ""
var quality := 1
var cam: Camera3D
var world_env: Node


var extra: Array = []      # --view=name:x,y,z:tx,ty,tz (repeatable)
var only_extra := false
var map_id := CampusMaps.DEFAULT_ID
var preview := false
## The chooser's preview per map: an oblique aerial from the south that
## shows the whole of the map's distinct layout.  [camera, target, vfov]
const PREVIEW := {
	"classic": [Vector3(0.0, 215.0, 255.0), Vector3(0.0, 0.0, -8.0), 50.0],
	"reference_campus": [Vector3(-70.0, 470.0, 640.0), Vector3(-90.0, 0.0, -70.0), 52.0],
}


func _views() -> Array:
	if preview:
		var pv: Array = PREVIEW[map_id]
		return [["preview_" + map_id, pv[0], pv[1], -float(pv[2])]]
	if only_extra:
		return extra
	var L := CampusMaps.layout(map_id)
	var out: Array = []
	# each start dorm's doors, from outside
	for did in CampusDorms.ids(map_id):
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
	var cc := L.bounds.get_center()
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
			# --view=name:x,y,z:tx,ty,tz[:hfov] (hfov: horizontal degrees, to
			# match a reference photo's framing)
			var parts := a.get_slice("=", 1).split(":")
			var p0 := parts[1].split_floats(",")
			var p1 := parts[2].split_floats(",")
			var v := [parts[0], Vector3(p0[0], p0[1], p0[2]), Vector3(p1[0], p1[1], p1[2])]
			if parts.size() > 3:
				v.append(float(parts[3]))
			extra.append(v)
		elif a == "--only-views":
			only_extra = true
		elif a.begins_with("--map="):
			map_id = CampusMaps.sanitize(a.get_slice("=", 1))
		elif a == "--preview":
			preview = true
	if out_dir == "":
		out_dir = OS.get_user_data_dir().path_join("campus_views")
	DirAccess.make_dir_recursive_absolute(out_dir)
	QualityPreset.apply(quality)
	world_env = EnvFactory.make_environment(quality)
	add_child(world_env)
	add_child(EnvFactory.make_moon(quality))
	var root := Node3D.new()
	add_child(root)
	if String(CampusMaps.def(map_id).get("look", "campus")) == "classic":
		ClassicBuilder.new(ClassicLayout.shared()).build_visuals(root, quality)
	else:
		CampusBuilder.new(CampusMaps.layout(map_id)).build_visuals(root, quality)
	if preview:
		# a soft fill from the south-west: the night look, readable at card size
		var fill := DirectionalLight3D.new()
		fill.light_color = Color(0.78, 0.84, 1.0)
		fill.light_energy = 0.55
		fill.shadow_enabled = false
		fill.rotation_degrees = Vector3(-38.0, -150.0, 0.0)
		add_child(fill)
		var env2: Environment = world_env.get("environment") if world_env != null else null
		if env2 != null:
			env2.ambient_light_energy = env2.ambient_light_energy * 1.6
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
		var over := String(v[0]).begins_with("overview")
		# (and the map previews)
		var over2 := over or String(v[0]).begins_with("preview")
		if env != null:
			env.fog_enabled = not over2
		# and nothing culled by its play-time view distance (chunks fade out a
		# few hundred metres away; an overview stands farther off than that)
		_set_ranges(self, over2)
		if v.size() > 3 and float(v[3]) < 0.0:
			# a vertical field of view (previews)
			cam.keep_aspect = Camera3D.KEEP_HEIGHT
			cam.fov = -float(v[3])
		elif v.size() > 3:
			cam.keep_aspect = Camera3D.KEEP_WIDTH
			cam.fov = float(v[3])
		else:
			cam.keep_aspect = Camera3D.KEEP_HEIGHT
			cam.fov = 62.0
		cam.look_at_from_position(v[1], v[2])
		for i in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(out_dir.path_join("%s.png" % v[0]))
		# what the frame drew (software rendering: counts, not timings)
		printerr("VIEW %s draws %d objects %d primitives %d" % [v[0],
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	get_tree().quit()


var _ranges := {}     # GeometryInstance3D -> its own visibility_range_end


func _set_ranges(n: Node, unlimited: bool) -> void:
	for c in n.get_children():
		var gi := c as GeometryInstance3D
		if gi != null:
			if not _ranges.has(gi):
				_ranges[gi] = gi.visibility_range_end
			gi.visibility_range_end = 0.0 if unlimited else float(_ranges[gi])
		_set_ranges(c, unlimited)
