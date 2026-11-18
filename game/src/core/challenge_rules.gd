class_name ChallengeRules
extends RefCounted
## Pass 8 challenges: three daily and three weekly goals that add Season XP
## to the existing pass (docs/ECONOMY.md §10).  (2.2 build 22) The daily
## three come from a pool of 21 on a fixed Monday-to-Sunday schedule
## ("daily_pool", "daily_schedule": UTC days, Monday first) that repeats
## every week; the weekly three stay the same.  The numbers live in
## config/catalogue.json "economy.challenges"; service/src/challenges.js
## implements the same rules and is the authority (it settles progress and
## the completion bonus with the round, once).  Pure functions, no scene
## tree.  Times here are unix seconds (the service uses milliseconds).
##
## A round counts for challenges only when it is an eligible, verified,
## completed online round the player actively played: its row's active_s
## (seconds of real input or objective play counted by the host's
## simulation, ActivityMeter) reaches min(active.min_s, active.min_share x
## round time).  It then adds one active round, its contribution credits
## (each unique required-water stamp or each different runner tagged, at
## most 3) and a Round Win when the player's team won: runners and the
## Night Watch progress alike.  Practice, tutorial, service-off, unverified,
## cancelled and host-loss rounds add nothing.

const DAY_S := 86400
## the host report version that carries active_s (Economy.row_canonical v2)
const REPORT_VERSION := 2
const ROLE_LINE := "New daily goals each day. Online rounds count."


static func cfg() -> Dictionary:
	var c: Variant = Catalogue.economy().get("challenges", {})
	return c if c is Dictionary else {}


## (build 22) Every daily challenge there is (the pool).
static func daily_pool() -> Array:
	var p: Variant = cfg().get("daily_pool", cfg().get("daily", []))
	return p if p is Array else []


## Which day of the schedule a time falls on: 0 Monday .. 6 Sunday (UTC).
static func weekday_index(t: int) -> int:
	return posmod(int(floor(float(t) / DAY_S)) + 3, 7)


## The daily challenges of the UTC day containing `t`, in schedule order.
static func daily_defs(t: int) -> Array:
	var sched: Variant = cfg().get("daily_schedule", [])
	var ids: Array = []
	if sched is Array and (sched as Array).size() == 7:
		ids = sched[weekday_index(t)]
	var out: Array = []
	for cid in ids:
		for d in daily_pool():
			if String(d["id"]) == String(cid):
				out.append(d)
	if out.is_empty():
		out = daily_pool().slice(0, 3)   # (an older catalogue: its fixed three)
	return out


## The goals in display order (daily, then weekly), each with its "period":
## today's daily three (the service's clock, `t`; now by default) and the
## weekly three.
static func defs(t: int = -1) -> Array:
	if t < 0:
		t = int(Time.get_unix_time_from_system())
	var out: Array = []
	for d in daily_defs(t):
		var e: Dictionary = (d as Dictionary).duplicate()
		e["period"] = "daily"
		out.append(e)
	for d in cfg().get("weekly", []):
		var e2: Dictionary = (d as Dictionary).duplicate()
		e2["period"] = "weekly"
		out.append(e2)
	return out


## Any challenge by id: the whole daily pool and the weekly ones.
static func def(id: String) -> Dictionary:
	for d in daily_pool():
		if String(d["id"]) == id:
			var e: Dictionary = (d as Dictionary).duplicate()
			e["period"] = "daily"
			return e
	for d in cfg().get("weekly", []):
		if String(d["id"]) == id:
			var e2: Dictionary = (d as Dictionary).duplicate()
			e2["period"] = "weekly"
			return e2
	return {}


static func grace_s() -> int:
	return int(cfg().get("grace_s", DAY_S))


## The most Season XP a period's challenges can give: the weekly three, or
## (daily) the richest day of the schedule.
static func max_xp(kind: String) -> int:
	if kind == "daily":
		var best := 0
		for i in 7:
			var n0 := 0
			for d in daily_defs(i * DAY_S + (4 * DAY_S)):   # 1970-01-05 was a Monday
				n0 += int(d.get("xp", 0))
			best = maxi(best, n0)
		return best
	var n := 0
	for d in cfg().get(kind, []):
		n += int(d.get("xp", 0))
	return n


## The Season XP the daily challenges of the schedule's day `i` (0 Monday)
## give in all.
static func day_xp(i: int) -> int:
	var n := 0
	for d in daily_defs((4 + i) * DAY_S):
		n += int(d.get("xp", 0))
	return n


# ------------------------------------------------------------------ periods
static func day_start(t: int) -> int:
	return int(floor(float(t) / DAY_S)) * DAY_S


## Monday 00:00 UTC (1970-01-01 was a Thursday).
static func week_start(t: int) -> int:
	var d := int(floor(float(t) / DAY_S))
	return (d - posmod(d + 3, 7)) * DAY_S


## {start, end, key}: the UTC period containing t ("daily" or "weekly").
static func period_of(kind: String, t: int) -> Dictionary:
	var start := day_start(t) if kind == "daily" else week_start(t)
	var end := start + DAY_S * (1 if kind == "daily" else 7)
	return {"start": start, "end": end, "key": Time.get_date_string_from_unix_time(start)}


static func instance_id(kind: String, key: String, cid: String) -> String:
	return "%s:%s:%s" % ["d" if kind == "daily" else "w", key, cid]


# ------------------------------------------------------------------ rounds
## Seconds of active play a round needs (60 s, or 40% of a shorter round).
static func active_need(round_time: float) -> float:
	var a: Dictionary = cfg().get("active", {})
	return minf(float(a.get("min_s", 60)), float(a.get("min_share", 0.4)) * maxf(0.0, round_time))


static func active_enough(row: Dictionary, round_time: float) -> bool:
	return float(row.get("active_s", 0)) >= active_need(round_time)


static func credits(row: Dictionary) -> int:
	var s := clampi(int(row.get("stamps", 0)), 0, 3)
	var u := maxi(0, int(row.get("unique_captures", 0)))
	return mini(int(cfg().get("credit_cap_per_round", 3)), s + u)


## Every metric a challenge can count (build 22: the daily pool's).
const METRICS := ["active_rounds", "credits", "round_wins", "stamps", "trifectas", "homes", "first_homes", "captures", "coins",
	"runner_rounds", "watch_rounds", "runner_wins", "watch_wins"]


## What a round row adds to challenges, as the service will settle it:
## {state: "applied" | "inactive", and one count per METRICS entry}.
static func increments(row: Dictionary, results: Dictionary) -> Dictionary:
	var out := {"state": "inactive"}
	for m in METRICS:
		out[m] = 0
	if not active_enough(row, float(results.get("round_time", 0.0))):
		return out
	var runner := int(row.get("role", 0)) == TC.Role.RUNNER
	var won := Economy.team_won(row, int(results.get("outcome", 0)))
	var stamps := clampi(int(row.get("stamps", 0)), 0, 3) if runner else 0
	var home := runner and bool(row.get("finished", false))
	out["state"] = "applied"
	out["active_rounds"] = 1
	out["credits"] = credits(row)
	out["round_wins"] = 1 if won else 0
	out["stamps"] = stamps
	out["trifectas"] = 1 if stamps >= 3 else 0
	out["homes"] = 1 if home else 0
	out["first_homes"] = 1 if home and bool(row.get("first_home", false)) else 0
	out["captures"] = 0 if runner else clampi(int(row.get("unique_captures", 0)), 0, 7)
	out["coins"] = clampi(int(row.get("coins_picked", 0)), 0, int(Economy.cfg().get("eligibility", {}).get("max_coin_spawns", 10)))
	out["runner_rounds"] = 1 if runner else 0
	out["watch_rounds"] = 0 if runner else 1
	out["runner_wins"] = 1 if runner and won else 0
	out["watch_wins"] = 1 if won and not runner else 0
	return out


# ------------------------------------------------------------------ text
## "Daily" / "Weekly".
static func period_label(kind: String) -> String:
	return "Weekly" if kind == "weekly" else "Daily"


## The device's offset from UTC in seconds (presentation only: periods are
## UTC on the service).
static func local_offset_s() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


static func _twelve_hour() -> bool:
	var loc := OS.get_locale()
	return loc.begins_with("en_US") or loc.begins_with("en_CA") or loc.begins_with("en_AU") or loc.begins_with("en_NZ") \
		or loc.begins_with("en_PH") or loc.begins_with("en_IN") or loc == "en"


## A unix time as the player's local clock time: "8:00 PM" or "20:00".
static func local_clock(t: int, offset_s: int = 0x7fffffff, twelve: int = -1) -> String:
	var off := local_offset_s() if offset_s == 0x7fffffff else offset_s
	var d := Time.get_datetime_dict_from_unix_time(t + off)
	var h := int(d["hour"])
	var m := int(d["minute"])
	if (twelve < 0 and _twelve_hour()) or twelve == 1:
		return "%d:%02d %s" % [12 if h % 12 == 0 else h % 12, m, "AM" if h < 12 else "PM"]
	return "%02d:%02d" % [h, m]


const WEEKDAYS := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]


## When a period resets, in local time: "Resets 8:00 PM" (within a day),
## "Resets Sun 8:00 PM" (later).  `now` decides "within a day".
static func reset_text(end_t: int, now: int, offset_s: int = 0x7fffffff, twelve: int = -1) -> String:
	var off := local_offset_s() if offset_s == 0x7fffffff else offset_s
	var clock := local_clock(end_t, off, twelve)
	if end_t - now <= DAY_S:
		return "Resets %s" % clock
	var d := Time.get_datetime_dict_from_unix_time(end_t + off)
	return "Resets %s %s" % [WEEKDAYS[int(d["weekday"])], clock]


## "+50 Season XP".
static func xp_text(xp: int) -> String:
	return "+%d Season XP" % xp


## One line for a card or the pinned row: "Campus Contribution 4/6".
static func progress_text(card: Dictionary) -> String:
	return "%s %d/%d" % [String(card.get("name", "")), int(card.get("progress", 0)), int(card.get("goal", 0))]
