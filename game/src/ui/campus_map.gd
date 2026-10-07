class_name CampusMap
extends Node
## The campus map's static picture, baked from the actual CampusLayout the
## first time a map is shown: the traced areas (lawns, fields, parking,
## woods, plazas), roads and paths in contrasting tones, every water's real
## outline with a light rim, building footprints with a drop shadow (start
## dorms warm), hedges.  It is drawn once into an off-screen canvas (no
## per-frame drawing, no readback) and reused for the session; the layout is
## the only input, so the picture can't drift from the campus.
##
## The full map shows the whole map.  The minimap is a window centred on
## you (mini_span() metres to its rim: the reference campus is about a
## kilometre across, Moonbrook College about 300 m) cut from a sharper
## bake; markers beyond its rim sit on the rim, pointing the way.
##
## One map at a time: use(layout) points the transforms at a map's bounds;
## changing map frees the other map's pictures (nothing of two maps is kept).
##
## Live things (you, your team, tonight's waters, the dorm, last-seen
## opponents, carts, splash cues) are drawn on top by MatchHUD.MapPainter
## with the same world -> map transforms.

## Fraction of the half-size kept as a margin around the campus.
const PAD := 0.02
const FULL_PX := 1024
const MINI_PX := 2048
static var _inst: CampusMap
var _vps: Dictionary = {}     # px -> SubViewport (the current map's)
var bakes := 0                # tests: how many pictures were rendered
## the map the transforms and pictures are for
static var _map := ""
static var _bounds := Rect2(-720.0, -560.0, 1190.0, 1000.0)
static var _span := 130.0


## Points the transforms at a layout's map (every bake and overlay of a
## round goes through this first).
static func use(layout: CampusLayout) -> void:
	if layout == null:
		return
	_bounds = layout.bounds
	_span = float(CampusMaps.def(layout.map_id).get("mini_span", 130.0))
	if layout.map_id != _map:
		_map = layout.map_id
		if _inst != null and is_instance_valid(_inst):
			_inst._drop()


## The minimap: metres from its centre (you) to its rim, on this map.
static func mini_span() -> float:
	return _span


## The current map's centre (the minimap's focus before you have a place).
static func centre() -> Vector2:
	return _bounds.get_center()


func _drop() -> void:
	for px in _vps:
		var vp: SubViewport = _vps[px]
		if is_instance_valid(vp):
			vp.queue_free()
	_vps.clear()


static func shared() -> CampusMap:
	if _inst == null or not is_instance_valid(_inst):
		_inst = CampusMap.new()
		_inst.name = "CampusMap"
		(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_inst)
	return _inst


## World XZ -> map position for a map square of half-size `half` centred on
## `c` showing the whole campus (canvas units or texture pixels; the bake
## and the overlays share it).
static func to_map(p: Vector2, c: Vector2, half: float) -> Vector2:
	var b := _bounds
	var s := (half * 2.0 * (1.0 - PAD)) / maxf(b.size.x, b.size.y)
	return c + (p - b.get_center()) * s


## Metres -> map units at that size (whole-campus view).
static func m_to_map(m: float, half: float) -> float:
	var b := _bounds
	return m * (half * 2.0 * (1.0 - PAD)) / maxf(b.size.x, b.size.y)


## World XZ -> map position for a window centred on `focus` whose rim is
## `span` metres away (the minimap).
static func to_view(p: Vector2, c: Vector2, half: float, focus: Vector2, span: float) -> Vector2:
	return c + (p - focus) * (half / span)


## The texture coordinate (0..1) of a world point in a whole-campus bake.
static func uv_of(p: Vector2) -> Vector2:
	return to_map(p, Vector2(0.5, 0.5), 0.5)


## The baked picture at `px` pixels square (rendered on first use, then kept).
func texture(layout: CampusLayout, px: int) -> Texture2D:
	use(layout)
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

	const AREA_COL := {"field_turf": Color("24493a"), "field_grass": Color("21443a"), "track": Color("5a3c3a"),
		"court": Color("2c4a5a"), "infield": Color("4e4234"), "parking": Color("2a3046"), "plaza": Color("3a4456"),
		"woods": Color("15302c"), "farm": Color("2b3a2c"), "construction": Color("4a4238"), "bed": Color("1a3a2a"),
		"gravel": Color("3e4048"), "sand": Color("4e4a3e"), "yard": Color("1f3a35")}

	func _poly(pts: PackedVector2Array, col: Color) -> void:
		if pts.size() >= 3 and not Geometry2D.triangulate_polygon(pts).is_empty():
			draw_colored_polygon(pts, col)

	func _draw() -> void:
		var L := layout
		var half := size.x * 0.5
		var c := size * 0.5
		var m := func(p: Vector2) -> Vector2: return CampusMap.to_map(p, c, half)
		var k := CampusMap.m_to_map(1.0, half)    # map units per metre
		var mp := func(poly: PackedVector2Array) -> PackedVector2Array:
			var out := PackedVector2Array()
			for q in poly:
				out.append(m.call(q))
			return out
		# ground: the world beyond the play area darker, the play area calm
		draw_rect(Rect2(Vector2.ZERO, size), Color("0f1b2e"))
		var b := L.bounds
		var g0: Vector2 = m.call(b.position)
		var g1: Vector2 = m.call(b.end)
		draw_rect(Rect2(g0, g1 - g0), Color("142a2c"))
		_poly(mp.call(L.play_boundary), Color("1a3537"))
		# areas (larger first so small beds and plazas sit on top)
		var areas := L.areas.duplicate()
		areas.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return absf(CampusData.area(x["poly"])) > absf(CampusData.area(y["poly"])))
		for a in areas:
			var col: Color = AREA_COL.get(String(a["kind"]), Color(0, 0, 0, 0))
			if col.a > 0.0:
				_poly(mp.call(a["poly"]), col)
		# tree crowns: soft discs read as groves
		for t in L.trees:
			if String(t["kind"]) == "shrub":
				continue
			draw_circle(m.call(t["pos"]), maxf(float(t.get("r", 3.0)), 2.0) * k, Color("17332e"))
		# roads: a darker kerb under a calm road tone, round joints
		for pass_i in 2:
			for r in L.roads:
				var pts: PackedVector2Array = r["pts"]
				var w: float = float(r["w"]) * k + (1.4 * k if pass_i == 0 else 0.0)
				var col2 := Color("1f2a44") if pass_i == 0 else Color("33415f")
				for i in pts.size() - 1:
					draw_line(m.call(pts[i]), m.call(pts[i + 1]), col2, maxf(w, 1.0), true)
				for p in pts:
					draw_circle(m.call(p), maxf(w, 1.0) * 0.5, col2)
		# footpaths in a warm stone tone
		for pth in L.paths:
			var pts2: PackedVector2Array = pth["pts"]
			var col3 := Color("7d7666")
			var w2: float = maxf(maxf(float(pth["w"]), 2.0) * k, 1.0)
			for i in pts2.size() - 1:
				draw_line(m.call(pts2[i]), m.call(pts2[i + 1]), col3, w2, true)
			for p in pts2:
				draw_circle(m.call(p), w2 * 0.5, col3)
		# hedges
		for h in L.hedges:
			draw_line(m.call(h["a"]), m.call(h["b"]), Color("1f4a36"), maxf(float(h["t"]) * k, 1.0), true)
		# waters: a light rim, the water, a lighter inner tone
		for wt in L.waters:
			for poly in wt["polys"]:
				var pp: PackedVector2Array = mp.call(poly)
				var rim := CampusData.offset(poly, maxf(0.9, 1.2 / maxf(k, 0.01)))
				_poly(mp.call(rim) if rim.size() >= 3 else pp, Color("9fd6f2"))
				_poly(pp, Color("2c6aa3"))
				var inner := CampusData.offset(poly, -maxf(2.0, sqrt(absf(CampusData.area(poly))) * 0.18))
				if inner.size() >= 3:
					_poly(mp.call(inner), Color("3a80c0"))
		# buildings: footprints with a drop shadow; start dorms warm
		var dorm_b: Dictionary = {}
		for id in CampusDorms.ids(L.map_id):
			dorm_b[String(CampusDorms.geometry(id).get("building", ""))] = true
		var sh := Vector2(1.0, 1.4) * maxf(k, 0.6)
		for bd in L.buildings:
			var bp: PackedVector2Array = mp.call(bd["poly"])
			var shadow := PackedVector2Array()
			for q in bp:
				shadow.append(q + sh)
			_poly(shadow, Color(0.02, 0.04, 0.08, 0.55))
		for bd in L.buildings:
			var bp2: PackedVector2Array = mp.call(bd["poly"])
			var dorm := dorm_b.has(String(bd["id"]))
			var fill := Color("d99a5e") if dorm else (Color("4a5470") if bool(bd["background"]) else Color("6b7694"))
			_poly(bp2, fill)
			var ring := bp2.duplicate()
			if ring.size() >= 2:
				ring.append(ring[0])
				draw_polyline(ring, Color("ffd99a") if dorm else fill.lightened(0.25), maxf(0.5 * k, 1.0), true)


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
