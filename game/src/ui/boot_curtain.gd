class_name BootCurtain
extends CanvasLayer
## App startup (V5): Idlery Games.
##
## iOS shows the static launch screen (assets/icon/launch.png: the Idlery
## Games lockup centred on pure black; V5 used navy), Godot shows the same image as its
## boot splash, and this curtain draws the same lockup at the same place
## over the first runtime frames, so launch -> boot -> first frame is one
## still picture with no white flash and no second splash.
## Pass 8: the curtain's lockup is rasterised from the vector for this
## screen (Brand.place_studio): exact pixel size, the launch image's
## sub-pixel position, drawn 1:1 by a BrandMark.  V5-V8 drew a 1400-px
## texture through its mipmaps (~0.95 of a mip level down on a phone) in a
## TextureRect whose position Godot rounds to whole canvas units: softer
## than the splash, up to 0.9 px off it, with a ringing halo.
##
## It leaves when the home screen is actually ready, not after a fixed
## number of frames (V4 left after six process frames, whatever was
## happening): the title screen is in the tree, the dorm stage has the
## player's runner, and a few frames in a row have arrived without a stall
## (first-use pipeline compiles happen under the curtain, not over the
## menu; a device that is steadily slow counts as steady).  A short minimum
## keeps the mark from flickering on a warm start; a cap makes sure a slow
## device never sits on a frozen logo.  Then the
## lockup fades with a slight settle and the black dissolves into the room
## (Reduced Motion: a plain short fade).  Taps are held until it has gone.

const MIN_HOLD_S := 0.45
const MAX_WAIT_S := 6.0
const STABLE_FRAMES := 3
const STALL_S := 0.1

var _t := 0.0
var _stable := 0
var _prev_delta := -1.0
var _leaving := false
var bg: ColorRect
var logo: BrandMark
## true when the lockup is the exact vector raster (false: PNG fallback)
var exact := false
var _placed_for := Rect2()
## timings for diagnostics and tests
var waited := 0.0
var reason := ""


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	bg = ColorRect.new()
	bg.color = Brand.STARTUP_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP   # nothing is tappable underneath yet
	add_child(bg)
	logo = Brand.studio()
	add_child(logo)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	if logo == null:
		return
	var vp := get_viewport()
	var key := Rect2(vp.get_visible_rect().size, vp.get_final_transform().get_scale())
	if key == _placed_for and logo.texture != null:
		return   # same screen: keep the raster
	_placed_for = key
	exact = Brand.place_studio(logo, vp)


## True once the first interactive screen exists with its 3D room ready.
static func app_ready() -> bool:
	var s: Variant = App.screen
	if s == null or not is_instance_valid(s) or not (s as Node).is_inside_tree():
		return false
	if App.stage != null and is_instance_valid(App.stage):
		return App.stage.local_character() != null
	return true


## A frame without a hitch: quick, or no slower than the frame before it
## (a slow device that is steadily slow is ready; a compile stall is not).
static func steady(delta: float, prev: float) -> bool:
	return delta < STALL_S or (prev > 0.0 and delta <= prev * 1.25)


func _process(delta: float) -> void:
	_t += delta
	if _leaving:
		return
	if app_ready() and steady(delta, _prev_delta):
		_stable += 1
	else:
		_stable = 0
	_prev_delta = delta
	if _stable >= STABLE_FRAMES and _t >= MIN_HOLD_S:
		_leave("ready")
	elif _t >= MAX_WAIT_S:
		_leave("cap")


func _leave(why: String) -> void:
	_leaving = true
	waited = _t
	reason = why
	Diag.mark("boot_curtain_out")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if UIKit.reduced_motion():
		Motion.animate(bg, "modulate:a", 0.0, 0.15)
		Motion.animate(logo, "fade", 0.0, 0.15)
		get_tree().create_timer(0.16).timeout.connect(queue_free)
		return
	Motion.animate(logo, "fade", 0.0, 0.26, Tween.TRANS_QUAD, Tween.EASE_IN)
	Motion.animate(logo, "settle", 1.03, 0.3, Tween.TRANS_QUAD, Tween.EASE_OUT)
	Motion.animate(bg, "modulate:a", 0.0, 0.34, Tween.TRANS_CUBIC, Tween.EASE_IN_OUT, 0.06)
	get_tree().create_timer(0.42).timeout.connect(queue_free)
