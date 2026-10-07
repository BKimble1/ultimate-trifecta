extends Node
## Development-only evidence for the map chooser (created by capture.gd for
## --capture=maps_ui; src/dev/ is excluded from iOS exports): Practice's Map
## row and its sheet (the new campus selected, then Moonbrook College
## picked), the party settings' Map row and sheet for the host, the same for
## a guest (read-only: the host's choice, Close), and the controller path
## (focus moved to the other card with the D-pad, Cancel closes the sheet
## and focus is back on the Map row).  A loopback party (no network).
## Layout evidence on desktop Linux (llvmpipe): not device input or timing.

var cap: Node
var _t := 0.0
var _at := 0.0
var _step := 0
var _hub: LoopbackTransport.Hub
var _host: NetSession
var _guest: NetSession


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_at = 5.0
	Save.set_setting("practice_map", CampusMaps.CAMPUS)


func _physics_process(delta: float) -> void:
	if _hub != null:
		_hub.advance(delta)


func _process(delta: float) -> void:
	_t += delta
	if _t < _at:
		return
	var steps := _steps()
	if _step >= steps.size():
		return
	var delay: float = (steps[_step] as Callable).call()
	_step += 1
	_at = _t + delay


func _steps() -> Array:
	return [_practice, _practice_sheet, _practice_pad_right, _practice_pick_classic, _practice_sheet_again,
		_practice_cancel, _party, _host_settings, _host_sheet, _host_pick_classic, _guest_view, _guest_settings,
		_guest_sheet, _quit]


func _snap(n: String) -> void:
	cap.call("snap", n)


func _later(delay: float, shot: String) -> void:
	get_tree().create_timer(delay).timeout.connect(_snap.bind(shot))


func _top_sheet() -> Control:
	# the open MapSheet: the last full-rect child with the dimmer
	var s := App.screen
	if s == null:
		return null
	for i in range(s.get_child_count() - 1, -1, -1):
		var c := s.get_child(i) as Control
		if c != null and c.get_child_count() >= 2 and c.get_child(0) is ColorRect:
			return c
	return null


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event.call_deferred(up)


func _map_row(root: Node) -> Button:
	for c in root.find_children("*", "Button", true, false):
		if String((c as Button).accessibility_name).begins_with("Map:"):
			return c
	return null


# ---------------------------------------------------------------- Practice
func _practice() -> float:
	App.goto(PracticeScreen)
	_later(2.0, "practice_map_row")
	return 2.6


func _practice_sheet() -> float:
	var row := _map_row(App.screen)
	if row:
		row.grab_focus()
		row.pressed.emit()
	_later(1.2, "practice_sheet_campus_selected")
	return 1.8


func _practice_pad_right() -> float:
	# controller: the D-pad moves focus to the other card (the focus ring,
	# not colour alone, shows which)
	_press("ui_left")
	_later(0.8, "practice_sheet_focus_other_card")
	return 1.4


func _practice_pick_classic() -> float:
	_press("ui_accept")
	_later(1.2, "practice_map_row_classic")
	return 1.8


func _practice_sheet_again() -> float:
	var row := _map_row(App.screen)
	if row:
		row.grab_focus()
		row.pressed.emit()
	_later(1.2, "practice_sheet_classic_selected")
	return 1.8


func _practice_cancel() -> float:
	_press("ui_cancel")
	get_tree().create_timer(0.8).timeout.connect(func() -> void:
		var f := get_viewport().gui_get_focus_owner()
		printerr("FOCUS after cancel: %s" % (f.accessibility_name if f is Button else str(f)))
		_snap("practice_after_cancel_focus_on_row"))
	return 1.6


# ------------------------------------------------------------------- party
func _party() -> float:
	Save.set_setting("practice_map", CampusMaps.CAMPUS)
	_hub = LoopbackTransport.Hub.new(7)
	var ht := LoopbackTransport.new(_hub, true)
	_host = NetSession.new()
	_host.name = "MapsCaptureHost"
	add_child(_host)
	_host.start_host(ht, "MAP247", Save.player_uid(), Save.party_name(), Save.data["cosmetic"], "any")
	_host.host_set_settings(2, 3, CampusMaps.CAMPUS)
	App.session = _host
	var ct := LoopbackTransport.new(_hub, false)
	_guest = NetSession.new()
	_guest.name = "MapsCaptureGuest"
	add_child(_guest)
	_guest.start_client(ct, "MAP247", "guest-maps", "Rowan", Cosmetics.bot_cosmetic(113), "any")
	_hub.link(ht.id, ct.id)
	App.show_lobby()
	_later(3.0, "party_host")
	return 3.6


func _host_settings() -> float:
	var l := App.screen as LobbyScreen
	if l:
		l._settings_sheet()
	_later(1.2, "party_host_settings_map_row")
	return 1.8


func _host_sheet() -> float:
	var row := _map_row(App.screen)
	if row:
		row.grab_focus()
		row.pressed.emit()
	_later(1.2, "party_host_map_sheet")
	return 1.8


func _host_pick_classic() -> float:
	_press("ui_left")
	get_tree().create_timer(0.5).timeout.connect(func() -> void: _press("ui_accept"))
	_later(1.6, "party_host_settings_classic")
	return 2.2


func _guest_view() -> float:
	# the guest's own lobby: the same party seen from the guest session
	printerr("GUEST settings map: %s" % String(_guest.settings.get("map", "")))
	App.session = _guest
	App.show_lobby()
	_later(2.4, "party_guest")
	return 3.0


func _guest_settings() -> float:
	var l := App.screen as LobbyScreen
	if l:
		l._settings_sheet()
	_later(1.2, "party_guest_settings_read_only")
	return 1.8


func _guest_sheet() -> float:
	var row := _map_row(App.screen)
	if row:
		row.pressed.emit()
	_later(1.2, "party_guest_map_sheet_read_only")
	return 1.8


func _quit() -> float:
	get_tree().quit()
	return 99.0
