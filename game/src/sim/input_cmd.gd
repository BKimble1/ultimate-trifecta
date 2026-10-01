class_name InputCmd
extends RefCounted
## One tick of player intent. Movement is already in world space (the client
## converts the stick using its camera), so the simulation never depends on
## presentation. 12 bytes on the wire.

var seq: int = 0
var move := Vector2.ZERO      # world XZ, length <= 1
var steer: float = 0.0        # -1 left .. +1 right (carts)
var drive: float = 0.0        # -1 brake/reverse .. +1 accelerate (carts)
var cam_yaw: float = 0.0      # camera yaw (radians) for aim assists / patrol view cone
var held: int = 0             # TC.BTN_* currently held
var pressed: int = 0          # TC.BTN_* edge this tick


func duplicate_cmd() -> InputCmd:
	var c := InputCmd.new()
	c.seq = seq
	c.move = move
	c.steer = steer
	c.drive = drive
	c.cam_yaw = cam_yaw
	c.held = held
	c.pressed = pressed
	return c


func is_held(bit: int) -> bool:
	return (held & bit) != 0


func is_pressed(bit: int) -> bool:
	return (pressed & bit) != 0


## Copy without one-shot edges (used when repeating a missing input).
func repeat_without_edges(next_seq: int) -> InputCmd:
	var c := duplicate_cmd()
	c.seq = next_seq
	c.pressed = 0
	return c


func write(buf: StreamPeerBuffer) -> void:
	buf.put_u32(seq)
	buf.put_8(_q8(move.x))
	buf.put_8(_q8(move.y))
	buf.put_8(_q8(steer))
	buf.put_8(_q8(drive))
	buf.put_u16(int(fposmod(cam_yaw, TAU) / TAU * 65535.0) & 0xFFFF)
	buf.put_u8(held & 0xFF)
	buf.put_u8(pressed & 0xFF)


static func read(buf: StreamPeerBuffer) -> InputCmd:
	var c := InputCmd.new()
	c.seq = buf.get_u32()
	c.move = Vector2(float(buf.get_8()) / 127.0, float(buf.get_8()) / 127.0)
	if c.move.length() > 1.0:
		c.move = c.move.normalized()
	c.steer = clampf(float(buf.get_8()) / 127.0, -1.0, 1.0)
	c.drive = clampf(float(buf.get_8()) / 127.0, -1.0, 1.0)
	c.cam_yaw = float(buf.get_u16()) / 65535.0 * TAU
	c.held = buf.get_u8()
	c.pressed = buf.get_u8()
	return c


static func _q8(v: float) -> int:
	return clampi(int(round(clampf(v, -1.0, 1.0) * 127.0)), -127, 127)


## Quantize in place so locally predicted inputs match exactly what the host decodes.
func quantize() -> void:
	move = Vector2(float(_q8(move.x)) / 127.0, float(_q8(move.y)) / 127.0)
	if move.length() > 1.0:
		move = move.normalized()
	steer = float(_q8(steer)) / 127.0
	drive = float(_q8(drive)) / 127.0
	cam_yaw = float(int(fposmod(cam_yaw, TAU) / TAU * 65535.0) & 0xFFFF) / 65535.0 * TAU
