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
