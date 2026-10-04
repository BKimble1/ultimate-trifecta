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
##  * V7 (forward drift): the dynamic stick's *logical* origin is where the
##    thumb touched down, so a touchdown is always neutral.  The ring is
##    drawn at that origin clamped on screen (stick_center), and the knob at
##    ring + the real offset (knob_pos()), so what is drawn is what is read.
##    Before V7 the origin itself was clamped: a thumb resting near the
##    bottom-left corner started at full deflection, and an exact vertical
##    push ran mostly sideways.
##  * A narrow, continuous straight-ahead tolerance around forward and back
##    absorbs a thumb's lean and wobble (see straighten()).
##  * A spare finger resting in the stick zone (a look pointer started there)
##    turns the camera only after it has clearly moved (LOOK_SLOP_PX).

const KIND_NONE := 0
const KIND_STICK := 1
const KIND_LOOK := 2
const KIND_BUTTON := 3

var view_size := Vector2(1280, 720)
var stick_zone_frac := 0.45          # left part of the screen that spawns the stick
## The dynamic stick's zone in screen space (TouchLayout: that side of the
## screen below the top HUD band, mirrored layouts on the right).  Empty =
## the left stick_zone_frac of the view.
var stick_zone := Rect2()
var stick_radius := 92.0             # canvas units
var fixed_stick := false
var fixed_center := Vector2(200, 520)
var follow_at := 1.6                 # dynamic base follows beyond this many radii
var dead_zone := 0.12                # radial, fraction of the radius
## Straight-ahead tolerance (degrees from the forward/back axis): inside
## STRAIGHT_DEG the direction is exactly forward/back; from there to
## STRAIGHT_BLEND_DEG it blends back continuously to the thumb's own angle;
## beyond, untouched.  Magnitude is never changed.  Chosen from the probe
## traces (tools/stick_probe.sh): a 4-6 degree thumb lean, the measured
## source of curving, falls inside; a deliberate 15 degree heading is kept.
const STRAIGHT_DEG := 6.0
const STRAIGHT_BLEND_DEG := 16.0
var straight_assist := true
## Unscaled screen pixels a look pointer that started in the stick zone must
## travel before it turns the camera (about 3 mm on a phone).
const LOOK_SLOP_PX := 24.0
var sprint_on := 0.88                # edge-sprint hysteresis (fraction of radius)
var sprint_off := 0.76
var edge_sprint := true
var buttons: Dictionary = {}         # name -> {"c": Vector2, "r": float, "hit": float (optional)}
var reserved: Array[Rect2] = []      # HUD regions that are not camera/stick

var owners: Dictionary = {}          # pointer index -> {"kind": int, "btn": String}
var stick_index := -1
var stick_center := Vector2.ZERO     # where the ring is DRAWN (dynamic: the origin clamped on screen)
var stick_origin := Vector2.ZERO     # where deflection is measured FROM (dynamic: the touchdown point)
var stick_pos := Vector2.ZERO
var follows := 0                     # base-follow steps this gesture (diagnostics)
var sprinting := false
var look_px := Vector2.ZERO          # unscaled screen pixels since last consume
var _edges: Array[String] = []       # button press edges, consumed once


func zone() -> Rect2:
	if stick_zone.has_area():
		return stick_zone
	return Rect2(0.0, 0.0, view_size.x * stick_zone_frac, view_size.y)


func spawn_center_for(p: Vector2) -> Vector2:
	if fixed_stick:
		return fixed_center
	# keep the whole ring on screen and inside the stick zone (a screen edge
	# keeps the full ring clear; the inner side may overlap by half)
	var z := zone()
	var m := stick_radius + 16.0
	var lo := z.position.x + (m if z.position.x <= 0.5 else m * 0.5)
	var hi := z.end.x - (m if z.end.x >= view_size.x - 0.5 else m * 0.5)
	return Vector2(clampf(p.x, lo, maxf(lo, hi)), clampf(p.y, view_size.y * 0.32, view_size.y - m))


func hit_button(p: Vector2) -> String:
	var best := ""
	var best_d := INF
	for name in buttons:
		var b: Dictionary = buttons[name]
		var d := p.distance_to(b["c"])
		if d <= float(b.get("hit", float(b["r"]) + 14.0)) and d < best_d:
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
	if zone().has_point(p) and stick_index < 0:
		owners[index] = {"kind": KIND_STICK, "btn": ""}
		stick_index = index
		# fixed stick: deflection from its fixed centre (a touch off-centre is
		# deliberate); dynamic: the touchdown is neutral wherever the ring is drawn
		stick_origin = fixed_center if fixed_stick else p
		stick_center = spawn_center_for(p)
		stick_pos = p
		sprinting = false
		follows = 0
		return
	# a look pointer that starts in the stick zone (a spare finger near the
	# stick) needs a clear movement before it turns the camera
	owners[index] = {"kind": KIND_LOOK, "btn": "", "slop": LOOK_SLOP_PX if zone().has_point(p) else 0.0, "net": Vector2.ZERO}


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
				# the base follows a thumb that drifts far away: along the
				# thumb's own direction, so the direction read never jumps
				var off := stick_pos - stick_origin
				if off.length() > stick_radius * follow_at:
					stick_origin = stick_pos - off.normalized() * stick_radius * follow_at
					stick_center = spawn_center_for(stick_origin)
					follows += 1
		KIND_LOOK:
			var slop := float(o.get("slop", 0.0))
			if slop > 0.0:
				# net travel from where it landed (touch-screen jitter cancels out)
				var net: Vector2 = o["net"] + screen_relative
				o["net"] = net
				if net.length() < slop:
					return
				o["slop"] = 0.0      # from here on every pixel turns the camera;
				# only the travel beyond the slop counts (no jump on crossing it)
				look_px += net - net.normalized() * slop
				return
			look_px += screen_relative


## Deflection before the dead zone and straight-ahead tolerance (diagnostics).
func raw_vector() -> Vector2:
	if stick_index < 0:
		return Vector2.ZERO
	var raw := (stick_pos - stick_origin) / stick_radius
	return Vector2(raw.x, -raw.y)


## The knob as drawn: the ring plus the real offset (never beyond the rim).
func knob_pos() -> Vector2:
	return stick_center + (stick_pos - stick_origin).limit_length(stick_radius)


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
	var raw := (stick_pos - stick_origin) / stick_radius
	var m := raw.length()
	if m <= dead_zone:
		_update_sprint(0.0)
		return Vector2.ZERO
	var out_m := clampf((m - dead_zone) / (1.0 - dead_zone), 0.0, 1.0)
	_update_sprint(minf(m, 1.0))
	var dir := raw / m
	var v := Vector2(dir.x, -dir.y) * out_m
	return straighten(v) if straight_assist else v


## Straight-ahead tolerance around forward and back (x right, y forward):
## within STRAIGHT_DEG of the axis the direction is exactly on it, then it
## blends linearly back to the thumb's own angle at STRAIGHT_BLEND_DEG.
## Continuous (no snap, no hysteresis to reset), magnitude kept, sideways and
## diagonals untouched.
static func straighten(v: Vector2) -> Vector2:
	var m := v.length()
	if m <= 0.0:
		return v
	var a := atan2(v.x, absf(v.y))       # signed angle off the forward/back axis
	var aa := absf(a)
	var b := deg_to_rad(STRAIGHT_DEG)
	var e := deg_to_rad(STRAIGHT_BLEND_DEG)
	if aa >= e:
		return v
	var na := 0.0 if aa <= b else (aa - b) * e / (e - b)
	na *= signf(a)
	return Vector2(sin(na), cos(na) * (1.0 if v.y >= 0.0 else -1.0)) * m


func _update_sprint(m: float) -> void:
	if not edge_sprint:
		sprinting = false
	elif sprinting:
		sprinting = m >= sprint_off
	else:
		sprinting = m >= sprint_on


func stick_active() -> bool:
	return stick_index >= 0
