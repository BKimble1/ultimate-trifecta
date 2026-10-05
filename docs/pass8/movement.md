# Pass 8 movement: sprint exhaustion and the jump→dive loop

Both P0 defects came from the shared motor (`game/src/sim/motor.gd`), which
the host, guest prediction, replay after a correction and the bots all run, so
each fix is a motor-state change plus the serialization that carries it.

## 1. Sprint pulsed while held

**Cause.** With Sprint held, the meter drained to zero, sprint stopped, the
regen delay ran out, the meter refilled to `sprint_min_to_start` (15 %) and
sprint started again on its own: a 0.38 s burst about every 1.3 s for as long as the button
or the touch edge-sprint was held. The 1.7 (7) trace shows 22 bursts in 30 s
of one hold ([sprint_hold_trace.png](../media/pass8/movement/sprint_hold_trace.png)).

**Change.** An exhausted latch, `SimPlayer.sprint_exhausted`:

* It is set on the tick the meter reaches zero while sprinting.
* While it is set, holding Sprint runs at normal speed and the meter refills
  (same regen delay and rate as before).
* It clears only when Sprint is **not held** and the meter is back to
  `sprint_rearm_fraction` = **45 %** (the brief asked for 40–50 %). Holding
  Sprint the whole time never clears it, whatever the meter shows.
* On touch, "not held" is the existing edge-sprint release: the thumb eases
  under the exit threshold (`sprint_off` 0.76 of the stick radius) or lifts.
  On a controller or keyboard it is the button up.
* It is bit 3 of the motor flags (`write_motor`/`read_motor`), so guest
  prediction and replay agree with the host, and it resets with the meter on
  respawn and at round start.

No change to speed, acceleration, the camera (the follow camera's FOV only
depends on the cart, so there was never a sprint FOV pulse to remove), root
motion or input latency: a fresh press with the latch clear sprints on the
same tick as before. Bots check the latch too, so they release and re-press
like a player instead of pulsing.

The HUD shows **"Sprint empty · ease off to recharge"** while the latch is
set and Sprint is still held, and the meter tints until it re-arms.

## 2. Repeated jump→dive out-ran the Night Watch

**Cause.** Any jump press made during a dive was buffered and fired on the
landing tick, skipping the 0.32 s landing recovery, and the new jump could
dive again at once, so a tapper chained 8.6 m/s dives with almost no ground
time: 8.05–8.45 m/s sustained, above the Watch's 6.6 m/s. In the 1.7 (7)
pursuit below, the dive loop out-ran the Watch for the whole 25 s.

**Change.**

| Rule | 1.7 (7) | Pass 8 |
|---|---|---|
| Dive speed (`dive_speed`) | 8.6 m/s | **8.0 m/s** |
| Landing recovery (`dive_land_s`) | 0.32 s, skippable | **0.45 s**, not skippable |
| Dives per airborne sequence | unlimited re-press | **one**; presses during a dive do nothing (no lift renewal, no buffered jump) |
| Jump during recovery | a buffered press fired on landing | only a press in the last `jump_buffer_s` (0.13 s) of the recovery is kept, and fires when it ends |

The authored `dive_land` clip was rebuilt to 0.45 s (contact 0–0.10 s,
tuck and plant 0.10–0.28 s, rise into a run-ready lean 0.28–0.45 s), so the
pose and the rule end together (`clip_check`: head and torso clear, step
7.9 cm). Captures, splashes, cart entry, cart bumps and respawns end any dive,
recovery and buffered jump together (`SimPlayer.end_air_actions`).

**Prediction.** Godot's `move_and_slide` floor snap depends on the body's
internal "was on floor" flag, which is not part of the motor state; after a
replay that crossed a dive landing it could disagree with the host for one
tick and snap differently (paired 0.27 m corrections at landings in the guest
prediction test). The snap length is now chosen from the serialized
`on_floor`, which made the guest's dive landings exact: 0 corrections over
25 cm in 25 s of dive spam at 50 ms ± 8 ms and 2 % loss, latch agreement on
every sample.

## 3. Measured on flat ground

`test_p8_movement.gd::test_movement_probe_and_contract`: one runner on the
longest clear straight `test_pursuit` finds on the campus (moved back 80 m
whenever it nears the end, motor state untouched), 25–30 s per scripted input, 60 Hz. Before is build 7's
code (`018b8d0`) with the same probe; after is this branch. Raw numbers:
[movement_before.json](data/movement_before.json),
[movement_after.json](data/movement_after.json).

| Input | Avg m/s before → after | Peak | Dives | Sprint bursts |
|---|---|---|---|---|
| Jog | 4.99 → 4.99 | 5.0 → 5.0 | 0 → 0 | 0 → 0 |
| Sprint held 30 s | 5.82 → **5.18** | 7.4 → 7.4 | 0 → 0 | 22 → **1** |
| Sprint, release, re-press at 50 % | 5.98 → **5.98** | 7.4 → 7.4 | 0 → 0 | 9 → 9 |
| Jump taps 5/s | 7.52 → 5.19 | 8.6 → 8.0 | 36 → 22 | 0 → 0 |
| Jump/dive taps 10/s | 8.45 → 5.52 | 8.6 → 8.0 | 38 → 23 | 0 → 0 |
| Jump/dive taps 10/s + sprint | 8.45 → 5.52 | 8.6 → 8.0 | 38 → 23 | 31 → 6 |
| Best jump/dive chain | 8.05 → **5.23** | 8.6 → 8.0 | 37 → 23 | 0 → 0 |
| Best jump/dive chain + sprint | 8.05 → **5.23** | 8.6 → 8.0 | 37 → 23 | 30 → 6 |
| Run + one dive every 3 s | 5.32 → 5.06 | 8.6 → 8.0 | 9 → 9 | 0 → 0 |

* Releasing and re-pressing Sprint (5.98 m/s) is now the fastest way across
  flat ground, unchanged from 1.7; no dive pattern reaches it, and none
  sustains the Watch's 6.6 m/s.
* A single dive is still a burst to 8.0 m/s and still lands a step ahead of
  jogging.
* Holding Sprint without releasing is slower than before (5.82 → 5.18): the
  auto-restart was free speed for not playing the meter.

**Pursuit** (`test_dive_loop_does_not_out_run_the_watch`, the same
human-like Watch as `test_pursuit`, starting 8 m behind):

| Runner | 1.7 (7) | Pass 8 |
|---|---|---|
| Dive loop + sprint | **escaped** (gap opening at 1.37 m/s) | **caught after 4.5 s** |
| Sprint bursts, re-press at 50 % | caught after 11.1 s | caught after 11.1 s |

The other chase suites (`test_pursuit`, `test_chase_balance`,
`test_routes_bots`) pass unchanged: route times and bot balance never relied
on dive chains.

## 4. Traces

Each image is speed over time (thick), the sprint meter (thin, lower half),
and ticks for sprinting (blue) and the exhausted latch (red), 1.7 (7) on top.

| File | Shows |
|---|---|
| [sprint_hold_trace.png](../media/pass8/movement/sprint_hold_trace.png) | Sprint held 30 s: 22 automatic bursts before; one burst, then the latch holds normal speed while the meter refills to full |
| [sprint_rearm_trace.png](../media/pass8/movement/sprint_rearm_trace.png) | Release and re-press at 50 %: identical before and after |
| [dive_loop_trace.png](../media/pass8/movement/dive_loop_trace.png) | Best jump→dive chain with Sprint held: 8.6 m/s plateaus above the Watch line before; 8.0 m/s dives separated by the 0.45 s recovery after |

## 4b. Gameplay clips (normal speed)

`src/dev/movement_reel_p8.tscn`, recorded by `tools/capture_p8_movement.sh`:
a real offline Practice round as a runner (the real motor, CharacterView,
follow camera and HUD, the bots parked), the same lane and input scripts as
the probe, on build 7's code (`018b8d0`) and on this branch. Godot's Movie
Maker at a fixed 30 fps clock on the Mobile renderer over llvmpipe, 960×540;
the round's load and reveal are cut. Each clip is Sprint held for 12 s, then
jump→dive pressed as fast as it goes with Sprint held for 10 s; the caption
line shows time, speed, meter and the latch. Desktop rendering of scripted
input, **not device footage or frame-rate evidence**.

| File | Shows |
|---|---|
| [p8_movement_before.mp4](../media/pass8/movement/p8_movement_before.mp4) | 1.7 (7): sprint restarts every ~1.3 s while held (7.4 / 5.0 m/s alternating); the dive loop holds 8.6 m/s |
| [p8_movement_after.mp4](../media/pass8/movement/p8_movement_after.mp4) | Pass 8: one 2.5 s burst, then a steady 5.0 m/s run with "exhausted latch" while the meter refills to 100 %; dives at 8.0 m/s, each followed by the 0.45 s landing recovery (1.8 m/s) |
| [p8_movement_side_by_side.mp4](../media/pass8/movement/p8_movement_side_by_side.mp4) | Both at once (left 1.7 (7), right Pass 8), 640×360 each |

## 5. Tests

* `test_p8_movement.gd` (6 tests, 31 checks): the probe and its contract,
  the pursuit, accepted and rejected jump/dive edges one press at a time,
  motor-state round trip and resets, bots re-arming, guest prediction under
  latency and loss.
* `test_p8_sprint_touch.gd`: real touches through `TouchControls` in a
  Practice round. Parked at the stick's edge for 6 s: one burst, then running
  with the meter empty; easing under the exit threshold releases and re-arms;
  pushing to the edge again sprints on the next tick.
