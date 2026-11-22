extends RefCounted
## (build 25) The basketball as drawn, frame by frame, on the real stage and
## lobby screen: picking it up, dribbling standing and walking and turning,
## the shot's windup, its release, its flight and its drop through the net
## never jump (each frame the ball moves no further than its own speed
## allows); a basket puts no words on screen (confetti only).
## (build 30) The body handles the bigger ball: measured on the skeleton as
## it is posed (BallBodyProbe, inside Skeleton3D.skeleton_updated), in every
## frame of the standing and walking dribble, of each dribble move and of
## the whole shot the ball is clear of the head, the torso, the hips, both
## legs and both arms, and a palm the pose has on the ball is on its
## surface; a moderate turn crosses the ball over, a sharp one (and a stop)
## puts it between the legs, a reversal goes behind the back, each to the
## other hand.
var t


func _setup() -> Dictionary:
	# (a first run's Wardrobe, open behind the tests, turns the local runner
	# to the camera every frame: pause it while the runner walks)
	var paused: Array = []
	for n in t.get_tree().root.find_children("*", "CreatorScreen", true, false):
		paused.append([n, n.process_mode])
		n.process_mode = Node.PROCESS_MODE_DISABLED
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(20, 0, 0.0, 0)
	await rig.wait_until(func() -> bool: return rig.host.social.ball.spawned, 300)
	var stage := DormStage.new()
	t.add_child(stage)
	var saved := [App.stage, App.session]
	App.stage = stage
	App.session = rig.host
	stage.set_mode("lobby", false)
	var l := LobbyScreen.new()
	l.session = rig.host
	t.add_child(l)
	await rig.frames(10)
	l._set_walk(true)
	await rig.frames(10)
	return {"rig": rig, "stage": stage, "l": l, "saved": saved, "b": rig.host.social.ball, "paused": paused}


func _teardown(e: Dictionary) -> void:
	(e["l"] as Node).queue_free()
	(e["stage"] as Node).queue_free()
	App.stage = e["saved"][0]
	App.session = e["saved"][1]
	(e["rig"] as NetRig).teardown()
	for pn in e["paused"]:
		if is_instance_valid(pn[0]):
			(pn[0] as Node).process_mode = pn[1]
	await t.get_tree().process_frame


## Stand somewhere open, facing `dir` (world x, z), the stick let go.
func _place(l: LobbyScreen, at: Vector2, dir: Vector2) -> void:
	l.hub.stick = Vector2.ZERO
	l.hub._vel = Vector2.ZERO
	l.hub._pos = at
	l.hub._yaw = atan2(-dir.x, -dir.y)


## The stick for walking along `dir` (world x, z).
static func _stick(dir: Vector2) -> Vector2:
	var d := dir.normalized()
	return Vector2(d.x, -d.y)


func test_the_ball_moves_smoothly_from_pick_up_to_the_basket() -> void:
	var e: Dictionary = await _setup()
	var rig: NetRig = e["rig"]
	var l: LobbyScreen = e["l"]
	var stage: DormStage = e["stage"]
	var b: BallSync = e["b"]
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
			var d := (last[0] as Vector3).distance_to(view.last_pos)
			last[0] = view.last_pos
			worst[label] = maxf(float(worst.get(label, 0.0)), d)
	# pick it up
	l.hub.interact()
	await track.call("pick up", 30)
	t.eq(b.holder, rig.host.local_slot, "picked up")
	# dribble standing, then walking with turns (moves among them)
	await track.call("dribble", 60)
	_place(l, Vector2(-0.6, 0.4), Vector2(1, 0))
	await rig.frames(20)
	last[0] = view.last_pos
	for dir in [Vector2(1, 0), Vector2(0.6, 1), Vector2(-1, 0.3), Vector2(1, -0.2), Vector2(0.6, -1)]:
		l.hub.stick = _stick(dir)
		await track.call("walk and turn", 28)
	l.hub.stick = Vector2.ZERO
	await track.call("stop", 40)
	# to the shooting spot (a teleport for the test; then settle)
	var rc := HubBall.rim_center()
	_place(l, Vector2(rc.x, rc.z) + HubBall.HOOP_DIR * 1.6, -HubBall.HOOP_DIR)
	await rig.frames(40)
	last[0] = view.last_pos
	b.force_make = 1
	l.hub.interact()
	await track.call("windup", 36)
	await track.call("release and flight", 60)
	await track.call("through the net", 60)
	# a frame at 60 Hz: the dribble bounces at most ~3 m/s off the floor; a
	# move carries it across at up to ~5 m/s and walking (and turning) adds
	# the runner's 2.4 m/s; a shot flies at up to ~8 m/s (0.14 m)
	var caps := {"pick up": 0.09, "dribble": 0.06, "walk and turn": 0.125, "stop": 0.11,
		"windup": 0.08, "release and flight": 0.14, "through the net": 0.14}
	for k in worst:
		var cap := float(caps[k])
		t.check(float(worst[k]) <= cap, "%s: smooth (largest step %.3f m a frame, at most %.3f)" % [k, float(worst[k]), cap])
	t.check(b.make_seq >= 1, "the shot went in")
	t.eq(said.size(), 0, "no words on a basket (no Swish!, no Nice shot!): %s" % [said])
	t.check(view.confetti_bursts >= 1, "the confetti says it")
	await _teardown(e)


## Walks along `a` until moving, then turns to `b` and keeps walking until a
## move is done (or `n` frames); returns the move done ([] none).
func _turn_for_move(rig: NetRig, l: LobbyScreen, view: HubBallView, a: Vector2, bdir: Vector2, n: int, probe: BallBodyProbe, label: String) -> Array:
	probe.label = label + " (approach)"
	l.hub.stick = _stick(a)
	# (setting off is a move of its own: let it finish first, walking on)
	var quiet := 0
	for i in 160:
		await rig.frames(1)
		quiet = quiet + 1 if view.moves.move == "" and view.moves._pending == "" and i > 20 else 0
		if quiet >= 18:
			break
	var before := view.moves.moves_done.size()
	probe.label = label
	l.hub.stick = _stick(bdir) if bdir != Vector2.ZERO else Vector2.ZERO
	for i in n:
		await rig.frames(1)
		if view.moves.moves_done.size() > before and view.moves.move == "":
			break
	l.hub.stick = Vector2.ZERO
	probe.label = label + " (after)"
	await rig.frames(24)
	return view.moves.moves_done[before] if view.moves.moves_done.size() > before else []


func test_the_body_handles_the_ball() -> void:
	var e: Dictionary = await _setup()
	var rig: NetRig = e["rig"]
	var l: LobbyScreen = e["l"]
	var stage: DormStage = e["stage"]
	var b: BallSync = e["b"]
	var view := stage.ball_view
	_place(l, Vector2(-0.6, 0.3), Vector2(1, 0))
	await rig.frames(5)
	b.sim.place(Vector3(l.hub._pos.x + 0.4, HubBall.R, l.hub._pos.y))
	await rig.frames(5)
	l.hub.interact()
	await rig.frames(40)
	t.eq(b.holder, rig.host.local_slot, "picked up")
	var v: CharacterView = stage.chars[l.hub.local_key()]
	var rg: BallRig = view._rigs.get(l.hub.local_key())
	t.check(rg != null and rg.get_parent() == v.skeleton, "the holder's body has its rig")
	var probe := BallBodyProbe.new(view, v)
	# --- standing: the palm on top, the arm pumping it
	var hand_y := [INF, -INF]
	probe.label = "standing dribble"
	for i in 90:
		await rig.frames(1)
		hand_y[0] = minf(float(hand_y[0]), (probe.last_palm[1] as Vector3).y)
		hand_y[1] = maxf(float(hand_y[1]), (probe.last_palm[1] as Vector3).y)
	t.check(float(hand_y[1]) - float(hand_y[0]) > 0.06, "the arm pumps the ball (the palm travels %.3f m)" % (float(hand_y[1]) - float(hand_y[0])))
	t.check(int(probe.contact_frames.get("standing dribble", 0)) > 25, "the palm is on the ball for part of every bounce")
	# --- walking
	probe.label = "walking dribble"
	l.hub.stick = _stick(Vector2(1, 0.1))
	await rig.frames(50)
	l.hub.stick = Vector2.ZERO
	probe.label = "stop"
	await rig.frames(40)
	# --- each move on its input
	_place(l, Vector2(-3.6, 0.2), Vector2(1, 0))
	await rig.frames(30)
	var m1: Array = await _turn_for_move(rig, l, view, Vector2(1, 0), Vector2(1, -1.0), 70, probe, "crossover")
	t.check(m1.size() == 3 and String(m1[0]) == "cross", "a moderate turn crosses it over (%s)" % [m1])
	t.check(m1.size() == 3 and int(m1[1]) == -int(m1[2]), "to the other hand")
	_place(l, Vector2(-3.6, -0.6), Vector2(1, 0))
	await rig.frames(30)
	var m2: Array = await _turn_for_move(rig, l, view, Vector2(1, 0), Vector2(0, 1), 70, probe, "between the legs")
	t.check(m2.size() == 3 and String(m2[0]) == "legs", "a sharp turn goes between the legs (%s)" % [m2])
	t.check(m2.size() == 3 and int(m2[1]) == -int(m2[2]), "to the other hand")
	_place(l, Vector2(-3.6, 0.0), Vector2(1, 0))
	await rig.frames(30)
	var m3: Array = await _turn_for_move(rig, l, view, Vector2(1, 0), Vector2(-1, 0), 80, probe, "behind the back")
	t.check(m3.size() == 3 and String(m3[0]) == "back", "a reversal goes behind the back (%s)" % [m3])
	t.check(m3.size() == 3 and int(m3[1]) == -int(m3[2]), "to the other hand")
	_place(l, Vector2(-3.6, 0.0), Vector2(1, 0))
	await rig.frames(30)
	var m4: Array = await _turn_for_move(rig, l, view, Vector2(1, 0), Vector2.ZERO, 70, probe, "stop move")
	t.check(m4.size() == 3 and String(m4[0]) == "legs", "a stop goes between the legs (%s)" % [m4])
	var hands := {}
	for m in view.moves.moves_done:
		hands[int(m[2])] = true
	t.check(hands.size() == 2, "both hands dribble")
	# --- the shot: gather, dip, rise, set, release, the follow-through
	var rc := HubBall.rim_center()
	_place(l, Vector2(rc.x, rc.z) + HubBall.HOOP_DIR * 1.6, -HubBall.HOOP_DIR)
	probe.label = ""
	await rig.frames(40)
	b.force_make = 1
	probe.label = "shot"
	l.hub.interact()
	var under := INF
	var crouch := 0.0
	var top := 0.0
	while b.phase == BallSync.Phase.SHOT:
		await rig.frames(1)
		crouch = maxf(crouch, float(view.pose.get("crouch", 0.0)))
		var ball := view.last_pos
		top = maxf(top, ball.y)
		if b.phase_t > BallSync.WINDUP_SHOT * (BallMoves.T_RISE + 0.02):
			under = minf(under, ball.y - (probe.last_palm[1] as Vector3).y)
	t.check(crouch > 0.1, "the knees bend in the dip (%.2f m)" % crouch)
	t.check(top > 1.0, "the ball goes up to the release (%.2f m)" % top)
	t.check(under > 0.03, "the shooting hand is under the ball (%.3f m below its centre)" % under)
	probe.label = "follow"
	await rig.frames(10)
	t.check(b.released_shot and (probe.last_palm[1] as Vector3).y > 0.95, "follow-through: the arm stays up (palm at %.2f m)" % (probe.last_palm[1] as Vector3).y)
	var made0 := b.make_seq
	await rig.wait_until(func() -> bool: return b.make_seq != made0 or b.make_seq >= 1, 120)
	t.check(b.make_seq >= 1, "the shot goes in (force_make)")
	probe.stop()
	print(probe.report())
	for f in probe.fails:
		t.check(false, f)
	for l2 in ["standing dribble", "walking dribble", "crossover", "between the legs", "behind the back", "shot"]:
		t.check(int(probe.frames.get(l2, 0)) > 10, "%s measured (%d frames)" % [l2, int(probe.frames.get(l2, 0))])
	t.eq(probe.fails.size(), 0, "the ball never goes into the body, and a hand on it is on its surface")
	await _teardown(e)
