extends CanvasLayer
## Development-only render diagnostics (never shown to players: created only
## from the --diag / --diag-report command-line flags, and src/dev/ is excluded
## from iOS exports).
##
## Measures what actually reaches the screen: window pixels vs. logical canvas,
## the root viewport's 3D render size/scale/AA, every SubViewport's render size
## vs. the size it is displayed at, frame-time distribution and engine counters.

var overlay: Label
var show_overlay := false
var report_path := ""
var _frames: PackedFloat32Array = PackedFloat32Array()
var _t := 0.0
var _next_dump := 2.0


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	if show_overlay:
		overlay = Label.new()
		overlay.position = Vector2(8, 8)
		overlay.add_theme_font_size_override("font_size", 14)
		overlay.add_theme_color_override("font_color", Color(0.9, 1.0, 0.9))
		overlay.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		overlay.add_theme_constant_override("outline_size", 4)
		add_child(overlay)


func _process(delta: float) -> void:
	_t += delta
	_frames.append(delta)
	if _frames.size() > 20000:
		_frames = _frames.slice(10000)
	if overlay and Engine.get_process_frames() % 15 == 0:
		overlay.text = text_summary(snapshot())
	if report_path != "" and _t >= _next_dump:
		_next_dump += 5.0
		write_report()


static func _vp_pixel_scale(c: CanvasItem) -> Vector2:
	# canvas units -> window pixels for a control in the root viewport
	return c.get_viewport().get_final_transform().get_scale() * c.get_global_transform_with_canvas().get_scale()


func snapshot() -> Dictionary:
	var root := get_tree().root
	var win := DisplayServer.window_get_size()
	var d := {
		"window_px": [win.x, win.y],
		"screen_px": [DisplayServer.screen_get_size().x, DisplayServer.screen_get_size().y],
		"screen_dpi": DisplayServer.screen_get_dpi(),
		"screen_scale": DisplayServer.screen_get_scale(),
		"canvas_units": [snappedf(root.get_visible_rect().size.x, 0.1), snappedf(root.get_visible_rect().size.y, 0.1)],
		"canvas_to_px": snappedf(root.get_final_transform().get_scale().x, 0.001),
		"root_render_px": [root.size.x, root.size.y],
		"scaling_3d_mode": root.scaling_3d_mode,
		"scaling_3d_scale": root.scaling_3d_scale,
		"msaa_3d": root.msaa_3d,
		"screen_space_aa": root.screen_space_aa,
		"use_taa": root.use_taa,
		"renderer": "%s / %s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name()],
		"adapter": RenderingServer.get_video_adapter_name(),
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"video_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"static_mem_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"subviewports": [],
	}
	for sv: SubViewport in _all_subviewports(root):
		var info := {"path": str(root.get_path_to(sv)), "render_px": [sv.size.x, sv.size.y], "msaa_3d": sv.msaa_3d,
			"scaling_3d_scale": sv.scaling_3d_scale}
		var parent: Node = sv.get_parent()
		if parent is Control:
			# SubViewportContainer (stretched) or a Control drawing the texture (Preview3D)
			var cont := parent as Control
			var px := cont.get_global_rect().size * _vp_pixel_scale(cont)
			info["display_control"] = cont.get_class()
			info["container_canvas"] = [snappedf(cont.size.x, 0.1), snappedf(cont.size.y, 0.1)]
			info["displayed_px"] = [snappedf(px.x, 0.1), snappedf(px.y, 0.1)]
			info["stretch"] = (cont as SubViewportContainer).stretch if cont is SubViewportContainer else false
			info["render_to_display"] = snappedf(float(sv.size.x) / maxf(1.0, px.x), 0.001)
		(d["subviewports"] as Array).append(info)
	d["frame_ms"] = frame_stats()
	return d


func _all_subviewports(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is SubViewport:
			out.append(c)
		out.append_array(_all_subviewports(c))
	return out


func frame_stats() -> Dictionary:
	if _frames.size() < 10:
		return {}
	var a := Array(_frames)
	a.sort()
	var n := a.size()
	var target := 1.0 / maxf(1.0, float(Engine.max_fps if Engine.max_fps > 0 else 60))
	var missed := 0
	var hitches := 0
	for f in a:
		if f > target * 1.5:
			missed += 1
		if f > 0.1:
			hitches += 1
	return {"n": n, "p50": snappedf(a[n / 2] * 1000.0, 0.01), "p95": snappedf(a[int(n * 0.95)] * 1000.0, 0.01),
		"p99": snappedf(a[int(n * 0.99)] * 1000.0, 0.01), "max": snappedf(a[n - 1] * 1000.0, 0.01),
		"over_1_5x_target": missed, "over_100ms": hitches}


static func text_summary(d: Dictionary) -> String:
	var s := "window %s px  canvas %s u  x%.3f\n" % [str(d["window_px"]), str(d["canvas_units"]), float(d["canvas_to_px"])]
	s += "3D %s px  scale %.2f mode %d  msaa %d  %s\n" % [str(d["root_render_px"]), float(d["scaling_3d_scale"]), int(d["scaling_3d_mode"]), int(d["msaa_3d"]), str(d["renderer"])]
	s += "fps %.0f  draws %d  prims %d  objs %d  vram %.0f MB\n" % [float(d["fps"]), int(d["draw_calls"]), int(d["primitives"]), int(d["objects"]), float(d["video_mem_mb"])]
	for sv in d["subviewports"]:
		s += "sub %s render %s shown %s (%.2f) msaa %d\n" % [String(sv["path"]).get_file(), str(sv["render_px"]), str(sv.get("displayed_px", "-")), float(sv.get("render_to_display", 0.0)), int(sv["msaa_3d"])]
	var fs: Dictionary = d.get("frame_ms", {})
	if not fs.is_empty():
		s += "frame ms p50 %.1f p95 %.1f p99 %.1f max %.1f" % [float(fs["p50"]), float(fs["p95"]), float(fs["p99"]), float(fs["max"])]
	return s


func write_report() -> void:
	if report_path == "":
		return
	var f := FileAccess.open(report_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(snapshot(), "  "))
