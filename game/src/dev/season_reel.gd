extends Node
## Development-only clip for the final release sweep's Season Pass
## (docs/final/season.md; src/dev: never exported): the real Season Pass,
## driven by scripted pointer input through Input (the engine turns it into
## touches as on desktop: buttons, the track's finger scrolling and the
## stage's drag-to-turn all see it), recorded by
## tools/capture_final_season_reel.sh with Movie Maker at a fixed 30 fps
## clock, so it plays at normal speed.  The TEST-DOUBLE service plays a
## regular player (Premium, Tier 43); a dot shows where the finger is.
##
## Timeline: open the pass -> Tier 50 (Record Breaker) -> drag it round ->
## Turn -> Reset -> Tier 100 (Dr. Doom) -> drag it round -> Run / Idle ->
## swipe the pass track both ways -> a badge (a picture) -> Record Breaker
## again -> Challenges -> Reward -> Back: home, the runner in the saved look.

const FakeService := preload("res://src/dev/fake_commerce_service.gd")
const TestStore := preload("res://src/dev/test_store_adapter.gd")
const LOOK := {"schema": 2, "outfit": "pj", "hat": "nightcap", "shoes": "slippers", "color": "sky", "hair": "tuft", "skin": "tone4"}

var svc
var _dot: Control
var _finger := Vector2(-100, -100)
var _down := false
var _frame := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = 125
	add_child(layer)
	_dot = Control.new()
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dot.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dot.draw.connect(func() -> void:
		if _down:
			_dot.draw_circle(_finger, 26.0, Color(1, 1, 1, 0.28), true, -1.0, true)
			_dot.draw_arc(_finger, 26.0, 0.0, TAU, 32, Color(1, 1, 1, 0.75), 3.0, true))
	layer.add_child(_dot)
	_run.call_deferred()


func _process(_delta: float) -> void:
	_frame += 1


func _mark(what: String) -> void:
	printerr("REEL %s frame %d" % [what, _frame])


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _px(p: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * p


func _press(at: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = _px(at)
	e.global_position = e.position
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	Input.parse_input_event(e)
	_finger = at
	_down = down
	_dot.queue_redraw()


func _move(from: Vector2, to: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = _px(to)
	e.global_position = e.position
	e.relative = _px(to) - _px(from)
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(e)
	_finger = to
	_dot.queue_redraw()


## A tap on a control's centre (a short, still press).
func _tap(c: Control) -> void:
	var at := c.get_global_rect().get_center()
	_press(at, true)
	await _frames(4)
	_press(at, false)
	await _frames(2)


## A finger drag over `sec` seconds (eased), then lifted.
func _drag(from: Vector2, to: Vector2, sec: float) -> void:
	_press(from, true)
	await _frames(2)
	var n := maxi(2, int(sec * 30.0))
	var p := from
	for i in n:
		var k := float(i + 1) / float(n)
		var e := k * k * (3.0 - 2.0 * k)
		var q := from.lerp(to, e)
		_move(p, q)
		p = q
		await _frames(1)
	await _frames(2)
	_press(to, false)
	await _frames(2)


func _run() -> void:
	await _wait(0.4)
	Save.data = Save.migrate({"version": 3, "uid": "local-reel", "name": "Sleepy Otter", "coins": 0, "level": 6, "xp": 40,
		"owned": [], "onboarded": true, "tutorial_done": true, "cosmetic": LOOK.duplicate(),
		"stats": {"online": {"matches": 14}, "practice": {"matches": 6}}, "settings": {}})
	svc = FakeService.new()
	svc.install()
	Purchases.use_adapter(TestStore.new())
	svc.gc_player = "T:_reel"
	await Cloud.sign_in()
	var pid := Cloud.profile_id()
	svc.grant(pid, 640)
	var s1: Dictionary = svc.wallet(pid)["season"]["s1"]
	s1["xp"] = 13000
	s1["premium"] = true
	svc.wallet(pid)["entitlements"]["season:s1:premium"] = {"source": "coin_purchase"}
	await Wallet.refresh()
	App.goto_title()
	await _wait(1.5)
	_mark("start")
	var look_before: Dictionary = Save.data["cosmetic"].duplicate(true)
	NavShell.open("pass")
	await _wait(2.0)
	var sp := App.screen as SeasonScreen
	# ---------------------------------------------------- Record Breaker
	_mark("record_breaker")
	await _tap(sp.milestone_chips[50])
	await _wait(1.6)
	var c := sp.turn.get_global_rect().get_center()
	_mark("rotate_rb")
	await _drag(c + Vector2(-90, 0), c + Vector2(150, 6), 1.6)
	await _wait(0.8)
	await _drag(c + Vector2(120, -20), c + Vector2(-140, -10), 1.6)
	await _wait(0.8)
	await _tap(sp.turn_btn)
	await _wait(1.0)
	await _tap(sp.reset_btn)
	await _wait(1.2)
	# ---------------------------------------------------- Dr. Doom
	_mark("dr_doom")
	await _tap(sp.milestone_chips[100])
	await _wait(1.6)
	_mark("rotate_dd")
	await _drag(c + Vector2(-110, 10), c + Vector2(130, 0), 1.8)
	await _wait(0.8)
	await _tap(sp.pose_btn)
	await _wait(2.2)
	await _tap(sp.pose_btn)
	await _wait(1.0)
	await _tap(sp.reset_btn)
	await _wait(0.8)
	# ---------------------------------------------------- the pass track
	_mark("scroll")
	var tr := sp.track_scroll.get_global_rect()
	var y := tr.position.y + tr.size.y * 0.3
	await _drag(Vector2(tr.end.x - 40, y), Vector2(tr.position.x + 60, y + 4), 1.0)
	await _wait(1.2)
	await _drag(Vector2(tr.position.x + 60, y), Vector2(tr.end.x - 40, y - 4), 1.0)
	await _wait(1.2)
	# Tier 50's Free badge (a picture, nothing to turn), then Record Breaker
	# again
	sp._scroll_to(50, true)
	await _wait(0.8)
	_mark("badge")
	await _tap(sp._cell(50, "free"))
	await _wait(1.6)
	await _tap(sp._cell(50, "premium"))
	await _wait(1.4)
	# ---------------------------------------------------- tabs
	_mark("challenges")
	await _tap(sp._tabs["challenges"])
	await _wait(2.0)
	await _tap(sp._tabs["reward"])
	await _wait(1.2)
	# ---------------------------------------------------- leave
	_mark("leave")
	var back := sp.find_child("Back", true, false) as Control
	await _tap(back)
	await _wait(2.4)
	var v := App.stage.local_character() if App.stage else null
	var same: bool = Save.data["cosmetic"] == look_before and v != null and v.cosmetic == Cosmetics.sanitize(look_before)
	printerr("REEL saved look unchanged: %s; runner shows it: %s" % [Save.data["cosmetic"] == look_before, same])
	_mark("end")
	await _wait(0.6)
	get_tree().quit()
