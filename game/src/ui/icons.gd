class_name Icons
extends RefCounted
## Vector icons drawn with CanvasItem primitives. Every target pairs a colour
## with a distinct shape so state is never colour-only.


static func draw_shape(ci: CanvasItem, kind: String, c: Vector2, r: float, col: Color, filled: bool = true) -> void:
	var pts := PackedVector2Array()
	match kind:
		"star":
			for i in 10:
				var a := -PI * 0.5 + TAU * float(i) / 10.0
				var rr := r if i % 2 == 0 else r * 0.45
				pts.append(c + Vector2(cos(a), sin(a)) * rr)
		"leaf":
			for i in 16:
				var t := float(i) / 15.0
				var a := lerpf(-PI * 0.5, PI * 0.5, t)
				pts.append(c + Vector2(sin(a) * r * 0.55, -cos(a) * r))
			for i in 16:
				var t2 := float(i) / 15.0
				var a2 := lerpf(PI * 0.5, PI * 1.5, t2)
				pts.append(c + Vector2(sin(a2) * r * 0.55, -cos(a2) * r))
		"drop":
			pts.append(c + Vector2(0, -r))
			for i in 13:
				var a3 := lerpf(-PI * 0.15, PI * 1.15, float(i) / 12.0)
				pts.append(c + Vector2(cos(a3) * r * 0.62, sin(a3) * r * 0.62 + r * 0.3))
		"diamond":
			pts = PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.75, 0), c + Vector2(0, r), c + Vector2(-r * 0.75, 0)])
		"flower":
			for i in 5:
				var a4 := -PI * 0.5 + TAU * float(i) / 5.0
				ci.draw_circle(c + Vector2(cos(a4), sin(a4)) * r * 0.55, r * 0.42, col)
			ci.draw_circle(c, r * 0.32, col.lightened(0.5))
			return
		"anchor":
			ci.draw_line(c + Vector2(0, -r * 0.7), c + Vector2(0, r * 0.8), col, r * 0.22)
			ci.draw_arc(c + Vector2(0, r * 0.1), r * 0.7, 0.2, PI - 0.2, 12, col, r * 0.22)
			ci.draw_circle(c + Vector2(0, -r * 0.8), r * 0.22, col)
			ci.draw_line(c + Vector2(-r * 0.45, -r * 0.35), c + Vector2(r * 0.45, -r * 0.35), col, r * 0.18)
			return
		"house":
			pts = PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, -r * 0.1), c + Vector2(r * 0.75, -r * 0.1), c + Vector2(r * 0.75, r * 0.8),
				c + Vector2(-r * 0.75, r * 0.8), c + Vector2(-r * 0.75, -r * 0.1), c + Vector2(-r, -r * 0.1)])
		"eye":
			ci.draw_arc(c, r, PI * 1.1, PI * 1.9, 12, col, r * 0.18)
			ci.draw_arc(c, r, PI * 0.1, PI * 0.9, 12, col, r * 0.18)
			ci.draw_circle(c, r * 0.38, col)
			return
		"whistle":
			ci.draw_circle(c + Vector2(r * 0.2, r * 0.15), r * 0.55, col)
			ci.draw_rect(Rect2(c + Vector2(-r, -r * 0.4), Vector2(r * 1.1, r * 0.5)), col)
			return
		"cart":
			ci.draw_rect(Rect2(c + Vector2(-r, -r * 0.2), Vector2(r * 2.0, r * 0.7)), col)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.8, -r), Vector2(r * 1.6, r * 0.18)), col)
			ci.draw_line(c + Vector2(-r * 0.7, -r), c + Vector2(-r * 0.7, -r * 0.2), col, r * 0.12)
			ci.draw_line(c + Vector2(r * 0.7, -r), c + Vector2(r * 0.7, -r * 0.2), col, r * 0.12)
			ci.draw_circle(c + Vector2(-r * 0.6, r * 0.55), r * 0.3, col)
			ci.draw_circle(c + Vector2(r * 0.6, r * 0.55), r * 0.3, col)
			return
		"bolt":
			pts = PackedVector2Array([c + Vector2(r * 0.2, -r), c + Vector2(-r * 0.6, r * 0.1), c + Vector2(-r * 0.05, r * 0.1),
				c + Vector2(-r * 0.25, r), c + Vector2(r * 0.6, -r * 0.15), c + Vector2(r * 0.05, -r * 0.15)])
		"duck":
			ci.draw_circle(c + Vector2(r * 0.15, r * 0.25), r * 0.6, col)
			ci.draw_circle(c + Vector2(-r * 0.35, -r * 0.35), r * 0.38, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.7, -r * 0.4), c + Vector2(-r, -r * 0.25), c + Vector2(-r * 0.68, -r * 0.18)]), Color(1.0, 0.55, 0.15))
			return
		"bomb":
			ci.draw_circle(c + Vector2(0, r * 0.15), r * 0.75, col)
			ci.draw_line(c + Vector2(r * 0.3, -r * 0.45), c + Vector2(r * 0.6, -r * 0.9), col, r * 0.16)
			return
		_:
			ci.draw_circle(c, r, col)
			return
	if filled:
		ci.draw_colored_polygon(pts, col)
	else:
		pts.append(pts[0])
		ci.draw_polyline(pts, col, maxf(2.0, r * 0.14))


static func gadget_icon(g: int) -> String:
	match g:
		TC.Gadget.TURBO: return "bolt"
		TC.Gadget.DECOY: return "duck"
		TC.Gadget.SPLASH_BOMB: return "bomb"
	return ""


## Simple Control that draws an icon (used inside containers).
class IconRect:
	extends Control
	var kind := "star"
	var col := Color.WHITE
	var filled := true

	func _init(k: String = "star", c: Color = Color.WHITE, size_px: float = 40.0) -> void:
		kind = k
		col = c
		custom_minimum_size = Vector2(size_px, size_px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		Icons.draw_shape(self, kind, size * 0.5, minf(size.x, size.y) * 0.45, col, filled)
