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
