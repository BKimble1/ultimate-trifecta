class_name NameSheet
extends PanelContainer
## Choose / change your player name.  Character rules are checked as you type
## (NameRules); the service decides whether the name is allowed and gives a
## discriminator for duplicates (#1234).  Rejections come with three friendly
## suggestions you can tap.  Without the service (or offline) the name is
## saved on this device only, and the sheet says so.

signal done(name: String)

var field: LineEdit
var msg: Label
var save_btn: Button
var sugg_row: HFlowContainer
var _busy := false
## first launch: keep the name on this device; the service checks it the
## first time you create or join a party (online screen asks again if needed)
var local_only := false


func _init() -> void:
	add_theme_stylebox_override("panel", UIKit.box(Color(UIKit.SLATE, 0.99), UIKit.R_PANEL, 0, Color.WHITE, 28))
	var v := UIKit.vbox(16)
	add_child(v)
	v.add_child(UIKit.heading("Your player name", 34))
	var sub := UIKit.label("Other players see this name. 3-16 letters, numbers, spaces or underscores.", 19, UIKit.IVORY_MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(560, 0)
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
	var cancel := UIKit.quiet("Cancel", Vector2(180, 80), 24)
	cancel.pressed.connect(cancel_sheet)
	row.add_child(cancel)
	save_btn = UIKit.primary("Save name", Vector2(260, 84), 28)
	save_btn.pressed.connect(_save)
	row.add_child(save_btn)
	v.add_child(row)
	_on_text(field.text)


func _ready() -> void:
	field.call_deferred("grab_focus")


func cancel_sheet() -> void:
	if _busy:
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
	var err := NameRules.shape_error(n)
	var ok_text := "Checked when you save."
	if local_only and Cloud.configured():
		ok_text = "Saved on this device. The game service checks it when you first play online."
	elif not Cloud.configured():
		ok_text = "Saved on this device. Online names are checked by the game service when it's set up."
	msg.text = err if err != "" else ok_text
	msg.add_theme_color_override("font_color", UIKit.AMBER if err != "" else UIKit.IVORY_MUTED)
	save_btn.disabled = err != "" or _busy


func _save() -> void:
	var n := NameRules.normalize(field.text)
	if NameRules.shape_error(n) != "" or _busy:
		return
	if not Cloud.configured() or local_only:
		Save.data["name"] = n
		Save.save_now()
		done.emit(n)
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
	for s in r.get("suggestions", []):
		var b := UIKit.secondary(String(s), Vector2(0, 64), 21)
		var ss := String(s)
		b.pressed.connect(func() -> void:
			field.text = ss
			_on_text(ss))
		sugg_row.add_child(b)


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
