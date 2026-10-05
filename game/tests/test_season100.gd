extends RefCounted
## Pass 9: Season 1 · After Hours from 30 to 100 tiers (docs/pass9/season.md)
## through the game's real wallet and Season Pass, against the test-double
## service (src/dev/fake_commerce_service.gd, which follows
## service/src/commerce.js; the service's own tests are
## service/test/season.test.mjs):
##  - migration: a 30-tier-era account (XP past the old cap, every old cell
##    claimed, Premium, Coins) keeps everything; its tier is recomputed;
##    only the newly reached rewards become claimable, once;
##  - an old cached wallet (catalogue version 2) is read safely offline;
##  - tier 50 / tier 100: Premium alone never unlocks an unearned tier, XP
##    alone never grants a Premium reward;
##  - idempotent claims: a lost reply, offline and back, a reinstall or a
##    second device, a whole 100-tier Claim all;
##  - catalogue mismatch: an older (30-tier) service, a changed reward;
##  - the pass UI: the navigation row and milestone shortcuts on the iPhone
##    SE, 844×390, 926×428 and iPad; progress runs; the featured skins'
##    preview (real art when present, a neutral state when not); one Claim;
##    finger scrolling; Reduced Motion; Season tier kept apart from the
##    lifetime level.
var t
var rig
var _saved := {}

## px size, point scale, safe insets in points (left, top, right, bottom)
const DEVICES := {
	"se_667x375": [Vector2i(1334, 750), 2.0, Rect2(0, 0, 0, 0)],
	"p14_844x390": [Vector2i(2532, 1170), 3.0, Rect2(47, 0, 47, 21)],
	"max_926x428": [Vector2i(2778, 1284), 3.0, Rect2(47, 0, 47, 21)],
	"ipad_1024x768": [Vector2i(2048, 1536), 2.0, Rect2(0, 24, 0, 20)],
}

const V2_TABLE := "res://tests/data/season_s1_v2.json"


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


func _begin(with_service: bool = true) -> void:
	rig = preload("res://tests/commerce_rig.gd").new(t)
	await rig.begin(with_service, with_service)
	if with_service:
		await rig.sign_in()
	_saved = {"emulate": Input.emulate_touch_from_mouse, "device": Controls.device, "size": t.get_tree().root.size,
		"emu": UIKit.emulation.duplicate(), "rm": Save.get_setting("reduced_motion", false)}
	Input.emulate_touch_from_mouse = true
	Controls.device = "touch"
	Save.data["onboarded"] = true
	for c in t.get_tree().root.get_children():
		if c is BootCurtain:
			c.queue_free()
	await _frames(2)


func _end() -> void:
	Input.emulate_touch_from_mouse = _saved["emulate"]
	Controls.device = _saved["device"]
	UIKit.emulation = _saved["emu"]
	t.get_tree().root.size = _saved["size"]
	Save.set_setting("reduced_motion", _saved["rm"])
	await rig.end()


func _device(key: String) -> void:
	var d: Array = DEVICES[key]
	UIKit.emulation = {"scale": float(d[1]), "safe": d[2]}
	t.get_tree().root.size = d[0]
	await _frames(3)


func _safe() -> Rect2:
	var vp: Viewport = t.get_viewport()
	return UIKit.safe_rect(vp, vp.get_visible_rect().size)


func _inside(inner: Rect2, outer: Rect2) -> bool:
	return outer.grow(0.6).encloses(inner)


func _v2() -> Dictionary:
	var f := FileAccess.open(V2_TABLE, FileAccess.READ)
	var d: Variant = JSON.parse_string(f.get_as_text()) if f else {}
	return d if d is Dictionary else {}


## The service wallet as a version 2 (30-tier) service left it: `xp`
## recorded, Premium, every reward of tiers 1-`upto` claimed and owned
## (past 30: as the current service would have left it).
func _old_account(pid: String, xp: int, premium: bool, upto: int = 30) -> void:
	var w: Dictionary = rig.svc.wallet(pid)
	var s1: Dictionary = w["season"]["s1"]
	s1["xp"] = xp
	s1["premium"] = premium
	if premium:
		w["entitlements"]["season:s1:premium"] = {"source": "coin_purchase"}
	var claimed: Array = []
	for tr in (_v2()["tiers"] as Array) + Catalogue.season_tiers("s1").slice(30):
		if int(tr["tier"]) > upto:
			break
		for track in ["free", "premium"]:
			var r: Variant = tr[track]
			if not (r is Dictionary) or (track == "premium" and not premium):
				continue
			claimed.append("%d:%s" % [int(tr["tier"]), track])
			if (r as Dictionary).has("item"):
				w["entitlements"][String(r["item"])] = {"source": "season"}
	s1["claimed"] = claimed


func _keys(list: Array) -> Array:
	return list.map(func(c: Dictionary) -> String: return "%d:%s" % [int(c["tier"]), String(c["track"])])


# ------------------------------------------------------------------ migration
func test_a_30_tier_account_keeps_everything_and_gets_only_new_rewards() -> void:
	await _begin()
	var pid := Cloud.profile_id()
	_old_account(pid, 12000, true)        # 3,700 Season XP past the old last tier
	rig.svc.grant(pid, 700)
	await Wallet.refresh()
	var st := Wallet.season_state("s1")
	t.eq(int(st["xp"]), 12000, "the recorded Season XP, including what was earned past tier 30")
	t.eq(Economy.tier_for_xp("s1", int(st["xp"])), 40, "the tier is recomputed with the 100-tier table (tier 40 at 11,800)")
	t.check(bool(st["premium"]), "Premium kept")
	t.eq((st["claimed"] as Dictionary).size(), 45, "every old claim kept")
	t.eq(int(st["service_tiers"]), 100, "the current service grants every tier")
	t.eq(Wallet.balance(), 700, "Coins kept")
	t.eq(_keys(Wallet.claimable("s1")), ["35:free", "35:premium", "40:free", "40:premium"], "only the newly reached rewards: nothing from 1-30 again")
	t.check(Wallet.owns_id("outfit:library_cardigan") and Wallet.owns_id("badge:s1_finisher"), "the tier 30 rewards stay owned (nothing clawed back)")
	var r: Dictionary = await Wallet.claim_all("s1")
	t.check(bool(r["ok"]), "Claim all")
	t.eq((r["claimed"] as Array).size(), 4, "four rewards")
	t.eq(Wallet.balance(), 700 + 50 + 75, "tier 35's Coins once")
	t.check(Wallet.owns_id("card:finish_line") and Wallet.owns_id("badge:big_dive"), "tier 40's name card and badge")
	var again: Dictionary = await Wallet.claim("s1", [{"tier": 30, "track": "premium"}, {"tier": 35, "track": "free"}])
	t.check(bool(again["ok"]) and (again["claimed"] as Array).is_empty(), "claiming old or done cells again grants nothing")
	t.eq(String(again["message"]), "", "and needs no warning (already claimed)")
	t.eq(Wallet.balance(), 825, "no second Coins")
	t.eq(int(rig.svc.wallet(pid)["season"]["s1"]["xp"]), 12000, "no XP invented or removed")
	await _end()


## The wallet cache an older game wrote (catalogue version 2, no "tiers")
## loads, and offline the new game reads it with the 100-tier table without
## offering claims the old service couldn't grant.
func test_an_old_cached_wallet_is_read_safely() -> void:
	await _begin(false)
	var cached := Wallet.blank_state()
	cached["account"] = {"profile_id": "p_old", "environment": "sandbox", "balance": 320, "revision": 41, "debt": 0,
		"app_account_token": "00000000-0000-4000-8000-000000000001", "entitlements": {"season:s1:premium": {"source": "coin_purchase", "revoked": false}},
		"season": {"s1": {"xp": 9000, "premium": true, "claimed": ["1:free", "1:premium", "30:premium"]}}, "synced_at": 1, "catalogue_version": 2}
	var f := FileAccess.open(Wallet.path, FileAccess.WRITE)
	f.store_string(JSON.stringify(cached))
	f.close()
	Wallet.reload()
	Cloud.state = "error"     # configured, offline
	var st := Wallet.season_state("s1")
	t.eq(int(st["xp"]), 9000, "cached Season XP read")
	t.eq(Economy.tier_for_xp("s1", 9000), 32, "shown as tier 32 with the new table (9,000 = tier 32)")
	t.eq(int(st["service_tiers"]), 30, "that snapshot came from a 30-tier (version 2) service")
	t.check(Wallet.claimable("s1").all(func(c: Dictionary) -> bool: return int(c["tier"]) <= 30), "nothing past tier 30 offered from it")
	t.check((st["claimed"] as Dictionary).has("30:premium"), "claims kept")
	await _end()


# ------------------------------------------------------------------ gates
func test_tier_50_and_100_need_the_tier_and_premium() -> void:
	await _begin()
	var pid := Cloud.profile_id()
	var w: Dictionary = rig.svc.wallet(pid)
	w["season"]["s1"]["premium"] = true
	w["entitlements"]["season:s1:premium"] = {"source": "coin_purchase"}
	w["season"]["s1"]["xp"] = Economy.tier_xp("s1", 50) - 1
	await Wallet.refresh()
	t.check(not _keys(Wallet.claimable("s1")).has("50:premium"), "Premium, one XP short: Record Breaker not claimable")
	var r: Dictionary = await Wallet.claim("s1", [{"tier": 50, "track": "premium"}, {"tier": 100, "track": "premium"}])
	t.eq((r["claimed"] as Array).size(), 0, "a forced claim grants nothing (the service checks)")
	t.eq((r["skipped"] as Array).map(func(s: Dictionary) -> String: return String(s["reason"])), ["locked", "locked"], "and says why")
	t.check(not Wallet.owns_id("outfit:record_breaker") and not Wallet.owns_id("outfit:dr_doom"), "not granted")
	w["season"]["s1"]["xp"] = Economy.tier_xp("s1", 50)
	await Wallet.refresh()
	r = await Wallet.claim("s1", [{"tier": 50, "track": "premium"}])
	t.eq(_keys(r["claimed"]), ["50:premium"], "exactly at tier 50: granted")
	t.check(Wallet.owns_id("outfit:record_breaker"), "Record Breaker owned (shown in the Locker once its art is in the build)")
	# XP alone: a free player far past tier 100
	await rig.sign_in("T:_free")
	var fpid := Cloud.profile_id()
	rig.svc.wallet(fpid)["season"]["s1"]["xp"] = 40000
	await Wallet.refresh()
	t.eq(Economy.tier_for_xp("s1", 40000), 100, "tier 100, nothing beyond")
	var keys := _keys(Wallet.claimable("s1"))
	t.check(keys.has("100:free") and not keys.has("100:premium") and not keys.has("50:premium"), "free track only without Premium")
	r = await Wallet.claim("s1", [{"tier": 100, "track": "premium"}, {"tier": 100, "track": "free"}])
	t.eq(_keys(r["claimed"]), ["100:free"], "the tier-100 completion badge, not Dr. Doom")
	t.eq((r["skipped"] as Array)[0]["reason"], "premium_required", "Dr. Doom needs Premium")
	t.check(Wallet.owns_id("badge:s1_legend") and not Wallet.owns_id("outfit:dr_doom"), "badge yes, skin no")
	await _end()


# ------------------------------------------------------------------ idempotency
func test_claims_survive_lost_replies_offline_reinstall_and_a_second_device() -> void:
	await _begin()
	var pid := Cloud.profile_id()
	_old_account(pid, Economy.tier_xp("s1", 50), true, 45)
	await Wallet.refresh()
	t.eq(_keys(Wallet.claimable("s1")), ["50:free", "50:premium"], "tier 50 earned")
	# the service grants, the reply is lost
	rig.svc.drop_reply = true
	var r: Dictionary = await Wallet.claim("s1", [{"tier": 50, "track": "premium"}])
	t.eq(String(r["state"]), "pending", "no answer: pending (a timeout isn't a no)")
	t.check(Wallet.claim_pending("s1", 50, "premium"), "the claim waits in the outbox with its key")
	t.check(not _keys(Wallet.claimable("s1")).has("50:premium"), "never offered (or queued) twice meanwhile")
	rig.svc.drop_reply = false
	Wallet.reload()     # the app restarts: the outbox is on disk
	t.check(Wallet.claim_pending("s1", 50, "premium"), "the claim survived the restart")
	await Wallet.refresh()
	await rig.until(func() -> bool: return Wallet.pending_ops() == 0)
	t.check(Wallet.season_state("s1")["claimed"].has("50:premium"), "claimed")
	t.eq(int(rig.svc.wallet(pid)["season"]["s1"]["claimed"].count("50:premium")), 1, "once on the service")
	# offline: queued, then sent when the network is back
	rig.svc.network_down = true
	r = await Wallet.claim("s1", [{"tier": 50, "track": "free"}])
	t.eq(String(r["state"]), "pending", "offline: pending")
	rig.svc.network_down = false
	await Wallet.refresh()
	await rig.until(func() -> bool: return Wallet.pending_ops() == 0)
	t.check(Wallet.owns_id("badge:record_pace"), "the badge arrives once the claim is sent")
	# a reinstall / second device: no local state, the snapshot says it all
	Wallet.reset_local()
	await Wallet.refresh()
	t.check(Wallet.season_state("s1")["claimed"].has("50:premium") and Wallet.owns_id("outfit:record_breaker"), "restored from the account")
	t.eq(Wallet.claimable("s1").size(), 0, "nothing to claim again on the new device")
	var dup: Dictionary = await Wallet.claim("s1", [{"tier": 50, "track": "premium"}])
	t.check(bool(dup["ok"]) and (dup["claimed"] as Array).is_empty(), "a stale second device claiming again: nothing granted")
	t.eq(String((dup["skipped"] as Array)[0]["reason"]), "already_claimed", "the service answers already claimed")
	await _end()


func test_a_whole_100_tier_claim_all_is_sent_in_batches_and_grants_once() -> void:
	await _begin()
	var pid := Cloud.profile_id()
	var w: Dictionary = rig.svc.wallet(pid)
	w["season"]["s1"]["xp"] = 33000
	w["season"]["s1"]["premium"] = true
	w["entitlements"]["season:s1:premium"] = {"source": "coin_purchase"}
	await Wallet.refresh()
	var n := Wallet.claimable("s1").size()
	t.eq(n, 15 + 14 + 30 + 14, "every reward of the season")
	var calls0: int = rig.svc.calls.size()
	var r: Dictionary = await Wallet.claim_all("s1")
	t.check(bool(r["ok"]), "Claim all")
	t.eq((r["claimed"] as Array).size(), n, "everything claimed")
	var sent: int = rig.svc.calls.slice(calls0).filter(func(c: Array) -> bool: return String(c[1]).ends_with("/claim")).size()
	t.eq(sent, ceili(float(n) / float(Wallet.CLAIM_BATCH)), "in batches an older service can answer (60 cells each)")
	t.eq(Wallet.balance(), Economy.season_coin_total("s1", "free") + Economy.season_coin_total("s1", "premium"), "every Coin reward once")
	t.eq(Wallet.claimable("s1").size(), 0, "nothing left")
	await _end()


# ------------------------------------------------------------------ mismatch
func test_an_older_service_and_a_changed_reward_never_mis_grant() -> void:
	await _begin()
	var pid := Cloud.profile_id()
	rig.svc.legacy_tiers = 30          # a service still on catalogue version 2
	_old_account(pid, Economy.tier_xp("s1", 52), true, 30)
	await Wallet.refresh()
	t.eq(int(Wallet.season_state("s1")["service_tiers"]), 30, "known from its catalogue version (no 'tiers' in its snapshot)")
	t.eq(Wallet.claimable("s1").size(), 0, "tiers 31-100 aren't offered while the service can't grant them")
	App.goto(SeasonScreen)
	await _frames(6)
	var sp := App.screen as SeasonScreen
	t.eq(sp.display_state(50, "premium"), "service_update", "Record Breaker shows earned, waiting for the service")
	sp.focus(50, "premium")
	t.check((sp._d["action"] as Button).disabled and (sp._d["reason"] as Label).text.contains("hasn't been updated"), "no Claim that would do nothing; the reason says why")
	t.eq(sp.claim_all_btn.text, "Nothing to claim", "Claim all counts what the service can grant")
	# forced anyway (a stale screen): the old service grants nothing and says
	# nothing; the game explains
	var r: Dictionary = await Wallet.claim("s1", [{"tier": 35, "track": "free"}])
	t.eq((r["claimed"] as Array).size(), 0, "nothing granted by the old service")
	t.check(String(r["message"]).contains("doesn't have this tier"), "an honest message: %s" % r["message"])
	t.eq(Wallet.balance(), 0, "no Coins")
	# the service updated: everything earned becomes claimable
	rig.svc.legacy_tiers = 0
	await Wallet.refresh()
	t.eq(int(Wallet.season_state("s1")["service_tiers"]), 100, "the service now reports 100 tiers")
	t.check(_keys(Wallet.claimable("s1")).has("50:premium"), "Record Breaker claimable")
	# a cell whose reward differs on the service: nothing granted, explained
	rig.svc.reward_override = {"35:premium": "coins:500"}
	r = await Wallet.claim("s1", [{"tier": 35, "track": "premium"}])
	t.eq((r["claimed"] as Array).size(), 0, "the game showed 75 Coins: the service grants nothing else")
	t.check(String(r["message"]).contains("different reward"), "explained: %s" % r["message"])
	t.eq(Wallet.balance(), 0, "no Coins")
	# an older game (no reward names, its own 30-tier Claim all) against the
	# current service: this table's tier 1-30 rewards, identical to its own
	rig.svc.reward_override = {}
	var old_body := {"claims": []}
	for tier in range(1, 31):
		for track in ["free", "premium"]:
			old_body["claims"].append({"tier": tier, "track": track})
	rig.svc.wallet(pid)["season"]["s1"]["claimed"] = []
	var reply: Dictionary = rig.svc._claim(pid, "s1", old_body)
	var got: Array = reply["body"]["claimed"]
	t.eq(got.size(), 45, "every tier 1-30 reward")
	var v2: Array = _v2()["tiers"]
	t.check(got.all(func(c: Dictionary) -> bool: return String(c["reward"]) == Economy.reward_key(v2[int(c["tier"]) - 1][String(c["track"])])),
		"each the reward the old game showed")
	await _end()


# ------------------------------------------------------------------ UI
func test_navigation_and_milestones_fit_every_device() -> void:
	await _begin()
	var pid := Cloud.profile_id()
	_old_account(pid, 13000, true, 43)     # tier 43, inside the 41-44 progress run
	rig.svc.wallet(pid)["season"]["s1"]["claimed"].erase("40:premium")
	await Wallet.refresh()
	var report: Array = []
	for key in DEVICES:
		await _device(key)
		App.goto(SeasonScreen)
		await _frames(8)
		var sp := App.screen as SeasonScreen
		var safe := _safe()
		var panel := sp.track_panel.get_global_rect()
		var tm := UIKit.touch_min()
		t.check(_inside(sp.nav_row.get_global_rect(), panel) and _inside(sp.nav_row.get_global_rect(), safe), "%s: the navigation row inside the track panel and the safe area" % key)
		var chips: Array = [sp.now_chip, sp.next_chip]
		for m in sp.milestone_chips:
			chips.append(sp.milestone_chips[m])
		t.eq(sp.milestone_chips.keys(), [30, 50, 100], "%s: milestone shortcuts 30, 50, 100" % key)
		var prev_end := -INF
		for c in chips:
			var r := (c as Control).get_global_rect()
			t.check(r.size.y >= tm - 0.5 and r.size.x >= tm - 0.5, "%s: %s is a whole 44 pt target" % [key, c.name])
			t.check(_inside(r, sp.nav_row.get_global_rect().grow(1.0)), "%s: %s inside the row" % [key, c.name])
			t.check(r.position.x >= prev_end - 0.5, "%s: %s doesn't overlap its neighbour" % [key, c.name])
			prev_end = r.end.x
			for l in [c.top_l, c.main_l]:
				t.check(UIKit.v7_text_width(l, (l as Label).text) <= (l as Control).size.x + 1.0, "%s: '%s' whole" % [key, (l as Label).text])
		t.eq(sp.now_chip.main_l.text, "Tier 43", "%s: you're at Tier 43" % key)
		t.eq(sp.next_chip.main_l.text, "Tier 45 · 550 XP", "%s: the next reward and its XP" % key)
		# jumps: current (a progress run), next reward, 50, 100 (and back)
		for spec in [["now", 43, "progress"], ["next", 45, "free"], [50, 50, "premium"], [100, 100, "premium"], [30, 30, "free"]]:
			if spec[0] is String and spec[0] == "now":
				sp.jump_current()
			elif spec[0] is String:
				sp.jump_next_reward()
			else:
				sp.jump_to(int(spec[0]))
			await _frames(30)
			t.eq([sp.focus_tier, sp.focus_track], [spec[1], spec[2]], "%s: jump %s" % [key, spec[0]])
			var col: Control = sp.columns[int(spec[1])]
			var track := sp.track_scroll.get_global_rect()
			t.check(track.grow(0.5).encloses(col.get_global_rect()), "%s: tier %d's column scrolled into view" % [key, spec[1]])
			t.check(_inside((sp._d["action"] as Control).get_global_rect(), safe) or not (sp._d["action"] as Control).visible, "%s: the action on screen" % key)
			t.check(_inside(sp.detail_panel.get_global_rect(), safe), "%s: the side panel inside the safe area" % key)
			# the lock reason / state is wholly in view without scrolling the detail
			var sl := sp._d["state"] as Control
			var info := (sp._d["scroll"] as Control).get_global_rect()
			t.check(info.grow(1.0).encloses(sl.get_global_rect()), "%s: tier %d's state whole in view (%s in %s)" % [key, spec[1], sl.get_global_rect(), info])
		# both rows whole, cells full targets
		var tr := sp.track_scroll.get_global_rect()
		var hbar := sp.track_scroll.get_h_scroll_bar().get_combined_minimum_size().y
		for c in sp.cells:
			var r: Rect2 = (c as Control).get_global_rect()
			if r.end.x <= tr.position.x or r.position.x >= tr.end.x:
				continue
			t.check(r.position.y >= tr.position.y - 0.5 and r.end.y <= tr.end.y - hbar + 0.5 and r.end.y <= safe.end.y + 0.5, "%s: %s cell whole" % [key, c.track])
			t.check(r.size.y >= tm - 0.5 and r.size.x >= tm - 0.5, "%s: a cell is a full target" % key)
		for run in sp.runs:
			var rr: Rect2 = (run as Control).get_global_rect()
			if rr.end.x > tr.position.x and rr.position.x < tr.end.x:
				t.check(rr.size.x >= tm - 0.5 and rr.end.y <= safe.end.y + 0.5, "%s: a progress run is a whole target" % key)
		# one claim action on screen: Claim all in the header, Claim in the detail
		sp.jump_to(40)
		await _frames(30)
		sp.focus(40, "premium")
		await _frames(2)
		var claims := sp.find_children("*", "Button", true, false).filter(func(b: Button) -> bool:
			return b.is_visible_in_tree() and (b.text.begins_with("Claim") or String(b.accessibility_name).contains("Claim")))
		t.eq(claims.size(), 2, "%s: Claim all and the one Claim (no duplicates): %s" % [key, claims.map(func(b: Button) -> String: return b.name)])
		report.append("%s: nav %s, chips %s, cell %s" % [key, sp.nav_row.get_global_rect(), chips.map(func(c: Control) -> int: return int(c.size.x)),
			(sp.cells[0] as Control).size])
	for line in report:
		print("[season100 nav] " + line)
	await _end()


func test_progress_runs_featured_preview_and_claim_from_the_pass() -> void:
	await _begin()
	var pid := Cloud.profile_id()
	_old_account(pid, Economy.tier_xp("s1", 52), true, 45)
	await Wallet.refresh()
	await _device("se_667x375")
	App.goto(SeasonScreen)
	await _frames(8)
	var sp := App.screen as SeasonScreen
	t.eq(sp.runs.size(), 14, "14 progress-run columns")
	t.eq(sp.cells.size(), 88, "44 reward tiers x 2 cells (not 100 x 2)")
	var run := sp.run_of(52)
	t.eq([run.first, run.last], [51, 54], "tier 52 is inside the 51-54 run")
	t.check(String(run.accessibility_name).contains("no reward") and String(run.accessibility_name).contains("Tier 52"), "the run says so: %s" % run.accessibility_name)
	sp._on_run(51)
	await _frames(2)
	t.eq([sp.focus_tier, sp.focus_track], [52, "progress"], "a tap shows the run (your tier inside it)")
	t.check(UIKit.face_of(run).selected, "the run is selected")
	t.check((sp._d["state"] as Label).text.contains("Tier 55") and (sp._d["state"] as Label).text.contains("1,050 more Season XP"), "what it leads to and the XP: %s" % (sp._d["state"] as Label).text)
	t.eq((sp._d["action"] as Button).text, "Show Tier 55", "it offers the next reward")
	sp._on_detail_action()
	await _frames(30)
	t.eq(sp.focus_tier, 55, "and goes there")
	# the featured skins (art from the SKINS9 stream)
	for spec in [[50, "outfit:record_breaker", "The clock has a new problem."], [100, "outfit:dr_doom", "Office hours are over. His rounds aren't."]]:
		sp.jump_to(int(spec[0]))
		await _frames(30)
		var id := String(spec[1])
		t.eq([sp.focus_tier, sp.focus_track], [spec[0], "premium"], "tier %d shows its skin" % spec[0])
		t.eq((sp._d["name"] as Label).text, Catalogue.display_name(id), "named")
		t.eq((sp._d["blurb"] as Label).text, String(spec[2]), "its description")
		t.check((sp._d["includes"] as Label).text.begins_with("Includes: Signature"), "what it includes")
		var chip: SeasonScreen.NavChip = sp.milestone_chips[int(spec[0])]
		t.eq(chip.skin, id, "the milestone chip features the skin")
		if Catalogue.has_art(id):
			t.check(is_instance_valid(sp._preview) and sp._preview.visible and sp._preview_skin == id, "art in the build: the live preview turns the real skin")
			t.eq((sp._d["note"] as Label).text, "", "no missing-art note")
		else:
			t.eq((sp._d["note"] as Label).text, "Preview not available in this build.", "art not in this build (SKINS9 not merged): said plainly")
			t.check((sp._d["art"] as Control).visible and not (is_instance_valid(sp._preview) and sp._preview.visible), "a neutral picture, no fake preview")
			t.check(chip.tex == null, "the chip shows a neutral head")
	t.eq(sp.display_state(50, "premium"), "claimable", "tier 52 with Premium: Record Breaker claimable")
	t.check((sp._d["state"] as Label).visible, "state shown")
	sp.jump_to(50)
	await _frames(30)
	sp._on_detail_action()
	await rig.until(func() -> bool: return sp.display_state(50, "premium") == "claimed")
	t.check(Wallet.owns_id("outfit:record_breaker"), "claimed from the pass")
	t.eq((sp._d["action"] as Button).text, "Wear it in the Locker", "then it points to the Locker")
	# Reduced Motion: jumps land at once and the preview doesn't turn
	Save.set_setting("reduced_motion", true)
	sp.track_scroll.scroll_horizontal = 0
	sp.jump_to(100)
	await _frames(3)
	var want := sp.track_scroll.scroll_horizontal
	await _frames(20)
	t.eq(sp.track_scroll.scroll_horizontal, want, "Reduced Motion: no glide, the jump lands at once")
	t.check(sp.track_scroll.scroll_horizontal > 0, "and it did scroll")
	Save.set_setting("reduced_motion", false)
	await _end()


func test_finger_swipe_on_a_progress_run_scrolls_and_never_selects() -> void:
	await _begin()
	var pid := Cloud.profile_id()
	_old_account(pid, 13000, true, 45)
	await Wallet.refresh()
	await _device("p14_844x390")
	App.goto(SeasonScreen)
	await _frames(8)
	var sp := App.screen as SeasonScreen
	sp.focus(45, "free")
	await sp._scroll_to(43)
	await _frames(4)
	var run := sp.run_of(43)
	var start := run.get_global_rect().get_center()
	var before := sp.track_scroll.scroll_horizontal
	_press(start, true)
	await _move(start, start + Vector2(-300, 3), 12)
	_press(start + Vector2(-300, 3), false)
	await _frames(25)
	t.check(sp.track_scroll.scroll_horizontal > before + 60, "the swipe scrolled the track (%d -> %d)" % [before, sp.track_scroll.scroll_horizontal])
	t.eq([sp.focus_tier, sp.focus_track], [45, "free"], "and selected nothing")
	await _end()


func test_season_tier_stays_apart_from_the_lifetime_level() -> void:
	await _begin()
	var pid := Cloud.profile_id()
	Save.data["level"] = 6
	rig.svc.wallet(pid)["season"]["s1"]["xp"] = 32800
	await Wallet.refresh()
	App.goto(SeasonScreen)
	await _frames(6)
	var sp := App.screen as SeasonScreen
	t.eq(sp.tier_lbl.text, "Tier 100 / 100", "the pass header shows the Season tier")
	t.eq(sp.tier_lbl.accessibility_name, "Season Pass tier 100 of 100", "named as the Season Pass tier")
	t.check(sp.now_chip.accessibility_name.contains("Season Pass Tier 100"), "the navigation too")
	t.eq(int(Save.data["level"]), 6, "the lifetime level is untouched by Season XP")
	# a round's summary reports Season tiers, never the lifetime level
	var s := Wallet.round_summary("none")
	t.check(not s.has("level"), "the wallet's round summary has no lifetime level")
	await _end()


func _px(p: Vector2) -> Vector2:
	return t.get_tree().root.get_final_transform() * p


func _press(at: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = _px(at)
	e.global_position = e.position
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	t.get_viewport().push_input(e)


func _move(from: Vector2, to: Vector2, steps: int) -> void:
	var prev := from
	for i in steps:
		var p := from.lerp(to, float(i + 1) / steps)
		var e := InputEventMouseMotion.new()
		e.position = _px(p)
		e.global_position = e.position
		e.relative = _px(p) - _px(prev)
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
		t.get_viewport().push_input(e)
		prev = p
		await t.get_tree().process_frame


func test_the_shop_never_advertises_100_rewards() -> void:
	var line := ShopScreen.premium_summary("s1")
	t.check(line.begins_with("44 Premium rewards over 100 tiers"), "the Shop counts the real rewards: %s" % line)
	t.check(line.contains("5 outfits") and line.contains("1,125 Coins"), "with the real mix")
	t.check(not line.contains("100 rewards") and not line.contains("100 Premium"), "never 100 rewards")


## The featured-skin code path with art present, exercised with an outfit
## whose art is in every build (Glow Jogger, Premium 15) standing in for the
## two skins until the skins workstream's art merges: the milestone chip
## asks Portraits for the skin's face, the detail turns the real skin on a
## live runner, and Reduced Motion holds it still.
func test_featured_preview_renders_the_real_art_when_present() -> void:
	await _begin()
	var season: Dictionary = Catalogue.season("s1")
	var saved := {"featured": season["featured"].duplicate(), "milestones": season["milestones"].duplicate()}
	season["featured"] = [15, 50, 100]
	season["milestones"] = [15, 50, 100]
	rig.svc.wallet(Cloud.profile_id())["season"]["s1"]["xp"] = 3400
	await Wallet.refresh()
	await _device("p14_844x390")
	App.goto(SeasonScreen)
	await _frames(8)
	var sp := App.screen as SeasonScreen
	var chip: SeasonScreen.NavChip = sp.milestone_chips[15]
	t.eq(chip.skin, "outfit:glow_jogger", "the chip features the tier's skin")
	t.check(chip.pic_key != "", "and asked Portraits for its face (the art exists)")
	sp.jump_to(15)
	await _frames(30)
	t.eq([sp.focus_tier, sp.focus_track], [15, "premium"], "the featured cell")
	t.check(is_instance_valid(sp._preview) and sp._preview.visible and not (sp._d["art"] as Control).visible, "a live preview instead of the static picture")
	t.eq(sp._preview_skin, "outfit:glow_jogger", "turning the featured skin")
	t.eq(String(sp._preview_view.cosmetic.get("outfit", "")), "glow_jogger", "on the real character")
	t.eq((sp._d["note"] as Label).text, "", "no missing-art note")
	var turn0 := sp._turn
	await _frames(20)
	t.check(sp._turn > turn0, "it turns slowly")
	Save.set_setting("reduced_motion", true)
	var turn1 := sp._turn
	await _frames(20)
	t.eq(sp._turn, turn1, "Reduced Motion: it holds still")
	Save.set_setting("reduced_motion", false)
	# an ordinary reward after it: the preview gives the runner back
	sp.focus(14, "premium")
	await _frames(3)
	t.eq(sp._preview_skin, "", "the preview is released")
	season["featured"] = saved["featured"]
	season["milestones"] = saved["milestones"]
	await _end()


## A free player who reached Record Breaker: the reason it is locked and the
## way to unlock it are both in view on the smallest phone.
func test_premium_lock_reason_fits_the_iphone_se() -> void:
	await _begin()
	var pid := Cloud.profile_id()
	_old_account(pid, Economy.tier_xp("s1", 52), false, 45)
	await Wallet.refresh()
	for key in ["se_667x375", "ipad_1024x768"]:
		await _device(key)
		App.goto(SeasonScreen)
		await _frames(8)
		var sp := App.screen as SeasonScreen
		sp.jump_to(50)
		await _frames(30)
		t.eq(sp.display_state(50, "premium"), "premium_locked", "%s: Record Breaker reached, needs Premium" % key)
		var sl := sp._d["state"] as Label
		t.check(sl.text.contains("Premium") and sl.text.contains("1,500 Coins"), "%s: the reason: %s" % [key, sl.text])
		t.check((sp._d["scroll"] as Control).get_global_rect().grow(1.0).encloses(sl.get_global_rect()), "%s: the whole reason in view" % key)
		var act := sp._d["action"] as Button
		t.eq(act.text, "Get Premium in the Shop", "%s: the way to unlock it" % key)
		t.check(_inside(act.get_global_rect(), _safe()) and _inside(act.get_global_rect(), sp.detail_panel.get_global_rect()), "%s: on screen, inside the panel" % key)
		t.check(_inside(sp.detail_panel.get_global_rect(), _safe()), "%s: the panel inside the safe area (no overflow)" % key)
	await _end()
