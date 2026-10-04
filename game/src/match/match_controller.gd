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
var _interp_ticks := 7.0     # displayed remote delay behind _est_tick (diagnostics; V8: derived)
var _snap_gap_avg := 3.0
var _last_snap_tick := -1
var _seen_tick: Dictionary = {}
# --- V8: remote jitter buffer.  Remote players and carts are drawn at a
# presentation time (server ticks) that advances smoothly and never goes
# backward: it follows a target = newest snapshot expected now (from the
# arrival times of recent snapshots, on the session's tick clock) minus a
# delay that covers the measured arrival spread and snapshot gaps.  The
# clock speeds up or slows down a little (JB_RATE_*) to follow the target;
# only a resync after a long gap (JB_RESYNC) jumps, and then cuts the
# remote poses.  The delay rises at once when the clock runs past the
# newest snapshot (an underrun) and relaxes slowly after a stable stretch.
# V4-V7 drew remote players at _est_tick - _interp_ticks, both corrected
# per snapshot (rt could step back) with a delay from tick gaps only.
# Local prediction does not use any of this.
const JB_WINDOW := 60          # snapshot arrivals remembered (~3 s at 20 Hz)
const JB_MIN := 4.0            # delay bounds (ticks)
const JB_MAX := 20.0
const JB_GAIN := 0.04          # rate change per tick of error
const JB_RATE_MIN := 0.86
const JB_RATE_MAX := 1.12
const JB_RESYNC := 30.0        # ticks of error that resync (cut) instead of slewing
const JB_STABLE_S := 6.0       # without an underrun before the delay relaxes
const JB_RELAX := 0.5          # ticks per second the delay relaxes by
const JB_UNDERRUN_STEP := 0.5  # ticks the delay rises per underrun tick
const EXTRAP_MAX_S := 0.1      # an underrun extrapolates at most this far, then holds
const RECOVER_TAU_S := 0.12    # back from an underrun: the held gap closes with this time constant
const RECOVER_MAX := 3.0       # m: a larger gap is a cut, not a blend
var _rec: Dictionary = {}      # slot -> {off, pt, held, at}: underrun recovery
var stat_recoveries := 0
const RESEEN_GAP := 18         # ticks absent from snapshots = out of interest
var interp_hermite := true     # V8 A/B: velocity-aware curves where safe
var _jb_off := PackedFloat64Array()   # tick - arrival tick, per snapshot
var _jb_gap := PackedFloat64Array()   # tick gaps between consecutive snapshots
var _jb_off_hi := 0.0
var _jb_floor := 7.0
var _jb_delay := 7.0
var _jb_stable_t := 0.0
var _pres_tick := 0.0
var _pres_ok := false
var _pres_rate := 1.0
var stat_underrun_ticks := 0
var stat_pres_resyncs := 0
var stat_pres_backward := 0    # must stay 0 (checked by tests)
var stat_extrap_clamped := 0
var _note_t := 0.0
var _beats: Array = []         # V8: remote cosmetic event beats waiting for the presentation time
var _beat_ids: Dictionary = {} # event id -> true (presented once)
var stat_beats_shown := 0

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
## capture contract presentation: who caught me (shown while captured) and
## my own catches this round (Night Watch confirmation)
var caught_by := ""
var my_catches := 0


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
		# (V6) names as this device shows them (a blocked player's is hidden);
		# the simulation keeps start["roster"] untouched
		roster[int(e["slot"])] = SocialSafety.display_entry(e)
	spectator = not roster.has(local_slot)
	home_dorm = String(start.get("home_dorm", CampusDorms.default_id()))
	if not CampusDorms.has_dorm(home_dorm):
		home_dorm = CampusDorms.default_id()


## V6: tonight's home dorm (from the round configuration).
var home_dorm := ""


## slot -> spawn index from the round configuration (keys arrive as strings).
func _spawn_map() -> Dictionary:
	var out := {}
	var dm: Dictionary = start.get("dorm", {})
	var sp: Dictionary = dm.get("spawns", {})
	for k in sp:
		out[int(k)] = int(sp[k])
	if out.is_empty():
		out = MatchSim.default_spawns(start["roster"])
	return out


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
	_prep = [_prep_campus, _prep_world, _prep_ground, _prep_nav, _prep_sim, _prep_views, _prep_rest, _prep_hud, _prep_touch, _prep_home_and_coins]
	_prep_i = 0
	if not staged:
		while _prep_i < _prep.size():
			_prep_run_one()
		_finish_prepare()


## V6: on a device that renders slowly anyway (a hot phone, a weak GPU,
## the CI Simulator at ~1 fps) a fixed 9 ms of work per frame made loading
## take as many frames as on a fast device, so many times longer.  When the
## frames are slow anyway, preparation may use up to half the measured
## frame interval (capped): the loop's cadence barely changes, the round is
## ready sooner.  At 60 fps the budget stays 9 ms.
const PREP_BUDGET_MAX_US := 40000
var _prep_last_us := 0
var _load_report_us := 0
var _prep_iv: Array[float] = []     # the last few frame intervals outside our own work


static func prep_budget_us(interval_us: float) -> int:
	return clampi(int(interval_us * 0.5), PREP_BUDGET_US, PREP_BUDGET_MAX_US)


func _process_prepare() -> void:
	var f0 := Time.get_ticks_usec()
	if _prep_last_us > 0:
		_prep_iv.append(float(f0 - _prep_last_us))
		if _prep_iv.size() > 4:
			_prep_iv.pop_front()
	# the least of the last four: one slow frame is not a slow device
	var budget := prep_budget_us(_prep_iv.min() if _prep_iv.size() >= 4 else 0.0)
	while _prep_i < _prep.size() and Time.get_ticks_usec() - f0 < budget:
		_prep_run_one()
	prep_frames += 1
	prep_max_ms = maxf(prep_max_ms, float(Time.get_ticks_usec() - f0) / 1000.0)
	_prep_last_us = Time.get_ticks_usec()
	# V6: a guest tells the host it is still on its way (twice a second)
	if is_client and _prep_last_us - _load_report_us > 500000:
		_load_report_us = _prep_last_us
		session.send_load_progress(prep_progress())
	if _prep_i >= _prep.size():
		_finish_prepare()


## How much of the round's preparation is done (0..1), from the steps
## actually completed: the campus build (its own step count, or nothing to
## do when the campus is kept from the last round), the shared data, the sim
## and each character.  The loading screen shows it.
func prep_progress() -> float:
	if prepared:
		return 1.0
	const W := [0.54, 0.08, 0.07, 0.06, 0.05, 0.16, 0.01, 0.01, 0.01, 0.01]   # campus, world, ground, nav, sim, views, carts+camera, hud, touch, home doors + coins
	var done := 0.0
	for k in mini(_prep_i, W.size()):
		done += W[k]
	if _prep_i < W.size():
		var part := 0.0
		if _prep_i == 0 and _builder != null:
			part = _builder.progress()
		elif _prep_i == 5 and not roster.is_empty():
			part = 1.0 - float(_view_queue.size()) / float(roster.size())
		elif _prep_i == 3 and NavGrid._building != null:
			part = float(NavGrid._building._phase) / float(NavGrid.PHASES.size())
		done += W[_prep_i] * clampf(part, 0.0, 1.0)
	return clampf(done, 0.0, 1.0)


## Per-job timings (V5): a budget checked *between* jobs can't stop one job
## from overrunning it, so every job is timed and the longest is kept; a job
## over PREP_SLOW_MS marks the diagnostics timeline with its name, so a
## stall on a phone is attributed to the job that caused it.
const PREP_SLOW_MS := 25.0
const PREP_NAMES := ["campus", "world", "ground", "nav", "sim", "views", "carts_camera", "hud", "touch", "home_coins"]
var prep_jobs: Array = []          # [[name, ms]] in order
var prep_longest := ["", 0.0]      # [name, ms]


func _prep_run_one() -> void:
	var i := _prep_i
	var nm := String(PREP_NAMES[i]) if i < PREP_NAMES.size() else "job%d" % i
	if i == 0 and _builder != null:
		nm = "campus:" + (String(_builder.call("next_step_name")) if _builder.has_method("next_step_name") else str(_builder.get("_step_i")))
	var t0 := Time.get_ticks_usec()
	var again: Variant = _prep[_prep_i].call()
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	prep_jobs.append([nm, ms])
	if ms > float(prep_longest[1]):
		prep_longest = [nm, ms]
	if ms > PREP_SLOW_MS:
		Diag.mark("prep_slow:" + nm)
	if not (again is bool and again):
		_prep_i += 1


func _stage(text: String) -> void:
	if stage_report.is_valid():
		stage_report.call(text)


func _prep_campus() -> bool:
	if not with_visuals:
		return false
	if _builder == null:
		_stage("Preparing campus…")
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


## V6: freed before it was prepared (Cancel / Leave on the loading screen,
## the party ended): nothing keeps running for a round that is gone.
func _exit_tree() -> void:
	stage_report = Callable()
	_set_view_held(false)     # menus draw 3D again
	NavGrid.settle_shared()   # V8: no bot path search left running on a worker
	if prepared:
		return
	Diag.mark("prep_cancelled")
	if _builder != null:
		App.adopt_worker_tasks(_builder.abort())
		_builder = null
	_prep_i = _prep.size()


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


## (V5) in slices, one per call, so the loading frame never holds the whole
## ~50 ms build
func _prep_nav() -> bool:
	if is_client:
		return false
	return NavGrid.build_step(layout)


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
			"gentle_bots": String(start.get("training", "")) == "watch",
			"patrol_release_extra_s": 24.0 if bool(start.get("tutorial", false)) else 0.0,
			"dorm": home_dorm, "spawns": _spawn_map(), "coins": start.get("coins", []),
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
	if int(e["role"]) == TC.Role.RUNNER:
		v.prewarm_fx()      # V8: drips exist before the first splash, not created on it
	v.terrain_contact = true
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
	if staged and with_visuals:
		_view_gating = true
		_set_view_held(true)
	add_child(camera)
	camera.current = true


# --- V6: nothing 3D is drawn behind the loading screen ---
# V5 made the round's camera current midway through preparation, so from
# then on the whole campus was drawn every frame behind the opaque loading
# screen, from a camera not yet placed (measured, a rendered practice round
# on this machine's software renderer: loading frames went from 9 draw calls
# and ~40 ms to 1,803 draw calls / 556k primitives and 3.4-17.7 s each), and
# online for as long as the round waited for other players: the loop
# animating and then freezing.  Now 3D drawing is held until the round is
# prepared; the camera is placed at the start view and a few frames are
# drawn to warm what the round shows first; then it is held again until the
# round goes live (the loading screen starts its fade the same frame).
const WARM_VIEW_FRAMES := 3
var _view_gating := false
var _view_held := false
var _warm_view_left := 0


func _set_view_held(held: bool) -> void:
	if held == _view_held:
		return
	_view_held = held
	var vp := get_viewport()
	if vp:
		vp.disable_3d = held
	Diag.mark("view_held" if held else "view_drawn")


## After the camera has been placed for this frame.
func _gate_view() -> void:
	if not _view_gating:
		return
	if _warm_view_left > 0:
		_warm_view_left -= 1
		_set_view_held(false)
	elif round_live():
		_view_gating = false
		_set_view_held(false)
	else:
		_set_view_held(true)


## The start view's first frames (the costly ones: first draws compile
## pipelines) have been drawn, still under the opaque loading screen, so
## the reveal's first visible frame is an ordinary one.  The loading screen
## waits for this as well as round_live().
func view_ready() -> bool:
	return prepared and (not _view_gating or _warm_view_left == 0)


## (V5) the HUD and the touch controls are separate jobs: together they were
## the longest non-campus step of a round's preparation.
func _prep_hud() -> void:
	hud = MatchHUD.new()
	add_child(hud)
	hud.setup(self)


func _prep_touch() -> void:
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


## V6: tonight's home-door markers and the round's coins (one MultiMesh,
## one shared material), warmed under the loading screen.
var coin_view: CoinView
var home_view: HomeDoorsView


func _prep_home_and_coins() -> void:
	if not with_visuals:
		return
	home_view = HomeDoorsView.new()
	home_view.name = "HomeDoors"
	add_child(home_view)
	home_view.setup(home_dorm)
	coin_view = CoinView.new()
	coin_view.name = "CoinView"
	add_child(coin_view)
	coin_view.setup(start.get("coins", []))
	coin_view.warm()


func _finish_prepare() -> void:
	if prepared:
		return
	prepared = true
	_warm_view_left = WARM_VIEW_FRAMES
	prepare_ms = float(Time.get_ticks_usec() - _prep_t0) / 1000.0
	Diag.mark("campus_prepared")
	if staged:
		print("[load] round prepared in %.0f ms over %d frames (longest frame of work %.1f ms; longest job %s %.1f ms)" % [prepare_ms, prep_frames, prep_max_ms, prep_longest[0], prep_longest[1]])
	if is_client:
		session.send_loaded()
	else:
		session.mark_local_loaded()
	Sfx.music("chase_calm")
	# V6: hold a steady pace on a phone that can't keep the preset (heat):
	# the 3D render scale steps down/up with hysteresis; freed with the match
	if with_visuals and DisplayServer.get_name() != "headless":
		var gov := QualityGovernor.new()
		gov.name = "QualityGovernor"
		add_child(gov)
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
		# the same spawn as MatchSim.setup: the round configuration's pad
		var sp := MatchSim.spawn_point(layout, home_dorm, pred.role, int(_spawn_map().get(local_slot, 0)))
		pred.body.global_position = sp[0]
		pred.yaw = sp[1]
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
	var tp := Prof.t()
	var cmd := _build_local_cmd()
	if is_client:
		_client_tick(cmd, delta)
	else:
		_host_tick(cmd, delta)
	_capture_tick()
	Prof.add("tick", tp)
	Prof.count("ticks")


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
	if prev.has("corr") and cur.has("corr"):
		out["corr"] = (prev["corr"] as Vector3).lerp(cur["corr"], f)
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
	if (hud and hud.blocks_gameplay_input()) or InputOwner.menu_owns():
		# the pause menu owns the controller: its A/Enter is "Resume", not a jump
		# (V6: so does the chat drawer: typing or a phrase never moves or tags)
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
	_advance_presentation(delta)
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
	_jb_arrival(tick, session.clock_s() * cfg.sim_hz if session != null else 0.0)
	var prev_tick := _last_snap_tick
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
	for slot in s["players"]:
		var seen := int(_seen_tick.get(int(slot), -1))
		if seen >= 0 and seen != prev_tick and tick - seen >= RESEEN_GAP:
			# back in this client's interest set after a gap: what the buffer
			# holds is from before it left; start again (a cut, not a slide).
			# Only if it was missing from snapshots that did arrive: lost or
			# late snapshots (a burst) drop every slot and are not a re-seen
			_bufs[int(slot)] = []
			_discont[int(slot)] = true
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
		rs["corr"] = _smooth      # V8: the presentation offset in pos (not travel)
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
	var rt := remote_time()
	var newest: Dictionary = arr[arr.size() - 1]
	var vis := (int(_last_snap.get("tick", 0)) - int(_seen_tick.get(slot, -999))) < RESEEN_GAP
	var out: Dictionary
	var held := rt > float(newest["tick"])
	if rt >= float(newest["tick"]):
		# underrun (or the newest sample exactly): a short, safe extrapolation
		out = _extrapolate_player(newest, rt)
	elif rt <= float(arr[0]["tick"]):
		# startup / just back in view: hold the oldest sample until time
		# reaches it (never show a newer state and then step back)
		out = (arr[0]["e"] as Dictionary).duplicate()
	else:
		out = {}
		for i in range(arr.size() - 1, 0, -1):
			var a: Dictionary = arr[i - 1]
			var b: Dictionary = arr[i]
			if float(a["tick"]) <= rt and rt <= float(b["tick"]):
				out = _blend_player(a, b, rt)
				break
		if out.is_empty():
			out = (newest["e"] as Dictionary).duplicate()
	out["visible"] = vis
	return _recover(slot, out, held)


## V8: back from an underrun (extrapolated, then held), a remote runner
## rejoins its real path over RECOVER_TAU_S of presentation time instead of
## jumping there in one frame.  Horizontal only (the height stays the real
## path's: no foot under a step).  Not across a cut: a re-seen slot, a
## resync, a state other than plain running, a gap of RECOVER_MAX or more.
func _recover(slot: int, out: Dictionary, held: bool) -> Dictionary:
	var r: Dictionary = _rec.get(slot, {})
	if not out.has("pos") or bool(_discont.get(slot, false)) or int(out.get("state", 0)) != TC.PState.ACTIVE:
		_rec.erase(slot)
		return out
	var pos: Vector3 = out["pos"]
	var off: Vector3 = r.get("off", Vector3.ZERO)
	if off != Vector3.ZERO:
		var dt := maxf(0.0, _pres_tick - float(r.get("pt", _pres_tick))) / cfg.sim_hz
		off *= exp(-dt / RECOVER_TAU_S)
		if off.length() < 0.005:
			off = Vector3.ZERO
	if not held and bool(r.get("held", false)):
		var at: Vector3 = r["at"]
		var gap := Vector3(at.x - pos.x, 0.0, at.z - pos.z)
		if gap.length() > 0.02 and gap.length() < RECOVER_MAX:
			off = gap
			stat_recoveries += 1
		else:
			off = Vector3.ZERO
	var drawn := pos + off
	out["pos"] = drawn
	_rec[slot] = {"off": off, "pt": _pres_tick, "held": held, "at": drawn}
	return out


func _blend_player(a: Dictionary, b: Dictionary, rt: float) -> Dictionary:
	var span := maxf(1.0, float(b["tick"]) - float(a["tick"]))
	var t := clampf((rt - float(a["tick"])) / span, 0.0, 1.0)
	var ea: Dictionary = a["e"]
	var eb: Dictionary = b["e"]
	var out: Dictionary = (eb if t > 0.5 else ea).duplicate()
	if int(ea["state"]) == int(eb["state"]):
		out["state_t"] = lerpf(float(ea["state_t"]), float(eb["state_t"]), t)
	var pa: Vector3 = ea["pos"]
	var pb: Vector3 = eb["pos"]
	if pa.distance_to(pb) < 8.0:
		var curve := interp_hermite and int(ea["state"]) == TC.PState.ACTIVE and int(eb["state"]) == TC.PState.ACTIVE
		out["pos"] = _curve_pos(pa, pb, ea["vel"], eb["vel"], span / cfg.sim_hz, t, curve,
			bool(ea.get("on_floor", true)) or bool(eb.get("on_floor", true)))
		out["yaw"] = lerp_angle(float(ea["yaw"]), float(eb["yaw"]), t)
		out["vel"] = (ea["vel"] as Vector3).lerp(eb["vel"], t)
	else:
		out["pos"] = pb if t > 0.5 else pa
	return out


## V8: position between two samples.  A cubic Hermite through both samples
## with their velocities (snapshots already carry them) where that is safe -
## continuous movement whose velocities agree with the displacement, no
## sharp reversal, a bend of under 25 cm - else the V7 straight line.  On
## the floor the height stays linear (a curve could dip under a step).
static func _curve_pos(pa: Vector3, pb: Vector3, va: Vector3, vb: Vector3, span_s: float, t: float, curve: bool, grounded: bool) -> Vector3:
	var lin := pa.lerp(pb, t)
	if not curve or span_s <= 0.0:
		return lin
	var d := pb - pa
	# the velocities must explain the displacement (a wall stop, a bump or a
	# state change does not)
	if (d - (va + vb) * 0.5 * span_s).length() > 0.35:
		return lin
	var ha := Vector2(va.x, va.z)
	var hb := Vector2(vb.x, vb.z)
	if ha.length() > 0.5 and hb.length() > 0.5 and ha.dot(hb) < 0.0:
		return lin
	var t2 := t * t
	var t3 := t2 * t
	var h00 := 2.0 * t3 - 3.0 * t2 + 1.0
	var h10 := t3 - 2.0 * t2 + t
	var h01 := -2.0 * t3 + 3.0 * t2
	var h11 := t3 - t2
	var c := pa * h00 + va * (span_s * h10) + pb * h01 + vb * (span_s * h11)
	# bounded bend: never more than 25 cm off the chord
	var mid := pa * 0.5 + pb * 0.5 + (va - vb) * (span_s * 0.125)
	if mid.distance_to(pa.lerp(pb, 0.5)) > 0.25:
		return lin
	if grounded:
		c.y = lin.y
	return c


## Underrun policy (players): extrapolate along the last horizontal velocity
## for at most EXTRAP_MAX_S, only in plain grounded running (no airborne
## arc, dive, tag action or other state is guessed), stopped short of a
## wall by a ray against this client's campus collision; then hold.
func _extrapolate_player(newest: Dictionary, rt: float) -> Dictionary:
	var e: Dictionary = (newest["e"] as Dictionary).duplicate()
	var ex := clampf((rt - float(newest["tick"])) / cfg.sim_hz, 0.0, EXTRAP_MAX_S)
	if ex <= 0.0:
		return e
	if int(e["state"]) != TC.PState.ACTIVE or not bool(e.get("on_floor", true)) or bool(e.get("diving", false)) \
			or int(e.get("tag_phase", 0)) != 0:
		return e
	var v: Vector3 = e["vel"]
	var p: Vector3 = e["pos"]
	e["pos"] = _clamp_motion(p, p + Vector3(v.x, 0.0, v.z) * ex, TC.L_WORLD, 0.35)
	return e


## The end of a straight move from `a` to `b` stopped `margin` short of the
## first static obstacle (a ray at knee height in this controller's world).
func _clamp_motion(a: Vector3, b: Vector3, mask: int, margin: float) -> Vector3:
	var d := b - a
	if d.length() < 0.01 or not is_inside_tree():
		return b
	var space := get_world_3d().direct_space_state
	var up := Vector3(0, 0.5, 0)
	var q := PhysicsRayQueryParameters3D.create(a + up, b + up + d.normalized() * margin, mask)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return b
	stat_extrap_clamped += 1
	var stop := maxf(0.0, a.distance_to((hit["position"] as Vector3) - up) - margin)
	return a + d.normalized() * minf(stop, d.length())


## The time remote players and carts are drawn at (server ticks).
func remote_time() -> float:
	return _pres_tick if _pres_ok else _est_tick - _interp_ticks


## Arrival statistics of the accepted snapshot `tick`, received at session
## tick time `arr_t`.
func _jb_arrival(tick: int, arr_t: float) -> void:
	_jb_off.append(float(tick) - arr_t)
	if _jb_off.size() > JB_WINDOW:
		_jb_off.remove_at(0)
	if _last_snap_tick >= 0:
		_jb_gap.append(float(tick - _last_snap_tick))
		if _jb_gap.size() > JB_WINDOW:
			_jb_gap.remove_at(0)
	var off := _jb_off.duplicate()
	off.sort()
	_jb_off_hi = off[off.size() - 1]
	var spread := _jb_off_hi - off[int(0.1 * float(off.size() - 1))]
	var gap_hi := float(cfg.snapshot_every_ticks)
	if not _jb_gap.is_empty():
		var g := _jb_gap.duplicate()
		g.sort()
		gap_hi = maxf(gap_hi, g[int(0.9 * float(g.size() - 1))])
	_jb_floor = clampf(gap_hi + spread + 1.0, JB_MIN, JB_MAX)
	if _jb_delay < _jb_floor:
		_jb_delay = _jb_floor       # more spread or gaps: more delay at once


## One physics tick of the presentation clock (clients).
func _advance_presentation(delta: float) -> void:
	if _jb_off.is_empty() or session == null:
		return
	var target := session.clock_s() * cfg.sim_hz + _jb_off_hi - _jb_delay
	if not _pres_ok or absf(target - _pres_tick) > JB_RESYNC:
		if _pres_ok:
			stat_pres_resyncs += 1
			Diag.mark("remote_resync")
			for slot in _bufs:
				if int(slot) != local_slot:
					_discont[int(slot)] = true
		_pres_tick = target
		_pres_ok = true
		_interp_ticks = _est_tick - _pres_tick
		return
	_pres_rate = clampf(1.0 + (target - _pres_tick) * JB_GAIN, JB_RATE_MIN, JB_RATE_MAX)
	var before := _pres_tick
	_pres_tick += delta * cfg.sim_hz * _pres_rate
	if _pres_tick < before:
		stat_pres_backward += 1
	if _last_snap_tick >= 0 and _pres_tick > float(_last_snap_tick):
		# ran past the newest snapshot: hold more from now on
		stat_underrun_ticks += 1
		_jb_stable_t = 0.0
		_jb_delay = minf(JB_MAX, _jb_delay + JB_UNDERRUN_STEP)
	else:
		_jb_stable_t += delta
		if _jb_stable_t > JB_STABLE_S and _jb_delay > _jb_floor:
			_jb_delay = maxf(_jb_floor, _jb_delay - JB_RELAX * delta)
	_interp_ticks = _est_tick - _pres_tick
	_note_t -= delta
	if _note_t <= 0.0:
		_note_t = 2.0
		var np := net_presentation()
		Diag.note("Remote presentation", "delay %.0f ms (target %.1f ticks), arrival spread %.0f ms, underrun ticks %d, resyncs %d" % [
			float(np["displayed_delay_ms"]), float(np["delay_ticks"]), float(np["arrival_spread_ms"]), int(np["underrun_ticks"]), int(np["resyncs"])])


## Network presentation numbers for diagnostics and tests.
func net_presentation() -> Dictionary:
	var spread := 0.0
	if not _jb_off.is_empty():
		var off := _jb_off.duplicate()
		off.sort()
		spread = off[off.size() - 1] - off[0]
	return {"delay_ticks": _jb_delay, "floor_ticks": _jb_floor, "displayed_delay_ms": _interp_ticks / cfg.sim_hz * 1000.0,
		"arrival_spread_ms": spread / cfg.sim_hz * 1000.0, "rate": _pres_rate, "underrun_ticks": stat_underrun_ticks,
		"resyncs": stat_pres_resyncs, "backward": stat_pres_backward, "extrap_clamped": stat_extrap_clamped,
		"recoveries": stat_recoveries}


func _cart_rs(i: int) -> Dictionary:
	if not is_client:
		var c: SimCart = sim.carts[i]
		return {"pos": c.pos(), "yaw": c.yaw, "speed": c.speed, "steer": c.steer_s, "occupied": c.occupant >= 0, "slowed": c.slowed_t > 0.0, "occupant": c.occupant}
	if i == pred_cart_id and pred_cart != null:
		return {"pos": pred_cart.pos() + _smooth, "yaw": pred_cart.yaw, "speed": pred_cart.speed, "steer": pred_cart.steer_s, "occupied": true, "slowed": pred_cart.slowed_t > 0.0, "occupant": local_slot,
			"corr": _smooth}
	var arr: Array = _cart_bufs[i] if i < _cart_bufs.size() else []
	if arr.is_empty():
		return {}
	var rt := remote_time()
	var newest: Dictionary = arr[arr.size() - 1]
	if rt >= float(newest["tick"]):
		# underrun: a short extrapolation along the cart's heading, stopped
		# short of walls and bollards, then hold
		var e: Dictionary = newest["e"]
		var out := _cart_out(e)
		var ex := clampf((rt - float(newest["tick"])) / cfg.sim_hz, 0.0, EXTRAP_MAX_S)
		if ex > 0.0 and absf(float(e["speed"])) > 0.2:
			var fw := Vector3(-sin(float(e["yaw"])), 0.0, -cos(float(e["yaw"])))
			out["pos"] = _clamp_motion(e["pos"], (e["pos"] as Vector3) + fw * float(e["speed"]) * ex, TC.L_WORLD | TC.L_CART_BLOCK, 1.0)
		return out
	if rt <= float(arr[0]["tick"]):
		# startup: hold the oldest (V4-V7 showed the newest here, then
		# stepped back once time reached the buffer)
		return _cart_out(arr[0]["e"])
	for k in range(arr.size() - 1, 0, -1):
		var a: Dictionary = arr[k - 1]
		var b: Dictionary = arr[k]
		if float(a["tick"]) <= rt and rt <= float(b["tick"]):
			var span := maxf(1.0, float(b["tick"]) - float(a["tick"]))
			var t := clampf((rt - float(a["tick"])) / span, 0.0, 1.0)
			var ea: Dictionary = a["e"]
			var eb: Dictionary = b["e"]
			var out := _cart_out(eb)
			var pa: Vector3 = ea["pos"]
			var pb: Vector3 = eb["pos"]
			if pa.distance_to(pb) < 8.0:
				var va := Vector3(-sin(float(ea["yaw"])), 0.0, -cos(float(ea["yaw"]))) * float(ea["speed"])
				var vb := Vector3(-sin(float(eb["yaw"])), 0.0, -cos(float(eb["yaw"]))) * float(eb["speed"])
				out["pos"] = _curve_pos(pa, pb, va, vb, span / cfg.sim_hz, t, interp_hermite, true)
			else:
				out["pos"] = pb if t > 0.5 else pa
			out["yaw"] = lerp_angle(float(ea["yaw"]), float(eb["yaw"]), t)
			out["speed"] = lerpf(float(ea["speed"]), float(eb["speed"]), t)
			return out
	return _cart_out(newest["e"])


static func _cart_out(e: Dictionary) -> Dictionary:
	return {"pos": e["pos"], "yaw": e["yaw"], "speed": e["speed"], "steer": e["steer"], "occupied": int(e["occupant"]) >= 0,
		"slowed": e["slowed"], "occupant": int(e["occupant"])}


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
			info["tag_ready"] = p.tag_ready
			info["tag_aim"] = p.tag_aim
			info["tag_busy"] = _tag_busy(p.tag_cd, p.tag_lockout)
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
		info["tag_ready"] = bool(_me.get("tag_ready", false))
		info["tag_aim"] = int(_me.get("tag_aim", -1))
		var mm: Dictionary = _me.get("motor", {})
		info["tag_busy"] = _tag_busy(float(mm.get("tag_cd", 0.0)), float(mm.get("tag_lockout", 0.0)))
	info["targets"] = targets
	# V6: tonight's home dorm and the coins this player has collected
	info["home_dorm"] = home_dorm
	if sim:
		var me := sim.player(local_slot)
		info["coins"] = me.coins_picked if me else 0
	else:
		info["coins"] = int(_me.get("coins_picked", 0))
	info["coins_total"] = (start.get("coins", []) as Array).size()
	return info


## Tag button cooldown ring, 0..1 of the miss cooldown (or cart-exit lockout).
func _tag_busy(cd: float, lockout: float) -> float:
	var c := maxf(cd / maxf(cfg.tag_miss_cooldown_s, 0.01), lockout / maxf(cfg.cart_exit_tag_lockout_s, 0.01))
	return clampf(c, 0.0, 1.0)


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
## V8: the one owner of a character view's visibility (the view no longer
## decides it from its own last state, which re-showed opponents this client
## stopped receiving as frozen ghosts): hidden with nothing to show, out of
## this client's interest set or not seen lately, or finished.
static func view_shown(rs: Dictionary) -> bool:
	return not rs.is_empty() and bool(rs.get("visible", true)) and int(rs.get("state", 0)) != TC.PState.FINISHED


func _process(delta: float) -> void:
	if not prepared:
		_process_prepare()
		return
	_shake_cd = maxf(0.0, _shake_cd - delta)
	# events -> effects/sounds/HUD
	var evs := _local_events
	_local_events = []
	var tp := Prof.t()
	for ev in evs:
		var wait := _beat_waits(ev)
		if wait:
			_beats.append({"ev": ev, "ms": Time.get_ticks_msec()})
		if Prof.on:
			var te := Prof.t()
			_present_event(ev, true, not wait)
			Prof.add("ev_" + str(TC.Ev.find_key(int(ev["type"]))), te)
		else:
			_present_event(ev, true, not wait)
	_present_due_beats()
	Prof.add("mc_events", tp)
	# characters
	tp = Prof.t()
	for slot in views:
		var v: CharacterView = views[slot]
		var rs := _render_rs(slot)
		if not view_shown(rs):
			if v.visible:
				v.hide_view()
			continue
		var reshown := not v.visible
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
		var snap := bool(_discont.get(slot, false)) or reshown
		_discont.erase(slot)
		v.apply_state(rs, delta, snap)
		v.reduced_motion = reduced_motion
		if snap and slot == (spectate_slot if spectate_slot >= 0 else local_slot) and camera:
			camera.snap_to(rs["pos"], camera.yaw)
	for i in cart_views.size():
		var crs2 := _render_cart(i)
		if not crs2.is_empty():
			cart_views[i].apply_state(crs2, delta)
	Prof.add("mc_apply", tp)
	tp = Prof.t()
	_update_beacons(delta)
	_update_aim_ring()
	_scan_seen(delta)
	_update_pickups()
	_update_home_and_coins()
	Prof.add("mc_world", tp)
	tp = Prof.t()
	_update_camera(delta)
	_gate_view()
	Prof.add("mc_camera", tp)
	tp = Prof.t()
	if hud:
		hud.refresh(delta)
	Prof.add("hud_refresh", tp)
	var info_phase: int = sim.phase if sim else _client_phase
	if info_phase != _phase_seen:
		_phase_seen = info_phase
		if info_phase == TC.Phase.PLAYING:
			Sfx.play("go")
	var done_phase := info_phase == TC.Phase.RESULTS or info_phase == TC.Phase.ENDED
	var res: Dictionary = sim.results if sim else _client_results
	if done_phase and not res.is_empty() and not _finish_sent:
		_finish_sent = true
		if hud:
			hud.round_over()   # V7: no menu or map left over the results
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
	if Diag.enabled and touch != null and follow_slot == local_slot:
		var r := touch.surface.router
		Diag.stick_tick(delta, r.stick_active(), r.stick_center - r.stick_origin, r.raw_vector(), Controls.touch_move,
			camera.yaw, look.x, camera.last_recenter, rs.get("vel", Vector3.ZERO), r.follows)


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


## V8: an event's presentation has two parts.  `ui`: the HUD, haptics and
## diagnostics - authoritative feedback, always shown when the event
## arrives.  `world`: the beat in the 3D scene (effects, positional sound,
## a coin vanishing, a remote tagger's miss) - on a client, for another
## player's event, it waits until the presentation time reaches the event's
## tick (_beats), so the splash or whistle meets that player where they are
## drawn instead of ~150-250 ms ahead of them.  Each event's world beat is
## shown once (keyed by event id).
const BEAT_HOLD_MS := 500      # a beat never waits longer than this
const _WORLD_BEATS := [TC.Ev.SPLASH_STAMP, TC.Ev.SPLASH_NOSTAMP, TC.Ev.CAPTURE, TC.Ev.TAG_MISS, TC.Ev.FINISH,
	TC.Ev.BUMP, TC.Ev.CART_ENTER, TC.Ev.CART_EXIT, TC.Ev.GADGET_PICKUP, TC.Ev.GADGET_USE, TC.Ev.BOMB_HIT,
	TC.Ev.RESPAWN, TC.Ev.RECOVER, TC.Ev.EMOTE, TC.Ev.COIN_PICKUP]


func _beat_waits(ev: Dictionary) -> bool:
	return is_client and _pres_ok and int(ev["a"]) != local_slot and ev.has("t") \
		and float(ev["t"]) > _pres_tick and int(ev["type"]) in _WORLD_BEATS


func _present_due_beats() -> void:
	if _beats.is_empty():
		return
	var now := Time.get_ticks_msec()
	var keep: Array = []
	for b in _beats:
		var ev: Dictionary = b["ev"]
		if float(ev["t"]) <= _pres_tick or now - int(b["ms"]) >= BEAT_HOLD_MS:
			_present_event(ev, false, true)
		else:
			keep.append(b)
	_beats = keep


func _present_event(ev: Dictionary, ui: bool = true, world: bool = true) -> void:
	var type: int = ev["type"]
	var a: int = ev["a"]
	var pos: Vector3 = ev["pos"]
	var mine := a == local_slot
	if world and int(ev.get("id", 0)) > 0:      # (id 0: local-only events, e.g. an emote echo)
		var id := int(ev["id"])
		if _beat_ids.has(id):
			world = false
		else:
			_beat_ids[id] = true
			if _beat_ids.size() > 256:
				_beat_ids.erase(_beat_ids.keys()[0])
	if world:
		stat_beats_shown += 1
	match type:
		TC.Ev.SPLASH_STAMP, TC.Ev.SPLASH_NOSTAMP:
			# the spray, foam and ripples are beats of the runner's splash
			# sequence (CharacterView, driven by its time in the water); the
			# event carries the one sound and the HUD feedback
			var big := type == TC.Ev.SPLASH_STAMP
			if world:
				Sfx.play("splash_big" if big else "splash", pos)
			if not ui:
				return
			Diag.mark("splash")
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
			if world:
				fx.whistle_burst(pos)
				Sfx.play("whistle", pos)
			if not ui:
				return
			Diag.mark("tag")
			var r: Dictionary = roster.get(a, {})
			var by: Dictionary = roster.get(int(ev["b"]), {})
			hud.feed("%s caught %s!" % [by.get("name", "?"), r.get("name", "?")], TC.Role.PATROL)
			if mine:
				caught_by = String(by.get("name", "the Night Watch"))
				_haptic(30)
			elif int(ev["b"]) == local_slot:
				# the tagger's confirmation, once, with their count this round
				my_catches += 1
				hud.toast("Tagged %s! · %d catch%s" % [r.get("name", "?"), my_catches, "" if my_catches == 1 else "es"], Color(1.0, 0.8, 0.3))
				_haptic(20)
		TC.Ev.TAG_MISS:
			if world:
				Sfx.play("whoosh", pos)
				if views.has(a):
					(views[a] as CharacterView).tag_missed()
			if ui:
				Diag.mark("tag_miss")
		TC.Ev.FINISH:
			if world:
				fx.confetti(pos)
				Sfx.play("cheer", pos)
			if not ui:
				return
			var r2: Dictionary = roster.get(a, {})
			hud.feed("%s made it home! (%d/%d)" % [r2.get("name", "?"), int(ev["v"]), cfg.runners_needed], TC.Role.RUNNER)
			if mine:
				# (the HOME SAFE overlay says it; no second toast)
				_haptic(40)
		TC.Ev.BUMP:
			if world:
				fx.bump(pos)
				Sfx.play("boing", pos)
			if ui and mine and _shake_cd <= 0.0:
				_haptic(15)
				_shake_cd = 0.6
		TC.Ev.CART_ENTER:
			if world:
				Sfx.play("cart_start", pos)
		TC.Ev.CART_EXIT:
			if world:
				Sfx.play("hop", pos)
		TC.Ev.GADGET_PICKUP:
			if world:
				Sfx.play("pickup", pos)
			if ui and mine:
				hud.toast("Got %s!" % TC.GADGET_NAMES.get(int(ev["v"]), "a gadget"), Color(1.0, 0.9, 0.4))
		TC.Ev.GADGET_USE:
			if world:
				var g: int = ev["v"]
				Sfx.play("squeak" if g == TC.Gadget.DECOY else ("turbo" if g == TC.Gadget.TURBO else "toss"), pos)
				if g == TC.Gadget.TURBO:
					fx.turbo(pos)
		TC.Ev.BOMB_HIT:
			if world:
				fx.splash(pos, Color(0.4, 0.8, 1.0), int(ev["v"]) == 1)
				Sfx.play("splash", pos)
		TC.Ev.RESPAWN:
			if world:
				fx.poof(pos)
		TC.Ev.RECOVER:
			if world:
				fx.poof(pos)
			if ui and mine:
				hud.toast("Back on campus", Color(0.8, 0.9, 1.0))
		TC.Ev.EMOTE:
			if world:
				var who: Dictionary = roster.get(a, {})
				if not SocialSafety.is_hidden(session, String(who.get("uid", "")), String(who.get("pid", ""))):   # (V6: blocked too)
					hud.emote_bubble(a, int(ev["v"]))
					Sfx.play("pop")
		TC.Ev.COIN_PICKUP:
			# the host decided who got it; a replayed or late event finds the
			# coin already gone and does nothing
			if world:
				var taken := coin_view.take(int(ev["v"])) if coin_view else true
				if taken:
					Sfx.play("pickup", pos, -5.0 if not mine else -2.0, 1.55)
			if ui and mine:
				if hud:
					hud.coin_pop()
				_haptic(12)
		TC.Ev.PLAYER_BOT_TAKEOVER:
			if ui:
				hud.feed("%s disconnected — a bot is covering (slot held 20s)" % roster.get(a, {}).get("name", "?"), -1)
		TC.Ev.PLAYER_RESUMED:
			if ui:
				hud.feed("%s reconnected" % roster.get(a, {}).get("name", "?"), -1)
		TC.Ev.PLAYER_LEFT:
			if ui:
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


## Opponents this player has actually seen - in view range and line of
## sight from their own head - and when.  The map shows them as "last seen"
## markers that fade and expire after LAST_SEEN_TTL_S; losing sight stops
## the tracking.  (Presentation only: see docs/V4_NOTES.md for what the
## network actually carries.)
const LAST_SEEN_TTL_S := 5.0
var last_seen: Dictionary = {}   # slot -> {"pos": Vector3, "ms": int, "live": bool}
var _seen_scan_t := 0.0


func _scan_seen(delta: float) -> void:
	_seen_scan_t -= delta
	if _seen_scan_t > 0.0:
		return
	_seen_scan_t = 0.2
	var now := Time.get_ticks_msec()
	for k in last_seen.keys():
		last_seen[k]["live"] = false
		if now - int(last_seen[k]["ms"]) > int(LAST_SEEN_TTL_S * 1000.0):
			last_seen.erase(k)
	if spectator or not roster.has(local_slot):
		return
	var my_role := int(roster[local_slot]["role"])
	var me := _player_rs(local_slot)
	if not me.has("pos"):
		return
	var eye: Vector3 = (me["pos"] as Vector3) + Vector3(0, 1.5, 0)
	var space := get_world_3d().direct_space_state
	for slot in roster:
		if int(roster[slot]["role"]) == my_role:
			continue
		var rs := _player_rs(int(slot))
		if not rs.has("pos"):
			continue
		var st := int(rs.get("state", 0))
		if st == TC.PState.FINISHED or st == TC.PState.CAPTURED or not bool(rs.get("visible", true)):
			continue
		var p: Vector3 = (rs["pos"] as Vector3) + Vector3(0, 1.0, 0)
		if eye.distance_to(p) > cfg.view_range_m:
			continue
		var q := PhysicsRayQueryParameters3D.create(eye, p, TC.L_WORLD)
		if space.intersect_ray(q).is_empty():
			last_seen[int(slot)] = {"pos": rs["pos"], "ms": now, "live": true}


var _aim_ring: MeshInstance3D
var _aim_mat: StandardMaterial3D


## Night Watch only: a ring under the runner the Tag assist would pick -
## soft while out of reach, bright amber when a press now would land.  Only
## this player sees it; it marks someone already in plain sight (the assist
## requires line of sight), so it reveals nothing hidden.
func _update_aim_ring() -> void:
	var info: Dictionary = hud.info if hud else {}
	var aim := int(info.get("tag_aim", -1))
	var show := aim >= 0 and views.has(aim) and int(info.get("role", -1)) == TC.Role.PATROL and not spectator
	if not show:
		if _aim_ring:
			_aim_ring.visible = false
		return
	if _aim_ring == null:
		var tm := TorusMesh.new()
		tm.inner_radius = 0.55
		tm.outer_radius = 0.68
		tm.rings = 32
		tm.ring_segments = 6
		_aim_mat = StandardMaterial3D.new()
		_aim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_aim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_aim_mat.no_depth_test = true
		_aim_ring = MeshInstance3D.new()
		_aim_ring.mesh = tm
		_aim_ring.material_override = _aim_mat
		_aim_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_aim_ring)
	var v: CharacterView = views[aim]
	_aim_ring.visible = true
	_aim_ring.global_position = v.global_position + Vector3(0, 0.06, 0)
	var ready := bool(info.get("tag_ready", false))
	var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) / 1000.0 * TAU * 1.6) if ready and not reduced_motion else 1.0
	_aim_mat.albedo_color = Color(UIKit.AMBER, 0.65 + 0.3 * pulse) if ready else Color(UIKit.IVORY, 0.35)
	_aim_ring.scale = Vector3.ONE * (1.0 + (0.06 * pulse if ready else 0.0))


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


## Coins still out (the host's state: snapshots on a guest) and how bright
## tonight's home doors are for this player.
func _update_home_and_coins() -> void:
	if coin_view:
		coin_view.set_mask(sim.coin_mask() if sim else int(_last_snap.get("coins", 0xFFFF)))
	if home_view:
		var rs := _player_rs(local_slot) if not spectator else {}
		var role: int = int(roster[local_slot]["role"]) if roster.has(local_slot) else TC.Role.SPECTATOR
		var st := 0
		if role == TC.Role.PATROL:
			st = 1
		elif role == TC.Role.RUNNER and int(rs.get("stamps", 0)) == 7 and int(rs.get("state", 0)) != TC.PState.FINISHED:
			st = 2
		home_view.set_state(st, reduced_motion)


func leave_match() -> void:
	quit_requested.emit()
