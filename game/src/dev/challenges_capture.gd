extends Node
## Development-only evidence for the Pass 8 challenges (src/dev: never
## exported).  Runs the real Season Pass and results screens at a device
## size:
##   01-04  service on with the TEST DOUBLE (src/dev/fake_commerce_service.gd,
##          labelled "svcon_test" and stamped on the picture): the Challenges
##          page with progress, a completed goal and a pin; scrolled to the
##          weekly goals; a tapped reward (the Reward page) with the track
##          unchanged; the pass with Premium.
##   05-06  results: a settled round that completed Campus Contribution
##          ("Campus Contribution complete · +50 Season XP", then the Season
##          tier bar) and a pending one (the confirmation not answered yet).
##   07     practice results: training feedback only.
##   10     service off (the shipped state): an honest preview.
## Besides each PNG it writes measure.json: the final allocated rects of
## the pass rows, the side panel, its tabs, the Challenges page and cards,
## the results' challenge lines, and every pressable control cut off where
## no scrolling can bring it back.  Layout evidence on desktop Linux
## (llvmpipe): not device input, timing or a live service.
##
##   tools/capture_pass8_challenges.sh OUT_DIR [se p14 pmax ipad]

const FakeService := preload("res://src/dev/fake_commerce_service.gd")
const TestStore := preload("res://src/dev/test_store_adapter.gd")
const MenusCapture := preload("res://src/dev/menus_capture.gd")

var out_dir := ""
var svc
var measures := {}
var _tag: Label
var _host: NetSession


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture-dir="):
			out_dir = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	_tag = Label.new()
	_tag.add_theme_font_size_override("font_size", 15)
	_tag.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_tag.add_theme_constant_override("outline_size", 4)
	_tag.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_tag.position = Vector2(8, 0)
	layer.add_child(_tag)
	_run.call_deferred()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _label(t: String) -> void:
	_tag.text = t
	_tag.position.y = get_viewport().get_visible_rect().size.y - 22.0


func snap(shot: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(shot + ".png"))
	measures[shot] = _measure()
	var f := FileAccess.open(out_dir.path_join("measure.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(measures, "  ", false))
		f.close()
	printerr("CAPTURE %s %dx%d" % [shot, img.get_width(), img.get_height()])


static func _r(c: Control) -> Array:
	return MenusCapture._r(c)


func _measure() -> Dictionary:
	var m := {}
	var view := get_viewport().get_visible_rect()
	m["view"] = [view.size.x, view.size.y]
	var safe := UIKit.safe_rect(get_viewport(), view.size)
	m["safe"] = [safe.position.x, safe.position.y, safe.size.x, safe.size.y]
	m["touch_min"] = UIKit.touch_min()
	var scr: Control = App.screen
	if scr == null:
		return m
	var cut: Array = []
	for n in scr.find_children("*", "BaseButton", true, false):
		var b := n as BaseButton
		if not b.is_visible_in_tree():
			continue
		var r := b.get_global_rect()
		var cl: Dictionary = MenusCapture._clip_of(b)
		var inter: Rect2 = r.intersection(cl["rect"])
		var frac := (inter.size.x * inter.size.y) / maxf(1.0, r.size.x * r.size.y) if inter.has_area() else 0.0
		if frac < 0.995 and not (bool(cl["scrolls"]) and view.encloses((cl["rect"] as Rect2).grow(-0.5))):
			cut.append({"name": String(b.name), "rect": _r(b), "visible": snappedf(frac, 0.01)})
	m["pressables_cut_off"] = cut
	if scr is SeasonScreen:
		var sp := scr as SeasonScreen
		var track: Rect2 = sp.track_scroll.get_global_rect()
		for row in ["free", "premium"]:
			var top := INF
			var bottom := -INF
			var h := 0.0
			for c in sp.cells:
				var r: Rect2 = (c as Control).get_global_rect()
				if String(c.track) != row or r.end.x <= track.position.x or r.position.x >= track.end.x:
					continue
				top = minf(top, r.position.y)
				bottom = maxf(bottom, r.end.y)
				h = r.size.y
			m[row + "_row"] = {"top": snappedf(top, 0.1), "bottom": snappedf(bottom, 0.1), "cell_h": snappedf(h, 0.1),
				"inside_safe": bottom <= safe.end.y + 0.5, "inside_track": bottom <= track.end.y + 0.5}
		m["side_page"] = sp.side_page
		m["side_panel"] = _r(sp.detail_panel)
		m["tabs"] = sp._tabs.keys().map(func(k: String) -> Dictionary: return {"tab": k, "rect": _r(sp._tabs[k])})
		m["claim_all_visible"] = sp.claim_all_btn.is_visible_in_tree()
		if sp.challenge_page.is_visible_in_tree():
			m["challenge_page"] = _r(sp.challenge_page)
			var list := sp._ch["scroll"] as Control
			m["challenge_list"] = _r(list)
			m["challenge_status"] = (sp._ch["status"] as Label).text if (sp._ch["status"] as Label).visible else ""
			m["challenge_cards"] = sp.challenge_cards.map(func(cc) -> Dictionary: return {"id": cc.id, "rect": _r(cc),
				"whole_in_list": list.get_global_rect().grow(0.5).encloses((cc as Control).get_global_rect()),
				"count": cc.count_l.text if cc.count_l.visible else "", "xp": cc.xp_l.text, "pinned": UIKit.face_of(cc).selected})
			m["groups"] = (sp._ch["groups"] as Dictionary).keys().map(func(k: String) -> String: return (sp._ch["groups"][k] as Label).text)
	elif scr is ResultsScreen:
		var lines: Array = []
		for n in scr.find_children("Challenge*", "Control", true, false):
			var c := n as Control
			var txt := ""
			if c is Label:
				txt = (c as Label).text
			else:
				for l in c.find_children("*", "Label", true, false):
					txt = (l as Label).text
			lines.append({"name": String(c.name), "text": txt, "rect": _r(c)})
		m["challenge_lines"] = lines
		m["challenges"] = Wallet.round_summary(String((scr as ResultsScreen).results.get("match_id", ""))).get("challenges", {})
	return m


# ------------------------------------------------------------------ states
func _setup_profile() -> void:
	Save.data = Save.migrate({"version": 3, "uid": "local-capture", "name": "Sleepy Otter", "coins": 0, "level": 6, "xp": 40,
		"owned": [], "onboarded": true, "tutorial_done": true,
		"cosmetic": {"schema": 2, "outfit": "pj", "hat": "nightcap", "shoes": "slippers", "color": "sky", "hair": "tuft", "skin": "tone4"},
		"stats": {"online": {"matches": 14}, "practice": {"matches": 6}}, "settings": {}})
	Save.data["onboarded"] = true


func _online() -> void:
	svc = FakeService.new()
	svc.install()
	Purchases.use_adapter(TestStore.new())
	svc.gc_player = "T:_capture"
	await Cloud.sign_in()
	var pid := Cloud.profile_id()
	svc.grant(pid, 1650)
	var s1: Dictionary = svc.wallet(pid)["season"]["s1"]
	s1["xp"] = 3450        # tier 15 (of 100 since Pass 9)
	s1["claimed"] = ["1:free", "3:free", "5:free", "9:free"]
	for id in ["card:after_hours", "hat:pompom_beanie", "emote:stargaze", "outfit:after_hours_hoodie"]:
		svc.wallet(pid)["entitlements"][id] = {"source": "season"}
	# the challenge fixture (as settled rounds would have left it)
	svc.set_challenge(pid, "night_shift", 1, false)
	svc.set_challenge(pid, "campus_contribution", 4, false)
	svc.set_challenge(pid, "team_effort", 1, false)
	svc.set_challenge(pid, "campus_regular", 6, false)
	svc.set_challenge(pid, "pull_your_weight", 11, false)
	svc.set_challenge(pid, "strong_together", 2, false)
	await Wallet.refresh()
	Wallet.pin_challenge("campus_contribution")
	await _wait(0.4)


func _pass(shot: String, prep: Callable = Callable()) -> void:
	NavShell.open("pass")
	await _wait(1.4)
	await _portraits_idle()
	var sp := App.screen as SeasonScreen
	if prep.is_valid():
		await prep.call(sp)
	await _wait(0.6)
	await _portraits_idle()
	await snap(shot)


func _portraits_idle(max_s: float = 15.0) -> void:
	var t := 0.0
	while t < max_s:
		var ps := Portraits.shared()
		if ps.pending() == 0 and not ps._busy:
			break
		await get_tree().process_frame
		t += get_process_delta_time()
	await _wait(0.35)


func _rows(me: String, my_stamps: int, active: int) -> Array:
	var names := ["Sleepy Otter", "Pip", "Rowan", "Snooze", "Biscuit", "Marigold Moonpup"]
	var out: Array = []
	for i in names.size():
		var bot := i in [3, 4]
		var runner := i not in [2, 5]
		var r := {"slot": i, "uid": me if i == 0 else ("friend-%d" % i if not bot else "bot-%d" % i), "name": names[i], "is_bot": bot,
			"role": TC.Role.RUNNER if runner else TC.Role.PATROL, "present": true, "away_s": 0.0, "active_s": 0 if bot else 150,
			"coins_picked": 1 if i == 0 else 0, "cosmetic": Cosmetics.bot_cosmetic(31 + i * 7)}
		if runner:
			r["stamps"] = my_stamps if i == 0 else [3, 3, 0, 2, 3, 3][i]
			r["finished"] = i in [0, 1, 4] and (i != 0 or my_stamps == 3)
			r["finish_order"] = {0: 2, 1: 1, 4: 3}.get(i, 0)
			r["finish_time"] = {0: 141.0, 1: 128.0, 4: 171.0}.get(i, -1.0)
			r["times_captured"] = [1, 0, 0, 2, 1, 0][i]
		else:
			r["captures"] = 3
			r["unique_captures"] = 2
		out.append(r)
	out[0]["cosmetic"] = Save.data["cosmetic"]
	out[0]["active_s"] = active
	return out


func _round_results(mid: String, practice: bool = false) -> Dictionary:
	return {"match_id": mid, "outcome": TC.Outcome.RUNNERS_WIN, "players": _rows(Save.player_uid(), 3, 150), "fastest_slot": 1,
		"finished": 3, "needed": 3, "watch": 2, "round_time": 171.0, "coin_spawns": 8, "practice": practice, "round_index": 1, "rounds_total": 3}


## Scrolls the results sheet to the end of the rewards card (its challenge
## lines and the Season progress), as a player would.
func _to_rewards() -> void:
	var r := App.screen as ResultsScreen
	if r == null:
		return
	r._sc.scroll_vertical = int(r._sc.get_v_scroll_bar().max_value)
	await _wait(0.4)


func _show_results(res: Dictionary, practice: bool) -> void:
	var s: NetSession = NetSession.new()
	add_child(s)
	if practice:
		s.start_offline(Save.player_uid(), Save.player_name(), Save.data["cosmetic"], "runner")
	else:
		s.mode = NetSession.Mode.HOST
		s.local_slot = 0
	var r := ResultsScreen.new()
	r.results = res
	r.reward = {}
	r.session = s
	App._ensure_background()
	App._show(r)


## A party round reported by the host and confirmed by this game (through
## the test double); `answer` false keeps the confirmation unanswered.
func _settle(mid: String, answer: bool) -> Dictionary:
	var pid := Cloud.profile_id()
	var res := _round_results(mid)
	var me: Dictionary = res["players"][0]
	var guest: String = svc._pid_for("T:_friend")
	svc.rounds[mid] = {"host": pid, "participants": {pid: 0, guest: 1}, "acks": {}, "settled": {}, "started_at": svc._now_ms(),
		"report": {"report_version": 2, "outcome": res["outcome"], "round_time_s": res["round_time"], "coin_spawns": 8, "players": [
			{"profile_id": pid, "slot": 0, "role": 0, "stamps": 3, "finished": true, "first_home": false, "unique_captures": 0, "coins_picked": 1,
				"present": true, "away_s": 0.0, "active_s": 150}]}}
	App.party_code = "CAPTURE"
	svc.network_down = not answer
	Wallet.settle_round(res, me, false)
	if answer:
		for i in 120:
			if String(Wallet.round_summary(mid)["state"]) == "settled":
				break
			await get_tree().process_frame
	return res


func _run() -> void:
	await _wait(0.5)
	_setup_profile()
	await _online()
	App.goto_title()
	await _wait(1.5)
	# --------------------------------------------------------------- Season Pass, service on (test double)
	_label("Dev fixture · test-double service (not the live service)")
	await _pass("01_svcon_test_pass_challenges")
	await _pass("02_svcon_test_pass_challenges_weekly", func(sp: SeasonScreen) -> void:
		var sc := sp._ch["scroll"] as ScrollContainer
		sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)
		await _wait(0.2))
	await _pass("03_svcon_test_pass_reward_detail", func(sp: SeasonScreen) -> void:
		sp._on_cell(15, "free")
		await _wait(0.2))
	# --------------------------------------------------------------- results
	var res := await _settle("CAPTURE-1-0000c0de", true)
	_show_results(res, false)
	await _wait(2.4)
	await _portraits_idle()
	await _to_rewards()
	await snap("05_svcon_test_results_challenge_settled")
	var res2 := await _settle("CAPTURE-2-0000c0de", false)
	_show_results(res2, false)
	await _wait(2.4)
	await _portraits_idle()
	await _to_rewards()
	await snap("06_svcon_test_results_challenge_pending")
	svc.network_down = false
	App.party_code = ""
	var pr := _round_results("practice-cap", true)
	Save.apply_results(pr, 0, true, Save.player_uid())
	_show_results(pr, true)
	await _wait(2.4)
	await _portraits_idle()
	_label("Practice (offline): training feedback only")
	await _to_rewards()
	await snap("07_practice_results_training")
	# --------------------------------------------------------------- the pass after the settled round
	_label("Dev fixture · test-double service (not the live service)")
	await _pass("04_svcon_test_pass_after_round")
	# --------------------------------------------------------------- service off (the shipped state)
	FakeService.uninstall()
	Purchases.use_adapter(StoreAdapter.new())
	Wallet.state = Wallet.blank_state()
	_label("Service off (as shipped): preview only")
	await _pass("10_svcoff_pass_challenges_preview")
	printerr("CAPTURE-DONE")
	get_tree().quit()
