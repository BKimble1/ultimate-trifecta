class_name RoundRanking
extends RefCounted
## What the results screens show, decided before anything is drawn (V6), so
## the order is authoritative and stable however often it is opened.
##
## A round has no single ranking: runners and the Night Watch do different
## jobs, so each team is listed on its own, by its own numbers (RULES.md
## "Round Win"), and nothing combines them into an invented score.
##   Runners      home first, in the order they got home (with the time);
##                then by splashes; then fewer times caught.  Runners not
##                home with the same splashes and catches share a line
##                position (no rank number is shown for them).
##   Night Watch  by different runners tagged, then tags.
## The series ranks people by Round Wins (PartySeries); ties share a place,
## shown as "T1" with no name order implied, and bots are never ranked.
## Names are shown as this device shows them (SocialSafety: blocked players
## are "Blocked player"); "You" is marked; bots are marked BOT; a player away
## for too much of the round is marked "away" (no Round Win for them).


## {outcome, cancelled, reason, round, total, practice, winners (role or -1),
##  runners: [row], watch: [row], celebrate: [row], me: row or {}}
## row: {slot, uid, name, is_bot, me, role, cosmetic, finished, finish_order,
##  finish_time, stamps, caught, tags, distinct, away, line}
static func round_view(results: Dictionary, my_uid: String, my_slot: int = -1) -> Dictionary:
	var oc := int(results.get("outcome", TC.Outcome.NONE))
	var out := {"outcome": oc, "cancelled": oc == TC.Outcome.CANCELLED or oc == TC.Outcome.NONE,
		"reason": reason(results), "why_short": short_reason(results),
		"round": int(results.get("round_index", 1)), "total": int(results.get("rounds_total", 1)),
		"practice": bool(results.get("practice", false)), "winners": -1, "runners": [], "watch": [], "celebrate": [], "me": {}}
	if bool(out["cancelled"]):
		return out   # no standings or rewards for a round that didn't finish
	out["winners"] = TC.Role.RUNNER if oc == TC.Outcome.RUNNERS_WIN else TC.Role.PATROL
	var rt := maxf(1.0, float(results.get("round_time", 1.0)))
	var mine_found := false
	for r in results.get("players", []):
		if not (r is Dictionary):
			continue
		var row := _row(r, rt)
		var me := (my_uid != "" and String(r.get("uid", "")) == my_uid)
		if not mine_found and me:
			mine_found = true
		row["me"] = me
		(out["runners"] if int(row["role"]) == TC.Role.RUNNER else out["watch"]).append(row)
	if not mine_found and my_slot >= 0:
		for row in out["runners"] + out["watch"]:
			if int(row["slot"]) == my_slot:
				row["me"] = true
	(out["runners"] as Array).sort_custom(_runner_before)
	(out["watch"] as Array).sort_custom(_watch_before)
	for row in out["runners"] + out["watch"]:
		if bool(row["me"]):
			out["me"] = row
	# the celebration: the winning team, people first, then bots
	var team: Array = (out["runners"] if int(out["winners"]) == TC.Role.RUNNER else out["watch"]).duplicate()
	var people := team.filter(func(x: Dictionary) -> bool: return not bool(x["is_bot"]))
	var bots := team.filter(func(x: Dictionary) -> bool: return bool(x["is_bot"]))
	out["celebrate"] = (people + bots).slice(0, 4)
	return out


static func _row(r: Dictionary, round_time: float) -> Dictionary:
	var bot := bool(r.get("is_bot", false)) and not bool(r.get("was_human", false))
	var away_s := float(r.get("away_s", 0.0))
	var away := not bot and (not bool(r.get("present", true)) or away_s > (1.0 - PartySeries.PRESENT_SHARE) * round_time)
	var row := {"slot": int(r.get("slot", -1)), "uid": String(r.get("uid", "")), "is_bot": bot,
		"role": int(r.get("role", TC.Role.RUNNER)), "cosmetic": r.get("cosmetic", {}), "finished": bool(r.get("finished", false)),
		"finish_order": int(r.get("finish_order", 0)), "finish_time": float(r.get("finish_time", -1.0)),
		"stamps": int(r.get("stamps", 0)), "caught": int(r.get("times_captured", 0)), "tags": int(r.get("captures", 0)),
		"distinct": int(r.get("unique_captures", 0)), "away": away, "me": false}
	row["name"] = SocialSafety.name_of({"uid": row["uid"], "pid": String(r.get("pid", "")), "name": String(r.get("name", "")), "is_bot": bot})
	row["line"] = ResultsScreen.contribution(r)
	return row


static func _runner_before(a: Dictionary, b: Dictionary) -> bool:
	if bool(a["finished"]) != bool(b["finished"]):
		return bool(a["finished"])
	if bool(a["finished"]) and int(a["finish_order"]) != int(b["finish_order"]):
		return int(a["finish_order"]) < int(b["finish_order"])
	if int(a["stamps"]) != int(b["stamps"]):
		return int(a["stamps"]) > int(b["stamps"])
	if int(a["caught"]) != int(b["caught"]):
		return int(a["caught"]) < int(b["caught"])
	return int(a["slot"]) < int(b["slot"])


static func _watch_before(a: Dictionary, b: Dictionary) -> bool:
	if int(a["distinct"]) != int(b["distinct"]):
		return int(a["distinct"]) > int(b["distinct"])
	if int(a["tags"]) != int(b["tags"]):
		return int(a["tags"]) > int(b["tags"])
	return int(a["slot"]) < int(b["slot"])


## Why the round ended, with the round's real numbers.
static func reason(r: Dictionary) -> String:
	var fin := int(r.get("finished", 0))
	var need := int(r.get("needed", 4))
	var t := int(r.get("round_time", 0))
	match int(r.get("outcome", 0)):
		TC.Outcome.RUNNERS_WIN:
			return "%d of %d runners needed made it home, %d:%02d into the round." % [fin, need, t / 60, t % 60]
		TC.Outcome.PATROL_WIN:
			return "Time ran out with %d of the %d runners needed home. The Night Watch held them off." % [fin, need]
	return "The round was interrupted (a player's connection or the host ended it), so it doesn't count and pays nothing."


## Pass 8: the reason in a few words for the results headline: "4 runners
## home · 2:31" or "Time expired: 3/4 home".
static func short_reason(r: Dictionary) -> String:
	var fin := int(r.get("finished", 0))
	var need := int(r.get("needed", 4))
	var t := int(r.get("round_time", 0))
	match int(r.get("outcome", 0)):
		TC.Outcome.RUNNERS_WIN:
			return "%d runner%s home · %d:%02d" % [fin, "" if fin == 1 else "s", t / 60, t % 60]
		TC.Outcome.PATROL_WIN:
			return "Time expired: %d/%d home" % [fin, need]
	return "Round cancelled"


## The series standings as shown: PartySeries order and shared places, with
## shown names, "you", and the place label ("1st", or "T1" for a tie).
static func series_rows(view: Dictionary, my_uid: String) -> Array:
	var rows := PartySeries.leaderboard_of(view.get("standings", {}))
	for r in rows:
		r["me"] = String(r["uid"]) == my_uid and my_uid != ""
		r["name"] = SocialSafety.name_of({"uid": r["uid"], "name": r["name"]})
		r["label"] = ("T%d" if bool(r["tied"]) else "%s") % ([int(r["place"])] if bool(r["tied"]) else [ordinal(int(r["place"]))])
	return rows


## Pass 8: your series standing in one line - "Series: tied 1st · 2 Round
## Wins" - for the pause menu, the map and results.  Round Wins only (one
## per eligible round on the winning team); a shared place says "tied" and
## no name order is implied; a late join or away rounds stay marked.  ""
## before any completed round (never a fake place) or when you are not in
## the standings (bots never are).
static func series_line(view: Dictionary, my_uid: String) -> String:
	if view.is_empty() or (view.get("rounds", []) as Array).is_empty() or my_uid == "":
		return ""
	for r in series_rows(view, my_uid):
		if not bool(r["me"]):
			continue
		var w := int(r["wins"])
		var s := "Series: %s%s · %d Round Win%s" % ["tied " if bool(r["tied"]) else "", ordinal(int(r["place"])), w, "" if w == 1 else "s"]
		if int(r["joined_round"]) > 1:
			s += " · joined round %d" % int(r["joined_round"])
		if int(r["partial"]) > 0:
			s += " · away %d" % int(r["partial"])
		return s
	return ""


## Podium steps: up to three places, people who share a place share a step.
static func podium(rows: Array) -> Array:
	var steps: Array = []
	for r in rows:
		var p := int(r["place"])
		if p > 3:
			break
		if steps.is_empty() or int(steps[-1]["place"]) != p:
			steps.append({"place": p, "rows": []})
		(steps[-1]["rows"] as Array).append(r)
	return steps


static func ordinal(n: int) -> String:
	match n:
		1: return "1st"
		2: return "2nd"
		3: return "3rd"
	return "%dth" % n
