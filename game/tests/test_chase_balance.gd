extends RefCounted
## Chase balance with real movement and the real bots: on open ground the Night
## Watch runs a fleeing runner down (a credible chase).  Pass 9: both run at
## one steady full speed (runner 6.0, Night Watch 6.6 m/s), so on a straight
## the Watch closes at their difference; a runner's separation comes from
## finite tools (Turbo for its duration, routes, timing), never a meter.
var t
const R := TC.Role.RUNNER
const P := TC.Role.PATROL
# open lawn starts: runner position + flee heading; the patrol starts 8 m behind
const STARTS := [[Vector3(-20, 0.05, 60), Vector2(1, 0)], [Vector3(-20, 0.05, 60), Vector2(0, -1)],
	[Vector3(-20, 0.05, 60), Vector2(-1, 0)], [Vector3(30, 0.05, 62), Vector2(0, -1)]]


func test_night_watch_runs_down_a_fleeing_runner_in_the_open() -> void:
	var caught := 0
	var times: Array = []
	for si in STARTS.size():
		var h := SimHarness.new(t)
		h.make([R, P], [0, 1, 2], [0, 1], 500 + si)
		await h.release_patrol()
		var a0: Vector3 = STARTS[si][0]
		var d: Vector2 = STARTS[si][1]
		# on the ground there (the campus has its real grades)
		var a := h.on_ground(Vector2(a0.x, a0.z))
		h.place(0, a, atan2(-d.x, -d.y))
		h.place(1, h.on_ground(Vector2(a0.x, a0.z) - d * 8.0), atan2(-d.x, -d.y))
		var t0 := h.sim.tick
		var secs := -1.0
		for i in 60 * 25:
			await h.step()
			if h.sim.player(0).state == TC.PState.CAPTURED:
				secs = float(h.sim.tick - t0) / 60.0
				break
		times.append(snappedf(secs, 0.1))
		if secs > 0.0:
			caught += 1
		h.free_sim()
	print("CHASE times (s, -1 = escaped 25 s): %s" % str(times))
	t.check(caught >= 3, "patrol bot catches a fleeing runner bot from 8 m on open ground (%d/%d within 25 s)" % [caught, STARTS.size()])


func test_steady_closure_and_turbo_opens_the_gap_for_its_duration() -> void:
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2])
	await h.release_patrol()
	h.place(0, h.on_ground(Vector2(-20, 60)), atan2(-1.0, 0.0))
	h.place(1, h.on_ground(Vector2(-26, 60)), atan2(-1.0, 0.0))
	h.cmd(0).move = Vector2(1, 0)
	h.cmd(1).move = Vector2(1, 0)
	h.cmd(0).held = TC.BTN_SPRINT   # the retired Sprint bit: adds nothing
	await h.step(30)   # both up to speed
	var g0 := h.sim.player(0).pos2().distance_to(h.sim.player(1).pos2())
	await h.step(120)  # 2 s of plain full-speed running
	var g1 := h.sim.player(0).pos2().distance_to(h.sim.player(1).pos2())
	var want := (Rules.cfg.patrol_speed - Rules.cfg.runner_speed) * 2.0
	t.near(g0 - g1, want, 0.15, "full speed against full speed: the Night Watch closes %.2f m in 2 s (theory %.2f)" % [g0 - g1, want])
	var r := h.sim.player(0)
	r.gadget = TC.Gadget.TURBO
	h.press(0, TC.BTN_GADGET)
	await h.step()
	t.check(r.turbo_t > 0.0, "Turbo on")
	await h.step(int(Rules.cfg.turbo_duration_s * 60.0) - 1)
	var g2 := h.sim.player(0).pos2().distance_to(h.sim.player(1).pos2())
	t.check(g2 > g1 + 1.5, "Turbo opens the gap for its duration (%.1f m -> %.1f m)" % [g1, g2])
	await h.step(180)  # Turbo over: the Night Watch closes again
	var g3 := h.sim.player(0).pos2().distance_to(h.sim.player(1).pos2())
	t.check(g3 < g2 - 1.2, "after Turbo the Night Watch closes in again (%.1f m -> %.1f m)" % [g2, g3])
	h.free_sim()
