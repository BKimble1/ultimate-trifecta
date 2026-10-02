extends RefCounted
## Protocol 4 trust rules over the loopback rig: the client's bound host
## can't be replaced and nobody else can send host messages; admission
## credentials are verified, bound to the sender and not replayable, and the
## host uses the service-approved name; junk and floods are contained; the
## round waits for load acks; names from the network are sanitised.
var t


func _rig(n: int) -> NetRig:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(20, 0, 0.0, n)
	return rig


func _raw(rig: NetRig, from: LoopbackTransport, to_id: int, bytes: PackedByteArray) -> void:
	from.send(to_id, bytes, true)


func test_bound_host_cannot_be_replaced_and_others_cannot_speak_for_it() -> void:
	var rig := _rig(1)
	var c: NetSession = rig.clients[0]
	await rig.wait_until(func() -> bool: return c.local_slot >= 0, 300)
	var host_peer := c.host_peer
	# a rogue endpoint links to the client and claims to be the host
	var rogue := LoopbackTransport.new(rig.hub, false)
	rig.hub.link(rogue.id, rig.client_ts[0].id)
	var ann := Protocol.buf_for(Protocol.M.ANNOUNCE)
	ann.put_u8(1)
	Protocol.put_str(ann, "rogue")
	Protocol.put_str(ann, "TEST1")
	_raw(rig, rogue, rig.client_ts[0].id, ann.data_array)
	# and sends a fake lobby, a kick and a host-end
	var fake := rig.host._lobby_bytes()
	_raw(rig, rogue, rig.client_ts[0].id, fake)
	_raw(rig, rogue, rig.client_ts[0].id, Protocol.buf_for(Protocol.M.KICK).data_array)
	_raw(rig, rogue, rig.client_ts[0].id, Protocol.buf_for(Protocol.M.HOST_END).data_array)
	await rig.frames(30)
	t.eq(c.host_peer, host_peer, "an announcement never replaces the bound host")
	t.check(not rig.ended_reason.has(c), "a stranger's KICK / HOST_END is ignored")
	t.check(c.connected, "still in the room")
	rig.teardown()


func test_expected_host_identity_is_enforced() -> void:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(20, 0, 0.0, 0)
	var c := rig.add_client("uid-x", "Xavier", "any")
	c.expected_host_uid = "gc-someone-else"   # the service named a different host
	await rig.frames(60)
	t.eq(c.host_peer, -1, "the client does not bind to a host the service didn't name")
	t.eq(c.local_slot, -1, "and never joins it")
	rig.teardown()


func _key_pair() -> Array:
	var crypto := Crypto.new()
	var k := crypto.generate_rsa(2048)
	var pub := CryptoKey.new()
	pub.load_from_string(k.save_to_string(true), true)
	return [k, pub]


static func _b64url(raw: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(raw).replace("+", "-").replace("/", "_").replace("=", "")


static func _token(priv: CryptoKey, claims: Dictionary) -> String:
	var h := _b64url(JSON.stringify({"alg": "RS256", "typ": "JWT"}).to_utf8_buffer())
	var p := _b64url(JSON.stringify(claims).to_utf8_buffer())
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update((h + "." + p).to_utf8_buffer())
	var sig := Crypto.new().sign(HashingContext.HASH_SHA256, ctx.finish(), priv)
	return h + "." + p + "." + _b64url(sig)


func _claims(gc: String, jti: String, extra: Dictionary = {}) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	var c := {"aud": "trifecta-host", "iat": now, "exp": now + 120, "code": "TEST1", "gc": gc, "slot": 1, "sub": "p_" + gc,
		"name": "Comfy Frog#0042", "jti": jti}
	c.merge(extra, true)
	return c


func test_admission_is_verified_bound_and_single_use() -> void:
	var keys := _key_pair()
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(20, 0, 0.0, 0)
	rig.host.require_admission = true
	rig.host.admission_key = keys[1]
	# no credential
	var a := rig.add_client("uid-a", "Typed Name", "any")
	await rig.wait_until(func() -> bool: return rig.ended_reason.has(a), 300)
	t.eq(rig.ended_reason.get(a, ""), "admission", "no credential, no entry")
	# someone else's credential
	var b := rig.add_client("uid-b", "Typed Name", "any")
	b.admission = _token(keys[0], _claims("uid-z", "j1"))
	await rig.wait_until(func() -> bool: return rig.ended_reason.has(b), 300)
	t.eq(rig.ended_reason.get(b, ""), "admission", "a credential is bound to its own Game Center player")
	# forged (signed by another key)
	var other := _key_pair()
	var f := rig.add_client("uid-f", "Typed Name", "any")
	f.admission = _token(other[0], _claims("uid-f", "j2"))
	await rig.wait_until(func() -> bool: return rig.ended_reason.has(f), 300)
	t.eq(rig.ended_reason.get(f, ""), "admission", "forged credential refused")
	# expired
	var e := rig.add_client("uid-e", "Typed Name", "any")
	var now := int(Time.get_unix_time_from_system())
	e.admission = _token(keys[0], _claims("uid-e", "j3", {"iat": now - 600, "exp": now - 400}))
	await rig.wait_until(func() -> bool: return rig.ended_reason.has(e), 300)
	t.eq(rig.ended_reason.get(e, ""), "admission", "expired credential refused")
	# valid
	var g := rig.add_client("uid-g", "Rude Typed Name", "any")
	g.admission = _token(keys[0], _claims("uid-g", "j4"))
	var ok := await rig.wait_until(func() -> bool: return g.local_slot >= 0, 300)
	t.check(ok, "a valid credential gets a slot")
	var ent: Dictionary = rig.host.roster[g.local_slot]
	t.eq(String(ent["name"]), "Comfy Frog", "the host shows the service-approved name, not the typed one")
	t.eq(String(ent["pid"]), "p_uid-g", "and knows the opaque profile id (for reports and blocks)")
	# replay of the same credential by another connection
	var r := rig.add_client("uid-g2", "Typed", "any")
	r.admission = _token(keys[0], _claims("uid-g2", "j4"))
	await rig.wait_until(func() -> bool: return rig.ended_reason.has(r), 300)
	t.eq(rig.ended_reason.get(r, ""), "admission", "a credential works once")
	rig.teardown()


func test_junk_and_floods_are_contained() -> void:
	var rig := _rig(1)
	var c: NetSession = rig.clients[0]
	await rig.wait_until(func() -> bool: return c.local_slot >= 0, 300)
	# a stranger (not in the room) sends 200 random packets of every type,
	# slowly enough not to trip the flood limit: parsing must hold up
	var junk := LoopbackTransport.new(rig.hub, false)
	rig.hub.link(junk.id, rig.host_t.id)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var before := rig.host.roster.filter(func(e): return e != null).size()
	for i in 200:
		var bytes := PackedByteArray()
		var ty := rng.randi_range(1, Protocol.M.LOADED)
		if ty == Protocol.M.HELLO:
			ty = Protocol.M.READY
		bytes.append(ty)
		for j in rng.randi_range(0, 60):
			bytes.append(rng.randi() % 256)
		junk.send(rig.host_t.id, bytes, true)
		if i % 10 == 0:
			await rig.frames(31)
	await rig.frames(30)
	t.check(rig.host != null and is_instance_valid(rig.host), "host survives junk")
	t.eq(rig.host.roster.filter(func(e): return e != null).size(), before, "no phantom players, nobody dropped")
	t.check(c.connected and not rig.ended_reason.has(c), "the real player is unaffected")
	# oversized HELLO strings are cut, not trusted
	var b := Protocol.buf_for(Protocol.M.HELLO)
	b.put_u16(Protocol.VERSION)
	Protocol.put_str(b, "uid-big")
	var long := ""
	for i in 300:
		long += "W"
	var u := long.to_utf8_buffer()
	b.put_u8(255)
	b.put_data(u.slice(0, 255))
	await rig.frames(10)
	t.check(true, "oversized fields bounded (no crash)")
	# a flood gets the peer removed
	var flooder := rig.add_client("uid-flood", "Flood", "any")
	await rig.wait_until(func() -> bool: return flooder.local_slot >= 0, 300)
	var ft: LoopbackTransport = rig.client_ts[rig.client_ts.size() - 1]
	var host_id: int = ft._links.keys()[0]
	for s in 4:
		for i in 60:
			var pb := Protocol.buf_for(Protocol.M.READY)
			pb.put_u8(1)
			pb.put_u8(0)
			ft.send(host_id, pb.data_array, true)
		await rig.frames(62)
	await rig.wait_until(func() -> bool: return rig.ended_reason.has(flooder), 300)
	t.eq(rig.ended_reason.get(flooder, ""), "kicked", "a peer flooding for 3 s is removed")
	t.check(c.connected and not rig.ended_reason.has(c), "everyone else is unaffected")
	rig.teardown()


func test_round_waits_for_load_acks() -> void:
	var rig := _rig(1)
	var c: NetSession = rig.clients[0]
	await rig.wait_until(func() -> bool: return c.local_slot >= 0, 300)
	t.check(rig.host.loads_complete(0.0), "nothing to wait for before a round")
	rig.host.host_start_match(5)
	t.check(not rig.host.loads_complete(0.0), "after START the host waits for the client to load")
	t.eq(rig.host.loading_names(), ["Client0"], "and can say who it is waiting for")
	await rig.wait_until(func() -> bool: return rig.host.loads_complete(0.0), 600)
	t.check(rig.host.loads_complete(0.0), "the client's LOADED ack releases the round")
	rig.teardown()


func test_names_from_the_network_are_sanitised() -> void:
	t.eq(NameRules.safe_display("Comfy Frog"), "Comfy Frog", "valid name kept")
	t.eq(NameRules.safe_display("Comfy Frog#0042"), "Comfy Frog#0042", "discriminator kept")
	t.eq(NameRules.safe_display("[b]Big[/b] <i>"), "Player", "markup-like names are replaced")
	t.eq(NameRules.safe_display("a"), "Player", "too short")
	t.eq(NameRules.safe_display("x".repeat(40)), "Player", "too long")
	t.eq(NameRules.safe_display("Emoji 😀"), "Player", "outside the character set")
	t.eq(NameRules.shape_error("Sleepy Otter 42"), "", "a normal name passes")
	t.check(NameRules.shape_error("two  spaces") != "", "double spaces")
	t.check(NameRules.shape_error("5551234567 x") != "", "long numbers")
	var rig := _rig(0)
	var evil := rig.add_client("uid-evil", "[color=red]Admin[/color]", "any")
	await rig.wait_until(func() -> bool: return evil.local_slot >= 0, 300)
	t.eq(String(rig.host.roster[evil.local_slot]["name"]), "Player", "the host sanitises a typed name")
	rig.teardown()
