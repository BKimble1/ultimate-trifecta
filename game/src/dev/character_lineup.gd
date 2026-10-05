extends Node3D
## Development-only character test scene (src/dev is excluded from exports).
##   tools/gd.sh --path game res://src/dev/character_lineup.tscn -- --lineup=<mode> --capture-dir=DIR
## modes: views (front/3-4/side/back, runner + Night Watch), outfits, skins,
##        poses (one pose per clip), transitions (timed strip of state changes),
##        closeup (face), all (every mode in turn).
## V5: hathair (every hat that keeps hair visible x every hair style, close,
##        the wardrobe's clipping risk), menuidle (a menu-idle character under
##        indoor light, one frame every 1.2 s for 24 s), steps (start, stop and
##        a reversal from the side, one frame every 0.1 s).
## V6: skintones (all eight skin tones, head and shoulders), and
##        --light=dorm (the real dorm room and its lights, as on home, the
##        wardrobe and the lobby) besides studio and campus (the game's night).
## Each mode saves a lossless PNG and quits when done.

const MODES := ["views", "outfits", "looks", "hairs", "posesheet", "transitions", "closeup", "faces", "cart", "hero", "group", "distance", "parts",
	"hathair", "menuidle", "steps", "skintones", "shop", "season", "outfitsheet", "newhats", "newshoes", "hatgrid", "emotes", "custom", "reel",
	"pass8", "pass8back"]
## V7 "reel": gameplay scenarios from the motion tests (tests/motion_rig.gd:
## the 60 Hz mini-motor -> apply_state path) back to back on one look, the
## camera circling the head; frames every 0.25 s go into lineup_reel.png and
## --write-movie records the whole run.  --reel-look=JSON overrides the look.
const REEL := ["start", "turn90", "jump_run", "splash", "emote"]
const REEL_LOOK := {"outfit": "swim", "hat": "swimcap", "shoes": "flippers", "pattern": "plain", "skin": "tone5", "color": "sky"}
## V6 Shop and Season 1 content (modes skip keys the catalog does not have,
## so the same file renders the V5 asset for "before" pictures)
const V6_OUTFITS := ["moonlight_runner", "starry_sleeper", "varsity_sprinter", "raincoat_explorer", "campus_courier", "lantern_scout",
	"after_hours_hoodie", "night_owl", "glow_jogger", "library_cardigan"]
const V6_HATS := ["headlamp", "pompom_beanie", "glow_headband", "owl_ears"]
const V6_SHOES := ["glow_sneakers", "moon_boots"]
const V6_EMOTES := ["stargaze", "victory_lap", "shush", "moon_shuffle"]
## how each new outfit is shown in the Shop pictures (shoes, hair, skin, colour)
const SHOWCASE := {
	"moonlight_runner": {"shoes": "sneakers", "hair": "tuft", "hair_color": "dark_brown", "skin": "tone5", "color": "navy"},
	"starry_sleeper": {"shoes": "slippers", "hair": "bob", "hair_color": "black", "skin": "tone3", "color": "grape"},
	"varsity_sprinter": {"shoes": "sneakers", "hair": "curly", "hair_color": "black", "skin": "tone7", "color": "coral"},
	"raincoat_explorer": {"shoes": "sneakers", "hair": "buns", "hair_color": "ginger", "skin": "tone2", "color": "sunny"},
	"campus_courier": {"shoes": "sneakers", "hair": "tuft", "hair_color": "brown", "skin": "tone6", "color": "sunny"},
	"lantern_scout": {"shoes": "sneakers", "hair": "bob", "hair_color": "auburn", "skin": "tone4", "color": "lime"},
	"after_hours_hoodie": {"shoes": "glow_sneakers", "hair": "curly", "hair_color": "espresso", "skin": "tone8", "color": "plum"},
	"night_owl": {"shoes": "slippers", "hair": "tuft", "hair_color": "brown", "skin": "tone1", "color": "tangerine"},
	"glow_jogger": {"shoes": "glow_sneakers", "hair": "buns", "hair_color": "black", "skin": "tone6", "color": "mint", "hat": "glow_headband"},
	"library_cardigan": {"shoes": "moon_boots", "hair": "bob", "hair_color": "blonde", "skin": "tone3", "color": "sunny", "hat": "pompom_beanie"},
}
## Pass 8 rotating Shop outfits ("pass8" / "pass8back": all six at the
## follow camera's distance, with the default runner and a Night Watch for
## scale and role contrast; --light=dorm puts them on the lobby's marks)
const P8_OUTFITS := ["midnight_mechanic", "moonwalk_cadet", "pumpkin_pajamas", "arcade_sprinter", "cloud_nine", "bedtime_bandit"]
const P8_SHOWCASE := {
	"midnight_mechanic": {"hair": "tuft", "hair_color": "dark_brown", "skin": "tone5", "color": "sunny"},
	"moonwalk_cadet": {"hair": "bob", "hair_color": "black", "skin": "tone2", "color": "teal"},
	"pumpkin_pajamas": {"hair": "curly", "hair_color": "auburn", "skin": "tone3", "color": "tangerine"},
	"arcade_sprinter": {"hair": "buns", "hair_color": "black", "skin": "tone7", "color": "bubblegum"},
	"cloud_nine": {"hair": "bob", "hair_color": "blonde", "skin": "tone4", "color": "sky"},
	"bedtime_bandit": {"hair": "tuft", "hair_color": "espresso", "skin": "tone8", "color": "grape"},
}
## the follow camera (follow_camera.gd): 6.2 m from the target, pitched 0.32 rad, fov 66
const FOLLOW_DIST := 6.2
const FOLLOW_PITCH := 0.32
const FOLLOW_FOV := 66.0
## hats that leave hair visible (nightcap and swim cap hide it) x hair styles
const HATHAIR_HATS := ["party", "headphones", "crown"]
const HATHAIR_HAIRS := ["tuft", "bob", "curly", "buns"]
## Close-ups of the parts whose silhouettes were refined in V4 (same cameras
## before and after): [label, role, look overrides, yaw, camera from, camera at, fov]
const PARTS := [
	["nightcap", 0, {"hat": "nightcap"}, PI + 1.2, Vector3(0.0, 1.32, 1.35), Vector3(0, 1.28, 0), 34],
	["collar", 0, {"hat": "none", "pattern": "plain"}, PI + 0.35, Vector3(0.0, 0.95, 1.05), Vector3(0, 0.82, 0), 34],
	["cuff + hand", 0, {"hat": "none", "pattern": "plain"}, PI + 1.1, Vector3(-0.05, 0.62, 0.9), Vector3(0.0, 0.55, 0), 34],
	["robe hem", 0, {"outfit": "robe", "hat": "none", "shoes": "slippers"}, PI + 0.5, Vector3(0.0, 0.5, 1.5), Vector3(0, 0.38, 0), 34],
	["slippers", 0, {"shoes": "slippers"}, PI + 0.6, Vector3(0.0, 0.32, 1.0), Vector3(0, 0.08, 0), 34],
	["sneakers", 0, {"shoes": "sneakers"}, PI + 0.6, Vector3(0.0, 0.32, 1.0), Vector3(0, 0.08, 0), 34],
	["flippers", 0, {"shoes": "flippers", "outfit": "swim"}, PI + 0.6, Vector3(0.0, 0.32, 1.0), Vector3(0, 0.08, 0), 34],
	["watch boots", 1, {}, PI + 0.6, Vector3(0.0, 0.32, 1.0), Vector3(0, 0.08, 0), 34],
	["hair tuft", 0, {"hat": "none", "hair": "tuft"}, PI + 1.57, Vector3(0.0, 1.3, 1.5), Vector3(0, 1.2, 0), 34],
	["hair bob", 0, {"hat": "none", "hair": "bob", "hair_color": "auburn"}, PI + 2.2, Vector3(0.0, 1.3, 1.5), Vector3(0, 1.18, 0), 34],
	["hair buns", 0, {"hat": "none", "hair": "buns", "hair_color": "black"}, PI + 0.9, Vector3(0.0, 1.3, 1.5), Vector3(0, 1.2, 0), 34],
	["watch cap", 1, {}, PI + 0.9, Vector3(0.0, 1.32, 1.45), Vector3(0, 1.25, 0), 34],
]
const PARTS_DEBUG := [
	["cap no head", 0, {"hat": "nightcap"}, PI + 1.2, Vector3(0.0, 1.32, 1.35), Vector3(0, 1.28, 0), 34, ["base"]],
	["cap no head 2", 0, {"hat": "nightcap"}, PI + 0.6, Vector3(0.0, 1.32, 1.35), Vector3(0, 1.28, 0), 34, ["base"]],
	["cap no head 3", 0, {"hat": "nightcap"}, PI + 2.2, Vector3(0.0, 1.32, 1.35), Vector3(0, 1.28, 0), 34, ["base"]],
	["cap no head top", 0, {"hat": "nightcap"}, PI + 1.2, Vector3(0.0, 2.1, 0.6), Vector3(0, 1.35, 0), 34, ["base"]],
]
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
var _grabbing := false
var debug_parts := false
## --shots-file=FILE (mode "custom"): a JSON list of shots, vectors as [x, y, z]
var shots_file := ""
var reel_look: Dictionary = REEL_LOOK
## Pass 9: look overrides for the "faces" mode (--faces-look=JSON)
var faces_look: Dictionary = {}
var _reel_i := -1
var _reel_rig: MotionRig
var _reel_t := 0.0
var _reel_labels: Array = []
var _cam_at := Vector3.ZERO
var _lawn: MeshInstance3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lineup="):
			var m := a.split("=")[1]
			modes = MODES.duplicate() if m == "all" else Array(m.split(","))
		elif a.begins_with("--capture-dir="):
			out_dir = a.split("=")[1]
		elif a == "--parts-debug":
			debug_parts = true
		elif a.begins_with("--light="):
			lighting = a.split("=")[1]
		elif a.begins_with("--shots-file="):
			shots_file = a.split("=")[1]
		elif a.begins_with("--reel-look="):
			reel_look = JSON.parse_string(a.substr(a.find("=") + 1))
		elif a.begins_with("--faces-look="):
			faces_look = JSON.parse_string(a.substr(a.find("=") + 1))
	if modes.is_empty():
		modes = ["views"]
	if out_dir == "":
		out_dir = OS.get_user_data_dir().path_join("lineup")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_build_world()
	_next_mode()


func _build_world() -> void:
	if lighting == "dorm":
		# V6: the real dorm room behind the menus (its own lights, rug, window)
		var ds := DormStage.new()
		add_child(ds)
		cam = Camera3D.new()
		cam.fov = 30
		add_child(cam)
		cam.current = true
		stage = Node3D.new()
		stage.position = Vector3(0.0, 0.0, 0.5)
		add_child(stage)
		return
	if lighting == "campus":
		# the game's own night: environment, moon and a lawn-coloured floor
		add_child(EnvFactory.make_environment(1))
		add_child(EnvFactory.make_moon(1))
		var lawn := MeshInstance3D.new()
		_lawn = lawn
		var lp := PlaneMesh.new()
		lp.size = Vector2(60, 60)
		lawn.mesh = lp
		var lm := StandardMaterial3D.new()
		lm.albedo_color = Color(0.25, 0.46, 0.30)
		lm.roughness = 0.95
		lawn.material_override = lm
		add_child(lawn)
		cam = Camera3D.new()
		cam.fov = 30
		add_child(cam)
		cam.current = true
		stage = Node3D.new()
		add_child(stage)
		return
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
	# the dorm's warm rim light, as on the menu stages
	v.lighting = "indoor" if lighting == "dorm" else "outdoor"
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
		_mode = ""
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
			# (V6: the five V5 outfits; the new ones have their own modes)
			for i in mini(outfits.size(), 5):
				_add(TC.Role.RUNNER, look({"outfit": outfits[i], "pattern": pats[i], "hat": hats[i], "shoes": shoes[i], "color": colors[i],
					"skin": skins[(i * 3) % skins.size()], "hair": ["tuft", "bob", "curly", "buns", "tuft"][i % 5]}), -4.5 + i * 1.5, 0.0, PI + 0.35, String(outfits[i]))
			_add(TC.Role.PATROL, look({"color": "bubblegum", "skin": "tone4"}), 3.0, 0.0, PI + 0.35, "night watch")
			_aim(Vector3(-0.75, 1.5, 13.0), Vector3(-0.75, 0.85, 0), 32)
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
				var fl := {"outfit": "pj", "pattern": "plain", "hat": "none", "color": colors[i % colors.size()],
					"skin": skins[i % skins.size()], "hair": ["tuft", "bob", "curly", "buns"][i % 4]}
				fl.merge(faces_look, true)   # Pass 9: --faces-look={"outfit": "dr_doom"} (a complete skin's own head)
				var v := _add(TC.Role.RUNNER, look(fl), -3.15 + i * 0.7, 0.0, PI, shapes[i] if shapes[i] != "" else "neutral")
				v.set_process(false)
				v.tree.active = false
				v.anim.play("idle")
				v.anim.seek(0.0, true)
				v.anim.pause()
				for n in v._face_idx:
					v.face_mesh.set_blend_shape_value(v._face_idx[n], 0.0)
				if shapes[i] != "":
					v.face_mesh.set_blend_shape_value(v.face_mesh.find_blend_shape_by_name(shapes[i]), 1.0)
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
		"parts":
			_strip_frames.clear()
			_sheet_i = -1
			_sheet_wait = 0
		"reel":
			# no lawn: the splash sinks the runner as into water
			if _lawn:
				_lawn.visible = false
			_strip_frames.clear()
			_reel_labels.clear()
			_reel_i = -1
			_strip_next = 0.0
			_reel_t = 0.0
			_next_reel()
		"skintones", "shop", "season", "outfitsheet", "newhats", "newshoes", "hatgrid", "emotes", "custom":
			_shots = _build_shots(_mode)
			_strip_frames.clear()
			_sheet_i = -1
			_sheet_wait = 0
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
		"hathair":
			_strip_frames.clear()
			_sheet_i = -1
			_sheet_wait = 0
		"menuidle":
			var mv := _add(TC.Role.RUNNER, d, 0.0, 0.0, PI + 0.42, "")
			mv.lighting = "indoor"
			mv.set_appearance(mv.role, mv.cosmetic)   # indoor rim light, as in the dorm
			if mv.has_method("set_menu_idle"):
				mv.call("set_menu_idle", true)
			_aim(Vector3(0.0, 1.0, 5.6), Vector3(0, 0.78, 0), 30)
			_strip_frames.clear()
			_strip_next = 0.6
		"steps":
			_add(TC.Role.RUNNER, d, 0.0, 0.0, PI * 0.5, "")
			_aim(Vector3(0, 1.0, 7.5), Vector3(0, 0.8, 0), 34)
			_strip_frames.clear()
			_strip_next = 0.45
		"pass8", "pass8back":
			var back := _mode == "pass8back"
			var row: Array = [[TC.Role.RUNNER, d, "Pajamas (default)"]]
			for k in P8_OUTFITS:
				if not _has("outfit", k):
					continue
				var o: Dictionary = {"outfit": k, "hat": "none"}
				o.merge(P8_SHOWCASE.get(k, {}), true)
				row.append([TC.Role.RUNNER, look(o), String(Cosmetics.entry("outfit", k)["name"])])
			if lighting == "dorm":
				# the lobby's marks and framing (DormStage.MARKS / FRAMES["lobby"])
				for i in mini(row.size(), DormStage.MARKS.size()):
					var mk: Vector3 = DormStage.MARKS[i]
					_add(row[i][0], row[i][1], mk.x, mk.z, (0.0 if back else PI) + float(DormStage.YAW_BIAS[i]))
				_aim(Vector3(0, 3.1, 0.5 + 6.2), Vector3(0, 0.62, 0.5), 38)
			else:
				row.append([TC.Role.PATROL, look({"color": "lime", "skin": "tone5"}), "Night Watch"])
				for i in row.size():
					var x := -3.5 + i * 1.0
					_add(row[i][0], row[i][1], x, -0.25 * absf(i - 3.5), (0.0 if back else PI) + (3.5 - i) * 0.05)
				_aim(Vector3(0, 0.9 + FOLLOW_DIST * sin(FOLLOW_PITCH), FOLLOW_DIST * cos(FOLLOW_PITCH)), Vector3(0, 0.9, 0), FOLLOW_FOV)
			var names: Array = row.map(func(r: Array) -> String: return String(r[2]))
			var f := FileAccess.open(out_dir.path_join("lineup_%s.txt" % _mode), FileAccess.WRITE)
			f.store_string("left to right: " + ", ".join(PackedStringArray(names)))
		"distance":
			# typical follow-camera distance (about 6 m) and a far runner (20 m)
			_add(TC.Role.RUNNER, d, 0.0, 0.0, PI + 2.6)
			_add(TC.Role.RUNNER, look({"color": "bubblegum", "hair": "bob", "hat": "none"}), 3.0, -14.0, PI + 0.5)
			_add(TC.Role.PATROL, look({"color": "lime", "skin": "tone5"}), -4.0, -9.0, PI - 0.6)
			_aim(Vector3(0.6, 2.6, 5.8), Vector3(0, 0.9, -3.0), 62)


func _next_reel() -> void:
	if _reel_rig:
		_reel_rig.cleanup()
		_reel_rig.queue_free()
		_reel_rig = null
	_reel_i += 1
	if _reel_i >= REEL.size():
		_save_grid("reel", 6, _reel_labels)
		_next_mode()
		return
	_reel_rig = MotionRig.new()
	stage.add_child(_reel_rig)
	_reel_rig.start(REEL[_reel_i], look(reel_look), 0.0)
	_reel_rig.cam.current = false
	cam.current = true
	_reel_t = 0.0


## The camera rides with the character (its body yaw, not the bobbing head)
## and circles it once over the reel at 1.35 m, starting in front: front, side, back,
## other side.  It looks at the head, lightly smoothed (30 ms), so the
## goggles stay in frame however fast the runner moves.
func _reel_camera(delta: float) -> void:
	var v := _reel_rig.view
	var head := v.skeleton.global_transform * v.skeleton.get_bone_global_pose(v.skeleton.find_bone("head"))
	var target := head * Vector3(0.0, 0.2, 0.0)
	if _cam_at == Vector3.ZERO or target.distance_to(_cam_at) > 1.0:
		_cam_at = target
	_cam_at = _cam_at.lerp(target, 1.0 - exp(-delta / 0.03))
	var a := 0.5 + _t * TAU / 13.0
	var off := v.global_transform.basis * Vector3(sin(a) * 1.35, 0.14, -cos(a) * 1.35)
	cam.fov = 36.0
	cam.look_at_from_position(_cam_at + off, _cam_at)


func _process(delta: float) -> void:
	_t += delta
	match _mode:
		"reel":
			if _reel_rig == null:
				return
			_reel_t += delta
			_reel_camera(delta)
			if _t >= _strip_next:
				_strip_next += 0.25
				await RenderingServer.frame_post_draw
				_strip_frames.append(get_viewport().get_texture().get_image())
				_reel_labels.append("%s %.2f s" % [REEL[_reel_i] if _reel_i < REEL.size() else "", _reel_t])
			if _reel_rig != null and not _reel_rig.running:
				_next_reel()
			return
		"skintones", "shop", "season", "outfitsheet", "newhats", "newshoes", "hatgrid", "emotes", "custom":
			_run_shots()
		"parts":
			if _t < 0.5:
				return
			if _sheet_wait > 0:
				_sheet_wait -= 1
				return
			if _grabbing:
				return
			if _sheet_i >= 0:
				_grabbing = true
				await RenderingServer.frame_post_draw
				_strip_frames.append(get_viewport().get_texture().get_image())
				_grabbing = false
			_sheet_i += 1
			var shots: Array = PARTS_DEBUG if debug_parts else PARTS
			if _sheet_i >= shots.size():
				_save_grid("parts_debug" if debug_parts else "parts", 4, shots.map(func(p: Array) -> String: return String(p[0])))
				_next_mode()
				return
			var sh: Array = shots[_sheet_i]
			_clear()
			var role: int = TC.Role.PATROL if int(sh[1]) == 1 else TC.Role.RUNNER
			var over: Dictionary = {"outfit": "pj", "pattern": "stripes", "color": "sky", "skin": "tone3"}
			if role == TC.Role.PATROL:
				over = {"color": "sky", "skin": "tone6"}
			over.merge(sh[2], true)
			var pv := _add(role, look(over), 0.0, 0.0, float(sh[3]))
			_pose(pv, "idle", 0.0)
			if sh.size() > 7:
				for part in sh[7]:
					if pv.parts.has(part):
						pv.parts[part].visible = false
			_aim(sh[4], sh[5], float(sh[6]))
			_sheet_wait = 6
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
		"hathair":
			if _t < 0.5:
				return
			if _sheet_wait > 0:
				_sheet_wait -= 1
				return
			if _grabbing:
				return
			if _sheet_i >= 0:
				_grabbing = true
				await RenderingServer.frame_post_draw
				_strip_frames.append(get_viewport().get_texture().get_image())
				_grabbing = false
			_sheet_i += 1
			var n := HATHAIR_HATS.size() * HATHAIR_HAIRS.size() * 2
			if _sheet_i >= n:
				var labels: Array = []
				for i in n:
					labels.append("%s + %s (%s)" % [HATHAIR_HATS[(i / 2) / HATHAIR_HAIRS.size()], HATHAIR_HAIRS[(i / 2) % HATHAIR_HAIRS.size()], "front" if i % 2 == 0 else "back"])
				_save_grid("hathair", 6, labels)
				_next_mode()
				return
			var k := _sheet_i / 2
			_clear()
			var hv := _add(TC.Role.RUNNER, look({"hat": HATHAIR_HATS[k / HATHAIR_HAIRS.size()], "hair": HATHAIR_HAIRS[k % HATHAIR_HAIRS.size()],
				"hair_color": ["brown", "black", "auburn", "blonde"][k % 4], "skin": "tone3", "outfit": "pj"}), 0.0, 0.0,
				PI + (0.5 if _sheet_i % 2 == 0 else PI - 0.7))
			_pose(hv, "idle", 0.0)
			_aim(Vector3(0.0, 1.5, 2.1), Vector3(0, 1.34, 0), 32)
			_sheet_wait = 6
		"menuidle":
			if _t >= _strip_next and _t < 24.6:
				_strip_next += 1.2
				await RenderingServer.frame_post_draw
				_strip_frames.append(get_viewport().get_texture().get_image())
			if _t >= 24.8:
				_save_strip("menuidle", 5, [])
				_next_mode()
		"steps":
			_drive_steps()
			if _t >= _strip_next and _t < 3.4:
				_strip_next += 0.1
				await RenderingServer.frame_post_draw
				_strip_frames.append(get_viewport().get_texture().get_image())
			if _t >= 3.5:
				_save_strip("steps", 10, [])
				_next_mode()
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


## Start (0.5 s), run, stop (1.4 s), start again, reverse (2.6 s): the sim's
## own accelerations (46 / 52 m/s^2) and turn rate, on the spot.
var _steps_v := Vector3.ZERO
var _steps_yaw := PI * 0.5
var _steps_t := 0.0


func _drive_steps() -> void:
	if _views.is_empty():
		return
	var v := _views[0]
	var dt := _t - _steps_t
	_steps_t = _t
	var dir := Vector3(-1, 0, 0)
	var want := Vector3.ZERO
	if _t >= 0.5 and _t < 1.4:
		want = dir * 5.0
	elif _t >= 1.9 and _t < 2.6:
		want = dir * 5.0
	elif _t >= 2.6:
		want = -dir * 5.0
	var acc := Rules.cfg.ground_accel if want.length() >= _steps_v.length() * 0.9 else Rules.cfg.ground_decel
	_steps_v = _steps_v.move_toward(want, acc * dt)
	if _steps_v.length() > 0.6:
		_steps_yaw = rotate_toward(_steps_yaw, atan2(-_steps_v.x, -_steps_v.z), deg_to_rad(Rules.cfg.turn_rate_deg) * dt)
	v.apply_state({"pos": Vector3.ZERO, "yaw": _steps_yaw, "vel": _steps_v, "state": TC.PState.ACTIVE, "on_floor": true})


func _save(n: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var p := out_dir.path_join("lineup_%s.png" % n)
	img.save_png(p)
	printerr("LINEUP %s %dx%d" % [p, img.get_width(), img.get_height()])


## Whole frames, scaled into a grid (close-ups need the full frame).
func _save_grid(n: String, cols: int, labels: Array) -> void:
	if _strip_frames.is_empty():
		return
	var cw := 600
	var ch := int(600.0 * _strip_frames[0].get_height() / _strip_frames[0].get_width())
	var rows := int(ceil(_strip_frames.size() / float(cols)))
	var sheet := Image.create(cw * cols, ch * rows, false, Image.FORMAT_RGBA8)
	for i in _strip_frames.size():
		var f := _strip_frames[i]
		f.convert(Image.FORMAT_RGBA8)
		f.resize(cw, ch, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(f, Rect2i(0, 0, cw, ch), Vector2i((i % cols) * cw, (i / cols) * ch))
	var p := out_dir.path_join("lineup_%s.png" % n)
	sheet.save_png(p)
	var f2 := FileAccess.open(out_dir.path_join("lineup_%s.txt" % n), FileAccess.WRITE)
	f2.store_string("\n".join(PackedStringArray(labels)))
	printerr("LINEUP %s %dx%d frames=%d" % [p, sheet.get_width(), sheet.get_height(), _strip_frames.size()])


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


# ---------------------------------------------------------------- V6 shot sequences
## A shot: {label, look (overrides of the hero look), role, yaw, from, at,
## fov, clip, t (pose time), hide (parts), x (character offset)}.  Each is
## posed, framed, rendered and added to a grid saved as lineup_<mode>.png
## (labels in lineup_<mode>.txt).
var _shots: Array = []
var _shot_cols := 4


func _has(field: String, key: String) -> bool:
	return Cosmetics.CATALOG.get(field, {}).has(key)


func _build_shots(m: String) -> Array:
	var out: Array = []
	var skins: Array = Cosmetics.keys_of("skin")
	match m:
		"custom":
			var data = JSON.parse_string(FileAccess.get_file_as_string(shots_file))
			_shot_cols = 4
			for d in data:
				var sh: Dictionary = d
				for k in ["from", "at"]:
					var a: Array = sh[k]
					sh[k] = Vector3(a[0], a[1], a[2])
				if sh.has("cols"):
					_shot_cols = int(sh["cols"])
				if sh.has("yaw_deg"):
					sh["yaw"] = PI + deg_to_rad(float(sh["yaw_deg"]))
				out.append(sh)
		"skintones":
			_shot_cols = 4
			var hs := ["tuft", "bob", "curly", "buns"]
			var hc := ["brown", "black", "auburn", "dark_brown", "blonde", "espresso", "black", "ginger"]
			var cols := ["sky", "bubblegum", "lime", "sunny", "grape", "teal", "tangerine", "cloud"]
			for i in skins.size():
				out.append({"label": "%s (%s hair)" % [skins[i], hc[i]], "look": {"skin": skins[i], "outfit": "pj", "pattern": "plain",
					"color": cols[i], "hat": "none", "hair": hs[i % 4], "hair_color": hc[i]}, "yaw": PI + 0.35,
					"from": Vector3(0.0, 1.2, 2.0), "at": Vector3(0, 1.08, 0), "fov": 30.0})
		"shop", "season":
			_shot_cols = 3 if m == "shop" else 4
			var keys: Array = V6_OUTFITS.slice(0, 6) if m == "shop" else V6_OUTFITS.slice(6)
			for k in keys:
				if not _has("outfit", k):
					continue
				var o: Dictionary = {"outfit": k, "hat": "none"}
				o.merge(SHOWCASE.get(k, {}), true)
				for side in [0, 1]:
					out.append({"label": "%s (%s)" % [k, "front" if side == 0 else "back"], "look": o,
						"yaw": PI + (0.4 if side == 0 else PI - 0.5), "from": Vector3(0.0, 1.0, 3.6), "at": Vector3(0, 0.76, 0), "fov": 30.0})
		"outfitsheet":
			_shot_cols = 4
			for k in V6_OUTFITS:
				if not _has("outfit", k):
					continue
				var o: Dictionary = {"outfit": k, "hat": "none"}
				o.merge(SHOWCASE.get(k, {}), true)
				out.append({"label": k + " idle", "look": o, "yaw": PI + 0.4, "from": Vector3(0.0, 1.0, 3.6), "at": Vector3(0, 0.76, 0), "fov": 30.0})
				out.append({"label": k + " run", "look": o, "yaw": PI + 1.25, "clip": "run", "t": 0.3, "from": Vector3(0.0, 1.0, 3.6),
					"at": Vector3(0, 0.76, 0), "fov": 30.0})
				out.append({"label": k + " sprint", "look": o, "yaw": PI - 1.1, "clip": "sprint", "t": 0.62, "from": Vector3(0.0, 1.0, 3.6),
					"at": Vector3(0, 0.76, 0), "fov": 30.0})
				var em: String = "emote_" + (V6_EMOTES[V6_OUTFITS.find(k) % 4] if _has("emote", V6_EMOTES[0]) else "cheer")
				out.append({"label": k + " " + em, "look": o, "yaw": PI + 0.3, "clip": em, "t": 0.45, "from": Vector3(0.0, 1.0, 3.6),
					"at": Vector3(0, 0.76, 0), "fov": 30.0})
		"newhats":
			_shot_cols = 4
			var hairs := ["tuft", "bob", "curly", "buns"]
			for i in V6_HATS.size():
				var h: String = V6_HATS[i]
				if not _has("hat", h):
					continue
				for j in 4:
					out.append({"label": "%s + %s" % [h, hairs[j]], "look": {"hat": h, "hair": hairs[j], "outfit": "pj", "pattern": "plain",
						"hair_color": ["brown", "black", "auburn", "blonde"][j], "skin": skins[(i * 2 + j) % 8], "color": "teal"},
						"yaw": PI + (0.5 if j % 2 == 0 else PI - 0.7), "from": Vector3(0.0, 1.45, 2.1), "at": Vector3(0, 1.3, 0), "fov": 32.0})
		"newshoes":
			_shot_cols = 4
			for sh in V6_SHOES:
				if not _has("shoes", sh):
					continue
				for j in 2:
					out.append({"label": "%s (%s)" % [sh, "front" if j == 0 else "side"], "look": {"shoes": sh, "outfit": "pj", "pattern": "plain"},
						"yaw": PI + (0.6 if j == 0 else 1.5), "from": Vector3(0.0, 0.34, 1.0), "at": Vector3(0, 0.1, 0), "fov": 34.0})
		"hatgrid":
			# every outfit x every hat, head close-ups (clipping review)
			_shot_cols = Cosmetics.keys_of("hat").size()
			for o in Cosmetics.keys_of("outfit"):
				for h in Cosmetics.keys_of("hat"):
					out.append({"label": "%s + %s" % [o, h], "look": {"outfit": o, "hat": h, "hair": ["tuft", "bob", "curly", "buns"][(out.size() / 3) % 4]},
						"yaw": PI + 0.55, "from": Vector3(0.0, 1.35, 2.3), "at": Vector3(0, 1.15, 0), "fov": 34.0})
		"emotes":
			_shot_cols = 8
			for e in V6_EMOTES:
				if not _has("emote", e):
					continue
				var o2: Dictionary = {"outfit": V6_OUTFITS[V6_EMOTES.find(e)], "hat": "none"}
				o2.merge(SHOWCASE.get(o2["outfit"], {}), true)
				for i in 8:
					out.append({"label": "%s %d/8" % [e, i], "look": o2, "yaw": PI + 0.35, "clip": "emote_" + e, "t": i * 0.2,
						"from": Vector3(0.0, 1.0, 3.6), "at": Vector3(0, 0.78, 0), "fov": 30.0})
	return out


func _run_shots() -> void:
	if _t < 0.5:
		return
	if _sheet_wait > 0:
		_sheet_wait -= 1
		return
	if _grabbing:
		return
	if _sheet_i >= 0:
		_grabbing = true
		await RenderingServer.frame_post_draw
		_strip_frames.append(get_viewport().get_texture().get_image())
		_grabbing = false
	_sheet_i += 1
	if _sheet_i >= _shots.size():
		_save_grid(_mode, _shot_cols, _shots.map(func(p: Dictionary) -> String: return String(p["label"])))
		_next_mode()
		return
	var sh: Dictionary = _shots[_sheet_i]
	_clear()
	var role: int = int(sh.get("role", TC.Role.RUNNER))
	var over: Dictionary = {"outfit": "pj", "pattern": "stripes", "color": "sky", "skin": "tone3"}
	over.merge(sh.get("look", {}), true)
	var pv := _add(role, look(over), float(sh.get("x", 0.0)), 0.0, float(sh.get("yaw", PI)))
	var clip := String(sh.get("clip", "idle"))
	_pose(pv, clip, float(sh.get("t", 0.0)))
	# the expression that state shows in play (no blink mid-shot)
	pv._blink_t = 99.0
	pv._update_face(1.0, clip if clip.begins_with("emote_") else "ground", false, 0, false)
	if sh.has("face"):
		# Pass 9: a held expression on the visible head ({"smile": 1.0, ...})
		pv.show_face(sh["face"])
	for part in sh.get("hide", []):
		if pv.parts.has(part):
			pv.parts[part].visible = false
	# Pass 9: more characters in the same shot ("also": [{look, x, z, yaw_deg, clip, t, role, face}])
	for o in sh.get("also", []):
		var od: Dictionary = o
		var ov: Dictionary = {"outfit": "pj", "pattern": "stripes", "color": "sky", "skin": "tone3"}
		ov.merge(od.get("look", {}), true)
		var av := _add(int(od.get("role", TC.Role.RUNNER)), look(ov), float(od.get("x", 0.0)), float(od.get("z", 0.0)),
			PI + deg_to_rad(float(od.get("yaw_deg", 0.0))))
		_pose(av, String(od.get("clip", "idle")), float(od.get("t", 0.0)))
		av._blink_t = 99.0
		av._update_face(1.0, "ground", false, 0, false)
		if od.has("face"):
			av.show_face(od["face"])
	if sh.has("bone"):
		# V7: frame a bone wherever the pose put it ("from" and "at" are
		# offsets from the bone's head in world space)
		var bi := pv.skeleton.find_bone(String(sh["bone"]))
		var bp: Vector3 = (pv.skeleton.global_transform * pv.skeleton.get_bone_global_pose(bi)).origin
		_aim(bp + (sh["from"] as Vector3), bp + (sh["at"] as Vector3), float(sh.get("fov", 30.0)))
	else:
		_aim(sh["from"], sh["at"], float(sh.get("fov", 30.0)))
	_sheet_wait = 6

