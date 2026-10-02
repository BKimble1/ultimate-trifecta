extends Control
## Development-only (src/dev is excluded from exports): renders the static
## launch image from the loading screen's own drawing code, so the iOS launch
## screen, the boot splash and the loading screen's resting frame match.
##   tools/make_launch_art.sh  (writes assets/icon/launch.png, 1440x1440)
## The image is square and drawn for a 720-unit-high screen at k = 2; shown
## "scale to fit" on a landscape phone it fills the height, so the motif and
## wordmark land where the loading screen draws them.

var out_path := "res://assets/icon/launch.png"
var _frames := 0
## --loading=T,T2,...: instead, save the real loading screen at those motif
## times (seconds into the loop) for evidence frames.
var loading_times: Array = []
var _ls: LoadingScreen


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


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), LoadingScreen.BG)
	var h := size.y
	var k := h / 720.0
	var c := Vector2(size.x * 0.5, h * LoadingScreen.MOTIF_Y)
	LoadingScreen.LoadingMotif.draw_resting(self, c, k, 1.0)
	LoadingScreen.LoadingMotif.draw_wordmark(self, Vector2(size.x * 0.5, h * LoadingScreen.WORDMARK_Y), k)


func _process(_d: float) -> void:
	_frames += 1
	if _ls != null:
		_loading_frames()
		return
	if _frames == 4:
		var img := get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		var err := img.save_png(ProjectSettings.globalize_path(out_path) if out_path.begins_with("res://") else out_path)
		print("launch art %dx%d -> %s (%s)" % [img.get_width(), img.get_height(), out_path, error_string(err)])
		get_tree().quit(0 if err == OK else 1)


func _loading_frames() -> void:
	var idx := (_frames - 1) / 3
	if idx >= loading_times.size():
		get_tree().quit()
		return
	var phase := (_frames - 1) % 3
	if phase == 0:
		# the motif advances by its frame time before the capture (~2 frames)
		_ls.motif._t = maxf(0.0, float(loading_times[idx]) - 2.0 / 60.0)
	elif phase == 2:
		var img := get_viewport().get_texture().get_image()
		var path := out_path.get_basename() + "_%.2f.png" % float(loading_times[idx])
		img.save_png(path)
		print("loading frame t~%.2f s -> %s" % [loading_times[idx], path])
