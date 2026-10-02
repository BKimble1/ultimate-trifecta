extends Node
## Development-only motion measurement (src/dev is excluded from exports).
##   tools/gd.sh --headless --fixed-fps 60 --path game res://src/dev/motion_probe.tscn -- [--scenarios=a,b] [--out=file.json]
## Runs MotionRig scenarios (tests/motion_rig.gd) one after another, each from
## three starting gait phases (pops: worst; slide: mean over all), and prints
## one line per scenario: pose pops, planted-foot slide, head-spring lag and
## hat-tip motion.  The same file runs against the V4 code for the "before"
## column of docs/v5/motion_register.md.  Numbers come from fixed-clock engine
## frames on a desktop: they measure continuity, not phone frame rate.

var out := ""
var names: Array = []
var results: Array = []
## V6: --outfit=<key> runs the scenarios on that outfit (no hat, sneakers)
var outfit := ""


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--bench"):
		await _bench()
		get_tree().quit()
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scenarios="):
			names = Array(a.split("=")[1].split(","))
		elif a.begins_with("--out="):
			out = a.split("=")[1]
		elif a.begins_with("--outfit="):
			outfit = a.split("=")[1]
	if names.is_empty():
		names = MotionRig.SCENARIOS.keys() + CameraRig.SCENARIOS.keys()
	await get_tree().process_frame
	for n in names:
		if String(n).begins_with("cam_"):
			var cr := CameraRig.new()
			add_child(cr)
			await get_tree().physics_frame
			cr.start(String(n))
			await cr.finished
			var cm := cr.metrics()
			results.append(cm)
			print("PROBE %-16s camera jump %.3f m @%.2fs  closest %.2f m  pulled-in frames %d  pivot hidden frames %d / %d" % [
				n, cm["jump_m"], cm["jump_t"], cm["dist_min"], cm["pull_frames"], cm["blocked_frames"], cm["frames"]])
			cr.cleanup()
			cr.queue_free()
			await get_tree().process_frame
			continue
		# three starting gait phases; pops are the worst, slides the mean
		var mt := {}
		for ph in [0.0, 0.37, 0.71]:
			var rig := MotionRig.new()
			add_child(rig)
			rig.start(String(n), _look(), ph)
			await rig.finished
			var r := rig.metrics()
			if String(n) == "lod":
				r["lod_bands"] = rig.lod_bands()
			rig.cleanup()
			rig.queue_free()
			await get_tree().process_frame
			if mt.is_empty():
				mt = r
				continue
			for k in ["pop_cm", "leg_pop_cm", "step_cm", "lag_max", "lag_step", "hat_tip_step_cm", "hat_tip_range_cm", "slide_p95"]:
				if float(r[k]) > float(mt[k]):
					mt[k] = r[k]
					if k == "pop_cm":
						mt["pop_t"] = r["pop_t"]
						mt["pop_joint"] = r["pop_joint"]
			mt["pops_over_3cm"] = int(mt["pops_over_3cm"]) + int(r["pops_over_3cm"])
			var pf := int(mt["planted_frames"]) + int(r["planted_frames"])
			mt["slide_mean"] = snappedf((float(mt["slide_mean"]) * int(mt["planted_frames"]) + float(r["slide_mean"]) * int(r["planted_frames"])) / maxf(1.0, pf), 0.001)
			mt["planted_frames"] = pf
		results.append(mt)
		print("PROBE %-16s pop %6.2f cm @%.2fs %-10s >3cm %3d  legs %5.1f  slide %.3f/%.3f m/s (%d)  lag %.3f/%.4f  hat %.2f/%.2f cm%s" % [
			n, mt["pop_cm"], mt["pop_t"], mt["pop_joint"], mt["pops_over_3cm"], mt["leg_pop_cm"], mt["slide_mean"], mt["slide_p95"],
			mt["planted_frames"], mt["lag_max"], mt["lag_step"], mt["hat_tip_step_cm"], mt["hat_tip_range_cm"],
			("  " + JSON.stringify(mt["lod_bands"])) if mt.has("lod_bands") else ""])
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(JSON.stringify(results, "  "))
	get_tree().quit()


## --bench: 8 characters (4 running in circles, 4 idle) near the camera,
## 600 frames; prints the mean and 95th percentile of the whole frame's CPU
## time (desktop, headless).  Relative V4/V5 comparison only.
func _bench() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.position = Vector3(0, 3, 8)
	var vs: Array[CharacterView] = []
	for i in 8:
		var v := CharacterView.new()
		add_child(v)
		v.setup(TC.Role.RUNNER if i < 6 else TC.Role.PATROL, _look(), i, "b%d" % i, false, i == 0)
		v.apply_state({"pos": Vector3(i - 4, 0, 0), "yaw": 0.0, "vel": Vector3.ZERO, "state": TC.PState.ACTIVE, "on_floor": true}, 0.0, true)
		if OS.get_cmdline_user_args().has("--no-footlock") and v.foot_lock:
			v.foot_lock.active = false
		vs.append(v)
	var times: Array[float] = []
	CharacterFootLock.profile = true
	var last := Time.get_ticks_usec()
	for f in 660:
		var tt := f / 60.0
		for i in 8:
			var a := tt * 1.2 + i
			var run := i % 2 == 0
			var vel := Vector3(cos(a), 0, sin(a)) * (5.0 if run else 0.0)
			vs[i].apply_state({"pos": Vector3(i - 4, 0, 0) + (Vector3(sin(a), 0, -cos(a)) * 4.0 if run else Vector3.ZERO),
				"yaw": atan2(-vel.x, -vel.z) if run else 0.0, "vel": vel, "state": TC.PState.ACTIVE, "on_floor": true})
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		if f >= 60:
			times.append(float(now - last))
		last = now
	times.sort()
	var mean := 0.0
	for x in times:
		mean += x
	mean /= times.size()
	print("BENCH foot lock: %.1f us per character and frame (%d calls)" % [
		float(CharacterFootLock.profile_us) / maxf(1.0, CharacterFootLock.profile_calls), CharacterFootLock.profile_calls])
	print("BENCH 8 characters%s: frame CPU mean %.0f us, p95 %.0f us (desktop headless, relative only)" % [
		" (foot lock off)" if OS.get_cmdline_user_args().has("--no-footlock") else "", mean, times[int(times.size() * 0.95)]])


## The icon hero: nightcap (spring tip), striped pajamas, slippers (or, with
## --outfit, that outfit with no hat and sneakers).
func _look() -> Dictionary:
	if outfit != "":
		return Cosmetics.sanitize({"outfit": outfit, "hat": "none", "shoes": "sneakers"})
	var c := Cosmetics.DEFAULT.duplicate()
	for k in {"outfit": "pj", "pattern": "stripes", "color": "sky", "hat": "nightcap", "shoes": "slippers"}:
		c[k] = {"outfit": "pj", "pattern": "stripes", "color": "sky", "hat": "nightcap", "shoes": "slippers"}[k]
	return Cosmetics.sanitize(c)
