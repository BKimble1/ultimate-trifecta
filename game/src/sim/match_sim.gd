class_name MatchSim
extends Node3D
## Authoritative Trifecta Chase simulation. Runs on the room host (or locally in
## practice). Clients never decide stamps, captures, finishes or results.
##
## Same-tick ordering (documented in RULES.md):
##   1. state timers   2. intents (cart seats, tag start, gadgets)
##   3. movement       4. finishes   5. splashes   6. tags   7. cart bumps
##   8. pickups/gadget effects   9. recovery   10. perception   11. win/timeout
## A runner who reaches the dorm finish boundary in a tick is safe from a tag
## resolved in that same tick. Finishes at or before the deadline tick count.

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
var patrol_release_extra_s := 0.0
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
	patrol_release_extra_s = float(opts.get("patrol_release_extra_s", 0.0))
	_bot_factory = opts.get("bot_factory", Callable())
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

	var runner_i := 0
	var patrol_i := 0
	for entry in roster:
		var p := SimPlayer.new()
		p.id = int(entry["slot"])
		p.uid = String(entry.get("uid", ""))
		p.display_name = String(entry.get("name", "Player"))
		p.is_bot = bool(entry.get("is_bot", false))
		p.role = int(entry["role"])
		p.cosmetic = entry.get("cosmetic", {})
		p.body = Motor.make_character_body("P%d" % p.id)
		add_child(p.body)
		if p.is_runner():
			var sp: Vector2 = layout.runner_spawns[runner_i % layout.runner_spawns.size()]
			runner_i += 1
			p.body.global_position = Vector3(sp.x, 0.05, sp.y)
			p.yaw = 0.0
		else:
			var pp: Vector2 = layout.patrol_spawns[patrol_i % layout.patrol_spawns.size()]
			patrol_i += 1
			p.body.global_position = Vector3(pp.x, 0.05, pp.y)
			p.yaw = PI
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
	_set_phase(TC.Phase.REVEAL)


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
	# disconnect reservations
	for p in players:
		if not p.connected and not p.is_bot:
			p.disconnect_t += dt
			if p.disconnect_t > cfg.disconnect_reserve_s and not p.is_bot:
				p.is_bot = true
				_emit(TC.Ev.PLAYER_LEFT, p.id)

	# 2. gather intents
	var cmds := {}
	for p in players:
		var cmd: InputCmd = null
		if p.is_bot or p.bot_takeover:
			var brain = bots.get(p.id)
			cmd = brain.think(self, p) if brain != null else InputCmd.new()
		else:
			cmd = inputs.get(p.id)
			if cmd == null:
				cmd = p.last_input.repeat_without_edges(p.last_input.seq)
		p.last_input = cmd
		cmds[p.id] = cmd
	_resolve_cart_requests(cmds)
	for p in players:
		_intent_tag(p, cmds[p.id])
		_intent_gadget(p, cmds[p.id])

	# 3. movement
	for c in carts:
		var drv_cmd: InputCmd = null
		if c.occupant >= 0:
			drv_cmd = cmds.get(c.occupant)
		Motor.step_cart(c, drv_cmd, cfg, dt, layout)
	for p in players:
		_move_player(p, cmds[p.id], dt)

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
		for p in players:
			_check_recover(p)
	if tick % 4 == 0:
		_perception()
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
		p.diving = false
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
	if not cmd.is_pressed(TC.BTN_TAG):
		return
	if p.tag_phase != SimPlayer.TagPhase.NONE or p.tag_cd > 0.0 or p.tag_lockout > 0.0:
		return
	if not (p.on_floor or p.coyote > 0.0):
		return
	# gentle aim assist: face the nearest valid runner close by in the view cone
	var view := Vector3(-sin(cmd.cam_yaw), 0, -cos(cmd.cam_yaw))
	var best: SimPlayer = null
	var bd := 3.4
	for r in players:
		if not r.is_taggable():
			continue
		var rel := r.pos() - p.pos()
		var flat := Vector3(rel.x, 0, rel.z)
		var d := flat.length()
		if d < bd and d > 0.05 and (flat.normalized().dot(view) > -0.2 or flat.normalized().dot(p.facing()) > 0.0):
			bd = d
			best = r
	if best:
		var rel2 := best.pos() - p.pos()
		p.yaw = atan2(-rel2.x, -rel2.z)
	p.tag_phase = SimPlayer.TagPhase.ANTICIPATE
	p.tag_t = 0.0


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
	r.diving = false
	r.sprinting = false
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
		pads = layout.dorm_pads
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
	p.sprint = 1.0
	p.clear_history()
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
	var door := layout.in_finish_zone(p.pos2())
	if door == "" or p.pos().y > 2.0:
		return
	finished_count += 1
	p.finish_order = finished_count
	p.finished_tick = tick
	p.vel = Vector3.ZERO
	Motor.set_body_enabled(p.body, false)
	_set_state(p, TC.PState.FINISHED)
	_emit(TC.Ev.FINISH, p.id, -1, finished_count, p.pos())


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
	p.diving = false
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
	_set_state(p, TC.PState.ACTIVE)


func _check_recover(p: SimPlayer) -> void:
	if p.state != TC.PState.ACTIVE and p.state != TC.PState.STUMBLE and p.state != TC.PState.EXITING:
		return
	var pp := p.pos()
	if pp.y > -6.0 and CampusLayout.BOUNDS.grow(-0.5).has_point(Vector2(pp.x, pp.z)):
		return
	# Out of bounds / fell through: return to a safe pad with no new progress.
	var pads: Array = layout.dorm_pads
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
			r.diving = false
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
			radius = cfg.noise_sprint_m if spd > cfg.runner_speed + 0.5 else cfg.noise_jog_m
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
			if d2 <= cfg.noise_sprint_m:
				out.append({"pos": dc["pos"], "kind": "steps", "loud": 1.0 - d2 / cfg.noise_sprint_m})
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
		})
	return {
		"match_id": match_id, "outcome": outcome, "players": rows, "fastest_slot": fastest,
		"fastest_time": fastest_t if fastest >= 0 else -1.0, "finished": finished_count,
		"needed": cfg.runners_needed, "targets": targets, "practice": practice,
		"round_time": round_time(),
	}
