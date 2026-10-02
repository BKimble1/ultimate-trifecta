## Development-only (src/dev is excluded from exports).  Run in a window:
##   xvfb-run tools/gd.sh --path game --resolution 1280x720 res://src/dev/input_fallthrough_check.tscn
## A HUD button on canvas layer 5 under the full-screen touch surface on
## layer 6: V3 swallowed the tap (count stays), V4 passes it through.
extends Node

class Surf:
	extends Control
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventScreenTouch or e is InputEventScreenDrag:
			accept_event()

var hits := 0

func _tap(at: Vector2) -> void:
	for pressed in [true, false]:
		var tch := InputEventScreenTouch.new()
		tch.index = 0
		tch.position = at
		tch.pressed = pressed
		Input.parse_input_event(tch)   # mouse emulation from touch is on by default
		await get_tree().process_frame
		await get_tree().process_frame

func _ready() -> void:
	await get_tree().process_frame
	var l5 := CanvasLayer.new()
	l5.layer = 5
	add_child(l5)
	var b := Button.new()
	b.position = Vector2(1100, 20)
	b.size = Vector2(80, 80)
	l5.add_child(b)
	b.pressed.connect(func() -> void: hits += 1)
	await get_tree().process_frame
	await _tap(b.get_global_rect().get_center())
	print("RESULT no surface: ", hits)
	var l6 := CanvasLayer.new()
	l6.layer = 6
	add_child(l6)
	var s := Surf.new()
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.mouse_filter = Control.MOUSE_FILTER_PASS
	l6.add_child(s)
	await get_tree().process_frame
	await _tap(b.get_global_rect().get_center())
	print("RESULT plain PASS surface (V3): ", hits)
	s.queue_free()
	var ts := TouchControls.TouchSurface.new()
	ts.set_anchors_preset(Control.PRESET_FULL_RECT)
	l6.add_child(ts)
	ts.mouse_filter = Control.MOUSE_FILTER_PASS
	var reserved: Array[Rect2] = [b.get_global_rect().grow(12)]
	ts.set_reserved(reserved)
	await get_tree().process_frame
	await _tap(b.get_global_rect().get_center())
	print("RESULT V4 surface: ", hits, "  surface owners: ", ts.router.owners.size())
	get_tree().quit()
