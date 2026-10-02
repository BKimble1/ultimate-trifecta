class_name RoundRewards
extends RefCounted
## The rewards part of a round's results (V6), from one adapter so the
## results screen doesn't care where they come from:
##   - the commerce workstream's wallet, when present: an autoload named
##     "Wallet" with round_summary(match_id) -> Dictionary (coins collected
##     on the campus, credited coins, Season XP progress), settled once per
##     round by its own ledger;
##   - otherwise this device's reward for the round (Save.apply_results),
##     remembered per round id so reopening the results, a reconnect or a
##     repeated packet shows the same summary, never a second payout.
## Summary: {coins_collected, coins, lines: [[label, amount]], away, level_up,
## level, season: {xp_gained, tier, xp_in_tier, xp_for_tier, premium} or {},
## pending, source}.  Empty when there is nothing to show.

const KEEP := 32

static var _cache: Dictionary = {}
static var _order: Array = []
## tests: replaces the wallet lookup (func(match_id) -> Dictionary)
static var wallet_override: Callable


static func summary(match_id: String, local_reward: Dictionary = {}) -> Dictionary:
	if match_id == "":
		return {}
	var w := _wallet(match_id)
	if not w.is_empty():
		_remember(match_id, w)
		return w
	if not local_reward.is_empty() and not _cache.has(match_id):
		_remember(match_id, _normalize(local_reward, "device"))
	return _cache.get(match_id, {})


static func _wallet(match_id: String) -> Dictionary:
	var s: Variant = null
	if wallet_override.is_valid():
		s = wallet_override.call(match_id)
	else:
		var ml := Engine.get_main_loop()
		var w: Node = (ml as SceneTree).root.get_node_or_null("Wallet") if ml is SceneTree else null
		if w != null and w.has_method("round_summary"):
			s = w.call("round_summary", match_id)
	if s is Dictionary and not (s as Dictionary).is_empty():
		return _normalize(s, "wallet")
	return {}


static func _normalize(r: Dictionary, source: String) -> Dictionary:
	var lines: Array = []
	for l in r.get("lines", []):
		if l is Array and l.size() >= 2:
			lines.append([String(l[0]), int(l[1])])
	var season: Dictionary = {}
	var sv: Variant = r.get("season", {})
	if sv is Dictionary and not (sv as Dictionary).is_empty():
		season = {"xp_gained": int(sv.get("xp_gained", 0)), "tier": int(sv.get("tier", 0)), "xp_in_tier": int(sv.get("xp_in_tier", 0)),
			"xp_for_tier": maxi(1, int(sv.get("xp_for_tier", 1))), "premium": bool(sv.get("premium", false))}
	return {"coins_collected": int(r.get("coins_collected", 0)), "coins": int(r.get("coins", 0)), "lines": lines,
		"away": bool(r.get("away", false)), "level_up": bool(r.get("level_up", false)), "level": int(r.get("level", 0)),
		"season": season, "pending": bool(r.get("pending", false)), "source": source}


static func _remember(match_id: String, s: Dictionary) -> void:
	if not _cache.has(match_id):
		_order.append(match_id)
	_cache[match_id] = s
	while _order.size() > KEEP:
		_cache.erase(_order.pop_front())
