class_name CommerceArt
extends RefCounted
## Drawn art for the V6 Shop, Locker and Season Pass: the gold Coin, the
## navigation glyphs (bag, pass ticket, hanger), Season badge emblems and
## name cards.  Vector drawing like Icons (no textures, crisp at any size);
## kept separate from Icons so the commerce screens own their look.

const GOLD := Color("ffc65c")
const GOLD_DEEP := Color("d9952e")
const GOLD_HI := Color("fff0c2")


## The Coin: a gold disc with a rim, an inner ring and a small gloss.
static func coin(ci: CanvasItem, c: Vector2, r: float, dim: bool = false) -> void:
	var a := 0.55 if dim else 1.0
	ci.draw_circle(c + Vector2(0, r * 0.12), r, Color(GOLD_DEEP.darkened(0.35), a))
	ci.draw_circle(c, r, Color(GOLD_DEEP, a))
	ci.draw_circle(c, r * 0.84, Color(GOLD, a))
	ci.draw_arc(c, r * 0.6, 0, TAU, 28, Color(GOLD_DEEP, 0.85 * a), maxf(1.0, r * 0.1), true)
	ci.draw_arc(c, r * 0.72, PI * 1.08, PI * 1.55, 10, Color(GOLD_HI, 0.9 * a), maxf(1.0, r * 0.12), true)


## Navigation and shop glyphs.  kind: "bag", "pass", "hanger", "coins",
## "restore", "lantern", "moon", "owl", plus every Icons shape.
static func glyph(ci: CanvasItem, kind: String, c: Vector2, r: float, col: Color) -> void:
	match kind:
		"bag":
			var body := PackedVector2Array([c + Vector2(-r * 0.78, -r * 0.3), c + Vector2(r * 0.78, -r * 0.3),
				c + Vector2(r * 0.66, r * 0.9), c + Vector2(-r * 0.66, r * 0.9)])
			ci.draw_colored_polygon(body, col)
			ci.draw_arc(c + Vector2(0, -r * 0.32), r * 0.4, PI, TAU, 16, col, r * 0.16, true)
			ci.draw_circle(c + Vector2(-r * 0.36, -r * 0.08), r * 0.08, Color(0.07, 0.1, 0.17))
			ci.draw_circle(c + Vector2(r * 0.36, -r * 0.08), r * 0.08, Color(0.07, 0.1, 0.17))
		"pass":
			# a ticket: a rounded plate, a perforation line and a star
			var rect := Rect2(c - Vector2(r * 0.95, r * 0.68), Vector2(r * 1.9, r * 1.36))
			var sb := StyleBoxFlat.new()
			sb.bg_color = col
			sb.set_corner_radius_all(int(maxf(2.0, r * 0.22)))
			sb.anti_aliasing = true
			ci.draw_style_box(sb, rect)
			var dark := Color(0.07, 0.1, 0.17)
			for i in 4:
				ci.draw_circle(c + Vector2(r * 0.42, -r * 0.45 + float(i) * r * 0.3), r * 0.06, dark)
			Icons.draw_shape(ci, "star", c + Vector2(-r * 0.22, 0), r * 0.4, dark)
		"hanger":
			ci.draw_arc(c + Vector2(0, -r * 0.62), r * 0.2, PI * 0.9, PI * 2.4, 12, col, r * 0.14, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(0, -r * 0.42), c + Vector2(-r * 0.95, r * 0.45), c + Vector2(r * 0.95, r * 0.45),
				c + Vector2(0, -r * 0.42)]), col, r * 0.16, true)
		"coins":
			coin(ci, c + Vector2(-r * 0.3, r * 0.15), r * 0.62)
			coin(ci, c + Vector2(r * 0.3, -r * 0.18), r * 0.62)
		"restore":
			Icons.draw_shape(ci, "rotate", c, r, col)
		"lantern":
			ci.draw_rect(Rect2(c + Vector2(-r * 0.45, -r * 0.45), Vector2(r * 0.9, r * 1.15)), col)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.25, -r * 0.3), Vector2(r * 0.5, r * 0.85)), Color(1.0, 0.95, 0.75))
			ci.draw_rect(Rect2(c + Vector2(-r * 0.55, -r * 0.6), Vector2(r * 1.1, r * 0.18)), col)
			ci.draw_arc(c + Vector2(0, -r * 0.62), r * 0.25, PI, TAU, 10, col, r * 0.1, true)
		"moon":
			ci.draw_circle(c, r * 0.85, col)
			ci.draw_circle(c + Vector2(r * 0.38, -r * 0.22), r * 0.7, Color(0.07, 0.1, 0.17))
		"owl":
			ci.draw_circle(c + Vector2(0, r * 0.15), r * 0.82, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.75, -r * 0.35), c + Vector2(-r * 0.5, -r * 0.95), c + Vector2(-r * 0.25, -r * 0.5)]), col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.75, -r * 0.35), c + Vector2(r * 0.5, -r * 0.95), c + Vector2(r * 0.25, -r * 0.5)]), col)
			for sx in [-1.0, 1.0]:
				ci.draw_circle(c + Vector2(sx * r * 0.33, 0), r * 0.27, Color(1, 1, 1, 0.95))
				ci.draw_circle(c + Vector2(sx * r * 0.33, 0), r * 0.13, Color(0.07, 0.1, 0.17))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.1, r * 0.2), c + Vector2(r * 0.1, r * 0.2), c + Vector2(0, r * 0.42)]), GOLD_DEEP)
		_:
			Icons.draw_shape(ci, kind, c, r, col)


## A Season badge emblem: a round plate in the badge colour with its icon.
static func badge(ci: CanvasItem, id: String, c: Vector2, r: float) -> void:
	var it := Catalogue.item(id)
	var col := Color(String(it.get("color", "5fd6c8")))
	ci.draw_circle(c + Vector2(0, r * 0.08), r, Color(0, 0.02, 0.06, 0.35))
	ci.draw_circle(c, r, col.darkened(0.45))
	ci.draw_circle(c, r * 0.86, col.darkened(0.2))
	ci.draw_arc(c, r * 0.93, 0, TAU, 32, Color(col.lightened(0.4), 0.9), maxf(1.0, r * 0.08), true)
	glyph(ci, String(it.get("icon", "star")), c, r * 0.5, col.lightened(0.55))


## A name card: the plate in its colours with the player's name and an
## optional badge.  Used by the Locker preview, the profile chip and Season
## reward cards.
static func name_card(ci: CanvasItem, rect: Rect2, card_id: String, player_name: String, badge_id: String = "", font_size: int = 22) -> void:
	var it := Catalogue.item(card_id)
	var cols: Array = it.get("colors", ["1b2740", "26355a"])
	var top := Color(String(cols[0]))
	var bot := Color(String(cols[1])) if cols.size() > 1 else top
	var accent := Color(String(it.get("accent", "f6f3ec")))
	var sb := UIKit.box(top, int(minf(rect.size.y * 0.3, 18.0)), 0)
	ci.draw_style_box(sb, rect)
	# a soft diagonal blend toward the second colour
	var steps := 10
	for i in steps:
		var t := float(i) / float(steps)
		var x := rect.position.x + rect.size.x * (0.35 + t * 0.65)
		var w := rect.size.x * 0.065 + 1.0
		ci.draw_rect(Rect2(Vector2(x, rect.position.y + 3), Vector2(minf(w, rect.end.x - x - 3), rect.size.y - 6)), Color(bot, 0.12 + t * 0.55))
	if bool(it.get("stars", false)):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(card_id)
		for i in 14:
			var p := rect.position + Vector2(rng.randf_range(0.08, 0.95) * rect.size.x, rng.randf_range(0.15, 0.85) * rect.size.y)
			ci.draw_circle(p, rng.randf_range(0.8, 1.8), Color(1, 1, 1, rng.randf_range(0.35, 0.8)))
	ci.draw_line(rect.position + Vector2(14, rect.size.y - 7), Vector2(rect.end.x - 14, rect.end.y - 7), Color(accent, 0.75), 2.0, true)
	var x0 := rect.position.x + 16.0
	if badge_id != "":
		var br := rect.size.y * 0.3
		badge(ci, badge_id, Vector2(x0 + br, rect.get_center().y), br)
		x0 += br * 2.0 + 10.0
	if player_name != "":
		var f := UIKit.font_w(700)
		var asc := f.get_ascent(font_size)
		ci.draw_string(f, Vector2(x0, rect.get_center().y + asc * 0.36), player_name, HORIZONTAL_ALIGNMENT_LEFT,
			rect.end.x - x0 - 12.0, font_size, Color.WHITE)


## A Control that draws a coin, a glyph, a badge or a name card in its rect.
class Pic:
	extends Control
	var kind := "coin"          # coin | glyph | badge | card
	var id := ""
	var col := Color.WHITE
	var text := ""
	var dim := false

	func _init(k: String = "coin", i: String = "", c: Color = Color.WHITE, size_units: float = 32.0) -> void:
		kind = k
		id = i
		col = c
		custom_minimum_size = Vector2(size_units, size_units)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.45
		match kind:
			"coin":
				CommerceArt.coin(self, c, r, dim)
			"glyph":
				CommerceArt.glyph(self, id, c, r, col)
			"badge":
				CommerceArt.badge(self, id, c, r)
			"card":
				CommerceArt.name_card(self, Rect2(Vector2.ZERO, size), id, text, "", int(clampf(size.y * 0.28, 14.0, 24.0)))
