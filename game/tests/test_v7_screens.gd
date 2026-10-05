extends RefCounted
## V7 screens: final allocated bounds of Play with Friends and Settings at
## the landscape phone and iPad sizes (and the owner's 2048x946 and 1536x710
## screenshot aspects); the iOS keyboard on the party code; that profile
## deletion is still explicitly confirmed; and the sweep of home, the party
## room (1 and 4 players), results, final standings and confirmations for
## off-screen, outside-the-safe-area, trimmed or covered controls.
##
## "Covered" is tested with the real GUI pick: a pointer moved to the centre
## of every visible control must land on that control (an invisible
## full-screen node above it would take it instead).  Clicks and swipes go
## through Viewport.push_input with touch emulated from the mouse, as iOS
## delivers them.
##
## The normal test lane runs on a headless desktop (44-unit touch targets,
## 16/12-unit safe margins).  tools/check_v7_screens.sh runs this file once
## per device with --emulate-phone (the device's 44 pt targets: ~81-85
## canvas units on phones), --emulate-safe (the notch and home indicator)
## and --v7-size=WxH, so the same checks hold at each device's real sizes.
var t

## [label, pixels, height in points, a typical landscape keyboard in points
## (the QuickType bar included)]
const DEVICES := [
	["iPhone SE 667x375 pt @2x", Vector2i(1334, 750), 375.0, 194.0],
	["812x375 pt @3x", Vector2i(2436, 1125), 375.0, 209.0],
	["844x390 pt @3x", Vector2i(2532, 1170), 390.0, 209.0],
	["926x428 pt @3x", Vector2i(2778, 1284), 428.0, 209.0],
	["iPad 1024x768 pt @2x", Vector2i(2048, 1536), 768.0, 398.0],
	["2048x946 (owner screenshot, as 844x390 pt)", Vector2i(2048, 946), 390.0, 209.0],
	["1536x710 (owner screenshot, as 812x375 pt)", Vector2i(1536, 710), 375.0, 209.0],
]
const SECTIONS := ["Profile", "Controls", "Sound", "Camera & comfort", "Graphics", "Diagnostics (beta)", "Privacy",
	"How to play", "Credits & licenses", "Delete game profile"]

var _saved := {}


func _devices() -> Array:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--v7-size="):
			var p := a.get_slice("=", 1).split("x")
			var sz := Vector2i(int(p[0]), int(p[1]))
			# (the device's height in points is read once the window has its size)
			return [["emulated %s" % a.get_slice("=", 1), sz, 0.0, 398.0 if float(sz.x) / sz.y < 1.5 else (194.0 if float(sz.x) / sz.y < 1.9 else 209.0)]]
	return DEVICES


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


func _begin() -> void:
	var root: Window = t.get_tree().root
	_saved = {"size": root.size, "device": Controls.device, "emulate": Input.emulate_touch_from_mouse,
		"gc": [Social.available, Social.authenticated, Social.multiplayer_restricted, Social.auth_error],
		"data": Save.data.duplicate(true), "had_file": FileAccess.file_exists(Save.PATH),
		"file": FileAccess.get_file_as_string(Save.PATH) if FileAccess.file_exists(Save.PATH) else "",
		"session": App.session, "stage": App.stage}
	Controls.device = "touch"
	Input.emulate_touch_from_mouse = true
	Save.data["onboarded"] = true
	# the startup curtain (it blocks input while shown) is not part of these screens
	for n in root.get_children():
		if n is BootCurtain:
			n.free()
	root.notification(Window.NOTIFICATION_WM_MOUSE_ENTER)
	Social.available = true
	Social.authenticated = true
	Social.multiplayer_restricted = false
	Social.auth_error = ""


func _end() -> void:
	UIKit.v7_emulated_keyboard_pt = -1.0
	await _close()
	var root: Window = t.get_tree().root
	root.size = _saved["size"]
	Controls.device = _saved["device"]
	Input.emulate_touch_from_mouse = _saved["emulate"]
	var gc: Array = _saved["gc"]
	Social.available = gc[0]
	Social.authenticated = gc[1]
	Social.multiplayer_restricted = gc[2]
	Social.auth_error = gc[3]
	Save.data = _saved["data"]
	if bool(_saved["had_file"]):
		var f := FileAccess.open(Save.PATH, FileAccess.WRITE)
		f.store_string(String(_saved["file"]))
	elif FileAccess.file_exists(Save.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Save.PATH))
	App.session = _saved["session"]
	await _frames(2)


func _size(sz: Vector2i) -> void:
	t.get_tree().root.size = sz
	await _frames(2)


func _show(s: Screen) -> Screen:
	App._ensure_background()
	App._show(s)
	await _frames(8)
	return s


func _close() -> void:
	if App.screen and is_instance_valid(App.screen):
		App.screen.queue_free()
	App.screen = null
	App._clear_background()
	await _frames(2)


# ------------------------------------------------------------- geometry
func _view() -> Rect2:
	return t.get_tree().root.get_visible_rect()


func _safe() -> Rect2:
	return UIKit.safe_rect(t.get_tree().root, _view().size)


## The region a control is shown in: its nearest scrolling list or clipping
## parent (the whole view otherwise).
func _shown_in(c: Control) -> Rect2:
	var p := c.get_parent()
	while p != null and p is Control:
		if p is ScrollContainer or (p as Control).clip_contents:
			return (p as Control).get_global_rect().intersection(_view())
		p = p.get_parent()
	return _view()


func _fully_shown(c: Control) -> bool:
	return c.is_visible_in_tree() and _shown_in(c).grow(0.5).encloses(c.get_global_rect())


## The control a pointer at `c`'s centre reaches (the real GUI pick).
func _picked(c: Control) -> Control:
	var e := InputEventMouseMotion.new()
	e.position = c.get_global_rect().get_center()
	e.global_position = e.position
	t.get_tree().root.push_input(e, true)
	return t.get_tree().root.gui_get_hovered_control()


func _reaches(c: Control) -> bool:
	var got := _picked(c)
	return got == c or (got != null and c.is_ancestor_of(got) and got.mouse_filter != Control.MOUSE_FILTER_STOP)


func _click(c: Control) -> void:
	var at := c.get_global_rect().get_center()
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = at
		e.global_position = at
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		t.get_tree().root.push_input(e, true)
		await _frames(2)


func _swipe(from: Vector2, by: Vector2) -> void:
	var root: Window = t.get_tree().root
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = from
	e.global_position = from
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	var prev := from
	for i in 12:
		var p := from + by * float(i + 1) / 12.0
		var m := InputEventMouseMotion.new()
		m.position = p
		m.global_position = p
		m.relative = p - prev
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(m, true)
		prev = p
		await _frames(1)
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	u.position = prev
	u.global_position = prev
	root.push_input(u, true)
	await _frames(20)


func _same(a: Rect2, b: Rect2) -> bool:
	return a.position.distance_to(b.position) < 1.0 and a.size.distance_to(b.size) < 1.0


func _text_of(c: Control) -> String:
	if c is LineEdit:
		return "field '%s'" % (c as LineEdit).placeholder_text
	if c is Button:
		var b := c as Button
		if b.text != "":
			return b.text
		var f := UIKit.face_of(b)
		if f != null and f.caption != "":
			return f.caption
		return b.tooltip_text if b.tooltip_text != "" else (b.accessibility_name if b.accessibility_name != "" else b.get_class())
	return c.get_class()


func _label_trimmed(l: Label) -> bool:
	if l.autowrap_mode != TextServer.AUTOWRAP_OFF or l.text == "" or not l.is_visible_in_tree():
		return false
	if not l.clip_text and l.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING:
		return false
	var txt := l.text.to_upper() if l.uppercase else l.text
	return UIKit.v7_text_width(l, txt) > l.size.x + 0.5


## Every visible control of a screen that is shown (not scrolled away) is
## inside the view and the safe area, a full touch target, whole (its words
## not trimmed) and reached by a pointer at its centre.
func _audit(tag: String, root: Control, skip: Array = []) -> void:
	var view := _view()
	var safe := _safe()
	var tm := UIKit.touch_min()
	for n in root.find_children("*", "Control", true, false):
		var c := n as Control
		if c in skip or not c.is_visible_in_tree():
			continue
		if c is Label:
			var lb := c as Label
			if _fully_shown(lb) and lb.has_meta(&"refit") == false:
				t.check(not _label_trimmed(lb), "%s: label '%s' whole" % [tag, lb.text])
			continue
		if not (c is BaseButton or c is LineEdit or c is Slider):
			continue
		if c.get_global_rect().size.x < 2.0:
			continue
		var name := _text_of(c)
		var r := c.get_global_rect()
		if not _fully_shown(c):
			continue   # (scrolled partly or wholly out of its list)
		t.check(view.grow(0.5).encloses(r), "%s: '%s' on screen (%s in %s)" % [tag, name, str(r), str(view)])
		t.check(safe.grow(0.5).encloses(r), "%s: '%s' inside the safe area (%s in %s)" % [tag, name, str(r), str(safe)])
		t.check(minf(r.size.x, r.size.y) >= tm - 0.5, "%s: '%s' a full touch target (%s, min %.1f)" % [tag, name, str(r.size), tm])
		if c is Button:
			t.check(UIKit.v7_button_text_fits(c as Button), "%s: '%s' not trimmed (%.0f wide)" % [tag, name, r.size.x])
		t.check(_reaches(c), "%s: a pointer at '%s' reaches it (got %s)" % [tag, name, str(_picked(c))])


# ------------------------------------------------------------- Play with Friends
func test_friends_first_view_shows_identity_create_join_and_friends() -> void:
	await _begin()
	for d in _devices():
		var tag := String(d[0])
		await _size(d[1])
		var s: OnlineScreen = await _show(OnlineScreen.new())
		var must := {"Back": s.back_btn, "who you play as": s.who_lbl, "Change name": s.rename_btn, "Create Party": s.create_btn,
			"code field": s.code_edit, "Join": s.join_btn, "Game Center friends": s.friends_btn}
		for k in must:
			var c: Control = must[k]
			t.check(c.is_visible_in_tree() and _fully_shown(c), "%s: %s fully in the first view (%s)" % [tag, k, str(c.get_global_rect())])
			t.check(_safe().grow(0.5).encloses(c.get_global_rect()), "%s: %s inside the safe area" % [tag, k])
		# hierarchy: header, then the two actions, then friends
		var back := s.back_btn.get_global_rect()
		var cr := s.create_btn.get_global_rect()
		var f := s.code_edit.get_global_rect()
		var j := s.join_btn.get_global_rect()
		var fr := s.friends_btn.get_global_rect()
		t.check(back.end.y <= minf(cr.position.y, f.position.y), "%s: the header sits above Create and Join" % tag)
		t.check(fr.position.y >= maxf(cr.end.y, j.end.y), "%s: the friends entry follows them" % tag)
		t.check(cr.size.x >= j.size.x, "%s: Create Party is the larger, primary action" % tag)
		# the code row: one height, one top edge, Join after the field
		t.near(f.size.y, j.size.y, 0.5, "%s: field and Join are the same height" % tag)
		t.near(f.position.y, j.position.y, 0.5, "%s: field and Join share a top edge (and so a centre line)" % tag)
		t.check(j.position.x >= f.end.x + 8.0, "%s: Join follows the field with a gap" % tag)
		t.eq(s.code_edit.get_theme_font_size("font_size"), s.join_btn.get_theme_font_size("font_size"), "%s: one type size, so one baseline" % tag)
		t.check(f.size.x >= UIKit.v7_text_width(s.code_edit, "ACE-347") + 24.0, "%s: a whole code fits the field" % tag)
		# the code row sits well above where a phone keyboard starts (no jump when it opens)
		t.check(j.end.y <= _view().size.y * 0.5, "%s: the code row is in the upper half (%.0f of %.0f)" % [tag, j.end.y, _view().size.y])
		t.check(s.code_msg.get_line_count() <= 2, "%s: the code message is short (%d lines)" % [tag, s.code_msg.get_line_count()])
		await _audit(tag + " Friends", s)
		await _close()
	await _end()


func test_friends_states_game_center_off_and_busy() -> void:
	await _begin()
	await _size(Vector2i(2532, 1170))
	Social.authenticated = false
	Social.auth_error = "The user canceled the sign-in"
	var s: OnlineScreen = await _show(OnlineScreen.new())
	t.check(s._status_card != null and s._status_card.is_visible_in_tree(), "not signed in: the Game Center card shows")
	t.check(s.create_btn.disabled and not s.code_edit.editable, "Create and the code field are off without Game Center")
	t.check(_fully_shown(s.create_btn) and _fully_shown(s.code_edit), "and still in the first view")
	var prac: Button = s._first_focus as Button
	t.check(prac != null and prac.text == "Go to Practice" and _fully_shown(prac) and _reaches(prac), "Practice stays one tap away")
	await _close()
	Social.authenticated = true
	Social.auth_error = ""
	s = await _show(OnlineScreen.new())
	# working: Back cancels the request instead of leaving, Cancel shows
	s._busy("Creating your party…")
	await _frames(3)
	t.check(s.busy_card.is_visible_in_tree() and _fully_shown(s._busy_cancel), "progress with Cancel in view")
	t.check(s.create_btn.disabled and s.join_btn.disabled, "no second request while one runs")
	t.check(s.back_action.is_valid(), "Back cancels the request")
	var op := s._op
	await _click(s._busy_cancel)
	t.check(not s.busy_card.visible and s._op == op + 1, "Cancel ends it (stale results are ignored)")
	t.check(not s.back_action.is_valid() and not s.create_btn.disabled, "and the screen is usable again")
	await _end()


func test_friends_code_is_strict_and_messages_are_short() -> void:
	await _begin()
	await _size(Vector2i(1334, 750))
	var s: OnlineScreen = await _show(OnlineScreen.new())
	var typed := func(txt: String) -> void:
		s.code_edit.text = txt
		s.code_edit.text_changed.emit(txt)
	typed.call("ace-3b7")
	t.eq(s.code_edit.text, "ACE-3B7", "typing is upper-cased")
	t.check(s.code_msg.text.begins_with("\"B\" isn't used in party codes"), "a wrong character is named (%s)" % s.code_msg.text)
	t.check(not s.code_msg.text.contains("Check the code"), "in one short sentence")
	t.check(s.join_btn.disabled, "Join stays off")
	typed.call("ace 3")
	t.eq(s.code_msg.text, OnlineScreen.HINT, "still typing: no error, just the hint")
	t.check(s.join_btn.disabled, "Join waits for six characters")
	typed.call("ACE-347")
	t.check(not s.join_btn.disabled, "a whole code turns Join on")
	t.eq(s.code_msg.text, OnlineScreen.HINT, "no message for a good code")
	typed.call("ACE3479")
	t.check(s.code_msg.text.contains("6 characters"), "too long is said (%s)" % s.code_msg.text)
	typed.call("AC")
	s._join()
	t.check(s.code_msg.text.contains("6 characters"), "Join with a short code explains the length (%s)" % s.code_msg.text)
	t.eq(Social.parse_code("ace-347"), {"ok": true, "code": "ACE347"}, "the parser is unchanged")
	t.eq(OnlineScreen.short_message("\"B\" isn't used in party codes. Check the code and try again."), "\"B\" isn't used in party codes.", "first sentence only")
	await _end()


## The iOS keyboard on the code field: Back stays put and uncovered; the
## field and Join stay above the keyboard - without moving at a typical
## keyboard height, and moved by exactly the overlap when a taller keyboard
## would cover them; closing it puts everything back.
func test_friends_keyboard_keeps_field_and_join_reachable() -> void:
	await _begin()
	for d in _devices():
		var tag := String(d[0])
		await _size(d[1])
		var s: OnlineScreen = await _show(OnlineScreen.new())
		s.code_edit.grab_focus()
		await _frames(2)
		var before := s.keyboard_report()
		var view := _view()
		# keyboards in this device's points, emulated through whatever point
		# scale this lane runs at
		var pts: float = float(d[2]) if float(d[2]) > 0.0 else view.size.y / UIKit.units_per_point()
		var dev_upp := view.size.y / pts
		var typical := float(d[3]) * dev_upp / UIKit.units_per_point()
		# and one whose top is 40 units above the bottom of the code row
		var row_end: float = maxf((before["field"] as Rect2).end.y, (s.code_msg.get_global_rect()).end.y)
		var taller := (view.size.y - row_end + 40.0) / UIKit.units_per_point()
		for kb in [typical, taller]:
			UIKit.v7_emulated_keyboard_pt = kb
			await _frames(4)
			var r := s.keyboard_report()
			var top := view.size.y - float(r["keyboard"])
			t.check(float(r["keyboard"]) > 0.0, "%s: keyboard %d pt seen" % [tag, int(kb)])
			t.check((r["field"] as Rect2).end.y <= top + 0.5 and (r["join"] as Rect2).end.y <= top + 0.5,
				"%s: with a %d pt keyboard the field and Join stay above it (%.0f, %.0f vs %.0f)" % [tag, int(kb), (r["field"] as Rect2).end.y, (r["join"] as Rect2).end.y, top])
			t.check(_same(r["back"], before["back"]), "%s: Back doesn't move (%d pt)" % [tag, int(kb)])
			t.check((r["back"] as Rect2).end.y <= top, "%s: Back isn't covered (%d pt)" % [tag, int(kb)])
			t.check((r["field"] as Rect2).position.y >= s._sc.get_global_rect().position.y - 0.5, "%s: the field never slides under the header" % tag)
			t.check(_reaches(s.join_btn) and _reaches(s.code_edit), "%s: field and Join take a tap with the keyboard open" % tag)
			if kb == typical:
				t.check(_same(r["field"], before["field"]), "%s: a typical keyboard needs no movement (%s, was %s)" % [tag, str(r["field"]), str(before["field"])])
		UIKit.v7_emulated_keyboard_pt = 0.0
		await _frames(4)
		var after := s.keyboard_report()
		t.eq(after["scroll"], before["scroll"], "%s: closing the keyboard scrolls back" % tag)
		t.check(_same(after["field"], before["field"]), "%s: and the field is where it was" % tag)
		UIKit.v7_emulated_keyboard_pt = -1.0
		await _close()
	await _end()


# ------------------------------------------------------------- Settings
func test_settings_sections_reachable_aligned_and_whole() -> void:
	await _begin()
	for d in _devices():
		var tag := String(d[0])
		await _size(d[1])
		var s: SettingsScreen = await _show(SettingsScreen.new())
		var sc := s._sc
		var list := sc.get_global_rect()
		# the header: Back and the title, outside the list, always shown
		var back: Button = null
		for b in s.content.get_child(0).find_children("*", "Button", true, false):
			back = b
		t.check(back != null and not sc.is_ancestor_of(back) and _fully_shown(back) and _reaches(back), "%s: Back in a header that doesn't scroll" % tag)
		t.check(back != null and back.get_global_rect().end.y <= list.position.y + 0.5, "%s: the header sits above the list" % tag)
		t.eq(sc.scroll_vertical, 0, "%s: opens at the top" % tag)
		# the first view starts with the profile rows and reaches Controls
		var ctl_top := (s.sections["Controls"] as Control).get_global_rect().position.y
		t.check(ctl_top < list.end.y - 40.0, "%s: Controls starts in the first view (%.0f < %.0f)" % [tag, ctl_top, list.end.y])
		for title in SECTIONS:
			t.check(s.sections.has(title), "%s: section %s exists" % [tag, title])
			if not s.sections.has(title):
				continue
			var card: Control = s.sections[title]
			sc.scroll_vertical = int(card.get_global_rect().position.y - list.position.y + sc.scroll_vertical)
			await _frames(2)
			var head := card.get_global_rect()
			t.check(head.position.y >= list.position.y - 0.5 and head.position.y + 60.0 <= list.end.y,
				"%s: %s scrolls into view (%.0f in %.0f-%.0f)" % [tag, title, head.position.y, list.position.y, list.end.y])
			# every control in it can be brought fully into view, inside its card
			for n in card.find_children("*", "Control", true, false):
				var c := n as Control
				if not (c is BaseButton or c is Slider) or not c.is_visible_in_tree():
					continue
				sc.ensure_control_visible(c)
				await _frames(1)
				var r := c.get_global_rect()
				t.check(list.grow(0.5).encloses(r), "%s: '%s' (%s) can be shown whole" % [tag, _text_of(c), title])
				t.check(card.get_global_rect().grow(0.5).encloses(r), "%s: '%s' stays inside its card" % [tag, _text_of(c)])
				if c is Button:
					t.check(UIKit.v7_button_text_fits(c as Button), "%s: '%s' not trimmed" % [tag, _text_of(c)])
		# alignment: sliders and choices start on one column and end on one edge
		sc.scroll_vertical = 0
		await _frames(2)
		var lefts: Array = []
		var rights: Array = []
		for k in ["sensitivity", "sfx", "music", "stick_mode", "sprint_mode", "quality"]:
			var c: Control = s._rows[k]
			var r := c.get_global_rect()
			var row := c.get_parent() as Control
			# (a choice that moved under its label starts at the row's left)
			if r.position.y < row.get_global_rect().position.y + 4.0:
				lefts.append(snappedf(r.position.x, 1.0))
			rights.append(snappedf(r.end.x if not (c is Slider) else r.end.x + 16.0 + 84.0, 1.0))
		t.check(lefts.size() >= 3 and lefts.all(func(x: float) -> bool: return absf(x - float(lefts[0])) <= 1.0), "%s: sliders and choices share a column (%s)" % [tag, str(lefts)])
		t.check(rights.all(func(x: float) -> bool: return absf(x - float(rights[0])) <= 2.0), "%s: and a right edge (%s)" % [tag, str(rights)])
		# the Sprint choices: both options whole and inside the Controls card
		for b in (s._rows["sprint_mode"] as Control).get_children():
			t.check(UIKit.v7_button_text_fits(b as Button), "%s: Sprint '%s' whole" % [tag, (b as Button).text])
			t.check((s.sections["Controls"] as Control).get_global_rect().grow(0.5).encloses((b as Control).get_global_rect()), "%s: Sprint '%s' inside Controls" % [tag, (b as Button).text])
		await _audit(tag + " Settings", s)
		await _close()
	await _end()


## A finger swipe on the list scrolls it (from a label, a slider or a
## choice) and changes no setting; a tap still changes one.
func test_settings_scroll_by_finger_keeps_values() -> void:
	await _begin()
	await _size(Vector2i(2532, 1170))
	Save.set_setting("sprint_mode", "edge")
	Save.set_setting("music", 0.6)
	var keys := ["sensitivity", "invert_y", "reduced_motion", "sfx", "music", "quality", "stick_mode", "sprint_mode", "haptics"]
	var before := {}
	for k in keys:
		before[k] = Save.get_setting(k, null)
	var s: SettingsScreen = await _show(SettingsScreen.new())
	var sc := s._sc
	var list := sc.get_global_rect()
	var from := Vector2(list.position.x + 60.0, list.end.y - 40.0)
	await _swipe(from, Vector2(0, -360))
	t.check(sc.scroll_vertical > 150, "a swipe scrolled Settings (%d)" % sc.scroll_vertical)
	# swipe again starting on whatever is there now (sliders and choices included)
	for x in [0.55, 0.8]:
		var y0 := sc.scroll_vertical
		await _swipe(Vector2(list.position.x + list.size.x * x, list.end.y - 60.0), Vector2(0, -300))
		t.check(sc.scroll_vertical > y0 or sc.scroll_vertical >= int(sc.get_v_scroll_bar().max_value - sc.size.y) - 2, "swipe from %.0f%% across scrolled on" % (x * 100.0))
	for k in keys:
		t.eq(Save.get_setting(k, null), before[k], "swiping left '%s' unchanged" % k)
	# a real tap on Sprint › Sprint button saves it; the saved value shows on reopening
	var hold: Button = (s._rows["sprint_mode"] as Control).get_child(1)
	sc.ensure_control_visible(hold)
	await _frames(3)
	await _click(hold)
	t.eq(String(Save.get_setting("sprint_mode", "")), "hold", "a tap chooses Sprint button")
	await _close()
	s = await _show(SettingsScreen.new())
	t.check(UIKit.face_of((s._rows["sprint_mode"] as Control).get_child(1)).selected, "reopened Settings shows the saved choice")
	t.near((s._rows["music"] as HSlider).value, 0.6, 0.001, "the music volume shows its saved value")
	t.eq((s._rows["haptics"] as CheckButton).button_pressed, bool(Save.get_setting("haptics", true)), "the haptics switch shows its saved value")
	await _end()


## Delete Game Profile is kept apart from the routine profile actions and
## still asks first: a tap opens the confirmation and deletes nothing;
## Cancel keeps everything; Delete in the confirmation deletes.
func test_profile_delete_still_confirmed() -> void:
	await _begin()
	await _size(Vector2i(2532, 1170))
	Save.data["coins"] = 432
	var s: SettingsScreen = await _show(SettingsScreen.new())
	var del: Button = null
	for b in s.find_children("*", "Button", true, false):
		if (b as Button).text == "Delete Game Profile":
			del = b
	t.check(del != null, "Delete Game Profile is there")
	t.check((s.sections["Delete game profile"] as Control).is_ancestor_of(del), "in its own section")
	t.check(not (s.sections["Profile"] as Control).is_ancestor_of(del), "not among the routine profile actions")
	var keys := SECTIONS.map(func(x: String) -> Control: return s.sections[x])
	t.eq(s._body.get_children().find(s.sections["Delete game profile"]), s._body.get_child_count() - 1, "it is the last section")
	t.check(keys.size() == SECTIONS.size(), "(all sections)")
	s._sc.ensure_control_visible(del)
	await _frames(3)
	await _click(del)
	t.check(s.has_modal(), "a tap asks for confirmation")
	t.eq(int(Save.data["coins"]), 432, "nothing is deleted yet")
	var dlg: Control = s._modals[-1]["node"]
	var cancel: Button = null
	var yes: Button = null
	for b in dlg.find_children("*", "Button", true, false):
		if (b as Button).text == "Cancel":
			cancel = b
		elif (b as Button).text == "Delete":
			yes = b
	t.check(cancel != null and yes != null, "the confirmation offers Cancel and Delete")
	await _audit("delete confirmation", dlg)
	# the dim behind it takes taps meant for the screen
	t.check(not _reaches(del), "the screen behind the confirmation takes no taps")
	await _click(cancel)
	t.check(not s.has_modal(), "Cancel closes it")
	t.eq(int(Save.data["coins"]), 432, "Cancel deletes nothing")
	await _click(del)
	dlg = s._modals[-1]["node"] if s.has_modal() else null
	yes = null
	if dlg:
		for b in dlg.find_children("*", "Button", true, false):
			if (b as Button).text == "Delete":
				yes = b
	t.check(yes != null, "asked again")
	if yes:
		await _click(yes)
		await _frames(3)
		t.eq(int(Save.data["coins"]), 0, "Delete in the confirmation deletes the profile")
	await _end()


# ------------------------------------------------------------- sweep
func test_home_results_and_standings_fit_every_device() -> void:
	await _begin()
	var me := Save.player_uid()
	for d in _devices():
		var tag := String(d[0])
		await _size(d[1])
		var home: TitleScreen = await _show(TitleScreen.new())
		for c in [home.play_btn, home.practice_btn, home.emote_btn]:
			t.check(_fully_shown(c), "%s: home '%s' shown" % [tag, _text_of(c)])
		var tr := home.title_art.get_global_rect()
		var top_right := home.content.get_child(0) as Control
		t.check(tr.end.x <= home.play_btn.get_global_rect().position.x or tr.end.y <= home.play_btn.get_global_rect().position.y, "%s: the title clears the actions" % tag)
		t.check(top_right.get_global_rect().end.y <= home.play_btn.get_global_rect().position.y, "%s: the top row clears Play with Friends" % tag)
		await _audit(tag + " Home", home)
		await _close()
		# practice results
		var off := NetSession.new()
		t.add_child(off)
		off.start_offline(me, "Tester", {}, "runner")
		var r := ResultsScreen.new()
		r.results = _results(me, true)
		r.reward = {"coins": 12, "xp": 40, "level": 2, "lines": [["Played the round", 5], ["Made it home", 4]]}
		r.session = off
		await _show(r)
		await _audit(tag + " Results", r)
		await _close()
		off.queue_free()
		# the last round of a friend series, its final standings, then the end
		var host := NetSession.new()
		host.mode = NetSession.Mode.HOST
		host.local_slot = 0
		var res := _series_final(me)
		host.series_view = res["series"]
		t.add_child(host)
		var r2 := ResultsScreen.new()
		r2.results = res
		r2.reward = {"coins": 12, "xp": 40, "lines": []}
		r2.session = host
		await _show(r2)
		await _audit(tag + " Series round", r2)
		# Pass 8 hierarchy (replaces V7's "first table row in the first
		# view"): the first view shows whether your team won and why, your
		# contribution and your series standing; the round's tables follow
		# below the rewards and are reached by scrolling
		for nm in ["Outcome", "Why", "Contribution", "SeriesLine"]:
			var n := r2._v.find_child(nm, true, false) as Control
			t.check(n != null and _fully_shown(n), "%s: %s is in the first view (%s)" % [tag, nm, str(n.get_global_rect()) if n else "none"])
		var first: Control = null
		for pc in r2._v.find_children("*", "PanelContainer", true, false):
			if String((pc as Control).accessibility_name).contains(": "):
				first = pc
				break
		t.check(first != null, "%s: the round's table rows are there" % tag)
		if first != null:
			r2._sc.ensure_control_visible(first)
			await _frames(3)
			t.check(_fully_shown(first), "%s: the round's first table row scrolls into view (%s)" % [tag, str(first.get_global_rect())])
			r2._sc.scroll_vertical = 0
			await _frames(2)
		t.eq(r2._primary.text, "Final standings", "%s: the last round leads to Final standings" % tag)
		await _click(r2._primary)
		await _frames(4)
		t.eq(r2.page, "final", "%s: Final standings shown" % tag)
		var first_row := (r2._v.get_child(2) as Control).get_child(1) as Control
		t.check(_fully_shown(first_row), "%s: the first standings row is in the first view (%s)" % [tag, str(first_row.get_global_rect())])
		await _audit(tag + " Final standings", r2)
		r2._sc.scroll_vertical = 100000
		await _frames(3)
		await _audit(tag + " Final standings (end)", r2)
		await _close()
		host.queue_free()
	await _end()


func test_party_room_with_one_four_and_eight_players_fits() -> void:
	await _begin()
	var saved_uid: Variant = Save.data["uid"]
	for d in _devices():
		var tag := String(d[0])
		await _size(d[1])
		for n in [1, 4, 8]:
			var rig := NetRig.new()
			t.add_child(rig)
			rig.setup(0, 0, 0.0, n - 1)
			await rig.wait_until(func() -> bool: return rig.host.human_count() == n, 300)
			Save.data["uid"] = "uid-host"
			App.session = rig.host
			App.show_lobby()
			await _frames(10)
			var l := App.screen as LobbyScreen
			var ptag := "%s party room (%d)" % [tag, n]
			t.check(l != null, "%s: shown" % ptag)
			if l:
				var shown := 0
				for c in l.cells:
					if c.visible:
						shown += 1
						t.check(_fully_shown(c), "%s: roster card shown" % ptag)
				t.eq(shown, mini(8, n + 1), "%s: everyone plus one open seat while there's room" % ptag)
				# the roster, top bar and bottom bar never overlap
				var roster := l.roster_col.get_global_rect()
				t.check(not roster.intersects(l.top_bar.get_global_rect().grow(-0.5)), "%s: roster clears the top bar" % ptag)
				t.check(not roster.intersects(l.bottom_bar.get_global_rect().grow(-0.5)), "%s: roster clears the bottom bar" % ptag)
				t.check(not roster.intersects(l.primary_btn.get_global_rect().grow(-0.5)), "%s: roster clears the primary action" % ptag)
				await _audit(ptag, l, [])
				# everyone on the stage stands clear of the roster (faces and arms)
				var guard := 0
				while App.stage._cam_t < 1.0 and guard < 200:
					await _frames(1)
					guard += 1
				var cam := App.stage.cam
				var right := cam.global_transform.basis.x
				var worst := -INF
				for k in App.stage.chars:
					var v: CharacterView = App.stage.chars[k]
					for pnt in [Vector3(0, 1.2, 0), Vector3(0.5, 0.9, 0), Vector3(0, 1.6, 0)]:
						var sp := cam.unproject_position(v.global_position + right * pnt.x + Vector3(0, pnt.y, 0))
						worst = maxf(worst, sp.x)
				t.check(worst <= roster.position.x, "%s: every runner stands left of the roster (rightmost %.0f, roster at %.0f)" % [ptag, worst, roster.position.x])
				# the leave confirmation
				l._go_back()
				await _frames(3)
				t.check(l.has_modal(), "%s: Back asks before leaving" % ptag)
				if l.has_modal():
					await _audit(ptag + " leave confirmation", l._modals[-1]["node"])
					l._unhandled_input(_cancel_event())
					await _frames(3)
				t.check(not l.has_modal() and App.session == rig.host, "%s: Stay keeps the party" % ptag)
			await _close()
			App.session = null
			rig.teardown()
			rig.queue_free()
			await _frames(2)
	Save.data["uid"] = saved_uid
	await _end()


## Sheets whose rows grow with the data stay on screen: a long block list
## (Settings › Blocked players) and eight friends' series standings (the
## party room's Standings) scroll inside their sheet.
func test_long_lists_stay_inside_their_sheets() -> void:
	await _begin()
	var saved_uid: Variant = Save.data["uid"]
	for d in _devices():
		var tag := String(d[0])
		await _size(d[1])
		var blocked: Array = []
		for i in 14:
			blocked.append({"pid": "", "uid": "u%d" % i, "name": "Comfy Frog %d" % i})
		Save.data["blocked"] = blocked
		var s: SettingsScreen = await _show(SettingsScreen.new())
		s._blocked_sheet()
		await _frames(4)
		var dlg: Control = s._modals[-1]["node"]
		t.check(_safe().grow(0.5).encloses(dlg.get_global_rect()), "%s: 14 blocked players: the sheet fits (%s in %s)" % [tag, str(dlg.get_global_rect()), str(_safe())])
		var lists := dlg.find_children("*", "ScrollContainer", true, false)
		t.check(lists.size() == 1 and (lists[0] as ScrollContainer).get_v_scroll_bar().max_value > (lists[0] as ScrollContainer).size.y, "%s: and its list scrolls" % tag)
		await _audit(tag + " blocked players", dlg)
		Save.data["blocked"] = []
		await _close()
		# eight friends in a series: the party room's Standings sheet
		var rig := NetRig.new()
		t.add_child(rig)
		rig.setup(0, 0, 0.0, 1)
		await rig.wait_until(func() -> bool: return rig.host.human_count() == 2, 300)
		Save.data["uid"] = "uid-host"
		var ps := PartySeries.new()
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		ps.start({"watch": 2, "rounds": 3}, rng)
		for k in 2:
			var rk := _results("uid-host", false)
			for row in rk["players"]:
				(row as Dictionary)["is_bot"] = false
				(row as Dictionary)["uid"] = "uid-host" if int(row["slot"]) == 0 else "friend-%d" % int(row["slot"])
			rk["match_id"] = "v7-st-%d" % k
			ps.record_round(rk)
		rig.host.series_view = ps.to_dict()
		App.session = rig.host
		App.show_lobby()
		await _frames(8)
		var l := App.screen as LobbyScreen
		l._standings_sheet()
		await _frames(4)
		var root: Control = l._modals[-1]["node"]
		var sheet := root.get_child(1) as Control
		t.check(_safe().grow(0.5).encloses(sheet.get_global_rect()), "%s: eight friends' standings fit (%s in %s)" % [tag, str(sheet.get_global_rect()), str(_safe())])
		await _audit(tag + " standings sheet", sheet)
		await _close()
		App.session = null
		rig.teardown()
		rig.queue_free()
		await _frames(2)
	Save.data["uid"] = saved_uid
	await _end()


func _cancel_event() -> InputEvent:
	var ev := InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	return ev


func _results(me: String, practice: bool) -> Dictionary:
	var names := ["Tester", "Pip", "Rowan", "Snooze", "Biscuit", "Marigold Moonpup", "Dozy", "Pajama Sam"]
	var rows: Array = []
	for i in 8:
		var bot := i in [3, 4, 6, 7]
		var runner := i not in [2, 6]
		var r := {"slot": i, "uid": me if i == 0 else ("f%d" % i if not bot else "bot-%d" % i), "name": names[i], "is_bot": bot,
			"role": TC.Role.RUNNER if runner else TC.Role.PATROL, "present": true, "away_s": 0.0}
		if runner:
			r["stamps"] = 3 if i in [0, 1, 4, 5] else 1
			r["finished"] = i in [0, 1, 4, 5]
			r["finish_order"] = {0: 2, 1: 1, 4: 4, 5: 3}.get(i, 0)
			r["finish_time"] = 120.0 + i * 9.0
		else:
			r["captures"] = 3
			r["unique_captures"] = 2
		rows.append(r)
	return {"match_id": "v7-test-%s" % ("p" if practice else "s"), "outcome": TC.Outcome.RUNNERS_WIN, "players": rows,
		"finished": 4, "needed": 4, "round_time": 171.0, "practice": practice}


func _series_final(me: String) -> Dictionary:
	var ps := PartySeries.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	ps.start({"watch": 2, "rounds": 3}, rng)
	for k in 3:
		var rk := _results(me, false)
		rk["match_id"] = "v7-test-s%d" % k
		rk["outcome"] = TC.Outcome.PATROL_WIN if k == 1 else TC.Outcome.RUNNERS_WIN
		ps.record_round(rk)
	var res := _results(me, false)
	res["match_id"] = "v7-test-s2"
	res["series"] = ps.to_dict()
	res["round_index"] = 3
	res["rounds_total"] = 3
	return res
