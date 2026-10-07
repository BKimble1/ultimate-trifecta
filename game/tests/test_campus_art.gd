extends RefCounted
## The reference-campus rebuild: the look is built from the traced data and
## adds no physics; the gameplay fingerprints (every collision shape, both
## navigation grids, the gameplay layout lists) are deterministic, identical
## however the grid build is staged, and pinned (a deliberate change to the
## data or the colliders updates them here and bumps the campus data
## version used online); the staged visual build keeps every step short;
## the art kit's meshes, LODs and textures load.
var t

## Recorded on the two-maps pass data (game/data/campus on its measured
## ground: terrain, stairs, parked cars; CampusData.campus_hash below).  A
## change here is a gameplay change: re-record deliberately.
const CAMPUS_HASH := "5dea79ef56ff26d3"
const CAMPUS_COLLISION := "8496f719389f54d444d2d7381ba68f5cab0dade6461e960d489d59a130da438b"
const CAMPUS_NAV := "70afc59ca460206f45c9b023fe0b173472fcf2eb4051110de8355a614b43faf3"
const CAMPUS_LAYOUT := "374d5c9e708a77074eb5db2979a88b7a3632dc2648240c775d362851ffc24be7"


func test_fingerprints_are_deterministic() -> void:
	var a := CampusLayout.new()
	var b := CampusLayout.new()
	t.eq(CampusFingerprint.layout_hash(a), CampusFingerprint.layout_hash(b), "the layout is rebuilt identically from the data")
	t.eq(CampusFingerprint.collision_hash(a), CampusFingerprint.collision_hash(b), "the colliders are rebuilt identically")
	var direct := NavGrid.new(a)
	var staged := NavGrid.new(a, true)
	var steps := 0
	while staged.step():
		steps += 1
	t.check(steps > 10, "the nav build is split into slices (%d)" % steps)
	t.eq(CampusFingerprint.nav_hash(a, staged), CampusFingerprint.nav_hash(a, direct), "a staged nav build equals a direct one cell for cell")


func test_campus_fingerprints_recorded() -> void:
	var lay := CampusLayout.new()
	var shapes := CampusFingerprint.collision_lines(lay).size()
	var dh := CampusData.shared().campus_hash
	var ch := CampusFingerprint.collision_hash(lay)
	var nh := CampusFingerprint.nav_hash(lay)
	var lh := CampusFingerprint.layout_hash(lay)
	print("[campus] fingerprints: data %s shapes %d collision %s nav %s layout %s" % [dh, shapes, ch, nh, lh])
	t.eq(dh, CAMPUS_HASH, "campus data hash")
	t.eq(ch, CAMPUS_COLLISION, "collision fingerprint")
	t.eq(nh, CAMPUS_NAV, "nav fingerprint")
	t.eq(lh, CAMPUS_LAYOUT, "layout fingerprint")


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
	t.eq(b.water_nodes.size(), CampusLayout.shared().waters.size(), "every water is drawn")
	root.queue_free()
	await t.get_tree().process_frame


## Every step of the staged visual build is short (this machine's CPU, not
## a phone; the bound is generous for shared CI machines - the measured
## figures are printed and reported in docs/campus/).
func test_staged_build_steps_are_short() -> void:
	var root := Node3D.new()
	t.add_child(root)
	var b := CampusBuilder.new(CampusLayout.shared())
	b.begin_visuals(root, 0)
	var times: Array = []
	var last := 0.0
	var monotonic := true
	var more := true
	# steps that wait on worker jobs (ground chunks) return at once until
	# the jobs are done: bound the loop by time, not by count
	var t_end := Time.get_ticks_msec() + 120000
	while more and Time.get_ticks_msec() < t_end:
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
			# like MatchController: the chunk jobs still on the worker pool are
			# collected once they finish (they hold the builder until then)
			var ids := b.abort()
			for id in ids:
				while not WorkerThreadPool.is_task_completed(id):
					await t.get_tree().process_frame
				WorkerThreadPool.wait_for_task_completion(id)
		else:
			while b.step():
				pass
			t.check(b.container != null and b.water_nodes.size() == CampusLayout.shared().waters.size() and b.foliage_material != null, "what the round reads is kept")
		b = null
		root.queue_free()
		await t.get_tree().process_frame
		await t.get_tree().process_frame
		t.check(wr.get_ref() == null, "build %d: the builder is freed" % i)
		counts.append(int(Performance.get_monitor(Performance.OBJECT_COUNT)))
	t.check(counts[2] - counts[0] <= 4, "objects stay flat across builds (%s)" % [counts])
