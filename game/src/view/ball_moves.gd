class_name BallMoves
extends RefCounted
## (build 30) The basketball's choreography for one holder, as pure math
## (HubBallView draws it; BallRig poses the body): the dribble, the dribble
## moves that hand the ball from hand to hand, the shooting form, the pass.
##
## Space: the holder's own frame, metres: x right, y up from the floor, z
## BACK (the skeleton's space: forward is -z).  Every pose is a dictionary:
##   ball      the ball's centre
##   arms      [left, right]: {key (a pose family: a change of family
##             blends over ARM_BLEND_S, the same family never lags), w,
##             contact (the palm is on the ball), wrist, basis (the hand
##             bone), elbow (a point the elbow points toward), shrug, reach}
##   crouch, rise, lean, turn, look_up, stance_w, stance ([left, right]
##             ankles)
##
## The moves are derived on every device from what everyone sees, the
## holder's drawn heading and speed (no new network data): a moderate turn
## crosses the ball over in front, a sharp turn (or a stop or a start) puts
## it between the legs, a reversal goes behind the back.  Each move hands
## the ball to the other hand.  Paths are laid out around the body (the
## between-the-legs stance is wide enough for the ball), and every frame
## the palm is on the ball while it is in a hand.

# --- the dribble
const X := 0.38              # beside the hand (the runner's hand hangs at 0.376)
const X_WALK := 0.07         # and further out walking (the knees come up)
const FWD := 0.1             # ahead of the hips standing ...
const FWD_WALK := 0.1        # ... and this much more at full walking speed
const TOP := 0.47            # the ball's centre in the hand at the top
const PUSH := 0.2            # the palm is on it this part of a bounce either side of the top
const SLOW_S := 0.5          # a bounce standing
const FAST_S := 0.38         # and at full walking speed
const CROUCH := 0.05         # knees bent
const LEAN := 0.13           # and a slight forward lean (rad)
# --- the moves
const MOVE_S := {"cross": 0.58, "legs": 0.76, "back": 0.68}
const MOVE_COOL := 0.18
## a stronger move asked for before the last one started replaces it
const RANK := ["cross", "legs", "back"]
## heading change (rad) over TURN_WINDOW for each move (while moving)
const TURN_MIN := 0.55       # ~32 degrees: a crossover
const TURN_SHARP := 1.25     # ~72 degrees: between the legs
const TURN_REVERSE := 2.3    # ~132 degrees: behind the back
const TURN_WINDOW := 0.45
## the turn has to have settled (rad/s) before the move (it runs in the new heading)
const SETTLED := 2.5
## stop / start (fractions of walking speed)
const STOP_FROM := 0.55
const STOP_TO := 0.12
const START_FROM := 0.1
const START_TO := 0.45
# --- hands
## the middle of the palm's surface in hand-bone space (left, right): the
## mitten's palm faces local +x on the left hand, -x on the right
const PALM := [Vector3(0.034, 0.062, 0.008), Vector3(-0.038, 0.062, 0.008)]
const PALM_GAP := 0.004
## the hand bone's origin is at most this far from the upper arm's (arm 0.32 m)
const REACH := 0.305
const ARM_BLEND_S := 0.16
# --- the shot (a ~1 m runner with a big head: the set point is in front of
# the chin, the release up and forward in front of the face)
const POCKET := Vector3(0.02, 0.75, -0.355)      # the gather, at the chest
const SET := Vector3(0.07, 0.9, -0.365)          # the set point (body-relative)
const REL := Vector3(0.07, 0.99, -0.41)          # the release (body-relative)
const REL_RISE := 0.09                           # the jump at the release
const T_GATHER := 0.38
const T_DIP := 0.55
const T_RISE := 0.83
const PASS_AT := Vector3(0.0, 0.75, -0.4)

# state
var side := 1                # +1 right hand, -1 left
var u := 0.0                 # the bounce: 0 the top (in the hand), 0.5 the floor
var k := 0.0                 # walking speed / full
var move := ""
var mt := 0.0                # the move's time (0..1)
var _mv := {}                # the move's path (built when it starts)
var _pending := ""
var _cool := 0.0
var _off := Vector3.INF      # the dribble's place (eased)
var _hist: Array = []        # [t, yaw, speed]
var _t := 0.0
var _yaw_was := NAN
var _yaw_rate := 0.0
var _sp := 0.0
var bounced := false         # (this step) the ball hit the floor
var moves_done: Array = []   # (tests) [kind, from side, to side]


func reset(from_floor: bool) -> void:
	u = 0.5 if from_floor else 0.0
	move = ""
	_mv = {}
	_pending = ""
	_cool = 0.3
	_off = Vector3.INF
	_hist.clear()
	_yaw_was = NAN


static func ease5(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)


static func ease3(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


static func bez(a: Vector3, c: Vector3, b: Vector3, t: float) -> Vector3:
	var m := 1.0 - t
	return a * (m * m) + c * (2.0 * m * t) + b * (t * t)


## The hand bone's orientation (holder space) for a palm facing `palm_dir`
## with the fingers along `fingers` (side 0 left, 1 right).
static func hand_basis(i: int, palm_dir: Vector3, fingers: Vector3) -> Basis:
	var x := (-palm_dir if i == 1 else palm_dir).normalized()
	var y := fingers - x * fingers.dot(x)
	if y.length() < 1e-4:
		y = Vector3.UP - x * x.y
	y = y.normalized()
	return Basis(x, y, x.cross(y))


## A hand with its palm on the ball (centre `c`) on the side `n` (outward
## from the ball's centre): [wrist, basis].
static func on_ball(i: int, c: Vector3, n: Vector3, fingers: Vector3) -> Array:
	var nn := n.normalized()
	var b := hand_basis(i, -nn, fingers)
	var contact := c + nn * (HubBall.R + PALM_GAP)
	return [contact - b * (PALM[i] as Vector3), b]


static func arm(key: String, w: float, contact: bool, wb: Array, elbow: Vector3, shrug: float = 0.0, reach: float = 0.0) -> Dictionary:
	return {"key": key, "w": w, "contact": contact, "wrist": wb[0], "basis": wb[1], "elbow": elbow, "shrug": shrug, "reach": reach}


static func relaxed() -> Dictionary:
	return {"key": "relax", "w": 0.0, "contact": false, "wrist": Vector3.ZERO, "basis": Basis(), "elbow": Vector3.ZERO, "shrug": 0.0, "reach": 0.0}


## i: 0 left, 1 right; s: -1 left, +1 right
static func idx(s: int) -> int:
	return 1 if s > 0 else 0


# ---------------------------------------------------------------------------
# Moves from the heading
# ---------------------------------------------------------------------------
## Feeds the holder's drawn heading and ground speed (m/s); returns the move
## this calls for ("" none).
func detect(dt: float, yaw: float, speed: float) -> String:
	_t += dt
	_cool = maxf(0.0, _cool - dt)
	if is_nan(_yaw_was):
		_yaw_was = yaw
	var yr := angle_difference(_yaw_was, yaw) / maxf(dt, 0.001)
	_yaw_was = yaw
	_yaw_rate = lerpf(_yaw_rate, yr, 1.0 - exp(-dt * 30.0))
	_sp = lerpf(_sp, speed, 1.0 - exp(-dt * 14.0))
	var kk := _sp / HubRoom.WALK_SPEED
	_hist.append([_t, yaw, kk])
	while _hist.size() > 2 and _t - float(_hist[0][0]) > TURN_WINDOW:
		_hist.pop_front()
	# (a move asked for while one is running follows it)
	if _cool > 0.0:
		return ""
	# the heading change while moving (turning on the spot is no move), the
	# most against any heading in the window (a reversal can come back past
	# where it started)
	var turn := 0.0
	var fastest := 0.0
	var slowest := INF
	for h in _hist:
		if float(h[2]) > 0.3:
			turn = maxf(turn, absf(angle_difference(float(h[1]), yaw)))
		fastest = maxf(fastest, float(h[2]))
		slowest = minf(slowest, float(h[2]))
	if kk <= 0.3:
		turn = 0.0
	var kind := ""
	if fastest > 0.3 and turn >= TURN_MIN and absf(_yaw_rate) < SETTLED:
		kind = "back" if turn >= TURN_REVERSE else ("legs" if turn >= TURN_SHARP else "cross")
	elif fastest > STOP_FROM and kk < STOP_TO and float(_hist[0][2]) > STOP_FROM:
		kind = "legs"     # a stop
	elif slowest < START_FROM and kk > START_TO and float(_hist[0][2]) < START_FROM:
		kind = "legs"     # a start
	if kind != "":
		_hist = [[_t, yaw, kk]]
	return kind


## The windup of a shot or a pass ends any move (the hands take the ball
## where it is).
func cancel() -> void:
	move = ""
	_mv = {}
	_pending = ""


## (tests, captures) start a move at the next chance
func request(kind: String) -> void:
	_pending = kind


# ---------------------------------------------------------------------------
# The dribble and the moves
# ---------------------------------------------------------------------------
func _base(s: int) -> Vector3:
	return Vector3(float(s) * (X + X_WALK * k), 0.0, -(FWD + FWD_WALK * k))


## A step of the dribble: `kk` walking speed / full, `want` a move to start
## ("" none).  Returns the pose.
func dribble(dt: float, kk: float, want: String) -> Dictionary:
	k = kk
	bounced = false
	if want != "" and (_pending == "" or RANK.find(want) > RANK.find(_pending)):
		_pending = want
	var base := _base(side)
	if _off == Vector3.INF:
		_off = base
	_off = _off.lerp(base, 1.0 - exp(-dt * 7.0))
	if move == "":
		var period := lerpf(SLOW_S, FAST_S, k)
		var u_was := u
		u = fmod(u + dt / period, 1.0)
		if u_was < 0.5 and u >= 0.5:
			bounced = true
		# a move starts with the ball in the hand
		var in_hand := u <= PUSH * 0.5 or u >= 1.0 - PUSH
		if _pending != "" and in_hand:
			_start(_pending)
			_pending = ""
	if move != "":
		mt += dt / float(MOVE_S[move])
		if mt >= 1.0:
			_finish()
		else:
			return _move_pose()
	return _dribble_pose()


## The palm on the top of the ball, a little to the outside and toward the
## back (more as it moves on: it pushes the ball ahead).
func top_n(s: int) -> Vector3:
	return (Vector3.UP + Vector3(float(s) * 0.12, 0, 0.12 + 0.25 * k)).normalized()


func _dribble_pose() -> Dictionary:
	var s := side
	var i := idx(s)
	var o := 1 - i
	var c := Vector3(_off.x, HubBall.R + (TOP - HubBall.R) * absf(cos(PI * u)), _off.z)
	var n := top_n(s)
	# the wrist: up a little as the ball comes into the hand, flexed (the
	# fingers pointing down) as it pushes, back for the next one
	var flex: float
	var contact := u <= PUSH or u >= 1.0 - PUSH
	var hc := c
	if u <= PUSH:
		flex = lerpf(0.15, -0.62, ease3(u / PUSH))
	elif u >= 1.0 - PUSH:
		flex = lerpf(-0.3, 0.15, ease3((u - (1.0 - PUSH)) / PUSH))
	else:
		# the ball's away: the hand waits over where it will be, dipping
		# a little after the push and rising to meet it
		var a := (u - PUSH) / (1.0 - 2.0 * PUSH)
		flex = lerpf(-0.62, -0.3, ease3(a))
		hc = Vector3(c.x, HubBall.R + (TOP - HubBall.R) * cos(PI * PUSH) - 0.03 * sin(PI * a), c.z)
	var fingers := Vector3(0.22 * float(s), sin(flex), -cos(flex))
	var hand := arm("ball", 1.0, contact, on_ball(i, hc, n, fingers), Vector3(float(s) * 0.6, 0.75, 0.35))
	var arms := [relaxed(), relaxed()]
	arms[i] = hand
	arms[o] = _guard(o, 1.0 - k)
	return {"ball": c, "arms": arms, "crouch": CROUCH + 0.02 * k, "rise": 0.0, "lean": LEAN + 0.05 * k, "turn": 0.0,
		"look_up": 0.0, "stance_w": 0.0, "stance": [Vector3.ZERO, Vector3.ZERO]}


## The off hand standing: the forearm up in front, guarding the ball.
func _guard(i: int, w: float) -> Dictionary:
	var s := 1.0 if i == 1 else -1.0
	var wb := [Vector3(s * 0.2, 0.62, -0.25), hand_basis(i, Vector3(s * 0.3, 0.0, -1.0), Vector3(-s * 0.35, 0.75, -0.3))]
	return arm("guard", w, false, wb, Vector3(s * 0.7, 0.4, 0.1))


func _start(kind: String) -> void:
	move = kind
	mt = 0.0
	var s := float(side)
	var o := -s
	var f := FWD + FWD_WALK * k
	var p0 := Vector3(_off.x, HubBall.R + (TOP - HubBall.R) * absf(cos(PI * u)), _off.z)
	match kind:
		"cross":
			# pushed down and across in front of the knees, a bounce in the
			# middle, up into the other hand
			_mv = {"segs": [
				["hand", 0.0, 0.22, p0, Vector3(s * 0.36, 0.43, -0.2), Vector3(s * 0.33, 0.39, -0.27)],
				["fall", 0.22, 0.5, Vector3(s * 0.33, 0.39, -0.27), Vector3(s * 0.26, 0, -0.47), Vector3(0.0, HubBall.R, -0.43)],
				["rise", 0.5, 0.82, Vector3(0.0, HubBall.R, -0.43), Vector3(o * 0.26, 0, -0.47), Vector3(o * 0.33, 0.39, -0.27)],
				["catch", 0.82, 1.0, Vector3(o * 0.33, 0.39, -0.27), Vector3(o * 0.36, 0.44, -(f + 0.08)), Vector3(o * X, TOP, -f)]],
				"crouch": 0.08, "lean": 0.22, "stance_w": 0.0}
		"legs":
			# a wide stance; the hand brings the ball in front, bounces it
			# back under the hips and the other hand takes it behind the hip
			_mv = {"segs": [
				["hand", 0.0, 0.34, p0, Vector3(s * 0.36, 0.44, -0.42), Vector3(s * 0.1, 0.33, -0.36)],
				# (down in front first, then back under the hips)
				["fall", 0.34, 0.54, Vector3(s * 0.1, 0.33, -0.36), Vector3(s * 0.02, 0, -0.34), Vector3(0.0, HubBall.R, 0.0), 1.8],
				# (back behind the hips low, then out and up to the other hand)
				["rise", 0.54, 0.82, Vector3(0.0, HubBall.R, 0.0), Vector3(o * 0.06, 0, 0.44), Vector3(o * 0.42, 0.37, 0.12), 0.7],
				["catch", 0.82, 1.0, Vector3(o * 0.42, 0.37, 0.12), Vector3(o * 0.43, 0.43, 0.06), Vector3(o * (X + 0.02), TOP - 0.02, 0.0)]],
				"crouch": 0.16, "lean": 0.3, "stance_w": 1.0,
				"stance": [Vector3(-0.44, 0.085, -0.02), Vector3(0.44, 0.085, -0.02)]}
		"back":
			# the hand swings it back and up beside the hip, lets it go
			# behind the back, a bounce behind the other foot, up into the
			# other hand at its side
			_mv = {"segs": [
				["hand", 0.0, 0.3, p0, Vector3(s * 0.4, 0.5, 0.0), Vector3(s * 0.38, 0.5, 0.15)],
				["fall", 0.3, 0.62, Vector3(s * 0.38, 0.5, 0.15), Vector3(0.0, 0, 0.58), Vector3(o * 0.38, HubBall.R, 0.3)],
				["rise", 0.62, 0.85, Vector3(o * 0.38, HubBall.R, 0.3), Vector3(o * 0.46, 0, 0.12), Vector3(o * 0.38, 0.37, -0.02)],
				["catch", 0.85, 1.0, Vector3(o * 0.37, 0.37, -0.02), Vector3(o * X, 0.43, -f * 0.5), Vector3(o * X, TOP, -f)]],
				"crouch": 0.08, "lean": 0.1, "stance_w": 0.0}
	_mv["from"] = side


func _finish() -> void:
	moves_done.append([move, side, -side])
	var segs: Array = _mv["segs"]
	var last: Array = segs[segs.size() - 1]
	side = -side
	_off = Vector3((last[5] as Vector3).x, 0.0, (last[5] as Vector3).z)
	u = 0.0
	move = ""
	_mv = {}
	_cool = MOVE_COOL


## Where the move has the ball at `t` (0..1) and which segment.
func move_ball(t: float) -> Array:
	for sg in _mv["segs"]:
		var t0 := float(sg[1])
		var t1 := float(sg[2])
		if t > t1 and t < 1.0:
			continue
		var x := clampf((t - t0) / (t1 - t0), 0.0, 1.0)
		var a: Vector3 = sg[3]
		var c: Vector3 = sg[4]
		var b: Vector3 = sg[5]
		match String(sg[0]):
			"hand", "catch":
				var e := ease3(x) if String(sg[0]) == "hand" else 1.0 - pow(1.0 - x, 1.6)
				var hp := bez(a, Vector3(c.x, c.y, c.z), b, e)
				return [hp, sg, x]
			"fall":
				# (sg[6]: >1 the ball drops before it travels)
				var hp := float(sg[6]) if sg.size() > 6 else 1.0
				var hz := bez(a, c, b, pow(x, hp) * 0.85 + 0.15 * ease3(x))
				var y := a.y + (b.y - a.y) * (0.45 * x + 0.55 * x * x)
				return [Vector3(hz.x, y, hz.z), sg, x]
			"rise":
				# (sg[6]: <1 the ball travels low before it rises)
				var rp := float(sg[6]) if sg.size() > 6 else 1.0
				var hz2 := bez(a, c, b, 1.0 - pow(1.0 - x, 1.0 / rp) if rp < 1.0 else x)
				var y2 := a.y + (b.y - a.y) * (1.0 - pow(1.0 - x, 1.5)) * (pow(x, 0.6) if rp < 1.0 else 1.0)
				return [Vector3(hz2.x, y2, hz2.z), sg, x]
	var segs: Array = _mv["segs"]
	return [segs[segs.size() - 1][5], segs[segs.size() - 1], 1.0]


func _move_pose() -> Dictionary:
	var r := move_ball(mt)
	var c: Vector3 = r[0]
	var sg: Array = r[1]
	var x := float(r[2])
	var s := int(_mv["from"])
	var o := -s
	var i_from := idx(s)
	var i_to := idx(o)
	var kind := String(sg[0])
	var arms := [relaxed(), relaxed()]
	# the body: into the move's crouch and lean and back out
	var e_in := ease3(mt / (0.17 if move == "legs" else 0.3))
	var e_out := 1.0 - ease3((mt - 0.78) / 0.22)
	var bw := minf(e_in, e_out)
	var crouch := lerpf(CROUCH + 0.02 * k, float(_mv["crouch"]), bw)
	var lean := lerpf(LEAN + 0.05 * k, float(_mv["lean"]), bw)
	var sw := float(_mv["stance_w"]) * bw
	# the hand that has it: on top and toward the outside, pushing it the way
	# it goes (the palm on the far side from where it is going)
	var segs: Array = _mv["segs"]
	var push_seg: Array = segs[0]
	var push_end: Vector3 = push_seg[5]
	var fall_end: Vector3 = (segs[1] as Array)[5]
	var push_dir := (fall_end - push_end).normalized()
	var n_push := (Vector3.UP * 1.0 - push_dir * 0.55 + Vector3(float(s) * 0.15, 0, 0)).normalized()
	var n_top := top_n(s)
	if kind == "hand":
		var nn := n_top.slerp(n_push, ease3(x))
		var fl := Vector3(0.22 * float(s), lerpf(0.1, -0.6, ease3(x)), -1.0)
		if move == "back":
			fl = Vector3(0.0, lerpf(0.1, -0.7, ease3(x)), lerpf(-1.0, 0.2, ease3(x)))
		arms[i_from] = arm("ball", 1.0, true, on_ball(i_from, c, nn, fl), Vector3(float(s) * 0.6, 0.75, 0.35 + (0.3 if move == "back" else 0.0)))
	else:
		# released: the hand follows through a moment where it let go,
		# then guards
		var tr := float(push_seg[2])
		var since := (mt - tr) * float(MOVE_S[move])
		var hold := on_ball(i_from, push_end + Vector3(0, 0.05, 0), n_push, Vector3(0.22 * float(s), -0.7, -0.7))
		var g := _guard(i_from, 1.0 - k)
		if since < 0.12:
			arms[i_from] = arm("ball", 1.0, false, hold, Vector3(float(s) * 0.6, 0.75, 0.35))
		else:
			arms[i_from] = g
	# the other hand: guards, goes to where it will take the ball, takes it
	var catch_seg: Array = segs[segs.size() - 1]
	var pc: Vector3 = catch_seg[3]
	var n_catch := (Vector3.UP + Vector3(float(o) * 0.2, 0, 0.0)).normalized()
	var fing_c := Vector3(0.22 * float(o), -0.35, -1.0)
	if move == "back":
		fing_c = Vector3(0.1 * float(o), -0.4, -1.0)
	elif move == "legs":
		fing_c = Vector3(0.15 * float(o), -0.45, 1.0)
	var t_c := float(catch_seg[1])
	if mt >= t_c:
		var n2 := n_catch.slerp(top_n(o), ease3(x)) if kind == "catch" else n_catch
		var fl2 := fing_c.lerp(Vector3(0.22 * float(o), 0.15, -1.0), ease3(x))
		arms[i_to] = arm("ball", 1.0, true, on_ball(i_to, c, n2, fl2), Vector3(float(o) * 0.6, 0.75, 0.35))
	elif mt >= t_c - 0.3:
		# waiting where it will be caught
		arms[i_to] = arm("ball", 1.0, false, on_ball(i_to, pc, n_catch, fing_c), Vector3(float(o) * 0.6, 0.75, 0.35))
	else:
		arms[i_to] = _guard(i_to, 1.0 - k)
	return {"ball": c, "arms": arms, "crouch": crouch, "rise": 0.0, "lean": lean, "turn": 0.0, "look_up": 0.0,
		"stance_w": sw, "stance": _mv.get("stance", [Vector3.ZERO, Vector3.ZERO])}


# ---------------------------------------------------------------------------
# The shot and the pass
# ---------------------------------------------------------------------------
## The shooting form at `t` (0..1 of the windup) from the ball at `from`
## (holder space; where it was when the windup began).
static func shot(t: float, from: Vector3, from_side: int) -> Dictionary:
	var arms := [relaxed(), relaxed()]
	var crouch := 0.0
	var rise := 0.0
	var c: Vector3
	var n_r: Vector3
	var n_l := Vector3(-1.0, 0.08, 0.05).normalized()
	var side_n := Vector3(1.0, 0.08, 0.05).normalized()
	var under := Vector3(0.15, -0.62, 0.77).normalized()   # under and behind it
	var fr_up := Vector3(0.2, 0.75, 0.6)
	var fl_side := Vector3(-0.1, 0.65, -0.75)
	var f_r := fr_up
	var look := 0.0
	var reach := 0.33
	var shrug_r := 0.0
	var contact_l := true
	var contact_r := true
	if t < T_GATHER:
		# the gather: both hands bring it to the chest
		var g := t / T_GATHER
		var e := ease3(g)
		crouch = lerpf(CROUCH, 0.07, e)
		# (round the front of the body, not through it)
		var to := POCKET - Vector3(0, crouch, 0)
		var ctrl := Vector3(from.x * 0.7, (from.y + to.y) * 0.5, minf(from.z, to.z) - 0.16)
		c = bez(from, ctrl, to, e)
		var tn := Vector3(0.0, 1.0, 0.12).normalized()
		n_r = tn.slerp(side_n, e) if from_side > 0 else side_n
		n_l = n_l if from_side > 0 else tn.slerp(n_l, e)
		f_r = Vector3(0.2, -0.2, -1.0).lerp(Vector3(0.1, 0.5, -0.85), e)
		contact_r = from_side > 0 or g > 0.7
		contact_l = from_side < 0 or g > 0.7
		reach = 0.33 * e
	elif t < T_DIP:
		# the dip: knees bend
		var d := ease3((t - T_GATHER) / (T_DIP - T_GATHER))
		crouch = lerpf(0.07, 0.14, d)
		c = POCKET - Vector3(0, crouch + 0.01 * d, -0.005 * d)
		n_r = side_n
		f_r = Vector3(0.1, 0.5, -0.85)
	elif t < T_RISE:
		# the rise: the legs drive up, the ball goes up to the set point, the
		# shooting hand turns in under it, the elbow under the ball
		var r := ease5((t - T_DIP) / (T_RISE - T_DIP))
		crouch = lerpf(0.14, 0.0, r)
		rise = lerpf(0.0, 0.035, r)
		var from_p := POCKET - Vector3(0, 0.01, -0.005)
		c = from_p.lerp(SET, r) + Vector3(0, rise - crouch, 0)
		# (up and a little out, round the chin)
		c.x += 0.03 * sin(PI * r)
		n_r = side_n.slerp(under, r)
		f_r = Vector3(0.1, 0.5, -0.85).lerp(fr_up, r)
		look = 0.22 * r
		shrug_r = 0.22 * r
	else:
		# the release: the arm extends up and forward, the guide hand comes off
		var q := ease3((t - T_RISE) / (1.0 - T_RISE))
		rise = lerpf(0.035, REL_RISE, q)
		c = SET.lerp(REL, q) + Vector3(0, rise, 0)
		n_r = under
		f_r = fr_up
		look = 0.22
		shrug_r = 0.22 + 0.06 * q
		contact_l = q < 0.35
	var body := Vector3(0, rise - crouch, 0)
	var wr := on_ball(1, c, n_r, f_r)
	var wl := on_ball(0, c, n_l, fl_side)
	if t >= T_RISE and not contact_l:
		# the guide hand opens away from the ball
		var off := ((t - T_RISE) / (1.0 - T_RISE) - 0.35) / 0.65
		wl = [(wl[0] as Vector3) + Vector3(-0.035, 0.01, 0) * ease3(off), wl[1]]
	arms[1] = arm("ball", 1.0, contact_r, wr, Vector3(0.55, -0.6 if t >= T_DIP else 0.2, 0.15) + body, shrug_r, reach)
	arms[0] = arm("ball", 1.0, contact_l, wl, Vector3(-0.7, 0.2, 0.15) + body, 0.08, reach)
	return {"ball": c, "arms": arms, "crouch": crouch, "rise": rise, "lean": 0.05, "turn": 0.0, "look_up": look,
		"stance_w": 0.0, "stance": [Vector3.ZERO, Vector3.ZERO]}


## After the release: the shooting arm stays up, the wrist flicked (the
## fingers down toward the rim), the guide hand up at the side; the jump
## lands.  `t`: seconds since the release.
static func follow(t: float) -> Dictionary:
	var land := ease3(t / 0.24)
	var rise := REL_RISE * (1.0 - land)
	var crouch := 0.06 * sin(PI * clampf((t - 0.16) / 0.3, 0.0, 1.0))
	var body := Vector3(0, rise - crouch, 0)
	var q := ease3(t / 0.12)
	var wr := Vector3(0.12, 1.0, -0.33).lerp(Vector3(0.25, 1.05, -0.27), q) + body
	var fr := Vector3(0.1, 0.4, -0.9).lerp(Vector3(0.05, -0.75, -0.65), q)
	var br := hand_basis(1, Vector3(0.0, -0.6, -0.8).lerp(Vector3(0.0, -0.3, -1.0), q), fr)
	var bl := hand_basis(0, Vector3(1.0, 0.1, 0.0), Vector3(-0.1, 0.7, -0.7))
	var arms := [arm("follow", 1.0, false, [Vector3(-0.2, 0.9, -0.28) + body, bl], Vector3(-0.7, 0.2, 0.15) + body, 0.08, 0.2),
		arm("follow", 1.0, false, [wr, br], Vector3(0.6, -0.4, 0.2) + body, 0.26, 0.25)]
	return {"ball": Vector3.ZERO, "arms": arms, "crouch": crouch, "rise": rise, "lean": 0.05, "turn": 0.0,
		"look_up": 0.22 * (1.0 - ease3((t - 0.3) / 0.3)), "stance_w": 0.0, "stance": [Vector3.ZERO, Vector3.ZERO]}


## The chest pass's windup at `t` (0..1): to the chest with both hands,
## then a push forward.
static func pass_pose(t: float, from: Vector3) -> Dictionary:
	var e := ease5(t)
	var c := from.lerp(PASS_AT, e)
	var side_r := Vector3(1.0, 0.05, 0.1).normalized()
	var side_l := Vector3(-1.0, 0.05, 0.1).normalized()
	var arms := [arm("ball", 1.0, t > 0.7, on_ball(0, c, side_l, Vector3(-0.1, 0.4, -0.9)), Vector3(-0.7, 0.1, 0.2), 0.0, 0.35 * e),
		arm("ball", 1.0, true, on_ball(1, c, side_r.slerp(Vector3(0.6, 0.6, 0.5).normalized(), 1.0 - e), Vector3(0.1, 0.4, -0.9)), Vector3(0.7, 0.1, 0.2), 0.0, 0.35 * e)]
	return {"ball": c, "arms": arms, "crouch": CROUCH, "rise": 0.0, "lean": 0.08, "turn": 0.0, "look_up": 0.0,
		"stance_w": 0.0, "stance": [Vector3.ZERO, Vector3.ZERO]}


# ---------------------------------------------------------------------------
# (build 33) The dunk and the block
# ---------------------------------------------------------------------------
## the gather: both hands bring it to the chest; up in front of the chin at
## the top of the jump (body-relative: the jump is added)
const D_CHEST := Vector3(0.0, 0.75, -0.38)
const D_COCK := Vector3(0.0, 0.95, -0.37)
const SHOULDER := [Vector3(-0.17, 0.835, 0.0), Vector3(0.17, 0.835, 0.0)]


static func _jump_up(r: float) -> float:
	r = clampf(r, 0.0, 1.0)
	return 1.0 - (1.0 - r) * (1.0 - r)


## The dunk's windup `t` seconds in (0 .. BallSync.WINDUP_DUNK) from the
## ball at `from` (holder space: where it was as the windup began; its
## dribbling side `from_side`): the gather step, the load, the jump with the
## ball carried up in both hands, and the slam down to `rel` (holder space:
## where it leaves the hands; INF: in front of the chin).
static func dunk(t: float, from: Vector3, from_side: int, rel: Vector3) -> Dictionary:
	var t1 := BallSync.DUNK_T_GATHER
	var t2 := BallSync.DUNK_T_TAKEOFF
	var t3 := BallSync.DUNK_T_APEX
	var w := BallSync.WINDUP_DUNK
	var crouch := CROUCH
	var rise := 0.0
	var lean := LEAN
	var look := 0.0
	var c: Vector3
	var side_n := Vector3(1.0, 0.08, 0.05).normalized()
	var n_r := side_n
	var n_l := Vector3(-1.0, 0.08, 0.05).normalized()
	var carry := Vector3(0.1, 0.5, -0.85)
	var f_r := carry
	var f_l := Vector3(-0.1, 0.5, -0.85)
	var contact_l := true
	var contact_r := true
	var reach := 0.33
	var shrug := 0.0
	var slam := 0.0
	if t < t1:
		# the gather (a step in toward the rim): both hands to the chest
		var e := ease3(t / t1)
		crouch = lerpf(CROUCH, 0.08, e)
		lean = lerpf(LEAN, 0.12, e)
		var to := D_CHEST - Vector3(0, crouch, 0)
		# (out round the knee as they step, not through it)
		var ctrl := Vector3(from.x * 0.9, (from.y + to.y) * 0.5, minf(from.z, to.z) - 0.22)
		c = bez(from, ctrl, to, e)
		var tn := Vector3(0.0, 1.0, 0.12).normalized()
		n_r = tn.slerp(side_n, e) if from_side > 0 else side_n
		n_l = n_l if from_side > 0 else tn.slerp(n_l, e)
		f_r = Vector3(0.2, -0.2, -1.0).lerp(carry, e) if from_side > 0 else carry
		f_l = Vector3(-0.2, -0.2, -1.0).lerp(f_l, e) if from_side < 0 else f_l
		# (the dribbling hand takes it as it comes up; the other joins it)
		contact_r = (from_side > 0 and from.y > TOP - 0.06) or t / t1 > 0.8
		contact_l = (from_side < 0 and from.y > TOP - 0.06) or t / t1 > 0.8
		reach = 0.33 * e
	elif t < t2:
		# the load: knees bend, the ball low at the chest, out in front of it
		var d := ease3((t - t1) / (t2 - t1))
		crouch = lerpf(0.08, 0.2, d)
		lean = 0.12
		c = D_CHEST - Vector3(0, crouch, 0.03 * d)
	elif t < t3 + 0.06:
		# the jump: the legs drive up, the ball goes up in front of the chin
		var r := (t - t2) / (t3 - t2)
		rise = BallSync.DUNK_APEX * _jump_up(r)
		crouch = lerpf(0.2, 0.0, ease3(minf(1.0, r * 1.6)))
		lean = lerpf(0.12, 0.02, ease3(minf(1.0, r * 1.5)))
		var k := ease5(minf(1.0, r / 0.6))
		c = (D_CHEST - Vector3(0, 0, 0.03)).lerp(D_COCK, k) + Vector3(0, rise - crouch, 0)
		look = 0.14 * k
		shrug = 0.14 * k
	else:
		# the slam: forward and down over the rim, the palms over the top of it
		var q := clampf((t - t3 - 0.06) / maxf(0.01, w - t3 - 0.06), 0.0, 1.0)
		slam = ease3(q)
		rise = BallSync.DUNK_APEX - 0.03 * q * q
		crouch = 0.0
		lean = 0.02 + 0.08 * slam
		var cock := D_COCK + Vector3(0, rise, 0)
		var tgt := rel if rel != Vector3.INF else D_COCK + Vector3(0, rise - 0.04, -0.1)
		c = bez(cock, cock + Vector3(0, 0.04, -0.05), tgt, q * q * (3.0 - 2.0 * q))
		look = 0.14 - 0.08 * slam
		shrug = 0.14 + 0.06 * slam
	if slam > 0.0:
		var top_r := Vector3(0.5, 0.48, 0.72).normalized()
		var top_l := Vector3(-0.5, 0.48, 0.72).normalized()
		n_r = side_n.slerp(top_r, slam)
		n_l = Vector3(-1.0, 0.08, 0.05).normalized().slerp(top_l, slam)
		f_r = carry.lerp(Vector3(0.1, -0.35, -0.95), slam)
		f_l = Vector3(-0.1, 0.5, -0.85).lerp(Vector3(-0.1, -0.35, -0.95), slam)
	var body := Vector3(0, rise - crouch, 0)
	var arms := [arm("ball", 1.0, contact_l, on_ball(0, c, n_l, f_l), Vector3(-0.65, 0.05, 0.25) + body, shrug, reach),
		arm("ball", 1.0, contact_r, on_ball(1, c, n_r, f_r), Vector3(0.65, 0.05, 0.25) + body, shrug, reach)]
	return {"ball": c, "arms": arms, "crouch": crouch, "rise": rise, "lean": lean, "turn": 0.0, "look_up": look,
		"stance_w": 0.0, "stance": [Vector3.ZERO, Vector3.ZERO]}


## After the slam, `t` seconds after the ball left the hands: hanging on the
## rim (the hands on it at `grips`: [left, right] [hand-bone target, basis],
## holder space; `dip`: how far the bent rim has come down), letting go,
## the drop and the landing.
static func dunk_after(t: float, grips: Array, dip: float) -> Dictionary:
	var let_go := BallSync.DUNK_LET_GO
	var hang := BallSync.DUNK_HANG
	var crouch := 0.0
	var rise := 0.0
	var lean := 0.0
	var look := 0.0
	var arms := [relaxed(), relaxed()]
	if t < let_go:
		# (the hands get to the rim before the body comes down to hang)
		var e := ease3((t - 0.06) / 0.2)
		rise = lerpf(BallSync.DUNK_APEX - 0.03, hang, e) - dip
		# the legs swing under them and settle
		crouch = 0.05 + 0.05 * sin(t * 10.0) * exp(-t * 3.0)
		lean = -0.05 + 0.07 * sin(t * 9.0 + 0.6) * exp(-t * 3.5)
		look = 0.2
		for i in 2:
			var g: Array = grips[i]
			var s := -1.0 if i == 0 else 1.0
			arms[i] = arm("rim", 1.0, false, [g[0], g[1]], Vector3(s * 0.75, rise - 0.2, 0.25), 0.12, 0.3)
	else:
		# let go: the drop (falling from where they hung), the landing
		var tf := t - let_go
		var h0 := hang
		var t_land := sqrt(2.0 * h0 / HubBall.G)
		rise = maxf(0.0, h0 - 0.5 * HubBall.G * tf * tf)
		var after := tf - t_land
		if after > 0.0:
			crouch = 0.15 * sin(PI * clampf(after / 0.32, 0.0, 1.0))
			lean = 0.08 * sin(PI * clampf(after / 0.4, 0.0, 1.0))
		else:
			crouch = 0.04 * clampf(tf / 0.15, 0.0, 1.0)
			lean = -0.04
		look = 0.2 * (1.0 - clampf(tf / 0.4, 0.0, 1.0))
		if after < 0.12:
			# the arms come down in front (clear of the big head), then relax
			var k := ease3(tf / 0.3)
			var body := Vector3(0, rise - crouch, 0)
			for i in 2:
				var s := -1.0 if i == 0 else 1.0
				var sh: Vector3 = SHOULDER[i]
				var wr := sh + body + Vector3(s * 0.06, lerpf(0.12, -0.12, k), lerpf(-0.28, -0.24, k))
				var b := hand_basis(i, Vector3(0, -0.6, -0.8).lerp(Vector3(-s, 0, -0.3), k), Vector3(s * 0.1, 0.3, -1.0).lerp(Vector3(0, -0.5, -0.8), k))
				arms[i] = arm("drop", 1.0, false, [wr, b], Vector3(s * 0.7, -0.4, 0.2) + body, 0.0, 0.2)
	return {"ball": Vector3.ZERO, "arms": arms, "crouch": crouch, "rise": rise, "lean": lean, "turn": 0.0, "look_up": look,
		"stance_w": 0.0, "stance": [Vector3.ZERO, Vector3.ZERO]}


## A hand on the rim: the hand-bone target and its orientation (holder
## space) for a grip on the tube at `p` (the tube's centre line), the rim's
## middle at `rc` (the fingers over the top, toward the middle).
static func rim_grip(i: int, p: Vector3, rc: Vector3) -> Array:
	var inward := Vector3(rc.x - p.x, 0.0, rc.z - p.z).normalized()
	var fingers := (inward * 0.75 + Vector3(0, -0.66, 0)).normalized()
	var b := hand_basis(i, Vector3(0, -1.0, 0) + inward * 0.25, fingers)
	# the palm on the top of the tube (its middle a little out of it)
	var palm := p + Vector3(0, HubBall.RIM_TUBE + 0.012, 0) - inward * 0.025
	return [palm - b * (PALM[i] as Vector3), b]


## The jump to block, `t` seconds in: a dip, up with an arm raised toward
## `at` (holder space: the ball, or the shooter), down and land.
static func block_jump(t: float, at: Vector3, hit: bool) -> Dictionary:
	var apex := 0.42
	var crouch := 0.0
	var rise := 0.0
	if t < 0.08:
		crouch = 0.1 * ease3(t / 0.08)
	elif t < 0.3:
		var r := (t - 0.08) / 0.22
		rise = apex * _jump_up(r)
		crouch = lerpf(0.1, 0.04, ease3(minf(1.0, r * 2.0)))
	elif t < 0.56:
		var f := (t - 0.3) / 0.26
		rise = apex * (1.0 - f * f)
		crouch = 0.04
	else:
		var a := (t - 0.56) / 0.14
		crouch = 0.12 * sin(PI * clampf(a, 0.0, 1.0))
	var body := Vector3(0, rise - crouch, 0)
	var s := 1.0 if at.x >= 0.0 else -1.0
	var i := 1 if s > 0.0 else 0
	var o := 1 - i
	var arms := [relaxed(), relaxed()]
	var up_k := ease3(t / 0.16) * (1.0 - ease3((t - 0.5) / 0.15))
	if t < 0.62:
		# the blocking arm: up and forward toward the ball, out past the
		# big head, the palm to it (a swat: a flick forward and down)
		var sh: Vector3 = (SHOULDER[i] as Vector3) + body
		var to := at - sh
		var hz := Vector2(to.x, to.z)
		hz = hz.normalized() if hz.length() > 0.05 else Vector2(0, -1)
		if hz.y > -0.35:
			hz = Vector2(hz.x, -0.35).normalized()
		var swat := 0.0
		if hit:
			swat = sin(PI * clampf((t - BallSync.BLOCK_HIT_T + 0.03) / 0.16, 0.0, 1.0))
		var dir := Vector3(hz.x * 0.42 + s * 0.7, 0.74 - 0.3 * swat, hz.y * 0.42).normalized()
		var rest := Vector3(s * 0.2, -0.95, -0.15).normalized()
		var d := rest.slerp(dir, up_k).normalized()
		var wr := sh + d * 0.3
		var b := hand_basis(i, Vector3(hz.x, 0.15 - 0.6 * swat, hz.y), Vector3(s * 0.25, 1.0, -0.2) + d * 0.6)
		arms[i] = arm("block", 1.0, false, [wr, b], sh + Vector3(s * 0.6, -0.3, 0.25), 0.1 * up_k, 0.25 * up_k)
		# the other arm: out and forward for balance
		var sh2: Vector3 = (SHOULDER[o] as Vector3) + body
		var d2 := rest * Vector3(-1, 1, 1)
		d2 = d2.slerp(Vector3(-s * 0.75, 0.3, -0.58).normalized(), up_k * 0.8).normalized()
		var b2 := hand_basis(o, Vector3(0.0, 0.0, -1.0), Vector3(-s * 0.4, 0.8, -0.3))
		arms[o] = arm("block", 1.0, false, [sh2 + d2 * 0.28, b2], sh2 + Vector3(-s * 0.6, -0.3, 0.25), 0.0, 0.1 * up_k)
	return {"ball": Vector3.ZERO, "arms": arms, "crouch": crouch, "rise": rise, "lean": 0.06 * up_k, "turn": 0.0,
		"look_up": 0.12 * up_k, "stance_w": 0.0, "stance": [Vector3.ZERO, Vector3.ZERO]}
