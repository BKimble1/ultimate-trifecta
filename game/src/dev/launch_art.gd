extends Control
## Development-only (src/dev is excluded from exports).
##   --loading=T,T2,...  saves the real match loading screen at those loop
##                       times (seconds into the runner loop) for evidence
##   (no flag)           saves the first runtime frame of the startup curtain
##                       (BootCurtain), to compare with assets/icon/launch.png
## The launch image itself is built by tools/branding/make_branding.py.

var out_path := "user://launch_frame.png"
var _frames := 0
var loading_times: Array = []
var _ls: LoadingScreen
var _wait := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_path = a.split("=")[1]
		elif a.begins_with("--loading="):
			for x in a.get_slice("=", 1).split(","):
				loading_times.append(float(x))
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if not loading_times.is_empty():
		_ls = LoadingScreen.new()
		_ls.info = {"settings": {"watch": 2}}
		add_child(_ls)
	else:
		add_child(BootCurtain.new())


func _process(_d: float) -> void:
	_frames += 1
	if _ls != null:
		_loading_frames()
		return
	if _frames == 4:
		var img := get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		var err := img.save_png(ProjectSettings.globalize_path(out_path) if out_path.begins_with("res://") else out_path)
		print("first frame %dx%d -> %s (%s)" % [img.get_width(), img.get_height(), out_path, error_string(err)])
		get_tree().quit(0 if err == OK else 1)


func _loading_frames() -> void:
	# wait for the loop atlas (background load), then one time per 3 frames
	if not _ls.loop_running() and _wait < 600:
		_wait += 1
		_frames = 0
		if _wait == 600:
			print("loading loop never started; capturing the still")
		return
	var idx := (_frames - 1) / 3
	if idx >= loading_times.size():
		get_tree().quit()
		return
	var phase := (_frames - 1) % 3
	if phase == 0:
		# the loop advances by about one frame time before the capture
		_ls.set_loop_time(maxf(0.0, float(loading_times[idx]) - 1.0 / 60.0))
	elif phase == 2:
		var img := get_viewport().get_texture().get_image()
		var path := out_path.get_basename() + "_%.2f.png" % float(loading_times[idx])
		img.save_png(path)
		print("loading frame t~%.2f s -> %s" % [loading_times[idx], path])
