extends Node
## Internal-beta diagnostics (Settings › Diagnostics, off by default).
##
## Everything stays in memory and is bounded: per-context histograms of the
## engine's frame interval, the last few hundred intervals, recent stalls
## and state markers.  Nothing is written to disk.  "Share summary" hands a
## plain-text report to the share sheet; it contains no player names, room
## codes or Game Center identifiers.
##
## What each number is:
##   frame interval     time between engine loop iterations, measured on the
##                      CPU (Time.get_ticks_usec).  It includes waiting for
##                      the display, so at a 60 fps cap the ideal is 16.67 ms.
##                      It is not GPU time and not the display's present time.
##   GPU render time    the renderer's own timestamp measurement of the main
##                      viewport (RenderingServer.viewport_get_measured_
##                      render_time_gpu).  Reported "unavailable" when the
##                      driver returns nothing.
##   CPU render time    the renderer's CPU-side time for the main viewport.
##   thermal state      iOS ProcessInfo.thermalState through the UTShare
##                      extension; "unavailable" elsewhere.
##   (V6) physics steps 60 Hz simulation ticks run in one frame.  2+ is the
##                      engine catching up; a long run of catch-up frames is
##                      the "smooth, then suddenly very glitchy" spiral (each
##                      catch-up frame takes longer, needing more ticks).
##   (V6) sim time      script time of the physics step(s) in the frame
##                      (Performance TIME_PHYSICS_PROCESS).
##   (V6) pipelines     render pipelines compiled, by source.  "draw" ones
##                      are compiled at draw time and can stall a frame; mesh/
##                      surface ones were prepared when the mesh loaded.
##   (V6) growth        node, object and orphan counts sampled every 10 s.

const RING := 1800          # last ~30 s of intervals at 60 fps
const MAX_MARKS := 160
const MAX_STALLS := 80
const HIST_MS := 250        # 1 ms buckets; the last one collects everything longer
const STALL_MS := 50.0
const ATTRIBUTE_S := 2.0    # a stall within this long after a marker is attributed to it
const TIMELINE := 240       # V6: recent frames kept for stall context (~4 s)
const STALL_CONTEXT := 12   # frames before a stall stored with it
const SPIRAL_FRAMES := 30   # consecutive catch-up frames that count as a spiral
const GROWTH_EVERY_S := 10.0

var enabled := false
var overlay := false
var _start_ms := 0
var _last_us := 0
var _ring := PackedFloat32Array()
var _ring_i := 0
var _ctx := "menu"
var _stats: Dictionary = {}      # context -> Dictionary
var _marks: Array = []           # {t, name}
var _counts: Dictionary = {}     # marker name -> count
var _stalls: Array = []          # {t, ms, ctx, mark, since}
var _last_mark := ""
var _last_mark_ms := -100000
var _thermal_worst := -1
var _thermal_now := -1
var _thermal_check := 0.0
var _net: Dictionary = {"rtt_n": 0, "rtt_sum": 0.0, "rtt_max": 0.0, "corr_n": 0, "corr_sum": 0.0, "corr_max": 0.0, "big": 0}
var _overlay_layer: CanvasLayer
var _overlay_lbl: Label
var _overlay_t := 0.0
var _measuring := false
# V6
var _phys_frames := -1
var _pipe_prev := PackedInt64Array([0, 0, 0, 0, 0])
var _timeline: Array = []        # [t_ms, interval_ms, steps, sim_ms, pipe_draw]
var _catchup_run := 0
var _growth: Array = []          # {t, nodes, objects, orphans, static_mb}
## V6: the same counts as each round goes live (the same moment in every
## round, so a leak across rounds shows as a steady climb); first + last 11
var _round_starts: Array = []
## V7 stick traces: one summary line per move-stick gesture (the last
## STICK_GESTURES) and the newest gesture sampled at 10 Hz (at most
## STICK_SAMPLES).  Numbers only.
const STICK_GESTURES := 12
const STICK_SAMPLES := 60
var _stick_g: Array = []
var _stick_cur: Dictionary = {}
var _stick_s: Array = []
var _growth_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -1000
	_ring.resize(RING)
	enabled = bool(Save.get_setting("diagnostics", false))
	overlay = enabled and bool(Save.get_setting("diag_overlay", false))
	_start_ms = Time.get_ticks_msec()
	_apply_measuring()
	_apply_overlay()


func set_enabled(on: bool) -> void:
	enabled = on
	Save.set_setting("diagnostics", on)
	if not on:
		set_overlay(false)
	_apply_measuring()


func set_overlay(on: bool) -> void:
	overlay = on and enabled
	Save.set_setting("diag_overlay", overlay)
	_apply_overlay()


func clear() -> void:
	_stats.clear()
	_marks.clear()
	_counts.clear()
	_stalls.clear()
	_ring.fill(0.0)
	_ring_i = 0
	_thermal_worst = -1
	_net = {"rtt_n": 0, "rtt_sum": 0.0, "rtt_max": 0.0, "corr_n": 0, "corr_sum": 0.0, "corr_max": 0.0, "big": 0}
	_start_ms = Time.get_ticks_msec()
	_timeline.clear()
	_growth.clear()
	_round_starts.clear()
	_catchup_run = 0
	_stick_g.clear()
	_stick_cur = {}
	_stick_s.clear()


func _apply_measuring() -> void:
	var want := enabled
	if want == _measuring or not is_inside_tree():
		return
	_measuring = want
	if DisplayServer.get_name() != "headless":
		RenderingServer.viewport_set_measure_render_time(get_tree().root.get_viewport_rid(), want)


## Where the player is (menu, lobby, loading, match, results).  Stats are
## kept per context so a lobby hitch doesn't hide inside match numbers.
static func context(name: String) -> void:
	var d := _node()
	if d:
		if name == "match" and d._ctx != "match" and d.enabled:
			d._round_starts.append(_counts_now())
			if d._round_starts.size() > 12:
				d._round_starts.remove_at(1)
		d._ctx = name


static func _counts_now() -> Dictionary:
	return {"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)), "orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0}


## A state marker: a stall shortly afterwards is attributed to it.
static func mark(name: String) -> void:
	var d := _node()
	if d == null or not d.enabled:
		return
	var now := Time.get_ticks_msec()
	d._last_mark = name
	d._last_mark_ms = now
	d._counts[name] = int(d._counts.get(name, 0)) + 1
	d._marks.append({"t": now - d._start_ms, "name": name})
	if d._marks.size() > MAX_MARKS:
		d._marks.pop_front()


## Network timing from the match (round trip, reconciliation size).
static func net_sample(rtt_s: float, correction_m: float) -> void:
	var d := _node()
	if d == null or not d.enabled:
		return
	if rtt_s > 0.0:
		d._net["rtt_n"] += 1
		d._net["rtt_sum"] += rtt_s * 1000.0
		d._net["rtt_max"] = maxf(d._net["rtt_max"], rtt_s * 1000.0)
	if correction_m >= 0.0:
		d._net["corr_n"] += 1
		d._net["corr_sum"] += correction_m
		d._net["corr_max"] = maxf(d._net["corr_max"], correction_m)
		if correction_m > 0.25:
			d._net["big"] += 1


## Per frame while playing (MatchController, only when enabled): the move
## stick's ownership, ring-vs-origin offset, raw and final vectors (x right,
## y forward), camera yaw, manual look and follow added this frame, travel
## velocity and base-follow count.
static func stick_tick(dt: float, owned: bool, ring_off: Vector2, raw: Vector2, out: Vector2, cam_yaw: float,
		look: float, follow: float, vel: Vector3, follows: int) -> void:
	var d := _node()
	if d == null or not d.enabled:
		return
	var g: Dictionary = d._stick_cur
	if not owned:
		if not g.is_empty():
			d._stick_g.append(g)
			if d._stick_g.size() > STICK_GESTURES:
				d._stick_g.pop_front()
			d._stick_cur = {}
		return
	if g.is_empty():
		g = {"t0": Time.get_ticks_msec() - d._start_ms, "dur": 0.0, "ring": ring_off.length(), "n": 0, "fx": 0.0, "fy": 0.0,
			"lean": 0.0, "yaw0": cam_yaw, "look": 0.0, "follow": 0.0, "follows": 0, "tlat": 0.0, "tfwd": 0.0, "k": 0}
		d._stick_cur = g
		d._stick_s.clear()
	g["dur"] = float(g["dur"]) + dt
	g["look"] = float(g["look"]) + absf(look)
	g["follow"] = float(g["follow"]) + follow
	g["follows"] = follows
	if out.y > 0.5:                     # held mostly forward
		g["n"] = int(g["n"]) + 1
		g["fx"] = float(g["fx"]) + absf(out.x)
		g["fy"] = float(g["fy"]) + out.y
		g["lean"] = maxf(float(g["lean"]), absf(rad_to_deg(atan2(raw.x, raw.y))))
		var fwd := Vector2(-sin(cam_yaw), -cos(cam_yaw))
		var hv := Vector2(vel.x, vel.z)
		g["tfwd"] = float(g["tfwd"]) + maxf(0.0, hv.dot(fwd)) * dt
		g["tlat"] = float(g["tlat"]) + absf(hv.dot(Vector2(-fwd.y, fwd.x))) * dt
	g["yaw1"] = cam_yaw
	g["k"] = int(g["k"]) + 1
	if int(g["k"]) % 6 == 1 and d._stick_s.size() < STICK_SAMPLES:
		var hv2 := Vector2(vel.x, vel.z)
		var rel := rad_to_deg(angle_difference(-cam_yaw, -atan2(-hv2.x, -hv2.y))) if hv2.length() > 0.5 else 0.0
		d._stick_s.append([float(g["dur"]), raw.x, raw.y, out.x, out.y, rad_to_deg(cam_yaw), rad_to_deg(look), rad_to_deg(follow) / maxf(dt, 1e-3), rel, hv2.length()])


static func _node() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Diag")


## V6: backgrounding (home, a call, Control Center).  The first frame after
## coming back spans the whole time away: it starts a fresh interval instead
## of being counted as a multi-second stall.  Both edges go on the timeline.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if _last_us != 0:
				mark("app_paused" if what == NOTIFICATION_APPLICATION_PAUSED else "app_focus_out")
			_last_us = 0
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			_last_us = 0
			mark("app_resumed" if what == NOTIFICATION_APPLICATION_RESUMED else "app_focus_in")


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_us == 0 or not enabled:
		_last_us = now
		return
	var ms := (now - _last_us) / 1000.0
	_last_us = now
	_record(ms)
	_record_v6(ms, _delta)
	_thermal_check -= _delta
	if _thermal_check <= 0.0:
		_thermal_check = 5.0
		var th := thermal_state()
		if th != _thermal_now and th >= 0:
			if _thermal_now >= 0:
				mark("thermal_" + _thermal_name(th))
			_thermal_now = th
		_thermal_worst = maxi(_thermal_worst, th)
	if overlay:
		_overlay_t -= _delta
		if _overlay_t <= 0.0:
			_overlay_t = 0.5
			_update_overlay()


func _record(ms: float) -> void:
	_ring[_ring_i] = ms
	_ring_i = (_ring_i + 1) % RING
	var s: Dictionary = _stats.get(_ctx, {})
	if s.is_empty():
		var h := PackedInt32Array()
		h.resize(HIST_MS + 1)
		s = {"hist": h, "n": 0, "sum": 0.0, "over50": 0, "over100": 0, "worst": 0.0,
			"gpu_n": 0, "gpu_sum": 0.0, "gpu_max": 0.0, "cpu_n": 0, "cpu_sum": 0.0, "cpu_max": 0.0,
			"dc_max": 0, "dc_sum": 0, "prim_max": 0}
		_stats[_ctx] = s
	var hist: PackedInt32Array = s["hist"]
	hist[mini(int(ms), HIST_MS)] += 1
	s["hist"] = hist
	s["n"] += 1
	s["sum"] += ms
	s["worst"] = maxf(s["worst"], ms)
	if ms > 100.0:
		s["over100"] += 1
	if ms > STALL_MS:
		s["over50"] += 1
		var since := Time.get_ticks_msec() - _last_mark_ms
		_stalls.append({"t": Time.get_ticks_msec() - _start_ms, "ms": ms, "ctx": _ctx,
			"mark": _last_mark if since <= int(ATTRIBUTE_S * 1000.0) else "", "since": since})
		if _stalls.size() > MAX_STALLS:
			_stalls.pop_front()
	if _measuring:
		var rid := get_tree().root.get_viewport_rid()
		var g := RenderingServer.viewport_get_measured_render_time_gpu(rid)
		if g > 0.0:
			s["gpu_n"] += 1
			s["gpu_sum"] += g
			s["gpu_max"] = maxf(s["gpu_max"], g)
		var c := RenderingServer.viewport_get_measured_render_time_cpu(rid)
		if c > 0.0:
			s["cpu_n"] += 1
			s["cpu_sum"] += c
			s["cpu_max"] = maxf(s["cpu_max"], c)
	var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	s["dc_max"] = maxi(s["dc_max"], dc)
	s["dc_sum"] += dc
	s["prim_max"] = maxi(s["prim_max"], RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))


## V6: physics catch-up, simulation time, pipeline compilations, timeline and
## growth (all bounded).
func _record_v6(ms: float, delta: float, steps_override: int = -1) -> void:
	var pf := Engine.get_physics_frames()
	var steps := (pf - _phys_frames) if _phys_frames >= 0 else 1
	_phys_frames = pf
	if steps_override >= 0:
		steps = steps_override
	var sim_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var draw_pipes := 0
	var s: Dictionary = _stats.get(_ctx, {})
	if not s.has("steps"):
		var sh := PackedInt32Array()
		sh.resize(8)
		s["steps"] = sh
		s["sim_sum"] = 0.0
		s["sim_max"] = 0.0
		s["pipes"] = PackedInt64Array([0, 0, 0, 0, 0])
		s["spirals"] = 0
		s["spiral_longest"] = 0
	var sh2: PackedInt32Array = s["steps"]
	sh2[mini(steps, 7)] += 1
	s["steps"] = sh2
	s["sim_sum"] = float(s["sim_sum"]) + sim_ms
	s["sim_max"] = maxf(float(s["sim_max"]), sim_ms)
	if DisplayServer.get_name() != "headless":
		var pipes: PackedInt64Array = s["pipes"]
		for i in 5:
			var v := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS + i)
			var d := v - _pipe_prev[i]
			if d > 0:
				pipes[i] += d
				if i == 3:   # draw-time compilation
					draw_pipes = d
			_pipe_prev[i] = v
		s["pipes"] = pipes
	if steps >= 2:
		_catchup_run += 1
		if _catchup_run == SPIRAL_FRAMES:
			s["spirals"] = int(s["spirals"]) + 1
			mark("catchup_spiral")
		s["spiral_longest"] = maxi(int(s["spiral_longest"]), _catchup_run)
	else:
		_catchup_run = 0
	_timeline.append([Time.get_ticks_msec() - _start_ms, ms, steps, sim_ms, draw_pipes])
	if _timeline.size() > TIMELINE:
		_timeline.pop_front()
	if ms > STALL_MS and not _stalls.is_empty():
		# the frames leading up to this stall (interval, ticks, sim, draw pipelines)
		_stalls[_stalls.size() - 1]["before"] = _timeline.slice(maxi(0, _timeline.size() - STALL_CONTEXT - 1), _timeline.size() - 1)
		_stalls[_stalls.size() - 1]["steps"] = steps
		_stalls[_stalls.size() - 1]["sim_ms"] = sim_ms
		_stalls[_stalls.size() - 1]["pipes"] = draw_pipes
	_growth_t -= delta
	if _growth_t <= 0.0:
		_growth_t = GROWTH_EVERY_S
		var g := _counts_now()
		g["t"] = Time.get_ticks_msec() - _start_ms
		_growth.append(g)
		if _growth.size() > 360:
			_growth.remove_at(1)   # keep the first sample as the baseline


func timeline() -> Array:
	return _timeline


## Percentile (0..1) of a 1 ms histogram, in ms.
static func percentile(hist: PackedInt32Array, n: int, p: float) -> float:
	if n <= 0:
		return 0.0
	var want := int(ceil(p * float(n)))
	var acc := 0
	for i in hist.size():
		acc += hist[i]
		if acc >= want:
			return float(i) + 0.5
	return float(hist.size())


## Recent intervals (newest last), for the overlay and tests.
func recent(count: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in count:
		var idx := (_ring_i - count + i + RING * 2) % RING
		out.append(_ring[idx])
	return out


func stats(ctx: String) -> Dictionary:
	return _stats.get(ctx, {})


func stalls() -> Array:
	return _stalls


func marker_count(name: String) -> int:
	return int(_counts.get(name, 0))


# ---------------------------------------------------------------------------
# Device state through the UTShare extension (iOS); -1 = unavailable
# ---------------------------------------------------------------------------
static func thermal_state() -> int:
	if ClassDB.class_exists("UTShare") and ClassDB.class_has_method("UTShare", "thermal_state"):
		return int(ClassDB.class_call_static("UTShare", "thermal_state"))
	return -1


static func low_power() -> int:
	if ClassDB.class_exists("UTShare") and ClassDB.class_has_method("UTShare", "low_power_mode"):
		return int(ClassDB.class_call_static("UTShare", "low_power_mode"))
	return -1


static func _thermal_name(v: int) -> String:
	return ["nominal", "fair", "serious", "critical"][v] if v >= 0 and v <= 3 else "unavailable"


# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
func summary() -> String:
	var L: PackedStringArray = []
	L.append("Ultimate Trifecta beta diagnostics")
	L.append("(no player names, room codes or Game Center IDs are included)")
	var ver := String(ProjectSettings.get_setting("application/config/version", "?"))
	var eng := Engine.get_version_info()
	L.append("App %s · Godot %s.%s.%s · %s %s · %s" % [ver, eng["major"], eng["minor"], eng["patch"], OS.get_name(), OS.get_version(), OS.get_model_name()])
	if DisplayServer.get_name() != "headless":
		L.append("GPU %s · %s · %s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version(), RenderingServer.get_current_rendering_driver_name()])
	var root := get_tree().root
	var win := DisplayServer.window_get_size() if DisplayServer.get_name() != "headless" else Vector2i.ZERO
	L.append("Preset %s · frame cap %s · window %dx%d · 3D scale %.2f · MSAA %s" % [
		QualityPreset.label(int(Save.get_setting("quality", 1))),
		("%d fps" % Engine.max_fps) if Engine.max_fps > 0 else "none (display sync)",
		win.x, win.y, root.scaling_3d_scale, ["off", "2x", "4x", "8x"][int(root.msaa_3d)]])
	var mins := (Time.get_ticks_msec() - _start_ms) / 60000.0
	L.append("Collected for %.1f min · thermal now %s, worst %s · Low Power Mode %s" % [mins, _thermal_name(_thermal_now),
		_thermal_name(_thermal_worst), {1: "on", 0: "off"}.get(low_power(), "unavailable")])
	L.append("")
	L.append("Frame interval (engine loop, measured on the CPU; target 16.7 ms at 60, 33.3 ms at 30)")
	L.append("context   frames   p50     p95     p99     >50ms  >100ms  worst")
	for ctx in ["menu", "lobby", "loading", "match", "results"]:
		var s: Dictionary = _stats.get(ctx, {})
		if s.is_empty() or int(s["n"]) == 0:
			continue
		var h: PackedInt32Array = s["hist"]
		var n := int(s["n"])
		L.append("%-9s %6d  %5.1f   %5.1f   %5.1f   %5d  %6d  %6.0f" % [ctx, n, percentile(h, n, 0.5), percentile(h, n, 0.95),
			percentile(h, n, 0.99), int(s["over50"]), int(s["over100"]), float(s["worst"])])
	L.append("")
	L.append("Renderer measurements per context (main viewport)")
	for ctx in ["menu", "lobby", "loading", "match", "results"]:
		var s: Dictionary = _stats.get(ctx, {})
		if s.is_empty() or int(s["n"]) == 0:
			continue
		var gpu := "unavailable" if int(s["gpu_n"]) == 0 else "avg %.1f ms, max %.1f ms" % [float(s["gpu_sum"]) / int(s["gpu_n"]), float(s["gpu_max"])]
		var cpu := "unavailable" if int(s["cpu_n"]) == 0 else "avg %.1f ms, max %.1f ms" % [float(s["cpu_sum"]) / int(s["cpu_n"]), float(s["cpu_max"])]
		L.append("%-9s GPU %s · CPU render %s · draw calls avg %d max %d · primitives max %d" % [ctx, gpu, cpu,
			int(s["dc_sum"]) / maxi(1, int(s["n"])), int(s["dc_max"]), int(s["prim_max"])])
	L.append("")
	L.append("Simulation (V6): 60 Hz ticks per frame and their script time")
	L.append("context   1 tick  2 ticks  3+ ticks  sim avg  sim max  catch-up spirals (longest run)")
	for ctx in ["menu", "lobby", "loading", "match", "results"]:
		var s: Dictionary = _stats.get(ctx, {})
		if s.is_empty() or not s.has("steps") or int(s["n"]) == 0:
			continue
		var sh: PackedInt32Array = s["steps"]
		var three := 0
		for i in range(3, sh.size()):
			three += sh[i]
		L.append("%-9s %6d  %7d  %8d  %5.1f ms %5.1f ms  %d (%d frames)" % [ctx, sh[1], sh[2], three, float(s["sim_sum"]) / int(s["n"]),
			float(s["sim_max"]), int(s["spirals"]), int(s["spiral_longest"])])
	L.append("Pipelines compiled (V6; draw-time ones can stall a frame)")
	for ctx in ["menu", "lobby", "loading", "match", "results"]:
		var s: Dictionary = _stats.get(ctx, {})
		if s.is_empty() or not s.has("pipes"):
			continue
		var pp: PackedInt64Array = s["pipes"]
		L.append("%-9s canvas %d · mesh %d · surface %d · draw %d · specialization %d" % [ctx, pp[0], pp[1], pp[2], pp[3], pp[4]])
	if _growth.size() >= 2:
		var g0: Dictionary = _growth[0]
		var g1: Dictionary = _growth[_growth.size() - 1]
		L.append("Growth since the first sample: nodes %+d · objects %+d · orphans %+d · static memory %+.1f MB" % [
			int(g1["nodes"]) - int(g0["nodes"]), int(g1["objects"]) - int(g0["objects"]), int(g1["orphans"]) - int(g0["orphans"]),
			float(g1["static_mb"]) - float(g0["static_mb"])])
	if not _round_starts.is_empty():
		# the first round also fills one-time caches: later rounds are the
		# comparison that shows a leak
		var parts: PackedStringArray = []
		for r in _round_starts:
			parts.append("%d/%d/%d/%.0f" % [r["nodes"], r["objects"], r["orphans"], r["static_mb"]])
		L.append("At each round start (nodes/objects/orphans/static MB): " + " → ".join(parts))
	L.append("")
	L.append("Memory: static %.0f MB · video %.0f MB" % [Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
	if int(_net["rtt_n"]) > 0 or int(_net["corr_n"]) > 0:
		L.append("Network: round trip avg %.0f ms, max %.0f ms · corrections avg %.3f m, max %.2f m, over 25 cm %d" % [
			float(_net["rtt_sum"]) / maxi(1, int(_net["rtt_n"])), float(_net["rtt_max"]),
			float(_net["corr_sum"]) / maxi(1, int(_net["corr_n"])), float(_net["corr_max"]), int(_net["big"])])
	if not _stick_g.is_empty() or not _stick_cur.is_empty():
		L.append("")
		L.append("Move stick, last gestures (forward-held part): secs · ring offset px · sideways/forward out · largest lean deg · camera turn deg (of which follow, look) · base moves · travel sideways/forward")
		for g in _stick_g + ([_stick_cur] if not _stick_cur.is_empty() else []):
			var n := maxi(1, int(g["n"]))
			var turn := rad_to_deg(angle_difference(float(g["yaw0"]), float(g.get("yaw1", g["yaw0"]))))
			L.append("  %s  %4.1f s  %3.0f  %.3f  %4.1f  %+6.1f (%+.1f, %.1f)  %d  %.3f" % [_clock(int(g["t0"])), float(g["dur"]), float(g["ring"]),
				float(g["fx"]) / maxf(float(g["fy"]), 1e-3), float(g["lean"]), turn, rad_to_deg(float(g["follow"])),
				rad_to_deg(float(g["look"])), int(g["follows"]), float(g["tlat"]) / maxf(float(g["tfwd"]), 1e-3)])
		if not _stick_s.is_empty():
			L.append("Newest gesture at 10 Hz: t · raw x,y · out x,y · camera yaw · look deg · follow deg/s · travel off camera deg · speed")
			for r in _stick_s:
				L.append("  %4.1f  %+.2f,%+.2f  %+.2f,%+.2f  %+7.1f  %+5.1f  %+5.1f  %+6.1f  %4.1f" % r)
	L.append("")
	L.append("Stalls over %d ms (newest last; attributed to a marker in the %.0f s before)" % [int(STALL_MS), ATTRIBUTE_S])
	for st in _stalls.slice(maxi(0, _stalls.size() - 25)):
		var at := _clock(int(st["t"]))
		var why := ("after \"%s\" (+%.1f s)" % [st["mark"], int(st["since"]) / 1000.0]) if String(st["mark"]) != "" else "no marker"
		var extra := ""
		if st.has("steps"):
			extra = " · %d ticks, sim %.1f ms, draw pipelines %d" % [int(st["steps"]), float(st["sim_ms"]), int(st["pipes"])]
		L.append("  %s  %4.0f ms  %-8s %s%s" % [at, float(st["ms"]), st["ctx"], why, extra])
	if _stalls.is_empty():
		L.append("  none")
	L.append("")
	var mk: PackedStringArray = []
	for k in _counts:
		mk.append("%s ×%d" % [k, int(_counts[k])])
	L.append("Markers: " + (", ".join(mk) if not mk.is_empty() else "none"))
	return "\n".join(L)


static func _clock(ms: int) -> String:
	var s := ms / 1000
	return "%02d:%02d" % [s / 60, s % 60]


# ---------------------------------------------------------------------------
# Optional on-screen readout (Settings › Diagnostics › Show readout)
# ---------------------------------------------------------------------------
func _apply_overlay() -> void:
	if overlay and _overlay_layer == null:
		_overlay_layer = CanvasLayer.new()
		_overlay_layer.layer = 120
		add_child(_overlay_layer)
		_overlay_lbl = Label.new()
		_overlay_lbl.position = Vector2(8, 4)
		_overlay_lbl.add_theme_font_size_override("font_size", 14)
		_overlay_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
		_overlay_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		_overlay_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_overlay_layer.add_child(_overlay_lbl)
	elif not overlay and _overlay_layer != null:
		_overlay_layer.queue_free()
		_overlay_layer = null
		_overlay_lbl = null


func _update_overlay() -> void:
	if _overlay_lbl == null:
		return
	var r := recent(60)
	var worst := 0.0
	var sum := 0.0
	for x in r:
		worst = maxf(worst, x)
		sum += x
	var s: Dictionary = _stats.get(_ctx, {})
	var gpu := ""
	if _measuring and int(s.get("gpu_n", 0)) > 0:
		gpu = " · GPU %.1f" % RenderingServer.viewport_get_measured_render_time_gpu(get_tree().root.get_viewport_rid())
	_overlay_lbl.text = "%s · %.1f ms avg · worst %.0f%s · stalls %d" % [_ctx, sum / 60.0, worst, gpu, int(s.get("over50", 0))]
