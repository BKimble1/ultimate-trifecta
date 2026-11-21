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
	[-5.78, DormStage.FIRE_Z, 0.32, 1.0],   # (2.3) the fireplace and hearth
]
## circles: [x, z, r]
const CIRCLES := [
	[3.9, -1.9, 0.3],             # floor lamp
	[DormStage.ARMCHAIR.x, DormStage.ARMCHAIR.z, 0.68],   # armchair
	[1.5, -2.4, 0.95],            # Season 1: the tree and its presents
	[-5.3, 1.6, 0.42],            # plant
	[4.0, 1.1, 0.72],             # beanbag
	[HubBall.HOOP_BASE.x, HubBall.HOOP_BASE.y, 0.36],   # (build 24) the hoop's base
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


# ---------------------------------------------------------------------------
# (build 20) Things to do in the party room
# ---------------------------------------------------------------------------
## Walk up to the couch, the floor lamp or the plant by the fireplace and a
## button offers what you can do there: bounce on the couch, switch the lamp
## off or on, hide in the plant.  One person at a time on the couch and in
## the plant (the host decides, HubSync).  Reach is measured from the edge
## of the prop's footprint, so it works from any side you can stand on.
const REACH := 0.8
## a little slack for the host's check (a pose from a tick ago)
const REACH_SLACK := 0.35
const PROP_COUCH := "couch"
const PROP_LAMP := "lamp"
const PROP_PLANT := "plant"
## the seat you bounce on (stage space): the top of the cushions, kept
## between the arms
const COUCH_SEAT_Y := 0.68
const COUCH_SEAT_Z := -2.58
const COUCH_SEAT_X := Vector2(-4.55, -2.65)


## Distance from `p` to the edge of a prop's footprint (INF: no such prop).
static func prop_dist(prop: String, p: Vector2) -> float:
	match prop:
		PROP_COUCH:
			var b: Array = BOXES[0]
			var q := Vector2(clampf(p.x, float(b[0]) - float(b[2]), float(b[0]) + float(b[2])),
				clampf(p.y, float(b[1]) - float(b[3]), float(b[1]) + float(b[3])))
			return p.distance_to(q)
		PROP_LAMP:
			var c: Array = CIRCLES[0]
			return maxf(0.0, p.distance_to(Vector2(float(c[0]), float(c[1]))) - float(c[2]))
		PROP_PLANT:
			var c2: Array = CIRCLES[3]
			return maxf(0.0, p.distance_to(Vector2(float(c2[0]), float(c2[1]))) - float(c2[2]))
	return INF


## The prop within reach of `p` (the nearest), or "".
static func prop_near(p: Vector2) -> String:
	var best := ""
	var bd := REACH
	for prop in [PROP_COUCH, PROP_LAMP, PROP_PLANT]:
		var d := prop_dist(prop, p)
		if d <= bd:
			bd = d
			best = prop
	return best


## Where on the couch someone standing at `p` bounces (stage space).
static func couch_seat(p: Vector2) -> Vector3:
	return Vector3(clampf(p.x, COUCH_SEAT_X.x, COUCH_SEAT_X.y), COUCH_SEAT_Y, COUCH_SEAT_Z)


## The middle of the plant (stage space): where a hider ducks in.
static func plant_middle() -> Vector3:
	var c: Array = CIRCLES[3]
	return Vector3(float(c[0]), 0.55, float(c[1]))
