extends Node
## Dev only (not exported): drives a normal cold launch through the season
## premiere with real input events, for recordings and evidence.
##   --premiere-drive=<plan>[,<plan>...]   natural | skip | early | tap |
##                                         background | key_skip | setup |
##                                         keyboard | quit_after_film
##   --premiere-log=<file>                 a line per event (times, screens,
##                                         music, film position)
##   --premiere-shots=<dir>                PNGs at the moments that matter
## Times are measured from the film starting (premiere_play).

var plan: PackedStringArray = []
var log_path := ""
var shots_dir := ""
var _t := 0.0
var _film_t := -1.0
var _end_t := -1.0
var _done := {}
var _lines: PackedStringArray = []
var _last_screen := ""
var _frame := 0
var _shot_i := 0
var p_last_hint := Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100
	if shots_dir != "":
		DirAccess.make_dir_recursive_absolute(shots_dir)
	_log("drive start plan=%s due=%s seen=%s onboarded=%s" % [",".join(plan), SeasonPremiere.due(), Save.data.get("season_film_seen"), Save.data.get("onboarded")])


func _log(s: String) -> void:
	var line := "[%7.3f f%05d] %s" % [_t, _frame, s]
	print("PREMIERE ", line)
	_lines.append(line)
	if log_path != "":
		var f := FileAccess.open(log_path, FileAccess.WRITE)
		if f:
			f.store_string("\n".join(_lines) + "\n")


func _shot(tag: String) -> void:
	if shots_dir == "":
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png(shots_dir.path_join("%02d_%s.png" % [_shot_i, tag]))
	_shot_i += 1


func _once(key: String) -> bool:
	if _done.has(key):
		return false
	_done[key] = true
	return true


func _touch(pos: Vector2, pressed: bool, idx: int = 0) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = get_tree().root.get_final_transform() * pos   # canvas units -> window
	e.pressed = pressed
	Input.parse_input_event(e)


func _key(_action: String, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_SPACE
	e.physical_keycode = KEY_SPACE
	e.pressed = pressed
	Input.parse_input_event(e)


func _center(c: Control) -> Vector2:
	return c.get_global_rect().get_center() if is_instance_valid(c) else Vector2(-1, -1)


func _process(delta: float) -> void:
	_t += delta
	_frame += 1
	var p := SeasonPremiere.current
	var sc := App.screen.get_class() if App.screen else ""
	if App.screen and App.screen.get_script():
		sc = String((App.screen.get_script() as Script).get_global_name())
	if sc != _last_screen:
		_log("screen -> %s (music=%s)" % [sc, Sfx.current_music()])
		_last_screen = sc
	if _film_t < 0.0 and BootCurtain.live == 0 and _once("curtain_gone"):
		_log("curtain gone: screen=%s premiere=%s music=%s" % [sc, p != null, Sfx.current_music()])
		if p == null:
			_film_t = _t   # no film: the quit timer still runs
	if p and _film_t < 0.0 and p.state == SeasonPremiere.State.PLAYING:
		_film_t = _t
		_log("film playing (curtains=%d)" % BootCurtain.live)
		_shot("film_start")
		if "late" in plan:
			p.video.stream_position = 29.0   # dev: straight to the title card
	if p and p.state == SeasonPremiere.State.ENDING and _once("ending"):
		_end_t = _t
		_log("film ending how=%s pos=%.3f music=%s seen=%s" % [p.how, p.video.stream_position if is_instance_valid(p.video) else -1.0, Sfx.current_music(), Save.data.get("season_film_seen")])
	if _film_t >= 0.0 and p == null and _once("ended"):
		_log("film gone; screen=%s music=%s stage=%s cam_t=%.2f region=%s" % [sc, Sfx.current_music(), App.stage.mode, App.stage._cam_t, App.stage.wardrobe_region])
	if _film_t >= 0.0 and p == null and _t - _end_t > 1.0 and _once("ended_1s"):
		_log("1 s later: stage=%s cam_t=%.2f region=%s" % [App.stage.mode, App.stage._cam_t, App.stage.wardrobe_region])
	var ft := _t - _film_t if _film_t >= 0.0 else -1.0
	if p and ft >= 0.0:
		if ft > 1.0 and _once("shot_1s"):
			_shot("film_1s")
		if p.hint.shown and _once("hint"):
			_log("hint shown at film %.2f s" % ft)
	for step in plan:
		match step:
			"tap":
				if p and ft >= 2.4 and _once("tap_down"):
					_log("tap on the hint")
					_touch(p.hint.target().get_center(), true, 0)
				if p and ft >= 2.5 and _once("tap_up"):
					_touch(p.hint.target().get_center(), false, 0)
					_log("tap released: state=%s" % p.state)
			"early":
				if p and ft >= 3.0 and _once("early_down"):
					_log("early hold")
					_touch(p.hint.target().get_center(), true, 0)
				if p and ft >= 3.4 and _once("early_up"):
					_touch(p.hint.target().get_center(), false, 0)
					_log("early release: hold=%.2f state=%s" % [p.hold, p.state])
			"background":
				if p and ft >= 4.0 and _once("bg_hold"):
					_touch(p.hint.target().get_center(), true, 1)
				if p and ft >= 4.3 and _once("bg_out"):
					_log("background (pos=%.3f hold=%.2f)" % [p.video.stream_position, p.hold])
					get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
					get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_PAUSED)
				if p and ft >= 6.3 and _once("bg_in"):
					_log("resume (pos=%.3f hold=%.2f paused=%s)" % [p.video.stream_position, p.hold, p.video.paused])
					get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_RESUMED)
					get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
					_touch(p.hint.target().get_center(), false, 1)
				if p and ft >= 7.0 and _once("bg_check"):
					_log("after resume pos=%.3f paused=%s players=%d" % [p.video.stream_position, p.video.paused, p.find_children("*", "VideoStreamPlayer", true, false).size()])
			"skip":
				if p and ft >= 6.0 and _once("skip_down"):
					_log("hold to skip")
					_shot("hold_start")
					p_last_hint = p.hint.target().get_center()
					_touch(p_last_hint, true, 0)
				if p and ft >= 6.5 and _once("skip_mid"):
					_shot("hold_half")
				if ft >= 7.4 and _once("skip_up"):
					# released well after the skip: the swallow eats it
					_touch(p_last_hint, false, 0)
					_log("released after skip; screen=%s swallow=%s" % [sc, get_tree().root.has_node("PremiereSwallow")])
			"key_skip":
				if p and ft >= 5.0 and _once("key_down"):
					_log("hold Space")
					_key("jump", true)
				if ft >= 6.2 and _once("key_up"):
					_key("jump", false)
					_log("Space released; screen=%s" % sc)
		if step == "setup" and _end_t >= 0.0 and p == null:
			var c := App.screen as CreatorScreen
			if c and c.first_run:
				var since := _t - _end_t
				if since > 0.05 and _once("reveal_0"):
					_shot("reveal_runner")
				if since > 1.4 and _once("reveal_1"):
					_shot("setup_look")
					_log("setup visible: panel alpha=%.2f" % c.setup_panel.modulate.a)
				if since > 2.2 and _once("pick_swim"):
					for card in c.cards:
						if card.field == "outfit" and card.key == "swim":
							_touch(_center(card), true)
							_touch(_center(card), false)
				if since > 2.8 and _once("group_colors"):
					_touch(_center(c._seg_btns["colors"]), true)
					_touch(_center(c._seg_btns["colors"]), false)
				if since > 3.2 and _once("pick_colour"):
					for sw in c.swatches:
						if sw.field == "color" and sw.key == "grape":
							_touch(_center(sw), true)
							_touch(_center(sw), false)
				if since > 3.6 and _once("shot_colors"):
					_shot("setup_colors")
					_touch(_center(c._seg_btns["hair"]), true)
					_touch(_center(c._seg_btns["hair"]), false)
				if since > 4.0 and _once("shot_look2"):
					_shot("setup_appearance")
				if since > 4.6 and _once("continue"):
					_log("Continue")
					_touch(_center(c.continue_btn), true)
					_touch(_center(c.continue_btn), false)
				if since > 5.6 and _once("shot_name"):
					_shot("setup_name")
				if "keyboard" in plan and since > 6.0 and _once("kb"):
					c.name_form.field.grab_focus()
				if "keyboard" in plan and since > 6.6 and _once("kb_shot"):
					_shot("setup_name_keyboard")
					c.name_form.field.release_focus()
				if since > 7.2 and _once("back"):
					_log("Back (draft outfit=%s)" % c.draft["outfit"])
					_touch(_center(c.name_form.cancel_btn), true)
					_touch(_center(c.name_form.cancel_btn), false)
				if since > 7.8 and _once("back_check"):
					_log("after Back: step=%s outfit=%s onboarded=%s" % [c.setup_step, c.draft["outfit"], Save.data.get("onboarded")])
					_touch(_center(c.continue_btn), true)
					_touch(_center(c.continue_btn), false)
				if since > 8.8 and _once("enter"):
					_log("Enter the dorm (name=%s)" % c.name_form.field.text)
					_touch(_center(c.name_form.save_btn), true)
					_touch(_center(c.name_form.save_btn), false)
			elif App.screen is LobbyScreen and _once("lobby_after_setup"):
				_log("lobby after setup: onboarded=%s cosmetic.outfit=%s name=%s" % [Save.data.get("onboarded"), Save.data["cosmetic"]["outfit"], Save.data.get("name")])
				_end_t = _t
		if step == "quit_after_film" and _film_t >= 0.0 and p == null and _once("quit_after_film_t"):
			get_tree().create_timer(3.0).timeout.connect(func() -> void:
				_shot("final")
				_log("quit: screen=%s music=%s modal=%s" % [String((App.screen.get_script() as Script).get_global_name()) if App.screen else "", Sfx.current_music(), (App.screen as Screen).has_modal() if App.screen is Screen else false])
				get_tree().quit())
		if step == "quit_mid_film" and p and ft >= 5.0 and _once("quit_mid"):
			_log("quit mid-film: seen=%s" % [Save.data.get("season_film_seen")])
			get_tree().quit()
	if "setup" in plan and App.screen is LobbyScreen and _done.has("enter") and _t - _end_t > 3.0 and _once("final_quit"):
		_shot("lobby")
		_log("quit in lobby: music=%s" % Sfx.current_music())
		get_tree().quit()
