class_name StageTurn
extends Control
## Final release sweep (docs/final/season.md): turning a character preview,
## in the Shop / Locker language (drag to turn, the Locker's drag rate),
## with clear ownership and non-drag alternatives.
##
##  * Touch ownership.  The first finger down owns the gesture until it
##    lifts.  It stays a tap until it moves past the touch dead zone
##    (TouchScroll.deadzone(), ~10 pt); a mostly sideways move then turns the
##    model and keeps turning it (also outside the area) until the finger
##    lifts; a mostly vertical move is not a turn and does nothing.  A second
##    finger never takes over.  Mouse events (the engine's twin of a finger)
##    are ignored: touch events arrive natively on iOS and from the mouse on
##    desktop (emulate_touch_from_mouse).  Buttons placed on the area receive
##    their own taps (they are drawn on top and stop the pointer).
##  * No fight with automatic motion.  `offset` is the player's turn from
##    the three-quarter start pose.  A slow sway may run only until the
##    player first turns, steps or resets (`touched`), and never under
##    Reduced Motion.  Step and Reset glide briefly (Reduced Motion: at
##    once); a finger cancels a glide.
##  * Alternatives to dragging: step(+1/-1) turns a quarter at a time (a
##    Turn button), reset() returns to the start pose, the controller's
##    right stick turns (turn_by from the screen's _process).
##  * Capture is released on lift, a cancelled touch, hiding the area,
##    leaving the tree, the app losing focus or going to the background,
##    and when the screen opens a sheet (release()).
## No zoom: the model's scale is fixed by the stage framing, so it can never
## clip through the camera or vanish.

signal turned(delta: float)
## the player's first deliberate turn, step or reset (the sway is over)
signal touched_first

## radians per canvas unit of finger travel (the Locker's and Shop's rate)
const RAD_PER_UNIT := 0.012
const STEP := PI * 0.5
const SWAY_RATE := 0.45
const SWAY := 0.3
const GLIDE := 9.0

## the player's turn from the start pose (radians, wraps at ±PI)
var offset := 0.0
## the player has turned the model: no automatic sway from then on
var touched := false
## a finger is turning the model now
var dragging := false
## false for a reward with nothing to turn (a 2D picture is shown)
var enabled := true
## the slow sway before the first touch (the Shop's): off for screens that
## want a still start pose; never under Reduced Motion
var sway_on := true
var _phase := 0.0
var _goal := 0.0
var _gliding := false
var _owner := -1
var _start := Vector2.ZERO
var _last := Vector2.ZERO
var _pending := false
## the finger chose vertical: it is ignored until it lifts
var _ignored := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		var st := e as InputEventScreenTouch
		if st.pressed and _owner < 0 and enabled:
			_owner = st.index
			_start = st.position
			_last = st.position
			_pending = true
			_ignored = false
			accept_event()
		elif not st.pressed and st.index == _owner:
			release()
			accept_event()
	elif e is InputEventScreenDrag:
		var d := e as InputEventScreenDrag
		if d.index != _owner:
			return
		accept_event()
		if _ignored or not enabled:
			return
		if _pending:
			var mv := d.position - _start
			if mv.length() < TouchScroll.deadzone():
				return
			_pending = false
			if absf(mv.x) < absf(mv.y):
				_ignored = true
				return
			dragging = true
			_last = d.position
			return
		if dragging:
			var dx := d.position.x - _last.x
			_last = d.position
			turn_by(dx * RAD_PER_UNIT)


## The finger lifted, was cancelled, or the area lost it (hidden, sheet,
## background): nothing stays captured; the next touch starts clean.
func release() -> void:
	_owner = -1
	_pending = false
	_ignored = false
	dragging = false


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_EXIT_TREE:
			release()
		NOTIFICATION_VISIBILITY_CHANGED:
			if not is_visible_in_tree():
				release()


## Turn by `rad` (a drag, the right stick): the player's own turn.
func turn_by(rad: float) -> void:
	if rad == 0.0:
		return
	_mark_touched()
	_gliding = false
	offset = wrapf(offset + rad, -PI, PI)
	turned.emit(rad)


## A quarter turn (+1 / -1), gliding (Reduced Motion: at once).
func step(dir: int) -> void:
	_mark_touched()
	var from := _goal if _gliding else offset
	_glide_to(from + STEP * float(signi(dir)))


## Back to the three-quarter start pose.
func reset() -> void:
	_mark_touched()
	_glide_to(0.0)


## True when the model is (about) at its start pose.
func at_start() -> bool:
	return absf(wrapf(_goal if _gliding else offset, -PI, PI)) < 0.02


func _glide_to(target: float) -> void:
	if dragging:
		return
	# the short way round
	_goal = offset + wrapf(target - offset, -PI, PI)
	if UIKit.reduced_motion() or not is_inside_tree():
		offset = wrapf(_goal, -PI, PI)
		_gliding = false
		turned.emit(0.0)
		return
	_gliding = true


func _mark_touched() -> void:
	if not touched:
		touched = true
		touched_first.emit()


## The sway's current angle (0 once touched, when off, or under Reduced Motion).
func sway() -> float:
	if touched or not sway_on or UIKit.reduced_motion():
		return 0.0
	return sin(_phase) * SWAY


## The yaw for a model whose three-quarter start pose is `start`.
func facing(start: float) -> float:
	return start + offset + sway()


## A new look (another skin): the player's turn stays (comparing skins from
## the same side); a glide in progress lands.
func settle() -> void:
	if _gliding:
		offset = wrapf(_goal, -PI, PI)
		_gliding = false


func _process(delta: float) -> void:
	if not touched and sway_on and not UIKit.reduced_motion():
		_phase += delta * SWAY_RATE
	if _gliding:
		if dragging:
			_gliding = false
			return
		var k := 1.0 - exp(-GLIDE * delta)
		var before := offset
		var next := lerpf(offset, _goal, k)
		if absf(_goal - next) < 0.004:
			next = _goal
			_gliding = false
		offset = next
		turned.emit(next - before)
		if not _gliding:
			offset = wrapf(offset, -PI, PI)
