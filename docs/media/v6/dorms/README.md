# V6 dorms media

Every image here is the real game drawn by Godot 4.7.2's **Mobile renderer**
on Mesa **llvmpipe** (software Vulkan) under Xvfb on a shared desktop Linux
machine. They show layout, art, framing and what the rules do on screen.
**They are not frame-rate, smoothness, GPU or heat evidence**, and nothing
here was captured on an iPhone or iPad. Graphics preset **Standard** unless a
file says Battery Saver. The design and the numbers are in
[`docs/v6/dorms_notes.md`](../../../v6/dorms_notes.md).

Two sources:

- **Real practice rounds** (`round_*`): the game as shipped, `--capture=dorm
  --autoplay=runner --local-bot` (a bot plays your runner; five runner bots
  and two Night Watch bots play the rest), 1280×592 (a 19.5:9 phone canvas
  at reduced pixels, point scale 1.5), on a fixed game clock: every drawn
  frame advances a fixed number of 60 Hz simulation ticks (`--fixed-fps 10`,
  6 ticks a frame, for Puddlesworth; `--fixed-fps 3 --capture-steps=20` for
  the others, to draw fewer frames on a loaded machine). The simulation is
  the same either way; only how many frames are drawn differs. Each shot is
  taken at a moment chosen from game state (the reveal, the countdown, the
  first step outside the home dorm, a coin a few metres ahead, the full map,
  the way back with all three splashes, the doorway, home). Seeds pick the
  dorm: Lanternfield House 1, Puddlesworth Hall 2, Moonpenny Lodge 5.
- **Fixed views** (`exterior_*`, `room_*`, `compare/`): `src/dev_shots.tscn`
  (`--dorms`, `--dorm-area`, `--q0`) at 1558×720, scaled to 1280 wide: the
  same cameras rendered on the V5 release code and on V6 for before/after.

All files are JPEG (quality 84).

## Real rounds

| Files | Shows |
|---|---|
| `round_<dorm>_reveal.jpg` | The role reveal inside tonight's home dorm: "Home tonight: …", the runner line naming the dorm, tonight's waters, both teams; the common room behind the card |
| `round_<dorm>_countdown.jpg` | The 3 s countdown: the runner on its pad in the common room, the camera behind it looking at its exit |
| `round_<dorm>_departure.jpg`, `…_departure_b.jpg` | The first step outside: runners leaving through the doorway at GO (the opening, jambs and lintel are real colliders) and a moment later |
| `round_<dorm>_coin_route.jpg` | A gold coin still out a few metres ahead on the route (one MultiMesh for all of a round's coins) |
| `round_moonpenny_coin_1.jpg` | The local runner's first pickup: the coin chip counts 1 with a small "+1" |
| `round_<dorm>_map.jpg` | The full map: tonight's waters, the home dorm marked "Home" with its door wedges, the team list |
| `round_<dorm>_runner_caught.jpg`, `…_runner_protected.jpg` | A capture ("back in 6") and the protected return (after a splash it is near the last water; the HUD's home chip keeps pointing at the dorm) |
| `round_<dorm>_return_approach.jpg`, `…_return_doorway.jpg` | All three splashed: "Back inside …" with the distance, the runner coming to a home door, then in the doorway |
| `round_<dorm>_home.jpg`, `…_runner_home.jpg` | Home: the host's threshold crossing finished the runner ("HOME SAFE!", Home n/4), then the camera watches a teammate |
| `round_moonpenny_q0_*.jpg` | The Moonpenny round again on **Battery Saver** |

Not every moment happens in every run (the bot decides). Puddlesworth's
runner picked up no coin and was never caught; Lanternfield's was caught and
came home; Moonpenny's picked up a coin, was caught four times and was still
out when the fourth teammate got home (Runners win, 3:20), so the Moonpenny
round has no return or home shots — `moonpenny_exterior.jpg` and
`moonpenny_return.jpg` show its front door.

## Dorms (fixed views)

| Files | Shows |
|---|---|
| `<dorm>_exterior.jpg` | Each dorm from its forecourt: Puddlesworth Hall (brick, slate gable, dormers), Lanternfield House (plaster, teal roof, lit lantern cupola), Moonpenny Lodge (sage boards, deep-red gable with a round window); entrances lit, interiors visible through the doors, name boards, yard signs, benches, lamps |
| `<dorm>_return.jpg` | A stand-in runner (capsule) 1.5 m outside the front door, heading in, with the follow camera pulled in by the real colliders as in the game |
| `<dorm>_room.jpg` | Each common room from a corner: plank floor and rugs, wainscot, beams and pendants, fireplace, sofas along the back wall, windows with curtains, noticeboard and pigeonholes, the doors at the ends |

## compare/

| Files | Shows |
|---|---|
| `area_*_v5_v6.jpg` | The same camera on the V5 release (left) and V6 (right): Puddlesworth's front and west side (new side doors and aprons), the two new dorm sites from their approach and from above the yard, the south of the campus from above |
| `area_lanternfield_yard_standard_battery.jpg`, `area_moonpenny_approach_standard_battery.jpg` | V6 on Standard (left) and Battery Saver (right) |

Reproduce: `--capture=dorm` as above through `tools/capture_v5_media.sh`'s
`game()` helper (or `tools/gd.sh --path game --resolution 1280x592
--fixed-fps 3 -- --capture-steps=20 --capture=dorm --autoplay=runner
--local-bot --skip-onboarding --seed=N --capture-dir=DIR` under Xvfb);
`res://src/dev_shots.tscn -- OUTDIR --dorms --runner [--q0]` and
`-- OUTDIR --dorm-area [--q0]` (for the "before" side, the same command on
a checkout of the V5 release with this `dev_shots.gd`'s `--dorm-area`
cameras copied in). Engine counters for these views are in the notes.
