class_name MatchSim
extends Node3D
## Authoritative Trifecta Chase simulation. Runs on the room host (or locally in
## practice). Clients never decide stamps, captures, finishes or results.
##
## Same-tick ordering (documented in RULES.md):
##   1. state timers   2. intents (cart seats, tag start, gadgets)
##   3. movement       4. finishes   5. splashes   6. tags   7. cart bumps
##   8. pickups/gadget effects, coins   9. recovery   10. perception
##   11. win/timeout
## A runner who crosses a home door threshold in a tick is safe from a tag
## resolved in that same tick. Finishes at or before the deadline tick count.
##
## V6: the round has a home dorm (CampusDorms, chosen by the host and carried
## in the round configuration).  Runners start on pads inside it; a runner
## with every stamp finishes by crossing one of its door thresholds from
## outside to inside (swept from the start to the end of the tick's move,
## with a line-of-sight check, so a fast move counts and a wall never does).
## Nobody can be tagged inside the home dorm's common room.  The round's
## gold coins (also from the configuration) go to the first player the host
## sees reach them.

signal event_emitted(ev: Dictionary)

var cfg: RulesConfig
var layout: CampusLayout
var players: Array[SimPlayer] = []
var carts: Array[SimCart] = []
var tick: int = 0
var phase: int = TC.Phase.REVEAL
var phase_tick: int = 0
var round_start_tick: int = -1
var end_tick: int = -1
var seed_v: int = 0
var targets: Array = []
var match_id: String = ""
var outcome: int = TC.Outcome.NONE
var finished_count: int = 0
var events: Array = []
var event_seq: int = 0
var pickups: Array = []
var decoys: Array = []
var bombs: Array = []
var splash_markers: Array = []
var results: Dictionary = {}
var bots: Dictionary = {}
var practice := false
var tutorial := false
## Night Watch training: runner bots jog slower
var gentle_bots := false
var patrol_release_extra_s := 0.0
## V6: tonight's home dorm, its doors, and slot -> pad (runner) or patrol
## spawn index (Night Watch) - all from the round configuration
var home_dorm := ""
var home_doors: Array = []
var spawn_map: Dictionary = {}
## V6: the round's coins [{id, pos: Vector3, by: slot or -1}]
var coins: Array = []
## Pass 8: each human slot's active play this round (challenges; the row's active_s)
var activity := ActivityMeter.new()
## Pass 8: the live runner pace (host only, output only: it never feeds
## back into the round); null with opts "pace": false
var pace: RunnerPace = null
var _space: PhysicsDirectSpaceState3D
var _cap_shape: CapsuleShape3D
var _bot_factory: Callable


func setup(config: RulesConfig, lay: CampusLayout, roster: Array, seed_value: int, target_list: Array, mid: String, opts: Dictionary = {}) -> void:
	cfg = config
	layout = lay
	seed_v = seed_value
	targets = target_list.duplicate()
	match_id = mid
	practice = bool(opts.get("practice", false))
	tutorial = bool(opts.get("tutorial", false))
	gentle_bots = bool(opts.get("gentle_bots", false))
	patrol_release_extra_s = float(opts.get("patrol_release_extra_s", 0.0))
	_bot_factory = opts.get("bot_factory", Callable())
	activity.setup(cfg.sim_hz)
	# tonight's home dorm: one of this map's (a dorm of another map, or an
	# unknown id, falls back to the map's default; NetSession refuses such a
	# round before it gets here)
	home_dorm = String(opts.get("dorm", CampusDorms.default_id(layout.map_id)))
	if not CampusDorms.has_dorm(home_dorm, layout.map_id):
		home_dorm = CampusDorms.default_id(layout.map_id)
	home_doors = CampusDorms.geometry(home_dorm)["doors"]
	spawn_map = opts.get("spawns", {}) if not (opts.get("spawns", {}) as Dictionary).is_empty() else default_spawns(roster)
	for c in opts.get("coins", []):
		coins.append({"id": String(c["id"]), "pos": Vector3(float(c["x"]), 0.0, float(c["z"])), "by": -1})
	var builder := CampusBuilder.new(layout)
	builder.build_collision(self)
	_cap_shape = CapsuleShape3D.new()
	_cap_shape.radius = Motor.CHAR_RADIUS
	_cap_shape.height = Motor.CHAR_HEIGHT

	for i in cfg.cart_count:
		var c := SimCart.new()
		c.id = i
		c.body = Motor.make_cart_body("Cart%d" % i)
		add_child(c.body)
		var cs: Dictionary = layout.cart_spawns[i % layout.cart_spawns.size()]
		var cp: Vector2 = cs["pos"]
		c.home = Vector3(cp.x, 0.05, cp.y)
		c.home_yaw = PI
		c.body.global_position = c.home
		c.yaw = c.home_yaw
		c.body.rotation.y = c.yaw
		carts.append(c)

	for entry in roster:
		var p := SimPlayer.new()
		p.id = int(entry["slot"])
		p.uid = String(entry.get("uid", ""))
		p.display_name = String(entry.get("name", "Player"))
		p.is_bot = bool(entry.get("is_bot", false))
		p.was_human = not p.is_bot
		p.role = int(entry["role"])
		p.cosmetic = entry.get("cosmetic", {})
		p.body = Motor.make_character_body("P%d" % p.id)
		add_child(p.body)
		var sp := spawn_point(layout, home_dorm, p.role, int(spawn_map.get(p.id, spawn_map.get(str(p.id), 0))))
		p.body.global_position = sp[0]
		p.yaw = sp[1]
		if p.is_patrol():
			p.state = TC.PState.WAITING   # held in the cart shed until the head start ends
		players.append(p)
		if p.is_bot and _bot_factory.is_valid():
			bots[p.id] = _bot_factory.call(self, p)
	players.sort_custom(func(a, b): return a.id < b.id)

	# Gadget pickups: types from the shared seed (only enabled gadgets ship).
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v ^ 0x5eed
	var enabled: Array = []
	for key in cfg.gadgets_enabled:
		if TC.GADGET_KEYS.has(key):
			enabled.append(TC.GADGET_KEYS[key])
	if not enabled.is_empty():
		for spot in layout.gadget_spots:
			pickups.append({"pos": Vector3(spot.x, 0.0, spot.y), "type": enabled[rng.randi() % enabled.size()], "respawn": 0.0})
	if bool(opts.get("pace", true)):
		pace = RunnerPace.new()
		pace.setup(self)       # starts the route fields on a worker (PaceFields)
	_set_phase(TC.Phase.REVEAL)


## Where a slot starts: [position, yaw].  Runners stand on the home dorm's
## pads inside (facing an exit), the Night Watch at the Grounds Shed.  The
## client uses the same function for its own predicted body.
static func spawn_point(lay: CampusLayout, dorm_id: String, role: int, index: int) -> Array:
	if role == TC.Role.RUNNER:
		var pads: Array = CampusDorms.geometry(dorm_id)["pads"]
		var pd: Dictionary = pads[posmod(index, pads.size())]
		var pp: Vector2 = pd["pos"]
		return [Vector3(pp.x, 0.05, pp.y), float(pd["yaw"])]
	var ps: Vector2 = lay.patrol_spawns[posmod(index, lay.patrol_spawns.size())]
	return [Vector3(ps.x, 0.05, ps.y), PI]


## slot -> pad / spawn index in roster order (the host publishes it in the
## round configuration; this is also what a configuration without it means).
static func default_spawns(roster: Array) -> Dictionary:
	var out := {}
	var ri := 0
	var pi := 0
	for e in roster:
		if int(e["role"]) == TC.Role.RUNNER:
			out[int(e["slot"])] = ri
			ri += 1
		else:
			out[int(e["slot"])] = pi
			pi += 1
	return out


func player(slot: int) -> SimPlayer:
	for p in players:
		if p.id == slot:
			return p
	return null


func space_state() -> PhysicsDirectSpaceState3D:
	if _space == null:
		_space = get_world_3d().direct_space_state
	return _space


# ---------------------------------------------------------------------------
# Phase / clock
# ---------------------------------------------------------------------------
func _set_phase(ph: int) -> void:
	phase = ph
	phase_tick = tick
	if ph == TC.Phase.PLAYING:
		round_start_tick = tick
		end_tick = tick + cfg.ticks(cfg.match_duration_s)
		for p in players:
			if p.is_patrol():
				p.state = TC.PState.WAITING
	_emit(TC.Ev.PHASE, -1, -1, ph)


func round_time() -> float:
	if round_start_tick < 0:
		return 0.0
	return float(tick - round_start_tick) / float(cfg.sim_hz)


func time_left() -> float:
	if phase == TC.Phase.PLAYING:
		return maxf(0.0, float(end_tick - tick) / float(cfg.sim_hz))
	if phase < TC.Phase.PLAYING:
		return cfg.match_duration_s
	return 0.0


func countdown_left() -> float:
	if phase == TC.Phase.REVEAL:
		return cfg.role_reveal_s + cfg.start_countdown_s - float(tick - phase_tick) / float(cfg.sim_hz)
	if phase == TC.Phase.COUNTDOWN:
		return cfg.start_countdown_s - float(tick - phase_tick) / float(cfg.sim_hz)
	return 0.0


func patrol_release_left() -> float:
	if phase != TC.Phase.PLAYING:
		return cfg.runner_head_start_s + patrol_release_extra_s
	return maxf(0.0, cfg.runner_head_start_s + patrol_release_extra_s - round_time())


# ---------------------------------------------------------------------------
# Events
# ---------------------------------------------------------------------------
## m: presentation detail (e.g. TC.Impact for splashes); objective fields
## a/b/v keep their meanings.
func _emit(type: int, a: int = -1, b: int = -1, v: int = 0, pos: Vector3 = Vector3.ZERO, m: int = 0) -> void:
	event_seq += 1
	var ev := {"id": event_seq, "t": tick, "type": type, "a": a, "b": b, "v": v, "pos": pos, "m": m}
	events.append(ev)
	event_emitted.emit(ev)


# ---------------------------------------------------------------------------
# Connection management (host side)
# ---------------------------------------------------------------------------
func set_disconnected(slot: int) -> void:
	var p := player(slot)
	if p == null or p.is_bot or not p.connected:
		return
	p.connected = false
	p.bot_takeover = true
	p.disconnect_t = 0.0
	if not bots.has(slot) and _bot_factory.is_valid():
		bots[slot] = _bot_factory.call(self, p)
	_emit(TC.Ev.PLAYER_BOT_TAKEOVER, slot)


## Valid reconnect: resumes the same authoritative state (no reset, no immunity).
func resume(slot: int, uid: String) -> bool:
	var p := player(slot)
	if p == null or p.is_bot or p.connected or p.uid != uid:
		return false
	if p.disconnect_t > cfg.disconnect_reserve_s:
		return false
	p.connected = true
	p.bot_takeover = false
	_emit(TC.Ev.PLAYER_RESUMED, slot)
	return true


func slot_for_uid(uid: String) -> int:
	for p in players:
		if p.uid == uid and not p.is_bot:
			return p.id
	return -1


# ---------------------------------------------------------------------------
# Main step
# ---------------------------------------------------------------------------
## V6 development profiling: per-section tick cost in microseconds (off
## unless a tool sets prof_on; then a handful of clock reads per tick).
static var prof_on := false
static var prof: Dictionary = {}


static func _prof_add(section: String, t0: int) -> void:
	prof[section] = int(prof.get(section, 0)) + Time.get_ticks_usec() - t0


func step(inputs: Dictionary) -> void:
	events.clear()
	var dt := cfg.dt()
	tick += 1
	match phase:
		TC.Phase.REVEAL:
			if tick - phase_tick >= cfg.ticks(cfg.role_reveal_s):
				_set_phase(TC.Phase.COUNTDOWN)
			_idle_bodies()
			return
		TC.Phase.COUNTDOWN:
			if tick - phase_tick >= cfg.ticks(cfg.start_countdown_s):
				_set_phase(TC.Phase.PLAYING)
			else:
				_idle_bodies()
				return
		TC.Phase.RESULTS, TC.Phase.ENDED:
			_idle_bodies()
			return

	# 1. timers + state machine
	for p in players:
		_tick_state(p, dt)
	# disconnect reservations (and time away, for series eligibility)
	for p in players:
		if p.was_human and not p.connected:
			p.away_ticks += 1
		if not p.connected and not p.is_bot:
			p.disconnect_t += dt
			if p.disconnect_t > cfg.disconnect_reserve_s and not p.is_bot:
				p.is_bot = true
				_emit(TC.Ev.PLAYER_LEFT, p.id)

	# 2. gather intents
	var cmds := {}
	var t0 := Time.get_ticks_usec() if prof_on else 0
	for p in players:
		var cmd: InputCmd = null
		if p.is_bot or p.bot_takeover:
			var brain = bots.get(p.id)
			var tb := Time.get_ticks_usec() if prof_on else 0
			cmd = brain.think(self, p) if brain != null else InputCmd.new()
			if prof_on:
				_prof_add("bots", tb)
		else:
			cmd = inputs.get(p.id)
			if cmd == null:
				cmd = p.last_input.repeat_without_edges(p.last_input.seq)
		p.last_input = cmd
		cmds[p.id] = cmd
	if prof_on:
		_prof_add("intents", t0)
		t0 = Time.get_ticks_usec()
	_resolve_cart_requests(cmds)
	for p in players:
		_update_tag_cues(p, (cmds[p.id] as InputCmd).cam_yaw)
		_intent_tag(p, cmds[p.id])
		_intent_gadget(p, cmds[p.id])
	if prof_on:
		_prof_add("tag_cues", t0)
		t0 = Time.get_ticks_usec()

	# 3. movement (each runner's start point is kept for the threshold sweep)
	for c in carts:
		var drv_cmd: InputCmd = null
		if c.occupant >= 0:
			drv_cmd = cmds.get(c.occupant)
		Motor.step_cart(c, drv_cmd, cfg, dt, layout)
	if prof_on:
		_prof_add("carts", t0)
		t0 = Time.get_ticks_usec()
	for p in players:
		p.prev_pos = p.pos()
		_move_player(p, cmds[p.id], dt)
		p.home_safe = p.is_runner() and CampusDorms.in_room(home_dorm, p.pos(), 0.1)
	if prof_on:
		_prof_add("move", t0)
		t0 = Time.get_ticks_usec()

	# 4..9 rules in fixed order
	if phase == TC.Phase.PLAYING and tick <= end_tick:
		for p in players:
			_check_finish(p)
		for p in players:
			_check_water(p)
		for p in players:
			_resolve_tag(p)
		_check_bumps()
		_update_gadgets(dt)
		_check_coins()
		for p in players:
			_check_recover(p)
		activity.step(self, inputs)
	if prof_on:
		_prof_add("rules", t0)
		t0 = Time.get_ticks_usec()
	if tick % 4 == 0:
		_perception()
	if prof_on:
		_prof_add("perception", t0)
	for p in players:
		p.push_history()
	for m in splash_markers:
		m["t"] = float(m["t"]) - dt
	splash_markers = splash_markers.filter(func(m): return float(m["t"]) > 0.0)

	# 11. win / timeout
	if phase == TC.Phase.PLAYING:
		if finished_count >= cfg.runners_needed:
			_end_match(TC.Outcome.RUNNERS_WIN)
		elif tick >= end_tick:
			_end_match(TC.Outcome.PATROL_WIN)
		elif pace != null and tick % RunnerPace.UPDATE_TICKS == 0:
			pace.update(self)      # Pass 8: 2 Hz, after the tick's rules


func _idle_bodies() -> void:
	# keep bodies settled on the ground during reveal/countdown/results
	for p in players:
		if p.body and p.state != TC.PState.FINISHED and p.state != TC.PState.IN_CART and p.state != TC.PState.CAPTURED:
			p.body.velocity = Vector3(0, -2.0, 0)
			p.body.move_and_slide()
			p.vel = Vector3.ZERO
	for p in players:
		p.push_history()


func _tick_state(p: SimPlayer, dt: float) -> void:
	p.protect = maxf(0.0, p.protect - dt)
	p.bump_protect = maxf(0.0, p.bump_protect - dt)
	p.gadget_cd = maxf(0.0, p.gadget_cd - dt)
	p.spotted = maxf(0.0, p.spotted - dt)
	p.emote_t = maxf(0.0, p.emote_t - dt)
	if Motor.advance_timers(p, cfg, dt):
		_emit(TC.Ev.TAG_MISS, p.id, -1, 0, p.pos())
	match p.state:
		TC.PState.WAITING:
			if patrol_release_left() <= 0.0:
				_set_state(p, TC.PState.ACTIVE)
		TC.PState.CAPTURED:
			p.penalty -= dt
			if p.penalty <= 0.0:
				_respawn(p)
		TC.PState.SPLASHING:
			if p.state_t >= cfg.splash_sequence_s:
				_resurface(p)


func _set_state(p: SimPlayer, s: int) -> void:
	p.state = s
	p.state_t = 0.0


func _move_player(p: SimPlayer, cmd: InputCmd, dt: float) -> void:
	match p.state:
		TC.PState.ACTIVE, TC.PState.STUMBLE, TC.PState.EXITING:
			if p.state == TC.PState.EXITING:
				var frozen := cmd.duplicate_cmd()
				frozen.move = Vector2.ZERO
				frozen.pressed = 0
				Motor.step_foot(p, frozen, cfg, dt)
			else:
				Motor.step_foot(p, cmd, cfg, dt)
		TC.PState.WAITING:
			var idle := InputCmd.new()
			Motor.step_foot(p, idle, cfg, dt)
		TC.PState.IN_CART, TC.PState.ENTERING:
			if p.cart_id >= 0:
				var c := carts[p.cart_id]
				p.body.global_position = c.pos() + c.right() * -0.35 + Vector3(0, 0.3, 0)
				p.yaw = c.yaw
				p.vel = c.forward() * c.speed
				if c.exiting and absf(c.speed) <= cfg.cart_exit_max_speed:
					_try_exit_cart(p, c)
		TC.PState.SPLASHING, TC.PState.CAPTURED, TC.PState.FINISHED:
			pass


# ---------------------------------------------------------------------------
# Carts: entry/exit with deterministic seat-race resolution
# ---------------------------------------------------------------------------
func _resolve_cart_requests(cmds: Dictionary) -> void:
	var claims := {}  # cart id -> [patrol, dist]
	for p in players:
		var cmd: InputCmd = cmds[p.id]
		if not cmd.is_pressed(TC.BTN_INTERACT) or not p.is_patrol():
			continue
		if p.state == TC.PState.IN_CART and p.cart_id >= 0:
			carts[p.cart_id].exiting = true
			continue
		if p.state != TC.PState.ACTIVE or p.tag_phase != SimPlayer.TagPhase.NONE:
			continue
		var best := -1
		var bd := 1e9
		for c in carts:
			if c.occupant >= 0 or absf(c.speed) > cfg.cart_enter_max_speed:
				continue
			var d := p.pos().distance_to(c.pos())
			if d <= cfg.cart_enter_range_m + SimCart.HALF.z * 0.5 and d < bd:
				bd = d
				best = c.id
		if best < 0:
			continue
		if not claims.has(best) or bd < float(claims[best][1]) or (is_equal_approx(bd, float(claims[best][1])) and p.id < int(claims[best][0])):
			claims[best] = [p.id, bd]
	for cid in claims:
		var c: SimCart = carts[cid]
		var p := player(int(claims[cid][0]))
		c.occupant = p.id
		c.exiting = false
		p.cart_id = c.id
		p.end_air_actions()
		p.tag_phase = SimPlayer.TagPhase.NONE
		Motor.set_body_enabled(p.body, false)
		_set_state(p, TC.PState.ENTERING)
		_emit(TC.Ev.CART_ENTER, p.id, c.id, 0, c.pos())


func _try_exit_cart(p: SimPlayer, c: SimCart) -> void:
	for ep in c.exit_points():
		var spot := _validate_exit_point(ep, c.pos())
		if spot != Vector3.INF:
			c.occupant = -1
			c.exiting = false
			p.cart_id = -1
			p.body.global_position = spot
			p.vel = Vector3.ZERO
			p.body.velocity = Vector3.ZERO
			Motor.set_body_enabled(p.body, true)
			p.tag_lockout = cfg.cart_exit_tag_lockout_s
			_set_state(p, TC.PState.EXITING)
			_emit(TC.Ev.CART_EXIT, p.id, c.id, 0, spot)
			return


## Returns a clear standing point on solid ground near `ep`, or Vector3.INF.
func _validate_exit_point(ep: Vector3, seat: Vector3 = Vector3.INF) -> Vector3:
	var ss := space_state()
	var from := Vector3(ep.x, ep.y + 1.6, ep.z)
	var rq := PhysicsRayQueryParameters3D.create(from, Vector3(ep.x, ep.y - 1.5, ep.z), TC.L_WORLD)
	var hit := ss.intersect_ray(rq)
	if hit.is_empty():
		return Vector3.INF
	var ground: Vector3 = hit["position"]
	if CampusBuilder.water_at(layout, Vector2(ground.x, ground.z)) >= 0 or ground.y < -0.3:
		return Vector3.INF
	if absf(ground.y - ep.y) > 1.2:
		return Vector3.INF
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _cap_shape
	q.transform = Transform3D(Basis.IDENTITY, ground + Vector3(0, Motor.CHAR_HEIGHT * 0.5 + 0.05, 0))
	q.collision_mask = TC.L_WORLD | TC.L_CART
	if not ss.intersect_shape(q, 1).is_empty():
		return Vector3.INF
	# line of sight from the cart seat to the exit point: never dismount through a wall
	if seat != Vector3.INF:
		var los := PhysicsRayQueryParameters3D.create(Vector3(seat.x, seat.y + 1.0, seat.z), ground + Vector3(0, 1.0, 0), TC.L_WORLD)
		if not ss.intersect_ray(los).is_empty():
			return Vector3.INF
	return ground + Vector3(0, 0.02, 0)


# ---------------------------------------------------------------------------
# Tags (patrol on foot)
# ---------------------------------------------------------------------------
func _intent_tag(p: SimPlayer, cmd: InputCmd) -> void:
	if not p.is_patrol() or p.state != TC.PState.ACTIVE:
		return
	_track_tag_target(p)
	if not cmd.is_pressed(TC.BTN_TAG):
		return
	if p.tag_phase != SimPlayer.TagPhase.NONE or p.tag_cd > 0.0 or p.tag_lockout > 0.0:
		return
	if not (p.on_floor or p.coyote > 0.0):
		return
	# V4 assist: an eligible runner in sight inside the cone; turn toward it
	# by at most tag_assist_snap_deg now, then track it at a limited rate
	var best := tag_candidate(p, cmd.cam_yaw)
	p.tag_target = best.id if best != null else -1
	if best != null:
		var rel := best.pos() - p.pos()
		var want := atan2(-rel.x, -rel.z)
		p.yaw = rotate_toward(p.yaw, want, deg_to_rad(cfg.tag_assist_snap_deg))
	p.tag_phase = SimPlayer.TagPhase.ANTICIPATE
	p.tag_t = 0.0


## The runner the assist picks for a Night Watch pressing Tag now: taggable,
## within the assist range and cone (camera view or facing), in line of
## sight; nearest by an angle-weighted distance.  Null when none.
func tag_candidate(p: SimPlayer, cam_yaw: float) -> SimPlayer:
	var view := Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
	var face := p.facing()
	var cos_lim := cos(deg_to_rad(cfg.tag_assist_half_angle_deg))
	var best: SimPlayer = null
	var best_score := INF
	for r in players:
		if r == p or not r.is_taggable():
			continue
		var rel := r.pos() - p.pos()
		if absf(rel.y) > cfg.tag_vertical_reach_m:
			continue
		var flat := Vector3(rel.x, 0, rel.z)
		var d := flat.length()
		if d > cfg.tag_assist_range_m:
			continue
		var c := 1.0 if d < 0.05 else maxf((flat / d).dot(view), (flat / d).dot(face))
		if c < cos_lim:
			continue
		var score := d * (2.0 - c)
		if score >= best_score:
			continue
		if not has_los(p.pos() + Vector3(0, 1.1, 0), r.pos() + Vector3(0, 1.0, 0)):
			continue
		best = r
		best_score = score
	return best


## Wind-up and lunge follow their target within the turn-rate limit (no
## suction: speed and reach are unchanged).
func _track_tag_target(p: SimPlayer) -> void:
	if p.tag_target < 0 or (p.tag_phase != SimPlayer.TagPhase.ANTICIPATE and p.tag_phase != SimPlayer.TagPhase.LUNGE):
		return
	var r := player(p.tag_target)
	if r == null or not r.is_taggable():
		p.tag_target = -1
		return
	var rel := r.pos() - p.pos()
	p.yaw = rotate_toward(p.yaw, atan2(-rel.x, -rel.z), deg_to_rad(cfg.tag_track_deg_per_s) * cfg.dt())


## The target and tag-ready cues for a Night Watch (host, every tick): the
## assist's pick, and whether a press now would land if the runner keeps
## going - the predicted gap at the end of the lunge is inside the reach.
func _update_tag_cues(p: SimPlayer, cam_yaw: float) -> void:
	p.tag_ready = false
	p.tag_aim = -1
	if not p.is_patrol() or p.state != TC.PState.ACTIVE or phase != TC.Phase.PLAYING:
		return
	var r := tag_candidate(p, cam_yaw)
	if r == null:
		return
	p.tag_aim = r.id
	if p.tag_phase != SimPlayer.TagPhase.NONE or p.tag_cd > 0.0 or p.tag_lockout > 0.0 or not (p.on_floor or p.coyote > 0.0):
		return
	var T := cfg.tag_anticipation_s + cfg.tag_lunge_s
	var travel := cfg.patrol_speed * cfg.tag_anticipation_move_scale * cfg.tag_anticipation_s + cfg.tag_lunge_speed * cfg.tag_lunge_s
	var future := r.pos() + Vector3(r.vel.x, 0, r.vel.z) * T
	var gap := Vector2(future.x - p.pos().x, future.z - p.pos().z).length()
	# the hit test measures from 0.25 m ahead of the Night Watch
	p.tag_ready = maxf(0.0, gap - travel) <= cfg.tag_reach_m + 0.25 - cfg.tag_ready_margin_m


func _resolve_tag(p: SimPlayer) -> void:
	if not p.is_patrol() or p.tag_phase != SimPlayer.TagPhase.LUNGE or p.state != TC.PState.ACTIVE:
		return
	var origin := p.pos() + p.facing() * 0.25
	var lag := clampi(p.lag_ticks, 0, cfg.ticks(cfg.tag_lag_comp_max_s))
	var best: SimPlayer = null
	var bd := 1e9
	for r in players:
		if r == p or not r.is_taggable():
			continue
		var now_pos := r.pos()
		var seen_pos := r.history_pos(lag) if lag > 0 else now_pos
		var ok := RulesLogic.tag_geometry_ok(origin, p.facing(), seen_pos, cfg)
		if ok and lag > 0:
			# never tag someone who is clearly gone now
			ok = Vector2(now_pos.x - origin.x, now_pos.z - origin.z).length() <= cfg.tag_reach_m + cfg.tag_lag_comp_slack_m
		if not ok:
			continue
		if not has_los(p.pos() + Vector3(0, 1.1, 0), now_pos + Vector3(0, 1.0, 0)):
			continue
		var d := origin.distance_to(seen_pos)
		if d < bd:
			bd = d
			best = r
	if best:
		_capture(best, p)
		p.tag_phase = SimPlayer.TagPhase.RECOVER
		p.tag_t = -cfg.tag_hit_recover_s
		p.tag_cd = cfg.tag_hit_recover_s


func has_los(a: Vector3, b: Vector3) -> bool:
	var rq := PhysicsRayQueryParameters3D.create(a, b, TC.L_WORLD | TC.L_CART)
	return space_state().intersect_ray(rq).is_empty()


func _capture(r: SimPlayer, by: SimPlayer) -> void:
	r.times_captured += 1
	by.captures += 1
	by.captured_ids[r.id] = true
	r.penalty = cfg.capture_penalty_s
	r.end_air_actions()
	r.fast = false
	r.turbo_t = 0.0
	r.vel = Vector3.ZERO
	Motor.set_body_enabled(r.body, false)
	_set_state(r, TC.PState.CAPTURED)
	_emit(TC.Ev.CAPTURE, r.id, by.id, 0, r.pos())


func _respawn(p: SimPlayer) -> void:
	var pads: Array = []
	if p.last_stamp_water >= 0:
		pads = layout.waters[p.last_stamp_water]["pads"]
	else:
		pads = CampusDorms.geometry(home_dorm)["respawn"]   # inside tonight's home dorm
	var patrol_pos: Array = []
	for q in players:
		if q.is_patrol():
			patrol_pos.append(q.pos2())
	var pad := RulesLogic.choose_pad(pads, patrol_pos)
	p.body.global_position = Vector3(pad.x, 0.1, pad.y)
	p.body.velocity = Vector3.ZERO
	p.vel = Vector3.ZERO
	Motor.set_body_enabled(p.body, true)
	p.protect = cfg.respawn_protect_s
	p.fast = false
	p.end_air_actions()
	p.clear_history()
	p.prev_pos = Vector3.INF
	_set_state(p, TC.PState.ACTIVE)
	_emit(TC.Ev.RESPAWN, p.id, -1, 0, p.body.global_position)


# ---------------------------------------------------------------------------
# Finish + water
# ---------------------------------------------------------------------------
func _check_finish(p: SimPlayer) -> void:
	if not p.is_runner() or (p.state != TC.PState.ACTIVE and p.state != TC.PState.STUMBLE):
		return
	if p.stamp_count() < cfg.targets_per_match:
		return
	var door := home_crossing(p.prev_pos, p.pos())
	if door.is_empty():
		return
	finished_count += 1
	p.finish_order = finished_count
	p.finished_tick = tick
	p.finish_door = String(door["id"])
	p.vel = Vector3.ZERO
	Motor.set_body_enabled(p.body, false)
	_set_state(p, TC.PState.FINISHED)
	_emit(TC.Ev.FINISH, p.id, home_doors.find(door), finished_count, p.pos())


## The home door whose threshold the move a -> b crossed from outside to
## inside, or {}: the swept test (CampusDorms.crosses: direction, width,
## height, step length) and a clear line between the two points at chest
## height, so neither a wall nor a teleport can count as a doorway.
func home_crossing(a: Vector3, b: Vector3) -> Dictionary:
	if a == Vector3.INF:
		return {}
	for door in home_doors:
		if CampusDorms.crosses(door, a, b):
			var rq := PhysicsRayQueryParameters3D.create(a + Vector3(0, 0.9, 0), b + Vector3(0, 0.9, 0), TC.L_WORLD)
			if space_state().intersect_ray(rq).is_empty():
				return door
	return {}


func _check_water(p: SimPlayer) -> void:
	if p.state != TC.PState.ACTIVE and p.state != TC.PState.STUMBLE:
		return
	var pp := p.pos()
	var wi := CampusBuilder.water_at(layout, Vector2(pp.x, pp.z))
	if wi < 0:
		return
	var w: Dictionary = layout.waters[wi]
	if pp.y > float(w["surface_y"]) + 0.25:
		return
	var heading := p.vel if p.vel.length() > 0.5 else p.facing()
	# impact class, read before the velocity reset below (presentation only)
	if p.diving:
		p.splash_impact = TC.Impact.DIVE
	elif p.air_t > 0.2 or p.vel.y < -3.0:
		p.splash_impact = TC.Impact.JUMP
	else:
		p.splash_impact = TC.Impact.WALK
	p.splash_water = wi
	p.splash_exit = RulesLogic.choose_splash_exit(w["exits"], pp, heading)
	p.splash_stamped = false
	p.end_air_actions()
	p.vel = Vector3.ZERO
	Motor.set_body_enabled(p.body, false)
	p.body.global_position = Vector3(pp.x, float(w["surface_y"]), pp.z)
	_set_state(p, TC.PState.SPLASHING)
	var ti := targets.find(wi)
	if p.is_runner() and ti >= 0 and (p.stamps & (1 << ti)) == 0:
		p.stamps |= (1 << ti)
		p.stamp_order.append(wi)
		p.last_stamp_water = wi
		p.splash_stamped = true
		splash_markers.append({"water": wi, "t": cfg.splash_marker_s})
		_emit(TC.Ev.SPLASH_STAMP, p.id, wi, ti, p.body.global_position, p.splash_impact)
	else:
		_emit(TC.Ev.SPLASH_NOSTAMP, p.id, wi, 0, p.body.global_position, p.splash_impact)


func _resurface(p: SimPlayer) -> void:
	var ex := p.splash_exit
	var spot := _validate_exit_point(ex)
	if spot == Vector3.INF:
		spot = ex + Vector3(0, 0.1, 0)
	p.body.global_position = spot
	var w: Dictionary = layout.waters[p.splash_water]
	var away := Vector3(spot.x - float(w["center"].x), 0, spot.z - float(w["center"].y)).normalized()
	p.vel = away * 2.5 + Vector3(0, 3.5, 0)
	p.body.velocity = p.vel
	p.yaw = atan2(-away.x, -away.z)
	Motor.set_body_enabled(p.body, true)
	p.splash_water = -1
	p.clear_history()
	p.prev_pos = Vector3.INF
	_set_state(p, TC.PState.ACTIVE)


func _check_recover(p: SimPlayer) -> void:
	if p.state != TC.PState.ACTIVE and p.state != TC.PState.STUMBLE and p.state != TC.PState.EXITING:
		return
	var pp := p.pos()
	if pp.y > -6.0 and layout.bounds.grow(-0.5).has_point(Vector2(pp.x, pp.z)):
		return
	# Out of bounds / fell through: return to a safe pad with no new progress.
	var pads: Array = CampusDorms.geometry(home_dorm)["respawn"]
	if p.is_patrol():
		pads = layout.patrol_spawns
	elif p.last_stamp_water >= 0:
		pads = layout.waters[p.last_stamp_water]["pads"]
	var pad: Vector2 = pads[0]
	var bd := 1e9
	for c in pads:
		var d := (c as Vector2).distance_to(Vector2(pp.x, pp.z))
		if d < bd:
			bd = d
			pad = c
	p.body.global_position = Vector3(pad.x, 0.2, pad.y)
	p.vel = Vector3.ZERO
	p.body.velocity = Vector3.ZERO
	p.clear_history()
	p.prev_pos = Vector3.INF
	_emit(TC.Ev.RECOVER, p.id, -1, 0, p.body.global_position)


# ---------------------------------------------------------------------------
# Cart bumps: controlled stumble, capped knockback, no stun loops, never a capture
# ---------------------------------------------------------------------------
func _check_bumps() -> void:
	for c in carts:
		if absf(c.speed) < cfg.cart_bump_min_speed:
			continue
		for r in players:
			if not r.is_runner() or r.state != TC.PState.ACTIVE:
				continue
			if r.bump_protect > 0.0 or r.protect > 0.0 or c.bump_cd.has(r.id):
				continue
			if not c.overlaps(r.pos(), Motor.CHAR_RADIUS + 0.15):
				continue
			var away := r.pos() - c.pos()
			away.y = 0.0
			if away.length() < 0.1:
				away = c.right()
			away = away.normalized()
			var push := minf(absf(c.speed) * 0.55 + 2.0, cfg.cart_bump_knockback_max)
			r.vel = away * push + Vector3(0, 3.2, 0)
			r.body.velocity = r.vel
			r.end_air_actions()
			r.tag_phase = SimPlayer.TagPhase.NONE
			r.bump_protect = cfg.bump_protect_s
			_set_state(r, TC.PState.STUMBLE)
			c.speed *= cfg.cart_bump_speed_keep
			c.bump_cd[r.id] = cfg.bump_protect_s + 0.5
			_emit(TC.Ev.BUMP, r.id, c.id, 0, r.pos())


# ---------------------------------------------------------------------------
# Gadgets (authoritative ownership, consumption, cooldown)
# ---------------------------------------------------------------------------
func _intent_gadget(p: SimPlayer, cmd: InputCmd) -> void:
	if not cmd.is_pressed(TC.BTN_GADGET) or not p.is_runner():
		return
	if p.state != TC.PState.ACTIVE or p.gadget == TC.Gadget.NONE or p.gadget_cd > 0.0:
		return
	var g := p.gadget
	p.gadget = TC.Gadget.NONE
	p.gadget_cd = cfg.gadget_use_cooldown_s
	var aim := Vector3(-sin(cmd.cam_yaw), 0, -cos(cmd.cam_yaw))
	if cmd.move.length() > 0.3:
		aim = Vector3(cmd.move.x, 0, cmd.move.y).normalized()
	match g:
		TC.Gadget.TURBO:
			p.turbo_t = cfg.turbo_duration_s
		TC.Gadget.DECOY:
			var land := _toss_landing(p.pos(), aim, cfg.decoy_range_m)
			var side := Vector3(-aim.z, 0, aim.x) * (1.0 if (tick % 2) == 0 else -1.0)
			decoys.append({"pos": land, "dir": (aim * 0.4 + side).normalized(), "t": cfg.decoy_duration_s + cfg.toss_flight_s, "flight": cfg.toss_flight_s, "owner": p.id, "from": p.pos()})
		TC.Gadget.SPLASH_BOMB:
			var target := _bomb_assist(p.pos(), aim)
			var land2 := _toss_landing(p.pos(), (target - p.pos()).normalized() if target != Vector3.INF else aim, minf(cfg.bomb_range_m, p.pos().distance_to(target)) if target != Vector3.INF else cfg.bomb_range_m)
			bombs.append({"from": p.pos(), "to": land2, "t": cfg.toss_flight_s, "owner": p.id})
	_emit(TC.Ev.GADGET_USE, p.id, -1, g, p.pos())


func _toss_landing(from: Vector3, dir: Vector3, dist: float) -> Vector3:
	var a := from + Vector3(0, 1.2, 0)
	var b := a + dir * dist
	var hit := space_state().intersect_ray(PhysicsRayQueryParameters3D.create(a, b, TC.L_WORLD))
	var end: Vector3 = b
	if not hit.is_empty():
		end = (hit["position"] as Vector3) - dir * 0.5
	var down := space_state().intersect_ray(PhysicsRayQueryParameters3D.create(end + Vector3(0, 2, 0), end - Vector3(0, 6, 0), TC.L_WORLD))
	if not down.is_empty():
		return down["position"]
	return Vector3(end.x, 0.0, end.z)


func _bomb_assist(from: Vector3, aim: Vector3) -> Vector3:
	var best := Vector3.INF
	var bd := cfg.bomb_assist_range_m
	for c in carts:
		var rel := c.pos() - from
		rel.y = 0.0
		var d := rel.length()
		if d > bd or d < 0.5:
			continue
		var ang := rad_to_deg(acos(clampf(rel.normalized().dot(aim), -1.0, 1.0)))
		if ang <= cfg.bomb_assist_cone_deg:
			bd = d
			best = c.pos() + c.forward() * c.speed * cfg.toss_flight_s
	return best


func _update_gadgets(dt: float) -> void:
	for pk in pickups:
		if float(pk["respawn"]) > 0.0:
			pk["respawn"] = float(pk["respawn"]) - dt
			continue
		for p in players:
			if not p.is_runner() or p.state != TC.PState.ACTIVE or p.gadget != TC.Gadget.NONE:
				continue
			if p.pos().distance_to(pk["pos"]) <= cfg.gadget_pickup_radius_m:
				p.gadget = int(pk["type"])
				pk["respawn"] = cfg.gadget_respawn_s
				_emit(TC.Ev.GADGET_PICKUP, p.id, -1, p.gadget, pk["pos"])
				break
	for d in decoys:
		d["t"] = float(d["t"]) - dt
		if float(d["flight"]) > 0.0:
			d["flight"] = float(d["flight"]) - dt
			continue
		var np: Vector3 = d["pos"] + (d["dir"] as Vector3) * cfg.decoy_step_speed * dt
		if has_los(d["pos"] + Vector3(0, 0.4, 0), np + Vector3(0, 0.4, 0)) and CampusBuilder.water_at(layout, Vector2(np.x, np.z)) < 0:
			d["pos"] = np
		else:
			d["dir"] = Vector3(-(d["dir"] as Vector3).z, 0, (d["dir"] as Vector3).x)
	decoys = decoys.filter(func(d): return float(d["t"]) > 0.0)
	for bm in bombs:
		bm["t"] = float(bm["t"]) - dt
		if float(bm["t"]) <= 0.0:
			for c in carts:
				if c.pos().distance_to(bm["to"]) <= cfg.bomb_radius_m + SimCart.HALF.z and c.immunity_t <= 0.0:
					c.slowed_t = cfg.bomb_slow_s
					c.immunity_t = cfg.bomb_immunity_s
					_emit(TC.Ev.BOMB_HIT, int(bm["owner"]), c.id, 1, bm["to"])
			_emit(TC.Ev.BOMB_HIT, int(bm["owner"]), -1, 0, bm["to"])
	bombs = bombs.filter(func(bm): return float(bm["t"]) > 0.0)


# ---------------------------------------------------------------------------
# Gold coins (V6): host-decided, once each, worth exactly one Coin
# ---------------------------------------------------------------------------
## Each coin goes to the first player the host sees reach it: on foot (either
## role, bots included), within the pickup radius.  Two in reach on the same
## tick: the nearer one, then the lower slot.  A taken coin never comes back
## this round, so nothing (a replayed packet, a reconnect, a second client)
## can collect it twice.
func _check_coins() -> void:
	var r := cfg.coin_pickup_radius_m
	for ci in coins.size():
		var c: Dictionary = coins[ci]
		if int(c["by"]) >= 0:
			continue
		var cp: Vector3 = c["pos"]
		var best: SimPlayer = null
		var bd := INF
		for p in players:
			if p.state != TC.PState.ACTIVE and p.state != TC.PState.STUMBLE and p.state != TC.PState.EXITING:
				continue
			var pp := p.pos()
			if pp.y - cp.y > 1.6 or cp.y - pp.y > 0.8:
				continue
			var d := Vector2(pp.x - cp.x, pp.z - cp.z).length()
			if d <= r and (d < bd - 0.0001 or (absf(d - bd) <= 0.0001 and best != null and p.id < best.id)):
				bd = d
				best = p
		if best != null:
			c["by"] = best.id
			best.coins_picked += 1
			_emit(TC.Ev.COIN_PICKUP, best.id, -1, ci, cp)


## Bit i set while coin i is still out (snapshots carry it).
func coin_mask() -> int:
	var m := 0
	for i in mini(coins.size(), 16):
		if int(coins[i]["by"]) < 0:
			m |= 1 << i
	return m


## Explicit emote request (lobby/spectators via reliable message).
func request_emote(slot: int, emote_id: int) -> void:
	var p := player(slot)
	if p == null or p.emote_t > 0.0 or emote_id < 0 or emote_id >= TC.EMOTES.size():
		return
	p.emote = emote_id
	p.emote_t = 1.6
	_emit(TC.Ev.EMOTE, slot, -1, emote_id, p.pos())


# ---------------------------------------------------------------------------
# Perception: what each side can legitimately know (bots + cues use this)
# ---------------------------------------------------------------------------
func can_see(viewer: SimPlayer, target_pos: Vector3, view_yaw: float, max_range: float) -> bool:
	var vp := viewer.pos() + Vector3(0, 1.4, 0)
	var rel := target_pos + Vector3(0, 1.0, 0) - vp
	var flat := Vector2(rel.x, rel.z)
	var d := flat.length()
	if d > max_range:
		return false
	if d > 4.0:
		var view := Vector2(-sin(view_yaw), -cos(view_yaw))
		var ang := rad_to_deg(acos(clampf(view.dot(flat.normalized()), -1.0, 1.0)))
		if ang > cfg.view_half_fov_deg:
			return false
	return has_los(vp, target_pos + Vector3(0, 1.0, 0))


func view_yaw_of(p: SimPlayer) -> float:
	if p.is_bot or p.bot_takeover:
		return p.yaw
	return p.last_input.cam_yaw


func _perception() -> void:
	for r in players:
		if not r.is_runner() or not r.is_in_play():
			continue
		for q in players:
			if not q.is_patrol() or q.state == TC.PState.WAITING:
				continue
			var vy := view_yaw_of(q)
			if q.state == TC.PState.IN_CART and q.cart_id >= 0:
				vy = carts[q.cart_id].yaw
			if can_see(q, r.pos(), vy, cfg.view_range_m):
				r.spotted = cfg.spotted_hold_s
				r.spotted_by_cart = q.state == TC.PState.IN_CART
				break


## Noise sources audible from `listener_pos` (runner footsteps, decoys, carts, patrol steps).
## Returns Array of {pos, kind, loud}. Identity is never included.
func noises_for(listener: SimPlayer) -> Array:
	var out: Array = []
	var lp := listener.pos()
	for p in players:
		if p == listener or not p.is_in_play() or p.state == TC.PState.IN_CART or p.state == TC.PState.WAITING:
			continue
		var spd := Vector2(p.vel.x, p.vel.z).length()
		if not p.on_floor or spd < 3.2:
			continue
		var radius := cfg.noise_patrol_step_m
		if p.is_runner():
			# Pass 9: full speed is loud (it was the sprint), a jog quieter;
			# under 3.2 m/s (walking) is silent (above)
			radius = cfg.noise_fast_m if spd >= cfg.runner_speed * cfg.fast_fraction else cfg.noise_jog_m
			if listener.is_runner():
				continue
		else:
			if listener.is_patrol():
				continue
		var d := lp.distance_to(p.pos())
		if d <= radius:
			out.append({"pos": p.pos(), "kind": "steps", "loud": 1.0 - d / radius})
	if listener.is_patrol():
		for dc in decoys:
			if float(dc["flight"]) > 0.0:
				continue
			var d2 := lp.distance_to(dc["pos"])
			if d2 <= cfg.noise_fast_m:
				out.append({"pos": dc["pos"], "kind": "steps", "loud": 1.0 - d2 / cfg.noise_fast_m})
	else:
		for c in carts:
			if c.occupant < 0:
				continue
			var d3 := lp.distance_to(c.pos())
			if d3 <= cfg.noise_cart_m:
				out.append({"pos": c.pos(), "kind": "cart", "loud": 1.0 - d3 / cfg.noise_cart_m})
	return out


# ---------------------------------------------------------------------------
# End of round + results
# ---------------------------------------------------------------------------
func _end_match(oc: int) -> void:
	if outcome != TC.Outcome.NONE:
		return
	outcome = oc
	if pace != null:
		pace.update(self)          # the final finishes are in the last pace
	results = build_results()
	_set_phase(TC.Phase.RESULTS)
	_emit(TC.Ev.MATCH_END, -1, -1, oc)


func cancel_match() -> void:
	if outcome != TC.Outcome.NONE:
		return
	outcome = TC.Outcome.CANCELLED
	results = build_results()
	_set_phase(TC.Phase.ENDED)
	_emit(TC.Ev.MATCH_END, -1, -1, outcome)


func build_results() -> Dictionary:
	var rows: Array = []
	var fastest := -1
	var fastest_t := 1e9
	for p in players:
		var ft := -1.0
		if p.finished_tick >= 0:
			ft = float(p.finished_tick - round_start_tick) / float(cfg.sim_hz)
			if ft < fastest_t:
				fastest_t = ft
				fastest = p.id
		rows.append({
			"slot": p.id, "name": p.display_name, "is_bot": p.is_bot, "role": p.role,
			"stamps": p.stamp_count(), "finished": p.finished_tick >= 0, "finish_time": ft,
			"finish_order": p.finish_order, "times_captured": p.times_captured,
			"captures": p.captures, "unique_captures": p.captured_ids.size(),
			"cosmetic": p.cosmetic, "uid": p.uid,
			"was_human": p.was_human, "present": p.connected, "away_s": float(p.away_ticks) / float(cfg.sim_hz),
			"coins_picked": p.coins_picked, "finish_door": p.finish_door,
			"active_s": activity.active_s(p.id, cfg.sim_hz),
		})
	var coin_log: Array = []
	for c in coins:
		if int(c["by"]) >= 0:
			coin_log.append([String(c["id"]), int(c["by"])])
	return {
		"match_id": match_id, "outcome": outcome, "players": rows, "fastest_slot": fastest,
		"fastest_time": fastest_t if fastest >= 0 else -1.0, "finished": finished_count,
		"needed": cfg.runners_needed, "watch": cfg.patrol_slots, "targets": targets, "practice": practice,
		"round_time": round_time(), "home_dorm": home_dorm, "coins_total": coins.size(), "coin_spawns": coins.size(), "coin_log": coin_log,
	}
