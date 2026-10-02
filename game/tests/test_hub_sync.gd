extends RefCounted
## V6 Walk around: party members see each other walk in the party room,
## through the real session code (loopback host + clients).  The host
## clamps every pose to the floor and to walking speed, ignores stale and
## out-of-order poses and poses from anyone without a seat, receivers never
## make an avatar for someone outside the roster, and a round start stops
## it all for everyone.
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
		return rig.host.human_count() == rig.clients.size() + 1, 300)
	await rig.frames(6)


func test_walkers_are_seen_by_everyone() -> void:
	var rig := _rig(2)
	await _ready_party(rig)
	var c0: NetSession = rig.clients[0]
	var c1: NetSession = rig.clients[1]
	var path := [Vector2(0.0, 1.0), Vector2(0.5, 1.2), Vector2(1.0, 1.4), Vector2(1.5, 1.6)]
	for p in path:
		c0.social.hub.set_local(HubSync.MODE_WALK, p, 0.5, 2.0)
		await rig.frames(8)
	await rig.frames(20)
	var hp: Dictionary = rig.host.social.hub.poses.get(c0.local_slot, {})
	t.check(not hp.is_empty() and int(hp["mode"]) == HubSync.MODE_WALK, "the host has the guest walking")
	t.check((hp["pos"] as Vector2).distance_to(path[-1]) < 0.05, "at the guest's position (%s)" % str(hp.get("pos")))
	var s: Dictionary = c1.social.hub.sample(c0.local_slot)
	t.check(not s.is_empty() and int(s["mode"]) == HubSync.MODE_WALK, "the other guest sees them walking")
	t.check((s["pos"] as Vector2).distance_to(path[-1]) < 0.3, "near where they are (%s)" % str(s.get("pos")))
	t.check(c1.social.hub.sample(c1.local_slot).is_empty(), "nobody gets a copy of themselves")
	# the host walks too
	rig.host.social.hub.set_local(HubSync.MODE_WALK, Vector2(-1.0, 0.5), 1.0, 1.5)
	await rig.frames(20)
	t.check((c0.social.hub.sample(0).get("pos", Vector2.INF) as Vector2).distance_to(Vector2(-1.0, 0.5)) < 0.05, "guests see the host walk")
	# back to the mark: everyone sees the switch
	c0.social.hub.set_local(HubSync.MODE_MARK, Vector2(1.5, 1.6), 0.5, 0.0)
	await rig.frames(20)
	t.eq(c1.social.hub.mode_of(c0.local_slot), HubSync.MODE_MARK, "back on the mark for everyone")
	rig.teardown()


func test_host_clamps_teleports_furniture_and_bounds() -> void:
	var rig := _rig(1)
	await _ready_party(rig)
	var c0: NetSession = rig.clients[0]
	var hub := rig.host.social.hub
	c0.social.hub.set_local(HubSync.MODE_WALK, Vector2(0.0, 1.0), 0.0, 2.0)
	await rig.frames(12)
	# a 4 m jump in one tenth of a second
	c0.social.hub.local_pos = Vector2(4.0, 1.0)
	c0.social.hub._send_pose(false)
	await rig.frames(6)
	var p: Vector2 = hub.poses[c0.local_slot]["pos"]
	t.check(p.distance_to(Vector2(0.0, 1.0)) < 1.6, "no teleport: the host moves them at most a plausible step (%s)" % str(p))
	t.check(hub.stat_clamped > 0, "and counts the correction")
	# inside the couch and outside the room
	t.check(HubRoom.is_free(HubRoom.resolve(Vector2(-3.6, -2.8))), "the couch pushes you out")
	t.check(not HubRoom.is_free(Vector2(-3.6, -2.8)), "(the couch is solid)")
	t.check(HubRoom.resolve(Vector2(30, 30)).distance_to(Vector2(HubRoom.BOUNDS.y, HubRoom.BOUNDS.w)) < 0.01, "nobody leaves the room")
	var through := HubRoom.step(Vector2(-3.6, -1.5), Vector2(0, -3.0))
	t.check(through.y > -2.2, "a fast step can't tunnel through the couch (%s)" % str(through))
	rig.teardown()


func test_stale_forged_and_strangers_are_ignored() -> void:
	var rig := _rig(1)
	await _ready_party(rig)
	var c0: NetSession = rig.clients[0]
	var hub := rig.host.social.hub
	c0.social.hub.set_local(HubSync.MODE_WALK, Vector2(1.0, 1.0), 0.0, 1.0)
	await rig.frames(12)
	var dropped := hub.stat_dropped
	# an old pose arriving late
	var b := Protocol.buf_for(SocialProto.HUB_POSE)
	HubSync._put_pose(b, (c0.social.hub._seq - 3) & 0xFFFF, HubSync.MODE_WALK, Vector2(-2, 0), 0.0, 1.0)
	rig.host._on_packet(_peer_of(rig, c0), b.data_array)
	t.eq(hub.stat_dropped, dropped + 1, "an out-of-order pose is ignored")
	t.check((hub.poses[c0.local_slot]["pos"] as Vector2).distance_to(Vector2(1.0, 1.0)) < 0.05, "the newer position stands")
	# from someone without a seat
	var b2 := Protocol.buf_for(SocialProto.HUB_POSE)
	HubSync._put_pose(b2, 1, HubSync.MODE_WALK, Vector2(0, 0), 0.0, 1.0)
	rig.host._on_packet(4242, b2.data_array)
	t.check(not hub.poses.has(-1) and hub.poses.size() == 1, "no pose for a stranger")
	# a host message about seats that are empty or bots: no avatars appear
	var st := Protocol.buf_for(SocialProto.HUB_STATE)
	st.put_u8(2)
	for slot in [5, 6]:
		st.put_u8(slot)
		HubSync._put_pose(st, 9, HubSync.MODE_WALK, Vector2(0, 0), 0.0, 1.0)
	c0._on_packet(c0.host_peer, st.data_array)
	t.check(c0.social.hub.sample(5).is_empty() and c0.social.hub.sample(6).is_empty(), "no avatar for anyone outside the party")
	# junk
	c0._on_packet(c0.host_peer, PackedByteArray([SocialProto.HUB_STATE, 200]))
	c0._on_packet(c0.host_peer, PackedByteArray([SocialProto.HUB_STATE, 1, 0, 1]))
	rig.host._on_packet(_peer_of(rig, c0), PackedByteArray([SocialProto.HUB_POSE, 1]))
	t.check(true, "malformed packets are ignored without errors")
	rig.teardown()


func _peer_of(rig: NetRig, c: NetSession) -> int:
	for peer in rig.host._peer_slot:
		if int(rig.host._peer_slot[peer]) == c.local_slot:
			return int(peer)
	return -1


func test_round_start_stops_walking_for_everyone() -> void:
	var rig := _rig(1)
	await _ready_party(rig)
	var c0: NetSession = rig.clients[0]
	c0.social.hub.set_local(HubSync.MODE_WALK, Vector2(1.0, 1.0), 0.0, 2.0)
	rig.host.social.hub.set_local(HubSync.MODE_WALK, Vector2(-1.0, 1.0), 0.0, 2.0)
	await rig.frames(15)
	t.check(not c0.social.hub.samples.is_empty(), "walking in the party room")
	c0.set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.can_start(), 200)
	rig.host.host_start_match(3)
	await rig.frames(4)
	t.check(rig.host.social.hub.poses.is_empty() and rig.host.social.hub.local_mode == HubSync.MODE_MARK, "the host drops every pose at the start")
	await rig.wait_until(func() -> bool: return c0.phase == TC.Phase.LOADING, 200)
	await rig.frames(4)
	t.check(c0.social.hub.samples.is_empty() and c0.social.hub.local_mode == HubSync.MODE_MARK, "so does every guest")
	# nothing more is sent during the round
	var b := Protocol.buf_for(SocialProto.HUB_STATE)
	b.put_u8(1)
	b.put_u8(0)
	HubSync._put_pose(b, 999, HubSync.MODE_WALK, Vector2(0, 0), 0.0, 1.0)
	c0._on_packet(c0.host_peer, b.data_array)
	t.check(c0.social.hub.samples.is_empty(), "and late poses are ignored once the round is on")
	rig.teardown()
