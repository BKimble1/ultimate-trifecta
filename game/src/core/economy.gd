class_name Economy
extends RefCounted
## V6 economy rules shared by the client projection and the service
## settlement (both read the numbers in config/catalogue.json "economy";
## service/src/economy.js implements the same functions and a test compares
## them).  Pure functions, no scene tree.
##
## One player-facing currency, Coins.  A round pays Coins and Season XP only
## when it is an eligible, completed, service-verified online round (see
## eligibility()); practice settles nothing into the wallet or the pass.
## Purchased Coins never pass through here, so they never become XP.
## Lifetime level XP stays local (RulesLogic.lifetime_xp) and is separate
## from Season XP.

## v2 (Pass 8): the row also binds active_s, the seconds of active play the
## host's simulation counted (challenges); the host reports report_version 2.
const DIGEST_VERSION := "v2"


static func cfg() -> Dictionary:
	return Catalogue.economy()


static func _row_role(row: Dictionary) -> int:
	return int(row.get("role", TC.Role.RUNNER))


static func team_won(row: Dictionary, outcome: int) -> bool:
	var role := _row_role(row)
	return (role == TC.Role.RUNNER and outcome == TC.Outcome.RUNNERS_WIN) or (role == TC.Role.PATROL and outcome == TC.Outcome.PATROL_WIN)


static func first_home(row: Dictionary, results: Dictionary) -> bool:
	return int(results.get("fastest_slot", -1)) >= 0 and int(results.get("fastest_slot", -1)) == int(row.get("slot", -2)) \
		and bool(row.get("finished", false))


## Coins this row collected from pickups (the match's coins_picked field,
## bounded by the round's spawn count).
static func coins_picked(row: Dictionary, results: Dictionary = {}) -> int:
	var spawns := int(results.get("coin_spawns", cfg().get("eligibility", {}).get("max_coin_spawns", 10)))
	return clampi(int(row.get("coins_picked", 0)), 0, clampi(spawns, 0, int(cfg().get("eligibility", {}).get("max_coin_spawns", 10))))


## Coins for one eligible completed round: {coins, lines}.
static func round_coins(row: Dictionary, results: Dictionary) -> Dictionary:
	var c: Dictionary = cfg().get("round_coins", {})
	var lines: Array = []
	if int(results.get("outcome", 0)) == TC.Outcome.CANCELLED:
		return {"coins": 0, "lines": lines}
	var total := 0
	var add := func(label: String, n: int) -> void:
		if n > 0:
			lines.append([label, n])
	var base := int(c.get("completed", 0))
	total += base
	add.call("Completed the round", base)
	var picked := coins_picked(row, results) * int(c.get("pickup", 1))
	total += picked
	add.call("Coins collected ×%d" % coins_picked(row, results), picked)
	if team_won(row, int(results.get("outcome", 0))):
		total += int(c.get("team_win", 0))
		add.call("Team win", int(c.get("team_win", 0)))
	if _row_role(row) == TC.Role.RUNNER:
		if bool(row.get("finished", false)):
			total += int(c.get("runner_home", 0))
			add.call("Made it home", int(c.get("runner_home", 0)))
		if first_home(row, results):
			total += int(c.get("first_home", 0))
			add.call("First home", int(c.get("first_home", 0)))
	else:
		var u := mini(int(row.get("unique_captures", 0)), int(c.get("watch_distinct_tag_cap", 3)))
		if u > 0:
			total += u * int(c.get("watch_distinct_tag", 0))
			add.call("Different runners tagged ×%d" % u, u * int(c.get("watch_distinct_tag", 0)))
	return {"coins": total, "lines": lines}


## Season XP for one eligible completed round: {xp, lines}.  Role
## contributions are balanced and capped: tagging the same runner again
## earns nothing more, and distinct tags stop counting after the cap.
static func round_season_xp(row: Dictionary, results: Dictionary) -> Dictionary:
	var c: Dictionary = cfg().get("season_xp", {})
	var lines: Array = []
	if int(results.get("outcome", 0)) == TC.Outcome.CANCELLED:
		return {"xp": 0, "lines": lines}
	var xp := int(c.get("completed", 0))
	lines.append(["Completed the round", int(c.get("completed", 0))])
	if _row_role(row) == TC.Role.RUNNER:
		var s := clampi(int(row.get("stamps", 0)), 0, int(c.get("stamp_cap", 3)))
		if s > 0:
			xp += s * int(c.get("stamp", 0))
			lines.append(["Splashes ×%d" % s, s * int(c.get("stamp", 0))])
		if bool(row.get("finished", false)):
			xp += int(c.get("runner_home", 0))
			lines.append(["Made it home", int(c.get("runner_home", 0))])
	else:
		var u := clampi(int(row.get("unique_captures", 0)), 0, int(c.get("watch_distinct_tag_cap", 3)))
		if u > 0:
			xp += u * int(c.get("watch_distinct_tag", 0))
			lines.append(["Different runners tagged ×%d" % u, u * int(c.get("watch_distinct_tag", 0))])
	if team_won(row, int(results.get("outcome", 0))):
		xp += int(c.get("team_win", 0))
		lines.append(["Team win", int(c.get("team_win", 0))])
	return {"xp": xp, "lines": lines}


## The most a single round can pay (service bound; also documented).
static func max_round_coins() -> int:
	var c: Dictionary = cfg().get("round_coins", {})
	var runner := int(c.get("runner_home", 0)) + int(c.get("first_home", 0))
	var watch := int(c.get("watch_distinct_tag", 0)) * int(c.get("watch_distinct_tag_cap", 3))
	return int(c.get("completed", 0)) + int(c.get("team_win", 0)) + maxi(runner, watch) \
		+ int(c.get("pickup", 1)) * int(cfg().get("eligibility", {}).get("max_coin_spawns", 10))


## Eligibility for the paid economy, as far as the client can tell (the
## service decides): {eligible, reason}.  reason: "" | "practice" |
## "cancelled" | "away" | "few_humans" | "bot" | "no_service".
static func eligibility(results: Dictionary, row: Dictionary, practice: bool) -> Dictionary:
	var e: Dictionary = cfg().get("eligibility", {})
	if practice or bool(results.get("practice", false)):
		return {"eligible": false, "reason": "practice"}
	if int(results.get("outcome", 0)) == TC.Outcome.CANCELLED:
		return {"eligible": false, "reason": "cancelled"}
	if bool(row.get("is_bot", false)):
		return {"eligible": false, "reason": "bot"}
	if not present_enough(row, results):
		return {"eligible": false, "reason": "away"}
	var humans := 0
	for r in results.get("players", []):
		if r is Dictionary and not bool(r.get("is_bot", false)) and present_enough(r, results):
			humans += 1
	if humans < int(e.get("min_humans", 2)):
		return {"eligible": false, "reason": "few_humans"}
	return {"eligible": true, "reason": ""}


static func present_enough(row: Dictionary, results: Dictionary) -> bool:
	var share := float(cfg().get("eligibility", {}).get("present_share", 0.6))
	var rt := float(results.get("round_time", 0.0))
	var away := float(row.get("away_s", 0.0))
	return bool(row.get("present", true)) and (rt <= 0.0 or away <= (1.0 - share) * rt)


## The row as both sides hash it.  The host reports rows to the service; each
## player confirms the row its own game received by sending this digest, and
## the service settles a player only when the two agree.
static func row_canonical(match_id: String, results: Dictionary, row: Dictionary) -> String:
	return "%s|%s|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d" % [DIGEST_VERSION, match_id, int(results.get("outcome", 0)), _row_role(row),
		clampi(int(row.get("stamps", 0)), 0, 3), 1 if bool(row.get("finished", false)) else 0, 1 if first_home(row, results) else 0,
		clampi(int(row.get("unique_captures", 0)), 0, 7), maxi(0, int(row.get("coins_picked", 0))),
		1 if bool(row.get("present", true)) else 0, int(round(float(row.get("away_s", 0.0)))), int(round(float(results.get("round_time", 0.0)))),
		maxi(0, int(row.get("active_s", 0)))]


static func row_digest(match_id: String, results: Dictionary, row: Dictionary) -> String:
	return row_canonical(match_id, results, row).sha256_text()


# ---------------------------------------------------------------- season
## The highest tier reached with `xp` (tier 1 needs 0 XP).
static func tier_for_xp(sid: String, xp: int) -> int:
	var tier := 0
	for t in Catalogue.season_tiers(sid):
		if xp >= int(t["xp"]):
			tier = int(t["tier"])
	return tier


static func max_tier(sid: String) -> int:
	return Catalogue.season_tiers(sid).size()


## Pass 9: Season XP a tier needs (0 for tier 1; -1 outside the table).
static func tier_xp(sid: String, tier: int) -> int:
	var ts := Catalogue.season_tiers(sid)
	if tier < 1 or tier > ts.size():
		return -1
	return int(ts[tier - 1]["xp"])


## Pass 9: how many tiers a game service on catalogue `version` has (the
## tiers added up to that version: 30 for version 2, 100 for version 3).
static func tiers_in_version(sid: String, version: int) -> int:
	var n := 0
	for t in Catalogue.season_tiers(sid):
		if maxi(1, int(t.get("added_in", 1))) <= version:
			n += 1
	return n


## Pass 9: a tier with a reward on either track.
static func has_reward(sid: String, tier: int) -> bool:
	return not reward_at(sid, tier, "free").is_empty() or not reward_at(sid, tier, "premium").is_empty()


## Pass 9: the first tier after `tier` with a reward this player can get
## (Free only without Premium); -1 when none is left.
static func next_reward_tier(sid: String, tier: int, premium: bool) -> int:
	for t in Catalogue.season_tiers(sid):
		var n := int(t["tier"])
		if n <= tier:
			continue
		if not reward_at(sid, n, "free").is_empty() or (premium and not reward_at(sid, n, "premium").is_empty()):
			return n
	return -1


## Pass 9: runs of consecutive progress tiers (no reward on either track),
## [[first, last], ...] in order: the track shows each run as one column.
static func progress_runs(sid: String) -> Array:
	var out: Array = []
	var start := -1
	for t in Catalogue.season_tiers(sid):
		var n := int(t["tier"])
		if not has_reward(sid, n):
			if start < 0:
				start = n
		elif start >= 0:
			out.append([start, n - 1])
			start = -1
	if start >= 0:
		out.append([start, max_tier(sid)])
	return out


## Pass 9: a reward as one string ("coins:50" or the item id), as the game
## service names it (economy.js rewardKey): a claim says which reward its
## game showed, so a service on another catalogue never grants another one.
static func reward_key(r: Dictionary) -> String:
	if r.is_empty():
		return ""
	if r.has("coins"):
		return "coins:%d" % int(r["coins"])
	return String(r.get("item", ""))


## Progress for the header: {tier, next, into, need, frac, xp, total}.
static func tier_progress(sid: String, xp: int) -> Dictionary:
	var tiers := Catalogue.season_tiers(sid)
	var tier := tier_for_xp(sid, xp)
	var total := int(tiers[-1]["xp"]) if not tiers.is_empty() else 0
	if tier >= tiers.size():
		return {"tier": tier, "next": -1, "into": 0, "need": 0, "frac": 1.0, "xp": xp, "total": total}
	var cur := int(tiers[tier - 1]["xp"]) if tier > 0 else 0
	var nxt := int(tiers[tier]["xp"])
	var span := maxi(1, nxt - cur)
	return {"tier": tier, "next": tier + 1, "into": xp - cur, "need": nxt - xp, "frac": clampf(float(xp - cur) / float(span), 0.0, 1.0),
		"xp": xp, "total": total}


static func reward_at(sid: String, tier: int, track: String) -> Dictionary:
	for t in Catalogue.season_tiers(sid):
		if int(t["tier"]) == tier:
			var r: Variant = t.get(track)
			return r if r is Dictionary else {}
	return {}


static func claim_key(tier: int, track: String) -> String:
	return "%d:%s" % [tier, track]


## A reward cell's state: "locked" (tier not reached), "premium_locked"
## (reached, Premium not owned), "claimable", "claimed", or "empty".
static func cell_state(sid: String, tier: int, track: String, xp: int, premium: bool, claimed: Dictionary) -> String:
	if reward_at(sid, tier, track).is_empty():
		return "empty"
	if claimed.has(claim_key(tier, track)):
		return "claimed"
	if tier_for_xp(sid, xp) < tier:
		return "locked"
	if track == "premium" and not premium:
		return "premium_locked"
	return "claimable"


## Everything claimable now, in tier order: [{tier, track, reward}].  Buying
## Premium later makes every Premium reward already earned claimable.
## Pass 9: `upto` (> 0) leaves out tiers past the last one the game service
## has (a service on an older catalogue).
static func claimable(sid: String, xp: int, premium: bool, claimed: Dictionary, upto: int = 0) -> Array:
	var out: Array = []
	for t in Catalogue.season_tiers(sid):
		if upto > 0 and int(t["tier"]) > upto:
			break
		for track in ["free", "premium"]:
			if cell_state(sid, int(t["tier"]), track, xp, premium, claimed) == "claimable":
				out.append({"tier": int(t["tier"]), "track": track, "reward": reward_at(sid, int(t["tier"]), track)})
	return out


## Coins the whole track pays (documentation and tests).
static func season_coin_total(sid: String, track: String) -> int:
	var n := 0
	for t in Catalogue.season_tiers(sid):
		var r: Variant = t.get(track)
		if r is Dictionary:
			n += int((r as Dictionary).get("coins", 0))
	return n


# ---------------------------------------------------------------- legacy
## The one-time import of a pre-V6 local balance, bounded by what the local
## stats could plausibly have earned and a hard cap.
static func legacy_import_amount(coins: int, online_rounds: int, practice_rounds: int) -> int:
	var l: Dictionary = cfg().get("legacy_import", {})
	var plausible := online_rounds * int(l.get("per_online_round", 75)) + practice_rounds * int(l.get("per_practice_round", 38))
	return clampi(mini(coins, plausible), 0, int(l.get("cap", 2000)))
