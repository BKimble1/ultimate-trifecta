extends RefCounted
## V5 startup and branding: Idlery Games at launch (the iOS launch screen,
## Godot's boot splash and the boot curtain show one composition), a curtain
## that leaves on readiness rather than a frame count, and the raster brand
## marks imported cleanly with accessibility names.
var t


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


## Bounding box of the pixels that differ from `bg` (by more than `tol`).
func _bbox(img: Image, bg: Color, tol: float = 0.08) -> Rect2i:
	var x0 := img.get_width()
	var y0 := img.get_height()
	var x1 := -1
	var y1 := -1
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			if absf(c.r - bg.r) + absf(c.g - bg.g) + absf(c.b - bg.b) > tol:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	return Rect2i(x0, y0, x1 - x0, y1 - y0)


func test_launch_image_boot_splash_and_curtain_agree() -> void:
	t.eq(ProjectSettings.get_setting("application/boot_splash/image"), "res://assets/icon/launch.png", "boot splash shows the launch image")
	var bg: Color = ProjectSettings.get_setting("application/boot_splash/bg_color")
	t.check(bg.is_equal_approx(Brand.STARTUP_BG), "boot splash background is the startup navy")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	t.check(preset.contains('storyboard/custom_image@3x="res://assets/icon/launch.png"') and preset.contains('storyboard/custom_image@2x="res://assets/icon/launch.png"'),
		"the iOS launch storyboard uses the same image")
	t.check(preset.contains("storyboard/custom_bg_color=Color(0.047058824, 0.07450981, 0.14117648, 1)"), "and the same navy (no white flash)")
	t.check(preset.contains("storyboard/image_scale_mode=2"), "scaled to fit, like the boot splash")
	var launch := (load("res://assets/icon/launch.png") as Texture2D).get_image()
	t.eq(launch.get_width(), launch.get_height(), "the launch image is square (fitted to the screen height)")
	t.check(not launch.detect_alpha(), "opaque: no checkerboard or see-through launch")
	var corner := launch.get_pixel(4, 4)
	t.check(absf(corner.r - Brand.STARTUP_BG.r) + absf(corner.g - Brand.STARTUP_BG.g) + absf(corner.b - Brand.STARTUP_BG.b) < 0.02, "its background is the startup navy")
	# where the lockup sits in the launch image = where the curtain draws it
	var lock := (load(Brand.STUDIO) as Texture2D).get_image()
	lock.decompress()
	var side := float(launch.get_width())
	var r := Brand.lockup_rect(Vector2(side, side), Vector2(lock.get_size()))
	var used := lock.get_used_rect()
	var k := r.size.x / float(lock.get_width())
	var expect := Rect2(r.position + Vector2(used.position) * k, Vector2(used.size) * k)
	var got := _bbox(launch, Brand.STARTUP_BG)
	t.check(absf(got.position.x - expect.position.x) < 6.0 and absf(got.position.y - expect.position.y) < 6.0
		and absf(got.size.x - expect.size.x) < 8.0 and absf(got.size.y - expect.size.y) < 8.0,
		"launch image lockup %s matches the curtain's placement %s" % [str(got), str(expect)])


func test_curtain_waits_for_readiness_not_frames() -> void:
	t.check(BootCurtain.steady(0.016, 0.016), "a normal frame is steady")
	t.check(not BootCurtain.steady(0.4, 0.016), "a compile stall is not")
	t.check(BootCurtain.steady(0.15, 0.16), "a steadily slow device is steady")
	var saved_screen: Variant = App.screen
	var saved_stage := App.stage
	App.screen = null
	App.stage = null
	var c := BootCurtain.new()
	t.add_child(c)
	await _frames(12)
	t.check(is_instance_valid(c) and not c._leaving, "no screen yet: the curtain stays (V4 left after 6 frames)")
	t.check(c.logo.texture != null and c.logo.accessibility_name == "Idlery Games", "the Idlery Games lockup, with an accessibility name")
	t.check(c.bg.mouse_filter == Control.MOUSE_FILTER_STOP, "taps are held while it is up")
	var scr := Control.new()
	t.add_child(scr)
	App.screen = scr
	c._t = BootCurtain.MIN_HOLD_S
	await _frames(BootCurtain.STABLE_FRAMES + 2)
	t.check(c._leaving and c.reason == "ready", "leaves once the screen is ready and frames are steady")
	t.eq(c.bg.mouse_filter, Control.MOUSE_FILTER_IGNORE, "and lets taps through as it fades")
	await _frames(40)
	t.check(not is_instance_valid(c), "then frees itself")
	App.screen = saved_screen
	App.stage = saved_stage
	scr.queue_free()


func test_brand_marks_import_cleanly() -> void:
	for spec in [[Brand.TITLE, 1440, 480, "Ultimate Trifecta"], [Brand.STUDIO, 1400, 805, "Idlery Games"]]:
		var tex := load(String(spec[0])) as Texture2D
		t.check(tex != null, "%s loads" % spec[0])
		if tex == null:
			continue
		t.eq(Vector2i(tex.get_size()), Vector2i(int(spec[1]), int(spec[2])), "%s runtime size (proportional to the master)" % spec[0])
		var img := tex.get_image()
		t.check(img.has_mipmaps(), "%s has mipmaps (crisp when drawn small)" % spec[0])
		img.decompress()
		t.check(img.detect_alpha() != Image.ALPHA_NONE, "%s keeps its transparency" % spec[0])
		t.eq(img.get_pixel(1, 1).a, 0.0, "%s: transparent padding, no opaque box or checkerboard" % spec[0])
	var title := Brand.title(400.0)
	t.eq(title.accessibility_name, "Ultimate Trifecta", "title graphic has an accessibility name")
	t.eq(title.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "never stretched or cropped")
	t.check(absf(title.custom_minimum_size.y - 400.0 / 3.0) < 1.0, "height follows the art (3:1 with its padding)")
	title.free()


func test_no_unwanted_branding_copy() -> void:
	# the requested wording is "Idlery Games" at startup; nothing says
	# "powered by" anywhere in the game's own scripts or scenes
	var hits: Array[String] = []
	for dir in ["res://src/ui", "res://src/view", "res://src/autoload", "res://src/match", "res://src/map"]:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".gd") or f.ends_with(".tscn"):
				var txt := FileAccess.get_file_as_string(dir.path_join(f)).to_lower()
				if txt.contains("powered" + " by"):
					hits.append(f)
	t.eq(hits, [] as Array[String], "no 'powered by' copy")
