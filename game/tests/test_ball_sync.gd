extends RefCounted
## (build 24) The party room's basketball across the party (BallSync): the
## host starts it somewhere open and everyone sees it there; only someone
## walking around and close to it can pick it up; the holder shoots (a make
## rains confetti on every device), drops it, or passes it to a friend who
## is walking around (only in a party with other people); stopping walking
## drops it; guests see the same flight; a round start puts it away.
var t


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
		return rig.host.human_count() == rig.clients.size() + 1 and rig.host.social.ball.spawned, 300)
	await rig.frames(6)


func _done(rig: NetRig) -> void:
	rig.teardown()
	await t.get_tree().process_frame
	await t.get_tree().process_frame


## Walk a session's runner to `p` (off the mark: a walk pose anywhere).
func _walk_to(rig: NetRig, s: NetSession, p: Vector2, yaw: float = 0.0) -> void:
	s.social.hub.set_local(HubSync.MODE_MARK, p, yaw, 0.0)
	await rig.frames(4)
	s.social.hub.set_local(HubSync.MODE_WALK, p, yaw, 0.0)
	await rig.frames(10)


const SPOT := Vector2(2.6, -0.2)    # open floor in front of the hoop


static func _yaw_to(from: Vector2, to: Vector2) -> float:
	var d := to - from
	return atan2(-d.x, -d.y)


func test_everyone_sees_the_ball_where_the_host_put_it() -> void:
	var rig := _rig(2)
	await _ready_party(rig)
	var hb := rig.host.social.ball
	t.check(hb.spawned, "the host has started the ball")
	var at := hb.sim.pos
	t.check(HubRoom.is_free(Vector2(at.x, at.z)) and at.y <= HubBall.R + 0.01, "on open floor (%s)" % at)
	await rig.frames(80)   # (resting: repeated once a second)
	for c in rig.clients:
		var cb: BallSync = c.social.ball
		t.check(cb.spawned, "a guest has it")
		t.check(cb.sim.pos.distance_to(hb.sim.pos) < 0.01, "in the same place (%s / %s)" % [cb.sim.pos, hb.sim.pos])
	await _done(rig)


func test_pick_up_only_when_close_and_walking() -> void:
	var rig := _rig(1)
	await _ready_party(rig)
	var c0: NetSession = rig.clients[0]
	var hb := rig.host.social.ball
	hb.sim.place(Vector3(SPOT.x, HubBall.R, SPOT.y))
	await rig.frames(70)
	# on the mark: no
	c0.social.ball.request(BallSync.ACT_PICKUP)
	await rig.frames(10)
	t.eq(hb.holder, -1, "nobody picks it up from their mark")
	# walking, across the room: no
	await _walk_to(rig, c0, Vector2(-1.5, 1.5))
	t.check(not c0.social.ball.can_pickup(c0.social.hub.local_pos), "the button isn't offered from across the room")
	c0.social.ball.request(BallSync.ACT_PICKUP)
	await rig.frames(10)
	t.eq(hb.holder, -1, "nor taken from across the room")
	# next to it: yes, and everyone knows who has it
	await _walk_to(rig, c0, SPOT + Vector2(-0.5, 0.1))
	t.check(c0.social.ball.can_pickup(c0.social.hub.local_pos), "Pick up is offered next to it")
	c0.social.ball.request(BallSync.ACT_PICKUP)
	await rig.frames(10)
	t.eq(hb.holder, c0.local_slot, "the guest has it")
	t.eq(c0.social.ball.holder, c0.local_slot, "and their device knows")
	t.check(c0.social.ball.local_has(), "local_has()")
	t.eq(hb.phase, BallSync.Phase.HELD, "dribbling")
	# the host can't take it out of their hands
	await _walk_to(rig, rig.host, SPOT + Vector2(-0.4, 0.3))
	hb.request(BallSync.ACT_PICKUP)
	await rig.frames(6)
	t.eq(hb.holder, c0.local_slot, "nobody takes it out of your hands")
	# stop walking: it's dropped where you were
	c0.social.hub.set_local(HubSync.MODE_MARK, c0.social.hub.local_pos, 0.0, 0.0)
	await rig.frames(10)
	t.eq(hb.holder, -1, "back to the mark: the ball is dropped")
	t.eq(hb.phase, BallSync.Phase.FREE, "loose")
	await rig.frames(240)
	t.check(hb.sim.sleeping and HubBall.reachable(hb.sim.pos), "it bounces and settles where it can be picked up (%s)" % hb.sim.pos)
	await _done(rig)


func test_shoot_make_confetti_everywhere_and_miss() -> void:
	var rig := _rig(1)
	await _ready_party(rig)
	var c0: NetSession = rig.clients[0]
	var hb := rig.host.social.ball
	var rc := HubBall.rim_center()
	var shoot_from := Vector2(rc.x, rc.z) + HubBall.HOOP_DIR * 1.6
	var face := _yaw_to(shoot_from, Vector2(rc.x, rc.z))   # (build 25) facing the hoop
	hb.sim.place(Vector3(shoot_from.x, HubBall.R, shoot_from.y + 0.4))
	await _walk_to(rig, c0, shoot_from, face)
	c0.social.ball.request(BallSync.ACT_PICKUP)
	await rig.frames(10)
	t.eq(hb.holder, c0.local_slot, "picked up")
	var made_host := [0]
	var made_guest := [0, -9, false]
	hb.made.connect(func(_s: int, _w: bool) -> void: made_host[0] += 1)
	c0.social.ball.made.connect(func(s: int, w: bool) -> void:
		made_guest[0] += 1
		made_guest[1] = s
		made_guest[2] = w)
	hb.force_make = 1
	c0.social.ball.request(BallSync.ACT_SHOOT)
	await rig.frames(4)
	t.eq(hb.phase, BallSync.Phase.SHOT, "winding up")
	await rig.wait_until(func() -> bool: return made_host[0] > 0, 240)
	t.eq(made_host[0], 1, "it goes in (host)")
	await rig.frames(20)
	t.eq(made_guest[0], 1, "the guest's device celebrates too")
	t.eq(made_guest[1], c0.local_slot, "for the guest's shot")
	t.eq(hb.holder, -1, "the ball is loose after the shot")
	# it drops through the net and comes to rest somewhere reachable
	await rig.frames(360)
	t.check(HubBall.reachable(hb.sim.pos), "back on the floor in reach (%s)" % hb.sim.pos)
	# a miss: no confetti
	await _walk_to(rig, c0, Vector2(hb.sim.pos.x, hb.sim.pos.z) + Vector2(-0.4, 0.2))
	c0.social.ball.request(BallSync.ACT_PICKUP)
	await rig.frames(12)
	t.eq(hb.holder, c0.local_slot, "picked up again")
	await _walk_to(rig, c0, shoot_from, face)
	hb.force_make = 0
	var before: int = made_host[0]
	c0.social.ball.request(BallSync.ACT_SHOOT)
	await rig.frames(240)
	t.check(made_host[0] - before <= 1, "a miss (it may still rattle in, rarely)")
	await _done(rig)


func test_guest_sees_the_same_flight() -> void:
	var rig := _rig(1)
	await _ready_party(rig)
	var c0: NetSession = rig.clients[0]
	var hb := rig.host.social.ball
	var cb: BallSync = c0.social.ball
	hb.sim.launch(Vector3(0.0, 1.4, 1.5), Vector3(1.2, 3.0, -1.4))
	hb._dirty = true
	# (from when the throw reaches the guest)
	await rig.wait_until(func() -> bool: return not cb.sim.sleeping, 30)
	var worst := 0.0
	for i in 150:
		await rig.frames(1)
		if cb.phase == BallSync.Phase.FREE:
			worst = maxf(worst, (cb.sim.pos + cb.err).distance_to(hb.sim.pos))
	# (the guest is one-way latency behind: 20 ms at up to ~5 m/s)
	t.check(worst < 0.3, "the guest's ball follows the host's (worst %.2f m apart)" % worst)
	t.check(cb.sim.pos.distance_to(hb.sim.pos) < 0.05, "and ends in the same place")
	await _done(rig)


func test_pass_only_in_a_party_to_someone_walking() -> void:
	# alone: no Pass
	var solo := _rig(0)
	await _ready_party(solo)
	var sb := solo.host.social.ball
	t.check(not sb.party_has_others(), "alone in your party")
	sb.sim.place(Vector3(SPOT.x, HubBall.R, SPOT.y))
	await _walk_to(solo, solo.host, SPOT + Vector2(-0.4, 0.0))
	sb.request(BallSync.ACT_PICKUP)
	await solo.frames(4)
	t.eq(sb.holder, solo.host.local_slot, "the host picks it up")
	sb.request(BallSync.ACT_PASS)
	await solo.frames(30)
	t.eq(sb.holder, solo.host.local_slot, "no pass with nobody to pass to")
	t.eq(sb.phase, BallSync.Phase.HELD, "still dribbling")
	await _done(solo)
	# in a party: a pass to a friend walking around, who catches it
	var rig := _rig(2)
	await _ready_party(rig)
	var c0: NetSession = rig.clients[0]
	var c1: NetSession = rig.clients[1]
	var hb := rig.host.social.ball
	hb.sim.place(Vector3(SPOT.x, HubBall.R, SPOT.y))
	await _walk_to(rig, c0, SPOT + Vector2(-0.4, 0.0))
	c0.social.ball.request(BallSync.ACT_PICKUP)
	await rig.frames(10)
	t.eq(hb.holder, c0.local_slot, "the guest has it")
	# nobody else walking: the host won't pass it to someone on their mark
	t.check(not c0.social.ball.others_walking(), "nobody else is walking")
	c0.social.ball.request(BallSync.ACT_PASS)
	await rig.frames(30)
	t.eq(hb.holder, c0.local_slot, "no pass to someone on their mark")
	await _walk_to(rig, c1, SPOT + Vector2(-2.6, 1.2))
	await rig.frames(10)
	t.check(c0.social.ball.others_walking(), "a friend is walking around")
	var caught := [false]
	hb.changed.connect(func() -> void:
		if hb.holder == c1.local_slot:
			caught[0] = true)
	c0.social.ball.request(BallSync.ACT_PASS, c1.local_slot)
	await rig.wait_until(func() -> bool: return caught[0], 180)
	t.check(caught[0], "the friend catches the pass")
	await rig.frames(10)
	t.eq(c1.social.ball.holder, c1.local_slot, "and their device knows it's theirs")
	await _done(rig)


func test_round_start_puts_it_away_and_it_comes_back_somewhere_new() -> void:
	var rig := _rig(1)
	await _ready_party(rig)
	var hb := rig.host.social.ball
	var seen := {}
	for i in 6:
		var p := hb.sim.pos
		seen["%.1f,%.1f" % [p.x, p.z]] = true
		hb.clear()
		t.check(not hb.spawned, "put away")
		await rig.frames(3)
		t.check(hb.spawned, "back when the room is")
	t.check(seen.size() >= 4, "somewhere different each time (%d places of 6)" % seen.size())
	await _done(rig)


func test_bad_requests_are_ignored() -> void:
	var rig := _rig(1)
	await _ready_party(rig)
	var c0: NetSession = rig.clients[0]
	var hb := rig.host.social.ball
	hb.sim.place(Vector3(SPOT.x, HubBall.R, SPOT.y))
	await _walk_to(rig, c0, SPOT + Vector2(-0.4, 0.0))
	var denied := hb.stat_denied
	# shooting, dropping, passing a ball you don't have; nonsense acts
	for act in [BallSync.ACT_SHOOT, BallSync.ACT_DROP, BallSync.ACT_PASS, 0, 99]:
		c0.social.ball.request(act)
		await rig.frames(4)
	t.eq(hb.holder, -1, "nothing happens")
	t.check(hb.stat_denied - denied >= 5, "each one refused")
	# a truncated packet
	var b := Protocol.buf_for(SocialProto.BALL_REQ)
	c0.transport.send(c0.host_peer, b.data_array, true)
	await rig.frames(4)
	t.eq(hb.holder, -1, "a broken request is ignored")
	await _done(rig)


func test_a_shot_goes_the_way_you_face() -> void:
	var rc := HubBall.rim_center()
	var rim := Vector2(rc.x, rc.z)
	var at := rim + HubBall.HOOP_DIR * 2.2
	var on := _yaw_to(at, rim)
	# the line a shot takes
	var l0 := BallSync.shot_line(at, on)
	t.check(bool(l0["rim"]), "facing the hoop: lined up on the rim")
	var l1 := BallSync.shot_line(at, on + deg_to_rad(10.0))
	t.check(bool(l1["rim"]) and (l1["dir"] as Vector2).distance_to((rim - at).normalized()) < 0.001, "10 degrees off: still lined up (aim assist)")
	var l2 := BallSync.shot_line(at, on + deg_to_rad(30.0))
	t.check(not bool(l2["rim"]), "30 degrees off: not at the hoop")
	t.check((l2["dir"] as Vector2).distance_to(Vector2(-sin(on + deg_to_rad(30.0)), -cos(on + deg_to_rad(30.0)))) < 0.001, "it goes the way you face")
	# in the room: facing away from the hoop, the shot flies that way
	var rig := _rig(1)
	await _ready_party(rig)
	var c0: NetSession = rig.clients[0]
	var hb := rig.host.social.ball
	var from := Vector2(1.6, 0.6)
	hb.sim.place(Vector3(from.x + 0.3, HubBall.R, from.y))
	await _walk_to(rig, c0, from)
	c0.social.ball.request(BallSync.ACT_PICKUP)
	await rig.frames(10)
	t.eq(hb.holder, c0.local_slot, "picked up")
	var away := _yaw_to(from, rim) + PI * 0.6   # well off to the side, away from the hoop
	var made := [0]
	hb.made.connect(func(_s: int, _w: bool) -> void: made[0] += 1)
	hb.force_make = 1   # (would be a make if it were at the hoop)
	c0.social.ball.request(BallSync.ACT_SHOOT, -1, away)
	await rig.wait_until(func() -> bool: return hb.phase == BallSync.Phase.FREE, 120)
	var start := Vector2(hb.sim.pos.x, hb.sim.pos.z)
	var f := Vector2(-sin(away), -cos(away))
	var vh := Vector2(hb.sim.vel.x, hb.sim.vel.z)
	t.check(vh.normalized().dot(f) > 0.99, "the shot flies the way they faced (%.3f)" % vh.normalized().dot(f))
	await rig.frames(60)
	var now := Vector2(hb.sim.pos.x, hb.sim.pos.z)
	t.check((now - start).dot(f) > 0.8, "and goes off that way (%.2f m)" % (now - start).dot(f))
	await rig.frames(240)
	t.eq(made[0], 0, "no basket facing away from the hoop")
	await _done(rig)
