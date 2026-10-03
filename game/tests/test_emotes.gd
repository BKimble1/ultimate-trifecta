extends RefCounted
## Lobby emotes end to end (V4): picker -> session -> host event -> the right
## character -> visible animation -> clean return, for every emote, from the
## host and from a guest; rapid reselection, repeats, the ready response,
## an outfit change, the picker sheet, and the stage going away mid-emote.
var t
var _stage: DormStage


func _setup_stage() -> DormStage:
	_stage = DormStage.new()
	t.add_child(_stage)
	App.stage = _stage
	_stage.set_mode("lobby", false)
	return _stage


func _teardown(rig: NetRig, screens: Array) -> void:
	for s in screens:
		if is_instance_valid(s):
			s.queue_free()
	if is_instance_valid(_stage):
		_stage.queue_free()
	App.stage = null
	rig.teardown()


func _lobby(rig: NetRig, s: NetSession) -> LobbyScreen:
	var l := LobbyScreen.new()
	l.session = s
	t.add_child(l)
	return l


func test_every_emote_from_host_and_guest() -> void:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(40, 5, 0.0, 1)
	var guest: NetSession = rig.clients[0]
	await rig.wait_until(func() -> bool: return guest.local_slot >= 0 and rig.host.human_count() == 2, 300)
	var stage := _setup_stage()
	var host_l := _lobby(rig, rig.host)
	await rig.frames(10)
	t.check(stage.chars.has("uid-host") and stage.chars.has("uid-c0"), "both runners on the stage")
	var hv: CharacterView = stage.chars["uid-host"]
	for id in TC.EMOTES.size():
		host_l._send_emote(id)
		await rig.frames(4)
		t.eq(hv._mode, "emote_" + String(TC.EMOTES[id]), "host %s plays at once" % TC.EMOTES[id])
		t.check(hv.find_children("*", "Label3D", false, false).any(func(n: Node) -> bool: return (n as Label3D).visible and (n as Label3D).text == TC.EMOTE_LABELS[TC.EMOTES[id]]),
			"name bubble shows %s" % TC.EMOTE_LABELS[TC.EMOTES[id]])
	# the host's own emote reaches the guest through the network
	await rig.wait_until(func() -> bool: return (rig.client_events[guest] as Array).any(func(e: Dictionary) -> bool: return int(e["type"]) == TC.Ev.EMOTE), 300)
	t.check((rig.client_events[guest] as Array).filter(func(e: Dictionary) -> bool: return int(e["type"]) == TC.Ev.EMOTE).size() == TC.EMOTES.size(),
		"the guest received every host emote (%d)" % TC.EMOTES.size())
	# clean return to idle after the last emote's time (V6: the Season 1
	# emotes come after the V4 six)
	await rig.frames(int(DormStage.EMOTE_S[String(TC.EMOTES[-1])] * 60) + 30)
	t.check(not stage.emoting("uid-host") and hv._mode == "ground", "returns to idle afterwards")
	host_l.queue_free()
	# guest: shown at once, and the host's echo doesn't start it twice
	var guest_l := _lobby(rig, guest)
	await rig.frames(5)
	var gv: CharacterView = stage.chars["uid-c0"]
	var before := int(stage.emote_starts.get("uid-c0", 0))
	guest_l._send_emote(4)
	await rig.frames(2)
	t.eq(gv._mode, "emote_dance", "guest sees its own dance immediately (before any round trip)")
	await rig.frames(30)
	t.eq(int(stage.emote_starts.get("uid-c0", 0)) - before, 1, "the host's echo is skipped: one tap, one start")
	_teardown(rig, [guest_l])


func test_reselection_repeat_ready_and_teardown() -> void:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(30, 0, 0.0, 1)
	var guest: NetSession = rig.clients[0]
	await rig.wait_until(func() -> bool: return guest.local_slot >= 0 and rig.host.human_count() == 2, 300)
	var stage := _setup_stage()
	var host_l := _lobby(rig, rig.host)
	await rig.frames(10)
	var hv: CharacterView = stage.chars["uid-host"]
	# rapid reselection: Wave, then Dance 1 s later; the old emote's end time
	# must not cut the dance short (V3's timer did, at 1.8 s)
	host_l._send_emote(0)
	await rig.frames(60)
	host_l._send_emote(4)
	await rig.frames(100)   # 2.67 s after Wave, 1.67 s into the 3.75 s dance
	t.eq(hv._mode, "emote_dance", "the newer emote owns the character")
	# the same emote again restarts it
	await rig.frames(60)
	var mt := hv._mode_t
	host_l._send_emote(4)
	await rig.frames(1)
	t.check(hv._mode_t < mt, "choosing the same emote again restarts it")
	await rig.frames(int(DormStage.EMOTE_S["dance"] * 60) + 20)
	# ready response: once per change, never over a deliberate emote
	var gv: CharacterView = stage.chars["uid-c0"]
	guest.set_local_ready(true)
	await rig.wait_until(func() -> bool: return gv._ready_t > 0.0, 200)
	t.check(gv._ready_t > 0.0, "a guest tapping Ready plays the ready response on the host's stage")
	await rig.frames(70)
	guest.set_local_ready(false)
	await rig.frames(20)
	stage.emote("uid-c0", 2)
	guest.set_local_ready(true)
	await rig.frames(30)
	t.check(gv._mode == "emote_laugh" and gv._ready_t <= 0.0, "ready doesn't overwrite an emote in progress")
	# after an outfit change, emotes still play
	var cos: Dictionary = Cosmetics.sanitize(rig.host.local_cosmetic)
	cos["outfit"] = "frog"
	rig.host.set_local_cosmetic(cos)
	await rig.frames(10)
	host_l._send_emote(1)
	await rig.frames(3)
	t.eq(hv._mode, "emote_cheer", "emotes work after an outfit change")
	# the picker sheet: open, choose, it closes; reopen and choose again
	for pass_i in 2:
		host_l._emote_popover(host_l.primary_btn)
		await rig.frames(2)
		var tiles := host_l._popover.find_children("*", "Button", true, false).filter(func(b: Node) -> bool: return (b as Button).custom_minimum_size == Vector2(150, 118))
		t.eq(tiles.size(), 6, "six emote tiles")
		(tiles[5] as Button).pressed.emit()
		await rig.frames(3)
		t.check(host_l._popover == null and hv._mode == "emote_point", "picking from the sheet plays it and closes the sheet (pass %d)" % pass_i)
		await rig.frames(160)
	# tap your own runner
	await rig.frames(5)
	var head := stage.cam.unproject_position(hv.global_position + Vector3(0, 0.9, 0))
	t.check(host_l.hit_own_runner(head), "a tap on your runner hits it")
	t.check(not host_l.hit_own_runner(head + Vector2(600, 0)), "a tap beside it doesn't")
	# the stage goes away mid-emote: no errors later (the test runner fails on script errors)
	host_l._send_emote(4)
	await rig.frames(5)
	stage.queue_free()
	App.stage = null
	await rig.frames(int(DormStage.EMOTE_S["dance"] * 60) + 30)
	host_l._send_emote(0)
	t.check(true, "emotes with no stage are a no-op")
	_teardown(rig, [host_l])
