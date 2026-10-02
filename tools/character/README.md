# Character asset pipeline

`game/assets/characters/runner.glb` is **generated**: it is not hand-edited. The Python files in this folder are the editable source.

```sh
python3.11 -m venv tools/.cache/bpyenv
tools/.cache/bpyenv/bin/pip install bpy==4.5.4     # Blender as a Python module, GPL, build-time only
tools/character/build.sh                            # writes runner.glb + runner_manifest.json (about 10 s)
```

| File | What it holds |
|---|---|
| `geo.py` | Parametric mesh kit: ellipsoids, sweeps, lathes, slabs. Also the vertex-data contract (colour, tint selector, stripe UVs, material class). |
| `rig.py` | Proportions, bone table, skin-weight functions. |
| `parts.py` | Each mesh: base (head, face, hands), hair, body skin, the six outfits, Night Watch uniform with flashlight and mustache, five hats, three shoes. |
| `anims.py` | 32 clips authored as code: FK deltas in armature axes, plus analytic two-bone leg IK for locomotion. |
| `build_character.py` | Builds the armature, meshes, vertex groups and face shape keys. It also bakes the actions and exports the GLB. |

## Conventions

- **Forward.** The character faces Godot −Z at yaw 0, which is the sim's and the camera's forward. In Blender it is built facing +Y. Menu scenes call `CharacterView.face_toward(camera)`.
- **One asset everywhere.** Every role and cosmetic is the same skeleton with mesh parts toggled. `CharacterView` maps the existing cosmetic IDs and the 5-byte network encoding onto parts, so nothing changes in saves or on the wire.
- **Colour path (measured, not assumed).**
  - Blender stores byte colours as sRGB, and the glTF exporter writes `COLOR_0` as linear: sRGB 0.5 becomes 0.216.
  - Godot keeps those linear values, quantised to 8 bits.
  - So `character.gdshader` uses `COLOR.rgb` directly, with no `srgb_to_linear`.
  - glTF flips V, so the shader reads `1 - UV.y` and `1 - UV2.y`.
  - World meshes built in code (`MeshKit`) store sRGB vertex colours and convert in `world_common`.
- **Locomotion clips.**
  - `walk`, `run` and `sprint` are each one 1.0 s cycle that starts with the left foot at mid-stance.
  - `LOCO[*].speed` is the metres travelled per cycle. `CharacterView` plays the blend at `ground speed / speed`, so planted feet move at ground speed and do not slide.
  - Planted-foot sweep is `speed × duty`. It must stay reachable for the 0.44 m legs; otherwise the IK clamps and the foot slides. The current values are chosen for that.
- **Face.**
  - Shape keys on `base`: `blink`, `squint`, `smile`, `open`, `brow_up`, `brow_angry`.
  - The neutral mouth (a closed smile) is baked into the basis.
- **Budgets.**
  - A typical outfit (base + pajamas + nightcap + slippers) is about 23k triangles at LOD0 (V3: 19.7k). Godot generates LODs on import.
  - Each visible part is one draw call with one shared `ShaderMaterial`; per-character colours are instance uniforms. Parts listed in `CharacterView.TWO_SIDED` (the nightcap) use a second, double-sided material with the same shader body (`character.gdshaderinc`).
- **Checking changes.** `src/dev/character_lineup.tscn -- --lineup=parts` renders 12 fixed close-ups (nightcap, collar, cuff and hand, robe hem, each shoe, hair edges, Night Watch cap); `--parts-debug` hides the head to inspect the cap alone. Render it before and after a change and compare.
  - Distant characters advance their AnimationTree at a third of the rate.
