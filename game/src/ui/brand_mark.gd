class_name BrandMark
extends Control
## A brand picture drawn at an exact, fractional rect (Pass 8).
##
## A TextureRect's own position is rounded to whole canvas units
## (gui/common/snap_controls_to_pixels, on by default, rounds every
## Control's transform origin).  Under the canvas_items stretch one canvas
## unit is 1.625 device px on a 1170-px-high phone (1.04 on an iPhone SE,
## 2.13 on a 12.9-inch iPad), so a TextureRect can't sit on an arbitrary
## device pixel: V5-V8's curtain lockup landed up to half a unit (0.8 px)
## away from where the launch image and boot splash put it.  This control
## stays at the origin of its full-screen rect (nothing to round) and
## draws its texture at `picture_rect`, which is not snapped, so a raster
## made for exact device pixels lands on exactly those pixels (1:1).
##
## `settle` scales the picture about `pivot` inside the draw call (the
## curtain's exit), so the motion is never quantised to the canvas grid.
## `fade` is the picture's opacity.  With `premultiplied` (a texture holding
## colour x coverage, as Brand.studio_raster makes) the mark draws with
## CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA and fades all four channels
## (the canvas shader multiplies the texture by the draw colour; with the
## premultiplied blend an alpha-only fade would leave the colour at full
## strength and glow).

static var _premult_material: CanvasItemMaterial

## The picture; null draws nothing.
var texture: Texture2D:
	set(v):
		texture = v
		queue_redraw()
## Where the picture's pixels go, in this control's (canvas) units.
var picture_rect := Rect2():
	set(v):
		picture_rect = v
		queue_redraw()
## Scale of the picture about `pivot` (1 = as placed).
var settle := 1.0:
	set(v):
		settle = v
		queue_redraw()
## The point the settle scales about, canvas units (the lockup's centre).
var pivot := Vector2()
## Opacity of the picture (the curtain fades this, not modulate).
var fade := 1.0:
	set(v):
		fade = v
		queue_redraw()
## The texture is premultiplied: draw it with the premultiplied blend.
var premultiplied := false:
	set(v):
		premultiplied = v
		if v and _premult_material == null:
			_premult_material = CanvasItemMaterial.new()
			_premult_material.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
		material = _premult_material if v else null
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _draw() -> void:
	if texture == null or picture_rect.size.x <= 0.0:
		return
	var r := picture_rect
	if settle != 1.0:
		r = Rect2(pivot + (r.position - pivot) * settle, r.size * settle)
	var c := Color(fade, fade, fade, fade) if premultiplied else Color(1.0, 1.0, 1.0, fade)
	draw_texture_rect(texture, r, false, c)
