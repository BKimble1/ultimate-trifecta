class_name OnlineScreen
extends Screen
## Play with Friends: a sheet over the dorm.  Create a private room (one
## primary action), join with a code, optionally show Game Center friends.
## Game Center status appears here, in context: if it is unavailable or the
## player declined sign-in, the actions say why and Practice stays one tap
## away.  Nothing is mocked.

var code_edit: LineEdit
var friends_box: VBoxContainer
var friends_status: Label
var _status_card: PanelContainer


func build() -> void:
	if App.stage:
		App.stage.set_mode("home")
	var row := UIKit.hbox(0)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)
	var back := UIKit.icon_button("back")
	back.tooltip_text = "Back"
	back.pressed.connect(_go_back)
	back.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(back)
	row.add_child(UIKit.spacer_h())
	var sheet := UIKit.panel(Color(UIKit.SLATE, 0.96), UIKit.R_PANEL, 28)
	sheet.custom_minimum_size = Vector2(560, 0)
	row.add_child(sheet)
	# the sheet scrolls rather than running off the bottom (status card on a
	# small phone, desktop LAN row)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	sheet.add_child(sc)
	var v := UIKit.vbox(18)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	v.add_child(UIKit.heading("Play with Friends", 38))
	var ready := Social.online_ready()
	if not ready:
		_status_card = _gc_card()
		v.add_child(_status_card)
	var create := UIKit.primary("Create a room", Vector2(500, 96), 32)
	create.disabled = not ready
	create.pressed.connect(func() -> void: App.host_room_gamekit())
	v.add_child(create)
	var hint := UIKit.label("You get a 5-letter code to share. You can invite Game Center friends from the room.", 19, UIKit.IVORY_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(500, 0)
	hint.visible = ready   # the status card explains things instead
	v.add_child(hint)
	v.add_child(UIKit.label("Join with a code", 24, UIKit.IVORY, true))
	var jrow := UIKit.hbox(12)
	code_edit = LineEdit.new()
	code_edit.placeholder_text = "ABCDE"
	code_edit.max_length = SocialServiceCodes.LEN
	code_edit.custom_minimum_size = Vector2(300, maxf(84.0, UIKit.touch_min()))
	code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_edit.editable = ready
	code_edit.text_changed.connect(func(t: String) -> void:
		var n := Social.normalize_code(t)
		if n != t:
			code_edit.text = n
			code_edit.caret_column = n.length())
	code_edit.text_submitted.connect(func(_t: String) -> void: _join())
	jrow.add_child(code_edit)
	var join := UIKit.secondary("Join", Vector2(188, 84), 28)
	join.disabled = not ready
	join.pressed.connect(_join)
	jrow.add_child(join)
	v.add_child(jrow)
	var fr := UIKit.quiet("Show Game Center friends", Vector2(500, 72), 22)
	fr.disabled = not ready
	fr.visible = ready
	fr.pressed.connect(func() -> void:
		friends_status.visible = true
		friends_status.text = "Loading…"
		Social.load_friends())
	v.add_child(fr)
	friends_status = UIKit.label("", 19, UIKit.IVORY_MUTED)
	friends_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	friends_status.custom_minimum_size = Vector2(500, 0)
	friends_status.visible = false
	v.add_child(friends_status)
	friends_box = UIKit.vbox(4)
	v.add_child(friends_box)
	if OS.is_debug_build() and not OS.has_feature("mobile"):
		v.add_child(UIKit.label("Developer LAN room (desktop debug builds only)", 18, UIKit.IVORY_MUTED))
		var lan := UIKit.hbox(10)
		var host := UIKit.quiet("Host LAN", Vector2(160, 64), 20)
		host.pressed.connect(func() -> void: App.host_room_enet())
		lan.add_child(host)
		var ip := LineEdit.new()
		ip.text = "127.0.0.1"
		ip.custom_minimum_size = Vector2(190, 64)
		ip.add_theme_font_size_override("font_size", 22)
		lan.add_child(ip)
		var lj := UIKit.quiet("Join LAN", Vector2(150, 64), 20)
		lj.pressed.connect(func() -> void: App.join_room_enet(ip.text))
		lan.add_child(lj)
		v.add_child(lan)
	Social.friends_loaded.connect(_on_friends)
	Social.auth_changed.connect(_on_auth)
	focus_first(create if ready else _first_focus)
	UIKit.appear(sheet, Vector2(40, 0), UIKit.T_SHEET)


func _gc_card() -> PanelContainer:
	var card := UIKit.panel(Color(UIKit.NAVY, 0.7), UIKit.R_SMALL, 18)
	var cv := UIKit.vbox(10)
	var msg := ""
	if not Social.available:
		msg = "Online rooms use Game Center, which is only available on iPhone and iPad. Practice works here."
	elif Social.multiplayer_restricted:
		msg = "Multiplayer is turned off for this Game Center account (Screen Time). Practice still works."
	elif Social.auth_error != "":
		msg = "You're not signed in to Game Center, so rooms and invites are off. Sign in from the Settings app (Game Center) and come back — Practice works meanwhile."
	else:
		msg = "Signing in to Game Center…"
	var l := UIKit.label(msg, 20, UIKit.IVORY)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(480, 0)
	cv.add_child(l)
	var prac := UIKit.secondary("Go to Practice", Vector2(260, 72), 24)
	prac.pressed.connect(func() -> void: App.goto(PracticeScreen))
	cv.add_child(prac)
	_first_focus = prac
	card.add_child(cv)
	return card


func _on_auth(_ok: bool) -> void:
	if is_inside_tree():
		App.goto(OnlineScreen)


func _join() -> void:
	if not Social.online_ready():
		return
	var c := Social.normalize_code(code_edit.text)
	if c.length() == SocialServiceCodes.LEN:
		App.join_room_gamekit(c)
	else:
		dialog("Room codes are %d letters or numbers." % SocialServiceCodes.LEN)


func _on_friends(friends: Array, err: String) -> void:
	if not is_instance_valid(friends_box):
		return
	for c in friends_box.get_children():
		c.queue_free()
	if err != "":
		friends_status.text = "Friends list unavailable (%s). Room codes still work." % err
		return
	friends_status.text = "%d Game Center friend%s play Ultimate Trifecta. Invite them from a room." % [friends.size(), "" if friends.size() == 1 else "s"]
	for f in friends:
		friends_box.add_child(UIKit.label("•  " + String(f["name"]), 22))


class SocialServiceCodes:
	const LEN := 5
