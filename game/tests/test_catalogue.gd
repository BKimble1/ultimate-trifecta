extends RefCounted
## V6 catalogue, economy and Season 1 tables: one authoritative catalogue
## with stable IDs, honest products (no stored real-money prices), every
## advertised item backed by art, Season 1 complete (30 tiers, Free and
## Premium, ascending XP), earning numbers in the documented target band,
## and the round rules (cancelled/practice/away/bots/repeat captures).
var t


func test_ids_are_stable_and_unique() -> void:
	var seen := {}
	for it in Catalogue.all_items():
		var id := String(it["id"])
		t.check(not seen.has(id), "unique id %s" % id)
		seen[id] = true
		t.check(id.contains(":"), "%s is field:key" % id)
		t.check(String(it["kind"]) in ["coin_item", "apple_skin", "coin_pack", "season_premium", "season_reward"], "%s has a known kind" % id)
	t.check(Catalogue.version() >= 1, "versioned catalogue")
	# V3 owned keys keep their meaning: the catalogue ID of a runner item is
	# exactly Cosmetics.own_key(field, key)
	t.eq(Catalogue.id_for("hat", "crown"), Cosmetics.own_key("hat", "crown"), "catalogue id = the save's owned key")
	t.check(Catalogue.has("hat:crown") and Catalogue.has("outfit:frog") and Catalogue.has("emote:dance"), "pre-V6 priced items are in the catalogue")


func test_products_are_honest() -> void:
	var prefix := String(Catalogue.data()["bundle_prefix"])
	t.eq(prefix, "com.idlery.ultimatetrifecta", "products live under the app's bundle prefix")
	var packs := 0
	var skins := 0
	for pid in Catalogue.product_ids():
		var p := Catalogue.product(pid)
		t.check(pid.begins_with(prefix + "."), "%s under the bundle prefix" % pid)
		t.check(not p.has("price") and not p.has("display_price"), "%s: no stored real-money price (StoreKit's localized price is shown)" % pid)
		t.eq(Catalogue.product_of(String(p["item"])), pid, "%s maps both ways" % pid)
		if String(p["kind"]) == "coin_pack":
			packs += 1
			t.eq(String(p["apple_type"]), "CONSUMABLE", "%s is consumable" % pid)
		else:
			skins += 1
			t.eq(String(p["apple_type"]), "NON_CONSUMABLE", "%s is a permanent skin" % pid)
	t.eq(packs, 3, "three Coin packs")
	t.eq(skins, 2, "two direct-purchase skins")
	var amounts := Catalogue.items_of_kind("coin_pack").map(func(i: Dictionary) -> int: return int(i["coins"]))
	amounts.sort()
	t.eq(amounts, [500, 1500, 3500], "500 / 1,500 / 3,500 Coins")
	t.eq(Catalogue.price("season:s1:premium"), 1500, "Season 1 Premium costs 1,500 Coins")
	t.eq(Catalogue.product_of("season:s1:premium"), "", "Premium is never an Apple product (bought with Coins, no subscription)")


func test_shop_outfits_and_prices() -> void:
	var shop_outfits := ["outfit:moonlight_runner", "outfit:starry_sleeper", "outfit:varsity_sprinter", "outfit:raincoat_explorer",
		"outfit:campus_courier", "outfit:lantern_scout"]
	for id in shop_outfits:
		t.check(Catalogue.has(id), "%s is in the catalogue" % id)
	t.eq(Catalogue.kind("outfit:moonlight_runner"), "apple_skin", "Moonlight Runner: direct Apple skin")
	t.eq(Catalogue.kind("outfit:starry_sleeper"), "apple_skin", "Starry Sleeper: direct Apple skin")
	for it in Catalogue.items_of_kind("coin_item"):
		if String(it["id"]).begins_with("outfit:") and not bool(it.get("legacy", false)):
			t.check(int(it["price"]) >= 300 and int(it["price"]) <= 1200, "%s priced in the 300-1,200 band (%d)" % [it["id"], int(it["price"])])
	# Season rewards are never sold under another ID
	var sold := {}
	for it in Catalogue.all_items():
		if String(it["kind"]) in Catalogue.SELLABLE:
			for g in Catalogue.grants(String(it["id"])):
				sold[String(g)] = true
	for rid in Catalogue.season_reward_ids("s1"):
		t.check(not sold.has(rid), "pass reward %s is not resold in the Shop" % rid)
		t.eq(Catalogue.kind(rid), "season_reward", "%s is a season reward" % rid)


## Run after the art merge: every runner item the Shop or the Season Pass
## advertises must have its Cosmetics entry (name, meshes).  Until the art
## workstream's entries land this lists what's missing.
func test_every_referenced_item_exists_in_cosmetics() -> void:
	var missing: Array[String] = []
	for it in Catalogue.all_items():
		var id := String(it["id"])
		if Catalogue.is_runner_item(id) and not Catalogue.has_art(id):
			missing.append(id)
	for rid in Catalogue.season_reward_ids("s1"):
		if Catalogue.is_runner_item(rid) and not Catalogue.has_art(rid) and not missing.has(rid):
			missing.append(rid)
	t.eq(missing, [] as Array[String], "every catalogue/Season runner item exists in Cosmetics (art)")
	# nothing priced in Cosmetics is orphaned (unobtainable)
	var orphans: Array[String] = []
	for f in Cosmetics.ORDER:
		for k in Cosmetics.keys_of(f):
			if Cosmetics.cost(f, String(k)) > 0 and not Catalogue.has(Catalogue.id_for(f, String(k))):
				orphans.append(Catalogue.id_for(f, String(k)))
	t.eq(orphans, [] as Array[String], "every priced Cosmetics item has a catalogue entry")


func test_season_table_is_complete() -> void:
	var tiers := Catalogue.season_tiers("s1")
	t.eq(tiers.size(), 30, "30 tiers")
	var prev := -1
	var free_n := 0
	for i in tiers.size():
		var tr: Dictionary = tiers[i]
		t.eq(int(tr["tier"]), i + 1, "tier %d in order" % (i + 1))
		t.check(int(tr["xp"]) > prev, "tier %d needs more XP than tier %d" % [i + 1, i])
		prev = int(tr["xp"])
		t.check(tr.get("premium") is Dictionary, "tier %d has a Premium reward" % (i + 1))
		for track in ["free", "premium"]:
			var r: Variant = tr.get(track)
			if r is Dictionary:
				var rd: Dictionary = r
				t.check(rd.has("item") != rd.has("coins"), "tier %d %s: exactly one item or a Coin amount" % [i + 1, track])
				if rd.has("item"):
					t.check(Catalogue.has(String(rd["item"])), "tier %d %s item is catalogued" % [i + 1, track])
				else:
					t.check(int(rd["coins"]) > 0 and int(rd["coins"]) <= 100, "tier %d %s: a modest Coin reward" % [i + 1, track])
				if track == "free":
					free_n += 1
	t.eq(int(tiers[0]["xp"]), 0, "tier 1 is reached at once")
	t.eq(free_n, 15, "15 Free rewards")
	t.eq(Catalogue.season("s1").get("ends_at"), null, "no fabricated end date")
	t.check(Economy.season_coin_total("s1", "premium") < Catalogue.price("season:s1:premium"), "Premium Coins never pay back the pass")
	# the advertised item mix: outfits, accessories, emotes, profile cosmetics
	var types := {}
	for rid in Catalogue.season_reward_ids("s1"):
		types[Catalogue.type_label(rid)] = int(types.get(Catalogue.type_label(rid), 0)) + 1
	t.eq(int(types.get("Outfit", 0)), 4, "4 outfits")
	t.eq(int(types.get("Hat", 0)), 4, "4 hats")
	t.eq(int(types.get("Shoes", 0)), 2, "2 shoes")
	t.eq(int(types.get("Emote", 0)), 4, "4 emotes")


func test_tier_boundaries_and_claim_states() -> void:
	t.eq(Economy.tier_for_xp("s1", 0), 1, "0 XP: tier 1")
	t.eq(Economy.tier_for_xp("s1", 199), 1, "199 XP: still tier 1")
	t.eq(Economy.tier_for_xp("s1", 200), 2, "200 XP: tier 2 exactly")
	t.eq(Economy.tier_for_xp("s1", 8299), 29, "one short of the last tier")
	t.eq(Economy.tier_for_xp("s1", 8300), 30, "the last tier")
	t.eq(Economy.tier_for_xp("s1", 999999), 30, "never past 30 (no paid skips either)")
	var p := Economy.tier_progress("s1", 250)
	t.eq(int(p["next"]), 3, "next tier")
	t.eq(int(p["need"]), 150, "150 XP to tier 3")
	t.near(float(p["frac"]), 0.25, 0.001, "a quarter of the way")
	# free player at tier 3: free rewards claimable, premium earned but locked
	var c := {}
	t.eq(Economy.cell_state("s1", 3, "free", 400, false, c), "claimable", "free reward claimable without buying")
	t.eq(Economy.cell_state("s1", 3, "premium", 400, false, c), "premium_locked", "premium earned but locked")
	t.eq(Economy.cell_state("s1", 4, "premium", 400, false, c), "locked", "tier 4 not reached")
	t.eq(Economy.cell_state("s1", 2, "free", 400, false, c), "empty", "no free reward at tier 2")
	var free_now := Economy.claimable("s1", 400, false, c)
	t.eq(free_now.size(), 2, "tiers 1 and 3 free")
	# late Premium: every Premium reward already earned becomes claimable
	var late := Economy.claimable("s1", 400, true, c)
	t.eq(late.size(), 5, "tiers 1-3 premium + 2 free")
	c[Economy.claim_key(1, "free")] = true
	t.eq(Economy.cell_state("s1", 1, "free", 400, true, c), "claimed", "claimed stays claimed")


func _row(role: int, o: Dictionary = {}) -> Dictionary:
	var r := {"slot": 0, "role": role, "stamps": 0, "finished": false, "unique_captures": 0, "captures": 0, "coins_picked": 0,
		"present": true, "away_s": 0.0, "is_bot": false}
	r.merge(o, true)
	return r


func _res(outcome: int, rows: Array, o: Dictionary = {}) -> Dictionary:
	var r := {"match_id": "ABCDEF-1-0000beef", "outcome": outcome, "fastest_slot": -1, "round_time": 200.0, "players": rows}
	r.merge(o, true)
	return r


func test_round_coins_and_season_xp() -> void:
	var e: Dictionary = Catalogue.economy()
	var runner := _row(TC.Role.RUNNER, {"slot": 0, "stamps": 3, "finished": true, "coins_picked": 2})
	var watch := _row(TC.Role.PATROL, {"slot": 1, "unique_captures": 5, "captures": 9})
	var mate := _row(TC.Role.RUNNER, {"slot": 2})
	var res := _res(TC.Outcome.RUNNERS_WIN, [runner, watch, mate], {"fastest_slot": 0})
	var rc: Dictionary = e["round_coins"]
	t.eq(int(Economy.round_coins(runner, res)["coins"]), int(rc["completed"]) + 2 + int(rc["team_win"]) + int(rc["runner_home"]) + int(rc["first_home"]),
		"runner: completion + 2 pickups (1 each) + win + home + first home")
	t.eq(int(Economy.round_coins(watch, res)["coins"]), int(rc["completed"]) + int(rc["watch_distinct_tag"]) * int(rc["watch_distinct_tag_cap"]),
		"Night Watch: distinct tags capped (5 distinct, 9 tags -> 3)")
	var sx: Dictionary = e["season_xp"]
	t.eq(int(Economy.round_season_xp(watch, res)["xp"]), int(sx["completed"]) + 3 * int(sx["watch_distinct_tag"]),
		"repeat captures can't farm XP: distinct runners only, capped")
	var again := _row(TC.Role.PATROL, {"slot": 1, "unique_captures": 1, "captures": 40})
	t.eq(int(Economy.round_season_xp(again, res)["xp"]), int(sx["completed"]) + int(sx["watch_distinct_tag"]), "tagging one runner 40 times = one distinct tag")
	var cancelled := _res(TC.Outcome.CANCELLED, [runner, watch])
	t.eq(int(Economy.round_coins(runner, cancelled)["coins"]), 0, "cancelled round: no Coins")
	t.eq(int(Economy.round_season_xp(runner, cancelled)["xp"]), 0, "cancelled round: no XP")
	t.check(Economy.max_round_coins() <= 40, "a round is bounded (%d Coins max)" % Economy.max_round_coins())


func test_eligibility_practice_bots_away() -> void:
	var a := _row(TC.Role.RUNNER, {"slot": 0})
	var b := _row(TC.Role.PATROL, {"slot": 1})
	var bot := _row(TC.Role.PATROL, {"slot": 2, "is_bot": true})
	t.check(bool(Economy.eligibility(_res(TC.Outcome.RUNNERS_WIN, [a, b]), a, false)["eligible"]), "two present humans: eligible")
	t.eq(String(Economy.eligibility(_res(TC.Outcome.RUNNERS_WIN, [a, b]), a, true)["reason"]), "practice", "practice is isolated")
	t.eq(String(Economy.eligibility(_res(TC.Outcome.RUNNERS_WIN, [a, bot]), a, false)["reason"]), "few_humans", "you + bots: not eligible")
	t.eq(String(Economy.eligibility(_res(TC.Outcome.RUNNERS_WIN, [a, bot]), bot, false)["reason"]), "bot", "bots have no wallet")
	var away := _row(TC.Role.RUNNER, {"slot": 0, "away_s": 120.0})
	t.eq(String(Economy.eligibility(_res(TC.Outcome.RUNNERS_WIN, [away, b]), away, false)["reason"]), "away", "away 60% of the round: nothing")
	t.eq(String(Economy.eligibility(_res(TC.Outcome.CANCELLED, [a, b]), a, false)["reason"]), "cancelled", "cancelled")


func test_row_digest_is_canonical() -> void:
	var r := _row(TC.Role.RUNNER, {"slot": 3, "stamps": 2, "coins_picked": 1, "away_s": 3.4})
	var res := _res(TC.Outcome.PATROL_WIN, [r])
	var d1 := Economy.row_digest("M-1", res, r)
	# the same row after the network (JSON floats, extra keys) hashes the same
	var wire: Dictionary = JSON.parse_string(JSON.stringify(r))
	wire["name"] = "Someone"
	t.eq(Economy.row_digest("M-1", res, wire), d1, "same digest after JSON and with display fields")
	var r2 := r.duplicate()
	r2["coins_picked"] = 2
	t.check(Economy.row_digest("M-1", res, r2) != d1, "a different pickup count changes the digest")
	t.check(Economy.row_digest("M-2", res, r) != d1, "bound to the match")
	# Pass 8 (report v2): the seconds of active play are bound too
	var r3 := r.duplicate()
	r3["active_s"] = 150
	t.check(Economy.row_digest("M-1", res, r3) != d1, "a different active_s changes the digest")
	t.eq(Economy.row_canonical("M-1", res, r3), "v2|M-1|2|0|2|0|0|0|1|1|3|200|150", "canonical form (shared with service/src/economy.js)")


func test_compute_rewards_decoupled_from_coins() -> void:
	var cfg: RulesConfig = Rules.cfg
	var w := _row(TC.Role.PATROL, {"slot": 0, "unique_captures": 2, "captures": 5})
	var r := _row(TC.Role.RUNNER, {"slot": 1, "coins_picked": 4})
	var res := _res(TC.Outcome.PATROL_WIN, [w, r])
	var r0 := RulesLogic.compute_rewards(res, 0, cfg, false)
	t.eq(int(r0["xp"]), cfg.coins_participation + 2 * cfg.coins_unique_capture + cfg.coins_team_win, "lifetime XP keeps the V5 performance values")
	t.check(int(r0["xp"]) != int(r0["coins"]), "XP is no longer the Coin amount")
	var r1 := RulesLogic.compute_rewards(res, 1, cfg, false)
	t.eq(int(r1["xp"]), cfg.coins_participation, "pickups never become lifetime XP (idle survival earns nothing extra)")
	t.eq(int(r1["coins"]), int(Economy.round_coins(r, res)["coins"]), "Coins projection from the economy table")
	var pr := RulesLogic.compute_rewards(res, 1, cfg, true)
	t.eq(int(pr["coins"]), 0, "practice projects no Coins")
	t.eq(int(pr["season_xp"]), 0, "practice projects no Season XP")
	t.eq(int(pr["coins_picked"]), 4, "practice still reports the coins picked (shown, not paid)")


func test_earning_rate_meets_the_pass_target() -> void:
	# a simulated mix of eligible rounds (documented in docs/ECONOMY.md):
	# half runner/half Night Watch, ~50% team wins, runners home 60%, first
	# home 1 in 6 runner rounds, 1.5 pickups on average, ~1.5 distinct tags
	var e: Dictionary = Catalogue.economy()
	var rc: Dictionary = e["round_coins"]
	var runner := float(rc["completed"]) + 0.5 * float(rc["team_win"]) + 0.6 * float(rc["runner_home"]) + float(rc["first_home"]) / 6.0 + 1.5
	var watch := float(rc["completed"]) + 0.5 * float(rc["team_win"]) + 1.5 * float(rc["watch_distinct_tag"]) + 1.5
	var avg := (runner + watch) * 0.5
	var rounds := 1500.0 / avg
	t.check(rounds >= 60.0 and rounds <= 120.0, "Premium (1,500 Coins) in %.0f typical eligible rounds (target 60-120)" % rounds)
	# Season XP from the rounds themselves (unchanged by Pass 8 challenges)
	var base := _base_season_xp()
	t.near(base, 85.75, 0.01, "base Season XP per typical eligible round (docs/ECONOMY.md §3)")
	var to30 := float(Catalogue.season_tiers("s1")[-1]["xp"]) / base
	t.check(to30 >= 70.0 and to30 <= 130.0, "base only: tier 30 in %.0f typical eligible rounds" % to30)


## Base Season XP of a typical eligible round: half as a runner (2.2
## splashes, home 60%), half as Night Watch (1.5 different runners tagged),
## team wins 50% (docs/ECONOMY.md §3).
func _base_season_xp() -> float:
	var sx: Dictionary = Catalogue.economy()["season_xp"]
	var xr := float(sx["completed"]) + 2.2 * float(sx["stamp"]) + 0.6 * float(sx["runner_home"]) + 0.5 * float(sx["team_win"])
	var xw := float(sx["completed"]) + 1.5 * float(sx["watch_distinct_tag"]) + 0.5 * float(sx["team_win"])
	return (xr + xw) * 0.5


## One modelled week: `days` active days of `per_day` eligible, active
## rounds.  A goal counts as completed when the period's expected amount
## (1 active round, 1.85 credits = half 2.2 splashes / half 1.5 different
## tags, 0.5 Round Wins per round) reaches it.  {base, daily, weekly, total}.
func _model_week(days: int, per_day: int) -> Dictionary:
	var per_round := {"active_rounds": 1.0, "credits": (2.2 + 1.5) * 0.5, "round_wins": 0.5}
	var c := ChallengeRules.cfg()
	var daily := 0
	for d in c["daily"]:
		if float(per_round[String(d["metric"])]) * per_day >= float(d["goal"]) - 0.0001:
			daily += int(d["xp"])
	var weekly := 0
	for d in c["weekly"]:
		if float(per_round[String(d["metric"])]) * per_day * days >= float(d["goal"]) - 0.0001:
			weekly += int(d["xp"])
	if days * per_day == 0:
		daily = 0
		weekly = 0
	var base := _base_season_xp() * days * per_day
	return {"base": base, "daily": daily * days, "weekly": weekly, "total": base + daily * days + weekly}


## Pass 8: challenges add Season XP to the same pass (no other currency).
## The documented light / typical / heavy weeks (docs/ECONOMY.md §3, "With
## challenges"), recomputed from the live catalogue; the brief's sample
## week (20 rounds over 5 days) is the typical one.
func test_challenges_accelerate_the_pass_as_documented() -> void:
	t.eq(ChallengeRules.max_xp("daily"), 150, "daily challenges: at most 150 Season XP a day")
	t.eq(ChallengeRules.max_xp("weekly"), 450, "weekly challenges: at most 450 Season XP a week")
	var tier30 := float(Catalogue.season_tiers("s1")[-1]["xp"])
	t.eq(int(tier30), 8300, "the pass and its thresholds are unchanged")
	var light := _model_week(2, 3)
	var typical := _model_week(5, 4)
	var heavy := _model_week(7, 8)
	t.near(float(typical["base"]), 1715.0, 0.5, "typical week: 20 rounds of base XP")
	t.eq(int(typical["daily"]), 750, "typical week: every daily goal on 5 days")
	t.eq(int(typical["weekly"]), 450, "typical week: every weekly goal")
	t.near(float(typical["total"]), 2915.0, 0.5, "typical week: about 2,915 Season XP")
	t.near(tier30 / float(typical["total"]), 2.85, 0.01, "typical: tier 30 in about 2.85 weeks")
	t.near(tier30 / (float(typical["total"]) / 20.0), 56.9, 0.1, "typical: about 57 rounds to tier 30 (97 without challenges)")
	t.near(float(light["total"]), 714.5, 0.5, "light week (2 days x 3 rounds): Night Shift and Team Effort only")
	t.eq(int(light["weekly"]), 0, "light week: no weekly goal")
	t.near(tier30 / float(light["total"]), 11.6, 0.05, "light: about 11.6 weeks (16.1 without challenges)")
	t.near(float(heavy["total"]), 6302.0, 0.5, "heavy week (7 days x 8 rounds)")
	t.near(tier30 / float(heavy["total"]), 1.32, 0.01, "heavy: about 1.3 weeks")
	# challenges accelerate without replacing the base: their share stays under half
	for wk in [light, typical, heavy]:
		var share := (float(wk["daily"]) + float(wk["weekly"])) / float(wk["total"])
		t.check(share < 0.45, "challenges are %.0f%% of a modelled week's Season XP" % (share * 100.0))
	# no round, no challenge XP; challenges give Season XP only
	t.eq(int(_model_week(0, 0)["total"]), 0, "no rounds, nothing")
	for d in ChallengeRules.defs():
		t.check(not (d as Dictionary).has("coins") and String(d["metric"]) in ["active_rounds", "credits", "round_wins"],
			"%s: Season XP from play only (no Coins, no purchase metric)" % d["id"])


func test_legacy_import_is_bounded() -> void:
	t.eq(Economy.legacy_import_amount(345, 10, 0), 345, "a plausible balance imports whole")
	t.eq(Economy.legacy_import_amount(99999, 10, 0), 750, "bounded by what 10 online rounds could earn")
	t.eq(Economy.legacy_import_amount(99999, 1000, 1000), 2000, "hard cap")
	t.eq(Economy.legacy_import_amount(-5, 10, 0), 0, "never negative")
