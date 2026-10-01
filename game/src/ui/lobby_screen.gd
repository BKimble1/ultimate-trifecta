class_name LobbyScreen
extends Screen
## Dorm common room lobby. A static roster list is always shown (accessible
## fallback) next to the 3D room. Host: invite, start (bots fill empty slots,
## clearly labelled). Everyone: ready, role preference, emotes, wardrobe, mute.

var session: NetSession
var room: Preview3D
var roster_box: VBoxContainer
var code_lbl: Label
var status_lbl: Label
var ready_btn: Button
var start_btn: Button
var pref_opt: OptionButton
var invite_btn: Button
var _is_ready := false
var _room_built := false
var _chars: Dictionary = {}


func build() -> void:
	back_action = func() -> void: dialog("Leave this room?", [["Leave", func() -> void: App.leave_room()], ["Stay", Callable()]])
	var top := UIKit.hbox(18)
	content.add_child(top)
	var leave := UIKit.button("‹ Leave", Color(0.22, 0.26, 0.48), Vector2(150, 60), 24)
	leave.pressed.connect(_go_back)
	top.add_child(leave)
	code_lbl = UIKit.outlined(UIKit.label("", 42, UIKit.ACCENT, true), 10)
	top.add_child(code_lbl)
	invite_btn = UIKit.button("Invite Friends", Color(0.35, 0.75, 0.95), Vector2(260, 60), 24)
	invite_btn.pressed.connect(_invite)
	top.add_child(invite_btn)
	status_lbl = UIKit.label("", 22, UIKit.MUTED)
	status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(status_lbl)

	var mid := UIKit.hbox(20)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(mid)
	room = Preview3D.new(Vector2i(560, 420))
	room.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(room)
	var rp := UIKit.panel(Color(0.12, 0.15, 0.32, 0.92), 24, 14)
	rp.custom_minimum_size = Vector2(520, 0)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(500, 380)
	sc.follow_focus = true
	roster_box = UIKit.vbox(6)
	roster_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(roster_box)
	rp.add_child(sc)
	mid.add_child(rp)

	var bottom := UIKit.hbox(14)
	content.add_child(bottom)
	pref_opt = OptionButton.new()
	for p in ["Play as: Any role", "Play as: Runner", "Play as: Night Watch"]:
		pref_opt.add_item(p)
	pref_opt.selected = ["any", "runner", "patrol"].find(session.local_pref)
	pref_opt.custom_minimum_size = Vector2(300, 64)
	pref_opt.item_selected.connect(func(i: int) -> void:
		var p: String = ["any", "runner", "patrol"][i]
		Save.set_setting("role_pref", p)
		session.set_local_pref(p))
	bottom.add_child(pref_opt)
	ready_btn = UIKit.button("Ready!", Color(0.45, 0.9, 0.55), Vector2(220, 64))
	ready_btn.pressed.connect(func() -> void:
		_is_ready = not _is_ready
		session.set_local_ready(_is_ready)
		_refresh())
	bottom.add_child(ready_btn)
	var ward := UIKit.button("Outfit", Color(0.75, 0.5, 0.95), Vector2(160, 64), 24)
	ward.pressed.connect(_quick_outfit)
	bottom.add_child(ward)
	for i in 4:
		var e := UIKit.button(TC.EMOTE_LABELS[TC.EMOTES[i]], Color(0.3, 0.38, 0.7), Vector2(120, 64), 20)
		var idx := i
		e.pressed.connect(func() -> void: session.send_emote(idx))
		bottom.add_child(e)
	start_btn = UIKit.button("Start", Color(1.0, 0.72, 0.25), Vector2(260, 64), 30)
	start_btn.pressed.connect(func() -> void:
		if session.can_start():
			session.host_start_match())
	bottom.add_child(start_btn)
	focus_first(ready_btn)
	session.lobby_changed.connect(_refresh)
	session.status_changed.connect(func(t: String) -> void: status_lbl.text = t)
	session.events_received.connect(_on_events)
	_build_room()
	_refresh()


func _build_room() -> void:
	var k := MeshKit.new()
	var floor_c := Color(0.55, 0.38, 0.28)
	k.box(Vector3(0, -0.05, 0), Vector3(14, 0.1, 9), floor_c)
	k.box(Vector3(0, -0.02, 0.5), Vector3(7, 0.05, 4.5), Color(0.75, 0.3, 0.35))
	k.box(Vector3(0, 2.0, -4.0), Vector3(14, 4.2, 0.3), Color(0.45, 0.5, 0.7))
	k.box(Vector3(-6.5, 2.0, 0), Vector3(0.3, 4.2, 9), Color(0.42, 0.47, 0.66))
	k.box(Vector3(6.5, 2.0, 0), Vector3(0.3, 4.2, 9), Color(0.42, 0.47, 0.66))
	for wx in [-3.5, 0.0, 3.5]:
		k.box(Vector3(wx, 2.3, -3.82), Vector3(2.0, 1.6, 0.05), Color(0.12, 0.16, 0.38))
		k.box(Vector3(wx, 2.3, -3.8), Vector3(0.08, 1.6, 0.06), Color(0.9, 0.88, 0.8))
		k.blob(Vector3(wx + 0.5, 2.7, -3.79), Vector3(0.12, 0.12, 0.02), Color(1.0, 0.98, 0.85), 2, 6, 2.0)
	# couch, lamp, string lights, posters, pizza box
	k.box(Vector3(-4.2, 0.35, -2.6), Vector3(3.2, 0.7, 1.2), Color(0.3, 0.5, 0.75))
	k.box(Vector3(-4.2, 0.85, -3.1), Vector3(3.2, 0.7, 0.3), Color(0.28, 0.46, 0.7))
	k.cylinder(Vector3(4.8, 0, -3.0), 0.08, 1.8, Color(0.2, 0.2, 0.25), 6)
	k.cone(Vector3(4.8, 1.7, -3.0), 0.45, 0.5, Color(1.0, 0.85, 0.55), 8, 1.2)
	for i in 14:
		var x := -6.0 + float(i) * 0.92
		k.blob(Vector3(x, 3.7 - 0.15 * sin(float(i) * 0.9), -3.75), Vector3(0.07, 0.07, 0.07), [Color(1, 0.5, 0.5), Color(1, 0.9, 0.4), Color(0.5, 0.9, 1)][i % 3], 2, 5, 3.0)
	k.box(Vector3(-1.8, 2.4, -3.82), Vector3(0.9, 1.2, 0.03), Color(1.0, 0.8, 0.3), 0.0, 0.2)
	k.box(Vector3(1.8, 2.4, -3.82), Vector3(0.9, 1.2, 0.03), Color(0.5, 0.85, 1.0), 0.0, 0.2)
	k.box(Vector3(3.6, 0.06, 1.8), Vector3(0.7, 0.08, 0.7), Color(0.9, 0.85, 0.75))
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit()
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/shaders/world_vc.gdshader")
	mi.material_override = m
	room.stage.add_child(mi)
	var warm := OmniLight3D.new()
	warm.position = Vector3(4.6, 1.8, -2.6)
	warm.light_color = Color(1.0, 0.8, 0.55)
	warm.light_energy = 2.2
	warm.omni_range = 9.0
	room.stage.add_child(warm)
	room.cam.fov = 52
	room.aim(Vector3(0, 2.4, 6.2), Vector3(0, 1.0, -0.5))
	_room_built = true


func _refresh() -> void:
	if not is_instance_valid(roster_box):
		return
	var hosting := session.is_host()
	code_lbl.text = "ROOM  %s" % session.room_code if session.room_code != "" else "Finding room…"
	invite_btn.visible = Social.online_ready() and session.transport is GameKitTransport and hosting
	for c in roster_box.get_children():
		c.queue_free()
	var humans := 0
	var all_ready := true
	for i in 8:
		var e: Variant = session.roster[i]
		var row := UIKit.hbox(8)
		if e == null:
			row.add_child(UIKit.label("·  Open slot (a bot fills it if empty at start)", 20, UIKit.MUTED))
			roster_box.add_child(row)
			continue
		var is_bot: bool = e["is_bot"]
		if not is_bot:
			humans += 1
		var me := i == session.local_slot
		var mark := "✓" if bool(e["ready"]) or (i == 0 and hosting) else "…"
		var name := String(e["name"]) + ("  (you)" if me else "") + ("  [BOT]" if is_bot else "")
		if not bool(e["connected"]):
			name += "  (reconnecting)"
		var pref: String = {"any": "", "runner": " · prefers Runner", "patrol": " · prefers Night Watch"}.get(String(e["pref"]), "")
		var l := UIKit.label("%s  %s%s" % [mark, name, pref], 22, UIKit.GOOD if mark == "✓" else UIKit.TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if not me and not is_bot:
			if not bool(e["ready"]) and i != 0:
				all_ready = false
			var muted := session.muted.has(String(e["uid"]))
			var mb := UIKit.button("Unmute" if muted else "Mute", Color(0.3, 0.32, 0.5), Vector2(110, 48), 18)
			var uid := String(e["uid"])
			mb.pressed.connect(func() -> void:
				if session.muted.has(uid):
					session.muted.erase(uid)
				else:
					session.muted[uid] = true
				_refresh())
			row.add_child(mb)
			if hosting:
				var kb := UIKit.button("Remove", Color(0.6, 0.3, 0.3), Vector2(120, 48), 18)
				var slot := i
				kb.pressed.connect(func() -> void: dialog("Remove %s from the room?" % e["name"], [["Remove", func() -> void: session.kick(slot)], ["Cancel", Callable()]]))
				row.add_child(kb)
		roster_box.add_child(row)
	var spec := int(session.get_meta("spectators", 0)) if session.has_meta("spectators") else session.spectators.size()
	if spec > 0:
		roster_box.add_child(UIKit.label("+%d waiting for the next round" % spec, 20, UIKit.MUTED))
	ready_btn.text = "Not ready" if _is_ready else "Ready!"
	ready_btn.visible = not hosting
	start_btn.visible = hosting
	var bots := 8 - humans
	start_btn.text = "Start (%d bot%s fill in)" % [bots, "" if bots == 1 else "s"] if bots > 0 else "Start"
	start_btn.disabled = not session.can_start()
	if hosting:
		status_lbl.text = "Share the code. Start when everyone is ready." if all_ready else "Waiting for everyone to tap Ready…"
		if humans == 1:
			status_lbl.text = "Share the code or invite friends. You can also start now with bots."
	elif session.host_peer < 0:
		status_lbl.text = "Looking for room %s…" % session.room_code
	else:
		status_lbl.text = "Waiting for the host to start…" if _is_ready else "Tap Ready when you are."
	_refresh_room()


func _refresh_room() -> void:
	if not _room_built:
		return
	room.clear()
	var present: Array = []
	for i in 8:
		if session.roster[i] != null:
			present.append(i)
	var n := present.size()
	for k in n:
		var i: int = present[k]
		var e: Dictionary = session.roster[i]
		var x := (float(k) - float(n - 1) * 0.5) * 1.5
		var z := 0.4 + 0.5 * absf(float(k) - float(n - 1) * 0.5) * 0.4
		var v := room.show_character(TC.Role.RUNNER, e["cosmetic"], Vector3(x, 0, z), -x * 0.08)
		v.name_label.visible = true
		v.name_label.text = String(e["name"]) + (" [BOT]" if bool(e["is_bot"]) else "")
		v.name_label.font_size = 28
		_chars[i] = v


func _on_events(evs: Array) -> void:
	for ev in evs:
		if int(ev["type"]) == TC.Ev.EMOTE and _chars.has(int(ev["a"])):
			var who: Dictionary = session.roster[int(ev["a"])] if session.roster[int(ev["a"])] != null else {}
			if session.muted.has(String(who.get("uid", ""))):
				continue
			var v: CharacterView = _chars[int(ev["a"])]
			if is_instance_valid(v):
				var rs := v.rs.duplicate()
				rs["emote"] = int(ev["v"])
				rs["emote_t"] = 1.0
				v.apply_state(rs, 0.0, true)
				get_tree().create_timer(1.8).timeout.connect(func() -> void:
					if is_instance_valid(v):
						var r2 := v.rs.duplicate()
						r2["emote"] = -1
						r2["emote_t"] = 0.0
						v.apply_state(r2, 0.0, true))
				Sfx.play("pop")


func _invite() -> void:
	if session.transport is GameKitTransport:
		Social.invite_friends(session.transport, session.room_code)


func _quick_outfit() -> void:
	# cycle through owned outfits quickly; full wardrobe is on the title screen
	var owned: Array = []
	for id in Cosmetics.OUTFITS:
		if Save.owns("outfit", id):
			owned.append(id)
	var cur := String(Save.data["cosmetic"]["outfit"])
	var nxt: String = owned[(owned.find(cur) + 1) % owned.size()]
	Save.equip("outfit", nxt)
	session.set_local_cosmetic(Save.data["cosmetic"])
