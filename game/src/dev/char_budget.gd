extends Node
## Development-only (src/dev is excluded from exports): the character's
## draw budget from the real asset and code.
##   tools/gd.sh --headless --path game res://src/dev/char_budget.tscn -- --out=FILE.json
##   xvfb-run tools/gd.sh --path game res://src/dev/char_budget.tscn -- --out=FILE.json --portraits
## Reports, for every runner look (outfit x hat x shoes x hair x marks, via
## Cosmetics.runner_parts) and the Night Watch: LOD0 triangles, draw calls
## (visible mesh parts, each one surface), the materials those parts use, and
## the heaviest look.  --portraits (needs a display) also times the shared
## Portraits renderer on a fixed set of looks: frames and wall time from
## request to picture.  On a desktop with software rendering (llvmpipe) the
## times compare before/after on the same machine; they are not phone numbers.

var out := ""
var portraits := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.split("=")[1]
		elif a == "--portraits":
			portraits = true
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/runner_manifest.json"))
	var meshes: Dictionary = m["meshes"]
	var tri := func(p: String) -> int: return int(meshes.get(p, {}).get("tris", 0))
	var res := {"art_version": m.get("art_version", "(none)")}
	# every runner look
	var worst := 0
	var worst_parts: Array = []
	var looks := 0
	var most_parts := 0
	for o in Cosmetics.keys_of("outfit"):
		for h in Cosmetics.keys_of("hat"):
			for sh in Cosmetics.keys_of("shoes"):
				for hair in Cosmetics.keys_of("hair"):
					for mk in Cosmetics.keys_of("marks"):
						var ps: Array = Cosmetics.runner_parts({"outfit": o, "hat": h, "shoes": sh, "hair": hair, "marks": mk})
						var n := 0
						for p in ps:
							n += tri.call(p)
						looks += 1
						most_parts = maxi(most_parts, ps.size())
						if n > worst:
							worst = n
							worst_parts = ps
	res["looks"] = looks
	res["heaviest_look_tris"] = worst
	res["heaviest_look_parts"] = worst_parts
	res["max_parts_per_runner"] = most_parts
	var typical: Array = Cosmetics.runner_parts(Cosmetics.DEFAULT)
	var tn := 0
	for p in typical:
		tn += tri.call(p)
	res["default_look_tris"] = tn
	res["default_look_parts"] = typical
	var swim: Array = Cosmetics.runner_parts({"outfit": "swim", "hat": "swimcap", "shoes": "flippers"})
	var sn := 0
	for p in swim:
		sn += tri.call(p)
	res["swim_goggles_look_tris"] = sn
	var watch := ["base", "watch", "flashlight", "mustache", "freckles"]
	var wn := 0
	for p in watch:
		wn += tri.call(p)
	res["night_watch_max_tris"] = wn
	# Pass 8: each rotating outfit's heaviest look (any hat, shoes, hair, marks)
	var p8 := {}
	for o in ["midnight_mechanic", "moonwalk_cadet", "pumpkin_pajamas", "arcade_sprinter", "cloud_nine", "bedtime_bandit"]:
		if not Cosmetics.CATALOG["outfit"].has(o):
			continue
		var ow := 0
		var owp: Array = []
		var omost := 0
		for h in Cosmetics.keys_of("hat"):
			for sh in Cosmetics.keys_of("shoes"):
				for hair in Cosmetics.keys_of("hair"):
					for mk in Cosmetics.keys_of("marks"):
						var ps2: Array = Cosmetics.runner_parts({"outfit": o, "hat": h, "shoes": sh, "hair": hair, "marks": mk})
						var n2 := 0
						for p in ps2:
							n2 += tri.call(p)
						omost = maxi(omost, ps2.size())
						if n2 > ow:
							ow = n2
							owp = ps2
		var hw: Array = Cosmetics.OUTFIT_HEADWEAR.get(o, {}).get("parts", [])
		p8[o] = {"outfit_part": Cosmetics.OUTFIT_PARTS[o][0], "outfit_part_tris": tri.call(Cosmetics.OUTFIT_PARTS[o][0]),
			"headwear_tris": tri.call(hw[0]) if not hw.is_empty() else 0, "heaviest_look_tris": ow, "heaviest_look_parts": owp,
			"max_parts_draw_calls": omost}
	res["pass8"] = p8
	# Pass 9: the complete skins (their own parts whatever hat, shoes, hair
	# and marks are saved: Cosmetics.COMPLETE_SKINS)
	var p9 := {}
	for o in Cosmetics.COMPLETE_SKINS:
		var ps3: Array = Cosmetics.runner_parts({"outfit": o})
		var n3 := 0
		var each := {}
		for p in ps3:
			n3 += tri.call(p)
			each[p] = tri.call(p)
		p9[o] = {"parts": ps3, "part_tris": each, "look_tris": n3, "draw_calls": ps3.size()}
	res["pass9"] = p9
	var glb := FileAccess.open("res://assets/characters/runner.glb", FileAccess.READ)
	res["glb_bytes"] = glb.get_length() if glb else 0
	var imp := ConfigFile.new()
	if imp.load("res://assets/characters/runner.glb.import") == OK:
		var ip := String(imp.get_value("remap", "path", ""))
		var f2 := FileAccess.open(ip, FileAccess.READ)
		res["imported_scene_bytes"] = f2.get_length() if f2 else 0
	var all_tris := 0
	for p in meshes:
		all_tris += tri.call(p)
	res["all_parts_tris"] = all_tris
	res["parts_in_asset"] = meshes.size()
	res["part_tris"] = {}
	for p in ["base", "hat_swimcap", "body_skin", "pj", "robe", "watch", "hair_bob", "hair_curly"]:
		res["part_tris"][p] = tri.call(p)
	# the real view: draw calls and materials of the heaviest look
	var v := CharacterView.new()
	add_child(v)
	v.setup(TC.Role.RUNNER, Cosmetics.DEFAULT, 0, "", false)
	var surfaces := 0
	var mats := {}
	for p in worst_parts:
		var mi: MeshInstance3D = v.parts.get(p)
		if mi:
			surfaces += mi.mesh.get_surface_count()
			mats[mi.material_override.get_instance_id()] = String(mi.material_override.shader.resource_path)
	res["heaviest_look_draw_calls"] = surfaces
	res["heaviest_look_materials"] = mats.values()
	var all_mats := {}
	for p in v.parts:
		all_mats[(v.parts[p] as MeshInstance3D).material_override.get_instance_id()] = true
	res["material_variants_in_asset"] = all_mats.size()
	v.queue_free()
	if portraits and DisplayServer.get_name() != "headless":
		res["portraits"] = await _time_portraits()
	var txt := JSON.stringify(res, "  ", false)
	print(txt)
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(txt)
	get_tree().quit()


## Twelve looks in each card framing, requested together as the Locker does;
## frames and milliseconds from request to picture.
func _time_portraits() -> Dictionary:
	await get_tree().process_frame
	var ps := Portraits.shared()
	await get_tree().process_frame
	var reqs: Array = []
	var outfits: Array = Cosmetics.keys_of("outfit")
	for i in 12:
		var app := Cosmetics.DEFAULT.duplicate()
		app["outfit"] = outfits[i % outfits.size()]
		app["hat"] = ["swimcap", "nightcap", "none", "headlamp"][i % 4]
		app["skin"] = Cosmetics.keys_of("skin")[i % 8]
		reqs.append([app, ["head", "body", "hat", "feet"][i % 4]])
	var t_req := {}
	var t_done := {}
	var f_req := {}
	var f_done := {}
	ps.portrait_ready.connect(func(k: String, _tex: Texture2D) -> void:
		t_done[k] = Time.get_ticks_usec()
		f_done[k] = Engine.get_process_frames())
	for r in reqs:
		var k := Portraits.key_for(r[0], TC.Role.RUNNER, r[1])
		t_req[k] = Time.get_ticks_usec()
		f_req[k] = Engine.get_process_frames()
		ps.portrait(r[0], TC.Role.RUNNER, "budget:%d" % t_req.size(), r[1])
	var guard := 0
	while t_done.size() < t_req.size() and guard < 6000:
		await get_tree().process_frame
		guard += 1
	var ms: Array = []
	var frames: Array = []
	var prev := -1
	var keys: Array = t_req.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(f_done.get(a, 0)) < int(f_done.get(b, 0)))
	for k in keys:
		if not t_done.has(k):
			continue
		var start: int = f_req[k] if prev < 0 else prev
		frames.append(int(f_done[k]) - start)
		prev = int(f_done[k])
	var first: int = t_req.values().min()
	var last: int = t_done.values().max() if not t_done.is_empty() else first
	return {"requested": t_req.size(), "rendered": t_done.size(), "renders": ps.renders,
		"frames_per_portrait": frames, "total_ms": (last - first) / 1000.0,
		"ms_per_portrait": (last - first) / 1000.0 / maxf(1.0, t_done.size()),
		"note": "desktop software rendering (llvmpipe) under Xvfb: relative numbers only"}
