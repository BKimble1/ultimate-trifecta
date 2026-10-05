extends Node
## Development-only (src/dev is excluded from exports): Pass 8 startup-logo
## evidence, driven from capture.gd for --capture=logo_*.  Lossless PNGs of
## the window at its native pixel size (viewport readback; dev tools only).
##
##   logo_startup   the real boot (main scene, App's own BootCurtain over the
##                  title): every drawn frame from the first until the curtain
##                  has been gone for 8 frames, cropped to the lockup (+16 px);
##                  full frames at the stage changes; timeline.json with the
##                  curtain's state per frame.  Run with --fixed-fps 60 so the
##                  curtain's clock is the frame count (llvmpipe is slow).
##   logo_variants  (run with --no-app) the lockup drawn several ways on the
##                  startup black at the window size, one full frame each:
##                    boot_<name>   a launch PNG as Godot's boot splash draws
##                                  it (window-height square, linear, no mips)
##                    v8_curtain    V8's curtain: the given 1400-px PNG
##                                  (--old-png) in a TextureRect at the lockup
##                                  rect, imported like V8 (alpha border fix,
##                                  mipmaps), linear-with-mipmaps
##                    v8_png_linear the same, linear filter (no mipmaps)
##                    v8_png_unsnapped  the V8 texture and filter in a BrandMark
##                                  (position not rounded to canvas units)
##                    fallback      Pass 8 fallback: the new PNG, mipmapped,
##                                  BrandMark
##                    curtain       the real Pass 8 BootCurtain (no App)
##                  Args: --launch=name:path[,name:path] --old-png=path

var cap: Node
var scenario := ""
var _frame := 0
var _timeline: Array = []
var _gone_at := -1
var _lock_px := Rect2i()
var _full_saved: Dictionary = {}
var _layer: CanvasLayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if scenario == "logo_variants":
		_variants.call_deferred()
	else:
		_startup.call_deferred()


func _out(file: String) -> String:
	return String(cap.get("out_dir")).path_join(file)


func _window_lockup() -> Rect2:
	var vp := get_viewport()
	var win := vp.get_final_transform().basis_xform(vp.get_visible_rect().size)
	return Brand.lockup_rect(win, Brand.svg_size(Brand.studio_svg()))


func _curtain() -> BootCurtain:
	for c in get_tree().root.get_children():
		if c is BootCurtain:
			return c
	return null


func _startup() -> void:
	var r := _window_lockup()
	_lock_px = Rect2i(Vector2i(r.position.floor()) - Vector2i(16, 16), Vector2i(r.size.ceil()) + Vector2i(33, 33))
	while _frame < 900:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var c := _curtain()
		var row := {"frame": _frame, "t": snappedf(float(_frame) / float(Engine.physics_ticks_per_second), 0.001)}
		if c != null and is_instance_valid(c):
			row["curtain"] = true
			row["exact"] = c.exact
			row["leaving"] = c._leaving
			row["logo_alpha"] = snappedf(c.logo.fade, 0.001)
			row["settle"] = snappedf(c.logo.settle, 0.0001)
			row["bg_alpha"] = snappedf(c.bg.modulate.a, 0.001)
			row["reason"] = c.reason
		else:
			row["curtain"] = false
			if _gone_at < 0:
				_gone_at = _frame
		row["screen"] = App.screen.get_class() if App.screen != null and is_instance_valid(App.screen) else ""
		if App.screen != null and is_instance_valid(App.screen) and App.screen.get_script() != null:
			row["screen"] = String((App.screen.get_script() as Script).get_global_name())
		_timeline.append(row)
		img.get_region(_lock_px).save_png(_out("crop_%03d.png" % _frame))
		var key := ""
		if _frame == 0:
			key = "first"
		elif row.get("leaving", false) and not _full_saved.has("leave"):
			key = "leave"
		elif row.get("leaving", false) and float(row.get("logo_alpha", 1.0)) <= 0.55 and not _full_saved.has("mid"):
			key = "mid"
		elif _gone_at == _frame:
			key = "gone"
		if key != "":
			_full_saved[key] = _frame
			img.save_png(_out("full_%s_%03d.png" % [key, _frame]))
		_frame += 1
		if _gone_at >= 0 and _frame >= _gone_at + 8:
			break
	var f := FileAccess.open(_out("timeline.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"window": [get_window().size.x, get_window().size.y],
		"lockup_px": [r.position.x, r.position.y, r.size.x, r.size.y],
		"crop": [_lock_px.position.x, _lock_px.position.y, _lock_px.size.x, _lock_px.size.y],
		"full": _full_saved, "frames": _timeline}, "  "))
	f.close()
	printerr("LOGO startup frames %d (curtain gone at %d) -> %s" % [_frame, _gone_at, String(cap.get("out_dir"))])
	get_tree().quit()


func _black_layer() -> void:
	if _layer != null:
		_layer.queue_free()
	_layer = CanvasLayer.new()
	_layer.layer = 100
	get_tree().root.add_child(_layer)
	var bg := ColorRect.new()
	bg.color = Brand.STARTUP_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(bg)


func _png(path: String, v8_import: bool) -> ImageTexture:
	var img := Image.load_from_file(path)
	if img == null:
		return null
	if v8_import:
		img.convert(Image.FORMAT_RGBA8)
		img.fix_alpha_edges()       # process/fix_alpha_border=true
		img.generate_mipmaps()      # mipmaps/generate=true
	return ImageTexture.create_from_image(img)


func _snap(name: String) -> void:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out("%s.png" % name))
	printerr("LOGO variant %s" % name)


func _variants() -> void:
	var launches: Array = []
	var old_png := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--launch="):
			for spec in a.get_slice("=", 1).split(","):
				launches.append([spec.get_slice(":", 0), spec.substr(spec.find(":") + 1)])
		elif a.begins_with("--old-png="):
			old_png = a.get_slice("=", 1)
	var vp := get_viewport()
	var win_r := _window_lockup()
	var inv := vp.get_final_transform().affine_inverse()
	var canvas_r := Rect2(inv * win_r.position, inv.basis_xform(win_r.size))
	for l in launches:
		_black_layer()
		var t := TextureRect.new()
		t.texture = _png(String(l[1]), false)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		t.set_anchors_preset(Control.PRESET_FULL_RECT)
		_layer.add_child(t)
		await _snap("boot_%s" % l[0])
	if old_png != "":
		for spec in [["v8_curtain", CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS], ["v8_png_linear", CanvasItem.TEXTURE_FILTER_LINEAR]]:
			_black_layer()
			var tr := TextureRect.new()
			tr.texture = _png(old_png, true)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.texture_filter = spec[1]
			# V8's layout: Brand.lockup_rect in canvas units
			var r := Brand.lockup_rect(vp.get_visible_rect().size, Vector2(tr.texture.get_size()))
			tr.position = r.position
			tr.size = r.size
			_layer.add_child(tr)
			await _snap(String(spec[0]))
		_black_layer()
		var m := BrandMark.new()
		m.texture = _png(old_png, true)
		m.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		m.picture_rect = canvas_r
		_layer.add_child(m)
		await _snap("v8_png_unsnapped")
	_black_layer()
	var fb := Brand.studio()
	_layer.add_child(fb)
	Brand.place_studio(fb, vp, "-")   # an unreadable source: the fallback path
	await _snap("fallback")
	_layer.queue_free()
	_layer = null
	var c := BootCurtain.new()
	get_tree().root.add_child(c)
	await _snap("curtain")
	printerr("LOGO variants exact=%s -> %s" % [str(c.exact), String(cap.get("out_dir"))])
	get_tree().quit()
