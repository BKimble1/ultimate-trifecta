class_name AlbumDisc
extends Button
## (2.2 build 16) An album in the Locker: its sleeve (the cover) with a
## disc sliding out of it (2.2 build 17: a gradient in the album's colours),
## grooves,
## a label ring and a centre hole.  The album playing has its disc out
## further and spinning, and says "Now playing"; a tap puts an album on.
## Painted (no extra images or shaders).

var album_id := ""
var cover: Texture2D
var col := Color.WHITE
var playing := false
var _spin := 0.0
var _out := 0.0      # 0..1 how far the disc slides out of the sleeve
var _title: Label
var _sub: Label


func setup(id: String, w: float) -> void:
	album_id = id
	var a := Albums.get_album(id)
	cover = Albums.cover(id)
	col = a["col"]
	name = "Album_" + id
	flat = true
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(w, w * 0.62 + 74.0)
	accessibility_name = "%s, album" % String(a["title"])
	_title = UIKit.styled(String(a["title"]), "label", UIKit.IVORY)
	_title.add_theme_font_size_override("font_size", 21)
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)
	_sub = UIKit.styled("", "caption", UIKit.IVORY_MUTED)
	_sub.add_theme_font_size_override("font_size", 17)
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sub)
	resized.connect(_layout)
	refresh()


## AutoGrid: the cell's width decides the disc's size.
func fit_cell(w: float, _lines: int) -> void:
	custom_minimum_size = Vector2(w, w * 0.62 + 74.0)


func refresh() -> void:
	playing = Albums.current() == album_id
	_sub.text = "Now playing" if playing else "Tap to play"
	_sub.add_theme_color_override("font_color", col if playing else UIKit.IVORY_MUTED)
	accessibility_name = "%s, album%s" % [Albums.title_of(album_id), ", now playing" if playing else ""]
	queue_redraw()


func _layout() -> void:
	var art_h := size.y - 74.0
	_title.position = Vector2(8, art_h + 8)
	_title.size = Vector2(size.x - 16, 28)
	_sub.position = Vector2(8, art_h + 38)
	_sub.size = Vector2(size.x - 16, 24)


func _process(delta: float) -> void:
	var want := 1.0 if playing else 0.0
	_out = move_toward(_out, want, delta * 2.2)
	if playing and not UIKit.reduced_motion():
		_spin = fmod(_spin + delta * TAU * 0.33, TAU)
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	var art_h := size.y - 74.0
	# the card
	var bg := UIKit.card_box(Color(UIKit.SLATE, 0.92), 18, 1.0, 16, 0.08)
	if playing:
		bg.border_color = Color(col, 0.9)
		bg.set_border_width_all(2)
	elif has_focus() or is_hovered():
		bg.border_color = Color(UIKit.IVORY, 0.35)
		bg.set_border_width_all(2)
	draw_style_box(bg, Rect2(Vector2.ZERO, size))
	var s := art_h - 20.0                      # sleeve side
	var sleeve := Rect2(Vector2(12, 10), Vector2(s, s))
	var r := s * 0.47
	var dc := sleeve.get_center() + Vector2(s * (0.22 + 0.3 * _ease(_out)), 0)   # the disc slides right
	# the disc (behind the sleeve's right half): rim, picture, grooves, label, hole
	draw_circle(dc + Vector2(3, 5), r, Color(0, 0, 0, 0.35))
	draw_circle(dc, r, Color("0e0f14"))
	_draw_picture(dc, r * 0.97)
	for k in 7:
		draw_arc(dc, r * (0.52 + 0.065 * k), 0, TAU, 48, Color(0, 0, 0, 0.18), 1.2, true)
	# the sheen: two light arcs that stay put while the disc turns
	draw_arc(dc, r * 0.8, -2.4, -1.6, 24, Color(1, 1, 1, 0.22), r * 0.12, true)
	draw_arc(dc, r * 0.8, 0.75, 1.4, 24, Color(1, 1, 1, 0.12), r * 0.08, true)
	draw_circle(dc, r * 0.2, Color(col.lightened(0.15), 1.0))
	draw_circle(dc, r * 0.2, Color(1, 1, 1, 0.08))
	draw_arc(dc, r * 0.2, 0, TAU, 32, Color(0, 0, 0, 0.35), 1.5, true)
	draw_circle(dc, r * 0.045, Color("0a0b10"))
	# the sleeve in front: the cover, a rim, a little shadow on its right edge
	draw_rect(Rect2(sleeve.position + Vector2(4, 6), sleeve.size), Color(0, 0, 0, 0.35))
	if cover:
		draw_texture_rect(cover, sleeve, false)
	else:
		_draw_house_sleeve(sleeve)
	draw_rect(sleeve, Color(1, 1, 1, 0.12), false, 1.5)
	draw_rect(Rect2(sleeve.end.x - 6, sleeve.position.y, 6, sleeve.size.y), Color(0, 0, 0, 0.18))
	if playing:
		# a small equaliser badge on the sleeve
		var bx := sleeve.position + Vector2(10, sleeve.size.y - 34)
		draw_style_box(UIKit.box(Color(UIKit.NAVY, 0.8), 8), Rect2(bx, Vector2(46, 26)))
		for i in 4:
			var hgt := 6.0 + 12.0 * absf(sin(_spin * 3.0 + float(i) * 1.3))
			draw_rect(Rect2(bx + Vector2(8 + i * 9, 21 - hgt), Vector2(5, hgt)), col)


static func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


## (2.2 build 17) The disc: one smooth gradient in the album's own colours
## (centre to rim), with a soft sheen band that turns with the disc.
func _draw_picture(c: Vector2, r: float) -> void:
	var a2: Color = Albums.get_album(album_id).get("col2", col.darkened(0.5))
	var n := 48
	# centre fan: col in the middle, col2 at the rim
	for i in n:
		var t0 := TAU * float(i) / float(n)
		var t1 := TAU * float(i + 1) / float(n)
		draw_polygon(PackedVector2Array([c, c + Vector2.from_angle(t0) * r, c + Vector2.from_angle(t1) * r]),
			PackedColorArray([col, a2, a2]))
	# a turning sheen: two lighter wedges opposite each other
	for k in 2:
		var base := _spin + PI * float(k)
		for j in 6:
			var u0 := base + 0.08 * float(j)
			var u1 := u0 + 0.08
			var alpha := 0.16 * (1.0 - absf(float(j) - 2.5) / 3.0)
			draw_polygon(PackedVector2Array([c, c + Vector2.from_angle(u0) * r, c + Vector2.from_angle(u1) * r]),
				PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, alpha), Color(1, 1, 1, alpha)]))


## The game's own album (no picture): a night-sky sleeve with a moon.
func _draw_house_sleeve(rect: Rect2) -> void:
	var top := Color("2b2a6e")
	var bot := Color("0f1a3c")
	var pts := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	draw_polygon(pts, PackedColorArray([top, top, bot, bot]))
	draw_circle(rect.position + rect.size * Vector2(0.7, 0.32), rect.size.x * 0.13, Color("fff1c4"))
	draw_circle(rect.position + rect.size * Vector2(0.75, 0.28), rect.size.x * 0.11, top.lerp(bot, 0.3))
	for i in 9:
		var sp := rect.position + rect.size * Vector2(fmod(0.13 + 0.37 * i, 0.9) + 0.05, fmod(0.21 + 0.29 * i, 0.55) + 0.08)
		draw_circle(sp, 2.0, Color(1, 1, 1, 0.7))
	var f := UIKit.font_w(800)
	draw_string(f, rect.position + Vector2(12, rect.size.x * 0.11 + 10), "DORM NIGHTS", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 24, int(rect.size.x * 0.11), UIKit.IVORY)
