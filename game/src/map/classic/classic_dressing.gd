class_name ClassicDressing
extends RefCounted
## Decorative dressing for Moonbrook College (the classic map, as 2.0 shipped it): understory shrubs,
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
##
## Classic map: the list baked by the 2.0 build (its generator and bake
## tool stay in that source) is restored verbatim as
## game/assets/maps/classic/classic_dressing.res; the loading screen only
## reads it.  test_classic_map checks it is the 2.0 bake, piece for piece.

const BAKED := "res://assets/maps/classic/classic_dressing.res"
## floats per item: x, y, z, yaw, scale, tint r g b, custom r g b
const STRIDE := 11
const LOW := ["grass", "flowers", "lilies", "rock_flat"]
const MID := ["shrub_round", "shrub_tall", "shrub_bloom", "reeds", "rock_round", "rock_layer"]
const FOREST := "forest"
## footprint radius at scale 1 (m), for clearances and the safety test
const RADIUS := {"grass": 0.2, "flowers": 0.3, "lilies": 0.8, "rock_flat": 0.5, "shrub_round": 0.55, "shrub_tall": 0.5,
	"shrub_bloom": 0.6, "reeds": 0.4, "rock_round": 0.5, "rock_layer": 0.5, "forest": 3.0}


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


static func species_list() -> Array:
	return ClassicKit.BROAD + ClassicKit.CONIFER


# ---------------------------------------------------------------------------
# (2.2 build 22) More foundation planting
# ---------------------------------------------------------------------------
## Extra shrubs along the buildings' walls, added to the 2.0 bake at load
## (the bake itself stays as shipped).  The same rules as the bake's "mid"
## pieces: each one hugs a wall (its middle 0.62 m out, inside 0.55 m of the
## plinth), never on a path, road or plaza, at an entrance or dorm door, a
## water, a coin or power-up spot, a hiding bush, a lamp or bench, and never
## on top of a baked shrub.  Deterministic: every device has the same.
## {kind: PackedFloat32Array} in the bake's layout (STRIDE floats each).
const EXTRA_STEP := 2.6
const EXTRA_OUT := 0.62
const EXTRA_CAP := 420


static func extras(L: ClassicLayout, baked: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 220022
	var taken: Array = []   # existing mid pieces (x, z)
	for kind in baked:
		if kind in MID:
			var a: PackedFloat32Array = baked[kind]
			for i in range(0, a.size(), STRIDE):
				taken.append(Vector2(a[i], a[i + 2]))
	var avoid: Array = []   # [point, clearance]
	for d in L.dorm_doors:
		avoid.append([d["pos"], 4.5])
	for g in L.gadget_spots:
		avoid.append([g, 2.5])
	for c in L.coin_spots:
		avoid.append([c, 2.0])
	for lp in L.lamps:
		avoid.append([lp, 1.0])
	for bn in L.benches:
		avoid.append([bn.get("pos", Vector2.INF), 1.6])
	for sp in L.runner_spawns + L.patrol_spawns + L.dorm_pads:
		avoid.append([sp, 2.0])
	var out := {"shrub_round": PackedFloat32Array(), "shrub_tall": PackedFloat32Array()}
	var n := 0
	for bd in L.buildings:
		if bool(bd.get("background", false)) or absf(float(bd.get("rot", 0.0))) > 0.001 or String(bd["id"]) in ["tower", "shed", "observatory"]:
			continue
		var pos: Vector2 = bd["pos"]
		var hs: Vector2 = (bd["size"] as Vector2) * 0.5
		# the entrance (non-dorm buildings): the face toward the campus centre
		var to_c := -pos
		var face_n := Vector2(signf(to_c.x), 0) if absf(to_c.x) * hs.y > absf(to_c.y) * hs.x else Vector2(0, signf(to_c.y))
		var entrance := pos + face_n * (hs * face_n.abs()).length()
		for f in [[Vector2(-hs.x, -hs.y), Vector2(hs.x, -hs.y), Vector2(0, -1)], [Vector2(hs.x, -hs.y), Vector2(hs.x, hs.y), Vector2(1, 0)],
				[Vector2(hs.x, hs.y), Vector2(-hs.x, hs.y), Vector2(0, 1)], [Vector2(-hs.x, hs.y), Vector2(-hs.x, -hs.y), Vector2(-1, 0)]]:
			var a0: Vector2 = pos + (f[0] as Vector2)
			var a1: Vector2 = pos + (f[1] as Vector2)
			var nrm: Vector2 = f[2]
			var length := a0.distance_to(a1)
			var dir := (a1 - a0) / length
			var t := 1.4 + rng.randf_range(0.0, 0.8)
			while t < length - 1.4 and n < EXTRA_CAP:
				var p := a0 + dir * t + nrm * (EXTRA_OUT + rng.randf_range(-0.05, 0.05))
				t += EXTRA_STEP + rng.randf_range(-0.5, 0.7)
				if not _extra_ok(L, p, entrance, taken, avoid):
					continue
				var tall := rng.randf() < 0.3
				var s := rng.randf_range(0.55, 0.72)
				var tint := Color(1, 1, 1).darkened(rng.randf_range(0.0, 0.12))
				var y := ClassicBuilder.grid_y(L, p.x, p.y)
				var arr: PackedFloat32Array = out["shrub_tall" if tall else "shrub_round"]
				arr.append_array(PackedFloat32Array([p.x, y, p.y, rng.randf() * TAU, s, tint.r, tint.g, tint.b, 0.22, 0.42, 0.24]))
				out["shrub_tall" if tall else "shrub_round"] = arr
				taken.append(p)
				n += 1
	# along the hedges and fences, on both sides (hugging them)
	for lst in [L.hedges, L.fences]:
		for sg in lst:
			var a: Vector2 = sg["a"]
			var b: Vector2 = sg["b"]
			var th := float(sg.get("t", 0.4)) * 0.5
			var length := a.distance_to(b)
			if length < 3.0:
				continue
			var dir := (b - a) / length
			var nrm := Vector2(-dir.y, dir.x)
			var t := 1.5 + rng.randf_range(0.0, 2.0)
			while t < length - 1.5 and n < EXTRA_CAP:
				var side := 1.0 if rng.randf() < 0.5 else -1.0
				var p := a + dir * t + nrm * side * (th + 0.45)
				t += 4.2 + rng.randf_range(0.0, 2.5)
				if not _extra_ok(L, p, Vector2.INF, taken, avoid):
					continue
				var s := rng.randf_range(0.5, 0.66)
				var tint := Color(1, 1, 1).darkened(rng.randf_range(0.0, 0.15))
				var arr: PackedFloat32Array = out["shrub_round"]
				arr.append_array(PackedFloat32Array([p.x, ClassicBuilder.grid_y(L, p.x, p.y), p.y, rng.randf() * TAU, s, tint.r, tint.g, tint.b, 0.22, 0.42, 0.24]))
				out["shrub_round"] = arr
				taken.append(p)
				n += 1
	return out


static func _extra_ok(L: ClassicLayout, p: Vector2, entrance: Vector2, taken: Array, avoid: Array) -> bool:
	if not BOUNDS_OK(L, p) or p.distance_to(entrance) < 3.4:
		return false
	if L.is_on_path(p, 0.9) or L.is_on_road(p, 1.0):
		return false
	for pl in L.plazas:
		if pl["shape"] == "circle":
			if p.distance_to(pl["center"]) < float(pl["radius"]) + 0.9:
				return false
		else:
			var phs: Vector2 = pl["size"] * 0.5 + Vector2(0.9, 0.9)
			var pc: Vector2 = pl["center"]
			if absf(p.x - pc.x) < phs.x and absf(p.y - pc.y) < phs.y:
				return false
	for w in L.waters:
		if ClassicLayout.in_water_shape(w, p, 2.5):
			return false
	for q in taken:
		if (q as Vector2).distance_to(p) < 1.6:
			return false
	for e in avoid:
		if (e[0] as Vector2).distance_to(p) < float(e[1]):
			return false
	return true


static func BOUNDS_OK(L: ClassicLayout, p: Vector2) -> bool:
	return ClassicLayout.BOUNDS.grow(-2.0).has_point(p)
