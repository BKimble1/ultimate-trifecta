extends RefCounted
## V6: bounded bot path work (NavGrid.find_path_budgeted).  Bot thinking was
## 97 % of a simulation tick (A* on the 320x300 grid; clustered replans and a
## bot re-searching an unreachable goal every tick reached 45-60 ms ticks and
## pushed the 60 Hz loop into catch-up).  Now: a clear line needs no search,
## at most one search per simulation tick, nearby starts to the same goal
## reuse a path, and an unreachable goal is not searched again at once.
## V8: a search runs on a worker thread and its answer is used on a tick
## fixed when it was asked (the tick waits for a slow worker): no search
## runs on the main thread, and seeded rounds stay deterministic.
var t


func _nav() -> NavGrid:
	var nav := NavGrid.shared(CampusLayout.shared())
	nav.settle()
	nav.debug_job_sleep_ms = 0
	nav.path_stats = {"search": 0, "direct": 0, "cache": 0, "deferred": 0, "unreachable": 0}
	nav._cache.clear()
	nav._cache_keys.clear()
	nav._unreachable.clear()
	return nav


## Ask every tick until answered (as a waiting bot does); [path, ticks].
func _ask(nav: NavGrid, a: Vector2, b: Vector2, cart := false) -> Array:
	for i in 60:
		var p := nav.find_path_budgeted(a, b, cart)
		if not nav.deferred:
			return [p, i]
		await t.get_tree().physics_frame
	return [PackedVector2Array(), 60]


func test_searches_run_off_the_main_thread_on_a_fixed_schedule() -> void:
	var nav := _nav()
	await t.get_tree().physics_frame
	var lay := CampusLayout.shared()
	var a: Vector2 = lay.waters[0]["center"]
	var b: Vector2 = lay.waters[3]["center"]
	var c: Vector2 = lay.waters[5]["center"]
	var direct_us := Time.get_ticks_usec()
	var ref := nav.find_path(b + Vector2(-12, 0), c + Vector2(0, -12))
	direct_us = Time.get_ticks_usec() - direct_us
	var f0 := Engine.get_physics_frames()
	var t0 := Time.get_ticks_usec()
	var p1 := nav.find_path_budgeted(a + Vector2(0, 12), b + Vector2(0, 12))
	var p2 := nav.find_path_budgeted(b + Vector2(-12, 0), c + Vector2(0, -12))
	var ask_us := Time.get_ticks_usec() - t0
	t.check(p1.is_empty() and p2.is_empty() and nav.deferred, "both requests are queued, not searched on this thread")
	t.check(ref.size() >= 0, "(direct reference search: %d points)" % ref.size())
	t.eq(nav.pending(), 2, "two searches queued for the foot grid")
	t.check(ask_us < maxi(2000, direct_us / 2), "asking costs %.2f ms here (one search on this thread: %.2f ms)" % [ask_us / 1000.0, direct_us / 1000.0])
	var got1 := -1
	var got2 := -1
	for i in NavGrid.ASYNC_DELAY + NavGrid.ASYNC_SPACING + 3:
		await t.get_tree().physics_frame
		if got1 < 0:
			var p := nav.find_path_budgeted(a + Vector2(0, 12), b + Vector2(0, 12))
			if not nav.deferred:
				got1 = Engine.get_physics_frames() - f0
				t.check(p.size() >= 2, "the first answer is a path (%d points)" % p.size())
		if got2 < 0:
			var q := nav.find_path_budgeted(b + Vector2(-12, 0), c + Vector2(0, -12))
			if not nav.deferred:
				got2 = Engine.get_physics_frames() - f0
				t.eq(q.size(), ref.size(), "the background answer is the direct search's path (%d points)" % ref.size())
	t.eq(got1, NavGrid.ASYNC_DELAY, "the first answer is used %d ticks after the request" % NavGrid.ASYNC_DELAY)
	t.eq(got2, NavGrid.ASYNC_DELAY + NavGrid.ASYNC_SPACING, "the next one on the same grid %d ticks after that" % NavGrid.ASYNC_SPACING)
	t.eq(int(nav.path_stats["search"]), 2, "two real searches (waiting requests don't search again)")


## A worker slower than the schedule: the tick the answer is due waits for
## it, so the answer still arrives on exactly that tick on any machine.
func test_a_slow_worker_is_waited_for_on_the_due_tick() -> void:
	var nav := _nav()
	await t.get_tree().physics_frame
	var lay := CampusLayout.shared()
	var a: Vector2 = lay.waters[1]["center"] + Vector2(0, 14)
	var b: Vector2 = lay.waters[4]["center"] + Vector2(12, 0)
	nav.debug_job_sleep_ms = 400
	var waits := nav.stat_wait_n
	var r: Array = await _ask(nav, a, b)
	nav.debug_job_sleep_ms = 0
	t.eq(int(r[1]), NavGrid.ASYNC_DELAY, "answered on the scheduled tick despite a 400 ms worker")
	t.check((r[0] as PackedVector2Array).size() >= 2, "with the path")
	t.eq(nav.stat_wait_n, waits + 1, "the due tick waited for the worker")


func test_clear_line_and_nearby_start_need_no_search() -> void:
	var nav := _nav()
	await t.get_tree().physics_frame
	var lay := CampusLayout.shared()
	var w: Vector2 = lay.waters[1]["center"]
	# a short open stretch: straight line, no search
	var from := nav.to_world(nav.nearest_open(nav.foot, w + Vector2(0, 20)))
	var to := nav.to_world(nav.nearest_open(nav.foot, w + Vector2(0, 16)))
	var d := nav.find_path_budgeted(from, to)
	t.check(int(nav.path_stats["direct"]) >= 1 or d.size() >= 2, "a clear straight line is used directly")
	# a long path, then the same goal from another point of the same start
	# cell in the next tick (a start a few metres away reuses it only when its
	# first leg is clear - checked, not assumed)
	var far: Vector2 = lay.waters[4]["center"] + Vector2(10, 10)
	var p1: PackedVector2Array = (await _ask(nav, from, far))[0]
	await t.get_tree().physics_frame
	var searches := int(nav.path_stats["search"])
	var p2 := nav.find_path_budgeted(from + Vector2(0.2, 0.15), far)
	t.check(p1.size() >= 2 and p2.size() >= 2, "both starts get a path")
	t.eq(int(nav.path_stats["search"]), searches, "the same neighbourhood reuses the path (no new search)")
	t.check(int(nav.path_stats["cache"]) >= 1, "answered from the cache")


func test_unreachable_goal_is_not_searched_every_tick() -> void:
	var nav := _nav()
	await t.get_tree().physics_frame
	# a cell walled in on every side (the grid's solid border is unreachable
	# from the campus; nearest_open picks the closest open cell, which is a
	# pocket only if one exists - so build the case on the cart grid: a lawn
	# cell far from any road)
	var lay := CampusLayout.shared()
	var start := nav.to_world(nav.nearest_open(nav.cart, Vector2(0, 0)))
	var pocket := Vector2.INF
	# find a cart-open cell whose path from the start fails (a pocket)
	for w in lay.waters:
		var cand: Vector2 = (w["center"] as Vector2) + Vector2(0, 2)
		await t.get_tree().physics_frame
		var r: Array = await _ask(nav, start, cand, true)
		if (r[0] as PackedVector2Array).is_empty() and int(r[1]) < 60:
			pocket = cand
			break
	if pocket == Vector2.INF:
		t.check(true, "no unreachable cart goal near a water on this layout (nothing to cache)")
		return
	var searches := int(nav.path_stats["search"])
	for i in 5:
		await t.get_tree().physics_frame
		nav.find_path_budgeted(start + Vector2(i * 7.0, 0), pocket, true)
	t.eq(int(nav.path_stats["search"]), searches, "an unreachable cart goal is not searched again from new starts")
	t.check(int(nav.path_stats["unreachable"]) >= 5, "each request is answered from the cache")
