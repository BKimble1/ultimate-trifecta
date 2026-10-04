extends Node
## Development-only: what a predicting client *shows* under network conditions
## (V5).  src/dev is excluded from exports.
##   tools/gd.sh --headless --fixed-fps 60 --path game res://src/dev/net_motion_probe.tscn -- [--out=file.json]
## A host and one predicting runner client over the in-process loopback hub
## (tests/net_rig.gd: real NetSession, protocol, prediction, reconciliation
## and interpolation; simulated latency, jitter and loss), 12 s of play per
## condition, the client's own MatchController presenting it.  Per rendered
## client frame it classifies discontinuities:
##   render stall      a frame longer than 40 ms (cannot happen on this fixed
##                     clock: listed so the classification is complete)
##   correction        the local character's drawn position moved more than
##                     8 cm away from where its own velocity took it within
##                     3 frames of a reconcile that moved it > 5 cm
##   terrain/collision the same deviation with no such reconcile (steps,
##                     kerbs, walls, landings)
##   camera collision  the camera moved > 8 cm relative to its pivot while
##                     its collision distance changed (pull-in / release)
##   camera jitter     the same without a distance change
##   remote snap       a remote character moved more than 15 cm away from its
##                     velocity path in one frame (interpolation gaps)
##   remote extrapolating  frames where the interpolation buffer ran dry
##   pose pop          an upper-body joint third difference > 6 cm on the
##                     local character or the nearest remote one
##   input loss        host ticks with no input from the client (starved)
## Headless numbers on a desktop: they classify, they do not measure phone
## smoothness.  No claim about live Game Center links follows from them.
##
## V8 adds, for the remote characters: the drawn time's backward steps,
## presentation underruns (drawn time past the newest snapshot), the
## displayed delay, the error against the host's own path at the drawn time
## (p50/p95), and the acceleration noise of the nearest remote character's
## drawn path (rms of its second difference: interpolation kinks show here).
## --interp=linear|hermite|both runs the V8 curve A/B (V8 builds only).

const CONDITIONS := [["lan", 0.0, 0.0, 0.0, 0.0, 0.0], ["rtt80_j8", 40.0, 8.0, 0.0, 0.0, 0.0],
	["rtt160_j25_loss3_dup5", 80.0, 25.0, 0.03, 0.05, 0.0], ["rtt250_j40_loss5_burst", 125.0, 40.0, 0.05, 0.0, 0.3],
	["rtt300_j30_loss10", 150.0, 30.0, 0.10, 0.0, 0.0]]
const UPPER := ["hips", "chest", "head", "hand.L", "hand.R", "forearm.L", "forearm.R"]

var out := ""
var interp := "both"
var results: Array = []
var _rec: Dictionary = {}       # view -> Array of PackedVector3Array


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.split("=")[1]
		elif a.begins_with("--interp="):
			interp = a.split("=")[1]
	await get_tree().process_frame
	var modes: Array = ["default"]
	var probe_mc := MatchController.new()
	if probe_mc.get("interp_hermite") != null:
		modes = ["hermite", "linear"] if interp == "both" else [interp]
	probe_mc.free()
	for c in CONDITIONS:
		for m in modes:
			var r: Dictionary = await _run(String(c[0]), float(c[1]), float(c[2]), float(c[3]), float(c[4]), float(c[5]), m)
			results.append(r)
			print("NETMOTION " + JSON.stringify(r))
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(JSON.stringify(results, "  "))
	get_tree().quit()


func _input_runner(_mc: MatchController) -> InputCmd:
	var c := InputCmd.new()
	var tk := Engine.get_physics_frames()
	c.move = [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)][(tk / 90) % 4]
	if tk % 70 == 0:
		c.pressed |= TC.BTN_JUMP
	if (tk / 45) % 3 == 0:
		c.held |= TC.BTN_SPRINT
	return c


func _hook(v: CharacterView) -> void:
	if v == null or _rec.has(v):
		return
	_rec[v] = []
	var last: SkeletonModifier3D = null
	for ch in v.skeleton.get_children():
		if ch is SkeletonModifier3D and (ch as SkeletonModifier3D).active:
			last = ch
	if last:
		last.modification_processed.connect(func() -> void:
			var p := PackedVector3Array()
			for b in UPPER:
				p.append(v.skeleton.get_bone_global_pose(v.skeleton.find_bone(b)).origin)
			(_rec[v] as Array).append(p))


func _pops(frames: Array) -> int:
	var n := 0
	for i in range(3, frames.size()):
		var a: PackedVector3Array = frames[i]
		var b: PackedVector3Array = frames[i - 1]
		var c: PackedVector3Array = frames[i - 2]
		var d: PackedVector3Array = frames[i - 3]
		for k in a.size():
			if (a[k] - 3.0 * b[k] + 3.0 * c[k] - d[k]).length() > 0.06:
				n += 1
				break
	return n


func _remote_time(cmc: MatchController) -> float:
	return cmc.remote_time() if cmc.has_method("remote_time") else cmc._est_tick - cmc._interp_ticks


static func _pct(a: Array, q: float) -> float:
	if a.is_empty():
		return -1.0
	var s := a.duplicate()
	s.sort()
	return float(s[mini(s.size() - 1, int(q * s.size()))])


func _run(label: String, lat: float, jit: float, loss: float, dup: float, burst: float, mode: String) -> Dictionary:
	var rig := NetRig.new()
	add_child(rig)
	rig.setup(lat, jit, loss, 1, ["patrol", "runner"])
	if rig.hub.get("duplicate") != null:
		rig.hub.duplicate = dup
		if burst > 0.0:
			rig.hub.burst_period_s = 4.0
			rig.hub.burst_s = burst
	elif dup > 0.0 or burst > 0.0:
		label += "(no dup/burst in this build)"
	var client: NetSession = rig.clients[0]
	rig.inputs[client] = _input_runner
	await rig.wait_until(func() -> bool: return client.local_slot >= 0, 300)
	client.set_local_ready(true)
	await rig.wait_until(func() -> bool: return rig.host.can_start(), 300)
	rig.host.host_start_match(4242)
	await rig.wait_until(func() -> bool: return rig.mcs.size() == 2, 300)
	var hmc := rig.host_mc()
	var cmc := rig.mc_of(client)
	if mode != "default":
		cmc.interp_hermite = mode == "hermite"
	await rig.wait_until(func() -> bool: return hmc.sim.phase == TC.Phase.PLAYING and cmc.prepared, 1200)
	await rig.frames(60)
	var back := 0
	var last_rt := -INF
	var errs: Array = []
	var delays: Array = []
	var underrun := 0
	var acc: Array = []
	var hist_near: Array = []
	_rec.clear()
	var me: CharacterView = cmc.views.get(client.local_slot)
	_hook(me)
	var st := {"frames": 0, "render_stall": 0, "correction": 0, "terrain": 0, "camera_jitter": 0, "camera_collision": 0,
		"remote_snap": 0, "remote_extrapolating": 0}
	var corr_seen := cmc.stat_corrections.size()
	var corr_recent := 0
	var prev_dist: float = cmc.camera._cur_dist
	var prev_me := me.global_position
	var prev_cam := cmc.camera.global_position
	var prev_piv := cmc.camera._pivot
	var prev_remote := {}
	var nearest: CharacterView = null
	var corr0 := cmc.stat_corrections.size()
	var starved0: int = int(rig.host.stat_starved.values().reduce(func(a, b): return a + b, 0)) if not rig.host.stat_starved.is_empty() else 0
	var t0 := Time.get_ticks_msec()
	for i in 60 * 12:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		st["frames"] += 1
		if dt > 0.04:
			st["render_stall"] += 1
		var rs := cmc._player_rs(client.local_slot)
		var vel: Vector3 = rs.get("vel", Vector3.ZERO)
		# a reconcile that moved the prediction more than 5 cm in the last 3 frames
		var nc := cmc.stat_corrections.size()
		for k in range(corr_seen, nc):
			if float(cmc.stat_corrections[k]) > 0.05:
				corr_recent = 3
		corr_seen = nc
		var exp_p := prev_me + vel * dt
		if me.global_position.distance_to(exp_p) > 0.08 and me.global_position.distance_to(prev_me) < 2.0:
			if corr_recent > 0:
				st["correction"] += 1
			else:
				st["terrain"] += 1     # steps, kerbs, walls, landings: not the network
		corr_recent = maxi(0, corr_recent - 1)
		prev_me = me.global_position
		var cam_move := cmc.camera.global_position - prev_cam
		var piv_move := cmc.camera._pivot - prev_piv
		if (cam_move - piv_move).length() > 0.08:
			if absf(cmc.camera._cur_dist - prev_dist) > 0.04:
				st["camera_collision"] += 1   # pull-in / release around geometry
			else:
				st["camera_jitter"] += 1
		prev_dist = cmc.camera._cur_dist
		prev_cam = cmc.camera.global_position
		prev_piv = cmc.camera._pivot
		var best := 1e9
		for slot in cmc.views:
			if slot == client.local_slot:
				continue
			var v: CharacterView = cmc.views[slot]
			if not v.visible:
				prev_remote.erase(slot)
				continue
			var d := v.global_position.distance_to(me.global_position)
			if d < best:
				best = d
				nearest = v
			var rr := cmc._interp_player(slot)
			var arr: Array = cmc._bufs.get(slot, [])
			if not arr.is_empty() and _remote_time(cmc) >= float(arr[arr.size() - 1]["tick"]):
				st["remote_extrapolating"] += 1
			# error against the host's path at the drawn time
			var rt := _remote_time(cmc)
			var hh: Dictionary = rig.host_positions.get(slot, {})
			var kk := int(floor(rt))
			if hh.has(kk) and hh.has(kk + 1) and int(rr.get("state", 0)) == TC.PState.ACTIVE:
				var truth: Vector3 = (hh[kk] as Vector3).lerp(hh[kk + 1], rt - kk)
				errs.append(Vector2(v.global_position.x - truth.x, v.global_position.z - truth.z).length())
			if prev_remote.has(slot):
				var rv: Vector3 = rr.get("vel", Vector3.ZERO)
				var e: Vector3 = (prev_remote[slot] as Vector3) + Vector3(rv.x, 0, rv.z) * dt
				var dev := Vector2(v.global_position.x - e.x, v.global_position.z - e.z).length()
				if dev > 0.15 and dev < 2.5:
					st["remote_snap"] += 1
			prev_remote[slot] = v.global_position
		if i == 30 and nearest:
			_hook(nearest)
		var rt_now := _remote_time(cmc)
		if rt_now < last_rt - 1e-6:
			back += 1
		last_rt = rt_now
		if _last_snap_tick(cmc) >= 0 and rt_now > float(_last_snap_tick(cmc)):
			underrun += 1
		delays.append((cmc._est_tick - rt_now) / 60.0 * 1000.0)
		# acceleration noise of the nearest remote character's drawn path
		if nearest:
			hist_near.append(nearest.global_position)
			if hist_near.size() >= 3:
				var n3 := hist_near.size()
				var a3: Vector3 = (hist_near[n3 - 1] - 2.0 * hist_near[n3 - 2] + hist_near[n3 - 3]) / (dt * dt)
				if a3.length() < 400.0:      # (a cut/teleport is not noise)
					acc.append(Vector2(a3.x, a3.z).length())
	var starved1: int = int(rig.host.stat_starved.values().reduce(func(a, b): return a + b, 0)) if not rig.host.stat_starved.is_empty() else 0
	var corr: Array = cmc.stat_corrections.slice(corr0)
	var big := corr.filter(func(e): return e > 0.25).size()
	var avg := 0.0
	for e in corr:
		avg += e
	avg /= maxf(1.0, corr.size())
	var pops := 0
	var pop_frames := 0
	for v in _rec:
		pops += _pops(_rec[v])
		pop_frames += (_rec[v] as Array).size()
	var rms := 0.0
	for x in acc:
		rms += float(x) * float(x)
	rms = sqrt(rms / maxf(1.0, acc.size()))
	var r := {"condition": label, "interp": mode, "rtt_ms": lat * 2.0, "jitter_ms": jit, "loss": loss, "dup": dup, "burst_s": burst,
		"client_frames": st["frames"],
		"remote_time_backward_frames": back, "presentation_underrun_frames": underrun,
		"displayed_delay_ms_p50": snappedf(_pct(delays, 0.5), 0.1), "displayed_delay_ms_p95": snappedf(_pct(delays, 0.95), 0.1),
		"remote_err_m_p50": snappedf(_pct(errs, 0.5), 0.001), "remote_err_m_p95": snappedf(_pct(errs, 0.95), 0.001),
		"remote_accel_rms": snappedf(rms, 0.01),
		"net_presentation": cmc.net_presentation() if cmc.has_method("net_presentation") else {},
		"render_stall_frames": st["render_stall"], "correction_frames": st["correction"], "terrain_frames": st["terrain"],
		"camera_jitter_frames": st["camera_jitter"], "camera_collision_frames": st["camera_collision"],
		"remote_snap_frames": st["remote_snap"], "remote_extrapolating_frames": st["remote_extrapolating"],
		"pose_pop_frames": pops, "pose_frames_checked": pop_frames,
		"reconciles": corr.size(), "corr_avg_m": snappedf(avg, 0.001), "corr_over_25cm": big,
		"host_starved_ticks": starved1 - starved0, "hub_dropped": rig.hub.dropped, "wall_ms": Time.get_ticks_msec() - t0}
	rig.teardown()
	await get_tree().process_frame
	return r


func _last_snap_tick(cmc: MatchController) -> int:
	return int(cmc._last_snap.get("tick", -1))
