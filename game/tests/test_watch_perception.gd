extends RefCounted
## (build 35) Night Watch bots only go after what they honestly perceive:
## a runner in their view cone and line of sight (out to WATCH_VIEW_M), or
## right behind them (WATCH_HEAR_M).  Footsteps further off only turn their
## head.  A runner they saw dive into a bush is checked there (a short
## search, then a lunge); one they didn't see go in, they walk past.
var t
const R := TC.Role.RUNNER
const P := TC.Role.PATROL
const LAWN := Vector2(-20, 60)    # open lawn on the reference campus


func _setup(seed_v: int = 41) -> SimHarness:
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2], [1], seed_v)
	return h


## A runner (human, slot 0) jogging to and fro `behind` m straight behind a
## Night Watch bot facing -z: does the bot ever take them for a target?
func _noticed_from_behind(behind: float) -> bool:
	var h := _setup()
	await h.release_patrol()
	var w := h.sim.player(1)
	var br: BotBrain = h.sim.bots[1]
	h.place(1, h.on_ground(LAWN), 0.0)
	h.place(0, h.on_ground(LAWN + Vector2(0, behind)), 0.0)
	var seen := false
	for i in 90:
		# side to side across the bot's back, at a jog (footsteps audible)
		h.cmd(0).move = Vector2(1 if (i / 30) % 2 == 0 else -1, 0) * 0.7
		w.yaw = 0.0
		w.body.global_position = h.on_ground(LAWN)
		w.vel = Vector3.ZERO
		await h.step()
		if br.last_seen.has(0) or br.chase_id == 0:
			seen = true
			break
	h.free_sim()
	return seen


func test_a_runner_behind_is_not_seen_beyond_arms_length() -> void:
	t.check(not await _noticed_from_behind(5.0), "a runner jogging 5 m behind a Night Watch bot isn't noticed (it used to chase anyone within 6 m)")
	t.check(not await _noticed_from_behind(12.0), "nor 12 m behind (footsteps: it turns to look at most)")
	t.check(await _noticed_from_behind(1.8), "right behind it (1.8 m), it hears them")


func test_in_view_it_sees_and_chases_after_a_beat() -> void:
	var h := _setup()
	await h.release_patrol()
	var br: BotBrain = h.sim.bots[1]
	var w := h.sim.player(1)
	h.place(1, h.on_ground(LAWN), 0.0)
	h.place(0, h.on_ground(LAWN + Vector2(2, -15)), 0.0)    # 15 m ahead, in view
	var react_ticks := -1
	var p0 := w.pos2()
	for i in 90:
		await h.step()
		if br.chase_id == 0 and w.pos2().distance_to(p0) > 1.0 and react_ticks < 0:
			react_ticks = i
	t.check(br.last_seen.has(0), "a runner 15 m ahead in the open is seen")
	t.check(react_ticks >= int(BotBrain.WATCH_REACT.x * 60.0 * 0.8), "and the chase starts after a reaction delay (%d ticks)" % react_ticks)
	h.free_sim()


func test_out_of_range_or_behind_a_wall_is_unseen() -> void:
	var h := _setup()
	await h.release_patrol()
	var br: BotBrain = h.sim.bots[1]
	var w := h.sim.player(1)
	h.place(1, h.on_ground(LAWN), 0.0)
	h.place(0, h.on_ground(LAWN + Vector2(0, -(BotBrain.WATCH_VIEW_M + 4.0))), 0.0)
	for i in 30:
		w.yaw = 0.0
		await h.step()
	t.check(not br.last_seen.has(0), "beyond its view range: unseen")
	# straight through a building: from the side of one to the other side
	var lay := h.sim.layout
	var found := false
	for b in lay.buildings:
		var rect: Rect2 = b["rect"]
		if rect.size.x < 10.0 or rect.size.y < 10.0 or rect.size.x > 40.0:
			continue
		var c := rect.get_center()
		var a := c + Vector2(0, rect.size.y * 0.5 + 3.0)
		var z := c - Vector2(0, rect.size.y * 0.5 + 3.0)
		var nav := NavGrid.shared(lay)
		if not nav.is_walkable(a) or not nav.is_walkable(z) or a.distance_to(z) > 30.0:
			continue
		found = true
		h.place(1, h.on_ground(a), 0.0)      # facing -z: at the wall
		h.place(0, h.on_ground(z), 0.0)
		br.last_seen.clear()
		for i in 30:
			w.yaw = 0.0
			w.body.global_position = h.on_ground(a)
			await h.step()
		t.check(not br.last_seen.has(0), "a runner behind %s is unseen" % String(b.get("name", "a building")))
		break
	t.check(found, "found a building to hide behind")
	h.free_sim()


# ---------------------------------------------------------------------------
# Bushes
# ---------------------------------------------------------------------------
func _bush_case(seen_going_in: bool) -> Dictionary:
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2], [1], 51, {"map": CampusMaps.CLASSIC})
	await h.release_patrol()
	h.sim.end_tick = 1 << 30
	var r := h.sim.player(0)
	var w := h.sim.player(1)
	var br: BotBrain = h.sim.bots[1]
	# the bush with the clearest lawn around it
	var nav := NavGrid.shared(h.sim.layout)
	var bp: Vector2 = h.sim.hide_bushes[0]
	for cand in h.sim.hide_bushes:
		var ok := true
		for k in 8:
			var a := TAU * float(k) / 8.0
			if not nav.is_walkable((cand as Vector2) + Vector2(cos(a), sin(a)) * 10.0):
				ok = false
		if ok:
			bp = cand
			break
	h.place(0, h.on_ground(bp + Vector2(1.3, 0)))
	var wp := bp + Vector2(0, 10.0)
	# looking at the runner (seen) or away from them (not)
	h.place(1, h.on_ground(wp), 0.0 if seen_going_in else PI)
	br.react_t = 0.0
	for i in 20:
		w.body.global_position = h.on_ground(wp)
		w.yaw = 0.0 if seen_going_in else PI
		await h.step()
	h.press(0, TC.BTN_INTERACT)
	await h.step()
	var hid := r.state == TC.PState.HIDING
	if not seen_going_in:
		# then it walks right past the bush, as if on its round
		br.investigate = Vector3(bp.x, 0, bp.y - 12.0)
		br.investigate_t = 30.0
	var at_bush := -1
	var lunge := -1
	var caught := -1
	var closest := INF
	for i in 60 * 12:
		await h.step()
		closest = minf(closest, w.pos2().distance_to(bp))
		if at_bush < 0 and w.pos2().distance_to(bp) <= 1.9:
			at_bush = i
		if lunge < 0 and w.tag_phase != SimPlayer.TagPhase.NONE:
			lunge = i
		if r.state == TC.PState.CAPTURED:
			caught = i
			break
	var out := {"hid": hid, "at_bush": at_bush, "lunge": lunge, "caught": caught, "closest": closest, "knew": br.saw_hide.has(0)}
	h.free_sim()
	return out


func test_seen_diving_into_a_bush_the_bot_checks_it() -> void:
	var o: Dictionary = await _bush_case(true)
	print("WATCHBUSH seen going in: %s" % str(o))
	t.check(bool(o["hid"]), "the runner hides")
	t.check(int(o["caught"]) >= 0, "the Night Watch bot that saw it goes to that bush and tags them there")
	t.check(int(o["at_bush"]) >= 0 and int(o["lunge"]) - int(o["at_bush"]) >= int(BotBrain.WATCH_SEARCH.x * 60.0) - 2,
		"after searching it for a moment (%.2f s at the bush before the lunge)" % (float(int(o["lunge"]) - int(o["at_bush"])) / 60.0))


func test_unseen_going_in_the_bot_walks_past() -> void:
	var o: Dictionary = await _bush_case(false)
	print("WATCHBUSH not seen going in: %s" % str(o))
	t.check(bool(o["hid"]), "the runner hides")
	t.check(float(o["closest"]) < 4.0, "the Night Watch bot passes right by the bush (%.1f m)" % float(o["closest"]))
	t.eq(int(o["caught"]), -1, "and doesn't know they're in it")
	t.check(not bool(o["knew"]), "(it never learned which bush)")
