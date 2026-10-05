extends RefCounted
## V5 startup and branding: Idlery Games at launch (the iOS launch screen,
## Godot's boot splash and the boot curtain show one composition), a curtain
## that leaves on readiness rather than a frame count, and the raster brand
## marks imported cleanly with accessibility names.
## Pass 8: clean logo edges through the startup path - the launch image and
## the curtain's lockup are rasterised from the same vector at the size they
## are shown at (no ringing halo, no fringe colour, an antialiased contour),
## the curtain puts it on the launch image's pixels (no jump at the
## handoff), and the fallback PNG mipmaps without misregistration.
var t
const FILLS := [Color8(57, 165, 171), Color8(229, 235, 245)]   # teal mark, ivory "GAMES"


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
	t.check(bg.is_equal_approx(Brand.STARTUP_BG), "boot splash background is the startup black (V6)")
	t.eq(Brand.STARTUP_BG, Color(0, 0, 0, 1), "the startup background is pure black #000000 (owner request, V6)")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	t.check(preset.contains('storyboard/custom_image@3x="res://assets/icon/launch.png"') and preset.contains('storyboard/custom_image@2x="res://assets/icon/launch.png"'),
		"the iOS launch storyboard uses the same image")
	t.check(preset.contains("storyboard/custom_bg_color=Color(0, 0, 0, 1)"), "and the same black (no white flash, no navy rectangle)")
	t.check(preset.contains("storyboard/image_scale_mode=2"), "scaled to fit, like the boot splash")
	var launch := _launch()
	t.eq(launch.get_width(), launch.get_height(), "the launch image is square (fitted to the screen height)")
	t.check(not launch.detect_alpha(), "opaque: no checkerboard or see-through launch")
	var corner := launch.get_pixel(4, 4)
	t.check(absf(corner.r - Brand.STARTUP_BG.r) + absf(corner.g - Brand.STARTUP_BG.g) + absf(corner.b - Brand.STARTUP_BG.b) < 0.02, "its background is the startup black")
	# its size against the screens it is minified onto with one bilinear tap
	# (Core Animation's default filter; Godot's boot splash sampler, no mips):
	# never upscaled on an iPhone, never past ~2.2:1 where the tap skips texels
	var side := float(launch.get_width())
	for h in [750, 828, 1125, 1170, 1179, 1206, 1242, 1284, 1290, 1320]:
		t.check(side / float(h) >= 1.0 and side / float(h) <= 2.25, "launch %d px on a %d-px-high iPhone: ratio %.2f" % [int(side), h, side / float(h)])
	# where the lockup sits in the launch image = where the curtain draws it
	var svg := Brand.studio_svg()
	var r := Brand.lockup_rect(Vector2(side, side), Brand.svg_size(svg))
	var lock := Brand.studio_raster(svg, r)
	t.check(lock != null, "the lockup rasterises from its vector at the launch image's size")
	if lock == null:
		return
	var o := Vector2(r.position.floor())
	var used := lock.get_used_rect()
	var expect := Rect2(o + Vector2(used.position), Vector2(used.size))
	var got := _bbox(launch, Brand.STARTUP_BG)
	t.check(absf(got.position.x - expect.position.x) <= 2.0 and absf(got.position.y - expect.position.y) <= 2.0
		and absf(got.size.x - expect.size.x) <= 3.0 and absf(got.size.y - expect.size.y) <= 3.0,
		"launch image lockup %s matches the curtain's placement %s" % [str(got), str(expect)])


func _launch() -> Image:
	var img := (load("res://assets/icon/launch.png") as Texture2D).get_image()
	img.decompress()
	return img


## Coverage of one pixel of the lockup on black: (fill index, coverage,
## colour error) - the pixel as the best blend t * fill.
func _blend(c: Color) -> Vector3:
	var best := Vector3(-1, 0, 99)
	for i in FILLS.size():
		var f: Color = FILLS[i]
		var tt := clampf((c.r * f.r + c.g * f.g + c.b * f.b) / (f.r * f.r + f.g * f.g + f.b * f.b), 0.0, 1.0)
		var err := maxf(absf(c.r - tt * f.r), maxf(absf(c.g - tt * f.g), absf(c.b - tt * f.b))) * 255.0
		if err < best.z:
			best = Vector3(i, tt, err)
	return best


func test_launch_image_edges_are_antialiased_without_halo() -> void:
	# The launch image is what the native launch screen and the boot splash
	# show: each edge pixel must be a blend of black and one fill colour (no
	# light or tinted fringe), partly covered pixels must sit on the contour
	# (a neighbour with more ink and, inside, one with less: no detached glow
	# ring or dark dip from a ringing resize), and the contour must be
	# antialiased (few direct background-to-fill steps).  Rows through the
	# middle of the mark and through "GAMES".
	var launch := _launch()
	var box := _bbox(launch, Brand.STARTUP_BG, 0.03)
	var worst := 0.0
	var partial := 0
	var detached := 0
	var crossings := 0
	var hard := 0
	var rows := []
	for k in 24:
		rows.append(box.position.y + 2 + int(float(box.size.y - 4) * float(k) / 23.0))
	for y in rows:
		var prev := -1.0
		var prev_cls := -1
		var prev_i := -1
		for x in range(box.position.x - 4, box.end.x + 5):
			var b := _blend(launch.get_pixel(x, y))
			var tt := b.y if b.x >= 0 else 0.0
			if launch.get_pixel(x, y).r8 + launch.get_pixel(x, y).g8 + launch.get_pixel(x, y).b8 > 0:
				worst = maxf(worst, b.z)
			if tt > 2.0 / 255.0 and tt < 0.99:
				partial += 1
				var hi := 0.0
				var lo := 1.0
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						if dx != 0 or dy != 0:
							var n := _blend(launch.get_pixel(x + dx, y + dy)).y
							hi = maxf(hi, n)
							lo = minf(lo, n)
				if (tt < 0.5 and hi <= tt + 1.0 / 255.0) or (tt >= 0.5 and lo >= tt - 1.0 / 255.0):
					detached += 1
			var cls := 0 if tt <= 0.06 else (1 if tt >= 0.94 else -1)
			if cls >= 0:
				if prev_cls >= 0 and cls != prev_cls:
					crossings += 1
					if x - prev_i == 1:
						hard += 1
				prev_cls = cls
				prev_i = x
			prev = tt
	t.check(worst <= 4.0, "every lit pixel is black blended with one fill colour (worst %.1f levels)" % worst)
	t.check(partial > 200, "partly covered contour pixels: %d (antialiased)" % partial)
	t.eq(detached, 0, "no detached glow or inner dip (ringing halo)")
	t.check(crossings > 100 and float(hard) / float(crossings) < 0.15,
		"contour crossings %d, direct background-to-fill steps %d (aliased edges would be ~half)" % [crossings, hard])


func test_curtain_lockup_lands_on_the_launch_image_pixels() -> void:
	# On a 2532 x 1170 phone the canvas is 1558 x 720 units: the lockup's
	# picture goes on whole device pixels with its texels 1:1, and that
	# picture is the launch image's lockup at this size (same vector, same
	# geometry), so the boot splash -> curtain handoff doesn't move it
	var root: Window = t.get_tree().root
	var saved_size: Vector2i = root.size
	root.size = Vector2i(2532, 1170)
	await t.get_tree().process_frame
	var vp: Viewport = root
	var xf := vp.get_final_transform()
	var mark := Brand.studio()
	t.add_child(mark)
	t.check(Brand.place_studio(mark, vp), "the curtain's lockup is the exact vector raster (not the fallback)")
	t.eq(mark.accessibility_name, "Idlery Games", "with its accessibility name")
	t.eq(mark.position, Vector2.ZERO, "the BrandMark itself stays at the origin (nothing for control snapping to round)")
	var win := xf.basis_xform(vp.get_visible_rect().size)
	t.near(win.x, 2532.0, 0.01, "window width in pixels")
	var want := Brand.lockup_rect(win, Brand.svg_size(Brand.studio_svg()))
	t.near(want.size.x, 1170.0 * Brand.LOCKUP_W, 0.01, "the lockup is 0.62 of the screen height, as in the launch image")
	var at := xf * mark.picture_rect.position
	var px := xf.basis_xform(mark.picture_rect.size)
	t.check(at.distance_to(at.round()) < 0.001 and at.round() == want.position.floor(),
		"the picture starts on a whole device pixel %s (lockup at %s)" % [str(at), str(want.position)])
	t.check(px.distance_to(Vector2(mark.texture.get_size())) < 0.001, "texels map 1:1 to device pixels: %s for a %s texture" % [str(px), str(mark.texture.get_size())])
	t.eq(mark.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR, "drawn 1:1 with a plain linear filter (no mip level choice)")
	t.check(mark.premultiplied and mark.material is CanvasItemMaterial
		and (mark.material as CanvasItemMaterial).blend_mode == CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA,
		"a premultiplied texture drawn with the premultiplied blend")
	# the raster is the launch image's lockup at this size: compare it with
	# the launch image rasterised for a 1170-px-high square (same geometry)
	var img := (mark.texture as ImageTexture).get_image()
	var ink := 0.0
	var cx := 0.0
	var cy := 0.0
	var bad_colour := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			ink += c.a
			cx += c.a * x
			cy += c.a * y
			# premultiplied: colour = fill x coverage (within 2.5 levels)
			var b := _blend(Color(c.r, c.g, c.b))
			if b.z > 2.5 or absf(b.y - c.a) * 255.0 > 2.5:
				bad_colour += 1
	t.eq(bad_colour, 0, "edge pixels hold the fill colour x coverage (no dark or light edge colour)")
	t.check(img.get_pixel(0, 0).a == 0.0 and img.get_pixel(img.get_width() - 1, img.get_height() - 1).a == 0.0, "transparent corners: no matte rectangle")
	var f := want.position - want.position.floor()
	var vb := Brand.svg_size(Brand.studio_svg())
	var k := want.size.x / vb.x
	# centroid of the vector's ink, from the 1.5x owner raster's alpha
	var master := Image.load_from_file(ProjectSettings.globalize_path("res://").path_join("../art_src/branding/idlery-games.png"))
	if master == null:
		t.check(true, "(art_src not available: centroid check skipped)")
	else:
		var mi := 0.0
		var mx := 0.0
		var my := 0.0
		for y in range(0, master.get_height(), 2):
			for x in range(0, master.get_width(), 2):
				var a := master.get_pixel(x, y).a
				mi += a
				mx += a * (x + 0.5)
				my += a * (y + 0.5)
		var s := k * vb.x / float(master.get_width())
		var expect := f + Vector2(mx / mi, my / mi) * s - Vector2(0.5, 0.5)
		var got := Vector2(cx / ink, cy / ink)
		t.check(got.distance_to(expect) < 0.25, "ink centroid %s where the vector puts it %s (sub-pixel)" % [str(got), str(expect)])
		t.near(ink / (mi * 4.0 * s * s), 1.0, 0.02, "ink area matches the vector's at this size")
	mark.queue_free()
	root.size = saved_size
	await t.get_tree().process_frame


func test_fallback_png_and_vector_source() -> void:
	# the shipped vector is the owner's editable master, byte for byte
	var shipped := FileAccess.get_file_as_bytes(Brand.STUDIO_SVG)
	var src := ProjectSettings.globalize_path("res://").path_join("../art_src/branding/idlery-games.svg")
	if FileAccess.file_exists(src):
		t.check(shipped == FileAccess.get_file_as_bytes(src), "assets/branding/idlery_games.svg is art_src/branding/idlery-games.svg")
	t.check(FileAccess.get_file_as_string(Brand.STUDIO_SVG + ".import").contains('importer="keep"'), "the vector ships as-is (import: keep)")
	t.eq(Brand.svg_size(Brand.studio_svg()), Vector2(1600, 920), "the lockup canvas is 1600 x 920")
	# without a readable vector the curtain still shows the lockup (PNG)
	var mark := Brand.studio()
	t.add_child(mark)
	t.check(not Brand.place_studio(mark, t.get_tree().root as Window, "-"), "an unreadable vector falls back to the PNG")
	t.check(mark.texture != null and mark.texture.get_size() == Vector2(1280, 736), "the 1280 x 736 fallback raster")
	t.eq(mark.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "drawn mipmapped")
	t.check(not mark.premultiplied and mark.material == null, "straight alpha (its import fixes the alpha border), ordinary blend")
	var view: Vector2 = (t.get_tree().root as Window).get_visible_rect().size
	var r := Brand.lockup_rect(view, Vector2(1280, 736))
	t.check(mark.picture_rect.position.distance_to(r.position) < 0.01 and mark.picture_rect.size.distance_to(r.size) < 0.01, "at the same rect")
	mark.queue_free()


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
	t.check(c.exact, "rasterised from the vector for this screen")
	t.check(c.bg.mouse_filter == Control.MOUSE_FILTER_STOP, "taps are held while it is up")
	var scr := Control.new()
	t.add_child(scr)
	App.screen = scr
	c._t = BootCurtain.MIN_HOLD_S
	await _frames(BootCurtain.STABLE_FRAMES + 2)
	t.check(c._leaving and c.reason == "ready", "leaves once the screen is ready and frames are steady")
	t.eq(c.bg.mouse_filter, Control.MOUSE_FILTER_IGNORE, "and lets taps through as it fades")
	await _frames(8)
	t.check(c.logo.fade < 1.0 and c.logo.modulate.a == 1.0, "the lockup fades through BrandMark.fade (%.2f), all channels together" % c.logo.fade)
	if not UIKit.reduced_motion():
		t.check(c.logo.settle > 1.0 and c.logo.position == Vector2.ZERO, "the settle scales the picture in its draw call (%.3f), not the snapped control" % c.logo.settle)
	await _frames(32)
	t.check(not is_instance_valid(c), "then frees itself")
	App.screen = saved_screen
	App.stage = saved_stage
	scr.queue_free()


func test_reduced_motion_exit_is_a_plain_fade() -> void:
	var saved_rm: Variant = Save.get_setting("reduced_motion", false)
	Save.set_setting("reduced_motion", true)
	var saved_screen: Variant = App.screen
	var saved_stage := App.stage
	App.stage = null
	var scr := Control.new()
	t.add_child(scr)
	App.screen = scr
	var c := BootCurtain.new()
	t.add_child(c)
	c._t = BootCurtain.MIN_HOLD_S
	await _frames(BootCurtain.STABLE_FRAMES + 2)
	t.check(c._leaving, "leaves on readiness")
	await _frames(4)
	if is_instance_valid(c):
		t.eq(c.logo.settle, 1.0, "Reduced Motion: no settle, the lockup only fades")
		t.check(c.logo.fade < 1.0, "fading (%.2f)" % c.logo.fade)
	await _frames(20)
	t.check(not is_instance_valid(c), "and the curtain is gone after the short fade")
	Save.set_setting("reduced_motion", saved_rm)
	App.screen = saved_screen
	App.stage = saved_stage
	scr.queue_free()


func test_brand_marks_import_cleanly() -> void:
	for spec in [[Brand.TITLE, 1440, 480, "Ultimate Trifecta"], [Brand.STUDIO, 1280, 736, "Idlery Games"]]:
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
	# the fallback lockup's mip chain halves exactly (both sides divide by 32:
	# V5's 805 rows halved to 402 and its mips sat up to half a texel low)
	var st := (load(Brand.STUDIO) as Texture2D).get_size()
	t.check(int(st.x) % 32 == 0 and int(st.y) % 32 == 0, "fallback lockup %s halves exactly through 5 mip levels" % str(st))
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
