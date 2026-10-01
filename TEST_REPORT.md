# Test report: Ultimate Trifecta

This report records what was actually run, where, and what each result proves. Version 1.1 (V2) is reported first; the V1 (1.0) report follows unchanged as the baseline. The evidence comes from these sources, each labelled by what it is:

| Label | What it is | What it can prove |
|---|---|---|
| **Headless sim** | The real `MatchSim`/physics/rules code running headless (Godot 4.7.2, Linux), with scripted inputs or bots | Rules, ordering, validation, routes, bot behaviour |
| **Unit (presentation)** | Headless tests of pure presentation logic: `TouchRouter`, render-state capture/interpolation, camera damping, springs, the dorm stage, profile migration | Touch ownership/cancellation, interpolation and discontinuities, frame-rate independence, in-place lobby updates |
| **Loopback net** | Host and up to 7 `NetSession` clients in one process over an in-memory transport with simulated latency, jitter and loss | Protocol, prediction/reconciliation, lag compensation, reconnect, host loss |
| **Desktop UDP** | Separate Godot processes (1 host + N clients) on one Linux machine over real UDP (ENet), each shaping its outbound traffic, playing full rounds with automation input | Multi-process networking across full rounds; *not* iPhones, *not* the Game Center transport |
| **Desktop render** | The game rendered by Godot's Mobile renderer on Mesa **llvmpipe** (software Vulkan) under Xvfb, at device resolutions, with a fixed frame clock (`--fixed-fps 60`, or Movie Maker) | Layout, framing, art, render-path dimensions (render size vs displayed size, MSAA, scale) and engine counters (draw calls, primitives). **Not** frame rate, frame pacing, GPU cost or device smoothness |
| **CI iOS** | GitHub Actions `macos-26` runner: Xcode project export, unsigned arm64 device archive, x86_64 Simulator build and run | That the iOS project compiles and links for device and launches in the Simulator; *not* device performance |

**Not done: no physical iPhone or iPad was available, so nothing in V1 or V2 has been device-tested.** Touch feel, frame rate, thermals and Game Center on hardware are unverified; see V2 section 8.

# V2 (version 1.1)

Code commits `e628130` … `5505024`, then the owner's app icon (`b56a82a`; the final app code) and documentation-only commits on `claude/ultimate-trifecta-testflight-oie9r7`. Implementation notes: [docs/V2_NOTES.md](docs/V2_NOTES.md). Media index: [docs/media/v2/README.md](docs/media/v2/README.md).

## V2.1 Automated tests

`tools/run_tests.sh` on the final code (`5505024`): **76 tests, 914 checks, 0 failures** (`docs/test-data/full_test_run.txt`). V1 had 53 tests and 802 checks. CI runs the same suite on every push. All V1 suites still pass unchanged: the rules, simulation, camping, chase-balance, route and network tests did not need edits, which is the regression check that movement speeds, timers, tag reach, routes and win conditions were not changed.

New V2 suites (behaviour, not style constants):

| Suite | Tests | What they exercise |
|---|---|---|
| `test_touch_input` | 13 | Walk + camera drag + jump with three fingers at once; a second finger in the stick zone never moves the player (it becomes a camera drag); a finger that slides off its button keeps it; jump then dive within one tick become two queued presses; leaving the cart while holding Gas releases it; pause while moving cancels everything and stale drags are ignored; a fresh touch after an interruption works; radial dead zone with sneak magnitude kept and no diagonal boost; sprint hysteresis (on 0.88, off 0.76); dynamic stick spawn clamped on screen, fixed-stick option; reserved HUD regions (pause, minimap) never start a stick or camera; camera drag is a displacement in unscaled pixels converted to points, never multiplied by frame time; a controller taking over, or focus loss, releases stick, gas and sprint, and touch works again afterwards |
| `test_motion` | 6 | Render state is interpolated between the last two sim ticks (position and yaw); a respawn after capture is not interpolated (no slide across the map); splash resurfacing, cart entry/exit and a large reconnect jump snap and reset history; camera damping reaches the same value after 1 s at 30 and at 120 fps; the head spring stays finite, bounded by its maximum lag and settles on target for steps from 1/120 s up to a 0.5 s hitch; character acceleration uses the previous frame's velocity (the V1 `prev_vel` bug) |
| `test_lobby` | 2 | Real lobby traffic over the loopback rig: the dorm stage is updated by player identity through a guest dropping and rejoining (everyone else keeps the same character instance and mark); an outfit change is applied in place; eight players get eight distinct marks, are all inside the camera frustum, and no face is covered on screen by a nearer character's head or cap |
| `test_profile` | 2 | A V1-era profile keeps uid, coins, level, stats, paid match IDs, wardrobe, equipped outfit and old settings, and new settings get defaults; all 108 outfit × hat × shoe combinations map onto parts of the new character, show the right parts (hoods hide hats, the Night Watch always wears the uniform) and round-trip the 5-byte network encoding |

## V2.2 Render path, measured (G1)

`game/src/dev/diag.gd` (`--diag`, `--diag-report=path`; excluded from iOS exports) records what reaches the screen. Every capture PNG has the snapshot next to it as JSON. Desktop render, llvmpipe; window at phone resolution 2532×1170 (canvas 1558×720, 1.625 px per canvas unit) or 1600×740 for gameplay.

| View | Build | 3D rendered at | SubViewport render → displayed | MSAA | Draw calls | Primitives |
|---|---|---|---|---|---|---|
| Home | V1 `654b0a8` | 2532×1170 (root) | none | 2× | 179 | 140 103 |
| Home | V2 `14475d3` | 2532×1170 (root) | none | 2× | 34 | 40 569 |
| Wardrobe / character preview | V1 | **400×470 shown at 650×764 (0.615×: a 1.63× upscale)** | stretched `SubViewportContainer` | 2× in root, **off in the preview** | 182 | 153 539 |
| Wardrobe | V2 `14475d3` | 2532×1170 (root, the character is in the dorm stage) | none | 2× | 48 | 42 326 |
| Lobby, 1 player | V1 | **990×436 shown at 1609×708 (1.63× upscale)** | stretched `SubViewportContainer` | off in the preview | 54 | 12 712 |
| Lobby, 1 player | V2 `4c89ed0` | 2532×1170 (root) | none | 2× | 82 | 44 566 |
| Lobby, 8 players | V1 | 990×436 shown at 1609×708 | stretched `SubViewportContainer` | off in the preview | 291 | 87 982 |
| Lobby, 8 players | V2 `4c89ed0` | 2532×1170 (root) | none | 2× | 166 | 272 632 |
| Runner outdoors (play shot 2) | V1 | 1600×740 (root) | none | 2× | 267 | 212 115 |
| Runner outdoors (play shot 2) | V2 `8e61029` | 1600×740 (root) | none | 2× | 158 | 246 658 |
| Cart driving | V1 | 1600×740 (root) | none | 2× | 525 | 323 870 |
| Cart driving | V2 `babee2a` | 1600×740 (root) | none | 2× | 234 | 261 019 |

What this established:
- **The V1 blur was a sizing bug, measured.** The `Preview3D.new(Vector2i(480, 300))` size in the source was never used: the stretched container sized the SubViewport in canvas units, so on a 3× phone the character preview rendered at 61.5% of its displayed size, upscaled bilinearly and without MSAA. V2 renders every menu character in the root viewport at native resolution. The inline `Preview3D` that remains renders at displayed pixel size and is drawn 1:1.
- **The main game view was already native** in V1 (root render = window, scale 1.0). Its softness came from content: flat-shaded low-poly characters, washed-out sRGB vertex colours (fixed late in V1) and the canopy dither. V2 changes the content (authored character, materials, water, foliage) rather than the render size.
- **Draw calls and geometry.** Home and wardrobe dropped from 179 and 182 draw calls to 34 and 48, because the campus fly-over and the stretched preview were replaced by one merged room. The one-player lobby draws more than V1's small preview card (54 → 82). The full lobby draws fewer calls (291 → 166) but more triangles (88k → 273k), because eight detailed characters replace primitives. In gameplay, draw calls fell from 267 to 158 (runner) and from 525 to 234 (cart view, where each rebuilt cart is about 7 calls instead of about 25), with similar geometry: 212k → 247k triangles for the runner view and 324k → 261k for the cart view. Distant characters use the imported LODs. Whether 273k triangles in the full lobby is comfortable on an iPhone 14-class GPU still needs a device measurement.
- **Frame times in these JSON files are not measurements.** Under `--fixed-fps 60` and Movie Maker the engine advances exactly 16.67 ms per frame regardless of how long llvmpipe takes, so the `frame_ms` percentiles are always 16.67. They are recorded only to show that the capture clock was fixed.

Presets (Settings → Graphics; never switched automatically), measured from the diag JSON of two captures: same seed, same moment (t = 20.03 s), commit `4c89ed0`, window 1600×740 (`docs/media/v2/standard_runner_same_moment.*` and `battery_saver_runner.*`):

| Measured in the diag JSON | Standard | Battery Saver |
|---|---|---|
| 3D render size | 1600×740 (100%) | 1280×592 (80%, bilinear; UI stays native) |
| MSAA | 2× | 2× |
| Moon shadow | 2 splits to 70 m, 2048 atlas | 1 orthographic split to 30 m, 1024 atlas |
| Campus meshes casting shadows | 49 of 56 | 0 of 56 (characters and carts still cast) |
| Glow | on | off |
| Mesh LOD threshold | 1.0 | 3.0 |
| Draw calls / primitives in that frame | 175 / 279 798 | 147 / 110 383 |
| Frame cap | 60 fps on iOS | 30 fps on iOS |

The frame cap is applied only on iOS (`OS.has_feature("mobile")`), so it cannot be observed on desktop. The preset is stored in the profile and applied at startup and whenever it changes.

## V2.3 Visual evidence

Index with platform, commit and settings for every file: [docs/media/v2/README.md](docs/media/v2/README.md). Before/after pairs are lossless PNGs at the size they were rendered; **art evidence** (the character lineup sheets) is kept separate from **gameplay evidence** (the running game). There is no device evidence.

| Before (V1 `654b0a8`) | After (V2) | What changed |
|---|---|---|
| `before/home.png` | `after/home.png` | Campus fly-over behind a column of five equally loud buttons, no character → your character standing front three-quarter in a native-resolution dorm common room; one primary action (Play with Friends), Practice as a quiet second, Outfit and Settings as icons |
| `before/wardrobe.png` | `after/wardrobe.png` (+ `art/closeup.png`) | 1.63×-upscaled preview → the same character rendered natively; close-up shows eyes, brows, nose, mouth, cap, collar, buttons and cuffs |
| `before/lobby_1p.png`, `before/lobby_8p.png` | `after/lobby_1p.png`, `after/lobby_8p.png` | Static roster beside a blurry preview → party on the stage, compact party list, one primary action; 8 players readable with a 34-character name |
| `before/runner_outdoors.png` | `after/runner_outdoors.png` | Primitive runner, compass strip, large labels → authored runner, timer/home chip, objective chips with bearing and distance, compact minimap |
| `before/water_entry.png`, `before/water_recovery.png` | `after/water_entry.png`, `after/water_recovery.png` | Glowing, washed-out surface → blue/teal water with a slim active ring, splash ripple and foam shoreline |
| `before/cart_drive.png` | `after/cart_drive.png` | Boxy cart half hidden by a canopy → merged-mesh cart with tyres, seat and a steering wheel the driver holds; the canopy in front of your cart is cut away cleanly |
| `before/foliage_near_camera.png` | `after/foliage_near_camera.png` | A canopy beside the camera drawn with the speckled 4×4 screen-door dither → the same canopy solid, parted away from the camera, no dither |
| (no tag shot in the V1 capture round) | `after/tag_lunge.png` | On-foot tag lunge |
| `before/results.png` | `after/results.png`, `after/results_drawer.png` | Full-screen eight-row table and reward list over a flat background → outcome, your round, rewards and one primary action on a sheet beside your character (cheering or shrugging); the full scoreboard is a drawer |

Layout checks at other device aspects (`docs/media/v2/layout/`): iPhone 19.5:9 @3x (2532×1170), iPhone SE 16:9 @2x (1334×750) and iPad 4:3 @2x (2048×1536) for home, Play with Friends, Settings, lobby with 8 players and a long name, results with the scoreboard drawer open, and the match HUD with touch controls. Each layout check was reviewed by eye. Problems found and fixed are in V2.7: the Play with Friends sheet overflowing, How to Play over the room, the scoreboard covering the results sheet, and a face hidden in the full lobby.

**Normal-speed recordings.** All are desktop renders recorded with Movie Maker at 60 fps, so one frame is 1/60 s of game time and the clips play at true game speed. The local player is bot-driven, and each clip says so in a burned-in label:
- `docs/media/v2/night_watch_v2_desktop.mp4`: V2 `4c89ed0`, 82 s, 1280×720, seed 12. Release, cart entry, driving, hopping out, an on-foot chase (the runner dives away) and a tag at 1:16.
- `docs/media/v2/runner_v2_desktop.mp4`: V2 `4c89ed0`, 50 s, 1280×720, seed 11. Countdown and head start, running and turns along paths and a road, the splash into Old Quarry Lagoon at 0:44 and the recovery.
- `docs/media/v2/runner_v1_baseline_desktop.mp4`: V1 `654b0a8`, 35.9 s, seed 11. The recording was stopped by a task time limit, and the HUD edges are cropped by the recorder (1600×740 window, 1280×720 movie).

These clips show animation, camera behaviour and the art in motion. **They cannot show device smoothness**: llvmpipe takes far longer than 16.7 ms per frame, and Movie Maker hides that. There is no recording of real touch input; that needs a device.

## V2.4 Functional checks from the brief

| Check | How | Result |
|---|---|---|
| No lost stick ownership, stuck gas/brake, stolen action touches, camera gestures firing actions | `test_touch_input` (13 cases above) | Pass (unit). Feel on glass unverified |
| Touch ↔ controller switching in play | `test_touch_input::test_controller_takeover_and_focus_loss_release_touch_intent`; prompts switch via `Controls.device_changed` (V1 behaviour kept) | Pass (unit). Needs a real controller on device |
| No progress loss, duplicate stamps/rewards, invalid captures, changed win conditions, rematch leaks | V1 `test_sim`, `test_rules`, `test_net` suites, unchanged and passing | Pass |
| Event feedback once (no duplicate splashes, haptics, stamp toasts after reconciliation) | Splash/capture feedback is driven only by host events, deduplicated by event ID (`NetSession`, V1 `test_duplicate_reordered_inputs_and_late_snapshots`); footsteps are generated by the render-time animation phase, never by prediction replay; splash and capture haptics are called only from those event handlers (button-press haptics are local input feedback) | Pass by construction + V1 tests; not separately measured on device |
| Lobby ready/outfit updates keep animation; all eight readable | `test_lobby`; lobby captures at three aspects | Pass |
| Safe areas, long names, drawers, controls on small phones and iPad | Layout captures at 19.5:9, 16:9 and 4:3 (above); safe margins come from `DisplayServer.get_display_safe_area()` | Pass on desktop renders at the three aspects after the V2.7 fixes. Names longer than the cell are shortened with an ellipsis (e.g. "Bartholomew Sn…"). Safe-area insets on a Dynamic Island device are unverified (desktop has none) |
| Standard and Battery Saver persist and match behaviour | Setting saved in the profile and applied at startup (`Save._apply_settings`); Battery Saver diag above | Pass on desktop: the measured settings differ as listed in V2.2. On device, the effect on frame time and battery is unmeasured. |
| Existing cosmetics and saves still load | `test_profile` | Pass |
| Routes, timers, speeds, tag reach unchanged | No rule, simulation, bot, network or map-layout code changed (`git diff 654b0a8 -- game/src/config game/src/core game/src/sim game/src/bots game/src/net game/src/map/campus_layout.gd game/src/map/nav_grid.gd` is empty); route and chase tests pass unchanged | Pass |

## V2.5 Networking on V2

V2 changed no simulation, protocol or network code (`git diff 654b0a8 -- game/src/net game/src/sim game/src/core game/src/bots game/src/config` is empty). What changed is presentation: render-time interpolation of the tick states the client already had, and explicit snaps on discontinuities. The network tests therefore check that the presentation work did not disturb prediction, reconciliation or events.

**Loopback net** (`test_net`, from the final test run on `5505024`, `docs/test-data/full_test_run.txt`). RTT is the simulated round trip. "Client RTT est." is the client's own smoothed estimate, which varies between runs: the 300 ms case read 309 ms in an earlier run of the same test.

| Case | Simulated network | Client RTT est. | Snapshots | Correction avg / max | Corrections > 25 cm | Teammate interpolation error | Missing reliable events |
|---|---|---|---|---|---|---|---|
| `rtt100` | 100 ms RTT, ±8 ms jitter | 97 ms | 379 | 3 mm / 0.18 m | 0 | 0.03 m | 0 |
| `rtt150_loss5` | 150 ms RTT, ±15 ms, 5% loss | 148 ms | 361 | 3 mm / 0.23 m | 0 | 0.02 m | 0 |
| `rtt300_loss10` | 300 ms RTT, ±30 ms, 10% loss | 231 ms | 332 | 4 mm / 0.34 m | 1 | 0.03 m | 0 |
| 8 humans (host + 7 clients) | 120 ms RTT, 3% loss | n/a | 2038 total | worst client avg 2 mm | n/a | n/a | 0 |
| Client Night Watch tag | 150 ms RTT | n/a | n/a | n/a | n/a | n/a | Tag **captured** with 9 ticks (150 ms) of lag |

**Desktop UDP soak on V2** (`tools/net_soak.sh`, final code `5505024`): separate Godot processes on one Linux machine over real UDP (ENet). Each process shapes its own outbound traffic, and every human slot is a separate process playing with automation input (`--local-bot`). Reports are in `docs/test-data/v2_net_soak_*`.

**8 humans: host + 7 clients, 60 ms ±10 ms one-way, 3% loss each way (about 150 ms RTT).** One complete 240 s round; the Night Watch won with 0/4 runners home.

| process | round | outcome | home | RTT est. | snapshots | corr. avg | corr. max | fps | packets sent | shaper drops | host starved/skipped |
|---|---|---|---|---|---|---|---|---|---|---|---|
| client1 | 1 | Night Watch win | 0/4 | 156 ms | 4768 | 1.3 mm | 0.30 m | 60 | 15341 | 454 |  |
| client2 | 1 | Night Watch win | 0/4 | 159 ms | 4794 | 1.7 mm | 0.54 m | 60 | 15359 | 460 |  |
| client3 | 1 | Night Watch win | 0/4 | 153 ms | 4778 | 2.0 mm | 0.80 m | 60 | 15337 | 468 |  |
| client4 | 1 | Night Watch win | 0/4 | 152 ms | 4794 | 1.7 mm | 1.56 m | 60 | 15341 | 501 |  |
| client5 | 1 | Night Watch win | 0/4 | 153 ms | 4799 | 1.5 mm | 0.67 m | 60 | 15349 | 447 |  |
| client6 | 1 | Night Watch win | 0/4 | 156 ms | 4774 | 1.3 mm | 0.26 m | 60 | 15351 | 449 |  |
| client7 | 1 | Night Watch win | 0/4 | 154 ms | 4811 | 0.9 mm | 0.30 m | 60 | 15355 | 483 |  |
| host | 1 | Night Watch win | 0/4 | - | 0 | host (no prediction) |  | 60 | 38859 | 1137 | 0 starved / 11 skipped ticks (all clients) |

**High latency: host + 3 clients, 130 ms ±25 ms one-way, 8% loss each way (about 300 ms RTT).** One complete round; the Night Watch won with 3/4 home.

| process | round | outcome | home | RTT est. | snapshots | corr. avg | corr. max | fps | packets sent | shaper drops | host starved/skipped |
|---|---|---|---|---|---|---|---|---|---|---|---|
| client1 | 1 | Night Watch win | 3/4 | 298 ms | 4552 | 2.3 mm | 0.31 m | 60 | 15357 | 1193 |  |
| client2 | 1 | Night Watch win | 3/4 | 285 ms | 4510 | 2.5 mm | 2.07 m | 60 | 15366 | 1250 |  |
| client3 | 1 | Night Watch win | 3/4 | 299 ms | 4539 | 4.2 mm | 1.86 m | 60 | 15369 | 1162 |  |
| host | 1 | Night Watch win | 3/4 | - | 0 | host (no prediction) |  | 60 | 16725 | 1296 | 55 starved / 4 skipped ticks (all clients) |

These match V1 under the same conditions (V1: average corrections of 0.4–2.5 mm, worst single correction 2.15 m at about 300 ms, host starved ≤ 0.3% of ticks), so the presentation changes did not degrade prediction or reconciliation. The round outcomes differ from V1's runs because the client processes' timing differs from run to run. The column meanings are explained under 3b below.

What these runs do **not** cover: iPhones, the Game Center (`GKMatch`) transport, cellular networks, and reconnect on a device. They remain on the device checklist (V2.8).


## V2.6 iOS build (CI iOS)

Same lane as V1 (`.github/workflows/ios.yml`, GitHub Actions `macos-26`, Xcode 26.6 (17F113), iOS SDK 26.5). `MARKETING_VERSION` is now **1.1**. Without App Store Connect access, the unsigned build number is the run number, so it is above V1's last build, 1.0 (10).

| Run | Commit | Tests | Unsigned arm64 device archive | Simulator (iPhone Air, iOS 26.2) | Signed archive / upload |
|---|---|---|---|---|---|
| #11 | `e628130` (character asset) | ✅ | ✅ | ✅ | ⏸ skipped (no secrets) |
| #12 | `0539d7c` (V2 UI, controls, motion, world) | ✅ | ✅ `1.1 (12)`, 263 MB `.app` | ✅ boot splash with the V2 character, loading, match role reveal and HUD; no crash report | ⏸ skipped |
| #13 | `e3d5c85` | ✅ | ✅ | ✅ | ⏸ skipped |
| #14 | `4c89ed0` | ✅ | ✅ `1.1 (14)`, arm64, 263 MB, `com.apple.developer.game-center`, `PrivacyInfo.xcprivacy` | ✅ same sequence (`docs/media/v2/ios_simulator_ci_run14.jpg`); cold launch still running at the check; "no crash report" | ⏸ skipped |
| #15 | `36f4cea` (docs) | cancelled when #16 was pushed (the workflow cancels in-progress runs on the same branch) | | | |
| #16 | `b56a82a` (final app code: `5505024` + owner-supplied app icon) | ✅ | ✅ `1.1 (16)`, arm64, 269 MB, Game Center entitlement, `PrivacyInfo.xcprivacy` | ✅ boot splash, loading, match reveal and HUD (`docs/media/v2/ios_simulator_ci_run16.jpg`); no crash report | ⏸ skipped (no secrets) |

As in V1, the Simulator runs the x86_64 slice under Rosetta with an OpenGL ES fallback and produces roughly one frame every several seconds. These runs show that the build installs, launches and reaches a match. They say nothing about load time or frame rate on an iPhone.


## V2.7 Fixed during V2 validation

Found by reviewing captures and tests, then fixed:
- **Steering sign.** The steer-left/right clips, the wheel rotation and the sim's steering sign disagreed, so the driver could turn the wheel against the cart. One convention now: positive steer is a right turn, the wheel rotates −50° × steer, and the clips are mapped to match (`art/cart.png`).
- **Arm raises had the wrong sign** in the clip authoring convention, so raise poses (jump, fall, splash, celebrate, wave, cheer and others) moved the arms the wrong way. Fixed in `tools/character/anims.py`, over-rotation reduced, and re-baked (`art/posesheet.png`).
- **Animation loop seam.** Clips were 1.033 s instead of 1.0 s because keys started at frame 1, which made locomotion hitch at the loop. Keys now start at frame 0.
- **Foot IK out of reach.** Locomotion foot targets were further than the legs could reach. Stride sweep and stance timing were reduced and the pelvis drop raised; playback rate still comes from the clip's metres per cycle, so feet do not slide.
- **Inside-out and misrotated geometry.** The cart steering wheel was mirrored with a negative scale and rendered inside out; it is now wound correctly. The new dorm doors were placed with a wrong yaw formula; corrected.
- **Lobby framing.** On a square or 4:3 viewport only 7 of 8 characters were in view (`test_lobby` failed). The lobby camera now frames the group in the space left of the party panel for any aspect.
- **A hidden face in the full lobby.** The 2532×1170 eight-player capture showed the back-centre player directly behind the local player, with their face covered by the local player's nightcap. The lobby camera is now 3.1 m up instead of 2.5 m, and the back mark is 0.2 m further back. `test_lobby` now checks on screen that no face is behind a nearer head or cap; on the old layout it fails with "p7 behind p0".
- **Scoreboard over the results sheet.** In the 16:9 and 4:3 captures, the scoreboard drawer opened at the left edge at its natural width and covered "Your round" and Play again. It is now a centred sheet over a dimmed backdrop, sized to the screen, with its own Close button; Back closes it first. Also fixed in the lobby: "1 bots" now reads "1 bot".
- **Name labels over the HUD.** A bot right next to the camera had its fixed-size name label float up over the timer (water-entry capture). Labels are now hidden within 3.5 m of the camera.
- **A canopy hid the player's own cart.** With the dither gone, the V2 cart capture showed a tree fully covering the cart, because the camera correctly ignores canopies and the parting only reaches 2.6 m. Canopy between the camera and the followed character is now cut away in a circle around it, with a clean edge and in the camera pass only (`after/cart_drive.png`, same moment as `before/cart_drive.png`).
- **Menu layout.** The wardrobe sheet slid with its container on entry (transitions are now fade + scale only); lobby labels overlapped and "(you)" was truncated; icon buttons stretched; the Play with Friends sheet ran off the bottom when the Game Center card was shown (now scrolls, inert controls hidden); How to Play drew text straight over the 3D room (now on a sheet with "Got it" in the header).

## V2.8 Not verified (exact remaining device checks)

Nothing below can be established on this machine. Each needs a signed build on hardware.
- [ ] **Frame rate and pacing.** A 15–20 minute session (several rounds) on an iPhone 14-class device at Standard, with Xcode Instruments (Game Performance / Metal System Trace): frame-time distribution, missed presentation intervals, hitches, memory growth, thermal state. Repeat for Battery Saver on an A12/A13 device. Profile the host with the full roster and bots, and a client, separating CPU (sim + bots) from GPU.
- [ ] **Touch on glass.** Dynamic and fixed stick feel, the 0.88/0.76 edge-sprint thresholds, camera drag speed (0.0065 rad per point), three-finger play, button sizes at Small/Medium/Large on a small iPhone, mirrored layout, haptics.
- [ ] **Safe areas** on Dynamic Island iPhones and iPad (insets are zero on desktop).
- [ ] **4× MSAA.** Standard uses 2×; whether 4× fits the frame budget needs GPU measurements on device.
- [ ] **Game Center on two or more iPhones** (unchanged from V1): code room, friend invite, full round with cart, chase, tag, splash and finish, rematch, host leaving.
- [ ] **Controllers on device**, connecting and disconnecting mid-match.
- [ ] **TestFlight install** of a signed build (blocked on App Store Connect access; see TESTFLIGHT_RELEASE.md).

## V2.9 Known limitations

- **iOS share sheet.** The room code has a Copy button; a native share sheet is not implemented.
- **World polish is partial.** Dorm doors (with trim, transom and step), benches, lamps, tree canopies, carts and water were refined. Window frames, roof edges, curbs and path edges, the fountain, the pool edge and the cart shed are unchanged from V1.
- **Canopy see-through inside a large tree.** When the follow camera ends up inside a big canopy (Night Watch movie, about 0:30), the see-through shows as a round window around the cart. The player stays visible, but it reads like a porthole. A softer treatment needs tuning on a device.
- **Overlapping distant labels.** Two characters at similar distance can still have overlapping name labels; there is no label decluttering.
- **Character LODs** are Godot's automatic import LODs and have not been checked on device.
- All V1 limitations below still apply (host trust, code-room timing, desktop LAN for development only, lighting needing a real-screen check, plugin export log noise, A12 minimum).

# V1 (version 1.0), kept as the baseline

The sections below are the V1 report as written for commit `b2d4844` / `f1c7579`. Where V2 changed behaviour, the V2 sections above take precedence.

## 1. Automated tests

Run them with `tools/run_tests.sh`. CI runs the same suite on every push (job "Rules, simulation and network tests").

The latest full local run, on the final commit `b2d4844`: **53 tests, 802 checks, 0 failures** (`docs/test-data/full_test_run.txt`). The CI test job runs the same suite on every push.

| Suite | Tests | What they exercise (behaviour, not constants) |
|---|---|---|
| `test_rules` | 11 | All 20 three-of-six combinations and their 6 orders; route-table fairness; seeded target pick with no immediate repeat; fair role rotation and preferences; respawn pad choice; tag geometry; rewards (unique captures, no idle-survival reward, practice ×0.5); level curve; input wire format; reward ledger paid once per match ID |
| `test_sim` | 19 | Every curated combo × all 6 orders; duplicate and inactive splashes; automatic resurfacing (no hiding in water); 6 s capture timing with stamps kept and role kept; return to the dorm before the first stamp and to the 3rd water after three; ~2 s protection; tag reach, cooldown and walls (no tag through a wall); tag role/state validation; **same-tick finish beats tag**; 4th runner ends the round immediately; timeout and deadline-tick finish; cart seat race and wrong-role entry; cart drive, safe exit and post-exit tag lockout; bump stumble without chain or capture; gadget single use and ownership; splash bomb slows a cart briefly; reconnect resume and reservation expiry; out-of-bounds recovery grants nothing; finished runner out of play; movement numbers; spotted cue needs line of sight |
| `test_camping` | 3 | Two campers at any water's exits/pads cannot cover every exit; the respawn pad is ≥ 15 m from both (worst case measured 20.7 m); an in-play respawn lands away from two campers; dorm doors are ≥ 15 m apart (18 m); carts driven flat out at the dorm from 4 directions are stopped by bollards 17–54 m from the nearest door |
| `test_net` | 13 | Snapshot size and round-trip; lobby join/ready/start; match sync at 100 ms, 150 ms + 5% loss, and 300 ms + 10% loss RTT; capture reaching the client, and client-patrol lag-compensated tags; clean and silent host loss; reconnect resumes slot and progress; late join spectates then plays; rematch cleanup; duplicate/reordered inputs and late snapshots; 8 humans online with no bots |
| `test_routes_bots` | 1 | Six runner bots, using the same movement code and inputs as players, complete every curated route with no pursuit |
| `test_chase_balance` | 2 | On open ground a Night Watch bot runs down a fleeing runner bot from 8 m (at least 3 of 4 trials within 25 s); a runner sprint still opens the gap and the Night Watch closes it again afterwards |
| `test_smoke`, `test_compile` | 2 | Campus layout and builder load; every script compiles |

## 2. Route fairness (headless sim, bots)

- **Method.** Six runner bots, using the same input limits as players, run each of the 14 curated combinations with the Night Watch held idle. Raw output: `docs/test-data/route_bot_times_run.txt`.
- **Result.** **84 / 84** bot runs finished.
  - Trip times ranged **103–132 s**, with a median of **117.5 s** (final run).
  - The per-combination medians are within ±12% of each other.
- **Excluded combinations.** The 6 other combinations were left out because their estimated or measured trips fell outside that band.
- **Expected human times.** Bots take near-optimal lines with sprint management. First-time human players should land in the requested 2–3 minutes: rough estimate 2:10–2:40, which still needs **device playtests** to confirm. That leaves 1–2 minutes of the 4-minute round for chases and captures.
- **With pursuit.** In the full-round capture, bot runners played against both Night Watch bots on the final tuning. The first runner got home at 2:03 and the fourth at 2:36; along the way the Night Watch caught three runners once each, and one runner ended the round with only 2/3 stamps (`docs/media/shots/results_runners_win.jpg`).

## 3. Networking

### 3a. Loopback net (in-process clients, simulated network)

The in-process network tests produce `NETSTAT` lines. Raw output: `docs/test-data/net_tests.txt`.

| Case | Simulated network | Client RTT estimate | Snapshots | Correction avg / max | Corrections > 25 cm | Teammate interpolation error | Missing reliable events |
|---|---|---|---|---|---|---|---|
| `rtt100` | 100 ms RTT, ±8 ms jitter | 139 ms | 379 | 2 mm / 0.15 m | 0 | 0.05 m | 0 |
| `rtt150_loss5` | 150 ms RTT, ±15 ms, 5% loss | 168 ms | 359 | 3 mm / 0.31 m | 2 | 0.01 m | 0 |
| `rtt300_loss10` | 300 ms RTT, ±30 ms, 10% loss | 302 ms | 336 | 3 mm / 0.15 m | 0 | 0.03 m | 0 |
| 8 humans (host + 7 clients) | 120 ms RTT, ±10 ms, 3% loss | n/a | 2038 total | worst client avg 3 mm; largest single correction 0.22 m | 0 | n/a | 0 |
| Client Night Watch tag | 150 ms RTT | n/a | n/a | n/a | n/a | n/a | Tag **captured** with 13 ticks (217 ms) of measured lag; compensation is capped at 150 ms |

- **Correction** is the distance the client's predicted position moves when a server snapshot is reconciled. Legitimate teleports (respawn, resurfacing, cart exit) are excluded.
- **Lag compensation.** A client playing Night Watch at 150 ms RTT tagged a running runner, and the host validated the tag against the runner's position as that client saw it.
- **Reliable events.** No reliable event went missing.
- **Snapshot size.** Snapshots are under 900 bytes for an 8-player room.

### 3b. Desktop UDP (separate processes, real sockets)

`tools/net_soak.sh` starts one host and N client processes, each with its own profile, outbound latency/jitter/loss shaping, and automation input. Every human slot is a separate process; no bots fill human slots. The rows below are copied from the JSON reports in `docs/test-data/`.

**Gameplay code `d89a78a` (the last gameplay commit; the final commit `b2d4844` only defers the title background): host + 3 clients, 60 ms ±10 ms one-way, 3% loss each way (≈150 ms RTT).** `docs/test-data/net_soak_3c_60ms_0.03/`. A complete round; runners won 4/4.

| process | round | outcome | home | RTT est. | snapshots | corr. avg | corr. max | fps | packets sent | shaper drops | host starved/skipped |
|---|---|---|---|---|---|---|---|---|---|---|---|
| client1 | 1 | Runners win | 4/4 | 154 ms | 4665 | 1.2 mm | 0.41 m | 60 | 14874 | 472 |  |
| client2 | 1 | Runners win | 4/4 | 154 ms | 4668 | 2.1 mm | 1.19 m | 60 | 14877 | 451 |  |
| client3 | 1 | Runners win | 4/4 | 152 ms | 4676 | 1.7 mm | 0.36 m | 60 | 14879 | 454 |  |
| host | 1 | Runners win | 4/4 | - | 0 | host (no prediction) |  | 60 | 16135 | 437 | 24 starved / 3 skipped ticks (all clients) |

**8 humans: host + 7 clients, 60 ms ±10 ms one-way per direction, 3% loss each way (≈150 ms RTT).** `docs/test-data/net_soak_7c_60ms_0.03/`. One complete 240 s round; the Night Watch won with 1 runner home.

| process | round | outcome | home | RTT est. | snapshots | corr. avg | corr. max | fps | packets sent | shaper drops | host starved/skipped |
|---|---|---|---|---|---|---|---|---|---|---|---|
| client1 | 1 | Night Watch win | 1/4 | 151 ms | 4810 | 0.6 mm | 0.08 m | 60 | 15298 | 500 |  |
| client2 | 1 | Night Watch win | 1/4 | 153 ms | 4791 | 1.3 mm | 0.32 m | 60 | 15303 | 445 |  |
| client3 | 1 | Night Watch win | 1/4 | 150 ms | 4780 | 0.4 mm | 0.27 m | 60 | 15285 | 441 |  |
| client4 | 1 | Night Watch win | 1/4 | 159 ms | 4808 | 1.0 mm | 0.31 m | 60 | 15300 | 482 |  |
| client5 | 1 | Night Watch win | 1/4 | 154 ms | 4764 | 0.7 mm | 0.31 m | 60 | 15339 | 458 |  |
| client6 | 1 | Night Watch win | 1/4 | 159 ms | 4813 | 1.5 mm | 0.63 m | 60 | 15317 | 465 |  |
| client7 | 1 | Night Watch win | 1/4 | 156 ms | 4778 | 1.7 mm | 0.63 m | 60 | 15290 | 427 |  |
| host | 1 | Night Watch win | 1/4 | - | 0 | host (no prediction) |  | 60 | 39709 | 1114 | 37 starved / 5 skipped ticks (all clients) |

**High latency: host + 3 clients, 130 ms ±25 ms one-way, 8% loss each way (≈300 ms RTT).** `docs/test-data/net_soak_3c_130ms_0.08/`. Runners won 4/4 before time ran out.

| process | round | outcome | home | RTT est. | snapshots | corr. avg | corr. max | fps | packets sent | shaper drops | host starved/skipped |
|---|---|---|---|---|---|---|---|---|---|---|---|
| client1 | 1 | Runners win | 4/4 | 299 ms | 2612 | 1.3 mm | 0.30 m | 60 | 8689 | 692 |  |
| client2 | 1 | Runners win | 4/4 | 278 ms | 2532 | 2.5 mm | 2.05 m | 60 | 8681 | 689 |  |
| client3 | 1 | Runners win | 4/4 | 312 ms | 2544 | 2.0 mm | 2.15 m | 60 | 8678 | 678 |  |
| host | 1 | Runners win | 4/4 | - | 0 | host (no prediction) |  | 60 | 9466 | 733 | 61 starved / 7 skipped ticks (all clients) |

**Baseline: host + 2 clients, 40 ms one-way, no loss.** `docs/test-data/net_soak_2c_40ms_0.0/` (earlier build). One complete 240 s round.

| process | round | outcome | home | RTT est. | snapshots | corr. avg | corr. max | fps | packets sent | shaper drops | host starved/skipped |
|---|---|---|---|---|---|---|---|---|---|---|---|
| client1 | 1 | Night Watch win | 3/4 | 117 ms | 4970 | 0.6 mm | 0.93 m | 60 | 15369 | 0 |  |
| client2 | 1 | Night Watch win | 3/4 | 117 ms | 4967 | 3.9 mm | 5.57 m | 60 | 15367 | 0 |  |
| host | 1 | Night Watch win | 3/4 | - | 0 | host (no prediction) |  | 60 | 11019 | 0 | 31 starved / 4 skipped ticks (all clients) |

How to read these tables:
- "Corr. avg" is the mean distance the client's own predicted position moved when reconciled, so lower is better. "Corr. max" is the single worst correction in the round.
- Rare large corrections (≈2 m at 300 ms RTT with 8% loss) happen when several consecutive snapshots are lost while the runner is turning sharply. Corrections under 3 m are blended out visually over a few frames instead of snapping the camera.
- "Host starved" counts ticks where the host had no new input from a client and repeated its last held input. The counts seen are ≤ 0.3% of ticks.

These are **8 independent desktop clients on one Linux machine over UDP**. They are not iPhones and not the Game Center transport.

The 7- and 3-client soaks ran on commit `23004fe`, before the bot and chase-tuning changes. Those changes alter gameplay balance, not the network code, so the networking numbers carry over.

## 4. iOS build (CI iOS)

| Step (`.github/workflows/ios.yml`) | Result |
|---|---|
| Godot 4.7.2 export to Xcode project (bundle `com.idlery.ultimatetrifecta`, Game Center entitlement) | ✅ |
| `xcodebuild archive` for `generic/platform=iOS`, `CODE_SIGNING_ALLOWED=NO` (arm64 compile + link) | ✅ **project compiled** (unsigned) |
| Simulator build (x86_64; Godot 4.7.2's simulator slice is x86_64 only) | ✅ |
| Simulator launch (runs 3–10, iPhone Air simulator, iOS 26.2 runtime) | ✅ **Installs, launches and reaches a match** (runs 4, 5, 8, 9 and 10; runs 6 and 7 used a shorter window and were still loading when it closed).<br>Run 10 is on the final code (`docs/media/ios_simulator_ci_run10.jpg`): boot splash, about 5 minutes of loading, then the role-reveal card, 4:00 HUD, target list, minimap and [BOT] players, still rendering at the end of the window. The Simulator here produces roughly one frame every 30 s, so game time advances very slowly and the round never got past the reveal.<br>**Crash reports:** run 8 produced one `UltimateTrifecta-…-111659.ips` report. CI printed only its file name, and the cold-launch app was no longer in the foreground at 45 s in that run, so the report most likely belongs to that cold launch. Its contents were not captured, so the cause is **unknown**. CI now summarises any report (`tools/ips_summary.py`). Runs 3–7, 9 and 10 produced none, and in runs 9 and 10 the cold launch was still alive at 45 s.<br>A cold launch never reached the title screen within the 45 s window. |
| Archive facts (runs 4–10) | Xcode 26.6 (17F113), iphoneos SDK 26.5, `arm64` binary, `.app` 261 MB uncompressed. Runs 5–6 have no purpose-string warnings.<br>Info.plist: `CFBundleIdentifier com.idlery.ultimatetrifecta`, `1.0 (10)` in run 10 (final code), `MinimumOSVersion 17.0`, `UIDeviceFamily 1,2`, landscape left/right, `ITSAppUsesNonExemptEncryption false`.<br>Entitlement: `com.apple.developer.game-center`.<br>Frameworks: `GodotApplePluginsGameCenter`, `SwiftGodotRuntime`. `PrivacyInfo.xcprivacy` declares file-timestamp, boot-time and disk-space API reasons. |
| Signed archive / upload | ⏸ not run: no App Store Connect credentials (see TESTFLIGHT_RELEASE.md) |

Godot 4.7.2's simulator slice is x86_64, so the app runs under Rosetta on a virtualised Apple-silicon runner. It also falls back to an OpenGL ES 3.0 context there (the console says "Setting up an OpenGL ES 3.0 context"), while devices use Metal.

As a result, the Simulator is orders of magnitude slower than a device. Loading took minutes there, against about 1 s for the whole map generation on the Linux desktop (layout 68 ms, nav grid 54 ms, collision 242 ms, visuals 591 ms), and screenshots 15–20 s apart were often identical. These runs prove that the iOS build installs, launches and runs the game code into a match. They say nothing about iPhone load time or frame rate.

Evidence: the GitHub Actions artifact `ios-simulator-evidence-<build>`, holding screenshots, a screen recording, `app-console.log` and `export.log`.

The archive build also showed that Godot's export writes **empty** camera, microphone and photo-library purpose strings, which Xcode warns about. They are now filled with honest "not used" text, so App Store validation does not trip on empty strings. The app bundle contains `PrivacyInfo.xcprivacy`.

## 5. Exploit attempts and fixes

| Attempt | How tested | Result |
|---|---|---|
| Camp a water's exits | `test_camping` (geometry for all six waters, plus a live respawn with two campers) | Cannot cover every exit; respawn ≥ 20 m from two campers |
| Camp the dorm with a cart | `test_camping`: cart driven at the dorm from 4 sides | Bollards stop it 17–54 m out; 4 doors 18+ m apart |
| Hide indefinitely in water | `test_water_resurfaces_automatically` | Forced resurfacing after 1.5 s at a shore exit |
| Hide anywhere | Rules | Survival never counts; only finishes win, so the clock favours the Night Watch |
| Chain-bump a runner with a cart | `test_bump_stumbles_without_chain_or_capture` | One stumble, then 1 s bump protection and a per-cart cooldown; never a capture |
| Tag through a wall | `test_tag_reach_cooldown_and_walls` | Rejected (line of sight is checked on the host) |
| Tag from a cart or right after dismount | `test_cart_drive_exit_safely_and_lockout`, `test_tag_validation_roles_and_states` | Rejected (on-foot only; 0.5 s lockout after exit) |
| Take a cart as a runner, or two patrols racing for one seat | `test_cart_seat_race_and_roles` | Runners cannot enter; exactly one patrol gets the seat |
| Double-use a gadget, or use one you don't own | `test_gadget_single_use_and_ownership` | Consumed once; ownership and cooldown checked on the host |
| Reconnect for an advantage (reset, free protection, duplicate gadget) | `test_reconnect_resumes_and_reservation_expires`, `test_reconnect_resumes_slot_and_progress` | Same state and progress resumed; no reset, no protection, no duplicates |
| Re-splash for extra stamps; inactive water | `test_duplicate_and_inactive_splash` | Rejected |
| Out-of-bounds or fall shortcut | `test_out_of_bounds_recovery_grants_nothing` | Recovers to the last pad; no stamps, no shortcut |
| Late or duplicate packets changing results | `test_duplicate_reordered_inputs_and_late_snapshots`, `test_same_tick_finish_beats_tag` | The host is the only authority; events are deduplicated by ID |
| Farm one runner for capture coins | `test_rewards_unique_captures_no_idle_survival` | Only distinct runners pay |

**Fixed during testing.**
- **Client prediction drift** (≈ cm-level corrections, occasionally more):
  - Floor contact is now serialized at the end of each step, and the floor is snapped after a reconcile.
  - An off-by-one in the client's process-tick gating was corrected.
  - The Night Watch now holds a WAITING state from setup on both host and client.
  - Average corrections dropped to a few millimetres.
- **Clients reporting "finished" twice:** now guarded, and the host remains the only authority.
- **Rendering:**
  - Back-facing generated meshes (cylinders, cones, roofs, door glows) fixed.
  - Washed-out vertex colours fixed with an sRGB→linear conversion.
  - Pool water was hidden under the plaza paving; fixed.
- **Route test overwrote bot timings:** it replaced the measured times for non-curated combinations; it now merges them.
- **Foot chases could not be won.** Seen in the Night Watch capture, where the bot followed a runner at 1–2 m for 20 s without a tag. The Night Watch foot speed is now 6.2 m/s, the wind-up keeps 60% speed, and the bot waits for a closer gap against sprinting runners. Details are in RULES.md, and `test_chase_balance` covers it.
- **Tree canopies could fill the screen** when the follow camera passed through a tree. Seen in the runner capture. Canopies now dissolve near the camera through a foliage-only shader variant.
- **Bots ran stacked in single file** on shared nav paths, and one got pinned on the pool's west gate post for over 3 minutes during the route test. Bots now have stable route preferences, steer apart from nearby teammates, and back off sideways when a hop doesn't free them.
- **Broken time-lapse captures.** A `--time-scale` capture flag made runners move 4× per simulation tick: a trifecta "in 0:36" in a captured results screen. The flag scaled the engine physics delta while the simulation counts fixed ticks. Normal play never used it; it has been removed.
- **Screen overflow at 16:9 and iPad 4:3.** The results, Play with Friends and lobby screens overflowed at 1280×720 and 1280×960; the lobby's Start button was partly off-screen. Found by rendering every menu screen at both aspects. Layouts were tightened and re-checked at 16:9, 4:3 and 19.5:9.
- **Empty purpose strings in Info.plist.** Godot's export wrote empty camera, microphone and photo-library strings; Xcode warned about them in CI run 3. They are now filled.

## 6. Visual and audio evidence

Index: `docs/media/README.md`. Every file is labelled by platform and commit.

- **Desktop clips** (Linux, Godot Movie Maker, software Vulkan):
  - a 58 s runner clip: reveal, head start, splash and stamp;
  - a 75 s Night Watch clip: cart in, drive, hop out, chase, capture;
  - a full-round time-lapse through to the results screen.

  The local player in each is bot-driven automation (`--local-bot`), and each clip says so.
- **Stills:** the title screen, the six waters and other campus locations, and key moments from the clips.
- **iOS Simulator contact sheet** from CI run 10, on the final code (see section 4).
- **Visual review findings.** Reviewing these captures found the canopy-camera, bot-stacking and foot-chase problems listed under "Fixed during testing", and the time-scale capture bug. All are fixed; the clips were re-recorded afterwards.
- **No physical-device footage.**

## 7. Not yet verified (exact remaining device checks)

- [ ] **Two or more iPhones over the internet:**
  - create a code room on one, join with the code on another (Game Center `player_group` matchmaking);
  - Game Center friend invite and accept;
  - a full round with cart entry/exit, chase, tag, splash and finish;
  - rematch; host leaves mid-round.
- [ ] **Performance:** 60 fps on an iPhone 14-class device across 3+ consecutive rounds, plus memory and heat (Xcode Instruments). Also check the "Battery saver" graphics option on an older device.
- [ ] **Touch:** feel of the dynamic stick and the edge-sprint threshold, camera drag ownership, and button sizes on small iPhones. Safe areas on Dynamic Island devices and iPad (menu layouts were render-checked at 16:9, 4:3 and 19.5:9 on desktop only).
- [ ] **Controllers:** an MFi/Xbox/PlayStation controller on device, plus connect and disconnect mid-match with prompt switching.
- [ ] **System behaviour:**
  - The silent switch mutes the game (Godot's default *Ambient* audio session); check that the visual cues carry play.
  - Airplane mode: online is disabled with an explanation and practice works.
  - Background/foreground during a round.
  - Declined or interrupted Game Center sign-in.
- [ ] **TestFlight install** of a signed build: blocked on App Store Connect access (TESTFLIGHT_RELEASE.md).

## 8. Known limitations

- **Host trust.** The online host is a player's device. Results are host-authoritative but **not cheat-proof**, and host migration is not implemented: if the host leaves, the round ends without rewards.
- **Code rooms.** Code rooms use Game Center matchmaking with a `player_group` derived from the code. Players with the same code are matched together, but Game Center decides timing, which can take a few seconds. This has only been reasoned about from Apple's API documentation and has not been run on devices.
- **Desktop LAN.** Desktop LAN (ENet) exists for development and testing only and is not shown in iOS builds.
- **Lighting.** Night lighting was tuned on desktop screenshots, and brightness needs a check on a real iPhone screen.
- **Plugin export errors.** When Godot exports, GodotApplePlugins' extension logs about 76 "Class 'GK…' already has constant …" errors (duplicate enum constants). They are harmless duplicates and the build succeeds, but they will also appear in the device console.
- **Minimum device.** Godot's export marks the app `iphone-ipad-minimum-performance-a12`, so it installs on A12-class devices (iPhone XS/XR) and newer.
- **One unexplained Simulator crash report** (run 8, see section 4). It was not reproduced in run 9, and it needs watching in the first TestFlight sessions.
