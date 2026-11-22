class_name BallRig
extends SkeletonModifier3D
## (build 30) A runner's body with the basketball: the last skeleton
## modifier (after the animation, the pose fade, the secondary motion and
## the foot lock), added by HubBallView the first time a runner has the
## ball and faded in and out with it.  Presentation only.
##
##   the legs: the hips drop (`crouch`: the knees bend, the feet stay where
##       the animation put them) or rise (`rise`: a jump, the feet leave the
##       floor with the body), and the feet can step to a stance
##       (`stance_w`, `stance`: a wide stance for a move between the legs);
##       each leg is a two-bone solve that keeps its knee forward
##   the upper body: leans forward (`lean`), turns (`turn`), the head tips
##       back to look up at the rim (`look_up`), each shoulder lifts
##       (`shrug`) and comes forward (`reach`) for the ball
##   the arms: a two-bone solve per arm with the elbow toward `elbow`, the
##       hand bone at `wrist` turned to `hand_basis` (HubBallView puts the
##       palm on the ball's surface with it); the forearm takes part of the
##       wrist's twist so the skin doesn't wring
##
## Everything HubBallView sets is in world space; `shoulder` and `posed`
## (outputs, skeleton space) are what this pass measured, read back by the
## view (its reach) and by tests (inside Skeleton3D.skeleton_updated, the
## only time the modified pose exists).

const SIDES := [".L", ".R"]
## the fraction of the wrist's twist the forearm takes
const FOREARM_TWIST := 0.55
## the hips' height standing (skeleton space)
const HIPS_Y := 0.51

## overall weight (0: the animation only)
var w := 0.0
var crouch := 0.0
var rise := 0.0
var lean := 0.0
var turn := 0.0
var look_up := 0.0
var stance_w := 0.0
## skeleton-space ankle targets for the stance (L, R): x right, y up, -z forward
var stance := [Vector3.ZERO, Vector3.ZERO]
## per arm (L, R)
var arm_w := [0.0, 0.0]
var wrist := [Vector3.ZERO, Vector3.ZERO]
var hand_basis := [Basis(), Basis()]
var elbow := [Vector3.ZERO, Vector3.ZERO]
var shrug := [0.0, 0.0]
var reach := [0.0, 0.0]
## outputs (skeleton space): each upper arm's origin after the body pose,
## and whether this pass ran
var shoulder := [Vector3(-0.17, 0.84, 0.0), Vector3(0.17, 0.84, 0.0)]
var measured := false
var passes := 0

var _b := {}


func _bones(sk: Skeleton3D) -> bool:
	if not _b.is_empty():
		return int(_b["hips"]) >= 0
	for n in ["hips", "spine", "chest", "neck", "head"]:
		_b[n] = sk.find_bone(n)
	for i in 2:
		var s: String = SIDES[i]
		_b["shoulder%d" % i] = sk.find_bone("shoulder" + s)
		_b["upper%d" % i] = sk.find_bone("upper_arm" + s)
		_b["fore%d" % i] = sk.find_bone("forearm" + s)
		_b["hand%d" % i] = sk.find_bone("hand" + s)
		_b["thigh%d" % i] = sk.find_bone("thigh" + s)
		_b["shin%d" % i] = sk.find_bone("shin" + s)
		_b["foot%d" % i] = sk.find_bone("foot" + s)
	return int(_b["hips"]) >= 0


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or not _bones(sk):
		return
	passes += 1
	var k := clampf(w, 0.0, 1.0)
	var inv := sk.global_transform.affine_inverse()
	if k > 0.0005:
		_body(sk, k)
	for i in 2:
		shoulder[i] = sk.get_bone_global_pose(int(_b["upper%d" % i])).origin
	measured = true
	if k <= 0.0005:
		return
	for i in 2:
		var aw := clampf(float(arm_w[i]), 0.0, 1.0) * k
		if aw <= 0.0005:
			continue
		var hb: Basis = inv.basis * (hand_basis[i] as Basis)
		solve(sk, int(_b["upper%d" % i]), int(_b["fore%d" % i]), int(_b["hand%d" % i]),
			inv * (wrist[i] as Vector3), inv * (elbow[i] as Vector3), hb.orthonormalized(), aw, FOREARM_TWIST)


## The legs, the upper body, the head and the shoulders.
func _body(sk: Skeleton3D, k: float) -> void:
	var ank := [sk.get_bone_global_pose(int(_b["foot0"])).origin, sk.get_bone_global_pose(int(_b["foot1"])).origin]
	var dy := (rise - crouch) * k
	var sw := clampf(stance_w, 0.0, 1.0) * k
	if sw > 0.0005:
		# (in a stance the hips go to a height of their own, not the gait's
		# bob: crouch below standing)
		var hy := sk.get_bone_global_pose(int(_b["hips"])).origin.y
		dy = lerpf(dy, HIPS_Y - crouch + rise - hy, sw)
	# (the knees as animated, carried down with the hips)
	var knee0 := [sk.get_bone_global_pose(int(_b["shin0"])).origin + Vector3(0, dy, 0),
		sk.get_bone_global_pose(int(_b["shin1"])).origin + Vector3(0, dy, 0)]
	if absf(dy) > 1e-5:
		var hips := int(_b["hips"])
		var par := sk.get_bone_parent(hips)
		var pb := sk.get_bone_global_pose(par).basis if par >= 0 else Basis()
		sk.set_bone_pose_position(hips, sk.get_bone_pose_position(hips) + pb.inverse() * Vector3(0, dy, 0))
	for i in 2:
		var tgt: Vector3 = (ank[i] as Vector3).lerp(stance[i], sw) + Vector3(0, maxf(rise, 0.0) * k, 0)
		if absf(dy) > 1e-5 or sw > 0.0005:
			# the knee keeps the animation's side of the leg, bent forward
			# over the toes (a little out in a wide stance)
			var knee := (knee0[i] as Vector3) + Vector3(0, 0, -0.03 - 0.09 * sw) + Vector3((-0.2 if i == 0 else 0.2) * sw, 0, 0)
			solve(sk, int(_b["thigh%d" % i]), int(_b["shin%d" % i]), int(_b["foot%d" % i]), tgt, knee, null, 1.0, 0.0)
	# the upper body: forward lean (about the right axis, -angle tips the top
	# forward), a turn, and the head back to the hoop
	var ln := lean * k
	var tn := turn * k
	if absf(ln) > 1e-5 or absf(tn) > 1e-5:
		CharacterSecondary._rotate_model(sk, int(_b["spine"]), Quaternion(Vector3.UP, tn * 0.4) * Quaternion(Vector3.RIGHT, -ln * 0.55))
		CharacterSecondary._rotate_model(sk, int(_b["chest"]), Quaternion(Vector3.UP, tn * 0.6) * Quaternion(Vector3.RIGHT, -ln * 0.45))
	var hd := (look_up + lean * 0.6) * k
	if absf(hd) > 1e-5:
		CharacterSecondary._rotate_model(sk, int(_b["neck"]), Quaternion(Vector3.RIGHT, hd * 0.4))
		CharacterSecondary._rotate_model(sk, int(_b["head"]), Quaternion(Vector3.RIGHT, hd * 0.6))
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var sh := float(shrug[i]) * k
		var rc := float(reach[i]) * k
		if absf(sh) > 1e-5 or absf(rc) > 1e-5:
			CharacterSecondary._rotate_model(sk, int(_b["shoulder%d" % i]), Quaternion(Vector3.UP, rc * s) * Quaternion(Vector3.BACK, sh * s))


## Two-bone IK in skeleton space: `b0` (root) and `b1` reach so that `b2`'s
## origin is at `target`, the middle joint toward `pole`; `b2` then takes
## `end_basis` (skeleton space; null: it keeps its global orientation from
## before the solve).  `wgt` blends from the pose there was.  `twist`: the
## part of the end's twist about the middle bone's axis that the middle
## bone takes.
static func solve(sk: Skeleton3D, b0: int, b1: int, b2: int, target: Vector3, pole: Vector3, end_basis: Variant,
		wgt: float, twist: float) -> void:
	var parent := sk.get_bone_parent(b0)
	var gpp := sk.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis()
	var g0 := sk.get_bone_global_pose(b0)
	var g1 := sk.get_bone_global_pose(b1)
	var g2 := sk.get_bone_global_pose(b2)
	var h := g0.origin
	var kn := g1.origin
	var a := g2.origin
	var la := h.distance_to(kn)
	var lb := kn.distance_to(a)
	var ht := target - h
	if ht.length() < 1e-5 or la < 1e-5 or lb < 1e-5:
		return
	var d := clampf(ht.length(), absf(la - lb) + 1e-4, la + lb - 1e-4)
	var u := ht.normalized()
	var pd := pole - h
	pd -= u * pd.dot(u)
	if pd.length() < 1e-5:
		pd = (kn - h) - u * (kn - h).dot(u)
		if pd.length() < 1e-5:
			pd = Vector3.UP - u * u.y
	pd = pd.normalized()
	var ca := clampf((la * la + d * d - lb * lb) / (2.0 * la * d), -1.0, 1.0)
	var k2 := h + u * (la * ca) + pd * (la * sqrt(maxf(0.0, 1.0 - ca * ca)))
	var t2 := h + u * d
	var q1 := _arc((kn - h).normalized(), (k2 - h).normalized())
	var bb0 := Basis(q1) * g0.basis.orthonormalized()
	var mid := (Basis(q1) * (a - kn)).normalized()
	var q2 := _arc(mid, (t2 - k2).normalized())
	var bb1 := Basis(q2) * Basis(q1) * g1.basis.orthonormalized()
	var bb2: Basis = end_basis if end_basis != null else g2.basis.orthonormalized()
	if twist > 0.0:
		# the middle bone rolls part of the way toward the end's twist
		var ax := (t2 - k2).normalized()
		var x1 := bb1.x - ax * bb1.x.dot(ax)
		var x2 := bb2.x - ax * bb2.x.dot(ax)
		if x1.length() > 1e-4 and x2.length() > 1e-4:
			var ang := x1.normalized().signed_angle_to(x2.normalized(), ax)
			bb1 = Basis(ax, ang * twist) * bb1
	var l0 := (gpp.inverse() * bb0).get_rotation_quaternion()
	var l1 := (bb0.inverse() * bb1).get_rotation_quaternion()
	var l2 := (bb1.inverse() * bb2).get_rotation_quaternion()
	if wgt < 0.9995:
		l0 = sk.get_bone_pose_rotation(b0).slerp(l0, wgt)
		l1 = sk.get_bone_pose_rotation(b1).slerp(l1, wgt)
		l2 = sk.get_bone_pose_rotation(b2).slerp(l2, wgt)
	sk.set_bone_pose_rotation(b0, l0)
	sk.set_bone_pose_rotation(b1, l1)
	sk.set_bone_pose_rotation(b2, l2)


static func _arc(from: Vector3, to: Vector3) -> Quaternion:
	var c := from.cross(to)
	var dt := from.dot(to)
	if c.length() < 1e-6:
		return Quaternion() if dt > 0.0 else Quaternion(Vector3.UP, PI)
	return Quaternion(c.normalized(), atan2(c.length(), dt))
