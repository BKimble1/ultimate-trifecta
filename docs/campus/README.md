# The campus rebuild

The game's campus is rebuilt from a real reference campus, in the game's own stylised look. The
player physics, the rules and the round are unchanged (`INVARIANTS.md`). Real institution and
building names identify the reference subjects only in the private research notes. The game, its
data and this repository use neutral names (`NEUTRAL_NAMES.md`). Nothing here claims to be an exact
survey.

## Where things are

| | |
|---|---|
| `game/data/campus/<layer>.json` | The campus as data: buildings, water, roads, paths, areas, barriers, trees, props, changes, and the gameplay layer. Every item carries its evidence (`ev`). Schema: `DATA_SCHEMA.md`. |
| `tools/campus/` | The pipeline: frame, tracing helpers, merge and validation, gameplay generator, registers, shipping scan (`tools/campus/README.md`). |
| `tools/campus/traced/<zone>.json` | The traced zones before the merge. |
| `game/src/map/` | Runtime: `CampusData` loads the layers; `CampusLayout` derives what the game reads; `CampusBuilder`, `CampusArchitecture`, `CampusChapel`, `CampusTower` and `DormArt` build the look and the colliders; `NavGrid` builds the bots' grid. |
| `EVIDENCE_REGISTER.md`, `evidence_register.csv` | Every traced item's sources, date, confidence and open questions. |
| `CHANGE_REGISTER.md` | What differs from the 2022 aerial (the October 2026 state). |
| `NEUTRAL_NAMES.md` | Inventory code → neutral id → in-game label. |

## The frame

One metric frame from EPSG:26916 (UTM 16N): x = E − 627300, z = 4479400 − N (+x east, +z south),
in metres. The 2022 public-domain orthophoto (0.295 m/px) is the base for tracing. The newer plans
and the wayfinding diagram are georeferenced onto it. `CampusLayout.BOUNDS` is
`Rect2(-720, -560, 1190, 1000)`.

## Start halls

Every race starts inside a men's residence hall: the **West Hall** (default) or the **North Hall**.
The host picks the hall in the round configuration. Guests get it with the hall's geometry hash
and refuse a round whose hall geometry differs (`CampusDorms.VERSION` 3).

- Each hall is the real building, with doors at its real entrances. Its interior is an open common
  room joined to the doors by the real entrance halls.
- The safe inside is the room plus every hallway past a door's threshold.
- Respawn pads stand just inside each door.

## The objective pool

Six real waters stand in for the game's six objective slots. The bindings are data
(`gameplay.json`, `objective_pool`), not code:

| Slot | In-game name | Real water (neutral id) | Colour | Icon |
|---|---|---|---|---|
| 0 | Garden Fountain | `garden_fountain` (small round basin with a pillar and bowl) | gold | star |
| 1 | Bridge Pond | `bridge_pond` (pond under the footbridge, stone edge on the plaza side) | green | leaf |
| 2 | Reflection Court | `reflection_court_basin_ne` + `_sw` (the paired basins, one objective) | cyan | drop |
| 3 | North Pond | `north_pond` | violet | diamond |
| 4 | Village Pond | `village_pond` | pink | flower |
| 5 | Campus Lake | `campus_lake` | orange | anchor |

The other waters are built and drawn but are never round targets:

- `garden_run`: a stony dry-creek channel; wadeable, never a splash.
- `garden_run_pool`: the small jet pool at its head.
- `lake_creek`.
- `woods_pond_west`: beyond the play area.

**Ambiguities flagged:**

- The reflection court is two touching basins, scored as one objective (a splash in either counts).
- Whether the garden run carries water except after rain is unknown, so it is modelled as wadeable.
- The garden fountain's basin depth and rim height are estimates.

## Measured routes and the timer

At the real scale the routes are long. The round stays 240 s; speeds, the timer and the waters'
positions are unchanged. `game/tools/route_analysis.gd` measures every three-water combination from
both halls on the runners' navigation grid and writes `game/config/route_table.json`. For each
combination it reports:

- **Route length:** out of the hall, through the three waters in the best order, and back.
- **Ideal run:** the length at full speed, plus three 1.5 s splashes.

| | Fastest ideal run | Median | Slowest |
|---|---|---|---|
| All 40 hall × combination routes | 148 s | 279 s | 429 s |

A round only uses combinations whose ideal run fits 85% of the round (204 s). If fewer than three
fit, the three shortest are used. This is a curation rule, not a rule change.

- **West Hall:** three combinations fit:
  - Garden Fountain + Bridge Pond + Reflection Court (934 m, 160 s ideal)
  - Garden Fountain + Bridge Pond + Campus Lake (929 m, 159 s)
  - Bridge Pond + Village Pond + Campus Lake (860 m, 148 s)
- **North Hall:** no combination fits. The three shortest are used:
  - Garden Fountain + Bridge Pond + Reflection Court (1,244 m, 212 s ideal; bots measured 218 s)
  - Garden Fountain + Reflection Court + Village Pond (1,449 m, 246 s)
  - Garden Fountain + Bridge Pond + Campus Lake (1,485 m, 252 s)

  The last two cannot be finished inside the round even with a perfect run.
- **North Pond** is in no curated combination from either hall. It is 300+ m from everything else.

**This is a conflict between the real scale and the timer, and it is reported, not hidden.** The
owner's options, none of them taken:

- a longer round for North Hall starts;
- a different objective pool for North Hall;
- North Hall as an occasional "long route" variant;
- or only West Hall starts.

## Acceptance gates

| Gate | How | Status |
|---|---|---|
| 1 Geometry overlay | `tools/campus/overlay.py` draws every layer over the aerial | overlays delivered privately (they show the reference imagery) |
| 2 Paired views | `game/src/dev/campus_views.gd` + the same viewpoints in the reference photos | delivered privately |
| 3 Traversal | `test_campus_traversal.gd`: colliders exist; every open passage (the chapel's atrium, the bell tower's gap, porches, breezeways) is run through; the footbridge is crossed both ways above the water and the nav grid routes across it; open nav cells fit the runner; walks are clear; the play area is closed | passing |
| 4 Physics before/after | `test_campus_invariants.gd` pins every rule and body value; `git diff b3e5d74` of the motor and rules is empty | passing |
| 5 Routes from both halls | `test_routes_bots.gd` (bots complete curated routes from both halls; measured times) and `route_table.json` | passing, with the timer conflict above |
| 6 Online | protocol 9; the round carries the campus data hash and the hall geometry hash; a guest with other data refuses | passing (`test_dorms`, `test_coins`, network tests) |
| 7 Polish / frame time | `tools/match_bench.sh` against the 2.0 baseline; loading steps; draw counts per view | p50 unchanged, p99 +0.6 ms, a few rare long frames (see Performance); not device-verified |
| 8 Shipping content | `tools/campus/scan_shipping.py` | 0 findings |

## Performance

These are this desktop container's numbers, never a phone's. No iPhone was available to this work, so
device frame rate, GPU time, heat and memory pressure are unverified. They were measured before the
last fixes: porticos, the chapel's roof and wings, facade bands and panels, and the water features.
Those add a few hundred triangles per building and seven colliders (the footbridge and its two
railings, and the docks).

**Gameplay bench.** `tools/match_bench.sh`: three Practice rounds of 75 s, every slot bot-driven, 60 fps
cap, seed 7, headless (CPU side). Two runs each, median (range):

| | 2.0 release candidate (old map) | Rebuilt campus |
|---|---|---|
| Frame interval p50 | 16.66 ms | 16.66 ms |
| Frame interval p95 | 17.21 ms | 17.51 ms |
| Frame interval p99 | 18.07 ms | 18.68 ms (18.57–18.80) |
| Frames over 33 ms (in 13,500) | 0 (0–1) | 6 (5–7) |
| Simulation tick p99 | 2.73 ms | 3.47 ms |
| Bots p99 | 1.09 ms | 1.44 ms |
| Nodes in a round | 1,654 | 6,161 |
| Static memory | 245–265 MB | 380–440 MB |

The median frame is unchanged and the tail is about 0.5 ms higher. The long frames are rare (about one
every 35 s of play, 34–91 ms) and no instrumented section explains them. The engine's own process and
physics times for those frames are small. A likely cause is CPU contention from the much longer
background work (path searches and pace fields on a grid 4 times the size) on a 4-core shared machine,
but that is not proven. **Profile on a device before release.** Memory and node counts are up, mostly
the 3,565 collision shapes (one node each) and the larger campus meshes.

**Draw cost.** `campus_views.gd` prints what each view drew, campus only and software rendered. At
player height, 43–144 draw calls and 52k–284k primitives per view. The old map's gameplay frames
measured about 316 draws and 456k primitives (with characters and HUD), so this is not like for like.

**Loading** (`test_loading`, this machine). A round prepares in about 3.6 s over about 350 frames. The
longest single job is about 40 ms; it was 125 ms before this pass's fixes:
- the ground height field is split into 16 tiles, built one per step and kept warm;
- the height grid is computed on a worker;
- the collision recipe is shared between rounds;
- build steps are time-sliced;
- the paved-area and shore-distance queries are indexed.

## Walkthrough

`tools/capture_campus_walkthrough.sh OUT_DIR` records one real Practice round on the rebuilt campus
with Movie Maker: West Hall start, the local runner driven by the game's own bot (`--local-bot`),
the follow camera and HUD, out to the round's three waters and back inside. It is composition
evidence on a software renderer, not device or frame-rate footage. The recording is delivered
privately with the other captures.

The first recording found a character bug unrelated to the map: far characters' skeletons went
NaN after a long frame. The planted-foot lock's release spring was stepped explicitly and
diverged when a frame's delta was long next to its 0.12 s time constant. It is now solved in
closed form and stable for any delta (`CharacterFootLock.release_step`, regression test in
`test_motion_v6`).

## Paired views (gate 2) findings

Thirteen reference photos were posed in the campus frame (five at medium confidence, eight low) and
rendered from the same cameras at the photo's field of view. The side-by-sides are delivered privately,
since they show the reference photos. (A first set framed the six photos narrower than 16:9 too
tightly: the game side showed about two thirds of the photo's field of view, so it looked zoomed in.
They are re-rendered with a field of view that matches after the crop.) What they show:

- **Massing, placement and storey counts** read right for the start halls, the chapel, the bell tower
  and the science centre.
- **Chapel roof and wings.** One roof was drawn over the chapel's whole outline, wings included, so it
  rose about 1.7 times too high against the walls and the four gabled wings did not show. The roof now
  covers the octagonal core only, and each diagonal wing has its own gable running back into it,
  closed by a white pediment with a ring moulding, as the photos show. The atrium's two porches are
  flat-topped under those pediments.
- **Chapel entrance axis.** Two photos show a pedimented, columned entrance gable facing north-west,
  and walks reach the garden ring from the NW, SW and SE. The data's walk-through atrium runs NE–SW,
  traced from a video frame and the ring walks. The atrium's axis needs a closer check (it may be
  NW–SE). It is left as traced until then.
- **Bell tower.** It matches from the north-east. The pier pair's orientation may be off by a few tens
  of degrees.
- **Porticos.** The generic gable drew the start halls' pediments in brick; the photos show white
  ones. Now drawn from the evidence (`roof.pediment` in `DATA_SCHEMA.md`):
  - North Hall: a white pediment with a round louvre, a white entablature, the giant columns rising
    to it (the portico is open to about 12.3 m) and windows on the wall behind; the west gable end
    is a white pediment with a louvre too.
  - West Hall and East Hall: a white pediment with a glazed oculus over the giant columns, and white
    cupolas.
  - The administration hall: a white pediment with a plain clock face (no lettering).
  The fifth row of windows in the North Hall photo is the exposed basement on the sloping site.
- **Facades.** West Hall's and East Hall's windows stack in vertical strips with grey panels between
  them, and North Hall has a white band above its ground floor. Both were in the style notes but not
  drawn; now they are (`style.spandrel`, `style.band`).
- **Garden fountain.** It was drawn as a generic upright form. It is now a slender pillar with a bronze
  bowl and four falls, as the evidence describes. In the photo the water leaves from spouts at the top
  of the pillar under the bowl; the game's falls drop from the bowl's lip.
- **Water features.** Several features were traced but never built: the footbridge over Bridge Pond,
  the lake's L-shaped swim dock, fishing dock, three swim rafts and sand beach. The dock art read keys
  the data does not use, and drew a plank in the middle of the lake. Now:
  - The footbridge (concrete deck, black picket railings) and the docks are walkable decks, and the
    bots' grid has a lane across the bridge.
  - The rafts are drawn only. A splash takes a runner straight to an exit, so nobody swims to them.
  - The beach tints the shore as sand.
  Every measured route is unchanged, since each one ends with a splash.
- **Village Pond.** The pose fitted on the four homes beyond it puts the camera inside the traced
  outline. The photo shows only about 15 m of water to the jet and 20 m to the far bank, so the built
  pond is probably smaller, or further north, than the design-plan circle the data uses (no overhead
  image after 2022 shows it). It is left as traced; newer imagery would settle it.

## Gaps

- North Hall's raised front porch is simplified to grade (the porch floor is 1.8 m up a stair in
  reality). Its cupola is not drawn: the roof where the ranges cross is modelled flat.
- The halls' side-door canopies are drawn as flat slabs; the photos show small white gabled ones.
- Hall doors are 3.2 m wide (wider than the real doors) so the game's door rules work. The thresholds
  and the finish line are unchanged.
- The garden run is modelled as a wadeable channel.
- Village Pond's shoreline is the 2023 design plan's; a 2025 photo suggests the built pond is smaller
  or further north (Paired views, above). It is an objective water, so a correction would move its
  exits and change the route table.
- The chapel atrium's route is assumed straight. A plaque wall may make the real route jog.
- North Hall rounds don't fit the timer, and North Pond is in no curated combination (above).
- Every inventory code is traced (`NEUTRAL_NAMES.md`), but these are low-confidence:
  - **Terrace apartments (B06):** placed from the 2026 wayfinding diagram fitted to the streets. There is
    no photo, so their height and finish are placeholders, and whether the rear block replaced a house is
    open.
  - **North court homes (B45):** placed from the inset map fitted to the street crossings (±3 m).
    Unit count and lengths are inferred from two photos. Neither site is in any overhead image in the
    pack; newer statewide imagery would settle both.
- **Vegetation** is read from the 2022 leaf-off aerial only (no species).
  - Woodland interiors are representative fills at about 10 m spacing (`obs: inferred`, low
    confidence), not counts.
  - Plantings inside sites built after 2022 were removed.
- **Two background side streets** (`ctx_road_007`, `ctx_road_011`) look 3–5 m off in the aerial.
  They are outside the play area and still to be checked.
- **Data conflicts resolved at merge time:**
  - Gates are cut where traced walks cross fences.
  - Trunks and props are moved off walks.
  - A few remain and are listed by the traversal test: under 0.2% of walk samples touch a collider,
    namely two spots on the chapel's alcove walls and a table on a walk.
