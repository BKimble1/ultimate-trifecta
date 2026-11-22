extends Node
## (build 30) Frames of the basketball in the dorm for review (development
## only; src/dev is never exported): the standing dribble over a bounce,
## each dribble move (crossover, between the legs, behind the back) and the
## shot (gather, dip, set point, release, follow-through), each from a side
## camera and a front three-quarter camera close on the runner (two
## SubViewports on the stage's world, so the menus never cover them).
##
##   xvfb-run -a -s "-screen 0 1020x504x24" tools/gd.sh --fixed-fps 60 \
##     --path game --resolution 956x440 res://src/dev/ball_capture.tscn \
##     -- --capture-dir=DIR [--only=stand,cross,legs,back,shot]
##
## Writes DIR/<sequence>_<camera>_<NN>.png and prints CAPTURE-DONE.  The
## moves are started with BallMoves.request (in play they come from turning:
## a moderate turn, a sharp turn or a stop or start, a reversal).

const NetRigScript := preload("res://tests/net_rig.gd")
const VIEW := Vector2i(520, 520)

var dir := ""
var only := ""
var rig
var stage: DormStage
var lobby: LobbyScreen
var ball: BallSync
var cams: Dictionary = {}     # name -> [SubViewport, Camera3D]
var v: CharacterView


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture-dir="):
			dir = a.get_slice("=", 1)
		elif a.begins_with("--only="):
			only = a.get_slice("=", 1)
	if dir == "":
		dir = "user://ball_capture"
	DirAccess.make_dir_recursive_absolute(dir)
	_run.call_deferred()


func _wanted(s: String) -> bool:
	return only == "" or Array(only.split(",")).has(s)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	await _frames(10)
	# (the first-run Wardrobe behind it would turn the runner to its camera)
	for n in get_tree().root.find_children("*", "CreatorScreen", true, false):
		n.process_mode = Node.PROCESS_MODE_DISABLED
	rig = NetRigScript.new()
	add_child(rig)
	rig.setup(20, 0, 0.0, 0)
	await rig.wait_until(func() -> bool: return rig.host.social.ball.spawned, 300)
	stage = DormStage.new()
	add_child(stage)
	App.stage = stage
	App.session = rig.host
	stage.set_mode("lobby", false)
	lobby = LobbyScreen.new()
	lobby.session = rig.host
	add_child(lobby)
	await _frames(10)
	lobby._set_walk(true)
	await _frames(10)
	ball = rig.host.social.ball
	_place(Vector2(-0.6, 0.6), Vector2(1, 0))
	await _frames(5)
	ball.sim.place(Vector3(lobby.hub._pos.x + 0.4, HubBall.R, lobby.hub._pos.y))
	await _frames(5)
	lobby.hub.interact()
	await _frames(40)
	v = stage.chars[lobby.hub.local_key()]
	_quiet()
	_make_cams()
	var view := stage.ball_view
	if _wanted("stand"):
		# one bounce, six frames from the top
		await _until(func() -> bool: return view.moves.u > 0.95 or view.moves.u < 0.02)
		var period := BallMoves.SLOW_S
		for i in 6:
			await _snap("stand", i)
			await _frames(maxi(1, int(round(period / 6.0 * 60.0))))
	for kind in ["cross", "legs", "back"]:
		if not _wanted(kind):
			continue
		_place(Vector2(-0.6, 0.6), Vector2(1, 0))
		await _frames(50)
		view.moves.request(kind)
		await _until(func() -> bool: return view.moves.move == kind)
		var dur := float(BallMoves.MOVE_S[kind])
		for i in 9:
			await _snap(kind, i)
			await _frames(maxi(1, int(round(dur / 8.0 * 60.0))))
	if _wanted("shot"):
		var rc := HubBall.rim_center()
		# (the hoop to the runner's left in the side camera)
		_place(Vector2(rc.x, rc.z) + HubBall.HOOP_DIR * 1.7, -HubBall.HOOP_DIR)
		await _frames(50)
		ball.force_make = 1
		lobby.hub.interact()
		var marks := [0.06, 0.2, 0.32, 0.42, 0.5, 0.57]
		var k := 0
		while ball.phase == BallSync.Phase.SHOT and k < marks.size():
			if ball.phase_t >= float(marks[k]) * BallSync.WINDUP_SHOT / 0.6:
				await _snap("shot", k)
				k += 1
			await _frames(1)
		for t2 in [0.06, 0.16, 0.32]:
			await _until(func() -> bool: return ball.phase == BallSync.Phase.FREE and ball.phase_t >= t2)
			await _snap("shot", k)
			k += 1
		# the ball and the (bigger) hoop: it drops through the rim
		var hc := Camera3D.new()
		hc.fov = 40.0
		(cams["side"][0] as SubViewport).add_child(hc)
		var side := Vector3(-HubBall.HOOP_DIR.y, 0, HubBall.HOOP_DIR.x)
		var rcw := stage.to_global(rc)
		hc.look_at_from_position(rcw + Vector3(HubBall.HOOP_DIR.x, 0, HubBall.HOOP_DIR.y) * 1.5 + side * 0.9 + Vector3(0, -0.15, 0), rcw + Vector3(0, -0.1, 0))
		hc.current = true
		var h := 0
		var t0 := ball.phase_t
		while h < 4 and ball.phase_t < t0 + 2.0:
			var p := stage.ball_view.last_pos
			if (h == 0 and p.y < HubBall.RIM_Y + 0.5 and p.distance_to(rc) < 0.9) or (h > 0 and p.y < HubBall.RIM_Y + 0.25 - 0.17 * h):
				await RenderingServer.frame_post_draw
				(cams["side"][0] as SubViewport).get_texture().get_image().save_png("%s/hoop_side_%02d.png" % [dir, h])
				h += 1
			await _frames(1)
	printerr("CAPTURE-DONE")
	get_tree().quit()


func _until(cond: Callable, max_frames: int = 400) -> void:
	for i in max_frames:
		if bool(cond.call()):
			return
		await get_tree().process_frame


func _place(at: Vector2, d: Vector2) -> void:
	lobby.hub.stick = Vector2.ZERO
	lobby.hub._vel = Vector2.ZERO
	lobby.hub._pos = at
	lobby.hub._yaw = atan2(-d.x, -d.y)


func _quiet() -> void:
	for c in stage.chars.values():
		if c is CharacterView:
			(c as CharacterView)._blink_t = 1.0e6
			(c as CharacterView)._next_fidget = 1.0e6


func _make_cams() -> void:
	for n in ["side", "front34", "back34"]:
		var sv := SubViewport.new()
		sv.size = VIEW
		sv.world_3d = get_viewport().world_3d
		sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		sv.msaa_3d = Viewport.MSAA_4X
		var cam := Camera3D.new()
		cam.fov = 38.0
		sv.add_child(cam)
		add_child(sv)
		cam.current = true
		cams[n] = [sv, cam]


## Each camera framed on the runner as they stand now (their own frame:
## the side camera on their right, the three-quarter ones in front and
## behind), then a frame from each.
func _snap(seq: String, i: int) -> void:
	var at := v.global_position
	var yaw := v.global_rotation.y
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var look := at + Vector3(0, 0.62, 0)
	var spots := {"side": right * 2.3 + Vector3(0, 0.75, 0) + fwd * 0.15,
		"front34": (fwd * 0.8 + right * 0.6).normalized() * 2.4 + Vector3(0, 0.95, 0),
		"back34": (-fwd * 0.75 - right * 0.66).normalized() * 2.4 + Vector3(0, 1.0, 0)}
	if seq == "shot":
		look = at + Vector3(0, 0.85, 0)
		spots["side"] = right * 2.6 + Vector3(0, 0.95, 0) + fwd * 0.2
	for n in cams:
		var cam: Camera3D = cams[n][1]
		cam.look_at_from_position(at + (spots[n] as Vector3), look)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	for n in cams:
		if seq != "back" and n == "back34":
			continue
		var img: Image = (cams[n][0] as SubViewport).get_texture().get_image()
		img.save_png("%s/%s_%s_%02d.png" % [dir, seq, n, i])
