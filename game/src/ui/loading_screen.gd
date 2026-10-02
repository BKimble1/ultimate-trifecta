class_name LoadingScreen
extends Screen
## Match loading (V5): Ultimate Trifecta.
##
##   top      the game title graphic
##   middle   three runners from the actual game rig, running in place on
##            moonlit ground: a 60 fps loop that is exactly periodic (one
##            gait cycle), drawn with premultiplied alpha over the screen's
##            own night background, so there is no box, seam or 4:3 picture
##   bottom   a quiet status: what the round is doing ("Getting campus
##            ready…", "Placing players…"), a thin bar that follows the
##            preparation steps actually completed (it never runs ahead), and
##            "Waiting for players · 3/4 ready" when that is what's happening
##
## The loop (assets/loading/rig_loop_*): 26 frames at 60 fps in one grid
## atlas, GPU-compressed (ASTC 4x4 on iOS, ~13 MB), no sound.  Frames rather
## than a video stream: nothing is decoded on the main thread while the
## round is prepared, and the loop restarts frame-exactly.  The still (loop
## frame 0) shows at once while the atlas loads on a background thread; the
## loop then starts from that same frame, and if the atlas can't load the
## still stays.  Reduced Motion shows only the still.  The screen fades into
## the round the moment it is live (it never waits for the loop), and lets
## everything go when it closes.  The V4 clip of the owner's animation was
## compared and replaced: see docs/V5_NOTES.md.

const BG := Color("0c1324")
const LOOP_ATLAS := "res://assets/loading/rig_loop_atlas.png"
const LOOP_STILL := "res://assets/loading/rig_loop_still.png"
const LOOP_META := "res://assets/loading/rig_loop.json"
## Written by tools/make_loading_loop_rig.py (rig_loop.json; test_loading
## checks they agree).
const LOOP_FRAMES := 26
const LOOP_GRID := Vector2(4, 7)
const LOOP_FPS := 60.0
const LOOP_FRAME := Vector2(920, 540)
## Picture height as a fraction of the screen, and never drawn larger than
## 1.25x its pixels (sharp on big iPads).
const PIC_H := 0.47
const PIC_MAX_SCALE := 1.25
const FEET_Y := 0.785

signal done

var info: Dictionary = {}
var session: NetSession
## The round being prepared underneath; the screen goes once it is live.
var match_ctrl: MatchController
var stage_lbl: Label
var wait_lbl: Label
var bar: ProgressLine
var leave_btn: Button
var backdrop: ColorRect
var title_art: TextureRect
var picture: ColorRect
var _mat: ShaderMaterial
var _bg_mat: ShaderMaterial
var _still: Texture2D
var _atlas: Texture2D
var _atlas_pending := false
var _loop_t := 0.0
var _frame := -1
var _t := 0.0
var _stage_text := "Getting campus ready…"
var _closing := false
var _status: VBoxContainer


func build() -> void:
	Diag.context("loading")
	backdrop = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_mat = ShaderMaterial.new()
	_bg_mat.shader = preload("res://assets/shaders/loading_bg.gdshader")
	backdrop.material = _bg_mat
	add_child(backdrop)
	move_child(backdrop, 0)
	title_art = Brand.title(400.0)
	title_art.custom_minimum_size = Vector2.ZERO
	add_child(title_art)
	move_child(title_art, 1)
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://assets/shaders/loading_loop.gdshader")
	picture = ColorRect.new()
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.material = _mat
	picture.accessibility_name = "Three runners in pajamas running"
	add_child(picture)
	move_child(picture, 2)
	_still = load(LOOP_STILL) as Texture2D
	_show_still()
	if not UIKit.reduced_motion():
		if App.claim_threaded_load(LOOP_ATLAS) or ResourceLoader.load_threaded_request(LOOP_ATLAS, "Texture2D") == OK:
			_atlas_pending = true
	# top left, clear of the runners and the status: only after a long wait
	var top := UIKit.hbox(0)
	top.alignment = BoxContainer.ALIGNMENT_BEGIN
	content.add_child(top)
	leave_btn = UIKit.quiet("Leave party", Vector2(220, 0))
	leave_btn.visible = false
	leave_btn.pressed.connect(func() -> void: App.leave_room())
	top.add_child(leave_btn)
	_status = UIKit.vbox(8)
	_status.alignment = BoxContainer.ALIGNMENT_END
	_status.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_status)
	stage_lbl = UIKit.styled(_stage_text, "caption", UIKit.IVORY_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_status.add_child(stage_lbl)
	bar = ProgressLine.new()
	bar.custom_minimum_size = Vector2(260, 4)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_status.add_child(bar)
	wait_lbl = UIKit.styled("", "caption", UIKit.TEAL, HORIZONTAL_ALIGNMENT_CENTER)
	wait_lbl.add_theme_font_size_override("font_size", 18)
	_status.add_child(wait_lbl)
	resized.connect(_layout)
	_layout()


## Title on top, the runners standing at FEET_Y, the status below them.
func _layout() -> void:
	var s := size
	if s.y <= 0.0:
		return
	var sm := UIKit.safe_margins(get_viewport()) if is_inside_tree() else Rect2(Vector2(16, 12), Vector2(16, 12))
	var c2px := get_viewport().get_final_transform().get_scale().y if is_inside_tree() else 1.0
	var h := minf(s.y * PIC_H, LOOP_FRAME.y * PIC_MAX_SCALE / maxf(0.01, c2px))
	var w := h * LOOP_FRAME.x / LOOP_FRAME.y
	if w > s.x * 0.92:
		w = s.x * 0.92
		h = w * LOOP_FRAME.y / LOOP_FRAME.x
	# the frames keep a small margin under the shoes: put the shoes on FEET_Y
	picture.size = Vector2(w, h)
	picture.position = Vector2((s.x - w) * 0.5, s.y * FEET_Y - h * 0.97)
	# the title above the group, a little narrower if a short screen needs it
	var ttop := maxf(sm.position.y * 0.5, s.y * 0.035)
	var tw := minf(minf(s.x * 0.38, s.y * 0.92), (picture.position.y + h * 0.06 - ttop) * 3.0)
	title_art.position = Vector2((s.x - tw) * 0.5, ttop)
	title_art.size = Vector2(tw, tw / 3.0)
	_bg_mat.set_shader_parameter("aspect", s)
	_bg_mat.set_shader_parameter("glow_c", Vector2(0.5, (picture.position.y + h * 0.45) / s.y))
	_bg_mat.set_shader_parameter("pool_c", Vector2(0.5, (picture.position.y + h * 0.93) / s.y))
	_bg_mat.set_shader_parameter("pool_w", w * 0.42 / s.x)
	_bg_mat.set_shader_parameter("horizon", clampf((picture.position.y + h * 0.7) / s.y, 0.5, 0.8))


func _show_still() -> void:
	if _still == null:
		picture.visible = false     # the background alone: no broken image
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
	var tw := Motion.animate(self, "modulate:a", 0.0, 0.25, Tween.TRANS_QUAD, Tween.EASE_IN)
	if tw:
		tw.tween_callback(func() -> void: done.emit())
	else:
		done.emit()


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
		var r := int(size.y * 0.5)
		draw_style_box(UIKit.box(Color(UIKit.IVORY, 0.14), r, 0), Rect2(Vector2.ZERO, size))
		if shown > 0.001:
			draw_style_box(UIKit.box(UIKit.TEAL, r, 0), Rect2(Vector2.ZERO, Vector2(maxf(size.y, size.x * shown), size.y)))
