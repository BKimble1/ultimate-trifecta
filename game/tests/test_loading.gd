extends RefCounted
## V4 loading pipeline: the round is prepared in bounded steps under the
## loading screen, the campus look is reused between rounds, and ten rounds
## in a row leave nothing behind.
var t


func _offline() -> NetSession:
	var s := NetSession.new()
	t.add_child(s)
	s.start_offline("u-load", "Tester", {}, "runner")
	return s


func _start(s: NetSession, staged: bool = true) -> MatchController:
	var info := {}
	var grab := func(i: Dictionary) -> void: info.merge(i, true)
	s.match_starting.connect(grab, CONNECT_ONE_SHOT)
	if s.phase != TC.Phase.LOBBY:
		s.host_return_to_lobby()
	s.host_start_match(4242)
	var mc := MatchController.new()
	mc.setup(s, info, {"quality": 0, "staged": staged})
	t.add_child(mc)
	return mc


func _end(mc: MatchController) -> void:
	mc.release_campus()
	mc.queue_free()


func test_round_is_prepared_in_bounded_steps() -> void:
	MatchController.drop_campus_cache()
	var s := _offline()
	var mc := _start(s)
	t.check(not mc.prepared, "nothing heavy happens in _ready")
	t.check(mc.sim == null, "the sim waits for its step")
	var frames := 0
	while not mc.prepared and frames < 400:
		await t.get_tree().process_frame
		frames += 1
	t.check(mc.prepared, "prepared")
	t.check(mc.prep_frames >= 4, "spread over several frames (%d)" % mc.prep_frames)
	# a single step can overrun the budget; none may be a long freeze.  The
	# figure here is this test machine's CPU, not a phone measurement.
	t.check(mc.prep_max_ms < 120.0, "no long freeze while loading (%.1f ms)" % mc.prep_max_ms)
	t.check(mc.sim != null and mc.views.size() == mc.roster.size(), "sim and every character ready")
	t.check(mc.round_live(), "practice goes live once prepared")
	t.check(mc.water_nodes.size() == 6, "six waters")
	_end(mc)
	await t.get_tree().process_frame
	s.queue_free()


func test_campus_look_is_reused_between_rounds() -> void:
	MatchController.drop_campus_cache()
	var s := _offline()
	var mc := _start(s, false)
	var campus := mc._campus
	t.check(campus != null and campus.is_inside_tree(), "campus built")
	var any_water: ShaderMaterial = (mc.water_nodes.values()[0] as Dictionary)["mat"]
	any_water.set_shader_parameter("stamped", 1.0)
	_end(mc)
	await t.get_tree().process_frame
	t.check(MatchController.campus_cached(), "kept after the round")
	t.check(is_instance_valid(campus) and not campus.is_inside_tree(), "kept out of the tree between rounds")
	var mc2 := _start(s, false)
	t.check(mc2._campus == campus, "the next round reuses the same campus")
	t.eq(float(any_water.get_shader_parameter("stamped")), 0.0, "per-round water state starts clean")
	t.check(not MatchController.campus_cached(), "in use, not double-held")
	_end(mc2)
	await t.get_tree().process_frame
	MatchController.drop_campus_cache()
	t.check(not is_instance_valid(campus), "dropping the cache frees it")
	s.queue_free()


func test_ten_rounds_leave_nothing_behind() -> void:
	MatchController.drop_campus_cache()
	var s := _offline()
	var counts: Array = []
	var conns: Array = []
	for i in 10:
		var mc := _start(s, false)
		for f in 3:
			await t.get_tree().physics_frame
		_end(mc)
		await t.get_tree().process_frame
		await t.get_tree().process_frame
		counts.append([Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)])
		var c := 0
		for sig in s.get_signal_list():
			c += s.get_signal_connection_list(String(sig["name"])).size()
		conns.append(c)
	print("[load] nodes/objects/orphans after rounds 2, 10: %s  %s; session connections %s" % [counts[1], counts[9], conns])
	t.eq(int(counts[9][0]), int(counts[1][0]), "scene nodes do not grow across rounds")
	t.check(int(counts[9][1]) - int(counts[1][1]) <= 16, "objects do not keep growing (%d -> %d)" % [counts[1][1], counts[9][1]])
	t.eq(int(counts[9][2]), int(counts[1][2]), "orphan nodes stay flat (the kept campus only)")
	t.eq(int(conns[9]), int(conns[1]), "no signal connections left on the session")
	MatchController.drop_campus_cache()
	s.queue_free()


# --- the loading screen's runner loop (V5: rendered from the game rig) ---

func test_loading_loop_assets_agree() -> void:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LoadingScreen.LOOP_META))
	var fw := int(meta["frame_w"])
	var fh := int(meta["frame_h"])
	t.eq(int(meta["frames"]), LoadingScreen.LOOP_FRAMES, "frame count matches the builder")
	t.eq(Vector2(float(meta["cols"]), float(meta["rows"])), LoadingScreen.LOOP_GRID, "atlas grid matches")
	t.eq(float(meta["fps"]), LoadingScreen.LOOP_FPS, "60 fps: the loop matches the UI's cadence (no 24 fps stride)")
	t.eq(Vector2(fw, fh), LoadingScreen.LOOP_FRAME, "frame size matches")
	t.check(bool(meta["premultiplied"]), "frames are premultiplied (drawn over the screen's own background)")
	t.check(float(meta["loop_closes_mad"]) < 0.05, "the loop closes: the frame after the last is the first")
	t.check(float(meta["seam_step_mad"]) <= float(meta["step_mad_max"]) * 1.15, "the step from the last frame to the first is an ordinary step")
	var g := LoadingScreen.LOOP_GRID
	t.check(LoadingScreen.LOOP_FRAMES <= int(g.x * g.y) and LoadingScreen.LOOP_FRAMES > int(g.x * (g.y - 1.0)), "every frame has a cell, no empty row")
	t.check(fw % 4 == 0 and fh % 4 == 0, "frames sit on whole compression blocks")
	var atlas := load(LoadingScreen.LOOP_ATLAS) as Texture2D
	var still := load(LoadingScreen.LOOP_STILL) as Texture2D
	t.check(atlas != null and still != null, "atlas and still are bundled")
	if atlas == null or still == null:
		return
	t.eq(atlas.get_size(), Vector2(fw * g.x, fh * g.y), "atlas is the grid of whole frames (never scaled)")
	t.eq(still.get_size(), Vector2(fw, fh), "the still is one frame at full size")
	t.check(not ResourceLoader.exists("res://assets/loading/run_loop_atlas.jpg"), "the V4 clip atlas is no longer shipped")


func test_loading_layout_keeps_feet_clear_of_status() -> void:
	var ls := LoadingScreen.new()
	t.add_child(ls)
	for sz in [Vector2(1558, 720), Vector2(1280, 720), Vector2(960, 720)]:
		ls.size = sz
		ls._layout()
		await t.get_tree().process_frame
		var pic := Rect2(ls.picture.position, ls.picture.size)
		var title := Rect2(ls.title_art.position, ls.title_art.size)
		t.check(pic.end.y <= sz.y * 0.8, "%s: the runners stand well above the status area" % str(sz))
		t.check(title.end.y <= pic.position.y + pic.size.y * 0.08, "%s: the title stays clear of the runners" % str(sz))
		t.check(absf(pic.get_center().x - sz.x * 0.5) < 1.0 and absf(title.get_center().x - sz.x * 0.5) < 1.0, "%s: centred" % str(sz))
		t.check(is_equal_approx(pic.size.x / pic.size.y, LoadingScreen.LOOP_FRAME.x / LoadingScreen.LOOP_FRAME.y), "%s: never stretched" % str(sz))
	t.eq(ls.title_art.accessibility_name, "Ultimate Trifecta", "the title graphic has an accessibility name")
	ls.queue_free()


## Background loads finish in wall-clock time, while the test runner's fixed
## frame clock can run hundreds of frames in a few milliseconds: wait on the
## wall clock (frames keep running, so App's reaper and the screen poll).
func _frames_until(cond: Callable, max_ms: int = 10000) -> void:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < max_ms:
		OS.delay_msec(2)
		await t.get_tree().process_frame


func _loading_screen(s: NetSession, mc: MatchController) -> LoadingScreen:
	var ls := LoadingScreen.new()
	ls.session = s
	ls.match_ctrl = mc
	t.add_child(ls)
	return ls


func test_loading_screen_still_loop_progress_and_release() -> void:
	MatchController.drop_campus_cache()
	var s := _offline()
	var mc := _start(s)
	var ls := _loading_screen(s, mc)
	var mat := ls.picture.material as ShaderMaterial
	t.check(mat.get_shader_parameter("frames") == ls._still and ls._still != null, "the still shows at once")
	t.eq(mat.get_shader_parameter("grid"), Vector2.ONE, "as a single frame")
	t.check(ls._atlas_pending, "the loop loads in the background")
	var closed := [false]
	ls.done.connect(func() -> void: closed[0] = true)
	var last := 0.0
	var steady := true
	var ahead := false
	var loop_seen := false
	var first_frame := -2.0
	var frames := 0
	while not closed[0] and frames < 900:
		await t.get_tree().process_frame
		frames += 1
		if not is_instance_valid(mc):
			break
		var p := mc.prep_progress()
		steady = steady and p >= last - 0.0001
		last = p
		ahead = ahead or ls.bar.shown > p + 0.0001
		if ls.loop_running() and not loop_seen:
			loop_seen = true
			first_frame = float(mat.get_shader_parameter("frame"))
			t.eq(mat.get_shader_parameter("grid"), LoadingScreen.LOOP_GRID, "then the loop atlas")
	t.check(steady, "preparation progress only moves forward")
	t.check(not ahead, "the bar never runs ahead of the real preparation")
	t.check(closed[0], "the screen closes as soon as the round is live (%d frames)" % frames)
	t.check(mc.round_live(), "and the round is live")
	if loop_seen:
		t.check(first_frame <= 1.0, "the loop starts from the still's frame (frame %d)" % int(first_frame))
	else:
		print("[load] round was ready before the loop finished loading: the still stayed (allowed)")
	t.check(ls.stage_lbl.text != "", "a status line is shown")
	ls.queue_free()
	await t.get_tree().process_frame
	t.check(not is_instance_valid(ls), "screen freed")
	t.check(mat.get_shader_parameter("frames") == null, "its textures are let go")
	# a load still running when the screen went is collected by App
	await _frames_until(func() -> bool: return App._orphan_loads.is_empty())
	t.check(App._orphan_loads.is_empty(), "no background load left behind")
	_end(mc)
	await t.get_tree().process_frame
	MatchController.drop_campus_cache()
	s.queue_free()


func test_loading_screen_closed_early_hands_its_load_to_app() -> void:
	var s := _offline()
	var ls := _loading_screen(s, null)
	var pending := ls._atlas_pending
	ls.queue_free()
	await t.get_tree().process_frame
	if pending:
		t.check(App._orphan_loads.has(LoadingScreen.LOOP_ATLAS) or ResourceLoader.load_threaded_get_status(LoadingScreen.LOOP_ATLAS) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "the unfinished load is adopted")
		# the next screen takes it over instead of asking twice
		var ls2 := _loading_screen(s, null)
		t.check(ls2._atlas_pending, "a new screen picks the load up")
		await _frames_until(func() -> bool: return ls2.loop_running())
		t.check(ls2.loop_running(), "and runs the loop")
		ls2.queue_free()
		await t.get_tree().process_frame
	await _frames_until(func() -> bool: return App._orphan_loads.is_empty())
	t.check(App._orphan_loads.is_empty(), "nothing left loading")
	s.queue_free()


func test_loading_screen_reduced_motion_shows_the_still_only() -> void:
	var was: Variant = Save.get_setting("reduced_motion", false)
	Save.data["settings"]["reduced_motion"] = true
	var s := _offline()
	var ls := _loading_screen(s, null)
	t.check(not ls._atlas_pending, "no loop is loaded with Reduced Motion")
	for i in 5:
		await t.get_tree().process_frame
	t.check(not ls.loop_running(), "the still stays")
	t.eq((ls.picture.material as ShaderMaterial).get_shader_parameter("grid"), Vector2.ONE, "as one frame")
	ls.queue_free()
	Save.data["settings"]["reduced_motion"] = was
	await t.get_tree().process_frame
	s.queue_free()


# --- V6: cancel at any point, and an unknown wait never looks stuck ---

func test_practice_can_be_cancelled_mid_preparation_and_the_next_round_works() -> void:
	MatchController.drop_campus_cache()
	var was_onboarded: Variant = Save.data.get("onboarded", false)
	Save.data["onboarded"] = true
	var counts: Array = []
	for cycle in 3:
		App.start_practice("runner", false)
		await t.get_tree().process_frame
		var ls := App.screen as LoadingScreen
		var mc := App.match_ctrl
		t.check(ls != null and mc != null, "practice opens the loading screen over a preparing round")
		if ls == null or mc == null:
			return
		if cycle == 0:
			t.eq(ls.leave_btn.text, "Cancel", "practice offers Cancel")
			t.check(ls.leave_btn.disabled, "not in the first instant (a carried-over tap can't cancel)")
		# well into the campus build: its chunk meshes are on the worker pool
		var frames := 0
		while frames < 2000 and not mc.prepared and not (mc._builder != null and mc._builder._commit_started):
			await t.get_tree().process_frame
			frames += 1
		var on_pool := mc._builder != null and mc._builder._commit_started
		t.check(not mc.prepared, "still preparing (%d frames, %.0f%%)" % [frames, mc.prep_progress() * 100.0])
		if cycle == 0:
			t.check(on_pool, "with campus work on the worker pool")
			t.eq(ls.stage_lbl.text, "Preparing campus…", "the stage says the campus is being prepared")
			t.check(not ls.bar.indeterminate, "with the real share done")
		await _frames_until(func() -> bool: return ls._t >= LoadingScreen.LEAVE_AFTER_S, 3000)
		t.check(not ls.leave_btn.disabled, "Cancel is usable while the round prepares")
		ls.leave_btn.pressed.emit()
		await t.get_tree().process_frame
		await t.get_tree().process_frame
		t.check(not is_instance_valid(mc), "the half-prepared round is freed")
		t.check(App.match_ctrl == null and App.session == null, "no round or session left")
		t.check(not (App.screen is LoadingScreen) and not is_instance_valid(ls), "back to the title")
		await _frames_until(func() -> bool: return App._orphan_tasks.is_empty() and App._orphan_loads.is_empty())
		t.check(App._orphan_tasks.is_empty(), "the build's background jobs were collected")
		await t.get_tree().process_frame
		counts.append([Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)])
	print("[load] nodes/objects/orphans after each cancel: %s" % [counts])
	t.eq(int(counts[2][0]), int(counts[1][0]), "cancelling again leaves no scene nodes behind")
	t.eq(int(counts[2][2]), int(counts[1][2]), "nor orphan nodes")
	t.check(int(counts[2][1]) - int(counts[1][1]) <= 16, "nor a growing number of objects (%d -> %d)" % [counts[1][1], counts[2][1]])
	# and the next round prepares and goes live as usual
	App.start_practice("runner", false)
	await t.get_tree().process_frame
	var mc2 := App.match_ctrl
	var ls2 := App.screen as LoadingScreen
	var closed := [false]
	if ls2:
		ls2.done.connect(func() -> void: closed[0] = true)
	await _frames_until(func() -> bool: return closed[0] or not is_instance_valid(mc2), 60000)
	t.check(is_instance_valid(mc2) and mc2.round_live(), "the next round prepares and goes live")
	t.check(closed[0], "and its loading screen closes")
	App._close_session(false)
	App._end_match_scene()
	App.goto_title()
	await t.get_tree().process_frame
	MatchController.drop_campus_cache()
	Save.data["onboarded"] = was_onboarded


func test_preparing_and_waiting_for_players_are_told_apart() -> void:
	var s := _offline()
	var ls := _loading_screen(s, null)
	ls._update_status(false, 0.4, [1, 1])
	t.eq(ls.stage_lbl.text, "Preparing campus…", "preparing: the campus")
	t.check(not ls.bar.indeterminate and is_equal_approx(ls.bar.target, 0.4), "with the real share done")
	t.eq(ls.wait_lbl.text, "", "no player count yet")
	ls._update_status(true, 1.0, [1, 3])
	t.eq(ls.stage_lbl.text, "Waiting for players", "ready here: waiting for the others")
	t.eq(ls.wait_lbl.text, "1/3 ready", "with the count")
	t.check(ls.bar.indeterminate, "an unknown wait shows an indeterminate sweep, not a stuck bar")
	var p0 := ls.bar._phase
	for i in 3:
		await t.get_tree().process_frame
	t.check(UIKit.reduced_motion() or ls.bar._phase != p0, "the sweep moves")
	ls._update_status(true, 1.0, [3, 3])
	t.eq(ls.stage_lbl.text, "Starting…", "everyone ready: starting")
	t.eq(ls.wait_lbl.text, "Everyone's ready", "said once")
	ls.queue_free()
	await t.get_tree().process_frame
	s.queue_free()


## V6: when frames are slow anyway, preparation takes a larger share of each
## (up to half the interval, capped); at 60 fps it stays at 9 ms.
func test_preparation_budget_follows_a_slow_device() -> void:
	t.eq(MatchController.prep_budget_us(7000.0), MatchController.PREP_BUDGET_US, "60 fps: the usual 9 ms")
	t.eq(MatchController.prep_budget_us(0.0), MatchController.PREP_BUDGET_US, "unknown: the usual 9 ms")
	t.eq(MatchController.prep_budget_us(50000.0), 25000, "a 50 ms frame: half of it")
	t.eq(MatchController.prep_budget_us(1000000.0), MatchController.PREP_BUDGET_MAX_US, "never more than the cap")
	# driven: frames that take 60 ms outside preparation
	MatchController.drop_campus_cache()
	var s := _offline()
	var mc := _start(s)
	var frames := 0
	while not mc.prepared and frames < 400:
		OS.delay_msec(60)
		await t.get_tree().process_frame
		frames += 1
	t.check(mc.prepared, "prepared")
	var slow_frames := frames
	_end(mc)
	await t.get_tree().process_frame
	MatchController.drop_campus_cache()
	var mc2 := _start(s)
	frames = 0
	while not mc2.prepared and frames < 400:
		await t.get_tree().process_frame
		frames += 1
	print("[load] frames to prepare: %d with 60 ms frames, %d with fast frames" % [slow_frames, frames])
	t.check(slow_frames < frames, "slow frames: fewer of them are needed (%d vs %d)" % [slow_frames, frames])
	_end(mc2)
	await t.get_tree().process_frame
	MatchController.drop_campus_cache()
	s.queue_free()


## A round whose start the test controls (an online round waiting for
## other players).
class WaitingMatch:
	extends MatchController
	var live := false

	func round_live() -> bool:
		return prepared and live


## V6: nothing 3D is drawn behind the loading screen: held while the round
## prepares (V5 drew the whole campus from an unplaced camera from step 7
## on), a few frames from the start view once prepared, held again while
## the round waits, drawn when it goes live; menus get 3D back.
func test_nothing_is_drawn_behind_the_loading_screen() -> void:
	MatchController.drop_campus_cache()
	var vp: Viewport = t.get_viewport()
	var s := _offline()
	var info := {}
	var grab := func(i: Dictionary) -> void: info.merge(i, true)
	s.match_starting.connect(grab, CONNECT_ONE_SHOT)
	s.host_start_match(4242)
	var mc := WaitingMatch.new()
	mc.setup(s, info, {"quality": 0, "staged": true})
	t.add_child(mc)
	var drawn_before_ready := 0
	var frames := 0
	while not mc.prepared and frames < 600:
		await t.get_tree().process_frame
		frames += 1
		if mc.camera != null and not vp.disable_3d:
			drawn_before_ready += 1
	t.check(mc.prepared, "prepared")
	t.eq(drawn_before_ready, 0, "no 3D frame is drawn while the round prepares")
	var drawn := 0
	for i in 8:
		await t.get_tree().process_frame
		if not vp.disable_3d:
			drawn += 1
	t.eq(drawn, MatchController.WARM_VIEW_FRAMES, "a few frames from the start view warm what the round shows first")
	t.check(mc.view_ready(), "and the view is ready for the reveal")
	t.check(vp.disable_3d, "then held while the round waits for other players")
	t.check(mc.camera.global_position.distance_to(Vector3.ZERO) > 1.0, "the camera was placed before those frames")
	mc.live = true
	await t.get_tree().process_frame
	t.check(not vp.disable_3d, "drawn the frame the round goes live")
	mc.live = false
	await t.get_tree().process_frame
	t.check(not vp.disable_3d, "and never held again in that round")
	_end(mc)
	await t.get_tree().process_frame
	t.check(not vp.disable_3d, "menus draw 3D again")
	# cancelled while held: 3D comes back too
	s.host_return_to_lobby()
	var mc2 := _start(s)
	while mc2.camera == null and not mc2.prepared:
		await t.get_tree().process_frame
	t.check(vp.disable_3d or mc2.prepared, "held once the camera exists")
	mc2.queue_free()
	await t.get_tree().process_frame
	t.check(not vp.disable_3d, "a round cancelled while held gives 3D back")
	MatchController.drop_campus_cache()
	s.queue_free()


## V6: in practice the round is live as soon as it is prepared; the loading
## screen still waits for the start view's first (costly) frames, drawn
## under it, so the fade never shows them.
func test_practice_reveal_waits_for_the_warm_frames() -> void:
	MatchController.drop_campus_cache()
	var s := _offline()
	var mc := _start(s)
	var ls := _loading_screen(s, mc)
	var closed_at := [-1]
	var frame := [0]
	ls.done.connect(func() -> void: closed_at[0] = frame[0])
	var prepared_at := -1
	var closing_at := -1
	while frame[0] < 900 and closed_at[0] < 0:
		await t.get_tree().process_frame
		frame[0] += 1
		if mc.prepared and prepared_at < 0:
			prepared_at = frame[0]
		if ls._closing and closing_at < 0:
			closing_at = frame[0]
	t.check(prepared_at > 0 and closing_at > 0, "prepared, then closed")
	t.check(closing_at - prepared_at >= MatchController.WARM_VIEW_FRAMES, "the screen began to fade only after the warm frames (%d frames after prepared)" % (closing_at - prepared_at))
	ls.queue_free()
	_end(mc)
	await t.get_tree().process_frame
	MatchController.drop_campus_cache()
	s.queue_free()
