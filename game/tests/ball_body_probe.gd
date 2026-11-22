class_name BallBodyProbe
extends RefCounted
## (build 30) Measures the basketball against the holder's body as it is
## posed, frame by frame: inside Skeleton3D.skeleton_updated (the only time
## the modified pose exists) each body part is a capsule (or the head an
## ellipsoid) from its bone's pose, sized from the runner's mesh, and the
## ball (HubBallView.last_pos) has to stay clear of every one; the palm of
## a hand the pose says is on the ball has to be on its surface.
##
## gap: metres between the ball's surface and the part's (along the line
## from the part's axis), negative = inside.

## [bone, y0, y1, rx, rz, need, ry]: a capsule along the bone (bone
## space) from y0 to y1, an elliptic section rx (bone x) by rz (bone z),
## its ends rounded over ry (the torso's are nearly flat: the hips end at
## the crotch); `need` the least gap
const PARTS := [
	["hips", 0.0, 0.03, 0.23, 0.205, 0.01, 0.06], ["spine", 0.03, 0.07, 0.235, 0.205, 0.01, 0.05],
	["chest", 0.04, 0.14, 0.22, 0.2, 0.01, 0.05],
	# (the legs: the ball can brush the trouser leg, never more)
	["thigh.L", 0.0, 0.22, 0.09, 0.09, 0.0, 0.09], ["thigh.R", 0.0, 0.22, 0.09, 0.09, 0.0, 0.09],
	["shin.L", 0.0, 0.22, 0.075, 0.075, 0.0, 0.075], ["shin.R", 0.0, 0.22, 0.075, 0.075, 0.0, 0.075],
	["foot.L", -0.06, 0.06, 0.06, 0.04, 0.005, 0.04], ["foot.R", -0.06, 0.06, 0.06, 0.04, 0.005, 0.04],
	# arms: touching is fine (the forearm along the ball), inside is not
	["upper_arm.L", 0.02, 0.17, 0.06, 0.06, -0.015, 0.06], ["upper_arm.R", 0.02, 0.17, 0.06, 0.06, -0.015, 0.06],
	["forearm.L", 0.02, 0.15, 0.045, 0.045, -0.015, 0.045], ["forearm.R", 0.02, 0.15, 0.045, 0.045, -0.015, 0.045],
]
## the head: an ellipsoid (bone space centre, radii)
const HEAD_C := Vector3(0.0, 0.287, 0.0225)
const HEAD_R := Vector3(0.354, 0.268, 0.3)
const HEAD_NEED := 0.01
## |palm - centre| - R while the hand is on the ball
const PALM_LO := -0.012
const PALM_HI := 0.03

var view: HubBallView
var v: CharacterView
var sk: Skeleton3D
var label := ""
## per label: {part: worst gap}, worst palm error, frames
var worst: Dictionary = {}
var palm_bad: Dictionary = {}
var frames: Dictionary = {}
var contact_frames: Dictionary = {}
var fails: Array = []
## the last frame's palms (stage space) and gaps
var last_gaps: Dictionary = {}
var last_bones: Dictionary = {}
var last_palm := [Vector3.ZERO, Vector3.ZERO]
var on := true
var _bi: Dictionary = {}


func _init(p_view: HubBallView, p_v: CharacterView) -> void:
	view = p_view
	v = p_v
	sk = v.skeleton
	for p in PARTS:
		_bi[p[0]] = sk.find_bone(String(p[0]))
	_bi["head"] = sk.find_bone("head")
	_bi["hand.L"] = sk.find_bone("hand.L")
	_bi["hand.R"] = sk.find_bone("hand.R")
	sk.skeleton_updated.connect(_measure)


func stop() -> void:
	on = false
	if sk.skeleton_updated.is_connected(_measure):
		sk.skeleton_updated.disconnect(_measure)


func _bone(n: String) -> Transform3D:
	return view.stage.global_transform.affine_inverse() * sk.global_transform * sk.get_bone_global_pose(int(_bi[n]))


## The gap from a ball at `c` to an elliptic capsule.
static func gap_capsule(xf: Transform3D, c: Vector3, y0: float, y1: float, rx: float, rz: float, ry: float) -> float:
	var p := xf.affine_inverse() * c
	var q := Vector3(p.x, p.y - clampf(p.y, y0, y1), p.z)
	var l := q.length()
	if l < 1e-6:
		return -HubBall.R - minf(rx, rz)
	var e := Vector3(q.x / rx, q.y / ry, q.z / rz).length()
	return l - l / e - HubBall.R


static func gap_ellipsoid(xf: Transform3D, c: Vector3, centre: Vector3, rad: Vector3) -> float:
	var q := xf.affine_inverse() * c - centre
	var l := q.length()
	if l < 1e-6:
		return -HubBall.R - rad.x
	var e := Vector3(q.x / rad.x, q.y / rad.y, q.z / rad.z).length()
	return l - l / e - HubBall.R


func _measure() -> void:
	if not on or label == "" or view.pose_key == "" and label != "follow":
		return
	var c := view.last_pos
	var w: Dictionary = worst.get(label, {})
	frames[label] = int(frames.get(label, 0)) + 1
	last_gaps = {}
	for p in PARTS:
		last_bones[p[0]] = _bone(String(p[0]))
		var g := gap_capsule(_bone(String(p[0])), c, float(p[1]), float(p[2]), float(p[3]), float(p[4]), float(p[6]))
		last_gaps[p[0]] = g
		w[p[0]] = minf(float(w.get(p[0], INF)), g)
		if g < float(p[5]) and fails.size() < 40:
			fails.append("%s: the ball is in %s (gap %.3f m, frame %d)" % [label, p[0], g, int(frames[label])])
	var hg := gap_ellipsoid(_bone("head"), c, HEAD_C, HEAD_R)
	last_gaps["head"] = hg
	w["head"] = minf(float(w.get("head", INF)), hg)
	if hg < HEAD_NEED and fails.size() < 40:
		fails.append("%s: the ball is in the head (gap %.3f m, frame %d)" % [label, hg, int(frames[label])])
	worst[label] = w
	# the palms
	var arms: Array = view.pose.get("arms", []) if view.pose_key != "" else []
	for i in 2:
		var hn := "hand.L" if i == 0 else "hand.R"
		var palm := _bone(hn) * (BallMoves.PALM[i] as Vector3)
		last_palm[i] = palm
		if arms.size() == 2 and bool((arms[i] as Dictionary)["contact"]):
			contact_frames[label] = int(contact_frames.get(label, 0)) + 1
			var e := palm.distance_to(c) - HubBall.R
			var key := "%s %s" % [label, "left" if i == 0 else "right"]
			var bad := 0.0
			if e < PALM_LO:
				bad = e - PALM_LO
			elif e > PALM_HI:
				bad = e - PALM_HI
			if absf(bad) > absf(float(palm_bad.get(key, 0.0))):
				palm_bad[key] = bad
			if bad != 0.0 and fails.size() < 40:
				fails.append("%s: the %s palm is off the ball (%.3f m from its surface, frame %d)" % [label, "left" if i == 0 else "right", e, int(frames[label])])


func report() -> String:
	var lines: Array = []
	for l in worst:
		var w: Dictionary = worst[l]
		var parts: Array = []
		for k in w:
			if float(w[k]) < 0.06:
				parts.append("%s %.3f" % [k, float(w[k])])
		lines.append("%s (%d frames, %d in hand): %s" % [l, int(frames.get(l, 0)), int(contact_frames.get(l, 0)), ", ".join(parts)])
	for k in palm_bad:
		lines.append("palm %s off by %.3f" % [k, float(palm_bad[k])])
	return "\n".join(lines)
