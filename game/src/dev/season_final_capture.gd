extends Node
## Development-only evidence for the final release sweep's Season Pass
## (docs/final/season.md; src/dev: never exported).  Runs the real Season
## Pass at a device size and measures the selected skin's figure on screen.
##
##   --set=before   the state the owner's screenshot shows (service off, as
##                  1.9 ships: "Rewards unavailable right now", Record Breaker
##                  selected) plus Dr. Doom and a mid-season test-double
##                  account; works on the pre-sweep screen too, so the same
##                  scene measures both
##   --set=after    the same states on the rebuilt screen and the full matrix
##                  (tier 1, a progress run, 30, 50, 100; Free-only and
##                  Premium; locked / earned / pending / claimed; service off,
##                  failed sign-in, offline, an older 30-tier service and the
##                  live TEST-DOUBLE service)
##
## Every service-on picture uses the TEST-DOUBLE service
## (src/dev/fake_commerce_service.gd) and says so on the picture and in its
## name (svcon_test); svcoff is the shipped state (no service URL).  Desktop
## Linux, Mobile renderer on llvmpipe: layout and look, never frame rate,
## touch feel or a device.
##
## measure.json per shot: the figure's projected height (top of the visible
## parts' bounds to the soles, at the model's centre line) in canvas units
## and iOS points, where it is drawn, and every pressable control cut off
## where no scrolling brings it back.
##
##   tools/capture_final_season.sh OUT_DIR before|after [se p14 pmax ipad]

const FakeService := preload("res://src/dev/fake_commerce_service.gd")
const TestStore := preload("res://src/dev/test_store_adapter.gd")
const MenusCapture := preload("res://src/dev/menus_capture.gd")
const FIXTURE := "Dev fixture · test-double service (not the live service) · desktop render"
const SVC_OFF := "Service off (as shipped in 1.9): preview only · desktop render"

var out_dir := ""
var shot_set := "before"
var only := ""
var svc
var measures := {}
var _tag: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture-dir="):
			out_dir = a.get_slice("=", 1)
		elif a.begins_with("--set="):
			shot_set = a.get_slice("=", 1)
		elif a.begins_with("--only="):
			only = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	_tag = Label.new()
	_tag.add_theme_font_size_override("font_size", 15)
	_tag.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_tag.add_theme_constant_override("outline_size", 4)
	_tag.position = Vector2(8, 0)
	layer.add_child(_tag)
	_run.call_deferred()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _label(t: String) -> void:
	_tag.text = t
	_tag.position.y = get_viewport().get_visible_rect().size.y - 22.0


func _wanted(shot: String) -> bool:
	return only == "" or Array(only.split(",")).any(func(o: String) -> bool: return shot.begins_with(o))


func snap(shot: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(shot + ".png"))
	measures[shot] = _measure()
	var f := FileAccess.open(out_dir.path_join("measure.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(measures, "  ", false))
		f.close()
	var fig: Dictionary = measures[shot].get("figure", {})
	printerr("CAPTURE %s %dx%d figure %s pt" % [shot, img.get_width(), img.get_height(), fig.get("height_pt", "-")])


# ------------------------------------------------------------------ measuring
## The figure wearing a featured skin, wherever the screen draws it: a live
## preview inside the screen (its own SubViewport) or the dorm stage behind
## the menus.  Height: the visible parts' bounds (rest pose) from the top to
## the soles, projected at the model's centre line.
func _figure() -> Dictionary:
	var cands: Array = []
	var scr: Node = App.screen
	if scr != null and is_instance_valid(scr):
		cands.append_array(scr.find_children("*", "CharacterView", true, false))
	if App.stage != null and is_instance_valid(App.stage):
		for k in App.stage.chars:
			cands.append(App.stage.chars[k])
	for c in cands:
		var cv := c as CharacterView
		if cv == null or not is_instance_valid(cv) or not cv.visible or not cv.is_inside_tree():
			continue
		var outfit := String(cv.cosmetic.get("outfit", ""))
		if not (outfit in ["record_breaker", "dr_doom"]):
			continue
		var host: Control = null
		var n: Node = cv
		while n != null:
			if n is Preview3D:
				host = n
				break
			n = n.get_parent()
		if host != null and not host.is_visible_in_tree():
			continue
		var box := AABB()
		var first := true
		for mi in cv.visible_parts:
			if not is_instance_valid(mi) or not mi.visible:
				continue
			var b: AABB = mi.global_transform * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
		if first:
			continue
		var cam := cv.get_viewport().get_camera_3d()
		var mid := box.get_center()
		var top := cam.unproject_position(Vector3(mid.x, box.end.y, mid.z))
		var bot := cam.unproject_position(Vector3(mid.x, box.position.y, mid.z))
		var side_l := cam.unproject_position(Vector3(box.position.x, mid.y, mid.z))
		var side_r := cam.unproject_position(Vector3(box.end.x, mid.y, mid.z))
		if host != null:
			# SubViewport pixels -> the preview control's rect (canvas units)
			var vs := Vector2((host as Preview3D).vp.size)
			var hr := host.get_global_rect()
			var k := hr.size / vs
			top = hr.position + top * k
			bot = hr.position + bot * k
			side_l = hr.position + side_l * k
			side_r = hr.position + side_r * k
		var upp := UIKit.units_per_point()
		var h := bot.y - top.y
		return {"skin": outfit, "where": "preview" if host != null else "stage", "height_units": snappedf(h, 0.1),
			"height_pt": snappedf(h / upp, 0.1), "model_height_m": snappedf(box.size.y, 0.001),
			"top_y": snappedf(top.y, 0.1), "feet_y": snappedf(bot.y, 0.1), "centre_x": snappedf((top.x + bot.x) * 0.5, 0.1),
			"width_units_rest": snappedf(absf(side_r.x - side_l.x), 0.1), "host_rect": MenusCapture._r(host) if host != null else [],
			"units_per_pt": snappedf(upp, 0.001), "yaw": snappedf(cv.rotation.y, 0.001)}
	return {}


func _measure() -> Dictionary:
	var m := {}
	var view := get_viewport().get_visible_rect()
	m["view"] = [view.size.x, view.size.y]
	var safe := UIKit.safe_rect(get_viewport(), view.size)
	m["safe"] = [safe.position.x, safe.position.y, safe.size.x, safe.size.y]
	m["touch_min"] = UIKit.touch_min()
	m["units_per_pt"] = UIKit.units_per_point()
	m["figure"] = _figure()
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
			cut.append({"name": String(b.name), "rect": MenusCapture._r(b), "visible": snappedf(frac, 0.01)})
		if not safe.grow(0.6).encloses(r) and not bool(cl["scrolls"]):
			cut.append({"name": String(b.name), "rect": MenusCapture._r(b), "outside_safe": true})
	m["pressables_cut_off"] = cut
	var sp := scr as SeasonScreen
	m["focus"] = [sp.focus_tier, sp.focus_track]
	m["header_tier"] = sp.tier_lbl.text
	m["header_xp"] = sp.xp_lbl.text
	var cells_in_view: Array = []
	var track: Rect2 = sp.track_scroll.get_global_rect()
	for c in sp.cells:
		var r: Rect2 = (c as Control).get_global_rect()
		if r.end.x > track.position.x and r.position.x < track.end.x:
			cells_in_view.append(r)
	if not cells_in_view.is_empty():
		var c0: Rect2 = cells_in_view[0]
		m["cell"] = [snappedf(c0.size.x, 0.1), snappedf(c0.size.y, 0.1)]
		m["cells_in_view"] = cells_in_view.size()
	m["track"] = MenusCapture._r(sp.track_scroll)
	if sp.has_method("card_texts"):
		m["card"] = sp.call("card_texts")
	elif "_d" in sp and not (sp._d as Dictionary).is_empty():
		var d: Dictionary = sp._d
		m["detail"] = {"over": (d["over"] as Label).text, "name": (d["name"] as Label).text, "state": (d["state"] as Label).text,
			"reason": (d["reason"] as Label).text, "action": (d["action"] as Button).text if (d["action"] as Button).visible else ""}
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


func _service_off() -> void:
	if svc != null:
		FakeService.uninstall()
		Purchases.use_adapter(StoreAdapter.new())
		svc = null
	Wallet.state = Wallet.blank_state()


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


func _portraits_idle(max_s: float = 15.0) -> void:
	var t := 0.0
	while t < max_s:
		var ps := Portraits.shared()
		if ps.pending() == 0 and not ps._busy:
			break
		await get_tree().process_frame
		t += get_process_delta_time()
	await _wait(0.35)


## Open (or reopen) the pass for a new player state.
func _open() -> void:
	App.goto_title()
	await _wait(0.8)
	NavShell.open("pass")
	await _wait(1.6)
	await _portraits_idle()


## One shot: `prep` sets the screen up, then the frame settles and is saved.
func _shot(shot: String, prep: Callable = Callable(), settle: float = 0.9) -> void:
	if not _wanted(shot):
		return
	if not (App.screen is SeasonScreen):
		await _open()
	var sp := App.screen as SeasonScreen
	if prep.is_valid():
		await prep.call(sp)
	await _wait(settle)
	await _portraits_idle()
	_still(sp)
	await snap(shot)


## The rebuilt screen's slow sway (before the first touch) is caught at its
## start so each picture shows the three-quarter start pose.
func _still(sp: SeasonScreen) -> void:
	if is_instance_valid(sp) and "turn" in sp and sp.get("turn") != null:
		(sp.get("turn") as Object).set("_phase", 0.0)


func _run() -> void:
	await _wait(0.5)
	_setup_profile()
	if shot_set == "before":
		await _run_before()
	else:
		await _run_after()
	printerr("CAPTURE-DONE")
	get_tree().quit()


## The owner's screenshot state and its neighbours, on whichever screen this
## build has (only the shared API: focus / jump_to).
func _run_before() -> void:
	_service_off()
	_label(SVC_OFF)
	await _open()
	await _shot("b01_svcoff_tier1_open")
	await _shot("b02_svcoff_tier1_record_breaker", func(sp: SeasonScreen) -> void:
		sp.jump_to(50)
		await _wait(0.8), 2.0)
	await _shot("b03_svcoff_tier1_dr_doom", func(sp: SeasonScreen) -> void:
		sp.jump_to(100)
		await _wait(0.8), 2.0)
	var pid := await _online("T:_regular")
	svc.grant(pid, 640)
	_set_season(pid, 13000, true)            # Tier 43, Premium
	_claimed_through(pid, 43, true, ["40:free", "40:premium"])
	await Wallet.refresh()
	_label(FIXTURE)
	await _open()
	await _shot("b04_svcon_test_tier43_record_breaker", func(sp: SeasonScreen) -> void:
		sp.jump_to(50)
		await _wait(0.8), 2.0)


func _run_after() -> void:
	await _run_before()
