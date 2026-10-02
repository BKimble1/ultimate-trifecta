# V5 campus art notes

The V5 campus pass answers the owner's complaint that Moonbrook College looked
dull next to polished mobile party games: repetitive stacked cones, plain
lawns and paths, sparse props and hard blue shadows. It changes **how the
campus looks** and nothing about how it plays. Every collider, both
navigation grids and all gameplay data (waters, exits, jump points, pads,
spawns, doors) hash to the same values as V4 (`dcebf4e`). The proof is in
[Collision and navigation safety](#collision-and-navigation-safety).

**What these notes can and cannot claim.** Every image and number here comes
from a desktop Linux machine running Godot 4.7.2's **Mobile renderer** on Mesa
**llvmpipe** (software Vulkan) under Xvfb, or headless. The machine was shared
with other jobs (load average 3 to 10), so absolute timings are noisy. V4 and
V5 were measured back to back under the same conditions. None of this says
how fast or smooth the game is on an iPhone, and no device was available.

Evidence: [media/v5/campus/](../media/v5/campus/README.md) has matched
before/after renders and side-by-side comparisons for the 7 route views, the
6 water views, the 10 overview views and 10 new landmark views, plus the
route in Battery Saver.

## Art direction

**A moonlit storybook campus.** The palette is cool blue-green moonlight on
rounded, chunky shapes, with warm amber pools at doors, lamps and windows. A
few saturated accents mark places: autumn maples on the quad, blossom trees
at the dorm and Lily Basin, white birches in the pond woods, and each water's
own lantern colour when it is a target. Silhouettes are soft and
cloud-like. Small detail comes from low-contrast patterns (lawn, flagstone,
brick, shingle) instead of extra polygons. Wayfinding uses the world itself:
a lamp style per area, fingerposts and name boards with the fictional names,
and lit entrances.

## What changed

| Area | V4 | V5 |
|---|---|---|
| Trees | Procedural lobes and stacked 9-sided cones; 2 broadleaf and 2 pine variants; the pond woods all pines | 8 species authored in Blender (oak, linden, autumn maple, birch, blossom, fir, spruce, stout pine). Each has 3 LODs (near ~800–1000, mid ~250–310 and far ~70 triangles) and baked vertex AO, trunks with root flare and branches into the crown, and puffy layered conifers. Species follow groves rather than a uniform mix: conifer stands, birch glades and mixed oaks in the pond woods, linden avenues on the College Loop, maples on the quad, blossom at the dorm and Lily Basin. Per-tree tint and scale. Collider trees keep their exact place; only the look changes. |
| Understory and dressing | Some rocks and hedge blobs | ~3,900 baked pieces: understory shrubs at trunks, foundation shrubs and blooms along buildings, reed beds and lilies at the natural banks, flat stones, grass tufts beside paths and at lamp, hedge and wall feet, 28 deliberate meadow drifts in open lawns, and a forest beyond the boundary hedges and across the lake. All of it is visual only and kept out of corridors (see below). |
| Ground and paths | One colour per 2 m quad and plain ribbons | Lawn detail plus broad dry and lush patches, and mowing stripes on the formal lawns. Darker moss-and-needle forest floor under the groves, worn grass beside paths, sandy pebbly banks at the natural waters. Flagstone, gravel and boardwalk paths have a **ragged lawn verge** instead of a hard edge. The fountain plaza is a paved rosette. Roads have raised kerbs. |
| Buildings | Framed flat windows, gable roofs | A shared modular kit. Brick or plaster walls on a dressed-stone plinth with quoins and a cornice. Recessed windows with varied lit interiors (warm lamp, cooler screen glow, curtains part-drawn) and stone lintels and sills. Roofs have thickness, fascia, a ridge cap, bargeboards and chimneys. Entrances have lit doors, transoms, wall lanterns, porch roofs on brackets and a step. The library has fluted columns, the tower an arch soffit, string courses and a flared copper spire. The boathouse has boat doors facing the inlet. |
| Props and wayfinding | Lamps, benches, a few props | Three lamp styles as cues: twin globes at the fountain and dorm, cast iron elsewhere, timber post lanterns on the gravel trails. Name boards with the fictional names (Puddlesworth Hall and the rest), six fingerposts at the main junctions, bike-rack hoops, a noticeboard with notices, a frog statue on a rock, a gazebo lantern. |
| Waters | Rim and rings | See [Water landmarks](#water-landmarks). |
| Lighting | Vertex-baked AO and warm light, blue ambient, hard shadows | The light field moved to the GPU (see below). Hemisphere fill and leaf translucency, softer moon shadows (opacity 0.5, blur 2.2), slightly less saturated ambient, a warm horizon glow and moon halo in the sky, restrained fog in the horizon's colour. |

### Water landmarks

Objective markers are new. Each water mesh carries a ring of **floating
lanterns** in its target colour. The water shader collapses them unless the
water is an active objective, bobs them gently, and dims them once the player
has stamped it. The old neon ring is now a slim, soft edge glow. A
decorative water therefore never looks like a target, and the lanterns cost
no extra draw call. MatchController drives the existing `active` and
`stamped` parameters unchanged.

- **Founders' Fountain**: a turned basin with a rolled lip and plinth step, and a two-tier pedestal and bowls matching the 1.3 m collider. Four arcing jets and a plume use a flowing-water material, ripple rings spread where the jets land, a warm up-light glows around it, and the plaza is a paved rosette.
- **Froggy Pond**: a wet-earth lip and sandy bank, with reed beds, lilies with flowers and flat stones in groups. Stepping stones mark each exit, flush with the ground. The frog sits on a mossy rock beside a name board, under a mixed grove.
- **Splashdown Pool**: tiled coping, deck and blue tiled inner walls. Lane lines and wall lights show in the water. Lane ropes, a diving board and the lifeguard chair.
- **Old Quarry Lagoon**: every boulder collider is drawn with the kit's layered rock, fitted to its box. A wet stone shelf at the waterline, scattered stones, work lanterns at the three gaps, a name board and darker violet water.
- **Lily Basin**: carved coping over the 0.45 m rim, corner urns with clipped topiary, flower boxes moved off the exits (in V4 one sat on an exit), lilies, blooms along the inner hedge feet and blossom trees around.
- **Boathouse Inlet**: a plank dock with stringers, pilings and cleats; the deck stays clear to run and jump. Bank boards, reeds in the corners, the boathouse's boat doors and lantern, and dock lanterns.

## Light field: improved bake, moved to the GPU (no LightmapGI)

V4 baked a 2 m grid of AO and warm light into vertex colours on the CPU, the
heaviest part of its build steps. V5 keeps the field and extends it:

- **Channels**: AO, warm light from lamps, doors and windows, and cool light from the pool and fountain. Canopy and path-wear grids feed the ground colours.
- **Contact shade**: every shrub and boulder adds a soft contact AO patch.
- **Sampling**: the field is uploaded as a 161×151 RGBA8 texture (~95 KB) that the world shaders sample per fragment. No vertex is baked on the CPU, the field is smooth per pixel, and the MultiMesh vegetation (trunk feet, shrubs) is lit by it too.

**Why not LightmapGI?** The campus is generated at runtime from
CampusLayout. Baked lightmaps would need UV2 unwraps of generated chunk meshes,
an offline bake of meshes the game no longer generates, and several MB of
lightmap textures. Mobile would also pay for another sampled texture set.
At night the scene is one moon (a dynamic directional shadow) plus small
warm sources, and a soft field captures that well. No SDFGI, VoxelGI, SSAO,
SSR, volumetric fog, TAA or ray tracing is used.

## Materials and shaders (Mobile renderer)

- **`world_common.gdshaderinc`**: every vertex carries a material id in UV.x, so one opaque material per chunk covers everything. The id selects:
  - a world-space detail pattern from two 512² tileable RGBA masks (`campus_detail_a/b.png`, ASTC/BPTC, mipmapped, ~340 KB each in VRAM), generated by numpy;
  - a derivative-based bump (no tangents);
  - a roughness and specular pair, so metal, glass, roof slate and leaves get refined highlights and lawns stay matte.

  Pattern contrast fades out by 140 m. Colours are converted from sRGB in the shader, as in V4. Battery Saver halves detail and bump (`detail_level`).
- **`water.gdshader`**: slow ripples, a fake sky reflection by fresnel, a moon glitter path, restrained shore foam, pool lanes and lights, fountain rings and the lantern markers. It stays opaque, with no screen reads.
- **`night_sky.gdshader`**: a warm horizon band toward the lake and a moon halo.
- **No transparency added for foliage.** Leaves are opaque meshes, the canopy keeps V4's parting and cut-away, and the new dressing uses the same canopy material.

## Draw cost

- **Trees** are drawn as one MultiMesh per 64×60 m chunk and species, with at most two species per chunk (a rare species is drawn as the commonest of its family). The kit's authored LODs are packed into Godot's **native mesh LOD**.
  - LOD keys are measured on 4.7.2: ~520 m per key unit at a 720 px render height. They are scaled by 720 / render height, so LOD 1 starts at ~30 m and LOD 2 at ~90 m on any screen.
  - LOD is chosen per batch from its nearest point, so the batch around the camera is always at full detail.
  - Trees cast through **low-poly shadow proxies**: the far LOD, one batch per family per 128 m region (Standard only).
- **Dressing** is one MultiMesh per 128×120 m region and kind. Tufts, flowers, reeds and lilies end through an empty last LOD (36–70 m), and far batches stop by visibility range. Dressing never casts shadows; its contact shade is in the light field.
- **Chunks**: ground is an indexed grid section per chunk (about a quarter of V4's ground vertices). The near-field detail meshes (lamps, bollards, frames) no longer cast shadows.

## Budgets (llvmpipe, 1558×720, desktop test machine; relative only)

Engine counters per view (`dev_shots.gd` STATS lines: draw calls and visible
primitives across all passes, shadows included). V4 is `dcebf4e` rendered with
the same tool and cameras.

**Standard (quality 1)**

| View | V4 draws | V5 draws | V4 prims | V5 prims | V5/V4 prims |
|---|---|---|---|---|---|
| route_1_dorm_door | 86 | 94 | 239,221 | 245,181 | 1.02 |
| route_2_quad_path | 74 | 72 | 258,742 | 188,123 | 0.73 |
| route_3_pond | 51 | 47 | 232,850 | 138,001 | 0.59 |
| route_4_trees | 60 | 58 | 234,824 | 169,168 | 0.72 |
| route_5_garden | 44 | 43 | 120,344 | 87,799 | 0.73 |
| route_6_fountain | 81 | 80 | 245,425 | 232,002 | 0.95 |
| route_7_return | 70 | 62 | 205,163 | 170,127 | 0.83 |
| water_1_fountain | 88 | 83 | 242,689 | 221,786 | 0.91 |
| water_2_pond | 41 | 44 | 209,812 | 110,402 | 0.53 |
| water_3_pool | 41 | 42 | 114,462 | 102,541 | 0.90 |
| water_4_quarry | 40 | 34 | 133,964 | 99,872 | 0.75 |
| water_5_garden | 40 | 35 | 115,519 | 78,932 | 0.68 |
| water_6_inlet | 32 | 31 | 103,751 | 90,011 | 0.87 |

**Battery Saver (quality 0)**: lighter than Standard everywhere. Against V4's
Battery Saver, primitives are mostly lower and draw calls slightly higher.

| View | V4 draws | V5 draws | V4 prims | V5 prims |
|---|---|---|---|---|
| route_1_dorm_door | 46 | 54 | 116,842 | 137,435 |
| route_2_quad_path | 36 | 43 | 100,805 | 82,020 |
| route_3_pond | 23 | 32 | 77,028 | 59,025 |
| route_4_trees | 34 | 36 | 92,562 | 83,088 |
| route_5_garden | 22 | 31 | 45,331 | 37,828 |
| route_6_fountain | 41 | 48 | 90,547 | 97,324 |
| route_7_return | 38 | 37 | 78,099 | 73,954 |
| water_1_fountain | 45 | 48 | 100,549 | 105,731 |
| water_2_pond | 20 | 32 | 75,688 | 42,210 |
| water_3_pool | 26 | 27 | 48,150 | 52,826 |
| water_4_quarry | 19 | 23 | 41,343 | 31,032 |
| water_5_garden | 20 | 25 | 37,453 | 31,372 |
| water_6_inlet | 16 | 20 | 36,168 | 34,829 |

The overview and landmark views are in the STATS lines of the evidence
README. On a phone the LOD keys are scaled to the device's render height, so
LOD distances match these renders. The counters say nothing about GPU time.

**Campus preparation steps** (staged build, `CampusBuilder.begin_visuals` /
`step`, once per session, kept between rounds as before):

| Measurement | V4 | V5 | How |
|---|---|---|---|
| Longest single step, rendering (llvmpipe) | 81.4 / 83.4 ms | 37.1 / 30.3 ms: first-use shader compiles (foliage, world, water: one step each) | `dev_shots --route` BUILD/SLOWEST lines, two back-to-back runs each |
| Longest non-shader step, rendering | (not separable in V4) | 13.1 / 13.9 ms (a ground chunk) | same |
| Steps over 16 ms, rendering | 18 / 22 of 126 | 3 (the shader compiles) | same |
| Total campus build work, rendering | 872 / 848 ms | 799 / 799 ms | same |
| Longest campus step, headless | (not measured per step) | 14.5 ms (paths); then bollards, Lily Basin and the horizon at ~11 ms | `test_campus_art` in the full test run (prints the slowest steps) |
| Longest frame of round preparation, headless `test_loading` (9 ms budget per frame; includes non-campus jobs: characters, HUD) | 62.0 / 77.0 ms | 23.9 / 22.1 ms | `test_loading` output (V4 on `dcebf4e`, V5 in the full test run) |

What made the steps short:

- No CPU light bake (now on the GPU).
- Ground per chunk as an indexed grid.
- Chunk meshes packed on the worker thread pool.
- Hot MeshKit paths inlined, with no per-triangle callables.
- One step per building, per window face, per fence, per hedge stretch, per two paths and per ten lamps.
- Trees, shrubs and rocks precomputed offline in Blender, and the dressing list baked offline.

Shader compilation stays on the main thread: compiling on the worker pool
deadlocked the renderer here. It is one step per shader so that no other
work shares those frames, and V4 compiled the same shaders inside its
longest step.

**Memory (assets added)**:

- `campus_kit.res`: 40 meshes, 12.6k triangles in total, 0.23 MB on disk.
- `campus_dressing.res`: 0.1 MB.
- Two detail textures: ~0.34 MB each in VRAM, compressed with mipmaps.
- The light field texture: ~95 KB.
- MultiMesh buffers for ~4.2k instances: ~0.3 MB.

Ground vertex memory fell (indexed). Chunk meshes gained one UV channel (8
bytes per vertex).

## Collision and navigation safety

- `CampusFingerprint` (game/src/map) hashes the authoritative state:
  - every collision shape that `CampusBuilder.build_collision` makes: body, layer and mask, shape type, dimensions (including a hash of the height-field data) and transform;
  - every cell of both `NavGrid` grids: solid flags, weight scales and low-wall cells;
  - the gameplay layout lists.

  The V4 values were computed on a pristine checkout of `dcebf4e`: 525 shapes, collision `15d3dc7a…`, nav `79361473…`, layout `803fc8ac…`. `test_campus_art` asserts V5 matches them all.
- `campus_layout.gd`, `nav_grid.gd` and `build_collision` are untouched (`git diff dcebf4e` shows no change). The decorative tree species are chosen in `CampusKit.species_of` from positions only.
- The visual build adds **no** collision objects (tested).
- **Dressing safety** (tested against the baked list):
  - nothing stands on a path, road or plaza, or near a water exit (3.2 m), jump point (2.6 m), pad, spawn, gadget spot, dorm door, bollard gate, lamp or bench;
  - every shrub, reed bed or boulder hugs an existing obstacle: within 0.55 m of a building, hedge, wall, fence, trunk or boulder collider, or on a bank;
  - the forest stays beyond the hedges;
  - no mid-height piece lies within 0.35 m of the bots' real routes (NavGrid paths from the dorm to every exit of every water and back, 40+ routes), or on the swim lines from each exit to the water's centre.
- Bots, routes and camping: collision and nav are byte-identical, so `test_routes_bots` and `test_camping` run on the same world (they pass; see below).

## Asset pipeline (regeneration)

```
tools/campus/build.sh            # everything (Blender bpy + numpy + Godot)
tools/campus/build.sh tree_fir   # only meshes whose name starts with ...
```

The steps, in order:

1. `tools/campus/build_kit.py` (Blender 4.5 as a Python module) writes `art_src/campus/raw/*.utm` and `manifest.json`. These are raw mesh dumps, kept so the import can be redone without Blender.
2. `tools/campus/make_textures.py` writes `game/assets/campus/campus_detail_a/b.png`.
3. `tools/campus/import_kit.gd` (Godot, headless) writes `game/assets/campus/campus_kit.res`, a MeshLibrary.
4. `tools/campus/bake_dressing.gd` writes `game/assets/campus/campus_dressing.res`. `test_campus_art` fails if this is stale.

Iterating:

- **Kit lineup render**: `dev_shots.tscn -- OUT --kit`.
- **Per-view stats**: `--count` prints a per-kind tally of what is drawn.

See `tools/campus/README.md`.

## Tests

The full suite passed on the final code: **167 tests, 2895 checks, 0
failures** in 286 s, against a V4 baseline of 159 tests and 2742 checks. That
includes `test_routes_bots`, `test_camping` and `test_loading`. The new
`test_campus_art` adds 8 tests:

- collision, nav and layout unchanged from V4;
- the visual build adds no physics;
- the dressing is fresh;
- corridors and exits stay clear;
- bot routes and swim lines stay clear;
- staged steps are short;
- kit LODs and textures load;
- Battery Saver is lighter.

## Limits

- **No device measurement.** Draw calls and primitives are llvmpipe engine counters; GPU time, thermal behaviour and frame pacing on an iPhone are unknown.
- **Battery Saver draw calls** are a few above V4's Battery Saver (+0 to +12), though primitives are mostly lower.
- **route_1 in Standard** draws 94 calls against V4's 86.
- **First-use shader compiles** are the longest preparation steps (~26–37 ms each here, one per shader).
- **Decoration has no collision.** A cart scraping a wall can pass through a foundation shrub; runners never meet one in open ground.
- **Some lawn stays open.** Gameplay sightlines and the fixed collider trees limit how much it could be filled; it is broken up by patterns, patches, mowing stripes, tufts and meadow drifts rather than new objects.
- **Collider trees did not move.** Groves and clearings are expressed by species, scale and understory, not new tree positions.
- **Label3D signs** draw one call each when within 32–45 m.
