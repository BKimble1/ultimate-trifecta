class_name HideBushes
extends RefCounted
## (2.3) Bushes a runner can hide in.  They are worked out from the map's own
## gameplay layout, the same on every device: beside the footpaths, every
## SPACING metres along them, on open lawn (clear of buildings, water,
## walls, hedges, roads, paths, trees, lamps, doors, the shed and each
## other).  They block nothing (no collider, no sight line): a runner inside
## is out of view, and the Night Watch can still tag them by lunging at the
## bush.  At most MAX on a map, so the campus never turns into a hedge maze.

const RADIUS := 1.15       # the bush's crown (m)
const ENTER_M := 1.8       # how close a runner must stand to hide
const SPACING := 26.0      # metres between candidates along a path
const SIDE := 3.6          # metres off the path's edge
const MIN_GAP := 18.0      # metres between two bushes
const MAX := 16

static var _cache: Dictionary = {}


static func spots(layout: CampusLayout) -> Array:
	if layout == null:
		return []
	var key := "%s:%d:%d" % [layout.map_id, layout.paths.size(), layout.gadget_spots.size()]
	if _cache.has(key):
		return _cache[key]
	var out: Array = []
	var flip := false
	for pth in layout.paths:
		var pts: PackedVector2Array = pth["pts"]
		var half := float(pth["w"]) * 0.5
		var carry := SPACING * 0.5
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var seg := b.distance_to(a)
			if seg < 0.5:
				continue
			var dir := (b - a) / seg
			var nrm := Vector2(-dir.y, dir.x)
			var d := carry
			while d < seg:
				flip = not flip
				var p := a + dir * d + nrm * (half + SIDE) * (1.0 if flip else -1.0)
				if _ok(layout, p, out):
					out.append(p)
				d += SPACING
			carry = d - seg
	# spread over the whole campus: keep the MAX farthest apart (farthest-
	# point picking from the bush nearest the middle; deterministic)
	if out.size() > MAX:
		var mid := layout.bounds.get_center()
		var first := 0
		for i in out.size():
			if (out[i] as Vector2).distance_to(mid) < (out[first] as Vector2).distance_to(mid):
				first = i
		var pick: Array = [out[first]]
		while pick.size() < MAX:
			var best := -1
			var bd := -1.0
			for i in out.size():
				var dmin := INF
				for q in pick:
					dmin = minf(dmin, (out[i] as Vector2).distance_to(q))
				if dmin > bd:
					bd = dmin
					best = i
			pick.append(out[best])
		out = pick
	_cache[key] = out
	return out


static func _ok(layout: CampusLayout, p: Vector2, taken: Array) -> bool:
	for q in taken:
		if (q as Vector2).distance_to(p) < MIN_GAP:
			return false
	if not layout._open_ground(p, RADIUS + 0.6):
		return false
	if layout.is_on_road(p, RADIUS + 1.0) or layout.is_on_path(p, RADIUS + 0.3):
		return false
	if layout.on_stair(p, RADIUS + 1.0):
		return false
	for tr in layout.trees:
		if (tr["pos"] as Vector2).distance_to(p) < RADIUS + float(tr.get("r", 0.6)) + 0.8:
			return false
	for l in layout.lamps:
		if l.distance_to(p) < RADIUS + 1.2:
			return false
	for s in layout.gadget_spots:
		if s.distance_to(p) < 5.0:
			return false
	for s in layout.coin_spots:
		if s.distance_to(p) < 3.0:
			return false
	for dd in layout.dorm_doors:
		if (dd["pos"] as Vector2).distance_to(p) < 9.0:
			return false
	for s in layout.patrol_spawns:
		if s.distance_to(p) < 14.0:
			return false
	for s in layout.runner_spawns:
		if s.distance_to(p) < 8.0:
			return false
	# never on a slope or step a runner couldn't stand still on
	var h := [layout.terrain_y(p), layout.terrain_y(p + Vector2(1, 0)), layout.terrain_y(p + Vector2(0, 1)),
		layout.terrain_y(p - Vector2(1, 0)), layout.terrain_y(p - Vector2(0, 1))]
	return (h.max() as float) - (h.min() as float) < 0.5


## The bush a runner at `p` could hide in (index), or -1.
static func near(layout: CampusLayout, p: Vector2, reach: float = ENTER_M) -> int:
	var best := -1
	var bd := reach + RADIUS
	var sp := spots(layout)
	for i in sp.size():
		var d := (sp[i] as Vector2).distance_to(p)
		if d < bd:
			bd = d
			best = i
	return best
