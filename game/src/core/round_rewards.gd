class_name RoundRewards
extends RefCounted
## The rewards part of a round's results (V6), from one adapter so the
## results screen doesn't care where they come from.
##
## Coins and Season XP belong to the commerce Wallet: `Wallet.round_summary
## (match_id)` (docs/ECONOMY.md §9), settled once per round by the game
## service and refreshed through `Wallet.round_updated(match_id)`.  Only a
## `settled` round has Coins and Season XP added; a `pending` round shows
## what it is expected to pay, labelled as not yet added; every other state
## (practice, no service, not eligible, cancelled, capped, …) shows the
## wallet's one honest sentence.  Lifetime level-ups stay on this device
## (Save.apply_results).
##
## Each round's summary is remembered (bounded), so reopening the results, a
## reconnect or a repeated packet shows the same thing, never a second
## payout; a live wallet answer always wins over the remembered one.
##
## Summary: {state, message, coins_collected, coins (added), coins_projected,
## season_xp (added), season_xp_projected, tier_before, tier_after,
## frac_before, frac_after, lines, season_lines, settled, pending, away,
## level_up, level, source}.  Empty when there is nothing to show.

const KEEP := 32

static var _cache: Dictionary = {}
static var _order: Array = []
## tests: replaces the wallet lookup (func(match_id) -> Dictionary)
static var wallet_override: Callable


static func summary(match_id: String, local_reward: Dictionary = {}) -> Dictionary:
	if match_id == "":
		return {}
	var w := _wallet(match_id)
	if w.is_empty() and local_reward.get("wallet") is Dictionary:
		w = local_reward["wallet"]   # (what apply_results got back)
	var known: Dictionary = _cache.get(match_id, {})
	if not w.is_empty() and String(w.get("state", "unknown")) != "unknown":
		var s := _normalize(w, local_reward if not local_reward.is_empty() else known)
		_remember(match_id, s)
		return s
	if not known.is_empty():
		return known
	if not local_reward.is_empty():
		var s := _normalize({}, local_reward)
		_remember(match_id, s)
		return s
	return {}


static func _wallet(match_id: String) -> Dictionary:
	var s: Variant = null
	if wallet_override.is_valid():
		s = wallet_override.call(match_id)
	else:
		var ml := Engine.get_main_loop()
		var w: Node = (ml as SceneTree).root.get_node_or_null("Wallet") if ml is SceneTree else null
		if w != null and w.has_method("round_summary"):
			s = w.call("round_summary", match_id)
	return s if s is Dictionary else {}


static func _lines(v: Variant) -> Array:
	var out: Array = []
	if v is Array:
		for l in v:
			if l is Array and l.size() >= 2:
				out.append([String(l[0]), int(l[1])])
	return out


## `local`: this device's part (level-ups, an away round) from
## Save.apply_results, or the remembered summary.
static func _normalize(w: Dictionary, local: Dictionary) -> Dictionary:
	var st := String(w.get("state", "device" if w.is_empty() else "unknown"))
	var settled := st == "settled"
	return {
		"state": st,
		"message": String(w.get("message", "")),
		"coins_collected": int(w.get("coins_collected", 0)),
		"coins": int(w.get("coins", 0)) if settled else 0,
		"coins_projected": int(w.get("coins_projected", 0)),
		"season_xp": int(w.get("season_xp", 0)) if settled else 0,
		"season_xp_projected": int(w.get("season_xp_projected", 0)),
		"tier_before": int(w.get("tier_before", 0)), "tier_after": int(w.get("tier_after", 0)),
		"frac_before": float(w.get("frac_before", 0.0)), "frac_after": float(w.get("frac_after", 0.0)),
		"lines": _lines(w.get("lines", [])), "season_lines": _lines(w.get("season_lines", [])),
		"settled": settled, "pending": st == "pending",
		"away": bool(local.get("away", false)) or String(w.get("reason", "")) == "away",
		"level_up": bool(local.get("level_up", false)), "level": int(local.get("level", 0)),
		"source": "device" if w.is_empty() else "wallet",
	}


static func _remember(match_id: String, s: Dictionary) -> void:
	if not _cache.has(match_id):
		_order.append(match_id)
	_cache[match_id] = s
	while _order.size() > KEEP:
		_cache.erase(_order.pop_front())
