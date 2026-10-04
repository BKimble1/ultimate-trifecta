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
##
## V8: a lower render scale only helps when the GPU is the bottleneck.  The
## governor reads the renderer's GPU time for the 3D view each frame (the
## driver's timestamps; Diag.request_render_timing) and, when the pace is
## slow but the GPU had clear headroom (its p75 under GPU_IDLE_RATIO of the
## budget), treats the frame as CPU-bound: the scale stays (no blur that
## could not help) and the diagnostics count a "slow_cpu" window.  With no
## GPU timing (some drivers return none) it acts as before.  Thermal
## "serious"/"critical" still steps down whatever the cause.

## Scale steps per preset (the first is the preset's own scale).
const STEPS := {1: [1.0, 0.9, 0.8, 0.72], 0: [0.8, 0.72, 0.65]}
const WINDOW_S := 3.0         # judge the pace over this long
const DOWN_RATIO := 1.18      # 75th percentile interval over budget by 18 %
const UP_STEADY_S := 20.0     # this long at budget before trying a step up
const UP_RATIO := 1.06
const COOLDOWN_S := 5.0       # no two changes closer than this
const BACKOFF_MAX_S := 120.0
const GPU_IDLE_RATIO := 0.6   # GPU p75 under this share of the budget: not GPU-bound
const GPU_BUSY_RATIO := 0.8   # over this: GPU-bound

var preset := 1
var level := 0                # index into STEPS[preset]
var target_ms := 16.7
var _t := 0.0
var _last_change := -100.0
var _steady := 0.0
var _up_wait := UP_STEADY_S
## V8: the window is a fixed ring (no per-frame allocation or pop_front) and
## is sorted once per frame for both percentiles (V6-V7 rebuilt and sorted
## a fresh array twice per frame)
const RING := 1024            # WINDOW_S of intervals at up to ~340 fps
var _ring_t := PackedFloat64Array()
var _ring_ms := PackedFloat32Array()
var _ring_gpu := PackedFloat32Array()   # GPU time per frame (ms; < 0 = none)
var cause := ""               # last slow window's cause: gpu / cpu / mixed / unknown / thermal
var stat_causes := {}         # cause -> slow windows judged
var _cpu_mark_t := -100.0
var _head := 0                # oldest entry
var _n := 0                   # entries in the window
var _last_us := 0
var _thermal := -1
var _thermal_check := 0.0
var _root: Viewport
var _resume_skip := 0
var _window_start := 0.0      # judge only once a full window has been seen


func _init() -> void:
	_ring_t.resize(RING)
	_ring_ms.resize(RING)
	_ring_gpu.resize(RING)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	preset = int(Save.get_setting("quality", 1))
	if not STEPS.has(preset):
		preset = 1
	target_ms = 1000.0 / float(Engine.max_fps) if Engine.max_fps > 0 else 16.7
	_root = get_viewport()
	Diag.request_render_timing(true)


func _exit_tree() -> void:
	# back to the preset's own scale for menus
	if _root != null and is_instance_valid(_root):
		_root.scaling_3d_scale = float(STEPS[preset][0])
	Diag.request_render_timing(false)


## Back from the background: the frame that spans the time away (and the
## few right after, while iOS restores the surface) say nothing about the
## phone's pace; start a fresh window.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_RESUMED \
			or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_last_us = 0
		_n = 0
		_window_start = _t
		_steady = 0.0
		_resume_skip = 3


func _process(delta: float) -> void:
	var tp := Prof.t()
	_process_gov(delta)
	Prof.add("governor", tp)


func _process_gov(delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _resume_skip > 0:
		_resume_skip -= 1
		_last_us = now
		return
	if _last_us > 0:
		var gpu := -1.0
		if _root != null and DisplayServer.get_name() != "headless":
			gpu = RenderingServer.viewport_get_measured_render_time_gpu(_root.get_viewport_rid())
			if gpu <= 0.0:
				gpu = -1.0
		feed((now - _last_us) / 1000.0, delta, gpu)
	_last_us = now
	_thermal_check -= delta
	if _thermal_check <= 0.0:
		_thermal_check = 5.0
		_thermal = Diag.thermal_state()


## One frame interval (ms), and the frame's GPU time when the driver gives
## one.  Separate from _process so tests can drive it.
func feed(ms: float, delta: float, gpu_ms: float = -1.0) -> void:
	_t += delta
	if _n == RING:
		_head = (_head + 1) % RING
		_n -= 1
	var at := (_head + _n) % RING
	_ring_t[at] = _t
	_ring_ms[at] = ms
	_ring_gpu[at] = gpu_ms
	_n += 1
	while _n > 0 and _t - _ring_t[_head] > WINDOW_S:
		_head = (_head + 1) % RING
		_n -= 1
	if _t - _window_start < WINDOW_S:
		return
	var sorted := _sorted_window()
	var p75 := _pick(sorted, 0.75)
	var p90 := _pick(sorted, 0.9)
	var steps: Array = STEPS[preset]
	var since := _t - _last_change
	var hot := _thermal >= 2
	var slow := p75 > target_ms * DOWN_RATIO
	if slow and not hot and since >= COOLDOWN_S:
		cause = _cause()
		if cause == "cpu":
			# CPU-bound: a lower scale would only blur; keep it, say so once
			# per cooldown on the diagnostics timeline
			stat_causes["cpu"] = int(stat_causes.get("cpu", 0)) + 1
			if _t - _cpu_mark_t >= COOLDOWN_S:
				_cpu_mark_t = _t
				Diag.mark("slow_cpu")
			_steady = 0.0
			return
	if (slow or (hot and level < 1)) and level < steps.size() - 1 and since >= COOLDOWN_S:
		if hot:
			cause = "thermal"
		stat_causes[cause] = int(stat_causes.get(cause, 0)) + 1
		_set_level(level + 1, cause if cause != "" else "slow")
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


## What a slow window is bound by, from the GPU times in it: "gpu", "cpu",
## "mixed", or "unknown" (fewer than half its frames have a GPU time).
func _cause() -> String:
	var g := PackedFloat32Array()
	for i in _n:
		var v := _ring_gpu[(_head + i) % RING]
		if v >= 0.0:
			g.append(v)
	if g.size() * 2 < _n:
		return "unknown"
	g.sort()
	var gp75 := g[mini(g.size() - 1, int(0.75 * g.size()))]
	if gp75 < target_ms * GPU_IDLE_RATIO:
		return "cpu"
	if gp75 >= target_ms * GPU_BUSY_RATIO:
		return "gpu"
	return "mixed"


func scale() -> float:
	return float(STEPS[preset][level])


func _set_level(l: int, why: String) -> void:
	level = l
	_last_change = _t
	_n = 0
	if _root != null and is_instance_valid(_root):
		_root.scaling_3d_scale = scale()
	Diag.mark("render_scale_%.2f_%s" % [scale(), why])


func _sorted_window() -> PackedFloat32Array:
	var v: PackedFloat32Array
	if _head + _n <= RING:
		v = _ring_ms.slice(_head, _head + _n)
	else:
		v = _ring_ms.slice(_head)
		v.append_array(_ring_ms.slice(0, _head + _n - RING))
	v.sort()
	return v


static func _pick(sorted: PackedFloat32Array, p: float) -> float:
	if sorted.is_empty():
		return 0.0
	return sorted[mini(sorted.size() - 1, int(p * sorted.size()))]


## The window's p-th percentile interval (ms).
func _percentile(p: float) -> float:
	return _pick(_sorted_window(), p)
