class_name LobbyScreen
extends Screen
## Party lobby in the dorm common room.
##   top bar   Back · room code (copy) · Invite
##   stage     the 3D room (App.stage, root viewport): local player at the
##             front facing the camera, others on stable staggered marks
##   panel     compact two-column party list (8 fixed cells, updated in place)
##   actions   one primary (host: Start, guest: Ready / Not ready); Outfit,
##             Emote and Role live in small popovers
## Updates are incremental: lobby_changed rewrites cell contents and syncs the
## stage by player identity; nothing is rebuilt wholesale.

var session: NetSession
var code_chip: Label
var invite_btn: Button
var status_lbl: Label
var primary_btn: Button
var sub_lbl: Label
var cells: Array[SlotCell] = []
var count_lbl: Label
var _is_ready := false
var _popover: Control


func build() -> void:
	back_action = func() -> void: dialog("Leave this room?", [["Leave", func() -> void: App.leave_room()], ["Stay", Callable()]])
	if App.stage:
		App.stage.set_mode("lobby")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shade := TextureRect.new()
	shade.texture = TitleScreen._side_gradient()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	move_child(shade, 0)

	# --- top bar
	var top := UIKit.hbox(14)
	content.add_child(top)
	var back := UIKit.icon_button("back")
	back.tooltip_text = "Leave room"
	back.pressed.connect(_go_back)
	top.add_child(back)
	var code_box := UIKit.panel(Color(UIKit.SLATE, 0.9), 999, 20)
	code_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var cb := UIKit.hbox(10)
	cb.add_child(UIKit.label("ROOM", 18, UIKit.IVORY_MUTED, true))
	code_chip = UIKit.label("", 30, UIKit.AMBER)
	code_chip.add_theme_font_override("font", UIKit.font_w(700))
	cb.add_child(code_chip)
	code_box.add_child(cb)
	top.add_child(code_box)
	var copy := UIKit.icon_button("copy")
	copy.tooltip_text = "Copy room code"
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(session.room_code)
		UIKit.toast(self, "Code %s copied" % session.room_code))
	top.add_child(copy)
	top.add_child(UIKit.spacer_h())
	invite_btn = UIKit.icon_button("invite", "Invite")
	invite_btn.pressed.connect(_invite)
	top.add_child(invite_btn)

	# --- middle: stage space (left) + party panel (right)
	var mid := UIKit.hbox(0)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(mid)
	mid.add_child(UIKit.spacer_h())
	var panel := UIKit.panel(Color(UIKit.SLATE, 0.92), UIKit.R_PANEL, 16)
	panel.custom_minimum_size = Vector2(520, 0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.add_child(panel)
	var pv := UIKit.vbox(10)
	panel.add_child(pv)
	var ph := UIKit.hbox(10)
	ph.add_child(UIKit.label("Party", 24, UIKit.IVORY, true))
	count_lbl = UIKit.label("", 20, UIKit.IVORY_MUTED)
	count_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ph.add_child(count_lbl)
	pv.add_child(ph)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	pv.add_child(grid)
	for i in 8:
		var c := SlotCell.new()
		c.slot = i
		c.pressed.connect(_on_cell.bind(i))
		grid.add_child(c)
		cells.append(c)

	# --- bottom: secondary popovers (left) + primary action (right)
	var bottom := UIKit.hbox(12)
	content.add_child(bottom)
	var outfit := UIKit.icon_button("shirt", "Outfit")
	outfit.pressed.connect(func() -> void:
		var w := CreatorScreen.new()
		w.back_action_override = func() -> void: App.show_lobby()
		App._show(w))
	outfit.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(outfit)
	var emote_b := UIKit.icon_button("smile", "Emote")
	emote_b.pressed.connect(func() -> void: _emote_popover(emote_b))
	emote_b.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(emote_b)
	var role_b := UIKit.icon_button("role", "Role")
	role_b.pressed.connect(func() -> void: _role_popover(role_b))
	role_b.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(role_b)
	bottom.add_child(UIKit.spacer_h())
	var pcol := UIKit.vbox(4)
	pcol.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_child(pcol)
	status_lbl = UIKit.label("", 18, UIKit.IVORY_MUTED, false, HORIZONTAL_ALIGNMENT_RIGHT)
	pcol.add_child(status_lbl)
	primary_btn = UIKit.primary("Start", Vector2(340, 96), 32)
	primary_btn.pressed.connect(_on_primary)
	pcol.add_child(primary_btn)
	sub_lbl = UIKit.label("", 18, UIKit.IVORY_MUTED, false, HORIZONTAL_ALIGNMENT_CENTER)
	pcol.add_child(sub_lbl)
	focus_first(primary_btn)
	session.lobby_changed.connect(_refresh)
	session.status_changed.connect(_on_status)
	session.events_received.connect(_on_events)
	_is_ready = session.local_slot >= 0 and session.roster[session.local_slot] != null and bool(session.roster[session.local_slot]["ready"])
	_refresh()
	UIKit.appear(panel, Vector2(40, 0), UIKit.T_SHEET)
	panel.resized.connect(_frame_stage.bind(panel))
	get_viewport().size_changed.connect(_frame_stage.bind(panel))
	_frame_stage.call_deferred(panel)


## Tell the stage how much of the screen is free left of the party panel.
func _frame_stage(panel: Control) -> void:
	if App.stage and is_instance_valid(panel):
		var w := get_viewport().get_visible_rect().size.x
		App.stage.set_lobby_free_frac((panel.get_global_rect().position.x - 12.0) / maxf(1.0, w))


func _on_primary() -> void:
	if session.is_host():
		if session.can_start():
			session.host_start_match()
		return
	_is_ready = not _is_ready
	session.set_local_ready(_is_ready)
	_refresh()


func _on_status(t: String) -> void:
	if is_instance_valid(status_lbl) and t != "":
		status_lbl.text = t


func _refresh() -> void:
	if not is_instance_valid(primary_btn):
		return
	var hosting := session.is_host()
	code_chip.text = session.room_code if session.room_code != "" else "…"
	invite_btn.visible = hosting and Social.online_ready() and session.transport is GameKitTransport
	var humans := 0
	var not_ready := 0
	var entries: Array = []
	var first_open := true
	for i in 8:
		var e: Variant = session.roster[i]
		cells[i].show_entry(e, i == session.local_slot, hosting, session.muted, _can_invite(), first_open)
		if e == null:
			first_open = false
		if e == null:
			continue
		if not bool(e["is_bot"]):
			humans += 1
			if i != session.local_slot and not bool(e["ready"]) and int(e["slot"]) != 0:
				not_ready += 1
		var ent := {"key": String(e["uid"]), "role": TC.Role.RUNNER, "cosmetic": e["cosmetic"], "name": String(e["name"]),
			"is_bot": bool(e["is_bot"]), "local": i == session.local_slot}
		if i == session.local_slot:
			entries.push_front(ent)
		else:
			entries.append(ent)
	if App.stage:
		App.stage.sync_party(entries)
	count_lbl.text = "%d / 8" % humans
	var bots := 8 - humans
	if hosting:
		primary_btn.text = "Start"
		primary_btn.disabled = not session.can_start()
		var bot_txt := "1 bot" if bots == 1 else "%d bots" % bots
		sub_lbl.text = ("You + " + bot_txt if humans == 1 else "%d players + %s" % [humans, bot_txt]) if bots > 0 else "Full party"
		if humans == 1:
			status_lbl.text = "Share the code, or start now — bots fill empty spots."
		elif not_ready > 0:
			status_lbl.text = "Waiting for %d to tap Ready" % not_ready
		else:
			status_lbl.text = "Everyone's ready"
	else:
		primary_btn.disabled = session.local_slot < 0
		primary_btn.text = "Not ready" if _is_ready else "Ready"
		UIKit._apply(primary_btn, UIKit.SLATE_HI if _is_ready else UIKit.AMBER, UIKit.IVORY if _is_ready else UIKit.NAVY)
		sub_lbl.text = ""
		if session.host_peer < 0:
			status_lbl.text = "Looking for room %s…" % session.room_code
		else:
			status_lbl.text = "You're ready — the host starts the round" if _is_ready else "Tap Ready when you are"


func _can_invite() -> bool:
	return session.is_host() and Social.online_ready() and session.transport is GameKitTransport


func _on_cell(i: int) -> void:
	var e: Variant = session.roster[i]
	if e == null:
		if _can_invite():
			_invite()
		else:
			DisplayServer.clipboard_set(session.room_code)
			UIKit.toast(self, "Code %s copied — share it to invite" % session.room_code)
		return
	if i == session.local_slot or bool(e["is_bot"]):
		return
	_player_popover(i, cells[i])


func _close_popover() -> void:
	if _popover and is_instance_valid(_popover):
		_popover.queue_free()
	_popover = null


## Small anchored panel with a dismiss catcher behind it.
func _popover_at(anchor: Control, body: Control, above: bool = true) -> void:
	_close_popover()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var catcher := Button.new()
	catcher.flat = true
	catcher.focus_mode = Control.FOCUS_NONE
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.pressed.connect(_close_popover)
	root.add_child(catcher)
	var p := UIKit.panel(Color(UIKit.SLATE_HI, 0.98), UIKit.R_PANEL, 16)
	p.add_child(body)
	root.add_child(p)
	var ar := anchor.get_global_rect()
	var sz := p.get_combined_minimum_size()
	var vis := get_viewport().get_visible_rect().size
	var pos := Vector2(ar.position.x, ar.position.y - sz.y - 12) if above else Vector2(ar.position.x - sz.x - 12, ar.position.y)
	pos.x = clampf(pos.x, 16, vis.x - sz.x - 16)
	pos.y = clampf(pos.y, 16, vis.y - sz.y - 16)
	p.position = pos
	UIKit.appear(p, Vector2(0, 10) if above else Vector2(10, 0), UIKit.T_FAST)
	_popover = root
	var first := body.find_children("*", "Button", true, false)
	if not first.is_empty():
		(first[0] as Button).call_deferred("grab_focus")


func _emote_popover(anchor: Control) -> void:
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 10)
	for i in TC.EMOTES.size():
		var b := UIKit.secondary(TC.EMOTE_LABELS[TC.EMOTES[i]], Vector2(170, 72), 22)
		var idx := i
		b.pressed.connect(func() -> void:
			session.send_emote(idx)
			_close_popover())
		g.add_child(b)
	_popover_at(anchor, g)


func _role_popover(anchor: Control) -> void:
	var v := UIKit.vbox(10)
	v.add_child(UIKit.label("I'd like to play as", 20, UIKit.IVORY_MUTED, true))
	var cur := session.local_pref
	for opt in [["any", "Either role"], ["runner", "Runner"], ["patrol", "Night Watch"]]:
		var key: String = opt[0]
		var b := UIKit.secondary(("✓  " if key == cur else "") + String(opt[1]), Vector2(300, 72), 24)
		if key == cur:
			UIKit._apply(b, UIKit.TEAL, UIKit.NAVY)
		b.pressed.connect(func() -> void:
			Save.set_setting("role_pref", key)
			session.set_local_pref(key)
			_close_popover()
			_refresh())
		v.add_child(b)
	var note := UIKit.label("Roles rotate fairly; this is a preference.", 17, UIKit.IVORY_MUTED)
	v.add_child(note)
	_popover_at(anchor, v)


func _player_popover(i: int, anchor: Control) -> void:
	var e: Dictionary = session.roster[i]
	var uid := String(e["uid"])
	var v := UIKit.vbox(10)
	var nm := UIKit.label(String(e["name"]), 22, UIKit.IVORY, true)
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.custom_minimum_size = Vector2(280, 0)
	v.add_child(nm)
	var muted := session.muted.has(uid)
	var mb := UIKit.secondary("Show their emotes" if muted else "Hide their emotes", Vector2(300, 72), 22)
	mb.pressed.connect(func() -> void:
		if session.muted.has(uid):
			session.muted.erase(uid)
		else:
			session.muted[uid] = true
		_close_popover()
		_refresh())
	v.add_child(mb)
	if session.is_host():
		var kb := UIKit.quiet("Remove from room", Vector2(300, 72), 22)
		kb.pressed.connect(func() -> void:
			_close_popover()
			dialog("Remove %s from the room?" % e["name"], [["Remove", func() -> void: session.kick(i)], ["Cancel", Callable()]]))
		v.add_child(kb)
	_popover_at(anchor, v, false)


func _on_events(evs: Array) -> void:
	for ev in evs:
		if int(ev["type"]) != TC.Ev.EMOTE:
			continue
		var a := int(ev["a"])
		if a < 0 or a >= 8 or session.roster[a] == null:
			continue
		var who: Dictionary = session.roster[a]
		if session.muted.has(String(who.get("uid", ""))):
			continue
		if App.stage:
			App.stage.emote(String(who["uid"]), int(ev["v"]), 1.8)
		Sfx.play("pop")


func _invite() -> void:
	if session.transport is GameKitTransport:
		Social.invite_friends(session.transport, session.room_code)


## One party-list cell (fixed per slot; contents updated in place).
class SlotCell:
	extends Button
	var slot := 0
	var dot: ColorRect
	var name_l: Label
	var sub_l: Label
	var badge: Icons.IconRect

	func _init() -> void:
		custom_minimum_size = Vector2(248, maxf(64.0, UIKit.touch_min()))
		focus_mode = Control.FOCUS_ALL
		UIKit.press_feedback(self)
		var h := UIKit.hbox(10)
		h.set_anchors_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 12
		h.offset_right = -10
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(h)
		dot = ColorRect.new()
		dot.custom_minimum_size = Vector2(10, 34)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(dot)
		var v := UIKit.vbox(0)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(v)
		name_l = UIKit.label("", 21, UIKit.IVORY, true)
		name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_l.clip_text = true
		name_l.custom_minimum_size = Vector2(150, 0)
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(name_l)
		sub_l = UIKit.label("", 16, UIKit.IVORY_MUTED)
		sub_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		sub_l.clip_text = true
		sub_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(sub_l)
		badge = Icons.IconRect.new("check", UIKit.TEAL, 30)
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(badge)

	func _style(bg: Color, border: Color) -> void:
		add_theme_stylebox_override("normal", UIKit.box(bg, UIKit.R_SMALL, 2, border))
		add_theme_stylebox_override("hover", UIKit.box(bg.lightened(0.06), UIKit.R_SMALL, 2, border))
		add_theme_stylebox_override("pressed", UIKit.box(bg.darkened(0.12), UIKit.R_SMALL, 2, border))
		add_theme_stylebox_override("focus", UIKit.box(Color(0, 0, 0, 0), UIKit.R_SMALL + 2, 3, UIKit.TEAL, 0))

	func show_entry(e: Variant, me: bool, hosting: bool, muted: Dictionary, can_invite: bool, first_open: bool = false) -> void:
		if e == null:
			_style(Color(UIKit.NAVY, 0.3), Color(UIKit.IVORY, 0.1))
			dot.color = Color(UIKit.IVORY, 0.1)
			name_l.text = "Invite" if can_invite else "Open"
			name_l.add_theme_color_override("font_color", Color(UIKit.IVORY, 0.45))
			sub_l.text = ("tap to invite a friend" if can_invite else "share the code") if first_open else ""
			badge.kind = "plus"
			badge.col = Color(UIKit.IVORY, 0.4)
			badge.queue_redraw()
			return
		var ent: Dictionary = e
		_style(Color(UIKit.SLATE_HI, 0.95) if me else Color(UIKit.SLATE_LO, 0.85), UIKit.AMBER if me else Color(0, 0, 0, 0))
		dot.color = Cosmetics.color_of(ent["cosmetic"])
		name_l.text = String(ent["name"])
		name_l.add_theme_color_override("font_color", UIKit.IVORY)
		var bits: Array[String] = []
		var host_slot := int(ent["slot"]) == 0
		if me:
			bits.append("You")
		if bool(ent["is_bot"]):
			bits.append("Bot")
		elif not bool(ent["connected"]):
			bits.append("Reconnecting…")
		elif host_slot:
			bits.append("Host")
		elif bool(ent["ready"]):
			bits.append("Ready")
		else:
			bits.append("Not ready")
		var pref := String(ent.get("pref", "any"))
		if pref == "runner":
			bits.append("prefers Runner")
		elif pref == "patrol":
			bits.append("prefers Night Watch")
		if muted.has(String(ent["uid"])):
			bits.append("emotes hidden")
		sub_l.text = "  ·  ".join(bits)
		var ok := bool(ent["ready"]) or host_slot or bool(ent["is_bot"])
		badge.kind = "crown" if host_slot else ("bot" if bool(ent["is_bot"]) else ("check" if ok else "smile"))
		badge.col = UIKit.AMBER if host_slot else (UIKit.TEAL if ok else Color(UIKit.IVORY, 0.35))
		badge.queue_redraw()
