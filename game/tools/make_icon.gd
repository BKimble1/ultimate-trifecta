extends Node3D
## Renders the app icon (1024x1024, opaque) and the launch image from the
## game's own character + water style. Run with a renderer (not headless):
## godot --path game --resolution 1024x1024 res://tools/make_icon.tscn

var frame := 0
var cam: Camera3D
var mode := "icon"


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.12, 0.34)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.62, 1.0)
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.6
	env.environment = e
	add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, 25, 0)
	key.light_energy = 1.05
	key.light_color = Color(1.0, 0.93, 0.82)
	add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-1.6, 2.4, -1.2)
	rim.light_color = Color(0.4, 0.75, 1.0)
	rim.light_energy = 4.0
	rim.omni_range = 6.0
	add_child(rim)
	# moon
	var moon := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.55
	sm.height = 1.1
	moon.mesh = sm
	moon.material_override = PropKit.mat(Color(1.0, 0.96, 0.8), 0.0, Color.WHITE, 1.4, 0.0)
	moon.position = Vector3(1.55, 2.75, -2.5)
	moon.scale = Vector3(0.6, 0.6, 0.6)
	add_child(moon)
	# stars
	for i in 24:
		var st := MeshInstance3D.new()
		var ss := SphereMesh.new()
		ss.radius = 0.025
		ss.height = 0.05
		st.mesh = ss
		st.material_override = PropKit.mat(Color(1, 1, 1), 0.0, Color.WHITE, 3.0, 0.0)
		var rng := RandomNumberGenerator.new()
		rng.seed = i * 17 + 3
		st.position = Vector3(rng.randf_range(-2.5, 2.5), rng.randf_range(1.6, 3.4), -3.0)
		add_child(st)
	# water disc with splash crown
	var water := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 2.4
	dm.bottom_radius = 2.4
	dm.height = 0.1
	dm.radial_segments = 48
	water.mesh = dm
	var wm := ShaderMaterial.new()
	wm.shader = preload("res://assets/shaders/water.gdshader")
	wm.set_shader_parameter("active", 1.0)
	wm.set_shader_parameter("target_color", Color(0.3, 0.85, 1.0))
	wm.set_shader_parameter("shape_half", Vector2(2.4, 2.4))
	water.material_override = wm
	water.position = Vector3(0, 0.05, 0)
	add_child(water)
	PropKit.init_meshes()
	for i in 22:
		var a := TAU * float(i) / 22.0
		var drop := MeshInstance3D.new()
		drop.mesh = PropKit.sphere
		drop.material_override = PropKit.mat(Color(0.7, 0.92, 1.0), 0.0, Color.WHITE, 0.35)
		var r := 0.95 + 0.12 * float(i % 3)
		drop.position = Vector3(cos(a) * r, 0.12 + 0.22 * float(i % 3) + 0.1 * sin(a * 3.0), sin(a) * r * 0.55)
		var sc := 0.07 + 0.03 * float(i % 2)
		drop.scale = Vector3(sc, sc * 1.6, sc)
		add_child(drop)
	var ringm := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.08
	ringm.mesh = tm
	ringm.material_override = PropKit.mat(Color(0.85, 0.97, 1.0), 0.0, Color.WHITE, 0.6)
	ringm.position = Vector3(0, 0.1, 0)
	ringm.scale = Vector3(1, 0.35, 0.65)
	add_child(ringm)
	# hero character mid-dive into the water
	var v := CharacterView.new()
	add_child(v)
	v.setup(TC.Role.RUNNER, {"outfit": "pj_stripes", "hat": "nightcap", "shoes": "slippers", "color": 0, "skin": 0}, 0, "", false, true)
	v.apply_state({"pos": Vector3(0, 0.25, 0.1), "yaw": PI - 0.28, "state": TC.PState.ACTIVE, "vel": Vector3(0, 0, 0), "on_floor": true, "diving": false, "emote": 1, "emote_t": 1.0}, 0.0, true)
	cam = Camera3D.new()
	cam.fov = 34
	add_child(cam)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, 1.08, 0) - Vector3(0, 1.45, 3.45), Vector3.UP), Vector3(0, 1.45, 3.45))
	if OS.get_cmdline_user_args().has("--splash"):
		mode = "splash"


func _process(_d: float) -> void:
	frame += 1
	if frame == 26:
		var img := get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		if mode == "icon":
			img.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
			img.save_png("res://assets/icon/icon.png")
			print("icon written")
		else:
			img.save_png("res://assets/icon/splash.png")
			print("splash written")
		get_tree().quit()
