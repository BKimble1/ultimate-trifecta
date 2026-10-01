class_name CharacterSecondary
extends SkeletonModifier3D
## Procedural overlays applied after the AnimationTree pose: the head lags
## body acceleration on a damped spring, and the spine banks into turns.
## CharacterView feeds `accel` (model space, m/s^2) and `turn_rate` (rad/s)
## once per rendered frame.  The spring is integrated with fixed sub-steps
## (<= 1/120 s), so it stays stable at any frame rate.

const OMEGA := 13.0        # rad/s natural frequency
const ZETA := 0.5          # damping ratio
const MAX_LAG := 0.32      # rad
const SUBSTEP := 1.0 / 120.0

var accel := Vector3.ZERO
var turn_rate := 0.0
var speed := 0.0
var enabled_lean := true
var gain := 1.0            # 0.4 with Reduced Motion
var _lag := Vector2.ZERO   # x = pitch (+ = back), y = roll
var _lag_v := Vector2.ZERO
var _bank := 0.0
var _head := -1
var _spine := -1
var _chest := -1


func reset_motion() -> void:
	_lag = Vector2.ZERO
	_lag_v = Vector2.ZERO
	_bank = 0.0
	accel = Vector3.ZERO
	turn_rate = 0.0


func _skeleton_changed(_old: Skeleton3D, new_sk: Skeleton3D) -> void:
	if new_sk:
		_head = new_sk.find_bone("head")
		_spine = new_sk.find_bone("spine")
		_chest = new_sk.find_bone("chest")


func _process_modification_with_delta(delta: float) -> void:
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
	if absf(_bank) > 1e-4:
		_rotate_model(sk, _spine, Quaternion(Vector3(0, 0, 1), _bank * 0.6))
		_rotate_model(sk, _chest, Quaternion(Vector3(0, 0, 1), _bank * 0.4))
	if _lag.length_squared() > 1e-8:
		_rotate_model(sk, _head, Quaternion(Vector3(1, 0, 0), _lag.x) * Quaternion(Vector3(0, 0, 1), _lag.y))


## Damped spring toward `target`, integrated with fixed sub-steps (semi-
## implicit Euler, <= 1/120 s each; long frames are capped at 0.1 s), so it
## is stable at any frame rate.  Returns [position, velocity].
static func spring_step(x: Vector2, v: Vector2, target: Vector2, delta: float) -> Array:
	var t := minf(delta, 0.1)
	while t > 0.0:
		var h := minf(t, SUBSTEP)
		var acc := (target - x) * (OMEGA * OMEGA) - v * (2.0 * ZETA * OMEGA)
		v += acc * h
		x += v * h
		t -= h
	return [x.limit_length(MAX_LAG), v]


static func _rotate_model(sk: Skeleton3D, bone: int, q: Quaternion) -> void:
	# rotate a bone about its own origin by q expressed in skeleton (model) axes
	if bone < 0:
		return
	var g := sk.get_bone_global_pose(bone)
	var parent := sk.get_bone_parent(bone)
	var pb := sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis()
	var nb := Basis(q) * g.basis
	sk.set_bone_pose_rotation(bone, (pb.inverse() * nb).get_rotation_quaternion())
