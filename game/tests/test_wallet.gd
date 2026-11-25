extends RefCounted
## V6 wallet: save migration (twice), the one-time bounded legacy import,
## atomic Coin spends that can't charge twice (lost replies, duplicates),
## offline cached ownership, account changes, service-off honesty, Season
## claims (repeated Claim all, late Premium, duplicate-owned rewards) and
## round settlement (host report + each player's own confirmation,
## cancelled/practice rounds, old-result replay).
var t
var rig


func _rig() -> Variant:
	rig = preload("res://tests/commerce_rig.gd").new(t)
	return rig


func _v3_profile() -> Dictionary:
	return {"version": 3, "uid": "local-1", "name": "Sleepy Otter", "coins": 345, "level": 4, "xp": 120,
		"owned": ["hat:crown", "outfit:frog", "outfit:pj_stripes"],
		"cosmetic": {"schema": 2, "outfit": "frog", "hat": "crown", "color": "plum"},
		"stats": {"online": {"matches": 12}, "practice": {"matches": 3}}, "rewarded": ["m1"], "settings": {}}


func test_save_migration_v3_to_v4_twice() -> void:
	var m1 := Save.migrate(_v3_profile())
	t.eq(int(m1["version"]), Save.VERSION, "migrated to v%d" % Save.VERSION)
	t.eq(int(m1["legacy"]["coins"]), 345, "the pre-V6 balance is frozen for the import")
	t.eq(int(m1["legacy"]["online_rounds"]), 12, "with its round counts (validation)")
	t.eq(m1["owned"], ["hat:crown", "outfit:frog", "outfit:pj"], "pre-V6 unlocks kept (V3 key migration too)")
	t.eq(String(m1["cosmetic"]["outfit"]), "frog", "selected appearance kept")
	t.eq(String(m1["cosmetic"]["color"]), "plum", "selected colour kept")
	t.eq(int(m1["level"]), 4, "lifetime level kept, separate from the Season")
	# migrating the migrated profile changes nothing (no second import record)
	var m2 := Save.migrate(JSON.parse_string(JSON.stringify(m1)))
	t.eq(m2["legacy"], m1["legacy"], "migration twice: identical legacy record")
	t.eq(m2["owned"], m1["owned"], "migration twice: same unlocks")
	# a later balance mirror never feeds back into the legacy record
	m2["coins"] = 99999
	var m3 := Save.migrate(m2)
	t.eq(int(m3["legacy"]["coins"]), 345, "an edited 'coins' field can't grow the import")


func test_legacy_items_stay_owned_offline() -> void:
	await _rig().begin(false, false)
	Save.data = Save.migrate(_v3_profile())
	t.check(Wallet.owns("hat", "crown"), "pre-V6 crown still owned with no service")
	t.check(Wallet.owns("outfit", "frog"), "pre-V6 frog still owned")
	t.check(Wallet.owns("outfit", "pj") and Wallet.owns("hat", "nightcap"), "free base options owned")
	t.check(not Wallet.owns("hat", "headphones"), "never-bought items aren't")
	t.eq(Wallet.balance(), 345, "the pre-V6 balance is shown (on this device)")
	t.check(Wallet.balance_is_device(), "labelled as this device's balance")
	t.eq(Wallet.service_state(), "off", "no service in this build")
	t.check(not bool(Wallet.can_transact()["ok"]), "spending is honestly unavailable")
	var r: Dictionary = await Wallet.spend("hat:headphones")
	t.check(not bool(r["ok"]) and String(r["message"]).contains("game service"), "spend refused with the reason")
	t.check(not Wallet.owns("hat", "headphones"), "nothing granted")
	t.eq(Wallet.balance(), 345, "nothing debited")
	await rig.end()


func test_legacy_import_once_per_account() -> void:
	await _rig().begin()
	Save.data = Save.migrate(_v3_profile())
	await rig.sign_in("T:_alice")
	await rig.until(func() -> bool: return not Wallet.legacy_pending())
	t.eq(String(Wallet.state["legacy_import"]["state"]), "done", "imported once signed in")
	t.eq(Wallet.balance(), 345, "the account balance includes the imported Coins")
	t.check(Wallet.ownership_source("hat:crown") in ["device", "legacy_beta"], "crown owned")
	var pid := Cloud.profile_id()
	t.eq(String((rig.svc.wallet(pid)["entitlements"] as Dictionary).get("hat:crown", {}).get("source", "")), "legacy_beta", "recorded on the account as legacy_beta")
	# the same account from a second device with its own old save: nothing more
	Wallet.state = Wallet.blank_state()
	await Wallet.refresh()
	await rig.until(func() -> bool: return not Wallet.legacy_pending())
	t.eq(Wallet.balance(), 345, "a second import adds nothing (idempotent per account)")
	t.check(bool(Wallet.state["legacy_import"].get("already", false)), "the service said it was already imported")
	await rig.end()


func test_spend_is_atomic_and_never_twice() -> void:
	await _rig().begin()
	await rig.sign_in()
	var pid := Cloud.profile_id()
	rig.svc.grant(pid, 1000)
	await Wallet.refresh()
	t.eq(Wallet.balance(), 1000, "balance from the service")
	var r: Dictionary = await Wallet.spend("outfit:robe")
	t.check(bool(r["ok"]), "bought the robe")
	t.eq(Wallet.balance(), 700, "debited exactly the catalogue price")
	t.check(Wallet.owns("outfit", "robe"), "granted in the same step")
	var again: Dictionary = await Wallet.spend("outfit:robe")
	t.check(not bool(again["ok"]), "an owned item can't be bought again")
	t.eq(Wallet.balance(), 700, "no second charge")
	var short: Dictionary = await Wallet.spend("outfit:frog")
	t.check(bool(short["ok"]), "frog (500) affordable with 700")
	var broke: Dictionary = await Wallet.spend("outfit:duck")
	t.check(not bool(broke["ok"]) and String(broke["message"]).contains("more Coins"), "insufficient: refused with the shortfall")
	t.eq(Wallet.balance(), 200, "never negative")
	await rig.end()


func test_lost_reply_retries_without_double_charge() -> void:
	await _rig().begin()
	await rig.sign_in()
	rig.svc.grant(Cloud.profile_id(), 500)
	await Wallet.refresh()
	rig.svc.drop_reply = true   # the service commits, the reply is lost
	var r: Dictionary = await Wallet.spend("hat:crown")
	t.eq(String(r["state"]), "pending", "no answer: pending, not failed (a timeout isn't a no)")
	t.eq(Wallet.pending_ops(), 1, "the operation stays in the outbox with its key")
	t.check(Wallet.pending_for("hat:crown"), "and blocks a second accidental purchase")
	var dup: Dictionary = await Wallet.spend("hat:crown")
	t.check(not bool(dup["ok"]) and String(dup["state"]) == "pending", "a second tap waits instead of charging again")
	rig.svc.drop_reply = false
	# the app restarts: the outbox is on disk
	Wallet.reload()
	t.eq(Wallet.pending_ops(), 1, "the pending operation survived a restart")
	await Wallet.refresh()
	await rig.until(func() -> bool: return Wallet.pending_ops() == 0)
	t.eq(Wallet.pending_ops(), 0, "retried and answered")
	t.eq(int(rig.svc.wallet(Cloud.profile_id())["balance"]), 500 - 240, "charged exactly once on the service")
	t.eq(Wallet.balance(), 260, "and the app agrees")
	await rig.end()


func test_offline_cached_ownership_and_account_change() -> void:
	await _rig().begin()
	await rig.sign_in("T:_alice")
	var alice := Cloud.profile_id()
	rig.svc.grant(alice, 500)
	await Wallet.refresh()
	await Wallet.spend("outfit:robe")
	t.check(Wallet.owns("outfit", "robe"), "alice owns the robe")
	# offline (no sign-in): the cached snapshot still opens the Locker
	Cloud.token = ""
	Cloud.profile = {}
	Cloud.state = "error"
	t.check(Wallet.owns("outfit", "robe"), "offline: cached ownership still works")
	t.eq(Wallet.balance(), 200, "offline: last verified balance shown")
	t.check(not bool(Wallet.can_transact()["ok"]), "offline: spending unavailable")
	# a different Game Center account signs in on this device
	await rig.sign_in("T:_bob")
	t.check(Cloud.profile_id() != alice, "bob is another profile")
	t.check(not Wallet.owns("outfit", "robe"), "bob doesn't see alice's purchases")
	t.eq(Wallet.balance(), 0, "nor her Coins")
	await rig.end()


func test_outbox_holds_another_profiles_operation() -> void:
	await _rig().begin()
	await rig.sign_in("T:_alice")
	rig.svc.grant(Cloud.profile_id(), 500)
	await Wallet.refresh()
	rig.svc.network_down = true
	var r: Dictionary = await Wallet.spend("hat:crown")
	t.eq(String(r["state"]), "pending", "queued while offline")
	rig.svc.network_down = false
	await rig.sign_in("T:_bob")
	await rig.frames(10)
	t.eq(Wallet.pending_ops(), 1, "alice's spend isn't sent with bob's session")
	t.eq(int(rig.svc.wallet(rig.svc._pid_for("T:_alice"))["balance"]), 500, "alice not charged yet")
	await rig.sign_in("T:_alice")
	await rig.until(func() -> bool: return Wallet.pending_ops() == 0)
	t.eq(int(rig.svc.wallet(Cloud.profile_id())["balance"]), 260, "sent once alice is back")
	await rig.end()


func test_season_claims_idempotent_and_late_premium() -> void:
	await _rig().begin()
	await rig.sign_in()
	var pid := Cloud.profile_id()
	rig.svc.wallet(pid)["season"]["s1"]["xp"] = 450     # tier 3
	rig.svc.grant(pid, 1600)
	await Wallet.refresh()
	t.eq(Wallet.claimable("s1").size(), 2, "free player: two free rewards (tiers 1, 3)")
	var r: Dictionary = await Wallet.claim_all("s1")
	t.check(bool(r["ok"]), "claim all")
	t.eq((r["claimed"] as Array).size(), 2, "both claimed")
	t.check(Wallet.owns_id("card:after_hours"), "tier 1 free name card in the Locker")
	var again: Dictionary = await Wallet.claim_all("s1")
	t.check(not bool(again["ok"]), "repeated Claim all: nothing left")
	t.eq(int(rig.svc.wallet(pid)["balance"]), 1600, "and no Coins granted twice")
	# (build 30) Premium is never sold for Coins
	var p: Dictionary = await Wallet.spend("season:s1:premium")
	t.check(not bool(p["ok"]), "Premium can't be bought with Coins")
	t.eq(Wallet.balance(), 1600, "nothing debited")
	# buying Premium later (from Apple) makes the already-earned Premium rewards claimable
	rig.svc.deliver_premium(pid)
	await Wallet.refresh()
	t.check(Wallet.premium("s1"), "Premium owned")
	t.eq(Wallet.balance(), 1600, "Premium costs no Coins")
	t.eq(Wallet.claimable("s1").size(), 3, "late unlock: Premium tiers 1-3 claimable")
	var pr: Dictionary = await Wallet.claim_all("s1")
	t.eq((pr["claimed"] as Array).size(), 3, "claimed")
	t.eq(Wallet.balance(), 1650, "tier 2 Premium: +50 Coins once")
	t.check(Wallet.owns("outfit", "night_owl") or not Catalogue.has_art("outfit:night_owl"), "Night Owl owned (when its art exists)")
	t.eq(int(Wallet.season_state("s1")["xp"]), 450, "buying never adds Season XP")
	await rig.end()


func test_duplicate_owned_reward_still_claims_once() -> void:
	await _rig().begin()
	await rig.sign_in()
	var pid := Cloud.profile_id()
	rig.svc.wallet(pid)["entitlements"]["card:after_hours"] = {"source": "admin"}
	await Wallet.refresh()
	var r: Dictionary = await Wallet.claim("s1", [{"tier": 1, "track": "free"}])
	t.check(bool(r["ok"]), "claiming a reward you already own succeeds")
	t.check(Wallet.season_state("s1")["claimed"].has("1:free"), "marked claimed")
	t.eq(String(rig.svc.wallet(pid)["entitlements"]["card:after_hours"]["source"]), "admin", "the existing ownership isn't duplicated")
	await rig.end()


## (2.2 (35)) Owner: "the coins you collect in game don't actually go towards
## your overall coins".  A guest's confirmation nearly always reaches the
## service before the host's report: the service answered "pending", paid
## the guest when the report came, and the guest's game never asked again,
## so its balance stayed short (and the results said "pending") until the
## next app launch.  Now the wallet asks again shortly: the Coins land in
## the balance once, in seconds, and the results follow.
func test_guest_paid_after_the_hosts_late_report_without_a_relaunch() -> void:
	await _rig().begin()
	await rig.sign_in("T:_guest")
	var guest := Cloud.profile_id()
	var host: String = rig.svc._pid_for("T:_host")
	var mid := "QWERTY-4-0000abcd"
	var t0 := int(Time.get_unix_time_from_system())
	var offset := {"s": 0}
	Wallet.clock_override = func() -> int: return t0 + int(offset["s"])
	rig.svc.rounds[mid] = {"host": host, "participants": {host: 0, guest: 1}, "report": {}, "acks": {}, "settled": {}}
	App.party_code = "QWERTY"
	var res := _round_results(mid)
	var me: Dictionary = res["players"][1]
	Wallet.settle_round(res, me, false)
	await rig.until(func() -> bool: return Wallet.pending_ops() == 0)
	t.eq(String(Wallet.round_summary(mid)["state"]), "pending", "our confirmation is in, the host's report isn't: pending")
	t.check(Wallet.following().has(mid), "the wallet will ask again")
	t.eq(Wallet.balance(), 0, "nothing paid yet")
	# the host's report arrives (the service pays the confirmed guest then)
	var rows: Array = []
	for r in res["players"]:
		if not bool(r["is_bot"]):
			rows.append({"profile_id": host if String(r["uid"]) == "T:_host" else guest, "slot": int(r["slot"]), "role": int(r["role"]),
				"stamps": int(r["stamps"]), "finished": bool(r["finished"]), "first_home": Economy.first_home(r, res),
				"unique_captures": int(r["unique_captures"]), "coins_picked": int(r["coins_picked"]), "present": true, "away_s": 0.0})
	rig.svc._round_report(host, mid, {"outcome": res["outcome"], "round_time_s": 180.0, "coin_spawns": 8, "players": rows})
	var want := int(Economy.round_coins(me, res)["coins"])
	t.check(int(rig.svc.wallet(guest)["balance"]) == want, "the service paid us when the report came (%d)" % want)
	await rig.frames(5)
	t.eq(Wallet.balance(), 0, "our game doesn't know yet")
	offset["s"] = Wallet.FOLLOW_S[0] + 1
	await rig.until(func() -> bool: return String(Wallet.round_summary(mid)["state"]) == "settled", 240)
	var s := Wallet.round_summary(mid)
	t.eq(String(s["state"]), "settled", "a few seconds later the round is settled on our device (no relaunch)")
	t.eq(int(s["coins"]), want, "with its Coins")
	t.eq(Wallet.balance(), want, "and the balance holds them")
	t.check(int(s["xp_after"]) - int(s["xp_before"]) == int(Economy.round_season_xp(me, res)["xp"]), "and the Season XP")
	t.check(not Wallet.following().has(mid), "the wallet stops asking")
	# the same round again (results reopened, a repeated packet): nothing more
	Wallet.settle_round(res, me, false)
	await Wallet.refresh()
	t.eq(Wallet.balance(), want, "paid once")
	t.eq(int(rig.svc.wallet(guest)["balance"]), want, "on the service too")
	Wallet.clock_override = Callable()
	App.party_code = ""
	await rig.end()


## (2.2 (35)) The host reports every round it registered, one that pays
## nobody (too few players) or that was ended early too: left open on the
## service, it held the party's next round back (registration refused for a
## minute after its start), so the series' next round paid nobody either.
func test_host_closes_unpaid_and_aborted_rounds_on_the_service() -> void:
	await _rig().begin()
	await rig.sign_in("T:_host")
	var host := Cloud.profile_id()
	var hub := LoopbackTransport.Hub.new(3)
	var s := NetSession.new()
	t.add_child(s)
	s.start_host(LoopbackTransport.new(hub, true), "QWERTY", "T:_host", "Host", {}, "any")
	var saved := App.session
	App.session = s
	App.party_code = "QWERTY"
	var solo := _round_results("QWERTY-6-0000abcd")
	(solo["players"] as Array).remove_at(1)
	var gone := _round_results("QWERTY-7-0000abcd")
	for mid in ["QWERTY-6-0000abcd", "QWERTY-7-0000abcd"]:
		rig.svc.rounds[mid] = {"host": host, "participants": {host: 0}, "report": {}, "acks": {}, "settled": {}}
	t.eq(String(Wallet.settle_round(solo, solo["players"][0], false)["state"]), "not_eligible", "you + bots: pays nothing")
	Wallet.round_aborted(gone)
	await rig.until(func() -> bool: return Wallet.pending_ops() == 0)
	t.check(not (rig.svc.rounds["QWERTY-6-0000abcd"]["report"] as Dictionary).is_empty(), "the unpaid round is reported (closed on the service)")
	t.eq(int(rig.svc.rounds["QWERTY-7-0000abcd"]["report"].get("outcome", -1)), TC.Outcome.CANCELLED, "the round ended early is reported cancelled")
	t.eq(Wallet.balance(), 0, "neither pays")
	App.session = saved
	App.party_code = ""
	s.queue_free()
	await rig.end()


## (2.2 (35)) A guest the host knows by another player id than this
## device's own (a host that admitted it through the relay while Game
## Center isn't signed in here) finds its row by its own seat: before, no
## row matched, so the round was neither recorded nor confirmed.
func test_round_row_found_by_seat_when_the_ids_differ() -> void:
	var res := _round_results("QWERTY-5-0000abcd")
	var s := NetSession.new()
	t.add_child(s)
	s.start_offline("someone-else", "Tester", {}, "runner")
	var saved := App.session
	App.session = s
	s.local_slot = 1
	s.roster[1] = {"slot": 1, "uid": "T:_guest", "name": "Guest", "is_bot": false}
	t.eq(App.round_uid(res), "T:_guest", "the uid the host knows us by")
	(res["players"][1] as Dictionary)["uid"] = Save.player_uid()
	t.eq(App.round_uid(res), Save.player_uid(), "our own id first when the row has it")
	App.session = saved
	s.queue_free()


## (2.2 (35)) Between the rounds of a series the results showed the Coins
## and XP a round *would* pay even when it paid nothing (practice, only bots,
## away): "+17 Coins" that never reached the wallet.  Now: added amounts in
## amber, amounts being added muted ("adding…"), a round that pays nothing a
## few words why; each number gives its breakdown when tapped.
func test_between_rounds_rewards_show_only_what_is_paid() -> void:
	var lines := [["Completed the round", 10], ["Coins collected ×3", 3], ["Team win", 4]]
	var xl := [["Completed the round", 50], ["Splashes ×3", 30], ["Made it home", 20], ["Team win", 15]]
	var base := {"coins_collected": 3, "coins_projected": 17, "season_xp_projected": 115, "lines": lines, "season_lines": xl}
	var cases := {
		"CHIPS-1": base.merged({"state": "not_eligible", "reason": "few_humans"}),
		"CHIPS-2": base.merged({"state": "practice"}),
		"CHIPS-3": base.merged({"state": "pending"}),
		"CHIPS-4": base.merged({"state": "settled", "coins": 17, "season_xp": 115}),
	}
	RoundRewards.wallet_override = func(m: String) -> Dictionary: return cases.get(m, {})
	var fly := [App.coin_fly_match, App.coin_fly_pending]
	var r := ResultsScreen.new()
	var chips := {}
	for mid in cases:
		r.results = {"match_id": mid}
		var h := HBoxContainer.new()
		r._fill_chips(h, mid)
		chips[mid] = h
	var no1: HBoxContainer = chips["CHIPS-1"]
	t.check(no1.find_child("TapCoins", true, false) == null and no1.find_child("TapXP", true, false) == null, "bots only: no Coins or XP shown as paid")
	t.check(no1.find_child("NoPay", true, false) != null and (no1.find_child("NoPay", true, false) as Label).text == "Coins and XP need 2+ players", "but why, in a few words")
	t.eq((chips["CHIPS-2"].find_child("NoPay", true, false) as Label).text, "Practice: no Coins or XP", "practice says so")
	var pend: HBoxContainer = chips["CHIPS-3"]
	t.check(pend.find_child("TapCoins", true, false) != null, "being added: the amount shows")
	t.check(String(pend.accessibility_name).contains("being added"), "marked as being added (%s)" % pend.accessibility_name)
	t.check(App.coin_fly_match != "CHIPS-3", "nothing flies into the counter before it is added")
	var paid: HBoxContainer = chips["CHIPS-4"]
	var xp: Control = paid.find_child("TapXP", true, false)
	t.check(xp != null and xp.mouse_filter == Control.MOUSE_FILTER_STOP, "added: +XP, tappable")
	t.eq(String(xp.get_meta(&"breakdown", "")), "XP: Completed the round +50 · Splashes ×3 +30 · Made it home +20 · Team win +15", "its breakdown on a tap")
	t.eq(String((paid.find_child("TapCoins", true, false) as Control).get_meta(&"breakdown", "")),
		"Coins: Completed the round +10 · Coins collected ×3 +3 · Team win +4", "and the Coins' breakdown")
	t.eq([App.coin_fly_match, App.coin_fly_pending], ["CHIPS-4", 17], "added Coins fly into the counter back in the lobby")
	for h in chips.values():
		(h as Node).free()
	r.free()
	RoundRewards.wallet_override = Callable()
	for mid in cases:
		RoundRewards._cache.erase(mid)
		RoundRewards._order.erase(mid)
	App.coin_fly_match = fly[0]
	App.coin_fly_pending = fly[1]


func _round_results(mid: String, outcome: int = TC.Outcome.RUNNERS_WIN) -> Dictionary:
	return {"match_id": mid, "outcome": outcome, "fastest_slot": 0, "round_time": 180.0, "coin_spawns": 8, "players": [
		{"slot": 0, "uid": "T:_host", "role": TC.Role.RUNNER, "stamps": 3, "finished": true, "unique_captures": 0, "coins_picked": 2,
			"present": true, "away_s": 0.0, "is_bot": false},
		{"slot": 1, "uid": "T:_guest", "role": TC.Role.PATROL, "stamps": 0, "finished": false, "unique_captures": 1, "coins_picked": 1,
			"present": true, "away_s": 0.0, "is_bot": false},
		{"slot": 2, "uid": "bot-2", "role": TC.Role.RUNNER, "stamps": 1, "finished": false, "coins_picked": 3, "present": true, "is_bot": true},
	]}


func test_round_settles_once_with_matching_confirmation() -> void:
	await _rig().begin()
	await rig.sign_in("T:_host")
	var host := Cloud.profile_id()
	var guest: String = rig.svc._pid_for("T:_guest")
	var mid := "QWERTY-1-0000abcd"
	# the host registered the round with both admitted players
	rig.svc.rounds[mid] = {"host": host, "participants": {host: 0, guest: 1}, "report": {}, "acks": {}, "settled": {}}
	App.party_code = "QWERTY"
	var res := _round_results(mid)
	var me: Dictionary = res["players"][0]
	# (host reporting is exercised in the service tests; here the double gets it directly)
	rig.svc.rounds[mid]["report"] = {"outcome": res["outcome"], "round_time_s": 180.0, "coin_spawns": 8, "players": [
		{"profile_id": host, "slot": 0, "role": 0, "stamps": 3, "finished": true, "first_home": true, "unique_captures": 0, "coins_picked": 2, "present": true, "away_s": 0.0},
		{"profile_id": guest, "slot": 1, "role": 1, "stamps": 0, "finished": false, "first_home": false, "unique_captures": 1, "coins_picked": 1, "present": true, "away_s": 0.0}]}
	var s1 := Wallet.settle_round(res, me, false)
	t.eq(String(s1["state"]), "pending", "online round with the service: pending")
	t.eq(int(s1["coins_collected"]), 2, "coins collected shown at once")
	await rig.until(func() -> bool: return String(Wallet.round_summary(mid)["state"]) == "settled")
	var s2 := Wallet.round_summary(mid)
	t.eq(String(s2["state"]), "settled", "settled after the service checked the confirmation")
	t.eq(int(s2["coins"]), int(Economy.round_coins(me, res)["coins"]), "Coins as the economy table says")
	t.eq(Wallet.balance(), int(s2["coins"]), "added to the wallet")
	t.eq(int(s2["xp_after"]) - int(s2["xp_before"]), int(Economy.round_season_xp(me, res)["xp"]), "Season XP before/after for the results screen")
	# reopening results / a duplicated results packet: nothing more
	var bal := Wallet.balance()
	Wallet.settle_round(res, me, false)
	await rig.frames(10)
	t.eq(Wallet.balance(), bal, "the same round never pays twice")
	App.party_code = ""
	await rig.end()


func test_mismatched_row_is_not_paid() -> void:
	await _rig().begin()
	await rig.sign_in("T:_host")
	var host := Cloud.profile_id()
	var mid := "QWERTY-2-0000abcd"
	rig.svc.rounds[mid] = {"host": host, "participants": {host: 0}, "report": {"outcome": 1, "round_time_s": 180.0, "coin_spawns": 8,
		"players": [{"profile_id": host, "slot": 0, "role": 0, "stamps": 3, "finished": true, "first_home": true, "unique_captures": 0,
			"coins_picked": 9, "present": true, "away_s": 0.0}]}, "acks": {}, "settled": {}}
	App.party_code = "QWERTY"
	var res := _round_results(mid)
	Wallet.settle_round(res, res["players"][0], false)
	await rig.until(func() -> bool: return String(Wallet.round_summary(mid)["state"]) != "pending")
	t.eq(String(Wallet.round_summary(mid)["state"]), "mismatch", "host reported 9 pickups, the player saw 2: not paid")
	t.eq(Wallet.balance(), 0, "nothing granted")
	App.party_code = ""
	await rig.end()


func test_practice_cancelled_and_service_off_settle_nothing() -> void:
	await _rig().begin(false, false)
	var res := _round_results("P-1")
	var me: Dictionary = res["players"][0]
	t.eq(String(Wallet.settle_round(res, me, true)["state"]), "practice", "practice: isolated")
	t.eq(String(Wallet.settle_round(_round_results("C-1", TC.Outcome.CANCELLED), me, false)["state"]), "cancelled", "cancelled: nothing")
	var off := Wallet.settle_round(_round_results("O-1"), me, false)
	t.eq(String(off["state"]), "no_service", "no service in the build: said honestly")
	t.check(String(off["message"]).contains("weren't added"), "the message says the rewards weren't added")
	t.eq(Wallet.pending_ops(), 0, "nothing queued")
	t.eq(Wallet.balance(), 0, "no Coins")
	var solo := _round_results("S-1")
	(solo["players"] as Array).remove_at(1)
	t.eq(String(Wallet.settle_round(solo, me, false)["reason"]), "few_humans", "you + bots: not eligible")
	await rig.end()


func test_apply_results_routes_to_wallet_and_keeps_lifetime_xp_separate() -> void:
	await _rig().begin(false, false)
	var res := _round_results("ROOM-3-0000aaaa")
	var lv := int(Save.data["level"])
	var xp := int(Save.data["xp"])
	var r := Save.apply_results(res, 0, false, "T:_host")
	t.check(int(r["xp"]) > 0, "lifetime XP from performance")
	t.check(int(Save.data["xp"]) != xp or int(Save.data["level"]) != lv, "lifetime XP applied locally")
	t.eq(String(r["wallet"]["state"]), "no_service", "Coins go through the wallet (none without the service)")
	t.eq(Wallet.balance(), 0, "no local minting")
	t.check(Save.apply_results(res, 0, false, "T:_host").is_empty(), "stats once per match")
	await rig.end()


func test_confirmation_before_registration_is_retried() -> void:
	await _rig().begin()
	await rig.sign_in("T:_host")
	var host := Cloud.profile_id()
	var mid := "QWERTY-3-0000abcd"
	App.party_code = "QWERTY"
	var res := _round_results(mid)
	var me: Dictionary = res["players"][0]
	var t0 := int(Time.get_unix_time_from_system())
	var offset := {"s": 0}
	Wallet.clock_override = func() -> int: return t0 + int(offset["s"])
	# the guest's game confirms before the host's registration reached the service
	rig.svc.rounds.erase(mid)
	Wallet.settle_round(res, me, false)
	await rig.frames(10)
	t.eq(Wallet.pending_ops(), 1, "an 'unknown round' confirmation stays queued (not taken as final)")
	t.eq(String(Wallet.round_summary(mid)["state"]), "pending", "still pending")
	rig.svc.rounds[mid] = {"host": host, "participants": {host: 0}, "report": {"outcome": 1, "round_time_s": 180.0, "coin_spawns": 8,
		"players": [{"profile_id": host, "slot": 0, "role": 0, "stamps": 3, "finished": true, "first_home": true, "unique_captures": 0,
			"coins_picked": 2, "present": true, "away_s": 0.0}]}, "acks": {}, "settled": {}}
	Wallet._pump()
	await rig.frames(5)
	t.eq(Wallet.pending_ops(), 1, "not hammered: it waits a minute")
	offset["s"] = 61
	Wallet._pump()
	await rig.until(func() -> bool: return String(Wallet.round_summary(mid)["state"]) == "settled")
	t.eq(String(Wallet.round_summary(mid)["state"]), "settled", "then it settles once the round is known")
	Wallet.clock_override = Callable()
	App.party_code = ""
	await rig.end()
