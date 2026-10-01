class_name OnlineScreen
extends Screen
## Private rooms over the internet (Game Center), join codes, friend invites
## and the friends list. Nothing here is mocked: if Game Center is unavailable
## the buttons are disabled with the reason, and practice remains available.

var code_edit: LineEdit
var friends_box: VBoxContainer
var friends_status: Label


func build() -> void:
	header("Play with Friends")
	var status := UIKit.label(Social.status_text(), 22, UIKit.MUTED)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(status)
	var ready := Social.online_ready()
	var row := UIKit.hbox(26)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)

	var left := UIKit.vbox(14)
	left.custom_minimum_size = Vector2(520, 0)
	row.add_child(left)
	var create := UIKit.button("Create a Room", Color(1.0, 0.72, 0.25), Vector2(500, 84), 32)
	create.disabled = not ready
	create.pressed.connect(func() -> void: App.host_room_gamekit())
	left.add_child(create)
	left.add_child(UIKit.label("You'll get a short code to share. Friends can also be invited with Game Center from the room.", 20, UIKit.MUTED))
	left.add_child(spacer(10))
	left.add_child(UIKit.label("Join with a code", 28, UIKit.TEXT, true))
	var jrow := UIKit.hbox(12)
	code_edit = LineEdit.new()
	code_edit.placeholder_text = "ABCDE"
	code_edit.max_length = SocialServiceCodes.LEN
	code_edit.custom_minimum_size = Vector2(260, 76)
	code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	code_edit.editable = ready
	code_edit.text_changed.connect(func(t: String) -> void:
		var n := Social.normalize_code(t)
		if n != t:
			code_edit.text = n
			code_edit.caret_column = n.length())
	jrow.add_child(code_edit)
	var join := UIKit.button("Join", Color(0.35, 0.75, 0.95), Vector2(200, 76))
	join.disabled = not ready
	join.pressed.connect(func() -> void:
		var c := Social.normalize_code(code_edit.text)
		if c.length() == SocialServiceCodes.LEN:
			App.join_room_gamekit(c)
		else:
			dialog("Room codes are %d letters/numbers." % SocialServiceCodes.LEN))
	jrow.add_child(join)
	left.add_child(jrow)
	if OS.is_debug_build() and not OS.has_feature("mobile"):
		left.add_child(spacer(10))
		left.add_child(UIKit.label("Developer LAN room (desktop debug builds only)", 20, UIKit.MUTED))
		var lan := UIKit.hbox(10)
		var host := UIKit.button("Host LAN", Color(0.3, 0.38, 0.7), Vector2(200, 60), 22)
		host.pressed.connect(func() -> void: App.host_room_enet())
		lan.add_child(host)
		var ip := LineEdit.new()
		ip.text = "127.0.0.1"
		ip.custom_minimum_size = Vector2(220, 60)
		ip.add_theme_font_size_override("font_size", 24)
		lan.add_child(ip)
		var lj := UIKit.button("Join LAN", Color(0.3, 0.38, 0.7), Vector2(200, 60), 22)
		lj.pressed.connect(func() -> void: App.join_room_enet(ip.text))
		lan.add_child(lj)
		left.add_child(lan)

	# friends entry point (Game Center friends who play)
	var right := UIKit.panel(Color(0.12, 0.15, 0.32, 0.9), 26, 18)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rv := UIKit.vbox(10)
	rv.add_child(UIKit.label("Friends", 30, UIKit.TEXT, true))
	friends_status = UIKit.label("Game Center can share your friends list with this game so you can see who plays. iOS will ask first; declining is fine — room codes still work.", 20, UIKit.MUTED)
	friends_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	friends_status.custom_minimum_size = Vector2(420, 0)
	rv.add_child(friends_status)
	var load_b := UIKit.button("Show my Game Center friends", Color(0.3, 0.45, 0.85), Vector2(420, 64), 24)
	load_b.disabled = not ready
	load_b.pressed.connect(func() -> void:
		friends_status.text = "Loading…"
		Social.load_friends())
	rv.add_child(load_b)
	friends_box = UIKit.vbox(6)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(420, 180)
	sc.add_child(friends_box)
	rv.add_child(sc)
	rv.add_child(UIKit.label("To invite friends, create a room and tap “Invite Friends”.", 18, UIKit.MUTED))
	right.add_child(rv)
	row.add_child(right)
	Social.friends_loaded.connect(_on_friends)
	focus_first(create if ready else load_b)
	if not ready:
		var prac := UIKit.button("Go to Practice", Color(0.35, 0.75, 0.95), Vector2(300, 64))
		prac.pressed.connect(func() -> void: App.goto(PracticeScreen))
		left.add_child(prac)
		_first_focus = prac


func _on_friends(friends: Array, err: String) -> void:
	if not is_instance_valid(friends_box):
		return
	for c in friends_box.get_children():
		c.queue_free()
	if err != "":
		friends_status.text = "Friends list unavailable: %s. Room codes still work." % err
		return
	friends_status.text = "%d Game Center friend(s) shared with Ultimate Trifecta." % friends.size()
	if friends.is_empty():
		friends_box.add_child(UIKit.label("No friends to show yet.", 20, UIKit.MUTED))
	for f in friends:
		friends_box.add_child(UIKit.label("•  " + String(f["name"]), 22))


class SocialServiceCodes:
	const LEN := 5
