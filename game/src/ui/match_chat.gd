class_name MatchChat
extends Control
## Chat during a round (V6), party rounds only.
##   button   a speech bubble beside Pause (a reserved touch region: it never
##            starts the stick or the camera)
##   feed     the last three messages of your channel, small, top right
##            under the minimap, fading after 6 s: never over the centre of
##            the screen (targets, runners) or the thumb controls
##   drawer   the shared ChatDrawer: your team ("Runners" / "Night Watch"),
##            or "Spectators" once you are home or watching.  While it is
##            open the round reads no input from you (InputOwner), the touch
##            controls are released and hidden, and nothing is left pressed
##            when it closes.
## Quick Chat is the main way to talk mid-chase; typed text is there when
## the moderation service is.

const FEED_S := 6.0
const FEED_MAX := 3

var hud: MatchHUD
var btn: Button
var feed: VBoxContainer
var drawer: ChatDrawer
var badge: PanelContainer
var badge_lbl: Label
var _shown := 0                 # newest sequence already in the feed
var _items: Array = []          # [{node, until}]


static func attach(p_hud: MatchHUD) -> MatchChat:
	var mc := p_hud.mc
	if mc == null or mc.session == null or mc.session.mode == NetSession.Mode.OFFLINE or bool(mc.start.get("practice", false)):
		return null
	var c := MatchChat.new()
	c.name = "MatchChat"
	c.hud = p_hud
	p_hud.root.add_child(c)
	return c


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	btn = UIKit.icon_button("chat", "", 64)
	btn.focus_mode = Control.FOCUS_NONE
	btn.tooltip_text = "Chat"
	btn.accessibility_name = "Chat"
	btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	btn.pressed.connect(open_drawer)
	var tr := hud.pause_btn.get_parent()
	tr.add_child(btn)
	tr.move_child(btn, hud.pause_btn.get_index())
	# unread count: a small gold badge on the button's corner
	badge = PanelContainer.new()
	badge.add_theme_stylebox_override("panel", UIKit.box(UIKit.AMBER, 999, 0, Color.WHITE, 4))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_lbl = UIKit.label("", 15, UIKit.NAVY, true, HORIZONTAL_ALIGNMENT_CENTER)
	badge_lbl.add_theme_font_override("font", UIKit.font_num(800))
	badge.add_child(badge_lbl)
	badge.visible = false
	btn.add_child(badge)
	badge.position = Vector2(btn.custom_minimum_size.x - 22.0, -6.0)
	feed = UIKit.vbox(4)
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(feed)
	var chat := hud.mc.session.social.chat
	chat.changed.connect(_on_chat)
	_shown = _newest()
	get_viewport().size_changed.connect(_layout)
	_layout.call_deferred()


## Touch regions the stick and camera must leave alone.
func reserved() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if is_instance_valid(btn):
		out.append(btn.get_global_rect().grow(12))
	return out


func _layout() -> void:
	if not is_instance_valid(feed):
		return
	var vs := get_viewport().get_visible_rect().size
	var sm := UIKit.safe_margins(get_viewport())
	var w := clampf(vs.x * 0.24, 280.0, 380.0)
	var tr := hud.pause_btn.get_parent() as Control
	feed.position = Vector2(vs.x - sm.size.x - w - 8.0, tr.get_global_rect().end.y + 10.0)
	feed.custom_minimum_size = Vector2(w, 0)
	feed.size = Vector2(w, 0)


func _round_state() -> Dictionary:
	var mc := hud.mc
	var st := int(mc._player_rs(mc.local_slot).get("state", TC.PState.ACTIVE)) if not mc.spectator else -1
	return {"finished": st == TC.PState.FINISHED, "spectator": mc.spectator}


func open_drawer() -> void:
	if drawer != null and is_instance_valid(drawer):
		return
	var mc := hud.mc
	if mc.touch:
		mc.touch.cancel_all()
		mc.touch.visible = false
	Controls.clear_edges()
	drawer = ChatDrawer.open(hud.root, mc.session, "round", _round_state())
	drawer.closed.connect(_on_closed)
	for it in _items:
		if is_instance_valid(it["node"]):
			(it["node"] as Control).queue_free()
	_items.clear()


func _on_closed() -> void:
	_paint_badge.call_deferred()
	var mc := hud.mc
	if mc != null and is_instance_valid(mc) and mc.touch:
		mc.touch.cancel_all()
		mc.touch.visible = true
	Controls.clear_edges()


func is_open() -> bool:
	return drawer != null and is_instance_valid(drawer)


func _newest() -> int:
	var n := 0
	for m in hud.mc.session.social.chat.history:
		n = maxi(n, int(m["seq"]))
	return n


func _on_chat() -> void:
	var chat := hud.mc.session.social.chat
	for m in chat.visible([QuickChat.Channel.TEAM, QuickChat.Channel.SPECTATORS], hud.mc.session.round_no):
		if int(m["seq"]) <= _shown:
			continue
		_shown = int(m["seq"])
		if is_open() or bool(m["mine"]):
			continue
		var pill := PanelContainer.new()
		pill.add_theme_stylebox_override("panel", UIKit.box(Color(UIKit.NAVY, 0.62), 14, 0, Color.WHITE, 8))
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := UIKit.label("%s: %s" % [chat.sender_name(m), String(m["text"])], 18, UIKit.IVORY)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.max_lines_visible = 2
		pill.add_child(l)
		feed.add_child(pill)
		_items.append({"node": pill, "until": Time.get_ticks_msec() / 1000.0 + FEED_S})
		while _items.size() > FEED_MAX:
			var old: Dictionary = _items.pop_front()
			if is_instance_valid(old["node"]):
				(old["node"] as Control).queue_free()
	_paint_badge()


func _paint_badge() -> void:
	var unread: int = hud.mc.session.social.chat.unread
	badge.visible = unread > 0 and not is_open()
	badge_lbl.text = str(mini(unread, 99))
	btn.accessibility_name = "Chat, %d new" % unread if unread > 0 else "Chat"


func _process(_delta: float) -> void:
	if _items.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	for it in _items.duplicate():
		var n: Control = it["node"]
		if not is_instance_valid(n):
			_items.erase(it)
			continue
		var left := float(it["until"]) - now
		if left <= 0.0:
			n.queue_free()
			_items.erase(it)
		elif left < 0.6 and not UIKit.reduced_motion():
			n.modulate.a = left / 0.6
