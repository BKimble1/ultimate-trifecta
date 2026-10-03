extends Node
## Development-only (src/dev is excluded from exports): the motion rig's
## turn90 and reverse scenarios, recording both feet in world space every
## frame with and without the V6 foot lock, for docs/v6 foot-slide plots
## (tools/character/plot_foot_trail.py).
##   tools/gd.sh --headless --fixed-fps 60 --path game res://src/dev/foot_trail.tscn -- --out=FILE.json


func _ready() -> void:
	var out := OS.get_user_data_dir().path_join("foot_trail.json")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.split("=")[1]
	await get_tree().process_frame
	var res := {}
	for sc in ["turn90", "reverse"]:
		for lock in [false, true]:
			var rig := MotionRig.new()
			add_child(rig)
			rig.start(sc, Cosmetics.DEFAULT, 0.0)
			rig.view.foot_lock.active = lock
			await rig.finished
			var fr: Array = []
			for f in rig.frames:
				var feet: PackedVector3Array = f["feet"]
				fr.append({"t": f["t"], "dt": f["dt"], "mode": f["mode"], "l": [feet[0].x, feet[0].y, feet[0].z],
					"r": [feet[1].x, feet[1].y, feet[1].z], "root": [(f["root"] as Vector3).x, (f["root"] as Vector3).z]})
			res["%s_%s" % [sc, "lock" if lock else "nolock"]] = {"metrics": rig.metrics(), "frames": fr}
			rig.cleanup()
			rig.queue_free()
			await get_tree().process_frame
	var fa := FileAccess.open(out, FileAccess.WRITE)
	fa.store_string(JSON.stringify(res))
	print("TRAIL %s" % out)
	get_tree().quit()
