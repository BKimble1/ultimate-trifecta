extends Node3D
## Dev tool: renders the campus from several viewpoints to PNGs.
## Usage: godot --path game res://src/dev_shots.tscn -- <outdir> [flags]
##   (no flag)   overview set (`shots` below)
##   --route     the seven follow-camera route views
##   --waters    one view per water (all six marked active)
##   --heroes    extra close views of the landmarks (V5)
##   --q0        Battery Saver preset (default: Standard)
##   --runner    a stand-in runner at each route/water view's focus point
##   --kit       (V5) a lineup of the Blender kit's meshes on a lawn, near
##               and far, without the campus (art iteration)
## Every shot prints a STATS line with the engine's counters for that frame
## (draw calls, primitives, objects; llvmpipe here - relative numbers only),
## and the staged campus build prints its step timings (BUILD line).  The
## camera lists are kept identical between versions for matched comparisons.

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
## renders V3, V4 and V5 art for matched comparisons.
const ROUTE := [
	["route_1_dorm_door", Vector2(0, 92), Vector2(0, 40)],
	["route_2_quad_path", Vector2(-30, 64), Vector2(-90, 50)],
	["route_3_pond", Vector2(-98, 52), Vector2(-120, 46)],
	["route_4_trees", Vector2(-96, 34), Vector2(-112, 2)],
	["route_5_garden", Vector2(70, -72), Vector2(92, -88)],
	["route_6_fountain", Vector2(14, 38), Vector2(0, 22)],
	["route_7_return", Vector2(0, 50), Vector2(0, 100)],
]
## --waters: each of the six waters from a nearby path, same framing as ROUTE
## (camera 5 m above the first point, looking down at the water's centre)
const WATERS := [
	["water_1_fountain", Vector2(0, 41), Vector2(0, 22)],
	["water_2_pond", Vector2(-101, 40), Vector2(-120, 46)],
	["water_3_pool", Vector2(92, 32), Vector2(112, 32)],
	["water_4_quarry", Vector2(-86, -74), Vector2(-100, -90)],
	["water_5_garden", Vector2(77, -73), Vector2(92, -88)],
	["water_6_inlet", Vector2(-26, -117), Vector2(-19, -137)],
]
## --heroes (V5): follow-camera framings at the landmarks and the barren
## areas the V5 art pass dressed: [name, runner (x, z), heading toward (x, z)]
const HEROES := [
	["hero_pond_exit", Vector2(-110, 62), Vector2(-121, 46)],
	["hero_pond_trail", Vector2(-86, 46), Vector2(-106, 46)],
	["hero_fountain", Vector2(-10, 8), Vector2(0, 22)],
	["hero_pool_gate", Vector2(84, 32), Vector2(112, 32)],
	["hero_quarry", Vector2(-100, -66), Vector2(-100, -90)],
	["hero_garden", Vector2(92, -60), Vector2(92, -88)],
	["hero_inlet", Vector2(-20, -104), Vector2(-19, -132)],
	["hero_dorm_west", Vector2(-60, 112), Vector2(-26, 112)],
	["hero_north_lawn", Vector2(0, -50), Vector2(-6, -90)],
	["hero_east_lawn", Vector2(64, 40), Vector2(64, -10)],
]
var cam: Camera3D
var i := 0
var wait := 0
var outdir := "user://shots"
var foliage_mat: ShaderMaterial
var runner: Node3D


func _follow_shot(name: String, p: Vector2, to: Vector2) -> Dictionary:
	var dir := (to - p).normalized()
	var target := Vector3(p.x, CampusBuilder.ground_y(CampusLayout.shared(), p.x, p.y) + 1.3, p.y)
	var pitch := 0.24
	var back := Vector3(-dir.x, 0, -dir.y) * 6.2 * cos(pitch)
	return {"name": name, "pos": target + back + Vector3(0, 1.55 + 6.2 * sin(pitch) - 1.3, 0), "look": target + Vector3(dir.x, 0, dir.y) * 2.0, "fov": 66.0,
		"focus": Vector3(p.x, 0.0, p.y), "yaw": atan2(dir.x, dir.y)}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		outdir = args[0]
	var q := 0 if args.has("--q0") else 1
	QualityPreset.apply(q)
	if args.has("--route") or args.has("--waters") or args.has("--heroes"):
		shots.clear()
	for r in (WATERS if args.has("--waters") else []):
		var sp: Vector2 = r[1]
		var wc: Vector2 = r[2]
		var lay0 := CampusLayout.shared()
		shots.append({"name": r[0], "pos": Vector3(sp.x, CampusBuilder.ground_y(lay0, sp.x, sp.y) + 5.0, sp.y),
			"look": Vector3(wc.x, 0.0, wc.y), "fov": 60.0})
	for r in (ROUTE if args.has("--route") else []):
		shots.append(_follow_shot(r[0], r[1], r[2]))
	for r in (HEROES if args.has("--heroes") else []):
		shots.append(_follow_shot(r[0], r[1], r[2]))
	DirAccess.make_dir_recursive_absolute(outdir)
	if args.has("--kit"):
		_kit_lineup(q)
		return
	var lay := CampusLayout.shared()
	var b := CampusBuilder.new(lay)
	# the same staged build the loading screen runs, one step at a time,
	# timing each step (this machine's CPU, not a phone)
	var t0 := Time.get_ticks_usec()
	b.begin_visuals(self, q)
	var times: Array = []
	var named: Array = []
	var more := true
	while more:
		var nm: String = b.next_step_name() if b.has_method("next_step_name") else str(times.size())
		var s0 := Time.get_ticks_usec()
		more = b.step()
		times.append(float(Time.get_ticks_usec() - s0) / 1000.0)
		named.append([times[-1], nm])
	var total := float(Time.get_ticks_usec() - t0) / 1000.0
	var sorted := times.duplicate()
	sorted.sort()
	sorted.reverse()
	named.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0])
	print("SLOWEST ", named.slice(0, 12).map(func(x: Array) -> String: return "%s %.1f" % [x[1], x[0]]))
	print("BUILD total %.0f ms, %d steps, longest %.1f ms, top5 %s, steps over 16 ms: %d" % [total, times.size(), sorted[0],
		str(sorted.slice(0, 5).map(func(x: float) -> float: return snappedf(x, 0.1))), times.filter(func(x: float) -> bool: return x > 16.0).size()])
	if b.container:
		var by := {}
		for ch in b.container.get_children():
			var pre := String(ch.name).get_slice("_", 0)
			by[pre] = int(by.get(pre, 0)) + 1
		print("NODES ", by)
	var waters: Dictionary = b.water_nodes
	foliage_mat = b.foliage_material
	for id in (waters.keys() if args.has("--waters") else ["fountain", "pond", "garden"]):
		(waters[id]["mat"] as ShaderMaterial).set_shader_parameter("active", 1.0)
	add_child(EnvFactory.make_environment(q))
	add_child(EnvFactory.make_moon(q))
	if args.has("--runner"):
		runner = _make_runner()
		add_child(runner)
	cam = Camera3D.new()
	cam.fov = 62
	cam.far = 600
	add_child(cam)


## --kit: every kit mesh in a row on a plain lawn under the game's night
## lighting; views at follow-camera distance and from further away.
func _kit_lineup(q: int) -> void:
	shots.clear()
	CampusKit.load_kit(q)
	var mat := ShaderMaterial.new()
	mat.shader = CampusBuilder.FOLIAGE_SHADER
	mat.set_shader_parameter("detail_a", CampusBuilder.DETAIL_A)
	mat.set_shader_parameter("detail_b", CampusBuilder.DETAIL_B)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.16, 0.3, 0.18)
	ground.material_override = gm
	add_child(ground)
	var trees := ["oak", "linden", "maple", "birch", "blossom", "fir", "spruce", "pine"]
	for i in trees.size():
		var mi := MeshInstance3D.new()
		mi.mesh = CampusKit.kit_mesh("tree_%s_0" % trees[i])
		mi.material_override = mat
		mi.position = Vector3(-35.0 + float(i) * 10.0, 0, 0)
		add_child(mi)
		for lod in [1, 2]:
			var m2 := MeshInstance3D.new()
			m2.mesh = CampusKit.kit_mesh("tree_%s_%d" % [trees[i], lod])
			m2.material_override = mat
			m2.position = Vector3(-35.0 + float(i) * 10.0, 0, -12.0 * float(lod))
			add_child(m2)
	var small := ["shrub_round_0", "shrub_tall_0", "shrub_bloom_0", "grass_tuft_0", "flowers_0", "reeds_0", "lilies_0", "rock_round_0", "rock_layer_0", "rock_flat_0"]
	for i in small.size():
		var mi2 := MeshInstance3D.new()
		mi2.mesh = CampusKit.kit_mesh(small[i])
		mi2.material_override = mat
		mi2.position = Vector3(-13.5 + float(i) * 3.0, 0, 9.0)
		add_child(mi2)
	add_child(EnvFactory.make_environment(q))
	add_child(EnvFactory.make_moon(q))
	cam = Camera3D.new()
	cam.far = 600
	add_child(cam)
	shots = [
		{"name": "kit_trees_near", "pos": Vector3(-15, 3.5, 13), "look": Vector3(-15, 4, 0), "fov": 66.0},
		{"name": "kit_trees_conifer", "pos": Vector3(15, 3.5, 13), "look": Vector3(15, 4, 0), "fov": 66.0},
		{"name": "kit_row", "pos": Vector3(0, 9, 34), "look": Vector3(0, 3, 0), "fov": 66.0},
		{"name": "kit_small", "pos": Vector3(0, 2.2, 15.5), "look": Vector3(0, 0.3, 9), "fov": 66.0},
		{"name": "kit_lods", "pos": Vector3(-30, 7, 14), "look": Vector3(10, 3, -12), "fov": 66.0},
	]


## --count: rough per-kind tally of geometry inside the view and its
## visibility range (diagnostics for draw-call work; shadows not included).
func _count_visible(shot: String) -> void:
	var planes := cam.get_frustum()
	var by := {}
	var stack: Array = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var gi := n as GeometryInstance3D
		if gi == null or not gi.is_visible_in_tree():
			continue
		var aabb: AABB = gi.global_transform * gi.get_aabb()
		var c := aabb.get_center()
		if gi.visibility_range_end > 0.0 and cam.global_position.distance_to(c) > gi.visibility_range_end:
			continue
		if gi.visibility_range_begin > 0.0 and cam.global_position.distance_to(c) < gi.visibility_range_begin:
			continue
		if gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			continue
		var inside := true
		for pl in planes:
			var pv := Vector3(aabb.end.x if pl.normal.x < 0.0 else aabb.position.x, aabb.end.y if pl.normal.y < 0.0 else aabb.position.y, aabb.end.z if pl.normal.z < 0.0 else aabb.position.z)
			if pl.is_point_over(pv):
				inside = false
				break
		if inside:
			var pre := String(n.name).get_slice("_", 0)
			by[pre] = int(by.get(pre, 0)) + 1
	print("VISIBLE %s %s" % [shot, by])


## A stand-in runner (pajama colours, the character's size) so a view shows
## how a player reads against the scenery.  Not the game's character rig.
func _make_runner() -> Node3D:
	PropKit.init_meshes()
	var n := Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = PropKit.capsule
	body.material_override = PropKit.mat(Color(0.35, 0.55, 1.0), 6.0, Color(0.95, 0.95, 1.0), 0.0, 0.45)
	body.scale = Vector3(0.42, 0.42, 0.42)
	body.position = Vector3(0, 0.82, 0)
	n.add_child(body)
	var head := MeshInstance3D.new()
	head.mesh = PropKit.sphere
	head.material_override = PropKit.mat(Color(0.95, 0.75, 0.6), 0.0, Color.WHITE, 0.0, 0.45)
	head.scale = Vector3(0.42, 0.42, 0.42)
	head.position = Vector3(0, 1.62, 0)
	n.add_child(head)
	return n


func _process(_d: float) -> void:
	if i >= shots.size():
		get_tree().quit()
		return
	var s: Dictionary = shots[i]
	cam.position = s["pos"]
	cam.look_at(s["look"])
	cam.fov = float(s.get("fov", 62.0))
	if foliage_mat:
		if s.has("focus"):
			var f: Vector3 = s["focus"]
			foliage_mat.set_shader_parameter("focus", Vector4(f.x, f.y + 0.85, f.z, 1.25))
		else:
			foliage_mat.set_shader_parameter("focus", Vector4.ZERO)
	if runner:
		runner.visible = s.has("focus")
		if s.has("focus"):
			runner.position = s["focus"]
			runner.rotation.y = float(s.get("yaw", 0.0))
	wait += 1
	if wait == 3 and OS.get_cmdline_user_args().has("--count"):
		_count_visible(s["name"])
	if wait >= 4:
		var img := get_viewport().get_texture().get_image()
		img.save_png(outdir.path_join("%s.png" % s["name"]))
		print("STATS %s draws %d prims %d objs %d" % [s["name"],
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)])
		wait = 0
		i += 1
