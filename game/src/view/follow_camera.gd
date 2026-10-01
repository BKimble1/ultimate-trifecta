class_name FollowCamera
extends Camera3D
## Elevated third-person follow camera: collision-aware, smooth recentering,
## sensible look limits, room ahead of the player, blended cart camera.

var target_pos := Vector3.ZERO
var target_vel := Vector3.ZERO
var target_yaw: float = 0.0
var yaw: float = 0.0
var pitch: float = 0.32
var in_cart := false
var reduced_motion := false
var auto_recenter := true

var _dist: float = 6.0
var _height: float = 1.55
var _fov: float = 66.0
var _cur_dist: float = 6.0
var _pivot := Vector3.ZERO
var _ahead := Vector3.ZERO
var _manual_t: float = 10.0
var _shake: float = 0.0
var _probe: SphereShape3D
var _initialized := false

const PITCH_MIN := -0.15
const PITCH_MAX := 1.05


func _ready() -> void:
	_probe = SphereShape3D.new()
	_probe.radius = 0.28
	near = 0.1
	far = 420.0
	fov = _fov


func snap_to(pos: Vector3, heading: float) -> void:
	target_pos = pos
	yaw = heading
	_pivot = pos + Vector3(0, _height, 0)
	_ahead = Vector3.ZERO
	_cur_dist = _dist
	_initialized = true
	_update_transform(1.0)


func add_look(d: Vector2) -> void:
	if d.length() > 0.0001:
		yaw -= d.x
		pitch = clampf(pitch + d.y, PITCH_MIN, PITCH_MAX)
		_manual_t = 0.0


func add_shake(amount: float) -> void:
	if not reduced_motion:
		_shake = minf(_shake + amount, 0.6)


func forward_yaw() -> float:
	return yaw


func update_camera(delta: float) -> void:
	if not _initialized:
		snap_to(target_pos, target_yaw)
	_manual_t += delta
	var want_dist := 8.6 if in_cart else 6.2
	var want_height := 2.3 if in_cart else 1.55
	var want_fov := 72.0 if in_cart else 66.0
	var blend := clampf(delta * 3.0, 0.0, 1.0)
	_dist = lerpf(_dist, want_dist, blend)
	_height = lerpf(_height, want_height, blend)
	_fov = lerpf(_fov, want_fov, blend)
	fov = _fov
	# automatic recentering behind the direction of travel
	var flat_v := Vector2(target_vel.x, target_vel.z)
	var spd := flat_v.length()
	var recenter_delay := 1.4 if not in_cart else 0.6
	if auto_recenter and _manual_t > recenter_delay and spd > 1.5:
		var heading := atan2(-flat_v.x, -flat_v.y)
		var rate := (0.9 if reduced_motion else 1.6) * clampf(spd / 6.0, 0.3, 1.5)
		if in_cart:
			rate *= 1.6
		yaw = rotate_toward(yaw, heading, rate * delta)
		if not in_cart:
			pitch = move_toward(pitch, 0.32, 0.3 * delta)
		else:
			pitch = move_toward(pitch, 0.38, 0.5 * delta)
	# look-ahead: shift the pivot a little toward where we're going
	var ahead_want := Vector3(target_vel.x, 0, target_vel.z) * (0.18 if not in_cart else 0.25)
	ahead_want = ahead_want.limit_length(1.8 if not in_cart else 3.0)
	_ahead = _ahead.lerp(ahead_want, clampf(delta * 2.5, 0.0, 1.0))
	var pivot_want := target_pos + Vector3(0, _height, 0) + _ahead
	var follow := clampf(delta * (14.0 if not reduced_motion else 9.0), 0.0, 1.0)
	_pivot = _pivot.lerp(pivot_want, follow)
	if _pivot.distance_to(pivot_want) > 12.0:
		_pivot = pivot_want
	_update_transform(delta)


func _update_transform(delta: float) -> void:
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var desired := _pivot + dir * _dist
	# obstacle handling: sphere sweep from the pivot toward the camera
	var safe_frac := 1.0
	if is_inside_tree():
		var ss := get_world_3d().direct_space_state
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = _probe
		q.transform = Transform3D(Basis.IDENTITY, _pivot)
		q.motion = desired - _pivot
		q.collision_mask = TC.L_WORLD
		var res := ss.cast_motion(q)
		if res.size() == 2:
			safe_frac = res[0]
	var want_d := _dist * safe_frac
	if want_d < _cur_dist:
		_cur_dist = want_d   # pull in immediately: never clip through walls
	else:
		_cur_dist = lerpf(_cur_dist, want_d, clampf(delta * 3.0, 0.0, 1.0))
	_cur_dist = maxf(_cur_dist, 0.8)
	var cam_pos := _pivot + dir * _cur_dist
	# keep above ground/water level
	cam_pos.y = maxf(cam_pos.y, _pivot.y - 0.6)
	var shake_off := Vector3.ZERO
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 1.8)
		var s := _shake * _shake * 0.25
		shake_off = Vector3(randf_range(-s, s), randf_range(-s, s), randf_range(-s, s))
	global_position = cam_pos + shake_off
	var look_at_pt := _pivot + Vector3(0, -0.25, 0)
	if global_position.distance_to(look_at_pt) > 0.05:
		look_at(look_at_pt, Vector3.UP)
