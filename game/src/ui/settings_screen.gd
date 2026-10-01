class_name SettingsScreen
extends Screen
## Settings, grouped: Controls (a small touch set), Camera & comfort,
## Graphics, Sound, Privacy & credits.  Everything saves immediately.

var _rows: Dictionary = {}


func build() -> void:
	if App.stage:
		App.stage.set_mode("home")
	header("Settings")
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	content.add_child(sc)
	var body := UIKit.panel(Color(UIKit.SLATE, 0.95), UIKit.R_PANEL, 26)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(body)
	var v := UIKit.vbox(14)
	body.add_child(v)

	_section(v, "Controls")
	var first := _slider(v, "Camera sensitivity", "sensitivity", 0.3, 2.5, 0.05)
	_choice(v, "Movement stick", "stick_mode", [["dynamic", "Appears where you touch"], ["fixed", "Fixed position"]])
	_choice(v, "Sprint", "sprint_mode", [["edge", "Push the stick to the edge"], ["hold", "Hold a Sprint button"]])
	_choice(v, "Button size", "button_size", [[0.85, "Small"], [1.0, "Medium"], [1.2, "Large"]])
	_choice(v, "Layout", "touch_layout", [["standard", "Stick left, buttons right"], ["mirrored", "Stick right, buttons left"]])
	_check(v, "Vibration (haptics)", "haptics", true)
	var prow := UIKit.hbox(12)
	var try_b := UIKit.secondary("Try in Practice", Vector2(260, 72), 22)
	try_b.pressed.connect(func() -> void: App.start_practice("runner", false))
	prow.add_child(try_b)
	var reset := UIKit.quiet("Reset controls", Vector2(240, 72), 22)
	reset.pressed.connect(func() -> void:
		var d: Dictionary = Save.default_profile()["settings"]
		for k in ["sensitivity", "invert_y", "reduced_motion", "sprint_threshold", "touch_sprint", "stick_mode", "sprint_mode", "button_size", "touch_layout", "haptics"]:
			Save.set_setting(k, d[k])
		App.goto(SettingsScreen))
	prow.add_child(reset)
	v.add_child(prow)
	var ctl := UIKit.label("Controller: " + (Controls.controller_name if Controls.has_controller() else "none connected (touch controls active)"), 19, UIKit.IVORY_MUTED)
	v.add_child(ctl)
	Controls.controller_connection_changed.connect(_on_controller.bind(ctl))

	_section(v, "Camera & comfort")
	_check(v, "Invert camera up/down", "invert_y", false)
	_check(v, "Reduced motion (calmer camera, no look-ahead, fades instead of slides)", "reduced_motion", false)

	_section(v, "Graphics")
	_choice(v, "Quality", "quality", [[1, "Standard (60 fps target)"], [0, "Battery Saver"]])
	var qn := UIKit.label("Battery Saver renders the world at a lower internal resolution with simpler shadows and effects, and caps the frame rate at 30. Text and buttons stay sharp in both.", 18, UIKit.IVORY_MUTED)
	qn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(qn)

	_section(v, "Sound")
	_slider(v, "Sound effects", "sfx", 0.0, 1.0, 0.05)
	_slider(v, "Music", "music", 0.0, 1.0, 0.05)

	_section(v, "Privacy")
	var priv := UIKit.label("Your profile (settings, wardrobe, coins, level and stats) is stored only on this device. Online rooms use Game Center for your name and invitations; the game has no accounts, ads, tracking, chat or analytics.", 18, UIKit.IVORY_MUTED)
	priv.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(priv)
	var del := UIKit.quiet("Delete my local profile", Vector2(320, 72), 22)
	del.pressed.connect(func() -> void:
		dialog("Delete your coins, wardrobe, level and stats on this device? This cannot be undone.", [["Delete", func() -> void:
			Save.data = Save.default_profile()
			Save.save_now()
			App.goto_title("Local profile deleted.")], ["Cancel", Callable()]]))
	v.add_child(del)
	_section(v, "How to play")
	var how := UIKit.quiet("Open the rules card", Vector2(320, 72), 22)
	how.pressed.connect(func() -> void: App.goto(HowToScreen))
	v.add_child(how)
	_section(v, "Credits & licenses")
	var cred := UIKit.label("Made with Godot Engine (MIT). Game Center bindings: GodotApplePlugins (MIT). Font: Fredoka (SIL OFL 1.1). Characters built with Blender's Python module (the generated model is original). All characters, campus, sounds and music are original to Ultimate Trifecta. Moonbrook College is fictional.", 18, UIKit.IVORY_MUTED)
	cred.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(cred)
	v.add_child(UIKit.label("Version %s" % ProjectSettings.get_setting("application/config/version", "1.0"), 16, UIKit.IVORY_MUTED))
	focus_first(first)


func _on_controller(on: bool, n: String, ctl: Label) -> void:
	if is_instance_valid(ctl):
		ctl.text = "Controller: " + (n if on else "none connected (touch controls active)")


func _section(parent: Control, title: String) -> void:
	var l := UIKit.label(title, 22, UIKit.TEAL, true)
	parent.add_child(l)


func _slider(parent: Control, text: String, key: String, mn: float, mx: float, step: float) -> HSlider:
	var row := UIKit.hbox(16)
	var l := UIKit.label(text, 22)
	l.custom_minimum_size = Vector2(300, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = float(Save.get_setting(key, mn))
	s.custom_minimum_size = Vector2(360, maxf(44.0, UIKit.touch_min()))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.focus_mode = Control.FOCUS_ALL
	s.value_changed.connect(func(val: float) -> void: Save.set_setting(key, val))
	row.add_child(s)
	parent.add_child(row)
	return s


## Segmented choice: one button per option, the current one in teal.
func _choice(parent: Control, text: String, key: String, opts: Array) -> void:
	var row := UIKit.hbox(10)
	var l := UIKit.label(text, 22)
	l.custom_minimum_size = Vector2(300, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	var btns: Array[Button] = []
	for o in opts:
		var b := UIKit.quiet(String(o[1]), Vector2(200, 64), 19)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		var val: Variant = o[0]
		b.pressed.connect(func() -> void:
			Save.set_setting(key, val)
			_paint(btns, opts, key))
		row.add_child(b)
		btns.append(b)
	parent.add_child(row)
	_paint(btns, opts, key)


func _paint(btns: Array[Button], opts: Array, key: String) -> void:
	var cur: Variant = Save.get_setting(key, opts[0][0])
	for i in btns.size():
		var on := str(cur) == str(opts[i][0])
		if on:
			UIKit._apply(btns[i], UIKit.TEAL, UIKit.NAVY)
		else:
			btns[i].add_theme_stylebox_override("normal", UIKit.box(Color(UIKit.SLATE, 0.55), UIKit.R_BUTTON, 2, Color(UIKit.IVORY, 0.22)))
			btns[i].add_theme_stylebox_override("hover", UIKit.box(Color(UIKit.SLATE_HI, 0.75), UIKit.R_BUTTON, 2, Color(UIKit.IVORY, 0.3)))
			for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
				btns[i].add_theme_color_override(k, UIKit.IVORY)


func _check(parent: Control, text: String, key: String, def: bool) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = bool(Save.get_setting(key, def))
	c.custom_minimum_size = Vector2(0, maxf(44.0, UIKit.touch_min()))
	c.toggled.connect(func(on: bool) -> void: Save.set_setting(key, on))
	c.add_theme_font_size_override("font_size", 22)
	parent.add_child(c)
	return c
