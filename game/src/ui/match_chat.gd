class_name MatchChat
extends Control
## Chat during a round (V6), party rounds only.
##   button   (2.2 build 16) a speech bubble under the minimap, beside the
##            Emote button (MatchActions owns both; a reserved touch region)
##   feed     (2.2 build 16) messages join the event feed on the left, like
##            a tag or a splash, in their own colour with who said them,
##            cut short when long
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
	var chat := hud.mc.session.social.chat
	chat.changed.connect(_on_chat)
	_shown = _newest()


## (2.2 build 16) MatchActions makes the button under the minimap; the
## unread badge goes on it.
func adopt_button(b: Button) -> void:
	btn = b
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


## Touch regions the stick and camera must leave alone.
func reserved() -> Array[Rect2]:
	return []   # (2.2 build 16) MatchActions reserves its buttons


func _round_state() -> Dictionary:
	var mc := hud.mc
	var st := int(mc._player_rs(mc.local_slot).get("state", TC.PState.ACTIVE)) if not mc.spectator else -1
	return {"finished": st == TC.PState.FINISHED, "spectator": mc.spectator}


func open_drawer() -> void:
	if drawer != null and is_instance_valid(drawer):
		return
	hud.overlay_opened("chat")   # V7: one owner list for every match overlay
	drawer = ChatDrawer.open(hud.root, hud.mc.session, "round", _round_state())
	drawer.closed.connect(_on_closed)
	for it in _items:
		if is_instance_valid(it["node"]):
			(it["node"] as Control).queue_free()
	_items.clear()


func _on_closed() -> void:
	_paint_badge.call_deferred()
	if is_instance_valid(hud):
		hud.overlay_closed("chat")


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
		if is_open():
			continue
		hud.feed_chat("You" if bool(m["mine"]) else chat.sender_name(m), String(m["text"]), bool(m["mine"]))
	_paint_badge()


func _paint_badge() -> void:
	if btn == null or badge == null:
		return
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
