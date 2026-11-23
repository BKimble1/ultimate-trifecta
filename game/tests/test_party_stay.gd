extends RefCounted
## (build 33) TestFlight feedback from two iPhones in a party, over the
## loopback network with real latency, jitter and loss (60-120 ms):
##   * a guest who leaves a round stays in the party: back in its lobby, a
##     bot plays their seat, the friends still playing are holograms there
##     ("In a round" on their cards) until the round ends, then everyone is
##     together and the guest plays the next round;
##   * the host leaving a round ends it for everyone (back to the lobby, the
##     round counts for nobody), nobody leaves the party;
##   * everyone readies up, the leader too, with a check beside each ready
##     name; the leader's Start waits for everyone;
##   * the party leader apart from the host: promotion, a guest leader's
##     Start / kick / settings checked by the host, non-leaders refused, and
##     leadership passing on when the leader leaves;
##   * the lobby "bunch of characters over top of each other" regression:
##     joins, leaves, quick rejoins, looks changing mid-join, a round and
##     back, spectators promoted - one character per player, none stacked;
##   * Leave party in the lobby header (where Copy code was) at the iPhone
##     SE, 6.9-inch and iPad sizes.
var t
var _saved_uid: Variant
var _saved_session: NetSession
var _stage: DormStage


func _rig(n_clients: int, lat: float = 90.0, jit: float = 30.0, loss: float = 0.02) -> NetRig:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(lat, jit, loss, n_clients)
	return rig


func _all_in(rig: NetRig) -> bool:
	for c in rig.clients:
		if c.local_slot < 0:
			return false
	return rig.host.human_count() == rig.clients.size() + 1


## A guest still in the party (its connection open, not ended).
func _live(rig: NetRig, c: NetSession) -> bool:
	return is_instance_valid(c) and c.transport != null and rig.hub.endpoints.has((c.transport as LoopbackTransport).id) \
		and not rig.ended_reason.has(c)


func _start_round(rig: NetRig, seed_v: int = 41) -> bool:
	for c in rig.clients:
		if _live(rig, c):
			c.set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.can_start(), 400)
	rig.host.host_start_match(seed_v)
	return await rig.wait_until(func() -> bool:
		if rig.host.sim == null or rig.host.sim.phase != TC.Phase.PLAYING:
			return false
		for c in rig.clients:
			if c.left_round or not _live(rig, c) or c.local_slot < 0:
				continue
			if rig.mc_of(c) == null or not rig.mc_of(c).prepared:
				return false
		return true, 2400)


## What App does when a guest picks Back to lobby in the pause menu.
func _guest_leaves_round(rig: NetRig, c: NetSession) -> void:
	t.check(c.leave_round(), "the guest leaves the round (the host keeps them in the party)")
	var mc := rig.mc_of(c)
	if mc != null and is_instance_valid(mc):
		mc.queue_free()
	rig.mcs.erase(c)


func _lobby_for(s: NetSession, from_home: bool = false) -> LobbyScreen:
	_saved_uid = Save.data["uid"]
	_saved_session = App.session
	_stage = DormStage.new()
	t.add_child(_stage)
	App.stage = _stage
	if from_home:
		# as in the app: home's stage already has our runner (App.sync_stage_local)
		_stage.sync_party([{"key": Save.player_uid(), "role": TC.Role.RUNNER, "cosmetic": Save.data["cosmetic"],
			"name": Save.player_name(), "is_bot": false, "local": true, "arrive": false}], false)
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


func _cell_of(l: LobbyScreen, slot: int) -> LobbyScreen.SlotCell:
	for c in l.cells:
		if c.visible and c.slot == slot:
			return c
	return null


## One character per present player on the stage, none sharing a mark.
func _one_each(tag: String, expect: int) -> void:
	var rep := _stage.views_report()
	t.eq(int(rep["views"]), expect, "%s: %d characters drawn (one per player)" % [tag, expect])
	var stacked: Array = []
	for m in rep["by_mark"]:
		if int(rep["by_mark"][m]) > 1:
			stacked.append("mark %s x%d" % [m, int(rep["by_mark"][m])])
	t.eq(stacked, [], "%s: nobody stacked on one mark" % tag)
	t.eq(_stage.chars.size(), expect, "%s: the stage tracks %d" % [tag, expect])


func _no_stacking(tag: String) -> void:
	var rep := _stage.views_report()
	var stacked: Array = []
	for m in rep["by_mark"]:
		if int(m) >= 0 and int(rep["by_mark"][m]) > 1:
			stacked.append("mark %s x%d" % [m, int(rep["by_mark"][m])])
	t.eq(stacked, [], "%s: nobody stacked on one mark, even mid-change" % tag)


# ---------------------------------------------------------------------------
func test_guest_leaves_round_stays_in_party_and_plays_the_next() -> void:
	var rig := _rig(2, 100.0, 20.0, 0.03)
	rig.host.settings["rounds"] = 1   # (one round: a series plays on by itself, test_series_flow)
	await rig.wait_until(func() -> bool: return _all_in(rig), 400)
	t.check(await _start_round(rig), "a party round is playing")
	var c0: NetSession = rig.clients[0]
	var c1: NetSession = rig.clients[1]
	var s0 := c0.local_slot
	t.check(c0.host_supports(Protocol.CAP_STAY), "the host offers staying in the party")
	var snaps := [0]
	c0.snapshot_received.connect(func(_s: Dictionary) -> void: snaps[0] += 1)
	_guest_leaves_round(rig, c0)
	var he: Dictionary = rig.host.roster[s0]
	await rig.wait_until(func() -> bool: return bool(he.get("away", false)), 200)
	t.check(bool(he["away"]) and bool(he["connected"]), "the host has them in the party, out of the round")
	t.eq(rig.host.human_count(), 3, "still three people in the party")
	var p := rig.host.sim.player(s0)
	t.check(p.is_bot and rig.host.sim.bots.has(s0), "a bot plays their runner")
	await rig.frames(30)
	var pos0 := p.pos()
	snaps[0] = 0
	await rig.frames(150)
	t.check(rig.host.sim.phase == TC.Phase.PLAYING, "the round plays on for the others")
	t.check(pos0.distance_to(p.pos()) > 0.5 or p.state != TC.PState.ACTIVE, "the bot moves their runner (%.1f m)" % pos0.distance_to(p.pos()))
	t.check(snaps[0] <= 2, "no round snapshots to the lobby (%d)" % snaps[0])
	t.check(rig.ended_reason.is_empty(), "nobody's party ended")
	t.check(c0.connected and not c0.left_round == false, "the guest is in the party, marked as out of the round")
	t.check(c0.host_phase == TC.Phase.PLAYING, "and knows the round is on")
	t.check(c0.member_in_round(0) and c0.member_in_round(c1.local_slot), "the host and the other guest are in the round (holograms)")
	t.check(not c0.member_in_round(s0), "not themselves")
	# the other guest's round is untouched
	t.check(rig.mc_of(c1) != null and rig.mc_of(c1)._last_snap_tick > 0, "the other guest still plays")
	# the round ends: everyone together in the lobby
	rig.host_mc().sim.end_tick = rig.host_mc().sim.tick + 2
	await rig.wait_until(func() -> bool: return rig.results.has(c1) and c0.host_phase == TC.Phase.RESULTS, 900)
	t.check(not c0.member_in_round(0), "round over: no holograms")
	var row: Dictionary = {}
	for r in rig.host.last_results.get("players", []):
		if int(r["slot"]) == s0:
			row = r
	t.check(not bool(row.get("present", true)), "the round's row has them away (no Round Win, no reward)")
	rig.host.host_return_to_lobby()
	await rig.wait_until(func() -> bool: return c0.host_phase == TC.Phase.LOBBY and c0.phase == TC.Phase.LOBBY, 300)
	t.eq(c0.host_phase, TC.Phase.LOBBY, "everyone is back in the party lobby")
	t.check(not bool(rig.host.roster[s0]["away"]), "the host has them back with everyone")
	# the next round includes them
	rig.started.erase(c0)
	rig.host.set_local_ready(true)
	t.check(await _start_round(rig, 43), "the next round starts with everyone")
	t.check(rig.started.has(c0) and rig.mc_of(c0) != null, "the guest who left plays it")
	var p2 := rig.host.sim.player(s0)
	t.check(p2 != null and not p2.is_bot, "as themselves again, not a bot")
	await rig.frames(30)
	t.check(rig.mc_of(c0)._last_snap_tick > 0, "and gets the round's snapshots")
	rig.teardown()


func test_hologram_while_the_others_play_and_gone_after() -> void:
	var rig := _rig(2, 70.0, 25.0, 0.02)
	rig.host.settings["rounds"] = 1   # (one round: a series plays on by itself, test_series_flow)
	await rig.wait_until(func() -> bool: return _all_in(rig), 400)
	t.check(await _start_round(rig), "a party round is playing")
	var c0: NetSession = rig.clients[0]
	var c1: NetSession = rig.clients[1]
	_guest_leaves_round(rig, c0)
	Save.data["uid"] = "uid-c0"
	var l := _lobby_for(c0)
	await rig.wait_until(func() -> bool: return _stage.chars.has("uid-host") and (_stage.chars["uid-host"] as CharacterView).hologram, 300)
	var hv: CharacterView = _stage.chars.get("uid-host")
	var gv: CharacterView = _stage.chars.get("uid-c1")
	var me: CharacterView = _stage.chars.get("uid-c0")
	t.check(hv != null and hv.hologram, "the host, still playing, is a hologram on their mark")
	t.check(gv != null and gv.hologram, "so is the other guest")
	t.check(me != null and not me.hologram, "we are ourselves")
	t.eq(_stage.chars.size(), 3, "three people on the stage (the round's bots stay in the round)")
	if hv != null:
		var mi: MeshInstance3D = hv.base_mesh
		t.check(mi.material_override is ShaderMaterial and (mi.material_override as ShaderMaterial).shader == CharacterView.HOLO_DEPTH_SHADER,
			"the hologram is a depth pass ...")
		t.check((mi.material_override as ShaderMaterial).next_pass is ShaderMaterial and ((mi.material_override as ShaderMaterial).next_pass as ShaderMaterial).shader == CharacterView.HOLO_SHADER,
			"... then its translucent colour pass")
		t.check((mi.material_override as ShaderMaterial).render_priority < ((mi.material_override as ShaderMaterial).next_pass as ShaderMaterial).render_priority,
			"every depth pass before any colour pass")
		t.eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "it casts no shadow")
		t.check(hv.holo_pad != null and hv.holo_pad.visible, "on a glowing disc")
	var hc := _cell_of(l, 0)
	t.check(hc != null and hc.round_chip.visible, "the host's card says In a round")
	t.check(hc != null and not hc.ready_mark.get_parent().visible, "with no ready check")
	t.eq(l.primary_btn.text, "Round in progress", "our button waits for the round")
	t.check(l.primary_btn.disabled, "and can't be pressed")
	_no_stacking("hologram lobby")
	# the round ends: solid again
	rig.host_mc().sim.end_tick = rig.host_mc().sim.tick + 2
	await rig.wait_until(func() -> bool: return rig.results.has(c1) and c0.host_phase == TC.Phase.RESULTS, 900)
	await rig.frames(4)
	t.check(not hv.hologram and not gv.hologram, "round over: everyone solid")
	t.check(hv.base_mesh.material_override == CharacterView._shared_material(false), "the character's own material is back")
	t.check(hv.holo_pad == null or not hv.holo_pad.visible, "no disc")
	t.check(hc != null and not hc.round_chip.visible, "no In a round chip")
	rig.host.host_return_to_lobby()
	await rig.wait_until(func() -> bool: return c0.host_phase == TC.Phase.LOBBY, 300)
	await rig.frames(70)
	_one_each("back together", 3)
	await _lobby_done(l)
	rig.teardown()


func test_host_ends_the_round_early_everyone_in_the_lobby() -> void:
	var rig := _rig(2, 110.0, 10.0, 0.02)
	await rig.wait_until(func() -> bool: return _all_in(rig), 400)
	t.check(await _start_round(rig), "a party round is playing")
	var series_round := rig.host.series.next_round()
	t.check(rig.host.host_abort_round(), "the host ends the round for everyone")
	t.eq(rig.host.phase, TC.Phase.LOBBY, "the host is back in the party lobby")
	for c in rig.clients:
		await rig.wait_until(func() -> bool: return rig.results.has(c) and c.phase == TC.Phase.LOBBY, 400)
		var r: Dictionary = rig.results.get(c, {})
		t.check(bool(r.get("aborted", false)) and int(r.get("outcome", -1)) == TC.Outcome.CANCELLED, "%s: told the round was ended (cancelled)" % c.name)
		t.eq(c.host_phase, TC.Phase.LOBBY, "%s: back in the party lobby" % c.name)
		t.check(c.connected, "%s: still in the party" % c.name)
	t.check(rig.ended_reason.is_empty(), "nobody left the party")
	t.eq(rig.host.human_count(), 3, "three in the party")
	t.eq(rig.host.series.next_round(), series_round, "the round doesn't count (the series is where it was)")
	t.eq(rig.host.series.rounds.size(), 0, "no result recorded")
	# a cancelled round pays and costs nothing
	var row := {"slot": 0, "uid": "uid-host", "role": TC.Role.RUNNER, "is_bot": false, "present": true}
	t.eq(int(Economy.round_coins(row, rig.host.last_results).get("coins", -1)), 0, "no reward for anyone")
	# the match's own end arriving afterwards changes nothing
	var before := rig.host.phase
	rig.host.host_match_finished(rig.host.last_results)
	t.eq(rig.host.phase, before, "a second end of the same round is ignored")
	# and the next round starts normally
	rig.host.set_local_ready(true)
	t.check(await _start_round(rig, 9), "the next round starts")
	rig.teardown()


func test_everyone_readies_with_checks_and_the_leader_starts() -> void:
	var rig := _rig(1, 80.0, 30.0, 0.02)
	await rig.wait_until(func() -> bool: return _all_in(rig), 400)
	var c0: NetSession = rig.clients[0]
	Save.data["uid"] = "uid-host"
	var l := _lobby_for(rig.host)
	await rig.frames(6)
	t.check(rig.host.is_leader(), "the host leads a new party")
	t.eq(l.primary_btn.text, "Ready", "the leader has a Ready button")
	t.check(not l.primary_btn.disabled, "usable before anyone else is ready")
	# the leader readies first (build 32: Start, disabled until the guest was ready)
	l._on_primary()
	await rig.frames(4)
	t.check(bool(rig.host.roster[0]["ready"]), "the leader is ready")
	t.eq(l.primary_btn.text, "Start", "then the button is Start")
	t.check(l.primary_btn.disabled, "waiting for the guest")
	t.check(l.unready_btn.visible, "with Not ready beside it")
	var hc := _cell_of(l, 0)
	var gc := _cell_of(l, c0.local_slot)
	t.check(hc.ready_mark.get_parent().visible, "a check beside the leader's name")
	t.check(not gc.ready_mark.get_parent().visible, "none beside the guest's")
	t.check(gc.sub_l.text.contains("Not ready"), "the guest's card says Not ready")
	t.check(hc.badge.visible and hc.badge.kind == "crown", "the leader's card has the crown")
	t.check(not rig.host.start_allowed(), "Start needs everyone ready")
	await rig.wait_until(func() -> bool: return c0.roster[0] != null and bool(c0.roster[0]["ready"]), 200)
	t.check(bool(c0.roster[0]["ready"]), "the guest sees the leader ready")
	c0.set_local_ready(true)
	await rig.wait_until(func() -> bool: return bool(rig.host.roster[c0.local_slot]["ready"]), 200)
	await rig.frames(2)
	t.check(gc.ready_mark.get_parent().visible, "now a check beside the guest's name")
	t.check(not l.primary_btn.disabled, "Start is ready to press")
	# Not ready undoes the leader's; Ready again
	l.unready_btn.pressed.emit()
	await rig.frames(2)
	t.check(not bool(rig.host.roster[0]["ready"]) and l.primary_btn.text == "Ready", "the leader can take it back")
	l._on_primary()
	await rig.frames(2)
	t.check(l.primary_btn.text == "Start" and not l.primary_btn.disabled, "ready again: Start")
	if App.stage:
		App.stage.stop_previews()
	l._on_primary()
	await rig.wait_until(func() -> bool: return rig.host.phase != TC.Phase.LOBBY, 60)
	t.check(rig.host.phase != TC.Phase.LOBBY, "the leader starts the round")
	await _lobby_done(l)
	rig.teardown()


func test_guest_leader_requests_are_checked_by_the_host() -> void:
	var rig := _rig(2, 90.0, 30.0, 0.02)
	await rig.wait_until(func() -> bool: return _all_in(rig), 400)
	var c0: NetSession = rig.clients[0]
	var c1: NetSession = rig.clients[1]
	t.check(rig.host.can_promote(c0.local_slot), "the host (leader) can promote a guest")
	t.check(not c1.can_promote(c0.local_slot), "a guest who doesn't lead can't")
	rig.host.promote(c0.local_slot)
	await rig.wait_until(func() -> bool: return c0.is_leader() and c1.leader_slot == c0.local_slot, 200)
	t.check(c0.is_leader(), "the promoted guest leads")
	t.eq(c1.leader_slot, c0.local_slot, "everyone sees who leads")
	t.check(not rig.host.is_leader(), "the host no longer leads (it keeps the simulation)")
	# a non-leader's requests are refused
	var refused := rig.host.leader_refusals
	c1._send_leader(Protocol.LeaderOp.START)
	c1._send_leader(Protocol.LeaderOp.KICK, c0.local_slot)
	c1._send_leader(Protocol.LeaderOp.PROMOTE, c1.local_slot)
	await rig.frames(30)
	t.eq(rig.host.leader_refusals, refused + 3, "the host refused all three from a non-leader")
	t.eq(rig.host.phase, TC.Phase.LOBBY, "nothing started")
	t.check(rig.host.roster[c0.local_slot] != null and c0.is_leader(), "nobody removed or promoted")
	# the leader's Start before everyone is ready: refused
	c0.set_local_ready(true)
	await rig.frames(20)
	c0.request_start()
	await rig.frames(30)
	t.eq(rig.host.phase, TC.Phase.LOBBY, "Start needs everyone ready (the host refused)")
	# settings from the leader go through the host
	t.check(c0.leader_set_settings(3, 1), "the leader changes the settings")
	await rig.wait_until(func() -> bool: return int(rig.host.settings["watch"]) == 3, 200)
	t.eq([int(rig.host.settings["watch"]), int(rig.host.settings["rounds"])], [3, 1], "the host applied them")
	await rig.wait_until(func() -> bool: return int(c1.settings["watch"]) == 3, 200)
	t.check(c1.settings_note.contains("leader"), "the others are told the leader changed them")
	t.check(not c1.leader_set_settings(1, 1), "a non-leader can't")
	# the leader can't remove the host's device
	c0.leader_kick(0)
	await rig.frames(30)
	t.check(rig.host.roster[0] != null and rig.ended_reason.is_empty(), "the host can't be removed (the party lives there)")
	# everyone ready: the guest leader's Start starts the round
	for s in [rig.host, c0, c1]:
		s.set_local_ready(true)
	await rig.wait_until(func() -> bool: return c0.start_allowed(), 200)
	t.check(c0.start_allowed(), "the leader sees everyone ready")
	c0.request_start()
	await rig.wait_until(func() -> bool: return rig.host.phase != TC.Phase.LOBBY and rig.started.has(c1) and rig.started.has(c0) and rig.started.has(rig.host), 300)
	t.check(rig.host.phase != TC.Phase.LOBBY, "the host started the leader's round")
	t.check(rig.started.has(c0) and rig.started.has(c1) and rig.started.has(rig.host), "for everyone")
	rig.host.host_abort_round()
	await rig.wait_until(func() -> bool: return c1.host_phase == TC.Phase.LOBBY and c0.host_phase == TC.Phase.LOBBY, 400)
	# the leader removes a member
	c0.leader_kick(c1.local_slot)
	await rig.wait_until(func() -> bool: return rig.ended_reason.has(c1), 200)
	t.eq(String(rig.ended_reason.get(c1, "")), "kicked", "the leader removed a member")
	t.eq(rig.host.human_count(), 2, "two left in the party")
	rig.teardown()


func test_leadership_passes_on_when_the_leader_leaves() -> void:
	var rig := _rig(3, 60.0, 20.0, 0.0)
	await rig.wait_until(func() -> bool: return _all_in(rig), 400)
	var by_slot := {}
	for c in rig.clients:
		by_slot[c.local_slot] = c
	# the guest in the highest slot leads; after them, party order wraps to
	# the host's slot 0, so make the guest in the lowest slot lead instead
	var slots: Array = by_slot.keys()
	slots.sort()
	var first: NetSession = by_slot[slots[0]]
	var second: NetSession = by_slot[slots[1]]
	var third: NetSession = by_slot[slots[2]]
	rig.host.promote(first.local_slot)
	await rig.wait_until(func() -> bool: return first.is_leader(), 200)
	first.leave()
	await rig.wait_until(func() -> bool: return rig.host.human_count() == 3, 200)
	t.eq(rig.host.leader_slot, second.local_slot, "the next member (party order) leads when the leader leaves the party")
	await rig.wait_until(func() -> bool: return second.is_leader() and third.leader_slot == second.local_slot, 200)
	t.check(second.is_leader(), "and knows it")
	t.eq(third.leader_slot, second.local_slot, "everyone sees it")
	# the leader drops out (a lost connection) in the lobby: the same
	rig.client_ts[rig.clients.find(second)].close()
	await rig.wait_until(func() -> bool: return rig.host.human_count() == 2, 300)
	t.eq(rig.host.leader_slot, third.local_slot, "the next member leads after a drop")
	# the last guest leads and leaves: order wraps to the host
	third.leave()
	await rig.wait_until(func() -> bool: return rig.host.human_count() == 1, 300)
	t.check(rig.host.is_leader(), "with nobody else, the host leads")
	# the network host leaving ends the party for everyone (no host migration)
	var late := rig.add_client("uid-late", "Late")
	await rig.wait_until(func() -> bool: return late.local_slot >= 0, 300)
	rig.host.leave()
	await rig.wait_until(func() -> bool: return rig.ended_reason.has(late), 300)
	t.eq(String(rig.ended_reason.get(late, "")), "host_ended", "the host leaving ends the party for everyone")
	rig.teardown()


## The lobby join glitch (build 32 TestFlight: "a bunch of characters over
## top of each other, like your character").  Root causes: the guest's lobby
## opened before its own slot was known, so the stage removed our runner
## (its leave wave kept playing on mark 0) and built a second one on the same
## mark when the slot arrived; a guest leaving and rejoining within the wave
## got a second character beside (or on) the one still waving.
func test_join_leave_rejoin_never_stacks_characters() -> void:
	var rig := _rig(1, 120.0, 30.0, 0.02)
	var c0: NetSession = rig.clients[0]
	# the guest's lobby, from the moment its session starts (before WELCOME)
	Save.data["uid"] = "uid-c0"
	var l := _lobby_for(c0, true)
	var mine: CharacterView = _stage.local_character()
	await rig.frames(2)
	_no_stacking("joining, before our slot")
	t.check(mine != null and _stage.local_character() == mine and not mine.leaving(), "our runner from home stays (no goodbye wave on our own mark)")
	t.eq(_stage.chars.size(), 1, "joining: our own runner stands on its mark")
	await rig.wait_until(func() -> bool: return c0.local_slot >= 0 and _stage.chars.size() == 2, 400)
	for i in 6:
		_no_stacking("joined, frame %d" % i)
		await rig.frames(5)
	t.check(_stage.local_character() == mine, "the same runner once our slot arrived")
	await rig.frames(70)
	_one_each("joined", 2)
	# others join, one leaves and rejoins at once, looks change mid-join
	var a := rig.add_client("uid-a", "Alpha")
	var b := rig.add_client("uid-b", "Bravo")
	await rig.wait_until(func() -> bool: return rig.host.human_count() == 4 and c0.human_count() == 4, 400)
	_no_stacking("two more joined")
	for k in 3:
		rig.client_ts[rig.clients.find(a)].close()
		await rig.wait_until(func() -> bool: return c0.human_count() == 3, 300)
		_no_stacking("a guest left (%d)" % k)
		a = rig.add_client("uid-a", "Alpha")
		var look := Cosmetics.bot_cosmetic(k * 5 + 1)
		await rig.frames(3)
		a.set_local_cosmetic(look)
		b.set_local_cosmetic(Cosmetics.bot_cosmetic(k * 7 + 2))
		await rig.wait_until(func() -> bool: return c0.human_count() == 4, 300)
		for i in 4:
			_no_stacking("rejoined at once (%d), frame %d" % [k, i])
			await rig.frames(4)
	await rig.frames(80)
	_one_each("after quick rejoins", 4)
	# a round, and back (the menu stage is freed and rebuilt in the app)
	t.check(await _start_round(rig), "a round")
	rig.host_mc().sim.end_tick = rig.host_mc().sim.tick + 2
	await rig.wait_until(func() -> bool: return rig.results.has(c0), 900)
	rig.host.host_return_to_lobby()
	await rig.wait_until(func() -> bool: return c0.phase == TC.Phase.LOBBY, 300)
	await _lobby_done(l)
	l = _lobby_for(c0)
	await rig.frames(80)
	_one_each("back from the round", 4)
	# a spectator joins mid-round and is promoted into the next round
	rig.host.set_local_ready(true)
	t.check(await _start_round(rig, 77), "another round")
	var sp := rig.add_client("uid-spec", "Specs")
	await rig.wait_until(func() -> bool: return rig.host.spectators.size() == 1, 300)
	rig.host_mc().sim.end_tick = rig.host_mc().sim.tick + 2
	await rig.wait_until(func() -> bool: return rig.results.has(c0), 900)
	rig.host.host_return_to_lobby()
	rig.host.set_local_ready(true)
	t.check(await _start_round(rig, 78), "the spectator's round")
	t.check(sp.local_slot >= 0, "the spectator has a seat")
	rig.host.host_abort_round()
	await rig.wait_until(func() -> bool: return c0.phase == TC.Phase.LOBBY and c0.human_count() == 5, 400)
	await rig.frames(80)
	_one_each("spectator promoted", 5)
	await _lobby_done(l)
	rig.teardown()


## A leaving character keeps its mark until it has gone, and the same player
## back in time is the same character (stage level).
func test_stage_revives_a_quick_rejoin_and_rekeys_its_own_runner() -> void:
	_stage = DormStage.new()
	t.add_child(_stage)
	_stage.set_mode("lobby", false)
	var me := {"key": "dev-id", "role": TC.Role.RUNNER, "cosmetic": Cosmetics.DEFAULT, "name": "Me", "is_bot": false, "local": true}
	var a := {"key": "a", "role": TC.Role.RUNNER, "cosmetic": Cosmetics.bot_cosmetic(1), "name": "A", "is_bot": false, "local": false}
	var b := {"key": "b", "role": TC.Role.RUNNER, "cosmetic": Cosmetics.bot_cosmetic(2), "name": "B", "is_bot": false, "local": false}
	_stage.sync_party([me, a])
	var av: CharacterView = _stage.chars["a"]
	var a_mark: int = _stage._mark_of["a"]
	_stage.sync_party([me])                 # a leaves (waving)
	_stage.sync_party([me, b])              # b arrives while a still waves
	t.check(_stage._mark_of["b"] != a_mark, "a newcomer doesn't take the spot of someone still waving goodbye")
	_stage.sync_party([me, b, a])           # a is back at once
	t.check(_stage.chars["a"] == av, "the same player back at once is the same character")
	t.eq(_stage._mark_of["a"], a_mark, "on their own mark")
	t.check(not av.leaving() and is_equal_approx(av.scale.x, 1.0), "no longer leaving")
	# our own runner, re-filed under a new id (Game Center) while waving
	_stage.sync_party([a, b])               # (our slot unknown for a moment)
	var mine: CharacterView = _stage.local_character()
	var me2 := me.duplicate()
	me2["key"] = "gc-id"
	_stage.sync_party([me2, a, b])
	await t.get_tree().process_frame
	_no_stacking("re-keyed local runner")
	t.check(_stage.chars["gc-id"] == mine or mine == null, "our runner came back as itself under the new id")
	await t.get_tree().create_timer(1.3).timeout
	_one_each("settled", 3)
	_stage.queue_free()


## Leave party sits where Copy code was, whole and clear of everything, at
## the iPhone SE (667x375 pt), 6.9-inch (956x440 pt) and iPad (1024x768 pt)
## sizes, with two and with eight people.
func test_leave_party_button_layout_at_three_sizes() -> void:
	var root: Window = t.get_tree().root
	var saved_size := root.size
	var saved_device := Controls.device
	Controls.device = "touch"
	_saved_uid = Save.data["uid"]
	_saved_session = App.session
	for d in [["iPhone SE 667x375", Vector2i(1334, 750)], ["6.9-inch 956x440", Vector2i(2868, 1320)], ["iPad 1024x768", Vector2i(2048, 1536)]]:
		root.size = d[1]
		for n in [2, 8]:
			var rig := _rig(n - 1, 0.0, 0.0, 0.0)
			await rig.wait_until(func() -> bool: return rig.host.human_count() == n, 400)
			Save.data["uid"] = "uid-host"
			App.session = rig.host
			App.show_lobby()
			await rig.frames(12)
			var l := App.screen as LobbyScreen
			var tag := "%s, %d people" % [d[0], n]
			t.check(l != null, "%s: lobby shown" % tag)
			if l == null:
				continue
			var lb := l.leave_btn
			var view := root.get_visible_rect()
			var safe := UIKit.safe_rect(root, view.size)
			var r := lb.get_global_rect()
			t.check(lb.is_visible_in_tree(), "%s: Leave party is shown" % tag)
			t.eq(lb.text, "Leave party", "%s: it says Leave party" % tag)
			t.check(safe.grow(0.5).encloses(r), "%s: inside the safe area (%s)" % [tag, str(r)])
			t.check(minf(r.size.x, r.size.y) >= UIKit.touch_min() - 0.5, "%s: a full touch target" % tag)
			t.check(UIKit.v7_button_text_fits(lb), "%s: its words whole" % tag)
			for other in [l.count_lbl, l.share_btn, l.top_bar, l.back_btn, l.season_pill, l.bottom_bar, l.primary_btn]:
				if other is Control and (other as Control).is_visible_in_tree():
					t.check(not r.intersects((other as Control).get_global_rect().grow(-0.5)), "%s: clear of %s" % [tag, (other as Control).name])
			for c in l.cells:
				if c.visible:
					t.check(not r.intersects(c.get_global_rect().grow(-0.5)), "%s: clear of the roster cards" % tag)
			t.check(not l.count_lbl.clip_text or UIKit.v7_text_width(l.count_lbl, l.count_lbl.text) <= l.count_lbl.size.x + 0.5, "%s: the party count stays whole" % tag)
			# it asks first
			lb.pressed.emit()
			await rig.frames(3)
			t.check(l.has_modal(), "%s: Leave party asks first" % tag)
			l._unhandled_input(_cancel_event())
			await rig.frames(3)
			t.check(App.session == rig.host, "%s: Stay keeps the party" % tag)
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


func _cancel_event() -> InputEvent:
	var e := InputEventAction.new()
	e.action = "ui_cancel"
	e.pressed = true
	return e


# ---------------------------------------------------------------------------
# (build 33 review) the party leader's edge cases
# ---------------------------------------------------------------------------
## A guest leader ends the series in the lobby: the host clears it (Play
## again), the settings unlock for everyone and the leader's next Start
## begins a new series.
func test_guest_leader_ends_the_series_in_the_lobby() -> void:
	var rig := _rig(2, 80.0, 30.0, 0.02)
	await rig.wait_until(func() -> bool: return _all_in(rig), 400)
	var c0: NetSession = rig.clients[0]
	var c1: NetSession = rig.clients[1]
	rig.host.promote(c0.local_slot)
	await rig.wait_until(func() -> bool: return c0.is_leader(), 200)
	for s in [rig.host, c0, c1]:
		s.set_local_ready(true)
	await rig.wait_until(func() -> bool: return c0.start_allowed(), 300)
	c0.request_start()
	await rig.wait_until(func() -> bool: return rig.host.phase != TC.Phase.LOBBY, 300)
	t.check(rig.host.series != null and rig.host.series.in_progress(), "a series is under way")
	rig.host.host_abort_round()   # (back in the lobby mid-series)
	await rig.wait_until(func() -> bool: return c0.host_phase == TC.Phase.LOBBY and c0.series_active(), 300)
	t.check(c0.series_active(), "the leader sees the series under way (settings locked)")
	c0.leader_end_series()
	await rig.wait_until(func() -> bool: return rig.host.series == null and not c0.series_active() and not c1.series_active(), 300)
	t.check(rig.host.series == null, "the host cleared the ended series (as Play again does)")
	t.check(not c0.series_active() and not c1.series_active(), "everyone's lobby knows: the settings unlock")
	t.check(bool(c1.series_view.get("finished", false)) and bool(c1.series_view.get("ended_early", false)), "the guests got the final standings")
	t.check(c0.leader_set_settings(1, 1), "the leader can change the settings again")
	await rig.wait_until(func() -> bool: return int(rig.host.settings["rounds"]) == 1, 300)
	t.eq(int(rig.host.settings["rounds"]), 1, "applied by the host")
	for s in [rig.host, c0, c1]:
		s.set_local_ready(true)
	await rig.wait_until(func() -> bool: return c0.start_allowed() and rig.host.start_allowed(), 300)
	t.check(rig.host.start_allowed(), "the host agrees the next round can start")
	rig.started.erase(c1)
	c0.request_start()
	await rig.wait_until(func() -> bool: return rig.host.phase != TC.Phase.LOBBY and rig.started.has(c1), 300)
	t.check(rig.host.phase != TC.Phase.LOBBY, "the leader's Start begins a new series")
	t.eq(int((rig.started.get(c1, {}) as Dictionary).get("series", {}).get("round", -1)), 1, "round 1 of the new series")
	rig.teardown()


## The host ends the round for everyone: a guest on an older build (no
## CAP_STAY) finishes its round from a last ENDED snapshot; one still loading
## when the round is ended is sent home instead of left on the loading screen.
func test_ending_the_round_reaches_older_guests() -> void:
	var rig := _rig(2, 90.0, 20.0, 0.02)
	await rig.wait_until(func() -> bool: return _all_in(rig), 400)
	var c0: NetSession = rig.clients[0]
	var c1: NetSession = rig.clients[1]
	var old := c1.local_slot
	rig.host.roster[old]["caps"] = 0   # as an older guest's HELLO leaves it
	t.check(await _start_round(rig), "a party round is playing")
	var phases: Array = []
	c1.snapshot_received.connect(func(sn: Dictionary) -> void: phases.append(int(sn.get("phase", -1))))
	var mc1 := rig.mc_of(c1)
	var done := [false]
	mc1.finished.connect(func(_r: Dictionary) -> void: done[0] = true)
	rig.host.host_abort_round()
	await rig.wait_until(func() -> bool: return phases.has(TC.Phase.ENDED), 300)
	t.check(phases.has(TC.Phase.ENDED), "the older guest got the ended round's snapshot")
	await rig.wait_until(func() -> bool: return done[0], 900)
	t.check(done[0], "so its round finishes (its results screen, then the lobby)")
	t.check(rig.ended_reason.is_empty(), "nobody was dropped")
	# ended while still loading: an older guest is sent home, a new one stays
	rig.host.set_local_ready(true)
	for c in [c0, c1]:
		c.set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.can_start(), 300)
	rig.host.host_start_match(12)
	t.check(not rig.host._loaded.has(old), "(the older guest's round hasn't loaded yet)")
	rig.host.host_abort_round()
	await rig.wait_until(func() -> bool: return rig.ended_reason.has(c1), 300)
	t.eq(String(rig.ended_reason.get(c1, "")), "host_ended", "the older guest is sent home, not left loading")
	t.eq(rig.host.stat_sent_home, 1, "only that one")
	t.check(not rig.ended_reason.has(c0), "the new guest stays in the party")
	await rig.wait_until(func() -> bool: return c0.host_phase == TC.Phase.LOBBY, 300)
	t.eq(c0.host_phase, TC.Phase.LOBBY, "and is back in its lobby")
	rig.teardown()


## A leader who left the round can't remove anyone while it runs; a removal
## mid-round (the host's) hands the seat to a bot instead of freezing it.
func test_no_removals_mid_round_and_a_removed_seat_plays_on() -> void:
	var rig := _rig(2, 70.0, 20.0, 0.02)
	await rig.wait_until(func() -> bool: return _all_in(rig), 400)
	var c0: NetSession = rig.clients[0]
	var c1: NetSession = rig.clients[1]
	rig.host.promote(c0.local_slot)
	await rig.wait_until(func() -> bool: return c0.is_leader(), 200)
	for s in [rig.host, c0, c1]:
		s.set_local_ready(true)
	await rig.wait_until(func() -> bool: return c0.start_allowed(), 300)
	c0.request_start()
	await rig.wait_until(func() -> bool: return rig.host.sim != null and rig.host.sim.phase == TC.Phase.PLAYING, 2400)
	_guest_leaves_round(rig, c0)
	await rig.wait_until(func() -> bool: return bool(rig.host.roster[c0.local_slot].get("away", false)), 200)
	var refused := rig.host.leader_refusals
	c0.leader_kick(c1.local_slot)
	await rig.frames(30)
	t.eq(rig.host.leader_refusals, refused + 1, "the leader's Remove is refused while the round runs")
	t.check(rig.host.roster[c1.local_slot] != null and not rig.ended_reason.has(c1), "the member is still there")
	var s1 := c1.local_slot
	rig.host.kick(s1)
	var p := rig.host.sim.player(s1)
	t.check(p.is_bot and rig.host.sim.bots.has(s1), "a seat removed mid-round is a bot's to the end")
	var pos0 := p.pos()
	await rig.frames(150)
	t.check(pos0.distance_to(p.pos()) > 0.5 or p.state != TC.PState.ACTIVE, "and it plays on (%.1f m)" % pos0.distance_to(p.pos()))
	rig.teardown()


## A host that doesn't lead readies up on its results screen like anyone,
## so the guest leader can start the next round from the lobby while the
## host is still there.
func test_a_host_that_does_not_lead_readies_on_its_results() -> void:
	var rig := _rig(1, 80.0, 20.0, 0.02)
	await rig.wait_until(func() -> bool: return _all_in(rig), 400)
	var c0: NetSession = rig.clients[0]
	rig.host.promote(c0.local_slot)
	await rig.wait_until(func() -> bool: return c0.is_leader(), 200)
	rig.host.set_local_ready(true)
	c0.set_local_ready(true)
	await rig.wait_until(func() -> bool: return c0.start_allowed(), 300)
	c0.request_start()
	await rig.wait_until(func() -> bool: return rig.host.sim != null and rig.host.sim.phase == TC.Phase.PLAYING, 2400)
	rig.host_mc().sim.end_tick = rig.host_mc().sim.tick + 2
	await rig.wait_until(func() -> bool: return rig.results.has(c0) and rig.host.phase == TC.Phase.RESULTS, 900)
	var r := ResultsScreen.new()
	r.results = rig.host.last_results
	r.reward = {}
	r.session = rig.host
	t.add_child(r)
	await rig.frames(4)
	# (build 34) between the rounds of a series nobody readies: the host's
	# results (it doesn't lead) offer only Leave match, and the next round
	# starts by itself
	t.check(not r._primary.visible and r.leave_btn.text == "Leave match", "the host's results: only Leave match (no Ready)")
	rig.host.next_round_wait_s = 9.0
	await rig.wait_until(func() -> bool: return rig.host.phase >= TC.Phase.LOADING and rig.host.phase <= TC.Phase.PLAYING, 900)
	t.check(rig.host.phase >= TC.Phase.LOADING and rig.host.phase <= TC.Phase.PLAYING, "the next round started by itself (no Ready, no Start)")
	r.queue_free()
	rig.teardown()


## A leader who drops out mid-round hands the crown on when the round ends;
## a guest leader is offered Promote only for members whose build can lead.
func test_crown_passes_after_a_drop_and_promote_needs_a_build_that_can_lead() -> void:
	var rig := _rig(2, 70.0, 20.0, 0.0)
	await rig.wait_until(func() -> bool: return _all_in(rig), 400)
	var c0: NetSession = rig.clients[0]
	var c1: NetSession = rig.clients[1]
	rig.host.promote(c0.local_slot)
	await rig.wait_until(func() -> bool: return c0.is_leader(), 200)
	await rig.frames(10)
	t.check(c0.can_promote(c1.local_slot), "a guest leader can promote a member whose build can lead")
	t.check(c0.can_promote(0), "and the host")
	rig.host.roster[c1.local_slot]["caps"] = 0   # an older build
	rig.host._broadcast_lobby()
	await rig.wait_until(func() -> bool: return not c0.can_promote(c1.local_slot), 200)
	t.check(not c0.can_promote(c1.local_slot), "not a member on an older build (the host would refuse)")
	rig.host.roster[c1.local_slot]["caps"] = Protocol.CAPS
	t.check(await _start_round(rig), "a round")
	var lead := c0.local_slot
	rig.client_ts[0].close()
	await rig.wait_until(func() -> bool: return not bool(rig.host.roster[lead]["connected"]), 300)
	rig.host_mc().sim.end_tick = rig.host_mc().sim.tick + 2
	await rig.wait_until(func() -> bool: return rig.host.phase == TC.Phase.RESULTS, 900)
	t.check(rig.host.leader_slot != lead, "the crown passed on when the round ended (now %d)" % rig.host.leader_slot)
	await rig.wait_until(func() -> bool: return c1.leader_slot == rig.host.leader_slot, 300)
	t.eq(c1.leader_slot, rig.host.leader_slot, "and everyone sees it")
	rig.teardown()
