class_name SimCart
extends RefCounted
## A Night Watch golf cart. Arcade kinematic model (no rigid-body chaos), so it
## behaves identically on host and in local prediction.

const HALF := Vector3(0.78, 0.9, 1.35)   # half extents (x, y, z) of the gameplay box

var id: int = 0
var body: CharacterBody3D
var yaw: float = 0.0
var speed: float = 0.0          # signed, along forward (-Z local)
var steer_s: float = 0.0        # smoothed steering
var occupant: int = -1          # player slot driving, -1 empty
var exiting := false            # driver requested exit: auto-brake until slow
var slowed_t: float = 0.0       # splash bomb slow
var immunity_t: float = 0.0
var on_road := true
var wall_hit := false
var bump_cd: Dictionary = {}    # runner id -> seconds until it may be bumped again
var home := Vector3.ZERO
var home_yaw: float = 0.0


func pos() -> Vector3:
	return body.global_position if body else Vector3.ZERO


func forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func right() -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))


## Candidate exit points for the driver, in preference order (left seat first).
func exit_points() -> Array[Vector3]:
	var p := pos()
	var r := right()
	var f := forward()
	return [p - r * 1.45, p + r * 1.45, p - f * 2.1, p + f * 2.1, p - r * 1.45 - f * 1.2, p + r * 1.45 - f * 1.2]


## Is a world point inside this cart's footprint grown by `margin` (XZ only)?
func overlaps(pt: Vector3, margin: float) -> bool:
	var rel := pt - pos()
	var lx := rel.dot(right())
	var lz := rel.dot(-forward())
	if rel.y < -0.4 or rel.y > 2.2:
		return false
	return absf(lx) <= HALF.x + margin and absf(lz) <= HALF.z + margin


func write_motor(buf: StreamPeerBuffer) -> void:
	var p := pos()
	buf.put_float(p.x)
	buf.put_float(p.y)
	buf.put_float(p.z)
	buf.put_float(yaw)
	buf.put_float(speed)
	buf.put_float(steer_s)
	buf.put_float(slowed_t)
	buf.put_float(body.velocity.y if body else 0.0)
	buf.put_u8(1 if exiting else 0)


static func read_motor(buf: StreamPeerBuffer) -> Dictionary:
	return {
		"pos": Vector3(buf.get_float(), buf.get_float(), buf.get_float()),
		"yaw": buf.get_float(), "speed": buf.get_float(), "steer_s": buf.get_float(),
		"slowed_t": buf.get_float(), "vy": buf.get_float(), "exiting": buf.get_u8() == 1,
	}


func apply_motor(d: Dictionary) -> void:
	if body:
		body.global_position = d["pos"]
		body.rotation = Vector3(0, d["yaw"], 0)
		body.velocity = Vector3(0, d["vy"], 0)
	yaw = d["yaw"]
	speed = d["speed"]
	steer_s = d["steer_s"]
	slowed_t = d["slowed_t"]
	exiting = d["exiting"]
