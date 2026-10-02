class_name LobbyScreen
extends Screen
## Party lobby in the dorm common room (V5).
##   top       Back · the party code with Copy and Share · Invite;
##             the settings as short labelled values ("3 rounds",
##             "2 Night Watch", "4 home to win"): the host taps them to
##             change, guests see them read-only
##   stage     the 3D room (App.stage) with the party on their marks, left of
##             the roster.  Tap your own runner to play your move.
##   roster    compact player cards: portrait, the full name where it fits
##             (a smaller size before any trimming; tap for details), host,
##             ready and bot status, and one open seat to invite into
##   bottom    Wardrobe, Emote and Try moves (left); the one primary action
##             (host: Start / Start round N, guest: Ready) with its status
##             line (right).  Nothing moves when states change.
## Updates are incremental: lobby_changed rewrites card contents and syncs
## the stage by player identity; nothing is rebuilt wholesale.
## V6: Walk around (HubWalk: a stick on the left, the roster folds away,
## nameplates over everyone, Done or Back returns to the menu composition),
## the party chat drawer with Quick Chat (bubbles over heads, an unread
## badge), "joined" / "left" notes, and Mute / Report / Block that act the
## same everywhere (SocialSafety, ReportSheet).  Emote holds Try moves.

var session: NetSession
var code_lbl: Label
var invite_btn: Button
var status_lbl: Label
var primary_btn: Button
var sub_lbl: Label
var settings_btn: Button
var settings_chips: Array[Label] = []
var settings_lock: Icons.IconRect
var series_lbl: Label
var series_row: Control
var standings_btn: Button
var cells: Array[SlotCell] = []
var count_lbl: Label
var roster_col: VBoxContainer
var _grid: GridContainer
var _is_ready := false
## guests see their own emote at once; the host's echo of it is skipped
var _predicted := {"id": -1, "t": -10.0}
var _last_note := ""
# V6
var hub: HubWalk
var stick: HubStick
var walk_btn: Button
var chat_btn: Button
var top_bar: Control
var bottom_bar: Control
var _known: Dictionary = {}      # uid -> shown name (join / leave notes)
var _bubbled := 0                # newest chat sequence shown as a bubble


func build() -> void:
	back_action = func() -> void:
		if hub != null and hub.walking:
			_set_walk(false)   # Back first returns to the menu
			return
		dialog("Leave this party?", [["Leave", func() -> void: App.leave_room()], ["Stay", Callable()]])
	Diag.context("lobby")
	if App.stage:
		App.stage.set_mode("lobby")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	TitleScreen.add_shades(self, 0.55, 0.3)

	# --- top bar
	var top := UIKit.hbox(12)
	content.add_child(top)
	top_bar = top
	var back := UIKit.icon_button("back")
	back.tooltip_text = "Leave party"
	back.accessibility_name = "Leave party"
	back.pressed.connect(_go_back)
	top.add_child(back)
	var code_card := UIKit.panel(Color(UIKit.SLATE, 0.94), UIKit.R_CARD, 18)
	code_card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var cv := UIKit.vbox(0)
	cv.add_child(UIKit.styled("Party code", "overline", UIKit.IVORY_MUTED))
	code_lbl = UIKit.styled("", "num", UIKit.AMBER)
	code_lbl.add_theme_font_override("font", UIKit.font_num(800))
	code_lbl.add_theme_font_size_override("font_size", 30)
	cv.add_child(code_lbl)
	code_card.add_child(cv)
	top.add_child(code_card)
	var copy := UIKit.icon_button("copy")
	copy.tooltip_text = "Copy party code"
	copy.accessibility_name = "Copy party code"
	copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(session.room_code)
		UIKit.toast(self, "Code %s copied" % session.room_code))
	top.add_child(copy)
	var share := UIKit.icon_button("share")
	share.tooltip_text = "Share party code"
	share.accessibility_name = "Share party code"
	share.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	share.pressed.connect(func() -> void:
		if not Share.share_text(Share.party_message(session.room_code)):
			UIKit.toast(self, "Invite message copied — paste it to a friend"))
	top.add_child(share)
	invite_btn = UIKit.icon_button("invite", "Invite")
	invite_btn.tooltip_text = "Invite Game Center friends"
	invite_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	invite_btn.pressed.connect(_invite)
	top.add_child(invite_btn)
	top.add_child(UIKit.spacer_h())
	settings_btn = _settings_summary()
	settings_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(settings_btn)

	# --- series line (only during a series)
	var srow := UIKit.hbox(10)
	series_row = srow
	content.add_child(srow)
	var sp := UIKit.scrim(999, 16, 0.6)
	series_lbl = UIKit.styled("", "label", UIKit.AMBER)
	sp.add_child(series_lbl)
	srow.add_child(sp)
	standings_btn = UIKit.quiet("Standings", Vector2(180, 0))
	standings_btn.pressed.connect(_standings_sheet)
	srow.add_child(standings_btn)

	# --- middle: stage space (left) + roster (right)
	var mid := UIKit.hbox(0)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(mid)
	mid.add_child(UIKit.spacer_h())
	roster_col = UIKit.vbox(10)
	roster_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.add_child(roster_col)
	count_lbl = UIKit.styled("", "overline", UIKit.IVORY_MUTED)
	roster_col.add_child(count_lbl)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	roster_col.add_child(_grid)
	for i in 8:
		var c := SlotCell.new()
		c.slot = -1
		c.pressed.connect(_on_cell.bind(c))
		_grid.add_child(c)
		cells.append(c)

	# --- bottom: secondary actions (left) + primary action (right)
	var bottom := UIKit.hbox(12)
	content.add_child(bottom)
	bottom_bar = bottom
	var outfit := UIKit.icon_button("shirt", "Wardrobe")
	outfit.pressed.connect(_open_wardrobe)
	outfit.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(outfit)
	var emote_b := UIKit.icon_button("smile", "Emote")
	emote_b.pressed.connect(func() -> void: _emote_popover(emote_b))
	emote_b.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(emote_b)
	# (V6) Try moves lives in the Emote popover; Walk and Chat take its place
	walk_btn = UIKit.icon_button("walk", "Walk")
	walk_btn.tooltip_text = "Walk around the party room"
	walk_btn.accessibility_name = "Walk around"
	walk_btn.pressed.connect(func() -> void: _set_walk(not (hub != null and hub.walking)))
	walk_btn.size_flags_vertical = Control.SIZE_SHRINK_END
	walk_btn.visible = session.mode != NetSession.Mode.OFFLINE
	bottom.add_child(walk_btn)
	chat_btn = UIKit.icon_button("chat", "Chat")
	chat_btn.tooltip_text = "Party chat"
	chat_btn.accessibility_name = "Party chat"
	chat_btn.pressed.connect(_open_chat)
	chat_btn.size_flags_vertical = Control.SIZE_SHRINK_END
	chat_btn.visible = session.mode != NetSession.Mode.OFFLINE
	bottom.add_child(chat_btn)
	bottom.add_child(UIKit.spacer_h())
	var pcol := UIKit.vbox(6)
	pcol.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_child(pcol)
	status_lbl = UIKit.styled("", "caption", UIKit.IVORY_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	pcol.add_child(status_lbl)
	var prow := UIKit.hbox(12)
	prow.alignment = BoxContainer.ALIGNMENT_END
	pcol.add_child(prow)
	sub_lbl = UIKit.styled("", "caption", UIKit.IVORY_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	sub_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prow.add_child(sub_lbl)
	primary_btn = UIKit.primary("Start", Vector2(340, 96))
	primary_btn.pressed.connect(_on_primary)
	prow.add_child(primary_btn)
	focus_first(primary_btn)
	session.lobby_changed.connect(_refresh)
	session.status_changed.connect(_on_status)
	session.events_received.connect(_on_events)
	session.series_changed.connect(_refresh)
	# (V6) walking around and chat
	if App.stage:
		hub = HubWalk.attach(App.stage, session)
		hub.input_allowed = func() -> bool: return is_visible_in_tree() and not has_modal()
	stick = HubStick.new()
	stick.walk = hub
	stick.visible = false
	add_child(stick)
	session.social.chat.changed.connect(_on_chat)
	_bubbled = _newest_seq()
	_compact_bottom.call_deferred()
	get_viewport().size_changed.connect(_compact_bottom)
	_is_ready = session.local_slot >= 0 and session.roster[session.local_slot] != null and bool(session.roster[session.local_slot]["ready"])
	_refresh()
	Motion.settle_in(roster_col)
	roster_col.resized.connect(_frame_stage.bind(roster_col))
	get_viewport().size_changed.connect(_frame_stage.bind(roster_col))
	_frame_stage.call_deferred(roster_col)


## The settings as three short chips in one tappable group.
func _settings_summary() -> Button:
	var b := UIKit.card_button(Vector2(0, UIKit.touch_min()), Color(UIKit.SLATE, 0.94))
	b.tooltip_text = "Party settings"
	var f := UIKit.face_of(b)
	var h := UIKit.hbox(8)
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 14
	h.offset_right = -14
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	settings_lock = Icons.IconRect.new("sliders", UIKit.TEAL, 26)
	settings_lock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(settings_lock)
	for i in 3:
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UIKit.box(Color(UIKit.NAVY, 0.55), 999, 0, Color.WHITE, 12))
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := UIKit.styled("", "label")
		l.add_theme_font_size_override("font_size", UIKit.T_CAPTION)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(l)
		h.add_child(chip)
		settings_chips.append(l)
	f.add_child(h)
	b.pressed.connect(_settings_sheet)
	UIKit.fit_card(b, h, 28.0)
	return b


func _paint_settings() -> void:
	var parts := PartySeries.summary_parts(session.settings)
	for i in settings_chips.size():
		settings_chips[i].text = parts[i]
	var host := session.is_host() and session.mode != NetSession.Mode.OFFLINE and not session.series_active()
	settings_lock.kind = "sliders" if host else "lock"
	settings_lock.col = UIKit.TEAL if host else UIKit.IVORY_MUTED
	settings_lock.queue_redraw()
	settings_btn.accessibility_name = "Party settings: %s%s" % [", ".join(parts), "" if host else " (set by the host)"]


## Tell the stage how much of the screen is free left of the roster.
func _frame_stage(panel: Control) -> void:
	if App.stage and is_instance_valid(panel):
		var w := get_viewport().get_visible_rect().size.x
		App.stage.set_lobby_free_frac((panel.get_global_rect().position.x - 12.0) / maxf(1.0, w))


# ---------------------------------------------------------------------------
# V6: Walk around and chat
# ---------------------------------------------------------------------------
## Walk mode on/off.  The roster folds away (the names float over everyone)
## and the stick appears on the left; off, everyone is back in the menu
## composition and the stick's finger is released.
func _set_walk(on: bool) -> void:
	if hub == null or session.mode == NetSession.Mode.OFFLINE:
		return
	if on and has_modal():
		return
	hub.set_walking(on)
	on = hub.walking
	if on and App.stage:
		App.stage._walk_at = Vector3.INF
	stick.visible = on
	if not on:
		stick.release()
	roster_col.visible = not on
	series_row.visible = not on and session.series_active()
	UIKit.face_of(walk_btn).caption = "Done" if on else "Walk"
	UIKit.face_of(walk_btn).icon = "check" if on else "walk"
	UIKit.face_of(walk_btn).queue_redraw()
	walk_btn.accessibility_name = "Stop walking" if on else "Walk around"
	if on:
		_layout_stick()
		# menu focus would turn the stick's arrow keys into menu moves
		var fo := get_viewport().gui_get_focus_owner()
		if fo != null:
			fo.release_focus()
		margin.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
		status_lbl.text = "Drag on the left to walk · Done to stop" if Controls.device == "touch" else "Move to walk · Back to stop"
	else:
		margin.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
		_refresh()
	Diag.mark("hub_walk" if on else "hub_menu")


func _layout_stick() -> void:
	if not is_instance_valid(stick) or not is_instance_valid(top_bar) or not is_instance_valid(bottom_bar):
		return
	var vs := get_viewport().get_visible_rect().size
	var top := top_bar.get_global_rect().end.y + 8.0
	var bottom := bottom_bar.get_global_rect().position.y - 8.0
	stick.position = Vector2(0, top)
	stick.size = Vector2(vs.x * 0.5, maxf(120.0, bottom - top))


## Narrow screens (iPad 4:3, iPhone SE): the bottom actions drop their
## captions so the primary action keeps its size.
func _compact_bottom() -> void:
	if not is_instance_valid(bottom_bar):
		return
	var vs := get_viewport().get_visible_rect().size
	var narrow := vs.x / maxf(1.0, vs.y) < 1.6
	for b in bottom_bar.get_children():
		if b is Button and UIKit.face_of(b) != null and String(UIKit.face_of(b).icon) != "":
			var f := UIKit.face_of(b)
			if not b.has_meta(&"caption"):
				b.set_meta(&"caption", f.caption)
				b.set_meta(&"min_w", b.custom_minimum_size.x)
			f.caption = "" if narrow else String(b.get_meta(&"caption"))
			b.custom_minimum_size.x = UIKit.touch_min() if narrow else float(b.get_meta(&"min_w"))
			f.queue_redraw()
	if hub != null and hub.walking:
		_layout_stick.call_deferred()


func _open_chat() -> void:
	if has_modal():
		return
	close_popover()
	if hub != null and hub.walking:
		stick.release()
	var d := ChatDrawer.open(self, session, "results" if session.phase == TC.Phase.RESULTS else "party")
	d.closed.connect(_paint_chat_badge)
	_paint_chat_badge()


func _newest_seq() -> int:
	var n := 0
	for m in session.social.chat.history:
		n = maxi(n, int(m["seq"]))
	return n


## New messages: a bubble over the sender's head (the drawer has the full
## conversation) and the unread badge.
func _on_chat() -> void:
	if not is_instance_valid(chat_btn):
		return
	for m in session.social.chat.visible([QuickChat.Channel.PARTY, QuickChat.Channel.ALL]):
		if int(m["seq"]) > _bubbled:
			_bubbled = int(m["seq"])
			if App.stage:
				App.stage.say(String(m["uid"]), String(m["text"]))
			if not bool(m["mine"]):
				Sfx.play("pop")
	_paint_chat_badge()


func _paint_chat_badge() -> void:
	if not is_instance_valid(chat_btn):
		return
	var n: int = session.social.chat.unread
	var f := UIKit.face_of(chat_btn)
	f.caption = ("Chat · %d" % n) if n > 0 else "Chat"
	if chat_btn.has_meta(&"caption"):
		chat_btn.set_meta(&"caption", f.caption)
		var vs := get_viewport().get_visible_rect().size
		if vs.x / maxf(1.0, vs.y) < 1.6:
			f.caption = ""
	f.queue_redraw()
	chat_btn.accessibility_name = "Party chat, %d new" % n if n > 0 else "Party chat"


func _exit_tree() -> void:
	# leaving the party room (Wardrobe/Locker, Shop, results, a round): the
	# walk ends here and nothing keeps reading the stick
	if hub != null and is_instance_valid(hub):
		hub.set_walking(false)
		hub.input_allowed = Callable()   # (it refers to this screen)
		hub.stick = Vector2.ZERO
	InputOwner.release("chat")


func _open_wardrobe() -> void:
	if App.stage:
		App.stage.stop_previews()
	var w := CreatorScreen.new()
	w.back_action_override = func() -> void: App.show_lobby()
	App._show(w)


func _on_primary() -> void:
	if session.is_host():
		if session.can_start():
			if App.stage:
				App.stage.stop_previews()
			Diag.mark("round_start")
			session.host_start_match()
		return
	_is_ready = not _is_ready
	session.set_local_ready(_is_ready)
	_refresh()


func _on_status(txt: String) -> void:
	if is_instance_valid(status_lbl) and txt != "":
		status_lbl.text = txt


func _local_key() -> String:
	if session.local_slot >= 0 and session.roster[session.local_slot] != null:
		return String(session.roster[session.local_slot]["uid"])
	return ""


func _refresh() -> void:
	if not is_instance_valid(primary_btn):
		return
	var hosting := session.is_host()
	code_lbl.text = session.room_code if session.room_code != "" else "…"
	invite_btn.visible = hosting and Social.online_ready() and session.transport is GameKitTransport
	var humans := 0
	var not_ready := 0
	var ready_n := 0
	var entries: Array = []
	var order: Array = []
	for i in 8:
		var e: Variant = session.roster[i]
		if e == null:
			continue
		order.append(i)
		if not bool(e["is_bot"]):
			humans += 1
			var counts := bool(e["ready"]) or int(e["slot"]) == 0
			if counts:
				ready_n += 1
			elif i != session.local_slot:
				not_ready += 1
		var ent := {"key": String(e["uid"]), "role": TC.Role.RUNNER, "cosmetic": e["cosmetic"], "name": SocialSafety.name_of(e),
			"is_bot": bool(e["is_bot"]), "local": i == session.local_slot, "ready": bool(e["ready"]) or int(e["slot"]) == 0}
		if i == session.local_slot:
			entries.push_front(ent)
		else:
			entries.append(ent)
	# everyone present, then one open seat (until the party is full)
	var shown := mini(8, order.size() + (1 if order.size() < 8 else 0))
	for ci in cells.size():
		var c: SlotCell = cells[ci]
		c.visible = ci < shown
		if ci < order.size():
			var slot: int = order[ci]
			c.slot = slot
			c.show_entry(SocialSafety.display_entry(session.roster[slot]), slot == session.local_slot, hosting, session.muted, _can_invite(), false)
		elif ci < shown:
			c.slot = -1
			c.show_entry(null, false, hosting, session.muted, _can_invite(), true)
	_grid.columns = 1 if shown <= 2 else 2
	if App.stage:
		App.stage.sync_party(entries)
	_join_leave_notes()
	count_lbl.text = ("Party · %d/8 · %d ready" % [humans, ready_n]) if humans > 1 else "Party · %d/8" % humans
	# settings + series
	_paint_settings()
	var series_on := session.series_active()
	var nxt := session.next_round_number()
	var total := session.rounds_total()
	var view: Dictionary = session.series_view
	if series_on:
		var tally := _tally(view)
		series_lbl.text = "Round %d of %d next  ·  Runners %d – %d Night Watch" % [nxt, total, tally[0], tally[1]]
	series_row.visible = series_on and not (hub != null and hub.walking)
	standings_btn.visible = series_on and not (view.get("standings", {}) as Dictionary).is_empty()
	var bots := 8 - humans
	if hosting:
		primary_btn.text = ("Start round %d" % nxt) if series_on else "Start"
		primary_btn.disabled = not session.can_start()
		var bot_txt := "1 bot" if bots == 1 else "%d bots" % bots
		sub_lbl.text = ("You + " + bot_txt if humans == 1 else "%d players + %s" % [humans, bot_txt]) if bots > 0 else "Full party"
		if humans == 1:
			status_lbl.text = "Share the code, or start now." if not series_on else "Start the next round when you're ready."
		elif not_ready > 0:
			status_lbl.text = "Waiting for %d to tap Ready" % not_ready
		else:
			status_lbl.text = "Everyone's ready"
	else:
		primary_btn.disabled = session.local_slot < 0
		primary_btn.text = "Not ready" if _is_ready else ("Ready for round %d" % nxt if series_on else "Ready")
		UIKit._apply(primary_btn, UIKit.SLATE_HI if _is_ready else UIKit.AMBER, UIKit.IVORY if _is_ready else UIKit.NAVY)
		sub_lbl.text = ""
		if session.host_peer < 0:
			status_lbl.text = "Looking for party %s…" % session.room_code
		else:
			status_lbl.text = "You're ready — waiting for the host" if _is_ready else "Tap Ready when you are"
		# a settings change cleared our ready: say so once
		if session.settings_note != "" and session.settings_note != _last_note:
			_last_note = session.settings_note
			_is_ready = false
			UIKit.toast(self, session.settings_note, 4.0)
			session.settings_note = ""
	# roster updates keep focus on its cell; if the focused control went away
	# (a sheet closed with its player gone), controllers land on the main action
	if Controls.device != "touch" and not has_modal() and get_viewport().gui_get_focus_owner() == null and not (hub != null and hub.walking):
		UIKit.soft_focus.call_deferred(primary_btn)
	if hub != null and hub.walking:
		status_lbl.text = "Drag on the left to walk · Done to stop" if Controls.device == "touch" else "Move to walk · Back to stop"


## "Comfy Frog joined" / "… left" for people (not bots), once per change.
func _join_leave_notes() -> void:
	var now: Dictionary = {}
	for e in session.roster:
		if e != null and not bool(e["is_bot"]):
			now[String(e["uid"])] = SocialSafety.name_of(e)
	var first := _known.is_empty()
	if not first:
		var notes: Array[String] = []
		for uid in now:
			if not _known.has(uid) and uid != _local_key():
				notes.append("%s joined" % now[uid])
		for uid in _known:
			if not now.has(uid):
				notes.append("%s left" % _known[uid])
		if not notes.is_empty():
			UIKit.toast(self, " · ".join(notes), 2.4)
			Sfx.play("pop")
	_known = now


static func _tally(view: Dictionary) -> Array:
	var r := 0
	var w := 0
	for rd in view.get("rounds", []):
		if int(rd.get("outcome", 0)) == TC.Outcome.RUNNERS_WIN:
			r += 1
		elif int(rd.get("outcome", 0)) == TC.Outcome.PATROL_WIN:
			w += 1
	return [r, w]


func _can_invite() -> bool:
	return session.is_host() and Social.online_ready() and session.transport is GameKitTransport


func _on_cell(c: SlotCell) -> void:
	var i := c.slot
	if i < 0:
		if _can_invite():
			_invite()
		else:
			DisplayServer.clipboard_set(session.room_code)
			UIKit.toast(self, "Code %s copied — share it to invite" % session.room_code)
		return
	var e: Variant = session.roster[i]
	if e == null:
		return
	_player_popover(i, c)


func _emote_popover(anchor: Control) -> void:
	var v := UIKit.vbox(12)
	v.add_child(UIKit.styled("Emote", "headline"))
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 10)
	for i in TC.EMOTES.size():
		var idx := i
		g.add_child(icon_tile(Icons.emote_icon(i), String(TC.EMOTE_LABELS[TC.EMOTES[i]]), func() -> void:
			close_popover()
			_send_emote(idx)))
	v.add_child(g)
	if not (hub != null and hub.walking):
		var tm := UIKit.quiet("Try moves (just on your screen)", Vector2(0, 64), UIKit.T_CAPTION)
		tm.pressed.connect(func() -> void:
			close_popover()
			_moves_popover(anchor))
		v.add_child(tm)
	popover_at(anchor, v)


## Play an emote: shown on our own runner at once (a guest's request still
## goes through the host, which tells everyone; our echo is skipped).
func _send_emote(id: int) -> void:
	var key := _local_key()
	if key == "" or App.stage == null:
		UIKit.toast(self, "Emotes show once you're in the party room.")
		return
	if session.is_host():
		session.send_emote(id)   # the host's own event comes straight back and plays it
	else:
		if App.stage.emote(key, id):
			Sfx.play("pop")
		_predicted = {"id": id, "t": Time.get_ticks_msec() / 1000.0}
		session.send_emote(id)
	Diag.mark("emote")


func _moves_popover(anchor: Control) -> void:
	var v := UIKit.vbox(12)
	v.add_child(UIKit.styled("Try moves", "headline"))
	v.add_child(UIKit.styled("Just on your screen", "caption", UIKit.IVORY_MUTED))
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 10)
	var mine := String(Cosmetics.sanitize(Save.data["cosmetic"]).get("emote", "wave"))
	for m in [["m_idle", "Idle", "idle"], ["m_run", "Run", "run"], ["m_run", "Sprint", "sprint"], ["m_jump", "Jump", "jump"], ["m_dive", "Dive", "dive"],
			["e_" + mine, "Your move", "move"]]:
		var kind: String = m[2]
		g.add_child(icon_tile(String(m[0]), String(m[1]), func() -> void:
			close_popover()
			_try_move(kind)))
	v.add_child(g)
	popover_at(anchor, v)


func _try_move(kind: String) -> void:
	var key := _local_key()
	if key == "" or App.stage == null:
		return
	if kind == "move":
		_play_own_move()
	else:
		App.stage.preview_move(key, kind)


## Tap your own runner (or Your move): your signature move, for everyone.
func _play_own_move() -> void:
	var mine := String(Cosmetics.sanitize(Save.data["cosmetic"]).get("emote", "wave"))
	var id := TC.EMOTES.find(mine)
	_send_emote(id if id >= 0 else 0)


## A tap on the room that no control took: on your own runner, it plays your
## move.  (Touch arrives as an emulated mouse press too; only that is used,
## so one tap is one action.)  Positions and the camera projection are both
## in the viewport's canvas units.
func _unhandled_input(ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton) or not (ev as InputEventMouseButton).pressed or (ev as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		super(ev)
		return
	if App.stage == null or has_modal() or not is_visible_in_tree() or (hub != null and hub.walking):
		return
	if hit_own_runner((ev as InputEventMouseButton).position):
		_play_own_move()
		get_viewport().set_input_as_handled()


func hit_own_runner(at: Vector2) -> bool:
	var v := App.stage.local_character() if App.stage else null
	if v == null or App.stage.cam == null or not v.visible:
		return false
	var head := App.stage.cam.unproject_position(v.global_position + Vector3(0, 1.45, 0))
	var feet := App.stage.cam.unproject_position(v.global_position)
	var h := absf(feet.y - head.y)
	return Rect2(Vector2(head.x - h * 0.42, head.y - h * 0.1), Vector2(h * 0.84, h * 1.15)).has_point(at)


func _settings_sheet() -> void:
	var host := session.is_host() and session.mode != NetSession.Mode.OFFLINE
	var locked := session.series_active()
	var v := UIKit.vbox(12)
	v.custom_minimum_size = Vector2(560, 0)
	v.add_child(UIKit.styled("Party settings", "headline"))
	if not host:
		v.add_child(UIKit.styled("Set by the host", "caption", UIKit.IVORY_MUTED))
	elif locked:
		v.add_child(UIKit.styled("Locked for this series (round %d of %d is next)." % [session.next_round_number(), session.rounds_total()], "caption", UIKit.IVORY_MUTED))
	var cur := session.settings.duplicate()
	var rows := []
	var notes := {}
	for spec in [["Night Watch", "watch", [[1, "1"], [2, "2"], [3, "3"]], "More Night Watch is tougher for runners."],
			["Rounds", "rounds", [[1, "1"], [3, "3"], [5, "5"]], "Most Round Wins takes the series."]]:
		v.add_child(UIKit.styled(String(spec[0]), "overline", UIKit.IVORY_MUTED))
		var row := UIKit.hbox(10)
		var btns: Array[Button] = []
		for o in spec[2]:
			var b := UIKit.quiet(String(o[1]), Vector2(150, 68))
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.disabled = not host or locked
			var key: String = spec[1]
			var val: int = o[0]
			b.pressed.connect(func() -> void:
				cur[key] = val
				session.host_set_settings(int(cur["watch"]), int(cur["rounds"]))
				cur = session.settings.duplicate()
				_paint_choices(rows, cur, notes)
				_refresh())
			row.add_child(b)
			btns.append(b)
		rows.append([spec[1], spec[2], btns])
		v.add_child(row)
		var note := UIKit.styled(String(spec[3]), "caption", UIKit.IVORY_MUTED)
		notes[spec[1]] = note
		v.add_child(note)
	var line := UIKit.styled("", "label", UIKit.AMBER)
	notes["line"] = line
	v.add_child(line)
	_paint_choices(rows, cur, notes)
	var foot := UIKit.hbox(10)
	if host and not locked:
		var reset := UIKit.quiet("Reset to recommended", Vector2(300, 68))
		reset.pressed.connect(func() -> void:
			session.host_set_settings(PartySeries.DEFAULT_WATCH, PartySeries.DEFAULT_ROUNDS)
			cur = session.settings.duplicate()
			_paint_choices(rows, cur, notes)
			_refresh())
		foot.add_child(reset)
	if host and locked:
		var endb := UIKit.quiet("End series", Vector2(240, 68))
		endb.pressed.connect(func() -> void:
			close_popover()
			dialog("End this series now? Rounds already played still count; there's no prize for the rest.", [["End series", func() -> void:
				session.host_end_series()
				App.show_series_final()], ["Keep playing", Callable()]]))
		foot.add_child(endb)
	foot.add_child(UIKit.spacer_h())
	var done := UIKit.secondary("Done", Vector2(180, 68))
	done.pressed.connect(close_popover)
	foot.add_child(done)
	v.add_child(foot)
	popover_at(settings_btn, v, "below")


func _paint_choices(rows: Array, cur: Dictionary, notes: Dictionary = {}) -> void:
	for r in rows:
		var key: String = r[0]
		var opts: Array = r[1]
		var btns: Array = r[2]
		for i in btns.size():
			var b: Button = btns[i]
			if is_instance_valid(b):
				UIKit.set_selected(b, int(opts[i][0]) == int(cur.get(key, -1)))
	if notes.has("line") and is_instance_valid(notes["line"]):
		var w := int(cur.get("watch", PartySeries.DEFAULT_WATCH))
		(notes["line"] as Label).text = "%d runners · %d home to win" % [PartySeries.runners(w), PartySeries.required_home(w)]


func _standings_sheet() -> void:
	var v := UIKit.vbox(10)
	v.custom_minimum_size = Vector2(560, 0)
	v.add_child(UIKit.styled("Standings", "headline"))
	v.add_child(ResultsScreen.standings_table(session.series_view, Save.player_uid()))
	var done := UIKit.secondary("Close", Vector2(180, 68))
	done.pressed.connect(close_popover)
	v.add_child(done)
	popover_at(standings_btn, v, "below")


## Player details: the full name, status and the actions for that player.
## Your own card: your move and the wardrobe.  Bots: who they are.
func _player_popover(i: int, anchor: Control) -> void:
	var e: Dictionary = session.roster[i]
	var uid := String(e["uid"])
	var pid := String(e.get("pid", ""))
	var me := i == session.local_slot
	var v := UIKit.vbox(10)
	v.custom_minimum_size = Vector2(380, 0)
	var head := UIKit.hbox(14)
	var av := Avatar.new()
	av.custom_minimum_size = Vector2(88, 88)
	av.set_entry(e["cosmetic"], int(e.get("role", -1)), "sheet")
	head.add_child(av)
	var nv := UIKit.vbox(2)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nm := UIKit.styled(String(e["name"]), "headline")
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.custom_minimum_size = Vector2(250, 0)
	nv.add_child(nm)
	var st := "Host" if int(e["slot"]) == 0 else ("Bot" if bool(e["is_bot"]) else ("Ready" if bool(e["ready"]) else "In the party"))
	nv.add_child(UIKit.styled(("You · " if me else "") + st, "caption", UIKit.IVORY_MUTED))
	head.add_child(nv)
	v.add_child(head)
	if me:
		var mv := UIKit.secondary("Play your move", Vector2(340, 72))
		mv.pressed.connect(func() -> void:
			close_popover()
			_play_own_move())
		v.add_child(mv)
		var wb := UIKit.quiet("Wardrobe", Vector2(340, 72))
		wb.pressed.connect(func() -> void:
			close_popover()
			_open_wardrobe())
		v.add_child(wb)
		popover_at(anchor, v, "left")
		return
	if bool(e["is_bot"]):
		v.add_child(UIKit.styled("Bots fill empty seats. A friend who joins takes this seat.", "caption", UIKit.IVORY_MUTED))
		popover_at(anchor, v, "left")
		return
	var muted := session.muted.has(uid)
	var mb := UIKit.secondary("Unmute" if muted else "Mute (chat and emotes)", Vector2(340, 72))
	mb.pressed.connect(func() -> void:
		SocialActions.toggle_mute(session, uid)
		close_popover()
		_refresh())
	v.add_child(mb)
	var rb := UIKit.secondary("Report…", Vector2(340, 72))
	rb.pressed.connect(func() -> void:
		close_popover()
		_report(e))
	v.add_child(rb)
	var bb := UIKit.quiet("Block", Vector2(340, 72))
	bb.pressed.connect(func() -> void:
		close_popover()
		dialog("Block %s? You won't see their chat, emotes or name, you won't be put in parties together, and they can't join yours." % SocialSafety.name_of(e),
			[["Block", func() -> void: _block(e, i)], ["Cancel", Callable()]]))
	v.add_child(bb)
	if session.is_host():
		var kb := UIKit.quiet("Remove from party", Vector2(340, 72))
		kb.pressed.connect(func() -> void:
			close_popover()
			dialog("Remove %s from the party?" % e["name"], [["Remove", func() -> void:
				if pid != "" and App.party_code != "":
					Cloud.kick_from_room(App.party_code, pid)
				session.kick(i)], ["Cancel", Callable()]]))
		v.add_child(kb)
	popover_at(anchor, v, "left")


const REPORT_REASONS := [["name", "Offensive name"], ["harassment", "Harassment or bullying"], ["cheating", "Cheating"],
	["inappropriate", "Inappropriate behaviour"], ["other", "Something else"]]


## (V6) The report sheet: honest states, a receipt only from the service.
func _report(e: Dictionary) -> void:
	ReportSheet.open(self, {"kind": "player", "name": SocialSafety.name_of(e), "pid": String(e.get("pid", "")),
		"context": {"room_code": session.room_code, "build": App.build_number()}})


func _block(e: Dictionary, slot: int) -> void:
	var d := e.duplicate()
	d["slot"] = slot
	var note: String = await SocialActions.block(session, d)
	if is_inside_tree():
		UIKit.toast(self, note)
		_refresh()


func _on_events(evs: Array) -> void:
	for ev in evs:
		if int(ev["type"]) != TC.Ev.EMOTE:
			continue
		var a := int(ev["a"])
		if a < 0 or a >= 8 or session.roster[a] == null:
			continue
		var who: Dictionary = session.roster[a]
		if SocialSafety.is_hidden(session, String(who.get("uid", "")), String(who.get("pid", ""))):   # muted or blocked
			continue
		var now := Time.get_ticks_msec() / 1000.0
		if a == session.local_slot and not session.is_host() and int(ev["v"]) == int(_predicted["id"]) and now - float(_predicted["t"]) < 2.0:
			_predicted = {"id": -1, "t": -10.0}
			continue   # our own emote, already showing (no second start or sound)
		if App.stage and App.stage.emote(String(who["uid"]), int(ev["v"])):
			Sfx.play("pop")


func _invite() -> void:
	if session.transport is GameKitTransport:
		Social.invite_friends(session.transport, session.room_code)


## A round portrait on a soft disc in the player's colour (cached portrait
## atlas; no live viewport per card).
class Avatar:
	extends Control
	var tex: Texture2D
	var col := Color(0.3, 0.4, 0.6)
	var _key := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(56, 56)

	func set_entry(cosmetic: Variant, role: int, tag: String) -> void:
		var r := TC.Role.PATROL if role == TC.Role.PATROL else TC.Role.RUNNER
		col = Cosmetics.color_of(cosmetic)
		var key := Portraits.key_of(Cosmetics.sanitize(cosmetic), r)
		if key != _key:
			_key = key
			var ps := Portraits.shared()
			tex = ps.portrait(cosmetic, r, tag)
			if not ps.portrait_ready.is_connected(_on_portrait):
				ps.portrait_ready.connect(_on_portrait)
				ps.portrait_evicted.connect(_on_evicted)
		queue_redraw()

	func clear() -> void:
		_key = ""
		tex = null
		queue_redraw()

	func _on_portrait(k: String, t: Texture2D) -> void:
		if k == _key:
			tex = t
			queue_redraw()

	## Our portrait's atlas cell went to another look: ask again next update.
	func _on_evicted(k: String) -> void:
		if k == _key:
			_key = ""

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, col.darkened(0.45))
		draw_circle(c, r * 0.93, col.darkened(0.2).lerp(UIKit.SLATE_HI, 0.35))
		if tex:
			draw_texture_rect(tex, Rect2(c - Vector2(r, r) * 1.02, Vector2(r, r) * 2.04), false)


## One roster card (contents updated in place): portrait, name, status and
## a status badge.  The card is the hit region; its face draws and presses.
class SlotCell:
	extends Button
	var slot := 0
	var face: Avatar
	var name_l: Label
	var sub_l: Label
	var badge: Icons.IconRect
	var _me := false

	func _init() -> void:
		# names up to 16 characters fit whole at 20 units in this width; the
		# status badge sits in the second line, not in a column of its own
		UIKit.make_card(self, Vector2(272, maxf(72.0, UIKit.touch_min())), Color(UIKit.SLATE, 0.95))
		var h := UIKit.hbox(10)
		h.set_anchors_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 10
		h.offset_right = -12
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UIKit.face_of(self).add_child(h)
		face = Avatar.new()
		face.custom_minimum_size = Vector2(52, 52)
		face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(face)
		var v := UIKit.vbox(0)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(v)
		name_l = UIKit.styled("", "label")
		name_l.custom_minimum_size = Vector2(60, 0)
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UIKit.fit_text(name_l, [UIKit.T_LABEL, UIKit.T_CAPTION, 18])
		v.add_child(name_l)
		var row := UIKit.hbox(5)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(row)
		badge = Icons.IconRect.new("check", UIKit.TEAL, 18)
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(badge)
		sub_l = UIKit.styled("", "caption", UIKit.IVORY_MUTED)
		sub_l.add_theme_font_size_override("font_size", 18)
		sub_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sub_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		sub_l.clip_text = true
		sub_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(sub_l)

	func _style(me: bool, open: bool) -> void:
		var f := UIKit.face_of(self)
		if open:
			var n := UIKit.box(Color(UIKit.NAVY, 0.45), UIKit.R_CARD, 2, Color(UIKit.IVORY, 0.14))
			f.styles = {"normal": n, "hover": UIKit._with_bg(n, Color(UIKit.SLATE, 0.6)), "pressed": UIKit._with_bg(n, Color(UIKit.SLATE_LO, 0.8)),
				"disabled": n, "selected": n}
		else:
			var bg := Color(UIKit.SLATE_HI, 0.97) if me else Color(UIKit.SLATE, 0.95)
			var n := UIKit.card_box(bg, UIKit.R_CARD, 1.0)
			if me:
				n.set_border_width_all(2)
				n.border_color = Color(UIKit.AMBER, 0.85)
			f.styles = {"normal": n, "hover": UIKit._with_bg(n, bg.lightened(0.05)), "pressed": UIKit.card_box(bg.darkened(0.08), UIKit.R_CARD, 0.0),
				"disabled": n, "selected": n}
		f.queue_redraw()

	func show_entry(e: Variant, me: bool, _hosting: bool, muted: Dictionary, can_invite: bool, first_open: bool = false) -> void:
		_me = me
		if e == null:
			_style(false, true)
			face.clear()
			face.col = Color(UIKit.IVORY, 0.12)
			name_l.text = "Invite" if can_invite else "Open seat"
			name_l.add_theme_color_override("font_color", Color(UIKit.IVORY, 0.6))
			sub_l.text = ("Invite a friend" if can_invite else "Share the code") if first_open else ""
			badge.kind = "plus"
			badge.col = Color(UIKit.IVORY, 0.45)
			badge.queue_redraw()
			accessibility_name = name_l.text
			UIKit.refit(name_l)
			return
		var ent: Dictionary = e
		_style(me, false)
		face.set_entry(ent["cosmetic"], int(ent.get("role", -1)), "cell%d" % get_instance_id())
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
		if muted.has(String(ent["uid"])):
			bits.append("emotes hidden")
		sub_l.text = " · ".join(bits)
		var ok := bool(ent["ready"]) or host_slot or bool(ent["is_bot"])
		badge.kind = "crown" if host_slot else ("bot" if bool(ent["is_bot"]) else ("check" if ok else "smile"))
		badge.col = UIKit.AMBER if host_slot else (UIKit.TEAL if ok else Color(UIKit.IVORY, 0.35))
		badge.queue_redraw()
		accessibility_name = "%s, %s" % [name_l.text, sub_l.text]
		UIKit.refit(name_l)
