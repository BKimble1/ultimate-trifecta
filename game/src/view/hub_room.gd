class_name HubRoom
extends RefCounted
## The party room's walkable floor (V6 Walk around): the DormStage common
## room's open floor with its furniture as simple 2D obstacles.  The same
## code moves the local runner (HubWalk) and checks every pose the host
## receives (HubSync), so nobody can stand inside the couch or walk out of
## the room on any device.  Players never collide with each other (nobody
## can body-block a doorway or trap a friend), there is no jump, and the
## floor is flat: walking around is a social thing, not a game mode.

const WALK_SPEED := 2.4          # m/s at full stick (a relaxed indoor jog)
const RADIUS := 0.3              # a character's footprint
## x min, x max, z min, z max of the floor (walls, window and camera side)
const BOUNDS := Vector4(-5.55, 5.35, -2.95, 2.75)
## boxes: [centre x, centre z, half x, half z]
const BOXES := [
	[-3.6, -2.8, 1.65, 0.62],     # couch (with arms and back)
	[-1.9, -2.1, 0.42, 0.3],      # side table
	[5.1, -2.9, 0.78, 0.3],       # bookshelf
]
## circles: [x, z, r]
const CIRCLES := [
	[3.9, -1.9, 0.3],             # floor lamp
	[2.85, -2.35, 0.68],          # armchair
	[-5.3, 1.6, 0.42],            # plant
	[4.0, 1.1, 0.72],             # beanbag
]


## A position pushed out of the furniture and clamped to the floor.
static func resolve(p: Vector2) -> Vector2:
	var q := p
	for _i in 3:
		for c in CIRCLES:
			var cc := Vector2(float(c[0]), float(c[1]))
			var r := float(c[2]) + RADIUS
			var d := q - cc
			if d.length() < r:
				q = cc + (d.normalized() if d.length() > 0.001 else Vector2(0, 1)) * r
		for bx in BOXES:
			var c2 := Vector2(float(bx[0]), float(bx[1]))
			var h := Vector2(float(bx[2]) + RADIUS, float(bx[3]) + RADIUS)
			var rel := q - c2
			if absf(rel.x) < h.x and absf(rel.y) < h.y:
				# out along the shallower side
				var px := h.x - absf(rel.x)
				var pz := h.y - absf(rel.y)
				if px < pz:
					q.x = c2.x + signf(rel.x if rel.x != 0.0 else 1.0) * h.x
				else:
					q.y = c2.y + signf(rel.y if rel.y != 0.0 else 1.0) * h.y
		q.x = clampf(q.x, BOUNDS.x, BOUNDS.y)
		q.y = clampf(q.y, BOUNDS.z, BOUNDS.w)
	return q


## Is `p` a valid place to stand?
static func is_free(p: Vector2) -> bool:
	return resolve(p).distance_to(p) < 0.001


## One movement step with sliding: `from` moved by `delta_p`, never through
## furniture (the step is split so a fast frame can't tunnel).
static func step(from: Vector2, delta_p: Vector2) -> Vector2:
	var n := maxi(1, int(ceil(delta_p.length() / 0.15)))
	var q := from
	for i in n:
		q = resolve(q + delta_p / float(n))
	return q
