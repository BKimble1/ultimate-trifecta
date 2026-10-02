class_name QualityGovernor
extends Node
## V6: keeps the pace steady when the phone can't hold the preset (heat, a
## heavy view): during a round it lowers the 3D render scale one step after
## the frame interval has stayed over budget, and raises it again only after
## a long steady stretch, with hysteresis and back-off.  The UI is 2D and is
## never scaled (it stays crisp).  MSAA, shadows and other features are not
## toggled mid-round: a render-scale change reallocates the 3D buffers once
## but compiles no new pipelines.  iOS "serious"/"critical" thermal state
## also steps down.  Every change is marked on the diagnostics timeline.

## Scale steps per preset (the first is the preset's own scale).
const STEPS := {1: [1.0, 0.9, 0.8, 0.72], 0: [0.8, 0.72, 0.65]}
const WINDOW_S := 3.0         # judge the pace over this long
const DOWN_RATIO := 1.18      # 75th percentile interval over budget by 18 %
const UP_STEADY_S := 20.0     # this long at budget before trying a step up
const UP_RATIO := 1.06
const COOLDOWN_S := 5.0       # no two changes closer than this
const BACKOFF_MAX_S := 120.0

var preset := 1
var level := 0                # index into STEPS[preset]
var target_ms := 16.7
var _t := 0.0
var _last_change := -100.0
var _steady := 0.0
var _up_wait := UP_STEADY_S
var _window: Array = []       # [t, ms]
var _last_us := 0
var _thermal := -1
var _thermal_check := 0.0
var _root: Viewport


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	preset = int(Save.get_setting("quality", 1))
	if not STEPS.has(preset):
		preset = 1
	target_ms = 1000.0 / float(Engine.max_fps) if Engine.max_fps > 0 else 16.7
	_root = get_viewport()


func _exit_tree() -> void:
	# back to the preset's own scale for menus
	if _root != null and is_instance_valid(_root):
		_root.scaling_3d_scale = float(STEPS[preset][0])


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_us > 0:
		feed((now - _last_us) / 1000.0, delta)
	_last_us = now
	_thermal_check -= delta
	if _thermal_check <= 0.0:
		_thermal_check = 5.0
		_thermal = Diag.thermal_state()


## One frame interval (ms).  Separate from _process so tests can drive it.
func feed(ms: float, delta: float) -> void:
	_t += delta
	_window.append([_t, ms])
	while not _window.is_empty() and _t - float(_window[0][0]) > WINDOW_S:
		_window.pop_front()
	if _t < WINDOW_S:
		return
	var p75 := _percentile(0.75)
	var p90 := _percentile(0.9)
	var steps: Array = STEPS[preset]
	var since := _t - _last_change
	var hot := _thermal >= 2
	if (p75 > target_ms * DOWN_RATIO or (hot and level < 1)) and level < steps.size() - 1 and since >= COOLDOWN_S:
		_set_level(level + 1, "slow" if not hot else "thermal")
		if since < _up_wait + COOLDOWN_S * 2.0:
			# the last step up didn't hold: wait longer before the next try
			_up_wait = minf(_up_wait * 2.0, BACKOFF_MAX_S)
		_steady = 0.0
		return
	if p90 <= target_ms * UP_RATIO and not hot:
		_steady += delta
	else:
		_steady = 0.0
	if level > 0 and _steady >= _up_wait and since >= COOLDOWN_S:
		_set_level(level - 1, "steady")
		_steady = 0.0


func scale() -> float:
	return float(STEPS[preset][level])


func _set_level(l: int, why: String) -> void:
	level = l
	_last_change = _t
	_window.clear()
	if _root != null and is_instance_valid(_root):
		_root.scaling_3d_scale = scale()
	Diag.mark("render_scale_%.2f_%s" % [scale(), why])


func _percentile(p: float) -> float:
	var v: Array = []
	for e in _window:
		v.append(float(e[1]))
	v.sort()
	if v.is_empty():
		return 0.0
	return float(v[mini(v.size() - 1, int(p * v.size()))])
