extends Node
## Development-only evidence (src/dev: never exported): the Pass 8 movement
## clips. A real offline Practice round as a runner (NetSession +
## MatchController: the real motor, prediction path, CharacterView, follow
## camera and HUD), the bots parked, then scripted input on the campus's
## longest clear straight (the same lane and input scripts as
## tests/test_p8_movement.gd):
##   sprint   Sprint held for 12 s on a full meter
##   dive     jump -> dive pressed at the best possible rate, Sprint held
## The same file runs on the build-7 checkout for "before". Record with Movie
## Maker at a fixed 30 fps clock (normal speed):
##   tools/gd.sh --path game --write-movie OUT.avi --fixed-fps 30 res://src/dev/movement_reel_p8.tscn -- [--scenarios=sprint,dive]
## (tools/capture_p8_movement.sh OUT NAME [ROOT] records, trims and labels it.)
## Desktop rendering of scripted input, not device footage.

const SCENARIOS := {
	"sprint": ["Sprint held 12 s", 12.0],
	"dive": ["Jump → dive pressed as fast as it goes, Sprint held", 10.0],
}

var scenarios: Array = ["sprint", "dive"]
var mc: MatchController
var session: NetSession
var lane: Array = []
var _moves: GDScript
var _i := -1
var _fn: Callable
var _tick := 0
var _ticks := 0
var _caption: Label
var _sub: Label
var _frame := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scenarios="):
			scenarios = Array(a.get_slice("=", 1).split(","))
	_moves = load("res://tests/test_p8_movement.gd")
	for c in get_tree().root.get_children():
		if c is BootCurtain:
			c.queue_free()
	if App.screen and is_instance_valid(App.screen):
		App.screen.queue_free()
	App.screen = null
	session = NetSession.new()
	add_child(session)
	session.start_offline("u-reel", "Runner", {}, "runner")
	var info := {}
	session.match_starting.connect(func(i: Dictionary) -> void: info.merge(i, true), CONNECT_ONE_SHOT)
	session.host_start_match(5150)
	mc = MatchController.new()
	mc.setup(session, info, {"quality": 1, "staged": false})
	add_child(mc)
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	# low in the frame: the HUD owns the top (round time, waters, map)
	var h := get_viewport().get_visible_rect().size.y
	_caption = _label(layer, 24, h - 124)
	_sub = _label(layer, 18, h - 90)
	_caption.text = "Loading"
	while not (mc.prepared and mc.sim != null and mc.sim.phase == TC.Phase.PLAYING):
		await get_tree().physics_frame
	mc.sim.bots.clear()
	for bp: SimPlayer in mc.sim.players:
		if bp.is_bot:
			bp.body.collision_layer = 0
			bp.body.global_position += Vector3(0, -40, 0)
	for c: SimCart in mc.sim.carts:
		c.body.collision_layer = 0
	var tp = load("res://tests/test_pursuit.gd").new()
	lane = tp._open_lane(mc.sim)
	mc.input_source = _scripted_cmd
	_next()


func _label(layer: CanvasLayer, sz: int, y: float) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_TOP_WIDE)
	l.position = Vector2(0, y)
	layer.add_child(l)
	return l


func _next() -> void:
	_i += 1
	if _i >= scenarios.size():
		_fn = Callable()
		_caption.text = "End"
		_sub.text = ""
		for k in 15:
			await get_tree().process_frame
		get_tree().quit()
		return
	var key: String = scenarios[_i]
	var sc: Array = SCENARIOS[key]
	var a: Vector3 = lane[0]
	var d: Vector2 = lane[1]
	var dir := Vector3(d.x, 0, d.y)
	var yaw := atan2(-d.x, -d.y)
	var p := mc.sim.player(mc.local_slot)
	var start := a - dir * 10.0
	var hit := p.body.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(start + Vector3(0, 30, 0), start - Vector3(0, 10, 0), TC.L_WORLD))
	if not hit.is_empty():
		start.y = (hit["position"] as Vector3).y + 0.05
	p.body.global_position = start
	p.vel = Vector3.ZERO
	p.body.velocity = Vector3.ZERO
	p.yaw = yaw
	p.sprint = 1.0
	p.diving = false
	p.dive_land = 0.0
	p.jump_buf = 0.0
	if "sprint_exhausted" in p:
		p.set("sprint_exhausted", false)
	p.clear_history()
	mc.camera.snap_to(p.body.global_position, yaw)
	mc.camera.set("_manual_t", 10.0)
	_fn = _moves.sprint_hold(d) if key == "sprint" else _moves.dive_chain(d, true)
	_tick = 0
	_ticks = int(float(sc[1]) * 60.0)
	_caption.text = String(sc[0])
	_sub.text = ""
	print("REEL_SCENARIO %s frame %d" % [key, _frame])


func _input_cmd_idle() -> InputCmd:
	var c := InputCmd.new()
	c.cam_yaw = mc.camera.yaw if mc.camera else 0.0
	return c


func _scripted_cmd(_m: Variant = null) -> InputCmd:
	if not _fn.is_valid():
		return _input_cmd_idle()
	var p := mc.sim.player(mc.local_slot)
	var c: InputCmd = _fn.call(mc.sim, p, _tick)
	_tick += 1
	var ex := bool(p.get("sprint_exhausted")) if "sprint_exhausted" in p else false
	_sub.text = "%.1f s · %.1f m/s · meter %d%%%s%s" % [_tick / 60.0, Vector2(p.vel.x, p.vel.z).length(), int(round(p.sprint * 100.0)),
		" · sprinting" if p.sprinting else "", " · exhausted latch" if ex else ""]
	if _tick >= _ticks:
		_next.call_deferred()
	return c


func _process(_delta: float) -> void:
	_frame += 1
