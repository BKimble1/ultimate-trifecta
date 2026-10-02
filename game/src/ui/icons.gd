class_name Icons
extends RefCounted
## Vector icons drawn with CanvasItem primitives. Every target pairs a colour
## with a distinct shape so state is never colour-only.


static func draw_shape(ci: CanvasItem, kind: String, c: Vector2, r: float, col: Color, filled: bool = true) -> void:
	var pts := PackedVector2Array()
	match kind:
		"back":
			ci.draw_polyline(PackedVector2Array([c + Vector2(r * 0.35, -r * 0.75), c + Vector2(-r * 0.4, 0), c + Vector2(r * 0.35, r * 0.75)]), col, r * 0.26, true)
			return
		"info":
			ci.draw_arc(c, r * 0.9, 0, TAU, 28, col, r * 0.16, true)
			ci.draw_circle(c + Vector2(0, -r * 0.42), r * 0.13, col)
			ci.draw_line(c + Vector2(0, -r * 0.14), c + Vector2(0, r * 0.5), col, r * 0.2, true)
			return
		"close":
			ci.draw_line(c + Vector2(-r * 0.6, -r * 0.6), c + Vector2(r * 0.6, r * 0.6), col, r * 0.24, true)
			ci.draw_line(c + Vector2(r * 0.6, -r * 0.6), c + Vector2(-r * 0.6, r * 0.6), col, r * 0.24, true)
			return
		"plus":
			ci.draw_line(c + Vector2(-r * 0.65, 0), c + Vector2(r * 0.65, 0), col, r * 0.24, true)
			ci.draw_line(c + Vector2(0, -r * 0.65), c + Vector2(0, r * 0.65), col, r * 0.24, true)
			return
		"check":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.7, 0), c + Vector2(-r * 0.15, r * 0.55), c + Vector2(r * 0.75, -r * 0.6)]), col, r * 0.28, true)
			return
		"gear":
			for i in 8:
				var ga := TAU * float(i) / 8.0
				ci.draw_line(c + Vector2(cos(ga), sin(ga)) * r * 0.5, c + Vector2(cos(ga), sin(ga)) * r * 0.98, col, r * 0.3)
			ci.draw_circle(c, r * 0.68, col)
			ci.draw_circle(c, r * 0.28, Color(0.07, 0.1, 0.17))
			return
		"copy":
			ci.draw_rect(Rect2(c + Vector2(-r * 0.75, -r * 0.45), Vector2(r * 1.1, r * 1.25)), col, false, r * 0.18)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.35, -r * 0.85), Vector2(r * 1.1, r * 1.25)), col, false, r * 0.18)
			return
		"person":
			ci.draw_circle(c + Vector2(0, -r * 0.42), r * 0.36, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.7, r * 0.85), c + Vector2(-r * 0.55, r * 0.15), c + Vector2(0, -r * 0.02),
				c + Vector2(r * 0.55, r * 0.15), c + Vector2(r * 0.7, r * 0.85)]), col)
			return
		"invite":
			ci.draw_circle(c + Vector2(-r * 0.25, -r * 0.42), r * 0.32, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.85, r * 0.8), c + Vector2(-r * 0.75, r * 0.15), c + Vector2(-r * 0.25, 0.0),
				c + Vector2(r * 0.25, r * 0.15), c + Vector2(r * 0.35, r * 0.8)]), col)
			ci.draw_line(c + Vector2(r * 0.45, -r * 0.25), c + Vector2(r * 1.0, -r * 0.25), col, r * 0.2)
			ci.draw_line(c + Vector2(r * 0.72, -r * 0.52), c + Vector2(r * 0.72, r * 0.02), col, r * 0.2)
			return
		"shirt":
			pts = PackedVector2Array([c + Vector2(-r * 0.35, -r * 0.8), c + Vector2(-r, -r * 0.45), c + Vector2(-r * 0.75, -r * 0.05), c + Vector2(-r * 0.5, -r * 0.2),
				c + Vector2(-r * 0.5, r * 0.85), c + Vector2(r * 0.5, r * 0.85), c + Vector2(r * 0.5, -r * 0.2), c + Vector2(r * 0.75, -r * 0.05),
				c + Vector2(r, -r * 0.45), c + Vector2(r * 0.35, -r * 0.8), c + Vector2(0, -r * 0.55)])
		"smile":
			ci.draw_arc(c, r * 0.9, 0, TAU, 24, col, r * 0.16, true)
			ci.draw_circle(c + Vector2(-r * 0.32, -r * 0.22), r * 0.12, col)
			ci.draw_circle(c + Vector2(r * 0.32, -r * 0.22), r * 0.12, col)
			ci.draw_arc(c + Vector2(0, r * 0.05), r * 0.45, 0.35, PI - 0.35, 12, col, r * 0.15, true)
			return
		"role":
			ci.draw_circle(c + Vector2(-r * 0.38, 0), r * 0.48, col)
			ci.draw_arc(c + Vector2(r * 0.38, 0), r * 0.48, 0, TAU, 20, col, r * 0.16, true)
			return
		"crown":
			pts = PackedVector2Array([c + Vector2(-r, r * 0.6), c + Vector2(-r, -r * 0.45), c + Vector2(-r * 0.45, 0), c + Vector2(0, -r * 0.7),
				c + Vector2(r * 0.45, 0), c + Vector2(r, -r * 0.45), c + Vector2(r, r * 0.6)])
		# --- emotes (lobby picker, results)
		"e_wave":
			# open hand with motion arcs
			ci.draw_rect(Rect2(c + Vector2(-r * 0.32, -r * 0.05), Vector2(r * 0.64, r * 0.75)), col)
			for i in 4:
				var fx := -r * 0.3 + r * 0.2 * float(i)
				ci.draw_line(c + Vector2(fx + r * 0.06, 0), c + Vector2(fx + r * 0.06, -r * 0.62 + absf(float(i) - 1.5) * r * 0.1), col, r * 0.16, true)
			ci.draw_line(c + Vector2(-r * 0.3, r * 0.25), c + Vector2(-r * 0.62, -r * 0.05), col, r * 0.16, true)
			ci.draw_arc(c, r * 0.95, -2.5, -1.9, 6, col, r * 0.1, true)
			ci.draw_arc(c, r * 0.95, -1.2, -0.6, 6, col, r * 0.1, true)
			return
		"e_cheer":
			ci.draw_circle(c + Vector2(0, -r * 0.1), r * 0.3, col)
			ci.draw_line(c + Vector2(-r * 0.2, r * 0.15), c + Vector2(-r * 0.7, -r * 0.65), col, r * 0.18, true)
			ci.draw_line(c + Vector2(r * 0.2, r * 0.15), c + Vector2(r * 0.7, -r * 0.65), col, r * 0.18, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.35, r * 0.2), c + Vector2(r * 0.35, r * 0.2), c + Vector2(r * 0.28, r * 0.9), c + Vector2(-r * 0.28, r * 0.9)]), col)
			return
		"e_laugh":
			ci.draw_arc(c, r * 0.9, 0, TAU, 24, col, r * 0.16, true)
			ci.draw_arc(c + Vector2(-r * 0.32, -r * 0.18), r * 0.16, PI + 0.3, TAU - 0.3, 8, col, r * 0.12, true)
			ci.draw_arc(c + Vector2(r * 0.32, -r * 0.18), r * 0.16, PI + 0.3, TAU - 0.3, 8, col, r * 0.12, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.45, r * 0.12), c + Vector2(r * 0.45, r * 0.12), c + Vector2(0, r * 0.6)]), col)
			return
		"e_shrug":
			ci.draw_circle(c + Vector2(0, -r * 0.25), r * 0.3, col)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.95, -r * 0.35), c + Vector2(-r * 0.7, r * 0.15), c + Vector2(-r * 0.25, r * 0.25)]), col, r * 0.16, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(r * 0.95, -r * 0.35), c + Vector2(r * 0.7, r * 0.15), c + Vector2(r * 0.25, r * 0.25)]), col, r * 0.16, true)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.3, r * 0.15), Vector2(r * 0.6, r * 0.75)), col)
			return
		"e_dance":
			# two beamed notes
			ci.draw_circle(c + Vector2(-r * 0.45, r * 0.55), r * 0.24, col)
			ci.draw_circle(c + Vector2(r * 0.45, r * 0.4), r * 0.24, col)
			ci.draw_line(c + Vector2(-r * 0.25, r * 0.55), c + Vector2(-r * 0.25, -r * 0.6), col, r * 0.13)
			ci.draw_line(c + Vector2(r * 0.65, r * 0.4), c + Vector2(r * 0.65, -r * 0.75), col, r * 0.13)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.25, -r * 0.6), c + Vector2(r * 0.65, -r * 0.75), c + Vector2(r * 0.65, -r * 0.48), c + Vector2(-r * 0.25, -r * 0.33)]), col)
			return
		"e_point":
			ci.draw_line(c + Vector2(-r * 0.8, r * 0.2), c + Vector2(r * 0.55, r * 0.2), col, r * 0.22, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.95, r * 0.2), c + Vector2(r * 0.35, -r * 0.3), c + Vector2(r * 0.35, r * 0.7)]), col)
			ci.draw_circle(c + Vector2(-r * 0.75, r * 0.2), r * 0.24, col)
			return
		# --- move previews
		"m_run":
			ci.draw_circle(c + Vector2(r * 0.2, -r * 0.6), r * 0.22, col)
			ci.draw_polyline(PackedVector2Array([c + Vector2(r * 0.1, -r * 0.3), c + Vector2(-r * 0.1, r * 0.2), c + Vector2(-r * 0.6, r * 0.45)]), col, r * 0.18, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.1, r * 0.2), c + Vector2(r * 0.3, r * 0.45), c + Vector2(r * 0.25, r * 0.9)]), col, r * 0.18, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.55, -r * 0.2), c + Vector2(r * 0.05, -r * 0.2), c + Vector2(r * 0.6, r * 0.05)]), col, r * 0.16, true)
			return
		"m_jump":
			ci.draw_circle(c + Vector2(0, -r * 0.55), r * 0.24, col)
			ci.draw_line(c + Vector2(0, -r * 0.3), c + Vector2(0, r * 0.25), col, r * 0.18, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.55, -r * 0.55), c + Vector2(0, -r * 0.15), c + Vector2(r * 0.55, -r * 0.55)]), col, r * 0.15, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.4, r * 0.55), c + Vector2(0, r * 0.25), c + Vector2(r * 0.4, r * 0.55)]), col, r * 0.15, true)
			ci.draw_line(c + Vector2(-r * 0.7, r * 0.9), c + Vector2(r * 0.7, r * 0.9), col, r * 0.12, true)
			return
		"m_dive":
			ci.draw_circle(c + Vector2(r * 0.65, -r * 0.1), r * 0.22, col)
			ci.draw_line(c + Vector2(r * 0.45, 0.0), c + Vector2(-r * 0.6, r * 0.3), col, r * 0.22, true)
			ci.draw_line(c + Vector2(r * 0.4, -r * 0.05), c + Vector2(r * 0.95, -r * 0.45), col, r * 0.13, true)
			ci.draw_line(c + Vector2(-r * 0.6, r * 0.3), c + Vector2(-r * 0.95, r * 0.15), col, r * 0.13, true)
			ci.draw_arc(c + Vector2(0, r * 0.9), r * 0.7, PI + 0.5, TAU - 0.5, 10, col, r * 0.1, true)
			return
		"m_idle":
			ci.draw_circle(c + Vector2(0, -r * 0.55), r * 0.26, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.38, -r * 0.2), c + Vector2(r * 0.38, -r * 0.2), c + Vector2(r * 0.3, r * 0.5), c + Vector2(-r * 0.3, r * 0.5)]), col)
			ci.draw_line(c + Vector2(-r * 0.15, r * 0.5), c + Vector2(-r * 0.18, r * 0.92), col, r * 0.16, true)
			ci.draw_line(c + Vector2(r * 0.15, r * 0.5), c + Vector2(r * 0.18, r * 0.92), col, r * 0.16, true)
			return
		"sliders":
			for i in 3:
				var y := -r * 0.6 + r * 0.6 * float(i)
				ci.draw_line(c + Vector2(-r * 0.85, y), c + Vector2(r * 0.85, y), col, r * 0.12, true)
				ci.draw_circle(c + Vector2([-0.35, 0.4, -0.05][i] * r, y), r * 0.2, col)
			return
		"trophy":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.55, -r * 0.75), c + Vector2(r * 0.55, -r * 0.75), c + Vector2(r * 0.4, 0.0), c + Vector2(0, r * 0.2), c + Vector2(-r * 0.4, 0.0)]), col)
			ci.draw_arc(c + Vector2(-r * 0.55, -r * 0.42), r * 0.28, PI * 0.5, PI * 1.5, 8, col, r * 0.12, true)
			ci.draw_arc(c + Vector2(r * 0.55, -r * 0.42), r * 0.28, -PI * 0.5, PI * 0.5, 8, col, r * 0.12, true)
			ci.draw_line(c + Vector2(0, r * 0.2), c + Vector2(0, r * 0.6), col, r * 0.16)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.45, r * 0.6), Vector2(r * 0.9, r * 0.25)), col)
			return
		"pause":
			ci.draw_rect(Rect2(c + Vector2(-r * 0.55, -r * 0.7), Vector2(r * 0.38, r * 1.4)), col)
			ci.draw_rect(Rect2(c + Vector2(r * 0.17, -r * 0.7), Vector2(r * 0.38, r * 1.4)), col)
			return
		"bot":
			ci.draw_rect(Rect2(c + Vector2(-r * 0.7, -r * 0.45), Vector2(r * 1.4, r * 1.1)), col)
			ci.draw_line(c + Vector2(0, -r * 0.45), c + Vector2(0, -r * 0.85), col, r * 0.14)
			ci.draw_circle(c + Vector2(0, -r * 0.9), r * 0.14, col)
			ci.draw_circle(c + Vector2(-r * 0.3, 0.05 * r), r * 0.15, Color(0.07, 0.1, 0.17))
			ci.draw_circle(c + Vector2(r * 0.3, 0.05 * r), r * 0.15, Color(0.07, 0.1, 0.17))
			return
		# --- V6 social: chat, walking, mute, report, block, medal
		"chat":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.9, -r * 0.65), c + Vector2(r * 0.9, -r * 0.65), c + Vector2(r * 0.9, r * 0.35),
				c + Vector2(-r * 0.05, r * 0.35), c + Vector2(-r * 0.55, r * 0.85), c + Vector2(-r * 0.45, r * 0.35), c + Vector2(-r * 0.9, r * 0.35)]), col)
			for i in 3:
				ci.draw_circle(c + Vector2(-r * 0.45 + r * 0.45 * float(i), -r * 0.15), r * 0.11, Color(0.07, 0.1, 0.17))
			return
		"walk":
			for side in [-1.0, 1.0]:
				var f := c + Vector2(side * r * 0.32, side * r * 0.3)
				ci.draw_set_transform(f, -0.25 * side, Vector2(0.62, 1.0))
				ci.draw_circle(Vector2.ZERO, r * 0.42, col)
				ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				ci.draw_circle(f + Vector2(0, -r * 0.62), r * 0.16, col)
			return
		"mute":
			ci.draw_arc(c, r * 0.85, 0, TAU, 26, col, r * 0.16, true)
			ci.draw_line(c + Vector2(-r * 0.6, -r * 0.6), c + Vector2(r * 0.6, r * 0.6), col, r * 0.18, true)
			ci.draw_circle(c + Vector2(-r * 0.25, -r * 0.05), r * 0.12, col)
			ci.draw_circle(c + Vector2(r * 0.25, -r * 0.05), r * 0.12, col)
			return
		"flag":
			ci.draw_line(c + Vector2(-r * 0.6, -r * 0.85), c + Vector2(-r * 0.6, r * 0.9), col, r * 0.18, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.55, -r * 0.8), c + Vector2(r * 0.8, -r * 0.5), c + Vector2(-r * 0.55, r * 0.05)]), col)
			return
		"block":
			ci.draw_arc(c, r * 0.82, 0, TAU, 28, col, r * 0.2, true)
			ci.draw_line(c + Vector2(-r * 0.55, r * 0.55), c + Vector2(r * 0.55, -r * 0.55), col, r * 0.2, true)
			return
		"medal":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.55, -r), c + Vector2(-r * 0.15, -r), c + Vector2(r * 0.1, -r * 0.2), c + Vector2(-r * 0.25, -r * 0.1)]), col.darkened(0.25))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.55, -r), c + Vector2(r * 0.15, -r), c + Vector2(-r * 0.1, -r * 0.2), c + Vector2(r * 0.25, -r * 0.1)]), col.darkened(0.25))
			ci.draw_circle(c + Vector2(0, r * 0.3), r * 0.62, col)
			ci.draw_arc(c + Vector2(0, r * 0.3), r * 0.42, 0, TAU, 20, col.darkened(0.3), r * 0.1, true)
			return
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
		"lock":
			ci.draw_arc(c + Vector2(0, -r * 0.2), r * 0.42, PI, TAU, 14, col, r * 0.18, true)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.62, -r * 0.2), Vector2(r * 1.24, r * 0.98)), col)
			return
		"share":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.35, -r * 0.2), c + Vector2(-r * 0.7, -r * 0.2), c + Vector2(-r * 0.7, r * 0.85),
				c + Vector2(r * 0.7, r * 0.85), c + Vector2(r * 0.7, -r * 0.2), c + Vector2(r * 0.35, -r * 0.2)]), col, r * 0.16, true)
			ci.draw_line(c + Vector2(0, r * 0.35), c + Vector2(0, -r * 0.85), col, r * 0.18, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.38, -r * 0.48), c + Vector2(0, -r * 0.88), c + Vector2(r * 0.38, -r * 0.48)]), col, r * 0.18, true)
			return
		"rotate":
			ci.draw_arc(c, r * 0.7, 0.4, TAU - 0.9, 20, col, r * 0.16, true)
			var tip := c + Vector2(cos(0.4), sin(0.4)) * r * 0.7
			ci.draw_colored_polygon(PackedVector2Array([tip + Vector2(-r * 0.32, -r * 0.05), tip + Vector2(r * 0.28, -r * 0.12), tip + Vector2(0.0, r * 0.38)]), col)
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


static func emote_icon(id: int) -> String:
	return "e_" + String(TC.EMOTES[id]) if id >= 0 and id < TC.EMOTES.size() else "smile"


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
