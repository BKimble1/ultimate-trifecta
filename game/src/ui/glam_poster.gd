class_name GlamPoster
extends Control
## The animated poster every promotion uses (2.2 build 15): the champion
## prize, the Season Pass offer and the daily present.  Painted, no image
## files: a rounded gradient card, slowly turning light rays from a focal
## point, a soft glow, tumbling confetti, twinkling sparkles, a light sweep
## that crosses it now and then, and a double gold frame.  It moves wherever
## it is shown (popups, banners), and only while it is on screen.
## Reduced Motion: (2.2 build 16) the same picture at a third of the speed
## and no light sweep (a still poster read as broken).
##
## Subclasses paint their art over the backdrop in _paint_art() and may
## change the palette and focal point before _ready.

var big := false
var t := 0.0
## colours: top and bottom of the gradient, the rays, the glow, the frame
var top_col := Color("3a1c7a")
var bot_col := Color("0b1a46")
var ray_col := Color(1.0, 0.85, 0.45, 0.07)
var glow_col := Color(1.0, 0.78, 0.36, 0.05)
var frame_col := UIKit.AMBER
## the rays' centre as a fraction of the size
var focus := Vector2(0.8, 0.52)
## confetti: how many, how fast (fractions of the height per second), where
## (x range as fractions)
var confetti_n := 0
var confetti_speed := Vector2(0.14, 0.3)
var confetti_x := Vector2(0.0, 1.0)
var confetti_cols: Array = [UIKit.AMBER, UIKit.TEAL, Color("ff7aa2"), Color("8fd3ff"), UIKit.IVORY]
var sparkles_n := 0
var radius := 0.0   # 0: 30 big, 20 small
var sweep_every := 4.5   # seconds between light sweeps (0: none)

var confetti: Array = []
var _sparkles: Array = []
var _shape := PackedVector2Array()
var _shape_for := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	if confetti_n <= 0:
		confetti_n = 44 if big else 26
	for i in confetti_n:
		confetti.append({"x": rng.randf_range(confetti_x.x, confetti_x.y), "y": rng.randf(),
			"s": rng.randf_range(confetti_speed.x, confetti_speed.y), "c": confetti_cols[i % confetti_cols.size()],
			"r": rng.randf() * TAU, "w": rng.randf_range(-3.0, 3.0), "f": rng.randf_range(3.0, 7.0),
			"sway": rng.randf_range(0.004, 0.014), "ph": rng.randf() * TAU, "len": rng.randf_range(0.8, 1.4)})
	if sparkles_n <= 0:
		sparkles_n = 9 if big else 5
	for i in sparkles_n:
		# (within the confetti's band: never over the poster's words)
		_sparkles.append({"p": Vector2(rng.randf_range(maxf(0.06, confetti_x.x), minf(0.94, confetti_x.y)), rng.randf_range(0.08, 0.92)), "ph": rng.randf() * TAU,
			"f": rng.randf_range(0.6, 1.3), "s": rng.randf_range(0.6, 1.2)})
	# the light sweep: a thin overlay child drawn over everything the poster
	# holds (labels and buttons included), added blend
	var sweep := Sweep.new()
	sweep.poster = self
	sweep.set_anchors_preset(Control.PRESET_FULL_RECT)
	sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child.call_deferred(sweep)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	t += delta * (0.35 if UIKit.reduced_motion() else 1.0)
	queue_redraw()


## The poster's rounded outline (everything painted stays inside it).
func shape() -> PackedVector2Array:
	if _shape_for == size and not _shape.is_empty():
		return _shape
	_shape_for = size
	_shape = PackedVector2Array()
	var rad := minf(corner(), minf(size.x, size.y) * 0.5)
	var corners := [[Vector2(size.x - rad, rad), -PI * 0.5], [Vector2(size.x - rad, size.y - rad), 0.0],
		[Vector2(rad, size.y - rad), PI * 0.5], [Vector2(rad, rad), PI]]
	for cr in corners:
		for k in 9:
			_shape.append((cr[0] as Vector2) + Vector2.from_angle(float(cr[1]) + PI * 0.5 * float(k) / 8.0) * rad)
	return _shape


func corner() -> float:
	return radius if radius > 0.0 else (30.0 if big else 20.0)


## A polygon cut to the poster's outline.
func fill_clipped(poly: PackedVector2Array, col: Color) -> void:
	for piece in Geometry2D.intersect_polygons(poly, shape()):
		if piece.size() >= 3:
			draw_colored_polygon(piece, col)


func disc(c: Vector2, r: float, n: int = 40) -> PackedVector2Array:
	var d := PackedVector2Array()
	for j in n:
		d.append(c + Vector2.from_angle(TAU * float(j) / float(n)) * r)
	return d


func _draw() -> void:
	var outline := shape()
	var cols := PackedColorArray()
	for v in outline:
		cols.append(top_col.lerp(bot_col, clampf(v.y / maxf(size.y, 1.0), 0.0, 1.0)))
	draw_polygon(outline, cols)
	var c := Vector2(size.x * focus.x, size.y * focus.y)
	var n := 16
	var L := size.length()
	for i in n:
		var a := TAU * float(i) / float(n) + t * 0.12
		var a2 := a + TAU / float(n) * 0.42
		fill_clipped(PackedVector2Array([c, c + Vector2.from_angle(a) * L, c + Vector2.from_angle(a2) * L]), ray_col)
	var pulse := 1.0 + 0.05 * sin(t * 1.8)
	for k in 7:
		fill_clipped(disc(c, size.y * 0.44 * pulse * (1.0 - float(k) * 0.13)), glow_col)
	_paint_art(c)
	_draw_sparkles()
	_draw_confetti()
	_draw_frame()


## Subclasses: the poster's own picture (the focal point given).
func _paint_art(_c: Vector2) -> void:
	pass


func _draw_sparkles() -> void:
	var s0 := size.y * (0.03 if big else 0.045)
	for q in _sparkles:
		var tw := 0.5 + 0.5 * sin(t * 2.4 * float(q["f"]) + float(q["ph"]))
		if tw < 0.15:
			continue
		var p: Vector2 = q["p"]
		Icons.draw_shape(self, "star", Vector2(p.x * size.x, p.y * size.y), s0 * float(q["s"]) * tw, Color(1, 1, 0.9, 0.85 * tw))


func _draw_confetti() -> void:
	var m := 0.04
	for q in confetti:
		var y := m + fmod(float(q["y"]) + t * float(q["s"]), 1.0) * (1.0 - m * 2.0)
		var x := m + (float(q["x"]) + sin(t * 1.3 + float(q["ph"])) * float(q["sway"])) * (1.0 - m * 2.0)
		var p := Vector2(x * size.x, y * size.y)
		var rot := float(q["r"]) + t * float(q["w"])
		var s := size.y * (0.011 if big else 0.016)
		# fade in at the top and out at the bottom: never cut by the edge
		var fade := clampf(minf(y - m, 1.0 - m - y) / 0.08, 0.0, 1.0)
		var col: Color = q["c"]
		# tumbling: the paper turns over (narrower, darker when edge-on)
		var flip := cos(t * float(q["f"]) + float(q["ph"]))
		col = col.darkened(0.25 * (1.0 - absf(flip)))
		col.a *= fade
		draw_set_transform(p, rot, Vector2(maxf(0.15, absf(flip)), 1.0))
		draw_rect(Rect2(-s * float(q["len"]), -s * 0.5, s * 2.0 * float(q["len"]), s), col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The frame, drawn last so nothing paints over it: a bright inner line in
## the frame colour and a fine outer one.
func _draw_frame() -> void:
	var rad := int(minf(corner(), minf(size.x, size.y) * 0.5))
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_corner_radius_all(rad)
	sb.border_color = Color(frame_col, 0.95)
	sb.set_border_width_all(3 if big else 2)
	sb.anti_aliasing = true
	sb.corner_detail = 12
	draw_style_box(sb, Rect2(Vector2.ZERO, size))
	var inner := StyleBoxFlat.new()
	inner.draw_center = false
	inner.set_corner_radius_all(maxi(0, rad - 6))
	inner.border_color = Color(frame_col.lightened(0.4), 0.28)
	inner.set_border_width_all(1)
	inner.anti_aliasing = true
	inner.corner_detail = 12
	draw_style_box(inner, Rect2(Vector2(6, 6), size - Vector2(12, 12)))


## The light sweep: a soft diagonal band crossing the poster every few
## seconds, over the text and buttons too (added light).
class Sweep:
	extends Control
	var poster: GlamPoster

	func _ready() -> void:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m
		z_index = 1

	func _process(_d: float) -> void:
		if poster != null and poster.sweep_every > 0.0 and not UIKit.reduced_motion() and is_visible_in_tree():
			queue_redraw()

	func _draw() -> void:
		if poster == null or poster.sweep_every <= 0.0 or UIKit.reduced_motion():
			return
		var u := fmod(poster.t, poster.sweep_every) / 1.1   # 1.1 s to cross
		if u > 1.0:
			return
		var w := size.x * 0.16
		var x := lerpf(-w * 2.0, size.x + w, u)
		var slant := size.y * 0.35
		for k in 3:
			var ww := w * (1.0 - float(k) * 0.3)
			var a := 0.05 + 0.03 * float(k)
			var poly := PackedVector2Array([Vector2(x - ww * 0.5 + slant, 0), Vector2(x + ww * 0.5 + slant, 0),
				Vector2(x + ww * 0.5, size.y), Vector2(x - ww * 0.5, size.y)])
			for piece in Geometry2D.intersect_polygons(poly, poster.shape()):
				if piece.size() >= 3:
					draw_colored_polygon(piece, Color(1, 1, 1, a))
