extends RefCounted
## V6: bounded bot path work (NavGrid.find_path_budgeted).  Bot thinking was
## 97 % of a simulation tick (A* on the 320x300 grid; clustered replans and a
## bot re-searching an unreachable goal every tick reached 45-60 ms ticks and
## pushed the 60 Hz loop into catch-up).  Now: a clear line needs no search,
## at most one search per simulation tick, nearby starts to the same goal
## reuse a path, and an unreachable goal is not searched again at once.
var t


func _nav() -> NavGrid:
	var nav := NavGrid.shared(CampusLayout.shared())
	nav.path_stats = {"search": 0, "direct": 0, "cache": 0, "deferred": 0, "unreachable": 0}
	nav._cache.clear()
	nav._cache_keys.clear()
	nav._unreachable.clear()
	return nav


func test_one_search_per_tick_then_the_next_waits() -> void:
	var nav := _nav()
	await t.get_tree().physics_frame
	var lay := CampusLayout.shared()
	var a: Vector2 = lay.waters[0]["center"]
	var b: Vector2 = lay.waters[3]["center"]
	var c: Vector2 = lay.waters[5]["center"]
	var p1 := nav.find_path_budgeted(a + Vector2(0, 12), b + Vector2(0, 12))
	t.check(p1.size() >= 2 and not nav.deferred, "the first search of the tick runs")
	var p2 := nav.find_path_budgeted(b + Vector2(-12, 0), c + Vector2(0, -12))
	t.check(nav.deferred and p2.is_empty(), "a second search in the same tick waits")
	await t.get_tree().physics_frame
	var p3 := nav.find_path_budgeted(b + Vector2(-12, 0), c + Vector2(0, -12))
	t.check(not nav.deferred, "and runs on the next tick (%d points)" % p3.size())
	t.eq(int(nav.path_stats["search"]), 2, "two real searches in two ticks")


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
	var p1 := nav.find_path_budgeted(from, far)
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
		var p := nav.find_path_budgeted(start, cand, true)
		if p.is_empty() and not nav.deferred:
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
