class_name ChatChannel
extends RefCounted
## Party chat over the party's own connection (V6).  The host is the relay
## and the referee; every device keeps a short, ordered history.
##
## Sending.  Quick Chat sends a phrase id.  Typed text is first checked on
## the device (ChatRules, for instant feedback), then approved by the
## service, which signs the approved text (ChatToken); only that signed
## text is ever sent or shown.  Without a working service typed chat is
## honestly unavailable and Quick Chat keeps working.
##
## Host (referee).  A message is relayed only when: the sender holds a seat
## (bots and room spectators don't chat); the channel is the one the sender
## may use now (party room: PARTY; during a round: TEAM, or SPECTATORS for
## finished runners, who see the whole campus and must not relay it; results:
## ALL); a phrase is allowed on that channel for the sender's role; a typed
## message's token verifies for this room and the sender's own profile and
## hasn't been used; and the sender is within the rate limit (a burst of 4,
## then one message every 2 s; the same phrase twice within 3 s is dropped).
## Rejections go back to the sender only.  Recipients: everyone for PARTY
## and ALL; the sender's role for TEAM; finished runners and room
## spectators for SPECTATORS.
##
## Receivers (defence).  Messages come only from the bound host; they are
## de-duplicated and ordered by the host's sequence number, the sender must
## be a seated human in the current roster, the channel must be one this
## device may see, a phrase must fit its channel and role, a typed message's
## token is verified again (and the text checked against the policy again),
## at most 8 messages per sender per 10 s are kept, and muted or blocked
## senders are dropped before anything is stored.  History: the last 80.

signal changed
signal rejected(message: String)

const HISTORY_MAX := 80
const BURST := 4
const REFILL_S := 2.0
const REPEAT_S := 3.0
const RECV_MAX := 8
const RECV_WINDOW_S := 10.0
const RELAY_HISTORY := 20

var session: NetSession
## [{seq, from, uid, pid, name, channel, kind, phrase, text, token, at, mine, state, round}] oldest first
var history: Array = []
var unread := 0
## the device clock in seconds (tests can drive it)
var now_fn: Callable = func() -> float: return Time.get_ticks_msec() / 1000.0
## tests: overrides the verification key (else Cloud.admission_key / session key)
var key_override: CryptoKey

# host
var _seq := 0
var _bucket: Dictionary = {}       # slot -> {tokens, at}
var _last_phrase: Dictionary = {}  # slot -> {id, at}
var _relay_jti: Dictionary = {}
# everyone
var _seen_seq: Dictionary = {}
var _seen_jti: Dictionary = {}
var _recv: Dictionary = {}         # slot -> [times]
var _nonce := 0
var _pending: Dictionary = {}      # nonce -> message (ours, waiting for the host)


func _init(s: NetSession) -> void:
	session = s


func _key() -> CryptoKey:
	if key_override != null:
		return key_override
	if session.admission_key != null:
		return session.admission_key
	return Cloud.admission_key


# ---------------------------------------------------------------------------
# Who may say what, where
# ---------------------------------------------------------------------------
## The channel a seated player may use right now (host's view), or -1.
func host_channel_for(slot: int) -> int:
	if slot < 0 or slot > 7 or session.roster[slot] == null or bool(session.roster[slot]["is_bot"]):
		return -1
	var ph := session.phase
	if ph == TC.Phase.LOBBY or ph == TC.Phase.LOADING:
		return QuickChat.Channel.PARTY
	if ph >= TC.Phase.REVEAL and ph <= TC.Phase.PLAYING:
		var p: SimPlayer = session.sim.player(slot) if session.sim else null
		if p == null:
			return -1
		return QuickChat.Channel.SPECTATORS if p.state == TC.PState.FINISHED else QuickChat.Channel.TEAM
	if ph == TC.Phase.RESULTS or ph == TC.Phase.ENDED:
		return QuickChat.Channel.ALL
	return -1


## The channel this device may use now.  `finished`: the local runner is
## home (watching the whole campus).  Clients follow the host's phases.
func my_channel(in_round: bool, finished: bool = false) -> int:
	if session.local_slot < 0:
		return -1
	if session.is_host():
		return host_channel_for(session.local_slot)
	if in_round:
		return QuickChat.Channel.SPECTATORS if finished else QuickChat.Channel.TEAM
	if session.phase == TC.Phase.RESULTS:
		return QuickChat.Channel.ALL
	return QuickChat.Channel.PARTY


func role_of(slot: int) -> int:
	if slot < 0 or slot > 7:
		return -1
	if session.sim != null:
		var p: SimPlayer = session.sim.player(slot)
		if p != null:
			return p.role
	for e in session.current_start.get("roster", []):
		if int(e.get("slot", -1)) == slot:
			return int(e.get("role", -1))
	var r: Variant = session.roster[slot]
	return int(r.get("role", -1)) if r != null else -1


# ---------------------------------------------------------------------------
# Sending
# ---------------------------------------------------------------------------
func send_quick(id: int, channel: int) -> bool:
	if not QuickChat.allowed(id, channel, role_of(session.local_slot)) or session.local_slot < 0:
		return false
	return _send(channel, SocialProto.Kind.QUICK, id, "", "")


## Typed chat available here?  {ok} or {ok:false, why}.
func text_available() -> Dictionary:
	if session.mode == NetSession.Mode.OFFLINE:
		return {"ok": false, "why": "Chat is for parties with friends."}
	if not Cloud.configured():
		return {"ok": false, "why": "Typed chat needs the game's online moderation service, which isn't set up in this build. Quick Chat works."}
	if not Cloud.has_feature("chat"):
		return {"ok": false, "why": "Typed chat isn't available from the game service right now. Quick Chat works."}
	if not Cloud.signed_in():
		return {"ok": false, "why": "Typed chat needs you signed in to the game service. Quick Chat works."}
	if _key() == null or not session.names_verified():
		return {"ok": false, "why": "This party wasn't set up through the game service, so typed chat is off. Quick Chat works."}
	return {"ok": true}


## Typed message: device check, then the service's approval, then the
## party.  Returns {ok} or {ok:false, message} (the text is never shown
## unless approved).
func send_text(raw: String, channel: int) -> Dictionary:
	var av := text_available()
	if not bool(av["ok"]):
		return {"ok": false, "message": String(av["why"])}
	var local := ChatRules.check(raw)
	if not bool(local["ok"]):
		return {"ok": false, "message": String(local["message"]), "reason": String(local["reason"])}
	var r: Dictionary = await Cloud.chat_check(session.room_code, channel, String(local["text"]))
	if not bool(r.get("ok", false)):
		return {"ok": false, "message": Cloud.explain(r), "reason": String(r.get("reason", r.get("error", "")))}
	if not is_instance_valid(session) or session.local_slot < 0:
		return {"ok": false, "message": "You left the party."}
	_send(channel, SocialProto.Kind.TEXT, 0, String(r["text"]), String(r["token"]))
	return {"ok": true}


func _send(channel: int, kind: int, phrase: int, text: String, token: String) -> bool:
	_nonce = (_nonce + 1) & 0xFFFF
	var msg := _make(-1, session.local_slot, channel, kind, phrase, text, token)
	msg["mine"] = true
	msg["state"] = "pending"
	msg["nonce"] = _nonce
	if session.is_host():
		return _host_accept(session.local_slot, -1, channel, kind, phrase, token, _nonce)
	if session.host_peer < 0:
		return false
	_pending[_nonce] = msg
	_insert(msg)
	var b := Protocol.buf_for(SocialProto.CHAT_SEND)
	b.put_u16(_nonce)
	b.put_u8(channel)
	b.put_u8(kind)
	if kind == SocialProto.Kind.QUICK:
		b.put_u8(phrase)
	else:
		Protocol.put_long_str(b, token)
	session.transport.send(session.host_peer, b.data_array, true)
	return true


# ---------------------------------------------------------------------------
# Host
# ---------------------------------------------------------------------------
func host_packet(peer: int, b: StreamPeerBuffer) -> void:
	if b.get_available_bytes() < 4:
		return
	var nonce := b.get_u16()
	var channel := b.get_u8()
	var kind := b.get_u8()
	var phrase := 0
	var token := ""
	if kind == SocialProto.Kind.QUICK:
		if b.get_available_bytes() < 1:
			return
		phrase = b.get_u8()
	elif kind == SocialProto.Kind.TEXT:
		token = Protocol.get_long_str(b)
	else:
		return
	var slot := int(session._peer_slot.get(peer, -1))
	if slot < 0:
		return   # room spectators and strangers don't chat
	_host_accept(slot, peer, channel, kind, phrase, token, nonce)


func _reject(peer: int, nonce: int, reason: int) -> bool:
	if peer >= 0:
		var b := Protocol.buf_for(SocialProto.CHAT_REJECT)
		b.put_u16(nonce)
		b.put_u8(reason)
		session.transport.send(peer, b.data_array, true)
	else:
		_on_reject(nonce, reason)
	return false


func _host_accept(slot: int, peer: int, channel: int, kind: int, phrase: int, token: String, nonce: int) -> bool:
	var allowed := host_channel_for(slot)
	if allowed < 0 or channel != allowed:
		return _reject(peer, nonce, SocialProto.Reject.CHANNEL)
	var text := ""
	if kind == SocialProto.Kind.QUICK:
		if not QuickChat.allowed(phrase, channel, role_of(slot)):
			return _reject(peer, nonce, SocialProto.Reject.PHRASE)
	else:
		if not session.names_verified() or _key() == null:
			return _reject(peer, nonce, SocialProto.Reject.UNAVAILABLE)
		var v := ChatToken.verify(token, _key(), {"room": session.room_code, "sub": String(session.roster[slot].get("pid", "")), "seen": _relay_jti})
		if not bool(v["ok"]) or int((v["claims"] as Dictionary).get("ch", -1)) != channel:
			return _reject(peer, nonce, SocialProto.Reject.UNVERIFIED)
		_relay_jti[String(v["claims"]["jti"])] = true
		text = String(v["claims"]["text"])
	var now: float = now_fn.call()
	if kind == SocialProto.Kind.QUICK:
		var lp: Dictionary = _last_phrase.get(slot, {})
		if int(lp.get("id", -1)) == phrase and now - float(lp.get("at", -99.0)) < REPEAT_S:
			return _reject(peer, nonce, SocialProto.Reject.REPEAT)
	var bk: Dictionary = _bucket.get(slot, {"tokens": float(BURST), "at": now})
	var tokens := minf(float(BURST), float(bk["tokens"]) + (now - float(bk["at"])) / REFILL_S)
	if tokens < 1.0:
		_bucket[slot] = {"tokens": tokens, "at": now}
		return _reject(peer, nonce, SocialProto.Reject.RATE)
	_bucket[slot] = {"tokens": tokens - 1.0, "at": now}
	if kind == SocialProto.Kind.QUICK:
		_last_phrase[slot] = {"id": phrase, "at": now}
	_seq += 1
	var body := _body(_seq, slot, channel, kind, nonce, phrase, token)
	var data := PackedByteArray([SocialProto.CHAT])
	data.append_array(body)
	for p in _recipient_peers(channel, slot):
		session.transport.send(p, data, true)
	# the host's own screen
	if _host_sees(channel, slot):
		_receive(_seq, slot, channel, kind, nonce, phrase, token, text)
	elif slot == session.local_slot:
		_receive(_seq, slot, channel, kind, nonce, phrase, token, text)
	return true


func _host_sees(channel: int, from_slot: int) -> bool:
	return _slot_sees(session.local_slot, channel, from_slot)


func _slot_sees(slot: int, channel: int, from_slot: int) -> bool:
	match channel:
		QuickChat.Channel.PARTY, QuickChat.Channel.ALL:
			return true
		QuickChat.Channel.TEAM:
			return slot >= 0 and role_of(slot) == role_of(from_slot)
		QuickChat.Channel.SPECTATORS:
			if slot < 0:
				return true   # room spectators
			var p: SimPlayer = session.sim.player(slot) if session.sim else null
			return p != null and p.state == TC.PState.FINISHED
	return false


func _recipient_peers(channel: int, from_slot: int) -> Array:
	var out: Array = []
	for peer in session.transport.peers():
		if session._peer_slot.has(peer):
			if _slot_sees(int(session._peer_slot[peer]), channel, from_slot):
				out.append(peer)
		elif session.spectators.has(peer) and channel != QuickChat.Channel.TEAM:
			out.append(peer)
	return out


func _body(seq: int, slot: int, channel: int, kind: int, nonce: int, phrase: int, token: String) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.big_endian = false
	b.put_u32(seq)
	b.put_8(slot)
	b.put_u8(channel)
	b.put_u8(kind)
	b.put_u16(nonce)
	if kind == SocialProto.Kind.QUICK:
		b.put_u8(phrase)
	else:
		Protocol.put_long_str(b, token)
	return b.data_array


## Host: a (re)joining player gets the recent party conversation (what they
## may see: PARTY and ALL, and their own team's messages of this round).
func host_send_history(peer: int, slot: int) -> void:
	var picked: Array = []
	for m in history:
		if int(m["seq"]) <= 0 or String(m.get("state", "")) == "failed":
			continue
		var ch := int(m["channel"])
		if ch == QuickChat.Channel.PARTY or ch == QuickChat.Channel.ALL or (ch == QuickChat.Channel.TEAM and slot >= 0 and _slot_sees(slot, ch, int(m["from"]))):
			picked.append(m)
	picked = picked.slice(maxi(0, picked.size() - RELAY_HISTORY))
	if picked.is_empty():
		return
	var b := Protocol.buf_for(SocialProto.CHAT_HISTORY)
	b.put_u8(picked.size())
	for m in picked:
		b.put_data(_body(int(m["seq"]), int(m["from"]), int(m["channel"]), int(m["kind"]), 0, int(m["phrase"]), String(m["token"])))
	session.transport.send(peer, b.data_array, true)


# ---------------------------------------------------------------------------
# Client
# ---------------------------------------------------------------------------
func client_packet(type: int, b: StreamPeerBuffer) -> void:
	match type:
		SocialProto.CHAT:
			_read_body(b)
		SocialProto.CHAT_HISTORY:
			if b.get_available_bytes() < 1:
				return
			var n := mini(b.get_u8(), RELAY_HISTORY)
			for i in n:
				if not _read_body(b, true):
					break
		SocialProto.CHAT_REJECT:
			if b.get_available_bytes() >= 3:
				var nonce := b.get_u16()
				_on_reject(nonce, b.get_u8())


func _read_body(b: StreamPeerBuffer, from_history: bool = false) -> bool:
	if b.get_available_bytes() < 9:
		return false
	var seq := b.get_u32()
	var slot := b.get_8()
	var channel := b.get_u8()
	var kind := b.get_u8()
	var nonce := b.get_u16()
	var phrase := 0
	var token := ""
	if kind == SocialProto.Kind.QUICK:
		if b.get_available_bytes() < 1:
			return false
		phrase = b.get_u8()
	elif kind == SocialProto.Kind.TEXT:
		token = Protocol.get_long_str(b)
	else:
		return false
	if channel > QuickChat.Channel.SPECTATORS:
		return true
	_receive(seq, slot, channel, kind, nonce if not from_history else 0, phrase, token, "")
	return true


func _on_reject(nonce: int, reason: int) -> void:
	var m: Variant = _pending.get(nonce)
	_pending.erase(nonce)
	if m != null:
		(m as Dictionary)["state"] = "failed"
	rejected.emit(SocialProto.REJECT_TEXT[clampi(reason, 0, SocialProto.REJECT_TEXT.size() - 1)])
	changed.emit()


## A message from the host (or the host's own): checked, then stored.
func _receive(seq: int, slot: int, channel: int, kind: int, nonce: int, phrase: int, token: String, text: String) -> void:
	if seq <= 0 or _seen_seq.has(seq):
		return
	if slot < 0 or slot > 7 or session.roster[slot] == null or bool(session.roster[slot]["is_bot"]):
		return
	var e: Dictionary = session.roster[slot]
	var mine := slot == session.local_slot
	if not session.is_host():
		# only channels this device may see
		if channel == QuickChat.Channel.TEAM and not mine and role_of(slot) != role_of(session.local_slot):
			return
		var now: float = now_fn.call()
		var times: Array = (_recv.get(slot, []) as Array).filter(func(x: float) -> bool: return now - x < RECV_WINDOW_S)
		if times.size() >= RECV_MAX and not mine:
			_recv[slot] = times
			return
		times.append(now)
		_recv[slot] = times
		if kind == SocialProto.Kind.QUICK:
			if not QuickChat.allowed(phrase, channel, role_of(slot)):
				return
		else:
			var v := ChatToken.verify(token, _key(), {"room": session.room_code, "sub": String(e.get("pid", "")), "seen": _seen_jti})
			if not bool(v["ok"]):
				return
			text = String(v["claims"]["text"])
			_seen_jti[String(v["claims"]["jti"])] = true
	_seen_seq[seq] = true
	if not mine and SocialSafety.is_hidden(session, String(e["uid"]), String(e.get("pid", ""))):
		return
	if mine and nonce > 0 and _pending.has(nonce):
		var pm: Dictionary = _pending[nonce]
		_pending.erase(nonce)
		history.erase(pm)
	var msg := _make(seq, slot, channel, kind, phrase, text, token)
	msg["mine"] = mine
	_insert(msg)
	if not mine:
		unread += 1
	changed.emit()


func _make(seq: int, slot: int, channel: int, kind: int, phrase: int, text: String, token: String) -> Dictionary:
	var e: Variant = session.roster[slot] if slot >= 0 and slot <= 7 else null
	return {"seq": seq, "from": slot, "uid": String(e["uid"]) if e != null else "", "pid": String(e.get("pid", "")) if e != null else "",
		"name": String(e["name"]) if e != null else "", "channel": channel, "kind": kind, "phrase": phrase,
		"text": QuickChat.text(phrase) if kind == SocialProto.Kind.QUICK else text, "token": token,
		"at": now_fn.call(), "mine": false, "state": "sent", "round": session.round_no}


## Ordered by the host's sequence (pending messages of ours stay last).
func _insert(msg: Dictionary) -> void:
	var at := history.size()
	if int(msg["seq"]) > 0:
		while at > 0 and (int(history[at - 1]["seq"]) <= 0 or int(history[at - 1]["seq"]) > int(msg["seq"])):
			at -= 1
	history.insert(at, msg)
	while history.size() > HISTORY_MAX:
		history.pop_front()
	changed.emit()


## Messages to show for a set of channels (blocked/muted senders removed
## again in case a block happened after they arrived).
func visible(channels: Array, round_no: int = -1) -> Array:
	var out: Array = []
	for m in history:
		if not channels.has(int(m["channel"])):
			continue
		if round_no >= 0 and int(m["round"]) != round_no:
			continue
		if not bool(m["mine"]) and SocialSafety.is_hidden(session, String(m["uid"]), String(m["pid"])):
			continue
		out.append(m)
	return out


## A mute or block hides what is already on screen too.
func forget_sender(uid: String) -> void:
	history = history.filter(func(m: Dictionary) -> bool: return bool(m["mine"]) or String(m["uid"]) != uid)
	changed.emit()


## The shown name of a message's sender (blocked players stay hidden).
func sender_name(m: Dictionary) -> String:
	if bool(m["mine"]):
		return "You"
	var slot := int(m["from"])
	var e: Variant = session.roster[slot] if slot >= 0 and slot <= 7 else null
	if e != null and String(e["uid"]) == String(m["uid"]):
		return SocialSafety.name_of(e)
	return SocialSafety.name_of({"uid": m["uid"], "pid": m["pid"], "name": m["name"]})
