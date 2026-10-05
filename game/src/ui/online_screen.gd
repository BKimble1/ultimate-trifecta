class_name OnlineScreen
extends Screen
## Play with Friends (V7): a header (Back, the title, who you play as and
## Change name), then two cards side by side - Start a party (the one gold
## action, Create Party) and Join with a code (the code field and Join on one
## row, the same height, a one-line message under them) - and the Game
## Center friends entry below them (Final: Friends, who's playing and
## invites, FriendsPanel).  Everything a player needs is in the
## first view on every supported phone and iPad; on a narrow screen the two
## cards stack.  Party codes are 6 characters from an alphabet without
## look-alikes; typing is checked strictly as you go (only case, spaces and
## dashes are forgiven).  While the service is contacted the screen shows
## progress with Cancel; every failure has its own message.  Game Center
## status appears here, in context; Practice stays one tap away.
## The on-screen keyboard: the header (Back) stays put; when the keyboard
## would cover the code row, the list below the header scrolls just enough
## to keep the field and Join above it, and returns when it closes.

var code_edit: LineEdit
var code_msg: Label
var join_btn: Button
var create_btn: Button
var busy_card: PanelContainer
var busy_lbl: Label
var friends_btn: Button
var who_lbl: Label
var rename_btn: Button
var back_btn: Button
var join_row: HBoxContainer
var cards: HFlowContainer
var _status_card: PanelContainer
var _op := 0          # increments on every start/cancel; stale results are ignored
var code_pad: GridContainer   # controller code entry (no system keyboard needed)
var _busy_cancel: Button
var _sc: ScrollContainer
## keyboard: its height in canvas units, the list's room to scroll past it,
## and the list position to return to when it closes (-1: not moved)
var _kb := 0.0
var _kb_space: Control
var _kb_from := -1
var _friends_hint: Label

const HINT := "Ask the host for their 6-character code."
## the code field's and Join's type size
const CODE_FS := 28


func build() -> void:
	if App.stage:
		App.stage.set_mode("home")
	var dim := ColorRect.new()
	dim.color = Color(UIKit.NAVY, 0.58)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	move_child(dim, 0)
	var tm := UIKit.touch_min()
	var ready := Social.online_ready()
	# --- header: Back, title, who you are online
	var head := header("Play with Friends")
	back_btn = head.get_child(0) as Button
	head.add_theme_constant_override("separation", 16)
	who_lbl = UIKit.styled("", "caption", UIKit.IVORY_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	who_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	who_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	who_lbl.custom_minimum_size = Vector2(180, 0)
	who_lbl.max_lines_visible = 2
	head.add_child(who_lbl)
	rename_btn = UIKit.quiet("Change name", Vector2(0, tm), UIKit.T_CAPTION)
	rename_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rename_btn.pressed.connect(func() -> void:
		await NameSheet.ask(self)
		_refresh_who())
	head.add_child(rename_btn)
	if not ready:
		_status_card = _gc_card()
		content.add_child(_status_card)
	# --- everything else scrolls under the header (finger swipes anywhere)
	_sc = UIKit.scroll_area()
	_sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sc.follow_focus = true
	# (the bar's room is kept even while it's hidden: the cards never change
	# width when the keyboard makes the list scrollable)
	_sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_RESERVE
	content.add_child(_sc)
	_open_at_top(_sc)
	var v := UIKit.vbox(14)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sc.add_child(v)
	cards = HFlowContainer.new()
	cards.add_theme_constant_override("h_separation", 14)
	cards.add_theme_constant_override("v_separation", 14)
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(cards)
	# Start a party
	var cc := _card(cards, "Start a party", 360.0, 1.0)
	create_btn = UIKit.primary("Create Party", Vector2(0, tm), 28)
	create_btn.disabled = not ready
	create_btn.pressed.connect(_create)
	cc.add_child(create_btn)
	var hint := UIKit.styled("You get a 6-character code to share. Invite Game Center friends from the party." if ready
		else "Needs Game Center (see above).", "caption", UIKit.IVORY_MUTED)
	hint.add_theme_font_size_override("font_size", 19)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cc.add_child(hint)
	# Join with a code: the field and Join share one row and one height
	var jc := _card(cards, "Join with a code", 420.0, 1.15)
	join_row = UIKit.hbox(12)
	jc.add_child(join_row)
	code_edit = LineEdit.new()
	code_edit.placeholder_text = "ACE-347"
	code_edit.max_length = 9    # room for "ABC-DEF" style spacing; parsing is strict
	code_edit.custom_minimum_size = Vector2(220, tm)
	code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_edit.add_theme_font_override("font", UIKit.font_w(700))
	code_edit.add_theme_font_size_override("font_size", CODE_FS)
	code_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	code_edit.editable = ready
	code_edit.accessibility_name = "Party code"
	code_edit.text_changed.connect(_on_code_text)
	code_edit.text_submitted.connect(func(_t: String) -> void: _join())
	join_row.add_child(code_edit)
	# the same height and type size as the field: one centre line, one baseline
	join_btn = UIKit.secondary("Join", Vector2(150, tm), CODE_FS)
	join_btn.disabled = true
	join_btn.pressed.connect(_join)
	join_row.add_child(join_btn)
	# one reserved line for the message, so nothing moves while typing
	code_msg = UIKit.styled("", "caption", UIKit.IVORY_MUTED)
	code_msg.add_theme_font_size_override("font_size", 19)
	code_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	code_msg.custom_minimum_size = Vector2(0, ceilf(UIKit.font_w(500).get_height(19)))
	jc.add_child(code_msg)
	_say("")
	# progress (service and Game Center), with Cancel
	busy_card = UIKit.panel(Color(UIKit.NAVY, 0.8), UIKit.R_CARD, 16)
	var bh := UIKit.hbox(14)
	busy_lbl = UIKit.styled("", "label")
	busy_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	busy_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bh.add_child(busy_lbl)
	var cancel := UIKit.quiet("Cancel", Vector2(150, tm), UIKit.T_LABEL)
	cancel.pressed.connect(_cancel)
	bh.add_child(cancel)
	_busy_cancel = cancel
	busy_card.add_child(bh)
	busy_card.visible = false
	v.add_child(busy_card)
	code_pad = _make_code_pad()
	v.add_child(code_pad)
	# Final: Friends (who's playing right now, invites) - the panel explains
	# its own states (Game Center, permission, status unavailable)
	var fcard := UIKit.panel(Color(UIKit.SLATE, 0.9), UIKit.R_PANEL, 16)
	var frow := UIKit.hbox(16)
	fcard.add_child(frow)
	friends_btn = UIKit.quiet("Friends", Vector2(180, tm), UIKit.T_LABEL)
	friends_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	friends_btn.accessibility_name = "Friends: see who's playing and invite them"
	friends_btn.pressed.connect(func() -> void: FriendsPanel.open(self))
	frow.add_child(friends_btn)
	_friends_hint = UIKit.styled("See which friends are playing and invite them to your party.", "caption", UIKit.IVORY_MUTED)
	_friends_hint.add_theme_font_size_override("font_size", 19)
	_friends_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_friends_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_friends_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_friends_hint.custom_minimum_size = Vector2(200, 0)
	frow.add_child(_friends_hint)
	v.add_child(fcard)
	Controls.device_changed.connect(_on_device)
	_on_device(Controls.device)
	if OS.is_debug_build() and not OS.has_feature("mobile") and not UIKit.emulate_phone():
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
	# room to scroll the code row above an open keyboard (0 while closed)
	_kb_space = Control.new()
	_kb_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_kb_space)
	Social.auth_changed.connect(_on_auth)
	App.party_error.connect(_on_party_error)
	_refresh_who()
	focus_first(create_btn if ready else _first_focus)


## A card with a small overline title; returns its content column.
func _card(parent: Control, title: String, min_w: float, stretch: float) -> VBoxContainer:
	var p := UIKit.panel(Color(UIKit.SLATE, 0.97), UIKit.R_PANEL, 20)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = stretch
	p.custom_minimum_size = Vector2(min_w, 0)
	var col := UIKit.vbox(10)
	col.add_child(UIKit.styled(title, "overline", UIKit.TEAL))
	p.add_child(col)
	parent.add_child(p)
	return col


func _refresh_who() -> void:
	if not is_instance_valid(who_lbl):
		return
	if not Cloud.configured():
		who_lbl.text = "Playing as %s" % Save.player_name()
	elif Cloud.full_name() != "":
		who_lbl.text = "Playing as %s" % Cloud.full_name()
	else:
		who_lbl.text = "Playing as %s · you'll confirm it before your first party" % Save.player_name()


func _gc_card() -> PanelContainer:
	var card := UIKit.panel(Color(UIKit.NAVY, 0.85), UIKit.R_CARD, 16)
	var row := UIKit.hbox(16)
	var msg := ""
	if not Social.available:
		msg = "Online parties use Game Center, on iPhone and iPad. Practice works here."
	elif Social.multiplayer_restricted:
		msg = "Multiplayer is off for this Game Center account (Screen Time). Practice still works."
	elif Social.auth_error != "":
		msg = "Not signed in to Game Center: sign in from the Settings app (Game Center), then come back. Practice works meanwhile."
	else:
		msg = "Signing in to Game Center…"
	var l := UIKit.styled(msg, "caption", UIKit.IVORY)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.custom_minimum_size = Vector2(240, 0)
	row.add_child(l)
	var prac := UIKit.secondary("Go to Practice", Vector2(0, UIKit.touch_min()), UIKit.T_LABEL)
	prac.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prac.pressed.connect(func() -> void: App.goto(PracticeScreen))
	row.add_child(prac)
	_first_focus = prac
	card.add_child(row)
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
		_say("")
		join_btn.disabled = true
		return
	var r := Social.parse_code(up)
	if bool(r["ok"]):
		_say("")
		join_btn.disabled = not Social.online_ready()
	else:
		join_btn.disabled = true
		# while still typing, only flag real mistakes (a wrong character)
		var bad := ""
		for ch in stripped:
			if not Social.CODE_ALPHABET.contains(ch):
				bad = ch
				break
		_say(short_message(String(r["message"])) if bad != "" or stripped.length() > Social.CODE_LEN else "", true)


## The parser's message, first sentence only ("\"B\" isn't used in party
## codes." rather than adding "Check the code and try again.").
static func short_message(m: String) -> String:
	var i := m.find(". ")
	return m.substr(0, i + 1) if i > 0 else m


## The line under the code: a mistake (amber), else what to type (muted).
func _say(text: String, warn: bool = false) -> void:
	if text == "":
		text = HINT if code_edit.editable else ""
		warn = false
	code_msg.text = text
	code_msg.add_theme_color_override("font_color", UIKit.AMBER if warn else UIKit.IVORY_MUTED)


## Make sure the online profile has an approved name (service builds only).
func _ensure_name() -> bool:
	if not Cloud.configured():
		return true
	if Cloud.update_required():
		_on_party_error("This version is too old for online parties. Update Ultimate Trifecta, then try again.", "update_required")
		return false
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
		_say(short_message(String(r["message"])), true)
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
	back_action = _cancel      # Back cancels the request instead of leaving
	UIKit.soft_focus.call_deferred(_busy_cancel)


func _idle() -> void:
	if not is_instance_valid(busy_card):
		return
	busy_card.visible = false
	back_action = Callable()
	create_btn.disabled = not Social.online_ready()
	_on_code_text(code_edit.text)
	if _busy_cancel.has_focus():
		UIKit.soft_focus.call_deferred(create_btn)


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
		"update_required": "Update needed",
	}.get(code, "")
	dialog((title + "\n" if title != "" else "") + message)


## Final: an accepted Friends invite.  The service already re-checked it;
## the join is the same as a typed code (admission, then Game Center
## matchmaking for the code), with this screen's progress, Cancel and error
## messages.  The player agreed to leave any party already.
func join_invited(code: String, who: String) -> void:
	if not Social.online_ready() or not await _ensure_name():
		return
	_op += 1
	var op := _op
	_busy("Joining %s's party…" % who)
	await App.join_room_gamekit(code, true)
	if op == _op and is_inside_tree():
		_idle()


## Controller code pad: the code alphabet as buttons plus Delete.  Shown while
## a controller is in use; the text field then leaves controller focus so it
## can never trap navigation (touch and keyboards type into it as usual).
func _make_code_pad() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 8
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	for ch in Social.CODE_ALPHABET:
		var b := UIKit.quiet(ch, Vector2(62, 62), 26)
		b.pressed.connect(func() -> void: _pad_key(ch))
		g.add_child(b)
	var del := UIKit.quiet("Del", Vector2(0, 62), 20)   # sized to its text
	del.tooltip_text = "Delete"
	del.pressed.connect(func() -> void: _pad_key(""))
	g.add_child(del)
	return g


func _pad_key(ch: String) -> void:
	var cur := code_edit.text.to_upper().replace(" ", "").replace("-", "")
	if ch == "":
		cur = cur.substr(0, maxi(0, cur.length() - 1))
	elif cur.length() < Social.CODE_LEN:
		cur += ch
	code_edit.text = cur
	_on_code_text(cur)
	if cur.length() == Social.CODE_LEN and not join_btn.disabled:
		join_btn.grab_focus()


func _on_device(kind: String) -> void:
	if not is_instance_valid(code_pad):
		return
	var pad := kind == "gamepad" and code_edit.editable
	code_pad.visible = pad
	code_edit.focus_mode = Control.FOCUS_NONE if kind == "gamepad" else Control.FOCUS_ALL
	if pad and code_edit.has_focus():
		(code_pad.get_child(0) as Control).grab_focus()


# ---------------------------------------------------------------- keyboard
## The keyboard's height is read every frame (iOS has no signal for it);
## a change moves things at most once, and only as far as needed.
func _process(_delta: float) -> void:
	if not is_instance_valid(_sc):
		return
	var kb := UIKit.v7_keyboard_height(get_viewport())
	if absf(kb - _kb) < 0.5:
		return
	_kb = kb
	_kb_space.custom_minimum_size.y = kb
	_keep_code_visible()


## Keyboard open with the code field focused: if it would cover the code row
## (field, Join and the message line), scroll the list under the header by
## exactly the overlap (never past the list's top edge).  Closed: scroll
## back to where the list was.  The header and Back never move.
func _keep_code_visible() -> void:
	await get_tree().process_frame     # (the list has re-measured its room)
	if not is_instance_valid(_sc) or not is_inside_tree():
		return
	if _kb <= 0.0:
		if _kb_from >= 0:
			_sc.scroll_vertical = _kb_from
			_kb_from = -1
		return
	if not code_edit.has_focus():
		return
	var limit := get_viewport().get_visible_rect().size.y - _kb - 12.0
	var row := join_row.get_global_rect().merge(code_msg.get_global_rect())
	var over := row.end.y - limit
	var room := row.position.y - (_sc.get_global_rect().position.y + 8.0)
	var by := int(ceilf(minf(over, room)))
	if by <= 0:
		return
	if _kb_from < 0:
		_kb_from = _sc.scroll_vertical
	_sc.scroll_vertical += by


## The rects that must stay usable while the keyboard is open (tests).
func keyboard_report() -> Dictionary:
	return {"keyboard": _kb, "field": code_edit.get_global_rect(), "join": join_btn.get_global_rect(),
		"message": code_msg.get_global_rect(), "back": back_btn.get_global_rect(), "scroll": _sc.scroll_vertical}
