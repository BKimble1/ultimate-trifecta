class_name CampusLandmarks
extends RefCounted
## The waters, the custom landmark structures and the world beyond the play
## boundary for the reference campus.
##
## Waters: each is one MeshInstance3D with the water shader (its own
## material: `active` and `stamped` are set per round by MatchController).
## The surface is a triangulation of the traced outline (interior grid +
## shoreline samples) with each vertex's distance to the shore in UV.y, so
## the shader's deep/shallow gradient, foam line and splash ripples follow
## the real shoreline.  Objective markers: a ring of floating lanterns in the
## water's target colour along the inner shore, hidden by the shader unless
## the water is an active objective (decorative water never looks like one).
## Edges: coping on hard-edged basins, rocks on stone edges, a pebbly bank
## on natural ones (the ground does that); features: jets, docks, a beach.
##
## Sculptures in the real fountains are artworks with their own rights: they
## are represented by abstract, non-replica forms (an upright bronze-toned
## column and bowl; plain plinths), so no artwork is copied.
##
## Landmarks (buildings with a `landmark` key) are built here instead of by
## the generic building generator: the bell tower, the prayer chapel, the
## water tower.

var B: CampusBuilder
var L: CampusLayout

const STONE := Color(0.72, 0.70, 0.74)
const COPING := Color(0.78, 0.76, 0.72)
const BRICK_T := Color(0.60, 0.30, 0.24)
const TRIM := Color(0.93, 0.92, 0.89)
const M_MARKER := 9.0
const M_FLOW := 20.0


func _init(builder: CampusBuilder) -> void:
	B = builder
	L = builder.L


# ---------------------------------------------------------------------------
# Water
# ---------------------------------------------------------------------------
func water(i: int) -> void:
	var w: Dictionary = L.waters[i]
	var c: Vector2 = w["center"]
	var mi := MeshInstance3D.new()
	mi.name = "Water_%s" % w["id"]
	var mat := ShaderMaterial.new()
	mat.shader = CampusBuilder.WATER_SHADER
	mat.set_shader_parameter("target_color", w["color"])
	mat.set_shader_parameter("shape_kind", 2.0)
	var y: float = w["surface_y"]
	var k := MeshKit.new()
	for poly in w["polys"]:
		_surface(k, poly, c)
	if bool(w["objective"]):
		_markers(k, w, c)
	_edges(w)
	for f in w["features"]:
		_feature(w, f, k, mat)
	mi.mesh = k.commit()
	mi.material_override = mat
	mi.position = Vector3(c.x, y, c.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 420.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	B.container.add_child(mi)
	B.water_nodes[w["id"]] = {"node": mi, "mat": mat, "index": i}


## The surface of one polygon, local to `origin`: a Delaunay triangulation of
## shoreline samples and an interior grid, triangles outside dropped; UV.y =
## distance to the shore (m).
func _surface(k: MeshKit, poly: PackedVector2Array, origin: Vector2) -> void:
	var r := CampusData.bounds(poly)
	var area := r.get_area()
	var step := clampf(sqrt(area) / 18.0, 1.2, 5.0)
	var pts := PackedVector2Array()
	var dist := PackedFloat32Array()
	for s in CampusData.boundary_samples(poly, step * 0.7):
		pts.append(s[0])
		dist.append(0.0)
	# shore distance: the shader reads it only near the shore (< 3.5 m), so
	# only edges within SHORE_CAP count (bucketed: a big lake has many
	# points and edges, and every-edge-for-every-point cost 70 ms)
	var near := CampusData.edge_buckets(poly, SHORE_CAP)
	var x := r.position.x + step * 0.5
	while x < r.end.x:
		var z := r.position.y + step * 0.5
		while z < r.end.y:
			var p := Vector2(x + fposmod(z * 0.37, 0.3), z)
			if Geometry2D.is_point_in_polygon(p, poly):
				var d := CampusData.near_edge_dist(p, poly, near, SHORE_CAP)
				if d > step * 0.4:
					pts.append(p)
					dist.append(d)
			z += step
		x += step
	# grow the outline a little so the surface tucks under the bank
	var grown := CampusData.offset(poly, 0.35)
	var tris := Geometry2D.triangulate_delaunay(pts)
	for t in range(0, tris.size(), 3):
		var a := pts[tris[t]]
		var b := pts[tris[t + 1]]
		var c := pts[tris[t + 2]]
		var cen := (a + b + c) / 3.0
		if not Geometry2D.is_point_in_polygon(cen, grown if grown.size() >= 3 else poly):
			continue
		var A := Vector3(a.x - origin.x, 0, a.y - origin.y)
		var Bv := Vector3(b.x - origin.x, 0, b.y - origin.y)
		var C := Vector3(c.x - origin.x, 0, c.y - origin.y)
		var up := Vector3.UP
		var ua := Vector2(0.0, dist[tris[t]])
		var ub := Vector2(0.0, dist[tris[t + 1]])
		var uc := Vector2(0.0, dist[tris[t + 2]])
		if ((Bv - A).cross(C - A)).y < 0.0:
			k.tri_full(A, Bv, C, up, up, up, Color.WHITE, Color.WHITE, Color.WHITE, ua, ub, uc)
		else:
			k.tri_full(A, C, Bv, up, up, up, Color.WHITE, Color.WHITE, Color.WHITE, ua, uc, ub)


const SHORE_CAP := 8.0


## Floating lanterns (objective markers, hidden unless active) along the
## inner shore: up to 16, evenly around the outline, 1.2 m in from the edge.
func _markers(k: MeshKit, w: Dictionary, origin: Vector2) -> void:
	var col: Color = w["color"]
	var pts: Array[Vector2] = []
	var total := 0.0
	for poly in w["polys"]:
		total += CampusData.perimeter(poly)
	var count := clampi(int(total / 9.0), 5, 16)
	for poly in w["polys"]:
		var share := maxi(2, int(round(count * CampusData.perimeter(poly) / maxf(total, 0.1))))
		var samples := CampusData.boundary_samples(poly, CampusData.perimeter(poly) / float(share))
		for s in samples:
			var p: Vector2 = s[0] - (s[1] as Vector2) * 1.2
			if Geometry2D.is_point_in_polygon(p, poly):
				pts.append(p - origin)
	for j in pts.size():
		var p3 := Vector3(pts[j].x, 0.0, pts[j].y)
		k.mat = M_MARKER
		k.param = float(j) * 1.7
		k.revolve(p3, PackedVector2Array([Vector2(0.26, -0.06), Vector2(0.3, 0.02), Vector2(0.22, 0.08)]), PackedColorArray([Color(0.12, 0.10, 0.10)]), 10)
		k.revolve(p3, PackedVector2Array([Vector2(0.06, 0.06), Vector2(0.2, 0.14), Vector2(0.23, 0.32), Vector2(0.18, 0.5), Vector2(0.05, 0.58)]),
			PackedColorArray([col.darkened(0.2), col, col.lightened(0.1), col, col.darkened(0.2)]), 10, PackedFloat32Array(), 0.75)
		k.revolve(p3, PackedVector2Array([Vector2(0.12, 0.56), Vector2(0.1, 0.64), Vector2(0.0, 0.7)]), PackedColorArray([Color(0.15, 0.12, 0.1)]), 8)
	k.mat = 0.0
	k.param = 0.0


## Edges: coping on rimmed basins (the rim collider is CampusBuilder's),
## stone edging (rocks from the kit), reeds on natural banks.
func _edges(w: Dictionary) -> void:
	var rim := float(w["rim_h"])
	var edge := String(w.get("edge", ""))
	for poly in w["polys"]:
		var cp := CampusData.ccw(poly)
		var n := cp.size()
		if rim > 0.0:
			var th := float(w.get("rim_t", 0.5))
			for i in n:
				var a := cp[i]
				var b := cp[(i + 1) % n]
				var d := b - a
				var len := d.length()
				if len < 0.05:
					continue
				var dir := d / len
				var out := Vector2(dir.y, -dir.x)
				var mid := (a + b) * 0.5 + out * (th * 0.5)
				var k := B.kit_at(mid.x, mid.y)
				# on the paving round the basin (its collider is ground-relative too)
				var g0 := B.gy(mid.x, mid.y)
				k.mat = MeshKit.M_STONE
				k.chamfer_box(Vector3(mid.x, g0 + rim * 0.5 - 0.1, mid.y), Vector3(len + th * 0.9, rim + 0.2, th), COPING.darkened(0.08), 0.05, atan2(-dir.y, dir.x))
				k.chamfer_box(Vector3(mid.x, g0 + rim + 0.04, mid.y), Vector3(len + th, 0.08, th + 0.1), COPING, 0.03, atan2(-dir.y, dir.x))
				k.mat = 0.0
			continue
		var stony := edge == "stone"
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(String(w["id"]))
		for s in CampusData.boundary_samples(cp, 2.2 if stony else 7.0):
			var p: Vector2 = s[0]
			var nrm: Vector2 = s[1]
			if B.L.near_deck(p, 1.2):
				continue      # a footbridge or a dock lands here
			if stony:
				var q := p + nrm * 0.2
				var sc := rng.randf_range(0.5, 1.0)
				var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc * 1.3, sc * 0.7, sc)), Vector3(q.x, B.gy(q.x, q.y) - 0.15, q.y))
				B.mm_add("decor", Vector3(q.x, 0, q.y), "rock_round", xf, Color(1, 1, 1) * rng.randf_range(0.85, 1.05), Color(1, 1, 1))
			elif String(w["kind"]) in ["pond", "lake", "channel"] and rng.randf() < 0.45:
				var q2 := p - nrm * 0.4
				var xf2 := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.3)), Vector3(q2.x, float(w["surface_y"]) - 0.1, q2.y))
				B.mm_add("decor", Vector3(q2.x, 0, q2.y), "reeds", xf2, Color(1, 1, 1), Color(1, 1, 1))


## Water features from the data: fountain jets, a dock, a beach, a plain
## plinth or an abstract upright centrepiece (no artwork is reproduced).
func _feature(w: Dictionary, f: Dictionary, k: MeshKit, mat: ShaderMaterial) -> void:
	var kind := String(f.get("kind", ""))
	var c: Vector2 = w["center"]
	var p: Vector2 = CampusLayout._v2(f.get("p", [c.x, c.y]))
	var y := float(w["surface_y"])
	match kind:
		"jet":
			# a column of white water rising from the surface (flowing-water material)
			var h := float(f.get("h", 3.0))
			var lp := Vector3(p.x - c.x, 0.0, p.y - c.y)
			k.mat = M_FLOW
			k.revolve(lp, PackedVector2Array([Vector2(0.35, 0.0), Vector2(0.22, h * 0.4), Vector2(0.12, h * 0.85), Vector2(0.28, h), Vector2(0.5, h * 0.82), Vector2(0.6, h * 0.5), Vector2(0.9, 0.05)]),
				PackedColorArray([Color(0.85, 0.92, 0.98), Color(0.9, 0.95, 1.0), Color(0.95, 0.98, 1.0), Color(0.95, 0.98, 1.0), Color(0.9, 0.95, 1.0), Color(0.85, 0.92, 0.98), Color(0.8, 0.9, 0.96)]), 14)
			k.mat = 0.0
			mat.set_shader_parameter("fountain", 0.0)
		"pillar_bowl":
			# a slender tapered dark-stone pillar standing in the basin, an open
			# bronze bowl on top, water spilling from its lip into the basin
			var kk2 := B.kit_at(p.x, p.y)
			var hp := float(f.get("h", 2.4))
			var r0 := float(f.get("r", 0.3))
			var fl := float(w["floor_y"])
			# its heights are above the plaza's grade (the ground it stands in)
			var g := B.L.terrain_y(p)
			kk2.mat = MeshKit.M_STONE
			var steps := 4
			for si in steps:
				var t0 := float(si) / steps
				var t1 := float(si + 1) / steps
				var wdt := r0 * 2.0 * lerpf(1.0, 0.72, (t0 + t1) * 0.5)
				var yb := lerpf(fl, g + hp - 0.25, t0)
				var yt := lerpf(fl, g + hp - 0.25, t1)
				kk2.box(Vector3(p.x, (yb + yt) * 0.5, p.y), Vector3(wdt, yt - yb + 0.02, wdt), Color(0.24, 0.24, 0.26).lightened(0.04 * si), 0.0)
			kk2.mat = MeshKit.M_METAL
			kk2.revolve(Vector3(p.x, g + hp - 0.27, p.y), PackedVector2Array([Vector2(0.12, 0.0), Vector2(0.3, 0.12), Vector2(0.5, 0.26), Vector2(0.56, 0.3), Vector2(0.5, 0.32)]),
				PackedColorArray([Color(0.30, 0.22, 0.14), Color(0.34, 0.25, 0.16), Color(0.40, 0.30, 0.18), Color(0.46, 0.35, 0.22), Color(0.36, 0.27, 0.17)]), 14)
			kk2.mat = 0.0
			# four thin falls from the lip to the surface (the flowing-water material)
			k.mat = M_FLOW
			for fi in 4:
				var ang := TAU * (float(fi) + 0.5) / 4.0
				var d2 := Vector3(cos(ang), 0, sin(ang))
				var top := Vector3(p.x - c.x, g + hp + 0.03 - y, p.y - c.y) + d2 * 0.55
				var bot := Vector3(p.x - c.x, 0.02, p.y - c.y) + d2 * 0.75
				var side := Vector3(-d2.z, 0, d2.x) * 0.025
				k.quad(top - side, top + side, bot + side, bot - side, Color(0.86, 0.93, 0.98))
				k.quad(bot - side, bot + side, top + side, top - side, Color(0.86, 0.93, 0.98))
			k.mat = 0.0
			mat.set_shader_parameter("fountain", 0.0)
		"statue_base", "centerpiece":
			# an abstract upright form on a plinth (bronze-toned), not a replica
			var kk := B.kit_at(p.x, p.y)
			var g2 := B.L.terrain_y(p)
			kk.mat = MeshKit.M_STONE
			kk.chamfer_box(Vector3(p.x, (y + g2 + 0.7) * 0.5, p.y), Vector3(1.1, g2 + 0.7 - y, 1.1), STONE.darkened(0.1), 0.06)
			kk.mat = MeshKit.M_METAL
			var hh := float(f.get("h", 2.6))
			kk.revolve(Vector3(p.x, g2 + 0.7, p.y), PackedVector2Array([Vector2(0.32, 0), Vector2(0.24, hh * 0.6), Vector2(0.36, hh * 0.85), Vector2(0.62, hh), Vector2(0.5, hh + 0.12)]),
				PackedColorArray([Color(0.30, 0.24, 0.18), Color(0.34, 0.27, 0.2), Color(0.38, 0.30, 0.22), Color(0.36, 0.28, 0.2), Color(0.3, 0.24, 0.18)]), 12)
			kk.mat = 0.0
		"bridge", "dock":
			# the deck CampusLayout made solid (platforms), drawn: a concrete
			# footbridge with black steel railings, or a grey plank dock on
			# posts down into the water
			var bridge := kind == "bridge"
			var deck := Color(0.70, 0.69, 0.66) if bridge else Color(0.62, 0.60, 0.56)
			for pf in CampusLayout.feature_decks(w, f, B.L.terrain_y):
				var pc: Vector3 = pf["center"]
				var sz: Vector3 = pf["size"]
				var yaw := float(pf["yaw"])
				var ax := Vector3(cos(yaw), 0, -sin(yaw))
				var nr := Vector3(sin(yaw), 0, cos(yaw))
				var kd := B.kit_at(pc.x, pc.z)
				kd.mat = MeshKit.M_STONE if bridge else MeshKit.M_WOOD
				kd.chamfer_box(pc - Vector3(0, sz.y * 0.5, 0), sz, deck, 0.03, yaw)
				kd.mat = MeshKit.M_WOOD
				var np := maxi(2, int(sz.x / 2.4))
				for j in np + 1:
					var q := pc + ax * (sz.x * (float(j) / float(np) - 0.5))
					for sd: float in [-1.0, 1.0]:
						var post := q + nr * (sd * (sz.z * 0.5 - 0.12))
						if bridge:
							kd.mat = MeshKit.M_METAL
							kd.box(post + Vector3(0, 0.52, 0), Vector3(0.07, 1.0, 0.07), CampusArchitecture.IRON, yaw)
						else:
							kd.revolve(Vector3(post.x, y - 0.6, post.z), PackedVector2Array([Vector2(0.11, 0.0), Vector2(0.11, pc.y - y + 0.55)]), PackedColorArray([Color(0.35, 0.27, 0.2)]), 8)
				if bridge:
					# railings: black steel pickets between a bottom and a top rail
					var kp := B.kit_at(pc.x, pc.z, false, true)
					kd.mat = MeshKit.M_METAL
					kp.mat = MeshKit.M_METAL
					var npk := int(sz.x / 0.16)
					for sd2: float in [-1.0, 1.0]:
						var rc := pc + nr * (sd2 * (sz.z * 0.5 - 0.05))
						kd.box(rc + Vector3(0, 0.16, 0), Vector3(sz.x, 0.05, 0.05), CampusArchitecture.IRON, yaw)
						kd.box(rc + Vector3(0, 1.02, 0), Vector3(sz.x, 0.06, 0.08), CampusArchitecture.IRON, yaw)
						for pk in npk:
							var q2 := rc + ax * (sz.x * ((float(pk) + 0.5) / float(npk) - 0.5))
							kp.box(q2 + Vector3(0, 0.59, 0), Vector3(0.025, 0.86, 0.025), CampusArchitecture.IRON.darkened(0.1), yaw)
					kp.mat = 0.0
				kd.mat = 0.0
		"island":
			# a floating swim raft: white floats with a deck, a ladder frame on
			# the large diving platform
			var sz2: Vector2 = CampusLayout._v2(f.get("size", [3.0, 3.0]))
			var yaw2 := -deg_to_rad(float(f.get("rot", 0.0)))
			var kr := B.kit_at(p.x, p.y)
			kr.mat = MeshKit.M_PLASTER
			kr.chamfer_box(Vector3(p.x, y + 0.1, p.y), Vector3(sz2.x, 0.3, sz2.y), Color(0.86, 0.86, 0.83), 0.06, yaw2)
			if sz2.y >= 6.0:
				kr.mat = MeshKit.M_METAL
				var fax := Vector3(sin(yaw2), 0, cos(yaw2))
				var fside := Vector3(cos(yaw2), 0, -sin(yaw2))
				var fc := Vector3(p.x, y + 0.25, p.y) + fax * (sz2.y * 0.5 - 0.6)
				for sd3: float in [-1.0, 1.0]:
					kr.box(fc + fside * (sd3 * 0.8) + Vector3(0, 0.7, 0), Vector3(0.08, 1.4, 0.08), CampusArchitecture.IRON.lightened(0.5), yaw2)
				kr.box(fc + Vector3(0, 1.4, 0), Vector3(1.7, 0.08, 0.08), CampusArchitecture.IRON.lightened(0.5), yaw2)
			kr.mat = 0.0


# ---------------------------------------------------------------------------
# Shelters (pergola, pavilion)
# ---------------------------------------------------------------------------
## A timber shelter: posts, beams and (pavilion) a pitched roof.
func shelter(pr: Dictionary) -> void:
	var p: Vector2 = pr["pos"]
	var rot := float(pr["rot"])
	var len := maxf(6.0, float(pr.get("len", 10.0)))
	var pav := String(pr["kind"]) == "pavilion"
	var wd := len * (0.55 if pav else 0.4)
	var k := B.kit_at(p.x, p.y)
	var ax := Vector3(cos(rot), 0, -sin(rot))
	var aw := Vector3(sin(rot), 0, cos(rot))
	var c := Vector3(p.x, 0, p.y)
	var h := 3.2
	var wood := Color(0.52, 0.36, 0.24)
	k.mat = MeshKit.M_WOOD
	var nl := maxi(2, int(len / 3.5) + 1)
	for i in nl:
		for s: float in [-1.0, 1.0]:
			var q := c + ax * (-len * 0.5 + len * float(i) / float(nl - 1)) + aw * (wd * 0.5 * s)
			k.chamfer_box(q + Vector3(0, h * 0.5, 0), Vector3(0.3, h, 0.3), wood, 0.04, rot)
	for s: float in [-1.0, 1.0]:
		k.chamfer_box(c + aw * (wd * 0.5 * s) + Vector3(0, h + 0.15, 0), Vector3(len + 0.6, 0.3, 0.3), wood.darkened(0.05), 0.04, rot)
	if pav:
		var rise := wd * 0.35
		var col := Color(0.30, 0.27, 0.25)
		k.mat = MeshKit.M_ROOF
		for s: float in [-1.0, 1.0]:
			var e0 := c - ax * (len * 0.5 + 0.8) + aw * ((wd * 0.5 + 0.8) * s) + Vector3(0, h + 0.2, 0)
			var e1 := c + ax * (len * 0.5 + 0.8) + aw * ((wd * 0.5 + 0.8) * s) + Vector3(0, h + 0.2, 0)
			var r0 := c - ax * (len * 0.5 + 0.8) + Vector3(0, h + 0.2 + rise, 0)
			var r1 := c + ax * (len * 0.5 + 0.8) + Vector3(0, h + 0.2 + rise, 0)
			_quad_facing(k, e0, e1, r1, r0, col if s > 0.0 else col.darkened(0.1), (aw * s + Vector3.UP).normalized())
			_quad_facing(k, e0, e1, r1, r0, wood.darkened(0.3), (-aw * s - Vector3.UP).normalized())
	else:
		var nj := int(len / 0.6)
		for j in nj:
			var q2 := c + ax * (-len * 0.5 + len * (float(j) + 0.5) / nj) + Vector3(0, h + 0.38, 0)
			k.chamfer_box(q2, Vector3(0.12, 0.16, wd + 0.8), wood, 0.02, rot)
	k.mat = 0.0


# ---------------------------------------------------------------------------
# Landmarks
# ---------------------------------------------------------------------------
## Builds a landmark building; false: not a landmark here (use the generic).
func landmark(bd: Dictionary) -> bool:
	match String(bd["landmark"]):
		"bell_tower":
			CampusTower.build(B, bd)
			return true
		"prayer_chapel":
			CampusChapel.build(B, bd)
			return true
		"water_tower":
			_water_tower(bd)
			return true
	return false


func _water_tower(bd: Dictionary) -> void:
	var c := CampusData.centroid(bd["poly"])
	var h := maxf(30.0, float(bd["h"]))
	var k := B.kit_at(c.x, c.y)
	k.mat = MeshKit.M_METAL
	var col := Color(0.80, 0.82, 0.84)
	for i in 6:
		var a := TAU * float(i) / 6.0
		var leg := Vector3(c.x + cos(a) * 4.2, 0, c.y + sin(a) * 4.2)
		var top := Vector3(c.x + cos(a) * 3.0, h - 6.0, c.y + sin(a) * 3.0)
		var mid := (leg + top) * 0.5
		k.chamfer_box(mid, Vector3(0.35, leg.distance_to(top), 0.35), col.darkened(0.1), 0.05)
	k.revolve(Vector3(c.x, h - 7.0, c.y), PackedVector2Array([Vector2(1.2, 0), Vector2(5.8, 2.5), Vector2(6.4, 5.0), Vector2(5.6, 7.0), Vector2(1.0, 8.4), Vector2(0.4, 9.0)]),
		PackedColorArray([col, col, col.lightened(0.05), col, col.darkened(0.05), col]), 24)
	k.revolve(Vector3(c.x, 0, c.y), PackedVector2Array([Vector2(0.9, 0), Vector2(0.9, h - 6.0)]), PackedColorArray([col.darkened(0.15)]), 10)
	k.mat = 0.0
	# aircraft warning light
	k.mat = MeshKit.M_GLASS
	k.box(Vector3(c.x, h + 2.1, c.y), Vector3(0.3, 0.3, 0.3), Color(1.0, 0.25, 0.2), 0.0, 1.0)
	k.mat = 0.0


# ---------------------------------------------------------------------------
# Beyond the play boundary
# ---------------------------------------------------------------------------
## Woods and tree lines beyond the boundary (areas of kind woods outside the
## play area are filled with kit trees, sparse and far LOD), and a band of
## trees along the horizon where the data has nothing.
func background() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for a in L.areas:
		if String(a["kind"]) != "woods":
			continue
		var poly: PackedVector2Array = a["poly"]
		var r: Rect2 = a["rect"]
		var inside_play := Geometry2D.is_point_in_polygon(CampusData.centroid(poly), L.play_boundary)
		var spacing := 7.0 if inside_play else 10.0
		var x := r.position.x
		while x < r.end.x:
			var z := r.position.y
			while z < r.end.y:
				var p := Vector2(x + rng.randf_range(-2.5, 2.5), z + rng.randf_range(-2.5, 2.5))
				z += spacing
				if not Geometry2D.is_point_in_polygon(p, poly):
					continue
				if inside_play:
					continue    # woods inside the play area get their own traced trees
				var s := rng.randf_range(1.4, 2.2)
				var sp := "oak" if rng.randf() < 0.6 else ("linden" if rng.randf() < 0.5 else "fir")
				var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(p.x, B.gy(p.x, p.y), p.y))
				B.mm_add("far", Vector3(p.x, 0, p.y), sp, xf, Color(0.62, 0.66, 0.78), Color(1, 1, 1))
			x += spacing


func _quad_facing(k: MeshKit, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, facing: Vector3) -> void:
	if ((b - a).cross(c - a)).dot(facing) < 0.0:
		k.quad(a, b, c, d, col)
	else:
		k.quad(d, c, b, a, col)
