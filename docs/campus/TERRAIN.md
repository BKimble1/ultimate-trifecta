# The reference campus's ground, floors and stairs

The reference campus is no longer flat. Its ground is the measured bare earth. Its waters, building
floors and entrances sit at levels resolved from that ground, and its raised entrances have real
stairs. The motor, the speeds, the jump, the timer and the rules are unchanged (`INVARIANTS.md`).
Moonbrook College (the classic map) stays flat at y = 0, as in 2.0.

## Source

| | |
|---|---|
| Data | USGS 3D Elevation Program 1 m DEM, tile `USGS_1M_16_x62y448_IN_Indiana_Statewide_LiDAR_2017_B17`; public domain |
| Survey | Indiana statewide LiDAR, acquired 2017-03-03 .. 2020-04-11, published 2021-07-04. **Not** an October 2026 survey: anything built or regraded since is not in it |
| Frame | NAD83 / UTM 16N (EPSG:26916), the campus frame `x = E − 627300`, `z = 4479400 − N`; 1 m samples |
| Vertical | NAVD88 metres. Game y = NAVD88 − **280.40 m**, the grade at West Hall's front door, so the default start stands at y ≈ 0 |
| Scale | One metre is one metre, horizontally and vertically. Nothing is exaggerated. The play area spans about −17.7 m (the lake) to +6.1 m |

The DEM tile and its crop stay in the private research area, outside this repository.
`tools/campus/terrain.py --crop` reproduces the crop from the tile, and `--dem` reproduces the bake.
The bake's output is `game/data/campus/terrain.bin` (float32 metres, 1191 × 1001 samples) and
`terrain.json` (its metadata, the levels below, a report and a sha256). Both feed the campus data
hash, so two builds with different ground refuse to play together.

## What the bake does (deterministic)

1. **Ground.** It samples the DEM at integer game metres (bilinear) and smooths it lightly (Gaussian,
   σ 0.8 m). That removes the LiDAR's sub-decimetre noise, not the grade.
2. **Waters.** Each one is levelled:
   - Survey-flattened ponds and the lake keep their measured surface: Campus Lake, North Pond, Bridge
     Pond's upper lobe, and the west woods pond.
   - A pond dug after the survey has a bed that is above its banks in the DEM. It sits just below its
     lowest bank: Village Pond, and Bridge Pond's lower lobe. **This is an inference.** Newer survey
     or photographs would settle it.
   - Built basins sit on their plaza's grade: the garden fountain, the reflection court's basins and
     the garden run's head pool.
   - Channels follow their slope: the garden run and the lake creek.
   - The ground inside a water is its surface; the game cuts the bed below it. A bank lower than the
     surface is raised to just above it.
   - **Footbridge abutments.** The survey predates the footbridge over Bridge Pond, and left its lower
     bank 0.17 m under the deck, more than a runner steps up. Both ends are graded to the higher bank:
     level within 1 m of each end, blending out over the next 2.5 m, on land only. The deck then spans
     level from bank to bank (`CampusLayout.feature_decks`).
3. **Floors.** Each building gets a floor level: the 80th percentile of the grade in a 1–3 m ring
   round its footprint, or the data's `floor_navd88`. A building on a slope stands at its high side,
   and its low side shows its foundation or exposed basement (`CampusBuilder._plinth`). The ground
   under the footprint is that level.
4. **Entrances.** Each one is resolved, and every door then sits at its level (`entrances[i].y`):

   | Step down to the grade outside | What the bake does | Count |
   |---|---|---|
   | under 0.25 m | grades a 4 m apron to the floor (accessible) | 82 |
   | from 0.25 m | a **stair** (below) | 24 |
   | over 2.6 m, with no stair in the data | a **lower-level door** at grade, under the exposed basement | 2 |
   | its stair would run into another building or stair | no stair; reported (the link needs evidence) | 1 (Lakeview Hall, facing the dining hall) |

5. **Steep ground.** Steep cells go on the bots' 2 m grid: a rise over 0.9 m per metre for runners, and
   over 0.55 m for carts. A stair's cells are open on foot and closed to carts.

## Stairs

A stair runs out from its entrance's top edge along the entrance's facing, from the floor down to
the grade:

- risers about 0.165 m (an integer count from the rise), a 0.30 m going;
- a landing after every 10 risers;
- rails where it rises more than 0.6 m;
- the foot where it meets the measured grade (iterated, since a longer stair reaches lower ground).

The data can fix any of these per entrance (`entrances[i].stair`, `DATA_SCHEMA.md`). A passage can
also have **steps with no door** at its open mouth (`passages[i].steps`): the innovation center's
front arcade stands 1.1 m over the walk at its south end, and inferred steps come down from it there.
A raised portico raises its whole building (`floor_navd88`), so its entrance gets a stair: the
administration hall stands 0.6 m over its front walk. **North Hall's
front stair** is one such: centred on the front doors as photographed, 16 risers of 0.167 m (about
2.7 m) in four flights with three 3.6 m landings stepping down the bank, a 0.32 m going, a 0.6 m deck
before the portico, 7 m between its rails, and the centre handrail between two flights. Its rise is
the DEM's, from the portico floor to where the traced rails end; the counts and landings are inferred
from the photos.

How it is built (`CampusStairs`):

- **Drawn** as real treads and risers (solid down into the ground), with a lighter nosing on each
  step, stepped cheek walls on both sides, landings, and rails (posts about 1.2 m apart and a
  handrail). Porticos have pale stone and white rails; other entrances concrete and dark rails.
- **Collision: the recorded approximation.** The character motor snaps to the floor but has no step
  climbing, so the motor is unchanged and the stair collides as a **close-fitting ramp under its
  nosings**. The ramp follows the line through the front edges of the treads, which is on or just
  above every tread and never more than one riser over a foot. It is level on the deck and the
  landings, and it is solid down into the ground, so nobody walks under a stair. Its slope is the
  stair's own (about 29°), inside the motor's 50° floor angle. It adds no shortcut: it covers
  exactly the stair's run and width. Rails collide (0.95 m) on the flights and landings. A porch deck
  stays open at its sides.
- **Carts:** one cart blocker covers each stair. A 29° ramp is inside the carts' 35° floor angle, and
  a stair is not a road.
- **Ground:** under a stair it is kept at least 0.3 m below the walking line. Two level slabs make
  the joins flush: a 1 m lead-in behind the top edge at the floor (the ground's 1 m samples leave a
  porch floor sloping down over its last metre), and a 0.6 m run-out past the last tread at the
  bottom step, where the ground is graded exactly to the bottom step (a ditch there left a lip steeper
  than the floor angle, and runners stopped at it). A 3 m walk beyond is graded to the bottom step.
  The lead-in is normally the porch floor inside the building. Where the building does not cover it
  (a door traced in front of its wall; six stairs, from slivers to a whole landing), it is drawn as a
  stone landing solid to the ground, never left as an invisible collider (`lead_open` in the layout).
  Waterside Hall's south-west door was traced a metre past the hall's corner; it is moved onto the
  south face (inferred) so its landing no longer stands beside the hall.
- **Furniture:** a bench, lamp, prop or trunk the data placed where a stair now stands is left out
  (`CampusLayout.off_stairs`; none in the current data). A barrier that crosses a stair
  stands on its walking line (North Hall's centre handrail).

`test_terrain.gd` covers:

- every stair's collision matches its nosing line (within 4 cm; measured 0 cm);
- every stair is closed to carts;
- a runner climbs North Hall's stair to the portico floor at running pace and comes back down to the
  walk;
- every stair is climbed from the walk at its foot to its top edge at running pace;
- a jump from its landing lands on the stair, not inside it.

## Elevation-relative gameplay

Everything that stood at y = 0 now stands on the ground or its floor:

- spawns, respawn pads, coins, gadgets and the carts' home;
- lamps, benches, trees, props, walls (split along slopes; a retaining wall tops out above its high
  side), hedges, fences and bollards;
- water surfaces, beds, exits and the splash threshold (absolute);
- each hall's room, ceiling, furniture and door thresholds (`CampusDorms.VERSION` 4).

The finish rule is unchanged: a runner physically crosses a valid doorway inward, within its width
and height band. The height band is now measured from that door's own floor (`door.floor_y`), so
nobody below a raised room counts as safe or home, and nobody finishes by walking under a porch
(`test_terrain`, `test_dorms`).

The ground's collision is still separate square Jolt height-field tiles (4 × 4 of 298 m) that share
their edge samples. `test_terrain` checks the seams: worst step under 5 cm.

## Limits

- A 1 m DEM does not hold curbs, steps or retaining walls below about a metre. Where the data has no
  stair, a step of under 0.25 m is graded as an apron.
- The survey predates Village Pond and Bridge Pond's lower lobe, and any building or grading since
  2020. Their levels are inferences (above).
- Floor levels are the grade round each building, not measured thresholds, unless the data gives one.
- Road crossfall, shore retaining walls and the bridge pond's terraces are not yet modelled as
  breaklines.
