extends Node
## Development-only evidence for the V7 menus pass (src/dev: never exported).
## Runs the real Locker (Outfit, Emotes, Hat, Shoes, Profile), Season Pass
## (first / middle / last tier, Free and Premium selected) and Shop
## (sections, detail, Coin confirmation) at a device size, then the real
## service-off state.  The service-on shots use the TEST ADAPTERS (the
## test-double service and the simulated store: "(test price)"), and every
## file name says which state it shows (svcon_test = test adapters,
## svcoff = no service, as the shipped build).
##
## Besides each PNG it writes measure.json: the final allocated rects (not
## custom_minimum_size) of the Pass rows, the detail action, Claim all, the
## Locker panel, its cards, their art wells and emote glyph bounds, the
## Save/Undo row, the category strip and every pressable control that is
## cut off by the viewport or by a non-scrolling parent.
##
##   tools/gd.sh --path game --resolution 2532x1170 res://src/dev/menus_capture.tscn -- \
##     --capture-dir=DIR --emulate-phone=3 --emulate-safe=47,0,47,21 --no-gamecenter
## (tools/capture_v7_menus.sh runs every device size.)

const FakeService := preload("res://src/dev/fake_commerce_service.gd")
const TestStore := preload("res://src/dev/test_store_adapter.gd")

var out_dir := ""
var only := ""
var svc
var store
var measures := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture-dir="):
			out_dir = a.get_slice("=", 1)
		elif a.begins_with("--only="):
			only = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _portraits_idle(max_s: float = 15.0) -> void:
	var t := 0.0
	while t < max_s:
		var ps := Portraits.shared()
		if ps.pending() == 0 and not ps._busy:
			break
		await get_tree().process_frame
		t += get_process_delta_time()
	await _wait(0.35)


func _wanted(shot: String) -> bool:
	return only == "" or Array(only.split(",")).any(func(o: String) -> bool: return shot.begins_with(o))


func snap(shot: String) -> void:
	if not _wanted(shot):
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(shot + ".png"))
	measures[shot] = _measure()
	_write_measures()
	printerr("CAPTURE %s %dx%d" % [shot, img.get_width(), img.get_height()])


## Written after every shot, so a run cut short keeps what it measured.
func _write_measures() -> void:
	var f := FileAccess.open(out_dir.path_join("measure.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(measures, "  ", false))
		f.close()


# ------------------------------------------------------------------ measuring
static func _r(c: Control) -> Array:
	var r := c.get_global_rect()
	return [snappedf(r.position.x, 0.1), snappedf(r.position.y, 0.1), snappedf(r.size.x, 0.1), snappedf(r.size.y, 0.1)]


## The rect a control can actually be seen in: the viewport, narrowed by
## every clipping ancestor.  `scrolls` is set when a ScrollContainer clips it.
static func _clip_of(c: Control) -> Dictionary:
	var vis := c.get_viewport().get_visible_rect()
	var scrolls := false
	var p := c.get_parent()
	while p != null:
		if p is Control:
			var pc := p as Control
			if pc is ScrollContainer or pc.clip_contents:
				vis = vis.intersection(pc.get_global_rect())
				if pc is ScrollContainer:
					scrolls = true
		p = p.get_parent()
	return {"rect": vis, "scrolls": scrolls}


func _measure() -> Dictionary:
	var scr: Control = App.screen
	var m := {}
	var view := get_viewport().get_visible_rect()
	m["view"] = [view.size.x, view.size.y]
	var safe := UIKit.safe_rect(get_viewport(), view.size)
	m["safe"] = [safe.position.x, safe.position.y, safe.size.x, safe.size.y]
	m["touch_min"] = UIKit.touch_min()
	if scr == null:
		return m
	# every pressable control cut off where no scrolling can bring it back
	var cut: Array = []
	var cut_in_list: Array = []
	for n in scr.find_children("*", "BaseButton", true, false):
		var b := n as BaseButton
		if not b.is_visible_in_tree():
			continue
		var r := b.get_global_rect()
		if r.size.x < 1.0 or r.size.y < 1.0:
			continue
		var cl := _clip_of(b)
		var inter: Rect2 = r.intersection(cl["rect"])
		var frac := (inter.size.x * inter.size.y) / (r.size.x * r.size.y) if inter.has_area() else 0.0
		if frac < 0.995:
			var row := {"name": String(b.name), "text": String(b.get("text")) if b.get("text") != null else "", "rect": _r(b), "visible": snappedf(frac, 0.01)}
			if bool(cl["scrolls"]) and view.encloses(cl["rect"].grow(-0.5)):
				cut_in_list.append(row)
			else:
				cut.append(row)
	m["pressables_cut_off"] = cut
	m["pressables_partly_in_list"] = cut_in_list.size()
	if scr is SeasonScreen:
		_measure_pass(scr as SeasonScreen, m)
	elif scr is CreatorScreen:
		_measure_locker(scr as CreatorScreen, m)
	elif scr is ShopScreen:
		_measure_shop(scr as ShopScreen, m)
	return m


func _measure_pass(sp: SeasonScreen, m: Dictionary) -> void:
	var view := get_viewport().get_visible_rect()
	var track: Rect2 = sp.track_scroll.get_global_rect()
	m["track_scroll"] = _r(sp.track_scroll)
	for row in ["free", "premium"]:
		var top := INF
		var bottom := -INF
		var shown := 0
		var whole := 0
		var h := 0.0
		for c in sp.cells:
			if String(c.track) != row:
				continue
			var r: Rect2 = (c as Control).get_global_rect()
			h = r.size.y
			if r.end.x <= track.position.x or r.position.x >= track.end.x:
				continue    # scrolled sideways out of view
			shown += 1
			top = minf(top, r.position.y)
			bottom = maxf(bottom, r.end.y)
			if track.encloses(r) or (r.position.y >= track.position.y - 0.5 and r.end.y <= track.end.y + 0.5 and r.end.y <= view.end.y + 0.5):
				if r.end.y <= view.end.y + 0.5:
					whole += 1
		m[row + "_row"] = {"top": snappedf(top, 0.1), "bottom": snappedf(bottom, 0.1), "cell_h": snappedf(h, 0.1), "columns_in_view": shown,
			"vertically_whole": whole, "inside_viewport": bottom <= view.end.y + 0.5, "inside_track": bottom <= track.end.y + 0.5}
	var act: Variant = sp._d.get("action") if sp._d.has("action") else null
	if act != null and is_instance_valid(act) and (act as Control).is_visible_in_tree():
		var ar := (act as Control).get_global_rect()
		var cl: Rect2 = _clip_of(act)["rect"]
		m["detail_action"] = {"rect": _r(act), "text": (act as Button).text, "disabled": (act as Button).disabled,
			"inside_viewport": view.encloses(ar.grow(-0.5)), "fully_visible": cl.encloses(ar.grow(-0.5))}
	else:
		m["detail_action"] = {"shown": false}
	if is_instance_valid(sp.claim_all_btn):
		m["claim_all"] = {"rect": _r(sp.claim_all_btn), "text": sp.claim_all_btn.text, "disabled": sp.claim_all_btn.disabled,
			"visible": sp.claim_all_btn.is_visible_in_tree()}
	var dp := sp.find_child("DetailPanel", true, false) as Control
	if dp:
		m["detail_panel"] = _r(dp)
	m["focus"] = [sp.focus_tier, sp.focus_track]
	var st_l: Variant = sp._d.get("state")
	if st_l is Label:
		m["detail_state_text"] = (st_l as Label).text
	if sp.banner != null and is_instance_valid(sp.banner):
		m["banner"] = sp.banner.text if sp.banner.is_visible_in_tree() else ""


func _measure_locker(c: CreatorScreen, m: Dictionary) -> void:
	m["tab"] = c.tab
	m["panel"] = _r(c.panel)
	m["scroll"] = _r(c.scroll)
	m["apply_btn"] = {"rect": _r(c.apply_btn), "text": c.apply_btn.text, "disabled": c.apply_btn.disabled, "visible": c.apply_btn.is_visible_in_tree()}
	m["undo_btn"] = {"rect": _r(c.undo_btn), "visible": c.undo_btn.is_visible_in_tree()}
	if is_instance_valid(c._stage_area):
		m["stage_area"] = _r(c._stage_area)
	var tabs := []
	var strip_clip := Rect2()
	for k in c.tab_btns:
		var b := c.tab_btns[k] as Control
		var cl: Rect2 = _clip_of(b)["rect"]
		strip_clip = cl
		tabs.append({"tab": k, "rect": _r(b), "whole": cl.encloses(b.get_global_rect().grow(-0.5))})
	m["categories"] = tabs
	var cards := []
	var art_outside := []
	for card in c.cards:
		var cr := (card as Control).get_global_rect()
		var row := {"key": String(card.key), "rect": _r(card)}
		var holder: Variant = card.get("holder")
		if holder is Control:
			var hr := (holder as Control).get_global_rect()
			row["well"] = _r(holder)
			# every drawn child of the well (an emote glyph, a picture)
			for ch in (holder as Control).get_children():
				if ch is Control and (ch as Control).visible:
					var gr := (ch as Control).get_global_rect()
					row["art"] = _r(ch)
					if not hr.grow(0.5).encloses(gr) or not cr.grow(0.5).encloses(gr):
						art_outside.append({"key": String(card.key), "well": _r(holder), "art": _r(ch)})
		cards.append(row)
	m["cards"] = cards
	m["card_count"] = cards.size()
	m["art_outside_well"] = art_outside
	var grid: Control = null
	for card in c.cards:
		grid = (card as Control).get_parent() as Control
		break
	if grid is GridContainer:
		m["columns"] = (grid as GridContainer).columns
		m["grid"] = _r(grid)
	m["discover"] = c.discover.map(func(b: Control) -> Dictionary: return {"rect": _r(b), "text": String(b.accessibility_name)})


func _measure_shop(s: ShopScreen, m: Dictionary) -> void:
	m["section"] = s.section
	m["panel"] = _r(s.panel)
	m["scroll"] = _r(s.scroll)
	var cards := []
	for c in s.cards:
		if is_instance_valid(c):
			cards.append({"id": String(c.id), "rect": _r(c)})
	m["cards"] = cards
	if s.detail != null and s._d.has("action"):
		var a: Button = s._d["action"]
		var view := get_viewport().get_visible_rect()
		m["detail_action"] = {"rect": _r(a), "text": a.text, "disabled": a.disabled, "inside_viewport": view.encloses(a.get_global_rect().grow(-0.5))}
	if s.banner != null:
		m["banner"] = s.banner.text if s.banner.is_visible_in_tree() else ""


# ------------------------------------------------------------------ states
func _setup_profile() -> void:
	# the owner's situation: the default look (pajamas, nightcap, bunny
	# slippers), a few pre-V6 unlocks on this device
	Save.data = Save.migrate({"version": 3, "uid": "local-capture", "name": "Sleepy Otter", "coins": 345, "level": 6, "xp": 40,
		"owned": ["outfit:robe", "outfit:frog", "hat:crown", "color:plum", "emote:dance"], "onboarded": true, "tutorial_done": true,
		"cosmetic": {"schema": 2, "outfit": "pj", "hat": "nightcap", "shoes": "slippers", "color": "sky", "hair": "tuft", "skin": "tone4"},
		"stats": {"online": {"matches": 14}, "practice": {"matches": 6}}, "settings": {}})
	Save.data["onboarded"] = true


func _online() -> void:
	svc = FakeService.new()
	svc.install()
	store = TestStore.new()
	Purchases.use_adapter(store)
	svc.gc_player = "T:_capture"
	await Cloud.sign_in()
	var pid := Cloud.profile_id()
	svc.grant(pid, 1650)
	var s1: Dictionary = svc.wallet(pid)["season"]["s1"]
	s1["xp"] = 3450        # tier 15 (the middle of the original 30 tiers)
	s1["claimed"] = ["1:free", "3:free", "5:free", "9:free"]
	for id in ["card:after_hours", "hat:pompom_beanie", "emote:stargaze", "outfit:after_hours_hoodie"]:
		svc.wallet(pid)["entitlements"][id] = {"source": "season"}
	await Wallet.refresh()
	await _wait(0.5)
	Save.set_profile_style("card", "card:after_hours")


func _pass_shots(base: int, state: String) -> void:
	NavShell.open("pass")
	await _wait(1.2)
	await _portraits_idle()
	var sp := App.screen as SeasonScreen
	var i := 0
	for spec in [["first", 1], ["mid", 15], ["last", 30]]:
		var tier: int = spec[1]
		for track in ["free", "premium"]:
			var shot := "%d_%s_pass_%s_%s" % [base + i, state, spec[0], track]
			i += 1
			if not _wanted(shot):
				continue
			sp.focus(tier, track)
			var col: Control = sp.columns[tier]
			var max_h := sp.track_scroll.get_h_scroll_bar().max_value - sp.track_scroll.size.x
			sp.track_scroll.scroll_horizontal = int(clampf(col.position.x - sp.track_scroll.size.x * 0.35, 0.0, maxf(0.0, max_h)))
			await _wait(0.5)
			await _portraits_idle()
			await snap(shot)


func _run() -> void:
	await _wait(0.5)
	_setup_profile()
	await _online()
	App.goto_title()
	await _wait(1.5)
	# --------------------------------------------------------------- Locker
	NavShell.open("locker")
	await _wait(1.0)
	await _portraits_idle()
	await snap("01_svcon_test_locker_outfit")
	var lk := App.screen as CreatorScreen
	for spec in [["move", "02_svcon_test_locker_emotes"], ["hat", "04_svcon_test_locker_hat"], ["shoes", "05_svcon_test_locker_shoes"],
			["face", "06_svcon_test_locker_face"], ["profile", "07_svcon_test_locker_profile"]]:
		if not _wanted(String(spec[1])) and not (spec[0] == "move" and _wanted("03_")):
			continue
		lk._select_tab(String(spec[0]))
		await _wait(0.5)
		await _portraits_idle()
		await snap(String(spec[1]))
		if spec[0] == "move":
			lk._pick("emote", "stargaze")
			await _wait(0.6)
			await snap("03_svcon_test_locker_emote_selected")
	lk._on_cancel()
	await _wait(0.3)
	# --------------------------------------------------------------- Pass
	await _pass_shots(10, "svcon_test")
	# --------------------------------------------------------------- Shop
	NavShell.open("shop")
	await _wait(1.0)
	await _portraits_idle()
	await snap("20_svcon_test_shop_featured")
	var shop := App.screen as ShopScreen
	for spec in [["outfits", "21_svcon_test_shop_outfits"], ["accessories", "22_svcon_test_shop_accessories"], ["coins", "23_svcon_test_shop_coins"]]:
		if not _wanted(String(spec[1])):
			continue
		shop.select_section(String(spec[0]))
		await _wait(0.5)
		await _portraits_idle()
		await snap(String(spec[1]))
	shop.select_section("outfits")
	await _wait(0.4)
	shop._open_detail("outfit:lantern_scout" if Catalogue.has("outfit:lantern_scout") and Catalogue.has_art("outfit:lantern_scout") else "outfit:duck")
	await _wait(0.8)
	await _portraits_idle()
	await snap("24_svcon_test_shop_detail_outfit")
	shop._close_detail()
	shop.select_section("accessories")
	await _wait(0.3)
	shop._open_detail("hat:headphones")
	await _wait(0.6)
	await _portraits_idle()
	await snap("25_svcon_test_shop_detail_hat")
	shop._confirm_spend("hat:headphones")
	await _wait(0.5)
	await snap("26_svcon_test_shop_coin_confirmation")
	for ch in App.screen.get_children():
		if ch.name == "ConfirmSpend" or ch is ColorRect:
			ch.queue_free()
	await _wait(0.3)
	shop._close_detail()
	# --------------------------------------------------------------- Pass with Premium (late unlock)
	var pid := Cloud.profile_id()
	svc.wallet(pid)["season"]["s1"]["premium"] = true
	svc.wallet(pid)["entitlements"]["season:s1:premium"] = {"source": "coin_purchase"}
	await Wallet.refresh()
	await _wait(0.3)
	NavShell.open("pass")
	await _wait(1.0)
	var sp2 := App.screen as SeasonScreen
	sp2.focus(4, "premium")
	sp2.track_scroll.scroll_horizontal = 0
	await _wait(0.5)
	await _portraits_idle()
	await snap("16_svcon_test_pass_premium_owned_claimable")
	# --------------------------------------------------------------- service off (the shipped state)
	FakeService.uninstall()
	Purchases.use_adapter(StoreAdapter.new())
	Wallet.state = Wallet.blank_state()
	await _pass_shots(30, "svcoff")
	NavShell.open("shop")
	await _wait(1.0)
	await _portraits_idle()
	await snap("40_svcoff_shop_featured")
	shop = App.screen as ShopScreen
	shop.select_section("outfits")
	await _wait(0.4)
	shop._open_detail("outfit:robe")
	await _wait(0.6)
	await _portraits_idle()
	await snap("41_svcoff_shop_detail_owned")
	shop._close_detail()
	shop._open_detail("outfit:duck")
	await _wait(0.6)
	await _portraits_idle()
	await snap("42_svcoff_shop_detail")
	NavShell.open("locker")
	await _wait(1.0)
	(App.screen as CreatorScreen)._select_tab("move")
	await _wait(0.5)
	await snap("43_svcoff_locker_emotes")
	_write_measures()
	printerr("CAPTURE-DONE")
	get_tree().quit()
