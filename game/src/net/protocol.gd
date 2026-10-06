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
## Protocol 7 (Pass 8): the motor state's flags carry the sprint-exhausted
## latch (bit 8) and the dive/landing rules changed, so a 1.7 peer can't
## predict a 1.8 host; RESULTS rows carry active_s (challenges), bound into
## the economy row digest (Economy.row_canonical v2), so a 6 and a 7 game
## can't confirm each other's rounds. Mismatched versions are refused at join.
## The private snapshot block ends with the live runner pace, for runner
## recipients only: their own suggested next goal (u8: target index, 16 +
## home door, 255 none) and, per runner, slot + place/flags + stamps (3 bytes
## each).  Never a position or another runner's goal.
## Protocol 8 (Pass 9): no sprint. The movement rules changed (one steady
## full-input speed: runner 6.0 m/s, no meter, latch or Sprint button), so a
## 1.8 peer would mispredict a 1.9 host. The motor state loses the meter and
## its refill delay (two floats) and its flags bit 1 means "fast" (at or near
## full speed; bit 8, the latch, is retired); snapshot player flag 4 is
## "fast" too; the private block loses the meter byte. A 7 and an 8 game
## refuse each other at join ("Update the game to join.").
## Protocol 9 (reference campus): the campus is about 1.2 x 1.0 km, beyond the
## +-512 m an int16 at 1/64 m can hold, so world positions carry x and z as
## 24-bit signed values (same 1/64 m precision, +-131 km); y stays int16.
## START names the campus data's hash (`campus`) so two builds with different
## maps can never share a round.  An 8 and a 9 game refuse each other at join.
const VERSION := 9

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
	LOADED,         # client -> host: {round} match scene ready (load ack); V6: {round, progress 0..254} while still preparing
	SERIES,         # host -> all: series standings and completed rounds (JSON)
}

## Messages a client accepts only from its bound host (protocol 4).
const HOST_ONLY := [M.WELCOME, M.LOBBY, M.START, M.SNAP, M.EVENTS, M.RESULTS, M.HOST_END, M.KICK, M.SERIES]
## Hard upper bounds for reads (bytes)
const MAX_STR := 64
const MAX_TOKEN := 4096
const MAX_JSON := 32768

const POS_SCALE := 64.0     # 1/64 m precision; x/z 24-bit (+-131 km), y int16 (+-512 m)
const POS_MAX24 := 8388607
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
	_put_24(b, clampi(int(round(v.x * POS_SCALE)), -POS_MAX24, POS_MAX24))
	b.put_16(clampi(int(round(v.y * POS_SCALE)), -32767, 32767))
	_put_24(b, clampi(int(round(v.z * POS_SCALE)), -POS_MAX24, POS_MAX24))


static func get_vec3(b: StreamPeerBuffer) -> Vector3:
	var x := _get_24(b)
	var y := b.get_16()
	var z := _get_24(b)
	return Vector3(float(x) / POS_SCALE, float(y) / POS_SCALE, float(z) / POS_SCALE)


## 24-bit two's complement: the low byte, then the signed high 16 bits.
static func _put_24(b: StreamPeerBuffer, v: int) -> void:
	b.put_u8(v & 0xFF)
	b.put_16(v >> 8)


static func _get_24(b: StreamPeerBuffer) -> int:
	var lo := b.get_u8()
	var hi := b.get_16()
	return (hi << 8) | lo


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
const PF_FAST := 4       # Pass 9: at or near full speed (was PF_SPRINT)
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
		if sp.fast: f |= PF_FAST
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
		put_pace(b, sim, recipient)
	return b.data_array


## Pass 8 (protocol 7): the live runner pace for a runner recipient.  The
## Night Watch (and anything before the round is under way) gets an empty
## block: pace is the runners' own progress display.
const PACE_TIED := 16
const PACE_APPROX := 32
const PACE_HOME := 64


static func put_pace(b: StreamPeerBuffer, sim: MatchSim, recipient: SimPlayer) -> void:
	var pc: RunnerPace = sim.pace
	if pc == null or recipient == null or not recipient.is_runner() or sim.phase < TC.Phase.PLAYING:
		b.put_u8(RunnerPace.NO_GOAL)
		b.put_u8(0)
		return
	b.put_u8(clampi(int(pc.next_goal.get(recipient.id, RunnerPace.NO_GOAL)), 0, 255))
	var slots: Array = pc.places.keys()
	slots.sort()
	b.put_u8(mini(slots.size(), 8))
	for i in mini(slots.size(), 8):
		var e: Dictionary = pc.places[slots[i]]
		var f := clampi(int(e["place"]), 0, 15)
		if bool(e["tied"]):
			f |= PACE_TIED
		if bool(e["approx"]):
			f |= PACE_APPROX
		if bool(e["home"]):
			f |= PACE_HOME
		b.put_u8(int(slots[i]))
		b.put_u8(f)
		b.put_u8(clampi(int(e["stamps"]), 0, 3))


static func get_pace(b: StreamPeerBuffer, me: Dictionary) -> void:
	me["next_goal"] = RunnerPace.NO_GOAL
	me["pace"] = {}
	if b.get_available_bytes() < 2:
		return
	me["next_goal"] = b.get_u8()
	var n := b.get_u8()
	if n > 8 or b.get_available_bytes() < n * 3:
		return
	var out := {}
	for i in n:
		var slot := b.get_u8()
		var f := b.get_u8()
		var st := b.get_u8()
		out[slot] = {"place": f & 15, "tied": (f & PACE_TIED) != 0, "approx": (f & PACE_APPROX) != 0,
			"home": (f & PACE_HOME) != 0, "stamps": clampi(st, 0, 3)}
	me["pace"] = out


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
		e["fast"] = (f & PF_FAST) != 0
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
		get_pace(b, me)
		s["me"] = me
	return s
