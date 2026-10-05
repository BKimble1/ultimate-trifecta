extends RefCounted
## Pass 9 full-speed contract through real touches (InputEventScreenTouch/Drag
## parsed by Input at rendered coordinates, TouchControls -> Controls ->
## MatchController -> sim) in a Practice round on a clear straight, using the
## V7 stick-round harness.  There is no sprint meter: a thumb pushed to the
## stick's rim and parked there holds the runner's one full speed for a whole
## minute without a single drop; small thumb jitter near the rim changes
## nothing; easing back to a part push jogs (not fast) and pushing out again
## is full speed at once.  The stick shows "full" exactly while the thumb is
## at the full-speed radius, and no Sprint button, meter or hint is shown.
var t
var sr   # test_stick_round instance (its harness)


func _setup() -> void:
	sr = load("res://tests/test_stick_round.gd").new()
	sr.t = t
	await sr._begin(false)


static func _hspeed(p: SimPlayer) -> float:
	return Vector2(p.vel.x, p.vel.z).length()


func test_rim_holds_full_speed_for_a_minute() -> void:
	await _setup()
	t.check(not sr.corridor.is_empty(), "a clear straight was found")
	if sr.corridor.is_empty():
		await sr._end()
		return
	var mc: MatchController = sr.mc
	var r: Object = mc.touch.surface.router
	var R: float = r.get("stick_radius")
	var z: Rect2 = r.call("zone")
	var at := Vector2(z.position.x + 1.6 * R, z.end.y - 1.6 * R)
	sr._place()
	await t.get_tree().physics_frame
	var p := mc.sim.player(mc.local_slot)
	var top := Rules.cfg.runner_speed
	var yaw0: float = sr.corridor["yaw"]
	var fwd := Vector3(-sin(yaw0), 0, -cos(yaw0))
	var start := p.body.global_position
	sr._touch(0, at, true)
	await t.get_tree().physics_frame
	var last := at
	# [label, seconds, thumb offset at time s (from the touchdown point)]
	var phases := [
		["park at the rim", 60.0, func(_s: float) -> Vector2: return Vector2(0, -R)],
		["jitter near the rim", 6.0, func(s: float) -> Vector2:
			# +-4 degrees and 0.92..1.06 of the radius, a few times a second
			var a := deg_to_rad(4.0) * sin(s * TAU * 3.1)
			var m := R * (0.99 + 0.07 * sin(s * TAU * 4.3))
			return Vector2(sin(a), -cos(a)) * m],
		["ease to a part push", 2.5, func(_s: float) -> Vector2: return Vector2(0, -R * 0.6)],
		["push to the rim again", 1.5, func(_s: float) -> Vector2: return Vector2(0, -R)],
	]
	var log := {}
	for ph in phases:
		var path: Callable = ph[2]
		var n := int(float(ph[1]) * 60.0)
		var settle := 18   # touch -> controls -> sim plus the 46 m/s^2 acceleration
		var lo := INF
		var hi := 0.0
		var sum := 0.0
		var cnt := 0
		var drops := 0
		var not_fast := 0
		var first_full := -1
		var shown_full := 0
		var shown_not_full := 0
		var mag_min := INF
		for i in n:
			var to: Vector2 = at + (path.call(float(i + 1) / 60.0) as Vector2)
			if to != last:
				sr._drag(0, last, to)
				last = to
			await t.get_tree().physics_frame
			var v := _hspeed(p)
			if first_full < 0 and p.fast:
				first_full = i
			if i >= settle:
				lo = minf(lo, v)
				hi = maxf(hi, v)
				sum += v
				cnt += 1
				drops += 1 if v < top - 0.1 else 0
				not_fast += 0 if p.fast else 1
				mag_min = minf(mag_min, Controls.touch_move.length())
				if mc.touch.surface.stick_at_full():
					shown_full += 1
				else:
					shown_not_full += 1
			# keep the runner on the clear straight (motor state untouched)
			if (p.body.global_position - start).dot(fwd) > 34.0:
				p.body.global_position -= fwd * 28.0
		log[ph[0]] = {"min": lo, "max": hi, "avg": sum / maxf(1.0, float(cnt)), "drops": drops, "not_fast": not_fast,
			"first_full": first_full, "shown_full": shown_full, "shown_not_full": shown_not_full, "mag_min": mag_min}
		print("P9 TOUCH %-24s min %.3f  max %.3f  avg %.3f m/s  drops %d  not-fast %d  first fast tick %d  stick full %d/%d  input min %.3f" % [
			ph[0], lo, hi, sum / maxf(1.0, float(cnt)), drops, not_fast, first_full, shown_full, shown_full + shown_not_full, mag_min])
	# the HUD and the touch surface carry no sprint state, button or meter
	var info: Dictionary = mc.hud.info if mc.hud else {}
	var stale: Array = []
	for k in info.keys():
		if String(k).contains("sprint"):
			stale.append(k)
	t.eq(stale, [], "the HUD state has no sprint fields")
	t.check(not (r.get("buttons") as Dictionary).has("sprint"), "no Sprint touch button")
	t.check(not TouchControls.LABELS.has("sprint"), "no Sprint button label")
	sr._touch(0, last, false)
	var park: Dictionary = log["park at the rim"]
	var jit: Dictionary = log["jitter near the rim"]
	var ease: Dictionary = log["ease to a part push"]
	var again: Dictionary = log["push to the rim again"]
	t.check(float(park["min"]) >= top - 0.05 and float(park["max"]) <= top + 0.01,
		"parked at the rim for 60 s: steady %.2f m/s (min %.3f, max %.3f)" % [top, float(park["min"]), float(park["max"])])
	t.eq(int(park["drops"]), 0, "no speed drop in the minute")
	t.eq(int(park["not_fast"]), 0, "fast the whole minute (footsteps, animation and bots see full speed)")
	t.check(int(park["shown_not_full"]) == 0 and int(park["shown_full"]) > 3000, "the stick shows full speed the whole time")
	t.check(float(jit["min"]) >= top - 0.05 and int(jit["drops"]) == 0,
		"thumb jitter near the rim keeps full speed (min %.3f, input min %.3f)" % [float(jit["min"]), float(jit["mag_min"])])
	t.check(float(ease["avg"]) > 2.5 and float(ease["max"]) < top * Rules.cfg.fast_fraction,
		"a part push jogs (%.2f m/s) and is not fast" % float(ease["avg"]))
	t.check(int(ease["shown_full"]) == 0, "the stick does not show full speed at a part push")
	t.check(int(again["first_full"]) >= 0 and int(again["first_full"]) <= 8, "pushing to the rim again is full speed at once (tick %d)" % int(again["first_full"]))
	await sr._end()
