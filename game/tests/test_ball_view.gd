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
	l.hub._yaw = atan2(HubBall.HOOP_DIR.x, HubBall.HOOP_DIR.y)   # (build 25) facing the hoop: -HOOP_DIR
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


## (build 25) The arm really works the ball: measured on the skeleton as it
## is posed (the IK's result exists only during the skeleton's update), the
## right hand is on its target every frame of the dribble, pumping up and
## down with the ball; in the shot it stays under the ball up to the set
## point, then reaches up and out in the follow-through.
func test_the_arm_dribbles_and_shoots() -> void:
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
	b.sim.place(Vector3(l.hub._pos.x + 0.4, HubBall.R, l.hub._pos.y))
	await rig.frames(5)
	l.hub.interact()
	await rig.frames(30)
	var v: CharacterView = stage.chars[l.hub.local_key()]
	var sk := v.skeleton
	var hi := sk.find_bone("hand.R")
	var hand := [Vector3.ZERO]
	sk.skeleton_updated.connect(func() -> void: hand[0] = stage.to_local(sk.global_transform * sk.get_bone_global_pose(hi).origin))
	var ik: Dictionary = stage.ball_view._iks.get(l.hub.local_key(), {})
	t.check(not ik.is_empty(), "the holder's arms have their IK")
	var gap := 0.0
	var lo := INF
	var hi_y := -INF
	var top_gap := INF
	for i in 40:
		await rig.frames(1)
		var tgt := stage.to_local((ik["tr"] as Node3D).global_position)
		gap = maxf(gap, hand[0].distance_to(tgt))
		lo = minf(lo, hand[0].y)
		hi_y = maxf(hi_y, hand[0].y)
		var ball := stage.ball_view.last_pos
		if ball.y > HubBallView.DRIBBLE_TOP - 0.02:
			top_gap = minf(top_gap, absf(hand[0].y - (ball.y + HubBall.R)))
	t.check(gap < 0.01, "the hand is where the dribble puts it (worst %.3f m)" % gap)
	t.check(hi_y - lo > 0.05, "the arm pumps the ball (the hand travels %.3f m)" % (hi_y - lo))
	t.check(top_gap < 0.03, "the palm meets the top of the ball (%.3f m)" % top_gap)
	# the shot: under the ball to the set point, then the follow-through
	var rc := HubBall.rim_center()
	var face := atan2(HubBall.HOOP_DIR.x, HubBall.HOOP_DIR.y)
	l.hub._pos = Vector2(rc.x, rc.z) + HubBall.HOOP_DIR * 1.6
	l.hub._yaw = face
	await rig.frames(30)
	b.force_make = 1
	l.hub.interact()
	var under := INF
	var set_reached := false
	while b.phase == BallSync.Phase.SHOT:
		await rig.frames(1)
		var ball2 := stage.ball_view.last_pos
		if b.phase_t > BallSync.WINDUP_SHOT * 0.6:
			under = minf(under, ball2.y - hand[0].y)
			set_reached = set_reached or ball2.y > 1.0
	t.check(set_reached, "the ball goes up to the set point")
	t.check(under > 0.0 and under < 0.15, "the shooting hand is under the ball (%.3f m below it)" % under)
	await rig.frames(8)
	t.check(b.released_shot and hand[0].y > 1.0, "follow-through: the arm stays up after the release (hand at %.2f m)" % hand[0].y)
	l.queue_free()
	stage.queue_free()
	App.stage = saved_stage
	App.session = saved_session
	rig.teardown()
	await t.get_tree().process_frame
