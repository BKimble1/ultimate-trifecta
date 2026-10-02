class_name Brand
extends RefCounted
## The two raster brand marks (V5), drawn once as TextureRects, never traced
## into per-frame text:
##   Ultimate Trifecta title  home, party, match loading (game identity)
##   Idlery Games lockup      app startup only (the studio)
## Runtime textures are made from the owner's masters in art_src/branding by
## tools/branding/make_branding.py: proportional, with the masters' own
## transparent padding kept as layout padding, mipmapped, lossless.  Each
## rect carries an accessibility name (the picture is the only text).

const TITLE := "res://assets/branding/title_ultimate_trifecta.png"
const STUDIO := "res://assets/branding/idlery_games.png"
## Startup background: the launch storyboard, Godot's boot splash and the
## boot curtain all use it (project boot_splash/bg_color).
const STARTUP_BG := Color("000000")   # V6: pure black (owner request)
## The lockup's width as a fraction of the launch square's side (the square
## is fitted to the landscape screen's height).  make_branding.py uses the
## same value for launch.png.
const LOCKUP_W := 0.62


static func _rect(path: String, access: String) -> TextureRect:
	var r := TextureRect.new()
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


static func studio() -> TextureRect:
	return _rect(STUDIO, "Idlery Games")


## Where the startup lockup sits on a screen of `view` size (canvas units):
## the same place the launch image puts it under "scale to fit".
static func lockup_rect(view: Vector2, tex_size: Vector2) -> Rect2:
	var side := minf(view.x, view.y)
	var w := side * LOCKUP_W
	var h := w * tex_size.y / maxf(1.0, tex_size.x)
	return Rect2((view - Vector2(w, h)) * 0.5, Vector2(w, h))
