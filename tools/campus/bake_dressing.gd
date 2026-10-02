extends SceneTree
## Bakes CampusDressing's deterministic placement into
## game/assets/campus/campus_dressing.res (the game only loads it).
## Run through tools/campus/build.sh, or:
##   tools/gd.sh --headless --path game -s tools/campus/bake_dressing.gd


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var cd := CampusDressing.new(CampusLayout.shared())
	cd.verbose = true
	var d := cd.generate()
	var r := Resource.new()
	r.set_meta("items", d)
	var err := ResourceSaver.save(r, CampusDressing.BAKED, ResourceSaver.FLAG_COMPRESS)
	var parts := PackedStringArray()
	var keys := d.keys()
	keys.sort()
	for k in keys:
		parts.append("%s %d" % [k, (d[k] as PackedFloat32Array).size() / CampusDressing.STRIDE])
	print("dressing: %d items (%s) in %d ms -> %s (%s)" % [CampusDressing.count(d), ", ".join(parts), Time.get_ticks_msec() - t0, CampusDressing.BAKED, error_string(err)])
	quit(0 if err == OK else 1)
