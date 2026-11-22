class_name FriendsPanel
extends Control
## The Friends drawer, opened from Friends on Home, in the party room and on
## Play with Friends.  Less is more: three large actions at the top, then
## only what the chosen one needs.
##   header    Friends, one line on what Invite does here, Close
##   actions   Invite | Join with code | Add friend (always one tap away)
##   waiting   friend requests (Accept / Decline) and party invites (Accept /
##             Decline), when there are any
##   Invite    your friends: Game Center friends and friends added by tag,
##             sorted Online → In a party → In a round → Offline → unknown,
##             then by name.  Each row: an initial disc with a status dot (and
##             the status in words: never colour alone), the name, the
##             status, one action (Invite, "Invited ✓", "Needs update", …).
##             Tap a row for Report, Block and (in-game friends) Remove.
##             States: checking, asking for friends-list access, access off /
##             restricted, Game Center signed out, no Game Center, no friends
##             yet; "Status unavailable" when the game service can't confirm
##             anyone (no green dot is ever guessed).  The party code with
##             Copy and Apple's invite sheet sit under the list.
##   Join      a party code field and Join (the same join as Play with
##             Friends: its progress, Cancel and messages)
##   Add       "Your tag  ComfyFrog#4821  Copy", a friend's tag and Add, the
##             answer in a few words ("No player with that tag",
##             "Already friends", …), and requests you sent ("Requested")
## Status is polled only while this is open (Friends.watch).  It owns input
## while open and releases it on close; Close, Back, a tap outside and
## ui_cancel all close it.  With the keyboard up over a field here, the
## waiting cards and then the three actions fold away (only as far as
## needed) so the field and its button stay above the keyboard.

signal closed

const TABS := ["invite", "join", "add"]
const TAB_TEXT := {"invite": "Invite", "join": "Join with code", "add": "Add friend"}
const TAB_ICON := {"invite": "share", "join": "house", "add": "invite"}
const MAX_CARDS := 2       # waiting cards shown at once on a tablet (a phone: 1; the rest: "+N more")
const FIELD_FS := 26

var panel: PanelContainer
var title_lbl: Label
var sub_lbl: Label
var close_btn: Button
var tiles: HBoxContainer
var tab_btns: Dictionary = {}    # tab -> Button
var tab := "invite"
var invites_box: VBoxContainer   # friend requests + party invites waiting
var more_lbl: Label
# --- Invite
var invite_tab: VBoxContainer
var service_lbl: Label
var scroll: ScrollContainer
var list_box: VBoxContainer
var state_box: VBoxContainer
var state_lbl: Label
var state_btn: Button
var hint_lbl: Label
var footer: Container
var code_lbl: Label
var copy_btn: Button
var gc_btn: Button
var party_card: PanelContainer
var create_btn: Button
var code_title: Label
var code_share_btn: Button
var share_btn: Button
## the Join with code action (party codes are always one tap away)
var play_btn: Button
# --- Join with code
var join_tab: VBoxContainer
var code_edit: LineEdit
var join_btn: Button
var join_msg: Label
# --- Add friend
var add_tab: VBoxContainer
var tag_lbl: Label
var tag_copy_btn: Button
var tag_edit: LineEdit
var add_btn: Button
var add_msg: Label
var sent_box: VBoxContainer
var gc_friends_btn: Button
var _rows: Dictionary = {}       # tid -> Row
var _open_tid := ""
var _note: Label
var _kb := 0.0
var _fold := 0             # keyboard up: 1 = waiting cards folded, 2 = the actions too
var _fold_wait := 0
var _joining := false


static func open(parent: Control) -> FriendsPanel:
	if parent == null or not is_instance_valid(parent) or parent.is_queued_for_deletion():
		return null
	for c in parent.get_children():
		if c is FriendsPanel and not c.is_queued_for_deletion():
			return c
	var d := FriendsPanel.new()
	parent.add_child(d)
	if parent is Screen:
		(parent as Screen).push_modal(d, d.close)
	return d


## The Friends button for a screen's top row, with a count of what is
## waiting (party invites and friend requests); it opens the panel.
static func entry_button(screen: Control) -> Button:
	var b := UIKit.icon_button("invite", "Friends")
	b.name = "FriendsButton"
	b.tooltip_text = "Friends"
	b.accessibility_name = "Friends"
	b.pressed.connect(func() -> void:
		if not is_instance_valid(screen) or not screen.is_inside_tree():
			return
		if screen is Screen and (screen as Screen).has_modal():
			return
		if screen.has_method("close_popover"):
			screen.call("close_popover")
		FriendsPanel.open(screen))
	var dot := PanelContainer.new()
	dot.name = "Badge"
	dot.add_theme_stylebox_override("panel", UIKit.box(UIKit.AMBER, 999, 0, Color.WHITE, 8))
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dl := UIKit.label("", 18, UIKit.NAVY, false, HORIZONTAL_ALIGNMENT_CENTER)
	dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.add_child(dl)
	dot.visible = false
	b.add_child(dot)
	var paint := func() -> void:
		if not is_instance_valid(b) or not is_instance_valid(dot):
			return
		var n := Friends.badge_count()
		dl.text = str(mini(n, 9))
		dot.visible = n > 0
		dot.reset_size()
		dot.position = Vector2(b.size.x - dot.size.x * 0.7, -dot.size.y * 0.3)
		b.accessibility_name = ("Friends, %d waiting" % n) if n > 0 else "Friends"
	# (connected while in the tree, so a re-parented button keeps counting)
	b.tree_entered.connect(func() -> void:
		if not Friends.invites_changed.is_connected(paint):
			Friends.invites_changed.connect(paint)
		paint.call_deferred())
	b.tree_exiting.connect(func() -> void:
		if Friends.invites_changed.is_connected(paint):
			Friends.invites_changed.disconnect(paint))
	b.resized.connect(paint)
	return b


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UIKit.theme()


func _ready() -> void:
	InputOwner.take("friends")
	# (the party room's walk stick lets go of its finger, as for the chat drawer)
	if get_parent() != null:
		for st in get_parent().find_children("*", "HubStick", false, false):
			st.call("release")
	var vs := get_viewport().get_visible_rect().size
	var sm := UIKit.safe_margins(get_viewport())
	var catcher := ColorRect.new()
	catcher.color = Color(UIKit.NAVY, 0.45)
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			close())
	add_child(catcher)
	panel = UIKit.panel(Color(UIKit.SLATE, 0.98), UIKit.R_PANEL, 22)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var w := clampf(vs.x * 0.48, 460.0, 680.0)
	w = minf(w, vs.x - sm.position.x - sm.size.x - 24.0)
	panel.position = Vector2(vs.x - sm.size.x - w - 12.0, sm.position.y + 12.0)
	panel.size = Vector2(w, vs.y - sm.position.y - sm.size.y - 24.0)
	panel.custom_minimum_size = panel.size
	add_child(panel)
	var v := UIKit.vbox(12)
	panel.add_child(v)
	# --- header
	var head := UIKit.hbox(10)
	var hv := UIKit.vbox(0)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl = UIKit.styled("Friends", "title")
	hv.add_child(title_lbl)
	sub_lbl = UIKit.styled("", "caption", UIKit.IVORY_MUTED)
	sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hv.add_child(sub_lbl)
	head.add_child(hv)
	close_btn = UIKit.icon_button("close")
	close_btn.name = "Close"
	close_btn.tooltip_text = "Close Friends"
	close_btn.accessibility_name = "Close Friends"
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_btn.pressed.connect(close)
	head.add_child(close_btn)
	v.add_child(head)
	# --- the three actions
	tiles = UIKit.hbox(10)
	for k in TABS:
		var tb := _tile(String(k))
		tiles.add_child(tb)
		tab_btns[k] = tb
	play_btn = tab_btns["join"]
	v.add_child(tiles)
	# --- what is waiting for you
	invites_box = UIKit.vbox(8)
	v.add_child(invites_box)
	more_lbl = UIKit.styled("", "caption", UIKit.IVORY_MUTED)
	more_lbl.visible = false
	v.add_child(more_lbl)
	_build_invite(v)
	_build_join(v)
	_build_add(v)
	_note = UIKit.styled("", "caption", UIKit.AMBER)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.visible = false
	v.add_child(_note)
	Friends.changed.connect(_refresh)
	Friends.invites_changed.connect(_refresh)
	Friends.watch(true)
	show_tab("invite")
	if not UIKit.reduced_motion():
		panel.modulate.a = 0.0
		Motion.animate(panel, "modulate:a", 1.0, UIKit.T_FAST)
	if Controls.device != "touch":
		UIKit.soft_focus.call_deferred(close_btn)


## One large action: an icon over its name, a full touch target.
func _tile(k: String) -> Button:
	var b := UIKit.card_button(Vector2(0, maxf(88.0, UIKit.touch_min() + 10.0)), Color(UIKit.NAVY, 0.55))
	b.name = "Tab_" + k
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_stretch_ratio = 1.0
	b.accessibility_name = String(TAB_TEXT[k])
	b.tooltip_text = String(TAB_TEXT[k])
	var tv := UIKit.vbox(2)
	tv.set_anchors_preset(Control.PRESET_FULL_RECT)
	tv.offset_left = 6
	tv.offset_right = -6
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.face_of(b).add_child(tv)
	var g := Glyph.new()
	g.icon = String(TAB_ICON[k])
	g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tv.add_child(g)
	var l := UIKit.styled(String(TAB_TEXT[k]), "label", UIKit.IVORY, HORIZONTAL_ALIGNMENT_CENTER)
	l.name = "Caption"
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.custom_minimum_size = Vector2(40, 0)
	UIKit.fit_text(l, [UIKit.T_LABEL, UIKit.T_CAPTION, 18, 16])
	tv.add_child(l)
	b.pressed.connect(func() -> void: show_tab(k))
	return b


func _build_invite(v: VBoxContainer) -> void:
	invite_tab = UIKit.vbox(10)
	invite_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(invite_tab)
	# (build 31) the party first: not in one yet, "Create party" (your own
	# lobby with a code, no Apple screen); in one, its code to share
	party_card = PanelContainer.new()
	party_card.name = "PartyCard"
	party_card.add_theme_stylebox_override("panel", UIKit.box(Color(UIKit.NAVY, 0.55), UIKit.R_CARD, 1, Color(UIKit.AMBER, 0.35), 12))
	var pr := UIKit.hbox(10)
	party_card.add_child(pr)
	create_btn = UIKit.primary("Create party", Vector2(0, UIKit.touch_min()), UIKit.T_LABEL)
	create_btn.name = "CreateParty"
	create_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_btn.pressed.connect(_create_party)
	pr.add_child(create_btn)
	code_title = UIKit.styled("Party code", "caption", UIKit.IVORY_MUTED)
	code_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pr.add_child(code_title)
	code_lbl = UIKit.styled("", "num", UIKit.AMBER)
	code_lbl.add_theme_font_override("font", UIKit.font_num(800))
	code_lbl.add_theme_font_size_override("font_size", 30)
	code_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	code_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pr.add_child(code_lbl)
	copy_btn = UIKit.quiet("Copy", Vector2(0, UIKit.touch_min()), UIKit.T_CAPTION)
	copy_btn.accessibility_name = "Copy party code"
	copy_btn.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(App.party_code)
		_say("Code %s copied" % App.party_code))
	pr.add_child(copy_btn)
	code_share_btn = UIKit.quiet("Share", Vector2(0, UIKit.touch_min()), UIKit.T_CAPTION)
	code_share_btn.accessibility_name = "Share party code"
	code_share_btn.pressed.connect(func() -> void:
		if not Share.share_text(Share.party_message(App.party_code)):
			DisplayServer.clipboard_set(Share.party_message(App.party_code))
			_say("Invite message copied: paste it to a friend"))
	pr.add_child(code_share_btn)
	invite_tab.add_child(party_card)
	# one restrained line about status when it can't be confirmed
	service_lbl = UIKit.styled("", "caption", UIKit.AMBER)
	service_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	invite_tab.add_child(service_lbl)
	scroll = UIKit.scroll_area()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	invite_tab.add_child(scroll)
	var inner := UIKit.vbox(8)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)
	state_box = UIKit.vbox(12)
	state_lbl = UIKit.styled("", "body", UIKit.IVORY)
	state_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	state_box.add_child(state_lbl)
	state_btn = UIKit.secondary("Try again", Vector2(0, UIKit.touch_min()), UIKit.T_LABEL)
	state_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	state_btn.pressed.connect(func() -> void: Friends.refresh())
	state_box.add_child(state_btn)
	inner.add_child(state_box)
	list_box = UIKit.vbox(8)
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(list_box)
	hint_lbl = UIKit.styled("", "caption", UIKit.IVORY_MUTED)
	hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(hint_lbl)
	# "Show when I'm playing" is a setting: it sits at the end of the list
	share_btn = UIKit.quiet("", Vector2(0, UIKit.touch_min()), UIKit.T_CAPTION)
	share_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	share_btn.pressed.connect(func() -> void: Friends.set_share_status(not Friends.share_status()))
	inner.add_child(share_btn)
	# the ways that never need status: the code, Apple's sheet
	var foot := HFlowContainer.new()
	foot.add_theme_constant_override("h_separation", 8)
	foot.add_theme_constant_override("v_separation", 8)
	footer = foot
	# (build 31) no Apple invite screen from here: Invite is the party's code
	# and the friends list below
	gc_btn = UIKit.quiet("Invite with Game Center", Vector2(0, UIKit.touch_min()), UIKit.T_CAPTION)
	gc_btn.visible = false
	foot.add_child(gc_btn)
	foot.visible = false
	invite_tab.add_child(foot)


func _field(placeholder: String, label: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.accessibility_name = label
	e.custom_minimum_size = Vector2(160, UIKit.touch_min())
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.add_theme_font_size_override("font_size", FIELD_FS)
	e.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	e.select_all_on_focus = true
	e.context_menu_enabled = true
	return e


func _build_join(v: VBoxContainer) -> void:
	join_tab = UIKit.vbox(10)
	v.add_child(join_tab)
	var row := UIKit.hbox(10)
	code_edit = _field("ACE-347", "Party code")
	code_edit.max_length = 9    # (room for "ABC-DEF"; parsing is strict)
	code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_edit.add_theme_font_override("font", UIKit.font_w(700))
	code_edit.text_changed.connect(func(t: String) -> void:
		var up := t.to_upper()
		if up != t:
			var c := code_edit.caret_column
			code_edit.text = up
			code_edit.caret_column = c
		_join_say(""))
	code_edit.text_submitted.connect(func(_t: String) -> void: _join())
	row.add_child(code_edit)
	join_btn = UIKit.primary("Join", Vector2(140, UIKit.touch_min()), UIKit.T_LABEL + 2)
	join_btn.pressed.connect(_join)
	row.add_child(join_btn)
	join_tab.add_child(row)
	join_msg = UIKit.styled("", "caption", UIKit.IVORY_MUTED)
	join_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	join_tab.add_child(join_msg)


func _build_add(v: VBoxContainer) -> void:
	add_tab = UIKit.vbox(10)
	add_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(add_tab)
	# your own tag, to give to a friend
	var mine := UIKit.hbox(10)
	var cap := UIKit.styled("Your tag", "caption", UIKit.IVORY_MUTED)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mine.add_child(cap)
	tag_lbl = UIKit.styled("", "label", UIKit.AMBER)
	tag_lbl.add_theme_font_override("font", UIKit.font_w(800))
	tag_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag_lbl.custom_minimum_size = Vector2(60, 0)
	UIKit.fit_text(tag_lbl, [UIKit.T_LABEL, UIKit.T_CAPTION, 18])
	mine.add_child(tag_lbl)
	tag_copy_btn = UIKit.quiet("Copy", Vector2(0, UIKit.touch_min()), UIKit.T_CAPTION)
	tag_copy_btn.accessibility_name = "Copy your tag"
	tag_copy_btn.pressed.connect(func() -> void:
		if Friends.my_tag == "":
			return
		DisplayServer.clipboard_set(Friends.my_tag)
		_add_say("Your tag is copied. Send it to a friend.", false))
	mine.add_child(tag_copy_btn)
	add_tab.add_child(mine)
	var row := UIKit.hbox(10)
	tag_edit = _field("Name#1234", "Friend's tag")
	tag_edit.max_length = 24
	tag_edit.text_changed.connect(func(_t: String) -> void: _add_say("", false))
	tag_edit.text_submitted.connect(func(_t: String) -> void: _add())
	row.add_child(tag_edit)
	add_btn = UIKit.primary("Add", Vector2(140, UIKit.touch_min()), UIKit.T_LABEL + 2)
	add_btn.pressed.connect(_add)
	row.add_child(add_btn)
	add_tab.add_child(row)
	add_msg = UIKit.styled("", "caption", UIKit.IVORY_MUTED)
	add_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_tab.add_child(add_msg)
	# requests you sent: "Requested"
	var sc := UIKit.scroll_area()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_tab.add_child(sc)
	var inner := UIKit.vbox(8)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(inner)
	sent_box = UIKit.vbox(8)
	sent_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(sent_box)
	# (2.2) Apple's Friends screen: Game Center friends by nickname
	gc_friends_btn = UIKit.quiet("Game Center friends", Vector2(0, UIKit.touch_min()), UIKit.T_CAPTION)
	gc_friends_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	gc_friends_btn.tooltip_text = "Add friends by their Game Center name"
	gc_friends_btn.pressed.connect(func() -> void:
		if not Social.show_friends_list():
			_add_say("Sign in to Game Center to see Game Center friends.", true))
	inner.add_child(gc_friends_btn)


func _exit_tree() -> void:
	InputOwner.release("friends")
	Friends.watch(false)
	if Friends.changed.is_connected(_refresh):
		Friends.changed.disconnect(_refresh)
	if Friends.invites_changed.is_connected(_refresh):
		Friends.invites_changed.disconnect(_refresh)


func close() -> void:
	if is_queued_for_deletion():
		return
	TouchScroll.release_all(self, null)
	for e in [code_edit, tag_edit]:
		if is_instance_valid(e) and (e as LineEdit).has_focus():
			(e as LineEdit).release_focus()     # (the keyboard goes with the panel)
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _say(t: String) -> void:
	_note.text = t
	_note.visible = t != ""


## The line under a field: the answer to the last try (until the text or the
## tab changes), else why it can't be used now (amber), else a hint.
var _join_note := ["", false]
var _add_note := ["", false]


func _join_say(t: String, warn: bool = true) -> void:
	_join_note = [t, warn]
	_paint_msg(join_msg, _join_note, _join_why(), _join_hint())


func _add_say(t: String, warn: bool) -> void:
	_add_note = [t, warn]
	_paint_msg(add_msg, _add_note, _add_why(), _add_hint())


func _paint_msg(l: Label, note: Array, why: String, hint: String) -> void:
	var warn := true
	var text := String(note[0])
	if text != "":
		warn = bool(note[1])
	elif why != "":
		text = why
	else:
		text = hint
		warn = false
	l.text = text
	l.add_theme_color_override("font_color", UIKit.AMBER if warn else UIKit.IVORY_MUTED)


func _join_why() -> String:
	return "" if Social.online_ready() else "Sign in to Game Center to join a party."


func _join_hint() -> String:
	return "Your party code: %s" % App.party_code if Friends.in_party() else "Ask the host for their party code."


func _add_why() -> String:
	if not Social.online_ready() or Friends.tags == "signed_out":
		return "Sign in to Game Center to add friends."
	if not Friends.tags_on() or Friends.tags == "off":
		return "Adding friends isn't available right now."
	if Friends.tags in ["unavailable", "network", "suspended"]:
		return Friends.tags_message if Friends.tags_message != "" else "Adding friends isn't available right now."
	return ""


func _add_hint() -> String:
	return "Ask your friend for their tag." if Friends.tags == "ok" and Friends.my_tag != "" else ""


# ---------------------------------------------------------------- actions
## invite | join | add
func show_tab(k: String) -> void:
	if not k in TABS:
		return
	tab = k
	for t in TABS:
		UIKit.set_selected(tab_btns[t], t == k)
		(tab_btns[t] as Button).accessibility_name = String(TAB_TEXT[t]) + (", selected" if t == k else "")
	invite_tab.visible = k == "invite"
	join_tab.visible = k == "join"
	add_tab.visible = k == "add"
	_say("")
	if k == "join":
		_join_say("")
	elif k == "add":
		_add_say("", false)
		if Friends.tags_on() and Friends.tags != "loading":
			Friends.load_tags()
	_refresh()


func _join() -> void:
	if _joining or is_queued_for_deletion():
		return
	code_edit.release_focus()
	var typed := code_edit.text
	var r := Social.parse_code(typed)
	if not bool(r["ok"]):
		_join_say(OnlineScreen.short_message(String(r["message"])))
		return
	if not Social.online_ready():
		_join_say("Sign in to Game Center to join a party.")
		return
	if String(r["code"]) == App.party_code and Friends.in_party():
		_join_say("You're already in this party.")
		return
	# (one join per tap: the panel closes as Play with Friends takes over)
	_joining = true
	close()
	var res: Dictionary = Friends.join_code(typed)
	if not bool(res.get("ok", false)) and App.screen is Control:
		UIKit.toast(App.screen as Control, String(res.get("message", "Check the code and try again.")), 3.0)


func _add() -> void:
	if Friends.adding:
		return
	var typed := tag_edit.text
	var r: Dictionary = await Friends.add_friend(typed)
	if not is_inside_tree():
		return
	if bool(r.get("busy", false)):
		return
	if bool(r.get("ok", false)):
		tag_edit.text = ""
		tag_edit.release_focus()
		_add_say(String(r.get("message", "")), false)
	else:
		_add_say(String(r.get("message", "")), true)
	_refresh()


# ---------------------------------------------------------------- states
## loading | unavailable | signed_out | multiplayer_off | not_determined |
## denied | restricted | error | empty | list  (tests and captures)
func state_name() -> String:
	if not sorted_models().is_empty():
		return "list"
	match Friends.access:
		"unknown", "checking":
			return "loading"
		"unavailable", "signed_out", "multiplayer_off", "not_determined", "denied", "restricted", "error":
			return Friends.access
		"authorized":
			return "loading" if Friends.loading_friends else "empty"
	return "loading"


const STATE_TEXT := {
	"loading": "Loading your friends…",
	"unavailable": "Game Center friends show on iPhone and iPad. Add friends by tag, or share a party code.",
	"signed_out": "Sign in to Game Center in the Settings app to see your friends and add friends.",
	"multiplayer_off": "Multiplayer is off for this Game Center account (Screen Time). Practice still works.",
	"not_determined": "Allow Ultimate Trifecta to see your Game Center friends to find who's playing.",
	"denied": "Friends list access is off. Turn it on in the Settings app (Game Center › Friends List). Party codes still work.",
	"restricted": "Friends list access is restricted on this device (Screen Time). Party codes still work.",
	"error": "Couldn't load your Game Center friends.",
	"empty": "No friends yet. Tap Add friend, or share your party code.",
}


func service_text() -> String:
	if state_name() != "list":
		return ""
	match Friends.service:
		"ok":
			return ""
		"loading", "idle":
			return "Checking who's playing…"
		"off":
			# (2.3) no game service: invites go through Game Center, rows say so
			return "" if Friends.can_gc_invite() else "Status unavailable right now. You can still invite with a party code."
		"network":
			return "Can't reach the game service, so status is unavailable. Check your connection."
		"signed_out":
			return "Sign in to see who's playing (status unavailable)."
		"suspended":
			return Friends.service_message if Friends.service_message != "" else "Online play is paused for this account."
	return "Status unavailable right now."


func _refresh() -> void:
	if not is_instance_valid(list_box) or is_queued_for_deletion():
		return
	var st := state_name()
	var in_party := Friends.in_party()
	sub_lbl.text = {"invite": "Share the code, or invite a friend." if in_party else "Create a party, then share its code.",
		"join": "Join a friend's party with its code.", "add": "Add friends by their tag."}[tab]
	state_box.visible = st != "list"
	state_lbl.text = String(STATE_TEXT.get(st, ""))
	state_btn.visible = st in ["error", "not_determined"]
	state_btn.text = "Allow friends list" if st == "not_determined" else "Try again"
	service_lbl.text = service_text()
	service_lbl.visible = service_lbl.text != ""
	hint_lbl.text = _list_hint(st)
	hint_lbl.visible = hint_lbl.text != ""
	_paint_waiting()
	_paint_rows(st == "list")
	# the party card: Create party, or the code to share
	create_btn.visible = not in_party
	for c in [code_title, code_lbl, copy_btn, code_share_btn]:
		(c as Control).visible = in_party
	code_lbl.text = App.party_code if in_party else ""
	gc_btn.visible = false
	footer.visible = false
	share_btn.visible = (Friends.access == "authorized" or Friends.has_tag_friends()) and Friends.feature_on()
	share_btn.text = "Show when I'm playing: %s" % ("On" if Friends.share_status() else "Off")
	share_btn.accessibility_name = share_btn.text
	_paint_add()
	_paint_msg(join_msg, _join_note, _join_why(), _join_hint())
	join_btn.disabled = _joining


## Under a list: what the dots mean, or why Game Center friends are missing.
func _list_hint(st: String) -> String:
	if st != "list":
		return ""
	if Friends.access in ["denied", "restricted", "signed_out", "not_determined", "error"]:
		return "Game Center friends aren't shown (friends list access is off)."
	return "Status shows for friends who also play Ultimate Trifecta." if Friends.service == "ok" else ""


func _paint_add() -> void:
	var t := Friends.my_tag
	if t != "":
		tag_lbl.text = t
	elif Friends.needs_name or (Cloud.signed_in() and bool(Cloud.profile.get("needs_name", false))):
		tag_lbl.text = "Choose a name first"
	elif Friends.tags in ["loading", "idle"]:
		tag_lbl.text = "…"
	elif Friends.tags == "signed_out" or not Social.online_ready():
		tag_lbl.text = "Sign in to Game Center"
	else:
		tag_lbl.text = "Unavailable"
	tag_copy_btn.visible = t != ""
	# (an unavailable service can still be tried again: only no sign-in stops it)
	var can := Friends.tags_on() and Friends.tags not in ["signed_out", "off"] and Social.online_ready()
	add_btn.disabled = Friends.adding or not can
	add_btn.text = "Adding…" if Friends.adding else "Add"
	tag_edit.editable = can and not Friends.adding
	_paint_msg(add_msg, _add_note, _add_why(), _add_hint())
	gc_friends_btn.visible = Social.online_ready()
	# "Requested": the requests you sent
	for c in sent_box.get_children():
		c.queue_free()
	if not Friends.requests_out.is_empty():
		var h := UIKit.styled("Sent", "overline", UIKit.IVORY_MUTED)
		sent_box.add_child(h)
	for rq in Friends.requests_out:
		sent_box.add_child(_sent_row(rq))


func _sent_row(rq: Dictionary) -> Control:
	var who: Dictionary = rq.get("to", {})
	var h := UIKit.hbox(10)
	h.custom_minimum_size = Vector2(0, 52)
	var nv := UIKit.vbox(0)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var n := UIKit.styled(person_name(who), "label")
	n.custom_minimum_size = Vector2(60, 0)
	UIKit.fit_text(n, [UIKit.T_LABEL, UIKit.T_CAPTION, 18])
	nv.add_child(n)
	if who.get("tag") is String:
		var tg := UIKit.styled(String(who["tag"]), "caption", UIKit.IVORY_MUTED)
		tg.clip_text = true
		tg.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		tg.custom_minimum_size = Vector2(60, 0)
		nv.add_child(tg)
	h.add_child(nv)
	var chip := UIKit.styled("Requested", "caption", UIKit.TEAL, HORIZONTAL_ALIGNMENT_RIGHT)
	chip.name = "Requested"
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(chip)
	return h


static func person_name(p: Dictionary) -> String:
	if p.get("name") is String and String(p["name"]) != "":
		return NameRules.safe_display(String(p["name"]))
	return "A player"


## (build 31) Your own party: a lobby with a code friends can join with
## (from the Friends autoload, which reopens this panel in the new lobby).
func _create_party() -> void:
	_say("")
	create_btn.disabled = true
	close()
	var r: Dictionary = await Friends.create_party()
	if not bool(r.get("ok", false)) and App.screen is Control:
		UIKit.toast(App.screen as Control, String(r.get("message", "Couldn't start a party. Try again.")), 3.0)


## Apple's invite sheet works for the host of a Game Center party.
func can_game_center() -> bool:
	var s: Variant = App.session
	if Social.online_ready() and App.is_solo_party():
		return true   # (2.2) the home party opens online first
	return Social.online_ready() and s != null and is_instance_valid(s) and (s as NetSession).is_host() \
		and (s as NetSession).transport is GameKitTransport


## (Crash sweep) Apple's sheet opens from the Friends autoload: this panel
## closes first, and a coroutine on a freed panel never resumes (from Home
## the sheet never opened).  One sheet at a time (Social guards it).
func _game_center_invite(recipients: Array) -> void:
	if not can_game_center():
		return
	close()
	Friends.open_gc_sheet(recipients)


# ---------------------------------------------------------------- waiting
## Friend requests first, then party invites; at most MAX_CARDS cards (the
## rest is a count, and the Invite list / Add friend show everything).
func _paint_waiting() -> void:
	for c in invites_box.get_children():
		c.queue_free()
	var cards: Array = []
	for rq in Friends.requests_in:
		cards.append(["request", rq])
	for iv in Friends.incoming:
		cards.append(["invite", iv])
	var folded := _fold >= 1
	var most := max_cards()
	for i in mini(cards.size(), most):
		var c: Array = cards[i]
		invites_box.add_child(_request_card(c[1]) if String(c[0]) == "request" else _invite_card(c[1]))
	invites_box.visible = not cards.is_empty() and not folded
	var more := cards.size() - most
	more_lbl.text = "+%d more waiting" % more if more > 0 else ""
	more_lbl.visible = more > 0 and not folded


## Waiting cards shown at once: one on a phone (the list keeps its room),
## MAX_CARDS on a tablet.
func max_cards() -> int:
	var tall_pt := get_viewport().get_visible_rect().size.y / UIKit.units_per_point()
	return MAX_CARDS if tall_pt >= 600.0 else 1


func _card_shell(title: String, sub: String) -> Array:
	var p := UIKit.panel(Color(UIKit.SLATE_HI, 0.95), UIKit.R_CARD, 12)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 8)
	var tv := UIKit.vbox(0)
	tv.custom_minimum_size = Vector2(220, 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var a := UIKit.styled(title, "label")
	a.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(a)
	var b := UIKit.styled(sub, "caption", UIKit.IVORY_MUTED)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(b)
	row.add_child(tv)
	p.add_child(row)
	return [p, row]


func _request_card(rq: Dictionary) -> Control:
	var from: Dictionary = rq.get("from", {})
	var shell := _card_shell("%s wants to be friends" % person_name(from), String(from.get("tag", "")) if from.get("tag") is String else "")
	var p: Control = shell[0]
	p.name = "Request"
	var row: HFlowContainer = shell[1]
	var id := String(rq.get("id", ""))
	var busy := Friends.answering.has(id)
	var dec := UIKit.quiet("Decline", Vector2(0, UIKit.touch_min()), UIKit.T_CAPTION)
	dec.disabled = busy
	dec.pressed.connect(func() -> void: _answer(rq, false))
	row.add_child(dec)
	var acc := UIKit.secondary("Accept", Vector2(0, UIKit.touch_min()), UIKit.T_CAPTION)
	acc.disabled = busy
	acc.pressed.connect(func() -> void: _answer(rq, true))
	row.add_child(acc)
	return p


func _answer(rq: Dictionary, yes: bool) -> void:
	var r: Dictionary = await Friends.answer_request(rq, yes)
	if not is_inside_tree():
		return
	if String(r.get("message", "")) != "":
		_say(String(r["message"]))


func _invite_card(iv: Dictionary) -> Control:
	var t := Friends.invite_text(iv)
	var left := maxi(0, int((float(iv.get("expires_at", 0)) - Friends.server_now_ms()) / 1000.0))
	var shell := _card_shell(String(t[0]), "%s · %d:%02d left" % [t[1], left / 60, left % 60])
	var p: Control = shell[0]
	p.name = "Invite"
	var row: HFlowContainer = shell[1]
	var later := Friends.accepting == String(iv["id"]) or not Friends.can_show_invites()
	var dec := UIKit.quiet("Decline", Vector2(0, UIKit.touch_min()), UIKit.T_CAPTION)
	dec.pressed.connect(func() -> void: Friends.decline(iv))
	row.add_child(dec)
	var acc := UIKit.secondary("Joining…" if Friends.accepting == String(iv["id"]) else "Accept", Vector2(0, UIKit.touch_min()), UIKit.T_CAPTION)
	acc.disabled = later
	acc.pressed.connect(func() -> void:
		close()
		Friends.accept(iv))
	row.add_child(acc)
	return p


# ---------------------------------------------------------------- keyboard
func _typing() -> bool:
	return _kb > 0.0 and ((is_instance_valid(code_edit) and code_edit.has_focus()) or (is_instance_valid(tag_edit) and tag_edit.has_focus()))


## The on-screen keyboard's height is read every frame (iOS has no signal);
## while it covers the field being typed in (or its button), the waiting
## cards fold away, then the three actions, one step a frame and only as far
## as needed.  Everything comes back when the keyboard goes.
func _process(_delta: float) -> void:
	var focused := (is_instance_valid(code_edit) and code_edit.has_focus()) or (is_instance_valid(tag_edit) and tag_edit.has_focus())
	_kb = UIKit.v7_keyboard_height(get_viewport()) if focused else 0.0
	if not _typing():
		if _fold > 0:
			_set_fold(0)
		return
	if _fold_wait > 0:
		_fold_wait -= 1
		return
	var r := keyboard_report()
	var limit := get_viewport().get_visible_rect().size.y - _kb - 8.0
	if maxf((r["field"] as Rect2).end.y, (r["button"] as Rect2).end.y) > limit and _fold < 2:
		_set_fold(_fold + 1)


func _set_fold(n: int) -> void:
	_fold = n
	_fold_wait = 2      # (the layout settles before the next look)
	sub_lbl.visible = n == 0
	tiles.visible = n < 2
	_paint_waiting()


## The rects that must stay usable while the keyboard is open (tests).
func keyboard_report() -> Dictionary:
	var e: LineEdit = code_edit if tab == "join" else tag_edit
	var b: Button = join_btn if tab == "join" else add_btn
	return {"keyboard": _kb, "field": e.get_global_rect(), "button": b.get_global_rect(), "typing": _typing()}


# ---------------------------------------------------------------- rows
const RANK := {"online": 0, "lobby": 1, "match": 2, "offline": 3, "unknown": 4, "unavailable": 4}


## The row model for one friend: {tid, name, gc_name, status, label,
## action, p (service entry or null), player, pid, kind (gc | tag)}.
static func model(f: Dictionary) -> Dictionary:
	var tid := String(f["tid"])
	var kind := String(f.get("kind", "gc"))
	var p: Variant = Friends.presence.get(tid)
	var gc := gc_display(String(f.get("name", ""))) if kind == "gc" else ""
	var name := gc if kind == "gc" else person_name(f)
	var status := "unavailable" if Friends.service != "ok" else "unknown"
	var label := "Status unavailable" if Friends.service != "ok" else "Status unknown"
	var action := ""
	if p is Dictionary:
		var pd: Dictionary = p
		if pd.get("name") is String and String(pd["name"]) != "":
			name = NameRules.safe_display(String(pd["name"]))
		status = String(pd.get("status", "offline"))
		label = {"online": "Online", "lobby": "In a party", "match": "In a round", "offline": "Offline"}.get(status, "Offline")
		if bool(pd.get("in_your_party", false)):
			action = "in_party"
			label = "In your party"
		elif Friends.sent.has(tid) or bool(pd.get("invited", false)):
			action = "invited"
		elif Friends.sending.has(tid):
			action = "sending"
		elif bool(pd.get("can_invite", false)):
			action = "invite"
		else:
			action = {"update": "update", "party_full": "full", "party_busy": "busy"}.get(String(pd.get("why", "")), "")
		if String(pd.get("source", "")) in ["tag", "both"]:
			kind = "tag" if kind == "tag" or String(pd.get("source", "")) == "tag" else "both"
	# (2.3) no game service needed: invite straight through Game Center
	if action == "" and f.get("player") is Object and Friends.can_gc_invite():
		action = {"sent": "gc_sent", "accepted": "gc_joining", "declined": "gc_declined"}.get(Friends.gc_state(tid), "gc_invite")
	if not (p is Dictionary) and Friends.service != "ok" and kind == "gc":
		label = "Game Center friend"
	var pid := String((p as Dictionary).get("profile_id", "")) if p is Dictionary else String(f.get("profile_id", ""))
	return {"tid": tid, "name": name, "gc_name": gc, "status": status, "label": label, "action": action, "p": p,
		"player": f.get("player"), "pid": pid, "kind": kind}


## Everyone on the Invite list: Game Center friends, friends added by tag
## that status lists, and friends added by tag it doesn't (yet).
static func friend_entries() -> Array:
	var out: Array = []
	var seen := {}
	for f in Friends.friends:
		out.append(f)
		seen[String(f.get("tid", ""))] = true
	for tid in Friends.presence.keys():
		var e: Dictionary = Friends.presence[tid]
		if seen.has(tid) or not String(e.get("source", "")) in ["tag", "both"]:
			continue
		seen[tid] = true
		out.append({"tid": String(tid), "name": e.get("name"), "tag": e.get("tag"), "player": null, "kind": "tag",
			"profile_id": String(e.get("profile_id", ""))})
	for f in Friends.tag_friends_without_status():
		out.append({"tid": "pid:" + String(f.get("profile_id", "")), "name": f.get("name"), "tag": f.get("tag"), "player": null,
			"kind": "tag", "profile_id": String(f.get("profile_id", ""))})
	return out


## Online → In a party → In a round → Offline → unknown, then by name.
static func sorted_models() -> Array:
	var out: Array = []
	for f in friend_entries():
		out.append(model(f))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := int(RANK.get(a["status"], 4))
		var rb := int(RANK.get(b["status"], 4))
		if ra != rb:
			return ra < rb
		var na := String(a["name"]).to_lower()
		var nb := String(b["name"]).to_lower()
		if na != nb:
			return na < nb
		return String(a["tid"]) < String(b["tid"]))
	return out


## A Game Center nickname for this player's own list: shown as Apple gives
## it (accents and emoji included) unless the game's abuse lists flag it.
static func gc_display(raw: String) -> String:
	var n := NameRules.normalize(raw)
	if n.length() > 24:
		n = n.substr(0, 23) + "…"
	if n == "":
		return "Game Center friend"
	if NameRules.display_ok(n):
		return n
	var probe := ""
	for ch in n:
		var c := ch.unicode_at(0)
		probe += ch if (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 32 else " "
	probe = NameRules.normalize(probe)
	if probe.length() >= 3:
		var m := NameRules.moderate(probe.substr(0, 16), [], false)
		# (shape reasons only mean "not a name the game itself would issue")
		if not bool(m["ok"]) and not String(m.get("reason", "")) in ["length", "characters", "spacing", "letters"]:
			return "Game Center friend"
	return n


func _paint_rows(show: bool) -> void:
	list_box.visible = show
	if not show:
		for tid in _rows.keys():
			(_rows[tid] as Row).queue_free()
		_rows.clear()
		return
	var models := sorted_models()
	var keep := {}
	for i in models.size():
		var m: Dictionary = models[i]
		var tid := String(m["tid"])
		keep[tid] = true
		var row: Row = _rows.get(tid)
		if row == null or not is_instance_valid(row):
			row = Row.new()
			row.panel = self
			list_box.add_child(row)
			_rows[tid] = row
		row.show_model(m, tid == _open_tid)
		if row.get_index() != i:
			list_box.move_child(row, i)
	for tid in _rows.keys():
		if not keep.has(tid):
			(_rows[tid] as Row).queue_free()
			_rows.erase(tid)


func rows_in_order() -> Array:
	var out: Array = []
	for c in list_box.get_children():
		if c is Row and not c.is_queued_for_deletion():
			out.append(c)
	return out


func _toggle(tid: String) -> void:
	_open_tid = "" if _open_tid == tid else tid
	_refresh()


func _invite(tid: String) -> void:
	_say("")
	var r: Dictionary = await Friends.invite(tid)
	if not is_inside_tree():
		return
	if not bool(r.get("ok", false)) and not bool(r.get("busy", false)):
		_say(Cloud.explain(r))


## (2.3) An in-game invite through Game Center (no service needed).
func _invite_gc(tid: String) -> void:
	_say("")
	var r: Dictionary = await Friends.invite_gc(tid)
	if not is_inside_tree():
		return
	if not bool(r.get("ok", false)):
		_say(String(r.get("message", "Couldn't send the invite.")))


func _report(m: Dictionary) -> void:
	ReportSheet.open(self, {"kind": "player", "name": String(m["name"]), "pid": String(m.get("pid", "")),
		"context": {"room_code": App.party_code, "build": App.build_number()}})


func _block(m: Dictionary) -> void:
	var e := {"pid": String(m.get("pid", "")), "uid": "", "name": String(m["name"])}
	var note: String = await SocialActions.block(null, e)
	if is_inside_tree():
		_say(note)
		_open_tid = ""
		Friends.refresh()


func _remove(m: Dictionary) -> void:
	var r: Dictionary = await Friends.remove_friend(String(m.get("pid", "")))
	if is_inside_tree():
		_open_tid = ""
		_say("%s was removed from your friends." % String(m["name"]) if bool(r.get("ok", false)) else String(r.get("message", "")))
		_refresh()


## One friend: the card (disc, name, status, action) and, when tapped, its
## actions.  Updated in place; nothing is rebuilt on a status poll.
class Row:
	extends VBoxContainer
	var panel: FriendsPanel
	var card: Button
	var disc: Disc
	var name_l: Label
	var status_l: Label
	var action_btn: Button
	var chip: Label
	var actions: HFlowContainer
	var model: Dictionary = {}

	func _init() -> void:
		add_theme_constant_override("separation", 6)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card = UIKit.card_button(Vector2(0, maxf(72.0, UIKit.touch_min() + 12.0)), Color(UIKit.NAVY, 0.5))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var h := UIKit.hbox(10)
		h.set_anchors_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 10
		h.offset_right = -10
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UIKit.face_of(card).add_child(h)
		disc = Disc.new()
		disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(disc)
		var v := UIKit.vbox(0)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(v)
		name_l = UIKit.styled("", "label")
		name_l.custom_minimum_size = Vector2(60, 0)
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_l.clip_text = true
		UIKit.fit_text(name_l, [UIKit.T_LABEL, UIKit.T_CAPTION, 18])
		v.add_child(name_l)
		status_l = UIKit.styled("", "caption", UIKit.IVORY_MUTED)
		status_l.add_theme_font_size_override("font_size", 18)
		status_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		status_l.clip_text = true
		status_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(status_l)
		chip = UIKit.styled("", "caption", UIKit.TEAL, HORIZONTAL_ALIGNMENT_RIGHT)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(chip)
		action_btn = UIKit.secondary("Invite", Vector2(130, UIKit.touch_min()), UIKit.T_CAPTION)
		action_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		action_btn.pressed.connect(func() -> void:
			if panel == null or not is_instance_valid(panel):
				return
			var a := String(model.get("action", ""))
			if a == "invite":
				panel._invite(String(model["tid"]))
			elif a == "gc_invite":
				panel._invite_gc(String(model["tid"])))
		# (the action sits over the card: it takes its own taps)
		h.add_child(action_btn)
		card.pressed.connect(func() -> void:
			if panel != null and is_instance_valid(panel):
				panel._toggle(String(model["tid"])))
		add_child(card)
		actions = HFlowContainer.new()
		actions.add_theme_constant_override("h_separation", 8)
		actions.add_theme_constant_override("v_separation", 8)
		actions.visible = false
		add_child(actions)

	func show_model(m: Dictionary, open: bool) -> void:
		var changed_actions: bool = open != actions.visible or m.get("p") != model.get("p")
		model = m
		name_l.text = String(m["name"])
		var gc := String(m["gc_name"])
		var line := String(m["label"])
		if gc != "" and gc != String(m["name"]) and gc != "Game Center friend":
			line += " · " + gc
		status_l.text = line
		disc.letter = String(m["name"]).left(1).to_upper()
		disc.status = String(m["status"]) if Friends.service == "ok" else "unavailable"
		disc.seed = String(m["tid"]).hash()
		disc.queue_redraw()
		var act := String(m["action"])
		action_btn.visible = act in ["invite", "sending", "gc_invite"]
		action_btn.disabled = act == "sending"
		action_btn.text = "Sending…" if act == "sending" else "Invite"
		# ("In your party" is already the status line: no second label)
		chip.visible = act in ["invited", "update", "full", "busy", "gc_sent", "gc_joining", "gc_declined"]
		chip.text = {"invited": "Invited ✓", "gc_sent": "Invited ✓", "gc_joining": "Joining…", "gc_declined": "Can't come",
			"update": "Needs update", "full": "Party full", "busy": "After the round"}.get(act, "")
		chip.add_theme_color_override("font_color", UIKit.TEAL if act in ["invited", "gc_sent", "gc_joining"] else UIKit.IVORY_MUTED)
		card.accessibility_name = "%s, %s" % [name_l.text, status_l.text]
		action_btn.accessibility_name = "Invite %s" % name_l.text
		if changed_actions or open:
			_paint_actions(open)

	func _paint_actions(open: bool) -> void:
		for c in actions.get_children():
			c.queue_free()
		actions.visible = open
		if not open:
			return
		var any := false
		if String(model.get("pid", "")) != "":
			var rb := UIKit.quiet("Report…", Vector2(0, 60), UIKit.T_CAPTION)
			rb.pressed.connect(func() -> void: panel._report(model))
			actions.add_child(rb)
			var bb := UIKit.quiet("Block…", Vector2(0, 60), UIKit.T_CAPTION)
			bb.pressed.connect(func() -> void: _confirm_block())
			actions.add_child(bb)
			any = true
		if String(model.get("kind", "")) in ["tag", "both"] and String(model.get("pid", "")) != "":
			var xb := UIKit.quiet("Remove…", Vector2(0, 60), UIKit.T_CAPTION)
			xb.pressed.connect(func() -> void: _confirm_remove())
			actions.add_child(xb)
		if not any:
			var l := UIKit.styled("Only the party host can invite. You can share the party code instead.", "caption", UIKit.IVORY_MUTED)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(260, 0)
			actions.add_child(l)

	func _confirm_block() -> void:
		_confirm("Block %s? You won't see each other in Friends, you won't be put in parties together, and they can't join yours." % name_l.text,
			"Block", func() -> void: panel._block(model))

	func _confirm_remove() -> void:
		_confirm("Remove %s from your friends?" % name_l.text, "Remove", func() -> void: panel._remove(model))

	func _confirm(text: String, yes_text: String, yes: Callable) -> void:
		for c in actions.get_children():
			c.queue_free()
		var q := UIKit.styled(text, "caption", UIKit.IVORY)
		q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		q.custom_minimum_size = Vector2(minf(panel.panel.size.x - 60.0, 520.0), 0)
		actions.add_child(q)
		var yb := UIKit.secondary(yes_text, Vector2(0, 60), UIKit.T_CAPTION)
		yb.pressed.connect(yes)
		actions.add_child(yb)
		var no := UIKit.quiet("Cancel", Vector2(0, 60), UIKit.T_CAPTION)
		no.pressed.connect(func() -> void: panel._toggle(String(model["tid"])))
		actions.add_child(no)


## A small drawn icon for the action tiles.
class Glyph:
	extends Control
	var icon := ""
	var col := UIKit.IVORY

	func _init() -> void:
		custom_minimum_size = Vector2(34, 30)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		Icons.draw_shape(self, icon, size * 0.5, minf(size.x, size.y) * 0.45, col)


## The friend's initial on a soft disc, with the status as a dot (online
## green, in a party teal, in a round amber, offline a grey ring; nothing
## when status is unknown or unavailable).
class Disc:
	extends Control
	var letter := ""
	var status := "unknown"
	var seed := 0

	func _init() -> void:
		custom_minimum_size = Vector2(48, 48)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		var hue := float(absi(seed) % 360) / 360.0
		draw_circle(c, r, Color.from_hsv(hue, 0.35, 0.42))
		var f := UIKit.font_w(800)
		var fs := int(r * 0.95)
		var sz := f.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(f, Vector2(c.x - sz.x * 0.5, c.y + f.get_ascent(fs) * 0.5 - f.get_descent(fs) * 0.25), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UIKit.IVORY)
		var dc := c + Vector2(r * 0.72, r * 0.72)
		match status:
			"online":
				draw_circle(dc, r * 0.3, UIKit.SLATE)
				draw_circle(dc, r * 0.22, UIKit.GOOD)
			"lobby":
				draw_circle(dc, r * 0.3, UIKit.SLATE)
				draw_circle(dc, r * 0.22, UIKit.TEAL)
			"match":
				draw_circle(dc, r * 0.3, UIKit.SLATE)
				draw_circle(dc, r * 0.22, UIKit.AMBER)
			"offline":
				draw_circle(dc, r * 0.3, UIKit.SLATE)
				draw_arc(dc, r * 0.18, 0, TAU, 16, UIKit.IVORY_DIM, r * 0.08, true)
