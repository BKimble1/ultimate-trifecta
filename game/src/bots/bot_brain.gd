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
var _hidden_t := 0.0
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
## (NP) progress toward the current waypoint: a bot sliding back and forth
## on a building corner its smoothed path cuts moves every tick, so the
## per-tick stuck test never fires; no gain on the waypoint for
## WP_STALL_S counts as stuck too
var _wp_at := Vector2.INF
var _wp_best := INF
var _wp_t := 0.0
const WP_STALL_S := 1.5
## (build 33) a runner bot dives away when the Night Watch is this close
## (was 3.0 m): diving a beat early spends the dive before the lunge, so
## open-ground chases end about 5% sooner (tests/test_chase_balance.gd:
## 6.0 / 9.1 / 6.1 / 8.2 s, were 6.3 / 9.6 / 6.5 / 8.6 s)
const DIVE_R := 3.3
## (build 35) "As a cop it's so hard to get a bot because they just swerve
## you so well": runner bots are now a person who is a beat slow and not
## always clever.  They notice a Night Watch closing in later (FLEE_R) and
## after a reaction delay; each chase they draw how they'll run it: some
## boost away once the Watch is close (BOOST_R), about half try an escape
## dive and at a distance that is often wrong, some panic and run straight
## away without looking for open ground (dead ends included), some freeze
## for a moment first; and they pick a new direction only every
## FLEE_TURN_S, not every tick.  Measured in tests/test_bot_fairness.gd.
const FLEE_R := 9.0
const RUNNER_REACT := Vector2(0.3, 0.6)
const BOOST_R := 4.5
const FLEE_TURN_S := 0.45
var chase_boost := false
var dive_r := DIVE_R
var will_dive := true
var panic := false
var freeze_t := 0.0
var flee_dir := Vector2.ZERO
var flee_turn_t := 0.0
var notice_t := -1.0
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
		TC.PState.CAPTURED, TC.PState.FINISHED, TC.PState.OUT, TC.PState.SPLASHING, TC.PState.WAITING, TC.PState.ENTERING, TC.PState.EXITING:
			path = PackedVector2Array()
			mode = Mode.PLAN
			return cmd
	if p.is_runner():
		if p.state == TC.PState.IN_CART:
			# (build 35) a runner's seat a bot took over at the wheel: stop
			# and get out (runner bots run)
			cmd.drive = -1.0
			cmd.pressed |= TC.BTN_INTERACT if (sim.tick % 20) == 0 else 0
		else:
			_runner(sim, p, cmd, dt)
	else:
		_patrol(sim, p, cmd, dt)
	_maybe_boost(sim, p, cmd)
	cmd.quantize()
	return cmd


## (build 20) Runner bots use the running boost like players: to get away
## from a Night Watch closing in, and now and then on a long open run.
## (build 35) The Night Watch has no boost.  A runner bot boosts away only
## in some chases (chase_boost, drawn when the chase starts) and only once
## the Night Watch is close, so a human chaser isn't simply out-run.
func _maybe_boost(_sim: MatchSim, p: SimPlayer, cmd: InputCmd) -> void:
	if not p.is_runner() or p.state != TC.PState.ACTIVE or p.boost_t > 0.0 or p.boost_cd > 0.0 or cmd.move.length() < 0.8:
		return
	if threat_t > 0.0 and threat != Vector3.INF:
		if chase_boost and threat.distance_to(p.pos()) < BOOST_R:
			cmd.pressed |= TC.BTN_BOOST
	elif goal != Vector2.ZERO and p.pos2().distance_to(goal) > 40.0 and rng.randf() < 0.002:
		cmd.pressed |= TC.BTN_BOOST


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
	# (2.3) in a bush: stay while a Night Watch is near, then hop out
	if p.state == TC.PState.HIDING:
		cmd.move = Vector2.ZERO
		_hidden_t += dt
		var still_near := nearest_threat != Vector3.INF and nd < 16.0
		if _hidden_t > 3.0 and (not still_near or _hidden_t > 14.0):
			cmd.pressed |= TC.BTN_INTERACT
			_hidden_t = 0.0
		return
	_hidden_t = 0.0
	# (2.3) a Night Watch closing in that hasn't spotted us: duck into a bush
	# right beside us
	if p.state == TC.PState.ACTIVE and p.on_floor and nearest_threat != Vector3.INF and nd < 13.0 and nd > 5.0 \
			and p.spotted <= 0.0 and HideBushes.near(sim.layout, p.pos2()) >= 0 and p.gadget != TC.Gadget.TURBO:
		cmd.pressed |= TC.BTN_INTERACT
		return
	# (build 33) a touch easier to tag: a runner bot starts fleeing at 11 m
	# (was 12), and its escape dive comes a beat early (DIVE_R).  (build
	# 35) at FLEE_R, after a reaction delay; each chase drawn afresh
	var danger_r := FLEE_R if p.state == TC.PState.ACTIVE else 0.0
	if nearest_threat != Vector3.INF and nd < danger_r and p.protect <= 0.0:
		if threat_t <= 0.0:
			if notice_t < 0.0:
				# (right on top of us is noticed at once; further off, a beat late)
				var close := nd < 7.5
				notice_t = rng.randf_range(0.1, 0.2) if close else rng.randf_range(RUNNER_REACT.x, RUNNER_REACT.y)
				_new_chase()
				if close:
					freeze_t = 0.0
			notice_t -= dt
			if notice_t > 0.0:
				nearest_threat = Vector3.INF     # not noticed yet: carry on
		if nearest_threat != Vector3.INF:
			threat = nearest_threat
			threat_t = 2.5
	else:
		threat_t = maxf(0.0, threat_t - dt)
		if threat_t <= 0.0:
			notice_t = -1.0

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


## (build 35) How this runner bot will run the chase that is starting.
func _new_chase() -> void:
	chase_boost = rng.randf() < 0.35
	will_dive = rng.randf() < 0.5
	dive_r = rng.randf_range(1.8, 4.6)
	panic = rng.randf() < 0.25
	freeze_t = rng.randf_range(0.15, 0.3) if rng.randf() < 0.3 else 0.0
	flee_turn_t = 0.0


func _flee(sim: MatchSim, p: SimPlayer, cmd: InputCmd, dt: float) -> void:
	var cfg := sim.cfg
	var d := p.pos2().distance_to(Vector2(threat.x, threat.z))
	if freeze_t > 0.0:
		# a moment of panic before running
		freeze_t -= dt
		cmd.move = Vector2.ZERO
		replan_t = 0.0
		return
	flee_turn_t -= dt
	if flee_turn_t <= 0.0 or flee_dir == Vector2.ZERO:
		flee_turn_t = FLEE_TURN_S * rng.randf_range(0.8, 1.3)
		var away := p.pos2() - Vector2(threat.x, threat.z)
		if away.length() < 0.1:
			away = Vector2(1, 0)
		away = away.normalized()
		# keep making progress toward the goal if it is not toward the threat
		var to_goal := (goal - p.pos2()).normalized() if goal != Vector2.ZERO else away
		var dir := away
		if to_goal.dot(away) > -0.2:
			dir = (away * 0.6 + to_goal * 0.4).normalized()
		# avoid running into walls: probe a few angles on the nav grid (a
		# panicking runner just runs, dead ends and all)
		var best := dir
		if not panic:
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
		flee_dir = best
	cmd.move = flee_dir
	if p.gadget == TC.Gadget.TURBO and d < 8.0:
		cmd.pressed |= TC.BTN_GADGET
		cmd.cam_yaw = atan2(-flee_dir.x, -flee_dir.y)
	elif p.gadget == TC.Gadget.DECOY and d < 9.0:
		# (build 35) the duck flies at the Night Watch by itself
		cmd.pressed |= TC.BTN_GADGET
	elif p.gadget == TC.Gadget.SHIELD and d < 4.5:
		# (2.3) the pillow goes up as the Night Watch closes in
		cmd.pressed |= TC.BTN_GADGET
	elif p.gadget == TC.Gadget.SPLASH_BOMB:
		for c in sim.carts:
			if c.occupant >= 0 and c.pos().distance_to(p.pos()) < 12.0:
				var rel := c.pos() - p.pos()
				cmd.cam_yaw = atan2(-rel.x, -rel.z)
				cmd.move = Vector2.ZERO
				cmd.pressed |= TC.BTN_GADGET
	# dive to snatch distance when the patrol is about to lunge (build 35:
	# in some chases, at a distance that is often too early or too late)
	if will_dive and d < dive_r and jump_cool <= 0.0 and p.on_floor:
		cmd.pressed |= TC.BTN_JUMP
		jump_cool = 1.35
	elif will_dive and not p.on_floor and not p.diving and d < dive_r + 0.4 and p.vel.y < 1.5:
		cmd.pressed |= TC.BTN_JUMP
	_hop_obstacles(sim, p, cmd)
	replan_t = 0.0


# ---------------------------------------------------------------------------
# Patrol
# ---------------------------------------------------------------------------
## (build 35) The owner's playtest: "the AI cops are too good" and "they
## should only start running after you if they see you".  A Night Watch bot
## now knows only what it honestly perceives, and plays like a person who
## is a beat slow:
##   - sight: line of sight inside its view cone, out to WATCH_VIEW_M (less
##     than a person's 34 m); "heard" only right behind it (WATCH_HEAR_M);
##     runner footsteps further off only make it turn and look (within
##     WATCH_LISTEN_M), never send it after anyone;
##   - a runner it has just spotted gets a reaction delay before the chase
##     (and again on reacquiring one it lost);
##   - it aims at where the runner is (a little lead at most), hesitates at
##     corners, and gives up WATCH_GIVE_UP_S after losing sight (it runs to
##     the last place it saw them, no further);
##   - its Tag press comes at a "looks close" distance that varies (some
##     lunges fall short), after a short delay;
##   - it steers a cart more gently;
##   - a runner it saw dive into a bush is in that bush: it goes there,
##     searches for WATCH_SEARCH s and lunges; one it didn't see go in, it
##     walks past.
const WATCH_VIEW_M := 26.0
const WATCH_HEAR_M := 2.5
const WATCH_LISTEN_M := 7.0
const WATCH_GIVE_UP_S := 1.6
const WATCH_REACT := Vector2(0.45, 0.8)
const WATCH_REACQUIRE_S := 1.2
const WATCH_SEARCH := Vector2(0.6, 1.0)
const WATCH_LEAD_MAX_S := 0.6
const WATCH_STEER_GAIN := 1.1
const WATCH_STEER_RATE := 2.6       # steering change per second (carts)
## the tick each runner was last seen ({slot: tick}) and the bush a runner
## was seen vanishing into ({slot: [bush, tick]})
var seen_tick: Dictionary = {}
var saw_hide: Dictionary = {}
var chase_id := -1
var react_t := 0.0
var search_t := 0.0
var look_t := 0.0
var look_dir := Vector2.ZERO
var hesitate_t := 0.0
var press_d := 0.0
var _last_move := Vector2.ZERO
var _steer := 0.0


## Can this Night Watch bot see (or, right behind it, hear) runner r now?
func _watch_sees(sim: MatchSim, p: SimPlayer, r: SimPlayer, view_yaw: float) -> bool:
	var eye := p.pos() + Vector3(0, 1.4, 0)
	var rel := r.pos() - p.pos()
	var d := Vector2(rel.x, rel.z).length()
	if r.cloak_t > 0.0:
		return d < 2.0    # (build 17) cloaked: only bumped into
	if d > WATCH_VIEW_M:
		return false
	if d > WATCH_HEAR_M:
		var view := Vector2(-sin(view_yaw), -cos(view_yaw))
		if view.dot(Vector2(rel.x, rel.z) / d) < cos(deg_to_rad(sim.cfg.view_half_fov_deg)):
			return false
	return sim.los_to(eye, r)


func _patrol(sim: MatchSim, p: SimPlayer, cmd: InputCmd, dt: float) -> void:
	var cfg := sim.cfg
	var in_cart := p.state == TC.PState.IN_CART
	var view_yaw := sim.carts[p.cart_id].yaw if in_cart and p.cart_id >= 0 else p.yaw
	react_t = maxf(0.0, react_t - dt)
	look_t = maxf(0.0, look_t - dt)
	hesitate_t = maxf(0.0, hesitate_t - dt)
	# --- perceive runners (the same limits as a person, a bit shorter-sighted)
	var target: SimPlayer = null
	var td := 1e9
	var target_fresh := false
	for r in sim.players:
		# (a runner inside the home dorm can't be tagged: not a target)
		if not r.is_runner() or r.home_safe:
			continue
		if r.state == TC.PState.HIDING:
			# (build 35) seen up to a moment before they vanished, close
			# enough to see which bush: this Watch knows where they are
			if not saw_hide.has(r.id) and seen_tick.has(r.id) and sim.tick - int(seen_tick[r.id]) <= 30 \
					and r.bush >= 0 and r.pos().distance_to(p.pos()) <= WATCH_VIEW_M:
				saw_hide[r.id] = [r.bush, sim.tick]
			continue
		if not r.is_in_play():
			continue
		if not _watch_sees(sim, p, r, view_yaw):
			continue
		saw_hide.erase(r.id)
		var fresh := not seen_tick.has(r.id) or sim.tick - int(seen_tick[r.id]) > int(WATCH_REACQUIRE_S * cfg.sim_hz)
		seen_tick[r.id] = sim.tick
		last_seen[r.id] = {"pos": r.pos(), "vel": r.vel, "t": sim.tick}
		var d := r.pos().distance_to(p.pos())
		if r.protect > 0.0 or r.bump_protect > 0.0:
			d += 8.0
		if r.state == TC.PState.IN_CART and r.cart_id >= 0 and absf(sim.carts[r.cart_id].speed) > 3.0 and not in_cart:
			d += 20.0     # a runner driving off is no foot chase
		if d < td:
			td = d
			target = r
			target_fresh = fresh
	var cart_c: SimCart = sim.carts[p.cart_id] if in_cart else null
	if target != null:
		if target_fresh and target.id != chase_id:
			react_t = rng.randf_range(WATCH_REACT.x, WATCH_REACT.y) / skill
		chase_id = target.id
		if react_t > 0.0:
			# just spotted: a beat to take it in (turn toward them, slow down)
			if in_cart:
				_drive_to(sim, p, cart_c, target.pos2(), cmd, dt, false)
				cmd.drive = minf(cmd.drive, 0.3)
				return
			var rel0 := target.pos2() - p.pos2()
			cmd.move = rel0.normalized() * 0.2
			cmd.cam_yaw = atan2(-rel0.x, -rel0.y)
			return
		_chase(sim, p, cmd, dt, target, target.pos(), target.vel, td, in_cart, cart_c)
		return
	# --- a runner seen going into a bush: check that bush
	for rid in saw_hide.keys():
		var e: Array = saw_hide[rid]
		if sim.tick - int(e[1]) > int(15.0 * cfg.sim_hz):
			saw_hide.erase(rid)
	if not saw_hide.is_empty() and not in_cart:
		var rid2: int = saw_hide.keys()[0]
		var b: int = saw_hide[rid2][0]
		if _check_bush(sim, p, cmd, dt, rid2, b):
			return
	# --- lost sight: run to where they were last seen, then give up
	if chase_id >= 0 and last_seen.has(chase_id):
		var ls: Dictionary = last_seen[chase_id]
		var age := float(sim.tick - int(ls["t"])) / float(cfg.sim_hz)
		var lp: Vector3 = ls["pos"]
		if age < WATCH_GIVE_UP_S and p.pos().distance_to(lp) > 1.5:
			var r2 := sim.player(chase_id)
			if r2 != null and r2.is_in_play() and r2.state != TC.PState.HIDING:
				_chase(sim, p, cmd, dt, r2, lp, Vector3.ZERO, p.pos().distance_to(lp), in_cart, cart_c, false)
				return
		chase_id = -1
		search_t = 0.0
	# hearing (close footsteps: turn and look, nothing more) and the splash
	# markers (a water a runner just stamped, as on a person's map)
	var loudest := 0.0
	for n in sim.noises_for(p):
		var np: Vector3 = n["pos"]
		if np.distance_to(p.pos()) <= WATCH_LISTEN_M and float(n["loud"]) > loudest and String(n["kind"]) == "steps":
			loudest = float(n["loud"])
			look_dir = Vector2(np.x - p.pos().x, np.z - p.pos().z)
			if look_t <= 0.0:
				look_t = 1.0
	# a squeaking duck is loud: those not chasing anyone go and look
	for dc in sim.decoys:
		if float(dc["flight"]) <= 0.0 and (dc["pos"] as Vector3).distance_to(p.pos()) <= cfg.decoy_lure_m:
			investigate = dc["pos"]
			investigate_t = maxf(investigate_t, 3.0)
	for m in sim.splash_markers:
		var wc: Vector2 = sim.layout.waters[int(m["water"])]["center"]
		if investigate_t <= 0.0 or rng.randf() < 0.02:
			investigate = Vector3(wc.x, 0, wc.y)
			investigate_t = 10.0
	investigate_t = maxf(0.0, investigate_t - dt)
	if look_t > 0.0 and not in_cart and look_dir.length() > 0.1:
		cmd.move = look_dir.normalized() * 0.2
		cmd.cam_yaw = atan2(-look_dir.x, -look_dir.y)
		return

	# --- nobody in sight: investigate or patrol a route
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
	_corner_hesitation(cmd)
	_hop_obstacles(sim, p, cmd)
	cmd.cam_yaw = p.yaw + sin(float(sim.tick) * 0.03 + slot) * 0.9   # look around


## Run (or drive) at a runner: at `at` (where they are, or were last seen),
## with at most a little lead from `vel`; Tag when they look close.
func _chase(sim: MatchSim, p: SimPlayer, cmd: InputCmd, dt: float, target: SimPlayer, at: Vector3, vel: Vector3, td: float,
		in_cart: bool, cart_c: SimCart, can_tag: bool = true) -> void:
	var cfg := sim.cfg
	var lead := at + Vector3(vel.x, 0, vel.z) * clampf(td / 12.0, 0.0, WATCH_LEAD_MAX_S)
	if in_cart:
		var driving_off := target.state == TC.PState.IN_CART
		if (td < 10.0 and not driving_off) or (not nav.is_drivable(Vector2(lead.x, lead.z)) and td < 22.0):
			cmd.pressed |= TC.BTN_INTERACT   # hop out and chase on foot
			cmd.drive = -1.0
			return
		_drive_to(sim, p, cart_c, Vector2(lead.x, lead.z), cmd, dt, true)
		return
	# on foot: chase, tag when close, go back to a cart if they get away
	if td > 30.0 and _free_cart_near(sim, p, 18.0) >= 0:
		_go_to_cart(sim, p, cmd, dt)
		return
	var tp := Vector2(lead.x, lead.z)
	if path.is_empty() or replan_t <= 0.0 or goal.distance_to(tp) > 3.0:
		goal = tp
		goal_kind = "chase"
		replan_t = 0.6
		_repath(p.pos2(), goal, false)
	if td < 6.0 and sim.los_to(p.pos() + Vector3(0, 1.0, 0), target):
		var rel := at - p.pos()
		cmd.move = Vector2(rel.x, rel.z).normalized()
	else:
		_follow(sim, p, cmd, dt, false)
		_corner_hesitation(cmd)
	reaction -= dt
	if can_tag:
		# the press comes at a "looks close" distance that varies per try
		# (some lunges fall short), a moment after it looks right
		if press_d <= 0.0:
			press_d = cfg.tag_reach_m + rng.randf_range(-0.2, 1.3)
		if td < press_d and p.tag_cd <= 0.0 and p.tag_lockout <= 0.0:
			if reaction <= 0.0:
				cmd.pressed |= TC.BTN_TAG
				var rel2 := target.pos() - p.pos()
				cmd.cam_yaw = atan2(-rel2.x, -rel2.z) + rng.randf_range(-0.25, 0.25)
				reaction = rng.randf_range(0.2, 0.45) / skill
				press_d = 0.0
		elif reaction <= 0.0:
			reaction = rng.randf_range(0.1, 0.3) / skill
	_hop_obstacles(sim, p, cmd)


## (build 35) A runner this Watch saw dive into bush b: go there, search it
## for a moment, then lunge at it (and find them if they're still in).
## False once there's nothing more to do there.
func _check_bush(sim: MatchSim, p: SimPlayer, cmd: InputCmd, dt: float, rid: int, b: int) -> bool:
	if b < 0 or b >= sim.hide_bushes.size():
		saw_hide.erase(rid)
		return false
	var bp: Vector2 = sim.hide_bushes[b]
	var d := p.pos2().distance_to(bp)
	if d > 1.9:
		search_t = 0.0
		if goal.distance_to(bp) > 1.0 or path.is_empty() or replan_t <= 0.0:
			goal = bp
			goal_kind = "bush"
			replan_t = 1.0
			_repath(p.pos2(), goal, false)
		_follow(sim, p, cmd, dt, false)
		_hop_obstacles(sim, p, cmd)
		return true
	# at the bush: search it, then lunge into it
	if search_t <= 0.0:
		search_t = rng.randf_range(WATCH_SEARCH.x, WATCH_SEARCH.y)
	search_t -= dt
	var rel := bp - p.pos2()
	cmd.move = rel.normalized() * 0.15 if rel.length() > 0.8 else Vector2.ZERO
	cmd.cam_yaw = atan2(-rel.x, -rel.y)
	if search_t <= 0.0:
		var r := sim.player(rid)
		if r != null and r.state == TC.PState.HIDING and r.bush == b:
			# found them: lunge into the bush (again after a miss)
			if p.tag_cd <= 0.0 and p.tag_lockout <= 0.0 and p.tag_phase == SimPlayer.TagPhase.NONE:
				cmd.pressed |= TC.BTN_TAG
			search_t = 0.01
			return true
		saw_hide.erase(rid)      # gone (or caught): nothing in there now
		search_t = 0.0
		return false
	return true


## Slow down for a moment where the path turns a corner, as a person does.
func _corner_hesitation(cmd: InputCmd) -> void:
	if cmd.move.length() < 0.3:
		return
	var m := cmd.move.normalized()
	if _last_move != Vector2.ZERO and m.dot(_last_move) < 0.75 and hesitate_t <= 0.0:
		hesitate_t = rng.randf_range(0.2, 0.4)
	_last_move = m
	if hesitate_t > 0.0:
		cmd.move *= 0.55


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
	# (build 35) a gentler hand on the wheel: less gain, and the wheel
	# turns at a limited rate (it used to snap to full lock)
	_steer = move_toward(_steer, clampf(ang * WATCH_STEER_GAIN, -1.0, 1.0), WATCH_STEER_RATE * dt)
	cmd.steer = _steer
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
	var dw := pp.distance_to(wp)
	if wp != _wp_at or dw < _wp_best - 0.3:
		_wp_at = wp
		_wp_best = dw
		_wp_t = 0.0
	elif cmd.move.length() > 0.5:
		_wp_t += dt
		if _wp_t > WP_STALL_S:
			# step back and to one side, then re-path from there
			_wp_t = 0.0
			_wp_at = Vector2.INF
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			unstick_dir = (Vector2(-cmd.move.y, cmd.move.x) * side - cmd.move * 0.7).normalized()
			unstick_t = 0.6
			stuck_count = 0
			last_pos = p.pos()
			return
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
