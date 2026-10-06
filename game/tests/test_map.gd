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


# --- Pass 8: what the map may show about the other side --------------------

func _practice(role: String) -> MatchController:
	var s := NetSession.new()
	t.add_child(s)
	s.start_offline("u-map8", "Mapper", {}, role)
	var info := {}
	s.match_starting.connect(func(i: Dictionary) -> void: info.merge(i, true), CONNECT_ONE_SHOT)
	s.host_start_match(99)
	var mc := MatchController.new()
	mc.setup(s, info, {"quality": 0, "staged": false})
	t.add_child(mc)
	for i in 8:
		await t.get_tree().process_frame
	mc._seen_scan_t = 1000.0       # the test runs the sighting passes itself
	return mc


func _done(mc: MatchController) -> void:
	var s: Variant = mc.session
	mc.release_campus()
	mc.queue_free()
	await t.get_tree().process_frame
	MatchController.drop_campus_cache()
	if is_instance_valid(s):
		(s as Node).queue_free()


func _clear(mc: MatchController, a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a + Vector3(0, 1.5, 0), b + Vector3(0, 1.0, 0), TC.L_WORLD)
	return mc.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _seen_items(mc: MatchController) -> Array:
	mc.hud.refresh(0.016)
	return MatchHUD.MapPainter.items(mc.hud, Vector2(300, 300), 280.0, true).filter(func(it: Dictionary) -> bool: return String(it["kind"]) == "seen")


func test_sight_walls_lost_sight_and_expiry() -> void:
	var mc := await _practice("runner")
	mc.sim._set_phase(TC.Phase.PLAYING)
	var me := mc.sim.player(mc.local_slot)
	var watch: SimPlayer = null
	var mate: SimPlayer = null
	for p in mc.sim.players:
		if p.is_patrol() and watch == null:
			watch = p
		elif p.is_runner() and p.id != mc.local_slot and mate == null:
			mate = p
	# a solid building 18-40 m across between you and the Night Watch: the
	# first one (in data order) with open ground 4 m beyond both sides
	var lay := mc.sim.layout
	var lib := Vector2.INF
	var half := 0.0
	for bd in lay.buildings:
		if bool(bd["background"]) or float(bd["h"]) < 6.0 or not (bd["passages"] as Array).is_empty():
			continue
		var r: Rect2 = bd["rect"]
		var c := r.get_center()
		if r.size.x < 18.0 or r.size.x > 40.0 or not Geometry2D.is_point_in_polygon(c, bd["poly"]):
			continue
		var pa := c - Vector2(r.size.x * 0.5 + 4.0, 0)
		var pb := c + Vector2(r.size.x * 0.5 + 4.0, 0)
		var ok := true
		for q in [pa, pb, pa + Vector2(-10.0, 0)]:
			if not lay.in_play(q) or lay.building_at(q, 1.5) >= 0 or lay.water_index_at(q, 1.0) >= 0:
				ok = false
		if ok:
			lib = c
			half = r.size.x * 0.5
			break
	t.check(lib != Vector2.INF, "a building to hide behind")
	var a := Vector3(lib.x - half - 4.0, 0.05, lib.y)
	var behind := Vector3(lib.x + half + 4.0, 0.05, lib.y)
	me.body.global_position = a
	watch.body.global_position = behind
	await t.get_tree().physics_frame
	t.check(not _clear(mc, a, behind), "the library blocks the line")
	t.check(a.distance_to(behind) < mc.cfg.view_range_m, "and they are within view range (%.0f m)" % a.distance_to(behind))
	mc.last_seen.clear()
	mc.scan_seen_now()
	t.check(not mc.last_seen.has(watch.id), "behind a building: not seen, nothing on the map")
	t.eq(_seen_items(mc).size(), 0, "no marker")
	# out in the open on your side: seen live, with its facing and role badge
	var open := Vector3.INF
	for c in [a + Vector3(0, 0, 12.0), a + Vector3(0, 0, -12.0), a + Vector3(-10.0, 0, 0)]:
		if _clear(mc, a, c):
			open = c
			break
	t.check(open != Vector3.INF, "an open spot on your side")
	watch.body.global_position = open
	watch.yaw = 1.0
	await t.get_tree().physics_frame
	me.body.global_position = a
	watch.body.global_position = open
	mc.scan_seen_now()
	t.check(mc.last_seen.has(watch.id) and bool(mc.last_seen[watch.id]["live"]), "in plain sight: live")
	var items := _seen_items(mc)
	t.eq(items.size(), 1, "one Watch marker")
	if items.size() == 1:
		t.check(bool(items[0]["live"]) and int(items[0]["opp"]) == TC.Role.PATROL and not bool(items[0]["cart"]), "a live Night Watch badge")
		t.check((items[0]["pos"] as Vector2).distance_to(CampusMap.to_map(Vector2(open.x, open.z), Vector2(300, 300), 280.0)) < 0.5, "where it is")
	# close by: the danger chip (from that sighting only)
	t.check(mc.hud.danger_chip.visible == (open.distance_to(a) <= MatchHUD.DANGER_M), "the danger chip follows a nearby live sighting")
	var seen_at: Vector3 = mc.last_seen[watch.id]["pos"] if mc.last_seen.has(watch.id) else open
	# lost sight: the mark stays where it was last seen, hollow, with its age
	watch.body.global_position = behind
	await t.get_tree().physics_frame
	me.body.global_position = a
	watch.body.global_position = behind
	mc.scan_seen_now()
	t.check(mc.last_seen.has(watch.id) and not bool(mc.last_seen[watch.id]["live"]), "lost sight: no longer live")
	items = _seen_items(mc)
	t.eq(items.size(), 1, "still one mark")
	if items.size() == 1:
		t.check(not bool(items[0]["live"]) and float(items[0]["age"]) >= 0.0, "hollow, with its age")
		t.check((items[0]["pos"] as Vector2).distance_to(CampusMap.to_map(Vector2(seen_at.x, seen_at.z), Vector2(300, 300), 280.0)) < 0.01,
			"frozen at the last point seen, not following the hidden Watch")
	t.check(not mc.hud.danger_chip.visible, "no danger chip without a live sighting")
	# the TTL: gone after 5 s
	if mc.last_seen.has(watch.id):
		mc.last_seen[watch.id]["ms"] = Time.get_ticks_msec() - int(MatchController.LAST_SEEN_TTL_S * 1000.0) - 100
	mc.scan_seen_now()
	t.check(not mc.last_seen.has(watch.id), "expired after the TTL")
	t.eq(_seen_items(mc).size(), 0, "and off the map")
	# caught / home: the view (and the sight) follow the teammate you watch
	me.state = TC.PState.FINISHED
	mc.spectate_slot = mate.id
	t.eq(mc.sight_slot(), mate.id, "home: sightings come from the followed teammate")
	mate.body.global_position = open + Vector3(3, 0, 0)
	watch.body.global_position = open
	await t.get_tree().physics_frame
	mate.body.global_position = open + Vector3(3, 0, 0)
	watch.body.global_position = open
	mc.scan_seen_now()
	t.check(mc.last_seen.has(watch.id), "what the followed teammate sees")
	me.state = TC.PState.ACTIVE
	mc.spectate_slot = -1
	t.eq(mc.sight_slot(), mc.local_slot, "back in play: your own eyes")
	# a Night Watch driving: a cart badge while in sight; no cart dots otherwise
	watch.state = TC.PState.IN_CART
	me.body.global_position = a
	watch.body.global_position = open
	mc.last_seen.clear()
	mc.scan_seen_now()
	items = _seen_items(mc)
	t.check(items.size() == 1 and bool(items[0]["cart"]), "a spotted driver shows as the Watch's cart badge")
	var all := MatchHUD.MapPainter.items(mc.hud, Vector2(300, 300), 280.0, true)
	t.eq(all.filter(func(it: Dictionary) -> bool: return String(it["kind"]) == "cart").size(), 0, "a runner's map never lists the carts")
	watch.state = TC.PState.WAITING
	await _done(mc)


func test_a_dead_link_adds_no_sightings() -> void:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(20, 0, 0.0, 1, ["runner", "runner"])
	var c0: NetSession = rig.clients[0]
	await rig.wait_until(func() -> bool: return c0.local_slot >= 0 and rig.host.human_count() == 2, 300)
	c0.set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.can_start(), 200)
	rig.host.host_start_match(31)
	var ok := await rig.wait_until(func() -> bool: return rig.host.sim != null and rig.host.sim.phase == TC.Phase.PLAYING \
		and rig.mc_of(c0) != null and rig.mc_of(c0).prepared, 1500)
	t.check(ok, "party round playing")
	var g := rig.mc_of(c0)
	g._seen_scan_t = 1000.0
	var sim := rig.host.sim
	var me := sim.player(g.local_slot)
	var watch: SimPlayer = null
	for p in sim.players:
		if p.is_patrol():
			watch = p
			break
	t.check(watch != null and watch.state == TC.PState.WAITING, "a Night Watch still in its head start (it stays put)")
	# put it in plain sight 4 m from the guest runner (inside tonight's dorm)
	watch.body.global_position = me.pos() + Vector3(0, 0, 4.0)
	watch.body.velocity = Vector3.ZERO
	await rig.frames(30)
	g.scan_seen_now()
	t.check(g.last_seen.has(watch.id) and bool(g.last_seen[watch.id]["live"]), "the guest sees it from fresh snapshots")
	rig.pass_through = false       # the link goes dead
	var t0 := Time.get_ticks_msec()     # (wall time: the TTL and staleness are wall-clock)
	while Time.get_ticks_msec() - t0 < MatchController.SEEN_STALE_MS + 200:
		await t.get_tree().process_frame
	g.scan_seen_now()
	t.check(not g.last_seen.has(watch.id) or not bool(g.last_seen[watch.id]["live"]), "stale snapshots never keep a Watch 'in sight'")
	rig.pass_through = true
	rig.teardown()
	await t.get_tree().process_frame
	await t.get_tree().process_frame
