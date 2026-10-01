# V2 media evidence (version 1.1)

Everything here was captured from the running game. Nothing is concept art, an offline render or a mock-up.

**Platform for all files:** desktop Linux, Godot 4.7.2, Mobile renderer on Mesa **llvmpipe** (software Vulkan) under Xvfb, with a fixed frame clock (`--fixed-fps 60`, or Movie Maker at 60 fps). Graphics preset **Standard** (MSAA 2×, 3D at 100%) unless a file says Battery Saver. These files show layout, framing and art. They **cannot** show frame rate or device smoothness: llvmpipe needs far longer than 16.7 ms per frame, and the fixed clock hides that. There is **no physical-device footage** (no device was available).

Each PNG is lossless, at the exact size it was rendered, with a JSON file of the same name holding the render diagnostics for that frame (window size, canvas, 3D render size, MSAA, any SubViewport's render vs displayed size, draw calls, primitives) and the capture label.

Gameplay captures are bot-driven: the local player is controlled by the game's own bot (`--local-bot`) so a round can be captured unattended. Other players in lobbies are separate headless desktop client processes.

## Before / after pairs (gameplay evidence)

| View | Before: V1 (`654b0a8`) | After: V2 |
|---|---|---|
| Home screen | `before/home.png`<br>baseline 654b0a8 linux llvmpipe 2532x1170 | `after/home.png`<br>V2 14475d3 linux llvmpipe 2532x1170 (iPhone-6.1in-19.5x9-@3x layout check) |
| Wardrobe (character preview) | `before/wardrobe.png`<br>baseline 654b0a8 linux llvmpipe 2532x1170 | `after/wardrobe.png`<br>V2 14475d3 linux llvmpipe 2532x1170 (iPhone-6.1in-19.5x9-@3x layout check) |
| Lobby, 1 player | `before/lobby_1p.png`<br>baseline 654b0a8 linux llvmpipe 2532x1170 | `after/lobby_1p.png`<br>V2 4c89ed0 linux llvmpipe 2532x1170 (iPhone-6.1in-19.5x9-@3x layout check); other players are headless desktop clients |
| Lobby, full party (8) | `before/lobby_8p.png`<br>baseline 654b0a8 linux llvmpipe 2532x1170; 7 other players are headless desktop clients | `after/lobby_8p.png`<br>V2 4c89ed0 linux llvmpipe 2532x1170 (iPhone-6.1in-19.5x9-@3x layout check); other players are headless desktop clients |
| Runner outdoors | `before/runner_outdoors.png`<br>baseline 654b0a8 linux llvmpipe 1600x740; local player bot-driven (--local-bot) | `after/runner_outdoors.png`<br>V2 8e61029 linux llvmpipe 1600x740; Standard preset; local player bot-driven (--local-bot) |
| Water entry | `before/water_entry.png`<br>baseline 654b0a8 linux llvmpipe 1600x740; local player bot-driven (--local-bot) | `after/water_entry.png`<br>V2 8e61029 linux llvmpipe 1600x740; Standard preset; local player bot-driven (--local-bot) |
| Water recovery | `before/water_recovery.png`<br>baseline 654b0a8 linux llvmpipe 1600x740; local player bot-driven (--local-bot) | `after/water_recovery.png`<br>V2 8e61029 linux llvmpipe 1600x740; Standard preset; local player bot-driven (--local-bot) |
| Cart driving | `before/cart_drive.png`<br>baseline 654b0a8 linux llvmpipe 1600x740; local player bot-driven (--local-bot) | `after/cart_drive.png`<br>V2 babee2a linux llvmpipe 1600x740; Standard preset; local player bot-driven (--local-bot) |
| Canopy beside the camera | `before/foliage_near_camera.png`<br>baseline 654b0a8 linux llvmpipe 1600x740; local player bot-driven (--local-bot) | `after/foliage_near_camera.png`<br>V2 8e61029 linux llvmpipe 1600x740; Standard preset; local player bot-driven (--local-bot) |
| On-foot tag (lunge) | — | `after/tag_lunge.png`<br>V2 4c89ed0 linux llvmpipe 1280x720; Standard preset; local player bot-driven (--local-bot); Movie Maker |
| On-foot tag (capture) | — | `after/tag_capture.png`<br>V2 4c89ed0 linux llvmpipe 1280x720; Standard preset; local player bot-driven (--local-bot); Movie Maker |
| Results | `before/results.png`<br>baseline 654b0a8 linux llvmpipe 1600x740; local player bot-driven (--local-bot) | `after/results.png`<br>V2 5505024 linux llvmpipe 2532x1170 (iPhone-6.1in-19.5x9-@3x layout check); results of a recorded bot-driven practice round shown again |
| Results, scoreboard drawer open | — | `after/results_drawer.png`<br>V2 5505024 linux llvmpipe 2532x1170 (iPhone-6.1in-19.5x9-@3x layout check); results of a recorded bot-driven practice round shown again |

Notes on the pairs:
- **Same moments.** Gameplay pairs use the same seed (11) and the same capture triggers. Bots are deterministic per seed, so before and after show the same moment of the same round: for example `runner_outdoors` at 29 s, the first water entry, and `cart_drive` at 19.8 s.
- **Sizes.** V1 gameplay was captured at 1600×740. V2 gameplay is 1600×740 with the phone touch layout shown (`--emulate-phone`); the tag stills are 1280×720 frames from the Night Watch recording, without the touch overlay. Menus are 2532×1170 (an iPhone at @3x in landscape) in both versions.
- **Commits.** V2 files come from several commits, each named in its label: `14475d3` home and wardrobe, `8e61029` runner round, `babee2a` cart, `4c89ed0` lobby and tag, `5505024` results. Between them only interface and presentation code changed (see `git log`); rules, simulation, bot and network code are identical in all of them. For example, the canopy see-through (`d154d9d`) appears in the cart shot but not in the runner round.
- **Results.** The V2 results screen shows a round recorded headless by the same game code (commit `7e99cfa`, seed 11), re-displayed through the real `ResultsScreen` (`--capture=results`). The rendered V2 runner round was stopped before its results screen (CPU time), and the V1 results come from a rendered round with the same seed: the same outcome, 4/4 home with the local runner first at 2:03.
- **No V1 tag still.** With seed 11 the local Night Watch never tags anyone. A headless run of seed 11 shows no tag, and the simulation and bot code is identical in V1 and V2. V2's tag comes from seed 12, found by running rounds headless first.

## Art evidence (character test scene)

Rendered by `res://src/dev/character_lineup.tscn` at commit `8e61029` (the character asset and its shader are unchanged since), 1600×900, using the same `runner.glb`, shader and animation tree as the game. This is the character asset on a neutral floor, **not** gameplay.

| File | What it shows |
|---|---|
| `art/closeup.png` | Front three-quarter close-up: runner (striped pajamas, nightcap) and Night Watch (uniform, cap, flashlight) |
| `art/views.png` | Front, three-quarter, side and back of the runner; front and back of the Night Watch |
| `art/outfits.png`, `art/skins.png` | Every outfit, hat and shoe; the five skin tones |
| `art/faces.png` | Expression shapes: blink, squint, smile, open mouth, brows up, brows angry |
| `art/posesheet.png` | One frame from each of 30 animation clips (labels in `art/posesheet.txt`) |
| `art/transitions.png` | Locomotion and state transitions sampled over time |
| `art/cart.png` | Three carts with seated drivers at steer −1, 0, +1 (hands on the wheel) |

## Layout checks at device aspects

| Device aspect | Files | Labels |
|---|---|---|
| iPhone 19.5:9 @3x (2532×1170) | `layout/phone_howto.png`, `layout/phone_hud.png`, `layout/phone_online.png`, `layout/phone_online_gc_declined.png`, `layout/phone_settings.png` | V2 14475d3 linux llvmpipe 2532x1170 (iPhone-6.1in-19.5x9-@3x layout check); Game Center unavailable (desktop)<br>V2 5505024 linux llvmpipe 2532x1170 (iPhone-6.1in-19.5x9-@3x layout check); SIMULATED declined Game Center sign-in (--gc-sim)<br>V2 babee2a linux llvmpipe 2532x1170 (iPhone-6.1in-19.5x9-@3x layout check); local player bot-driven (--local-bot), touch layout shown |
| iPhone SE 16:9 @2x (1334×750) | `layout/se_home.png`, `layout/se_howto.png`, `layout/se_hud.png`, `layout/se_lobby_8p.png`, `layout/se_online.png`, `layout/se_results.png`, `layout/se_results_drawer.png`, `layout/se_settings.png` | V2 4c89ed0 linux llvmpipe 1334x750 (iPhone-SE-16x9-@2x layout check)<br>V2 4c89ed0 linux llvmpipe 1334x750 (iPhone-SE-16x9-@2x layout check); Game Center unavailable (desktop)<br>V2 4c89ed0 linux llvmpipe 1334x750 (iPhone-SE-16x9-@2x layout check); local player bot-driven (--local-bot), touch layout shown<br>V2 5505024 linux llvmpipe 1334x750 (iPhone-SE-16x9-@2x layout check); other players are headless desktop clients<br>V2 5505024 linux llvmpipe 1334x750 (iPhone-SE-16x9-@2x layout check); results of a recorded bot-driven practice round shown again |
| iPad 4:3 @2x (2048×1536) | `layout/ipad_home.png`, `layout/ipad_howto.png`, `layout/ipad_hud.png`, `layout/ipad_lobby_8p.png`, `layout/ipad_online.png`, `layout/ipad_results.png`, `layout/ipad_results_drawer.png`, `layout/ipad_settings.png` | V2 4c89ed0 linux llvmpipe 2048x1536 (iPad-4x3-@2x layout check)<br>V2 4c89ed0 linux llvmpipe 2048x1536 (iPad-4x3-@2x layout check); Game Center unavailable (desktop)<br>V2 4c89ed0 linux llvmpipe 2048x1536 (iPad-4x3-@2x layout check); local player bot-driven (--local-bot), touch layout shown<br>V2 4c89ed0 linux llvmpipe 2048x1536 (iPad-4x3-@2x layout check); other players are headless desktop clients<br>V2 5505024 linux llvmpipe 2048x1536 (iPad-4x3-@2x layout check); results of a recorded bot-driven practice round shown again |

The phone (19.5:9) home, lobby and results screens are the `after/` files above. Every layout check was reviewed by eye. The problems they exposed are fixed and listed in TEST_REPORT.md (V2.7).

## Recordings

| File | Platform / build | What it shows |
|---|---|---|
| `night_watch_v2_desktop.mp4` | V2 `4c89ed0`, desktop Linux, llvmpipe, Movie Maker 60 fps (normal game speed), 1280×720, Standard | 82 s as the Night Watch, **bot-driven** (`--local-bot`, seed 12): release, cart entry, driving, hop out, an on-foot chase (the runner dives away) and a tag at 1:16. No touch overlay. |
| `runner_v2_desktop.mp4` | V2 `4c89ed0`, same platform and settings | 50 s as a runner, **bot-driven** (`--local-bot`, seed 11): countdown and head start, running and turns along paths and a road, the splash into Old Quarry Lagoon at 0:44 (ring, foam burst, "stamped") and the recovery. No touch overlay. |
| `runner_v1_baseline_desktop.mp4` | **V1** `654b0a8`, same platform | 35.9 s of the same seed-11 runner round, **bot-driven**. The recording was stopped by a task time limit, and the recorder cropped the HUD edges (1600×740 window, 1280×720 movie). |
| `ios_simulator_ci_run14.jpg` | **iOS Simulator** (iPhone Air, iOS 26.2) on the GitHub `macos-26` runner, unsigned build **1.1 (14)** of `4c89ed0`, x86_64 under Rosetta with the OpenGL ES fallback | Screenshots 30 s apart, rotated to landscape: boot splash with the V2 character, about 5 minutes of loading, then the match (role reveal, 4:00 HUD, objective chips, minimap). It shows the iOS build launching and reaching a match. **It is not** evidence of performance. |
| `standard_runner_same_moment.png`, `battery_saver_runner.png` | V2 `4c89ed0`, 1600×740 | The same moment (t = 20.03 s) in each graphics preset; the JSON files hold the measured settings. |

A Movie Maker recording plays at true game speed (one rendered frame per 1/60 s of game time), so starts, stops, turns and camera motion appear as the game produces them. It still says nothing about how smoothly an iPhone renders the same scene.
