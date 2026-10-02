extends RefCounted
## Controller / keyboard menu navigation: every menu screen opens with a
## focused control, and moving focus up/down/left/right from there reaches
## every visible enabled button (nothing is stranded).  Dialogs and sheets
## keep focus inside themselves, Back closes them, and focus returns to the
## control that opened them.  The code field never traps a controller.
var t
const SIDES := [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]
var _saved_device := ""


func _open(cls: GDScript) -> Screen:
	App._ensure_background()
	var s: Screen = cls.new()
	App._show(s)
	for i in 4:
		await t.get_tree().process_frame
	return s


func _close() -> void:
	if App.screen and is_instance_valid(App.screen):
		App.screen.queue_free()
	App.screen = null
	App._clear_background()
	await t.get_tree().process_frame


func _focused() -> Control:
	return t.get_viewport().gui_get_focus_owner()


func _targets(root: Node) -> Array:
	var out: Array = []
	for c in root.find_children("*", "BaseButton", true, false):
		var b := c as BaseButton
		if b.is_visible_in_tree() and not b.disabled and b.focus_mode == Control.FOCUS_ALL and b.get_global_rect().size.x > 1.0:
			out.append(b)
	return out


## Controls reachable with the four directions from `start`.
func _reach(start: Control) -> Dictionary:
	var seen := {start: true}
	var q: Array = [start]
	while not q.is_empty():
		var c: Control = q.pop_front()
		for side in SIDES:
			var n: Control = c.find_valid_focus_neighbor(side)
			if n != null and not seen.has(n):
				seen[n] = true
				q.append(n)
	return seen


func _check_screen(cls: GDScript, label: String) -> void:
	var s := await _open(cls)
	var f := _focused()
	t.check(f != null and s.is_ancestor_of(f), "%s opens with a focused control" % label)
	if f == null:
		await _close()
		return
	var seen := _reach(f)
	var missing: Array = []
	for b in _targets(s):
		if not seen.has(b):
			missing.append((b as Button).text if b is Button else b.name)
	t.eq(missing, [], "%s: every button is reachable with the d-pad" % label)
	await _close()


func test_menu_screens_are_fully_navigable() -> void:
	_saved_device = Controls.device
	Controls.device = "gamepad"
	Save.data["onboarded"] = true
	for pair in [[TitleScreen, "Home"], [OnlineScreen, "Play with Friends"], [PracticeScreen, "Practice"],
			[SettingsScreen, "Settings"], [HowToScreen, "How to play"], [CreatorScreen, "Create Your Runner"]]:
		await _check_screen(pair[0], pair[1])
	Controls.device = _saved_device


func test_code_entry_never_traps_a_controller() -> void:
	_saved_device = Controls.device
	Controls.device = "gamepad"
	var s: OnlineScreen = await _open(OnlineScreen)
	s._on_device("gamepad")
	t.eq(s.code_edit.focus_mode, Control.FOCUS_NONE, "the text field leaves controller focus")
	t.check(s.code_pad.visible == s.code_edit.editable, "the code pad replaces it while the controller is used")
	if s.code_edit.editable:
		for ch in "AC3":
			s._pad_key(ch)
		s._pad_key("")
		t.eq(s.code_edit.text, "AC", "pad types and deletes")
	s._on_device("touch")
	t.eq(s.code_edit.focus_mode, Control.FOCUS_ALL, "touch/keyboard type into the field again")
	t.check(not s.code_pad.visible, "pad hidden for touch")
	await _close()
	Controls.device = _saved_device


func test_dialogs_trap_focus_close_on_back_and_restore_focus() -> void:
	var s: SettingsScreen = await _open(SettingsScreen)
	var opener: Button = null
	for b in s.find_children("*", "Button", true, false):
		if (b as Button).text == "Delete Game Profile":
			opener = b
	t.check(opener != null, "found the opener")
	opener.grab_focus()
	await t.get_tree().process_frame
	s._confirm_delete()
	for i in 3:
		await t.get_tree().process_frame
	var dlg: Node = s._modals[-1]["node"] if s.has_modal() else null
	t.check(dlg != null and dlg.is_ancestor_of(_focused()), "focus moves into the dialog")
	var escaped := false
	for c in _reach(_focused()):
		if not dlg.is_ancestor_of(c):
			escaped = true
	t.check(not escaped, "d-pad can't leave the dialog")
	var ev := InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	s._unhandled_input(ev)
	for i in 3:
		await t.get_tree().process_frame
	t.check(not s.has_modal(), "Back closes the dialog (Cancel, nothing deleted)")
	t.check(App.screen == s, "and stays on the screen")
	t.eq(_focused(), opener, "focus returns to the button that opened it")
	await _close()
