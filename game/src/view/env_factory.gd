class_name EnvFactory
extends RefCounted
## Night lighting: soft blue ambient, moonlight, gentle fog and glow.
## Bright enough to navigate on an iPhone; no heavy post-processing.


static func make_environment(quality: int = 1) -> WorldEnvironment:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://assets/shaders/night_sky.gdshader")
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# V5: a little less saturated, so shade reads moonlit rather than flat
	# blue (the campus shaders add their own soft sky/ground fill)
	env.ambient_light_color = Color(0.40, 0.46, 0.74)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	# restrained depth fog in the horizon's colour: distance reads as layers
	env.fog_light_color = Color(0.16, 0.19, 0.37)
	env.fog_density = 1.0
	env.fog_depth_begin = 60.0
	env.fog_depth_end = 300.0
	env.fog_depth_curve = 1.3
	env.fog_sky_affect = 0.5
	# conservative glow: only genuinely bright things (lamps, lit windows,
	# beacons) bloom; no full-screen haze.  Off in Battery Saver.
	env.glow_enabled = quality >= 1
	env.glow_intensity = 0.45
	env.glow_strength = 0.85
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.04
	we.environment = env
	return we


static func make_moon(quality: int = 1) -> DirectionalLight3D:
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.74, 0.80, 1.0)
	moon.light_energy = 0.75
	moon.rotation_degrees = Vector3(-52, 35, 0)
	# characters always cast (contact shadows read movement); Battery Saver
	# uses a single short split and the campus itself does not cast
	moon.shadow_enabled = true
	# V5: softer contact shadows (less hard blue shade)
	moon.shadow_opacity = 0.5
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if quality >= 1 else DirectionalLight3D.SHADOW_ORTHOGONAL
	moon.directional_shadow_max_distance = 70.0 if quality >= 1 else 30.0
	moon.shadow_blur = 2.2
	return moon
