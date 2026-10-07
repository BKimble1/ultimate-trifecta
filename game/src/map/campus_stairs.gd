class_name CampusStairs
extends RefCounted
## Entrance stairs (CampusLayout.stairs, resolved by the terrain bake from
## each entrance's floor and the measured grade in front of it, or from the
## data's own stair): drawn as real treads and risers with cheeks and
## rails, and made walkable for the unchanged character motor.
##
## The motor snaps to the floor but has no step climbing, so a staircase
## collides as a close-fitting ramp under its nosings (the line through the
## front edges of the treads: every point of it is on or just above a
## tread, never more than a riser's height under a foot), level on its deck
## and landings.  Its sides are solid down into the ground (you can't walk
## under a stair), rails stand on the sides that have them, and one cart
## blocker covers the whole run (a 29 degree ramp is inside the carts' 35
## degree floor angle; the stair is not a road).  docs/campus/TERRAIN.md
## records the approximation.

const RAIL_H := 0.95        # handrail height above the nosing line
const LEAD_IN := 1.0        # a level slab behind the top edge, at the floor (the
                            # ground's 1 m samples leave a porch floor sloping
                            # down over the last metre before its mouth)
const RUN_OUT := 0.6        # a level slab past the last tread, at the bottom step
const RAIL_T := 0.12        # rail collision thickness
const CHEEK_T := 0.28       # the side walls' thickness (drawn)


## The walking line of a stair: [[d, y], ...] (d: distance out from its top
## edge), corners only: the deck, each flight's nosing line and each
## landing, ending one going past the last nosing on the ground.
static func profile(st: Dictionary) -> Array:
	var top := float(st["top"])
	var rise := float(st["rise"])
	var going := float(st["going"])
	var raw: Array = [[0.0, top]]
	var nos: Array = st["nosings"]
	for k in nos.size():
		raw.append([float(nos[k]), top - rise * float(k)])
		raw.append([float(nos[k]) + going, top - rise * float(k + 1)])
	var out: Array = []
	for q in raw:
		if not out.is_empty() and absf(float(q[0]) - float(out[-1][0])) < 0.001:
			out[-1] = q
			continue
		# a point on the line through the last two is not a corner
		if out.size() >= 2:
			var a: Array = out[-2]
			var b: Array = out[-1]
			var s0 := (float(b[1]) - float(a[1])) / maxf(float(b[0]) - float(a[0]), 0.001)
			var s1 := (float(q[1]) - float(b[1])) / maxf(float(q[0]) - float(b[0]), 0.001)
			if absf(s0 - s1) < 0.001:
				out[-1] = q
				continue
		out.append(q)
	return out


## World point of a stair at distance d out, height y.
static func at(st: Dictionary, d: float, y: float, side: float = 0.0) -> Vector3:
	var p: Vector2 = st["p"] + (st["dir"] as Vector2) * d + (st["tg"] as Vector2) * side
	return Vector3(p.x, y, p.y)


## The oriented box whose top face runs from A to B (both on the stair's
## centre line), `w` wide and `thick` deep below it: [Basis, centre].
static func slab(A: Vector3, B: Vector3, w: float, thick: float, lead: float = 0.0) -> Transform3D:
	var x_axis := (B - A).normalized()
	var z_axis := x_axis.cross(Vector3.UP).normalized()
	var y_axis := z_axis.cross(x_axis).normalized()
	var len := A.distance_to(B) + 2.0 * lead
	return Transform3D(Basis(x_axis * len, y_axis * thick, z_axis * w), (A + B) * 0.5 - y_axis * (thick * 0.5))


## Collision of one stair through `add(body, shape, xf)` (CampusBuilder's
## recipe): the walking surface (solid down past the bottom), rails, and a
## cart blocker.  body_world / body_block: the recipe's two bodies.
static func collision(st: Dictionary, add: Callable, body_world: int, body_block: int) -> void:
	var prof := profile(st)
	var w := float(st["w"])
	var deep := float(st["top"]) - float(st["bottom"]) + 1.2
	for i in prof.size() - 1:
		var A := at(st, float(prof[i][0]), float(prof[i][1]))
		var B := at(st, float(prof[i + 1][0]), float(prof[i + 1][1]))
		var bs := BoxShape3D.new()
		bs.size = Vector3.ONE
		# a few centimetres longer each way: no seam at a corner
		add.call(body_world, bs, slab(A, B, w, deep, 0.03))
		# rails on the flights and landings (not on the deck: a porch is open)
		if String(st["rails"]) != "none" and not (i == 0 and absf(float(prof[0][1]) - float(prof[1][1])) < 0.001 and float(prof[1][0]) > 0.0):
			for s: float in [-1.0, 1.0]:
				var off := (st["tg"] as Vector2) * (s * (w * 0.5 - RAIL_T * 0.5))
				var o3 := Vector3(off.x, 0.0, off.y)
				var xf := slab(A + o3 + Vector3(0, RAIL_H, 0), B + o3 + Vector3(0, RAIL_H, 0), RAIL_T, RAIL_H, 0.0)
				var rs := BoxShape3D.new()
				rs.size = Vector3.ONE
				add.call(body_world, rs, xf)
	# level slabs flush with the floor behind the top edge (a porch's floor
	# runs onto the stair without a seam) and with the walk past the last
	# tread (the terrain bake grades the ground there to the bottom step,
	# so the walk meets the stair without a lip)
	for ends: Array in [[-LEAD_IN, 0.0, float(st["top"])], [float(prof[-1][0]), float(prof[-1][0]) + RUN_OUT, float(st["bottom"])]]:
		var es := BoxShape3D.new()
		es.size = Vector3.ONE
		add.call(body_world, es, slab(at(st, float(ends[0]), float(ends[2])), at(st, float(ends[1]), float(ends[2])), w, deep, 0.03))
	# carts: never on a stair
	var length := float(prof[-1][0])
	var c := at(st, length * 0.5, (float(st["top"]) + float(st["bottom"])) * 0.5 + 0.6)
	var n: Vector2 = st["dir"]
	var cb := BoxShape3D.new()
	cb.size = Vector3(length + 0.6, float(st["top"]) - float(st["bottom"]) + 2.6, w + 0.4)
	add.call(body_block, cb, Transform3D(Basis(Vector3.UP, atan2(-n.y, n.x)), c))


## Draws one stair into `kit_at(x, z)` kits: stepped treads and risers
## down to the ground, cheek walls, a deck and landings, rails.
## light: the stone (porticos: a pale stone; otherwise concrete).
static func draw(st: Dictionary, kit_at: Callable, ground: Callable, light: bool, rail_col: Color) -> void:
	var c0: Vector3 = at(st, float(st["length"]) * 0.5, 0.0)
	var k: MeshKit = kit_at.call(c0.x, c0.z)
	var w := float(st["w"])
	var n: Vector2 = st["dir"]
	var tg: Vector2 = st["tg"]
	var n3 := Vector3(n.x, 0, n.y)
	var t3 := Vector3(tg.x, 0, tg.y)
	var stone := Color(0.80, 0.78, 0.74) if light else Color(0.62, 0.61, 0.58)
	var cheek := stone.darkened(0.12)
	var top := float(st["top"])
	var rise := float(st["rise"])
	var going := float(st["going"])
	var nos: Array = st["nosings"]
	# the lowest ground under the stair (the steps' solid reaches below it)
	var lo := float(st["bottom"])
	for f in [0.0, 0.5, 1.0]:
		for s in [-0.5, 0.5]:
			var q := at(st, float(st["length"]) * f, 0.0, w * s)
			lo = minf(lo, float(ground.call(q.x, q.z)))
	lo -= 0.25
	k.mat = MeshKit.M_STONE
	# deck: floor level from the top edge to the first nosing
	var tread := func(d0: float, d1: float, y: float) -> void:
		if d1 - d0 < 0.01:
			return
		var ctr := at(st, (d0 + d1) * 0.5, (y + lo) * 0.5)
		k.box_xf(Transform3D(Basis(n3 * (d1 - d0), Vector3.UP * (y - lo), t3 * w), ctr), stone.darkened(0.05), 0.0, 0.0, true, stone)
	tread.call(-0.05, float(nos[0]), top)
	for kk in range(1, nos.size()):
		# tread kk: from riser kk's nosing to riser kk + 1's (a landing is a
		# long tread)
		tread.call(float(nos[kk - 1]), float(nos[kk]), top - rise * float(kk))
	# nosing lines: a thin lighter edge on each step
	for kk in nos.size():
		var y := top - rise * float(kk)
		var e := at(st, float(nos[kk]) + 0.02, y - 0.02)
		k.box_xf(Transform3D(Basis(n3 * 0.05, Vector3.UP * 0.04, t3 * (w - 0.04)), e), stone.lightened(0.12))
	# cheek walls on both sides, stepped with the flights (to the ground)
	var prof := profile(st)
	for s: float in [-1.0, 1.0]:
		for i in prof.size() - 1:
			var d0 := float(prof[i][0])
			var d1 := float(prof[i + 1][0])
			var y0 := float(prof[i][1])
			var y1 := float(prof[i + 1][1])
			var pieces := maxi(1, int(ceil((d1 - d0) / 0.6)))
			for j in pieces:
				var a := d0 + (d1 - d0) * float(j) / float(pieces)
				var b := d0 + (d1 - d0) * float(j + 1) / float(pieces)
				var ytop := maxf(lerpf(y0, y1, float(j) / float(pieces)), lerpf(y0, y1, float(j + 1) / float(pieces))) + 0.18
				var ctr := at(st, (a + b) * 0.5, (ytop + lo) * 0.5, s * (w * 0.5 + CHEEK_T * 0.5))
				k.box_xf(Transform3D(Basis(n3 * (b - a + 0.01), Vector3.UP * (ytop - lo), t3 * CHEEK_T), ctr), cheek, 0.0, 0.0, true, cheek.lightened(0.08))
	k.mat = 0.0
	# rails: posts every ~1.2 m and a handrail along the walking line
	if String(st["rails"]) == "none":
		return
	k.mat = MeshKit.M_METAL
	for s: float in [-1.0, 1.0]:
		var side := s * (w * 0.5 - 0.1)
		for i in prof.size() - 1:
			var d0 := float(prof[i][0])
			var d1 := float(prof[i + 1][0])
			var y0 := float(prof[i][1])
			var y1 := float(prof[i + 1][1])
			if i == 0 and absf(y0 - y1) < 0.001 and d1 > 0.0:
				continue      # no rail on the open deck
			var A := at(st, d0, y0 + RAIL_H, side)
			var B := at(st, d1, y1 + RAIL_H, side)
			var dv := B - A
			var xa := dv.normalized()
			var za := xa.cross(Vector3.UP).normalized()
			var ya := za.cross(xa).normalized()
			k.box_xf(Transform3D(Basis(xa * (dv.length() + 0.06), ya * 0.06, za * 0.06), (A + B) * 0.5), rail_col)
			var posts := maxi(1, int(ceil((d1 - d0) / 1.2)))
			for j in posts + 1:
				var d := d0 + (d1 - d0) * float(j) / float(posts)
				var y := lerpf(y0, y1, float(j) / float(posts))
				var pp := at(st, d, y + RAIL_H * 0.5, side)
				k.box_xf(Transform3D(Basis(n3 * 0.05, Vector3.UP * RAIL_H, t3 * 0.05), pp), rail_col)
	k.mat = 0.0
