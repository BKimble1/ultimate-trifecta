# V8 evidence (1.6 build 6 → 1.7)

Every file here is the real game code rendered on **desktop Linux**: Godot
4.7.2's Mobile renderer on Mesa llvmpipe (software Vulkan) under Xvfb. The
"before" side is the build-6 code (commit `cb3c48a`, build 6's game plus
measurement hooks) in its own checkout; the "after" side is this branch.
Nothing is sped up, slowed down or frame-interpolated. **None of it is device
footage or frame-rate evidence**: llvmpipe draws one frame in about 0.2 s,
so the clips use Movie Maker's fixed clock and show poses and timing only.
The numbers behind these pictures are in [docs/v8/performance.md](../../v8/performance.md)
and [docs/v8/motion.md](../../v8/motion.md).

## Motion (`motion/`)

| File | What it is |
|---|---|
| `v8_motion_before.mp4`, `v8_motion_after.mp4` | `src/dev/motion_reel_v8.tscn` on each build: the motion-test scenarios (start, stop, reverse, 90° turn, sprint, running jump, Night Watch tag miss and hit, splash, cart) through the real interpolation → CharacterView path, each from behind at follow-camera distance and then from the side, on the game's night lighting over a 1 m grid. 960×540, Movie Maker at a fixed 30 fps, 47.2 s, 1,415 frames each. Recorded by `tools/capture_v8_motion.sh` |
| `stop_filmstrip.jpg` | The stop from a run, from the side, every 0.1 s (top: 1.6 (6), bottom: 1.7). Around +0.7–0.9 s, 1.7's front foot plants a stride ahead and then steps back beside the other; build 6 settles straight into idle |

At follow-camera distance most changes are small by design: the drive,
brake and turn-lead layers move the chest, head and arms by a few degrees.
Where a picture can't show a change, the probes in `docs/v8/data/` measure it.

## Characters (`characters/`)

`src/dev/character_lineup.tscn --lineup=custom --shots-file=shots_v8.json`,
900² per cell, on both builds, under the campus (moonlight) and dorm (warm
interior) light. Each JPEG pairs the same cell: 1.6 (6) on the left, 1.7 on
the right.

| File | Shows |
|---|---|
| `eyes_{campus,dorm}.jpg` | Eyes front and 3/4 on two skin tones: iris, pupil and catch-light outlines are rounder (more segments), and the highlights on the eye domes follow the surface (analytic normals) instead of its polygons |
| `lenses_and_materials_{campus,dorm}.jpg` | Goggle lenses front and 3/4 (a round highlight across each lens); the robe's satin lapels and sash; the varsity jacket's metal snaps and zip |
| `night_watch_and_distance_{campus,dorm}.jpg` | Night Watch badge, buttons and whistle (metal), the flashlight body; then a runner and the Night Watch at gameplay distance, where the two builds look the same: the finish changes are close-up detail |

Budget (`docs/v8/data/char_budget_{before,after}.json`): heaviest look 32,506 →
32,834 triangles (+328, the eyes only), still **7 draw calls** and one
material; GLB 12.12 → 12.36 MB.

## Campus (`campus/`)

`src/dev/campus_views.tscn`: fixed cameras on the real campus visuals at the
Standard preset, 1280×720, the same positions on both builds.

| File | Shows |
|---|---|
| `quad.jpg`, `dorm_entrance.jpg`, `dorm_doorway_close.jpg`, `water_*.jpg`, `chase_route.jpg`, `overview.jpg` | The campus is unchanged in layout, routes, openings and lighting. Mean per-pixel difference 0.01–1.3 of 255; the water views also differ because the water animates |
| `quad_far_paving_crop.jpg` | The far paving of `quad.jpg` at 2× (top 1.6, bottom 1.7): the cobble relief fades out where one stone is smaller than a pixel, so distant paving carries less sub-pixel noise (on a phone that noise is shimmer while the camera moves; a still can only show the noise, not the shimmer) |
