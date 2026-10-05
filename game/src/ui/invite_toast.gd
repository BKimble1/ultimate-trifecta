class_name InviteToast
extends Control
## An incoming party invite (FINAL_RELEASE_SWEEP): a small card with who
## invited you, for which party, the time left, and Decline / Accept.
##   where   the right half of the screen, under the top row: never over the
##           left half (the party room's walk stick) or the bottom row
##   when    never during a round or its loading screen (the invite waits
##           for the results or the lobby), never over a dialog, and not
##           while a Friends panel is open (it lists invites itself)
##   how     it doesn't block anything around it (only the card takes
##           touches), takes no controller focus (the Friends panel has the
##           same actions for controllers), and after 15 s it folds into the
##           Friends button's badge; the invite stays in the panel until it
##           expires
## Owned by the Friends autoload (its own canvas layer above the screens).

const SHOW_S := 15.0

var card: PanelContainer
var title_l: Label
var sub_l: Label
var accept_btn: Button
var decline_btn: Button
var current: Dictionary = {}
var _shown_s := 0.0     # time on screen, counted in the 1 s state ticks (game time)
var _anchor := Vector2.ZERO


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UIKit.theme()


func _ready() -> void:
	card = UIKit.panel(Color(UIKit.SLATE_HI, 0.98), UIKit.R_PANEL, 16)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.visible = false
	add_child(card)
	card.minimum_size_changed.connect(_fit)
	var v := UIKit.vbox(10)
	card.add_child(v)
	var head := UIKit.hbox(12)
	var ic := Icons.IconRect.new("invite", UIKit.AMBER, 30)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(ic)
	var tv := UIKit.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_l = UIKit.styled("", "label")
	title_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(title_l)
	sub_l = UIKit.styled("", "caption", UIKit.IVORY_MUTED)
	sub_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(sub_l)
	head.add_child(tv)
	v.add_child(head)
	var row := UIKit.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_END
	decline_btn = UIKit.quiet("Decline", Vector2(150, UIKit.touch_min()), UIKit.T_LABEL)
	decline_btn.focus_mode = Control.FOCUS_NONE
	decline_btn.pressed.connect(func() -> void:
		var iv := current
		_hide(true)
		Friends.decline(iv))
	row.add_child(decline_btn)
	accept_btn = UIKit.secondary("Accept", Vector2(170, UIKit.touch_min()), UIKit.T_LABEL)
	accept_btn.focus_mode = Control.FOCUS_NONE
	accept_btn.pressed.connect(func() -> void:
		var iv := current
		_hide(true)
		Friends.accept(iv))
	row.add_child(accept_btn)
	v.add_child(row)


func showing() -> bool:
	return card != null and card.visible


func _allowed() -> bool:
	if not Friends.can_show_invites() or Friends.watching():
		return false
	var scr: Variant = App.screen
	if scr == null or not is_instance_valid(scr):
		return false
	return not (scr is Screen and (scr as Screen).has_modal())


## Called by Friends each second (`tick_s`) and whenever invites change.
func refresh(tick_s: float = 0.0) -> void:
	if card == null:
		return
	if showing():
		var still := false
		for iv in Friends.incoming:
			if String(iv["id"]) == String(current.get("id", "")):
				still = true
		if not still:
			_hide(false)
		elif Friends.watching():
			_hide(true)      # the panel shows it now
		elif not _allowed():
			_hide(false)     # a round started: shown again afterwards
		else:
			_shown_s += tick_s
			if _shown_s >= SHOW_S:
				_hide(true)      # folds into the Friends badge
			else:
				_paint()
		return
	if not _allowed():
		return
	var nxt := Friends.next_toast()
	if not nxt.is_empty():
		_show(nxt)


func _show(iv: Dictionary) -> void:
	current = iv
	_shown_s = 0.0
	_paint()
	card.visible = true
	_place()
	Sfx.play("pop")
	Motion.appear(card, -8.0, UIKit.T_FAST)


func _paint() -> void:
	var t := Friends.invite_text(current)
	title_l.text = String(t[0])
	var left := maxi(0, int((float(current.get("expires_at", 0)) - Friends.server_now_ms()) / 1000.0))
	sub_l.text = "%s · %d:%02d left" % [t[1], left / 60, left % 60]
	accept_btn.accessibility_name = "Accept: %s %s" % [t[0], t[1]]
	decline_btn.accessibility_name = "Decline: %s %s" % [t[0], t[1]]


## Right half, under the top row, inside the safe area.
func _place() -> void:
	var vs := get_viewport().get_visible_rect().size
	var sm := UIKit.safe_margins(get_viewport())
	var right := vs.x - sm.size.x - 16.0
	var w := clampf(vs.x * 0.4, 380.0, 600.0)
	w = minf(w, right - (vs.x * 0.5 + 8.0))
	# (wrapped text needs its width up front, or it measures one word a line)
	var text_w := w - 2.0 * 16.0 - 30.0 - 12.0
	title_l.custom_minimum_size.x = text_w
	sub_l.custom_minimum_size.x = text_w
	card.custom_minimum_size = Vector2(w, 0)
	_anchor = Vector2(right, sm.position.y + UIKit.touch_min() + 28.0)
	_fit()


## Shrink-wrap the card at its anchor (again once wrapped text has its width).
func _fit() -> void:
	if card == null or not card.visible:
		return
	card.reset_size()
	card.position = Vector2(_anchor.x - card.size.x, _anchor.y)


func _hide(done: bool) -> void:
	if done and not current.is_empty():
		Friends.mark_toasted(String(current.get("id", "")))
	card.visible = false
	if done:
		current = {}
