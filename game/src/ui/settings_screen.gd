class_name SettingsScreen
extends Screen
## Settings (V7): a header that never scrolls (Back and the title), then one
## list that scrolls by finger, made of grouped cards of compact labelled
## rows - Profile, Controls, Sound, Camera & comfort, Graphics, Diagnostics,
## Privacy, How to play, Credits - and, kept apart at the end, Delete
## Game Profile (always explicitly confirmed).  Every row has the same label
## column, so sliders, switches and choices line up; a choice whose options
## don't fit beside its label moves under it instead of trimming them.
## Everything saves immediately, with the same keys and values as before.

const MAX_W := 1500.0
const ACTION_W := 232.0

var _rows: Dictionary = {}
var _acct: VBoxContainer
var _sc: ScrollContainer
var _body: VBoxContainer
var _label_w := 300.0
## section title -> its card (tests, captures)
var sections: Dictionary = {}


func build() -> void:
	if App.stage:
		App.stage.set_mode("home")
	header("Settings")
	# an opaque sheet over a dimmed room (no translucent slab)
	var dim := ColorRect.new()
	dim.color = Color(UIKit.NAVY, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	move_child(dim, 0)
	_sc = UIKit.scroll_area()
	_sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sc.follow_focus = true
	content.add_child(_sc)
	_body = UIKit.vbox(14)
	_body.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_sc.add_child(_body)
	_fit_width()
	_sc.resized.connect(_fit_width)

	var prof := _section("Profile")
	_acct = UIKit.vbox(3)
	prof.add_child(_acct)
	_fill_account()
	Cloud.changed.connect(_fill_account)

	var ctl_s := _section("Controls")
	var first := _slider(ctl_s, "Camera sensitivity", "sensitivity", 0.3, 2.5, 0.05, "%.2f×")
	_choice(ctl_s, "Movement stick", "stick_mode", [["dynamic", "Where you touch"], ["fixed", "Fixed position"]])
	var tl := TouchControls.saved_layout()
	var custom := not (tl["move"] as Array).is_empty() or not (tl["action"] as Dictionary).is_empty()
	var edit := _action("Edit layout")
	edit.pressed.connect(func() -> void: App.goto(TouchLayoutEditor))
	_row(ctl_s, "Touch layout", edit, "%s · size %d%% · %s" % ["Mirrored" if bool(tl["mirror"]) else "Standard", int(round(float(tl["size"]) * 100.0)),
		"your positions" if custom else "recommended positions"])
	_check(ctl_s, "Vibration (haptics)", "haptics", true)
	var arow := UIKit.hbox(12)
	var ctl := UIKit.styled(_controller_text(Controls.has_controller(), Controls.controller_name), "caption", UIKit.IVORY_MUTED)
	ctl.add_theme_font_size_override("font_size", 19)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ctl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ctl.custom_minimum_size = Vector2(160, 0)
	arow.add_child(ctl)
	var try_b := _action("Try in Practice")
	try_b.pressed.connect(func() -> void: App.start_practice("runner", false))
	arow.add_child(try_b)
	var reset := _action("Reset controls")
	reset.pressed.connect(func() -> void:
		var d: Dictionary = Save.default_profile()["settings"]
		for k in ["sensitivity", "invert_y", "reduced_motion", "stick_mode", "button_size", "touch_layout", "haptics"]:
			Save.set_setting(k, d[k])
		Save.set_setting("touch_layout_v2", TouchLayout.default_layout())
		App.goto(SettingsScreen))
	arow.add_child(reset)
	_add_row(ctl_s, arow)
	Controls.controller_connection_changed.connect(_on_controller.bind(ctl))

	var snd := _section("Sound")
	_slider(snd, "Sound effects", "sfx", 0.0, 1.0, 0.05, "%d%%")
	_slider(snd, "Music", "music", 0.0, 1.0, 0.05, "%d%%")

	var cam := _section("Camera & comfort")
	_check(cam, "Invert camera up/down", "invert_y", false)
	_check(cam, "Reduced motion", "reduced_motion", false, "Calmer camera, no look-ahead, fades instead of slides.")

	var gfx := _section("Graphics")
	_choice(gfx, "Quality", "quality", [[1, "Standard (60 fps)"], [0, "Battery Saver (30 fps)"]],
		"Battery Saver draws the world at a lower resolution with simpler shadows and effects. Text and buttons stay sharp.")

	_diag_section(_section("Diagnostics"))

	var priv_s := _section("Privacy")
	priv_s.add_child(_note(_privacy_text()))
	# the owner's real links only (config/links.cfg, else the service); nothing shown until set
	var links := UIKit.hbox(12)
	for l in [["privacy_url", "Privacy policy"], ["support_url", "Support"]]:
		var url := AppLinks.get_link(String(l[0]))
		if url != "":
			var lb := UIKit.quiet(String(l[1]), Vector2(0, UIKit.touch_min()), UIKit.T_LABEL)
			lb.pressed.connect(func() -> void: OS.shell_open(url))
			links.add_child(lb)
	if links.get_child_count() > 0:
		priv_s.add_child(links)
	else:
		links.free()
	var how_s := _section("How to play")
	var how := _action("Open the rules card")
	how.pressed.connect(func() -> void: App.goto(HowToScreen))
	_row(how_s, "Rules", how, "Roles, waters, tags and how a round is won.")
	var cred_s := _section("Credits & licenses")
	cred_s.add_child(_note("Made with Godot Engine (MIT). Game Center bindings: GodotApplePlugins (MIT). Fonts: Manrope (SIL OFL 1.1); the startup mark's descriptor is outlined DejaVu Sans (Bitstream Vera licence). Characters built with Blender's Python module (the generated model is original). All characters, campus, sounds and music are original to Ultimate Trifecta. Moonbrook College is fictional."))
	cred_s.add_child(_note("Version %s" % ProjectSettings.get_setting("application/config/version", "1.0")))

	# --- kept apart from the routine profile actions, at the very end
	var del_s := _section("Delete game profile", UIKit.BAD)
	var del := _action("Delete Game Profile")
	UIKit.face_of(del).fg = {"normal": UIKit.BAD, "disabled": UIKit.IVORY_DIM}
	UIKit.face_of(del).queue_redraw()
	del.pressed.connect(_confirm_delete)
	_row(del_s, "Your profile", del, "Removes your name, runner, progress, Coins and items. You'll be asked to confirm.")
	focus_first(first)
	_open_at_top(_sc)


## The list is as wide as the screen allows, up to MAX_W (rows stay
## readable on wide phones); every row's label column follows it.
func _fit_width() -> void:
	if not is_instance_valid(_sc) or not is_instance_valid(_body):
		return
	var w := _sc.size.x
	if w <= 1.0:
		w = get_viewport().get_visible_rect().size.x - float(margin.get_theme_constant("margin_left") + margin.get_theme_constant("margin_right"))
	w = minf(MAX_W, w - 18.0)   # (room for the scroll bar)
	_body.custom_minimum_size.x = w
	_label_w = clampf(w * 0.3, 220.0, 330.0)
	for l in find_children("*", "Label", true, false):
		if l.has_meta(&"row_label"):
			(l as Label).custom_minimum_size.x = _label_w


## A section: a card with a small overline title.  Returns its row column.
func _section(title: String, col: Color = UIKit.TEAL) -> VBoxContainer:
	var p := UIKit.panel(Color(UIKit.SLATE, 0.99), UIKit.R_PANEL, 20)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UIKit.vbox(3)
	var t := UIKit.styled(title, "overline", col)
	v.add_child(t)
	v.set_meta(&"titled", true)
	p.add_child(v)
	_body.add_child(p)
	sections[title] = p
	return v


## A row: a thin divider above it (except a section's first), then its
## content.
func _add_row(parent: VBoxContainer, row: Control) -> void:
	if parent.get_child_count() > (1 if parent.has_meta(&"titled") else 0):
		var line := ColorRect.new()
		line.color = Color(UIKit.IVORY, 0.07)
		line.custom_minimum_size = Vector2(0, 1)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(line)
	parent.add_child(row)


## The row label (the shared label column), with an optional note under it.
func _label_cell(text: String, note: String = "") -> Control:
	var l := UIKit.styled(text, "label")
	l.custom_minimum_size = Vector2(_label_w, 0)
	l.set_meta(&"row_label", true)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if note == "":
		return l
	var v := UIKit.vbox(2)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_child(l)
	v.add_child(_note(note))
	return v


func _note(text: String) -> Label:
	var n := UIKit.styled(text, "caption", UIKit.IVORY_MUTED)
	n.add_theme_font_size_override("font_size", 18)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.custom_minimum_size = Vector2(200, 0)
	return n


## A row's action: a quiet button, all of them one width (wider only when
## their words need it), so the right-hand column lines up.
func _action(text: String) -> Button:
	var b := UIKit.quiet(text, Vector2(0, UIKit.touch_min()), UIKit.T_LABEL)
	b.custom_minimum_size.x = maxf(ACTION_W, UIKit.v7_text_width(b, text) + 40.0)
	return b


## Label (with an optional note) on the left, a control on the right.
func _row(parent: VBoxContainer, text: String, control: Control, note: String = "") -> HBoxContainer:
	var row := UIKit.hbox(16)
	row.custom_minimum_size = Vector2(0, UIKit.touch_min())
	var lc := _label_cell(text, note)
	lc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lc)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	_add_row(parent, row)
	return row


## Opt-in performance diagnostics for the internal beta: collected in memory
## only, shared as plain text through the share sheet when the player asks.
func _diag_section(v: VBoxContainer) -> void:
	var on := _switch(v, "Collect performance diagnostics", Diag.enabled)
	var ov := _switch(v, "Show a small frame-time readout", Diag.overlay)
	ov.disabled = not Diag.enabled
	var row := UIKit.hbox(12)
	var live := UIKit.styled("", "caption", UIKit.IVORY_MUTED)
	live.add_theme_font_size_override("font_size", 18)
	live.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	live.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	live.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	live.custom_minimum_size = Vector2(200, 0)
	row.add_child(live)
	var share := _action("Share summary")
	share.disabled = not Diag.enabled
	share.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	share.pressed.connect(func() -> void:
		var txt: String = Diag.summary()
		if not Share.share_text(txt):
			UIKit.toast(self, "Summary copied — paste it into a message"))
	row.add_child(share)
	var clr := _action("Clear")
	clr.disabled = not Diag.enabled
	clr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	clr.pressed.connect(func() -> void:
		Diag.clear()
		_diag_live(live))
	row.add_child(clr)
	_add_row(v, row)
	v.add_child(_note("While this is on, the game keeps frame timings, short notes such as \"lobby\", \"tag\" or \"splash\", and your phone's model, iOS version and heat level in memory. Nothing is sent unless you tap Share summary, and the summary has no names, party codes or Game Center IDs. Turning it off or closing the game discards it."))
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
	var t := "Settings, level and stats are stored on this device. The game has no ads, tracking or analytics. Online parties use Game Center for invitations and matchmaking. App Store purchases are handled by Apple; the game never sees your payment details."
	if Cloud.configured():
		t += " When you play online, the Ultimate Trifecta service stores your player name, runner look, a Game Center-linked account ID, your block list and any reports you send, so parties and safety tools work. It also keeps your Coins, purchases (App Store transaction IDs, never payment details), Season progress and rewarded rounds, so they're delivered once and restore on any device. With Friends, it keeps your Game Center friends list as scrambled IDs and your status (online, in a party, in a round) for about a minute, shown only to friends who list you too; turn off Show when I'm playing in Friends to hide it. Delete Game Profile removes all of this."
	return t


# ------------------------------------------------------------------ profile
## Routine profile actions as rows (name, account, runner, blocked players);
## Delete Game Profile lives in its own card at the end.
func _fill_account() -> void:
	if not is_instance_valid(_acct):
		return
	for c in _acct.get_children():
		_acct.remove_child(c)
		c.queue_free()
	var tm := UIKit.touch_min()
	var full := Cloud.full_name()
	var rename := _action("Change name")
	rename.pressed.connect(func() -> void:
		await NameSheet.ask(self)
		App.sync_stage_local()
		_fill_account())
	var nrow := _row(_acct, "Player name", rename)
	var nv := UIKit.vbox(0)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var nm := UIKit.styled(full if full != "" else Save.player_name(), "label", UIKit.AMBER)
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nv.add_child(nm)
	var st := _note(_account_status())
	st.custom_minimum_size.x = 160
	nv.add_child(st)
	nrow.get_child(0).size_flags_horizontal = Control.SIZE_FILL
	nrow.add_child(nv)
	nrow.move_child(nv, 1)
	focus_first(rename)   # opens at the top, on Profile
	# sign in / out, when it applies to this build and account
	if Cloud.configured() and Social.online_ready() and not Cloud.signed_in() and Cloud.state != "signing_in":
		var si := _action("Sign in")
		si.pressed.connect(func() -> void: Cloud.sign_in())
		_row(_acct, "Game service", si, "Online parties sign you in with Game Center.")
	elif Cloud.signed_in():
		var so := _action("Sign out")
		so.pressed.connect(func() -> void:
			dialog("Sign out of the game service on this device? Practice still works; online parties sign you in again with Game Center.", [["Sign out", func() -> void: Cloud.sign_out()], ["Cancel", Callable()]]))
		_row(_acct, "Game service", so, "Signed in on this device.")
	var look := _action("Edit runner")
	look.pressed.connect(func() -> void:
		var c := CreatorScreen.new()
		c.back_action_override = func() -> void: App.goto(SettingsScreen)
		App._ensure_background()
		App._show(c))
	_row(_acct, "Runner", look, "Your outfit and colours, the same in every round.")
	var nb := (Save.data.get("blocked", []) as Array).size()
	var blocks := _action("Manage")
	blocks.accessibility_name = "Blocked players (%d)" % nb
	blocks.pressed.connect(_blocked_sheet)
	_row(_acct, "Blocked players", blocks, "None" if nb == 0 else "%d player%s" % [nb, "" if nb == 1 else "s"])


static func _account_status() -> String:
	if not Cloud.configured():
		return "Stored on this device."
	match Cloud.state:
		"ready":
			if String(Cloud.profile.get("status", "active")) == "suspended":
				return "Signed in with Game Center. Online play is paused on this profile."
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
	# (V7) a long block list scrolls inside the dialog instead of running off
	# the screen
	var vh := get_viewport().get_visible_rect().size.y
	var cap := maxf(160.0, vh - UIKit.touch_min() * 2.0 - 220.0)
	var list_sc := UIKit.v7_capped_list(box, cap)
	v.add_child(list_sc)
	v.move_child(list_sc, 1)
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
	list_sc.custom_minimum_size.y = minf(box.get_combined_minimum_size().y, cap)
	# (V7) re-centre for the rows: the dialog's entrance tween would otherwise
	# put it back where it was centred without them (half off a phone screen)
	Motion.stop(p, "position")
	p.position = (get_viewport().get_visible_rect().size - p.get_combined_minimum_size()) * 0.5


func _confirm_delete() -> void:
	var t := "Delete your game profile? This removes your player name, runner, level, stats, block list, Coins and unlocked items from this device"
	if Cloud.configured():
		t += ", and deletes your online profile from the Ultimate Trifecta service (Game Center confirms it's you first): your Coins (earned and purchased), Coin-bought items, Season 1 progress, Premium access and claimed rewards are deleted with it and can't be restored"
	t += ". Skins bought directly from the App Store stay with your Apple Account: Shop › Restore Purchases brings them back. This can't be undone."
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
	Wallet.reset_local()
	App.sync_stage_local()
	App.goto_title("Game profile deleted.")


static func _controller_text(on: bool, n: String) -> String:
	return "Controller: " + (n if on else "none connected (touch controls active)")


func _on_controller(on: bool, n: String, ctl: Label) -> void:
	if is_instance_valid(ctl):
		ctl.text = _controller_text(on, n)


# ------------------------------------------------------------------ rows
## A slider row: label, slider, and its value at the right end.
func _slider(parent: VBoxContainer, text: String, key: String, mn: float, mx: float, step: float, fmt: String) -> HSlider:
	var row := UIKit.hbox(16)
	row.custom_minimum_size = Vector2(0, UIKit.touch_min())
	row.add_child(_label_cell(text))
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = float(Save.get_setting(key, mn))
	s.custom_minimum_size = Vector2(200, maxf(44.0, UIKit.touch_min()))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_ALL
	s.accessibility_name = text
	var knob := _knob()
	s.add_theme_icon_override("grabber", knob)
	s.add_theme_icon_override("grabber_highlight", knob)
	row.add_child(s)
	var val := UIKit.styled("", "num", UIKit.IVORY_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	val.custom_minimum_size = Vector2(84, 0)
	val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(val)
	var show := func(v: float) -> void:
		val.text = fmt % (roundf(v * 100.0) if fmt.contains("%%") else v)
	show.call(s.value)
	s.value_changed.connect(func(v: float) -> void:
		Save.set_setting(key, v)
		show.call(v))
	_add_row(parent, row)
	_rows[key] = s
	return s


## A slider knob a finger can see (the engine's is ~8 pt on a phone).
static var _knob_tex: Texture2D


static func _knob() -> Texture2D:
	if _knob_tex == null:
		var d := 34
		var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
		var c := Vector2(d, d) * 0.5
		for y in d:
			for x in d:
				var r := Vector2(x + 0.5, y + 0.5).distance_to(c)
				var a := clampf(d * 0.5 - 1.0 - r, 0.0, 1.0)
				var rim := clampf(d * 0.5 - 4.0 - r, 0.0, 1.0)
				img.set_pixel(x, y, Color(UIKit.TEAL.lerp(UIKit.IVORY, rim), a))
		_knob_tex = ImageTexture.create_from_image(img)
	return _knob_tex


## Segmented choice: one button per option sized to its words, the current
## one selected.  The options sit beside the label when they fit, else they
## move under it (never trimmed).
func _choice(parent: VBoxContainer, text: String, key: String, opts: Array, note: String = "") -> void:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 16)
	row.add_theme_constant_override("v_separation", 8)
	row.custom_minimum_size = Vector2(0, UIKit.touch_min())
	row.add_child(_label_cell(text))
	var seg := UIKit.hbox(10)
	seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var btns: Array[Button] = []
	for o in opts:
		var b := UIKit.quiet(String(o[1]), Vector2(0, UIKit.touch_min()), UIKit.T_CAPTION)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var val: Variant = o[0]
		b.pressed.connect(func() -> void:
			Save.set_setting(key, val)
			_paint(btns, opts, key))
		seg.add_child(b)
		btns.append(b)
	row.add_child(seg)
	_add_row(parent, row)
	if note != "":
		parent.add_child(_note(note))
	_paint(btns, opts, key)
	_rows[key] = seg


func _paint(btns: Array[Button], opts: Array, key: String) -> void:
	var cur: Variant = Save.get_setting(key, opts[0][0])
	for i in btns.size():
		UIKit.set_selected(btns[i], str(cur) == str(opts[i][0]))
		btns[i].accessibility_name = "%s%s" % [btns[i].text, " (selected)" if str(cur) == str(opts[i][0]) else ""]


## A switch row: the label (and note) on the left, the switch at the right.
func _switch(parent: VBoxContainer, text: String, on: bool, note: String = "") -> CheckButton:
	var c := Toggle.new()
	c.button_pressed = on
	c.custom_minimum_size = Vector2(maxf(96.0, UIKit.touch_min() * 1.4), maxf(44.0, UIKit.touch_min()))
	c.accessibility_name = text
	c.tooltip_text = text
	_row(parent, text, c, note)
	return c


func _check(parent: VBoxContainer, text: String, key: String, def: bool, note: String = "") -> CheckButton:
	var c := _switch(parent, text, bool(Save.get_setting(key, def)), note)
	c.toggled.connect(func(on: bool) -> void: Save.set_setting(key, on))
	_rows[key] = c
	return c


## A switch drawn at a phone-readable size (the engine's toggle icon is
## ~23 pt wide on a phone): a rounded track, teal when on, with a knob.  The
## whole control is the hit area (at least 44 pt tall).
class Toggle:
	extends CheckButton

	func _init() -> void:
		var none := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
			add_theme_stylebox_override(st, none)
		var blank := PlaceholderTexture2D.new()
		blank.size = Vector2(1, 1)
		for ic in ["checked", "unchecked", "checked_disabled", "unchecked_disabled", "checked_mirrored", "unchecked_mirrored",
				"checked_disabled_mirrored", "unchecked_disabled_mirrored"]:
			add_theme_icon_override(ic, blank)
		add_theme_stylebox_override("focus", UIKit.focus_ring(UIKit.R_SMALL))
		toggled.connect(func(_on: bool) -> void: queue_redraw())

	func _draw() -> void:
		var h := clampf(UIKit.touch_min() * 0.62, 26.0, 56.0)
		var w := h * 1.72
		var r := Rect2(Vector2(size.x - w - 6.0, (size.y - h) * 0.5), Vector2(w, h))
		var on := button_pressed
		var track := UIKit.box(UIKit.TEAL if on else UIKit.SLATE_LO, int(h * 0.5), 2, UIKit.TEAL if on else Color(UIKit.IVORY, 0.22), 0)
		if disabled:
			track.bg_color = Color(track.bg_color, 0.4)
			track.border_color = Color(track.border_color, 0.3)
		draw_style_box(track, r)
		var k := h * 0.5 - 4.0
		var cx := r.end.x - h * 0.5 if on else r.position.x + h * 0.5
		draw_circle(Vector2(cx, r.get_center().y), k, Color(UIKit.NAVY if on else UIKit.IVORY, 0.45 if disabled else 1.0))
