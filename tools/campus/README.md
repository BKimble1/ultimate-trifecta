# Campus tools

Two pipelines live here:

1. **Campus data** (the reference-campus rebuild): the layer data in
   `game/data/campus/*.json` is traced over a public-domain 2022 orthophoto
   into `tools/campus/traced/<zone>.json` and merged by `build_data.py`.
   The schema is `docs/campus/DATA_SCHEMA.md`. The reference pack (photos,
   maps, the atlas) stays outside the repository; set `CAMPUS_REF` to its
   folder for the raster tools.
2. **Art kit**: original, procedural vegetation and rock meshes. No
   third-party art, scans or asset packs are used. Everything is generated
   from the parameters in these scripts.

## Campus data

| Script | Does |
|---|---|
| `geo.py` | The metric frame: EPSG:26916 (UTM 16N), x = E - 627300, z = 4479400 - N (+x east, +z south). Raster helpers. |
| `tile.py` | Renders an aerial tile with a labelled metre grid (`--src` draws traced data on top). |
| `overlay.py` | Draws whole layers over the aerial for checking. |
| `georef.py` | Fits (least squares affine) and warps newer plans/diagrams onto the frame. |
| `build_data.py` | Validates the traced zones (ids, kinds, polygons, evidence, a private real-name screen) and writes `game/data/campus/<layer>.json`. `--check` validates only. Two merge rules run first (below). |
| `make_gameplay.py` | Writes `game/data/campus/gameplay.json` from the merged layers and the hand-written `gameplay_spec.json` (below). `--check` prints only. |
| `registers.py` | Writes the evidence, change and neutral-name registers in `docs/campus/` from the merged data, screened against the private deny list. |
| `scan_shipping.py` | Acceptance gate 8: scans everything that ships (game/, the export filters) for real names, branding and reference imagery. |

### Merge rules (`build_data.py`)

The zones were traced separately, layer by layer. Two conflicts between
layers are resolved at merge time, and each changed item says so in its
evidence (`ev.open`):

- **Gates.** Where a traced walk or road crosses a fence, hedge, rail or low
  wall at more than 25°, the barrier gets a gap as wide as the walk plus
  0.8 m. A real walk through a fence line passes a gate. Construction fences
  and retaining walls stay closed.
- **Off the walk.** A tree trunk or a prop (bench, table, planter, sign, bike
  rack, lamp, pole, bin) whose traced spot falls on a walk moves straight out
  to the walk's edge. Crowns and pole shadows place them a little off. If
  that would land it on another walk, it stays where it was (and the count is
  printed).

### The gameplay layer (`make_gameplay.py`)

`gameplay_spec.json` holds the design decisions: the two start halls (each
one's open interior, its doors at the building's real entrances, furniture),
the objective pool (which six real waters stand in for the game's six slots,
with names, colours and icons), where the Night Watch starts, and the
landmark labels. The script computes the rest from the place:

- **Play boundary.** Every campus feature grown by 30 m, merged, closed back
  in by 18 m and simplified.
- **Coin candidates.** Spread along the walks at least 26 m apart, clear of
  buildings, water, trunks and doors, and 6 m from every water's exits.
- **Gadget spots.** Farthest-point order over walks and plazas.
- **Night Watch and cart spawns.**

It refuses an objective water that is missing from the data or lies outside
the play area.

## Art kit

| Script | Runs in | Writes |
|---|---|---|
| `build_kit.py` | Blender 4.5 as a Python module (`bpy`) | `art_src/campus/raw/<mesh>.utm` + `manifest.json` |
| `make_textures.py` | python3 + numpy + Pillow | `game/assets/campus/campus_detail_a.png`, `campus_detail_b.png` |
| `import_kit.gd` | Godot 4.7.2, headless | `game/assets/campus/campus_kit.res` (MeshLibrary) |
| `build.sh` | all of the above, in order | |

```
tools/campus/build.sh              # rebuild everything
tools/campus/build.sh tree_oak     # only meshes whose name starts with tree_oak
BPY_PYTHON=/path/to/python tools/campus/build.sh   # another bpy install
```

## build_kit.py: what it makes

- **Trees**, 8 species × 3 LODs (`tree_<species>_<lod>`): oak, linden, maple, birch, blossom, fir, spruce, pine.
  - Broadleaf crowns are metaball clouds: a soft core plus leaf clusters over the upper ellipsoid. Conifers are puffy skirts (rings of overlapping balls) with an attached rounded tip.
  - The crowns are polygonised and decimated to fixed budgets: about 800–1000 / 250–310 / 70 triangles.
  - Trunks are tubes with a root flare and branches into the crown.
- **Shrubs** (round, tall, blooming × 2 LODs), **grass tuft**, **flower clump**, **reeds** with cattails, **lilies**, and **rocks** (round boulder, layered ledge rock, flat stone × 2 LODs).
- **Vertex colours** carry the look: a species palette, sky-facing gradients, cluster hue drift, ambient occlusion ray-cast against the asset and the ground (Blender BVH), and birch bark bands.
- **Petals** have material id 13, and the shader tints them per instance.
- **Vertex layout**: position, normal, sRGB colour, UV = (material id, parameter) and CUSTOM0 = (emission, sway). This is the same layout as the runtime `MeshKit` meshes, so one shader family draws everything (`game/assets/shaders/world_common.gdshaderinc` lists the ids).
- **Scale**: trees are authored 8 m tall and scaled per instance to the layout's tree height. Rocks are normalised to a unit box and scaled to each collider box.

## At runtime

- `CampusKit.load_kit()` loads the MeshLibrary.
- `CampusKit.lod_mesh(base)` packs `base_0/1/2` into one ArrayMesh with native mesh LODs. The keys are scaled to the render height so LOD distances are the same on every screen.
- `CampusBuilder` places the kit as chunked MultiMeshes.
- Shrubs and trees come from the traced vegetation layer (`trees.json`); there is no random dressing pass.

## Iterating

```
xvfb-run -a -s "-screen 0 1700x800x24" tools/gd.sh --path game --resolution 1558x720 \
  res://src/dev_shots.tscn -- /tmp/out --kit        # lineup of every kit mesh and LOD
... res://src/dev_shots.tscn -- /tmp/out --route     # the follow-camera route views
... res://src/dev_shots.tscn -- /tmp/out --heroes --runner --count
```
