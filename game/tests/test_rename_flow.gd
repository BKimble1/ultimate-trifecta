extends RefCounted
## Changing your name from Settings while home (your party lobby) is up:
## Change name, type, Save, back to the lobby. With the game service (the
## name is checked online) and without it (saved on the device).
var t
var rig


func _settings_rename(new_name: String, tap_save: bool = false) -> void:
	App.goto_title()
	await rig.frames(20)
	t.check(App.stage != null and is_instance_valid(App.stage), "home: the lobby stage is up")
	App.goto(SettingsScreen)
	await rig.frames(12)
	var st := App.screen as SettingsScreen
	t.check(st != null, "Settings opened")
	if st == null:
		return
	var btn: Button = null
	for b in st.find_children("*", "Button", true, false):
		if (b as Button).text == "Change name":
			btn = b
	t.check(btn != null, "Change name offered")
	if btn == null:
		return
	btn.pressed.emit()
	await rig.frames(6)
	var sheets := st.find_children("*", "NameSheet", true, false)
	t.check(sheets.size() == 1, "the name sheet opens")
	if sheets.is_empty():
		return
	var ns: NameSheet = sheets[0]
	ns.field.grab_focus()
	ns.field.text = new_name
	ns._on_text(new_name)
	await rig.frames(3)
	if tap_save:
		# a phone: the keyboard is up while typing (the sheet docks above it),
		# then a finger taps Save (focus leaves the field, the keyboard goes)
		UIKit.v7_emulated_keyboard_pt = 210.0
		await rig.frames(4)
		t.check(ns.docked, "typing with the keyboard up: docked")
		var at := ns.save_btn.get_global_rect().get_center()
		for down in [true, false]:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.pressed = down
			e.position = at
			e.global_position = at
			e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
			if not down:
				UIKit.v7_emulated_keyboard_pt = 0.0   # iOS hides it as focus leaves
			t.get_tree().root.push_input(e, true)
			await rig.frames(2)
	else:
		ns._save()
	await rig.until(func() -> bool: return not is_instance_valid(ns) or ns.is_queued_for_deletion(), 240)
	await rig.frames(12)
	t.check(not is_instance_valid(ns) or ns.is_queued_for_deletion(), "the sheet closes on Save (%s)" % (ns.msg.text if is_instance_valid(ns) else ""))
	t.eq(Save.player_name(), new_name, "the new name is kept")
	# back home: one runner of ours on the stage
	NavShell.go("play")
	await rig.frames(20)
	if App.stage and is_instance_valid(App.stage):
		var rep: Dictionary = App.stage.views_report()
		t.check(int(rep.get("views", 0)) >= 1, "our runner is on the stage (%s)" % str(rep))
		for m in (rep.get("by_mark", {}) as Dictionary):
			if int(m) >= 0:
				t.check(int(rep["by_mark"][m]) == 1, "one character per spot (%s)" % str(rep))


func test_rename_from_settings_with_the_service() -> void:
	rig = preload("res://tests/commerce_rig.gd").new(t)
	await rig.begin()
	await rig.sign_in()
	await _settings_rename("Comfy Toad")
	await rig.end()


func test_rename_from_settings_on_device() -> void:
	rig = preload("res://tests/commerce_rig.gd").new(t)
	await rig.begin(false)
	Save.data["onboarded"] = true
	await _settings_rename("Sleepy Moth")
	await rig.end()


func test_rename_on_a_phone_tapping_save() -> void:
	rig = preload("res://tests/commerce_rig.gd").new(t)
	await rig.begin()
	await rig.sign_in()
	var dev := Controls.device
	Controls.device = "touch"
	Input.emulate_touch_from_mouse = true
	await _settings_rename("Brave Otter", true)
	UIKit.v7_emulated_keyboard_pt = -1.0
	Controls.device = dev
	Input.emulate_touch_from_mouse = false
	await rig.end()
