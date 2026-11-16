extends RefCounted
## 2.3 bush hiding: the bushes sit on open lawn (the same on every device),
## a runner beside one hides with Interact, is out of the Night Watch's
## sight while inside, can still be tagged by a lunge at the bush, and hops
## out with Interact or Jump.
var t

const R := TC.Role.RUNNER
const P := TC.Role.PATROL


func test_bushes_on_open_ground() -> void:
	for id in [CampusMaps.CLASSIC, CampusMaps.DEFAULT_ID]:
		var lay := CampusMaps.layout(id)
		var sp := HideBushes.spots(lay)
		t.check(sp.size() >= 6 and sp.size() <= HideBushes.MAX, "%s: a handful of bushes (%d)" % [id, sp.size()])
		t.eq(sp, HideBushes.spots(CampusMaps.layout(id)), "%s: the same spots every time" % id)
		for i in sp.size():
			var p: Vector2 = sp[i]
			t.check(lay._open_ground(p, HideBushes.RADIUS), "%s: bush %d on open ground" % [id, i])
			t.check(not lay.is_on_path(p, HideBushes.RADIUS) and not lay.is_on_road(p, HideBushes.RADIUS), "%s: bush %d off the paths and roads" % [id, i])
			for j in range(i + 1, sp.size()):
				t.check(p.distance_to(sp[j]) >= HideBushes.MIN_GAP - 0.01, "%s: bushes %d and %d apart" % [id, i, j])


func test_hide_unseen_tag_and_jump_out() -> void:
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2], [], 11, {"map": CampusMaps.CLASSIC})
	await h.release_patrol()
	var r := h.sim.player(0)
	var q := h.sim.player(1)
	var bp: Vector2 = h.sim.hide_bushes[0]
	h.place(0, h.on_ground(Vector2(bp.x + 1.2, bp.y)))
	await h.step(6)
	h.press(0, TC.BTN_INTERACT)
	await h.step()
	t.eq(r.state, TC.PState.HIDING, "Interact beside a bush hides the runner")
	t.check(Vector2(r.pos().x, r.pos().z).distance_to(bp) < 0.2, "in the bush's middle")
	t.check(r.is_taggable(), "still taggable")
	# a Night Watch 9 m away looking straight at the bush doesn't spot them
	var qp := Vector2(bp.x, bp.y + 9.0)
	h.place(1, h.on_ground(qp), 0.0)
	await h.step(30)
	t.check(r.spotted <= 0.0, "unseen in the bush")
	t.check(h.sim.tag_candidate(q, 0.0) == null, "and no tag cue from 9 m")
	# jump out: active, with a hop
	await h.step(int(Rules.cfg.hide_min_s * 60.0) + 2)
	h.press(0, TC.BTN_JUMP)
	await h.step()
	t.eq(r.state, TC.PState.ACTIVE, "Jump hops out")
	t.check(r.vel.y > 1.0, "with a hop (%.1f)" % r.vel.y)
	h.free_sim()


func test_a_lunge_at_the_bush_tags() -> void:
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2], [], 11, {"map": CampusMaps.CLASSIC})
	await h.release_patrol()
	var r := h.sim.player(0)
	var bp: Vector2 = h.sim.hide_bushes[1]
	h.place(0, h.on_ground(Vector2(bp.x + 1.0, bp.y)))
	await h.step(6)
	h.press(0, TC.BTN_INTERACT)
	await h.step()
	t.eq(r.state, TC.PState.HIDING, "hidden")
	var qp := Vector2(bp.x, bp.y + 1.3)
	h.place(1, h.on_ground(qp), 0.0)
	await h.step(4)
	for i in 40:
		h.cmd(1).cam_yaw = 0.0
		h.press(1, TC.BTN_TAG)
		await h.step()
		if r.state == TC.PState.CAPTURED:
			break
	t.eq(r.state, TC.PState.CAPTURED, "the Night Watch tags a runner in the bush")
	t.eq(r.bush, -1, "and the bush is free again")
	h.free_sim()
