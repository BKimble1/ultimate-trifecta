extends Node
## Development-only evidence for the Pass 8 match clarity work (created by
## capture.gd for --capture=pass8_match; src/dev/ is excluded from iOS
## exports).  A real practice round (--autoplay=runner or =patrol) or the
## results screens (--p8-part=results), driven into each state the brief
## asks to see.  States are DETERMINISTIC DEV STATES, labelled as such in
## every shot's JSON: the driver teleports players, sets stamps, calls the
## simulation's own capture / finish rules and shortens the clock; the HUD,
## map, pace and results then show what the game itself computes.
##
## Next to each PNG a <shot>.json (capture.gd: renderer, label) and a
## <shot>_hud.json: the viewport, the safe area, units per point, and the
## rects (canvas units and points) of the goal bar, the personal card, the
## danger chip, Pause, the minimap and the thumb controls, with any overlap
## between them listed (expected: none).
## Layout/look evidence on desktop Linux (llvmpipe): not device input,
## frame rate or a comprehension test.

var cap: Node
var part := "runner"
var _t := 0.0
var _at := 0.0
var _step := 0
var _hold: Callable = Callable()    # re-applied every frame until the next step
var _host: NetSession


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--p8-part="):
			part = a.get_slice("=", 1)
	_at = 4.0
	Save.set_setting("quality", 0)


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
		_at = _t + 0.25       # not ready yet: ask again shortly
		return
	_step += 1
	_at = _t + delay


func _steps() -> Array:
	match part:
		"patrol":
			return [_wait_round, _watch_on_foot, _watch_map, _watch_map_close, _watch_cart, _watch_urgent, _runners_finish, _results_shot, _quit]
		"results":
			return [_series_round, _series_final, _series_watch_lost, _series_cancelled, _quit]
	return [_wait_round, _runner_0, _runner_2, _runner_3, _runner_danger, _runner_map, _runner_map_lost, _runner_map_close,
		_runner_caught, _runner_protected, _runner_home, _runner_urgent, _results_shot, _quit]


func _quit() -> float:
	get_tree().quit()
	return 99.0


func _snap(n: String) -> void:
	cap.call("snap", n)
	_hud_json.call_deferred(n)


func _mc() -> MatchController:
	var mc: MatchController = App.match_ctrl
	return mc if mc != null and is_instance_valid(mc) and mc.prepared and mc.hud != null else null


func _me() -> SimPlayer:
	var mc := _mc()
	return mc.sim.player(mc.local_slot) if mc and mc.sim else null


func _first(role: int, not_slot: int = -1) -> SimPlayer:
	var mc := _mc()
	for p in mc.sim.players:
		if p.role == role and p.id != not_slot:
			return p
	return null


func _put(p: SimPlayer, at: Vector3, yaw: float) -> void:
	p.body.global_position = at
	p.body.velocity = Vector3.ZERO
	p.vel = Vector3.ZERO
	p.yaw = yaw
	p.clear_history()


## The local player stands at `at` facing `yaw`, the camera behind them.
func _stand(at: Vector3, yaw: float) -> void:
	var mc := _mc()
	var me := _me()
	_put(me, at, yaw)
	mc.camera.snap_to(at, yaw)


static func _yaw_to(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return atan2(-d.x, -d.z)


# ---------------------------------------------------------------- runner
func _wait_round() -> float:
	var mc := _mc()
	if mc == null or mc.sim == null or not mc.round_live() or not mc.view_ready() or App.screen != null:
		return -1.0
	# straight to play with the head start over; the route fields ready now
	if mc.sim.phase < TC.Phase.PLAYING:
		mc.sim._set_phase(TC.Phase.PLAYING)
	mc.sim.patrol_release_extra_s = -100.0
	PaceFields.settle()
	if part == "runner":
		# the Night Watch bots stand still where the driver puts them (no
		# chase in the stills): their brains are switched off
		for p in mc.sim.players:
			if p.is_patrol():
				mc.sim.bots.erase(p.id)
	return 2.0


func _water_view(stamps: int) -> void:
	var mc := _mc()
	var me := _me()
	var tg: Array = mc.targets
	# face the first water not stamped from 18 m away (or the fountain area)
	var wi := int(tg[0])
	for i in tg.size():
		if (stamps & (1 << i)) == 0:
			wi = int(tg[i])
			break
	var c: Vector2 = mc.layout.waters[wi]["center"]
	var nav := NavGrid.shared(mc.layout)
	var at := Vector3.INF
	for k in 16:
		var a := TAU * float(k) / 16.0
		var p := c + Vector2(cos(a), sin(a)) * 20.0
		if nav.is_walkable(p) and mc.sim.has_los(Vector3(p.x, 1.5, p.y), Vector3(c.x, 1.0, c.y)):
			at = Vector3(p.x, 0.1, p.y)
			break
	if at == Vector3.INF:
		at = Vector3(c.x, 0.1, c.y + 20.0)
	me.stamps = stamps
	_stand(at, _yaw_to(at, Vector3(c.x, 0, c.y)))
	_hold = func() -> void:
		var m := _me()
		if m:
			m.stamps = stamps


func _runner_0() -> float:
	_water_view(0)
	get_tree().create_timer(1.6).timeout.connect(_snap.bind("runner_0_waters"))
	return 2.4


func _runner_2() -> float:
	_water_view(3)
	get_tree().create_timer(1.6).timeout.connect(_snap.bind("runner_2_waters"))
	return 2.4


func _runner_3() -> float:
	var mc := _mc()
	var d: Dictionary = mc.layout.home_doors(mc.home_dorm)[0]
	var p: Vector2 = (d["pos"] as Vector2) + (d["normal"] as Vector2) * 22.0
	var at := Vector3(p.x, 0.1, p.y)
	_me().stamps = 7
	_stand(at, _yaw_to(at, Vector3((d["pos"] as Vector2).x, 0, (d["pos"] as Vector2).y)))
	_hold = func() -> void:
		var m := _me()
		if m:
			m.stamps = 7
	get_tree().create_timer(1.6).timeout.connect(_snap.bind("runner_3_waters_return_inside"))
	return 2.4


## A Night Watch (still in its head start, so it can't move or tag) in plain
## sight 10 m ahead: the live badge on the minimap and the danger chip.
var _spot := Vector3.ZERO
var _watch: SimPlayer


func _runner_danger() -> float:
	var mc := _mc()
	var me := _me()
	_water_view(3)
	_watch = _first(TC.Role.PATROL)
	var fw := Vector3(-sin(me.yaw), 0, -cos(me.yaw))
	var side := Vector3(-fw.z, 0, fw.x)
	# 10-15 m away in plain sight, to one side (a separate mark on the map)
	_spot = me.pos() + fw * 8.0 + side * 3.0
	var nav := NavGrid.shared(mc.layout)
	for off in [fw * 13.0 + side * 7.0, fw * 12.0 - side * 7.0, fw * 11.0 + side * 4.0, fw * 10.0 - side * 4.0]:
		var q: Vector3 = me.pos() + off
		if nav.is_walkable(Vector2(q.x, q.z)) and mc.sim.has_los(me.pos() + Vector3(0, 1.5, 0), q + Vector3(0, 1.0, 0)):
			_spot = q
			break
	var w := _watch
	_hold = func() -> void:
		var m := _me()
		if m:
			m.stamps = 3
		_put(w, _spot, _yaw_to(_spot, me.pos()))
	get_tree().create_timer(1.6).timeout.connect(_snap.bind("runner_watch_in_sight_danger"))
	return 2.4


func _runner_map() -> float:
	_mc().hud.open_map()
	get_tree().create_timer(1.0).timeout.connect(_snap.bind("map_runner_watch_in_sight"))
	return 1.6


## Lost sight: the Watch goes behind a building; its mark freezes, hollow,
## with its age (expanded map).
func _runner_map_lost() -> float:
	var mc := _mc()
	var me := _me()
	var w := _watch
	var hidden := Vector3.INF
	for b in mc.layout.buildings:
		var bp: Vector2 = b["pos"]
		var bs: Vector2 = b["size"]
		for off in [Vector2(bs.x * 0.5 + 3.0, 0), Vector2(-bs.x * 0.5 - 3.0, 0), Vector2(0, bs.y * 0.5 + 3.0), Vector2(0, -bs.y * 0.5 - 3.0)]:
			var q: Vector2 = bp + off
			var qv := Vector3(q.x, 0.1, q.y)
			if qv.distance_to(me.pos()) < 60.0 and not mc.sim.has_los(me.pos() + Vector3(0, 1.5, 0), qv + Vector3(0, 1.0, 0)):
				hidden = qv
				break
		if hidden != Vector3.INF:
			break
	if hidden == Vector3.INF:
		hidden = Vector3(0, 0.1, -140)
	_hold = func() -> void:
		var m := _me()
		if m:
			m.stamps = 3
		_put(w, hidden, 0.0)
	get_tree().create_timer(2.2).timeout.connect(_snap.bind("map_runner_last_seen_2s"))
	return 2.8


func _runner_map_close() -> float:
	_mc().hud.close_map()
	return 0.6


func _runner_caught() -> float:
	var mc := _mc()
	_water_view(3)
	var me := _me()
	var w := _watch
	var at := me.pos() + Vector3(1.0, 0, 1.0)
	_put(w, at, 0.0)
	mc.sim._capture(me, w)
	var hidden := Vector3(0, 0.1, -140)
	_hold = func() -> void:
		_put(w, hidden, 0.0)
	get_tree().create_timer(0.8).timeout.connect(_snap.bind("runner_caught"))
	return 2.6


func _runner_protected() -> float:
	var me := _me()
	if me.state == TC.PState.CAPTURED:
		return -1.0
	get_tree().create_timer(0.3).timeout.connect(_snap.bind("runner_protected"))
	return 2.6


## Home through a real doorway crossing (the simulation's own finish rule),
## then the view follows a teammate.
func _runner_home() -> float:
	var mc := _mc()
	var me := _me()
	_hold = Callable()
	me.stamps = 7
	var d: Dictionary = mc.sim.home_doors[0]
	var lp: Vector2 = d["line_p"]
	var n_in: Vector2 = d["n_in"]
	var outside := Vector3(lp.x - n_in.x * 0.4, 0.05, lp.y - n_in.y * 0.4)
	var inside := Vector3(lp.x + n_in.x * 0.4, 0.05, lp.y + n_in.y * 0.4)
	me.body.global_position = inside
	me.prev_pos = outside
	mc.sim._check_finish(me)
	get_tree().create_timer(1.0).timeout.connect(_snap.bind("runner_home_waiting_for_team"))
	get_tree().create_timer(4.6).timeout.connect(_snap.bind("runner_home_watching_teammate"))
	return 5.4


func _runner_urgent() -> float:
	var mc := _mc()
	mc.sim.end_tick = mc.sim.tick + 9 * 60
	get_tree().create_timer(1.6).timeout.connect(_snap.bind("urgent_clock"))
	return 9.5


func _results_shot() -> float:
	if not (App.screen is ResultsScreen):
		return -1.0
	get_tree().create_timer(1.6).timeout.connect(_snap.bind("results_%s_practice" % part))
	return 2.4


# ---------------------------------------------------------------- watch
func _watch_on_foot() -> float:
	var mc := _mc()
	var me := _me()
	var r1 := _first(TC.Role.RUNNER)
	var r2: SimPlayer = null
	for p in mc.sim.players:
		if p.is_runner() and p != r1:
			r2 = p
			break
	# two real tags of two different runners, and one runner home
	_put(r1, me.pos() + Vector3(1, 0, 0), 0.0)
	mc.sim._capture(r1, me)
	_put(r2, me.pos() + Vector3(-1, 0, 0), 0.0)
	mc.sim._capture(r2, me)
	var r3: SimPlayer = null
	for p in mc.sim.players:
		if p.is_runner() and p != r1 and p != r2:
			r3 = p
			break
	_finish(r3)
	# stand in the open facing a runner 7 m away
	var c: Vector2 = mc.layout.waters[int(mc.targets[0])]["center"]
	var at := Vector3(c.x, 0.1, c.y + 22.0)
	var r4 := r3
	for p in mc.sim.players:
		if p.is_runner() and p.state == TC.PState.ACTIVE:
			r4 = p
			break
	var spot := at + Vector3(0, 0, -7.0)
	_stand(at, _yaw_to(at, spot))
	_hold = func() -> void:
		_put(r4, spot, PI)
	get_tree().create_timer(1.6).timeout.connect(_snap.bind("watch_on_foot"))
	return 2.4


func _finish(p: SimPlayer) -> void:
	var mc := _mc()
	p.stamps = 7
	var d: Dictionary = mc.sim.home_doors[mc.sim.finished_count % mc.sim.home_doors.size()]
	var lp: Vector2 = d["line_p"]
	var n_in: Vector2 = d["n_in"]
	p.body.global_position = Vector3(lp.x + n_in.x * 0.4, 0.05, lp.y + n_in.y * 0.4)
	p.prev_pos = Vector3(lp.x - n_in.x * 0.4, 0.05, lp.y - n_in.y * 0.4)
	mc.sim._check_finish(p)


func _watch_map() -> float:
	_mc().hud.open_map()
	get_tree().create_timer(1.0).timeout.connect(_snap.bind("map_watch_runner_in_sight"))
	return 1.6


func _watch_map_close() -> float:
	_mc().hud.close_map()
	return 0.6


## Into a cart the way the simulation seats a driver.
func _watch_cart() -> float:
	var mc := _mc()
	var me := _me()
	_hold = Callable()
	var c: SimCart = mc.sim.carts[0]
	c.occupant = me.id
	c.exiting = false
	me.cart_id = c.id
	Motor.set_body_enabled(me.body, false)
	me.state = TC.PState.IN_CART
	me.state_t = 1.0
	mc.camera.snap_to(c.pos(), c.yaw)
	get_tree().create_timer(1.6).timeout.connect(_snap.bind("watch_in_cart"))
	return 2.4


func _watch_urgent() -> float:
	var mc := _mc()
	mc.sim.end_tick = mc.sim.tick + 9 * 60
	get_tree().create_timer(1.6).timeout.connect(_snap.bind("watch_urgent_clock"))
	return 2.4


## The runners reach their goal (real finishes): RUNNERS WIN.
func _runners_finish() -> float:
	var mc := _mc()
	for p in mc.sim.players:
		if mc.sim.phase != TC.Phase.PLAYING:
			break
		if p.is_runner() and p.state != TC.PState.FINISHED:
			if p.state == TC.PState.CAPTURED:
				continue
			_finish(p)
	return 0.5


# ---------------------------------------------------------------- results
## A three-round friend series (DETERMINISTIC DEV STATE: results built from
## these rows and recorded through PartySeries, so the Round Wins, shared
## places, the late join and the away round are the real rules' output).
func _rows(oc: int, my_role: int, away_uid := "", late := false) -> Dictionary:
	var me := Save.player_uid()
	var rows: Array = [
		{"slot": 0, "uid": me, "name": Save.player_name(), "is_bot": false, "role": my_role, "stamps": 3, "finished": my_role == TC.Role.RUNNER and oc == TC.Outcome.RUNNERS_WIN,
			"finish_order": 2, "finish_time": 151.0, "times_captured": 1, "captures": 3 if my_role == TC.Role.PATROL else 0, "unique_captures": 2 if my_role == TC.Role.PATROL else 0, "present": true, "away_s": 0.0},
		{"slot": 1, "uid": "uid-ana", "name": "Ana", "is_bot": false, "role": TC.Role.RUNNER if my_role == TC.Role.PATROL else TC.Role.PATROL, "stamps": 3, "finished": true,
			"finish_order": 1, "finish_time": 132.0, "captures": 1, "unique_captures": 1, "present": true, "away_s": 0.0},
		{"slot": 2, "uid": "uid-bo", "name": "Bo", "is_bot": false, "role": TC.Role.RUNNER, "stamps": 2, "finished": false, "times_captured": 2,
			"present": true, "away_s": 130.0 if away_uid == "uid-bo" else 0.0},
		{"slot": 3, "uid": "bot-3", "name": "Bot Snooze", "is_bot": true, "role": TC.Role.RUNNER, "stamps": 3, "finished": oc == TC.Outcome.RUNNERS_WIN, "finish_order": 3, "finish_time": 170.0},
		{"slot": 4, "uid": "bot-4", "name": "Bot Pillow", "is_bot": true, "role": TC.Role.RUNNER, "stamps": 1},
		{"slot": 5, "uid": "bot-5", "name": "Bot Yawn", "is_bot": true, "role": TC.Role.RUNNER, "stamps": 3, "finished": oc == TC.Outcome.RUNNERS_WIN, "finish_order": 4, "finish_time": 199.0},
		{"slot": 6, "uid": "bot-6", "name": "Bot Drowsy", "is_bot": true, "role": TC.Role.PATROL, "captures": 2, "unique_captures": 2},
		{"slot": 7, "uid": "bot-7", "name": "Bot Nap", "is_bot": true, "role": TC.Role.PATROL},
	]
	if late:
		rows[7] = {"slot": 7, "uid": "uid-cy", "name": "Cy", "is_bot": false, "role": TC.Role.RUNNER, "stamps": 3, "finished": oc == TC.Outcome.RUNNERS_WIN,
			"finish_order": 5, "finish_time": 210.0, "present": true, "away_s": 0.0}
	var fin := 4 if oc == TC.Outcome.RUNNERS_WIN else 2
	return {"match_id": "p8-%d-%d" % [oc, my_role], "outcome": oc, "players": rows, "finished": fin, "needed": 4, "watch": 2,
		"round_time": 199.0 if oc == TC.Outcome.RUNNERS_WIN else 240.0, "practice": false}


func _series(rounds: Array) -> PartySeries:
	var ps := PartySeries.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	ps.start({"watch": 2, "rounds": 3}, rng)
	for i in rounds.size():
		var r: Dictionary = rounds[i]
		r["match_id"] = "p8-s%d" % i
		ps.record_round(r)
	return ps


func _show_results(res: Dictionary, ps: PartySeries, idx: int) -> ResultsScreen:
	if _host == null:
		_host = NetSession.new()
		_host.mode = NetSession.Mode.HOST
		_host.local_slot = 0
		add_child(_host)
	res["series"] = ps.to_dict()
	res["round_index"] = idx
	res["rounds_total"] = 3
	_host.series = ps
	_host.series_view = res["series"]
	if App.screen and is_instance_valid(App.screen):
		App.screen.queue_free()
		App.screen = null
	var r := ResultsScreen.new()
	r.results = res
	r.reward = {"coins": 18, "xp": 40, "lines": [["Played the round", 10], ["Team win", 4]]}
	r.session = _host
	App._ensure_background()
	App._show(r)
	return r


## SIMULATED WALLET (dev fixture, labelled in the shot JSON): the game
## service isn't deployed, so these shots show the results card's settled
## and pending states from a stand-in Wallet.round_summary - the same shape
## the real wallet returns (docs/ECONOMY.md); a "challenges" list in the
## CHALLENGES stream's documented shape shows that slot.
var _wallet_state := ""


func _sim_wallet(mid: String) -> Dictionary:
	var settled := _wallet_state == "settled"
	var d := {"state": _wallet_state, "message": "Added to your account." if settled else "Adding your rewards… they're checked by the game service and saved once.",
		"coins_collected": 3, "coins": 18 if settled else 0, "coins_projected": 18, "season_xp": 85 if settled else 0, "season_xp_projected": 85,
		"tier_before": 6, "tier_after": 7, "frac_before": 0.82, "frac_after": 0.11,
		"lines": [["Completed the round", 10], ["Each coin", 3], ["Team win", 4], ["Home", 3]], "season_lines": [["Completed the round", 50], ["Splashes", 30]]}
	if settled:
		d["challenges"] = [{"title": "Campus Contribution", "state": "settled", "xp": 50}, {"title": "Night Shift", "state": "progress", "progress": 1, "goal": 2}]
	return d


## Round 2 of 3: your team (runners) won; you and Ana are tied 1st.
func _series_round() -> float:
	_wallet_state = "settled"
	RoundRewards.wallet_override = _sim_wallet
	var r1 := _rows(TC.Outcome.PATROL_WIN, TC.Role.RUNNER)
	var r2 := _rows(TC.Outcome.RUNNERS_WIN, TC.Role.RUNNER, "uid-bo")
	var ps := _series([r1, r2])
	_show_results(_rows(TC.Outcome.RUNNERS_WIN, TC.Role.RUNNER, "uid-bo"), ps, 2)
	get_tree().create_timer(2.0).timeout.connect(_snap.bind("results_round2_your_team_won_series_tied"))
	return 2.8


## The last round (you on the Night Watch, the runners win), then Final
## standings: shared places, a late join (Cy, round 3) and an away round
## (Bo, round 2), bots never ranked.
func _series_final() -> float:
	RoundRewards.wallet_override = Callable()
	var r1 := _rows(TC.Outcome.PATROL_WIN, TC.Role.RUNNER)
	var r2 := _rows(TC.Outcome.RUNNERS_WIN, TC.Role.RUNNER, "uid-bo")
	var r3 := _rows(TC.Outcome.RUNNERS_WIN, TC.Role.PATROL, "", true)
	var ps := _series([r1, r2, r3])
	var rs := _show_results(_rows(TC.Outcome.RUNNERS_WIN, TC.Role.PATROL, "", true), ps, 3)
	get_tree().create_timer(2.0).timeout.connect(_snap.bind("results_round3_your_team_lost_last_round"))
	get_tree().create_timer(2.6).timeout.connect(func() -> void:
		if is_instance_valid(rs):
			rs._on_primary())
	get_tree().create_timer(4.4).timeout.connect(_snap.bind("results_final_standings_ties_late_join_away"))
	return 5.2


func _series_watch_lost() -> float:
	_wallet_state = "pending"
	RoundRewards.wallet_override = _sim_wallet
	var r1 := _rows(TC.Outcome.PATROL_WIN, TC.Role.RUNNER)
	var ps := _series([r1])
	_show_results(_rows(TC.Outcome.PATROL_WIN, TC.Role.RUNNER), ps, 1)
	get_tree().create_timer(2.0).timeout.connect(_snap.bind("results_round1_your_team_lost_time_expired"))
	return 2.8


func _series_cancelled() -> float:
	RoundRewards.wallet_override = Callable()
	var r1 := _rows(TC.Outcome.PATROL_WIN, TC.Role.RUNNER)
	var ps := _series([r1])
	var res := _rows(TC.Outcome.CANCELLED, TC.Role.RUNNER)
	_show_results(res, ps, 2)
	get_tree().create_timer(2.0).timeout.connect(_snap.bind("results_cancelled_round_counts_for_nothing"))
	return 2.8


# ---------------------------------------------------------------- layout facts
func _hud_json(n: String) -> void:
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	var view := vp.get_visible_rect()
	var safe := UIKit.safe_rect(vp, view.size)
	var upp := UIKit.units_per_point()
	var out := {"shot": n, "state": "DETERMINISTIC DEV STATE (driver: src/dev/capture_pass8_match.gd)",
		"rewards": ("SIMULATED WALLET (dev fixture): " + _wallet_state) if RoundRewards.wallet_override.is_valid() else "the build's real wallet state", "viewport": [view.size.x, view.size.y],
		"units_per_point": upp, "points": [view.size.x / upp, view.size.y / upp], "touch_min_units": UIKit.touch_min(),
		"safe": [safe.position.x, safe.position.y, safe.size.x, safe.size.y], "rects": {}, "overlaps": []}
	var mc := _mc()
	if mc != null and App.screen == null:
		var hud := mc.hud
		var rects := {"goal_bar": hud.goal_bar.get_global_rect(), "personal_card": hud.personal.get_global_rect(),
			"pause": hud.pause_btn.get_global_rect(), "minimap": hud.minimap.get_global_rect()}
		if hud.danger_chip.visible:
			rects["danger_chip"] = hud.danger_chip.get_global_rect()
		var res: Dictionary = mc.touch.surface.res if mc.touch else {}
		for bn in res.get("buttons", {}):
			var b: Dictionary = res["buttons"][bn]
			rects["thumb_" + String(bn)] = Rect2(b["c"] - Vector2.ONE * float(b["hit"]), Vector2.ONE * float(b["hit"]) * 2.0)
		if res.has("stick_c"):
			var sr := float(res["stick_r"])
			rects["thumb_stick"] = Rect2(res["stick_c"] - Vector2.ONE * sr, Vector2.ONE * sr * 2.0)
		var ks := rects.keys()
		for k in ks:
			var r: Rect2 = rects[k]
			out["rects"][k] = {"units": [snappedf(r.position.x, 0.1), snappedf(r.position.y, 0.1), snappedf(r.size.x, 0.1), snappedf(r.size.y, 0.1)],
				"points": [snappedf(r.position.x / upp, 0.1), snappedf(r.position.y / upp, 0.1), snappedf(r.size.x / upp, 0.1), snappedf(r.size.y / upp, 0.1)]}
		for i in ks.size():
			for j in range(i + 1, ks.size()):
				var a: String = ks[i]
				var b2: String = ks[j]
				if a.begins_with("thumb_") and b2.begins_with("thumb_"):
					continue
				if (rects[a] as Rect2).intersects(rects[b2]):
					(out["overlaps"] as Array).append([a, b2])
		out["personal_rows"] = []
		for r in hud.personal_rows:
			(out["personal_rows"] as Array).append(String(r["text"]))
		out["goal"] = hud.goal_lbl.text + " " + hud.timer_lbl.text
		out["clipped_card_words"] = hud.personal.clipped_rows()
	var f := FileAccess.open(cap.get("out_dir").path_join(n + "_hud.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, "  "))
	printerr("HUDJSON %s overlaps=%s" % [n, str(out["overlaps"])])
