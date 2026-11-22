extends "res://src/dev/season_final_capture.gd"
## (build 32) The first-run name step with the keyboard up (development
## only; src/dev is never exported): run with --sim-keyboard, which gives
## the screen an iPhone-like landscape keyboard height.  Shot: name_keyboard.


func _run() -> void:
	LoginFlow.enabled = false
	if shot_set == "rename":
		await _rename()
		return
	App._onboarding()
	await _wait(1.5)
	var c := App.screen as CreatorScreen
	if c == null:
		printerr("NAME no creator screen")
		get_tree().quit()
		return
	c.show_name_step()
	await _wait(0.8)
	c.name_form.field.grab_focus()
	c.name_form.field.text = "TrapKid444"
	c.name_form.field.caret_column = 10
	c.name_form._on_text(c.name_form.field.text)
	await _wait(1.0)
	# the keyboard, drawn where iOS puts it (grey, labelled)
	var kh := float(DisplayServer.window_get_size().y) * 0.52
	var vs := get_viewport().get_visible_rect().size
	var units := roundf(kh * vs.y / maxf(1.0, float(DisplayServer.window_get_size().y)))
	var layer := CanvasLayer.new()
	layer.layer = 110
	add_child(layer)
	var kb := ColorRect.new()
	kb.color = Color(0.55, 0.57, 0.62, 0.96)
	kb.position = Vector2(0, vs.y - units)
	kb.size = Vector2(vs.x, units)
	layer.add_child(kb)
	await snap("name_keyboard")
	var r := c.name_form.field.get_global_rect()
	printerr("NAME field %s keyboard_top %.0f view %s visible_above %s" % [str(r), vs.y - units, str(vs), r.end.y <= vs.y - units])
	get_tree().quit()


## (build 33) --set=rename: changing the name later, from Settings, with the
## keyboard up. Shot: rename_keyboard.
func _rename() -> void:
	Save.data["onboarded"] = true
	var st := SettingsScreen.new()
	App._ensure_background()
	App._show(st)
	await _wait(1.2)
	NameSheet.ask(st, true)
	await _wait(0.6)
	var ns: NameSheet = st.find_children("*", "NameSheet", true, false)[0]
	ns.field.grab_focus()
	ns.field.text = "TrapKid444"
	ns.field.caret_column = 10
	ns._on_text(ns.field.text)
	await _wait(1.0)
	var vs := get_viewport().get_visible_rect().size
	var units := vs.y * 0.6
	var layer := CanvasLayer.new()
	layer.layer = 110
	add_child(layer)
	var kb := ColorRect.new()
	kb.color = Color(0.55, 0.57, 0.62, 0.96)
	kb.position = Vector2(0, vs.y - units)
	kb.size = Vector2(vs.x, units)
	layer.add_child(kb)
	await snap("rename_keyboard")
	var r := ns.field.get_global_rect()
	printerr("RENAME field %s keyboard_top %.0f docked %s save %s" % [str(r), vs.y - units, ns.docked, ns.save_btn.is_visible_in_tree()])
	get_tree().quit()
