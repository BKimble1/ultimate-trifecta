class_name CampusArchitecture
extends RefCounted
## Buildings, walls, hedges, fences, lamps, benches and props for the
## reference campus, generated from the traced data (visual only: every
## collider comes from CampusLayout via CampusBuilder.build_collision).
##
## A building is its footprint (or its parts, each a mass with its own
## height and roof) extruded with the game's established modular look:
## walls in their material on a dressed plinth, a moulded cornice, recessed
## windows with lit interiors that vary (warm lamps, cooler screens, curtains
## half drawn), frames, lintels and sills, roofs with thickness (flat behind
## a parapet, gable, hip, pyramid, dome, shed), and the real entrances (a
## lit door with a canopy, or a classical portico with columns and a
## pediment).  Windows follow each facade in bays per floor and skip walls
## another part of the same building stands against.  Background buildings
## (beyond the play boundary) get the cheap version: massing, roof and a
## scatter of lit windows.

var B: CampusBuilder
var L: CampusLayout

const TRIM := Color(0.92, 0.91, 0.88)
const STONE_TRIM := Color(0.76, 0.73, 0.68)
const IRON := Color(0.17, 0.19, 0.25)
const WOOD := Color(0.62, 0.42, 0.27)
const BRICK := Color(0.62, 0.33, 0.28)

const WALLS := {
	# style.wall: [colour, material id]
	"brick_red": [Color(0.62, 0.33, 0.28), MeshKit.M_BRICK],
	"brick_brown": [Color(0.50, 0.31, 0.25), MeshKit.M_BRICK],
	"brick_tan": [Color(0.72, 0.58, 0.45), MeshKit.M_BRICK],
	"stone_light": [Color(0.78, 0.75, 0.68), MeshKit.M_STONE],
	"siding_white": [Color(0.90, 0.89, 0.86), MeshKit.M_WOOD],
	"siding_grey": [Color(0.64, 0.66, 0.68), MeshKit.M_WOOD],
	"glass": [Color(0.36, 0.50, 0.58), MeshKit.M_GLASS],
	"metal_light": [Color(0.78, 0.80, 0.82), MeshKit.M_METAL],
	"metal_dark": [Color(0.30, 0.32, 0.36), MeshKit.M_METAL],
	"concrete": [Color(0.70, 0.69, 0.66), MeshKit.M_STONE],
}
const TRIMS := {"white": TRIM, "stone": STONE_TRIM, "dark": Color(0.22, 0.22, 0.25), "none": Color(0, 0, 0, 0)}
const ROOFS := {
	"shingle_dark": [Color(0.22, 0.23, 0.27), MeshKit.M_ROOF],
	"shingle_grey": [Color(0.38, 0.39, 0.42), MeshKit.M_ROOF],
	"metal_grey": [Color(0.50, 0.53, 0.56), MeshKit.M_METAL],
	"metal_dark": [Color(0.25, 0.28, 0.32), MeshKit.M_METAL],
	"membrane": [Color(0.52, 0.52, 0.53), MeshKit.M_STONE],
	"copper": [Color(0.30, 0.48, 0.42), MeshKit.M_METAL],
}


func _init(builder: CampusBuilder) -> void:
	B = builder
	L = builder.L


func _k(x: float, z: float, detail: bool = false) -> MeshKit:
	return B.kit_at(x, z, false, detail)


# ---------------------------------------------------------------------------
# Buildings
# ---------------------------------------------------------------------------
## `doors`: open doorways cut through the walls (a start dorm's, from
## CampusDorms): [{pos, normal, w, h}].  No wall, window or entrance door is
## drawn across them; a portico at one is still drawn.
func building(bd: Dictionary, doors: Array = []) -> void:
	if bd.get("landmark") != null and String(bd["landmark"]) != "":
		if B.marks.landmark(bd):
			return
	if bool(bd["background"]):
		_background_building(bd)
		return
	var style: Dictionary = bd["style"]
	var wall_spec: Array = WALLS.get(String(style.get("wall", "brick_red")), WALLS["brick_red"])
	var trim: Color = TRIMS.get(String(style.get("trim", "stone")), STONE_TRIM)
	var roof_spec: Array = ROOFS.get(String(style.get("roof_mat", "shingle_dark")), ROOFS["shingle_dark"])
	var win := String(style.get("windows", "punched"))
	var parts: Array = bd["parts"]
	if parts.is_empty():
		parts = [{"poly": bd["poly"], "h": float(bd["h"]), "base": 0.0, "roof": bd["roof"]}]
	var floors := int(bd.get("floors", 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(bd["id"]))
	var warm := 0.55 if String(bd["kind"]) != "residence" else 0.62
	var passages: Array = bd["passages"]
	for pi in parts.size():
		var part: Dictionary = parts[pi]
		var poly: PackedVector2Array = part["poly"]
		var h := float(part["h"])
		var base := float(part.get("base", 0.0))
		var nfl := floors if floors > 0 and pi == 0 else maxi(1, int(round((h - base) / (3.3 if String(bd["kind"]) == "residence" else 4.0))))
		_mass(bd, part, parts, wall_spec, trim, base, h, doors, passages)
		if win != "none" and String(style.get("wall", "")) != "glass":
			_windows(bd, part, parts, win, nfl, base, h, trim, warm, rng, doors, passages)
		elif String(style.get("wall", "")) == "glass":
			_curtain_mullions(poly, base, h, trim)
		_roof(part, poly, h, roof_spec, wall_spec, trim)
	_passage_art(bd, wall_spec, trim, doors)
	for e in bd["entrances"]:
		var ep := CampusLayout._v2(e.get("p", [0, 0]))
		var at_door := false
		for dr in doors:
			if ep.distance_to(dr["pos"]) < float(dr["w"]) * 0.5 + 1.5:
				at_door = true
		var ps := _passage_near(ep, passages)
		if not ps.is_empty():
			# an entrance at an open porch or breezeway: its door stands on the
			# far wall of the passage (the mouth's columns are the portico)
			var face := deg_to_rad(float(e.get("face", 0.0)))
			var n := Vector2(sin(face), -cos(face))
			var back := _far_side(ep, n, ps["poly"])
			if back != Vector2.INF and not at_door:
				var e2: Dictionary = (e as Dictionary).duplicate()
				e2["p"] = [back.x, back.y]
				e2["kind"] = "double" if float(e.get("w", 2.4)) > 2.6 else "door"
				var near_door := false
				for dr in doors:
					if back.distance_to(dr["pos"]) < float(dr["w"]) * 0.5 + 1.5:
						near_door = true
				if not near_door:
					_entrance(bd, e2, trim, wall_spec)
			continue
		if not at_door:
			_entrance(bd, e, trim, wall_spec)
		elif String(e.get("kind", "")) == "portico":
			var face2 := deg_to_rad(float(e.get("face", 0.0)))
			var n3 := Vector3(sin(face2), 0, -cos(face2))
			portico(_k(ep.x, ep.y), Vector3(ep.x, 0, ep.y) + n3 * 0.06, n3, Vector3(-n3.z, 0, n3.x), portico_width(e), clampf(float(bd["h"]) * 0.75, 5.0, 11.0), trim if trim.a > 0.0 else TRIM)


# ---------------------------------------------------------------------------
# Open passages (porches, breezeways, arcades): the data's `passages`
# ---------------------------------------------------------------------------
static func _in_passages(p: Vector2, passages: Array) -> Dictionary:
	for ps in passages:
		if Geometry2D.is_point_in_polygon(p, ps["poly"]):
			return ps
	return {}


static func _passage_near(p: Vector2, passages: Array) -> Dictionary:
	for ps in passages:
		if Geometry2D.is_point_in_polygon(p, ps["poly"]) or CampusData.dist_to_edge(p, ps["poly"]) < 1.2:
			return ps
	return {}


## Where a line from `p` (on a passage's mouth) inward against `n` leaves the
## passage on its far side, or INF.
static func _far_side(p: Vector2, n: Vector2, poly: PackedVector2Array) -> Vector2:
	var best := Vector2.INF
	var bd := INF
	var m := poly.size()
	for i in m:
		var hit: Variant = Geometry2D.segment_intersects_segment(p - n * 0.3, p - n * 60.0, poly[i], poly[(i + 1) % m])
		if hit != null:
			var d := p.distance_to(hit)
			if d > 0.5 and d < bd:
				bd = d
				best = hit
	return best


## Open spans of the edge a->b where a passage meets it (sampled 0.25 m
## apart just inside the wall): [[centre, half length, clear height]].
static func passage_holes(a: Vector2, b: Vector2, passages: Array) -> Array:
	var out: Array = []
	if passages.is_empty():
		return out
	var d := b - a
	var len := d.length()
	if len < 0.05:
		return out
	var dir := d / len
	var inward := Vector2(-dir.y, dir.x)
	var steps := maxi(2, int(len / 0.25))
	var run0 := -1.0
	var run_clear := 0.0
	for si in steps + 1:
		var t := len * float(si) / float(steps)
		var ps := _in_passages(a + dir * clampf(t, 0.02, len - 0.02) + inward * 0.15, passages)
		var inside := not ps.is_empty()
		if inside and run0 < 0.0:
			run0 = t
			run_clear = float(ps["clear"])
		if (not inside or si == steps) and run0 >= 0.0:
			var t1 := t if not inside else len
			if t1 - run0 > 0.3:
				out.append([(run0 + t1) * 0.5, (t1 - run0) * 0.5, run_clear])
			run0 = -1.0
	return out


## The columns standing in the open mouths of a building's passages (where
## a passage meets the outline): [[position, radius, height]].  Drawn by
## _passage_art and used for the colliders and the nav grid, so they agree.
static func passage_columns(bd: Dictionary) -> Array:
	var out: Array = []
	var foot: PackedVector2Array = CampusData.ccw(bd["poly"])
	var n := foot.size()
	for i in n:
		var a := foot[i]
		var b := foot[(i + 1) % n]
		var len := a.distance_to(b)
		if len < 0.5:
			continue
		var dir := (b - a) / len
		for hl in passage_holes(a, b, bd["passages"]):
			var clear := float(hl[2])
			var span := float(hl[1]) * 2.0
			if clear < 3.4 or span < 4.0:
				continue
			var r := clampf(clear * 0.045, 0.25, 0.55)
			var cnt := maxi(2, int(round(span / 3.4)) + 1)
			var t0 := float(hl[0]) - float(hl[1]) + r + 0.1
			var t1 := float(hl[0]) + float(hl[1]) - r - 0.1
			for ci in cnt:
				var t := lerpf(t0, t1, float(ci) / float(cnt - 1))
				out.append([a + dir * t - Vector2(dir.y, -dir.x) * (r + 0.15), r, clear])
	return out


## Inside each passage: side walls in the wall material (with any dorm
## doorway cut), a soffit at the clear height, paving underfoot,
## downlights; giant columns in the open mouths.
func _passage_art(bd: Dictionary, wall_spec: Array, trim: Color, doors: Array) -> void:
	var foot: PackedVector2Array = bd["poly"]
	var col: Color = wall_spec[0]
	var tc := trim if trim.a > 0.0 else TRIM
	for ps in bd["passages"]:
		var pp: PackedVector2Array = CampusData.ccw(ps["poly"])
		var clear := float(ps["clear"])
		var c := CampusData.centroid(pp)
		var k := _k(c.x, c.y)
		var idx := CampusData.triangulate(pp)
		k.mat = MeshKit.M_PAVING
		for t in range(0, idx.size(), 3):
			CampusBuilder._tri_up(k, Vector3(pp[idx[t]].x, 0.085, pp[idx[t]].y), Vector3(pp[idx[t + 1]].x, 0.085, pp[idx[t + 1]].y), Vector3(pp[idx[t + 2]].x, 0.085, pp[idx[t + 2]].y), Color(0.62, 0.60, 0.56))
		k.mat = MeshKit.M_PLASTER
		for t in range(0, idx.size(), 3):
			_tri_facing(k, Vector3(pp[idx[t]].x, clear, pp[idx[t]].y), Vector3(pp[idx[t + 1]].x, clear, pp[idx[t + 1]].y), Vector3(pp[idx[t + 2]].x, clear, pp[idx[t + 2]].y), tc.darkened(0.3), Vector3.DOWN)
		var m := pp.size()
		for i in m:
			var a := pp[i]
			var b := pp[(i + 1) % m]
			var len := a.distance_to(b)
			if len < 0.1:
				continue
			var mid := (a + b) * 0.5
			if not Geometry2D.is_point_in_polygon(mid, foot) or CampusData.dist_to_edge(mid, foot) < 0.3:
				continue      # a mouth (on the outline): open
			var dir := (b - a) / len
			var inw := Vector3(-dir.y, 0, dir.x)
			var holes := edge_holes(b, a, doors)
			k.mat = wall_spec[1]
			for sp in solid_spans(len, holes):
				# edge_holes ran b->a: flip the spans back onto a->b
				var s0 := b - dir * float(sp[0])
				var s1 := b - dir * float(sp[1])
				_quad_facing(k, Vector3(s0.x, 0.0, s0.y), Vector3(s1.x, 0.0, s1.y), Vector3(s1.x, clear, s1.y), Vector3(s0.x, clear, s0.y), col.darkened(0.08), inw)
			for hl in holes:
				var h0 := b - dir * (float(hl[0]) - float(hl[1]))
				var h1 := b - dir * (float(hl[0]) + float(hl[1]))
				_quad_facing(k, Vector3(h0.x, float(hl[2]), h0.y), Vector3(h1.x, float(hl[2]), h1.y), Vector3(h1.x, clear, h1.y), Vector3(h0.x, clear, h0.y), col.darkened(0.08), inw)
			k.mat = 0.0
		# downlights along the passage's long axis
		var obb := obb_of(pp)
		var ax: Vector2 = obb["axis"]
		var size: Vector2 = obb["size"]
		if size.y > size.x:
			ax = Vector2(-ax.y, ax.x)
		var plen := maxf(size.x, size.y)
		var kd := _k(c.x, c.y, true)
		for li in maxi(1, int(plen / 4.0)):
			var lp: Vector2 = (obb["center"] as Vector2) + ax * (plen * ((float(li) + 0.5) / maxf(1.0, float(int(plen / 4.0))) - 0.5))
			if not Geometry2D.is_point_in_polygon(lp, pp):
				continue
			kd.mat = MeshKit.M_GLASS
			kd.box(Vector3(lp.x, clear - 0.02, lp.y), Vector3(0.24, 0.03, 0.24), Color(1.0, 0.86, 0.62), 0.0, 1.0)
			kd.mat = 0.0
			B.glow_disc(Vector3(lp.x, 0.1, lp.y), 1.8)
	# giant columns in the mouths, and a beam over each mouth
	for cl in passage_columns(bd):
		var q: Vector2 = cl[0]
		var r := float(cl[1])
		var h := float(cl[2])
		var k2 := _k(q.x, q.y)
		k2.mat = MeshKit.M_PLASTER
		k2.revolve(Vector3(q.x, 0, q.y), PackedVector2Array([Vector2(r * 1.35, 0.0), Vector2(r * 1.35, 0.35), Vector2(r * 1.1, 0.5), Vector2(r, h * 0.5), Vector2(r * 0.9, h - 0.6), Vector2(r * 1.2, h - 0.3), Vector2(r * 1.4, h)]),
			PackedColorArray([tc.darkened(0.12), tc.darkened(0.06), tc, tc, tc, tc.lightened(0.04), tc.lightened(0.06)]), 12)
		k2.mat = 0.0


## Door openings along the edge a->b: [[distance from a, half width,
## height]] for every door standing on it (within 0.7 m, facing out).
static func edge_holes(a: Vector2, b: Vector2, doors: Array) -> Array:
	var out: Array = []
	var d := b - a
	var len := d.length()
	if len < 0.01:
		return out
	var dir := d / len
	var nrm := Vector2(dir.y, -dir.x)
	for dr in doors:
		var p: Vector2 = dr["pos"]
		var t := (p - a).dot(dir)
		if t < -0.5 or t > len + 0.5:
			continue
		if absf((p - a).dot(nrm)) > 0.7 or (dr["normal"] as Vector2).dot(nrm) < 0.7:
			continue
		out.append([clampf(t, 0.0, len), float(dr["w"]) * 0.5, float(dr.get("h", 3.0))])
	out.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	return out


## The solid stretches of a->b between holes: [[t0, t1]].
static func solid_spans(len: float, holes: Array) -> Array:
	var out: Array = []
	var t := 0.0
	for hl in holes:
		var h0 := float(hl[0]) - float(hl[1])
		if h0 > t + 0.001:
			out.append([t, h0])
		t = maxf(t, float(hl[0]) + float(hl[1]))
	if t < len - 0.001:
		out.append([t, len])
	return out


## Walls of one mass: one quad per footprint edge in the wall material, a
## darker plinth band and a cornice band in the trim colour.
func _mass(bd: Dictionary, part: Dictionary, parts: Array, wall_spec: Array, trim: Color, base: float, h: float, doors: Array = [], passages: Array = []) -> void:
	var poly: PackedVector2Array = CampusData.ccw(part["poly"])
	var c := CampusData.centroid(poly)
	var k := _k(c.x, c.y)
	var col: Color = wall_spec[0]
	var mat: float = wall_spec[1]
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var d := b - a
		if d.length() < 0.05:
			continue
		var out := Vector3(d.normalized().y, 0, -d.normalized().x)
		var shade := col.darkened(0.06 * absf(out.x))
		# a wall another part of this building stands against is hidden: only
		# what rises above the neighbour is drawn (and nothing cuts through
		# an open interior)
		var y0 := maxf(base, _cover_height(a, b, Vector2(out.x, out.z), part, parts))
		if y0 >= h - 0.05:
			continue
		var holes := edge_holes(a, b, doors) if y0 < 0.5 else []
		if y0 < 0.5:
			holes.append_array(passage_holes(a, b, passages))
			holes.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) - float(x[1]) < float(y[0]) - float(y[1]))
		var dir := d.normalized()
		k.mat = mat
		if holes.is_empty():
			_quad_facing(k, Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, h, b.y), Vector3(a.x, h, a.y), shade, out)
		else:
			for sp in solid_spans(d.length(), holes):
				var s0 := a + dir * float(sp[0])
				var s1 := a + dir * float(sp[1])
				_quad_facing(k, Vector3(s0.x, y0, s0.y), Vector3(s1.x, y0, s1.y), Vector3(s1.x, h, s1.y), Vector3(s0.x, h, s0.y), shade, out)
			for hl in holes:
				var h0 := a + dir * (float(hl[0]) - float(hl[1]))
				var h1 := a + dir * (float(hl[0]) + float(hl[1]))
				var top := float(hl[2])
				_quad_facing(k, Vector3(h0.x, top, h0.y), Vector3(h1.x, top, h1.y), Vector3(h1.x, h, h1.y), Vector3(h0.x, h, h0.y), shade, out)
		if y0 < 0.5:
			# plinth: a dressed band at the foot of the wall
			k.mat = MeshKit.M_STONE
			var po := out * 0.08
			for sp2 in solid_spans(d.length(), holes):
				var p0 := a + dir * float(sp2[0])
				var p1 := a + dir * float(sp2[1])
				_quad_facing(k, Vector3(p0.x, 0.0, p0.y) + po, Vector3(p1.x, 0.0, p1.y) + po, Vector3(p1.x, 0.62, p1.y) + po, Vector3(p0.x, 0.62, p0.y) + po, col.darkened(0.3).lerp(STONE_TRIM.darkened(0.25), 0.5), out)
				_quad_facing(k, Vector3(p0.x, 0.62, p0.y) + po, Vector3(p1.x, 0.62, p1.y) + po, Vector3(p1.x, 0.62, p1.y), Vector3(p0.x, 0.62, p0.y), STONE_TRIM.darkened(0.2), Vector3.UP)
		if trim.a > 0.0:
			# cornice: a moulded band projecting from the wall top
			k.mat = MeshKit.M_STONE
			var co := out * 0.22
			_quad_facing(k, Vector3(a.x, h - 0.45, a.y) + co, Vector3(b.x, h - 0.45, b.y) + co, Vector3(b.x, h, b.y) + co, Vector3(a.x, h, a.y) + co, trim, out)
			_quad_facing(k, Vector3(a.x, h - 0.45, a.y), Vector3(b.x, h - 0.45, b.y), Vector3(b.x, h - 0.45, b.y) + co, Vector3(a.x, h - 0.45, a.y) + co, trim.darkened(0.35), Vector3.DOWN)
		k.mat = 0.0


## Windows of one mass, bay by bay along each edge, one row per floor.
func _windows(bd: Dictionary, part: Dictionary, parts: Array, style: String, floors: int, base: float, h: float, trim: Color, warm: float, rng: RandomNumberGenerator, doors: Array = [], passages: Array = []) -> void:
	var poly: PackedVector2Array = CampusData.ccw(part["poly"])
	var n := poly.size()
	var resid := String(bd["kind"]) == "residence" or String(bd["kind"]) == "house"
	var bay := 2.9 if resid else 3.4
	var fl_h := (h - base - 0.6) / maxf(1.0, float(floors))
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var d := b - a
		var len := d.length()
		if len < 2.6:
			continue
		var dir := d / len
		var out := Vector3(dir.y, 0, -dir.x)
		var out2 := Vector2(dir.y, -dir.x)
		var bays := int(floor((len - 1.0) / bay))
		if bays <= 0:
			continue
		var step := (len - 1.0) / float(bays)
		var mid := (a + b) * 0.5
		var k := _k(mid.x, mid.y)
		var holes := edge_holes(a, b, doors)
		holes.append_array(passage_holes(a, b, passages))
		for r in floors:
			var y := base + 0.6 + fl_h * (float(r) + 0.5)
			if y + 0.9 > h - 0.4:
				continue
			for c in bays:
				var t := 0.5 + step * (float(c) + 0.5)
				var p := a + dir * t
				# a wall another part of this building stands against: no window
				if _covered(p + out2 * 0.6, y, part, parts):
					continue
				if style == "sparse" and (c % 2 == 1):
					continue
				var by_door := false
				for hl in holes:
					if absf(t - float(hl[0])) < float(hl[1]) + 0.9 and y - 0.9 < float(hl[2]) + 0.6:
						by_door = true
				if by_door:
					continue
				var ctr := Vector3(p.x, y, p.y)
				var w := 1.15 if style != "ribbon" else step * 0.82
				var hh := 0.8 if style != "ribbon" else 0.62
				_window(k, ctr, Vector3(dir.x, 0, dir.y), out, w, hh, rng.randf() < warm, rng, trim, style != "ribbon")


## How high the other parts of the building stand against the outer face of
## the edge a-b (the lowest over three samples; 0 when open).
static func _cover_height(a: Vector2, b: Vector2, out: Vector2, me: Dictionary, parts: Array) -> float:
	if parts.size() < 2:
		return 0.0
	var lowest := INF
	for f: float in [0.2, 0.5, 0.8]:
		var p := a.lerp(b, f) + out * 0.3
		var top := 0.0
		for other in parts:
			if other == me:
				continue
			if float(other.get("base", 0.0)) < 0.5 and Geometry2D.is_point_in_polygon(p, other["poly"]):
				top = maxf(top, float(other["h"]))
		lowest = minf(lowest, top)
	return lowest


func _covered(p: Vector2, y: float, me: Dictionary, parts: Array) -> bool:
	for other in parts:
		if other == me:
			continue
		if y < float(other["h"]) and y > float(other.get("base", 0.0)) and Geometry2D.is_point_in_polygon(p, other["poly"]):
			return true
	return false


## One window: a dark reveal, the glass with a lit interior that varies,
## curtains; frame, mullion, lintel and sill in the near-field detail mesh.
func _window(k: MeshKit, ctr: Vector3, right: Vector3, normal: Vector3, width: float, height: float, lit: bool, rng: RandomNumberGenerator, trim: Color, frames: bool) -> void:
	var up := Vector3.UP
	var hw := right * (width * 0.5)
	var hh := up * height
	k.mat = MeshKit.M_PLAIN
	var rv := ctr + normal * 0.04
	_quad_facing(k, rv - hw * 1.16 + hh * 1.1, rv + hw * 1.16 + hh * 1.1, rv + hw * 1.16 - hh * 1.1, rv - hw * 1.16 - hh * 1.1, Color(0.12, 0.11, 0.13), normal)
	var g0 := ctr + normal * 0.05
	k.mat = MeshKit.M_GLASS
	if lit:
		var tone := rng.randf()
		var room := Color(1.0, 0.76, 0.42) if tone < 0.6 else (Color(0.96, 0.62, 0.34) if tone < 0.85 else Color(0.62, 0.72, 0.95))
		var em := rng.randf_range(0.55, 0.9)
		_quad_facing(k, g0 - hw + hh, g0 + hw + hh, g0 + hw, g0 - hw, room.darkened(0.12), normal)
		k.cu_emission_last(6, em * 0.85)
		_quad_facing(k, g0 - hw, g0 + hw, g0 + hw - hh, g0 - hw - hh, room, normal)
		k.cu_emission_last(6, em)
		if rng.randf() < 0.65:
			var cur := Color(0.70, 0.40, 0.26) if rng.randf() < 0.5 else Color(0.56, 0.46, 0.40)
			var cw := width * rng.randf_range(0.14, 0.26)
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var e := g0 + right * (width * 0.5 * side) + normal * 0.005
			var inner := e - right * (cw * side)
			_quad_facing(k, e + hh, inner + hh, inner - hh, e - hh, cur, normal)
			k.cu_emission_last(6, em * 0.45)
	else:
		_quad_facing(k, g0 - hw + hh, g0 + hw + hh, g0 + hw - hh, g0 - hw - hh, Color(0.10, 0.14, 0.24), normal)
		k.cu_emission_last(6, 0.04)
		_quad_facing(k, g0 - hw * 0.2 + hh * 0.9 + normal * 0.003, g0 + hw * 0.1 + hh * 0.9 + normal * 0.003, g0 - hw * 0.5 - hh * 0.4 + normal * 0.003, g0 - hw * 0.8 - hh * 0.4 + normal * 0.003, Color(0.32, 0.38, 0.55), normal)
		k.cu_emission_last(6, 0.12)
	k.mat = 0.0
	if not frames:
		return
	var kd := _k(ctr.x, ctr.z, true)
	var frame := trim if trim.a > 0.0 else TRIM
	var f0 := ctr + normal * 0.07
	var t := 0.08
	kd.mat = MeshKit.M_WOOD
	_quad_facing(kd, f0 - hw - right * t + hh + up * t, f0 + hw + right * t + hh + up * t, f0 + hw + right * t + hh, f0 - hw - right * t + hh, frame, normal)
	_quad_facing(kd, f0 - hw - right * t - hh, f0 + hw + right * t - hh, f0 + hw + right * t - hh - up * t, f0 - hw - right * t - hh - up * t, frame, normal)
	_quad_facing(kd, f0 - hw - right * t + hh, f0 - hw + hh, f0 - hw - hh, f0 - hw - right * t - hh, frame, normal)
	_quad_facing(kd, f0 + hw + hh, f0 + hw + right * t + hh, f0 + hw + right * t - hh, f0 + hw - hh, frame, normal)
	_quad_facing(kd, f0 - right * 0.03 + hh, f0 + right * 0.03 + hh, f0 + right * 0.03 - hh, f0 - right * 0.03 - hh, frame.darkened(0.08), normal)
	kd.mat = MeshKit.M_STONE
	var yaw := atan2(-right.z, right.x)
	kd.chamfer_box(ctr - hh - up * 0.12 + normal * 0.1, Vector3(width + 0.35, 0.11, 0.22), STONE_TRIM.lightened(0.08), 0.03, yaw)
	kd.mat = 0.0


## Glass walls: mullions every ~1.6 m and a transom band per floor.
func _curtain_mullions(poly: PackedVector2Array, base: float, h: float, trim: Color) -> void:
	var cp := CampusData.ccw(poly)
	var n := cp.size()
	for i in n:
		var a := cp[i]
		var b := cp[(i + 1) % n]
		var len := a.distance_to(b)
		if len < 1.0:
			continue
		var dir := (b - a) / len
		var out := Vector3(dir.y, 0, -dir.x)
		var mid := (a + b) * 0.5
		var kd := _k(mid.x, mid.y, true)
		kd.mat = MeshKit.M_METAL
		var cnt := int(len / 1.6)
		for m in range(1, cnt):
			var p := a + dir * (len * float(m) / float(cnt))
			var q := Vector3(p.x, 0, p.y) + out * 0.05
			_quad_facing(kd, q - Vector3(dir.x, 0, dir.y) * 0.05 + Vector3(0, base, 0), q + Vector3(dir.x, 0, dir.y) * 0.05 + Vector3(0, base, 0), q + Vector3(dir.x, 0, dir.y) * 0.05 + Vector3(0, h, 0), q - Vector3(dir.x, 0, dir.y) * 0.05 + Vector3(0, h, 0), Color(0.80, 0.83, 0.85), out)
		var fl := base + 4.0
		while fl < h - 0.5:
			var a3 := Vector3(a.x, fl, a.y) + out * 0.05
			var b3 := Vector3(b.x, fl, b.y) + out * 0.05
			_quad_facing(kd, a3, b3, b3 + Vector3(0, 0.12, 0), a3 + Vector3(0, 0.12, 0), Color(0.80, 0.83, 0.85), out)
			fl += 4.0
		kd.mat = 0.0
		# the lit interior behind the glass (cool office light, some warm)
		var k := _k(mid.x, mid.y)
		k.mat = MeshKit.M_GLASS
		var g := Vector3(0, 0, 0) + out * 0.02
		_quad_facing(k, Vector3(a.x, base + 0.2, a.y) + g, Vector3(b.x, base + 0.2, b.y) + g, Vector3(b.x, h - 0.4, b.y) + g, Vector3(a.x, h - 0.4, a.y) + g, Color(0.62, 0.74, 0.86), out)
		k.cu_emission_last(6, 0.32)
		k.mat = 0.0


# ---------------------------------------------------------------------------
# Roofs
# ---------------------------------------------------------------------------
## The roof of one mass, by type; pitched roofs sit on the mass's oriented
## bounding box (most masses are near-rectangular; complex shapes are split
## into parts by the data, and anything else falls back to flat).
func _roof(part: Dictionary, poly: PackedVector2Array, h: float, roof_spec: Array, wall_spec: Array, trim: Color) -> void:
	var roof: Dictionary = part.get("roof", {})
	var kind := String(roof.get("type", "flat"))
	var col: Color = roof_spec[0]
	var mat: float = roof_spec[1]
	var c := CampusData.centroid(poly)
	var k := _k(c.x, c.y)
	var obb := obb_of(poly)
	var fill := absf(CampusData.area(poly)) / maxf(1.0, (obb["size"] as Vector2).x * (obb["size"] as Vector2).y)
	if kind in ["gable", "hip", "pyramid", "shed"] and fill < 0.82:
		kind = "flat"
	var pitch := deg_to_rad(clampf(float(roof.get("pitch", 30.0)), 5.0, 60.0))
	match kind:
		"gable", "hip", "pyramid", "shed":
			_pitched(k, obb, h, pitch, kind, String(roof.get("ridge", "long")), col, mat, wall_spec, trim)
		"dome":
			_flat(k, poly, h, Color(0.52, 0.52, 0.53), trim, false)
			var r := minf((obb["size"] as Vector2).x, (obb["size"] as Vector2).y) * 0.5 * float(roof.get("scale", 0.8))
			dome(k, Vector3(c.x, h, c.y), r, Color(0.88, 0.89, 0.90), float(roof.get("drum", 2.5)))
		_:
			_flat(k, poly, h, col if mat != MeshKit.M_ROOF else Color(0.50, 0.50, 0.52), trim, true)


## Flat roof: the membrane, a parapet with a coping, and a few rooftop units
## on larger roofs.
func _flat(k: MeshKit, poly: PackedVector2Array, h: float, col: Color, trim: Color, units: bool) -> void:
	var idx := CampusData.triangulate(poly)
	k.mat = MeshKit.M_STONE
	for t in range(0, idx.size(), 3):
		CampusBuilder._tri_up(k, Vector3(poly[idx[t]].x, h + 0.02, poly[idx[t]].y), Vector3(poly[idx[t + 1]].x, h + 0.02, poly[idx[t + 1]].y), Vector3(poly[idx[t + 2]].x, h + 0.02, poly[idx[t + 2]].y), col)
	# parapet: inner face and coping
	var cp := CampusData.ccw(poly)
	var n := cp.size()
	var cop := trim if trim.a > 0.0 else STONE_TRIM
	for i in n:
		var a := cp[i]
		var b := cp[(i + 1) % n]
		var d := b - a
		if d.length() < 0.05:
			continue
		var dn := d.normalized()
		var inw := Vector3(-dn.y, 0, dn.x)
		var a3 := Vector3(a.x, h, a.y)
		var b3 := Vector3(b.x, h, b.y)
		_quad_facing(k, a3 + inw * 0.3, b3 + inw * 0.3, b3 + inw * 0.3 + Vector3(0, 0.7, 0), a3 + inw * 0.3 + Vector3(0, 0.7, 0), col.darkened(0.15), inw)
		_quad_facing(k, a3 + Vector3(0, 0.7, 0) - inw * 0.1, b3 + Vector3(0, 0.7, 0) - inw * 0.1, b3 + Vector3(0, 0.7, 0) + inw * 0.32, a3 + Vector3(0, 0.7, 0) + inw * 0.32, cop, Vector3.UP)
		_quad_facing(k, a3 - inw * 0.1, b3 - inw * 0.1, b3 - inw * 0.1 + Vector3(0, 0.7, 0), a3 - inw * 0.1 + Vector3(0, 0.7, 0), cop.darkened(0.08), -inw)
	k.mat = 0.0
	var area := absf(CampusData.area(poly))
	if units and area > 400.0:
		var c := CampusData.centroid(poly)
		var rng := RandomNumberGenerator.new()
		rng.seed = int(c.x * 13.0 + c.y * 7.0)
		k.mat = MeshKit.M_METAL
		for u in clampi(int(area / 600.0), 1, 4):
			var p := c + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * sqrt(area) * 0.18
			if Geometry2D.is_point_in_polygon(p, poly):
				k.chamfer_box(Vector3(p.x, h + 0.6, p.y), Vector3(rng.randf_range(2.0, 3.6), 1.2, rng.randf_range(1.6, 2.6)), Color(0.62, 0.64, 0.66), 0.08)
		k.mat = 0.0


## A pitched roof over an oriented box: gable (ridge along `ridge`), hip,
## pyramid or shed, with eaves, soffits, fascia and gable-end walls.
func _pitched(k: MeshKit, obb: Dictionary, h: float, pitch: float, kind: String, ridge: String, col: Color, mat: float, wall_spec: Array, trim: Color) -> void:
	var c: Vector2 = obb["center"]
	var size: Vector2 = obb["size"]
	var ax2: Vector2 = obb["axis"]          # unit vector along size.x
	var aw2 := Vector2(-ax2.y, ax2.x)       # along size.y
	var along_x := size.x >= size.y
	if ridge == "short":
		along_x = not along_x
	elif ridge.is_valid_float():
		var rd := deg_to_rad(float(ridge))
		var rv := Vector2(sin(rd), -cos(rd))
		along_x = absf(rv.dot(ax2)) >= absf(rv.dot(aw2))
	var ax := Vector3(ax2.x, 0, ax2.y) if along_x else Vector3(aw2.x, 0, aw2.y)
	var aw := Vector3(aw2.x, 0, aw2.y) if along_x else Vector3(ax2.x, 0, ax2.y)
	var half_l := (size.x if along_x else size.y) * 0.5
	var half_w := (size.y if along_x else size.x) * 0.5
	var ov := 0.5
	var rise := half_w * tan(pitch)
	if kind == "shed":
		rise = half_w * 2.0 * tan(pitch) * 0.5
	var base := Vector3(c.x, h, c.y)
	var drop := ov * tan(pitch)
	k.mat = mat
	match kind:
		"gable":
			var r0 := base + Vector3.UP * rise - ax * (half_l + ov)
			var r1 := base + Vector3.UP * rise + ax * (half_l + ov)
			for sg: float in [-1.0, 1.0]:
				var e0 := base + aw * ((half_w + ov) * sg) - ax * (half_l + ov) - Vector3.UP * drop
				var e1 := base + aw * ((half_w + ov) * sg) + ax * (half_l + ov) - Vector3.UP * drop
				_quad_facing(k, r0, r1, e1, e0, col.darkened(0.1) if sg < 0.0 else col, (aw * sg + Vector3.UP).normalized())
				_quad_facing(k, e0, e1, e1 + aw * (-ov * sg) + Vector3.UP * drop, e0 + aw * (-ov * sg) + Vector3.UP * drop, col.darkened(0.55), Vector3.DOWN)
			k.mat = wall_spec[1]
			for se: float in [-1.0, 1.0]:
				var g := base + ax * (half_l * se)
				_tri_facing(k, g - aw * half_w, g + aw * half_w, g + Vector3.UP * rise, (wall_spec[0] as Color).darkened(0.06), ax * se)
			k.mat = MeshKit.M_WOOD
			var fas := trim if trim.a > 0.0 else TRIM.darkened(0.12)
			for se: float in [-1.0, 1.0]:
				var gb := base + ax * ((half_l + ov) * se)
				for sg: float in [-1.0, 1.0]:
					var lo := gb + aw * ((half_w + ov) * sg) - Vector3.UP * drop
					var hi := gb + Vector3.UP * rise
					_quad_facing(k, lo, hi, hi - Vector3.UP * 0.28, lo - Vector3.UP * 0.28, fas, ax * se)
			k.mat = mat
			k.chamfer_box(base + Vector3.UP * (rise + 0.06), Vector3(half_l * 2.0 + ov * 2.0, 0.16, 0.3), col.lightened(0.12), 0.05, atan2(-ax.z, ax.x))
		"hip", "pyramid":
			var rl := 0.0 if kind == "pyramid" else maxf(0.0, half_l - half_w)
			var t0 := base + Vector3.UP * rise - ax * rl
			var t1 := base + Vector3.UP * rise + ax * rl
			var corners := []
			for s in [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]:
				corners.append(base + ax * ((half_l + ov) * float(s[0])) + aw * ((half_w + ov) * float(s[1])) - Vector3.UP * drop)
			# long sides (trapezoids) and ends (triangles)
			_quad_facing(k, corners[0], corners[1], t1, t0, col.darkened(0.1), (-aw + Vector3.UP).normalized())
			_quad_facing(k, corners[3], corners[2], t1, t0, col, (aw + Vector3.UP).normalized())
			_tri_facing(k, corners[0], corners[3], t0, col.darkened(0.05), (-ax + Vector3.UP).normalized())
			_tri_facing(k, corners[1], corners[2], t1, col.darkened(0.03), (ax + Vector3.UP).normalized())
			for i in 4:
				var e0: Vector3 = corners[i]
				var e1: Vector3 = corners[(i + 1) % 4]
				var inward: Vector3 = (base - (e0 + e1) * 0.5)
				inward.y = 0.0
				inward = inward.normalized() * ov
				_quad_facing(k, e0, e1, e1 + inward + Vector3.UP * drop, e0 + inward + Vector3.UP * drop, col.darkened(0.55), Vector3.DOWN)
		"shed":
			var lo0 := base - aw * (half_w + ov) - ax * (half_l + ov)
			var lo1 := base - aw * (half_w + ov) + ax * (half_l + ov)
			var hi0 := base + aw * (half_w + ov) - ax * (half_l + ov) + Vector3.UP * rise
			var hi1 := base + aw * (half_w + ov) + ax * (half_l + ov) + Vector3.UP * rise
			_quad_facing(k, lo0, lo1, hi1, hi0, col, (-aw + Vector3.UP * 2.0).normalized())
			k.mat = wall_spec[1]
			for se: float in [-1.0, 1.0]:
				var g := base + ax * (half_l * se)
				_tri_facing(k, g - aw * half_w, g + aw * half_w, g + aw * half_w + Vector3.UP * rise, (wall_spec[0] as Color).darkened(0.06), ax * se)
			var g2a := base + aw * half_w - ax * half_l
			var g2b := base + aw * half_w + ax * half_l
			_quad_facing(k, g2a, g2b, g2b + Vector3.UP * rise, g2a + Vector3.UP * rise, (wall_spec[0] as Color).darkened(0.04), aw)
	k.mat = 0.0


## A dome on a short drum: smooth hemisphere (revolve) with a lantern cap.
func dome(k: MeshKit, base: Vector3, r: float, col: Color, drum: float) -> void:
	k.mat = MeshKit.M_STONE
	k.revolve(base, PackedVector2Array([Vector2(r * 1.04, 0.0), Vector2(r * 1.04, drum * 0.15), Vector2(r, drum * 0.2), Vector2(r, drum)]),
		PackedColorArray([STONE_TRIM, STONE_TRIM, STONE_TRIM.darkened(0.05), STONE_TRIM.darkened(0.05)]), 28)
	k.mat = MeshKit.M_METAL
	var prof := PackedVector2Array()
	var cols := PackedColorArray()
	for i in 9:
		var a := PI * 0.5 * float(i) / 8.0
		prof.append(Vector2(r * cos(a), drum + r * 0.92 * sin(a)))
		cols.append(col.darkened(0.12 * (1.0 - float(i) / 8.0)))
	k.revolve(base, prof, cols, 28)
	k.revolve(base + Vector3(0, drum + r * 0.92, 0), PackedVector2Array([Vector2(r * 0.12, 0), Vector2(r * 0.12, 0.9), Vector2(0.05, 1.3)]), PackedColorArray([TRIM, TRIM, TRIM]), 10)
	k.mat = 0.0


## Minimum-area oriented bounding box of a polygon (rotating the hull's edges).
static func obb_of(poly: PackedVector2Array) -> Dictionary:
	var hull := Geometry2D.convex_hull(poly)
	var best := {"area": INF}
	var n := hull.size()
	for i in n - 1:
		var e := (hull[i + 1] - hull[i])
		if e.length() < 1e-4:
			continue
		var ax := e.normalized()
		var aw := Vector2(-ax.y, ax.x)
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for p in hull:
			var u := p.dot(ax)
			var v := p.dot(aw)
			mn = Vector2(minf(mn.x, u), minf(mn.y, v))
			mx = Vector2(maxf(mx.x, u), maxf(mx.y, v))
		var a := (mx.x - mn.x) * (mx.y - mn.y)
		if a < float(best["area"]):
			var cu := (mn + mx) * 0.5
			best = {"area": a, "axis": ax, "size": mx - mn, "center": ax * cu.x + aw * cu.y}
	if not best.has("axis"):
		var r := CampusData.bounds(poly)
		return {"area": r.get_area(), "axis": Vector2(1, 0), "size": r.size, "center": r.get_center()}
	return best


# ---------------------------------------------------------------------------
# Entrances
# ---------------------------------------------------------------------------
## A real entrance: a lit door (double where wide) with a transom; a canopy
## on brackets, or a classical portico (columns, entablature, pediment) for
## "portico"; a step and two wall lanterns.
func _entrance(bd: Dictionary, e: Dictionary, trim: Color, wall_spec: Array) -> void:
	var p := CampusLayout._v2(e.get("p", [0, 0]))
	var face := deg_to_rad(float(e.get("face", 0.0)))
	var n := Vector2(sin(face), -cos(face))          # 0 = facing north (-Z)
	var right := Vector2(-n.y, n.x)
	var w := float(e.get("w", 2.4))
	var kind := String(e.get("kind", "door"))
	var nr := Vector3(n.x, 0, n.y)
	var rt := Vector3(right.x, 0, right.y)
	var base := Vector3(p.x, 0, p.y) + nr * 0.06
	var k := _k(p.x, p.y)
	var dw := clampf(w * 0.8, 1.2, 3.4)
	k.mat = MeshKit.M_GLASS
	_quad_facing(k, base - rt * (dw * 0.5) + Vector3(0, 2.5, 0), base + rt * (dw * 0.5) + Vector3(0, 2.5, 0), base + rt * (dw * 0.5) + Vector3(0, 0.05, 0), base - rt * (dw * 0.5) + Vector3(0, 0.05, 0), Color(1.0, 0.78, 0.48), nr)
	k.cu_emission_last(6, 0.9)
	_quad_facing(k, base - rt * (dw * 0.5) + Vector3(0, 3.1, 0), base + rt * (dw * 0.5) + Vector3(0, 3.1, 0), base + rt * (dw * 0.5) + Vector3(0, 2.65, 0), base - rt * (dw * 0.5) + Vector3(0, 2.65, 0), Color(1.0, 0.82, 0.55), nr)
	k.cu_emission_last(6, 0.7)
	k.mat = MeshKit.M_WOOD
	var fr := trim if trim.a > 0.0 else TRIM
	k.chamfer_box(base + Vector3(0, 2.58, 0) + nr * 0.03, Vector3(dw + 0.3, 0.12, 0.12), fr, 0.03, atan2(-rt.z, rt.x))
	for s: float in [-1.0, 1.0]:
		k.chamfer_box(base + rt * (s * (dw * 0.5 + 0.08)) + Vector3(0, 1.58, 0) + nr * 0.03, Vector3(0.16, 3.16, 0.14), fr, 0.03, atan2(-rt.z, rt.x))
	if dw > 1.8:
		k.chamfer_box(base + Vector3(0, 1.3, 0) + nr * 0.03, Vector3(0.08, 2.5, 0.1), fr.darkened(0.15), 0.02, atan2(-rt.z, rt.x))
	k.mat = MeshKit.M_STONE
	k.chamfer_box(base + nr * 0.6 + Vector3(0, 0.06, 0), Vector3(dw + 1.2, 0.12, 1.2), STONE_TRIM, 0.03, atan2(-rt.z, rt.x))
	k.mat = 0.0
	match kind:
		"portico":
			portico(k, base, nr, rt, portico_width(e), clampf(float(bd["h"]) * 0.75, 5.0, 11.0), fr)
		"canopy", "double", "door":
			k.mat = MeshKit.M_METAL if kind == "canopy" else MeshKit.M_WOOD
			k.chamfer_box(base + nr * 0.9 + Vector3(0, 3.5, 0), Vector3(dw + 1.0, 0.22, 1.8), fr.darkened(0.05) if kind != "canopy" else Color(0.32, 0.34, 0.38), 0.05, atan2(-rt.z, rt.x))
			k.mat = 0.0
	for s: float in [-1.0, 1.0]:
		wall_lantern(Vector3(p.x, 0, p.y) + rt * (s * (dw * 0.5 + 0.7)) + nr * 0.1, nr)


const PORTICO_DEPTH := 2.6


static func portico_width(e: Dictionary) -> float:
	var w := float(e.get("w", 2.4))
	return maxf(w, clampf(w * 0.8, 1.2, 3.4) + 2.0)


## Where an entrance's portico columns stand (none unless it is a portico):
## the same placement `portico` draws, for the colliders.
static func portico_columns(e: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	if String(e.get("kind", "door")) != "portico":
		return out
	var p := CampusLayout._v2(e.get("p", [0, 0]))
	var face := deg_to_rad(float(e.get("face", 0.0)))
	var n := Vector2(sin(face), -cos(face))
	var rt := Vector2(-n.y, n.x)
	var width := portico_width(e)
	var cols := clampi(int(width / 2.0) + 1, 2, 6)
	for i in cols:
		var u := -width * 0.5 + width * float(i) / float(cols - 1)
		out.append(p + n * (0.06 + PORTICO_DEPTH - 0.35) + rt * u)
	return out


## A classical portico: a row of columns before the door, an entablature and
## a triangular pediment in the trim colour.
func portico(k: MeshKit, base: Vector3, nr: Vector3, rt: Vector3, width: float, height: float, col: Color) -> void:
	var depth := PORTICO_DEPTH
	var cols := clampi(int(width / 2.0) + 1, 2, 6)
	k.mat = MeshKit.M_STONE
	k.chamfer_box(base + nr * (depth * 0.5) + Vector3(0, 0.12, 0), Vector3(width + 0.6, 0.24, depth + 0.6), STONE_TRIM, 0.04, atan2(-rt.z, rt.x))
	for i in cols:
		var u := -width * 0.5 + width * float(i) / float(cols - 1)
		var cp := base + nr * (depth - 0.35) + rt * u
		k.revolve(cp, PackedVector2Array([Vector2(0.34, 0.24), Vector2(0.34, 0.45), Vector2(0.27, 0.6), Vector2(0.26, height * 0.5), Vector2(0.23, height - 0.6), Vector2(0.31, height - 0.4), Vector2(0.36, height - 0.2)]),
			PackedColorArray([col.darkened(0.12), col.darkened(0.06), col, col, col, col.lightened(0.04), col.lightened(0.06)]), 12)
	var yaw := atan2(-rt.z, rt.x)
	k.chamfer_box(base + nr * (depth * 0.5) + Vector3(0, height + 0.25, 0), Vector3(width + 0.9, 0.5, depth + 0.4), col, 0.06, yaw)
	var ped := minf(1.8, width * 0.18)
	var front := base + nr * (depth + 0.2) + Vector3(0, height + 0.5, 0)
	_tri_facing(k, front - rt * (width * 0.5 + 0.45), front + rt * (width * 0.5 + 0.45), front + Vector3(0, ped, 0), col.lightened(0.03), nr)
	var back := base + Vector3(0, height + 0.5, 0)
	k.mat = MeshKit.M_ROOF
	for s: float in [-1.0, 1.0]:
		var e0 := front + rt * (s * (width * 0.5 + 0.45))
		var e1 := back + rt * (s * (width * 0.5 + 0.45))
		var r0 := front + Vector3(0, ped, 0)
		var r1 := back + Vector3(0, ped, 0)
		_quad_facing(k, e0, e1, r1, r0, Color(0.28, 0.29, 0.33), (rt * s + Vector3.UP).normalized())
	k.mat = 0.0


func wall_lantern(p: Vector3, nrm: Vector3) -> void:
	var kd := _k(p.x, p.z, true)
	var at := p + Vector3(0, 2.4, 0) + nrm * 0.18
	kd.mat = MeshKit.M_METAL
	kd.chamfer_box(at, Vector3(0.24, 0.36, 0.24), IRON, 0.03)
	kd.mat = MeshKit.M_GLASS
	kd.box(at + Vector3(0, -0.02, 0), Vector3(0.18, 0.24, 0.18), Color(1.0, 0.82, 0.5), 0.0, 0.9)
	kd.mat = 0.0
	B.glow_disc(Vector3(p.x, 0.07, p.z) + nrm * 1.3, 2.2)


## A building beyond the play boundary: its massing, a simple roof and a
## scatter of lit windows (no frames, no detail mesh).
func _background_building(bd: Dictionary) -> void:
	var poly: PackedVector2Array = CampusData.ccw(bd["poly"])
	var h := float(bd["h"])
	var style: Dictionary = bd["style"]
	var wall_spec: Array = WALLS.get(String(style.get("wall", "siding_white")), WALLS["siding_white"])
	var roof_spec: Array = ROOFS.get(String(style.get("roof_mat", "shingle_dark")), ROOFS["shingle_dark"])
	var c := CampusData.centroid(poly)
	var k := _k(c.x, c.y)
	var col: Color = wall_spec[0]
	k.mat = wall_spec[1]
	var n := poly.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(bd["id"]))
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var d := b - a
		if d.length() < 0.05:
			continue
		var out := Vector3(d.normalized().y, 0, -d.normalized().x)
		_quad_facing(k, Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), Vector3(b.x, h, b.y), Vector3(a.x, h, a.y), col.darkened(0.08 * absf(out.x)), out)
		# a few lit windows
		var len := d.length()
		k.mat = MeshKit.M_GLASS
		var cnt := int(len / 4.0)
		for j in cnt:
			if rng.randf() > 0.35:
				continue
			var q := a + d.normalized() * (len * (float(j) + 0.5) / float(cnt))
			var y := 1.4 + 3.0 * float(rng.randi_range(0, maxi(0, int(h / 3.0) - 1)))
			if y + 1.0 > h:
				continue
			var ctr := Vector3(q.x, y, q.y) + out * 0.04
			var rt := Vector3(d.normalized().x, 0, d.normalized().y)
			_quad_facing(k, ctr - rt * 0.5 + Vector3(0, 0.6, 0), ctr + rt * 0.5 + Vector3(0, 0.6, 0), ctr + rt * 0.5 - Vector3(0, 0.6, 0), ctr - rt * 0.5 - Vector3(0, 0.6, 0), Color(1.0, 0.76, 0.45), out)
			k.cu_emission_last(6, 0.75)
		k.mat = wall_spec[1]
	k.mat = 0.0
	var part := {"poly": poly, "h": h, "roof": bd["roof"]}
	_roof(part, poly, h, roof_spec, wall_spec, Color(0, 0, 0, 0))


# ---------------------------------------------------------------------------
# Walls, hedges, fences, bollards
# ---------------------------------------------------------------------------
func walls() -> void:
	for s in L.walls:
		var a: Vector2 = s["a"]
		var b: Vector2 = s["b"]
		var h := float(s["h"])
		var t := float(s["t"])
		var c := (a + b) * 0.5
		var k := _k(c.x, c.y)
		var d := b - a
		var yaw := atan2(-d.y, d.x)
		var col := Color(0.66, 0.60, 0.54) if String(s.get("kind", "")) != "wall_retaining" else Color(0.58, 0.56, 0.52)
		k.mat = MeshKit.M_STONE
		k.chamfer_box(Vector3(c.x, h * 0.5, c.y), Vector3(d.length() + t, h, t), col, 0.06, yaw)
		k.chamfer_box(Vector3(c.x, h + 0.05, c.y), Vector3(d.length() + t + 0.08, 0.1, t + 0.12), col.lightened(0.12), 0.03, yaw)
		k.mat = 0.0


func hedges(from: int, to: int) -> void:
	for s in L.hedges.slice(from, mini(to, L.hedges.size())):
		var a: Vector2 = s["a"]
		var b: Vector2 = s["b"]
		var h := float(s["h"])
		var t := float(s["t"])
		var len := a.distance_to(b)
		var pieces := maxi(1, int(ceil(len / 3.0)))
		for i in pieces:
			var p0 := a.lerp(b, float(i) / pieces)
			var p1 := a.lerp(b, float(i + 1) / pieces)
			var c := (p0 + p1) * 0.5
			var kf := B.kit_at(c.x, c.y, true)
			var d := p1 - p0
			var tone := 0.92 + 0.12 * fposmod(c.x * 0.37 + c.y * 0.21, 1.0)
			kf.mat = MeshKit.M_LEAF
			kf.chamfer_box(Vector3(c.x, h * 0.5, c.y), Vector3(d.length() + 0.15, h, t), Color(0.15, 0.32, 0.18) * tone, 0.3, atan2(-d.y, d.x))
			kf.mat = 0.0


func fences(from: int, to: int) -> void:
	for s in L.fences.slice(from, mini(to, L.fences.size())):
		var a: Vector2 = s["a"]
		var b: Vector2 = s["b"]
		var h := float(s["h"])
		var kind := String(s.get("kind", "fence_iron"))
		var len := a.distance_to(b)
		if len < 0.1:
			continue
		var dir := (b - a) / len
		var c := (a + b) * 0.5
		var kd := _k(c.x, c.y, true)
		var k := _k(c.x, c.y)
		var yaw := atan2(-dir.y, dir.x)
		var post_step := 2.4 if kind != "fence_construction" else 3.0
		var posts := maxi(1, int(ceil(len / post_step)))
		match kind:
			"fence_chain":
				k.mat = MeshKit.M_METAL
				for i in posts + 1:
					var p := a + dir * (len * float(i) / posts)
					k.chamfer_box(Vector3(p.x, h * 0.5, p.y), Vector3(0.08, h, 0.08), Color(0.62, 0.64, 0.66), 0.02)
				k.chamfer_box(Vector3(c.x, h - 0.03, c.y), Vector3(len, 0.06, 0.06), Color(0.62, 0.64, 0.66), 0.02, yaw)
				# the mesh: a faint, see-through-looking panel
				var n3 := Vector3(-dir.y, 0, dir.x)
				_quad_facing(kd, Vector3(a.x, 0.05, a.y), Vector3(b.x, 0.05, b.y), Vector3(b.x, h, b.y), Vector3(a.x, h, a.y), Color(0.42, 0.45, 0.47, 0.35), n3)
				_quad_facing(kd, Vector3(a.x, 0.05, a.y), Vector3(b.x, 0.05, b.y), Vector3(b.x, h, b.y), Vector3(a.x, h, a.y), Color(0.42, 0.45, 0.47, 0.35), -n3)
			"fence_construction":
				k.mat = MeshKit.M_PLAIN
				for i in posts:
					var p := a + dir * (len * (float(i) + 0.5) / posts)
					k.chamfer_box(Vector3(p.x, h * 0.5, p.y), Vector3(len / posts - 0.1, h, 0.05), Color(0.78, 0.80, 0.80), 0.01, yaw)
					k.chamfer_box(Vector3(p.x, 0.15, p.y), Vector3(0.5, 0.3, 0.6), Color(0.55, 0.22, 0.12), 0.05, yaw)
			_:
				k.mat = MeshKit.M_METAL
				for i in posts + 1:
					var p := a + dir * (len * float(i) / posts)
					k.chamfer_box(Vector3(p.x, h * 0.5, p.y), Vector3(0.1, h, 0.1), IRON, 0.02)
				for y: float in ([h - 0.12, 0.3] if kind != "rail" else [h - 0.05, h * 0.5]):
					k.chamfer_box(Vector3(c.x, y, c.y), Vector3(len, 0.05, 0.05), IRON, 0.01, yaw)
				if kind == "fence_iron":
					var pick := maxi(1, int(len / 0.16))
					for i in pick:
						var p := a + dir * (len * (float(i) + 0.5) / pick)
						kd.mat = MeshKit.M_METAL
						kd.box(Vector3(p.x, h * 0.5, p.y), Vector3(0.025, h - 0.1, 0.025), IRON)
		k.mat = 0.0
		kd.mat = 0.0


func bollards(from: int, to: int) -> void:
	for s in L.cart_blockers.slice(from, mini(to, L.cart_blockers.size())):
		if bool(s.get("hidden", false)):
			continue
		var a: Vector2 = s["a"]
		var b: Vector2 = s["b"]
		var len := a.distance_to(b)
		var n := maxi(1, int(round(len / 1.5)))
		for i in n + 1:
			var p := a.lerp(b, float(i) / n)
			var kd := _k(p.x, p.y, true)
			kd.mat = MeshKit.M_METAL
			kd.revolve(Vector3(p.x, 0, p.y), PackedVector2Array([Vector2(0.11, 0), Vector2(0.11, 0.85), Vector2(0.09, 0.95), Vector2(0.02, 1.0)]), PackedColorArray([IRON, IRON, IRON.lightened(0.2), IRON]), 8)
			kd.mat = 0.0


# ---------------------------------------------------------------------------
# Lamps, benches, props
# ---------------------------------------------------------------------------
## Campus lamps: a cast-iron post with a lantern head; parking-lot and road
## lights are taller poles.  Collider: the same 0.14 m post everywhere.
func lamps(from: int, to: int) -> void:
	for lp in L.lamps.slice(from, mini(to, L.lamps.size())):
		var tall := L.is_on_road(lp, 2.0)
		var kd := _k(lp.x, lp.y, true)
		var k := _k(lp.x, lp.y)
		k.mat = MeshKit.M_METAL
		var h := 7.5 if tall else 3.6
		k.revolve(Vector3(lp.x, 0, lp.y), PackedVector2Array([Vector2(0.2, 0), Vector2(0.2, 0.35), Vector2(0.09, 0.5), Vector2(0.07, h - 0.4), Vector2(0.1, h - 0.3)]),
			PackedColorArray([IRON, IRON, IRON, IRON, IRON]), 8)
		k.mat = MeshKit.M_GLASS
		if tall:
			k.chamfer_box(Vector3(lp.x, h, lp.y), Vector3(0.8, 0.2, 0.4), Color(1.0, 0.86, 0.6), 0.04)
			k.cu_emission_last(36, 1.0)
		else:
			k.box(Vector3(lp.x, h - 0.05, lp.y), Vector3(0.36, 0.5, 0.36), Color(1.0, 0.84, 0.56), 0.0, 1.0)
		k.mat = MeshKit.M_METAL
		kd.mat = MeshKit.M_METAL
		kd.chamfer_box(Vector3(lp.x, h + 0.28, lp.y), Vector3(0.46, 0.12, 0.46), IRON, 0.03)
		kd.mat = 0.0
		k.mat = 0.0
		B.glow_disc(Vector3(lp.x, 0.08, lp.y), 5.5 if tall else 4.2)


## Benches, props, rocks: one step for all of them.
func small_things() -> void:
	for bn in L.benches:
		_bench(bn["pos"], float(bn["rot"]))
	for pr in L.props:
		_prop(pr)
	for r in L.rocks:
		var rp: Vector3 = r["pos"]
		var k := _k(rp.x, rp.z)
		k.mat = MeshKit.M_ROCK
		k.chamfer_box(rp + Vector3(0, float(r["size"].y) * 0.5, 0), r["size"], Color(0.48, 0.47, 0.46), 0.25, float(r["rot"]))
		k.mat = 0.0


func _bench(p: Vector2, rot: float) -> void:
	var kd := _k(p.x, p.y, true)
	var k := _k(p.x, p.y)
	var f := Vector3(sin(rot), 0, cos(rot))       # facing (seat front)
	var r := Vector3(cos(rot), 0, -sin(rot))
	k.mat = MeshKit.M_WOOD
	k.chamfer_box(Vector3(p.x, 0.45, p.y), Vector3(1.8, 0.07, 0.5), WOOD, 0.02, rot)
	k.chamfer_box(Vector3(p.x, 0.75, p.y) - f * 0.24, Vector3(1.8, 0.4, 0.06), WOOD.darkened(0.05), 0.02, rot)
	kd.mat = MeshKit.M_METAL
	for s: float in [-0.75, 0.75]:
		kd.chamfer_box(Vector3(p.x, 0.22, p.y) + r * s, Vector3(0.07, 0.44, 0.5), IRON, 0.02, rot)
	kd.mat = 0.0
	k.mat = 0.0


## Colliding size of a prop (Vector3.ZERO: no collider).
static func prop_collider(pr: Dictionary) -> Vector3:
	match String(pr["kind"]):
		"bike_rack":
			return Vector3(maxf(2.0, float(pr.get("len", 2.0))), 0.9, 0.5)
		"bin":
			return Vector3(0.6, 1.0, 0.6)
		"planter":
			return Vector3(1.2, 0.8, 1.2)
		"table":
			return Vector3(1.8, 0.8, 1.8)
		"sign_blank":
			return Vector3(1.6, 1.3, 0.35)
		"bleachers":
			return Vector3(maxf(4.0, float(pr.get("len", 8.0))), 1.6, 3.0)
		"dugout":
			return Vector3(maxf(6.0, float(pr.get("len", 8.0))), 2.2, 2.0)
	return Vector3.ZERO


func _prop(pr: Dictionary) -> void:
	var p: Vector2 = pr["pos"]
	var rot := float(pr["rot"])
	var k := _k(p.x, p.y)
	var kd := _k(p.x, p.y, true)
	var kind := String(pr["kind"])
	match kind:
		"bike_rack":
			var len := maxf(2.0, float(pr.get("len", 2.0)))
			kd.mat = MeshKit.M_METAL
			var n := maxi(2, int(len / 0.8))
			var r := Vector3(cos(rot), 0, -sin(rot))
			for i in n:
				var q := Vector3(p.x, 0, p.y) + r * (-len * 0.5 + len * (float(i) + 0.5) / n)
				kd.chamfer_box(q + Vector3(0, 0.45, 0), Vector3(0.06, 0.9, 0.5), Color(0.55, 0.58, 0.62), 0.03, rot)
			kd.mat = 0.0
		"bin":
			k.mat = MeshKit.M_METAL
			k.revolve(Vector3(p.x, 0, p.y), PackedVector2Array([Vector2(0.28, 0), Vector2(0.3, 0.95), Vector2(0.32, 1.0)]), PackedColorArray([IRON, IRON, IRON.lightened(0.15)]), 10)
			k.mat = 0.0
		"planter":
			k.mat = MeshKit.M_STONE
			k.chamfer_box(Vector3(p.x, 0.4, p.y), Vector3(1.2, 0.8, 1.2), STONE_TRIM.darkened(0.1), 0.06, rot)
			k.mat = 0.0
			B.mm_add("decor", Vector3(p.x, 0.8, p.y), "shrub_bloom", Transform3D(Basis(Vector3.UP, rot).scaled(Vector3(0.9, 0.7, 0.9)), Vector3(p.x, 0.8, p.y)), Color(1, 1, 1), Color(0.22, 0.42, 0.24))
		"table":
			k.mat = MeshKit.M_WOOD
			k.chamfer_box(Vector3(p.x, 0.75, p.y), Vector3(1.8, 0.06, 0.8), WOOD, 0.02, rot)
			for s: float in [-0.7, 0.7]:
				k.chamfer_box(Vector3(p.x, 0.45, p.y) + Vector3(cos(rot), 0, -sin(rot)) * 0.0 + Vector3(sin(rot), 0, cos(rot)) * s, Vector3(1.8, 0.05, 0.3), WOOD.darkened(0.05), 0.02, rot)
			k.mat = 0.0
		"flagpole":
			k.mat = MeshKit.M_METAL
			k.revolve(Vector3(p.x, 0, p.y), PackedVector2Array([Vector2(0.09, 0), Vector2(0.06, 9.0), Vector2(0.1, 9.1)]), PackedColorArray([Color(0.8, 0.82, 0.84), Color(0.8, 0.82, 0.84), Color(0.85, 0.75, 0.4)]), 8)
			k.mat = 0.0
		"sign_blank":
			k.mat = MeshKit.M_STONE
			k.chamfer_box(Vector3(p.x, 0.65, p.y), Vector3(1.6, 1.3, 0.35), Color(0.55, 0.36, 0.30), 0.05, rot)
			k.mat = 0.0
		"bleachers":
			var len := maxf(4.0, float(pr.get("len", 8.0)))
			k.mat = MeshKit.M_METAL
			var f := Vector3(sin(rot), 0, cos(rot))
			for i in 4:
				k.chamfer_box(Vector3(p.x, 0.25 + 0.4 * i, p.y) - f * (0.75 * i - 1.1), Vector3(len, 0.08, 0.7), Color(0.70, 0.72, 0.74), 0.02, rot)
			k.mat = 0.0
		"goal":
			k.mat = MeshKit.M_METAL
			var r := Vector3(cos(rot), 0, -sin(rot))
			for s: float in [-3.6, 3.6]:
				k.chamfer_box(Vector3(p.x, 1.2, p.y) + r * s, Vector3(0.12, 2.4, 0.12), Color(0.92, 0.92, 0.92), 0.02)
			k.chamfer_box(Vector3(p.x, 2.4, p.y), Vector3(7.4, 0.12, 0.12), Color(0.92, 0.92, 0.92), 0.02, rot)
			k.mat = 0.0
		"dugout":
			var len := maxf(6.0, float(pr.get("len", 8.0)))
			k.mat = MeshKit.M_STONE
			k.chamfer_box(Vector3(p.x, 1.1, p.y), Vector3(len, 2.2, 2.0), Color(0.55, 0.53, 0.50), 0.05, rot)
			k.mat = 0.0
		"pergola", "pavilion":
			B.marks.shelter(pr)
		_:
			pass


# ---------------------------------------------------------------------------
# Surface markings
# ---------------------------------------------------------------------------
## Parking stalls: lines square to each long edge of the lot, 2.7 m apart.
func lot_markings(a: Dictionary) -> void:
	var poly: PackedVector2Array = CampusData.ccw(a["poly"])
	var n := poly.size()
	var col := Color(0.86, 0.86, 0.84)
	for i in n:
		var p0 := poly[i]
		var p1 := poly[(i + 1) % n]
		var len := p0.distance_to(p1)
		if len < 14.0:
			continue
		var dir := (p1 - p0) / len
		var inw := Vector2(-dir.y, dir.x)
		var cnt := int((len - 3.0) / 2.7)
		for j in cnt + 1:
			var q := p0 + dir * (1.5 + 2.7 * j) + inw * 0.4
			var q2 := q + inw * 4.8
			if not Geometry2D.is_point_in_polygon(q2, poly):
				continue
			_k(q.x, q.y, true).ribbon(PackedVector2Array([q, q2]), 0.1, 0.034, col, 0.0, false)


## Field lines: the outline and a centre line on fields and courts; the
## track gets lane lines from its outline inward.
func field_markings(a: Dictionary) -> void:
	var poly: PackedVector2Array = CampusData.ccw(a["poly"])
	var kind := String(a["kind"])
	var col := Color(0.9, 0.9, 0.88)
	var y := 0.03
	if kind == "track":
		for lane in 6:
			var off := CampusData.offset(poly, -1.22 * float(lane + 1))
			if off.size() < 3:
				break
			var closed := off.duplicate()
			closed.append(off[0])
			var c := CampusData.centroid(off)
			_k(c.x, c.y, true).ribbon(closed, 0.06, y, col, 0.0, false)
		return
	var closed2 := poly.duplicate()
	closed2.append(poly[0])
	var c2 := CampusData.centroid(poly)
	_k(c2.x, c2.y, true).ribbon(closed2, 0.12 if kind != "court" else 0.06, y, col, 0.0, false)
	var obb := obb_of(poly)
	var ax: Vector2 = obb["axis"]
	var aw := Vector2(-ax.y, ax.x)
	var size: Vector2 = obb["size"]
	var along_x := size.x >= size.y
	var long_v := ax if along_x else aw
	var short_v := aw if along_x else ax
	var half_s := (size.y if along_x else size.x) * 0.5
	var half_l := (size.x if along_x else size.y) * 0.5
	var cen: Vector2 = obb["center"]
	_k(cen.x, cen.y, true).ribbon(PackedVector2Array([cen - short_v * half_s, cen + short_v * half_s]), 0.12, y, col, 0.0, false)
	if kind == "field_turf" and half_l > 40.0:
		# yard lines every ~9 m
		var step := 9.14
		var t := -half_l + step
		while t < half_l - 1.0:
			var m := cen + long_v * t
			_k(m.x, m.y, true).ribbon(PackedVector2Array([m - short_v * half_s, m + short_v * half_s]), 0.1, y, col, 0.0, false)
			t += step


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
func _quad_facing(k: MeshKit, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, facing: Vector3) -> void:
	# MeshKit quads are clockwise from the front; flip to face `facing`
	if ((b - a).cross(c - a)).dot(facing) < 0.0:
		k.quad(a, b, c, d, col)
	else:
		k.quad(d, c, b, a, col)


func _tri_facing(k: MeshKit, a: Vector3, b: Vector3, c: Vector3, col: Color, facing: Vector3) -> void:
	if ((b - a).cross(c - a)).dot(facing) < 0.0:
		k.tri(a, b, c, col)
	else:
		k.tri(a, c, b, col)
