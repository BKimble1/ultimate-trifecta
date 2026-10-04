# V8 performance and timing

Reproducible measurements behind the V8 hot-path and timing work, before
(build 6 code) and after (V8), under the same conditions. **Every number
here is this desktop machine's, never a phone's**: a shared 4-core x86-64
Linux container, Godot 4.7.2. Headless runs use Godot's dummy renderer, so
they time the CPU side of a frame (script, simulation, animation, physics
queries) and nothing on the GPU. No iPhone or iPad was available to this
work, so **device frame rate, GPU time, heat and battery are unverified**.

## The scenario suite

`tools/match_bench.sh` runs `game/src/dev/match_bench.tscn`: whole Practice
rounds through the real App flow (Practice start → loading screen → round →
results → menu → next round), 8 slots, **every slot bot-driven** (the local
runner too, by the same `BotBrain` as the bots), so each round has crowded
chases, splashes of every kind, tags, captures, carts, coins, finishes and
confetti. The engine runs on the real clock with a frame cap (`--fps`), like
a phone on Standard (60) or Battery Saver (30, with the Battery preset).
Three rounds of 75 s of play per run, seed 7 (rounds use seeds 8, 9, 10:
the same campus, targets, coins and bot decisions on both builds).

Per frame it records the engine-loop interval (time between the bench's
own first-in-frame callbacks), the physics ticks run, and the CPU time of
each instrumented section: the match controller's event, view, world,
camera and HUD passes; each character's view work and AnimationTree
advance; the skeleton modifiers (pose fade, secondary motion, foot lock);
effects; the quality governor; and the simulation's own sections
(`MatchSim.prof`: bots, intents, movement, carts, rules, perception). It
lists the events each frame presented and any bot path search over 8 ms.
Instrumentation (`Prof`) is off in normal play: a hook costs one static read.

Before = commit `cb3c48a` (build 6's game code plus the measurement hooks
only) in its own worktree; after = `01277a9` in its own worktree. Both ran
back to back on the same machine with nothing else running.

Summaries: `tools/bench_summary.py docs/v8/data before_std60 after_std60 before_bat30 after_bat30`.
Raw per-run JSON: `docs/v8/data/{before,after}_{std60,bat30}_run{1,2,3}.json`.

## Results (engine-loop intervals in ms; median of 3 runs, range in brackets)

Headline rows (Standard = 60 fps cap with the Standard preset, Battery =
30 fps cap with the Battery Saver preset; 13,500 / 6,750 playing frames per
run):

| | Standard before | Standard after | Battery before | Battery after |
|---|---|---|---|---|
| p50 | 16.66 | 16.66 | 33.33 | 33.33 |
| p95 | 17.91 | 17.79 | 35.89 | 35.41 |
| **p99** | **21.52** (21.07–21.64) | **19.01** (18.99–19.29) | **43.28** (42.87–44.12) | **37.07** (37.02–37.11) |
| longest stall | 57.1 (56.0–169.7) | 68.3 (49.3–105.2) | 97.0 (89.8–147.3) | 59.4 (55.8–75.8) |
| frames > 33.3 | **43** (42–44) | **5** (4–9) | n/a at a 30 fps cap | n/a |
| frames > 50 | 4 (2–5) | 2 (0–2) | **42** (41–48) | **2** (1–4) |
| frames > 100 | 0 (0–1) | 0 (0–1) | 0 (0–1) | 0 |
| simulation tick p99 | 6.31 | 4.20 | 14.99 | 7.25 |
| simulation tick max | 42.3 | 24.9 | 67.7 | 18.6 |
| bot thinking max | 40.9 | 7.9 | 58.8 | 9.1 |
| path searches > 8 ms | 68, on the main thread | 80, on a worker; **0 waits** | 69, main thread | 82, worker; 0 waits |

At a 30 fps cap the interval sits at 33.3 ms, so "> 33.3" counts on-time
frames; Battery is judged by > 50 and the percentiles.

**The machine's own noise floor** (`src/dev/idle_bench.tscn`: an empty
scene, same 60 fps cap, 180 s, `docs/v8/data/idle_noise_60.json`): p99
17.0 ms, 2 frames over 33.3 ms and 1 over 50 ms (56.7 ms). The few long
frames left after V8 (4–9 over 33.3 ms in 225 s of play) are within a few
times that rate, and the bench attributes at most two of each run's 15
worst frames to nothing inside the game (`worst-15 frames not explained`
below); the build-6 longest stalls of 147–170 ms were of that unexplained
kind too (a 169.7 ms frame with 12 ms of game work in it). Neither build's
"longest stall" is therefore a game measurement; the counts and p99 are.

**Attribution.** In build 6 every one of the 15 worst frames of every run
was a single bot path search (24–42 ms) inside one simulation tick; at 30
fps two ticks per frame stacked them (up to 58.8 ms of bot thinking in one
frame). V8 runs those searches on a worker: the same searches still take
up to 50 ms there, the main thread never waited for one (2.4–3.1 ms of
`wait_for_task_completion` bookkeeping over a whole run), and the bot
decisions are identical in all six V8 runs (589 searches, 1,251 cache
hits, 1,623 direct lines, 3,198 unreachable answers each), as designed.

**What got more expensive.** Character work rose by about 0.2 ms per
frame for eight characters (views 0.80 → 1.00 ms mean; AnimationTree 0.23
→ 0.32 ms: the drive/brake/lead layers and the stop one-shot are three
Add2 nodes and a one-shot more per character; foot lock 0.09 → 0.14 ms:
terrain contact). It is within the frame budget here and far below what
the path searches cost, but it is real and is the first place to look if
a device shows character cost.

**Events.** No presented event cost more than 3.1 ms of CPU on either
build (`ev_*` sections); the first splash, tag and confetti of a round
were not stalls on this machine's CPU. GPU-side first use (pipeline
compilation) cannot be measured headless; the V6 shader baking and
warm-up are unchanged, and V8 warms more emitters per kind.

**Memory and objects across rounds** (`round_starts`): objects, nodes and
orphan nodes are flat from round 2 (no orphans in any run); static memory
rises about 8–12 MB per round over three rounds on both builds alike. The
ten-round run below checks whether that settles.

<details><summary>Every section, both presets (tools/bench_summary.py)</summary>

| metric | before_std60 (3 runs) | after_std60 (3 runs) | before_bat30 (3 runs) | after_bat30 (3 runs) |
|---|---|---|---|---|
| p50 | 16.66 (16.66-16.67) | 16.66 (16.66-16.67) | 33.33 (33.32-33.33) | 33.33 (33.32-33.33) |
| p95 | 17.91 (17.87-17.92) | 17.79 (17.78-17.81) | 35.89 (35.84-35.95) | 35.41 (35.39-35.49) |
| p99 | 21.52 (21.07-21.64) | 19.01 (18.99-19.29) | 43.28 (42.87-44.12) | 37.07 (37.02-37.11) |
| max | 57.05 (55.96-169.73) | 68.31 (49.30-105.15) | 97.01 (89.82-147.26) | 59.38 (55.78-75.78) |
| >33.3 | 43 (42-44) | 5 (4-9) | 3499 (3497-3506) | 3520 (3490-3533) |
| >50 | 4 (2-5) | 2 (0-2) | 42 (41-48) | 2 (1-4) |
| >100 | 0 (0-1) | 0 (0-1) | 0 (0-1) | 0 |
| clusters | 43 (40-44) | 5 (4-9) | 2122 (2119-2133) | 2149 (2131-2180) |
| longest cluster ms | 84.62 (55.96-169.73) | 68.31 (49.30-105.15) | 203.25 (202.22-235.81) | 236.33 (203.07-242.88) |
| frames | 13497 (13489-13500) | 13503 (13497-13504) | 6751 (6749-6751) | 6751 (6750-6752) |
| tick mean ms | 2.32 (2.29-2.38) | 2.30 (2.28-2.38) | 4.39 (4.37-4.40) | 4.14 (4.06-4.18) |
| tick p99 ms | 6.31 (6.30-6.55) | 4.20 (4.19-4.25) | 14.99 (14.08-15.45) | 7.25 (7.08-7.60) |
| tick max ms | 42.27 (41.85-42.64) | 24.85 (24.36-36.73) | 67.67 (53.37-73.50) | 18.61 (16.28-24.60) |
| sim_bots mean ms | 0.86 (0.85-0.88) | 0.77 (0.77-0.80) | 1.67 (1.66-1.67) | 1.43 (1.38-1.43) |
| sim_bots p99 ms | 4.38 (4.34-4.55) | 1.78 (1.77-1.83) | 11.31 (10.86-11.41) | 3.24 (3.22-3.33) |
| sim_bots max ms | 40.85 (39.92-41.24) | 7.85 (4.25-8.97) | 58.77 (51.09-62.52) | 9.06 (6.26-11.33) |
| sim_move mean ms | 0.43 (0.43-0.44) | 0.44 (0.44-0.45) | 0.83 (0.82-0.84) | 0.83 (0.81-0.84) |
| sim_move p99 ms | 0.84 (0.82-0.84) | 0.87 (0.84-0.91) | 1.52 (1.44-1.62) | 1.59 (1.56-1.74) |
| sim_move max ms | 7.38 (4.55-11.38) | 13.05 (8.11-22.34) | 7.32 (5.82-29.45) | 9.57 (7.98-10.93) |
| sim_carts mean ms | 0.31 (0.31-0.32) | 0.33 (0.33-0.34) | 0.57 (0.57-0.58) | 0.58 (0.57-0.59) |
| sim_carts p99 ms | 0.61 (0.61-0.63) | 0.64 (0.62-0.64) | 1.06 (1.05-1.08) | 1.10 (1.09-1.12) |
| sim_carts max ms | 4.90 (4.65-5.76) | 8.94 (6.16-10.67) | 5.36 (5.30-8.33) | 6.37 (5.58-14.10) |
| sim_rules mean ms | 0.22 (0.22-0.23) | 0.23 (0.23-0.24) | 0.43 (0.42-0.43) | 0.42 (0.41-0.43) |
| sim_rules p99 ms | 0.43 (0.43-0.45) | 0.47 (0.46-0.48) | 0.83 (0.78-0.83) | 0.82 (0.80-0.93) |
| sim_rules max ms | 12.61 (4.35-15.85) | 17.80 (5.77-32.87) | 9.23 (5.49-33.76) | 4.68 (4.41-8.72) |
| views mean ms | 0.80 (0.79-0.83) | 1.00 (0.98-1.03) | 0.84 (0.84-0.85) | 1.12 (1.10-1.12) |
| views p99 ms | 1.46 (1.42-1.49) | 1.82 (1.79-1.83) | 1.50 (1.48-1.53) | 1.98 (1.94-2.13) |
| views max ms | 15.07 (6.24-15.15) | 8.30 (7.82-10.76) | 11.23 (6.75-11.36) | 7.71 (6.94-18.43) |
| anim_advance mean ms | 0.23 (0.22-0.23) | 0.32 (0.31-0.33) | 0.23 (0.23-0.23) | 0.39 (0.39-0.39) |
| anim_advance p99 ms | 0.45 (0.43-0.47) | 0.62 (0.61-0.64) | 0.44 (0.43-0.44) | 0.71 (0.69-0.76) |
| anim_advance max ms | 3.39 (2.99-3.73) | 4.32 (3.80-10.04) | 3.92 (2.25-5.55) | 4.53 (3.45-4.64) |
| mod_footlock mean ms | 0.09 (0.09-0.10) | 0.14 (0.14-0.14) | 0.09 (0.09-0.09) | 0.14 (0.14-0.14) |
| mod_footlock p99 ms | 0.20 (0.20-0.22) | 0.31 (0.31-0.31) | 0.19 (0.19-0.20) | 0.32 (0.32-0.34) |
| mod_footlock max ms | 2.36 (2.15-6.24) | 2.41 (2.36-3.41) | 1.31 (1.22-1.83) | 4.37 (2.36-4.37) |
| mod_secondary mean ms | 0.08 (0.08-0.08) | 0.08 (0.08-0.08) | 0.09 (0.09-0.09) | 0.09 (0.09-0.09) |
| mod_secondary p99 ms | 0.17 (0.17-0.17) | 0.17 (0.17-0.18) | 0.18 (0.18-0.18) | 0.18 (0.17-0.20) |
| mod_secondary max ms | 2.19 (2.17-3.51) | 3.22 (2.11-4.21) | 2.32 (1.33-2.44) | 1.68 (1.16-12.80) |
| mod_posefade mean ms | 0.04 (0.04-0.04) | 0.04 (0.04-0.04) | 0.04 (0.04-0.04) | 0.04 (0.04-0.04) |
| mod_posefade p99 ms | 0.09 (0.09-0.10) | 0.09 (0.09-0.10) | 0.09 (0.09-0.09) | 0.09 (0.09-0.10) |
| mod_posefade max ms | 2.00 (1.83-4.23) | 1.87 (1.64-7.94) | 0.78 (0.40-2.12) | 2.10 (1.10-2.15) |
| mc_apply mean ms | 0.27 (0.26-0.28) | 0.29 (0.28-0.30) | 0.28 (0.28-0.28) | 0.29 (0.29-0.29) |
| mc_apply p99 ms | 0.48 (0.47-0.49) | 0.53 (0.52-0.53) | 0.49 (0.47-0.50) | 0.51 (0.50-0.56) |
| mc_apply max ms | 5.64 (5.51-70.44) | 5.91 (5.25-6.36) | 4.42 (2.48-5.59) | 4.26 (2.90-4.83) |
| mc_events mean ms | 0.00 (0.00-0.00) | 0.01 (0.01-0.01) | 0.01 (0.01-0.01) | 0.01 (0.01-0.01) |
| mc_events p99 ms | 0.01 (0.01-0.01) | 0.03 (0.03-0.03) | 0.07 (0.06-0.07) | 0.07 (0.07-0.07) |
| mc_events max ms | 1.43 (1.11-1.60) | 1.35 (1.22-2.50) | 1.23 (1.22-1.58) | 3.00 (2.10-3.07) |
| mc_world mean ms | 0.12 (0.12-0.13) | 0.13 (0.13-0.14) | 0.13 (0.13-0.13) | 0.13 (0.13-0.13) |
| mc_world p99 ms | 0.25 (0.24-0.25) | 0.26 (0.25-0.27) | 0.26 (0.25-0.27) | 0.26 (0.26-0.26) |
| mc_world max ms | 4.33 (2.06-5.55) | 3.01 (2.32-3.34) | 3.39 (3.23-4.82) | 5.14 (1.53-7.34) |
| mc_camera mean ms | 0.11 (0.11-0.12) | 0.12 (0.12-0.12) | 0.12 (0.11-0.12) | 0.11 (0.11-0.12) |
| mc_camera p99 ms | 0.23 (0.23-0.24) | 0.24 (0.24-0.24) | 0.23 (0.23-0.24) | 0.23 (0.23-0.24) |
| mc_camera max ms | 7.81 (3.55-9.07) | 2.42 (2.24-3.26) | 1.77 (1.72-15.75) | 2.21 (2.01-2.36) |
| hud_refresh mean ms | 0.27 (0.26-0.28) | 0.28 (0.28-0.29) | 0.28 (0.28-0.28) | 0.28 (0.28-0.29) |
| hud_refresh p99 ms | 0.55 (0.54-0.57) | 0.59 (0.58-0.59) | 0.57 (0.56-0.58) | 0.62 (0.58-0.63) |
| hud_refresh max ms | 5.64 (5.43-18.42) | 14.80 (5.71-17.91) | 4.38 (4.00-5.59) | 4.52 (3.30-5.23) |
| fx mean ms | 0.01 (0.01-0.01) | 0.01 (0.01-0.01) | 0.01 (0.01-0.01) | 0.01 (0.01-0.01) |
| fx p99 ms | 0.03 (0.03-0.03) | 0.03 (0.03-0.03) | 0.03 (0.03-0.03) | 0.03 (0.03-0.03) |
| fx max ms | 0.55 (0.46-15.12) | 0.71 (0.28-1.27) | 0.18 (0.12-0.62) | 0.21 (0.07-0.41) |
| path searches > 8 ms (build 6: on the main thread; V8: on a worker) | 68 (67-69) | 80 (79-81) | 69 (69-74) | 82 (81-87) |
| main thread waited for a worker search | (searched on the main thread) | 0 waits, 3.12 (2.94-3.12) ms | (searched on the main thread) | 0 waits, 2.40 (2.39-2.54) ms |
| worst-15 frames not explained by any section | 2 (0-3) | 1 (0-2) | 2 (1-2) | 1 (0-2) |


</details>

## Confirmation on the final code

The table above compares `cb3c48a` with `01277a9`. The final game code
(`5e96387`) adds the underrun recovery, the loss-burst fix, hidden idle
emitters and the filtered layers. It was benched twice more (Standard, the
same seeds; `docs/v8/data/final_std60_run{1,2}.json`) **on a different
machine**: the session's worker was restarted onto a host whose CPU
sections all measure ~30 % faster (tick mean 1.56 ms vs 2.30), so these runs
confirm the shape, not the size, of the result and are not set against
build 6.

| | run 1 | run 2 |
|---|---|---|
| p95 / p99 | 17.20 / 18.07 | 17.21 / 18.07 |
| frames > 33.3 / > 50 / > 100 | 1 / 1 / 1 | 0 / 0 / 0 |
| worst frame | 191.2 ms (round 1, frame 1) | 32.8 ms |
| bot thinking, worst frame | 6.3 ms | 15.8 ms |
| main thread waited for a worker search | 0 times | 0 times |

The 191 ms frame is the first frame of play of the first round of the first
run after the machine started; instrumented game work in it was ~12 ms
(six catch-up ticks included). It did not recur in run 2. That fits a cold
disk cache, but the cause was not traced, so it is listed as open: a phone
on its first round after a cold start could see such a read too.

Run 2's worst frame (32.8 ms) spent 15.8 ms in bot thinking in one tick,
more than any earlier V8 run (4.3–9.0 ms) although this machine is faster.
It did not wait for a path search (0 waits; the same 589 searches as every
V8 run); the bench does not break bot thinking down further, so this frame
is not attributed. It is listed as open.

**HUD refresh.** A few frames per run spend 15–21 ms refreshing the HUD
(V8 runs: 14.8, 17.9, 21.4 ms; build 6's section maximum was 18.4 ms, so it
is not new). Those frames stayed under 33.3 ms here; the cause (possibly
first use of glyphs at a size) is not attributed.

## Draw calls (desktop render)

`RENDER=1 tools/match_bench.sh … --rounds=1 --round-secs=40 --seed=7`: the
same bench on the Mobile renderer over llvmpipe under Xvfb at 1280×720,
sampling the renderer's own counters about once a second (37 samples).
llvmpipe draws a frame in about 2 s, so these runs say nothing about frame
time; they count what is submitted.

| | draw calls, mean (min–max) | objects, mean (max) | primitives, mean |
|---|---|---|---|
| build 6 (`cb3c48a`) | 243 (196–298) | 323 (486) | 369,611 |
| V8, first measurement | 256 (192–316) | 338 (504) | 355,093 |
| V8, final code (`5e96387`) | **236** (191–275) | 318 (463) | 354,328 |

The first V8 measurement showed 18 more draw calls than build 6 on average
and from the very first sample. At that first sample the first and the final
V8 runs show the same view (the same 456,463 primitives): 316 draw calls and
504 objects before the fix, 275 and 463 after it, so 41 draw calls were idle
emitters. They were the warmed effect pool (V8 warms three
sets, up to 43 emitters, below the campus, where a camera looking down
still has them in its frustum) and the runners' drip emitters made at load:
an idle CPU particle emitter is still a rendered object. Idle emitters are
now hidden until they fire and hide again when their last particle dies
(`test_v8_hot_paths`). Build 6 drew its smaller warmed set the same way;
with them hidden, V8 averages 236 draw calls against build 6's 243
(`docs/v8/data/render_{before,after,final}.json`). Primitives are lower in V8 on average because the
scenes differ: build 6 answered a bot's path search at once, V8 six ticks
later, so the bots (and the followed camera) take different routes. Nothing
was simplified.
The heaviest character look is still 7 draw calls (motion.md).

## Network presentation

`src/dev/net_motion_probe.tscn` (V5, extended in V8): a host and one
predicting client over the in-process loopback hub (the real `NetSession`,
protocol, prediction, reconciliation and the client's own
`MatchController`), 12 s of play per condition on a fixed 60 fps clock. It
reports what the client *draws* for the remote characters: the displayed
delay, frames drawn past the newest snapshot (underrun), frames
extrapolating, the drawn time stepping backward, the distance from the
host's own path at the drawn time (p95), the acceleration noise of the
nearest remote character's drawn path (rms of its second difference; frames
over 400 m/s² are counted separately as one-frame jumps, and a teleport of
2.5 m or more is neither), and snaps (a remote more than 15 cm off its
velocity path in one frame). Loopback conditions are seeded test inputs,
**not** measurements of Game Center links. Data:
`docs/v8/data/net_probe_{before,after}.json`.

Build 6's hub had no duplicates or bursts, so for those two conditions the
"before" column is the same latency, jitter and loss *without* them: not
like for like, and no comparison is drawn from those rows.

| condition | build 6: delay p50/p95 ms | underrun frames | extrapolating | jumps | accel rms | V8: delay p50/p95 ms | underrun frames | extrapolating | jumps | snaps | accel rms | recoveries |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| clean | 117 / 117 | 0 | 0 | 0 | 20.3 | **54 / 89** | 0 | 0 | 0 | 0 | 20.3 | 0 |
| 80 ms RTT, 8 ms jitter | 117 / 117 | 0 | 0 | 0 | 20.2 | **74 / 85** | 0 | 0 | 0 | 0 | **18.4** | 0 |
| 300 ms RTT, 30 ms jitter, 10 % loss | 123 / 136 | **117** | **585** | 3 | 46.7 | 197 / 201 | **2** | **10** | 0 | 0 | **24.6** | 9 |
| 160 ms RTT, 25 ms jitter, 3 % loss, 5 % duplicates | (no duplicates) 117 / 125 | 5 | 25 | 0 | 31.5 | 152 / 159 | 3 | 15 | 2 | 0 | 24.8 | 14 |
| 250 ms RTT, 40 ms jitter, 5 % loss, 0.3 s outage every 4 s | (no outages) 128 / 150 | 47 | 235 | 0 | 59.1 | 342 / 354 | 16 | 80 | 4 | 0 | 25.9 | 20 |

Every V8 run: **0 backward steps** of the drawn time, **0 resyncs**, error
against the host's path p95 0.25 m (build 6: 0.25–0.26). Build 6 drew every
remote a fixed ~117 ms behind whatever the link did; V8 sizes the delay from
the measured arrival spread, so it is about half that on a clean link, and
more on a bad one in exchange for far fewer frames with nothing to draw (10 %
loss: 117 underrun frames → 2). With 0.3 s outages the delay reaches the 20
tick ceiling (≈ 340 ms) and underruns remain; the recovery blend (D11) closes
each gap without a snap, and a burst no longer cuts every remote (D12: 15
snap frames in that condition before the fix).

**Hermite or linear.** The same runs with `--interp=linear`:

| condition | accel rms Hermite / linear | error p95 Hermite / linear | jumps Hermite / linear |
|---|---|---|---|
| clean | 20.3 / 23.2 | 0.252 / 0.251 | 0 / 0 |
| 80 ms RTT | 18.4 / 23.1 | 0.251 / 0.251 | 0 / 0 |
| 160 ms RTT, loss, duplicates | 24.8 / 26.1 | 0.252 / 0.252 | 2 / 2 |
| 250 ms RTT, outages | 25.9 / 26.3 | 0.256 / 0.259 | 4 / 5 |
| 300 ms RTT, 10 % loss | 24.6 / 25.7 | 0.252 / 0.251 | 0 / 0 |

The curve is smoother in every condition at the same error, so it stays on
(only where its safety checks pass: see V8_NOTES "Decisions").

**What the acceleration column does and doesn't say.** In the loss
conditions V8's rms is higher with the recovery blend than without it (an
earlier V8 run without it: 18.3 at 160 ms RTT), because a hold followed by
a jump had been *excluded* as a cut (over 400 m/s²) and the blend is a
counted catch-up instead. The jump column is the honest pair to it.

## Ten rounds back to back (lifecycle)

`tools/match_bench.sh … --rounds=10 --round-secs=20 --seed=21`, V8, each
round through results and the menu into the next. Read at each round start
(`docs/v8/data/after_cycles10.json`; `after_cycles10_lifecycle.json` is the
same run with `--lifecycle`, which keeps no per-frame records):

| round | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| nodes | 1,652 | 1,653 | 1,653 | 1,653 | 1,655 | 1,653 | 1,653 | 1,653 | 1,657 | 1,653 |
| orphan nodes | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| objects | 5,722 | 5,848 | 5,852 | 5,855 | 5,861 | 5,860 | 5,873 | 5,878 | 5,883 | 5,880 |
| static MB (lifecycle mode) | 241.0 | 241.2 | 241.3 | 241.3 | 241.4 | 241.4 | 242.1 | 242.2 | 242.2 | 242.2 |

With per-frame records kept, static memory rose ~3.3 MB a round; without
them, 1.2 MB over nine rounds. The rise in the three-round runs above was
therefore mostly the bench's own records (~2.5 KB a frame). Nodes are flat
and no node is ever orphaned. Objects rise by about 4 a round (32 over
rounds 2–10); that has **not** been attributed. A bounded cache filling
(V8's colour-ramp cache holds at most 48) would look like this, but it was
not checked, so it is listed as open in V8_NOTES. The playing frames of the
first ten-round run (p99 19.1 ms, 3 over 33.3 ms) agree with the three-round
runs; the lifecycle run's frame times are not used (another probe shared
the CPU during it).


