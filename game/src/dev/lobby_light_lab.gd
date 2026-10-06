extends Node
## Development-only lighting lab for the final lobby pass (src/dev: never
## exported).  Puts the dorm stage up with no UI (home framing with the
## player's runner, or the party framing with the eight looks of
## lobby_light_capture.gd), then renders it under named variants of the
## stage's light and environment settings and saves, per variant, the frame
## (<v>.png and <v>_3d.png), the room alone (<v>_room.png) and <v>.json in
## the capture driver's format, for tools/lobby_light_measure.py.
##   --lab-mode=home|lobby8
##   --lab=NAME:node.prop=value|node.prop=value;NAME2:...
##     nodes: key fill moon lamp lamp2 (lights), env (Environment); values
##     are GDScript literals (str_to_var), e.g. env.ambient_light_color=Color("7480a8")
## Desktop render (llvmpipe): relative comparisons only.

const Driver := preload("res://src/dev/lobby_light_capture.gd")

var out_dir := "/tmp"
var mode := "home"
var variants: Array = []   # [name, [[node, prop, value]...]]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture-dir="):
			out_dir = a.get_slice("=", 1)
		elif a.begins_with("--lab-mode="):
			mode = a.get_slice("=", 1)
		elif a.begins_with("--lab="):
			for spec in a.substr(6).split(";", false):
				var name := spec.get_slice(":", 0)
				var sets: Array = []
				if spec.contains(":"):
					for kv in spec.substr(spec.find(":") + 1).split("|", false):
						var lhs := kv.get_slice("=", 0)
						sets.append([lhs.get_slice(".", 0), lhs.get_slice(".", 1), str_to_var(kv.substr(kv.find("=") + 1))])
				variants.append([name, sets])
	if variants.is_empty():
		variants.append(["base", []])
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _nodes() -> Dictionary:
	var st := App.stage
	var d := {}
	var dirs: Array = []
	var omnis: Array = []
	for c in st.get_children():
		if c is DirectionalLight3D:
			dirs.append(c)
		elif c is OmniLight3D:
			omnis.append(c)
		elif c is WorldEnvironment:
			d["env"] = (c as WorldEnvironment).environment
	d["key"] = dirs[0]
	d["fill"] = dirs[1]
	d["moon"] = dirs[2]
	d["lamp"] = omnis[0]
	d["lamp2"] = omnis[1]
	return d


func _run() -> void:
	await _wait(0.3)
	Save.data["cosmetic"] = Cosmetics.sanitize(Cosmetics.DEFAULT.duplicate())
	App._ensure_background()
	App.sync_stage_local()
	var helper: Node = Driver.new()
	if mode == "lobby8":
		var entries: Array = [{"key": Save.player_uid(), "role": TC.Role.RUNNER, "cosmetic": Save.data["cosmetic"], "local": true, "arrive": false}]
		for i in Driver.GUESTS.size():
			var g: Array = Driver.GUESTS[i]
			entries.append({"key": "guest-%d" % i, "role": TC.Role.RUNNER, "cosmetic": helper._look(g[1]), "name": g[0], "arrive": false})
		App.stage.set_mode("lobby", false)
		App.stage.sync_party(entries)
	else:
		App.stage.set_mode("home", false)
	Driver.steady_poses()
	await _wait(3.0)
	var nodes := _nodes()
	for v in variants:
		var keep: Array = []
		for s in v[1]:
			var obj: Object = nodes[s[0]]
			keep.append([obj, s[1], obj.get(s[1])])
			obj.set(s[1], s[2])
		Driver.steady_poses()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var vp := get_viewport()
		var img := vp.get_texture().get_image()
		img.save_png(out_dir.path_join(String(v[0]) + ".png"))
		img.save_png(out_dir.path_join(String(v[0]) + "_3d.png"))
		var view := vp.get_visible_rect().size
		var rep := {"label": "desktop render, llvmpipe (lab)", "image": [img.get_width(), img.get_height()], "view": [view.x, view.y],
			"px_per_unit": float(img.get_width()) / maxf(1.0, view.x), "screen": "", "quality": int(Save.get_setting("quality", 1)),
			"refs": helper._refs(), "chars": helper._chars(), "texts": [], "variant": str(v[1])}
		for k in App.stage.chars:
			(App.stage.chars[k] as Node3D).visible = false
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png(out_dir.path_join(String(v[0]) + "_room.png"))
		for k in App.stage.chars:
			(App.stage.chars[k] as Node3D).visible = true
		var f := FileAccess.open(out_dir.path_join(String(v[0]) + ".json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(rep, "  ", false))
		f.close()
		printerr("LAB %s" % v[0])
		for k in keep:
			(k[0] as Object).set(k[1], k[2])
	helper.free()
	get_tree().quit()
