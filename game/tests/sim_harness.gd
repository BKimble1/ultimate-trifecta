class_name SimHarness
extends RefCounted
## Helpers to build a MatchSim with scripted (non-bot) players and drive it
## tick by tick inside physics frames.

var t   # test runner node
var sim: MatchSim
var inputs: Dictionary = {}


func _init(runner) -> void:
	t = runner


## roles: Array of TC.Role, one per slot. bots: slots driven by BotBrain.
## opts (V6): "dorm" (home dorm id, default: the map's default), "coins",
## "map" (a CampusMaps id, default the reference campus).
func make(roles: Array, targets: Array = [0, 1, 2], bots: Array = [], seed_v: int = 11, opts: Dictionary = {}) -> MatchSim:
	sim = MatchSim.new()
	t.add_child(sim)
	var roster: Array = []
	for i in roles.size():
		roster.append({"slot": i, "uid": "u%d" % i, "name": "P%d" % i, "is_bot": bots.has(i), "role": roles[i], "cosmetic": {}})
	var o := {"bot_factory": func(s: MatchSim, p: SimPlayer) -> BotBrain: return BotBrain.new(s, p)}
	o.merge(opts, true)
	sim.setup(Rules.cfg, CampusMaps.layout(String(opts.get("map", CampusMaps.DEFAULT_ID))), roster, seed_v, targets, "test-%d" % seed_v, o)
	return sim


func free_sim() -> void:
	if sim and is_instance_valid(sim):
		sim.queue_free()
	sim = null


func step(n: int = 1) -> void:
	for i in n:
		await t.get_tree().physics_frame
		var cmds := {}
		for slot in inputs:
			var c: InputCmd = inputs[slot]
			cmds[slot] = c
		sim.step(cmds)
		# edges are one-shot
		for slot in inputs:
			(inputs[slot] as InputCmd).pressed = 0


func to_playing() -> void:
	while sim.phase != TC.Phase.PLAYING:
		await step()


func release_patrol() -> void:
	await to_playing()
	while sim.patrol_release_left() > 0.0:
		await step()
	await step()


func cmd(slot: int) -> InputCmd:
	if not inputs.has(slot):
		inputs[slot] = InputCmd.new()
	return inputs[slot]


func press(slot: int, bit: int) -> void:
	cmd(slot).pressed |= bit


func place(slot: int, pos: Vector3, yaw: float = 0.0) -> void:
	var p := sim.player(slot)
	p.body.global_position = pos
	p.vel = Vector3.ZERO
	p.body.velocity = Vector3.ZERO
	p.yaw = yaw
	p.clear_history()


## Drop a runner into a water body and wait for the full splash sequence.
func splash_into(slot: int, water_index: int) -> void:
	var w: Dictionary = sim.layout.waters[water_index]
	var c: Vector2 = w["center"]
	place(slot, Vector3(c.x + drop_offset(w), float(w["surface_y"]) + 1.2, c.y))
	var guard := 0
	while sim.player(slot).state != TC.PState.SPLASHING and guard < 120:
		await step()
		guard += 1
	while sim.player(slot).state == TC.PState.SPLASHING and guard < 400:
		await step()
		guard += 1


## A point inside the water footprint that avoids pedestals and docks.
static func drop_offset(w: Dictionary) -> float:
	match String(w["shape"]):
		"circle":
			return -float(w["radius"]) * 0.58
		"ellipse":
			return -float(w["rx"]) * 0.5
		"rect":
			return -float(w["size"].x) * 0.25
	return 0.0


## Just outside home door i (V6: outside the threshold, nothing happens
## there; enter_door walks in).
func door_point(i: int = 0) -> Vector3:
	var d: Dictionary = sim.home_doors[i % sim.home_doors.size()]
	var p: Vector2 = (d["pos"] as Vector2) + (d["normal"] as Vector2) * 0.9
	return Vector3(p.x, 0.05, p.y)


## Puts a runner in home door i's opening, 6 cm short of the threshold and
## running in at 5 m/s: the next tick crosses it.
func cross_next_tick(slot: int, i: int = 0) -> void:
	var d: Dictionary = sim.home_doors[i % sim.home_doors.size()]
	var lp: Vector2 = d["line_p"]
	var n_in: Vector2 = d["n_in"]
	var n := Vector3(n_in.x, 0, n_in.y)
	place(slot, Vector3(lp.x, 0.05, lp.y) - n * 0.06, atan2(-n.x, -n.z))
	var p := sim.player(slot)
	p.vel = n * 5.0
	p.body.velocity = p.vel
	cmd(slot).move = n_in


## Walks a runner in through home door i the way a player would: placed
## outside, then pushing the stick inward until it is home (or `max_ticks`).
## Returns true once the runner has finished.
func enter_door(slot: int, i: int = 0, max_ticks: int = 90) -> bool:
	var d: Dictionary = sim.home_doors[i % sim.home_doors.size()]
	var n_in: Vector2 = d["n_in"]
	place(slot, door_point(i), atan2(-n_in.x, -n_in.y))
	cmd(slot).move = n_in
	var p := sim.player(slot)
	for k in max_ticks:
		await step()
		if p.state == TC.PState.FINISHED or sim.phase != TC.Phase.PLAYING:
			break
	cmd(slot).move = Vector2.ZERO
	return p.state == TC.PState.FINISHED


func events_of(type: int) -> Array:
	return sim.events.filter(func(e): return int(e["type"]) == type)


## Steps until an event of `type` appears (returns it) or max ticks pass.
func wait_event(type: int, max_ticks: int = 600) -> Dictionary:
	for i in max_ticks:
		await step()
		for e in sim.events:
			if int(e["type"]) == type:
				return e
	return {}
