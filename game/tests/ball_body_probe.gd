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
##
## (build 33) For the dunk and the block it also measures, when asked: the
## head, the torso and the legs against the rim as it is bent now (and the
## head against the backboard), a ball in the hands against the rim, the
## hands on the rim while the pose has them there, and each arm against the
## runner's own (big) head; with `any_pose` it measures without the
## holder's pose too (the hang after a dunk, a jump to block).

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
## (build 33)
var rim := false
var arms_head := false
var any_pose := false
var key := ""
## worst gaps: label -> {what: gap}
var extra: Dictionary = {}
## the highest the hips and a hand got (above the runner's feet), by label
var top_hips: Dictionary = {}
var top_hand: Dictionary = {}
const RIM_NEED := 0.004
const ARM_R := 0.045


func _init(p_view: HubBallView, p_v: CharacterView) -> void:
	view = p_view
	v = p_v
	sk = v.skeleton
	for p in PARTS:
		_bi[p[0]] = sk.find_bone(String(p[0]))
	_bi["head"] = sk.find_bone("head")
	_bi["hand.L"] = sk.find_bone("hand.L")
	_bi["hand.R"] = sk.find_bone("hand.R")
	for n in ["upper_arm.L", "upper_arm.R", "forearm.L", "forearm.R"]:
		_bi[n] = sk.find_bone(n)
	for k in view.stage.chars:
		if view.stage.chars[k] == p_v:
			key = String(k)
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


func _note(what: String, g: float, need: float) -> void:
	var w: Dictionary = extra.get(label, {})
	w[what] = minf(float(w.get(what, INF)), g)
	extra[label] = w
	if g < need and fails.size() < 40:
		fails.append("%s: %s (gap %.3f m, frame %d)" % [label, what, g, int(frames.get(label, 0))])


## (build 33) The head, the body, a ball in hand and the hands against the
## rim; the head against the backboard.
func _measure_rim(c: Vector3, in_hand: bool) -> void:
	var rx: Transform3D = view.rim_xform()
	var rc := HubBall.rim_center()
	var pts: Array = []
	for i in 64:
		var th := TAU * float(i) / 64.0
		pts.append(rx * (rc + Vector3(cos(th), 0, sin(th)) * HubBall.RIM_R))
	var head := _bone("head")
	var hg := INF
	for p in pts:
		hg = minf(hg, gap_ellipsoid(head, p, HEAD_C, HEAD_R) + HubBall.R - HubBall.RIM_TUBE)
	_note("the head and the rim", hg, RIM_NEED)
	for part in PARTS:
		var n := String(part[0])
		if n.begins_with("upper_arm") or n.begins_with("forearm"):
			continue
		var g := INF
		for p in pts:
			g = minf(g, gap_capsule(_bone(n), p, float(part[1]), float(part[2]), float(part[3]), float(part[4]), float(part[6])) + HubBall.R - HubBall.RIM_TUBE)
		_note("%s and the rim" % n, g, 0.0)
	# the head and the backboard's face
	var hc := head * HEAD_C
	var fwd := Vector3(HubBall.HOOP_DIR.x, 0, HubBall.HOOP_DIR.y)
	var bc := HubBall.HOOP_BASE + HubBall.HOOP_DIR * HubBall.BOARD_OUT
	var face := Vector3(bc.x, HubBall.BOARD_Y, bc.y)
	if absf(hc.y - HubBall.BOARD_Y) < HubBall.BOARD_HALF.y + HEAD_R.y:
		var nl := head.basis.inverse() * (-fwd)
		var support := Vector3(nl.x * HEAD_R.x, nl.y * HEAD_R.y, nl.z * HEAD_R.z).length() / maxf(0.0001, (head.basis.inverse() * (-fwd)).length())
		_note("the head and the backboard", (hc - face).dot(fwd) - support, 0.005)
	if in_hand:
		var bg := INF
		for p in pts:
			bg = minf(bg, c.distance_to(p) - HubBall.R - HubBall.RIM_TUBE)
		_note("the ball in hand and the rim", bg, -0.002)
	# hands on the rim
	var ps: Dictionary = view.poses.get(key, {})
	var arms: Array = ps.get("arms", [])
	for i in 2:
		if arms.size() == 2 and String((arms[i] as Dictionary)["key"]) == "rim" and label.ends_with("hang"):
			var palm := _bone("hand.L" if i == 0 else "hand.R") * (BallMoves.PALM[i] as Vector3)
			var pg := INF
			for p in pts:
				pg = minf(pg, palm.distance_to(p) - HubBall.RIM_TUBE)
			var w: Dictionary = extra.get(label, {})
			var hk := "%s hand on the rim (worst distance)" % ("left" if i == 0 else "right")
			w[hk] = maxf(float(w.get(hk, -INF)), pg)
			extra[label] = w
			if pg > 0.06 and fails.size() < 40:
				fails.append("%s: the %s hand is off the rim (%.3f m, frame %d)" % [label, "left" if i == 0 else "right", pg, int(frames.get(label, 0))])


## (build 33) Each arm (upper arm, forearm, hand) against the runner's head.
func _measure_arms_head() -> void:
	var head := _bone("head")
	for s in [".L", ".R"]:
		var a := _bone("upper_arm" + s).origin
		var b := _bone("forearm" + s).origin
		var h := _bone("hand" + s)
		var tip := h * Vector3(0, 0.09, 0)
		var g := INF
		for k in 9:
			var u := float(k) / 8.0
			for p in [a.lerp(b, u), b.lerp(h.origin, u), h.origin.lerp(tip, u)]:
				g = minf(g, gap_ellipsoid(head, p, HEAD_C, HEAD_R) + HubBall.R - ARM_R)
		_note("the %s arm and the head" % ("left" if s == ".L" else "right"), g, -0.005)


func _measure() -> void:
	if not on or label == "" or view.pose_key == "" and label != "follow" and not any_pose:
		return
	var floor_y := view.stage.to_local(v.global_position).y
	top_hips[label] = maxf(float(top_hips.get(label, -INF)), _bone("hips").origin.y - floor_y)
	top_hand[label] = maxf(float(top_hand.get(label, -INF)), maxf(_bone("hand.L").origin.y, _bone("hand.R").origin.y) - floor_y)
	if any_pose:
		frames[label] = int(frames.get(label, 0)) + 1
		if rim:
			_measure_rim(view.last_pos, view.pose_key == key)
		if arms_head:
			_measure_arms_head()
		if view.pose_key != key and not view.poses.has(key):
			return
		frames[label] = int(frames.get(label, 0)) - 1
	elif rim or arms_head:
		if rim:
			_measure_rim(view.last_pos, true)
		if arms_head:
			_measure_arms_head()
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
	var arms: Array = (view.poses.get(key, {}) as Dictionary).get("arms", []) if key != "" else (view.pose.get("arms", []) if view.pose_key != "" else [])
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
	for l in extra:
		var w2: Dictionary = extra[l]
		var parts2: Array = []
		for k in w2:
			parts2.append("%s %.3f" % [k, float(w2[k])])
		lines.append("%s (rim / arms): %s" % [l, ", ".join(parts2)])
	for k in palm_bad:
		lines.append("palm %s off by %.3f" % [k, float(palm_bad[k])])
	return "\n".join(lines)
