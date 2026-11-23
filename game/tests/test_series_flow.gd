extends RefCounted
## (build 34) A series plays on like a kart racer's cup (owner feedback on
## 2.2 (33)): between rounds nobody goes back to the lobby or readies up;
## the results stay on screen with the standings, the host's countdown is
## the same on every device and the next round starts by itself.  Leave
## match: a guest sits the rest of the match out in the party lobby, the
## host or the leader ends it for everyone.  After the last round: final
## standings, then the lobby, with the party's people only (no bots).  Older
## guests follow along (START moves them into the round as before).
## Loopback network with latency, jitter and loss.
var t
var _saved_uid: Variant
var _saved_session: NetSession
var _stage: DormStage


func _rig(n_clients: int, wait_s: float = 3.0, lat: float = 90.0, jit: float = 30.0, loss: float = 0.02) -> NetRig:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(lat, jit, loss, n_clients)
	rig.host.next_round_wait_s = wait_s
	return rig


func _all_in(rig: NetRig) -> bool:
	for c in rig.clients:
		if c.local_slot < 0:
			return false
	return rig.host.human_count() == rig.clients.size() + 1


func _round_of(rig: NetRig, s: NetSession) -> int:
	var info: Dictionary = rig.started.get(s, {})
	return int((info.get("series", {}) as Dictionary).get("round", 0))


## Starts round 1 of a 3-round series (everyone ready once, as in the lobby).
func _start_series(rig: NetRig) -> bool:
	for c in rig.clients:
		c.set_local_ready(true)
	rig.host.set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.start_allowed(), 400)
	rig.host.host_start_match(31)
	return await _playing(rig)


func _playing(rig: NetRig) -> bool:
	return await rig.wait_until(func() -> bool:
		if rig.host.sim == null or rig.host.sim.phase != TC.Phase.PLAYING:
			return false
		for c in rig.clients:
			if c.sitting_out() or rig.ended_reason.has(c):
				continue
			if rig.mc_of(c) == null or not rig.mc_of(c).prepared:
				return false
		return true, 2400)


func _end_round(rig: NetRig) -> void:
	var sim := rig.host_mc().sim
	sim.end_tick = sim.tick + 2
	await rig.wait_until(func() -> bool: return rig.host.phase == TC.Phase.RESULTS, 900)


func _lobby_for(s: NetSession, uid: String) -> LobbyScreen:
	_saved_uid = Save.data["uid"]
	_saved_session = App.session
	Save.data["uid"] = uid
	_stage = DormStage.new()
	t.add_child(_stage)
	App.stage = _stage
	_stage.set_mode("lobby", false)
	var l := LobbyScreen.new()
	l.session = s
	t.add_child(l)
	return l


func _lobby_done(l: LobbyScreen) -> void:
	if is_instance_valid(l):
		l.queue_free()
	if is_instance_valid(_stage):
		_stage.queue_free()
	App.stage = null
	App.session = _saved_session
	Save.data["uid"] = _saved_uid
	await t.get_tree().process_frame


func _results_for(rig: NetRig, s: NetSession) -> ResultsScreen:
	var r := ResultsScreen.new()
	r.results = rig.results.get(s, {})
	r.reward = {}
	r.session = s
	t.add_child(r)
	return r


# ---------------------------------------------------------------------------
func test_a_three_round_series_runs_without_the_lobby() -> void:
	var rig := _rig(2, 6.0)
	await rig.wait_until(func() -> bool: return _all_in(rig), 400)
	var c0: NetSession = rig.clients[0]
	var c1: NetSession = rig.clients[1]
	t.check(c0.series_flow() and c1.series_flow(), "the host offers the series flow")
	t.check(await _start_series(rig), "round 1 is playing")
	# nobody's screen sees the lobby between rounds: watch every LOBBY
	var lobby_seen := [0]
	for c in [c0, c1]:
		c.lobby_changed.connect(func() -> void:
			if c.host_phase == TC.Phase.LOBBY:
				lobby_seen[0] += 1)
	for rd in [1, 2, 3]:
		await _end_round(rig)
		await rig.wait_until(func() -> bool: return rig.results.has(c0) and int(rig.results[c0].get("round_index", 0)) == rd \
			and rig.results.has(c1) and int(rig.results[c1].get("round_index", 0)) == rd, 900)
		if rd == 3:
			break
		# the countdown: the host's, the same on every device (within latency)
		t.check(rig.host.next_round_in() > 0.0, "round %d: the host counts down to round %d" % [rd, rd + 1])
		await rig.frames(20)
		var hl := rig.host.next_round_in()
		for c in [c0, c1]:
			var d := absf(c.next_round_in() - hl)
			t.check(c.next_round_in() > 0.0 and d < 0.3, "round %d: %s counts down with the host (%.2f vs %.2f s)" % [rd, c.name, c.next_round_in(), hl])
		if rd == 1:
			# the results screen between rounds: standings, countdown, Leave match only
			var r := _results_for(rig, c0)
			await rig.frames(4)
			t.check(r.between_rounds(), "the guest's results know a round follows")
			t.check(not r._primary.visible, "no Ready, Next or Back to lobby")
			t.eq(r.leave_btn.text, "Leave match", "only Leave match")
			t.check(r.leave_btn.visible and not (r.chat_btn != null and r.chat_btn.visible), "and nothing else")
			t.check(r._v.find_child("Standings", true, false) != null, "the series standings are on it")
			await rig.wait_until(func() -> bool: return c0.next_round_in() >= 0.0 and c0.next_round_in() < 4.5, 600)
			await rig.frames(3)
			t.check(r.countdown.visible, "the 5-second countdown shows")
			t.eq(int(ceil(r.countdown.left)), int(ceil(c0.next_round_in())), "with the seconds left")
			r.queue_free()
		# nobody readies: the next round starts by itself, for everyone
		await rig.wait_until(func() -> bool: return _round_of(rig, c0) == rd + 1 and _round_of(rig, c1) == rd + 1, 900)
		t.eq([_round_of(rig, c0), _round_of(rig, c1)], [rd + 1, rd + 1], "round %d started by itself for both guests" % (rd + 1))
		t.check(not bool(rig.host.roster[c0.local_slot]["ready"]), "(nobody tapped Ready)")
		t.check(await _playing(rig), "round %d is playing" % (rd + 1))
	t.eq(lobby_seen[0], 0, "no device saw the lobby between rounds")
	# after the last round: no countdown, the series is over
	t.eq(rig.host.next_round_in(), -1.0, "after the last round no next round is scheduled")
	t.eq(c0.next_round_in(), -1.0, "nor on the guests")
	await rig.frames(300)
	t.eq(rig.host.phase, TC.Phase.RESULTS, "nothing starts by itself after the last round")
	t.check(bool(rig.host.series_view.get("finished", false)), "the series is over")
	var played := 0
	for uid in rig.host.series_view["standings"]:
		played += int(rig.host.series_view["standings"][uid]["played"])
	t.eq(played, 9, "three people played three rounds")
	# the final standings, then Back to lobby
	var rf := _results_for(rig, c0)
	await rig.frames(4)
	t.eq(rf._primary.text, "Final standings", "the last round leads to the final standings")
	rf._on_primary()
	await rig.frames(3)
	t.eq(rf.page, "final", "the podium page")
	t.eq(rf._primary.text, "Back to lobby", "one clear Back to lobby")
	t.check(not rf.leave_btn.visible, "and nothing else")
	rf.queue_free()
	rig.host.host_return_to_lobby()   # (the host's Back to lobby)
	await rig.wait_until(func() -> bool: return c0.host_phase == TC.Phase.LOBBY, 300)
	# the lobby: the people only, never the bots that filled the rounds
	var l := _lobby_for(c0, "uid-c0")
	await rig.frames(8)
	var shown := 0
	var bots := 0
	for c in l.cells:
		if c.visible and c.slot >= 0:
			shown += 1
			if bool(c0.roster[c.slot]["is_bot"]):
				bots += 1
	t.eq(shown, 3, "three people on the roster")
	t.eq(bots, 0, "no bots on the roster")
	t.eq(_stage.chars.size(), 3, "three characters on the stage")
	t.check(not l.series_row.visible and not l.standings_btn.visible, "no series line or standings in the lobby")
	t.check(not c0.series_active(), "the series is over for the guests too")
	await _lobby_done(l)
	rig.teardown()


func test_a_guest_who_leaves_the_match_sits_it_out() -> void:
	var rig := _rig(2, 3.0, 70.0, 20.0, 0.02)
	await rig.wait_until(func() -> bool: return _all_in(rig), 400)
	var c0: NetSession = rig.clients[0]
	var c1: NetSession = rig.clients[1]
	t.check(await _start_series(rig), "round 1 is playing")
	await _end_round(rig)
	await rig.wait_until(func() -> bool: return rig.results.has(c0) and c0.next_round_in() > 0.0, 300)
	# Leave match during the countdown
	t.check(c0.leave_round(), "the guest leaves the match between rounds")
	await rig.wait_until(func() -> bool: return bool(rig.host.roster[c0.local_slot].get("away", false)), 200)
	t.check(bool(rig.host.roster[c0.local_slot]["connected"]), "still in the party")
	await rig.wait_until(func() -> bool: return _round_of(rig, c1) == 2, 600)
	t.eq(_round_of(rig, c1), 2, "the countdown went on: round 2 started")
	await rig.frames(30)
	t.eq(_round_of(rig, c0), 1, "without the guest who left (no round 2 for them)")
	t.check(c0.sitting_out() and c0.left_round, "they sit the rest of the match out")
	t.check(c0.member_in_round(0) and c0.member_in_round(c1.local_slot), "the others are in the match (holograms)")
	t.check(await _playing(rig), "round 2 is playing")
	var p := rig.host.sim.player(c0.local_slot)
	t.check(p.is_bot, "a bot plays their seat")
	await _end_round(rig)
	await rig.wait_until(func() -> bool: return rig.host.next_round_in() < 0.0 and _round_of(rig, c1) == 3, 600)
	t.eq(_round_of(rig, c0), 1, "they sit round 3 out too")
	t.check(c0.member_in_round(0), "still holograms between rounds and in round 3")
	t.check(await _playing(rig), "round 3 is playing")
	await _end_round(rig)
	await rig.wait_until(func() -> bool: return not bool(rig.host.roster[c0.local_slot].get("away", false)) and not c0.sitting_out(), 300)
	t.check(not c0.sitting_out(), "the match is over: back with everyone")
	t.check(not c0.member_in_round(0), "no holograms")
	rig.host.host_return_to_lobby()
	rig.host.set_local_ready(true)
	for c in [c0, c1]:
		c.set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.start_allowed(), 300)
	var old_mid := String(rig.started[c0]["match_id"])
	rig.host.host_start_match(77)
	await rig.wait_until(func() -> bool: return String(rig.started[c0]["match_id"]) != old_mid, 300)
	t.check(String(rig.started[c0]["match_id"]) != old_mid and rig.mc_of(c0) != null, "the next match includes them")
	rig.teardown()


func test_the_host_leaving_ends_the_match_for_everyone() -> void:
	var rig := _rig(2, 3.0, 100.0, 20.0, 0.02)
	await rig.wait_until(func() -> bool: return _all_in(rig), 400)
	var c0: NetSession = rig.clients[0]
	var c1: NetSession = rig.clients[1]
	t.check(await _start_series(rig), "round 1 is playing")
	await _end_round(rig)
	await rig.wait_until(func() -> bool: return c0.next_round_in() > 0.0 and c1.next_round_in() > 0.0, 300)
	# the host's Leave match in the countdown (App.leave_series_match)
	rig.host.host_end_series()
	rig.host.host_return_to_lobby()
	await rig.wait_until(func() -> bool: return c0.host_phase == TC.Phase.LOBBY and c1.host_phase == TC.Phase.LOBBY, 300)
	for c in [c0, c1]:
		t.eq(c.next_round_in(), -1.0, "%s: no next round" % c.name)
		t.check(bool(c.series_view.get("ended_early", false)), "%s: the match counts as ended early" % c.name)
		t.check(not c.series_active(), "%s: the series is over" % c.name)
	await rig.frames(300)
	t.eq(rig.host.phase, TC.Phase.LOBBY, "nothing starts: everyone is in the party lobby")
	t.check(rig.ended_reason.is_empty(), "nobody left the party")
	# mid-round: the host's End match ends the round and the match
	rig.host.set_local_ready(true)
	for c in [c0, c1]:
		c.set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.start_allowed(), 300)
	rig.host.host_start_match(8)
	t.check(await _playing(rig), "a new match is playing")
	rig.host.host_end_series()
	rig.host.host_abort_round()
	await rig.wait_until(func() -> bool: return c0.host_phase == TC.Phase.LOBBY and c1.host_phase == TC.Phase.LOBBY, 300)
	t.check(bool(rig.results[c0].get("aborted", false)), "the guests are told the round was ended")
	t.check(rig.host.series == null and not c0.series_active(), "and the match is over")
	await rig.frames(300)
	t.eq(rig.host.phase, TC.Phase.LOBBY, "no next round")
	# a guest leader ends the match between rounds
	rig.host.promote(c0.local_slot)
	await rig.wait_until(func() -> bool: return c0.is_leader(), 200)
	for s in [rig.host, c0, c1]:
		s.set_local_ready(true)
	await rig.wait_until(func() -> bool: return c0.start_allowed(), 300)
	c0.request_start()
	t.check(await _playing(rig), "the leader's match is playing")
	await _end_round(rig)
	await rig.wait_until(func() -> bool: return c0.next_round_in() > 0.0, 300)
	c0.leader_end_series()
	await rig.wait_until(func() -> bool: return rig.host.phase == TC.Phase.LOBBY and c1.host_phase == TC.Phase.LOBBY, 300)
	t.eq(rig.host.phase, TC.Phase.LOBBY, "the leader's Leave match ends it for everyone")
	await rig.frames(240)
	t.eq(rig.host.phase, TC.Phase.LOBBY, "and no next round starts")
	rig.teardown()


## Older guests (builds 20-32, and 33 without the series flow) never ready
## up on their results: START moves them into each round as it did when a
## host started one.  A build 33 host (no CAP_SERIES) keeps the Ready flow
## on a new guest's results.
func test_older_guests_follow_the_series() -> void:
	var rig := _rig(2, 3.0, 80.0, 20.0, 0.02)
	var c0: NetSession = rig.clients[0]
	var c1: NetSession = rig.clients[1]
	c1.caps_mask = 0                                           # builds 20-32
	c0.caps_mask = Protocol.CAP_STAY | Protocol.CAP_LEADER     # build 33
	await rig.wait_until(func() -> bool: return _all_in(rig), 400)
	t.eq(int(rig.host.roster[c1.local_slot].get("caps", -1)), 0, "the host knows the older build can't lead")
	t.check(not c0.series_flow() and not c1.series_flow(), "the older guests don't know the series flow")
	t.check(await _start_series(rig), "round 1 is playing")
	for rd in [1, 2]:
		await _end_round(rig)
		await rig.wait_until(func() -> bool: return rig.results.has(c1) and int(rig.results[c1].get("round_index", 0)) == rd, 900)
		t.eq(c1.next_round_in(), -1.0, "round %d: no countdown on the oldest guest" % rd)
		if rd == 1:
			var r := _results_for(rig, c0)
			await rig.frames(4)
			t.check(r._primary.visible and r._primary.text.begins_with("Ready for round"), "a build 33 guest's results keep Ready (%s)" % r._primary.text)
			r.queue_free()
		# nobody readies: START still arrives and moves them into the round
		await rig.wait_until(func() -> bool: return _round_of(rig, c1) == rd + 1 and _round_of(rig, c0) == rd + 1, 900)
		t.eq([_round_of(rig, c0), _round_of(rig, c1)], [rd + 1, rd + 1], "round %d: START moved both older guests into the round" % (rd + 1))
		t.check(rig.mc_of(c1) != null, "the oldest guest loads it")
		t.check(await _playing(rig), "and plays it")
	rig.teardown()


## The lobby is clean every time you come back from a match: the party's
## people only (the match's bots stay in the match), no series line or
## standings, and Start (or Ready), Emote, Walk and Chat whole on screen at
## the iPhone SE, 6.9-inch and iPad sizes with 2, 4 and 8 people.
func test_the_lobby_after_a_match_is_clean_at_every_size() -> void:
	var root: Window = t.get_tree().root
	var saved_size := root.size
	var saved_device := Controls.device
	Controls.device = "touch"
	_saved_uid = Save.data["uid"]
	_saved_session = App.session
	for d in [["iPhone SE 667x375", Vector2i(1334, 750)], ["6.9-inch 956x440", Vector2i(2868, 1320)], ["iPad 1024x768", Vector2i(2048, 1536)]]:
		root.size = d[1]
		for n in [2, 4, 8]:
			var rig := _rig(n - 1, 3.0, 40.0, 10.0, 0.0)
			await rig.wait_until(func() -> bool: return _all_in(rig), 400)
			# a match with bots in the empty seats, ended: everyone in the lobby
			for s in [rig.host] + rig.clients:
				for cn in s.match_starting.get_connections():
					s.match_starting.disconnect(cn["callable"])
			rig.host.host_start_match(5)
			var guest: NetSession = rig.clients[0]
			var nbots := func() -> int: return guest.roster.filter(func(e: Variant) -> bool: return e != null and bool(e["is_bot"])).size()
			await rig.wait_until(func() -> bool: return guest.host_phase == TC.Phase.LOADING and int(nbots.call()) == 8 - n, 300)
			t.eq(int(nbots.call()), 8 - n, "(%d bots filled the match)" % (8 - n))
			rig.host.host_end_series()
			rig.host.host_abort_round()
			await rig.wait_until(func() -> bool: return guest.host_phase == TC.Phase.LOBBY, 300)
			Save.data["uid"] = "uid-c0"
			App.session = guest
			App.show_lobby()
			await rig.frames(12)
			var l := App.screen as LobbyScreen
			var tag := "%s, %d people" % [d[0], n]
			if not t.check(l != null, "%s: lobby shown" % tag):
				continue
			var people := 0
			var bots := 0
			for c in l.cells:
				if c.visible and c.slot >= 0:
					people += 1
					if guest.roster[c.slot] != null and bool(guest.roster[c.slot]["is_bot"]):
						bots += 1
			t.eq([people, bots], [n, 0], "%s: the people only on the roster, no bots" % tag)
			t.eq(App.stage.chars.size(), n, "%s: and on the stage" % tag)
			t.check(not l.series_row.visible and not l.standings_btn.visible, "%s: no series line or standings" % tag)
			var view := root.get_visible_rect()
			var safe := UIKit.safe_rect(root, view.size)
			var bottom: Array = [l.primary_btn, l.walk_btn, l.chat_btn]
			for c in l.bottom_bar.get_children():
				if c is Button and UIKit.face_of(c) != null and String(UIKit.face_of(c).icon) == "smile":
					bottom.append(c)
			for b in bottom:
				var bb := b as Control
				if bb.visible:
					t.check(safe.grow(0.5).encloses(bb.get_global_rect()), "%s: '%s' whole on screen (%s)" % [tag, bb.name, str(bb.get_global_rect())])
			t.check(not l.roster_col.get_global_rect().intersects(l.bottom_bar.get_global_rect().grow(-0.5)), "%s: the roster clears the bottom row" % tag)
			if App.screen and is_instance_valid(App.screen):
				App.screen.queue_free()
			App.screen = null
			App._clear_background()
			App.session = null
			rig.teardown()
			await t.get_tree().process_frame
			await t.get_tree().process_frame
	root.size = saved_size
	Controls.device = saved_device
	App.session = _saved_session
	Save.data["uid"] = _saved_uid
