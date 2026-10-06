extends SceneTree
## Route analysis (campus rebuild): route lengths on the runners' nav grid
## between each start dorm and every water of the objective pool, the best
## order for every three-target combination per dorm, and the curated fair
## set per dorm.  Measured, not assumed: nothing here changes the campus,
## the speeds or the timer; the report says how long the real routes are.
## Usage: godot --headless --path game -s res://tools/route_analysis.gd
## Writes res://config/route_table.json (and prints a report).
##
## A trip starts on the dorm's middle pad, leaves through its nearest door,
## visits the three waters (in at a jump point, out at a shore exit) and
## ends just inside the door nearest the last water.  Distances come from
## multi-source route fields (PaceFields.flood, the same solid cells, wall
## and fence costs and corner rule as the bots' A*): one field per water
## (its jump points and exits) and one per dorm (its doors' approach
## points).  One band around the median of ALL dorms' trips keeps the round
## length comparable whichever dorm is home; measured bot times (from
## tools/dorm_balance.gd, config/route_bot_times.json "dorms") tighten it.

const BAND := 0.16       # nav-distance band (used when no measured times exist)
const TIME_BAND := 0.12  # measured bot-time band around the median
## Real scale: the reference campus's routes are far longer than the old
## map's, and the round stays 240 s.  A combination is kept only when its
## ideal run (full speed on the measured route, three splashes) fits in
## this share of the round, leaving time to dodge the Night Watch; if fewer
## than MIN_CURATED fit, the shortest ones are kept (and reported).
const FEASIBLE_SHARE := 0.85
const MIN_CURATED := 3


func _initialize() -> void:
	var cfg: RulesConfig = load("res://config/rules_default.tres")
	var lay := CampusLayout.new()
	var nav := NavGrid.new(lay)
	var grid := _grid(nav)
	var pool := lay.pool_size()
	var wf: Array = []
	for i in pool:
		var w: Dictionary = lay.waters[i]
		var src := PackedVector2Array()
		for jp in w["jump_points"]:
			src.append(jp)
		for e in w["exits"]:
			src.append(Vector2((e as Vector3).x, (e as Vector3).z))
		wf.append(_field(grid, src))
	var measured_all := {}
	if FileAccess.file_exists("res://config/route_bot_times.json"):
		var mv: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://config/route_bot_times.json"))
		if mv is Dictionary:
			measured_all = mv
	var per_dorm := {}
	var all_lens: Array = []
	for id in CampusDorms.ids():
		var r := _dorm_routes(lay, nav, grid, wf, id)
		per_dorm[id] = r
		for cb in r["combos"]:
			all_lens.append(float(cb["length_m"]))
	all_lens.sort()
	var median: float = all_lens[all_lens.size() / 2]
	var tall: Array = []
	for dk in measured_all.get("dorms", {}):
		for v in (measured_all["dorms"][dk] as Dictionary).values():
			tall.append(float(v))
	tall.sort()
	var tmed := float(tall[tall.size() / 2]) if not tall.is_empty() else 0.0
	var dorms_out := {}
	var speed := float(cfg.runner_speed)
	var splash := float(cfg.splash_sequence_s)
	for id in per_dorm:
		var r: Dictionary = per_dorm[id]
		var measured: Dictionary = (measured_all.get("dorms", {}) as Dictionary).get(id, {})
		var curated: Array = []
		var limit := float(cfg.match_duration_s) * FEASIBLE_SHARE
		for cb in r["combos"]:
			var L2: float = cb["length_m"]
			cb["vs_median"] = snappedf(L2 / median, 0.01)
			# the ideal run: full speed on the measured route, three splash
			# sequences, nothing in the way (a floor, not a forecast)
			cb["ideal_s"] = snappedf(L2 / speed + 3.0 * splash, 0.1)
			cb["fits_round"] = float(cb["ideal_s"]) <= limit
			var key := str(cb["targets"])
			if measured.has(key):
				cb["bot_time_s"] = measured[key]
				cb["time_vs_median"] = snappedf(float(measured[key]) / tmed, 0.01) if tmed > 0.0 else 0.0
			var ok := bool(cb["fits_round"])
			if measured.has(key):
				ok = ok and float(measured[key]) <= float(cfg.match_duration_s) * 0.95
			if ok:
				curated.append(cb["targets"])
		if curated.size() < MIN_CURATED:
			var by_len: Array = (r["combos"] as Array).duplicate()
			by_len.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["length_m"]) < float(y["length_m"]))
			for cb2 in by_len:
				if curated.size() >= MIN_CURATED:
					break
				if not curated.has(cb2["targets"]):
					curated.append(cb2["targets"])
		dorms_out[id] = {"curated": curated, "combos": r["combos"], "pair_m": r["pair_m"], "bot_time_median_s": tmed,
			"door_m": r["door_m"], "unreachable": r["unreachable"]}
		print("%s: curated %d/%d" % [id, curated.size(), (r["combos"] as Array).size()])
		for cb in r["combos"]:
			print("  %-36s best %-36s %7.1f m  ideal %5.1f s  (%.2f)%s" % [str(cb["targets"].map(func(i): return lay.waters[i]["short"])), str(cb["best_order"].map(func(i): return lay.waters[i]["short"])),
				cb["length_m"], cb["ideal_s"], cb["vs_median"], ("" if curated.has(cb["targets"]) else "   EXCLUDED") + ("" if bool(cb["fits_round"]) else " (does not fit the round)")])
		if not (r["unreachable"] as Array).is_empty():
			print("  UNREACHABLE: %s" % str(r["unreachable"]))
	var home: Dictionary = dorms_out[CampusDorms.default_id()]
	var names: Array = ["dorm"]
	for i in pool:
		names.append(lay.waters[i]["id"])
	var round_s := float(cfg.match_duration_s)
	var out := {
		"generated_by": "tools/route_analysis.gd", "band": BAND, "time_band": TIME_BAND, "median_m": snappedf(median, 0.1),
		"rule": "keep combinations whose ideal run fits %.0f%% of the round (fewer than %d: the shortest)" % [FEASIBLE_SHARE * 100.0, MIN_CURATED],
		"feasible_share": FEASIBLE_SHARE,
		"nodes": names, "pair_m": home["pair_m"], "combos": home["combos"], "curated": home["curated"],
		"unreachable": home["unreachable"], "bot_time_median_s": home["bot_time_median_s"],
		"dorms": dorms_out, "dorm_version": CampusDorms.VERSION, "campus": CampusData.shared().campus_hash,
		"runner_speed": speed, "round_s": round_s,
		"runner_estimate_s": {"min": snappedf(float(all_lens[0]) / speed + 3.0 * splash, 1), "median": snappedf(median / speed + 3.0 * splash, 1),
			"max": snappedf(float(all_lens[-1]) / speed + 3.0 * splash, 1)},
	}
	var f := FileAccess.open("res://config/route_table.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	print("median over all dorms %.1f m; ideal runs %.0f..%.0f s (median %.0f s) against a %.0f s round" % [median,
		float(out["runner_estimate_s"]["min"]), float(out["runner_estimate_s"]["max"]), float(out["runner_estimate_s"]["median"]), round_s])
	quit()


## The runners' grid as flat arrays (PaceFields' layout: border solid).
func _grid(nav: NavGrid) -> Dictionary:
	var w := nav.dims.x
	var h := nav.dims.y
	var solid := PackedByteArray()
	solid.resize(w * h)
	var wt := PackedByteArray()
	wt.resize(w * h)
	for y in h:
		for x in w:
			var c := Vector2i(x, y)
			var i := y * w + x
			solid[i] = 1 if nav.foot.is_point_solid(c) or x < 1 or y < 1 or x >= w - 1 or y >= h - 1 else 0
			wt[i] = clampi(int(round(nav.foot.get_point_weight_scale(c))), 1, 6)
	return {"nav": nav, "w": w, "h": h, "solid": solid, "wt": wt}


func _cell(grid: Dictionary, p: Vector2) -> int:
	var nav: NavGrid = grid["nav"]
	var c := nav.nearest_open(nav.foot, p, 3)
	return -1 if nav.foot.is_point_solid(c) else c.y * int(grid["w"]) + c.x


func _field(grid: Dictionary, src: PackedVector2Array) -> PackedInt32Array:
	var cells := PackedInt32Array()
	for p in src:
		var c := _cell(grid, p)
		if c >= 0:
			cells.append(c)
	return PaceFields.flood(grid["solid"], grid["wt"], int(grid["w"]), int(grid["h"]), cells)["d"]


## Metres from a field to the nearest of some points (INF if none reachable).
func _to(grid: Dictionary, field: PackedInt32Array, pts: Array) -> float:
	var best := INF
	for p in pts:
		var q: Vector2 = p if p is Vector2 else Vector2((p as Vector3).x, (p as Vector3).z)
		var c := _cell(grid, q)
		if c < 0 or field[c] >= PaceFields.UNREACH:
			continue
		best = minf(best, float(field[c]) / PaceFields.UNIT * NavGrid.CELL)
	return best


## One dorm: node 0 the dorm, nodes 1..pool the waters.
func _dorm_routes(lay: CampusLayout, nav: NavGrid, grid: Dictionary, wf: Array, id: String) -> Dictionary:
	var g := CampusDorms.geometry(id)
	var pool := wf.size()
	var start: Vector2 = g["pads"][0]["pos"]
	var approaches: Array = []
	for dr in g["doors"]:
		approaches.append(dr["approach"])
	var df := _field(grid, PackedVector2Array(approaches))
	# pad -> out of the nearest door; approach -> just inside (way home)
	var door_out := INF
	var door_in := INF
	for dr in g["doors"]:
		var p := nav.find_path(start, dr["approach"], false)
		if p.size() >= 2:
			door_out = minf(door_out, nav.path_length(p))
		var p2 := nav.find_path(dr["approach"], dr["inside"], false)
		if p2.size() >= 2:
			door_in = minf(door_in, nav.path_length(p2))
	var n := pool + 1
	var dist := []
	for i in n:
		var row := []
		row.resize(n)
		row.fill(0.0)
		dist.append(row)
	var unreachable: Array = []
	var home := [0.0]
	for j in pool:
		var w: Dictionary = lay.waters[j]
		var out_d := door_out + _to(grid, df, w["jump_points"])
		dist[0][j + 1] = out_d
		dist[j + 1][0] = out_d
		home.append(_to(grid, df, w["exits"]) + door_in)
		if out_d == INF:
			unreachable.append("dorm-%s" % w["id"])
		for k in range(j + 1, pool):
			var d2 := _to(grid, wf[j], lay.waters[k]["jump_points"])
			var d3 := _to(grid, wf[k], lay.waters[j]["jump_points"])
			var d := minf(d2, d3)
			dist[j + 1][k + 1] = d
			dist[k + 1][j + 1] = d
			if d == INF:
				unreachable.append("%s-%s" % [w["id"], lay.waters[k]["id"]])
	var combos: Array = []
	for c in RulesLogic.all_combos(pool):
		var best_len := INF
		var best_order: Array = []
		for perm in RulesLogic.permutations3(c):
			var L: float = dist[0][perm[0] + 1] + dist[perm[0] + 1][perm[1] + 1] + dist[perm[1] + 1][perm[2] + 1] + float(home[perm[2] + 1])
			if L < best_len:
				best_len = L
				best_order = perm
		combos.append({"targets": c, "best_order": best_order, "length_m": snappedf(best_len, 0.1),
			"first_m": snappedf(float(dist[0][best_order[0] + 1]), 0.1)})
	return {"combos": combos, "pair_m": dist.map(func(r): return r.map(func(v): return snappedf(v, 0.1) if v != INF else -1.0)),
		"unreachable": unreachable, "door_m": [snappedf(door_out, 0.1), snappedf(door_in, 0.1)]}
