# Handoff: two maps and the campus detail pass

What changed, what is closed, what is still open, how it was checked, and what only a device can
tell. The details are in `docs/maps/README.md` (the two maps), `docs/campus/TERRAIN.md` (ground,
floors, stairs), `docs/campus/COVERAGE_MATRIX.md` (every inventory code) and
`docs/campus/README.md` (routes, gates, gaps).

## What changed

**Two maps.**
- Moonbrook College (`classic`), the 2.0 (10) map, is restored and plays through the shared
  pipeline. Its colliders match 2.0's (ray comparison), and its halls get exactly 2.0's target sets.
- Lakeside Campus (`reference_campus`) is the default.
- A registry (`CampusMaps`) replaces every single-map assumption.
- The map is a party setting (host picks, guests read-only, locked for the series) and a Practice
  choice (saved locally). It travels in the lobby bytes and in START (map id, data hash, hall
  version). A guest without the map, or with other data, ends with "update the game" and never
  falls back to its own default. Protocol 10.
- A compact Map row and a two-card chooser with in-engine previews.

**Real ground.**
- The campus stands on the USGS 3DEP 1 m bare-earth DEM (y = NAVD88 − 280.40 m).
- Water levels are measured or inferred, and say which.
- Each building has a floor level, with its foundation drawn where it shows and an exposed
  basement's windows where more than 1.9 m shows.
- Every entrance sits at its level:
  - 24 stairs, North Hall's front stair from the data;
  - 2 lower-level doors at grade;
  - 1 entrance reported (no stair: it would run into the neighbour).
- Stairs are real treads with rails, colliding as a ramp under the nosings (the motor is unchanged)
  and closed to carts.
- Everything that stood at y = 0 now stands on its ground or floor: spawns, pads, coins, gadgets,
  doors and thresholds, lamps, walls, fences, props, decks.
- The finish threshold and the safe room are measured from each door's own floor.

**Fixes found on the way.**
- The drawing kit ignored its floor lift for most geometry, so buildings were drawn at y = 0
  whatever their floor. That was invisible on a flat map, and on terrain they floated or sank. All
  kit geometry now honours the lift.
- The ground mesh was flat away from water. It now follows the terrain, and paving, lots and
  markings are draped on the ground mesh's own cells.

**Buildings.**
- The village homes are rebuilt from the photos: central bay with front gable and round vent,
  arched windows, shutters, corner boards, white-posted open porches with twin end gables.
- The bell tower is at its published 21.9 m, with a louvred speaker housing (no bells).
- North Hall has its white cupola over the crossing, and its portico floor is the hall floor at the
  head of the front stair.
- The administration hall stands on its raised basement: its floor is 0.6 m over the front walk, with
  steps up into the portico and at its other doors.
- The track and its sprint straight are a gravel bed, and the infield is a construction site (the
  October 2026 state).
- New data-driven facade features any building can use: `style.shutters`, `style.corner_boards`,
  part `arched_floor`, gable `roof.vent`, entrance `stair`, `floor_navd88`.

**Waters.** Bridge Pond is two lobes at their measured levels (one objective). The footbridge spans
level from its higher bank, and both its ends are graded to the deck (the DEM predates it, and left
its lower bank 0.17 m under the deck: more than a runner steps up).

**Lived-in detail.**
- 733 parked cars (a neutral original fleet of five kinds) in the lots' stalls, solid inside the
  play area.
- Bikes at the racks and at the village porches.
- Three hammocks, each between two trunks near a hall (requested scenery, placed plausibly).
- A woodland understory: about 1,230 shrubs, grass tufts and rocks under the woods, drawn only.
- Benches in the chapel garden's eight alcoves (the traced walls are "stepped into alcoves with
  benches"; placed at each alcove's back, facing the garden).
- Street furniture or a trunk the data places where a stair stands is left out (none in the current
  data).

**Routes.**
- The "three shortest anyway" fallback is gone. A hall starts a race only with a target set whose
  ideal run fits 85% of the 240 s round.
- West Hall: 3 sets (148–160 s). North Hall: none, so it starts no race and shows no start option.
  Its modelled stair and rooms stay.
- Recomputed on the final terrain, stairs and cars.

**Docs.**
- Maps (`docs/maps/README.md`), terrain (`docs/campus/TERRAIN.md`), the coverage matrix and this
  handoff are new.
- The campus README now says what the runtime does: the hall is chosen from the seed among
  race-start halls (nobody picks it), routes follow the strict rule, and the ground is terrain.

## Still open (from the evidence, not the code)

- **North Hall cannot start a race inside the timer.** That is the real scale against a 240 s round.
  Owner options are listed in `docs/campus/README.md`; none is taken.
- **Not modelled yet:**
  - the chapel atrium's axis (unresolved in the photos);
  - North Hall's photographed basement row (the DEM's bank is 12 m out from the wings);
  - Founders Hall's unfinished east half (drawn finished);
  - the Assembly site's steel frame;
  - the dining hall's 2024 addition and the apartments' 2024 expansion (no overhead image after
    2022);
  - furniture clusters at the dining plaza and the pond terraces;
  - shore retaining walls and the bridge pond's terraces as breaklines.
- **Inferred, and marked as inferred:**
  - Village Pond and Bridge Pond's lower lobe levels (both dug after the 2017–2020 survey);
  - floor levels from the grade round each building;
  - North Hall's stair counts.
- Every row of `COVERAGE_MATRIX.md` says what this pass did and what is still open. No row claims a
  survey.

## Tests

- **New:**
  - `test_maps`: registry; classic restoration against 2.0; settings; Practice; mismatch refused;
    map over the network, including reconnect; caches; the chooser editable and read-only;
  - `test_terrain`: terrain; stairs follow their nosings; walking a stair up, down and jumping from
    its landing; tile seams; the raised threshold.
- **Updated for real grades:** `test_dorms`, `test_coins`, `test_map`, `test_camping`,
  `test_campus_traversal`, `test_sim`, `test_pursuit`, `test_chase_balance`, `test_runner_pace`,
  `test_net`, `test_rules`, `test_routes_bots`. They now place and probe on the ground or floor,
  where they used to assume y = 0.
- Results and the commit they ran on: the final report in the session, and `TEST_REPORT.md` if
  updated.

## Performance

`docs/campus/README.md` (Performance). These are desktop container numbers (headless CPU and
llvmpipe draw counts), never a phone's. Device frame rate, GPU, memory pressure and heat are
unverified.

## Device testing needed

- iPhone and iPad: frame pacing on the campus with terrain and the parked fleet; memory; loading
  time; heat in a long session.
- The chooser on a real phone: touch, an Xbox or PlayStation controller, VoiceOver names, reduced
  motion.
- Two devices online: a Classic party, a campus party, an old build refused with "update the game",
  and a reconnect mid-round.

## Release

Nothing was uploaded and no version or build number changed: this pass doesn't authorise a release.
The code is ready for the repository's normal iOS build lane.
