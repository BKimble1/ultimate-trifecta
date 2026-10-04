extends Node
## Development-only evidence for the V7 screens pass (created by capture.gd
## for --capture=v7_screens; src/dev/ is excluded from iOS exports).  Shots go
## through capture.gd's snap() (PNG + render report); next to each PNG a
## <shot>_layout.json holds the final allocated rect of every visible
## control (canvas units), the viewport, the safe area, touch_min() and what
## is clipped, off screen, outside the safe area or trimmed.
##
## One run walks: Home, Play with Friends (resting; an emulated iOS keyboard
## open on the code field; a mistyped code), Settings (top, then scrolled to
## Controls, Sound, Graphics, Diagnostics and the end), the Delete Game
## Profile confirmation, practice results, the last round of a friend series
## and its final standings, then an in-process party room (loopback
## transport, no network) with 1 and 4 players and its leave confirmation.
##
## --emulate-keyboard=<points> sets the keyboard height used for the
## keyboard shot (default: 209 pt on notched phones, 194 pt on 16:9 phones,
## 398 pt on iPad: typical iOS landscape keyboards with the QuickType bar).
## The keyboard itself is drawn as a labelled grey block; the screen reacts
## through UIKit's V7 keyboard hook (none before V7).
## Layout evidence on desktop Linux (llvmpipe): not device input or timing.

var cap: Node
var _t := 0.0
var _at := 0.0
var _step := 0
var _hub: LoopbackTransport.Hub
var _host: NetSession
var _clients: Array[NetSession] = []
var _kb_layer: CanvasLayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_at = 5.0


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
	var delay: float = (steps[_step][1] as Callable).call()
	_step += 1
	_at = _t + delay


## [group, step]; --v7-only=friends,settings,... keeps only those groups
## (home friends settings confirm results party).
func _steps() -> Array:
	var all := [
		["home", _home], ["friends", _friends], ["friends", _friends_keyboard], ["friends", _friends_invalid],
		["settings", _settings_top], ["settings", _settings_section.bind("Controls")], ["settings", _settings_section.bind("Sound")],
		["settings", _settings_section.bind("Graphics")], ["settings", _settings_section.bind("Diagnostics (beta)")],
		["settings", _settings_end], ["confirm", _confirm_delete], ["results", _results_practice], ["results", _results_series],
		["results", _final_standings], ["results", _final_standings_end], ["party", _party.bind(1)], ["party", _party.bind(4)],
		["party", _party_leave],
	]
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--v7-only="):
			only = a.get_slice("=", 1)
	var out: Array = []
	for st in all:
		if only == "" or String(st[0]) in only.split(","):
			out.append(st)
	out.append(["end", _quit])
	return out


func _snap(n: String) -> void:
	cap.call("snap", n)
	_audit.call_deferred(n)


# --------------------------------------------------------------- steps
func _home() -> float:
	_snap("home")
	return 1.0


func _friends() -> float:
	App.goto(OnlineScreen)
	_later(2.2, "friends")
	return 3.0


func _friends_keyboard() -> float:
	var s := App.screen as OnlineScreen
	if s and is_instance_valid(s.code_edit):
		s.code_edit.grab_focus()
		s.code_edit.text = "ACE34"
		s.code_edit.text_changed.emit(s.code_edit.text)
	_keyboard(true)
	_later(1.6, "friends_keyboard")
	return 2.2


func _friends_invalid() -> float:
	var s := App.screen as OnlineScreen
	_keyboard(false)
	if s and is_instance_valid(s.code_edit):
		s.code_edit.release_focus()
		s.code_edit.text = "ACE-3B7"
		s.code_edit.text_changed.emit(s.code_edit.text)
	_later(1.0, "friends_invalid")
	return 1.6


func _settings_top() -> float:
	App.goto(SettingsScreen)
	_later(2.2, "settings_top")
	return 3.0


func _settings_list() -> ScrollContainer:
	var best: ScrollContainer = null
	for sc in App.screen.find_children("*", "ScrollContainer", true, false):
		var s := sc as ScrollContainer
		if s.is_visible_in_tree() and (best == null or s.size.y > best.size.y):
			best = s
	return best


func _settings_section(title: String) -> float:
	var sc := _settings_list()
	if sc:
		for l in App.screen.find_children("*", "Label", true, false):
			var lb := l as Label
			if lb.text.to_lower() == title.to_lower() and sc.is_ancestor_of(lb):
				var y := lb.get_global_rect().position.y - sc.get_global_rect().position.y + float(sc.scroll_vertical)
				sc.scroll_vertical = int(maxf(0.0, y - 8.0))
				break
	_later(0.9, "settings_" + title.split(" ")[0].to_lower())
	return 1.5


func _settings_end() -> float:
	var sc := _settings_list()
	if sc:
		sc.scroll_vertical = 1000000
	_later(0.9, "settings_end")
	return 1.5


func _confirm_delete() -> float:
	if not (App.screen is SettingsScreen):
		App.goto(SettingsScreen)
		get_tree().create_timer(1.5).timeout.connect(_confirm_delete)
		return 3.5
	var sc := _settings_list()
	if sc:
		sc.scroll_vertical = 0
	(App.screen as SettingsScreen)._confirm_delete()
	_later(1.2, "confirm_delete")
	return 1.8


func _rows(me: String) -> Array:
	var names := ["Comfy Frog", "Pip", "Rowan", "Snooze", "Biscuit", "Marigold Moonpup", "Dozy", "Pajama Sam"]
	var out: Array = []
	for i in 8:
		var bot := i in [3, 4, 6, 7]
		var uid := me if i == 0 else ("friend-%d" % i if not bot else "bot-%d" % i)
		var runner := i not in [2, 6]
		var r := {"slot": i, "uid": uid, "name": names[i], "is_bot": bot, "role": TC.Role.RUNNER if runner else TC.Role.PATROL,
			"present": true, "away_s": 0.0, "cosmetic": Cosmetics.bot_cosmetic(31 + i * 7)}
		if runner:
			r["stamps"] = [3, 3, 0, 2, 3, 3, 0, 1][i]
			r["finished"] = i in [0, 1, 4, 5]
			r["finish_order"] = {0: 2, 1: 1, 4: 4, 5: 3}.get(i, 0)
			r["finish_time"] = {0: 141.0, 1: 128.0, 4: 171.0, 5: 160.0}.get(i, -1.0)
			r["times_captured"] = [1, 0, 0, 2, 1, 0, 0, 3][i]
		else:
			r["captures"] = 4 if i == 2 else 2
			r["unique_captures"] = 3 if i == 2 else 2
		out.append(r)
	out[0]["cosmetic"] = Save.data["cosmetic"]
	return out


func _results(practice: bool) -> Dictionary:
	return {"match_id": "v7-cap-%s" % ("p" if practice else "s"), "outcome": TC.Outcome.RUNNERS_WIN, "players": _rows(Save.player_uid()),
		"finished": 4, "needed": 4, "round_time": 171.0, "practice": practice}


func _reward() -> Dictionary:
	return {"coins": 12, "xp": 40, "level": 2, "lines": [["Played the round", 5], ["Splashes x3", 3], ["Made it home", 4]]}


func _results_practice() -> float:
	var off := NetSession.new()
	add_child(off)
	off.start_offline(Save.player_uid(), Save.player_name(), Save.data["cosmetic"], "runner")
	var r := ResultsScreen.new()
	r.results = _results(true)
	r.reward = _reward()
	r.session = off
	App._ensure_background()
	App._show(r)
	_later(2.4, "results_practice")
	return 3.2


func _results_series() -> float:
	var me := Save.player_uid()
	var ps := PartySeries.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	ps.start({"watch": 2, "rounds": 3}, rng)
	for k in 3:
		var rk := _results(false)
		rk["match_id"] = "v7-cap-s%d" % k
		rk["outcome"] = TC.Outcome.PATROL_WIN if k == 1 else TC.Outcome.RUNNERS_WIN
		if k == 1:
			for row in rk["players"]:
				var d: Dictionary = row
				if String(d["uid"]) == me:
					d["role"] = TC.Role.PATROL
					d["captures"] = 3
					d["unique_captures"] = 2
		ps.record_round(rk)
	var res := _results(false)
	res["match_id"] = "v7-cap-s2"
	res["series"] = ps.to_dict()
	res["round_index"] = 3
	res["rounds_total"] = 3
	var host := NetSession.new()
	host.mode = NetSession.Mode.HOST
	host.local_slot = 0
	host.series_view = res["series"]
	add_child(host)
	var r := ResultsScreen.new()
	r.results = res
	r.reward = _reward()
	r.session = host
	App._ensure_background()
	App._show(r)
	_later(2.4, "results_series_round")
	return 3.2


func _final_standings() -> float:
	var r := App.screen as ResultsScreen
	if r:
		r._on_primary()
	_later(1.4, "final_standings")
	return 2.0


func _final_standings_end() -> float:
	for sc in App.screen.find_children("*", "ScrollContainer", true, false):
		(sc as ScrollContainer).scroll_vertical = 1000000
	_later(0.9, "final_standings_end")
	return 1.5


## A party room on the in-process loopback transport (no network): this
## device hosts; n-1 guests join with their own looks and are marked ready.
func _party(n: int) -> float:
	if _hub == null:
		_hub = LoopbackTransport.Hub.new(7)
		var ht := LoopbackTransport.new(_hub, true)
		_host = NetSession.new()
		_host.name = "V7CaptureHost"
		add_child(_host)
		_host.start_host(ht, "ACE347", Save.player_uid(), Save.party_name(), Save.data["cosmetic"], "any")
		App.session = _host
	var names := ["Pip", "Rowan", "Biscuit", "Marigold Moonpup", "Dozy", "Pajama Sam", "Wren"]
	while _clients.size() < n - 1:
		var i := _clients.size()
		var ct := LoopbackTransport.new(_hub, false)
		var c := NetSession.new()
		c.name = "V7CaptureGuest%d" % i
		add_child(c)
		c.start_client(ct, "ACE347", "guest-%d" % i, names[i], Cosmetics.bot_cosmetic(101 + i * 13), "any")
		_clients.append(c)
		_hub.link(ht_id(), ct.id)
	if not (App.screen is LobbyScreen):
		App.show_lobby()
	get_tree().create_timer(1.2).timeout.connect(func() -> void:
		for c in _clients:
			if c.local_slot >= 0:
				c.set_local_ready(true))
	_later(3.6, "party_%dp" % n)
	return 4.4


func ht_id() -> int:
	return (_host.transport as LoopbackTransport).id


func _party_leave() -> float:
	var l := App.screen as LobbyScreen
	if l:
		l._go_back()
	_later(1.2, "confirm_leave_party")
	return 1.8


func _quit() -> float:
	get_tree().quit()
	return 99.0


func _later(delay: float, shot: String) -> void:
	get_tree().create_timer(delay).timeout.connect(_snap.bind(shot))


# --------------------------------------------------------------- keyboard
func _kb_points() -> float:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--emulate-keyboard="):
			return a.get_slice("=", 1).to_float()
	var vs := get_viewport().get_visible_rect().size
	if vs.x / vs.y < 1.5:
		return 398.0
	return 194.0 if vs.x / vs.y < 1.9 else 209.0


func _keyboard(on: bool) -> void:
	var pts := _kb_points() if on else 0.0
	var kit: GDScript = load("res://src/ui/ui_kit.gd")
	kit.set("v7_emulated_keyboard_pt", pts)   # (no such hook before V7: no effect)
	if _kb_layer:
		_kb_layer.queue_free()
		_kb_layer = null
	if not on:
		return
	_kb_layer = CanvasLayer.new()
	_kb_layer.layer = 120
	add_child(_kb_layer)
	var vs := get_viewport().get_visible_rect().size
	var h := pts * UIKit.units_per_point()
	var r := ColorRect.new()
	r.color = Color(0.24, 0.25, 0.28, 0.94)
	r.position = Vector2(0, vs.y - h)
	r.size = Vector2(vs.x, h)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kb_layer.add_child(r)
	var l := UIKit.label("iOS keyboard (emulated, %d pt)" % int(pts), 22, Color(1, 1, 1, 0.75), true, HORIZONTAL_ALIGNMENT_CENTER)
	l.position = Vector2(0, vs.y - h * 0.5 - 16)
	l.size = Vector2(vs.x, 32)
	_kb_layer.add_child(l)


# --------------------------------------------------------------- layout audit
func _audit(shot: String) -> void:
	await RenderingServer.frame_post_draw
	if App.screen == null or not is_instance_valid(App.screen):
		return
	var vp := get_viewport()
	var view := vp.get_visible_rect()
	var safe := UIKit.safe_rect(vp, view.size)
	var kb := float(_kb_points() * UIKit.units_per_point()) if _kb_layer != null else 0.0
	var items: Array = []
	var issues: Array = []
	for n in App.screen.find_children("*", "Control", true, false):
		var c := n as Control
		if not c.is_visible_in_tree():
			continue
		var kind := ""
		if c is LineEdit:
			kind = "field"
		elif c is Slider:
			kind = "slider"
		elif c is BaseButton:
			kind = "button"
		elif c is Label:
			kind = "label"
		else:
			continue
		var r := c.get_global_rect()
		var text := _text_of(c)
		var it := {"kind": kind, "text": text, "rect": [snappedf(r.position.x, 0.1), snappedf(r.position.y, 0.1), snappedf(r.size.x, 0.1), snappedf(r.size.y, 0.1)]}
		var clip := _clip_rect(c)
		var shown := r.intersection(clip) if clip.size != Vector2.ZERO else r
		if clip.size != Vector2.ZERO and not clip.grow(0.5).encloses(r):
			it["clipped"] = "scrolled out" if shown.size.x <= 0.0 or shown.size.y <= 0.0 else "partly visible"
		if not view.grow(0.5).encloses(r) and not it.has("clipped"):
			it["offscreen"] = true
			issues.append("offscreen %s '%s' %s" % [kind, text, str(r)])
		elif kind != "label" and not safe.grow(0.5).encloses(r) and not it.has("clipped"):
			it["outside_safe"] = true
			issues.append("outside safe area %s '%s'" % [kind, text])
		if kb > 0.0 and r.end.y > view.size.y - kb and kind != "label" and not it.has("clipped"):
			it["under_keyboard"] = true
		if kind != "label" and (r.size.x < UIKit.touch_min() - 0.5 or r.size.y < UIKit.touch_min() - 0.5) and not (c is CheckButton and r.size.y >= UIKit.touch_min() - 0.5):
			it["small_target"] = true
		var trim := _trimmed(c)
		if trim:
			it["trimmed"] = true
			issues.append("trimmed %s '%s'" % [kind, text])
		items.append(it)
	var out := {"shot": shot, "viewport": [view.size.x, view.size.y], "safe": [safe.position.x, safe.position.y, safe.size.x, safe.size.y],
		"touch_min": UIKit.touch_min(), "units_per_point": UIKit.units_per_point(), "keyboard_units": kb,
		"screen": App.screen.get_class() if App.screen.get_script() == null else String((App.screen.get_script() as Script).get_global_name()),
		"issues": issues, "controls": items}
	var f := FileAccess.open(String(cap.get("out_dir")).path_join(shot + "_layout.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, "  "))
	printerr("LAYOUT %s issues=%d %s" % [shot, issues.size(), "; ".join(PackedStringArray(issues.slice(0, 6)))])


func _text_of(c: Control) -> String:
	if c is LineEdit:
		return (c as LineEdit).text if (c as LineEdit).text != "" else (c as LineEdit).placeholder_text
	if c is Label:
		return (c as Label).text.substr(0, 60)
	if c is Button:
		var b := c as Button
		var f := UIKit.face_of(b)
		if b.text != "":
			return b.text
		if f != null and f.caption != "":
			return f.caption
		if b.tooltip_text != "":
			return b.tooltip_text
		var ls := b.find_children("*", "Label", true, false)
		return (ls[0] as Label).text if not ls.is_empty() else b.accessibility_name
	return ""


## The visible region of a control: its nearest scrolling list (or a
## clipping parent).
func _clip_rect(c: Control) -> Rect2:
	var p := c.get_parent()
	while p != null and p is Control:
		if p is ScrollContainer or (p as Control).clip_contents:
			return (p as Control).get_global_rect()
		p = p.get_parent()
	return Rect2()


func _trimmed(c: Control) -> bool:
	if c is Button:
		var b := c as Button
		var f := UIKit.face_of(b)
		if b.text == "":
			return false
		var font: Font = b.get_theme_font("font")
		var fs: int = b.get_theme_font_size("font_size")
		var pad := f.text_pad() if f != null else 8.0
		return font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > b.size.x - pad * 2.0 + 0.5
	if c is Label:
		var l := c as Label
		if l.autowrap_mode != TextServer.AUTOWRAP_OFF or l.text == "":
			return false
		if not l.clip_text and l.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING:
			return false
		var font2: Font = l.get_theme_font("font")
		var fs2: int = l.get_theme_font_size("font_size")
		var txt := l.text.to_upper() if l.uppercase else l.text
		return font2.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x > l.size.x + 0.5
	return false
