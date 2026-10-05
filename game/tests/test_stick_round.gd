extends RefCounted
## V7 forward drift, end to end: real touches parsed by Input at rendered
## coordinates on a phone-shaped canvas (1559x720 = 812x375 pt), through
## TouchControls -> Controls -> MatchController -> sim and the real
## FollowCamera, in a Practice round on a clear straight of the campus (bots
## idle).  Written against the public match state only, so the same file
## runs on the pre-fix build, where it fails (a corner touchdown ran 31 m
## sideways; a 6 degree lean swung the camera 100 degrees).  The online part
## sends exactly straight commands from a guest over the loopback rig and
## checks neither prediction nor host correction bends the path.
var t
var mc: MatchController
var _saved := {}
var corridor := {}


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


func _begin(mirrored: bool) -> void:
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
	s.start_offline("u-stick", "Tester", {}, "runner")
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
	mc.sim.bots.clear()
	for bp: SimPlayer in mc.sim.players:
		if bp.is_bot:
			bp.body.collision_layer = 0
	for c: SimCart in mc.sim.carts:
		c.body.collision_layer = 0
	await _frames(4)
	if corridor.is_empty():
		corridor = _find_corridor(mc.get_world_3d(), 45.0)


func _end() -> void:
	_touch(0, Vector2.ZERO, false)
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


## The first straight of at least `want` metres whose 6 m wide strip is open
## on the nav grid and clear of physics (posts and props included).
static func _find_corridor(world: World3D, want: float) -> Dictionary:
	var ng := NavGrid.shared(CampusLayout.shared())
	var g := ng.foot
	var ss := world.direct_space_state
	var sph := SphereShape3D.new()
	sph.radius = 0.55
	var b := CampusLayout.BOUNDS
	var y := b.position.y + 6.0
	while y < b.end.y - 6.0:
		var x := b.position.x + 6.0
		while x < b.end.x - 6.0:
			for k in 12:
				var yaw := TAU * float(k) / 12.0
				var d := Vector2(-sin(yaw), -cos(yaw))
				var n := Vector2(-d.y, d.x)
				var ok := true
				var L := 0.0
				while ok and L <= want:
					for w in [-3.0, -1.5, 0.0, 1.5, 3.0]:
						var c := ng.to_cell(Vector2(x, y) + d * L + n * w)
						if not g.is_in_boundsv(c) or g.is_point_solid(c):
							ok = false
							break
					L += 1.0
				if not ok:
					continue
				for w in [-3.0, -2.0, -1.0, 0.0, 1.0, 2.0, 3.0]:
					for h in [0.6, 1.2]:
						var q := PhysicsShapeQueryParameters3D.new()
						q.shape = sph
						q.transform = Transform3D(Basis.IDENTITY, Vector3(x + n.x * w, h, y + n.y * w))
						q.motion = Vector3(d.x, 0.0, d.y) * want
						q.collision_mask = TC.L_WORLD
						var r := ss.cast_motion(q)
						if r.size() == 2 and r[0] < 1.0:
							ok = false
				if ok:
					return {"start": Vector2(x, y), "yaw": yaw, "len": want}
			x += 7.0
		y += 7.0
	return {}


func _place() -> void:
	var p := mc.sim.player(mc.local_slot)
	var s: Vector2 = corridor["start"]
	var yaw: float = corridor["yaw"]
	var ground := 0.05
	var hit := p.body.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(Vector3(s.x, 30.0, s.y), Vector3(s.x, -10.0, s.y), TC.L_WORLD))
	if not hit.is_empty():
		ground = (hit["position"] as Vector3).y + 0.05
	p.body.global_position = Vector3(s.x, ground, s.y)
	p.vel = Vector3.ZERO
	p.body.velocity = Vector3.ZERO
	p.yaw = yaw
	p.clear_history()
	mc.camera.snap_to(p.body.global_position, yaw)
	mc.camera.set("_manual_t", 10.0)   # no recent camera input: recentering may act at once
	Controls.reset_touch()


## Holds a scripted stick gesture; returns {d0, dev, yaw, fwd}.
func _run(at: Vector2, secs: float, path: Callable) -> Dictionary:
	_place()
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
	var last := at
	var peak := 0.0
	for i in int(secs * 60.0):
		var to: Vector2 = at + (path.call(float(i + 1) / 60.0) as Vector2)
		if to != last:
			_drag(0, last, to)
			last = to
		await t.get_tree().physics_frame
		var rel := Vector2(p.body.global_position.x - p0.x, p.body.global_position.z - p0.z)
		peak = maxf(peak, absf(rel.dot(nrm)))
	var rel_end := Vector2(p.body.global_position.x - p0.x, p.body.global_position.z - p0.z)
	var out := {"d0": d0, "dev": peak, "yaw": rad_to_deg(angle_difference(cam0, mc.camera.yaw)), "fwd": rel_end.dot(fwd)}
	# lifting the thumb stops the runner on the next update
	_touch(0, last, false)
	await t.get_tree().physics_frame
	out["released_move"] = Controls.get_move().length()
	var ticks := 0
	while ticks < 60 and Vector2(p.vel.x, p.vel.z).length() > 0.3:
		await t.get_tree().physics_frame
		ticks += 1
	out["stop_ticks"] = ticks
	return out


func test_corner_touchdown_runs_straight_both_layouts() -> void:
	for mirrored in [false, true]:
		await _begin(mirrored)
		t.check(not corridor.is_empty(), "a clear straight was found")
		if corridor.is_empty():
			await _end()
			return
		var r: Object = mc.touch.surface.router
		var R: float = r.get("stick_radius")
		var z: Rect2 = r.call("zone")
		var corner := Vector2(z.end.x - 0.3 * R if mirrored else z.position.x + 0.3 * R, z.end.y - 0.3 * R)
		var tag := "mirrored" if mirrored else "standard"
		var o: Dictionary = await _run(corner, 3.0, func(tt: float) -> Vector2: return Vector2(0, -R * minf(1.0, tt / 0.15)))
		t.check(float(o["d0"]) < 0.01, "%s: a thumb landing near the corner doesn't move the runner (%.2f)" % [tag, o["d0"]])
		t.check(float(o["dev"]) < 0.25, "%s: an exact vertical push runs straight (%.2f m sideways)" % [tag, o["dev"]])
		t.check(float(o["fwd"]) > 15.0, "%s: and forward (%.1f m)" % [tag, o["fwd"]])
		t.check(absf(float(o["yaw"])) < 0.5, "%s: the camera stays put (%.2f deg)" % [tag, o["yaw"]])
		t.eq(float(o["released_move"]), 0.0, "%s: lifting the thumb zeroes the command on the next tick" % tag)
		t.check(int(o["stop_ticks"]) <= 20, "%s: and the runner stops promptly (%d ticks)" % [tag, o["stop_ticks"]])
		await _end()


func test_a_thumb_lean_does_not_curve_the_run() -> void:
	await _begin(false)
	if corridor.is_empty():
		t.check(false, "a clear straight was found")
		await _end()
		return
	var r: Object = mc.touch.surface.router
	var R: float = r.get("stick_radius")
	var centre: Vector2 = (r.call("zone") as Rect2).get_center()
	# forward with a 5 degree lean and a little wobble, recentering on
	var lean := func(tt: float) -> Vector2:
		return Vector2(0, -R * minf(1.0, tt / 0.15)).rotated(deg_to_rad(5.0)) + Vector2(R * 0.03 * sin(TAU * 1.3 * tt), 0)
	var o: Dictionary = await _run(centre, 5.0, lean)
	t.check(absf(float(o["yaw"])) < 2.0, "a held lean doesn't swing the camera round (%.1f deg in 5 s)" % o["yaw"])
	t.check(float(o["dev"]) < 1.0, "the run stays straight (%.2f m sideways over %.0f m)" % [o["dev"], o["fwd"]])
	await _end()


func test_online_straight_commands_stay_straight() -> void:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(30, 5, 0.0, 1, ["patrol", "runner"])
	var c0: NetSession = rig.clients[0]
	await rig.wait_until(func() -> bool: return c0.local_slot >= 0 and rig.host.human_count() == 2, 300)
	c0.set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.can_start(), 200)
	rig.host.host_start_match(31)
	await rig.wait_until(func() -> bool: return rig.host.sim != null and rig.host.sim.phase == TC.Phase.PLAYING \
		and rig.mc_of(c0) != null and rig.mc_of(c0).prepared, 1500)
	var hm := rig.host_mc()
	var g := rig.mc_of(c0)
	var cor := _find_corridor(hm.get_world_3d(), 30.0)
	t.check(not cor.is_empty(), "a clear straight for the guest")
	if cor.is_empty():
		rig.teardown()
		return
	hm.sim.bots.clear()
	for bp: SimPlayer in hm.sim.players:
		if bp.id != c0.local_slot:
			bp.body.collision_layer = 0
	var slot := c0.local_slot
	var yaw: float = cor["yaw"]
	var d := Vector2(-sin(yaw), -cos(yaw))
	var n := Vector2(-d.y, d.x)
	var hp := hm.sim.player(slot)
	var s: Vector2 = cor["start"]
	hp.body.global_position = Vector3(s.x, 0.1, s.y)
	hp.vel = Vector3.ZERO
	hp.body.velocity = Vector3.ZERO
	hp.yaw = yaw
	hp.clear_history()
	g.input_source = func(_m: MatchController) -> InputCmd: return InputCmd.new()
	await rig.frames(45)            # the guest's prediction takes the new spot
	g.input_source = func(_m: MatchController) -> InputCmd:
		var c := InputCmd.new()
		c.move = d
		c.cam_yaw = yaw
		return c
	var h0 := hp.body.global_position
	var g0: Vector3 = g._player_rs(slot).get("pos", Vector3.ZERO)
	var hpeak := 0.0
	var gpeak := 0.0
	for i in 150:
		await rig.frames(1)
		var hr := Vector2(hp.body.global_position.x - h0.x, hp.body.global_position.z - h0.z)
		hpeak = maxf(hpeak, absf(hr.dot(n)))
		var gp: Vector3 = g._player_rs(slot).get("pos", g0)
		gpeak = maxf(gpeak, absf(Vector2(gp.x - g0.x, gp.z - g0.z).dot(n)))
	var hfwd := Vector2(hp.body.global_position.x - h0.x, hp.body.global_position.z - h0.z).dot(d)
	t.check(hfwd > 8.0, "the guest ran forward on the host (%.1f m)" % hfwd)
	t.check(hpeak < 0.25, "the host's authoritative path is straight (%.2f m sideways)" % hpeak)
	t.check(gpeak < 0.25, "and so is the guest's own predicted path, corrections included (%.2f m)" % gpeak)
	rig.teardown()
	await t.get_tree().process_frame
	await t.get_tree().process_frame
