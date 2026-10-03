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
		UIKit.soft_focus.call_deferred(_first_focus)
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


## Wrapped labels report huge heights until their width is known, so the
## initial focus scroll of a ScrollContainer lands far down; once layout
## settles, start at the top.  V6: for the next three frames only, through
## this screen's own one-shot frame hook (dropped if the screen goes), and
## never under a finger that has already started to scroll it.
var _top_list: ScrollContainer
var _top_frames := 0


func _open_at_top(sc: ScrollContainer) -> void:
	_top_list = sc
	_top_frames = 3
	_hook_top()


func _hook_top() -> void:
	if is_inside_tree() and not get_tree().process_frame.is_connected(_settle_top):
		get_tree().process_frame.connect(_settle_top, CONNECT_ONE_SHOT)
	elif not is_inside_tree() and not tree_entered.is_connected(_hook_top):
		tree_entered.connect(_hook_top, CONNECT_ONE_SHOT)


func _settle_top() -> void:
	if _top_frames <= 0 or not is_instance_valid(_top_list):
		return
	_top_frames -= 1
	if TouchScroll.is_dragging(_top_list):
		_top_frames = 0
		return
	_top_list.scroll_vertical = 0
	if _top_frames > 0:
		_hook_top()


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
	var t := UIKit.styled(title, "title")
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
	# V6: lists behind it let go of the finger and stop gliding
	TouchScroll.release_all(self, node)
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
			UIKit.soft_focus(prev as Control)
		elif _modals.is_empty() and is_instance_valid(_first_focus) and _first_focus.is_inside_tree():
			UIKit.soft_focus(_first_focus)).call_deferred()


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
	var l := UIKit.styled(text, "body", UIKit.IVORY, HORIZONTAL_ALIGNMENT_CENTER)
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
	var l := UIKit.styled(text, "body", UIKit.IVORY, HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(minf(600.0, get_viewport().get_visible_rect().size.x * 0.6), 0)
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
		var b := UIKit.secondary(String(bdef[0]), Vector2(220, 76)) if first == null else UIKit.quiet(String(bdef[0]), Vector2(200, 76))
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
	Motion.appear(p, 10.0, UIKit.T_FAST)
	push_modal(p, cancel_cb)
	p.tree_exiting.connect(func() -> void:
		if is_instance_valid(dim):
			dim.queue_free(), CONNECT_ONE_SHOT)
	if first:
		UIKit.soft_focus.call_deferred(first)
	return p


# ---------------------------------------------------------------------------
# Popovers (V5: shared by home, lobby and wardrobe)
# ---------------------------------------------------------------------------
var _popover: Control


func close_popover() -> void:
	if _popover and is_instance_valid(_popover):
		_popover.queue_free()
	_popover = null


## A small card anchored to `anchor` with a dismiss catcher behind it.
## side: "above", "left" or "below".
func popover_at(anchor: Control, body: Control, side: String = "above") -> PanelContainer:
	close_popover()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var catcher := Button.new()
	catcher.flat = true
	catcher.focus_mode = Control.FOCUS_NONE
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.pressed.connect(close_popover)
	root.add_child(catcher)
	var p := UIKit.panel(Color(UIKit.SLATE_HI, 0.99), UIKit.R_PANEL, 18)
	p.add_child(body)
	root.add_child(p)
	var ar := anchor.get_global_rect()
	var sz := p.get_combined_minimum_size()
	var vis := get_viewport().get_visible_rect().size
	var pos := Vector2(ar.position.x, ar.position.y - sz.y - 12)
	match side:
		"left":
			pos = Vector2(ar.position.x - sz.x - 12, ar.position.y)
		"below":
			pos = Vector2(ar.position.x, ar.end.y + 12)
	var sm := UIKit.safe_margins(get_viewport())
	pos.x = clampf(pos.x, sm.position.x + 8, vis.x - sz.x - sm.size.x - 8)
	pos.y = clampf(pos.y, sm.position.y + 8, vis.y - sz.y - sm.size.y - 8)
	p.position = pos
	Motion.appear(p, 8.0 if side == "above" else -8.0 if side == "below" else 0.0, UIKit.T_FAST)
	_popover = root
	push_modal(root, close_popover)
	var first := body.find_children("*", "Button", true, false)
	if not first.is_empty():
		UIKit.soft_focus.call_deferred(first[0] as Button)
	return p


## The emote picker: a big tile per emote the player owns (V6: Season 1
## emotes only once earned); `on_pick(id)` runs after it closes.
func emote_picker(anchor: Control, on_pick: Callable, side: String = "above") -> void:
	var v := UIKit.vbox(12)
	v.add_child(UIKit.styled("Emote", "headline"))
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 10)
	for i in TC.EMOTES.size():
		var idx := i
		if Cosmetics.entry("emote", String(TC.EMOTES[i])).has("season") and not Save.owns("emote", String(TC.EMOTES[i])):
			continue
		g.add_child(icon_tile(Icons.emote_icon(i), String(TC.EMOTE_LABELS[TC.EMOTES[i]]), func() -> void:
			close_popover()
			on_pick.call(idx)))
	v.add_child(g)
	popover_at(anchor, v, side)


## A large icon tile (emote and move pickers): icon over a short label.
static func icon_tile(icon: String, label_text: String, on_press: Callable) -> Button:
	var b := UIKit.card_button(Vector2(150, 118), UIKit.SLATE)
	var f := UIKit.face_of(b)
	var v := UIKit.vbox(6)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := Icons.IconRect.new(icon, UIKit.AMBER, 48)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var l := UIKit.styled(label_text, "label", UIKit.IVORY, HORIZONTAL_ALIGNMENT_CENTER)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(l)
	f.add_child(v)
	b.accessibility_name = label_text
	b.pressed.connect(on_press)
	return b
