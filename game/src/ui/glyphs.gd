class_name Glyphs
extends RefCounted
## Controller / keyboard button glyphs, drawn as vectors (no third-party
## artwork).  Face buttons follow the active controller's family: letters for
## Xbox-layout and MFi pads, the four PlayStation symbols, and a positional
## diamond (the pressed position filled) for Nintendo and unidentified pads,
## whose letters don't match the positions the game receives.  Shoulders,
## triggers and menu are labelled pills; keyboard keys are key caps.

const BG := Color(0.07, 0.10, 0.17, 0.82)
const RIM := Color(0.957, 0.949, 0.925, 0.85)
const INK := Color(0.957, 0.949, 0.925, 1.0)


## Width the glyph for `action` takes at height `h` (0 when there is none).
static func width(action: String, h: float) -> float:
	var p := Controls.prompt_info(action)
	match String(p["kind"]):
		"pad":
			if _is_face(String(p["slot"])):
				return h
			return maxf(h * 1.25, _text_w(String(p["label"]), h) + h * 0.6)
		"key":
			return maxf(h, _text_w(String(p["label"]), h) + h * 0.55)
	return 0.0


## Draws the glyph with its left edge at `pos.x`, vertically centred on
## `pos.y`; returns the width used.
static func draw(ci: CanvasItem, action: String, pos: Vector2, h: float, alpha: float = 1.0) -> float:
	var p := Controls.prompt_info(action)
	var w := width(action, h)
	if w <= 0.0:
		return 0.0
	var label := String(p["label"])
	var slot := String(p["slot"])
	var bg := Color(BG, BG.a * alpha)
	var rim := Color(RIM, RIM.a * alpha)
	var ink := Color(INK, alpha)
	if String(p["kind"]) == "key":
		var rect := Rect2(pos.x, pos.y - h * 0.5, w, h)
		ci.draw_style_box(_box(bg, rim, h * 0.22), rect)
		_text(ci, label, rect.get_center(), h, ink)
		return w
	if _is_face(slot):
		var c := pos + Vector2(h * 0.5, 0)
		var r := h * 0.5
		ci.draw_circle(c, r, bg)
		ci.draw_arc(c, r - 1.0, 0, TAU, 40, rim, 2.0, true)
		match label:
			"cross":
				var d := r * 0.38
				ci.draw_line(c + Vector2(-d, -d), c + Vector2(d, d), ink, r * 0.16, true)
				ci.draw_line(c + Vector2(d, -d), c + Vector2(-d, d), ink, r * 0.16, true)
			"circle":
				ci.draw_arc(c, r * 0.4, 0, TAU, 32, ink, r * 0.15, true)
			"square":
				var q := r * 0.36
				ci.draw_rect(Rect2(c - Vector2(q, q), Vector2(q, q) * 2.0), ink, false, r * 0.14)
			"triangle":
				var t := r * 0.46
				var pts := PackedVector2Array([c + Vector2(0, -t), c + Vector2(t * 0.87, t * 0.5), c + Vector2(-t * 0.87, t * 0.5), c + Vector2(0, -t)])
				ci.draw_polyline(pts, ink, r * 0.14, true)
			"pos":
				var off := {"north": Vector2(0, -1), "east": Vector2(1, 0), "south": Vector2(0, 1), "west": Vector2(-1, 0)}
				for k in off:
					var dc: Vector2 = c + (off[k] as Vector2) * r * 0.42
					if k == slot:
						ci.draw_circle(dc, r * 0.2, ink)
					else:
						ci.draw_arc(dc, r * 0.16, 0, TAU, 20, Color(ink, ink.a * 0.7), r * 0.07, true)
			_:
				_text(ci, label, c, h, ink)
		return w
	var pill := Rect2(pos.x, pos.y - h * 0.42, w, h * 0.84)
	ci.draw_style_box(_box(bg, rim, h * 0.42), pill)
	_text(ci, label, pill.get_center(), h * 0.92, ink)
	return w


static func _is_face(slot: String) -> bool:
	return slot in ["south", "east", "west", "north"]


static func _text_w(t: String, h: float) -> float:
	return UIKit.font_w(650).get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(h * 0.5)).x


static func _text(ci: CanvasItem, t: String, c: Vector2, h: float, col: Color) -> void:
	var f := UIKit.font_w(650)
	var fs := int(h * 0.5)
	var sz := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	ci.draw_string(f, Vector2(c.x - sz.x * 0.5, c.y + fs * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


static func _box(bg: Color, rim: Color, radius: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = rim
	s.set_border_width_all(2)
	s.set_corner_radius_all(int(radius))
	s.anti_aliasing = true
	return s


## A small Control showing a glyph and a caption ("[A] Join").
class Hint:
	extends Control
	var action := ""
	var caption := ""
	var h := 34.0

	func _init(a: String = "", text: String = "", height: float = 34.0) -> void:
		action = a
		caption = text
		h = height
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		Controls.device_changed.connect(_on_device)
		_refresh()

	func _on_device(_k: String) -> void:
		_refresh()

	func _refresh() -> void:
		var gw := Glyphs.width(action, h)
		visible = gw > 0.0
		var tw := UIKit.font_w(650).get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, int(h * 0.6)).x
		custom_minimum_size = Vector2(gw + (10.0 + tw if caption != "" else 0.0), h)
		queue_redraw()

	func _draw() -> void:
		var gw := Glyphs.draw(self, action, Vector2(0, size.y * 0.5), h)
		if caption != "":
			var fs := int(h * 0.6)
			draw_string(UIKit.font_w(650), Vector2(gw + 10.0, size.y * 0.5 + fs * 0.36), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UIKit.IVORY)
