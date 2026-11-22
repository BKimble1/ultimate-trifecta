class_name NameSheet
extends PanelContainer
## Choose / change your player name.  (V6) The whole name policy is checked
## as you type (NameRules: abuse, impersonation, contact details, reserved
## names, with evasions handled); a refusal says why and offers three safe
## suggestions to tap.  The service still decides whether the name is
## allowed online and gives a discriminator for duplicates (#1234).
## Without the service the name is saved on this device only, and parties
## show a curated name instead (Save.party_name); the sheet says which.

signal done(name: String)
## (build 23) embedded in first-run setup: Back instead of Cancel
signal back_requested

var field: LineEdit
var msg: Label
var save_btn: Button
var sugg_row: HFlowContainer
var _busy := false
## first launch: keep the name on this device; the service checks it the
## first time you create or join a party (online screen asks again if needed)
var local_only := false
## (build 23) a step inside another screen's panel (first-run setup): no
## sheet chrome, no centring, Back keeps the typed name, Save doesn't close
var embedded := false
var title_l: Label
var sub_l: Label
## (build 32) set by the screen while the keyboard is up
var compact_typing := false:
	set(v):
		if v != compact_typing:
			compact_typing = v
			if is_instance_valid(field):
				_on_text(field.text)
var cancel_btn: Button
var button_row: HBoxContainer
## (build 33) the popup (changing your name later, from Settings or Online)
## while the keyboard is up: docked to the top, only what fits above it
var docked := false
var _title_size := 34


func _init() -> void:
	add_theme_stylebox_override("panel", UIKit.box(Color(UIKit.SLATE, 0.99), UIKit.R_PANEL, 0, Color.WHITE, 28))
	var v := UIKit.vbox(16)
	add_child(v)
	title_l = UIKit.heading("Your player name", 34)
	v.add_child(title_l)
	var sub := UIKit.label("Other players see this name. 3-16 letters, numbers, spaces or underscores.", 19, UIKit.IVORY_MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(560, 0)
	sub_l = sub
	v.add_child(sub)
	field = LineEdit.new()
	field.text = _current()
	field.max_length = NameRules.MAX_LEN
	field.custom_minimum_size = Vector2(560, maxf(84.0, UIKit.touch_min()))
	field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	field.select_all_on_focus = true
	field.text_changed.connect(_on_text)
	field.text_submitted.connect(func(_t: String) -> void: _save())
	v.add_child(field)
	msg = UIKit.label("", 19, UIKit.IVORY_MUTED)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size = Vector2(560, 0)
	v.add_child(msg)
	sugg_row = HFlowContainer.new()
	sugg_row.add_theme_constant_override("h_separation", 10)
	sugg_row.add_theme_constant_override("v_separation", 10)
	v.add_child(sugg_row)
	var row := UIKit.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_END
	button_row = row
	var cancel := UIKit.quiet("Cancel", Vector2(180, 80), 24)
	cancel.pressed.connect(cancel_sheet)
	cancel_btn = cancel
	row.add_child(cancel)
	save_btn = UIKit.primary("Save name", Vector2(260, 84), 28)
	save_btn.pressed.connect(_save)
	row.add_child(save_btn)
	v.add_child(row)
	_on_text(field.text)


func _ready() -> void:
	if embedded:
		# the name is already filled in: on touch, no keyboard until the
		# player taps the field; a controller or keyboard starts on Enter
		if Controls.device != "touch":
			save_btn.call_deferred("grab_focus")
		return
	field.call_deferred("grab_focus")
	set_process(true)
	# (V6) suggestions make the sheet taller: keep it centred on screen, and
	# shrink it back when they go
	resized.connect(func() -> void:
		if is_inside_tree() and not docked:
			position = ((get_viewport().get_visible_rect().size - size) * 0.5).max(Vector2.ZERO))
	minimum_size_changed.connect(func() -> void:
		if is_inside_tree():
			reset_size.call_deferred())


## (build 33) The popup and the keyboard. Build 32 fixed this for the first
## launch only; changing the name later (Settings, Online) still opened the
## sheet in the middle of the screen, where an iPhone's landscape keyboard
## (over half the screen) covered the name being typed. While typing the
## sheet now docks just under the top edge and keeps the field (and the
## buttons, when they fit) above the keyboard; the small print and the
## heading make room first.
func _process(_delta: float) -> void:
	if embedded or not is_inside_tree():
		return
	keyboard_fit()


func keyboard_fit() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var mobile := OS.has_feature("mobile") or OS.get_name() in ["iOS", "Android"]
	var emulated := UIKit.v7_emulated_keyboard_pt >= 0.0 or OS.get_cmdline_user_args().has("--sim-keyboard")
	var typing := field.has_focus() and (mobile or emulated)
	var vs := vp.get_visible_rect().size
	var kh := UIKit.v7_keyboard_height(vp)
	if typing:
		# whatever the keyboard reports (iOS reports it late, or not at all
		# on some models), keep the field in the top part of the screen
		kh = maxf(kh, vs.y * 0.6)
	var want := typing and kh > 0.0
	if want != docked:
		docked = want
		sub_l.visible = not docked
		title_l.add_theme_font_size_override("font_size", 24 if docked else _title_size)
		title_l.visible = true
		button_row.visible = true
		compact_typing = docked
	var top := UIKit.safe_margins(vp).position.y + 8.0
	if docked:
		var room := vs.y - kh - top - 8.0
		# the heading, then the buttons go if the field would not fit
		# (Return on the keyboard still saves)
		if get_combined_minimum_size().y > room and title_l.visible:
			title_l.visible = false
		if get_combined_minimum_size().y > room and button_row.visible:
			button_row.visible = false
		reset_size()
		position = Vector2(maxf(0.0, (vs.x - size.x) * 0.5), top)
	else:
		var p := ((vs - size) * 0.5).max(Vector2.ZERO)
		if position.distance_to(p) > 0.5:
			position = p


func cancel_sheet() -> void:
	if _busy:
		return
	if embedded:
		field.release_focus()
		back_requested.emit()
		return
	done.emit("")
	queue_free()


static func _current() -> String:
	var cp: Dictionary = Save.data.get("cloud_profile", {})
	var n: Variant = cp.get("display_name")
	if n != null and String(n) != "":
		return String(n)
	return Save.player_name()


func _on_text(t: String) -> void:
	var n := NameRules.normalize(t)
	var m := NameRules.moderate(n)
	var err := "" if bool(m["ok"]) else String(m["message"])
	var ok_text := "Checked when you save."
	if local_only and Cloud.configured():
		ok_text = "Saved on this device. The game service checks it when you first play online."
	elif not Cloud.configured():
		ok_text = "Saved on this device." + ("" if NameRules.is_curated(n) else
			" Parties show %s: without the online name check, parties use the game's own names." % NameRules.generated(String(Save.data.get("uid", ""))))
	msg.text = err if err != "" else ok_text
	msg.add_theme_color_override("font_color", UIKit.AMBER if err != "" else UIKit.IVORY_MUTED)
	# (build 32) while the keyboard is up only a problem is said (the fine
	# print makes room for the field and its button)
	msg.visible = err != "" or not compact_typing
	save_btn.disabled = err != "" or _busy
	# a refusal for the words in it (not just a typo) comes with safe ideas
	var words := not bool(m["ok"]) and not String(m["reason"]) in ["length", "characters", "spacing", "letters"]
	if words and sugg_row.get_child_count() == 0:
		_suggest(NameRules.suggestions(n, 3))
	elif not words and not _busy and bool(m["ok"]):
		for c in sugg_row.get_children():
			c.queue_free()


func _suggest(names: Array) -> void:
	for c in sugg_row.get_children():
		c.queue_free()
	for sg in names:
		var b := UIKit.secondary(String(sg), Vector2(0, 64), 21)
		var ss := String(sg)
		b.pressed.connect(func() -> void:
			field.text = ss
			_on_text(ss))
		sugg_row.add_child(b)


func _save() -> void:
	var n := NameRules.normalize(field.text)
	if not bool(NameRules.moderate(n)["ok"]) or _busy:
		return
	if not Cloud.configured() or local_only:
		Save.data["name"] = n
		Save.save_now()
		done.emit(n)
		if not embedded:
			queue_free()
		return
	_busy = true
	save_btn.disabled = true
	msg.text = "Checking…"
	for c in sugg_row.get_children():
		c.queue_free()
	var r: Dictionary = await Cloud.set_display_name(n)
	_busy = false
	if bool(r.get("ok", false)):
		Save.data["name"] = n
		Save.save_now()
		done.emit(Cloud.full_name())
		queue_free()
		return
	msg.text = Cloud.explain(r)
	msg.add_theme_color_override("font_color", UIKit.AMBER)
	save_btn.disabled = false
	_suggest(r.get("suggestions", []))


## (build 23) Use the sheet as a step inside another panel (first-run
## setup): its heading, buttons and widths follow that panel.
func embed(title: String, save_text: String, back_text: String) -> void:
	embedded = true
	local_only = true
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	title_l.text = title
	title_l.add_theme_font_size_override("font_size", UIKit.T_HEADLINE)
	sub_l.text = "Other players see this name. You can change it later in Settings."
	sub_l.add_theme_font_size_override("font_size", UIKit.T_CAPTION)
	for c: Control in [sub_l, msg, field]:
		c.custom_minimum_size.x = 0.0
	field.custom_minimum_size.y = maxf(72.0, UIKit.touch_min())
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg.add_theme_font_size_override("font_size", UIKit.T_CAPTION)
	cancel_btn.text = back_text
	cancel_btn.custom_minimum_size = Vector2(maxf(150.0, UIKit.row_h() * 1.8), UIKit.row_h())
	save_btn.text = save_text
	save_btn.custom_minimum_size = Vector2(maxf(250.0, UIKit.row_h() * 3.0), UIKit.row_h())
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.accessibility_name = back_text
	save_btn.accessibility_name = save_text
	_on_text(field.text)


## Show the sheet centred over a screen; returns the chosen name ("" = cancelled).
static func ask(parent: Control, on_device_only: bool = false) -> String:
	var dim := ColorRect.new()
	dim.color = Color(UIKit.NAVY, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(dim)
	var s := NameSheet.new()
	s.local_only = on_device_only
	s._on_text(s.field.text)
	parent.add_child(s)
	s.set_anchors_preset(Control.PRESET_CENTER)
	s.position = (parent.get_viewport().get_visible_rect().size - s.get_combined_minimum_size()) * 0.5
	UIKit.appear(s, Vector2(0, 14), UIKit.T_FAST)
	if parent is Screen:
		(parent as Screen).push_modal(s, s.cancel_sheet)
	var r: Variant = await s.done
	dim.queue_free()
	return String(r)
