extends RefCounted
## V5 campus art pass: the look changed, the game did not.
##  * every collision shape (type, size, transform, layers), both
##    navigation grids and the gameplay layout data hash to the values
##    recorded on the V4 code (dcebf4e) - see CampusFingerprint;
##  * the decorative dressing is visual only, fresh (the baked copy equals a
##    regeneration from CampusLayout) and keeps out of running corridors,
##    water exits, jump points, pads, doors and the bots' routes;
##  * the staged visual build keeps every step short, and the art kit's
##    meshes, LODs and textures load.
##
## V6 deliberately rebuilt the dorm districts (CampusDorms.DISTRICTS: three
## dorms with common rooms, their yards and approaches).  So the V4/V5
## fingerprints now pin the *V5 campus* (CampusLayout.new(true), built by the
## same code as before the V6 additions), and the V6 campus is proved equal
## to it everywhere outside the districts: collider by collider, nav cell by
## nav cell and layout item by layout item.  The V6 fingerprints are pinned
## too, so any later change shows up here.
var t

## Recorded on V4 (dcebf4e) with CampusFingerprint (525 collision shapes).
const V4_COLLISION := "15d3dc7a8becbc37cd44e17631ee3dbe781bb6ebeedf5112da1298a9ee29b8e9"
const V4_NAV := "79361473a550cd4687026242aa04255c3b1c15df4ee134f70ed5addf5d9b7d4c"
const V4_LAYOUT := "803fc8acbd99fdb948fb2780957abc9380c53da1a1a1c1b8cdf9cfe31dc5924a"
const V4_SHAPES := 525
## Recorded on V6 (CampusDorms.VERSION 1).
const V6_COLLISION := "767e9d7786569cc7f236626247e91fcc6ff8d96e1f4dee779a89f7473fc060bf"
const V6_NAV := "513896383541500563bdced2f6ede5e58154fada7d97c795f2651db77a60aef2"
const V6_LAYOUT := "7ec4416fd8b6f7e63fa498976f51a0916605e6d5d7e7b813113fbcfae9b4cfbc"
const V6_SHAPES := 605


func test_v5_campus_is_reproduced_exactly() -> void:
	var lay := CampusLayout.new(true)
	t.eq(CampusFingerprint.collision_lines(lay).size(), V4_SHAPES, "same number of collision shapes as V4")
	t.eq(CampusFingerprint.collision_hash(lay), V4_COLLISION, "every collision shape (type, size, transform, layer) matches V4")
	t.eq(CampusFingerprint.nav_hash(lay), V4_NAV, "both navigation grids match V4 cell for cell")
	t.eq(CampusFingerprint.layout_hash(lay), V4_LAYOUT, "waters, exits, pads, spawns, doors and every collider list match V4")


## Outside the dorm districts the V6 campus is the V5 campus.
func test_v6_changes_only_inside_the_dorm_districts() -> void:
	var v5 := CampusLayout.new(true)
	var v6 := CampusLayout.new()
	var c5 := CampusFingerprint.collision_lines_outside(v5)
	var c6 := CampusFingerprint.collision_lines_outside(v6)
	t.check(c5.size() > 400, "most of the campus lies outside the districts (%d shapes)" % c5.size())
	t.eq(c6, c5, "every collision shape outside the dorm districts is unchanged")
	var n5 := CampusFingerprint.nav_hash_outside(v5)
	var n6 := CampusFingerprint.nav_hash_outside(v6)
	t.eq(n6[0], n5[0], "both nav grids are unchanged outside the districts (%d cells)" % int(n5[1]))
	var l5 := CampusFingerprint.layout_outside(v5)
	var l6 := CampusFingerprint.layout_outside(v6)
	for k in l5:
		if k == "patrol_spawns":
			continue
		t.eq(l6[k], l5[k], "layout list '%s' unchanged outside the districts" % k)
	# the one deliberate change outside: a third Night Watch spawn at the shed
	var extra: Array = Array(l6["patrol_spawns"]).filter(func(x: String) -> bool: return not (l5["patrol_spawns"] as PackedStringArray).has(x))
	t.eq(extra.size(), 1, "one extra Night Watch spawn (three watchers no longer share a spot)")
	print("[campus] V6: %d collision shapes (V5 %d); outside the districts %d shapes, %d nav cells identical" % [
		CampusFingerprint.collision_lines(v6).size(), V4_SHAPES, c5.size(), int(n5[1])])


func test_v6_fingerprints_recorded() -> void:
	var lay := CampusLayout.new()
	var shapes := CampusFingerprint.collision_lines(lay).size()
	var ch := CampusFingerprint.collision_hash(lay)
	var nh := CampusFingerprint.nav_hash(lay)
	var lh := CampusFingerprint.layout_hash(lay)
	print("[campus] V6 fingerprints: shapes %d collision %s nav %s layout %s" % [shapes, ch, nh, lh])
	t.eq(shapes, V6_SHAPES, "V6 collision shape count")
	t.eq(ch, V6_COLLISION, "V6 collision fingerprint")
	t.eq(nh, V6_NAV, "V6 nav fingerprint")
	t.eq(lh, V6_LAYOUT, "V6 layout fingerprint")


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
	var on_route := 0
	var all_routes := CampusDressing.bot_routes(lay)
	var routes := all_routes.size()
	for path: PackedVector2Array in all_routes:
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


## V6: a finished (or cancelled) build lets the builder go: its step
## closures and helpers referred back to it, so every cold campus build kept
## the builder and its working data (mesh kits, light-field kit, tree and
## decor tables) alive for the rest of the session.
func test_builder_is_freed_after_a_build_and_after_a_cancel() -> void:
	var counts: Array = []
	for i in 3:
		var root := Node3D.new()
		t.add_child(root)
		var b: CampusBuilder = CampusBuilder.new(CampusLayout.shared())
		b.begin_visuals(root, 0)
		var wr: WeakRef = weakref(b)
		if i == 2:
			for k in 40:
				b.step()
			b.abort()
		else:
			while b.step():
				pass
			t.check(b.container != null and b.water_nodes.size() == 6 and b.foliage_material != null, "what the round reads is kept")
		b = null
		root.queue_free()
		await t.get_tree().process_frame
		await t.get_tree().process_frame
		t.check(wr.get_ref() == null, "build %d: the builder is freed" % i)
		counts.append(int(Performance.get_monitor(Performance.OBJECT_COUNT)))
	t.check(counts[2] - counts[0] <= 4, "objects stay flat across builds (%s)" % [counts])
