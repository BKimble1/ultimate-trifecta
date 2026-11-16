class_name Rankings
extends RefCounted
## Rankings (2.2): two Game Center leaderboards that reset every 30 days
## (Game Center's recurring leaderboards, whose period can't be longer), and
## the player's own run stats on this device.
##
##   Season Points  points earned in online rounds with at least one other
##                  real player (bots-only rounds and practice never count),
##                  the running total of the season, best score kept
##   Fastest Run    a runner's time from GO to home (all three splashes,
##                  through a home door), lowest kept
##
## Seasons: 30-day periods counted from PERIOD0 (2026-11-01 00:00 UTC, the
## preseason).  Period 1 (from 2026-12-01) is Season 1 · Winter Break, and so
## on.  The leaderboards in App Store Connect use the same start date and a
## 30-day recurrence (tools/asc.py gc-leaderboards), so the game's season and
## Game Center's occurrence are the same window.
##
## Trust: the round is the host's simulation; scores are what this device
## saw, with sanity limits (a run can't be faster than MIN_RUN_S, a round
## gives at most ROUND_CAP points, at most DAILY_ROUNDS rounds count per
## day).  Game Center scores can still be forged by a modified client, so
## the champion is reviewed by the developer before the prize (the Official
## Rules say so) and cheated scores can be removed in App Store Connect.
## No divisions, no hidden rating, no gameplay rewards.

const PERIOD0 := "2026-11-01T00:00:00"
const PERIOD_DAYS := 30
const BOARD_POINTS := "ut.season_points"
const BOARD_FASTEST := "ut.fastest_run"
const MIN_RUN_S := 50.0
const ROUND_CAP := 70
const DAILY_ROUNDS := 40
## the season names players see, by period (period 0: the preseason)
const NAMES := {0: "Preseason", 1: "Season 1 · Winter Break"}

## tests: replace the clock (unix seconds)
static var clock_override: Callable


static func now() -> int:
	return int(clock_override.call()) if clock_override.is_valid() else int(Time.get_unix_time_from_system())


static func period0() -> int:
	return int(Time.get_unix_time_from_datetime_string(PERIOD0))


static func period_index(t: int = -1) -> int:
	var tt := now() if t < 0 else t
	return maxi(0, floori(float(tt - period0()) / float(PERIOD_DAYS * 86400)))


## [start, end) of a period, unix seconds.
static func period_bounds(idx: int) -> Array[int]:
	var s := period0() + idx * PERIOD_DAYS * 86400
	return [s, s + PERIOD_DAYS * 86400]


static func season_name(idx: int = -1) -> String:
	var i := period_index() if idx < 0 else idx
	return String(NAMES.get(i, "Season %d" % i))


## "12d 4h" / "5h 20m" / "9m" until the period ends.
static func time_left_text(t: int = -1) -> String:
	var tt := now() if t < 0 else t
	var left := maxi(0, period_bounds(period_index(tt))[1] - tt)
	var d := left / 86400
	var h := (left % 86400) / 3600
	var m := (left % 3600) / 60
	if d > 0:
		return "%dd %dh" % [d, h]
	if h > 0:
		return "%dh %dm" % [h, m]
	return "%dm" % maxi(1, m)


## Season Points for one results row: [[label, points], ...] and the total
## (capped at ROUND_CAP).
static func round_points(row: Dictionary, results: Dictionary) -> Dictionary:
	var parts: Array = [["Round played", 10]]
	var role := int(row.get("role", TC.Role.RUNNER))
	var won := (role == TC.Role.RUNNER and int(results.get("outcome", 0)) == TC.Outcome.RUNNERS_WIN) \
		or (role == TC.Role.PATROL and int(results.get("outcome", 0)) == TC.Outcome.PATROL_WIN)
	if won:
		parts.append(["Team win", 15])
	if role == TC.Role.RUNNER:
		var st := mini(3, int(row.get("stamps", 0)))
		if st > 0:
			parts.append(["Splashes ×%d" % st, 5 * st])
		if bool(row.get("finished", false)):
			parts.append(["Made it home", 10])
			if int(row.get("finish_order", 0)) == 1:
				parts.append(["First home", 5])
	elif role == TC.Role.PATROL:
		var u := mini(3, int(row.get("unique_captures", 0)))
		if u > 0:
			parts.append(["Runners tagged ×%d" % u, 10 * u])
	var total := 0
	for p in parts:
		total += int(p[1])
	return {"parts": parts, "total": mini(total, ROUND_CAP)}


static func humans_in(results: Dictionary) -> int:
	var n := 0
	for r in results.get("players", []):
		if bool(r.get("was_human", false)) and not bool(r.get("is_bot", false)):
			n += 1
	return n


static func _row(results: Dictionary, slot: int) -> Dictionary:
	for r in results.get("players", []):
		if int(r.get("slot", -2)) == slot:
			return r
	return {}


static func _store() -> Dictionary:
	var d: Variant = Save.data.get("rankings")
	if not (d is Dictionary):
		d = {"bests": {}, "periods": {}, "days": {}}
		Save.data["rankings"] = d
	for k in ["bests", "periods", "days"]:
		if not (d as Dictionary).has(k):
			d[k] = {}
	return d


## This season's numbers on this device: {points, rounds, best_run}.
static func period_stats(idx: int = -1) -> Dictionary:
	var p: Dictionary = (_store()["periods"] as Dictionary).get(str(period_index() if idx < 0 else idx), {})
	return {"points": int(p.get("points", 0)), "rounds": int(p.get("rounds", 0)), "best_run": float(p.get("best_run", -1.0))}


## Personal bests on this device: {online, practice} (seconds, -1 = none).
static func bests() -> Dictionary:
	var b: Dictionary = _store()["bests"]
	return {"online": float(b.get("online", -1.0)), "practice": float(b.get("practice", -1.0))}


## After a round: the player's run and points, stored, and (when it counts)
## sent to Game Center.  Returns what the results screen shows:
## {run_time, best, new_best, points, parts, season_points, counted, why}.
static func record(results: Dictionary, slot: int, practice: bool, submit: bool = true) -> Dictionary:
	var row := _row(results, slot)
	var out := {"run_time": -1.0, "best": -1.0, "new_best": false, "points": 0, "parts": [], "season_points": 0,
		"counted": false, "why": ""}
	if row.is_empty() or bool(row.get("is_bot", false)):
		return out
	var st := _store()
	var key := "practice" if practice else "online"
	var run := float(row.get("finish_time", -1.0)) if bool(row.get("finished", false)) else -1.0
	if run > 0.0 and run < MIN_RUN_S:
		run = -1.0   # not a real run (a bad clock or a modified game)
	out["run_time"] = run
	var bests_d: Dictionary = st["bests"]
	var old := float(bests_d.get(key, -1.0))
	if run > 0.0 and (old < 0.0 or run < old):
		bests_d[key] = run
		out["new_best"] = true
	out["best"] = float(bests_d.get(key, -1.0))
	var idx := str(period_index())
	var per: Dictionary = (st["periods"] as Dictionary).get(idx, {"points": 0, "rounds": 0, "best_run": -1.0})
	out["season_points"] = int(per.get("points", 0))
	# what counts toward the leaderboards
	var why := ""
	if practice or bool(results.get("practice", false)):
		why = "Practice rounds don't count toward Rankings."
	elif humans_in(results) < 2:
		why = "Rankings count online rounds with at least one other player."
	elif bool(results.get("cancelled", false)):
		why = "A cancelled round doesn't count."
	var day := Time.get_date_string_from_unix_time(now())
	var days: Dictionary = st["days"]
	if why == "" and int(days.get(day, 0)) >= DAILY_ROUNDS:
		why = "You've reached today's %d counted rounds." % DAILY_ROUNDS
	out["why"] = why
	if why == "":
		var rp := round_points(row, results)
		out["points"] = int(rp["total"])
		out["parts"] = rp["parts"]
		out["counted"] = true
		per["points"] = int(per.get("points", 0)) + int(rp["total"])
		per["rounds"] = int(per.get("rounds", 0)) + 1
		if run > 0.0 and (float(per.get("best_run", -1.0)) < 0.0 or run < float(per["best_run"])):
			per["best_run"] = run
		(st["periods"] as Dictionary)[idx] = per
		var counted_today := int(days.get(day, 0)) + 1
		days.clear()          # only today's count is kept
		days[day] = counted_today
		out["season_points"] = int(per["points"])
		if submit:
			Social.submit_score(BOARD_POINTS, int(per["points"]))
			if run > 0.0:
				Social.submit_score(BOARD_FASTEST, int(round(run * 100.0)))   # centiseconds
	Save.mark()
	return out


## "1:52.40" for 112.4 s.
static func fmt_time(s: float) -> String:
	if s < 0.0:
		return "—"
	var cs := int(round(s * 100.0))
	return "%d:%02d.%02d" % [cs / 6000, (cs / 100) % 60, cs % 100]
