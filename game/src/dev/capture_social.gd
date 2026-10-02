extends Node
## Development-only evidence for the V6 social work (created by capture.gd
## for --capture=social_*; src/dev/ is excluded from iOS exports).  Shots go
## through capture.gd's snap() (PNG + render report).  Scenarios:
##   social_hub      host of a LAN dev room (--capture-players=N): the menu
##                   composition, then Walk around (the host's stick is
##                   driven by this script), members walking (their
##                   headless clients run social_bot), Quick Chat bubbles,
##                   the chat drawer, a player card and the report sheet
##                   (the service is off in these runs: it says reports are
##                   unavailable and sends nothing)
##   social_bot      a headless client: walks a loop around its mark and
##                   sends a Quick Chat phrase now and then
##   social_names    the name sheet refusing a name, its suggestions, and a
##                   suggestion tapped
##   social_results  a recorded bot round (--capture-results=path) shown as
##                   round 3 of a friend series (two bot seats relabelled as
##                   friends, earlier rounds recorded through PartySeries):
##                   the round page, scrolled, then Final standings, scrolled
## Layout and behaviour evidence on desktop Linux (llvmpipe): not frame
## rate, pacing or device input.

var cap: Node
var scenario := ""
var _t := 0.0
var _step := 0
var _at := 0.0
var _phrase := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _snap(n: String) -> void:
	cap.call("snap", n)


func _next(delay: float) -> void:
	_step += 1
	_at = _t + delay


func _process(delta: float) -> void:
	_t += delta
	match scenario:
		"social_hub":
			_hub()
		"social_bot":
			_bot()
		"social_names":
			_names()
		"social_results":
			_results()
		"social_service_host":
			_service_host()
		"social_service_guest":
			_service_guest()


func _lobby() -> LobbyScreen:
	return App.screen as LobbyScreen if App.screen is LobbyScreen else null


func _hub() -> void:
	var s: NetSession = App.session
	var want := int(cap.get("want_players"))
	if s == null or _t < _at:
		return
	var l := _lobby()
	# (a shot is taken a frame later: every shot has a step of its own, and
	# the next action waits for it)
	match _step:
		0:
			if s.human_count() >= want and l != null:
				_next(5.0)
		1:
			_snap("hub_%dp_menu" % want)
			_next(1.0)
		2:
			if want > 1:
				l._set_walk(true)
			_next(0.5)
		3, 4, 5, 6, 7, 8:
			if want <= 1:
				_step = 10
				return
			# the host walks a short loop with its stick
			var dirs := [Vector2(0, 1), Vector2(1, 0.4), Vector2(0.3, -1), Vector2(-1, -0.2), Vector2(-0.4, 1), Vector2(0.6, 0.2)]
			if is_instance_valid(l) and l.hub:
				l.hub.stick = dirs[_step - 3] * 0.8
			_next(1.4)
		9:
			if is_instance_valid(l) and l.hub:
				l.hub.stick = Vector2.ZERO
			_snap("hub_%dp_walk" % want)
			_next(1.0)
		10:
			s.social.chat.send_quick(1, QuickChat.Channel.PARTY)
			_next(2.0)
		11:
			_snap("hub_%dp_bubbles" % want)
			_next(1.0)
		12:
			if is_instance_valid(l):
				l._open_chat()
			_next(2.0)
		13:
			_snap("hub_%dp_chat" % want)
			_next(1.0)
		14:
			for d in l.find_children("*", "ChatDrawer", true, false):
				(d as ChatDrawer).close()
			if want > 1 and is_instance_valid(l):
				l._set_walk(false)
			_next(2.5)
		15:
			var c: Variant = null
			for cell in l.cells:
				if cell.visible and cell.slot > 0 and s.roster[cell.slot] != null and not bool(s.roster[cell.slot]["is_bot"]):
					c = cell
					break
			if c == null:
				_step = 20
				return
			l._player_popover(c.slot, c)
			_next(1.5)
		16:
			_snap("hub_%dp_player_card" % want)
			_next(1.0)
		17:
			l.close_popover()
			for i in range(1, 8):
				if s.roster[i] != null and not bool(s.roster[i]["is_bot"]):
					l._report(s.roster[i])
					break
			_next(1.5)
		18:
			_snap("hub_%dp_report" % want)
			_next(1.0)
		19:
			_step = 20
		20:
			get_tree().quit()


func _bot() -> void:
	var s: NetSession = App.session
	if s == null or s.local_slot < 0 or s.phase != TC.Phase.LOBBY:
		return
	var mark: Vector3 = DormStage.MARKS[clampi(s.local_slot, 0, 7)]
	# a walk loop around the mark, a pause on the mark every so often
	var cyc := fmod(_t + float(s.local_slot) * 1.7, 14.0)
	if cyc < 10.0:
		var a := cyc / 10.0 * TAU
		var p := Vector2(mark.x + sin(a) * 1.1, mark.z - 0.6 + cos(a) * 0.9)
		var v := Vector2(cos(a), -sin(a))
		s.social.hub.set_local(HubSync.MODE_WALK, p, atan2(-v.x, -v.y), 1.3)
	else:
		s.social.hub.set_local(HubSync.MODE_MARK, Vector2(mark.x, mark.z), 0.0, 0.0)
	if _t > 6.0 + float(s.local_slot) and _t - _at > 9.0:
		_at = _t
		var ids := QuickChat.offered(QuickChat.Channel.PARTY)
		s.social.chat.send_quick(int(ids[(_phrase + s.local_slot) % ids.size()]), QuickChat.Channel.PARTY)
		_phrase += 1


func _sheet() -> NameSheet:
	var f := App.screen.find_children("*", "NameSheet", true, false)
	return f[0] if not f.is_empty() else null


func _type(text: String) -> void:
	var sheet := _sheet()
	sheet.field.text = text
	sheet._on_text(text)


func _names() -> void:
	if _t < _at:
		return
	match _step:
		0:
			if _t > 5.0 and App.screen is Screen:
				NameSheet.ask(App.screen as Screen, true)
				_next(1.5)
		1:
			_type("Tr1fecta Admin")
			_next(1.5)
		2:
			_snap("name_rejected_impersonation")
			_next(1.0)
		3:
			_type("add me on snap")
			_next(1.5)
		4:
			_snap("name_rejected_contact")
			_next(1.0)
		5:
			for b in _sheet().sugg_row.get_children():
				if not b.is_queued_for_deletion():
					(b as Button).pressed.emit()
					break
			_next(1.5)
		6:
			_snap("name_suggestion_tapped")
			_next(1.0)
		7:
			_type("Bob Builder")
			_next(1.5)
		8:
			_snap("name_harmless_lookalike_ok")
			_next(1.0)
		9:
			get_tree().quit()


func _results() -> void:
	if _t < _at:
		return
	match _step:
		0:
			if _t > 3.0:
				_show_series()
				_next(3.0)
		1:
			_snap("results_round")
			_next(1.0)
		2:
			_scroll(100000)
			_next(1.0)
		3:
			_snap("results_round_scrolled")
			_next(1.0)
		4:
			(App.screen as ResultsScreen)._on_primary()
			_next(2.0)
		5:
			_snap("results_final")
			_next(1.0)
		6:
			_scroll(100000)
			_next(1.0)
		7:
			_snap("results_final_scrolled")
			_next(1.0)
		8:
			get_tree().quit()


func _scroll(y: int) -> void:
	for sc in App.screen.find_children("*", "ScrollContainer", true, false):
		(sc as ScrollContainer).scroll_vertical = y


## The recorded round as the last round of a three-round friend series.
func _show_series() -> void:
	var d: Dictionary = str_to_var(FileAccess.get_file_as_string(String(cap.get("results_path"))))
	var res: Dictionary = (d["results"] as Dictionary).duplicate(true)
	var local := int(d["local_slot"])
	var me := Save.player_uid()
	var friends := {TC.Role.RUNNER: ["Snug Puffin 37", "Moonlit Koala"], TC.Role.PATROL: ["Cozy Walrus"]}
	var rows: Array = res.get("players", [])
	for r in rows:
		var row: Dictionary = r
		var role := int(row.get("role", TC.Role.RUNNER))
		if int(row.get("slot", -1)) == local:
			row["uid"] = me
			row["name"] = Save.player_name()
		elif bool(row.get("is_bot", false)) and not (friends[role] as Array).is_empty():
			row["name"] = (friends[role] as Array).pop_front()
			row["uid"] = "friend-" + String(row["name"]).replace(" ", "")
			row["is_bot"] = false
		elif String(row.get("uid", "")) == "":
			row["uid"] = "bot-%d" % int(row.get("slot", 0))
	var ps := PartySeries.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	ps.start({"watch": 2, "rounds": 3}, rng)
	for k in 2:
		var earlier: Array = []
		for r in rows:
			var e: Dictionary = (r as Dictionary).duplicate()
			if not bool(e.get("is_bot", false)):
				e["role"] = TC.Role.PATROL if (k + int(e.get("slot", 0))) % 3 == 0 else TC.Role.RUNNER
			earlier.append(e)
		ps.record_round({"match_id": "social-r%d" % (k + 1), "outcome": TC.Outcome.RUNNERS_WIN if k == 0 else TC.Outcome.PATROL_WIN,
			"round_time": 200.0, "players": earlier})
	res["match_id"] = "social-r3"
	ps.record_round(res)
	res["series"] = ps.to_dict()
	res["round_index"] = 3
	res["rounds_total"] = 3
	res["practice"] = false
	var s := NetSession.new()
	s.mode = NetSession.Mode.HOST
	s.local_slot = local
	s.series_view = res["series"]
	add_child(s)
	App._ensure_background()
	var rsc := ResultsScreen.new()
	rsc.results = res
	rsc.reward = d["reward"]
	rsc.session = s
	App._show(rsc)


# ---------------------------------------------------------------------------
# With the real service code, run locally (service/tools/dev_server.mjs:
# NOT a deployment).  Args: --service-url=http://127.0.0.1:P (Cloud reads
# it), --dev-service-dir=DIR (admission_public.pem from the dev server; the
# host writes room_code.txt there), --dev-player=T:id, --dev-name="Name",
# --dev-port=ENET_PORT (guest).
#   social_service_host   a LAN dev room registered as a service room:
#                         typed chat approved by the service and verified on
#                         every device, a refused message, a message report
#                         with its receipt, a block
#   social_service_guest  a headless member admitted by the service; types
#                         and sends Quick Chat
# ---------------------------------------------------------------------------
var _busy := false
var _ready_done := false
var _code := ""


func _arg(k: String, def: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % k):
			return a.substr(a.find("=") + 1)
	return def


func _identity() -> Dictionary:
	var h := HTTPRequest.new()
	add_child(h)
	h.request(Cloud.base_url + "/dev/identity?player=" + _arg("dev-player").uri_encode())
	var res: Array = await h.request_completed
	h.queue_free()
	var d: Variant = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	return d if d is Dictionary else {"ok": false, "message": "dev identity failed"}


## Sign in with the dev identity and take the approved name.
func _service_login() -> bool:
	var dir := _arg("dev-service-dir")
	Save.data["uid"] = _arg("dev-player")
	Save.data["name"] = _arg("dev-name", "Comfy Frog")
	Cloud.admission_key = Admission.load_public_key(FileAccess.get_file_as_string(dir.path_join("admission_public.pem")))
	Cloud.identity_override = _identity
	await Cloud.fetch_config()
	var s: Dictionary = await Cloud.sign_in()
	if not bool(s.get("ok", false)):
		printerr("SOCIAL dev sign-in failed: %s" % str(s))
		return false
	var n: Dictionary = await Cloud.set_display_name(_arg("dev-name", "Comfy Frog"))
	printerr("SOCIAL signed in as %s (%s)" % [Cloud.full_name(), str(n.get("ok", false))])
	return true


func _service_host() -> void:
	var s: NetSession = App.session
	if s == null or _busy or _t < _at:
		return
	var l := _lobby()
	var chat := s.social.chat
	match _step:
		0:
			_busy = true
			if not await _service_login():
				get_tree().quit()
				return
			var r: Dictionary = await Cloud.create_room(8)
			_code = String(r.get("room", {}).get("code", ""))
			printerr("SOCIAL room %s" % _code)
			s.room_code = _code
			s.local_uid = Save.player_uid()
			s.require_admission = true
			s.admission_key = Cloud.admission_key
			s.local_pid = Cloud.profile_id()
			s.roster[0]["uid"] = s.local_uid
			s.roster[0]["pid"] = s.local_pid
			s.roster[0]["name"] = String(Cloud.profile.get("display_name", "Host"))
			App._start_room_heartbeat(_code)
			await get_tree().create_timer(2.0).timeout
			var f := FileAccess.open(_arg("dev-service-dir").path_join("room_code.txt"), FileAccess.WRITE)
			f.store_string(_code)
			f.close()
			s._broadcast_lobby()
			_busy = false
			_next(1.0)
		1:
			if s.human_count() >= 2 and chat.history.any(func(m: Dictionary) -> bool: return int(m["kind"]) == SocialProto.Kind.TEXT):
				_next(3.0)
		2:
			_snap("service_lobby_typed_bubble")
			_next(1.0)
		3:
			l._open_chat()
			_next(2.0)
		4:
			var d: ChatDrawer = l.find_children("*", "ChatDrawer", true, false)[0]
			d.field.text = "Nice outfit! See you at the fountain"
			_busy = true
			await d._send_text()
			_busy = false
			_next(3.0)
		5:
			_snap("service_chat_typed")
			_next(1.0)
		6:
			var d: ChatDrawer = l.find_children("*", "ChatDrawer", true, false)[0]
			d.field.text = "add me on snap, my number is 555 123 4567"
			_busy = true
			await d._send_text()
			_busy = false
			_next(1.5)
		7:
			_snap("service_chat_refused")
			_next(1.0)
		8:
			var d: ChatDrawer = l.find_children("*", "ChatDrawer", true, false)[0]
			for m in chat.visible([QuickChat.Channel.PARTY]):
				if not bool(m["mine"]) and int(m["kind"]) == SocialProto.Kind.TEXT:
					d._open_actions = int(m["seq"])
					d._refresh()
					break
			_next(1.5)
		9:
			_snap("service_message_actions")
			_next(1.0)
		10:
			var d: ChatDrawer = l.find_children("*", "ChatDrawer", true, false)[0]
			for b in d.find_children("*", "Button", true, false):
				if (b as Button).text == "Report message":
					(b as Button).pressed.emit()
					break
			_next(1.5)
		11:
			_snap("service_report_reasons")
			_next(1.0)
		12:
			var rs: ReportSheet = l.find_children("*", "ReportSheet", true, false)[0]
			for b in rs.find_children("*", "Button", true, false):
				if (b as Button).text == "Harassment or bullying":
					(b as Button).pressed.emit()
					break
			_next(4.0)
		13:
			_snap("service_report_sent")
			var rs: ReportSheet = l.find_children("*", "ReportSheet", true, false)[0]
			printerr("SOCIAL report state=%s receipt=%s" % [rs.state, rs.receipt])
			_next(1.0)
		14:
			for rs in l.find_children("*", "ReportSheet", true, false):
				(rs as ReportSheet).close()
			for d in l.find_children("*", "ChatDrawer", true, false):
				(d as ChatDrawer).close()
			_next(1.0)
		15:
			for i in range(1, 8):
				if s.roster[i] != null and not bool(s.roster[i]["is_bot"]):
					var e: Dictionary = s.roster[i].duplicate()
					e["slot"] = i
					_busy = true
					var note: String = await SocialActions.block(s, e)
					printerr("SOCIAL block: %s" % note)
					UIKit.toast(l, note)
					_busy = false
					break
			_next(1.0)
		16:
			_snap("service_after_block")
			_next(2.0)
		17:
			get_tree().quit()


func _service_guest() -> void:
	if _busy or _t < _at:
		return
	match _step:
		0:
			var p := _arg("dev-service-dir").path_join("room_code.txt")
			if not FileAccess.file_exists(p):
				return
			_busy = true
			if not await _service_login():
				get_tree().quit()
				return
			_code = FileAccess.get_file_as_string(p).strip_edges()
			var r: Dictionary = await Cloud.join_room(_code)
			printerr("SOCIAL join %s: %s" % [_code, str(r.get("ok", false))])
			if not bool(r.get("ok", false)):
				printerr(str(r))
				get_tree().quit()
				return
			App.join_room_enet("127.0.0.1", int(_arg("dev-port", "7787")))
			App.session.admission = String(r["admission"])
			App.session.local_pid = Cloud.profile_id()
			App.party_code = _code
			_busy = false
			_next(1.0)
		1:
			var s: NetSession = App.session
			if s != null and s.local_slot >= 0:
				_next(3.0)
		2:
			_busy = true
			var r2: Dictionary = await App.session.social.chat.send_text("Ready when you are!", QuickChat.Channel.PARTY)
			printerr("SOCIAL guest typed: %s" % str(r2))
			_busy = false
			_next(6.0)
		3:
			App.session.social.chat.send_quick(5, QuickChat.Channel.PARTY)
			_next(60.0)
		4:
			pass
