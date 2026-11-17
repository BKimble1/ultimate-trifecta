extends RefCounted
## (2.2 build 18) A Night Watch tag puts the runner out of the round: the
## caught moment, then out for good (no respawn, out of play, out of the
## race), and the Night Watch win as soon as too few runners are left to
## get enough home.
var t
const R := TC.Role.RUNNER
const P := TC.Role.PATROL


func _h() -> SimHarness:
	return SimHarness.new(t)


func _tag(h: SimHarness, runner: int, patrol: int, at: Vector2) -> void:
	h.place(runner, h.on_ground(at), 0.0)
	h.place(patrol, h.on_ground(at + Vector2(0, 1.2)), 0.0)
	await h.step()
	h.press(patrol, TC.BTN_TAG)


func test_a_tag_knocks_the_runner_out_for_the_round() -> void:
	var h := _h()
	h.make([R, R, R, R, R, R, P], [0, 1, 2], [], 11, {"tag_out": true})
	t.check(Rules.cfg.tag_eliminates, "knock-out tags are the game's rule")
	await h.release_patrol()
	await _tag(h, 0, 6, Vector2(-20, 60))
	var ev := await h.wait_event(TC.Ev.CAPTURE, 60)
	t.check(not ev.is_empty(), "the tag lands")
	var r := h.sim.player(0)
	t.eq(r.state, TC.PState.CAPTURED, "the caught moment first")
	var out := await h.wait_event(TC.Ev.KNOCKED_OUT, int(Rules.cfg.tag_out_s * 60.0) + 30)
	t.check(not out.is_empty() and int(out["a"]) == 0, "then knocked out")
	t.eq(r.state, TC.PState.OUT, "out of the round")
	t.check(not r.is_in_play() and not r.is_taggable(), "out of play: can't be tagged again")
	await h.step(int(Rules.cfg.capture_penalty_s * 60.0) + 120)
	t.eq(r.state, TC.PState.OUT, "and never respawns")
	t.eq(h.sim.phase, TC.Phase.PLAYING, "five runners can still get four home: the round goes on")
	t.eq(h.sim.runners_alive(), 5, "five runners left")
	h.free_sim()


func test_too_few_runners_left_ends_it_for_the_night_watch() -> void:
	var h := _h()
	h.make([R, R, R, R, R, R, P], [0, 1, 2], [], 12, {"tag_out": true})
	await h.release_patrol()
	for i in 3:
		# the same open lawn each time (an out runner has no body)
		await _tag(h, i, 6, Vector2(-20, 60))
		var ev := await h.wait_event(TC.Ev.CAPTURE, 90)
		t.eq(int(ev.get("a", -1)), i, "tag %d lands" % (i + 1))
		await h.step(int(maxf(Rules.cfg.tag_hit_recover_s, Rules.cfg.tag_miss_cooldown_s) * 60.0) + 10)
	t.check(h.sim.runners_alive() < Rules.cfg.runners_needed, "three out: only three of six left, four needed")
	await h.step(2)
	t.check(h.sim.phase >= TC.Phase.RESULTS, "the round ends at once")
	t.eq(int(h.sim.results.get("outcome", -1)), TC.Outcome.PATROL_WIN, "a Night Watch win")
	h.free_sim()


func test_respawn_rules_stay_available() -> void:
	var h := _h()
	h.make([R, P], [0, 1, 2], [], 13, {"tag_out": false})
	await h.release_patrol()
	await _tag(h, 0, 1, Vector2(-20, 60))
	await h.wait_event(TC.Ev.CAPTURE, 60)
	await h.wait_event(TC.Ev.RESPAWN, int(Rules.cfg.capture_penalty_s * 60.0) + 30)
	t.eq(h.sim.player(0).state, TC.PState.ACTIVE, "with tag_out off a caught runner comes back")
	h.free_sim()
