class_name BotBrain
extends RefCounted
## Bots play by the same rules and produce the same InputCmd a human would.
## Information limits: they only use MatchSim.can_see (range + view cone +
## line of sight), MatchSim.noises_for (hearing), and patrol-visible splash
## markers. No omniscience, no teleporting.

## How far beyond tag reach a patrol bot starts its wind-up.
static var TAG_TRIGGER_SLACK := 0.6

enum Mode { PLAN, TRAVEL, APPROACH_WATER, FLEE, HOME, CHASE, INVESTIGATE, PATROL_ROUTE, TO_CART, IDLE }

var slot: int
var nav: NavGrid
var rng := RandomNumberGenerator.new()
var mode: int = Mode.PLAN
var path := PackedVector2Array()
var path_i := 0
var path_cart := false
var goal := Vector2.ZERO
var goal_kind := ""
var goal_water := -1
var replan_t := 0.0
var think_t := 0.0
var jump_cool := 0.0
var flee_t := 0.0
var threat := Vector3.INF
var threat_t := 0.0
var last_seen: Dictionary = {}     # runner slot -> {pos, t}
var investigate := Vector3.INF
var investigate_t := 0.0
var patrol_stops: Array = []
var stop_i := 0
var linger_t := 0.0
var stuck_t := 0.0
var stuck_count := 0
var unstick_t := 0.0
var unstick_dir := Vector2.ZERO
var reverse_t := 0.0
var last_pos := Vector3.ZERO
var pref_cart := -1
var prev_pressed := 0
## Measurement switch for game/tools/p9_balance.gd only (false = the 1.8
## path steering, to separate the Pass 9 bot fixes from the movement
## change in the balance matrix).  Always true in the game.
static var pass9_nav := true
var reaction := 0.0
var _path_wait := Vector2.INF     # goal of a path request waiting for budget
var _path_wait_cart := false
var skill := 1.0
var coin_i := -1


func _init(sim: MatchSim, p: SimPlayer) -> void:
	slot = p.id
	nav = NavGrid.shared(sim.layout)
	rng.seed = sim.seed_v * 31 + p.id * 7919
	pref_cart = p.id % maxi(sim.carts.size(), 1)
	if p.is_patrol():
		var patrol_index := 0
		for q in sim.players:
			if q.is_patrol() and q.id < p.id:
				patrol_index += 1
		pref_cart = patrol_index % maxi(sim.carts.size(), 1)
	skill = rng.randf_range(0.85, 1.0)


func think(sim: MatchSim, p: SimPlayer) -> InputCmd:
	var cmd := _think(sim, p)
	# Night Watch training: runner bots jog a little slower
	if sim.gentle_bots and p.is_runner():
		cmd.move *= 0.8
	return cmd


func _think(sim: MatchSim, p: SimPlayer) -> InputCmd:
	var cmd := InputCmd.new()
	var dt := sim.cfg.dt()
	if _path_wait != Vector2.INF:
		_repath(p.pos2(), _path_wait, _path_wait_cart)
	jump_cool = maxf(0.0, jump_cool - dt)
	replan_t -= dt
	cmd.cam_yaw = p.yaw
	if sim.phase != TC.Phase.PLAYING:
		return cmd
	match p.state:
		TC.PState.CAPTURED, TC.PState.FINISHED, TC.PState.SPLASHING, TC.PState.WAITING, TC.PState.ENTERING, TC.PState.EXITING:
			path = PackedVector2Array()
			mode = Mode.PLAN
			return cmd
	if p.is_runner():
		_runner(sim, p, cmd, dt)
	else:
		_patrol(sim, p, cmd, dt)
	cmd.quantize()
	return cmd


# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------
func _runner(sim: MatchSim, p: SimPlayer, cmd: InputCmd, dt: float) -> void:
	var cfg := sim.cfg
	# perceive patrol threats (sight with a wide personal awareness, or hearing)
	var nearest_threat := Vector3.INF
	var nd := 1e9
	for q in sim.players:
		if not q.is_patrol() or q.state == TC.PState.WAITING:
			continue
		var qp := q.pos()
		var d := qp.distance_to(p.pos())
		var seen := d < 9.0 and sim.has_los(p.pos() + Vector3(0, 1.4, 0), qp + Vector3(0, 1.2, 0))
		if not seen and d < cfg.view_range_m:
			seen = sim.can_see(p, qp, p.yaw, cfg.view_range_m * 0.8)
		if not seen:
			for n in sim.noises_for(p):
				if (n["pos"] as Vector3).distance_to(qp) < 2.0 and float(n["loud"]) > 0.35:
					seen = true
		if seen and d < nd:
			nd = d
			nearest_threat = qp
	var danger_r := 12.0 if p.state == TC.PState.ACTIVE else 0.0
	if nearest_threat != Vector3.INF and nd < danger_r and p.protect <= 0.0:
		threat = nearest_threat
		threat_t = 2.5
	else:
		threat_t = maxf(0.0, threat_t - dt)

	if threat_t > 0.0 and threat != Vector3.INF:
		_flee(sim, p, cmd, dt)
		return

	var remaining: Array = []
	for i in sim.targets.size():
		if (p.stamps & (1 << i)) == 0:
			remaining.append(int(sim.targets[i]))
	# (a coin detour in progress keeps its goal until the coin is gone)
	var detour := goal_kind == "coin" and coin_i >= 0 and coin_i < sim.coins.size() and int(sim.coins[coin_i]["by"]) < 0
	if detour:
		pass
	elif remaining.is_empty():
		if goal_kind != "home" or replan_t <= 0.0:
			_plan_home(sim, p)
	elif goal_kind != "water" or not remaining.has(goal_water) or replan_t <= 0.0:
		_plan_water(sim, p, remaining)

	# a gold coin close to where we are (never while heading into a water)
	if goal_kind != "coin" and not (goal_kind == "water" and p.pos2().distance_to(goal) < 6.0):
		var ci := _coin_near(sim, p, 7.0)
		if ci >= 0:
			var cpos: Vector3 = sim.coins[ci]["pos"]
			goal = Vector2(cpos.x, cpos.z)
			goal_kind = "coin"
			coin_i = ci
			_repath(p.pos2(), goal, false)
	if goal_kind == "coin" and (coin_i < 0 or coin_i >= sim.coins.size() or int(sim.coins[coin_i]["by"]) >= 0):
		replan_t = 0.0
		goal_kind = ""
		coin_i = -1
	# detour for a nearby gadget if empty-handed
	if p.gadget == TC.Gadget.NONE and goal_kind != "gadget" and goal_kind != "coin":
		for pk in sim.pickups:
			if float(pk["respawn"]) <= 0.0 and (pk["pos"] as Vector3).distance_to(p.pos()) < 9.0:
				goal = Vector2(pk["pos"].x, pk["pos"].z)
				goal_kind = "gadget"
				_repath(p.pos2(), goal, false)
				break
	if goal_kind == "gadget" and (p.gadget != TC.Gadget.NONE or p.pos2().distance_to(goal) < 0.8):
		replan_t = 0.0
		goal_kind = ""

	var near_goal := p.pos2().distance_to(goal) < 1.6
	if goal_kind == "water" and near_goal:
		# face the water and leap in (dive at apex sometimes)
		var w: Dictionary = sim.layout.waters[goal_water]
		var c: Vector2 = w["center"]
		var dir := (c - p.pos2()).normalized()
		cmd.move = dir
		if p.on_floor and jump_cool <= 0.0:
			cmd.pressed |= TC.BTN_JUMP
			jump_cool = 0.6
		elif not p.on_floor and p.vel.y < 0.5 and not p.diving and rng.randf() < 0.5:
			cmd.pressed |= TC.BTN_JUMP
		return
	_follow(sim, p, cmd, dt, false)
	_separate(sim, p, cmd)
	# (Pass 9: no sprint to pace: a full move input is the steady full speed)
	# Pass 9: paths may cross a low wall (weighted, not solid, on the foot
	# grid) and only the Night Watch and a fleeing runner hopped it; a runner
	# heading for a water or home pushed into it until the stuck hop
	if pass9_nav:
		_hop_obstacles(sim, p, cmd)


## Runners pass through each other, so without this bots sharing a nav path
## run stacked in single file. Steer gently away from teammates that are close.
func _separate(sim: MatchSim, p: SimPlayer, cmd: InputCmd) -> void:
	if cmd.move.length() < 0.3:
		return
	var push := Vector2.ZERO
	var pp := p.pos2()
	for q in sim.players:
		if q == p or not q.is_runner() or not q.is_in_play():
			continue
		var rel := pp - q.pos2()
		var d := rel.length()
		if d < 1.6:
			if d < 0.05:
				rel = Vector2(cmd.move.y, -cmd.move.x) * (1.0 if p.id > q.id else -1.0)
				d = 0.05
			push += rel.normalized() * (1.0 - d / 1.6)
	if push != Vector2.ZERO:
		cmd.move = (cmd.move + push * 0.7).normalized()


func _plan_water(sim: MatchSim, p: SimPlayer, remaining: Array) -> void:
	# best order over remaining targets by straight-line estimate (+ home)
	var best_first := int(remaining[0])
	var best_cost := 1e9
	var dorm := sim.layout.dorm_center(sim.home_dorm)
	var perms: Array = [remaining]
	if remaining.size() == 2:
		perms = [[remaining[0], remaining[1]], [remaining[1], remaining[0]]]
	elif remaining.size() == 3:
		perms = RulesLogic.permutations3(remaining)
	for perm in perms:
		var cost := 0.0
		var at := p.pos2()
		for wi in perm:
			var c: Vector2 = sim.layout.waters[int(wi)]["center"]
			cost += at.distance_to(c)
			at = c
		cost += at.distance_to(dorm)
		# personal route preference: stable per bot and order (no flip-flopping
		# between replans), large enough that bots don't all pick one order
		cost += float(absi(hash([slot, sim.seed_v, perm])) % 1000) * 0.045
		if cost < best_cost:
			best_cost = cost
			best_first = int(perm[0])
	goal_water = best_first
	var w: Dictionary = sim.layout.waters[goal_water]
	# pick the jump point nearest to us (but not right next to a known patrol)
	var best_jp: Vector2 = w["jump_points"][0]
	var bd := 1e9
	for jp in w["jump_points"]:
		var d := p.pos2().distance_to(jp)
		for q in sim.players:
			if q.is_patrol() and last_seen.has(q.id):
				pass
		if d < bd:
			bd = d
			best_jp = jp
	goal = best_jp
	goal_kind = "water"
	replan_t = 4.0
	_repath(p.pos2(), goal, false)


## Home: run in through one of tonight's home doors (V6).  The goal is a
## point just inside the chosen door, so the path goes through the opening
## and the threshold crossing finishes the round for us.
func _plan_home(sim: MatchSim, p: SimPlayer) -> void:
	var doors: Array = sim.home_doors
	var best: Vector2 = (doors[0] as Dictionary)["inside"] if not doors.is_empty() else sim.layout.dorm_center(sim.home_dorm)
	var bd := 1e9
	for d in doors:
		var approach: Vector2 = d["approach"]
		var cost := p.pos2().distance_to(approach)
		if threat != Vector3.INF and threat_t > 0.0:
			cost += 40.0 / maxf(1.0, Vector2(threat.x, threat.z).distance_to(approach)) * 10.0
		if cost < bd:
			bd = cost
			best = d["inside"]
	goal = best
	goal_kind = "home"
	replan_t = 3.0
	_repath(p.pos2(), goal, false)


func _flee(sim: MatchSim, p: SimPlayer, cmd: InputCmd, dt: float) -> void:
	var cfg := sim.cfg
	var away := p.pos2() - Vector2(threat.x, threat.z)
	if away.length() < 0.1:
		away = Vector2(1, 0)
	away = away.normalized()
	# keep making progress toward the goal if it is not toward the threat
	var to_goal := (goal - p.pos2()).normalized() if goal != Vector2.ZERO else away
	var dir := away
	if to_goal.dot(away) > -0.2:
		dir = (away * 0.6 + to_goal * 0.4).normalized()
	# avoid running into walls: probe a few angles on the nav grid
	var best := dir
	var best_score := -1e9
	for k in 9:
		var ang := (float(k) - 4.0) * 0.35
		var cand := dir.rotated(ang)
		var probe := p.pos2() + cand * 4.0
		var score := cand.dot(away) * 2.0 + cand.dot(to_goal) * 0.6 - absf(ang) * 0.2
		if not nav.is_walkable(probe) or not nav.is_walkable(p.pos2() + cand * 2.0):
			score -= 10.0
		if score > best_score:
			best_score = score
			best = cand
	cmd.move = best
	var d := p.pos2().distance_to(Vector2(threat.x, threat.z))
	if p.gadget == TC.Gadget.TURBO and d < 8.0:
		cmd.pressed |= TC.BTN_GADGET
		cmd.cam_yaw = atan2(-best.x, -best.y)
	elif p.gadget == TC.Gadget.DECOY and d < 14.0:
		cmd.pressed |= TC.BTN_GADGET
		cmd.cam_yaw = atan2(best.x, best.y)  # toss sideways-back
	elif p.gadget == TC.Gadget.SPLASH_BOMB:
		for c in sim.carts:
			if c.occupant >= 0 and c.pos().distance_to(p.pos()) < 12.0:
				var rel := c.pos() - p.pos()
				cmd.cam_yaw = atan2(-rel.x, -rel.z)
				cmd.move = Vector2.ZERO
				cmd.pressed |= TC.BTN_GADGET
	# dive to snatch distance when the patrol is about to lunge
	if d < 3.0 and jump_cool <= 0.0 and p.on_floor:
		cmd.pressed |= TC.BTN_JUMP
		jump_cool = 1.2
	elif not p.on_floor and not p.diving and d < 3.5 and p.vel.y < 1.5:
		cmd.pressed |= TC.BTN_JUMP
	_hop_obstacles(sim, p, cmd)
	replan_t = 0.0


# ---------------------------------------------------------------------------
# Patrol
# ---------------------------------------------------------------------------
func _patrol(sim: MatchSim, p: SimPlayer, cmd: InputCmd, dt: float) -> void:
	var cfg := sim.cfg
	var in_cart := p.state == TC.PState.IN_CART
	var view_yaw := sim.carts[p.cart_id].yaw if in_cart and p.cart_id >= 0 else p.yaw
	# --- perceive runners (same limits as humans)
	var target: SimPlayer = null
	var td := 1e9
	for r in sim.players:
		# (a runner inside the home dorm can't be tagged: not a target)
		if not r.is_runner() or not r.is_in_play() or r.home_safe:
			continue
		var seen := sim.can_see(p, r.pos(), view_yaw, cfg.view_range_m)
		if not seen and r.pos().distance_to(p.pos()) < 6.0:
			seen = sim.has_los(p.pos() + Vector3(0, 1.3, 0), r.pos() + Vector3(0, 1.0, 0))
		if seen:
			last_seen[r.id] = {"pos": r.pos(), "vel": r.vel, "t": sim.tick}
			var d := r.pos().distance_to(p.pos())
			if r.protect > 0.0 or r.bump_protect > 0.0:
				d += 8.0
			if d < td:
				td = d
				target = r
	# hearing + splash markers feed investigation
	if target == null:
		var loudest := 0.0
		for n in sim.noises_for(p):
			if float(n["loud"]) > loudest:
				loudest = float(n["loud"])
				investigate = n["pos"]
				investigate_t = 6.0
		for m in sim.splash_markers:
			var wc: Vector2 = sim.layout.waters[int(m["water"])]["center"]
			if investigate_t <= 0.0 or rng.randf() < 0.02:
				investigate = Vector3(wc.x, 0, wc.y)
				investigate_t = 10.0
	investigate_t = maxf(0.0, investigate_t - dt)

	var cart_c: SimCart = sim.carts[p.cart_id] if in_cart else null
	if target != null:
		var lead := target.pos() + target.vel * clampf(td / 8.0, 0.0, 1.2)
		if in_cart:
			if td < 10.0 or not nav.is_drivable(Vector2(lead.x, lead.z)) and td < 22.0:
				cmd.pressed |= TC.BTN_INTERACT   # hop out and chase on foot
				cmd.drive = -1.0
				return
			var lead2 := Vector2(lead.x, lead.z)
			_drive_to(sim, p, cart_c, lead2, cmd, dt, true)
			return
		# on foot: chase, tag when close, go back to cart if they get away
		if td > 30.0 and _free_cart_near(sim, p, 18.0) >= 0:
			_go_to_cart(sim, p, cmd, dt)
			return
		var tp := Vector2(lead.x, lead.z)
		if path.is_empty() or replan_t <= 0.0 or goal.distance_to(tp) > 3.0:
			goal = tp
			goal_kind = "chase"
			replan_t = 0.5
			_repath(p.pos2(), goal, false)
		if td < 6.0 and sim.has_los(p.pos() + Vector3(0, 1.0, 0), target.pos() + Vector3(0, 1.0, 0)):
			var rel := target.pos() - p.pos()
			cmd.move = Vector2(rel.x, rel.z).normalized()
		else:
			_follow(sim, p, cmd, dt, false)
		reaction -= dt
		# a runner faster than the Night Watch on foot (Turbo, a dive; Pass 8
		# and earlier: a sprint) outpaces the wind-up: wait until closer
		var outpaces := Vector2(target.vel.x, target.vel.z).length() > cfg.patrol_speed + 0.05
		var slack := TAG_TRIGGER_SLACK if not outpaces else 0.05
		if td < cfg.tag_reach_m + slack and p.tag_cd <= 0.0 and p.tag_lockout <= 0.0:
			if reaction <= 0.0:
				cmd.pressed |= TC.BTN_TAG
				var rel2 := target.pos() - p.pos()
				cmd.cam_yaw = atan2(-rel2.x, -rel2.z)
				reaction = rng.randf_range(0.12, 0.3) / skill
		_hop_obstacles(sim, p, cmd)
		return

	# --- no runner in sight: investigate or patrol a route
	var dest := Vector2.INF
	if investigate_t > 0.0 and investigate != Vector3.INF:
		dest = Vector2(investigate.x, investigate.z)
		if p.pos2().distance_to(dest) < 4.0:
			investigate_t = 0.0
	if dest == Vector2.INF:
		if patrol_stops.is_empty():
			_make_patrol_route(sim)
		var stop: Vector2 = patrol_stops[stop_i % patrol_stops.size()]
		if p.pos2().distance_to(stop) < 8.0:
			linger_t += dt
			if linger_t > rng.randf_range(3.0, 6.0):
				linger_t = 0.0
				stop_i += 1
		dest = patrol_stops[stop_i % patrol_stops.size()]
	if in_cart:
		var drive_dest := _park_point(sim, dest)
		if p.pos2().distance_to(drive_dest) < 6.0 and p.pos2().distance_to(dest) > 8.0:
			cmd.pressed |= TC.BTN_INTERACT   # park and walk in
			cmd.drive = -1.0
			return
		_drive_to(sim, p, cart_c, drive_dest, cmd, dt, false)
		return
	if p.pos2().distance_to(dest) > 45.0 and _free_cart_near(sim, p, 25.0) >= 0:
		_go_to_cart(sim, p, cmd, dt)
		return
	# a gold coin right beside our route
	var ci := _coin_near(sim, p, 6.0)
	if ci >= 0:
		var cpos: Vector3 = sim.coins[ci]["pos"]
		dest = Vector2(cpos.x, cpos.z)
	if goal.distance_to(dest) > 2.0 or path.is_empty() or replan_t <= 0.0:
		goal = dest
		goal_kind = "patrol"
		replan_t = 3.0
		_repath(p.pos2(), goal, false)
	_follow(sim, p, cmd, dt, false)
	_hop_obstacles(sim, p, cmd)
	cmd.cam_yaw = p.yaw + sin(float(sim.tick) * 0.03 + slot) * 0.9   # look around


## Where a cart stops for a destination: the nearest drivable cell (a
## search toward an enclosed cell would explore the whole road network for
## nothing).
func _park_point(_sim: MatchSim, dest: Vector2) -> Vector2:
	return nav.to_world(nav.nearest_open(nav.cart, dest, 30))


func _make_patrol_route(sim: MatchSim) -> void:
	patrol_stops.clear()
	for wi in sim.targets:
		var w: Dictionary = sim.layout.waters[int(wi)]
		patrol_stops.append(w["center"])
	# tonight's home dorm: outside each of its doors
	for d in sim.home_doors:
		patrol_stops.append((d["approach"] as Vector2) + (d["normal"] as Vector2) * 4.0)
	# shuffle deterministically so two patrol bots split up
	for i in patrol_stops.size():
		var j := rng.randi_range(0, patrol_stops.size() - 1)
		var t: Variant = patrol_stops[i]
		patrol_stops[i] = patrol_stops[j]
		patrol_stops[j] = t
	stop_i = slot % patrol_stops.size()


## The nearest coin still out within `radius` (and reachable on the nav
## grid), or -1.
func _coin_near(sim: MatchSim, p: SimPlayer, radius: float) -> int:
	var best := -1
	var bd := radius
	for i in sim.coins.size():
		if int(sim.coins[i]["by"]) >= 0:
			continue
		var cp: Vector3 = sim.coins[i]["pos"]
		var d := p.pos().distance_to(cp)
		if d < bd and nav.is_walkable(Vector2(cp.x, cp.z)):
			bd = d
			best = i
	return best


func _free_cart_near(sim: MatchSim, p: SimPlayer, radius: float) -> int:
	var best := -1
	var bd := radius
	for c in sim.carts:
		if c.occupant >= 0:
			continue
		var d := c.pos().distance_to(p.pos())
		if c.id == pref_cart:
			d -= 6.0
		if d < bd:
			bd = d
			best = c.id
	return best


func _go_to_cart(sim: MatchSim, p: SimPlayer, cmd: InputCmd, dt: float) -> void:
	var cid := _free_cart_near(sim, p, 60.0)
	if cid < 0:
		return
	var c: SimCart = sim.carts[cid]
	var cp := Vector2(c.pos().x, c.pos().z)
	if p.pos2().distance_to(cp) < sim.cfg.cart_enter_range_m + 0.4:
		cmd.pressed |= TC.BTN_INTERACT
		return
	if goal.distance_to(cp) > 1.5 or path.is_empty() or replan_t <= 0.0:
		goal = cp
		goal_kind = "cart"
		replan_t = 1.5
		_repath(p.pos2(), cp, false)
	_follow(sim, p, cmd, dt, false)
	_hop_obstacles(sim, p, cmd)


func _drive_to(sim: MatchSim, p: SimPlayer, c: SimCart, dest: Vector2, cmd: InputCmd, dt: float, urgent: bool) -> void:
	if not path_cart or path.is_empty() or replan_t <= 0.0 or goal.distance_to(dest) > 4.0:
		goal = dest
		path_cart = true
		replan_t = 1.0 if urgent else 2.5
		# V6: bounded; V8: while a background search runs, a path already
		# leading to this destination is kept
		var np := nav.find_path_budgeted(Vector2(c.pos().x, c.pos().z), dest, true)
		if not nav.deferred or not _leads_to(dest, true):
			path = np
			path_i = 0
	var cp := Vector2(c.pos().x, c.pos().z)
	# pure pursuit: aim ~6 m ahead along the path
	var aim := dest
	while path_i < path.size() and cp.distance_to(path[path_i]) < 5.0:
		path_i += 1
	if path_i < path.size():
		aim = path[path_i]
	var fwd := Vector2(c.forward().x, c.forward().z)
	var to := (aim - cp)
	var ang := fwd.angle_to(to.normalized()) if to.length() > 0.1 else 0.0
	# angle_to is positive counter-clockwise in screen space (x right, y=z down) => turn right
	cmd.steer = clampf(ang * 1.8, -1.0, 1.0)
	var dist := cp.distance_to(dest)
	cmd.drive = 1.0
	if absf(ang) > 1.1:
		cmd.drive = 0.35
	if dist < 10.0 and not urgent:
		cmd.drive = 0.3 if absf(c.speed) < 4.0 else -0.6
	# stuck: back up with opposite lock
	if absf(c.speed) < 0.6 and cmd.drive > 0.2:
		stuck_t += dt
	else:
		stuck_t = maxf(0.0, stuck_t - dt * 2.0)
	if stuck_t > 1.2:
		reverse_t = 1.1
		stuck_t = 0.0
		replan_t = 0.0
	if reverse_t > 0.0:
		reverse_t -= dt
		cmd.drive = -1.0
		cmd.steer = -cmd.steer
	cmd.cam_yaw = c.yaw


func _repath(from: Vector2, to: Vector2, cart: bool) -> void:
	# V6: bounded per tick (NavGrid.find_path_budgeted); a request that has
	# to wait is retried next tick while the bot steers at its goal.
	# V8: the search runs in the background for a few ticks: a bot that
	# already follows a path to (about) the same goal keeps following it
	# meanwhile instead of dropping it and walking straight at the goal
	var np := nav.find_path_budgeted(from, to, cart)
	_path_wait_cart = cart
	if nav.deferred:
		_path_wait = to
		if not _leads_to(to, cart):
			path = PackedVector2Array()
			path_i = 0
		return
	_path_wait = Vector2.INF
	path = np
	path_cart = cart
	path_i = 1 if path.size() > 1 else 0


## The current path ends near `to` (and is of the same kind).
func _leads_to(to: Vector2, cart: bool) -> bool:
	return path.size() >= 2 and path_cart == cart and path[path.size() - 1].distance_to(to) < 3.0


func _follow(sim: MatchSim, p: SimPlayer, cmd: InputCmd, dt: float, _cart: bool) -> void:
	if path.is_empty():
		var d := goal - p.pos2()
		if d.length() > 0.5:
			cmd.move = d.normalized()
		return
	var pp := p.pos2()
	if unstick_t > 0.0:
		# backing off a corner we kept running into, then re-path from there
		unstick_t -= dt
		cmd.move = unstick_dir
		last_pos = p.pos()
		if unstick_t <= 0.0:
			replan_t = 0.0
		return
	while path_i < path.size() - 1 and pp.distance_to(path[path_i]) < 1.1:
		path_i += 1
	var wp := path[mini(path_i, path.size() - 1)]
	if path_i >= path.size() - 1 and pp.distance_to(wp) < 1.1 + nav.cell:
		# the path ends on the centre of the goal's nearest open cell, up to
		# a 2 m cell short of a goal in the water (a jump point) or on a
		# blocked cell: the last step heads for the goal itself
		wp = goal
	var dir := wp - pp
	if dir.length() > 0.05:
		cmd.move = _along_walls(sim, p, dir.normalized())
	# stuck detection (horizontal progress only: hopping in place is still stuck)
	var moved := Vector2(p.pos().x - last_pos.x, p.pos().z - last_pos.z).length()
	if moved < 0.02 and cmd.move.length() > 0.5:
		stuck_t += dt
		if stuck_t > 0.7:
			stuck_t = 0.0
			replan_t = 0.0
			stuck_count += 1
			if stuck_count >= 2:
				# hop didn't free us: step back and to one side, then try again
				var side := 1.0 if rng.randf() < 0.5 else -1.0
				unstick_dir = (Vector2(-cmd.move.y, cmd.move.x) * side - cmd.move * 0.7).normalized()
				unstick_t = 0.6
				stuck_count = 0
			else:
				cmd.pressed |= TC.BTN_JUMP
	elif moved > 0.04:
		stuck_t = 0.0
		stuck_count = 0
	last_pos = p.pos()


## Pass 9: a long path segment that passes a wall closer than the capsule
## (or a bot pushed a little off its line) ran into the wall at a shallow
## angle and slid along it at cos(angle) of its speed, slowing for seconds
## (the same on 1.8).  Like a person, run along a tall wall's face instead,
## at full input, until past it.  A low wall (hoppable: nothing at 1.25 m)
## is left to the hop, head-on contact to the stuck detection.  Applies to
## every bot, either role.
func _along_walls(sim: MatchSim, p: SimPlayer, want: Vector2) -> Vector2:
	if not pass9_nav or not p.on_floor or p.state != TC.PState.ACTIVE:
		return want
	var b := p.body
	for k in b.get_slide_collision_count():
		var c := b.get_slide_collision(k)
		var n3 := c.get_normal()
		var n := Vector2(n3.x, n3.z)
		if absf(n3.y) > 0.7 or n.length() < 0.5:
			continue
		n = n.normalized()
		var into := want.dot(n)
		if into >= -0.05 or into <= -0.9:
			continue
		var at := p.pos() + Vector3(0, 1.25, 0)
		var tall := sim.space_state().intersect_ray(PhysicsRayQueryParameters3D.create(at, at - Vector3(n.x, 0, n.y) * 1.0, TC.L_WORLD))
		if tall.is_empty():
			continue
		return (want - n * into).normalized()
	return want


func _hop_obstacles(sim: MatchSim, p: SimPlayer, cmd: InputCmd) -> void:
	if not p.on_floor or jump_cool > 0.0 or cmd.move.length() < 0.3:
		return
	var dir := Vector3(cmd.move.x, 0, cmd.move.y).normalized()
	var base := p.pos()
	var low := sim.space_state().intersect_ray(PhysicsRayQueryParameters3D.create(base + Vector3(0, 0.35, 0), base + Vector3(0, 0.35, 0) + dir * 1.3, TC.L_WORLD))
	# rising ground (a slope the capsule walks up) is no obstacle
	if low.is_empty() or (low["normal"] as Vector3).y > 0.64:
		return
	var high := sim.space_state().intersect_ray(PhysicsRayQueryParameters3D.create(base + Vector3(0, 1.25, 0), base + Vector3(0, 1.25, 0) + dir * 1.6, TC.L_WORLD))
	if high.is_empty():
		cmd.pressed |= TC.BTN_JUMP
		jump_cool = 0.5
