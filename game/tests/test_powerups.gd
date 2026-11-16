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
	t.check(a.all(func(g: int) -> bool: return g in [TC.Gadget.TURBO, TC.Gadget.DECOY, TC.Gadget.SHIELD]), "only enabled items")
	t.check(a.has(TC.Gadget.SHIELD) and a.has(TC.Gadget.TURBO), "a round has a mix")
	for g in [TC.Gadget.TURBO, TC.Gadget.DECOY, TC.Gadget.SHIELD]:
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
