class_name CharacterPoseFade
extends SkeletonModifier3D
## Pose-continuous transitions for CharacterView (V5).  The first modifier on
## the skeleton: it sees the AnimationTree's pose and, during a fade, replaces
## it with a blend from the pose that was actually on screen when the fade
## started ("dead blending"): that pose keeps moving with its own angular
## velocity, decaying over HALFLIFE, while the weight eases into the new
## animation.
##
## Why: AnimationNodeTransition and OneShot cross-fade only two inputs.  A
## new request during a running cross-fade drops the half-faded pose in one
## frame (on_floor flicker, a landing during a state fade, tag phases under
## prediction corrections, emote restarts), which measured as 50-100 cm
## single-frame snaps at the hands.  Starting every fade from the displayed
## pose cannot snap, however often it is interrupted.
##
## Cost: while idle it copies 23 bone rotations and 2 positions per frame
## (the history it needs for velocity); during a fade (typically 0.06-0.3 s)
## it blends them.  Distant (LOD) characters skip fades: CharacterView cuts.

const HALFLIFE := 0.05
const LN2 := 0.6931472
## bones whose translation is animated (the rest only rotate)
const MOVING_BONES := ["root", "hips"]

## completed fade starts (tests)
var fades_started := 0
var _n := 0
var _rot: Array[Quaternion] = []        # pose shown this frame
var _rot_prev: Array[Quaternion] = []   # pose shown last frame
var _src: Array[Quaternion] = []        # pose shown when the fade began
var _src_w: PackedVector3Array = []     # its angular velocity (parent space, rad/s)
var _pos_i: PackedInt32Array = []
var _pos: PackedVector3Array = []
var _pos_prev: PackedVector3Array = []
var _src_p: PackedVector3Array = []
var _src_v: PackedVector3Array = []
var _hist := 0          # frames of history (velocity needs 2)
var _dt := 1.0 / 60.0
var _t := 0.0
var _dur := 0.0


func fading() -> bool:
	return _dur > 0.0


## Fade from what is on screen now into whatever the animation shows next,
## over `dur` seconds.  Safe to call during a running fade.
func capture(dur: float) -> void:
	if dur <= 0.0 or _hist < 1 or _n == 0:
		_dur = 0.0
		return
	var have_vel := _hist >= 2 and _dt > 0.0
	for i in _n:
		_src[i] = _rot[i]
		var w := Vector3.ZERO
		if have_vel:
			var dq := _rot[i] * _rot_prev[i].inverse()
			if dq.w < 0.0:
				dq = -dq
			var ang := dq.get_angle()
			if ang > 1e-5:
				w = dq.get_axis() * (ang / _dt)
		_src_w[i] = w.limit_length(30.0)
	for k in _pos_i.size():
		_src_p[k] = _pos[k]
		_src_v[k] = ((_pos[k] - _pos_prev[k]) / _dt).limit_length(12.0) if have_vel else Vector3.ZERO
	_t = 0.0
	_dur = dur
	fades_started += 1


## Teleport / respawn: no blend and no velocity carried across the cut.
func cut() -> void:
	_dur = 0.0
	_hist = 0


func _setup(sk: Skeleton3D) -> void:
	_n = sk.get_bone_count()
	_rot.resize(_n)
	_rot_prev.resize(_n)
	_src.resize(_n)
	_src_w.resize(_n)
	_pos_i.clear()
	for b in MOVING_BONES:
		var i := sk.find_bone(b)
		if i >= 0:
			_pos_i.append(i)
	var m := _pos_i.size()
	_pos.resize(m)
	_pos_prev.resize(m)
	_src_p.resize(m)
	_src_v.resize(m)
	_hist = 0


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if _n != sk.get_bone_count():
		_setup(sk)
	var tmp := _rot_prev
	_rot_prev = _rot
	_rot = tmp
	var tmp_p := _pos_prev
	_pos_prev = _pos
	_pos = tmp_p
	if _dur > 0.0:
		_t += delta
		var u := clampf(_t / _dur, 0.0, 1.0)
		var wgt := u * u * (3.0 - 2.0 * u)
		# distance travelled by a velocity decaying with HALFLIFE
		var drift := HALFLIFE / LN2 * (1.0 - exp(-LN2 * _t / HALFLIFE))
		for i in _n:
			var a := sk.get_bone_pose_rotation(i)
			var s: Quaternion = _src[i]
			var w: Vector3 = _src_w[i]
			var wl := w.length()
			if wl > 1e-5:
				s = (Quaternion(w / wl, wl * drift) * s).normalized()
			var r := s.slerp(a, wgt)
			sk.set_bone_pose_rotation(i, r)
			_rot[i] = r
		for k in _pos_i.size():
			var bi := _pos_i[k]
			var p := sk.get_bone_pose_position(bi)
			var q := (_src_p[k] + _src_v[k] * drift).lerp(p, wgt)
			sk.set_bone_pose_position(bi, q)
			_pos[k] = q
		if _t >= _dur:
			_dur = 0.0
	else:
		for i in _n:
			_rot[i] = sk.get_bone_pose_rotation(i)
		for k in _pos_i.size():
			_pos[k] = sk.get_bone_pose_position(_pos_i[k])
	_dt = maxf(delta, 1e-4)
	_hist = mini(_hist + 1, 2)
