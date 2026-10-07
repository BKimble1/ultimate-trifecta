# Performance: two maps, before and after

These are desktop numbers from this work's container. They are never a phone's. No iPhone or iPad
was available, so device frame rate, GPU time, heat and memory pressure are **unverified**.
Profile on a device before release.

## How it was measured

- **Machine:** a 4-vCPU Linux container (Intel Xeon at 2.8 GHz, 15 GB RAM) running Godot 4.7.2.
  It is shared and virtualised, so the longest frames vary from run to run. Treat single long
  frames as noise unless they repeat.
- **Builds compared:**
  - Lakeside Campus:
    - *before*: `f4ae758`, the flat-ground campus this pass started from;
    - *after*: `b39ccca`, this pass.
  - Moonbrook College:
    - *before*: `66e7575`, the 2.0 (10) release, where it was the only map;
    - *after*: `b39ccca`, the restored map in this pass.
- **Gameplay bench:** `tools/match_bench.sh OUT.json --map=<id>`.
  - Three Practice rounds of 75 s through the real App flow (loading, results, menu between
    rounds), with all 8 slots bot-driven.
  - 60 fps cap, seed 7, quality 1 (Standard), the game's own follow camera on the local runner.
  - Headless: CPU only, with a dummy renderer.
  - Two runs per build, interleaved in one session. Tables show the median and, in brackets, the
    range.
  - `tools/bench_summary.py` builds the tables. The raw JSON is in the session's evidence, not the
    repository.
- **Draw cost:** the same bench with `RENDER=1`: one round, windowed at 1280×720 on llvmpipe (software
  rendering) under Xvfb. It samples draw calls and primitives once a second while playing. These are
  counts, not timings.

## Moonbrook College (2.0 vs this pass)

| | 2.0 (`66e7575`) | This pass (`b39ccca`) |
|---|---|---|
| Frame interval p50 / p95 / p99 | 16.66 / 18.03 / 19.72 ms | 16.66 / 18.06 / 19.90 ms |
| Longest frame | 51 ms (43–58) | 60 ms (58–61) |
| Frames over 33 ms (in 13,500) | 5 (4–6) | 4 (3–5) |
| Frames over 50 ms | 1 (0–2) | 2 |
| Simulation tick mean / p99 | 2.59 / 4.89 ms | 2.60 / 5.02 ms |
| Bots mean / p99 | 0.91 / 2.04 ms | 0.99 / 2.32 ms |
| Nodes in a round | 1,793 | 1,901 |
| Static memory | 273 MB (255–285) | 300 MB (282–313) |
| Host collision shapes | not recorded | 712 |
| First round: prepared in | not recorded | 1.97 s over 116 frames |
| First round: longest loading job | not recorded | 26 ms (20–32) |
| Longest loading frame | 33–44 ms | 41–43 ms |
| Later rounds (map kept): prepared in | not recorded | 0.11 s |
| Longest menu frame (leaving the results) | 119–121 ms | 105–153 ms |

The restored map plays like 2.0. The median and p95 frames are the same. The p99 is 0.2 ms higher:
the bots do slightly more work on the shared navigation code (path search, slopes, route fields),
which is now map-agnostic.

The run-to-run noise on this machine is larger than the differences in the longest frames. While
looking for a 39–64 ms bot spike in an earlier run, three identical seeded probe runs gave 2, 4, 9
and then 0 slow bot decisions. The slow ones fell in code that does almost no work, which fits the
shared VM pausing the process rather than a code path. That is not proven.

## Lakeside Campus (flat ground vs this pass)

LAKESIDE_TABLE

## Draw cost (llvmpipe, counts only)

DRAW_TABLE

## What this pass changed for performance

- **Loading.**
  - The round's collision bodies are built in slices (the "bodies" job).
  - The collision recipe's rest is built in five slices.
  - `CampusLayout.stair_y` uses a coarse cell index:
    - same answers as the old scan (0 mismatches in 312,000 samples);
    - about 9× faster.
    - Without it, every ground-following collider asked all 28 stairs, and that held two loading
      steps 57–62 ms.
  - Background trunks more than 30 m outside the play area are drawn only (no collider).
  - The woodland understory is drawn only.
  - Ground-mesh heights and area draping are faster.
  - Nav-grid roads and points are built in quarters: 26 slices, the longest about 26 ms.
  - Moonbrook's art layout (its tree scatter) is built on a worker thread. In the first campus step it
    held one frame 90–167 ms.
- **Between rounds.** The round's collision bodies are kept for the next round on the same map, as
  the campus look already was:
  - About 5,700 shapes on the campus.
  - Freeing them as a round ended held the frame leaving the results 0.8 s.
  - The next round then built them all again.
  - Taking them out of the tree costs about 3 ms; putting them back costs about 10 ms.
  - Another map's kept bodies are freed during loading, 400 shapes a step.

## Not measured, or open

- **Any device.** iPhone and iPad frame pacing, GPU time, thermal throttling, memory warnings. The
  campus has about 4.5× the nodes of Moonbrook.
- **Static memory.** It is up by 60 MB on the campus (the kept collision bodies, terrain and the
  parked fleet). Watch memory warnings on a 4 GB device.
- **The first campus round's cold load (about 9 s on this machine).** It runs under the animated
  loading screen, with the longest step about 36 ms. On a phone it will be longer; the step budget
  follows a slow device (`test_loading`).
- **The frame leaving the results (about 0.26 s on the campus).** It now spends no time on the
  collision bodies. It still frees the round's characters, HUD and simulation in one frame. The 2.0
  map takes 0.1–0.15 s.
