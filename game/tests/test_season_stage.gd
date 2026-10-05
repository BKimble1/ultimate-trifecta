extends RefCounted
## Final release sweep (docs/final/season.md): the Season Pass shows the
## selected reward on the dorm stage, in the Shop / Locker language.
##  - touch ownership: a sideways drag on the stage turns the model, a
##    vertical drag or a tap doesn't, a second finger never takes over, the
##    turn is released on lift, hiding, losing focus or a sheet opening; a
##    swipe on the track scrolls it and never turns the model; a vertical
##    swipe on the description scrolls it;
##  - no automatic motion fights the player: the sway stops at the first
##    turn and never runs under Reduced Motion; Turn / Reset and the
##    controller are the alternatives to dragging;
##  - previewing never saves: a locked skin on the stage leaves the saved
##    look, the inventory and the wallet alone, and the saved look is back
##    on the runner after Back, any tab, the hub and before a round starts;
##  - every reward state reads differently (locked, Premium-locked,
##    claimable, earned while claiming is unavailable, claiming, an older
##    service, claimed, equipped) and a locked reward never looks claimable;
##  - the layout fits the iPhone SE, 844x390, 926x428 and the iPad with
##    the figure at least twice the old preview's height on the phones.
var t
var rig
var _saved := {}

const DEVICES := {
	"se_667x375": [Vector2i(1334, 750), 2.0, Rect2(0, 0, 0, 0)],
	"p14_844x390": [Vector2i(2532, 1170), 3.0, Rect2(47, 0, 47, 21)],
	"max_926x428": [Vector2i(2778, 1284), 3.0, Rect2(47, 0, 47, 21)],
	"ipad_1024x768": [Vector2i(2048, 1536), 2.0, Rect2(0, 24, 0, 20)],
}
## the old side preview's figure, measured by tools/capture_final_season.sh
## (before) with the same projection as _figure() below, in points
const OLD_FIGURE_PT := {"se_667x375": 70.4, "p14_844x390": 70.1, "max_926x428": 79.9, "ipad_1024x768": 206.3}


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
	# the project's own setting: a pointer on desktop is also a finger (the
	# lists' drag scrolling and the stage's touch turn both see it)
	Input.emulate_touch_from_mouse = true
	Controls.device = "touch"
	Save.data["onboarded"] = true
	Save.set_setting("reduced_motion", false)
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
	App.goto_title()
	await _frames(2)
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


## Canvas units to window pixels (touch events arrive in window pixels).
func _px(p: Vector2) -> Vector2:
	return t.get_tree().root.get_final_transform() * p


## A real finger on iOS: the touch event, then the mouse event the engine
## emulates from it (Input.parse_input_event does that emulation).
func _touch(i: int, at: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = _px(at)
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _drag(i: int, from: Vector2, to: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = i
	e.position = _px(to)
	e.relative = _px(to) - _px(from)
	Input.parse_input_event(e)
	Input.flush_buffered_events()


## A pointer press / release and moves through Input (the engine turns
## them into touches too, as on desktop with emulate_touch_from_mouse).
func _press(at: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = _px(at)
	e.global_position = e.position
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _move(from: Vector2, to: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = _px(to)
	e.global_position = e.position
	e.relative = _px(to) - _px(from)
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(e)
	Input.flush_buffered_events()


## A whole one-finger swipe in `steps` moves, a frame apart.
func _swipe(from: Vector2, to: Vector2, steps: int = 10, lift: bool = true) -> void:
	_press(from, true)
	await _frames(1)
	var p := from
	for k in steps:
		var q := from.lerp(to, float(k + 1) / float(steps))
		_move(p, q)
		p = q
		await _frames(1)
	if lift:
		_press(to, false)
		await _frames(2)


## Season XP for `tier`, Premium or not, everything up to `claimed_to` claimed.
func _account(tier: int, premium: bool, claimed_to: int = 0) -> void:
	var pid := Cloud.profile_id()
	var w: Dictionary = rig.svc.wallet(pid)
	w["season"]["s1"]["xp"] = Economy.tier_xp("s1", tier)
	w["season"]["s1"]["premium"] = premium
	if premium:
		w["entitlements"]["season:s1:premium"] = {"source": "coin_purchase"}
	var claimed: Array = []
	for tr in Catalogue.season_tiers("s1"):
		if int(tr["tier"]) > claimed_to:
			break
		for track in ["free", "premium"]:
			var r := Economy.reward_at("s1", int(tr["tier"]), track)
			if r.is_empty() or (track == "premium" and not premium):
				continue
			claimed.append(Economy.claim_key(int(tr["tier"]), track))
			if r.has("item"):
				w["entitlements"][String(r["item"])] = {"source": "season"}
	w["season"]["s1"]["claimed"] = claimed
	await Wallet.refresh()


func _open() -> SeasonScreen:
	App.goto(SeasonScreen)
	await _frames(10)
	return App.screen as SeasonScreen


## The figure on the stage: its projected height (the visible parts'
## bounds, top to soles at the model's centre line) in canvas units and its
## top / bottom / centre on screen.
func _figure() -> Dictionary:
	var v := App.stage.local_character()
	var box := AABB()
	var first := true
	for mi in v.visible_parts:
		if not is_instance_valid(mi) or not mi.visible:
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var cam := App.stage.cam
	var mid := box.get_center()
	var top := cam.unproject_position(Vector3(mid.x, box.end.y, mid.z))
	var bot := cam.unproject_position(Vector3(mid.x, box.position.y, mid.z))
	return {"h": bot.y - top.y, "top": top.y, "bottom": bot.y, "x": (top.x + bot.x) * 0.5}


# ------------------------------------------------------------------ StageTurn alone
## The turn control on its own (no screen): what a finger may and may not do.
func test_one_sideways_finger_owns_the_turn() -> void:
	var saved_emulate := Input.emulate_touch_from_mouse
	var saved_size: Vector2i = t.get_tree().root.size
	var saved_rm: bool = Save.get_setting("reduced_motion", false)
	Input.emulate_touch_from_mouse = false
	Save.set_setting("reduced_motion", false)
	t.get_tree().root.size = Vector2i(1280, 720)
	var layer := CanvasLayer.new()
	layer.layer = 120
	t.add_child(layer)
	var area := StageTurn.new()
	area.position = Vector2(100, 100)
	area.size = Vector2(400, 400)
	layer.add_child(area)
	await _frames(2)
	var dz := TouchScroll.deadzone()
	# a tap: nothing
	_touch(0, Vector2(300, 300), true)
	_touch(0, Vector2(300, 300), false)
	await _frames(1)
	t.eq(area.offset, 0.0, "a tap doesn't turn")
	t.check(not area.touched, "and isn't a turn")
	# a small wobble inside the dead zone: nothing
	_touch(0, Vector2(300, 300), true)
	_drag(0, Vector2(300, 300), Vector2(300 + dz * 0.6, 300))
	_touch(0, Vector2(300 + dz * 0.6, 300), false)
	t.eq(area.offset, 0.0, "a wobble inside the touch dead zone doesn't turn")
	# a vertical drag: never a turn, even if it then goes sideways
	_touch(0, Vector2(300, 200), true)
	_drag(0, Vector2(300, 200), Vector2(302, 260))
	_drag(0, Vector2(302, 260), Vector2(380, 270))
	_touch(0, Vector2(380, 270), false)
	t.eq(area.offset, 0.0, "a vertical drag doesn't turn")
	# a sideways drag turns, at the Locker's rate, from where it passed the dead zone
	_touch(0, Vector2(200, 300), true)
	var p := Vector2(200, 300)
	for k in 6:
		var q := p + Vector2(20, 1)
		_drag(0, p, q)
		p = q
	t.check(area.dragging and area.touched, "the sideways finger owns the turn")
	t.near(area.offset, 100.0 * StageTurn.RAD_PER_UNIT, 0.02, "the turn follows the finger (%.3f)" % area.offset)
	var before := area.offset
	# a second finger: neither its touch nor its drags turn
	_touch(1, Vector2(450, 300), true)
	_drag(1, Vector2(450, 300), Vector2(350, 300))
	t.near(area.offset, before, 0.0001, "a second finger does nothing")
	_touch(1, Vector2(350, 300), false)
	# the finger leaves the area: it keeps turning until it lifts
	_drag(0, p, p + Vector2(100, 0))
	t.check(area.offset > before, "a drag that leaves the area keeps turning (%.2f > %.2f)" % [area.offset, before])
	_touch(0, p + Vector2(100, 0), false)
	t.check(not area.dragging, "lifting releases")
	var after := area.offset
	_drag(0, p, p + Vector2(60, 0))
	t.near(area.offset, after, 0.0001, "after lifting, nothing turns")
	# hiding the area mid-drag releases it
	_touch(0, Vector2(200, 300), true)
	_drag(0, Vector2(200, 300), Vector2(240, 300))
	_drag(0, Vector2(240, 300), Vector2(260, 300))
	t.check(area.dragging, "a new drag")
	area.visible = false
	t.check(not area.dragging, "hidden: released")
	area.visible = true
	var held := area.offset
	_drag(0, Vector2(260, 300), Vector2(320, 300))
	t.near(area.offset, held, 0.0001, "and the old finger doesn't come back")
	_touch(0, Vector2(320, 300), false)
	# the app going to the background mid-drag releases it
	_touch(0, Vector2(200, 300), true)
	_drag(0, Vector2(200, 300), Vector2(240, 300))
	_drag(0, Vector2(240, 300), Vector2(260, 300))
	area.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	t.check(not area.dragging, "backgrounded: released")
	_touch(0, Vector2(260, 300), false)
	# no target: a 2D picture has nothing to turn
	area.enabled = false
	var off := area.offset
	_touch(0, Vector2(200, 300), true)
	_drag(0, Vector2(200, 300), Vector2(260, 300))
	_drag(0, Vector2(260, 300), Vector2(320, 300))
	_touch(0, Vector2(320, 300), false)
	t.near(area.offset, off, 0.0001, "disabled: nothing turns")
	layer.queue_free()
	Input.emulate_touch_from_mouse = saved_emulate
	t.get_tree().root.size = saved_size
	Save.set_setting("reduced_motion", saved_rm)
	await _frames(1)


## The sway stops for good at the first touch and never runs under Reduced
## Motion; Turn and Reset glide (Reduced Motion: at once) and land exactly.
func test_no_automatic_motion_fights_the_player() -> void:
	var saved_rm: bool = Save.get_setting("reduced_motion", false)
	Save.set_setting("reduced_motion", false)
	var area := StageTurn.new()
	t.add_child(area)
	await _frames(1)
	var s0 := area.sway()
	await _frames(20)
	t.check(not is_equal_approx(area.sway(), s0), "a slow sway before anyone touches it")
	t.check(absf(area.sway()) <= StageTurn.SWAY + 0.001, "a small one")
	t.near(area.facing(1.0), 1.0 + area.sway(), 0.0001, "the facing is the start pose plus the sway")
	Save.set_setting("reduced_motion", true)
	t.eq(area.sway(), 0.0, "Reduced Motion: no automatic motion")
	Save.set_setting("reduced_motion", false)
	area.step(1)
	t.check(area.touched and area.sway() == 0.0, "the first step ends the sway for good")
	await _frames(60)
	t.near(area.offset, StageTurn.STEP, 0.01, "a quarter turn, glided")
	await _frames(20)
	t.near(area.offset, StageTurn.STEP, 0.0001, "and it stays put")
	t.check(not area.at_start(), "not at the start pose")
	area.reset()
	await _frames(60)
	t.check(area.at_start(), "Reset: back to the three-quarter start pose")
	Save.set_setting("reduced_motion", true)
	area.step(-1)
	t.near(area.offset, -StageTurn.STEP, 0.0001, "Reduced Motion: a step lands at once")
	area.reset()
	t.near(area.offset, 0.0, 0.0001, "and so does Reset")
	Save.set_setting("reduced_motion", saved_rm)
	area.queue_free()


# ------------------------------------------------------------------ the screen
## Touch ownership on the real screen: a sideways swipe on the stage turns
## the model and selects nothing; a swipe on the track scrolls it and never
## turns the model; a vertical swipe on the description scrolls it; the
## Turn tool steps; R3 resets; a sheet opening releases a drag.
func test_touch_ownership_on_the_season_pass() -> void:
	await _begin()
	await _account(43, false, 43)
	await _device("se_667x375")
	var sp := await _open()
	sp.jump_to(50)
	await _frames(30)
	t.eq(sp.preview_id, "outfit:record_breaker", "Record Breaker on the stage")
	var v := App.stage.local_character()
	var zone := sp.turn.get_global_rect()
	var c := zone.get_center()
	var sel := [sp.focus_tier, sp.focus_track]
	var scroll0 := sp.track_scroll.scroll_horizontal
	# sideways on the stage: turns it
	await _swipe(c, c + Vector2(160, 4))
	t.check(sp.turn.touched and absf(sp.turn.offset) > 1.0, "the stage drag turned the model (%.2f)" % sp.turn.offset)
	t.eq([sp.focus_tier, sp.focus_track], sel, "and selected nothing")
	t.eq(sp.track_scroll.scroll_horizontal, scroll0, "nor scrolled the track")
	await _frames(2)
	var yaw := v.rotation.y
	await _frames(20)
	t.near(v.rotation.y, yaw, 0.0001, "the model stays where the player turned it (no sway)")
	# vertical on the stage: nothing
	var off := sp.turn.offset
	await _swipe(c, c + Vector2(4, 140))
	t.near(sp.turn.offset, off, 0.0001, "a vertical drag on the stage doesn't turn it")
	# a swipe on the track scrolls it and doesn't turn the model
	var cell: Control = sp._cell(55, "free")
	var tr := sp.track_scroll.get_global_rect()
	var at := Vector2(clampf(cell.get_global_rect().get_center().x, tr.position.x + 40.0, tr.end.x - 40.0), cell.get_global_rect().get_center().y)
	var s1 := sp.track_scroll.scroll_horizontal
	await _swipe(at, at + Vector2(-260, 3), 12)
	await _frames(20)
	t.check(sp.track_scroll.scroll_horizontal > s1 + 60, "the track scrolled (%d -> %d)" % [s1, sp.track_scroll.scroll_horizontal])
	t.near(sp.turn.offset, off, 0.0001, "a track swipe never turns the model")
	t.eq([sp.focus_tier, sp.focus_track], sel, "nor selects a reward")
	# a vertical swipe on the description scrolls it (Dr. Doom's includes run
	# long under its requirements and View Premium)
	sp.jump_to(100)
	await _frames(30)
	var info := sp._d["scroll"] as ScrollContainer
	await _frames(2)
	var room := info.get_v_scroll_bar().max_value - info.size.y
	t.check(room > 8.0, "on the iPhone SE Dr. Doom's description runs past the panel (%.0f more)" % room)
	var ic := info.get_global_rect().get_center()
	await _swipe(ic, ic + Vector2(2, -120), 10)
	await _frames(20)
	t.check(info.scroll_vertical > 10, "the description scrolled by finger (%d)" % info.scroll_vertical)
	t.check((sp._d["action"] as Control).is_visible_in_tree() and _inside((sp._d["action"] as Control).get_global_rect(), _safe()), "the action stays put")
	t.near(sp.turn.offset, off, 0.0001, "and the model didn't turn")
	# the Turn tool steps a quarter (an alternative to dragging)
	var o2 := sp.turn.offset
	sp.turn_btn.pressed.emit()
	await _frames(60)
	t.near(wrapf(sp.turn.offset - o2, -PI, PI), StageTurn.STEP, 0.02, "Turn: a quarter turn")
	t.check(not sp.reset_btn.disabled, "Reset available once turned")
	# controller: R3 resets
	var r3 := InputEventJoypadButton.new()
	r3.button_index = JOY_BUTTON_RIGHT_STICK
	r3.pressed = true
	sp._unhandled_input(r3)
	await _frames(60)
	t.check(sp.turn.at_start(), "R3: back to the start pose")
	t.check(sp.reset_btn.disabled, "Reset quiet at the start pose")
	# the shoulders switch the side panel's pages
	var nxt := InputEventAction.new()
	nxt.action = "menu_next"
	nxt.pressed = true
	sp._unhandled_input(nxt)
	t.eq(sp.side_page, "challenges", "a shoulder shows Challenges")
	sp._unhandled_input(nxt)
	t.eq(sp.side_page, "reward", "and back")
	# a sheet opening mid-drag releases the turn
	await _swipe(c, c + Vector2(60, 0), 3, false)
	t.check(sp.turn.dragging, "a drag in progress")
	sp.dialog("Test sheet")
	await _frames(2)
	t.check(not sp.turn.dragging, "a sheet opened: the turn let go")
	var o3 := sp.turn.offset
	_move(c + Vector2(60, 0), c + Vector2(160, 0))
	await _frames(1)
	t.near(sp.turn.offset, o3, 0.0001, "the old finger no longer turns it")
	_press(c + Vector2(160, 0), false)
	await _end()


## Previewing a locked skin never saves anything, and every way out puts the
## saved look back on the runner: Back, a navigation tab, the hub, another
## screen replacing it, and a round starting.
func test_previewing_never_saves_and_every_exit_restores_the_look() -> void:
	await _begin()
	await _account(10, false, 0)
	Save.data["cosmetic"] = Cosmetics.sanitize({"schema": 2, "outfit": "pj", "hat": "nightcap", "shoes": "slippers", "color": "sky"})
	var look: Dictionary = Save.data["cosmetic"].duplicate(true)
	var owned_before := Wallet.owns_id("outfit:record_breaker")
	var bal := Wallet.balance()
	var claimed_before: Dictionary = Wallet.season_state("s1")["claimed"].duplicate()
	t.check(not owned_before, "Record Breaker isn't owned")
	var exits := {
		"back": func(sp: SeasonScreen) -> void: sp._go_back(),
		"tab": func(_sp: SeasonScreen) -> void: NavShell.go("shop"),
		"locker": func(_sp: SeasonScreen) -> void: NavShell.go("locker"),
		"hub": func(_sp: SeasonScreen) -> void: NavShell.go("play"),
		"replaced": func(_sp: SeasonScreen) -> void: App.goto(ShopScreen),
	}
	for k in exits:
		var sp := await _open()
		sp.jump_to(50)
		await _frames(20)
		var v := App.stage.local_character()
		t.eq(String(v.cosmetic.get("outfit", "")), "record_breaker", "%s: the locked skin previewed on the stage" % k)
		sp.turn.turn_by(1.2)
		sp.preview_run = true
		await _frames(3)
		t.eq(Save.data["cosmetic"], look, "%s: previewing changed nothing saved" % k)
		(exits[k] as Callable).call(sp)
		await _frames(6)
		var v2 := App.stage.local_character()
		t.eq(v2.cosmetic, Cosmetics.sanitize(look), "%s: the saved look is back on the runner" % k)
		t.check(v2.visible, "%s: the runner is shown" % k)
		t.eq(Vector3(v2.rs.get("vel", Vector3.ZERO)), Vector3.ZERO, "%s: standing still" % k)
	t.eq(Save.data["cosmetic"], look, "the saved look never changed")
	t.eq(Wallet.owns_id("outfit:record_breaker"), owned_before, "nothing granted")
	t.eq(Wallet.balance(), bal, "no Coins moved")
	t.eq(Wallet.season_state("s1")["claimed"], claimed_before, "no claim made")
	# a round starting from a previewed state: the session carries the saved look
	var sp2 := await _open()
	sp2.jump_to(100)
	await _frames(20)
	t.eq(String(App.stage.local_character().cosmetic.get("outfit", "")), "dr_doom", "Dr. Doom previewed")
	App.start_practice("runner", false)
	await _frames(2)
	t.check(App.session != null and App.session.roster[0] is Dictionary, "a practice round is starting")
	t.eq(Cosmetics.sanitize(App.session.roster[0]["cosmetic"]), Cosmetics.sanitize(look), "the round gets the saved look, never the preview")
	t.check(App.stage == null, "the menu stage is gone for the round")
	var mc := App.match_ctrl
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(mc) and not mc.prepared and Time.get_ticks_msec() - t0 < 60000:
		await t.get_tree().process_frame
	App._close_session(false)
	App._end_match_scene()
	App.goto_title()
	await _frames(3)
	t.eq(App.stage.local_character().cosmetic, Cosmetics.sanitize(look), "back home: the saved look")
	MatchController.drop_campus_cache()
	await _end()


## Each reward state reads differently (chip word and icon, the action and
## whether it works), a locked reward never offers a claim, an earned one
## never looks lost while claiming is unavailable.
func test_reward_states_are_distinct() -> void:
	await _begin()
	await _account(52, false, 45)
	var sp := await _open()
	var seen := {}
	var read := func(tier: int, track: String) -> Array:
		sp.focus(tier, track)
		var chip: Variant = sp._d["chip"]
		var act := sp._d["action"] as Button
		return [sp.display_state(tier, track), String(chip.text_l.text), String(chip.icon.kind) if chip.icon.visible else "",
			act.text if act.visible else "", act.disabled if act.visible else true]
	var rows: Array = []
	rows.append(read.call(55, "free"))          # locked (Free)
	rows.append(read.call(55, "premium"))       # locked, needs Premium too
	rows.append(read.call(50, "premium"))       # reached, Premium-locked
	rows.append(read.call(50, "free"))          # claimable
	rows.append(read.call(45, "free"))          # claimed (Coins)
	for r in rows:
		seen[str(r.slice(1))] = r[0]
	t.eq(seen.size(), rows.size(), "five states, five different looks: %s" % [rows])
	var by := {}
	for r in rows:
		by[String(r[0])] = r
	t.eq(by["locked"][1], "Locked", "locked says so")
	t.check(not String(by["locked"][3]).begins_with("Claim"), "a locked reward never offers Claim")
	t.eq(String(rows[1][3]), "View Premium", "a locked Premium reward shows what it needs")
	t.eq(by["premium_locked"][1], "Needs Premium", "Premium-locked")
	t.eq(by["premium_locked"][3], "Get Premium", "and how to get it")
	t.eq([by["claimable"][1], by["claimable"][3], by["claimable"][4]], ["Ready to claim", "Claim", false], "claimable: one working Claim")
	t.eq(by["claimed"][1], "Claimed", "claimed")
	# claiming, then equip from the pass
	sp.focus(50, "free")
	sp._on_detail_action()
	t.eq((sp._d["action"] as Button).text, "Claim", "the claim is on its way")
	await rig.until(func() -> bool: return sp.display_state(50, "free") == "claimed")
	t.eq(String(sp._d["chip"].text_l.text), "Claimed", "claimed")
	t.eq((sp._d["action"] as Button).text, "Equip", "a claimed badge can be equipped from here")
	sp._on_detail_action()
	await _frames(2)
	t.eq(String(Save.profile_style()["badge"]), "badge:record_pace", "equipped (the Locker's own rule: owned only)")
	t.eq(String(sp._d["chip"].text_l.text), "Equipped", "the chip says so")
	t.eq((sp._d["action"] as Button).text, "View in Locker", "then it points to the Locker")
	# signed out: the states stay what they are, the reason is said once
	Cloud.token = ""
	Cloud.state = "signed_out"
	sp._refresh()
	sp.focus(50, "premium")
	t.eq(sp.display_state(50, "premium"), "premium_locked", "signed out: still Premium-locked")
	t.eq((sp._d["action"] as Button).text, "View Premium", "Premium can be looked at, not bought, signed out")
	t.check(sp.status_row.visible and sp.status_l.text.contains("Sign in with Game Center"), "signed out: one status line says why")
	t.check(not sp.claim_all_btn.visible, "no Claim all that can't work")
	await _end()


## Earned while claiming is unavailable, a claim on its way and an older
## service: three different, honest states.
func test_earned_pending_and_older_service_read_differently() -> void:
	await _begin()
	await _account(50, true, 45)
	var sp := await _open()
	# a claim on its way (the network dropped while it was sent)
	rig.svc.network_down = true
	await Wallet.claim("s1", [{"tier": 50, "track": "premium"}])
	rig.svc.network_down = false
	sp._refresh()
	sp.focus(50, "premium")
	t.eq(sp.display_state(50, "premium"), "pending", "pending")
	var pend := [String(sp._d["chip"].text_l.text), (sp._d["action"] as Button).text, (sp._d["action"] as Button).disabled]
	t.eq(pend, ["Claiming…", "Claiming…", true], "Claiming…, nothing to press")
	await Wallet.refresh()
	await rig.until(func() -> bool: return Wallet.pending_ops() == 0)
	# Game Center doesn't sign in: earned, kept, the reason on the status line
	Cloud.identity_override = func() -> Dictionary: return {"ok": false, "message": "Sign in to Game Center to play online."}
	Cloud.token = ""
	await Cloud.sign_in()
	sp._refresh()
	sp.focus(50, "free")
	t.eq(sp.display_state(50, "free"), "earned", "earned while claiming is unavailable")
	var earned := [String(sp._d["chip"].text_l.text), (sp._d["action"] as Button).text, (sp._d["action"] as Button).disabled]
	t.eq(earned, ["Earned", "Claim", true], "Earned, Claim visibly off")
	t.check((sp._d["state"] as Label).text.contains("It stays earned"), "it isn't lost")
	t.check(sp.status_l.text.contains("Game Center didn't sign in"), "the failed sign-in, said once: %s" % sp.status_l.text)
	# no network at launch: "offline"
	rig.svc.install()
	rig.svc.network_down = true
	Cloud.token = ""
	await Cloud.sign_in()
	sp._refresh()
	t.check(sp.status_l.text.contains("You're offline"), "no network: offline (%s)" % sp.status_l.text)
	rig.svc.network_down = false
	await rig.sign_in()
	# an older (30-tier) service: earned, not claimable here, said plainly
	rig.svc.legacy_tiers = 30
	await Wallet.refresh()
	sp._refresh()
	sp.focus(50, "free")
	t.eq(sp.display_state(50, "free"), "service_update", "older service")
	var old := [String(sp._d["chip"].text_l.text), (sp._d["action"] as Button).text, (sp._d["action"] as Button).disabled, (sp._d["reason"] as Label).text]
	t.check(old[0] == "Earned" and old[2] and String(old[3]).contains("isn't open yet"), "earned, Claim off, why: %s" % [old])
	t.check(old != earned and earned != pend, "three different reads")
	rig.svc.legacy_tiers = 0
	await _end()


## The layout at the four device shapes: the stage column, the side panel
## and the pass panel inside the safe area, the tools whole 44 pt targets,
## the figure head to soles inside its column with margins, and at least
## twice the old preview's height on the phones.
func test_stage_layout_fits_every_device() -> void:
	await _begin()
	await _account(43, true, 43)
	var report: Array = []
	for key in DEVICES:
		await _device(key)
		var sp := await _open()
		var safe := _safe()
		var tm := UIKit.touch_min()
		for skin in [50, 100]:
			sp.jump_to(skin)
			await _frames(30)
			var zone := sp.turn.get_global_rect()
			t.check(_inside(sp.fig_zone.get_global_rect(), safe), "%s: the stage column inside the safe area" % key)
			t.check(_inside(sp.detail_panel.get_global_rect(), safe), "%s: the side panel inside the safe area" % key)
			t.check(_inside(sp.track_panel.get_global_rect(), safe), "%s: the pass panel inside the safe area" % key)
			t.check(_inside(sp.track_panel.get_global_rect(), (sp.track_panel.get_parent() as Control).get_global_rect()),
				"%s: the pass panel inside its column (nothing widens it)" % key)
			t.check(sp.fig_zone.get_global_rect().end.x <= sp.detail_panel.get_global_rect().position.x + 0.5 and
				sp.detail_panel.get_global_rect().end.x <= sp.track_panel.get_global_rect().position.x + 0.5, "%s: three columns, no overlap" % key)
			for b in [sp.pose_btn, sp.turn_btn, sp.reset_btn]:
				var r := (b as Control).get_global_rect()
				t.check(_inside(r, safe) and _inside(r, sp.fig_zone.get_global_rect()), "%s: %s inside the stage column" % [key, b.name])
				t.check(r.size.x >= tm - 0.5 and r.size.y >= tm - 0.5, "%s: %s a whole 44 pt target" % [key, b.name])
				t.check(UIKit.v7_button_text_fits(b), "%s: %s's word whole" % [key, b.name])
			var f := _figure()
			var upp := UIKit.units_per_point()
			t.check(f["top"] >= zone.position.y - 0.5 and f["bottom"] <= zone.end.y + 0.5, "%s: tier %d head to soles inside the stage (%s in %s)" % [key, skin, f, zone])
			t.check(f["top"] >= safe.position.y + tm and f["bottom"] <= safe.end.y, "%s: below the top row, above the bottom edge" % key)
			t.check(f["x"] > zone.position.x and f["x"] < zone.end.x, "%s: centred in its column" % key)
			var pt: float = f["h"] / upp
			var old: float = OLD_FIGURE_PT[key]
			if key != "ipad_1024x768":
				t.check(pt >= old * 2.0, "%s: tier %d at least twice the old preview (%.0f pt vs %.0f pt)" % [key, skin, pt, old])
			else:
				t.check(pt >= old * 1.5, "%s: tier %d larger than the old preview (%.0f pt vs %.0f pt)" % [key, skin, pt, old])
			report.append("%s tier %d: figure %.0f pt (old %.0f), stage %s" % [key, skin, pt, old, zone])
		# the side panel's action and its page fit
		var act := sp._d["action"] as Control
		t.check(not act.visible or (_inside(act.get_global_rect(), safe) and act.get_global_rect().size.y >= tm - 0.5), "%s: the action on screen, 44 pt" % key)
		for k in sp._tabs:
			var tr := (sp._tabs[k] as Control).get_global_rect()
			t.check(_inside(tr, safe) and tr.size.y >= tm - 0.5 and tr.size.x >= tm - 0.5, "%s: the %s tab is a whole 44 pt target" % [key, k])
	for line in report:
		print("[season stage] " + line)
	await _end()
