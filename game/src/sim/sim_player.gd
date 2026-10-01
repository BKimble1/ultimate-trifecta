class_name SimPlayer
extends RefCounted
## Authoritative per-player state. Lives on the host (and in practice mode).
## The client keeps one for its own predicted character.

enum TagPhase { NONE, ANTICIPATE, LUNGE, RECOVER }

var id: int = 0                 # roster slot 0..7
var uid: String = ""            # stable identity for reconnect (Game Center id or local id)
var display_name: String = ""
var is_bot := false
var bot_takeover := false       # human slot temporarily driven by a bot after disconnect
var connected := true
var disconnect_t := 0.0
var role: int = TC.Role.RUNNER
var cosmetic: Dictionary = {}

var body: CharacterBody3D

# motor state
var vel := Vector3.ZERO
var yaw: float = 0.0
var state: int = TC.PState.ACTIVE
var state_t: float = 0.0
var sprint: float = 1.0
var sprint_delay: float = 0.0
var sprinting := false
var coyote: float = 0.0
var jump_buf: float = 0.0
var on_floor := true
var air_t: float = 0.0
var diving := false
var dive_land: float = 0.0
var turbo_t: float = 0.0
var tag_phase: int = TagPhase.NONE
var tag_t: float = 0.0
var tag_cd: float = 0.0
var tag_lockout: float = 0.0
var protect: float = 0.0
var bump_protect: float = 0.0
var jumped_this_tick := false
var landed_this_tick := false

# rules state
var stamps: int = 0                 # bit i => active target i stamped
var stamp_order: Array[int] = []    # water indices in the order earned
var last_stamp_water: int = -1
var finished_tick: int = -1
var finish_order: int = 0
var times_captured: int = 0
var captures: int = 0
var captured_ids: Dictionary = {}   # unique runner ids tagged (patrol)
var penalty: float = 0.0
var splash_water: int = -1
var splash_exit := Vector3.ZERO
var splash_stamped := false
var cart_id: int = -1
var gadget: int = TC.Gadget.NONE
var gadget_cd: float = 0.0
var spotted: float = 0.0
var spotted_by_cart := false
var last_input: InputCmd = InputCmd.new()
var last_seq: int = -1
var lag_ticks: int = 0
var emote: int = -1
var emote_t: float = 0.0
var stuck_t: float = 0.0
var pos_history: Array[Vector3] = []   # ring buffer of recent positions (lag comp)
var hist_head: int = 0
const HIST := 24


func pos() -> Vector3:
	return body.global_position if body else Vector3.ZERO


func pos2() -> Vector2:
	var p := pos()
	return Vector2(p.x, p.z)


func facing() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func is_runner() -> bool:
	return role == TC.Role.RUNNER


func is_patrol() -> bool:
	return role == TC.Role.PATROL


func stamp_count() -> int:
	var n := 0
	for i in 3:
		if stamps & (1 << i):
			n += 1
	return n


func is_taggable() -> bool:
	return is_runner() and (state == TC.PState.ACTIVE or state == TC.PState.STUMBLE) and protect <= 0.0 and bump_protect <= 0.0


func is_in_play() -> bool:
	return state != TC.PState.FINISHED and state != TC.PState.CAPTURED and state != TC.PState.SPLASHING


func push_history() -> void:
	if pos_history.size() < HIST:
		pos_history.append(pos())
		hist_head = pos_history.size() - 1
	else:
		hist_head = (hist_head + 1) % HIST
		pos_history[hist_head] = pos()


func history_pos(ticks_ago: int) -> Vector3:
	if pos_history.is_empty():
		return pos()
	var n := clampi(ticks_ago, 0, pos_history.size() - 1)
	var idx := (hist_head - n + HIST * 4) % pos_history.size()
	return pos_history[idx]


func clear_history() -> void:
	pos_history.clear()
	hist_head = 0


## Motor state needed to re-simulate this player's movement exactly (prediction).
func write_motor(buf: StreamPeerBuffer) -> void:
	var p := pos()
	buf.put_float(p.x)
	buf.put_float(p.y)
	buf.put_float(p.z)
	buf.put_float(vel.x)
	buf.put_float(vel.y)
	buf.put_float(vel.z)
	buf.put_float(yaw)
	buf.put_u8(state)
	buf.put_float(state_t)
	buf.put_float(sprint)
	buf.put_float(sprint_delay)
	var flags := 0
	if sprinting: flags |= 1
	if on_floor: flags |= 2
	if diving: flags |= 4
	buf.put_u8(flags)
	buf.put_float(coyote)
	buf.put_float(jump_buf)
	buf.put_float(dive_land)
	buf.put_float(turbo_t)
	buf.put_u8(tag_phase)
	buf.put_float(tag_t)
	buf.put_float(tag_cd)
	buf.put_float(tag_lockout)
	buf.put_8(cart_id)
	buf.put_float(air_t)
	buf.put_float(stuck_t)


func read_motor(buf: StreamPeerBuffer) -> Dictionary:
	var d := {}
	d["pos"] = Vector3(buf.get_float(), buf.get_float(), buf.get_float())
	d["vel"] = Vector3(buf.get_float(), buf.get_float(), buf.get_float())
	d["yaw"] = buf.get_float()
	d["state"] = buf.get_u8()
	d["state_t"] = buf.get_float()
	d["sprint"] = buf.get_float()
	d["sprint_delay"] = buf.get_float()
	var flags := buf.get_u8()
	d["sprinting"] = (flags & 1) != 0
	d["on_floor"] = (flags & 2) != 0
	d["diving"] = (flags & 4) != 0
	d["coyote"] = buf.get_float()
	d["jump_buf"] = buf.get_float()
	d["dive_land"] = buf.get_float()
	d["turbo_t"] = buf.get_float()
	d["tag_phase"] = buf.get_u8()
	d["tag_t"] = buf.get_float()
	d["tag_cd"] = buf.get_float()
	d["tag_lockout"] = buf.get_float()
	d["cart_id"] = buf.get_8()
	d["air_t"] = buf.get_float()
	d["stuck_t"] = buf.get_float()
	return d


func apply_motor(d: Dictionary) -> void:
	if body:
		body.global_position = d["pos"]
	vel = d["vel"]
	if body:
		body.velocity = vel
	yaw = d["yaw"]
	state = d["state"]
	state_t = d["state_t"]
	sprint = d["sprint"]
	sprint_delay = d["sprint_delay"]
	sprinting = d["sprinting"]
	on_floor = d["on_floor"]
	diving = d["diving"]
	coyote = d["coyote"]
	jump_buf = d["jump_buf"]
	dive_land = d["dive_land"]
	turbo_t = d["turbo_t"]
	tag_phase = d["tag_phase"]
	tag_t = d["tag_t"]
	tag_cd = d["tag_cd"]
	tag_lockout = d["tag_lockout"]
	cart_id = d["cart_id"]
	air_t = d.get("air_t", 0.0)
	stuck_t = d.get("stuck_t", 0.0)
