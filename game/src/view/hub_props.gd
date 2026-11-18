class_name HubProps
extends Node3D
## (build 20) The party room's props that move (DormStage builds one):
##
##  * the couch's seat cushions and pillows, which squash under someone
##    bouncing on them and spring back with a little wobble;
##  * the floor lamp: its light, its glowing shade and the warm pools it
##    throws, all switched together (with a quick flicker coming on);
##  * the plant by the fireplace, whose leaves rustle when someone ducks in
##    or jumps out;
##  * a cat asleep on the armchair, breathing.
## Positions match the room's static mesh and HubRoom's footprints.  View
## only: HubWalk and HubSync decide who is doing what.  Reduced Motion keeps
## the squash and the switch but drops the wobble, the flicker and the cat's
## breathing.

const COUCH_C := Vector3(-3.6, 0.48, -2.6)      # bottom of the seat cushions
const PLANT_C := Vector3(-5.3, 0.5, 1.6)        # the pot's rim
const LAMP_SHADE := Vector3(3.9, 1.5, -1.9)
## how far the cushions give under a bounce (fraction of their 0.2 m)
const SQUASH := 0.32
const LAMP_ENERGY := 2.15
const CAT_SCALE := 0.82

var reduced := false
var lamp_on := true
var _cushions: Node3D
var _pillows: Node3D
var _plant: Node3D
var _cat: Node3D
var _shade_mat: ShaderMaterial
var _light: OmniLight3D
var _pools: Array = []        # [MeshInstance3D, base intensity]
var _dims: Array = []         # [Object, property, base value, factor when off]
var _lamp_k := 1.0
var _flick := 0.0
var _press := 0.0             # target from HubWalk (0..1.5)
var _sq := 0.0                # the cushions' spring
var _sq_v := 0.0
var _rustle := 0.0
var _t := 0.0


static func _mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/shaders/dorm.gdshader")
	return m


static func _node(k: MeshKit, at: Vector3, mat: ShaderMaterial, nm: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = k.commit()
	mi.material_override = mat
	mi.position = at
	return mi


## cc: the couch fabric colour; light: the lamp's OmniLight3D; pools: the
## lamp's light pools ([MeshInstance3D] with an "intensity" parameter).
func build(cc: Color, light: OmniLight3D, pools: Array, armchair: Vector3, armchair_yaw: float) -> void:
	name = "HubProps"
	var mat := _mat()
	# --- the couch's two seat cushions and its two pillows
	var k := MeshKit.new()
	for ci in 2:
		k.chamfer_box(Vector3(-4.27 + 1.34 * float(ci), 0.58, -2.6) - COUCH_C, Vector3(1.24, 0.2, 0.85), cc, 0.08)
	_cushions = _node(k, COUCH_C, mat, "CouchCushions")
	add_child(_cushions)
	var kp := MeshKit.new()
	# (build 21) the pillows lean on the back (their backs just touch its
	# front face at z -3.02) and sit on the seat, clear of the arms
	kp.soft_blob(Vector3(-4.2, 0.85, -2.9) - COUCH_C, Vector3(0.3, 0.19, 0.11), Color("ffc668", DormStage.FABRIC), 5, 12)
	kp.soft_blob(Vector3(-3.0, 0.85, -2.9) - COUCH_C, Vector3(0.28, 0.18, 0.1), Color("6fd8cc", DormStage.FABRIC), 5, 12)
	_pillows = _node(kp, COUCH_C, mat, "CouchPillows")
	add_child(_pillows)
	# (build 21: the red throw over the left arm is gone: at this size it
	# read as two lumps fighting the arm's rounded top)
	# --- the floor lamp's shade (its own material: it goes dark when off)
	var ks := MeshKit.new()
	ks.cylinder(Vector3.ZERO, 0.36, 0.42, Color("ffd9a0"), 28, 1.4, true, 0.22)
	_shade_mat = _mat()
	var shade := _node(ks, LAMP_SHADE, _shade_mat, "LampShade")
	add_child(shade)
	_light = light
	for p in pools:
		var pm := p as MeshInstance3D
		_pools.append([pm, float((pm.material_override as ShaderMaterial).get_shader_parameter("intensity"))])
	# --- the plant: a fuller leafy crown you could just about hide in
	var kl := MeshKit.new()
	for li in 6:
		var la := TAU * float(li) / 6.0 + 0.4
		var rr := 0.2 if li % 2 == 0 else 0.15
		kl.soft_blob(Vector3(cos(la) * rr, 0.38 + 0.1 * float(li % 3), sin(la) * rr), Vector3(0.36, 0.44, 0.36),
			Color("4f9a5c").lightened(0.035 * float(li)), 5, 12)
	kl.soft_blob(Vector3(0.0, 0.78, 0.0), Vector3(0.3, 0.36, 0.3), Color("5aa866"), 5, 12)
	_plant = _node(kl, PLANT_C, mat, "PlantLeaves")
	add_child(_plant)
	# --- a cat curled up asleep on the armchair's cushion
	_cat = Node3D.new()
	_cat.name = "Cat"
	var b := Basis(Vector3.UP, armchair_yaw)
	# (build 21) at the front of the seat cushion, lying across it, a little
	# smaller: clear of the chair's cream pillow (back) and its arms (sides)
	_cat.position = armchair + b * Vector3(0.0, 0.64, 0.24)
	_cat.rotation.y = armchair_yaw
	_cat.scale = Vector3.ONE * CAT_SCALE
	var kc := MeshKit.new()
	var fur := Color("e08a3c", DormStage.FABRIC)
	var fur_d := Color("b86a2a", DormStage.FABRIC)
	kc.soft_blob(Vector3(0, 0.1, 0), Vector3(0.25, 0.12, 0.17), fur, 5, 14)
	for si in 3:
		kc.soft_blob(Vector3(-0.1 + 0.1 * float(si), 0.2, 0), Vector3(0.025, 0.03, 0.15), fur_d, 3, 8)
	kc.soft_blob(Vector3(0.2, 0.12, 0.1), Vector3(0.1, 0.09, 0.1), fur, 5, 12)          # head
	kc.soft_blob(Vector3(0.23, 0.1, 0.17), Vector3(0.05, 0.04, 0.04), Color("f4e6d0", DormStage.FABRIC), 4, 8)
	for ex in [-1.0, 1.0]:
		kc.cone(Vector3(0.19 + 0.04 * ex, 0.18, 0.1 + 0.05 * ex), 0.035, 0.07, fur_d, 6)
	# the tail wrapped round the front
	for ti in 6:
		var ta := -0.4 + 0.4 * float(ti)
		kc.soft_blob(Vector3(-0.02 + cos(ta) * 0.22, 0.04, 0.12 + sin(ta) * 0.1), Vector3(0.05, 0.035, 0.05), fur_d if ti == 5 else fur, 3, 8)
	var cm := _node(kc, Vector3.ZERO, mat, "CatBody")
	_cat.add_child(cm)
	add_child(_cat)
	_apply_lamp()


## The room dims with the lamp: `prop` of `obj` falls to `off_factor` of
## its value while the lamp is off.
func dim_with(obj: Object, prop: String, off_factor: float) -> void:
	_dims.append([obj, prop, float(obj.get(prop)), off_factor])
	_apply_lamp()


## How hard someone is pressing the couch down this frame (HubWalk).
func couch_bounce(press: float) -> void:
	_press = clampf(press, 0.0, 1.5)


## The leaves shake (someone ducked in or jumped out).
func rustle() -> void:
	_rustle = 1.0


func set_lamp(on: bool, animate: bool = true) -> void:
	if on == lamp_on and animate:
		return
	lamp_on = on
	if not animate:
		_lamp_k = 1.0 if on else 0.0
		_flick = 0.0
	elif on and not reduced:
		_flick = 0.24
	if animate:
		Sfx.play("click", to_global(LAMP_SHADE), -4.0)
	_apply_lamp()


func _apply_lamp() -> void:
	var k := _lamp_k
	if _flick > 0.0:
		# coming on: a quick stutter, then steady
		k *= 0.25 if fmod(_flick, 0.08) < 0.03 else 1.0
	if is_instance_valid(_light):
		_light.light_energy = LAMP_ENERGY * k
		_light.visible = k > 0.01
	_shade_mat.set_shader_parameter("emission_boost", 1.6 * k)
	for d in _dims:
		if is_instance_valid(d[0]):
			(d[0] as Object).set(String(d[1]), float(d[2]) * lerpf(float(d[3]), 1.0, k))
	for e in _pools:
		var pm: MeshInstance3D = e[0]
		if is_instance_valid(pm):
			(pm.material_override as ShaderMaterial).set_shader_parameter("intensity", float(e[1]) * k)
			pm.visible = k > 0.01


## Is the lamp's light showing (tests)?
func lamp_lit() -> bool:
	return _lamp_k > 0.5


func _process(delta: float) -> void:
	_t += delta
	# the lamp eases between on and off in a tenth of a second
	var want := 1.0 if lamp_on else 0.0
	if not is_equal_approx(_lamp_k, want) or _flick > 0.0:
		_lamp_k = move_toward(_lamp_k, want, delta / 0.1)
		_flick = maxf(0.0, _flick - delta)
		_apply_lamp()
	# the cushions: a spring toward the press (it overshoots a little coming
	# back up, so the couch visibly bounces)
	if reduced:
		_sq = _press
		_sq_v = 0.0
	else:
		_sq_v += ((_press - _sq) * 260.0 - _sq_v * 14.0) * delta
		_sq += _sq_v * delta
	var s := clampf(_sq, -0.4, 1.6)
	# (build 21) only down and a touch forward: growing sideways pushed the
	# cushions into the arms, and tilting the pillows pushed them into the
	# back
	_cushions.scale = Vector3(1.0, 1.0 - SQUASH * s, 1.0 + 0.02 * maxf(s, 0.0))
	_pillows.position = COUCH_C + Vector3(0, -0.2 * SQUASH * s, 0)
	# the plant
	if _rustle > 0.0:
		_rustle = maxf(0.0, _rustle - delta / 0.75)
		var w := _rustle * _rustle * (0.35 if reduced else 1.0)
		_plant.rotation = Vector3(sin(_t * 31.0) * 0.07 * w, sin(_t * 7.0) * 0.1 * w, sin(_t * 27.0 + 1.0) * 0.09 * w)
		_plant.scale = Vector3.ONE * (1.0 + 0.05 * w * sin(_t * 19.0))
	elif _plant.rotation != Vector3.ZERO:
		_plant.rotation = Vector3.ZERO
		_plant.scale = Vector3.ONE
	# the cat breathes
	if not reduced:
		var br := sin(_t * 2.1)
		_cat.scale = Vector3(1.0 + 0.012 * br, 1.0 + 0.035 * br, 1.0 + 0.012 * br) * CAT_SCALE


## How far the seat is pressed down right now (m): the bouncer's feet sit
## on the cushion, not in the air above it.
func seat_drop() -> float:
	return 0.2 * SQUASH * clampf(_sq, 0.0, 1.6)
