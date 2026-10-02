extends RefCounted
## V6 Walk around in the party room, on the real stage and lobby screen:
## menu input never moves the runner; walk mode moves it with collision and
## the other device sees it; the chat drawer or a sheet takes input
## ownership and nothing moves while it is open (and nothing sticks after);
## a guest's walk shows on the host's stage with a nameplate and strolls
## back to its mark; leaving the screen or starting the round ends it all.
var t
var _stage: DormStage


func _setup(rig: NetRig) -> LobbyScreen:
	_stage = DormStage.new()
	t.add_child(_stage)
	App.stage = _stage
	_stage.set_mode("lobby", false)
	var l := LobbyScreen.new()
	l.session = rig.host
	t.add_child(l)
	return l


func _press(action: String, on: bool) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)


func test_walk_mode_input_ownership_and_sync() -> void:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(20, 0, 0.0, 1)
	var guest: NetSession = rig.clients[0]
	await rig.wait_until(func() -> bool: return guest.local_slot >= 0 and rig.host.human_count() == 2, 300)
	var saved_uid: Variant = Save.data["uid"]
	var saved_session := App.session
	Save.data["uid"] = "uid-host"
	App.session = rig.host
	var l := _setup(rig)
	await rig.frames(10)
	var hv: CharacterView = _stage.chars["uid-host"]
	var mark := hv.position
	# menu mode: movement keys don't move anyone
	_press("move_forward", true)
	await rig.frames(20)
	t.check(hv.position.distance_to(mark) < 0.01, "menu input never moves the runner")
	t.eq(l.hub.moved_frames, 0, "(no movement read in menu mode)")
	_press("move_forward", false)
	# walk mode
	l._set_walk(true)
	await rig.frames(2)
	t.check(l.hub.walking and _stage.mode == "walk", "walk mode: the follow camera")
	t.check(l.stick.visible and not l.roster_col.visible, "the stick shows and the roster folds away")
	_press("move_forward", true)
	await rig.frames(40)
	_press("move_forward", false)
	t.check(hv.position.z < mark.z - 0.5, "walking forward moves the runner away from the camera (%s -> %s)" % [str(mark), str(hv.position)])
	await rig.frames(20)
	var seen: Dictionary = guest.social.hub.sample(0)
	t.check(not seen.is_empty() and int(seen["mode"]) == HubSync.MODE_WALK, "the guest sees the host walking")
	t.check((seen["pos"] as Vector2).distance_to(Vector2(hv.position.x, hv.position.z)) < 0.3, "where the host is")
	# walls and furniture: a long walk into the couch stops at it
	_press("move_left", true)
	_press("move_forward", true)
	await rig.frames(240)
	_press("move_left", false)
	_press("move_forward", false)
	t.check(HubRoom.is_free(Vector2(hv.position.x, hv.position.z)), "never inside furniture or a wall (%s)" % str(hv.position))
	# the chat drawer owns input: holding a key does nothing while it is open
	l._open_chat()
	await rig.frames(2)
	t.check(InputOwner.menu_owns(), "the chat drawer takes input ownership")
	var before := hv.position
	var mf := l.hub.moved_frames
	_press("move_right", true)
	await rig.frames(30)
	t.check(hv.position.distance_to(before) < 0.05, "nothing moves while chat is open")
	t.eq(l.hub.moved_frames, mf, "(no movement read)")
	Controls.touch_move = Vector2(1, 0)   # a finger that was on the stick when the drawer opened
	var drawer: ChatDrawer = l.find_children("*", "ChatDrawer", true, false)[0]
	drawer.close()
	await rig.frames(2)
	t.check(not InputOwner.menu_owns(), "closing it gives input back")
	t.eq(Controls.touch_move, Vector2.ZERO, "and clears stuck touch state")
	_press("move_right", false)
	# a sheet over the room (has_modal) blocks too
	l.dialog("A sheet", [["OK", Callable()]])
	before = hv.position
	_press("move_back", true)
	await rig.frames(20)
	_press("move_back", false)
	t.check(hv.position.distance_to(before) < 0.05, "no walking under a sheet")
	for d in l.find_children("*", "PanelContainer", false, false):
		d.queue_free()
	await rig.frames(4)
	# the guest walks: their runner leaves its mark on the host's stage, with a nameplate
	var gv: CharacterView = _stage.chars["uid-c0"]
	var gmark := gv.position
	for i in 12:
		guest.social.hub.set_local(HubSync.MODE_WALK, Vector2(gmark.x + 0.15 * i, gmark.z - 0.1 * i), 0.0, 2.0)
		await rig.frames(4)
	await rig.frames(20)
	t.check(gv.position.distance_to(gmark) > 0.8, "the guest's walk shows on the host's stage")
	t.check(_stage.free_roam.has("uid-c0"), "(walking freely)")
	t.check(gv.name_label != null and gv.name_label.visible, "with a nameplate over them")
	guest.social.hub.set_local(HubSync.MODE_MARK, Vector2(gmark.x + 1.8, gmark.z - 1.2), 0.0, 0.0)
	await rig.wait_until(func() -> bool: return not _stage.free_roam.has("uid-c0"), 400)
	t.check(gv.position.distance_to(gmark) < 0.1, "they stroll back to their mark when they stop")
	t.eq((_stage.chars["uid-c0"] as Node).get_instance_id(), gv.get_instance_id(), "the same character the whole time (no rebuild)")
	# Back leaves walk mode first (not the party)
	l.back_action.call()
	await rig.frames(2)
	t.check(not l.hub.walking and _stage.mode == "lobby" and l.roster_col.visible, "Back returns to the menu composition")
	t.check(not l.has_modal(), "without asking to leave the party")
	await rig.wait_until(func() -> bool: return not _stage.free_roam.has("uid-host"), 400)
	t.check(hv.position.distance_to(mark) < 0.1, "the host is back on their mark")
	# leaving the screen (wardrobe/Locker, shop) ends walk mode at once
	l._set_walk(true)
	await rig.frames(3)
	l.queue_free()
	await rig.frames(3)
	t.check(rig.host.social.hub.local_mode == HubSync.MODE_MARK, "leaving the party room screen stops the walk for everyone")
	_stage.queue_free()
	App.stage = null
	App.session = saved_session
	Save.data["uid"] = saved_uid
	rig.teardown()
	await t.get_tree().process_frame   # (queued frees happen before the next test)
	await t.get_tree().process_frame


func test_round_start_cancels_walking_everywhere() -> void:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(20, 0, 0.0, 1)
	var guest: NetSession = rig.clients[0]
	await rig.wait_until(func() -> bool: return guest.local_slot >= 0 and rig.host.human_count() == 2, 300)
	var saved_uid: Variant = Save.data["uid"]
	var saved_session := App.session
	Save.data["uid"] = "uid-host"
	App.session = rig.host
	var l := _setup(rig)
	await rig.frames(10)
	l._set_walk(true)
	guest.social.hub.set_local(HubSync.MODE_WALK, Vector2(1.0, 0.0), 0.0, 1.0)
	_press("move_forward", true)
	await rig.frames(20)
	t.check(not _stage.free_roam.is_empty(), "people are walking")
	guest.set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.can_start(), 200)
	l._on_primary()
	await rig.frames(3)
	_press("move_forward", false)
	t.check(not l.hub.walking, "starting the round ends walk mode at once")
	t.check(_stage.free_roam.is_empty(), "everyone is back on their mark")
	t.check(rig.host.social.hub.poses.is_empty(), "no poses carry into the round")
	await rig.frames(6)
	t.check(guest.social.hub.samples.is_empty(), "on the guest too")
	l.queue_free()
	_stage.queue_free()
	App.stage = null
	App.session = saved_session
	Save.data["uid"] = saved_uid
	rig.teardown()
	await t.get_tree().process_frame   # (queued frees happen before the next test)
	await t.get_tree().process_frame
