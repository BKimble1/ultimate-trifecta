class_name LoadingScreen
extends Screen
## Match loading (V4): the three runners from the owner's clip running in a
## seamless loop on the clip's own blue, with the real state underneath -
## what the round is doing ("Getting campus ready…", "Placing players…"), a
## bar that follows the preparation steps actually completed, and "Waiting
## for players · 3/4 ready" when that is what is happening.  The screen
## fades into the round the moment it is live; it never waits for the loop.
##
## The loop (assets/loading, built by tools/make_loading_loop.py from
## art_src/loading/characters_run.mp4): 19 frames at 24 fps in one grid
## atlas, GPU-compressed (ASTC on iOS), no sound.  Frames rather than a
## video stream: nothing is decoded on the main thread while the round is
## being prepared, and the loop restarts frame-exactly.  The matching still
## (loop frame 0) shows at once while the atlas loads on a background
## thread, and stays if it can't load; Reduced Motion shows only the still.
## Everything is released when the screen closes.
##
## The droplet motif below is no longer drawn here; the boot curtain and the
## launch image (tools/make_launch_art.sh) still use it.

const BG := Color("0c1324")
## layout of the motif in canvas units of a 720-unit-high screen (launch art)
const MOTIF_Y := 0.40
const WORDMARK_Y := 0.585
const LOOP_S := 2.6

const LOOP_ATLAS := "res://assets/loading/run_loop_atlas.jpg"
const LOOP_STILL := "res://assets/loading/run_still.jpg"
## Written by tools/make_loading_loop.py (run_loop.json; test_loading_screen
## checks they agree).
const LOOP_FRAMES := 19
const LOOP_GRID := Vector2(5, 4)
const LOOP_FPS := 24.0
const LOOP_ASPECT := 960.0 / 720.0
## The frame's own side colours, top to bottom, continued across the screen.
const LOOP_SIDES := ["0f3767", "103e6d", "124673", "144d7a", "114875", "114573", "11416f", "0e3967", "0d2f5c"]
## Picture height and top, as fractions of the screen height.
const PIC_H := 0.80
const PIC_TOP := 0.025

signal done

var info: Dictionary = {}
var session: NetSession
## The round being prepared underneath; the screen goes once it is live.
var match_ctrl: MatchController
var stage_lbl: Label
var wait_lbl: Label
var bar: ProgressLine
var leave_btn: Button
var backdrop: Backdrop
var picture: ColorRect
var _mat: ShaderMaterial
var _still: Texture2D
var _atlas: Texture2D
var _atlas_pending := false
var _loop_t := 0.0
var _frame := -1
var _t := 0.0
var _stage_text := "Getting campus ready…"
var _closing := false


func build() -> void:
	Diag.context("loading")
	backdrop = Backdrop.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	move_child(backdrop, 0)
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://assets/shaders/loading_loop.gdshader")
	picture = ColorRect.new()
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.material = _mat
	add_child(picture)
	move_child(picture, 1)
	_still = load(LOOP_STILL) as Texture2D
	_show_still()
	if not UIKit.reduced_motion():
		if App.claim_threaded_load(LOOP_ATLAS) or ResourceLoader.load_threaded_request(LOOP_ATLAS, "Texture2D") == OK:
			_atlas_pending = true
	# top left, clear of the runners and the status: only after a long wait
	var top := UIKit.hbox(0)
	top.alignment = BoxContainer.ALIGNMENT_BEGIN
	content.add_child(top)
	leave_btn = UIKit.quiet("Leave party", Vector2(240, 64), 20)
	leave_btn.visible = false
	leave_btn.pressed.connect(func() -> void: App.leave_room())
	top.add_child(leave_btn)
	var col := UIKit.vbox(8)
	col.alignment = BoxContainer.ALIGNMENT_END
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(col)
	stage_lbl = UIKit.label(_stage_text, 22, UIKit.IVORY, true, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(stage_lbl)
	bar = ProgressLine.new()
	bar.custom_minimum_size = Vector2(300, 6)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(bar)
	wait_lbl = UIKit.label("", 18, UIKit.TEAL, false, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(wait_lbl)
	resized.connect(_layout)
	_layout()


## The picture: as tall as the layout allows, never stretched or cropped
## (all three runners stay whole on every phone and iPad), centred, with the
## status below it.
func _layout() -> void:
	var s := size
	if s.y <= 0.0:
		return
	var h := s.y * PIC_H
	var w := h * LOOP_ASPECT
	if w > s.x * 0.98:
		w = s.x * 0.98
		h = w / LOOP_ASPECT
	picture.position = Vector2((s.x - w) * 0.5, s.y * PIC_TOP)
	picture.size = Vector2(w, h)
	backdrop.pic_top = picture.position.y
	backdrop.pic_h = h
	backdrop.queue_redraw()


func _show_still() -> void:
	if _still == null:
		picture.visible = false     # the backdrop alone: no broken image
		return
	_mat.set_shader_parameter("frames", _still)
	_mat.set_shader_parameter("grid", Vector2.ONE)
	_mat.set_shader_parameter("frame", 0.0)


## The match reports what it is doing (known steps only).
func set_stage(text: String) -> void:
	_stage_text = text
	if is_instance_valid(stage_lbl):
		stage_lbl.text = text


## Evidence captures: the loop at a given time.
func set_loop_time(t: float) -> void:
	_loop_t = t
	_frame = -1


func loop_running() -> bool:
	return _atlas != null


func _process(delta: float) -> void:
	_t += delta
	_poll_atlas()
	if _atlas != null:
		_loop_t += delta
		var f := int(floor(_loop_t * LOOP_FPS)) % LOOP_FRAMES
		if f != _frame:
			_frame = f
			_mat.set_shader_parameter("frame", float(f))
	if _closing:
		return
	var mc_ok := match_ctrl != null and is_instance_valid(match_ctrl)
	if mc_ok and match_ctrl.round_live():
		_close()
		return
	var online := session != null and is_instance_valid(session) and session.mode != NetSession.Mode.OFFLINE
	if mc_ok:
		bar.target = match_ctrl.prep_progress()
		if match_ctrl.prepared:
			set_stage("Starting…" if not online else "Ready")
	if not online:
		return
	var lp: Array = session.load_progress()
	if int(lp[1]) > 1:
		wait_lbl.text = "Waiting for players · %d/%d ready" % [lp[0], lp[1]] if int(lp[0]) < int(lp[1]) else "Everyone's ready"
	# a real, recoverable state: a long wait for a slow or lost player
	leave_btn.visible = _t > 25.0


func _poll_atlas() -> void:
	if not _atlas_pending:
		return
	var st := ResourceLoader.load_threaded_get_status(LOOP_ATLAS)
	if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	_atlas_pending = false
	if st != ResourceLoader.THREAD_LOAD_LOADED:
		return      # keep the still
	var tex := ResourceLoader.load_threaded_get(LOOP_ATLAS) as Texture2D
	if tex == null or _closing:
		return
	_atlas = tex
	_mat.set_shader_parameter("frames", _atlas)
	_mat.set_shader_parameter("grid", LOOP_GRID)
	# starts on frame 0, the still that was already showing
	_loop_t = 0.0
	_frame = -1
	Diag.mark("loading_loop")


## A short fade into the round (no fade with Reduced Motion).
func _close() -> void:
	_closing = true
	Diag.mark("loading_closed")
	Diag.context("match")
	if UIKit.reduced_motion():
		done.emit()
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func() -> void: done.emit())


## Release the loop's textures; a load still running is handed to App,
## which collects and drops it when it finishes.
func _exit_tree() -> void:
	if _atlas_pending:
		App.adopt_threaded_load(LOOP_ATLAS)
		_atlas_pending = false
	if _mat:
		_mat.set_shader_parameter("frames", null)
	_atlas = null
	_still = null


func _go_back() -> void:
	pass


## The screen behind the picture: the frame's own side colours row by row,
## so the picture's feathered edges meet the same blue on any width.
class Backdrop:
	extends Control
	var pic_top := 0.0
	var pic_h := 1.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var stops: Array = LoadingScreen.LOOP_SIDES
		var ys: Array = [0.0]
		var cs: Array = [Color(stops[0])]
		for i in stops.size():
			ys.append(pic_top + pic_h * float(i) / float(stops.size() - 1))
			cs.append(Color(stops[i]))
		ys.append(size.y)
		cs.append(Color(stops[-1]).darkened(0.12))
		for i in ys.size() - 1:
			var a: float = ys[i]
			var b: float = ys[i + 1]
			if b <= a:
				continue
			draw_polygon(PackedVector2Array([Vector2(0, a), Vector2(size.x, a), Vector2(size.x, b), Vector2(0, b)]),
				PackedColorArray([cs[i], cs[i], cs[i + 1], cs[i + 1]]))


## A thin bar for the real preparation progress: it eases toward what the
## match reports and never runs ahead of it.
class ProgressLine:
	extends Control
	var target := 0.0
	var shown := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		var t := clampf(target, 0.0, 1.0)
		var n := minf(t, move_toward(shown, t, delta * 1.6))
		if not is_equal_approx(n, shown):
			shown = n
			queue_redraw()

	func _draw() -> void:
		var r := size.y * 0.5
		draw_style_box(UIKit.box(Color(UIKit.IVORY, 0.18), int(r), 0), Rect2(Vector2.ZERO, size))
		if shown > 0.001:
			draw_style_box(UIKit.box(UIKit.AMBER, int(r), 0), Rect2(Vector2.ZERO, Vector2(maxf(size.y, size.x * shown), size.y)))


## The droplet motif.  Drawn in canvas units relative to the screen height,
## so the resting frame lines up with the launch image on any aspect.
class LoadingMotif:
	extends Control
	var animate := true
	var _t := 0.0
	const DROP_X := [-64.0, 0.0, 64.0]
	const DROP_COL := [Color("6fd8cc"), Color("f4f2ec"), Color("ffc668")]

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		# laid out like the launch image: a square fitted to the screen
		var side := minf(size.x, size.y)
		var top := (size.y - side) * 0.5
		var c := Vector2(size.x * 0.5, top + side * LoadingScreen.MOTIF_Y)
		var k := side / 720.0
		LoadingMotif.draw_resting(self, c, k, 1.0 if animate else 0.85 + 0.15 * sin(_t * 1.3))
		if animate:
			_draw_cycle(c, k)
		LoadingMotif.draw_wordmark(self, Vector2(size.x * 0.5, top + side * LoadingScreen.WORDMARK_Y), k)

	## Animated part: each droplet falls in turn, touches the water line and
	## rings out; the resting frame stays underneath as the calm base.
	func _draw_cycle(c: Vector2, k: float) -> void:
		var u := fmod(_t, LoadingScreen.LOOP_S)
		for i in 3:
			var land := 0.35 + 0.55 * float(i)
			var fall_t := u - (land - 0.42)
			if fall_t >= 0.0 and fall_t < 0.42:
				var e := fall_t / 0.42
				var y := lerpf(-150.0, -34.0, e * e)
				LoadingMotif.droplet(self, c + Vector2(DROP_X[i], y) * k, 11.0 * k, Color(DROP_COL[i], 0.9))
			var r_t := u - land
			if r_t >= 0.0 and r_t < 1.3:
				var e2 := r_t / 1.3
				for ring in 2:
					var rr := (10.0 + 70.0 * (e2 - 0.18 * ring)) * k
					if rr <= 6.0 * k:
						continue
					var a := (1.0 - e2) * (0.55 - 0.2 * ring)
					LoadingMotif.ellipse(self, c + Vector2(DROP_X[i], 22.0) * k, rr, 0.32, Color(DROP_COL[i], a), 2.5 * k)

	## The resting frame (also the launch image): three drops above three
	## soft ripples on a moonlit water line.
	static func draw_resting(ci: CanvasItem, c: Vector2, k: float, alpha: float = 1.0) -> void:
		# moon glow (many faint discs: no visible rings)
		for g in 24:
			ci.draw_circle(c + Vector2(0, 8) * k, (150.0 - g * 5.5) * k, Color(0.30, 0.42, 0.72, 0.0095 * alpha))
		for i in 3:
			var x: float = DROP_X[i]
			LoadingMotif.ellipse(ci, c + Vector2(x, 22.0) * k, 26.0 * k, 0.32, Color(DROP_COL[i], 0.42 * alpha), 2.5 * k)
			LoadingMotif.ellipse(ci, c + Vector2(x, 22.0) * k, 44.0 * k, 0.32, Color(DROP_COL[i], 0.18 * alpha), 2.0 * k)
			LoadingMotif.droplet(ci, c + Vector2(x, -18.0 - (6.0 if i == 1 else 0.0)) * k, 15.0 * k, Color(DROP_COL[i], alpha))

	static func droplet(ci: CanvasItem, p: Vector2, r: float, col: Color) -> void:
		# round bottom, soft point on top: the arc runs between the two
		# tangent points seen from the tip, so the outline never crosses
		var tip := 1.85
		var half := acos(1.0 / tip)
		var pts := PackedVector2Array()
		for s in 25:
			var a := PI + half + (TAU - 2.0 * half) * float(s) / 24.0
			pts.append(p + Vector2(sin(a), cos(a)) * r)
		pts.append(p + Vector2(0, -r * tip))
		ci.draw_colored_polygon(pts, col)
		ci.draw_circle(p + Vector2(-r * 0.35, -r * 0.1), r * 0.24, Color(1, 1, 1, 0.55 * col.a))

	static func ellipse(ci: CanvasItem, c: Vector2, r: float, flat: float, col: Color, width: float) -> void:
		var pts := PackedVector2Array()
		for s in 49:
			var a := TAU * float(s) / 48.0
			pts.append(c + Vector2(cos(a) * r, sin(a) * r * flat))
		ci.draw_polyline(pts, col, width, true)

	## "ULTIMATE TRIFECTA", compact and centred (the title's letterforms).
	static func draw_wordmark(ci: CanvasItem, top_center: Vector2, k: float) -> void:
		var f := UIKit.font_w(700)
		var s1 := int(22 * k)
		var s2 := int(46 * k)
		var w1 := f.get_string_size("ULTIMATE", HORIZONTAL_ALIGNMENT_LEFT, -1, s1).x + 7 * 2.0 * k
		var x := top_center.x - w1 * 0.5
		for ch in "ULTIMATE":
			var cw := f.get_char_size(ch.unicode_at(0), s1).x
			ci.draw_char_outline(f, Vector2(x, top_center.y + 22 * k), ch, s1, int(6 * k), UIKit.NAVY)
			ci.draw_char(f, Vector2(x, top_center.y + 22 * k), ch, s1, UIKit.AMBER)
			x += cw + 2.0 * k
		var w2 := 0.0
		for ch in "TRIFECTA":
			w2 += f.get_char_size(ch.unicode_at(0), s2).x - 1.0 * k
		x = top_center.x - w2 * 0.5
		var i := 0
		for ch in "TRIFECTA":
			var cw := f.get_char_size(ch.unicode_at(0), s2).x
			var bob := (-3.0 if i % 2 == 0 else 2.0) * k
			var base := Vector2(x, top_center.y + 74 * k + bob)
			ci.draw_char_outline(f, base + Vector2(0, 4 * k), ch, s2, int(10 * k), UIKit.NAVY)
			ci.draw_char(f, base + Vector2(0, 4 * k), ch, s2, UIKit.TEAL.darkened(0.25))
			ci.draw_char_outline(f, base, ch, s2, int(9 * k), UIKit.NAVY)
			ci.draw_char(f, base, ch, s2, UIKit.IVORY)
			x += cw - 1.0 * k
			i += 1
