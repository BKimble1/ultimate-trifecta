extends RefCounted
## V4 loading pipeline: the round is prepared in bounded steps under the
## loading screen, the campus look is reused between rounds, and ten rounds
## in a row leave nothing behind.
var t


func _offline() -> NetSession:
	var s := NetSession.new()
	t.add_child(s)
	s.start_offline("u-load", "Tester", {}, "runner")
	return s


func _start(s: NetSession, staged: bool = true) -> MatchController:
	var info := {}
	var grab := func(i: Dictionary) -> void: info.merge(i, true)
	s.match_starting.connect(grab, CONNECT_ONE_SHOT)
	if s.phase != TC.Phase.LOBBY:
		s.host_return_to_lobby()
	s.host_start_match(4242)
	var mc := MatchController.new()
	mc.setup(s, info, {"quality": 0, "staged": staged})
	t.add_child(mc)
	return mc


func _end(mc: MatchController) -> void:
	mc.release_campus()
	mc.queue_free()


func test_round_is_prepared_in_bounded_steps() -> void:
	MatchController.drop_campus_cache()
	var s := _offline()
	var mc := _start(s)
	t.check(not mc.prepared, "nothing heavy happens in _ready")
	t.check(mc.sim == null, "the sim waits for its step")
	var frames := 0
	while not mc.prepared and frames < 400:
		await t.get_tree().process_frame
		frames += 1
	t.check(mc.prepared, "prepared")
	t.check(mc.prep_frames >= 4, "spread over several frames (%d)" % mc.prep_frames)
	# a single step can overrun the budget; none may be a long freeze.  The
	# figure here is this test machine's CPU, not a phone measurement.
	t.check(mc.prep_max_ms < 120.0, "no long freeze while loading (%.1f ms)" % mc.prep_max_ms)
	t.check(mc.sim != null and mc.views.size() == mc.roster.size(), "sim and every character ready")
	t.check(mc.round_live(), "practice goes live once prepared")
	t.check(mc.water_nodes.size() == 6, "six waters")
	_end(mc)
	await t.get_tree().process_frame
	s.queue_free()


func test_campus_look_is_reused_between_rounds() -> void:
	MatchController.drop_campus_cache()
	var s := _offline()
	var mc := _start(s, false)
	var campus := mc._campus
	t.check(campus != null and campus.is_inside_tree(), "campus built")
	var any_water: ShaderMaterial = (mc.water_nodes.values()[0] as Dictionary)["mat"]
	any_water.set_shader_parameter("stamped", 1.0)
	_end(mc)
	await t.get_tree().process_frame
	t.check(MatchController.campus_cached(), "kept after the round")
	t.check(is_instance_valid(campus) and not campus.is_inside_tree(), "kept out of the tree between rounds")
	var mc2 := _start(s, false)
	t.check(mc2._campus == campus, "the next round reuses the same campus")
	t.eq(float(any_water.get_shader_parameter("stamped")), 0.0, "per-round water state starts clean")
	t.check(not MatchController.campus_cached(), "in use, not double-held")
	_end(mc2)
	await t.get_tree().process_frame
	MatchController.drop_campus_cache()
	t.check(not is_instance_valid(campus), "dropping the cache frees it")
	s.queue_free()


func test_ten_rounds_leave_nothing_behind() -> void:
	MatchController.drop_campus_cache()
	var s := _offline()
	var counts: Array = []
	var conns: Array = []
	for i in 10:
		var mc := _start(s, false)
		for f in 3:
			await t.get_tree().physics_frame
		_end(mc)
		await t.get_tree().process_frame
		await t.get_tree().process_frame
		counts.append([Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)])
		var c := 0
		for sig in s.get_signal_list():
			c += s.get_signal_connection_list(String(sig["name"])).size()
		conns.append(c)
	print("[load] nodes/objects/orphans after rounds 2, 10: %s  %s; session connections %s" % [counts[1], counts[9], conns])
	t.eq(int(counts[9][0]), int(counts[1][0]), "scene nodes do not grow across rounds")
	t.check(int(counts[9][1]) - int(counts[1][1]) <= 16, "objects do not keep growing (%d -> %d)" % [counts[1][1], counts[9][1]])
	t.eq(int(counts[9][2]), int(counts[1][2]), "orphan nodes stay flat (the kept campus only)")
	t.eq(int(conns[9]), int(conns[1]), "no signal connections left on the session")
	MatchController.drop_campus_cache()
	s.queue_free()


# --- the loading screen's character loop (owner's clip) ---

func test_loading_loop_assets_agree() -> void:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/loading/run_loop.json"))
	var fw := int(meta["frame_w"])
	var fh := int(meta["frame_h"])
	t.eq(int(meta["frames"]), LoadingScreen.LOOP_FRAMES, "frame count matches the builder")
	t.eq(Vector2(float(meta["cols"]), float(meta["rows"])), LoadingScreen.LOOP_GRID, "atlas grid matches")
	t.eq(float(meta["fps"]), LoadingScreen.LOOP_FPS, "frame rate matches the source clip")
	t.check(is_equal_approx(float(fw) / float(fh), LoadingScreen.LOOP_ASPECT), "picture aspect matches the frames")
	t.eq(meta["side_stops"], LoadingScreen.LOOP_SIDES, "the backdrop continues the frame's own side colours")
	var g := LoadingScreen.LOOP_GRID
	t.check(LoadingScreen.LOOP_FRAMES <= int(g.x * g.y) and LoadingScreen.LOOP_FRAMES > int(g.x * (g.y - 1.0)), "every frame has a cell, no empty row")
	var atlas := load(LoadingScreen.LOOP_ATLAS) as Texture2D
	var still := load(LoadingScreen.LOOP_STILL) as Texture2D
	t.check(atlas != null and still != null, "atlas and still are bundled")
	if atlas == null or still == null:
		return
	t.eq(atlas.get_size(), Vector2(fw * g.x, fh * g.y), "atlas is the grid of whole frames (never scaled)")
	t.eq(still.get_size(), Vector2(fw, fh), "the still is one frame at full size")


func _loading_screen(s: NetSession, mc: MatchController) -> LoadingScreen:
	var ls := LoadingScreen.new()
	ls.session = s
	ls.match_ctrl = mc
	t.add_child(ls)
	return ls


func test_loading_screen_still_loop_progress_and_release() -> void:
	MatchController.drop_campus_cache()
	var s := _offline()
	var mc := _start(s)
	var ls := _loading_screen(s, mc)
	var mat := ls.picture.material as ShaderMaterial
	t.check(mat.get_shader_parameter("frames") == ls._still and ls._still != null, "the still shows at once")
	t.eq(mat.get_shader_parameter("grid"), Vector2.ONE, "as a single frame")
	t.check(ls._atlas_pending, "the loop loads in the background")
	var closed := [false]
	ls.done.connect(func() -> void: closed[0] = true)
	var last := 0.0
	var steady := true
	var ahead := false
	var loop_seen := false
	var first_frame := -2.0
	var frames := 0
	while not closed[0] and frames < 900:
		await t.get_tree().process_frame
		frames += 1
		if not is_instance_valid(mc):
			break
		var p := mc.prep_progress()
		steady = steady and p >= last - 0.0001
		last = p
		ahead = ahead or ls.bar.shown > p + 0.0001
		if ls.loop_running() and not loop_seen:
			loop_seen = true
			first_frame = float(mat.get_shader_parameter("frame"))
			t.eq(mat.get_shader_parameter("grid"), LoadingScreen.LOOP_GRID, "then the loop atlas")
	t.check(steady, "preparation progress only moves forward")
	t.check(not ahead, "the bar never runs ahead of the real preparation")
	t.check(closed[0], "the screen closes as soon as the round is live (%d frames)" % frames)
	t.check(mc.round_live(), "and the round is live")
	if loop_seen:
		t.check(first_frame <= 1.0, "the loop starts from the still's frame (frame %d)" % int(first_frame))
	else:
		print("[load] round was ready before the loop finished loading: the still stayed (allowed)")
	t.check(ls.stage_lbl.text != "", "a status line is shown")
	ls.queue_free()
	await t.get_tree().process_frame
	t.check(not is_instance_valid(ls), "screen freed")
	t.check(mat.get_shader_parameter("frames") == null, "its textures are let go")
	# a load still running when the screen went is collected by App
	var waited := 0
	while not App._orphan_loads.is_empty() and waited < 300:
		await t.get_tree().process_frame
		waited += 1
	t.check(App._orphan_loads.is_empty(), "no background load left behind")
	_end(mc)
	await t.get_tree().process_frame
	MatchController.drop_campus_cache()
	s.queue_free()


func test_loading_screen_closed_early_hands_its_load_to_app() -> void:
	var s := _offline()
	var ls := _loading_screen(s, null)
	var pending := ls._atlas_pending
	ls.queue_free()
	await t.get_tree().process_frame
	if pending:
		t.check(App._orphan_loads.has(LoadingScreen.LOOP_ATLAS) or ResourceLoader.load_threaded_get_status(LoadingScreen.LOOP_ATLAS) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "the unfinished load is adopted")
		# the next screen takes it over instead of asking twice
		var ls2 := _loading_screen(s, null)
		t.check(ls2._atlas_pending, "a new screen picks the load up")
		var f := 0
		while not ls2.loop_running() and f < 600:
			await t.get_tree().process_frame
			f += 1
		t.check(ls2.loop_running(), "and runs the loop")
		ls2.queue_free()
		await t.get_tree().process_frame
	var waited := 0
	while not App._orphan_loads.is_empty() and waited < 300:
		await t.get_tree().process_frame
		waited += 1
	t.check(App._orphan_loads.is_empty(), "nothing left loading")
	s.queue_free()


func test_loading_screen_reduced_motion_shows_the_still_only() -> void:
	var was: Variant = Save.get_setting("reduced_motion", false)
	Save.data["settings"]["reduced_motion"] = true
	var s := _offline()
	var ls := _loading_screen(s, null)
	t.check(not ls._atlas_pending, "no loop is loaded with Reduced Motion")
	for i in 5:
		await t.get_tree().process_frame
	t.check(not ls.loop_running(), "the still stays")
	t.eq((ls.picture.material as ShaderMaterial).get_shader_parameter("grid"), Vector2.ONE, "as one frame")
	ls.queue_free()
	Save.data["settings"]["reduced_motion"] = was
	await t.get_tree().process_frame
	s.queue_free()
