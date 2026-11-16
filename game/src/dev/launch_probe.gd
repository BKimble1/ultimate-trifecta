extends Node
## Development probe (--launch-probe=DIR): the first seconds after launch as
## a returning player sees them (onboarded, the champion poster due).  Every
## rendered frame is saved small (fNNN_tS.SS_<screen>.jpg) and the screen
## changes are printed, to find any flash, jump or glitch between the boot
## curtain, home and the poster.

var out_dir := ""
var secs := 14.0
var _t := 0.0
var _i := 0
var _last := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(out_dir)
	Save.data["onboarded"] = true
	Save.set_setting("promo_seen_at", 0)


func _process(delta: float) -> void:
	_t += delta
	var scr: String = String((App.screen.get_script() as Script).get_global_name()) if App.screen != null and App.screen.get_script() != null else "none"
	if scr != _last:
		print("LAUNCH_PROBE t=%.2f screen=%s" % [_t, scr])
		_last = scr
	if _t > secs:
		get_tree().quit()
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		return
	img.resize(img.get_width() / 3, img.get_height() / 3)
	img.save_jpg(out_dir.path_join("f%03d_t%.2f_%s.jpg" % [_i, _t, scr]), 0.75)
	_i += 1
