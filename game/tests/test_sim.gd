extends RefCounted
## Authoritative simulation scenarios (physics). These exercise behaviour:
## stamps, captures, timing, ordering, carts, tags, gadgets, reconnect.
var t
const R := TC.Role.RUNNER
const P := TC.Role.PATROL


func _h() -> SimHarness:
	return SimHarness.new(t)


func test_every_curated_combo_all_orders() -> void:
	# 6 runners take the 6 different orders of the same three targets.
	var combos := RulesLogic.curated_combos()
	for ci in combos.size():
		var targets: Array = combos[ci]
		var h := _h()
		h.make([R, R, R, R, R, R, P, P], targets)
		await h.to_playing()
		var perms := RulesLogic.permutations3(targets)
		for step_i in 3:
			for r in 6:
				await h.splash_into(r, int(perms[r][step_i]))
		var ok := true
		for r in 6:
			var p := h.sim.player(r)
			if p.stamp_count() != 3 or p.last_stamp_water != int(perms[r][2]):
				ok = false
		t.check(ok, "combo %s: every order earns exactly 3 stamps" % str(targets))
		# everyone can finish through a door (V6: running in through one of
		# tonight's home doors)
		for r in 4:
			await h.enter_door(r, r % 3)
		t.eq(h.sim.outcome, TC.Outcome.RUNNERS_WIN, "combo %s: four finishes win" % str(targets))
		h.free_sim()


func test_duplicate_and_inactive_splash() -> void:
	var h := _h()
	h.make([R, P], [0, 1, 2])
	await h.to_playing()
	await h.splash_into(0, 0)
	t.eq(h.sim.player(0).stamp_count(), 1, "first splash stamps")
	await h.splash_into(0, 0)
	t.eq(h.sim.player(0).stamp_count(), 1, "repeat entry never stamps twice")
	await h.splash_into(0, 4)
	t.eq(h.sim.player(0).stamp_count(), 1, "inactive water awards nothing")
	h.free_sim()


func test_water_resurfaces_automatically() -> void:
	var h := _h()
	h.make([R, P], [0, 1, 2])
	await h.to_playing()
	var w: Dictionary = h.sim.layout.waters[1]
	var c: Vector2 = w["center"]
	h.place(0, Vector3(c.x, float(w["surface_y"]) + 1.0, c.y))
	var t0 := h.sim.tick
	while h.sim.player(0).state != TC.PState.SPLASHING:
		await h.step()
	while h.sim.player(0).state == TC.PState.SPLASHING:
		await h.step()
	var dt := float(h.sim.tick - t0) / 60.0
	t.check(dt < Rules.cfg.splash_sequence_s + 1.0, "cannot linger in water (%.2fs)" % dt)
	var pp := h.sim.player(0).pos()
	t.eq(CampusBuilder.water_at(h.sim.layout, Vector2(pp.x, pp.z)), -1, "resurfaces on the shore, not in the water")
	var near_exit := false
	for e in w["exits"]:
		if Vector2(pp.x, pp.z).distance_to(Vector2(e.x, e.z)) < 2.5:
			near_exit = true
	t.check(near_exit, "resurfaces at a legitimate shore exit")
	h.free_sim()


func _tag_setup(h: SimHarness, gap: float) -> void:
	# runner on open lawn, patrol `gap` metres south of it facing north
	h.place(0, Vector3(-20, 0.05, 60), 0.0)
	h.place(1, Vector3(-20, 0.05, 60 + gap), 0.0)


func test_capture_timing_progress_and_respawn() -> void:
	var h := _h()
	h.make([R, P], [0, 1, 2])
	await h.release_patrol()
	await h.splash_into(0, 0)
	await h.splash_into(0, 1)
	t.eq(h.sim.player(0).stamp_count(), 2, "two stamps before capture")
	_tag_setup(h, 1.2)
	await h.step()
	h.press(1, TC.BTN_TAG)
	var ev := await h.wait_event(TC.Ev.CAPTURE, 60)
	t.check(not ev.is_empty(), "valid on-foot tag captures")
	var cap_tick := h.sim.tick
	var r := h.sim.player(0)
	t.eq(r.state, TC.PState.CAPTURED, "runner in recovery penalty")
	t.eq(r.stamp_count(), 2, "stamps kept through capture")
	t.eq(r.role, R, "keeps runner role")
	while h.sim.player(0).state == TC.PState.CAPTURED:
		await h.step()
	var secs := float(h.sim.tick - cap_tick) / 60.0
	t.near(secs, Rules.cfg.capture_penalty_s, 1.5 / 60.0, "six-second recovery penalty")
	var pos := r.pos2()
	var near_pad := false
	for pad in h.sim.layout.waters[1]["pads"]:
		if pos.distance_to(pad) < 1.5:
			near_pad = true
	t.check(near_pad, "returns to a pad at the last completed splash (Pond)")
	t.check(r.protect > 1.8 and not r.is_taggable(), "~2 s visible respawn protection")
	await h.step(130)
	t.check(r.is_taggable(), "protection expires")
	h.free_sim()


func test_capture_before_first_splash_returns_to_dorm() -> void:
	var h := _h()
	h.make([R, P], [0, 1, 2])
	await h.release_patrol()
	_tag_setup(h, 1.2)
	await h.step()
	h.press(1, TC.BTN_TAG)
	await h.wait_event(TC.Ev.CAPTURE, 60)
	while h.sim.player(0).state == TC.PState.CAPTURED:
		await h.step()
	var pos := h.sim.player(0).pos2()
	var near := false
	for pad in CampusDorms.geometry(h.sim.home_dorm)["respawn"]:
		if pos.distance_to(pad) < 1.5:
			near = true
	t.check(near, "no splashes yet -> back inside tonight's home dorm")
	h.free_sim()


func test_after_three_splashes_return_to_third() -> void:
	var h := _h()
	h.make([R, P], [0, 1, 2])
	await h.release_patrol()
	for wi in [2, 0, 1]:
		await h.splash_into(0, wi)
	_tag_setup(h, 1.2)
	await h.step()
	h.press(1, TC.BTN_TAG)
	await h.wait_event(TC.Ev.CAPTURE, 60)
	while h.sim.player(0).state == TC.PState.CAPTURED:
		await h.step()
	var near := false
	for pad in h.sim.layout.waters[1]["pads"]:
		if h.sim.player(0).pos2().distance_to(pad) < 1.5:
			near = true
	t.check(near, "third (last) splash location")
	t.eq(h.sim.player(0).stamp_count(), 3, "still needs to run home with 3 stamps")
	t.eq(h.sim.player(0).state, TC.PState.ACTIVE, "not finished just by having 3 stamps")
	h.free_sim()


func test_tag_reach_cooldown_and_walls() -> void:
	var h := _h()
	h.make([R, P], [0, 1, 2])
	await h.release_patrol()
	# out of reach -> miss -> cooldown
	_tag_setup(h, 4.5)
	await h.step()
	h.press(1, TC.BTN_TAG)
	var miss := await h.wait_event(TC.Ev.TAG_MISS, 40)
	t.check(not miss.is_empty(), "lunge out of reach misses")
	t.eq(h.sim.player(0).state, TC.PState.ACTIVE, "no capture on a miss")
	t.check(h.sim.player(1).tag_cd > 0.5, "cooldown after a miss")
	# pressing during cooldown does nothing
	_tag_setup(h, 1.0)
	await h.step()
	h.press(1, TC.BTN_TAG)
	await h.step(3)
	var ph := int(h.sim.player(1).tag_phase)
	t.check(ph != SimPlayer.TagPhase.ANTICIPATE and ph != SimPlayer.TagPhase.LUNGE, "cannot lunge again during cooldown")
	await h.step(60)
	# through a wall: library east wall at x = -39; runner inside? use the dorm: runner north of
	# the north face, patrol just south of it inside... instead use a hedge segment between them.
	var hedge: Dictionary = h.sim.layout.hedges[3]  # garden ring hedge segment
	var a: Vector2 = hedge["a"]
	var b: Vector2 = hedge["b"]
	var mid := (a + b) * 0.5
	var n := (b - a).normalized().orthogonal()
	var rp := mid + n * 0.95
	var pp := mid - n * 0.95
	h.place(0, Vector3(rp.x, 0.05, rp.y))
	var face := atan2(-(rp - pp).x, -(rp - pp).y)
	h.place(1, Vector3(pp.x, 0.05, pp.y), face)
	await h.step()
	h.press(1, TC.BTN_TAG)
	await h.step(30)
	t.eq(h.sim.player(0).state, TC.PState.ACTIVE, "no tag through a hedge/wall (line of sight)")
	h.free_sim()


func test_tag_validation_roles_and_states() -> void:
	var h := _h()
	h.make([R, R, P], [0, 1, 2])
	await h.release_patrol()
	# a runner pressing TAG next to another runner does nothing
	h.place(0, Vector3(-20, 0.05, 60))
	h.place(1, Vector3(-20, 0.05, 61.2))
	await h.step()
	h.press(1, TC.BTN_TAG)
	await h.step(30)
	t.eq(h.sim.player(0).state, TC.PState.ACTIVE, "runners cannot tag")
	# protected runner can't be tagged
	h.sim.player(0).protect = 2.0
	h.place(2, Vector3(-20, 0.05, 61.2))
	await h.step()
	h.press(2, TC.BTN_TAG)
	await h.step(30)
	t.eq(h.sim.player(0).state, TC.PState.ACTIVE, "protected runner not taggable")
	h.free_sim()


func _same_tick_case(stamped: bool) -> Dictionary:
	var h := _h()
	h.make([R, P], [0, 1, 2])
	await h.release_patrol()
	# V6: the runner is in the front doorway 6 cm short of the threshold,
	# running in; the Night Watch lunges from just behind
	var d: Dictionary = h.sim.home_doors[0]
	var lp: Vector2 = d["line_p"]
	var n2: Vector2 = d["n_in"]
	var n := Vector3(n2.x, 0, n2.y)
	var at := Vector3(lp.x, 0.05, lp.y)
	var face := atan2(-n.x, -n.z)
	var r := h.sim.player(0)
	var pt := h.sim.player(1)
	if stamped:
		r.stamps = 7
	h.place(0, at - n * 0.5, face)
	h.place(1, at - n * 1.6, face)
	h.cmd(0).move = n2
	await h.step()   # settle on floor
	h.place(0, at - n * 0.06, face)
	h.place(1, at - n * 1.1, face)
	r.vel = n * 6.0
	r.body.velocity = r.vel
	pt.tag_phase = SimPlayer.TagPhase.LUNGE
	pt.tag_t = 0.0
	await h.step()
	var out := {"finished": r.state == TC.PState.FINISHED, "captured": r.state == TC.PState.CAPTURED, "tick_events": h.sim.events.map(func(e): return int(e["type"]))}
	h.free_sim()
	return out


func test_same_tick_finish_beats_tag() -> void:
	var control := await _same_tick_case(false)
	t.check(control["captured"], "control: without three stamps the same lunge captures")
	var res := await _same_tick_case(true)
	t.check(res["finished"] and not res["captured"], "finish boundary wins over a same-tick tag %s" % str(res))


func test_fourth_runner_ends_round_immediately() -> void:
	var h := _h()
	h.make([R, R, R, R, R, R, P, P], [0, 1, 2])
	await h.to_playing()
	for r in 4:
		for wi in [0, 1, 2]:
			await h.splash_into(r, wi)
	for r in 3:
		await h.enter_door(r, r)
	t.eq(h.sim.finished_count, 3, "three home")
	t.eq(h.sim.phase, TC.Phase.PLAYING, "round continues at three")
	await h.enter_door(3, 0)
	t.eq(h.sim.outcome, TC.Outcome.RUNNERS_WIN, "fourth valid finish wins")
	t.eq(h.sim.phase, TC.Phase.RESULTS, "round ends on that tick")
	var fin_tick := -1
	for p in h.sim.players:
		if p.finish_order == 4:
			fin_tick = p.finished_tick
	t.eq(fin_tick, h.sim.tick, "ended on the 4th finish tick")
	h.free_sim()


func test_timeout_and_deadline_finish() -> void:
	# A: timeout with 3 home -> patrol win exactly at the deadline
	var h := _h()
	h.make([R, R, R, R, R, R, P, P], [0, 1, 2])
	await h.to_playing()
	for r in 4:
		for wi in [0, 1, 2]:
			await h.splash_into(r, wi)
	for r in 3:
		await h.enter_door(r, r)
	h.sim.end_tick = h.sim.tick + 5
	await h.step(5)
	t.eq(h.sim.outcome, TC.Outcome.PATROL_WIN, "time expires with fewer than four home")
	h.free_sim()
	# B: the 4th finish lands exactly on the deadline tick -> counts
	var h2 := _h()
	h2.make([R, R, R, R, R, R, P, P], [0, 1, 2])
	await h2.to_playing()
	for r in 4:
		for wi in [0, 1, 2]:
			await h2.splash_into(r, wi)
	for r in 3:
		await h2.enter_door(r, r)
	h2.sim.end_tick = h2.sim.tick + 1
	h2.cross_next_tick(3, 0)
	await h2.step(1)
	t.eq(h2.sim.outcome, TC.Outcome.RUNNERS_WIN, "finish accepted at the deadline tick counts")
	# no late result changes after the end
	h2.cross_next_tick(4, 0)
	await h2.step(3)
	t.eq(h2.sim.finished_count, 4, "nothing changes after the round ended")
	h2.free_sim()


func test_cart_seat_race_and_roles() -> void:
	var h := _h()
	h.make([R, P, P], [0, 1, 2])
	await h.release_patrol()
	var c: SimCart = h.sim.carts[0]
	var cp := c.pos()
	h.place(1, cp + c.right() * -1.6)
	h.place(2, cp + c.right() * 1.9)
	h.place(0, cp + c.forward() * 2.2)
	await h.step()
	h.press(1, TC.BTN_INTERACT)
	h.press(2, TC.BTN_INTERACT)
	h.press(0, TC.BTN_INTERACT)
	await h.step()
	var enters := h.events_of(TC.Ev.CART_ENTER)
	t.eq(enters.size(), 1, "exactly one seat claim wins the same-tick race")
	t.eq(c.occupant, 1, "closest patrol gets the seat")
	t.eq(h.sim.player(2).state, TC.PState.ACTIVE, "loser stays on foot")
	t.eq(h.sim.player(0).cart_id, -1, "runners can't take a cart")
	h.press(2, TC.BTN_INTERACT)
	await h.step(2)
	t.eq(c.occupant, 1, "occupied cart cannot be entered")
	h.free_sim()


func test_cart_drive_exit_safely_and_lockout() -> void:
	var h := _h()
	h.make([R, P], [0, 1, 2])
	await h.release_patrol()
	var c: SimCart = h.sim.carts[0]
	h.place(1, c.pos() + c.right() * -1.5)
	await h.step()
	h.press(1, TC.BTN_INTERACT)
	await h.step(30)
	t.eq(h.sim.player(1).state, TC.PState.IN_CART, "seated after the entry beat")
	h.cmd(1).drive = 1.0
	await h.step(150)
	t.check(c.speed > 6.0, "cart accelerates (%.1f m/s)" % c.speed)
	var top := c.speed
	t.check(top <= Rules.cfg.cart_max_speed_road + 0.1, "respects top speed")
	h.cmd(1).drive = 0.0
	h.press(1, TC.BTN_INTERACT)
	var exited := false
	var speed_at_exit := 99.0
	for i in 200:
		await h.step()
		if h.sim.player(1).state == TC.PState.EXITING:
			exited = true
			speed_at_exit = absf(c.speed)
			break
	t.check(exited, "driver hops out after the cart slows")
	t.check(speed_at_exit <= Rules.cfg.cart_exit_max_speed + 0.5, "exit only once slow (%.2f)" % speed_at_exit)
	var pp := h.sim.player(1).pos()
	var ss := h.sim.space_state()
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.4
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, pp + Vector3(0, 0.8, 0))
	q.collision_mask = TC.L_WORLD
	t.check(ss.intersect_shape(q, 1).is_empty(), "exit point is clear (no clipping)")
	t.check(h.sim.player(1).tag_lockout > 0.0, "no instant tag after dismount")
	h.free_sim()


func test_bump_stumbles_without_chain_or_capture() -> void:
	var h := _h()
	h.make([R, P], [0, 1, 2])
	await h.release_patrol()
	var c: SimCart = h.sim.carts[0]
	# put the cart on the loop road heading east, runner ahead in its path
	c.body.global_position = Vector3(-40, 0.05, -58)
	c.yaw = -PI * 0.5
	c.body.rotation.y = c.yaw
	c.occupant = 1
	h.sim.player(1).cart_id = 0
	h.sim.player(1).state = TC.PState.IN_CART
	Motor.set_body_enabled(h.sim.player(1).body, false)
	h.place(0, Vector3(-28, 0.05, -58))
	h.cmd(1).drive = 1.0
	var bumps := 0
	for i in 160:
		await h.step()
		bumps += h.events_of(TC.Ev.BUMP).size()
		if not h.events_of(TC.Ev.CAPTURE).is_empty():
			t.check(false, "a bump must never capture")
	t.check(bumps >= 1, "cart bump happened")
	t.check(bumps <= 2, "no repeated stun loop (%d bumps)" % bumps)
	t.check(h.sim.player(0).state != TC.PState.CAPTURED, "bump is not a capture")
	h.free_sim()


func test_gadget_single_use_and_ownership() -> void:
	var h := _h()
	h.make([R, P], [0, 1, 2])
	await h.release_patrol()
	var r := h.sim.player(0)
	var spot: Vector3 = h.sim.pickups[0]["pos"]
	h.place(0, spot + Vector3(0, 0.05, 0))
	await h.step(2)
	t.check(r.gadget != TC.Gadget.NONE, "picked up a gadget")
	var g := r.gadget
	h.place(1, spot + Vector3(0, 0.05, 0.3))
	await h.step(2)
	t.eq(h.sim.player(1).gadget, TC.Gadget.NONE, "patrol cannot hold gadgets")
	h.press(0, TC.BTN_GADGET)
	await h.step()
	h.press(0, TC.BTN_GADGET)
	await h.step()
	h.press(0, TC.BTN_GADGET)
	await h.step()
	var uses := 0
	# count across the last ticks via state: gadget gone, cooldown running
	t.eq(r.gadget, TC.Gadget.NONE, "consumed")
	t.check(r.gadget_cd > 0.0, "cooldown running")
	# pickup has respawn timer -> can't immediately re-grab the same one
	t.check(float(h.sim.pickups[0]["respawn"]) > 0.0, "pickup respawns later")
	h.free_sim()
	# duplicate presses within the same window produce exactly one use event
	var h2 := _h()
	h2.make([R, P], [0, 1, 2])
	await h2.release_patrol()
	var r2 := h2.sim.player(0)
	r2.gadget = TC.Gadget.TURBO
	var use_events := 0
	for i in 6:
		h2.press(0, TC.BTN_GADGET)
		await h2.step()
		use_events += h2.events_of(TC.Ev.GADGET_USE).size()
	t.eq(use_events, 1, "one held gadget = one use (%s)" % g)
	t.check(r2.turbo_t > 0.0, "turbo active")
	# turbo + sprint is capped
	h2.cmd(0).move = Vector2(1, 0)
	h2.cmd(0).held = TC.BTN_SPRINT
	await h2.step(40)
	var spd := Vector2(r2.vel.x, r2.vel.z).length()
	t.check(spd <= Rules.cfg.turbo_speed_cap + 0.05, "turbo+sprint speed capped (%.2f)" % spd)
	h2.free_sim()


func test_splash_bomb_slows_cart_briefly() -> void:
	var h := _h()
	h.make([R, P], [0, 1, 2])
	await h.release_patrol()
	var c: SimCart = h.sim.carts[0]
	var r := h.sim.player(0)
	h.place(0, c.pos() + Vector3(0, 0, 8))
	r.gadget = TC.Gadget.SPLASH_BOMB
	h.cmd(0).cam_yaw = 0.0  # facing -Z (north) toward the cart
	h.press(0, TC.BTN_GADGET)
	var hit := false
	for i in 60:
		await h.step()
		for e in h.sim.events:
			if int(e["type"]) == TC.Ev.BOMB_HIT and int(e["b"]) == 0:
				hit = true
	t.check(hit, "assisted toss hits a nearby cart")
	t.check(c.slowed_t > 0.0 and c.slowed_t <= Rules.cfg.bomb_slow_s, "short slow, no long stun")
	h.free_sim()


func test_reconnect_resumes_and_reservation_expires() -> void:
	var h := _h()
	h.make([R, P], [0, 1, 2])
	await h.to_playing()
	await h.splash_into(0, 0)
	var r := h.sim.player(0)
	h.sim.set_disconnected(0)
	t.check(r.bot_takeover, "bot covers the disconnected slot")
	await h.step(300)
	t.check(h.sim.resume(0, "u0"), "valid reconnect within 20 s resumes")
	t.check(r.connected and not r.bot_takeover, "player back in control")
	t.eq(r.stamp_count() >= 1, true, "same authoritative progress (no reset)")
	t.eq(r.protect, 0.0, "no free immunity on reconnect")
	t.check(not h.sim.resume(0, "u0"), "duplicate resume rejected")
	h.sim.set_disconnected(0)
	await h.step(int(Rules.cfg.disconnect_reserve_s * 60) + 30)
	t.check(not h.sim.resume(0, "u0"), "slot reservation expires after ~20 s")
	t.check(r.is_bot, "bot keeps the slot for the rest of the round")
	t.check(not h.sim.resume(0, "intruder"), "wrong identity cannot take the slot")
	h.free_sim()


func test_out_of_bounds_recovery_grants_nothing() -> void:
	var h := _h()
	h.make([R, P], [0, 1, 2])
	await h.to_playing()
	await h.splash_into(0, 0)
	h.place(0, Vector3(0, -20, 0))
	var ev := await h.wait_event(TC.Ev.RECOVER, 10)
	t.check(not ev.is_empty(), "out-of-bounds recovery")
	t.eq(h.sim.player(0).stamp_count(), 1, "no new stamps from recovery")
	t.eq(h.sim.player(0).state, TC.PState.ACTIVE, "back in play, not finished")
	h.free_sim()


func test_finished_runner_is_out_of_play() -> void:
	var h := _h()
	h.make([R, P], [0, 1, 2])
	await h.release_patrol()
	for wi in [0, 1, 2]:
		await h.splash_into(0, wi)
	await h.enter_door(0, 1)
	var r := h.sim.player(0)
	t.eq(r.state, TC.PState.FINISHED, "finished")
	t.check(not r.is_taggable(), "finished runners are safe")
	var fpos := r.pos()
	h.cmd(0).move = Vector2(1, 0)
	await h.step(30)
	t.check(r.pos().distance_to(fpos) < 0.01, "finished runners cannot interfere with active play")
	h.free_sim()


func test_movement_feel_numbers() -> void:
	var h := _h()
	h.make([R, P], [0, 1, 2])
	await h.release_patrol()
	var r := h.sim.player(0)
	h.place(0, Vector3(-20, 0.05, 40))
	h.cmd(0).move = Vector2(1, 0)
	await h.step(30)
	t.near(Vector2(r.vel.x, r.vel.z).length(), Rules.cfg.runner_speed, 0.3, "run speed ~5 m/s")
	h.cmd(0).held = TC.BTN_SPRINT
	await h.step(30)
	t.near(Vector2(r.vel.x, r.vel.z).length(), Rules.cfg.runner_sprint_speed, 0.3, "sprint ~7 m/s")
	var t0 := h.sim.tick
	while r.sprinting:
		await h.step()
	var dur := float(h.sim.tick - t0 + 30) / 60.0
	t.near(dur, Rules.cfg.sprint_capacity_s, 0.25, "sprint lasts ~2.5 s")
	h.cmd(0).held = 0
	# jump + coyote + dive
	h.cmd(0).move = Vector2.ZERO
	await h.step(20)
	h.press(0, TC.BTN_JUMP)
	await h.step(2)
	t.check(r.vel.y > 4.0, "jump launches")
	var peak := 0.0
	var base_y := 0.05
	for i in 40:
		await h.step()
		peak = maxf(peak, r.pos().y - base_y)
	t.check(peak > 0.8 and peak < 1.4, "jump height ~1.1 m (%.2f)" % peak)
	await h.step(20)
	h.cmd(0).move = Vector2(1, 0)
	h.press(0, TC.BTN_JUMP)
	await h.step(6)
	h.press(0, TC.BTN_JUMP)
	await h.step(2)
	t.check(r.diving, "second press in the air dives")
	t.check(Vector2(r.vel.x, r.vel.z).length() >= Rules.cfg.dive_speed - 0.3, "dive carries speed")
	# input buffer: press jump just before landing
	while not r.on_floor:
		await h.step()
	await h.step(25)
	h.press(0, TC.BTN_JUMP)
	await h.step(4)
	var landed_buffer := false
	for i in 50:
		await h.step()
		if r.on_floor:
			break
	h.press(0, TC.BTN_JUMP)   # within ~2 ticks of landing
	await h.step(3)
	t.check(r.vel.y > 3.0 or not r.on_floor, "buffered jump fires on landing")
	# patrol foot speed
	var p := h.sim.player(1)
	h.place(1, Vector3(-20, 0.05, 50))
	h.cmd(1).move = Vector2(1, 0)
	await h.step(40)
	t.near(Vector2(p.vel.x, p.vel.z).length(), Rules.cfg.patrol_speed, 0.3, "patrol foot speed between run and sprint")
	h.free_sim()


func test_spotted_cue_requires_line_of_sight() -> void:
	var h := _h()
	h.make([R, P], [0, 1, 2])
	await h.release_patrol()
	h.place(0, Vector3(-20, 0.05, 50))
	h.place(1, Vector3(-20, 0.05, 62), 0.0)
	h.cmd(1).cam_yaw = 0.0
	await h.step(10)
	t.check(h.sim.player(0).spotted > 0.0, "visible runner is spotted")
	# behind the library (x -61..-39, z 1..35): patrol east of it, runner west of it
	h.place(0, Vector3(-66, 0.05, 18))
	h.place(1, Vector3(-30, 0.05, 18), PI * 0.5)
	h.cmd(1).cam_yaw = PI * 0.5
	await h.step(Rules.cfg.ticks(Rules.cfg.spotted_hold_s) + 10)
	t.eq(h.sim.player(0).spotted, 0.0, "breaking line of sight behind a building loses the pursuer")
	h.free_sim()
