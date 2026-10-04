extends RefCounted
## V7: the pause menu in a party round (host and guest, in-process loopback
## network).  The menu is personal: the shared round, its clock and the
## network keep running for everyone, this player's input is neutral while it
## is open (no immunity: they can still be caught), it says so in one line,
## and Leave states its real consequence.  Leaving never makes up a finish,
## a result or a reward.  The touch path to these buttons is covered on the
## real viewport in test_pause_input.gd; here the menu opens through the
## HUD's own entry point so both ends of the network can be watched.
var t


func _rig() -> NetRig:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(20, 0, 0.0, 2, ["runner", "runner", "patrol"])
	return rig


func _start(rig: NetRig) -> bool:
	var c0: NetSession = rig.clients[0]
	var c1: NetSession = rig.clients[1]
	await rig.wait_until(func() -> bool: return c0.local_slot >= 0 and c1.local_slot >= 0 and rig.host.human_count() == 3, 300)
	for c in rig.clients:
		c.set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.can_start(), 200)
	rig.host.host_start_match(77)
	return await rig.wait_until(func() -> bool: return rig.host.sim != null and rig.host.sim.phase == TC.Phase.PLAYING \
		and rig.mc_of(c0) != null and rig.mc_of(c0).prepared and rig.mc_of(c1) != null and rig.mc_of(c1).prepared, 1500)


func _end(rig: NetRig) -> void:
	Input.action_release("move_forward")
	rig.teardown()
	await t.get_tree().process_frame
	await t.get_tree().process_frame


func test_host_menu_keeps_the_round_running() -> void:
	var rig := _rig()
	t.check(await _start(rig), "party round playing")
	var mc := rig.host_mc()
	var g := rig.mc_of(rig.clients[0])
	var hud := mc.hud
	mc.input_source = Callable()   # read the real controls
	hud.open_pause()
	await rig.frames(2)
	t.check(hud.paused() and not hud.game_frozen() and not t.get_tree().paused, "the host's menu never pauses the shared round")
	t.eq(hud._status_lbl.text, "Online match continues.", "and says so in one line")
	var tick0: int = mc.sim.tick
	var gtick0: int = g._last_snap_tick
	Input.action_press("move_forward")
	Controls.push_edge(TC.BTN_JUMP)
	var cmd := mc._build_local_cmd()
	t.eq(cmd.move, Vector2.ZERO, "the host's own input is neutral under the menu")
	t.eq(cmd.pressed, 0, "no jump or tag")
	Input.action_release("move_forward")
	await rig.frames(60)
	t.check(mc.sim.tick >= tick0 + 50, "the host keeps simulating (%d -> %d ticks)" % [tick0, mc.sim.tick])
	t.check(g._last_snap_tick > gtick0 + 30, "and guests keep receiving the round (snapshot %d -> %d)" % [gtick0, g._last_snap_tick])
	t.eq(rig.host.mode, NetSession.Mode.HOST, "the party is intact")
	t.check(rig.ended_reason.is_empty(), "no one was dropped")
	var p := mc.sim.player(mc.local_slot)
	t.eq(p.state, TC.PState.ACTIVE, "no immunity or special state while the menu is open")
	hud._ask_leave()
	t.check(hud._confirm_text.text.contains("ends the match and the party for everyone"), "the host is told leaving ends it for everyone")
	hud._cancel_leave()
	hud.close_pause()
	await rig.frames(4)
	t.check(not hud.paused() and hud.overlays().is_empty(), "closed cleanly")
	await _end(rig)


func test_guest_menu_leave_and_results() -> void:
	var rig := _rig()
	t.check(await _start(rig), "party round playing")
	var c0: NetSession = rig.clients[0]
	var c1: NetSession = rig.clients[1]
	var g := rig.mc_of(c0)
	var hud := g.hud
	g.input_source = Callable()
	hud.open_pause()
	await rig.frames(2)
	t.check(hud.paused() and not t.get_tree().paused, "a guest's menu pauses nothing")
	t.eq(hud._status_lbl.text, "Online match continues.", "Online match continues.")
	var host_tick: int = rig.host_mc().sim.tick
	var snap0: int = g._last_snap_tick
	await rig.frames(30)
	t.check(rig.host_mc().sim.tick > host_tick, "the host's round runs on")
	t.check(g._last_snap_tick > snap0, "and keeps reaching the guest behind the menu")
	hud._ask_leave()
	t.check(hud._confirm_text.text.contains("others play on") and hud._confirm_text.text.contains("earns you nothing"), "a guest is told the others play on and nothing is earned")
	# Leave: once, through the app's own party departure
	var quits := [0]
	var finished := [0]
	g.quit_requested.connect(func() -> void:
		quits[0] += 1
		c0.leave())
	g.finished.connect(func(_r: Dictionary) -> void: finished[0] += 1)
	hud._confirm_leave()
	hud._confirm_leave()
	await rig.frames(30)
	t.eq(quits[0], 1, "Leave fires once")
	t.eq(finished[0], 0, "leaving makes up no finish")
	t.check(not rig.results.has(c0), "and no results for the one who left")
	var hp := rig.host_mc().sim.player(c0.local_slot) if c0.local_slot >= 0 else null
	if hp != null:
		t.check(hp.state != TC.PState.FINISHED, "the host records no finish for them")
	t.eq(rig.host.mode, NetSession.Mode.HOST, "the host's party carries on")
	# the other guest has its menu open when the round ends: results close it
	var g1 := rig.mc_of(c1)
	g1.hud.open_pause()
	g1.hud._ask_leave()
	await rig.frames(2)
	t.check(g1.hud.confirming_leave(), "second guest is on the leave confirmation")
	rig.host_mc().sim.end_tick = rig.host_mc().sim.tick + 2
	await rig.wait_until(func() -> bool: return rig.results.has(c1), 900)
	await rig.wait_until(func() -> bool: return not g1.hud.paused(), 120)
	t.check(not g1.hud.paused() and not g1.hud.confirming_leave() and g1.hud.overlays().is_empty(), "results close the menu and the confirmation")
	g1.hud.open_pause()
	t.check(not g1.hud.paused(), "and Pause stays shut over the results")
	t.check(g1.touch == null or g1.touch.visible or g1.hud.overlays().is_empty(), "no overlay left owning input")
	await _end(rig)
