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
| 3 Traversal | `test_campus_traversal.gd`: colliders exist; every open passage (the chapel's atrium, the bell tower's gap, porches, breezeways) is run through; open nav cells fit the runner; walks are clear; the play area is closed | passing |
| 4 Physics before/after | `test_campus_invariants.gd` pins every rule and body value; `git diff b3e5d74` of the motor and rules is empty | passing |
| 5 Routes from both halls | `test_routes_bots.gd` (bots complete curated routes from both halls; measured times) and `route_table.json` | passing, with the timer conflict above |
| 6 Online | protocol 9; the round carries the campus data hash and the hall geometry hash; a guest with other data refuses | passing (`test_dorms`, `test_coins`, network tests) |
| 7 Polish / frame time | see Performance | see Performance |
| 8 Shipping content | `tools/campus/scan_shipping.py` | 0 findings |

## Gaps

- North Hall's raised front porch is simplified to grade (the porch floor is 1.8 m up a stair in
  reality).
- Hall doors are 3.2 m wide (wider than the real doors) so the game's door rules work. The thresholds
  and the finish line are unchanged.
- The garden run is modelled as a wadeable channel.
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
