# Pass 9 · Fit: garments on the body, and animation at the steady speeds

The FIT workstream of Pass 9 (brief §7 "costumes appearing off the body" and
§8 "clean the animation through the full system"). Branch `p9-fit`, from
the release commit `2fff573`.

**Status.** The complaint reproduces on the shipped asset, and it was in the
generated garments, not the import or the view. Cuffs stood up to 4.2 cm off
the wrist with a near-black lining. Shorts hems flared up to 8 cm round
bare thighs, and their hoops crossed into the other leg. Shoulder caps and
hip tops parted from their sleeves and trousers by up to 8.8 cm in motion.

These are fixed in the character generator. A new offline check
(`fit_check.py`) and a Godot test on the imported scene in final blended
poses (`test_fit_p9.gd`) now catch them:

| Check | Before (2fff573) | After (p9-fit) |
|---|---|---|
| `fit_check.py` | 120 failures | 0 failures |
| `test_fit_p9.gd` | 14 failures | 0 failures |

The animation now holds up at the Pass 9 steady speeds (runner 6.0 m/s,
Night Watch 6.6). A 180-degree reversal no longer fires a one-frame
planted stop: in the motion probe the hand snap fell from 24.8 to 4.5 cm and
the planted-foot slide from 1.09 to 0.04 m/s. A stop from full speed fades from the pose on
screen. These fix all 22 stop/reverse failures the integrator saw at
`runner_speed = 6.0`.

**Limits of the evidence.** Everything here was measured on desktop Linux:
offline numpy, headless Godot 4.7.2, and llvmpipe renders. Nothing was
checked on a physical phone; see [Open items](#open-items).

## How the character reaches the screen (verified, not changed)

The brief's first question was whether the importer or the runtime moves
garments off the body. I measured this on the real imported
`runner.glb` in the pinned engine (`test_fit_p9::test_imported_skinning_setup`
and `::test_runtime_deformation_matches_the_asset`, plus scratch inspectors).

| Item | Measured | Result |
|---|---|---|
| Mesh → skeleton path | Every one of the 53 skinned parts has an explicit `skeleton` path to the single `Skeleton3D`. Godot 4.6 changed `MeshInstance3D.skeleton`'s default from `..` to an empty path; the 4.7.2 glTF importer sets it explicitly. Every part of a live `CharacterView` is skinned to its skeleton after `setup()`. | sound |
| Skin registration | One `Skin` shared by all parts (one armature). 23 binds, each named after a bone that exists. `bone global rest × bind pose` = identity to 1e-4; the worst measured value is about 7e-7. | sound |
| Transforms, units | Every part has an identity transform under the skeleton. Root scale is 1 and units are metres. No transform is applied twice and no armature is mismatched. | sound |
| Influences | 4 bone weights per vertex (no 8-weight flag), sums within 2e-3, no unweighted vertex. Duplicated seam vertices carry identical weights (`fit_check` weights, every look). | sound |
| Normals | Faces agree with their vertex normals and all normals are unit length: 0 flipped faces on any garment. The only flipped faces are 5 in total on the nightcap, hair and courier cap (pinched tips). | sound |
| Animation import | `animation/fps=30`: the 30 fps keys import as authored (e.g. `run` keeps 30 keys over its 1 s cycle, and `dive_land` keeps its authored length). | sound |
| Imported vs runtime deformation | Anchor vertices are re-skinned on the CPU from the imported meshes and the AnimationPlayer's skeleton. They match the asset's own evaluation (`glb_rig.py`) within 2 mm in run, dive, cheer, hard landing and cart for 11 looks. | sound |
| Mesh LOD | The importer generates LODs per part (`meshes/generate_lods=true`). Godot picks a LOD only while its error projects under `mesh_lod_threshold`: 1 px on the standard tier and 3 px on the low tier (`quality.gd`). | bounded; see open items |

So a garment that is off the body in game is off the body in the asset. The
measurements below are on the asset, and then again in game in final poses.

## Defect register

Symptom → reproduction → measured cause → change → evidence. "Gap" is the
radial distance from an open edge to the surface that comes out of it (skin,
mitten, sock). "Parting" is how far two pieces that touch at rest separate
in a pose. Numbers are `fit_check.py` on the GLB unless marked "in game". It samples all 48 full-body clips at 10 Hz, 567 poses; the 5 additive layer clips are excluded.

| # | Symptom | Reproduction | Measured cause | Change (generator) | Evidence |
|---|---|---|---|---|---|
| F1 | Sleeve cuffs read as rings floating round the hand, with a dark band between cuff and hand | Every long-sleeved outfit, idle and arm-raised close-ups. `fit_check` "opening … cuff". | The sleeve kept its full width to the edge: 2–4.2 cm of air round the wrist on Night Owl, Cloud Nine, Bedtime Bandit, the onesies and the Night Watch; Raincoat 4.2 against its loose 2.5 bound. The inside was a lining at **50 %** of the fabric colour, turned in past the wrist, which reads as a near-black gap. **Geometry and vertex colour, not shading:** normals are consistent (see above). | `parts.sleeve_r` gathers the last 6 cm into a fitted cuff: the bare arm's radius plus `CUFF_EASE` (9 mm); the robe and raincoat keep their own ease. `lining_of` is 72 %, and the lining stops at the limb's surface. Knit and roll cuffs (varsity, arcade, mechanic, jogger wristband, cardigan) are sized from `sleeve_r`. | Worst fitted cuff 4.2 → 1.2 cm; robe 2.2 and raincoat 2.2 are within their loose bounds. Short and rolled sleeves 2.2 → 1.4 cm. Close-ups: "cuff", "cuff raised". |
| F2 | Shorts hems flare off the thigh; the hem hoop shows through the other leg | Arcade Sprinter, Varsity Sprinter, Campus Courier, Lantern Scout, Glow Jogger; run and knee-lift poses. | The hems were a constant 2.8–3 cm off the leg, so 3.4–8.0 cm off the thigh as it narrows, under hem rings sized for the flare. Leg pieces and rings crossed the body's midline by up to 2.1 cm into the other leg. | Hem ease tapers toward the edge (e.g. arcade `0.028 − 0.014·smoothstep`), and rings are sized to the tapered hem. `geo.clamp_midline` (3 mm gap, 2 cm soft zone) keeps every leg piece on its own side: `pant_legs`, `kit6.leg_tube` and `ring_on_leg`, `kit6.clamp_legs` for the suits, and the swim legs. | Thigh hem 8.0 → 1.5 cm. Midline crossing +2.1 → −1.0 cm (clear of the midline). Close-up: "hem / waist". |
| F3 | Shoulder caps, epaulettes and hood yokes lift off the sleeve with the arm up or diving | Hoodie, cardigan, raincoat, courier, scout, Night Watch; `emote_stargaze`, `dive`, `splash_dive`. | Caps carried fixed torso-only or arm-only weights while the sleeve under them blended torso → arm. They parted by 4.8–6.7 cm, and the Night Watch epaulette junction by 7.2 cm. | `parts.shoulder_cap_w` uses the sleeve's own blend: arm share by the position along the arm and by distance from the spine. It is used by every cap, the Night Watch epaulettes and the scout epaulette. | Attached seams ≤ 1.2 cm (bound 1.2). Junctions ≤ 1.2 cm (bound 2). Close-up: "shoulder". |
| F4 | The trouser top and the pelvis part at the front of the hip | Pumpkin Pajamas, splash jump, stop. In game: 8.1 cm in the `stop` scenario. | `torso_w` and `leg_w` blended hip → thigh over different heights. The pelvis piece and the trouser top, touching at rest, followed different bones and parted by up to 8.8 cm. | One shared blend: `rig.HIP_THIGH` / `hip_thigh_share()` in `torso_w`, and `leg_w` mixes `{hips, thigh}` over z 0.45–0.485. | Pumpkin Pajamas hip seam 8.8 → 0.7 cm. In game, Pumpkin Pajamas' worst anchor pair (all regions): 8.1 → ≤ 0.8 cm. |
| F5 | Slipper and boot collars, socks and capris part at the ankle | Pumpkin Pajamas socks, Cloud Nine slippers, Raincoat boots, pj over slippers; hard landing, dive. | `foot_w` was foot-only up to the ankle while the leg piece above it followed the shin. | `outfits_p8.foot_w` blends into `leg_w` at the back of the ankle (z 0.075–0.12). Cloud slipper collar weights are mixed with the leg. Pumpkin socks are fuller and topped below the capri. The rain boot shaft is lowered under the rain trousers. | Bedtime Bandit ankle seam (hard landing) 2.6 → 0.9 cm. Pumpkin Pajamas hem over the slipper 3.4 → 1.6 cm. Ankle openings ≤ 0.5 cm; over-shoe hems ≤ 4.0 cm (bound 4.5; pj's 4.0 is unchanged, an authored loose hem over a slipper). Close-up: "ankle". |
| F6 | Trim floats off its garment | Lantern Scout belt and woggle, Glow Jogger wristband, Cloud jogger rib. | Rings were placed by fixed radii, not on the surface they trim: the scout waist trim floated 0.9 cm. | Rings are sized from the surface they sit on (`kit6.ring_on_arm(r=…)`, woggle tails and ring, jogger wristband from `sleeve_r`, rib heights). | Worst trim +0.9 → +0.2 cm (bound +0.4: a trim may sink, never float). |

Lineage: the first version of the check (commit `ca32d89`) counted 148 failures on 2fff573. The tool was then refined (pocket edges are no longer openings; footwear hems use the over-shoe rule; loose bounds are keyed by garment), and the same before asset now gives 120. The after asset gives 0 with both versions.

### Per-look numbers, before → after (`fit_check.py`, cm)

Worst opening gap (bounds: 1.6 limbs and neck; 4.5 over a shoe; robe cuff
4; raincoat cuff 2.5), worst attached-seam parting (bound 1.2), worst
junction opening (bound 2), midline crossing (bound 0.2; negative = clear of
the midline), failures.

| Look | Opening | Seam | Junction | Midline | Failures |
|---|---|---|---|---|---|
| midnight_mechanic | 2.2 → 1.4 | 0.7 → 0.8 | 4.1 → 0.3 | −0.7 → −1.1 | 3 → 0 |
| moonwalk_cadet | 1.9 → 1.5 | 4.0 → 0.7 | 4.7 → 0.3 | 0.7 → −0.7 | 6 → 0 |
| pumpkin_pajamas | 3.4 → 1.6 | 8.8 → 0.7 | 4.2 → 0.0 | 0.1 → −0.8 | 4 → 0 |
| arcade_sprinter | 8.0 → 1.5 | 6.7 → 0.5 | 4.0 → 0.2 | 2.1 → −1.0 | 10 → 0 |
| cloud_nine | 4.2 → 1.2 | 0.8 → 0.8 | 4.7 → 1.0 | 0.5 → −0.7 | 5 → 0 |
| bedtime_bandit | 4.2 → 1.2 | 2.6 → 0.9 | 4.7 → 0.0 | 0.3 → −0.8 | 6 → 0 |
| after_hours_hoodie | 3.3 → 1.2 | 5.2 → 0.6 | 4.3 → 0.9 | −0.1 → −0.8 | 4 → 0 |
| night_owl | 4.2 → 1.2 | 5.7 → 0.7 | 4.7 → 0.1 | 0.3 → −0.8 | 6 → 0 |
| glow_jogger | 2.4 → 1.2 | 6.3 → 0.5 | 3.7 → 0.3 | 1.9 → −0.7 | 8 → 0 |
| library_cardigan | 3.8 → 1.2 | 5.5 → 0.5 | 4.5 → 0.0 | −0.4 → −1.0 | 4 → 0 |
| pj (default) | 4.0 → 4.0 (over shoe) | 5.2 → 0.5 | 3.9 → 0.1 | −0.5 → −1.0 | 4 → 0 |
| night_watch | 2.9 → 1.2 | 5.2 → 0.5 | 7.2 → 0.2 | −0.5 → −1.0 | 4 → 0 |
| varsity_sprinter | 8.0 → 1.5 | 6.6 → 0.6 | 4.0 → 0.3 | 2.1 → −0.9 | 12 → 0 |
| campus_courier | 3.4 → 1.6 | 4.8 → 0.7 | 4.2 → 1.2 | 1.5 → −0.9 | 8 → 0 |
| lantern_scout | 3.4 → 1.5 | 6.6 → 0.5 | 5.8 → 0.5 | 1.2 → −0.8 | 9 → 0 |
| raincoat_explorer | 4.2 → 2.2 | 5.3 → 1.1 | 4.4 → 0.4 | 0.0 → 0.0 | 4 → 0 |
| moonlight_runner | 2.4 → 1.2 | 6.5 → 0.5 | 3.8 → 0.6 | −0.6 → −1.1 | 4 → 0 |
| starry_sleeper | 2.8 → 1.2 | 6.7 → 0.5 | 4.0 → 0.1 | 0.4 → −0.7 | 6 → 0 |
| duck / frog | 4.2 → 1.2 | 6.2 → 0.1 | 4.2 → 0.1 | 0.3 → −0.8 | 6 → 0 each |
| robe | 2.2 → 2.2 | 0.5 → 0.9 | 4.1 → 0.1 | 0.0 → 0.0 | 1 → 0 |
| swim | 0.2 → 0.2 | 0.1 → 1.1 | 0.0 → 0.0 | −0.1 → −0.9 | 0 → 0 |

The two featured skins (Record Breaker, Dr. Doom) belong to SKINS9 and are
not on this branch; the integrator branch has them as of `8c6af2d`. Both
checks run on them after the merge (see
[Integrator steps](#integrator-steps)).

## The checks

### `tools/character/fit_check.py` (offline, the shipped GLB)

`glb_rig.py` is a numpy reader that evaluates the GLB the way an importer
does. It reads the skin's joints and inverse binds, the joints' rest
transforms, the baked channels, and linear-blend skinning with the 4
exported influences. `fit_check.py` uses it to measure every look as
Cosmetics shows it (outfit parts plus that outfit's shoes, 22 looks) through
every clip at 10 Hz:

- **weights**: sum to 1, none unweighted, joints in range, ≤ 4 influences,
  and split vertices at a seam carry the same weights.
- **normals**: per part, faces agree with their vertex normals (≤ 0.2 %
  flipped) and normals are unit length.
- **trims**: a closed ring round a limb or the torso (hem ring, roll, belt,
  boot collar). For each 15° sector, the ring's inner radius minus the
  outward-facing surface it sits on. Bound +4 mm: a trim may sink in, but
  may not float.
- **openings**: an uncovered open edge round a limb or the neck (cuff, hem,
  ankle, neck). For each sector, the edge radius minus the outward-facing
  surface coming out of it. Linings do not count as support, so a deep cuff
  with a dark lining is the gap it shows.
  - Region bounds: 1.6 cm for limbs and neck, 4.5 cm for a trouser hem over
    a shoe. Skirts are exempt. The robe's cuffs have 4 cm and the raincoat's
    2.5 cm.
  - Pocket edges are told apart by their axis. Hems under a cuff band, or
    trousers inside a boot, are skipped as covered.
- **crossing**: a trouser leg may not cross the body's midline (2 mm).
- **seams / junctions**: pieces of one garment that touch at rest. On the
  same main bone (a ring on its tube, a patch, a collar) they may part by at
  most 1.2 cm in any pose. Layers overlapping across a joint (a cap over its
  sleeve, the pelvis over a trouser top) may part by at most 2 cm.
- **fitted regions** (reported): garment radial offset from the posed limb
  axis at the shoulder, elbow, wrist, hip, knee and ankle.

Run it with `python3 tools/character/fit_check.py [--looks a,b] [--json out]`.
It exits with status 1 on a failure. `tools/character/build.sh` runs it after
every default build and regenerates the game fixture with
`--anchors game/tests/data/fit_anchors.json`. The fixture holds the anchor
pairs with their bounds and the asset's own skinned positions in five
reference poses.

### `game/tests/test_fit_p9.gd` (in game, the imported scene, final poses)

| Test | What it proves |
|---|---|
| `test_imported_skinning_setup` | Skeleton path, one Skin, named binds that invert the rests, identity transforms, 4 normalised weights, no unweighted vertex. Every part of a live `CharacterView` is skinned to its skeleton after `setup()`. |
| `test_runtime_deformation_matches_the_asset` | Imported vs runtime: the anchors re-skinned from the imported meshes and the AnimationPlayer's skeleton match the asset's own evaluation within 2 mm (11 looks × 5 poses). |
| `test_garments_stay_on_the_body_in_final_poses` | Every anchor pair is measured **in the final pose of every frame**, read from `Skeleton3D.skeleton_updated`, which fires after the last modifier (`pose_updated` would miss the pose fade, secondary motion, foot lock and the nightcap spring). It runs the gameplay motion rig (60 Hz mini-motor → interpolation → CharacterView → AnimationTree) for each look. Looks: the six Shop outfits, the four Season 1 pass outfits and the default pj, through start, stop, 180° reversal, ramp, jump and land at speed, dive and dive landing, and an emote interrupted by a run. The Night Watch goes through a patrol run, tag miss, tag hit and the cart. |
| `test_cosmetic_swap_mid_run_keeps_the_gait_and_the_fit` | An outfit swapped mid-run keeps the gait phase and fits from its first frame. |
| `test_interruptions_leave_no_layer_latched` | After each of reversal, stop, tag miss, tag hit, emote interrupt, dive and jump, these are all released: the stop one-shot, the action layer, the drive/brake/lead layers and the pose fade. A full-speed reversal plays no planted stop, and a stop plays exactly one. |

Bounds in game:

- 1.2 cm for pieces on one bone.
- 2 cm for layers across a joint.
- 3 cm across the ankle: a hem over footwear, or a shoe collar round the
  shin, whose two ends follow the foot to different extents (foot weight
  share differing by more than 0.2).

Results:

- **2fff573** (asset and view): 14 failures. The worst pair growth in game
  was 4.0–8.1 cm, and a reversal fires the planted stop.
- **p9-fit**: 0 failures at both runner speeds.
  - At 6.0 m/s, the worst growth for every look is ≤ 0.8 cm.
  - At 5.0 m/s (the committed default, sprint 7.4), the reversal pivots on
    a locked foot. The cardigan's trouser hem over moon boots and the pj hem
    over slippers part by 2.4 cm across the ankle (bound 3). Everything else
    stays ≤ 0.8 cm.

## Animation at the steady speeds (§8)

### What was reproduced

With `runner_speed = 6.0` (the Pass 9 movement contract, set locally only),
the integrator's CI showed 22 failures, all stop or reverse:

- test_motion_v5: stop 10.3, reverse 24.8.
- test_motion_v6: reverse slide 0.98 / 1.46; upper body 24.35 vs 23.23.
- test_outfits_p8 and test_outfits_v6: reverse 23–25 and stop 10.0–10.3 on every outfit.
- test_v8_motion: stop 10.2; head-led reverse 23.3, slide 0.98.

The motion rig (`tests/motion_rig.gd`: the motion tests' 60 Hz mini-motor
driving a CharacterView) traced both to the view:

- **Reverse.** At 6 m/s a 180° reversal passes through zero ground speed
  for a single 60 Hz tick. The view fired the planted stop one-shot that
  frame and aborted it the next: a 24.8 cm hand snap and a planted foot
  dragged at 1.09 m/s on average (probe).
- **Stop.** The stop one-shot's linear fade-in met the running arms at full
  swing: a 10.0 cm hand snap.
- **Layers.** The drive, brake and turn-lead additive layers and the tag
  action weight eased as first-order exponentials. These start at full rate,
  which kicked the hands at a brake onset and as a Night Watch's tag
  recovery ended (16.0 cm).

### Changes (`game/src/view/character_view.gd`, animation paths only)

- A planted stop needs the body to stay stopped for 30 ms over at least two
  frames (`STOP_DEBOUNCE`), and fires once per stop (`_stop_fired`). It
  starts, and is cancelled, from the pose on screen (`_fade_from_shown(0.14)`,
  the existing dead-blend pose fade).
- The drive, brake and lead layer weights move as critically damped springs
  (`_spring`, 1/120 s sub-steps, frame-rate independent). Weight and rate
  stay continuous. `_clear_layers` resets the rates; teleport and respawn
  still cut.
- A full-body action (tag lunge or recovery) that ends after its state
  settled hands back through the pose fade. When the action is mid-fade or
  going into another full-body state, it eases out with the spring.
- A stop made in another state belongs to that state. Outside the ground
  state, the remembered run pace (`_run_mem`) follows the real speed. Before,
  an emote, landing or dive recovery entered at speed and left standing
  still played the planted stop late from a standstill. In the emote probe
  this was 5.0 cm with that change alone; now it is 3.8.
- One-shot construction is factored into `_one_shot()` with the same fade
  times; eased curves were tried and rejected (see below).
- No root motion, no change to the sim, collision timing, protocol or the
  `"sprinting"` key. The view still reads `rs["sprinting"]` only for the
  footstep level and the determined brow (the integrator renames it to
  `"fast"`). No exhaustion-driven pose exists in the view: the Pass 8
  exhausted latch lives only in the sim, which the integrator removes.

### Gait blend

`LOCO_POINTS` (`walk 1.3`, `run 5.0`, `sprint` = fast-run `7.0`) places the
clips in the locomotion blend space. At the steady speeds:

- Runner 6.0 m/s: half run, half fast-run, 2.42 cycles/s.
- Night Watch 6.6 m/s: 80 % fast-run, 2.55 cycles/s.

Cadence follows ground travel (stride from `runner_manifest.json`;
`test_animation` checks 2.0–2.7 cycles/s at both speeds). I compared
candidate points in the motion rig at 6.0, from one starting gait phase
(hand pop / planted-foot slide p95):

| run / fast-run points | stop | reverse | Night Watch run | walk start-stop |
|---|---|---|---|---|
| **5.0 / 7.0 (kept)** | 5.0 cm / 0.36 m/s | 4.2 cm / 0.31 | 3.9 cm | 5.3 cm |
| 4.6 / 7.0 | 5.6 / 0.92 | 5.7 / 0.31 | 5.6 | 5.3 |
| 5.0 / 7.4 | 5.6 / 0.31 | 5.1 / 0.31 | 4.1 | 5.3 |
| 5.4 / 7.4 | 6.1 / 0.45 | 6.8 / 2.74 | 4.0 | 5.3 |
| 4.2 / 6.6 (fast-run at full input) | 5.0 / 0.85 | 8.1 / 0.31 | 5.0 | 7.5 |

Moving the fast-run clip to the steady speed doubled the reversal snap and
the stop slide, so I kept the V8 points. There is no sprint burst for the
gait to depend on: the blend is a continuous function of ground speed.

### Motion survey at 6.0 m/s, 2fff573 → p9-fit

Measured with the committed `src/dev/motion_probe.tscn`: MotionRig scenarios,
each from three starting gait phases. Pops are the worst of the three runs;
slides are the mean over all. Both trees ran with `runner_speed = 6.0` set
locally.

- "Pop" is the largest third difference of an upper-body joint (cm), the
  motion tests' measure.
- "Leg pop" is the same measure on the legs.
- "Slide" is the planted-foot speed.

| Scenario | Pop, cm | Frames > 3 cm | Leg pop, cm | Slide mean / p95, m/s |
|---|---|---|---|---|
| start | 5.3 → 5.3 | 18 → 18 | 14.9 → 15.0 | 0.025 / 0.24 → 0.025 / 0.24 |
| stop | 10.0 → 4.9 | 30 → 36 | 14.9 → 15.0 | 0.112 / 0.64 → 0.076 / 0.35 |
| walk_start_stop | 5.4 → 5.4 | 11 → 12 | 4.1 → 4.1 | 0.063 / 0.49 → 0.064 / 0.49 |
| reverse | 24.8 → 4.5 | 31 → 23 | 37.4 → 15.0 | 1.089 / 10.15 → 0.036 / 0.32 |
| turn90 | 3.8 → 3.8 | 14 → 14 | 18.2 → 18.2 | 0.040 / 0.30 → 0.041 / 0.35 |
| speeds | 5.5 → 5.4 | 11 → 11 | 15.7 → 15.8 | 0.009 / 0.04 → 0.009 / 0.04 |
| jump_run | 10.6 → 10.6 | 53 → 53 | 14.9 → 15.0 | 0.055 / 0.34 → 0.054 / 0.32 |
| jump_idle | 9.8 → 9.9 | 39 → 39 | 3.3 → 3.3 | 0.043 / 0.26 → 0.042 / 0.26 |
| dive | 8.9 → 8.8 | 71 → 71 | 17.0 → 17.1 | 0.754 / 8.51 → 0.754 / 8.51 |
| kerb | 7.1 → 7.1 | 62 → 65 | 14.9 → 15.0 | 0.124 / 1.40 → 0.124 / 1.42 |
| flicker | 3.8 → 3.8 | 12 → 12 | 14.9 → 15.0 | 0.050 / 0.46 → 0.050 / 0.46 |
| tag_miss | 16.0 → 12.7 | 67 → 62 | 41.8 → 41.8 | 0.952 / 12.53 → 0.824 / 12.53 |
| tag_hit | 10.9 → 10.1 | 72 → 57 | 16.9 → 16.9 | 0.092 / 0.61 → 0.094 / 0.61 |
| splash | 14.0 → 14.0 | 125 → 125 | 14.9 → 15.0 | 0.058 / 0.48 → 0.059 / 0.47 |
| cart | 5.0 → 5.0 | 9 → 9 | 14.8 → 14.8 | 0.342 / 0.88 → 0.340 / 0.88 |
| emote | 3.9 → 3.8 | 22 → 17 | 13.6 → 13.7 | 0.430 / 5.02 → 0.399 / 5.02 |
| hitch | 3.8 → 3.8 | 12 → 12 | 14.9 → 15.0 | 0.029 / 0.30 → 0.030 / 0.31 |
| jitter | 3.8 → 3.8 | 12 → 12 | 14.9 → 15.0 | 0.030 / 0.31 → 0.030 / 0.35 |
| respawn | 8.8 → 8.7 | 33 → 33 | 14.9 → 15.0 | 0.120 / 0.53 → 0.120 / 0.53 |
| correction | 4.3 → 4.3 | 33 → 33 | 17.2 → 17.2 | 0.027 / 0.23 → 0.027 / 0.23 |
| nw_run | 4.0 → 4.1 | 18 → 18 | 13.4 → 13.4 | 0.037 / 0.34 → 0.036 / 0.30 |
| sprint | 3.8 → 3.8 | 12 → 12 | 14.9 → 15.0 | 0.040 / 0.30 → 0.040 / 0.33 |
| ramp | 3.8 → 3.8 | 12 → 12 | 14.9 → 15.0 | 0.033 / 0.30 → 0.033 / 0.30 |

The remaining larger values are authored impact sharpness, which I left
alone. All are unchanged from 2fff573 except the tag miss, which fell:

- the splash resurface (14.0);
- landings after a jump (≈ 10);
- the Night Watch's tag wind-up and lunge (10–13; the lunge is a 9 m/s
  burst, hence its leg pop and slide);
- respawn (≈ 9) and the dive (≈ 9). Smoothing them is exactly what would
soften the V8 clips and the 0.45 s `dive_land`. Two experiments were tried
and reverted:

- Baking clips at 60 fps: no change in pops, and the GLB grew by 1.4 MB.
- Eased one-shot curves: landings popped more.

### Preserved

- The V8 clips and the 0.45 s `dive_land` (`clip_check`,
  `test_v8_motion::test_asset_has_the_v8_clips`).
- Foot contact and terrain contact (`test_v8_motion`, `test_motion_v6`).
- Reduced motion: the layer gains and secondary motion are still halved.
  The code paths are untouched.
- Remote interpolation and respawn cuts (`test_motion`).
- Animation LOD hysteresis (`test_motion_v5::test_lod_has_hysteresis_and_keeps_time`).
- Teleport reset (`test_motion_v5::test_teleport_cuts_pose_and_resets_history`).
- Distant animation keeps real time (`test_animation`).
- The shared authoritative motor (no sim change on this branch).

## Evidence index

All renders are desktop renders: Godot 4.7.2 Mobile renderer on Linux
llvmpipe under Xvfb. They are look and fit evidence, not device, frame-rate
or touch evidence.

| File | What |
|---|---|
| [`closeups_<outfit>.jpg`](../media/pass9/fit/) (15) | Matched close-ups, BEFORE 2fff573 over AFTER p9-fit: same camera, pose and look per column, dorm light. Columns: neck (`emote_cheer` 0.3 s), shoulder (`dive` 0.2 s), cuff (idle), cuff raised (`emote_cheer` 0.3 s), hem/waist (`run` 0.3 s), knee (`land_hard` 0.15 s), ankle (idle). Outfits: the six Shop outfits, the four pass outfits, pj, Varsity Sprinter, Campus Courier, Lantern Scout, Raincoat Explorer. Rendered in both trees with `src/dev/character_lineup.tscn --lineup=custom --light=dorm --shots-file=…` (420×420 tiles). |
| `reel_<outfit>_before_after.mp4` (3) | Side-by-side motion reels at normal speed, BEFORE 2fff573 (left) and AFTER p9-fit (right). Arcade Sprinter, Moonwalk Cadet, Pumpkin Pajamas through start, 180° reversal, stop and dive in close-up, from `motion_reel_v8.tscn` (the motion tests' 60 Hz motor → CharacterView path) at runner_speed 6.0, fixed 30 fps clock, scripted input. Recorded with `tools/character/capture_fit_reel.sh`. |

Numbers: `python3 tools/character/fit_check.py --json …` and the
`FIT_P9` line printed by `test_fit_p9`. The before tree is a `git archive`
of 2fff573 under the ignored `build/before/`, with the same local
`runner_speed = 6.0`.

## How verified

All runs were on desktop Linux and were focused, not the whole suite.

| What | Result |
|---|---|
| `python3 tools/character/fit_check.py` (p9-fit GLB) | 22 looks, 567 poses, **0 failures**. The same tool on 2fff573's GLB gives 120. |
| `tools/character/build.sh` (full rebuild) | Deterministic: the same `runner.glb` (sha256 `a7493a56…`, art version `v9-a7493a564e73`), manifest and `character_art.gd`. fit_check runs and the fixture is regenerated. The fixture is identical under the bpy environment's numpy 1.26 and the system's numpy 2.4. |
| `clip_check.py`, `outfit_check.py` (bpy env) | Exit 0. 0 clips with the arms > 1 cm inside the head or goggles; outfit_check 0 failures; gloves 0 mm outside. |
| Godot, 12 files at `runner_speed` 5.0 (committed) | 70 tests, 1232 checks, **0 failures**. Files: test_fit_p9, test_animation, test_motion, test_motion_v5, test_motion_v6, test_v8_motion, test_outfits_v6, test_outfits_p8, test_characters_v7, test_portraits, test_emotes, test_motion_layer. |
| The same 12 files at `runner_speed` 6.0 (local only) | 70 tests, 1233 checks, **0 failures**. This includes the 22 stop/reverse checks the integrator reported failing at 6.0 (below). |
| Budgets | `test_outfits_p8::test_budgets_against_the_heaviest_look` (heaviest look not above its old count, ≤ 7 draw calls) and `test_outfits_v6::test_triangle_budgets` pass. Triangle changes: Cloud Nine +64 (11,940 → 12,004), Raincoat +48, Lantern Scout +24. Every other part is unchanged, so the heaviest look's ~32.8k triangles are unchanged. |

The 22 integrator-reported failures at 6.0 m/s now pass. The cause and the
fix are in "What was reproduced" and "Changes" above; no bound was changed.

| Test | Was at 6.0 | Now |
|---|---|---|
| `test_motion_v5::test_transitions_do_not_snap` | stop 10.3, reverse 24.8 | pass |
| `test_motion_v6` turns and straight running | reverse slide 0.98 and 1.46; the "upper body untouched" check (24.35 vs 23.23) | pass |
| `test_outfits_p8::test_every_outfit_moves` | reverse 23–24.6 on the Shop outfits | pass |
| `test_outfits_v6::test_every_new_outfit_moves` | stop 10.0–10.3 and reverse 23–25 on every V6 outfit | pass |
| `test_v8_motion::test_a_stop_from_a_run_plants_once` | stop 10.2 | pass |
| `test_v8_motion::test_turns_are_led_by_head_and_chest` | reverse 23.3, slide 0.98 | pass |

## Open items

- **Physical phone.** Not verified on a device. The fit numbers are
  geometric and hold on any GPU. What a phone adds is the low-tier mesh LOD
  (`mesh_lod_threshold` 3 px): a garment and the body under it are
  simplified independently, so a layer about 1 cm off the skin can show up
  to that many pixels of the other at distance. It needs one look on the
  low tier in a match.
- **Impact sharpness** (splash resurface, landings, tag lunge, respawn) is
  authored and left as is (see the survey).
- **Hidden overlaps.** Shells over the hips sink into the body under
  covering layers; this is intended and not visible. Rain boots and the
  raincoat cuff use their loose bounds.
- **Ankle pivot at 5.0 m/s.** At the committed speeds (5.0, sprint 7.4)
  the reversal pivots on a locked foot. Hems over footwear part by up to
  2.4 cm across the ankle, within the 3 cm ankle bound. At 6.0 this does
  not happen (≤ 0.8 cm).
- **Hood at the neck.** The hood is measured as a loose garment and not
  checked against the neck the way a collar is.
- **Dorm stage "sprint" preview.** `dorm_stage` previews the run at
  `runner_sprint_speed`; it should use the role's full speed once the
  integrator removes the sprint speed.
- **Face** (blinks, brows, mouth) and the featured skins' head variants
  are SKINS9's. Nothing here changes the face paths.

## Integrator steps

1. Merge `p9-fit` onto the integrator branch, which has p9-pass100 and
   p9-skins as of `8c6af2d`. This branch does not touch
   `build_character.py`, `skins_p9.py` or `cosmetics.gd`.
   - In `character_view.gd` it touches only the animation paths:
     `LOCO_POINTS`' comment, the stop debounce fields, `_one_shot`,
     `_update_act`, `_update_layers`, `_spring`, `_begin_stop`,
     `_clear_layers` and `_update_ground`. It also adds one line in
     `_process_view`'s non-ground branch (`_run_mem = speed`).
   - Both branches regenerate the GLB, manifest and `character_art.gd`.
     Take either version, then rebuild.
2. Run `tools/character/build.sh` once on the merged tree. It regenerates
   `runner.glb`, `runner_manifest.json`, `character_art.gd` and (new)
   `game/tests/data/fit_anchors.json`. Re-import with
   `tools/gd.sh --headless --path game --import`.
3. Run `python3 tools/character/fit_check.py` (expect 0 failures),
   `clip_check.py` and `outfit_check.py`.
4. Bring the featured skins into the fit checks:
   - `fit_check.looks()` reads `OUTFIT_PARTS` / `OUTFIT_OWN_SHOES` from
     `cosmetics.gd`. If Record Breaker and Dr. Doom are complete-skin
     overrides outside `OUTFIT_PARTS`, add their part lists to `looks()`.
   - Add `record_breaker` and `dr_doom` to `REFERENCE_LOOKS` in
     `fit_check.py` and to `MOTION_LOOKS` in `test_fit_p9.gd`. Check that
     the test's `_cosmetic()` turns each into the Cosmetics look that wears
     it.
   - Rebuild the fixture with
     `python3 tools/character/fit_check.py --anchors game/tests/data/fit_anchors.json`.
5. With `runner_speed = 6.0`, run `test_fit_p9`, test_animation, test_motion,
   test_motion_v5, test_motion_v6, test_v8_motion, test_outfits_v6,
   test_outfits_p8, test_characters_v7 and test_portraits.
6. The `"sprinting"` → `"fast"` rename in `character_view.gd` touches only
   the footstep level (`_update_ground`) and the face read (`_update_face`).
   The view does not depend on sprint bursts. `motion_rig.gd`'s `"fast"` key
   (on floor, not diving, ≥ 0.85 × role speed) feeds the same two reads.
7. `dorm_stage`'s "sprint" preview uses `runner_sprint_speed`; switch it to
   the role's full speed when that setting goes.
