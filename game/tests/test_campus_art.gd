extends RefCounted
## V5 campus art pass: the look changed, the game did not.
##  * every collision shape (type, size, transform, layers), both navigation
##    grids and the gameplay layout data hash to the values recorded on the
##    V4 code (dcebf4e) - see CampusFingerprint;
##  * the decorative dressing is visual only, fresh (the baked copy equals a
##    regeneration from CampusLayout) and keeps out of running corridors,
##    water exits, jump points, pads, doors and the bots' routes;
##  * the staged visual build keeps every step short, and the art kit's
##    meshes, LODs and textures load.
var t

## Recorded on V4 (dcebf4e) with CampusFingerprint (525 collision shapes).
const V4_COLLISION := "15d3dc7a8becbc37cd44e17631ee3dbe781bb6ebeedf5112da1298a9ee29b8e9"
const V4_NAV := "79361473a550cd4687026242aa04255c3b1c15df4ee134f70ed5addf5d9b7d4c"
const V4_LAYOUT := "803fc8acbd99fdb948fb2780957abc9380c53da1a1a1c1b8cdf9cfe31dc5924a"
const V4_SHAPES := 525


func test_collision_nav_and_layout_unchanged_from_v4() -> void:
	var lay := CampusLayout.new()
	t.eq(CampusFingerprint.collision_lines(lay).size(), V4_SHAPES, "same number of collision shapes as V4")
	t.eq(CampusFingerprint.collision_hash(lay), V4_COLLISION, "every collision shape (type, size, transform, layer) matches V4")
	t.eq(CampusFingerprint.nav_hash(lay), V4_NAV, "both navigation grids match V4 cell for cell")
	t.eq(CampusFingerprint.layout_hash(lay), V4_LAYOUT, "waters, exits, pads, spawns, doors and every collider list match V4")


func test_visual_build_adds_no_physics() -> void:
	var root := Node3D.new()
	t.add_child(root)
	var b := CampusBuilder.new(CampusLayout.shared())
	b.build_visuals(root, 1)
	var bodies := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is CollisionObject3D or n is CollisionShape3D:
			bodies += 1
	t.eq(bodies, 0, "the campus look has no collision objects of its own")
	t.eq(b.water_nodes.size(), 6, "six water landmarks")
	root.queue_free()
	await t.get_tree().process_frame


func test_dressing_is_fresh_and_visual_only() -> void:
	var baked := CampusDressing.load_baked()
	t.check(not baked.is_empty(), "the baked dressing ships with the game")
	var fresh := CampusDressing.new(CampusLayout.shared()).generate()
	var same := baked.size() == fresh.size()
	for k in fresh:
		same = same and baked.has(k) and (baked[k] as PackedFloat32Array) == (fresh[k] as PackedFloat32Array)
	t.check(same, "the baked dressing equals a regeneration from CampusLayout (run tools/campus/build.sh if not)")
	print("[campus] dressing: %d pieces" % CampusDressing.count(fresh))


func _items(d: Dictionary) -> Array:
	var out: Array = []
	for kind in d:
		var a: PackedFloat32Array = d[kind]
		for i in range(0, a.size(), CampusDressing.STRIDE):
			out.append([kind, Vector2(a[i], a[i + 2]), float(CampusDressing.RADIUS[kind]) * a[i + 4]])
	return out


func test_dressing_keeps_out_of_corridors_and_water_exits() -> void:
	var lay := CampusLayout.shared()
	var items := _items(CampusDressing.load_baked())
	var bad_corridor := 0
	var bad_mid := 0
	var bad_exit := 0
	var forest_inside := 0
	for it in items:
		var kind: String = it[0]
		var p: Vector2 = it[1]
		var r: float = it[2]
		if kind == CampusDressing.FOREST:
			if CampusLayout.BOUNDS.grow(2.0).has_point(p):
				forest_inside += 1
			continue
		var bank := kind in ["reeds", "rock_flat", "lilies"]
		if not CampusDressing.clear_of_gameplay(lay, p, r if kind != "lilies" else 0.0, bank):
			bad_corridor += 1
		if kind in CampusDressing.MID and kind != "reeds" and not CampusDressing.hugging_obstacle(lay, p):
			bad_mid += 1
		for w in lay.waters:
			for e in w["exits"]:
				if p.distance_to(Vector2(e.x, e.z)) < 2.5 + r * 0.5:
					bad_exit += 1
			for j in w["jump_points"]:
				if p.distance_to(j) < 2.0 + r * 0.5:
					bad_exit += 1
	t.eq(bad_corridor, 0, "no dressing on paths, roads, plazas, pads, spawns, doors, gates, lamps or benches")
	t.eq(bad_mid, 0, "every shrub or boulder hugs an existing obstacle (never alone in open ground)")
	t.eq(bad_exit, 0, "water exits and jump points stay clear")
	t.eq(forest_inside, 0, "the forest beyond the hedges stays beyond them")


## The bots' actual routes (nav paths dorm -> each water's exits -> dorm):
## no shrub, reed bed or boulder is centred on a route line, and nothing but
## flat lilies lies on the swim lines from an exit to the water's centre.
func test_bot_routes_and_swim_lines_are_clear() -> void:
	var lay := CampusLayout.shared()
	var nav := NavGrid.shared(lay)
	var items := _items(CampusDressing.load_baked()).filter(func(it: Array) -> bool: return String(it[0]) in CampusDressing.MID)
	var start: Vector2 = lay.runner_spawns[0]
	var on_route := 0
	var routes := 0
	for w in lay.waters:
		for e in w["exits"]:
			var ep := Vector2(e.x, e.z)
			for pair in [[start, ep], [ep, lay.dorm_doors[0]["pos"] + Vector2(0, -2.5)]]:
				var path := nav.find_path(pair[0], pair[1])
				if path.size() < 2:
					continue
				routes += 1
				for it in items:
					var p: Vector2 = it[1]
					for i in path.size() - 1:
						if CampusLayout._dist_to_segment(p, path[i], path[i + 1]) < 0.35:
							on_route += 1
							break
	t.check(routes >= 30, "bot routes computed (%d)" % routes)
	t.eq(on_route, 0, "no shrub, reed bed or boulder sits on a bot route")
	var swim := 0
	for it in items:
		var p2: Vector2 = it[1]
		for w in lay.waters:
			for e in w["exits"]:
				if CampusLayout._dist_to_segment(p2, Vector2(e.x, e.z), w["center"]) < 0.6:
					swim += 1
	t.eq(swim, 0, "swim lines from each exit to the water's centre are clear")


## Every step of the staged visual build is short (this machine's CPU, not
## a phone; the bound is generous for shared CI machines - the measured
## figures are printed and reported in docs/v5/campus_notes.md).
func test_staged_build_steps_are_short() -> void:
	var root := Node3D.new()
	t.add_child(root)
	var b := CampusBuilder.new(CampusLayout.shared())
	b.begin_visuals(root, 0)
	var times: Array = []
	var last := 0.0
	var monotonic := true
	var more := true
	var guard := 0
	while more and guard < 200000:
		guard += 1
		var nm := b.next_step_name()
		var s0 := Time.get_ticks_usec()
		more = b.step()
		times.append([float(Time.get_ticks_usec() - s0) / 1000.0, nm])
		monotonic = monotonic and b.progress() >= last
		last = b.progress()
	times.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0])
	print("[campus] slowest build steps (ms): %s" % str(times.slice(0, 6).map(func(x: Array) -> String: return "%s %.1f" % [x[1], x[0]])))
	t.check(not more, "the build finishes")
	t.check(monotonic, "progress only moves forward")
	t.check(b.step_names.size() > 100, "the build is split into many short steps (%d)" % b.step_names.size())
	t.check(float(times[0][0]) < 45.0, "no build step is a long freeze (longest %.1f ms: %s)" % [times[0][0], times[0][1]])
	root.queue_free()
	await t.get_tree().process_frame


func test_art_kit_loads_with_lods() -> void:
	CampusKit.load_kit()
	for sp in CampusKit.BROAD + CampusKit.CONIFER:
		for lod in 3:
			t.check(CampusKit.has_mesh("tree_%s_%d" % [sp, lod]), "tree %s LOD %d" % [sp, lod])
		var m := CampusKit.lod_mesh("tree_" + sp) as ArrayMesh
		var lod0 := CampusKit.kit_mesh("tree_%s_0" % sp) as ArrayMesh
		t.check(m != null and m.surface_get_array_index_len(0) == lod0.surface_get_array_index_len(0), "%s: LOD 0 drawn at full detail" % sp)
		t.check(lod0.surface_get_array_index_len(0) / 3 <= 1200, "%s: near LOD within budget" % sp)
		t.check((CampusKit.kit_mesh("tree_%s_2" % sp) as ArrayMesh).surface_get_array_index_len(0) / 3 <= 120, "%s: far LOD / shadow proxy is light" % sp)
	for kind in CampusKit.DECOR_MESH:
		t.check(CampusKit.lod_mesh(CampusKit.DECOR_MESH[kind]) != null, "dressing mesh %s" % kind)
	for tex in [CampusBuilder.DETAIL_A, CampusBuilder.DETAIL_B]:
		t.check(tex != null and tex.get_width() == 512, "detail texture loads")
		var img: Image = tex.get_image()
		t.check(img != null and img.has_mipmaps(), "detail texture has mipmaps")


func test_battery_saver_is_lighter() -> void:
	var counts := []
	for q in [1, 0]:
		var root := Node3D.new()
		t.add_child(root)
		var b := CampusBuilder.new(CampusLayout.shared())
		b.build_visuals(root, q)
		var casters := 0
		var proxies := 0
		for n in b.container.get_children():
			var gi := n as GeometryInstance3D
			if gi == null:
				continue
			if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				casters += 1
			if String(n.name).begins_with("TreeShadows"):
				proxies += 1
			if String(n.name).begins_with("Decor"):
				t.check(gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "dressing never casts shadows")
		counts.append([casters, proxies])
		root.queue_free()
		await t.get_tree().process_frame
	t.check(counts[0][1] > 0, "Standard: trees cast through shadow proxies")
	t.eq(counts[1][0], 0, "Battery Saver: the campus casts no shadows (characters still do)")
