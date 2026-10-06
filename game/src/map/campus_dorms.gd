class_name CampusDorms
extends RefCounted
## The start dorms (the reference campus's two men's halls): runners spawn in
## tonight's home dorm and finish by running back in through one of its
## doors.  The host picks the dorm per round and publishes it; nothing here
## is derived independently by a client.
##
## Defined by the gameplay layer (game/data/campus/gameplay.json, items of
## kind "start_dorm"): the building it belongs to, the open interior at
## ground level (a commons `room` polygon plus short door `corridors`, all
## inside the traced footprint), the ceiling height, and the doors at the
## building's real entrances.  Everything a dorm is made of is computed here
## from that, so the colliders (CampusBuilder), the navigation grids, the
## look (DormArt), the spawn and respawn pads, the finish thresholds, the
## bots' door points, the maps and the tests can't drift apart.
##
##      outer wall face ─┬── door (p, outward normal n) ──┬─
##                       │  corridor (DOOR_W wide)         │
##      inner face ── threshold line (line_p = p - n*wall_t)
##                       │  commons room (open, ceiling)   │
##
## The rest of the footprint is solid; above `ceil` the whole building is
## solid.  Door openings are open, lit and identical on every client.

## Geometry version: part of every round's configuration.  Bump it with ANY
## change to a dorm's interior, doors, pads or thresholds (a client with
## other geometry is refused rather than simulating a different building).
const VERSION := 2

const WALL_T := 0.5      # default outer wall thickness at a door
const DOOR_W := 3.2      # clear opening
const DOOR_H := 3.0      # opening height (lintel above)
const CEIL := 4.6        # default commons ceiling
## Threshold: the line across the door at the wall's inner face.  A runner's
## centre must cross it inward within this half-width at a feet height
## inside FINISH_Y.
const THRESH_HALF_W := 1.5
const FINISH_Y := Vector2(-0.5, 1.6)
## A crossing longer than this in one tick is a teleport, never a finish.
const MAX_STEP_M := 3.0
const PAD_COUNT := 8

static var _defs: Array = []
static var _geo: Dictionary = {}


static func _load() -> void:
	if not _defs.is_empty():
		return
	for it in CampusData.shared().items("gameplay"):
		if String(it.get("kind", "")) == "start_dorm":
			_defs.append(it)
	# the default dorm first
	_defs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return bool(a.get("default", false)) and not bool(b.get("default", false)))


## Drops cached definitions and geometry (tests that swap data).
static func reset() -> void:
	_defs.clear()
	_geo.clear()


static func ids() -> Array[String]:
	_load()
	var out: Array[String] = []
	for d in _defs:
		out.append(String(d["dorm"]))
	return out


static func has_dorm(id: String) -> bool:
	return ids().has(id)


static func def(id: String) -> Dictionary:
	_load()
	for d in _defs:
		if String(d["dorm"]) == id:
			var out := (d as Dictionary).duplicate()
			out["id"] = id
			return out
	return {}


static func display_name(id: String) -> String:
	return String(def(id).get("name", "the dorm"))


static func default_id() -> String:
	_load()
	return String(_defs[0]["dorm"]) if not _defs.is_empty() else ""


## Tonight's home dorm: the default dorm when there is no previous round,
## otherwise never the same as last round's when another is available.
## Every client derives nothing itself: the host publishes the choice.
static func pick(seed_v: int, previous: String) -> String:
	var all := ids()
	if all.is_empty():
		return ""
	if previous == "" or not all.has(previous):
		return all[0]
	var h := posmod(int(hash([seed_v, "home-dorm"])), all.size())
	var choice := all[h]
	if all.size() > 1 and choice == previous:
		choice = all[(h + 1 + posmod(seed_v >> 3, all.size() - 1)) % all.size()]
	return choice


# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------
## Everything about one dorm's shape (cached):
##   room       PackedVector2Array: the commons interior (XZ)
##   interior   [PackedVector2Array]: room + door corridors (open at ground level)
##   footprint  PackedVector2Array of the whole building
##   solid      [PackedVector2Array]: footprint minus the interior (walls)
##   boxes      [[center Vector3, size Vector3, kind, yaw]] extra colliders (lintels, furniture)
##   foot       [PackedVector2Array]: what blocks walking at ground level (nav)
##   doors      [{id, name, dorm, pos, normal, line_p, n_in, tangent, half_w, approach, inside}]
##   pads       [{pos, yaw, door}] runner spawn pads inside, facing an exit
##   respawn    [Vector2] pre-first-stamp return pads, one inside each door
##   cart_lines [[a, b]] cart-only blockers across every door opening
##   ceil, h    ceiling of the commons, building height
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
	var data := CampusData.shared()
	var bld := data.item(String(d.get("building", "")))
	var footprint: PackedVector2Array = CampusData.ccw(bld.get("footprint", PackedVector2Array()))
	var h := float(d.get("h", bld.get("h", 10.0)))
	var ceil_y := float(d.get("ceil", CEIL))
	var room: PackedVector2Array = CampusData.ccw(d.get("room", PackedVector2Array()))
	var interior: Array[PackedVector2Array] = [room]
	var doors: Array = []
	var boxes: Array = []
	var specs: Array = d.get("doors", [])
	for i in specs.size():
		var sp: Dictionary = specs[i]
		var p := CampusLayout._v2(sp.get("p", [0, 0]))
		var n := CampusLayout._v2(sp.get("normal", [0, -1])).normalized()
		var t := float(sp.get("wall_t", WALL_T))
		var depth := float(sp.get("depth", t + 1.0))   # corridor length inside the wall
		var w := float(sp.get("w", DOOR_W))
		var n_in := -n
		var tg := Vector2(-n_in.y, n_in.x)
		var line_p := p + n_in * t
		# the opening: from just outside the outer face to `depth` inside it
		var o0 := p + n * 0.4
		var o1 := p + n_in * depth
		var hw := w * 0.5
		var corridor := CampusData.ccw(PackedVector2Array([o0 - tg * hw, o0 + tg * hw, o1 + tg * hw, o1 - tg * hw]))
		interior.append(corridor)
		doors.append({"id": String(sp.get("id", "door%d" % i)), "name": String(sp.get("name", "Door")), "dorm": String(d["id"]),
			"pos": p, "normal": n, "line_p": line_p, "n_in": n_in, "tangent": tg, "half_w": THRESH_HALF_W,
			"approach": p + n * 2.5, "inside": line_p + n_in * 2.0, "w": w, "wall_t": t})
		# lintel over the opening, between the door height and the ceiling
		var lc := p + n_in * (t * 0.5)
		boxes.append([Vector3(lc.x, (DOOR_H + ceil_y) * 0.5, lc.y), Vector3(w + 0.2, ceil_y - DOOR_H, t + 0.02), "lintel", atan2(n.x, n.y)])
	for cpoly in d.get("corridors", []):
		var cp := CampusData.ccw(CampusData.to_poly(cpoly) if cpoly is Array else cpoly)
		if cp.size() >= 3:
			interior.append(cp)
	var solid := CampusData.subtract(footprint, interior) if footprint.size() >= 3 else ([] as Array[PackedVector2Array])
	var foot: Array = []
	for s in solid:
		foot.append(s)
	for f in d.get("furniture", []):
		var fp := CampusLayout._v2(f.get("p", [0, 0]))
		var fs: Array = f.get("size", [1, 0.8, 1])
		var fy := deg_to_rad(float(f.get("yaw", 0.0)))
		boxes.append([Vector3(fp.x, float(fs[1]) * 0.5, fp.y), Vector3(float(fs[0]), float(fs[1]), float(fs[2])), String(f.get("kind", "furniture")), fy])
		foot.append(_obox(fp, Vector2(float(fs[0]), float(fs[2])), fy))
	var pads := _pads(room, doors, d.get("pads", []))
	var respawn: Array = []
	for dr in doors:
		respawn.append((dr["line_p"] as Vector2) + (dr["n_in"] as Vector2) * 2.6)
	var cart_lines: Array = []
	for dr in doors:
		var p2: Vector2 = (dr["pos"] as Vector2) + (dr["normal"] as Vector2) * 0.35
		var tg2: Vector2 = dr["tangent"]
		var hw2 := float(dr["w"]) * 0.5
		cart_lines.append([p2 - tg2 * (hw2 + 0.4), p2 + tg2 * (hw2 + 0.4)])
	return {"id": String(d["id"]), "building": String(d.get("building", "")), "room": room, "interior": interior,
		"footprint": footprint, "solid": solid, "boxes": boxes, "foot": foot, "doors": doors, "pads": pads,
		"respawn": respawn, "cart_lines": cart_lines, "ceil": ceil_y, "h": h,
		"room_rect": CampusData.bounds(room)}


## An oriented rectangle as a polygon (centre, size along its own x/z, yaw).
static func _obox(c: Vector2, size: Vector2, yaw: float) -> PackedVector2Array:
	var ax := Vector2(cos(yaw), -sin(yaw)) * size.x * 0.5
	var az := Vector2(sin(yaw), cos(yaw)) * size.y * 0.5
	return PackedVector2Array([c - ax - az, c + ax - az, c + ax + az, c - ax + az])


## Runner pads: explicit ones from the data ([x, z, door]), else up to
## PAD_COUNT points on a 1.7 m grid inside the room (1.3 m from its walls),
## nearest the room's centre first, each facing its nearest door.
static func _pads(room: PackedVector2Array, doors: Array, explicit: Array) -> Array:
	var out: Array = []
	var pts: Array = []
	if not explicit.is_empty():
		for e in explicit:
			pts.append([Vector2(float(e[0]), float(e[1])), int(e[2]) if (e as Array).size() > 2 else -1])
	elif room.size() >= 3:
		var inner := CampusData.offset(room, -1.3)
		var r := CampusData.bounds(inner if inner.size() >= 3 else room)
		var c := CampusData.centroid(room)
		var cand: Array = []
		var step := 1.7
		var x := r.position.x + 0.5
		while x <= r.end.x:
			var z := r.position.y + 0.5
			while z <= r.end.y:
				var p := Vector2(x, z)
				if inner.size() >= 3 and Geometry2D.is_point_in_polygon(p, inner):
					cand.append(p)
				z += step
			x += step
		cand.sort_custom(func(a: Vector2, b: Vector2) -> bool:
			var da := a.distance_squared_to(c)
			var db := b.distance_squared_to(c)
			return da < db if absf(da - db) > 1e-6 else (a.x < b.x if a.x != b.x else a.y < b.y))
		for p in cand.slice(0, PAD_COUNT):
			pts.append([p, -1])
	for pp in pts:
		var at: Vector2 = pp[0]
		var di := int(pp[1])
		if di < 0 or di >= doors.size():
			var best := INF
			for i in doors.size():
				var dd := at.distance_to(doors[i]["line_p"])
				if dd < best:
					best = dd
					di = i
		var to: Vector2 = (doors[di]["line_p"] as Vector2) if di >= 0 else at + Vector2(0, -1)
		var dir := (to - at).normalized()
		out.append({"pos": at, "yaw": atan2(-dir.x, -dir.y), "door": di})
	return out


## Is a point inside this dorm's open interior (feet below the ceiling)?
static func in_room(id: String, p: Vector3, margin: float = 0.0) -> bool:
	var g := geometry(id)
	if g.is_empty():
		return false
	if p.y >= float(g["ceil"]) - 1.0 or p.y <= -1.0:
		return false
	var q := Vector2(p.x, p.z)
	var room: PackedVector2Array = g["room"]
	if not Geometry2D.is_point_in_polygon(q, room):
		return false
	return margin <= 0.0 or CampusData.dist_to_edge(q, room) >= margin


## The outside->inside threshold test for one door (pure geometry; the sim
## adds the collision check).  a = position at the start of the tick, b = at
## its end.  True when the centre crossed the line at the inner face of the
## wall inward, within the opening, at a plausible feet height.
static func crosses(door: Dictionary, a: Vector3, b: Vector3) -> bool:
	var lp: Vector2 = door["line_p"]
	var n: Vector2 = door["n_in"]
	var tg: Vector2 = door["tangent"]
	var a2 := Vector2(a.x, a.z) - lp
	var b2 := Vector2(b.x, b.z) - lp
	var da := a2.dot(n)
	var db := b2.dot(n)
	if not (da < 0.0 and db >= 0.0):
		return false
	if a2.distance_to(b2) > MAX_STEP_M:
		return false
	var t := da / (da - db)
	var at := a2.lerp(b2, t)
	if absf(at.dot(tg)) > float(door["half_w"]):
		return false
	var y := lerpf(a.y, b.y, t)
	return y >= FINISH_Y.x and y <= FINISH_Y.y


## A short fingerprint of a dorm's gameplay geometry (published in the round
## configuration next to VERSION; a client whose dorm differs refuses it).
static func geometry_hash(id: String) -> String:
	var g := geometry(id)
	if g.is_empty():
		return ""
	var parts := PackedStringArray([str(VERSION), id, "%.3f" % float(g["ceil"])])
	for poly in g["interior"]:
		var s := PackedStringArray()
		for p in poly:
			s.append(_v2s(p))
		parts.append(";".join(s))
	for bx in g["boxes"]:
		parts.append("%s|%s|%s|%.3f" % [_v3s(bx[0]), _v3s(bx[1]), bx[2], float(bx[3])])
	for dr in g["doors"]:
		parts.append("%s|%s|%s|%.3f" % [dr["id"], _v2s(dr["line_p"]), _v2s(dr["n_in"]), float(dr["half_w"])])
	for pd in g["pads"]:
		parts.append("%s|%.3f" % [_v2s(pd["pos"]), float(pd["yaw"])])
	for rp in g["respawn"]:
		parts.append(_v2s(rp))
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update("\n".join(parts).to_utf8_buffer())
	return ctx.finish().hex_encode().substr(0, 16)


static func _v3s(v: Vector3) -> String:
	return "%.3f,%.3f,%.3f" % [v.x, v.y, v.z]


static func _v2s(v: Vector2) -> String:
	return "%.3f,%.3f" % [v.x, v.y]
