# V6 implementation notes (version 1.5)

V6 answers the owner's report on the V5 beta: graphics improved, but play
could suddenly turn very glitchy after running smoothly; match loading
started animating and then froze; finger swipes did not scroll the wardrobe
(only its scrollbar did); results looked dated. It also adds real dorm
interiors with doorway starts and finishes, a walkable party hub, Shop,
Locker, Season 1 and moderated communication (sections below).

Everything measured here was measured on a desktop Linux machine (headless,
or the Mobile renderer on Mesa llvmpipe) or in CI. **No iPhone or iPad was
available to this work**: device frame rate, heat and pipeline-compile cost
are unmeasured. Settings › Diagnostics (beta) now records what is needed to
measure them on a phone (below).

## Defect register

Categories are kept separate: **render stall**, **sustained low frame
rate**, **simulation backlog (catch-up)**, **camera jitter**, **animation
discontinuity**, **collision**, **input loss**, **network correction**,
**UI/input**.

| # | Trigger | Evidence | Category | Cause | Fix | Verification |
|---|---|---|---|---|---|---|
| D1 | A round with bots (practice; online parties fill seats with bots) | Headless practice soak on the V5 code: in some 5 s windows the physics step took 40–54 ms per frame and **every** frame ran 6 simulation ticks (the engine's cap), ~10 fps, then recovered (`docs/test-data/v6_soak_before.txt`). Section profile of a full 8-bot round (`src/dev/sim_profile.tscn`): bot thinking was **97 %** of a tick — 11.9 ms per tick on average; ticks p50 16.8 ms, p95 26.8, p99 35.8, max 60.8; 3,589 of 6,204 playing ticks over 16 ms (`docs/test-data/v6_sim_profile_before.txt`) | Simulation backlog → sustained low frame rate | Bot path planning: one A* on the 320×300 nav grid costs ~6 ms here (20–55 ms when the goal is unreachable — the search explores the whole grid); replans cluster (round start, Night Watch chases every 0.5 s, flee/stuck replans), and a bot whose goal was unreachable searched again **every tick** (2,570 repeats in one round, mostly Night Watch carts driving to points off the road network). A 60 Hz tick costing more than the frame budget makes the engine run several ticks in the next frame, which takes longer still: the "smooth, then suddenly very glitchy" spiral. On an A12 phone the same work costs more | `NavGrid.find_path_budgeted`: a clear straight line needs no search; at most one search per simulation tick (a waiting bot steers straight at its goal and retries next tick); a path to the same goal from the same neighbourhood is reused when its first leg is clear; an unreachable foot goal is not searched again for 5 s from that neighbourhood, an unreachable cart goal for 60 s. All bot paths (foot and cart) go through it | Same profile after: bot thinking **0.55 ms** per tick; ticks mean 1.52 ms, **p50 1.36, p95 2.24, p99 3.70**, max 25.6; 10 ticks over 16 ms per round (`docs/test-data/v6_sim_profile_after.txt`). `test_path_budget` (one search per tick, the next waits; clear line and same-neighbourhood reuse; an unreachable cart goal is not searched again). Bot behaviour suites (routes, pursuit, balance, camping) |
| D2 | Swipe on wardrobe cards | Owner report; reproduced in `test_touch_scroll` with V5's structure: the swipe moved nothing | UI/input | Cards are Buttons, which stop the touch, so the ScrollContainer (the engine's touch scrolling) never received it | `TouchScroll` / `UIKit.scroll_area()` for every list: content passes pointer events up; ~10 pt dead zone; a scroll cancels the press under the finger (lifting never selects/buys); nested strips keep their axis; follow-focus only for controller/keyboard; presses cancelled when the app loses focus | `test_touch_scroll` drives real GUI events with touch emulated from the mouse (as iOS delivers them): a swipe that starts on a card's picture scrolls and activates nothing; a tap activates once; jitter is still a tap; vertical and horizontal nesting. Both tests fail without the fix |
| D2b | Locker: drag to turn the runner with a second finger on the screen | `test_stage_drag` on the V5 handler: a second finger's touch and drag turned the runner (it jumped 100 px back) | UI/input | The turn area listened to every touch and mouse event | One pointer owns the turn (the first finger's touch index); its emulated mouse twin and other fingers are ignored; lifting or losing focus releases it | `test_stage_drag`: a 100 px drag turns 100 px once; a second finger does nothing; a drag leaving the area keeps turning until lifted; nothing after lifting |
| D2c | Locker: switch categories quickly | `test_wardrobe` sequence: V5 restored each category's scroll one frame later through a coroutine that did not check the category was still showing, and saved the next category's position from a list that had not been restored yet | UI/input | Stale deferred assignment | The newest request wins (one pending restore, through the screen's own one-shot frame hook, dropped if the screen goes, skipped under a finger); a pending restore is what gets saved. Screen's "open at top" uses the same hook | `test_wardrobe::test_category_positions_survive_rapid_switching` |
| D2d | A sheet or dialog opens while a list is under a finger or still gliding | `test_touch_scroll`: without the fix the list glided on behind the sheet (419 → 1054) and the finger kept scrolling it (1106 → 785) | UI/input | The list kept the pointer and its glide | `Screen.push_modal` makes every list behind it let go: the press is cancelled, a release ends the list's drag and capture, the glide stops; also on backgrounding | `test_touch_scroll::test_a_sheet_opening_releases_the_list` (both checks fail without the fix) |
| D3 | App start | Owner request | Startup | V5 used navy behind Idlery Games | Pure black `#000000` in the launch image, the launch storyboard, Godot's boot splash and the curtain; the CI audit fails on anything else | `test_boot_branding`; the audit passes on a local Godot 4.7.2 iOS export and fails when the storyboard colour is put back to navy |
| D4 | Match loading | Owner report ("animates, then freezes"); V5 code review | UI/input (loading) | In V5 the bar stopped at full once this device was ready while the round waited on other players or the host's first snapshot: an unknown wait looked like a frozen screen, and "preparing" and "waiting" shared one line. Leave appeared online only, after 25 s; practice had no way out | Two phases told apart: "Preparing campus…" with the real share of preparation done, then "Waiting for players · a/b ready" (or "Starting…") with an indeterminate sweep (still and dimmer with Reduced Motion). Cancel (practice) / Leave party (online) from 0.8 s on, and Back cancels practice. The freed round hands unfinished worker-pool jobs to App, which collects each when it is done (cancel never blocks a frame) | `test_loading`: cancel in the middle of the campus build with its meshes on the worker pool, three times — the round, session and screen go, the jobs are collected, scene nodes and orphans stay flat and objects stay within 1; the next practice round prepares and goes live. Phases and the sweep tested directly. Whether the V5 device freeze was this wait, a render stall or a catch-up spiral (D1) is not proven without a device: Settings › Diagnostics now separates them |
| D5 | Every cold campus build (first round; after a quality change) | `weakref` test: the builder was still alive after its build; objects grew by ~78 per build, and by the same per cancelled round | Memory growth | The builder's step closures and its architecture/landmark helpers referred back to it, so the builder and its working data (mesh kits, the light-field kit, tree and decor tables) were never freed | The builder lets go of everything but what the round reads (container, waters, foliage material, step names) when its last step finishes or it is aborted | `test_campus_art`: freed after a full build and after an abort; objects flat across three builds. `test_loading` repeated-cancel counts |
| D6 | Home button / call / Control Center during play | Code review | Diagnostics accuracy; render scale | The first frame back spans the whole time away: diagnostics counted it as a multi-second stall, and the render-scale governor could treat it (and the slow frames while iOS restores the surface) as a slowdown | Diagnostics start a fresh interval and mark `app_paused`/`app_resumed` on the timeline; the governor drops the interval, skips three frames and waits for a full 3 s window | `test_diag`, `test_quality_governor` |

Not reproduced here and left as hypotheses for the device diagnostics:
render-time pipeline compilation on Metal (counted per source in the
summary; see the shader-baking export below) and network corrections
(V5's untraced ~1 m corrections are counted and sized by
`Diag.net_sample`).

Where pipelines compile, on this machine's driver (Vulkan on llvmpipe, a
rendered practice round with `--beta-diag`,
`docs/test-data/v6_beta_diag_llvmpipe_round.txt`): during loading, 48
surface, 27 specialization, 7 canvas and 2 mesh pipelines; during the
round, **0 draw-time** and 21 specialization pipelines (the engine builds
specializations in the background while its general shader draws, so they
are not expected to stall a frame). The campus warm-up therefore covers
what the round draws on this driver. Metal compiles its own pipelines, so
this is not evidence for an iPhone; the same counters in the beta's
diagnostics are. (Frame times in that file are software rendering and
mean nothing for a phone.)

## Diagnostics (Settings › Diagnostics (beta))

V6 adds, all bounded and in memory, nothing written to disk, no names,
codes or Game Center IDs in the shared summary:

- **Simulation ticks per frame** per context (1 / 2 / 3+), their script
  time (average/max), and **catch-up spirals** (30+ consecutive frames that
  each ran 2+ ticks; also marked `catchup_spiral` on the timeline).
- **Pipelines compiled** per context by source (canvas, mesh, surface,
  draw, specialization). Draw-time compilations are the ones that can stall
  a frame on a phone.
- **Stall context**: each stall over 50 ms keeps the dozen frames before it
  (interval, ticks, sim time, draw-time pipelines) and its own tick count.
- **Growth**: node, object and orphan counts and static memory every 10 s;
  the summary reports the change since the first sample.

## Steady pace on a hot phone

`QualityGovernor` (added to each round) lowers the 3D render scale one step
(Standard 1.0 → 0.9 → 0.8 → 0.72; Battery Saver 0.8 → 0.72 → 0.65) when the
frame interval's 75th percentile stays 18 % over budget for 3 s, or when iOS
reports a "serious" thermal state; it steps back up only after 20 s at
budget, doubling that wait (up to 2 min) when a step up doesn't hold; no two
changes within 5 s. The UI is 2D and stays at full resolution. MSAA, shadows
and other features are never toggled mid-round (a scale change reallocates
the 3D buffers once and compiles no pipelines). Each change is marked on the
diagnostics timeline. `test_quality_governor`. Device behaviour unmeasured.

## Loading (V6)

- **Preparing campus…** with a bar that follows the steps actually done,
  then **Waiting for players · a/b ready** (or **Starting…**) with an
  indeterminate sweep once this device is ready: a wait on others never
  looks like a frozen bar.
- **Cancel** (practice) / **Leave party** (online) at the top left from
  0.8 s (so a tap carried over from the previous screen can't cancel);
  Back cancels practice. A cancelled round is freed at once; its unfinished
  worker-pool jobs are collected by App when they finish; the next round
  prepares normally.
- The runner loop keeps animating throughout (preparation is sliced into
  short jobs, V4/V5).

## Startup

Pure black `#000000` behind the Idlery Games lockup in the native launch
image and storyboard, Godot's boot splash and the runtime curtain (one
picture through all three handoffs). Readiness-driven exit and the Reduced
Motion fade are unchanged.
