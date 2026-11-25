extends RefCounted
## (build 35) "Other players should be able to drive the cop carts if they
## find them, except hitting other players won't do anything": a runner can
## take an empty Night Watch cart and drive it; their cart never tags,
## stumbles or launches anyone (people in its way are only nudged aside);
## a Night Watch on foot can still tag the runner at the wheel; Night Watch
## bots carry on with the other cart.  Also: no Boost for the Night Watch.
var t
const R := TC.Role.RUNNER
const P := TC.Role.PATROL


func _seat(h: SimHarness, slot: int, ci: int) -> void:
	var c: SimCart = h.sim.carts[ci]
	h.place(slot, c.pos() + c.right() * -1.5)
	await h.step()
	h.press(slot, TC.BTN_INTERACT)
	await h.step(30)


func test_a_runner_drives_an_empty_cart_and_gets_out() -> void:
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2])
	await h.release_patrol()
	var r := h.sim.player(0)
	var c: SimCart = h.sim.carts[0]
	await _seat(h, 0, 0)
	t.eq(r.state, TC.PState.IN_CART, "a runner beside an empty cart takes the wheel")
	t.eq(c.occupant, 0, "the cart is theirs")
	h.cmd(0).drive = 1.0
	await h.step(120)
	t.check(c.speed > 5.0, "and drives it (%.1f m/s)" % c.speed)
	h.cmd(0).drive = 0.0
	h.press(0, TC.BTN_INTERACT)
	var out := false
	for i in 240:
		await h.step()
		if r.state == TC.PState.ACTIVE or r.state == TC.PState.EXITING:
			out = true
			break
	t.check(out, "and gets out again")
	t.eq(c.occupant, -1, "leaving it empty")
	# a Night Watch can take it now
	await _seat(h, 1, 0)
	t.eq(h.sim.player(1).state, TC.PState.IN_CART, "the Night Watch drives it as before")
	h.free_sim()


## A runner at the wheel at full speed straight at someone on foot.
func _ram(victim_role: int) -> Dictionary:
	var h := SimHarness.new(t)
	h.make([R, victim_role], [0, 1, 2])
	await h.release_patrol()
	var c: SimCart = h.sim.carts[0]
	var r := h.sim.player(0)
	c.body.global_position = h.on_ground(Vector2(-40, -58), 0.3)
	c.yaw = -PI * 0.5
	c.body.rotation.y = c.yaw
	c.occupant = 0
	r.cart_id = 0
	r.state = TC.PState.IN_CART
	Motor.set_body_enabled(r.body, false)
	h.place(1, h.on_ground(Vector2(-28, -58)))
	var v := h.sim.player(1)
	var start := v.pos()
	h.cmd(0).drive = 1.0
	var out := {"captures": 0, "bumps": 0, "peak_up": 0.0, "max_v": 0.0, "states": {}, "overlap_ticks": 0}
	for i in 160:
		await h.step()
		out["captures"] = int(out["captures"]) + h.events_of(TC.Ev.CAPTURE).size()
		out["bumps"] = int(out["bumps"]) + h.events_of(TC.Ev.BUMP).size()
		out["peak_up"] = maxf(float(out["peak_up"]), v.pos().y - start.y)
		out["max_v"] = maxf(float(out["max_v"]), Vector2(v.vel.x, v.vel.z).length())
		(out["states"] as Dictionary)[v.state] = true
		if c.overlaps(v.pos(), 0.0):
			out["overlap_ticks"] = int(out["overlap_ticks"]) + 1
	out["moved"] = Vector2(v.pos().x - start.x, v.pos().z - start.z).length()
	h.free_sim()
	return out


func test_a_runners_cart_never_tags_or_launches_anyone() -> void:
	for role in [R, P]:
		var o: Dictionary = await _ram(role)
		var who := "a runner" if role == R else "the Night Watch"
		print("RUNNERCART ram %s: %s" % [who, str(o)])
		t.eq(int(o["captures"]), 0, "a runner's cart never tags %s" % who)
		t.eq(int(o["bumps"]), 0, "nor bumps them into a stumble")
		t.check(not (o["states"] as Dictionary).has(TC.PState.STUMBLE) and not (o["states"] as Dictionary).has(TC.PState.CAPTURED), "%s stays on their feet" % who)
		t.check(float(o["peak_up"]) < 0.5, "nobody is launched (%.2f m up)" % float(o["peak_up"]))
		t.check(float(o["max_v"]) <= Rules.cfg.cart_nudge_speed + 0.6, "only a gentle push (%.1f m/s at most)" % float(o["max_v"]))
		t.check(int(o["overlap_ticks"]) <= 6, "and never left inside the cart (%d ticks)" % int(o["overlap_ticks"]))


func test_the_night_watch_can_tag_a_runner_at_the_wheel() -> void:
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2])
	await h.release_patrol()
	var r := h.sim.player(0)
	var c: SimCart = h.sim.carts[0]
	await _seat(h, 0, 0)
	t.eq(r.state, TC.PState.IN_CART, "seated")
	t.check(r.is_taggable(), "a runner at the wheel can be tagged")
	# the Night Watch walks up to the driver's side and tags
	var side := c.pos() + c.right() * -1.7
	var face := c.pos() - side
	h.place(1, Vector3(side.x, h.gy(Vector2(side.x, side.z)) + 0.05, side.z), atan2(-face.x, -face.z))
	await h.step(3)
	var caught := false
	for i in 40:
		h.cmd(1).cam_yaw = atan2(-face.x, -face.z)
		h.press(1, TC.BTN_TAG)
		await h.step()
		if r.state == TC.PState.CAPTURED:
			caught = true
			break
	t.check(caught, "a lunge at the seat tags them")
	t.eq(c.occupant, -1, "and the cart is left empty")
	t.eq(r.cart_id, -1, "the runner is out of it")
	h.free_sim()


func test_night_watch_bots_use_the_other_cart() -> void:
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2], [1], 77)
	await h.release_patrol()
	var w := h.sim.player(1)
	var br: BotBrain = h.sim.bots[1]
	# a runner takes the bot's own cart and parks there
	await _seat(h, 0, br.pref_cart)
	t.eq(h.sim.carts[br.pref_cart].occupant, 0, "the runner holds the bot's cart")
	var p0 := w.pos2()
	var moved := 0.0
	for i in 60 * 12:
		await h.step()
		moved = maxf(moved, w.pos2().distance_to(p0))
	t.eq(h.sim.carts[br.pref_cart].occupant, 0, "the bot never takes a cart someone is in")
	t.check(moved > 15.0 or w.state == TC.PState.IN_CART, "and gets on with its round (%.0f m, state %d)" % [moved, w.state])
	h.free_sim()


func test_drive_shows_for_a_runner_beside_a_cart_and_no_boost_for_the_watch() -> void:
	var s := TouchControls.TouchSurface.new()
	var c := {"st": TC.PState.ACTIVE, "role": TC.Role.RUNNER, "in_cart": false, "near_cart": false, "gadget": 0,
		"phase": TC.Phase.PLAYING, "airborne": false, "watching": false}
	t.check(not s.visible_set(c).has("cart"), "no Drive for a runner away from carts")
	c["near_cart"] = true
	t.check(s.visible_set(c).has("cart"), "Drive for a runner beside an empty cart")
	t.check(TouchLayout.SLOTS["runner"].has("cart"), "with its own slot on the runner's cluster")
	c["role"] = TC.Role.PATROL
	t.check(not s.visible_set(c).has("boost"), "no Boost button for the Night Watch")
	c["role"] = TC.Role.RUNNER
	c["near_cart"] = false
	t.check(s.visible_set(c).has("boost"), "runners keep theirs")
	s.free()


## (build 35 review) Hide and Drive are the same press: beside a bush a
## runner hides, even with an empty cart in reach (the cart won before, and
## a runner bot looped in and out of the cart).
func test_beside_a_bush_the_press_hides_not_drives() -> void:
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2])
	await h.release_patrol()
	var bush: Vector2 = HideBushes.spots(h.sim.layout)[0]
	var c: SimCart = h.sim.carts[0]
	c.body.global_position = h.on_ground(bush + Vector2(2.6, 0.0), 0.3)
	h.place(0, h.on_ground(bush + Vector2(0.9, 0.0)))
	await h.step()
	t.check(HideBushes.near(h.sim.layout, h.sim.player(0).pos2()) >= 0, "the runner is beside a bush")
	t.check(c.pos().distance_to(h.sim.player(0).pos()) < h.sim.cfg.cart_enter_range_m, "and an empty cart is in reach")
	h.press(0, TC.BTN_INTERACT)
	await h.step(30)
	t.check(h.sim.player(0).state != TC.PState.IN_CART and c.occupant != 0, "the press hides: no cart (state %d)" % h.sim.player(0).state)
	t.eq(h.sim.player(0).state, TC.PState.HIDING, "in the bush")
	h.free_sim()


## (build 35 review) A runner tagged at the wheel at speed leaves an empty
## cart that brakes itself, not one coasting ~20 m into people.
func test_an_emptied_cart_brakes_itself() -> void:
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2])
	await h.release_patrol()
	var r := h.sim.player(0)
	var c: SimCart = h.sim.carts[0]
	await _seat(h, 0, 0)
	h.cmd(0).drive = 1.0
	await h.step(150)
	var v0 := c.speed
	t.check(v0 > 6.0, "driving fast (%.1f m/s)" % v0)
	h.sim._leave_cart(r)
	var start := c.pos()
	await h.step(90)
	t.check(c.occupant == -1 and absf(c.speed) < 0.5, "the empty cart has stopped (%.2f m/s)" % c.speed)
	t.check(c.pos().distance_to(start) < 12.0, "within a short distance (%.1f m)" % c.pos().distance_to(start))
	h.free_sim()
