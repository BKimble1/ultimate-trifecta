extends Node
## Development probe (--launch-probe=DIR): the first seconds after launch as
## a returning player sees them (onboarded, the champion poster due).  Every
## rendered frame is saved small (fNNN_tS.SS_<screen>.jpg) and the screen
## changes are printed, to find any flash, jump or glitch between the boot
## curtain, home and the poster.

var out_dir := ""
var secs := 18.0
## --launch-probe-leave: open a LAN party at 4 s, leave it at 7 s
var leave_test := false
var _step := 0
var _t := 0.0
var _i := 0
var _last := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(out_dir)
	Save.data["onboarded"] = true
	Save.set_setting("promo_seen_at", Rankings.now() if OS.get_cmdline_user_args().has("--launch-probe-nopromo") else 0)


func _process(delta: float) -> void:
	_t += delta
	var scr: String = String((App.screen.get_script() as Script).get_global_name()) if App.screen != null and App.screen.get_script() != null else "none"
	if scr != _last:
		print("LAUNCH_PROBE t=%.2f screen=%s" % [_t, scr])
		_last = scr
	if _t > secs:
		get_tree().quit()
		return
	if leave_test and _step == 0 and _t > 4.0:
		_step = 1
		print("LAUNCH_PROBE t=%.2f host LAN party" % _t)
		App.host_room_enet(7795)
	elif leave_test and _step == 1 and _t > 7.0:
		_step = 2
		print("LAUNCH_PROBE t=%.2f leave party" % _t)
		App.leave_room()
	elif leave_test and _step == 2 and _t > 9.0:
		_step = 3
		print("LAUNCH_PROBE t=%.2f to the Shop" % _t)
		NavShell.go("shop")
	elif leave_test and _step == 3 and _t > 11.5:
		_step = 4
		print("LAUNCH_PROBE t=%.2f to the Season Pass" % _t)
		NavShell.go("pass")
	elif leave_test and _step == 4 and _t > 13.0 and App.screen is SeasonScreen:
		_step = 5
		print("LAUNCH_PROBE t=%.2f Record Breaker (tier 50 premium)" % _t)
		(App.screen as SeasonScreen)._on_cell(50, "premium")
	elif leave_test and _step == 5 and _t > 15.0 and App.screen is SeasonScreen:
		_step = 6
		print("LAUNCH_PROBE t=%.2f the hat (tier 3)" % _t)
		(App.screen as SeasonScreen)._on_cell(3, "free")
	if App.stage != null and is_instance_valid(App.stage) and int(_t * 10.0) % 5 == 0:
		var n := 0
		for k in App.stage.chars:
			var v: Node3D = App.stage.chars[k]
			if is_instance_valid(v) and v.visible:
				n += 1
		var all3d := App.stage.find_children("*", "CharacterView", true, false).size()
		print("LAUNCH_PROBE t=%.2f chars_visible=%d character_views=%d mode=%s" % [_t, n, all3d, App.stage.mode])
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		return
	img.resize(img.get_width() / 3, img.get_height() / 3)
	img.save_jpg(out_dir.path_join("f%03d_t%.2f_%s.jpg" % [_i, _t, scr]), 0.75)
	_i += 1
