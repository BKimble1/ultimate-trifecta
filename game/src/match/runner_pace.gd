class_name RunnerPace
extends RefCounted
## Pass 8: the live "Runner pace: 3rd/6" (host only; MatchSim updates it at
## 2 Hz and snapshots carry the compact result to runners).
##
## Pace is route progress, not the team's result and not a finish position:
## it awards nothing and decides nothing.  The authoritative order:
##   1. runners already home, in true finish order (the tick they crossed a
##      door: two crossings on the same tick share a place);
##   2. everyone else by unique required waters stamped (more first);
##   3. within the same stamp count, by the estimated remaining route: from
##      where they are, through every remaining water in the best of the
##      (at most 3! = 6) visit orders, then to an eligible door of tonight's
##      dorm, on the runners' navigation grid (PaceFields: real doors,
##      obstacles and water entry points; never a straight line through a
##      building or across water);
##   4. remaining routes within TOL_M of the first runner of a group share
##      that place.  Slot order may lay rows out but never breaks a tie.
## Special states: a splashing runner is measured from the shore exit they
## will come out at; a caught runner from the best pad they can return to,
## plus the hold left at jog speed (being caught costs pace, stamps stay).
## When a route can't be measured (fields still being built, a runner off
## the grid) that runner's whole stamp group shares one place, flagged
## approximate ("stamp-based"), rather than an invented exact place.
## Published places change at once when a stamp or a finish changes the
## groups; a change from route distance alone is published once the new
## order has held for two updates (1 s), so two runners side by side don't
## flicker.  Cost: all runners, all orders, a few array reads each, twice a
## second (stats); no path search and nothing per frame.

const TOL_M := 4.0
const UPDATE_TICKS := 30          # 2 Hz at the 60 Hz simulation
const NO_GOAL := 255
const DOOR_GOAL := 16             # next_goal 16 + d: door d of tonight's dorm

## slot -> {place, tied, approx, home, stamps}; published (debounced)
var places: Dictionary = {}
## slot -> suggested next goal: 0..2 target index, 16 + door index, 255 none
var next_goal: Dictionary = {}
var runners := 0
var revision := 0
var ready := false
var stats := {"updates": 0, "us_total": 0, "us_max": 0, "ready_tick": -1, "approx_updates": 0}

var _targets: Array = []          # target index -> water index
var _dorm := ""
var _layout: CampusLayout
var _w: Dictionary = {}           # water index -> field
var _h: Dictionary = {}
var _c: Dictionary = {}           # a * 16 + b: water -> water cost (best exit of a to b)
var _x: Dictionary = {}           # water -> home cost (best exit)
var _cand: Dictionary = {}        # last computed (not yet published) ranking
var _cand_n := 0                  # how many updates in a row it has held
var _speed := 5.0


func setup(sim: MatchSim) -> void:
	_targets = sim.targets.duplicate()
	_dorm = sim.home_dorm
	_layout = sim.layout
	_speed = sim.cfg.runner_speed
	PaceFields.request(_layout, _targets, _dorm)


## Twice a second on the host (MatchSim.step).
func update(sim: MatchSim) -> void:
	var t0 := Time.get_ticks_usec()
	if not ready:
		_try_ready(sim)
	var entries: Array = []
	var goals := {}
	for p in sim.players:
		if not p.is_runner():
			continue
		var e := {"slot": p.id, "home": p.finished_tick >= 0, "tick": p.finished_tick, "stamps": p.stamp_count(), "cost": -1.0}
		if not bool(e["home"]) and ready:
			var r := route_of(p)
			e["cost"] = float(r[0])
			goals[p.id] = int(r[1])
		entries.append(e)
	runners = entries.size()
	next_goal = goals
	var ranked := rank(entries, TOL_M)
	_publish(ranked)
	var us := Time.get_ticks_usec() - t0
	stats["updates"] = int(stats["updates"]) + 1
	stats["us_total"] = int(stats["us_total"]) + us
	stats["us_max"] = maxi(int(stats["us_max"]), us)


## Debounce: structural changes (home, stamps, approximate) at once; an
## order from route distance alone once it held for two updates.
func _publish(ranked: Dictionary) -> void:
	if ranked == places:
		_cand = {}
		_cand_n = 0
		return
	var structural := ranked.size() != places.size()
	if not structural:
		for slot in ranked:
			var a: Dictionary = ranked[slot]
			var b: Dictionary = places.get(slot, {})
			if b.is_empty() or a["home"] != b["home"] or a["stamps"] != b["stamps"] or a["approx"] != b["approx"]:
				structural = true
				break
	if not structural:
		if ranked == _cand:
			_cand_n += 1
		else:
			_cand = ranked
			_cand_n = 1
		if _cand_n < 2:
			return
	places = ranked
	_cand = {}
	_cand_n = 0
	revision += 1


func _try_ready(sim: MatchSim) -> void:
	PaceFields.poll()
	for wi in _targets:
		if not PaceFields.has(PaceFields.water_key(int(wi))):
			return
	if not PaceFields.has(PaceFields.home_key(_dorm)):
		return
	for wi in _targets:
		_w[int(wi)] = PaceFields.field(PaceFields.water_key(int(wi)))
	_h = PaceFields.field(PaceFields.home_key(_dorm))
	# leg costs between tonight's waters and from each to home: from the
	# best of the water's shore exits (a runner resurfaces at the exit
	# nearest where they were heading, so they can pick it)
	for a in _targets:
		var exits: Array = _layout.waters[int(a)]["exits"]
		var cells: Array[int] = []
		for e in exits:
			cells.append(PaceFields.cell_of(Vector2((e as Vector3).x, (e as Vector3).z)))
		for b in _targets:
			if int(a) == int(b):
				continue
			var best := INF
			for c in cells:
				best = minf(best, PaceFields.metres(_w[int(b)], c))
			_c[int(a) * 16 + int(b)] = best
		var bh := INF
		for c in cells:
			bh = minf(bh, PaceFields.metres(_h, c))
		_x[int(a)] = bh
	ready = true
	stats["ready_tick"] = sim.tick


## [remaining route in metres (INF when unknown), next goal] for a runner
## not yet home.
func route_of(p: SimPlayer) -> Array:
	var remaining: Array = []
	for i in _targets.size():
		if (p.stamps & (1 << i)) == 0:
			remaining.append(i)
	var starts: Array = []
	var extra := 0.0
	match p.state:
		TC.PState.SPLASHING:
			starts = [Vector2(p.splash_exit.x, p.splash_exit.z)]
		TC.PState.CAPTURED:
			var pads: Array = _layout.waters[p.last_stamp_water]["pads"] if p.last_stamp_water >= 0 else CampusDorms.geometry(_dorm)["respawn"]
			starts = pads.duplicate()
			extra = maxf(0.0, p.penalty) * _speed
		_:
			starts = [p.pos2()]
	var best := INF
	var goal := NO_GOAL
	for s in starts:
		var r := remaining_from(PaceFields.cell_of(s), remaining)
		if float(r[0]) < best:
			best = float(r[0])
			goal = int(r[1])
	return [best + extra if best < INF else INF, goal]


## The best order through `remaining` (target indices) from a grid cell.
func remaining_from(cell: int, remaining: Array) -> Array:
	if cell < 0:
		return [INF, NO_GOAL]
	if remaining.is_empty():
		var hd := PaceFields.metres(_h, cell)
		var door := PaceFields.label_at(_h, cell)
		return [hd, DOOR_GOAL + door if door >= 0 else NO_GOAL]
	var best := INF
	var first := NO_GOAL
	for order in permutations(remaining):
		var w0 := int(_targets[int(order[0])])
		var cost := PaceFields.metres(_w[w0], cell)
		for k in range(1, order.size()):
			cost += float(_c[int(_targets[int(order[k - 1])]) * 16 + int(_targets[int(order[k])])])
		cost += float(_x[int(_targets[int(order[-1])])])
		if cost < best:
			best = cost
			first = int(order[0])
	return [best, first]


## Every order of a short list (at most 3 items: 6 orders).
static func permutations(items: Array) -> Array:
	if items.size() <= 1:
		return [items.duplicate()]
	var out: Array = []
	for i in items.size():
		var rest := items.duplicate()
		rest.remove_at(i)
		for tail in permutations(rest):
			out.append([items[i]] + tail)
	return out


## The pace order (see the class notes).  entries: [{slot, home, tick,
## stamps, cost (metres; < 0 or INF when unknown)}].  Returns slot ->
## {place, tied, approx, home, stamps}; places are shared (1, 2, 2, 4).
static func rank(entries: Array, tol_m: float = TOL_M) -> Dictionary:
	var out := {}
	var home: Array = entries.filter(func(e: Dictionary) -> bool: return bool(e["home"]))
	var out_of: Array = entries.filter(func(e: Dictionary) -> bool: return not bool(e["home"]))
	home.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["tick"]) < int(b["tick"]) if int(a["tick"]) != int(b["tick"]) else int(a["slot"]) < int(b["slot"]))
	var groups: Array = []      # [[entries sharing a place], approx]
	var i := 0
	while i < home.size():
		var g: Array = [home[i]]
		while i + 1 < home.size() and int(home[i + 1]["tick"]) == int(home[i]["tick"]):
			i += 1
			g.append(home[i])
		groups.append([g, false])
		i += 1
	# the rest: by stamps (more first), then route within each stamp count
	var by_stamps := {}
	for e in out_of:
		var k := int(e["stamps"])
		if not by_stamps.has(k):
			by_stamps[k] = []
		(by_stamps[k] as Array).append(e)
	var counts := by_stamps.keys()
	counts.sort()
	counts.reverse()
	for k in counts:
		var g2: Array = by_stamps[k]
		var known := true
		for e in g2:
			var c := float(e["cost"])
			if c < 0.0 or c == INF or is_nan(c):
				known = false
		if not known:
			g2.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["slot"]) < int(b["slot"]))
			groups.append([g2, true])
			continue
		g2.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["cost"]) < float(b["cost"]) if float(a["cost"]) != float(b["cost"]) else int(a["slot"]) < int(b["slot"]))
		var j := 0
		while j < g2.size():
			var anchor := float(g2[j]["cost"])
			var tg: Array = [g2[j]]
			while j + 1 < g2.size() and float(g2[j + 1]["cost"]) - anchor <= tol_m:
				j += 1
				tg.append(g2[j])
			groups.append([tg, false])
			j += 1
	var place := 1
	for gr in groups:
		var members: Array = gr[0]
		for e in members:
			out[int(e["slot"])] = {"place": place, "tied": members.size() > 1, "approx": bool(gr[1]),
				"home": bool(e["home"]), "stamps": int(e["stamps"])}
		place += members.size()
	return out


## Average and worst update cost in microseconds.
func cost_us() -> Dictionary:
	var n := maxi(1, int(stats["updates"]))
	return {"mean": float(stats["us_total"]) / float(n), "max": int(stats["us_max"]), "updates": int(stats["updates"])}


## "1st", "2nd", ... for pace and series labels.
static func ordinal(n: int) -> String:
	return RoundRanking.ordinal(n)


## What a runner's HUD says about their pace, from a published entry and
## the runner count.  round_over: the round has ended (unfinished runners
## are "Not home", never a manufactured finish place).
static func label(e: Dictionary, n: int, round_over: bool = false) -> String:
	if e.is_empty() or n <= 0:
		return "Runner pace: updating"
	if bool(e.get("home", false)):
		return "Runner pace: %s%s/%d" % ["tied " if bool(e.get("tied", false)) else "", ordinal(int(e["place"])), n]
	if round_over:
		return "Runner pace: Not home"
	return "Runner pace: %s%s/%d" % ["tied " if bool(e.get("tied", false)) else "", ordinal(int(e["place"])), n]
