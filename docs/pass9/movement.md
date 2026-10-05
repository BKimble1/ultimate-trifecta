# Pass 9 movement: one steady full speed, no stamina

The brief asked for the sprint meter to be removed entirely. Full stick input
should give one steady, fair top speed on touch, controller and keyboard, and
the whole match should be re-measured afterwards.

The motor (`game/src/sim/motor.gd`) is shared by the host, guest prediction,
replay after a correction and the bots, so the change is a motor-state change
plus the serialization that carries it (protocol 8).

All numbers below come from **simulation**: headless Godot 4.7.2 at 60 Hz on
desktop Linux, using the real motor, physics, campus and bots. None of it is
device or human-playtest evidence (see the "Not measured here" section).

## 1. What changed

| | 1.8 (8) | 1.9 (9) |
|---|---|---|
| Runner, full stick input | 5.0 m/s | **6.0 m/s, for as long as it is held** |
| Sprint | 7.4 m/s from a 2.5 s meter. It refilled in 3.6 s after a 0.35 s delay. A Pass 8 latch kept it off once the meter ran dry until release and a 45 % refill | **removed**: no button, meter, recharge, latch, edge sprint or setting |
| Night Watch, full stick input | 6.6 m/s | 6.6 m/s (unchanged; §4) |
| Walk / jog | the same analog curve below the top speed | the same curve. Touch reaches full at 90 % of the stick radius |
| Dive | 8.0 m/s, one per jump, 0.45 s landing recovery, 0.13 s end-of-recovery jump buffer | unchanged |
| Turbo | ×1.25 for 3 s, capped at 8.0 (6.25 m/s alone, 8.0 with sprint) | ×1.25 for 3 s, capped at 8.0 (**7.5 m/s**) |
| "Fast" (footsteps, expressions, bots, animation) | `sprinting` (meter in use) | `fast`: on the floor, not diving, and at or above 85 % of the role's full speed, from the **actual** velocity |
| Footstep noise | sprint 24 m, run/jog 14 m, under 3.2 m/s silent | full speed 24 m, jog 14 m, under 3.2 m/s silent |
| Protocol | 7 | **8** (motor state and snapshot flags changed). Older or newer builds are refused at join with "Update the game to join." |

**Removed from the live game:**

- the HUD meter and the "Sprint empty · ease off to recharge" hint;
- the Sprint touch button and edge sprint;
- Settings › Sprint;
- the Sprint key and controller button;
- the sprint lines in How to Play and the tutorial (the tutorial now says
  "Full speed: push the stick all the way out. You can keep it up as long as
  you like.").

The lobby's "Try moves" tiles are now Jog and Full speed.

`TC.BTN_SPRINT` (bit 2) is retired and never reused. The motor ignores it, so
an old binding or client cannot add speed. When a saved profile loads,
`sprint_mode`, `sprint_threshold` and `touch_sprint` are dropped. Every other
setting and the custom touch layout are kept (`test_profile`).

**Noise is a deliberate choice.** A runner at full speed is now as loud as a
1.8 sprint (24 m). A 1.8 runner holding the stick at 5.0 m/s was heard at
14 m. Stealth now means easing off: a jog is heard at 14 m and a walk is
silent. The Watch's information about a runner moving flat out is the same as
before. A runner who wants quiet pays for it with speed.

## 2. Steady speed on every device path

### The probe

Runs on both builds, over the same lane and with the same input scripts:
`tests/test_p9_movement.gd`, data in `data/movement_1.8.json` and
`data/movement_1.9.json`.

A "drop tick" is a tick after the start more than 3 % under full speed while
the input is full. "Fast" is time classified fast (on 1.8 this is the time
spent sprinting).

| Scenario (simulated, open straight) | 1.8 avg m/s | 1.8 peak | 1.9 avg | 1.9 peak | 1.9 slowest settled tick | 1.9 drop ticks | 1.9 "fast" |
|---|---|---|---|---|---|---|---|
| walk, 30 % input (20 s) | 1.50 | 1.50 | 1.80 | 1.80 | – | 0 | 0 s |
| jog, 60 % input (20 s) | 3.00 | 3.00 | 3.59 | 3.60 | – | 0 | 0 s |
| full input held 60 s | 5.00 | 5.00 | **5.99** | 6.00 | **6.00** | **0** | 59.9 s |
| full input + old Sprint held 60 s | 5.09 | 7.40 | 5.99 | 6.00 | 6.00 | 0 | 59.9 s |
| full input, diagonal stick (30 s) | 4.99 | 5.00 | 5.99 | 6.00 | 6.00 | 0 | 29.9 s |
| full input, direction wobble ±4° (30 s) | 4.99 | 5.00 | 5.98 | 6.00 | 6.00 | 0 | 29.9 s |
| Sprint release / re-press at 50 % (the Pass 8 best) | 5.98 | 7.40 | 5.99 | 6.00 | 6.00 | 0 | 29.9 s |
| jump whenever possible (25 s) | 4.97 | 5.00 | 5.96 | 6.00 | 6.00 | 0 | 0.6 s |
| jump/dive taps 10/s | 5.52 | 8.00 | 5.65 | 8.00 | – | 0 | 1.1 s |
| best jump/dive chain (± Sprint) | 5.23 | 8.00 | **5.38** | 8.00 | – | 0 | 1.1 s |
| run + one dive every 3 s | 5.06 | 8.00 | 5.75 | 8.00 | 2.87 (landing recovery) | 32 (landings) | 15.1 s |

- **1.9 runner:** full input is a flat 6.00 m/s for the whole minute, with no
  drop tick. The old Sprint input changes nothing (same average to 0.005 m/s,
  same peak).
- **1.8 runner:** the Pass 8 best way across flat ground was releasing and
  re-pressing Sprint at 50 % (5.98 m/s average, see the
  [chart](../media/pass9/movement/full_input_60s.png)). 1.9's steady 6.0 m/s
  matches it with no input work.
- **Dives:** jump/dive chains stay slower than running (5.38 m/s) and slower
  than the Night Watch ([chart](../media/pass9/movement/dive_chain.png)). A
  single dive is still an 8.0 m/s burst. Its landing recovery is the only
  dip, and it is intended.

### Each device

Each input path is checked to give full input of magnitude 1, which the motor
turns into the role's full speed:

- **Touch** (`test_p9_full_speed_touch`):
  - Real `InputEventScreenTouch` and `InputEventScreenDrag` events go through
    TouchControls, Controls, MatchController and the sim in a Practice round.
  - A thumb parked at the rim for **60 s** held 6.000 m/s at every tick: 0
    drops, fast for the whole minute, and the stick drew "full" in
    3582/3582 frames.
  - ±4° and 92–106 % radius jitter near the rim changed nothing.
  - A part push jogs at 3.69 m/s and is not fast.
  - Pushing out again is fast within 2 ticks.
  - There is no Sprint button, label or HUD sprint state.
- **Touch curve** (`test_touch_input`): the curve is monotonic, has no step
  anywhere, reaches 1 at `full_at` = 0.9 of the radius and stays exactly 1
  out to the rim.
- **Keyboard and controller** (`test_controls`):
  - Keys W, W+D and S+A give magnitude 1.
  - A stick straight, diagonal, at a square-gate corner (1, 1) or just inside
    its outer dead zone gives 1, both through the radial dead zone and curve
    and through `get_move()`.
  - No Sprint action is bound.
  - The left trigger stays the cart brake (L2/LT/ZL prompts).

### Online

`test_guest_holds_full_speed_for_a_minute_online` is a 60 s trace over the
loopback rig at 50 ± 8 ms with 2 % loss. A guest runner holds full input,
circling open lawn. Each tick records input magnitude, desired speed, host
speed, guest predicted speed, state, fast and the reconciliation correction
(`data/trace_60s_online_1.9.json`).

- The host's slowest tick was 5.97 m/s (the turn of the circle), with 0 drops.
- The guest's prediction was the same.
- No correction exceeded 25 cm; the largest was 0.1 cm.
- [Chart](../media/pass9/movement/online_60s.png).

The 10 s jump/dive version had 0 corrections over 25 cm, and the guest's fast
flag agreed with the host in 19 or 20 of 20 samples.

## 3. Chases

The `test_pursuit` chaser is human-like: full stick, the camera following
with a 0.25 s lag, and Tag pressed at a "looks close" 2.6 m or on the
tag-ready cue. It ran on an open straight on both builds
(`data/pursuit_*.json`).

| Scenario | 1.8 | 1.9 | Closure-only estimate (1.9) |
|---|---|---|---|
| runner holding full input, 4 m behind | 1.3 s, 1 press | 3.9 s, 2 presses | 6.7 s to zero gap |
| … 8 m behind | 3.8 s, 1 press | **10.6 s**, 2 presses | 13.3 s |
| … 12 m behind | 6.3 s, 1 press | 17.2 s, 2 presses | 20 s |
| 1.8 runner sprinting in released bursts, 8 m | 11.1 s | (no sprint) | – |
| dive loop, 8 m | 4.5 s | 5.9 s | – |
| run + a dive every 3 s, 8 m | – | 7.6 s | – |
| pressing only on the cue, 8 m | – | 9.9 s, **1 press** | – |
| 100 ms input delay ±33 ms, 8 m | – | 11.8 s | – |
| 250 ms hitch, 8 m | – | 10.6 s | – |
| cart from 21 m, hop out, finish on foot | – | 21.6 s (out of the cart at 9.3 s) | – |

- **Straight chases end, sooner than closure alone.** At 6.6 against 6.0 the
  gap closes at 0.6 m/s. Every chase ended in a tag, sooner than closure
  alone predicts, because reach and the lunge cover the last 2.5 m.
- **1.9 compared with 1.8.** Against a 1.8 runner who held the stick without
  sprinting, the chase now lasts much longer. Against a 1.8 runner sprinting
  well, it lasts about the same (10.6 s against 11.1 s from 8 m).
- **The first press at 2.6 m misses.** The wind-up and lunge gain 0.65 m on a
  6.0 m/s runner, against 1.0 m on a 5.0 m/s runner. A press lands from about
  2.5 m, so the chaser's first press at a "looks close" 2.6 m misses. Pressing
  when Tag lights up lands first time.
- **Tag left unchanged.** The brief says to keep reach, line of sight and lag
  compensation unchanged initially, and they are. A human playtest should say
  whether a slightly faster lunge (about 9.5 m/s restores "a 2.6 m press
  behind a full-speed runner lands") is wanted.
- **Turbo is a real burst.** `test_pursuit` shows 2 s of Turbo opening a
  4.6 m gap to 6.4 m, and `test_chase_balance` shows the Watch closing again
  once Turbo ends. Turbo is now faster than the Watch on its own (7.5 against
  6.6). In 1.8 it was 6.25 alone and 8.0 only with sprint.
- **Carts off-road are about runner speed.** An off-road cart tops out at
  6.5 m/s, close to a full-speed runner, so the cart chase takes longer (the
  scenario's window was raised from 20 to 30 s). On the road, carts reach
  11 m/s. The cart values are the Pass 8 baseline, kept as the brief asked.
- **Online head-on passes (`test_net`).** At 150 ms round-trip time, a client
  Night Watch that misses a runner running back past it cannot catch back up
  within the old test's 3 s back-and-forth legs: one phase had 13 misses in
  40 s. The same phases on 1.8 catch within 7 s. Lag compensation is not the
  cause: with 6 s legs every phase catches in 2.7–7.5 s. The test now uses
  6 s legs anchored to the moment the two are placed. Before, the legs were
  timed from the global frame count, so the phase depended on which tests ran
  first.

## 4. The match as a whole: seeded bot-round matrix

### Method

`game/tools/p9_balance.gd` plays full bot rounds: real simulation, physics
and bots, headless.

- **Team sizes:** every supported size: 1, 2 (default) or 3 Night Watch of 8
  players. These need 5 of 7, 4 of 6 and 4 of 5 runners home.
- **Seeds:** 12 per team size. They rotate through the three home dorms and
  their curated water combinations, so both builds play identical
  seed/dorm/water rounds.
- **Measures per round:**
  - outcome, runners home, captures, stamps and round length;
  - route time of the runners who got home, and time to the first capture;
  - Tag hit rate and dives;
  - gadget uses;
  - Turbo value: whether the runner was not caught within 10 s, and the gap
    change over 3 s;
  - chase episodes: a Watch within 8 m, ending with a capture or the runner
    15 m clear;
  - the runners' average speed while moving.
- **Variants:** the 1.9 code ran twice. Once with the Pass 9 bot path fixes
  off (`nav old`: bots steer exactly as in 1.8), and once as shipped.
- **Experiment:** one tuning experiment set the Night Watch to 6.8 m/s.

Data: `data/balance_*.json`. Tables: `tools/p9_balance_summary.py`.

These are bot rounds, not people, and 12 rounds per cell leave wide
intervals.

### Results

**2 Night Watch (default):**

| build | runner wins (95 % CI) | home / needed | captures | round s | route s (home) | Tag hits | dives | Turbo: no capture 10 s / median gap +3 s | chases escaped / caught | runner m/s moving |
|---|---|---|---|---|---|---|---|---|---|---|
| 1.8 | 10/12 = 83 % (55–95) | 3.8 / 4 | 10.7 | 200 | 160 | 92 % of 11.6 | 28 | 10 % of 10 / −0.2 m | 8 % / 88 % of 12.2 | 5.78 |
| 1.9, bots steering as 1.8 | 10/12 = 83 % (55–95) | 3.8 / 4 | 9.2 | 185 | 157 | 90 % of 10.3 | 28 | 100 % of 8 / +2.7 m | 16 % / 82 % of 11.2 | 5.89 |
| **1.9 as shipped** | 12/12 = 100 % (76–100) | 4.0 / 4 | 8.2 | 181 | 146 | 97 % of 8.5 | 25 | 77 % of 13 / +1.8 m | 10 % / 86 % of 9.6 | 5.95 |
| 1.9, Watch 6.8 (not adopted) | 11/12 = 92 % (65–99) | 3.9 / 4 | 10.1 | 190 | 150 | 94 % of 10.8 | 28 | 67 % of 9 / +1.9 m | 15 % / 83 % of 12.2 | 5.94 |

**3 Night Watch:**

| build | runner wins | captures | round s | route s | Turbo: no capture 10 s | runner m/s |
|---|---|---|---|---|---|---|
| 1.8 | 5/12 = 42 % (19–68) | 14.3 | 219 | 187 | 15 % of 13 | 5.78 |
| 1.9, bots as 1.8 | 5/12 = 42 % (19–68) | 12.3 | 230 | 177 | 100 % of 12 | 5.90 |
| 1.9 as shipped | 8/12 = 67 % (39–86) | 11.8 | 217 | 173 | 70 % of 10 | 5.94 |
| 1.9, Watch 6.8 | 5/12 = 42 % (19–68) | 12.8 | 221 | 175 | 57 % of 14 | 5.94 |

**1 Night Watch:**

| build | runner wins | captures | round s | route s | runner m/s |
|---|---|---|---|---|---|
| 1.8 | 11/12 = 92 % (65–99) | 4.9 | 155 | 133 | 5.79 |
| 1.9, bots as 1.8 | 12/12 = 100 % (76–100) | 3.7 | 146 | 126 | 5.92 |
| 1.9 as shipped | 12/12 = 100 % (76–100) | 2.5 | 135 | 123 | 5.96 |
| 1.9, Watch 6.8 | 12/12 = 100 % (76–100) | 3.3 | 140 | 123 | 5.96 |

Full columns (stamps, first capture, gadget mix) are in `data/` and
`tools/p9_balance_summary.py --md`.

### Reading the results

- **The movement change on its own is close to outcome-neutral.** With the
  bots steering exactly as in 1.8, the 1.9 movement gives the same wins at 2
  and 3 Night Watch (10/12 and 5/12). It gives 12/12 against 11/12 at 1 Night
  Watch, which was already runner-heavy. Captures fall by about 1–2 a round,
  routes are 3–10 s shorter, and runner bots move 2 % faster on average (5.90
  against 5.78 m/s; 1.8 bots sprinted on long straights).
- **Turbo became a real escape.** In 1.8 a fleeing runner bot's Turbo almost
  never prevented a capture within 10 s (10–15 %). With 1.9 movement it does
  most of the time (70–100 %). The median gap gained in 3 s is +1.8 to
  +2.7 m. The brief describes finite gadgets as one of the runner's ways out,
  so this was kept. Gadgets stay finite (9 pickups, 25 s respawn, one at a
  time).
- **The shipped 1.9 is more runner-favoured, and that is the bot fix.** Every
  team size moves toward the runners: 100 % at 2 Watch, 67 % at 3 Watch. The
  movement-only variant shows the cause. It is the runner bots no longer
  losing seconds against walls (§5): routes are 146 s against 157 s.
- **Not adopted: Night Watch 6.8 m/s.** It restores 1.8's bot outcomes with
  the improved bots: 11/12 and 5/12. It was not adopted, because it would
  compensate for a bot improvement by speeding up one role. The brief rules
  that out, and human-against-human rounds don't have the bot defect. 6.8 is
  the measured next step if human playtests find the Night Watch too weak.
- **Final values:**
  - runner 6.0 m/s, Night Watch 6.6 m/s;
  - dive 8.0 m/s with its 0.45 s recovery;
  - Turbo ×1.25 for 3 s, capped at 8.0;
  - Tag reach 1.6 m, lunge 9.0 m/s, lag compensation 0.15 s;
  - carts unchanged.
- **Route estimates.** The runner pace estimate converts hold time with
  `cfg.runner_speed`, so it follows the new speed (`test_runner_pace`). The
  measured no-pursuit route times (`test_routes_bots`, 6 runner bots) are now
  a median of 111.5 s, range 96–126 s, over 16 combinations × 6 runs. All
  96 runs completed.

## 5. Bot defect found and fixed (both roles' bots)

| | |
|---|---|
| **Symptom** | `test_p9_movement::test_bots_run_steadily` failed: a runner bot was at full speed for only 11 of 19 s while moving. |
| **Reproduction** | A seeded round on the default dorm. A runner bot heading for a water slid along a long wall at 4.6 m/s, then slowed to 0.8 m/s over 5 s before the stuck hop. The 1.8 code does the same at the same spot. |
| **Measured cause** | Two causes. (1) A path segment passing a wall closer than the capsule: the bot pushes into it at a shallow angle and slides at cos(angle) of its speed. (2) A low wall (0.6 m) that the foot grid weights but does not block. Paths cross it, but only the Night Watch and fleeing runners called the hop check. A runner on its way to a water or home pressed into it until stuck. |
| **Change** | `BotBrain._along_walls`: along a **tall** wall (something at 1.25 m) the bot runs along the face at full input instead of into it. Runners heading for waters or home now call `_hop_obstacles` like the Night Watch. Head-on contact is still the stuck logic's job. `BotBrain.pass9_nav` switches both off for measurement only. |
| **Evidence** | Bot runner at full speed for all of the trace (`test_bots_run_steadily` passes). Route times shorter. Matrix variants above. |

Separately, the Night Watch bot's "wait a little closer before lunging" used
to apply when its target was sprinting. It now applies when the target is
actually faster than the Night Watch on foot (Turbo, a dive). Without this,
every full-speed runner would count.

## 6. Verification

Suites passing on 1.9: `test_p9_movement` (9 tests), `test_p9_full_speed_touch`, `test_pursuit`,
`test_chase_balance`, `test_touch_input`, `test_controls`, `test_profile`
(Pass 8 profile migration), `test_sim`, `test_net` (incl. protocol and lag
compensation), `test_trust`, `test_runner_pace`, `test_match_hud_pass8` (no
sprint UI), `test_v7_screens` (Settings), `test_routes_bots`, `test_dorms` and `test_coins` bot rounds.
The animation suites at the new speed are handled by the animation workstream
(`docs/pass9/fit.md`).

Protocol: `test_old_protocol_is_refused_with_update_needed` sends a raw
protocol 7 (1.8) and protocol 9 HELLO. Each gets WELCOME slot −1 with reason
"version", which shows "That party is on a different version of the game.
Update the game to join." No slot is taken, and the current client stays in.

Respawn and floor snap: `test_motor_state_round_trip_and_resets` checks that
the motor state round-trips without the meter floats (read size equals
written size) and that `fast` resets on capture and respawn. The Pass 8
floor-snap and respawn tests still pass (`test_sim`, `test_net`).

Clips (desktop renders of scripted input, Movie Maker 30 fps over llvmpipe,
not device footage): see `docs/media/pass9/movement/`.

## 7. Not measured here (needs devices and people)

- **Touch feel on a phone.** Does a thumb at the stick's rim feel like full
  speed without straining? The 90 % saturation radius is a desktop choice.
- **Frame rate and thermals** while running flat out on the oldest supported
  phone.
- **Human Night Watch against human runners.** Is a 10–17 s straight chase
  fair? Is the 2.6 m first press missing frustrating? Does Turbo feel too
  strong? The levers are measured: Watch 6.8 m/s, or a lunge of about
  9.5 m/s.
- **Online play over real networks.** These numbers are loopback simulation.

**Playtest script.** Two phones in a party, 2 Night Watch:

1. A runner holds the stick fully forward on a long lawn for 30 s. It should
   be steady, with no pulses.
2. A Night Watch chases from about 8 m and presses Tag when it lights.
3. Repeat with a runner who jogs, which is quieter.
4. Note who wins five rounds at each team size.
