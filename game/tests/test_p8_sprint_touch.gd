extends RefCounted
## Pass 8 sprint contract through real touches (InputEventScreenTouch/Drag
## parsed by Input at rendered coordinates, TouchControls -> Controls ->
## MatchController -> sim) in a Practice round on a clear straight, using the
## V7 stick-round harness: a thumb pushed to the stick's edge (edge sprint)
## and parked there sprints once, then runs while the meter is empty however
## long it stays there; easing back under the edge-sprint exit threshold lets
## it recharge, and pushing to the edge again sprints at once.
var t
var sr   # test_stick_round instance (its harness)


func _setup() -> void:
	sr = load("res://tests/test_stick_round.gd").new()
	sr.t = t
	await sr._begin(false)


func test_edge_sprint_parks_rests_and_rearms() -> void:
	await _setup()
	t.check(not sr.corridor.is_empty(), "a clear straight was found")
	if sr.corridor.is_empty():
		await sr._end()
		return
	var mc: MatchController = sr.mc
	var r: Object = mc.touch.surface.router
	var R: float = r.get("stick_radius")
	var off: float = r.get("sprint_off")
	var z: Rect2 = r.call("zone")
	var at := Vector2(z.position.x + 1.6 * R, z.end.y - 1.6 * R)
	sr._place()
	await t.get_tree().physics_frame
	var p := mc.sim.player(mc.local_slot)
	var yaw0: float = sr.corridor["yaw"]
	var fwd := Vector3(-sin(yaw0), 0, -cos(yaw0))
	var start := p.body.global_position
	sr._touch(0, at, true)
	await t.get_tree().physics_frame
	var last := at
	var phases := [
		["park at the edge", 6.0, Vector2(0, -R)],
		["ease off under the exit threshold", 2.5, Vector2(0, -R * (off - 0.16))],
		["push to the edge again", 1.5, Vector2(0, -R)],
	]
	var log := {}
	for ph in phases:
		var to: Vector2 = at + (ph[2] as Vector2)
		sr._drag(0, last, to)
		last = to
		var bursts := 0
		var was := p.sprinting
		var first_sprint := -1
		var exhausted_seen := false
		var shown_on_while_latched := 0
		var shown_latched := 0
		for i in int(float(ph[1]) * 60.0):
			await t.get_tree().physics_frame
			if p.sprinting and not was:
				bursts += 1
			if p.sprinting and first_sprint < 0:
				first_sprint = i
			was = p.sprinting
			exhausted_seen = exhausted_seen or p.sprint_exhausted
			# what the stick draws follows the motor (sampled once the HUD has the state)
			if p.sprint_exhausted and mc.hud and bool(mc.hud.info.get("sprint_exhausted", false)):
				var st: Dictionary = mc.touch.surface.stick_sprint_state()
				shown_on_while_latched += 1 if bool(st["sprinting"]) else 0
				shown_latched += 1 if bool(st["latched"]) else 0
			# keep the runner on the clear straight (motor state untouched)
			if (p.body.global_position - start).dot(fwd) > 34.0:
				p.body.global_position -= fwd * 28.0
		log[ph[0]] = {"bursts": bursts, "first": first_sprint, "end_sprinting": p.sprinting, "meter": p.sprint,
			"exhausted": p.sprint_exhausted, "exhausted_seen": exhausted_seen, "held": Controls.touch_sprint,
			"shown_on_while_latched": shown_on_while_latched, "shown_latched": shown_latched}
	sr._touch(0, last, false)
	var park: Dictionary = log["park at the edge"]
	var ease: Dictionary = log["ease off under the exit threshold"]
	var again: Dictionary = log["push to the edge again"]
	t.check(int(park["first"]) >= 0 and int(park["first"]) <= 3, "the edge push sprints at once (tick %d)" % int(park["first"]))
	t.eq(int(park["bursts"]), 1, "parked at the edge for 6 s: one burst, never restarted (%d bursts)" % int(park["bursts"]))
	t.check(bool(park["exhausted"]) and not bool(park["end_sprinting"]), "and still parked, it runs with the meter empty")
	t.check(int(park["shown_latched"]) > 60 and int(park["shown_on_while_latched"]) == 0,
		"parked and latched, the stick shows the latch, never sprint on (%d latched frames, %d shown on)" % [int(park["shown_latched"]), int(park["shown_on_while_latched"])])
	t.check(not bool(ease["held"]), "easing under the exit threshold releases sprint")
	t.check(not bool(ease["exhausted"]) and float(ease["meter"]) >= Rules.cfg.sprint_rearm_fraction, "and lets the meter re-arm (%.2f)" % float(ease["meter"]))
	t.check(int(again["first"]) >= 0 and int(again["first"]) <= 3, "pushing to the edge again sprints at once (tick %d)" % int(again["first"]))
	await sr._end()
