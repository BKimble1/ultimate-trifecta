class_name SnowPrints
extends MultiMeshInstance3D
## (2.2 build 21) Footprints in the snow patches (SnowCover): every runner and
## Night Watch on foot leaves a print each stride, left and right in turn,
## pressed into the snow where it is drawn, and every print stays until the
## round ends.  One MultiMesh: a flat print quad per footstep (up to CAP; the
## oldest is reused only past that), lit like the snow, slightly bluer and
## darker so it reads as pressed in.  View only.

const CAP := 4096
## distance between prints (one foot strike)
const STRIDE := 0.72
## half the distance between the feet
const SIDE := 0.11
## a step longer than this is a jump in position (a respawn, a rift): no print
const JUMP := 3.0

var cover: Dictionary
var placed := 0
## where each print is (the MultiMesh's own copy can't be read back on every
## renderer)
var spots := PackedVector3Array()
var _mm: MultiMesh
var _next := 0
var _last: Dictionary = {}   # slot -> {"p": Vector2, "side": float}


static func _print_texture() -> ImageTexture:
	var w := 32
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var u := (float(x) + 0.5) / float(w) * 2.0 - 1.0
			var v := (float(y) + 0.5) / float(h) * 2.0 - 1.0
			# one sole: a wide rounded toe (v < 0) running into a narrower heel
			# (smooth union, no gap at the waist)
			var toe := Vector2(u / 0.88, (v + 0.3) / 0.6).length()
			var heel := Vector2(u / 0.7, (v - 0.5) / 0.42).length()
			var k := 0.25
			var hh := clampf(0.5 + 0.5 * (heel - toe) / k, 0.0, 1.0)
			var d := lerpf(heel, toe, hh) - k * hh * (1.0 - hh)
			var a := clampf((1.0 - d) / 0.3, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			# the rim of the print is a touch lighter (packed snow edge)
			var c := 1.0 - 0.2 * clampf(1.0 - absf(d - 0.85) / 0.15, 0.0, 1.0)
			img.set_pixel(x, y, Color(c, c, c, a))
	return ImageTexture.create_from_image(img)


func setup(cover_d: Dictionary) -> void:
	name = "SnowPrints"
	cover = cover_d
	var pm := PlaneMesh.new()
	pm.size = Vector2(0.2, 0.38)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _print_texture()
	mat.albedo_color = Color(0.5, 0.57, 0.72, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.9
	mat.disable_receive_shadows = false
	pm.material = mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = pm
	_mm.instance_count = CAP
	_mm.visible_instance_count = 0
	multimesh = _mm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Called every frame for each character drawn on foot (pos at the feet).
func track(slot: int, pos: Vector3, on_floor: bool) -> void:
	var q := Vector2(pos.x, pos.z)
	var l: Dictionary = _last.get(slot, {})
	if l.is_empty() or not on_floor:
		# in the air (or new): the next print is where they land
		_last[slot] = {"p": q, "side": float(l.get("side", 1.0))}
		return
	var d := q - (l["p"] as Vector2)
	var dl := d.length()
	if dl < STRIDE:
		return
	var side := -float(l["side"])
	_last[slot] = {"p": q, "side": side}
	if dl > JUMP:
		return
	var dir := d / dl
	var at := q + Vector2(-dir.y, dir.x) * SIDE * side
	if SnowCover.amount_at(cover, at) < 0.55:
		return
	add_print(Vector3(at.x, pos.y + 0.012, at.y), dir)


func add_print(at: Vector3, dir: Vector2) -> void:
	var b := Basis(Vector3.UP, atan2(-dir.x, -dir.y))
	_mm.set_instance_transform(_next, Transform3D(b, at))
	if spots.size() < CAP:
		spots.append(at)
	else:
		spots[_next] = at
	_next = (_next + 1) % CAP
	placed += 1
	_mm.visible_instance_count = mini(placed, CAP)


## Someone left the round: forget their last step.
func forget(slot: int) -> void:
	_last.erase(slot)
