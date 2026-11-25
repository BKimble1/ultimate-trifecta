extends RefCounted
## (build 35) The owner's playtest with friends: the Night Watch bots were
## too good (and caught every bot runner in seconds, which ended the round
## on the humans), and runner bots were too slippery for a human Night
## Watch.  Measured with the real sim, physics and bots:
##   - a full Moonbrook round, 2 scripted "human" runners (one hides in a
##     bush, one runs the routes) + 4 bot runners against 2 Night Watch bots,
##     knock-out tags: when the round ends, how long the bot runners last;
##   - a scripted human-like Night Watch (straight pursuit, no prediction,
##     Tag when it looks close) against a fleeing runner bot from 6-8 m;
##   - a Night Watch bot against a careless human-like runner (jogs past in
##     plain sight and never dodges): it must still catch them.
## The numbers print as BOTFAIR lines (before/after in the build 35 notes).
var t
const R := TC.Role.RUNNER
const P := TC.Role.PATROL

# open lawn starts on the reference campus (as test_chase_balance): runner
# position + flee heading
const STARTS := [[Vector3(-20, 0.05, 60), Vector2(1, 0)], [Vector3(-20, 0.05, 60), Vector2(0, -1)],
	[Vector3(-20, 0.05, 60), Vector2(-1, 0)], [Vector3(30, 0.05, 62), Vector2(0, -1)]]


# ---------------------------------------------------------------------------
# A full round: the humans' round never ends while one of them is still free
# ---------------------------------------------------------------------------
func _round(seed_v: int) -> Dictionary:
	var h := SimHarness.new(t)
	var roles := [R, R, R, R, R, R, P, P]
	h.make(roles, [0, 1, 2], [2, 3, 4, 5, 6, 7], seed_v, {"map": CampusMaps.CLASSIC, "tag_out": true, "pace": false, "rifts": false})
	var sim := h.sim
	# human 1 runs the routes: a runner brain whose commands arrive as a
	# human's inputs (the sim treats the slot as a person)
	var legs := BotBrain.new(sim, sim.player(1))
	await h.to_playing()
	var hider := sim.player(0)
	var hidden_at := -1.0
	var caught_t := {}
	var end_t := -1.0
	var free_humans_at_end := 0
	var t0 := sim.tick
	while sim.phase == TC.Phase.PLAYING:
		var rt := float(sim.tick - t0) / 60.0
		# human 0: out of the dorm and into a bush on the lawn 3 s after GO
		if hidden_at < 0.0 and rt > 3.0 and hider.state == TC.PState.ACTIVE:
			var best: Vector2 = sim.hide_bushes[0]
			var dorm := sim.layout.dorm_center(sim.home_dorm)
			for bp in sim.hide_bushes:
				if (bp as Vector2).distance_to(dorm) < best.distance_to(dorm) and (bp as Vector2).distance_to(dorm) > 25.0:
					best = bp
			h.place(0, h.on_ground(best + Vector2(1.3, 0)))
			hidden_at = rt
		if hidden_at >= 0.0 and hider.state == TC.PState.ACTIVE and rt > hidden_at + 0.1:
			h.press(0, TC.BTN_INTERACT)
		h.inputs[1] = legs.think(sim, sim.player(1))
		await h.step()
		for e in sim.events:
			if int(e["type"]) == TC.Ev.CAPTURE and not caught_t.has(int(e["a"])):
				caught_t[int(e["a"])] = snappedf(float(sim.tick - t0) / 60.0, 0.1)
	end_t = sim.round_time()
	for s in [0, 1]:
		var p := sim.player(s)
		if p.state != TC.PState.OUT and p.state != TC.PState.CAPTURED and p.state != TC.PState.FINISHED:
			free_humans_at_end += 1
	var bot_times: Array = []
	for s in [2, 3, 4, 5]:
		bot_times.append(caught_t.get(s, -1.0))
	var out := {"end": snappedf(end_t, 0.1), "outcome": sim.outcome, "bots_caught_at": bot_times,
		"humans_caught_at": [caught_t.get(0, -1.0), caught_t.get(1, -1.0)], "free_humans_at_end": free_humans_at_end,
		"timeout": end_t >= Rules.cfg.match_duration_s - 0.05, "finished": sim.finished_count}
	h.free_sim()
	return out


func test_a_round_never_ends_on_free_humans() -> void:
	var early := 0
	var surv: Array = []
	for seed_v in [101, 202, 303]:
		var r: Dictionary = await _round(seed_v)
		print("BOTFAIR round seed %d: end %.1f s (%s), outcome %d, home %d, bot runners caught at %s, humans caught at %s, humans free at the end %d" % [
			seed_v, r["end"], "time" if r["timeout"] else "early", r["outcome"], r["finished"], str(r["bots_caught_at"]), str(r["humans_caught_at"]), r["free_humans_at_end"]])
		if int(r["outcome"]) == TC.Outcome.PATROL_WIN and not bool(r["timeout"]) and int(r["free_humans_at_end"]) > 0:
			early += 1
		for x in r["bots_caught_at"]:
			surv.append(float(x) if float(x) >= 0.0 else float(r["end"]))
	surv.sort()
	var med: float = (surv[surv.size() / 2 - 1] + surv[surv.size() / 2]) * 0.5
	print("BOTFAIR bot runner survival (s, censored at round end): median %.1f, all %s" % [med, str(surv)])
	t.eq(early, 0, "no round ends for the Night Watch while a human runner is still free")
	t.check(med >= 45.0, "bot runners last a while against Night Watch bots (median %.1f s)" % med)


# ---------------------------------------------------------------------------
# A human-like Night Watch chasing a runner bot on open ground
# ---------------------------------------------------------------------------
## Straight pursuit at the runner (no lead), Tag pressed once it looks close
## (2.4 m), the view on the runner.  The chaser starts `gap` m behind and
## the runner gets going first (the chaser sets off once the runner is
## running away, at most 1 s later: a fleeing bot, not a surprised one).
## Returns seconds to the catch from the chaser's start, -1 if the runner
## got away for `limit` s.
func _human_chase(si: int, gap: float, limit: float) -> float:
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2], [0], 700 + si * 13 + int(gap))
	await h.release_patrol()
	var a0: Vector3 = STARTS[si][0]
	var d: Vector2 = STARTS[si][1]
	h.place(0, h.on_ground(Vector2(a0.x, a0.z)), atan2(-d.x, -d.y))
	h.place(1, h.on_ground(Vector2(a0.x, a0.z) - d * gap), atan2(-d.x, -d.y))
	var r := h.sim.player(0)
	var w := h.sim.player(1)
	# the runner sees the Night Watch and gets going
	for i in 60:
		var rel0 := r.pos() - w.pos()
		h.cmd(1).cam_yaw = atan2(-rel0.x, -rel0.z)
		await h.step()
		if Vector2(r.vel.x, r.vel.z).dot(Vector2(rel0.x, rel0.z).normalized()) > 4.0:
			break
	var t0 := h.sim.tick
	var secs := -1.0
	var cd := 0
	for i in int(limit * 60.0):
		var rel := r.pos() - w.pos()
		var flat := Vector2(rel.x, rel.z)
		var c := h.cmd(1)
		c.move = flat.normalized() if flat.length() > 0.2 else Vector2.ZERO
		c.cam_yaw = atan2(-rel.x, -rel.z)
		cd -= 1
		if flat.length() < 2.4 and cd <= 0:
			h.press(1, TC.BTN_TAG)
			cd = 20
		await h.step()
		if r.state == TC.PState.CAPTURED:
			secs = float(h.sim.tick - t0) / 60.0
			break
	h.free_sim()
	return snappedf(secs, 0.1)


func test_a_human_like_night_watch_catches_runner_bots() -> void:
	var caught := 0
	var n := 0
	var times: Array = []
	for gap in [6.0, 8.0]:
		for si in STARTS.size():
			var s: float = await _human_chase(si, gap, 20.0)
			times.append(s)
			n += 1
			if s > 0.0:
				caught += 1
	var got: Array = times.filter(func(x: float) -> bool: return x > 0.0)
	got.sort()
	var med := -1.0 if got.is_empty() else float(got[got.size() / 2])
	print("BOTFAIR human-like chaser vs runner bot, 6 m x4 then 8 m x4 (s, -1 = got away 20 s): %s; caught %d/%d, median %.1f s" % [str(times), caught, n, med])
	t.check(caught >= 6, "a human-like Night Watch catches a fleeing runner bot from 6-8 m on open ground (%d/%d in 20 s)" % [caught, n])


# ---------------------------------------------------------------------------
# A Night Watch bot against a careless runner
# ---------------------------------------------------------------------------
## The runner jogs straight across open lawn at full speed (it never looks
## back or dodges); the Night Watch bot starts 9 m to its side, looking at
## it.  Seconds to the catch, -1 for none in `limit` s.
func _careless(si: int, limit: float) -> float:
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2], [1], 900 + si)
	await h.release_patrol()
	var a0: Vector3 = STARTS[si][0]
	var d: Vector2 = STARTS[si][1]
	var side := Vector2(-d.y, d.x)
	var rp := Vector2(a0.x, a0.z) - d * 8.0
	h.place(0, h.on_ground(rp), atan2(-d.x, -d.y))
	var wp := rp + side * 9.0
	var look := (rp - wp).normalized()
	h.place(1, h.on_ground(wp), atan2(-look.x, -look.y))
	var r := h.sim.player(0)
	var t0 := h.sim.tick
	var secs := -1.0
	var heading := d
	for i in int(limit * 60.0):
		# straight on, turning back along the lane at its ends
		if r.pos2().distance_to(rp) > 26.0 and (r.pos2() - rp).dot(heading) > 0.0:
			heading = -heading
		h.cmd(0).move = heading
		h.cmd(0).cam_yaw = atan2(-heading.x, -heading.y)
		await h.step()
		if r.state == TC.PState.CAPTURED:
			secs = float(h.sim.tick - t0) / 60.0
			break
	h.free_sim()
	return snappedf(secs, 0.1)


func test_a_night_watch_bot_still_catches_a_careless_runner() -> void:
	var times: Array = []
	var caught := 0
	for si in STARTS.size():
		var s: float = await _careless(si, 25.0)
		times.append(s)
		if s > 0.0:
			caught += 1
	print("BOTFAIR Night Watch bot vs careless runner (s, -1 = none in 25 s): %s" % str(times))
	t.check(caught >= 3, "a Night Watch bot is still a threat: it catches a careless runner (%d/%d)" % [caught, STARTS.size()])
