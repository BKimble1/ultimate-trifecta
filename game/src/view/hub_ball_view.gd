class_name HubBallView
extends Node3D
## (build 24) The party room's basketball and its Christmas hoop, drawn.
##
## The hoop is furniture (build_hoop adds it to the room's mesh): a weighted
## base wrapped as a present, a candy-cane pole that hooks over to hold the
## backboard, a garland of tiny lights and a bow along the board's top, an
## orange rim and a white net (its own mesh: it sways when a shot drops).
##
## The ball is drawn from BallSync: loose, where its physics has it (eased
## after a guest's correction, rolling and spinning as it moves); held, in
## the holder's hands (below); winding up, the shooting form or the chest
## pass.  A shadow under it grounds it.  A made shot drops confetti over the
## shooter and the hoop.

## (build 30) The ball is 40 % bigger and the hoop half again with it; the body
## handles it: BallMoves lays out the dribble (the palm on the ball, the
## elbow and wrist working, knees bent), the moves that hand it from hand to
## hand as the holder turns (a crossover, between the legs, behind the
## back), the shooting form (gather, dip, rise, set, release, the
## follow-through held) and the pass; BallRig (a skeleton modifier on the
## holder) poses both arms, the legs and the upper body for it.  Nothing
## new goes over the network: every device lays the moves out from the
## holder's drawn heading and speed.

## the shot leaves from here, relative to the shooter (right, up, back):
## in front of the chin, up and forward of the set point, at the top of a
## little jump (BallSync.shot_start)
const SHOT_HOLD := BallMoves.REL + Vector3(0, BallMoves.REL_RISE, 0)
const FOLLOW_S := 0.62
const IK_IN_S := 0.14
const IK_OUT_S := 0.3
## a runner with the ball turns at most this fast (rad/s): the ball turns
## with them without being flung round
const BALL_TURN := 9.0
## and during a dribble move
const MOVE_TURN := 2.5

var stage: DormStage
var ball: BallSync
var reduced := false
var _ball: MeshInstance3D
var _shadow: MeshInstance3D
var _net: MeshInstance3D
var _net_t := 9.0
var _net_k := 0.0
var _rot := Basis()
var _drawn := Vector3.ZERO
var _have_drawn := false
var _handoff := Vector3.ZERO
var _phase_was := -1
var _holder_was := ""
var _wind_from := Vector3.INF     # holder space
var _wind_side := 1
var _last_at: Dictionary = {}     # key -> [position, speed]
var _hooked: BallSync
## (build 30) the holder's choreography, the ball's frame, each runner's
## rig and its arms' outputs (holder space, blended between pose families)
var moves := BallMoves.new()
var _rigs: Dictionary = {}        # key -> BallRig
var _arm_out: Dictionary = {}     # key -> [left, right] {key, w, wrist, basis (Quaternion), elbow, shrug, reach, from, bt}
var _rig_w: Dictionary = {}       # key -> overall weight
## a change of hands: the gap at the moment it happened, closed over HANDOFF_S
## on an eased curve (gentle at both ends)
var _handoff_t := 9.0
const HANDOFF_S := 0.36
## (tests / captures) the last drawn ball (stage space), the confetti count,
## the holder's pose this frame and whose it is
var last_pos := Vector3.ZERO
var confetti_bursts := 0
var pose: Dictionary = {}
var pose_key := ""


static func _mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/shaders/dorm.gdshader")
	return m


func build() -> void:
	name = "HubBall"
	# (build 30) after the runners have moved and turned this frame
	# (CharacterView._process): the hands are placed for the body as drawn
	process_priority = 100
	_ball = MeshInstance3D.new()
	_ball.name = "Ball"
	var sm := SphereMesh.new()
	sm.radius = HubBall.R
	sm.height = HubBall.R * 2.0
	sm.radial_segments = 32
	sm.rings = 16
	_ball.mesh = sm
	var bm := ShaderMaterial.new()
	bm.shader = preload("res://assets/shaders/ball.gdshader")
	_ball.material_override = bm
	_ball.visible = false
	add_child(_ball)
	# a soft round shadow on the planks
	_shadow = MeshInstance3D.new()
	_shadow.name = "BallShadow"
	var pm := PlaneMesh.new()
	pm.size = Vector2(0.36, 0.36)
	_shadow.mesh = pm
	var sh := ShaderMaterial.new()
	sh.shader = _shadow_shader()
	_shadow.material_override = sh
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.visible = false
	add_child(_shadow)
	# the net (it sways when a shot drops through)
	_net = MeshInstance3D.new()
	_net.name = "Net"
	_net.mesh = _net_mesh()
	var nm := StandardMaterial3D.new()
	nm.albedo_color = Color(0.96, 0.96, 0.98)
	nm.roughness = 0.9
	nm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_net.material_override = nm
	_net.position = HubBall.rim_center()
	add_child(_net)


static func _shadow_shader() -> Shader:
	var s := Shader.new()
	s.code = """shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform float alpha = 0.45;
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	ALBEDO = vec3(0.06, 0.04, 0.03);
	ALPHA = alpha * (1.0 - smoothstep(0.35, 1.0, d));
}
"""
	return s


# ---------------------------------------------------------------------------
# The hoop (furniture: added to the room's mesh)
# ---------------------------------------------------------------------------
const RED := Color("d22b3b", 0.6)
const WHITE := Color("f6f1ea", 0.6)


## A tube along `path` (smooth normals); col_fn(s, theta) gives each quad's
## colour (s: distance along the path).
static func _tube(k: MeshKit, path: PackedVector3Array, r: float, seg: int, col_fn: Callable, emis: float = 0.0) -> void:
	var s := 0.0
	var rings: Array = []
	var ss: Array = []
	var ref := Vector3.UP
	for i in path.size():
		var t := (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		if absf(t.dot(ref)) > 0.95:
			ref = Vector3.RIGHT if absf(t.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
		var a := t.cross(ref).normalized()
		var b := t.cross(a).normalized()
		ref = b   # parallel-transport-ish: no twist round the bends
		var ring: Array = []
		for j in seg + 1:
			var th := TAU * float(j) / float(seg)
			var n := a * cos(th) + b * sin(th)
			ring.append([path[i] + n * r, n])
		rings.append(ring)
		if i > 0:
			s += path[i].distance_to(path[i - 1])
		ss.append(s)
	for i in range(path.size() - 1):
		for j in seg:
			var p00: Array = rings[i][j]
			var p10: Array = rings[i + 1][j]
			var p11: Array = rings[i + 1][j + 1]
			var p01: Array = rings[i][j + 1]
			var col: Color = col_fn.call((float(ss[i]) + float(ss[i + 1])) * 0.5, TAU * (float(j) + 0.5) / float(seg))
			_tri_out(k, p00, p10, p11, col, emis)
			_tri_out(k, p00, p11, p01, col, emis)


## A smooth triangle wound to face out along its normals (MeshKit fronts
## are clockwise).
static func _tri_out(k: MeshKit, a: Array, b: Array, c: Array, col: Color, emis: float) -> void:
	var pa: Vector3 = a[0]
	var pb: Vector3 = b[0]
	var pc: Vector3 = c[0]
	var nsum: Vector3 = (a[1] as Vector3) + (b[1] as Vector3) + (c[1] as Vector3)
	if (pb - pa).cross(pc - pa).dot(nsum) > 0.0:
		k.tri_n(pa, pc, pb, a[1], c[1], b[1], col, col, col, emis)
	else:
		k.tri_n(pa, pb, pc, a[1], b[1], c[1], col, col, col, emis)


static func build_hoop(k: MeshKit) -> void:
	var base2 := HubBall.HOOP_BASE
	var base := Vector3(base2.x, 0.0, base2.y)
	var d2 := HubBall.HOOP_DIR
	var fwd := Vector3(d2.x, 0.0, d2.y)
	var side := Vector3(-d2.y, 0.0, d2.x)
	var yaw := HubBall.hoop_yaw()
	var fabric := 0.8
	# --- the weighted base: a present (red paper, gold ribbon and bow)
	var pres := Color("c7353e", fabric)
	var gold := Color("f2c14e", 0.6)
	k.ellipse_disc(base + Vector3(0, 0.009, 0), 0.43, 0.43, Color("1a120c"), 20)
	k.chamfer_box(base + Vector3(0, HubBall.BASE_H * 0.5, 0), Vector3(0.6, HubBall.BASE_H, 0.6), pres, 0.03, yaw)
	k.box(base + Vector3(0, HubBall.BASE_H * 0.5, 0), Vector3(0.108, HubBall.BASE_H + 0.006, 0.607), gold, yaw)
	k.box(base + Vector3(0, HubBall.BASE_H * 0.5, 0), Vector3(0.607, HubBall.BASE_H + 0.006, 0.108), gold, yaw)
	var bow := base + Vector3(0, HubBall.BASE_H + 0.03, 0) + side * 0.12 + fwd * 0.12
	k.soft_blob(bow + side * 0.05, Vector3(0.06, 0.035, 0.035), gold, 4, 10)
	k.soft_blob(bow - side * 0.05, Vector3(0.06, 0.035, 0.035), gold, 4, 10)
	k.soft_blob(bow, Vector3(0.025, 0.025, 0.025), gold.darkened(0.1), 4, 8)
	# --- the candy-cane pole, hooking over to the top of the backboard
	var top := HubBall.POLE_TOP
	var hook_r := (HubBall.BOARD_OUT - HubBall.BOARD_HALF.z) * 0.5
	var board_top := HubBall.BOARD_Y + HubBall.BOARD_HALF.y
	var path := PackedVector3Array()
	var n_up := 24
	for i in n_up + 1:
		path.append(base + Vector3(0, lerpf(HubBall.BASE_H - 0.02, top, float(i) / float(n_up)), 0))
	var hc := base + fwd * hook_r + Vector3(0, top, 0)
	for i in range(1, 15):
		var th := PI - PI * float(i) / 14.0
		path.append(hc + fwd * (hook_r * cos(th)) + Vector3(0, hook_r * sin(th), 0))
	var down_n := 4
	for i in range(1, down_n + 1):
		path.append(base + fwd * (hook_r * 2.0) + Vector3(0, lerpf(top, board_top - 0.01, float(i) / float(down_n)), 0))
	var stripes := func(s: float, th: float) -> Color:
		# helical stripes, like a real candy cane
		return RED if fposmod(s * 7.5 + th / TAU, 1.0) < 0.5 else WHITE
	_tube(k, path, HubBall.POLE_R, 16, stripes)
	# a sprig of holly where the cane bends
	var holly := hc + Vector3(0, hook_r + 0.015, 0)
	var leaf := Color("2b7a46", fabric)
	k.soft_blob(holly + side * 0.045, Vector3(0.05, 0.012, 0.025), leaf, 3, 8)
	k.soft_blob(holly - side * 0.045, Vector3(0.05, 0.012, 0.025), leaf.darkened(0.08), 3, 8)
	for bi in 3:
		var bo := Vector3(cos(float(bi) * 2.1), 0.0, sin(float(bi) * 2.1)) * 0.014
		k.blob(holly + bo + Vector3(0, 0.012, 0), Vector3(0.014, 0.014, 0.014), Color("e02a35"), 3, 7)
	# --- the backboard: white, a red frame and the red square over the rim,
	# frosted along the top, on a bracket from the pole
	var bc := base + fwd * (HubBall.BOARD_OUT - HubBall.BOARD_HALF.z) + Vector3(0, HubBall.BOARD_Y, 0)
	var bh := HubBall.BOARD_HALF
	k.chamfer_box(bc, bh * 2.0, Color("f4f6fb", 0.6), 0.012, yaw)
	var face := bc + fwd * (bh.z + 0.002)
	var fr := 0.034
	k.box(face + Vector3(0, bh.y - fr * 0.5, 0), Vector3(bh.x * 2.0, fr, 0.006), RED, yaw)
	k.box(face - Vector3(0, bh.y - fr * 0.5, 0), Vector3(bh.x * 2.0, fr, 0.006), RED, yaw)
	k.box(face + side * (bh.x - fr * 0.5), Vector3(fr, bh.y * 2.0, 0.006), RED, yaw)
	k.box(face - side * (bh.x - fr * 0.5), Vector3(fr, bh.y * 2.0, 0.006), RED, yaw)
	# (build 30) the shooter's square, half again bigger with the rim
	var sq := face + Vector3(0, HubBall.RIM_Y + 0.153 - HubBall.BOARD_Y, 0)
	var sw := 0.234
	var shh := 0.162
	var st := 0.024
	k.box(sq + Vector3(0, shh, 0), Vector3(sw * 2.0, st, 0.008), RED, yaw)
	k.box(sq - Vector3(0, shh, 0), Vector3(sw * 2.0, st, 0.008), RED, yaw)
	k.box(sq + side * sw, Vector3(st, shh * 2.0, 0.008), RED, yaw)
	k.box(sq - side * sw, Vector3(st, shh * 2.0, 0.008), RED, yaw)
	# snow along the top
	for i in 13:
		var u := (float(i) / 12.0 - 0.5) * 2.0
		k.soft_blob(bc + side * (u * (bh.x - 0.04)) + Vector3(0, bh.y + 0.01, 0), Vector3(0.065, 0.022 + 0.007 * float(i % 2), 0.034), Color("fbfdff", 0.6), 3, 8)
	# the bracket behind the board and the rim's mount
	k.box(base + fwd * 0.11 + Vector3(0, HubBall.RIM_Y + 0.06, 0), Vector3(0.048, 0.048, 0.2), Color("c9ccd4", 0.6), yaw)
	var rc := HubBall.rim_center()
	k.box(Vector3(rc.x, rc.y - 0.014, rc.z) - fwd * (HubBall.RIM_R + 0.035), Vector3(0.12, 0.03, 0.09), Color("e8552b", 0.6), yaw)
	# --- the rim
	var ring := PackedVector3Array()
	for i in 65:
		var th := TAU * float(i) / 64.0
		ring.append(rc + Vector3(cos(th), 0, sin(th)) * HubBall.RIM_R)
	_tube(k, ring, HubBall.RIM_TUBE, 12, func(_s: float, _t: float) -> Color: return Color("e8552b", 0.6))
	# --- a garland of tiny lights over the frame and down both sides
	var gl := PackedVector3Array()
	var gcorner := bc + fwd * (bh.z + 0.012)
	for i in 29:
		var u2 := float(i) / 28.0
		var sx := lerpf(-bh.x, bh.x, u2)
		gl.append(gcorner + side * sx + Vector3(0, bh.y - 0.012 - 0.05 * sin(PI * fposmod(u2 * 3.0, 1.0)), 0))
	var green := Color("2e7d4f", fabric)
	for i in gl.size():
		k.soft_blob(gl[i], Vector3(0.026, 0.024, 0.019), green.darkened(0.08 * float(i % 2)), 3, 7)
		if i % 2 == 0:
			var bulb: Color = HolidayDecor.BULB_COLS[(i / 2) % HolidayDecor.BULB_COLS.size()]
			k.blob(gl[i] + fwd * 0.019 - Vector3(0, 0.014, 0), Vector3(0.011, 0.014, 0.011), bulb, 2, 6, 2.6)
	# a red bow on the top corner
	var bw := gcorner + side * (bh.x - 0.03) + Vector3(0, bh.y + 0.006, 0)
	k.soft_blob(bw + side * 0.046 + Vector3(0, 0.02, 0), Vector3(0.052, 0.034, 0.018), RED, 4, 8)
	k.soft_blob(bw - side * 0.046 + Vector3(0, 0.02, 0), Vector3(0.052, 0.034, 0.018), RED, 4, 8)
	k.soft_blob(bw + Vector3(0, 0.016, 0), Vector3(0.021, 0.021, 0.018), Color("b1202f", 0.6), 3, 7)
	k.box(bw + side * 0.026 - Vector3(0, 0.046, 0), Vector3(0.016, 0.09, 0.006), RED, yaw)
	k.box(bw - side * 0.026 - Vector3(0, 0.052, 0), Vector3(0.016, 0.104, 0.006), RED, yaw)


## The net (rim-centred): a diamond mesh of strings narrowing to the bottom.
static func _net_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 16
	var levels := 5
	var pts: Array = []
	for l in levels + 1:
		var row: Array = []
		var k := float(l) / float(levels)
		var r := lerpf(HubBall.RIM_R - 0.004, HubBall.NET_BOTTOM_R, k)
		var y := -HubBall.NET_DEPTH * k
		for j in n:
			var th := TAU * (float(j) + 0.5 * float(l % 2)) / float(n)
			row.append(Vector3(cos(th) * r, y, sin(th) * r))
		pts.append(row)
	var w := 0.0068
	var seg := func(a: Vector3, b: Vector3) -> void:
		var d := b - a
		var out := Vector3(a.x + b.x, 0, a.z + b.z).normalized()
		var sd := d.cross(out).normalized() * w
		# a thin ribbon, both ways out (two-sided material)
		st.add_vertex(a - sd)
		st.add_vertex(b - sd)
		st.add_vertex(b + sd)
		st.add_vertex(a - sd)
		st.add_vertex(b + sd)
		st.add_vertex(a + sd)
	for l in levels:
		for j in n:
			var a: Vector3 = pts[l][j]
			var j2 := j if l % 2 == 0 else (j + 1) % n
			var j1 := (j - 1 + n) % n if l % 2 == 0 else j
			seg.call(a, pts[l + 1][j1])
			seg.call(a, pts[l + 1][j2])
	st.generate_normals()
	return st.commit()


# ---------------------------------------------------------------------------
func _key_of(slot: int) -> String:
	if ball == null or slot < 0 or slot > 7:
		return ""
	var e: Variant = ball.session.roster[slot]
	return "" if e == null else String(e["uid"])


func _hook() -> void:
	if ball == _hooked:
		return
	if _hooked != null:
		if _hooked.sound.is_connected(_on_sound):
			_hooked.sound.disconnect(_on_sound)
		if _hooked.made.is_connected(_on_made):
			_hooked.made.disconnect(_on_made)
	_hooked = ball
	_phase_was = -1
	_have_drawn = false
	if ball != null:
		ball.sound.connect(_on_sound)
		ball.made.connect(_on_made)


func _process(delta: float) -> void:
	_hook()
	_net_t += delta
	_animate_net()
	var live := ball != null and is_instance_valid(ball.session) and ball.spawned and ball.in_room() and stage != null
	if not live:
		_ball.visible = false
		_shadow.visible = false
		_have_drawn = false
		_phase_was = -1
		pose = {}
		pose_key = ""
		_pose_rigs(delta, {})
		return
	var key := _key_of(ball.holder)
	var v: CharacterView = stage.chars.get(key) if key != "" else null
	if v != null and (not is_instance_valid(v) or not v.visible):
		v = null
	var p: Vector3
	var want: Dictionary = {}
	var phase := ball.phase
	var free := phase == BallSync.Phase.FREE or v == null
	var was_free := _phase_was == BallSync.Phase.FREE or _phase_was < 0
	if not free and (key != _holder_was or was_free):
		# (build 25) picked up off the floor: the dribble starts at the
		# bottom of a bounce (where the ball is) and rises into the hand;
		# caught in the air: it starts at the hand
		moves.reset(_have_drawn and _drawn.y < 0.3)
		moves.side = 1
	if phase != _phase_was and not free:
		_wind_from = _to_holder(v, _drawn) if _have_drawn else Vector3.INF
		_wind_side = moves.side
		if phase != BallSync.Phase.HELD:
			moves.cancel()
	_holder_was = "" if free else key
	pose = {}
	pose_key = ""
	if free:
		p = ball.sim.pos + ball.err
		var w := ball.sim.spin
		if w.length() > 0.01:
			_rot = Basis(w.normalized(), w.length() * delta) * _rot
	else:
		p = _held(v, key, phase, delta, want)
	# (build 25) every change of hands (a pick-up, a catch, a release) glides
	# from where the ball was drawn instead of jumping
	if _have_drawn and _phase_was >= 0 and free != was_free:
		_handoff = _drawn - p + _handoff_now()
		_handoff_t = 0.0
	_handoff_t += delta
	p += _handoff_now()
	_phase_was = phase
	_drawn = p
	_have_drawn = true
	last_pos = p
	_rot = _rot.orthonormalized()
	_ball.visible = true
	_ball.transform = Transform3D(_rot, p)
	var h := maxf(0.0, p.y - HubBall.R)
	_shadow.visible = h < 2.0
	_shadow.position = Vector3(p.x, 0.006, p.z)
	_shadow.scale = Vector3.ONE * (1.0 + h * 0.5)
	(_shadow.material_override as ShaderMaterial).set_shader_parameter("alpha", 0.5 * (1.0 - clampf(h / 2.0, 0.0, 1.0)))
	_follow_through(want)
	_pose_rigs(delta, want)


## (build 30) Just after a shot leaves the hand: the shooting arm stays up
## and out, the wrist flicked toward the rim, the guide hand up, the jump
## lands; then both relax.
func _follow_through(want: Dictionary) -> void:
	if ball.phase != BallSync.Phase.FREE or not ball.released_shot or ball.phase_t > FOLLOW_S:
		return
	var key := _key_of(ball.sim.shooter)
	if key == "" or want.has(key):
		return
	var v: CharacterView = stage.chars.get(key)
	if v == null or not is_instance_valid(v) or not v.visible:
		return
	var f := BallMoves.follow(ball.phase_t)
	if ball.phase_t > FOLLOW_S - 0.2:
		for a in f["arms"]:
			(a as Dictionary)["key"] = "relax"
	want[key] = f


func _handoff_now() -> Vector3:
	if _handoff_t >= HANDOFF_S:
		return Vector3.ZERO
	var u := clampf(_handoff_t / HANDOFF_S, 0.0, 1.0)
	return _handoff * (1.0 - u * u * u * (u * (u * 6.0 - 15.0) + 10.0))


## The holder's frame (stage space): where they stand, the way they face.
func _frame(v: CharacterView) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, v.rotation.y), stage.to_local(v.global_position) * Vector3(1, 0, 1))


func _to_holder(v: CharacterView, at: Vector3) -> Vector3:
	return _frame(v).affine_inverse() * at


## Where the ball is in a holder's hands this frame (stage space); the
## holder's pose goes into `want`.
func _held(v: CharacterView, key: String, phase: int, delta: float, want: Dictionary) -> Vector3:
	var at := stage.to_local(v.global_position)
	var prev: Array = _last_at.get(key, [at, 0.0])
	var sp := (Vector2(at.x, at.z) - Vector2((prev[0] as Vector3).x, (prev[0] as Vector3).z)).length() / maxf(delta, 0.001)
	if sp > HubRoom.WALK_SPEED * 2.5:
		sp = float(prev[1])   # a jump (a correction): not a sprint
	var raw := minf(sp, HubRoom.WALK_SPEED * 1.2)
	sp = lerpf(float(prev[1]), raw, 1.0 - exp(-delta * 5.0))
	_last_at[key] = [at, sp]
	var k := clampf(sp / HubRoom.WALK_SPEED, 0.0, 1.0)
	# (a dribbler turns at most BALL_TURN: the ball and the arms with them)
	# (and slower in a dribble move: it commits them)
	v.max_turn = MOVE_TURN if moves.move != "" else BALL_TURN
	var yaw := v.rotation.y
	var ps: Dictionary
	match phase:
		BallSync.Phase.HELD:
			var kind := moves.detect(delta, yaw, raw)
			ps = moves.dribble(delta, k, kind)
			if moves.bounced:
				var fr := _frame(v)
				var spot := fr * Vector3((ps["ball"] as Vector3).x, HubBall.R, (ps["ball"] as Vector3).z)
				_play("ball_bounce", spot, -14.0 + 4.0 * k, randf_range(0.96, 1.04))
			_rot = Basis(_frame(v).basis.x, -delta * 8.0) * _rot
		BallSync.Phase.SHOT:
			var t := clampf(ball.phase_t / BallSync.WINDUP_SHOT, 0.0, 1.0)
			ps = BallMoves.shot(t, _wind_from if _wind_from != Vector3.INF else BallMoves.POCKET, _wind_side)
		_:
			var t2 := clampf(ball.phase_t / BallSync.WINDUP_PASS, 0.0, 1.0)
			ps = BallMoves.pass_pose(t2, _wind_from if _wind_from != Vector3.INF else BallMoves.PASS_AT)
	want[key] = ps
	pose = ps
	pose_key = key
	return _frame(v) * (ps["ball"] as Vector3)


# ---------------------------------------------------------------------------
# The body (BallRig: added to a runner's skeleton the first time they hold
# the ball, faded in and out)
# ---------------------------------------------------------------------------
func _rig_for(v: CharacterView, key: String) -> BallRig:
	var rig: BallRig = _rigs.get(key)
	var sk := v.skeleton
	if rig != null and is_instance_valid(rig) and rig.get_parent() == sk:
		return rig
	if rig != null and is_instance_valid(rig):
		rig.queue_free()
	if sk == null:
		return null
	rig = BallRig.new()
	rig.name = "BallRig"
	sk.add_child(rig)
	_rigs[key] = rig
	_arm_out.erase(key)
	return rig


func _pose_rigs(delta: float, want: Dictionary) -> void:
	for key in want:
		var v: CharacterView = stage.chars.get(key) if stage != null else null
		if v != null and is_instance_valid(v):
			_rig_for(v, key)
	for key in _rigs.keys():
		var rig: BallRig = _rigs[key]
		var v2: Variant = stage.chars.get(key) if stage != null else null
		if v2 == null or not is_instance_valid(v2) or not is_instance_valid(rig) or rig.get_parent() != (v2 as CharacterView).skeleton:
			if is_instance_valid(rig):
				rig.queue_free()
			_rigs.erase(key)
			_arm_out.erase(key)
			_rig_w.erase(key)
			continue
		var cv := v2 as CharacterView
		if key != pose_key:
			cv.max_turn = INF
		var ps: Dictionary = want.get(key, {})
		var on := not ps.is_empty()
		var w := move_toward(float(_rig_w.get(key, 0.0)), 1.0 if on else 0.0, delta / (IK_IN_S if on else IK_OUT_S))
		_rig_w[key] = w
		rig.w = w * w * (3.0 - 2.0 * w)
		rig.active = rig.w > 0.0005
		if not on:
			continue
		var gx := stage.global_transform * _frame(cv)
		rig.crouch = float(ps["crouch"])
		rig.rise = float(ps["rise"])
		rig.lean = float(ps["lean"])
		rig.turn = float(ps["turn"])
		rig.look_up = float(ps["look_up"])
		rig.stance_w = float(ps["stance_w"])
		# (the stance is in the body's own frame: the skeleton's)
		rig.stance = ps["stance"]
		var outs: Array = _arm_out.get(key, [{}, {}])
		for i in 2:
			var a: Dictionary = ps["arms"][i]
			var o: Dictionary = _blend_arm(outs[i], a, delta)
			outs[i] = o
			rig.arm_w[i] = float(o["w"])
			rig.wrist[i] = gx * (o["wrist"] as Vector3)
			rig.hand_basis[i] = gx.basis * Basis(o["basis"] as Quaternion)
			rig.elbow[i] = gx * (o["elbow"] as Vector3)
			rig.shrug[i] = float(o["shrug"])
			rig.reach[i] = float(o["reach"])
		_arm_out[key] = outs


## One arm's output this frame: the pose asked for, or (just after a
## change of pose family) a blend to it from where the arm was.
func _blend_arm(o: Dictionary, a: Dictionary, delta: float) -> Dictionary:
	var tgt := {"key": a["key"], "w": a["w"], "wrist": a["wrist"], "basis": (a["basis"] as Basis).get_rotation_quaternion(),
		"elbow": a["elbow"], "shrug": a["shrug"], "reach": a["reach"]}
	if String(a["key"]) == "relax":
		# back to the animation: the weight fades where the arm was
		if o.is_empty():
			tgt["w"] = 0.0
			return tgt
		var r := o.duplicate()
		r["key"] = "relax"
		r["w"] = move_toward(float(o["w"]), 0.0, delta / IK_OUT_S)
		r.erase("from")
		return r
	if o.is_empty() or String(o["key"]) == "relax" or float(o["w"]) < 0.02:
		# from the animation: in where it is going, the weight easing up
		tgt["w"] = minf(float(a["w"]), (0.0 if o.is_empty() else float(o["w"])) + delta / IK_IN_S)
		return tgt
	if String(o["key"]) != String(a["key"]):
		tgt["from"] = {"wrist": o["wrist"], "basis": o["basis"], "elbow": o["elbow"], "shrug": o["shrug"], "reach": o["reach"], "w": o["w"]}
		tgt["bt"] = 0.0
		o = tgt.duplicate()
	if not o.has("from"):
		return tgt
	var bt := float(o.get("bt", 0.0)) + delta
	if bt >= BallMoves.ARM_BLEND_S:
		return tgt
	var f: Dictionary = o["from"]
	var e := BallMoves.ease3(bt / BallMoves.ARM_BLEND_S)
	var r2 := tgt.duplicate()
	r2["from"] = f
	r2["bt"] = bt
	r2["wrist"] = (f["wrist"] as Vector3).lerp(tgt["wrist"], e)
	r2["basis"] = (f["basis"] as Quaternion).slerp(tgt["basis"], e)
	r2["elbow"] = (f["elbow"] as Vector3).lerp(tgt["elbow"], e)
	r2["shrug"] = lerpf(float(f["shrug"]), float(tgt["shrug"]), e)
	r2["reach"] = lerpf(float(f["reach"]), float(tgt["reach"]), e)
	r2["w"] = lerpf(float(f["w"]), float(tgt["w"]), e)
	return r2


# ---------------------------------------------------------------------------
# Sounds, the net and confetti
# ---------------------------------------------------------------------------
func _play(sfx: String, at: Vector3, db: float, pitch: float = 1.0) -> void:
	if stage == null or stage.cam == null:
		return
	var g := stage.to_global(at)
	if stage.cam.global_position.distance_to(g) > 16.0:
		return
	Sfx.play(sfx, g, db, pitch)


func _on_sound(kind: int, at: Vector3, strength: float) -> void:
	var loud := clampf(strength / 5.0, 0.0, 1.0)
	match kind:
		HubBall.Kind.FLOOR:
			_play("ball_bounce", at, lerpf(-20.0, -5.0, loud), randf_range(0.95, 1.05))
		HubBall.Kind.RIM:
			_play("ball_rim", at, lerpf(-16.0, -4.0, loud), randf_range(0.96, 1.04))
			_net_k = maxf(_net_k, 0.35)
			if _net_t > 0.2:
				_net_t = 0.0
		HubBall.Kind.BOARD:
			_play("ball_board", at, lerpf(-16.0, -5.0, loud), randf_range(0.95, 1.05))
		HubBall.Kind.WOOD, HubBall.Kind.WALL, HubBall.Kind.POLE:
			_play("ball_bounce", at, lerpf(-22.0, -9.0, loud), randf_range(1.1, 1.25))
		HubBall.Kind.SOFT, HubBall.Kind.PLAYER:
			_play("ball_thud", at, lerpf(-22.0, -10.0, loud), randf_range(0.9, 1.1))
		HubBall.Kind.NET:
			pass   # (build 25) no swish sound


func _on_made(slot: int, _swish: bool) -> void:
	var rc := HubBall.rim_center()
	_net_t = 0.0
	_net_k = 1.0
	# (build 25) no swish: a soft chime for the basket
	_play("reward", rc, -8.0)
	# over the shooter and the hoop
	var from := Vector3(rc.x, 0, rc.z) + Vector3(HubBall.HOOP_DIR.x, 0, HubBall.HOOP_DIR.y) * 1.8
	var sv: Variant = stage.chars.get(_key_of(slot)) if stage != null else null
	if sv != null and is_instance_valid(sv):
		from = stage.to_local((sv as Node3D).global_position)
	confetti(Vector3(rc.x, 0, rc.z), from)


## Confetti from above, spread over the line between `a` and `b` (stage
## space, floor level), plus a little pop of it out of the rim.
func confetti(a: Vector3, b: Vector3) -> void:
	confetti_bursts += 1
	var mid := (a + b) * 0.5
	var span := Vector2(absf(a.x - b.x), absf(a.z - b.z)) * 0.5
	var rain := _confetti_node(110 if reduced else 220, 3.8)
	rain.position = Vector3(mid.x, 2.7, mid.z)
	rain.emission_box_extents = Vector3(maxf(span.x, 0.9) + 0.4, 0.2, maxf(span.y, 0.8) + 0.4)
	rain.direction = Vector3.UP
	rain.spread = 70.0
	rain.initial_velocity_min = 0.3
	rain.initial_velocity_max = 1.4
	add_child(rain)
	rain.emitting = true
	var pop := _confetti_node(36 if reduced else 70, 2.4)
	pop.position = HubBall.rim_center() + Vector3(0, 0.05, 0)
	pop.emission_box_extents = Vector3(0.1, 0.02, 0.1)
	pop.direction = Vector3.UP
	pop.spread = 55.0
	pop.initial_velocity_min = 1.6
	pop.initial_velocity_max = 3.0
	pop.gravity = Vector3(0, -2.6, 0)
	add_child(pop)
	pop.emitting = true


static func _confetti_node(amount: int, life: float) -> CPUParticles3D:
	var cp := CPUParticles3D.new()
	cp.name = "Confetti"
	cp.amount = amount
	cp.lifetime = life
	cp.one_shot = true
	cp.explosiveness = 0.9
	cp.randomness = 0.6
	cp.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	cp.gravity = Vector3(0, -1.25, 0)
	cp.damping_min = 0.6
	cp.damping_max = 1.4
	cp.angle_min = 0.0
	cp.angle_max = 360.0
	cp.angular_velocity_min = -520.0
	cp.angular_velocity_max = 520.0
	cp.scale_amount_min = 0.6
	cp.scale_amount_max = 1.25
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
	g.colors = PackedColorArray([Color("e8434f"), Color("f2c14e"), Color("2fa36b"), Color("f6f1ea"), Color("4fa3e8"), Color("ff7aa2")])
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	cp.color_initial_ramp = g
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.8, 1.0])
	fade.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	cp.color_ramp = fade
	var q := QuadMesh.new()
	q.size = Vector2(0.045, 0.026)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	cp.mesh = q
	cp.finished.connect(cp.queue_free)
	return cp


func _animate_net() -> void:
	if _net == null:
		return
	if _net_t > 2.5:
		_net.scale = Vector3.ONE
		_net.rotation = Vector3.ZERO
		_net_k = 0.0
		return
	# (build 25) a soft, slow sway: the net stretches down as the ball drops
	# through and settles back (no buzzing)
	var t := _net_t
	var amp := _net_k * exp(-t * 3.2)
	var stretch := sin(t * 9.0) * amp
	_net.scale = Vector3(1.0 - 0.06 * stretch, 1.0 + 0.18 * stretch, 1.0 - 0.06 * stretch)
	_net.rotation = Vector3(0.06 * amp * sin(t * 6.0), 0.0, 0.06 * amp * cos(t * 5.0))
