# Campus art kit (V5)

Original, procedural assets for Moonbrook College. No third-party art,
scans or asset packs are used. Everything here is generated from the
parameters in these scripts.

| Script | Runs in | Writes |
|---|---|---|
| `build_kit.py` | Blender 4.5 as a Python module (`bpy`) | `art_src/campus/raw/<mesh>.utm` + `manifest.json` |
| `make_textures.py` | python3 + numpy + Pillow | `game/assets/campus/campus_detail_a.png`, `campus_detail_b.png` |
| `import_kit.gd` | Godot 4.7.2, headless | `game/assets/campus/campus_kit.res` (MeshLibrary) |
| `bake_dressing.gd` | Godot 4.7.2, headless | `game/assets/campus/campus_dressing.res` |
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
- `CampusDressing` holds the decorative placement rules (corridor clearances, obstacle hugging). They run offline in `bake_dressing.gd`, and `test_campus_art` checks the result.

## Iterating

```
xvfb-run -a -s "-screen 0 1700x800x24" tools/gd.sh --path game --resolution 1558x720 \
  res://src/dev_shots.tscn -- /tmp/out --kit        # lineup of every kit mesh and LOD
... res://src/dev_shots.tscn -- /tmp/out --route     # the follow-camera route views
... res://src/dev_shots.tscn -- /tmp/out --heroes --runner --count
```
