extends RefCounted
## Network behaviour over the in-process loopback rig (simulated latency/loss).
var t
const R := TC.Role.RUNNER
const P := TC.Role.PATROL


func _rig(lat: float, jit: float, loss: float, n: int, prefs: Array = []) -> NetRig:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(lat, jit, loss, n, prefs)
	return rig


func test_protocol_snapshot_size_and_roundtrip() -> void:
	var h := SimHarness.new(t)
	h.make([R, R, R, R, R, R, P, P], [0, 1, 2])
	await h.to_playing()
	await h.step(5)
	var all: Array = h.sim.players.duplicate()
	var data := Protocol.encode_snapshot(h.sim, h.sim.player(6), all, 1234, true)
	t.check(data.size() < 900, "8-player snapshot fits one unreliable packet (%d bytes)" % data.size())
	var b := Protocol.reader(data)
	b.get_u8()
	var s := Protocol.decode_snapshot(b)
	t.eq(int(s["tick"]), h.sim.tick, "tick")
	t.eq(int(s["ack"]), 1234, "ack")
	t.eq((s["players"] as Dictionary).size(), 8, "all players")
	var p3: Dictionary = s["players"][3]
	t.check((p3["pos"] as Vector3).distance_to(h.sim.player(3).pos()) < 0.02, "position quantisation < 2 cm")
	t.check(s.has("me") and (s["me"] as Dictionary).has("motor"), "private motor block for prediction")
	var evs := [{"id": 7, "t": 99, "type": TC.Ev.CAPTURE, "a": 2, "b": 6, "v": 0, "pos": Vector3(1, 2, 3)}]
	var eb := Protocol.reader(Protocol.encode_events(evs))
	eb.get_u8()
	var de := Protocol.decode_events(eb)
	t.eq(int(de[0]["id"]), 7, "event id")
	t.eq(int(de[0]["type"]), TC.Ev.CAPTURE, "event type")
	h.free_sim()


func test_lobby_join_ready_start() -> void:
	var rig := _rig(40, 5, 0.0, 3)
	await rig.wait_until(func() -> bool: return rig.host.human_count() == 4, 240)
	t.eq(rig.host.human_count(), 4, "host sees four humans")
	await rig.wait_until(func() -> bool:
		for c in rig.clients:
			if c.local_slot < 0 or c.human_count() != 4:
				return false
		return true, 240)
	for c in rig.clients:
		t.check(c.local_slot >= 1, "client got a roster slot")
		t.eq(c.human_count(), 4, "clients see the full roster")
	t.check(not rig.host.can_start(), "can't start until everyone is ready")
	for c in rig.clients:
		c.set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.can_start(), 240)
	t.check(rig.host.can_start(), "all ready -> can start")
	rig.host.host_start_match(4242)
	await rig.wait_until(func() -> bool: return rig.started.size() == 4, 240)
	t.eq(rig.started.size(), 4, "everyone received START")
	var hs: Dictionary = rig.started[rig.host]
	for c in rig.clients:
		var cs: Dictionary = rig.started[c]
		t.eq(int(cs["seed"]), int(hs["seed"]), "same seed")
		t.eq(cs["targets"], hs["targets"], "same targets")
		t.eq(str(cs["roster"].map(func(e): return [e["slot"], e["role"], e["is_bot"]])), str(hs["roster"].map(func(e): return [e["slot"], e["role"], e["is_bot"]])), "same roster/roles")
	var bots := 0
	var patrol := 0
	for e in hs["roster"]:
		if bool(e["is_bot"]):
			bots += 1
			# shown everywhere with a "BOT" tag driven by is_bot (synced above);
			# bot names are from the fixed list, never a player's name
			t.check(NetSession.BOT_NAMES.has(String(e["name"])), "bots clearly labelled")
		if int(e["role"]) == P:
			patrol += 1
	t.eq(bots, 4, "bots fill the 4 empty slots")
	t.eq(patrol, 2, "six/two split")
	rig.teardown()


func _scripted_runner(mc: MatchController) -> InputCmd:
	var c := InputCmd.new()
	var tk := Engine.get_physics_frames()
	var phase := (tk / 90) % 4
	c.move = [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)][phase]
	if tk % 70 == 0:
		c.pressed |= TC.BTN_JUMP
	if (tk / 45) % 3 == 0:
		c.held |= TC.BTN_SPRINT
	c.cam_yaw = 0.0
	return c


func _match_sync(lat: float, jit: float, loss: float, label: String) -> Dictionary:
	var rig := _rig(lat, jit, loss, 1, ["patrol", "runner"])
	var client: NetSession = rig.clients[0]
	rig.inputs[client] = _scripted_runner
	await rig.wait_until(func() -> bool: return client.local_slot >= 0, 300)
	client.set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.can_start(), 300)
	rig.host.host_start_match(777)
	await rig.wait_until(func() -> bool: return rig.mcs.size() == 2, 300)
	var hmc := rig.host_mc()
	var cmc := rig.mc_of(client)
	await rig.wait_until(func() -> bool: return hmc.sim.phase == TC.Phase.PLAYING, 900)
	await rig.frames(60 * 12)
	var slot := client.local_slot
	# prediction quality: corrections applied on reconciliation
	var corr: Array = cmc.stat_corrections
	var avg := 0.0
	var mx := 0.0
	var big := 0
	for e in corr:
		avg += e
		mx = maxf(mx, e)
		if e > 0.25:
			big += 1
	avg /= maxf(1.0, float(corr.size()))
	# final agreement: client's predicted pos vs host authoritative pos ~latency ago
	var host_p := hmc.sim.player(slot).pos()
	var pred_p := cmc.pred.pos()
	# remote interpolation error: a teammate runner (always relevant) as seen by the client
	var mate := -1
	for p in hmc.sim.players:
		if p.is_runner() and p.id != slot:
			mate = p.id
			break
	var rs := cmc._player_rs(mate)
	var rt := int(round(cmc._est_tick - cmc._interp_ticks))
	var hist: Dictionary = rig.host_positions.get(mate, {})
	var interp_err := -1.0
	if rs.has("pos") and hist.has(rt):
		interp_err = (rs["pos"] as Vector3).distance_to(hist[rt])
	var host_ev_ids: Array = rig.host_events.map(func(e): return int(e["id"]))
	var client_ev_ids: Array = (rig.client_events[client] as Array).map(func(e): return int(e["id"]))
	var missing := 0
	for id in host_ev_ids:
		if not client_ev_ids.has(id) and id < host_ev_ids.max() - 30:
			missing += 1
	var stats := {"label": label, "rtt_ms": lat * 2.0, "jitter_ms": jit, "loss": loss, "snapshots": cmc.stat_snapshots,
		"corr_avg_m": snappedf(avg, 0.001), "corr_max_m": snappedf(mx, 0.001), "corr_over_25cm": big,
		"pred_vs_host_m": snappedf(pred_p.distance_to(host_p), 0.01), "interp_err_m": snappedf(interp_err, 0.01),
		"host_events": host_ev_ids.size(), "missing_reliable_events": missing, "client_rtt_est_ms": snappedf(client.rtt * 1000.0, 1),
		"hub_sent": rig.hub.sent, "hub_dropped": rig.hub.dropped, "kb_sent": snappedf(rig.hub.bytes / 1024.0, 0.1),
		"host_starved": rig.host.stat_starved, "host_skipped": rig.host.stat_skipped}
	print("NETSTAT " + JSON.stringify(stats))
	rig.teardown()
	return stats


func test_match_sync_100ms() -> void:
	var s := await _match_sync(50, 8, 0.0, "rtt100")
	t.check(s["snapshots"] > 150, "client received a steady snapshot stream")
	t.check(float(s["corr_avg_m"]) < 0.05, "prediction corrections small on average (%s m)" % s["corr_avg_m"])
	t.eq(int(s["missing_reliable_events"]), 0, "no reliable events lost")
	t.check(float(s["interp_err_m"]) >= 0.0 and float(s["interp_err_m"]) < 0.6, "remote interpolation close to authoritative (%s m)" % s["interp_err_m"])


func test_match_sync_150ms_with_loss() -> void:
	var s := await _match_sync(75, 15, 0.05, "rtt150_loss5")
	t.check(float(s["corr_avg_m"]) < 0.12, "prediction holds with 5%% loss (%s m)" % s["corr_avg_m"])
	t.eq(int(s["missing_reliable_events"]), 0, "reliable events survive loss")


func test_match_sync_high_latency() -> void:
	var s := await _match_sync(150, 30, 0.1, "rtt300_loss10")
	t.check(int(s["snapshots"]) > 100, "still synchronising at 300 ms RTT / 10%% loss")


func test_capture_reaches_client_and_client_patrol_tag() -> void:
	# host = patrol (scripted chase), client = runner standing still
	var rig := _rig(60, 10, 0.02, 1, ["patrol", "runner"])
	var client: NetSession = rig.clients[0]
	await rig.wait_until(func() -> bool: return client.local_slot >= 0, 300)
	client.set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.can_start(), 300)
	var chase := func(mc: MatchController) -> InputCmd:
		var c := InputCmd.new()
		if mc.sim == null or mc.sim.phase != TC.Phase.PLAYING:
			return c
		var me := mc.sim.player(mc.local_slot)
		var tgt := mc.sim.player(1)
		var rel := tgt.pos() - me.pos()
		c.move = Vector2(rel.x, rel.z).normalized()
		c.cam_yaw = atan2(-rel.x, -rel.z)
		if Vector2(rel.x, rel.z).length() < 1.3 and Engine.get_physics_frames() % 20 == 0:
			c.pressed |= TC.BTN_TAG
		return c
	rig.inputs[rig.host] = chase
	rig.host.host_start_match(31)
	await rig.wait_until(func() -> bool: return rig.mcs.size() == 2, 300)
	var hmc := rig.host_mc()
	await rig.wait_until(func() -> bool: return hmc.sim.patrol_release_left() <= 0.0 and hmc.sim.phase == TC.Phase.PLAYING, 900)
	# park the runner next to the patrol so the chase is short
	var me := hmc.sim.player(0)
	hmc.sim.player(1).body.global_position = me.pos() + Vector3(4, 0, 0)
	var got := await rig.wait_until(func() -> bool:
		for e in rig.client_events[client]:
			if int(e["type"]) == TC.Ev.CAPTURE and int(e["a"]) == 1:
				return true
		return false, 600)
	t.check(got, "client receives the authoritative capture event")
	var cmc := rig.mc_of(client)
	await rig.frames(20)
	t.eq(int(cmc._player_rs(1).get("state", -1)), TC.PState.CAPTURED, "client's own state shows captured (not predicted away)")
	rig.teardown()


func test_client_patrol_lag_compensated_tags() -> void:
	# client = patrol at ~150 ms RTT tags a host-side runner moving in a line
	var rig := _rig(75, 10, 0.0, 1, ["runner", "patrol"])
	var client: NetSession = rig.clients[0]
	await rig.wait_until(func() -> bool: return client.local_slot >= 0, 300)
	client.set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.can_start(), 300)
	var runner_line := func(mc: MatchController) -> InputCmd:
		var c := InputCmd.new()
		c.move = Vector2(1, 0) if (Engine.get_physics_frames() / 180) % 2 == 0 else Vector2(-1, 0)
		return c
	rig.inputs[rig.host] = runner_line
	var hunter := func(mc: MatchController) -> InputCmd:
		var c := InputCmd.new()
		if mc._client_phase != TC.Phase.PLAYING or mc.pred == null:
			return c
		var seen := mc._player_rs(0)   # what this client actually sees (interpolated)
		if not seen.has("pos"):
			return c
		var rel: Vector3 = (seen["pos"] as Vector3) - mc.pred.pos()
		c.move = Vector2(rel.x, rel.z).normalized()
		c.cam_yaw = atan2(-rel.x, -rel.z)
		if Vector2(rel.x, rel.z).length() < 1.4 and Engine.get_physics_frames() % 15 == 0:
			c.pressed |= TC.BTN_TAG
		return c
	rig.inputs[client] = hunter
	rig.host.host_start_match(55)
	await rig.wait_until(func() -> bool: return rig.mcs.size() == 2, 300)
	var hmc := rig.host_mc()
	await rig.wait_until(func() -> bool: return hmc.sim.patrol_release_left() <= 0.0 and hmc.sim.phase == TC.Phase.PLAYING, 900)
	var pat := hmc.sim.player(client.local_slot)
	hmc.sim.player(0).body.global_position = Vector3(-30, 0.05, 50)
	pat.body.global_position = Vector3(-30, 0.05, 56)
	var captured := await rig.wait_until(func() -> bool:
		for e in rig.host_events:
			if int(e["type"]) == TC.Ev.CAPTURE:
				return true
		return false, 900)
	t.check(captured, "client patrol can tag a moving runner at 150 ms RTT (lag compensation)")
	print("NETSTAT " + JSON.stringify({"label": "client_patrol_tag_150ms", "captured": captured, "lag_ticks": pat.lag_ticks}))
	rig.teardown()


func test_host_loss_clean_and_silent() -> void:
	var rig := _rig(40, 5, 0.0, 2)
	await rig.wait_until(func() -> bool: return rig.clients[0].local_slot >= 0 and rig.clients[1].local_slot >= 0, 300)
	for c in rig.clients:
		c.set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.can_start(), 300)
	rig.host.host_start_match(9)
	await rig.wait_until(func() -> bool: return rig.mcs.size() == 3, 300)
	await rig.frames(240)
	# (a) clean: host closes its transport -> clients see peer_left
	rig.host_t.close()
	var a := await rig.wait_until(func() -> bool: return rig.ended_reason.has(rig.clients[0]), 120)
	t.check(a, "clients detect host loss")
	t.eq(String(rig.ended_reason.get(rig.clients[0], "")), "host_left", "reported as host left")
	t.check(not rig.results.has(rig.clients[0]), "no results/rewards claimed for the interrupted round")
	rig.teardown()
	# (b) silent: host stops sending (frozen/backgrounded) -> timeout
	var rig2 := _rig(40, 5, 0.0, 1)
	await rig2.wait_until(func() -> bool: return rig2.clients[0].local_slot >= 0, 300)
	rig2.clients[0].set_local_ready(true)
	await rig2.wait_until(func() -> bool: return rig2.host.can_start(), 300)
	rig2.host.host_start_match(10)
	await rig2.wait_until(func() -> bool: return rig2.mcs.size() == 2, 300)
	await rig2.frames(120)
	rig2.hub.frozen[rig2.host_t.id] = true   # host app frozen/backgrounded: silent, unresponsive
	var b := await rig2.wait_until(func() -> bool: return rig2.ended_reason.has(rig2.clients[0]), int(Rules.cfg.host_timeout_s * 60) + 120)
	t.check(b, "silent host detected by timeout")
	t.eq(String(rig2.ended_reason.get(rig2.clients[0], "")), "host_timeout", "timeout reason")
	rig2.teardown()


func test_reconnect_resumes_slot_and_progress() -> void:
	var rig := _rig(40, 5, 0.0, 1, ["patrol", "runner"])
	var c0: NetSession = rig.clients[0]
	await rig.wait_until(func() -> bool: return c0.local_slot >= 0, 300)
	c0.set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.can_start(), 300)
	rig.host.host_start_match(12)
	await rig.wait_until(func() -> bool: return rig.mcs.size() == 2, 300)
	var hmc := rig.host_mc()
	await rig.wait_until(func() -> bool: return hmc.sim.phase == TC.Phase.PLAYING, 900)
	var slot := c0.local_slot
	var key := c0.rejoin_key
	t.check(key.length() >= 16, "the host gave this player a rejoin key")
	var sp := hmc.sim.player(slot)
	sp.stamps = 1
	sp.last_stamp_water = int(hmc.sim.targets[0])
	# drop the client
	rig.client_ts[0].close()
	await rig.frames(30)
	t.check(sp.bot_takeover, "bot covers while the player is away")
	await rig.frames(60 * 5)
	# an impostor with the same identity but no key is refused
	var imp := rig.add_client("uid-c0", "Client0", "runner")
	await rig.wait_until(func() -> bool: return rig.ended_reason.has(imp), 300)
	t.eq(rig.ended_reason.get(imp, ""), "in_use", "no slot takeover without the rejoin key")
	t.check(sp.bot_takeover, "the slot is still held for its owner")
	# same identity reconnects with a fresh transport and its key
	var c1 := rig.add_client("uid-c0", "Client0", "runner")
	c1.rejoin_key = key
	var ok := await rig.wait_until(func() -> bool: return c1.local_slot == slot and rig.started.has(c1), 300)
	t.check(ok, "reconnected into the same slot and match")
	t.check(sp.connected and not sp.bot_takeover, "player back in control")
	t.eq(sp.stamps, 1, "same progress, no reset")
	t.eq(sp.protect, 0.0, "no free immunity")
	await rig.frames(60)
	var cmc := rig.mc_of(c1)
	t.check(cmc != null and cmc.stat_snapshots > 0, "reconnected client receives snapshots")
	rig.teardown()


func test_late_join_spectates_then_plays_next_round() -> void:
	var rig := _rig(30, 5, 0.0, 1)
	await rig.wait_until(func() -> bool: return rig.clients[0].local_slot >= 0, 300)
	rig.clients[0].set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.can_start(), 300)
	rig.host.host_start_match(13)
	await rig.wait_until(func() -> bool: return rig.mcs.size() == 2, 300)
	await rig.wait_until(func() -> bool: return rig.host_mc().sim.phase == TC.Phase.PLAYING, 900)
	var late := rig.add_client("uid-late", "Late", "any")
	await rig.wait_until(func() -> bool: return rig.started.has(late), 300)
	t.eq(late.local_slot, -1, "mid-match newcomer waits as spectator")
	t.check(rig.mc_of(late).spectator, "spectator view")
	var roster_uids: Array = rig.started[rig.host]["roster"].map(func(e): return e["uid"])
	t.check(not roster_uids.has("uid-late"), "active roster locked")
	# finish the round, rematch
	rig.host_mc().sim.end_tick = rig.host_mc().sim.tick + 2
	await rig.wait_until(func() -> bool: return rig.host_mc().sim.phase == TC.Phase.RESULTS, 1200)
	rig.host.host_return_to_lobby()
	rig.host.host_start_match(14)
	await rig.frames(30)
	var uids2: Array = rig.host.current_start["roster"].map(func(e): return e["uid"])
	t.check(uids2.has("uid-late"), "spectator joins the next round")
	t.check(late.local_slot >= 0, "spectator got a slot")
	rig.teardown()


func test_rematch_cleanup() -> void:
	var rig := _rig(20, 0, 0.0, 1)
	await rig.wait_until(func() -> bool: return rig.clients[0].local_slot >= 0, 300)
	rig.clients[0].set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.can_start(), 300)
	rig.host.host_start_match(15)
	var first_targets: Array = rig.host.current_start["targets"]
	await rig.wait_until(func() -> bool: return rig.mcs.size() == 2, 300)
	await rig.wait_until(func() -> bool: return rig.host_mc().sim.phase == TC.Phase.PLAYING, 900)
	rig.host_mc().sim.end_tick = rig.host_mc().sim.tick + 2
	await rig.wait_until(func() -> bool: return rig.host_mc().sim.phase == TC.Phase.RESULTS, 1200)
	await rig.frames(10)
	t.check(rig.results.has(rig.clients[0]), "client received results")
	rig.host.host_return_to_lobby()
	var bots := 0
	for e in rig.host.roster:
		if e != null and bool(e["is_bot"]):
			bots += 1
		if e != null:
			t.eq(bool(e["ready"]), false, "ready flags reset")
			t.eq(int(e["role"]), -1, "roles cleared")
	t.eq(bots, 0, "bots removed between rounds")
	t.eq(rig.host.sim, null, "previous sim released")
	await rig.frames(10)
	t.eq(rig.clients[0].phase, TC.Phase.LOBBY, "client back in lobby")
	rig.clients[0].set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.can_start(), 300)
	rig.host.host_start_match(15)   # same seed on purpose
	t.check(not RulesLogic._same_set(rig.host.current_start["targets"], first_targets), "no immediate target repeat across rematches")
	rig.teardown()


func test_duplicate_reordered_inputs_and_late_snapshots() -> void:
	var s := NetSession.new()
	t.add_child(s)
	s.start_offline("u", "n", {}, "runner")
	s.host_start_match(1)
	var h := SimHarness.new(t)
	h.make([R, P], [0, 1, 2])
	s.sim = h.sim
	var mk := func(seq: int) -> InputCmd:
		var c := InputCmd.new()
		c.seq = seq
		return c
	s._queue_inputs(1, [mk.call(5), mk.call(3), mk.call(4), mk.call(4), mk.call(6)])
	var order: Array = []
	for i in 4:
		var got := s.host_collect_inputs()
		if got.has(1):
			order.append((got[1] as InputCmd).seq)
	t.eq(order, [3, 4, 5, 6], "processed once each, in sequence order")
	s._queue_inputs(1, [mk.call(2), mk.call(6), mk.call(7)])
	var got2 := s.host_collect_inputs()
	t.eq((got2[1] as InputCmd).seq, 7, "late/duplicate inputs ignored")
	# skipped inputs keep their button edges
	var a: InputCmd = mk.call(8)
	a.pressed = TC.BTN_JUMP
	s._queue_inputs(1, [a, mk.call(9), mk.call(10), mk.call(11), mk.call(12)])
	var got3 := s.host_collect_inputs()
	t.check(((got3[1] as InputCmd).pressed & TC.BTN_JUMP) != 0, "edges survive catch-up skipping")
	h.free_sim()
	s.queue_free()
	# late snapshot never overrides newer state
	var mc := MatchController.new()
	mc.cfg = Rules.cfg
	mc._on_snapshot({"tick": 100, "phase": TC.Phase.PLAYING, "players": {}, "carts": [], "ack": 0})
	mc._on_snapshot({"tick": 90, "phase": TC.Phase.REVEAL, "players": {}, "carts": [], "ack": 0})
	t.eq(int(mc._last_snap["tick"]), 100, "late snapshot ignored")
	t.eq(mc._client_phase, TC.Phase.PLAYING, "phase not rolled back by a late packet")
	mc.free()


func test_eight_players_online_sync() -> void:
	# host + 7 simulated network clients, 120 ms RTT, 3% loss
	var rig := _rig(60, 10, 0.03, 7)
	await rig.wait_until(func() -> bool: return rig.host.human_count() == 8, 600)
	t.eq(rig.host.human_count(), 8, "eight humans in the room (no bots)")
	for c in rig.clients:
		rig.inputs[c] = _scripted_runner
		c.set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.can_start(), 600)
	rig.host.host_start_match(808)
	await rig.wait_until(func() -> bool: return rig.mcs.size() == 8, 600)
	var hmc := rig.host_mc()
	await rig.wait_until(func() -> bool: return hmc.sim.phase == TC.Phase.PLAYING, 900)
	await rig.frames(60 * 8)
	var worst := 0.0
	var total := 0
	for c in rig.clients:
		var mc := rig.mc_of(c)
		total += mc.stat_snapshots
		var avg := 0.0
		for e in mc.stat_corrections:
			avg += e
		avg /= maxf(1.0, float(mc.stat_corrections.size()))
		worst = maxf(worst, avg)
	var bots := 0
	for p in hmc.sim.players:
		if p.is_bot:
			bots += 1
	t.eq(bots, 0, "no bots needed with eight humans")
	for c in rig.clients:
		var mcx := rig.mc_of(c)
		var a2 := 0.0
		for e in mcx.stat_corrections:
			a2 += e
		print("CLIENT slot=%d role=%d avg=%.3f n=%d big=%s" % [c.local_slot, mcx.pred.role, a2 / maxf(1.0, mcx.stat_corrections.size()), mcx.stat_corrections.size(), str(mcx.stat_big.slice(0, 4))])
	t.check(total > 7 * 100, "all seven clients synchronising (%d snapshots)" % total)
	t.check(worst < 0.15, "worst client's average correction %.3f m" % worst)
	print("NETSTAT " + JSON.stringify({"label": "eight_player_loopback_rtt120_loss3", "clients": 7, "snapshots": total, "worst_avg_corr_m": snappedf(worst, 0.001), "kb_sent": snappedf(rig.hub.bytes / 1024.0, 0.1), "dropped": rig.hub.dropped, "sent": rig.hub.sent, "host_starved": rig.host.stat_starved, "host_skipped": rig.host.stat_skipped}))
	rig.teardown()


class AnyError:
	extends Logger
	var n := 0

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool,
			_error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		n += 1


func test_enet_sends_to_departed_peers_are_dropped_quietly() -> void:
	# real UDP on localhost (the desktop/LAN development transport)
	var port := 7600 + randi() % 90
	var host := EnetTransport.new()
	if host.host(port) != OK:
		t.check(false, "could not open a UDP port for the ENet test")
		return
	var cl := EnetTransport.new()
	cl.join("127.0.0.1", port)
	var deadline := Time.get_ticks_msec() + 3000
	while host.peers().is_empty() and Time.get_ticks_msec() < deadline:
		host.poll(0.016)
		cl.poll(0.016)
		await t.get_tree().process_frame
	t.eq(host.peers().size(), 1, "a client connects over UDP")
	if host.peers().is_empty():
		host.close()
		cl.close()
		return
	var id: int = host.peers()[0]
	host.latency_ms = 40.0
	host.send(id, PackedByteArray([1, 2, 3]), true)  # still queued (shaped latency) when the client leaves
	cl.close()
	deadline = Time.get_ticks_msec() + 3000
	while not host.peers().is_empty() and Time.get_ticks_msec() < deadline:
		host.poll(0.016)
		await t.get_tree().process_frame
	t.check(host.peers().is_empty(), "the host sees the client leave")
	var errs := AnyError.new()
	OS.add_logger(errs)
	host.send(id, PackedByteArray([4]), true)
	host.latency_ms = 0.0
	host.send(id, PackedByteArray([5]), false)
	host.send(4242, PackedByteArray([6]), true)
	await t.get_tree().create_timer(0.1).timeout
	host.poll(0.016)
	OS.remove_logger(errs)
	t.eq(errs.n, 0, "packets for a departed or unknown peer are dropped without engine errors")
	host.close()
