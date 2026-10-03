class_name Protocol
extends RefCounted
## Binary wire protocol. Every message starts with a type byte. Snapshots are
## per-recipient (relevance filtered) and kept well under 1000 bytes so they
## fit a single unreliable GameKit/ENet packet.

## 4 (V3): event field m (splash impact), snapshot impact byte, appearance
## schema 2 wire format, host-bound control messages.
## 5 (V4): party settings (Night Watch count, rounds) and series state in
## LOBBY, settings + series in START, SERIES standings, load-ready flags,
## tag-ready/target fields in the private snapshot block.
## 6 (V6): the round configuration in START names tonight's home dorm
## (id, geometry version and fingerprint, slot -> spawn pad), the round's
## coins and its start timing; snapshots carry the coins still out (u16)
## and, privately, the recipient's coin count (u8); EVENTS gain
## COIN_PICKUP.  Message types 60-79 are reserved for the V6 social
## messages (chat / hub); none of them is defined here.
const VERSION := 6

enum M {
	ANNOUNCE = 1,   # any -> all: {is_host, uid, room_code}
	HELLO,          # client -> host: {ver, uid, name, cosmetic, pref}
	WELCOME,        # host -> client: {slot, reason}
	LOBBY,          # host -> all: roster + settings
	READY,          # client -> host: {ready, pref}
	COSMETIC,       # client -> host: {cosmetic}
	EMOTE,          # client -> host: {emote}
	START,          # host -> all: match start info
	INPUT,          # client -> host: redundant input window
	SNAP,           # host -> client: world snapshot
	EVENTS,         # host -> client: reliable gameplay events
	RESULTS,        # host -> all: authoritative results (JSON)
	PING,
	PONG,
	LEAVE,          # client -> host
	HOST_END,       # host -> all: room closing / round cancelled
	KICK,           # host -> client
	MUTE,           # unused on wire (local block list)
	LOADED,         # client -> host: {round} match scene ready (load ack)
	SERIES,         # host -> all: series standings and completed rounds (JSON)
}

## Messages a client accepts only from its bound host (protocol 4).
const HOST_ONLY := [M.WELCOME, M.LOBBY, M.START, M.SNAP, M.EVENTS, M.RESULTS, M.HOST_END, M.KICK, M.SERIES]
## Hard upper bounds for reads (bytes)
const MAX_STR := 64
const MAX_TOKEN := 4096
const MAX_JSON := 32768

const POS_SCALE := 64.0     # 1/64 m precision, int16 range +-512 m
const VEL_SCALE := 100.0


static func buf_for(type: int) -> StreamPeerBuffer:
	var b := StreamPeerBuffer.new()
	b.big_endian = false
	b.put_u8(type)
	return b


static func reader(data: PackedByteArray) -> StreamPeerBuffer:
	var b := StreamPeerBuffer.new()
	b.big_endian = false
	b.data_array = data
	return b


static func put_str(b: StreamPeerBuffer, s: String, max_len: int = 64) -> void:
	var u := s.substr(0, max_len).to_utf8_buffer()
	b.put_u8(mini(u.size(), 255))
	b.put_data(u.slice(0, mini(u.size(), 255)))


static func get_str(b: StreamPeerBuffer, max_len: int = MAX_STR) -> String:
	if b.get_available_bytes() < 1:
		return ""
	var n := b.get_u8()
	if n == 0 or n > b.get_available_bytes():
		return ""
	var r: Array = b.get_data(n)
	if r[0] != OK:
		return ""
	var s := (r[1] as PackedByteArray).get_string_from_utf8()
	return s.substr(0, max_len)


## Long strings (admission tokens): u16 length, bounded.
static func put_long_str(b: StreamPeerBuffer, s: String) -> void:
	var u := s.to_utf8_buffer()
	if u.size() > MAX_TOKEN:
		u = PackedByteArray()
	b.put_u16(u.size())
	b.put_data(u)


static func get_long_str(b: StreamPeerBuffer) -> String:
	if b.get_available_bytes() < 2:
		return ""
	var n := b.get_u16()
	if n == 0 or n > MAX_TOKEN or n > b.get_available_bytes():
		return ""
	var r: Array = b.get_data(n)
	return (r[1] as PackedByteArray).get_string_from_utf8() if r[0] == OK else ""


## Length-prefixed JSON object (START, RESULTS), bounded; {} if malformed.
static func get_json(b: StreamPeerBuffer) -> Dictionary:
	if b.get_available_bytes() < 4:
		return {}
	var n := b.get_u32()
	if n == 0 or n > MAX_JSON or n > b.get_available_bytes():
		return {}
	var r: Array = b.get_data(n)
	if r[0] != OK:
		return {}
	var parsed: Variant = JSON.parse_string((r[1] as PackedByteArray).get_string_from_utf8())
	return parsed if parsed is Dictionary else {}


static func put_vec3(b: StreamPeerBuffer, v: Vector3) -> void:
	b.put_16(clampi(int(round(v.x * POS_SCALE)), -32767, 32767))
	b.put_16(clampi(int(round(v.y * POS_SCALE)), -32767, 32767))
	b.put_16(clampi(int(round(v.z * POS_SCALE)), -32767, 32767))


static func get_vec3(b: StreamPeerBuffer) -> Vector3:
	return Vector3(float(b.get_16()) / POS_SCALE, float(b.get_16()) / POS_SCALE, float(b.get_16()) / POS_SCALE)


static func put_vel(b: StreamPeerBuffer, v: Vector3) -> void:
	b.put_16(clampi(int(round(v.x * VEL_SCALE)), -32767, 32767))
	b.put_16(clampi(int(round(v.y * VEL_SCALE)), -32767, 32767))
	b.put_16(clampi(int(round(v.z * VEL_SCALE)), -32767, 32767))


static func get_vel(b: StreamPeerBuffer) -> Vector3:
	return Vector3(float(b.get_16()) / VEL_SCALE, float(b.get_16()) / VEL_SCALE, float(b.get_16()) / VEL_SCALE)


static func put_angle(b: StreamPeerBuffer, a: float) -> void:
	b.put_u16(int(fposmod(a, TAU) / TAU * 65535.0) & 0xFFFF)


static func get_angle(b: StreamPeerBuffer) -> float:
	return float(b.get_u16()) / 65535.0 * TAU


# ---------------------------------------------------------------------------
# Events (reliable)
# ---------------------------------------------------------------------------
static func encode_events(events: Array) -> PackedByteArray:
	var b := buf_for(M.EVENTS)
	b.put_u8(mini(events.size(), 255))
	for i in mini(events.size(), 255):
		var e: Dictionary = events[i]
		b.put_u32(int(e["id"]))
		b.put_u32(int(e["t"]))
		b.put_u8(int(e["type"]))
		b.put_8(int(e["a"]))
		b.put_8(int(e["b"]))
		b.put_16(int(e["v"]))
		put_vec3(b, e["pos"])
		b.put_u8(clampi(int(e.get("m", 0)), 0, 255))
	return b.data_array


static func decode_events(b: StreamPeerBuffer) -> Array:
	var out: Array = []
	var n := b.get_u8()
	for i in n:
		out.append({
			"id": b.get_u32(), "t": b.get_u32(), "type": b.get_u8(), "a": b.get_8(),
			"b": b.get_8(), "v": b.get_16(), "pos": get_vec3(b), "m": b.get_u8(),
		})
	return out


## Appearance: u8 length + Cosmetics wire bytes (schema 2, versioned).  The
## read is bounded and always yields a valid appearance.
static func put_appearance(b: StreamPeerBuffer, c: Dictionary) -> void:
	var a := Cosmetics.encode(c)
	b.put_u8(a.size())
	b.put_data(a)


static func get_appearance(b: StreamPeerBuffer) -> Dictionary:
	var n := b.get_u8()
	if n == 0 or n > Cosmetics.max_wire_size() or b.get_available_bytes() < n:
		return Cosmetics.DEFAULT.duplicate()
	var r: Array = b.get_data(n)
	return Cosmetics.decode(r[1] if r[0] == OK else PackedByteArray())


# ---------------------------------------------------------------------------
# Inputs (unreliable, redundant window so a lost packet costs nothing)
# ---------------------------------------------------------------------------
static func encode_inputs(cmds: Array, emote: int = -1) -> PackedByteArray:
	var b := buf_for(M.INPUT)
	b.put_u8(mini(cmds.size(), 10))
	for i in range(maxi(0, cmds.size() - 10), cmds.size()):
		(cmds[i] as InputCmd).write(b)
	b.put_8(emote)
	return b.data_array


static func decode_inputs(b: StreamPeerBuffer) -> Dictionary:
	if b.get_available_bytes() < 1 or b.get_available_bytes() > 512:
		return {"cmds": [], "emote": -1}
	var n := b.get_u8()
	var cmds: Array = []
	for i in mini(n, 10):
		if b.get_available_bytes() < 14:
			break
		cmds.append(InputCmd.read(b))
	var emote := -1
	if b.get_available_bytes() > 0:
		emote = b.get_8()
	return {"cmds": cmds, "emote": emote}


# ---------------------------------------------------------------------------
# Snapshot (per recipient)
# ---------------------------------------------------------------------------
## flags bits for a player entry
const PF_FLOOR := 1
const PF_DIVING := 2
const PF_SPRINT := 4
const PF_PROTECT := 8
const PF_BUMPPROT := 16
const PF_SPOTTED := 32
const PF_CONNECTED := 64
const PF_BOT := 128


static func encode_snapshot(sim: MatchSim, recipient: SimPlayer, relevant: Array, ack_seq: int, own_motor: bool) -> PackedByteArray:
	var b := buf_for(M.SNAP)
	b.put_u32(sim.tick)
	b.put_u8(sim.phase)
	b.put_u32(maxi(sim.phase_tick, 0))
	b.put_u32(maxi(sim.end_tick, 0))
	b.put_u32(maxi(sim.round_start_tick, 0))
	b.put_u8(sim.finished_count)
	b.put_u32(maxi(ack_seq, 0))
	b.put_u16(sim.coin_mask())
	# players
	b.put_u8(relevant.size())
	for p in relevant:
		var sp: SimPlayer = p
		b.put_u8(sp.id)
		b.put_u8(sp.state)
		var f := 0
		if sp.on_floor: f |= PF_FLOOR
		if sp.diving: f |= PF_DIVING
		if sp.sprinting: f |= PF_SPRINT
		if sp.protect > 0.0: f |= PF_PROTECT
		if sp.bump_protect > 0.0: f |= PF_BUMPPROT
		if sp.spotted > 0.0: f |= PF_SPOTTED
		if sp.connected: f |= PF_CONNECTED
		if sp.is_bot or sp.bot_takeover: f |= PF_BOT
		b.put_u8(f)
		put_vec3(b, sp.pos())
		put_vel(b, sp.vel)
		put_angle(b, sp.yaw)
		b.put_u8(sp.tag_phase)
		b.put_u8(sp.stamps)
		b.put_8(sp.cart_id)
		b.put_8(sp.emote if sp.emote_t > 0.0 else -1)
		b.put_u8(clampi(int(sp.state_t * 20.0), 0, 255))
		b.put_u8(sp.splash_impact)
	# carts (all; they are loud and large)
	b.put_u8(sim.carts.size())
	for c in sim.carts:
		put_vec3(b, c.pos())
		put_angle(b, c.yaw)
		b.put_16(int(round(c.speed * 100.0)))
		b.put_8(int(round(c.steer_s * 100.0)))
		b.put_8(c.occupant)
		b.put_u8(1 if c.slowed_t > 0.0 else 0)
	# private block for the recipient
	b.put_u8(1 if recipient != null else 0)
	if recipient != null:
		b.put_u8(recipient.id)
		b.put_u8(int(recipient.sprint * 255.0))
		b.put_u8(recipient.gadget)
		b.put_u8(int(clampf(recipient.gadget_cd, 0.0, 12.0) * 20.0))
		b.put_u8(int(clampf(recipient.penalty, 0.0, 12.0) * 20.0))
		b.put_u8(int(clampf(recipient.turbo_t, 0.0, 12.0) * 20.0))
		b.put_u8(int(clampf(recipient.spotted, 0.0, 12.0) * 20.0))
		b.put_u8(1 if recipient.spotted_by_cart else 0)
		# Night Watch cues: tag-ready and the runner the assist would pick
		b.put_u8(1 if recipient.tag_ready else 0)
		b.put_8(recipient.tag_aim)
		b.put_u8(clampi(recipient.coins_picked, 0, 255))
		b.put_u8(1 if own_motor else 0)
		if own_motor:
			recipient.write_motor(b)
			if recipient.cart_id >= 0:
				sim.carts[recipient.cart_id].write_motor(b)
		# hearing: anonymous noise sources
		var noises := sim.noises_for(recipient)
		b.put_u8(mini(noises.size(), 8))
		for i in mini(noises.size(), 8):
			var n: Dictionary = noises[i]
			put_vec3(b, (n["pos"] as Vector3).snapped(Vector3(1, 1, 1)))
			b.put_u8(0 if n["kind"] == "steps" else 1)
			b.put_u8(int(clampf(float(n["loud"]), 0.0, 1.0) * 255.0))
		# splash markers (patrol only), pickups availability bitmask
		var marks: Array = sim.splash_markers if recipient.is_patrol() else []
		b.put_u8(marks.size())
		for m in marks:
			b.put_u8(int(m["water"]))
			b.put_u8(int(clampf(float(m["t"]), 0.0, 12.0) * 20.0))
		var mask := 0
		for i in sim.pickups.size():
			if float(sim.pickups[i]["respawn"]) <= 0.0:
				mask |= (1 << i)
		b.put_u16(mask)
		# decoys + bombs visible near the recipient (presentation)
		var fx: Array = []
		for d in sim.decoys:
			if (d["pos"] as Vector3).distance_to(recipient.pos()) < 40.0:
				fx.append([0, d["pos"]])
		for bm in sim.bombs:
			fx.append([1, bm["to"]])
		b.put_u8(mini(fx.size(), 6))
		for i in mini(fx.size(), 6):
			b.put_u8(int(fx[i][0]))
			put_vec3(b, fx[i][1])
	return b.data_array


static func decode_snapshot(b: StreamPeerBuffer) -> Dictionary:
	var s := {}
	s["tick"] = b.get_u32()
	s["phase"] = b.get_u8()
	s["phase_tick"] = b.get_u32()
	s["end_tick"] = b.get_u32()
	s["round_start"] = b.get_u32()
	s["finished"] = b.get_u8()
	s["ack"] = b.get_u32()
	s["coins"] = b.get_u16()
	var players := {}
	var n := b.get_u8()
	if n > 8:
		return {}
	for i in n:
		var e := {}
		var id := b.get_u8()
		e["state"] = b.get_u8()
		var f := b.get_u8()
		e["on_floor"] = (f & PF_FLOOR) != 0
		e["diving"] = (f & PF_DIVING) != 0
		e["sprinting"] = (f & PF_SPRINT) != 0
		e["protect"] = 1.0 if (f & PF_PROTECT) != 0 else 0.0
		e["bump_protect"] = 1.0 if (f & PF_BUMPPROT) != 0 else 0.0
		e["spotted"] = (f & PF_SPOTTED) != 0
		e["connected"] = (f & PF_CONNECTED) != 0
		e["bot"] = (f & PF_BOT) != 0
		e["pos"] = get_vec3(b)
		e["vel"] = get_vel(b)
		e["yaw"] = get_angle(b)
		e["tag_phase"] = b.get_u8()
		e["stamps"] = b.get_u8()
		e["cart_id"] = b.get_8()
		e["emote"] = b.get_8()
		e["emote_t"] = 1.0 if e["emote"] >= 0 else 0.0
		e["state_t"] = float(b.get_u8()) / 20.0
		e["impact"] = b.get_u8()
		players[id] = e
	s["players"] = players
	var carts: Array = []
	var nc := b.get_u8()
	if nc > 8:
		return {}
	for i in nc:
		carts.append({
			"pos": get_vec3(b), "yaw": get_angle(b), "speed": float(b.get_16()) / 100.0,
			"steer": float(b.get_8()) / 100.0, "occupant": b.get_8(), "slowed": b.get_u8() == 1,
		})
	s["carts"] = carts
	if b.get_u8() == 1:
		var me := {}
		me["slot"] = b.get_u8()
		me["sprint"] = float(b.get_u8()) / 255.0
		me["gadget"] = b.get_u8()
		me["gadget_cd"] = float(b.get_u8()) / 20.0
		me["penalty"] = float(b.get_u8()) / 20.0
		me["turbo_t"] = float(b.get_u8()) / 20.0
		me["spotted"] = float(b.get_u8()) / 20.0
		me["spotted_by_cart"] = b.get_u8() == 1
		me["tag_ready"] = b.get_u8() == 1
		me["tag_aim"] = b.get_8()
		me["coins_picked"] = b.get_u8()
		var has_motor := b.get_u8() == 1
		if has_motor:
			var tmp := SimPlayer.new()
			me["motor"] = tmp.read_motor(b)
			if int(me["motor"]["cart_id"]) >= 0:
				me["cart_motor"] = SimCart.read_motor(b)
		var noises: Array = []
		var nn := b.get_u8()
		for i in nn:
			noises.append({"pos": get_vec3(b), "kind": "steps" if b.get_u8() == 0 else "cart", "loud": float(b.get_u8()) / 255.0})
		me["noises"] = noises
		var marks: Array = []
		var nm := b.get_u8()
		for i in nm:
			marks.append({"water": b.get_u8(), "t": float(b.get_u8()) / 20.0})
		me["markers"] = marks
		me["pickups"] = b.get_u16()
		var fx: Array = []
		var nf := b.get_u8()
		for i in nf:
			fx.append({"kind": b.get_u8(), "pos": get_vec3(b)})
		me["fx"] = fx
		s["me"] = me
	return s
