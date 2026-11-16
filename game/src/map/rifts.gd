class_name Rifts
extends RefCounted
## (2.2 build 16) Rift portals.  A few shimmering rifts stand on the campus
## lawns.  Step into one (on foot, runner or Night Watch) and you pop out of
## its far end, somewhere else on the campus; that rift then closes.  After
## REOPEN_S a new rift opens at another spot.  Spots come from the map's
## open ground (its coin spots, away from water, buildings, dorms and the
## power-ups), so every device works out the same list; which spots are open
## and where each leads is the host's and travels in the snapshot.

## (2.2 build 17) rarer: at most two at once, each appearing after a random
## wait, staying a while, then fading if nobody used it
const COUNT := 2            # rift slots (at most this many open at once)
const RADIUS := 1.1         # step this close to the centre to go through
const FIRST_WAIT := Vector2(20.0, 70.0)   # seconds into the round a slot first opens
const REOPEN_WAIT := Vector2(50.0, 110.0) # after it closes (used or faded)
const LIFE := Vector2(45.0, 75.0)         # how long an unused rift stays open
const REOPEN_S := 50.0      # (the shortest reopen wait; tests)
const MIN_TRIP := 55.0      # a rift never leads somewhere this close
const SPAWN_GUARD := 14.0   # nor opens this close to a dorm door

static var _cache := {}


## Candidate spots (indices are what the snapshot carries; at most 255).
static func spots(layout: CampusLayout) -> Array:
	var key := layout.get_instance_id()
	if _cache.has(key):
		return _cache[key]
	var out: Array = []
	var gadget: Array = layout.gadget_spots
	var coins: Array = layout.coin_spots
	for sp in coins:
		# (beside a coin spot, never on one: a runner picking up a coin
		# would otherwise be whisked away)
		var p := Vector2.INF
		for off in [Vector2(5, 0), Vector2(0, 5), Vector2(-5, 0), Vector2(0, -5)]:
			var c: Vector2 = (sp as Vector2) + off
			var clear := true
			for q in coins:
				if (q as Vector2).distance_to(c) < 4.0:
					clear = false
					break
			if clear and layout._open_ground(c, 1.6):
				p = c
				break
		if p == Vector2.INF:
			continue
		var bad := false
		for g in gadget:
			if (g as Vector2).distance_to(p) < 6.0:
				bad = true
				break
		for d in layout.dorm_doors:
			if not bad and _v2(d).distance_to(p) < SPAWN_GUARD:
				bad = true
		for q in out:
			if not bad and (q as Vector2).distance_to(p) < 10.0:
				bad = true
		if not bad:
			out.append(p)
		if out.size() >= 200:
			break
	_cache[key] = out
	return out


static func _v2(d: Variant) -> Vector2:
	if d is Vector2:
		return d
	if d is Dictionary:
		var p: Variant = (d as Dictionary).get("pos", (d as Dictionary).get("p", Vector2.ZERO))
		return Vector2(p.x, p.z) if p is Vector3 else (p as Vector2)
	if d is Vector3:
		return Vector2((d as Vector3).x, (d as Vector3).z)
	return Vector2.ZERO


## A fresh rift: {at, to, open, wait} (spot indices), avoiding spots in use.
static func pick(layout: CampusLayout, rng: RandomNumberGenerator, used: Dictionary) -> Dictionary:
	var sp := spots(layout)
	if sp.size() < 2:
		return {}
	for attempt in 40:
		var a := rng.randi_range(0, sp.size() - 1)
		if used.has(a):
			continue
		var best := -1
		var best_d := 0.0
		for k in 12:
			var b := rng.randi_range(0, sp.size() - 1)
			if b == a or used.has(b):
				continue
			var d := (sp[a] as Vector2).distance_to(sp[b])
			if d >= MIN_TRIP and d > best_d:
				best = b
				best_d = d
		if best >= 0:
			return {"at": a, "to": best, "open": true, "wait": 0.0, "life": rng.randf_range(LIFE.x, LIFE.y)}
	return {}


static func world(layout: CampusLayout, idx: int) -> Vector3:
	var sp := spots(layout)
	if idx < 0 or idx >= sp.size():
		return Vector3.ZERO
	var v: Vector2 = sp[idx]
	return Vector3(v.x, CampusBuilder.grid_y(layout, v.x, v.y), v.y)
