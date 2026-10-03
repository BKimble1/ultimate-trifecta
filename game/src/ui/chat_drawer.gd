class_name ChatDrawer
extends Control
## The chat drawer (V6): party room, results and rounds share it.
##   header      who hears you ("Party", "Runners", "Night Watch",
##               "Spectators", "Everyone") and Close
##   typed text  at the top, so the iOS keyboard never covers it; only when
##               the moderation service is working (else it says why and
##               Quick Chat carries on).  Text is checked on the device,
##               then approved and signed by the service; a refusal shows
##               its reason under the field and the text is never posted
##   messages    a finger-scrolled list; tap someone else's message to Mute,
##               Block or Report (a typed message can be reported itself)
##   Quick Chat  the phrases for this channel and role, one tap to send
## Opening it takes input ownership (InputOwner): nothing moves, jumps or
## tags while it is open, and stuck touches are cleared when it closes.

signal closed

var session: NetSession
var context := "party"        # party | results | round
var finished := false         # round: the local runner is home (spectators)
var spectator := false        # round: watching (no seat)
var panel: PanelContainer
var list_box: VBoxContainer
var scroll: ScrollContainer
var field: LineEdit
var send_btn: Button
var note_lbl: Label
var title_lbl: Label
var quick_box: Container     # chips: a flow (tall screens) or one sideways strip (phones)
var quick_strip: ScrollContainer = null
var _open_actions := -1       # seq of the message whose actions are showing
var _show_row: Control = null  # that message's row: kept in view instead of the newest
var _sending := false


static func open(parent: Control, p_session: NetSession, p_context: String, opts: Dictionary = {}) -> ChatDrawer:
	var d := ChatDrawer.new()
	d.session = p_session
	d.context = p_context
	d.finished = bool(opts.get("finished", false))
	d.spectator = bool(opts.get("spectator", false))
	parent.add_child(d)
	if parent is Screen:
		(parent as Screen).push_modal(d, d.close)
	return d


## Below this panel height in canvas units the Quick Chat phrases sit in one
## sideways strip.  The canvas is 720 units tall on every phone held sideways
## (16:9 or wider) and 960 on a 4:3 iPad.
const SHORT_PANEL := 800.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UIKit.theme()


func channel() -> int:
	match context:
		"results":
			return QuickChat.Channel.ALL
		"round":
			return QuickChat.Channel.SPECTATORS if finished or spectator else QuickChat.Channel.TEAM
	return QuickChat.Channel.PARTY


func my_role() -> int:
	return session.social.chat.role_of(session.local_slot)


func channel_title() -> String:
	match channel():
		QuickChat.Channel.TEAM:
			return "Night Watch chat" if my_role() == TC.Role.PATROL else "Runners chat"
		QuickChat.Channel.SPECTATORS:
			return "Spectators chat"
		QuickChat.Channel.ALL:
			return "Everyone"
	return "Party chat"


func channel_note() -> String:
	match channel():
		QuickChat.Channel.TEAM:
			return "Only your team hears you."
		QuickChat.Channel.SPECTATORS:
			return "You can see the whole campus now, so only other spectators hear you."
		QuickChat.Channel.ALL:
			return "Everyone in the party hears you."
	return "Everyone in the party hears you."


func _ready() -> void:
	InputOwner.take("chat")
	var vs := get_viewport().get_visible_rect().size
	var sm := UIKit.safe_margins(get_viewport())
	var catcher := Control.new()
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			close())
	add_child(catcher)
	panel = UIKit.panel(Color(UIKit.SLATE, 0.97), UIKit.R_PANEL, 18)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var w := clampf(vs.x * 0.42, 420.0, 640.0)
	panel.position = Vector2(vs.x - sm.size.x - w - 12.0, sm.position.y + 12.0)
	panel.size = Vector2(w, vs.y - sm.position.y - sm.size.y - 24.0)
	panel.custom_minimum_size = panel.size
	add_child(panel)
	var v := UIKit.vbox(10)
	panel.add_child(v)
	var head := UIKit.hbox(10)
	var hv := UIKit.vbox(0)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl = UIKit.styled(channel_title(), "headline")
	hv.add_child(title_lbl)
	var sub := UIKit.styled(channel_note(), "caption", UIKit.IVORY_MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hv.add_child(sub)
	head.add_child(hv)
	var close_b := UIKit.icon_button("close")
	close_b.accessibility_name = "Close chat"
	close_b.tooltip_text = "Close chat"
	close_b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_b.pressed.connect(close)
	head.add_child(close_b)
	v.add_child(head)
	# typed text (top: clear of the on-screen keyboard)
	var av := session.social.chat.text_available()
	if bool(av["ok"]):
		var row := UIKit.hbox(8)
		field = LineEdit.new()
		field.placeholder_text = "Message (%d characters)" % ChatRules.MAX_LEN
		field.max_length = ChatRules.MAX_LEN
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.custom_minimum_size = Vector2(0, UIKit.touch_min())
		field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
		field.context_menu_enabled = false
		field.text_submitted.connect(func(_t: String) -> void: _send_text())
		field.text_changed.connect(func(_t: String) -> void: note_lbl.text = "")
		row.add_child(field)
		send_btn = UIKit.secondary("Send", Vector2(130, UIKit.touch_min()))
		send_btn.pressed.connect(_send_text)
		row.add_child(send_btn)
		v.add_child(row)
	note_lbl = UIKit.styled("" if bool(av["ok"]) else String(av["why"]), "caption", UIKit.IVORY_MUTED if not bool(av["ok"]) else UIKit.AMBER)
	note_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note_lbl)
	# messages
	scroll = UIKit.scroll_area()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	list_box = UIKit.vbox(6)
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_box)
	# quick chat: on a phone held sideways the phrases are one strip that
	# scrolls sideways, so the messages keep most of the height
	v.add_child(UIKit.styled("Quick Chat", "overline", UIKit.IVORY_MUTED))
	if panel.size.y < SHORT_PANEL:
		quick_strip = UIKit.scroll_area(true)
		quick_strip.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER   # (the cut-off last phrase shows there is more)
		quick_strip.custom_minimum_size.y = maxf(60.0, UIKit.touch_min()) + 4.0
		quick_box = UIKit.hbox(8)
		quick_strip.add_child(quick_box)
		v.add_child(quick_strip)
	else:
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		quick_box = flow
		v.add_child(flow)
	_build_quick()
	session.social.chat.changed.connect(_refresh)
	session.social.chat.rejected.connect(_on_rejected)
	session.social.chat.unread = 0
	_refresh()
	if not UIKit.reduced_motion():
		panel.modulate.a = 0.0
		Motion.animate(panel, "modulate:a", 1.0, UIKit.T_FAST)
	var first := quick_box.get_child(0) if quick_box.get_child_count() > 0 else null
	if first != null and Controls.device != "touch":
		UIKit.soft_focus.call_deferred(first as Control)


func _exit_tree() -> void:
	InputOwner.release("chat")
	if is_instance_valid(session) and session.social != null:
		session.social.chat.unread = 0


func close() -> void:
	if is_queued_for_deletion():
		return
	if field and field.has_focus():
		field.release_focus()
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		DisplayServer.virtual_keyboard_hide()
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _build_quick() -> void:
	for c in quick_box.get_children():
		c.queue_free()
	var ch := channel()
	for id in QuickChat.offered(ch, my_role()):
		var pid: int = id
		var b := UIKit.quiet(QuickChat.text(pid), Vector2(0, maxf(60.0, UIKit.touch_min())), UIKit.T_CAPTION)
		b.pressed.connect(func() -> void:
			if not session.social.chat.send_quick(pid, channel()):
				note_lbl.text = "That message isn't available right now."
				note_lbl.add_theme_color_override("font_color", UIKit.AMBER))
		quick_box.add_child(b)


func _send_text() -> void:
	if field == null or _sending:
		return
	var raw := field.text
	if raw.strip_edges() == "":
		return
	_sending = true
	send_btn.disabled = true
	note_lbl.text = "Checking…"
	note_lbl.add_theme_color_override("font_color", UIKit.IVORY_MUTED)
	var r: Dictionary = await session.social.chat.send_text(raw, channel())
	if not is_inside_tree():
		return
	_sending = false
	send_btn.disabled = false
	if bool(r.get("ok", false)):
		field.text = ""
		note_lbl.text = ""
	else:
		# the reason only: the refused text is never posted or shown elsewhere
		note_lbl.text = String(r.get("message", "That message can't be sent."))
		note_lbl.add_theme_color_override("font_color", UIKit.AMBER)


func _on_rejected(msg: String) -> void:
	if is_instance_valid(note_lbl):
		note_lbl.text = msg
		note_lbl.add_theme_color_override("font_color", UIKit.AMBER)


func visible_messages() -> Array:
	var chat := session.social.chat
	if context == "round":
		return chat.visible([QuickChat.Channel.TEAM, QuickChat.Channel.SPECTATORS], session.round_no)
	return chat.visible([QuickChat.Channel.PARTY, QuickChat.Channel.ALL])


func _refresh() -> void:
	if not is_instance_valid(list_box):
		return
	for c in list_box.get_children():
		c.queue_free()
	_show_row = null
	var msgs := visible_messages()
	if msgs.is_empty():
		var e := UIKit.styled("No messages yet. Say hi with Quick Chat.", "caption", UIKit.IVORY_MUTED)
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list_box.add_child(e)
	for m in msgs:
		list_box.add_child(_row(m))
	session.social.chat.unread = 0
	if _show_row != null:
		_reveal(_show_row)
	else:
		_scroll_to_end.call_deferred()


func _scroll_to_end() -> void:
	if is_instance_valid(scroll):
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


## A message with its actions open stays in view (new messages arriving
## don't scroll it away), once the list has been laid out.
func _reveal(row: Control) -> void:
	await get_tree().process_frame
	if is_instance_valid(scroll) and is_instance_valid(row) and row.is_inside_tree():
		scroll.ensure_control_visible(row)


func _row(m: Dictionary) -> Control:
	var chat := session.social.chat
	var mine := bool(m["mine"])
	var box := UIKit.vbox(4)
	var b := UIKit.card_button(Vector2(0, 0), Color(UIKit.SLATE_HI, 0.85) if mine else Color(UIKit.NAVY, 0.55))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var inner := UIKit.vbox(0)
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 14
	inner.offset_right = -14
	inner.offset_top = 8
	inner.offset_bottom = -8
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var who := chat.sender_name(m)
	var state := String(m.get("state", "sent"))
	var head := UIKit.styled(who + ("  ·  sending…" if state == "pending" else ("  ·  not sent" if state == "failed" else "")), "caption",
		UIKit.AMBER if mine else UIKit.TEAL)
	head.add_theme_font_size_override("font_size", 18)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(head)
	# always plain text in a Label: no markup is ever interpreted
	var body := UIKit.styled(String(m["text"]), "body", UIKit.IVORY if state != "failed" else UIKit.IVORY_DIM)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(body)
	UIKit.face_of(b).add_child(inner)
	b.accessibility_name = "%s: %s" % [who, String(m["text"])]
	var resize := func() -> void:
		if is_instance_valid(b) and is_instance_valid(inner):
			b.custom_minimum_size.y = inner.get_combined_minimum_size().y + 16.0
	inner.minimum_size_changed.connect(resize)
	resize.call_deferred()
	box.add_child(b)
	if not mine and int(m["seq"]) > 0:
		var seq := int(m["seq"])
		b.pressed.connect(func() -> void:
			_open_actions = -1 if _open_actions == seq else seq
			_refresh())
		if _open_actions == seq:
			box.add_child(_actions(m))
			_show_row = box
	return box


func _actions(m: Dictionary) -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	var uid := String(m["uid"])
	var slot := int(m["from"])
	var e: Dictionary = session.roster[slot] if slot >= 0 and slot <= 7 and session.roster[slot] != null else {"uid": uid, "pid": m["pid"], "name": m["name"], "slot": slot}
	var shown := SocialSafety.name_of(e)
	var mute := UIKit.quiet("Mute", Vector2(0, 60), UIKit.T_CAPTION)
	mute.pressed.connect(func() -> void:
		SocialActions.toggle_mute(session, uid)
		_open_actions = -1
		note_lbl.text = "%s is muted for this party (chat and emotes)." % shown
		note_lbl.add_theme_color_override("font_color", UIKit.IVORY_MUTED)
		_refresh())
	row.add_child(mute)
	if int(m["kind"]) == SocialProto.Kind.TEXT:
		var rm := UIKit.quiet("Report message", Vector2(0, 60), UIKit.T_CAPTION)
		rm.pressed.connect(func() -> void:
			ReportSheet.open(self, {"kind": "message", "name": shown, "pid": String(m["pid"]), "token": String(m["token"])}))
		row.add_child(rm)
	var rp := UIKit.quiet("Report player", Vector2(0, 60), UIKit.T_CAPTION)
	rp.pressed.connect(func() -> void:
		ReportSheet.open(self, {"kind": "player", "name": shown, "pid": String(e.get("pid", "")),
			"context": {"room_code": session.room_code, "build": App.build_number()}}))
	row.add_child(rp)
	var bl := UIKit.quiet("Block…", Vector2(0, 60), UIKit.T_CAPTION)
	bl.pressed.connect(func() -> void:
		# confirm in place: what blocking does, then Block / Cancel
		for c in row.get_children():
			c.queue_free()
		var q := UIKit.styled("Block %s? You won't see their chat, emotes or name, and you won't be put in parties together." % shown, "caption", UIKit.IVORY)
		q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		q.custom_minimum_size = Vector2(minf(panel.size.x - 60.0, 520.0), 0)
		row.add_child(q)
		var yes := UIKit.secondary("Block", Vector2(0, 60), UIKit.T_CAPTION)
		yes.pressed.connect(func() -> void:
			_open_actions = -1
			var note: String = await SocialActions.block(session, e)
			if is_instance_valid(note_lbl):
				note_lbl.text = note
				note_lbl.add_theme_color_override("font_color", UIKit.IVORY_MUTED)
				_refresh())
		row.add_child(yes)
		var no := UIKit.quiet("Cancel", Vector2(0, 60), UIKit.T_CAPTION)
		no.pressed.connect(func() -> void:
			_open_actions = -1
			_refresh())
		row.add_child(no))
	row.add_child(bl)
	return row
