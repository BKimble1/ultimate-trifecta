extends "res://src/dev/capture_pass8_match.gd"
## App Store screenshots: gameplay (development only; src/dev is never
## exported).  A real practice round (created by capture.gd for
## --capture=store_match with --autoplay=runner or =patrol) staged into a
## good moment with the Pass 8 match driver's tools, then played by the
## game itself: the driver places players and holds the local player's
## stick (MatchController.input_source, the same InputCmd a thumb or a pad
## makes); the simulation moves everyone, a Night Watch bot chases on its
## own brain, the splash and the HUD are the game's.  Nothing is stamped
## (capture.gd's snap with --store-shot saves RGB PNGs).
##
##   --store-part=splash  (runner, --seed=2: the fountain is one of the
##       round's waters) the local runner sprints up the central path and
##       jumps into Founders' Fountain while a Night Watch comes round it;
##       frames on the approach and through the splash
##   --store-part=cart    (Night Watch) the local Night Watch drives a golf
##       cart along Library Lane, closing on a fleeing runner; frames as the
##       gap closes
##
##   tools/capture_store_screenshots.sh OUT_DIR [iphone ipad]

class ScriptedBrain:
	extends RefCounted
	## a bot's stick held by the driver (same InputCmd shape as BotBrain.think)
	var fn: Callable

	func think(_sim: MatchSim, p: SimPlayer) -> InputCmd:
		return fn.call(p)


## the splash: where the chasing Night Watch starts (x, z), where the runner
## jumps, and whether it dives (a second press in the air)
const WATCH_FROM := Vector2(13.0, 25.0)
const JUMP_Z := 31.4
const DIVE := true

var store_part := "splash"
var _jumped := false
var _dived := false
var _jump_t := -1.0
var _splash_t := -1.0
var _shots_taken: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--store-part="):
			store_part = a.get_slice("=", 1)
	part = "store_" + store_part
	_at = 2.0
	# the game's Standard graphics (the evidence driver uses Battery Saver)
	Save.set_setting("quality", QualityPreset.STANDARD)
	QualityPreset.apply(QualityPreset.STANDARD)
	# the iconic look: striped pajamas, nightcap, bunny slippers (the
	# default a new player starts in), on a fictional player
	Save.data["cosmetic"] = Cosmetics.sanitize(Cosmetics.DEFAULT.duplicate())


## As the base driver's, but a step that isn't ready is asked again on the
## next frame (the moments here are a fraction of a second apart).
func _process(delta: float) -> void:
	_t += delta
	if _hold.is_valid():
		_hold.call()
	if _t < _at:
		return
	var steps := _steps()
	if _step >= steps.size():
		return
	var delay: float = (steps[_step] as Callable).call()
	if delay < 0.0:
		return
	_step += 1
	_at = _t + delay


func _steps() -> Array:
	match store_part:
		"cart":
			return [_wait_round, _cart_stage, _cart_wait, _quit]
	return [_wait_round, _splash_stage, _splash_wait, _quit]


## A Night Watch bot that took a golf cart at the shed gets out (as the
## simulation's own exit leaves a driver: on foot, the cart empty).
func _on_foot(p: SimPlayer) -> void:
	var mc := _mc()
	if p.cart_id >= 0:
		var c: SimCart = mc.sim.carts[p.cart_id]
		c.occupant = -1
		c.exiting = false
		c.speed = 0.0
		p.cart_id = -1
	Motor.set_body_enabled(p.body, true)
	p.state = TC.PState.ACTIVE
	p.state_t = 1.0


func _shoot(n: String) -> void:
	if _shots_taken.has(n):
		return
	_shots_taken[n] = true
	cap.call("snap", n)
	var mc := _mc()
	if mc != null:
		var where: Array = []
		for p in mc.sim.players:
			where.append("%d:%s@%s/%d" % [p.id, "W" if p.is_patrol() else "R", str(p.pos().snapped(Vector3.ONE * 0.1)), p.state])
		printerr("STORE %s %s" % [n, " ".join(PackedStringArray(where))])


# ---------------------------------------------------------------- splash
func _splash_stage() -> float:
	var mc := _mc()
	var me := _me()
	var fountain := -1
	for i in mc.layout.waters.size():
		if String(mc.layout.waters[i]["id"]) == "fountain":
			fountain = i
	var ti: int = mc.targets.find(fountain)
	# one water already stamped (not the fountain): this splash makes it 2 of 3
	var done := 0
	me.last_stamp_water = -1
	for i in mc.targets.size():
		if i != ti:
			done = 1 << i
			me.last_stamp_water = int(mc.targets[i])
			break
	me.stamps = done
	mc.last_stamp_water = me.last_stamp_water
	var start := Vector3(0.9, 0.1, 41.0)
	_stand(start, 0.0)
	mc.camera.pitch = 0.24
	# a Night Watch cutting across the plaza from the right, chasing the
	# runner (its stick held by the driver: straight at the runner; one
	# lunge once the runner is in the water, where a tag can't land)
	var w := _first(TC.Role.PATROL)
	var wat := Vector3(WATCH_FROM.x, 0.1, WATCH_FROM.y)
	_on_foot(w)
	_put(w, wat, _yaw_to(wat, start))
	var lunged := {"done": false}
	var wb := ScriptedBrain.new()
	wb.fn = func(pl: SimPlayer) -> InputCmd:
		var cmd := InputCmd.new()
		var r := _me()
		if r == null:
			return cmd
		var d := r.pos() - pl.pos()
		var dir := Vector2(d.x, d.z)
		if dir.length() > 0.8:
			cmd.move = dir.normalized()
		cmd.cam_yaw = atan2(-d.x, -d.z)
		if r.state == TC.PState.SPLASHING and not bool(lunged["done"]) and dir.length() < 4.5:
			lunged["done"] = true
			cmd.held = TC.BTN_TAG
			cmd.pressed = TC.BTN_TAG
		return cmd
	mc.sim.bots[w.id] = wb
	# the other Night Watch well away
	var w2 := _first(TC.Role.PATROL, w.id)
	if w2 != null and w2.cart_id < 0:
		_put(w2, Vector3(-60, 0.1, -40), 0.0)
	# the local stick: straight up the path, jump at the rim, dive
	mc.input_source = func(m: MatchController) -> InputCmd:
		var cmd := InputCmd.new()
		cmd.cam_yaw = m.camera.yaw if m.camera else 0.0
		var p := m.sim.player(m.local_slot)
		if p == null or p.state != TC.PState.ACTIVE or _splash_t >= 0.0:
			return cmd
		cmd.move = Vector2(0, -1)
		if not _jumped and p.pos().z < JUMP_Z:
			_jumped = true
			_jump_t = _t
			cmd.held = TC.BTN_JUMP
			cmd.pressed = TC.BTN_JUMP
		elif _jumped and DIVE and not _dived and p.air_t > 0.12:
			_dived = true
			cmd.held = TC.BTN_JUMP
			cmd.pressed = TC.BTN_JUMP
		return cmd
	return 0.1


func _splash_wait() -> float:
	var me := _me()
	if me == null:
		return -1.0
	var z := me.pos().z
	if _splash_t < 0.0:
		if z < 37.5:
			_shoot("splash_approach_a")
		if z < 34.5:
			_shoot("splash_approach_b")
		if z < 32.4:
			_shoot("splash_approach_c")
		if _jump_t >= 0.0:
			for k in [[0.1, "splash_air_0"], [0.2, "splash_air_1"], [0.3, "splash_air_2"], [0.4, "splash_air_3"]]:
				if _t - _jump_t >= float(k[0]):
					_shoot(String(k[1]))
		if me.state == TC.PState.SPLASHING:
			_splash_t = _t
			_shoot("splash_in_0")
		return -1.0
	var dt := _t - _splash_t
	for k in [[0.12, "splash_in_1"], [0.25, "splash_in_2"], [0.4, "splash_in_3"], [0.6, "splash_in_4"], [0.85, "splash_in_5"]]:
		if dt >= float(k[0]):
			_shoot(String(k[1]))
	if dt < 1.2:
		return -1.0
	return 1.5


# ---------------------------------------------------------------- cart
func _cart_stage() -> float:
	var mc := _mc()
	var me := _me()
	var c: SimCart = mc.sim.carts[0]
	var yaw := -PI * 0.5                        # east along Library Lane
	var at := Vector3(-52.0, c.body.global_position.y, -14.6)
	c.body.global_position = at
	c.body.velocity = Vector3.ZERO
	c.yaw = yaw
	c.body.rotation.y = yaw
	c.speed = 7.0
	c.occupant = me.id
	c.exiting = false
	me.cart_id = c.id
	Motor.set_body_enabled(me.body, false)
	me.state = TC.PState.IN_CART
	me.state_t = 1.0
	mc.camera.snap_to(at, yaw)
	mc.camera.pitch = 0.22
	# two runners ahead, fleeing east on their own sticks (scripted brains)
	var fwd := Vector3(1, 0, 0)
	var placed := 0
	for p in mc.sim.players:
		if not p.is_runner() or p.state != TC.PState.ACTIVE or placed >= 2:
			continue
		var off: Vector3 = [fwd * 12.5 + Vector3(0, 0, 1.0), fwd * 21.0 + Vector3(0, 0, -1.6)][placed]
		var spot := at + off
		spot.y = 0.1
		_put(p, spot, yaw)
		var weave := 0.04 if placed == 0 else -0.03
		var sb := ScriptedBrain.new()
		sb.fn = func(pl: SimPlayer) -> InputCmd:
			var cmd := InputCmd.new()
			cmd.move = Vector2(1.0, weave).normalized()
			cmd.cam_yaw = yaw
			return cmd
		mc.sim.bots[p.id] = sb
		placed += 1
	# the local driver: full throttle, straight
	mc.input_source = func(m: MatchController) -> InputCmd:
		var cmd := InputCmd.new()
		cmd.cam_yaw = m.camera.yaw if m.camera else yaw
		cmd.drive = 1.0
		cmd.held = TC.BTN_ACCEL
		return cmd
	_splash_t = _t
	return 0.1


func _cart_wait() -> float:
	var dt := _t - _splash_t
	for k in [[0.6, "cart_a"], [1.0, "cart_b"], [1.4, "cart_c"], [1.8, "cart_d"], [2.2, "cart_e"]]:
		if dt >= float(k[0]):
			_shoot(String(k[1]))
	if dt < 2.5:
		return -1.0
	return 1.5
