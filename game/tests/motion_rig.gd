class_name MotionRig
extends Node3D
## Scripted gameplay -> presentation driver for motion measurements (V5).
## Used by tests/test_motion_v5.gd and src/dev/motion_probe.tscn (which also
## runs unchanged against the V4 code for before/after numbers).
##
## Pipeline, mirroring MatchController: a 60 Hz kinematic mini-motor (the
## RulesConfig speeds, accelerations, turn rate, gravity, jump, dive, tag,
## splash and cart timings) -> tick capture with the same discontinuity rule
## -> render-time lerp(prev, cur, fraction) -> CharacterView.apply_state ->
## CharacterView._process (engine-driven, after this node) -> skeleton
## modifiers.  After the last skeleton modifier of each frame the final pose
## is recorded in character space (including squash and stretch) together
## with the feet in world space.
##
## Frames are real engine frames: run the scene with --fixed-fps 60; the
## "hitch" and "jitter" scenarios change Engine.time_scale per frame to make
## long and irregular frames.  Nothing here is gameplay code.

signal finished

const TICK := 1.0 / 60.0
const JOINTS := ["hips", "chest", "head", "upper_arm.L", "upper_arm.R", "forearm.L", "forearm.R", "hand.L", "hand.R",
	"shin.L", "shin.R", "foot.L", "foot.R"]
## extra points: mitten tips and toes (bone origin + bone axis * length)
const TIPS := {"hand.L": 0.09, "hand.R": 0.09, "foot.L": 0.12, "foot.R": 0.12}
## indices of leg points in a frame's joint array (knees, ankles, toes)
const LEG_IDX := [9, 10, 11, 12, 15, 16]
## ankle height (above the ground) under which the lower foot counts as
## planted (the gait's stance ankle runs 0.085-0.107 m, its swing starts at 0.107)
const PLANT_H := 0.095

## scenario name -> length in seconds
const SCENARIOS := {
	"start": 1.6, "stop": 2.0, "walk_start_stop": 3.0, "reverse": 2.2, "turn90": 2.0, "speeds": 5.0,
	"jump_run": 2.2, "jump_idle": 2.0, "dive": 2.6, "kerb": 2.0, "flicker": 2.4, "tag_miss": 2.0, "tag_hit": 2.2,
	"splash": 3.4, "cart": 3.4, "emote": 3.6, "hitch": 3.0, "jitter": 3.0, "respawn": 3.0, "correction": 3.0,
	"lod": 6.0, "menu_idle": 24.0, "nw_run": 2.0, "sprint": 2.0, "ramp": 2.4,
}


class MiniMotor:
	extends RefCounted
	var cfg: RulesConfig
	var role := TC.Role.RUNNER
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var yaw := 0.0
	var on_floor := true
	var state := TC.PState.ACTIVE
	var state_t := 0.0
	var diving := false
	var dive_land := 0.0
	var sprinting := false
	var tag_phase := 0
	var tag_t := 0.0
	var air_t := 0.0
	var cart_id := -1
	var steer := 0.0
	var emote := -1
	var emote_t := 0.0
	var impact := 0
	var protect := 0.0
	var flicker := false     # report on_floor = false for this tick (slope crest / correction)
	var ledge_x := INF       # ground drops by ledge_h beyond x (kerb scenario)
	var ledge_h := 0.0
	var slope := 0.0         # V8 ramp scenario: the ground rises this much per metre forward (-z)

	func ground(p: Vector3) -> float:
		return (-ledge_h if p.x > ledge_x else 0.0) + slope * -p.z

	func facing() -> Vector3:
		return Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)

	func step(inp: Dictionary, dt: float) -> void:
		state_t += dt
		emote_t = maxf(0.0, emote_t - dt)
		protect = maxf(0.0, protect - dt)
		if inp.has("emote"):
			emote = int(inp["emote"])
			emote_t = 2.0
		if state != TC.PState.ACTIVE:
			return
		# tag timers (Motor.advance_timers)
		if tag_phase != 0:
			tag_t += dt
			if tag_phase == 1 and tag_t >= cfg.tag_anticipation_s:
				tag_phase = 2
				tag_t = 0.0
			elif tag_phase == 2 and tag_t >= cfg.tag_lunge_s:
				tag_phase = 3
				tag_t = -cfg.tag_hit_recover_s if bool(inp.get("hit", false)) else 0.0
			elif tag_phase == 3 and tag_t >= 0.2:
				tag_phase = 0
				tag_t = 0.0
		if bool(inp.get("tag", false)) and tag_phase == 0:
			tag_phase = 1
			tag_t = 0.0
		if on_floor:
			if diving:
				diving = false
				dive_land = cfg.dive_land_s
			air_t = 0.0
		else:
			air_t += dt
		dive_land = maxf(0.0, dive_land - dt)
		var control := 0.35 if dive_land > 0.0 else 1.0
		var move: Vector2 = inp.get("move", Vector2.ZERO)
		var mag := minf(move.length(), 1.0)
		sprinting = role == TC.Role.RUNNER and bool(inp.get("sprint", false)) and mag > 0.3
		var top := cfg.runner_speed if role == TC.Role.RUNNER else cfg.patrol_speed
		if sprinting:
			top = cfg.runner_sprint_speed
		var target := move.normalized() * top * mag * control if mag > 0.01 else Vector2.ZERO
		if tag_phase == 1:
			target *= cfg.tag_anticipation_move_scale
		var hv := Vector2(vel.x, vel.z)
		if tag_phase == 2:
			var f := facing()
			hv = Vector2(f.x, f.z) * cfg.tag_lunge_speed
		elif diving:
			pass
		else:
			var acc: float = (cfg.ground_accel if target.length() >= hv.length() * 0.9 else cfg.ground_decel) if on_floor else cfg.air_accel
			hv = hv.move_toward(target, acc * dt)
		if bool(inp.get("jump", false)):
			if on_floor:
				vel.y = cfg.jump_velocity if role == TC.Role.RUNNER else cfg.patrol_jump_velocity
				on_floor = false
			elif not diving and role == TC.Role.RUNNER:
				diving = true
				var f2 := facing()
				var dir := move.normalized() if mag > 0.2 else Vector2(f2.x, f2.z)
				hv = dir * maxf(hv.length(), cfg.dive_speed)
				vel.y = maxf(vel.y, cfg.dive_up_velocity)
		if not on_floor or vel.y > 0.0:
			vel.y = maxf(vel.y - cfg.gravity * dt, -cfg.max_fall_speed)
		if not (tag_phase == 2 or diving) and hv.length() > 0.6 and control > 0.0:
			yaw = rotate_toward(yaw, atan2(-hv.x, -hv.y), deg_to_rad(cfg.turn_rate_deg) * dt)
		pos += Vector3(hv.x, vel.y, hv.y) * dt
		vel = Vector3(hv.x, vel.y, hv.y)
		var g := ground(pos)
		if pos.y <= g + 0.001 and vel.y <= 0.0:
			pos.y = g
			vel.y = 0.0
			on_floor = true
		elif on_floor and vel.y <= 0.0 and pos.y - g < 0.35:
			pos.y = g     # floor snap (CharacterBody3D floor_snap_length)
		else:
			on_floor = false

	func rs() -> Dictionary:
		return {"pos": pos, "yaw": yaw, "vel": vel, "state": state, "state_t": state_t, "on_floor": on_floor and not flicker,
			"diving": diving, "sprinting": sprinting, "tag_phase": tag_phase, "protect": protect, "bump_protect": 0.0,
			"spotted": false, "cart_id": cart_id, "steer": steer, "emote": emote, "emote_t": emote_t, "visible": true,
			"impact": impact, "stamped": false}


var cfg: RulesConfig
var view: CharacterView
var cam: Camera3D
var m: MiniMotor
var scenario := ""
var length := 2.0
var local := true
var cosmetic: Dictionary = {}
var role := TC.Role.RUNNER
var lighting := "outdoor"
## per-frame records
var frames: Array = []
var running := false
var _sim_t := 0.0
var _acc := 0.0
var _ticks := 0
var _prev: Dictionary = {}
var _cur: Dictionary = {}
var _snap := false
var _frame := 0
var _bones: PackedInt32Array = []
var _tip_bones: Array = []
var _hat := -1
var _head := -1
var _recording_hooked := false
var _last_delta := 0.0
var _cam_dist := 5.0


func _init() -> void:
	process_priority = -100   # state first, then CharacterView animates


## Starts a scenario; await `finished`, then read metrics().
func start(p_scenario: String, p_cosmetic: Dictionary = {}, phase0: float = 0.0) -> void:
	cfg = Rules.cfg
	scenario = p_scenario
	length = float(SCENARIOS.get(scenario, 2.0))
	cosmetic = p_cosmetic if not p_cosmetic.is_empty() else Cosmetics.DEFAULT
	role = TC.Role.PATROL if scenario in ["tag_miss", "tag_hit", "cart", "nw_run"] else TC.Role.RUNNER
	local = scenario != "lod"
	lighting = "indoor" if scenario == "menu_idle" else "outdoor"
	m = MiniMotor.new()
	m.cfg = cfg
	m.role = role
	if scenario == "kerb":
		m.ledge_x = 3.0
		m.ledge_h = 0.45
	if scenario == "ramp":
		m.slope = 0.2
	cam = Camera3D.new()
	add_child(cam)
	cam.current = true
	view = CharacterView.new()
	view.lighting = lighting
	add_child(view)
	view.setup(role, cosmetic, 0, "probe", false, local)
	# deterministic: the gait phase and idle offset are random per instance
	view._phase = phase0
	view._idle_off = phase0 * 4.0
	if scenario == "menu_idle" and view.has_method("set_menu_idle"):
		view.call("set_menu_idle", true)
	_prev = m.rs()
	_cur = m.rs()
	view.apply_state(_cur, 0.0, true)
	_bones.clear()
	for b in JOINTS:
		_bones.append(view.skeleton.find_bone(b))
	_tip_bones.clear()
	for b in TIPS:
		_tip_bones.append([view.skeleton.find_bone(b), float(TIPS[b])])
	_hat = view.skeleton.find_bone("hat3")
	_head = view.skeleton.find_bone("head")
	_hook_recording()
	frames.clear()
	_sim_t = 0.0
	_acc = 0.0
	_ticks = 0
	_frame = 0
	Engine.time_scale = 1.0
	running = true


func _hook_recording() -> void:
	# the last active modifier's signal fires with the final pose in place
	var last: SkeletonModifier3D = null
	for c in view.skeleton.get_children():
		if c is SkeletonModifier3D and (c as SkeletonModifier3D).active:
			last = c
	if last != null:
		last.modification_processed.connect(_record)
		_recording_hooked = true


# ---------------------------------------------------------------- scenarios
func _scenario_input(t: float) -> Dictionary:
	var fwd := Vector2(0, -1)
	match scenario:
		"start":
			return {"move": fwd if t >= 0.5 else Vector2.ZERO}
		"stop":
			return {"move": fwd if t < 0.9 else Vector2.ZERO}
		"walk_start_stop":
			return {"move": fwd * 0.3 if (t >= 0.5 and t < 1.8) else Vector2.ZERO}
		"reverse":
			return {"move": fwd if t < 1.0 else -fwd}
		"turn90":
			return {"move": fwd if t < 0.9 else Vector2(1, 0)}
		"speeds":
			if t < 0.4:
				return {}
			if t < 1.6:
				return {"move": fwd * 0.3}
			if t < 2.8:
				return {"move": fwd}
			if t < 4.0:
				return {"move": fwd, "sprint": true}
			return {"move": fwd}
		"sprint":
			return {"move": fwd, "sprint": true}
		"nw_run", "ramp":
			return {"move": fwd}
		"jump_run":
			return {"move": fwd, "jump": _edge(t, 0.8)}
		"jump_idle":
			return {"jump": _edge(t, 0.6)}
		"dive":
			return {"move": fwd, "jump": _edge(t, 0.7) or _edge(t, 0.95)}
		"kerb":
			return {"move": Vector2(1, 0)}
		"flicker":
			m.flicker = t > 0.6 and fmod(t, 0.35) < TICK * 1.5
			return {"move": fwd}
		"tag_miss":
			return {"move": fwd, "tag": _edge(t, 0.7)}
		"tag_hit":
			return {"move": fwd if t < 0.75 else Vector2.ZERO, "tag": _edge(t, 0.7), "hit": true}
		"splash":
			_splash_script(t)
			return {"move": fwd if m.state == TC.PState.ACTIVE else Vector2.ZERO}
		"cart":
			_cart_script(t)
			return {"move": fwd * 0.4 if (t < 0.6 or t > 2.6) else Vector2.ZERO}
		"emote":
			var i := {}
			if _edge(t, 0.3) or _edge(t, 2.3):
				i["emote"] = 4
			if t > 1.4 and t < 2.0:
				i["move"] = fwd
			return i
		"hitch", "jitter", "correction":
			return {"move": fwd if t < 2.2 else Vector2(0.7, -0.7)}
		"respawn":
			_respawn_script(t)
			return {"move": fwd if m.state == TC.PState.ACTIVE else Vector2.ZERO}
		"lod":
			# a remote runner circling at 5 m/s while the camera backs away
			var a := t * 0.9
			return {"move": Vector2(cos(a), sin(a))}
		"menu_idle":
			return {}
	return {}


func _edge(t: float, at: float) -> bool:
	return t >= at and t < at + TICK * 0.999


func _splash_script(t: float) -> void:
	if m.state == TC.PState.ACTIVE and t >= 0.8 and t < 1.0:
		m.state = TC.PState.SPLASHING
		m.state_t = 0.0
		m.impact = TC.Impact.WALK
		m.vel = Vector3.ZERO
		m.pos.y = -0.3
		m.on_floor = false
	elif m.state == TC.PState.SPLASHING and m.state_t >= cfg.splash_sequence_s:
		# resurface at a shore exit 2.4 m to the side, hopping out (MatchSim._resurface)
		m.state = TC.PState.ACTIVE
		m.state_t = 0.0
		m.pos = Vector3(m.pos.x + 2.4, 0.1, m.pos.z)
		m.vel = Vector3(2.5, 3.5, 0)
		m.yaw = atan2(-1.0, 0.0)
		m.on_floor = false


func _cart_script(t: float) -> void:
	if m.state == TC.PState.ACTIVE and t >= 0.8 and t < 1.0:
		m.state = TC.PState.ENTERING
		m.state_t = 0.0
		m.cart_id = 0
		m.vel = Vector3.ZERO
		m.pos = m.pos + Vector3(-0.8, 0.75, 0.2)     # the seat (CartView.SEAT)
	elif m.state == TC.PState.ENTERING and m.state_t >= cfg.cart_enter_s:
		m.state = TC.PState.IN_CART
		m.state_t = 0.0
	elif m.state == TC.PState.IN_CART:
		m.vel = m.facing() * minf(6.0, m.state_t * 6.8)
		m.pos += m.vel * TICK
		m.steer = sin(m.state_t * 3.0) * 0.6
		if m.state_t >= 1.2:
			m.state = TC.PState.EXITING
			m.state_t = 0.0
			m.vel = Vector3.ZERO
			m.pos = m.pos + Basis(Vector3.UP, m.yaw) * Vector3(-1.3, -0.75, 0.0)
			m.cart_id = -1
	elif m.state == TC.PState.EXITING and m.state_t >= cfg.cart_exit_s:
		m.state = TC.PState.ACTIVE
		m.state_t = 0.0


func _respawn_script(t: float) -> void:
	if m.state == TC.PState.ACTIVE and t >= 0.7 and t < 0.9:
		m.state = TC.PState.CAPTURED
		m.state_t = 0.0
		m.vel = Vector3.ZERO
	elif m.state == TC.PState.CAPTURED and m.state_t >= 1.4:
		m.state = TC.PState.ACTIVE
		m.state_t = 0.0
		m.pos += Vector3(30, 0, 0)
		m.protect = cfg.respawn_protect_s


# ---------------------------------------------------------------- frames
func _process(delta: float) -> void:
	if not running:
		return
	_last_delta = delta
	_acc += delta
	while _acc >= TICK:
		_acc -= TICK
		var inp := _scenario_input(_sim_t)
		m.step(inp, TICK)
		if scenario == "correction" and _ticks % 3 == 0 and _sim_t > 0.5:
			# a reconcile replays inputs and lands on a slightly different velocity
			m.vel += Vector3(sin(_ticks * 1.7), 0, cos(_ticks * 2.3)) * 1.2
		_sim_t += TICK
		_ticks += 1
		_capture_tick()
	var f := clampf(_acc / TICK, 0.0, 1.0)
	var rs := _cur.duplicate()
	rs["pos"] = (_prev["pos"] as Vector3).lerp(_cur["pos"], f)
	rs["yaw"] = lerp_angle(float(_prev["yaw"]), float(_cur["yaw"]), f)
	view.apply_state(rs, delta, _snap)
	_snap = false
	_place_camera(rs["pos"])
	# render-rate patterns for the next frame
	Engine.time_scale = 1.0
	if scenario == "hitch" and _frame == 70:
		Engine.time_scale = 15.0          # one 250 ms frame
	elif scenario == "jitter" and _frame > 30:
		Engine.time_scale = [0.5, 1.6, 0.7, 1.2, 0.45, 2.1][_frame % 6]
	_frame += 1
	if _sim_t >= length:
		running = false
		Engine.time_scale = 1.0
		finished.emit.call_deferred()


func _capture_tick() -> void:
	var rs := m.rs()
	var jump := false
	var ps: int = _cur.get("state", 0)
	var cs: int = rs.get("state", 0)
	var tele := [TC.PState.CAPTURED, TC.PState.SPLASHING, TC.PState.ENTERING, TC.PState.EXITING]
	if (_cur["pos"] as Vector3).distance_to(rs["pos"]) > 2.5:
		jump = true
	elif ps != cs and (ps in tele or cs in tele):
		jump = true
	_prev = rs if jump else _cur
	_cur = rs
	if jump:
		_snap = true


func _place_camera(p: Vector3) -> void:
	if scenario == "lod":
		# 30 m -> 70 m -> 30 m from the runner
		var u := _sim_t / length
		_cam_dist = 30.0 + 40.0 * sin(PI * u)
		cam.global_position = p + Vector3(0, 3.0, _cam_dist)
	elif scenario == "menu_idle":
		cam.global_position = Vector3(0, 1.3, 3.0)
	else:
		cam.global_position = p + Vector3(0, 2.2, 5.0)


func _record() -> void:
	if not running and frames.size() > 0 and float(frames[-1]["t"]) >= length:
		return
	var sk := view.skeleton
	# character space: skeleton pose under the model's squash/stretch scale
	var ms := view.global_transform.affine_inverse() * sk.global_transform
	var j := PackedVector3Array()
	for b in _bones:
		j.append(ms * sk.get_bone_global_pose(b).origin)
	for tb in _tip_bones:
		var g := sk.get_bone_global_pose(int(tb[0]))
		j.append(ms * (g.origin + g.basis.y.normalized() * float(tb[1])))
	var xf := sk.global_transform
	var feet := PackedVector3Array()
	for k in [_bones[11], _bones[12]]:
		feet.append(xf * sk.get_bone_global_pose(k).origin)
	var tip := Vector3.ZERO
	if _hat >= 0 and _head >= 0:
		var hg := sk.get_bone_global_pose(_hat)
		var head_g := sk.get_bone_global_pose(_head)
		tip = head_g.affine_inverse() * (hg.origin + hg.basis.y.normalized() * 0.14)
	var lag := Vector2.ZERO
	if view.secondary:
		lag = view.secondary.get("_lag")
	var tele := not frames.is_empty() and (frames[-1]["root"] as Vector3).distance_to(view.global_position) > 0.5 \
		and int(frames[-1]["state"]) != int(view.rs.get("state", 0))
	frames.append({"t": _sim_t, "dt": _last_delta, "mode": view._mode, "j": j, "feet": feet, "tele": tele,
		"ground": m.ground(view.global_position) if m else 0.0, "root": view.global_position, "lag": lag, "tip": tip,
		"state": int(view.rs.get("state", 0)), "anim": view.anim_time_advanced, "cam": _cam_dist})


# ---------------------------------------------------------------- metrics
## pop_cm: the largest third difference of an upper-body joint (hips, chest,
##   head, shoulders, elbows, wrists, mitten tips) over four consecutive
##   equal-length frames (cm).  Smooth motion stays near zero (a steady 60 fps
##   sprint peaks at ~3 cm at the mitten tips); a pose that snaps by X cm in
##   one frame scores 2X, and a sudden change of joint velocity v scores v*dt.
## leg_pop_cm: the same for knees, ankles and toes.  Toe-off and foot strike
##   are sharp by nature (~16 cm in a steady sprint), so legs are judged by
##   the planted-foot slide instead.
## step_cm: the largest single-frame joint displacement.
## slide: horizontal speed of the planted (lower) foot in ground locomotion
##   (m/s), mean and 95th percentile.
## lag_*: the head spring's lag (rad) and its largest change in one frame.
## hat_*: the nightcap tip in head space: largest one-frame move and range.
func metrics() -> Dictionary:
	var pop := 0.0
	var pop_at := -1.0
	var pop_j := -1
	var leg_pop := 0.0
	var step := 0.0
	var pops_over := 0
	var slides: Array[float] = []
	var lag_max := 0.0
	var lag_step := 0.0
	var tip_step := 0.0
	var tip_max := 0.0
	var names := JOINTS.duplicate()
	names.append_array(TIPS.keys().map(func(k: String) -> String: return k + "_tip"))
	var tip0: Vector3 = frames[0]["tip"] if not frames.is_empty() else Vector3.ZERO
	for i in range(1, frames.size()):
		var a: Dictionary = frames[i - 1]
		var b: Dictionary = frames[i]
		var ja: PackedVector3Array = a["j"]
		var jb: PackedVector3Array = b["j"]
		for k in jb.size():
			step = maxf(step, ja[k].distance_to(jb[k]) * 100.0)
		if i >= 3:
			var z: Dictionary = frames[i - 2]
			var y: Dictionary = frames[i - 3]
			var even := true
			for q in [a, z, y]:
				if absf(float(b["dt"]) - float(q["dt"])) > 1e-4:
					even = false
			# a teleport (respawn, resurfacing, cart seat in/out) cuts the pose
			# on purpose, together with the position: not a pop
			for q in [b, a, z]:
				if bool(q.get("tele", false)):
					even = false
			if even:
				var jz: PackedVector3Array = z["j"]
				var jy: PackedVector3Array = y["j"]
				var worst := 0.0
				var wk := -1
				for k in jb.size():
					var d := (jb[k] - 3.0 * ja[k] + 3.0 * jz[k] - jy[k]).length() * 100.0
					if k in LEG_IDX:
						leg_pop = maxf(leg_pop, d)
					elif d > worst:
						worst = d
						wk = k
				if worst > 3.0:
					pops_over += 1
				if worst > pop:
					pop = worst
					pop_at = float(b["t"])
					pop_j = wk
		# planted-foot slide (ground locomotion only, the lower foot)
		if String(b["mode"]) == "ground" and int(b["state"]) == TC.PState.ACTIVE and float(b["dt"]) > 0.0:
			var fa: PackedVector3Array = a["feet"]
			var fb: PackedVector3Array = b["feet"]
			var k2 := 0 if fb[0].y <= fb[1].y else 1
			var ga := float(a["ground"])
			var gb := float(b["ground"])
			if fa[k2].y - ga < PLANT_H and fb[k2].y - gb < PLANT_H:
				var d2 := Vector2(fb[k2].x - fa[k2].x, fb[k2].z - fa[k2].z).length()
				slides.append(d2 / float(b["dt"]))
		var la: Vector2 = a["lag"]
		var lb: Vector2 = b["lag"]
		lag_max = maxf(lag_max, lb.length())
		# springs restart at a teleport by design (with the pose cut)
		if not bool(b.get("tele", false)):
			lag_step = maxf(lag_step, la.distance_to(lb))
			tip_step = maxf(tip_step, (a["tip"] as Vector3).distance_to(b["tip"]) * 100.0)
		tip_max = maxf(tip_max, (b["tip"] as Vector3).distance_to(tip0) * 100.0)
	slides.sort()
	var mean := 0.0
	for s in slides:
		mean += s
	mean = mean / slides.size() if not slides.is_empty() else 0.0
	return {
		"scenario": scenario, "frames": frames.size(),
		"pop_cm": snappedf(pop, 0.01), "pop_t": snappedf(pop_at, 0.001), "pop_joint": names[pop_j] if pop_j >= 0 else "",
		"pops_over_3cm": pops_over, "step_cm": snappedf(step, 0.01), "leg_pop_cm": snappedf(leg_pop, 0.01),
		"slide_mean": snappedf(mean, 0.001), "slide_p95": snappedf(slides[int(slides.size() * 0.95)] if not slides.is_empty() else 0.0, 0.001),
		"planted_frames": slides.size(),
		"lag_max": snappedf(lag_max, 0.001), "lag_step": snappedf(lag_step, 0.0001),
		"hat_tip_step_cm": snappedf(tip_step, 0.01), "hat_tip_range_cm": snappedf(tip_max, 0.01),
	}


## Animation updates seen per camera-distance band (LOD scenario): how many
## frames in the band changed the pose's animation time.
func lod_bands() -> Dictionary:
	var out := {}
	for i in range(1, frames.size()):
		var d := float(frames[i]["cam"])
		var band := "near<40" if d < 40.0 else ("mid40-50" if d < 50.0 else "far>50")
		var e: Array = out.get(band, [0, 0])
		e[0] += 1
		if float(frames[i]["anim"]) != float(frames[i - 1]["anim"]):
			e[1] += 1
		out[band] = e
	return out


func cleanup() -> void:
	Engine.time_scale = 1.0
	if view:
		view.queue_free()
	if cam:
		cam.queue_free()
