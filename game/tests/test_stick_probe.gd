extends RefCounted
## V7 stick-drift probe: a measurement, not a pass/fail test (the asserted
## behaviour lives in test_stick_drift.gd).  Runs only with STICK_PROBE=1
## (tools/stick_probe.sh).  A Practice round on a phone-shaped canvas
## (1559x720 = 812x375 pt), bots idle, the runner placed on the longest clear
## straight on campus; scripted touches are parsed by Input exactly as iOS
## delivers them and reach the real TouchControls -> Controls ->
## MatchController -> sim path and the real FollowCamera.  One line per case:
##   d0     stick output right after touchdown (before any drag)
##   lat    mean |local x| / mean |local y| while held
##   dev    sideways distance from the starting line at the end (m)
##   peak   largest sideways distance (m)
##   yaw    camera yaw change without any look input (deg)
##   head   travel heading change, start to end (deg)
##   fwd    distance along the line (m)
##   stop   ticks from lifting the finger until the command and speed are 0
## Probe values are emulated touches on desktop Linux, not device input.
var t
var mc: MatchController
var _saved := {}
var R := 92.0
var zone := Rect2()
var corridor := {}
var mirrored := false
var out: Array[String] = []


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


func _touch(i: int, at: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = at
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _drag(i: int, from: Vector2, to: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = i
	e.position = to
	e.relative = to - from
	e.screen_relative = to - from
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _begin(p_mirrored: bool) -> void:
	mirrored = p_mirrored
	_saved = {"device": Controls.device, "size": t.get_tree().root.size, "emu": Input.emulate_touch_from_mouse,
		"layout": Save.get_setting("touch_layout", "standard"), "layout2": Save.get_setting("touch_layout_v2", null),
		"stick": Save.get_setting("stick_mode", "dynamic")}
	Save.set_setting("touch_layout", "mirrored" if mirrored else "standard")
	Save.set_setting("touch_layout_v2", null)
	Save.set_setting("stick_mode", "dynamic")
	Controls.device = "touch"
	Input.emulate_touch_from_mouse = false
	t.get_tree().root.size = Vector2i(1559, 720)
	t.get_tree().root.notification(Window.NOTIFICATION_WM_MOUSE_ENTER)
	for c in t.get_tree().root.get_children():
		if c is BootCurtain:
			c.queue_free()
	if App.screen and is_instance_valid(App.screen):
		App.screen.queue_free()
	App.screen = null
	MatchController.drop_campus_cache()
	var s := NetSession.new()
	t.add_child(s)
	s.start_offline("u-probe", "Probe", {}, "runner")
	var info := {}
	s.match_starting.connect(func(i: Dictionary) -> void: info.merge(i, true), CONNECT_ONE_SHOT)
	s.host_start_match(5150)
	mc = MatchController.new()
	mc.setup(s, info, {"quality": 0, "staged": false})
	t.add_child(mc)
	for i in 1800:
		await t.get_tree().physics_frame
		if mc.prepared and mc.sim.phase == TC.Phase.PLAYING:
			break
	mc.sim.bots.clear()          # bots stand still, and nothing parked is in the way
	for bp: SimPlayer in mc.sim.players:
		if bp.is_bot:
			bp.body.collision_layer = 0
	for c: SimCart in mc.sim.carts:
		c.body.collision_layer = 0
	await _frames(4)
	R = mc.touch.surface.router.stick_radius
	zone = mc.touch.surface.router.zone()
	if corridor.is_empty():
		corridor = _find_corridor()


func _end() -> void:
	var s: Variant = mc.session
	mc.queue_free()
	if is_instance_valid(s):
		(s as Node).queue_free()
	await _frames(3)
	MatchController.drop_campus_cache()
	Controls.device = _saved["device"]
	Input.emulate_touch_from_mouse = _saved["emu"]
	Save.set_setting("touch_layout", _saved["layout"])
	Save.set_setting("touch_layout_v2", _saved["layout2"])
	Save.set_setting("stick_mode", _saved["stick"])
	t.get_tree().root.size = _saved["size"]


## The longest straight on campus whose 5 m wide strip is open ground.
func _find_corridor() -> Dictionary:
	var ng := NavGrid.shared(CampusLayout.shared())
	var g := ng.foot
	var best := {"len": 0.0}
	var b := CampusLayout.BOUNDS
	var y := b.position.y + 6.0
	while y < b.end.y - 6.0:
		var x := b.position.x + 6.0
		while x < b.end.x - 6.0:
			for k in 24:
				var yaw := TAU * float(k) / 24.0
				var d := Vector2(-sin(yaw), -cos(yaw))
				var n := Vector2(-d.y, d.x)
				var L := 0.0
				while L < 110.0:
					var ok := true
					for w in [-2.5, -1.25, 0.0, 1.25, 2.5]:
						var c := ng.to_cell(Vector2(x, y) + d * L + n * w)
						if not g.is_in_boundsv(c) or g.is_point_solid(c):
							ok = false
							break
					if not ok:
						break
					L += 1.0
				if L > float(best["len"]):
					var clear := _clear_length(Vector2(x, y), d, n, L)
					if clear > float(best["len"]):
						best = {"len": clear, "start": Vector2(x, y), "yaw": yaw}
			x += 5.0
		y += 5.0
	return best


## Physics check of a strip the nav grid calls open (posts, benches and
## low props are not all on the grid): spheres swept along it at shin and
## chest height, 3 m either side of the line, overlapping (no gaps).
func _clear_length(s: Vector2, d: Vector2, n: Vector2, L: float) -> float:
	var ss := mc.get_world_3d().direct_space_state
	var sph := SphereShape3D.new()
	sph.radius = 0.55
	var best := L
	for w in [-3.0, -2.0, -1.0, 0.0, 1.0, 2.0, 3.0]:
		for h in [0.6, 1.2]:
			var a: Vector2 = s + n * w
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = sph
			q.transform = Transform3D(Basis.IDENTITY, Vector3(a.x, h, a.y))
			q.motion = Vector3(d.x, 0.0, d.y) * L
			q.collision_mask = TC.L_WORLD
			var r := ss.cast_motion(q)
			if r.size() == 2 and r[0] < 1.0:
				best = minf(best, L * float(r[0]) - 1.0)
	return best


func _place() -> void:
	var p := mc.sim.player(mc.local_slot)
	var s: Vector2 = corridor["start"]
	var yaw: float = corridor["yaw"]
	var ground := 0.05
	var ss := p.body.get_world_3d().direct_space_state
	var hit := ss.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(s.x, 30.0, s.y), Vector3(s.x, -10.0, s.y), TC.L_WORLD))
	if not hit.is_empty():
		ground = (hit["position"] as Vector3).y + 0.05
	p.body.global_position = Vector3(s.x, ground, s.y)
	p.vel = Vector3.ZERO
	p.body.velocity = Vector3.ZERO
	p.yaw = yaw
	p.sprint = 1.0
	p.clear_history()
	mc.camera.snap_to(p.body.global_position, yaw)
	mc.camera.pitch = 0.32
	mc.camera.set("_manual_t", 10.0)   # no recent camera input: recentering may act at once


## One scripted gesture.  `path` maps time (s) -> stick-finger offset from
## the touchdown point in canvas units.  Extra fingers come from `extra`.
func _case(name: String, at: Vector2, secs: float, path: Callable, recenter := true, extra := Callable()) -> Dictionary:
	_place()
	mc.camera.auto_recenter = recenter
	Controls.reset_touch()
	await t.get_tree().physics_frame
	await t.get_tree().physics_frame
	var p := mc.sim.player(mc.local_slot)
	var p0 := p.body.global_position
	var yaw0: float = corridor["yaw"]
	var fwd := Vector2(-sin(yaw0), -cos(yaw0))
	var nrm := Vector2(-fwd.y, fwd.x)
	var cam0 := mc.camera.yaw
	_touch(0, at, true)
	await t.get_tree().physics_frame
	var d0 := Controls.touch_move.length()
	var r := mc.touch.surface.router
	var logical0: Vector2 = r.get("stick_origin") if r.get("stick_origin") != null else r.stick_center
	var visual0: Vector2 = r.stick_center
	var last := at
	var sx := 0.0
	var sy := 0.0
	var peak := 0.0
	var tt := 0.0
	var n := int(secs * 60.0)
	var head_start := INF
	var rel_sum := 0.0           # travel direction relative to the camera, second half (+ = right)
	var rel_n := 0
	var yaw_min := cam0
	var yaw_max := cam0
	for i in n:
		tt += 1.0 / 60.0
		var to: Vector2 = at + (path.call(tt) as Vector2)
		if to != last:
			_drag(0, last, to)
			last = to
		if extra.is_valid():
			extra.call(tt)
		await t.get_tree().physics_frame
		sx += absf(Controls.touch_move.x)
		sy += absf(Controls.touch_move.y)
		var rel := Vector2(p.body.global_position.x - p0.x, p.body.global_position.z - p0.z)
		peak = maxf(peak, absf(rel.dot(nrm)))
		var hv := Vector2(p.vel.x, p.vel.z)
		if head_start == INF and hv.length() > 2.0 and i > 30:
			head_start = atan2(-hv.x, -hv.y)
		if OS.get_environment("STICK_TRACE") != "" and name.begins_with(OS.get_environment("STICK_TRACE")) and i % 30 == 0:
			var rt: Object = mc.touch.surface.router
			var col := p.body.get_last_slide_collision()
			if col != null:
				var co := col.get_collider() as Node
				print("TRACE   hit %s layer=%d at %s" % [co.get_path() if co else "?", (co as CollisionObject3D).collision_layer if co is CollisionObject3D else -1, str(col.get_position())])
			print("TRACE %s t=%.1f mv=%s spd=%.2f pos=%s owners=%s stickpos=%s origin=%s" % [name.substr(0, 3), tt, str(Controls.touch_move), Vector2(p.vel.x, p.vel.z).length(), str(rel.round()), str(rt.owners), str(rt.stick_pos), str(rt.get("stick_origin"))])
		if i > n / 2 and hv.length() > 1.0:
			rel_sum += angle_difference(-mc.camera.yaw, -atan2(-hv.x, -hv.y))
			rel_n += 1
		yaw_min = minf(yaw_min, mc.camera.yaw)
		yaw_max = maxf(yaw_max, mc.camera.yaw)
	var rel_end := Vector2(p.body.global_position.x - p0.x, p.body.global_position.z - p0.z)
	var hv_end := Vector2(p.vel.x, p.vel.z)
	var head_end := atan2(-hv_end.x, -hv_end.y) if hv_end.length() > 0.5 else head_start
	var yaw_end := mc.camera.yaw
	var rel_deg := rad_to_deg(rel_sum / maxi(1, rel_n))
	var end_note := "rel=%+6.1f st=%d spd=%.1f y=%+.2f sprint=%.2f" % [rel_deg, p.state, Vector2(p.vel.x, p.vel.z).length(), p.body.global_position.y - p0.y, p.sprint]
	_touch(0, last, false)
	var stop := -1
	for i in 60:
		await t.get_tree().physics_frame
		var cmd_zero := Controls.touch_move == Vector2.ZERO and Controls.get_move() == Vector2.ZERO
		if cmd_zero and Vector2(p.vel.x, p.vel.z).length() < 0.3:
			stop = i + 1
			break
	var row := {"case": name, "d0": d0, "lat": sx / maxf(sy, 1e-6),
		"dev": rel_end.dot(nrm), "peak": peak, "yaw": rad_to_deg(angle_difference(cam0, yaw_end)),
		"yawspan": rad_to_deg(yaw_max - yaw_min),
		"head": rad_to_deg(angle_difference(head_start, head_end)) if head_start != INF else 0.0,
		"fwd": rel_end.dot(fwd), "stop": stop, "y": p.body.global_position.y - p0.y,
		"origin": logical0 - at, "visual": visual0 - at}
	out.append("%-44s d0=%.2f lat=%.3f dev=%+6.2f peak=%5.2f yaw=%+7.1f head=%+7.1f fwd=%5.1f stop=%d  origin-touch=%s visual-touch=%s  %s" % [
		name, d0, row["lat"], row["dev"], peak, row["yaw"], row["head"], row["fwd"], stop, str((logical0 - at).round()), str((visual0 - at).round()), end_note])
	return row


func _straight(tt: float) -> Vector2:
	return Vector2(0, -R * minf(1.0, tt / 0.15))


func test_stick_probe() -> void:
	if OS.get_environment("STICK_PROBE") == "":
		return
	await _begin(false)
	out.append("corridor %.0f m, R=%.0f, zone=%s, view=%s, fps=%d" % [corridor["len"], R, str(zone), str(mc.touch.surface.size), Engine.physics_ticks_per_second])
	var centre := zone.get_center()
	var corner := Vector2(zone.position.x + 0.3 * R, zone.end.y - 0.3 * R)
	var left_mid := Vector2(zone.position.x + 0.3 * R, zone.get_center().y)
	var full := func(tt: float) -> Vector2: return _straight(tt)
	var half := func(tt: float) -> Vector2: return _straight(tt) * 0.6
	# natural thumb: forward with a small rolling sideways wobble (zero mean)
	var wobble := func(tt: float) -> Vector2:
		return _straight(tt) + Vector2(R * (0.07 * sin(TAU * 1.3 * tt) + 0.035 * sin(TAU * 3.1 * tt + 1.0)), 0)
	# a thumb pivoting on its base: forward with a constant 6 degree lean plus wobble
	var lean := func(tt: float) -> Vector2:
		return _straight(tt).rotated(deg_to_rad(6.0)) + Vector2(R * 0.04 * sin(TAU * 1.3 * tt), 0)
	var long_push := func(tt: float) -> Vector2:
		var reach := clampf(tt / 0.6, 0.0, 1.0) * 2.4
		if tt > 3.0:
			reach = lerpf(2.4, 0.9, clampf((tt - 3.0) / 0.5, 0.0, 1.0))
		return Vector2(R * 0.05 * sin(TAU * 1.1 * tt), -R * reach)
	var edge_slide := func(tt: float) -> Vector2:
		var base := Vector2(0, -R * 1.9 * minf(1.0, tt / 0.4))
		return base + Vector2(R * 0.5 * sin(TAU * 0.4 * tt), 0)
	await _case("1 centre, exact vertical", centre, 6.0, full)
	await _case("1b centre, exact vertical, recenter off", centre, 6.0, full, false)
	await _case("1c centre, 60% vertical (jog)", centre, 6.0, half)
	await _case("2 bottom-left corner, exact vertical", corner, 6.0, full)
	await _case("2b left edge mid, exact vertical", left_mid, 6.0, full)
	await _case("3 centre, forward + wobble", centre, 6.0, wobble)
	await _case("3b centre, forward + 6deg lean + wobble", centre, 6.0, lean)
	await _case("3c 6deg lean, recenter off", centre, 6.0, lean, false)
	await _case("4 long push past base-follow, ease back", centre, 6.0, long_push)
	await _case("4b push along the rim side to side", centre, 6.0, edge_slide)
	await _case("5 forward 15 s, 3deg lean, recenter on", centre, 15.0,
		func(tt: float) -> Vector2: return _straight(tt).rotated(deg_to_rad(3.0)))
	await _case("5b forward 15 s, 3deg lean, recenter off", centre, 15.0,
		func(tt: float) -> Vector2: return _straight(tt).rotated(deg_to_rad(3.0)), false)
	# a spare finger resting in the stick zone: touch-screen jitter (+-1.5 px)
	# with a slow 0.05 px/frame creep; then one that rolls 0.4 px/frame
	for creep in [0.05, 0.4]:
		var spare_at := centre + Vector2(R * 1.4, R * 0.8)
		var spare := [spare_at, false, 0]
		var spare_fn := func(tt: float) -> void:
			if not spare[1] and tt > 0.5:
				_touch(1, spare_at, true)
				spare[1] = true
			elif spare[1] and tt < 3.0:
				spare[2] = int(spare[2]) + 1
				var j := 1.5 if int(spare[2]) % 2 == 0 else -1.5
				var to: Vector2 = spare[0] + Vector2(creep + j, 0.25 * creep - j * 0.5)
				_drag(1, spare[0], to)
				spare[0] = to
			elif spare[1] and tt >= 3.0 and tt < 3.02:
				_touch(1, spare[0], false)
		await _case("6 forward + spare finger, jitter, creep %.2f px/f" % creep, centre, 4.0, full, true, spare_fn)
	# the base-follow policy: as shipped, and with the base never following
	var rr: Object = mc.touch.surface.router
	var fa: Variant = rr.get("follow_at")
	if fa != null:
		rr.set("follow_at", 99.0)
		await _case("4c long push, base never follows (comparison)", centre, 6.0, long_push)
		rr.set("follow_at", fa)
	# a drifting pad (left stick 0.25 right) while the touch stick is held in its dead zone
	Controls.active_joy = 0
	var jm := InputEventJoypadMotion.new()
	jm.device = 0
	jm.axis = JOY_AXIS_LEFT_X
	jm.axis_value = 0.25
	Input.parse_input_event(jm)
	var jl := InputEventJoypadMotion.new()
	jl.device = 0
	jl.axis = JOY_AXIS_RIGHT_X
	jl.axis_value = 0.2
	Input.parse_input_event(jl)
	Input.flush_buffered_events()
	await _case("7 thumb resting in dead zone + drifting pad", centre, 3.0, func(tt: float) -> Vector2: return Vector2(0, -R * 0.05))
	await _case("7b forward + drifting pad", centre, 3.0, full)
	jm.axis_value = 0.0
	jl.axis_value = 0.0
	Input.parse_input_event(jm)
	Input.parse_input_event(jl)
	Input.flush_buffered_events()
	Controls.active_joy = -1
	# deliberate steering stays as asked (rel = travel direction off the camera's forward)
	for a in [15.0, 45.0, 90.0, 180.0]:
		await _case("8 deliberate %d deg (stick angle)" % int(a), centre, 4.0,
			func(tt: float) -> Vector2: return _straight(tt).rotated(deg_to_rad(a)), false)
	await _case("8e left-right flicks every 0.5 s", centre, 4.0,
		func(tt: float) -> Vector2: return Vector2(R if int(tt * 2.0) % 2 == 0 else -R, 0) * minf(1.0, tt / 0.1), false)
	await _case("8f 15 deg held, recenter on (camera follows)", centre, 4.0,
		func(tt: float) -> Vector2: return _straight(tt).rotated(deg_to_rad(15.0)))
	await _end()
	await _begin(true)
	var corner_m := Vector2(zone.end.x - 0.3 * R, zone.end.y - 0.3 * R)
	await _case("2m mirrored, bottom-right corner, exact vertical", corner_m, 6.0, full)
	await _case("1m mirrored, centre, exact vertical", zone.get_center(), 6.0, full)
	await _end()
	print("STICKPROBE BEGIN")
	for l in out:
		print("STICKPROBE ", l)
	print("STICKPROBE END")
