class_name Icons
extends RefCounted
## Vector icons drawn with CanvasItem primitives. Every target pairs a colour
## with a distinct shape so state is never colour-only.


static func draw_shape(ci: CanvasItem, kind: String, c: Vector2, r: float, col: Color, filled: bool = true) -> void:
	if kind.begins_with("e_") and emote_shapes().has(kind):
		draw_emote(ci, kind, c, r, col)
		return
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
		# emotes ("e_*"): drawn by draw_emote() (V7 set, below)
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


# ---------------------------------------------------------------------------
# V7 emote icons: one coherent set
# ---------------------------------------------------------------------------
# V6's emote glyphs mixed a hand, notes, faces and arrows at different
# scales, each off-centre in its own way (the wave's arcs reached past the
# hand, the cheer sat low, the point ran to one side), so a grid of them
# never lined up.  V7 draws every body move as the same chibi runner (a big
# round head, a capsule body, rounded limbs of one stroke weight) in the
# move's key pose, and the face moves (giggle, shush) as that runner's head.
# Every shape is data in a unit square, normalised once so that its drawn
# bounds (strokes included) are centred on the icon's centre and reach the
# same extent: any icon drawn at (c, r) stays inside the circle of radius r
# around c (test_menus_layout checks the bounds).
const E_LIMB := 0.15        # arms
const E_LEG := 0.17         # legs
const E_HEAD := 0.27
const E_BODY := 0.40        # torso capsule width
const E_EXTENT := 0.94      # normalised half-extent (largest side)

static var _emote_cache: Dictionary = {}


## The runner figure: head centre `h`, neck `n` and pelvis `p` of the torso
## capsule, then each limb as a polyline (hands get a small mitten).
static func _fig(h: Vector2, n: Vector2, p: Vector2, arms: Array, legs: Array) -> Array:
	var out: Array = [["circle", h, E_HEAD], ["line", n, p, E_BODY]]
	for a in arms:
		out.append(["stroke", PackedVector2Array(a), E_LIMB])
		out.append(["circle", (a as Array)[-1], 0.1])
	for l in legs:
		out.append(["stroke", PackedVector2Array(l), E_LEG])
	return out


static func _star(c: Vector2, r: float) -> Array:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + PI * float(i) / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	return ["poly", pts]


static func _crescent(c: Vector2, r: float) -> Array:
	# an outer arc and an inner arc offset to the right: a "C"-shaped moon
	var pts := PackedVector2Array()
	var n := 18
	for i in n + 1:
		var a := lerpf(PI * 0.3, PI * 1.7, float(i) / n)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	var inner := c + Vector2(r * 0.42, -r * 0.08)
	var a0 := (pts[n] - inner).angle()
	var a1 := (pts[0] - inner).angle()
	if a1 > a0:
		a1 -= TAU
	for i in range(1, n):
		var a := lerpf(a0, a1, float(i) / n)
		pts.append(inner + Vector2(cos(a), sin(a)) * r * 0.8)
	return ["poly", pts]


## The raw shapes (before normalisation).
static func _emote_raw(kind: String) -> Array:
	var V := func(x: float, y: float) -> Vector2: return Vector2(x, y)
	match kind:
		"e_wave":
			var s := _fig(V.call(-0.1, -0.56), V.call(-0.1, -0.05), V.call(-0.1, 0.24),
				[[V.call(0.1, -0.08), V.call(0.38, -0.2), V.call(0.44, -0.56)], [V.call(-0.3, -0.06), V.call(-0.42, 0.26)]],
				[[V.call(-0.2, 0.38), V.call(-0.24, 0.84)], [V.call(0.0, 0.38), V.call(0.04, 0.84)]])
			s.append(["arc", V.call(0.44, -0.6), 0.25, -1.25, -0.2, 0.09])
			s.append(["arc", V.call(0.44, -0.6), 0.4, -1.1, -0.3, 0.09])
			return s
		"e_cheer":
			var s := _fig(V.call(0.0, -0.5), V.call(0.0, 0.01), V.call(0.0, 0.28),
				[[V.call(-0.2, -0.02), V.call(-0.44, -0.3), V.call(-0.54, -0.66)], [V.call(0.2, -0.02), V.call(0.44, -0.3), V.call(0.54, -0.66)]],
				[[V.call(-0.1, 0.42), V.call(-0.26, 0.86)], [V.call(0.1, 0.42), V.call(0.26, 0.86)]])
			return s
		"e_laugh":
			return [["ring", V.call(0, 0), 0.8, 0.13],
				["arc", V.call(-0.3, -0.16), 0.15, PI + 0.3, TAU - 0.3, 0.11],
				["arc", V.call(0.3, -0.16), 0.15, PI + 0.3, TAU - 0.3, 0.11],
				["halfdisc", V.call(0, 0.12), 0.38]]
		"e_shrug":
			return _fig(V.call(0.05, -0.56), V.call(0.0, -0.05), V.call(0.0, 0.24),
				[[V.call(-0.2, -0.06), V.call(-0.48, 0.08), V.call(-0.66, -0.16)], [V.call(0.2, -0.06), V.call(0.48, 0.08), V.call(0.66, -0.16)]],
				[[V.call(-0.1, 0.38), V.call(-0.12, 0.84)], [V.call(0.1, 0.38), V.call(0.12, 0.84)]])
		"e_dance":
			var s := _fig(V.call(-0.08, -0.56), V.call(-0.04, -0.05), V.call(0.02, 0.24),
				[[V.call(0.15, -0.08), V.call(0.38, -0.36), V.call(0.5, -0.7)], [V.call(-0.22, -0.04), V.call(-0.44, 0.1), V.call(-0.26, 0.26)]],
				[[V.call(-0.08, 0.38), V.call(-0.16, 0.84)], [V.call(0.12, 0.38), V.call(0.34, 0.56), V.call(0.56, 0.48)]])
			s.append(["circle", V.call(-0.66, -0.46), 0.1])
			s.append(["line", V.call(-0.58, -0.46), V.call(-0.58, -0.86), 0.07])
			s.append(["line", V.call(-0.58, -0.86), V.call(-0.42, -0.78), 0.07])
			return s
		"e_point":
			var s := _fig(V.call(-0.32, -0.56), V.call(-0.32, -0.05), V.call(-0.32, 0.24),
				[[V.call(-0.12, -0.08), V.call(0.5, -0.08)], [V.call(-0.52, -0.06), V.call(-0.6, 0.26)]],
				[[V.call(-0.42, 0.38), V.call(-0.46, 0.84)], [V.call(-0.22, 0.38), V.call(-0.18, 0.84)]])
			s.append(["line", V.call(0.5, -0.1), V.call(0.78, -0.1), 0.09])
			return s
		"e_stargaze":
			var s := _fig(V.call(-0.3, -0.42), V.call(-0.36, 0.08), V.call(-0.38, 0.36),
				[[V.call(-0.18, 0.02), V.call(0.08, -0.26), V.call(0.28, -0.5)], [V.call(-0.56, 0.06), V.call(-0.36, 0.2)]],
				[[V.call(-0.46, 0.5), V.call(-0.52, 0.9)], [V.call(-0.26, 0.5), V.call(-0.16, 0.9)]])
			s.append(_star(V.call(0.58, -0.68), 0.24))
			s.append(_star(V.call(0.62, -0.14), 0.12))
			return s
		"e_victory_lap":
			var s := _fig(V.call(0.1, -0.54), V.call(0.05, -0.04), V.call(-0.02, 0.24),
				[[V.call(0.24, -0.06), V.call(0.38, -0.36), V.call(0.36, -0.7)], [V.call(-0.15, -0.02), V.call(-0.4, 0.1), V.call(-0.52, -0.08)]],
				[[V.call(0.04, 0.38), V.call(0.3, 0.56), V.call(0.34, 0.86)], [V.call(-0.08, 0.38), V.call(-0.3, 0.62), V.call(-0.56, 0.6)]])
			s.append(["line", V.call(-0.92, 0.26), V.call(-0.7, 0.26), 0.08])
			s.append(["line", V.call(-0.96, 0.44), V.call(-0.78, 0.44), 0.08])
			return s
		"e_shush":
			return [["ring", V.call(0, 0), 0.8, 0.13],
				["circle", V.call(-0.28, -0.18), 0.09], ["circle", V.call(0.3, -0.18), 0.09],
				["line", V.call(-0.34, 0.36), V.call(-0.12, 0.36), 0.1],
				["line", V.call(0.04, 0.6), V.call(0.04, 0.02), 0.17],
				["circle", V.call(0.08, 0.72), 0.21]]
		"e_moon_shuffle":
			var s := _fig(V.call(0.16, -0.5), V.call(0.14, 0.0), V.call(0.16, 0.28),
				[[V.call(0.32, -0.02), V.call(0.5, 0.14), V.call(0.64, 0.0)], [V.call(-0.04, -0.02), V.call(-0.18, 0.16), V.call(-0.08, 0.32)]],
				[[V.call(0.24, 0.42), V.call(0.3, 0.66), V.call(0.34, 0.86)], [V.call(0.06, 0.42), V.call(-0.18, 0.64), V.call(-0.4, 0.84)]])
			s.append(_crescent(V.call(-0.52, -0.56), 0.3))
			s.append(["line", V.call(-0.92, 0.84), V.call(-0.66, 0.84), 0.08])
			s.append(["line", V.call(-0.86, 0.66), V.call(-0.66, 0.66), 0.08])
			return s
	return []


## Every emote's shapes, normalised: bounds centred on (0, 0), the larger
## half-extent E_EXTENT.  Positions scale; stroke widths and radii scale
## with them so the drawing keeps its proportions.
static func emote_shapes() -> Dictionary:
	if not _emote_cache.is_empty():
		return _emote_cache
	for e in TC.EMOTES:
		var kind := "e_" + String(e)
		var raw := _emote_raw(kind)
		if raw.is_empty():
			continue
		var b := shape_bounds(raw)
		var k := E_EXTENT / maxf(b.size.x, b.size.y) * 2.0
		_emote_cache[kind] = _transform(raw, -b.get_center(), k)
	return _emote_cache


static func _transform(shapes: Array, off: Vector2, k: float) -> Array:
	var out: Array = []
	for s in shapes:
		var t: Array = (s as Array).duplicate()
		match String(t[0]):
			"circle":
				t[1] = ((t[1] as Vector2) + off) * k
				t[2] = float(t[2]) * k
			"line":
				t[1] = ((t[1] as Vector2) + off) * k
				t[2] = ((t[2] as Vector2) + off) * k
				t[3] = float(t[3]) * k
			"stroke":
				var p := PackedVector2Array()
				for v in (t[1] as PackedVector2Array):
					p.append((v + off) * k)
				t[1] = p
				t[2] = float(t[2]) * k
			"poly":
				var p2 := PackedVector2Array()
				for v in (t[1] as PackedVector2Array):
					p2.append((v + off) * k)
				t[1] = p2
			"ring", "halfdisc":
				t[1] = ((t[1] as Vector2) + off) * k
				t[2] = float(t[2]) * k
				if t.size() > 3:
					t[3] = float(t[3]) * k
			"arc":
				t[1] = ((t[1] as Vector2) + off) * k
				t[2] = float(t[2]) * k
				t[5] = float(t[5]) * k
		out.append(t)
	return out


## The drawn bounds of a shape list (strokes and round caps included), in
## the shapes' own units.
static func shape_bounds(shapes: Array) -> Rect2:
	var pts := PackedVector2Array()
	var grow := func(p: Vector2, r: float) -> void:
		pts.append(p - Vector2(r, r))
		pts.append(p + Vector2(r, r))
	for s in shapes:
		var t: Array = s
		match String(t[0]):
			"circle":
				grow.call(t[1], float(t[2]))
			"line":
				grow.call(t[1], float(t[3]) * 0.5)
				grow.call(t[2], float(t[3]) * 0.5)
			"stroke":
				for v in (t[1] as PackedVector2Array):
					grow.call(v, float(t[2]) * 0.5)
			"poly":
				for v in (t[1] as PackedVector2Array):
					pts.append(v)
			"ring":
				grow.call(t[1], float(t[2]) + float(t[3]) * 0.5)
			"halfdisc":
				var c: Vector2 = t[1]
				var r: float = t[2]
				pts.append(c + Vector2(-r, 0))
				pts.append(c + Vector2(r, r))
			"arc":
				for i in 9:
					var a := lerpf(float(t[3]), float(t[4]), float(i) / 8.0)
					grow.call((t[1] as Vector2) + Vector2(cos(a), sin(a)) * float(t[2]), float(t[5]) * 0.5)
	if pts.is_empty():
		return Rect2()
	var r2 := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r2 = r2.expand(p)
	return r2


## Draws an emote icon centred at `c`, fitting the circle of radius `r`.
static func draw_emote(ci: CanvasItem, kind: String, c: Vector2, r: float, col: Color) -> void:
	var shapes: Array = emote_shapes().get(kind, [])
	for s in shapes:
		var t: Array = s
		match String(t[0]):
			"circle":
				ci.draw_circle(c + (t[1] as Vector2) * r, float(t[2]) * r, col, true, -1.0, true)
			"line":
				_capsule(ci, c + (t[1] as Vector2) * r, c + (t[2] as Vector2) * r, float(t[3]) * r, col)
			"stroke":
				var p: PackedVector2Array = t[1]
				for i in p.size() - 1:
					_capsule(ci, c + p[i] * r, c + p[i + 1] * r, float(t[2]) * r, col)
			"poly":
				var q := PackedVector2Array()
				for v in (t[1] as PackedVector2Array):
					q.append(c + v * r)
				ci.draw_colored_polygon(q, col)
			"ring":
				ci.draw_arc(c + (t[1] as Vector2) * r, float(t[2]) * r, 0.0, TAU, 48, col, float(t[3]) * r, true)
			"halfdisc":
				var hc: Vector2 = c + (t[1] as Vector2) * r
				var hr: float = float(t[2]) * r
				var d := PackedVector2Array()
				for i in 17:
					var a := PI * float(i) / 16.0
					d.append(hc + Vector2(cos(a), sin(a)) * hr)
				ci.draw_colored_polygon(d, col)
			"arc":
				var ac: Vector2 = c + (t[1] as Vector2) * r
				var ar := float(t[2]) * r
				var aw := float(t[5]) * r
				ci.draw_arc(ac, ar, float(t[3]), float(t[4]), 12, col, aw, true)
				for a in [float(t[3]), float(t[4])]:
					ci.draw_circle(ac + Vector2(cos(a), sin(a)) * ar, aw * 0.5, col, true, -1.0, true)


static func _capsule(ci: CanvasItem, a: Vector2, b: Vector2, w: float, col: Color) -> void:
	ci.draw_line(a, b, col, w, true)
	ci.draw_circle(a, w * 0.5, col, true, -1.0, true)
	ci.draw_circle(b, w * 0.5, col, true, -1.0, true)


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
