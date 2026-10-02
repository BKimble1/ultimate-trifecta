class_name PartySeries
extends RefCounted
## Party settings and multi-round series for private friend parties (V4).
##
## Settings: the host picks the Night Watch count (1, 2 or 3) and the number
## of rounds (1, 3 or 5).  Eight gameplay slots stay fixed; bots fill empty
## ones.  Everything else is derived here, in one place:
##   runners       = 8 - watch
##   required home = ceil(2 x runners / 3)      1 -> 7 runners, 5 home
##                                              2 -> 6 runners, 4 home
##                                              3 -> 5 runners, 4 home
## The host locks a validated copy of the settings when a series starts, and
## every round gets its own immutable RulesConfig (rules_for) - the global
## default resource is never modified.
##
## A series is the chosen number of completed rounds in the same party.  The
## host owns it: roles are assigned per round with fair random rotation,
## each completed round is recorded once (by match id), cancelled rounds
## don't count, and the friends leaderboard orders humans by Round Wins (ties
## share a place).  Bots never appear in the friends standings.

const SLOTS := 8
const WATCH_CHOICES := [1, 2, 3]
const ROUND_CHOICES := [1, 3, 5]
const DEFAULT_WATCH := 2
const DEFAULT_ROUNDS := 3
## A human earns the round's Round Win only if they controlled their own
## runner/watcher for at least this share of the round (a bot covering a
## disconnected player doesn't earn the returning human free wins).
const PRESENT_SHARE := 0.6

var id := ""
var settings: Dictionary = {}
var rounds: Array = []            # completed rounds, oldest first (see record_round)
var standings: Dictionary = {}    # uid -> {name, wins, played, partial, watch_turns, runner_turns, joined_round, ...}
var finished := false
var ended_early := false
var _recorded: Dictionary = {}    # match_id -> true


# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------
static func default_settings() -> Dictionary:
	return {"watch": DEFAULT_WATCH, "rounds": DEFAULT_ROUNDS, "rev": 0}


## A checked copy, or {} when anything is outside the allowed choices.
static func sanitize_settings(d: Variant) -> Dictionary:
	if not (d is Dictionary):
		return {}
	var w: Variant = d.get("watch")
	var r: Variant = d.get("rounds")
	if not (w is int or w is float) or not (r is int or r is float):
		return {}
	if not WATCH_CHOICES.has(int(w)) or not ROUND_CHOICES.has(int(r)):
		return {}
	return {"watch": int(w), "rounds": int(r), "rev": clampi(int(d.get("rev", 0)), 0, 65535)}


static func runners(watch: int) -> int:
	return SLOTS - watch


static func required_home(watch: int) -> int:
	return int(ceil(2.0 * float(runners(watch)) / 3.0))


## "3 rounds · 2 Night Watch · 6 runners · 4 home to win"
static func summary(s: Dictionary) -> String:
	var w := int(s.get("watch", DEFAULT_WATCH))
	var r := int(s.get("rounds", DEFAULT_ROUNDS))
	return "%s · %d Night Watch · %d runners · %d home to win" % ["Single round" if r == 1 else "%d rounds" % r, w, runners(w), required_home(w)]


## The same settings as short labelled values for the lobby (V5):
## ["3 rounds", "2 Night Watch", "4 home to win"].
static func summary_parts(s: Dictionary) -> Array[String]:
	var w := int(s.get("watch", DEFAULT_WATCH))
	var r := int(s.get("rounds", DEFAULT_ROUNDS))
	return ["1 round" if r == 1 else "%d rounds" % r, "%d Night Watch" % w, "%d home to win" % required_home(w)]


## The rules for one round: a copy of the base config with the party's slot
## counts.  Nothing else changes, and the base resource is left untouched.
static func rules_for(base: RulesConfig, watch: int) -> RulesConfig:
	var w := clampi(watch, WATCH_CHOICES[0], WATCH_CHOICES[-1])
	var c: RulesConfig = base.duplicate()
	c.patrol_slots = w
	c.runner_slots = runners(w)
	c.runners_needed = required_home(w)
	return c


# ---------------------------------------------------------------------------
# Series lifecycle
# ---------------------------------------------------------------------------
func start(locked: Dictionary, rng: RandomNumberGenerator) -> void:
	settings = sanitize_settings(locked)
	if settings.is_empty():
		settings = default_settings()
	id = "%08x" % (rng.randi() & 0x7FFFFFFF)
	rounds.clear()
	standings.clear()
	_recorded.clear()
	finished = false
	ended_early = false


func rounds_total() -> int:
	return int(settings.get("rounds", DEFAULT_ROUNDS))


## 1-based index of the round about to be played (or just played).
func next_round() -> int:
	return rounds.size() + 1


func in_progress() -> bool:
	return id != "" and not finished


## Fair random roles for one round of a friend party.
## players: [{slot, uid, is_bot}].  Returns slot -> TC.Role.
##  * Saved role preferences are ignored.
##  * Two or more humans: at least one human runner; up to
##    min(watch, humans - 1) humans are Night Watch, preferring those with
##    fewer Night Watch turns in this series (ties random), so the first
##    round is an equal draw and later rounds rotate.
##  * One human: they are Night Watch with the same odds as any seat
##    (watch / 8), otherwise a runner.  (Practice lets them choose.)
##  * Bots fill the remaining Night Watch seats.
func assign_roles(players: Array, seed_v: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var watch := int(settings.get("watch", DEFAULT_WATCH))
	var humans: Array = []
	var bots: Array = []
	for p in players:
		(bots if bool(p.get("is_bot", false)) else humans).append(p)
	var roles := {}
	for p in players:
		roles[int(p["slot"])] = TC.Role.RUNNER
	var human_watch := 0
	if humans.size() >= 2:
		human_watch = mini(watch, humans.size() - 1)
	elif humans.size() == 1:
		human_watch = 1 if rng.randf() < float(watch) / float(SLOTS) else 0
	var ranked: Array = []
	for h in humans:
		var st: Dictionary = standings.get(String(h["uid"]), {})
		ranked.append({"slot": int(h["slot"]), "turns": int(st.get("watch_turns", 0)), "r": rng.randf()})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["turns"] < b["turns"] if a["turns"] != b["turns"] else a["r"] < b["r"])
	for i in human_watch:
		roles[int(ranked[i]["slot"])] = TC.Role.PATROL
	var bot_order: Array = []
	for b in bots:
		bot_order.append({"slot": int(b["slot"]), "r": rng.randf()})
	bot_order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["r"] < b["r"])
	for i in mini(watch - human_watch, bot_order.size()):
		roles[int(bot_order[i]["slot"])] = TC.Role.PATROL
	return roles


## Records one round's authoritative results.  Idempotent by match id;
## cancelled rounds are ignored.  Returns true if the round was new.
func record_round(results: Dictionary) -> bool:
	var mid := String(results.get("match_id", ""))
	if mid == "" or _recorded.has(mid) or finished:
		return false
	var oc := int(results.get("outcome", TC.Outcome.NONE))
	if oc != TC.Outcome.RUNNERS_WIN and oc != TC.Outcome.PATROL_WIN:
		return false
	_recorded[mid] = true
	var idx := rounds.size() + 1
	var win_role := TC.Role.RUNNER if oc == TC.Outcome.RUNNERS_WIN else TC.Role.PATROL
	var round_time := maxf(1.0, float(results.get("round_time", 1.0)))
	var entry := {"round": idx, "match_id": mid, "outcome": oc, "players": []}
	for r in results.get("players", []):
		var row: Dictionary = r
		var role := int(row.get("role", TC.Role.RUNNER))
		# a human whose long disconnect handed the slot to a bot is still a
		# human here (played, partial), never a bot
		var bot := bool(row.get("is_bot", false)) and not bool(row.get("was_human", false))
		var away := float(row.get("away_s", 0.0))
		var present := bool(row.get("present", true)) and away <= (1.0 - PRESENT_SHARE) * round_time
		var won := role == win_role
		(entry["players"] as Array).append({"uid": String(row.get("uid", "")), "name": String(row.get("name", "")),
			"is_bot": bot, "role": role, "won": won, "eligible": present and not bot,
			"stamps": int(row.get("stamps", 0)), "finished": bool(row.get("finished", false)),
			"finish_order": int(row.get("finish_order", 0)), "finish_time": float(row.get("finish_time", -1.0)),
			"times_captured": int(row.get("times_captured", 0)), "captures": int(row.get("captures", 0)),
			"unique_captures": int(row.get("unique_captures", 0))})
		if bot:
			continue
		var uid := String(row.get("uid", ""))
		if uid == "":
			continue
		var st: Dictionary = standings.get(uid, {"name": String(row.get("name", "")), "wins": 0, "played": 0, "partial": 0,
			"watch_turns": 0, "runner_turns": 0, "joined_round": idx, "tags": 0, "distinct_tagged": 0,
			"stamps": 0, "homes": 0, "caught": 0})
		st["name"] = String(row.get("name", st["name"]))
		st["played"] = int(st["played"]) + 1
		if role == TC.Role.PATROL:
			st["watch_turns"] = int(st["watch_turns"]) + 1
			st["tags"] = int(st["tags"]) + int(row.get("captures", 0))
			st["distinct_tagged"] = int(st["distinct_tagged"]) + int(row.get("unique_captures", 0))
		else:
			st["runner_turns"] = int(st["runner_turns"]) + 1
			st["stamps"] = int(st["stamps"]) + int(row.get("stamps", 0))
			st["homes"] = int(st["homes"]) + (1 if bool(row.get("finished", false)) else 0)
			st["caught"] = int(st["caught"]) + int(row.get("times_captured", 0))
		if not present:
			st["partial"] = int(st["partial"]) + 1
		elif won:
			st["wins"] = int(st["wins"]) + 1
		standings[uid] = st
	rounds.append(entry)
	if rounds.size() >= rounds_total():
		finished = true
	return true


## The host ended the series early: completed rounds stand, nothing else counts.
func end_early() -> void:
	if not finished:
		finished = true
		ended_early = true


## Humans ordered by Round Wins; ties share a place (1, 1, 3 ...).
func leaderboard() -> Array:
	return leaderboard_of(standings)


static func leaderboard_of(st: Dictionary) -> Array:
	var rows: Array = []
	for uid in st:
		var s: Dictionary = st[uid]
		rows.append({"uid": uid, "name": String(s.get("name", "")), "wins": int(s.get("wins", 0)), "played": int(s.get("played", 0)),
			"partial": int(s.get("partial", 0)), "joined_round": int(s.get("joined_round", 1)),
			"watch_turns": int(s.get("watch_turns", 0)), "runner_turns": int(s.get("runner_turns", 0)),
			"tags": int(s.get("tags", 0)), "distinct_tagged": int(s.get("distinct_tagged", 0)),
			"stamps": int(s.get("stamps", 0)), "homes": int(s.get("homes", 0)), "caught": int(s.get("caught", 0))})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["wins"] != b["wins"]:
			return a["wins"] > b["wins"]
		return String(a["name"]).nocasecmp_to(String(b["name"])) < 0)
	var place := 0
	var prev := -1
	for i in rows.size():
		if int(rows[i]["wins"]) != prev:
			place = i + 1
			prev = int(rows[i]["wins"])
		rows[i]["place"] = place
	return rows


## "Runners won 2 rounds, Night Watch won 1" - a tally by role, not by friend.
func team_tally() -> Dictionary:
	var out := {"runners": 0, "watch": 0}
	for r in rounds:
		if int(r["outcome"]) == TC.Outcome.RUNNERS_WIN:
			out["runners"] += 1
		else:
			out["watch"] += 1
	return out


# ---------------------------------------------------------------------------
# Wire form (host -> clients, JSON).  Clients only display it.
# ---------------------------------------------------------------------------
func to_dict() -> Dictionary:
	return {"id": id, "settings": settings, "rounds": rounds, "standings": standings, "finished": finished, "ended_early": ended_early}


## Client: a checked copy of the host's series (bounded sizes and types), or {}.
static func sanitize_view(d: Variant) -> Dictionary:
	if not (d is Dictionary):
		return {}
	var s := sanitize_settings(d.get("settings", {}))
	if s.is_empty():
		return {}
	var out := {"id": String(d.get("id", "")).substr(0, 16), "settings": s, "finished": bool(d.get("finished", false)),
		"ended_early": bool(d.get("ended_early", false)), "rounds": [], "standings": {}}
	var rr: Variant = d.get("rounds", [])
	if rr is Array:
		for r in (rr as Array).slice(0, ROUND_CHOICES[-1]):
			if not (r is Dictionary):
				continue
			var plist: Array = []
			var pl: Variant = r.get("players", [])
			if pl is Array:
				for p in (pl as Array).slice(0, SLOTS):
					if p is Dictionary:
						plist.append({"uid": String(p.get("uid", "")).substr(0, 64), "name": NameRules.safe_display(String(p.get("name", ""))),
							"is_bot": bool(p.get("is_bot", false)), "role": clampi(int(p.get("role", 0)), 0, 1), "won": bool(p.get("won", false)),
							"eligible": bool(p.get("eligible", false)), "stamps": clampi(int(p.get("stamps", 0)), 0, 3),
							"finished": bool(p.get("finished", false)), "finish_order": clampi(int(p.get("finish_order", 0)), 0, SLOTS),
							"finish_time": float(p.get("finish_time", -1.0)), "times_captured": clampi(int(p.get("times_captured", 0)), 0, 999),
							"captures": clampi(int(p.get("captures", 0)), 0, 999), "unique_captures": clampi(int(p.get("unique_captures", 0)), 0, SLOTS)})
			(out["rounds"] as Array).append({"round": clampi(int(r.get("round", 0)), 0, 99), "match_id": String(r.get("match_id", "")).substr(0, 64),
				"outcome": clampi(int(r.get("outcome", 0)), 0, TC.Outcome.CANCELLED), "players": plist})
	var st: Variant = d.get("standings", {})
	if st is Dictionary:
		var n := 0
		for uid in st:
			if n >= SLOTS * 2:
				break
			var v: Variant = st[uid]
			if not (v is Dictionary):
				continue
			var e := {}
			for k in ["wins", "played", "partial", "watch_turns", "runner_turns", "joined_round", "tags", "distinct_tagged", "stamps", "homes", "caught"]:
				e[k] = clampi(int(v.get(k, 0)), 0, 9999)
			e["name"] = NameRules.safe_display(String(v.get("name", "")))
			out["standings"][String(uid).substr(0, 64)] = e
			n += 1
	return out
