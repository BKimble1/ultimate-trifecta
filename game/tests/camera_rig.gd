class_name CameraRig
extends Node3D
## FollowCamera measurement (V5): the real FollowCamera following a scripted
## target past campus-sized colliders (a tree trunk: cylinder r 0.42 m,
## 4 m; a lamp post: r 0.14 m, 3.4 m; a building wall; a ramp), with the
## campus collision layer.  Records per frame the camera distance from the
## pivot, the camera position and whether the pivot is visible from the
## camera.  Used by tests/test_motion_v5.gd and src/dev/motion_probe.tscn.

signal finished

const SCENARIOS := {"cam_trunk": 3.0, "cam_lamp": 3.0, "cam_wall": 3.5, "cam_ramp": 3.0, "cam_hitch": 2.0, "cam_turn": 3.0}

var cam: FollowCamera
var scenario := ""
var length := 2.0
var frames: Array = []
var running := false
var _t := 0.0
var _pos := Vector3.ZERO
var _frame := 0
var _yaw := 0.0


func _init() -> void:
	process_priority = -100


func _cyl(r: float, h: float, at: Vector3) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = TC.L_WORLD
	var cs := CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = r
	c.height = h
	cs.shape = c
	b.add_child(cs)
	b.position = at + Vector3(0, h * 0.5, 0)
	add_child(b)


func _box(size: Vector3, at: Vector3, rot_x: float = 0.0) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = TC.L_WORLD
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	cs.shape = s
	b.add_child(cs)
	b.position = at
	b.rotation.x = rot_x
	add_child(b)


func start(p_scenario: String) -> void:
	scenario = p_scenario
	length = float(SCENARIOS.get(scenario, 2.0))
	_box(Vector3(200, 1, 200), Vector3(0, -0.5, 0))     # ground
	match scenario:
		"cam_trunk":
			_cyl(0.42, 4.0, Vector3(6.0, 0, 3.2))
		"cam_lamp":
			_cyl(0.14, 3.4, Vector3(6.0, 0, 3.2))
		"cam_wall":
			_box(Vector3(40, 8, 1), Vector3(5, 4, 3.2))
		"cam_ramp":
			# runs up a 15 degree ramp toward -Z with the camera behind
			_box(Vector3(6, 0.4, 14), Vector3(0, 1.4, -9), deg_to_rad(15))
	cam = FollowCamera.new()
	add_child(cam)
	cam.current = true
	_pos = Vector3.ZERO
	_yaw = 0.0    # camera on +Z, looking toward -Z
	# side passes: the camera stays on +Z (no recentering) so obstacles cross
	# its line at a known moment
	cam.auto_recenter = scenario in ["cam_ramp", "cam_turn"]
	cam.snap_to(_pos, _yaw)
	frames.clear()
	_t = 0.0
	_frame = 0
	Engine.time_scale = 1.0
	running = true


func _target(t: float) -> Vector3:
	match scenario:
		"cam_trunk", "cam_lamp", "cam_wall", "cam_hitch":
			# runs along +X at 5 m/s; the camera trails behind on +Z
			return Vector3(5.0 * t, 0, 0)
		"cam_ramp":
			var z := -5.0 * t
			var h := clampf((-z - 2.0) * tan(deg_to_rad(15)), 0.0, 3.0) if z < -2.0 else 0.0
			return Vector3(0, h, z)
		"cam_turn":
			var a := t * 1.6
			return Vector3(sin(a) * 4.0, 0, -cos(a) * 4.0 + 4.0)
	return Vector3.ZERO


func _process(delta: float) -> void:
	if not running:
		return
	_t += delta
	var p := _target(_t)
	var v := (p - _pos) / maxf(delta, 1e-4)
	_pos = p
	cam.target_pos = p
	cam.target_vel = v
	cam.move_input = Vector2(0, 1) if scenario != "cam_turn" else Vector2.ZERO
	cam.update_camera(delta)
	var pivot := p + Vector3(0, 1.55, 0)
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, pivot, TC.L_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	frames.append({"t": _t, "dt": delta, "cam": cam.global_position, "dist": cam._cur_dist, "pivot": pivot, "blocked": not hit.is_empty()})
	Engine.time_scale = 15.0 if (scenario == "cam_hitch" and _frame == 60) else 1.0
	_frame += 1
	if _t >= length:
		running = false
		Engine.time_scale = 1.0
		finished.emit.call_deferred()


## jump_m: the largest one-frame camera move beyond what the target moved
## that frame (m); dist_min: the closest the camera came; pull_frames: frames
## spent pulled in more than 1 m; blocked: frames the pivot was hidden.
func metrics() -> Dictionary:
	var jump := 0.0
	var jump_t := 0.0
	var dmin := 99.0
	var pulled := 0
	var blocked := 0
	for i in range(1, frames.size()):
		var a: Dictionary = frames[i - 1]
		var b: Dictionary = frames[i]
		var cam_move := (b["cam"] as Vector3) - (a["cam"] as Vector3)
		var tgt_move := (b["pivot"] as Vector3) - (a["pivot"] as Vector3)
		var j := (cam_move - tgt_move).length()
		if j > jump:
			jump = j
			jump_t = float(b["t"])
		dmin = minf(dmin, float(b["dist"]))
		if float(b["dist"]) < 5.2:
			pulled += 1
		if bool(b["blocked"]):
			blocked += 1
	return {"scenario": scenario, "jump_m": snappedf(jump, 0.001), "jump_t": snappedf(jump_t, 0.01), "dist_min": snappedf(dmin, 0.01),
		"pull_frames": pulled, "blocked_frames": blocked, "frames": frames.size()}


func cleanup() -> void:
	Engine.time_scale = 1.0
