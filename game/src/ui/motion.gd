class_name Motion
extends RefCounted
## V5 motion layer: every animated UI property has exactly one owner.
##
## V4 started a new tween for each press and release (UIKit._scale_to) and
## never stopped the previous one, so a quick tap-release-tap left a 0.2 s
## release spring running underneath the new press: the held button sprang
## back to full size while the finger was still down (reproduced in
## test_motion_layer).  Here a property's running tween is killed before a
## new one starts, and the tween is bound to the node, so freeing the node
## frees its animations.  Owners are kept in the node's own metadata, so
## nothing outlives it.
##
## Timings (seconds), used everywhere:
##   press in 0.085 (immediate response), release 0.19 with a very small
##   overshoot, panels/tabs 0.22 fade with at most 12 units of movement,
##   scene-camera moves 0.32 (DormStage).  Reduced Motion: no scale, no
##   movement, no bounce; state and colour still change at once.

const PRESS_IN := 0.085
const PRESS_OUT := 0.19
const PRESS_SCALE := 0.955
const PANEL := 0.22
const FAST := 0.15
const CAMERA := 0.32
const _META := &"_motion_owners"


static func reduced() -> bool:
	return bool(Save.get_setting("reduced_motion", false)) if Engine.get_main_loop() != null else false


## Animate `prop` (a property path such as "scale" or "modulate:a") of
## `node` to `value`.  Any animation already running on that property is
## stopped first (retargeted from where it is now).  A zero duration, or a
## node outside the tree, sets the value at once.  Returns the tween (or
## null when the value was set directly).
static func animate(node: Node, prop: String, value: Variant, dur: float, trans: int = Tween.TRANS_CUBIC,
		ease: int = Tween.EASE_OUT, delay: float = 0.0) -> Tween:
	if node == null or not is_instance_valid(node):
		return null
	stop(node, prop)
	if dur <= 0.0 or not node.is_inside_tree():
		node.set_indexed(NodePath(prop), value)
		return null
	var tw := node.create_tween()
	var pt := tw.tween_property(node, NodePath(prop), value, dur).set_trans(trans).set_ease(ease)
	if delay > 0.0:
		pt.set_delay(delay)
	var owners := _owners(node)
	owners[prop] = tw
	tw.finished.connect(_release.bind(node.get_instance_id(), prop, tw), CONNECT_ONE_SHOT)
	return tw


## Stop the animation that owns `prop` (the value stays where it is).
static func stop(node: Node, prop: String) -> void:
	if node == null or not is_instance_valid(node) or not node.has_meta(_META):
		return
	var owners: Dictionary = node.get_meta(_META)
	var old: Variant = owners.get(prop)
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	owners.erase(prop)


static func stop_all(node: Node) -> void:
	if node == null or not is_instance_valid(node) or not node.has_meta(_META):
		return
	var owners: Dictionary = node.get_meta(_META)
	for p in owners.keys():
		stop(node, String(p))


## Running animations on `node` (tests: never more than one per property).
static func running(node: Node) -> Dictionary:
	var out := {}
	if node == null or not is_instance_valid(node) or not node.has_meta(_META):
		return out
	var owners: Dictionary = node.get_meta(_META)
	for p in owners:
		var tw: Variant = owners[p]
		if tw is Tween and (tw as Tween).is_valid() and (tw as Tween).is_running():
			out[p] = tw
	return out


static func _owners(node: Node) -> Dictionary:
	if not node.has_meta(_META):
		node.set_meta(_META, {})
	return node.get_meta(_META)


static func _release(id: int, prop: String, tw: Tween) -> void:
	var node := instance_from_id(id) as Node
	if node == null or not node.has_meta(_META):
		return
	var owners: Dictionary = node.get_meta(_META)
	if owners.get(prop) == tw:
		owners.erase(prop)


# ---------------------------------------------------------------------------
# Common moves
# ---------------------------------------------------------------------------
## Press feedback on a visual (never on the hit region itself).
static func press(visual: Control, down: bool) -> void:
	if visual == null or not is_instance_valid(visual):
		return
	visual.pivot_offset = visual.size * 0.5
	if reduced():
		stop(visual, "scale")
		visual.scale = Vector2.ONE
		return
	if down:
		animate(visual, "scale", Vector2.ONE * PRESS_SCALE, PRESS_IN, Tween.TRANS_QUAD, Tween.EASE_OUT)
	else:
		animate(visual, "scale", Vector2.ONE, PRESS_OUT, Tween.TRANS_BACK, Tween.EASE_OUT)


## Fade in, with a short rise (none with Reduced Motion).  `visual` must be
## free to move: a child the containers don't position, or a top-level sheet.
static func appear(visual: Control, rise: float = 10.0, dur: float = PANEL) -> void:
	if visual == null or not is_instance_valid(visual):
		return
	visual.modulate.a = 0.0
	animate(visual, "modulate:a", 1.0, dur, Tween.TRANS_QUAD, Tween.EASE_OUT)
	if not reduced() and rise != 0.0:
		var end := visual.position
		visual.position = end + Vector2(0, rise)
		animate(visual, "position", end, dur, Tween.TRANS_CUBIC, Tween.EASE_OUT)


## Fade a control that lives inside a container (containers own its
## position, so only opacity and a slight scale settle are animated).
static func settle_in(visual: Control, dur: float = PANEL) -> void:
	if visual == null or not is_instance_valid(visual):
		return
	visual.modulate.a = 0.0
	animate(visual, "modulate:a", 1.0, dur, Tween.TRANS_QUAD, Tween.EASE_OUT)
	if reduced():
		visual.scale = Vector2.ONE
		return
	visual.pivot_offset = visual.size * 0.5
	visual.scale = Vector2.ONE * 0.985
	animate(visual, "scale", Vector2.ONE, dur, Tween.TRANS_CUBIC, Tween.EASE_OUT)


## Fade out, then call `then` (e.g. queue_free).  Interrupting it with
## another opacity animation cancels the callback too.
static func vanish(visual: Control, then: Callable = Callable(), dur: float = FAST) -> void:
	if visual == null or not is_instance_valid(visual):
		return
	var tw := animate(visual, "modulate:a", 0.0, dur, Tween.TRANS_QUAD, Tween.EASE_IN)
	if then.is_valid():
		if tw == null:
			then.call()
		else:
			tw.tween_callback(then)
