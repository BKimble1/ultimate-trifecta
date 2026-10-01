class_name TouchRouter
extends RefCounted
## Pure touch-ownership logic for the match controls (no drawing, no nodes),
## so it can be unit-tested headless (tests/test_touch_input.gd).
##
## Rules
##  * Each pointer gets exactly one owner when it goes down, and keeps it
##    until it lifts or is cancelled: a button, the stick, the camera, or
##    "none" (ignored).  Buttons and reserved regions (pause, minimap) are
##    tested before anything else, so the camera never takes a button touch.
##  * Exactly one pointer owns movement.  A second finger in the stick zone
##    becomes a camera drag; it never moves the stick.
##  * Button holds are per pointer; a button is held while any pointer that
##    started on it is down.  Press edges are queued and consumed once.
##  * When the visible button set changes (cart entry/exit, role/state
##    change), pointers on buttons that vanished become "none" and release
##    them (e.g. gas is cleared when leaving a cart while holding it).
##  * cancel_all() clears everything (focus loss, backgrounding, pause,
##    scene change, controller takes over).
##  * Camera drags accumulate *unscaled* screen pixels (screen_relative).

const KIND_NONE := 0
const KIND_STICK := 1
const KIND_LOOK := 2
const KIND_BUTTON := 3

var view_size := Vector2(1280, 720)
var stick_zone_frac := 0.45          # left part of the screen that spawns the stick
var stick_radius := 92.0             # canvas units
var fixed_stick := false
var fixed_center := Vector2(200, 520)
var dead_zone := 0.12                # radial, fraction of the radius
var sprint_on := 0.88                # edge-sprint hysteresis (fraction of radius)
var sprint_off := 0.76
var edge_sprint := true
var buttons: Dictionary = {}         # name -> {"c": Vector2, "r": float}
var reserved: Array[Rect2] = []      # HUD regions that are not camera/stick

var owners: Dictionary = {}          # pointer index -> {"kind": int, "btn": String}
var stick_index := -1
var stick_center := Vector2.ZERO
var stick_pos := Vector2.ZERO
var sprinting := false
var look_px := Vector2.ZERO          # unscaled screen pixels since last consume
var _edges: Array[String] = []       # button press edges, consumed once


func spawn_center_for(p: Vector2) -> Vector2:
	if fixed_stick:
		return fixed_center
	# keep the whole ring on screen and inside the stick zone
	var m := stick_radius + 16.0
	return Vector2(clampf(p.x, m, view_size.x * stick_zone_frac - m * 0.5), clampf(p.y, view_size.y * 0.32, view_size.y - m))


func hit_button(p: Vector2) -> String:
	var best := ""
	var best_d := INF
	for name in buttons:
		var b: Dictionary = buttons[name]
		var d := p.distance_to(b["c"])
		if d <= float(b["r"]) + 14.0 and d < best_d:
			best = name
			best_d = d
	return best


func in_reserved(p: Vector2) -> bool:
	for r in reserved:
		if r.has_point(p):
			return true
	return false


func touch_down(index: int, p: Vector2) -> void:
	if owners.has(index):
		touch_up(index)
	var btn := hit_button(p)
	if btn != "":
		owners[index] = {"kind": KIND_BUTTON, "btn": btn}
		_edges.append(btn)
		return
	if in_reserved(p):
		owners[index] = {"kind": KIND_NONE, "btn": ""}
		return
	if p.x < view_size.x * stick_zone_frac and stick_index < 0:
		owners[index] = {"kind": KIND_STICK, "btn": ""}
		stick_index = index
		stick_center = spawn_center_for(p)
		stick_pos = p
		sprinting = false
		return
	owners[index] = {"kind": KIND_LOOK, "btn": ""}


func touch_up(index: int) -> void:
	var o: Dictionary = owners.get(index, {})
	owners.erase(index)
	if o.is_empty():
		return
	if int(o["kind"]) == KIND_STICK and index == stick_index:
		stick_index = -1
		sprinting = false


func drag(index: int, p: Vector2, screen_relative: Vector2) -> void:
	var o: Dictionary = owners.get(index, {})
	if o.is_empty():
		return
	match int(o["kind"]):
		KIND_STICK:
			stick_pos = p
			if not fixed_stick:
				# the base follows a thumb that drifts far away
				var off := stick_pos - stick_center
				if off.length() > stick_radius * 1.6:
					stick_center = stick_pos - off.normalized() * stick_radius * 1.6
		KIND_LOOK:
			look_px += screen_relative


func cancel_all() -> void:
	owners.clear()
	stick_index = -1
	sprinting = false
	look_px = Vector2.ZERO
	_edges.clear()


## Replace the visible button set; owners of vanished buttons are released.
func set_buttons(b: Dictionary) -> void:
	buttons = b
	for idx in owners.keys():
		var o: Dictionary = owners[idx]
		if int(o["kind"]) == KIND_BUTTON and not buttons.has(String(o["btn"])):
			owners[idx] = {"kind": KIND_NONE, "btn": ""}


func held() -> Dictionary:
	var h := {}
	for idx in owners:
		var o: Dictionary = owners[idx]
		if int(o["kind"]) == KIND_BUTTON:
			h[String(o["btn"])] = true
	return h


func is_held(btn: String) -> bool:
	return held().has(btn)


func take_edges() -> Array[String]:
	var e := _edges.duplicate()
	_edges.clear()
	return e


func take_look_px() -> Vector2:
	var v := look_px
	look_px = Vector2.ZERO
	return v


## Stick deflection (x right, y up/forward), radial dead zone remapped so the
## output starts at 0 just outside the dead zone and reaches 1 at the rim.
## Magnitude is preserved (sneaking works) and never exceeds 1 (no diagonal boost).
func move_vector() -> Vector2:
	if stick_index < 0:
		return Vector2.ZERO
	var raw := (stick_pos - stick_center) / stick_radius
	var m := raw.length()
	if m <= dead_zone:
		_update_sprint(0.0)
		return Vector2.ZERO
	var out_m := clampf((m - dead_zone) / (1.0 - dead_zone), 0.0, 1.0)
	_update_sprint(minf(m, 1.0))
	var dir := raw / m
	return Vector2(dir.x, -dir.y) * out_m


func _update_sprint(m: float) -> void:
	if not edge_sprint:
		sprinting = false
	elif sprinting:
		sprinting = m >= sprint_off
	else:
		sprinting = m >= sprint_on


func stick_active() -> bool:
	return stick_index >= 0
