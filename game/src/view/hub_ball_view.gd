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
## after a guest's correction, rolling and spinning as it moves); held, at
## the holder's right hand, dribbled at the pace they walk with their arm
## pumping it (a two-bone IK on the arm); winding up, lifted over the head
## for a shot (both hands) or to the chest for a pass.  A shadow under it
## grounds it.  A made shot drops confetti over the shooter and the hoop.

## (build 25) the ball meets the hand with the elbow bent (its top at
## ~0.61 m), so the arm visibly pushes it down and rides it back up
const DRIBBLE_TOP := 0.52        # ball centre at the hand (a ~1 m runner)
const HAND_LOW := 0.535          # the lowest the hand reaches (arm straight)
const HAND_HIGH := 0.64
const DRIBBLE_SLOW_S := 0.46     # a bounce standing still
const DRIBBLE_FAST_S := 0.34     # and at full walking speed
## (build 25) the shooting form, relative to the shooter (right, up, back):
## the gather at the chest, then the set point up over the right eye (where
## the ball is released; BallSync.shot_start), then the follow-through
const SHOT_POCKET := Vector3(0.07, 0.64, -0.17)
const SHOT_HOLD := Vector3(0.13, 1.1, -0.06)
const FOLLOW_S := 0.45
const PASS_HOLD := Vector3(0.0, 0.56, 0.2)      # at the chest (right, up, forward)
const IK_IN_S := 0.12
const IK_OUT_S := 0.28

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
var _dribble := 0.0
var _wind_from := Vector3.ZERO
var _last_at: Dictionary = {}     # key -> [position, speed]
var _iks: Dictionary = {}         # key -> {r, l, tr, tl, pr, pl, wr, wl}
var _hooked: BallSync
## (build 25) smoothing: the dribble's offset from the runner (turns ease),
## its pace, and each IK target
var _off := Vector3.INF
var _pace := 0.0
var _ik_at: Dictionary = {}       # "key|side" -> Vector3 (stage space)
## a change of hands: the gap at the moment it happened, closed over HANDOFF_S
## on an eased curve (gentle at both ends)
var _handoff_t := 9.0
const HANDOFF_S := 0.36
## (tests / captures) the last drawn ball, stage space, and the confetti count
var last_pos := Vector3.ZERO
var confetti_bursts := 0


static func _mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/shaders/dorm.gdshader")
	return m


func build() -> void:
	name = "HubBall"
	_ball = MeshInstance3D.new()
	_ball.name = "Ball"
	var sm := SphereMesh.new()
	sm.radius = HubBall.R
	sm.height = HubBall.R * 2.0
	sm.radial_segments = 24
	sm.rings = 12
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
	pm.size = Vector2(0.26, 0.26)
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
	var fr := 0.026
	k.box(face + Vector3(0, bh.y - fr * 0.5, 0), Vector3(bh.x * 2.0, fr, 0.006), RED, yaw)
	k.box(face - Vector3(0, bh.y - fr * 0.5, 0), Vector3(bh.x * 2.0, fr, 0.006), RED, yaw)
	k.box(face + side * (bh.x - fr * 0.5), Vector3(fr, bh.y * 2.0, 0.006), RED, yaw)
	k.box(face - side * (bh.x - fr * 0.5), Vector3(fr, bh.y * 2.0, 0.006), RED, yaw)
	var sq := face + Vector3(0, HubBall.RIM_Y + 0.102 - HubBall.BOARD_Y, 0)
	var sw := 0.156
	var shh := 0.108
	var st := 0.017
	k.box(sq + Vector3(0, shh, 0), Vector3(sw * 2.0, st, 0.008), RED, yaw)
	k.box(sq - Vector3(0, shh, 0), Vector3(sw * 2.0, st, 0.008), RED, yaw)
	k.box(sq + side * sw, Vector3(st, shh * 2.0, 0.008), RED, yaw)
	k.box(sq - side * sw, Vector3(st, shh * 2.0, 0.008), RED, yaw)
	# snow along the top
	for i in 9:
		var u := (float(i) / 8.0 - 0.5) * 2.0
		k.soft_blob(bc + side * (u * (bh.x - 0.03)) + Vector3(0, bh.y + 0.008, 0), Vector3(0.055, 0.018 + 0.006 * float(i % 2), 0.028), Color("fbfdff", 0.6), 3, 8)
	# the bracket behind the board and the rim's mount
	k.box(base + fwd * 0.11 + Vector3(0, HubBall.RIM_Y + 0.06, 0), Vector3(0.048, 0.048, 0.2), Color("c9ccd4", 0.6), yaw)
	var rc := HubBall.rim_center()
	k.box(Vector3(rc.x, rc.y - 0.012, rc.z) - fwd * (HubBall.RIM_R + 0.03), Vector3(0.084, 0.024, 0.084), Color("e8552b", 0.6), yaw)
	# --- the rim
	var ring := PackedVector3Array()
	for i in 49:
		var th := TAU * float(i) / 48.0
		ring.append(rc + Vector3(cos(th), 0, sin(th)) * HubBall.RIM_R)
	_tube(k, ring, HubBall.RIM_TUBE, 12, func(_s: float, _t: float) -> Color: return Color("e8552b", 0.6))
	# --- a garland of tiny lights over the frame and down both sides
	var gl := PackedVector3Array()
	var gcorner := bc + fwd * (bh.z + 0.012)
	for i in 21:
		var u2 := float(i) / 20.0
		var sx := lerpf(-bh.x, bh.x, u2)
		gl.append(gcorner + side * sx + Vector3(0, bh.y - 0.01 - 0.035 * sin(PI * fposmod(u2 * 3.0, 1.0)), 0))
	var green := Color("2e7d4f", fabric)
	for i in gl.size():
		k.soft_blob(gl[i], Vector3(0.022, 0.02, 0.016), green.darkened(0.08 * float(i % 2)), 3, 7)
		if i % 2 == 0:
			var bulb: Color = HolidayDecor.BULB_COLS[(i / 2) % HolidayDecor.BULB_COLS.size()]
			k.blob(gl[i] + fwd * 0.016 - Vector3(0, 0.012, 0), Vector3(0.009, 0.012, 0.009), bulb, 2, 6, 2.6)
	# a red bow on the top corner
	var bw := gcorner + side * (bh.x - 0.02) + Vector3(0, bh.y + 0.005, 0)
	k.soft_blob(bw + side * 0.035 + Vector3(0, 0.015, 0), Vector3(0.04, 0.026, 0.014), RED, 4, 8)
	k.soft_blob(bw - side * 0.035 + Vector3(0, 0.015, 0), Vector3(0.04, 0.026, 0.014), RED, 4, 8)
	k.soft_blob(bw + Vector3(0, 0.012, 0), Vector3(0.016, 0.016, 0.014), Color("b1202f", 0.6), 3, 7)
	k.box(bw + side * 0.02 - Vector3(0, 0.035, 0), Vector3(0.012, 0.07, 0.005), RED, yaw)
	k.box(bw - side * 0.02 - Vector3(0, 0.04, 0), Vector3(0.012, 0.08, 0.005), RED, yaw)


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
	var w := 0.0054
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
		_relax_all(delta, {})
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
	if phase != _phase_was and phase != BallSync.Phase.FREE and v != null:
		_wind_from = _drawn if _have_drawn else Vector3.INF
		if was_free:
			# (build 25) picked up off the floor: the dribble starts at the
			# bottom of a bounce (where the ball is) and rises into the hand;
			# caught in the air: it starts at the hand
			_dribble = 0.5 if (_have_drawn and _drawn.y < 0.25) else 0.0
			_off = Vector3.INF
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
	_relax_all(delta, want)


## (build 25) Just after a shot leaves the hand: the shooting arm reaches up
## and out the way it went (the wrist "in the cookie jar"), the guide hand
## stays up a moment, then both relax.
func _follow_through(want: Dictionary) -> void:
	if ball.phase != BallSync.Phase.FREE or not ball.released_shot or ball.phase_t > FOLLOW_S:
		return
	var key := _key_of(ball.sim.shooter)
	if key == "" or want.has(key):
		return
	var v: CharacterView = stage.chars.get(key)
	if v == null or not is_instance_valid(v) or not v.visible:
		return
	var at := stage.to_local(v.global_position)
	var yaw := v.rotation.y
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var shoulder_r := at + right * 0.17 + Vector3(0, 0.84, 0)
	var shoulder_l := at - right * 0.17 + Vector3(0, 0.84, 0)
	# (out to the side of the big head, so it reads from behind too)
	want[key] = {"r": at + right * 0.2 + fwd * 0.2 + Vector3(0, 1.16, 0),
		"pr": shoulder_r + fwd * 0.2 + right * 0.2 + Vector3(0, -0.1, 0),
		"l": at - right * 0.06 + fwd * 0.15 + Vector3(0, 1.0, 0),
		"pl": shoulder_l - right * 0.35 + Vector3(0, -0.2, 0)}


func _handoff_now() -> Vector3:
	if _handoff_t >= HANDOFF_S:
		return Vector3.ZERO
	var u := clampf(_handoff_t / HANDOFF_S, 0.0, 1.0)
	return _handoff * (1.0 - u * u * u * (u * (u * 6.0 - 15.0) + 10.0))


## Where the ball is in a holder's hands this frame (and what their arms do).
## (build 25) A smooth dribble: the ball eases into and out of the hand at
## the top (no snap) and bounces crisply off the floor; its pace and its
## place beside the runner follow their walking and turning gradually.
func _held(v: CharacterView, key: String, phase: int, delta: float, want: Dictionary) -> Vector3:
	var at := stage.to_local(v.global_position)
	var yaw := v.rotation.y
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var prev: Array = _last_at.get(key, [at, 0.0])
	var sp := (Vector2(at.x, at.z) - Vector2((prev[0] as Vector3).x, (prev[0] as Vector3).z)).length() / maxf(delta, 0.001)
	if sp > HubRoom.WALK_SPEED * 2.5:
		sp = float(prev[1])   # a jump (a correction): not a sprint
	sp = lerpf(float(prev[1]), minf(sp, HubRoom.WALK_SPEED * 1.2), 1.0 - exp(-delta * 3.0))
	_last_at[key] = [at, sp]
	var k := clampf(sp / HubRoom.WALK_SPEED, 0.0, 1.0)
	# beside the right hand, a little ahead when walking; turns ease in
	var off_want := right * 0.21 + fwd * (0.05 + 0.1 * k)
	if _off == Vector3.INF:
		_off = off_want
	_off = _off.lerp(off_want, 1.0 - exp(-delta * 9.0))
	var dribble_at := at + _off
	# the pace eases too (no hiccup when you start or stop walking)
	var pace_want := 1.0 / lerpf(DRIBBLE_SLOW_S, DRIBBLE_FAST_S, k)
	_pace = pace_want if _pace <= 0.0 else lerpf(_pace, pace_want, 1.0 - exp(-delta * 4.0))
	var u_was := _dribble
	_dribble = fmod(_dribble + delta * _pace, 1.0)
	var u := _dribble
	# |cos|: level and slow at the hand, quick off the floor
	var y := HubBall.R + (DRIBBLE_TOP - HubBall.R) * absf(cos(PI * u))
	var p := dribble_at + Vector3(0, y, 0)
	var shoulder_r := at + right * 0.17 + Vector3(0, 0.84, 0)
	match phase:
		BallSync.Phase.HELD:
			if u_was < 0.5 and u >= 0.5:
				_play("ball_bounce", dribble_at + Vector3(0, HubBall.R, 0), -14.0 + 4.0 * k, randf_range(0.96, 1.04))
			# (build 25) the arm works the ball: the palm on top of it as it
			# comes up (elbow bent), pushing it down until the arm is
			# straight, then waiting low for it and riding it back up
			var hand := p + Vector3(0, HubBall.R + 0.01, 0) + right * 0.012
			hand.y = clampf(hand.y, HAND_LOW, HAND_HIGH)
			want[key] = {"r": hand, "pr": shoulder_r + right * 0.32 - fwd * 0.28 + Vector3(0, -0.12, 0)}
			_rot = Basis(right, -delta * 8.0) * _rot
		BallSync.Phase.SHOT:
			# (build 25) the form: both hands bring the ball to the chest,
			# then up to the set point over the right eye, the shooting hand
			# under and behind it, the elbow in under the ball, the guide
			# hand on its side
			var t := clampf(ball.phase_t / BallSync.WINDUP_SHOT, 0.0, 1.0)
			var pocket := at + right * SHOT_POCKET.x + Vector3(0, SHOT_POCKET.y, 0) - fwd * SHOT_POCKET.z
			var hold := at + right * SHOT_HOLD.x + Vector3(0, SHOT_HOLD.y, 0) - fwd * SHOT_HOLD.z
			var from := _wind_from if _wind_from != Vector3.INF else p
			if t < 0.4:
				var u1 := t / 0.4
				p = from.lerp(pocket, u1 * u1 * u1 * (u1 * (u1 * 6.0 - 15.0) + 10.0))
			else:
				var u2 := (t - 0.4) / 0.6
				p = pocket.lerp(hold, u2 * u2 * (3.0 - 2.0 * u2))
			var shoulder_l := at - right * 0.17 + Vector3(0, 0.84, 0)
			want[key] = {"r": p - fwd * (HubBall.R * 0.75) - Vector3(0, HubBall.R * 0.55, 0) + right * 0.015,
				"l": p - right * (HubBall.R + 0.012) + fwd * 0.01,
				"pr": shoulder_r + fwd * 0.3 + Vector3(0, -0.35, 0) + right * 0.05,
				"pl": shoulder_l - right * 0.35 + fwd * 0.1 + Vector3(0, -0.2, 0)}
		BallSync.Phase.PASS:
			var t2 := clampf(ball.phase_t / BallSync.WINDUP_PASS, 0.0, 1.0)
			var e2 := t2 * t2 * t2 * (t2 * (t2 * 6.0 - 15.0) + 10.0)
			var hold2 := at + right * PASS_HOLD.x + Vector3(0, PASS_HOLD.y, 0) + fwd * PASS_HOLD.z
			var from2 := _wind_from if _wind_from != Vector3.INF else p
			p = from2.lerp(hold2, e2)
			want[key] = {"r": p + right * (HubBall.R + 0.012), "l": p - right * (HubBall.R + 0.012),
				"pr": shoulder_r + right * 0.35 + Vector3(0, -0.35, 0) + fwd * 0.05,
				"pl": shoulder_r - right * 0.69 + Vector3(0, -0.35, 0) + fwd * 0.05}
	return p


# ---------------------------------------------------------------------------
# Arms (a two-bone IK per arm, added to a runner's skeleton the first time
# they hold the ball, faded in and out)
# ---------------------------------------------------------------------------
func _ik_for(v: CharacterView, key: String) -> Dictionary:
	var e: Dictionary = _iks.get(key, {})
	var sk := v.skeleton
	if not e.is_empty() and is_instance_valid(e["r"]) and (e["r"] as Node).get_parent() == sk:
		return e
	if not e.is_empty():
		_free_ik(e)
	if sk == null:
		return {}
	e = {"wr": 0.0, "wl": 0.0}
	for side in ["r", "l"]:
		var sfx := "R" if side == "r" else "L"
		var tgt := Node3D.new()
		tgt.name = "BallHand" + sfx
		add_child(tgt)
		var pole := Node3D.new()
		pole.name = "BallElbow" + sfx
		add_child(pole)
		var ik := TwoBoneIK3D.new()
		ik.name = "BallArm" + sfx
		ik.set_setting_count(1)
		ik.set_root_bone_name(0, "upper_arm." + sfx)
		ik.set_middle_bone_name(0, "forearm." + sfx)
		ik.set_end_bone_name(0, "hand." + sfx)
		ik.influence = 0.0
		ik.active = false
		sk.add_child(ik)
		ik.set_target_node(0, ik.get_path_to(tgt))
		ik.set_pole_node(0, ik.get_path_to(pole))
		e[side] = ik
		e["t" + side] = tgt
		e["p" + side] = pole
	_iks[key] = e
	return e


func _free_ik(e: Dictionary) -> void:
	for n in ["r", "l", "tr", "tl", "pr", "pl"]:
		var o: Variant = e.get(n)
		if o != null and is_instance_valid(o):
			(o as Node).queue_free()


func _relax_all(delta: float, want: Dictionary) -> void:
	for key in want:
		var v: CharacterView = stage.chars.get(key)
		if v != null and is_instance_valid(v):
			_ik_for(v, key)
	for key in _iks.keys():
		var e: Dictionary = _iks[key]
		var v2: Variant = stage.chars.get(key) if stage != null else null
		if v2 == null or not is_instance_valid(v2) or not is_instance_valid(e.get("r")):
			_free_ik(e)
			_iks.erase(key)
			continue
		var w: Dictionary = want.get(key, {})
		for side in ["r", "l"]:
			var on := w.has(side)
			var cur := float(e["w" + side])
			cur = move_toward(cur, 1.0 if on else 0.0, delta / (IK_IN_S if on else IK_OUT_S))
			e["w" + side] = cur
			var ik: TwoBoneIK3D = e[side]
			if on:
				# (build 25) the hand glides to its target (no snap between
				# the dribble and the windup)
				var ik_key := "%s|%s" % [key, side]
				var tgt_now: Vector3 = w[side]
				var was_at: Vector3 = _ik_at.get(ik_key, tgt_now)
				if cur < 0.05:
					was_at = tgt_now
				var glided := was_at.lerp(tgt_now, 1.0 - exp(-delta * 22.0))
				_ik_at[ik_key] = glided
				(e["t" + side] as Node3D).global_position = stage.to_global(glided)
				(e["p" + side] as Node3D).global_position = stage.to_global(w["p" + side])
			ik.influence = cur * cur * (3.0 - 2.0 * cur)
			ik.active = cur > 0.001


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
