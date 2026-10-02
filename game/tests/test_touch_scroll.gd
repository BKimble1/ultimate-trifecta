extends RefCounted
## V6 finger scrolling (TouchScroll): a swipe that starts on a card scrolls
## the list and never activates the card; a tap still activates it exactly
## once; a horizontal strip inside a vertical list keeps to its axis.
## Events go through the real viewport GUI path (push_input) with touch
## emulated from the mouse, as iOS delivers them.
var t
var _saved_emulate := false
var _saved_device := ""
var _saved_size := Vector2i.ZERO


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


func _setup() -> void:
	_saved_emulate = Input.emulate_touch_from_mouse
	_saved_device = Controls.device
	Input.emulate_touch_from_mouse = true
	Controls.device = "touch"
	# a headless window is tiny and never hears that the pointer entered it
	_saved_size = t.get_tree().root.size
	t.get_tree().root.size = Vector2i(1280, 720)
	t.get_tree().root.notification(Window.NOTIFICATION_WM_MOUSE_ENTER)
	await _frames(2)


func _teardown() -> void:
	Input.emulate_touch_from_mouse = _saved_emulate
	Controls.device = _saved_device
	t.get_tree().root.size = _saved_size


func _list(n: int, presses: Array) -> ScrollContainer:
	var layer := CanvasLayer.new()
	layer.layer = 120   # above the startup curtain (layer 100), which blocks input while shown
	t.add_child(layer)
	var sc := UIKit.scroll_area()
	sc.position = Vector2(100, 100)
	sc.size = Vector2(420, 360)
	layer.add_child(sc)
	var v := VBoxContainer.new()
	v.custom_minimum_size.x = 400
	sc.add_child(v)
	for i in n:
		var b := UIKit.card_button(Vector2(400, 120))
		b.text = "Card %d" % i
		var lbl := Label.new()
		lbl.text = "label %d" % i
		b.add_child(lbl)   # a label on the card (its default filter is IGNORE)
		var pic := TextureRect.new()
		pic.mouse_filter = Control.MOUSE_FILTER_STOP   # a picture that stops the pointer
		pic.size = Vector2(80, 80)
		b.add_child(pic)
		b.pressed.connect(func() -> void: presses.append(i))
		v.add_child(b)
	return sc


func _press(at: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = at
	e.global_position = at
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	t.get_viewport().push_input(e)


func _move(from: Vector2, to: Vector2, steps: int) -> void:
	var prev := from
	for i in steps:
		var p := from.lerp(to, float(i + 1) / steps)
		var e := InputEventMouseMotion.new()
		e.position = p
		e.global_position = p
		e.relative = p - prev
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
		t.get_viewport().push_input(e)
		prev = p
		await t.get_tree().process_frame


func test_swipe_on_a_card_scrolls_and_never_selects() -> void:
	await _setup()
	var presses: Array = []
	var sc := _list(12, presses)
	await _frames(3)
	t.check(DisplayServer.is_touchscreen_available(), "touch is available (emulated, as on iOS)")
	# start on the picture of card 1 (a child that stops the pointer)
	var start := Vector2(160, 300)
	_press(start, true)
	await _move(start, start + Vector2(4, -220), 12)
	_press(start + Vector2(4, -220), false)
	await _frames(20)
	t.check(sc.scroll_vertical > 100, "the swipe scrolled the list (%d)" % sc.scroll_vertical)
	t.eq(presses, [], "lifting the finger after a swipe activated nothing")
	# a plain tap (no movement) activates exactly one card, once
	var top := sc.scroll_vertical
	await _frames(30)   # inertia settles
	var tap := Vector2(300, 250)
	_press(tap, true)
	await _frames(2)
	_press(tap, false)
	await _frames(2)
	t.eq(presses.size(), 1, "a tap activates exactly one card")
	t.check(absf(sc.scroll_vertical - top) < 400.0, "and the list stays put (no follow-focus jump)")
	# a tiny jitter (under the dead zone) is still a tap
	var tap2 := Vector2(300, 380)
	_press(tap2, true)
	await _move(tap2, tap2 + Vector2(3, 4), 3)
	_press(tap2 + Vector2(3, 4), false)
	await _frames(2)
	t.eq(presses.size(), 2, "a few points of jitter still count as a tap")
	sc.get_parent().queue_free()
	_teardown()


func test_horizontal_strip_inside_a_vertical_list_keeps_its_axis() -> void:
	await _setup()
	var layer := CanvasLayer.new()
	layer.layer = 120   # above the startup curtain (layer 100), which blocks input while shown
	t.add_child(layer)
	var outer := UIKit.scroll_area()
	outer.position = Vector2(100, 100)
	outer.size = Vector2(420, 360)
	layer.add_child(outer)
	var v := VBoxContainer.new()
	v.custom_minimum_size.x = 400
	outer.add_child(v)
	var strip := UIKit.scroll_area(true)
	strip.custom_minimum_size = Vector2(400, 100)
	v.add_child(strip)
	var h := HBoxContainer.new()
	strip.add_child(h)
	var taps: Array = []
	for i in 10:
		var b := UIKit.card_button(Vector2(150, 90))
		b.pressed.connect(func() -> void: taps.append(i))
		h.add_child(b)
	for i in 8:
		var b := UIKit.card_button(Vector2(400, 120))
		v.add_child(b)
	await _frames(3)
	# a vertical swipe starting on the strip scrolls the list, not the strip
	var s := Vector2(200, 150)
	_press(s, true)
	await _move(s, s + Vector2(0, -200), 10)
	_press(s + Vector2(0, -200), false)
	await _frames(20)
	t.check(outer.scroll_vertical > 80, "vertical swipe on the strip scrolled the list (%d)" % outer.scroll_vertical)
	t.eq(strip.scroll_horizontal, 0, "and not the strip")
	outer.scroll_vertical = 0
	await _frames(25)
	# a horizontal swipe on the strip scrolls the strip only
	_press(s, true)
	await _move(s, s + Vector2(-220, 0), 10)
	_press(s + Vector2(-220, 0), false)
	await _frames(20)
	t.check(strip.scroll_horizontal > 80, "horizontal swipe scrolled the strip (%d)" % strip.scroll_horizontal)
	t.check(outer.scroll_vertical < 10, "and not the list (%d)" % outer.scroll_vertical)
	t.eq(taps, [], "no card in the strip was activated by either swipe")
	layer.queue_free()
	_teardown()
