extends RefCounted
## (build 25) The basketball as drawn, frame by frame, on the real stage and
## lobby screen: picking it up, dribbling standing and walking and turning,
## the shot's windup, its release, its flight and its drop through the net
## never jump (each frame the ball moves no further than its own speed
## allows); the dribble eases in at the hand; a basket puts no words on
## screen (confetti only).
var t


func _move(a: Vector3, b: Vector3) -> float:
	return a.distance_to(b)


func test_the_ball_moves_smoothly_from_pick_up_to_the_basket() -> void:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(20, 0, 0.0, 0)
	await rig.wait_until(func() -> bool: return rig.host.social.ball.spawned, 300)
	var stage := DormStage.new()
	t.add_child(stage)
	var saved_stage := App.stage
	var saved_session := App.session
	App.stage = stage
	App.session = rig.host
	stage.set_mode("lobby", false)
	var l := LobbyScreen.new()
	l.session = rig.host
	t.add_child(l)
	await rig.frames(10)
	l._set_walk(true)
	await rig.frames(10)
	var b := rig.host.social.ball
	var said: Array = []
	l.hub.notice.connect(func(s: String) -> void: said.append(s))
	b.sim.place(Vector3(l.hub._pos.x + 0.55, HubBall.R, l.hub._pos.y))
	await rig.frames(10)
	var view := stage.ball_view
	var worst := {}
	var last := [view.last_pos]   # (an array: the lambda shares it)
	var track := func(label: String, n: int) -> void:
		for i in n:
			await rig.frames(1)
			var d := _move(last[0], view.last_pos)
			last[0] = view.last_pos
			worst[label] = maxf(float(worst.get(label, 0.0)), d)
	# pick it up
	l.hub.interact()
	await track.call("pick up", 30)
	t.eq(b.holder, rig.host.local_slot, "picked up")
	# dribble standing, then walking with turns
	await track.call("dribble", 60)
	for dir in [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0.3), Vector2(0.6, -1)]:
		l.hub.stick = dir
		await track.call("walk and turn", 25)
	l.hub.stick = Vector2.ZERO
	await track.call("stop", 30)
	# to the shooting spot (a teleport for the test; then settle)
	var rc := HubBall.rim_center()
	l.hub._pos = Vector2(rc.x, rc.z) + HubBall.HOOP_DIR * 1.6
	await rig.frames(40)
	last[0] = view.last_pos
	b.force_make = 1
	l.hub.interact()
	await track.call("windup", 20)
	await track.call("release and flight", 60)
	await track.call("through the net", 60)
	# a frame at 60 Hz: the dribble bounces at most ~2.6 m/s off the floor
	# (0.045 m); walking adds the runner's 2.4 m/s; a shot flies at up to
	# ~8 m/s (0.14 m)
	var caps := {"pick up": 0.075, "dribble": 0.05, "walk and turn": 0.09, "stop": 0.09,
		"windup": 0.1, "release and flight": 0.14, "through the net": 0.14}
	for k in worst:
		var cap := float(caps[k])
		t.check(float(worst[k]) <= cap, "%s: smooth (largest step %.3f m a frame, at most %.3f)" % [k, float(worst[k]), cap])
	t.check(b.make_seq >= 1, "the shot went in")
	t.eq(said.size(), 0, "no words on a basket (no Swish!, no Nice shot!): %s" % [said])
	t.check(view.confetti_bursts >= 1, "the confetti says it")
	l.queue_free()
	stage.queue_free()
	App.stage = saved_stage
	App.session = saved_session
	rig.teardown()
	await t.get_tree().process_frame
