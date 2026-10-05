extends RefCounted
## Pass 8 challenges, the game side (docs/ECONOMY.md §10; the service side
## is service/test/challenges.test.mjs):
##  - ChallengeRules mirrors service/src/challenges.js: UTC days, Monday
##    weeks, instance ids, credits, the active-play threshold, local reset
##    text;
##  - ActivityMeter counts active play in the real simulation: input that
##    changes or moves the runner, objective events, capture/splash/home
##    holds; never neutral input, a stale repeat, a held key against a wall,
##    a disconnected or bot-covered slot;
##  - the Wallet's cards, status, pin and a round's challenge part (pending
##    projection, settled result, practice training, no service), the
##    completion milestone once, Season progress including the bonus;
##  - the Season Pass: the Challenges page opens with the screen, both pass
##    rows stay whole and the cards are full touch targets at phone and iPad
##    sizes, a tap pins, the service-off state is an honest preview.
## The service-on states use the test-double service (tests/commerce_rig).
var t
var rig
var _saved := {}

const DEVICES := {
	"se_667x375": [Vector2i(1334, 750), 2.0, Rect2(0, 0, 0, 0)],
	"p14_844x390": [Vector2i(2532, 1170), 3.0, Rect2(47, 0, 47, 21)],
	"max_926x428": [Vector2i(2778, 1284), 3.0, Rect2(47, 0, 47, 21)],
	"ipad_1024x768": [Vector2i(2048, 1536), 2.0, Rect2(0, 24, 0, 20)],
}


# ------------------------------------------------------------------ rules
func test_rules_periods_credits_and_the_active_threshold() -> void:
	var c := ChallengeRules.cfg()
	t.eq((c["daily"] as Array).map(func(d: Dictionary) -> String: return "%s:%d:%d" % [d["id"], d["goal"], d["xp"]]),
		["night_shift:2:50", "campus_contribution:6:50", "team_effort:1:50"], "the daily set")
	t.eq((c["weekly"] as Array).map(func(d: Dictionary) -> String: return "%s:%d:%d" % [d["id"], d["goal"], d["xp"]]),
		["campus_regular:10:150", "pull_your_weight:18:150", "strong_together:4:150"], "the weekly set")
	# 2026-10-05 is a Monday
	var mon := int(Time.get_unix_time_from_datetime_string("2026-10-05T00:00:00"))
	t.eq(int(Time.get_datetime_dict_from_unix_time(mon)["weekday"]), 1, "the fixture is a Monday")
	t.eq(ChallengeRules.week_start(mon), mon, "Monday 00:00 UTC starts the week")
	t.eq(ChallengeRules.week_start(mon - 1), mon - 7 * 86400, "Sunday 23:59:59 is last week")
	t.eq(ChallengeRules.week_start(mon + 7 * 86400 - 1), mon, "up to the next Monday")
	t.eq(ChallengeRules.day_start(mon + 86399), mon, "the UTC day")
	var w := ChallengeRules.period_of("weekly", mon + 3 * 86400)
	t.eq([int(w["start"]), int(w["end"]), String(w["key"])], [mon, mon + 7 * 86400, "2026-10-05"], "the week's period")
	t.eq(ChallengeRules.instance_id("weekly", String(w["key"]), "pull_your_weight"), "w:2026-10-05:pull_your_weight", "instance ids as the service's")
	t.eq(ChallengeRules.instance_id("daily", "2026-10-06", "night_shift"), "d:2026-10-06:night_shift", "daily instance id")
	# credits: unique stamps or different runners tagged, at most 3
	t.eq(ChallengeRules.credits({"role": TC.Role.RUNNER, "stamps": 3}), 3, "three waters: 3")
	t.eq(ChallengeRules.credits({"role": TC.Role.PATROL, "unique_captures": 5, "captures": 11}), 3, "five different runners: capped at 3")
	t.eq(ChallengeRules.credits({"role": TC.Role.PATROL, "unique_captures": 1, "captures": 9}), 1, "one runner tagged nine times: 1")
	# active play: min(60 s, 40% of the round)
	t.near(ChallengeRules.active_need(240.0), 60.0, 0.001, "a full round needs 60 s")
	t.near(ChallengeRules.active_need(100.0), 40.0, 0.001, "a short one 40%")
	var res := {"outcome": TC.Outcome.PATROL_WIN, "round_time": 240.0}
	t.eq(ChallengeRules.increments({"role": TC.Role.PATROL, "unique_captures": 2, "active_s": 61}, res),
		{"state": "applied", "active_rounds": 1, "credits": 2, "round_wins": 1}, "Night Watch: active, 2 credits, a Round Win")
	t.eq(ChallengeRules.increments({"role": TC.Role.RUNNER, "stamps": 3, "active_s": 59}, res)["state"], "inactive", "59 s: not active")
	# local reset time (presentation only)
	t.eq(ChallengeRules.local_clock(mon, -4 * 3600, 1), "8:00 PM", "UTC midnight in New York (EDT)")
	t.eq(ChallengeRules.local_clock(mon, 2 * 3600, 0), "02:00", "24-hour clocks")
	t.eq(ChallengeRules.reset_text(mon, mon - 3600, -4 * 3600, 1), "Resets 8:00 PM", "within a day: the time")
	t.eq(ChallengeRules.reset_text(mon, mon - 3 * 86400, -4 * 3600, 1), "Resets Sun 8:00 PM", "later: the local weekday")


# ------------------------------------------------------------------ activity
## The evidence rule on its own: a fresh input that changes (stick, camera,
## buttons) or a steady stick that really moves the player.
func test_activity_evidence_rule() -> void:
	var m := ActivityMeter.new()
	var p := SimPlayer.new()
	p.body = CharacterBody3D.new()
	t.add_child(p.body)
	p.body.global_position = Vector3(5, 0, 5)
	p.prev_pos = p.pos()
	var dt := 1.0 / 60.0
	var c := InputCmd.new()
	t.check(not m._evidence(0, c, p, dt), "a neutral input: nothing")
	c.move = Vector2(0, -1)
	t.check(m._evidence(0, c, p, dt), "the stick pushed: evidence")
	t.check(not m._evidence(0, c, p, dt), "the same stick, the player not moving (a key held against a wall): nothing")
	p.prev_pos = p.pos() - Vector3(0, 0, 0.1)   # 0.1 m this tick = 6 m/s
	t.check(m._evidence(0, c, p, dt), "the same stick, the player running: evidence")
	p.prev_pos = p.pos() - Vector3(0, 0, 5.0)
	t.check(not m._evidence(0, c, p, dt), "a 5 m jump in one tick (a respawn) isn't movement")
	p.prev_pos = Vector3.INF
	c.cam_yaw = 0.02
	t.check(not m._evidence(0, c, p, dt), "a camera twitch under 2 degrees: nothing")
	c.cam_yaw = 0.04
	t.check(m._evidence(0, c, p, dt), "turning the camera past 2 degrees since the last evidence: evidence")
	c.move = Vector2(0.05, -1).normalized()
	t.check(not m._evidence(0, c, p, dt), "a tiny stick change: nothing")
	c.move = Vector2(0.4, -0.9).normalized()
	t.check(m._evidence(0, c, p, dt), "steering: evidence")
	c.pressed = TC.BTN_JUMP
	t.check(m._evidence(0, c, p, dt), "a button press: evidence")
	c.pressed = 0
	c.held = TC.BTN_TAG
	t.check(m._evidence(0, c, p, dt), "starting to hold a button: evidence")
	t.check(not m._evidence(0, c, p, dt), "still holding it, not moving: nothing")
	p.body.queue_free()


## In the real simulation: idling, looking around, a stale repeat, a
## capture hold, the window, a disconnect, the reported row.
func test_activity_meter_counts_play_not_idling() -> void:
	var h := SimHarness.new(t)
	var sim := h.make([TC.Role.RUNNER, TC.Role.RUNNER, TC.Role.PATROL, TC.Role.RUNNER])
	await h.to_playing()
	var hz := sim.cfg.sim_hz
	# slot 0: connected, sends neutral input every tick (menu idling)
	h.cmd(0)
	# slot 1: looks around (the camera turns a little every tick)
	# slot 2: Night Watch steering in a slow circle (held in the shed first)
	# slot 3: sends nothing (no fresh input: the host repeats the last one)
	for i in 20 * hz:
		h.cmd(1).cam_yaw = fposmod(h.cmd(1).cam_yaw + 0.012, TAU)
		h.cmd(2).move = Vector2.from_angle(float(i) * 0.01)
		await h.step()
	var a := func(slot: int) -> int: return sim.activity.active_s(slot, hz)
	t.eq(a.call(0), 0, "neutral input every tick is not play")
	t.check(a.call(1) >= 19 and a.call(1) <= 20, "looking around counts (%d s of 20)" % a.call(1))
	t.check(a.call(2) >= 19 and a.call(2) <= 20, "steering counts, also in the shed (%d s of 20)" % a.call(2))
	t.eq(a.call(3), 0, "a stale repeated input is not play")
	# slot 1 stops and is captured: the capture keeps an active player active
	var p1 := sim.player(1)
	p1.state = TC.PState.CAPTURED
	p1.penalty = 8.0
	var before := int(a.call(1))
	for i in 7 * hz:
		await h.step()
	t.check(int(a.call(1)) - before >= 6, "captured for 7 s: still active (%d s)" % (int(a.call(1)) - before))
	# then idle after the capture: only the 5 s window counts
	p1.state = TC.PState.ACTIVE
	p1.penalty = 0.0
	before = int(a.call(1))
	for i in 12 * hz:
		await h.step()
	t.check(int(a.call(1)) - before <= 6, "idle afterwards: only the 5 s window (%d s)" % (int(a.call(1)) - before))
	# disconnected: nothing, whatever the bot covering the slot does
	sim.set_disconnected(1)
	before = int(a.call(1))
	for i in 3 * hz:
		h.cmd(1).cam_yaw = fposmod(h.cmd(1).cam_yaw + 0.02, TAU)
		await h.step()
	t.eq(int(a.call(1)) - before, 0, "a disconnected (bot-covered) slot counts nothing")
	# the row: whole seconds, never more than the round, never while away
	var res := sim.build_results()
	for r in res["players"]:
		var row: Dictionary = r
		t.check(row.has("active_s") and row["active_s"] is int, "slot %d reports whole active seconds" % int(row["slot"]))
		t.check(float(row["active_s"]) <= float(res["round_time"]) - float(row["away_s"]) + 1.0, "slot %d: active <= round - away" % int(row["slot"]))
	# objective events are evidence: a stamp counts for its runner
	t.eq(a.call(3), 0, "slot 3 still idle")
	sim.events = [{"type": TC.Ev.SPLASH_STAMP, "a": 3, "b": 0}]
	sim.activity.step(sim, {})
	t.eq(int(sim.activity._ticks.get(3, 0)), 1, "a stamp is evidence of play")
	h.free_sim()


# ------------------------------------------------------------------ wallet
func _round(mid: String, me_row: Dictionary, outcome: int = TC.Outcome.RUNNERS_WIN) -> Dictionary:
	var me := {"slot": 0, "uid": "T:_host", "role": TC.Role.RUNNER, "stamps": 3, "finished": true, "unique_captures": 0, "coins_picked": 1,
		"present": true, "away_s": 0.0, "is_bot": false, "active_s": 200}
	me.merge(me_row, true)
	return {"match_id": mid, "outcome": outcome, "fastest_slot": 0, "round_time": 240.0, "coin_spawns": 8, "players": [me,
		{"slot": 1, "uid": "T:_guest", "role": TC.Role.PATROL, "stamps": 0, "finished": false, "unique_captures": 1, "coins_picked": 0,
			"present": true, "away_s": 0.0, "is_bot": false, "active_s": 180}]}


func _report(res: Dictionary, pid: String) -> Dictionary:
	var me: Dictionary = res["players"][0]
	return {"report_version": 2, "outcome": res["outcome"], "round_time_s": 240.0, "coin_spawns": 8, "players": [
		{"profile_id": pid, "slot": 0, "role": int(me["role"]), "stamps": int(me["stamps"]), "finished": bool(me["finished"]),
			"first_home": bool(me["finished"]), "unique_captures": int(me["unique_captures"]), "coins_picked": int(me["coins_picked"]),
			"present": true, "away_s": 0.0, "active_s": int(me["active_s"])}]}


func test_service_off_and_practice_add_nothing_and_say_so() -> void:
	rig = preload("res://tests/commerce_rig.gd").new(t)
	await rig.begin(false, false)
	var cards := Wallet.challenge_cards()
	t.eq(cards.size(), 6, "six goals previewed")
	t.check(cards.all(func(c: Dictionary) -> bool: return not bool(c["known"]) and int(c["progress"]) == 0), "no progress pretended")
	var st := Wallet.challenge_status()
	t.check(not bool(st["live"]) and String(st["text"]).contains("game service") and String(st["text"]).contains("No progress or Season XP"),
		"an honest preview status: %s" % st["text"])
	Wallet.pin_challenge("campus_contribution")
	t.eq(Wallet.pinned_challenge_text(), "Campus Contribution · Earn 6 contribution credits", "the pinned goal reads as a goal, no progress")
	t.eq(Wallet.pinned_challenge_text({"stamps": 2}), "Campus Contribution · Earn 6 contribution credits", "and no provisional count without the service")
	Wallet.pin_challenge("")
	t.eq(Wallet.pinned_challenge_text(), "", "nothing pinned: empty")
	var me := {"slot": 0, "role": TC.Role.RUNNER, "stamps": 2, "unique_captures": 0, "present": true, "active_s": 200}
	var pr := Wallet.settle_round(_round("P-1", me), _round("P-1", me)["players"][0], true)
	var ch: Dictionary = pr["challenges"]
	t.eq(String(ch["state"]), "practice", "practice: training feedback only")
	t.check(String(ch["message"]).contains("Training only: 2 contribution credits") and String(ch["message"]).contains("doesn't count"),
		"labelled as training: %s" % ch["message"])
	t.eq(int(pr["challenge_xp"]), 0, "no challenge XP")
	var off := Wallet.settle_round(_round("O-1", me), _round("O-1", me)["players"][0], false)
	t.eq(String(off["state"]), "no_service", "no service: not settled")
	t.eq(String(off["challenges"]["state"]), "none", "and no challenge part")
	var cx := Wallet.settle_round(_round("C-1", me, TC.Outcome.CANCELLED), me, false)
	t.eq(String(cx["challenges"]["state"]), "none", "cancelled: nothing")
	t.eq(int(Wallet.season_state("s1")["xp"]), 0, "no Season XP anywhere")
	await rig.end()


func test_settled_round_completes_a_goal_once_and_moves_the_pass() -> void:
	rig = preload("res://tests/commerce_rig.gd").new(t)
	await rig.begin()
	await rig.sign_in("T:_host")
	var pid := Cloud.profile_id()
	rig.svc.set_challenge(pid, "campus_contribution", 4, false)
	rig.svc.set_challenge(pid, "night_shift", 1, false)
	await Wallet.refresh()
	var cards := Wallet.challenge_cards()
	var cc: Dictionary = cards.filter(func(c: Dictionary) -> bool: return String(c["id"]) == "campus_contribution")[0]
	t.eq([cc["progress"], cc["goal"], cc["known"], cc["period"]], [4, 6, true, "daily"], "the service's progress for today")
	t.check(int(cc["resets_at"]) == ChallengeRules.period_of("daily", Wallet.server_now())["end"], "resets at the next 00:00 UTC")
	t.check(bool(Wallet.challenge_status()["live"]), "live")
	Wallet.pin_challenge("campus_contribution")
	t.eq(Wallet.pinned_challenge_text(), "Campus Contribution 4/6 · +50 Season XP", "the pinned line")
	t.eq(Wallet.pinned_challenge_text({"role": TC.Role.RUNNER, "stamps": 1}), "Campus Contribution 4/6 · +50 Season XP · +1 this round (provisional)",
		"in a round: provisional, separate from settled progress")
	var done := []
	Wallet.challenge_completed.connect(func(c: Dictionary) -> void: done.append(c))
	# a round: the host (runner) splashes three waters, actively
	var mid := "QWERTY-1-0000c0de"
	var guest: String = rig.svc._pid_for("T:_guest")
	rig.svc.rounds[mid] = {"host": pid, "participants": {pid: 0, guest: 1}, "report": {}, "acks": {}, "settled": {}, "started_at": rig.svc._now_ms()}
	App.party_code = "QWERTY"
	var res := _round(mid, {})
	var me: Dictionary = res["players"][0]
	var xp0 := int(Wallet.season_state("s1")["xp"])
	# (the host's report is in; this game's confirmation goes out now and is
	# answered a frame later: until then the round is pending)
	rig.svc.rounds[mid]["report"] = _report(res, pid)
	var pend := Wallet.settle_round(res, me, false)
	var pc: Dictionary = pend["challenges"]
	t.eq(String(pc["state"]), "pending", "pending until the service settles")
	t.check((pc["lines"] as Array).any(func(l: Dictionary) -> bool: return String(l["id"]) == "campus_contribution" and bool(l["completed_now"])),
		"projected: Campus Contribution would complete")
	t.eq(int(pend["challenge_xp"]), 0, "nothing added while pending")
	await rig.until(func() -> bool: return String(Wallet.round_summary(mid)["state"]) == "settled")
	var s := Wallet.round_summary(mid)
	var sc: Dictionary = s["challenges"]
	t.eq(String(sc["state"]), "settled", "settled by the service")
	t.eq(String(sc["result"]), "applied", "the round counted (active)")
	var names := (sc["lines"] as Array).filter(func(l: Dictionary) -> bool: return bool(l["completed_now"])).map(func(l: Dictionary) -> String: return String(l["name"]))
	t.eq(names, ["Night Shift", "Campus Contribution", "Team Effort"], "three goals completed by this round")
	t.eq(int(s["challenge_xp"]), 150, "+150 Season XP from challenges")
	var base := int(Economy.round_season_xp(me, res)["xp"])
	t.eq(int(s["xp_after"]) - int(s["xp_before"]), base + 150, "the pass progress includes the bonus")
	t.eq(int(Wallet.season_state("s1")["xp"]) - xp0, base + 150, "and so does the wallet")
	await rig.frames(3)
	t.eq(done.size(), 3, "each completion announced once")
	var c2: Dictionary = Wallet.challenge_cards().filter(func(c: Dictionary) -> bool: return String(c["id"]) == "campus_contribution")[0]
	t.eq([c2["progress"], c2["completed"], c2["bonus_xp"]], [6, true, 50], "the card: complete, bonus delivered")
	t.eq(Wallet.pinned_challenge_text(), "Campus Contribution complete · +50 Season XP", "the pinned line says so")
	# the same results again (reopened, duplicated packet), a refresh: nothing more
	Wallet.settle_round(res, me, false)
	await Wallet.refresh()
	await rig.frames(5)
	t.eq(int(Wallet.season_state("s1")["xp"]) - xp0, base + 150, "never twice")
	t.eq(done.size(), 3, "no repeated milestone")
	# the RoundRewards view the results screen reads
	RoundRewards._cache.clear()
	var rr := RoundRewards.summary(mid)
	t.eq(int(rr["challenge_xp"]), 150, "results: the bonus")
	t.eq(String(rr["challenges"]["state"]), "settled", "results: settled")
	var box := VBoxContainer.new()
	ResultsScreen.add_challenge_lines(box, rr["challenges"])
	var texts: Array = box.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	t.check(texts.has("Campus Contribution complete · +50 Season XP"), "results line: %s" % [texts])
	box.free()
	App.party_code = ""
	await rig.end()


func test_inactive_round_and_results_lines() -> void:
	# a settled round the player didn't actively play: paid, no challenge
	var inactive := {"state": "settled", "result": "inactive", "xp": 0, "lines": [],
		"message": "No challenge progress: challenges count rounds with at least 60 s of active play."}
	var box := VBoxContainer.new()
	ResultsScreen.add_challenge_lines(box, inactive)
	var texts: Array = box.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	t.eq(texts, ["No challenge progress: challenges count rounds with at least 60 s of active play."], "an honest sentence")
	box.free()
	# pending: completion marked pending; other goals listed with progress
	var pending := {"state": "pending", "result": "applied", "xp": 50, "message": "", "lines": [
		{"id": "campus_contribution", "name": "Campus Contribution", "period": "daily", "progress": 6, "goal": 6, "inc": 3, "completed_now": true, "xp": 50},
		{"id": "pull_your_weight", "name": "Pull Your Weight", "period": "weekly", "progress": 9, "goal": 18, "inc": 3, "completed_now": false, "xp": 0}]}
	box = VBoxContainer.new()
	ResultsScreen.add_challenge_lines(box, pending)
	texts = box.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	t.eq(texts, ["Campus Contribution complete · +50 Season XP (pending)", "Challenges, pending: Pull Your Weight 9/18"], "pending is labelled")
	box.free()
	box = VBoxContainer.new()
	ResultsScreen.add_challenge_lines(box, {"state": "none"})
	t.eq(box.get_child_count(), 0, "nothing for a round with no challenge part")
	box.free()


# ------------------------------------------------------------------ Season Pass
func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


func _begin(with_service: bool) -> void:
	rig = preload("res://tests/commerce_rig.gd").new(t)
	await rig.begin(with_service, with_service)
	if with_service:
		await rig.sign_in()
	_saved = {"emulate": Input.emulate_touch_from_mouse, "device": Controls.device, "size": t.get_tree().root.size, "emu": UIKit.emulation.duplicate()}
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


func _px(p: Vector2) -> Vector2:
	return t.get_tree().root.get_final_transform() * p


func _tap(at: Vector2) -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = _px(at)
		e.global_position = e.position
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		t.get_viewport().push_input(e)
		await _frames(3)


func test_season_pass_challenges_fit_with_both_rows_whole() -> void:
	await _begin(true)
	var pid := Cloud.profile_id()
	rig.svc.wallet(pid)["season"]["s1"]["xp"] = 3450   # tier 15
	rig.svc.set_challenge(pid, "campus_contribution", 4)
	rig.svc.set_challenge(pid, "team_effort", 1)
	rig.svc.set_challenge(pid, "pull_your_weight", 11)
	await Wallet.refresh()
	var report: Array = []
	for key in DEVICES:
		await _device(key)
		App.goto(SeasonScreen)
		await _frames(8)
		var sp := App.screen as SeasonScreen
		var safe := _safe()
		# final sweep: the screen opens on the reward the stage shows; the
		# Challenges tab is one tap away
		t.eq(sp.side_page, "reward", "%s: the Reward page opens with the screen" % key)
		await _tap((sp._tabs["challenges"] as Control).get_global_rect().get_center())
		t.eq(sp.side_page, "challenges", "%s: the Challenges tab opens the goals" % key)
		t.check(sp.challenge_page.is_visible_in_tree(), "%s: and is shown" % key)
		var head := sp._ch["head"] as Label
		t.eq(head.text, "Challenges · Earn Season XP", "%s: the heading" % key)
		t.eq((sp._ch["role"] as Label).text, "Splash waters or tag different runners.", "%s: the role line, once" % key)
		t.check(not (sp._ch["status"] as Label).visible, "%s: live: no status line" % key)
		t.check(_inside(sp.challenge_page.get_global_rect(), sp.detail_panel.get_global_rect()), "%s: the page inside the side panel" % key)
		t.check(_inside(sp.detail_panel.get_global_rect(), safe), "%s: the side panel inside the safe area" % key)
		for k in sp._tabs:
			var tr := (sp._tabs[k] as Control).get_global_rect()
			t.check(_inside(tr, safe) and tr.size.y >= UIKit.touch_min() - 0.5, "%s: the %s tab is a whole 44 pt target" % [key, k])
		t.eq(sp.challenge_cards.size(), 6, "%s: six goals" % key)
		var list_r := (sp._ch["scroll"] as Control).get_global_rect()
		var shown := 0
		for cc in sp.challenge_cards:
			var r := (cc as Control).get_global_rect()
			t.check(r.size.y >= UIKit.touch_min() - 0.5, "%s: %s is a full touch target (%.0f)" % [key, cc.id, r.size.y])
			if list_r.grow(0.5).encloses(r):
				shown += 1
		t.check(shown >= 2, "%s: at least two whole cards in view (%d)" % [key, shown])
		var ccard: Variant = sp.challenge_cards.filter(func(c) -> bool: return c.id == "campus_contribution")[0]
		t.eq(ccard.count_l.text, "4/6", "%s: progress 4/6" % key)
		t.eq(ccard.xp_l.text, "+50 Season XP", "%s: +50 Season XP" % key)
		t.check(ccard.bar.visible and absf(ccard.bar.value - 4.0 / 6.0) < 0.01, "%s: the bar" % key)
		var te: Variant = sp.challenge_cards.filter(func(c) -> bool: return c.id == "team_effort")[0]
		t.eq(te.xp_l.text, "Done · +50 Season XP", "%s: a completed goal says so" % key)
		t.check((sp._ch["groups"]["daily"] as Label).text.begins_with("Daily · Resets "), "%s: daily reset in local time: %s" % [key, (sp._ch["groups"]["daily"] as Label).text])
		t.check((sp._ch["groups"]["weekly"] as Label).text.begins_with("Weekly · Resets "), "%s: weekly reset" % key)
		# both pass rows stay whole in the track with the Challenges page open
		var track := sp.track_scroll.get_global_rect()
		var hbar := sp.track_scroll.get_h_scroll_bar().get_combined_minimum_size().y
		for c in sp.cells:
			var r: Rect2 = (c as Control).get_global_rect()
			if r.end.x <= track.position.x or r.position.x >= track.end.x:
				continue
			t.check(r.position.y >= track.position.y - 0.5 and r.end.y <= track.end.y - hbar + 0.5 and r.end.y <= safe.end.y + 0.5,
				"%s: %s cell whole" % [key, c.track])
		t.check(_inside(sp.claim_all_btn.get_global_rect(), safe), "%s: Claim all reachable" % key)
		var fr: Rect2 = sp._cell(15, "free").get_global_rect()
		var pr: Rect2 = sp._cell(15, "premium").get_global_rect()
		report.append("%s: cell %.0fx%.0f, free y %.0f-%.0f, premium y %.0f-%.0f, side %s, cards in view %d" % [key, pr.size.x, pr.size.y,
			fr.position.y, fr.end.y, pr.position.y, pr.end.y, sp.detail_panel.get_global_rect(), shown])
		# a tap on a reward (one wholly in view) shows its detail; the tab comes back
		var target: Control = null
		for c in sp.cells:
			var cr := (c as Control).get_global_rect()
			if c.track == "premium" and cr.position.x >= track.position.x + 2.0 and cr.end.x <= track.end.x - 2.0:
				target = c
				break
		t.check(target != null, "%s: a Premium reward in view" % key)
		if target == null:
			continue
		await _tap(target.get_global_rect().get_center())
		t.eq(sp.side_page, "reward", "%s: a tapped reward shows its detail" % key)
		t.check((sp._d["page"] as Control).is_visible_in_tree() and not sp.challenge_page.is_visible_in_tree(), "%s: one page at a time" % key)
		await _tap((sp._tabs["challenges"] as Control).get_global_rect().get_center())
		t.eq(sp.side_page, "challenges", "%s: the Challenges tab" % key)
	for line in report:
		print("[challenges bounds] " + line)
	# a tap pins (viewport-delivered touch), another unpins; one pin at a time
	var sp2 := App.screen as SeasonScreen
	var first: Control = sp2.challenge_cards[0]
	await _tap(first.get_global_rect().get_center())
	t.eq(Wallet.pinned_challenge_id(), "night_shift", "a tap pins the goal")
	t.check(UIKit.face_of(first).selected and first.mark.visible, "and the card shows it")
	await _tap((sp2.challenge_cards[1] as Control).get_global_rect().get_center())
	t.eq(Wallet.pinned_challenge_id(), "campus_contribution", "pinning another replaces the pin")
	t.check(not UIKit.face_of(first).selected, "one pin at a time")
	await _tap((sp2.challenge_cards[1] as Control).get_global_rect().get_center())
	t.eq(Wallet.pinned_challenge_id(), "", "a second tap unpins")
	await _end()


func test_season_pass_challenges_service_off_is_an_honest_preview() -> void:
	await _begin(false)
	for key in ["se_667x375", "p14_844x390"]:
		await _device(key)
		App.goto(SeasonScreen)
		await _frames(8)
		var sp := App.screen as SeasonScreen
		var safe := _safe()
		sp.show_side("challenges")
		await _frames(2)
		var status := sp._ch["status"] as Label
		t.check(status.is_visible_in_tree() and status.text.contains("No progress or Season XP"), "%s: %s" % [key, status.text])
		t.check(not status.text.contains("build") and not status.text.contains("game service"), "%s: no developer wording on screen" % key)
		t.check(_inside(status.get_global_rect(), sp.detail_panel.get_global_rect()), "%s: the status sits whole in the panel" % key)
		for cc in sp.challenge_cards:
			t.check(not cc.bar.visible and not cc.count_l.visible, "%s: %s shows no progress it doesn't have" % [key, cc.id])
			t.check(cc.task_l.text != "" and cc.xp_l.text.begins_with("+"), "%s: %s is a readable goal preview" % [key, cc.id])
		var labels: Array = sp.challenge_page.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
		t.check(not labels.any(func(s: String) -> bool: return s.begins_with("Done") or s.contains("Claim")), "%s: no pretend completion or claim" % key)
		t.check(not sp.claim_all_btn.visible and sp.banner.visible, "%s: the pass header keeps its honest status" % key)
		for c in sp.cells:
			var r: Rect2 = (c as Control).get_global_rect()
			var track := sp.track_scroll.get_global_rect()
			if r.end.x > track.position.x and r.position.x < track.end.x:
				t.check(r.end.y <= safe.end.y + 0.5, "%s: %s row whole" % [key, c.track])
	await _end()


## Pass 8 §12: a goal that completes while its card is on screen confirms
## once with the shared motion; a card first shown already done, a refresh
## of a done card, and Reduced Motion add no motion.
func test_completion_confirms_once_with_shared_motion() -> void:
	var prev: Variant = Save.get_setting("reduced_motion", false)
	Save.set_setting("reduced_motion", false)
	var mk := func(done: bool) -> Dictionary:
		return {"name": "Splash", "task": "Stamp 6 waters", "goal": 6, "progress": 6 if done else 5, "completed": done,
			"pinned": false, "xp": 50, "period": "daily"}
	var c := SeasonScreen.ChallengeCard.new()
	c.setup(null, "d_waters")
	t.get_tree().root.add_child(c)
	c.refresh(mk.call(true), true)
	t.check(not Motion.running(c.mark).has("scale"), "shown already done: no motion")
	var c2 := SeasonScreen.ChallengeCard.new()
	c2.setup(null, "d_waters")
	t.get_tree().root.add_child(c2)
	c2.refresh(mk.call(false), true)
	c2.refresh(mk.call(true), true)
	t.check(Motion.running(c2.mark).has("scale"), "completed while shown: the check confirms")
	await t.get_tree().create_timer(0.4).timeout
	c2.refresh(mk.call(true), true)
	t.check(not Motion.running(c2.mark).has("scale"), "a later refresh of a done goal: no repeat")
	Save.set_setting("reduced_motion", true)
	var c3 := SeasonScreen.ChallengeCard.new()
	c3.setup(null, "d_waters")
	t.get_tree().root.add_child(c3)
	c3.refresh(mk.call(false), true)
	c3.refresh(mk.call(true), true)
	t.check(not Motion.running(c3.mark).has("scale"), "Reduced Motion: no motion")
	Save.set_setting("reduced_motion", prev)
	for n in [c, c2, c3]:
		n.queue_free()
	await t.get_tree().process_frame
