# V4 media evidence (version 1.3)

Everything here was captured from the running game. Nothing is concept art,
an offline render or a mock-up.

**Platform for every file:**
- Desktop Linux, Godot 4.7.2, Mobile renderer on Mesa **llvmpipe**
  (software Vulkan) under Xvfb.
- Clips use Movie Maker with a fixed 30 fps game clock, so they play at
  normal game speed. Stills are taken from the running game.

These files show layout, framing, art and animation timing. They **cannot**
show frame rate or smoothness on a phone: llvmpipe takes far longer than a
frame budget, and the fixed clock hides that. There is **no device
footage**: no iPhone or iPad was available. None of the clips is
frame-interpolated or sped up.

**Versions compared:**
- **V3:** 1.2, commit `e39c98c`. The campus "before" is `edbac7c`, the last
  commit before the V4 art change.
- **V4:** the final app code `6677eb2` for the touch, match and screen
  stills and the clips. The campus and water "after" shots are from
  `0aa0476`, and the character shots from `20c0531`; that code is unchanged
  in `6677eb2`.

**How the stills were taken:**
- In-game stills are 1558×720. That is an iPhone 14 Pro screen in canvas
  units, with its touch sizing and safe area emulated (`--emulate-phone=1.85
  --emulate-safe=59,0,59,21`).
- They come from the game's own capture scenarios (`src/dev/capture.gd`):
  bot-driven practice rounds with fixed seeds, so V3 and V4 play the same
  start.
- `compare_*.jpg` puts V3 on the left and V4 on the right. Each side is also
  kept as `*_v3.jpg` / `*_v4.jpg`.
- Other players in lobbies are headless desktop clients in a LAN room (a
  development path; iOS uses Game Center).

## Match loading screen: [loading/](loading/README.md)

The owner's three-runner animation as the loading screen. Its README covers
iPhone, iPhone SE and iPad framing, the bundled loop played six times, and
loading into a round. It also has the previous droplet screen for comparison.

## Campus: `campus_before/`, `campus_after/`, `campus_compare/`

Seven identical route cameras on the V3 and V4 art (`src/dev_shots.gd
--route`): dorm door, quad path, pond, trees, garden, fountain and the way
back. Rounded broadleaf and layered pines replace stacked cones. The ground
has baked shade and lamp light. Buildings have framed windows, cornices and
porches.

## Waters: `waters_before/`, `waters_after/`, `waters_compare/`

One camera per water for all six (`--waters`): Founders' Fountain, Froggy
Pond, Splashdown Pool, Old Quarry Lagoon, Lily Basin and Boathouse Inlet.

## Characters: `characters/`

| File | What it shows |
|---|---|
| `parts_before.jpg`, `parts_after.jpg` | 12 matched close-ups (same cameras and pose): nightcap fold, cuffs, collar, sleeves, hands, robe sleeve, bob and bun hair. |
| `hero_before.jpg`, `hero_after.jpg` | The hero framing of one runner. |
| `group_after.jpg`, `outfits_after.jpg` | A group and the outfit range on the refined meshes. |
| `skins_campus_before.png`, `skins_campus_after.png` | Skin tones under campus night light, before and after the skin self-light. |
| `skins_studio_after.png` | The same tones under neutral light. |

## Touch controls: `touch/`

| File | What it shows |
|---|---|
| `compare_hud_runner.jpg` | Runner HUD at the head start. V4 sizes the stick and Jump in points, anchored to the safe area. |
| `compare_hud_patrol.jpg` | Night Watch on foot. In V4, Tag is the primary button, with Jump beside it. |
| `compare_cart_drive.jpg` | Driving a cart: Gas, Brake and Exit. |
| `layout_runner.jpg`, `layout_patrol.jpg` | **Settings › Controls › Edit layout** for each role. |
| `layout_dragged.jpg` | A control moved and resized in the editor. |
| `layout_try.jpg` | "Try it", which previews the edited layout. |

## Match: `match/`

| File | What it shows |
|---|---|
| `compare_reveal_runner.jpg`, `compare_reveal_patrol.jpg` | Role reveal. V4 states the goal and the capture rule and lists both teams. |
| `compare_water_entry.jpg`, `compare_water_recovery.jpg` | A splash, and resurfacing after it. |
| `runner_caught.jpg` | V4's capture contract: "Caught by … · back in 6…", "Your splashes are safe", and where you come back. Seed 12, where the bot runner is tagged at 68 s. |
| `runner_protected.jpg` | Back in play with "Protected". |
| `compare_home_safe.jpg` | Home safe: one HOME SAFE message, and the objective chip now says "Home safe". |
| `compare_results_runner.jpg` | Practice results: outcome and reason, your contribution, coins. |
| `runner_map.jpg`, `patrol_map.jpg` | The full map (tap the minimap). Opponents appear only as last seen. |
| `patrol_results.jpg` | Night Watch results. |
| `series_final.jpg`, `series_final_standings.jpg` | The final results of a three-round friend series: Round Wins, rounds, each round's winner and your role, Play again and Leave party. The rounds are recorded through `PartySeries`; two bot seats are relabelled as friends, so this is layout evidence, not network play. |

## Screens: `screens/`

| File | What it shows |
|---|---|
| `compare_home.jpg`, `compare_wardrobe.jpg` | Home and the wardrobe in the dorm room, with V4's rounded furniture. |
| `compare_creator.jpg` | The creator. The V3 side is `docs/media/v3/screens/creator.png`; it was captured at `001f274`, whose game code is identical to `e39c98c`. |
| `creator_outfit_tiles.jpg`, `creator_tab_face.jpg`, `creator_tab_hair.jpg`, `creator_tab_hat.jpg` | V4 creator tabs with thumbnails. |
| `compare_lobby_8p.jpg` | An 8-player party. V4 shows the host settings summary, the ready count, and Emote and Try moves. |

## Clips: `clips/`

| File | What it shows |
|---|---|
| `runner_splash_desktop.mp4` | Runner practice, bot-driven: reveal, head start, a splash and the run on (75 s). |
| `nightwatch_pursuit_desktop.mp4` | Night Watch practice, bot-driven: reveal, the cart, exit, and an on-foot chase with the Tag cue and a lunge (80 s). It ends before any tag lands; the pursuit harness in `test_pursuit` measures tags. |
| `lobby_emotes_desktop.mp4` | A LAN party of four (three headless desktop clients): the real Emote and Try moves buttons (Dance, Wave, Ha!, Sprint, Jump). |
| `round_transition_desktop.mp4` | The last 45 s of a two-player LAN series (one headless desktop guest). Round 1 ends with "Runners win!", then the results show the real "Next: round 2" button. The party room shows "Start round 2" once the guest is ready again. Round 2's role reveal follows: roles rotate, so the host is now a runner. Then the countdown and GO. Round 2 was prepared in 0.5 s, because the campus is kept from round 1, so its loading screen shows only briefly. |
| `startup_loading_v4_desktop.mp4` | Startup and loading on `20c0531`, before the loading animation: the droplet loading screen. It is kept as the "before" for [loading/](loading/README.md). |
