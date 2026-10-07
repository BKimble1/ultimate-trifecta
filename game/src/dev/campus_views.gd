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
## --tour: a walker's-eye camera tour (no character) along the bots' foot
## paths between TOUR's waypoints, on the ground and up and down stairs;
## record it with --write-movie and --fixed-fps (tools/capture_campus_tour.sh).
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
var tour := false
var tour_speed := 7.5
## The tour's waypoints per map: [name, x, z] (neutral names; the route
## between them is the bots' foot path, so it uses the real doors, stairs
## and passages).
const TOUR := {
	"reference_campus": [
		["west hall common room", 82.0, 139.0], ["west hall front door", 84.5, 131.0], ["chapel walk", 92.0, 28.0],
		["chapel atrium", 75.0, 21.0], ["chapel garden", 60.0, 30.0], ["library", 120.0, -96.0],
		["bell tower gap", 146.8, -126.0], ["bell tower gap (through)", 146.8, -138.0], ["north hall walk", 336.0, -339.0],
		["north hall portico (up the stair)", 317.0, -339.2], ["north hall walk again (down)", 337.0, -330.0],
		["bridge pond shore exit", -14.4, 216.4], ["bridge pond footbridge (east end)", -18.0, 226.0],
		["bridge pond footbridge (west end)", -34.0, 217.0], ["lake shore", -86.0, 300.0],
		["lake fishing dock", -91.5, 318.0], ["lake shore exit", -246.5, 258.7],
		["woods path (south strip)", -300.0, 30.0], ["woods path (out)", -250.0, 26.0],
		["west hall front door (home)", 84.5, 131.0], ["west hall common room (home)", 82.0, 139.0]],
	"classic": [["puddlesworth hall", 0.0, 104.0], ["quad", 0.0, 40.0], ["fountain", 0.0, 0.0], ["clock tower", 0.0, -66.0], ["pond", -100.0, -80.0], ["back home", 0.0, 104.0]],
}
var _tour_pts := PackedVector2Array()
var _tour_names: Array = []
var _tour_d := 0.0
var _tour_len := 0.0
var _tour_yaw := 0.0
var _tour_layout: CampusLayout
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
		return _grounded(extra) if relative else extra
	return _grounded(_default_views()) if not CampusMaps.layout(map_id).terrain.is_empty() else _default_views()


## Heights above the ground (or a stair) where the camera and its target
## stand: on a map with terrain the same view keeps its height over the
## ground (the flat map's absolute heights are heights over its y = 0).
var relative := false


func _grounded(views: Array) -> Array:
	var L := CampusMaps.layout(map_id)
	var out: Array = []
	for v in views:
		var w: Array = (v as Array).duplicate()
		var c: Vector3 = w[1]
		var t: Vector3 = w[2]
		w[1] = Vector3(c.x, c.y + maxf(CampusBuilder.grid_y(L, c.x, c.z), L.stair_y(Vector2(c.x, c.z))), c.z)
		w[2] = Vector3(t.x, t.y + maxf(CampusBuilder.grid_y(L, t.x, t.z), L.stair_y(Vector2(t.x, t.z))), t.z)
		out.append(w)
	return out


func _default_views() -> Array:
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
		elif a == "--relative":
			relative = true
		elif a.begins_with("--map="):
			map_id = CampusMaps.sanitize(a.get_slice("=", 1))
		elif a == "--preview":
			preview = true
		elif a == "--tour":
			tour = true
		elif a.begins_with("--tour-speed="):
			tour_speed = float(a.get_slice("=", 1))
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
	if tour:
		_tour_setup()
		return
	_run.call_deferred()


## The tour's route: the bots' foot path between each pair of waypoints.
func _tour_setup() -> void:
	_tour_layout = CampusMaps.layout(map_id)
	var nav := NavGrid.shared(_tour_layout)
	var wps: Array = TOUR.get(map_id, [])
	for i in wps.size():
		var b := Vector2(float(wps[i][1]), float(wps[i][2]))
		if i == 0:
			_tour_pts.append(b)
			_tour_names.append([0.0, String(wps[i][0])])
			continue
		var a := _tour_pts[_tour_pts.size() - 1]
		var seg := nav.find_path(a, b, false, true)
		if seg.size() < 2:
			seg = PackedVector2Array([a, b])
		for j in range(1, seg.size()):
			_tour_pts.append(seg[j])
		if seg[seg.size() - 1].distance_to(b) > 0.5:
			_tour_pts.append(b)
		var length := 0.0
		for j in _tour_pts.size() - 1:
			length += _tour_pts[j].distance_to(_tour_pts[j + 1])
		_tour_names.append([length, String(wps[i][0])])
	for j in _tour_pts.size() - 1:
		_tour_len += _tour_pts[j].distance_to(_tour_pts[j + 1])
	printerr("TOUR %s: %d points, %.0f m, %.0f s at %.1f m/s" % [map_id, _tour_pts.size(), _tour_len, _tour_len / tour_speed, tour_speed])
	var env: Environment = world_env.get("environment") if world_env != null else null
	if env != null:
		env.fog_enabled = true
	_tour_yaw = _tour_heading(0.0)


func _tour_at(d: float) -> Vector2:
	var left := clampf(d, 0.0, _tour_len)
	for j in _tour_pts.size() - 1:
		var l := _tour_pts[j].distance_to(_tour_pts[j + 1])
		if left <= l:
			return _tour_pts[j].lerp(_tour_pts[j + 1], left / maxf(l, 0.001))
		left -= l
	return _tour_pts[_tour_pts.size() - 1]


func _tour_heading(d: float) -> float:
	var a := _tour_at(d)
	var b := _tour_at(d + 7.0)
	if b.distance_to(a) < 0.1:
		return _tour_yaw
	return atan2(-(b - a).x, -(b - a).y)


## Where a walker stands at p: the ground, or a stair's walking line.
func _tour_floor(p: Vector2) -> float:
	return maxf(CampusBuilder.grid_y(_tour_layout, p.x, p.y), _tour_layout.stair_y(p))


var _tour_named := 0
var _tour_eye := INF


func _process(delta: float) -> void:
	if not tour or _tour_pts.size() < 2:
		return
	_tour_d += tour_speed * delta
	if _tour_d >= _tour_len + 2.0:
		printerr("TOUR done")
		get_tree().quit()
		return
	var p := _tour_at(_tour_d)
	# the heading turns smoothly (a walker looks where they're going)
	var want := _tour_heading(_tour_d)
	_tour_yaw = lerp_angle(_tour_yaw, want, clampf(delta * 2.2, 0.0, 1.0))
	var eye := _tour_floor(p) + 1.65
	_tour_eye = eye if _tour_eye == INF else lerpf(_tour_eye, eye, clampf(delta * 6.0, 0.0, 1.0))
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.fov = 64.0
	cam.global_position = Vector3(p.x, _tour_eye, p.y)
	cam.rotation = Vector3(-0.06, _tour_yaw, 0.0)
	while _tour_named < _tour_names.size() and _tour_d >= float(_tour_names[_tour_named][0]):
		printerr("TOUR %.1f s: %s" % [_tour_d / tour_speed, String(_tour_names[_tour_named][1])])
		_tour_named += 1


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
		# the camera, for matched captures (metres, the map's frame)
		printerr("CAMERA %s pos %s target %s fov %.1f %s" % [v[0], str((v[1] as Vector3).snapped(Vector3(0.01, 0.01, 0.01))),
			str((v[2] as Vector3).snapped(Vector3(0.01, 0.01, 0.01))), cam.fov, "vertical" if cam.keep_aspect == Camera3D.KEEP_HEIGHT else "horizontal"])
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
