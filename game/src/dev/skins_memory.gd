extends Node3D
## Development-only (src/dev is excluded from exports): Pass 9 memory of the
## shared character asset and of eight players drawn together.
##   xvfb-run -a tools/gd.sh --path game res://src/dev/skins_memory.tscn -- --glb=res://X.glb [--out=FILE.json]
##   xvfb-run -a tools/gd.sh --path game res://src/dev/skins_memory.tscn -- --players=modular|skins [--out=FILE.json]
## Each run is one fresh process and reports Godot's static (CPU) memory and
## the renderer's buffer and video memory before and after:
##  * --glb=: loading a runner asset and instancing it once (every part is
##    uploaded once, as the game does).  Point it at a separate import of
##    the asset (a copy under another path), so it is not already loaded;
##    the before/after assets are measured the same way.
##  * --players=: eight CharacterViews of the game's own asset rendering 30
##    frames in view: "modular" is seven runners in heavy modular looks and
##    the Night Watch (looks that exist before and after Pass 9); "skins"
##    swaps two of the runners for Record Breaker and Dr. Doom.
## Desktop Mobile renderer on llvmpipe: Godot's own allocation counters, not
## a phone's resident memory; compare before/after on the same machine.

const MODULAR := [
	{"outfit": "robe", "hat": "beanie", "hair": "bob", "shoes": "slippers", "marks": "freckles"},
	{"outfit": "robe", "hat": "beanie", "hair": "bob", "shoes": "slippers", "marks": "freckles", "skin": "tone6"},
	{"outfit": "pj", "hat": "nightcap", "shoes": "slippers"},
	{"outfit": "swim", "hat": "swimcap", "shoes": "flippers"},
	{"outfit": "moonwalk_cadet", "hat": "none", "hair": "bob", "marks": "freckles"},
	{"outfit": "midnight_mechanic", "hat": "beanie", "hair": "bob", "marks": "freckles"},
	{"outfit": "raincoat_explorer", "hat": "nightcap", "hair": "curly"},
]

var glb := ""
var players := ""
var out := ""


func _mem() -> Dictionary:
	return {"static": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"video": int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),
		"buffers": int(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)),
		"textures": int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))}


func _delta(a: Dictionary, b: Dictionary) -> Dictionary:
	var d := {}
	for k in a:
		d[k] = int(b[k]) - int(a[k])
	return d


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--glb="):
			glb = a.get_slice("=", 1)
		elif a.begins_with("--players="):
			players = a.get_slice("=", 1)
		elif a.begins_with("--out="):
			out = a.get_slice("=", 1)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.look_at_from_position(Vector3(0, 1.6, 7.5), Vector3(0, 0.9, 0))
	var light := DirectionalLight3D.new()
	add_child(light)
	await _frames(10)
	var res := {"renderer": RenderingServer.get_video_adapter_name()}
	if glb != "":
		res["glb"] = glb
		res["asset_cached_at_start"] = ResourceLoader.has_cached(glb)
		var m0 := _mem()
		var scene: PackedScene = load(glb)
		var inst := scene.instantiate()
		add_child(inst)
		var verts := 0
		var shapes := 0
		var parts := 0
		for n in inst.find_children("*", "MeshInstance3D", true, false):
			var m: Mesh = (n as MeshInstance3D).mesh
			parts += 1
			for s in m.get_surface_count():
				verts += m.surface_get_array_len(s)
			if m is ArrayMesh:
				shapes += (m as ArrayMesh).get_blend_shape_count()
		await _frames(10)
		res["asset_loaded_and_instanced"] = _delta(m0, _mem())
		res["asset_parts"] = parts
		res["asset_vertices_all_parts"] = verts
		res["asset_blend_shapes"] = shapes
	elif players != "":
		var CV: GDScript = load("res://src/view/character_view.gd")
		var looks: Array = MODULAR.duplicate()
		if players == "skins":
			looks[2] = {"outfit": "record_breaker"}
			looks[3] = {"outfit": "dr_doom"}
		# one view first: the asset loads with it (not counted below)
		var first: Node3D = CV.new()
		add_child(first)
		first.setup(TC.Role.RUNNER, Cosmetics.sanitize({}), 0, "", false)
		await _frames(10)
		first.queue_free()
		await _frames(10)
		var m2 := _mem()
		var views: Array = []
		for i in 8:
			var v: Node3D = CV.new()
			add_child(v)
			var watch := i == 7
			v.setup(TC.Role.PATROL if watch else TC.Role.RUNNER, Cosmetics.sanitize(looks[mini(i, looks.size() - 1)]), i, "", false)
			v.position = Vector3(-3.5 + i, 0, 0)
			views.append(v)
		await _frames(30)
		res["players"] = players
		res["eight_players_added"] = _delta(m2, _mem())
		var tris := 0
		var draws: Array = []
		for v in views:
			draws.append(v.visible_parts.size())
			for mi in v.visible_parts:
				tris += int((mi as MeshInstance3D).mesh.get_faces().size() / 3)
		res["eight_players_lod0_tris"] = tris
		res["eight_players_draw_calls"] = draws
	res["note"] = "Godot allocation counters on the desktop Mobile renderer (llvmpipe under Xvfb); compare before/after on this machine only"
	var txt := JSON.stringify(res, "  ", false)
	print(txt)
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(txt)
	get_tree().quit()
