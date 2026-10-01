extends SceneTree
## Route analysis: nav-grid path lengths between the dorm and all six waters,
## the best order for every 3-target combination, and the curated fair set.
## Usage: godot --headless --path game -s res://tools/route_analysis.gd
## Writes res://config/route_table.json

const BAND := 0.16   # keep combos within +-16% of the median optimal route


func _initialize() -> void:
	var lay := CampusLayout.new()
	var nav := NavGrid.new(lay)
	var nodes: Array = []   # [name, [points...]]
	var dorm_pts: Array = []
	for d in lay.dorm_doors:
		dorm_pts.append((d["pos"] as Vector2) + (d["normal"] as Vector2) * 1.2)
	nodes.append(["dorm", dorm_pts])
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
	var combos: Array = []
	for c in RulesLogic.all_combos(6):
		var best_len := INF
		var best_order: Array = []
		for perm in RulesLogic.permutations3(c):
			var L: float = dist[0][perm[0] + 1] + dist[perm[0] + 1][perm[1] + 1] + dist[perm[1] + 1][perm[2] + 1] + dist[perm[2] + 1][0]
			if L < best_len:
				best_len = L
				best_order = perm
		combos.append({"targets": c, "best_order": best_order, "length_m": snappedf(best_len, 0.1)})
	var lens: Array = combos.map(func(x): return x["length_m"])
	lens.sort()
	var median: float = (lens[9] + lens[10]) * 0.5
	var curated: Array = []
	for cb in combos:
		var L2: float = cb["length_m"]
		cb["vs_median"] = snappedf(L2 / median, 0.01)
		if absf(L2 / median - 1.0) <= BAND:
			curated.append(cb["targets"])
	var names: Array = []
	for nd in nodes:
		names.append(nd[0])
	var out := {
		"generated_by": "tools/route_analysis.gd", "band": BAND, "median_m": snappedf(median, 0.1),
		"nodes": names, "pair_m": dist.map(func(r): return r.map(func(v): return snappedf(v, 0.1))),
		"combos": combos, "curated": curated, "unreachable": unreachable,
		"runner_estimate_s": {"min": snappedf(float(lens[0]) / 5.6 + 6.0, 1), "median": snappedf(median / 5.6 + 6.0, 1), "max": snappedf(float(lens[19]) / 5.6 + 6.0, 1)},
	}
	var f := FileAccess.open("res://config/route_table.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	print("median %.1f m, curated %d/20, unreachable %s" % [median, curated.size(), str(unreachable)])
	for cb in combos:
		print("%-28s best %-28s %6.1f m  (%.2f)%s" % [str(cb["targets"].map(func(i): return lay.waters[i]["short"])), str(cb["best_order"].map(func(i): return lay.waters[i]["short"])), cb["length_m"], cb["vs_median"], "" if curated.has(cb["targets"]) else "   EXCLUDED"])
	quit()
