extends RefCounted
## 2.3 power-ups: Speed Sneakers (10 s), Squeaky Duck, Pillow Shield (no tag
## lands for 5 s); the Splash Bomb no longer spawns; every device works out
## the same item for each spot from the round's seed (the holograms).
var t

const R := TC.Role.RUNNER
const P := TC.Role.PATROL


func test_the_set_and_the_seeded_types() -> void:
	var keys: PackedStringArray = Rules.cfg.gadgets_enabled
	t.check(not keys.has("splash_bomb"), "the Splash Bomb is out of the set")
	t.check(keys.has("turbo") and keys.has("decoy") and keys.has("shield"), "sneakers, duck and shield")
	t.eq(Rules.cfg.turbo_duration_s, 10.0, "the sneakers last 10 s")
	var a := MatchSim.pickup_types(4242, keys, 16)
	var b := MatchSim.pickup_types(4242, keys, 16)
	t.eq(a, b, "the same seed gives the same items on every device")
	t.check(a.all(func(g: int) -> bool: return g in [TC.Gadget.TURBO, TC.Gadget.DECOY, TC.Gadget.SHIELD, TC.Gadget.CLOAK]), "only enabled items")
	t.check(a.has(TC.Gadget.SHIELD) and a.has(TC.Gadget.TURBO), "a round has a mix")
	for g in [TC.Gadget.TURBO, TC.Gadget.DECOY, TC.Gadget.SHIELD, TC.Gadget.CLOAK]:
		t.check(TC.GADGET_NAMES.has(g) and TC.GADGET_BLURBS.has(g) and Icons.gadget_icon(g) != "", "%s has a name, a blurb and an icon" % TC.GADGET_NAMES.get(g, g))


func test_the_shield_stops_a_tag() -> void:
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2])
	await h.release_patrol()
	var r := h.sim.player(0)
	# out on the campus (runners start safe in their dorm)
	h.place(0, (h.sim.pickups[0]["pos"] as Vector3) + Vector3(2.5, 0.05, 0))
	await h.step(3)
	t.check(r.is_taggable(), "taggable before (%s)" % [r.home_safe])
	r.gadget = TC.Gadget.SHIELD
	h.press(0, TC.BTN_GADGET)
	await h.step()
	t.eq(r.gadget, TC.Gadget.NONE, "used up")
	t.check(r.protect > Rules.cfg.shield_s - 0.2, "the shield is up (%.2f s)" % r.protect)
	t.check(not r.is_taggable(), "a tag can't land")
	# the Night Watch lunges at point-blank range: no capture while it lasts
	h.place(1, r.pos() + Vector3(0, 0, 1.0))
	h.sim.player(1).yaw = 0.0
	for i in 20:
		h.press(1, TC.BTN_TAG)
		await h.step()
	t.check(r.state != TC.PState.CAPTURED, "no capture through the pillow")
	await h.step(int(Rules.cfg.shield_s * 60.0))
	t.check(r.protect <= 0.0, "and it wears off")
	h.free_sim()


## (2.2 build 16) The Squeaky Duck lands with a squeak: a Night Watch near it
## trips and can't tag for a moment.
func test_the_duck_dazes_the_night_watch() -> void:
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2])
	await h.release_patrol()
	var r := h.sim.player(0)
	var w := h.sim.player(1)
	var at: Vector3 = (h.sim.pickups[0]["pos"] as Vector3) + Vector3(2.5, 0.05, 0)
	h.place(0, at)
	h.place(1, at + Vector3(0, 0, -6.0))
	await h.step(3)
	r.yaw = 0.0   # facing -z, toward the Night Watch
	r.gadget = TC.Gadget.DECOY
	h.press(0, TC.BTN_GADGET)
	var dazed := false
	for i in 90:
		await h.step()
		if not h.events_of(TC.Ev.DAZE).is_empty():
			dazed = true
			break
	t.check(dazed, "the duck dazes the Night Watch next to where it lands")
	t.check(w.tag_lockout > 1.5, "who can't tag for a moment (%.2f s)" % w.tag_lockout)
	h.free_sim()


## (2.2 build 16) A picked-up power-up comes back somewhere else.
func test_a_pickup_comes_back_elsewhere() -> void:
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2])
	await h.release_patrol()
	var pk: Dictionary = h.sim.pickups[0]
	var was: Vector3 = pk["pos"]
	h.place(0, was + Vector3(0, 0.05, 0))
	await h.step(2)
	t.check(h.sim.player(0).gadget != TC.Gadget.NONE, "picked up")
	h.place(0, was + Vector3(30, 0.05, 30))
	await h.step(int(Rules.cfg.gadget_respawn_s * 60.0) + 5)
	t.check(float(pk["respawn"]) <= 0.0, "it's back")
	t.check((pk["pos"] as Vector3).distance_to(was) > 3.0, "at another spot (%s -> %s)" % [str(was), str(pk["pos"])])
	var spots := {}
	for q in h.sim.pickups:
		t.check(not spots.has(int(q["spot"])), "never two on one spot")
		spots[int(q["spot"])] = true
	h.free_sim()


## (2.2 build 17) The Invisibility Cloak: the Night Watch don't see the
## runner while it lasts (their perception and their devices), then it fades.
func test_the_cloak_hides_you() -> void:
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2])
	await h.release_patrol()
	var r := h.sim.player(0)
	var w := h.sim.player(1)
	var at: Vector3 = (h.sim.pickups[0]["pos"] as Vector3) + Vector3(2.5, 0.05, 0)
	h.place(0, at)
	h.place(1, at + Vector3(0, 0, 6.0))
	w.yaw = 0.0   # facing the runner (-z)
	await h.step(8)
	r.gadget = TC.Gadget.CLOAK
	h.press(0, TC.BTN_GADGET)
	await h.step(8)
	t.check(r.cloak_t > Rules.cfg.cloak_s - 0.5, "cloaked (%.2f s)" % r.cloak_t)
	r.spotted = 0.0   # (any sighting from before the cloak)
	var seen_while := false
	for i in 60:
		await h.step()
		if r.spotted > 0.9:
			seen_while = true
	t.check(not seen_while, "not spotted while cloaked")
	await h.step(int(Rules.cfg.cloak_s * 60.0))
	t.check(r.cloak_t <= 0.0, "and it wears off")
	h.free_sim()


## (build 35) "The squeaky duck doesn't do anything": thrown while fleeing
## (aimed away from the Night Watch) it used to land 9 m ahead, far from the
## chaser, and nothing drew it.  Now it flies at the nearest Night Watch in
## sight, dazes them, says so (Ev.DUCK) and squeaks where it lies.
func test_a_duck_thrown_while_fleeing_still_dazes_the_chaser() -> void:
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2])
	await h.release_patrol()
	var r := h.sim.player(0)
	var w := h.sim.player(1)
	var at: Vector3 = (h.sim.pickups[0]["pos"] as Vector3) + Vector3(2.5, 0.05, 0)
	h.place(0, at, 0.0)
	h.place(1, at + Vector3(0, 0, 7.0), 0.0)    # 7 m behind the runner
	await h.step(3)
	r.gadget = TC.Gadget.DECOY
	h.cmd(0).move = Vector2(0, -1)              # running away, stick forward
	h.cmd(0).cam_yaw = 0.0
	h.press(0, TC.BTN_GADGET)
	var duck := {}
	for i in 90:
		await h.step()
		for e in h.sim.events:
			if int(e["type"]) == TC.Ev.DUCK:
				duck = e
		if not duck.is_empty():
			break
	t.check(not duck.is_empty(), "the duck lands and says so")
	t.eq(int(duck.get("v", -1)), 1, "dazing the Night Watch behind the thrower")
	t.check(w.tag_lockout > 1.5, "who can't tag for a moment (%.2f s)" % w.tag_lockout)
	t.check(h.sim.decoys.size() == 1, "and it lies there squeaking")
	h.cmd(0).move = Vector2.ZERO
	h.free_sim()


func test_a_duck_nobody_is_near_says_so() -> void:
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2])
	await h.release_patrol()
	var r := h.sim.player(0)
	var at: Vector3 = (h.sim.pickups[0]["pos"] as Vector3) + Vector3(2.5, 0.05, 0)
	h.place(0, at, 0.0)
	h.place(1, at + Vector3(0, 0, 40.0), 0.0)
	await h.step(3)
	r.gadget = TC.Gadget.DECOY
	h.press(0, TC.BTN_GADGET)
	var e := await h.wait_event(TC.Ev.DUCK, 90)
	t.check(not e.is_empty() and int(e["v"]) == 0 and int(e["a"]) == 0, "a squeak that dazed nobody (the thrower is told) %s, watch %.1f m away" % [str(e), h.sim.player(1).pos().distance_to(at)])
	h.free_sim()


func test_night_watch_bots_go_to_a_squeaking_duck() -> void:
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2], [1])
	await h.release_patrol()
	var w := h.sim.player(1)
	var at: Vector3 = (h.sim.pickups[0]["pos"] as Vector3) + Vector3(2.5, 0.05, 0)
	h.place(0, at + Vector3(0, 0, 30.0), PI)
	h.place(1, at + Vector3(16.0, 0, 0), PI * 0.5)
	h.sim.decoys.append({"pos": at, "dir": Vector3(1, 0, 0), "t": 5.0, "flight": 0.0, "owner": 0, "from": at})
	var d0 := w.pos().distance_to(at)
	await h.step(150)
	t.check(w.pos().distance_to(at) < d0 - 5.0, "a Night Watch bot with nobody to chase goes to the squeak (%.1f -> %.1f m)" % [d0, w.pos().distance_to(at)])
	h.free_sim()


func test_the_duck_is_drawn_on_every_device() -> void:
	var v := DuckView.new()
	t.add_child(v)
	t.check(not v.visible, "nothing until a duck is out")
	v.show_at(Vector3(3, 0, 4), true)
	v._process(0.1)
	t.check(v.visible, "in the air")
	v.show_at(Vector3(3, 0, 4), false)
	v._process(0.2)
	t.check(v.visible and v._label.visible and v._ring.visible, "on the ground: the duck, its SQUEAK! sign and its reach")
	v.hide_duck()
	t.check(not v.visible, "gone when it's done")
	v.queue_free()
