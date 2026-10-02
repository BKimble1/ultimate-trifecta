# V5 motion notes: smoother, more expressive characters

Work stream: character animation and motion glitches. The defect register,
with every before/after number and how it was measured, is
[motion_register.md](motion_register.md). Captures and clips are in
[../media/v5/motion/](../media/v5/motion/README.md).

**What these notes can claim.** Everything was measured on a desktop:
headless engine frames on a fixed clock, or Mesa llvmpipe for pictures and
Movie Maker clips. That measures continuity (does a pose, the camera or the
cap jump between two frames) and relative cost. It says nothing about frame
rate or feel on an iPhone, and nothing about live Game Center links.

## What changed

The asset, rig, bone names, cosmetics catalog, 5-byte/appearance encodings
and the one animation graph every screen uses are unchanged in shape. The
asset gained clips and one hair variant; the graph gained an upper-body
action layer. Gameplay is untouched: nothing here moves the capsule, adds
root motion or delays an action.

### Transitions start from the pose on screen

`game/src/view/character_pose_fade.gd` (`CharacterPoseFade`) is the first
skeleton modifier. Every state change in `CharacterView._set_mode` captures
the pose that was actually drawn last frame plus its angular velocity, and
blends from that pose (extrapolated with the velocity decaying over 50 ms)
into the new animation over the state's fade time. Godot's own transition
now switches at once (`xfade_time = 0`), so an interrupted fade can no
longer drop a half-faded pose. Landings, restarted emotes and the action
layer use the same capture.

Teleports cut instead: a state change that moved the character more than
0.5 m in a frame (respawn after capture, resurfacing at a shore exit, cart
seat in/out, reconnect jumps) resets motion history, aborts overlays and
shows the new pose at once. `apply_state(snap = true)` only resets history
when the character actually moved (MatchController also flags cart
EXITING → ACTIVE, which does not move).

### Locomotion

- **Weight and blend in time.** The sim reaches full speed in ~0.1 s (46 /
  52 m/s²). The idle ↔ gait weight now eases in over 0.045 s and out over
  0.085 s; the blend-space speed follows the ground speed through a 0.03 s
  filter (0.08 s measured as more foot slide in turns; none let prediction
  corrections shake the pose).
- **Starts and stops.** From a standstill the gait phase is set to a half
  cycle (one foot under the body, the other passing it) while its weight is
  still ~0, so the first visible motion is a step. A stop keeps advancing
  the phase (≥ 2.4 cycles/s) to the next half cycle and holds there while
  the legs blend to idle.
- **Cadence.** `rate = forward ground speed / metres per cycle of the pose
  shown`; at the rule speeds that is 2.27 cycles/s (runner 5.0 m/s), 2.50
  (Night Watch 6.6), 2.69 (sprint 7.4), 2.91 (Turbo cap 8.0), 1.86 (walk
  1.3). `test_gait_cadence_matches_ground_travel` checks each against the
  phase actually advanced.
- **Facing.** In plain ground locomotion the drawn body aims at the
  (filtered) velocity heading the sim is turning its yaw toward, instead
  of trailing the capped sim yaw and then a 24/s smoothing; tag phases,
  dives and other states keep the sim facing (aim assist, committed dives).
- **Air.** The air pose shows at once for a real jump (rising) and only
  after 0.07 s off the floor otherwise, so a one-tick on_floor flicker
  (slope crests, kerbs, a correction) never plays half a jump.
- **Night Watch tag.** Wind-up and recovery play on the upper body while
  the legs keep running (`act` layer, filtered to spine, chest, neck, head
  and arms; below 1.2 m/s the full-body clips play as before). The lunge is
  a leap: the sim carries the body 2 m at 9 m/s and the feet now leave the
  floor instead of sliding a planted stance.

### Secondary motion

- **Acceleration.** `accel = d/dt of a filtered velocity` (τ = `ACC_TAU`
  0.05 s, bound `ACC_MAX` 55 m/s²): ≤ Δv / τ whatever the frame length.
  V4 divided a 60 Hz-quantised velocity change by the render frame.
- **Body lean.** `CharacterSecondary` adds a spine/chest lean spring:
  forward into acceleration, back against braking, one soft wobble (ω 10,
  ζ 0.6, ≤ 0.13 rad). Upper body only, so planted feet stay put.
- **Squash and stretch.** A damped spring (ω 20, ζ 0.5) kicked by landings
  (≤ 15 %) and take-offs, instead of a scale set in one frame.
- **Nightcap.** The spring bone runs in the character's own space
  (`CENTER_FROM_NODE`); inertia comes from the filtered acceleration as an
  external force (0.025 per m/s², ≤ 1.4); a sphere just inside the head
  keeps the tip out of it; on a teleport the cap shows its rest shape in
  the cut frame and restarts next frame. Hitches and teleports no longer
  fling it, and in the air it floats a little (free fall).
- **Face.** Blinks are a quick close and softer open (0.15 s; 0.2 s in
  menus) instead of a hard 0.13 s on/off; menus add the odd double blink.
  Fidget-specific expressions (yawn face only for the yawn).

### Menu idle API

```gdscript
CharacterView.set_menu_idle(on: bool)   # override either way
CharacterView.menu_idle                 # read
```

On by default when `lighting == "indoor"` at `setup()`: every menu stage
(dorm lobby, home, wardrobe/creator preview) already sets that, so **no
change to `dorm_stage.gd` was needed**. Portraits (`set_process(false)`) are
unaffected. In menu idle:

- breathing and weight shift run at 0.8× (the idle loop's clock);
- fidgets every 7–12 s from a restrained set, weighted: look over the
  shoulders (3), shift weight onto one leg with a small sigh (3,
  `fidget_shift`, new), two small toe bounces (2, `fidget_bounce`, new),
  the pajama yawn (1); fade in 0.45 s, out 0.5 s;
- softer blinks, 20 % of them doubled;
- nightcap stiffness 2.6 and drag 0.7 (play: 1.8 / 0.45), inertia force
  and head lag at 0.6×.

Emotes, arrivals, ready responses, "Try moves" and the leave wave are
unchanged and pre-empt fidgets. Measured over 24 s: largest upper-body
third difference 0.5 cm (V4 idle: 3.1), cap tip within 6.6 cm of its rest position (V4: 10.0) (`motion_probe`, three starting phases; `test_menu_idle_api` bounds them at 2.5 and 12 cm).

### Animation LOD

Throttled (every third frame, elapsed time accumulated exactly) beyond
48 m from the camera, back to every frame inside 42 m; the local character
never throttles. The camera distance is measured once per frame. Throttled
characters cut instead of fading and skip the fade's pose history. Lobby
rosters are always within a few metres, so they always run at full rate.

### Camera

`FollowCamera` keeps immediate manual look, exact horizontal follow and
the 0.06 s vertical damp. New: a narrow occluder (camera spot clear, the
obstacle < 0.9 m deep along the line, a parallel ray 1 m to one side
clear) no longer pulls the camera in; walls and buildings still pull in at
once and release after 0.15 s clear. Extra cost: up to four rays and one
shape query, only on frames whose sweep hits. Slopes (ramp), turns and a
250 ms hitch measured no extra camera jump (≤ 4 cm relative to the pivot).
No motion blur, no added lag.

### Frame order and interpolation

Physics interpolation is off in `project.godot`, and CharacterView never
smooths translation. Interpolation happens once, in `MatchController`
(`lerp(prev tick, cur tick, physics fraction)`), and the camera follows that
same anchor. Per frame: `MatchController._process` applies render states
to the views, then updates the camera; the views (its children) then
evaluate their animation; skeleton modifiers (pose fade → secondary →
cap spring) run in the deferred skeleton update. The camera reads only the
anchor, never a bone, so the picture equals state → animation → camera.
`match_controller.gd` was not edited.

### Resets

| Event | What resets |
|---|---|
| Respawn after capture, resurfacing, cart seat in/out, reconnect jump (> 0.5 m in a frame) | head/lean springs, velocity filter, squash, cap spring (rest shape in the cut frame), visual yaw, pose cut, overlays aborted |
| Spectator switch | camera cut (`snap_to`, unchanged) |
| Hitch (long frame) | nothing needed: filters are bounded, the cap is node-space |
| Discontinuity flag without movement (cart EXITING → ACTIVE) | nothing (history kept) |

Event-driven sounds, stamps, splashes and haptics are untouched (event IDs
in MatchController/NetSession). Landing and jump sounds fire once per
landing, including flicker and hitch runs (`test_landings_and_jumps_fire_once`).

## Asset changes (`tools/character/`)

- `anims.py`: overhead arm poses kept out of the head (yawn, celebrate,
  arrive, cheer, wave, air fall, splash dip/duck); IK targets interpolate in
  `blend_pose`; landings start from the falling pose with a settling dip;
  tag wind-up (left hand cocks back, the right holds the flashlight), leap
  lunge, recover and miss; cart hop-in and hop-out; ready and arrive hops
  lift the feet instead of over-stretching the leg IK; locomotion arms with
  follow-through (forearm and mitten lag) and a small head give at each
  strike; new `fidget_shift` (2.6 s) and `fidget_bounce` (1.8 s). 42 clips
  (V4: 40). Strides and duty factors are unchanged.
- `parts.py`: `hair_curly_hat`, the curly crop with a smooth band where a
  crown or headphone band rests.
- `clip_check.py` (new): every clip on the real rig: arm/head and
  hand/torso penetration, IK leg reach, in-clip joint jumps.

### Rebuilding `runner.glb`

```sh
python3.11 -m venv tools/.cache/bpyenv && tools/.cache/bpyenv/bin/pip install bpy==4.5.4
BPY_PYTHON=/path/to/bpyenv/bin/python tools/character/build.sh      # ~10 s
BPY_PYTHON=/path/to/bpyenv/bin/python tools/character/build.sh /tmp/x.glb   # elsewhere
tools/.cache/bpyenv/bin/python tools/character/clip_check.py        # exit 0: no arm > 1 cm into the head
tools/gd.sh --headless --path game --import
```

Before editing, the unchanged V4 sources rebuilt `runner.glb` and its
manifest byte for byte with bpy 4.5.4.

## Budgets

| | V4 | V5 |
|---|---|---|
| Typical outfit (base, pajamas, nightcap, slippers), LOD0 triangles | 23.4k | 23.4k (unchanged parts) |
| Curly hair under crown/headphones | 5,848 | 4,048 (`hair_curly_hat`) |
| All parts in the GLB (not all drawn) | 95,122 | 99,170 |
| Clips | 40 | 42 |
| Skeleton modifiers per character | 2 (secondary, cap spring) | 3 (+ pose fade) |
| Physics queries per frame, camera | 1 sweep + 1 shape | same; + ≤ 4 rays + 1 shape on frames whose sweep hits |
| Physics queries per frame, characters | 0 | 0 (no foot IK) |
| Frame CPU, 8 characters on screen (desktop, headless, `motion_probe --bench`, 3 runs) | 459–813 µs | 519–652 µs |

The CPU comparison (`motion_probe.tscn -- --bench`: 8 characters, 4
running, 4 idle, 600 frames, no rendering) ran on a desktop shared with
other jobs (load average ≈ 7): V4 and V5 are within run-to-run noise, so
no difference is claimed. Structurally, V5 adds per nearby character and
frame 23 bone-rotation and 2 position reads (the pose fade's history; zero
for throttled distant characters), a lean spring in `CharacterSecondary`,
and slerps only while a fade runs (0.06–0.3 s after a state change).

## Tests

`game/tests/test_motion_v5.gd` (new, 13 tests) runs gameplay-like scenarios
through `tests/motion_rig.gd` and `tests/camera_rig.gd`:

- upper-body snap bounds for start, stop, walk, reversal, speed changes,
  kerb drop, contact flicker, emote, running jump, tag, cart and
  prediction-correction stress (V4 values in the messages);
- a one-tick floor flicker never shows the air pose; landings and jumps
  fire once (also through flicker and a 250 ms hitch);
- the nightcap and head spring stay bounded through a hitch, a respawn and
  a jump;
- teleports cut and reset history; a flagged discontinuity that did not
  move keeps it;
- acceleration fed to the springs is bounded whatever the frame length;
- gait cadence equals ground speed / stride shown at 1.3, 5.0, 6.6, 7.4 and
  8.0 m/s, and steady running keeps the planted foot planted;
- a stop ends on a half-cycle pose;
- LOD hysteresis and exact elapsed time; the local character never
  throttles;
- the menu idle API (default, override, cap tuning, fidget pool, blinks,
  24 s without a snap);
- the asset has the V5 clips, 23 bones and unchanged strides;
- the camera ignores a post and a trunk but still pulls in for a wall, and
  does not jump on a ramp, a turn or a hitch;
- a lobby run on the spot keeps facing the camera and keeps its legs
  cycling.

Two existing tests changed with the behaviour they check:
`test_motion.gd::test_character_acceleration_uses_previous_velocity` now
expects the filtered acceleration (still guarding the V2 "always zero"
bug), and `test_profile.gd::test_every_appearance_maps_onto_the_character`
accepts `hair_curly_hat` where the catalog names `hair_curly` under a crown
or headphones.

## Network: what a client shows

`src/dev/net_motion_probe.tscn` (host + one predicting runner client over
the in-process loopback, 12 s of play, 720 client frames per condition;
`docs/media/v5/motion/data/netmotion_v5.json`):

| | LAN (0 ms) | 120 ms RTT, 10 ms jitter, 3 % loss | 300 ms RTT, 30 ms jitter, 10 % loss |
|---|---|---|---|
| Render stall (frame > 40 ms) | 0 | 0 | 0 (fixed clock: cannot occur here) |
| Visible correction (drawn position > 8 cm off its own path within 3 frames of a reconcile > 5 cm) | 0 | 0 | 0 |
| Reconcile size, mean / > 25 cm | 0 mm / 0 | 4 mm / 0 | 3 mm / 0 |
| Terrain/collision deviation (same, no reconcile) | 46 | 45 | 45 |
| Camera collision pull/release frames | 176 | 150 | 53 |
| Camera movement without a distance change | 3 | 2 | 2 |
| Remote characters extrapolating (of ~5,000 remote-character frames) | 0 | 25 | 310 |
| Remote position snaps > 15 cm | 0 | 0 | 3 |
| Host ticks without client input | 0 | 0 | 0 |

The terrain and camera counts do not change with the link, so they are not
network effects (they come from the route: kerbs, steps, walls). The same
probe on V4 counted 325 / 220 / 325 upper-body pose-snap frames (> 6 cm
third difference) against V5's 261 / 142 / 264; most remaining ones are the
scripted runner's jumps every 1.2 s and 90° turns every 1.5 s.

The real-UDP soak (`tools/net_soak.sh`, ENet, host + 2 bot-driven clients,
one full round each, on a desktop shared with renders; reports in
`docs/media/v5/motion/data/soak_*.json`):

| | Unshaped | 60 ± 10 ms one way, 3 % loss |
|---|---|---|
| Client RTT estimate | 18–19 ms | 153–163 ms |
| Correction mean / max | 2.4–2.6 mm / 0.88–0.99 m | 10.7–11.8 mm / 1.21 m |
| Host ticks starved / skipped (all clients) | 48 / 74 | 622 / 482 |

Classification: render stall — not measurable here (fixed clock; the
Diagnostics panel measures it on a phone). Camera jitter — none beyond
collision pull/release (post/trunk pulls fixed). Pose popping — the
transitions above (fixed or reduced). Collision/terrain — constant across
links. Input loss — host starvation grows under shaping (late or lost
inputs re-use the last one; they produce the rare large corrections).
Network correction — small on average (3–12 mm); rare large ones (≈ 1 m
max in both soak conditions, so not only shaping) were not traced further
in this stream. Remote interpolation — runs dry only under heavy loss.

## Limits and next steps

- **Turn foot slide** is about as in V4 (0.78 vs 0.69 m/s mean planted-foot
  speed in a 90° turn): a planted foot pivots with the body. The fix is
  foot locking (pin the stance foot in world space during stance, two-bone
  IK, fade at toe-off); budget: two IK solves per nearby character per
  frame, no physics queries on flat ground, one ray per foot for slopes.
  Not done in V5.
- **Slopes and stairs** were not measured (no ground IK; feet follow the
  character origin's plane).
- **Remote players under heavy loss** (300 ms RTT, 30 ms jitter, 10 %
  loss) spend ~6 % of remote-character frames extrapolating because the
  interpolation delay is capped at 14 ticks in `MatchController`; at
  120 ms / 3 % loss it is 0.5 %. Raising the cap when loss is measured is a
  net-code change for that stream.
- **Shoulders** are not re-skinned; the clips simply no longer raise the
  arms into the head.
- No foot-planting, camera or stall numbers from a phone exist. The
  Diagnostics panel (V4) is the way to get them.
