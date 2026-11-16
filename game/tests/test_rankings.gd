extends RefCounted
## 2.2 Rankings: Season Points, what counts, run times and personal bests,
## 30-day seasons, and the contest rules Apple requires.
var t


func _results(outcome: int, rows: Array, practice := false) -> Dictionary:
	return {"match_id": "m1", "outcome": outcome, "players": rows, "practice": practice}


func _row(slot: int, role: int, human := true, extra := {}) -> Dictionary:
	var r := {"slot": slot, "role": role, "is_bot": not human, "was_human": human, "stamps": 0, "finished": false,
		"finish_time": -1.0, "finish_order": 0, "unique_captures": 0}
	r.merge(extra, true)
	return r


func _reset() -> void:
	Save.data["rankings"] = {"bests": {}, "periods": {}, "days": {}}
	Rankings.clock_override = func() -> int: return int(Time.get_unix_time_from_datetime_string("2026-12-05T12:00:00"))


func test_points_per_round() -> void:
	var res := _results(TC.Outcome.RUNNERS_WIN, [])
	var p := Rankings.round_points(_row(0, TC.Role.RUNNER, true, {"stamps": 3, "finished": true, "finish_order": 1}), res)
	t.eq(int(p["total"]), 10 + 15 + 15 + 10 + 5, "runner: played, win, 3 splashes, home, first home")
	p = Rankings.round_points(_row(1, TC.Role.PATROL, true, {"unique_captures": 5}), res)
	t.eq(int(p["total"]), 10 + 30, "Night Watch on the losing side: played, 3 different runners at most")
	p = Rankings.round_points(_row(1, TC.Role.PATROL, true, {"unique_captures": 3}), _results(TC.Outcome.PATROL_WIN, []))
	t.check(int(p["total"]) <= Rankings.ROUND_CAP, "never above the round cap")


func test_what_counts() -> void:
	_reset()
	var me := _row(0, TC.Role.RUNNER, true, {"stamps": 3, "finished": true, "finish_time": 118.25, "finish_order": 2})
	var r := Rankings.record(_results(TC.Outcome.RUNNERS_WIN, [me, _row(1, TC.Role.RUNNER, false)]), 0, false, false)
	t.check(not bool(r["counted"]) and String(r["why"]).contains("at least one other player"), "you and bots: doesn't count")
	t.eq(float(r["run_time"]), 118.25, "but the run time is shown")
	t.check(bool(r["new_best"]), "and it is your first personal best (any non-practice round)")
	r = Rankings.record(_results(TC.Outcome.RUNNERS_WIN, [me, _row(1, TC.Role.RUNNER)], true), 0, true, false)
	t.check(not bool(r["counted"]), "practice doesn't count")
	t.check(Rankings.bests()["practice"] == 118.25, "a practice best is kept separately")
	r = Rankings.record(_results(TC.Outcome.RUNNERS_WIN, [me, _row(1, TC.Role.PATROL)]), 0, false, false)
	t.check(bool(r["counted"]) and int(r["points"]) == 10 + 15 + 15 + 10, "an online round with another player counts")
	t.check(not bool(r["new_best"]), "the same time again is not a new best")
	t.eq(int(Rankings.period_stats()["points"]), int(r["points"]), "season points add up")
	var fast := me.duplicate()
	fast["finish_time"] = 20.0
	r = Rankings.record(_results(TC.Outcome.RUNNERS_WIN, [fast, _row(1, TC.Role.PATROL)]), 0, false, false)
	t.eq(float(r["run_time"]), -1.0, "an implausible run (under %d s) is not a run" % int(Rankings.MIN_RUN_S))
	t.eq(Rankings.bests()["online"], 118.25, "and doesn't replace the best")
	for i in Rankings.DAILY_ROUNDS:
		Rankings.record(_results(TC.Outcome.RUNNERS_WIN, [me, _row(1, TC.Role.PATROL)]), 0, false, false)
	r = Rankings.record(_results(TC.Outcome.RUNNERS_WIN, [me, _row(1, TC.Role.PATROL)]), 0, false, false)
	t.check(not bool(r["counted"]) and String(r["why"]).contains("today"), "a daily cap on counted rounds")
	Rankings.clock_override = Callable()


func test_seasons_are_30_days() -> void:
	var p0 := Rankings.period0()
	t.eq(Rankings.period_index(p0 + 10), 0, "the preseason")
	t.eq(Rankings.period_index(p0 + 30 * 86400), 1, "Season 1 starts 30 days later")
	t.eq(Rankings.season_name(1), "Season 1 · Winter Break", "Season 1's name")
	var b := Rankings.period_bounds(1)
	t.eq(b[1] - b[0], 30 * 86400, "a season is 30 days (Game Center's longest recurrence)")
	t.eq(Time.get_date_string_from_unix_time(b[0]), "2026-12-01", "Season 1 starts on 1 December")
	t.eq(Rankings.fmt_time(112.4), "1:52.40", "run times read m:ss.cc")


func test_contest_rules_meet_guideline_5_3() -> void:
	var r := ChampionPromo.rules_text()
	t.check(r.contains("Apple is not a sponsor") and r.contains("not involved"), "Apple is not a sponsor or involved")
	t.check(r.contains("No purchase necessary"), "free to enter")
	t.check(r.contains("Idlery Games"), "the developer is the sponsor")
	t.check(r.contains("30 days"), "the season window is stated")
	t.check(not r.contains("\\n"), "no stray escape sequences")
