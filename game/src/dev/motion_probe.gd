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


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scenarios="):
			names = Array(a.split("=")[1].split(","))
		elif a.begins_with("--out="):
			out = a.split("=")[1]
	if names.is_empty():
		names = MotionRig.SCENARIOS.keys()
	await get_tree().process_frame
	for n in names:
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


## The icon hero: nightcap (spring tip), striped pajamas, slippers.
func _look() -> Dictionary:
	var c := Cosmetics.DEFAULT.duplicate()
	for k in {"outfit": "pj", "pattern": "stripes", "color": "sky", "hat": "nightcap", "shoes": "slippers"}:
		c[k] = {"outfit": "pj", "pattern": "stripes", "color": "sky", "hat": "nightcap", "shoes": "slippers"}[k]
	return Cosmetics.sanitize(c)
