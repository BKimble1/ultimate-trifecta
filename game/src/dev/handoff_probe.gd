extends Node
## Development-only (src/dev: never exported).  The loading screen -> round
## handoff of an online GUEST, measured frame by frame through the game's own
## path: App's lobby, LoadingScreen, MatchController and results, with the
## host in the same process (its own NetSession and MatchController in a
## SubViewport, like tests/net_rig.gd) over the loopback hub with latency and
## jitter.  Plays a series: round 1, results, the 5 s countdown, round 2.
##
## Per rendered guest frame (--fixed-fps 60: the clock is the frame counter)
## it records which screen is up and how opaque, whether 3D is drawn, the
## camera, every character view against the newest snapshot of it, the
## snapshot count, the guest's phase and countdown, and the HUD.  It prints
## HANDOFF lines with the classified numbers per round (reveal timing, view
## jumps and camera jumps in the first second, empty or wrong first frames)
## and, with --frames=DIR (needs a display: xvfb-run), saves the frames of the
## transition, from 0.5 s before the loading screen starts to fade to 1.5 s
## after, every --every=N frames.
##
##   tools/gd.sh --headless --fixed-fps 60 --path game res://src/dev/handoff_probe.tscn -- [--lat=60 --jit=30] [--out=file.json]
##   xvfb-run -a tools/gd.sh --fixed-fps 60 --resolution 640x360 --path game res://src/dev/handoff_probe.tscn -- --frames=DIR

var lat := 60.0
var jit := 30.0
var out := ""
var frames_dir := ""
var every := 2
var rounds := 2
var play_s := 8.0

var hub: LoopbackTransport.Hub
var host: NetSession
var host_t: LoopbackTransport
var host_mc: MatchController
var host_vp: SubViewport
var guest: NetSession
var log_rows: Array = []
var _round := 0
var _loading: LoadingScreen
var _loading_seen := {}       # round -> first frame the loading screen showed
var _report: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		var v := a.get_slice("=", 1)
		if a.begins_with("--lat="):
			lat = float(v)
		elif a.begins_with("--jit="):
			jit = float(v)
		elif a.begins_with("--out="):
			out = v
		elif a.begins_with("--frames="):
			frames_dir = v
		elif a.begins_with("--every="):
			every = maxi(1, int(v))
		elif a.begins_with("--rounds="):
			rounds = maxi(1, int(v))
		elif a.begins_with("--play="):
			play_s = float(v)
	if frames_dir != "":
		DirAccess.make_dir_recursive_absolute(frames_dir)
	await get_tree().process_frame
	_run()


func _physics_process(delta: float) -> void:
	if hub != null:
		hub.advance(delta)


func _run() -> void:
	Save.data["onboarded"] = true
	Save.data["tutorial_done"] = true
	App.goto_title()
	await _frames(30)
	hub = LoopbackTransport.Hub.new(7)
	hub.latency_ms = lat
	hub.jitter_ms = jit
	host_t = LoopbackTransport.new(hub, true)
	host = NetSession.new()
	host.name = "ProbeHost"
	add_child(host)
	host.start_host(host_t, "PROBE1", "uid-probe-host", "Probe Host", {}, "runner")
	host.settings["rounds"] = rounds
	host.role_override["uid-probe-host"] = TC.Role.RUNNER
	host.role_override[Save.player_uid()] = TC.Role.RUNNER
	host.match_starting.connect(_host_round)
	var ct := LoopbackTransport.new(hub, false)
	App._begin_session(NetSession.Mode.CLIENT, ct, "PROBE1")
	guest = App.session
	hub.link(host_t.id, ct.id)
	var ok := await _until(func() -> bool: return guest.local_slot >= 1, 600)
	if not ok:
		print("HANDOFF error: the guest never joined")
		get_tree().quit(1)
		return
	guest.set_local_ready(true)
	await _until(func() -> bool: return host.can_start(), 600)
	await _frames(30)
	host.host_start_match(4242)
	for r in rounds:
		_round = r + 1
		await _record_round(_round)
	_finish()


func _host_round(info: Dictionary) -> void:
	if host_mc != null and is_instance_valid(host_mc):
		host_mc.queue_free()
	if host_vp == null:
		host_vp = SubViewport.new()
		host_vp.own_world_3d = true
		host_vp.size = Vector2i(64, 64)
		host_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(host_vp)
	host_mc = MatchController.new()
	host_mc.setup(host, info, {"visuals": false, "quality": 0})
	var ap := Autopilot.new(99)
	host_mc.input_source = func(m: MatchController) -> InputCmd: return _host_cmd(m)
	host_vp.add_child(host_mc)


## The host walks forward once the round plays (its own runner moves on the
## guest's screen like a person's would).
func _host_cmd(m: MatchController) -> InputCmd:
	var c := InputCmd.new()
	if m.sim != null and m.sim.phase == TC.Phase.PLAYING:
		c.move = Vector2(0, -1)
	return c


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


## One round on the guest: from its loading screen to play_s seconds of
## play, every frame recorded; then the host ends the round.
func _record_round(r: int) -> void:
	var rows: Array = []
	var f := 0
	var mc: MatchController = null
	var t_live := -1
	var played := 0
	var have_ap := false
	while f < 60 * 120:
		await get_tree().process_frame
		f += 1
		if App.screen is LoadingScreen:
			_loading = App.screen as LoadingScreen
		var cur: Variant = App.get("match_ctrl")
		if cur != null and is_instance_valid(cur) and int((cur as MatchController).start.get("series", {}).get("round", 1) if (cur as MatchController).start.get("series") is Dictionary else 1) == r:
			mc = cur
		if mc == null or not is_instance_valid(mc):
			rows.append(_row(f, null))
			continue
		if not have_ap and mc.prepared:
			have_ap = true
			var ap := Autopilot.new(7 + r)
			mc.input_source = func(m: MatchController) -> InputCmd: return ap.cmd_for(m)
		var row := _row(f, mc)
		rows.append(row)
		if frames_dir != "":
			await _maybe_save(r, f, row, rows)
		if bool(row["live"]) and t_live < 0:
			t_live = f
		if mc._client_phase == TC.Phase.PLAYING:
			played += 1
			if played >= int(play_s * 60.0):
				break
	_report.append(_classify(r, rows))
	log_rows.append({"round": r, "rows": rows})
	# the host ends this round (the series goes on by itself)
	if host_mc != null and host_mc.sim != null:
		host_mc.sim.end_tick = host_mc.sim.tick + 2
	if r < rounds:
		await _until(func() -> bool: return App.screen is ResultsScreen, 60 * 20)


var _save_from := {}


func _maybe_save(r: int, f: int, row: Dictionary, rows: Array) -> void:
	# from the frame 3D is first drawn visibly (the loading screen fading or
	# gone) back 30 frames, to 90 frames after
	if not _save_from.has(r) and bool(row["fading"]):
		_save_from[r] = f
	var s0 := int(_save_from.get(r, -1))
	var near := s0 >= 0 and f - s0 <= 90
	if not near or (f - s0) % every != 0:
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(frames_dir.path_join("r%d_f%04d.png" % [r, f - s0 + 1000]))


func _row(f: int, mc: MatchController) -> Dictionary:
	var ld := _loading if _loading != null and is_instance_valid(_loading) else null
	var row := {"f": f, "screen": (App.screen.get_script().get_global_name() if App.screen != null and is_instance_valid(App.screen) and App.screen.get_script() else "none"),
		"loading": ld != null, "loading_a": ld.modulate.a if ld != null else 0.0,
		"fading": ld != null and ld._closing or (ld == null and mc != null and mc.prepared),
		"disable_3d": get_viewport().disable_3d}
	if mc == null:
		row["live"] = false
		return row
	row["prepared"] = mc.prepared
	row["live"] = mc.round_live()
	row["view_ready"] = mc.view_ready()
	row["snaps"] = mc.stat_snapshots
	row["phase"] = mc._client_phase
	row["countdown"] = float(mc.local_info().get("countdown", 0.0)) if mc.prepared else -1.0
	row["pres_ok"] = mc._pres_ok
	if mc.camera != null:
		row["cam"] = _v(mc.camera.global_position)
		row["cam_yaw"] = mc.camera.yaw
	if mc.hud != null:
		row["hud"] = mc.hud.visible
	var views := {}
	for slot in mc.views:
		var v: CharacterView = mc.views[slot]
		var e := {"pos": _v(v.global_position), "vis": v.visible}
		var buf: Array = mc._bufs.get(slot, [])
		if not buf.is_empty():
			e["snap"] = _v((buf[buf.size() - 1]["e"] as Dictionary)["pos"])
			e["buf"] = buf.size()
		if slot == mc.local_slot and mc.pred != null:
			e["pred"] = _v(mc.pred.pos())
		if host_mc != null and host_mc.sim != null and host_mc.sim.player(int(slot)) != null:
			e["host"] = _v(host_mc.sim.player(int(slot)).pos())
		views[str(slot)] = e
	row["views"] = views
	return row


static func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)]


static func _p(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## The numbers for one round: when the loading screen started to fade
## (reveal), how many snapshots and buffered samples the guest had then, the
## first frames' camera and character jumps (the largest per-frame move in
## the first second after the reveal that its own motion doesn't explain),
## characters drawn at the origin or not at all, and how far each drawn
## character was from its newest snapshot at the reveal.
func _classify(r: int, rows: Array) -> Dictionary:
	var rev := -1
	for i in rows.size():
		if bool(rows[i].get("fading", false)):
			rev = i
			break
	var res := {"round": r, "lat_ms": lat, "jit_ms": jit, "reveal_frame": rev}
	if rev < 0:
		res["error"] = "no reveal"
		return res
	var r0: Dictionary = rows[rev]
	res["snaps_at_reveal"] = int(r0.get("snaps", 0))
	res["phase_at_reveal"] = int(r0.get("phase", -1))
	res["countdown_at_reveal"] = snappedf(float(r0.get("countdown", -1.0)), 0.01)
	var min_buf := 99
	var far := 0.0
	var hidden := 0
	var at_origin := 0
	for k in (r0.get("views", {}) as Dictionary):
		var e: Dictionary = r0["views"][k]
		min_buf = mini(min_buf, int(e.get("buf", 0)))
		if not bool(e.get("vis", false)):
			hidden += 1
		if _p(e["pos"]).length() < 0.5:
			at_origin += 1
		if e.has("snap"):
			far = maxf(far, _p(e["pos"]).distance_to(_p(e["snap"])))
	res["min_buffered_at_reveal"] = min_buf
	res["views_hidden_at_reveal"] = hidden
	res["views_at_origin_at_reveal"] = at_origin
	res["max_view_to_snapshot_m"] = snappedf(far, 0.001)
	# under the loading screen: was the warm-up drawn from the start view?
	var warm_cam_far := 0.0
	var first_cam: Variant = null
	for i in range(rev, -1, -1):
		if not bool(rows[i].get("disable_3d", true)) and rows[i].has("cam"):
			first_cam = rows[i]["cam"]
	if first_cam != null and r0.has("cam"):
		warm_cam_far = _p(first_cam).distance_to(_p(r0["cam"]))
	res["warm_view_vs_reveal_cam_m"] = snappedf(warm_cam_far, 0.01)
	# the first second after the reveal
	var cam_jump := 0.0
	var cam_yaw_jump := 0.0
	var view_jump := 0.0
	var pop_in := 0
	for i in range(rev + 1, mini(rows.size(), rev + 61)):
		var a: Dictionary = rows[i - 1]
		var b: Dictionary = rows[i]
		if a.has("cam") and b.has("cam"):
			cam_jump = maxf(cam_jump, _p(a["cam"]).distance_to(_p(b["cam"])))
			cam_yaw_jump = maxf(cam_yaw_jump, absf(angle_difference(float(a["cam_yaw"]), float(b["cam_yaw"]))))
		for k in (b.get("views", {}) as Dictionary):
			var eb: Dictionary = b["views"][k]
			var ea: Dictionary = (a.get("views", {}) as Dictionary).get(k, {})
			if ea.is_empty():
				continue
			if bool(eb["vis"]) and not bool(ea["vis"]):
				pop_in += 1
			if bool(eb["vis"]) and bool(ea["vis"]):
				view_jump = maxf(view_jump, _p(ea["pos"]).distance_to(_p(eb["pos"])))
	res["cam_max_step_m_1s"] = snappedf(cam_jump, 0.001)
	res["cam_max_yaw_step_deg_1s"] = snappedf(rad_to_deg(cam_yaw_jump), 0.01)
	res["view_max_step_m_1s"] = snappedf(view_jump, 0.001)
	res["views_popping_in_1s"] = pop_in
	# the screen before the loading screen (round 2: the results go
	# straight into loading)
	var screens: Array = []
	for i in rev:
		var s := String(rows[i]["screen"])
		if screens.is_empty() or screens[-1] != s:
			screens.append(s)
	res["screens_before_reveal"] = screens
	var hud_on := -1
	for i in range(rev, rows.size()):
		if bool(rows[i].get("hud", false)):
			hud_on = i - rev
			break
	res["hud_frame_after_reveal"] = hud_on
	return res


func _finish() -> void:
	for r in _report:
		print("HANDOFF " + JSON.stringify(r))
	if out != "":
		var fo := FileAccess.open(out, FileAccess.WRITE)
		fo.store_string(JSON.stringify({"report": _report, "frames": log_rows}))
	get_tree().quit()
