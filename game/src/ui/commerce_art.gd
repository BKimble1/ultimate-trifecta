class_name CommerceArt
extends RefCounted
## Drawn art for the Shop, Locker and Season Pass: the gold Coin and Coin
## piles, the navigation glyphs (bag, pass ticket, hanger), Season badge
## emblems and name cards.  Vector drawing like Icons (no textures, crisp at
## any size); kept separate from Icons so the commerce screens own their look.
##
## V7: one light (from the upper left) for every piece: a darker edge below,
## a rim, the face and a narrow highlight.  Coins carry the game's crescent;
## badges are medallions with ribbon tails and an engraved emblem; a name
## card is drawn as it appears when equipped (the player's name, their badge,
## the card's own motif), never as an empty strip.  Thumbnails of runner
## items are rendered from preview_look(): the item on the player's look with
## neutral accessories, so an outfit's picture never shows the player's own
## nightcap and slippers as if they came with it.

const GOLD := Color("ffc65c")
const GOLD_DEEP := Color("d9952e")
const GOLD_HI := Color("fff0c2")
const INK := Color(0.07, 0.1, 0.17)

## The shoes worn in outfit pictures (plain high-tops: the outfit reads,
## the shoes don't; an outfit with its own footwear keeps it).
const PREVIEW_SHOES := "sneakers"
## Sample name for a name card when the player has none yet.
const SAMPLE_NAME := "Your Name"

## Each name card's motif (art only; the catalogue gives its colours).
const CARD_MOTIF := {
	"card:after_hours": "moon", "card:moonlit_quad": "quad", "card:dawn_patrol": "sun",
	"card:lantern_glow": "lantern", "card:starfield": "stars", "card:library_lamp": "lamp",
	"card:glow_track": "track", "card:night_sky": "moon",
}


## The look a runner item's picture is rendered with: `base` (the player's
## look) wearing `field` = `key`.  Outfits and patterns are shown without a
## hat and in plain shoes; a hairstyle without a hat; hats, shoes and faces on
## the player's own look.  The emote is fixed so equal pictures share a cache
## entry.  The live preview on the stage always uses the real look.
static func preview_look(base: Dictionary, field: String, key: String) -> Dictionary:
	var look: Dictionary = Cosmetics.sanitize(base).duplicate()
	look[field] = key
	match field:
		"outfit", "pattern":
			look["hat"] = "none"
			look["shoes"] = PREVIEW_SHOES
		"hair":
			look["hat"] = "none"
	look["emote"] = "wave"
	return Cosmetics.sanitize(look)


## Portrait framing for a runner item's picture ("" = drawn art).
static func framing_for(field: String) -> String:
	match field:
		"outfit", "pattern":
			return "body"
		"hat":
			return "hat"
		"shoes":
			return "feet"
		"hair", "face", "brows", "marks":
			return "head"
	return ""


## The Coin: an edge below, a rim, the face with an engraved crescent, and a
## highlight.  `dim` mutes it toward the card (locked), never transparent.
static func coin(ci: CanvasItem, c: Vector2, r: float, dim: bool = false) -> void:
	var m := func(col: Color) -> Color: return col.lerp(Color("4a4f63"), 0.45) if dim else col
	ci.draw_circle(c + Vector2(0, r * 0.16), r, m.call(GOLD_DEEP.darkened(0.42)), true, -1.0, true)
	ci.draw_circle(c, r, m.call(GOLD_DEEP), true, -1.0, true)
	ci.draw_circle(c, r * 0.86, m.call(GOLD), true, -1.0, true)
	ci.draw_arc(c, r * 0.72, 0, TAU, 40, m.call(GOLD_DEEP.lerp(GOLD, 0.35)), maxf(1.0, r * 0.07), true)
	# the crescent, engraved: a shadow line and the shape
	_crescent(ci, c + Vector2(r * 0.03, r * 0.04), r * 0.4, m.call(GOLD_DEEP.darkened(0.12)))
	_crescent(ci, c, r * 0.4, m.call(GOLD_DEEP))
	ci.draw_arc(c, r * 0.78, PI * 1.08, PI * 1.5, 14, m.call(GOLD_HI), maxf(1.0, r * 0.1), true)


## A pile of Coins for a quantity: 1 coin up to 25, 2 up to 50, a small pile
## up to 500, a larger one beyond (the number itself is written by the caller).
static func coin_pile(ci: CanvasItem, c: Vector2, r: float, amount: int, dim: bool = false) -> void:
	var layout: Array = [[0.0, 0.0]]
	if amount > 25:
		layout = [[-0.42, 0.18], [0.42, -0.1]]
	if amount > 50:
		layout = [[-0.62, 0.3], [0.62, 0.3], [0.0, -0.16]]
	if amount > 500:
		layout = [[-0.95, 0.42], [0.0, 0.42], [0.95, 0.42], [-0.48, -0.08], [0.48, -0.08]]
	if amount > 1500:
		layout = [[-1.2, 0.5], [-0.4, 0.5], [0.4, 0.5], [1.2, 0.5], [-0.8, 0.02], [0.0, 0.02], [0.8, 0.02], [0.0, -0.46]]
	var k := 1.0 if layout.size() == 1 else (0.78 if layout.size() <= 3 else (0.6 if layout.size() <= 5 else 0.5))
	for p in layout:
		coin(ci, c + Vector2(float(p[0]), float(p[1])) * r * k, r * k, dim)


static func _crescent(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var n := 20
	for i in n + 1:
		var a := lerpf(PI * 0.3, PI * 1.7, float(i) / n)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	var inner := c + Vector2(r * 0.42, -r * 0.08)
	var a0 := (pts[n] - inner).angle()
	var a1 := (pts[0] - inner).angle()
	if a1 > a0:
		a1 -= TAU
	for i in range(1, n):
		pts.append(inner + Vector2(cos(lerpf(a0, a1, float(i) / n)), sin(lerpf(a0, a1, float(i) / n))) * r * 0.8)
	ci.draw_colored_polygon(pts, col)


## Navigation and shop glyphs.  kind: "bag", "pass", "hanger", "coins",
## "restore", "lantern", "moon", "owl", "whistle", "drop", "lamp", "quad",
## "sun", "track", "stars", plus every Icons shape.
static func glyph(ci: CanvasItem, kind: String, c: Vector2, r: float, col: Color) -> void:
	match kind:
		"bag":
			var body := PackedVector2Array([c + Vector2(-r * 0.78, -r * 0.3), c + Vector2(r * 0.78, -r * 0.3),
				c + Vector2(r * 0.66, r * 0.9), c + Vector2(-r * 0.66, r * 0.9)])
			ci.draw_colored_polygon(body, col)
			ci.draw_arc(c + Vector2(0, -r * 0.32), r * 0.4, PI, TAU, 16, col, r * 0.16, true)
			ci.draw_circle(c + Vector2(-r * 0.36, -r * 0.08), r * 0.08, INK)
			ci.draw_circle(c + Vector2(r * 0.36, -r * 0.08), r * 0.08, INK)
		"pass":
			# a ticket: a rounded plate, a perforation line and a star
			var rect := Rect2(c - Vector2(r * 0.95, r * 0.68), Vector2(r * 1.9, r * 1.36))
			var sb := StyleBoxFlat.new()
			sb.bg_color = col
			sb.set_corner_radius_all(int(maxf(2.0, r * 0.22)))
			sb.anti_aliasing = true
			ci.draw_style_box(sb, rect)
			for i in 4:
				ci.draw_circle(c + Vector2(r * 0.42, -r * 0.45 + float(i) * r * 0.3), r * 0.06, INK)
			Icons.draw_shape(ci, "star", c + Vector2(-r * 0.22, 0), r * 0.4, INK)
		"hanger":
			ci.draw_arc(c + Vector2(0, -r * 0.62), r * 0.2, PI * 0.9, PI * 2.4, 12, col, r * 0.14, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(0, -r * 0.42), c + Vector2(-r * 0.95, r * 0.45), c + Vector2(r * 0.95, r * 0.45),
				c + Vector2(0, -r * 0.42)]), col, r * 0.16, true)
		"coins":
			coin(ci, c + Vector2(-r * 0.3, r * 0.15), r * 0.62)
			coin(ci, c + Vector2(r * 0.3, -r * 0.18), r * 0.62)
		"restore":
			Icons.draw_shape(ci, "rotate", c, r, col)
		"lantern", "lamp":
			# a hanging lantern (a reading lamp: a shade on a stand)
			if kind == "lamp":
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.62, -r * 0.05), c + Vector2(-r * 0.3, -r * 0.8),
					c + Vector2(r * 0.3, -r * 0.8), c + Vector2(r * 0.62, -r * 0.05)]), col)
				ci.draw_line(c + Vector2(0, -r * 0.05), c + Vector2(0, r * 0.72), col, r * 0.16, true)
				ci.draw_rect(Rect2(c + Vector2(-r * 0.45, r * 0.68), Vector2(r * 0.9, r * 0.2)), col)
				ci.draw_circle(c + Vector2(0, r * 0.06), r * 0.16, Color(1.0, 0.9, 0.6, col.a))
				return
			ci.draw_arc(c + Vector2(0, -r * 0.82), r * 0.18, 0, TAU, 12, col, r * 0.1, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.5, -r * 0.42), c + Vector2(0, -r * 0.7), c + Vector2(r * 0.5, -r * 0.42)]), col)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.42, -r * 0.42), Vector2(r * 0.84, r * 0.95)), col)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.28, -r * 0.3), Vector2(r * 0.56, r * 0.72)), Color(INK, col.a))
			ci.draw_circle(c + Vector2(0, r * 0.12), r * 0.2, Color(1.0, 0.82, 0.42, col.a))
			ci.draw_circle(c + Vector2(0, r * 0.02), r * 0.12, Color(1.0, 0.95, 0.75, col.a))
			ci.draw_rect(Rect2(c + Vector2(-r * 0.55, r * 0.53), Vector2(r * 1.1, r * 0.18)), col)
		"moon":
			_crescent(ci, c + Vector2(-r * 0.08, 0), r * 0.86, col)
			Icons.draw_shape(ci, "star", c + Vector2(r * 0.52, -r * 0.36), r * 0.26, col)
		"owl":
			ci.draw_circle(c + Vector2(0, r * 0.15), r * 0.8, col, true, -1.0, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.75, -r * 0.3), c + Vector2(-r * 0.52, -r * 0.92), c + Vector2(-r * 0.22, -r * 0.46)]), col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.75, -r * 0.3), c + Vector2(r * 0.52, -r * 0.92), c + Vector2(r * 0.22, -r * 0.46)]), col)
			for sx in [-1.0, 1.0]:
				ci.draw_circle(c + Vector2(sx * r * 0.33, 0), r * 0.27, Color(1, 1, 1, 0.95 * col.a), true, -1.0, true)
				ci.draw_circle(c + Vector2(sx * r * 0.33, 0), r * 0.13, Color(INK, col.a), true, -1.0, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.1, r * 0.2), c + Vector2(r * 0.1, r * 0.2), c + Vector2(0, r * 0.42)]), Color(GOLD_DEEP, col.a))
		"whistle":
			# a coach's whistle: the barrel, its mouthpiece, the ring and lanyard
			ci.draw_circle(c + Vector2(r * 0.12, r * 0.18), r * 0.58, col, true, -1.0, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.96, -r * 0.42), c + Vector2(r * 0.12, -r * 0.42),
				c + Vector2(r * 0.12, r * 0.06), c + Vector2(-r * 0.96, r * 0.06)]), col)
			ci.draw_circle(c + Vector2(r * 0.12, r * 0.18), r * 0.2, Color(INK, col.a), true, -1.0, true)
			ci.draw_arc(c + Vector2(r * 0.62, -r * 0.42), r * 0.2, 0, TAU, 14, col, r * 0.1, true)
		"drop":
			var pts := PackedVector2Array([c + Vector2(0, -r * 0.95)])
			for i in 17:
				var a := lerpf(-PI * 0.18, PI * 1.18, float(i) / 16.0)
				pts.append(c + Vector2(cos(a) * r * 0.6, sin(a) * r * 0.6 + r * 0.3))
			ci.draw_colored_polygon(pts, col)
			ci.draw_arc(c + Vector2(0, r * 0.3), r * 0.36, PI * 0.95, PI * 1.35, 8, Color(1, 1, 1, 0.45 * col.a), r * 0.1, true)
		"quad":
			# a moon over a campus roofline
			ci.draw_circle(c + Vector2(r * 0.4, -r * 0.45), r * 0.3, col, true, -1.0, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r, r * 0.8), c + Vector2(-r, r * 0.1), c + Vector2(-r * 0.6, -r * 0.2),
				c + Vector2(-r * 0.2, r * 0.1), c + Vector2(-r * 0.2, r * 0.2), c + Vector2(r * 0.3, r * 0.2), c + Vector2(r * 0.3, r * 0.0),
				c + Vector2(r * 0.6, r * 0.0), c + Vector2(r * 0.6, r * 0.25), c + Vector2(r, r * 0.25), c + Vector2(r, r * 0.8)]), col)
		"sun":
			# a rising sun with rays over the horizon
			var half := PackedVector2Array()
			for i in 17:
				var a := PI + PI * float(i) / 16.0
				half.append(c + Vector2(0, r * 0.4) + Vector2(cos(a), sin(a)) * r * 0.5)
			ci.draw_colored_polygon(half, col)
			for i in 5:
				var a2 := PI + PI * (float(i) + 0.5) / 5.0
				var d := Vector2(cos(a2), sin(a2))
				ci.draw_line(c + Vector2(0, r * 0.4) + d * r * 0.66, c + Vector2(0, r * 0.4) + d * r * 0.92, col, r * 0.1, true)
			ci.draw_line(c + Vector2(-r, r * 0.45), c + Vector2(r, r * 0.45), col, r * 0.08, true)
		"track":
			# running-track lanes curving away
			for i in 3:
				ci.draw_arc(c + Vector2(r * 1.1, r * 0.9), r * (0.9 + 0.32 * float(i)), PI * 1.0, PI * 1.5, 16, col, r * 0.09, true)
		"stars":
			for p in [[-0.5, -0.3, 0.32], [0.3, -0.55, 0.22], [0.45, 0.3, 0.36], [-0.25, 0.5, 0.18]]:
				Icons.draw_shape(ci, "star", c + Vector2(float(p[0]), float(p[1])) * r, r * float(p[2]), col)
		_:
			Icons.draw_shape(ci, kind, c, r, col)


## A Season badge emblem: a medallion in the badge colour with two ribbon
## tails, a notched rim, a lighter face and its emblem, lit from the upper
## left.  Fits the circle of radius `r` around `c`.
static func badge(ci: CanvasItem, id: String, c: Vector2, r: float, dim: bool = false) -> void:
	var it := Catalogue.item(id)
	var col := Color(String(it.get("color", "5fd6c8")))
	if dim:
		col = col.lerp(Color("5b6075"), 0.45)
	var m := r * 0.78        # medallion radius
	var mc := c + Vector2(0, -r * 0.14)
	# ribbon tails (behind)
	for sx in [-1.0, 1.0]:
		var base := mc + Vector2(sx * m * 0.38, m * 0.55)
		ci.draw_colored_polygon(PackedVector2Array([base + Vector2(-m * 0.2, 0), base + Vector2(m * 0.2, 0),
			base + Vector2(m * 0.2 + sx * m * 0.16, m * 0.72), base + Vector2(sx * m * 0.16, m * 0.56),
			base + Vector2(-m * 0.2 + sx * m * 0.16, m * 0.72)]), col.darkened(0.38))
	# shadow, notched rim, face
	ci.draw_circle(mc + Vector2(0, m * 0.1), m, Color(0, 0.02, 0.06, 0.35), true, -1.0, true)
	var rim := PackedVector2Array()
	for i in 48:
		var a := TAU * float(i) / 48.0
		rim.append(mc + Vector2(cos(a), sin(a)) * m * (1.0 if i % 2 == 0 else 0.93))
	ci.draw_colored_polygon(rim, col.darkened(0.3))
	ci.draw_circle(mc, m * 0.82, col.darkened(0.08), true, -1.0, true)
	ci.draw_circle(mc + Vector2(m * 0.06, m * 0.07), m * 0.74, col.darkened(0.2), true, -1.0, true)
	ci.draw_arc(mc, m * 0.82, PI * 1.05, PI * 1.6, 14, col.lightened(0.45), maxf(1.0, m * 0.07), true)
	# the emblem: engraved (a dark offset) in a pale tint of the colour
	var g := String(it.get("icon", "star"))
	glyph(ci, g, mc + Vector2(m * 0.04, m * 0.05), m * 0.44, Color(col.darkened(0.55), 0.8))
	glyph(ci, g, mc, m * 0.44, col.lightened(0.62))


## A name card as it appears when equipped: the plate in its colours (a
## smooth diagonal blend), its motif on the right, the badge (if any) on the
## left, and the player's name.  Used by the Locker, the Season Pass and the
## Shop.  An empty name draws the sample name.
static func name_card(ci: CanvasItem, rect: Rect2, card_id: String, player_name: String, badge_id: String = "", font_size: int = 22) -> void:
	var it := Catalogue.item(card_id)
	var cols: Array = it.get("colors", ["1b2740", "26355a"])
	var c0 := Color(String(cols[0]))
	var c1 := Color(String(cols[1])) if cols.size() > 1 else c0
	var accent := Color(String(it.get("accent", "f6f3ec")))
	var rad := minf(rect.size.y * 0.22, 16.0)
	# shadow, then the plate with its blend (per-vertex colours on a rounded rect)
	_rounded(ci, Rect2(rect.position + Vector2(0, maxf(2.0, rect.size.y * 0.05)), rect.size), rad, [Color(0, 0.02, 0.06, 0.4)])
	_rounded(ci, rect, rad, [c0, c1])
	ci.draw_arc(rect.position + Vector2(rad, rad), rad - 0.75, PI, PI * 1.5, 6, Color(1, 1, 1, 0.18), 1.5, true)
	ci.draw_line(rect.position + Vector2(rad, 0.75), Vector2(rect.end.x - rad, rect.position.y + 0.75), Color(1, 1, 1, 0.16), 1.5, true)
	# motif: restrained, in the accent colour, on the right
	var h := rect.size.y
	var motif := String(CARD_MOTIF.get(card_id, "stars" if bool(it.get("stars", false)) else "moon"))
	if bool(it.get("stars", false)):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(card_id)
		for i in 12:
			var p := rect.position + Vector2(rng.randf_range(0.45, 0.97) * rect.size.x, rng.randf_range(0.14, 0.86) * h)
			ci.draw_circle(p, rng.randf_range(0.7, 1.6) * maxf(1.0, h / 60.0), Color(1, 1, 1, rng.randf_range(0.3, 0.75)))
	if motif != "stars" or not bool(it.get("stars", false)):
		glyph(ci, motif, Vector2(rect.end.x - h * 0.42, rect.get_center().y), h * 0.26, Color(accent, 0.45))
	# badge slot and the name
	var x0 := rect.position.x + maxf(10.0, h * 0.22)
	if badge_id != "":
		var br := h * 0.32
		badge(ci, badge_id, Vector2(x0 + br, rect.get_center().y), br)
		x0 += br * 2.0 + h * 0.14
	var nm := player_name if player_name.strip_edges() != "" else SAMPLE_NAME
	var f := UIKit.font_w(800)
	var room := rect.end.x - x0 - h * 0.62
	# the plate shows the whole name: a long one is set a little smaller (it
	# is a picture of the card), and only a very long one is trimmed
	var fs := clampi(font_size, 12, int(maxf(12.0, h * 0.4)))
	var min_fs := maxi(11, int(fs * 0.62))
	while fs > min_fs and f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
		fs -= 1
	while nm.length() > 2 and f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
		nm = nm.substr(0, nm.length() - 2).strip_edges() + "…"
	var asc := f.get_ascent(fs)
	var desc := f.get_descent(fs)
	var base_y := rect.get_center().y + (asc - desc) * 0.5 - h * 0.04
	ci.draw_string(f, Vector2(x0, base_y + maxf(1.0, fs * 0.08)), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0.02, 0.06, 0.45))
	ci.draw_string(f, Vector2(x0, base_y), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("fbf8f1"))
	# a short accent rule under the name
	var w := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_line(Vector2(x0, base_y + desc + h * 0.06), Vector2(x0 + w * 0.42, base_y + desc + h * 0.06), accent, maxf(1.5, h * 0.035), true)


## A filled rounded rect; two colours make a diagonal blend.
static func _rounded(ci: CanvasItem, r: Rect2, rad: float, cols: Array) -> void:
	var pts := PackedVector2Array()
	var corners := [[r.end.x - rad, r.position.y + rad, -PI * 0.5], [r.end.x - rad, r.end.y - rad, 0.0],
		[r.position.x + rad, r.end.y - rad, PI * 0.5], [r.position.x + rad, r.position.y + rad, PI]]
	for cr in corners:
		for i in 7:
			var a := float(cr[2]) + PI * 0.5 * float(i) / 6.0
			pts.append(Vector2(float(cr[0]), float(cr[1])) + Vector2(cos(a), sin(a)) * rad)
	var a0: Color = cols[0]
	var a1: Color = cols[-1]
	var pc := PackedColorArray()
	for p in pts:
		var t := clampf(((p.x - r.position.x) / maxf(1.0, r.size.x)) * 0.75 + ((p.y - r.position.y) / maxf(1.0, r.size.y)) * 0.25, 0.0, 1.0)
		pc.append(a0.lerp(a1, t))
	ci.draw_polygon(pts, pc)


## A Control that draws a coin, a glyph, a badge or a name card in its rect.
class Pic:
	extends Control
	var kind := "coin"          # coin | glyph | badge | card
	var id := ""
	var col := Color.WHITE
	var text := ""
	var badge_id := ""
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
				CommerceArt.badge(self, id, c, r, dim)
			"card":
				# the plate keeps a name card's proportions inside the rect
				var h := minf(size.y, size.x / 2.6)
				var rr := Rect2(Vector2(0, (size.y - h) * 0.5), Vector2(size.x, h))
				CommerceArt.name_card(self, rr, id, text, badge_id, int(clampf(h * 0.36, 14.0, 28.0)))
