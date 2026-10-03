extends Node
## Development-only evidence (src/dev: never exported): finger swipes on the
## real Locker, Shop, Season Pass and (with --results=path) Results screens,
## recorded with Godot's Movie Maker at a fixed 30 fps clock.
##
## Gestures are real InputEventScreenTouch / InputEventScreenDrag events
## (what iOS delivers; the engine emulates the mouse from them, as on a
## phone), parsed by Input, so they travel the whole GUI path.  A soft ring
## marks the finger.  Each swipe starts ON a card (picture or label), the
## way a thumb does; the clip shows the list moving, inertia, the tap that
## does select, and that lifting after a swipe selects/buys/claims nothing.
## The network is the TEST ADAPTERS (fake service, simulated store whose
## prices read "(test price)"), as in commerce_capture.gd.
##
##   tools/gd.sh --path game --resolution 1280x720 --write-movie OUT.avi --fixed-fps 30 \
##     res://src/dev/swipe_reel.tscn -- --emulate-phone=1.92 --no-gamecenter [--results=path]
## (tools/capture_v6_media.sh runs it and labels the MP4.)

const FakeService := preload("res://src/dev/fake_commerce_service.gd")
const TestStore := preload("res://src/dev/test_store_adapter.gd")
const FPS := 30.0

var svc
var store
var results_path := ""
var _finger: Control
var _finger_at := Vector2(-100, -100)
var _finger_down := false
var _log: PackedStringArray = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--results="):
			results_path = a.get_slice("=", 1)
	var layer := CanvasLayer.new()
	layer.layer = 128
	add_child(layer)
	_finger = Control.new()
	_finger.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_finger.set_anchors_preset(Control.PRESET_FULL_RECT)
	_finger.draw.connect(_draw_finger)
	layer.add_child(_finger)
	_run.call_deferred()


func _draw_finger() -> void:
	if _finger_at.x < 0.0:
		return
	var r := 26.0
	_finger.draw_circle(_finger_at, r, Color(1, 1, 1, 0.28 if _finger_down else 0.12))
	_finger.draw_arc(_finger_at, r, 0.0, TAU, 40, Color(1, 1, 1, 0.75 if _finger_down else 0.35), 2.5, true)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait(sec: float) -> void:
	await _frames(int(round(sec * FPS)))


func _mark(text: String) -> void:
	_log.append("%05d %s" % [Engine.get_process_frames(), text])
	printerr("REEL %s" % text)


func _touch(at: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = at
	e.pressed = down
	Input.parse_input_event(e)
	_finger_at = at
	_finger_down = down
	_finger.queue_redraw()


func _drag_to(from: Vector2, to: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = 0
	e.position = to
	e.relative = to - from
	e.velocity = (to - from) * FPS
	Input.parse_input_event(e)
	_finger_at = to
	_finger.queue_redraw()


## A thumb swipe: down, a short ease-in-out travel, up (the list carries on
## with its own inertia).
func swipe(from: Vector2, to: Vector2, secs: float = 0.28) -> void:
	_touch(from, true)
	await _frames(2)
	var n := maxi(2, int(round(secs * FPS)))
	var prev := from
	for i in n:
		var k := float(i + 1) / n
		var p := from.lerp(to, k * k * (3.0 - 2.0 * k))
		_drag_to(prev, p)
		prev = p
		await get_tree().process_frame
	_touch(to, false)
	await _frames(1)


func tap(at: Vector2) -> void:
	_touch(at, true)
	await _frames(3)
	_touch(at, false)
	await _frames(1)


func _hide_finger() -> void:
	_finger_at = Vector2(-100, -100)
	_finger.queue_redraw()


func _vp() -> Vector2:
	return get_viewport().get_visible_rect().size


## The centre of the first visible control of `type` whose rect contains a
## point of `sc` (a card to start a swipe on).
func _card_in(sc: ScrollContainer, type: String, along := 0.5) -> Vector2:
	var r := sc.get_global_rect()
	var best: Control = null
	for n in sc.find_children("*", type, true, false):
		var c := n as Control
		if c.is_visible_in_tree() and r.encloses(c.get_global_rect()):
			if best == null or c.get_global_rect().position.y > best.get_global_rect().position.y - 1.0:
				best = c
				if c.get_global_rect().get_center().y > r.position.y + r.size.y * along:
					break
	return best.get_global_rect().get_center() if best else r.get_center()


func _first_scroll(root: Node, horizontal := false) -> ScrollContainer:
	var best: ScrollContainer = null
	for n in root.find_children("*", "ScrollContainer", true, false):
		var sc := n as ScrollContainer
		if not sc.is_visible_in_tree():
			continue
		var h := sc.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED and sc.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED
		if h != horizontal:
			continue
		if best == null or sc.size.x * sc.size.y > best.size.x * best.size.y:
			best = sc
	return best


func _setup() -> void:
	Input.emulate_mouse_from_touch = true
	Controls.device = "touch"
	Save.data = Save.migrate({"version": 3, "uid": "local-reel", "name": "Sleepy Otter", "coins": 345, "level": 6, "xp": 40,
		"owned": ["hat:crown", "outfit:robe", "color:plum"], "onboarded": true, "tutorial_done": true,
		"cosmetic": {"schema": 2, "outfit": "robe", "color": "plum", "hat": "crown", "hair": "curly", "skin": "tone6"},
		"stats": {"online": {"matches": 14}, "practice": {"matches": 6}}, "settings": {}})
	Save.data["onboarded"] = true
	svc = FakeService.new()
	svc.install()
	store = TestStore.new()
	Purchases.use_adapter(store)
	svc.gc_player = "T:_reel"
	await Cloud.sign_in()
	var pid := Cloud.profile_id()
	svc.grant(pid, 1650)
	var s1: Dictionary = svc.wallet(pid)["season"]["s1"]
	s1["xp"] = 1450
	s1["claimed"] = ["1:free"]
	await Wallet.refresh()


func _settle() -> void:
	var t := 0
	while t < 360:
		var ps := Portraits.shared()
		if ps.pending() == 0 and not ps._busy:
			break
		await get_tree().process_frame
		t += 1
	await _wait(0.4)


func _run() -> void:
	await _wait(0.3)
	await _setup()
	App.goto_title()
	await _wait(1.0)
	await _locker()
	await _shop()
	await _season()
	if results_path != "":
		await _results()
	printerr("REEL-DONE frames=%d" % Engine.get_process_frames())
	get_tree().quit()


func _locker() -> void:
	NavShell.open("locker")
	await _wait(0.8)
	var lk := App.screen as CreatorScreen
	lk._select_tab("face")      # the longest category
	await _settle()
	var sc := lk.scroll
	_mark("locker: swipe up, starting on a card")
	var a := _card_in(sc, "Button", 0.6)
	var before := String(lk.draft.get("skin", ""))
	await swipe(a, a + Vector2(0, -sc.size.y * 0.55))
	await _wait(1.0)
	await swipe(a, a + Vector2(0, -sc.size.y * 0.5), 0.2)
	await _wait(1.2)
	_mark("locker: swipe back down")
	await swipe(a - Vector2(0, sc.size.y * 0.2), a + Vector2(0, sc.size.y * 0.35), 0.3)
	await _wait(1.0)
	printerr("REEL locker selection unchanged by swipes: %s" % (String(lk.draft.get("skin", "")) == before))
	_mark("locker: tap a card (selects)")
	await tap(_card_in(sc, "Button", 0.4))
	await _wait(1.0)
	_hide_finger()


func _shop() -> void:
	NavShell.open("shop")
	await _wait(0.8)
	var shop := App.screen as ShopScreen
	shop.select_section("outfits")
	await _settle()
	var sc := _first_scroll(shop)
	if sc == null:
		printerr("REEL shop: no list found")
		return
	_mark("shop: swipe up on an outfit card (no detail opens, nothing is bought)")
	var a := _card_in(sc, "Button", 0.6)
	await swipe(a, a + Vector2(0, -sc.size.y * 0.5))
	await _wait(1.2)
	await swipe(a, a + Vector2(0, -sc.size.y * 0.4), 0.22)
	await _wait(1.2)
	printerr("REEL shop: App Store purchase sheets opened by the swipes: %d" % int(store.purchases_started))
	_mark("shop: tap a card (opens its detail)")
	await tap(_card_in(sc, "Button", 0.4))
	await _wait(1.6)
	_hide_finger()
	if shop.has_method("_close_detail"):
		shop._close_detail()
	await _wait(0.4)


func _season() -> void:
	NavShell.open("pass")
	await _wait(1.0)
	await _settle()
	var sp := App.screen as SeasonScreen
	var sc: ScrollContainer = sp.track_scroll
	var r := sc.get_global_rect()
	var start := Vector2(r.position.x + r.size.x * 0.8, r.get_center().y)
	_mark("season: swipe the track left, starting on a reward (nothing is claimed)")
	await swipe(start, start - Vector2(r.size.x * 0.55, 0))
	await _wait(1.2)
	await swipe(start, start - Vector2(r.size.x * 0.5, 0), 0.2)
	await _wait(1.2)
	_mark("season: swipe back")
	await swipe(start - Vector2(r.size.x * 0.5, 0), start, 0.3)
	await _wait(1.2)
	_hide_finger()


func _results() -> void:
	var d: Dictionary = str_to_var(FileAccess.get_file_as_string(results_path))
	var s := NetSession.new()
	s.local_slot = int(d["local_slot"])
	add_child(s)
	App._ensure_background()
	var rs := ResultsScreen.new()
	rs.results = d["results"]
	rs.reward = d.get("reward", {})
	rs.session = s
	App._show(rs)
	await _wait(1.5)
	var sc := _first_scroll(rs)
	if sc == null:
		printerr("REEL results: no list found")
		return
	_mark("results: swipe the standings")
	var a := sc.get_global_rect().get_center() + Vector2(0, sc.size.y * 0.25)
	await swipe(a, a - Vector2(0, sc.size.y * 0.5))
	await _wait(1.2)
	await swipe(a - Vector2(0, sc.size.y * 0.3), a + Vector2(0, sc.size.y * 0.1), 0.3)
	await _wait(1.2)
	_hide_finger()
