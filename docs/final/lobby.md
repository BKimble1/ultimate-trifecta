# Final release sweep · Lobby lighting (LIGHT)

Brief §3, "Lighten the lobby with a controlled art pass". Branch
`worktree-agent-ae69c577cd2e768e4`, from the integrated commit `e3c2cd6`
(1.9 (9)). Evidence: [`../media/final/lobby/`](../media/final/lobby/).

**Status.** Done and measured on same-camera desktop renders: the dorm
behind Home, the party room, Locker, Shop and Season Pass is lighter in its
dark midtones, the runner and the party are a little brighter and stay the
clear focal point, the warm lamp corner is no longer hidden by an overlay, and
every line of text that sits directly on the room is above the 4.5:1
guideline on both phone shapes (lowest 5.57 on the iPhone 14 shape, 4.97 on
SE; several were under 4.5:1 before). The room stays night:
the lamp shade highlight, the moonlit window and the contact shadows keep
their places, nothing clips. No lights, shadow settings, glow, tone mapping or
post-processing were added or changed in kind; Battery Saver gets the same
result. **Not verified on a phone**: the brightness/OLED judgement and the
light falloff on a real Apple GPU (open items below).

**One finding affects every stream's desktop evidence (L1).** On this
machine's CPU (AVX-512 FP16), llvmpipe miscompiles some of the Mobile
renderer's half-precision shaders, and the characters lose all directional
light: Pass 9's desktop captures (and the first baseline of this pass) show
the default runner with a dark tan face and navy pyjamas instead of a pale
face and sky-blue stripes. It is a desktop rendering fault, not a game bug;
`GALLIUM_OVERRIDE_CPU_CAPS=avx` gives the correct picture. Every frame in this
pass's evidence uses it.

## What the player sees

| | Before | After |
|---|---|---|
| Home as seen (iPhone 14 shape), mean luma / near-black pixels | 78.1 / 25.2 % | 88.1 / 12.9 % |
| Party room, 1 player, as seen | 80.6 / 21.2 % | 90.3 / 10.2 % |
| Room alone on Home: mean / 10th percentile | 88.0 / 31.6 | 97.0 / 39.0 |
| Your runner on Home: cheek / torso | 160.4 / 134.8 | 167.1 / 141.2 |
| Warm lamp shade (highlight) | 229.7 | 230.2 |
| Back wall / night sky through the window | 57.7 / 29.7 | 80.2 / 36.7 |
| Lowest over-room text contrast (iPhone 14 · SE) | 4.17 · 3.18 | 5.57 · 4.97 |

Luma is Rec. 709 Y′ of the sRGB pixel (0-255). Full tables below.

## Defect register

| # | Symptom | Reproduction | Cause | Fix | Evidence |
|---|---|---|---|---|---|
| L1 | Desktop captures show the characters much darker than designed: tone-2 skin reads as dark tan (cheek 93 luma, RGB 123/86/76), sky-blue pyjamas as navy (torso 63); a StandardMaterial3D sphere beside the runner is black under the key light while the room is lit. Pass 9's `docs/media/pass9/skins/lineup_dorm.jpg` shows it; V8's dorm close-ups (`docs/media/v8/characters/*_dorm.jpg`) do not | `src/dev/lobby_light_lab.tscn` on the Mobile renderer, Mesa default: with only the key (or fill, or moon) on, the runner's torso is 1.5 / 0.1 / 0.1 luma; custom test shaders on spheres: `diffuse_lambert_wrap` 0, `BACKLIGHT` alone 0, `BACKLIGHT`+`ROUGHNESS` lit, burley lit, the dorm shader (lambert wrap) lit, so it depends on how each shader compiles, not on the lighting maths | **Verified**: llvmpipe (Mesa, LLVM 20.1.2) on a CPU with AVX-512 FP16 miscompiles part of the Mobile renderer's fp16 (half-precision) shader path. With `GALLIUM_OVERRIDE_CPU_CAPS=avx` the same frame is correct (cheek 93 → 161, RGB 198/155/125; torso 63 → 135) and matches the Forward+ renderer (fp32) on the same machine (cheek 165, torso 135). The V8 tree renders the same wrong picture here today, so no code or asset change caused it; V8's evidence was rendered on a host without the fault. iOS (Metal, Apple GPU) does not use llvmpipe; a default material missing its sun light there would break every Godot mobile game, so the device is not expected to show this (not verified on a phone) | `tools/capture_final_lobby.sh`, `tools/capture_lobby_loadin.sh` set `GALLIUM_OVERRIDE_CPU_CAPS=avx` by default (`=native` shows the fault). **Integrator**: other capture lanes need the same (proposal below). No game change | `L1_llvmpipe_fp16_fault.jpg` (same frame: host features / AVX / Forward+) |
| L2 | The room behind every menu is dark in the midtones: the walls (the largest area of every framing) 57.7 luma, the night sky 29.7, the dark wood 31.9; 16.8 % of the Home room frame is under 40 | `tools/capture_final_lobby.sh` (before: the base tree), `tools/lobby_light_measure.py` | Low wall albedo (`3a4a6b`, a dark slate) under a modest grey-lavender ambient (`6d6f8c` × 0.55); the cool front fill (0.22) barely reaches the walls; a near-black sky | The room's own values, no new lights (below): room mean 88.0 → 97.0, p10 31.6 → 39.0, near-black 16.8 % → 10.3 %; back wall 57.7 → 80.2, sky 29.7 → 36.7, plinth 31.9 → 38.2, couch 81.3 → 86.5, lamp shade 229.7 → 230.2 | `p14_*.jpg`, `se_*.jpg`, `battery_*.jpg`; tables below |
| L3 | The runner and the warm lamp corner look dimmer than the room around them on Home and in the party room | Same captures: what the player sees against the 3D frame alone: the lamp/bookshelf corner 70 %, the runner's torso 85 % (Home and party room) | `TitleScreen.add_shades`: the right-hand navy gradient ran across the whole width (≈ 0.15 alpha over the Home runner, 0.12 over the party, 0.3-0.45 over the lamp and bookshelf) | The shade now starts in the lower-right corner (where text sits on the room) and is gone before the middle: the lamp corner 70 % → 82 % of its 3D brightness, the runner 85 % → 93 % (Home) and 97 % (party room). With L2, Home as seen 78.1 → 88.1, near-black 25.2 % → 12.9 % | `p14_01_home.jpg`, `p14_06_lobby_1p.jpg` |
| L4 | Party room lines drawn straight on the room under 4.5:1: "Share the code, or start now." 4.17, "You + 7 bots" 4.31 (iPhone 14); 3.74 and 3.86 on SE | Captures `06`-`08`, contrast column | 70 % ivory caption on a 0.3-0.4 alpha shade over the room | 88 % ivory and `UIKit.outlined`'s soft halo on the party count, status and sub lines: 5.57-7.34 (iPhone 14), 4.97-6.65 (SE) | contrast table below |
| L5 | (Introduced, then fixed in this pass) On the SE shape Home's new-player hint ("New here? Practice starts with a short tutorial.") sits over the floor lamp's light pool; with the lighter room the halo alone measured 4.06:1 | `00_home_new`, SE | The pool is the brightest floor area; a halo is not enough there | A compact navy pill (`UIKit.scrim`, 50 %) behind the hint only, while it is shown: 7.16:1 on SE (was 3.18 before this pass), 10.81 on iPhone 14 | `se_00_home_new.jpg`, contrast table |
| O1 | (Observation for SEASON) On the Season Pass the room character is mostly hidden by the central panel; the room's lift reaches only the edges (as seen 59.5 → 63.7). Text inside its translucent side cards measured 5.16 → 4.72-4.89 on SE (still above 4.5) | `05_season` | Season layout (owned by the SEASON stream) | None here: `season_screen.gd` untouched | `p14_05_season.jpg` |

## Decisions, with the numbers

How it was judged: same camera, same poses (each character's idle clock
restarted together, no fidget or blink due), the Mobile renderer with Mesa
limited to AVX (L1), at the iPhone 14 shape (2532×1170 @3x with its 47/0/47/21
pt safe area, rendered as its 1558×720 canvas, the FAST=1 approach of
`tools/capture_pass9_season.sh`) and the SE (1334×750 @2x), Standard and
Battery Saver. Each shot is measured three ways: as seen (UI included), the
3D frame (UI hidden) and the room alone (UI and characters hidden).
Characters are measured on their own pixels (where the 3D frame differs from
the room frame): the cheek (median of a disk below the eyes) and the torso.

The starting values (ambient 0.55, key 1.05, fill 0.22, moon 0.4, lamps
1.9 / 0.9) were evidence. What each lever did on the Home room, alone
(lab, `src/dev/lobby_light_lab.tscn`): ambient 0.55 → 0.70 lifted the room
mean only 88.0 → 89.4; fill 0.22 → 0.40, 88.0 → 90.7; lamps +26 %,
88.0 → 89.7. The walls stayed dark under every light change because their
albedo is low, so the main lever is the wall colour, with small light changes
around it.

| Setting (`DormStage._build_room`) | Before | After | Why |
|---|---|---|---|
| Ambient | `6d6f8c` × 0.55 | `7379a0` × 0.62 | The shadowed side of furniture and walls lifts; a touch bluer keeps it night and keeps the sky-blue pyjamas saturated (0.194 vs 0.169 with the old hue at matched brightness). Same-luminance variants with the old hue changed skin saturation by only 0.015 |
| Cool front fill (no shadow, no specular) | 0.22 | 0.32 | Lifts faces and walls; it rakes the floor at 12°, so the contact shadows keep their depth |
| Floor lamp / table lamp | 1.9 / 0.9 | 2.15 / 1.0 | A warmer lamp corner; the shade highlight stays ≈ 230 (not blown) |
| Walls / wainscot | `3a4a6b` / `2f3d5a` | `4a5c83` / `3b4d6d` | The largest dark area, one step lighter in the same slate blue (saturation 0.18 → 0.21: not greyer) |
| Night sky (window view, unshaded) | `0a1230` · `15224a` · `2b3f72` | `0c1638` · `192a56` · `31487e` | Reads as cool moonlit sky instead of a dark hole; still night |
| Key light, moon, shadows, glow, tone mapping | 1.05, 0.4, one shadowed directional, glow 0.35, filmic white 6 | unchanged | Not needed; no exposure or post-processing change |

Tried and not kept: a stronger light step on the same walls (ambient 0.68,
fill 0.36) gave a room mean of 98.3 against 97.0, too little for the
flatter shadows (ambient and the fill fill the contact shadows); the walls'
saturation was the same either way (0.21), so the wall colour stayed. The
first, smaller step (the same lights with walls `43557a`) reached 95.2. The
CharacterView indoor path (rim, skin warmth) is
unchanged: it is shared with the Shop and Locker portraits and the Season
preview, and on a correct render the runner already reads as the focal point
(cheek ≈ 160 and torso ≈ 135 against a room mean of 88); the room lift adds
about +6 luma to every character without clipping (character p95 176 → 181,
nothing above 235 but the eye catch-lights, as before).

Overlays: the right shade (`TitleScreen.add_shades`, used by Home, the party
room, Locker, Shop, Season Pass and results) keeps its alpha at the lower-right
corner (where text is on the room) and fades to 0 at 62 % of the diagonal
toward the upper left; the upper-left shade behind the title is unchanged.
Panels and cards keep their surfaces (their text contrast is unchanged within
measurement noise). The four over-room lines get 88 % ivory, the halo, and on
Home the hint a pill.

## Measurements

iPhone 14 shape, Standard (`build/lobby/final/compare_p14_standard.json`).
"Room" is the frame with UI and characters hidden; "seen" is what the player
sees. Luma 0-255.

| Shot | Room mean | Room p10 | Room p50 | Room p90 | Room <40 | Seen mean | Seen p10 | Seen <40 | Seen >235 |
|---|---|---|---|---|---|---|---|---|---|
| Home (new player) | 88.0 → 97.0 | 31.6 → 39.0 | 77.1 → 85.5 | 170.9 → 177.1 | 16.8 % → 10.3 % | 78.4 → 88.3 | 30.2 → 39.3 | 25.1 % → 12.9 % | 1.26 % → 1.26 % |
| Home | 88.0 → 97.0 | 31.6 → 39.0 | 77.1 → 85.5 | 170.9 → 177.1 | 16.8 % → 10.3 % | 78.1 → 88.1 | 30.1 → 39.3 | 25.2 % → 12.9 % | 1.26 % → 1.26 % |
| Locker | 84.6 → 94.0 | 29.9 → 37.6 | 69.8 → 83.2 | 154.2 → 158.6 | 19.0 % → 11.7 % | 65.0 → 71.8 | 34.8 → 37.5 | 44.0 % → 34.8 % | 0.17 % → 0.21 % |
| Shop | 84.6 → 94.0 | 29.9 → 37.6 | 69.8 → 83.2 | 154.2 → 158.6 | 19.0 % → 11.7 % | 64.0 → 70.7 | 34.7 → 37.5 | 46.1 % → 37.3 % | 0.20 % → 0.21 % |
| Shop, charcoal outfit tried on | 84.6 → 94.0 | 29.9 → 37.6 | 69.8 → 83.2 | 154.2 → 158.6 | 19.0 % → 11.7 % | 63.9 → 70.4 | 30.7 → 36.0 | 46.1 % → 36.5 % | 0.38 % → 0.39 % |
| Season Pass | 88.0 → 97.0 | 31.6 → 39.0 | 77.1 → 85.5 | 170.9 → 177.1 | 16.8 % → 10.3 % | 59.5 → 63.7 | 33.1 → 36.2 | 38.5 % → 32.3 % | 0.55 % → 0.55 % |
| Party room, 1 | 94.4 → 101.7 | 38.4 → 52.4 | 98.0 → 101.5 | 170.4 → 175.1 | 11.2 % → 5.9 % | 80.6 → 90.3 | 32.8 → 40.0 | 21.2 % → 10.2 % | 0.35 % → 0.35 % |
| Party room, 4 | 96.0 → 102.1 | 38.7 → 55.4 | 93.7 → 98.2 | 142.5 → 149.2 | 10.5 % → 4.3 % | 80.1 → 88.9 | 36.3 → 38.8 | 21.0 % → 12.7 % | 0.51 % → 0.51 % |
| Party room, 8 | 82.5 → 89.1 | 32.4 → 32.4 | 85.7 → 89.5 | 121.2 → 125.6 | 15.1 % → 11.6 % | 72.7 → 80.2 | 30.0 → 33.2 | 32.8 % → 28.4 % | 0.72 % → 0.72 % |

(Locker, Shop and Season as seen move less: their panels cover over half the
screen by design. In the 8-player room the p10 is the far, unlit right wall
under the party panel.)

Characters (cheek = median of the cheek disk; torso = mean of the chest patch):

| Shot | Your cheek | Your torso | Party cheeks (avg) | Party torsos (avg) |
|---|---|---|---|---|
| Home | 160.4 → 167.1 | 134.8 → 141.2 | - | - |
| Locker | 162.8 → 169.2 | 136.5 → 142.8 | - | - |
| Shop, charcoal outfit | 164.9 → 171.4 | 170.2 → 176.6 (cream belly) | - | - |
| Season Pass | 160.4 → 167.1 | 134.8 → 141.2 | - | - |
| Party room, 1 | 163.1 → 169.5 | 133.5 → 140.3 | - | - |
| Party room, 4 | 165.2 → 171.8 | 138.8 → 145.5 | 149.6 → 155.1 | 161.5 → 167.5 |
| Party room, 8 | 163.6 → 169.7 | 136.4 → 143.2 | 122.9 → 128.0 | 131.4 → 136.8 |

The eight party looks (iPhone 14, 8 players; cheek · torso):

| Who | Look | Before | After |
|---|---|---|---|
| You (front centre) | default pyjamas, tone 2 | 163.6 · 136.4 | 169.7 · 143.2 |
| Pip | Record Breaker (white shorts) | 160.6 · 173.2 | 167.0 · 178.5 |
| Rowan | Dr. Doom (brown suit) | 154.7 · 133.6 | 161.1 · 139.7 |
| Biscuit | Bedtime Bandit (charcoal) | 133.1 · 170.4 | 138.2 · 176.9 |
| Marigold | Moonwalk Cadet (ivory) | 156.5 · 111.9 | 162.8 · 117.6 |
| Dozy | white pyjamas, tone 7 | 65.4 · 136.2 | 68.9 · 141.7 |
| Wren | Midnight track suit, tone 8 | 45.8 · 32.4 | 48.2 · 35.5 |
| Juniper | Raincoat Explorer (yellow) | 144.2 · 162.1 | 150.1 · 167.5 |

Reference patches (room frame, Home unless noted):

| Patch | Before | After |
|---|---|---|
| Lamp shade (warm highlight) | 229.7 | 230.2 |
| Night sky through the window | 29.7 | 36.7 |
| Window sill (ivory paint) | 124.5 | 135.2 |
| Back wall | 57.7 | 80.2 |
| Couch front, in shade | 81.3 | 86.5 |
| Armchair, lamp side | 103.0 | 108.5 |
| Bookshelf plinth (dark wood) | 31.9 | 38.2 |
| Floor planks (party room, 1) | 92.8 | 96.6 |
| Rug | 133.1 | 137.3 |

SE (1334×750) and Battery Saver (iPhone 14 shape, 3D at 80 %, 1024 shadow
map) give the same picture:

| | SE Home room · seen | SE party 8 seen | SE your cheek · torso | Battery Home room · seen | Battery party 8 seen | Battery your cheek · torso |
|---|---|---|---|---|---|---|
| Mean | 89.6 → 98.3 · 77.7 → 87.5 | 72.5 → 79.3 | 160.4 → 167.0 · 134.8 → 141.3 | 88.4 → 97.5 · 78.4 → 88.5 | 73.0 → 80.5 | 160.4 → 167.3 · 134.6 → 141.0 |
| <40 | 20.1 % → 12.4 % · 26.5 % → 15.5 % | 34.3 % → 30.1 % | | 16.3 % → 10.0 % · 24.8 % → 12.4 % | 32.4 % → 28.1 % | |

Text contrast (WCAG ratio, measured on the frame the player sees: the text's
98th luminance percentile against the median of its box; buttons on their
inner area; text scrolled out of view is skipped):

| Text (over the room) | iPhone 14 before → after | SE before → after |
|---|---|---|
| Home: "New here? Practice starts with a short tutorial." | 5.59 → 10.81 (pill) | 3.18 → 7.16 (pill) |
| Party 1: "Party · 1/8" | 9.41 → 9.24 | 5.08 → 5.89 |
| Party 1: "Share the code, or start now." | 4.17 → 5.75 | 3.74 → 4.97 |
| Party 1: "You + 7 bots" | 4.31 → 5.94 | 3.86 → 5.32 |
| Party 4: "Party · 4/8 · 4 ready" | 5.07 → 5.57 | 7.90 → 7.94 |
| Party 4: "Everyone's ready" | 4.95 → 6.88 | 3.74 → 5.04 |
| Party 4: "4 players + 4 bots" | 4.81 → 6.98 | 4.18 → 5.86 |
| Party 8: "Everyone's ready" · "Full party" | 5.02 · 5.11 → 7.03 · 7.20 | 3.99 · 4.74 → 5.37 · 6.65 |

| Text (on panels and buttons, unchanged surfaces) | iPhone 14 before → after |
|---|---|
| Play with Friends · Practice · Start | 11.89 · 10.90 · 11.89 → unchanged |
| Profile chip name · Party code | 13.45 · 7.31 → 13.23 · 7.30 |
| Open seat card: "Open seat" · "Share the code" | 5.41 · 7.32 → 5.04 · 6.84 (translucent card, still above 4.5) |
| Shop detail: "Bedtime Bandit" · description | 13.41 · 13.37 → 13.23 · 13.34 |
| Season Pass: "Season 1 · After Hours" · "Rewards unavailable right now" | 13.60 · 9.62 → 13.41 · 9.43 |

## Performance

Nothing that costs frame time on an A12 changed: the same three directional
lights (one shadowed, the same 10 m orthogonal shadow range and blur), the
same two unshadowed omni lights, the same additive light-pool quads, the
same glow and filmic tone mapping, no post-processing, no new draw calls (the
room and the window view are still one mesh each; only vertex colours and
light energies changed). The overlay is still two 256×128 gradient textures per
screen. The quality presets and the governor are untouched; Battery Saver
was captured and matches.

## Campus and match

`DormStage` and the dorm shaders are used only behind the menus (the campus
dorms are separate geometry); `CharacterView` was not changed; the match HUD
does not use `add_shades`. Checked on a rendered round: an offline Practice
round (`--autoplay=runner --local-bot --seed=3`, a frame every 4 s) on the base
tree and on this branch. The campus dorm's role reveal and countdown frames
are identical except the characters (their idle phase is seeded per object
instance) and the randomly generated player name: 2.7 % and 5.2 % of pixels,
all on those; walls, floor, light, HUD and sky do not change. The first
outdoor frame could not be compared pixel for pixel (the round's load time
differs between runs, so the clock read 3:57 vs 3:58); it shows the same
campus night light. Evidence: `match_unchanged.jpg`.

## How verified

- Captures (each run renders a tree; "before" is the base commit's tree
  extracted with `git archive e3c2cd6 game`):
  `GAME_ROOT=<base> tools/capture_final_lobby.sh build/lobby/final before p14 se`,
  `tools/capture_final_lobby.sh build/lobby/final after p14 se`, and the same
  with `QUALITY=0` for Battery Saver. 9 shots each, all present.
- Measurement: `tools/lobby_light_measure.py --compare <before> <after> --json …`.
- Lighting lab (iteration, the L1 diagnosis): `src/dev/lobby_light_lab.tscn`
  (`--lab-mode=home|lobby8`, `--lab=name:node.prop=value|…`).
- Tests (headless): `tools/gd.sh --headless --fixed-fps 60 --path game -s
  res://tests/run_tests.gd -- <filters>`:
  `test_lobby, test_lobby_flow, test_v7_screens, test_menus_layout,
  test_boot_branding, test_characters_v7` (36 tests, 12,122 checks, 0
  failures); `test_account, test_focus, test_screen_cycles, test_wardrobe,
  test_shop_ui, test_emotes, test_hub_walk, test_portraits, test_stage_drag`
  (36 tests, 471 checks, 0 failures); after the label and hint changes
  `test_v7_screens, test_menus_layout, test_account, test_focus,
  test_screen_cycles, test_boot_branding` (41 tests, 12,085 checks, 0
  failures) and `test_lobby, test_lobby_flow, …` (37 tests, 12,095 checks,
  0 failures). The 3 "Lambda capture at index 0 was freed" errors in that log
  appear identically on the base tree.

## Evidence index (`docs/media/final/lobby/`)

Every picture: desktop render, llvmpipe (Godot 4.7.2 Mobile renderer under
Xvfb, Mesa limited to AVX), same camera before and after, fictional names;
not device footage. Before above, after below, 1280 px wide (the face crops
side by side).

| File | What |
|---|---|
| `L1_llvmpipe_fp16_fault.jpg` | L1: one frame of the base tree with the host's CPU features (wrong), with Mesa limited to AVX (correct) and in Forward+ |
| `match_unchanged.jpg` | A Practice round's dorm reveal and countdown, base vs this branch, with the changed pixels (characters' idle phase and the generated name only) |
| `p14_00_home_new.jpg`, `p14_01_home.jpg` | Home for a new player (the hint) and a returning one, iPhone 14 shape |
| `p14_01_home_faces.jpg`, `p14_08_lobby_8p_faces.jpg` | Faces side by side (crops) |
| `p14_02_locker.jpg`, `p14_03_shop.jpg`, `p14_04_shop_dark.jpg`, `p14_05_season.jpg` | Locker, Shop, a charcoal outfit tried on, Season Pass |
| `p14_06_lobby_1p.jpg`, `p14_08_lobby_8p.jpg` | Party room with you alone and full (Record Breaker, Dr. Doom, charcoal, ivory, white pyjamas, midnight, yellow) |
| `se_00_home_new.jpg`, `se_01_home.jpg`, `se_06_lobby_1p.jpg`, `se_08_lobby_8p.jpg` | The same on the SE shape |
| `battery_01_home.jpg`, `battery_08_lobby_8p.jpg` | Battery Saver |
| `loadin_before.mp4`, `loadin_after.mp4` | The app opening into Home: Idlery Games curtain, the dissolve into the room, the hello wave; fixed 30 fps Movie Maker clock encoded at 30 fps (real-time speed) |
| `data/compare_*.json` | The measurements behind the tables |

Before frames (every shot, all three passes per shot) stay in
`build/lobby/final/before_*` (ignored).

## Open items (need a real phone)

1. **Brightness on the device.** Look at Home on an ordinary iPhone at
   mid brightness, then low brightness, with Auto-Brightness on: the room
   should read as a lamp-lit room at night, the runner first. Pass: the walls
   are blue, not grey; the window is clearly night; nothing glows.
2. **OLED black level.** On an OLED iPhone (12 or later) the window sky
   (≈ 37 luma) and the plinth (≈ 38) should hold detail, not crush to black.
3. **Characters on Metal.** Confirm the runner's face reads pale peach and
   the pyjamas sky blue (as `L1…jpg` middle/right), not dark tan and navy
   (left). If a device shows the left picture, L1 is not desktop-only:
   report it before release (the fix would be in the character shader, not
   this pass's values).
4. **Text over the room.** Read the party room's status lines and Home's
   tutorial hint at arm's length on an SE-class phone.

## For the integrator

- Merge as is; no protocol, save, service or migration change.
- **L1, all capture lanes:** set `GALLIUM_OVERRIDE_CPU_CAPS=avx` for every
  rendered desktop capture on this machine type. Proposed: in `tools/gd.sh`,
  before `exec`, `export GALLIUM_OVERRIDE_CPU_CAPS="${GALLIUM_OVERRIDE_CPU_CAPS:-avx}"`
  (headless tests are unaffected; llvmpipe timings change, which only
  matters to old llvmpipe frame-time comparisons, never device evidence).
  Captures taken without it under-light the characters (for example Pass 9's
  `docs/media/pass9/skins/lineup_dorm.jpg`); re-check any character evidence
  rendered on this machine type before reusing it.
- Files outside LIGHT's list: `game/src/ui/lobby_screen.gd` (three label
  constructors, lines with `count_lbl`, `status_lbl`, `sub_lbl`) and the hint
  block in `game/src/ui/title_screen.gd` (both also touched by FRIENDS for
  their entry buttons; different hunks).

Proposed TEST_REPORT.md lines:

> Final sweep, lobby lighting: same-camera desktop renders (Godot 4.7.2
> Mobile, llvmpipe with Mesa limited to AVX) at the iPhone 14 and SE shapes,
> Standard and Battery Saver: Home room mean luma 88 → 97, near-black pixels
> 17 % → 10 %; Home as seen 78 → 88; the runner +6 luma, nothing clipped;
> every line on the room at 4.97:1 or better (the lowest was 3.18). Desktop
> evidence; device brightness/OLED judgement pending. Desktop captures on AVX-512 FP16 hosts
> need `GALLIUM_OVERRIDE_CPU_CAPS=avx` (llvmpipe fp16 fault).

Proposed What to Test line:

> The dorm behind the menus is a little lighter: check that Home and the
> party room feel welcoming at night on your phone, that your runner stands
> out, and that the small lines beside the Start button are easy to read.
