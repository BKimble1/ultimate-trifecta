# Final release sweep · garments at the large preview scale (ARTFIX)

The Season Pass, Shop and Locker now show the runner on the dorm stage at
about three times the old side preview's height and let the player turn it
through 360 degrees. At that size, pieces that were built a few centimetres
off the body read as floating. This workstream fixed them where they are
generated (`tools/character/*.py`, Blender bpy 4.5.4), rebuilt
`runner.glb`, and added a fit_check rule that would have caught them.

Base: `4f82df6`. The character asset and its sources there are unchanged
since `e3c2cd6` (1.9), which is the "before" in every picture.

**What these notes can claim.** Everything was built and measured on
desktop Linux: the bpy checks, headless Godot 4.7.2 tests, and desktop
renders (Mobile renderer on Mesa llvmpipe under Xvfb with
`GALLIUM_OVERRIDE_CPU_CAPS=avx`, so characters keep their directional
light). No device was used. The two likeness skins are only "Record
Breaker" and "Dr. Doom" here. Dr. Doom's construction changed; his look
did not (same colours, lapels, buttons, triangle count).

## Defect register

Gaps are fit_check's standoff measures (below), worst case over the rest
pose and every hair style the piece is worn with. Positive means standing
off; negative means sunk into what is under it.

| # | Symptom at the stage scale | Reproduction | Measured cause | Fix | Before → after |
|---|---|---|---|---|---|
| 1 | Night Owl and Bedtime Bandit: the cream belly patch floats off the body in profile as an oval disc (Duck and Frog share the builder) | Locker or Shop, select the outfit, turn to profile; `fit_check.py --looks night_owl,bedtime_bandit,duck,frog` | The patch was a flat ellipsoid placed tangent to the front of a round belly; its lower rim stood off the suit by the belly's fall-off | `parts.belly_panel`: the panel is bent onto the suit (`kit6.conform`, centre 1.2 mm under the surface), and sits 1 cm higher (Duck, Frog and Night Owl also 1 cm shorter) so its lower edge stays clear of where the suit turns in at the crotch. The owl's feathers now lie on the panel's top | Owl 6.4 → −0.3 cm, Bandit 9.8 → 0.2 cm, Duck and Frog 8.0 → −0.9 cm (bound 0.6) |
| 2 | Hood face ring forward of the face, face set back inside it (Night Owl, Bedtime Bandit, Cloud Nine, Duck, Frog) | Same, profile and three-quarter; `fit_check` "face rim" | The hood shell kept its full 3.5 cm grow right to the opening and the rim sat on it | `parts._hood`: the shell rolls in over the last 28% of the opening's radius to `HOOD_EDGE_GROW` 2.45 cm and the rim sits on that edge (inner side 4.5 mm off the face; `test_outfits_p8` still sees every hood at least 4 mm off the skin). The duck bill, owl beak and eye discs, frog cheek spots and Cloud Nine's puffs are re-seated on the rolled hood (the puffs 9 mm lower, to keep the shush emote's hand clear) | 2.1 → 0.9 cm on all five (bound 1.0) |
| 3 | Dr. Doom: the open jacket's front edges, facing and lapels read as dark strips standing off the shirt | Locker, Dr. Doom, profile and three-quarter; `fit_check --looks dr_doom` "edges" | The jacket's below-the-waist width floor (19.6 cm radius) was applied at every height, holding the jacket out above the chest where the torso narrows to the neck; the front edges stood 2.4 cm off the shirt on average | `skins_p9.jacket_base`: the floor applies below the waist only. `jacket_edge_pull` rolls the last ~10 cm before each front edge in to 8 mm over the shirt (clear of the belt) between the waist and the gorge; the 40 columns are spaced closer at the edges | Front edge 4.0 cm (mean 2.4) → 1.0 cm (mean 0.7) (bound 1.2) |
| 4 | Dr. Doom: the jacket's back is a flat rectangular slab in profile and from behind | Same, back and profile; `fit_check` "silhouette" | The same floor stood the jacket up to 8.8 cm off the shoulders and upper back, ending in a flat ring round the neck; below the waist the back hung straight down from its widest point and flared | The floor fix above, and `jacket_back_fit`: going down from the waist the back comes in at most 0.45 m per metre and never closer than 2.5 cm over the trousers' seat | Upper chest and back 8.8 → 3.9 cm off the torso (bound 6.0); back hem flare +0.4 → −5.8 cm (bound 0.0) |
| 5 | Glow Jogger with the Headlamp: the band reads as a halo round the head from behind | Locker, Headlamp with a tuft, curly or buns style, back and three-quarter back; `fit_check --heads` | The band and its top strap were a fixed 2.5 cm off the head, sized for the bob (2.4 cm); the other styles are 1.6–1.8 cm | `outfits_v6._band_ring`: the band lies on the hair round the back, sides and temples (`HAIR_BAND_G` 1.75 cm) and dips onto the bare forehead under the lamp; the top strap lies on the hair; the strap is 9 mm thick so its top edge and stripe stay in view where it presses into a bob | Ring and strap 2.8 → 0.3 cm (bob 0.3 → −0.1) (bound 0.4) |

Found by the same rule in the catalogue sweep and fixed the same way (the
band builder's constants):

| Piece | Before → after (bound) |
|---|---|
| Glow headband ring; its star | 1.3 → 0.3 cm (0.4); 4.1 → 1.4 cm (3.0) |
| Owl ears hat's band over the crown | 2.7 → 0.2 cm (0.4) |
| Sleep mask's strap (also 9 mm thick, so it shows whole on the bob) | 1.1 → 0.3 cm (0.4) |
| Night Owl hood eye discs (bent onto the hood); wrist feathers (on the sleeve's own radius, which gathers into the cuff) | 0.5 → −0.3 cm and 0.7 → 0.05 cm (small pieces, already inside 3.0) |

## The new fit_check rule: standoff

`tools/character/fit_check.py` measures, along each surface's own normal,
how far a piece that should lie on the body stands off it (module docstring,
"Final sweep (ARTFIX): standoff"). It runs on every look in the rest pose
and through every clip, and on every hat with every hair style it is worn
with (`--heads`):

- **patches**: flat pieces on a larger piece (belly panels, badges,
  pockets, lapels, decals, feathers, eyes on a hood). A panel 10 cm or more
  across must lie within 6 mm and not overhang; a smaller piece within 3 cm
  (a raised detail). In every pose no patch vertex may lift off the plane
  of the surface face under it by more than the seam bound.
- **bands**: rings and straps on the head, per 15-degree sector, measured
  toward the head's centre to the hair, head or face under them: 4 mm (the
  trim bound); a hood's face rim, which must keep 4 mm off the skin, 1 cm.
  Hat brims and cuffs are not bands.
- **edges**: the free front edge of an open jacket, cardigan or vest
  between the waist and the collar, straight in to the layer under it:
  1.2 cm. Pairs may not part by more than the seam bound in any pose.
- **silhouette**: a top across the upper chest and back may stand at most
  6 cm off the torso, and the back of a hip-length top may not flare out at
  its hem beyond its waist.

`STANDOFF_ALLOW` names the designed 3D pieces, each with its reason: the
Campus Courier's messenger bag, the Moonwalk Cadet's life-support pack, the
Raincoat Explorer's hood piping, the cadet cap's visor frame and ear pads.

Run on the 1.9 asset, the rule reports **29 failures** (every defect above,
on each hair style); on the rebuilt asset **0**.

## Checks

| Check | Result |
|---|---|
| `tools/character/build.sh` (build + fit_check, rewrites `game/tests/data/fit_anchors.json`) | `runner.glb` sha256 `49a45748…bfb3`; `CharacterArt.VERSION` `v10-49a45748ffed` (portrait keys change, old thumbnails are not reused) |
| `fit_check.py` on the rebuilt asset | 24 looks, 567 poses, 52 head looks: **0 failures** (1.9 asset: 29) |
| `skins_check.py` | 0 failures |
| `outfit_check.py` | 0 failures (Cloud Nine's shush emote hand 5.2 cm from the puffs, limit 5.7) |
| `clip_check.py` | 0 clips with the arms inside the head or goggles |
| Budgets (`runner_manifest.json`) | Bedtime Bandit 11475 → 11470 triangles, every other mesh unchanged; 59 parts; one shared material |
| `tools/gd.sh --headless --path game --import` | exit 0 |
| Focused suites: test_fit_p9, test_skins_p9, test_outfits_v6, test_outfits_p8, test_characters_v7, test_portraits, test_profile, test_motion_v5, test_motion_v6, test_v8_motion, test_season_stage, test_season100 | **87 tests, 2090 checks, 0 failures** |

## Evidence

[`../media/final/artfix/`](../media/final/artfix/): before (1.9 asset)
above, after below, same cameras and dorm lights, each labelled "desktop
render". Rendered with `tools/character/capture_inspection.sh OUT zoom bands`
(shot lists from `tools/character/inspect_shots.py`); the same script
renders the whole catalogue (`outfits_1` … `outfits_6`, `hats`: every
outfit and hat from the front, three-quarter, both profiles and the back at
the stage's on-screen size), which was inspected before and after, and
`bands` (each head band with each hair style from behind). The bands sheet
caught one problem with the first version of this fix: the sleep mask's
strap, 7 mm thick on the new line, showed only in dashes where it pressed
into the bob (Starry Sleeper's own look); it is now 9 mm, like the
headlamp's, and shows as one band.

| File | Shows |
|---|---|
| `night_owl_profile_back.jpg` | #1, #2: belly panel in profile, back, hood rim in profile |
| `bedtime_bandit_profile_back.jpg` | #1, #2 |
| `hoods_cloud_duck_profile.jpg` | #2 on Cloud Nine and the Duck (shared hood builder), #1 on the Duck |
| `dr_doom_profile_back.jpg` | #3, #4: both profiles and the back |
| `glow_jogger_headlamp_back.jpg` | #5: profile, three-quarter back, back |
| `headlamp_every_hair_back.jpg` | #5 with the tuft, bob, curly and buns styles |
| `sleep_mask_every_hair_back.jpg` | the sleep mask's strap with the same four styles |

## What's left

- Small raised pieces stay inside the 3 cm small-piece bound and were not
  changed: the belt buckles of Night Watch (2.2 cm), Midnight Mechanic
  (1.9), Lantern Scout (1.8) and Moonwalk Cadet (1.5); two pairs of pieces
  on the Campus Courier (at the upper chest 2.1, at the hips 1.7); a
  Library Cardigan chest piece (1.6); the shoe glow decals (1.3–1.8); a
  piece on the pumpkin cap (1.2); the glow headband star (1.4); and the
  sleep mask's lower edge over a bare forehead (1.7–1.8). At the stage
  scale they read as raised details; none was flagged in the catalogue
  inspection.
- Small pieces with part of their edge over nothing are reported, not
  failed: the After Hours hoodie's front pocket (0.6 cm where a surface is
  under it) and small pieces at the backs of the Midnight Mechanic's and
  Raincoat Explorer's lower legs.
- The designed 3D pieces in `STANDOFF_ALLOW` stand off by design (the
  courier bag at the hip, the cadet's pack at 5.4 cm).
- One hat mesh is worn with every hair style, so a band can lie on the
  thinner styles or on the bob, not both: bands now lie on the thinner
  styles and press up to 6 mm into the bob. On the bob the headlamp shows
  its strap's top edge and reflective stripe, the sleep mask's strap and
  the glow headband show whole, and the owl ears' band is hidden in the
  bob (as it was in 1.9).
- The belly panels moved up rather than refining the suit's coarse lathe
  under the crotch (budget).
- `outfit_check.py`'s analytic hood shell still uses the full grow, so its
  hood clearances are conservative now that the hood rolls in.
- No device verification: desktop renders only.

## Integrator steps

1. Merge the branch (one commit). If another workstream rebuilt
   `runner.glb`, do not pick a side for `runner.glb`, `runner_manifest.json`,
   `character_art.gd` or `fit_anchors.json`: merge the sources and run
   `tools/character/build.sh` again.
2. `tools/gd.sh --headless --path game --import`.
3. Re-run `fit_check.py`, `skins_check.py`, `outfit_check.py`,
   `clip_check.py` (all `tools/.cache/bpyenv/bin/python`) and the focused
   suites above.
4. Portrait thumbnails regenerate on first use (new art version).
