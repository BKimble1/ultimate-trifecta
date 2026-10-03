class_name HubStick
extends Control
## The walk stick of the party room (V6 Walk around): a floating stick in
## the left part of the screen.  Touch down anywhere in its area, drag to
## walk, lift to stop.  One finger owns it (others can press Ready, Emote or
## Chat at the same time); touch cancellation, backgrounding, opening a
## menu or leaving walk mode release it.  Desktop: the mouse works the same.

var walk: HubWalk
var _finger := -1
var _origin := Vector2.ZERO
var _at := Vector2.ZERO
var _mouse := false
var _touch_seen := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func radius() -> float:
	return UIKit.touch_min() * 1.25


func release() -> void:
	_finger = -1
	_mouse = false
	if walk != null and is_instance_valid(walk):
		walk.stick = Vector2.ZERO
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_EXIT_TREE:
		release()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		_touch_seen = true
		var st := ev as InputEventScreenTouch
		if st.pressed and _finger < 0:
			_finger = st.index
			_origin = st.position
			_at = st.position
			_update()
			accept_event()
		elif not st.pressed and st.index == _finger:
			release()
			accept_event()
	elif ev is InputEventScreenDrag:
		var sd := ev as InputEventScreenDrag
		if sd.index == _finger:
			_at = sd.position
			_update()
			accept_event()
	elif not _touch_seen and ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := ev as InputEventMouseButton
		if mb.pressed:
			_mouse = true
			_origin = mb.position
			_at = mb.position
			_update()
		else:
			release()
		accept_event()
	elif not _touch_seen and ev is InputEventMouseMotion and _mouse:
		_at = (ev as InputEventMouseMotion).position
		_update()
		accept_event()


func _update() -> void:
	var d := _at - _origin
	var r := radius()
	if d.length() > r:
		# the base follows a finger that runs past the rim (no dead stick)
		_origin = _at - d.normalized() * r
		d = _at - _origin
	if walk != null and is_instance_valid(walk):
		var v := d / r
		walk.stick = Vector2(v.x, -v.y) if v.length() > 0.12 else Vector2.ZERO
	queue_redraw()


func held() -> bool:
	return _finger >= 0 or _mouse


func _draw() -> void:
	if not held():
		# a quiet hint where the stick appears
		var c := Vector2(size.x * 0.32, size.y * 0.62)
		draw_circle(c, radius(), Color(UIKit.IVORY, 0.06))
		draw_arc(c, radius(), 0, TAU, 40, Color(UIKit.IVORY, 0.22), 2.0, true)
		return
	draw_circle(_origin, radius(), Color(UIKit.NAVY, 0.35))
	draw_arc(_origin, radius(), 0, TAU, 40, Color(UIKit.IVORY, 0.4), 3.0, true)
	draw_circle(_at, radius() * 0.42, Color(UIKit.IVORY, 0.85))
