# V3 media evidence (version 1.2)

Everything here was captured from the running game. Nothing is concept art,
an offline render or a mock-up.

**Platform for every file:**
- Desktop Linux, Godot 4.7.2, Mobile renderer on Mesa **llvmpipe**
  (software Vulkan) under Xvfb.
- The frame clock is fixed: `--fixed-fps`, or Movie Maker at 30 fps.
- Graphics preset **Standard** (MSAA 2×, 3D at 100%).

These files show layout, framing, art and animation timing. They **cannot**
show frame rate or device smoothness: llvmpipe takes far longer than a frame
budget, and the fixed clock hides that. There is **no physical-device
footage** (no device was available) and **no physical controller**.

- **Stills.** Lossless PNGs at the size they were rendered. Most have a JSON
  file of the same name with the render diagnostics for that frame: window
  and 3D render size, MSAA, draw calls, primitives and the capture label.
- **Lobby players.** Other players in lobbies are separate headless desktop
  client processes in a desktop LAN room (a development path; iOS uses Game
  Center).
- **Gameplay.** It is bot-driven: the local player is steered by the game's
  own bot (`--local-bot`).
- **Before.** The V2 ("before") files are in [../v2/after/](../v2/after/).

## Party lobby: 1, 2, 4 and 8 players (iPhone 6.1" layout, 2532×1170)

| File | What it shows |
|---|---|
| `lobby/lobby_1p.png` | Create Party result: code with Copy and Share, your runner front and centre, "share the code" on the first open slot, Start, bot fill stated once. |
| `lobby/lobby_2p.png` | Two players. Portraits in the slots, host crown, the guest's ready check. |
| `lobby/lobby_4p.png`, `lobby/lobby_8p.png` | Four and eight players. Every face is visible and every body is in frame, with random looks including tall hats. Status badges sit inside their cells. |
| `lobby/lobby_se_8p.png`, `lobby/lobby_ipad_8p.png` | Eight players at iPhone SE 16:9 (1334×750) and iPad 4:3 (2048×1536). The iPad capture is from `001f274`; the dorm is built larger than any framing, so the 4:3 view never sees past the walls. |

Before (V2): `../v2/after/lobby_1p.png`, `../v2/after/lobby_8p.png`.

Three problems were found in these captures and fixed. Each one now has a
test that fails on the old code:
- Slot badges spilled outside their cells.
- A back-row face sat behind a crown, and later an eye behind a nightcap.
- A wing player's arm was clipped by the screen edge.

## Screens

| File | Size | What it shows |
|---|---|---|
| `screens/home.png` | 2532×1170 | Home: the original wordmark, static font weights, one primary action. |
| `screens/creator.png` | 2532×1170 | Create Your Runner (opened from Outfit). |
| `screens/first_run_creator.png` | 1600×740 | First launch: Create Your Runner without Back, with "That's me!". |
| `screens/first_run_name.png` | 1600×740 | First launch: the name sheet (kept on the device until the service checks it). |
| `screens/settings_profile.png` | 1600×740 | Settings opens on Profile: name, status, Change name, Edit runner, Blocked players, Delete Game Profile. |
| `screens/delete_confirm.png` | 1600×740 | The Delete Game Profile confirmation, with the service off: on this device only. |
| `screens/online.png` | 2532×1170 | Play with Friends as it really appears on desktop: Game Center isn't available, so Create Party and the code field are disabled, and the sheet says why and offers Practice. On a signed-in iPhone, Create Party is the primary action. |
| `screens/practice.png`, `settings.png`, `howto.png` | 2532×1170 | Practice, Settings (opens on Profile), How to play. |
| `screens/results.png`, `results_drawer.png` | 2532×1170 | Results of a full bot-driven practice round, played headless with seed 11 and shown again: your round first, coins, Play again; the scoreboard sheet. |

## Character art (1600×900, `src/dev/character_lineup.tscn`)

| File | What it shows |
|---|---|
| `art/lineup_hero.png`, `art/lineup_closeup.png` | The icon-benchmark head: large clear eyes with one catch-light, tapered brows, matte skin, a clean collar. No speckling. |
| `art/lineup_faces.png` | Skin tones, eye styles and expressions. |
| `art/lineup_views.png` | Front, three-quarter, side and back views, runner and Night Watch. |
| `art/lineup_looks.png`, `art/lineup_hairs.png` | Outfits, patterns and hats; the hair styles built from hairline curves. |
| `art/lineup_group.png`, `art/lineup_distance.png` | A group and the distance read. |
| `art/lineup_posesheet.png` (+ `.txt` clip list) | All clips at a key frame each. |
| `art/lineup_transitions.png` | Gait blend transitions. |
| `art/lineup_cart.png` | Night Watch drivers seated, hands on the wheel. |

## Gameplay

| File | What it shows |
|---|---|
| `gameplay/controller_hints_playstation_simulated.png` (1600×740) | The controller hint list replacing the touch buttons, with PlayStation glyphs (✕ Jump, L1 Sprint). **Simulated** with `--sim-pad=playstation`: no controller was attached. Captured before the bot-name cleanup (`f5ecf18`), so bots still read "Bot Snooze · BOT". |
| `gameplay/splash_sequence_quarry.png` (6 frames, 640×360 each), `gameplay/splash_quarry_f1340.png` (1280×720) | Splashing into the Quarry, from the runner clip (frames 1310–1410). Your runner (blue nightcap) leaps in, then a second runner drops in right in front of the camera. Then the impact spray, the ripples around the swimmer, and climbing out with drips and running on. The HUD shows "Quarry stamped, 1 of 3 splashes", and the feed shows the bots' splashes coalesced into one line. |
| `gameplay/tag_f2035.png` (1280×720) | The Night Watch tags a runner: the whistle ring, "Tagged Snooze!", and the feed line. |
| `gameplay/cart_f720.png` (1280×720) | A golf cart under a tree after the canopy fix. The near canopy is cut away, so the tree's trunk and bare branches show in the foreground (before the fix this frame was 45.7% canopy, after 3.4%). |
| `gameplay/canopy_before_f*.png`, `gameplay/canopy_after_f*.png` (1280×720) | The canopy "porthole" and its fix. Frames 930, 1000 and 1250 of the same seeded Night Watch round (`--seed=21`, Movie Maker at 30 fps), before and after `cf53155`; the game state is identical frame for frame. Dark canopy covers 57.5% and 83.8% of frames 1000 and 1250 before, 2.2% and 2.8% after. Frame 930 shows the cost: a lit canopy no longer hides the right of the screen, and the tree's trunk and branches show instead. Method and full numbers: `docs/V3_NOTES.md`, "Camera and performance". |

## Movies (normal speed, 30 fps, 1280×720 unless stated)

Movie Maker writes every frame on a fixed 30 fps clock, so each clip plays
at normal game speed even though llvmpipe rendered it at about 9% of real
time. Every clip has its build and "NOT device footage" burned into the
bottom strip. H.264, no audio.

| File | Length | Code | What it shows |
|---|---|---|---|
| `movies/runner_v3_desktop.mp4` | 75 s | `cf53155` | A practice round as a runner (seed 11, steered by the game's bot): loading, role reveal, countdown, running across campus with the other runners, the Quarry splash sequence and the Inlet stamp. |
| `movies/nightwatch_v3_desktop.mp4` | 80 s | `cf53155` | A practice round as the Night Watch (seed 21, bot-driven): driving the golf cart along the roads and under trees, getting out, chasing on foot and tagging a runner. |
| `movies/canopy_before_after_desktop.mp4` | 16 s, 1280×390 | before / `cf53155` | Frames 870–1350 of the same seeded Night Watch round side by side: left, V3 before the canopy change (the porthole); right, with it. |
| `movies/lobby_v3_desktop.mp4` | 28 s | `d2fd2f3` | A LAN development room filling up: five headless desktop clients join one by one and ready up a few seconds later. The camera reframes as the group grows. |
| `movies/creator_v3_desktop.mp4` | 24 s | `d2fd2f3` | Create Your Runner: an outfit and pattern, colour and trim, a face, a hair style and colour, the hat tab, the runner's test run, and turning the runner by drag. |

The lobby and creator clips were recorded on `d2fd2f3`. Later commits
changed the lobby only by enlarging the room behind the group (for iPad
4:3); at 16:9 the old room already filled the frame.
