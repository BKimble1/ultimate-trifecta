extends RefCounted
## (build 33) The dunk and the block as drawn, on the real stage and lobby
## screen, measured on the skeleton as it is posed (BallBodyProbe): the
## button says Dunk in range; the dunker's head, body and legs never touch
## the rim (as it bends under them) or the backboard, the ball in their
## hands never passes through the rim or their body, the hands are on the
## rim while they hang, the arms never pass through their own big head, the
## jump really is one; the rim bends and springs back; the same on a
## guest's screen, 60 ms away; a blocker's jump with an arm up never puts
## the arm through their head, they lunge at the shooter, and the swat
## shows (a burst, a slap).
var t


func _setup(n_clients: int = 0, latency: float = 20.0, jitter: float = 0.0, viewer: int = -1) -> Dictionary:
	var paused: Array = []
	for nd in t.get_tree().root.find_children("*", "CreatorScreen", true, false):
		paused.append([nd, nd.process_mode])
		nd.process_mode = Node.PROCESS_MODE_DISABLED
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(latency, jitter, 0.0, n_clients)
	await rig.wait_until(func() -> bool:
		for c in rig.clients:
			if c.local_slot < 0:
				return false
		return rig.host.human_count() == n_clients + 1 and rig.host.social.ball.spawned, 400)
	var me: NetSession = rig.host if viewer < 0 else rig.clients[viewer]
	var stage := DormStage.new()
	t.add_child(stage)
	var saved := [App.stage, App.session, Save.data["uid"]]
	App.stage = stage
	App.session = me
	Save.data["uid"] = "uid-host" if viewer < 0 else "uid-c%d" % viewer
	stage.set_mode("lobby", false)
	var l := LobbyScreen.new()
	l.session = me
	t.add_child(l)
	await rig.frames(12)
	l._set_walk(true)
	await rig.frames(10)
	return {"rig": rig, "stage": stage, "l": l, "saved": saved, "b": me.social.ball, "hb": rig.host.social.ball, "paused": paused, "me": me}


func _teardown(e: Dictionary) -> void:
	(e["l"] as Node).queue_free()
	(e["stage"] as Node).queue_free()
	App.stage = e["saved"][0]
	App.session = e["saved"][1]
	Save.data["uid"] = e["saved"][2]
	(e["rig"] as NetRig).teardown()
	for pn in e["paused"]:
		if is_instance_valid(pn[0]):
			(pn[0] as Node).process_mode = pn[1]
	await t.get_tree().process_frame
	await t.get_tree().process_frame


static func _rim() -> Vector2:
	var rc := HubBall.rim_center()
	return Vector2(rc.x, rc.z)


static func _spot(d: float, a: float = 0.0) -> Vector2:
	return _rim() + HubBall.HOOP_DIR.rotated(a) * d


static func _yaw_to(from: Vector2, to: Vector2) -> float:
	var d := to - from
	return atan2(-d.x, -d.y)


func _place(l: LobbyScreen, at: Vector2, yaw: float) -> void:
	l.hub.stick = Vector2.ZERO
	l.hub._vel = Vector2.ZERO
	l.hub._pos = at
	l.hub._yaw = yaw


## The local runner picks the ball up at `at`.
func _pick_up(e: Dictionary, at: Vector2) -> void:
	var l: LobbyScreen = e["l"]
	var rig: NetRig = e["rig"]
	var hb: BallSync = e["hb"]
	_place(l, at, 0.0)
	await rig.frames(8)
	hb.sim.place(Vector3(at.x + 0.4, HubBall.R, at.y))
	hb._dirty = true
	await rig.frames(14)
	l.hub.interact()
	await rig.wait_until(func() -> bool: return (e["b"] as BallSync).local_has(), 60)
	await rig.frames(30)


func test_dunk_button_body_and_rim() -> void:
	var e: Dictionary = await _setup()
	var rig: NetRig = e["rig"]
	var l: LobbyScreen = e["l"]
	var stage: DormStage = e["stage"]
	var b: BallSync = e["b"]
	var view := stage.ball_view
	await _pick_up(e, Vector2(1.6, 0.6))
	t.check(b.local_has(), "picked up")
	# out of range: Shoot; in range: Dunk (the same button)
	var far := _spot(2.6)
	_place(l, far, _yaw_to(far, _rim()))
	await rig.frames(8)
	t.eq(String(l.hub.prompt()["text"]), "Shoot", "2.6 m out: Shoot")
	t.eq(UIKit.face_of(l.act_btn).caption, "Shoot", "(the button)")
	var v: CharacterView = stage.chars[l.hub.local_key()]
	var probe := BallBodyProbe.new(view, v)
	probe.rim = true
	probe.arms_head = true
	probe.any_pose = true
	var steps := {}
	var runs := [[1.3, 0.0], [1.05, 0.8], [1.4, -0.6]]
	for r in runs:
		var from := _spot(float(r[0]), float(r[1]))
		_place(l, from, _yaw_to(from, _rim()))
		probe.label = ""
		await rig.frames(30)
		var pr := l.hub.prompt()
		t.eq(String(pr["text"]), "Dunk", "%.1f m out: Dunk" % float(r[0]))
		t.eq(String(pr["icon"]), "dunk", "with its own icon")
		t.eq(UIKit.face_of(l.act_btn).caption, "Dunk", "(the button)")
		var tag := "dunk %.1f m %.1f rad" % [float(r[0]), float(r[1])]
		var made0 := b.make_seq
		var bend := 0.0
		var worst_step := 0.0
		var last := view.last_pos
		probe.label = tag + ": windup"
		l.hub.interact()
		await rig.wait_until(func() -> bool: return b.phase == BallSync.Phase.SHOT, 10)
		t.check(b.dunk, "%s: a dunk" % tag)
		var t0 := 0
		while t0 < 200:
			await rig.frames(1)
			t0 += 1
			if b.phase == BallSync.Phase.FREE:
				probe.label = tag + (": to the rim" if b.phase_t < 0.2 else (": hang" if b.phase_t < BallSync.DUNK_LET_GO else ": drop"))
			bend = maxf(bend, view.rim_bend)
			var st := view.last_pos.distance_to(last)
			if st > worst_step:
				worst_step = st
				steps[tag] = "%s at %.2f s (%s)" % [["free", "held", "shot", "pass"][b.phase], b.phase_t, view.last_pos]
			last = view.last_pos
			if b.phase == BallSync.Phase.FREE and b.phase_t > BallSync.DUNK_AFTER_S:
				break
		probe.label = ""
		t.check(b.make_seq != made0, "%s: it goes in" % tag)
		var top := float(probe.top_hips.get(tag + ": windup", 0.0))
		t.check(top > 0.51 + 0.85, "%s: a real jump (the hips %.2f m up)" % [tag, top])
		t.check(bend > 0.07, "%s: the rim bends under them (%.3f rad)" % [tag, bend])
		t.check(worst_step < 0.16, "%s: the ball never jumps (%.3f m a frame: %s)" % [tag, worst_step, steps.get(tag, "")])
		var lp := l.hub._pos
		t.check(absf((lp - _rim()).length() - BallSync.DUNK_LAND_D) < 0.1, "%s: they land in front of the rim (%.2f m)" % [tag, (lp - _rim()).length()])
		await rig.frames(70)
		t.check(absf(view.rim_bend) < 0.01, "%s: the rim springs back (%.3f)" % [tag, view.rim_bend])
		# the ball back for the next run
		await rig.wait_until(func() -> bool: return b.sim.sleeping or b.sim.pos.y < 0.3, 200)
		await _pick_up(e, Vector2(1.6, 0.6))
	probe.stop()
	print(probe.report())
	for f in probe.fails:
		t.check(false, f)
	t.eq(probe.fails.size(), 0, "nothing passes through anything")
	t.check(view.dunk_slams >= 3 and view.confetti_bursts >= 3, "a slam's clang and the confetti every time (%d, %d)" % [view.dunk_slams, view.confetti_bursts])
	await _teardown(e)


## The host dunks; a guest 60 ms away sees the same on their screen.
func test_dunk_looks_right_on_a_guest() -> void:
	var e: Dictionary = await _setup(1, 60.0, 12.0, 0)
	var rig: NetRig = e["rig"]
	var stage: DormStage = e["stage"]
	var gb: BallSync = e["b"]
	var hb: BallSync = e["hb"]
	var host := rig.host
	var view := stage.ball_view
	var from := _spot(1.3, 0.25)
	var face := _yaw_to(from, _rim())
	# the host walks over and picks it up (their own device drives their pose)
	host.social.hub.set_local(HubSync.MODE_MARK, from, face, 0.0)
	await rig.frames(4)
	host.social.hub.set_local(HubSync.MODE_WALK, from, face, 0.0)
	hb.sim.place(Vector3(from.x + 0.3, HubBall.R, from.y))
	hb._dirty = true
	await rig.frames(20)
	hb.request(BallSync.ACT_PICKUP)
	await rig.wait_until(func() -> bool: return gb.holder == host.local_slot, 60)
	await rig.frames(40)
	var hv: CharacterView = stage.chars["uid-host"]
	var probe := BallBodyProbe.new(view, hv)
	probe.rim = true
	probe.arms_head = true
	probe.any_pose = true
	probe.label = "guest's view: windup"
	hb.request(BallSync.ACT_SHOOT, BallSync.ARG_DUNK, face)
	var worst := 0.0
	var last := view.last_pos
	var off := 0.0
	var wat := ""
	for i in 150:
		# (the host's device walks its runner along the dunk, as HubWalk does)
		if hb.dunker() == host.local_slot:
			host.social.hub.set_local(HubSync.MODE_WALK, BallSync.dunk_body(hb.dunk_from, hb.dunk_clock()), BallSync.dunk_yaw(hb.dunk_from), 1.0)
		await rig.frames(1)
		if gb.phase == BallSync.Phase.FREE:
			probe.label = "guest's view: to the rim" if gb.phase_t < 0.2 else ("guest's view: hang" if gb.phase_t < BallSync.DUNK_LET_GO else "guest's view: drop")
		if gb.dunker() == host.local_slot:
			var want := BallSync.dunk_body(gb.dunk_from, gb.dunk_clock())
			off = maxf(off, Vector2(hv.position.x, hv.position.z).distance_to(want))
		var st := view.last_pos.distance_to(last)
		if st > worst:
			worst = st
			wat = "%s at %.2f s" % [["free", "held", "shot", "pass"][gb.phase], gb.phase_t]
		last = view.last_pos
	probe.stop()
	print(probe.report())
	t.check(gb.make_seq >= 1, "the guest sees it go in")
	t.check(view.dunk_slams >= 1, "with the slam's clang")
	t.check(off < 0.02, "the guest draws the dunker on the dunk's path (off by %.3f m)" % off)
	var top := float(probe.top_hips.get("guest's view: windup", 0.0))
	t.check(top > 1.36, "the jump (the hips %.2f m up)" % top)
	t.check(worst < 0.16, "the ball never jumps on the guest's screen (%.3f m a frame, %s)" % [worst, wat])
	for f in probe.fails:
		t.check(false, f)
	t.check(int(probe.frames.get("guest's view: windup", 0)) > 20 and int(probe.frames.get("guest's view: hang", 0)) > 10, "measured (%s)" % [probe.frames])
	await _teardown(e)


## The local runner blocks a guest's shot.
func test_block_jump_body_and_swat() -> void:
	var e: Dictionary = await _setup(1)
	var rig: NetRig = e["rig"]
	var l: LobbyScreen = e["l"]
	var stage: DormStage = e["stage"]
	var hb: BallSync = e["hb"]
	var c0: NetSession = rig.clients[0]
	var view := stage.ball_view
	var at := _spot(2.5, 0.15)
	var face := _yaw_to(at, _rim())
	c0.social.hub.set_local(HubSync.MODE_MARK, at, face, 0.0)
	await rig.frames(4)
	c0.social.hub.set_local(HubSync.MODE_WALK, at, face, 0.0)
	hb.sim.place(Vector3(at.x + 0.3, HubBall.R, at.y))
	hb._dirty = true
	await rig.frames(20)
	c0.social.ball.request(BallSync.ACT_PICKUP)
	await rig.wait_until(func() -> bool: return hb.holder == c0.local_slot, 60)
	await rig.frames(30)
	var bp := at + (_rim() - at).normalized().rotated(0.4) * 1.35
	_place(l, bp, _yaw_to(bp, at))
	await rig.frames(20)
	t.check(l.hub.prompt().is_empty() or String(l.hub.prompt().get("text", "")) != "Block", "no Block while they just dribble")
	var v: CharacterView = stage.chars[l.hub.local_key()]
	var probe := BallBodyProbe.new(view, v)
	probe.arms_head = true
	probe.any_pose = true
	hb.force_make = 1
	c0.social.ball.request(BallSync.ACT_SHOOT, -1, face)
	await rig.wait_until(func() -> bool: return hb.phase == BallSync.Phase.SHOT and hb.phase_t > 0.18, 60)
	await rig.frames(2)
	var pr := l.hub.prompt()
	t.eq(String(pr.get("text", "")), "Block", "Block is offered next to a shooter winding up")
	t.eq(String(pr.get("icon", "")), "swat", "with its own icon")
	t.eq(UIKit.face_of(l.act_btn).caption, "Block", "(the button)")
	probe.label = "block jump"
	var from := l.hub._pos
	l.hub.interact()
	await rig.frames(50)
	probe.stop()
	var top := float(probe.top_hips.get("block jump", 0.0))
	var hand_hi := float(probe.top_hand.get("block jump", 0.0))
	print(probe.report())
	t.eq(hb.stat_blocks, 1, "blocked")
	t.check(view.block_bursts >= 1, "a burst and a slap where the hand met the ball")
	t.check(top > 0.51 + 0.3, "a jump (the hips %.2f m up)" % top)
	t.check(hand_hi > 1.15, "an arm up (a hand %.2f m up)" % hand_hi)
	var moved := l.hub._pos.distance_to(from)
	t.check(moved > 0.25 and l.hub._pos.distance_to(at) < from.distance_to(at), "a lunge at the shooter (%.2f m)" % moved)
	t.check(l.hub._pos.distance_to(at) >= BallSync.BLOCK_STOP - 0.05, "stopping short of them (%.2f m)" % l.hub._pos.distance_to(at))
	for f in probe.fails:
		t.check(false, f)
	t.check(int(probe.frames.get("block jump", 0)) > 20, "measured (%d frames)" % int(probe.frames.get("block jump", 0)))
	await rig.frames(60)
	t.check(l.hub.walking and l.hub.prompt().is_empty() or String(l.hub.prompt().get("text", "")) != "Block", "Block goes away after")
	await _teardown(e)
