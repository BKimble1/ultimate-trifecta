class_name RulesLogic
extends RefCounted
## Pure rule functions (no scene tree). Unit-tested directly.

const ROUTE_TABLE_PATH := "res://config/route_table.json"

static var _route_table: Dictionary = {}


static func route_table() -> Dictionary:
	if _route_table.is_empty():
		var f := FileAccess.open(ROUTE_TABLE_PATH, FileAccess.READ)
		if f:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_route_table = parsed
	return _route_table


## All 20 three-target combinations of the six waters (sorted index triples).
static func all_combos(n: int = 6) -> Array:
	var out: Array = []
	for a in n:
		for b in range(a + 1, n):
			for c in range(b + 1, n):
				out.append([a, b, c])
	return out


## Curated fair combinations (from route analysis). Falls back to all combos.
## V6: per home dorm (route_table.json "dorms"); without a dorm, the
## Puddlesworth Hall set (the V5 table's own list).
static func curated_combos(dorm_id: String = "") -> Array:
	var rt := route_table()
	var src: Variant = rt.get("curated", [])
	if dorm_id != "" and rt.get("dorms", {}) is Dictionary and (rt.get("dorms", {}) as Dictionary).has(dorm_id):
		src = (rt["dorms"][dorm_id] as Dictionary).get("curated", src)
	if src is Array and (src as Array).size() > 0:
		var out: Array = []
		for c in src:
			out.append([int(c[0]), int(c[1]), int(c[2])])
		return out
	return all_combos()


## Choose the shared targets from the match seed, avoiding an immediate repeat.
static func pick_targets(seed_v: int, previous: Array, combos: Array = []) -> Array:
	var pool := combos if not combos.is_empty() else curated_combos()
	if pool.is_empty():
		return [0, 1, 2]
	var idx := posmod(seed_v, pool.size())
	var choice: Array = pool[idx]
	if pool.size() > 1 and _same_set(choice, previous):
		choice = pool[(idx + 1) % pool.size()]
	return choice.duplicate()


static func _same_set(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for x in a:
		if not b.has(x):
			return false
	return true


## The round's gold coins (V6), chosen by the host from the seed: a few of
## the layout's candidate spots, spread out, clear of tonight's home doors
## and of the active waters' exits, jump-in points and pads.  Returns
## [{id, x, z}] (ids are the spot's index: unique within the round).
static func pick_coins(seed_v: int, layout: CampusLayout, dorm_id: String, targets: Array, cfg: RulesConfig) -> Array:
	var doors: Array = CampusDorms.geometry(dorm_id).get("doors", [])
	var cand: Array = []
	for i in layout.coin_spots.size():
		var p: Vector2 = layout.coin_spots[i]
		var ok := true
		for d in doors:
			if p.distance_to(d["pos"]) < cfg.coin_door_clearance_m:
				ok = false
		for wi in targets:
			var w: Dictionary = layout.waters[int(wi)]
			for e in w["exits"]:
				if p.distance_to(Vector2((e as Vector3).x, (e as Vector3).z)) < cfg.coin_water_clearance_m:
					ok = false
			for j in w["jump_points"]:
				if p.distance_to(j) < cfg.coin_water_clearance_m:
					ok = false
			for pad in w["pads"]:
				if p.distance_to(pad) < cfg.coin_water_clearance_m:
					ok = false
		if ok:
			cand.append(i)
	# a seeded shuffle, then greedy spacing
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v ^ 0xC01C
	for i in range(cand.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: int = cand[i]
		cand[i] = cand[j]
		cand[j] = tmp
	var out: Array = []
	for spacing in [cfg.coin_min_spacing_m, cfg.coin_min_spacing_m * 0.6, 0.0]:
		for i in cand:
			if out.size() >= cfg.coin_spawns_per_round:
				break
			var p2: Vector2 = layout.coin_spots[i]
			var clash := false
			for o in out:
				if p2.distance_to(Vector2(float(o["x"]), float(o["z"]))) < spacing or int(String(o["id"]).substr(1)) == i:
					clash = true
					break
			if not clash:
				out.append({"id": "s%02d" % i, "x": p2.x, "z": p2.y})
		if out.size() >= cfg.coin_spawns_per_round:
			break
	return out


## Every order (permutation) a runner could take through three targets.
static func permutations3(t: Array) -> Array:
	return [[t[0], t[1], t[2]], [t[0], t[2], t[1]], [t[1], t[0], t[2]], [t[1], t[2], t[0]], [t[2], t[0], t[1]], [t[2], t[1], t[0]]]


## Roles: friend parties draw them in PartySeries.assign_roles (fair random
## rotation, preferences ignored); practice uses the player's own choice.


static func _key_less(a: Array, b: Array) -> bool:
	for i in a.size():
		if a[i] < b[i]:
			return true
		if a[i] > b[i]:
			return false
	return false


## Respawn pad that maximises distance to the nearest patrol (reduces recapture).
static func choose_pad(pads: Array, patrol_positions: Array) -> Vector2:
	if pads.is_empty():
		return Vector2.ZERO
	var best: Vector2 = pads[0]
	var best_d := -1.0
	for pad in pads:
		var dmin := 1e9
		for pp in patrol_positions:
			dmin = minf(dmin, (pad as Vector2).distance_to(pp))
		if patrol_positions.is_empty():
			dmin = 0.0
		if dmin > best_d + 0.01:
			best_d = dmin
			best = pad
	return best


## Exit point after a splash: the shore exit closest to where the runner was heading.
static func choose_splash_exit(exits: Array, entry: Vector3, heading: Vector3) -> Vector3:
	var aim := entry + Vector3(heading.x, 0, heading.z).normalized() * 6.0 if Vector3(heading.x, 0, heading.z).length() > 0.5 else entry
	var best: Vector3 = exits[0]
	var bd := 1e9
	for e in exits:
		var d := (e as Vector3).distance_to(aim)
		if d < bd:
			bd = d
			best = e
	return best


## Geometric tag test (role/state/cooldown checks are done by the caller).
static func tag_geometry_ok(patrol_pos: Vector3, facing: Vector3, target_pos: Vector3, cfg: RulesConfig) -> bool:
	var rel := target_pos - patrol_pos
	var flat := Vector2(rel.x, rel.z)
	if absf(rel.y) > cfg.tag_vertical_reach_m:
		return false
	if flat.length() > cfg.tag_reach_m:
		return false
	if flat.length() < 0.25:
		return true
	var f := Vector2(facing.x, facing.z).normalized()
	var ang := rad_to_deg(acos(clampf(f.dot(flat.normalized()), -1.0, 1.0)))
	return ang <= cfg.tag_half_angle_deg


## Coins/XP for one player from authoritative results. Unique captures only.
static func compute_rewards(results: Dictionary, slot: int, cfg: RulesConfig, practice: bool) -> Dictionary:
	var me: Dictionary = {}
	for r in results.get("players", []):
		if int(r["slot"]) == slot:
			me = r
	if me.is_empty() or results.get("outcome", TC.Outcome.NONE) == TC.Outcome.CANCELLED:
		return {"coins": 0, "xp": 0, "lines": []}
	var lines: Array = []
	var coins := cfg.coins_participation
	lines.append(["Played the round", cfg.coins_participation])
	var role: int = me["role"]
	var outcome: int = results["outcome"]
	if role == TC.Role.RUNNER:
		var s := int(me.get("stamps", 0))
		if s > 0:
			coins += s * cfg.coins_per_stamp
			lines.append(["Splashes x%d" % s, s * cfg.coins_per_stamp])
		if bool(me.get("finished", false)):
			coins += cfg.coins_finish
			lines.append(["Made it home", cfg.coins_finish])
		if outcome == TC.Outcome.RUNNERS_WIN:
			coins += cfg.coins_team_win
			lines.append(["Runners win", cfg.coins_team_win])
		if int(results.get("fastest_slot", -1)) == slot:
			coins += cfg.coins_fastest_trifecta
			lines.append(["Fastest Trifecta", cfg.coins_fastest_trifecta])
	else:
		var u := int(me.get("unique_captures", 0))
		if u > 0:
			coins += u * cfg.coins_unique_capture
			lines.append(["Different runners caught x%d" % u, u * cfg.coins_unique_capture])
		if outcome == TC.Outcome.PATROL_WIN:
			coins += cfg.coins_team_win
			lines.append(["Night Watch wins", cfg.coins_team_win])
	if practice:
		var scaled := int(round(float(coins) * cfg.practice_reward_scale))
		lines.append(["Practice (x%.1f)" % cfg.practice_reward_scale, scaled - coins])
		coins = scaled
	return {"coins": coins, "xp": coins, "lines": lines}


static func xp_for_level(level: int, cfg: RulesConfig) -> int:
	return int(round(float(cfg.level_xp_base) * pow(cfg.level_xp_growth, float(level - 1))))


## Applies xp to (level, xp_into_level). Returns [level, xp].
static func add_xp(level: int, xp: int, gained: int, cfg: RulesConfig) -> Array:
	var lv := level
	var x := xp + gained
	while x >= xp_for_level(lv, cfg):
		x -= xp_for_level(lv, cfg)
		lv += 1
	return [lv, x]
