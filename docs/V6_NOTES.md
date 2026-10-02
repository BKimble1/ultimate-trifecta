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
| D3 | App start | Owner request | Startup | V5 used navy behind Idlery Games | Pure black `#000000` in the launch image, the launch storyboard, Godot's boot splash and the curtain; the CI audit fails on anything else | `test_boot_branding`; the audit passes on a local Godot 4.7.2 iOS export and fails when the storyboard colour is put back to navy |

Further items (loading freeze, render-time compilation, lifecycle) are
added as they are measured.

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

## Startup

Pure black `#000000` behind the Idlery Games lockup in the native launch
image and storyboard, Godot's boot splash and the runtime curtain (one
picture through all three handoffs). Readiness-driven exit and the Reduced
Motion fade are unchanged.
