class_name SettingsScreen
extends Screen


func build() -> void:
	header("Settings")
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.follow_focus = true
	content.add_child(sc)
	var v := UIKit.vbox(14)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	var first := _slider(v, "Camera sensitivity", "sensitivity", 0.3, 2.5, 0.05)
	_check(v, "Invert camera up/down", "invert_y")
	_check(v, "Reduced camera motion (slower recentring, no shake or bob)", "reduced_motion")
	_slider(v, "Sound effects volume", "sfx", 0.0, 1.0, 0.05)
	_slider(v, "Music volume", "music", 0.0, 1.0, 0.05)
	_check(v, "Touch: sprint by pushing the stick to the edge", "touch_sprint")
	_slider(v, "Touch sprint threshold (higher = harder to trigger)", "sprint_threshold", 0.7, 0.98, 0.01)
	var q := OptionButton.new()
	q.add_item("Graphics: Battery saver (no shadows/glow)", 0)
	q.add_item("Graphics: Standard", 1)
	q.selected = int(Save.get_setting("quality", 1))
	q.item_selected.connect(func(i: int) -> void: Save.set_setting("quality", i))
	q.custom_minimum_size = Vector2(560, 60)
	v.add_child(q)
	var pref := OptionButton.new()
	for p in ["Role preference: Any", "Role preference: Runner", "Role preference: Night Watch"]:
		pref.add_item(p)
	pref.selected = ["any", "runner", "patrol"].find(String(Save.get_setting("role_pref", "any")))
	pref.item_selected.connect(func(i: int) -> void: Save.set_setting("role_pref", ["any", "runner", "patrol"][i]))
	pref.custom_minimum_size = Vector2(560, 60)
	v.add_child(pref)
	var ctl := UIKit.label("Controller: " + (Controls.controller_name if Controls.has_controller() else "none connected (touch active)"), 22, UIKit.MUTED)
	v.add_child(ctl)
	Controls.controller_connection_changed.connect(func(on: bool, n: String) -> void:
		if is_instance_valid(ctl):
			ctl.text = "Controller: " + (n if on else "none connected (touch active)"))
	v.add_child(UIKit.label("Privacy", 28, UIKit.ACCENT, true))
	var priv := UIKit.label("Your profile (settings, wardrobe, coins, level and stats) is stored only on this device. Online rooms use Game Center for your name and invitations; the game has no accounts, ads, tracking, chat or analytics.", 20, UIKit.MUTED)
	priv.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(priv)
	var reset := UIKit.button("Delete my local profile", UIKit.BAD, Vector2(380, 60), 24)
	reset.pressed.connect(func() -> void:
		dialog("Delete your coins, wardrobe, level and stats on this device? This cannot be undone.", [["Delete", func() -> void:
			Save.data = Save.default_profile()
			Save.save_now()
			App.goto_title("Local profile deleted.")], ["Cancel", Callable()]]))
	v.add_child(reset)
	v.add_child(UIKit.label("Credits & licenses", 28, UIKit.ACCENT, true))
	var cred := UIKit.label("Made with Godot Engine (MIT). Game Center bindings: GodotApplePlugins (MIT). Font: Fredoka (SIL OFL 1.1). All characters, campus, sounds and music are original to Ultimate Trifecta. Moonbrook College is fictional.", 20, UIKit.MUTED)
	cred.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(cred)
	v.add_child(UIKit.label("Version %s" % ProjectSettings.get_setting("application/config/version", "1.0"), 18, UIKit.MUTED))
	focus_first(first)


func _slider(parent: Control, text: String, key: String, mn: float, mx: float, step: float) -> HSlider:
	var row := UIKit.hbox(16)
	var l := UIKit.label(text, 24)
	l.custom_minimum_size = Vector2(520, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = float(Save.get_setting(key, mn))
	s.custom_minimum_size = Vector2(320, 44)
	s.focus_mode = Control.FOCUS_ALL
	s.value_changed.connect(func(val: float) -> void: Save.set_setting(key, val))
	row.add_child(s)
	parent.add_child(row)
	return s


func _check(parent: Control, text: String, key: String) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = bool(Save.get_setting(key, false))
	c.toggled.connect(func(on: bool) -> void: Save.set_setting(key, on))
	c.add_theme_font_size_override("font_size", 24)
	parent.add_child(c)
	return c
