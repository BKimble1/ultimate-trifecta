# V7 character notes: goggles that fit, and another pass on the shared runner

Work stream: brief §8 ("Another real character pass, especially goggles and
accessories") and the portrait-cache invalidation for changed art. Media:
[../media/v7/characters/](../media/v7/characters/README.md).

**What these notes can claim.** Geometry was measured on the generator's
own output (offsets from the shared head surface, symmetry, winding) and on
the imported `runner.glb` by `game/tests/test_characters_v7.gd`. Pictures
are Godot 4.7.2's Mobile renderer on Mesa llvmpipe under Xvfb, same shots
and cameras before and after. Nothing here is a phone measurement: frame
cost, heat and feel on an iPhone are unmeasured.

## The goggles: what was actually wrong

The swim cap (`hat_swimcap`, catalog `swimcap`, "Swim Cap + Goggles") is the
only goggles-bearing item. Every outfit, hat and headwear entry was checked:
the headlamp has a lens (a lamp, emissive, unchanged), the Starry Sleeper's
sleep mask has none. Measured on the V6 generator output (`parts.py
build_swimcap`, offsets from the head skin; the cap shell sits at 12-14 mm)
and confirmed in renders (front, 3/4, side, rear, above, below; 16 poses;
dorm and campus light; all eight tones; every face and brow preset):

| Symptom (V6) | Cause in the source | Evidence |
|---|---|---|
| A dark ring floating round the head, sticking out past the temples in front views and standing off the cap in 3/4, side and rear views | The strap was one planar torus (`lathe` of a 6-sided profile) round the head centre, offset 13 cm and tilted 14° about X, with a radius taken from the head width at another height. A plane cannot follow a head, so it floated 15-61 mm off the skin (0.2-4.8 cm off the cap) all the way round | `goggles_zoom_*.jpg`, `goggles_views_*.jpg`; the V7 test on the V6 asset: "frame stands < 4 cm off the skin (58.1 / 61.5 mm)" |
| The strap crossed the face at brow height, below the lenses, 4-5 cm in front of the forehead | Tilting the ring forward put its front at z 1.22-1.25 m (brows 1.25-1.27, lens centres 1.335) | same |
| Two teal "buttons" on the forehead, not goggles | Each lens was a separate ellipsoid with a torus frame; nothing between them (7.4 cm gap: no bridge) and nothing linking them to the strap | `goggles_zoom_*.jpg` (front, from above) |
| Lenses half-buried | The lens ellipsoid's back half sat inside the cap shell (lens 12.3 mm off the skin, cap 12-14 mm) | probe |
| Broken dark fragments under the lenses | The cap's front edge was at z ≈ 1.22 m, below the brows; the brows (tubes up to 13 mm proud, 1.27 m; 1.30 m with `brow_up`) poked through the 13 mm shell | `goggles_faces_*.jpg`; V7 test on V6: "brows (neutral) ... top 1.276 m, edge 1.239 m" and every other face shape |
| Staircase cap edge at the sides and back | The cap was a full shell with whole quads dropped by a `keep` predicate (the defect V6 already fixed for hood openings) | side and rear views |
| (Not a defect) | Lens facing followed the surface normal; the two sides were symmetric by formula; normals smooth | |

## The rebuild (tools/character/parts.py, "V7 swim cap + goggles")

Everything is placed on the shared head shell at the cap's grow
(`rig.head_*`, `parts._shell_point`, `kit6.head_project`), so the fit comes
from the head geometry, not from offsets tuned per frame, and it is the same
in every animation (the cap and goggles are rigid on the head bone).

- **Cap:** a `hair_shell` (like the hair) at 13 mm whose edge is a smooth,
  symmetric cosine series: 1.305 m on the forehead (above the brows,
  raised brows included), arched to 1.26 m over the ears, down to 1.075 m at
  the nape. A rolled bead gives the edge its thickness.
- **Cups:** one cup built on the right and mirrored
  (`MeshBuilder.merge_mirrored_x`), so the pair is exactly symmetric. A
  rounded superellipse outline, 8.9 cm wide, 5.8 cm tall at the nose side
  and 7.1 cm at the temple. The gasket's back edge is projected onto the cap
  (sunk 1.5 mm, so no gap shows at grazing angles); its top is a plane;
  the rounded rim turns in to a slightly domed lens. The lens plane is
  turned 11° down from the forehead's slope (15° above horizontal instead
  of 26°) so the lenses read from the front; the wall is 6-18.5 mm.
- **Bridge, clips, strap:** a 1 cm band across the forehead from inside one
  cup to inside the other, lying on the cap; a rounded clip at each temple
  overlapping the cup's wall; a 2.4 cm strap from clip to clip round the
  back, lying on the cap (13-18 mm off the skin) and easing from the clips'
  height to 1.27 m at the back.
- **Tinted lens, cheap on Mobile:** a new material class in the shared
  shader (`geo.MAT_LENS`, `character.gdshaderinc`): opaque (no blending, no
  sorting, no extra pass), the tint gradient (deep at the bottom, sky toward
  the top) and a soft glint baked into vertex colour, a fresnel sheen in the
  scene's rim colour (warm indoors, cool under the moon) and a little
  self-light so it reads as glass at night. Roughness 0.2, not a mirror, so
  the highlight does not shimmer. Same `ShaderMaterial`, no new material or
  draw call.

Measured (generator output): lenses 17-27 mm off the skin, frames
11.5-30 mm (their base on the cap), strap and bridge 13.4-18.2 mm, cap
median 13 mm; mirror error 0.0 mm; every lens face looks away from the head.
`clip_check.py` now also measures sleeves and mittens against the goggles'
real vertices: 0.0 cm in all 46 clips (the cheer, stargaze and shush raise
their mittens nowhere near the forehead).

## The rest of the runner

All on the shared asset (dorm, Locker, Shop, Pass, gameplay and results use
the same `runner.glb`). Close-ups before/after: `refinements_*.jpg`.

- **Eyes:** the white's dome was 2 cm deep (`EYE_D` 0.02); in 3/4 views the
  far eye broke the cheek's silhouette like a sticker. Now 1.25 cm, with the
  lash line, iris, pupil and catch-lights following the new depth. Shape keys
  (blink, squint, face presets) are unchanged in kind.
- **Ears:** V6 pushed a darker disc through the ear's face: an orange slit
  with a jagged edge on light tones, a sticker from 3/4. Now an ear body
  sunk into the head at its front edge, the bowl shaded into it by vertex
  colour (no second surface to intersect) and a helix rim round the top and
  back.
- **Mittens and wrists:** a wrist neck runs from inside the forearm or
  sleeve into the palm; the palm is tapered at the wrist and a little
  cupped; the thumb branches from the side of the palm (V6: a dome stuck on
  the mitten's face). Bare forearms (swim, robe, the V6 short-sleeve
  outfits) ease into the wrist and end round inside the mitten (V6: a
  hard-edged flat disc at the wrist; `kit6.skin_arm` left an open ring).
- **Cuffs and hems:** `parts.sleeves` closed every long sleeve with a flat
  disc and put a torus round it (a donut the hand came out of). Now an open
  hem: a slim raised cuff band in the cuff colour (or a rolled lip), then a
  lining in shadow that turns in and runs back to the wrist. The pajama
  trousers' ankle cuffs get the same hem. Every outfit that uses `sleeves`
  gets it (pajamas, Night Watch, Moonlight Runner, Starry Sleeper, Raincoat,
  Courier and Scout short sleeves, Hoodie, Owl, Glow Jogger, Cardigan,
  Varsity); the robe's bell sleeves keep their trim.
- **Bob over the ears:** the ears poked through the bob in slivers; the
  bob's shell now bulges over them (`hair_shell(..., bulge=ear_bulge)`).
- Kept as they were (checked in the close-ups, not changed): brows and
  mouth, nose, collar/placket/buttons, nightcap folds, beanie, bunny
  slippers and high-tops, skin and cloth shading. The rounded identity,
  skin tones and outfits are unchanged.

## Portrait cache

`Portraits.key_of` now starts with `Portraits.art_version()`:
`CharacterArt.VERSION` (generated by `build_character.py` with the GLB:
`v7-` + the first 12 hex digits of its SHA-256) plus `Portraits.LOOK_VERSION`
(bump it when the portrait framing, light or the character shader's look
changes). Every framing's key carries it, so a build with new character art
can never reuse a picture of the old one, whatever caches pictures in
future. Queue (24), cache (40 cells) and the one atlas viewport are
unchanged. `test_portraits` checks `CharacterArt` matches the manifest and
the committed GLB's SHA-256 (a rebuilt GLB without its generated version
fails), and that keys carry the version.

## Budgets

Measured from the asset and code by `src/dev/char_budget.tscn` on both
trees (`docs/media/v7/characters/data/budget.json`); LOD0 triangles (Godot
still generates LODs on import).

| | V6 (`d2d0749`) | V7 |
|---|---|---|
| Heaviest look (robe + body + bob + beanie + slippers + freckles, of 6,000 runner looks) | 31,334 | 32,506 (+3.7 %) |
| Default look (pajamas, nightcap, slippers, tuft) | 24,102 | 24,522 (+1.7 %) |
| Swim trunks + swim cap and goggles + flippers | 18,230 | 20,930 |
| Night Watch (with mustache and freckles) | 21,942 | 22,554 |
| `base` (head, face, ears, mittens) | 8,034 | 8,758 |
| `hat_swimcap` (cap + goggles) | 2,048 | 3,576 |
| `body_skin` / `pj` / `watch` | 4,244 / 8,576 / 12,712 | 4,692 / 8,272 / 12,600 |
| All 45 parts in the GLB (only worn ones are drawn) | 210,734 | 216,682 |
| Draw calls, heaviest look | 7 | 7 |
| Draw calls per runner, most parts | 8 | 8 |
| Material variants (shared opaque + two-sided nightcap) | 2 | 2 (the lens is a class inside the shared shader) |
| `runner.glb` | 11.78 MB | 12.12 MB |
| Portrait generation: frames per picture | 3 | 3 |
| Portrait generation: wall time per picture (llvmpipe, load ~30) | 228 / 477 ms | 350 / 421 ms |

The portrait pipeline is unchanged (one job in flight, three frames each,
GPU copy into the bounded atlas, 24-entry queue, 40 cells). Its wall time on
this shared software renderer moved by more between two runs of the same
tree than between trees, so no cost difference is claimed; the frame count
is exact. The heaviest look stays under `test_outfits_v6`'s budget (the
heaviest V6 look may not exceed the heaviest V5 look, both measured from
the current asset). The added triangles are mostly the base's ears,
wrist necks and thumbs (+724) and the goggles (+1,528, only drawn with the
swim cap); hidden caps buried in the forearm and palm were left open to
save 416.

## Tests

- `game/tests/test_characters_v7.gd` (new, 4 tests) on the imported GLB:
  the cap follows the shared head (median offset = cap grow); lenses 4 mm-3.5
  cm off the skin; each frame's base rests on the cap and never sinks into
  the head; two lenses mirrored to 1 mm, on the forehead, 5-11 cm wide;
  the whole goggle mirror-symmetric to 1 mm; every lens face looks out;
  strap and bridge on the cap; strap, clips, frames and bridge close the
  loop round the head (largest gap ≤ 2°); the strap meets both cups; the
  strap stays above the cap's edge; brows under the cap's edge in neutral,
  `brow_up`, `brow_angry`, `face_bright`, `face_sleepy`, `brow_flat`. Run on
  the V6 asset it fails 15 checks (the halo, no strap-to-cup link, brows
  through the cap in every face).
- `test_portraits::test_keys_carry_the_art_version` (new).
- Unchanged and passing: `test_outfits_v6` (including the heaviest-look
  budget and every outfit through the motion scenarios), `test_motion_v6`,
  `test_motion_v5`, `test_motion`, `test_animation`, `test_profile`,
  `test_emotes`, `test_wardrobe`, `test_portraits`.
- `tools/character/clip_check.py`: 0 clips over 1 cm in the head (worst
  0.9 cm, unchanged) or the goggles (0.0 cm everywhere).

## Rebuilding

```sh
python3.11 -m venv tools/.cache/bpyenv && tools/.cache/bpyenv/bin/pip install bpy==4.5.4
tools/character/build.sh        # runner.glb, runner_manifest.json, src/view/character_art.gd
tools/.cache/bpyenv/bin/python tools/character/clip_check.py
tools/gd.sh --headless --path game --import
tools/run_tests.sh characters_v7 && tools/run_tests.sh portraits && tools/run_tests.sh outfits_v6
tools/gd.sh --headless --path game res://src/dev/char_budget.tscn -- --out=budget.json
```

The build is deterministic: rebuilding the committed sources with bpy 4.5.4
gives a byte-identical GLB (checked against `d2d0749` before any change).

## Limits

- No phone: frame cost, heat and feel on device are unmeasured; the
  portrait timings are llvmpipe numbers, useful only before/after.
- The goggles are worn pushed up on the forehead, as designed in V2; there
  is no "over the eyes" variant (it would hide the face).
- One head shape exists; "every face" means the three face presets, three
  brow presets and the expressions (blink, squint, smile, open, brow up,
  angry), all checked.
- Hidden-geometry and intersection checks are in rest pose for head-rigid
  parts (exact for them) and by `clip_check.py` sample points for the arms;
  cloth-on-cloth intersections of the new hems were reviewed in renders
  through the pose sheets, not by an automatic mesh test.
