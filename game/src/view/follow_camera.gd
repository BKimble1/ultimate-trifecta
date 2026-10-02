class_name FollowCamera
extends Camera3D
## Third-person follow camera.
##
## Pipeline position: it runs every rendered frame *after* the characters,
## following the same render-time anchor the local character is drawn at
## (MatchController hands it the interpolated position), so the camera and
## the character never disagree by a physics step.
##
##  * Manual look is applied immediately (no smoothing on input).
##  * All damping is frame-rate independent: x += (target - x) * (1 - e^(-dt/tau)).
##  * Horizontal follow is exact; only the vertical anchor is lightly damped
##    (tau 0.06 s) so jumps and steps don't bounce the view.
##  * Recentering starts after a pause in manual look, is gradual, and only
##    happens while the stick points mostly forward (no circling when the
##    player holds a diagonal).
##  * Collision: sphere sweep pivot -> camera; if the pivot itself starts
##    inside geometry the sweep restarts from the character's chest; the
##    collision distance always wins over the preferred minimum; pull-in is
##    immediate, push-out waits for a short clear period (hysteresis).
##  * V5: a narrow occluder (tree trunk, lamp post) crossing the line to a
##    camera spot that is itself clear no longer pulls the camera in.  It
##    jumped ~3 m in one frame and eased back over ~0.7 s for a 14 cm post
##    (CameraRig cam_lamp).  Walls and buildings still pull in at once.
##    Cost: up to four rays and one shape test, only on frames whose sweep
##    hits something.
##  * Cart entry/exit blends distance/height over ~0.4 s.  No speed zoom, no
##    random shake, level horizon.  Reduced Motion: slower recentering, no
##    look-ahead, softer blends.

var target_pos := Vector3.ZERO
var target_vel := Vector3.ZERO
var target_yaw: float = 0.0
var move_input := Vector2.ZERO    # local stick/keys (x right, y forward), for recentering
var yaw: float = 0.0
var pitch: float = 0.32
var in_cart := false
var reduced_motion := false
var auto_recenter := true

var _dist: float = 6.2
var _height: float = 1.55
var _fov: float = 66.0
var _cur_dist: float = 6.2
var _pivot := Vector3.ZERO
var _ahead := Vector3.ZERO
var _manual_t: float = 10.0
var _clear_t: float = 0.0
var _probe: SphereShape3D
var _initialized := false

const PITCH_MIN := -0.15
const PITCH_MAX := 1.05
const MIN_DIST := 1.1


static func damp(cur: float, target: float, tau: float, dt: float) -> float:
	return target if tau <= 0.0 else cur + (target - cur) * (1.0 - exp(-dt / tau))


static func damp_v(cur: Vector3, target: Vector3, tau: float, dt: float) -> Vector3:
	return target if tau <= 0.0 else cur + (target - cur) * (1.0 - exp(-dt / tau))


func _ready() -> void:
	_probe = SphereShape3D.new()
	_probe.radius = 0.28
	near = 0.1
	far = 420.0
	fov = _fov


## Hard cut (spawn, respawn, spectator change, reconnect): no history carried.
func snap_to(pos: Vector3, heading: float) -> void:
	target_pos = pos
	yaw = heading
	_pivot = pos + Vector3(0, _height, 0)
	_ahead = Vector3.ZERO
	_cur_dist = _dist
	_clear_t = 0.0
	_initialized = true
	_update_transform(1.0)


func add_look(d: Vector2) -> void:
	if d.length() > 0.00001:
		yaw -= d.x
		pitch = clampf(pitch + d.y, PITCH_MIN, PITCH_MAX)
		_manual_t = 0.0


func add_shake(_amount: float) -> void:
	pass   # V2: no random shake (calm horizon); kept so callers stay simple


func forward_yaw() -> float:
	return yaw


func update_camera(delta: float) -> void:
	if not _initialized:
		snap_to(target_pos, target_yaw)
	_manual_t += delta
	var blend_tau := 0.18 if not reduced_motion else 0.3
	_dist = damp(_dist, 8.4 if in_cart else 6.2, blend_tau, delta)
	_height = damp(_height, 2.2 if in_cart else 1.55, blend_tau, delta)
	_fov = damp(_fov, 68.0 if in_cart else 66.0, blend_tau, delta)
	fov = _fov
	# gradual recentering behind the direction of travel
	var flat_v := Vector2(target_vel.x, target_vel.z)
	var spd := flat_v.length()
	var delay := 0.6 if in_cart else 1.4
	var forwardish := in_cart or (move_input.length() > 0.2 and absf(move_input.x) < 0.38 * move_input.length() and move_input.y > 0.0)
	if auto_recenter and _manual_t > delay and spd > 1.5 and forwardish:
		var heading := atan2(-flat_v.x, -flat_v.y)
		var rate := (0.7 if reduced_motion else 1.4) * clampf(spd / 6.0, 0.3, 1.4)
		if in_cart:
			rate *= 1.5
		yaw = rotate_toward(yaw, heading, rate * delta)
		pitch = move_toward(pitch, 0.38 if in_cart else 0.32, 0.3 * delta)
	# look-ahead (none with Reduced Motion)
	var ahead_want := Vector3.ZERO
	if not reduced_motion:
		ahead_want = (Vector3(target_vel.x, 0, target_vel.z) * (0.16 if not in_cart else 0.22)).limit_length(1.6 if not in_cart else 2.8)
	_ahead = damp_v(_ahead, ahead_want, 0.45, delta)
	var anchor := target_pos + Vector3(0, _height, 0) + _ahead
	if _pivot.distance_to(anchor) > 10.0:
		_pivot = anchor
	_pivot.x = anchor.x
	_pivot.z = anchor.z
	_pivot.y = damp(_pivot.y, anchor.y, 0.06 if not reduced_motion else 0.1, delta)
	_update_transform(delta)


func _sweep(from: Vector3, to: Vector3) -> float:
	if not is_inside_tree():
		return 1.0
	var ss := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _probe
	q.transform = Transform3D(Basis.IDENTITY, from)
	q.motion = to - from
	q.collision_mask = TC.L_WORLD
	var res := ss.cast_motion(q)
	if res.size() == 2:
		return res[0]
	return 1.0


func _pivot_blocked(p: Vector3) -> bool:
	if not is_inside_tree():
		return false
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _probe
	q.transform = Transform3D(Basis.IDENTITY, p)
	q.collision_mask = TC.L_WORLD
	return not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## True when what blocks the line from `from` to `to` is a post-like
## obstacle: the camera spot is clear, a ray meets less than 0.9 m of it and
## a parallel ray 1 m to one side passes.
func _narrow_occluder(from: Vector3, to: Vector3) -> bool:
	if not is_inside_tree() or _pivot_blocked(to):
		return false
	var ss := get_world_3d().direct_space_state
	var len := from.distance_to(to)
	var h1 := ss.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, TC.L_WORLD))
	if not h1.is_empty():
		var h2 := ss.intersect_ray(PhysicsRayQueryParameters3D.create(to, from, TC.L_WORLD))
		if h2.is_empty():
			return false
		var depth := len - from.distance_to(h1["position"]) - to.distance_to(h2["position"])
		if depth > 0.9:
			return false
	else:
		return true    # only the probe sphere grazes it: the line of sight is open
	# a wall blocks parallel rays 1 m to both sides; a post or trunk (< 0.9 m
	# across) at most one of them
	var side := (to - from).cross(Vector3.UP)
	if side.length() < 1e-4:
		return false
	side = side.normalized() * 1.0
	for sgn in [-1.0, 1.0]:
		var o: Vector3 = side * sgn
		if ss.intersect_ray(PhysicsRayQueryParameters3D.create(to + o, from + o, TC.L_WORLD)).is_empty():
			return true
	return false


func _update_transform(delta: float) -> void:
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var origin := _pivot
	if _pivot_blocked(origin):
		# pivot inside geometry (low branch, doorway lintel): sweep from the chest
		origin = target_pos + Vector3(0, 0.9, 0)
	var desired := origin + dir * _dist
	var frac := _sweep(origin, desired)
	if frac < 0.999 and _narrow_occluder(origin, desired):
		frac = 1.0
	var want_d := _dist * frac
	# the preferred minimum only applies when collision allows it
	var free_d := want_d
	if want_d < MIN_DIST and frac >= 0.999:
		free_d = MIN_DIST
	if free_d < _cur_dist - 0.01:
		_cur_dist = free_d          # pull in immediately: never clip through walls
		_clear_t = 0.0
	else:
		_clear_t += delta
		if _clear_t > 0.15:         # hysteresis: wait until clear before easing out
			_cur_dist = damp(_cur_dist, free_d, 0.35, delta)
		_cur_dist = minf(_cur_dist, free_d)
	var cam_pos := origin + dir * _cur_dist
	cam_pos.y = maxf(cam_pos.y, target_pos.y + 0.35)
	global_position = cam_pos
	var look_at_pt := _pivot + Vector3(0, -0.25, 0)
	if global_position.distance_to(look_at_pt) > 0.05:
		look_at(look_at_pt, Vector3.UP)
