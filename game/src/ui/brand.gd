class_name Brand
extends RefCounted
## The two brand marks (V5), drawn once as TextureRects, never traced into
## per-frame text:
##   Ultimate Trifecta title  home, party, match loading (game identity)
##   Idlery Games lockup      app startup only (the studio)
## Runtime art is made from the owner's masters in art_src/branding by
## tools/branding/make_branding.py, lossless.  Each rect carries an
## accessibility name (the picture is the only text).
##
## Pass 8: the startup lockup is rasterised from its vector source
## (STUDIO_SVG) at the exact device-pixel size and sub-pixel position it is
## shown at, and drawn 1:1 with a plain linear filter by a BrandMark (whose
## picture isn't snapped to the canvas-unit grid): no mip level choice, no
## resampling of a bigger raster, the same geometry as the launch image
## (which make_branding.py rasterises from the same vector).  The 1400-px
## PNG (an exact-coverage raster of the same vector, mipmapped) is only the
## fallback for a build without the SVG rasteriser.

const TITLE := "res://assets/branding/title_ultimate_trifecta.png"
const STUDIO := "res://assets/branding/idlery_games.png"
## The lockup's vector source, shipped as-is (import "keep"); a copy of
## art_src/branding/idlery-games.svg made by make_branding.py.
const STUDIO_SVG := "res://assets/branding/idlery_games.svg"
## Startup background: the launch storyboard, Godot's boot splash and the
## boot curtain all use it (project boot_splash/bg_color).
const STARTUP_BG := Color("000000")   # V6: pure black (owner request)
## The lockup's width as a fraction of the launch square's side (the square
## is fitted to the landscape screen's height).  make_branding.py uses the
## same value for launch.png.
const LOCKUP_W := 0.62


static func _rect(path: String, access: String) -> TextureRect:
	var r := TextureRect.new()
	if path != "":
		r.texture = load(path) as Texture2D
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.accessibility_name = access
	return r


## The game title.  `width` in canvas units; the height follows the art.
static func title(width: float) -> TextureRect:
	var r := _rect(TITLE, "Ultimate Trifecta")
	var tex := r.texture
	r.custom_minimum_size = Vector2(width, width * float(tex.get_height()) / float(tex.get_width())) if tex else Vector2(width, width / 3.0)
	return r


## The startup lockup, without its picture yet: place_studio() rasterises
## it for the screen it is on.
static func studio() -> BrandMark:
	var m := BrandMark.new()
	m.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	m.accessibility_name = "Idlery Games"
	return m


## Where the startup lockup sits on a screen of `view` size (canvas units):
## the same place the launch image puts it under "scale to fit".
static func lockup_rect(view: Vector2, tex_size: Vector2) -> Rect2:
	var side := minf(view.x, view.y)
	var w := side * LOCKUP_W
	var h := w * tex_size.y / maxf(1.0, tex_size.x)
	return Rect2((view - Vector2(w, h)) * 0.5, Vector2(w, h))


## The lockup's vector source text, or "" when it can't be read.
static func studio_svg() -> String:
	return FileAccess.get_file_as_string(STUDIO_SVG) if FileAccess.file_exists(STUDIO_SVG) else ""


## Size of the vector's canvas (its viewBox) in its own units; the lockup's
## aspect ratio.  Vector2.ZERO if `svg` has none.
static func svg_size(svg: String) -> Vector2:
	var head := _svg_head(svg)
	var vb := _attr(head, "viewBox").replace(",", " ").split(" ", false)
	if vb.size() == 4:
		return Vector2(float(vb[2]), float(vb[3]))
	return Vector2(float(_attr(head, "width")), float(_attr(head, "height")))


## The lockup rasterised from `svg` so that its canvas covers exactly
## `px` (device pixels, fractional position and size allowed).  The image
## spans the whole pixels from floor(px.position) to ceil(px.end) and is
## PREMULTIPLIED (colour x coverage), so the settle's bilinear scaling can't
## pull the transparent pixels' black into the contour; draw it with
## BrandMark.premultiplied (the matching blend).  null on failure.
static func studio_raster(svg: String, px: Rect2) -> Image:
	var size := svg_size(svg)
	var head := _svg_head(svg)
	if size.x <= 0.0 or size.y <= 0.0 or head == "" or px.size.x < 1.0:
		return null
	var vb := _attr(head, "viewBox").replace(",", " ").split(" ", false)
	var vx := float(vb[0]) if vb.size() == 4 else 0.0
	var vy := float(vb[1]) if vb.size() == 4 else 0.0
	var k := px.size.x / size.x                 # device px per vector unit
	var o := px.position.floor()
	var f := px.position - o                    # sub-pixel offset
	var w := ceili(f.x + px.size.x - 0.001)
	var h := ceili(f.y + size.y * k - 0.001)
	var root := '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="%.6f %.6f %.6f %.6f">' % [
		w, h, vx - f.x / k, vy - f.y / k, float(w) / k, float(h) / k]
	var img := Image.new()
	if img.load_svg_from_string(root + svg.substr(svg.find(head) + head.length()), 1.0) != OK:
		return null
	if img.get_width() != w or img.get_height() != h:
		return null
	img.premultiply_alpha()
	return img


## Puts the startup lockup into `mark` for `vp`: rasterised from the
## vector at the exact pixel size and sub-pixel position (drawn 1:1, linear
## filter, premultiplied alpha with the premultiplied blend), or, if that is
## unavailable, the PNG fallback over the same rect (straight alpha with its
## import's alpha-border fix, mipmapped).  Returns true for the exact raster.
static func place_studio(mark: BrandMark, vp: Viewport, svg: String = "") -> bool:
	if svg == "":
		svg = studio_svg()
	var aspect := svg_size(svg)
	var fallback: Texture2D = null
	if aspect.x <= 0.0 or aspect.y <= 0.0:
		fallback = load(STUDIO) as Texture2D   # same canvas aspect as the vector
		aspect = fallback.get_size()
	# canvas units -> window pixels.  Not quite uniform: the canvas size is
	# whole units (1558 x 720 on a 2532 x 1170 phone: x 1.62516, y 1.625),
	# so the rect is laid out in window pixels, exactly as the launch image
	# and the boot splash lay it out, and mapped back to canvas units
	var xf := vp.get_final_transform()
	var inv := xf.affine_inverse()
	var px := lockup_rect(xf.basis_xform(vp.get_visible_rect().size), aspect)
	var img := studio_raster(svg, px) if fallback == null else null
	mark.premultiplied = img != null
	if img != null:
		mark.texture = ImageTexture.create_from_image(img)
		mark.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		mark.picture_rect = Rect2(inv * px.position.floor(), inv.basis_xform(Vector2(img.get_size())))
	else:
		mark.texture = fallback if fallback != null else load(STUDIO) as Texture2D
		mark.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		mark.picture_rect = Rect2(inv * px.position, inv.basis_xform(px.size))
	mark.pivot = inv * px.get_center()
	return img != null


static func _svg_head(svg: String) -> String:
	var a := svg.find("<svg")
	var b := svg.find(">", a)
	return svg.substr(a, b - a + 1) if a >= 0 and b > a else ""


static func _attr(tag: String, name: String) -> String:
	var key := " %s=\"" % name
	var a := tag.find(key)
	if a < 0:
		return ""
	a += key.length()
	return tag.substr(a, tag.find("\"", a) - a)
