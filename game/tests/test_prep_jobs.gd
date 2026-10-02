extends RefCounted
## V5 preparation profile: every job is timed and attributed, the bots'
## navigation grid is built in slices that give exactly the one-shot grid,
## and no single non-campus job holds a loading frame for long.  Times are
## this test machine's CPU (not a phone): the bounds are generous.
var t


static func _sum(n: NavGrid) -> Array:
	var h := 0
	var ws := 0.0
	for g in [n.foot, n.cart]:
		for y in n.dims.y:
			for x in n.dims.x:
				var c := Vector2i(x, y)
				h = (h * 31 + (1 if g.is_point_solid(c) else 0)) % 1000000007
				ws += g.get_point_weight_scale(c) * float((x * 7 + y * 13) % 17 + 1)
	return [h, snappedf(ws, 0.001), n.low_wall_cells.size()]


func test_staged_nav_grid_equals_the_one_shot_grid() -> void:
	var lay := CampusLayout.shared()
	var full := _sum(NavGrid.new(lay))
	var keep := NavGrid._shared
	NavGrid._shared = null
	var steps := 0
	var worst := 0.0
	while true:
		var t0 := Time.get_ticks_usec()
		var more := NavGrid.build_step(lay)
		worst = maxf(worst, float(Time.get_ticks_usec() - t0) / 1000.0)
		steps += 1
		if not more:
			break
	var staged := _sum(NavGrid.shared(lay))
	t.eq(staged, full, "the staged grid is exactly the one-shot grid (solid cells, weights, low walls)")
	t.check(steps >= NavGrid.PHASES.size(), "built in %d slices" % steps)
	print("[prep] nav grid: %d slices, longest %.1f ms (V4: one ~50 ms block)" % [steps, worst])
	if keep != null:
		NavGrid._shared = keep


func test_every_job_is_timed_and_named() -> void:
	MatchController.drop_campus_cache()
	NavGrid._shared = null
	var s := NetSession.new()
	t.add_child(s)
	s.start_offline("u-prep", "Prep", {}, "runner")
	var info := {}
	s.match_starting.connect(func(i: Dictionary) -> void: info.merge(i, true), CONNECT_ONE_SHOT)
	s.host_start_match(4242)
	var mc := MatchController.new()
	mc.setup(s, info, {"quality": 1, "staged": true})
	t.add_child(mc)
	var f := 0
	while not mc.prepared and f < 800:
		await t.get_tree().process_frame
		f += 1
	t.check(mc.prepared, "prepared")
	var names := {}
	for j in mc.prep_jobs:
		names[String(j[0]).get_slice("#", 0)] = true
	for n in ["campus", "world", "ground", "nav", "sim", "views", "carts_camera", "hud", "touch"]:
		t.check(names.has(n), "job %s timed" % n)
	var worst_non_campus := ["", 0.0]
	for j in mc.prep_jobs:
		if not String(j[0]).begins_with("campus") and float(j[1]) > float(worst_non_campus[1]):
			worst_non_campus = j
	print("[prep] longest job %s %.1f ms; longest non-campus job %s %.1f ms" % [mc.prep_longest[0], mc.prep_longest[1], worst_non_campus[0], worst_non_campus[1]])
	t.check(float(worst_non_campus[1]) < 40.0, "no non-campus job holds a frame for long (%s %.1f ms)" % worst_non_campus)
	mc.release_campus()
	mc.queue_free()
	await t.get_tree().process_frame
	MatchController.drop_campus_cache()
	s.queue_free()
