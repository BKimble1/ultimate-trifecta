# V6 character evidence

Captures and data for [docs/v6/character_notes.md](../../../v6/character_notes.md).

**Platform.** Desktop Linux. Stills: Godot 4.7.2's Mobile renderer on Mesa
llvmpipe (software Vulkan) under Xvfb, from `game/src/dev/character_lineup.tscn`
(`--lineup=<mode> --light=studio|campus|dorm`) and `game/src/dev/thumb_sheet.tscn`.
Window sizes are in each picture's label (1558×720 for lineups, 900×720 for
the grids of close-ups, 1280×720 for the thumbnails; grids are downscaled
into JPEG). Motion numbers: headless engine frames on a fixed 60 Hz clock
(`motion_probe.tscn`, `foot_trail.tscn`). "V5" is the unchanged asset and
code at `2314331`, rendered with the same V6 lineup tool, cameras and light.

**Lights.** *studio*: the lineup's neutral light. *campus*: the game's own
night (`EnvFactory` environment and moon) on a lawn. *dorm*: the real
`DormStage` room behind the menus (home, Locker/wardrobe, lobby), with the
characters' indoor rim light.

**What this cannot show.** Frame rate, pacing, heat or feel on an iPhone;
Game Center links. Characters are posed (`AnimationPlayer` seek) or driven
by the scripted mini-motor (`game/tests/motion_rig.gd`), not a live round.

| File | What it shows |
|---|---|
| `closeup_studio.jpg`, `closeup_campus.jpg`, `closeup_dorm.jpg` | V5 above, V6 below: runner and Night Watch faces (lash lines, ears, nose, mouth, mittens; skin warmth at night) |
| `skintones_campus.jpg`, `skintones_dorm.jpg`, `skintones_studio.jpg` | V5 above, V6 below: all eight skin tones, head and shoulders, same outfit and camera |
| `hero_campus.jpg`, `views_dorm.jpg` | V5 / V6: the icon hero; front, 3/4, side, back and the Night Watch |
| `parts_studio.jpg`, `hathair_studio.jpg` | V5 / V6: the V4 part close-ups (nightcap, collar, cuff and hand, robe hem, shoes, hair edges) and every V5 hat × hairstyle |
| `shop_outfits_campus.jpg`, `shop_outfits_dorm.jpg` | the six Shop outfits, front and back |
| `season_outfits_campus.jpg`, `season_outfits_dorm.jpg` | the four Season 1 outfits, front and back |
| `season_hats_dorm.jpg`, `season_shoes_campus.jpg` | the four Season 1 hats on every hairstyle (front/back), the two Season 1 shoes |
| `outfit_poses_campus.jpg` | every V6 outfit in idle, run, sprint and an emote |
| `emotes_campus.jpg` | the four new emotes, a frame every 0.2 s |
| `thumbnails.jpg` | the real cached item thumbnails, rendered through `Portraits` (what Locker/Shop cards show) |
| `foot_trail.jpg` | top-down planted-foot trails through a 90° turn and a 180° reversal, V5 behaviour (lock off) vs V6 foot lock |

## Data

| File | What |
|---|---|
| `data/probe_v5.json`, `data/probe_v6.json` | `motion_probe.tscn` on V5 (`2314331`) and V6: pops, planted-foot slide, head lag and hat motion per scenario |
| `data/foot_trail.json` | both feet per frame in `turn90` and `reverse`, lock off and on |
| `data/clipcheck_v6.json` | `tools/character/clip_check.py` on all 46 clips |
