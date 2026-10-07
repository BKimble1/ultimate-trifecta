class_name CampusVehicles
extends RefCounted
## Human-scale scenery that explains a place: parked cars in the lots'
## stalls, bikes at racks and porches, and a few hammocks between trees.
## All original, neutral and static: no logos, plates or per-car scripts,
## nothing drivable.  Meshes are built once and drawn as chunked MultiMesh
## instances (CampusBuilder: one shared mesh per kind, a tint per car).
##
## Parked cars are gameplay geometry (a solid box each, in CampusLayout's
## solids, so the colliders, the bots' grid and the layout fingerprint all
## have them) and are placed deterministically from the lot outlines:
## `stalls()` lays out the same stalls the lot markings draw, `parked()`
## fills a share of them.  Bikes and hammocks are drawn only.

const KINDS := ["car_compact", "car_sedan", "car_suv", "car_pickup", "car_van"]
## [length, width, height, body height]
const SIZE := {
	"car_compact": [4.1, 1.76, 1.46, 0.56],
	"car_sedan": [4.75, 1.84, 1.45, 0.58],
	"car_suv": [4.75, 1.92, 1.76, 0.74],
	"car_pickup": [5.5, 2.0, 1.86, 0.76],
	"car_van": [5.1, 2.0, 2.0, 0.84],
}
## a restrained palette (white, black, silvers and greys, dark blue, dark
## red, beige, dark green), weighted toward the common ones
const PAINT := [Color(0.92, 0.92, 0.91), Color(0.92, 0.92, 0.91), Color(0.07, 0.07, 0.08), Color(0.07, 0.07, 0.08),
	Color(0.62, 0.64, 0.66), Color(0.62, 0.64, 0.66), Color(0.38, 0.40, 0.42), Color(0.38, 0.40, 0.42),
	Color(0.12, 0.18, 0.32), Color(0.36, 0.08, 0.08), Color(0.66, 0.60, 0.50), Color(0.14, 0.22, 0.17)]
const STALL_W := 2.7          # the lot markings' spacing (CampusArchitecture.lot_markings)
const STALL_D := 4.8

static var _meshes: Dictionary = {}


## The lots' stalls: [{"lot", "pos", "dir" (into the stall from the
## aisle... i.e. from its mouth to its back), "edge"}], along every lot edge
## of 14 m or more, between consecutive stall lines that both lie inside
## the lot (as the markings are drawn).
static func stalls(lot_id: String, poly_in: PackedVector2Array) -> Array:
	var poly := CampusData.ccw(poly_in)
	var out: Array = []
	var n := poly.size()
	for i in n:
		var p0 := poly[i]
		var p1 := poly[(i + 1) % n]
		var len := p0.distance_to(p1)
		if len < 14.0:
			continue
		var dir := (p1 - p0) / len
		var inw := Vector2(-dir.y, dir.x)
		var cnt := int((len - 3.0) / STALL_W)
		var ok_line := func(j: int) -> bool:
			var q := p0 + dir * (1.5 + STALL_W * float(j)) + inw * 0.4
			return Geometry2D.is_point_in_polygon(q + inw * STALL_D, poly)
		for j in cnt:
			if not ok_line.call(j) or not ok_line.call(j + 1):
				continue
			var c := p0 + dir * (1.5 + STALL_W * (float(j) + 0.5)) + inw * (0.4 + STALL_D * 0.5)
			out.append({"lot": lot_id, "pos": c, "back": -inw, "edge": i})
	return out


## Fills a share of a lot's stalls (deterministic from the lot id): a
## residence lot is fuller at night than an academic one; `free(p)` says
## whether a stall may hold a car (entries, walks, exits and spawns stay
## clear).  [{"kind", "pos", "yaw", "tint", "size": Vector3}]
static func parked(lot_id: String, poly: PackedVector2Array, free: Callable) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("parked:" + lot_id)
	var full := 0.72
	for w in ["dorm", "village", "hall", "court", "terrace", "north_court", "env_center_service"]:
		if lot_id.contains(w):
			full = 0.78
	if lot_id.contains("arena") or lot_id.contains("rec") or lot_id.contains("softball") or lot_id.contains("cc_") or lot_id.contains("innovation"):
		full = 0.42
	var out: Array = []
	for st in stalls(lot_id, poly):
		var p: Vector2 = st["pos"]
		var roll := rng.randf()
		var kind_roll := rng.randf()
		var paint := rng.randi_range(0, PAINT.size() - 1)
		var nose_in := rng.randf() < 0.8
		var jitter := rng.randf_range(-0.12, 0.12)
		if roll > full or not bool(free.call(p)):
			continue
		var kind := "car_sedan"
		if kind_roll < 0.2:
			kind = "car_compact"
		elif kind_roll < 0.55:
			kind = "car_sedan"
		elif kind_roll < 0.85:
			kind = "car_suv"
		elif kind_roll < 0.95:
			kind = "car_pickup"
		else:
			kind = "car_van"
		var sz: Array = SIZE[kind]
		var back: Vector2 = st["back"]
		# the car's own +x points to its front: nose in = front toward the
		# stall's back (the lot edge)
		var fwd := back if nose_in else -back
		var yaw := atan2(-fwd.y, fwd.x)
		out.append({"kind": kind, "pos": p + back * (STALL_D * 0.5 - float(sz[0]) * 0.5 - 0.25) * (1.0 if nose_in else 1.0) + Vector2(-back.y, back.x) * jitter,
			"yaw": yaw, "tint": PAINT[paint], "size": Vector3(float(sz[0]), float(sz[2]), float(sz[1]))})
	return out


## One kind's mesh (built once): a car in its own frame, +x forward, y up
## from the ground, centred; the body is white (the instance tint paints
## it), glass, tyres and lights keep their own colours.
static func mesh(kind: String) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var k := MeshKit.new()
	if kind == "bike":
		_bike(k)
	elif kind == "hammock_frame":
		pass
	else:
		_car(k, kind)
	_meshes[kind] = k.commit()
	return _meshes[kind]


static func _car(k: MeshKit, kind: String) -> void:
	var sz: Array = SIZE[kind]
	var L := float(sz[0])
	var W := float(sz[1])
	var H := float(sz[2])
	var bh := float(sz[3])
	var white := Color(1, 1, 1)
	var glass := Color(0.10, 0.12, 0.16)
	var tyre := Color(0.05, 0.05, 0.06)
	var clear := 0.28                     # ground clearance
	k.mat = MeshKit.M_METAL
	# lower body
	k.chamfer_box(Vector3(0, clear + bh * 0.5, 0), Vector3(L, bh, W), white, 0.12)
	# the cabin: glass all round, a painted roof
	var cab_l := L * 0.52
	var cab_x := -L * 0.06
	if kind == "car_van":
		cab_l = L * 0.86
		cab_x = -L * 0.04
	elif kind == "car_pickup":
		cab_l = L * 0.38
		cab_x = L * 0.08
	elif kind == "car_suv":
		cab_l = L * 0.62
		cab_x = -L * 0.08
	var cab_h := H - clear - bh
	k.mat = MeshKit.M_GLASS
	k.chamfer_box(Vector3(cab_x, clear + bh + cab_h * 0.45, 0), Vector3(cab_l, cab_h * 0.9, W * 0.88), glass, 0.1)
	k.mat = MeshKit.M_METAL
	k.chamfer_box(Vector3(cab_x, H - 0.05, 0), Vector3(cab_l * 0.94, 0.1, W * 0.86), white, 0.04)
	# pillars between the windows read as one painted band at the belt line
	k.chamfer_box(Vector3(cab_x, clear + bh + 0.04, 0), Vector3(cab_l + 0.02, 0.08, W * 0.9), white, 0.02)
	if kind == "car_pickup":
		# the open bed: low side walls behind the cab
		var bx := cab_x - cab_l * 0.5 - (L * 0.5 + cab_x - cab_l * 0.5) * 0.0
		var bed_len := (cab_x - cab_l * 0.5) - (-L * 0.5)
		var bc := -L * 0.5 + bed_len * 0.5
		for s: float in [-1.0, 1.0]:
			k.chamfer_box(Vector3(bc, clear + bh + 0.22, s * (W * 0.5 - 0.06)), Vector3(bed_len, 0.44, 0.1), white, 0.02)
		k.chamfer_box(Vector3(-L * 0.5 + 0.06, clear + bh + 0.22, 0), Vector3(0.1, 0.44, W - 0.1), white, 0.02)
		k.mat = MeshKit.M_PLAIN
		k.box(Vector3(bc, clear + bh + 0.01, 0), Vector3(bed_len - 0.1, 0.02, W - 0.2), Color(0.12, 0.12, 0.13))
		var _unused := bx
	# wheels: an octagon each side (two turned boxes), dark
	k.mat = MeshKit.M_PLAIN
	var r := 0.34
	for sx: float in [-1.0, 1.0]:
		for sz2: float in [-1.0, 1.0]:
			var c := Vector3(sx * (L * 0.5 - 0.8), r, sz2 * (W * 0.5 - 0.08))
			k.box_xf(Transform3D(Basis(Vector3(0, 0, 1), 0.0).scaled_local(Vector3(r * 1.8, r * 1.5, 0.24)), c), tyre)
			k.box_xf(Transform3D(Basis(Vector3(0, 0, 1), PI * 0.25).scaled_local(Vector3(r * 1.8, r * 1.5, 0.24)), c), tyre)
			k.box_xf(Transform3D(Basis.IDENTITY.scaled_local(Vector3(0.28, 0.28, 0.25)), c), Color(0.55, 0.56, 0.58))
	# lights: pale fronts, red tails
	k.mat = MeshKit.M_GLASS
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(L * 0.5 + 0.005, clear + bh * 0.72, s * (W * 0.5 - 0.3)), Vector3(0.04, 0.12, 0.34), Color(0.95, 0.94, 0.86))
		k.box(Vector3(-L * 0.5 - 0.005, clear + bh * 0.72, s * (W * 0.5 - 0.26)), Vector3(0.04, 0.12, 0.3), Color(0.55, 0.06, 0.05))
	# bumpers
	k.mat = MeshKit.M_PLAIN
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(s * (L * 0.5 + 0.03), clear + 0.1, 0), Vector3(0.12, 0.2, W * 0.96), Color(0.16, 0.16, 0.17))
	k.mat = 0.0


static func _bike(k: MeshKit) -> void:
	# a step-through campus bike: two wheels, a frame, a saddle and bars;
	# +x forward, standing upright, about 1.75 m long
	var frame := Color(1, 1, 1)
	var dark := Color(0.06, 0.06, 0.07)
	var r := 0.34
	k.mat = MeshKit.M_METAL
	for wx: float in [-0.55, 0.55]:
		var c := Vector3(wx, r, 0)
		for i in 10:
			var a0 := TAU * float(i) / 10.0
			var a1 := TAU * float(i + 1) / 10.0
			var p0 := c + Vector3(cos(a0), sin(a0), 0) * r
			var p1 := c + Vector3(cos(a1), sin(a1), 0) * r
			var m := (p0 + p1) * 0.5
			var d := p1 - p0
			k.box_xf(Transform3D(Basis(d, Vector3(-d.y, d.x, 0).normalized() * 0.04, Vector3(0, 0, 0.04)), m), dark)
	var seg := func(a: Vector3, b: Vector3, t: float, col: Color) -> void:
		var d := b - a
		var side := Vector3(0, 0, 1)
		var up := side.cross(d).normalized()
		k.box_xf(Transform3D(Basis(d, up * t, side * t), (a + b) * 0.5), col)
	var bb := Vector3(-0.05, 0.36, 0)      # bottom bracket
	var seat := Vector3(-0.22, 0.86, 0)
	var head := Vector3(0.42, 0.88, 0)
	seg.call(Vector3(-0.55, r, 0), bb, 0.035, frame)
	seg.call(bb, seat, 0.04, frame)
	seg.call(bb, head, 0.045, frame)
	seg.call(Vector3(-0.55, r, 0), seat, 0.03, frame)
	seg.call(head, Vector3(0.55, r, 0), 0.035, frame)
	k.mat = MeshKit.M_PLAIN
	k.box(seat + Vector3(0, 0.05, 0), Vector3(0.24, 0.06, 0.12), dark)
	k.box(head + Vector3(-0.04, 0.12, 0), Vector3(0.06, 0.04, 0.56), dark)
	k.mat = 0.0


## Hammock spots: pairs of trunks 3.4-5.6 m apart on open lawn near the
## residence buildings (none across a walk, a road, water or a building),
## at most `count`, deterministic.  [[trunk a, trunk b]]
static func hammock_spots(L: CampusLayout, count: int = 4) -> Array:
	var homes: Array = []
	for bd in L.buildings:
		if String(bd["kind"]) == "residence" and not bool(bd["background"]):
			homes.append(bd)
	var out: Array = []
	var used := {}
	var trees: Array = L.trees
	# the colliding trunks bucketed on a 25 m grid: each hall looks only at
	# the buckets round it
	const CELL := 25.0
	var buckets := {}
	for i in trees.size():
		var t: Dictionary = trees[i]
		if bool(t.get("collide", true)):
			var tp: Vector2 = t["pos"]
			var key := Vector2i(floori(tp.x / CELL), floori(tp.y / CELL))
			if not buckets.has(key):
				buckets[key] = []
			(buckets[key] as Array).append(i)
	for bd in homes:
		if out.size() >= count:
			break
		var c: Vector2 = bd["pos"]
		var best: Array = []
		var best_d := INF
		# the trees round this hall only (a pair search over the whole
		# campus would be millions of steps)
		var near: Array[int] = []
		var kc := Vector2i(floori(c.x / CELL), floori(c.y / CELL))
		for dz in range(-3, 4):
			for dx in range(-3, 4):
				for i in buckets.get(kc + Vector2i(dx, dz), []):
					if ((trees[i] as Dictionary)["pos"] as Vector2).distance_to(c) <= 75.0:
						near.append(i)
		near.sort()
		for ii in near.size():
			var i := near[ii]
			var a: Dictionary = trees[i]
			var pa: Vector2 = a["pos"]
			if pa.distance_to(c) > 70.0 or used.has(i):
				continue
			for jj in range(ii + 1, near.size()):
				var j := near[jj]
				var b: Dictionary = trees[j]
				var pb: Vector2 = b["pos"]
				var d := pa.distance_to(pb)
				if d < 3.4 or d > 5.6 or used.has(j) or not bool(b.get("collide", true)):
					continue
				var clear := true
				for f in [0.2, 0.5, 0.8]:
					var q := pa.lerp(pb, f)
					if L.is_on_path(q, 1.2) or L.is_on_road(q, 2.0) or L.water_index_at(q, 2.0) >= 0 or L.building_at(q, 3.0) >= 0 or not L.in_play(q):
						clear = false
				if not clear:
					continue
				var dc := pa.distance_to(c)
				if dc < best_d:
					best_d = dc
					best = [i, j]
		if not best.is_empty():
			used[best[0]] = true
			used[best[1]] = true
			out.append([(trees[best[0]] as Dictionary)["pos"], (trees[best[1]] as Dictionary)["pos"]])
	return out


## Draws a hammock slung between two trunks into kit `k`: straps from the
## trunks about 1.6 m up down to a sagging fabric bed (lowest about 0.6 m
## over the ground), in a restrained colour.
static func draw_hammock(k: MeshKit, a: Vector2, b: Vector2, ya: float, yb: float, col: Color) -> void:
	var d := b - a
	var len := d.length()
	var dir := d / len
	var side := Vector2(-dir.y, dir.x)
	var top_a := Vector3(a.x, ya + 1.6, a.y) + Vector3(dir.x, 0, dir.y) * 0.32
	var top_b := Vector3(b.x, yb + 1.6, b.y) - Vector3(dir.x, 0, dir.y) * 0.32
	var n := 10
	var pts: Array[Vector3] = []
	var bed0 := 0.22
	for i in n + 1:
		var t := float(i) / float(n)
		var base := top_a.lerp(top_b, t)
		var sag := 1.0 - pow(2.0 * t - 1.0, 2.0)
		pts.append(base - Vector3(0, 1.0 * sag, 0))
	k.mat = MeshKit.M_WOOD
	for i in n:
		var t0 := float(i) / float(n)
		var t1 := float(i + 1) / float(n)
		# the bed is wider in the middle (spreader-less, gathered at the ends)
		var w0 := 0.42 * sin(PI * t0) + 0.02
		var w1 := 0.42 * sin(PI * t1) + 0.02
		var s3 := Vector3(side.x, 0, side.y)
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var in_bed := t0 >= bed0 and t1 <= 1.0 - bed0 + 0.001
		var c0 := col if in_bed else Color(0.82, 0.78, 0.70)
		if not in_bed:
			w0 = 0.02
			w1 = 0.02
		k.quad(p0 - s3 * w0, p1 - s3 * w1, p1 + s3 * w1, p0 + s3 * w0, c0)
		k.quad(p0 + s3 * w0, p1 + s3 * w1, p1 - s3 * w1, p0 - s3 * w0, c0.darkened(0.15))
	k.mat = 0.0
