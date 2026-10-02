class_name BootCurtain
extends CanvasLayer
## The launch image, held for the first frames of the app (V4): iOS shows
## the static launch screen, Godot the same image as its boot splash, and
## this curtain draws that frame again over the title while its 3D scene
## warms up, then fades.  Launch -> boot -> title has no jump or flash.

const HOLD_FRAMES := 6
var _frames := 0
var _fading := false
var _face: Control


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_face = Face.new()
	_face.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_face)


func _process(_d: float) -> void:
	_frames += 1
	if _fading or _frames < HOLD_FRAMES:
		return
	_fading = true
	Diag.mark("boot_curtain_out")
	if UIKit.reduced_motion():
		queue_free()
		return
	var tw := create_tween()
	tw.tween_property(_face, "modulate:a", 0.0, 0.35)
	tw.tween_callback(queue_free)


class Face:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP   # nothing is tappable underneath yet

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), LoadingScreen.BG)
		# the launch image is a square fitted to the screen's height
		var side := minf(size.x, size.y)
		var k := side / 720.0
		var top := (size.y - side) * 0.5
		var c := Vector2(size.x * 0.5, top + side * LoadingScreen.MOTIF_Y)
		LoadingScreen.LoadingMotif.draw_resting(self, c, k, 1.0)
		LoadingScreen.LoadingMotif.draw_wordmark(self, Vector2(size.x * 0.5, top + side * LoadingScreen.WORDMARK_Y), k)
