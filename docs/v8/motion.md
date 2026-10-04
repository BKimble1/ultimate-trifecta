# V8 motion, contact and character finish

What changed in the character's movement and finish for 1.7, how it is
built, and the evidence. Everything here was measured on desktop Linux:
headless, or Godot 4.7.2's Mobile renderer on Mesa llvmpipe under Xvfb.
**No iPhone or iPad was available.** Clips are Movie Maker recordings on a
fixed 30 fps clock at normal speed: they show poses and timing, not frame
rate or feel on a device.

## The contract kept

- The capsule and the simulation stay authoritative. Every change below is
  presentation: no root motion, no change to speeds, tag reach or timing,
  collision or navigation.
- Walk/run/sprint stay 1.0 s cycles that start at left mid-stance, seeked by
  the gait phase (`loco_seek`). Strides (0.70 / 2.20 / 2.75 m per cycle) and
  duty factors are unchanged, so planted feet still travel at ground speed.
- Transitions start from the pose on screen (CharacterPoseFade) and can be
  interrupted; a teleport still cuts.

## Authored transitions (new clips, `tools/character/anims.py`)

| Clip | Kind | What it does | Driven by |
|---|---|---|---|
| `loco_accel` | additive, 1.0 s loop seeked with the gait phase | the push of an acceleration: chest pitched into it, head level, the swing knee driving higher, arms pumping wider in time with the legs, the stance foot extending through toe-off | a start from a standstill holds it ~0.25 s, then lets go by 0.55 s; otherwise a hard forward acceleration (filtered over 0.1 s; the first 8 m/s² are ignored, 30 m/s² shows it fully) |
| `loco_brake` | additive, static | leaning back against a stop: spine and chest sit back, head level, arms swing forward and out | deceleration from a run (the same filter and dead zone; full at 20 m/s², a stop from a run peaks near 23); when the planted stop starts it takes over the lean, and the layer eases out from zero slope over 0.3 s |
| `lead_l`, `lead_r` (+ `add_zero`) | additive, static, a 1-D blend | the head looks further into the turn, chest and spine follow, the inside arm opens back and the outside arm swings across | the body's turn rate (≥ 7 rad/s full); the side is chosen when the lead starts and kept until it has eased off, so a 180° reversal never flips it |
| `stop_l`, `stop_r` | one-shot, 0.5 s | a planted stop: the foot under the body stays planted, the foot coming through plants a stride ahead heel first, the knees take it, the chest sits back with the arms forward, a small rebound, then the front foot steps back beside the other (lifted) into the idle stance | a stop from at least 3 m/s, once the body has stopped (the side from the settle phase: right at phase 0, left at 0.5); never while the Night Watch's tag owns the body (its miss recovery stopping is not a planted stop) |

**None of the additive layers touches the hips.** The legs hang from the
pelvis, so the first version's pelvis drop, pitch and twist moved the
planted feet: 0.36–0.69 m/s of slide in the start, stop, 90° turn and
reversal scenarios (bounds 0.3 / 0.15). The posture is now carried by the
spine, chest, head and arms; the drive's knee lift acts only on the leg in
the air. The layers also yield while an upper-body action owns the torso
(the Night Watch's tag: its 9 m/s lunge is neither a start nor a brake).

The layers read a filtered acceleration with a dead zone because the motion
probe showed them reacting to reconcile noise: in its `correction` scenario
(a predicting client's small corrections) the first version raised the
frames with an upper-body pop over 3 cm from 70 (build 6) to 198; filtered
and dead-zoned, 84. Measured in the rig, real braking reaches −23 m/s²
(filtered) and correction noise stays within −6.

## Refined clips

| Clip | Change |
|---|---|
| `run`, `sprint` | stronger toe-off (36° vs 28°) so push-off, flight and contact read; arm swings travel in an arc (in across the body going forward, slightly out going back) instead of a flat hinge; a touch of asymmetry (left arm 3 % wider, right elbow 2.5° more bent); steadier head (nod 1.3° vs 2.2°); a little more bob for a readable flight (run 0.026 m, sprint 0.031 m; sprint knee lift 0.205 m) |
| `air_rise`, `air_apex`, `air_fall` | a bound instead of a hop: takeoff with the lead knee driving up, the trailing leg extended through a pointed toe and opposite arms; a tuck at the apex with the arms open; in the fall the legs reach for the ground, toes up, arms up and out (≤ 84°, outside the head) |
| `land_soft`, `land_hard` | the feet land slightly staggered; the hard landing goes deeper (0.17 m) with more lean |
| `tag_windup` | a deeper coil: lower, more turned, the tagging hand further back, the head on the target. The flashlight hand swings down with it, so for about 0.2 s its pool lands beside the feet (smaller and brighter than build 6's pool ahead) |
| `tag_lunge` | one long line from the trailing toe to the reaching mitten: the reach arm straight, the torso long and low, the flashlight arm thrown back as a counter |
| `tag_recover` | contact: the mitten closes and pulls back toward the chest ("got you") before the arm settles |
| `tag_miss` | starts from the new lunge's end pose; the sweep's envelope ends with zero slope (sin²) |

`clip_check.py` (all 53 clips, real rig, 60 Hz): no arm in the head or the
goggles; IK reach no worse than build 6 (run 0.443 m as before; the stops
0.432 m); in-clip steps within V7's range. Data: `docs/v8/data/clip_check_after.json`
and `clip_check_before.json`.

## The motion probe, before and after

`src/dev/motion_probe.tscn`: every motion-test scenario through
`tests/motion_rig.gd` (the 60 Hz mini-motor with the RulesConfig values →
interpolation → CharacterView, real engine frames), three starting gait
phases each (worst pop, mean slide). *Pop* is the largest third difference
of an upper-body joint over four equal frames (a snap of X cm scores 2X; a
steady 60 fps sprint peaks near 3 cm at the mitten tips); *slide* is the
horizontal speed of the lower foot while it is planted. Build 6 = `cb3c48a`;
after = this branch's final code. Data:
`docs/v8/data/motion_probe_{before,after}.json`.

| scenario | worst pop, cm | frames with a pop > 3 cm | planted slide, mean m/s | slide p95, m/s |
|---|---|---|---|---|
| `start` | 5.42 → 5.42 | 9 → 15 | 0.022 → 0.025 | 0.24 → 0.232 |
| `stop` | 3.5 → 8.25 | 6 → 26 | 0.138 → 0.134 | 0.77 → 0.768 |
| `walk_start_stop` | 5.41 → 5.38 | 12 → 12 | 0.04 → 0.04 | 0.269 → 0.268 |
| `reverse` | 6.83 → 6.24 | 12 → 20 | 0.113 → 0.113 | 0.473 → 0.47 |
| `turn90` | 3.49 → 4.39 | 3 → 9 | 0.04 → 0.038 | 0.465 → 0.468 |
| `speeds` | 5.37 → 5.29 | 6 → 9 | 0.007 → 0.007 | 0.025 → 0.018 |
| `sprint` | 3.44 → 4.17 | 3 → 32 | 0.052 → 0.052 | 0.347 → 0.303 |
| `jump_run` | 9.95 → 9.91 | 40 → 57 | 0.05 → 0.056 | 0.302 → 0.335 |
| `jump_idle` | 10.01 → 9.66 | 36 → 39 | 0.026 → 0.042 | 0.164 → 0.258 |
| `dive` | 6.95 → 6.86 | 60 → 62 | 0.282 → 0.282 | 1.489 → 1.491 |
| `kerb` | 6.82 → 7.62 | 59 → 60 | 0.128 → 0.127 | 1.412 → 1.417 |
| `flicker` | 3.49 → 4.4 | 3 → 9 | 0.038 → 0.038 | 0.401 → 0.405 |
| `tag_miss` | 14.38 → 16.01 | 45 → 67 | 0.651 → 0.952 | 1.033 → 12.529 |
| `tag_hit` | 8.88 → 10.87 | 36 → 72 | 0.094 → 0.092 | 0.615 → 0.612 |
| `splash` | 14.74 → 14.01 | 114 → 120 | 0.05 → 0.05 | 0.302 → 0.329 |
| `cart` | 5.09 → 4.81 | 9 → 9 | 0.349 → 0.34 | 0.874 → 0.877 |
| `emote` | 4.02 → 3.85 | 19 → 24 | 0.365 → 0.402 | 4.979 → 5.018 |
| `hitch` | 3.49 → 4.39 | 3 → 9 | 0.026 → 0.025 | 0.241 → 0.236 |
| `jitter` | 3.5 → 4.4 | 3 → 9 | 0.025 → 0.025 | 0.232 → 0.241 |
| `correction` | 6.75 → 7.27 | 70 → 84 | 0.11 → 0.111 | 0.347 → 0.346 |
| `ramp` (V8 only) | 4.39 | 9 | 0.029 | 0.305 |

How to read it:

- **Bounds hold.** Every worst pop is inside the V5/V6 bounds the motion
  tests enforce (9–10 cm for locomotion, 18 for the tag); planted-foot slide
  is unchanged within a few mm/s except where noted.
- **More frames over 3 cm** in the sprint (3 → 32), the turns and the tags.
  These are the new authored motion moving the mitten tips faster (the arm
  swing travels in an arc; the drive layer pumps the arms at a start; the
  tag clips reach further and recoil). The largest single-frame joint move
  grew with them, by 0–3 cm (sprint 15.1 → 16.3 cm, running jump 11.2 →
  14.3, tag hit 15.8 → 17.2): faster authored joints, not cuts (a cut moves a
  joint tens of centimetres; the splash, cart and hitch scenarios' 50–190 cm
  steps are their designed teleports, the same on both builds). The 3 cm
  line was drawn under build 6's gentler arm swing; whether the livelier
  arms read better or busier on a phone is a device question.
- **The stop** peaks at 8.3 cm (3.5 before): the planted stop is a real
  arm-forward action where build 6 had none. The first integrated version
  scored 9.6 (the brake layer's exponential release kicked the arms the
  frame the stop fired); it now hands off from zero slope.
- **`tag_miss` slide p95 1.03 → 12.5 m/s.** The same two-frame skim exists in
  both builds: as the Night Watch comes out of the 9 m/s lunge back into the
  run cycle, the lower ankle passes 8–9 cm above the ground (the probe
  counts under 9.5 cm as planted) while the body still moves at ~6.6 m/s.
  Build 6 has one such frame (14.8 m/s), 1.7 two (its ankle is ~1 mm
  lower), and with 85 samples the 95th percentile lands on them. It is
  listed as open, not fixed.
- **`correction`**: 70 → 84 frames over 3 cm (198 in the first integrated
  version, before the layers' acceleration was filtered).

## Terrain contact (prototype, shipped for nearby characters)

V6's foot lock pinned planted ankles horizontally on the plane of the
character's origin. On a ramp or a step the front foot sank into the ground
and the back one floated. Now, once per touch-down, the ground under that
ankle is sampled (one ray against the static world, `CharacterView._probe_ground`)
and the planted ankle is held at that **world** height for its stance;
the pelvis drops by the lower foot's deficit (at most 0.10 m) so the leg
can reach. The correction eases in at touch-down (12 ms: a running stance
lasts under 0.1 s) and out in the air. Distant characters keep the old
path. The capsule, collision and navigation never move.

Measured on a 20 % ramp (`motion_rig` "ramp", `test_v8_motion::test_terrain_contact_on_a_ramp`):
the planted ankle's spread around its mean height above the ground under
it went from **5.9 cm to 2.6 cm** (most of what remains is the authored
heel-toe roll), mean planted-foot slide 0.065 m/s, no snap (4.4 cm,
unchanged), **12 rays in 1.6 s** of running.

## Character finish (GLB rebuilt, art generation 8)

- **Eyes and goggle lenses**: the sclera, iris, pupil and catch-light domes
  and the goggle lenses carry their analytic normals (the ellipsoid's
  gradient; the lens dome's own slope) instead of normals averaged from the
  faces, so the highlights on these shallow domes are round instead of
  following their polygons. The iris (18 → 24 segments), pupil (14 → 18) and
  catch-lights (10 → 16, 8 → 12) have a few more segments for their
  outlines in close-ups: +328 triangles on the base mesh, the only part
  that grew.
- **Material separation**: two new material classes in the character
  shader. *Satin* (robe lapels, cuffs and sash; the Track Suit's midnight
  satin): a broad, soft highlight and a stronger grazing sheen than cotton.
  *Metal* (Night Watch badge, buttons and whistle, zips, snaps, gold
  buttons, the flashlight body, the crown): metallic, tinting its reflection,
  with a little self-light so small parts stay readable at night. Skin,
  cotton, rubber/soles, lenses and plastic gloss keep their classes.
- One draw call per visible part and one shared material, as before.

## Remote motion and the body's heading

- The local player's decaying reconcile offset (`_smooth`) is no longer read
  as travel: the view's heading derivative excludes it (`rs["corr"]`).
  Reproduced in `test_v8_timing::test_correction_offset_does_not_turn_the_body`:
  a 0.5 m sideways correction turned a straight-running body by more than 8°
  when read as travel; excluded, under 1.5°.
- Remote players and carts are drawn on a monotonic presentation clock; see
  [performance.md](performance.md#network-presentation).

## Evidence

See [docs/media/v8/README.md](../media/v8/README.md) for the clips and stills.
