# V6 dorms: real common rooms, a home dorm per round, doorway finishes, gold coins

This is the V6 dorm workstream (brief §6, the coin collectibles of §11, the
campus-around-the-dorms part of §5). A round now **starts inside tonight's
home dorm** and **ends by running back inside it through a door**; the host
picks the dorm per round and publishes it in the round configuration; eight
gold coins per round wait on the runner routes.

**What these notes can and cannot claim.** Every number here comes from the
real simulation, physics, bots and renderer, run headless or on Mesa
llvmpipe (software Vulkan, Mobile renderer) under Xvfb on a shared desktop
Linux machine (load average often above 10). Bot timings are bot play, not
people. Draw counts are engine counters on llvmpipe; nothing here measures an
iPhone's frame time, GPU cost or heat.

## The three dorms

| Dorm | Where | Footprint × height | Look | Common room | Doors |
|---|---|---|---|---|---|
| **Puddlesworth Hall** | (0, 112), the V5 dorm | 44 × 18 m, 11 m | red brick, slate gable with chimneys and four lit dormers, blue-and-gold house banners | 43 × 9 m long gallery behind the front, red sofas | front (N), west, east |
| **Lanternfield House** | (−96, 114), the lawn west of it | 28 × 20 m, 9.5 m | cream plaster, steep teal roof with a glowing glazed lantern cupola on the ridge, gold banners | 27 × 9 m, teal sofas | front (N), west, east |
| **Moonpenny Lodge** | (96, 113), the lawn east of it | 24 × 26 m, 8.5 m | sage timber cladding, a tall deep-red gable facing the campus with a round lit window, a stone chimney | 23 × 9 m, mustard sofas | front (N), west, east |

All three share one plan (`game/src/map/campus_dorms.gd`, `CampusDorms`):
a one-storey common room across the front of the building (ceiling 4.6 m,
the floors above solid), the rest of the building closed. Each room has
**three real openings** (3.2 m wide, 3 m high, a lintel above): the front
door on the campus side and one door in each end wall, so the doors are on
three faces, 18–44 m apart, and no spot outside covers two of them within two
lunges (tested). There are no door leaves and no animation: an open, lit
entrance is identical on every client and can't block anyone.

Everything about a dorm is computed from a few numbers in one place:
colliders (`CampusBuilder.build_collision`), both nav grids (`NavGrid`), the
look (`DormArt`), the spawn and respawn pads, the thresholds, the bots' door
points, the maps and the tests. The geometry has a version
(`CampusDorms.VERSION`, 1) and a fingerprint (`geometry_hash`), both
published in every round's configuration.

**Inside.** Warm plaster walls over a dark wood wainscot, a plank floor with
two rugs, ceiling beams and pendant lights, a low fireplace with the house
crest, sofa runs along the back wall (with colliders), framed pictures and
sconces, moonlit windows with curtains on the front wall, a noticeboard and
pigeonholes, potted plants in the back corners. The middle of the room stays
open for running. Warmth comes from per-vertex emission (as the lit windows
do) and the light field's warm channel stamped over the room — no new
lights, materials or textures. **Outside.** Stone door surrounds with a
keystone and a lit fanlight, porch hoods on knee braces, wall lanterns, a
flush stone threshold and a warm pool of light at each door; the interior is
visible through the openings.

## Home dorm per round and the round configuration

The host picks tonight's dorm from the round seed (`CampusDorms.pick`),
never the same as the previous round when another is available (the guided
tutorial always uses Puddlesworth Hall). Then the targets come from **that
dorm's** fair set (`RulesLogic.curated_combos(dorm)`), the spawn pads are
assigned, and the coins are chosen. All of it goes into START (protocol 6):

```
"home_dorm": "lanternfield",
"dorm": {"id": "lanternfield", "ver": 1, "geo": "<16 hex>", "spawns": {"0": 0, "1": 1, ...}},
"targets": [...],
"coins": [{"id": "s07", "x": -88.0, "z": 46.0}, ...],
"timing": {"reveal_s": 4.0, "countdown_s": 3.0, "head_start_s": 6.0}
```

A guest checks it field by field (`NetSession._fix_start`): an unknown dorm,
another geometry version or fingerprint is **incompatible** and the guest
leaves with the existing "Update the game to join" reason; an out-of-range
pad falls back to the default mapping; malformed coins are dropped. A
reconnecting guest is sent the same START, so it rejoins the same dorm,
pads, targets and coins; results carry `home_dorm`.

## Start, reveal and countdown

Runners stand on their own pads in the common room (8 pads, ≥ 1.6 m apart,
≥ 1 m from the walls, ≥ 2.4 m from any doorway, clear of furniture), each
facing one of the three doors with a clear line to it: three before the front
door, two toward each end door. The Night Watch starts at the Grounds Shed
(a third shed spawn was added so three watchers no longer share one spot).
The 4 s reveal card now names the dorm ("Home tonight: Lanternfield House",
or for the Night Watch "The runners' home tonight: …") with the role lines,
then the 3 s countdown; the camera starts behind the runner inside the room,
looking at its exit. Nothing can tag during the reveal or the countdown —
the simulation runs no intents before GO (tested with a watcher standing next
to a runner pressing Tag every tick, for every dorm and 1/2/3 watchers).

## The finish: a threshold crossing, host-authoritative

`CampusDorms.crosses(door, a, b)` plus `MatchSim.home_crossing`:

1. Each tick the host keeps every runner's position at the start of its move
   (`prev_pos`; cleared to "none" after a respawn, a resurfacing or a
   recovery, so a teleport can never be a crossing).
2. After the move, for each of **tonight's home doors**: the segment from the
   start to the end position must go from the outside side of the threshold
   line (across the opening at the wall's **inner** face) to the inside side
   — inward only;
3. cross it within the opening (±1.5 m of the door's centre: the capsule
   can't get nearer the jambs anyway);
4. at feet height between −0.5 and 1.6 m (a mid-jump through the door counts;
   nothing over a lintel could);
5. on a move shorter than 3 m in one tick (no teleport);
6. with a clear line between the two points at chest height (no wall, no
   tunnelling).

A runner with all three stamps whose move passes every check is home: the
finish applies once (FINISHED, body off, finish order, which door), and as
before it is resolved before tags in the same tick. Because the test sweeps
the move, any speed counts (a 40 m/s move — 0.67 m in a tick — is caught on
that tick in the tests) while a move that would carry a runner through the
wall beside a door is stopped by the body, and a forced position change
through the wall is refused by the line check.

**Never a finish:** standing inside from the start, running out, coming back
without all three stamps, another dorm's doors (the other dorms are
enterable ordinary buildings), pushing against the wall beside a door,
crossing outward, crossing over the height band, a teleport. The old
exterior finish boxes are gone.

**Safe inside.** Nobody can be tagged inside the home dorm's common room
(`SimPlayer.home_safe`, set by the host each tick; the tag assist and the
Night Watch bots ignore such runners). The Night Watch may walk in. This is
what keeps a watcher from camping the pads: before a runner's first splash,
a capture (or an out-of-bounds recovery) returns them to one of the pads
just inside each door of the **home dorm**, the one farthest from the Night
Watch, with the usual 2 s protection — and with three doors on three faces,
one camper can't cover the way out.

## Collision, navigation, bots and the camera

- **Colliders** (11 boxes per dorm + 3 furniture): the closed block, the
  upper block over the room, wall segments beside each opening, three
  lintels; sofas and the hearth. Carts are stopped at every doorway by a
  cart-only blocker (not drawn: no bollards in a door) and, as Puddlesworth's
  grounds already were, by bollards around the two new yards — the whole
  dorm strip along the south of the campus is cart-free.
- **Nav.** The foot grid has the room and a 2-cell-wide passage through each
  door (walls inflated by the usual 0.45 m); the cart grid has the whole
  building solid. Every pad reaches every door; every door's outside reaches
  its inside in a straight line (tested).
- **Bots.** Runner bots plan their order from tonight's dorm, leave through
  the nearest door, and come home to a point just inside the door nearest
  their approach (the path through the opening finishes them). Night Watch
  bots patrol outside tonight's doors, ignore runners who are safe inside,
  and park carts on the road along the yards instead of searching for the
  enclosed yard cells (that search explored the whole road network and
  failed: 2,619 unreachable lookups per 6,000 ticks in `sim_profile`, 354
  after). Every bot path goes through `NavGrid.find_path_budgeted` (one A*
  per tick).
- **Door jambs.** From −60° to +60° and three offsets at every door of every
  dorm, and sliding along the wall into the opening, a runner pushing for
  the door gets in without snagging (slowest scripted entry 1.6 s from 6 m).
- **Camera.** `FollowCamera._narrow_occluder` treated a wall's end beside an
  opening as a lamp post and left the camera 0.2 m behind the wall with the
  runner hidden; it now needs both parallel rays clear (a free-standing post
  or trunk). From every pad and door, all round and at three pitches (1,560
  poses), the camera is clear of every collider, under the ceiling inside,
  and sees the runner.

## Gold coins

Eight gold coins per round (`RulesConfig.coin_spawns_per_round`), each worth
**exactly one Coin**.

- **Where.** 30 candidate spots on the runner routes (footpaths and walks
  across the campus, `CampusLayout.coin_spots`). Every candidate is on walkable
  ground, not in water, ≥ 4 m from a gadget pickup, ≥ 10 m from any dorm door,
  ≥ 6 m from every water exit, and reachable on foot from every dorm (tested).
  Per round the host shuffles them with the seed and takes eight, ≥ 28 m apart
  where possible (falling back to 17 m), ≥ 14 m from tonight's home doors and
  ≥ 8 m from the active waters' exits, jump-in points and pads
  (`RulesLogic.pick_coins`). Each gets a round-scoped id (`s07`: the spot's
  index) and goes into the round configuration. Over 360 test rounds every
  dorm's sets move around the whole list.
- **Who.** Anyone on foot within 1.1 m — a runner or the Night Watch, human or
  bot (`MatchSim._check_coins`, step 8 of the fixed tick order). Not while
  caught, splashing, home, waiting in the shed or driving a cart. Two on the
  same tick: the nearer, then the lower slot. A taken coin stays gone for the
  round.
- **Replication.** The host emits `COIN_PICKUP` (reliable event, deduplicated
  by event id like every event), every snapshot carries the coins still out
  (u16) and the recipient's own count (u8, private block). So a replayed
  packet, a second client, a late snapshot or a reconnect can't show a coin
  that was taken or count one twice: the view only ever hides coins.
- **Results.** Every row has `coins_picked` (humans and bots; bots own no
  wallet — the row says `is_bot`) and the round has `coin_log` [[id, slot]]
  and `coins_total`. Wallet settlement is the commerce workstream's, once per
  match id and player identity, from `coins_picked`. **Cancelled rounds settle
  nothing** (RULES.md); the row still records the pickups.
- **Bots.** Runner bots detour for a coin within 7 m of where they are (never
  while lining up a jump into a water); Night Watch bots on patrol take one
  within 6 m of their way. That is what makes them visible collectors; it
  costs at most one path request (budgeted).
- **Look and cost.** All of a round's coins are one `MultiMesh` instance list
  with one shared `ShaderMaterial` (`coin.gdshader`: spin and bob in the
  vertex shader, warm gold with a restrained emission and rim) — one draw
  call, no per-frame CPU, no material per pickup. A taken coin flips its
  instance's custom data (the instance collapses). A pooled two-emitter gold
  sparkle, a higher-pitched pickup sound (quieter for others), a 12 ms
  haptic tick for your own, and a HUD chip beside Home n/N with a small "+1"
  that rises and fades (no motion with Reduced Motion). Mesh, material and
  sparkle are made once per session and warmed in a preparation job
  (`home_coins`).

## Route, contact and first-objective analysis (every dorm × combination)

TBD-BALANCE

## Campus around the dorms

The two new dorms stand on what were open lawns between the service roads
(no V5 tree, lamp, bench or prop stood there), Puddlesworth keeps its V5
grounds. Composed rather than scattered:

- **Approaches.** Each new dorm has a paved forecourt off the road with a
  monument name sign (stone, lit, a small collider), benches flanking the
  front door, lamps at the forecourt corners and a bike rack by the facade;
  stone paths from its end doors to the service road and to the V5 diagonal
  paths that lead to Puddlesworth, so the three dorms are linked on foot.
  Puddlesworth gets paved aprons at its new side doors.
- **Wayfinding.** Fingerposts at the two yard junctions (Lanternfield House /
  Puddlesworth Hall, Moonpenny Lodge / Puddlesworth Hall); name boards on
  each dorm above its porch; the three silhouettes differ (long brick block
  with dormers, lantern cupola, tall timber gable).
- **Planting.** A few hand-placed yard trees (broadleaf and pine, colliders as
  every layout tree) frame the forecourts and the backs; the dressing's
  foundation shrubs and blooms grow along the new walls away from doors,
  tufts along the new paths, flowers at the new lamps (regenerated inside the
  districts only; the V5 pieces outside are kept piece for piece, minus five
  shrubs that stood on the new bots' routes).
- **Kept clear.** No new collider stands on a new path, in a doorway or on a
  door's approach (tested); the yards are cart-free; nothing new is
  transparent, no light was added, nothing has physics of its own.

## What changed in collision, nav and layout (and what did not)

`test_campus_art` now proves two things instead of one:

1. **The V5 campus is still built exactly.** `CampusLayout.new(true)` (the V5
   layout, built by the same code before the V6 additions) hashes to the
   values recorded on V4 (`dcebf4e`): 525 collision shapes, collision
   `15d3dc7a…`, nav `79361473…`, layout `803fc8ac…`.
2. **V6 changes nothing outside the dorm districts**
   (`CampusDorms.DISTRICTS`: Puddlesworth's building and ring walk,
   Rect2(−28, 98, 56, 26); the west and east yards, 45 × 50 m each). Compared
   with the V5 layout: the 513 collision shapes lying outside the districts
   are identical (sorted line by line: body, layers, type, size, transform);
   88,192 nav cells of both grids outside the districts (grown by 3 m for
   inflation) are identical; every layout list's items outside the districts
   are identical. The one deliberate change outside: a third Night Watch spawn
   at the shed (data only, no collider).

Inside the districts (V5 → V6): shapes 525 → 605; buildings −1 (Puddlesworth's
box) +3 (the shells: 11 boxes + 3 furniture each); +6 paths, +5 plazas,
+15 cart blockers (9 hidden doorway stops, 6 yard bollard lines), +10 trees,
+8 lamps, +4 benches, +2 props, +2 monument signs; runner spawns 6 outdoor →
24 indoor pads (8 per dorm), dorm doors 4 → 9 (with thresholds instead of
finish boxes), dorm respawn pads 6 → 9 (inside). Nav cells changed: 1,377
(foot) and 2,508 (cart), all inside the districts. The V6 fingerprints are
pinned too (`test_v6_fingerprints_recorded`).

## Budgets

TBD-BUDGETS

## Tests

TBD-TESTS

## Limits

TBD-LIMITS
