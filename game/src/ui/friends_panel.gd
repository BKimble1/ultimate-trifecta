class_name FriendsPanel
extends Control
## The Friends drawer (FINAL_RELEASE_SWEEP), opened from Friends on Home,
## in the party room and on Play with Friends.
##   header    Friends, what Invite does here, Close
##   invites   invites waiting for you: who, which party, time left,
##             Decline / Accept
##   list      your Game Center friends, sorted Online → In a party → In a
##             round → Offline → status unknown, then by name.  Each row: an
##             initial disc with a status dot (and the status in words: never
##             colour alone), the name (the verified game name where the
##             service knows it, else the Game Center name), the status, and
##             one action: Invite, "Invited ✓" (only after the service
##             confirmed the send), "In your party", "Needs update".  Tap a
##             row for Invite with Game Center (that friend pre-selected in
##             Apple's sheet), Report and Block (where a verified profile
##             is shown).
##   states    checking, asking for friends-list access (Apple's sheet),
##             access off / restricted (Screen Time), Game Center signed
##             out, no Game Center on this device, no friends yet; and when
##             the game service can't confirm anyone's status, every row says
##             "Status unavailable" (no green dot is ever guessed)
##   footer    the reliable ways that need no status: the party code with
##             Copy, Invite with Game Center (Apple's sheet; the host), or
##             Party codes (Play with Friends) from Home.  "Show when I'm
##             playing" (on/off) ends the list
## Status is polled only while this is open (Friends.watch).  It owns input
## while open (nothing in the party room moves) and releases it on close;
## Close, Back, a tap outside and ui_cancel all close it.

signal closed

var panel: PanelContainer
var title_lbl: Label
var sub_lbl: Label
var close_btn: Button
var invites_box: VBoxContainer
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
var play_btn: Button
var share_btn: Button
var _rows: Dictionary = {}       # tid -> Row
var _open_tid := ""
var _note: Label


static func open(parent: Control) -> FriendsPanel:
	for c in parent.get_children():
		if c is FriendsPanel and not c.is_queued_for_deletion():
			return c
	var d := FriendsPanel.new()
	parent.add_child(d)
	if parent is Screen:
		(parent as Screen).push_modal(d, d.close)
	return d


## The Friends button for a screen's top row, with a count of invites
## waiting (it opens the panel on `screen`).
static func entry_button(screen: Control) -> Button:
	var b := UIKit.icon_button("invite", "Friends")
	b.name = "FriendsButton"
	b.tooltip_text = "Friends"
	b.accessibility_name = "Friends"
	b.pressed.connect(func() -> void:
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
		b.accessibility_name = ("Friends, %d invite%s" % [n, "" if n == 1 else "s"]) if n > 0 else "Friends"
	Friends.invites_changed.connect(paint)
	b.resized.connect(paint)
	b.tree_exiting.connect(func() -> void:
		if Friends.invites_changed.is_connected(paint):
			Friends.invites_changed.disconnect(paint), CONNECT_ONE_SHOT)
	paint.call_deferred()
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
	panel = UIKit.panel(Color(UIKit.SLATE, 0.98), UIKit.R_PANEL, 18)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var w := clampf(vs.x * 0.48, 460.0, 680.0)
	panel.position = Vector2(vs.x - sm.size.x - w - 12.0, sm.position.y + 12.0)
	panel.size = Vector2(w, vs.y - sm.position.y - sm.size.y - 24.0)
	panel.custom_minimum_size = panel.size
	add_child(panel)
	var v := UIKit.vbox(10)
	panel.add_child(v)
	# --- header
	var head := UIKit.hbox(10)
	var hv := UIKit.vbox(0)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl = UIKit.styled("Friends", "headline")
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
	# --- invites waiting for you
	invites_box = UIKit.vbox(8)
	v.add_child(invites_box)
	# --- one restrained line about status when it can't be confirmed
	service_lbl = UIKit.styled("", "caption", UIKit.AMBER)
	service_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(service_lbl)
	# --- the list (finger scrolled) and the non-list states
	scroll = UIKit.scroll_area()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
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
	hint_lbl = UIKit.styled("Status shows for friends who also use Friends in Ultimate Trifecta.", "caption", UIKit.IVORY_MUTED)
	hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(hint_lbl)
	_note = UIKit.styled("", "caption", UIKit.AMBER)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.visible = false
	v.add_child(_note)
	# --- the ways that never need status
	var foot := HFlowContainer.new()
	foot.add_theme_constant_override("h_separation", 8)
	foot.add_theme_constant_override("v_separation", 8)
	footer = foot
	code_lbl = UIKit.styled("", "label", UIKit.AMBER)
	code_lbl.add_theme_font_override("font", UIKit.font_num(800))
	code_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(code_lbl)
	copy_btn = UIKit.quiet("Copy code", Vector2(0, UIKit.touch_min()), UIKit.T_CAPTION)
	copy_btn.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(App.party_code)
		_say("Code %s copied" % App.party_code))
	foot.add_child(copy_btn)
	gc_btn = UIKit.quiet("Invite with Game Center", Vector2(0, UIKit.touch_min()), UIKit.T_CAPTION)
	gc_btn.pressed.connect(func() -> void: _game_center_invite([]))
	foot.add_child(gc_btn)
	play_btn = UIKit.quiet("Party codes", Vector2(0, UIKit.touch_min()), UIKit.T_CAPTION)
	play_btn.tooltip_text = "Create a party or join with a code"
	play_btn.pressed.connect(func() -> void:
		close()
		App.goto(OnlineScreen))
	foot.add_child(play_btn)
	v.add_child(foot)
	# "Show when I'm playing" is a setting: it sits at the end of the list
	share_btn = UIKit.quiet("", Vector2(0, UIKit.touch_min()), UIKit.T_CAPTION)
	share_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	share_btn.pressed.connect(func() -> void: Friends.set_share_status(not Friends.share_status()))
	inner.add_child(share_btn)
	Friends.changed.connect(_refresh)
	Friends.invites_changed.connect(_refresh)
	Friends.watch(true)
	_refresh()
	if not UIKit.reduced_motion():
		panel.modulate.a = 0.0
		Motion.animate(panel, "modulate:a", 1.0, UIKit.T_FAST)
	if Controls.device != "touch":
		UIKit.soft_focus.call_deferred(close_btn)


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
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _say(t: String) -> void:
	_note.text = t
	_note.visible = t != ""


# ---------------------------------------------------------------- states
## loading | unavailable | signed_out | multiplayer_off | not_determined |
## denied | restricted | error | empty | list  (tests and captures)
func state_name() -> String:
	match Friends.access:
		"unknown", "checking":
			return "loading"
		"unavailable", "signed_out", "multiplayer_off", "not_determined", "denied", "restricted", "error":
			return Friends.access
		"authorized":
			if Friends.friends.is_empty():
				return "loading" if Friends.loading_friends else "empty"
			return "list"
	return "loading"


const STATE_TEXT := {
	"loading": "Loading your friends…",
	"unavailable": "Friends use Game Center on iPhone and iPad.",
	"signed_out": "Sign in to Game Center in the Settings app to see your friends.",
	"multiplayer_off": "Multiplayer is off for this Game Center account (Screen Time). Practice still works.",
	"not_determined": "Allow Ultimate Trifecta to see your Game Center friends to find who's playing.",
	"denied": "Friends list access is off. Turn it on in the Settings app (Game Center › Friends List). Party codes still work.",
	"restricted": "Friends list access is restricted on this device (Screen Time). Party codes still work.",
	"error": "Couldn't load your Game Center friends.",
	"empty": "No Game Center friends yet. Add friends in Game Center, or share a party code.",
}


func service_text() -> String:
	if Friends.access != "authorized" or Friends.friends.is_empty():
		return ""
	match Friends.service:
		"ok":
			return ""
		"loading", "idle":
			return "Checking who's playing…"
		"off":
			return "Status unavailable right now. You can still invite with Game Center or a party code."
		"network":
			return "Can't reach the game service, so status is unavailable. Check your connection."
		"signed_out":
			return "Sign in to see who's playing (status unavailable)."
		"suspended":
			return Friends.service_message if Friends.service_message != "" else "Online play is paused for this account."
	return "Status unavailable right now."


func _refresh() -> void:
	if not is_instance_valid(list_box):
		return
	var st := state_name()
	var in_party := Friends.in_party()
	sub_lbl.text = "Invite friends to this party." if in_party else "Invite starts a party for you."
	state_box.visible = st != "list"
	state_lbl.text = String(STATE_TEXT.get(st, ""))
	state_btn.visible = st in ["error", "not_determined"]
	state_btn.text = "Allow friends list" if st == "not_determined" else "Try again"
	service_lbl.text = service_text()
	service_lbl.visible = service_lbl.text != ""
	hint_lbl.visible = st == "list" and Friends.service == "ok"
	_paint_invites()
	_paint_rows(st == "list")
	# footer
	code_lbl.visible = in_party
	copy_btn.visible = in_party
	code_lbl.text = ("Code " + App.party_code) if in_party else ""
	gc_btn.visible = can_game_center()
	play_btn.visible = not in_party
	share_btn.visible = Friends.access == "authorized" and Friends.feature_on()
	share_btn.text = "Show when I'm playing: %s" % ("On" if Friends.share_status() else "Off")
	share_btn.accessibility_name = share_btn.text


## Apple's invite sheet works for the host of a Game Center party.
func can_game_center() -> bool:
	var s: Variant = App.session
	return Social.online_ready() and s != null and is_instance_valid(s) and (s as NetSession).is_host() \
		and (s as NetSession).transport is GameKitTransport


func _game_center_invite(recipients: Array) -> void:
	var s: Variant = App.session
	if not can_game_center():
		return
	close()
	Social.invite_friends((s as NetSession).transport, (s as NetSession).room_code, recipients)


func _paint_invites() -> void:
	for c in invites_box.get_children():
		c.queue_free()
	for iv in Friends.incoming:
		invites_box.add_child(_invite_card(iv))
	invites_box.visible = not Friends.incoming.is_empty()


func _invite_card(iv: Dictionary) -> Control:
	var p := UIKit.panel(Color(UIKit.SLATE_HI, 0.95), UIKit.R_CARD, 12)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 8)
	var t := Friends.invite_text(iv)
	var tv := UIKit.vbox(0)
	tv.custom_minimum_size = Vector2(240, 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var a := UIKit.styled(String(t[0]), "label")
	a.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(a)
	var left := maxi(0, int((float(iv.get("expires_at", 0)) - Friends.server_now_ms()) / 1000.0))
	var b := UIKit.styled("%s · %d:%02d left" % [t[1], left / 60, left % 60], "caption", UIKit.IVORY_MUTED)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(b)
	row.add_child(tv)
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
	p.add_child(row)
	return p


# ---------------------------------------------------------------- rows
const RANK := {"online": 0, "lobby": 1, "match": 2, "offline": 3, "unknown": 4, "unavailable": 4}


## The row model for one Game Center friend: {tid, name, gc_name, status,
## label, action, p (service entry or null), player}.
static func model(f: Dictionary) -> Dictionary:
	var tid := String(f["tid"])
	var p: Variant = Friends.presence.get(tid)
	var gc := gc_display(String(f.get("name", "")))
	var name := gc
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
	return {"tid": tid, "name": name, "gc_name": gc, "status": status, "label": label, "action": action, "p": p, "player": f.get("player")}


## Online → In a party → In a round → Offline → unknown, then by name.
static func sorted_models() -> Array:
	var out: Array = []
	for f in Friends.friends:
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


func _report(m: Dictionary) -> void:
	var p: Dictionary = m["p"]
	ReportSheet.open(self, {"kind": "player", "name": String(m["name"]), "pid": String(p.get("profile_id", "")),
		"context": {"room_code": App.party_code, "build": App.build_number()}})


func _block(m: Dictionary) -> void:
	var p: Dictionary = m["p"]
	var e := {"pid": String(p.get("profile_id", "")), "uid": "", "name": String(m["name"])}
	var note: String = await SocialActions.block(null, e)
	if is_inside_tree():
		_say(note)
		_open_tid = ""
		Friends.refresh()


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
			if panel != null and String(model.get("action", "")) == "invite":
				panel._invite(String(model["tid"])))
		# (the action sits over the card: it takes its own taps)
		h.add_child(action_btn)
		card.pressed.connect(func() -> void:
			if panel != null:
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
		if gc != String(m["name"]) and gc != "Game Center friend":
			line += " · " + gc
		status_l.text = line
		disc.letter = String(m["name"]).left(1).to_upper()
		disc.status = String(m["status"]) if Friends.service == "ok" else "unavailable"
		disc.seed = String(m["tid"]).hash()
		disc.queue_redraw()
		var act := String(m["action"])
		action_btn.visible = act in ["invite", "sending"]
		action_btn.disabled = act == "sending"
		action_btn.text = "Sending…" if act == "sending" else "Invite"
		# ("In your party" is already the status line: no second label)
		chip.visible = act in ["invited", "update", "full", "busy"]
		chip.text = {"invited": "Invited ✓", "update": "Needs update", "full": "Party full", "busy": "After the round"}.get(act, "")
		chip.add_theme_color_override("font_color", UIKit.TEAL if act == "invited" else UIKit.IVORY_MUTED)
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
		if panel.can_game_center() and model.get("player") is Object:
			var gcb := UIKit.quiet("Invite with Game Center", Vector2(0, 60), UIKit.T_CAPTION)
			gcb.pressed.connect(func() -> void: panel._game_center_invite([model["player"]]))
			actions.add_child(gcb)
			any = true
		var p: Variant = model.get("p")
		if p is Dictionary and String((p as Dictionary).get("profile_id", "")) != "":
			var rb := UIKit.quiet("Report…", Vector2(0, 60), UIKit.T_CAPTION)
			rb.pressed.connect(func() -> void: panel._report(model))
			actions.add_child(rb)
			var bb := UIKit.quiet("Block…", Vector2(0, 60), UIKit.T_CAPTION)
			bb.pressed.connect(func() -> void: _confirm_block())
			actions.add_child(bb)
			any = true
		if not any:
			var l := UIKit.styled("Invite with Game Center from your party, or share the party code.", "caption", UIKit.IVORY_MUTED)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(260, 0)
			actions.add_child(l)

	func _confirm_block() -> void:
		for c in actions.get_children():
			c.queue_free()
		var q := UIKit.styled("Block %s? You won't see each other in Friends, you won't be put in parties together, and they can't join yours." % name_l.text,
			"caption", UIKit.IVORY)
		q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		q.custom_minimum_size = Vector2(minf(panel.panel.size.x - 60.0, 520.0), 0)
		actions.add_child(q)
		var yes := UIKit.secondary("Block", Vector2(0, 60), UIKit.T_CAPTION)
		yes.pressed.connect(func() -> void: panel._block(model))
		actions.add_child(yes)
		var no := UIKit.quiet("Cancel", Vector2(0, 60), UIKit.T_CAPTION)
		no.pressed.connect(func() -> void: panel._toggle(String(model["tid"])))
		actions.add_child(no)


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
