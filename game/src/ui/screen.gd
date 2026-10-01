class_name Screen
extends Control
## Base for menu screens: themed, safe-area aware, controller navigable
## (ui_cancel goes back), focuses its first button.

var content: VBoxContainer
var margin: MarginContainer
var _first_focus: Control
var back_action: Callable


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	content = UIKit.vbox(16)
	margin.add_child(content)


func _ready() -> void:
	_apply_safe()
	get_viewport().size_changed.connect(_apply_safe)
	build()
	if _first_focus:
		_first_focus.call_deferred("grab_focus")


func build() -> void:
	pass


func _apply_safe() -> void:
	var s := UIKit.safe_margins(get_viewport())
	margin.add_theme_constant_override("margin_left", int(s.position.x) + 24)
	margin.add_theme_constant_override("margin_top", int(s.position.y) + 16)
	margin.add_theme_constant_override("margin_right", int(s.size.x) + 24)
	margin.add_theme_constant_override("margin_bottom", int(s.size.y) + 16)


func focus_first(c: Control) -> void:
	if _first_focus == null:
		_first_focus = c


func header(title: String, show_back: bool = true) -> HBoxContainer:
	var h := UIKit.hbox(18)
	if show_back:
		var b := UIKit.button("‹ Back", Color(0.22, 0.26, 0.48), Vector2(150, 60), 24)
		b.pressed.connect(_go_back)
		h.add_child(b)
	var t := UIKit.outlined(UIKit.label(title, 46, UIKit.TEXT, true), 10)
	h.add_child(t)
	content.add_child(h)
	return h


func _go_back() -> void:
	if back_action.is_valid():
		back_action.call()
	else:
		App.goto_title()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_back()
		get_viewport().set_input_as_handled()


func spacer(h: float = 10) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func dialog(text: String, buttons: Array = [["OK", Callable()]]) -> PanelContainer:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var p := UIKit.panel(Color(0.10, 0.13, 0.30, 0.98), 28, 26)
	var v := UIKit.vbox(16)
	var l := UIKit.label(text, 28, UIKit.TEXT, false, HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(620, 0)
	v.add_child(l)
	var row := UIKit.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var first: Button = null
	for bdef in buttons:
		var b := UIKit.button(String(bdef[0]), Color(0.3, 0.45, 0.85), Vector2(200, 64))
		var cb: Callable = bdef[1]
		b.pressed.connect(func() -> void:
			dim.queue_free()
			p.queue_free()
			if cb.is_valid():
				cb.call())
		row.add_child(b)
		if first == null:
			first = b
	v.add_child(row)
	p.add_child(v)
	add_child(p)
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.position = (get_viewport().get_visible_rect().size - p.get_combined_minimum_size()) * 0.5
	if first:
		first.call_deferred("grab_focus")
	return p
