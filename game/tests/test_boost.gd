extends RefCounted
## (2.2 build 20) The running boost: a press on foot when the bar is full
## gives boost_duration_s of extra speed (runner or Night Watch); then the
## bar refills over boost_recharge_s and a press does nothing until it has.
var t

const R := TC.Role.RUNNER
const P := TC.Role.PATROL


func _speed(h: SimHarness, slot: int) -> float:
	var v := h.sim.player(slot).vel
	return Vector2(v.x, v.z).length()


func _run(h: SimHarness, slot: int) -> void:
	h.cmd(slot).move = Vector2(0, -1)


## An open lawn spot with room to run north (the rift spots are open ground).
func _open(h: SimHarness) -> Vector3:
	for v in Rifts.spots(h.sim.layout):
		var ok := true
		for k in 8:
			var q := (v as Vector2) + Vector2(0, -3.0 * float(k + 1))
			if not h.sim.layout._open_ground(q, 1.0):
				ok = false
				break
		if ok:
			return h.on_ground(v)
	return h.on_ground(Rifts.spots(h.sim.layout)[0])


func test_a_press_gives_three_seconds_of_extra_speed() -> void:
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2])
	await h.release_patrol()
	var cfg: RulesConfig = h.sim.cfg
	h.place(0, _open(h))
	_run(h, 0)
	await h.step(60)
	var plain := _speed(h, 0)
	t.check(absf(plain - cfg.runner_speed) < 0.3, "running at the steady speed first (%.2f)" % plain)
	h.press(0, TC.BTN_BOOST)
	await h.step(45)
	var fast := _speed(h, 0)
	t.check(h.sim.player(0).boost_t > 0.0, "boosting")
	t.check(fast > plain * 1.2, "faster while boosting (%.2f vs %.2f)" % [fast, plain])
	t.check(fast <= cfg.boost_speed_cap + 0.05, "never past the cap")
	await h.step(int(cfg.boost_duration_s * 60.0))
	t.eq(h.sim.player(0).boost_t, 0.0, "the boost runs out after %.0f s" % cfg.boost_duration_s)
	t.check(h.sim.player(0).boost_cd > cfg.boost_recharge_s - 1.5, "and the bar starts refilling")
	await h.step(30)
	t.check(absf(_speed(h, 0) - plain) < 0.3, "back to the steady speed")
	h.free_sim()


func test_no_second_boost_until_the_bar_refills() -> void:
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2])
	await h.release_patrol()
	var cfg: RulesConfig = h.sim.cfg
	h.place(0, _open(h))
	_run(h, 0)
	h.press(0, TC.BTN_BOOST)
	await h.step(2)
	var first := h.sim.player(0).boost_t
	# pressing again while it runs does nothing (it doesn't restart)
	await h.step(30)
	h.press(0, TC.BTN_BOOST)
	await h.step(1)
	t.check(h.sim.player(0).boost_t < first - 0.4, "a press while boosting doesn't restart it")
	await h.step(int(cfg.boost_duration_s * 60.0))
	# recharging: a press does nothing
	h.press(0, TC.BTN_BOOST)
	await h.step(2)
	t.eq(h.sim.player(0).boost_t, 0.0, "a press while recharging does nothing")
	await h.step(int(cfg.boost_recharge_s * 60.0) + 5)
	t.eq(h.sim.player(0).boost_cd, 0.0, "the bar is full again after %.0f s" % cfg.boost_recharge_s)
	h.press(0, TC.BTN_BOOST)
	await h.step(2)
	t.check(h.sim.player(0).boost_t > 0.0, "and the next press boosts")
	h.free_sim()


func test_the_night_watch_can_boost_too_but_not_in_a_cart() -> void:
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2])
	await h.release_patrol()
	var w := h.sim.player(1)
	if w.cart_id >= 0:
		(h.sim.carts[w.cart_id] as SimCart).occupant = -1
		w.cart_id = -1
		Motor.set_body_enabled(w.body, true)
		w.state = TC.PState.ACTIVE
	h.place(1, _open(h))
	_run(h, 1)
	h.press(1, TC.BTN_BOOST)
	await h.step(2)
	t.check(w.boost_t > 0.0, "a Night Watch on foot boosts")
	h.free_sim()
	# driving: nothing
	var h2 := SimHarness.new(t)
	h2.make([R, P], [0, 1, 2])
	await h2.release_patrol()
	var w2 := h2.sim.player(1)
	var c: SimCart = h2.sim.carts[0]
	c.occupant = w2.id
	w2.cart_id = 0
	w2.state = TC.PState.IN_CART
	Motor.set_body_enabled(w2.body, false)
	h2.press(1, TC.BTN_BOOST)
	await h2.step(2)
	t.eq(w2.boost_t, 0.0, "no boost while driving")
	h2.free_sim()


func test_a_tag_ends_a_boost_and_it_still_recharges() -> void:
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2])
	await h.release_patrol()
	h.place(0, _open(h))
	_run(h, 0)
	h.press(0, TC.BTN_BOOST)
	await h.step(2)
	h.sim._capture(h.sim.player(0), h.sim.player(1))
	t.eq(h.sim.player(0).boost_t, 0.0, "tagged: the boost stops")
	t.check(h.sim.player(0).boost_cd > 0.0, "and the bar has to refill")
	h.free_sim()


func test_the_boost_travels_with_the_motor_state() -> void:
	# the owner's device predicts its own boost: it is part of the motor
	# state a guest reconciles to
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2])
	await h.release_patrol()
	var p := h.sim.player(0)
	p.boost_t = 1.25
	p.boost_cd = 0.0
	var b := StreamPeerBuffer.new()
	p.write_motor(b)
	b.seek(0)
	var d := p.read_motor(b)
	t.check(absf(float(d["boost_t"]) - 1.25) < 0.001, "boost time in the motor state")
	p.boost_t = 0.0
	p.boost_cd = 7.5
	b = StreamPeerBuffer.new()
	p.write_motor(b)
	b.seek(0)
	d = p.read_motor(b)
	t.check(absf(float(d["boost_cd"]) - 7.5) < 0.001, "recharge time too")
	h.free_sim()
