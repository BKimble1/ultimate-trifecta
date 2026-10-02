extends RefCounted
## V6: drag-to-turn in the Locker is owned by one finger: each move turns
## the runner once (not again for the emulated mouse twin), a second finger
## does nothing, and a drag that leaves the area keeps turning until lifted.
var t
var _saved_emulate := false
var _saved_size := Vector2i.ZERO


func _setup() -> void:
	_saved_emulate = Input.emulate_touch_from_mouse
	Input.emulate_touch_from_mouse = false
	_saved_size = t.get_tree().root.size
	t.get_tree().root.size = Vector2i(1280, 720)
	t.get_tree().root.notification(Window.NOTIFICATION_WM_MOUSE_ENTER)
	for i in 2:
		await t.get_tree().process_frame


func _teardown() -> void:
	Input.emulate_touch_from_mouse = _saved_emulate
	t.get_tree().root.size = _saved_size


## A real finger on iOS: the touch event, then the mouse event the engine
## emulates from it (Input.parse_input_event does that emulation).
func _touch(i: int, at: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = at
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _drag(i: int, from: Vector2, to: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = i
	e.position = to
	e.relative = to - from
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func test_one_finger_owns_the_turn() -> void:
	await _setup()
	var layer := CanvasLayer.new()
	layer.layer = 120
	t.add_child(layer)
	var area := CreatorScreen.StageDrag.new()
	area.position = Vector2(100, 100)
	area.size = Vector2(400, 400)
	layer.add_child(area)
	var got: Array = [0.0, 0]
	area.turned.connect(func(dx: float) -> void:
		got[0] += dx
		got[1] += 1)
	for i in 2:
		await t.get_tree().process_frame
	var a := Vector2(200, 300)
	_touch(0, a, true)
	var p := a
	for k in 5:
		var q := p + Vector2(20, 0)
		_drag(0, p, q)
		p = q
		await t.get_tree().process_frame
	t.near(float(got[0]), 100.0, 0.5, "a 100 px drag turns by 100 px once (%.0f in %d events)" % [got[0], got[1]])
	# a second finger: neither its touch nor its drags turn the runner
	_touch(1, Vector2(400, 300), true)
	_drag(1, Vector2(400, 300), Vector2(300, 300))
	await t.get_tree().process_frame
	t.near(float(got[0]), 100.0, 0.5, "a second finger does nothing")
	_touch(1, Vector2(300, 300), false)
	# the first finger leaves the area and keeps turning until lifted
	_drag(0, p, p + Vector2(300, 0))
	await t.get_tree().process_frame
	t.check(float(got[0]) > 100.0, "a drag that leaves the area keeps turning (%.0f)" % got[0])
	_touch(0, p + Vector2(300, 0), false)
	var after := float(got[0])
	_drag(0, p, p + Vector2(50, 0))
	await t.get_tree().process_frame
	t.near(float(got[0]), after, 0.01, "after lifting, nothing turns")
	layer.queue_free()
	_teardown()
