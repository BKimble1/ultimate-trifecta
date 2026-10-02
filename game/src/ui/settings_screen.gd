class_name SettingsScreen
extends Screen
## Settings, grouped: Profile (name, sign-in, blocked players, Delete Game
## Profile), Controls (a small touch set), Camera & comfort, Graphics, Sound,
## Privacy & credits.  Everything saves immediately.

var _rows: Dictionary = {}
var _acct: VBoxContainer


func build() -> void:
	if App.stage:
		App.stage.set_mode("home")
	header("Settings")
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	content.add_child(sc)
	# an opaque sheet over a dimmed room (no translucent slab)
	var dim := ColorRect.new()
	dim.color = Color(UIKit.NAVY, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	move_child(dim, 0)
	var body := UIKit.panel(Color(UIKit.SLATE, 0.99), UIKit.R_PANEL, 26)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(body)
	var v := UIKit.vbox(14)
	body.add_child(v)

	_section(v, "Profile")
	_acct = UIKit.vbox(12)
	v.add_child(_acct)
	_fill_account()
	Cloud.changed.connect(_fill_account)

	_section(v, "Controls")
	var first := _slider(v, "Camera sensitivity", "sensitivity", 0.3, 2.5, 0.05)
	_choice(v, "Movement stick", "stick_mode", [["dynamic", "Appears where you touch"], ["fixed", "Fixed position"]])
	_choice(v, "Sprint", "sprint_mode", [["edge", "Push the stick to the edge"], ["hold", "Hold a Sprint button"]])
	var lrow := UIKit.hbox(14)
	lrow.add_child(UIKit.label("Touch layout", 22, UIKit.IVORY))
	var tl := TouchControls.saved_layout()
	var custom := not (tl["move"] as Array).is_empty() or not (tl["action"] as Dictionary).is_empty()
	var lsum := UIKit.label("%s · size %d%% · %s" % ["Mirrored" if bool(tl["mirror"]) else "Standard", int(round(float(tl["size"]) * 100.0)),
		"your positions" if custom else "recommended positions"], 19, UIKit.IVORY_MUTED)
	lsum.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lrow.add_child(lsum)
	var edit := UIKit.secondary("Edit layout", Vector2(220, 64), 22)
	edit.pressed.connect(func() -> void: App.goto(TouchLayoutEditor))
	lrow.add_child(edit)
	v.add_child(lrow)
	_check(v, "Vibration (haptics)", "haptics", true)
	var prow := UIKit.hbox(12)
	var try_b := UIKit.secondary("Try in Practice", Vector2(260, 72), 22)
	try_b.pressed.connect(func() -> void: App.start_practice("runner", false))
	prow.add_child(try_b)
	var reset := UIKit.quiet("Reset controls", Vector2(240, 72), 22)
	reset.pressed.connect(func() -> void:
		var d: Dictionary = Save.default_profile()["settings"]
		for k in ["sensitivity", "invert_y", "reduced_motion", "sprint_threshold", "touch_sprint", "stick_mode", "sprint_mode", "button_size", "touch_layout", "haptics"]:
			Save.set_setting(k, d[k])
		Save.set_setting("touch_layout_v2", TouchLayout.default_layout())
		App.goto(SettingsScreen))
	prow.add_child(reset)
	v.add_child(prow)
	var ctl := UIKit.label("Controller: " + (Controls.controller_name if Controls.has_controller() else "none connected (touch controls active)"), 19, UIKit.IVORY_MUTED)
	v.add_child(ctl)
	Controls.controller_connection_changed.connect(_on_controller.bind(ctl))

	_section(v, "Camera & comfort")
	_check(v, "Invert camera up/down", "invert_y", false)
	_check(v, "Reduced motion (calmer camera, no look-ahead, fades instead of slides)", "reduced_motion", false)

	_section(v, "Graphics")
	_choice(v, "Quality", "quality", [[1, "Standard (60 fps target)"], [0, "Battery Saver"]])
	var qn := UIKit.label("Battery Saver renders the world at a lower internal resolution with simpler shadows and effects, and caps the frame rate at 30. Text and buttons stay sharp in both.", 18, UIKit.IVORY_MUTED)
	qn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(qn)

	_section(v, "Diagnostics (beta)")
	_diag_section(v)

	_section(v, "Sound")
	_slider(v, "Sound effects", "sfx", 0.0, 1.0, 0.05)
	_slider(v, "Music", "music", 0.0, 1.0, 0.05)

	_section(v, "Privacy")
	var priv := UIKit.label(_privacy_text(), 18, UIKit.IVORY_MUTED)
	priv.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(priv)
	# the owner's real links only (from the service); nothing shown until set
	var links := UIKit.hbox(12)
	for l in [["privacy_url", "Privacy policy"], ["support_url", "Support"]]:
		var url := Cloud.link(String(l[0]))
		if url != "":
			var lb := UIKit.quiet(String(l[1]), Vector2(240, 64), 20)
			lb.pressed.connect(func() -> void: OS.shell_open(url))
			links.add_child(lb)
	if links.get_child_count() > 0:
		v.add_child(links)
	else:
		links.free()
	_section(v, "How to play")
	var how := UIKit.quiet("Open the rules card", Vector2(320, 72), 22)
	how.pressed.connect(func() -> void: App.goto(HowToScreen))
	v.add_child(how)
	_section(v, "Credits & licenses")
	var cred := UIKit.label("Made with Godot Engine (MIT). Game Center bindings: GodotApplePlugins (MIT). Fonts: Manrope (SIL OFL 1.1); the startup mark's descriptor is outlined DejaVu Sans (Bitstream Vera licence). Characters built with Blender's Python module (the generated model is original). All characters, campus, sounds and music are original to Ultimate Trifecta. Moonbrook College is fictional.", 18, UIKit.IVORY_MUTED)
	cred.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(cred)
	v.add_child(UIKit.label("Version %s" % ProjectSettings.get_setting("application/config/version", "1.0"), 16, UIKit.IVORY_MUTED))
	focus_first(first)
	_open_at_top(sc)


## Opt-in performance diagnostics for the internal beta: collected in memory
## only, shared as plain text through the share sheet when the player asks.
func _diag_section(v: VBoxContainer) -> void:
	var on := CheckButton.new()
	on.text = "Collect performance diagnostics"
	on.button_pressed = Diag.enabled
	on.custom_minimum_size = Vector2(0, maxf(44.0, UIKit.touch_min()))
	on.add_theme_font_size_override("font_size", 22)
	v.add_child(on)
	var ov := CheckButton.new()
	ov.text = "Show a small frame-time readout"
	ov.button_pressed = Diag.overlay
	ov.disabled = not Diag.enabled
	ov.custom_minimum_size = Vector2(0, maxf(44.0, UIKit.touch_min()))
	ov.add_theme_font_size_override("font_size", 22)
	v.add_child(ov)
	var live := UIKit.label("", 18, UIKit.IVORY_MUTED)
	live.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(live)
	var row := UIKit.hbox(12)
	var share := UIKit.secondary("Share summary", Vector2(260, 72), 22)
	share.disabled = not Diag.enabled
	share.pressed.connect(func() -> void:
		var txt: String = Diag.summary()
		if not Share.share_text(txt):
			UIKit.toast(self, "Summary copied — paste it into a message"))
	row.add_child(share)
	var clr := UIKit.quiet("Clear", Vector2(180, 72), 22)
	clr.disabled = not Diag.enabled
	clr.pressed.connect(func() -> void:
		Diag.clear()
		_diag_live(live))
	row.add_child(clr)
	v.add_child(row)
	var note := UIKit.label("While this is on, the game keeps frame timings, short notes such as \"lobby\", \"tag\" or \"splash\", and your phone's model, iOS version and heat level in memory. Nothing is sent anywhere unless you tap Share summary, and the summary has no names, party codes or Game Center IDs. Turning it off or closing the game discards it.", 17, UIKit.IVORY_MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	on.toggled.connect(func(b: bool) -> void:
		Diag.set_enabled(b)
		ov.disabled = not b
		share.disabled = not b
		clr.disabled = not b
		if not b:
			ov.button_pressed = false
		_diag_live(live))
	ov.toggled.connect(func(b: bool) -> void: Diag.set_overlay(b))
	_diag_live(live)
	var tm := Timer.new()
	tm.wait_time = 1.0
	tm.autostart = true
	tm.timeout.connect(_diag_live.bind(live))
	add_child(tm)


func _diag_live(live: Label) -> void:
	if not is_instance_valid(live):
		return
	if not Diag.enabled:
		live.text = "Off. Turn it on, play a few rounds, then share the summary with the developer."
		return
	var mins := (Time.get_ticks_msec() - Diag._start_ms) / 60000.0
	var stalls: int = Diag.stalls().size()
	var parts: PackedStringArray = ["Collecting for %.1f min" % mins, "%d stall%s over 50 ms" % [stalls, "" if stalls == 1 else "s"]]
	var m: Dictionary = Diag.stats("match")
	if not m.is_empty() and int(m["n"]) > 0:
		parts.append("in play p95 %.1f ms" % Diag.percentile(m["hist"], int(m["n"]), 0.95))
	live.text = " · ".join(parts)


static func _privacy_text() -> String:
	var t := "Settings, coins, unlocked items, level and stats are stored on this device. The game has no ads, tracking, chat or analytics. Online parties use Game Center for invitations and matchmaking."
	if Cloud.configured():
		t += " When you play online, the Ultimate Trifecta service stores your player name, runner look, a Game Center-linked account ID, your block list and any reports you send, so parties and safety tools work. Delete Game Profile removes it."
	return t


# ------------------------------------------------------------------ profile
func _fill_account() -> void:
	if not is_instance_valid(_acct):
		return
	for c in _acct.get_children():
		c.queue_free()
	var full := Cloud.full_name()
	var name_l := UIKit.label("Player name: %s" % (full if full != "" else Save.player_name()), 22, UIKit.IVORY, true)
	_acct.add_child(name_l)
	var st := UIKit.label(_account_status(), 18, UIKit.IVORY_MUTED)
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_acct.add_child(st)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_constant_override("v_separation", 12)
	_acct.add_child(row)
	var rename := UIKit.secondary("Change name", Vector2(240, 72), 22)
	rename.pressed.connect(func() -> void:
		await NameSheet.ask(self)
		App.sync_stage_local()
		_fill_account())
	row.add_child(rename)
	focus_first(rename)   # opens at the top, on Profile
	var look := UIKit.quiet("Edit runner", Vector2(220, 72), 22)
	look.pressed.connect(func() -> void:
		var c := CreatorScreen.new()
		c.back_action_override = func() -> void: App.goto(SettingsScreen)
		App._ensure_background()
		App._show(c))
	row.add_child(look)
	var nb := (Save.data.get("blocked", []) as Array).size()
	var blocks := UIKit.quiet("Blocked players (%d)" % nb, Vector2(280, 72), 22)
	blocks.pressed.connect(_blocked_sheet)
	row.add_child(blocks)
	if Cloud.configured() and Social.online_ready() and not Cloud.signed_in() and Cloud.state != "signing_in":
		var si := UIKit.quiet("Sign in", Vector2(180, 72), 22)
		si.pressed.connect(func() -> void: Cloud.sign_in())
		row.add_child(si)
	if Cloud.signed_in():
		var so := UIKit.quiet("Sign out", Vector2(180, 72), 22)
		so.pressed.connect(func() -> void:
			dialog("Sign out of the game service on this device? Practice still works; online parties sign you in again with Game Center.", [["Sign out", func() -> void: Cloud.sign_out()], ["Cancel", Callable()]]))
		row.add_child(so)
	var del := UIKit.quiet("Delete Game Profile", Vector2(300, 72), 22)
	del.add_theme_color_override("font_color", UIKit.BAD)
	del.pressed.connect(_confirm_delete)
	row.add_child(del)


static func _account_status() -> String:
	if not Cloud.configured():
		return "Your profile is stored on this device. Online names are checked when the game service is set up for this build."
	match Cloud.state:
		"ready":
			if String(Cloud.profile.get("status", "active")) == "suspended":
				return "Signed in with Game Center. Online play is paused on this profile; see the message when you create or join a party."
			return "Signed in with Game Center. Party members see your name and runner."
		"signing_in":
			return "Signing in with Game Center…"
		"error":
			return "Not signed in: %s" % Cloud.last_error
	if not Social.online_ready():
		return Social.status_text()
	return "Not signed in. Online parties sign you in with Game Center."


func _blocked_sheet() -> void:
	var list: Array = Save.data.get("blocked", [])
	var p := dialog("Blocked players can't join your parties, and you won't be placed in theirs." if not list.is_empty()
		else "You haven't blocked anyone. Use a player's card in a party to block them.", [["Done", _fill_account]])
	if list.is_empty():
		return
	var v: VBoxContainer = p.get_child(0)
	var box := UIKit.vbox(10)
	v.add_child(box)
	v.move_child(box, 1)
	for b in list:
		var row := UIKit.hbox(12)
		var nm := UIKit.label(NameRules.safe_display(String(b.get("name", "Player"))), 22, UIKit.IVORY)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		var un := UIKit.quiet("Unblock", Vector2(170, 64), 20)
		var pid := String(b.get("pid", ""))
		var uid := String(b.get("uid", ""))
		un.pressed.connect(func() -> void:
			if pid != "" and Cloud.signed_in():
				var r: Dictionary = await Cloud.unblock(pid)
				if not bool(r.get("ok", false)) and int(r.get("http_status", 0)) != 404:
					UIKit.toast(self, Cloud.explain(r))
					return
			Save.remove_block(pid, uid)
			Save.save_now()
			row.queue_free())
		row.add_child(un)
		box.add_child(row)
	p.position = (get_viewport().get_visible_rect().size - p.get_combined_minimum_size()) * 0.5


func _confirm_delete() -> void:
	var t := "Delete your game profile? This removes your player name, runner, coins, unlocked items, level, stats and block list from this device"
	if Cloud.configured():
		t += ", and deletes your online profile from the Ultimate Trifecta service (Game Center confirms it's you first)"
	t += ". This can't be undone."
	dialog(t, [["Cancel", Callable()], ["Delete", _delete_profile]])


func _delete_profile() -> void:
	if Cloud.configured():
		var b := busy("Deleting your online profile…")
		var r: Dictionary = await Cloud.delete_profile()
		b.queue_free()
		if not bool(r.get("ok", false)):
			dialog("Your online profile wasn't deleted: %s Nothing has been removed yet." % Cloud.explain(r),
				[["Try again", _delete_profile], ["Cancel", Callable()]])
			return
	if App.session:
		App._close_session()
	Save.data = Save.default_profile()
	Save.save_now()
	App.sync_stage_local()
	App.goto_title("Game profile deleted.")


func _on_controller(on: bool, n: String, ctl: Label) -> void:
	if is_instance_valid(ctl):
		ctl.text = "Controller: " + (n if on else "none connected (touch controls active)")


## A section: a thin divider (except the first) and a small overline title.
func _section(parent: Control, title: String) -> void:
	if parent.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 6)
		parent.add_child(gap)
		var line := ColorRect.new()
		line.color = Color(UIKit.IVORY, 0.08)
		line.custom_minimum_size = Vector2(0, 1)
		parent.add_child(line)
	parent.add_child(UIKit.styled(title, "overline", UIKit.TEAL))


func _slider(parent: Control, text: String, key: String, mn: float, mx: float, step: float) -> HSlider:
	var row := UIKit.hbox(16)
	var l := UIKit.label(text, 22)
	l.custom_minimum_size = Vector2(300, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = float(Save.get_setting(key, mn))
	s.custom_minimum_size = Vector2(360, maxf(44.0, UIKit.touch_min()))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.focus_mode = Control.FOCUS_ALL
	s.value_changed.connect(func(val: float) -> void: Save.set_setting(key, val))
	row.add_child(s)
	parent.add_child(row)
	return s


## Segmented choice: one button per option, the current one in teal.
func _choice(parent: Control, text: String, key: String, opts: Array) -> void:
	var row := UIKit.hbox(10)
	var l := UIKit.label(text, 22)
	l.custom_minimum_size = Vector2(300, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	var btns: Array[Button] = []
	for o in opts:
		var b := UIKit.quiet(String(o[1]), Vector2(200, 64), 19)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		var val: Variant = o[0]
		b.pressed.connect(func() -> void:
			Save.set_setting(key, val)
			_paint(btns, opts, key))
		row.add_child(b)
		btns.append(b)
	parent.add_child(row)
	_paint(btns, opts, key)


func _paint(btns: Array[Button], opts: Array, key: String) -> void:
	var cur: Variant = Save.get_setting(key, opts[0][0])
	for i in btns.size():
		UIKit.set_selected(btns[i], str(cur) == str(opts[i][0]))


func _check(parent: Control, text: String, key: String, def: bool) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = bool(Save.get_setting(key, def))
	c.custom_minimum_size = Vector2(0, maxf(44.0, UIKit.touch_min()))
	c.toggled.connect(func(on: bool) -> void: Save.set_setting(key, on))
	c.add_theme_font_size_override("font_size", 22)
	parent.add_child(c)
	return c
