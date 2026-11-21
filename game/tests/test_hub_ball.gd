extends RefCounted
## (build 24) The party room's basketball, its physics (HubBall): it bounces
## and comes to rest on the floor, rolls off anything it lands on (never
## stuck on the couch, the shelf, the tree, the beanbag or the hoop), stays
## in the room and reachable whatever is thrown at it, a clean shot goes in
## and a near miss mostly doesn't, runners walking into it knock it along,
## and it starts somewhere different and open each time.
var t


func _settle(b: HubBall, seconds: float) -> float:
	var s := 0.0
	while s < seconds:
		b.step(1.0 / 60.0)
		s += 1.0 / 60.0
		if b.sleeping:
			return s
	return s


func test_drop_bounces_and_rests_on_the_floor() -> void:
	var b := HubBall.new()
	b.launch(Vector3(0.5, 1.5, 1.8), Vector3.ZERO)
	var bounces := 0
	var top := 0.0
	var tops: Array = []
	for i in 600:
		b.step(1.0 / 60.0)
		var hit := false
		for e in b.events:
			if e.has("kind") and int(e["kind"]) == HubBall.Kind.FLOOR:
				hit = true
		if hit:
			if bounces > 0:
				tops.append(top)
			bounces += 1
			top = 0.0
		top = maxf(top, b.pos.y)
		if b.sleeping:
			break
	t.check(b.sleeping, "it comes to rest")
	t.near(b.pos.y, HubBall.R, 0.003, "on the floor")
	t.check(bounces >= 4, "it bounces a few times (%d)" % bounces)
	t.check(tops.size() >= 2 and float(tops[0]) > float(tops[1]), "each bounce lower than the last %s" % [tops])
	t.check(float(tops[0]) > 0.5 and float(tops[0]) < 1.0, "a lively first bounce (%.2f m from 1.5 m)" % float(tops[0]))


func test_rolls_off_every_piece_of_furniture() -> void:
	# dropped onto the top of each thing in the room, it always ends up on
	# the floor where a runner can pick it up
	var spots := {
		"couch seat": Vector3(-3.6, 0.9, -2.6), "couch back": Vector3(-3.0, 1.6, -3.17),
		"couch arm": Vector3(-5.02, 1.1, -2.7), "side table": Vector3(-1.75, 0.5, -1.95),
		"table lamp": Vector3(-2.1, 1.0, -2.2), "bookshelf": Vector3(5.1, 2.4, -2.9),
		"mantel": Vector3(-5.6, 1.7, -1.15), "floor lamp shade": Vector3(3.9, 2.1, -1.9),
		"armchair seat": DormStage.ARMCHAIR + Vector3(0, 0.95, 0), "armchair back": DormStage.ARMCHAIR + Basis(Vector3.UP, -0.55) * Vector3(0, 1.5, -0.38),
		"tree top": HolidayDecor.TREE + Vector3(0.05, 2.9, 0.05), "tree side": HolidayDecor.TREE + Vector3(0.3, 1.2, 0.5),
		"present": Vector3(1.62, 0.6, -2.06), "plant": Vector3(-5.3, 1.6, 1.6),
		"beanbag": Vector3(4.0, 1.0, 1.1), "beanbag middle": Vector3(4.0, 0.9, 1.15), "cushion": Vector3(-2.1, 0.5, -1.55),
		"hoop board": HubBall.rim_center() + Vector3(0, 0.6, 0) + Vector3(HubBall.HOOP_DIR.x, 0, HubBall.HOOP_DIR.y) * -0.2,
		"hoop base": Vector3(HubBall.HOOP_BASE.x + 0.1, 0.5, HubBall.HOOP_BASE.y), "on the rim": HubBall.rim_center() + Vector3(HubBall.RIM_R, 0.2, 0),
	}
	for name in spots:
		var b := HubBall.new()
		b.rng.seed = 7
		b.launch(spots[name], Vector3.ZERO)
		_settle(b, 12.0)
		var reach := HubBall.reachable(b.pos)
		t.check(b.sleeping and b.pos.y <= HubBall.R + 0.01 and reach,
			"%s: rolled off onto open floor (at %s, resting %s, reachable %s)" % [name, b.pos, b.sleeping, reach])


func test_never_stuck_whatever_is_thrown() -> void:
	# 300 random throws from anywhere in the room, in any direction: the
	# ball always ends up resting on the floor, in the room, reachable
	var r := RandomNumberGenerator.new()
	r.seed = 2401
	var bad := 0
	var rescued := 0
	var worst := 0.0
	for i in 300:
		var b := HubBall.new()
		b.rng.seed = i
		var p := Vector3(r.randf_range(-5.5, 5.4), r.randf_range(0.2, 2.6), r.randf_range(-3.3, 2.9))
		var v := Vector3(r.randf_range(-7, 7), r.randf_range(-2, 7), r.randf_range(-7, 7))
		b.launch(p, v)
		var s := 0.0
		var saw_rescue := false
		while s < 20.0 and not (b.sleeping and HubBall.reachable(b.pos)):
			b.step(1.0 / 30.0)
			s += 1.0 / 30.0
			for e in b.events:
				if e.has("rescue"):
					saw_rescue = true
		if saw_rescue:
			rescued += 1
		worst = maxf(worst, s)
		var ok := b.sleeping and HubBall.reachable(b.pos) and b.pos.y < HubBall.R + 0.01 \
			and b.pos.x > -6.0 and b.pos.x < 5.8 and b.pos.z > -3.5 and b.pos.z < 3.15
		if not ok:
			bad += 1
			if bad <= 5:
				t.check(false, "throw %d from %s at %s ended at %s (resting %s)" % [i, p, v, b.pos, b.sleeping])
	t.eq(bad, 0, "every throw ends on reachable floor (slowest %.1f s, %d needed a rescue)" % [worst, rescued])
	t.check(rescued <= 6, "the rescue is a last resort (%d of 300)" % rescued)


func _shoot(from: Vector2, make: bool, seed_v: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var rc := HubBall.rim_center()
	var dir := (Vector2(rc.x, rc.z) - from).normalized()
	var start := Vector3(from.x + dir.x * 0.1, 1.2, from.y + dir.y * 0.1)
	var aim := BallSync.shot_aim(from, make, r)
	var d := Vector2(aim.x - start.x, aim.z - start.z).length()
	var b := HubBall.new()
	b.launch(start, BallSync.ballistic(start, aim, BallSync.shot_time(d)))
	var made := false
	var swish := false
	var rim := false
	for i in 360:
		b.step(1.0 / 60.0)
		for e in b.events:
			if e.has("make"):
				made = true
				swish = bool(e["swish"])
			elif e.has("kind") and int(e["kind"]) in [HubBall.Kind.RIM, HubBall.Kind.BOARD]:
				rim = true
	return {"made": made, "swish": swish, "rim": rim, "end": b.pos}


func test_shots_make_and_miss() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 77
	var makes := 0
	var swishes := 0
	var miss_in := 0
	var n := 0
	var froms: Array = []
	while froms.size() < 40:
		var p := Vector2(r.randf_range(-1.0, 4.0), r.randf_range(-1.6, 2.4))
		var rc := HubBall.rim_center()
		if HubRoom.is_free(p) and (p - Vector2(rc.x, rc.z)).dot(HubBall.HOOP_DIR) > 0.4:
			froms.append(p)
	for p in froms:
		n += 1
		var m := _shoot(p, true, n)
		if bool(m["made"]):
			makes += 1
		if bool(m["swish"]):
			swishes += 1
		var x := _shoot(p, false, n * 31)
		if bool(x["made"]):
			miss_in += 1
	t.check(makes >= 38, "a clean shot goes in (%d of 40)" % makes)
	t.check(swishes >= 30, "and mostly touches nothing (%d swishes)" % swishes)
	t.check(miss_in <= 10, "a near miss rarely rattles in (%d of 40)" % miss_in)


func test_make_chance_by_distance() -> void:
	var rc := HubBall.rim_center()
	var f := Vector2(rc.x, rc.z) + HubBall.HOOP_DIR
	var near := BallSync.make_chance(Vector2(rc.x, rc.z) + HubBall.HOOP_DIR * 1.0)
	var mid := BallSync.make_chance(Vector2(rc.x, rc.z) + HubBall.HOOP_DIR * 3.0)
	var far := BallSync.make_chance(Vector2(rc.x, rc.z) + HubBall.HOOP_DIR * 7.0)
	var behind := BallSync.make_chance(Vector2(rc.x, rc.z) - HubBall.HOOP_DIR * 0.6)
	t.check(near > mid and mid > far, "closer is likelier (%.2f > %.2f > %.2f)" % [near, mid, far])
	t.check(near < 0.95 and far >= 0.15, "never certain, never hopeless")
	t.eq(behind, 0.0, "not from behind the board")
	t.check(f != Vector2.ZERO, "")


func test_runner_walking_into_it_knocks_it_along() -> void:
	var b := HubBall.new()
	b.place(Vector3(0.0, HubBall.R, 1.8))
	var me := Vector2(-0.8, 1.8)
	for i in 60:
		me.x += HubRoom.WALK_SPEED / 60.0
		b.players = [[me, Vector2(HubRoom.WALK_SPEED, 0), 3]]
		b.step(1.0 / 60.0)
	t.check(b.pos.x > me.x, "the ball goes on ahead (ball %.2f, runner %.2f)" % [b.pos.x, me.x])
	t.check(b.vel.x > 1.0, "rolling away (%.2f m/s)" % b.vel.x)
	# the holder / a ghost passes through it
	var g := HubBall.new()
	g.place(Vector3(0.0, HubBall.R, 1.8))
	g.ghost = {3: true}
	g.players = [[Vector2(0.0, 1.8), Vector2(HubRoom.WALK_SPEED, 0), 3]]
	g.step(0.2)
	t.check(g.sleeping and g.pos.x == 0.0, "a ghost doesn't touch it")


func test_spawn_spots_are_open_and_vary() -> void:
	var seen := {}
	for i in 40:
		var r := RandomNumberGenerator.new()
		r.seed = i * 977 + 5
		var p := HubBall.spawn_spot(r)
		var f := Vector2(p.x, p.z)
		t.check(HubRoom.is_free(f) and HubBall.reachable(p), "spot %s is open floor" % p)
		for m in DormStage.MARKS:
			t.check(f.distance_to(Vector2((m as Vector3).x, (m as Vector3).z)) >= 0.75, "spot %s is off the marks" % p)
		seen["%d,%d" % [int(round(p.x)), int(round(p.z))]] = true
	t.check(seen.size() >= 7, "a different place each time (%d distinct)" % seen.size())


func test_the_hoop_base_is_an_obstacle() -> void:
	t.check(not HubRoom.is_free(HubBall.HOOP_BASE), "nobody stands in the hoop's base")
	t.check(HubRoom.is_free(HubBall.HOOP_BASE + HubBall.HOOP_DIR * 0.9), "the shooting spot in front is open")
