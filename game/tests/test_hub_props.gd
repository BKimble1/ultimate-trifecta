extends RefCounted
## (build 20) Things to do in the party room: walk up to the couch, the floor
## lamp or the plant and a button on the right offers what you can do.  The
## couch and the plant are one person at a time and only within reach (the
## host decides; a device that asked too late is told and walks on), the
## lamp is one switch the whole party sees, the jumper bounces on the seat
## and the cushions squash, a hider is out of sight for everyone, and a
## round start puts everything back.
var t
var _stage: DormStage


func _rig(n: int) -> NetRig:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(20, 0, 0.0, n)
	return rig


func _ready_party(rig: NetRig) -> void:
	await rig.wait_until(func() -> bool:
		for c in rig.clients:
			if c.local_slot < 0:
				return false
		return rig.host.human_count() == rig.clients.size() + 1, 300)
	await rig.frames(6)


func _done(rig: NetRig) -> void:
	rig.teardown()
	await t.get_tree().process_frame
	await t.get_tree().process_frame


## Spots in reach of each prop (open floor).
const BY_COUCH := Vector2(-3.6, -1.75)
const BY_LAMP := Vector2(3.9, -1.2)
const BY_PLANT := Vector2(-4.45, 1.6)


func test_reach_is_measured_from_each_prop() -> void:
	t.eq(HubRoom.prop_near(BY_COUCH), HubRoom.PROP_COUCH, "in front of the couch")
	t.eq(HubRoom.prop_near(BY_LAMP), HubRoom.PROP_LAMP, "by the lamp")
	t.eq(HubRoom.prop_near(BY_PLANT), HubRoom.PROP_PLANT, "by the plant")
	t.eq(HubRoom.prop_near(Vector2(0, 1)), "", "nothing in the middle of the rug")
	for p in [BY_COUCH, BY_LAMP, BY_PLANT]:
		t.check(HubRoom.is_free(p), "%s is somewhere you can stand" % str(p))
	var seat := HubRoom.couch_seat(Vector2(-9, -1.7))
	t.check(seat.x >= HubRoom.COUCH_SEAT_X.x and seat.y > 0.6, "you bounce between the couch's arms")


func test_the_couch_is_one_person_at_a_time() -> void:
	var rig := _rig(2)
	await _ready_party(rig)
	var c0: NetSession = rig.clients[0]
	var c1: NetSession = rig.clients[1]
	var hub := rig.host.social.hub
	c0.social.hub.set_local(HubSync.MODE_WALK, BY_COUCH, 0.0, 0.0)
	c1.social.hub.set_local(HubSync.MODE_WALK, BY_COUCH + Vector2(0.6, 0.1), 0.0, 0.0)
	await rig.frames(12)
	c0.social.hub.set_local(HubSync.MODE_COUCH, BY_COUCH, 0.0, 0.0)
	await rig.frames(12)
	t.eq(int(hub.poses[c0.local_slot]["mode"]), HubSync.MODE_COUCH, "the first one up gets the couch")
	await rig.frames(12)
	t.eq(c1.social.hub.occupant(HubSync.MODE_COUCH), c0.local_slot, "the other guest sees who is on it")
	# the second one asks anyway (a race): the host says no, they walk on
	var said := [-1]
	c1.social.hub.denied.connect(func(m: int, taken: bool) -> void: said[0] = m if taken else -2)
	c1.social.hub.set_local(HubSync.MODE_COUCH, BY_COUCH + Vector2(0.6, 0.1), 0.0, 0.0)
	await rig.frames(12)
	t.eq(int(hub.poses[c1.local_slot]["mode"]), HubSync.MODE_WALK, "the host keeps the second one walking")
	t.eq(said[0], HubSync.MODE_COUCH, "and tells their device")
	t.eq(c1.social.hub.local_mode, HubSync.MODE_WALK, "which walks on")
	# off the couch: now it's free
	c0.social.hub.set_local(HubSync.MODE_WALK, BY_COUCH, 0.0, 0.0)
	await rig.frames(12)
	c1.social.hub.set_local(HubSync.MODE_COUCH, BY_COUCH + Vector2(0.6, 0.1), 0.0, 0.0)
	await rig.frames(12)
	t.eq(int(hub.poses[c1.local_slot]["mode"]), HubSync.MODE_COUCH, "once it's free the next one gets it")
	# from across the room: no
	c0.social.hub.set_local(HubSync.MODE_WALK, Vector2(2.0, 1.5), 0.0, 0.0)
	await rig.frames(60)
	c0.social.hub.set_local(HubSync.MODE_PLANT, Vector2(2.0, 1.5), 0.0, 0.0)
	await rig.frames(12)
	t.eq(int(hub.poses[c0.local_slot]["mode"]), HubSync.MODE_WALK, "nobody hides in the plant from across the room")
	# a pose straight from the mark into the plant: no
	c0.social.hub.set_local(HubSync.MODE_MARK, BY_PLANT, 0.0, 0.0)
	await rig.frames(12)
	c0.social.hub.set_local(HubSync.MODE_PLANT, BY_PLANT, 0.0, 0.0)
	await rig.frames(12)
	t.check(hub.occupant_host(HubSync.MODE_PLANT) < 0, "nobody steps off their mark straight into the plant")
	# a pose that jumps across the room into reach: clamped first, so no
	c0.social.hub.set_local(HubSync.MODE_WALK, Vector2(3.0, 1.5), 0.0, 0.0)
	await rig.frames(30)
	c0.social.hub.set_local(HubSync.MODE_PLANT, BY_PLANT, 0.0, 0.0)
	await rig.frames(12)
	t.check(hub.occupant_host(HubSync.MODE_PLANT) < 0, "nor teleports into reach")
	await _done(rig)


func test_the_lamp_is_one_switch_for_everyone() -> void:
	var rig := _rig(2)
	await _ready_party(rig)
	var c0: NetSession = rig.clients[0]
	var c1: NetSession = rig.clients[1]
	var hub := rig.host.social.hub
	# from across the room: nothing
	c0.social.hub.set_local(HubSync.MODE_WALK, Vector2(0, 1), 0.0, 0.0)
	await rig.frames(12)
	c0.social.hub.request_lamp()
	await rig.frames(12)
	t.check(hub.lamp_on, "the switch is out of reach across the room")
	# (stepping off the mark puts you anywhere; walking there is clamped)
	c0.social.hub.set_local(HubSync.MODE_MARK, Vector2(0, 1), 0.0, 0.0)
	await rig.frames(12)
	c0.social.hub.set_local(HubSync.MODE_WALK, BY_LAMP, 0.0, 0.0)
	await rig.frames(12)
	c0.social.hub.request_lamp()
	await rig.frames(16)
	t.check(not hub.lamp_on, "by the lamp: off")
	t.check(not c0.social.hub.lamp_on and not c1.social.hub.lamp_on, "for everyone")
	# flicking it twice at once only counts once
	await rig.frames(30)
	c0.social.hub.request_lamp()
	c0.social.hub.request_lamp()
	await rig.frames(30)
	t.check(c1.social.hub.lamp_on, "back on (once, however fast the taps)")
	c0.social.hub.request_lamp()
	await rig.frames(16)
	t.check(not c1.social.hub.lamp_on, "and off again")
	# with nobody walking any more the host still repeats it, so a late
	# arrival sees the room dark
	c0.social.hub.set_local(HubSync.MODE_MARK, BY_LAMP, 0.0, 0.0)
	await rig.frames(130)
	c1.social.hub.lamp_on = true
	await rig.frames(80)
	t.check(not c1.social.hub.lamp_on, "the state is repeated while the lamp is off")
	# a round start: the lamp is on again
	rig.host.social.hub.clear()
	t.check(rig.host.social.hub.lamp_on, "the room is reset at a round start")
	await _done(rig)


func _setup(rig: NetRig) -> LobbyScreen:
	_stage = DormStage.new()
	t.add_child(_stage)
	App.stage = _stage
	_stage.set_mode("lobby", false)
	var l := LobbyScreen.new()
	l.session = rig.host
	t.add_child(l)
	return l


func test_couch_plant_and_lamp_on_the_stage() -> void:
	var rig := _rig(1)
	var guest: NetSession = rig.clients[0]
	await rig.wait_until(func() -> bool: return guest.local_slot >= 0 and rig.host.human_count() == 2, 300)
	var saved_uid: Variant = Save.data["uid"]
	var saved_session := App.session
	Save.data["uid"] = "uid-host"
	App.session = rig.host
	var l := _setup(rig)
	await rig.frames(10)
	var hv: CharacterView = _stage.chars["uid-host"]
	l._set_walk(true)
	await rig.frames(3)
	t.check(not l.act_btn.visible, "nothing in reach on the mark: no button")
	# walk up to the couch
	l.hub._pos = BY_COUCH
	await rig.frames(60)   # (the host's own pose catches up at walking pace)
	t.eq(l.hub.prompt().get("text", ""), "Jump on couch", "by the couch: Jump on couch")
	t.check(l.act_btn.visible, "the button shows")
	var vs := l.get_viewport().get_visible_rect().size
	t.check(l.act_btn.get_global_rect().get_center().x > vs.x * 0.6, "on the right side (%s)" % str(l.act_btn.get_global_rect()))
	l.act_btn.pressed.emit()
	await rig.frames(50)
	t.eq(l.hub.act, HubSync.MODE_COUCH, "bouncing on the couch")
	t.eq(int(rig.host.social.hub.poses[0]["mode"]), HubSync.MODE_COUCH, "everyone knows")
	t.check(hv.position.y > 0.55, "up on the seat (%.2f)" % hv.position.y)
	t.eq(l.hub.prompt().get("text", ""), "Stop jumping", "the button now says Stop jumping")
	var lowest := 1.0
	var highest := 0.0
	var top_y := 0.0
	for i in 90:
		await t.get_tree().process_frame
		lowest = minf(lowest, _stage.props._cushions.scale.y)
		highest = maxf(highest, _stage.props._cushions.scale.y)
		top_y = maxf(top_y, hv.position.y)
	t.check(lowest < 0.93, "the cushions squash under the bounce (%.2f)" % lowest)
	t.check(highest > 0.995, "and spring back up")
	t.check(top_y > 0.68 + 0.3, "jumping up and down (%.2f)" % top_y)
	# the guest sees it too
	await rig.frames(10)
	t.eq(guest.social.hub.mode_of(0), HubSync.MODE_COUCH, "the guest sees the host on the couch")
	t.check(guest.social.hub.occupant(HubSync.MODE_COUCH) == 0, "and that it's taken")
	l.act_btn.pressed.emit()
	await rig.frames(45)
	t.eq(l.hub.act, HubSync.MODE_WALK, "Stop jumping: off the couch")
	t.check(hv.position.y < 0.02 and hv.position.distance_to(Vector3(BY_COUCH.x, 0, BY_COUCH.y)) < 0.1, "back on the floor where they got on (%s)" % str(hv.position))
	# the plant
	l.hub._pos = BY_PLANT
	await rig.frames(40)   # (the host's own pose catches up at walking pace)
	t.eq(l.hub.prompt().get("text", ""), "Hide", "by the plant: Hide")
	l.act_btn.pressed.emit()
	await rig.frames(40)
	t.check(not hv.visible, "hidden in the plant")
	t.check(_stage.is_hiding("uid-host"), "(the stage knows)")
	# a stage reframe (mode change) doesn't give them away
	_stage._place("uid-host")
	t.check(not hv.visible, "still hidden after a re-place")
	t.eq(l.hub.prompt().get("text", ""), "Jump out", "the button says Jump out")
	l.act_btn.pressed.emit()
	await rig.frames(40)
	t.check(hv.visible and l.hub.act == HubSync.MODE_WALK, "out of the plant")
	# the lamp
	l.hub._pos = BY_LAMP
	await rig.frames(60)
	t.eq(l.hub.prompt().get("text", ""), "Lights off", "by the lamp: Lights off")
	l.act_btn.pressed.emit()
	await rig.frames(20)
	t.check(not rig.host.social.hub.lamp_on and not _stage.props.lamp_lit(), "the lamp goes off")
	t.eq(l.hub.prompt().get("text", ""), "Lights on", "and the button offers Lights on")
	await rig.frames(10)
	t.check(not guest.social.hub.lamp_on, "the guest's room is dark too")
	# Done while bouncing: off the couch, then back to the mark
	l.hub._pos = BY_COUCH
	await rig.frames(70)
	l.hub.interact()
	await rig.frames(40)
	l._set_walk(false)
	await rig.wait_until(func() -> bool: return not _stage.free_roam.has("uid-host"), 400)
	t.check(hv.position.y < 0.02, "Done while bouncing: down off the couch and home to the mark")
	t.check(not l.act_btn.visible, "the button goes away")
	# the lamp is the party's: it stays off while the party is in the room,
	# and a round start (or leaving the party) turns it back on
	t.check(not _stage.props.lamp_lit(), "the party's lamp stays off after walking")
	rig.host.social.hub.clear()
	await rig.frames(12)
	t.check(_stage.props.lamp_lit(), "a round start puts the lamp back on")
	l.queue_free()
	await rig.frames(3)
	_stage.queue_free()
	App.stage = null
	App.session = saved_session
	Save.data["uid"] = saved_uid
	await _done(rig)
