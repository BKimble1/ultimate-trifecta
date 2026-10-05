extends RefCounted
## Pass 8 match clarity: the team goal bar ("Team home 2/4 · Need 2 more" /
## "Runners home 2/4 · Hold until" + the one clock) from the round's own
## configuration for 1/2/3 Night Watch, the segmented tracker counting real
## finishes, the personal card in every runner and Night Watch state, the
## pace and "Not home" at the end, the pause menu's where-you-stand lines,
## and the layout at phone and iPad sizes in point units with safe areas,
## standard and mirrored controls: nothing over Pause, the minimap, the
## thumb clusters or outside the HUD band.
var t
var _saved := {}

## [label, pixels, point scale, safe insets in points L,T,R,B]
const DEVICES := [
	["iPhone SE 667x375 pt", Vector2i(1334, 750), 2.0, Rect2(0, 0, 0, 0)],
	["844x390 pt (notch left)", Vector2i(2532, 1170), 3.0, Rect2(47, 0, 47, 21)],
	["926x428 pt", Vector2i(2778, 1284), 3.0, Rect2(47, 0, 47, 21)],
	["iPad 1024x768 pt", Vector2i(2048, 1536), 2.0, Rect2(0, 24, 0, 20)],
	["844x390 pt, other landscape (asymmetric inset)", Vector2i(2532, 1170), 3.0, Rect2(0, 0, 59, 21)],
]


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


func _begin(role := "runner", watch := 2, mirrored := false, seed_v := 4242) -> MatchController:
	_saved = {"device": Controls.device, "size": t.get_tree().root.size,
		"layout": Save.get_setting("touch_layout", "standard"), "layout2": Save.get_setting("touch_layout_v2", null),
		"emu": UIKit.emulation.duplicate()}
	Save.set_setting("touch_layout", "mirrored" if mirrored else "standard")
	Save.set_setting("touch_layout_v2", null)
	Controls.device = "touch"
	for c in t.get_tree().root.get_children():
		if c is BootCurtain:
			c.queue_free()
	if App.screen and is_instance_valid(App.screen):
		App.screen.queue_free()
	App.screen = null
	MatchController.drop_campus_cache()
	var s := NetSession.new()
	t.add_child(s)
	s.start_offline("u-hud8", "Tester", {}, role)
	s.settings["watch"] = watch
	var info := {}
	s.match_starting.connect(func(i: Dictionary) -> void: info.merge(i, true), CONNECT_ONE_SHOT)
	s.host_start_match(seed_v)
	var mc := MatchController.new()
	mc.setup(s, info, {"quality": 0, "staged": false})
	t.add_child(mc)
	await _frames(6)
	return mc


func _end(mc: MatchController) -> void:
	var s: Variant = mc.session
	mc.queue_free()
	if is_instance_valid(s):
		(s as Node).queue_free()
	await _frames(2)
	MatchController.drop_campus_cache()
	Controls.device = _saved["device"]
	Save.set_setting("touch_layout", _saved["layout"])
	Save.set_setting("touch_layout_v2", _saved["layout2"])
	UIKit.emulation = _saved["emu"]
	t.get_tree().root.size = _saved["size"]
	await _frames(2)


func _rows(mc: MatchController) -> Array:
	mc.hud.refresh(0.016)
	return mc.hud.personal_rows


func _texts(mc: MatchController) -> Array:
	var out: Array = []
	for r in _rows(mc):
		out.append(String(r["text"]))
	return out


func test_goal_bar_follows_the_round_configuration() -> void:
	for w in [1, 2, 3]:
		var mc := await _begin("runner", w)
		var need := PartySeries.required_home(w)
		t.eq(mc.cfg.runners_needed, need, "%d Watch: required home from the round's settings (%d)" % [w, need])
		t.eq(mc.runner_count(), 8 - w, "%d Watch: %d runners" % [w, 8 - w])
		mc.hud.refresh(0.016)
		t.eq(mc.hud.goal_lbl.text, "Team home 0/%d · Need %d more" % [need, need], "%d Watch: runner sentence" % w)
		t.eq(mc.hud.tracker.needed, need, "one tracker segment per required finish")
		mc.sim.finished_count = 2
		mc.hud.refresh(0.016)
		t.eq(mc.hud.goal_lbl.text, "Team home 2/%d · Need %d more" % [need, need - 2], "%d Watch: counts finishes" % w)
		t.eq(mc.hud.tracker.home, 2, "two segments filled for two finishes")
		# splashes and catches never fill the tracker
		mc.sim.player(mc.local_slot).stamps = 7
		mc.sim.player(mc.local_slot).times_captured = 2
		mc.hud.refresh(0.016)
		t.eq(mc.hud.tracker.home, 2, "stamps and catches don't count as home")
		t.check(not mc.hud.goal_lbl.text.to_lower().contains("win"), "no win claimed from time or counts")
		await _end(mc)
	var mw := await _begin("patrol", 3)
	mw.hud.refresh(0.016)
	t.eq(int(mw.hud.info["role"]), TC.Role.PATROL, "Night Watch practice")
	t.eq(mw.hud.goal_lbl.text, "Runners home 0/4 · Hold until", "Watch sentence, the clock beside it")
	t.check(mw.hud.timer_lbl.is_visible_in_tree() and mw.hud.timer_lbl.text == "4:00", "one round clock (%s)" % mw.hud.timer_lbl.text)
	t.eq(mw.hud.find_children("*", "Label", true, false).filter(func(l: Label) -> bool: return l.is_visible_in_tree() and l.text.contains(":") and l.text.length() <= 5 and l.text[0].is_valid_int()).size(), 1,
		"exactly one clock on the HUD")
	await _end(mw)


func test_clock_urgency_has_colour_and_shape() -> void:
	t.eq(MatchHUD.clock_urgency(120.0, true), 0, "calm")
	t.eq(MatchHUD.clock_urgency(29.0, true), 1, "under 30 s: amber")
	t.eq(MatchHUD.clock_urgency(9.0, true), 2, "under 10 s: the alarm-clock shape")
	t.eq(MatchHUD.clock_urgency(5.0, false), 0, "not while not playing")
	t.eq(MatchHUD.clock_text(48.9), "0:48", "m:ss")


func test_runner_card_in_every_state() -> void:
	var mc := await _begin("runner", 2)
	PaceFields.settle()
	mc.sim._set_phase(TC.Phase.PLAYING)
	var p := mc.sim.player(mc.local_slot)
	var dorm := CampusDorms.display_name(mc.home_dorm)
	p.stamps = 0
	var tx := _texts(mc)
	t.eq(tx[0], "You: 0/3 waters", "progress first")
	t.check(String(tx[1]).begins_with("Next: "), "one next action (%s)" % tx[1])
	var goal: Dictionary = mc.hud.personal_rows[1]
	t.check(float(goal["bearing"]) != INF and float(goal["dist"]) > 0.0, "with a direction and distance")
	var ws: Array = mc.hud.personal_rows[0]["waters"]
	var icons := {}
	for w in ws:
		icons[String(w["icon"])] = true
	t.eq(icons.size(), 3, "three distinct water icons")
	p.stamps = 3
	tx = _texts(mc)
	t.eq(tx[0], "You: 2/3 waters", "two of three")
	t.eq((mc.hud.personal_rows[0]["waters"] as Array).filter(func(w: Dictionary) -> bool: return bool(w["done"])).size(), 2, "two checked")
	var tgi := int(mc.hud.personal_rows[1].get("target", -1))
	t.eq(tgi, 2, "the next suggestion is the remaining water")
	p.stamps = 7
	tx = _texts(mc)
	t.eq(tx[1], "Return inside %s" % dorm, "all three: back inside tonight's dorm")
	var door := int(mc.hud.personal_rows[1].get("door", -1))
	t.check(door >= 0 and door < mc.layout.home_doors(mc.home_dorm).size(), "pointing at one of its doors (%d)" % door)
	# the map marks the same suggestion
	var items := MatchHUD.MapPainter.items(mc.hud, Vector2(300, 300), 280.0, true)
	var nd := items.filter(func(it: Dictionary) -> bool: return String(it["kind"]) == "door" and bool(it.get("next", false)))
	t.eq(nd.size(), 1, "one door marked on the map")
	if not nd.is_empty():
		t.eq(int(nd[0]["door"]), door, "the same door as the card")
	# caught: countdown, stamps kept, where you come back, protection
	p.stamps = 3
	mc.last_stamp_water = int(mc.targets[1])
	p.state = TC.PState.CAPTURED
	p.penalty = 4.2
	tx = _texts(mc)
	t.eq(tx[1], "Caught · back in 5", "the card's countdown")
	t.check(mc.hud.overlay.visible, "the capture notice")
	t.check(mc.hud.overlay_title.text.begins_with("Caught"), "says caught (%s)" % mc.hud.overlay_title.text)
	t.eq(mc.hud.overlay_sub.text, "2/3 waters kept · back at %s · protected %d s" % [String(mc.layout.waters[int(mc.targets[1])]["short"]), int(mc.cfg.respawn_protect_s)],
		"stamps retained, return place, protection")
	p.state = TC.PState.ACTIVE
	p.penalty = 0.0
	p.protect = 1.5
	mc.hud.refresh(0.016)
	t.eq(mc.hud.sub_lbl.text, "Protected · 2", "protection after the return")
	p.protect = 0.0
	# home: "Home · 2nd to finish · Waiting for team", then watching
	p.stamps = 7
	p.state = TC.PState.FINISHED
	p.finished_tick = mc.sim.tick
	mc.sim.finished_count = 2
	mc.my_finish_order = 2
	mc.hud.home_now()
	tx = _texts(mc)
	t.eq(tx[0], "Home · 2nd to finish", "home and your finish place")
	t.check(String(tx[1]).begins_with("Waiting for team"), "waiting for the team (%s)" % tx[1])
	t.check(mc.hud.overlay.visible and mc.hud.overlay_title.text == "Home · 2nd to finish", "the moment you get home")
	mc.hud._home_t -= MatchHUD.HOME_OVERLAY_S + 0.1
	mc.hud.refresh(0.016)
	t.check(not mc.hud.overlay.visible, "then the notice gives way to watching a teammate (%s, home_t %.2f, t %.2f)" % [mc.hud.overlay_title.text, mc.hud._home_t, mc.hud._t])
	# the round ends with you out: "Not home"
	p.state = TC.PState.ACTIVE
	p.stamps = 3
	mc.sim._end_match(TC.Outcome.PATROL_WIN)
	tx = _texts(mc)
	t.check(tx.has("Runner pace: Not home"), "an unfinished runner's pace is Not home at the end (%s)" % str(tx))
	await _end(mc)


func test_watch_card_tags_and_pause_info() -> void:
	var mc := await _begin("patrol", 2)
	mc.sim._set_phase(TC.Phase.PLAYING)
	var tx := _texts(mc)
	t.eq(tx[0], "You: 0 tags · 0 different runners", "your contribution first")
	var runners: Array = []
	for slot in mc.roster:
		if int(mc.roster[slot]["role"]) == TC.Role.RUNNER:
			runners.append(int(slot))
	# three tags of two different runners (reliable events, host or guest)
	for a in [runners[0], runners[0], runners[1]]:
		mc._present_event({"type": TC.Ev.CAPTURE, "a": a, "b": mc.local_slot, "v": 0, "pos": Vector3.ZERO, "id": 0}, true, false)
	tx = _texts(mc)
	t.eq(tx[0], "You: 3 tags · 2 different runners", "tags and different runners")
	t.check(not str(tx).contains("pace"), "no runner pace for the Night Watch")
	t.check((mc.local_info()["pace"] as Dictionary).is_empty(), "and none in its data")
	var guard := (mc.hud.personal_rows as Array).filter(func(r: Dictionary) -> bool: return String(r["type"]) == "guard")
	t.eq(guard.size(), 1, "the waters to guard")
	if not guard.is_empty():
		t.eq((guard[0]["waters"] as Array).size(), 3, "all three")
	mc.hud.open_pause()
	await _frames(2)
	var pi := mc.hud._info_lbl.text
	t.check(pi.contains("Runners home 0/4 · Hold until") and pi.contains("You: 3 tags · 2 different runners"), "the menu says where you stand (%s)" % pi)
	t.check(not pi.contains("Series"), "practice: no series line")
	mc.hud.close_pause()
	await _end(mc)


func test_series_line_never_fakes_a_place() -> void:
	t.eq(RoundRanking.series_line({}, "u1"), "", "no series: nothing")
	var ps := PartySeries.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	ps.start({"watch": 2, "rounds": 3}, rng)
	t.eq(RoundRanking.series_line(ps.to_dict(), "u1"), "", "before the first results: no place")
	var mk := func(mid: String, oc: int, roles: Dictionary, away: Dictionary = {}) -> Dictionary:
		var rows: Array = []
		for uid in roles:
			rows.append({"uid": uid, "name": uid, "is_bot": false, "role": roles[uid], "present": true, "away_s": float(away.get(uid, 0.0))})
		rows.append({"uid": "bot-7", "name": "Bot Snooze", "is_bot": true, "role": TC.Role.RUNNER})
		return {"match_id": mid, "outcome": oc, "players": rows, "round_time": 200.0}
	ps.record_round(mk.call("m1", TC.Outcome.RUNNERS_WIN, {"u1": TC.Role.RUNNER, "u2": TC.Role.RUNNER, "u3": TC.Role.PATROL}))
	t.eq(RoundRanking.series_line(ps.to_dict(), "u1"), "Series: tied 1st · 1 Round Win", "two winners share 1st, said as tied")
	t.eq(RoundRanking.series_line(ps.to_dict(), "u3"), "Series: 3rd · 0 Round Wins", "the other team's member")
	ps.record_round(mk.call("m2", TC.Outcome.PATROL_WIN, {"u1": TC.Role.PATROL, "u2": TC.Role.RUNNER, "u3": TC.Role.RUNNER, "u4": TC.Role.RUNNER},
		{"u1": 150.0}))
	t.eq(RoundRanking.series_line(ps.to_dict(), "u1"), "Series: tied 1st · 1 Round Win · away 1", "an away round stays marked (no win for it)")
	t.eq(RoundRanking.series_line(ps.to_dict(), "u4"), "Series: tied 3rd · 0 Round Wins · joined round 2", "a late join stays marked (and ties share a place)")
	t.eq(RoundRanking.series_line(ps.to_dict(), "bot-7"), "", "bots have no series place")
	t.check(not RoundRanking.series_line(ps.to_dict(), "u2").begins_with("Runner pace"), "never shaped like the pace")


## The HUD's own rects (canvas units).
func _hud_rects(mc: MatchHUD) -> Dictionary:
	var out := {"goal": mc.goal_bar.get_global_rect(), "personal": mc.personal.get_global_rect(),
		"badge": (mc.role_lbl.get_parent().get_parent().get_parent() as Control).get_global_rect()}
	if mc.danger_chip.visible:
		out["danger"] = mc.danger_chip.get_global_rect()
	return out


func test_layout_at_phone_and_ipad_sizes() -> void:
	var orig_emu := UIKit.emulation.duplicate()
	var orig_size: Vector2i = t.get_tree().root.size
	for mirrored in [false, true]:
		for role in ["runner", "patrol"]:
			if mirrored and role == "patrol":
				continue
			for d in DEVICES:
				var tag := "%s %s%s" % [String(d[0]), role, " mirrored" if mirrored else ""]
				UIKit.emulation = {"scale": float(d[2]), "safe": d[3]}
				t.get_tree().root.size = d[1]
				await _frames(2)
				var mc := await _begin(role, 2, mirrored)
				UIKit.emulation = {"scale": float(d[2]), "safe": d[3]}
				t.get_tree().root.size = d[1]
				await _frames(4)
				mc.sim._set_phase(TC.Phase.PLAYING)
				mc._seen_scan_t = 1000.0      # keep the sighting set below for this check
				var p := mc.sim.player(mc.local_slot)
				if role == "runner":
					p.stamps = 3
					# a Night Watch in plain sight close by: the danger chip shows
					for slot in mc.roster:
						if int(mc.roster[slot]["role"]) == TC.Role.PATROL:
							mc.last_seen[int(slot)] = {"pos": p.pos() + Vector3(6, 0, 0), "ms": Time.get_ticks_msec(), "live": true, "dist": 6.0, "cart": false, "yaw": 0.0}
							break
				mc.sim.finished_count = 1
				mc.hud.refresh(0.016)
				await _frames(2)
				mc.hud.refresh(0.016)
				var hud := mc.hud
				var vs: Vector2 = t.get_tree().root.get_visible_rect().size
				var safe := UIKit.safe_rect(t.get_tree().root, vs)
				var rects := _hud_rects(hud)
				if role == "runner":
					t.check(rects.has("danger"), "%s: the danger chip shows for a spotted nearby Watch" % tag)
				var pause := hud.pause_btn.get_global_rect()
				var mini := hud.minimap.get_global_rect()
				t.check(pause.size.x >= UIKit.touch_min() - 0.5 and pause.size.y >= UIKit.touch_min() - 0.5, "%s: Pause is a 44 pt target" % tag)
				var res: Dictionary = mc.touch.surface.res
				var thumbs: Array = []
				for bn in res.get("buttons", {}):
					var b: Dictionary = res["buttons"][bn]
					thumbs.append(Rect2(b["c"] - Vector2.ONE * float(b["hit"]), Vector2.ONE * float(b["hit"]) * 2.0))
				var sr := float(res.get("stick_r", 0.0))
				thumbs.append(Rect2(res.get("stick_c", Vector2.ZERO) - Vector2.ONE * sr, Vector2.ONE * sr * 2.0))
				var names := rects.keys()
				for i in names.size():
					var r: Rect2 = rects[names[i]]
					t.check(safe.grow(0.5).encloses(r), "%s: %s inside the safe area (%s in %s)" % [tag, names[i], str(r), str(safe)])
					t.check(r.end.y <= vs.y * TouchLayout.TOP_BAND + 0.5, "%s: %s stays in the top HUD band (%.0f of %.0f)" % [tag, names[i], r.end.y, vs.y])
					t.check(not r.intersects(pause) and not r.intersects(mini), "%s: %s clear of Pause and the minimap" % [tag, names[i]])
					for th in thumbs:
						t.check(not r.intersects(th), "%s: %s clear of the thumb controls" % [tag, names[i]])
					for j in range(i + 1, names.size()):
						t.check(not r.intersects(rects[names[j]]), "%s: %s and %s don't overlap" % [tag, names[i], names[j]])
				# words fit: nothing on the card is cut (long lines take two)
				t.eq(hud.personal.clipped_rows(), [], "%s: no clipped words on the card" % tag)
				# and in the states with the longest words
				for st in [[7, TC.PState.ACTIVE], [3, TC.PState.CAPTURED], [7, TC.PState.FINISHED]]:
					if role != "runner":
						break
					p.stamps = int(st[0])
					p.state = int(st[1])
					p.penalty = 5.0
					mc.my_finish_order = 3
					hud.refresh(0.016)
					await _frames(1)
					t.eq(hud.personal.clipped_rows(), [], "%s state %d: no clipped words" % [tag, int(st[1])])
					var pr := hud.personal.get_global_rect()
					t.check(pr.end.y <= vs.y * TouchLayout.TOP_BAND + 0.5, "%s state %d: the card stays in the HUD band (%.0f)" % [tag, int(st[1]), pr.end.y])
				p.state = TC.PState.ACTIVE
				await _end(mc)
	UIKit.emulation = orig_emu
	t.get_tree().root.size = orig_size
	await _frames(2)
