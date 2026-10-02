extends RefCounted
## V6 party chat over the real session code (loopback host + clients):
## Quick Chat delivery and ordering, the host as referee (channel, phrase,
## rate and repeat limits), forged and duplicate packets, typed messages
## with service-signed tokens (tampered, someone else's, replayed, relayed
## unverified by a bad host), mute/block suppression, reconnect history,
## and the round's channels (own team only; finished runners talk only to
## other spectators; everyone after results).
var t
var _key: CryptoKey
var _pub: CryptoKey


func _rig(n: int, prefs: Array = []) -> NetRig:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(20, 0, 0.0, n, prefs)
	return rig


func _ready_party(rig: NetRig) -> void:
	await rig.wait_until(func() -> bool:
		for c in rig.clients:
			if c.local_slot < 0:
				return false
		return rig.host.human_count() == rig.clients.size() + 1, 300)
	await rig.frames(6)


static func _texts(s: NetSession) -> Array:
	var out: Array = []
	for m in s.social.chat.history:
		if String(m["state"]) != "failed":
			out.append(String(m["text"]))
	return out


func _keys() -> void:
	if _key == null:
		_key = Crypto.new().generate_rsa(2048)
		_pub = CryptoKey.new()
		_pub.load_from_string(_key.save_to_string(true), true)


static func _b64u(raw: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(raw).replace("+", "-").replace("/", "_").replace("=", "")


## A chat token as the service signs it (test key).
func _token(sub: String, room: String, text: String, ch: int = 0, jti: String = "") -> String:
	_keys()
	var now := int(Time.get_unix_time_from_system())
	var head := _b64u(JSON.stringify({"alg": "RS256", "typ": "JWT"}).to_utf8_buffer())
	var body := _b64u(JSON.stringify({"sub": sub, "room": room, "ch": ch, "text": text, "aud": "trifecta-chat",
		"iat": now, "exp": now + 300, "jti": jti if jti != "" else "c_%d" % randi()}).to_utf8_buffer())
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update((head + "." + body).to_utf8_buffer())
	return head + "." + body + "." + _b64u(Crypto.new().sign(HashingContext.HASH_SHA256, ctx.finish(), _key))


## Make the rig a service-backed party (verified names, profile ids, key).
func _verified(rig: NetRig) -> void:
	_keys()
	rig.host.require_admission = true
	rig.host.admission_key = _pub
	rig.host.roster[0]["pid"] = "p_host"
	for i in rig.clients.size():
		var c: NetSession = rig.clients[i]
		c.admission = "test-admission"
		c.admission_key = _pub
		rig.host.roster[c.local_slot]["pid"] = "p_c%d" % i
	rig.host._broadcast_lobby()


func _send_raw(c: NetSession, channel: int, kind: int, payload: Variant) -> void:
	var b := Protocol.buf_for(SocialProto.CHAT_SEND)
	b.put_u16(999)
	b.put_u8(channel)
	b.put_u8(kind)
	if kind == SocialProto.Kind.QUICK:
		b.put_u8(int(payload))
	else:
		Protocol.put_long_str(b, String(payload))
	c.transport.send(c.host_peer, b.data_array, true)


func test_quick_chat_reaches_the_party_in_order_once() -> void:
	var rig := _rig(2)
	await _ready_party(rig)
	var c0: NetSession = rig.clients[0]
	var c1: NetSession = rig.clients[1]
	t.check(c0.social.chat.send_quick(1, QuickChat.Channel.PARTY), "a guest sends Ready!")
	t.eq(_texts(c0), ["Ready!"], "shown on the sender's screen at once (pending)")
	t.eq(String(c0.social.chat.history[0]["state"]), "pending", "until the host relays it")
	await rig.frames(10)
	rig.host.social.chat.now_fn = func() -> float: return 100.0
	t.check(rig.host.social.chat.send_quick(4, QuickChat.Channel.PARTY), "the host says hi")
	await rig.frames(10)
	for s in [rig.host, c0, c1]:
		t.eq(_texts(s), ["Ready!", "Hi everyone!"], "%s: both messages, in the host's order" % s.name)
	t.eq(String(c0.social.chat.history[0]["state"]), "sent", "the guest's own message is confirmed, not doubled")
	t.eq(c1.social.chat.unread, 2, "unread count for the drawer badge")
	# a duplicated packet (the transport repeating itself) is stored once
	var m: Dictionary = rig.host.social.chat.history[1]
	var dup := PackedByteArray([SocialProto.CHAT])
	dup.append_array(rig.host.social.chat._body(int(m["seq"]), int(m["from"]), int(m["channel"]), int(m["kind"]), 0, int(m["phrase"]), ""))
	c1._on_packet(c1.host_peer, dup)
	c1._on_packet(c1.host_peer, dup)
	t.eq(_texts(c1), ["Ready!", "Hi everyone!"], "a repeated packet doesn't repeat the message")
	# out of order: an older sequence number slots in before
	var early := PackedByteArray([SocialProto.CHAT])
	early.append_array(rig.host.social.chat._body(int(m["seq"]) + 5, 0, QuickChat.Channel.PARTY, SocialProto.Kind.QUICK, 0, 3, ""))
	var late := PackedByteArray([SocialProto.CHAT])
	late.append_array(rig.host.social.chat._body(int(m["seq"]) + 4, 0, QuickChat.Channel.PARTY, SocialProto.Kind.QUICK, 0, 9, ""))
	c1._on_packet(c1.host_peer, early)
	c1._on_packet(c1.host_peer, late)
	t.eq(_texts(c1).slice(2), ["Change the settings?", "Let's play!"], "ordered by the host's sequence, whatever the arrival order")
	rig.teardown()
	await t.get_tree().process_frame   # (queued frees happen before the next test)
	await t.get_tree().process_frame


func test_host_referees_channel_phrase_rate_and_repeat() -> void:
	var rig := _rig(2)
	await _ready_party(rig)
	var c0: NetSession = rig.clients[0]
	var c1: NetSession = rig.clients[1]
	var rejections: Array = []
	c0.social.chat.rejected.connect(func(msg: String) -> void: rejections.append(msg))
	# a team message before any round
	_send_raw(c0, QuickChat.Channel.TEAM, SocialProto.Kind.QUICK, 20)
	# a round phrase in the party room
	_send_raw(c0, QuickChat.Channel.PARTY, SocialProto.Kind.QUICK, 26)
	# an unknown phrase id and an unknown kind
	_send_raw(c0, QuickChat.Channel.PARTY, SocialProto.Kind.QUICK, 250)
	await rig.frames(10)
	t.eq(rejections.size(), 3, "three rejections, back to the sender only")
	t.eq(_texts(c1), [], "nobody else saw any of them")
	t.eq(_texts(rig.host), [], "nor the host's screen")
	# rate: a burst of four, then wait
	var hc := rig.host.social.chat
	var clock := {"t": 50.0}
	hc.now_fn = func() -> float: return float(clock["t"])
	for id in [1, 2, 3, 5, 7]:
		_send_raw(c0, QuickChat.Channel.PARTY, SocialProto.Kind.QUICK, id)
	await rig.frames(10)
	t.eq(_texts(c1).size(), 4, "a burst of four gets through")
	t.eq(rejections.size(), 4, "the fifth is refused as too fast")
	clock["t"] = 52.5
	_send_raw(c0, QuickChat.Channel.PARTY, SocialProto.Kind.QUICK, 8)
	await rig.frames(8)
	t.eq(_texts(c1).size(), 5, "one more after two seconds")
	clock["t"] = 53.0
	_send_raw(c0, QuickChat.Channel.PARTY, SocialProto.Kind.QUICK, 8)
	await rig.frames(8)
	t.eq(rejections.size(), 5, "the same phrase twice in three seconds is dropped")
	rig.teardown()
	await t.get_tree().process_frame   # (queued frees happen before the next test)
	await t.get_tree().process_frame


func test_receivers_defend_against_forged_messages() -> void:
	var rig := _rig(2)
	await _ready_party(rig)
	var c1: NetSession = rig.clients[1]
	var hc := rig.host.social.chat
	var bodies := [
		hc._body(901, 5, QuickChat.Channel.PARTY, SocialProto.Kind.QUICK, 0, 1, ""),    # an empty seat
		hc._body(902, 7, QuickChat.Channel.PARTY, SocialProto.Kind.QUICK, 0, 1, ""),    # (empty too)
		hc._body(903, 0, QuickChat.Channel.PARTY, SocialProto.Kind.QUICK, 0, 26, ""),   # a round phrase in the party room
		hc._body(904, 0, QuickChat.Channel.PARTY, SocialProto.Kind.QUICK, 0, 222, ""),  # no such phrase
		hc._body(905, 0, QuickChat.Channel.PARTY, SocialProto.Kind.TEXT, 0, 0, "not.a.token"),
	]
	for body in bodies:
		var d := PackedByteArray([SocialProto.CHAT])
		d.append_array(body)
		c1._on_packet(c1.host_peer, d)
	# the same message from someone who isn't the host
	var ok := PackedByteArray([SocialProto.CHAT])
	ok.append_array(hc._body(906, 0, QuickChat.Channel.PARTY, SocialProto.Kind.QUICK, 0, 1, ""))
	c1._on_packet(c1.host_peer + 77, ok)
	# truncated and oversized junk
	c1._on_packet(c1.host_peer, PackedByteArray([SocialProto.CHAT, 1, 2]))
	c1._on_packet(c1.host_peer, PackedByteArray([SocialProto.CHAT_HISTORY, 200]))
	t.eq(_texts(c1), [], "nothing forged, invalid or from a non-host peer is shown")
	# a flood relayed by the host: at most 8 per sender per 10 s are kept
	c1.social.chat._recv.clear()
	for i in 20:
		var d2 := PackedByteArray([SocialProto.CHAT])
		d2.append_array(hc._body(1000 + i, 0, QuickChat.Channel.PARTY, SocialProto.Kind.QUICK, 0, [1, 2, 3, 4][i % 4], ""))
		c1._on_packet(c1.host_peer, d2)
	t.eq(_texts(c1).size(), ChatChannel.RECV_MAX, "a flooding sender is cut off on the receiver too")
	rig.teardown()
	await t.get_tree().process_frame   # (queued frees happen before the next test)
	await t.get_tree().process_frame


func test_typed_messages_need_the_services_signature() -> void:
	var rig := _rig(2)
	await _ready_party(rig)
	_verified(rig)
	await rig.frames(8)
	var c0: NetSession = rig.clients[0]
	var c1: NetSession = rig.clients[1]
	var rejections: Array = []
	c0.social.chat.rejected.connect(func(msg: String) -> void: rejections.append(msg))
	var room := rig.host.room_code
	_send_raw(c0, QuickChat.Channel.PARTY, SocialProto.Kind.TEXT, _token("p_c0", room, "Ready when you are!", 0, "c_one"))
	await rig.frames(10)
	t.eq(_texts(c1), ["Ready when you are!"], "an approved message is shown (verified again on arrival)")
	t.eq(_texts(rig.host), ["Ready when you are!"], "and on the host")
	# replayed
	_send_raw(c0, QuickChat.Channel.PARTY, SocialProto.Kind.TEXT, _token("p_c0", room, "Ready when you are!", 0, "c_one"))
	# someone else's message presented as ours
	_send_raw(c0, QuickChat.Channel.PARTY, SocialProto.Kind.TEXT, _token("p_c1", room, "I'm c1", 0))
	# another room
	_send_raw(c0, QuickChat.Channel.PARTY, SocialProto.Kind.TEXT, _token("p_c0", "OTHER1", "elsewhere", 0))
	# edited after signing
	var tok := _token("p_c0", room, "nice", 0)
	var parts := tok.split(".")
	var forged_body := _b64u(Admission._b64url(parts[1]).get_string_from_utf8().replace("nice", "rude").to_utf8_buffer())
	_send_raw(c0, QuickChat.Channel.PARTY, SocialProto.Kind.TEXT, parts[0] + "." + forged_body + "." + parts[2])
	# signed, but for another channel than it's sent on
	_send_raw(c0, QuickChat.Channel.PARTY, SocialProto.Kind.TEXT, _token("p_c0", room, "team only", 1))
	await rig.frames(10)
	t.eq(rejections.size(), 5, "replay, someone else's, another room, edited and wrong channel are all refused")
	t.eq(_texts(c1), ["Ready when you are!"], "and none of them reached anyone")
	# a bad host relaying text the service never approved: receivers drop it
	var unsigned := PackedByteArray([SocialProto.CHAT])
	unsigned.append_array(rig.host.social.chat._body(500, 0, QuickChat.Channel.PARTY, SocialProto.Kind.TEXT, 0, 0, tok.replace(parts[2], parts[2].reverse())))
	c1._on_packet(c1.host_peer, unsigned)
	var abusive := PackedByteArray([SocialProto.CHAT])
	abusive.append_array(rig.host.social.chat._body(501, 0, QuickChat.Channel.PARTY, SocialProto.Kind.TEXT, 0, 0,
		_token("p_host", room, Marshalls.base64_to_utf8("ZnVjayB5b3U="), 0)))
	c1._on_packet(c1.host_peer, abusive)
	t.eq(_texts(c1), ["Ready when you are!"], "receivers verify the signature and the policy themselves")
	# without the service the party has no typed chat at all
	var plain := _rig(1)
	await _ready_party(plain)
	var pc: NetSession = plain.clients[0]
	var pr: Array = []
	pc.social.chat.rejected.connect(func(msg: String) -> void: pr.append(msg))
	_send_raw(pc, QuickChat.Channel.PARTY, SocialProto.Kind.TEXT, _token("p_c0", plain.host.room_code, "hello", 0))
	await plain.frames(8)
	t.eq(pr.size(), 1, "a party without the service refuses typed messages")
	t.check(not bool(pc.social.chat.text_available()["ok"]), "and says typed chat is unavailable")
	t.check(String(pc.social.chat.text_available()["why"]).contains("Quick Chat"), "while Quick Chat keeps working")
	plain.teardown()
	await t.get_tree().process_frame   # (queued frees happen before the next test)
	await t.get_tree().process_frame
	rig.teardown()
	await t.get_tree().process_frame   # (queued frees happen before the next test)
	await t.get_tree().process_frame


func test_send_text_shows_only_approved_text() -> void:
	var rig := _rig(1)
	await _ready_party(rig)
	_verified(rig)
	await rig.frames(6)
	var c0: NetSession = rig.clients[0]
	var saved := {"state": Cloud.state, "token": Cloud.token, "exp": Cloud.token_exp_ms, "cfg": Cloud.service_config, "tr": Cloud.transport_override}
	Cloud.state = "ready"
	Cloud.token = "test-session"
	Cloud.token_exp_ms = int(Time.get_unix_time_from_system() * 1000.0) + 3600000
	Cloud.service_config = {"features": ["chat"]}
	var calls: Array = []
	Cloud.transport_override = func(_m: int, path: String, body: Variant, _h: PackedStringArray) -> Dictionary:
		calls.append(path)
		var text := String((body as Dictionary).get("text", ""))
		if text.contains("snap"):
			return {"status": 422, "body": {"ok": false, "error": "chat_rejected", "reason": "contact", "message": "Chat can't include links, handles or contact details."}}
		return {"status": 200, "body": {"ok": true, "text": text, "token": _token("p_c0", rig.host.room_code, text, 0)}}
	t.check(bool(c0.social.chat.text_available()["ok"]), "typed chat is available in a service party")
	var r1: Dictionary = await c0.social.chat.send_text("Wait   for me", QuickChat.Channel.PARTY)
	t.check(bool(r1["ok"]), "an ordinary message goes")
	var r2: Dictionary = await c0.social.chat.send_text("add me on snap", QuickChat.Channel.PARTY)
	t.check(not bool(r2["ok"]) and String(r2["message"]).contains("contact"), "the device catches contact spam first, with the reason")
	var r3: Dictionary = await c0.social.chat.send_text("my snaps are great", QuickChat.Channel.PARTY)
	t.check(not bool(r3["ok"]), "the service's rejection is passed on")
	await rig.frames(10)
	t.eq(_texts(rig.host), ["Wait for me"], "only approved, normalised text is ever shown")
	t.eq(_texts(c0), ["Wait for me"], "on the sender's screen too (never the rejected raw text)")
	t.eq(calls.size(), 2, "the device didn't ask the service about text it already knew was refused")
	Cloud.state = saved["state"]
	Cloud.token = saved["token"]
	Cloud.token_exp_ms = saved["exp"]
	Cloud.service_config = saved["cfg"]
	Cloud.transport_override = saved["tr"]
	rig.teardown()
	await t.get_tree().process_frame   # (queued frees happen before the next test)
	await t.get_tree().process_frame


func test_mute_and_block_suppress_everywhere() -> void:
	var rig := _rig(2)
	await _ready_party(rig)
	var c0: NetSession = rig.clients[0]
	var c1: NetSession = rig.clients[1]
	c0.social.chat.send_quick(1, QuickChat.Channel.PARTY)
	await rig.frames(10)
	t.eq(_texts(c1), ["Ready!"], "seen before the mute")
	c1.muted["uid-c0"] = true
	t.eq(c1.social.chat.visible([QuickChat.Channel.PARTY]).size(), 0, "a mute hides what is already there")
	rig.host.social.chat.now_fn = func() -> float: return 300.0
	c0.social.chat.send_quick(2, QuickChat.Channel.PARTY)
	await rig.frames(10)
	t.eq(c1.social.chat.visible([QuickChat.Channel.PARTY]).size(), 0, "and what comes after")
	c1.muted.erase("uid-c0")
	# block (kept on the device)
	var saved_blocks: Array = (Save.data["blocked"] as Array).duplicate()
	Save.add_block("", "uid-c0", "Client0")
	rig.host.social.chat.now_fn = func() -> float: return 400.0
	c0.social.chat.send_quick(3, QuickChat.Channel.PARTY)
	await rig.frames(10)
	t.check(c1.social.chat.visible([QuickChat.Channel.PARTY]).all(func(m: Dictionary) -> bool: return String(m["uid"]) != "uid-c0"), "a blocked player's messages never show")
	t.eq(SocialSafety.name_of(c1.roster[c0.local_slot]), SocialSafety.BLOCKED_NAME, "and their name is hidden")
	t.check(SocialSafety.name_of(c1.roster[0]) != SocialSafety.BLOCKED_NAME, "others' names are untouched")
	Save.data["blocked"] = saved_blocks
	rig.teardown()
	await t.get_tree().process_frame   # (queued frees happen before the next test)
	await t.get_tree().process_frame


func test_rejoining_player_gets_recent_party_chat() -> void:
	var rig := _rig(1)
	await _ready_party(rig)
	rig.host.social.chat.send_quick(4, QuickChat.Channel.PARTY)
	rig.clients[0].social.chat.send_quick(1, QuickChat.Channel.PARTY)
	await rig.frames(10)
	var late := rig.add_client("uid-c9", "Late", "any")
	await rig.wait_until(func() -> bool: return late.local_slot >= 0, 300)
	await rig.frames(10)
	t.eq(_texts(late), ["Hi everyone!", "Ready!"], "a newcomer sees the recent party conversation")
	rig.teardown()
	await t.get_tree().process_frame   # (queued frees happen before the next test)
	await t.get_tree().process_frame


func test_round_channels_keep_information_on_its_side() -> void:
	# host and c0 run, c1 is Night Watch
	var rig := _rig(2, ["runner", "runner", "patrol"])
	await _ready_party(rig)
	var c0: NetSession = rig.clients[0]
	var c1: NetSession = rig.clients[1]
	c0.social.chat.send_quick(1, QuickChat.Channel.PARTY)
	await rig.frames(8)
	for c in rig.clients:
		c.set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.can_start(), 200)
	rig.host.host_start_match(77)
	await rig.wait_until(func() -> bool: return rig.host.sim != null and rig.host.sim.phase == TC.Phase.PLAYING, 1200)
	t.eq(rig.host.sim.phase, TC.Phase.PLAYING, "the round is on")
	var hc := rig.host.social.chat
	t.eq(hc.host_channel_for(c0.local_slot), QuickChat.Channel.TEAM, "an active runner talks to their team")
	var before0 := _texts(rig.host).size()
	var before1 := _texts(c1).size()
	t.check(c0.social.chat.send_quick(24, QuickChat.Channel.TEAM), "Night Watch nearby!")
	await rig.frames(10)
	t.eq(_texts(rig.host).size(), before0 + 1, "the runner host hears it")
	t.eq(_texts(c1).size(), before1, "the Night Watch never does")
	t.check(not c1.social.chat.send_quick(24, QuickChat.Channel.TEAM), "a runners' phrase isn't offered to the Night Watch")
	_send_raw(c0, QuickChat.Channel.PARTY, SocialProto.Kind.QUICK, 1)
	await rig.frames(8)
	t.eq(_texts(c1).size(), before1, "party chat is closed during the round")
	# a runner who got home watches the whole campus: spectators only
	rig.host.sim.player(c0.local_slot).state = TC.PState.FINISHED
	t.eq(hc.host_channel_for(c0.local_slot), QuickChat.Channel.SPECTATORS, "finished: the spectators' channel")
	var rejections: Array = []
	c0.social.chat.rejected.connect(func(msg: String) -> void: rejections.append(msg))
	_send_raw(c0, QuickChat.Channel.TEAM, SocialProto.Kind.QUICK, 24)
	await rig.frames(8)
	t.eq(rejections.size(), 1, "a finished runner can't tell active teammates where the Night Watch is")
	t.eq(_texts(rig.host).size(), before0 + 1, "(the active runner heard nothing)")
	c0.social.chat.send_quick(45, QuickChat.Channel.SPECTATORS)
	await rig.frames(8)
	t.eq(_texts(rig.host).size(), before0 + 1, "spectator chat doesn't reach active players")
	t.eq(_texts(c1).size(), before1, "on either team")
	# results: everyone again
	rig.host.sim.player(c0.local_slot).state = TC.PState.ACTIVE
	rig.host.sim.cancel_match()
	await rig.wait_until(func() -> bool: return rig.host.phase == TC.Phase.RESULTS or rig.host.phase == TC.Phase.ENDED, 400)
	rig.host.phase = TC.Phase.RESULTS
	t.eq(hc.host_channel_for(c1.local_slot), QuickChat.Channel.ALL, "results: everyone")
	c1.phase = TC.Phase.RESULTS
	t.check(c1.social.chat.send_quick(40, QuickChat.Channel.ALL), "Good game!")
	await rig.frames(10)
	t.check(_texts(c0).has("Good game!") and _texts(rig.host).has("Good game!"), "heard by both teams")
	rig.teardown()
	await t.get_tree().process_frame   # (queued frees happen before the next test)
	await t.get_tree().process_frame
