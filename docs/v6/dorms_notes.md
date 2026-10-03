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

Two tools, both on the real campus data:

- **`tools/route_analysis.gd`** — nav-grid path lengths. A trip is measured
  from the dorm's middle pad out through its best door, round the three
  waters in the best order (jump points), and back in through the best door
  to just inside. Writes `config/route_table.json` (per dorm: all twenty
  combinations, best order, length, the first water's distance, the
  measured bot time, the curated set).
- **`tools/dorm_balance.gd`** — the real `MatchSim`, Jolt physics and
  `BotBrain`, headless at a fixed 60 Hz, one seed per dorm × combination
  (60 of each mode):
  - *trip*: six runner bots, the Night Watch held in the shed; the median
    time from GO to home (six of six finished in every run). These feed
    `config/route_bot_times.json` → `"dorms"`.
  - *contact*: six runner bots against two Night Watch bots (carts from the
    shed), a whole round: **first contact** (a runner first spotted by the
    Night Watch), first capture, **the runners' first objective** (first
    stamp), **the Night Watch's first objective** (first arrival within 20 m
    of an active water), runners home, who won.

**Curation per dorm.** A combination is in a dorm's fair set when its route
is within ±16 % of the median of all 60 routes (602 m) *and* its measured
bot trip is within ±12 % of the median of all 60 trips. Each dorm keeps
15–16 of 20. What drops out is mostly the short trips, three waters bunched
on the dorm's side of campus: Fountain · Pond · Pool from every dorm;
Fountain · Pond · Quarry and Fountain · Quarry · Inlet from Puddlesworth and
Lanternfield; Fountain · Pool · Garden from Puddlesworth and Moonpenny;
Fountain · Pond · Inlet and Pond · Quarry · Inlet from Lanternfield (the west
waters are close to it); Fountain · Pool · Inlet from Moonpenny — and one
long one, Moonpenny's Pond · Garden · Inlet (697 m, across the campus).
`RulesLogic.curated_combos(dorm)` reads the set; the host draws tonight's
targets from the home dorm's.

<!-- balance:begin -->
Over each dorm's curated set (medians; seconds from GO):

| Home dorm | Curated | Route (median) | Bot trip, no pursuit | First contact | First capture | Runners' first stamp | Night Watch at a water | Runners won | First contact, all 20 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Puddlesworth Hall | 16/20 | 593 m | 120.7 s | 21.3 s | 36.1 s | 24.6 s | 15.2 s | 16/16 | 21.3 s |
| Lanternfield House | 15/20 | 630 m | 123.3 s | 27.7 s | 40.2 s | 22.6 s | 15.2 s | 13/15 | 27.8 s |
| Moonpenny Lodge | 16/20 | 616 m | 120.8 s | 21.8 s | 33.9 s | 21.3 s | 15.2 s | 13/16 | 21.8 s |

<details><summary>Every dorm × combination (60 rows)</summary>

**Puddlesworth Hall** (16 of 20 curated)

| Waters (best order) | Route | First water | Bot trip, no pursuit | First contact | First capture | First stamp | Watch at a water | Home | Won by | Curated |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| Pool · Fountain · Pond | 454 m | 134 m | 96.6 s (6/6) | 20.9 | 31.6 | 24.6 | 24.1 | 4/6 | Runners | no |
| Fountain · Quarry · Pond | 445 m | 80 m | 91.0 s (6/6) | 35.9 | 50.2 | 15.4 | 25.7 | 4/6 | Runners | no |
| Fountain · Garden · Pond | 570 m | 80 m | 120.5 s (6/6) | 20.3 | 33.2 | 14.0 | 10.8 | 4/6 | Runners | yes |
| Fountain · Inlet · Pond | 529 m | 80 m | 108.2 s (6/6) | 25.9 | 37.3 | 14.7 | 15.2 | 4/6 | Runners | yes |
| Fountain · Quarry · Pool | 565 m | 80 m | 111.6 s (6/6) | 31.8 | 48.6 | 14.0 | 27.1 | 4/6 | Runners | yes |
| Fountain · Garden · Pool | 438 m | 80 m | 91.4 s (6/6) | 20.3 | 30.9 | 13.9 | 10.8 | 4/6 | Runners | no |
| Fountain · Inlet · Pool | 539 m | 80 m | 108.0 s (6/6) | 42.7 | 56.9 | 14.0 | 61.5 | 4/6 | Runners | yes |
| Fountain · Garden · Quarry | 601 m | 80 m | 118.1 s (6/6) | 20.0 | 33.3 | 13.9 | 10.8 | 4/6 | Runners | yes |
| Fountain · Inlet · Quarry | 514 m | 80 m | 95.6 s (6/6) | 26.9 | 36.0 | 14.0 | 27.2 | 4/6 | Runners | no |
| Garden · Inlet · Fountain | 547 m | 221 m | 108.4 s (6/6) | 19.7 | 28.9 | 13.9 | 40.6 | 4/6 | Runners | yes |
| Pool · Quarry · Pond | 594 m | 134 m | 121.4 s (6/6) | 21.1 | 35.0 | 24.6 | 24.6 | 4/6 | Runners | yes |
| Pool · Garden · Pond | 591 m | 134 m | 121.1 s (6/6) | 20.9 | 39.3 | 24.7 | 10.8 | 4/6 | Runners | yes |
| Pool · Inlet · Pond | 637 m | 134 m | 124.6 s (6/6) | 21.5 | 65.8 | 24.5 | 15.2 | 4/6 | Runners | yes |
| Garden · Quarry · Pond | 619 m | 221 m | 120.8 s (6/6) | 24.1 | 32.3 | 27.5 | 10.8 | 4/6 | Runners | yes |
| Inlet · Quarry · Pond | 542 m | 238 m | 110.1 s (6/6) | 34.1 | 47.8 | 27.5 | 15.2 | 4/6 | Runners | yes |
| Garden · Inlet · Pond | 632 m | 221 m | 125.8 s (6/6) | 54.9 | 67.4 | 25.6 | 15.2 | 4/6 | Runners | yes |
| Quarry · Garden · Pool | 614 m | 224 m | 121.7 s (6/6) | 20.9 | 31.0 | 24.7 | 10.8 | 4/6 | Runners | yes |
| Quarry · Inlet · Pool | 613 m | 224 m | 120.9 s (6/6) | 20.9 | 34.3 | 24.6 | 15.2 | 4/6 | Runners | yes |
| Inlet · Garden · Pool | 566 m | 238 m | 116.3 s (6/6) | 20.9 | 30.3 | 24.7 | 15.2 | 4/6 | Runners | yes |
| Garden · Inlet · Quarry | 617 m | 221 m | 122.4 s (6/6) | 54.3 | 68.4 | 38.4 | 15.2 | 4/6 | Runners | yes |

**Lanternfield House** (15 of 20 curated)

| Waters (best order) | Route | First water | Bot trip, no pursuit | First contact | First capture | First stamp | Watch at a water | Home | Won by | Curated |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| Pond · Fountain · Pool | 483 m | 61 m | 95.9 s (6/6) | 58.3 | 73.9 | 11.2 | 46.3 | 4/6 | Runners | no |
| Pond · Quarry · Fountain | 436 m | 61 m | 86.5 s (6/6) | 36.7 | 48.6 | 11.0 | 48.4 | 4/6 | Runners | no |
| Pond · Garden · Fountain | 560 m | 61 m | 107.8 s (6/6) | 29.8 | 44.6 | 11.0 | 10.8 | 4/6 | Runners | yes |
| Pond · Inlet · Fountain | 520 m | 61 m | 96.0 s (6/6) | 24.3 | 33.6 | 11.0 | 44.9 | 4/6 | Runners | no |
| Quarry · Fountain · Pool | 642 m | 189 m | 127.2 s (6/6) | 40.1 | 51.2 | 23.3 | 48.6 | 4/6 | Runners | yes |
| Fountain · Garden · Pool | 582 m | 129 m | 114.2 s (6/6) | 29.1 | 40.2 | 22.6 | 10.8 | 3/6 | Night Watch | yes |
| Inlet · Pool · Fountain | 682 m | 260 m | 128.8 s (6/6) | 26.9 | 37.1 | 22.6 | 15.2 | 2/6 | Night Watch | yes |
| Quarry · Garden · Fountain | 615 m | 189 m | 118.9 s (6/6) | 29.4 | 40.4 | 23.3 | 10.8 | 4/6 | Runners | yes |
| Quarry · Inlet · Fountain | 528 m | 189 m | 100.1 s (6/6) | 29.3 | 43.5 | 23.3 | 15.2 | 3/6 | Night Watch | no |
| Inlet · Garden · Fountain | 623 m | 260 m | 120.2 s (6/6) | 25.5 | 39.4 | 23.2 | 15.2 | 4/6 | Runners | yes |
| Pond · Quarry · Pool | 623 m | 61 m | 122.8 s (6/6) | 27.7 | 34.9 | 11.2 | 32.9 | 4/6 | Runners | yes |
| Pond · Garden · Pool | 620 m | 61 m | 120.4 s (6/6) | 47.7 | 57.4 | 11.0 | 10.8 | 4/6 | Runners | yes |
| Pond · Inlet · Pool | 665 m | 61 m | 123.3 s (6/6) | 24.4 | 34.4 | 11.0 | 74.9 | 4/6 | Runners | yes |
| Pond · Quarry · Garden | 616 m | 61 m | 118.3 s (6/6) | 27.8 | 34.2 | 11.0 | 10.8 | 4/6 | Runners | yes |
| Pond · Quarry · Inlet | 507 m | 61 m | 100.3 s (6/6) | 27.7 | 34.2 | 11.0 | 32.3 | 3/6 | Night Watch | no |
| Pond · Inlet · Garden | 630 m | 61 m | 123.5 s (6/6) | 26.1 | 44.6 | 11.0 | 33.3 | 4/6 | Runners | yes |
| Quarry · Garden · Pool | 675 m | 189 m | 129.7 s (6/6) | 27.6 | 40.4 | 33.5 | 10.8 | 4/6 | Runners | yes |
| Quarry · Inlet · Pool | 674 m | 189 m | 130.7 s (6/6) | 27.5 | 33.6 | 33.1 | 15.2 | 4/6 | Runners | yes |
| Inlet · Garden · Pool | 683 m | 260 m | 132.6 s (6/6) | 40.9 | 49.6 | 38.1 | 15.2 | 4/6 | Runners | yes |
| Quarry · Inlet · Garden | 638 m | 189 m | 128.4 s (6/6) | 27.5 | 36.8 | 33.5 | 15.2 | 4/6 | Runners | yes |

**Moonpenny Lodge** (16 of 20 curated)

| Waters (best order) | Route | First water | Bot trip, no pursuit | First contact | First capture | First stamp | Watch at a water | Home | Won by | Curated |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| Pool · Fountain · Pond | 482 m | 66 m | 100.3 s (6/6) | 60.9 | 95.0 | 11.9 | 72.9 | 4/6 | Runners | no |
| Fountain · Quarry · Pond | 587 m | 125 m | 112.0 s (6/6) | 47.2 | 77.6 | 21.3 | 33.3 | 4/6 | Runners | yes |
| Garden · Fountain · Pond | 638 m | 189 m | 122.7 s (6/6) | 17.3 | 29.9 | 21.8 | 10.8 | 4/6 | Runners | yes |
| Fountain · Inlet · Pond | 671 m | 125 m | 123.9 s (6/6) | 33.5 | 45.3 | 21.3 | 15.2 | 4/6 | Runners | yes |
| Pool · Quarry · Fountain | 552 m | 66 m | 110.6 s (6/6) | 24.2 | 32.6 | 12.2 | 46.6 | 4/6 | Runners | yes |
| Pool · Garden · Fountain | 424 m | 66 m | 87.8 s (6/6) | 21.3 | 32.1 | 11.9 | 10.8 | 4/6 | Runners | no |
| Pool · Inlet · Fountain | 526 m | 66 m | 105.5 s (6/6) | 23.4 | 33.2 | 12.2 | 142.3 | 3/6 | Night Watch | no |
| Garden · Quarry · Fountain | 613 m | 189 m | 114.3 s (6/6) | 17.4 | 21.9 | 21.6 | 10.8 | 4/6 | Runners | yes |
| Fountain · Quarry · Inlet | 598 m | 125 m | 111.9 s (6/6) | 17.9 | 27.8 | 21.8 | 15.2 | 4/6 | Runners | yes |
| Garden · Inlet · Fountain | 558 m | 189 m | 110.5 s (6/6) | 17.4 | 30.1 | 21.6 | 15.2 | 3/6 | Night Watch | yes |
| Pool · Quarry · Pond | 623 m | 66 m | 121.4 s (6/6) | 25.6 | 39.9 | 12.0 | 60.2 | 3/6 | Night Watch | yes |
| Pool · Garden · Pond | 620 m | 66 m | 124.1 s (6/6) | 21.7 | 34.8 | 12.1 | 10.8 | 4/6 | Runners | yes |
| Pool · Inlet · Pond | 665 m | 66 m | 126.0 s (6/6) | 26.5 | 38.0 | 11.9 | -1.0 | 4/6 | Runners | yes |
| Garden · Quarry · Pond | 684 m | 189 m | 128.8 s (6/6) | 17.4 | 30.7 | 37.2 | 10.8 | 3/6 | Night Watch | yes |
| Inlet · Quarry · Pond | 670 m | 270 m | 127.5 s (6/6) | 17.8 | 28.9 | 39.3 | 15.2 | 4/6 | Runners | yes |
| Garden · Inlet · Pond | 697 m | 189 m | 137.2 s (6/6) | 17.4 | 30.8 | 37.3 | 15.2 | 4/6 | Runners | no |
| Pool · Garden · Quarry | 602 m | 66 m | 117.7 s (6/6) | 21.9 | 33.0 | 12.4 | 10.8 | 4/6 | Runners | yes |
| Pool · Inlet · Quarry | 602 m | 66 m | 120.3 s (6/6) | 24.0 | 44.9 | 11.8 | 41.3 | 4/6 | Runners | yes |
| Pool · Garden · Inlet | 537 m | 66 m | 112.0 s (6/6) | 23.5 | 36.3 | 12.0 | 40.3 | 4/6 | Runners | yes |
| Garden · Inlet · Quarry | 634 m | 189 m | 126.4 s (6/6) | 17.5 | 35.2 | 48.1 | 15.2 | 4/6 | Runners | yes |

</details>
<!-- balance:end -->

**Reading it.** Over the curated sets the three dorms give the same round:
route medians 593–630 m (within 6 %), no-pursuit bot trips 120.7–123.3 s,
the runners' first stamp 21–25 s after GO, and the Night Watch at an active
water first, at 15.2 s for every dorm (it starts at the shed whichever dorm
is home, so its first objective doesn't depend on the dorm). First contact
is 21–22 s at Puddlesworth and Moonpenny and about 6 s later at Lanternfield
(27.7 s): the watch's carts come from the shed on the north edge, east of
the middle (about 285 m from Lanternfield, 240 m from the other two); first
capture follows the same order (34–40 s). The outcome column is one seed per combination with
bots on both sides, and a round ends at the fourth runner home, so one
capture flips it — read it as a sanity check (no dorm is a walkover either
way: the Night Watch took 2 of 15 at Lanternfield and 3 of 16 at Moonpenny,
none at Puddlesworth), not as a win rate.

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

Engine counters from `dev_shots` (draw calls / primitives of one frame,
Mobile renderer on llvmpipe, 1558×720; relative numbers only, not a phone
measurement). "V5" is the V5 release code rendered with the same cameras.

**Matched views, Standard (V5 → V6).**

| View | V5 draws | V6 draws | V5 prims | V6 prims |
|---|---:|---:|---:|---:|
| route_1_dorm_door (start of the V5 route) | 94 | 94 | 245,181 | 260,741 |
| route_7_return (back at the dorm) | 62 | 63 | 170,127 | 196,465 |
| dorm_front | 51 | 52 | 129,552 | 157,028 |
| overview | 66 | 66 | 148,496 | 167,084 |
| area_puddlesworth_front | 45 | 45 | 112,261 | 140,671 |
| area_puddlesworth_west | 62 | 62 | 142,607 | 164,813 |
| area_lanternfield_approach | 33 | 38 | 107,592 | 133,594 |
| area_lanternfield_yard | 35 | 40 | 115,110 | 141,112 |
| area_moonpenny_approach | 40 | 47 | 84,449 | 108,065 |
| area_moonpenny_yard | 44 | 50 | 93,498 | 119,278 |
| area_south_overview | 60 | 60 | 131,162 | 144,714 |

**Battery Saver (V5 → V6):** route_1 54 → 54 draws (137,435 → 142,361
prims), route_7 37 → 37 (73,954 → 83,618); the dorm-area views on V6 are
26–40 draws, 51k–102k prims.

**The new views (V6 only, Standard / Battery Saver).**

<!-- budgets-dorms -->

What the numbers say: where the old campus is in view nothing changed in
draw calls (the dorm shells, interiors and porches are merged into the
campus chunks and the existing glow mesh; the yard props share the existing
kit meshes); primitives grow 10–25 % in views that include a dorm (interior
furniture, door surrounds, window frames). The new yards add 5–7 draw calls
where they are in view (their trees, lamps and benches). The heaviest new
view is a reveal camera inside a common room looking out through the front
door: 89–100 draws, within the range of the heaviest V5 views (route_1, 94),
because the campus behind the front wall is still in the frustum (there is
no occlusion culling). In a round the dorm adds three draw calls of its own
(the home doors' glow, the beacon, the coins' single MultiMesh).

**Preparation (cold build, this machine under load from three other jobs;
three runs).** The dorm steps of the staged campus build: windows 38–54 ms
over three jobs, entrances 15–18 ms, interiors 25–27 ms, yard signs < 1 ms;
the `home_coins` job ~2 ms. No dorm job is longer than ~20 ms, and the campus
is cached between rounds. Navigation phases are unchanged in cost
(~110 ms over six phases on both). Round setup on the host no longer builds
a campus layout to pick coins and check pads: `CampusLayout.round_data()`
(waters, spawns, coin spots) takes 0.14 ms the first time, where a full
`CampusLayout.new()` took 165–236 ms here, on the frame Start is pressed.

## Tests

New suites (all in `tools/run_tests.sh`):

- **`test_dorms`** (17 tests): three dorms with real doors and pads (faces,
  spacing, widths, room sizes, pads inside/apart/clear of doorways and
  furniture/facing an exit); colliders (a runner fits every doorway, the
  wall beside it is solid, a clear line through it, a lintel above, a
  ceiling, carts stopped, every pad sees its exit); navigation through every
  door (and no cart inside); spawn inside and **no tags before GO** (every
  dorm × 1/2/3 Night Watch); the **threshold contract at every door of every
  dorm** (standing inside, running out, pushing against the wall, back in
  without all stamps, finishing once through a named door); **other dorms
  never finish**; the swept threshold geometry (direction, width, height,
  step length, diagonal); a **40 m/s crossing between ticks counts on that
  tick** and a dive into the wall or a blocked line never does; **safe inside
  the home dorm**, tagged just outside; the **pre-first-stamp respawn inside
  the home dorm** (farthest pad, protected, also after out-of-bounds);
  **door jambs don't snag** (5 angles × 3 offsets × every door, plus sliding
  along the wall); **bots leave and come home through the doors**; the
  **round configuration** rotates the dorm (never twice in a row, all three
  in 30 rounds, targets from the dorm's set, coins, timing); **guests refuse
  another geometry** (version/fingerprint/unknown dorm → "Update the game")
  and repair bad pads/coins; **yard colliders** clear of new paths and doors;
  **the follow camera never clips** (1,560 poses); **two door campers can't
  block the way out**.
- **`test_coins`** (8 tests): candidate spots on routes and reachable from
  every dorm; seeded, spread, clear of home doors and active waters (360
  rounds); **first valid collector** (tie → lower slot, nearer wins, either
  role) and **no double credit** (walking over a taken coin, results rows,
  coin log); who can't collect (before GO, caught, home, in a cart); **bots
  collect and are marked**; **cancelled rounds** still report and pay
  nothing; the view dedups (a replayed event or a stale mask can't bring a
  coin back) and every round shares one mesh and material; **over the
  network**: the guest sees one event, its count, the mask; a replayed EVENTS
  packet is ignored; a **reconnect** gets the same configuration and the
  coin stays gone.

Changed deliberately (each commit says why): `test_sim` finishes by running
in through a door (`SimHarness.enter_door` / `cross_next_tick`) instead of
being placed in a finish box, the same-tick finish-beats-tag case starts in
the doorway, the pre-first-stamp return checks the home dorm's pads;
`test_camping`'s dorm test checks every dorm's doors (spacing and carts held
off from the roads); `test_campus_art` pins the V5 campus to the V4 values,
proves V6 identical outside the districts, pins V6, and checks the dressing
against every dorm's bot routes; `test_routes_bots` runs Puddlesworth's set
from inside the dorm and three combinations from each other dorm;
`test_net`'s scripted Night Watch stops beside the runner before tagging
(characters pass through each other, so a chaser that kept running overshot
and its lunge turned toward a runner directly behind it — which way depended
on millimetres of start position; with runners now starting inside a dorm it
stopped connecting).

TBD-TESTRUN

## Limits

- **No device measurement.** Draw calls and primitives are llvmpipe engine
  counters; frame time, GPU cost and heat on an iPhone are unmeasured.
- **Bot balance, not people.** The contact and first-objective numbers are
  one seed per dorm × combination with BotBrain on both sides; outcomes vary
  by seed. They show the dorms behave alike (first contact medians within a
  second or two of each other) and catch outliers; real playtests should
  confirm them.
- **The Night Watch spawn is the shed for every dorm.** Contact timings came
  out comparable, so per-dorm watch spawns weren't needed; the yards make the
  last stretch to Lanternfield and Moonpenny on foot, as at Puddlesworth.
- **Doorway glow and beacon are presentation.** The finish is the host's
  threshold test; a guest's prediction shows the runner stepping in a few
  ticks before the host's FINISH event arrives.
- **Furniture without colliders** (noticeboard, pigeonholes, pictures,
  plants, pendants) is mounted on walls, in corners or overhead; a runner
  hugging a wall can graze a board by a few centimetres.
- **Other dorms are plain buildings to the rules**: enterable, no safety, no
  finish. Their interiors are drawn like the home dorm's (warm), so the home
  dorm is told by its glowing doors, the beacon, the map and the reveal.
- **Coins are 8 per round** (`RulesConfig`), and both roles can collect; how
  many a typical round yields per player is in the balance runs only
  indirectly (bots detour within 7 m) — the commerce workstream tunes the
  economy from `coins_picked`.
