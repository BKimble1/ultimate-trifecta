class_name CampusMap
extends Node
## The campus map's static picture (V5), baked from the actual CampusLayout
## the first time a map is shown: softened building footprints with a drop
## shadow, roads and paths in contrasting tones, groves as soft regions,
## water shapes with a light rim, plazas, hedges and calm ground.  It is drawn
## once into an off-screen canvas (no per-frame road/building drawing, no
## readback) and reused by the minimap and the full map for the session; the
## layout is the only input, so the picture can't drift from the campus.
##
## Live things (you, your team, tonight's waters, the dorm, last-seen
## opponents, carts, splash cues) are drawn on top by MatchHUD.MapPainter,
## with the same world -> map transform (to_map) the bake uses.

## Fraction of the half-size kept as a margin around the campus.
const PAD := 0.045
const FULL_PX := 1024
const MINI_PX := 384

static var _inst: CampusMap
var _vps: Dictionary = {}     # px -> SubViewport
var bakes := 0                # tests: how many pictures were rendered


static func shared() -> CampusMap:
	if _inst == null or not is_instance_valid(_inst):
		_inst = CampusMap.new()
		_inst.name = "CampusMap"
		(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_inst)
	return _inst


## World XZ -> map position for a map square of half-size `half` centred on
## `c` (canvas units or texture pixels; the bake and the overlays share it).
static func to_map(p: Vector2, c: Vector2, half: float) -> Vector2:
	var b := CampusLayout.BOUNDS
	var s := (half * 2.0 * (1.0 - PAD)) / maxf(b.size.x, b.size.y)
	return c + (p - b.get_center()) * s


## Metres -> map units at that size.
static func m_to_map(m: float, half: float) -> float:
	var b := CampusLayout.BOUNDS
	return m * (half * 2.0 * (1.0 - PAD)) / maxf(b.size.x, b.size.y)


## The baked picture at `px` pixels square (rendered on first use, then kept).
func texture(layout: CampusLayout, px: int) -> Texture2D:
	if _vps.has(px):
		return (_vps[px] as SubViewport).get_texture()
	var vp := SubViewport.new()
	vp.size = Vector2i(px, px)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var b := Bake.new()
	b.layout = layout
	b.size = Vector2(px, px)
	vp.add_child(b)
	if is_inside_tree():
		add_child(vp)
	else:
		add_child.call_deferred(vp)
	_vps[px] = vp
	bakes += 1
	return vp.get_texture()


## Everything static, in texture pixels.
class Bake:
	extends Control
	var layout: CampusLayout

	func _draw() -> void:
		var L := layout
		var half := size.x * 0.5
		var c := size * 0.5
		var m := func(p: Vector2) -> Vector2: return CampusMap.to_map(p, c, half)
		var k := CampusMap.m_to_map(1.0, half)    # map units per metre
		# frame and ground
		draw_style_box(UIKit.box(Color("0f1b2e"), int(size.x * 0.03)), Rect2(Vector2.ZERO, size))
		var b := CampusLayout.BOUNDS
		var g0: Vector2 = m.call(b.position)
		var g1: Vector2 = m.call(b.end)
		draw_style_box(UIKit.box(Color("1a3537"), int(8.0 * k)), Rect2(g0, g1 - g0))
		# groves: overlapping soft discs read as wooded regions
		for t in L.trees:
			var tp: Vector2 = t["pos"]
			draw_circle(m.call(tp), maxf(float(t.get("r", 1.0)) * 1.7, 3.4) * k, Color("15302c"))
		for t in L.trees:
			var tp2: Vector2 = t["pos"]
			draw_circle(m.call(tp2) + Vector2(-0.6, -0.6) * k, maxf(float(t.get("r", 1.0)) * 1.1, 2.2) * k, Color("1b3b33"))
		# plazas
		for pz in L.plazas:
			var pc: Vector2 = pz["center"]
			if String(pz["shape"]) == "circle":
				draw_circle(m.call(pc), float(pz["radius"]) * k, Color("3a4456"))
			else:
				var ps: Vector2 = pz["size"]
				draw_style_box(UIKit.box(Color("3a4456"), int(2.0 * k)), Rect2(m.call(pc - ps * 0.5), ps * k))
		# roads: a darker kerb under a calm road tone, round joints
		for pass_i in 2:
			for r in L.roads:
				var pts: PackedVector2Array = r["pts"]
				var w: float = float(r["w"]) * k + (1.4 * k if pass_i == 0 else 0.0)
				var col := Color("1f2a44") if pass_i == 0 else Color("33415f")
				for i in pts.size() - 1:
					draw_line(m.call(pts[i]), m.call(pts[i + 1]), col, w, true)
				for p in pts:
					draw_circle(m.call(p), w * 0.5, col)
		# footpaths in a warm stone tone (gravel a little darker)
		for pth in L.paths:
			var pts2: PackedVector2Array = pth["pts"]
			var pcol: Color = pth.get("color", Color(0.66, 0.62, 0.56))
			var col2 := Color("8d8574").lerp(pcol, 0.35).darkened(0.18)
			var w2: float = maxf(float(pth["w"]), 2.4) * k
			for i in pts2.size() - 1:
				draw_line(m.call(pts2[i]), m.call(pts2[i + 1]), col2, w2, true)
			for p in pts2:
				draw_circle(m.call(p), w2 * 0.5, col2)
		# hedges
		for h in L.hedges:
			draw_line(m.call(h["a"]), m.call(h["b"]), Color("1f4a36"), maxf(float(h["t"]), 1.0) * k, true)
		# waters: shape, a lighter inner tone and a light rim
		for wt in L.waters:
			_water(wt, m, k)
		# buildings: soft footprints with a drop shadow; the dorm is warm
		for bd in L.buildings:
			var bp: Vector2 = bd["pos"]
			var bs: Vector2 = bd["size"]
			var r := Rect2(m.call(bp - bs * 0.5), bs * k)
			var rad := int(clampf(1.4 * k, 2.0, 12.0))
			draw_style_box(UIKit.box(Color(0.02, 0.04, 0.08, 0.55), rad), Rect2(r.position + Vector2(1.0, 1.4) * k, r.size))
			var dorm := bool(bd.get("dorm", false))
			var roof: Color = bd.get("roof", Color(0.3, 0.3, 0.4))
			var fill := Color("d99a5e") if dorm else roof.lerp(Color("55607e"), 0.55).lightened(0.12)
			var sb := UIKit.box(fill, rad)
			sb.set_border_width_all(maxi(1, int(0.5 * k)))
			sb.border_color = Color("ffd99a") if dorm else fill.lightened(0.25)
			draw_style_box(sb, r)

	func _water(w: Dictionary, m: Callable, k: float) -> void:
		var c: Vector2 = m.call(w["center"])
		var deep := Color("2c6aa3")
		var light := Color("3f8bc9")
		var rim := Color("9fd6f2")
		match String(w["shape"]):
			"circle":
				var r := float(w["radius"]) * k
				draw_circle(c, r + 0.9 * k, rim)
				draw_circle(c, r, deep)
				draw_circle(c + Vector2(-0.2, -0.25) * r, r * 0.55, light)
			"ellipse":
				var rx := float(w["rx"]) * k
				var rz := float(w["rz"]) * k
				for layer in [[1.0 + 0.9 * k / rx, rim], [1.0, deep], [0.55, light]]:
					var pts := PackedVector2Array()
					var f: float = layer[0]
					for i in 40:
						var a := TAU * float(i) / 40.0
						pts.append(c + Vector2(cos(a) * rx, sin(a) * rz) * f + (Vector2(-0.2 * rx, -0.25 * rz) if f < 0.9 else Vector2.ZERO))
					draw_colored_polygon(pts, layer[1])
			_:
				var s: Vector2 = (w["size"] as Vector2) * k
				var rad := int(clampf(1.2 * k, 2.0, 10.0))
				var rr := UIKit.box(rim, rad + 1)
				draw_style_box(rr, Rect2(c - s * 0.5 - Vector2.ONE * 0.9 * k, s + Vector2.ONE * 1.8 * k))
				draw_style_box(UIKit.box(deep, rad), Rect2(c - s * 0.5, s))
				draw_style_box(UIKit.box(light, rad), Rect2(c - s * 0.5 + s * Vector2(0.12, 0.12), s * 0.5))


## Greedy label placement (full map): each label takes the first of four
## spots around its anchor that overlaps nothing placed so far and stays on
## the map; labels that fit nowhere are left out (the side panel lists
## everything).  requests: [{at, text, size, prio, col, r}] (r: marker radius).
static func place_labels(requests: Array, font: Font, bounds: Rect2, blocked: Array) -> Array:
	var placed: Array = []
	var taken: Array = blocked.duplicate()
	var reqs := requests.duplicate()
	reqs.sort_custom(func(a: Dictionary, b2: Dictionary) -> bool: return int(a["prio"]) > int(b2["prio"]))
	for rq in reqs:
		var sz := font.get_string_size(String(rq["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(rq["size"]))
		sz += Vector2(10, 4)
		var at: Vector2 = rq["at"]
		var r := float(rq.get("r", 8.0)) + 4.0
		for off in [Vector2(r, -sz.y * 0.5), Vector2(-r - sz.x, -sz.y * 0.5), Vector2(-sz.x * 0.5, r), Vector2(-sz.x * 0.5, -r - sz.y)]:
			var rect := Rect2(at + off, sz)
			if not bounds.encloses(rect):
				continue
			var clash := false
			for o in taken:
				if (o as Rect2).intersects(rect):
					clash = true
					break
			if clash:
				continue
			taken.append(rect)
			placed.append({"rect": rect, "text": rq["text"], "size": rq["size"], "col": rq["col"]})
			break
	return placed
