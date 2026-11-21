class_name HubBall
extends RefCounted
## (build 24) The party room's basketball: its physics.
##
## A small ball (the runners are about a metre tall, so it is a mini ball
## and the hoop is a mini hoop) bouncing on the planks, off the walls, off
## and over every piece of furniture, off the runners walking around, and
## through (or off) the Christmas hoop by the bookshelf.  Plain code, a fixed
## step: the host runs it and is the referee (BallSync); every guest runs
## the same code from the host's state between its corrections, so a bounce
## looks the same everywhere.
##
## Nothing keeps the ball: a ball resting on top of something is eased off
## its nearest edge, one that has stopped where nobody can reach it gets a
## nudge back toward the open floor, and one that is somehow still stuck
## after a few seconds (or has left the room) is put back on the floor.
##
## Space: stage space (DormStage), y up, the floor at y = 0, x and z the
## same as HubRoom's floor plan.

const R := 0.075                 # the ball (a mini ball: runners are ~1 m tall)
const G := 9.8
const DT := 1.0 / 120.0          # fixed physics step
const MAX_STEPS := 12            # per call (a long frame doesn't spiral)
const FLOOR_E := 0.72            # planks: a lively bounce
const ROLL_DECEL := 0.5          # m/s^2 rolling resistance
const ROLL_DAMP := 0.18          # and a little more at speed (1/s)
const AIR_DAMP := 0.0            # 1/s (none: a shot lands where it was aimed)
const SLEEP_SPEED := 0.035
const BOUNCE_MIN := 0.32         # slower impacts don't bounce (no jitter)
## (no ball should ever sit on furniture) the push toward the edge, m/s^2
const ROLL_OFF := 2.6
## a ball slow and off the floor this long gets a hop toward open floor
const STUCK_S := 1.0
## and anything still stuck this long is put back on the floor
const RESCUE_S := 5.0
## how far from where a runner can stand the ball can be and still be picked up
const REACH := 0.8
## the highest a runner can pick the ball up from
const REACH_Y := 1.15

# --- the hoop (a freestanding mini hoop by the bookshelf, turned a little
# toward the room so it reads from the walk camera)
const HOOP_BASE := Vector2(4.95, -0.6)
const HOOP_DIR := Vector2(-0.94386, 0.33035)     # (-1, 0.35) normalised: the way it faces
const RIM_Y := 1.6
const RIM_R := 0.145
const RIM_TUBE := 0.011
const RIM_OUT := 0.40            # pole to the middle of the rim
const BOARD_OUT := 0.2           # pole to the front of the board
const BOARD_HALF := Vector3(0.32, 0.21, 0.015)   # half width, height, thickness
const BOARD_Y := RIM_Y + 0.13
const NET_DEPTH := 0.27
const NET_BOTTOM_R := 0.095
const POLE_R := 0.04
const POLE_TOP := RIM_Y + 0.52
const BASE_R := 0.28
const BASE_H := 0.2

enum Kind { FLOOR, WALL, SOFT, WOOD, RIM, BOARD, POLE, PLAYER, NET }

## state
var pos := Vector3(0, R, 0)
var vel := Vector3.ZERO
## angular velocity (rad/s, the axis it spins about): rolling, backspin
var spin := Vector3.ZERO
var sleeping := true
## the last step's support: the floor, something else or nothing
var on_floor := false
var on_top := false
## touched the rim / board since it was last thrown (a swish is clean)
var touched_rim := false
## made shots and the slot that shot it (BallSync sets shooter)
var shooter := -1
var _stuck_t := 0.0
var _rescue_t := 0.0
var _hops := 0
var _acc := 0.0
var _make_cool := 0.0
var _sound_cool: Dictionary = {}
## per-step outputs: [{kind, at, strength}] sounds and {"make": true} events
var events: Array = []
## runners walking around: [[pos (Vector2), vel (Vector2), slot]]
var players: Array = []
## slots the ball passes through (the holder, a shooter just after release)
var ghost: Dictionary = {}
var rng := RandomNumberGenerator.new()

static var _cols: Array = []


static func rim_center() -> Vector3:
	var c := HOOP_BASE + HOOP_DIR * RIM_OUT
	return Vector3(c.x, RIM_Y, c.y)


static func hoop_yaw() -> float:
	# the hoop's local -Z faces HOOP_DIR (Godot's forward)
	return atan2(-HOOP_DIR.x, -HOOP_DIR.y)


static func hoop_basis() -> Basis:
	return Basis(Vector3.UP, hoop_yaw())


# ---------------------------------------------------------------------------
# The room
# ---------------------------------------------------------------------------
## Colliders: {t: "box", lo, hi, e, k} | {t: "obox", c, half, b (Basis), e, k}
## | {t: "cyl", c (Vector2), y0, y1, r, e, k} | {t: "cone", c, y0, h, r, e, k}
## | {t: "ell", c (Vector3), rad, e, k}; e: restitution, k: Kind (sound)
static func colliders() -> Array:
	if not _cols.is_empty():
		return _cols
	var a: Array = []
	var box := func(lo: Vector3, hi: Vector3, e: float, k: int, out: Vector2 = Vector2.ZERO) -> void:
		a.append({"t": "box", "lo": lo, "hi": hi, "e": e, "k": k, "out": out})
	var obox := func(c: Vector3, half: Vector3, yaw: float, e: float, k: int, out: Vector2 = Vector2.ZERO) -> void:
		a.append({"t": "obox", "c": c, "half": half, "b": Basis(Vector3.UP, yaw), "e": e, "k": k, "out": out})
	var cyl := func(c: Vector2, y0: float, y1: float, r: float, e: float, k: int) -> void:
		a.append({"t": "cyl", "c": c, "y0": y0, "y1": y1, "r": r, "e": e, "k": k})
	var ell := func(c: Vector3, rad: Vector3, e: float, k: int) -> void:
		a.append({"t": "ell", "c": c, "rad": rad, "e": e, "k": k})
	# the couch: seat, back and rolled arms (DormStage._build_room)
	# (anything on the seat or the back rolls off the front)
	box.call(Vector3(-5.1, 0.0, -3.0), Vector3(-2.1, 0.66, -2.22), 0.3, Kind.SOFT, Vector2(0, 1))
	box.call(Vector3(-5.1, 0.0, -3.34), Vector3(-2.1, 1.32, -3.0), 0.3, Kind.SOFT, Vector2(0, 1))
	box.call(Vector3(-5.16, 0.0, -3.27), Vector3(-4.88, 0.92, -2.2), 0.35, Kind.SOFT)
	box.call(Vector3(-2.32, 0.0, -3.27), Vector3(-2.04, 0.92, -2.2), 0.35, Kind.SOFT)
	# the side table: a top on four legs (the ball can roll underneath) and
	# its lamp
	box.call(Vector3(-2.3, 0.26, -2.38), Vector3(-1.5, 0.3, -1.82), 0.55, Kind.WOOD)
	for lx in [-1.0, 1.0]:
		for lz in [-1.0, 1.0]:
			cyl.call(Vector2(-1.9 + lx * 0.33, -2.1 + lz * 0.21), 0.0, 0.27, 0.03, 0.5, Kind.WOOD)
	cyl.call(Vector2(-2.1, -2.2), 0.3, 0.76, 0.16, 0.45, Kind.WOOD)
	# the bookshelf
	box.call(Vector3(4.35, 0.0, -3.15), Vector3(5.85, 2.1, -2.65), 0.5, Kind.WOOD)
	# the fireplace: surround, mantel and the low hearth
	var fz := DormStage.FIRE_Z
	box.call(Vector3(-6.0, 0.0, fz - 0.86), Vector3(-5.6, 1.32, fz + 0.86), 0.5, Kind.WALL)
	box.call(Vector3(-5.92, 1.31, fz - 1.0), Vector3(-5.32, 1.43, fz + 1.0), 0.5, Kind.WOOD)
	box.call(Vector3(-5.81, 0.0, fz - 1.0), Vector3(-5.19, 0.06, fz + 1.0), 0.5, Kind.WALL)
	# the floor lamp: base, pole, shade
	cyl.call(Vector2(3.9, -1.9), 0.0, 0.05, 0.25, 0.5, Kind.POLE)
	cyl.call(Vector2(3.9, -1.9), 0.0, 1.55, 0.04, 0.55, Kind.POLE)
	cyl.call(Vector2(3.9, -1.9), 1.42, 1.86, 0.27, 0.35, Kind.SOFT)
	# the armchair: body, seat cushion, back, arms (turned like the mesh)
	var ay := -0.55
	var ab := Basis(Vector3.UP, ay)
	var ac := DormStage.ARMCHAIR
	# (the seat is a pocket between the arms and the back: out the front)
	var front3 := ab * Vector3(0, 0, 1)
	var front := Vector2(front3.x, front3.z)
	obox.call(ac + ab * Vector3(0, 0.24, 0), Vector3(0.525, 0.24, 0.475), ay, 0.3, Kind.SOFT, front)
	obox.call(ac + ab * Vector3(0, 0.32, 0.06), Vector3(0.39, 0.32, 0.39), ay, 0.3, Kind.SOFT, front)
	obox.call(ac + ab * Vector3(0, 0.62, -0.38), Vector3(0.525, 0.62, 0.13), ay, 0.3, Kind.SOFT, front)
	for sx in [-1.0, 1.0]:
		obox.call(ac + ab * Vector3(sx * 0.46, 0.42, 0.0), Vector3(0.11, 0.42, 0.475), ay, 0.3, Kind.SOFT)
	# Season 1: the tree (a cone of needles, soft) and its presents
	var tr := HolidayDecor.TREE
	if HolidayDecor.ENABLED:
		a.append({"t": "cone", "c": Vector2(tr.x, tr.z), "y0": 0.0, "h": HolidayDecor.TREE_TOP + 0.1, "r": 0.92, "e": 0.2, "k": Kind.SOFT})
	for p in (HolidayDecor.PRESENTS if HolidayDecor.ENABLED else []):
		var hx := maxf(float(p[2]), float(p[4])) * 0.45
		box.call(Vector3(float(p[0]) - hx, 0.0, float(p[1]) - hx), Vector3(float(p[0]) + hx, float(p[3]), float(p[1]) + hx), 0.4, Kind.SOFT)
	# the plant by the fireplace: pot and leaves
	cyl.call(Vector2(-5.3, 1.6), 0.0, 0.53, 0.36, 0.5, Kind.WOOD)
	ell.call(Vector3(-5.3, 0.95, 1.6), Vector3(0.5, 0.48, 0.5), 0.2, Kind.SOFT)
	# the beanbag and the floor cushions
	ell.call(Vector3(4.0, 0.32, 1.1), Vector3(0.75, 0.38, 0.7), 0.15, Kind.SOFT)
	ell.call(Vector3(-2.1, 0.13, -1.55), Vector3(0.42, 0.14, 0.42), 0.2, Kind.SOFT)
	ell.call(Vector3(-1.55, 0.12, -1.85), Vector3(0.36, 0.12, 0.36), 0.2, Kind.SOFT)
	# the hoop: its weighted base (a present), the candy-cane pole and the
	# backboard (the rim and the net are handled on their own)
	cyl.call(HOOP_BASE, 0.0, BASE_H, BASE_R, 0.45, Kind.WOOD)
	cyl.call(HOOP_BASE, 0.0, POLE_TOP, POLE_R, 0.6, Kind.POLE)
	var bc := HOOP_BASE + HOOP_DIR * (BOARD_OUT - BOARD_HALF.z)
	obox.call(Vector3(bc.x, BOARD_Y, bc.y), BOARD_HALF, hoop_yaw(), 0.62, Kind.BOARD)
	_cols = a
	return a


## Planes the ball can't pass: [point, normal, e].  The back and left walls;
## the right and the front (camera) sides are open, so an invisible line a
## little past where runners can walk keeps the ball where it can be reached.
const WALLS := [
	[Vector3(0, 0, -3.475), Vector3(0, 0, 1), 0.6],
	[Vector3(-5.975, 0, 0), Vector3(1, 0, 0), 0.6],
	[Vector3(5.75, 0, 0), Vector3(-1, 0, 0), 0.35],
	[Vector3(0, 0, 3.1), Vector3(0, 0, -1), 0.35],
	[Vector3(0, 7.1, 0), Vector3(0, -1, 0), 0.5],
]


# ---------------------------------------------------------------------------
## Put the ball somewhere (resting, or dropped from that height).
func place(p: Vector3, v: Vector3 = Vector3.ZERO) -> void:
	pos = p
	vel = v
	sleeping = v == Vector3.ZERO and p.y <= R + 0.001
	_stuck_t = 0.0
	_rescue_t = 0.0
	_hops = 0
	_acc = 0.0


## Thrown (a shot, a pass, a drop): it flies from `p` with `v`.
func launch(p: Vector3, v: Vector3, p_spin: Vector3 = Vector3.ZERO) -> void:
	place(p, v)
	spin = p_spin
	sleeping = false
	touched_rim = false


## A free spot on the floor for the ball to start on (each new party room):
## open floor, off the runners' marks and in the part of the room the menus
## show.
static func spawn_spot(r: RandomNumberGenerator) -> Vector3:
	for _i in 80:
		var p := Vector2(r.randf_range(-2.4, 2.9), r.randf_range(-1.45, 1.6))
		if not HubRoom.is_free(p):
			continue
		var ok := p.distance_to(HOOP_BASE) > 0.9
		for m in DormStage.MARKS:
			if p.distance_to(Vector2((m as Vector3).x, (m as Vector3).z)) < 0.75:
				ok = false
		if ok:
			return Vector3(p.x, R, p.y)
	return Vector3(1.6, R, 1.7)


## Can a runner standing on the floor pick it up where it is?
static func reachable(p: Vector3) -> bool:
	var f := Vector2(p.x, p.z)
	return p.y <= REACH_Y and HubRoom.resolve(f).distance_to(f) <= REACH - 0.1


## Advance by `delta` seconds (fixed steps).
func step(delta: float) -> void:
	events.clear()
	_acc = minf(_acc + delta, DT * MAX_STEPS)
	while _acc >= DT:
		_acc -= DT
		_step(DT)


func _step(dt: float) -> void:
	_make_cool = maxf(0.0, _make_cool - dt)
	for k in _sound_cool.keys():
		_sound_cool[k] = float(_sound_cool[k]) - dt
	if sleeping:
		# something walked into it?
		if not _players_touch():
			_watch(dt)
			return
		sleeping = false
	var prev := pos
	vel.y -= G * dt
	vel *= 1.0 - AIR_DAMP * dt
	pos += vel * dt
	on_floor = false
	on_top = false
	var top_out := Vector2.ZERO
	# the floor
	if pos.y < R:
		pos.y = R
		if vel.y < 0.0:
			var impact := -vel.y
			vel.y = impact * FLOOR_E if impact > BOUNCE_MIN else 0.0
			# a bounce scrubs a little of the run and spin
			vel.x *= 0.96
			vel.z *= 0.96
			_sound(Kind.FLOOR, impact)
		on_floor = true
	# walls
	for w in WALLS:
		var n: Vector3 = w[1]
		var d := (pos - (w[0] as Vector3)).dot(n)
		if d < R:
			_contact(n, R - d, float(w[2]), Kind.WALL)
	# furniture and the hoop
	for c in colliders():
		var hit := _hit(c)
		if hit.is_empty():
			continue
		var n: Vector3 = hit["n"]
		_contact(n, float(hit["pen"]), float(c["e"]), int(c["k"]))
		if n.y > 0.55:
			on_top = true
			top_out = _outward(c)
	_rim(prev)
	_net(prev, dt)
	_players_hit()
	# rolling
	if on_floor and absf(vel.y) < 0.01:
		var h := Vector2(vel.x, vel.z)
		var sp := h.length()
		var dec := (ROLL_DECEL + ROLL_DAMP * sp) * dt
		h = h * maxf(0.0, sp - dec) / sp if sp > 0.0001 else Vector2.ZERO
		vel.x = h.x
		vel.z = h.y
		# rolling without slipping
		spin = Vector3(h.y, 0.0, -h.x) / R
		if h.length() < SLEEP_SPEED and not on_top:
			vel = Vector3.ZERO
			sleeping = true
	else:
		spin *= 1.0 - 0.4 * dt
	if on_top:
		# off the top of whatever it landed on, over the nearest edge
		vel.x += top_out.x * ROLL_OFF * dt
		vel.z += top_out.y * ROLL_OFF * dt
	_watch(dt)


## Sphere against a collider: {} or {n: Vector3 (out of it), pen: float}.
func _hit(c: Dictionary) -> Dictionary:
	match String(c["t"]):
		"box":
			return _vs_box(pos, c["lo"], c["hi"])
		"obox":
			var b: Basis = c["b"]
			var lp := b.inverse() * (pos - (c["c"] as Vector3))
			var half: Vector3 = c["half"]
			var h := _vs_box(lp, -half, half)
			if not h.is_empty():
				h["n"] = b * (h["n"] as Vector3)
			return h
		"cyl":
			return _vs_cyl(c["c"], float(c["y0"]), float(c["y1"]), float(c["r"]))
		"cone":
			return _vs_cone(c["c"], float(c["y0"]), float(c["h"]), float(c["r"]))
		"ell":
			return _vs_ell(c["c"], c["rad"])
	return {}


static func _vs_box(p: Vector3, lo: Vector3, hi: Vector3) -> Dictionary:
	if p.x < lo.x - R or p.x > hi.x + R or p.y < lo.y - R or p.y > hi.y + R or p.z < lo.z - R or p.z > hi.z + R:
		return {}
	var q := p.clamp(lo, hi)
	var d := p - q
	var dist := d.length()
	if dist > 0.00001:
		if dist >= R:
			return {}
		return {"n": d / dist, "pen": R - dist}
	# the centre is inside: out through the nearest face (never down)
	var best := INF
	var n := Vector3.UP
	var pen := 0.0
	var faces := [[p.x - lo.x, Vector3.LEFT], [hi.x - p.x, Vector3.RIGHT], [hi.y - p.y, Vector3.UP],
		[p.z - lo.z, Vector3.FORWARD], [hi.z - p.z, Vector3.BACK]]
	for f in faces:
		if float(f[0]) < best:
			best = float(f[0])
			n = f[1]
	pen = best + R
	return {"n": n, "pen": pen}


func _vs_cyl(c: Vector2, y0: float, y1: float, r: float) -> Dictionary:
	if pos.y < y0 - R or pos.y > y1 + R:
		return {}
	var h := Vector2(pos.x - c.x, pos.z - c.y)
	var dh := h.length()
	if dh > r + R:
		return {}
	var dir := h / dh if dh > 0.0001 else Vector2(0, 1)
	var q: Vector3
	if dh > r:
		q = Vector3(c.x + dir.x * r, clampf(pos.y, y0, y1), c.y + dir.y * r)
	elif pos.y > y1:
		q = Vector3(pos.x, y1, pos.z)
	elif pos.y < y0:
		q = Vector3(pos.x, y0, pos.z)
	else:
		# inside: out of the side or over the top, whichever is nearer
		if y1 - pos.y < r - dh:
			return {"n": Vector3.UP, "pen": y1 - pos.y + R}
		return {"n": Vector3(dir.x, 0, dir.y), "pen": r - dh + R}
	var d := pos - q
	var dist := d.length()
	if dist >= R or dist < 0.00001:
		return {}
	return {"n": d / dist, "pen": R - dist}


func _vs_cone(c: Vector2, y0: float, ht: float, r0: float) -> Dictionary:
	var y := pos.y - y0
	if y < -R or y > ht + R:
		return {}
	var h := Vector2(pos.x - c.x, pos.z - c.y)
	var dh := h.length()
	if dh > r0 + R:
		return {}
	var dir := h / dh if dh > 0.0001 else Vector2(0, 1)
	# the slanted side in (radial, up): through (r0, 0) and (0, ht)
	var l := sqrt(ht * ht + r0 * r0)
	var n2 := Vector2(ht, r0) / l
	var sd := ((dh - r0) * n2.x + y * n2.y)
	if sd >= R:
		return {}
	return {"n": Vector3(dir.x * n2.x, n2.y, dir.y * n2.x), "pen": R - sd}


func _vs_ell(c: Vector3, rad: Vector3) -> Dictionary:
	var big := rad + Vector3(R, R, R)
	var q := (pos - c) / big
	var l := q.length()
	if l >= 1.0:
		return {}
	var u := q / l if l > 0.0001 else Vector3.UP
	var s := c + u * big
	var n := (u / big).normalized()
	return {"n": n, "pen": maxf(0.0, (s - pos).dot(n))}


## Bounce off a surface: out of it, the speed into it reflected (e) and a
## little scrubbed along it.
func _contact(n: Vector3, pen: float, e: float, kind: int) -> void:
	pos += n * pen
	var vn := vel.dot(n)
	if vn >= 0.0:
		return
	var impact := -vn
	var ee := e if impact > BOUNCE_MIN else 0.0
	vel -= n * vn * (1.0 + ee)
	var vt := vel - n * vel.dot(n)
	vel -= vt * (0.04 if kind != Kind.SOFT else 0.12)
	if kind == Kind.RIM or kind == Kind.BOARD:
		touched_rim = true
	_sound(kind, impact)


## Which way is "off" a collider for a ball resting on top of it: toward
## where a runner could stand to pick it up (HubRoom), or else straight out
## from its middle.
func _outward(c: Dictionary) -> Vector2:
	var fixed: Vector2 = c.get("out", Vector2.ZERO)
	if fixed != Vector2.ZERO:
		return fixed
	var f := Vector2(pos.x, pos.z)
	var to := HubRoom.resolve(f) - f
	if to.length() > 0.05:
		return to.normalized()
	var mid: Vector2
	match String(c["t"]):
		"box":
			mid = Vector2(((c["lo"] as Vector3).x + (c["hi"] as Vector3).x) * 0.5, ((c["lo"] as Vector3).z + (c["hi"] as Vector3).z) * 0.5)
		"obox", "ell":
			mid = Vector2((c["c"] as Vector3).x, (c["c"] as Vector3).z)
		_:
			mid = c["c"]
	var o := f - mid
	return o.normalized() if o.length() > 0.01 else Vector2(0, 1)


# ---------------------------------------------------------------------------
# The hoop: the rim (a ring), the net and a made shot
# ---------------------------------------------------------------------------
func _rim(prev: Vector3) -> void:
	var rc := rim_center()
	var h := Vector2(pos.x - rc.x, pos.z - rc.z)
	var dh := h.length()
	if absf(pos.y - RIM_Y) < R + RIM_TUBE and dh > RIM_R - R - RIM_TUBE - 0.01 and dh < RIM_R + R + RIM_TUBE:
		var dir := h / dh if dh > 0.0001 else HOOP_DIR
		var ring := Vector3(rc.x + dir.x * RIM_R, RIM_Y, rc.z + dir.y * RIM_R)
		var d := pos - ring
		var dist := d.length()
		if dist < R + RIM_TUBE and dist > 0.00001:
			_contact(d / dist, R + RIM_TUBE - dist, 0.55, Kind.RIM)
	# through the hoop from above: a basket
	if prev.y >= RIM_Y and pos.y < RIM_Y and vel.y < 0.0 and _make_cool <= 0.0:
		var t := (prev.y - RIM_Y) / maxf(0.00001, prev.y - pos.y)
		var at := prev.lerp(pos, t)
		if Vector2(at.x - rc.x, at.z - rc.z).length() < RIM_R - R * 0.35:
			_make_cool = 1.0
			events.append({"make": true, "swish": not touched_rim, "shooter": shooter, "at": rc})


## The net: a soft funnel under the rim that slows the ball and drops it
## straight down (and stops one coming up from underneath).
func _net(prev: Vector3, dt: float) -> void:
	var rc := rim_center()
	var top := RIM_Y
	var bottom := RIM_Y - NET_DEPTH
	if pos.y > top or pos.y < bottom - R:
		return
	var h := Vector2(pos.x - rc.x, pos.z - rc.z)
	var dh := h.length()
	var k := clampf((top - pos.y) / NET_DEPTH, 0.0, 1.0)
	var nr := lerpf(RIM_R, NET_BOTTOM_R, k)
	if dh > nr + R * 0.6:
		return   # outside the net
	if prev.y < pos.y and prev.y < bottom + 0.05 and vel.y > 0.0:
		# from below: the net catches it and it falls back
		vel.y = -vel.y * 0.25
		_sound(Kind.NET, 1.0)
		return
	# in the net: drag, and drawn to the middle
	var drag := exp(-7.0 * dt)
	vel.x *= drag
	vel.z *= drag
	vel.y *= exp(-1.6 * dt)
	if dh > 0.0001:
		var pull := minf(dh, 2.4 * dt)
		pos.x -= h.x / dh * pull * 0.5
		pos.z -= h.y / dh * pull * 0.5
	if dh > nr - R * 0.4:
		# the strings hold it in
		var dir2 := h / dh
		var over := dh - (nr - R * 0.4)
		pos.x -= dir2.x * over
		pos.z -= dir2.y * over
		var vh := Vector2(vel.x, vel.z)
		if vh.dot(dir2) > 0.0:
			vh -= dir2 * vh.dot(dir2) * 1.2
			vel.x = vh.x
			vel.z = vh.y
	spin *= drag


# ---------------------------------------------------------------------------
# Runners (walking around) bump the ball along
# ---------------------------------------------------------------------------
const BODY_R := 0.2
const BODY_H := 0.95


func _players_touch() -> bool:
	for pl in players:
		if ghost.has(int(pl[2])):
			continue
		var p: Vector2 = pl[0]
		if pos.y < BODY_H + R and Vector2(pos.x, pos.z).distance_to(p) < BODY_R + R:
			return true
	return false


func _players_hit() -> void:
	for pl in players:
		if ghost.has(int(pl[2])):
			continue
		var p: Vector2 = pl[0]
		var pv: Vector2 = pl[1]
		if pos.y > BODY_H + R:
			continue
		var h := Vector2(pos.x - p.x, pos.z - p.y)
		var dh := h.length()
		if dh >= BODY_R + R:
			continue
		var dir := h / dh if dh > 0.0001 else (pv.normalized() if pv.length() > 0.01 else Vector2(0, 1))
		var n := Vector3(dir.x, 0.0, dir.y)
		_contact(n, BODY_R + R - dh, 0.35, Kind.PLAYER)
		# a runner walking into it sends it on ahead (a little faster than
		# they walk, so it doesn't stick to their feet)
		var push := pv.dot(dir) * 1.15
		var vn := Vector2(vel.x, vel.z).dot(dir)
		if push > vn:
			vel.x += dir.x * (push - vn)
			vel.z += dir.y * (push - vn)
			vel.y = maxf(vel.y, 0.25 * (push - vn))


# ---------------------------------------------------------------------------
# Never stuck
# ---------------------------------------------------------------------------
func _watch(dt: float) -> void:
	if not is_finite(pos.x) or not is_finite(pos.y) or not is_finite(pos.z) or not is_finite(vel.length()) \
			or pos.y < -0.5 or pos.y > 7.5 or absf(pos.x) > 7.0 or pos.z < -4.0 or pos.z > 4.0:
		rescue()
		return
	var slow := vel.length() < 0.3
	var up := pos.y > R + 0.02
	var good := not up and reachable(pos)
	if slow and not good:
		_stuck_t += dt
	else:
		_stuck_t = 0.0
	# the rescue clock runs until it is back on open floor (a hop that lands
	# it back where it was doesn't reset it)
	if good:
		_rescue_t = 0.0
		_hops = 0
	elif not sleeping or slow:
		_rescue_t += dt
	if _stuck_t >= STUCK_S:
		# a hop toward the open floor, high enough to clear an armrest; each
		# further hop tries a little further round
		_stuck_t = 0.0
		var f := Vector2(pos.x, pos.z)
		var to := HubRoom.resolve(f) - f
		var dir := to.normalized() if to.length() > 0.02 else Vector2(0, 1)
		dir = dir.rotated(float(_hops) * 0.9 * (1.0 if _hops % 2 == 0 else -1.0))
		_hops += 1
		# (from the floor, under a table: a low scoot out; off a top: a hop)
		vel = Vector3(dir.x * 1.3, 2.4, dir.y * 1.3) if up else Vector3(dir.x * 1.6, 0.5, dir.y * 1.6)
		sleeping = false
	if _rescue_t >= RESCUE_S:
		rescue()


## Back on the open floor (dropped in from a little height so it is seen
## arriving).
func rescue() -> void:
	var p := spawn_spot(rng)
	place(Vector3(p.x, 0.9, p.z), Vector3(0, -0.5, 0))
	spin = Vector3.ZERO
	events.append({"kind": Kind.FLOOR, "rescue": true, "at": pos, "strength": 0.0})


func _sound(kind: int, strength: float) -> void:
	if strength < 0.45 and kind != Kind.NET:
		return
	if float(_sound_cool.get(kind, 0.0)) > 0.0:
		return
	_sound_cool[kind] = 0.07
	events.append({"kind": kind, "at": pos, "strength": strength})
