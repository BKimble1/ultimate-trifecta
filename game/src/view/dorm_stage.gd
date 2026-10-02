class_name DormStage
extends Node3D
## The dorm common room behind the menus: home (one character, front
## three-quarter), wardrobe (one character, larger) and the party lobby (up
## to eight characters on stable marks).  Rendered in the root viewport at
## native resolution (no SubViewport resampling).  The camera is stationary
## per mode; switching modes eases over ~200 ms (cut with Reduced Motion).
##
## Characters are keyed by a stable identity (player uid) and updated in
## place: sync_party() adds arrivals (with one short arrival hop), removes
## leavers and changes outfits without rebuilding anyone else.

## Lobby marks, filled in order (0 = the local player, front centre).  Nobody
## stands directly behind anyone: every back-row mark sits between two
## front-row marks, so with the raised camera each face clears the heads (and
## nightcaps) in front at 1, 2, 4 or 8 players (test_lobby checks this).
const MARKS := [
	Vector3(0.0, 0, 1.25),
	Vector3(-1.12, 0, 0.9), Vector3(1.12, 0, 0.9),
	Vector3(-0.62, 0, -0.2), Vector3(0.62, 0, -0.2),
	Vector3(-2.15, 0, 0.42), Vector3(2.15, 0, 0.42),
	Vector3(1.78, 0, -0.62),
]
## each character turns a little toward the group's centre
const YAW_BIAS := [0.0, 0.2, -0.2, 0.12, -0.12, 0.32, -0.32, -0.1]
## Framing per mode, independent of screen aspect: the subject point is put
## at `x_frac` of the screen width (the menu / party panel owns the right
## side), `height` metres of the scene fill the screen height.
##   [subject, height_m, x_frac, cam_height, look_down_extra, fov]
const FRAMES := {
	"home": [Vector3(0.62, 0.86, 0.6), 2.75, 0.40, 1.05, 0.0, 34.0],
	"wardrobe": [Vector3(0.62, 0.84, 0.6), 2.35, 0.27, 1.0, 0.0, 34.0],
	"lobby": [Vector3(0.0, 0.62, 0.0), 4.5, 0.33, 3.1, 0.0, 38.0],
}
const HOME_MARK := Vector3(0.62, 0, 0.6)

## half-width of a character on its mark (body + arms + head), metres
const BODY_HALF_W := 0.62
## fraction of the screen width left of the party panel (set by LobbyScreen)
var lobby_free_frac := 0.62
var cam: Camera3D
var chars: Dictionary = {}       # key -> CharacterView
var _mark_of: Dictionary = {}    # key -> mark index
var _ready_of: Dictionary = {}   # key -> last ready flag (ready response once per change)
var mode := "home"
var reduced_motion := false
var _cam_from: Array = []
var _cam_t := 1.0
var _cam_dur := 0.2
var _t := 0.0
var _lamp: OmniLight3D
## Emotes: who is emoting until when.  The newest emote owns the character
## (no timers: an older emote can never cancel a newer one), and a repeat of
## the same emote restarts it.
var _emote_until: Dictionary = {}   # key -> stage time the emote ends
var _bubbles: Dictionary = {}       # key -> Label3D (the emote's name over the head)
## "Try moves": key -> {kind, t, len} local presentation of the player's own runner
var _preview: Dictionary = {}

## How long each lobby emote plays: two passes of its loop, so a glance
## catches it (the clips are 1.2-1.4 s loops).
const EMOTE_S := {"wave": 2.4, "cheer": 2.4, "laugh": 2.4, "shrug": 2.8, "dance": 3.75, "point": 2.4}
const PREVIEW_S := {"idle": 1.2, "run": 2.4, "sprint": 2.4, "jump": 1.1, "dive": 1.3}


func _ready() -> void:
	reduced_motion = bool(Save.get_setting("reduced_motion", false))
	_build_room()
	cam = Camera3D.new()
	add_child(cam)
	cam.current = true
	_apply_cam(_cam_for(mode), 1.0)
	get_viewport().size_changed.connect(func() -> void:
		if _cam_t >= 1.0:
			_apply_cam(_cam_for(mode), 1.0))


## Camera [position, look_at, fov] for a mode at the current aspect ratio.
func _cam_for(m: String) -> Array:
	var f: Array = FRAMES[m]
	var subject: Vector3 = f[0]
	var height_m: float = f[1]
	var x_frac: float = f[2]
	var fov: float = f[5]
	var vs := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(16, 9)
	var aspect := vs.x / maxf(1.0, vs.y)
	var cam_h := float(f[3])
	if m == "lobby":
		# frame the marks actually in use (1 to 8 players), centred in the free
		# area left of the party panel, on any aspect (phone 19.5:9 ... iPad 4:3)
		var b := _group_bounds()
		subject = Vector3((b.x + b.y) * 0.5, subject.y, (b.z + b.w) * 0.5)
		var group_w := b.y - b.x + BODY_HALF_W * 2.0
		x_frac = lobby_free_frac * 0.5
		height_m = maxf(2.6 + 0.35 * (b.w - b.z), (group_w * 1.3 / lobby_free_frac) / aspect)
		# the camera rises with the depth of the group so back-row faces clear the front row
		cam_h = 1.5 + 2.2 * clampf((b.w - b.z) / 1.7, 0.0, 1.0)
	var dist := height_m * 0.5 / tan(deg_to_rad(fov) * 0.5)
	var width_m := height_m * aspect
	var shift := (0.5 - x_frac) * width_m      # look right of the subject
	var at := subject + Vector3(shift, 0, 0)
	# home/wardrobe: the camera sits right of the character and looks straight
	# ahead.  Lobby: it stays in front of the group's centre and turns toward
	# the same aim point, so the staggered back row is seen *between* the
	# front row (from the side, back-row faces fell behind front heads)
	var cam_x := subject.x if m == "lobby" else at.x
	var from := Vector3(cam_x, cam_h, subject.z + sqrt(maxf(0.01, dist * dist - pow(cam_h - subject.y, 2.0))))
	return [from, at, fov]


## x min, x max, z min, z max of the occupied lobby marks.
func _group_bounds() -> Vector4:
	var b := Vector4(INF, -INF, INF, -INF)
	for k in _mark_of:
		var p: Vector3 = MARKS[int(_mark_of[k])]
		b = Vector4(minf(b.x, p.x), maxf(b.y, p.x), minf(b.z, p.z), maxf(b.w, p.z))
	if b.x == INF:
		var p0: Vector3 = MARKS[0]
		b = Vector4(p0.x, p0.x, p0.z, p0.z)
	return b


## Party size changed: ease the camera to the new framing (cut with Reduced Motion).
func _reframe() -> void:
	if mode != "lobby" or not is_inside_tree():
		return
	_cam_from = [cam.global_position, cam.global_position - cam.global_transform.basis.z * 3.0, cam.fov]
	_cam_t = 1.0 if reduced_motion else 0.0
	_cam_dur = 0.25
	if _cam_t >= 1.0:
		_apply_cam(_cam_for(mode), 1.0)
	for k in chars:
		_place(k)


func set_lobby_free_frac(f: float) -> void:
	f = clampf(f, 0.3, 1.0)
	if absf(f - lobby_free_frac) < 0.01:
		return
	lobby_free_frac = f
	if mode == "lobby" and _cam_t >= 1.0:
		_apply_cam(_cam_for(mode), 1.0)
		for k in chars:
			_place(k)


func set_mode(m: String, animate: bool = true) -> void:
	if not FRAMES.has(m):
		return
	if m == mode and _cam_t >= 1.0:
		return
	_cam_from = [cam.global_position, cam.global_position - cam.global_transform.basis.z * 3.0, cam.fov]
	mode = m
	_cam_t = 0.0 if (animate and not reduced_motion and is_inside_tree()) else 1.0
	_cam_dur = 0.2
	if _cam_t >= 1.0:
		_apply_cam(_cam_for(m), 1.0)
	for k in chars:
		_place(k)


func _apply_cam(c: Array, u: float) -> void:
	var to_p: Vector3 = c[0]
	var to_at: Vector3 = c[1]
	var to_fov: float = c[2]
	if u < 1.0 and not _cam_from.is_empty():
		var e := 1.0 - pow(1.0 - u, 3.0)
		to_p = (_cam_from[0] as Vector3).lerp(to_p, e)
		to_at = (_cam_from[1] as Vector3).lerp(to_at, e)
		to_fov = lerpf(float(_cam_from[2]), to_fov, e)
	cam.fov = to_fov
	cam.look_at_from_position(to_p, to_at)


func _process(delta: float) -> void:
	_t += delta
	for k in _emote_until.keys():
		if _t >= float(_emote_until[k]):
			_end_emote(k)
	if not _preview.is_empty():
		_update_preview(delta)
	if _cam_t < 1.0:
		_cam_t = minf(1.0, _cam_t + delta / _cam_dur)
		_apply_cam(_cam_for(mode), _cam_t)
	if _lamp:
		_lamp.light_energy = 1.9 + 0.04 * sin(_t * 1.7)


## entries: [{key, role, cosmetic, name, is_bot, local}] (local first).
## Incremental: unchanged characters are left alone.  With exclusive=false
## characters missing from `entries` are kept (single-entry updates).
func sync_party(entries: Array, exclusive: bool = true) -> void:
	var seen := {}
	var marks_before := _mark_of.size()
	for e in entries:
		var key := String(e["key"])
		seen[key] = true
		var v: CharacterView = chars.get(key)
		var role := int(e.get("role", TC.Role.RUNNER))
		if v == null or not is_instance_valid(v):
			v = CharacterView.new()
			v.lighting = "indoor"
			v.reduced_motion = reduced_motion
			add_child(v)
			v.setup(role, e["cosmetic"], -1, String(e.get("name", "")), bool(e.get("is_bot", false)), bool(e.get("local", false)))
			chars[key] = v
			_mark_of[key] = _free_mark(bool(e.get("local", false)))
			_place(key)
			v.apply_state(_idle_rs(v), 0.0, true)
			if bool(e.get("arrive", true)) and mode == "lobby":
				v.play_arrive()
			_ready_of[key] = bool(e.get("ready", false))
		else:
			if v.cosmetic != Cosmetics.sanitize(e["cosmetic"]) or v.role != role:
				v.set_appearance(role, e["cosmetic"])
				if mode == "lobby":
					v.play_arrive()   # a little hop to show the new look
			var rdy := bool(e.get("ready", false))
			# the ready response plays once per change and never over a
			# deliberate emote or a move preview
			if rdy and not bool(_ready_of.get(key, false)) and mode == "lobby" and not emoting(key) and not _preview.has(key):
				v.play_ready()
			_ready_of[key] = rdy
		if v.name_label:
			var nm := String(e.get("name", ""))
			v.name_label.text = (nm + "  ·  BOT") if bool(e.get("is_bot", false)) else nm
			# names live in the party panel; 3D labels would overlap in a group
			v.name_label.visible = false
			v.name_label.font_size = 26
			v.name_label.position = Vector3(0, 1.82, 0)
	for k in chars.keys():
		if exclusive and not seen.has(k):
			var v: CharacterView = chars[k]
			if is_instance_valid(v):
				if mode == "lobby" and is_inside_tree():
					v.play_leave()
				else:
					v.queue_free()
			chars.erase(k)
			_mark_of.erase(k)
			_ready_of.erase(k)
			_emote_until.erase(k)
			_bubbles.erase(k)
			_preview.erase(k)
	if _mark_of.size() != marks_before:
		_reframe()


func _free_mark(local: bool) -> int:
	if local:
		return 0
	var used := {}
	for k in _mark_of:
		used[_mark_of[k]] = true
	for i in range(1, MARKS.size()):
		if not used.has(i):
			return i
	return MARKS.size() - 1


func _place(key: String) -> void:
	var v: CharacterView = chars.get(key)
	if v == null:
		return
	var mi: int = _mark_of.get(key, 0)
	var p: Vector3 = MARKS[mi]
	var yaw_bias := 0.0
	if mode == "home" or mode == "wardrobe":
		# single-character modes: everyone but the local player is hidden
		v.visible = mi == 0
		p = HOME_MARK
		yaw_bias = 0.42 if mode == "home" else 0.3
	else:
		v.visible = true
		yaw_bias = YAW_BIAS[mi]
	v.position = p
	var cpos: Vector3 = _cam_for(mode)[0]
	v.face_toward(Vector3(cpos.x, 0, cpos.z))
	v.set_facing(v.rotation.y + yaw_bias)
	v.rs["pos"] = v.global_position


func _idle_rs(v: CharacterView) -> Dictionary:
	return {"pos": v.global_position, "yaw": v.rotation.y, "state": TC.PState.ACTIVE, "vel": Vector3.ZERO, "on_floor": true}


## Plays an emote on a character.  Returns false (and does nothing) when that
## character isn't on the stage or the id is unknown.
func emote(key: String, id: int, seconds: float = -1.0) -> bool:
	var v: CharacterView = chars.get(key)
	if v == null or not is_instance_valid(v) or not v.visible or id < 0 or id >= TC.EMOTES.size():
		return false
	_preview.erase(key)
	var name: String = TC.EMOTES[id]
	var dur := seconds if seconds > 0.0 else float(EMOTE_S.get(name, 2.4))
	var rs := v.rs.duplicate()
	rs["emote"] = id
	rs["emote_t"] = 1.0
	rs["vel"] = Vector3.ZERO
	rs["on_floor"] = true
	rs.erase("diving")
	v.cancel_reactions()
	v.apply_state(rs)
	v.restart_emote(id)
	_emote_until[key] = _t + dur
	_show_bubble(key, v, String(TC.EMOTE_LABELS[name]))
	return true


func emoting(key: String) -> bool:
	return _emote_until.has(key)


func _end_emote(key: String) -> void:
	_emote_until.erase(key)
	var v: CharacterView = chars.get(key)
	if v != null and is_instance_valid(v):
		var r2 := v.rs.duplicate()
		r2["emote"] = -1
		r2["emote_t"] = 0.0
		v.apply_state(r2)
	var b: Label3D = _bubbles.get(key)
	if b != null and is_instance_valid(b):
		var tw := b.create_tween()
		tw.tween_property(b, "modulate:a", 0.0, 0.18)
		tw.tween_callback(func() -> void: b.visible = false)


func _show_bubble(key: String, v: CharacterView, text: String) -> void:
	var b: Label3D = _bubbles.get(key)
	if b == null or not is_instance_valid(b):
		b = Label3D.new()
		b.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		b.no_depth_test = true
		b.fixed_size = false
		b.pixel_size = 0.0042
		b.font_size = 46
		b.outline_size = 14
		b.font = UIKit.font_w(700)
		b.modulate = UIKit.IVORY
		b.outline_modulate = Color(UIKit.NAVY, 0.92)
		b.position = Vector3(0, 2.18, 0)
		b.render_priority = 4
		v.add_child(b)
		_bubbles[key] = b
	b.text = text
	b.visible = true
	b.modulate.a = 1.0
	if not reduced_motion:
		b.scale = Vector3.ONE * 0.6
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector3.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## "Try moves": a local presentation of the player's own runner on its mark
## (running and jumping on the spot).  Nothing is sent to the party; an
## emote, a new preview or leaving the room ends it.
func preview_move(key: String, kind: String) -> bool:
	var v: CharacterView = chars.get(key)
	if v == null or not is_instance_valid(v) or not PREVIEW_S.has(kind):
		return false
	if emoting(key):
		_end_emote(key)
	v.cancel_reactions()
	_preview[key] = {"kind": kind, "t": 0.0, "len": float(PREVIEW_S[kind])}
	return true


func stop_previews() -> void:
	for k in _preview.keys():
		var v: CharacterView = chars.get(k)
		if v != null and is_instance_valid(v):
			v.apply_state(_idle_rs(v))
	_preview.clear()


func _update_preview(delta: float) -> void:
	for k in _preview.keys():
		var v: CharacterView = chars.get(k)
		var pv: Dictionary = _preview[k]
		pv["t"] = float(pv["t"]) + delta
		if v == null or not is_instance_valid(v) or float(pv["t"]) >= float(pv["len"]):
			_preview.erase(k)
			if v != null and is_instance_valid(v):
				v.apply_state(_idle_rs(v))
			continue
		var t := float(pv["t"])
		var rs := _idle_rs(v)
		var fwd := Vector3(sin(v.rotation.y), 0, cos(v.rotation.y))
		match String(pv["kind"]):
			"run":
				rs["vel"] = fwd * Rules.cfg.runner_speed
			"sprint":
				rs["vel"] = fwd * Rules.cfg.runner_sprint_speed
				rs["sprinting"] = true
			"jump":
				# the real jump arc, on the spot
				var g := Rules.cfg.gravity
				var v0 := Rules.cfg.jump_velocity
				var air := t < 2.0 * v0 / g
				rs["on_floor"] = not air
				rs["vel"] = Vector3(0, v0 - g * t, 0) if air else Vector3.ZERO
				var base: Vector3 = MARKS[int(_mark_of.get(k, 0))] if mode == "lobby" else v.position
				rs["pos"] = to_global(Vector3(base.x, maxf(0.0, v0 * t - 0.5 * g * t * t) if air else 0.0, base.z))
			"dive":
				rs["diving"] = t < 0.75
				rs["on_floor"] = t >= 0.75
				rs["vel"] = fwd * (Rules.cfg.dive_speed * 0.3) if t < 0.75 else Vector3.ZERO
		v.apply_state(rs)


func local_character() -> CharacterView:
	for k in chars:
		if _mark_of.get(k, -1) == 0:
			return chars[k]
	return null


# ---------------------------------------------------------------------------
## dorm.gdshader surface codes (vertex alpha)
const WOOD := 0.9
const FABRIC := 0.8
const PAPER := 0.7
const GLOSS := 0.6


func _build_room() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("11192b")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("6d6f8c")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.4
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# warm key (shadows: contact shadows under the characters)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52, 32, 0)
	key.light_color = Color(1.0, 0.86, 0.68)
	key.light_energy = 1.05
	key.shadow_enabled = true
	key.shadow_blur = 1.5
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = 14.0
	add_child(key)
	# cool moonlight through the window
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-25, 168, 0)
	moon.light_color = Color(0.55, 0.68, 1.0)
	moon.light_energy = 0.4
	add_child(moon)
	_lamp = OmniLight3D.new()
	_lamp.position = Vector3(3.9, 1.75, -1.9)
	_lamp.light_color = Color(1.0, 0.76, 0.5)
	_lamp.light_energy = 1.9
	_lamp.omni_range = 7.5
	_lamp.omni_attenuation = 1.4
	add_child(_lamp)
	var lamp2 := OmniLight3D.new()
	lamp2.position = Vector3(-1.9, 0.75, -2.1)
	lamp2.light_color = Color(1.0, 0.72, 0.45)
	lamp2.light_energy = 0.9
	lamp2.omni_range = 4.0
	lamp2.omni_attenuation = 1.6
	add_child(lamp2)

	var k := MeshKit.new()
	var wood := Color("8a5a3c", WOOD)
	var wood_d := Color("6e4630", WOOD)
	var wall := Color("3a4a6b", PAPER)
	var wall_lo := Color("2f3d5a")
	# floor planks (grain, seams and staggered ends come from the dorm shader)
	# (the room is larger than any framing needs: the wide iPad 4:3 lobby
	# framing pulls the camera back, and must never see past the walls)
	for i in 32:
		var x := -12.0 + 0.75 * float(i) + 0.375
		k.box(Vector3(x, -0.05, 4.0), Vector3(0.75, 0.1, 18.0), Color(wood.lightened(0.03 * float(i % 3)) if i % 2 == 0 else wood.darkened(0.05), WOOD))
	# walls (back + left), skirting, window
	k.box(Vector3(0, 3.5, -3.6), Vector3(24.4, 7.2, 0.25), wall)
	k.box(Vector3(0, 0.6, -3.46), Vector3(24.4, 1.2, 0.05), wall_lo)
	k.box(Vector3(0, 1.21, -3.43), Vector3(24.4, 0.06, 0.08), Color("c9b48a"))
	k.box(Vector3(0, 4.42, -3.45), Vector3(24.4, 0.1, 0.1), Color("c9b48a"))     # picture rail
	k.box(Vector3(-6.1, 3.5, 4.0), Vector3(0.25, 7.2, 16.0), Color(wall.darkened(0.08), PAPER))
	k.box(Vector3(-5.96, 0.6, 4.0), Vector3(0.05, 1.2, 16.0), wall_lo.darkened(0.08))
	# window: frame, night sky panes, moon, distant lit windows
	var wx := -0.4
	k.box(Vector3(wx, 2.35, -3.46), Vector3(3.4, 2.1, 0.06), Color("1a2846"), 0.0, 0.0)
	for gx in [-0.85, 0.85]:
		for gy in [-0.5, 0.5]:
			k.box(Vector3(wx + gx, 2.35 + gy, -3.44), Vector3(1.6, 0.95, 0.02), Color("22365e"), 0.0, 0.5)
	k.blob(Vector3(wx + 1.0, 2.85, -3.42), Vector3(0.19, 0.19, 0.012), Color("fff3cf"), 8, 22, 3.0)
	for i in 9:
		var lx := wx - 1.4 + 0.33 * float(i)
		k.box(Vector3(lx, 1.62 + 0.12 * float(i % 3), -3.425), Vector3(0.09, 0.07, 0.01), Color("ffd27a"), 0.0, 2.2)
	k.box(Vector3(wx, 2.35, -3.40), Vector3(3.5, 0.08, 0.1), Color("e9e2d2"))
	k.box(Vector3(wx, 2.35, -3.40), Vector3(0.08, 2.2, 0.1), Color("e9e2d2"))
	k.box(Vector3(wx, 1.27, -3.36), Vector3(3.7, 0.08, 0.22), Color("e9e2d2"))
	k.box(Vector3(wx, 3.43, -3.40), Vector3(3.6, 0.1, 0.12), Color("e9e2d2"))
	# curtains
	for side in [-1.0, 1.0]:
		k.box(Vector3(wx + side * 1.95, 2.3, -3.32), Vector3(0.42, 2.5, 0.08), Color("b84d5e", FABRIC))
	# rug (round, layered)
	k.ellipse_disc(Vector3(0.1, 0.012, 0.25), 3.1, 2.1, Color("2f8f88", FABRIC), 40)
	k.ellipse_disc(Vector3(0.1, 0.018, 0.25), 2.75, 1.8, Color("f1d9a6", FABRIC), 40)
	k.ellipse_disc(Vector3(0.1, 0.024, 0.25), 2.3, 1.45, Color("3aa39b", FABRIC), 40)
	# couch along the back-left
	var cc := Color("5b6fb3", FABRIC)
	k.box(Vector3(-3.6, 0.28, -2.75), Vector3(3.0, 0.42, 1.05), cc.darkened(0.1))
	k.box(Vector3(-3.6, 0.58, -2.6), Vector3(2.7, 0.2, 0.85), cc)
	k.box(Vector3(-3.6, 0.95, -3.18), Vector3(3.0, 0.75, 0.32), cc.darkened(0.05))
	for sx in [-1.0, 1.0]:
		k.box(Vector3(-3.6 + sx * 1.42, 0.68, -2.72), Vector3(0.28, 0.5, 1.05), cc.darkened(0.12))
	k.box(Vector3(-4.2, 0.82, -2.75), Vector3(0.62, 0.38, 0.22), Color("ffc668", FABRIC), 0.25)
	k.box(Vector3(-3.0, 0.82, -2.75), Vector3(0.58, 0.36, 0.2), Color("6fd8cc", FABRIC), -0.2)
	# floor lamp + warm shade
	k.cylinder(Vector3(3.9, 0.0, -1.9), 0.25, 0.04, Color("2a2d36"), 12)
	k.cylinder(Vector3(3.9, 0.0, -1.9), 0.035, 1.55, Color("2a2d36"), 8)
	k.cylinder(Vector3(3.9, 1.5, -1.9), 0.36, 0.42, Color("ffd9a0"), 14, 1.4, true, 0.22)
	# bookshelf on the right
	k.box(Vector3(5.1, 1.05, -2.9), Vector3(1.5, 2.1, 0.5), wood_d)
	for sh in 4:
		var y := 0.25 + 0.5 * float(sh)
		k.box(Vector3(5.1, y, -2.7), Vector3(1.4, 0.04, 0.42), wood)
		for b in 6:
			var bh := 0.26 + 0.05 * float((b * 7 + sh * 3) % 4)
			k.box(Vector3(4.55 + 0.2 * float(b), y + bh * 0.5 + 0.02, -2.72), Vector3(0.15, bh, 0.3),
				[Color("e46a5e"), Color("f1c75b"), Color("6fd8cc"), Color("9a7bd8"), Color("f4f2ec")][(b + sh) % 5])
	# plant, beanbag, side table + pizza box, posters, string lights
	k.cylinder(Vector3(-5.3, 0, 1.6), 0.28, 0.5, Color("c27a4f", GLOSS), 10, 0.0, true, 0.34)
	k.blob(Vector3(-5.3, 0.95, 1.6), Vector3(0.55, 0.6, 0.55), Color("4f9a5c"), 4, 9)
	k.blob(Vector3(4.0, 0.32, 1.1), Vector3(0.75, 0.38, 0.7), Color("ff8f6b", FABRIC), 4, 12)
	k.box(Vector3(-1.9, 0.28, -2.1), Vector3(0.8, 0.04, 0.55), wood)
	k.box(Vector3(-1.9, 0.14, -2.1), Vector3(0.7, 0.28, 0.45), wood_d)
	k.box(Vector3(-1.9, 0.33, -2.1), Vector3(0.45, 0.06, 0.45), Color("f4f2ec"), 0.3)
	k.cylinder(Vector3(-2.1, 0.3, -2.2), 0.08, 0.28, Color("e9e2d2", GLOSS), 10)
	k.cylinder(Vector3(-2.1, 0.56, -2.2), 0.16, 0.2, Color("ffd9a0"), 12, 1.3, true, 0.1)
	k.box(Vector3(2.4, 2.45, -3.45), Vector3(0.9, 1.2, 0.03), Color("ffc668", GLOSS), 0.0, 0.0)
	k.blob(Vector3(2.4, 2.62, -3.43), Vector3(0.24, 0.24, 0.01), Color("6fd8cc"), 6, 20)
	k.box(Vector3(2.4, 2.1, -3.43), Vector3(0.62, 0.08, 0.01), Color("11192b"))
	k.box(Vector3(2.4, 1.98, -3.43), Vector3(0.44, 0.05, 0.01), Color("11192b"))
	k.box(Vector3(-2.9, 2.5, -3.45), Vector3(0.8, 1.05, 0.03), Color("6fd8cc"))
	k.box(Vector3(-2.9, 2.5, -3.43), Vector3(0.5, 0.65, 0.01), Color("f4f2ec"))
	for i in 22:
		var x := -5.6 + 0.52 * float(i)
		k.blob(Vector3(x, 3.95 - 0.16 * absf(sin(float(i) * 0.8)), -3.38), Vector3(0.05, 0.06, 0.05),
			[Color("ffc668"), Color("ff8f8f"), Color("6fd8cc")][i % 3], 2, 5, 2.4)
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit()
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/shaders/dorm.gdshader")
	mi.material_override = m
	add_child(mi)
