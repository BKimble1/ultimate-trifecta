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
static func curated_combos() -> Array:
	var rt := route_table()
	if rt.has("curated") and (rt["curated"] as Array).size() > 0:
		var out: Array = []
		for c in rt["curated"]:
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


## Every order (permutation) a runner could take through three targets.
static func permutations3(t: Array) -> Array:
	return [[t[0], t[1], t[2]], [t[0], t[2], t[1]], [t[1], t[0], t[2]], [t[1], t[2], t[0]], [t[2], t[0], t[1]], [t[2], t[1], t[0]]]


## Fair role rotation. players: Array of {slot, pref: "runner"/"patrol"/"any",
## patrol_rounds: int, last_was_patrol: bool, is_bot: bool}.
## Returns Dictionary slot -> TC.Role. Never forces a runner-preferring human into
## patrol while a willing player (or a bot) is available.
static func assign_roles(players: Array, patrol_slots: int, seed_v: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var scored: Array = []
	for p in players:
		var pref: String = p.get("pref", "any")
		var tier := 1
		if pref == "patrol":
			tier = 0
		elif pref == "runner":
			tier = 3
		if bool(p.get("is_bot", false)):
			tier = 2  # bots take patrol before anyone who asked to run
		var key := [tier, int(p.get("patrol_rounds", 0)), 1 if bool(p.get("last_was_patrol", false)) else 0, rng.randf()]
		scored.append({"slot": p["slot"], "key": key})
	scored.sort_custom(func(x, y): return _key_less(x["key"], y["key"]))
	var roles := {}
	for i in scored.size():
		roles[scored[i]["slot"]] = TC.Role.PATROL if i < patrol_slots else TC.Role.RUNNER
	return roles


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
