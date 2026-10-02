class_name Screen
extends Control
## Base for menu screens: themed, safe-area aware, controller navigable
## (ui_cancel goes back), focuses its first button.

var content: VBoxContainer
var margin: MarginContainer
var _first_focus: Control
var back_action: Callable
## open sheets/dialogs, top last: {node, cancel, prev}
var _modals: Array[Dictionary] = []


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
	# entry transition: 180 ms fade (plus a small rise unless Reduced Motion)
	UIKit.appear(margin, Vector2.ZERO, 0.18)


func build() -> void:
	pass


func _apply_safe() -> void:
	var s := UIKit.safe_margins(get_viewport())
	margin.add_theme_constant_override("margin_left", int(s.position.x) + 24)
	margin.add_theme_constant_override("margin_top", int(s.position.y) + 16)
	margin.add_theme_constant_override("margin_right", int(s.size.x) + 24)
	margin.add_theme_constant_override("margin_bottom", int(s.size.y) + 16)
	margin.position = Vector2.ZERO


func focus_first(c: Control) -> void:
	if _first_focus == null:
		_first_focus = c


func header(title: String, show_back: bool = true) -> HBoxContainer:
	var h := UIKit.hbox(20)
	h.alignment = BoxContainer.ALIGNMENT_BEGIN
	if show_back:
		var b := UIKit.icon_button("back")
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.tooltip_text = "Back"
		b.pressed.connect(_go_back)
		h.add_child(b)
	var t := UIKit.heading(title, 40)
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
		get_viewport().set_input_as_handled()
		if not _modals.is_empty():
			var cb: Callable = _modals[-1]["cancel"]
			if cb.is_valid():
				cb.call()
			return
		_go_back()


## Registers an open sheet or dialog: controller/keyboard focus stays inside
## it (the screen behind can't take focus), Back runs `on_cancel` (an invalid
## Callable means Back does nothing, e.g. while working), and when it closes
## focus returns to the control that was focused when it opened.
func push_modal(node: Control, on_cancel: Callable) -> void:
	var vp := get_viewport()
	var prev: Control = vp.gui_get_focus_owner() if vp else null
	_modals.append({"node": node, "cancel": on_cancel, "prev": prev})
	margin.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	node.tree_exiting.connect(_on_modal_closed.bind(node), CONNECT_ONE_SHOT)


func _on_modal_closed(node: Control) -> void:
	var prev: Variant = null     # untyped: the opener may already be freed
	for i in range(_modals.size() - 1, -1, -1):
		if _modals[i]["node"] == node:
			prev = _modals[i]["prev"]
			_modals.remove_at(i)
			break
	if not is_instance_valid(prev):
		prev = null
	# a sheet that opened a dialog and then closed: the dialog returns focus
	# to whatever opened the sheet
	for m in _modals:
		var mp: Variant = m["prev"]
		if mp == null or not is_instance_valid(mp) or node.is_ancestor_of(mp) or mp == node:
			m["prev"] = prev
	if not _modals.is_empty():
		return
	margin.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
	if is_queued_for_deletion() or not is_inside_tree():
		return
	(func() -> void:
		if is_instance_valid(prev) and (prev as Control).is_inside_tree() and (prev as Control).is_visible_in_tree():
			(prev as Control).grab_focus()
		elif _modals.is_empty() and is_instance_valid(_first_focus) and _first_focus.is_inside_tree():
			_first_focus.grab_focus()).call_deferred()


func has_modal() -> bool:
	return not _modals.is_empty()


func spacer(h: float = 10) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


## Full-screen "working…" card that blocks input; free the returned node to
## dismiss it.
func busy(text: String) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(UIKit.NAVY, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var p := UIKit.panel(Color(UIKit.SLATE, 0.99), UIKit.R_PANEL, 30)
	var l := UIKit.label(text, 26, UIKit.IVORY, false, HORIZONTAL_ALIGNMENT_CENTER)
	l.custom_minimum_size = Vector2(480, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(l)
	root.add_child(p)
	add_child(root)
	p.position = (get_viewport().get_visible_rect().size - p.get_combined_minimum_size()) * 0.5
	push_modal(root, Callable())
	return root


func dialog(text: String, buttons: Array = [["OK", Callable()]]) -> PanelContainer:
	var dim := ColorRect.new()
	dim.color = Color(UIKit.NAVY, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var p := UIKit.panel(Color(UIKit.SLATE, 0.99), UIKit.R_PANEL, 30)
	var v := UIKit.vbox(22)
	var l := UIKit.label(text, 26, UIKit.IVORY, false, HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(600, 0)
	v.add_child(l)
	var row := UIKit.hbox(16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var first: Button = null
	var cancel_cb := Callable()
	for bdef in buttons:
		# Back = the dialog's non-destructive choice
		if String(bdef[0]) in ["Cancel", "OK", "Done", "Keep editing", "Not now", "Close"]:
			var cbd: Callable = bdef[1]
			cancel_cb = func() -> void:
				dim.queue_free()
				p.queue_free()
				if cbd.is_valid():
					cbd.call()
	for bdef in buttons:
		var b := UIKit.secondary(String(bdef[0]), Vector2(220, 76), 26) if first == null else UIKit.quiet(String(bdef[0]), Vector2(200, 76), 24)
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
	UIKit.appear(p, Vector2(0, 14), UIKit.T_FAST)
	push_modal(p, cancel_cb)
	p.tree_exiting.connect(func() -> void:
		if is_instance_valid(dim):
			dim.queue_free(), CONNECT_ONE_SHOT)
	if first:
		first.call_deferred("grab_focus")
	return p
