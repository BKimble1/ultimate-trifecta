extends RefCounted
## V6 chat during a party round, on the real match controller and HUD:
## the chat button is a reserved touch region, a teammate's Quick Chat
## shows in the small feed (the other team's never does), and while the
## drawer is open the round reads no input from this player (no movement,
## no tag, no jump), with nothing left pressed when it closes.
var t


func test_round_chat_feed_drawer_and_input_ownership() -> void:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(20, 0, 0.0, 2, ["runner", "runner", "patrol"])
	var c0: NetSession = rig.clients[0]
	var c1: NetSession = rig.clients[1]
	await rig.wait_until(func() -> bool: return c0.local_slot >= 0 and c1.local_slot >= 0 and rig.host.human_count() == 3, 300)
	for c in rig.clients:
		c.set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.can_start(), 200)
	rig.host.host_start_match(91)
	await rig.wait_until(func() -> bool: return rig.host.sim != null and rig.host.sim.phase == TC.Phase.PLAYING, 1200)
	var mc := rig.host_mc()
	var hud := mc.hud
	t.check(hud.chat != null, "party rounds have chat")
	await rig.frames(4)
	hud._reserve_touch_regions()
	var reserved: Array = hud.chat.reserved()
	t.check(not reserved.is_empty(), "the chat button is reserved from the stick and camera")
	# a runner teammate's phrase reaches the runner host's feed; the Night Watch's doesn't
	c0.social.chat.send_quick(24, QuickChat.Channel.TEAM)
	c1.social.chat.send_quick(26, QuickChat.Channel.TEAM)
	await rig.frames(12)
	var feed_texts: Array = []
	for n in hud.chat.feed.get_children():
		for l in n.find_children("*", "Label", true, false):
			feed_texts.append((l as Label).text)
	t.check(feed_texts.any(func(x: String) -> bool: return x.ends_with("Night Watch nearby!")), "a teammate's message shows in the feed (%s)" % str(feed_texts))
	t.check(not feed_texts.any(func(x: String) -> bool: return x.contains("Runner spotted!")), "the other team's message never reaches you")
	t.check(hud.chat.feed.get_child_count() <= MatchChat.FEED_MAX, "the feed stays short")
	# the feed sits top right, clear of the screen centre and the thumbs
	var vs := hud.root.get_viewport_rect().size
	var fr := hud.chat.feed.get_global_rect()
	t.check(fr.end.x <= vs.x and fr.end.x >= vs.x - 40.0, "feed against the right edge (%s in %s)" % [str(fr), str(vs)])
	t.check(fr.position.y >= hud.pause_btn.get_global_rect().end.y, "below the top-right controls, never over the centre")
	# the drawer owns input: movement, tag and jump are not read
	mc.input_source = Callable()
	hud.chat.open_drawer()
	await rig.frames(2)
	t.check(InputOwner.menu_owns(), "the drawer owns input")
	t.check(mc.touch == null or not mc.touch.visible, "the touch controls are released and hidden")
	Input.action_press("move_forward")
	Controls.push_edge(TC.BTN_TAG)
	Controls.push_edge(TC.BTN_JUMP)
	var cmd := mc._build_local_cmd()
	t.eq(cmd.move, Vector2.ZERO, "no movement while chatting")
	t.eq(cmd.pressed, 0, "no tag or jump while chatting")
	Input.action_release("move_forward")
	Controls.push_edge(TC.BTN_TAG)
	hud.chat.drawer.close()
	await rig.frames(2)
	t.check(not InputOwner.menu_owns(), "closing hands input back")
	t.eq(Controls.pending_edges(), 0, "and nothing pressed meanwhile fires afterwards")
	t.check(mc.touch == null or mc.touch.visible, "the touch controls are back")
	rig.teardown()


func test_practice_has_no_chat() -> void:
	var off := NetSession.new()
	t.add_child(off)
	off.start_offline("uid-solo", "Solo", {}, "runner")
	off.host_start_match(5)
	await t.get_tree().physics_frame
	var mc := MatchController.new()
	mc.setup(off, off.current_start, {"visuals": false, "quality": 0})
	mc.input_source = func(_m: MatchController) -> InputCmd: return InputCmd.new()
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	t.add_child(vp)
	vp.add_child(mc)
	for i in 600:
		if mc.prepared:
			break
		await t.get_tree().physics_frame
	t.check(mc.hud != null and mc.hud.chat == null, "practice with bots has no chat button")
	vp.queue_free()
	off.queue_free()
