extends Node3D
## Development-only character test scene (src/dev is excluded from exports).
##   tools/gd.sh --path game res://src/dev/character_lineup.tscn -- --lineup=<mode> --capture-dir=DIR
## modes: views (front/3-4/side/back, runner + Night Watch), outfits, skins,
##        poses (one pose per clip), transitions (timed strip of state changes),
##        closeup (face), all (every mode in turn).
## Each mode saves a lossless PNG and quits when done.

const MODES := ["views", "outfits", "looks", "hairs", "posesheet", "transitions", "closeup", "faces", "cart", "hero", "group", "distance"]
const SHEET_CLIPS := ["idle", "walk", "run", "sprint", "turn_l", "air_rise", "air_apex", "air_fall", "land_soft", "land_hard",
	"dive", "dive_land", "splash_walk", "splash_jump", "splash_dive", "recover", "stumble", "flop", "dizzy", "tag_windup",
	"tag_lunge", "tag_recover", "tag_miss", "cart_enter", "cart_drive", "cart_steer_l", "cart_exit", "celebrate", "arrive", "ready",
	"fidget_yawn", "fidget_look", "emote_wave", "emote_cheer", "emote_laugh", "emote_shrug", "emote_dance", "emote_point"]
const SHEET_T := {"walk": 0.25, "run": 0.3, "sprint": 0.37, "turn_l": 0.2, "air_rise": 0.0, "air_apex": 0.0, "air_fall": 0.25,
	"land_soft": 0.1, "land_hard": 0.15, "dive": 0.6, "dive_land": 0.1, "splash_walk": 0.1, "splash_jump": 0.1, "splash_dive": 0.1,
	"recover": 0.25, "stumble": 0.27, "flop": 0.9, "dizzy": 0.4, "tag_windup": 0.14, "tag_lunge": 0.15, "tag_recover": 0.1,
	"tag_miss": 0.15, "cart_enter": 0.35, "cart_exit": 0.17, "celebrate": 0.25, "arrive": 0.33, "ready": 0.4, "fidget_yawn": 1.1,
	"fidget_look": 0.5, "emote_wave": 0.3, "emote_cheer": 0.2, "emote_laugh": 0.3, "emote_shrug": 0.4, "emote_dance": 0.2,
	"emote_point": 0.5}
## the icon's hero: blue striped pajamas, nightcap, bunny slippers
const HERO := {"outfit": "pj", "pattern": "stripes", "color": "sky", "hat": "nightcap", "shoes": "slippers", "skin": "tone2",
	"hair": "tuft", "hair_color": "brown", "face": "classic"}


static func look(over: Dictionary) -> Dictionary:
	var c := Cosmetics.DEFAULT.duplicate()
	for k in over:
		c[k] = over[k]
	return Cosmetics.sanitize(c)


var out_dir := ""
var modes: Array = []
var cam: Camera3D
var stage: Node3D
var _t := 0.0
var _mode := ""
var _views: Array[CharacterView] = []
var _strip_frames: Array[Image] = []
var _strip_next := 0.0
var _env: WorldEnvironment
var lighting := "studio"
var _sheet_i := -1
var _sheet_wait := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lineup="):
			var m := a.split("=")[1]
			modes = MODES.duplicate() if m == "all" else Array(m.split(","))
		elif a.begins_with("--capture-dir="):
			out_dir = a.split("=")[1]
		elif a.begins_with("--light="):
			lighting = a.split("=")[1]
	if modes.is_empty():
		modes = ["views"]
	if out_dir == "":
		out_dir = OS.get_user_data_dir().path_join("lineup")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_build_world()
	_next_mode()


func _build_world() -> void:
	_env = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("223049")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("8fa3c8")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	_env.environment = env
	add_child(_env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, 28, 0)
	key.light_energy = 1.25
	key.light_color = Color(1.0, 0.94, 0.86)
	key.shadow_enabled = true
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -140, 0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.6, 0.72, 1.0)
	add_child(fill)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("2b3a57")
	fm.roughness = 0.9
	floor_mi.material_override = fm
	add_child(floor_mi)
	cam = Camera3D.new()
	cam.fov = 30
	add_child(cam)
	cam.current = true
	stage = Node3D.new()
	add_child(stage)


func _clear() -> void:
	for v in _views:
		v.queue_free()
	_views.clear()


func _add(role: int, cos: Dictionary, x: float, z: float = 0.0, yaw: float = PI, label: String = "") -> CharacterView:
	var v := CharacterView.new()
	stage.add_child(v)
	v.setup(role, cos, -1, label, false, false)
	v.apply_state({"pos": Vector3(x, 0, z), "yaw": yaw, "state": TC.PState.ACTIVE, "vel": Vector3.ZERO, "on_floor": true}, 0.0, true)
	if v.name_label:
		v.name_label.visible = label != ""
		v.name_label.fixed_size = false
		v.name_label.pixel_size = 0.004
		v.name_label.position = Vector3(0, -0.25, 0.6)
		v.name_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		v.name_label.rotation.y = -yaw + PI
	_views.append(v)
	return v


func _aim(from: Vector3, at: Vector3, fov: float = 30.0) -> void:
	cam.fov = fov
	cam.look_at_from_position(from, at)


func _pose(v: CharacterView, clip: String, t: float) -> void:
	v.set_process(false)
	v.tree.active = false
	v.anim.play(clip)
	v.anim.seek(t, true)
	v.anim.pause()


func _next_mode() -> void:
	_clear()
	if modes.is_empty():
		get_tree().quit()
		return
	_mode = modes.pop_front()
	_t = 0.0
	var d := look(HERO)
	var colors: Array = Cosmetics.keys_of("color")
	var skins: Array = Cosmetics.keys_of("skin")
	match _mode:
		"views":
			var yaws := [0.0, PI * 0.25, PI * 0.5, PI]
			var names := ["front", "3/4", "side", "back"]
			for i in 4:
				# yaw PI faces +Z (toward the camera); add the view angle
				_add(TC.Role.RUNNER, d, -4.5 + i * 1.5, 0.0, PI + yaws[i], names[i])
			for i in 2:
				_add(TC.Role.PATROL, look({"color": "sky", "skin": "tone6"}), 1.8 + i * 1.5, 0.0, PI + (0.0 if i == 0 else PI), "watch " + ("front" if i == 0 else "back"))
			_aim(Vector3(-0.75, 1.4, 11.5), Vector3(-0.75, 0.85, 0), 30)
		"outfits":
			var outfits: Array = Cosmetics.keys_of("outfit")
			var hats := ["nightcap", "none", "swimcap", "party", "headphones", "crown"]
			var shoes := ["slippers", "sneakers", "flippers", "sneakers", "slippers", "sneakers"]
			var pats := ["stripes", "plain", "plain", "bands", "plain", "plain"]
			for i in outfits.size():
				_add(TC.Role.RUNNER, look({"outfit": outfits[i], "pattern": pats[i], "hat": hats[i], "shoes": shoes[i], "color": colors[i],
					"skin": skins[(i * 3) % skins.size()], "hair": ["tuft", "bob", "curly", "buns", "tuft"][i % 5]}), -4.5 + i * 1.5, 0.0, PI + 0.35, String(outfits[i]))
			_add(TC.Role.PATROL, look({"color": "bubblegum", "skin": "tone4"}), 4.5, 0.0, PI + 0.35, "night watch")
			_aim(Vector3(0, 1.5, 13.5), Vector3(0, 0.85, 0), 32)
		"looks", "skins":
			# hairstyles x hair colours, faces, brows, freckles, skin tones
			var hairs := ["tuft", "bob", "curly", "buns"]
			var hcols := ["black", "brown", "auburn", "ginger", "blonde", "silver", "blue", "pink"]
			var faces := ["classic", "bright", "sleepy", "classic", "bright", "sleepy", "classic", "bright"]
			var brows := ["arched", "arched", "flat", "raised", "flat", "arched", "raised", "arched"]
			for i in 8:
				_add(TC.Role.RUNNER, look({"outfit": "pj", "pattern": "plain", "hat": "none", "hair": hairs[i % 4], "hair_color": hcols[i],
					"face": faces[i], "brows": brows[i], "marks": "freckles" if i % 3 == 1 else "none", "color": colors[(i + 2) % colors.size()],
					"skin": skins[i]}), -3.5 + i * 1.0, 0.0, PI + 0.15, "%s/%s" % [hairs[i % 4], faces[i]])
			_aim(Vector3(0, 1.35, 8.6), Vector3(0, 1.0, 0), 30)
		"hairs":
			# each hairstyle from three-quarter front and three-quarter back (hairline check)
			var hs := ["tuft", "bob", "curly", "buns"]
			for i in 8:
				var hcol: String = ["brown", "auburn", "black", "blonde"][i % 4]
				_add(TC.Role.RUNNER, look({"hair": hs[i % 4], "hair_color": hcol, "hat": "none", "outfit": "pj", "pattern": "plain",
					"color": colors[i % 4], "skin": skins[(i * 2) % 8]}), -3.15 + i * 0.9, 0.0, PI + (0.6 if i < 4 else PI - 0.6), hs[i % 4])
			_aim(Vector3(0, 1.45, 6.2), Vector3(0, 1.15, 0), 34)
		"posesheet":
			var pv := _add(TC.Role.RUNNER, d, 0.0, 0.0, PI + 0.75, "")
			pv.set_process(false)
			_aim(Vector3(0, 1.1, 5.2), Vector3(0, 0.75, 0), 30)
			_strip_frames.clear()
			_sheet_i = -1
		"transitions":
			var v := _add(TC.Role.RUNNER, d, 0.0, 0.0, PI * 0.5, "")
			_aim(Vector3(0, 1.0, 6.5), Vector3(0, 0.8, 0), 30)
			_strip_frames.clear()
			_strip_next = 0.0
		"faces":
			var shapes := ["", "blink", "squint", "smile", "open", "brow_up", "brow_angry", "face_bright", "face_sleepy", "brow_flat"]
			for i in shapes.size():
				var v := _add(TC.Role.RUNNER, look({"outfit": "pj", "pattern": "plain", "hat": "none", "color": colors[i % colors.size()],
					"skin": skins[i % skins.size()], "hair": ["tuft", "bob", "curly", "buns"][i % 4]}), -3.15 + i * 0.7, 0.0, PI, shapes[i] if shapes[i] != "" else "neutral")
				v.set_process(false)
				v.tree.active = false
				v.anim.play("idle")
				v.anim.seek(0.0, true)
				v.anim.pause()
				for n in v._face_idx:
					v.base_mesh.set_blend_shape_value(v._face_idx[n], 0.0)
				if shapes[i] != "":
					v.base_mesh.set_blend_shape_value(v.base_mesh.find_blend_shape_by_name(shapes[i]), 1.0)
			_aim(Vector3(0, 1.25, 7.4), Vector3(0, 1.12, 0), 28)
		"cart":
			for i in 3:
				var steer := float(i - 1)
				var cv := CartView.new()
				stage.add_child(cv)
				cv.setup(i % 2)
				var cpos := Vector3(-3.2 + i * 3.2, 0, 0)
				var cyaw := PI + 0.7
				cv.apply_state({"pos": cpos, "yaw": cyaw, "speed": 0.0, "steer": steer, "occupied": true})
				var v := _add(TC.Role.PATROL, look({"color": colors[i], "skin": skins[i * 2]}), 0.0, 0.0, cyaw, "steer %+d" % int(steer))
				v.global_position = cpos + Basis(Vector3.UP, cyaw) * CartView.SEAT
				v.rotation.y = cyaw
				v.name_label.visible = false
				_pose(v, "cart_drive" if steer == 0.0 else ("cart_steer_r" if steer > 0.0 else "cart_steer_l"), 0.0)
			_aim(Vector3(0, 3.0, 8.5), Vector3(0, 1.0, 0), 36)
		"closeup":
			_add(TC.Role.RUNNER, d, -0.45, 0.0, PI + 0.35)
			_add(TC.Role.PATROL, look({"color": "sky", "skin": "tone7"}), 0.45, -0.3, PI - 0.3)
			_aim(Vector3(0, 1.3, 3.0), Vector3(0, 1.08, 0), 26)
		"hero":
			# the icon benchmark: front three-quarter head-and-shoulders, and full body
			_add(TC.Role.RUNNER, d, 0.0, 0.0, PI + 0.42)
			_aim(Vector3(0.05, 1.22, 2.05), Vector3(0.0, 1.1, 0), 30)
		"group":
			for i in 8:
				var c := Cosmetics.bot_cosmetic(i * 7 + 3)
				if i == 0:
					c = d
				_add(TC.Role.RUNNER if i < 6 else TC.Role.PATROL, c, -3.15 + i * 0.9, -0.35 * absf(i - 3.5), PI + (3.5 - i) * 0.06)
			_aim(Vector3(0, 1.6, 8.6), Vector3(0, 0.9, -0.5), 34)
		"distance":
			# typical follow-camera distance (about 6 m) and a far runner (20 m)
			_add(TC.Role.RUNNER, d, 0.0, 0.0, PI + 2.6)
			_add(TC.Role.RUNNER, look({"color": "bubblegum", "hair": "bob", "hat": "none"}), 3.0, -14.0, PI + 0.5)
			_add(TC.Role.PATROL, look({"color": "lime", "skin": "tone5"}), -4.0, -9.0, PI - 0.6)
			_aim(Vector3(0.6, 2.6, 5.8), Vector3(0, 0.9, -3.0), 62)


func _process(delta: float) -> void:
	_t += delta
	match _mode:
		"posesheet":
			if _t < 1.0:
				return
			if _sheet_wait > 0:
				_sheet_wait -= 1
				return
			if _sheet_i >= 0:
				_strip_frames.append(get_viewport().get_texture().get_image())
			_sheet_i += 1
			if _sheet_i >= SHEET_CLIPS.size():
				_save_strip("posesheet", 6, SHEET_CLIPS)
				_next_mode()
				return
			var clip: String = SHEET_CLIPS[_sheet_i]
			var pv := _views[0]
			var cs: Array = Cosmetics.keys_of("color")
			pv.set_appearance(TC.Role.PATROL if clip.begins_with("tag_") or clip.begins_with("cart") else TC.Role.RUNNER,
				look({"color": cs[_sheet_i % cs.size()], "skin": Cosmetics.keys_of("skin")[_sheet_i % 8]}))
			_pose(pv, clip, SHEET_T.get(clip, 0.3))
			_sheet_wait = 2
		"transitions":
			_drive_transitions(delta)
			if _t >= _strip_next and _t < 6.0:
				_strip_next += 0.4
				await RenderingServer.frame_post_draw
				_strip_frames.append(get_viewport().get_texture().get_image())
			if _t >= 6.2:
				_save_strip("transitions", 5, [])
				_next_mode()
		_:
			if _t > 1.5:
				await RenderingServer.frame_post_draw
				if _mode != "" and _t > 1.5:
					_save(_mode)
					_t = -999.0
					_next_mode()


## Scripted state changes: idle -> walk -> run -> sprint -> jump/fall -> land
## -> stop -> emote, driven through the same apply_state API as gameplay.
func _drive_transitions(_delta: float) -> void:
	if _views.is_empty():
		return
	var v := _views[0]
	var t := _t
	var speed := 0.0
	var vy := 0.0
	var floor_ok := true
	var emote := -1
	if t < 0.6:
		speed = 0.0
	elif t < 1.4:
		speed = 1.4
	elif t < 2.2:
		speed = 5.0
	elif t < 3.0:
		speed = 7.0
	elif t < 3.7:
		speed = 6.0
		floor_ok = false
		vy = 6.4 - 19.0 * (t - 3.0)
	elif t < 4.6:
		speed = maxf(0.0, 5.0 - (t - 3.7) * 8.0)
	else:
		emote = 1
	var x := 0.0
	v.apply_state({"pos": Vector3(0, maxf(0.0, (6.4 * (t - 3.0) - 9.5 * (t - 3.0) * (t - 3.0))) if not floor_ok else 0.0, 0),
		"yaw": PI * 0.5, "vel": Vector3(-speed, vy, 0), "state": TC.PState.ACTIVE, "on_floor": floor_ok,
		"sprinting": speed > 6.5, "emote": emote, "emote_t": 1.0 if emote >= 0 else 0.0})


func _save(n: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var p := out_dir.path_join("lineup_%s.png" % n)
	img.save_png(p)
	printerr("LINEUP %s %dx%d" % [p, img.get_width(), img.get_height()])


func _save_strip(n: String, cols: int, labels: Array) -> void:
	if _strip_frames.is_empty():
		return
	var w := _strip_frames[0].get_width()
	var h := _strip_frames[0].get_height()
	var cw := w / 4
	var ch := int(h * 0.8)
	var rows := int(ceil(_strip_frames.size() / float(cols)))
	var sheet := Image.create(cw * cols, ch * rows, false, Image.FORMAT_RGBA8)
	for i in _strip_frames.size():
		var f := _strip_frames[i]
		f.convert(Image.FORMAT_RGBA8)
		var crop := f.get_region(Rect2i(w / 2 - cw / 2, h / 2 - ch / 2, cw, ch))
		sheet.blit_rect(crop, Rect2i(0, 0, cw, ch), Vector2i((i % cols) * cw, (i / cols) * ch))
	var p := out_dir.path_join("lineup_%s.png" % n)
	sheet.save_png(p)
	if not labels.is_empty():
		var f2 := FileAccess.open(out_dir.path_join("lineup_%s.txt" % n), FileAccess.WRITE)
		f2.store_string("\n".join(PackedStringArray(labels)))
	printerr("LINEUP %s %dx%d frames=%d" % [p, sheet.get_width(), sheet.get_height(), _strip_frames.size()])
