# V7 character evidence

Captures and data for [docs/v7/character_notes.md](../../../v7/character_notes.md).

**Renderer.** Desktop Linux: Godot 4.7.2's Mobile renderer on Mesa llvmpipe
(software Vulkan) under Xvfb. Not an iPhone; nothing here is frame-rate,
GPU-cost, heat or feel evidence.

**Resolution.** Stills: `game/src/dev/character_lineup.tscn --lineup=custom`
at a 900×900 window per cell, grids downscaled to 1200 px wide JPEG. Reel:
`--lineup=reel` at 1280×720, recorded with Godot's Movie Maker on a fixed
30 fps clock (every frame rendered however long it takes), each side scaled
to 960×540 in the MP4.

**Lighting.** *dorm*: the real `DormStage` room behind home, the Locker and
the lobby, with the characters' warm indoor rim light. *campus*: the game's
own night (`EnvFactory` environment and moon) with the cool outdoor rim
light; the reel hides the lawn so the splash sinks as into water.

**Before/after.** "Before" is the unchanged asset and code at `d2d0749`
(this branch's base), extracted and imported separately, rendered with the
same lineup tool, shot lists, cameras and light as "after". Characters are
posed with `AnimationPlayer` seeks (stills) or driven by the motion tests'
mini-motor through `CharacterView.apply_state` (reel), not a live round.

| File | What it shows |
|---|---|
| `goggles_closeups_dorm.jpg`, `goggles_closeups_campus.jpg` | Swim cap + goggles close: front, 3/4, side, rear 3/4, from above, low 3/4; skin tones 2 and 7. Before: the strap is a tilted ring floating off the cap and crossing below the lenses, the lenses two buttons with no bridge, brow fragments through the cap, a stepped cap edge. After: paired cups with gasket frames and tinted lenses, a bridge, clips, a strap lying on the cap; brows below a smooth cap edge. |
| `goggles_views_dorm.jpg`, `goggles_views_campus.jpg` | Front, 3/4, side and rear at head-and-shoulders distance, tones 1, 4, 7, 8 |
| `goggles_poses_dorm.jpg`, `goggles_poses_campus.jpg` | Idle, run, sprint, turn, jump rise and apex, hard landing, dive, splash, splash dive, cheer, dance, laugh, stargaze, shush, victory lap |
| `goggles_faces_dorm.jpg`, `goggles_faces_campus.jpg` | Every face × brow preset (classic/bright/sleepy × arched/flat/raised) on tones 1-8 and four hairstyles (hidden by the cap) |
| `goggles_reel_before_after.mp4` | 13 s side by side: start, 90° turn, running jump, splash, emote (`tests/motion_rig.gd` scenarios), the camera circling the head once (front, side, back, side) |
| `goggles_reel_after.gif`, `goggles_reel_strip_after.jpg`, `goggles_reel_strip_before.jpg` | The same run: a small GIF of "after", and a frame every 0.25 s of each |
| `refinements_dorm.jpg`, `refinements_campus.jpg` | Face front, 3/4 (bob over the ear) and side (ear), eyes close, pajama cuff and mitten, bare wrist and mitten, collar and buttons, robe, nightcap, beanie, bunny slippers and pajama hem, high-tops and trouser hem |
| `cuffs_all_outfits_dorm.jpg` | Every outfit's sleeve end and mitten (the camera on the right hand) and the Night Watch: open hems instead of a torus round a flat disc |

## Data

| File | What |
|---|---|
| `data/budget.json` | `src/dev/char_budget.tscn` on both trees: every runner look's LOD0 triangles (heaviest, default, swim + goggles, Night Watch), draw calls and materials of the heaviest look, material variants, per-part triangles, and the portrait renderer timed on twelve looks (`--portraits`) |
| `data/clipcheck_v7.json` | `tools/character/clip_check.py` on all 46 clips, with the new goggles column |
