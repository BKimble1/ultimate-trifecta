class_name MatchController
extends Node3D
## One round of Trifecta Chase on this device.
##  - Host / practice: runs the authoritative MatchSim and renders it directly.
##  - Client: predicts its own character (and cart) with the shared Motor,
##    reconciles against host snapshots, and interpolates everyone else.
## Simulation, input, presentation, transport and persistence stay separate.

signal finished(results: Dictionary)
signal quit_requested

var session: NetSession
var start: Dictionary
var cfg: RulesConfig
var layout: CampusLayout
var local_slot := -1
var is_client := false
var spectator := false
var targets: Array = []
var roster: Dictionary = {}   # slot -> start roster entry
var quality := 1
var reduced_motion := false
var with_visuals := true
## Tests/automation: Callable(mc) -> InputCmd used instead of device input.
var input_source: Callable
# measurements (network tests / soak runs)
var stat_corrections: Array[float] = []
var stat_snapshots := 0
var stat_big: Array = []

# host
var sim: MatchSim
var _results_sent := false

# client
var pred: SimPlayer
var pred_cart: SimCart
var pred_cart_id := -1
var client_world: Node3D
var cart_proxies: Array[AnimatableBody3D] = []
var _pending: Array = []      # InputCmd not yet acknowledged
var _last_ack := 0
var _sent_window: Array = []
var _next_seq := 1
var _est_tick: float = 0.0
var _have_clock := false
var _bufs: Dictionary = {}    # slot -> Array of {tick, e}
var _cart_bufs: Array = []
var _last_snap: Dictionary = {}
var _me: Dictionary = {}
var _smooth := Vector3.ZERO
var _client_phase: int = TC.Phase.REVEAL
var _client_results: Dictionary = {}
var _interp_ticks := 7.0
var _snap_gap_avg := 3.0
var _last_snap_tick := -1
var _seen_tick: Dictionary = {}

# presentation
var views: Dictionary = {}     # slot -> CharacterView
var cart_views: Array[CartView] = []
var water_nodes: Dictionary = {}
var beacons: Dictionary = {}   # water index -> MeshInstance3D
var pickup_views: Array[Node3D] = []
var camera: FollowCamera
var hud: MatchHUD
var touch: TouchControls
var fx: Fx
var spectate_slot := -1
# render-time interpolation: state captured at the last two physics ticks
var _tick_prev: Dictionary = {}   # slot -> rs at the previous tick
var _tick_cur: Dictionary = {}    # slot -> rs at the latest tick
var _cart_prev: Dictionary = {}   # cart index -> rs
var _cart_cur: Dictionary = {}
var _discont: Dictionary = {}     # slot -> true: snap + reset presentation history
var _cam_follow := -2
var _foliage_mat: ShaderMaterial   # canopy see-through around the followed character
var _local_events: Array = []
var _shake_cd := 0.0
var _phase_seen := -1
var _countdown_last := -1
var _finish_sent := false
var _prev_server_state := -1


func setup(p_session: NetSession, p_start: Dictionary, settings: Dictionary) -> void:
	session = p_session
	start = p_start
	# this round's immutable rules (party settings) - never the global default
	cfg = PartySeries.rules_for(Rules.cfg, int((start.get("settings", {}) as Dictionary).get("watch", PartySeries.DEFAULT_WATCH)))
	layout = CampusLayout.shared()
	is_client = session.mode == NetSession.Mode.CLIENT
	local_slot = session.local_slot
	quality = int(settings.get("quality", 1))
	reduced_motion = bool(settings.get("reduced_motion", false))
	with_visuals = bool(settings.get("visuals", true))
	# tests and tools without a loading screen prepare in one go
	staged = bool(settings.get("staged", with_visuals))
	targets = start["targets"]
	for e in start["roster"]:
		roster[int(e["slot"])] = e
	spectator = not roster.has(local_slot)


# --- staged preparation (V4): the round is made in short steps so the
# loading screen keeps animating; the campus look is kept between rounds.
signal prepared_now
const PREP_BUDGET_US := 9000
## Every step of a round's preparation is done (sim attached, views built).
var prepared := false
## App: shows the current preparation stage on the loading screen.
var stage_report: Callable
var _prep: Array[Callable] = []
var _prep_i := 0
var _builder: CampusBuilder
var _campus: Node3D
var _view_queue: Array = []
var _prep_t0 := 0
var prepare_ms := 0.0
var prep_frames := 0
var prep_max_ms := 0.0     # longest single frame of preparation work
var staged := true

## The campus look (meshes, waters, canopy material) outlives a round: it is
## static for a layout and quality, so rematches reuse it instead of
## regenerating ~60 meshes.  App releases it here when a round ends.
static var _campus_cache: Dictionary = {}


func _ready() -> void:
	Diag.mark("load_begin")
	_prep_t0 = Time.get_ticks_usec()
	_prep = [_prep_campus, _prep_world, _prep_ground, _prep_nav, _prep_sim, _prep_views, _prep_rest]
	_prep_i = 0
	if not staged:
		while _prep_i < _prep.size():
			_prep_run_one()
		_finish_prepare()


func _process_prepare() -> void:
	var f0 := Time.get_ticks_usec()
	while _prep_i < _prep.size() and Time.get_ticks_usec() - f0 < PREP_BUDGET_US:
		_prep_run_one()
	prep_frames += 1
	prep_max_ms = maxf(prep_max_ms, float(Time.get_ticks_usec() - f0) / 1000.0)
	if _prep_i >= _prep.size():
		_finish_prepare()


func _prep_run_one() -> void:
	var again: Variant = _prep[_prep_i].call()
	if not (again is bool and again):
		_prep_i += 1


func _stage(text: String) -> void:
	if stage_report.is_valid():
		stage_report.call(text)


func _prep_campus() -> bool:
	if not with_visuals:
		return false
	if _builder == null:
		_stage("Getting campus ready…")
		if _take_cached_campus():
			Diag.mark("campus_cached")
			return false
		_builder = CampusBuilder.new(layout)
		_builder.begin_visuals(self, quality)
	if _builder.step():
		return true
	water_nodes = _builder.water_nodes
	_foliage_mat = _builder.foliage_material
	_campus = _builder.container
	_builder = null
	Diag.mark("campus_built")
	return false


func _take_cached_campus() -> bool:
	var c := _campus_cache
	if c.is_empty() or not is_instance_valid(c.get("node")) or c.get("layout") != layout or int(c.get("quality", -1)) != quality:
		_campus_cache = {}
		return false
	_campus = c["node"]
	_campus_cache = {}
	if _campus.get_parent():
		_campus.get_parent().remove_child(_campus)
	add_child(_campus)
	water_nodes = c["water"]
	_foliage_mat = c["foliage"]
	# per-round state on the shared materials starts clean
	for wid in water_nodes:
		var m: ShaderMaterial = water_nodes[wid]["mat"]
		m.set_shader_parameter("active", 0.0)
		m.set_shader_parameter("stamped", 0.0)
		var empty: Array[Vector4] = []
		for i in Fx.RIPPLE_SLOTS:
			empty.append(Vector4.ZERO)
		m.set_shader_parameter("ripples", empty)
	if _foliage_mat:
		_foliage_mat.set_shader_parameter("focus", Vector4.ZERO)
	return true


## App, when the round ends: keep the campus look for the next round.
func release_campus() -> void:
	if _campus == null or not is_instance_valid(_campus) or _campus.get_parent() != self:
		return
	remove_child(_campus)
	_campus_cache = {"node": _campus, "water": water_nodes, "foliage": _foliage_mat, "quality": quality, "layout": layout}
	_campus = null


## Frees the kept campus (tests, quality change, low memory).
static func drop_campus_cache() -> void:
	var n: Variant = _campus_cache.get("node")
	if n is Node and is_instance_valid(n) and (n as Node).get_parent() == null:
		(n as Node).free()
	_campus_cache = {}


static func campus_cached() -> bool:
	return not _campus_cache.is_empty() and is_instance_valid(_campus_cache.get("node"))


func _prep_world() -> void:
	if with_visuals:
		add_child(EnvFactory.make_environment(quality))
		add_child(EnvFactory.make_moon(quality))
	fx = Fx.new()
	add_child(fx)
	if with_visuals:
		fx.warm()
	_build_beacons()
	_build_pickups()


## Data every round shares, built once per session in steps of their own:
## the ground collision shape and (host) the bots' navigation grid.
func _prep_ground() -> void:
	CampusBuilder.ground_shape(layout)


func _prep_nav() -> void:
	if not is_client:
		NavGrid.shared(layout)


func _prep_sim() -> void:
	_stage("Placing players…")
	if is_client:
		_setup_client_world()
	else:
		sim = MatchSim.new()
		sim.name = "Sim"
		add_child(sim)
		sim.setup(cfg, layout, start["roster"], int(start["seed"]), targets, String(start["match_id"]),
			{"practice": bool(start.get("practice", false)), "tutorial": bool(start.get("tutorial", false)),
			"patrol_release_extra_s": 24.0 if bool(start.get("tutorial", false)) else 0.0,
			"bot_factory": func(s: MatchSim, p: SimPlayer) -> BotBrain: return BotBrain.new(s, p)})
		session.attach_sim(sim)
		sim.event_emitted.connect(func(ev: Dictionary) -> void: _local_events.append(ev))
		if App.dev_local_bot and sim.player(local_slot) != null:
			var lp := sim.player(local_slot)
			lp.bot_takeover = true
			sim.bots[local_slot] = BotBrain.new(sim, lp)
	_view_queue = roster.keys()


## One character per call (each is a full rig with its animation tree).
func _prep_views() -> bool:
	if _view_queue.is_empty():
		return false
	var slot: int = int(_view_queue.pop_front())
	var e: Dictionary = roster[slot]
	var v := CharacterView.new()
	v.reduced_motion = reduced_motion
	v.fx = fx
	v.water_at = _water_info
	add_child(v)
	v.setup(int(e["role"]), e["cosmetic"], slot, String(e["name"]), bool(e["is_bot"]), slot == local_slot)
	views[slot] = v
	return not _view_queue.is_empty()


func _prep_rest() -> void:
	for i in cfg.cart_count:
		var cv := CartView.new()
		add_child(cv)
		cv.setup(i)
		cart_views.append(cv)
		_cart_bufs.append([])

	camera = FollowCamera.new()
	camera.reduced_motion = reduced_motion
	add_child(camera)
	camera.current = true

	hud = MatchHUD.new()
	add_child(hud)
	hud.setup(self)
	touch = TouchControls.new()
	add_child(touch)
	touch.setup(self)
	if is_client:
		session.snapshot_received.connect(_on_snapshot)
		session.events_received.connect(func(evs: Array) -> void: _local_events.append_array(evs))
		session.results_received.connect(func(r: Dictionary) -> void: _client_results = r)
	else:
		session.events_received.connect(func(evs: Array) -> void:
			for ev in evs:
				if int(ev["type"]) == TC.Ev.EMOTE:
					_local_events.append(ev))
	# initial camera placement
	var p0 := _player_rs(local_slot if not spectator else _first_slot())
	camera.snap_to(p0.get("pos", Vector3.ZERO), p0.get("yaw", 0.0))


func _finish_prepare() -> void:
	if prepared:
		return
	prepared = true
	prepare_ms = float(Time.get_ticks_usec() - _prep_t0) / 1000.0
	Diag.mark("campus_prepared")
	if staged:
		print("[load] round prepared in %.0f ms over %d frames (longest frame of work %.1f ms)" % [prepare_ms, prep_frames, prep_max_ms])
	if is_client:
		session.send_loaded()
	else:
		session.mark_local_loaded()
	Sfx.music("chase_calm")
	prepared_now.emit()


## The round is under way on this device: the loading screen can go
## (host: every player has loaded or the wait timed out; guest: the host's
## first snapshot is here; practice: prepared).
func round_live() -> bool:
	if not prepared:
		return false
	if is_client:
		return stat_snapshots > 0
	return session.loads_complete()


func _first_slot() -> int:
	for s in roster:
		return int(s)
	return 0


# ---------------------------------------------------------------------------
# Client world: collision + predicted body
# ---------------------------------------------------------------------------
func _setup_client_world() -> void:
	client_world = Node3D.new()
	client_world.name = "ClientWorld"
	add_child(client_world)
	CampusBuilder.new(layout).build_collision(client_world)
	if not spectator:
		pred = SimPlayer.new()
		pred.id = local_slot
		pred.role = int(roster[local_slot]["role"])
		pred.body = Motor.make_character_body("Pred")
		client_world.add_child(pred.body)
		# same spawn assignment as MatchSim.setup (roster order)
		var ri := 0
		var pi := 0
		var sp := Vector2.ZERO
		for e in start["roster"]:
			var is_r := int(e["role"]) == TC.Role.RUNNER
			if int(e["slot"]) == local_slot:
				sp = layout.runner_spawns[ri % layout.runner_spawns.size()] if is_r else layout.patrol_spawns[pi % layout.patrol_spawns.size()]
				pred.yaw = 0.0 if is_r else PI
			if is_r:
				ri += 1
			else:
				pi += 1
		pred.body.global_position = Vector3(sp.x, 0.05, sp.y)
		if pred.is_patrol():
			pred.state = TC.PState.WAITING
	for i in cfg.cart_count:
		var ab := AnimatableBody3D.new()
		ab.collision_layer = TC.L_CART
		ab.collision_mask = 0
		ab.sync_to_physics = false
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = SimCart.HALF * 2.0 - Vector3(0, 0.6, 0)
		cs.shape = bx
		cs.position = Vector3(0, SimCart.HALF.y, 0)
		ab.add_child(cs)
		client_world.add_child(ab)
		cart_proxies.append(ab)


# ---------------------------------------------------------------------------
# Per tick
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if not prepared:
		return
	var cmd := _build_local_cmd()
	if is_client:
		_client_tick(cmd, delta)
	else:
		_host_tick(cmd, delta)
	_capture_tick()


const _TELEPORT_STATES := [TC.PState.CAPTURED, TC.PState.SPLASHING, TC.PState.ENTERING, TC.PState.EXITING]


## Pipeline: input -> fixed 60 Hz sim/prediction (above) -> capture the tick
## state here -> _process renders lerp(prev, cur, physics fraction) for every
## character, cart and the camera anchor.  Discontinuities (respawn,
## resurfacing, cart entry/exit, recovery, reconnect jumps) are not
## interpolated: prev = cur and the view's motion history is reset.
func _capture_tick() -> void:
	for slot in views:
		var rs := _player_rs(slot)
		if rs.is_empty() or not rs.has("pos"):
			continue
		var prev: Dictionary = _tick_cur.get(slot, {})
		var jump := false
		if prev.is_empty():
			jump = true
		else:
			var ps: int = prev.get("state", 0)
			var cs: int = rs.get("state", 0)
			if (prev["pos"] as Vector3).distance_to(rs["pos"]) > 2.5:
				jump = true
			elif ps != cs and (ps in _TELEPORT_STATES or cs in _TELEPORT_STATES):
				jump = true
		_tick_prev[slot] = rs if jump else prev
		_tick_cur[slot] = rs
		if jump and not prev.is_empty():
			_discont[slot] = true
	for i in cart_views.size():
		var crs := _cart_rs(i)
		if crs.is_empty():
			continue
		var cp: Dictionary = _cart_cur.get(i, {})
		var cjump := cp.is_empty() or (cp["pos"] as Vector3).distance_to(crs["pos"]) > 3.0
		_cart_prev[i] = crs if cjump else cp
		_cart_cur[i] = crs


## Render-time state for a player: interpolated between the last two ticks.
func _render_rs(slot: int, frac: float = -1.0) -> Dictionary:
	var cur: Dictionary = _tick_cur.get(slot, {})
	if cur.is_empty():
		return _player_rs(slot)
	var prev: Dictionary = _tick_prev.get(slot, cur)
	var f := clampf(Engine.get_physics_interpolation_fraction() if frac < 0.0 else frac, 0.0, 1.0)
	var out := cur.duplicate()
	out["pos"] = (prev["pos"] as Vector3).lerp(cur["pos"], f)
	out["yaw"] = lerp_angle(float(prev.get("yaw", 0.0)), float(cur.get("yaw", 0.0)), f)
	if prev.has("steer") and cur.has("steer"):
		out["steer"] = lerpf(float(prev["steer"]), float(cur["steer"]), f)
	return out


func _render_cart(i: int) -> Dictionary:
	var cur: Dictionary = _cart_cur.get(i, {})
	if cur.is_empty():
		return _cart_rs(i)
	var prev: Dictionary = _cart_prev.get(i, cur)
	var f := clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	var out := cur.duplicate()
	out["pos"] = (prev["pos"] as Vector3).lerp(cur["pos"], f)
	out["yaw"] = lerp_angle(float(prev["yaw"]), float(cur["yaw"]), f)
	out["speed"] = lerpf(float(prev.get("speed", 0.0)), float(cur.get("speed", 0.0)), f)
	return out


## Stamps the local runner has, counting the water just splashed (the event
## can arrive a tick before the snapshot that records it).
func _my_stamp_count(water: int) -> int:
	var m := int(_player_rs(local_slot).get("stamps", 0))
	var ti := targets.find(water)
	if ti >= 0:
		m |= 1 << ti
	var n := 0
	for i in targets.size():
		if m & (1 << i):
			n += 1
	return n


func _local_in_cart() -> bool:
	var rs := _player_rs(local_slot)
	var st: int = rs.get("state", TC.PState.ACTIVE)
	return st == TC.PState.IN_CART or st == TC.PState.ENTERING


func _build_local_cmd() -> InputCmd:
	var cmd := InputCmd.new()
	if spectator:
		return cmd
	if input_source.is_valid():
		cmd = input_source.call(self)
		cmd.seq = _next_seq
		_next_seq += 1
		cmd.quantize()
		return cmd
	if hud and hud.pause_panel and hud.pause_panel.visible:
		# the pause menu owns the controller: its A/Enter is "Resume", not a jump
		Controls.clear_edges()
		cmd.cam_yaw = camera.yaw if camera else 0.0
		cmd.seq = _next_seq
		_next_seq += 1
		cmd.quantize()
		return cmd
	var mv := Controls.get_move()
	var yaw := camera.yaw if camera else 0.0
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(cos(yaw), -sin(yaw))
	cmd.move = (right * mv.x + fwd * mv.y).limit_length(1.0)
	cmd.cam_yaw = yaw
	cmd.held = Controls.held_bits()
	cmd.pressed = Controls.consume_pressed()
	if _local_in_cart():
		cmd.steer = Controls.get_steer()
		cmd.drive = Controls.get_drive()
		cmd.move = Vector2.ZERO
	var em := Controls.consume_emote()
	if em >= 0:
		session.send_emote(em)
	cmd.seq = _next_seq
	_next_seq += 1
	cmd.quantize()
	return cmd


func _host_tick(cmd: InputCmd, delta: float) -> void:
	# hold the round until every player's match scene has loaded (load acks)
	if not session.loads_complete(delta):
		if hud:
			hud.set_waiting(session.loading_names())
		return
	if hud:
		hud.set_waiting([])
	var inputs := session.host_collect_inputs()
	if not spectator and roster.has(local_slot):
		inputs[local_slot] = cmd
	sim.step(inputs)
	session.host_after_step(delta)
	if (sim.phase == TC.Phase.RESULTS or sim.phase == TC.Phase.ENDED) and not _results_sent:
		_results_sent = true
		session.host_match_finished(sim.results)


func _client_tick(cmd: InputCmd, delta: float) -> void:
	_est_tick += delta * cfg.sim_hz
	if not spectator and pred != null:
		_pending.append(cmd)
		if _pending.size() > 120:
			_pending.pop_front()
		_sent_window.append(cmd)
		while _sent_window.size() > 6:
			_sent_window.pop_front()
		session.client_send_inputs(_sent_window)
		_predict_step(cmd, delta)
	# keep proxy carts where we render them (parked carts block runners)
	for i in cart_proxies.size():
		if i == pred_cart_id:
			cart_proxies[i].global_position = Vector3(0, -50, 0)
			continue
		var crs := _cart_rs(i)
		if crs.has("pos"):
			cart_proxies[i].global_transform = Transform3D(Basis(Vector3.UP, float(crs["yaw"])), crs["pos"])
	_smooth = _smooth.lerp(Vector3.ZERO, clampf(delta * 12.0, 0.0, 1.0))


func _controllable(st: int) -> bool:
	return st == TC.PState.ACTIVE or st == TC.PState.STUMBLE or st == TC.PState.EXITING


## Server tick at which an input sent now will be simulated (clock estimate).
func _arrival_tick() -> float:
	var rtt_s := session.rtt if session != null else 0.1
	return _est_tick + rtt_s * 0.5 * cfg.sim_hz + 1.0


func _round_start_estimate() -> float:
	var s := _last_snap
	if _client_phase >= TC.Phase.PLAYING:
		return float(s.get("round_start", 0))
	if _client_phase == TC.Phase.COUNTDOWN:
		return float(s.get("phase_tick", 0)) + cfg.ticks(cfg.start_countdown_s)
	if _client_phase == TC.Phase.REVEAL:
		return float(s.get("phase_tick", 0)) + cfg.ticks(cfg.role_reveal_s + cfg.start_countdown_s)
	return INF


## Host tick that will simulate input `seq`: inputs are consumed one per tick
## after the last acknowledged one (reported in each snapshot).
func _process_tick_of(seq: int) -> float:
	if not _last_snap.has("tick"):
		return _arrival_tick()
	return float(_last_snap["tick"]) + float(seq - _last_ack)


func _predict_step(cmd: InputCmd, dt: float) -> void:
	# predict exactly the inputs the host will simulate as PLAYING ("GO")
	var arrive := _process_tick_of(cmd.seq)
	var start_t := _round_start_estimate()
	if _client_phase > TC.Phase.PLAYING or not _last_snap.has("tick") or arrive < start_t:
		return
	if pred.state == TC.PState.WAITING:
		if arrive >= start_t + cfg.ticks(cfg.runner_head_start_s):
			pred.state = TC.PState.ACTIVE
			pred.state_t = 0.0
		else:
			return
	if pred.state == TC.PState.IN_CART and pred_cart != null:
		Motor.advance_timers(pred, cfg, dt)
		Motor.step_cart(pred_cart, cmd, cfg, dt, layout)
		pred.body.global_position = pred_cart.pos()
		pred.yaw = pred_cart.yaw
		pred.vel = pred_cart.forward() * pred_cart.speed
		return
	if not _controllable(pred.state):
		return
	Motor.advance_timers(pred, cfg, dt)
	if pred.state == TC.PState.EXITING:
		var frozen := cmd.duplicate_cmd()
		frozen.move = Vector2.ZERO
		frozen.pressed = 0
		Motor.step_foot(pred, frozen, cfg, dt)
	else:
		Motor.step_foot(pred, cmd, cfg, dt)


func _on_snapshot(s: Dictionary) -> void:
	var tick: int = s["tick"]
	if _last_snap.has("tick") and tick <= int(_last_snap["tick"]):
		return   # late or duplicate snapshot: never let it override newer state
	if _last_snap_tick >= 0:
		_snap_gap_avg = lerpf(_snap_gap_avg, float(tick - _last_snap_tick), 0.1)
	_last_snap_tick = tick
	_last_snap = s
	_client_phase = int(s["phase"])
	var rtt_s := session.rtt if session != null else 0.1
	var target := float(tick) + rtt_s * 0.5 * cfg.sim_hz
	if not _have_clock or absf(_est_tick - target) > 20.0:
		_est_tick = target
		_have_clock = true
	else:
		_est_tick += (target - _est_tick) * 0.06
	_interp_ticks = clampf(_snap_gap_avg * 2.0 + 1.0, 6.0, 14.0)
	for slot in s["players"]:
		var arr: Array = _bufs.get(int(slot), [])
		arr.append({"tick": tick, "e": s["players"][slot]})
		while arr.size() > 24:
			arr.pop_front()
		_bufs[int(slot)] = arr
		_seen_tick[int(slot)] = tick
	for i in (s["carts"] as Array).size():
		if i < _cart_bufs.size():
			var ca: Array = _cart_bufs[i]
			ca.append({"tick": tick, "e": s["carts"][i]})
			while ca.size() > 24:
				ca.pop_front()
	if s.has("me"):
		_me = s["me"]
		_reconcile(s)


func _reconcile(s: Dictionary) -> void:
	if pred == null or not _me.has("motor"):
		return
	var ack: int = s["ack"]
	_last_ack = ack
	while not _pending.is_empty() and (_pending[0] as InputCmd).seq <= ack:
		_pending.pop_front()
	var before := pred.pos()
	var m: Dictionary = _me["motor"]
	pred.apply_motor(m)
	if pred.on_floor:
		pred.body.apply_floor_snap()
	var server_state: int = m["state"]
	var cart_id: int = m["cart_id"]
	# local cart prediction while driving
	if cart_id >= 0 and _me.has("cart_motor"):
		if pred_cart == null or pred_cart_id != cart_id:
			_make_pred_cart(cart_id)
		pred_cart.apply_motor(_me["cart_motor"])
		pred_cart.occupant = local_slot
	elif pred_cart != null:
		pred_cart.body.queue_free()
		pred_cart = null
		pred_cart_id = -1
	var enabled := _controllable(server_state) or server_state == TC.PState.WAITING
	Motor.set_body_enabled(pred.body, enabled)
	if enabled or server_state == TC.PState.IN_CART:
		for c in _pending:
			_predict_step(c, cfg.dt())
	var after := pred.pos()
	var err := before.distance_to(after)
	stat_snapshots += 1
	# only count true mispredictions: skip legitimate teleports (respawn,
	# resurfacing, recovery, cart exits) where the server state just changed
	var transition := server_state != _prev_server_state
	_prev_server_state = server_state
	if enabled and stat_snapshots > 1 and not transition and err < 4.0:
		stat_corrections.append(err)
		Diag.net_sample(session.rtt, err)
		if err > 0.5:
			Diag.mark("correction")
		if err > 0.2 and stat_big.size() < 12:
			stat_big.append({"err": snappedf(err, 0.01), "tick": int(s["tick"]), "ack": ack, "phase": _client_phase, "pend_seqs": [(_pending[0] as InputCmd).seq if not _pending.is_empty() else -1, (_pending[-1] as InputCmd).seq if not _pending.is_empty() else -1], "state": server_state, "pending": _pending.size(), "srv_pos": m["pos"], "before": before, "after": after, "floor": m["on_floor"], "vel": m["vel"], "role": pred.role})
	if err < 3.0:
		_smooth += before - after
	else:
		_smooth = Vector3.ZERO


func _make_pred_cart(cart_id: int) -> void:
	if pred_cart != null:
		pred_cart.body.queue_free()
	pred_cart = SimCart.new()
	pred_cart.id = cart_id
	pred_cart.body = Motor.make_cart_body("PredCart")
	client_world.add_child(pred_cart.body)
	pred_cart_id = cart_id


# ---------------------------------------------------------------------------
# Render state providers
# ---------------------------------------------------------------------------
func _player_rs(slot: int) -> Dictionary:
	if not is_client:
		var p := sim.player(slot) if sim else null
		if p == null:
			return {}
		return {
			"pos": p.pos(), "yaw": p.yaw, "vel": p.vel, "state": p.state, "state_t": p.state_t,
			"on_floor": p.on_floor, "diving": p.diving, "sprinting": p.sprinting, "tag_phase": p.tag_phase,
			"protect": p.protect, "bump_protect": p.bump_protect, "spotted": p.spotted > 0.0,
			"cart_id": p.cart_id, "steer": sim.carts[p.cart_id].steer_s if p.cart_id >= 0 else 0.0,
			"emote": p.emote, "emote_t": p.emote_t, "stamps": p.stamps, "visible": true,
			"bot": p.is_bot or p.bot_takeover, "connected": p.connected, "impact": p.splash_impact,
		}
	if slot == local_slot and pred != null and _last_snap.has("players") and (_last_snap["players"] as Dictionary).has(slot):
		var srv: Dictionary = _last_snap["players"][slot]
		var rs: Dictionary = srv.duplicate()
		rs["pos"] = pred.pos() + _smooth
		rs["yaw"] = pred.yaw
		rs["vel"] = pred.vel
		rs["on_floor"] = pred.on_floor
		rs["diving"] = pred.diving
		rs["sprinting"] = pred.sprinting
		rs["state"] = pred.state if _controllable(int(srv["state"])) or int(srv["state"]) == TC.PState.IN_CART else int(srv["state"])
		if pred.state == TC.PState.IN_CART and pred_cart != null:
			rs["steer"] = pred_cart.steer_s
		rs["visible"] = true
		return rs
	return _interp_player(slot)


func _interp_player(slot: int) -> Dictionary:
	var arr: Array = _bufs.get(slot, [])
	if arr.is_empty():
		return {}
	var rt := _est_tick - _interp_ticks
	var newest: Dictionary = arr[arr.size() - 1]
	var vis := (int(_last_snap.get("tick", 0)) - int(_seen_tick.get(slot, -999))) < 18
	if rt >= float(newest["tick"]):
		var e: Dictionary = (newest["e"] as Dictionary).duplicate()
		var ex := clampf((rt - float(newest["tick"])) / cfg.sim_hz, 0.0, 0.1)
		e["pos"] = (e["pos"] as Vector3) + Vector3((e["vel"] as Vector3).x, 0, (e["vel"] as Vector3).z) * ex
		e["visible"] = vis
		return e
	for i in range(arr.size() - 1, 0, -1):
		var a: Dictionary = arr[i - 1]
		var b: Dictionary = arr[i]
		if float(a["tick"]) <= rt and rt <= float(b["tick"]):
			var span := maxf(1.0, float(b["tick"]) - float(a["tick"]))
			var t := (rt - float(a["tick"])) / span
			var ea: Dictionary = a["e"]
			var eb: Dictionary = b["e"]
			var out: Dictionary = (eb if t > 0.5 else ea).duplicate()
			if int(ea["state"]) == int(eb["state"]):
				out["state_t"] = lerpf(float(ea["state_t"]), float(eb["state_t"]), t)
			if (ea["pos"] as Vector3).distance_to(eb["pos"]) < 8.0:
				out["pos"] = (ea["pos"] as Vector3).lerp(eb["pos"], t)
				out["yaw"] = lerp_angle(float(ea["yaw"]), float(eb["yaw"]), t)
				out["vel"] = (ea["vel"] as Vector3).lerp(eb["vel"], t)
			else:
				out["pos"] = eb["pos"] if t > 0.5 else ea["pos"]
			out["visible"] = vis
			return out
	var oldest: Dictionary = (arr[0]["e"] as Dictionary).duplicate()
	oldest["visible"] = vis
	return oldest


func _cart_rs(i: int) -> Dictionary:
	if not is_client:
		var c: SimCart = sim.carts[i]
		return {"pos": c.pos(), "yaw": c.yaw, "speed": c.speed, "steer": c.steer_s, "occupied": c.occupant >= 0, "slowed": c.slowed_t > 0.0, "occupant": c.occupant}
	if i == pred_cart_id and pred_cart != null:
		return {"pos": pred_cart.pos() + _smooth, "yaw": pred_cart.yaw, "speed": pred_cart.speed, "steer": pred_cart.steer_s, "occupied": true, "slowed": pred_cart.slowed_t > 0.0, "occupant": local_slot}
	var arr: Array = _cart_bufs[i] if i < _cart_bufs.size() else []
	if arr.is_empty():
		return {}
	var rt := _est_tick - _interp_ticks
	for k in range(arr.size() - 1, 0, -1):
		var a: Dictionary = arr[k - 1]
		var b: Dictionary = arr[k]
		if float(a["tick"]) <= rt and rt <= float(b["tick"]):
			var t := (rt - float(a["tick"])) / maxf(1.0, float(b["tick"]) - float(a["tick"]))
			var ea: Dictionary = a["e"]
			var eb: Dictionary = b["e"]
			return {"pos": (ea["pos"] as Vector3).lerp(eb["pos"], t), "yaw": lerp_angle(float(ea["yaw"]), float(eb["yaw"]), t),
				"speed": lerpf(float(ea["speed"]), float(eb["speed"]), t), "steer": float(eb["steer"]),
				"occupied": int(eb["occupant"]) >= 0, "slowed": bool(eb["slowed"]), "occupant": int(eb["occupant"])}
	var last: Dictionary = arr[arr.size() - 1]["e"]
	return {"pos": last["pos"], "yaw": last["yaw"], "speed": last["speed"], "steer": last["steer"], "occupied": int(last["occupant"]) >= 0, "slowed": last["slowed"], "occupant": int(last["occupant"])}


## HUD-facing state for the local player (works for host and client).
func local_info() -> Dictionary:
	var info := {}
	var rs := _player_rs(local_slot if not spectator else spectate_slot)
	info["rs"] = rs
	info["phase"] = sim.phase if sim else _client_phase
	info["role"] = int(roster[local_slot]["role"]) if roster.has(local_slot) else TC.Role.SPECTATOR
	if sim:
		var p := sim.player(local_slot)
		info["time_left"] = sim.time_left()
		info["countdown"] = sim.countdown_left()
		info["release_left"] = sim.patrol_release_left()
		info["finished"] = sim.finished_count
		if p:
			info["sprint"] = p.sprint
			info["gadget"] = p.gadget
			info["gadget_cd"] = p.gadget_cd
			info["penalty"] = p.penalty
			info["turbo"] = p.turbo_t
			info["spotted"] = p.spotted
			info["stamps"] = p.stamps
			info["noises"] = sim.noises_for(p)
		info["markers"] = sim.splash_markers if (p != null and p.is_patrol()) else []
	else:
		var s := _last_snap
		var est := _est_tick
		var end_t := float(s.get("end_tick", 0))
		var rs_t := float(s.get("round_start", 0))
		var ph := _client_phase
		if ph == TC.Phase.PLAYING:
			info["time_left"] = maxf(0.0, (end_t - est) / cfg.sim_hz)
			info["release_left"] = maxf(0.0, cfg.runner_head_start_s - (est - rs_t) / cfg.sim_hz)
		else:
			info["time_left"] = cfg.match_duration_s if ph < TC.Phase.PLAYING else 0.0
			info["release_left"] = cfg.runner_head_start_s
		info["countdown"] = maxf(0.0, (_reveal_end_tick() - est) / cfg.sim_hz) if ph < TC.Phase.PLAYING else 0.0
		info["finished"] = int(s.get("finished", 0))
		info["sprint"] = pred.sprint if pred else float(_me.get("sprint", 1.0))
		info["gadget"] = int(_me.get("gadget", 0))
		info["gadget_cd"] = float(_me.get("gadget_cd", 0.0))
		info["penalty"] = float(_me.get("penalty", 0.0))
		info["turbo"] = float(_me.get("turbo_t", 0.0))
		info["spotted"] = float(_me.get("spotted", 0.0))
		info["stamps"] = int(rs.get("stamps", 0))
		info["noises"] = _me.get("noises", [])
		var marks: Array = []
		for m in _me.get("markers", []):
			marks.append({"water": m["water"], "t": m["t"]})
		info["markers"] = marks
	info["targets"] = targets
	return info


func _reveal_end_tick() -> float:
	var s := _last_snap
	var pt := float(s.get("phase_tick", 0))
	if _client_phase == TC.Phase.REVEAL:
		return pt + cfg.ticks(cfg.role_reveal_s + cfg.start_countdown_s)
	if _client_phase == TC.Phase.COUNTDOWN:
		return pt + cfg.ticks(cfg.start_countdown_s)
	return float(s.get("round_start", 0))


# ---------------------------------------------------------------------------
# Presentation
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not prepared:
		_process_prepare()
		return
	_shake_cd = maxf(0.0, _shake_cd - delta)
	# events -> effects/sounds/HUD
	var evs := _local_events
	_local_events = []
	for ev in evs:
		_present_event(ev)
	# characters
	for slot in views:
		var v: CharacterView = views[slot]
		var rs := _render_rs(slot)
		if rs.is_empty() or not bool(rs.get("visible", true)):
			v.visible = false
			continue
		v.visible = true
		var st: int = rs.get("state", 0)
		if st == TC.PState.IN_CART or st == TC.PState.ENTERING:
			var cid: int = rs.get("cart_id", -1)
			if cid >= 0:
				var crs := _render_cart(cid)
				if crs.has("pos"):
					var cy: float = crs["yaw"]
					var seat: Vector3 = (crs["pos"] as Vector3) + Basis(Vector3.UP, cy) * CartView.SEAT
					rs["pos"] = seat
					rs["yaw"] = cy
					rs["steer"] = crs.get("steer", 0.0)
		var snap := bool(_discont.get(slot, false))
		_discont.erase(slot)
		v.apply_state(rs, delta, snap)
		v.reduced_motion = reduced_motion
		if snap and slot == (spectate_slot if spectate_slot >= 0 else local_slot) and camera:
			camera.snap_to(rs["pos"], camera.yaw)
	for i in cart_views.size():
		var crs2 := _render_cart(i)
		if not crs2.is_empty():
			cart_views[i].apply_state(crs2, delta)
	_update_beacons(delta)
	_update_pickups()
	_update_camera(delta)
	if hud:
		hud.refresh(delta)
	var info_phase: int = sim.phase if sim else _client_phase
	if info_phase != _phase_seen:
		_phase_seen = info_phase
		if info_phase == TC.Phase.PLAYING:
			Sfx.play("go")
	var done_phase := info_phase == TC.Phase.RESULTS or info_phase == TC.Phase.ENDED
	var res: Dictionary = sim.results if sim else _client_results
	if done_phase and not res.is_empty() and not _finish_sent:
		_finish_sent = true
		Sfx.music("results")
		get_tree().create_timer(cfg.results_hold_s).timeout.connect(func() -> void: finished.emit(res))
	if info_phase < TC.Phase.PLAYING:
		var cd := int(ceil(float(local_info().get("countdown", 0.0))))
		if cd != _countdown_last and cd <= int(cfg.start_countdown_s) and cd > 0:
			Sfx.play("beep")
			if _countdown_last <= 0 or _countdown_last > int(cfg.start_countdown_s):
				Diag.mark("countdown")
		_countdown_last = cd


func _update_camera(delta: float) -> void:
	var follow_slot := local_slot
	var rs := _render_rs(local_slot) if not spectator else {}
	var st: int = rs.get("state", TC.PState.ACTIVE)
	var watching := spectator or st == TC.PState.FINISHED or (st == TC.PState.CAPTURED and float(rs.get("state_t", 0.0)) > 1.6)
	if watching:
		if spectate_slot < 0 or not _spectatable(spectate_slot):
			spectate_slot = _next_spectate(-1)
		if Input.is_action_just_pressed("spectate_next") or (touch and touch.consume_spectate()):
			spectate_slot = _next_spectate(spectate_slot)
		if spectate_slot >= 0:
			follow_slot = spectate_slot
			rs = _render_rs(spectate_slot)
	else:
		spectate_slot = -1
	var look := Controls.consume_look(delta)
	camera.add_look(look)
	camera.reduced_motion = reduced_motion
	camera.move_input = Controls.get_move() if follow_slot == local_slot else Vector2.ZERO
	if follow_slot != _cam_follow and rs.has("pos"):
		# spectator switch / own respawn view: cut, don't swing across the map
		if _cam_follow != -2:
			camera.snap_to(rs["pos"], camera.yaw)
		_cam_follow = follow_slot
	if rs.has("pos"):
		var cs: int = rs.get("state", 0)
		camera.in_cart = cs == TC.PState.IN_CART or cs == TC.PState.ENTERING
		var p: Vector3 = rs["pos"]
		if camera.in_cart:
			var crs := _render_cart(int(rs.get("cart_id", -1))) if int(rs.get("cart_id", -1)) >= 0 else {}
			if crs.has("pos"):
				p = crs["pos"]
				camera.target_vel = Basis(Vector3.UP, float(crs["yaw"])) * Vector3(0, 0, -float(crs["speed"]))
		else:
			camera.target_vel = rs.get("vel", Vector3.ZERO)
		if cs == TC.PState.SPLASHING:
			p.y = maxf(p.y, 0.0)
		camera.target_pos = p
		camera.target_yaw = rs.get("yaw", 0.0)
		if _foliage_mat:
			# canopies between the camera and the followed runner/cart are cut
			# away around them, so a tree never hides who you are playing
			_foliage_mat.set_shader_parameter("focus", Vector4(p.x, p.y + (1.1 if camera.in_cart else 0.85), p.z,
				2.0 if camera.in_cart else 1.25))
	elif _foliage_mat:
		_foliage_mat.set_shader_parameter("focus", Vector4.ZERO)
	camera.update_camera(delta)
	hud.set_spectating(follow_slot if follow_slot != local_slot else -1)


## Water under a point, for splash beats: {mat, center, color} or {}.
func _water_info(pos: Vector3) -> Dictionary:
	var wi := CampusBuilder.water_at(layout, Vector2(pos.x, pos.z))
	if wi < 0:
		return {}
	var wd: Dictionary = layout.waters[wi]
	if not water_nodes.has(wd["id"]):
		return {"color": wd["color"]}
	return {"mat": water_nodes[wd["id"]]["mat"], "center": wd["center"], "color": wd["color"]}


func _spectatable(slot: int) -> bool:
	if not roster.has(slot):
		return false
	var my_role: int = int(roster[local_slot]["role"]) if roster.has(local_slot) else TC.Role.RUNNER
	if int(roster[slot]["role"]) != my_role and not spectator:
		return false
	var rs := _player_rs(slot)
	return not rs.is_empty() and int(rs.get("state", 0)) != TC.PState.FINISHED and bool(rs.get("visible", true))


func _next_spectate(after: int) -> int:
	var slots := roster.keys()
	slots.sort()
	var start_i := slots.find(after) + 1
	for k in slots.size():
		var s: int = slots[(start_i + k) % slots.size()]
		if s != local_slot and _spectatable(s):
			return s
	return -1


func _haptic(ms: int) -> void:
	if bool(Save.get_setting("haptics", true)) and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms, 0.5)


func _present_event(ev: Dictionary) -> void:
	var type: int = ev["type"]
	var a: int = ev["a"]
	var pos: Vector3 = ev["pos"]
	var mine := a == local_slot
	match type:
		TC.Ev.SPLASH_STAMP, TC.Ev.SPLASH_NOSTAMP:
			# the spray, foam and ripples are beats of the runner's splash
			# sequence (CharacterView, driven by its time in the water); the
			# event carries the one sound and the HUD feedback
			var big := type == TC.Ev.SPLASH_STAMP
			Diag.mark("splash")
			var wcol: Color = layout.waters[int(ev["b"])]["color"] if int(ev["b"]) >= 0 else Color.CYAN
			Sfx.play("splash_big" if big else "splash", pos)
			if mine:
				if big:
					hud.stamp_pop(layout.waters[int(ev["b"])], _my_stamp_count(int(ev["b"])), targets.size())
					_haptic(20)
				else:
					var wi: int = ev["b"]
					hud.toast("Already stamped" if targets.has(wi) else "%s isn't a target tonight" % layout.waters[wi]["short"], Color(0.8, 0.9, 1.0))
			if big and not mine:
				var rr: Dictionary = roster.get(a, {})
				hud.feed_splash(String(rr.get("name", "?")), String(layout.waters[int(ev["b"])]["short"]), int(rr.get("role", 0)))
		TC.Ev.CAPTURE:
			Diag.mark("tag")
			fx.whistle_burst(pos)
			Sfx.play("whistle", pos)
			var r: Dictionary = roster.get(a, {})
			var by: Dictionary = roster.get(int(ev["b"]), {})
			hud.feed("%s caught %s!" % [by.get("name", "?"), r.get("name", "?")], TC.Role.PATROL)
			if mine:
				hud.toast("CAUGHT! Back in %d…" % int(cfg.capture_penalty_s), Color(1.0, 0.6, 0.4))
				_haptic(30)
			elif int(ev["b"]) == local_slot:
				hud.toast("Tagged %s!" % r.get("name", "?"), Color(1.0, 0.8, 0.3))
		TC.Ev.TAG_MISS:
			Diag.mark("tag_miss")
			Sfx.play("whoosh", pos)
			if views.has(a):
				(views[a] as CharacterView).tag_missed()
		TC.Ev.FINISH:
			fx.confetti(pos)
			Sfx.play("cheer", pos)
			var r2: Dictionary = roster.get(a, {})
			hud.feed("%s made it home! (%d/%d)" % [r2.get("name", "?"), int(ev["v"]), cfg.runners_needed], TC.Role.RUNNER)
			if mine:
				hud.toast("HOME SAFE! Cheer on your team", Color(0.5, 1.0, 0.6))
				_haptic(40)
		TC.Ev.BUMP:
			fx.bump(pos)
			Sfx.play("boing", pos)
			if mine and _shake_cd <= 0.0:
				_haptic(15)
				_shake_cd = 0.6
		TC.Ev.CART_ENTER:
			Sfx.play("cart_start", pos)
		TC.Ev.CART_EXIT:
			Sfx.play("hop", pos)
		TC.Ev.GADGET_PICKUP:
			Sfx.play("pickup", pos)
			if mine:
				hud.toast("Got %s!" % TC.GADGET_NAMES.get(int(ev["v"]), "a gadget"), Color(1.0, 0.9, 0.4))
		TC.Ev.GADGET_USE:
			var g: int = ev["v"]
			Sfx.play("squeak" if g == TC.Gadget.DECOY else ("turbo" if g == TC.Gadget.TURBO else "toss"), pos)
			if g == TC.Gadget.TURBO:
				fx.turbo(pos)
		TC.Ev.BOMB_HIT:
			fx.splash(pos, Color(0.4, 0.8, 1.0), int(ev["v"]) == 1)
			Sfx.play("splash", pos)
		TC.Ev.RESPAWN:
			fx.poof(pos)
		TC.Ev.RECOVER:
			fx.poof(pos)
			if mine:
				hud.toast("Back on campus", Color(0.8, 0.9, 1.0))
		TC.Ev.EMOTE:
			var who: Dictionary = roster.get(a, {})
			if not session.muted.has(String(who.get("uid", ""))):
				hud.emote_bubble(a, int(ev["v"]))
				Sfx.play("pop")
		TC.Ev.PLAYER_BOT_TAKEOVER:
			hud.feed("%s disconnected — a bot is covering (slot held 20s)" % roster.get(a, {}).get("name", "?"), -1)
		TC.Ev.PLAYER_RESUMED:
			hud.feed("%s reconnected" % roster.get(a, {}).get("name", "?"), -1)
		TC.Ev.PLAYER_LEFT:
			hud.feed("%s left — bot keeps their spot this round" % roster.get(a, {}).get("name", "?"), -1)


func _build_beacons() -> void:
	var glow := preload("res://assets/shaders/glow_add.gdshader")
	for wi in targets:
		var w: Dictionary = layout.waters[int(wi)]
		var c: Vector2 = w["center"]
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 1.6
		cm.bottom_radius = 2.4
		cm.height = 34.0
		cm.cap_top = false
		cm.cap_bottom = false
		cm.radial_segments = 16
		mi.mesh = cm
		var m := ShaderMaterial.new()
		m.shader = glow
		m.set_shader_parameter("color", w["color"])
		m.set_shader_parameter("intensity", 0.55)
		m.set_shader_parameter("mode", 1.0)
		m.set_shader_parameter("fade_near", 10.0)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(c.x, 17.0 + float(w["surface_y"]), c.y)
		add_child(mi)
		beacons[int(wi)] = mi
		if water_nodes.has(w["id"]):
			(water_nodes[w["id"]]["mat"] as ShaderMaterial).set_shader_parameter("active", 1.0)


func _update_beacons(_delta: float) -> void:
	var info_stamps := 0
	var rs := _player_rs(local_slot) if not spectator else {}
	info_stamps = int(rs.get("stamps", 0))
	for i in targets.size():
		var wi: int = targets[i]
		var done := (info_stamps & (1 << i)) != 0
		var mi: MeshInstance3D = beacons.get(wi)
		if mi:
			(mi.material_override as ShaderMaterial).set_shader_parameter("intensity", 0.18 if done else 0.55)
		var wid: String = layout.waters[wi]["id"]
		if water_nodes.has(wid):
			(water_nodes[wid]["mat"] as ShaderMaterial).set_shader_parameter("stamped", 1.0 if done else 0.0)


func _build_pickups() -> void:
	for spot in layout.gadget_spots:
		var n := Node3D.new()
		n.position = Vector3(spot.x, 0.9, spot.y)
		add_child(n)
		PropKit.init_meshes()
		var box := MeshInstance3D.new()
		box.mesh = PropKit.box
		box.scale = Vector3(0.6, 0.6, 0.6)
		box.material_override = PropKit.mat(Color(1.0, 0.85, 0.3), 0.0, Color.WHITE, 0.8)
		n.add_child(box)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.55
		tm.outer_radius = 0.7
		ring.mesh = tm
		ring.material_override = PropKit.mat(Color(1.0, 1.0, 1.0), 0.0, Color.WHITE, 1.2)
		ring.position = Vector3(0, -0.8, 0)
		n.add_child(ring)
		var lbl := Label3D.new()
		lbl.text = "?"
		lbl.font_size = 64
		lbl.pixel_size = 0.008
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.modulate = Color(0.3, 0.2, 0.1)
		lbl.position = Vector3(0, 0, 0)
		lbl.no_depth_test = false
		n.add_child(lbl)
		pickup_views.append(n)


func _update_pickups() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var mask := 0
	if sim:
		for i in sim.pickups.size():
			if float(sim.pickups[i]["respawn"]) <= 0.0:
				mask |= (1 << i)
	else:
		mask = int(_me.get("pickups", 0x1FF))
	var my_role: int = int(roster[local_slot]["role"]) if roster.has(local_slot) else TC.Role.RUNNER
	for i in pickup_views.size():
		var n := pickup_views[i]
		n.visible = (mask & (1 << i)) != 0
		n.rotation.y = t * 1.5 + float(i)
		n.position.y = 0.9 + sin(t * 2.0 + float(i)) * 0.12
		if my_role == TC.Role.PATROL:
			n.scale = Vector3(0.7, 0.7, 0.7)


func leave_match() -> void:
	quit_requested.emit()
