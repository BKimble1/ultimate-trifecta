class_name CampusDressing
extends RefCounted
## Decorative dressing for Moonbrook College (V5): understory shrubs,
## foundation planting, flower clumps, sparse grass tufts beside paths,
## reeds and lilies at the banks, small rocks, and the forest beyond the
## boundary hedges.
##
## Visual only.  Nothing here has a collider or touches the nav grids, and
## placement keeps every piece out of the running corridors:
##   * nothing on a path, road or plaza, at a water exit or jump point, a
##     respawn pad, a spawn, a gadget spot, a dorm door, a gate (bollard
##     line) or a lamp/bench;
##   * anything taller than a tuft ("mid": shrubs, reeds, round rocks) only
##     hugging something that already blocks movement - within 0.55 m of a
##     building, hedge, wall, fence, tree trunk or boulder collider, or on a
##     water bank - so a runner never meets a bush in open ground;
##   * "low" pieces (grass, flowers, flat stones, lilies; <= 0.45 m) may sit
##     on open lawn, clustered, never in the corridors above.
## test_campus_art re-checks all of this against the real nav grid and the
## bots' routes.
##
## The list is generated offline (tools/campus/bake_dressing.gd) into
## game/assets/campus/campus_dressing.res, so the loading screen only reads
## it; the test regenerates it and fails if the baked copy is stale.

const BAKED := "res://assets/campus/campus_dressing.res"
## floats per item: x, y, z, yaw, scale, tint r g b, custom r g b
const STRIDE := 11
const LOW := ["grass", "flowers", "lilies", "rock_flat"]
const MID := ["shrub_round", "shrub_tall", "shrub_bloom", "reeds", "rock_round", "rock_layer"]
const FOREST := "forest"
## footprint radius at scale 1 (m), for clearances and the safety test
const RADIUS := {"grass": 0.2, "flowers": 0.3, "lilies": 0.8, "rock_flat": 0.5, "shrub_round": 0.55, "shrub_tall": 0.5,
	"shrub_bloom": 0.6, "reeds": 0.4, "rock_round": 0.5, "rock_layer": 0.5, "forest": 3.0}

var L: CampusLayout
var items: Dictionary = {}   # kind -> PackedFloat32Array (STRIDE per item)
var _rng := RandomNumberGenerator.new()
var _occupied: Array = []    # [Vector2, r] of mid items placed so far
var verbose := false


func _init(layout: CampusLayout) -> void:
	L = layout


## Loads the baked list (the game) - {} if missing.
static func load_baked() -> Dictionary:
	if not ResourceLoader.exists(BAKED):
		return {}
	var r := load(BAKED)
	if r == null or not r.has_meta("items"):
		return {}
	return r.get_meta("items")


static func count(d: Dictionary) -> int:
	var n := 0
	for k in d:
		n += (d[k] as PackedFloat32Array).size() / STRIDE
	return n


## Full generation (offline bake and the test): deterministic.
func generate() -> Dictionary:
	items.clear()
	_occupied.clear()
	_occ_hash.clear()
	var t0 := Time.get_ticks_msec()
	_build_masks()
	_rng.seed = 5150
	var passes := [_understory, _foundations, _banks, _lily_basin, _quarry, _flowers_and_grass, _forest_beyond]
	var times := []
	for f: Callable in passes:
		f.call()
		times.append(Time.get_ticks_msec() - t0)
	if verbose:
		print("dressing passes (cumulative ms, masks first): ", times)
	return items


func _add(kind: String, p: Vector2, y: float, yaw: float, s: float, tint: Color = Color(1, 1, 1), custom: Color = Color(1, 1, 1)) -> void:
	if not items.has(kind):
		items[kind] = PackedFloat32Array()
	var a: PackedFloat32Array = items[kind]
	a.append_array(PackedFloat32Array([p.x, y, p.y, yaw, s, tint.r, tint.g, tint.b, custom.r, custom.g, custom.b]))
	items[kind] = a
	if kind in MID:
		var e := [p, float(RADIUS[kind]) * s]
		_occupied.append(e)
		var key := Vector2i(int(floor(p.x / 4.0)), int(floor(p.y / 4.0)))
		if not _occ_hash.has(key):
			_occ_hash[key] = []
		(_occ_hash[key] as Array).append(e)


# ---------------------------------------------------------------------------
# clearances
# ---------------------------------------------------------------------------
## Placement uses two 0.5 m rasters to reject most candidates cheaply (the
## exact clear_of_gameplay() check then confirms the survivors):
## _block = every corridor and keep-clear zone (water and the obstacles a
## piece may hug are left to the exact check), _near = within 2.6 m of a
## path edge (tufts follow the paths).
const MC := 0.5
var _block := PackedByteArray()
var _near := PackedByteArray()
var _mw := 0
var _md := 0
var _occ_hash: Dictionary = {}   # Vector2i(4 m cell) -> [[p, r], ...]


func _build_masks() -> void:
	var b := CampusLayout.BOUNDS
	_mw = int(b.size.x / MC) + 1
	_md = int(b.size.y / MC) + 1
	_block.resize(_mw * _md)
	_block.fill(0)
	_near.resize(_mw * _md)
	_near.fill(0)
	for r in L.roads:
		var pts: PackedVector2Array = r["pts"]
		for i in pts.size() - 1:
			_mask_seg(_block, pts[i], pts[i + 1], float(r["w"]) * 0.5 + 0.8)
	for pth in L.paths:
		var pts2: PackedVector2Array = pth["pts"]
		for i in pts2.size() - 1:
			_mask_seg(_block, pts2[i], pts2[i + 1], float(pth["w"]) * 0.5 + 0.3)
			_mask_seg(_near, pts2[i], pts2[i + 1], float(pth["w"]) * 0.5 + 2.6)
	for pl in L.plazas:
		if pl["shape"] == "circle":
			_mask_disc(_block, pl["center"], float(pl["radius"]) + 0.2)
		else:
			var hs: Vector2 = pl["size"] * 0.5 + Vector2(0.2, 0.2)
			_mask_rect(_block, Rect2(pl["center"] - hs, hs * 2.0))
	for w in L.waters:
		for e in w["exits"]:
			_mask_disc(_block, Vector2(e.x, e.z), 3.2)
		for j in w["jump_points"]:
			_mask_disc(_block, j, 2.6)
		for pad in w["pads"]:
			_mask_disc(_block, pad, 1.8)
	for sp in L.runner_spawns + L.patrol_spawns + L.gadget_spots + L.dorm_pads:
		_mask_disc(_block, sp, 1.8)
	for cs in L.cart_spawns:
		_mask_disc(_block, cs["pos"], 4.0)
	for d in L.dorm_doors:
		_mask_disc(_block, d["pos"], 4.5)
	for s2 in L.cart_blockers:
		_mask_seg(_block, s2["a"], s2["b"], 1.6)
	for lp in L.lamps:
		_mask_disc(_block, lp, 0.5)
	for bn in L.benches:
		_mask_disc(_block, bn["pos"], 1.4)
	for pr in L.props:
		_mask_disc(_block, pr["pos"], 1.6)


func _mask_cells(r: Rect2) -> Array:
	var b := CampusLayout.BOUNDS
	return [maxi(0, int(floor((r.position.x - b.position.x) / MC))), mini(_mw - 1, int(ceil((r.end.x - b.position.x) / MC))),
		maxi(0, int(floor((r.position.y - b.position.y) / MC))), mini(_md - 1, int(ceil((r.end.y - b.position.y) / MC)))]


func _mask_seg(m: PackedByteArray, a: Vector2, bb: Vector2, rad: float) -> void:
	var b := CampusLayout.BOUNDS
	var c := _mask_cells(Rect2(a, Vector2.ZERO).expand(bb).grow(rad))
	for j in range(c[2], c[3] + 1):
		for i in range(c[0], c[1] + 1):
			var p := Vector2(b.position.x + i * MC, b.position.y + j * MC)
			if CampusLayout._dist_to_segment(p, a, bb) <= rad:
				m[j * _mw + i] = 1


func _mask_disc(m: PackedByteArray, c0: Vector2, rad: float) -> void:
	var b := CampusLayout.BOUNDS
	var c := _mask_cells(Rect2(c0, Vector2.ZERO).grow(rad))
	for j in range(c[2], c[3] + 1):
		for i in range(c[0], c[1] + 1):
			if Vector2(b.position.x + i * MC, b.position.y + j * MC).distance_to(c0) <= rad:
				m[j * _mw + i] = 1


func _mask_rect(m: PackedByteArray, r: Rect2) -> void:
	var c := _mask_cells(r)
	for j in range(c[2], c[3] + 1):
		for i in range(c[0], c[1] + 1):
			m[j * _mw + i] = 1


func _mask_at(m: PackedByteArray, p: Vector2) -> int:
	var b := CampusLayout.BOUNDS
	var i := int(round((p.x - b.position.x) / MC))
	var j := int(round((p.y - b.position.y) / MC))
	if i < 0 or j < 0 or i >= _mw or j >= _md:
		return 1
	return m[j * _mw + i]


## Quick raster test: the centre and eight points around the footprint.
func _mask_free(p: Vector2, r: float) -> bool:
	if not CampusLayout.BOUNDS.grow(-3.0).has_point(p):
		return false
	if _mask_at(_block, p) != 0:
		return false
	for k in 8:
		var a := TAU * float(k) / 8.0
		if _mask_at(_block, p + Vector2(cos(a), sin(a)) * r) != 0:
			return false
	return true


func _near_path(p: Vector2) -> bool:
	return _mask_at(_near, p) != 0

## True when a piece of footprint radius r at p keeps out of every gameplay
## corridor (shared by placement and test_campus_art).
static func clear_of_gameplay(L: CampusLayout, p: Vector2, r: float, in_water_ok: bool = false) -> bool:
	if not CampusLayout.BOUNDS.grow(-3.0).has_point(p):
		return false
	if L.is_on_road(p, r + 0.8) or L.is_on_path(p, r + 0.3):
		return false
	for pl in L.plazas:
		if pl["shape"] == "circle":
			if p.distance_to(pl["center"]) < float(pl["radius"]) + r + 0.2:
				return false
		else:
			var hs: Vector2 = pl["size"] * 0.5 + Vector2(r + 0.2, r + 0.2)
			var c: Vector2 = pl["center"]
			if absf(p.x - c.x) < hs.x and absf(p.y - c.y) < hs.y:
				return false
	for w in L.waters:
		if not in_water_ok and CampusLayout.in_water_shape(w, p, r + 0.15):
			return false
		for e in w["exits"]:
			if p.distance_to(Vector2(e.x, e.z)) < r + 3.2:
				return false
		for j in w["jump_points"]:
			if p.distance_to(j) < r + 2.6:
				return false
		for pad in w["pads"]:
			if p.distance_to(pad) < r + 1.8:
				return false
	for sp in L.runner_spawns + L.patrol_spawns + L.gadget_spots + L.dorm_pads:
		if p.distance_to(sp) < r + 1.8:
			return false
	for cs in L.cart_spawns:
		if p.distance_to(cs["pos"]) < r + 4.0:
			return false
	for d in L.dorm_doors:
		if p.distance_to(d["pos"]) < r + 4.5:
			return false
	for s in L.cart_blockers:
		# bollard lines mark the gates and openings: keep them clear
		if CampusLayout._dist_to_segment(p, s["a"], s["b"]) < r + 1.6:
			return false
	for lp in L.lamps:
		if p.distance_to(lp) < r + 0.5:
			return false
	for bn in L.benches:
		if p.distance_to(bn["pos"]) < r + 1.4:
			return false
	for pr in L.props:
		if p.distance_to(pr["pos"]) < r + 1.6:
			return false
	for t in L.trees:
		if p.distance_to(t["pos"]) < 0.5 + r * 0.5:
			return false
	for bd in L.buildings:
		var hs2: Vector2 = bd["size"] * 0.5
		var bp: Vector2 = bd["pos"]
		if absf(p.x - bp.x) < hs2.x + 0.05 and absf(p.y - bp.y) < hs2.y + 0.05:
			return false
	for lst in [L.walls, L.hedges, L.fences]:
		for s in lst:
			if CampusLayout._dist_to_segment(p, s["a"], s["b"]) < float(s.get("t", 0.25)) * 0.5 + r * 0.4:
				return false
	return true


## Mid pieces hug an obstacle that already blocks movement: the centre lies
## within HUG_M of a building, hedge, wall, fence, trunk or boulder
## collider (inside the band the bots' nav grid already treats as solid or
## costly), so a shrub never stands alone in open ground.
const HUG_M := 0.55


static func hugging_obstacle(L: CampusLayout, p: Vector2) -> bool:
	for bd in L.buildings:
		var hs: Vector2 = bd["size"] * 0.5
		var bp: Vector2 = bd["pos"]
		var dx := maxf(absf(p.x - bp.x) - hs.x, 0.0)
		var dz := maxf(absf(p.y - bp.y) - hs.y, 0.0)
		if Vector2(dx, dz).length() <= HUG_M:
			return true
	for lst in [L.walls, L.hedges, L.fences]:
		for s in lst:
			if CampusLayout._dist_to_segment(p, s["a"], s["b"]) <= float(s.get("t", 0.25)) * 0.5 + HUG_M:
				return true
	for t in L.trees:
		if p.distance_to(t["pos"]) <= 0.42 + HUG_M:
			return true
	for r in L.rocks:
		var rp: Vector3 = r["pos"]
		var rs: Vector3 = r["size"]
		if p.distance_to(Vector2(rp.x, rp.z)) <= maxf(rs.x, rs.z) * 0.5 + HUG_M:
			return true
	return false


func _sheltered(p: Vector2, _r: float) -> bool:
	return hugging_obstacle(L, p)


func _free_of_mid(p: Vector2, r: float) -> bool:
	var k0 := Vector2i(int(floor(p.x / 4.0)), int(floor(p.y / 4.0)))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			for o in _occ_hash.get(k0 + Vector2i(dx, dy), []):
				if p.distance_to(o[0]) < r + float(o[1]) * 0.8:
					return false
	return true


func _try_mid(kind: String, p: Vector2, s: float, tint: Color = Color(1, 1, 1), custom: Color = Color(1, 1, 1)) -> bool:
	var r: float = float(RADIUS[kind]) * s
	if not _mask_free(p, r) or not _sheltered(p, r) or not _free_of_mid(p, r):
		return false
	if not clear_of_gameplay(L, p, r):
		return false
	_add(kind, p, 0.0, _rng.randf() * TAU, s, tint, custom)
	return true


func _try_low(kind: String, p: Vector2, s: float, tint: Color = Color(1, 1, 1), custom: Color = Color(1, 1, 1), y: float = 0.0) -> bool:
	var r: float = float(RADIUS[kind]) * s
	if not _mask_free(p, r) or not _free_of_mid(p, r * 0.5):
		return false
	for w in L.waters:
		if CampusLayout.in_water_shape(w, p, r + 0.15):
			return false
	if not clear_of_gameplay(L, p, r):
		return false
	_add(kind, p, y, _rng.randf() * TAU, s, tint, custom)
	return true


static func _noise(p: Vector2, f: float, salt: int) -> float:
	# cheap smooth value noise for clustering (deterministic)
	var q := p * f
	var i := q.floor()
	var t := q - i
	t = t * t * (Vector2(3, 3) - 2.0 * t)
	var h := func(x: float, y: float) -> float:
		return float(posmod(hash(Vector3i(int(x), int(y), salt)), 1000)) / 1000.0
	var a: float = h.call(i.x, i.y)
	var b: float = h.call(i.x + 1, i.y)
	var c: float = h.call(i.x, i.y + 1)
	var d: float = h.call(i.x + 1, i.y + 1)
	return lerpf(lerpf(a, b, t.x), lerpf(c, d, t.x), t.y)


# ---------------------------------------------------------------------------
# placement passes
# ---------------------------------------------------------------------------
## Shrubs at tree bases inside the groves (in the trunk's solid ring).
func _understory() -> void:
	for t in L.trees:
		var tp: Vector2 = t["pos"]
		if _mask_at(_near, tp) != 0:
			continue
		var grove := _noise(tp, 0.06, 3)
		if _rng.randf() > 0.25 + 0.5 * grove:
			continue
		var n := 1 + int(_rng.randf() < 0.4)
		for k in n:
			var a := _rng.randf() * TAU
			var d := _rng.randf_range(0.55, 0.92)
			var kind := "shrub_round" if _rng.randf() < 0.6 else "shrub_tall"
			if tp.y < -60.0 and tp.x > 60.0:
				kind = "shrub_bloom"
			var s := _rng.randf_range(0.6, 0.85)
			_try_mid(kind, tp + Vector2(cos(a), sin(a)) * d, s, _leaf_tint())


func _leaf_tint() -> Color:
	var v := _rng.randf_range(0.85, 1.12)
	var w := _rng.randf_range(-0.05, 0.05)
	return Color(v * (1.0 + w), v, v * (1.0 - w))


const BLOOMS := [Color(1.0, 0.42, 0.62), Color(1.0, 0.80, 0.28), Color(0.92, 0.94, 1.0), Color(0.66, 0.46, 1.0), Color(1.0, 0.52, 0.30)]


## Foundation planting: shrubs tucked against building walls (the solid
## band), never near an entrance; blooming shrubs at the dorm.
func _foundations() -> void:
	for bd in L.buildings:
		var id := String(bd["id"])
		if id in ["tower", "chapel_w", "chapel_e", "shed", "greenhouse", "observatory"]:
			continue
		var pos: Vector2 = bd["pos"]
		var hs: Vector2 = bd["size"] * 0.5
		var sides := [[Vector2(-hs.x, -hs.y), Vector2(hs.x, -hs.y), Vector2(0, -1)], [Vector2(hs.x, hs.y), Vector2(-hs.x, hs.y), Vector2(0, 1)],
			[Vector2(-hs.x, hs.y), Vector2(-hs.x, -hs.y), Vector2(-1, 0)], [Vector2(hs.x, -hs.y), Vector2(hs.x, hs.y), Vector2(1, 0)]]
		for sd in sides:
			var a: Vector2 = pos + sd[0]
			var b: Vector2 = pos + sd[1]
			var nrm: Vector2 = sd[2]
			var length := a.distance_to(b)
			var x := 1.6
			while x < length - 1.6:
				var p := a.lerp(b, x / length) + nrm * 0.42
				var dorm := id == "dorm"
				var kind := "shrub_bloom" if (dorm or _rng.randf() < 0.25) else ("shrub_round" if _rng.randf() < 0.7 else "shrub_tall")
				var s := _rng.randf_range(0.6, 0.78)
				var ok := _try_mid(kind, p, s, _leaf_tint(), BLOOMS[_rng.randi() % BLOOMS.size()])
				x += _rng.randf_range(2.2, 3.4) if ok else 1.0


## Reeds, lilies and flat stones at the natural banks (pond, quarry, inlet).
func _banks() -> void:
	for w in L.waters:
		var id := String(w["id"])
		if id not in ["pond", "quarry", "inlet"]:
			continue
		var c: Vector2 = w["center"]
		if id == "inlet":
			# reeds in the two shore corners away from the dock and exits
			for cp in [c + Vector2(-8.6, -2.0), c + Vector2(-8.4, 4.5), c + Vector2(8.6, 8.4), c + Vector2(4.0, 8.6)]:
				for k in 3:
					var q: Vector2 = cp + Vector2(_rng.randf_range(-0.9, 0.9), _rng.randf_range(-0.9, 0.9))
					_try_bank("reeds", w, q, _rng.randf_range(0.8, 1.1))
			continue
		var rx: float = float(w["rx"])
		var rz: float = float(w["rz"])
		var n := 64
		for j in n:
			var a := TAU * float(j) / float(n) + _rng.randf_range(-0.03, 0.03)
			var dir := Vector2(cos(a), sin(a))
			var bank := c + Vector2(dir.x * rx, dir.y * rz)
			var cluster := _noise(bank, 0.35, 11 + j / 16)
			if id == "pond" and cluster > 0.45:
				_try_bank("reeds", w, bank + dir * _rng.randf_range(-0.3, 0.35), _rng.randf_range(0.8, 1.15))
			elif cluster < 0.35:
				_try_bank("rock_flat", w, bank + dir * _rng.randf_range(0.2, 0.7), _rng.randf_range(0.45, 0.75))
		if id == "pond":
			# lily groups on the water, kept off the swim lines to the exits
			for k in 9:
				var a2 := _rng.randf() * TAU
				var rr := _rng.randf_range(0.35, 0.72)
				var q2 := c + Vector2(cos(a2) * rx * rr, sin(a2) * rz * rr)
				var ok := true
				for e in w["exits"]:
					if CampusLayout._dist_to_segment(q2, c, Vector2(e.x, e.z)) < 1.6:
						ok = false
				if ok:
					_add("lilies", q2, float(w["surface_y"]) + 0.03, _rng.randf() * TAU, _rng.randf_range(0.8, 1.2), Color(1, 1, 1), BLOOMS[0] if k % 3 else BLOOMS[2])


## A bank piece straddles the shoreline: clear of exits and jump points but
## allowed over the water's edge.
func _try_bank(kind: String, w: Dictionary, p: Vector2, s: float) -> bool:
	var r: float = float(RADIUS[kind]) * s
	if not _mask_free(p, r) or not clear_of_gameplay(L, p, r, true):
		return false
	if CampusLayout.in_water_shape(w, p, -0.9):
		return false   # not out in the water
	if not _free_of_mid(p, r):
		return false
	var y := 0.0
	if CampusLayout.in_water_shape(w, p, 0.0):
		y = float(w["surface_y"]) - 0.05
	_add(kind, p, y, _rng.randf() * TAU, s, _leaf_tint() if kind == "reeds" else Color(1, 1, 1))
	return true


## Lily Basin: lilies on the basin, blooms along the inner hedge feet.
func _lily_basin() -> void:
	var w := L.water_by_id("garden")
	var c: Vector2 = w["center"]
	var hs: Vector2 = w["size"] * 0.5
	for k in 6:
		var q := c + Vector2(_rng.randf_range(-hs.x + 1.2, hs.x - 1.2), _rng.randf_range(-hs.y + 1.0, hs.y - 1.0))
		_add("lilies", q, float(w["surface_y"]) + 0.03, _rng.randf() * TAU, _rng.randf_range(0.7, 1.0), Color(1, 1, 1), BLOOMS[k % 2])
	# flower borders inside the hedge ring (16 m square around the basin)
	for side in 4:
		for k in 22:
			var t := -15.0 + 30.0 * float(k) / 21.0
			var q2: Vector2
			match side:
				0: q2 = c + Vector2(t, -13.6)
				1: q2 = c + Vector2(t, 13.6)
				2: q2 = c + Vector2(-15.6, t * 0.86)
				_: q2 = c + Vector2(15.6, t * 0.86)
			q2 += Vector2(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.3, 0.3))
			_try_low("flowers", q2, _rng.randf_range(1.0, 1.4), Color(1, 1, 1), BLOOMS[(side + k / 4) % BLOOMS.size()])


## Quarry: scattered stones between the collider boulders.
func _quarry() -> void:
	var q := Vector2(-100, -90)
	for k in 60:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(15.0, 21.0)
		var p := q + Vector2(cos(a) * r, sin(a) * r * 0.82)
		if _rng.randf() < 0.5:
			_try_mid("rock_round", p, _rng.randf_range(0.6, 1.1))
		else:
			_try_low("rock_flat", p, _rng.randf_range(0.5, 0.9))


## Flower clumps and grass tufts: clusters in clearings, along path edges,
## at lamp feet and hedge feet; none in corridors.
func _flowers_and_grass() -> void:
	var b := CampusLayout.BOUNDS.grow(-4.0)
	# meadow clusters (noise-gated jittered grid)
	var step := 3.2
	var y := b.position.y
	while y < b.end.y:
		var x := b.position.x
		while x < b.end.x:
			var p := Vector2(x + _rng.randf_range(-1.4, 1.4), y + _rng.randf_range(-1.4, 1.4))
			var meadow := _noise(p, 0.045, 21)
			var near_path := _near_path(p)
			if near_path and _rng.randf() < 0.55:
				_try_low("grass", p, _rng.randf_range(0.9, 1.4), _grass_tint())
			elif meadow > 0.5 and _rng.randf() < 0.3:
				for k in 2:
					_try_low("grass", p + Vector2(_rng.randf_range(-0.8, 0.8), _rng.randf_range(-0.8, 0.8)), _rng.randf_range(0.8, 1.3), _grass_tint())
			x += step
		y += step
	# lamp feet: a few tufts, and on the formal lawns a little bed of blooms
	for lp in L.lamps:
		var col: Color = BLOOMS[posmod(int(lp.x * 3.0 + lp.y * 7.0), BLOOMS.size())]
		for k in 3:
			var a := _rng.randf() * TAU
			_try_low("grass", lp + Vector2(cos(a), sin(a)) * _rng.randf_range(0.7, 1.1), _rng.randf_range(0.8, 1.2), _grass_tint())
		if absf(lp.x) < 76.0 and lp.y > -60.0:
			for k in 4:
				var a2 := _rng.randf() * TAU
				_try_low("flowers", lp + Vector2(cos(a2), sin(a2)) * _rng.randf_range(0.65, 1.2), _rng.randf_range(1.0, 1.3), Color(1, 1, 1), col)
	# blooms in front of the foundation shrubs (one colour per building side)
	for o in _occupied.duplicate():
		var op: Vector2 = o[0]
		if _rng.randf() < 0.55 and _near_building(op):
			var col2: Color = BLOOMS[posmod(int(op.x * 0.2) + int(op.y * 0.2), BLOOMS.size())]
			var away := _away_from_building(op)
			for k in 2:
				_try_low("flowers", op + away * _rng.randf_range(0.8, 1.2) + away.orthogonal() * _rng.randf_range(-0.7, 0.7), _rng.randf_range(1.0, 1.3), Color(1, 1, 1), col2)
	# wildflowers in small groups on the pond and quarry banks
	for wid in ["pond", "quarry"]:
		var w := L.water_by_id(wid)
		var c: Vector2 = w["center"]
		for g in 7:
			var a3 := TAU * (float(g) + 0.3) / 7.0
			var gp := c + Vector2(cos(a3) * (float(w["rx"]) + 3.2), sin(a3) * (float(w["rz"]) + 3.2))
			var col3: Color = BLOOMS[(g + (2 if wid == "quarry" else 0)) % BLOOMS.size()]
			for k in 3:
				_try_low("flowers", gp + Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)), _rng.randf_range(0.9, 1.3), Color(1, 1, 1), col3)
	# hedge and wall feet: tufts
	for s in L.hedges + L.walls:
		var a2: Vector2 = s["a"]
		var b2: Vector2 = s["b"]
		var length := a2.distance_to(b2)
		var nrm := (b2 - a2).normalized().orthogonal()
		var t := 1.0
		while t < length - 1.0:
			if _rng.randf() < 0.3:
				var side := 1.0 if _rng.randf() < 0.5 else -1.0
				_try_low("grass", a2.lerp(b2, t / length) + nrm * side * (float(s["t"]) * 0.5 + 0.35), _rng.randf_range(0.9, 1.3), _grass_tint())
			t += 1.6


func _near_building(p: Vector2) -> bool:
	for bd in L.buildings:
		var hs: Vector2 = bd["size"] * 0.5
		var bp: Vector2 = bd["pos"]
		if Vector2(maxf(absf(p.x - bp.x) - hs.x, 0.0), maxf(absf(p.y - bp.y) - hs.y, 0.0)).length() <= 0.8:
			return true
	return false


func _away_from_building(p: Vector2) -> Vector2:
	for bd in L.buildings:
		var hs: Vector2 = bd["size"] * 0.5
		var bp: Vector2 = bd["pos"]
		var dx := absf(p.x - bp.x) - hs.x
		var dz := absf(p.y - bp.y) - hs.y
		if Vector2(maxf(dx, 0.0), maxf(dz, 0.0)).length() <= 0.8:
			return Vector2(signf(p.x - bp.x), 0) if dx > dz else Vector2(0, signf(p.y - bp.y))
	return Vector2.UP


func _grass_tint() -> Color:
	var v := _rng.randf_range(0.82, 1.12)
	return Color(v * _rng.randf_range(0.95, 1.08), v, v * 0.95)


## The forest beyond the boundary hedges (west, east, south) and a fringe
## on the far side of the lake rail: depth for the horizon.  Never reachable.
func _forest_beyond() -> void:
	var b := CampusLayout.BOUNDS
	var bands := [Rect2(b.position.x - 46.0, b.position.y - 10.0, 42.0, b.size.y + 60.0), Rect2(b.end.x + 4.0, b.position.y - 10.0, 42.0, b.size.y + 60.0),
		Rect2(b.position.x - 4.0, b.end.y + 4.0, b.size.x + 8.0, 40.0)]
	for rect: Rect2 in bands:
		var area := rect.get_area()
		var n := int(area / 52.0)
		for k in n:
			var p := Vector2(_rng.randf_range(rect.position.x, rect.end.x), _rng.randf_range(rect.position.y, rect.end.y))
			if _noise(p, 0.05, 31) < 0.22:
				continue   # clearings
			# one species per band (one batch per forest chunk): firs west
			# and south, broadleaf east
			var sp: String = "oak" if rect.position.x > 0.0 else "fir"
			var s := _rng.randf_range(0.95, 1.45)
			var tint := Color(_rng.randf_range(0.8, 1.0), _rng.randf_range(0.82, 1.0), _rng.randf_range(0.85, 1.0))
			# custom.r carries the species index for the builder
			_add(FOREST, p, 0.0, _rng.randf() * TAU, s, tint, Color(float(_species_index(sp)), 0, 0))


static func species_list() -> Array:
	return CampusKit.BROAD + CampusKit.CONIFER


static func _species_index(sp: String) -> int:
	return species_list().find(sp)
