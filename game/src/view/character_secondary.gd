class_name CharacterSecondary
extends SkeletonModifier3D
## Procedural overlays applied after the AnimationTree pose: the head lags
## body acceleration on a damped spring, the body leans into acceleration and
## back against braking (V5: a little weight shift on starts, stops and
## reversals, with one soft wobble), and the spine banks into turns.
## CharacterView feeds `accel` (model space, m/s^2, already filtered and
## bounded) and `turn_rate` (rad/s) once per rendered frame.  The springs are
## integrated with fixed sub-steps (<= 1/120 s), so they stay stable at any
## frame rate.  Presentation only.

const OMEGA := 13.0        # rad/s natural frequency
const ZETA := 0.5          # damping ratio
const MAX_LAG := 0.32      # rad
const SUBSTEP := 1.0 / 120.0
## body lean: rad per m/s^2 of forward acceleration, and its limit
const LEAN_GAIN := 0.0032
const MAX_LEAN := 0.13

var accel := Vector3.ZERO
var turn_rate := 0.0
var speed := 0.0
var enabled_lean := true
var gain := 1.0            # 0.4 with Reduced Motion
var _lag := Vector2.ZERO   # x = pitch (+ = back), y = roll
var _lag_v := Vector2.ZERO
var _bank := 0.0
var _lean := Vector2.ZERO  # x = pitch of the spine (+ = back)
var _lean_v := Vector2.ZERO
var _head := -1
var _spine := -1
var _chest := -1


func reset_motion() -> void:
	_lag = Vector2.ZERO
	_lag_v = Vector2.ZERO
	_bank = 0.0
	_lean = Vector2.ZERO
	_lean_v = Vector2.ZERO
	accel = Vector3.ZERO
	turn_rate = 0.0


func _skeleton_changed(_old: Skeleton3D, new_sk: Skeleton3D) -> void:
	if new_sk:
		_head = new_sk.find_bone("head")
		_spine = new_sk.find_bone("spine")
		_chest = new_sk.find_bone("chest")


func _process_modification_with_delta(delta: float) -> void:
	if Prof.on:
		var t0 := Prof.t()
		_modify(delta)
		Prof.add("mod_secondary", t0)
		return
	_modify(delta)


func _modify(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if _head < 0:
		_skeleton_changed(null, sk)
	if _head < 0:
		return
	# accel in model space: -Z forward.  Forward acceleration tips the head back.
	var target := Vector2(clampf(-accel.z * 0.012, -MAX_LAG, MAX_LAG), clampf(-accel.x * 0.010, -MAX_LAG, MAX_LAG)) * gain
	var st := spring_step(_lag, _lag_v, target, delta)
	_lag = st[0]
	_lag_v = st[1]
	var bank_target := clampf(-turn_rate * speed * 0.018, -0.3, 0.3) * gain if enabled_lean else 0.0
	_bank = lerpf(_bank, bank_target, 1.0 - exp(-delta * 10.0))
	# body lean: forward acceleration tips the body forward, braking leans it
	# back (accel.z < 0 is forward; +x about X tips the top backward)
	var lean_target := Vector2(clampf(accel.z * LEAN_GAIN, -MAX_LEAN, MAX_LEAN), 0.0) * gain if enabled_lean else Vector2.ZERO
	var ls := spring_step(_lean, _lean_v, lean_target, delta, 10.0, 0.6, MAX_LEAN)
	_lean = ls[0]
	_lean_v = ls[1]
	if absf(_lean.x) > 1e-4:
		# upper body only (rotating the hips would swing the planted feet)
		_rotate_model(sk, _spine, Quaternion(Vector3(1, 0, 0), _lean.x * 0.6))
		_rotate_model(sk, _chest, Quaternion(Vector3(1, 0, 0), _lean.x * 0.4))
	if absf(_bank) > 1e-4:
		_rotate_model(sk, _spine, Quaternion(Vector3(0, 0, 1), _bank * 0.6))
		_rotate_model(sk, _chest, Quaternion(Vector3(0, 0, 1), _bank * 0.4))
	if _lag.length_squared() > 1e-8:
		_rotate_model(sk, _head, Quaternion(Vector3(1, 0, 0), _lag.x) * Quaternion(Vector3(0, 0, 1), _lag.y))


## Damped spring toward `target`, integrated with fixed sub-steps (semi-
## implicit Euler, <= 1/120 s each; long frames are capped at 0.1 s), so it
## is stable at any frame rate.  Returns [position, velocity].
static func spring_step(x: Vector2, v: Vector2, target: Vector2, delta: float, omega: float = OMEGA,
		zeta: float = ZETA, limit: float = MAX_LAG) -> Array:
	var t := minf(delta, 0.1)
	while t > 0.0:
		var h := minf(t, SUBSTEP)
		var acc := (target - x) * (omega * omega) - v * (2.0 * zeta * omega)
		v += acc * h
		x += v * h
		t -= h
	return [x.limit_length(limit), v]


static func _rotate_model(sk: Skeleton3D, bone: int, q: Quaternion) -> void:
	# rotate a bone about its own origin by q expressed in skeleton (model) axes
	if bone < 0:
		return
	var g := sk.get_bone_global_pose(bone)
	var parent := sk.get_bone_parent(bone)
	var pb := sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis()
	var nb := Basis(q) * g.basis
	sk.set_bone_pose_rotation(bone, (pb.inverse() * nb).get_rotation_quaternion())
