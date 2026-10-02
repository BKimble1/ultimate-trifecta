# V5 motion evidence

Matched before/after captures and clips for [docs/v5/motion_notes.md](../../../v5/motion_notes.md)
and the defect register [docs/v5/motion_register.md](../../../v5/motion_register.md).

**Platform and clock.** Desktop Linux. Stills: Godot 4.7.2's Mobile
renderer on Mesa llvmpipe (software Vulkan) under Xvfb, 1558×720.
Clips: Godot Movie Maker on a **fixed 30 fps clock**, 960×540, encoded to
H.264; every frame is a real engine frame, nothing is interpolated, sped up
or slowed down. "Before" is the V4 code (`dcebf4e`) run from a temporary
worktree with the same dev scenes, cameras and light.

**What this cannot show.** Frame rate, frame pacing, touch latency, heat
or feel on an iPhone; Game Center links. llvmpipe frame times mean nothing
for a phone. The clips drive the character with a scripted 60 Hz
mini-motor (`game/tests/motion_rig.gd`, rule speeds and accelerations) on
an empty lawn, not a live round; the splash shows the body only (no water
or spray), and the cart sequence places a cart mesh under the seat.

## Stills (before above or left, after below or right)

| File | What it shows |
|---|---|
| `views_compare.jpg` | `--lineup=views`: front, 3/4, side, back; Night Watch front/back (idle pose) |
| `closeup_compare.jpg` | `--lineup=closeup`: faces |
| `posesheet_compare.jpg` | `--lineup=posesheet`: one pose per clip at fixed times (V5 clips changed) |
| `arms_compare.jpg` | full-resolution cells from the pose sheets: air apex, air fall, celebrate, arrive, yawn, cheer (V4: arms inside the head); tag wind-up, lunge (V5 leaps), cart hop in, drive, hop out, wave |
| `transitions_compare.jpg` | `--lineup=transitions`: idle → walk → run → sprint → jump → land → stop → emote, a frame every 0.4 s |
| `steps_compare.jpg` | `--lineup=steps`: start (0.5 s), stop (1.4 s), start, 180° reversal (2.6 s), a frame every 0.1 s, run on the spot with the sim's accelerations |
| `hathair_compare.jpg` | `--lineup=hathair`: party hat, headphones and crown × tuft, bob, curls, buns, front and back (V4: curls through the crown band, the headphone band sunk into the curls) |
| `menuidle_compare.jpg` | `--lineup=menuidle`: a menu character, a frame every 1.2 s for 24 s (V5: restrained fidgets, blinks) |

## Clips (fixed 30 fps clock)

| File | What it shows |
|---|---|
| `runner_v4_v5.mp4` | V4 left, V5 right: start, stop, 180° reversal, 90° turn, running jump, dive, splash, emote and walk away |
| `watch_v4_v5.mp4` | V4 left, V5 right: tag miss and tag hit while running, cart hop in / drive / hop out, Night Watch run |
| `menu_idle_v5.mp4` | V5 menu idle for 24 s |

## Data

`data/` holds the raw numbers behind the register: `probe_v4.json` /
`probe_v5.json` (`src/dev/motion_probe.tscn`), `netmotion_v4.json` /
`netmotion_v5.json` (`src/dev/net_motion_probe.tscn`),
`clipcheck_v4.json` / `clipcheck_v5.json` (`tools/character/clip_check.py`).
