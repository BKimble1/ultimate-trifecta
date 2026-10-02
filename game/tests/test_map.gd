extends RefCounted
## V5 campus map: the baked picture and the live markers share one
## world -> map transform; labels never overlap; and the map only shows
## what the information policy allows (your team openly, opponents only as
## host-sent last-seen cues).
var t


func test_bake_and_overlay_share_the_transform() -> void:
	var b := CampusLayout.BOUNDS
	var c := Vector2(300, 260)
	var half := 240.0
	t.eq(CampusMap.to_map(b.get_center(), c, half), c, "the campus centre is the map centre")
	for p in [b.position, b.end, Vector2(b.position.x, b.end.y), Vector2(0, 112), Vector2(-120, 46)]:
		var on_canvas := CampusMap.to_map(p, c, half)
		var in_tex := CampusMap.to_map(p, Vector2.ONE * 512.0, 512.0) / 1024.0
		var uv := (on_canvas - (c - Vector2.ONE * half)) / (half * 2.0)
		t.check(uv.distance_to(in_tex) < 0.0005, "%s lands on the same spot of the picture and the overlay" % str(p))
		t.check(Rect2(c - Vector2.ONE * half, Vector2.ONE * half * 2.0).has_point(on_canvas), "%s is inside the map square" % str(p))
	# uniform scale (no stretch): 10 m east = 10 m south on the map
	var e := CampusMap.to_map(Vector2(10, 0), c, half) - CampusMap.to_map(Vector2.ZERO, c, half)
	var s := CampusMap.to_map(Vector2(0, 10), c, half) - CampusMap.to_map(Vector2.ZERO, c, half)
	t.check(absf(e.length() - s.length()) < 0.001, "uniform scale")
	t.check(absf(CampusMap.m_to_map(10.0, half) - e.length()) < 0.001, "m_to_map agrees")


func test_labels_never_overlap() -> void:
	var f := UIKit.font_w(700)
	var reqs: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	# a crowded corner: twelve labels around nearby anchors
	for i in 12:
		reqs.append({"at": Vector2(200, 200) + Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30)), "text": "Player %d" % i,
			"size": 15, "prio": rng.randi() % 4, "col": Color.WHITE, "r": 8.0})
	var blocked: Array = [Rect2(190, 190, 20, 20)]
	var area := Rect2(0, 0, 400, 400)
	var placed := CampusMap.place_labels(reqs, f, area, blocked)
	t.check(placed.size() >= 4 and placed.size() < 12, "some fit, the rest are left to the side panel (%d placed)" % placed.size())
	for i in placed.size():
		var r: Rect2 = placed[i]["rect"]
		t.check(area.encloses(r), "label %d stays on the map" % i)
		t.check(not r.intersects(blocked[0]), "label %d doesn't cover a marker" % i)
		for j in range(i + 1, placed.size()):
			t.check(not r.intersects(placed[j]["rect"]), "labels %d and %d don't overlap" % [i, j])


func test_map_shows_only_permitted_opponents() -> void:
	var s := NetSession.new()
	t.add_child(s)
	s.start_offline("u-map", "Mapper", {}, "runner")
	var info := {}
	s.match_starting.connect(func(i: Dictionary) -> void: info.merge(i, true), CONNECT_ONE_SHOT)
	s.host_start_match(99)
	var mc := MatchController.new()
	mc.setup(s, info, {"quality": 0, "staged": true})
	t.add_child(mc)
	var frames := 0
	while not (mc.prepared and mc.hud != null) and frames < 600:
		await t.get_tree().process_frame
		frames += 1
	for i in 30:
		await t.get_tree().process_frame
	t.check(mc.hud != null, "the HUD is up")
	if mc.hud == null:
		mc.queue_free()
		return
	var my_role := int(mc.roster[mc.local_slot]["role"])
	var opponents := []
	for slot in mc.roster:
		if int(mc.roster[slot]["role"]) != my_role:
			opponents.append(int(slot))
	# nobody seen yet: no opponent marker at all
	mc.last_seen.clear()
	var items := MatchHUD.MapPainter.items(mc.hud, Vector2(300, 300), 280.0, true)
	t.eq(items.filter(func(it: Dictionary) -> bool: return String(it["kind"]) == "seen").size(), 0, "no opponent is drawn until seen")
	for it in items:
		if String(it["kind"]) == "team":
			for sl in it["slots"]:
				t.eq(int(mc.roster[sl]["role"]), my_role, "team markers are only your own role")
	t.eq(items.filter(func(it: Dictionary) -> bool: return String(it["kind"]) == "target").size(), 3, "tonight's three waters")
	t.eq(items.filter(func(it: Dictionary) -> bool: return String(it["kind"]) == "home").size(), 1, "the dorm")
	# one opponent seen two seconds ago: exactly one fading ring, at that spot
	if not opponents.is_empty():
		var o: int = opponents[0]
		mc.last_seen[o] = {"pos": Vector3(10, 0, 20), "ms": Time.get_ticks_msec() - 2000, "live": false}
		items = MatchHUD.MapPainter.items(mc.hud, Vector2(300, 300), 280.0, true)
		var seen := items.filter(func(it: Dictionary) -> bool: return String(it["kind"]) == "seen")
		t.eq(seen.size(), 1, "one last-seen cue")
		t.check(not bool(seen[0]["live"]) and float(seen[0]["fade"]) > 0.4 and float(seen[0]["fade"]) < 0.8, "fading, not live")
		t.check((seen[0]["pos"] as Vector2).distance_to(CampusMap.to_map(Vector2(10, 20), Vector2(300, 300), 280.0)) < 0.01, "where they were seen")
		mc.last_seen.clear()
	# the full map opens and closes, and blocks play input while open
	mc.hud.open_map()
	await t.get_tree().process_frame
	t.check(mc.hud.map_view != null and mc.hud.map_view.mouse_filter == Control.MOUSE_FILTER_STOP, "the map takes touches while open")
	if mc.touch:
		t.check(not mc.touch.visible, "touch controls are set aside under the map")
	mc.hud.close_map()
	await t.get_tree().process_frame
	t.check(mc.hud.map_view == null, "closed")
	mc.release_campus()
	mc.queue_free()
	await t.get_tree().process_frame
	MatchController.drop_campus_cache()
	s.queue_free()
