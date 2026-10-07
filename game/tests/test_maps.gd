extends RefCounted
## Two maps: the registry, Moonbrook College restored from the 2.0 source
## (its data, halls, waters and colliders as 2.0 had them), the map carried
## through settings, START and reconnects, a mismatched map refused, and
## caches that follow the map instead of keeping two worlds.
var t


func _classic() -> CampusLayout:
	return CampusMaps.layout(CampusMaps.CLASSIC)


func test_registry() -> void:
	t.eq(CampusMaps.ids(), ["classic", "reference_campus"] as Array[String], "two maps, in the chooser's order")
	t.eq(CampusMaps.title(CampusMaps.CLASSIC), "Moonbrook College", "the classic map's title")
	t.eq(CampusMaps.title(CampusMaps.CAMPUS), "Lakeside Campus", "the new map's title")
	t.eq(CampusMaps.DEFAULT_ID, CampusMaps.CAMPUS, "the new campus is the default")
	t.eq(CampusMaps.sanitize("nope"), CampusMaps.DEFAULT_ID, "an unknown id falls back to the default")
	t.eq(CampusMaps.sanitize(null), CampusMaps.DEFAULT_ID, "a missing id falls back to the default")
	t.eq(_classic().bounds, Rect2(-160.0, -150.0, 320.0, 300.0), "classic bounds as 2.0 had them")
	t.eq(_classic().nav_cell, 1.0, "classic navigation on 2.0's 1 m grid")
	t.eq(CampusLayout.shared().bounds, Rect2(-720.0, -560.0, 1190.0, 1000.0), "the campus's bounds")
	t.check(_classic() != CampusLayout.shared(), "one layout per map")
	t.check(_classic().data.campus_hash != CampusLayout.shared().data.campus_hash, "different data, different revision")
	for id in CampusMaps.ids():
		var d := CampusMaps.def(id)
		t.check(ResourceLoader.exists(String(d["preview"])), "%s has its preview image" % id)
		t.check(FileAccess.file_exists(String(d["routes"])), "%s has its route table" % id)


## Each map's dorm index lists exactly its data's start dorms, and no id is
## shared: a classic hall id never resolves to a hall of the other map.
func test_dorm_index_and_ids() -> void:
	var seen := {}
	for id in CampusMaps.ids():
		var from_data: Array = []
		for it in CampusMaps.data(id).items("gameplay"):
			if String(it.get("kind", "")) == "start_dorm":
				from_data.append(String(it["dorm"]))
		from_data.sort()
		var idx: Array = (CampusMaps.def(id)["dorms"] as Array).duplicate()
		idx.sort()
		t.eq(idx, from_data, "%s: the dorm index matches the data" % id)
		for d in from_data:
			t.check(not seen.has(d), "dorm id %s belongs to one map only" % d)
			seen[d] = id
			t.eq(CampusMaps.map_of_dorm(d), id, "%s resolves to %s" % [d, id])
	t.check(CampusDorms.has_dorm("puddlesworth", CampusMaps.CLASSIC), "a classic hall on the classic map")
	t.check(not CampusDorms.has_dorm("puddlesworth", CampusMaps.CAMPUS), "never on the new map")
	t.check(not CampusDorms.has_dorm("west_hall", CampusMaps.CLASSIC), "a new-map hall never on the classic map")
	t.eq(CampusDorms.default_id(CampusMaps.CLASSIC), "puddlesworth", "Puddlesworth Hall is the classic default")
	t.eq(CampusDorms.default_id(CampusMaps.CAMPUS), "west_hall", "West Hall is the new map's default")


## The committed classic data is exactly what the restored 2.0 description
## exports today (no drift between the classic look and its gameplay).
func test_classic_export_is_current() -> void:
	var exp := preload("res://tools/classic_export.gd")
	var layers: Dictionary = exp.export_layers(ClassicLayout.new())
	for name in layers:
		var path := "res://data/maps/classic/%s.json" % name
		t.check(FileAccess.file_exists(path), "%s exists" % path)
		t.eq(FileAccess.get_file_as_string(path), exp.to_json(layers[name]), "%s is the current export" % path)


## Moonbrook College keeps its six waters (order, names, hand-placed exits,
## jump points and pads) and its three halls (rooms, doors, thresholds,
## pads) exactly as 2.0 defined them.
func test_classic_waters_and_halls_as_2_0() -> void:
	var L := _classic()
	var N := ClassicLayout.new()
	t.eq(L.pool_size(), 6, "six objective waters")
	for i in 6:
		var w: Dictionary = L.waters[i]
		var nw: Dictionary = N.waters[i]
		t.eq(String(w["id"]), String(nw["id"]), "water %d is %s" % [i, nw["id"]])
		t.eq(String(w["name"]), String(nw["name"]), "%s keeps its name" % nw["id"])
		t.eq(w["exits"].size(), nw["exits"].size(), "%s keeps its exits" % nw["id"])
		for k in nw["exits"].size():
			t.check((w["exits"][k] as Vector3).distance_to(nw["exits"][k]) < 0.002, "%s exit %d" % [nw["id"], k])
		for k in nw["jump_points"].size():
			t.check((w["jump_points"][k] as Vector2).distance_to(nw["jump_points"][k]) < 0.002, "%s jump point %d" % [nw["id"], k])
		for k in nw["pads"].size():
			t.check((w["pads"][k] as Vector2).distance_to(nw["pads"][k]) < 0.002, "%s pad %d" % [nw["id"], k])
		t.check(absf(float(w["surface_y"]) - float(nw["surface_y"])) < 0.001 and absf(float(w["floor_y"]) - float(nw["floor_y"])) < 0.001, "%s surface and floor" % nw["id"])
		for s in 40:
			var a := TAU * float(s) / 40.0
			var c: Vector2 = nw["center"]
			for r in [0.5, 0.95, 1.05, 1.6]:
				var ext := 6.0 if String(nw["shape"]) == "circle" else 10.0
				var p := c + Vector2(cos(a), sin(a)) * ext * float(r)
				t.check(CampusLayout.in_water_shape(w, p) == ClassicLayout.in_water_shape(nw, p) or _near_edge(nw, p), "%s: same water at %s" % [nw["id"], p])
	t.eq(CampusDorms.ids(CampusMaps.CLASSIC), ["puddlesworth", "lanternfield", "moonpenny"] as Array[String], "three halls, Puddlesworth first")
	for id in ClassicDorms.ids():
		var g := CampusDorms.geometry(id)
		var ng := ClassicDorms.geometry(id)
		t.eq(CampusData.bounds(g["room"]), ng["room"], "%s: the same common room" % id)
		t.eq(g["doors"].size(), ng["doors"].size(), "%s: three doors" % id)
		for k in ng["doors"].size():
			var d: Dictionary = g["doors"][k]
			var nd: Dictionary = ng["doors"][k]
			t.check((d["line_p"] as Vector2).distance_to(nd["line_p"]) < 0.002 and (d["n_in"] as Vector2).distance_to(nd["n_in"]) < 0.001, "%s %s: the same threshold" % [id, nd["id"]])
		for k in ng["pads"].size():
			t.check((g["pads"][k]["pos"] as Vector2).distance_to(ng["pads"][k]["pos"]) < 0.002 and absf(float(g["pads"][k]["yaw"]) - float(ng["pads"][k]["yaw"])) < 0.001, "%s pad %d" % [id, k])
		for k in ng["respawn"].size():
			t.check((g["respawn"][k] as Vector2).distance_to(ng["respawn"][k]) < 0.002, "%s respawn %d" % [id, k])


func _near_edge(w: Dictionary, p: Vector2) -> bool:
	return ClassicLayout.in_water_shape(w, p, 0.03) != ClassicLayout.in_water_shape(w, p, -0.03) if String(w["shape"]) != "rect" else ClassicLayout.in_water_shape(w, p, 0.03) and not ClassicLayout.in_water_shape(w, p, -0.03)


## The classic map's collision through the shared pipeline is 2.0's: rays
## down from 3.9 m (everything a runner can touch) over the whole map land
## on the same surface as 2.0's own collider set (rebuilt here from its
## source logic).
func test_classic_collision_as_2_0() -> void:
	var L := _classic()
	var N := ClassicLayout.new()
	var old_space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(old_space, true)
	var new_space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(new_space, true)
	var rids: Array[RID] = []
	var old_body := _body(old_space, rids)
	# (the shapes are held until the end: a body keeps only their RIDs)
	var old_shapes := _v2_colliders(N)
	for s in old_shapes:
		PhysicsServer3D.body_add_shape(old_body, (s[0] as Shape3D).get_rid(), s[1])
	var new_body := _body(new_space, rids)
	var tiles := CampusBuilder.ground_tiles(L)
	for tile in tiles:
		PhysicsServer3D.body_add_shape(new_body, (tile[0] as HeightMapShape3D).get_rid(), Transform3D(Basis.IDENTITY, tile[1]))
	var recipe := CampusBuilder.collision_recipe(L)
	for r in recipe:
		if int(r[0]) == CampusBuilder.RB_WORLD:
			PhysicsServer3D.body_add_shape(new_body, (r[1] as Shape3D).get_rid(), r[2])
	await t.get_tree().physics_frame
	await t.get_tree().physics_frame
	var so := PhysicsServer3D.space_get_direct_state(old_space)
	var sn := PhysicsServer3D.space_get_direct_state(new_space)
	var n := 0
	var same := 0
	var big: Array = []
	var x := -158.3
	while x < 158.0:
		var z := -148.3
		while z < 148.0:
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, 3.9, z), Vector3(x, -6.0, z))
			q.hit_from_inside = true
			var ho := so.intersect_ray(q)
			var hn := sn.intersect_ray(q)
			var yo := float(ho["position"].y) if not ho.is_empty() else -99.0
			var yn := float(hn["position"].y) if not hn.is_empty() else -99.0
			n += 1
			if absf(yo - yn) < 0.06:
				same += 1
			elif absf(yo - yn) > 0.3:
				big.append(Vector3(x, yo, z) if big.size() < 12 else Vector3.ZERO)
			z += 0.9
		x += 0.9
	var share := float(same) / float(n)
	t.check(share > 0.997, "%.2f%% of %d rays land where 2.0's did (differences over 0.3 m at %s)" % [share * 100.0, n, str(big.slice(0, 12))])
	for rid in rids:
		PhysicsServer3D.free_rid(rid)
	PhysicsServer3D.free_rid(old_space)
	PhysicsServer3D.free_rid(new_space)


func _body(space: RID, rids: Array[RID]) -> RID:
	var b := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(b, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(b, space)
	rids.append(b)
	return b


## 2.0's world colliders (its CampusBuilder.build_collision, cart blockers
## aside): [[Shape3D, Transform3D]].
func _v2_colliders(L: ClassicLayout) -> Array:
	var out: Array = []
	var box := func(c: Vector3, size: Vector3, yaw: float = 0.0) -> void:
		var bs := BoxShape3D.new()
		bs.size = size
		out.append([bs, Transform3D(Basis(Vector3.UP, yaw), c)])
	var seg := func(a: Vector2, b: Vector2, y0: float, h: float, th: float) -> void:
		var dd := b - a
		if dd.length() < 0.01:
			return
		var c := (a + b) * 0.5
		box.call(Vector3(c.x, y0 + h * 0.5, c.y), Vector3(dd.length() + th, h, th), atan2(-dd.y, dd.x))
	var cyl := func(c: Vector3, r: float, h: float) -> void:
		var cs := CylinderShape3D.new()
		cs.radius = r
		cs.height = h
		out.append([cs, Transform3D(Basis.IDENTITY, c)])
	# the ground: 2.0's single 1 m height field (pits under the waters)
	var grid := ClassicBuilder.height_grid(L)
	var b := ClassicLayout.BOUNDS
	var w := int(b.size.x) + 1
	var d := int(b.size.y) + 1
	var nn := maxi(w, d)
	var data := PackedFloat32Array()
	for zi in nn:
		for xi in nn:
			data.append(grid[zi * w + xi] if zi < d and xi < w else 0.0)
	var hm := HeightMapShape3D.new()
	hm.map_width = nn
	hm.map_depth = nn
	hm.map_data = data
	out.append([hm, Transform3D(Basis.IDENTITY, Vector3(b.position.x + (nn - 1) * 0.5, 0.0, b.position.y + (nn - 1) * 0.5))])
	for bd in L.buildings:
		var pos: Vector2 = bd["pos"]
		var size: Vector2 = bd["size"]
		var h: float = bd["h"]
		var y0: float = float(bd.get("base_y", 0.0))
		if bd.has("dorm_id"):
			for bx in ClassicDorms.geometry(String(bd["dorm_id"]))["boxes"]:
				box.call(bx[0], bx[1])
			continue
		if bd["id"] == "shed":
			var hz := size.y * 0.5
			box.call(Vector3(pos.x, h * 0.5, pos.y - hz + 0.3), Vector3(size.x, h, 0.6))
			box.call(Vector3(pos.x - size.x * 0.5 + 0.3, h * 0.5, pos.y), Vector3(0.6, h, size.y))
			box.call(Vector3(pos.x + size.x * 0.5 - 0.3, h * 0.5, pos.y), Vector3(0.6, h, size.y))
			box.call(Vector3(pos.x, h - 0.3, pos.y), Vector3(size.x, 0.6, size.y))
			continue
		box.call(Vector3(pos.x, y0 + (h - y0) * 0.5, pos.y), Vector3(size.x, h - y0, size.y), float(bd.get("rot", 0.0)))
	for s in L.walls:
		seg.call(s["a"], s["b"], 0.0, s["h"], s["t"])
	for s in L.hedges:
		seg.call(s["a"], s["b"], 0.0, s["h"], s["t"])
	for s in L.fences:
		seg.call(s["a"], s["b"], 0.0, s["h"], 0.25)
	for tr in L.trees:
		cyl.call(Vector3(tr["pos"].x, 2.0, tr["pos"].y), 0.42, 4.0)
	for r in L.rocks:
		box.call(r["pos"] + Vector3(0, float(r["size"].y) * 0.5, 0), r["size"], float(r["rot"]))
	for p in L.platforms:
		box.call(p["center"] - Vector3(0, float(p["size"].y) * 0.5, 0), p["size"])
	for rp in L.ramps:
		var dv: Vector3 = rp["to"] - rp["from"]
		var xa := dv.normalized()
		var za := xa.cross(Vector3.UP).normalized()
		var ya := za.cross(xa).normalized()
		var bs := BoxShape3D.new()
		bs.size = Vector3.ONE
		out.append([bs, Transform3D(Basis(xa * dv.length(), ya * 0.4, za * float(rp["w"])), (rp["from"] + rp["to"]) * 0.5 - ya * 0.2)])
	for lp in L.lamps:
		cyl.call(Vector3(lp.x, 1.7, lp.y), 0.14, 3.4)
	for bn in L.benches:
		box.call(Vector3(bn["pos"].x, 0.25, bn["pos"].y), Vector3(1.9, 0.5, 0.7), float(bn["rot"]))
	for so in L.solids:
		box.call(Vector3(so["pos"].x, float(so["size"].y) * 0.5, so["pos"].y), so["size"], float(so["rot"]))
	for wt in L.waters:
		var rim: float = float(wt.get("rim_h", 0.0))
		var c: Vector2 = wt["center"]
		if rim <= 0.0:
			continue
		var th: float = float(wt.get("rim_t", 0.5))
		if wt["shape"] == "circle":
			var r0: float = float(wt["radius"])
			for i in 20:
				var a := TAU * (float(i) + 0.5) / 20.0
				var cp := c + Vector2(cos(a), sin(a)) * (r0 + th * 0.5)
				box.call(Vector3(cp.x, rim * 0.5, cp.y), Vector3(th, rim, TAU * (r0 + th) / 20.0 + 0.15), -a)
			cyl.call(Vector3(c.x, 0.0, c.y), 1.3, 2.6)
		elif wt["shape"] == "rect":
			var hs: Vector2 = wt["size"] * 0.5
			box.call(Vector3(c.x, rim * 0.5, c.y - hs.y - th * 0.5), Vector3(hs.x * 2.0 + th * 2.0, rim, th))
			box.call(Vector3(c.x, rim * 0.5, c.y + hs.y + th * 0.5), Vector3(hs.x * 2.0 + th * 2.0, rim, th))
			box.call(Vector3(c.x - hs.x - th * 0.5, rim * 0.5, c.y), Vector3(th, rim, hs.y * 2.0))
			box.call(Vector3(c.x + hs.x + th * 0.5, rim * 0.5, c.y), Vector3(th, rim, hs.y * 2.0))
	return out


func test_settings_carry_the_map() -> void:
	var s := PartySeries.sanitize_settings({"watch": 2, "rounds": 3})
	t.eq(String(s["map"]), CampusMaps.DEFAULT_ID, "settings from before two maps get the default map")
	s = PartySeries.sanitize_settings({"watch": 2, "rounds": 3, "map": "classic"})
	t.eq(String(s["map"]), "classic", "the map is kept")
	t.check(PartySeries.summary(s).begins_with("Moonbrook College"), "the summary names the map")
	t.eq(PartySeries.summary_parts(s)[0], "Moonbrook College", "the lobby chip names the map")
	s = PartySeries.sanitize_settings({"watch": 2, "rounds": 3, "map": "future_map"})
	t.eq(PartySeries.map_title(s), "Unknown map", "a newer host's map shows as unknown here")


func test_practice_plays_its_map() -> void:
	for id in CampusMaps.ids():
		var s := NetSession.new()
		t.add_child(s)
		s.start_offline("u-maps", "Mapper", {}, "runner", false, id)
		var info := {}
		s.match_starting.connect(func(i: Dictionary) -> void: info.merge(i, true), CONNECT_ONE_SHOT)
		s.host_start_match(41)
		t.eq(String(info["map"]["id"]), id, "START names %s" % id)
		t.eq(String(info["map"]["data"]), CampusMaps.data(id).campus_hash, "with its data revision")
		t.check(CampusDorms.has_dorm(String(info["home_dorm"]), id), "the home hall is one of %s's" % id)
		t.check(RulesLogic.curated_combos(String(info["home_dorm"]), CampusMaps.layout(id).pool_size()).has(info["targets"]), "targets from that hall's feasible set")
		s.queue_free()


func test_mismatched_map_is_refused() -> void:
	var s := NetSession.new()
	t.add_child(s)
	s.start_offline("u-maps", "Mapper", {}, "runner", false, CampusMaps.CLASSIC)
	var info := {}
	s.match_starting.connect(func(i: Dictionary) -> void: info.merge(i, true), CONNECT_ONE_SHOT)
	s.host_start_match(7)
	var good := s._fix_start(JSON.parse_string(JSON.stringify(NetSession._jsonable(info))))
	t.check(not good.is_empty() and not good.has("_incompatible"), "the host's own START passes")
	var bad: Dictionary = JSON.parse_string(JSON.stringify(NetSession._jsonable(info)))
	bad["map"]["data"] = "0000000000000000"
	var r := s._fix_start(bad)
	t.check(r.has("_incompatible") and String(r.get("_why", "")) == "map", "other map data: refused as needing an update")
	bad = JSON.parse_string(JSON.stringify(NetSession._jsonable(info)))
	bad["map"]["id"] = "future_map"
	t.check(s._fix_start(bad).has("_incompatible"), "a map this build doesn't have: refused")
	bad = JSON.parse_string(JSON.stringify(NetSession._jsonable(info)))
	bad.erase("map")
	t.check(s._fix_start(bad).has("_incompatible"), "no map named: refused, never the local default")
	bad = JSON.parse_string(JSON.stringify(NetSession._jsonable(info)))
	bad["dorm"]["id"] = "west_hall"
	bad["home_dorm"] = "west_hall"
	t.check(s._fix_start(bad).is_empty(), "a hall of the other map is never resolved on this one")
	s.queue_free()


func test_map_over_the_network() -> void:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(30, 5, 0.0, 1)
	await rig.wait_until(func() -> bool: return rig.host.human_count() == 2, 300)
	rig.clients[0].set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.can_start(), 300)
	var rev := int(rig.host.settings["rev"])
	t.check(rig.host.host_set_settings(2, 3, CampusMaps.CLASSIC), "the host picks the classic map")
	t.check(int(rig.host.settings["rev"]) == rev + 1, "a map change is a settings change (revision)")
	t.check(not rig.host.can_start(), "and clears the guests' ready")
	t.check(not rig.host.host_set_settings(2, 3, "future_map"), "the host can't pick a map this build doesn't have")
	await rig.wait_until(func() -> bool: return String(rig.clients[0].settings.get("map", "")) == CampusMaps.CLASSIC, 300)
	t.eq(String(rig.clients[0].settings["map"]), CampusMaps.CLASSIC, "the guest sees the map")
	t.check(not rig.clients[0].host_set_settings(2, 3, CampusMaps.CAMPUS), "a guest can't change it")
	rig.clients[0].set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.can_start(), 300)
	rig.host.host_start_match(91)
	t.check(not rig.host.host_set_settings(2, 3, CampusMaps.CAMPUS), "locked for the series")
	await rig.wait_until(func() -> bool: return rig.started.has(rig.clients[0]), 300)
	var info: Dictionary = rig.started[rig.clients[0]]
	t.eq(String(info["map"]["id"]), CampusMaps.CLASSIC, "the guest's START is on the classic map")
	t.check(CampusDorms.has_dorm(String(info["home_dorm"]), CampusMaps.CLASSIC), "with a classic home hall")
	# a guest who drops and comes back mid-round gets the same map again
	await rig.wait_until(func() -> bool: return rig.host.phase >= TC.Phase.REVEAL, 600)
	var c0: NetSession = rig.clients[0]
	var slot := c0.local_slot
	var key := c0.rejoin_key
	rig.client_ts[0].close()
	await rig.frames(30)
	var c1 := rig.add_client(String(c0.local_uid), "Client0", "runner")
	c1.rejoin_key = key
	await rig.wait_until(func() -> bool: return c1.local_slot == slot and rig.started.has(c1), 400)
	var rs: Dictionary = rig.started.get(c1, {})
	t.eq(String((rs.get("map", {}) as Dictionary).get("id", "")), CampusMaps.CLASSIC, "a reconnecting guest's START names the classic map")
	t.eq(String(rs.get("home_dorm", "")), String(info["home_dorm"]), "and the same home hall")
	rig.teardown()


## Caches follow the map: the shared collision/height caches and the
## minimap rebuild for the other map; nothing keeps both.
func test_caches_follow_the_map() -> void:
	var a := CampusLayout.shared()
	var b := _classic()
	var ga := CampusBuilder.height_grid(a)
	t.eq(ga.size(), (int(a.bounds.size.x) + 1) * (int(a.bounds.size.y) + 1), "the campus grid covers its bounds")
	var gb := CampusBuilder.height_grid(b)
	t.eq(gb.size(), (int(b.bounds.size.x) + 1) * (int(b.bounds.size.y) + 1), "the classic grid covers its bounds")
	t.eq(CampusBuilder.tile_grid(a), Vector2i(4, 298), "the campus ground in 4 x 4 tiles of 298 m")
	t.eq(CampusBuilder.tile_grid(b), Vector2i(2, 160), "the classic ground in 2 x 2 tiles of 160 m")
	t.eq(CampusBuilder.ground_tiles(b).size(), 4, "four classic tiles")
	t.eq(NavGrid.shared(b).cell, 1.0, "the classic nav grid at 1 m")
	t.eq(NavGrid.shared(a).cell, 2.0, "the campus nav grid at 2 m")
	CampusMap.use(b)
	t.check(absf(CampusMap.mini_span() - 110.0) < 0.01, "the classic minimap window")
	t.eq(CampusMap.centre(), b.bounds.get_center(), "the minimap follows the classic map")
	CampusMap.use(a)
	t.eq(CampusMap.centre(), a.bounds.get_center(), "and back")
	CampusBuilder.drop_caches()


## (NP) A round's collision bodies are kept for the next round on the same
## map, and another map's kept bodies are freed while the new one loads:
## Moonbrook -> Moonbrook -> campus -> Moonbrook never plays in the other
## map's world, and nothing is left behind.
func test_kept_bodies_follow_the_map() -> void:
	MatchController.drop_campus_cache()
	var prev: Array = [null]
	for step in [[CampusMaps.CLASSIC, false], [CampusMaps.CLASSIC, true], [CampusMaps.CAMPUS, false], [CampusMaps.CLASSIC, false]]:
		var id: String = step[0]
		var lay := CampusMaps.layout(id)
		var s := NetSession.new()
		t.add_child(s)
		s.start_offline("u-maps", "Mapper", {}, "runner", false, id)
		var info := {}
		s.match_starting.connect(func(i: Dictionary) -> void: info.merge(i, true), CONNECT_ONE_SHOT)
		s.host_start_match(43)
		var mc := MatchController.new()
		mc.setup(s, info, {"quality": 0, "staged": true, "visuals": false})
		t.add_child(mc)
		var f := 0
		while not mc.prepared and f < 1500:
			await t.get_tree().process_frame
			f += 1
		t.check(mc.prepared, "%s: prepared" % id)
		var world := mc.sim.get_node_or_null("WorldCollision")
		var ground := mc.sim.get_node_or_null("GroundCollision")
		t.check(world != null and ground != null, "%s: the sim has its bodies" % id)
		if world == null or ground == null:
			mc.queue_free()
			s.queue_free()
			return
		var want := CampusBuilder.collision_recipe(lay).filter(func(r: Array) -> bool: return int(r[0]) == CampusBuilder.RB_WORLD).size()
		t.eq(world.get_child_count(), want, "%s: its own world shapes" % id)
		t.eq(ground.get_child_count(), CampusBuilder.ground_tiles(lay).size(), "%s: its own ground tiles" % id)
		if bool(step[1]):
			t.check(world == prev[0], "%s again: the kept bodies, not built again" % id)
		elif prev[0] != null:
			t.check(not is_instance_valid(prev[0]), "%s: the other map's kept bodies were freed while it loaded" % id)
		mc.release_campus()
		t.check(MatchController.bodies_kept(), "%s: kept as the round ends" % id)
		t.check(world.get_parent() == null, "%s: out of the tree between rounds" % id)
		prev[0] = world
		mc.queue_free()
		s.queue_free()
		await t.get_tree().process_frame
	MatchController.drop_campus_cache()
	t.check(not MatchController.bodies_kept(), "dropped with the cache")
	t.check(not is_instance_valid(prev[0]), "and freed")


## The chooser itself: both cards for whoever may pick (the chosen one
## marked by a check and the word, focus on it); for a guest only the
## host's map, read-only, with Close.
func test_map_sheet_editable_and_read_only() -> void:
	App.goto(PracticeScreen)
	await t.get_tree().process_frame
	var picked := [""]
	var root := MapSheet.open(App.screen, CampusMaps.CAMPUS, true, func(id: String) -> void: picked[0] = id)
	await t.get_tree().process_frame
	var cards := root.find_children("*", "Button", true, false).filter(func(b: Node) -> bool: return String((b as Button).accessibility_name).contains(" map. "))
	t.eq(cards.size(), 2, "two map cards")
	var sel := cards.filter(func(b: Node) -> bool: return String((b as Button).accessibility_name).ends_with("Selected."))
	t.eq(sel.size(), 1, "one marked selected (in words, not only colour)")
	t.check(String((sel[0] as Button).accessibility_name).begins_with("Lakeside Campus"), "the current map")
	var classic: Button = cards.filter(func(b: Node) -> bool: return String((b as Button).accessibility_name).begins_with("Moonbrook College"))[0]
	classic.pressed.emit()
	await t.get_tree().process_frame
	t.eq(picked[0], CampusMaps.CLASSIC, "a card picks its map")
	t.check(not is_instance_valid(root) or root.is_queued_for_deletion(), "and the sheet closes")
	var ro := MapSheet.open(App.screen, CampusMaps.CLASSIC, false, func(_id: String) -> void: picked[0] = "guest picked")
	await t.get_tree().process_frame
	var cards2 := ro.find_children("*", "Button", true, false).filter(func(b: Node) -> bool: return String((b as Button).accessibility_name).contains(" map. "))
	t.eq(cards2.size(), 1, "a guest sees the host's map only")
	t.eq((cards2[0] as Button).focus_mode, Control.FOCUS_NONE, "read-only: not focusable")
	t.check(String((cards2[0] as Button).accessibility_name).begins_with("Moonbrook College"), "the host's choice")
	var close := ro.find_children("*", "Button", true, false).filter(func(b: Node) -> bool: return (b as Button).text == "Close")
	t.eq(close.size(), 1, "with Close")
	ro.queue_free()
	App.goto_title()
