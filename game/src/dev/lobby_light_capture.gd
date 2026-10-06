extends Node
## Development-only evidence for the final lobby lighting pass (src/dev: never
## exported).  Walks the screens the dorm room shows through, with the same
## looks and the same cameras on every run, so a before and an after frame
## differ only by the change being judged:
##   00_home_new    a new player's Home (default look, the tutorial hint)
##   01_home        Home for a returning player (after the hello wave)
##   02_locker      the Locker (wardrobe framing)
##   03_shop        the Shop as it opens (service off, as shipped)
##   04_shop_dark   the Shop detail of a charcoal outfit, tried on (a black garment large)
##   05_season      the Season Pass (service off, as shipped)
##   06_lobby_1p    a party room with only you (in-process loopback transport, no network)
##   07_lobby_4p    + Record Breaker, Dr. Doom and a charcoal suit
##   08_lobby_8p    + an ivory space suit, white pajamas, midnight track suit, yellow raincoat
## Every shot is saved three ways: <shot>.png (what the player sees),
## <shot>_3d.png (the UI hidden) and <shot>_room.png (the UI and characters
## hidden), plus <shot>.json: the projected face/torso point and radius of
## each character, reference points in the room (lamp shade, window, wall,
## furniture, floor), and the rect, font colour and text of every visible
## label/button.  tools/lobby_light_measure.py turns these into numbers.
## The clock is the frame counter (run with --fixed-fps 30), so poses repeat.
## Desktop render (Mobile renderer, llvmpipe): look and layout evidence only,
## never frame rate.
##
##   tools/capture_final_lobby.sh OUT_DIR NAME [devices...]

const LABEL := "desktop render, llvmpipe"
const StoreShot := preload("res://src/dev/store_shot.gd")

var out_dir := ""
var only := ""
var _hub: LoopbackTransport.Hub
var _host: NetSession
var _clients: Array[NetSession] = []
var _tag: Label
var _tag_layer: CanvasLayer

## Looks (fixed; fictional names).  The local player wears the default look
## a new player starts with.
const GUESTS := [
	["Pip", {"outfit": "record_breaker"}],
	["Rowan", {"outfit": "dr_doom"}],
	["Biscuit", {"outfit": "bedtime_bandit", "skin": "tone5"}],
	["Marigold", {"outfit": "moonwalk_cadet", "skin": "tone3", "hair": "bob", "hair_color": "auburn"}],
	["Dozy", {"outfit": "pj", "pattern": "plain", "color": "cloud", "trim": "navy", "skin": "tone7", "hair": "curly",
		"hair_color": "black", "hat": "none", "shoes": "sneakers"}],
	["Wren", {"outfit": "moonlight_runner", "color": "navy", "skin": "tone8", "hair": "buns", "hair_color": "black", "hat": "none"}],
	["Juniper", {"outfit": "raincoat_explorer", "skin": "tone4", "hair": "tuft", "hair_color": "ginger", "hat": "none"}],
]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture-dir="):
			out_dir = a.get_slice("=", 1)
		elif a.begins_with("--only="):
			only = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_tag_layer = CanvasLayer.new()
	_tag_layer.layer = 120
	add_child(_tag_layer)
	_tag = Label.new()
	_tag.add_theme_font_size_override("font_size", 15)
	_tag.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_tag.add_theme_constant_override("outline_size", 4)
	_tag.text = LABEL
	_tag.visible = not StoreShot.on()   # --store-shot: nothing stamped
	_tag_layer.add_child(_tag)
	StoreShot.quiet_overlays()
	_run.call_deferred()


func _physics_process(delta: float) -> void:
	if _hub != null:
		_hub.advance(delta)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _portraits_idle(max_s: float = 15.0) -> void:
	var t := 0.0
	while t < max_s:
		var ps := Portraits.shared()
		if ps.pending() == 0 and not ps._busy:
			break
		await get_tree().process_frame
		t += get_process_delta_time()
	await _wait(0.35)


func _wanted(shot: String) -> bool:
	return only == "" or shot.begins_with(only)


# ------------------------------------------------------------------ shots
func snap(shot: String) -> void:
	if not _wanted(shot):
		return
	var vp := get_viewport()
	_tag.position = Vector2(8, vp.get_visible_rect().size.y - 22.0)
	steady_poses()
	await _wait(0.5)
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if StoreShot.on():
		StoreShot.save_rgb(img.duplicate(), out_dir.path_join(shot + ".png"))
	else:
		img.save_png(out_dir.path_join(shot + ".png"))
	var rep := _report(img)
	# the 3D alone (the UI layer hidden for a frame), then the room alone
	var ui: CanvasLayer = App._ui_layer
	var hidden_layers: Array = []
	for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var cl := n as CanvasLayer
		if cl.visible:
			hidden_layers.append(cl)
			cl.visible = false
	if ui and ui.visible:
		hidden_layers.append(ui)
		ui.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(out_dir.path_join(shot + "_3d.png"))
	rep["chars"] = _chars()
	var shown: Array = []
	if App.stage:
		for k in App.stage.chars:
			var v: CharacterView = App.stage.chars[k]
			if is_instance_valid(v) and v.visible:
				v.visible = false
				shown.append(v)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(out_dir.path_join(shot + "_room.png"))
	for v in shown:
		(v as CharacterView).visible = true
	for cl in hidden_layers:
		(cl as CanvasLayer).visible = true
	var f := FileAccess.open(out_dir.path_join(shot + ".json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(rep, "  ", false))
		f.close()
	printerr("CAPTURE %s %dx%d" % [shot, img.get_width(), img.get_height()])


## Same pose on every run: each character's idle clock restarts together,
## with no fidget or blink due (CharacterView seeds them per instance, so
## two runs would otherwise catch different idle phases and blinks).
static func steady_poses() -> void:
	if App.stage == null:
		return
	for k in App.stage.chars:
		var v: CharacterView = App.stage.chars[k]
		if is_instance_valid(v):
			v._idle_clock = 0.0
			v._next_fidget = 1.0e6
			v._blink_t = 1.0e6


func _report(img: Image) -> Dictionary:
	var vp := get_viewport()
	var view := vp.get_visible_rect().size
	var rep := {"label": LABEL, "image": [img.get_width(), img.get_height()], "view": [view.x, view.y],
		"px_per_unit": float(img.get_width()) / maxf(1.0, view.x), "quality": int(Save.get_setting("quality", 1)),
		"screen": "" if App.screen == null else String((App.screen.get_script() as Script).get_global_name()),
		"stage_mode": App.stage.mode if App.stage else ""}
	rep["refs"] = _refs()
	rep["texts"] = _texts()
	return rep


func _proj(p: Vector3, r: float) -> Dictionary:
	var cam: Camera3D = App.stage.cam
	if cam.is_position_behind(p):
		return {}
	var c := cam.unproject_position(p)
	var e := cam.unproject_position(p + cam.global_transform.basis.x * r)
	return {"x": snappedf(c.x, 0.1), "y": snappedf(c.y, 0.1), "r": snappedf(c.distance_to(e), 0.1)}


## Fixed room points (stage space; DormStage._build_room).
func _refs() -> Dictionary:
	var out := {}
	if App.stage == null:
		return out
	var pts := {
		"lamp_shade": [Vector3(3.9, 1.71, -1.53), 0.12],      # the floor lamp's lit shade (warm highlight)
		"table_lamp": [Vector3(-2.1, 0.66, -2.04), 0.05],     # the small table lamp's shade
		"window_sky": [Vector3(-1.3, 2.95, -3.6), 0.22],      # the night sky through the upper-left pane
		"window_sill": [Vector3(-0.4, 1.27, -3.25), 0.05],    # the ivory painted sill (a near-white surface)
		"back_wall": [Vector3(3.3, 3.25, -3.47), 0.25],       # wallpaper right of the poster
		"curtain": [Vector3(-2.35, 2.0, -3.25), 0.07],        # red curtain left of the window
		"couch": [Vector3(-3.6, 0.6, -2.17), 0.2],            # couch seat front (blue fabric, in shade)
		"armchair": [Vector3(2.62, 0.62, -1.88), 0.12],       # terracotta armchair seat (lamp side)
		"bookshelf_base": [Vector3(5.1, 0.12, -2.64), 0.05],  # dark wood plinth under the first shelf
		"floor_front": [Vector3(-1.3, 0.0, 2.3), 0.25],       # planks in front of the rug
		"floor_lamp_pool": [Vector3(3.3, 0.0, -0.9), 0.25],   # planks in the lamp's pool
		"rug": [Vector3(1.9, 0.03, 0.9), 0.15],
		"beanbag": [Vector3(4.0, 0.45, 1.6), 0.15],
	}
	for k in pts:
		var spec: Array = pts[k]
		var p := App.stage.to_global(spec[0])
		var d := _proj(p, float(spec[1]))
		if not d.is_empty():
			out[k] = d
	return out


func _chars() -> Array:
	var out: Array = []
	if App.stage == null:
		return out
	for k in App.stage.chars:
		var v: CharacterView = App.stage.chars[k]
		if not is_instance_valid(v) or not v.visible or v.skeleton == null:
			continue
		var sk := v.skeleton
		var head := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("head")).origin
		var chest := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("chest")).origin
		var hips := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("hips")).origin if sk.find_bone("hips") >= 0 else chest
		var fwd := -v.global_transform.basis.z.normalized()   # face_toward(): -Z faces the target
		var up := Vector3.UP
		out.append({"key": String(k), "local": v == App.stage.local_character(), "outfit": String(v.cosmetic.get("outfit", "")),
			"skin": String(v.cosmetic.get("skin", "")), "color": String(v.cosmetic.get("color", "")),
			"head_bone": _proj(head, 0.1), "face": _proj(head + up * 0.15 + fwd * 0.12, 0.05),
			"torso": _proj(chest.lerp(hips, 0.35) + fwd * 0.12, 0.07), "feet": _proj(v.global_position, 0.1)})
	return out


func _texts() -> Array:
	var out: Array = []
	if App.screen == null or not is_instance_valid(App.screen):
		return out
	for n in (App.screen as Node).find_children("*", "Control", true, false):
		var c := n as Control
		if not c.is_visible_in_tree():
			continue
		var text := ""
		var col := Color(0, 0, 0, 0)
		if c is Label:
			text = (c as Label).text
			col = c.get_theme_color("font_color")
		elif c is Button:
			var b := c as Button
			var face := UIKit.face_of(b)
			text = b.text if b.text != "" else (face.caption if face != null else "")
			col = c.get_theme_color("font_color")
		else:
			continue
		if text.strip_edges() == "":
			continue
		var r := c.get_global_rect()
		# the share of the text box its scrolling/clipping ancestors leave in view
		var shown := r
		var p := c.get_parent()
		while p != null and p is Control:
			if p is ScrollContainer or (p as Control).clip_contents:
				shown = shown.intersection((p as Control).get_global_rect())
			p = p.get_parent()
		var vis := (shown.get_area() / r.get_area()) if r.get_area() > 0.0 and shown.has_area() else 0.0
		out.append({"kind": "label" if c is Label else "button", "visible": snappedf(vis, 0.01), "text": text.substr(0, 48), "rect": [snappedf(r.position.x, 0.1),
			snappedf(r.position.y, 0.1), snappedf(r.size.x, 0.1), snappedf(r.size.y, 0.1)], "color": col.to_html(true),
			"size": c.get_theme_font_size("font_size")})
	return out


# ------------------------------------------------------------------ flow
func _setup_profile() -> void:
	var look: Dictionary = Cosmetics.DEFAULT.duplicate()
	Save.data = Save.migrate({"version": 3, "uid": "local-capture", "name": "Comfy Frog", "coins": 240, "level": 6, "xp": 40,
		"owned": [], "onboarded": true, "tutorial_done": true, "cosmetic": look,
		"stats": {"online": {"matches": 14}, "practice": {"matches": 6}}, "settings": Save.data.get("settings", {})})
	Save.data["onboarded"] = true


func _look(over: Dictionary) -> Dictionary:
	var c: Dictionary = Cosmetics.DEFAULT.duplicate()
	for k in over:
		c[k] = over[k]
	return Cosmetics.sanitize(c)


func _run() -> void:
	await _wait(0.5)
	_setup_profile()
	# a new player's first Home (after Create Your Runner): the tutorial hint
	Save.data["tutorial_done"] = false
	App.goto_title()
	await _wait(4.0)
	await snap("00_home_new")
	Save.data["tutorial_done"] = true
	App.goto_title()
	await _wait(4.0)
	await snap("01_home")
	NavShell.open("locker")
	await _wait(2.5)
	await _portraits_idle()
	await snap("02_locker")
	NavShell.open("shop")
	await _wait(2.5)
	await _portraits_idle()
	await snap("03_shop")
	var shop := App.screen as ShopScreen
	if shop:
		shop._open_detail("outfit:bedtime_bandit")
		await _wait(2.0)
		await snap("04_shop_dark")
		shop._go_hub()   # restores the saved look
		await _wait(0.5)
	NavShell.open("pass")
	await _wait(2.5)
	await _portraits_idle()
	await snap("05_season")
	App.goto_title()
	await _wait(1.0)
	await _party(1)
	await snap("06_lobby_1p")
	await _party(4)
	await snap("07_lobby_4p")
	await _party(8)
	await snap("08_lobby_8p")
	printerr("CAPTURE-DONE")
	get_tree().quit()


## A party room on the in-process loopback transport (no network): this
## device hosts; guests join with fixed looks and are marked ready.
func _party(n: int) -> void:
	if _hub == null:
		_hub = LoopbackTransport.Hub.new(7)
		var ht := LoopbackTransport.new(_hub, true)
		_host = NetSession.new()
		_host.name = "LightCaptureHost"
		add_child(_host)
		_host.start_host(ht, "ACE347", Save.player_uid(), Save.party_name(), Save.data["cosmetic"], "any")
		App.session = _host
	while _clients.size() < n - 1:
		var i := _clients.size()
		var g: Array = GUESTS[i]
		var ct := LoopbackTransport.new(_hub, false)
		var c := NetSession.new()
		c.name = "LightCaptureGuest%d" % i
		add_child(c)
		c.start_client(ct, "ACE347", "guest-%d" % i, String(g[0]), _look(g[1]), "any")
		_clients.append(c)
		_hub.link((_host.transport as LoopbackTransport).id, ct.id)
		await _wait(0.25)
	if not (App.screen is LobbyScreen):
		App.show_lobby()
	await _wait(1.2)
	for c in _clients:
		if c.local_slot >= 0:
			c.set_local_ready(true)
	await _wait(4.5)
	await _portraits_idle()
