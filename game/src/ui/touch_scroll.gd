class_name TouchScroll
extends Node
## V6: finger scrolling for every list in the app (wardrobe/Locker, Shop,
## pass track, results, settings, roster, chat).
##
## The owner could only scroll the wardrobe by dragging its scrollbar: its
## cards are Buttons, and a Button stops the touch, so the ScrollContainer
## (whose touch-drag scrolling, with inertia and clamping, is the engine's)
## never saw the finger.  This helper keeps the engine's behaviour and makes
## it reachable:
##  - every Control inside the list passes pointer events up to it (a card
##    still receives its own tap first), so a swipe that starts on a card,
##    picture, label or blank space scrolls;
##  - a touch stays a tap until it moves past a small dead zone (~10 pt);
##  - when the list starts scrolling, the press on the card under the
##    finger is cancelled, so lifting the finger never selects, equips,
##    claims or buys;
##  - nested lists keep to their axis (a horizontal strip inside a vertical
##    list: the engine scrolls whichever axis the drag goes along);
##  - follow-focus is for controller and keyboard focus only, so a tap never
##    snaps the list back mid-drag.
## Lists are made with UIKit.scroll_area(); attach() adapts an existing one.

const DEADZONE_PT := 10.0

var sc: ScrollContainer
## the list is being dragged by a finger (taps inside it are cancelled)
var dragging := false


static func attach(s: ScrollContainer) -> TouchScroll:
	if s.has_meta(&"touch_scroll"):
		return s.get_meta(&"touch_scroll")
	var t := TouchScroll.new()
	t.name = "TouchScroll"
	t.sc = s
	s.set_meta(&"touch_scroll", t)
	s.add_child(t, false, Node.INTERNAL_MODE_BACK)   # not content
	return t


## The touch dead zone in canvas units (10 pt on this device).
static func deadzone() -> float:
	return UIKit.touch_min() * DEADZONE_PT / 44.0


func _ready() -> void:
	sc.mouse_filter = Control.MOUSE_FILTER_PASS
	sc.scroll_deadzone = int(round(deadzone()))
	sc.scroll_started.connect(_on_scroll_started)
	sc.scroll_ended.connect(func() -> void: dragging = false)
	sc.gui_input.connect(_on_gui_input)
	get_tree().node_added.connect(_on_node_added)
	for c in sc.find_children("*", "Control", true, false):
		_pass(c)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func _on_node_added(n: Node) -> void:
	if n is Control and is_instance_valid(sc) and sc.is_ancestor_of(n):
		# after the node's own _ready, which may set STOP
		_pass.call_deferred(n)


## A Control that stops the pointer hides the swipe from the list.  Opt out
## with set_meta(&"scroll_keep_stop", true) (e.g. a slider in a list).
func _pass(c: Variant) -> void:
	if not is_instance_valid(c) or not (c is Control):
		return
	var ctl := c as Control
	if ctl.mouse_filter == Control.MOUSE_FILTER_STOP and not ctl.has_meta(&"scroll_keep_stop"):
		ctl.mouse_filter = Control.MOUSE_FILTER_PASS


## Backgrounding, an incoming call or losing focus mid-drag: nothing stays
## pressed, and the next touch starts clean.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		dragging = false
		if is_instance_valid(sc):
			cancel_presses(sc)


func _on_gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			dragging = false
			# a finger tapping a card must not make the list jump to it
			sc.follow_focus = Controls.device != "touch"


func _on_scroll_started() -> void:
	dragging = true
	cancel_presses(sc)


## Cancel the press of every button held inside `root` without activating
## it (lifting the finger then does nothing) and settle its press animation.
static func cancel_presses(root: Node) -> void:
	for n in root.find_children("*", "BaseButton", true, false):
		var bb := n as BaseButton
		if bb.toggle_mode or not bb.is_pressed():
			continue
		cancel_press(bb)


static func cancel_press(bb: BaseButton) -> void:
	var was := bb.disabled
	bb.disabled = true      # clears the press attempt (no signal)
	bb.disabled = was
	var v := UIKit._press_visual(bb)
	if v != null:
		Motion.press(v, false)
