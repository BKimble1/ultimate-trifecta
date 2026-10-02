extends Node
## Development-only (src/dev is excluded from exports): where a 60 Hz
## simulation tick spends its time in a full 8-player bot round (6 runners,
## 2 Night Watch, all BotBrain), headless.  Prints per-section totals and the
## worst ticks, and the tick-cost distribution, to find what can push a
## phone into a physics catch-up spiral.
##   tools/gd.sh --headless --path game res://src/dev/sim_profile.tscn -- [--ticks=N] [--seed=S]

var _sim: MatchSim
var _ticks := 0
var _max_ticks := 60 * 200
var _costs := PackedFloat32Array()
var _worst: Array = []


func _ready() -> void:
	var seed_v := 11
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ticks="):
			_max_ticks = int(a.get_slice("=", 1))
		elif a.begins_with("--seed="):
			seed_v = int(a.get_slice("=", 1))
	_sim = MatchSim.new()
	add_child(_sim)
	var roster: Array = []
	var roles := [TC.Role.RUNNER, TC.Role.RUNNER, TC.Role.RUNNER, TC.Role.RUNNER, TC.Role.RUNNER, TC.Role.RUNNER, TC.Role.PATROL, TC.Role.PATROL]
	for i in roles.size():
		roster.append({"slot": i, "uid": "b%d" % i, "name": "Bot %d" % i, "is_bot": true, "role": roles[i], "cosmetic": {}})
	_sim.setup(Rules.cfg, CampusLayout.shared(), roster, seed_v, [0, 1, 2], "profile-%d" % seed_v,
		{"practice": true, "bot_factory": func(s: MatchSim, p: SimPlayer) -> BotBrain: return BotBrain.new(s, p)})
	MatchSim.prof_on = true
	MatchSim.prof = {}
	NavGrid.shared(CampusLayout.shared()).debug_slow_searches = []


func _physics_process(_d: float) -> void:
	if _sim == null:
		return
	var before := MatchSim.prof.duplicate()
	var t0 := Time.get_ticks_usec()
	_sim.step({})
	var us := Time.get_ticks_usec() - t0
	_ticks += 1
	if _sim.phase == TC.Phase.PLAYING:
		_costs.append(us / 1000.0)
		var parts := {}
		for k in MatchSim.prof:
			parts[k] = int(MatchSim.prof[k]) - int(before.get(k, 0))
		_worst.append({"tick": _sim.tick, "ms": us / 1000.0, "parts": parts})
		_worst.sort_custom(func(a, b): return a["ms"] > b["ms"])
		if _worst.size() > 8:
			_worst.resize(8)
	if _ticks >= _max_ticks or _sim.phase == TC.Phase.RESULTS or _sim.phase == TC.Phase.ENDED:
		_report()
		get_tree().quit()


func _report() -> void:
	var sorted := _costs.duplicate()
	sorted.sort()
	var n := sorted.size()
	if n == 0:
		print("SIMPROF no playing ticks")
		return
	var total := 0.0
	var over8 := 0
	var over16 := 0
	for c in sorted:
		total += c
		if c > 8.0:
			over8 += 1
		if c > 16.0:
			over16 += 1
	print("SIMPROF playing ticks=%d mean=%.2f ms p50=%.2f p95=%.2f p99=%.2f max=%.2f over8ms=%d over16ms=%d" % [
		n, total / n, sorted[int(n * 0.5)], sorted[int(n * 0.95)], sorted[mini(n - 1, int(n * 0.99))], sorted[n - 1],
		over8, over16])
	var keys := MatchSim.prof.keys()
	keys.sort_custom(func(a, b): return MatchSim.prof[a] > MatchSim.prof[b])
	for k in keys:
		print("SIMPROF section %-10s total=%8.1f ms  per tick=%.3f ms" % [k, MatchSim.prof[k] / 1000.0, MatchSim.prof[k] / 1000.0 / maxf(1.0, _ticks)])
	var nav := NavGrid.shared(CampusLayout.shared())
	if "path_stats" in nav:
		print("SIMPROF paths %s (budget %d per tick)" % [str(nav.path_stats), nav.budget_per_tick])
		for e in nav.debug_slow_searches:
			print("SIMPROF slow search from %s to %s cart=%s %.1f ms cells=%d" % e)
	for w in _worst:
		print("SIMPROF worst tick %d: %.2f ms %s" % [w["tick"], w["ms"], str(w["parts"])])
