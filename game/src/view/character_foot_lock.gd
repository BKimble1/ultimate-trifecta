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
## Cost: two two-bone solves per nearby character per frame, no physics
## queries (the feet follow the character origin's plane, as before; slopes
## and stairs keep the V5 behaviour).  Distant (animation-LOD) characters, the
## Night Watch in a cart, the air and every non-ground state run without it.

## clamp of the pin's pull (m): beyond it the foot is released
const MAX_PULL := 0.26
## time constant of the release in the air (s)
const FADE := 0.12
## the animated ankle counts as on the floor below this height (m, model
## space; the stance ankle runs 0.085-0.107 m)
const PLANT_H := 0.108
## largest yaw a planted foot is held against the body's turn (rad)
const MAX_TWIST := 0.6

## set by CharacterView every frame
var weight := 0.0          # 0 off .. 1 full (ground locomotion, travelling)
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


## Teleport / respawn / any cut: forget the pins.
func reset() -> void:
	for i in 2:
		_was[i] = false
		_off[i] = Vector3.ZERO
		_off_v[i] = Vector3.ZERO
		_twist[i] = 0.0
		pinned[i] = false
		pull[i] = Vector3.ZERO
	_w = 0.0


func _setup(sk: Skeleton3D) -> void:
	_bones.clear()
	for sfx in [".L", ".R"]:
		_bones.append([sk.find_bone("thigh" + sfx), sk.find_bone("shin" + sfx), sk.find_bone("foot" + sfx), sk.find_bone("hips")])


func _process_modification_with_delta(delta: float) -> void:
	if profile:
		var t0 := Time.get_ticks_usec()
		_modify(delta)
		profile_us += Time.get_ticks_usec() - t0
		profile_calls += 1
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
	for side in 2:
		var b: Array = _bones[side]
		var ft := sk.get_bone_global_pose(int(b[2]))
		var ankle_w := xf * ft.origin
		var ph := fposmod(phase + (0.0 if side == 0 else 0.5) + duty * 0.5, 1.0)
		var stance := ph < duty and ft.origin.y < PLANT_H and weight > 0.0
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
				_off_v[side] = (want - (_off[side] as Vector3)) / delta
			_off[side] = want
			_twist[side] = clampf(wrapf(float(_pin_yaw[side]) - body_yaw, -PI, PI), -MAX_TWIST, MAX_TWIST)
		else:
			# released: a critically damped return that starts with the
			# pull's own velocity (no kink at toe-off)
			var o: Vector3 = _off[side]
			var ov: Vector3 = _off_v[side]
			var dt := maxf(delta, 0.0)
			var om := 2.0 / FADE
			var acc: Vector3 = -o * om * om - ov * 2.0 * om
			ov += acc * dt
			o += ov * dt
			_off[side] = o
			_off_v[side] = ov
			_twist[side] = float(_twist[side]) * decay
		pull[side] = (_off[side] as Vector3) * _w
		if (_off[side] as Vector3).length_squared() < 1e-8 and absf(float(_twist[side])) < 1e-4:
			continue
		var off: Vector3 = _off[side]
		var target: Vector3 = inv * (ankle_w + off * _w)
		_solve(sk, b, target, float(_twist[side]) * _w)


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
