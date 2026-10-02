extends SceneTree
## Route analysis: nav-grid path lengths between each dorm and all six
## waters, the best order for every 3-target combination per dorm, and the
## curated fair set per dorm (V6).
## Usage: godot --headless --path game -s res://tools/route_analysis.gd
## Writes res://config/route_table.json
##
## V6: a round starts inside tonight's home dorm and ends running back into
## it, so a trip is measured from the dorm's middle pad out through its
## nearest door, round the three waters and back in through the door nearest
## the last water.  One band around the median of ALL dorms' trips keeps the
## round length comparable whichever dorm is home; measured bot times (from
## tools/dorm_balance.gd, config/route_bot_times.json "dorms") tighten it.
## The top-level "curated"/"combos" keep Puddlesworth Hall's values (what a
## round without a dorm in its configuration meant before V6).

const BAND := 0.16       # nav-distance band (used when no measured times exist)
const TIME_BAND := 0.12  # measured bot-time band around the median


func _initialize() -> void:
	var lay := CampusLayout.new()
	var nav := NavGrid.new(lay)
	var measured_all := {}
	if FileAccess.file_exists("res://config/route_bot_times.json"):
		var mv: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://config/route_bot_times.json"))
		if mv is Dictionary:
			measured_all = mv
	var per_dorm := {}
	var all_lens: Array = []
	for dm in lay.dorms:
		var id := String(dm["id"])
		var g: Dictionary = dm["geo"]
		var r := _dorm_routes(lay, nav, g)
		per_dorm[id] = r
		for cb in r["combos"]:
			all_lens.append(float(cb["length_m"]))
	all_lens.sort()
	var median: float = all_lens[all_lens.size() / 2]
	var dorms_out := {}
	for id in per_dorm:
		var r: Dictionary = per_dorm[id]
		var measured: Dictionary = (measured_all.get("dorms", {}) as Dictionary).get(id, {})
		if id == CampusDorms.default_id() and measured.is_empty():
			# V5 measured Puddlesworth trips at the top level
			for k in measured_all:
				if String(k).begins_with("["):
					measured[k] = measured_all[k]
		var tmed := 0.0
		var tall: Array = []
		for dk in measured_all.get("dorms", {}):
			for v in (measured_all["dorms"][dk] as Dictionary).values():
				tall.append(float(v))
		if tall.is_empty():
			for v in measured.values():
				tall.append(float(v))
		tall.sort()
		if not tall.is_empty():
			tmed = float(tall[tall.size() / 2])
		var curated: Array = []
		for cb in r["combos"]:
			var L2: float = cb["length_m"]
			cb["vs_median"] = snappedf(L2 / median, 0.01)
			var key := str(cb["targets"])
			if measured.has(key):
				cb["bot_time_s"] = measured[key]
				cb["time_vs_median"] = snappedf(float(measured[key]) / tmed, 0.01)
			var ok := absf(L2 / median - 1.0) <= BAND
			if measured.has(key) and tmed > 0.0:
				ok = ok and absf(float(measured[key]) / tmed - 1.0) <= TIME_BAND
			if ok:
				curated.append(cb["targets"])
		dorms_out[id] = {"curated": curated, "combos": r["combos"], "pair_m": r["pair_m"], "bot_time_median_s": tmed}
		print("%s: curated %d/20" % [id, curated.size()])
		for cb in r["combos"]:
			print("  %-28s best %-28s %6.1f m  (%.2f)%s" % [str(cb["targets"].map(func(i): return lay.waters[i]["short"])), str(cb["best_order"].map(func(i): return lay.waters[i]["short"])),
				cb["length_m"], cb["vs_median"], "" if curated.has(cb["targets"]) else "   EXCLUDED"])
	var home: Dictionary = dorms_out[CampusDorms.default_id()]
	var names: Array = ["dorm"]
	for w in lay.waters:
		names.append(w["id"])
	var out := {
		"generated_by": "tools/route_analysis.gd", "band": BAND, "time_band": TIME_BAND, "median_m": snappedf(median, 0.1),
		"nodes": names, "pair_m": home["pair_m"], "combos": home["combos"], "curated": home["curated"],
		"unreachable": per_dorm[CampusDorms.default_id()]["unreachable"], "bot_time_median_s": home["bot_time_median_s"],
		"dorms": dorms_out, "dorm_version": CampusDorms.VERSION,
		"runner_estimate_s": {"min": snappedf(float(all_lens[0]) / 5.6 + 6.0, 1), "median": snappedf(median / 5.6 + 6.0, 1), "max": snappedf(float(all_lens[-1]) / 5.6 + 6.0, 1)},
	}
	var f := FileAccess.open("res://config/route_table.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	print("median over all dorms %.1f m" % median)
	quit()


## Path lengths for one dorm: node 0 is the dorm (out from the middle pad
## through the best door; back in through the best door to just inside),
## nodes 1..6 the waters' jump points.
func _dorm_routes(lay: CampusLayout, nav: NavGrid, g: Dictionary) -> Dictionary:
	var start: Vector2 = g["pads"][0]["pos"]
	var nodes: Array = [["dorm", [start]]]
	for w in lay.waters:
		nodes.append([w["id"], w["jump_points"]])
	var n := nodes.size()
	var dist := []
	for i in n:
		var row := []
		for j in n:
			row.append(0.0)
		dist.append(row)
	var unreachable: Array = []
	for i in n:
		for j in range(i + 1, n):
			var best := INF
			for a in nodes[i][1]:
				for b in nodes[j][1]:
					var p := nav.find_path(a, b, false)
					if p.size() < 2:
						continue
					best = minf(best, nav.path_length(p))
			if best == INF:
				unreachable.append("%s-%s" % [nodes[i][0], nodes[j][0]])
			dist[i][j] = best
			dist[j][i] = best
	# the way home ends just inside a door (not at the middle pad)
	var home := []
	for j in n:
		var best2 := INF
		if j > 0:
			for b in nodes[j][1]:
				for dr in g["doors"]:
					var p2 := nav.find_path(b, dr["inside"], false)
					if p2.size() >= 2:
						best2 = minf(best2, nav.path_length(p2))
		home.append(best2)
	var combos: Array = []
	for c in RulesLogic.all_combos(6):
		var best_len := INF
		var best_order: Array = []
		for perm in RulesLogic.permutations3(c):
			var L: float = dist[0][perm[0] + 1] + dist[perm[0] + 1][perm[1] + 1] + dist[perm[1] + 1][perm[2] + 1] + float(home[perm[2] + 1])
			if L < best_len:
				best_len = L
				best_order = perm
		combos.append({"targets": c, "best_order": best_order, "length_m": snappedf(best_len, 0.1),
			"first_m": snappedf(float(dist[0][best_order[0] + 1]), 0.1)})
	return {"combos": combos, "pair_m": dist.map(func(r): return r.map(func(v): return snappedf(v, 0.1))), "unreachable": unreachable}
