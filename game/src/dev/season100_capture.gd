extends Node
## Development-only evidence for the Pass 9 Season Pass (100 tiers; src/dev:
## never exported).  Runs the real Season Pass at a device size with the
## TEST DOUBLE service (src/dev/fake_commerce_service.gd; every picture is
## stamped "Dev fixture · test-double service (not the live service)") and
## the shipped service-off state:
##   01  a regular player mid-season (Premium, Season XP for Tier 43, tier
##       40 earned and not claimed): the pass opens on the Challenges page
##       with the navigation row and the claimable tier 40
##   02  "You're at Tier 43": the progress run 41-44 and its detail
##   03  the Tier 50 shortcut: Record Breaker (locked, its lock reason)
##   04  the Tier 100 shortcut: Dr. Doom (locked)
##   05  tier 40 Premium ready to claim (the one Claim, and Claim all)
##   06  the same reward claimed
##   07  a free player at Tier 52: Record Breaker reached but Premium-locked
##   08  the same player: tier 50 Free (Record Pace badge) claimable
##   09  a finished pass (Tier 100, everything claimed): Dr. Doom claimed
##   10  a claim waiting for the service (network down): "Claiming…"
##   11  an older game service (catalogue version 2, 30 tiers): tier 50
##       earned, "the game service hasn't been updated for this tier"
##   12  (only while the skins' art isn't in the build) the featured-skin
##       preview path with a STAND-IN: Glow Jogger as a featured tier, its
##       face on the milestone chip and the live, turning preview; labelled
##   20  service off (the shipped state): honest preview, milestones work
## The two skins' art comes from the SKINS9 stream: until it is merged the
## pass shows their neutral picture and says "Preview not available in this
## build."; with the art it shows the real portraits and the live preview.
## Besides each PNG it writes measure.json: the final allocated rects of the
## navigation row and its chips, both reward rows, the progress runs in
## view, the side panel, the detail action, and every pressable control cut
## off where no scrolling can bring it back.  Layout evidence on desktop
## Linux (llvmpipe): not device input, timing or a live service.
##
##   tools/capture_pass9_season.sh OUT_DIR [se p14 pmax ipad]

const FakeService := preload("res://src/dev/fake_commerce_service.gd")
const TestStore := preload("res://src/dev/test_store_adapter.gd")
const MenusCapture := preload("res://src/dev/menus_capture.gd")
const FIXTURE := "Dev fixture · test-double service (not the live service) · desktop render"

var out_dir := ""
var svc
var measures := {}
var _tag: Label
## --only=12: re-take one shot (the others' measurements are kept)
var only := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture-dir="):
			out_dir = a.get_slice("=", 1)
		if a.begins_with("--only="):
			only = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(out_dir)
	if only != "" and FileAccess.file_exists(out_dir.path_join("measure.json")):
		var old: Variant = JSON.parse_string(FileAccess.get_file_as_string(out_dir.path_join("measure.json")))
		if old is Dictionary:
			measures = old
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
	if not (scr is SeasonScreen):
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
	var sp := scr as SeasonScreen
	var track: Rect2 = sp.track_scroll.get_global_rect()
	m["header_tier"] = sp.tier_lbl.text
	m["header_xp"] = sp.xp_lbl.text
	m["nav_row"] = _r(sp.nav_row)
	var chips: Array = [sp.now_chip, sp.next_chip]
	for k in sp.milestone_chips:
		chips.append(sp.milestone_chips[k])
	m["nav_chips"] = chips.map(func(c: SeasonScreen.NavChip) -> Dictionary: return {"name": String(c.name), "rect": _r(c),
		"text": "%s / %s" % [c.top_l.text, c.main_l.text], "whole_in_safe": safe.grow(0.6).encloses(c.get_global_rect()),
		"touch_ok": c.get_global_rect().size.y >= UIKit.touch_min() - 0.5 and c.get_global_rect().size.x >= UIKit.touch_min() - 0.5})
	for row in ["free", "premium"]:
		var top := INF
		var bottom := -INF
		var h := 0.0
		var w := 0.0
		for c in sp.cells:
			var r: Rect2 = (c as Control).get_global_rect()
			if String(c.track) != row or r.end.x <= track.position.x or r.position.x >= track.end.x:
				continue
			top = minf(top, r.position.y)
			bottom = maxf(bottom, r.end.y)
			h = r.size.y
			w = r.size.x
		m[row + "_row"] = {"top": snappedf(top, 0.1), "bottom": snappedf(bottom, 0.1), "cell": [snappedf(w, 0.1), snappedf(h, 0.1)],
			"inside_safe": bottom <= safe.end.y + 0.5, "inside_track": bottom <= track.end.y + 0.5}
	var shown_runs: Array = []
	for run in sp.runs:
		var rr: Rect2 = (run as Control).get_global_rect()
		if rr.end.x > track.position.x and rr.position.x < track.end.x:
			shown_runs.append({"tiers": "%d-%d" % [run.first, run.last], "rect": _r(run)})
	m["runs_in_view"] = shown_runs
	m["focus"] = [sp.focus_tier, sp.focus_track, sp.display_state(sp.focus_tier, sp.focus_track) if sp.focus_track != "progress" else "progress"]
	m["side_page"] = sp.side_page
	m["side_panel"] = _r(sp.detail_panel)
	m["claim_all"] = sp.claim_all_btn.text if sp.claim_all_btn.is_visible_in_tree() else ""
	if sp.side_page == "reward":
		var act := sp._d["action"] as Button
		m["detail"] = {"over": (sp._d["over"] as Label).text, "name": (sp._d["name"] as Label).text, "state": (sp._d["state"] as Label).text,
			"reason": (sp._d["reason"] as Label).text, "blurb": (sp._d["blurb"] as Label).text, "includes": (sp._d["includes"] as Label).text,
			"note": (sp._d["note"] as Label).text, "action": act.text if act.visible else "", "action_disabled": act.disabled,
			"action_rect": _r(act) if act.visible else [], "action_in_safe": safe.grow(0.6).encloses(act.get_global_rect()) if act.visible else true}
	return m


# ------------------------------------------------------------------ states
func _setup_profile() -> void:
	Save.data = Save.migrate({"version": 3, "uid": "local-capture", "name": "Sleepy Otter", "coins": 0, "level": 6, "xp": 40,
		"owned": [], "onboarded": true, "tutorial_done": true,
		"cosmetic": {"schema": 2, "outfit": "pj", "hat": "nightcap", "shoes": "slippers", "color": "sky", "hair": "tuft", "skin": "tone4"},
		"stats": {"online": {"matches": 14}, "practice": {"matches": 6}}, "settings": {}})
	Save.data["onboarded"] = true


func _online(gc: String) -> String:
	if svc == null:
		svc = FakeService.new()
		svc.install()
		Purchases.use_adapter(TestStore.new())
	svc.gc_player = gc
	Cloud.token = ""
	await Cloud.sign_in()
	return Cloud.profile_id()


## Everything of tiers 1..`upto` claimed (rewards granted as a settled pass
## would have left them), except `skip` cells ("40:premium").
func _claimed_through(pid: String, upto: int, premium: bool, skip: Array = []) -> void:
	var s1: Dictionary = svc.wallet(pid)["season"]["s1"]
	var claimed: Array = []
	for t in Catalogue.season_tiers("s1"):
		var n := int(t["tier"])
		if n > upto:
			break
		for track in ["free", "premium"]:
			if track == "premium" and not premium:
				continue
			var r := Economy.reward_at("s1", n, track)
			var key := Economy.claim_key(n, track)
			if r.is_empty() or skip.has(key):
				continue
			claimed.append(key)
			if r.has("item"):
				svc.wallet(pid)["entitlements"][String(r["item"])] = {"source": "season"}
	s1["claimed"] = claimed


func _set_season(pid: String, xp: int, premium: bool) -> void:
	var s1: Dictionary = svc.wallet(pid)["season"]["s1"]
	s1["xp"] = xp
	s1["premium"] = premium
	if premium:
		svc.wallet(pid)["entitlements"]["season:s1:premium"] = {"source": "coin_purchase"}
	else:
		svc.wallet(pid)["entitlements"].erase("season:s1:premium")


func _pass(shot: String, prep: Callable = Callable()) -> void:
	if only != "" and not shot.begins_with(only + "_"):
		return
	if not (App.screen is SeasonScreen):
		NavShell.open("pass")
		await _wait(1.4)
	await _portraits_idle()
	var sp := App.screen as SeasonScreen
	if prep.is_valid():
		await prep.call(sp)
	await _wait(0.7)
	await _portraits_idle()
	await snap(shot)


## Reopen the pass (a new player state).
func _reopen() -> void:
	App.goto_title()
	await _wait(0.8)
	NavShell.open("pass")
	await _wait(1.4)


func _portraits_idle(max_s: float = 15.0) -> void:
	var t := 0.0
	while t < max_s:
		var ps := Portraits.shared()
		if ps.pending() == 0 and not ps._busy:
			break
		await get_tree().process_frame
		t += get_process_delta_time()
	await _wait(0.35)


func _run() -> void:
	await _wait(0.5)
	_setup_profile()
	# ------------------------------------------------------------------ a regular player mid-season
	var pid := await _online("T:_regular")
	svc.grant(pid, 640)
	_set_season(pid, 13000, true)            # Tier 43 (tier 45 at 13,550)
	_claimed_through(pid, 43, true, ["40:free", "40:premium"])
	await Wallet.refresh()
	App.goto_title()
	await _wait(1.5)
	_label(FIXTURE)
	await _pass("01_svcon_test_pass_open_tier43")
	await _pass("02_svcon_test_nav_current_run", func(sp: SeasonScreen) -> void:
		sp.jump_current()
		await _wait(0.6))
	await _pass("03_svcon_test_milestone_50_record_breaker", func(sp: SeasonScreen) -> void:
		sp.jump_to(50)
		await _wait(0.6))
	await _pass("04_svcon_test_milestone_100_dr_doom", func(sp: SeasonScreen) -> void:
		sp.jump_to(100)
		await _wait(0.6))
	await _pass("05_svcon_test_tier40_claimable", func(sp: SeasonScreen) -> void:
		sp.jump_to(40)
		await _wait(0.4)
		sp.focus(40, "premium")
		await _wait(0.2))
	await _pass("06_svcon_test_tier40_claimed", func(sp: SeasonScreen) -> void:
		sp._on_detail_action()
		for i in 120:
			if sp.display_state(40, "premium") == "claimed":
				break
			await get_tree().process_frame
		await _wait(2.2))     # the toast fades
	# ------------------------------------------------------------------ a free player at tier 52
	pid = await _online("T:_free")
	_set_season(pid, 16000, false)           # Tier 52
	_claimed_through(pid, 45, false)
	await Wallet.refresh()
	await _reopen()
	await _pass("07_svcon_test_free_tier52_record_breaker_premium_locked", func(sp: SeasonScreen) -> void:
		sp.jump_to(50)
		await _wait(0.6))
	await _pass("08_svcon_test_free_tier50_badge_claimable", func(sp: SeasonScreen) -> void:
		sp.focus(50, "free")
		await _wait(0.2))
	# ------------------------------------------------------------------ a finished pass
	pid = await _online("T:_finished")
	_set_season(pid, 33200, true)
	_claimed_through(pid, 100, true)
	await Wallet.refresh()
	await _reopen()
	await _pass("09_svcon_test_tier100_dr_doom_claimed", func(sp: SeasonScreen) -> void:
		sp.jump_to(100)
		await _wait(0.6))
	# ------------------------------------------------------------------ a claim waiting for the service
	pid = await _online("T:_offline")
	_set_season(pid, 15400, true)            # Tier 50
	_claimed_through(pid, 45, true)
	await Wallet.refresh()
	await _reopen()
	await _pass("10_svcon_test_claim_pending", func(sp: SeasonScreen) -> void:
		sp.jump_to(50)
		await _wait(0.6)
		# the claim is sent while the network is down: it stays queued (the
		# screen's own path would also say so in a dialog)
		svc.network_down = true
		await Wallet.claim("s1", [{"tier": 50, "track": "premium"}])
		sp._refresh()
		sp.focus(50, "premium")
		await _wait(0.3))
	svc.network_down = false
	# ------------------------------------------------------------------ an older game service
	pid = await _online("T:_legacy")
	svc.legacy_tiers = 30
	_set_season(pid, 15400, true)
	_claimed_through(pid, 30, true)
	await Wallet.refresh()
	await _reopen()
	_label(FIXTURE + " · acting as an older (30-tier) service")
	await _pass("11_svcon_test_old_service_tier50", func(sp: SeasonScreen) -> void:
		sp.jump_to(50)
		await _wait(0.6))
	svc.legacy_tiers = 0
	# ------------------------------------------------------------------ the live preview path, with a stand-in
	# The two skins' art isn't in this branch: the featured-preview path is
	# shown with Glow Jogger (Premium 15), labelled as a stand-in.
	var season: Dictionary = Catalogue.season("s1")
	var keep_f: Array = season["featured"].duplicate()
	var keep_m: Array = season["milestones"].duplicate()
	if not Catalogue.has_art("outfit:record_breaker"):
		season["featured"] = [15, 50, 100]
		season["milestones"] = [15, 50, 100]
		pid = await _online("T:_standin")
		_set_season(pid, 3400, true)
		await Wallet.refresh()
		await _reopen()
		_label(FIXTURE + " · STAND-IN: Glow Jogger shows the featured-skin preview path (the two skins' art is not in this branch)")
		await _pass("12_svcon_test_featured_preview_path_standin", func(sp: SeasonScreen) -> void:
			sp.jump_to(15)
			await _wait(1.6))
		season["featured"] = keep_f
		season["milestones"] = keep_m
	# ------------------------------------------------------------------ service off (the shipped state)
	FakeService.uninstall()
	Purchases.use_adapter(StoreAdapter.new())
	Wallet.state = Wallet.blank_state()
	await _reopen()
	_label("Service off (as shipped): preview only · desktop render")
	await _pass("20_svcoff_pass_preview")
	await _pass("21_svcoff_milestone_100", func(sp: SeasonScreen) -> void:
		sp.jump_to(100)
		await _wait(0.6))
	printerr("CAPTURE-DONE")
	get_tree().quit()
