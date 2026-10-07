extends Node
## V8 gameplay bench (development only; src/dev is never exported).
##
## Plays whole Practice rounds through the real App flow (practice start ->
## loading screen -> round -> results -> menu -> next round), 8 slots: the
## local runner is driven by a BotBrain like the 7 bots (crowded chases,
## splashes of every kind, tags, captures, carts, coins, finishes, confetti).
## The engine runs on the real clock with a frame cap (--fps), like a phone
## at Standard (60) or Battery Saver (30).
##
## Per frame it records the engine-loop interval, the physics ticks run, and
## the CPU time of each instrumented section (Prof: character views and their
## animation evaluation, skeleton modifiers, the match controller's event,
## view, world, camera and HUD passes, effects, the governor; MatchSim.prof:
## the simulation's sections).  It notes the frame each event type first
## shows (cold caches) and reads objects/nodes/memory at every round start.
## Every frame also lists the events it presented (and the match
## controller's time per event type, ev_*), and bot path searches over 8 ms
## (NavGrid.debug_slow_searches) are kept with the frame they ran in.
##
## Headless (the dummy renderer) this measures the CPU side of a frame on the
## machine it runs on; with a window it also reads the renderer's draw calls
## and primitives.  Neither is a phone measurement.
##
##   tools/match_bench.sh OUT.json [--fps=60] [--rounds=3] [--round-secs=75] [--seed=7] [--quality=1]

var fps := 60
var rounds := 3
var round_secs := 75.0
var seed_v := 7
var quality := 1
var out_path := ""

var _frames: Array = []          # per-frame records during PLAYING
var _ctx_counts := {}            # context -> frames
var _ctx_long := {}              # context -> [ >33, >50, >100, worst ms, worst's round, context before it ]
var _prev_ctx := ""
var _last_us := 0
var _round := 0
var _round_t := 0.0
var _mc: MatchController
var _takeover_done := false
var _first_events := {}          # "round:type" -> frame index (in _frames)
var _pending_events: Array = []
var _round_starts: Array = []
var _done := false
var _wait_t := 0.0
var _state := "boot"
var _prev_prof := {}
var _render_samples: Array = []
var _render_t := 0.0
var _nav: NavGrid
var map_id := CampusMaps.DEFAULT_ID
## --lifecycle: keep only a compact interval per frame (no per-frame
## records), so memory read at each round start is the game's own: the full
## records are ~2.5 KB a frame and grow the process by ~11 MB per 75 s round
var lifecycle := false
var _iv_only := PackedFloat32Array()
var _slow: Array = []            # [frame, round, from, to, cart, ms, points]


func _ready() -> void:
	process_priority = -100000       # first in every frame: the previous frame is complete
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		var v := a.get_slice("=", 1)
		if a.begins_with("--fps="):
			fps = int(v)
		elif a.begins_with("--rounds="):
			rounds = int(v)
		elif a.begins_with("--round-secs="):
			round_secs = float(v)
		elif a.begins_with("--seed="):
			seed_v = int(v)
		elif a.begins_with("--quality="):
			quality = int(v)
		elif a.begins_with("--out="):
			out_path = v
		elif a == "--lifecycle":
			lifecycle = true
		elif a.begins_with("--map="):
			map_id = CampusMaps.sanitize(v)
	Save.set_setting("quality", quality)
	Save.set_setting("practice_map", map_id)
	Save.data["onboarded"] = true
	QualityPreset.apply(quality)
	Engine.max_fps = fps
	App.dev_seed = seed_v
	Prof.on = true
	MatchSim.prof_on = true
	MatchSim.prof = {}
	_nav = NavGrid.shared(CampusMaps.layout(map_id))
	_nav.debug_slow_searches = []
	printerr("BENCH start fps=%d rounds=%d round_secs=%.0f seed=%d quality=%d renderer=%s" % [fps, rounds, round_secs, seed_v, quality, DisplayServer.get_name()])


func _context() -> String:
	if App.match_ctrl != null and is_instance_valid(App.match_ctrl):
		var mc := App.match_ctrl
		if not mc.prepared:
			return "loading"
		if mc.sim and mc.sim.phase == TC.Phase.PLAYING:
			return "playing"
		return "match_other"
	return "menu"


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var iv := (now - _last_us) / 1000.0 if _last_us > 0 else 0.0
	_last_us = now
	var ctx := _context()
	var p := Prof.take()
	var sim_prof := MatchSim.prof.duplicate()
	var sim_d := {}
	for k in sim_prof:
		sim_d[k] = int(sim_prof[k]) - int(_prev_prof.get(k, 0))
	_prev_prof = sim_prof
	if iv > 0.0:
		_ctx_counts[ctx] = int(_ctx_counts.get(ctx, 0)) + 1
		var lg: Array = _ctx_long.get(ctx, [0, 0, 0, 0.0, 0, ""])
		if iv > 33.3:
			lg[0] += 1
		if iv > 50.0:
			lg[1] += 1
		if iv > 100.0:
			lg[2] += 1
		if iv > float(lg[3]):
			# where it fell: the round, and the context the frame came from
			# (a menu frame after "match_other" is a round being torn down)
			lg[3] = iv
			lg[4] = _round
			lg[5] = _prev_ctx
		_ctx_long[ctx] = lg
	_prev_ctx = ctx
	if ctx == "playing" and iv > 0.0:
		var rec := {"iv": iv, "ticks": int(p["n"].get("ticks", 0)), "round": _round,
			"views_n": int(p["n"].get("views_processed", 0)), "adv_n": int(p["n"].get("anim_advances", 0))}
		for k in p["us"]:
			rec[k] = float(p["us"][k]) / 1000.0
		for k in sim_d:
			rec["sim_" + k] = float(sim_d[k]) / 1000.0
		# the engine's own measure of the last frame's process and physics
		# passes (catches time no instrumented section explains)
		rec["eng_process"] = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		rec["eng_physics"] = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		rec["pace_tasks"] = float(PaceFields.stats.get("tasks", 0))
		var names: Array = []
		for ev in _pending_events:
			var key := "%d:%d" % [_round, int(ev)]
			if not _first_events.has(key):
				_first_events[key] = _frames.size()
			names.append(str(TC.Ev.find_key(int(ev))))
		_pending_events.clear()
		if not names.is_empty():
			rec["events"] = names
		var sl: Array = _nav.debug_slow_searches
		if not sl.is_empty():
			var mine: Array = []
			for e in sl:
				mine.append(e[3])
				_slow.append([_frames.size(), _round, str(e[0]), str(e[1]), e[2], e[3], e[4]])
			rec["slow_paths_ms"] = mine
			sl.clear()
		if lifecycle:
			_iv_only.append(iv)
		else:
			_frames.append(rec)
	if DisplayServer.get_name() != "headless" and ctx == "playing":
		_render_t += delta
		if _render_t >= 1.0:
			_render_t = 0.0
			_render_samples.append({
				"draw": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				"prims": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
				"objects": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)})
	_drive(delta)


func _drive(delta: float) -> void:
	match _state:
		"boot":
			_wait_t += delta
			if _wait_t > 1.5:
				_start_round()
		"round":
			var mc := App.match_ctrl
			if mc == null or not is_instance_valid(mc):
				# the round ended and the app went on to results / the menu
				_state = "between"
				_wait_t = 0.0
				return
			if mc != _mc:
				_mc = mc
				_takeover_done = false
				_round_t = 0.0
				if mc.sim:
					mc.sim.event_emitted.connect(func(ev: Dictionary) -> void: _pending_events.append(int(ev["type"])))
			if mc.prepared and mc.sim and mc.sim.phase >= TC.Phase.REVEAL and not _takeover_done:
				_takeover_done = true
				var lp := mc.sim.player(mc.local_slot)
				if lp:
					lp.bot_takeover = true
					mc.sim.bots[lp.id] = BotBrain.new(mc.sim, lp)
				# (and the round's loading: time, frames, the longest job; the
				# host sim's collision shapes)
				var shapes := 0
				for body_name in ["WorldCollision", "CartBlockers", "GroundCollision"]:
					var body := mc.sim.get_node_or_null(body_name)
					if body != null:
						shapes += body.get_child_count()
				_round_starts.append({"round": _round, "objects": Performance.get_monitor(Performance.OBJECT_COUNT),
					"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
					"orphans": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
					"static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
					"prepare_ms": mc.prepare_ms, "prep_frames": mc.prep_frames, "prep_longest": mc.prep_longest,
					"collision_shapes": shapes, "map": map_id})
			if mc.sim and mc.sim.phase == TC.Phase.PLAYING:
				_round_t += delta
				if _round_t > round_secs and mc.sim.end_tick > mc.sim.tick + 2:
					mc.sim.end_tick = mc.sim.tick + 2
		"between":
			_wait_t += delta
			# results, then the menu, as a player would see them
			if _wait_t > 4.0:
				if _round >= rounds:
					_finish()
				else:
					_start_round()


func _start_round() -> void:
	_round += 1
	_state = "round"
	_wait_t = 0.0
	App.dev_seed = seed_v + _round
	App.start_practice("runner", false)


static func _pct(a: PackedFloat32Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return s[clampi(int(ceil(q * s.size())) - 1, 0, s.size() - 1)]


func _finish() -> void:
	if _done:
		return
	_done = true
	var iv := PackedFloat32Array()
	var sections := {}
	if lifecycle:
		iv = _iv_only
	for r in _frames:
		iv.append(float(r["iv"]))
		for k in r:
			if k in ["iv", "round", "events", "slow_paths_ms"]:
				continue
			if not sections.has(k):
				sections[k] = PackedFloat32Array()
	for k in sections:
		var arr: PackedFloat32Array = sections[k]
		for r in _frames:
			arr.append(float(r.get(k, 0.0)))
	var summary := {"fps": fps, "rounds": rounds, "round_secs": round_secs, "seed": seed_v, "quality": quality,
		"map": map_id, "renderer": DisplayServer.get_name(), "engine": Engine.get_version_info()["string"],
		"frames": _frames.size(), "interval": {}, "sections": {}, "contexts": {}, "first_events": {}, "round_starts": _round_starts}
	summary["interval"] = {"p50": _pct(iv, 0.5), "p95": _pct(iv, 0.95), "p99": _pct(iv, 0.99), "max": _pct(iv, 1.0),
		"over33": _count_over(iv, 33.3),
		"over50": _count_over(iv, 50.0), "over100": _count_over(iv, 100.0), "clusters": _clusters(iv)}
	for k in sections:
		var a: PackedFloat32Array = sections[k]
		var tot := 0.0
		for x in a:
			tot += x
		summary["sections"][k] = {"mean": tot / maxf(1.0, a.size()), "p95": _pct(a, 0.95), "p99": _pct(a, 0.99), "max": _pct(a, 1.0)}
	for c in _ctx_counts:
		summary["contexts"][c] = {"frames": _ctx_counts[c], "over33": _ctx_long[c][0], "over50": _ctx_long[c][1], "over100": _ctx_long[c][2], "worst": _ctx_long[c][3],
			"worst_round": _ctx_long[c][4], "worst_after": _ctx_long[c][5]}
	for key in _first_events:
		var i: int = _first_events[key]
		var worst := 0.0
		for j in range(i, mini(i + 3, _frames.size())):
			worst = maxf(worst, float(_frames[j]["iv"]))
		summary["first_events"][key] = {"frame": i, "worst_iv_next3": worst}
	if not _render_samples.is_empty():
		summary["render"] = _render_samples
	# the 15 longest frames, with where their time went (and first events)
	var order := range(_frames.size())
	order.sort_custom(func(a: int, b: int) -> bool: return float(_frames[a]["iv"]) > float(_frames[b]["iv"]))
	var worst: Array = []
	for i in order.slice(0, 15):
		var r: Dictionary = _frames[i].duplicate()
		var firsts: Array = []
		for key in _first_events:
			if int(_first_events[key]) == i or int(_first_events[key]) == i - 1:
				firsts.append(key)
		r["index"] = i
		r["first_events"] = firsts
		worst.append(r)
	summary["worst_frames"] = worst
	summary["slow_searches"] = _slow
	summary["nav"] = {"path_stats": _nav.path_stats.duplicate(), "waits": _nav.get("stat_wait_n"),
		"waited_ms": float(_nav.get("stat_waited_us")) / 1000.0 if _nav.get("stat_waited_us") != null else null}
	var txt := JSON.stringify(summary, " ")
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(txt)
	printerr("BENCH interval p50 %.2f p95 %.2f p99 %.2f max %.1f ms; >33 %d >50 %d >100 %d; frames %d" % [
		summary["interval"]["p50"], summary["interval"]["p95"], summary["interval"]["p99"], summary["interval"]["max"],
		summary["interval"]["over33"], summary["interval"]["over50"], summary["interval"]["over100"], _frames.size()])
	var keys: Array = summary["sections"].keys()
	keys.sort()
	for k in keys:
		var s: Dictionary = summary["sections"][k]
		printerr("BENCH %-22s mean %7.3f p95 %7.3f p99 %7.3f max %7.2f" % [k, s["mean"], s["p95"], s["p99"], s["max"]])
	for r in summary["worst_frames"]:
		var parts: PackedStringArray = []
		for k in r:
			if k in ["iv", "index", "round", "first_events", "views_n", "adv_n", "events", "slow_paths_ms"]:
				continue
			if float(r[k]) >= 0.5:
				parts.append("%s %.1f" % [k, float(r[k])])
		printerr("BENCH worst %6.1f ms  round %d frame %d  %s  %s %s %s" % [r["iv"], r["round"], r["index"], " ".join(parts), str(r["first_events"]),
			str(r.get("events", "")), ("paths " + str(r["slow_paths_ms"])) if r.has("slow_paths_ms") else ""])
	var cart_n := 0
	var foot_n := 0
	var worst_ms := 0.0
	for e in _slow:
		if bool(e[4]):
			cart_n += 1
		else:
			foot_n += 1
		worst_ms = maxf(worst_ms, float(e[5]))
	printerr("BENCH slow path searches (>8 ms): foot %d cart %d worst %.1f ms; %s" % [foot_n, cart_n, worst_ms, JSON.stringify(summary["nav"])])
	printerr("BENCH DONE")
	get_tree().quit()


static func _count_over(a: PackedFloat32Array, ms: float) -> int:
	var n := 0
	for x in a:
		if x > ms:
			n += 1
	return n


## Runs of consecutive frames over 33.3 ms: count and the longest run's total.
static func _clusters(a: PackedFloat32Array) -> Dictionary:
	var runs := 0
	var longest := 0.0
	var cur := 0.0
	for x in a:
		if x > 33.3:
			if cur == 0.0:
				runs += 1
			cur += x
			longest = maxf(longest, cur)
		else:
			cur = 0.0
	return {"runs": runs, "longest_ms": longest}
