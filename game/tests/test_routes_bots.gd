extends RefCounted
## Route reachability with real movement: for every curated target combination,
## runner bots (same inputs/limits as players) must reach all three waters and
## get home with no pursuit, in a time compatible with the 4-minute round.
## Slow (~1-2 min); prints ROUTE lines used by TEST_REPORT.
var t
const R := TC.Role.RUNNER
const P := TC.Role.PATROL


func test_bots_complete_every_curated_route() -> void:
	var combos := RulesLogic.curated_combos()
	var all_times: Array = []
	var per_combo := {}
	for ci in combos.size():
		var targets: Array = combos[ci]
		var h := SimHarness.new(t)
		# six runner bots; patrol slots are human-scripted and stay idle in the shed
		h.make([R, R, R, R, R, R, P, P], targets, [0, 1, 2, 3, 4, 5], 100 + ci)
		h.sim.cfg.runners_needed = 7   # don't end early: let all six finish
		await h.to_playing()
		var start := h.sim.tick
		var limit := Rules.cfg.ticks(Rules.cfg.match_duration_s)
		while h.sim.tick - start < limit:
			await h.step()
			var done := 0
			for p in h.sim.players:
				if p.is_runner() and p.state == TC.PState.FINISHED:
					done += 1
			if done == 6:
				break
		var times: Array = []
		for p in h.sim.players:
			if p.is_runner():
				times.append(float(p.finished_tick - start) / 60.0 if p.finished_tick >= 0 else -1.0)
		h.sim.cfg.runners_needed = 4
		var finished := times.filter(func(x): return x > 0.0)
		var names := targets.map(func(i): return h.sim.layout.waters[i]["short"])
		print("ROUTE %s finished %d/6 times %s" % [str(names), finished.size(), str(times.map(func(x): return snappedf(x, 0.1)))])
		t.check(finished.size() >= 5, "combo %s: runner bots complete the route without pursuit (%d/6)" % [str(names), finished.size()])
		all_times.append_array(finished)
		if not finished.is_empty():
			var fs: Array = finished.duplicate()
			fs.sort()
			per_combo[str(targets)] = fs[fs.size() / 2]
		h.free_sim()
	all_times.sort()
	if not all_times.is_empty():
		var med: float = all_times[all_times.size() / 2]
		print("ROUTE_SUMMARY n=%d min=%.1f median=%.1f max=%.1f" % [all_times.size(), all_times[0], med, all_times[-1]])
		t.check(med > 90.0 and med < 200.0, "typical no-pursuit trip is in a sensible range (median %.0f s)" % med)
	# feed measured times back into route curation (tools/route_analysis.gd);
	# merge so combinations outside the curated set keep their earlier measurement
	var path := "res://config/route_bot_times.json"
	var merged: Dictionary = {}
	if FileAccess.file_exists(path):
		var old: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if old is Dictionary:
			merged = old
	merged.merge(per_combo, true)
	var keys := merged.keys()
	keys.sort()
	var ordered := {}
	for k in keys:
		ordered[k] = merged[k]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(ordered, "  "))
