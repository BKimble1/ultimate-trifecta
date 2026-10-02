class_name InputRouter
extends Node
## Action-based input shared by keyboard (testing), touch and game controllers.
## Gameplay reads merged intent from here; it never reads devices directly.

signal device_changed(kind: String)
signal controller_connection_changed(connected: bool, name: String)

const ACTIONS := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"jump": [KEY_SPACE],
	"sprint": [KEY_SHIFT],
	"tag": [KEY_F],
	"interact": [KEY_E],
	"gadget": [KEY_Q],
	"pause": [KEY_ESCAPE],
	"cam_left": [KEY_J],
	"cam_right": [KEY_L],
	"cam_up": [KEY_I],
	"cam_down": [KEY_K],
	"emote_1": [KEY_1], "emote_2": [KEY_2], "emote_3": [KEY_3], "emote_4": [KEY_4],
	"spectate_next": [KEY_TAB],
}
const JOY_BUTTONS := {
	"jump": [JOY_BUTTON_A],
	"sprint": [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER],
	"tag": [JOY_BUTTON_X],
	"interact": [JOY_BUTTON_Y],
	"gadget": [JOY_BUTTON_B],
	"pause": [JOY_BUTTON_START],
	"emote_1": [JOY_BUTTON_DPAD_UP], "emote_2": [JOY_BUTTON_DPAD_RIGHT], "emote_3": [JOY_BUTTON_DPAD_DOWN], "emote_4": [JOY_BUTTON_DPAD_LEFT],
	"spectate_next": [JOY_BUTTON_RIGHT_SHOULDER],
}

var device := "touch"            # "touch" | "keyboard" | "gamepad"
var controller_name := ""
var sensitivity := 1.0
var invert_y := false
var sprint_threshold := 0.88     # touch: stick deflection that triggers sprint
var touch_sprint_enabled := true

# touch state written by TouchControls
var touch_move := Vector2.ZERO   # x right, y forward (screen up); radial dead zone applied
var touch_look_px := Vector2.ZERO  # accumulated camera drag, UNSCALED screen pixels
var touch_held := 0
var touch_sprint := false        # edge-sprint (with hysteresis) or the hold-to-sprint button
var touch_drive := 0.0
var touch_steer := 0.0
## Camera drag sensitivity: radians per point (pixels / screen scale), so the
## same finger travel turns the camera the same amount on any device.
const TOUCH_RAD_PER_PT := 0.0065

## Press edges from every source (touch taps, keys, controller buttons) in
## arrival order: [{bit, ms}].  Each simulation tick takes edges in order
## until one repeats an action already taken this tick, so jump-then-dive is
## never merged into one press on any device.  Bounded, and edges older than
## EDGE_TTL_MS are dropped (a press made in a menu or before a hitch never
## fires later in play).
const MAX_EDGES := 12
const EDGE_TTL_MS := 350
var _edges: Array[Dictionary] = []
var _look_acc := Vector2.ZERO
var _emote_req := -1
var _mouse_look := false

## Controller arbitration: sticks and prompts follow one active controller
## (the last one with a button press or a deliberate stick push), so a second
## idle or drifting pad can't fight it.
var active_joy := -1
var family := "none"             # xbox | playstation | mfi | nintendo | generic | none
const STICK_SWITCH := 0.55       # stick push that counts as "using the controller"
const DEVICE_SWITCH_HOLD_S := 0.5
var _last_switch_ms := 0
var _touch_points := 0           # fingers down on the game surface (TouchControls)
var _look_full_t := 0.0          # seconds the right stick has been near full tilt

## Stick response (radial dead zones, then a curve).
const MOVE_INNER := 0.15
const MOVE_OUTER := 0.95
const LOOK_INNER := 0.12
const LOOK_OUTER := 0.95
const LOOK_EXPO := 1.7
const LOOK_YAW_RATE := 3.0       # rad/s at full tilt
const LOOK_PITCH_RATE := 1.8
const LOOK_BOOST := 1.45         # extra turn rate after holding full tilt
const LOOK_BOOST_DELAY_S := 0.3
const LOOK_BOOST_RAMP_S := 0.35


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_install_actions()
	Input.joy_connection_changed.connect(_on_joy)
	for id in Input.get_connected_joypads():
		_activate_joy(id)
	if OS.has_feature("pc") and not OS.has_feature("mobile") and not UIKit.emulate_phone():
		device = "keyboard"   # desktop; --emulate-phone keeps the touch layout for evidence runs


func _install_actions() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for k in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	for action in JOY_BUTTONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for b in JOY_BUTTONS[action]:
			var jb := InputEventJoypadButton.new()
			jb.button_index = b
			InputMap.action_add_event(action, jb)
	# menu tabs (creator categories): shoulders / Q and E
	for pair in [["menu_prev", JOY_BUTTON_LEFT_SHOULDER, KEY_Q], ["menu_next", JOY_BUTTON_RIGHT_SHOULDER, KEY_E]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0], 0.2)
		var mb := InputEventJoypadButton.new()
		mb.button_index = pair[1]
		InputMap.action_add_event(pair[0], mb)
		var mk := InputEventKey.new()
		mk.physical_keycode = pair[2]
		InputMap.action_add_event(pair[0], mk)
	# accept/cancel on controllers for menus (Godot defaults cover keyboard)
	var acc := InputEventJoypadButton.new()
	acc.button_index = JOY_BUTTON_A
	InputMap.action_add_event("ui_accept", acc)
	var can := InputEventJoypadButton.new()
	can.button_index = JOY_BUTTON_B
	InputMap.action_add_event("ui_cancel", can)


func _on_joy(id: int, connected: bool) -> void:
	if connected:
		_activate_joy(id)
		controller_connection_changed.emit(true, controller_name)
		_set_device("gamepad", true)
		return
	if id == active_joy:
		active_joy = -1
		controller_name = ""
		family = "none"
		var rest := Input.get_connected_joypads()
		if not rest.is_empty():
			_activate_joy(rest[0])
	clear_edges()
	controller_connection_changed.emit(not Input.get_connected_joypads().is_empty(), controller_name)
	if Input.get_connected_joypads().is_empty():
		# restore touch immediately on mobile (keyboard on desktop)
		_set_device("touch" if OS.has_feature("mobile") else "keyboard", true)


func _activate_joy(id: int) -> void:
	if id == active_joy:
		return
	active_joy = id
	controller_name = Input.get_joy_name(id)
	family = family_of(controller_name, Input.get_joy_info(id))
	if device == "gamepad":
		device_changed.emit(device)   # prompts follow the new pad's family


## Controller family from the reported name / USB vendor.  Nintendo pads are
## identified but get positional glyphs: their A/B labels are swapped
## relative to the button positions games receive.
static func family_of(joy_name: String, info: Dictionary = {}) -> String:
	var n := joy_name.to_lower()
	var vendor := int(info.get("vendor_id", 0))
	if n.contains("xbox") or n.contains("xinput") or vendor == 0x045e:
		return "xbox"
	if n.contains("dualsense") or n.contains("dualshock") or n.contains("playstation") or n.contains("ps4") \
			or n.contains("ps5") or vendor == 0x054c:
		return "playstation"
	if n.contains("pro controller") or n.contains("joy-con") or n.contains("nintendo") or n.contains("switch") or vendor == 0x057e:
		return "nintendo"
	if n.contains("mfi") or n.contains("backbone") or n.contains("kishi") or n.contains("steelseries") or n.contains("nimbus"):
		return "mfi"
	return "generic"


## Device switches: a button/key/touch switches at once; stick motion only
## when it's a deliberate push, never while fingers are on the screen, and at
## most every DEVICE_SWITCH_HOLD_S, so drift can't flip prompts every frame.
func _set_device(kind: String, immediate: bool = false) -> void:
	if kind == device:
		return
	var now := Time.get_ticks_msec()
	if not immediate and now - _last_switch_ms < int(DEVICE_SWITCH_HOLD_S * 1000.0):
		return
	_last_switch_ms = now
	device = kind
	device_changed.emit(kind)


func has_controller() -> bool:
	return not Input.get_connected_joypads().is_empty()


## TouchControls reports fingers on the game surface (arbitration).
func set_touch_points(n: int) -> void:
	_touch_points = maxi(0, n)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			# backgrounding: nothing pressed before it may fire after it
			clear_edges()
			_look_acc = Vector2.ZERO
			_mouse_look = false


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_set_device("touch", true)
	elif event is InputEventJoypadButton:
		if (event as InputEventJoypadButton).pressed:
			_activate_joy(event.device)
			_set_device("gamepad", true)
	elif event is InputEventJoypadMotion:
		var jm := event as InputEventJoypadMotion
		if absf(jm.axis_value) > STICK_SWITCH and _touch_points == 0:
			_activate_joy(jm.device)
			_set_device("gamepad")
	elif event is InputEventKey and not event.is_echo():
		_set_device("keyboard", true)
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT and not OS.has_feature("mobile"):
		_mouse_look = (event as InputEventMouseButton).pressed
	if event is InputEventMouseMotion and _mouse_look:
		_look_acc += (event as InputEventMouseMotion).relative * 0.0035
	if not _gameplay_event(event):
		return
	for pair in [["jump", TC.BTN_JUMP], ["tag", TC.BTN_TAG], ["interact", TC.BTN_INTERACT], ["gadget", TC.BTN_GADGET]]:
		if event.is_action_pressed(pair[0], false, true):
			push_edge(int(pair[1]))
	for i in 4:
		if event.is_action_pressed("emote_%d" % (i + 1), false, true):
			_emote_req = i


## Keys typed into a text field are text, not gameplay; buttons from a pad
## other than the active one don't press anything.
func _gameplay_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		var vp := get_viewport()
		var fo: Control = vp.gui_get_focus_owner() if vp else null
		if fo is LineEdit or fo is TextEdit:
			return false
	if event is InputEventJoypadButton and active_joy >= 0 and event.device != active_joy:
		return false
	return true


## Radial dead zone: 0 inside `inner`, 1 beyond `outer` (worn sticks still
## reach full speed), linear in between; direction kept.
static func radial(v: Vector2, inner: float, outer: float) -> Vector2:
	var l := v.length()
	if l <= inner:
		return Vector2.ZERO
	return v / l * clampf((l - inner) / (outer - inner), 0.0, 1.0)


## Move stick curve: a gentle expo widens the walking range while full tilt
## stays full speed (walk < ~0.45, run, then sprint with the sprint button).
static func move_curve(m: float) -> float:
	return lerpf(m, m * m, 0.3)


## Screen-space move: x right, y forward. Analog magnitude preserved.
## A finger on the touch stick owns movement outright (a drifting pad can't
## pull against it); otherwise the active controller, then keys.
func get_move() -> Vector2:
	if touch_move != Vector2.ZERO:
		return touch_move.limit_length(1.0)
	var j := Vector2.ZERO
	if active_joy >= 0:
		j = radial(Vector2(Input.get_joy_axis(active_joy, JOY_AXIS_LEFT_X), -Input.get_joy_axis(active_joy, JOY_AXIS_LEFT_Y)), MOVE_INNER, MOVE_OUTER)
		if j != Vector2.ZERO:
			j = j.normalized() * move_curve(j.length())
	var v := Input.get_vector("move_left", "move_right", "move_back", "move_forward", 0.15)
	return (j if j.length() >= v.length() else v).limit_length(1.0)


## Camera look delta in radians (yaw, pitch) since the last call.  Touch and
## mouse are displacements (never scaled by delta); sticks/keys are rates.
func consume_look(delta: float) -> Vector2:
	var out := _look_acc * sensitivity
	_look_acc = Vector2.ZERO
	var pts := touch_look_px / maxf(1.0, DisplayServer.screen_get_scale())
	out += Vector2(pts.x, pts.y * 0.85) * TOUCH_RAD_PER_PT * sensitivity
	touch_look_px = Vector2.ZERO
	if active_joy >= 0:
		out += stick_look(Vector2(Input.get_joy_axis(active_joy, JOY_AXIS_RIGHT_X), Input.get_joy_axis(active_joy, JOY_AXIS_RIGHT_Y)), delta) * sensitivity
	var kx := Input.get_axis("cam_left", "cam_right")
	var ky := Input.get_axis("cam_up", "cam_down")
	out += Vector2(kx * 2.4, ky * 1.4) * delta * sensitivity
	if invert_y:
		out.y = -out.y
	return out


## Right-stick look rate -> radians this frame: radial dead zone, expo curve
## for fine aim, and a short ramp to a faster turn when held at full tilt.
func stick_look(raw: Vector2, delta: float) -> Vector2:
	var r := radial(raw, LOOK_INNER, LOOK_OUTER)
	if r == Vector2.ZERO:
		_look_full_t = 0.0
		return Vector2.ZERO
	var m := r.length()
	_look_full_t = _look_full_t + delta if m > 0.97 else 0.0
	var boost := 1.0 + (LOOK_BOOST - 1.0) * clampf((_look_full_t - LOOK_BOOST_DELAY_S) / LOOK_BOOST_RAMP_S, 0.0, 1.0)
	var c := r / m * pow(m, LOOK_EXPO) * boost
	return Vector2(c.x * LOOK_YAW_RATE, c.y * LOOK_PITCH_RATE) * delta


func held_bits() -> int:
	var b := touch_held
	if Input.is_action_pressed("jump"):
		b |= TC.BTN_JUMP
	if Input.is_action_pressed("sprint"):
		b |= TC.BTN_SPRINT
	if Input.is_action_pressed("tag"):
		b |= TC.BTN_TAG
	if touch_sprint and device == "touch":
		b |= TC.BTN_SPRINT
	return b


## Touch press edge (TouchControls); same ordered queue as keys and pads.
func queue_press(bit: int) -> void:
	push_edge(bit)


func push_edge(bit: int) -> void:
	if _edges.size() >= MAX_EDGES:
		_edges.pop_front()
	_edges.append({"bit": bit, "ms": Time.get_ticks_msec()})


## Press edges for this simulation tick (called once per tick): edges in
## arrival order until one repeats an action already taken (that one waits
## for the next tick), stale edges dropped.
func consume_pressed() -> int:
	var now := Time.get_ticks_msec()
	while not _edges.is_empty() and now - int(_edges[0]["ms"]) > EDGE_TTL_MS:
		_edges.pop_front()
	var b := 0
	while not _edges.is_empty():
		var bit := int(_edges[0]["bit"])
		if b & bit:
			break
		b |= bit
		_edges.pop_front()
	return b


func pending_edges() -> int:
	return _edges.size()


## Drop queued presses from every source (scene/focus changes, pause,
## backgrounding, controller disconnect).
func clear_edges() -> void:
	_edges.clear()
	_emote_req = -1


func consume_emote() -> int:
	var e := _emote_req
	_emote_req = -1
	return e


func request_emote(i: int) -> void:
	_emote_req = i


## Cart throttle: +1 accelerate, -1 brake/reverse.
func get_drive() -> float:
	var d := touch_drive
	for id in Input.get_connected_joypads():
		var r := Input.get_joy_axis(id, JOY_AXIS_TRIGGER_RIGHT)
		var l := Input.get_joy_axis(id, JOY_AXIS_TRIGGER_LEFT)
		if absf(r - l) > absf(d):
			d = r - l
	var k := Input.get_axis("move_back", "move_forward")
	if absf(k) > absf(d):
		d = k
	return clampf(d, -1.0, 1.0)


func get_steer() -> float:
	var s := touch_steer
	var m := get_move()
	if absf(m.x) > absf(s):
		s = m.x
	return clampf(s, -1.0, 1.0)


func reset_touch() -> void:
	touch_move = Vector2.ZERO
	touch_look_px = Vector2.ZERO
	touch_held = 0
	touch_sprint = false
	clear_edges()
	touch_drive = 0.0
	touch_steer = 0.0


## Button for an action, by position (south/east/west/north face buttons,
## shoulders, triggers, menu) or keyboard key; Glyphs draws it per family.
const PAD_SLOTS := {"jump": "south", "gadget": "east", "tag": "west", "interact": "north", "sprint": "l1",
	"accelerate": "r2", "brake": "l2", "pause": "menu", "spectate_next": "r1", "emote_1": "dpad_up",
	"menu_prev": "l1", "menu_next": "r1", "accept": "south", "back": "east"}
const KEY_NAMES := {"jump": "Space", "sprint": "Shift", "tag": "F", "interact": "E", "gadget": "Q", "pause": "Esc",
	"accelerate": "W", "brake": "S", "spectate_next": "Tab", "emote_1": "1", "menu_prev": "Q", "menu_next": "E",
	"accept": "Enter", "back": "Esc"}
const LABELS := {
	"xbox": {"south": "A", "east": "B", "west": "X", "north": "Y", "l1": "LB", "r1": "RB", "l2": "LT", "r2": "RT", "menu": "Menu", "dpad_up": "D-pad"},
	"playstation": {"south": "cross", "east": "circle", "west": "square", "north": "triangle", "l1": "L1", "r1": "R1", "l2": "L2", "r2": "R2", "menu": "Options", "dpad_up": "D-pad"},
	"mfi": {"south": "A", "east": "B", "west": "X", "north": "Y", "l1": "L1", "r1": "R1", "l2": "L2", "r2": "R2", "menu": "Menu", "dpad_up": "D-pad"},
	"nintendo": {"south": "pos", "east": "pos", "west": "pos", "north": "pos", "l1": "L", "r1": "R", "l2": "ZL", "r2": "ZR", "menu": "+", "dpad_up": "D-pad"},
	"generic": {"south": "pos", "east": "pos", "west": "pos", "north": "pos", "l1": "L1", "r1": "R1", "l2": "L2", "r2": "R2", "menu": "Menu", "dpad_up": "D-pad"},
}


## {kind: "pad"|"key"|"", slot, label} for an action on the current device.
func prompt_info(action: String) -> Dictionary:
	if device == "gamepad":
		var slot := String(PAD_SLOTS.get(action, ""))
		var fam := family if LABELS.has(family) else "generic"
		return {"kind": "pad", "slot": slot, "label": String(LABELS[fam].get(slot, "")), "family": fam}
	if device == "keyboard":
		return {"kind": "key", "slot": "", "label": String(KEY_NAMES.get(action, action)), "family": "keyboard"}
	return {"kind": "", "slot": "", "label": "", "family": "touch"}


## Text prompt for an action on the current device ("" on touch).
func prompt(action: String) -> String:
	var p := prompt_info(action)
	match String(p["label"]):
		"cross":
			return "Cross"
		"circle":
			return "Circle"
		"square":
			return "Square"
		"triangle":
			return "Triangle"
		"pos":
			return {"south": "Bottom button", "east": "Right button", "west": "Left button", "north": "Top button"}.get(p["slot"], "")
	return String(p["label"])
