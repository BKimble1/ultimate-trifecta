class_name ClassicDorms
extends RefCounted
## The classic map's three playable dorms as the 2.0 build defined them
## (restored from that source): fictional halls built from the campus kit,
## each with a compact ground-floor common room behind the front facade and
## real door openings onto the campus.  Here for the classic look
## (ClassicLayout, ClassicDormArt) only: gameplay builds the same dorms
## through CampusDorms from the exported start_dorm definitions
## (game/data/maps/classic/gameplay.json), and test_classic_map checks the
## two agree wall for wall and door for door.
## Coordinates as ClassicLayout: metres, +X east, +Z south.
##
## Shape of a dorm (all three face north, toward the campus):
##
##      front face (z_f) ──┬── front door ──┬──
##      │  common room (interior)           │   <- west / east doors in the
##      │  open, ceiling at CEIL            │      end walls, mid-room
##      ├───────────────────────────────────┤ block_z
##      │  closed block (rooms upstairs)    │
##      └───────────────────────────────────┘ z_b

const WALL_T := 0.5      # outer wall thickness around the common room
const DOOR_W := 3.2      # clear opening
const DOOR_H := 3.0      # opening height (lintel above)
const CEIL := 4.6        # common-room ceiling (the upper block starts here)
## Threshold: the line across the door at the wall's inner face.  A runner's
## centre must cross it inward within this half-width (the capsule can't get
## nearer the jambs anyway) at a feet height inside FINISH_Y.
const THRESH_HALF_W := 1.5
const FINISH_Y := Vector2(-0.5, 1.6)
## A crossing longer than this in one tick is a teleport, never a finish.
const MAX_STEP_M := 3.0

const DORMS := [
	{"id": "puddlesworth", "name": "Puddlesworth Hall", "short": "Puddlesworth",
		"pos": Vector2(0, 112), "size": Vector2(44, 18), "h": 11.0, "gallery": 9.5,
		"wall": Color(0.64, 0.34, 0.30), "roof": Color(0.26, 0.30, 0.42), "accent": Color(0.24, 0.32, 0.78),
		"inner": Color(0.93, 0.80, 0.62), "floor": Color(0.44, 0.30, 0.21), "fabric": Color(0.62, 0.22, 0.22), "style": "brick", "warm": 0.9},
	{"id": "lanternfield", "name": "Lanternfield House", "short": "Lanternfield",
		"pos": Vector2(-96, 114), "size": Vector2(28, 20), "h": 9.5, "gallery": 9.5,
		"wall": Color(0.88, 0.82, 0.68), "roof": Color(0.20, 0.44, 0.46), "accent": Color(0.96, 0.74, 0.30),
		"inner": Color(0.96, 0.86, 0.66), "floor": Color(0.50, 0.37, 0.25), "fabric": Color(0.18, 0.46, 0.48), "style": "cupola", "warm": 0.85},
	{"id": "moonpenny", "name": "Moonpenny Lodge", "short": "Moonpenny",
		"pos": Vector2(96, 113), "size": Vector2(24, 26), "h": 8.5, "gallery": 9.5,
		"wall": Color(0.55, 0.64, 0.50), "roof": Color(0.50, 0.21, 0.21), "accent": Color(0.40, 0.78, 0.74),
		"inner": Color(0.92, 0.78, 0.60), "floor": Color(0.40, 0.28, 0.20), "fabric": Color(0.78, 0.56, 0.20), "style": "lodge", "warm": 0.85},
]

## The areas V6 rebuilt around the dorms (layout, colliders and nav may
## differ from V5 only inside these; test_campus_art proves the rest is
## identical).  Puddlesworth keeps its V5 grounds; the other two dorms
## stand on what were open lawns between the service roads.
const DISTRICTS := {
	"puddlesworth": Rect2(-28.0, 98.0, 56.0, 26.0),
	"lanternfield": Rect2(-118.5, 89.0, 45.0, 50.0),
	"moonpenny": Rect2(73.5, 89.0, 45.0, 50.0),
}

## The cart-free strip of dorm yards along the south of the campus
## (Puddlesworth's grounds and the two new yards, bollards all round).
const YARDS := Rect2(-116.4, 91.8, 232.8, 44.8)

static var _geo: Dictionary = {}


static func ids() -> Array[String]:
	var out: Array[String] = []
	for d in DORMS:
		out.append(String(d["id"]))
	return out


static func has_dorm(id: String) -> bool:
	return ids().has(id)


static func def(id: String) -> Dictionary:
	for d in DORMS:
		if String(d["id"]) == id:
			return d
	return {}


static func display_name(id: String) -> String:
	return String(def(id).get("name", "the dorm"))


static func default_id() -> String:
	return String(DORMS[0]["id"])


# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------
## Everything about one dorm's shape (cached):
##   room      Rect2 interior of the common room (XZ)
##   boxes     [[center Vector3, size Vector3, kind]] world colliders
##   foot      [Rect2] footprints that block walking (nav)
##   footprint Rect2 of the whole building
##   doors     [{id, name, dorm, pos, normal, line_p, n_in, tangent, half_w, approach, inside}]
##   pads      [{pos, yaw}] runner spawn pads inside, facing an exit
##   respawn   [Vector2] pre-first-stamp return pads, one inside each door
##   cart_lines [[a, b]] cart-only blockers across every door opening
static func geometry(id: String) -> Dictionary:
	if _geo.has(id):
		return _geo[id]
	var d := def(id)
	if d.is_empty():
		return {}
	var g := _build(d)
	_geo[id] = g
	return g


static func _build(d: Dictionary) -> Dictionary:
	var pos: Vector2 = d["pos"]
	var size: Vector2 = d["size"]
	var h: float = d["h"]
	var gal: float = d["gallery"]
	var T := WALL_T
	var xw := pos.x - size.x * 0.5
	var xe := pos.x + size.x * 0.5
	var zf := pos.y - size.y * 0.5
	var zb := pos.y + size.y * 0.5
	var bz := zf + gal                    # front of the closed block
	var room := Rect2(xw + T, zf + T, size.x - 2.0 * T, gal - T)
	var cx := pos.x
	var side_z := zf + T + (gal - T) * 0.5
	var hw := DOOR_W * 0.5
	var boxes: Array = []
	var add := func(x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, kind: String) -> void:
		boxes.append([Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5), Vector3(x1 - x0, y1 - y0, z1 - z0), kind])
	# closed block (the rest of the building, full height)
	add.call(xw, xe, 0.0, h, bz, zb, "block")
	# upper block over the common room (ceiling and the floors above)
	add.call(xw, xe, CEIL, h, zf, bz, "upper")
	# front wall with the front door
	add.call(xw, cx - hw, 0.0, CEIL, zf, zf + T, "wall")
	add.call(cx + hw, xe, 0.0, CEIL, zf, zf + T, "wall")
	add.call(cx - hw, cx + hw, DOOR_H, CEIL, zf, zf + T, "lintel")
	# end walls with the west / east doors (between the front wall and the block)
	for side in [-1.0, 1.0]:
		var x0: float = xw if side < 0.0 else xe - T
		var x1: float = x0 + T
		add.call(x0, x1, 0.0, CEIL, zf + T, side_z - hw, "wall")
		add.call(x0, x1, 0.0, CEIL, side_z + hw, bz, "wall")
		add.call(x0, x1, DOOR_H, CEIL, side_z - hw, side_z + hw, "lintel")
	# furniture with collision (nothing a runner could clip into): two sofa
	# runs and the fireplace hearth along the back wall of the common room
	var w := room.size.x
	for s in [-1.0, 1.0]:
		var a: float = cx + s * w * 0.18
		var b: float = cx + s * w * 0.40
		add.call(minf(a, b), maxf(a, b), 0.0, 0.85, bz - 1.0, bz, "sofa")
	add.call(cx - 1.4, cx + 1.4, 0.0, 1.1, bz - 0.45, bz, "hearth")
	var foot: Array = []
	for bx in boxes:
		var c: Vector3 = bx[0]
		var sz: Vector3 = bx[1]
		if c.y - sz.y * 0.5 < 1.0:
			foot.append(Rect2(c.x - sz.x * 0.5, c.z - sz.z * 0.5, sz.x, sz.z))
	# doors: outer face point, outward normal, threshold at the inner face
	var doors: Array = []
	var specs := [
		["front", "Front door", Vector2(cx, zf), Vector2(0, -1)],
		["west", "West door", Vector2(xw, side_z), Vector2(-1, 0)],
		["east", "East door", Vector2(xe, side_z), Vector2(1, 0)],
	]
	for sp in specs:
		var p: Vector2 = sp[2]
		var n: Vector2 = sp[3]
		var n_in := -n
		var line_p := p + n_in * T
		doors.append({"id": String(sp[0]), "name": String(sp[1]), "dorm": String(d["id"]), "pos": p, "normal": n,
			"line_p": line_p, "n_in": n_in, "tangent": Vector2(-n_in.y, n_in.x), "half_w": THRESH_HALF_W,
			"approach": p + n * 2.5, "inside": line_p + n_in * 2.0})
	# runner pads: three before the front door, two toward each end door
	var x0r := room.position.x
	var x1r := room.end.x
	var z0r := room.position.y
	var pad_pts := [
		[Vector2(cx, z0r + 5.5), 0], [Vector2(cx - 2.6, z0r + 4.5), 0], [Vector2(cx + 2.6, z0r + 4.5), 0],
		[Vector2(x0r + 0.24 * w, z0r + 3.6), 1], [Vector2(x1r - 0.24 * w, z0r + 3.6), 2],
		[Vector2(x0r + 0.36 * w, z0r + 6.0), 1], [Vector2(x1r - 0.36 * w, z0r + 6.0), 2],
		[Vector2(cx, z0r + 3.0), 0],
	]
	var pads: Array = []
	for pp in pad_pts:
		var at: Vector2 = pp[0]
		var to: Vector2 = (doors[int(pp[1])] as Dictionary)["line_p"]
		var dir := (to - at).normalized()
		pads.append({"pos": at, "yaw": atan2(-dir.x, -dir.y), "door": int(pp[1])})
	var respawn: Array = []
	for dr in doors:
		respawn.append((dr["line_p"] as Vector2) + (dr["n_in"] as Vector2) * 2.6)
	var cart_lines: Array = []
	for dr in doors:
		var p2: Vector2 = (dr["pos"] as Vector2) + (dr["normal"] as Vector2) * 0.35
		var tg: Vector2 = dr["tangent"]
		cart_lines.append([p2 - tg * (hw + 0.4), p2 + tg * (hw + 0.4)])
	return {"id": String(d["id"]), "room": room, "boxes": boxes, "foot": foot, "doors": doors, "pads": pads,
		"respawn": respawn, "cart_lines": cart_lines, "footprint": Rect2(xw, zf, size.x, size.y),
		"block_z": bz, "ceil": CEIL, "h": h}


static func in_yards(p: Vector2) -> bool:
	return YARDS.has_point(p)


## Which district rect (if any) a point lies in.
static func district_of(p: Vector2) -> String:
	for k in DISTRICTS:
		if (DISTRICTS[k] as Rect2).has_point(p):
			return k
	return ""


static func in_any_district(r: Rect2) -> bool:
	for k in DISTRICTS:
		if (DISTRICTS[k] as Rect2).intersects(r):
			return true
	return false
