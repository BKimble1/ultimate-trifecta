class_name OnlineScreen
extends Screen
## Play with Friends: a sheet over the dorm with one primary action (Create
## Party) and Join with a code.  Party codes are 6 characters from an
## alphabet without look-alikes; typing is checked strictly as you go (only
## case, spaces and dashes are forgiven).  While the service is contacted the
## sheet shows progress with Cancel; every failure has its own message.
## Game Center status appears here, in context; Practice stays one tap away.

var code_edit: LineEdit
var code_msg: Label
var join_btn: Button
var create_btn: Button
var busy_card: PanelContainer
var busy_lbl: Label
var friends_box: VBoxContainer
var friends_status: Label
var who_lbl: Label
var _status_card: PanelContainer
var _op := 0          # increments on every start/cancel; stale results are ignored


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
	sheet.custom_minimum_size = Vector2(600, 0)
	row.add_child(sheet)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	sheet.add_child(sc)
	var v := UIKit.vbox(18)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	v.add_child(UIKit.heading("Play with Friends", 40))
	var ready := Social.online_ready()
	if not ready:
		_status_card = _gc_card()
		v.add_child(_status_card)
	# who you are online
	var who := UIKit.hbox(12)
	who_lbl = UIKit.label("", 20, UIKit.IVORY_MUTED)
	who_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	who.add_child(who_lbl)
	var rename := UIKit.quiet("Change name", Vector2(0, 60), 20)
	rename.pressed.connect(func() -> void:
		await NameSheet.ask(self)
		_refresh_who())
	who.add_child(rename)
	v.add_child(who)
	create_btn = UIKit.primary("Create Party", Vector2(540, 100), 34)
	create_btn.disabled = not ready
	create_btn.pressed.connect(_create)
	v.add_child(create_btn)
	var hint := UIKit.label("You get a 6-character code to share. Invite Game Center friends from the party.", 19, UIKit.IVORY_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(540, 0)
	hint.visible = ready
	v.add_child(hint)
	v.add_child(UIKit.label("Join with a code", 24, UIKit.IVORY, true))
	var jrow := UIKit.hbox(12)
	code_edit = LineEdit.new()
	code_edit.placeholder_text = "ACE-347"
	code_edit.max_length = 9    # room for "ABC-DEF" style spacing; parsing is strict
	code_edit.custom_minimum_size = Vector2(320, maxf(88.0, UIKit.touch_min()))
	code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_edit.add_theme_font_override("font", UIKit.font_w(700))
	code_edit.add_theme_font_size_override("font_size", 44)
	code_edit.editable = ready
	code_edit.text_changed.connect(_on_code_text)
	code_edit.text_submitted.connect(func(_t: String) -> void: _join())
	jrow.add_child(code_edit)
	join_btn = UIKit.secondary("Join", Vector2(200, 88), 30)
	join_btn.disabled = true
	join_btn.pressed.connect(_join)
	jrow.add_child(join_btn)
	v.add_child(jrow)
	code_msg = UIKit.label("", 19, UIKit.IVORY_MUTED)
	code_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	code_msg.custom_minimum_size = Vector2(540, 0)
	v.add_child(code_msg)
	# progress (service and Game Center), with Cancel
	busy_card = UIKit.panel(Color(UIKit.NAVY, 0.72), UIKit.R_SMALL, 18)
	var bh := UIKit.hbox(14)
	busy_lbl = UIKit.label("", 22, UIKit.IVORY, true)
	busy_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(busy_lbl)
	var cancel := UIKit.quiet("Cancel", Vector2(170, 68), 22)
	cancel.pressed.connect(_cancel)
	bh.add_child(cancel)
	busy_card.add_child(bh)
	busy_card.visible = false
	v.add_child(busy_card)
	var fr := UIKit.quiet("Show Game Center friends", Vector2(540, 72), 22)
	fr.disabled = not ready
	fr.visible = ready
	fr.pressed.connect(func() -> void:
		friends_status.visible = true
		friends_status.text = "Loading…"
		Social.load_friends())
	v.add_child(fr)
	friends_status = UIKit.label("", 19, UIKit.IVORY_MUTED)
	friends_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	friends_status.custom_minimum_size = Vector2(540, 0)
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
	App.party_error.connect(_on_party_error)
	_refresh_who()
	focus_first(create_btn if ready else _first_focus)
	UIKit.appear(sheet, Vector2(40, 0), UIKit.T_SHEET)


func _refresh_who() -> void:
	if not is_instance_valid(who_lbl):
		return
	if not Cloud.configured():
		who_lbl.text = "Playing as %s" % Save.player_name()
	elif Cloud.full_name() != "":
		who_lbl.text = "Playing as %s" % Cloud.full_name()
	else:
		who_lbl.text = "Playing as %s (you'll confirm your name before your first party)" % Save.player_name()


func _gc_card() -> PanelContainer:
	var card := UIKit.panel(Color(UIKit.NAVY, 0.7), UIKit.R_SMALL, 18)
	var cv := UIKit.vbox(10)
	var msg := ""
	if not Social.available:
		msg = "Online parties use Game Center, which is only available on iPhone and iPad. Practice works here."
	elif Social.multiplayer_restricted:
		msg = "Multiplayer is turned off for this Game Center account (Screen Time). Practice still works."
	elif Social.auth_error != "":
		msg = "You're not signed in to Game Center, so parties and invites are off. Sign in from the Settings app (Game Center) and come back — Practice works meanwhile."
	else:
		msg = "Signing in to Game Center…"
	var l := UIKit.label(msg, 20, UIKit.IVORY)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(520, 0)
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


## Live, strict feedback while typing a code.
func _on_code_text(t: String) -> void:
	var up := t.to_upper()
	if up != t:
		var c := code_edit.caret_column
		code_edit.text = up
		code_edit.caret_column = c
	var stripped := up.replace(" ", "").replace("-", "")
	if stripped.length() == 0:
		code_msg.text = ""
		join_btn.disabled = true
		return
	var r := Social.parse_code(up)
	if bool(r["ok"]):
		code_msg.text = ""
		join_btn.disabled = not Social.online_ready()
	else:
		join_btn.disabled = true
		# while still typing, only flag real mistakes (a wrong character)
		var bad := ""
		for ch in stripped:
			if not Social.CODE_ALPHABET.contains(ch):
				bad = ch
				break
		code_msg.text = String(r["message"]) if bad != "" or stripped.length() > Social.CODE_LEN else ""
		code_msg.add_theme_color_override("font_color", UIKit.AMBER)


## Make sure the online profile has an approved name (service builds only).
func _ensure_name() -> bool:
	if not Cloud.configured():
		return true
	if not Cloud.signed_in():
		_busy("Signing in…")
		var s: Dictionary = await Cloud.sign_in()
		_idle()
		if not bool(s.get("ok", false)):
			_on_party_error(Cloud.explain(s), String(s.get("error", "")))
			return false
	if bool(Cloud.profile.get("needs_name", false)):
		var n := await NameSheet.ask(self)
		_refresh_who()
		return n != ""
	return true


func _create() -> void:
	if not await _ensure_name():
		return
	_op += 1
	var op := _op
	_busy("Creating your party…")
	await App.host_room_gamekit()
	if op == _op and is_inside_tree():
		_idle()


func _join() -> void:
	var r := Social.parse_code(code_edit.text)
	if not bool(r["ok"]):
		code_msg.text = String(r["message"])
		code_msg.add_theme_color_override("font_color", UIKit.AMBER)
		return
	if not Social.online_ready() or not await _ensure_name():
		return
	_op += 1
	var op := _op
	_busy("Checking code %s…" % r["code"])
	await App.join_room_gamekit(String(r["code"]))
	if op == _op and is_inside_tree():
		_idle()


func _busy(text: String) -> void:
	busy_lbl.text = text
	busy_card.visible = true
	create_btn.disabled = true
	join_btn.disabled = true


func _idle() -> void:
	if not is_instance_valid(busy_card):
		return
	busy_card.visible = false
	create_btn.disabled = not Social.online_ready()
	_on_code_text(code_edit.text)


func _cancel() -> void:
	_op += 1
	App.cancel_party_request()
	_idle()


func _on_party_error(message: String, code: String) -> void:
	if not is_inside_tree():
		return
	_idle()
	var title: String = {
		"not_found": "No party with that code",
		"expired": "That party has ended",
		"full": "That party is full",
		"in_match": "They're in a round",
		"not_ready": "Almost ready",
		"version_mismatch": "Different game versions",
		"not_allowed": "Can't join",
		"suspended": "Online play paused",
		"code_format": "Check the code",
		"network": "No connection",
	}.get(code, "")
	dialog((title + "\n" if title != "" else "") + message)


func _on_friends(friends: Array, err: String) -> void:
	if not is_instance_valid(friends_box):
		return
	for c in friends_box.get_children():
		c.queue_free()
	if err != "":
		friends_status.text = "Friends list unavailable (%s). Party codes still work." % err
		return
	friends_status.text = "%d Game Center friend%s play Ultimate Trifecta. Invite them from your party." % [friends.size(), "" if friends.size() == 1 else "s"]
	for f in friends:
		friends_box.add_child(UIKit.label("•  " + NameRules.safe_display(String(f["name"])), 22))
