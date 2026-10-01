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

var _pressed_acc := 0
var _press_queue: Array[int] = []   # touch press edges, one entry per tap
var _look_acc := Vector2.ZERO
var _emote_req := -1
var _mouse_look := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_install_actions()
	Input.joy_connection_changed.connect(_on_joy)
	for id in Input.get_connected_joypads():
		controller_name = Input.get_joy_name(id)
	if OS.has_feature("pc") and not OS.has_feature("mobile"):
		device = "keyboard"


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
	# accept/cancel on controllers for menus (Godot defaults cover keyboard)
	var acc := InputEventJoypadButton.new()
	acc.button_index = JOY_BUTTON_A
	InputMap.action_add_event("ui_accept", acc)
	var can := InputEventJoypadButton.new()
	can.button_index = JOY_BUTTON_B
	InputMap.action_add_event("ui_cancel", can)


func _on_joy(id: int, connected: bool) -> void:
	controller_name = Input.get_joy_name(id) if connected else ""
	controller_connection_changed.emit(connected, controller_name)
	if connected:
		_set_device("gamepad")
	elif Input.get_connected_joypads().is_empty():
		# restore touch immediately on mobile (keyboard on desktop)
		_set_device("touch" if OS.has_feature("mobile") else "keyboard")


func _set_device(kind: String) -> void:
	if kind != device:
		device = kind
		device_changed.emit(kind)


func has_controller() -> bool:
	return not Input.get_connected_joypads().is_empty()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_set_device("touch")
	elif event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.4):
		_set_device("gamepad")
	elif event is InputEventKey and not event.is_echo():
		_set_device("keyboard")
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT and not OS.has_feature("mobile"):
		_mouse_look = (event as InputEventMouseButton).pressed
	if event is InputEventMouseMotion and _mouse_look:
		_look_acc += (event as InputEventMouseMotion).relative * 0.0035
	for pair in [["jump", TC.BTN_JUMP], ["tag", TC.BTN_TAG], ["interact", TC.BTN_INTERACT], ["gadget", TC.BTN_GADGET]]:
		if event.is_action_pressed(pair[0], false, true):
			_pressed_acc |= int(pair[1])
	for i in 4:
		if event.is_action_pressed("emote_%d" % (i + 1), false, true):
			_emote_req = i


## Screen-space move: x right, y forward. Analog magnitude preserved.
func get_move() -> Vector2:
	var v := Input.get_vector("move_left", "move_right", "move_back", "move_forward", 0.15)
	var j := Vector2.ZERO
	for id in Input.get_connected_joypads():
		var jx := Input.get_joy_axis(id, JOY_AXIS_LEFT_X)
		var jy := -Input.get_joy_axis(id, JOY_AXIS_LEFT_Y)
		var jv := Vector2(jx, jy)
		if jv.length() > 0.18:
			j = jv.normalized() * clampf((jv.length() - 0.18) / 0.82, 0.0, 1.0)
	var out := v
	if j.length() > out.length():
		out = j
	if touch_move.length() > out.length():
		out = touch_move
	return out.limit_length(1.0)


## Camera look delta in radians (yaw, pitch) since the last call.  Touch and
## mouse are displacements (never scaled by delta); sticks/keys are rates.
func consume_look(delta: float) -> Vector2:
	var out := _look_acc * sensitivity
	_look_acc = Vector2.ZERO
	var pts := touch_look_px / maxf(1.0, DisplayServer.screen_get_scale())
	out += Vector2(pts.x, pts.y * 0.85) * TOUCH_RAD_PER_PT * sensitivity
	touch_look_px = Vector2.ZERO
	for id in Input.get_connected_joypads():
		var rx := Input.get_joy_axis(id, JOY_AXIS_RIGHT_X)
		var ry := Input.get_joy_axis(id, JOY_AXIS_RIGHT_Y)
		var rv := Vector2(rx, ry)
		if rv.length() > 0.15:
			rv = rv.normalized() * pow(clampf((rv.length() - 0.15) / 0.85, 0.0, 1.0), 1.6)
			out += Vector2(rv.x * 3.0, rv.y * 1.8) * delta * sensitivity
	var kx := Input.get_axis("cam_left", "cam_right")
	var ky := Input.get_axis("cam_up", "cam_down")
	out += Vector2(kx * 2.4, ky * 1.4) * delta * sensitivity
	if invert_y:
		out.y = -out.y
	return out


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


## Queue a touch press edge; each simulation tick consumes at most one queued
## touch edge, so two quick taps (jump, then dive) are never merged.
func queue_press(bit: int) -> void:
	if _press_queue.size() < 8:
		_press_queue.append(bit)


## Press edges for this simulation tick (called once per tick).
func consume_pressed() -> int:
	var b := _pressed_acc
	_pressed_acc = 0
	if not _press_queue.is_empty():
		b |= _press_queue.pop_front()
	return b


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
	_press_queue.clear()
	touch_drive = 0.0
	touch_steer = 0.0


## Prompt label for an action on the current device.
func prompt(action: String) -> String:
	if device == "gamepad":
		var names := {"jump": "A", "sprint": "LB", "tag": "X", "interact": "Y", "gadget": "B", "pause": "Menu", "accelerate": "RT", "brake": "LT"}
		return names.get(action, action)
	if device == "keyboard":
		var keys := {"jump": "Space", "sprint": "Shift", "tag": "F", "interact": "E", "gadget": "Q", "pause": "Esc", "accelerate": "W", "brake": "S"}
		return keys.get(action, action)
	return ""
