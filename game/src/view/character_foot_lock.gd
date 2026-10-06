class_name CharacterFootLock
extends SkeletonModifier3D
## Planted-foot lock for ground locomotion (V6; V5 register M8: a planted
## foot pivoted with the body in 90-degree turns and slid ~0.8 m/s).
##
## While a foot is in its stance (CharacterView passes the gait phase and
## duty of the pose shown) and its animated ankle is near the floor, the
## ankle is pinned where it touched down, in world space; the thigh and shin
## are re-solved with a two-bone IK that keeps the animated knee plane, and
## the foot keeps its animated orientation, turned back by the body's yaw
## since touch-down (a planted foot does not swivel with the body).  When the
## foot lifts, the correction eases out in the air over FADE seconds, where
## it cannot read as a slide.  In a straight run the gait already plants the
## foot (cadence = ground speed / stride), so the correction stays near zero;
## it acts in turns, reversals, stops and speed changes.
##
## Cost: two two-bone solves per nearby character per frame.  Distant
## (animation-LOD) characters, the Night Watch in a cart, the air and every
## non-ground state run without it.
##
## V8 terrain contact (nearby characters; `ground_probe` set): V6 kept the
## feet on the character origin's plane, so on a ramp or a step the front
## foot sank into the ground and the back one floated.  Now, once per
## touch-down, the ground under that ankle is sampled (one ray, the caller's
## probe) and the planted ankle is held at that height (bounded by
## GROUND_MAX); the pelvis drops by the lower foot's deficit (bounded by
## PELVIS_MAX) so the leg can reach.  It eases out in the air like the pull.
## Presentation only: the capsule, collision and navigation never move.

## clamp of the pin's pull (m): beyond it the foot is released
const MAX_PULL := 0.26
## time constant of the release in the air (s)
const FADE := 0.12
## largest rate of change a pull hands to its release (m/s): a pin's step
## divided by a tiny frame delta is not a velocity
const MAX_OFF_V := 20.0
## the animated ankle counts as on the floor below this height (m, model
## space; the stance ankle runs 0.085-0.107 m)
const PLANT_H := 0.108
## largest yaw a planted foot is held against the body's turn (rad)
const MAX_TWIST := 0.6
## V8 terrain contact: largest ground height correction of a foot, and of
## the pelvis (m); a sample further off than GROUND_MAX is ignored (a wall
## edge, a gap: not a step to stand on)
const GROUND_MAX := 0.16
const PELVIS_MAX := 0.1
const GROUND_TAU := 0.05

## set by CharacterView every frame
var weight := 0.0          # 0 off .. 1 full (ground locomotion, travelling)
var ground_probe: Callable  # V8: f(world ankle) -> ground height (world y) or NAN; unset = flat
var phase := 0.0           # gait phase of the pose shown
var duty := 0.2            # stance fraction of the pose shown
## measurements (tests; `profile` makes the modifier time itself, for
## motion_probe --bench)
static var profile := false
static var profile_us := 0
static var profile_calls := 0
var pinned := [false, false]
var pull := [Vector3.ZERO, Vector3.ZERO]

var _bones := []           # per side: [thigh, shin, foot, hips]
var _pin := [Vector3.ZERO, Vector3.ZERO]          # world ankle while planted
var _pin_yaw := [0.0, 0.0]                        # body yaw at touch-down
var _off := [Vector3.ZERO, Vector3.ZERO]          # current pull (world)
var _off_v := [Vector3.ZERO, Vector3.ZERO]        # its rate of change
var _twist := [0.0, 0.0]
var _was := [false, false]
var _w := 0.0
var _gy := [NAN, NAN]      # V8: world ground height sampled at each foot's touch-down
var _gw := [0.0, 0.0]      # its eased weight (in at touch-down, out in the air)
var _pelvis := 0.0
var ground_samples := 0    # rays cast (tests, cost)


## Teleport / respawn / any cut: forget the pins.
func reset() -> void:
	for i in 2:
		_was[i] = false
		_off[i] = Vector3.ZERO
		_off_v[i] = Vector3.ZERO
		_twist[i] = 0.0
		pinned[i] = false
		pull[i] = Vector3.ZERO
		_gy[i] = NAN
		_gw[i] = 0.0
	_pelvis = 0.0
	_w = 0.0


func _setup(sk: Skeleton3D) -> void:
	_bones.clear()
	for sfx in [".L", ".R"]:
		_bones.append([sk.find_bone("thigh" + sfx), sk.find_bone("shin" + sfx), sk.find_bone("foot" + sfx), sk.find_bone("hips")])


func _process_modification_with_delta(delta: float) -> void:
	if profile or Prof.on:
		var t0 := Time.get_ticks_usec()
		_modify(delta)
		profile_us += Time.get_ticks_usec() - t0
		profile_calls += 1
		Prof.add("mod_footlock", t0)
	else:
		_modify(delta)


func _modify(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if _bones.is_empty():
		_setup(sk)
	if int(_bones[0][0]) < 0:
		return
	# the overall weight follows the caller's quickly (no pop when the
	# lock engages or lets go)
	_w += (weight - _w) * (1.0 - exp(-maxf(delta, 0.0) / 0.05))
	if weight <= 0.0 and _w < 0.01:
		if _w > 0.0 or _was[0] or _was[1]:
			reset()
		return
	var xf := sk.global_transform
	var inv := xf.affine_inverse()
	var body_yaw := xf.basis.orthonormalized().get_euler().y
	var decay := exp(-maxf(delta, 0.0) / FADE)
	# --- stance from the animated pose (before any pelvis change)
	var probing := ground_probe.is_valid()
	var gk := 1.0 - exp(-maxf(delta, 0.0) / GROUND_TAU)
	var stances := [false, false]
	var anim_ankles := [Vector3.ZERO, Vector3.ZERO]
	for side in 2:
		var ft0 := sk.get_bone_global_pose(int(_bones[side][2]))
		anim_ankles[side] = xf * ft0.origin
		var ph := fposmod(phase + (0.0 if side == 0 else 0.5) + duty * 0.5, 1.0)
		stances[side] = ph < duty and ft0.origin.y < PLANT_H and weight > 0.0
		if probing and stances[side] and not _was[side]:
			# V8: the ground under this ankle, once per step (world height)
			ground_samples += 1
			var gy: float = ground_probe.call(anim_ankles[side])
			_gy[side] = gy if not is_nan(gy) and absf(gy - xf.origin.y) <= GROUND_MAX else NAN
	# --- V8 terrain contact: each planted ankle is held at its sampled
	# ground height (world), i.e. lifted by (ground - the origin's current
	# height); the weight eases in at touch-down and out in the air
	var lifts := [0.0, 0.0]
	var drop := 0.0
	for side in 2:
		var valid: bool = probing and stances[side] and not is_nan(float(_gy[side]))
		# (in almost at once: a running stance lasts under 0.1 s; out gently in the air)
		var gw_to := 1.0 if valid else 0.0
		_gw[side] = float(_gw[side]) + (gw_to - float(_gw[side])) * (1.0 - exp(-maxf(delta, 0.0) / (0.012 if gw_to > float(_gw[side]) else GROUND_TAU)))
		if not is_nan(float(_gy[side])):
			lifts[side] = clampf(float(_gy[side]) - xf.origin.y, -GROUND_MAX, GROUND_MAX) * float(_gw[side]) * _w
		drop = maxf(drop, -float(lifts[side]))
	drop = minf(drop, PELVIS_MAX)
	_pelvis += (drop - _pelvis) * gk
	var hip_drop := Vector3(0, -_pelvis, 0)
	if _pelvis > 1e-4:
		# the pelvis drops so the leg on the lower ground can reach it
		var hip := int(_bones[0][3])
		sk.set_bone_pose_position(hip, sk.get_bone_pose_position(hip) + inv.basis * hip_drop)
	for side in 2:
		var b: Array = _bones[side]
		var ft := sk.get_bone_global_pose(int(b[2]))
		var ankle_w := xf * ft.origin
		var stance: bool = stances[side]
		if stance and not _was[side]:
			# touch-down: pin here (keeping any pull still easing out)
			_pin[side] = ankle_w + (_off[side] as Vector3)
			_pin_yaw[side] = body_yaw - float(_twist[side])
		_was[side] = stance
		pinned[side] = stance
		if stance:
			var want: Vector3 = (_pin[side] as Vector3) - ankle_w
			want.y = 0.0
			if want.length() > MAX_PULL:
				# out of reach: let the foot go (re-pin at its next contact)
				want = want.limit_length(MAX_PULL)
				_pin[side] = ankle_w + want
			if delta > 0.0:
				_off_v[side] = ((want - (_off[side] as Vector3)) / delta).limit_length(MAX_OFF_V)
			_off[side] = want
			_twist[side] = clampf(wrapf(float(_pin_yaw[side]) - body_yaw, -PI, PI), -MAX_TWIST, MAX_TWIST)
		else:
			# released: a critically damped return that starts with the
			# pull's own velocity (no kink at toe-off).  Solved exactly, not
			# stepped: a stepped spring blew up (to inf, then a NaN skeleton
			# for good) when a frame's delta was long next to FADE (a far
			# character's batched animation time, a slow device frame)
			var r := release_step(_off[side], _off_v[side], delta)
			_off[side] = r[0]
			_off_v[side] = r[1]
			_twist[side] = float(_twist[side]) * decay
		pull[side] = (_off[side] as Vector3) * _w
		# the height: the planted foot's ground lift; any foot gets back what
		# the pelvis drop took from it (the swing foot keeps its clearance)
		var lift: float = float(lifts[side]) + _pelvis
		if (_off[side] as Vector3).length_squared() < 1e-8 and absf(float(_twist[side])) < 1e-4 and absf(lift) < 1e-4:
			continue
		var off: Vector3 = _off[side]
		var target: Vector3 = inv * (ankle_w + off * _w + Vector3(0, lift, 0))
		_solve(sk, b, target, float(_twist[side]) * _w)


## The release in the air, one frame: the critically damped return of the
## pull `o` (moving at `ov`) towards zero, in closed form, so any delta is
## stable; returns [pull, velocity].  Anything non-finite comes back as zero.
static func release_step(o: Vector3, ov: Vector3, delta: float) -> Array:
	var dt := maxf(delta, 0.0)
	var om := 2.0 / FADE
	var e := exp(-om * dt)
	var cv := ov + o * om
	var o2 := (o + cv * dt) * e
	var v2 := (ov - cv * (om * dt)) * e
	if not (o2.is_finite() and v2.is_finite()):
		return [Vector3.ZERO, Vector3.ZERO]
	return [o2, v2]


## Two-bone IK in skeleton space: thigh and shin reach `target` keeping the
## animated knee plane; the foot keeps its animated orientation, turned by
## `twist` about the model's up axis.
func _solve(sk: Skeleton3D, b: Array, target: Vector3, twist: float) -> void:
	var gp := sk.get_bone_global_pose(int(b[3]))
	var gt := sk.get_bone_global_pose(int(b[0]))
	var gs := sk.get_bone_global_pose(int(b[1]))
	var gf := sk.get_bone_global_pose(int(b[2]))
	var h := gt.origin
	var k := gs.origin
	var a := gf.origin
	var la := h.distance_to(k)
	var lb := k.distance_to(a)
	var ht := target - h
	var d := clampf(ht.length(), absf(la - lb) + 1e-4, la + lb - 1e-4)
	if ht.length() < 1e-5:
		return
	var u := ht.normalized()
	# the knee keeps its side of the hip-ankle line (animated knee plane)
	# a small forward bias keeps the knee plane defined when the animated leg
	# is nearly straight (it used to flip between the two and pop the knee)
	var fwd := (gp.basis * Vector3(0, 0, -1)).normalized()
	var pole := (k - h) - (a - h).normalized() * (k - h).dot((a - h).normalized()) + fwd * 0.02
	pole = pole - u * pole.dot(u)
	if pole.length() < 1e-5:
		pole = fwd - u * fwd.dot(u)
	pole = pole.normalized()
	var cos_a := clampf((la * la + d * d - lb * lb) / (2.0 * la * d), -1.0, 1.0)
	var k2 := h + u * (la * cos_a) + pole * (la * sqrt(maxf(0.0, 1.0 - cos_a * cos_a)))
	var t2 := h + u * d
	var q1 := _arc((k - h).normalized(), (k2 - h).normalized())
	var bt := Basis(q1) * gt.basis
	var shin_dir := Basis(q1) * (a - k).normalized()
	var q2 := _arc(shin_dir.normalized(), (t2 - k2).normalized())
	var bs := Basis(q2) * Basis(q1) * gs.basis
	var bf := Basis(Vector3.UP, twist) * gf.basis
	sk.set_bone_pose_rotation(int(b[0]), (gp.basis.inverse() * bt).get_rotation_quaternion())
	sk.set_bone_pose_rotation(int(b[1]), (bt.inverse() * bs).get_rotation_quaternion())
	sk.set_bone_pose_rotation(int(b[2]), (bs.inverse() * bf).get_rotation_quaternion())


static func _arc(from: Vector3, to: Vector3) -> Quaternion:
	var c := from.cross(to)
	var dt := from.dot(to)
	if c.length() < 1e-6:
		return Quaternion() if dt > 0.0 else Quaternion(Vector3.UP, PI)
	return Quaternion(c.normalized(), atan2(c.length(), dt))
