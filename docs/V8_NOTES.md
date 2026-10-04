# V8 implementation notes (version 1.7)

V8 is the "smoother gameplay, stronger animation, sharper art" pass on the
1.6 (6) beta. It was measured first, then fixed in the order the evidence
ranked: frame-time spikes, remote timing, authored animation, contact and
finish, UI motion.

Everything here was measured on desktop Linux: headless (Godot's dummy
renderer: CPU only) or the Mobile renderer on Mesa llvmpipe under Xvfb.
**No iPhone or iPad was available to this work.** Device frame rate,
presentation pacing, GPU time, heat and battery are **unverified**; none of
them is inferred from these numbers. What still needs a device is listed at
the end and in What to Test.

Details: [docs/v8/performance.md](v8/performance.md) (scenario suite,
before/after distributions, attribution, network presentation) and
[docs/v8/motion.md](v8/motion.md) (clips, graph, contact, character finish).
Evidence: [docs/media/v8/](media/v8/README.md).

## Ranking, re-checked against the baseline

The brief's ranking held, with one change of emphasis. The baseline (build 6
code, the V8 gameplay bench) showed **every one of the 15 worst frames of
every run** to be one bot path search on the main thread (24–42 ms each,
69 searches over 8 ms per 3-round run). V6 had bounded the *number* of
searches per tick, but a single search was still a whole frame. That made
#1 (spikes) concrete and moved bot path work to the top of it. Effects and
character work (#2) measured small on the CPU side (fx 0.01 ms, all eight
views 0.8 ms per frame), so they were fixed for correctness and cold-start
cost rather than for average time.

## Defect register

| # | Area | Trigger | Evidence (before) | Cause | Fix | Verification |
|---|---|---|---|---|---|---|
| D1 | Frame spikes | Bots re-planning far goals (chases, cart routes over the lawn) | All 15 worst frames per run were one A* search each, 24–42 ms; a cluster of them about a second apart in round 3 | V6 capped searches per tick at one, but one search on the 320×300 grid is itself 20–40 ms | Searches run on a worker thread (one per grid at a time). Each answer is used on a tick fixed when it was asked (6 ticks later, 2 apart per grid); that tick waits for a slow worker, so seeded rounds stay deterministic. A bot keeps following its current path while the new one is in flight. V6's cache and unreachable-goal memory are kept | `test_path_budget` (answers arrive on the scheduled tick even with a 400 ms worker; the request costs < 2 ms here); route bots 96/96 + 36/36 routes finished; bench: see performance.md |
| D2 | Network presentation | An opponent leaves a client's interest set (> 45 m, or > 90 m / out of sight), then comes back | Reproduced on build 6 by `test_v8_hot_paths::test_pruned_opponent_does_not_linger_as_a_ghost`: the pruned opponent stayed **visible for all 119 frames** after pruning, frozen; on its return it **slid 116 m** from the old spot | Two owners of a view's visibility: the match controller hid it, the view's own `_process` showed it again from its last state the same frame; the stale buffer interpolated from the old place | One owner (`MatchController.view_shown`); a hidden view does no work; a slot back in the snapshots after a gap starts a fresh buffer and its view is cut, not slid | The same test passes: 0 frames shown after pruning, back at its real place (< 1 m) |
| D3 | Remote timing | Jitter, loss, duplicates, bursts | Source: remote render time = `_est_tick - _interp_ticks`, both corrected per snapshot, so it could step backward; the delay came from tick gaps only, not arrival spread | No presentation clock | A jitter buffer: arrival statistics on the session's tick clock, a monotonic presentation clock that slews (−14 %/+12 %) toward its target, the delay rising at once on an underrun and relaxing slowly | `test_v8_timing::test_presentation_clock_monotonic_and_bounded` (0 backward steps, no resync, bounded delay and underruns in three seeded conditions) |
| D4 | Carts | A client's first frames of a cart, or render time older than the buffer | Source: `_cart_rs` returned the newest sample whenever no bracket was found, so a cart showed its newest place and then stepped back | Start-up and underrun shared one fallback | Start-up holds the oldest sample; an underrun extrapolates along the heading for at most 0.1 s, stopped short of walls and bollards, then holds | `test_startup_and_underrun_policies` |
| D5 | Remote extrapolation | Underrun while a remote runner runs at a wall | Source: up to 100 ms along velocity, through anything | — | Only plain grounded running is extrapolated (no airborne arc, dive, tag or state change), stopped 0.35 m short of the first static obstacle (a ray in the client's world), then held | same test (an airborne sample holds; a run at a wall stops ≥ 0.3 m clear) |
| D6 | Local heading | A reconcile moves the local player sideways | `test_correction_offset_does_not_turn_the_body`: read as travel, a 0.5 m correction turned a straight-running body by more than 8° | The view derived its heading from the drawn position, which includes the decaying correction offset | The offset is passed with the render state (`corr`) and excluded from the travel derivative | same test: under 1.5° |
| D7 | Event timing | Another player's splash, tag, bump, coin… | Source: every event's effect played on arrival, ~150–250 ms ahead of where that player is drawn | — | The HUD/haptics part is shown at once; the world beat (effects, positional sound, a coin vanishing, a remote miss) waits for the presentation time to reach the event's tick (≤ 0.5 s), once per event id | `test_remote_beats_follow_the_presentation_time` |
| D8 | Animation LOD | Distant characters at 30 or 120 fps | Source: "every third rendered frame" = 10 Hz at 30 fps, 40 Hz at 120 | Frame-count schedule | An elapsed-time clock (20 Hz at any frame rate), staggered per slot | `test_far_animation_is_elapsed_time_and_staggered` (~40 updates in 2 s at 30, 60 and 120 fps; at most 4 of 8 on one frame) |
| D9 | Effects churn | Every burst; the first crowded moment | Source: a new Gradient per burst, a Curve per emitter, a mesh and ramp per drip emitter, `amount` rewritten (it reallocates the particle buffers and the renderer's multimesh) on every reuse; one emitter of each kind warmed | — | Shared, bounded ramp cache (48, cleared when full; one colour never recolours another burst); one curve and drip mesh; properties written only when they change; a bounded warm-up (3 sets: ≤ 43 emitters); runner drips made at load | `test_fx_reuse_and_bounded_prewarm` (five splashes and a capture at once on warm pools: ≤ 2 new emitters, no new ramp) |
| D10 | Adaptive quality | A sustained slow pace with an idle GPU | Source: any slow window lowered the render scale (blur), whatever the cause; the window was rebuilt and sorted twice a frame | — | A ring window sorted once a frame; the GPU's own timing (the renderer's timestamps) attributes a slow window: CPU-bound windows keep the scale (and are counted in diagnostics), GPU-bound or unknown ones step down as before; thermal still steps down | `test_governor_attributes_the_cause`, `test_governor_ring_window`, the V6 governor tests |
| D11 | Remote recovery | The buffer runs dry (a burst of late or lost snapshots) and data comes back | Probe, 250 ms RTT with 0.3 s bursts: the drawn runner was extrapolated 0.1 s, held, then jumped to its real path (a 0.82 m step in one frame in the unit case) | The underrun policy had no way back but a step | Back from an underrun, the gap between the held place and the real path closes with a 0.12 s time constant (horizontal only; a gap ≥ 3 m, a state change or a re-seen slot still cuts) | `test_startup_and_underrun_policies` (first frame continues from the held place, no step over 0.3 m at 7 m/s, back on the path; fails with the blend off: 0.82 m) |
| D12 | Remote recovery (found in integration, introduced by D2) | Same bursts | Probe: 15 snap frames in the burst condition, 0 recoveries | D2's "re-seen after 18 ticks" rule also fired when *every* slot was missing because snapshots were lost, so a burst cut every remote | A slot is re-seen only if it was missing from snapshots that did arrive | `test_a_loss_burst_is_not_a_re_seen_slot` (fails on the first rule); the ghost test still passes; probe: 0 snap frames |

## Decisions and rejected options

- **Godot physics interpolation** was not turned on: the game interpolates
  its own ticks, and the remote buffer is a separate clock. Turning both on
  would smooth twice and add delay (brief §6).
- **Snapshots stay at 20 Hz.** The jitter buffer measures arrival spread;
  nothing here needed a higher rate.
- **Hermite curves** are used only where safe (both samples active, the
  velocities explain the displacement within 35 cm, no reversal, a bend of
  at most 25 cm, height linear on the floor); elsewhere linear. A/B in
  performance.md.
- **No lag compensation, no change to tag reach, lunge, immunity, capture
  or speeds.** The event split only delays *cosmetic* beats of *other*
  players; stamps, tags and results show at once.
- **Bot path searches**: an incremental (time-sliced) A* in GDScript would
  be several times slower than the native AStarGrid2D it replaces;
  per-tick budgets cannot split one search. A worker with a fixed delivery
  tick keeps the native search, removes it from the main thread, and keeps
  rounds deterministic.
- **CPU particles kept.** Effects cost 0.01 ms per frame on average here;
  nothing pointed at GPU particles.
- **No FSR/TAA/MetalFX, no renderer change.**
- **Additive layers never touch the pelvis** (it moves the planted feet:
  measured 0.36–0.69 m/s of slide in the first version).

RESULTS_PLACEHOLDER
