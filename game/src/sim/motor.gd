class_name Motor
extends RefCounted
## Deterministic movement shared by the authoritative host and client-side
## prediction. Must only depend on (state, input, config, static world).

const CHAR_RADIUS := 0.35
const CHAR_HEIGHT := 1.5
const FLOOR_SNAP := 0.35


static func make_character_body(name: String) -> CharacterBody3D:
	var b := CharacterBody3D.new()
	b.name = name
	b.collision_layer = TC.L_CHAR
	b.collision_mask = TC.L_WORLD | TC.L_CART
	b.floor_max_angle = deg_to_rad(50.0)
	b.floor_snap_length = FLOOR_SNAP
	b.floor_stop_on_slope = true
	b.floor_block_on_wall = true
	b.max_slides = 5
	b.safe_margin = 0.02
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = CHAR_RADIUS
	cap.height = CHAR_HEIGHT
	cs.shape = cap
	cs.position = Vector3(0, CHAR_HEIGHT * 0.5, 0)
	b.add_child(cs)
	return b


static func make_cart_body(name: String) -> CharacterBody3D:
	var b := CharacterBody3D.new()
	b.name = name
	b.collision_layer = TC.L_CART
	b.collision_mask = TC.L_WORLD | TC.L_CART_BLOCK | TC.L_CART
	b.floor_max_angle = deg_to_rad(35.0)
	b.floor_snap_length = 0.5
	b.floor_stop_on_slope = true
	b.max_slides = 4
	b.safe_margin = 0.03
	b.wall_min_slide_angle = deg_to_rad(10.0)
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = SimCart.HALF * 2.0 - Vector3(0, 0.6, 0)
	cs.shape = bx
	cs.position = Vector3(0, SimCart.HALF.y - 0.0, 0)
	b.add_child(cs)
	return b


static func set_body_enabled(b: CharacterBody3D, enabled: bool, is_cart: bool = false) -> void:
	if is_cart:
		b.collision_layer = TC.L_CART if enabled else 0
		b.collision_mask = (TC.L_WORLD | TC.L_CART_BLOCK | TC.L_CART) if enabled else 0
	else:
		b.collision_layer = TC.L_CHAR if enabled else 0
		b.collision_mask = (TC.L_WORLD | TC.L_CART) if enabled else 0


## Movement-relevant timers + short state transitions shared by host and
## client prediction. Returns true if a tag lunge just ended without a hit.
static func advance_timers(p: SimPlayer, cfg: RulesConfig, dt: float) -> bool:
	var missed := false
	p.state_t += dt
	match p.state:
		TC.PState.STUMBLE:
			if p.state_t >= cfg.stumble_s:
				p.state = TC.PState.ACTIVE
				p.state_t = 0.0
		TC.PState.EXITING:
			if p.state_t >= cfg.cart_exit_s:
				p.state = TC.PState.ACTIVE
				p.state_t = 0.0
		TC.PState.ENTERING:
			if p.state_t >= cfg.cart_enter_s:
				p.state = TC.PState.IN_CART
				p.state_t = 0.0
	if p.tag_phase != SimPlayer.TagPhase.NONE:
		p.tag_t += dt
		match p.tag_phase:
			SimPlayer.TagPhase.ANTICIPATE:
				if p.tag_t >= cfg.tag_anticipation_s:
					p.tag_phase = SimPlayer.TagPhase.LUNGE
					p.tag_t = 0.0
			SimPlayer.TagPhase.LUNGE:
				if p.tag_t >= cfg.tag_lunge_s:
					p.tag_phase = SimPlayer.TagPhase.RECOVER
					p.tag_t = 0.0
					p.tag_cd = cfg.tag_miss_cooldown_s
					missed = true
			SimPlayer.TagPhase.RECOVER:
				p.tag_target = -1
				if p.tag_t >= 0.2:
					p.tag_phase = SimPlayer.TagPhase.NONE
					p.tag_t = 0.0
	return missed


## Advance an on-foot character by one tick. Returns nothing; flags on p.
static func step_foot(p: SimPlayer, cmd: InputCmd, cfg: RulesConfig, dt: float) -> void:
	var b := p.body
	p.jumped_this_tick = false
	p.landed_this_tick = false
	var runner := p.is_runner()
	# p.on_floor is the floor state after the previous move; it is part of the
	# serialized motor state so host and predicting client step identically.
	if p.on_floor:
		if p.air_t > 0.0:
			p.landed_this_tick = true
		p.air_t = 0.0
		if p.diving:
			p.diving = false
			p.dive_land = cfg.dive_land_s
		p.coyote = cfg.coyote_time_s
	else:
		p.coyote = maxf(0.0, p.coyote - dt)
		p.air_t += dt

	# --- timers
	p.turbo_t = maxf(0.0, p.turbo_t - dt)
	p.dive_land = maxf(0.0, p.dive_land - dt)
	p.tag_cd = maxf(0.0, p.tag_cd - dt)
	p.tag_lockout = maxf(0.0, p.tag_lockout - dt)

	var stumbling := p.state == TC.PState.STUMBLE
	var control := 1.0
	if stumbling:
		control = 0.0
	elif p.dive_land > 0.0:
		control = 0.35

	# --- speed (Pass 9): one continuous analog speed. The input magnitude
	# (after the device's dead zone and curve: walking, jogging, running)
	# scales the role's full-input speed, and a held full input keeps it for
	# as long as it is held. No sprint button, meter, refill or latch (V4 to
	# Pass 8 had a 2.5 s meter to 7.4 m/s over a 5.0 m/s run); BTN_SPRINT is
	# ignored, so an old binding or client can't add speed.
	var move := cmd.move
	var mag := minf(move.length(), 1.0)
	var top := full_speed(p, cfg)
	if p.turbo_t > 0.0:
		top = minf(top * cfg.turbo_multiplier, cfg.turbo_speed_cap)
	var target := Vector2.ZERO
	if mag > 0.01:
		target = move.normalized() * top * mag * control

	# --- tag lunge phases (patrol)
	if p.tag_phase == SimPlayer.TagPhase.ANTICIPATE:
		target *= cfg.tag_anticipation_move_scale
	var hv := Vector2(p.vel.x, p.vel.z)
	var lunging := p.tag_phase == SimPlayer.TagPhase.LUNGE

	if lunging:
		var f := p.facing()
		hv = Vector2(f.x, f.z) * cfg.tag_lunge_speed
	elif p.diving:
		# committed dive: keep momentum, tiny steering
		if mag > 0.1:
			var d := hv.length()
			var steer := hv.normalized().lerp(move.normalized(), 0.04 * control)
			hv = steer.normalized() * d
	elif stumbling:
		hv = hv.move_toward(Vector2.ZERO, 6.0 * dt)
	else:
		var accel: float
		if p.on_floor:
			accel = cfg.ground_accel if target.length() >= hv.length() * 0.9 else cfg.ground_decel
		else:
			accel = cfg.air_accel
		hv = hv.move_toward(target, accel * dt)

	# --- jump / dive
	# Pass 8: one dive per airborne sequence, and a dive's landing recovery
	# (dive_land) must finish before the next takeoff. Presses during a dive
	# are dropped; during recovery only a press within jump_buffer_s of its
	# end may wait for it (V4-V8 buffered any press and jumped on the landing
	# tick, so jump/dive presses chained into a sustained 8+ m/s).
	var recovering := p.dive_land > 0.0
	if cmd.is_pressed(TC.BTN_JUMP) and control > 0.0:
		var grounded := p.on_floor or p.coyote > 0.0
		if not grounded and runner and not p.diving and not recovering and p.state == TC.PState.ACTIVE:
			# second press while airborne: dive
			p.diving = true
			p.jump_buf = 0.0
			var dir := Vector2(p.facing().x, p.facing().z)
			if mag > 0.2:
				dir = move.normalized()
			hv = dir * maxf(hv.length(), cfg.dive_speed)
			p.vel.y = maxf(p.vel.y, cfg.dive_up_velocity)
		elif p.diving:
			p.jump_buf = 0.0
		elif recovering:
			p.jump_buf = cfg.jump_buffer_s if p.dive_land <= cfg.jump_buffer_s else 0.0
		else:
			p.jump_buf = cfg.jump_buffer_s
	else:
		p.jump_buf = maxf(0.0, p.jump_buf - dt)
	if p.jump_buf > 0.0 and (p.on_floor or p.coyote > 0.0) and not p.diving and not recovering and control > 0.0 and p.tag_phase != SimPlayer.TagPhase.LUNGE:
		p.vel.y = cfg.jump_velocity if runner else cfg.patrol_jump_velocity
		p.jump_buf = 0.0
		p.coyote = 0.0
		p.on_floor = false
		p.jumped_this_tick = true

	# --- gravity
	if not p.on_floor or p.vel.y > 0.0:
		p.vel.y = maxf(p.vel.y - cfg.gravity * dt, -cfg.max_fall_speed)
	else:
		p.vel.y = 0.0

	# --- facing (an assisted wind-up keeps its aim; the sim tracks the target)
	if lunging or p.diving or (p.tag_phase == SimPlayer.TagPhase.ANTICIPATE and p.tag_target >= 0):
		pass
	elif hv.length() > 0.6 and control > 0.0:
		var want := atan2(-hv.x, -hv.y)
		p.yaw = rotate_toward(p.yaw, want, deg_to_rad(cfg.turn_rate_deg) * dt)

	b.velocity = Vector3(hv.x, p.vel.y, hv.y)
	# Pass 8: move_and_slide only snaps to the floor when the body was on it
	# after its previous move, which is engine-internal state that a
	# reconcile (apply_motor) can't restore. Tie the snap to the serialized
	# p.on_floor instead, so a predicting client replays a landing on the
	# same tick as the host (a stale "was on floor" snapped an airborne
	# replay down up to 0.35 m early: a 0.27 m correction at every dive
	# landing once landings stopped chaining into a jump). On the host the
	# two always agree.
	b.floor_snap_length = FLOOR_SNAP if p.on_floor else 0.0
	b.move_and_slide()
	var rv := b.velocity
	p.vel = Vector3(rv.x, rv.y, rv.z)
	p.on_floor = b.is_on_floor()
	if p.on_floor and p.vel.y < 0.0:
		p.vel.y = 0.0
	if b.is_on_ceiling() and p.vel.y > 0.0:
		p.vel.y = 0.0

	# stuck recovery: pushing into something for a long time nudges upward/back
	if mag > 0.5 and Vector2(rv.x, rv.z).length() < 0.2 and p.on_floor and not lunging:
		p.stuck_t += dt
		if p.stuck_t > 1.5:
			p.stuck_t = 0.0
			b.global_position += Vector3(-move.x, 0.0, -move.y) * 0.3 + Vector3(0, 0.05, 0)
	else:
		p.stuck_t = 0.0
	# Pass 9: "fast" from the speed actually moved, not from a button
	p.fast = p.on_floor and not p.diving and Vector2(p.vel.x, p.vel.z).length() >= full_speed(p, cfg) * cfg.fast_fraction


## The role's full-input foot speed (Pass 9: steady; Turbo is applied on top).
static func full_speed(p: SimPlayer, cfg: RulesConfig) -> float:
	return cfg.runner_speed if p.is_runner() else cfg.patrol_speed


## Advance a cart one tick with driver intent (cmd may be null for no driver).
static func step_cart(c: SimCart, cmd: InputCmd, cfg: RulesConfig, dt: float, layout: CampusLayout) -> void:
	var b := c.body
	c.slowed_t = maxf(0.0, c.slowed_t - dt)
	c.immunity_t = maxf(0.0, c.immunity_t - dt)
	for k in c.bump_cd.keys():
		c.bump_cd[k] = float(c.bump_cd[k]) - dt
		if c.bump_cd[k] <= 0.0:
			c.bump_cd.erase(k)
	var p := c.pos()
	c.on_road = layout.is_on_road(Vector2(p.x, p.z), 0.6)
	var vmax := cfg.cart_max_speed_road if c.on_road else cfg.cart_max_speed_offroad
	if c.slowed_t > 0.0:
		vmax = minf(vmax, cfg.bomb_slow_max_speed)
	var drive := 0.0
	var steer_in := 0.0
	if cmd != null and c.occupant >= 0 and not c.exiting:
		drive = cmd.drive
		steer_in = cmd.steer
	if c.exiting:
		c.speed = move_toward(c.speed, 0.0, cfg.cart_exit_auto_brake * dt)
	elif drive > 0.05:
		if c.speed < -0.1:
			c.speed = move_toward(c.speed, 0.0, cfg.cart_brake * drive * dt)
		else:
			c.speed += cfg.cart_accel * drive * dt
	elif drive < -0.05:
		if c.speed > 0.2:
			c.speed = move_toward(c.speed, 0.0, cfg.cart_brake * -drive * dt)
		else:
			c.speed = maxf(c.speed - cfg.cart_accel * 0.8 * -drive * dt, -cfg.cart_reverse_max)
	else:
		c.speed = move_toward(c.speed, 0.0, cfg.cart_coast_drag * dt)
	if c.speed > vmax:
		c.speed = move_toward(c.speed, vmax, 7.0 * dt)
	c.steer_s = move_toward(c.steer_s, steer_in, 4.5 * dt)
	var t := clampf(absf(c.speed) / cfg.cart_max_speed_road, 0.0, 1.0)
	var radius := lerpf(cfg.cart_turn_radius_slow, cfg.cart_turn_radius_fast, t)
	if absf(c.speed) > 0.25:
		c.yaw -= c.steer_s * c.speed / radius * dt
	b.rotation = Vector3(0, c.yaw, 0)
	var vy := b.velocity.y
	if b.is_on_floor():
		vy = -0.5
	else:
		vy -= cfg.gravity * dt
	var fwd := c.forward()
	b.velocity = fwd * c.speed + Vector3(0, vy, 0)
	b.move_and_slide()
	c.wall_hit = false
	var real := b.get_real_velocity()
	var along := Vector3(real.x, 0, real.z).dot(fwd)
	for i in b.get_slide_collision_count():
		var col := b.get_slide_collision(i)
		var n := col.get_normal()
		if absf(n.y) < 0.5 and absf(n.dot(fwd)) > 0.6 and absf(c.speed) > 3.0:
			c.wall_hit = true
	if c.wall_hit:
		c.speed = along * cfg.cart_wall_speed_keep
	elif absf(c.speed) > 0.5:
		# sliding along walls naturally reduces forward speed
		if absf(along) < absf(c.speed) - 0.5:
			c.speed = along
